import { createRoute, z } from "@hono/zod-openapi";
import { and, asc, eq, inArray, isNull, sql } from "drizzle-orm";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import {
  AgentNutrientAmountSchema,
  AgentNutrientValidationIssueSchema,
  AgentNutrientValidationLimitsSchema,
  validateAgentFoodEntry,
  validateAgentMealTime,
  type AgentMealValidationIssue,
  type AgentNutrientValidationIssue
} from "./agent-validation.js";
import {
  AGENT_PROTOCOLS_MAX_OFFSET_MINUTES,
  AGENT_PROTOCOLS_MIN_OFFSET_MINUTES,
  LocalDateSchema
} from "./agent-protocols.js";
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
import { localDateAtOffset, offsetMinutesInTimezone } from "./timezone.js";

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
    mealType: MealTypeSchema.optional().openapi({
      description:
        "Meal Type label, stored as sent. Required to create a Meal; omit it to keep the stored value."
    }),
    startedAt: ISO8601StringSchema.optional().openapi({
      description:
        "Meal start instant in UTC. Required to create a Meal. Sent with timezoneOffsetMinutes, timezone, or both; omit the whole time block to keep the stored time."
    }),
    endedAt: ISO8601StringSchema.nullable().optional().openapi({
      description:
        "Meal end instant in UTC. Omit to keep the stored value; null clears it."
    }),
    timezone: z.string().min(1).optional().openapi({
      description:
        "The Meal's time zone as entered: an IANA name lets the server derive the offset; any other label is stored for display only."
    }),
    timezoneOffsetMinutes: z
      .number()
      .int()
      .min(AGENT_PROTOCOLS_MIN_OFFSET_MINUTES)
      .max(AGENT_PROTOCOLS_MAX_OFFSET_MINUTES)
      .optional()
      .openapi({
        description:
          "UTC offset at startedAt, in minutes east of UTC (UTC-3 is -180), -720 to +840. Frozen on the Meal; wins over the offset derived from timezone. Sent only with startedAt."
      }),
    localDate: LocalDateSchema.optional().openapi({
      description:
        "Nutrition Day date (YYYY-MM-DD). Ignored when the offset is known (sent, or derived from an IANA timezone): the server derives it from startedAt. Required with startedAt when the offset can't be resolved. Sent only with startedAt."
    }),
    timePrecision: z.enum(["instant", "date"]).optional().openapi({
      description:
        "instant: startedAt is the time eaten. date: only the date is known and startedAt is local midnight. Sending startedAt sets instant unless this is also sent; omit to keep the stored value."
    }),
    deletedAt: ISO8601StringSchema.nullable().optional().openapi({
      description:
        "Nullable archive tombstone. Setting it is an ordinary LWW write of a tombstone, the same archive semantics the app's own delete affordance produces — never a purge. Omit to keep the stored value; null un-archives. Archiving also needs every Food Entry stored active in the Meal sent with deletedAt set in the same request, or the write fails with 422 meal_archived."
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
    deletedAt: ISO8601StringSchema.nullable().optional().openapi({
      description:
        "Nullable archive tombstone. Setting it is an ordinary LWW write of a tombstone, the same archive semantics the app's own delete affordance produces — never a purge. Omit to keep the stored value (null for a new entry)."
    })
  })
  .openapi("AgentMealBatchWriteEntry");

/** The Meal fields besides `id`; a request that sends none is entries-only. */
const AGENT_MEAL_BATCH_WRITE_MEAL_FIELDS = [
  "mealType",
  "startedAt",
  "endedAt",
  "timezone",
  "timezoneOffsetMinutes",
  "localDate",
  "timePrecision",
  "deletedAt"
] as const;

function mealFieldsSent(meal: AgentMealBatchWriteRequest["meal"]): boolean {
  return AGENT_MEAL_BATCH_WRITE_MEAL_FIELDS.some(
    (field) => meal[field] !== undefined
  );
}

