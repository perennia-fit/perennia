import { createRoute, z } from "@hono/zod-openapi";
import { and, asc, eq } from "drizzle-orm";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import {
  AgentNutrientAmountSchema,
  AgentNutrientValidationIssueSchema,
  AgentNutrientValidationLimitsSchema,
  validateAgentFoodEntry,
  type AgentNutrientValidationIssue
} from "./agent-validation.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";
import {
  FOOD_ENTRIES_SYNC_ENTITY,
  MEALS_SYNC_ENTITY,
  pushFoodEntriesInTransaction,
  pushMealsInTransaction,
  type SyncPushChange
} from "./sync.js";

export const AGENT_MEAL_BATCH_WRITE_MAX_ENTRIES = 100;

const ISO8601StringSchema = z.string().min(1).openapi({
  description: "ISO-8601 timestamp."
});

const MealTypeSchema = z.string().trim().min(1).openapi({
  description:
    "Meal Type (eating-occasion label, e.g. Breakfast/Lunch/Dinner/Snack)."
});

const PortionUnitSchema = z
  .enum(["gram", "milliliter", "ounce", "fluidOunce", "serving", "package"])
  .openapi("AgentMealPortionUnit");

const FoodSourceSchema = z
  .enum(["usda", "openFoodFacts", "user"])
  .openapi("AgentMealFoodSource");

export const AgentMealBatchWriteMealSchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "Client-supplied UUIDv7 Meal id."
    }),
    mealType: MealTypeSchema,
    startedAt: ISO8601StringSchema.openapi({
      description: "Meal start instant in UTC."
    }),
    endedAt: ISO8601StringSchema.nullable().default(null).openapi({
      description: "Meal end instant in UTC, or null while still open."
    }),
    timezone: z.string().min(1).openapi({
      description: "IANA timezone captured at Meal creation."
    }),
    localDate: z.string().min(1).openapi({
      description:
        "Nutrition Day date (YYYY-MM-DD) the Meal falls on in its local timezone."
    }),
    deletedAt: ISO8601StringSchema.nullable().default(null).openapi({
      description:
        "Nullable archive tombstone. Setting it is an ordinary LWW write of a tombstone, the same archive semantics the app's own delete affordance produces — never a purge."
    })
  })
  .openapi("AgentMealBatchWriteMeal");

const AgentMealBatchWritePortionSchema = z
  .object({
    value: z.number().positive().openapi({
      description: "Logged Portion magnitude as entered."
    }),
    entered: z.string().trim().min(1).openapi({
      description: "Raw user/agent-entered Portion magnitude."
    }),
    unit: PortionUnitSchema
  })
  .openapi("AgentMealBatchWritePortion");

const AgentMealNutrientVectorSchema = z
  .record(z.string().min(1), AgentNutrientAmountSchema)
  .openapi({
    description:
      "Self-describing nutrient vector keyed by fixed nutrient id. For a reference Food this is the per-100 g/ml vector; for a Quick Entry it is the directly entered amounts for the whole entry. Unknown nutrients stay unknown and are never coerced to zero."
  });

export const AgentMealBatchWriteEntrySchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "Client-supplied UUIDv7 Food Entry row id."
    }),
    position: z.number().int().min(0).openapi({
      description: "Zero-based Food Entry order inside the Meal."
    }),
    name: z.string().trim().min(1).optional().openapi({
      description:
        "Display name snapshotted at log time. Optional for a reference Food entry — the server resolves it (and the fields below) from the Food when omitted; required for a Quick Entry."
    }),
    nutrients: AgentMealNutrientVectorSchema.optional().openapi({
      description:
        "Per-100 nutrient vector for a reference Food, or the whole-entry vector for a Quick Entry. Optional for a reference Food entry — the server resolves it from the Food when omitted; required for a Quick Entry."
    }),
    isLiquid: z.boolean().optional().openapi({
      description:
        "Whether the food is logged by volume (ml) rather than weight (g). Optional for a reference Food entry — resolved from the Food when omitted; required for a Quick Entry."
    }),
    foodId: z.string().min(1).nullable().default(null).openapi({
      description:
        "Reference Food id for a catalogue entry, or null for a Quick Entry."
    }),
    foodSource: FoodSourceSchema.nullable().default(null).openapi({
      description:
        "Where the food facts came from (usda/openFoodFacts/user). Null for a Quick Entry. Orthogonal to Provenance. When foodSource is user and name/nutrients/isLiquid are omitted, the server resolves the snapshot from the caller's own Food library."
    }),
    portion: AgentMealBatchWritePortionSchema.nullable().default(null).openapi({
      description:
        "Semantic Portion for a reference Food entry. Null for a Quick Entry (the nutrient vector already describes the whole entry)."
    }),
    servingLabel: z.string().trim().min(1).nullable().optional().openapi({
      description:
        "Snapshotted serving label (e.g. 'slice'), if any. Resolved from the Food when omitted on a reference Food entry."
    }),
    servingSize: z.number().positive().nullable().optional().openapi({
      description:
        "Snapshotted serving size in g/ml, if any. Resolved from the Food when omitted on a reference Food entry."
    }),
    packageSize: z.number().positive().nullable().optional().openapi({
      description:
        "Snapshotted package size in g/ml, if any. Resolved from the Food when omitted on a reference Food entry."
    }),
    updatedAt: ISO8601StringSchema.optional().openapi({
      description:
        "Client-observed row update clock. Defaults to the server receive time when omitted."
    }),
    deletedAt: ISO8601StringSchema.nullable().default(null).openapi({
      description:
        "Nullable archive tombstone. Setting it is an ordinary LWW write of a tombstone, the same archive semantics the app's own delete affordance produces — never a purge."
    })
  })
  .openapi("AgentMealBatchWriteEntry");

export const AgentMealBatchWriteRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200).openapi({
      description:
        "Stable key for this agent request. Replays with the same key return the original result without appending another Activity Log batch."
    }),
    meal: AgentMealBatchWriteMealSchema,
    entries: z
      .array(AgentMealBatchWriteEntrySchema)
      .min(1)
      .max(AGENT_MEAL_BATCH_WRITE_MAX_ENTRIES)
      .openapi({
        description:
          "Food Entries to apply atomically as one Activity Log batch."
      })
  })
  .openapi("AgentMealBatchWriteRequest");

export const AgentMealBatchWriteIssueSchema = AgentNutrientValidationIssueSchema
  .extend({
    itemIndex: z.number().int().min(0).openapi({
      description: "Index of the Food Entry item that produced the issue."
    }),
    entryId: z.string().min(1).openapi({
      description: "Client-supplied Food Entry id for the failed item."
    })
  })
  .openapi("AgentMealBatchWriteIssue");

export const AgentMealBatchWriteEntryResultSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1),
    kind: z.enum(["food", "quickEntry"]),
    warnings: z.array(AgentNutrientValidationIssueSchema)
  })
  .openapi("AgentMealBatchWriteEntryResult");

export const AgentMealBatchWriteResponseSchema = z
  .object({
    accepted: z.literal(true),
    duplicate: z.boolean().openapi({
      description:
        "True when the idempotency key had already been applied and no new rows or Activity Log entries were written."
    }),
    idempotencyKey: z.string().min(1),
    batchId: z.string().min(1).openapi({
      description: "Activity Log batch id. Equal to the idempotency key."
    }),
    mealId: z.string().min(1),
    serverClock: z.string().min(1),
    entries: z.array(AgentMealBatchWriteEntryResultSchema)
  })
  .openapi("AgentMealBatchWriteResponse");

export const AgentMealBatchWriteErrorResponseSchema = z
  .object({
    code: z.literal("agent_meal_batch_write_failed"),
    message: z.string().min(1),
    errors: z.array(AgentMealBatchWriteIssueSchema),
    warnings: z.array(AgentMealBatchWriteIssueSchema),
    limits: AgentNutrientValidationLimitsSchema
  })
  .openapi("AgentMealBatchWriteErrorResponse");

export const AgentMealBatchWriteUnavailableResponseSchema = z
  .object({
    code: z.literal("agent_meal_batch_write_unavailable"),
    message: z.string().min(1)
  })
  .openapi("AgentMealBatchWriteUnavailableResponse");

