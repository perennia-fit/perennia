import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/analytics/repositories/exercise_analytics_repository.dart';

void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  group('exercise analytics repository', () {
    late AppDatabase database;
    late TrainingRepositories repositories;
    late ExerciseAnalyticsRepository analytics;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
      analytics = ExerciseAnalyticsRepository(database);
    });

    tearDown(() async {
      await database.close();
    });

    test(
      'streams recompute from raw sets when values mutate or delete',
      () async {
        final exerciseId = await repositories.exercises.create(
          ExerciseDraft(
            name: 'Back Squat',
            type: ExerciseType(<DimensionId>[
              DimensionId.load,
              DimensionId.reps,
            ]),
          ),
        );
        final workoutId = await repositories.workoutSessions.create(
          WorkoutSessionDraft(
            startedAt: DateTime.utc(2026, 6, 16, 8),
            timezone: 'UTC',
          ),
        );

        final emissions = <String?>[];
        final subscription = analytics.watchForExercise(exerciseId).listen((
          result,
        ) {
          final headline = result?.headlineRecord;
          emissions.add(
            headline == null
                ? null
                : '${headline.value}:${headline.reps}:${headline.setId}',
          );
        });
        addTearDown(subscription.cancel);
        await _waitFor(() => emissions.isNotEmpty);

        final setId = await repositories.sets.create(
          LoggedSetDraft(
            workoutId: workoutId,
            exerciseId: exerciseId,
            position: 0,
            values: _loadReps(load: '100', reps: '5'),
          ),
        );

        await _waitFor(() => emissions.contains('100.0:5:$setId'));
        await repositories.sets.updateValues(
          setId,
          values: _loadReps(load: '120', reps: '5'),
        );

        await _waitFor(() => emissions.contains('120.0:5:$setId'));
        await repositories.sets.softDelete(setId);

        await _waitFor(() => emissions.last == null);

        final schema = await database.describeSchema();
        expect(
          schema.keys.where((table) => table.contains('analytics')),
          isEmpty,
        );
        expect(schema.keys.where((table) => table.contains('record')), isEmpty);
      },
    );

    test(
      'one-shot query returns headline PR, e1RM series, and volume',
      () async {
        final exerciseId = await repositories.exercises.create(
          ExerciseDraft(
            name: 'Bench Press',
            type: ExerciseType(<DimensionId>[
              DimensionId.load,
              DimensionId.reps,
            ]),
          ),
        );
        final workoutId = await repositories.workoutSessions.create(
          WorkoutSessionDraft(
            startedAt: DateTime.utc(2026, 6, 16, 9),
            timezone: 'UTC',
          ),
        );
        await repositories.sets.create(
          LoggedSetDraft(
            workoutId: workoutId,
            exerciseId: exerciseId,
            position: 0,
            values: _loadReps(load: '100', reps: '5'),
          ),
        );
        await repositories.sets.create(
          LoggedSetDraft(
            workoutId: workoutId,
            exerciseId: exerciseId,
            position: 1,
            values: _loadReps(load: '110', reps: '3'),
          ),
        );

        final result = await analytics.getForExercise(exerciseId);

        expect(result?.headlineRecords, hasLength(2));
        expect(result?.estimatedOneRepMax.points, hasLength(2));
        expect(result?.volume.total, 830);
      },
    );
  });
}

LoggedSet _loadReps({required String load, required String reps}) {
  return LoggedSet.fromValues(<SetDimensionValue>[
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
  ]);
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for condition.');
}