export const AgentMealBatchWriteRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200).openapi({
      description:
        "Stable key for this agent request. Replays with the same key return the original result without appending another Activity Log batch."
    }),
    meal: AgentMealBatchWriteMealSchema,
    entries: z
      .array(AgentMealBatchWriteEntrySchema)
      .min(0)
      .max(AGENT_MEAL_BATCH_WRITE_MAX_ENTRIES)
      .openapi({
        description:
          "Food Entries to apply atomically with the Meal fields as one Activity Log batch. May be empty when the request sends Meal fields."
      })
  })
  // Input shape only (meal-logging.md §9): a request that writes nothing, and
  // a time block whose parts can't be read together. Stored-state rules
  // (create, archived, ownership) are prepareAgentMealBatchWrite's.
  .superRefine((request, context) => {
    const meal = request.meal;
    if (!mealFieldsSent(meal) && request.entries.length === 0) {
      context.addIssue({
        code: "custom",
        path: ["meal"],
        message:
          "A Meal batch must send at least one Meal field besides id, or at least one entry."
      });
    }
    if (
      meal.startedAt !== undefined &&
      meal.timezoneOffsetMinutes === undefined &&
      meal.timezone === undefined
    ) {
      context.addIssue({
        code: "custom",
        path: ["meal", "startedAt"],
        message: "startedAt must be sent with timezoneOffsetMinutes, timezone, or both."
      });
    }
    if (meal.startedAt === undefined) {
      for (const field of ["timezoneOffsetMinutes", "localDate", "timezone"] as const) {
        if (meal[field] !== undefined) {
          context.addIssue({
            code: "custom",
            path: ["meal", field],
            message: `${field} is only accepted together with startedAt.`
          });
        }
      }
    }
  })
  .openapi("AgentMealBatchWriteRequest");