export const agentMealBatchWriteRoute = createRoute({
  method: "post",
  path: "/agent/meals/batch-write",
  operationId: "batchWriteAgentMeal",
  tags: ["Agent Writes"],
  summary: "Batch-write a Meal with Food Entries as one Activity Log batch.",
  description:
    "Authenticated agent write path for nutrition. Snapshots a self-describing Food Entry per item (nutrient vector, name, Food Source, serving/package, isLiquid) plus the semantic Portion, validates every item with the shared two-tier nutrient validation module, applies the request atomically, and records one Activity Log batch. No nutrition totals are stored; energy and macros are derived on read. Purge and hard-delete are intentionally absent.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: AgentMealBatchWriteRequestSchema
        }
      }
    }
  },
  responses: {
    200: {
      description:
        "The batch was accepted, or recognized as an idempotent replay.",
      content: {
        "application/json": {
          schema: AgentMealBatchWriteResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid agent API key.",
      content: {
        "application/json": {
          schema: AgentUnauthorizedResponseSchema
        }
      }
    },
    422: {
      description:
        "One or more items failed hard validation; no rows were written.",
      content: {
        "application/json": {
          schema: AgentMealBatchWriteErrorResponseSchema
        }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key or write storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentMealBatchWriteUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export type AgentMealBatchWriteRequest = z.infer<
  typeof AgentMealBatchWriteRequestSchema
>;
export type AgentMealBatchWriteEntry = z.infer<
  typeof AgentMealBatchWriteEntrySchema
>;
export type AgentMealBatchWriteIssue = z.infer<
  typeof AgentMealBatchWriteIssueSchema
>;
export type AgentMealBatchWriteEntryResult = z.infer<
  typeof AgentMealBatchWriteEntryResultSchema
>;
export type AgentMealBatchPreparedRow = {
  id: string;
  updatedAt: string;
  deletedAt: string | null;
  payload: Record<string, unknown>;
};
export type AgentMealBatchPreparation =
  | {
      accepted: true;
      meal: AgentMealBatchPreparedRow;
      entries: AgentMealBatchPreparedRow[];
      responseEntries: AgentMealBatchWriteEntryResult[];
    }
  | {
      accepted: false;
      errors: AgentMealBatchWriteIssue[];
      warnings: AgentMealBatchWriteIssue[];
    };
export type AgentMealBatchWriteStore = {
  writeMealBatch(input: {
    userId: string;
    batchId: string;
    correlationId?: string;
    deviceId: string;
    meal: AgentMealBatchPreparedRow;
    entries: AgentMealBatchPreparedRow[];
  }): Promise<{
    duplicate: boolean;
    serverClock: string;
    applied: { id: string; updatedAt: string; deviceId: string }[];
  }>;
};

/**
 * A resolved Food's nutrient amount, as read back from storage: structurally
 * compatible with the write-side AgentNutrientAmountSchema for the fields
 * this module actually reads (status/value for "complete"), but the
 * "unknown" branch's value/entered may be null (as stored) rather than
 * merely omittable (as the write-input contract requires). The resolution
 * merge below only ever forwards an amount object straight through to
 * nutrientVectorStorage, which discards value/entered for "unknown" amounts
 * regardless — so null vs. undefined never affects behavior.
 */
type AgentMealResolvedNutrientAmount =
  | { status: "complete"; value: number; entered: string; unit: string }
  | {
      status: "unknown";
      unit: string;
      value?: number | null;
      entered?: string | null;
    };

/**
 * Minimal Food lookup this module needs to resolve a reference Food entry's
 * snapshot server-side. Deliberately narrower than the full
 * AgentFoodCatalogStore (agent-foods.ts) so this module never depends on that
 * one — both depend on nothing but the shape below, avoiding an import cycle.
 */
export type AgentMealFoodLookup = {
  getFoodById(input: {
    userId: string;
    foodId: string;
  }): Promise<{
    name: string;
    nutrientsPer100: Record<string, AgentMealResolvedNutrientAmount>;
    isLiquid: boolean;
    servingLabel: string | null;
    servingSize: number | null;
    packageSize: number | null;
    deletedAt: string | null;
  } | null>;
};

export async function prepareAgentMealBatchWrite({
  request,
  userId,
  foodCatalogStore,
  now = new Date()
}: {
  request: AgentMealBatchWriteRequest;
  userId?: string;
  foodCatalogStore?: AgentMealFoodLookup;
  now?: Date;
}): Promise<AgentMealBatchPreparation> {
  const errors: AgentMealBatchWriteIssue[] = [];
  const warnings: AgentMealBatchWriteIssue[] = [];
  const preparedEntries: AgentMealBatchPreparedRow[] = [];
  const responseEntries: AgentMealBatchWriteEntryResult[] = [];
  const nowIso = now.toISOString();

  for (const [itemIndex, rawItem] of request.entries.entries()) {
    const kind = rawItem.foodId === null ? "quickEntry" : "food";

    // A reference Food carries a semantic Portion; a Quick Entry does not.
    if (kind === "food" && rawItem.portion === null) {
      errors.push(
        issueForItem(itemIndex, rawItem, {
          field: `entries[${itemIndex}].portion`,
          nutrient: null,
          rule: "reference_food_requires_portion",
          message: "A reference Food entry requires a Portion.",
          limit: null
        })
      );
      continue;
    }
    if (kind === "quickEntry" && rawItem.portion !== null) {
      errors.push(
        issueForItem(itemIndex, rawItem, {
          field: `entries[${itemIndex}].portion`,
          nutrient: null,
          rule: "quick_entry_forbids_portion",
          message:
            "A Quick Entry must not carry a Portion; its nutrient vector describes the whole entry.",
          limit: null
        })
      );
      continue;
    }
    if (kind === "food" && rawItem.foodSource === null) {
      errors.push(
        issueForItem(itemIndex, rawItem, {
          field: `entries[${itemIndex}].foodSource`,
          nutrient: null,
          rule: "reference_food_requires_food_source",
          message: "A reference Food entry requires a Food Source.",
          limit: null
        })
      );
      continue;
    }
    if (kind === "quickEntry" && rawItem.nutrients === undefined) {
      errors.push(
        issueForItem(itemIndex, rawItem, {
          field: `entries[${itemIndex}].nutrients`,
          nutrient: null,
          rule: "quick_entry_requires_nutrients",
          message: "A Quick Entry requires an explicit nutrient vector.",
          limit: null
        })
      );
      continue;
    }
    if (kind === "quickEntry" && rawItem.name === undefined) {
      errors.push(
        issueForItem(itemIndex, rawItem, {
          field: `entries[${itemIndex}].name`,
          nutrient: null,
          rule: "quick_entry_requires_name",
          message: "A Quick Entry requires an explicit name.",
          limit: null
        })
      );
      continue;
    }

    // Reference Food resolution: a caller may omit name/nutrients/
    // isLiquid/serving/package fields on a reference Food entry and have the
    // server resolve them from the caller's own Food library, exactly the
    // snapshot the app itself would take when a user picks a Food from the
    // list. Any field the caller DID supply is respected as-is (unchanged
    // behavior) — resolution only fills in what's missing.
    let item = rawItem;
    if (
      kind === "food" &&
      rawItem.foodSource === "user" &&
      (rawItem.name === undefined ||
        rawItem.nutrients === undefined ||
        rawItem.isLiquid === undefined)
    ) {
      if (foodCatalogStore === undefined || userId === undefined) {
        errors.push(
          issueForItem(itemIndex, rawItem, {
            field: `entries[${itemIndex}].nutrients`,
            nutrient: null,
            rule: "food_reference_resolution_unavailable",
            message:
              "This Food Entry omits a nutrient snapshot and server-side Food resolution is not configured.",
            limit: null
          })
        );
        continue;
      }

      const food = await foodCatalogStore.getFoodById({
        userId,
        foodId: rawItem.foodId as string
      });
      if (food === null || food.deletedAt !== null) {
        errors.push(
          issueForItem(itemIndex, rawItem, {
            field: `entries[${itemIndex}].foodId`,
            nutrient: null,
            rule: "food_reference_not_found",
            message:
              "foodId must reference an active Food visible to the authenticated account.",
            limit: null
          })
        );
        continue;
      }

      item = {
        ...rawItem,
        name: rawItem.name ?? food.name,
        nutrients:
          rawItem.nutrients ??
          (food.nutrientsPer100 as Record<
            string,
            z.infer<typeof AgentNutrientAmountSchema>
          >),
        isLiquid: rawItem.isLiquid ?? food.isLiquid,
        servingLabel:
          rawItem.servingLabel !== undefined
            ? rawItem.servingLabel
            : food.servingLabel,
        servingSize:
          rawItem.servingSize !== undefined
            ? rawItem.servingSize
            : food.servingSize,
        packageSize:
          rawItem.packageSize !== undefined
            ? rawItem.packageSize
            : food.packageSize
      };
    }

    if (item.name === undefined || item.nutrients === undefined || item.isLiquid === undefined) {
      errors.push(
        issueForItem(itemIndex, rawItem, {
          field: `entries[${itemIndex}].nutrients`,
          nutrient: null,
          rule: "food_reference_snapshot_incomplete",
          message:
            "A reference Food entry requires name, nutrients, and isLiquid, either supplied directly or resolvable from foodId.",
          limit: null
        })
      );
      continue;
    }
    // A Quick Entry or a fully explicit reference Food entry that never went
    // through resolution can still carry `undefined` here (the schema makes
    // these fields optional); normalize to null, the sentinel the rest of
    // this function and buildFoodEntryPayload already expect.
    const servingLabel = item.servingLabel ?? null;
    const servingSize = item.servingSize ?? null;
    const packageSize = item.packageSize ?? null;

    const resolvedBaseQuantity =
      item.portion === null
        ? undefined
        : resolvePortionBaseQuantity(item.portion, {
            servingSize,
            packageSize
          });
    if (
      item.portion !== null &&
      (resolvedBaseQuantity === undefined ||
        !Number.isFinite(resolvedBaseQuantity))
    ) {
      errors.push(
        issueForItem(itemIndex, item, {
          field: `entries[${itemIndex}].portion.unit`,
          nutrient: null,
          rule: "portion_unit_unavailable",
          message:
            "Portion unit is not available for this food (missing serving or package size).",
          limit: item.portion.unit
        })
      );
      continue;
    }

    const validation = validateAgentFoodEntry({
      nutrients: item.nutrients,
      portion:
        item.portion === null || resolvedBaseQuantity === undefined
          ? undefined
          : {
              value: item.portion.value,
              entered: item.portion.entered,
              unit: item.portion.unit,
              resolvedBaseQuantity
            }
    });
    for (const warning of validation.warnings) {
      warnings.push(issueForItem(itemIndex, item, warning));
    }
    for (const error of validation.errors) {
      errors.push(issueForItem(itemIndex, item, error));
    }
    if (validation.errors.length > 0) {
      continue;
    }

    const updatedAt = item.updatedAt ?? nowIso;
    const deletedAt = item.deletedAt ?? null;
    const payload = buildFoodEntryPayload({
      item,
      name: item.name,
      nutrients: item.nutrients,
      isLiquid: item.isLiquid,
      servingLabel,
      servingSize,
      packageSize,
      request,
      kind,
      updatedAt,
      deletedAt
    });
    preparedEntries.push({
      id: item.id,
      updatedAt,
      deletedAt,
      payload
    });
    responseEntries.push(
      AgentMealBatchWriteEntryResultSchema.parse({
        id: item.id,
        name: item.name,
        kind,
        warnings: validation.warnings
      })
    );
  }

  if (errors.length > 0) {
    return { accepted: false, errors, warnings };
  }

  const mealUpdatedAt = nowIso;
  const mealDeletedAt = request.meal.deletedAt ?? null;
  const meal: AgentMealBatchPreparedRow = {
    id: request.meal.id,
    updatedAt: mealUpdatedAt,
    deletedAt: mealDeletedAt,
    payload: buildMealPayload({
      request,
      updatedAt: mealUpdatedAt,
      deletedAt: mealDeletedAt
    })
  };

  return {
    accepted: true,
    meal,
    entries: preparedEntries,
    responseEntries
  };
}

export function createDrizzleAgentMealBatchWriteStore(
  db: ServerDatabase
): AgentMealBatchWriteStore {
  return {
    async writeMealBatch({ userId, batchId, deviceId, meal, entries }) {
      const serverClock = new Date();

      return db.transaction(async (transaction) => {
        const existingBatchRows = await transaction
          .select({ id: schema.activityLog.id })
          .from(schema.activityLog)
          .where(
            and(
              eq(schema.activityLog.userId, userId),
              eq(schema.activityLog.actor, "agent"),
              eq(schema.activityLog.batchId, batchId)
            )
          )
          .orderBy(asc(schema.activityLog.createdAt), asc(schema.activityLog.id))
          .limit(1);

        if (existingBatchRows.length > 0) {
          return {
            duplicate: true,
            serverClock: serverClock.toISOString(),
            applied: []
          };
        }

        const mealBeforeImage = await readBeforeImage({
          transaction,
          table: schema.meals,
          userId,
          rowId: meal.id
        });
        const mealResult = await pushMealsInTransaction(transaction, {
          userId,
          deviceId,
          serverClock,
          changes: [
            {
              id: meal.id,
              payload: meal.payload,
              updatedAt: meal.updatedAt,
              deletedAt: meal.deletedAt,
              activityLogId: `agent:${batchId}:${meal.id}`,
              actor: "agent",
              batchId,
              beforeImage: mealBeforeImage,
              afterImage: meal.payload,
              occurredAt: meal.updatedAt
            }
          ]
        });

        const entryChanges: SyncPushChange[] = [];
        for (const entry of entries) {
          const beforeImage = await readBeforeImage({
            transaction,
            table: schema.foodEntries,
            userId,
            rowId: entry.id
          });
          entryChanges.push({
            id: entry.id,
            payload: entry.payload,
            updatedAt: entry.updatedAt,
            deletedAt: entry.deletedAt,
            activityLogId: `agent:${batchId}:${entry.id}`,
            actor: "agent",
            batchId,
            beforeImage,
            afterImage: entry.payload,
            occurredAt: entry.updatedAt
          });
        }
        const entryResult = await pushFoodEntriesInTransaction(transaction, {
          userId,
          deviceId,
          changes: entryChanges,
          serverClock
        });

        return {
          duplicate: false,
          serverClock: entryResult.serverClock,
          applied: [...mealResult.applied, ...entryResult.applied]
        };
      });
    }
  };
}

function buildMealPayload({
  request,
  updatedAt,
  deletedAt
}: {
  request: AgentMealBatchWriteRequest;
  updatedAt: string;
  deletedAt: string | null;
}): Record<string, unknown> {
  return {
    id: request.meal.id,
    meal_type: request.meal.mealType,
    started_at: request.meal.startedAt,
    timezone: request.meal.timezone,
    local_date: request.meal.localDate,
    ended_at: request.meal.endedAt,
    updated_at: updatedAt,
    deleted_at: deletedAt
  };
}

function buildFoodEntryPayload({
  item,
  name,
  nutrients,
  isLiquid,
  servingLabel,
  servingSize,
  packageSize,
  request,
  kind,
  updatedAt,
  deletedAt
}: {
  item: AgentMealBatchWriteEntry;
  name: string;
  nutrients: Record<string, z.infer<typeof AgentNutrientAmountSchema>>;
  isLiquid: boolean;
  servingLabel: string | null;
  servingSize: number | null;
  packageSize: number | null;
  request: AgentMealBatchWriteRequest;
  kind: "food" | "quickEntry";
  updatedAt: string;
  deletedAt: string | null;
}): Record<string, unknown> {
  return {
    id: item.id,
    meal_id: request.meal.id,
    entry_kind: kind,
    position: item.position,
    name,
    nutrient_values_json: JSON.stringify(nutrientVectorStorage(nutrients)),
    food_id: item.foodId,
    portion_json:
      item.portion === null
        ? null
        : JSON.stringify({
            value: item.portion.value,
            entered: item.portion.entered,
            unit: item.portion.unit
          }),
    food_source: item.foodSource,
    is_liquid: isLiquid,
    serving_label: servingLabel,
    serving_size: servingSize,
    package_size: packageSize,
    updated_at: updatedAt,
    deleted_at: deletedAt
  };
}

const NUTRIENT_STORAGE_KEYS = [
  "energy",
  "protein",
  "carbohydrate",
  "sugar",
  "fat",
  "saturated_fat",
  "monounsaturated_fat",
  "polyunsaturated_fat",
  "fiber",
  "sodium",
  "cholesterol",
  "vitamin_a",
  "vitamin_c",
  "vitamin_d",
  "vitamin_e",
  "vitamin_k",
  "thiamin",
  "riboflavin",
  "niacin",
  "vitamin_b6",
  "folate",
  "vitamin_b12",
  "calcium",
  "iron",
  "magnesium",
  "phosphorus",
  "potassium",
  "zinc",
  "copper",
  "manganese",
  "selenium",
  "caffeine",
  "water"
] as const;

const NUTRIENT_DEFAULT_UNIT: Record<string, string> = {
  energy: "kilocalorie",
  protein: "gram",
  carbohydrate: "gram",
  sugar: "gram",
  fat: "gram",
  saturated_fat: "gram",
  monounsaturated_fat: "gram",
  polyunsaturated_fat: "gram",
  fiber: "gram",
  sodium: "milligram",
  cholesterol: "milligram",
  vitamin_a: "microgram",
  vitamin_c: "milligram",
  vitamin_d: "microgram",
  vitamin_e: "milligram",
  vitamin_k: "microgram",
  thiamin: "milligram",
  riboflavin: "milligram",
  niacin: "milligram",
  vitamin_b6: "milligram",
  folate: "microgram",
  vitamin_b12: "microgram",
  calcium: "milligram",
  iron: "milligram",
  magnesium: "milligram",
  phosphorus: "milligram",
  potassium: "milligram",
  zinc: "milligram",
  copper: "milligram",
  manganese: "milligram",
  selenium: "microgram",
  caffeine: "milligram",
  water: "milliliter"
};

/**
 * Render the full self-describing nutrient vector for storage: every fixed
 * nutrient id is present, an omitted or unknown Nutrient is stored as an
 * explicit `unknown` amount (never coerced to zero, NUTRITION.md §4), matching
 * the device-canonical `nutrient_values_json` shape.
 */
function nutrientVectorStorage(
  nutrients: Record<string, z.infer<typeof AgentNutrientAmountSchema>>
): Record<string, Record<string, unknown>> {
  const storage: Record<string, Record<string, unknown>> = {};
  for (const key of NUTRIENT_STORAGE_KEYS) {
    const amount = nutrients[key];
    const unit = amount?.unit ?? NUTRIENT_DEFAULT_UNIT[key];
    if (amount === undefined || amount.status === "unknown") {
      storage[key] = {
        status: "unknown",
        value: null,
        entered: null,
        unit
      };
      continue;
    }
    storage[key] = {
      status: "complete",
      value: amount.value,
      entered: amount.entered,
      unit
    };
  }

  return storage;
}

const OUNCE_GRAMS = 28.349523125;
const FLUID_OUNCE_MILLILITERS = 29.5735295625;

/**
 * Resolve the logged Portion to a base quantity in grams or milliliters, the
 * same conversions the device uses (apps/mobile resolvePortionBaseQuantity).
 * Returns undefined when a serving/package unit is requested but the matching
 * snapshot size is absent. Exported for reuse by agent-foods.ts, which needs
 * the identical conversion to derive a Recipe's nutrition from its
 * ingredients (mirrors deriveRecipeNutrition() in
 * apps/mobile/lib/domain/nutrition/nutrition.dart).
 */
export function resolvePortionBaseQuantity(
  portion: { value: number; unit: string },
  {
    servingSize,
    packageSize
  }: { servingSize: number | null; packageSize: number | null }
): number | undefined {
  switch (portion.unit) {
    case "gram":
    case "milliliter":
      return portion.value;
    case "ounce":
      return portion.value * OUNCE_GRAMS;
    case "fluidOunce":
      return portion.value * FLUID_OUNCE_MILLILITERS;
    case "serving":
      return servingSize === null ? undefined : portion.value * servingSize;
    case "package":
      return packageSize === null ? undefined : portion.value * packageSize;
    default:
      return undefined;
  }
}

async function readBeforeImage({
  transaction,
  table,
  userId,
  rowId
}: {
  transaction: Pick<ServerDatabase, "select">;
  table: typeof schema.meals | typeof schema.foodEntries;
  userId: string;
  rowId: string;
}) {
  const existingRows = await transaction
    .select({
      userId: table.userId,
      payload: table.payload
    })
    .from(table)
    .where(eq(table.id, rowId))
    .limit(1);
  const existing = existingRows[0];
  if (existing === undefined || existing.userId !== userId) {
    return null;
  }

  return existing.payload;
}

function issueForItem(
  itemIndex: number,
  item: AgentMealBatchWriteEntry,
  issue: AgentNutrientValidationIssue
): AgentMealBatchWriteIssue {
  return AgentMealBatchWriteIssueSchema.parse({
    ...issue,
    field: issue.field.startsWith("entries[")
      ? issue.field
      : `entries[${itemIndex}].${issue.field}`,
    itemIndex,
    entryId: item.id
  });
}
