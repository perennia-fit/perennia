import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/analytics/progress_measure.dart';
import 'package:perennia/domain/training/training_day.dart';
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

    test(
      'Progress Measures read only Performed Sets of live Workouts',
      () async {
        final exerciseId = await repositories.exercises.create(
          ExerciseDraft(
            name: 'Deadlift',
            type: ExerciseType(<DimensionId>[
              DimensionId.load,
              DimensionId.reps,
            ]),
            recordProfile: RecordProfile.maxLoad,
          ),
        );
        final first = await _workoutOn(repositories, DateTime.utc(2026, 6, 1));
        final second = await _workoutOn(repositories, DateTime.utc(2026, 6, 8));
        final deleted =
            await _workoutOn(repositories, DateTime.utc(2026, 6, 15));
        final performedId = await _performedSet(
          repositories,
          workoutId: first,
          exerciseId: exerciseId,
          load: '100',
        );
        // Heavier, but not Performed.
        await repositories.sets.create(
          LoggedSetDraft(
            workoutId: first,
            exerciseId: exerciseId,
            position: 1,
            values: _loadReps(load: '140', reps: '5'),
          ),
        );
        final bestId = await _performedSet(
          repositories,
          workoutId: second,
          exerciseId: exerciseId,
          load: '110',
        );
        await _performedSet(
          repositories,
          workoutId: deleted,
          exerciseId: exerciseId,
          load: '150',
        );

        final emissions = <List<String>>[];
        final subscription = analytics
            .watchProgressSeries(<String>[exerciseId]).listen((series) {
          emissions.add(<String>[
            for (final point in series.single.points)
              '${point.setId}:${point.value}:${point.isNewBest}',
          ]);
        });
        addTearDown(subscription.cancel);
        await _waitFor(() => emissions.isNotEmpty);
        expect(emissions.last, hasLength(3));

        // A synced Workout delete leaves its Sets undeleted; the join to the
        // Workout drops them and re-emits.
        await (database.update(database.workoutSessions)
              ..where((row) => row.id.equals(deleted)))
            .write(
          WorkoutSessionsCompanion(
            deletedAt: Value<DateTime?>(DateTime.utc(2026, 6, 16)),
          ),
        );
        await _waitFor(() => emissions.last.length == 2);
        expect(emissions.last, <String>[
          '$performedId:100.0:false',
          '$bestId:110.0:true',
        ]);

        final bests = await analytics.watchNewBests(_june(1), _june(30)).first;
        expect(
          bests.map((best) => '${best.exerciseId}:${best.setId}:${best.value}'),
          <String>['$exerciseId:$bestId:110.0'],
        );
        expect(bests.single.measure, ProgressMeasureKind.maxLoad);
        expect(bests.single.localDate, _june(8));
      },
    );

    test('an archived exercise has no series and no New Bests', () async {
      final ids = <String>[
        for (final name in <String>['Front Squat', 'Overhead Press'])
          await repositories.exercises.create(
            ExerciseDraft(
              name: name,
              type: ExerciseType(<DimensionId>[
                DimensionId.load,
                DimensionId.reps,
              ]),
              recordProfile: RecordProfile.maxLoad,
            ),
          ),
      ];
      final first = await _workoutOn(repositories, DateTime.utc(2026, 6, 1));
      final second = await _workoutOn(repositories, DateTime.utc(2026, 6, 8));
      for (final exerciseId in ids) {
        await _performedSet(
          repositories,
          workoutId: first,
          exerciseId: exerciseId,
          load: '60',
        );
        await _performedSet(
          repositories,
          workoutId: second,
          exerciseId: exerciseId,
          load: '70',
        );
      }
      final [archived, active] = ids;

      expect(
        await analytics.watchNewBests(_june(1), _june(30)).first,
        hasLength(2),
      );

      await repositories.exercises.softDelete(archived);

      final series =
          await analytics.watchProgressSeries(<String>[archived, active]).first;
      expect(series.map((one) => one.exerciseId), <String>[active]);
      final bests = await analytics.watchNewBests(_june(1), _june(30)).first;
      expect(bests.map((best) => best.exerciseId), <String>[active]);
    });
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

TrainingDayDate _june(int day) =>
    TrainingDayDate(year: 2026, month: 6, day: day);

Future<String> _workoutOn(
  TrainingRepositories repositories,
  DateTime startedAt,
) {
  return repositories.workoutSessions.create(
    WorkoutSessionDraft(startedAt: startedAt, timezone: 'UTC'),
  );
}

Future<String> _performedSet(
  TrainingRepositories repositories, {
  required String workoutId,
  required String exerciseId,
  required String load,
}) {
  return repositories.sets.create(
    LoggedSetDraft(
      workoutId: workoutId,
      exerciseId: exerciseId,
      position: 0,
      values: _loadReps(load: load, reps: '5'),
      isCompleted: true,
    ),
  );
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
