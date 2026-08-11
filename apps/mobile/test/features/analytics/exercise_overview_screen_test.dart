import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/analytics/widgets/exercise_overview_screen.dart';
import 'package:perennia/theme/theme.dart';

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

  group('exercise overview screen', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    testWidgets('renders history with workout totals comments and PR highlight',
        (tester) async {
      final categoryId = await repositories.catalog.createCategory(
        const ExerciseCategoryDraft(name: 'Strength'),
      );
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Bench Press',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
          categoryId: categoryId,
        ),
      );
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 16, 8),
          timezone: 'UTC',
        ),
      );
      await _createSet(
        repositories,
        workoutId: workoutId,
        exerciseId: exerciseId,
        position: 0,
        load: '100',
        reps: '5',
        comment: 'Felt smooth',
      );
      final recordSetId = await _createSet(
        repositories,
        workoutId: workoutId,
        exerciseId: exerciseId,
        position: 1,
        load: '110',
        reps: '3',
      );

      await _pumpOverview(tester, repositories, exerciseId);

      expect(find.text('Bench Press'), findsOneWidget);
      expect(find.text('Strength'), findsOneWidget);
      expect(find.text('History'), findsWidgets);
      expect(find.text('Volume 830 kg'), findsOneWidget);
      expect(find.text('Reps 8'), findsOneWidget);
      expect(find.text('Felt smooth'), findsOneWidget);
      await _waitForFinder(
        tester,
        find.byKey(ExerciseOverviewScreen.prBadgeKey(recordSetId)),
      );
      await _disposeWidgetTree(tester);
    });

    testWidgets('renders actual and estimated record values from analytics',
        (tester) async {
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
          startedAt: DateTime.utc(2026, 1, 1, 8),
          timezone: 'UTC',
        ),
      );
      await _createSet(
        repositories,
        workoutId: workoutId,
        exerciseId: exerciseId,
        position: 0,
        load: '100',
        reps: '5',
      );
      await _createSet(
        repositories,
        workoutId: workoutId,
        exerciseId: exerciseId,
        position: 1,
        load: '100',
        reps: '6',
      );
      await _createSet(
        repositories,
        workoutId: workoutId,
        exerciseId: exerciseId,
        position: 2,
        load: '102.5',
        reps: '5',
      );
      await _createSet(
        repositories,
        workoutId: workoutId,
        exerciseId: exerciseId,
        position: 3,
        load: '225',
        reps: '5',
        loadUnit: TrainingUnit.pound,
      );

      await _pumpOverview(tester, repositories, exerciseId);
      await tester.tap(find.byKey(ExerciseOverviewScreen.recordsTabKey));
      await tester.pumpAndSettle();
      await _scrollRecordsUntilVisible(tester, find.text('Actual rep maxes'));

      expect(find.text('Actual rep maxes'), findsOneWidget);
      await _scrollRecordsUntilVisible(tester, find.text('102.5 kg'));
      expect(find.text('5 reps'), findsWidgets);
      expect(find.text('102.5 kg'), findsOneWidget);
      expect(find.text('6 reps'), findsWidgets);
      expect(find.text('100 kg'), findsWidgets);
      await _scrollRecordsUntilVisible(
          tester, find.text('Estimated rep maxes'));
      expect(find.text('Estimated rep maxes'), findsOneWidget);
      expect(find.text('116.1 kg'), findsOneWidget);
      await _disposeWidgetTree(tester);
    });

    testWidgets('renders exactly the alpha graphs and raw tap inspection', (
      tester,
    ) async {
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
          startedAt: DateTime.utc(2026, 6, 16, 8),
          timezone: 'UTC',
        ),
      );
      await _createSet(
        repositories,
        workoutId: workoutId,
        exerciseId: exerciseId,
        position: 0,
        load: '100',
        reps: '5',
      );

      await _pumpOverview(tester, repositories, exerciseId);
      await tester.tap(find.byKey(ExerciseOverviewScreen.recordsTabKey));
      await tester.pumpAndSettle();

      expect(
        find.byKey(ExerciseOverviewScreen.graphKey('headlineRecordTrend')),
        findsOneWidget,
      );
      expect(
        find.byKey(ExerciseOverviewScreen.graphKey('volume')),
        findsOneWidget,
      );
      expect(
        find.byKey(ExerciseOverviewScreen.graphKey('estimatedOneRepMax')),
        findsOneWidget,
      );
      expect(find.text('Headline record trend'), findsOneWidget);
      expect(find.text('Volume'), findsOneWidget);
      expect(find.text('e1RM'), findsOneWidget);
      expect(find.textContaining('Goals'), findsNothing);

      await tester.tap(find.byKey(ExerciseOverviewScreen.graphKey('volume')));
      await tester.pumpAndSettle();

      expect(
          find.text('Selected Volume: 500 kg on 2026-06-16'), findsOneWidget);
      await _disposeWidgetTree(tester);
    });

    testWidgets('omits assisted e1RM and volume figures', (tester) async {
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Assisted Pull-up',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
          loadMode: ExerciseLoadMode.assisted,
        ),
      );
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 16, 8),
          timezone: 'UTC',
        ),
      );
      await _createSet(
        repositories,
        workoutId: workoutId,
        exerciseId: exerciseId,
        position: 0,
        load: '20',
        reps: '5',
      );

      await _pumpOverview(
        tester,
        repositories,
        exerciseId,
        expectedName: 'Assisted Pull-up',
      );

      expect(find.textContaining('Volume 0'), findsNothing);
      await tester.tap(find.byKey(ExerciseOverviewScreen.recordsTabKey));
      await tester.pumpAndSettle();
      expect(find.text('Estimated rep maxes undefined'), findsOneWidget);
      expect(find.textContaining('0 kg'), findsNothing);
      await _disposeWidgetTree(tester);
    });

    testWidgets('hides assisted volume and e1RM graphs', (tester) async {
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Assisted Pull-up',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
          loadMode: ExerciseLoadMode.assisted,
        ),
      );
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 16, 8),
          timezone: 'UTC',
        ),
      );
      await _createSet(
        repositories,
        workoutId: workoutId,
        exerciseId: exerciseId,
        position: 0,
        load: '20',
        reps: '5',
      );

      await _pumpOverview(
        tester,
        repositories,
        exerciseId,
        expectedName: 'Assisted Pull-up',
      );
      await tester.tap(find.byKey(ExerciseOverviewScreen.recordsTabKey));
      await tester.pumpAndSettle();

      expect(
        find.byKey(ExerciseOverviewScreen.graphKey('headlineRecordTrend')),
        findsOneWidget,
      );
      expect(
        find.byKey(ExerciseOverviewScreen.graphKey('volume')),
        findsNothing,
      );
      expect(
        find.byKey(ExerciseOverviewScreen.graphKey('estimatedOneRepMax')),
        findsNothing,
      );
      await _disposeWidgetTree(tester);
    });

    testWidgets('meets overview accessibility guidelines in both themes', (
      tester,
    ) async {
      final categoryId = await repositories.catalog.createCategory(
        const ExerciseCategoryDraft(name: 'Strength'),
      );
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Bench Press',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
          categoryId: categoryId,
        ),
      );
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 16, 8),
          timezone: 'UTC',
        ),
      );
      await _createSet(
        repositories,
        workoutId: workoutId,
        exerciseId: exerciseId,
        position: 0,
        load: '100',
        reps: '5',
        comment: 'Felt smooth',
      );

      for (final theme in <ThemeData>[
        AppTheme.light(),
        AppTheme.dark(),
      ]) {
        final semantics = tester.ensureSemantics();
        await _pumpOverview(
          tester,
          repositories,
          exerciseId,
          theme: theme,
        );

        expect(
          find.semantics.byLabel('Exercise overview metadata, Strength'),
          findsOne,
        );
        expect(find.semantics.byLabel(RegExp(r'^History')), findsOne);
        expect(find.semantics.byLabel(RegExp(r'^Records')), findsOne);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        await tester.tap(find.byKey(ExerciseOverviewScreen.recordsTabKey));
        await tester.pumpAndSettle();
        expect(
          find.semantics.byLabel(
            RegExp(r'^Progress graph, Headline record trend, 1 raw points'),
          ),
          findsOne,
        );
        expect(
          find.semantics
              .byLabel(RegExp(r'^Progress graph, Volume, 1 raw points')),
          findsOne,
        );
        expect(
          find.semantics
              .byLabel(RegExp(r'^Progress graph, e1RM, 1 raw points')),
          findsOne,
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        semantics.dispose();
        await _disposeWidgetTree(tester);
      }
    });
  });
}

