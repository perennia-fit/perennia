import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';

import 'performance_budget_thresholds.dart';

class LargeExerciseOverviewHistoryFixture {
  const LargeExerciseOverviewHistoryFixture({
    required this.exercise,
    required this.workouts,
    required this.sets,
  });

  final ExerciseRecord exercise;
  final List<WorkoutSessionRecord> workouts;
  final List<LoggedSetRecord> sets;
}

LargeExerciseOverviewHistoryFixture buildLargeExerciseOverviewHistoryFixture({
  int setCount = exerciseOverviewLargeHistorySetCount,
  int setsPerWorkout = 100,
}) {
  if (setCount <= 0) {
    throw ArgumentError.value(setCount, 'setCount', 'Must be positive.');
  }
  if (setsPerWorkout <= 0) {
    throw ArgumentError.value(
      setsPerWorkout,
      'setsPerWorkout',
      'Must be positive.',
    );
  }

  final updatedAt = DateTime.utc(2026, 6, 21, 8);
  final exercise = ExerciseRecord(
    id: 'perf-exercise-bench-press',
    origin: ExerciseLibraryOrigin.user,
    name: 'Bench Press',
    type: ExerciseType(const <DimensionId>[
      DimensionId.load,
      DimensionId.reps,
    ]),
    defaultLoadUnit: TrainingUnit.kilogram,
    loadMode: ExerciseLoadMode.added,
    recordProfile: RecordProfile.repMax,
    categoryId: null,
    notes: null,
    isFavorite: false,
    updatedAt: updatedAt,
  );
  final workoutCount = (setCount / setsPerWorkout).ceil();
  final workouts = <WorkoutSessionRecord>[];
  final sets = <LoggedSetRecord>[];
  final firstWorkoutAt = DateTime.utc(2016, 6, 21, 6);

  var remainingSets = setCount;
  var globalSetIndex = 0;
  for (var workoutIndex = 0; workoutIndex < workoutCount; workoutIndex += 1) {
    final startedAt = firstWorkoutAt.add(Duration(days: workoutIndex * 7));
    final workoutId = 'perf-workout-${workoutIndex.toString().padLeft(4, '0')}';
    final workout = WorkoutSessionRecord(
      id: workoutId,
      startedAt: startedAt,
      timezone: 'UTC',
      localDate: TrainingDayDate.fromDateTime(startedAt),
      endedAt: startedAt.add(const Duration(hours: 1)),
      comment: null,
      updatedAt: startedAt,
      deletedAt: null,
    );
    workouts.add(workout);

    final workoutSetCount = math.min(setsPerWorkout, remainingSets);
    for (var position = 0; position < workoutSetCount; position += 1) {
      sets.add(
        LoggedSetRecord(
          id: 'perf-set-${globalSetIndex.toString().padLeft(5, '0')}',
          workoutId: workoutId,
          exerciseId: exercise.id,
          position: position,
          values: _loadRepsValues(
            load: (80 + globalSetIndex % 40).toString(),
            reps: (1 + globalSetIndex % 10).toString(),
          ),
          plannedRestAfter: null,
          isCompleted: true,
          updatedAt: startedAt.add(Duration(seconds: position)),
          comment: null,
        ),
      );
      globalSetIndex += 1;
    }
    remainingSets -= workoutSetCount;
  }

  return LargeExerciseOverviewHistoryFixture(
    exercise: exercise,
    workouts: List<WorkoutSessionRecord>.unmodifiable(workouts),
    sets: List<LoggedSetRecord>.unmodifiable(sets),
  );
}

