import { createRoute, z } from "@hono/zod-openapi";
import { and, asc, eq, isNull } from "drizzle-orm";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import {
  buildNutritionTrend,
  CORE_NUTRIENT_IDS,
  COMMON_NUTRIENT_IDS,
  dayTotals,
  deriveGoalProgress,
  enumerateNutritionDays,
  GOALABLE_NUTRIENT_IDS,
  nutrientDefaultUnit,
  NUTRIENT_IDS,
  totalsFromEntries,
  type AnalyticsFoodEntry,
  type AnalyticsMeal,
  type AnalyticsNutritionDay,
  type NutrientAmount,
  type NutrientGoalTarget,
  type NutrientId,
  type NutrientTotal,
  type NutrientUnit
} from "./analytics/nutrition-analytics.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";

/** The widest range an agent may request in one read, keeping egress bounded. */
export const AGENT_NUTRITION_MAX_RANGE_DAYS = 366;

const NUTRITION_DAY_REGEX = /^\d{4}-\d{2}-\d{2}$/;

const ISO8601StringSchema = z.string().min(1).openapi({
  description: "ISO-8601 timestamp."
});

const NutrientUnitSchema = z
  .enum(["kilocalorie", "gram", "milligram", "microgram", "milliliter"])
  .openapi("AgentNutritionNutrientUnit");

const NutrientIdSchema = z
  .enum(NUTRIENT_IDS as [NutrientId, ...NutrientId[]])
  .openapi("AgentNutritionNutrientId");

const GoalableNutrientIdSchema = z
  .enum(GOALABLE_NUTRIENT_IDS as [NutrientId, ...NutrientId[]])
  .openapi("AgentNutritionGoalableNutrientId");

export const AgentNutrientTotalSchema = z
  .object({
    nutrient: NutrientIdSchema,
    unit: NutrientUnitSchema,
    value: z.number().openapi({
      description:
        "Derived total for the nutrient over the grain. Meaningful only when complete is true; with complete=false the contributing data was partial and the value omits unknown components."
    }),
    complete: z.boolean().openapi({
      description:
        "False when any contributing Food Entry lacked this nutrient. An unknown component propagates as incompleteness and is never reported as 0 (NUTRITION.md §4)."
    })
  })
  .strict()
  .openapi("AgentNutrientTotal");

const AgentNutrientGoalStatusSchema = z
  .enum(["noGoal", "unknown", "below", "met", "over"])
  .openapi("AgentNutrientGoalStatus");

const AgentNutrientGoalTargetSchema = z
  .object({
    nutrient: GoalableNutrientIdSchema,
    unit: NutrientUnitSchema,
    value: z.number().openapi({
      description: "Configured target value supplied by the agent (config, never a stored total)."
    })
  })
  .strict()
  .openapi("AgentNutrientGoalTarget");

export const AgentNutrientGoalProgressSchema = z
  .object({
    nutrient: GoalableNutrientIdSchema,
    status: AgentNutrientGoalStatusSchema,
    total: AgentNutrientTotalSchema,
    target: z.union([AgentNutrientGoalTargetSchema, z.null()]),
    ratio: z.number().nullable().openapi({
      description:
        "total / target for a complete total against a non-zero target, else null (no goal, an unknown total, or a zero target)."
    }),
    remaining: z.number().nullable().openapi({
      description: "target - total for a complete goaled total (negative when over), else null."
    })
  })
  .strict()
  .openapi("AgentNutrientGoalProgress");

export const AgentNutritionDayTotalsSchema = z
  .object({
    localDate: z.string().min(1).openapi({
      description: "Nutrition Day date (YYYY-MM-DD)."
    }),
    mealCount: z.number().int().min(0),
    entryCount: z.number().int().min(0),
    totals: z.array(AgentNutrientTotalSchema),
    goalProgress: z.array(AgentNutrientGoalProgressSchema)
  })
  .strict()
  .openapi("AgentNutritionDayTotals");

export const AgentNutritionPeriodTotalsSchema = z
  .object({
    from: z.string().min(1),
    to: z.string().min(1),
    dayCount: z.number().int().min(1),
    loggedDayCount: z.number().int().min(0).openapi({
      description: "Days in the range that had at least one logged Meal."
    }),
    mealCount: z.number().int().min(0),
    entryCount: z.number().int().min(0),
    totals: z.array(AgentNutrientTotalSchema),
    goalProgress: z.array(AgentNutrientGoalProgressSchema)
  })
  .strict()
  .openapi("AgentNutritionPeriodTotals");

const AgentNutritionTrendPointSchema = z
  .object({
    localDate: z.string().min(1),
    value: z.number().nullable().openapi({
      description:
        "The day's derived total, or null when incomplete (the nutrient was unknown for that day). Null is distinct from a genuine 0 (a day with no logged meals)."
    }),
    complete: z.boolean()
  })
  .strict()
  .openapi("AgentNutritionTrendPoint");

