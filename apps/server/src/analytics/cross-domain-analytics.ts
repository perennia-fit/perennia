/**
 * Server-side cross-domain analytics — the **derived time-joins** the agent read
 * surface exposes. It combines three otherwise-distinct stores at read
 * time only: the derived nutrition analytics (energy + macros over `Food Entry`
 * snapshots), training (`Workout`s, surfaced through logged `Set`s), and
 * monitoring (calories-burned `Metric` `Reading`s).
 *
 * The join key is **time**. A meal near a workout is a *temporally related but
 * distinct event* — never the same session — so nothing here is ever written
 * back as an `Activity Link` or any stored association ("join, never merge",
 * NUTRITION.md §8). Every value is computed on demand and stored nowhere.
 *
 *
 * Everything stays **unknown-aware** (`0 ≠ unknown`, NUTRITION.md §4): an
 * incomplete energy-in or a day with no calories-burned `Reading` is held out of
 * the subtraction rather than coerced to zero. This module mirrors the
 * device-canonical EnergyBalance.derive in
 * apps/mobile/lib/domain/analytics/energy_balance.dart so an agent and the phone
 * agree on the same range.
 */

import {
  dayTotals,
  type AnalyticsNutritionDay,
  type NutrientId
} from "./nutrition-analytics.js";

/** A calories-burned `Metric` `Reading`, reduced to the day it lands on. */
export type CaloriesBurnedReading = {
  /** The Nutrition Day (`YYYY-MM-DD`) the reading's instant falls on (UTC). */
  localDate: string;
  /** kilocalories burned; a finite scalar (unknown readings are dropped upstream). */
  value: number;
};

/** A logged `Workout`, reduced to the timing the time-join needs. */
export type WorkoutTiming = {
  /** The Workout id (a Workout is a session, not a day-bucket). */
  workoutId: string;
  /** Session start instant. */
  startedAt: Date;
  /** The Nutrition Day (`YYYY-MM-DD`) the session start falls on (UTC). */
  localDate: string;
};

/** A `Meal`, reduced to the timing + derived energy/protein the join needs. */
export type MealTiming = {
  mealId: string;
  mealType: string;
  startedAt: Date;
  /** The Nutrition Day (`YYYY-MM-DD`) the meal was logged on, as stored. */
  localDate: string;
};

export type EnergyBalanceStatus = "computed" | "indeterminate";

/**
 * One day's **energy-in vs energy-out**, joined from two independent sources and
 * stored nowhere. `net = energyIn − energyOut` only when *both* sides are known;
 * an incomplete in-side or a day with no calories-burned `Reading` yields an
 * `indeterminate` day with a `null` net — never a fabricated number.
 */
export type DailyEnergyBalance = {
  localDate: string;
  status: EnergyBalanceStatus;
  /** Known energy-in (kcal), or null when the derived energy total was incomplete. */
  energyIn: number | null;
  /** Known energy-out (kcal), or null when no calories-burned Reading landed that day. */
  energyOut: number | null;
  /** energy-in − energy-out when both are known, else null. */
  net: number | null;
};

export type EnergyBalancePeriodSummary = {
  /** Days in the range with a `computed` balance (both sides known). */
  computedDayCount: number;
  /** Days held out because one side was unknown. */
  indeterminateDayCount: number;
  /** Mean energy-in over computed days, or null when none are computed. */
  averageEnergyIn: number | null;
  /** Mean energy-out over computed days, or null when none are computed. */
  averageEnergyOut: number | null;
  /** Mean net over computed days, or null when none are computed. */
  averageNet: number | null;
  /** Sum of net over computed days, or null when none are computed. */
  cumulativeNet: number | null;
};

const ENERGY: NutrientId = "energy";

/**
 * Derive one day's energy balance from the two independent sides. Mirrors
 * EnergyBalance.derive: the in-side counts only when its derived total is
 * complete; the out-side counts only when a calories-burned `Reading` exists.
 */
export function deriveDailyEnergyBalance({
  localDate,
  energyIn,
  energyInComplete,
  energyOut
}: {
  localDate: string;
  energyIn: number;
  energyInComplete: boolean;
  energyOut: number | null;
}): DailyEnergyBalance {
  const inKnown = energyInComplete;
  const outKnown = energyOut !== null;
  const status: EnergyBalanceStatus =
    inKnown && outKnown ? "computed" : "indeterminate";
  const inValue = inKnown ? energyIn : null;
  const outValue = outKnown ? energyOut : null;

  return {
    localDate,
    status,
    energyIn: inValue,
    energyOut: outValue,
    net: status === "computed" ? inValue! - outValue! : null
  };
}

/**
 * Join derived nutrition energy totals against calories-burned `Metric`
 * `Reading`s by day, for an enumerated, ordered list of `days`. Each day yields
 * exactly one balance. Energy-out per day is the sum of that day's known
 * calories-burned `Reading`s; a day with none stays unknown (never an implicit
 * 0). Pure value computation — nothing is stored ("join, never merge").
 */
