// The training progress core (docs/designs/progress-overview.md, D0-D3): how
// this week went against the weekly Routines, which dates were Trained Days,
// and how much time each Focus got. The TypeScript twin of
// apps/mobile/lib/domain/training/training_progress.dart, pinned with it by
// packages/golden-vectors/vectors/m37-training-progress.json, so an Agent read
// and Progress Overview never disagree.
//
// Pure and timezone-free: dates are local `YYYY-MM-DD` strings, instants are
// ISO-8601 strings, and "today" is an input. Nothing returned here is stored.
// Date arithmetic and id order are the Protocol plan core's, which pins the
// same UTC epoch-day and code-unit rules against Dart.

import {
  compareIds,
  epochDay,
  epochDayIsoWeekday,
  localDateFromEpochDay
} from "../protocol-plan.js";

/** A local `YYYY-MM-DD` date. */
export type TrainingLocalDate = string;

/** The `secondsByFocus` key for Workouts without a Focus (D3). */
export const NO_FOCUS_KEY = "none";

/** The longest range `trainingDays` accepts, in dates. */
export const MAX_TRAINING_DAYS_RANGE = 366;

/** D1's nine statuses, as their wire values. Never a score. */
export type TrainingDayStatus =
  | "done"
  | "partly_done"
  | "done_differently"
  | "not_done"
  | "pending"
  | "planned"
  | "trained"
  | "rest"
  | "no_plan";

/** `weekday` is ISO, 1 = Monday to 7 = Sunday, from the entry's slot. */
export type WeeklyPlanEntry = {
  workoutTemplateId: string;
  weekday: number;
};

export type WeeklyPlan = {
  routineId: string;
  entries: readonly WeeklyPlanEntry[];
};

/**
 * One Workout's facts (D0, D1). A Workout with `performedSetCount` 0 is not a
 * Logged Workout and every function here ignores it. `endedAt` is null for an
 * Open Workout.
 */
export type ProgressWorkout = {
  workoutId: string;
  localDate: TrainingLocalDate;
  startedAt: string;
  endedAt: string | null;
  focusId: string | null;
  linkedTemplateId: string | null;
  performedSetCount: number;
};

export type TrainingWeekDay = {
  localDate: TrainingLocalDate;
  status: TrainingDayStatus;
  plannedCount: number;
  matchedCount: number;
  workoutCount: number;
};

export type TrainingWeek = {
  weekStart: TrainingLocalDate;
  days: TrainingWeekDay[];
  comparedRoutineIds: string[];
};

export type TrainingWeekCounts = {
  done: number;
  partlyDone: number;
  doneDifferently: number;
  notDone: number;
  trained: number;
};

export type TrainingDay = {
  localDate: TrainingLocalDate;
  workoutCount: number;
  secondsByFocus: Record<string, number>;
};

/**
 * The Training Day Status of each day of the week starting at `weekStart`
 * (D1). Throws a RangeError when `today` is outside that week. Workouts dated
 * outside the week are ignored.
 *
 * Each planned entry of a date, ordered by Routine id then Workout Template
 * id, takes the first unmatched Logged Workout of that date, by start then id,
 * whose `linkedTemplateId` is its template.
 */
export function trainingWeek({
  plans,
  workouts,
  weekStart,
  today
}: {
  plans: readonly WeeklyPlan[];
  workouts: readonly ProgressWorkout[];
  weekStart: TrainingLocalDate;
  today: TrainingLocalDate;
}): TrainingWeek {
  const firstDay = epochDay(weekStart);
  const todayOffset = epochDay(today) - firstDay;
  if (todayOffset < 0 || todayOffset > 6) {
    throw new RangeError(`today ${today} is not in the week starting ${weekStart}.`);
  }

  const comparing = plans.filter((plan) => plan.entries.length > 0);
  const comparedRoutineIds = comparing.map((plan) => plan.routineId).sort(compareIds);
  const loggedByDate = loggedWorkoutsByDate(workouts);

  const days: TrainingWeekDay[] = [];
  for (let offset = 0; offset < 7; offset += 1) {
    const day = firstDay + offset;
    const localDate = localDateFromEpochDay(day);
    const weekday = epochDayIsoWeekday(day);
    const planned = comparing
      .flatMap((plan) =>
        plan.entries
          .filter((entry) => entry.weekday === weekday)
          .map((entry) => ({ routineId: plan.routineId, workoutTemplateId: entry.workoutTemplateId }))
      )
      .sort(
        (left, right) =>
          compareIds(left.routineId, right.routineId) ||
          compareIds(left.workoutTemplateId, right.workoutTemplateId)
      );

    const logged = loggedByDate.get(localDate) ?? [];
    const unmatched = [...logged];
    let matched = 0;
    for (const entry of planned) {
      const index = unmatched.findIndex(
        (workout) => workout.linkedTemplateId === entry.workoutTemplateId
      );
      if (index >= 0) {
        unmatched.splice(index, 1);
        matched += 1;
      }
    }

    days.push({
      localDate,
      status: status(planned.length, matched, logged.length, offset - todayOffset, comparing.length > 0),
      plannedCount: planned.length,
      matchedCount: matched,
      workoutCount: logged.length
    });
  }

  return { weekStart, days, comparedRoutineIds };
}