export const AgentNutritionTrendSchema = z
  .object({
    nutrient: NutrientIdSchema,
    unit: NutrientUnitSchema,
    target: z.union([AgentNutrientGoalTargetSchema, z.null()]),
    points: z.array(AgentNutritionTrendPointSchema)
  })
  .strict()
  .openapi("AgentNutritionTrend");

const AgentNutritionGoalSourceSchema = z
  .enum(["query", "stored", "none"])
  .openapi({
    description:
      "Where the goal targets used for this response's goalProgress came from: explicit query params ('query'), the caller's stored Nutrition Goals ('stored'), or 'none' when neither supplied a target for any goalable Nutrient."
  });

export const AgentNutritionTotalsResponseSchema = z
  .object({
    from: z.string().min(1),
    to: z.string().min(1),
    dayCount: z.number().int().min(1),
    goalSource: AgentNutritionGoalSourceSchema,
    period: AgentNutritionPeriodTotalsSchema,
    days: z.array(AgentNutritionDayTotalsSchema)
  })
  .strict()
  .openapi("AgentNutritionTotalsResponse");

export const AgentNutritionTrendsResponseSchema = z
  .object({
    from: z.string().min(1),
    to: z.string().min(1),
    dayCount: z.number().int().min(1),
    goalSource: AgentNutritionGoalSourceSchema,
    trends: z.array(AgentNutritionTrendSchema),
    goalProgress: z.array(AgentNutrientGoalProgressSchema).openapi({
      description:
        "Period goal progress for the goaled nutrients, derived over the whole range."
    })
  })
  .strict()
  .openapi("AgentNutritionTrendsResponse");

export const AgentNutritionReadUnavailableResponseSchema = z
  .object({
    code: z.literal("agent_nutrition_read_unavailable"),
    message: z.string().min(1)
  })
  .openapi("AgentNutritionReadUnavailableResponse");

export const AgentNutritionReadInvalidRangeResponseSchema = z
  .object({
    code: z.literal("agent_nutrition_read_invalid_range"),
    message: z.string().min(1)
  })
  .openapi("AgentNutritionReadInvalidRangeResponse");

/**
 * Optional per-nutrient goal targets supplied as query params, taking
 * precedence over the caller's stored Nutrition Goal for that nutrient when
 * both are present (`resolveNutritionGoalTargets` merges the two).
 * Nutrition Goals now sync as ordinary LWW rows (NUTRITION.md §7,
 * `nutrition_goals` in `sync.ts`) — a query param is an override, not the
 * only way to supply a target. They are pure config inputs — never read from
 * a stored total.
 */
const GoalTargetQuerySchema = z.coerce
  .number()
  .finite()
  .openapi({ description: "Optional Goal target value." });

const NutritionRangeQuerySchema = z.object({
  from: z.string().trim().regex(NUTRITION_DAY_REGEX).openapi({
    param: { name: "from", in: "query" },
    description: "Inclusive Nutrition Day lower bound (YYYY-MM-DD)."
  }),
  to: z.string().trim().regex(NUTRITION_DAY_REGEX).openapi({
    param: { name: "to", in: "query" },
    description: "Inclusive Nutrition Day upper bound (YYYY-MM-DD)."
  }),
  energyGoal: GoalTargetQuerySchema.optional().openapi({
    param: { name: "energyGoal", in: "query" },
    description: "Optional energy (kcal) Goal target to score progress against."
  }),
  proteinGoal: GoalTargetQuerySchema.optional().openapi({
    param: { name: "proteinGoal", in: "query" },
    description: "Optional protein (g) Goal target to score progress against."
  }),
  carbohydrateGoal: GoalTargetQuerySchema.optional().openapi({
    param: { name: "carbohydrateGoal", in: "query" },
    description: "Optional carbohydrate (g) Goal target to score progress against."
  }),
  fatGoal: GoalTargetQuerySchema.optional().openapi({
    param: { name: "fatGoal", in: "query" },
    description: "Optional fat (g) Goal target to score progress against."
  })
});

export const AgentNutritionTotalsQuerySchema = NutritionRangeQuerySchema;
export const AgentNutritionTrendsQuerySchema = NutritionRangeQuerySchema;

export const AGENT_MEAL_DEFAULT_PAGE_LIMIT = 50;
export const AGENT_MEAL_MAX_PAGE_LIMIT = 200;

export const AGENT_MEAL_LIST_FIELDS = [
  "id",
  "mealType",
  "startedAt",
  "endedAt",
  "timezone",
  "localDate",
  "entries"
] as const;

const AgentMealListFieldSchema = z
  .enum(AGENT_MEAL_LIST_FIELDS)
  .openapi("AgentMealListField");