export function computeEnergyBalance({
  days,
  nutritionDays,
  caloriesBurned
}: {
  days: readonly string[];
  nutritionDays: readonly AnalyticsNutritionDay[];
  caloriesBurned: readonly CaloriesBurnedReading[];
}): DailyEnergyBalance[] {
  const nutritionByDate = new Map<string, AnalyticsNutritionDay>();
  for (const day of nutritionDays) {
    nutritionByDate.set(day.localDate, day);
  }

  const energyOutByDate = sumCaloriesBurnedByDay(caloriesBurned);

  return days.map((localDate) => {
    const nutritionDay = nutritionByDate.get(localDate) ?? {
      localDate,
      meals: []
    };
    const energyTotal = dayTotals(nutritionDay).get(ENERGY);
    const energyIn = energyTotal?.value ?? 0;
    const energyInComplete = energyTotal?.isComplete ?? true;
    const energyOut = energyOutByDate.has(localDate)
      ? energyOutByDate.get(localDate)!
      : null;

    return deriveDailyEnergyBalance({
      localDate,
      energyIn,
      energyInComplete,
      energyOut
    });
  });
}

/**
 * Roll a per-day balance up over the period. Averages and the cumulative net are
 * over `computed` days only — an `indeterminate` day is held out of the rollup
 * rather than dragging an unknown into the mean (`0 ≠ unknown`).
 */
export function summarizeEnergyBalance(
  daily: readonly DailyEnergyBalance[]
): EnergyBalancePeriodSummary {
  const computed = daily.filter((day) => day.status === "computed");
  const indeterminateDayCount = daily.length - computed.length;
  if (computed.length === 0) {
    return {
      computedDayCount: 0,
      indeterminateDayCount,
      averageEnergyIn: null,
      averageEnergyOut: null,
      averageNet: null,
      cumulativeNet: null
    };
  }

  const sumIn = computed.reduce((sum, day) => sum + day.energyIn!, 0);
  const sumOut = computed.reduce((sum, day) => sum + day.energyOut!, 0);
  const sumNet = computed.reduce((sum, day) => sum + day.net!, 0);

  return {
    computedDayCount: computed.length,
    indeterminateDayCount,
    averageEnergyIn: sumIn / computed.length,
    averageEnergyOut: sumOut / computed.length,
    averageNet: sumNet / computed.length,
    cumulativeNet: sumNet
  };
}

export type ProteinByDayCohort = {
  /** Days in the cohort (range days that are/aren't training days). */
  dayCount: number;
  /** Cohort days whose protein total was complete. */
  completeDayCount: number;
  /** Cohort days whose protein total was incomplete (held out of the average). */
  incompleteDayCount: number;
  /** Mean protein (g) over the cohort's complete days, or null when none. */
  averageProtein: number | null;
  /** Sum of protein (g) over the cohort's complete days, or null when none. */
  totalProtein: number | null;
};

export type ProteinOnTrainingDays = {
  trainingDays: ProteinByDayCohort;
  restDays: ProteinByDayCohort;
};

const PROTEIN: NutrientId = "protein";

/**
 * Compare protein intake on **training days** (days bearing at least one
 * `Workout`) against **rest days**, across the range. A day's protein total is
 * the derived nutrition analytic over its `Food Entry`s; an incomplete total is
 * held out of the cohort average rather than coerced to 0 (NUTRITION.md §4).
 *
 * Training-day membership is a pure time-join on the day grid — no association is
 * written linking a meal to a workout ("join, never merge").
 */
export function computeProteinOnTrainingDays({
  days,
  nutritionDays,
  trainingDayDates
}: {
  days: readonly string[];
  nutritionDays: readonly AnalyticsNutritionDay[];
  trainingDayDates: ReadonlySet<string>;
}): ProteinOnTrainingDays {
  const nutritionByDate = new Map<string, AnalyticsNutritionDay>();
  for (const day of nutritionDays) {
    nutritionByDate.set(day.localDate, day);
  }

  const trainingTotals: ProteinDayPoint[] = [];
  const restTotals: ProteinDayPoint[] = [];
  for (const localDate of days) {
    const nutritionDay = nutritionByDate.get(localDate) ?? {
      localDate,
      meals: []
    };
    const proteinTotal = dayTotals(nutritionDay).get(PROTEIN);
    const point: ProteinDayPoint = {
      value: proteinTotal?.value ?? 0,
      isComplete: proteinTotal?.isComplete ?? true
    };
    if (trainingDayDates.has(localDate)) {
      trainingTotals.push(point);
    } else {
      restTotals.push(point);
    }
  }

  return {
    trainingDays: cohort(trainingTotals),
    restDays: cohort(restTotals)
  };
}

export type FuellingWindow = "pre" | "post";

export type WorkoutFuelling = {
  workoutId: string;
  workoutStartedAt: string;
  /** Count of meals that started within `preWindowMinutes` before the workout. */
  preWorkoutMealCount: number;
  /** Count of meals that started within `postWindowMinutes` after the workout. */
  postWorkoutMealCount: number;
  /** Minutes from the nearest pre-workout meal start to the workout, or null. */
  minutesSincePreWorkoutMeal: number | null;
  /** Minutes from the workout to the nearest post-workout meal start, or null. */
  minutesUntilPostWorkoutMeal: number | null;
};