// D1's status table, checked top to bottom. `sinceToday` is negative for a
// past date, 0 for today and positive for a future date.
function status(
  planned: number,
  matched: number,
  workouts: number,
  sinceToday: number,
  anyPlan: boolean
): TrainingDayStatus {
  if (planned === 0) {
    if (workouts > 0) return "trained";
    return anyPlan ? "rest" : "no_plan";
  }
  if (matched === planned) return "done";
  if (sinceToday === 0) return "pending";
  if (sinceToday > 0) return "planned";
  if (matched > 0) return "partly_done";
  if (workouts > 0) return "done_differently";
  return "not_done";
}

/** The number of `days` with each counted status. */
export function summarizeTrainingWeek(days: readonly TrainingWeekDay[]): TrainingWeekCounts {
  const count = (wanted: TrainingDayStatus) =>
    days.filter((day) => day.status === wanted).length;
  return {
    done: count("done"),
    partlyDone: count("partly_done"),
    doneDifferently: count("done_differently"),
    notDone: count("not_done"),
    trained: count("trained")
  };
}

/**
 * One TrainingDay per date from `from` through `to`, inclusive and ascending
 * (D2, D3). Throws a RangeError when `from` is after `to` or the range holds
 * more than MAX_TRAINING_DAYS_RANGE dates. A Logged Workout's time is
 * `endedAt - startedAt` in whole seconds, truncated, or 0 when it ended before
 * it started; an Open Workout counts but adds no time and no key.
 */
export function trainingDays({
  workouts,
  from,
  to
}: {
  workouts: readonly ProgressWorkout[];
  from: TrainingLocalDate;
  to: TrainingLocalDate;
}): TrainingDay[] {
  const firstDay = epochDay(from);
  const dateCount = epochDay(to) - firstDay + 1;
  if (dateCount < 1 || dateCount > MAX_TRAINING_DAYS_RANGE) {
    throw new RangeError(
      `trainingDays needs from <= to and at most ${MAX_TRAINING_DAYS_RANGE} dates; got ${from} to ${to}.`
    );
  }

  const loggedByDate = loggedWorkoutsByDate(workouts);
  const days: TrainingDay[] = [];
  for (let offset = 0; offset < dateCount; offset += 1) {
    const localDate = localDateFromEpochDay(firstDay + offset);
    const logged = loggedByDate.get(localDate) ?? [];
    // A Map, not an object: a Focus id is opaque synced data, and one named
    // like an Object.prototype member ("constructor", "__proto__") must sum
    // like any other, as it does in the Dart core's Map.
    const secondsByFocus = new Map<string, number>();
    for (const workout of logged) {
      if (workout.endedAt === null) {
        continue;
      }
      const seconds = Math.trunc((Date.parse(workout.endedAt) - Date.parse(workout.startedAt)) / 1000);
      const key = workout.focusId ?? NO_FOCUS_KEY;
      secondsByFocus.set(key, (secondsByFocus.get(key) ?? 0) + Math.max(seconds, 0));
    }
    days.push({
      localDate,
      workoutCount: logged.length,
      secondsByFocus: Object.fromEntries(secondsByFocus)
    });
  }
  return days;
}

// The Logged Workouts of each date, ordered by start then id.
function loggedWorkoutsByDate(
  workouts: readonly ProgressWorkout[]
): Map<TrainingLocalDate, ProgressWorkout[]> {
  const byDate = new Map<TrainingLocalDate, ProgressWorkout[]>();
  for (const workout of workouts) {
    if (workout.performedSetCount > 0) {
      const logged = byDate.get(workout.localDate);
      if (logged === undefined) {
        byDate.set(workout.localDate, [workout]);
      } else {
        logged.push(workout);
      }
    }
  }
  for (const logged of byDate.values()) {
    logged.sort(
      (left, right) =>
        Date.parse(left.startedAt) - Date.parse(right.startedAt) ||
        compareIds(left.workoutId, right.workoutId)
    );
  }
  return byDate;
}
