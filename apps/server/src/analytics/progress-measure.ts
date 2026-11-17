// The Progress Measure core (docs/designs/progress-overview.md, D0 and D4): one
// number per Logged Workout for an exercise, taken from its Record Profile, and
// the New Bests among them. The TypeScript twin of
// apps/mobile/lib/domain/analytics/progress_measure.dart, pinned with it by
// packages/golden-vectors/vectors/m37-progress-measure.json, so an Agent read
// and Progress Overview never disagree about what was a New Best.
//
// Pure: no I/O, no clock. Dates are local `YYYY-MM-DD` strings and instants
// ISO-8601 strings. Every value comes from the existing exercise analytics
// engine, which is called per Workout and not changed, so its unit
// normalization and record rules apply. Nothing returned here is stored.
// Id order is the Protocol plan core's code-unit order, which matches Dart's
// String.compareTo.

import { compareIds } from "../protocol-plan.js";
import {
  ExerciseAnalyticsEngine,
  type AnalyticsSet,
  type ExerciseAnalyticsProfile,
  type ExerciseAnalyticsResult,
  type LoggedSetValues,
  type RecordProfile,
  type TrainingUnit
} from "./exercise-analytics.js";

/** A local `YYYY-MM-DD` date. */
export type ProgressLocalDate = string;

/** D4's measures, one per Record Profile that has a single best number. */
export type ProgressMeasureKind =
  | "estimatedOneRepMax"
  | "maxLoad"
  | "maxReps"
  | "maxDuration"
  | "minDuration"
  | "maxDistance"
  | "fastestPace";

export type ProgressBetterIs = "higher" | "lower";

/**
 * One Set of a Workout (D0). `values` is the engine's logged-values shape; a
 * Set with `isCompleted` false is not Performed and is ignored.
 */
export type ProgressSet = {
  id: string;
  position: number;
  isCompleted: boolean;
  values: LoggedSetValues;
};

/** One Workout's Sets of the exercise. The loaders drop deleted Workouts. */
export type ProgressWorkoutSets = {
  workoutId: string;
  localDate: ProgressLocalDate;
  startedAt: string;
  sets: readonly ProgressSet[];
};

/** `setId` is the Set the engine's value came from. */
export type ProgressPoint = {
  workoutId: string;
  localDate: ProgressLocalDate;
  startedAt: string;
  setId: string;
  value: number;
  unit: TrainingUnit;
  isNewBest: boolean;
};

export type ProgressSeries = {
  exerciseId: string;
  measure: ProgressMeasureKind;
  betterIs: ProgressBetterIs;
  points: ProgressPoint[];
};

export type NewBest = {
  exerciseId: string;
  measure: ProgressMeasureKind;
  workoutId: string;
  localDate: ProgressLocalDate;
  startedAt: string;
  setId: string;
  value: number;
  unit: TrainingUnit;
};

const engine = new ExerciseAnalyticsEngine();

// D4's table. `minAssistancePerRepCount` is a record per rep count, so no
// single number would agree with the engine; `completionStreak` has no value.
const MEASURE_BY_RECORD_PROFILE: Readonly<
  Record<RecordProfile, { measure: ProgressMeasureKind; betterIs: ProgressBetterIs } | null>
> = {
  repMax: { measure: "estimatedOneRepMax", betterIs: "higher" },
  maxLoad: { measure: "maxLoad", betterIs: "higher" },
  maxReps: { measure: "maxReps", betterIs: "higher" },
  maxDuration: { measure: "maxDuration", betterIs: "higher" },
  maxDistance: { measure: "maxDistance", betterIs: "higher" },
  minDuration: { measure: "minDuration", betterIs: "lower" },
  fastestPace: { measure: "fastestPace", betterIs: "lower" },
  minAssistancePerRepCount: null,
  completionStreak: null
};

/**
 * The exercise's Progress Measure per Logged Workout (D4), or null for a
 * Record Profile with no single best number. Each Workout's Performed Sets
 * run through the engine on their own, with `performedAt` the Workout's
 * `startedAt` and the sequence the Set's `position`; a Workout with no
 * Performed Set, or no value for the measure, has no point. Points are ordered
 * by (localDate, startedAt, workoutId), and a point is a New Best when it is
 * strictly better than every earlier one, so the first point never is.
 */