export type FuellingSummary = {
  workoutCount: number;
  /** Workouts with at least one meal inside the pre-window. */
  workoutsWithPreMeal: number;
  /** Workouts with at least one meal inside the post-window. */
  workoutsWithPostMeal: number;
};

/**
 * Window each `Meal`'s `started_at` against each `Workout`'s `started_at`. A meal
 * inside `[start − preWindow, start)` is pre-workout fuelling; one inside
 * `[start, start + postWindow]` is post-workout. This is the headline
 * meal-level-granularity join (NUTRITION.md §1.2): the meal stays a distinct
 * event — its proximity to the workout is computed, never stored as a link.
 *
 * The shape is data-minimizing: per-workout *counts* and the nearest-meal gap,
 * never a dump of the matched meals.
 */
export function computeWorkoutFuelling({
  workouts,
  meals,
  preWindowMinutes,
  postWindowMinutes
}: {
  workouts: readonly WorkoutTiming[];
  meals: readonly MealTiming[];
  preWindowMinutes: number;
  postWindowMinutes: number;
}): { perWorkout: WorkoutFuelling[]; summary: FuellingSummary } {
  const preWindowMs = preWindowMinutes * 60_000;
  const postWindowMs = postWindowMinutes * 60_000;
  const mealStartsMs = meals
    .map((meal) => meal.startedAt.getTime())
    .sort((left, right) => left - right);

  const perWorkout = workouts
    .slice()
    .sort(
      (left, right) =>
        left.startedAt.getTime() - right.startedAt.getTime() ||
        left.workoutId.localeCompare(right.workoutId)
    )
    .map((workout) => {
      const startMs = workout.startedAt.getTime();
      let preCount = 0;
      let postCount = 0;
      let nearestPreGapMs: number | null = null;
      let nearestPostGapMs: number | null = null;

      for (const mealMs of mealStartsMs) {
        const deltaMs = mealMs - startMs;
        if (deltaMs < 0 && -deltaMs <= preWindowMs) {
          preCount += 1;
          const gap = -deltaMs;
          if (nearestPreGapMs === null || gap < nearestPreGapMs) {
            nearestPreGapMs = gap;
          }
        } else if (deltaMs >= 0 && deltaMs <= postWindowMs) {
          postCount += 1;
          if (nearestPostGapMs === null || deltaMs < nearestPostGapMs) {
            nearestPostGapMs = deltaMs;
          }
        }
      }

      return {
        workoutId: workout.workoutId,
        workoutStartedAt: workout.startedAt.toISOString(),
        preWorkoutMealCount: preCount,
        postWorkoutMealCount: postCount,
        minutesSincePreWorkoutMeal:
          nearestPreGapMs === null ? null : nearestPreGapMs / 60_000,
        minutesUntilPostWorkoutMeal:
          nearestPostGapMs === null ? null : nearestPostGapMs / 60_000
      };
    });

  return {
    perWorkout,
    summary: {
      workoutCount: perWorkout.length,
      workoutsWithPreMeal: perWorkout.filter(
        (workout) => workout.preWorkoutMealCount > 0
      ).length,
      workoutsWithPostMeal: perWorkout.filter(
        (workout) => workout.postWorkoutMealCount > 0
      ).length
    }
  };
}

type ProteinDayPoint = { value: number; isComplete: boolean };

function cohort(points: readonly ProteinDayPoint[]): ProteinByDayCohort {
  const complete = points.filter((point) => point.isComplete);
  const incompleteDayCount = points.length - complete.length;
  if (complete.length === 0) {
    return {
      dayCount: points.length,
      completeDayCount: 0,
      incompleteDayCount,
      averageProtein: null,
      totalProtein: null
    };
  }

  const sum = complete.reduce((total, point) => total + point.value, 0);
  return {
    dayCount: points.length,
    completeDayCount: complete.length,
    incompleteDayCount,
    averageProtein: sum / complete.length,
    totalProtein: sum
  };
}

/** Sum known calories-burned `Reading`s onto their day. A day with no reading is absent. */
function sumCaloriesBurnedByDay(
  readings: readonly CaloriesBurnedReading[]
): Map<string, number> {
  const byDate = new Map<string, number>();
  for (const reading of readings) {
    if (!Number.isFinite(reading.value)) {
      continue;
    }
    byDate.set(reading.localDate, (byDate.get(reading.localDate) ?? 0) + reading.value);
  }

  return byDate;
}

/** UTC `YYYY-MM-DD` for an instant — the server-side Nutrition Day bucket. */
export function utcDayKey(instant: Date): string {
  const year = instant.getUTCFullYear().toString().padStart(4, "0");
  const month = (instant.getUTCMonth() + 1).toString().padStart(2, "0");
  const day = instant.getUTCDate().toString().padStart(2, "0");
  return `${year}-${month}-${day}`;
}
