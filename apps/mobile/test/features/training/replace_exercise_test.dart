import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/catalog/repositories/exercise_catalog_repository.dart';
import 'package:perennia/features/catalog/widgets/exercise_catalog_picker.dart';
import 'package:perennia/features/training/widgets/replace_exercise.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

const _replaceButtonKey = Key('test.replace');

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

  late AppDatabase database;
  late TrainingRepositories repositories;

  setUp(() {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(database);
  });

  tearDown(() async {
    await database.close();
  });

  _testReplace(
      'opens the picker on the Workout Focus; a cancel returns null and '
      'writes nothing', (tester) async {
    final fixture = (await tester.runAsync(
      () => _createFixture(repositories, focusId: 'focus-weights'),
    ))!;
    final results = <String?>[];
    await _pumpHarness(tester, repositories, fixture, results);
    final before = (await tester.runAsync(
      () => _workoutRows(repositories, fixture.workoutId),
    ))!;

    await tester.tap(find.byKey(_replaceButtonKey));
    await _settle(tester);
    expect(find.byType(ExerciseCatalogPicker), findsOneWidget);
    expect(
      tester
          .widget<ExerciseCatalogPicker>(find.byType(ExerciseCatalogPicker))
          .initialFocusId,
      'focus-weights',
    );

    // Dismiss the sheet without picking.
    await tester.tapAt(const Offset(10, 10));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ExerciseCatalogPicker), findsNothing);
    expect(results, <String?>[null]);
    expect(find.byType(SnackBar), findsNothing);
    final after = (await tester.runAsync(
      () => _workoutRows(repositories, fixture.workoutId),
    ))!;
    expect(after, before);
  });

  _testReplace('returns the new Workout Exercise id, and null when refused', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(
      () => _createFixture(repositories),
    ))!;
    final results = <String?>[];
    await _pumpHarness(tester, repositories, fixture, results);

    await _replaceWith(tester, fixture.squat.id);
    final rows = (await tester.runAsync(
      () => repositories.workoutExercises.listActiveForWorkout(
        fixture.workoutId,
      ),
    ))!;
    expect(rows.map((row) => row.exerciseId), <String>[fixture.squat.id]);
    expect(results, <String?>[rows.single.id]);
    expect(find.widgetWithText(SnackBar, 'Replaced'), findsOneWidget);

    // Replacing the new one with its own Exercise is refused.
    fixture.workoutExerciseId = rows.single.id;
    await _replaceWith(tester, fixture.squat.id);
    expect(results, <String?>[rows.single.id, null]);
    expect(
      find.widgetWithText(SnackBar, 'Already in this workout'),
      findsOneWidget,
    );
  });
}

/// A widget test that tears the tree down before the database closes: the
/// picker's catalogue and the Drift streams stay live until then.
void _testReplace(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    try {
      await callback(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}

Future<_Fixture> _createFixture(
  TrainingRepositories repositories, {
  String? focusId,
}) async {
  final workoutId = await repositories.workoutSessions.create(
    WorkoutSessionDraft(
      startedAt: DateTime.utc(2026, 11, 2, 6),
      timezone: 'UTC',
      focusId: focusId,
    ),
  );
  final loadReps = ExerciseType(
    const <DimensionId>[DimensionId.load, DimensionId.reps],
  );
  final benchId = await repositories.exercises.create(
    ExerciseDraft(name: 'Bench Press', type: loadReps),
  );
  final squatId = await repositories.exercises.create(
    ExerciseDraft(name: 'Back Squat', type: loadReps),
  );
  final workoutExerciseId = await repositories.workoutExercises.create(
    WorkoutExerciseDraft(workoutId: workoutId, exerciseId: benchId),
  );
  final squat = (await repositories.exercises.getById(squatId))!;
  return _Fixture(
    workoutId: workoutId,
    workoutExerciseId: workoutExerciseId,
    squat: squat,
    catalog: StubExerciseCatalogRepository(
      sections: <ExerciseCatalogSectionRecord>[
        ExerciseCatalogSectionRecord(
          category: ExerciseCategoryRecord(
            id: 'category-strength',
            name: 'Strength',
            sortOrder: 0,
            colorHex: '#2F6FED',
            updatedAt: DateTime.utc(2026),
          ),
          exercises: <ExerciseRecord>[squat],
        ),
      ],
    ),
  );
}

class _Fixture {
  _Fixture({
    required this.workoutId,
    required this.workoutExerciseId,
    required this.squat,
    required this.catalog,
  });

  final String workoutId;
  String workoutExerciseId;
  final ExerciseRecord squat;
  final ExerciseCatalogRepository catalog;
}

/// The Workout's Workout Exercises and Sets with the times they were last
/// written. (The Activity Log is no measure: opening the catalogue seeds
/// the platform library.)
Future<List<String>> _workoutRows(
  TrainingRepositories repositories,
  String workoutId,
) async {
  final workoutExercises =
      await repositories.workoutExercises.listActiveForWorkout(workoutId);
  final sets = await repositories.sets.listActiveForWorkout(workoutId);
  return <String>[
    for (final row in workoutExercises)
      'exercise ${row.id} ${row.exerciseId} ${row.updatedAt}',
    for (final set in sets) 'set ${set.id} ${set.updatedAt}',
  ];
}

/// A screen with one button that runs [replaceExercise] on the fixture's
/// Workout Exercise and records what it returns.
Future<void> _pumpHarness(
  WidgetTester tester,
  TrainingRepositories repositories,
  _Fixture fixture,
  List<String?> results,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => repositories.database),
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
        exerciseCatalogRepositoryProvider.overrideWith(
          (ref) => fixture.catalog,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: TextButton(
                key: _replaceButtonKey,
                onPressed: () async {
                  results.add(
                    await replaceExercise(
                      context,
                      ref,
                      fixture.workoutExerciseId,
                    ),
                  );
                },
                child: const Text('Replace'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _replaceWith(WidgetTester tester, String exerciseId) async {
  await tester.tap(find.byKey(_replaceButtonKey));
  await _settle(tester);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(
    find.byKey(ExerciseCatalogPicker.selectButtonKey(exerciseId)),
  );
  await _settle(tester);
  await tester.pump(const Duration(milliseconds: 400));
}

/// Lets repository writes, and the Drift streams they wake, finish.
Future<void> _settle(WidgetTester tester) async {
  for (var round = 0; round < 6; round += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}