export function progressSeries({
  exerciseId,
  profile,
  workouts
}: {
  exerciseId: string;
  profile: ExerciseAnalyticsProfile;
  workouts: readonly ProgressWorkoutSets[];
}): ProgressSeries | null {
  const kind = MEASURE_BY_RECORD_PROFILE[profile.recordProfile];
  if (kind === null) {
    return null;
  }

  const ordered = [...workouts].sort(
    (left, right) =>
      compareIds(left.localDate, right.localDate) ||
      Date.parse(left.startedAt) - Date.parse(right.startedAt) ||
      compareIds(left.workoutId, right.workoutId)
  );

  const points: ProgressPoint[] = [];
  let best: number | null = null;
  for (const workout of ordered) {
    const performed = workout.sets.filter((set) => set.isCompleted);
    if (performed.length === 0) {
      continue;
    }
    const performedAt = new Date(workout.startedAt);
    const result = engine.compute({
      profile,
      sets: performed.map(
        (set): AnalyticsSet => ({
          id: set.id,
          performedAt,
          sequence: set.position,
          values: set.values
        })
      )
    });
    const taken = measureValue(kind.measure, result, performed);
    if (taken === null) {
      continue;
    }

    const isNewBest = best !== null && isBetter(taken.value, best, kind.betterIs);
    if (best === null || isNewBest) {
      best = taken.value;
    }
    points.push({
      workoutId: workout.workoutId,
      localDate: workout.localDate,
      startedAt: workout.startedAt,
      setId: taken.setId,
      value: taken.value,
      unit: taken.unit,
      isNewBest
    });
  }

  return { exerciseId, measure: kind.measure, betterIs: kind.betterIs, points };
}

// The value D4 takes from one Workout's engine result. For e1RM, the highest
// point; on a tie, the Set with the lower (position, id), compared here rather
// than left to the engine's own Set order.
function measureValue(
  measure: ProgressMeasureKind,
  result: ExerciseAnalyticsResult,
  sets: readonly ProgressSet[]
): { setId: string; value: number; unit: TrainingUnit } | null {
  if (measure !== "estimatedOneRepMax") {
    const record = result.headlineRecord;
    return record === null ? null : { setId: record.setId, value: record.value, unit: record.unit };
  }

  const positionById = new Map(sets.map((set) => [set.id, set.position]));
  const compareSets = (left: string, right: string) =>
    (positionById.get(left) ?? 0) - (positionById.get(right) ?? 0) || compareIds(left, right);
  let best: { setId: string; value: number; unit: TrainingUnit } | null = null;
  for (const point of result.estimatedOneRepMax.points) {
    if (
      best === null ||
      point.value > best.value ||
      (point.value === best.value && compareSets(point.setId, best.setId) < 0)
    ) {
      best = { setId: point.setId, value: point.value, unit: point.unit };
    }
  }
  return best;
}

function isBetter(candidate: number, current: number, betterIs: ProgressBetterIs): boolean {
  return betterIs === "higher" ? candidate > current : candidate < current;
}

/**
 * Every New Best point of `series` whose `localDate` is in [from, to] (D4),
 * newest first: by localDate, startedAt and workoutId descending, then
 * exerciseId ascending. The series carry each exercise's whole history, so a
 * best in the period is judged against everything before it.
 */
export function newBestsBetween(
  series: readonly ProgressSeries[],
  from: ProgressLocalDate,
  to: ProgressLocalDate
): NewBest[] {
  const bests: NewBest[] = [];
  for (const one of series) {
    for (const point of one.points) {
      if (point.isNewBest && point.localDate >= from && point.localDate <= to) {
        bests.push({
          exerciseId: one.exerciseId,
          measure: one.measure,
          workoutId: point.workoutId,
          localDate: point.localDate,
          startedAt: point.startedAt,
          setId: point.setId,
          value: point.value,
          unit: point.unit
        });
      }
    }
  }
  return bests.sort(
    (left, right) =>
      compareIds(right.localDate, left.localDate) ||
      Date.parse(right.startedAt) - Date.parse(left.startedAt) ||
      compareIds(right.workoutId, left.workoutId) ||
      compareIds(left.exerciseId, right.exerciseId)
  );
}
