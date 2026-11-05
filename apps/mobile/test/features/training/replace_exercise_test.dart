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
import 'package:perennia/features/training/widgets/training_confirmation.dart';
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
    final shown = <TrainingConfirmation>[];
    await _pumpHarness(tester, repositories, fixture, results, shown);
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
    expect(shown, isEmpty);
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
    final shown = <TrainingConfirmation>[];
    await _pumpHarness(tester, repositories, fixture, results, shown);

    await _replaceWith(tester, fixture.squat.id);
    final rows = (await tester.runAsync(
      () => repositories.workoutExercises.listActiveForWorkout(
        fixture.workoutId,
      ),
    ))!;
    expect(rows.map((row) => row.exerciseId), <String>[fixture.squat.id]);
    expect(results, <String?>[rows.single.id]);
    expect(shown.single.message, 'Replaced');
    expect(shown.single.undoLabel, 'Undo');
    expect(shown.single.onUndo, isNotNull);

    // Replacing the new one with its own Exercise is refused.
    fixture.workoutExerciseId = rows.single.id;
    await _replaceWith(tester, fixture.squat.id);
    expect(results, <String?>[rows.single.id, null]);
    expect(shown, hasLength(2));
    expect(shown.last.message, 'Already in this workout');
    expect(shown.last.undoLabel, isNull);
    expect(shown.last.onUndo, isNull);
  });

  _testReplace('the Undo it hands over reverts the Replace', (tester) async {
    final fixture = (await tester.runAsync(
      () => _createFixture(repositories),
    ))!;
    final shown = <TrainingConfirmation>[];
    await _pumpHarness(tester, repositories, fixture, <String?>[], shown);
    await _replaceWith(tester, fixture.squat.id);

    shown.single.onUndo!();
    await _settle(tester);

    final rows = (await tester.runAsync(
      () => repositories.workoutExercises.listActiveForWorkout(
        fixture.workoutId,
      ),
    ))!;
    expect(rows.map((row) => row.id), <String>[fixture.workoutExerciseId]);
    expect(shown, hasLength(1));
  });

  _testReplace('its Undo says so when the rows changed since', (tester) async {
    final fixture = (await tester.runAsync(
      () => _createFixture(repositories),
    ))!;
    final results = <String?>[];
    final shown = <TrainingConfirmation>[];
    await _pumpHarness(tester, repositories, fixture, results, shown);
    await _replaceWith(tester, fixture.squat.id);
    // Another device removes the new one.
    await tester.runAsync(
      () => repositories.workoutExercises.softDelete(
        results.single!,
        actor: 'sync',
      ),
    );

    shown.first.onUndo!();
    await _settle(tester);

    expect(shown, hasLength(2));
    expect(shown.last.message, "Couldn't undo: changed since");
    expect(shown.last.onUndo, isNull);
    final rows = (await tester.runAsync(
      () => repositories.workoutExercises.listActiveForWorkout(
        fixture.workoutId,
      ),
    ))!;
    expect(rows, isEmpty);
  });

  _testReplace(
      'an exercise removed while the picker is open is not replaced, and '
      'nothing is written', (tester) async {
    final fixture = (await tester.runAsync(
      () => _createFixture(repositories),
    ))!;
    final results = <String?>[];
    final shown = <TrainingConfirmation>[];
    await _pumpHarness(tester, repositories, fixture, results, shown);

    await tester.tap(find.byKey(_replaceButtonKey));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    // Another device removes it before the pick lands.
    await tester.runAsync(
      () => repositories.workoutExercises.softDelete(
        fixture.workoutExerciseId,
        actor: 'sync',
      ),
    );
    final before = (await tester.runAsync(
      () => _replaceEntries(repositories),
    ))!;
    await tester.tap(
      find.byKey(ExerciseCatalogPicker.selectButtonKey(fixture.squat.id)),
    );
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(results, <String?>[null]);
    expect(shown.single.message, 'Exercise not replaced');
    expect(shown.single.undoLabel, isNull);
    expect(shown.single.onUndo, isNull);
    final after = (await tester.runAsync(
      () => _replaceEntries(repositories),
    ))!;
    expect(after, before);
    final rows = (await tester.runAsync(
      () => repositories.workoutExercises.listActiveForWorkout(
        fixture.workoutId,
      ),
    ))!;
    expect(rows, isEmpty);
  });
}

/// The Activity Log entries of the tables Replace writes.
Future<List<String>> _replaceEntries(TrainingRepositories repositories) async {
  final entries = await repositories.activityLog.listEntries();
  return <String>[
    for (final entry in entries)
      if (entry.entityTable == AppDatabase.workoutExercisesTable ||
          entry.entityTable == AppDatabase.loggedSetsTable ||
          entry.entityTable == AppDatabase.exerciseGroupMembersTable)
        '${entry.entityTable} ${entry.entityId}',
  ];
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
/// Workout Exercise and records what it returns and what it shows.
Future<void> _pumpHarness(
  WidgetTester tester,
  TrainingRepositories repositories,
  _Fixture fixture,
  List<String?> results,
  List<TrainingConfirmation> shown,
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
                      show: shown.add,
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
