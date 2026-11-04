import { createRoute, z } from "@hono/zod-openapi";
import { and, eq, isNull } from "drizzle-orm";

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
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";

export const AGENT_MEAL_TYPES_DESCRIPTION =
  "Returns the caller's active Meal Types, ordered by sortOrder then id, as the app lists them. Archived Meal Types are left out. Call it before choosing a mealType for batchWriteAgentMeal: a Meal stores the Meal Type name it was sent, so send a name from this list.";

export const AgentMealTypeItemSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().openapi({
      description:
        "The Meal Type name, as batchWriteAgentMeal's meal.mealType carries it."
    }),
    sortOrder: z.number().int().openapi({
      description: "The position the app lists this Meal Type in."
    })
  })
  .openapi("AgentMealTypeItem");

export const AgentMealTypesResponseSchema = z
  .object({
    mealTypes: z.array(AgentMealTypeItemSchema)
  })
  .openapi("AgentMealTypesResponse");

/**
 * The 503 body when no Meal Types store is configured. Meal Types are a
 * nutrition read, so this is the nutrition read's unavailable body, as Food
 * History uses it; a second code for the same condition would only split it.
 */
export const AgentMealTypesUnavailableResponseSchema =
  AgentNutritionReadUnavailableResponseSchema;

export const agentMealTypesRoute = createRoute({
  method: "get",
  path: "/agent/meal-types",
  operationId: "listAgentMealTypes",
  tags: ["Agent Reads"],
  summary: "List the user's active Meal Types, in the order the app shows them.",
  description: AGENT_MEAL_TYPES_DESCRIPTION,
  security: [{ bearerAuth: [] }],
  responses: {
    200: {
      description: "The caller's active Meal Types.",
      content: {
        "application/json": {
          schema: AgentMealTypesResponseSchema
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
            AgentMealTypesUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export type AgentMealTypeItem = z.infer<typeof AgentMealTypeItemSchema>;
export type AgentMealTypesResponse = z.infer<
  typeof AgentMealTypesResponseSchema
>;

export type AgentMealTypesReadStore = {
  /** The caller's active Meal Types, ordered by sortOrder then id. */
  listMealTypes(input: { userId: string }): Promise<AgentMealTypesResponse>;
};

export function createDrizzleAgentMealTypesReadStore(
  db: ServerDatabase
): AgentMealTypesReadStore {
  return {
    async listMealTypes({ userId }) {
      const rows = await db
        .select({ id: schema.mealTypes.id, payload: schema.mealTypes.payload })
        .from(schema.mealTypes)
        .where(
          and(
            eq(schema.mealTypes.userId, userId),
            isNull(schema.mealTypes.deletedAt)
          )
        );

      // The payload keys are the app's Meal Type image (`name`,
      // `sort_order`). Ordering happens here, after the payload is read, so a
      // malformed sort_order sorts as 0 instead of failing the read.
      const mealTypes = rows
        .map(({ id, payload }) => ({
          id,
          name: stringValue(payload.name) ?? "",
          sortOrder: Math.trunc(numberValue(payload.sort_order) ?? 0)
        }))
        .sort((left, right) =>
          left.sortOrder !== right.sortOrder
            ? left.sortOrder - right.sortOrder
            : left.id < right.id
              ? -1
              : left.id > right.id
                ? 1
                : 0
        );

      return AgentMealTypesResponseSchema.parse({ mealTypes });
    }
  };
}
