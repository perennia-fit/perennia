import { createRoute, z } from "@hono/zod-openapi";
import { and, asc, eq, isNull } from "drizzle-orm";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import {
  AgentNutritionReadInvalidRangeResponseSchema,
  AgentNutritionReadUnavailableResponseSchema,
  type AgentNutritionReadStore
} from "./agent-nutrition-reads.js";
import {
  computeEnergyBalance,
  computeProteinOnTrainingDays,
  computeWorkoutFuelling,
  summarizeEnergyBalance,
  utcDayKey,
  type CaloriesBurnedReading,
  type MealTiming,
  type WorkoutTiming
} from "./analytics/cross-domain-analytics.js";
import {
  enumerateNutritionDays,
  type AnalyticsNutritionDay
} from "./analytics/nutrition-analytics.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";

/** Same 366-day egress cap the nutrition reads use, kept in lockstep. */
export const AGENT_CROSS_DOMAIN_MAX_RANGE_DAYS = 366;

/** The well-known monitoring `Metric` name supplying the energy-out side. */
export const CALORIES_BURNED_METRIC_NAME = "Calories Burned";

/** Default pre/post fuelling windows (minutes) around a `Workout` start. */
export const DEFAULT_FUELLING_WINDOW_MINUTES = 120;
export const MAX_FUELLING_WINDOW_MINUTES = 720;

/**
 * The widest fuelling fan-out one read returns. Pre/post counts roll up over the
 * whole range, but the per-workout breakdown is capped so a long range cannot
 * turn the data-minimizing summary into an unbounded per-workout dump.
 */
export const AGENT_CROSS_DOMAIN_MAX_WORKOUT_POINTS = 200;

const NUTRITION_DAY_REGEX = /^\d{4}-\d{2}-\d{2}$/;

const RangeQuerySchema = z.object({
  from: z.string().trim().regex(NUTRITION_DAY_REGEX).openapi({
    param: { name: "from", in: "query" },
    description: "Inclusive Nutrition Day lower bound (YYYY-MM-DD)."
  }),
  to: z.string().trim().regex(NUTRITION_DAY_REGEX).openapi({
    param: { name: "to", in: "query" },
    description: "Inclusive Nutrition Day upper bound (YYYY-MM-DD)."
  })
});

export const AgentEnergyBalanceQuerySchema = RangeQuerySchema;

export const AgentTrainingDayNutritionQuerySchema = RangeQuerySchema.extend({
  preWindowMinutes: z.coerce
    .number()
    .int()
    .min(1)
    .max(MAX_FUELLING_WINDOW_MINUTES)
    .default(DEFAULT_FUELLING_WINDOW_MINUTES)
    .openapi({
      param: { name: "preWindowMinutes", in: "query" },
      description:
        "Minutes before a Workout start that count a Meal as pre-workout fuelling."
    }),
  postWindowMinutes: z.coerce
    .number()
    .int()
    .min(1)
    .max(MAX_FUELLING_WINDOW_MINUTES)
    .default(DEFAULT_FUELLING_WINDOW_MINUTES)
    .openapi({
      param: { name: "postWindowMinutes", in: "query" },
      description:
        "Minutes after a Workout start that count a Meal as post-workout fuelling."
    })
});

const AgentDailyEnergyBalanceSchema = z
  .object({
    localDate: z.string().min(1),
    status: z.enum(["computed", "indeterminate"]).openapi({
      description:
        "computed when both sides are known; indeterminate when energy-in was incomplete or no calories-burned Reading landed that day (0 != unknown)."
    }),
    energyIn: z.number().nullable().openapi({
      description:
        "Derived nutrition energy total (kcal), or null when incomplete. Never a fabricated value for an unknown in-side."
    }),
    energyOut: z.number().nullable().openapi({
      description:
        "Sum of the day's calories-burned Metric Readings (kcal), or null when there is no Reading (an unknown out-side, never an implicit 0)."
    }),
    net: z.number().nullable().openapi({
      description: "energy-in - energy-out when both sides are known, else null."
    })
  })
  .strict()
  .openapi("AgentDailyEnergyBalance");

