import { createRoute, z } from "@hono/zod-openapi";
import { and, eq, isNotNull, isNull } from "drizzle-orm";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import {
  AgentNutritionReadUnavailableResponseSchema,
  numberValue,
  parseRawPortion,
  stringValue
} from "./agent-nutrition-reads.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import {
  buildFoodHistory,
  type FoodHistoryEntry,
  type FoodHistoryMeal
} from "./food-history.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";

export const AGENT_FOOD_HISTORY_DEFAULT_LIMIT = 50;
export const AGENT_FOOD_HISTORY_MAX_LIMIT = 200;

export const AGENT_FOOD_HISTORY_DESCRIPTION =
  "Returns the distinct Foods the caller has logged, derived on each call from live Food Entries and Meals and never stored, in the same order the app's add-food picker uses: Food Entries in the last 90 days descending, then the most recent Meal, then position in that Meal. Each item carries the Food Source and Food id to look the Food up with listAgentFoods or searchAgentPlatformFoods, the name the Food had when it was last logged, and its Last Portion. Archived User Foods are left out. Bounded by limit.";

export const AgentFoodHistoryQuerySchema = z.object({
  limit: z.coerce
    .number()
    .int()
    .min(1)
    .max(AGENT_FOOD_HISTORY_MAX_LIMIT)
    .default(AGENT_FOOD_HISTORY_DEFAULT_LIMIT)
    .openapi({
      param: { name: "limit", in: "query" },
      description: "Maximum Foods to return, bounded to 200."
    })
});

export const AgentFoodHistoryItemSchema = z
  .object({
    foodSource: z.string().min(1).openapi({
      description:
        "The Food Source name, such as openFoodFacts, as AgentMealEntry.foodSource carries it."
    }),
    foodId: z.string().min(1),
    lastLoggedName: z.string().openapi({
      description: "The name on the latest Food Entry for this Food."
    }),
    recentCount: z.number().int().min(0).openapi({
      description: "Food Entries whose Meal started in the last 90 days."
    }),
    lastLoggedAt: z.string().min(1).openapi({
      description: "ISO-8601 start of the latest Meal this Food was logged in."
    }),
    lastPortion: z
      .object({
        value: z.number(),
        entered: z.string().min(1),
        unit: z.string().min(1)
      })
      .nullable()
      .openapi({
        description:
          "The Last Portion: the Portion of the latest Food Entry for this Food that has one, or null."
      })
  })
  .openapi("AgentFoodHistoryItem");

export const AgentFoodHistoryResponseSchema = z
  .object({
    items: z.array(AgentFoodHistoryItemSchema),
    limit: z.number().int().min(1).max(AGENT_FOOD_HISTORY_MAX_LIMIT),
    totalMatched: z.number().int().min(0)
  })
  .openapi("AgentFoodHistoryResponse");

export const agentFoodHistoryRoute = createRoute({
  method: "get",
  path: "/agent/foods/history",
  operationId: "listAgentFoodHistory",
  tags: ["Agent Reads"],
  summary:
    "List the user's Food History: the Foods they log, most often in the last 90 days first.",
  description: AGENT_FOOD_HISTORY_DESCRIPTION,
  security: [{ bearerAuth: [] }],
  request: {
    query: AgentFoodHistoryQuerySchema
  },
  responses: {
    200: {
      description: "The caller's Food History, bounded by limit.",
      content: {
        "application/json": {
          schema: AgentFoodHistoryResponseSchema
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
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key or read storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentNutritionReadUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export type AgentFoodHistoryQuery = z.infer<typeof AgentFoodHistoryQuerySchema>;
export type AgentFoodHistoryResponse = z.infer<
  typeof AgentFoodHistoryResponseSchema
>;

export type AgentFoodHistoryReadStore = {
  /** The caller's Food History, computed on each call and never stored. */
  listFoodHistory(input: {
    userId: string;
    limit: number;
    now: Date;
  }): Promise<AgentFoodHistoryResponse>;
};

export function createDrizzleAgentFoodHistoryReadStore(
  db: ServerDatabase
): AgentFoodHistoryReadStore {
  return {
    async listFoodHistory({ userId, limit, now }) {
      const [mealRows, entryRows, archivedRows] = await Promise.all([
        db
          .select({ id: schema.meals.id, payload: schema.meals.payload })
          .from(schema.meals)
          .where(
            and(eq(schema.meals.userId, userId), isNull(schema.meals.deletedAt))
          ),
        db
          .select({
            id: schema.foodEntries.id,
            payload: schema.foodEntries.payload
          })
          .from(schema.foodEntries)
          .where(
            and(
              eq(schema.foodEntries.userId, userId),
              isNull(schema.foodEntries.deletedAt)
            )
          ),
        db
          .select({ id: schema.foods.id })
          .from(schema.foods)
          .where(
            and(
              eq(schema.foods.userId, userId),
              isNotNull(schema.foods.deletedAt)
            )
          )
      ]);

      const meals: FoodHistoryMeal[] = mealRows.flatMap((row) => {
        const startedAt = row.payload.started_at;
        return typeof startedAt === "string"
          ? [{ id: row.id, startedAt, deletedAt: null }]
          : [];
      });
      const names = new Map<string, string>();
      const entries: FoodHistoryEntry[] = entryRows.flatMap((row) => {
        const entry = foodHistoryEntryFromPayload(row.id, row.payload);
        if (entry === null) {
          return [];
        }
        names.set(row.id, stringValue(row.payload.name) ?? "");
        return [entry];
      });

      const history = buildFoodHistory({
        entries,
        meals,
        archivedUserFoodIds: archivedRows.map((row) => row.id),
        now
      });

      return AgentFoodHistoryResponseSchema.parse({
        items: history.slice(0, limit).map((record) => ({
          foodSource: record.foodSource,
          foodId: record.foodId,
          lastLoggedName: names.get(record.latestEntryId) ?? "",
          recentCount: record.recentCount,
          lastLoggedAt: record.lastLoggedAt,
          lastPortion: record.lastPortion
        })),
        limit,
        totalMatched: history.length
      });
    }
  };
}

/**
 * A synced Food Entry payload as Food History reads it. The liquid flag is
 * read as stored: a null flag leaves the entry out, as it does in the app, so
 * this does not use the meal read's mapper, which reads null as false.
 */
function foodHistoryEntryFromPayload(
  id: string,
  payload: Record<string, unknown>
): FoodHistoryEntry | null {
  const mealId = stringValue(payload.meal_id);
  const updatedAt = stringValue(payload.updated_at);
  if (mealId === null || updatedAt === null) {
    return null;
  }
  return {
    id,
    mealId,
    kind: stringValue(payload.entry_kind) ?? "quickEntry",
    position: numberValue(payload.position) ?? 0,
    foodSource: stringValue(payload.food_source),
    foodId: stringValue(payload.food_id),
    isLiquid: typeof payload.is_liquid === "boolean" ? payload.is_liquid : null,
    portion: parseRawPortion(payload.portion_json),
    updatedAt,
    deletedAt: null
  };
}
