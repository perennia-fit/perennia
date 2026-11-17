import { createRoute, z } from "@hono/zod-openapi";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import {
  AgentNutritionReadUnavailableResponseSchema,
  parseRawPortion,
  stringValue
} from "./agent-nutrition-reads.js";
import type { ServerDatabase } from "./db/client.js";
import {
  buildFoodHistory,
  type FoodHistoryEntry,
  type FoodHistoryMeal
} from "./food-history.js";
import { historyEntryBaseFromPayload, loadHistoryRows } from "./history-rows.js";
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
      // Every query is scoped to the caller: another user's Meals, Food
      // Entries and Foods never reach buildFoodHistory.
      const {
        meals: mealRows,
        entries: entryRows,
        archivedUserFoodIds
      } = await loadHistoryRows(db, userId, {
        includeTimePrecision: false,
        entryFields: [
          "meal_id",
          "entry_kind",
          "position",
          "name",
          "food_source",
          "food_id",
          "is_liquid",
          "portion_json",
          "updated_at"
        ]
      });

      const meals: FoodHistoryMeal[] = mealRows.flatMap(({ id, startedAt }) =>
        startedAt === null ? [] : [{ id, startedAt, deletedAt: null }]
      );
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
        archivedUserFoodIds,
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
 * A synced Food Entry payload as Food History reads it: the fields both
 * histories read, plus the entry's updatedAt, which it needs, and its Portion.
 */
function foodHistoryEntryFromPayload(
  id: string,
  payload: Record<string, unknown>
): FoodHistoryEntry | null {
  const base = historyEntryBaseFromPayload(id, payload);
  const updatedAt = stringValue(payload.updated_at);
  if (base === null || updatedAt === null) {
    return null;
  }
  return {
    ...base,
    portion: parseRawPortion(payload.portion_json),
    updatedAt
  };
}