Future<LargeExerciseOverviewHistoryFixture>
    seedLargeExerciseOverviewHistoryFixture(
  AppDatabase database, {
  int setCount = exerciseOverviewLargeHistorySetCount,
  int setsPerWorkout = 100,
}) async {
  final fixture = buildLargeExerciseOverviewHistoryFixture(
    setCount: setCount,
    setsPerWorkout: setsPerWorkout,
  );

  await database.into(database.exercises).insert(
        _exerciseCompanion(fixture.exercise),
      );
  await database.batch((batch) {
    batch.insertAll(
      database.workoutSessions,
      fixture.workouts.map(_workoutCompanion).toList(growable: false),
    );
  });

  const chunkSize = 1000;
  for (var start = 0; start < fixture.sets.length; start += chunkSize) {
    final end = math.min(start + chunkSize, fixture.sets.length);
    final chunk = fixture.sets
        .sublist(start, end)
        .map(_loggedSetCompanion)
        .toList(growable: false);
    await database.batch((batch) {
      batch.insertAll(database.loggedSets, chunk);
    });
  }

  return fixture;
}

/// Five years of training and one body Metric, for the Progress Overview
/// budgets (docs/designs/progress-overview.md, item 36), in an in-memory
/// database the caller closes.
class ProgressHistoryFixture {
  const ProgressHistoryFixture({
    required this.database,
    required this.repositories,
    required this.today,
    required this.exerciseIds,
    required this.metricId,
  });

  final AppDatabase database;
  final TrainingRepositories repositories;

  /// The last date of the history, a Sunday.
  final TrainingDayDate today;

  /// Ten exercises each with the Record Profiles `repMax`, `maxLoad`,
  /// `maxDuration` and `fastestPace`, in that order.
  final List<String> exerciseIds;

  /// The Metric holding [progressHistoryReadingCount] Readings.
  final String metricId;
}