const AgentEnergyBalanceSummarySchema = z
  .object({
    computedDayCount: z.number().int().min(0),
    indeterminateDayCount: z.number().int().min(0),
    averageEnergyIn: z.number().nullable(),
    averageEnergyOut: z.number().nullable(),
    averageNet: z.number().nullable(),
    cumulativeNet: z.number().nullable()
  })
  .strict()
  .openapi("AgentEnergyBalanceSummary");

export const AgentEnergyBalanceResponseSchema = z
  .object({
    from: z.string().min(1),
    to: z.string().min(1),
    dayCount: z.number().int().min(1),
    unit: z.literal("kilocalorie"),
    caloriesBurnedMetricName: z.string().min(1).openapi({
      description: "The monitoring Metric whose Readings supplied the energy-out side."
    }),
    summary: AgentEnergyBalanceSummarySchema,
    days: z.array(AgentDailyEnergyBalanceSchema)
  })
  .strict()
  .openapi("AgentEnergyBalanceResponse");

const AgentProteinCohortSchema = z
  .object({
    dayCount: z.number().int().min(0),
    completeDayCount: z.number().int().min(0),
    incompleteDayCount: z.number().int().min(0).openapi({
      description:
        "Cohort days whose protein total was incomplete; held out of the average rather than counted as 0 (NUTRITION.md §4)."
    }),
    averageProtein: z.number().nullable(),
    totalProtein: z.number().nullable()
  })
  .strict()
  .openapi("AgentProteinCohort");

const AgentWorkoutFuellingSchema = z
  .object({
    workoutId: z.string().min(1),
    workoutStartedAt: z.string().min(1),
    preWorkoutMealCount: z.number().int().min(0),
    postWorkoutMealCount: z.number().int().min(0),
    minutesSincePreWorkoutMeal: z.number().nullable(),
    minutesUntilPostWorkoutMeal: z.number().nullable()
  })
  .strict()
  .openapi("AgentWorkoutFuelling");

const AgentFuellingSummarySchema = z
  .object({
    workoutCount: z.number().int().min(0),
    workoutsWithPreMeal: z.number().int().min(0),
    workoutsWithPostMeal: z.number().int().min(0)
  })
  .strict()
  .openapi("AgentFuellingSummary");

export const AgentTrainingDayNutritionResponseSchema = z
  .object({
    from: z.string().min(1),
    to: z.string().min(1),
    dayCount: z.number().int().min(1),
    trainingDayCount: z.number().int().min(0).openapi({
      description: "Range days bearing at least one Workout."
    }),
    proteinUnit: z.literal("gram"),
    protein: z
      .object({
        trainingDays: AgentProteinCohortSchema,
        restDays: AgentProteinCohortSchema
      })
      .strict(),
    fuelling: z
      .object({
        preWindowMinutes: z.number().int().min(1),
        postWindowMinutes: z.number().int().min(1),
        summary: AgentFuellingSummarySchema,
        perWorkout: z.array(AgentWorkoutFuellingSchema),
        workoutPointLimit: z
          .number()
          .int()
          .min(1)
          .max(AGENT_CROSS_DOMAIN_MAX_WORKOUT_POINTS),
        truncated: z.boolean().openapi({
          description:
            "True when more workouts matched than the per-workout breakdown returns; the summary counts still reflect all of them."
        })
      })
      .strict()
  })
  .strict()
  .openapi("AgentTrainingDayNutritionResponse");