Future<String> _createSet(
  TrainingRepositories repositories, {
  required String workoutId,
  required String exerciseId,
  required int position,
  required String load,
  required String reps,
  String? comment,
  TrainingUnit loadUnit = TrainingUnit.kilogram,
}) {
  return repositories.sets.create(
    LoggedSetDraft(
      workoutId: workoutId,
      exerciseId: exerciseId,
      position: position,
      values: LoggedSet.fromValues(<SetDimensionValue>[
        SetDimensionValue(
          dimension: DimensionId.load,
          entered: load,
          unit: loadUnit,
        ),
        SetDimensionValue(
          dimension: DimensionId.reps,
          entered: reps,
          unit: TrainingUnit.repetition,
        ),
      ]),
      comment: comment,
    ),
  );
}

Future<void> _pumpOverview(
  WidgetTester tester,
  TrainingRepositories repositories,
  String exerciseId, {
  String expectedName = 'Bench Press',
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => repositories.database),
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: ExerciseOverviewScreen(exerciseId: exerciseId),
      ),
    ),
  );
  await _waitForFinder(tester, find.text(expectedName));
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

Future<void> _scrollRecordsUntilVisible(
  WidgetTester tester,
  Finder finder,
) async {
  for (var attempt = 0; attempt < 8; attempt += 1) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.drag(
      find.byKey(ExerciseOverviewScreen.recordsTableKey),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
  }

  fail('Timed out scrolling records tab to $finder.');
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _disposeWidgetTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _pumpFrames(tester);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
  await _pumpFrames(tester);
}