/// The fixture rows, inserted directly rather than through the repositories
/// so 60 000 Sets seed in seconds:
/// *   [progressHistoryWorkoutCount] finished Workouts spread evenly over
///     [progressHistoryYears] years, each under one of
///     [progressHistoryFocusCount] Focuses in turn;
///     each Workout on a weekday a weekly Routine plans is linked to that
///     day's Workout Template, the way Up next links it;
/// *   two weekly Routines, planning Monday, Wednesday and Friday, and
///     Tuesday and Saturday;
/// *   40 Sets per Workout over four of the
///     [progressHistoryExerciseCount] exercises in turn, every twentieth Set
///     left incomplete (95% complete);
/// *   [progressHistoryReadingCount] Readings of one body-weight Metric over
///     the same years.
Future<ProgressHistoryFixture> buildProgressHistoryFixture() async {
  final database = AppDatabase.inMemory();
  final repositories = TrainingRepositories(database);
  const today = TrainingDayDate(year: 2026, month: 11, day: 1);
  const historyDays = progressHistoryYears * 365 + 1;
  final firstDay = today.addDays(-(historyDays - 1));
  final updatedAt = DateTime.utc(2026, 11, 1);

  final focusIds = <String>[
    for (var index = 0; index < progressHistoryFocusCount; index += 1)
      'perf-focus-$index',
  ];
  const profiles = <(RecordProfile, List<DimensionId>)>[
    (RecordProfile.repMax, <DimensionId>[DimensionId.load, DimensionId.reps]),
    (RecordProfile.maxLoad, <DimensionId>[DimensionId.load, DimensionId.reps]),
    (RecordProfile.maxDuration, <DimensionId>[DimensionId.duration]),
    (
      RecordProfile.fastestPace,
      <DimensionId>[DimensionId.distance, DimensionId.duration],
    ),
  ];
  final perProfile = progressHistoryExerciseCount ~/ profiles.length;
  final exercises = <(String, RecordProfile, List<DimensionId>)>[
    for (final (profile, dimensions) in profiles)
      for (var index = 0; index < perProfile; index += 1)
        ('perf-${profile.name}-$index', profile, dimensions),
  ];
  // Two weekly Routines' templates, by the ISO weekday they plan.
  const plannedWeekdays = <List<int>>[
    <int>[DateTime.monday, DateTime.wednesday, DateTime.friday],
    <int>[DateTime.tuesday, DateTime.saturday],
  ];
  final templateIdByWeekday = <int, String>{
    for (final weekdays in plannedWeekdays)
      for (final weekday in weekdays) weekday: 'perf-template-$weekday',
  };

  await database.batch((batch) {
    batch.insertAll(database.focuses, [
      for (var index = 0; index < focusIds.length; index += 1)
        FocusesCompanion.insert(
          id: focusIds[index],
          name: 'Focus $index',
          sortOrder: index,
          updatedAt: updatedAt,
        ),
    ]);
    batch.insertAll(database.exercises, [
      for (final (id, profile, dimensions) in exercises)
        ExercisesCompanion.insert(
          id: id,
          name: id,
          dimensionIds: jsonEncode(
            dimensions.map((dimension) => dimension.name).toList(),
          ),
          recordProfile: Value<String>(profile.name),
          updatedAt: updatedAt,
        ),
    ]);
    batch.insertAll(database.workoutTemplates, [
      for (final MapEntry(key: weekday, value: id)
          in templateIdByWeekday.entries)
        WorkoutTemplatesCompanion.insert(
          id: id,
          name: 'Day $weekday',
          updatedAt: updatedAt,
        ),
    ]);
    for (var routine = 0; routine < plannedWeekdays.length; routine += 1) {
      final routineId = 'perf-routine-$routine';
      batch.insert(
        database.planRoutines,
        PlanRoutinesCompanion.insert(
          id: routineId,
          name: 'Routine $routine',
          cadenceKind: const Value<String?>('weekly'),
          updatedAt: updatedAt,
        ),
      );
      final weekdays = plannedWeekdays[routine];
      for (var position = 0; position < weekdays.length; position += 1) {
        final weekday = weekdays[position];
        batch.insert(
          database.routineEntries,
          RoutineEntriesCompanion.insert(
            id: 'perf-entry-$weekday',
            routineId: routineId,
            workoutTemplateId: templateIdByWeekday[weekday]!,
            position: position,
            slot: Value<int?>(weekday),
            updatedAt: updatedAt,
          ),
        );
      }
    }
  });

  const setsPerWorkout =
      progressHistorySetCount ~/ progressHistoryWorkoutCount;
  const exercisesPerWorkout = 4;
  const setsPerExercise = setsPerWorkout ~/ exercisesPerWorkout;
  var setIndex = 0;
  for (var start = 0;
      start < progressHistoryWorkoutCount;
      start += _progressWorkoutChunk) {
    final end =
        math.min(start + _progressWorkoutChunk, progressHistoryWorkoutCount);
    await database.batch((batch) {
      for (var index = start; index < end; index += 1) {
        final day = firstDay.addDays(
          index * historyDays ~/ progressHistoryWorkoutCount,
        );
        final startedAt = DateTime.utc(day.year, day.month, day.day, 6);
        final workoutId = 'perf-workout-${index.toString().padLeft(4, '0')}';
        batch.insert(
          database.workoutSessions,
          WorkoutSessionsCompanion.insert(
            id: workoutId,
            startedAt: startedAt,
            timezone: 'UTC',
            localDate: Value<String>(day.storageValue),
            endedAt: Value<DateTime?>(
              startedAt.add(const Duration(hours: 1)),
            ),
            focusId: Value<String?>(focusIds[index % focusIds.length]),
            updatedAt: startedAt,
          ),
        );
        final templateId =
            templateIdByWeekday[day.toLocalDateTime().weekday];
        if (templateId != null) {
          batch.insert(
            database.templateLinks,
            TemplateLinksCompanion.insert(
              id: 'perf-link-$index',
              workoutId: workoutId,
              workoutTemplateId: templateId,
              updatedAt: startedAt,
            ),
          );
        }
        for (var slot = 0; slot < exercisesPerWorkout; slot += 1) {
          final (exerciseId, profile, _) = exercises[
              (index * exercisesPerWorkout + slot) % exercises.length];
          for (var position = 0; position < setsPerExercise; position += 1) {
            batch.insert(
              database.loggedSets,
              _progressSetCompanion(
                id: 'perf-set-${setIndex.toString().padLeft(5, '0')}',
                workoutId: workoutId,
                exerciseId: exerciseId,
                profile: profile,
                position: position,
                progress: index / progressHistoryWorkoutCount,
                isCompleted: setIndex % 20 != 19,
                performedAt: startedAt.add(Duration(minutes: setIndex % 60)),
              ),
            );
            setIndex += 1;
          }
        }
      }
    });
  }

  const metricId = 'perf-metric-body-weight';
  await database.into(database.metrics).insert(
        MetricsCompanion.insert(
          id: metricId,
          name: 'Body Weight',
          unit: MeasurementUnit.kilogram.name,
          valueShape: MetricValueShape.scalar.name,
          metricGroup: MetricGroup.bodyComposition.name,
          sortOrder: 0,
          updatedAt: updatedAt,
        ),
      );
  final firstReadingAt =
      DateTime.utc(firstDay.year, firstDay.month, firstDay.day, 7);
  final readingStep = Duration(
    milliseconds: historyDays *
        Duration.millisecondsPerDay ~/
        progressHistoryReadingCount,
  );
  await database.batch((batch) {
    batch.insertAll(database.metricReadings, [
      for (var index = 0; index < progressHistoryReadingCount; index += 1)
        _progressReadingCompanion(
          id: 'perf-reading-${index.toString().padLeft(4, '0')}',
          metricId: metricId,
          at: firstReadingAt.add(readingStep * index),
          // A slow drift down with a daily swing of about a kilogram.
          kilograms: 84 - index * 0.002 + math.sin(index * 1.3) * 0.6,
        ),
    ]);
  });

  return ProgressHistoryFixture(
    database: database,
    repositories: repositories,
    today: today,
    exerciseIds: List<String>.unmodifiable(
      exercises.map((exercise) => exercise.$1),
    ),
    metricId: metricId,
  );
}

