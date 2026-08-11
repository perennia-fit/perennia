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
  nutrientValidationLimitsResponse,
  validateAgentFoodEntry,
  type AgentNutrientValidationIssue
} from "./agent-validation.js";
import { resolvePortionBaseQuantity } from "./agent-meal-batch-write.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";
import {
  FOODS_SYNC_ENTITY,
  pushFoodsInTransaction,
  type SyncPushChange
} from "./sync.js";
import {
  USDA_FOOD_SEED_FOODS,
  USDA_FOOD_SEED_METADATA
} from "./data/usda-food-seed.generated.js";

// Bounded-read page sizing (data-minimizing by default) — mirrors
// the exercise/protocols catalog list surfaces.
export const AGENT_FOODS_DEFAULT_PAGE_LIMIT = 50;
export const AGENT_FOODS_MAX_PAGE_LIMIT = 100;
export const AGENT_FOODS_DEFAULT_PLATFORM_SEARCH_LIMIT = 20;
export const AGENT_FOODS_MAX_PLATFORM_SEARCH_LIMIT = 50;
export const AGENT_FOOD_BATCH_WRITE_MAX_FOODS = 50;
export const AGENT_FOOD_BATCH_WRITE_MAX_RECIPE_INGREDIENTS = 50;

const ISO8601StringSchema = z.string().min(1).openapi({
  description: "ISO-8601 timestamp."
});

const PortionUnitSchema = z
  .enum(["gram", "milliliter", "ounce", "fluidOunce", "serving", "package"])
  .openapi("AgentFoodPortionUnit");

// `Food Source` (CONTEXT.md, NUTRITION.md §3): a curated registry of where a
// Food's reference data came from. Agent-authored/edited Foods and Recipes are
// always `user` (mirrors the app: only User Library rows are ever mutable
// through this surface — externally-sourced Foods are read-only, and
// customizing one forks a User Food copy, which is exactly what an agent
// batch-write of a new `user` Food represents).
const AgentFoodSourceSchema = z
  .enum(["usda", "openFoodFacts", "user"])
  .openapi("AgentFoodSource");

const AGENT_FOOD_FIELDS = [
  "id",
  "name",
  "foodSource",
  "nutrientsPer100",
  "isLiquid",
  "servingLabel",
  "servingSize",
  "packageSize",
  "isRecipe",
  "recipeServingCount",
  "updatedAt",
  "deletedAt"
] as const;

const AGENT_FOOD_DEFAULT_LIST_FIELDS = [
  "id",
  "name",
  "foodSource",
  "isLiquid",
  "isRecipe"
] as const;

const foodFieldSet = new Set<string>(AGENT_FOOD_FIELDS);

export const AgentFoodNutrientVectorSchema = z
  .record(z.string().min(1), AgentNutrientAmountSchema)
  .openapi({
    description:
      "Self-describing per-100 g/ml nutrient vector keyed by fixed nutrient id. Unknown nutrients stay unknown and are never coerced to zero (NUTRITION.md §4)."
  });

// Read-side amount shape: mirrors the device-canonical storage exactly (every
// fixed nutrient id present, an `unknown` amount always carries explicit
// `value: null, entered: null` — see nutrientVectorStorage below), unlike the
// write-side AgentNutrientAmountSchema whose `unknown` variant leaves
// value/entered simply omittable. Keeping the two separate means the
// write-input contract (agent-validation.ts, shared with meal batch-write)
// never has to accept a nullable value, while a read never has to guess
// whether "unknown" means omitted or explicitly null.
const AgentFoodReadNutrientAmountSchema = z
  .union([
    z.object({
      status: z.literal("complete"),
      value: z.number(),
      entered: z.string().min(1),
      unit: z.string().min(1)
    }),
    z.object({
      status: z.literal("unknown"),
      unit: z.string().min(1),
      value: z.number().nullable().optional(),
      entered: z.string().nullable().optional()
    })
  ])
  .openapi("AgentFoodReadNutrientAmount");

const AgentFoodReadNutrientVectorSchema = z
  .record(z.string().min(1), AgentFoodReadNutrientAmountSchema)
  .openapi({
    description:
      "Self-describing per-100 g/ml nutrient vector keyed by fixed nutrient id, as stored. Unknown nutrients stay unknown and are never coerced to zero (NUTRITION.md §4)."
  });

export const AgentFoodSchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "Stable Food id to use as a meal Food Entry reference."
    }),
    name: z.string().min(1),
    foodSource: AgentFoodSourceSchema,
    nutrientsPer100: AgentFoodReadNutrientVectorSchema,
    isLiquid: z.boolean(),
    servingLabel: z.string().min(1).nullable(),
    servingSize: z.number().positive().nullable(),
    packageSize: z.number().positive().nullable(),
    isRecipe: z.boolean().openapi({
      description:
        "True when this Food is a Recipe (its payload carries a flat ingredient snapshot)."
    }),
    recipeServingCount: z.number().positive().nullable(),
    updatedAt: ISO8601StringSchema,
    deletedAt: ISO8601StringSchema.nullable()
  })
  .openapi("AgentFood");

const AgentFoodFieldSchema = z.enum(AGENT_FOOD_FIELDS).openapi("AgentFoodField");

const AgentFoodListItemSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1),
    foodSource: AgentFoodSourceSchema.optional(),
    nutrientsPer100: AgentFoodReadNutrientVectorSchema.optional(),
    isLiquid: z.boolean().optional(),
    servingLabel: z.string().min(1).nullable().optional(),
    servingSize: z.number().positive().nullable().optional(),
    packageSize: z.number().positive().nullable().optional(),
    isRecipe: z.boolean().optional(),
    recipeServingCount: z.number().positive().nullable().optional(),
    updatedAt: ISO8601StringSchema.optional(),
    deletedAt: ISO8601StringSchema.nullable().optional()
  })
  .openapi("AgentFoodListItem");

export const AgentFoodListQuerySchema = z.object({
  search: z.string().trim().min(1).optional().openapi({
    param: { name: "search", in: "query" },
    description: "Optional case-insensitive Food/Recipe name filter."
  }),
  includeArchived: z.coerce.boolean().default(false).openapi({
    param: { name: "includeArchived", in: "query" },
    description: "When true, archived Foods are included."
  }),
  limit: z.coerce
    .number()
    .int()
    .min(1)
    .max(AGENT_FOODS_MAX_PAGE_LIMIT)
    .default(AGENT_FOODS_DEFAULT_PAGE_LIMIT)
    .openapi({
      param: { name: "limit", in: "query" },
      description: "Maximum Food rows to return, bounded to 100."
    }),
  cursor: z.string().trim().min(1).optional().openapi({
    param: { name: "cursor", in: "query" },
    description: "Opaque pagination cursor returned by the previous page."
  }),
  fields: z
    .string()
    .trim()
    .min(1)
    .optional()
    .refine(
      (value) =>
        value === undefined ||
        value
          .split(",")
          .map((field) => field.trim())
          .every((field) => foodFieldSet.has(field)),
      "fields must be a comma-separated list of known Food fields"
    )
    .openapi({
      param: { name: "fields", in: "query" },
      description:
        "Comma-separated list of additional fields. id and name are always returned."
    })
});

export const AgentFoodListResponseSchema = z
  .object({
    foods: z.array(AgentFoodListItemSchema),
    limit: z.number().int().min(1).max(AGENT_FOODS_MAX_PAGE_LIMIT),
    nextCursor: z.string().min(1).nullable(),
    fields: z.array(AgentFoodFieldSchema)
  })
  .openapi("AgentFoodListResponse");

// ---------------------------------------------------------------------------
// Platform Food search (USDA) — the SAME bundled CC0 dataset the app ships,
// served server-side from a generated seed module so an agent and
// the app resolve identical USDA results. Open Food Facts is NOT proxied by
// this slice: it is a live-query + per-user-cache external API,
// which does not fit a deterministic, network-free server read; the response
// shape below reserves room for it (source is already a field) without
// committing to a rate-limited external proxy in v1.
// ---------------------------------------------------------------------------

const AgentPlatformFoodSourceSchema = z.enum(["usda"]).openapi(
  "AgentPlatformFoodSource"
);

export const AgentPlatformFoodSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1),
    foodSource: AgentPlatformFoodSourceSchema,
    nutrientsPer100: AgentFoodReadNutrientVectorSchema,
    isLiquid: z.boolean(),
    servingLabel: z.string().min(1).nullable(),
    servingSize: z.number().positive().nullable(),
    packageSize: z.number().positive().nullable()
  })
  .openapi("AgentPlatformFood");

export const AgentPlatformFoodAttributionSchema = z
  .object({
    source: AgentPlatformFoodSourceSchema,
    datasetVersion: z.string().min(1),
    sourceName: z.string().min(1),
    sourceUrl: z.string().min(1),
    licenseName: z.string().min(1),
    attributionText: z.string().min(1)
  })
  .openapi("AgentPlatformFoodAttribution");

export const AgentFoodPlatformSearchQuerySchema = z.object({
  search: z.string().trim().min(1).optional().openapi({
    param: { name: "search", in: "query" },
    description:
      "Optional case-insensitive name filter. Omit to list the bundled catalog."
  }),
  source: AgentPlatformFoodSourceSchema.default("usda").openapi({
    param: { name: "source", in: "query" },
    description:
      "Platform Food source. Only usda is available in this slice — the bundled, offline CC0 dataset."
  }),
  limit: z.coerce
    .number()
    .int()
    .min(1)
    .max(AGENT_FOODS_MAX_PLATFORM_SEARCH_LIMIT)
    .default(AGENT_FOODS_DEFAULT_PLATFORM_SEARCH_LIMIT)
    .openapi({
      param: { name: "limit", in: "query" },
      description: "Maximum Platform Food rows to return, bounded to 50."
    })
});

export const AgentFoodPlatformSearchResponseSchema = z
  .object({
    foods: z.array(AgentPlatformFoodSchema),
    limit: z.number().int().min(1).max(AGENT_FOODS_MAX_PLATFORM_SEARCH_LIMIT),
    attribution: AgentPlatformFoodAttributionSchema.openapi({
      description:
        "Required attribution for the source dataset. USDA is CC0/public domain; courtesy attribution is still surfaced here."
    })
  })
  .openapi("AgentFoodPlatformSearchResponse");

export const AgentFoodsUnavailableResponseSchema = z
  .object({
    code: z.literal("agent_foods_unavailable"),
    message: z.string().min(1)
  })
  .openapi("AgentFoodsUnavailableResponse");

