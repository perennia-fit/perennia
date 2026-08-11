import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import '../../../data/repositories/training_repositories.dart';
import '../../../domain/analytics/exercise_analytics.dart';
import '../../../domain/training/training_dimensions.dart';

final exerciseAnalyticsRepositoryProvider =
    Provider<ExerciseAnalyticsRepository>((ref) {
      return ExerciseAnalyticsRepository(ref.watch(appDatabaseProvider));
    });

final exerciseAnalyticsControllerProvider =
    StreamProvider.family<ExerciseAnalyticsResult?, String>((ref, exerciseId) {
      return ref
          .watch(exerciseAnalyticsRepositoryProvider)
          .watchForExercise(exerciseId);
    });

class ExerciseAnalyticsRepository {
  const ExerciseAnalyticsRepository(
    this._database, {
    ExerciseAnalyticsEngine engine = const ExerciseAnalyticsEngine(),
  }) : _engine = engine;

  final AppDatabase _database;
  final ExerciseAnalyticsEngine _engine;

  Future<ExerciseAnalyticsResult?> getForExercise(String exerciseId) async {
    final exercise = await _exerciseQuery(exerciseId).getSingleOrNull();
    if (exercise == null || exercise.deletedAt != null) {
      return null;
    }

    final sets = await _activeSetQuery(exerciseId).get();
    return _buildFromRows(exercise, sets);
  }

  Stream<ExerciseAnalyticsResult?> watchForExercise(String exerciseId) {
    late final StreamSubscription<List<ExerciseRow>> exerciseSubscription;
    late final StreamSubscription<List<LoggedSetRow>> setSubscription;
    final controller = StreamController<ExerciseAnalyticsResult?>();
    ExerciseRow? latestExercise;
    List<LoggedSetRow>? latestSets;

    Future<void> emitIfReady() async {
      final sets = latestSets;
      if (sets == null) {
        return;
      }

      final exercise = latestExercise;
      final next = exercise == null || exercise.deletedAt != null
          ? null
          : await _buildFromRows(exercise, sets);
      if (!controller.isClosed) {
        controller.add(next);
      }
    }

    controller.onListen = () {
      exerciseSubscription = _exerciseQuery(exerciseId).watch().listen((rows) {
        latestExercise = rows.isEmpty ? null : rows.single;
        unawaited(emitIfReady());
      }, onError: controller.addError);
      setSubscription = _activeSetQuery(exerciseId).watch().listen((rows) {
        latestSets = rows;
        unawaited(emitIfReady());
      }, onError: controller.addError);
    };
    controller.onCancel = () async {
      await exerciseSubscription.cancel();
      await setSubscription.cancel();
    };

    return controller.stream;
  }

  Future<ExerciseAnalyticsResult> _buildFromRows(
    ExerciseRow exercise,
    List<LoggedSetRow> setRows,
  ) async {
    final workoutIds = setRows.map((row) => row.workoutId).toSet();
    final workoutsById = await _activeWorkoutsById(workoutIds);
    final analyticsSets = <AnalyticsSet>[];

    for (final row in setRows) {
      final workout = workoutsById[row.workoutId];
      if (workout == null) {
        continue;
      }

      analyticsSets.add(
        AnalyticsSet(
          id: row.id,
          performedAt: workout.startedAt.toUtc(),
          sequence: row.position,
          values: _loggedSetValuesFromRow(row),
        ),
      );
    }

    return _engine.compute(
      profile: ExerciseAnalyticsProfile(
        type: _decodeDimensions(exercise.dimensionIds),
        loadMode: ExerciseLoadMode.values.byName(exercise.loadMode),
        recordProfile: RecordProfile.values.byName(exercise.recordProfile),
      ),
      sets: analyticsSets,
    );
  }

  Future<Map<String, WorkoutSessionRow>> _activeWorkoutsById(
    Set<String> workoutIds,
  ) async {
    if (workoutIds.isEmpty) {
      return const <String, WorkoutSessionRow>{};
    }

    final rows = await (_database.select(
      _database.workoutSessions,
    )..where((row) => row.id.isIn(workoutIds) & row.deletedAt.isNull())).get();
    return <String, WorkoutSessionRow>{for (final row in rows) row.id: row};
  }

  SimpleSelectStatement<$ExercisesTable, ExerciseRow> _exerciseQuery(
    String exerciseId,
  ) {
    return _database.select(_database.exercises)
      ..where((row) => row.id.equals(exerciseId));
  }

  SimpleSelectStatement<$LoggedSetsTable, LoggedSetRow> _activeSetQuery(
    String exerciseId,
  ) {
    return _database.select(_database.loggedSets)
      ..where(
        (row) => row.exerciseId.equals(exerciseId) & row.deletedAt.isNull(),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.workoutId),
        (row) => OrderingTerm.asc(row.position),
        (row) => OrderingTerm.asc(row.updatedAt),
      ]);
  }
}

ExerciseType _decodeDimensions(String encoded) {
  final dimensionNames = jsonDecode(encoded) as List<Object?>;
  return ExerciseType(
    dimensionNames.map((name) => DimensionId.values.byName(name! as String)),
  );
}

LoggedSet _loggedSetValuesFromRow(LoggedSetRow row) {
  final values = <SetDimensionValue>[];
  _addSetValue(
    values,
    dimension: DimensionId.load,
    entered: row.loadEntered,
    unitName: row.loadUnit,
  );
  _addSetValue(
    values,
    dimension: DimensionId.reps,
    entered: row.repsEntered,
    unitName: row.repsUnit,
  );
  _addSetValue(
    values,
    dimension: DimensionId.duration,
    entered: row.durationEntered,
    unitName: row.durationUnit,
  );
  _addSetValue(
    values,
    dimension: DimensionId.distance,
    entered: row.distanceEntered,
    unitName: row.distanceUnit,
  );

  return values.isEmpty ? LoggedSet.completion() : LoggedSet.fromValues(values);
}

void _addSetValue(
  List<SetDimensionValue> values, {
  required DimensionId dimension,
  required String? entered,
  required String? unitName,
}) {
  if (entered == null || unitName == null) {
    return;
  }

  values.add(
    SetDimensionValue(
      dimension: dimension,
      entered: entered,
      unit: TrainingUnit.values.byName(unitName),
    ),
  );
}
