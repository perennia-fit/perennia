/// The training progress core (docs/designs/progress-overview.md, D0-D3):
/// how this week went against the weekly Routines, which dates were Trained
/// Days, and how much time each Focus got. Progress Overview's This week,
/// Trained days and Time by Focus cards read these functions, and so does
/// the Agent read `listAgentTrainingDays`.
///
/// Pure and timezone-free: no I/O, no clock. Dates are local
/// [TrainingDayDate]s and "today" is an input. Nothing returned here is
/// stored or synced.
///
/// [trainingWeek], [summarizeTrainingWeek] and [trainingDays] are pinned
/// against the TypeScript twin (`apps/server/src/analytics/training-progress.ts`)
/// by `packages/golden-vectors/vectors/m37-training-progress.json`.
/// [weeklyFocusSeconds] is Dart only, because an Agent sums the per-date
/// seconds itself.
library;

import 'training_day.dart';

/// The `secondsByFocus` key for Workouts without a Focus (D3).
const String noFocusKey = 'none';

/// The longest range [trainingDays] accepts, in dates: one leap year, the
/// longest period Progress Overview offers.
const int maxTrainingDaysRange = 366;

/// The single label for one day of the current week against the weekly
/// Routines (CONTEXT.md `Training Day Status`), from a closed set. Never a
/// score: UI copy and API fields carry statuses and counts only.
enum TrainingDayStatus {
  done('done'),
  partlyDone('partly_done'),
  doneDifferently('done_differently'),
  notDone('not_done'),
  pending('pending'),
  planned('planned'),
  trained('trained'),
  rest('rest'),
  noPlan('no_plan');

  const TrainingDayStatus(this.wireName);

  final String wireName;
}

/// One planning Routine Entry of a weekly Routine: [weekday] is ISO, 1 is
/// Monday and 7 is Sunday, from the entry's Cadence slot.
final class WeeklyPlanEntry {
  const WeeklyPlanEntry({
    required this.workoutTemplateId,
    required this.weekday,
  });

  final String workoutTemplateId;
  final int weekday;
}

/// One active weekly Routine and the entries that plan something. The
/// loaders drop entries with no slot, archived entries and entries whose
/// Workout Template is archived, as Up next does.
final class WeeklyPlan {
  WeeklyPlan({
    required this.routineId,
    required Iterable<WeeklyPlanEntry> entries,
  }) : entries = List<WeeklyPlanEntry>.unmodifiable(entries);

  final String routineId;
  final List<WeeklyPlanEntry> entries;
}

/// The facts the core needs about one Workout (D0, D1). [linkedTemplateId]
/// is the Workout Template of its Template Link. [performedSetCount] counts
/// its Performed Sets; a Workout with none is not a Logged Workout, and every
/// function here ignores it. An Open Workout has a null [endedAt].
final class ProgressWorkout {
  const ProgressWorkout({
    required this.workoutId,
    required this.localDate,
    required this.startedAt,
    required this.endedAt,
    required this.focusId,
    required this.linkedTemplateId,
    required this.performedSetCount,
  });

  final String workoutId;
  final TrainingDayDate localDate;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? focusId;
  final String? linkedTemplateId;
  final int performedSetCount;

  bool get isLogged => performedSetCount > 0;
}

final class TrainingWeekDay {
  const TrainingWeekDay({
    required this.localDate,
    required this.status,
    required this.plannedCount,
    required this.matchedCount,
    required this.workoutCount,
  });

  final TrainingDayDate localDate;
  final TrainingDayStatus status;
  final int plannedCount;
  final int matchedCount;
  final int workoutCount;
}

final class TrainingWeek {
  TrainingWeek({
    required this.weekStart,
    required Iterable<TrainingWeekDay> days,
    required Iterable<String> comparedRoutineIds,
  })  : days = List<TrainingWeekDay>.unmodifiable(days),
        comparedRoutineIds = List<String>.unmodifiable(comparedRoutineIds);

  final TrainingDayDate weekStart;

  /// Seven days, in date order.
  final List<TrainingWeekDay> days;

  /// The ids of the plans with entries, ascending.
  final List<String> comparedRoutineIds;
}

/// How many days of a week have each counted status. `pending`, `planned`,
/// `rest` and `no_plan` are not counted, so an unfinished today never is.
final class TrainingWeekCounts {
  const TrainingWeekCounts({
    required this.done,
    required this.partlyDone,
    required this.doneDifferently,
    required this.notDone,
    required this.trained,
  });

  final int done;
  final int partlyDone;
  final int doneDifferently;
  final int notDone;
  final int trained;
}