const mealListFieldSet = new Set<string>(AGENT_MEAL_LIST_FIELDS);

const AgentMealEntryNutrientAmountSchema = z
  .object({
    status: z.enum(["complete", "unknown"]),
    value: z.number().nullable(),
    entered: z.string().nullable(),
    unit: z.string().min(1)
  })
  .openapi("AgentMealEntryNutrientAmount");

export const AgentMealEntrySchema = z
  .object({
    id: z.string().min(1),
    position: z.number().int().min(0),
    name: z.string().min(1),
    kind: z.enum(["food", "quickEntry"]),
    nutrients: z.record(z.string(), AgentMealEntryNutrientAmountSchema),
    isLiquid: z.boolean(),
    foodId: z.string().min(1).nullable(),
    foodSource: z.string().min(1).nullable(),
    portion: z
      .object({
        value: z.number(),
        entered: z.string().min(1),
        unit: z.string().min(1)
      })
      .nullable(),
    servingLabel: z.string().min(1).nullable(),
    servingSize: z.number().nullable(),
    packageSize: z.number().nullable(),
    updatedAt: ISO8601StringSchema
  })
  .openapi("AgentMealEntry");

export const AgentMealListItemSchema = z
  .object({
    id: z.string().min(1),
    mealType: z.string().min(1).optional(),
    startedAt: z.string().min(1).optional(),
    endedAt: z.string().min(1).nullable().optional(),
    timezone: z.string().min(1).optional(),
    localDate: z.string().min(1).optional(),
    entries: z.array(AgentMealEntrySchema).optional()
  })
  .openapi("AgentMealListItem");