export const agentFoodListRoute = createRoute({
  method: "get",
  path: "/agent/foods",
  operationId: "listAgentFoods",
  tags: ["Agent Catalog"],
  summary: "Search or list the caller's Food library (User Foods and Recipes).",
  description:
    "Bounded, data-minimizing read (limit/cursor/fields) over the caller's own synced User Library Foods and Recipes. Platform reference data (USDA/Open Food Facts) is never in this table — use GET /agent/foods/platform-search for that.",
  security: [{ bearerAuth: [] }],
  request: { query: AgentFoodListQuerySchema },
  responses: {
    200: {
      description: "A bounded page of the caller's Foods and Recipes.",
      content: { "application/json": { schema: AgentFoodListResponseSchema } }
    },
    401: {
      description: "The request is missing a valid agent API key.",
      content: {
        "application/json": { schema: AgentUnauthorizedResponseSchema }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key or Food storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentFoodsUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export const agentFoodPlatformSearchRoute = createRoute({
  method: "get",
  path: "/agent/foods/platform-search",
  operationId: "searchAgentPlatformFoods",
  tags: ["Agent Catalog"],
  summary: "Search the bundled USDA Platform Food reference dataset.",
  description:
    "Serves the SAME bundled USDA FoodData Central seed the app ships, so an agent and the app resolve identical generic-food nutrient facts offline of any external network call. CC0/public domain; courtesy attribution is still included in the response. Open Food Facts (branded/barcode) is not available through this operation in this slice.",
  security: [{ bearerAuth: [] }],
  request: { query: AgentFoodPlatformSearchQuerySchema },
  responses: {
    200: {
      description: "A bounded page of matching Platform Foods with attribution.",
      content: {
        "application/json": { schema: AgentFoodPlatformSearchResponseSchema }
      }
    },
    401: {
      description: "The request is missing a valid agent API key.",
      content: {
        "application/json": { schema: AgentUnauthorizedResponseSchema }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key storage is not configured.",
      content: {
        "application/json": { schema: AgentApiKeyUnavailableResponseSchema }
      }
    }
  }
});

// ---------------------------------------------------------------------------
// Batch-write (create/edit/archive User Foods and Recipes)
// ---------------------------------------------------------------------------

const AgentFoodBatchWriteRecipeIngredientSchema = z
  .object({
    foodId: z.string().min(1).openapi({
      description: "Reference Food id this ingredient snapshots from."
    }),
    name: z.string().trim().min(1),
    foodSource: AgentFoodSourceSchema,
    nutrientsPer100: AgentFoodNutrientVectorSchema,
    isLiquid: z.boolean(),
    portion: z
      .object({
        value: z.number().positive(),
        entered: z.string().trim().min(1),
        unit: PortionUnitSchema
      })
      .openapi("AgentFoodBatchWriteRecipeIngredientPortion"),
    servingLabel: z.string().trim().min(1).nullable().default(null),
    servingSize: z.number().positive().nullable().default(null),
    packageSize: z.number().positive().nullable().default(null)
  })
  .openapi("AgentFoodBatchWriteRecipeIngredient");

export const AgentFoodBatchWriteFoodSchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "Client-supplied UUIDv7 Food id."
    }),
    name: z.string().trim().min(1),
    nutrientsPer100: AgentFoodNutrientVectorSchema.openapi({
      description:
        "Per-100 g/ml nutrient vector for a plain User Food. Ignored for a Recipe (recipeIngredients set): the server derives the Recipe's own nutrientsPer100 from its ingredients instead, mirroring the app's deriveRecipeNutrition()."
    }),
    isLiquid: z.boolean().default(false).openapi({
      description:
        "Ignored for a Recipe, which is always stored as not-liquid (mirrors the app)."
    }),
    servingLabel: z.string().trim().min(1).nullable().default(null).openapi({
      description:
        "Ignored for a Recipe, which always stores the generic 'serving' label (mirrors the app)."
    }),
    servingSize: z.number().positive().nullable().default(null).openapi({
      description:
        "Ignored for a Recipe: the server derives servingSize from recipeIngredients/recipeServingCount instead (mirrors the app's deriveRecipeNutrition())."
    }),
    packageSize: z.number().positive().nullable().default(null).openapi({
      description: "Ignored for a Recipe, which is never a package Food."
    }),
    recipeIngredients: z
      .array(AgentFoodBatchWriteRecipeIngredientSchema)
      .max(AGENT_FOOD_BATCH_WRITE_MAX_RECIPE_INGREDIENTS)
      .nullable()
      .default(null)
      .openapi({
        description:
          "Set (non-empty) to make this Food a Recipe: a flat, self-describing snapshot of its ingredients at save time. Null for a plain User Food. Recipe nesting is not supported, mirroring the app's flat v1 composition. When set, the server derives this Recipe's nutrientsPer100/servingSize/isLiquid/servingLabel/packageSize from the ingredients and recipeServingCount — CONTEXT.md defines a Recipe's nutrition as derived from its ingredients, never caller-supplied verbatim."
      }),
    recipeServingCount: z.number().positive().nullable().default(null).openapi({
      description: "Required alongside recipeIngredients; null for a plain Food."
    }),
    updatedAt: ISO8601StringSchema.optional().openapi({
      description:
        "Client-observed row update clock. Defaults to the server receive time when omitted."
    }),
    deletedAt: ISO8601StringSchema.nullable().default(null).openapi({
      description:
        "Nullable archive tombstone. Setting it is an ordinary LWW write of a tombstone — never a purge. Any Meal Entries that reference this Food keep their own self-describing snapshot untouched."
    })
  })
  .openapi("AgentFoodBatchWriteFood");

export const AgentFoodBatchWriteRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200).openapi({
      description:
        "Stable key for this agent request. Replays with the same key return the original result without appending another Activity Log batch."
    }),
    foods: z
      .array(AgentFoodBatchWriteFoodSchema)
      .min(1)
      .max(AGENT_FOOD_BATCH_WRITE_MAX_FOODS)
      .openapi({
        description:
          "User Foods and Recipes to create, edit, or archive atomically as one Activity Log batch."
      })
  })
  .openapi("AgentFoodBatchWriteRequest");