/// One date's Logged Workouts. [secondsByFocus] maps a Focus id, or
/// [noFocusKey], to the summed time of that date's ended Logged Workouts.
final class TrainingDay {
  TrainingDay({
    required this.localDate,
    required this.workoutCount,
    required Map<String, int> secondsByFocus,
  }) : secondsByFocus = Map<String, int>.unmodifiable(secondsByFocus);

  final TrainingDayDate localDate;
  final int workoutCount;
  final Map<String, int> secondsByFocus;
}

final class WeeklyFocusSeconds {
  WeeklyFocusSeconds({
    required this.weekStart,
    required Map<String, int> secondsByFocus,
  }) : secondsByFocus = Map<String, int>.unmodifiable(secondsByFocus);

  final TrainingDayDate weekStart;
  final Map<String, int> secondsByFocus;
}

/// The Training Day Status of each day of the week starting at [weekStart]
/// (D1). [today] must fall inside that week; otherwise this throws an
/// [ArgumentError]. Workouts dated outside the week are ignored, so a caller
/// may pass a wider list.
///
/// Each planned entry of a date, ordered by Routine id then Workout Template
/// id, takes the first unmatched Logged Workout of that date, by start then
/// id, whose [ProgressWorkout.linkedTemplateId] is its template. Matching is
/// by template and date, not by the Template Link's Routine and slot, so a
/// planned workout started from the saved-workouts list counts as done.
TrainingWeek trainingWeek({
  required Iterable<WeeklyPlan> plans,
  required Iterable<ProgressWorkout> workouts,
  required TrainingDayDate weekStart,
  required TrainingDayDate today,
}) {
  final todayOffset = today.daysBetween(weekStart);
  if (todayOffset < 0 || todayOffset > 6) {
    throw ArgumentError.value(
      today.storageValue,
      'today',
      'must be in the week starting ${weekStart.storageValue}',
    );
  }

  final comparing = plans.where((plan) => plan.entries.isNotEmpty).toList();
  final comparedRoutineIds = comparing.map((plan) => plan.routineId).toList()
    ..sort();
  final loggedByDate = _loggedWorkoutsByDate(workouts);

  final days = <TrainingWeekDay>[];
  for (var offset = 0; offset < 7; offset += 1) {
    final date = weekStart.addDays(offset);
    final weekday = date.isoWeekday;
    final planned = <(String, String)>[
      for (final plan in comparing)
        for (final entry in plan.entries)
          if (entry.weekday == weekday)
            (plan.routineId, entry.workoutTemplateId),
    ]..sort((a, b) {
        final byRoutine = a.$1.compareTo(b.$1);
        return byRoutine != 0 ? byRoutine : a.$2.compareTo(b.$2);
      });

    final logged = loggedByDate[date] ?? const <ProgressWorkout>[];
    final unmatched = logged.toList();
    var matched = 0;
    for (final (_, workoutTemplateId) in planned) {
      final index = unmatched.indexWhere(
        (workout) => workout.linkedTemplateId == workoutTemplateId,
      );
      if (index >= 0) {
        unmatched.removeAt(index);
        matched += 1;
      }
    }

    days.add(
      TrainingWeekDay(
        localDate: date,
        status: _status(
          planned: planned.length,
          matched: matched,
          workouts: logged.length,
          sinceToday: offset - todayOffset,
          anyPlan: comparing.isNotEmpty,
        ),
        plannedCount: planned.length,
        matchedCount: matched,
        workoutCount: logged.length,
      ),
    );
  }

  return TrainingWeek(
    weekStart: weekStart,
    days: days,
    comparedRoutineIds: comparedRoutineIds,
  );
}

/// D1's status table, checked top to bottom. [sinceToday] is negative for a
/// past date, 0 for today and positive for a future date.
TrainingDayStatus _status({
  required int planned,
  required int matched,
  required int workouts,
  required int sinceToday,
  required bool anyPlan,
}) {
  if (planned == 0) {
    if (workouts > 0) return TrainingDayStatus.trained;
    return anyPlan ? TrainingDayStatus.rest : TrainingDayStatus.noPlan;
  }
  if (matched == planned) return TrainingDayStatus.done;
  if (sinceToday == 0) return TrainingDayStatus.pending;
  if (sinceToday > 0) return TrainingDayStatus.planned;
  if (matched > 0) return TrainingDayStatus.partlyDone;
  if (workouts > 0) return TrainingDayStatus.doneDifferently;
  return TrainingDayStatus.notDone;
}