export const AgentMealListQuerySchema = z.object({
  from: z.string().trim().min(1).optional().openapi({
    param: { name: "from", in: "query" },
    description: "Optional inclusive ISO-8601 lower bound for the Meal start."
  }),
  to: z.string().trim().min(1).optional().openapi({
    param: { name: "to", in: "query" },
    description: "Optional inclusive ISO-8601 upper bound for the Meal start."
  }),
  limit: z.coerce
    .number()
    .int()
    .min(1)
    .max(AGENT_MEAL_MAX_PAGE_LIMIT)
    .default(AGENT_MEAL_DEFAULT_PAGE_LIMIT)
    .openapi({
      param: { name: "limit", in: "query" },
      description: "Maximum Meals to return, bounded to 200."
    }),
  cursor: z.string().trim().min(1).optional().openapi({
    param: { name: "cursor", in: "query" },
    description: "Opaque cursor returned by the previous page."
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
          .every((field) => mealListFieldSet.has(field)),
      "fields must be a comma-separated list of known Meal fields"
    )
    .openapi({
      param: { name: "fields", in: "query" },
      description:
        "Comma-separated list of Meal fields to return. id, mealType, and startedAt are always returned; omitting fields returns the minimal default. Include entries to get the raw Food Entry list for each Meal."
    })
});

export const AgentMealListResponseSchema = z
  .object({
    meals: z.array(AgentMealListItemSchema),
    fields: z.array(AgentMealListFieldSchema),
    limit: z.number().int().min(1).max(AGENT_MEAL_MAX_PAGE_LIMIT),
    nextCursor: z.string().min(1).nullable(),
    totalMatched: z.number().int().min(0)
  })
  .openapi("AgentMealListResponse");

export const agentNutritionTotalsRoute = createRoute({
  method: "get",
  path: "/agent/nutrition/totals",
  operationId: "getAgentNutritionTotals",
  tags: ["Agent Reads"],
  summary: "Read computed nutrition totals per Nutrition Day and for the period.",
  description:
    "Computes energy + macro + tracked-micro totals on demand from self-describing Food Entry snapshots and Portions, per Nutrition Day and aggregated over the range, plus goal progress against the resolved v1 Goal targets: an explicit query param wins per nutrient, otherwise the caller's stored Nutrition Goal is used by default; `goalSource` reports which. No nutrition total is stored or synced. Unknown nutrients propagate an incompleteness flag and are never reported as 0. This is the preferred, data-minimizing shape for analytical questions; bounded raw meal-by-meal reads exist separately (GET /agent/meals) for when an agent genuinely needs the rows. Pure read — no rows mutate and no Activity Log entry is written.",
  security: [{ bearerAuth: [] }],
  request: {
    query: AgentNutritionTotalsQuerySchema
  },
  responses: {
    200: {
      description: "Computed per-day and period nutrition totals for the range.",
      content: {
        "application/json": {
          schema: AgentNutritionTotalsResponseSchema
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
      description: "The requested date range is invalid or too wide.",
      content: {
        "application/json": {
          schema: AgentNutritionReadInvalidRangeResponseSchema
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

export const agentNutritionTrendsRoute = createRoute({
  method: "get",
  path: "/agent/nutrition/trends",
  operationId: "getAgentNutritionTrends",
  tags: ["Agent Reads"],
  summary: "Read computed nutrition trends and goal progress over a period.",
  description:
    "Computes a per-day trend line for each goaled nutrient (energy + three macros) across the range, plus period goal progress against the resolved v1 Goal targets: an explicit query param wins per nutrient, otherwise the caller's stored Nutrition Goal is used by default; `goalSource` reports which. Trends are derived on demand from Food Entry snapshots; nothing is stored. A day whose entries omitted a nutrient is flagged incomplete with a null value rather than a false 0 (NUTRITION.md §4). This is the preferred, data-minimizing shape for analytical questions; bounded raw meal-by-meal reads exist separately (GET /agent/meals) for when an agent genuinely needs the rows. Pure read — no rows mutate and no Activity Log entry is written.",
  security: [{ bearerAuth: [] }],
  request: {
    query: AgentNutritionTrendsQuerySchema
  },
  responses: {
    200: {
      description: "Computed per-day trends and period goal progress for the range.",
      content: {
        "application/json": {
          schema: AgentNutritionTrendsResponseSchema
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
      description: "The requested date range is invalid or too wide.",
      content: {
        "application/json": {
          schema: AgentNutritionReadInvalidRangeResponseSchema
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

export const agentMealListRoute = createRoute({
  method: "get",
  path: "/agent/meals",
  operationId: "listAgentMeals",
  tags: ["Agent Reads"],
  summary: "List a bounded raw Meal (+ Food Entry) page over a date range.",
  description:
    "Returns the caller's live Meals over an optional date range, each self-describing Food Entry snapshot included only when the entries field is requested. Data-minimizing and bounded by default: date-scoped, limit/cursor-paginated, with a minimal default fields projection — never an unbounded meal-by-meal dump. Computed nutrition totals/trends remain the preferred read for analytical questions; this read is for when an agent genuinely needs the raw rows (e.g. to build a batch edit).",
  security: [{ bearerAuth: [] }],
  request: {
    query: AgentMealListQuerySchema
  },
  responses: {
    200: {
      description: "A bounded page of Meals.",
      content: {
        "application/json": {
          schema: AgentMealListResponseSchema
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

export type AgentNutritionTotalsQuery = z.infer<
  typeof AgentNutritionTotalsQuerySchema
>;
export type AgentNutritionTrendsQuery = z.infer<
  typeof AgentNutritionTrendsQuerySchema
>;
export type AgentMealListQuery = z.infer<typeof AgentMealListQuerySchema>;
export type AgentMealListPage = z.infer<typeof AgentMealListResponseSchema>;
export type AgentNutritionTotalsResponse = z.infer<
  typeof AgentNutritionTotalsResponseSchema
>;
export type AgentNutritionTrendsResponse = z.infer<
  typeof AgentNutritionTrendsResponseSchema
>;

export type AgentNutritionReadStore = {
  /** Live (non-tombstoned) Nutrition Days with their Meals + Food Entries in the range. */
  readNutritionDays(input: {
    userId: string;
    from: string;
    to: string;
  }): Promise<AnalyticsNutritionDay[]>;
  /** Bounded raw Meal (+ Food Entry) list over an optional date range. */
  listMeals(input: {
    userId: string;
    query: AgentMealListQuery;
  }): Promise<AgentMealListPage>;
};

type MealRow = {
  id: string;
  payload: Record<string, unknown>;
};

type FoodEntryRow = {
  id: string;
  payload: Record<string, unknown>;
};

/** The "core" + "common" nutrient tiers a totals summary reports. */
const SUMMARY_NUTRIENT_IDS: readonly NutrientId[] = [
  ...CORE_NUTRIENT_IDS,
  ...COMMON_NUTRIENT_IDS
];

export function createDrizzleAgentNutritionReadStore(
  db: ServerDatabase
): AgentNutritionReadStore {
  return {
    async readNutritionDays({ userId, from, to }) {
      const days = enumerateNutritionDays(from, to);
      const inRange = new Set(days);

      const mealRows = await db
        .select({
          id: schema.meals.id,
          payload: schema.meals.payload
        })
        .from(schema.meals)
        .where(
          and(eq(schema.meals.userId, userId), isNull(schema.meals.deletedAt))
        )
        .orderBy(asc(schema.meals.receivedAt), asc(schema.meals.id));

      const entryRows = await db
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
        )
        .orderBy(asc(schema.foodEntries.receivedAt), asc(schema.foodEntries.id));

      const entriesByMeal = new Map<string, AnalyticsFoodEntry[]>();
      for (const row of entryRows) {
        const mapped = mapFoodEntryRow(row);
        if (mapped === null) {
          continue;
        }
        const list = entriesByMeal.get(mapped.mealId) ?? [];
        list.push(mapped.entry);
        entriesByMeal.set(mapped.mealId, list);
      }

      const mealsByDay = new Map<string, AnalyticsMeal[]>();
      for (const row of mealRows) {
        const mapped = mapMealRow(row, entriesByMeal);
        if (mapped === null || !inRange.has(mapped.localDate)) {
          continue;
        }
        const list = mealsByDay.get(mapped.localDate) ?? [];
        list.push(mapped.meal);
        mealsByDay.set(mapped.localDate, list);
      }

      return days.map((localDate) => ({
        localDate,
        meals: mealsByDay.get(localDate) ?? []
      }));
    },
    async listMeals({ userId, query }) {
      const fields = resolveMealFieldSelection(query.fields);
      const includeEntries = fields.includes("entries");

      const mealRows = await db
        .select({
          id: schema.meals.id,
          payload: schema.meals.payload,
          receivedAt: schema.meals.receivedAt
        })
        .from(schema.meals)
        .where(
          and(eq(schema.meals.userId, userId), isNull(schema.meals.deletedAt))
        )
        .orderBy(asc(schema.meals.receivedAt), asc(schema.meals.id));

      const from = dateValue(query.from);
      const to = dateValue(query.to);
      const matching = mealRows
        .flatMap((row) => {
          const startedAt = dateValue(row.payload.started_at);
          if (startedAt === null) {
            return [];
          }
          if (from !== null && startedAt < from) {
            return [];
          }
          if (to !== null && startedAt > to) {
            return [];
          }

          return [{ ...row, startedAt }];
        })
        .sort(
          (left, right) => right.startedAt.getTime() - left.startedAt.getTime()
        );

      const offset = cursorOffsetById(matching, query.cursor);
      const page = matching.slice(offset, offset + query.limit);
      const nextOffset = offset + query.limit;

      const entriesByMeal = includeEntries
        ? await readFoodEntriesByMealId(db, {
            userId,
            mealIds: page.map((row) => row.id)
          })
        : new Map<string, AgentMealEntry[]>();

      return AgentMealListResponseSchema.parse({
        meals: page.map((row) =>
          projectMealRow(row, fields, entriesByMeal.get(row.id) ?? [])
        ),
        fields,
        limit: query.limit,
        nextCursor:
          nextOffset < matching.length ? page[page.length - 1]?.id ?? null : null,
        totalMatched: matching.length
      });
    }
  };
}

export type AgentNutritionGoalSource = "query" | "stored" | "none";

export function buildAgentNutritionTotalsResponse({
  from,
  to,
  days,
  goals,
  goalSource = "none"
}: {
  from: string;
  to: string;
  days: readonly AnalyticsNutritionDay[];
  goals: Map<NutrientId, NutrientGoalTarget>;
  goalSource?: AgentNutritionGoalSource;
}): AgentNutritionTotalsResponse {
  const totalsByDate = new Map<string, Map<NutrientId, NutrientTotal>>();
  const dayShapes = days.map((day) => {
    const totals = dayTotals(day);
    totalsByDate.set(day.localDate, totals);
    const entryCount = day.meals.reduce(
      (count, meal) => count + meal.entries.length,
      0
    );
    return {
      localDate: day.localDate,
      mealCount: day.meals.length,
      entryCount,
      totals: SUMMARY_NUTRIENT_IDS.map((id) =>
        serializeTotal(requireTotal(totals, id))
      ),
      goalProgress: GOALABLE_NUTRIENT_IDS.map((id) =>
        serializeGoalProgress(
          deriveGoalProgress(requireTotal(totals, id), goals.get(id) ?? null)
        )
      )
    };
  });

  const allEntries = days.flatMap((day) =>
    day.meals.flatMap((meal) => [...meal.entries])
  );
  const periodTotals = totalsFromEntries(allEntries);
  const mealCount = days.reduce((count, day) => count + day.meals.length, 0);
  const entryCount = allEntries.length;
  const loggedDayCount = days.filter((day) => day.meals.length > 0).length;

  return AgentNutritionTotalsResponseSchema.parse({
    from,
    to,
    dayCount: days.length,
    goalSource,
    period: {
      from,
      to,
      dayCount: days.length,
      loggedDayCount,
      mealCount,
      entryCount,
      totals: SUMMARY_NUTRIENT_IDS.map((id) =>
        serializeTotal(requireTotal(periodTotals, id))
      ),
      goalProgress: GOALABLE_NUTRIENT_IDS.map((id) =>
        serializeGoalProgress(
          deriveGoalProgress(requireTotal(periodTotals, id), goals.get(id) ?? null)
        )
      )
    },
    days: dayShapes
  });
}

export function buildAgentNutritionTrendsResponse({
  from,
  to,
  days,
  goals,
  goalSource = "none"
}: {
  from: string;
  to: string;
  days: readonly AnalyticsNutritionDay[];
  goals: Map<NutrientId, NutrientGoalTarget>;
  goalSource?: AgentNutritionGoalSource;
}): AgentNutritionTrendsResponse {
  const dayList = days.map((day) => day.localDate);
  const totalsByDate = new Map<string, Map<NutrientId, NutrientTotal>>();
  for (const day of days) {
    totalsByDate.set(day.localDate, dayTotals(day));
  }

  const trends = GOALABLE_NUTRIENT_IDS.map((nutrient) => {
    const trend = buildNutritionTrend({
      nutrient,
      days: dayList,
      totalsByDate,
      target: goals.get(nutrient) ?? null
    });
    return {
      nutrient: trend.nutrient,
      unit: trend.unit,
      target: serializeTarget(trend.target),
      points: trend.points.map((point) => ({
        localDate: point.localDate,
        value: point.isComplete ? point.value : null,
        complete: point.isComplete
      }))
    };
  });

  const allEntries = days.flatMap((day) =>
    day.meals.flatMap((meal) => [...meal.entries])
  );
  const periodTotals = totalsFromEntries(allEntries);
  const goalProgress = GOALABLE_NUTRIENT_IDS.map((id) =>
    serializeGoalProgress(
      deriveGoalProgress(requireTotal(periodTotals, id), goals.get(id) ?? null)
    )
  );

  return AgentNutritionTrendsResponseSchema.parse({
    from,
    to,
    dayCount: days.length,
    goalSource,
    trends,
    goalProgress
  });
}

/**
 * Collect the supplied per-nutrient Goal targets into a map, defaulting their
 * units to the nutrient's canonical unit (energy=kcal, macros=g).
 */
export function goalTargetsFromQuery(
  query: AgentNutritionTotalsQuery
): Map<NutrientId, NutrientGoalTarget> {
  const goals = new Map<NutrientId, NutrientGoalTarget>();
  const supplied: [NutrientId, number | undefined][] = [
    ["energy", query.energyGoal],
    ["protein", query.proteinGoal],
    ["carbohydrate", query.carbohydrateGoal],
    ["fat", query.fatGoal]
  ];
  for (const [nutrient, value] of supplied) {
    if (value !== undefined) {
      goals.set(nutrient, {
        nutrient,
        value,
        unit: nutrientDefaultUnit(nutrient)
      });
    }
  }

  return goals;
}

/**
 * Resolve the goal targets a totals/trends read should score against: an
 * explicit query-param target always wins for its nutrient (query-supplied
 * targets are pure config inputs the agent asked for); any goalable
 * Nutrient the query left unset falls back to the caller's stored Nutrition
 * Goal (fixes the root cause of every agent read needing goal
 * targets re-supplied on each call). `goalSource` summarizes which source
 * contributed at least one target: "query" if any query param was supplied
 * (even if stored Goals filled the rest), "stored" if only stored Goals
 * contributed, "none" if neither did.
 */
export function resolveNutritionGoalTargets({
  queryGoals,
  storedGoals
}: {
  queryGoals: Map<NutrientId, NutrientGoalTarget>;
  storedGoals: Map<NutrientId, NutrientGoalTarget>;
}): { goals: Map<NutrientId, NutrientGoalTarget>; goalSource: "query" | "stored" | "none" } {
  const merged = new Map<NutrientId, NutrientGoalTarget>(storedGoals);
  for (const [nutrient, target] of queryGoals) {
    merged.set(nutrient, target);
  }

  const goalSource =
    queryGoals.size > 0 ? "query" : merged.size > 0 ? "stored" : "none";

  return { goals: merged, goalSource };
}

/** Validate a range and return the inclusive day count, or an error message. */
export function validateNutritionRange(
  from: string,
  to: string
): { ok: true; dayCount: number } | { ok: false; message: string } {
  let days: string[];
  try {
    days = enumerateNutritionDays(from, to);
  } catch (error) {
    return {
      ok: false,
      message:
        error instanceof Error ? error.message : "Invalid nutrition day range."
    };
  }
  if (days.length > AGENT_NUTRITION_MAX_RANGE_DAYS) {
    return {
      ok: false,
      message: `Requested range spans ${days.length} days, exceeding the ${AGENT_NUTRITION_MAX_RANGE_DAYS}-day maximum.`
    };
  }

  return { ok: true, dayCount: days.length };
}

function requireTotal(
  totals: Map<NutrientId, NutrientTotal>,
  id: NutrientId
): NutrientTotal {
  const total = totals.get(id);
  if (total === undefined) {
    throw new Error(`Missing computed total for nutrient ${id}.`);
  }

  return total;
}

function serializeTotal(total: NutrientTotal) {
  return {
    nutrient: total.id,
    unit: total.unit,
    value: canonicalNumber(total.value),
    complete: total.isComplete
  };
}

function serializeTarget(target: NutrientGoalTarget | null) {
  if (target === null) {
    return null;
  }

  return {
    nutrient: target.nutrient,
    unit: target.unit,
    value: canonicalNumber(target.value)
  };
}

function serializeGoalProgress(progress: ReturnType<typeof deriveGoalProgress>) {
  return {
    nutrient: progress.nutrient,
    status: progress.status,
    total: serializeTotal(progress.total),
    target: serializeTarget(progress.target),
    ratio: progress.ratio === null ? null : canonicalNumber(progress.ratio),
    remaining:
      progress.remaining === null ? null : canonicalNumber(progress.remaining)
  };
}

function mapMealRow(
  row: MealRow,
  entriesByMeal: Map<string, AnalyticsFoodEntry[]>
): { localDate: string; meal: AnalyticsMeal } | null {
  const payload = row.payload;
  const localDate = stringValue(payload.local_date);
  const startedAt = dateValue(payload.started_at);
  if (localDate === null || startedAt === null) {
    return null;
  }

  return {
    localDate,
    meal: {
      id: row.id,
      mealType: stringValue(payload.meal_type) ?? "",
      startedAt,
      entries: entriesByMeal.get(row.id) ?? []
    }
  };
}

function mapFoodEntryRow(
  row: FoodEntryRow
): { mealId: string; entry: AnalyticsFoodEntry } | null {
  const payload = row.payload;
  const mealId = stringValue(payload.meal_id);
  if (mealId === null) {
    return null;
  }

  const kind = payload.entry_kind === "quickEntry" ? "quickEntry" : "food";
  const nutrients = parseNutrientVector(payload.nutrient_values_json);
  if (nutrients === null) {
    return null;
  }

  if (kind === "quickEntry") {
    return { mealId, entry: { kind: "quickEntry", nutrients } };
  }

  const portion = parsePortion(payload.portion_json);
  if (portion === null) {
    return null;
  }
  const resolvedBaseQuantity = resolvePortionBaseQuantity(portion, {
    servingSize: numberValue(payload.serving_size),
    packageSize: numberValue(payload.package_size)
  });
  if (resolvedBaseQuantity === undefined) {
    return null;
  }

  return {
    mealId,
    entry: { kind: "food", nutrients, resolvedBaseQuantity }
  };
}

function parseNutrientVector(
  value: unknown
): Partial<Record<NutrientId, NutrientAmount>> | null {
  let decoded: unknown = value;
  if (typeof value === "string") {
    try {
      decoded = JSON.parse(value);
    } catch {
      return null;
    }
  }
  if (!isRecord(decoded)) {
    return null;
  }

  const nutrients: Partial<Record<NutrientId, NutrientAmount>> = {};
  for (const id of NUTRIENT_IDS) {
    const raw = decoded[id];
    if (!isRecord(raw)) {
      continue;
    }
    const unit = nutrientUnit(raw.unit) ?? nutrientDefaultUnit(id);
    if (raw.status === "complete" && typeof raw.value === "number" && Number.isFinite(raw.value)) {
      nutrients[id] = { status: "complete", value: raw.value, unit };
    } else {
      nutrients[id] = { status: "unknown", unit };
    }
  }

  return nutrients;
}

type ParsedPortion = { value: number; unit: string };

function parsePortion(value: unknown): ParsedPortion | null {
  let decoded: unknown = value;
  if (typeof value === "string") {
    try {
      decoded = JSON.parse(value);
    } catch {
      return null;
    }
  }
  if (!isRecord(decoded)) {
    return null;
  }
  const magnitude = decoded.value;
  const unit = decoded.unit;
  if (typeof magnitude !== "number" || !Number.isFinite(magnitude)) {
    return null;
  }
  if (typeof unit !== "string") {
    return null;
  }

  return { value: magnitude, unit };
}

const OUNCE_GRAMS = 28.349523125;
const FLUID_OUNCE_MILLILITERS = 29.5735295625;

function resolvePortionBaseQuantity(
  portion: ParsedPortion,
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

function canonicalNumber(value: number): number {
  return Number.parseFloat(value.toFixed(6));
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function numberValue(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function dateValue(value: unknown): Date | null {
  if (typeof value !== "string" || value.trim().length === 0) {
    return null;
  }
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function nutrientUnit(value: unknown): NutrientUnit | null {
  return value === "kilocalorie" ||
    value === "gram" ||
    value === "milligram" ||
    value === "microgram" ||
    value === "milliliter"
    ? value
    : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

type AgentMealEntry = z.infer<typeof AgentMealEntrySchema>;

type RawMealRow = {
  id: string;
  payload: Record<string, unknown>;
  receivedAt: Date;
};

type RawFoodEntryRow = {
  id: string;
  payload: Record<string, unknown>;
};

function resolveMealFieldSelection(
  value: string | undefined
): (typeof AGENT_MEAL_LIST_FIELDS)[number][] {
  if (value === undefined) {
    return ["id", "mealType", "startedAt"];
  }

  return [
    ...new Set<(typeof AGENT_MEAL_LIST_FIELDS)[number]>([
      "id",
      "mealType",
      "startedAt",
      ...value
        .split(",")
        .map((field) => field.trim())
        .filter((field): field is (typeof AGENT_MEAL_LIST_FIELDS)[number] =>
          (AGENT_MEAL_LIST_FIELDS as readonly string[]).includes(field)
        )
    ])
  ];
}

function cursorOffsetById<T extends { id: string }>(
  rows: readonly T[],
  cursor: string | undefined
) {
  if (cursor === undefined) {
    return 0;
  }

  const index = rows.findIndex((row) => row.id === cursor);
  return index < 0 ? 0 : index + 1;
}

async function readFoodEntriesByMealId(
  db: ServerDatabase,
  { userId, mealIds }: { userId: string; mealIds: readonly string[] }
): Promise<Map<string, AgentMealEntry[]>> {
  const byMeal = new Map<string, AgentMealEntry[]>();
  if (mealIds.length === 0) {
    return byMeal;
  }

  const rows = await db
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
    )
    .orderBy(asc(schema.foodEntries.receivedAt), asc(schema.foodEntries.id));

  const mealIdSet = new Set(mealIds);
  for (const row of rows) {
    const mapped = mapRawFoodEntryRow(row);
    if (mapped === null || !mealIdSet.has(mapped.mealId)) {
      continue;
    }
    const list = byMeal.get(mapped.mealId) ?? [];
    list.push(mapped.entry);
    byMeal.set(mapped.mealId, list);
  }

  for (const list of byMeal.values()) {
    list.sort((left, right) => left.position - right.position);
  }

  return byMeal;
}

function mapRawFoodEntryRow(
  row: RawFoodEntryRow
): { mealId: string; entry: AgentMealEntry } | null {
  const payload = row.payload;
  const mealId = stringValue(payload.meal_id);
  const name = stringValue(payload.name);
  const updatedAt = stringValue(payload.updated_at);
  if (mealId === null || name === null || updatedAt === null) {
    return null;
  }

  const nutrients = parseRawNutrientVector(payload.nutrient_values_json);
  const portion = parseRawPortion(payload.portion_json);

  return {
    mealId,
    entry: AgentMealEntrySchema.parse({
      id: row.id,
      position: numberValue(payload.position) ?? 0,
      name,
      kind: payload.entry_kind === "quickEntry" ? "quickEntry" : "food",
      nutrients,
      isLiquid: payload.is_liquid === true,
      foodId: stringValue(payload.food_id),
      foodSource: stringValue(payload.food_source),
      portion,
      servingLabel: stringValue(payload.serving_label),
      servingSize: numberValue(payload.serving_size),
      packageSize: numberValue(payload.package_size),
      updatedAt
    })
  };
}

function parseRawNutrientVector(value: unknown): Record<string, unknown> {
  let decoded: unknown = value;
  if (typeof value === "string") {
    try {
      decoded = JSON.parse(value);
    } catch {
      return {};
    }
  }

  return isRecord(decoded) ? decoded : {};
}

function parseRawPortion(
  value: unknown
): { value: number; entered: string; unit: string } | null {
  let decoded: unknown = value;
  if (typeof value === "string") {
    try {
      decoded = JSON.parse(value);
    } catch {
      return null;
    }
  }
  if (!isRecord(decoded)) {
    return null;
  }

  const portionValue = numberValue(decoded.value);
  const entered = stringValue(decoded.entered);
  const unit = stringValue(decoded.unit);
  if (portionValue === null || entered === null || unit === null) {
    return null;
  }

  return { value: portionValue, entered, unit };
}

function projectMealRow(
  row: RawMealRow,
  fields: readonly (typeof AGENT_MEAL_LIST_FIELDS)[number][],
  entries: readonly AgentMealEntry[]
) {
  const payload = row.payload;
  const full: Record<string, unknown> = {
    id: row.id,
    mealType: stringValue(payload.meal_type),
    startedAt: stringValue(payload.started_at),
    endedAt: stringValue(payload.ended_at),
    timezone: stringValue(payload.timezone),
    localDate: stringValue(payload.local_date),
    entries: [...entries]
  };

  return AgentMealListItemSchema.parse(
    Object.fromEntries(fields.map((field) => [field, full[field]]))
  );
}