export const AgentFoodBatchWriteIssueSchema = AgentNutrientValidationIssueSchema
  .extend({
    itemIndex: z.number().int().min(0).openapi({
      description: "Index of the Food item that produced the issue."
    }),
    foodId: z.string().min(1).openapi({
      description: "Client-supplied Food id for the failed item."
    })
  })
  .openapi("AgentFoodBatchWriteIssue");

export const AgentFoodBatchWriteResultSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1),
    isRecipe: z.boolean(),
    warnings: z.array(AgentNutrientValidationIssueSchema)
  })
  .openapi("AgentFoodBatchWriteResult");

export const AgentFoodBatchWriteResponseSchema = z
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
    serverClock: z.string().min(1),
    foods: z.array(AgentFoodBatchWriteResultSchema)
  })
  .openapi("AgentFoodBatchWriteResponse");

export const AgentFoodBatchWriteErrorResponseSchema = z
  .object({
    code: z.literal("agent_food_batch_write_failed"),
    message: z.string().min(1),
    errors: z.array(AgentFoodBatchWriteIssueSchema),
    warnings: z.array(AgentFoodBatchWriteIssueSchema),
    limits: AgentNutrientValidationLimitsSchema
  })
  .openapi("AgentFoodBatchWriteErrorResponse");

export const agentFoodBatchWriteRoute = createRoute({
  method: "post",
  path: "/agent/foods/batch-write",
  operationId: "batchWriteAgentFoods",
  tags: ["Agent Writes"],
  summary:
    "Batch-write User Foods and Recipes (create, edit, archive) as one Activity Log batch.",
  description:
    "Authenticated agent write path for the food library. Only User Library rows are ever mutable through this op (mirrors the app: externally-sourced Foods are read-only and customizing one forks a User Food copy) — payload shape matches the synced foods row so devices pull agent writes as ordinary edits. Nutrient vectors are validated by the shared two-tier nutrient validator; missing nutrients stay unknown and are never coerced to zero.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": { schema: AgentFoodBatchWriteRequestSchema }
      }
    }
  },
  responses: {
    200: {
      description:
        "The batch was accepted, or recognized as an idempotent replay.",
      content: {
        "application/json": { schema: AgentFoodBatchWriteResponseSchema }
      }
    },
    401: {
      description: "The request is missing a valid agent API key.",
      content: {
        "application/json": { schema: AgentUnauthorizedResponseSchema }
      }
    },
    422: {
      description:
        "One or more Foods failed hard validation; no rows were written.",
      content: {
        "application/json": { schema: AgentFoodBatchWriteErrorResponseSchema }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key or Food batch write storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentFoodsUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export type AgentFoodListField = z.infer<typeof AgentFoodFieldSchema>;
export type AgentFoodListQuery = z.infer<typeof AgentFoodListQuerySchema>;
export type AgentFoodListResponse = z.infer<typeof AgentFoodListResponseSchema>;
export type AgentFoodPlatformSearchQuery = z.infer<
  typeof AgentFoodPlatformSearchQuerySchema
>;
export type AgentFoodPlatformSearchResponse = z.infer<
  typeof AgentFoodPlatformSearchResponseSchema
>;
export type AgentFoodBatchWriteRequest = z.infer<
  typeof AgentFoodBatchWriteRequestSchema
>;
export type AgentFoodBatchWriteFood = z.infer<
  typeof AgentFoodBatchWriteFoodSchema
>;
export type AgentFoodBatchWriteIssue = z.infer<
  typeof AgentFoodBatchWriteIssueSchema
>;
export type AgentFoodBatchWriteResult = z.infer<
  typeof AgentFoodBatchWriteResultSchema
>;

export type AgentFoodBatchPreparedRow = {
  id: string;
  updatedAt: string;
  deletedAt: string | null;
  payload: Record<string, unknown>;
};
export type AgentFoodBatchPreparation =
  | {
      accepted: true;
      foods: AgentFoodBatchPreparedRow[];
      responseFoods: AgentFoodBatchWriteResult[];
    }
  | {
      accepted: false;
      errors: AgentFoodBatchWriteIssue[];
      warnings: AgentFoodBatchWriteIssue[];
    };

export type AgentFoodBatchWriteStore = {
  writeFoodBatch(input: {
    userId: string;
    batchId: string;
    correlationId?: string;
    deviceId: string;
    foods: AgentFoodBatchPreparedRow[];
  }): Promise<{
    duplicate: boolean;
    serverClock: string;
    applied: { id: string; updatedAt: string; deviceId: string }[];
  }>;
};

export type AgentFoodCatalogRow = {
  id: string;
  updatedAt: Date;
  deletedAt: Date | null;
  payload: Record<string, unknown>;
};

export type AgentFoodCatalogStore = {
  listFoods(input: {
    userId: string;
    search?: string;
    includeArchived: boolean;
    limit: number;
    cursor?: string;
    fields: AgentFoodListField[];
  }): Promise<AgentFoodListResponse>;
  getFoodById(input: {
    userId: string;
    foodId: string;
  }): Promise<AgentFoodSchemaType | null>;
};

type AgentFoodSchemaType = z.infer<typeof AgentFoodSchema>;

export function prepareAgentFoodBatchWrite({
  request,
  now = new Date()
}: {
  request: AgentFoodBatchWriteRequest;
  now?: Date;
}): AgentFoodBatchPreparation {
  const errors: AgentFoodBatchWriteIssue[] = [];
  const warnings: AgentFoodBatchWriteIssue[] = [];
  const preparedFoods: AgentFoodBatchPreparedRow[] = [];
  const responseFoods: AgentFoodBatchWriteResult[] = [];
  const nowIso = now.toISOString();
  const seenIds = new Set<string>();

  for (const [itemIndex, item] of request.foods.entries()) {
    if (seenIds.has(item.id)) {
      errors.push(
        foodIssue(itemIndex, item.id, {
          field: `foods[${itemIndex}].id`,
          nutrient: null,
          rule: "duplicate_food_id",
          message: "A Food id may appear only once per batch.",
          limit: null
        })
      );
      continue;
    }
    seenIds.add(item.id);

    const isRecipe = item.recipeIngredients !== null;
    if (isRecipe && item.recipeIngredients!.length === 0) {
      errors.push(
        foodIssue(itemIndex, item.id, {
          field: `foods[${itemIndex}].recipeIngredients`,
          nutrient: null,
          rule: "recipe_requires_ingredients",
          message: "A Recipe requires at least one ingredient.",
          limit: null
        })
      );
      continue;
    }
    if (isRecipe && item.recipeServingCount === null) {
      errors.push(
        foodIssue(itemIndex, item.id, {
          field: `foods[${itemIndex}].recipeServingCount`,
          nutrient: null,
          rule: "recipe_requires_serving_count",
          message: "A Recipe requires a positive recipeServingCount.",
          limit: null
        })
      );
      continue;
    }
    if (!isRecipe && item.recipeServingCount !== null) {
      errors.push(
        foodIssue(itemIndex, item.id, {
          field: `foods[${itemIndex}].recipeServingCount`,
          nutrient: null,
          rule: "plain_food_forbids_serving_count",
          message: "A plain Food must not carry a recipeServingCount.",
          limit: null
        })
      );
      continue;
    }

    // A Recipe's own nutritional facts are never caller-supplied — CONTEXT.md:
    // a Recipe's "nutrition is derived from its ingredients," and the app
    // enforces this mechanically (deriveRecipeNutrition() in
    // apps/mobile/lib/domain/nutrition/nutrition.dart). Validate the
    // top-level vector only for a plain Food; for a Recipe the top-level
    // vector supplied by the caller is discarded below in favor of the
    // derived one, so validating it here would be pointless (and could
    // surface errors/warnings about a value that never gets stored).
    const validation = isRecipe
      ? { errors: [], warnings: [] }
      : validateAgentFoodEntry({ nutrients: item.nutrientsPer100 });
    for (const warning of validation.warnings) {
      warnings.push(foodIssue(itemIndex, item.id, warning));
    }
    for (const error of validation.errors) {
      errors.push(foodIssue(itemIndex, item.id, error));
    }

    let ingredientError = false;
    if (isRecipe) {
      for (const [
        ingredientIndex,
        ingredient
      ] of item.recipeIngredients!.entries()) {
        const ingredientValidation = validateAgentFoodEntry({
          nutrients: ingredient.nutrientsPer100
        });
        for (const warning of ingredientValidation.warnings) {
          warnings.push(
            foodIssue(itemIndex, item.id, {
              ...warning,
              field: `foods[${itemIndex}].recipeIngredients[${ingredientIndex}].${warning.field}`
            })
          );
        }
        for (const error of ingredientValidation.errors) {
          errors.push(
            foodIssue(itemIndex, item.id, {
              ...error,
              field: `foods[${itemIndex}].recipeIngredients[${ingredientIndex}].${error.field}`
            })
          );
          ingredientError = true;
        }
      }
    }

    if (validation.errors.length > 0 || ingredientError) {
      continue;
    }

    let derivedRecipe: DerivedRecipeNutrition | null = null;
    if (isRecipe) {
      const derivation = deriveRecipeNutrition({
        ingredients: item.recipeIngredients!,
        servingCount: item.recipeServingCount!
      });
      if (!derivation.ok) {
        errors.push(
          foodIssue(itemIndex, item.id, {
            field: `foods[${itemIndex}].recipeIngredients[${derivation.ingredientIndex}].portion.unit`,
            nutrient: null,
            rule: "recipe_ingredient_portion_unavailable",
            message:
              "Recipe ingredient portion is not available (missing serving or package size snapshot).",
            limit: derivation.unit
          })
        );
        continue;
      }
      derivedRecipe = derivation.value;
    }

    const updatedAt = item.updatedAt ?? nowIso;
    const deletedAt = item.deletedAt ?? null;
    const payload = buildFoodPayload({
      item,
      updatedAt,
      deletedAt,
      derivedRecipe
    });
    preparedFoods.push({ id: item.id, updatedAt, deletedAt, payload });
    responseFoods.push(
      AgentFoodBatchWriteResultSchema.parse({
        id: item.id,
        name: item.name,
        isRecipe,
        warnings: validation.warnings
      })
    );
  }

  if (errors.length > 0) {
    return { accepted: false, errors, warnings };
  }

  return { accepted: true, foods: preparedFoods, responseFoods };
}

export function createDrizzleAgentFoodBatchWriteStore(
  db: ServerDatabase
): AgentFoodBatchWriteStore {
  return {
    async writeFoodBatch({ userId, batchId, deviceId, foods }) {
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

        const foodChanges: SyncPushChange[] = [];
        for (const food of foods) {
          const beforeImage = await readFoodBeforeImage({
            transaction,
            userId,
            rowId: food.id
          });
          foodChanges.push({
            id: food.id,
            payload: food.payload,
            updatedAt: food.updatedAt,
            deletedAt: food.deletedAt,
            activityLogId: `agent:${batchId}:${food.id}`,
            actor: "agent",
            batchId,
            beforeImage,
            afterImage: food.payload,
            occurredAt: food.updatedAt
          });
        }

        const result = await pushFoodsInTransaction(transaction, {
          userId,
          deviceId,
          changes: foodChanges,
          serverClock
        });

        return {
          duplicate: false,
          serverClock: result.serverClock,
          applied: result.applied
        };
      });
    }
  };
}

export function createDrizzleAgentFoodCatalogStore(
  db: ServerDatabase
): AgentFoodCatalogStore {
  return {
    async listFoods({ userId, search, includeArchived, limit, cursor, fields }) {
      const rows = await db
        .select({
          id: schema.foods.id,
          payload: schema.foods.payload,
          updatedAt: schema.foods.updatedAt,
          deletedAt: schema.foods.deletedAt
        })
        .from(schema.foods)
        .where(eq(schema.foods.userId, userId))
        .orderBy(asc(schema.foods.updatedAt), asc(schema.foods.id));

      return listFoodsFromRows(
        rows.map((row) => ({
          id: row.id,
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          payload: row.payload ?? {}
        })),
        { search, includeArchived, limit, cursor, fields }
      );
    },
    async getFoodById({ userId, foodId }) {
      const rows = await db
        .select({
          id: schema.foods.id,
          payload: schema.foods.payload,
          updatedAt: schema.foods.updatedAt,
          deletedAt: schema.foods.deletedAt
        })
        .from(schema.foods)
        .where(and(eq(schema.foods.id, foodId), eq(schema.foods.userId, userId)))
        .limit(1);

      const row = rows[0];
      if (row === undefined) {
        return null;
      }

      return toAgentFood({
        id: row.id,
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
        payload: row.payload ?? {}
      });
    }
  };
}

/**
 * In-memory projection shared by the Drizzle store and tests: identical
 * search/pagination/field-selection semantics regardless of backing storage,
 * mirroring the exercise catalog's split between DB fetch and pure
 * list/filter/paginate logic.
 */
export function listFoodsFromRows(
  rows: readonly AgentFoodCatalogRow[],
  {
    search,
    includeArchived,
    limit,
    cursor,
    fields
  }: {
    search?: string;
    includeArchived: boolean;
    limit: number;
    cursor?: string;
    fields: AgentFoodListField[];
  }
): AgentFoodListResponse {
  const normalizedFields = normalizeFieldSelection(fields);
  const matched = rows
    .filter((row) => includeArchived || row.deletedAt === null)
    .filter((row) => matchesSearch(row.payload, search));
  const offset = parseCursor(cursor);
  const page = matched.slice(offset, offset + limit);
  const nextOffset = offset + limit;

  return AgentFoodListResponseSchema.parse({
    foods: page.map((row) => projectFood(row, normalizedFields)),
    limit,
    nextCursor: nextOffset < matched.length ? String(nextOffset) : null,
    fields: normalizedFields
  });
}

export function toAgentFood(row: AgentFoodCatalogRow): AgentFoodSchemaType {
  const payload = row.payload;
  const recipeIngredientsRaw = payload.recipe_ingredients_json;
  const isRecipe =
    typeof recipeIngredientsRaw === "string" && recipeIngredientsRaw.length > 0;

  return AgentFoodSchema.parse({
    id: row.id,
    name: typeof payload.name === "string" ? payload.name : "",
    foodSource:
      typeof payload.food_source === "string" ? payload.food_source : "user",
    nutrientsPer100: parseNutrientVector(payload.nutrient_values_json),
    isLiquid: payload.is_liquid === true,
    servingLabel:
      typeof payload.serving_label === "string" ? payload.serving_label : null,
    servingSize:
      typeof payload.serving_size === "number" ? payload.serving_size : null,
    packageSize:
      typeof payload.package_size === "number" ? payload.package_size : null,
    isRecipe,
    recipeServingCount:
      typeof payload.recipe_serving_count === "number"
        ? payload.recipe_serving_count
        : null,
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt === null ? null : row.deletedAt.toISOString()
  });
}

function parseNutrientVector(raw: unknown): Record<string, unknown> {
  if (typeof raw !== "string" || raw.length === 0) {
    return {};
  }
  try {
    const parsed = JSON.parse(raw) as unknown;
    return typeof parsed === "object" && parsed !== null
      ? (parsed as Record<string, unknown>)
      : {};
  } catch {
    return {};
  }
}

function matchesSearch(payload: Record<string, unknown>, search?: string) {
  if (search === undefined) {
    return true;
  }
  const name = typeof payload.name === "string" ? payload.name : "";
  const queryKey = normalizeName(search);
  const nameKey = normalizeName(name);
  return nameKey.includes(queryKey) || queryKey.includes(nameKey);
}

function projectFood(
  row: AgentFoodCatalogRow,
  fields: readonly AgentFoodListField[]
) {
  const fullFood = toAgentFood(row);
  const selected: Partial<Record<AgentFoodListField, unknown>> = {
    id: fullFood.id,
    name: fullFood.name
  };
  for (const field of fields) {
    selected[field] = fullFood[field];
  }
  return selected;
}

function normalizeFieldSelection(
  fields: readonly AgentFoodListField[]
): AgentFoodListField[] {
  return [...new Set<AgentFoodListField>(["id", "name", ...fields])];
}

export function parseAgentFoodListQuery(
  query: AgentFoodListQuery
): Omit<Parameters<AgentFoodCatalogStore["listFoods"]>[0], "userId"> {
  return {
    search: query.search,
    includeArchived: query.includeArchived,
    limit: query.limit,
    cursor: query.cursor,
    fields: resolveFieldSelection(query.fields)
  };
}

function resolveFieldSelection(rawFields: string | undefined) {
  if (rawFields === undefined) {
    return [...AGENT_FOOD_DEFAULT_LIST_FIELDS];
  }
  return normalizeFieldSelection(
    rawFields
      .split(",")
      .map((field) => field.trim())
      .filter((field): field is AgentFoodListField =>
        (AGENT_FOOD_FIELDS as readonly string[]).includes(field)
      )
  );
}

function parseCursor(cursor: string | undefined) {
  if (cursor === undefined) {
    return 0;
  }
  const parsed = Number.parseInt(cursor, 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
}

function normalizeName(value: string) {
  return value.trim().toLocaleLowerCase("en-US").replace(/\s+/g, " ");
}

function buildFoodPayload({
  item,
  updatedAt,
  deletedAt,
  derivedRecipe
}: {
  item: AgentFoodBatchWriteFood;
  updatedAt: string;
  deletedAt: string | null;
  derivedRecipe: DerivedRecipeNutrition | null;
}): Record<string, unknown> {
  const isRecipe = item.recipeIngredients !== null;
  // A Recipe's nutritionsPer100/servingSize/isLiquid/servingLabel/packageSize
  // are derived server-side (never caller-supplied verbatim) — mirrors the
  // app's FoodsCompanion construction for a saved Recipe exactly (always
  // isLiquid=false, servingLabel="serving", packageSize=null; nutrientsPer100
  // and servingSize computed from the ingredients).
  const nutrientsPer100 = derivedRecipe
    ? derivedRecipe.nutrientsPer100
    : item.nutrientsPer100;
  const isLiquid = derivedRecipe ? false : item.isLiquid;
  const servingLabel = derivedRecipe ? "serving" : item.servingLabel;
  const servingSize = derivedRecipe ? derivedRecipe.servingSize : item.servingSize;
  const packageSize = derivedRecipe ? null : item.packageSize;
  return {
    id: item.id,
    name: item.name,
    food_source: "user",
    nutrient_values_json: JSON.stringify(nutrientVectorStorage(nutrientsPer100)),
    is_liquid: isLiquid,
    serving_label: servingLabel,
    serving_size: servingSize,
    package_size: packageSize,
    recipe_ingredients_json: isRecipe
      ? JSON.stringify(
          item.recipeIngredients!.map((ingredient) => ({
            food_id: ingredient.foodId,
            name: ingredient.name,
            food_source: ingredient.foodSource,
            nutrient_values: nutrientVectorStorage(ingredient.nutrientsPer100),
            is_liquid: ingredient.isLiquid,
            serving_label: ingredient.servingLabel,
            serving_size: ingredient.servingSize,
            package_size: ingredient.packageSize,
            portion: {
              value: ingredient.portion.value,
              entered: ingredient.portion.entered,
              unit: ingredient.portion.unit
            }
          }))
        )
      : null,
    recipe_serving_count: item.recipeServingCount,
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
 * the device-canonical `nutrient_values_json` shape (mirrors
 * agent-meal-batch-write.ts's nutrientVectorStorage — same rules, applied to a
 * Food's per-100 vector instead of a Food Entry's logged vector).
 */
function nutrientVectorStorage(
  nutrients: Record<string, z.infer<typeof AgentNutrientAmountSchema>>
): Record<string, Record<string, unknown>> {
  const storage: Record<string, Record<string, unknown>> = {};
  for (const key of NUTRIENT_STORAGE_KEYS) {
    const amount = nutrients[key];
    const unit = amount?.unit ?? NUTRIENT_DEFAULT_UNIT[key];
    if (amount === undefined || amount.status === "unknown") {
      storage[key] = { status: "unknown", value: null, entered: null, unit };
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

type AgentFoodBatchWriteRecipeIngredient = z.infer<
  typeof AgentFoodBatchWriteRecipeIngredientSchema
>;
type AgentNutrientAmount = z.infer<typeof AgentNutrientAmountSchema>;

export type DerivedRecipeNutrition = {
  nutrientsPer100: Record<string, AgentNutrientAmount>;
  servingSize: number;
};

type DeriveRecipeNutritionResult =
  | { ok: true; value: DerivedRecipeNutrition }
  | { ok: false; ingredientIndex: number; unit: string };

/**
 * Derive a Recipe's own `nutrientsPer100`/`servingSize` from its ingredient
 * snapshot, the SAME computation the app performs mechanically
 * (deriveRecipeNutrition() in apps/mobile/lib/domain/nutrition/nutrition.dart)
 * — a Recipe's advertised facts are never trusted verbatim from the caller
 * (CONTEXT.md: Recipe nutrition "is derived from its ingredients"). Each
 * ingredient's portion is resolved to a base quantity in grams/milliliters
 * (resolvePortionBaseQuantity, shared with meal batch-write's portion
 * resolution), weighted, and summed; a per-100 nutrient stays `unknown` if
 * ANY ingredient is missing it (never coerced to zero, NUTRITION.md §4).
 */
function deriveRecipeNutrition({
  ingredients,
  servingCount
}: {
  ingredients: readonly AgentFoodBatchWriteRecipeIngredient[];
  servingCount: number;
}): DeriveRecipeNutritionResult {
  const resolvedQuantities: number[] = [];
  for (const [ingredientIndex, ingredient] of ingredients.entries()) {
    const resolved = resolvePortionBaseQuantity(ingredient.portion, {
      servingSize: ingredient.servingSize,
      packageSize: ingredient.packageSize
    });
    if (resolved === undefined || !Number.isFinite(resolved) || resolved <= 0) {
      return {
        ok: false,
        ingredientIndex,
        unit: ingredient.portion.unit
      };
    }
    resolvedQuantities.push(resolved);
  }

  const totalBaseQuantity = resolvedQuantities.reduce(
    (total, quantity) => total + quantity,
    0
  );

  const nutrientsPer100: Record<string, AgentNutrientAmount> = {};
  for (const key of NUTRIENT_STORAGE_KEYS) {
    // NUTRIENT_DEFAULT_UNIT is a fixed lookup covering every key in
    // NUTRIENT_STORAGE_KEYS with a valid unit string; widen it back to the
    // strict unit union here (mirrors the loose typing nutrientVectorStorage
    // already tolerates for the same table).
    const unit = NUTRIENT_DEFAULT_UNIT[key] as AgentNutrientAmount["unit"];
    let total = 0;
    let hasUnknown = false;
    for (const [index, ingredient] of ingredients.entries()) {
      const amount = ingredient.nutrientsPer100[key];
      if (amount === undefined || amount.status === "unknown") {
        hasUnknown = true;
        break;
      }
      total += (amount.value * resolvedQuantities[index]) / 100;
    }
    if (hasUnknown) {
      nutrientsPer100[key] = { status: "unknown", unit };
      continue;
    }
    const per100 = (total / totalBaseQuantity) * 100;
    nutrientsPer100[key] = {
      status: "complete",
      value: per100,
      entered: formatDerivedNutrientValue(per100),
      unit
    };
  }

  return {
    ok: true,
    value: {
      nutrientsPer100,
      servingSize: totalBaseQuantity / servingCount
    }
  };
}

/**
 * Mirrors the app's derived-value formatting (a derived amount still needs
 * an `entered` string for the self-describing vector shape) — a fixed
 * precision is sufficient here since this value is never user-edited.
 */
function formatDerivedNutrientValue(value: number): string {
  return Number.isInteger(value) ? String(value) : value.toFixed(4);
}

async function readFoodBeforeImage({
  transaction,
  userId,
  rowId
}: {
  transaction: Pick<ServerDatabase, "select">;
  userId: string;
  rowId: string;
}) {
  const existingRows = await transaction
    .select({ userId: schema.foods.userId, payload: schema.foods.payload })
    .from(schema.foods)
    .where(eq(schema.foods.id, rowId))
    .limit(1);
  const existing = existingRows[0];
  if (existing === undefined || existing.userId !== userId) {
    return null;
  }
  return existing.payload;
}

function foodIssue(
  itemIndex: number,
  foodId: string,
  issue: AgentNutrientValidationIssue
): AgentFoodBatchWriteIssue {
  return AgentFoodBatchWriteIssueSchema.parse({
    ...issue,
    field: issue.field.startsWith("foods[")
      ? issue.field
      : `foods[${itemIndex}].${issue.field}`,
    itemIndex,
    foodId
  });
}

// ---------------------------------------------------------------------------
// Platform Food search (bundled USDA seed, /0031)
// ---------------------------------------------------------------------------

function toPlatformFood(
  food: (typeof USDA_FOOD_SEED_FOODS)[number]
): z.infer<typeof AgentPlatformFoodSchema> {
  return AgentPlatformFoodSchema.parse({
    id: food.id,
    name: food.name,
    foodSource: "usda",
    nutrientsPer100: food.nutrientsPer100,
    isLiquid: food.isLiquid,
    servingLabel: food.servingLabel,
    servingSize: food.servingSize,
    packageSize: food.packageSize
  });
}

export function searchAgentPlatformFoods({
  search,
  limit
}: {
  search?: string;
  limit: number;
}): AgentFoodPlatformSearchResponse {
  const queryKey = search === undefined ? undefined : normalizeName(search);
  const matched = USDA_FOOD_SEED_FOODS.filter((food) => {
    if (queryKey === undefined) {
      return true;
    }
    const nameKey = normalizeName(food.name);
    return nameKey.includes(queryKey) || queryKey.includes(nameKey);
  }).slice(0, limit);

  return AgentFoodPlatformSearchResponseSchema.parse({
    foods: matched.map(toPlatformFood),
    limit,
    attribution: {
      source: "usda",
      datasetVersion: USDA_FOOD_SEED_METADATA.datasetVersion,
      sourceName: USDA_FOOD_SEED_METADATA.sourceName,
      sourceUrl: USDA_FOOD_SEED_METADATA.sourceUrl,
      licenseName: USDA_FOOD_SEED_METADATA.licenseName,
      attributionText: USDA_FOOD_SEED_METADATA.attributionText
    }
  });
}

export function nutrientValidationLimitsForFoods() {
  return nutrientValidationLimitsResponse();
}

export { FOODS_SYNC_ENTITY as AGENT_FOODS_ENTITY };