/// Workouts per insert batch: 50 Workouts are 2 000 Sets.
const _progressWorkoutChunk = 50;

/// One Set shaped by [profile], getting slowly better as [progress] goes
/// from 0 to 1 over the history, so the series have New Bests to find.
LoggedSetsCompanion _progressSetCompanion({
  required String id,
  required String workoutId,
  required String exerciseId,
  required RecordProfile profile,
  required int position,
  required double progress,
  required bool isCompleted,
  required DateTime performedAt,
}) {
  String entered(num value) => value.toStringAsFixed(1);
  final hasLoad = profile == RecordProfile.repMax ||
      profile == RecordProfile.maxLoad;
  final hasDistance = profile == RecordProfile.fastestPace;
  final hasDuration = !hasLoad;
  final wobble = (position % 3) * 2.5;
  final load = 60 + progress * 40 + wobble;
  final reps = 5.0 + position % 4;
  // A hold that lengthens, or a 5 km run that gets faster.
  final seconds = hasDistance
      ? 1800 - progress * 300 + wobble
      : 60 + progress * 60 + wobble;
  const kilometres = 5.0;
  return LoggedSetsCompanion.insert(
    id: id,
    workoutId: workoutId,
    exerciseId: exerciseId,
    position: position,
    performedAt: Value<DateTime?>(performedAt),
    loadValue: Value<double?>(hasLoad ? load : null),
    loadUnit: Value<String?>(hasLoad ? TrainingUnit.kilogram.name : null),
    loadEntered: Value<String?>(hasLoad ? entered(load) : null),
    repsValue: Value<double?>(hasLoad ? reps : null),
    repsUnit: Value<String?>(hasLoad ? TrainingUnit.repetition.name : null),
    repsEntered: Value<String?>(hasLoad ? entered(reps) : null),
    durationValue: Value<double?>(hasDuration ? seconds : null),
    durationUnit: Value<String?>(
      hasDuration ? TrainingUnit.second.name : null,
    ),
    durationEntered: Value<String?>(hasDuration ? entered(seconds) : null),
    distanceValue: Value<double?>(hasDistance ? kilometres : null),
    distanceUnit: Value<String?>(
      hasDistance ? TrainingUnit.kilometer.name : null,
    ),
    distanceEntered: Value<String?>(hasDistance ? entered(kilometres) : null),
    isCompleted: Value<bool>(isCompleted),
    updatedAt: performedAt,
  );
}

