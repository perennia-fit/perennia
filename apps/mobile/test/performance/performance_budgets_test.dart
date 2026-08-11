import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/analytics/repositories/exercise_overview_repository.dart';
import 'package:perennia/features/home/repositories/home_repository.dart';
import 'package:perennia/features/training/widgets/training_screen.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

import 'performance_budget_fixtures.dart';
import 'performance_budget_thresholds.dart';

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

  group('M5 performance budgets', () {
    test('Exercise Overview aggregates 50k-set fixture under 300 ms', () {
      final fixture = buildLargeExerciseOverviewHistoryFixture();
      final stopwatch = Stopwatch()..start();

      final overview = buildExerciseOverviewModel(
        exercise: fixture.exercise,
        workouts: fixture.workouts,
        sets: fixture.sets,
      );
      stopwatch.stop();

      expect(fixture.sets, hasLength(exerciseOverviewLargeHistorySetCount));
      expect(
        overview.setsById,
        hasLength(exerciseOverviewLargeHistorySetCount),
      );
      expect(
        stopwatch.elapsed,
        lessThan(exerciseOverviewAggregateBudget),
        reason:
            'Exercise Overview must stay under the documented M5 large-history '
            'budget.',
      );
    });

    test('50k-set fixture seeds persisted Exercise Overview history', () async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repositories = TrainingRepositories(database);
      final fixture = await seedLargeExerciseOverviewHistoryFixture(database);

      final overview = await ExerciseOverviewRepository(
        repositories,
      ).getForExercise(fixture.exercise.id);

      expect(
        overview?.setsById,
        hasLength(exerciseOverviewLargeHistorySetCount),
      );
      expect(overview?.groups, hasLength(fixture.workouts.length));
    });

    testWidgets('set save confirms optimistically within one frame', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repositories = TrainingRepositories(database);
      final workoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(repositories),
      );

      await _pumpTrainingScreen(tester, repositories, workoutExerciseId!);
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '100',
      );
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '5',
      );

      await tester.tap(find.byKey(TrainingScreen.saveSetButtonKey));
      await tester.pump(setSaveConfirmationFrameBudget);

      expect(
        find.byKey(TrainingScreen.saveSetConfirmationKey),
        findsOneWidget,
      );

      await _settleRepositoryWork(tester);
      final workoutExercise = await tester.runAsync(
        () => repositories.workoutExercises.getById(workoutExerciseId),
      );
      final sets = await tester.runAsync(
        () => repositories.sets.listActiveForWorkout(
          workoutExercise!.workoutId,
        ),
      );
      expect(sets, hasLength(1));
    });

    test('cold start Home data path stays under 2 s', () async {
      final database = AppDatabase.inMemory();
      final repositories = TrainingRepositories(database);
      try {
        const selectedDate = TrainingDayDate(year: 2026, month: 6, day: 21);
        final repository = RepositoryHomeRepository(repositories);
        final stopwatch = Stopwatch()..start();

        final summary = await repository
            .watchTrainingDay(selectedDate)
            .first
            .timeout(coldStartHomeInteractiveBudget);
        stopwatch.stop();

        expect(summary.exercises, isEmpty);
        expect(summary.workoutExercises, isEmpty);
        expect(summary.sets, isEmpty);
        expect(summary.status, 'No workout started');
        expect(
          stopwatch.elapsed,
          lessThan(coldStartHomeInteractiveBudget),
          reason: 'Cold start must load the first Home data needed for an '
              'interactive Home Screen before the M5 target.',
        );
      } finally {
        await database.close();
      }
    });
  });
}

Future<String> _createWorkoutExercise(TrainingRepositories repositories) async {
  final exerciseId = await repositories.exercises.create(
    ExerciseDraft(
      name: 'Bench Press',
      type: ExerciseType(
        const <DimensionId>[DimensionId.load, DimensionId.reps],
      ),
    ),
  );
  final workoutId = await repositories.workoutSessions.create(
    WorkoutSessionDraft(
      startedAt: DateTime.utc(2026, 6, 21, 7),
      timezone: 'Australia/Brisbane',
    ),
  );
  return repositories.workoutExercises.create(
    WorkoutExerciseDraft(
      workoutId: workoutId,
      exerciseId: exerciseId,
    ),
  );
}

Future<void> _pumpTrainingScreen(
  WidgetTester tester,
  TrainingRepositories repositories,
  String workoutExerciseId,
) async {
  final initialWorkoutExercise = await tester.runAsync(
    () => repositories.workoutExercises.getById(workoutExerciseId),
  );
  final initialExercise = await tester.runAsync(
    () => repositories.exercises.getById(initialWorkoutExercise!.exerciseId),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => repositories.database),
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TrainingScreen(
          workoutExerciseId: workoutExerciseId,
          initialWorkoutExercise: initialWorkoutExercise,
          initialExercise: initialExercise,
          setsStream: Stream<List<LoggedSetRecord>>.value(
            const <LoggedSetRecord>[],
          ),
          recordSetIdsStream: Stream<Set<String>>.value(const <String>{}),
          enableRestTimerTicker: false,
        ),
      ),
    ),
  );
  await _waitForFinder(tester, find.byKey(TrainingScreen.saveSetButtonKey));
}

Future<void> _settleRepositoryWork(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
  await tester.pump();
}

Future<void> _waitForFinder(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }

  fail('Timed out waiting for $finder.');
}
