import { createRoute, z } from "@hono/zod-openapi";
import { and, eq, isNotNull, isNull, sql } from "drizzle-orm";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import {
  AgentNutritionReadUnavailableResponseSchema,
  numberValue,
  stringValue
} from "./agent-nutrition-reads.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import {
  buildMealHistory,
  type MealHistoryEntry,
  type MealHistoryMeal
} from "./meal-history.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";

export const AGENT_MEAL_HISTORY_DEFAULT_LIMIT = 20;
export const AGENT_MEAL_HISTORY_MAX_LIMIT = 50;

export const AGENT_MEAL_HISTORY_DESCRIPTION =
  "Returns the meals the caller repeats (Meal History, shown in the app as Your meals), derived on each call from live Meals and Food Entries and never stored. A meal is the set of distinct Foods in a timed Meal of the last 90 days holding two or more Foods; Portions and Quick Entries don't count, and archived Meals, date-only Meals and archived User Foods are left out. Ordered by how many Meals had that set, then the most recent one, then the Foods. Each item lists its Foods with the names they had in that most recent Meal, which is lastMealId: the Meal the app's Log again copies, Portions and Quick Entries included. Bounded by limit.";

export const AgentMealHistoryQuerySchema = z.object({
  limit: z.coerce
    .number()
    .int()
    .min(1)
    .max(AGENT_MEAL_HISTORY_MAX_LIMIT)
    .default(AGENT_MEAL_HISTORY_DEFAULT_LIMIT)
    .openapi({
      param: { name: "limit", in: "query" },
      description: "Maximum meals to return, bounded to 50."
    })
});

export const AgentMealHistoryFoodSchema = z
  .object({
    foodSource: z.string().min(1).openapi({
      description:
        "The Food Source name, such as openFoodFacts, as AgentMealEntry.foodSource carries it."
    }),
    foodId: z.string().min(1),
    name: z.string().openapi({
      description:
        "The Food's name on its Food Entry in the most recent Meal with this set of Foods."
    })
  })
  .openapi("AgentMealHistoryFood");

export const AgentMealHistoryItemSchema = z
  .object({
    foods: z.array(AgentMealHistoryFoodSchema).openapi({
      description:
        "The distinct Foods of the meal, ordered by `foodSource:foodId` in byte order."
    }),
    count: z.number().int().min(1).openapi({
      description: "Meals in the last 90 days with this set of Foods."
    }),
    lastMealId: z.string().min(1).openapi({
      description:
        "The most recent Meal with this set of Foods, Portions and Quick Entries included."
    }),
    lastStartedAt: z.string().min(1).openapi({
      description: "ISO-8601 start of the most recent Meal with this set of Foods."
    })
  })
  .openapi("AgentMealHistoryItem");

export const AgentMealHistoryResponseSchema = z
  .object({
    items: z.array(AgentMealHistoryItemSchema)
  })
  .openapi("AgentMealHistoryResponse");

export const agentMealHistoryRoute = createRoute({
  method: "get",
  path: "/agent/meals/history",
  operationId: "listAgentMealHistory",
  tags: ["Agent Reads"],
  summary:
    "List the user's Meal History: the meals they repeat, most often in the last 90 days first.",
  description: AGENT_MEAL_HISTORY_DESCRIPTION,
  security: [{ bearerAuth: [] }],
  request: {
    query: AgentMealHistoryQuerySchema
  },
  responses: {
    200: {
      description: "The caller's Meal History, bounded by limit.",
      content: {
        "application/json": {
          schema: AgentMealHistoryResponseSchema
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

export type AgentMealHistoryQuery = z.infer<typeof AgentMealHistoryQuerySchema>;
export type AgentMealHistoryResponse = z.infer<
  typeof AgentMealHistoryResponseSchema
>;

export type AgentMealHistoryReadStore = {
  /** The caller's Meal History, computed on each call and never stored. */
  listMealHistory(input: {
    userId: string;
    limit: number;
    now: Date;
  }): Promise<AgentMealHistoryResponse>;
};

export function createDrizzleAgentMealHistoryReadStore(
  db: ServerDatabase
): AgentMealHistoryReadStore {
  return {
    async listMealHistory({ userId, limit, now }) {
      const meal = schema.meals.payload;
      const entry = schema.foodEntries.payload;
      // Every query is scoped to the caller: another user's Meals, Food
      // Entries and Foods never reach buildMealHistory.
      const [mealRows, entryRows, archivedRows] = await Promise.all([
        db
          .select({
            id: schema.meals.id,
            startedAt: sql<string | null>`CASE WHEN jsonb_typeof(${meal} -> 'started_at') = 'string' THEN ${meal} ->> 'started_at' END`,
            timePrecision: sql<string | null>`${meal} ->> 'time_precision'`
          })
          .from(schema.meals)
          .where(
            and(eq(schema.meals.userId, userId), isNull(schema.meals.deletedAt))
          ),
        // Only the entries that can count, and only the fields Meal History
        // reads; buildMealHistory still applies every rule.
        db
          .select({
            id: schema.foodEntries.id,
            payload: sql<Record<string, unknown>>`jsonb_build_object(
              'meal_id', ${entry} -> 'meal_id',
              'entry_kind', ${entry} -> 'entry_kind',
              'position', ${entry} -> 'position',
              'name', ${entry} -> 'name',
              'food_source', ${entry} -> 'food_source',
              'food_id', ${entry} -> 'food_id',
              'is_liquid', ${entry} -> 'is_liquid'
            )`
          })
          .from(schema.foodEntries)
          .where(
            and(
              eq(schema.foodEntries.userId, userId),
              isNull(schema.foodEntries.deletedAt),
              sql`${entry} ->> 'entry_kind' = 'food'`,
              sql`${entry} ->> 'food_source' IS NOT NULL`,
              sql`${entry} ->> 'food_id' IS NOT NULL`
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

      // A payload written before Meals carried a time precision has none;
      // buildMealHistory reads that as `instant`.
      const meals: MealHistoryMeal[] = mealRows.flatMap(
        ({ id, startedAt, timePrecision }) =>
          startedAt === null
            ? []
            : [{ id, startedAt, timePrecision, deletedAt: null }]
      );
      const entries: MealHistoryEntry[] = entryRows.flatMap((row) => {
        const entry = mealHistoryEntryFromPayload(row.id, row.payload);
        return entry === null ? [] : [entry];
      });

      return AgentMealHistoryResponseSchema.parse({
        items: buildMealHistory(
          {
            meals,
            entries,
            archivedUserFoodIds: archivedRows.map((row) => row.id)
          },
          { now, limit }
        )
      });
    }
  };
}

/**
 * A synced Food Entry payload as Meal History reads it. The liquid flag is
 * read as stored: a null flag leaves the entry out, as it does in the app and
 * in Food History.
 */
function mealHistoryEntryFromPayload(
  id: string,
  payload: Record<string, unknown>
): MealHistoryEntry | null {
  const mealId = stringValue(payload.meal_id);
  if (mealId === null) {
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
    name: typeof payload.name === "string" ? payload.name : "",
    deletedAt: null
  };
}
