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