export const agentEnergyBalanceRoute = createRoute({
  method: "get",
  path: "/agent/cross-domain/energy-balance",
  operationId: "getAgentEnergyBalance",
  tags: ["Agent Reads"],
  summary: "Read computed energy-in vs energy-out balance over a range.",
  description:
    "Joins the derived nutrition energy total (energy-in) against calories-burned Metric Readings (energy-out) per Nutrition Day, computed on demand. The two stay distinct stores combined only at read time: no balance value and no meal<->workout association is ever written, and no Activity Link is created ('join, never merge', NUTRITION.md §8). Unknown-aware: an incomplete energy-in or a day with no calories-burned Reading yields an indeterminate day with a null net rather than a fabricated number (0 != unknown). Data-minimizing per-day + period rollups, never a raw Meal/Reading dump. Pure read — no rows mutate and no Activity Log entry is written.",
  security: [{ bearerAuth: [] }],
  request: {
    query: AgentEnergyBalanceQuerySchema
  },
  responses: {
    200: {
      description: "Computed per-day and period energy balance for the range.",
      content: {
        "application/json": {
          schema: AgentEnergyBalanceResponseSchema
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

export const agentTrainingDayNutritionRoute = createRoute({
  method: "get",
  path: "/agent/cross-domain/training-day-nutrition",
  operationId: "getAgentTrainingDayNutrition",
  tags: ["Agent Reads"],
  summary: "Read protein-on-training-days and pre/post-workout fuelling over a range.",
  description:
    "Joins derived nutrition macros against Workouts by time, computed on demand. Protein-on-training-days compares the average protein on days bearing a Workout against rest days; pre/post-workout fuelling windows each Meal's start against each Workout's started_at at meal-level granularity (NUTRITION.md §1.2). A meal near a workout stays a distinct event — its proximity is computed, never written as an Activity Link or any stored association ('join, never merge', NUTRITION.md §8). Unknown-aware: an incomplete protein day is held out of the cohort average, never counted as 0. Data-minimizing cohort/summary rollups plus a bounded per-workout breakdown, never a raw Meal/Workout dump. Pure read — no rows mutate and no Activity Log entry is written.",
  security: [{ bearerAuth: [] }],
  request: {
    query: AgentTrainingDayNutritionQuerySchema
  },
  responses: {
    200: {
      description:
        "Computed protein-on-training-days cohorts and fuelling summary for the range.",
      content: {
        "application/json": {
          schema: AgentTrainingDayNutritionResponseSchema
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

export type AgentEnergyBalanceQuery = z.infer<typeof AgentEnergyBalanceQuerySchema>;
export type AgentTrainingDayNutritionQuery = z.infer<
  typeof AgentTrainingDayNutritionQuerySchema
>;
export type AgentEnergyBalanceResponse = z.infer<
  typeof AgentEnergyBalanceResponseSchema
>;
export type AgentTrainingDayNutritionResponse = z.infer<
  typeof AgentTrainingDayNutritionResponseSchema
>;

/**
 * The training + monitoring side of the cross-domain join. The nutrition side is
 * read through the existing {@link AgentNutritionReadStore} so the totals match
 * the nutrition reads exactly (parity). This store adds only the two other
 * families it needs to join against — never writing back into either.
 */
export type AgentCrossDomainReadStore = {
  /** Distinct `Workout`s (id + start) in the range, derived from logged `Set`s. */
  readWorkoutTimings(input: {
    userId: string;
    from: string;
    to: string;
  }): Promise<WorkoutTiming[]>;
  /** Calories-burned `Metric` `Reading`s in the range, bucketed onto their day. */
  readCaloriesBurnedReadings(input: {
    userId: string;
    from: string;
    to: string;
  }): Promise<CaloriesBurnedReading[]>;
};

type LoggedSetRow = {
  payload: Record<string, unknown>;
};

type MetricReadingRow = {
  metricName: string;
  scalarValue: number | null;
  atTime: Date | null;
  windowStartedAt: Date | null;
  windowEndedAt: Date | null;
};

export function createDrizzleAgentCrossDomainReadStore(
  db: ServerDatabase
): AgentCrossDomainReadStore {
  return {
    async readWorkoutTimings({ userId, from, to }) {
      const inRange = new Set(enumerateNutritionDays(from, to));
      const rows = await db
        .select({ payload: schema.loggedSets.payload })
        .from(schema.loggedSets)
        .where(
          and(
            eq(schema.loggedSets.userId, userId),
            isNull(schema.loggedSets.deletedAt)
          )
        )
        .orderBy(asc(schema.loggedSets.receivedAt), asc(schema.loggedSets.id));

      // A Workout is a session, not a day-bucket: collapse the logged sets to
      // their distinct workout id + start, then keep the ones whose start day
      // falls in the requested range.
      const byWorkout = new Map<string, WorkoutTiming>();
      for (const row of rows) {
        const timing = mapWorkoutTiming(row);
        if (timing === null || !inRange.has(timing.localDate)) {
          continue;
        }
        if (!byWorkout.has(timing.workoutId)) {
          byWorkout.set(timing.workoutId, timing);
        }
      }

      return [...byWorkout.values()];
    },
    async readCaloriesBurnedReadings({ userId, from, to }) {
      const inRange = new Set(enumerateNutritionDays(from, to));
      const rows: MetricReadingRow[] = await db
        .select({
          metricName: schema.metrics.name,
          scalarValue: schema.metricReadings.scalarValue,
          atTime: schema.metricReadings.atTime,
          windowStartedAt: schema.metricReadings.windowStartedAt,
          windowEndedAt: schema.metricReadings.windowEndedAt
        })
        .from(schema.metricReadings)
        .innerJoin(
          schema.metrics,
          eq(schema.metricReadings.metricId, schema.metrics.id)
        )
        .where(
          and(
            eq(schema.metricReadings.userId, userId),
            eq(schema.metrics.name, CALORIES_BURNED_METRIC_NAME),
            isNull(schema.metricReadings.deletedAt),
            isNull(schema.metrics.deletedAt)
          )
        );

      const readings: CaloriesBurnedReading[] = [];
      for (const row of rows) {
        const reading = mapCaloriesBurnedReading(row);
        if (reading === null || !inRange.has(reading.localDate)) {
          continue;
        }
        readings.push(reading);
      }

      return readings;
    }
  };
}

export function buildAgentEnergyBalanceResponse({
  from,
  to,
  nutritionDays,
  caloriesBurned
}: {
  from: string;
  to: string;
  nutritionDays: readonly AnalyticsNutritionDay[];
  caloriesBurned: readonly CaloriesBurnedReading[];
}): AgentEnergyBalanceResponse {
  const days = enumerateNutritionDays(from, to);
  const daily = computeEnergyBalance({ days, nutritionDays, caloriesBurned });
  const summary = summarizeEnergyBalance(daily);

  return AgentEnergyBalanceResponseSchema.parse({
    from,
    to,
    dayCount: days.length,
    unit: "kilocalorie",
    caloriesBurnedMetricName: CALORIES_BURNED_METRIC_NAME,
    summary: {
      computedDayCount: summary.computedDayCount,
      indeterminateDayCount: summary.indeterminateDayCount,
      averageEnergyIn: canonicalOrNull(summary.averageEnergyIn),
      averageEnergyOut: canonicalOrNull(summary.averageEnergyOut),
      averageNet: canonicalOrNull(summary.averageNet),
      cumulativeNet: canonicalOrNull(summary.cumulativeNet)
    },
    days: daily.map((day) => ({
      localDate: day.localDate,
      status: day.status,
      energyIn: canonicalOrNull(day.energyIn),
      energyOut: canonicalOrNull(day.energyOut),
      net: canonicalOrNull(day.net)
    }))
  });
}

export function buildAgentTrainingDayNutritionResponse({
  from,
  to,
  nutritionDays,
  workouts,
  preWindowMinutes,
  postWindowMinutes
}: {
  from: string;
  to: string;
  nutritionDays: readonly AnalyticsNutritionDay[];
  workouts: readonly WorkoutTiming[];
  preWindowMinutes: number;
  postWindowMinutes: number;
}): AgentTrainingDayNutritionResponse {
  const days = enumerateNutritionDays(from, to);
  const trainingDayDates = new Set(workouts.map((workout) => workout.localDate));
  const protein = computeProteinOnTrainingDays({
    days,
    nutritionDays,
    trainingDayDates
  });

  const meals = mealTimingsFromNutritionDays(nutritionDays);
  const fuelling = computeWorkoutFuelling({
    workouts,
    meals,
    preWindowMinutes,
    postWindowMinutes
  });

  const truncated =
    fuelling.perWorkout.length > AGENT_CROSS_DOMAIN_MAX_WORKOUT_POINTS;
  const perWorkout = fuelling.perWorkout
    .slice(0, AGENT_CROSS_DOMAIN_MAX_WORKOUT_POINTS)
    .map((workout) => ({
      workoutId: workout.workoutId,
      workoutStartedAt: workout.workoutStartedAt,
      preWorkoutMealCount: workout.preWorkoutMealCount,
      postWorkoutMealCount: workout.postWorkoutMealCount,
      minutesSincePreWorkoutMeal: canonicalOrNull(
        workout.minutesSincePreWorkoutMeal
      ),
      minutesUntilPostWorkoutMeal: canonicalOrNull(
        workout.minutesUntilPostWorkoutMeal
      )
    }));

  return AgentTrainingDayNutritionResponseSchema.parse({
    from,
    to,
    dayCount: days.length,
    trainingDayCount: trainingDayDates.size,
    proteinUnit: "gram",
    protein: {
      trainingDays: serializeCohort(protein.trainingDays),
      restDays: serializeCohort(protein.restDays)
    },
    fuelling: {
      preWindowMinutes,
      postWindowMinutes,
      summary: fuelling.summary,
      perWorkout,
      workoutPointLimit: AGENT_CROSS_DOMAIN_MAX_WORKOUT_POINTS,
      truncated
    }
  });
}

/** Flatten the nutrition days into per-meal timings for the fuelling window join. */
export function mealTimingsFromNutritionDays(
  nutritionDays: readonly AnalyticsNutritionDay[]
): MealTiming[] {
  const meals: MealTiming[] = [];
  for (const day of nutritionDays) {
    for (const meal of day.meals) {
      meals.push({
        mealId: meal.id,
        mealType: meal.mealType,
        startedAt: meal.startedAt,
        localDate: day.localDate
      });
    }
  }

  return meals;
}

export function validateCrossDomainRange(
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
  if (days.length > AGENT_CROSS_DOMAIN_MAX_RANGE_DAYS) {
    return {
      ok: false,
      message: `Requested range spans ${days.length} days, exceeding the ${AGENT_CROSS_DOMAIN_MAX_RANGE_DAYS}-day maximum.`
    };
  }

  return { ok: true, dayCount: days.length };
}

function serializeCohort(cohort: ReturnType<
  typeof computeProteinOnTrainingDays
>["trainingDays"]) {
  return {
    dayCount: cohort.dayCount,
    completeDayCount: cohort.completeDayCount,
    incompleteDayCount: cohort.incompleteDayCount,
    averageProtein: canonicalOrNull(cohort.averageProtein),
    totalProtein: canonicalOrNull(cohort.totalProtein)
  };
}

function mapWorkoutTiming(row: LoggedSetRow): WorkoutTiming | null {
  const payload = row.payload;
  const workoutId = stringValue(payload.workout_id);
  const startedAt =
    dateValue(payload.workout_started_at) ?? dateValue(payload.performed_at);
  if (workoutId === null || startedAt === null) {
    return null;
  }

  return {
    workoutId,
    startedAt,
    localDate: utcDayKey(startedAt)
  };
}

function mapCaloriesBurnedReading(row: MetricReadingRow): CaloriesBurnedReading | null {
  const value = row.scalarValue;
  if (value === null || !Number.isFinite(value)) {
    return null;
  }
  const instant = row.atTime ?? row.windowStartedAt ?? row.windowEndedAt;
  if (instant === null) {
    return null;
  }

  return { localDate: utcDayKey(instant), value };
}

function canonicalOrNull(value: number | null): number | null {
  return value === null ? null : Number.parseFloat(value.toFixed(6));
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function dateValue(value: unknown): Date | null {
  if (typeof value !== "string" || value.trim().length === 0) {
    return null;
  }
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}