export const AgentMealBatchWriteIssueSchema = AgentNutrientValidationIssueSchema
  .extend({
    itemIndex: z.number().int().min(0).nullable().openapi({
      description:
        "Index of the Food Entry item that produced the issue, or null for a Meal-level issue."
    }),
    entryId: z.string().min(1).nullable().openapi({
      description:
        "Client-supplied Food Entry id for the failed item, or null for a Meal-level issue."
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
    entries: z.array(AgentMealBatchWriteEntryResultSchema),
    warnings: z.array(AgentMealBatchWriteIssueSchema).openapi({
      description:
        "Meal-level soft warnings (for example meal_time_in_future). Per-entry nutrient warnings stay on entries[].warnings."
    })
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
    "Authenticated agent write path for nutrition. Writes only the Meal fields a request sends: an absent field keeps its stored value and null clears endedAt or deletedAt. Creating a Meal needs mealType and the time block (startedAt with timezoneOffsetMinutes and/or timezone); the offset is the one sent, else derived from an IANA timezone, and with a known offset localDate is derived. A request whose meal carries only id writes its entries and leaves the Meal row untouched. Snapshots a self-describing Food Entry per item (nutrient vector, name, Food Source, serving/package, isLiquid) plus the semantic Portion, validates every item with the shared two-tier nutrient validation module, applies the request atomically, and records one Activity Log batch. No nutrition totals are stored; energy and macros are derived on read. Purge and hard-delete are intentionally absent.",
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
    404: {
      description:
        "The request carries only the Meal id and entries, and no Meal with that id exists (meal_not_found); nothing was written.",
      content: {
        "application/json": {
          schema: AgentMealBatchWriteErrorResponseSchema
        }
      }
    },
    409: {
      description:
        "The Meal id or a Food Entry id belongs to another account (meal_id_conflict, entry_id_conflict); nothing was written.",
      content: {
        "application/json": {
          schema: AgentMealBatchWriteErrorResponseSchema
        }
      }
    },
    422: {
      description:
        "One or more items or the Meal failed hard validation (nutrient rules, meal_ended_before_start, meal_type_required, meal_create_incomplete, meal_offset_unknown, meal_archived, entry_meal_mismatch); no rows were written.",
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

/**
 * A request entry after Food resolution: the snapshot fields a reference Food
 * entry may omit are filled in, so the rest of the pipeline never reads the
 * Food library again.
 */
export type AgentMealBatchResolvedEntry = AgentMealBatchWriteEntry & {
  name: string;
  nutrients: Record<string, z.infer<typeof AgentNutrientAmountSchema>>;
  isLiquid: boolean;
  servingLabel: string | null;
  servingSize: number | null;
  packageSize: number | null;
};
export type AgentMealBatchResolvedRequest = Omit<
  AgentMealBatchWriteRequest,
  "entries"
> & {
  entries: AgentMealBatchResolvedEntry[];
};
export type AgentMealBatchEntryResolution =
  | {
      accepted: true;
      request: AgentMealBatchResolvedRequest;
      responseEntries: AgentMealBatchWriteEntryResult[];
    }
  | {
      accepted: false;
      errors: AgentMealBatchWriteIssue[];
      warnings: AgentMealBatchWriteIssue[];
    };

/** A stored Meal or Food Entry row, read for any user. */
export type AgentMealBatchStoredRow = {
  userId: string;
  payload: Record<string, unknown>;
  deletedAt: string | null;
};
/**
 * What `prepareAgentMealBatchWrite` reads besides the request: the caller's
 * user id (to tell its own rows from another account's), the stored Meal and
 * request entries, by id, for any user, and the ids of the caller's Food
 * Entries stored active under this Meal id.
 */
export type AgentMealBatchStoredState = {
  userId: string;
  meal: AgentMealBatchStoredRow | null;
  entries: ReadonlyMap<string, AgentMealBatchStoredRow>;
  /**
   * The ids of the caller's Food Entries stored active (deleted_at null)
   * under this Meal id, whether or not the request sends them. Empty when the
   * Meal doesn't exist or belongs to another account.
   */
  activeEntryIds: ReadonlySet<string>;
};
export type AgentMealBatchRejectionStatus = 404 | 409 | 422;
export type AgentMealBatchPreparation =
  | {
      accepted: true;
      /** null means the Meal row is not rewritten (an entries-only request). */
      meal: AgentMealBatchPreparedRow | null;
      entries: AgentMealBatchPreparedRow[];
      warnings: AgentMealBatchWriteIssue[];
    }
  | {
      accepted: false;
      status: AgentMealBatchRejectionStatus;
      errors: AgentMealBatchWriteIssue[];
      warnings: AgentMealBatchWriteIssue[];
    };
export type AgentMealBatchWriteResult =
  | {
      status: "written";
      duplicate: boolean;
      serverClock: string;
      applied: { id: string; updatedAt: string; deviceId: string }[];
      warnings: AgentMealBatchWriteIssue[];
    }
  | {
      status: "rejected";
      httpStatus: AgentMealBatchRejectionStatus;
      errors: AgentMealBatchWriteIssue[];
      warnings: AgentMealBatchWriteIssue[];
    };
export type AgentMealBatchWriteStore = {
  writeMealBatch(input: {
    userId: string;
    batchId: string;
    correlationId?: string;
    deviceId: string;
    request: AgentMealBatchResolvedRequest;
    now?: Date;
  }): Promise<AgentMealBatchWriteResult>;
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

/**
 * The first, read-only half of the pipeline (meal-logging.md §9): checks each
 * entry's shape, resolves a reference Food's omitted snapshot from the
 * caller's Food library, resolves the Portion and runs the shared nutrient
 * validation. It runs before the write transaction, so an idempotent replay
 * still returns the same `entries` response. Nutrient warnings ride on
 * `responseEntries[].warnings`.
 */
export async function resolveAgentMealBatchEntries({
  request,
  userId,
  foodCatalogStore
}: {
  request: AgentMealBatchWriteRequest;
  userId?: string;
  foodCatalogStore?: AgentMealFoodLookup;
}): Promise<AgentMealBatchEntryResolution> {
  const errors: AgentMealBatchWriteIssue[] = [];
  const warnings: AgentMealBatchWriteIssue[] = [];
  const resolvedEntries: AgentMealBatchResolvedEntry[] = [];
  const responseEntries: AgentMealBatchWriteEntryResult[] = [];

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

    resolvedEntries.push({
      ...item,
      name: item.name,
      nutrients: item.nutrients,
      isLiquid: item.isLiquid,
      servingLabel,
      servingSize,
      packageSize
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

  return {
    accepted: true,
    request: { ...request, entries: resolvedEntries },
    responseEntries
  };
}

/**
 * The pure second half of the pipeline (meal-logging.md §9): applies the
 * field rules to the resolved request against the stored Meal and entries,
 * and returns the rows to write or the issues and HTTP status to reject with.
 *
 * - Only the Meal fields sent are written; an absent field keeps the stored
 *   value, and null clears `endedAt` or `deletedAt`. A Meal whose request
 *   carries only `id` is not rewritten (`meal: null`), so its `updated_at`
 *   doesn't move and no Meal Activity Log entry is written (CUJ 7).
 * - The time block: the offset is the one sent, else derived from an IANA
 *   `timezone` at `startedAt`, else null. A known offset derives `local_date`
 *   (a sent `localDate` is ignored); a null offset needs the sent `localDate`.
 * - Rejections take one status, by precedence 409 (another account's id),
 *   then 404 (an entries-only request for an unknown Meal), then 422, and
 *   carry only that status's issues.
 *
 * - The three §8 Meal rules run on every request, against the Meal as it
 *   will be stored (§8, §9): the rewritten Meal, or, for an entries-only
 *   request, the stored Meal. So entries into a future-started Meal return
 *   `meal_time_in_future`, and a stored Meal that breaks a hard rule takes
 *   no entries until the request also fixes it.
 */
export function prepareAgentMealBatchWrite(
  request: AgentMealBatchResolvedRequest,
  stored: AgentMealBatchStoredState,
  now: Date = new Date()
): AgentMealBatchPreparation {
  const nowIso = now.toISOString();
  const meal = request.meal;
  const storedMeal = stored.meal;

  // 409: an id that already belongs to another account.
  const conflicts: AgentMealBatchWriteIssue[] = [];
  if (storedMeal !== null && storedMeal.userId !== stored.userId) {
    conflicts.push(
      mealLevelIssue({
        field: "meal.id",
        rule: "meal_id_conflict",
        message: "This Meal id already belongs to another account.",
        limit: null
      })
    );
  }
  for (const [itemIndex, entry] of request.entries.entries()) {
    const storedEntry = stored.entries.get(entry.id);
    if (storedEntry !== undefined && storedEntry.userId !== stored.userId) {
      conflicts.push(
        entryLevelIssue(itemIndex, entry.id, {
          field: `entries[${itemIndex}].id`,
          rule: "entry_id_conflict",
          message: "This Food Entry id already belongs to another account.",
          limit: null
        })
      );
    }
  }
  if (conflicts.length > 0) {
    return { accepted: false, status: 409, errors: conflicts, warnings: [] };
  }

  const rewritesMeal = mealFieldsSent(meal);

  // 404: entries for a Meal that doesn't exist, with nothing to create it.
  if (storedMeal === null && !rewritesMeal) {
    return {
      accepted: false,
      status: 404,
      errors: [
        mealLevelIssue({
          field: "meal.id",
          rule: "meal_not_found",
          message:
            "No Meal with this id exists. To create it, send mealType and the time block.",
          limit: null
        })
      ],
      warnings: []
    };
  }

  const errors: AgentMealBatchWriteIssue[] = [];
  const warnings: AgentMealBatchWriteIssue[] = [];

  for (const [itemIndex, entry] of request.entries.entries()) {
    const storedEntry = stored.entries.get(entry.id);
    if (
      storedEntry !== undefined &&
      storedEntry.payload.meal_id !== meal.id
    ) {
      errors.push(
        entryLevelIssue(itemIndex, entry.id, {
          field: `entries[${itemIndex}].id`,
          rule: "entry_meal_mismatch",
          message:
            "This Food Entry already exists under a different Meal; an agent write never moves an entry to another Meal.",
          limit: null
        })
      );
    }
  }

  const entryDeletedAt = request.entries.map((entry) => {
    if (entry.deletedAt !== undefined) {
      return entry.deletedAt;
    }
    const storedEntry = stored.entries.get(entry.id);
    return storedEntry === undefined ? null : storedDeletedAt(storedEntry);
  });

  let preparedMeal: AgentMealBatchPreparedRow | null = null;
  let resultingMealDeletedAt: string | null =
    storedMeal === null ? null : storedDeletedAt(storedMeal);
  // The Meal as it will be stored, for the §8 rules. Without a rewrite it is
  // the stored Meal (non-null here: an unknown id without Meal fields is 404).
  const storedPayload: Record<string, unknown> =
    storedMeal === null ? {} : storedMeal.payload;
  let resultingTime = {
    startedAt: storedString(storedPayload.started_at) ?? "",
    endedAt: storedString(storedPayload.ended_at),
    mealType: storedString(storedPayload.meal_type) ?? ""
  };

  if (rewritesMeal) {
    const base: Record<string, unknown> =
      storedMeal === null ? {} : storedMeal.payload;

    if (storedMeal === null) {
      const incomplete: AgentMealBatchWriteIssue[] = [];
      if (meal.mealType === undefined) {
        incomplete.push(
          mealLevelIssue({
            field: "meal.mealType",
            rule: "meal_create_incomplete",
            message: "Creating a Meal requires mealType.",
            limit: null
          })
        );
      }
      if (meal.startedAt === undefined) {
        incomplete.push(
          mealLevelIssue({
            field: "meal.startedAt",
            rule: "meal_create_incomplete",
            message:
              "Creating a Meal requires the time block: startedAt with timezoneOffsetMinutes and/or timezone.",
            limit: null
          })
        );
      }
      if (incomplete.length > 0) {
        return {
          accepted: false,
          status: 422,
          errors: [...errors, ...incomplete],
          warnings
        };
      }
    }

    const mealType = meal.mealType ?? storedString(base.meal_type) ?? "";
    let startedAt = storedString(base.started_at);
    let timezone: string | null = storedString(base.timezone);
    let localDate = storedString(base.local_date);
    let offsetMinutes = storedOffset(base.timezone_offset_minutes);
    let timePrecision =
      meal.timePrecision ?? storedTimePrecision(base.time_precision);

    if (meal.startedAt !== undefined) {
      const instant = new Date(meal.startedAt);
      startedAt = meal.startedAt;
      offsetMinutes =
        meal.timezoneOffsetMinutes ??
        (meal.timezone === undefined
          ? null
          : offsetMinutesInTimezone(instant, meal.timezone));
      if (offsetMinutes !== null) {
        localDate = localDateAtOffset(instant, offsetMinutes);
      } else if (meal.localDate !== undefined) {
        localDate = meal.localDate;
      } else {
        localDate = null;
        errors.push(
          mealLevelIssue({
            field: "meal.localDate",
            rule: "meal_offset_unknown",
            message:
              "The UTC offset can't be resolved from timezone; send timezoneOffsetMinutes or localDate.",
            limit: null
          })
        );
      }
      timezone =
        meal.timezone ??
        (offsetMinutes === null ? timezone : utcOffsetLabel(offsetMinutes));
      timePrecision = meal.timePrecision ?? "instant";
    }

    const endedAt =
      meal.endedAt !== undefined ? meal.endedAt : storedString(base.ended_at);
    const deletedAt =
      meal.deletedAt !== undefined
        ? meal.deletedAt
        : storedMeal === null
          ? null
          : storedDeletedAt(storedMeal);
    resultingMealDeletedAt = deletedAt;
    resultingTime = { startedAt: startedAt ?? "", endedAt, mealType };

    preparedMeal = {
      id: meal.id,
      updatedAt: nowIso,
      deletedAt,
      payload: {
        ...base,
        id: meal.id,
        meal_type: mealType,
        started_at: startedAt,
        timezone,
        local_date: localDate,
        ended_at: endedAt,
        updated_at: nowIso,
        deleted_at: deletedAt,
        timezone_offset_minutes: offsetMinutes,
        time_precision: timePrecision
      }
    };
  }

  const validation = validateAgentMealTime(resultingTime, { now });
  for (const issue of validation.errors) {
    errors.push(mealValidationIssue(issue));
  }
  for (const issue of validation.warnings) {
    warnings.push(mealValidationIssue(issue));
  }

  // An archived Meal takes no active Food Entry (meal-logging.md §7).
  if (
    resultingMealDeletedAt !== null &&
    entryDeletedAt.some((deletedAt) => deletedAt === null)
  ) {
    errors.push(
      mealLevelIssue({
        field: "meal.deletedAt",
        rule: "meal_archived",
        message:
          "This Meal is archived: it can't take active Food Entries. Send meal.deletedAt: null to un-archive it in the same request.",
        limit: null
      })
    );
  }

  // Archiving a Meal tombstones its active Food Entries in the same request
  // (meal-logging.md §9 'Archived Meals'). The app's deleteMeal archives the
  // Meal and its entries in one Batch, and no agent request may leave an
  // active Food Entry in an archived Meal. The rule judges the resulting Meal,
  // so it also covers an edit to an already archived Meal that still holds
  // stored active entries. An entry counts as tombstoned only when the request
  // sends it with deletedAt set: an unsent deletedAt keeps the stored null.
  if (resultingMealDeletedAt !== null && stored.activeEntryIds.size > 0) {
    const tombstoned = new Set(
      request.entries
        .filter((_, index) => entryDeletedAt[index] !== null)
        .map((entry) => entry.id)
    );
    const untombstoned = [...stored.activeEntryIds]
      .filter((id) => !tombstoned.has(id))
      .sort();
    if (untombstoned.length > 0) {
      errors.push(
        mealLevelIssue({
          field: "meal.deletedAt",
          rule: "meal_archived",
          message: `Archiving this Meal needs every active Food Entry in it sent with deletedAt set in the same request; not tombstoned: ${untombstoned.join(", ")}.`,
          limit: null
        })
      );
    }
  }

  if (errors.length > 0) {
    return { accepted: false, status: 422, errors, warnings };
  }

  const entries = request.entries.map((entry, index) => {
    const updatedAt = entry.updatedAt ?? nowIso;
    const deletedAt = entryDeletedAt[index] ?? null;
    return {
      id: entry.id,
      updatedAt,
      deletedAt,
      payload: buildFoodEntryPayload({
        item: entry,
        name: entry.name,
        nutrients: entry.nutrients,
        isLiquid: entry.isLiquid,
        servingLabel: entry.servingLabel,
        servingSize: entry.servingSize,
        packageSize: entry.packageSize,
        mealId: meal.id,
        kind: entry.foodId === null ? "quickEntry" : "food",
        updatedAt,
        deletedAt
      })
    };
  });

  return { accepted: true, meal: preparedMeal, entries, warnings };
}

export function createDrizzleAgentMealBatchWriteStore(
  db: ServerDatabase
): AgentMealBatchWriteStore {
  return {
    async writeMealBatch({ userId, batchId, deviceId, request, now }) {
      const serverClock = now ?? new Date();

      return db.transaction(async (transaction): Promise<AgentMealBatchWriteResult> => {
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
            status: "written",
            duplicate: true,
            serverClock: serverClock.toISOString(),
            applied: [],
            warnings: []
          };
        }

        // Read the stored rows for any user, locked for the rest of the
        // transaction, so the field rules judge the rows this batch will
        // overwrite and a concurrent write can't slip in between. The same
        // locked pass reads the caller's Food Entries stored active under this
        // Meal, so the archive rule (meal-logging.md §9 'Archived Meals') sees
        // every entry a concurrent write could otherwise add or revive.
        const storedMealRows = await transaction
          .select({
            userId: schema.meals.userId,
            payload: schema.meals.payload,
            deletedAt: schema.meals.deletedAt
          })
          .from(schema.meals)
          .where(eq(schema.meals.id, request.meal.id))
          .for("update");
        const entryIds = [...new Set(request.entries.map((entry) => entry.id))];
        const storedEntryRows =
          entryIds.length === 0
            ? []
            : await transaction
                .select({
                  id: schema.foodEntries.id,
                  userId: schema.foodEntries.userId,
                  payload: schema.foodEntries.payload,
                  deletedAt: schema.foodEntries.deletedAt
                })
                .from(schema.foodEntries)
                .where(inArray(schema.foodEntries.id, entryIds))
                .for("update");

        const storedMealRow = storedMealRows[0];
        const activeEntryRows =
          storedMealRow !== undefined && storedMealRow.userId === userId
            ? await transaction
                .select({ id: schema.foodEntries.id })
                .from(schema.foodEntries)
                .where(
                  and(
                    eq(schema.foodEntries.userId, userId),
                    eq(sql`${schema.foodEntries.payload}->>'meal_id'`, request.meal.id),
                    isNull(schema.foodEntries.deletedAt)
                  )
                )
                .for("update")
            : [];
        const activeEntryIds = new Set(activeEntryRows.map((row) => row.id));
        const storedMeal: AgentMealBatchStoredRow | null =
          storedMealRow === undefined
            ? null
            : {
                userId: storedMealRow.userId,
                payload: storedMealRow.payload,
                deletedAt: storedMealRow.deletedAt?.toISOString() ?? null
              };
        const storedEntries = new Map<string, AgentMealBatchStoredRow>(
          storedEntryRows.map((row) => [
            row.id,
            {
              userId: row.userId,
              payload: row.payload,
              deletedAt: row.deletedAt?.toISOString() ?? null
            }
          ])
        );

        const prepared = prepareAgentMealBatchWrite(
          request,
          { userId, meal: storedMeal, entries: storedEntries, activeEntryIds },
          serverClock
        );
        if (!prepared.accepted) {
          return {
            status: "rejected",
            httpStatus: prepared.status,
            errors: prepared.errors,
            warnings: prepared.warnings
          };
        }

        const applied: { id: string; updatedAt: string; deviceId: string }[] = [];
        let resultClock = serverClock.toISOString();

        if (prepared.meal !== null) {
          const meal = prepared.meal;
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
                // prepareAgentMealBatchWrite has already rejected another
                // account's Meal, so a stored row here is the caller's.
                beforeImage: storedMeal?.payload ?? null,
                afterImage: meal.payload,
                occurredAt: meal.updatedAt
              }
            ]
          });
          applied.push(...mealResult.applied);
          resultClock = mealResult.serverClock;
        }

        if (prepared.entries.length > 0) {
          const entryChanges: SyncPushChange[] = prepared.entries.map((entry) => ({
            id: entry.id,
            payload: entry.payload,
            updatedAt: entry.updatedAt,
            deletedAt: entry.deletedAt,
            activityLogId: `agent:${batchId}:${entry.id}`,
            actor: "agent",
            batchId,
            beforeImage: storedEntries.get(entry.id)?.payload ?? null,
            afterImage: entry.payload,
            occurredAt: entry.updatedAt
          }));
          const entryResult = await pushFoodEntriesInTransaction(transaction, {
            userId,
            deviceId,
            changes: entryChanges,
            serverClock
          });
          applied.push(...entryResult.applied);
          resultClock = entryResult.serverClock;
        }

        return {
          status: "written",
          duplicate: false,
          serverClock: resultClock,
          applied,
          warnings: prepared.warnings
        };
      });
    }
  };
}

/** The error body's message for each status a stored-state rule rejects with. */
export function agentMealBatchWriteRejectionMessage(
  status: AgentMealBatchRejectionStatus
): string {
  switch (status) {
    case 409:
      return "The Meal id or a Food Entry id belongs to another account.";
    case 404:
      return "No Meal with this id exists.";
    case 422:
      return "Batch contains one or more hard validation failures.";
  }
}

/** A stored row's tombstone: the column decides, the payload keeps its text. */
function storedDeletedAt(row: AgentMealBatchStoredRow): string | null {
  if (row.deletedAt === null) {
    return null;
  }
  return typeof row.payload.deleted_at === "string"
    ? row.payload.deleted_at
    : row.deletedAt;
}

function storedString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function storedOffset(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) ? value : null;
}

/** A payload written before time precision existed reads as `instant`. */
function storedTimePrecision(value: unknown): "instant" | "date" {
  return value === "date" ? "date" : "instant";
}

/**
 * The display label stored when an agent sends only an offset: `UTC+10:00`,
 * `UTC-03:30`, `UTC+00:00`.
 */
function utcOffsetLabel(offsetMinutes: number): string {
  const sign = offsetMinutes < 0 ? "-" : "+";
  const magnitude = Math.abs(offsetMinutes);
  const hours = String(Math.floor(magnitude / 60)).padStart(2, "0");
  const minutes = String(magnitude % 60).padStart(2, "0");
  return `UTC${sign}${hours}:${minutes}`;
}

function mealLevelIssue(issue: {
  field: string;
  rule: string;
  message: string;
  limit: number | string | null;
}): AgentMealBatchWriteIssue {
  return AgentMealBatchWriteIssueSchema.parse({
    ...issue,
    nutrient: null,
    itemIndex: null,
    entryId: null
  });
}

function entryLevelIssue(
  itemIndex: number,
  entryId: string,
  issue: { field: string; rule: string; message: string; limit: number | string | null }
): AgentMealBatchWriteIssue {
  return AgentMealBatchWriteIssueSchema.parse({
    ...issue,
    nutrient: null,
    itemIndex,
    entryId
  });
}

function mealValidationIssue(
  issue: AgentMealValidationIssue
): AgentMealBatchWriteIssue {
  return mealLevelIssue({
    field: `meal.${issue.field}`,
    rule: issue.rule,
    message: issue.message,
    limit: issue.limit
  });
}

function buildFoodEntryPayload({
  item,
  name,
  nutrients,
  isLiquid,
  servingLabel,
  servingSize,
  packageSize,
  mealId,
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
  mealId: string;
  kind: "food" | "quickEntry";
  updatedAt: string;
  deletedAt: string | null;
}): Record<string, unknown> {
  return {
    id: item.id,
    meal_id: mealId,
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
