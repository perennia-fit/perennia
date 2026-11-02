import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import '../../../data/repositories/training_repositories.dart';
import '../../../domain/analytics/exercise_analytics.dart';
import '../../../domain/analytics/progress_measure.dart';
import '../../../domain/training/training_day.dart';
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
      profile: _profileFromRow(exercise),
      sets: analyticsSets,
    );
  }

  /// Each of [exerciseIds]' Progress Measure over its whole history
  /// (docs/designs/progress-overview.md, D0 and D4), in the order given. An
  /// archived or missing exercise, or one whose Record Profile has no series,
  /// is left out. Computed on this isolate, because Key exercises asks for at
  /// most six (D8).
  Stream<List<ProgressSeries>> watchProgressSeries(
    Iterable<String> exerciseIds,
  ) {
    final ids = exerciseIds.toSet();
    if (ids.isEmpty) {
      return Stream<List<ProgressSeries>>.value(const <ProgressSeries>[]);
    }

    return watchProgressHistory(exerciseIds: ids).map(
      (history) => List<ProgressSeries>.unmodifiable(<ProgressSeries>[
        for (final id in ids)
          if (history.profiles[id] case final profile?)
            if (progressSeries(
              exerciseId: id,
              profile: profile,
              workouts: history.workoutsByExercise[id] ??
                  const <ProgressWorkoutSets>[],
            )
                case final series?)
              series,
      ]),
    );
  }

  /// Every active exercise's New Bests dated in [from]..[to] (D4), each
  /// judged against the exercise's whole history, newest first.
  ///
  /// Every exercise's whole history runs through the engine, tens of
  /// thousands of Sets after a few years, so the series are built in a
  /// background isolate (`compute`, D8), which receives only the plain
  /// [ProgressHistory]. A history that changes while one is still
  /// computing supersedes it: only the latest history's result is emitted.
  Stream<List<NewBest>> watchNewBests(
    TrainingDayDate from,
    TrainingDayDate to,
  ) {
    late final StreamSubscription<ProgressHistory> subscription;
    final controller = StreamController<List<NewBest>>();
    var generation = 0;

    Future<void> emit(ProgressHistory history) async {
      final current = generation += 1;
      try {
        final bests = await compute(
          newBestsInHistory,
          (history: history, from: from, to: to),
          debugLabel: 'progress.newBests',
        );
        if (current == generation && !controller.isClosed) {
          controller.add(bests);
        }
      } on Object catch (error, stackTrace) {
        if (current == generation && !controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      }
    }

    controller.onListen = () {
      subscription = watchProgressHistory().listen(
        (history) => unawaited(emit(history)),
        onError: controller.addError,
      );
    };
    controller.onCancel = () => subscription.cancel();

    return controller.stream;
  }

  /// The Progress Measure inputs (D0): active exercises' profiles, limited to
  /// [exerciseIds] when given, and their Performed Sets grouped by Workout.
  ///
  /// Sets are joined to their Workout for `localDate` and `startedAt`, and
  /// the join drops Sets of deleted Workouts. It is a watched join rather
  /// than a lookup after the Set query, so deleting a Workout whose Sets stay
  /// undeleted (a synced delete does not cascade) re-emits too. A Workout
  /// whose stored date cannot be read is left out, as the Workout loader
  /// does.
  @visibleForTesting
  Stream<ProgressHistory> watchProgressHistory({Set<String>? exerciseIds}) {
    final exercises = _database.select(_database.exercises)
      ..where((row) {
        final active = row.deletedAt.isNull();
        return exerciseIds == null ? active : active & row.id.isIn(exerciseIds);
      });
    final sets = _database.loggedSets;
    final workouts = _database.workoutSessions;
    final performed = sets.deletedAt.isNull() & sets.isCompleted.isValue(true);
    final setQuery = _database.select(sets).join([
      innerJoin(
        workouts,
        workouts.id.equalsExp(sets.workoutId) & workouts.deletedAt.isNull(),
        useColumns: false,
      ),
    ])
      ..addColumns([workouts.localDate, workouts.startedAt])
      ..where(
        exerciseIds == null
            ? performed
            : performed & sets.exerciseId.isIn(exerciseIds),
      );

    late final StreamSubscription<List<ExerciseRow>> exerciseSubscription;
    late final StreamSubscription<List<TypedResult>> setSubscription;
    final controller = StreamController<ProgressHistory>();
    List<ExerciseRow>? latestExercises;
    List<TypedResult>? latestSets;

    void emitIfReady() {
      final exerciseRows = latestExercises;
      final setRows = latestSets;
      if (exerciseRows == null || setRows == null || controller.isClosed) {
        return;
      }
      controller.add(
        _progressHistoryFromRows(exerciseRows, setRows, workouts),
      );
    }

    controller.onListen = () {
      exerciseSubscription = exercises.watch().listen((rows) {
        latestExercises = rows;
        emitIfReady();
      }, onError: controller.addError);
      setSubscription = setQuery.watch().listen((rows) {
        latestSets = rows;
        emitIfReady();
      }, onError: controller.addError);
    };
    controller.onCancel = () async {
      await exerciseSubscription.cancel();
      await setSubscription.cancel();
    };

    return controller.stream;
  }

  ProgressHistory _progressHistoryFromRows(
    List<ExerciseRow> exerciseRows,
    List<TypedResult> setRows,
    $WorkoutSessionsTable workouts,
  ) {
    final profiles = <String, ExerciseAnalyticsProfile>{
      for (final row in exerciseRows) row.id: _profileFromRow(row),
    };
    final workoutFacts = <String, (TrainingDayDate, DateTime)>{};
    final setsByWorkoutByExercise = <String, Map<String, List<ProgressSet>>>{};
    for (final result in setRows) {
      final set = result.readTable(_database.loggedSets);
      if (!profiles.containsKey(set.exerciseId)) {
        continue;
      }
      final localDate = _parseTrainingDayDate(result.read(workouts.localDate));
      final startedAt = result.read(workouts.startedAt);
      if (localDate == null || startedAt == null) {
        continue;
      }
      workoutFacts[set.workoutId] = (localDate, startedAt.toUtc());
      setsByWorkoutByExercise
          .putIfAbsent(set.exerciseId, () => <String, List<ProgressSet>>{})
          .putIfAbsent(set.workoutId, () => <ProgressSet>[])
          .add(
            ProgressSet(
              id: set.id,
              position: set.position,
              isCompleted: set.isCompleted,
              values: _loggedSetValuesFromRow(set),
            ),
          );
    }

    return ProgressHistory(
      profiles: profiles,
      workoutsByExercise: <String, List<ProgressWorkoutSets>>{
        for (final MapEntry(key: exerciseId, value: byWorkout)
            in setsByWorkoutByExercise.entries)
          exerciseId: <ProgressWorkoutSets>[
            for (final MapEntry(key: workoutId, value: sets)
                in byWorkout.entries)
              ProgressWorkoutSets(
                workoutId: workoutId,
                localDate: workoutFacts[workoutId]!.$1,
                startedAt: workoutFacts[workoutId]!.$2,
                sets: sets,
              ),
          ],
      },
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

/// The Progress Measure inputs [ExerciseAnalyticsRepository.watchNewBests]
/// sends to its background isolate: plain data only, keyed by exercise id.
final class ProgressHistory {
  const ProgressHistory({
    required this.profiles,
    required this.workoutsByExercise,
  });

  /// Active exercises only.
  final Map<String, ExerciseAnalyticsProfile> profiles;

  /// Each exercise's Performed Sets by Workout; an exercise with none is
  /// absent.
  final Map<String, List<ProgressWorkoutSets>> workoutsByExercise;
}

/// `progressSeries` for every exercise of [input]'s history plus
/// `newBestsBetween` over its period: the work
/// [ExerciseAnalyticsRepository.watchNewBests] runs in a background isolate.
/// Top level, so `compute` can send it.
List<NewBest> newBestsInHistory(
  ({ProgressHistory history, TrainingDayDate from, TrainingDayDate to}) input,
) {
  final history = input.history;
  return newBestsBetween(
    <ProgressSeries>[
      for (final MapEntry(key: exerciseId, value: profile)
          in history.profiles.entries)
        if (progressSeries(
          exerciseId: exerciseId,
          profile: profile,
          workouts: history.workoutsByExercise[exerciseId] ??
              const <ProgressWorkoutSets>[],
        )
            case final series?)
          series,
    ],
    input.from,
    input.to,
  );
}

ExerciseAnalyticsProfile _profileFromRow(ExerciseRow exercise) {
  return ExerciseAnalyticsProfile(
    type: _decodeDimensions(exercise.dimensionIds),
    loadMode: ExerciseLoadMode.values.byName(exercise.loadMode),
    recordProfile: RecordProfile.values.byName(exercise.recordProfile),
  );
}

TrainingDayDate? _parseTrainingDayDate(String? value) {
  if (value == null) {
    return null;
  }
  try {
    return TrainingDayDate.parse(value);
  } on FormatException {
    return null;
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