/// The number of [days] with each counted status.
TrainingWeekCounts summarizeTrainingWeek(Iterable<TrainingWeekDay> days) {
  int count(TrainingDayStatus status) =>
      days.where((day) => day.status == status).length;
  return TrainingWeekCounts(
    done: count(TrainingDayStatus.done),
    partlyDone: count(TrainingDayStatus.partlyDone),
    doneDifferently: count(TrainingDayStatus.doneDifferently),
    notDone: count(TrainingDayStatus.notDone),
    trained: count(TrainingDayStatus.trained),
  );
}

/// One [TrainingDay] per date from [from] through [to], inclusive and
/// ascending (D2, D3). Throws an [ArgumentError] when [from] is after [to]
/// or the range holds more than [maxTrainingDaysRange] dates. Workouts dated
/// outside the range are ignored.
///
/// A Logged Workout's time is `endedAt - startedAt` in whole seconds,
/// truncated, or 0 when it ended before it started. An Open Workout counts
/// toward [TrainingDay.workoutCount] but adds no time and no key. A Workout
/// counts toward its local date even when it crosses midnight.
List<TrainingDay> trainingDays({
  required Iterable<ProgressWorkout> workouts,
  required TrainingDayDate from,
  required TrainingDayDate to,
}) {
  final dateCount = to.daysBetween(from) + 1;
  if (dateCount < 1 || dateCount > maxTrainingDaysRange) {
    throw ArgumentError(
      'trainingDays needs from <= to and at most $maxTrainingDaysRange '
      'dates; got ${from.storageValue} to ${to.storageValue}.',
    );
  }

  final loggedByDate = _loggedWorkoutsByDate(workouts);
  return List<TrainingDay>.unmodifiable(<TrainingDay>[
    for (var offset = 0; offset < dateCount; offset += 1)
      _trainingDay(from.addDays(offset), loggedByDate),
  ]);
}

TrainingDay _trainingDay(
  TrainingDayDate date,
  Map<TrainingDayDate, List<ProgressWorkout>> loggedByDate,
) {
  final logged = loggedByDate[date] ?? const <ProgressWorkout>[];
  final secondsByFocus = <String, int>{};
  for (final workout in logged) {
    final endedAt = workout.endedAt;
    if (endedAt == null) {
      continue;
    }
    final seconds = endedAt.difference(workout.startedAt).inSeconds;
    final key = workout.focusId ?? noFocusKey;
    secondsByFocus[key] =
        (secondsByFocus[key] ?? 0) + (seconds < 0 ? 0 : seconds);
  }
  return TrainingDay(
    localDate: date,
    workoutCount: logged.length,
    secondsByFocus: secondsByFocus,
  );
}

/// Sums each date's [TrainingDay.secondsByFocus] into consecutive seven-day
/// buckets, the first starting at [firstWeekStart] (the period's first date,
/// whatever its weekday) and the last holding the latest of [days]. Days
/// before [firstWeekStart] are ignored; a week with no time has an empty
/// map. Amounts stay in seconds: the display rounds each (week, Focus)
/// amount to minutes once, so an Agent summing the per-date seconds gets the
/// same numbers (D3).
List<WeeklyFocusSeconds> weeklyFocusSeconds(
  Iterable<TrainingDay> days,
  TrainingDayDate firstWeekStart,
) {
  final buckets = <Map<String, int>>[];
  for (final day in days) {
    final offset = day.localDate.daysBetween(firstWeekStart);
    if (offset < 0) {
      continue;
    }
    final week = offset ~/ 7;
    while (buckets.length <= week) {
      buckets.add(<String, int>{});
    }
    final bucket = buckets[week];
    day.secondsByFocus.forEach((focus, seconds) {
      bucket[focus] = (bucket[focus] ?? 0) + seconds;
    });
  }
  return List<WeeklyFocusSeconds>.unmodifiable(<WeeklyFocusSeconds>[
    for (var week = 0; week < buckets.length; week += 1)
      WeeklyFocusSeconds(
        weekStart: firstWeekStart.addDays(week * 7),
        secondsByFocus: buckets[week],
      ),
  ]);
}

/// The Logged Workouts of each date, ordered by start then id: the order
/// [trainingWeek] matches them in and [trainingDays] sums them in.
Map<TrainingDayDate, List<ProgressWorkout>> _loggedWorkoutsByDate(
  Iterable<ProgressWorkout> workouts,
) {
  final byDate = <TrainingDayDate, List<ProgressWorkout>>{};
  for (final workout in workouts) {
    if (workout.isLogged) {
      byDate.putIfAbsent(workout.localDate, () => <ProgressWorkout>[]).add(
            workout,
          );
    }
  }
  for (final logged in byDate.values) {
    logged.sort((a, b) {
      final byStart = a.startedAt.compareTo(b.startedAt);
      return byStart != 0 ? byStart : a.workoutId.compareTo(b.workoutId);
    });
  }
  return byDate;
}