MetricReadingsCompanion _progressReadingCompanion({
  required String id,
  required String metricId,
  required DateTime at,
  required double kilograms,
}) {
  final entered = kilograms.toStringAsFixed(1);
  final value = double.parse(entered);
  return MetricReadingsCompanion.insert(
    id: id,
    metricId: metricId,
    valueJson: jsonEncode(<String, Object?>{
      'shape': MetricValueShape.scalar.name,
      'value': value,
      'entered': entered,
    }),
    scalarValue: Value<double?>(value),
    scalarEntered: Value<String?>(entered),
    atTime: Value<DateTime?>(at),
    provenance: MetricReadingProvenance.manual.name,
    source: MetricReadingProvenance.manual.name,
    updatedAt: at,
  );
}

LoggedSet _loadRepsValues({
  required String load,
  required String reps,
}) {
  return LoggedSet.fromValues(
    <SetDimensionValue>[
      SetDimensionValue(
        dimension: DimensionId.load,
        entered: load,
        unit: TrainingUnit.kilogram,
      ),
      SetDimensionValue(
        dimension: DimensionId.reps,
        entered: reps,
        unit: TrainingUnit.repetition,
      ),
    ],
  );
}

ExercisesCompanion _exerciseCompanion(ExerciseRecord exercise) {
  return ExercisesCompanion.insert(
    id: exercise.id,
    libraryOrigin: Value<String>(exercise.origin.name),
    name: exercise.name,
    dimensionIds: jsonEncode(
      exercise.type.dimensions.map((dimension) => dimension.name).toList(),
    ),
    defaultLoadUnit: Value<String>(exercise.defaultLoadUnit.name),
    loadMode: Value<String>(exercise.loadMode.name),
    recordProfile: Value<String>(exercise.recordProfile.name),
    isFavorite: Value<bool>(exercise.isFavorite),
    isUnilateral: Value<bool>(exercise.isUnilateral),
    usesRpe: Value<bool>(exercise.usesRpe),
    categoryId: Value<String?>(exercise.categoryId),
    notes: Value<String?>(exercise.notes),
    updatedAt: exercise.updatedAt,
    deletedAt: Value<DateTime?>(exercise.deletedAt),
  );
}

WorkoutSessionsCompanion _workoutCompanion(WorkoutSessionRecord workout) {
  return WorkoutSessionsCompanion.insert(
    id: workout.id,
    startedAt: workout.startedAt,
    timezone: workout.timezone,
    localDate: Value<String>(workout.localDate.storageValue),
    endedAt: Value<DateTime?>(workout.endedAt),
    comment: Value<String?>(workout.comment),
    updatedAt: workout.updatedAt,
    deletedAt: Value<DateTime?>(workout.deletedAt),
  );
}

LoggedSetsCompanion _loggedSetCompanion(LoggedSetRecord set) {
  final load = set.values.load;
  final reps = set.values.reps;
  return LoggedSetsCompanion.insert(
    id: set.id,
    workoutId: set.workoutId,
    exerciseId: set.exerciseId,
    position: set.position,
    plannedRestAfter: Value<int?>(set.plannedRestAfter?.inSeconds),
    loadValue: Value<double?>(load?.numericValue),
    loadUnit: Value<String?>(load?.unit.name),
    loadEntered: Value<String?>(load?.entered),
    repsValue: Value<double?>(reps?.numericValue),
    repsUnit: Value<String?>(reps?.unit.name),
    repsEntered: Value<String?>(reps?.entered),
    comment: Value<String?>(set.comment),
    isCompleted: Value<bool>(set.isCompleted),
    updatedAt: set.updatedAt,
  );
}
