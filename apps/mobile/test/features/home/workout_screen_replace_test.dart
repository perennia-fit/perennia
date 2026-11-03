import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/catalog/repositories/exercise_catalog_repository.dart';
import 'package:perennia/features/catalog/widgets/exercise_catalog_picker.dart';
import 'package:perennia/features/home/widgets/workout_screen.dart';
import 'package:perennia/l10n/l10n.dart';
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

  late AppDatabase database;
  late TrainingRepositories repositories;

  setUp(() {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(database);
  });

  tearDown(() async {
    await database.close();
  });

  _testWorkoutScreen(
      'CUJ 13: Replace exercise on a card swaps the superset member, and '
      'Undo restores it', (tester) async {
    final fixture = (await tester.runAsync(
      () => _createReplaceFixture(repositories),
    ))!;
    await _pumpWorkoutScreen(tester, repositories, fixture);

    expect(_cardNames(tester), <String>['Pull-Up', 'Incline Press']);

    await _chooseReplace(
      tester,
      fixture.inclineWorkoutExerciseId,
      fixture.machinePress.id,
    );
    await _waitFor(tester, () => _cardNames(tester).length == 3);

    // The Workout screen stays, with the new card in the old one's place.
    expect(find.byType(WorkoutScreen), findsOneWidget);
    expect(_cardNames(tester), <String>[
      'Pull-Up',
      'Incline Machine Press',
      'Incline Press',
    ]);
    expect(find.widgetWithText(SnackBar, 'Replaced'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget);
    final machineCardId = _cardIds(tester)[1];
    _expectCardText(machineCardId, '0/2 sets');
    // Incline Press keeps its performed Set, outside the superset.
    _expectCardText(fixture.inclineWorkoutExerciseId, 'Done');
    // The superset is still in progress, so Now stays on its first card.
    _expectCardText(fixture.pullUpWorkoutExerciseId, 'Now');
    _expectCardText(fixture.pullUpWorkoutExerciseId, 'Round 2 of 3');

    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await _waitFor(tester, () => _cardNames(tester).length == 2);

    expect(_cardNames(tester), <String>['Pull-Up', 'Incline Press']);
    _expectCardText(fixture.inclineWorkoutExerciseId, '1/3 sets');
    expect(find.text("Couldn't undo: changed since"), findsNothing);
  });

  _testWorkoutScreen(
      'Replace exercise with one already in the Workout says so and '
      'changes nothing', (tester) async {
    final fixture = (await tester.runAsync(
      () => _createReplaceFixture(repositories),
    ))!;
    await _pumpWorkoutScreen(tester, repositories, fixture);

    await _chooseReplace(
      tester,
      fixture.inclineWorkoutExerciseId,
      fixture.pullUpExercise.id,
    );
    await _settle(tester);

    expect(
      find.widgetWithText(SnackBar, 'Already in this workout'),
      findsOneWidget,
    );
    expect(find.widgetWithText(SnackBarAction, 'Undo'), findsNothing);
    expect(_cardNames(tester), <String>['Pull-Up', 'Incline Press']);
  });

  _testWorkoutScreen('the card options button is 48 dp and labelled', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(
      () => _createReplaceFixture(repositories),
    ))!;
    final semantics = tester.ensureSemantics();
    await _pumpWorkoutScreen(tester, repositories, fixture);

    final button = find.byKey(
      WorkoutScreen.exerciseOptionsButtonKey(fixture.inclineWorkoutExerciseId),
    );
    final size = tester.getSize(button);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(
      tester.getSemantics(
        find.descendant(of: button, matching: find.byType(IconButton)),
      ),
      matchesSemantics(
        tooltip: 'Options for Incline Press',
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        hasEnabledState: true,
        isEnabled: true,
        // A popup menu button reports whether its menu is open.
        hasExpandedState: true,
      ),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  _testWorkoutScreen('a card with the options button fits at text scale 2.0',
      (tester) async {
    final fixture = (await tester.runAsync(
      () => _createReplaceFixture(
        repositories,
        inclineName: 'Incline Dumbbell Press With Neutral Grip',
      ),
    ))!;
    await _pumpWorkoutScreen(
      tester,
      repositories,
      fixture,
      surfaceSize: const Size(360, 3200),
      textScaler: const TextScaler.linear(2),
    );

    // The Workout header's own fit at this scale is its own test; the
    // cards' rows are checked here.
    tester.takeException();
    final card = find.byKey(
      WorkoutScreen.exerciseCardKey(fixture.inclineWorkoutExerciseId),
    );
    final flexes = tester.renderObjectList<RenderFlex>(
      find.descendant(
        of: card,
        matching: find.byWidgetPredicate((widget) => widget is Flex),
      ),
    );
    expect(flexes, isNotEmpty);
    for (final flex in flexes) {
      expect(flex.toStringShort(), isNot(contains('OVERFLOWING')));
    }
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(
          WorkoutScreen.exerciseOptionsButtonKey(
            fixture.inclineWorkoutExerciseId,
          ),
        ),
      ),
      findsOneWidget,
    );
  });
}

/// A widget test of the Workout screen that tears the tree down before the
/// database closes: the screen holds live Drift streams.
void _testWorkoutScreen(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    try {
      await callback(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
    }
  });
}

/// CUJ 13: the superset [Pull-Up, Incline Press], each with one performed
/// and two planned Sets, and Incline Machine Press last performed in an
/// earlier Workout. The catalogue offers both exercises the tests pick.
Future<_ReplaceFixture> _createReplaceFixture(
  TrainingRepositories repositories, {
  String inclineName = 'Incline Press',
}) async {
  final workoutId = await repositories.workoutSessions.create(
    WorkoutSessionDraft(
      startedAt: DateTime.utc(2026, 11, 2, 6),
      timezone: 'UTC',
    ),
  );
  final pullUpExerciseId = await repositories.exercises.create(
    ExerciseDraft(
      name: 'Pull-Up',
      type: ExerciseType(const <DimensionId>[DimensionId.reps]),
    ),
  );
  final inclineExerciseId = await repositories.exercises.create(
    ExerciseDraft(name: inclineName, type: _loadReps),
  );
  final pullUpWorkoutExerciseId = await repositories.workoutExercises.create(
    WorkoutExerciseDraft(workoutId: workoutId, exerciseId: pullUpExerciseId),
  );
  final inclineWorkoutExerciseId = await repositories.workoutExercises.create(
    WorkoutExerciseDraft(workoutId: workoutId, exerciseId: inclineExerciseId),
  );
  for (final (exerciseId, values) in <(String, LoggedSet)>[
    (pullUpExerciseId, _reps('8')),
    (inclineExerciseId, _loadRepsValues('26', '10')),
  ]) {
    for (var index = 0; index < 3; index += 1) {
      await repositories.sets.create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
          position: await repositories.sets.nextPositionForWorkout(workoutId),
          values: values,
          plannedRestAfter: const Duration(seconds: 90),
          isCompleted: index == 0,
          performedAt: index == 0 ? DateTime.utc(2026, 11, 2, 6, 5) : null,
        ),
      );
    }
  }
  await repositories.exerciseGroups.create(
    ExerciseGroupDraft(
      workoutId: workoutId,
      name: 'Superset',
      colorHex: '#2F6FED',
      workoutExerciseIds: <String>[
        pullUpWorkoutExerciseId,
        inclineWorkoutExerciseId,
      ],
    ),
  );

  final earlierWorkoutId = await repositories.workoutSessions.create(
    WorkoutSessionDraft(
      startedAt: DateTime.utc(2026, 10, 30, 6),
      timezone: 'UTC',
      endedAt: DateTime.utc(2026, 10, 30, 7),
    ),
  );
  final machinePressId = await repositories.exercises.create(
    ExerciseDraft(name: 'Incline Machine Press', type: _loadReps),
  );
  await repositories.workoutExercises.create(
    WorkoutExerciseDraft(
      workoutId: earlierWorkoutId,
      exerciseId: machinePressId,
    ),
  );
  await repositories.sets.create(
    LoggedSetDraft(
      workoutId: earlierWorkoutId,
      exerciseId: machinePressId,
      position: 0,
      values: _loadRepsValues('40', '10'),
      isCompleted: true,
    ),
  );

  final machinePress = (await repositories.exercises.getById(machinePressId))!;
  final pullUpExercise =
      (await repositories.exercises.getById(pullUpExerciseId))!;
  return _ReplaceFixture(
    workoutId: workoutId,
    pullUpWorkoutExerciseId: pullUpWorkoutExerciseId,
    inclineWorkoutExerciseId: inclineWorkoutExerciseId,
    machinePress: machinePress,
    pullUpExercise: pullUpExercise,
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
          exercises: <ExerciseRecord>[machinePress, pullUpExercise],
        ),
      ],
    ),
  );
}

class _ReplaceFixture {
  const _ReplaceFixture({
    required this.workoutId,
    required this.pullUpWorkoutExerciseId,
    required this.inclineWorkoutExerciseId,
    required this.machinePress,
    required this.pullUpExercise,
    required this.catalog,
  });

  final String workoutId;
  final String pullUpWorkoutExerciseId;
  final String inclineWorkoutExerciseId;
  final ExerciseRecord machinePress;
  final ExerciseRecord pullUpExercise;
  final ExerciseCatalogRepository catalog;
}

final _loadReps = ExerciseType(
  const <DimensionId>[DimensionId.load, DimensionId.reps],
);

LoggedSet _reps(String reps) {
  return LoggedSet.fromValues(<SetDimensionValue>[
    SetDimensionValue(
      dimension: DimensionId.reps,
      entered: reps,
      unit: TrainingUnit.repetition,
    ),
  ]);
}

LoggedSet _loadRepsValues(String load, String reps) {
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

Future<void> _pumpWorkoutScreen(
  WidgetTester tester,
  TrainingRepositories repositories,
  _ReplaceFixture fixture, {
  Size surfaceSize = const Size(400, 1600),
  TextScaler? textScaler,
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
        builder: textScaler == null
            ? null
            : (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: textScaler,
                  ),
                  child: child!,
                ),
        home: WorkoutScreen(workoutId: fixture.workoutId),
      ),
    ),
  );
  await _waitFor(tester, () => _cardIds(tester).isNotEmpty);
  await _settle(tester);
}

/// Opens [workoutExerciseId]'s card options, chooses Replace exercise and
/// picks [exerciseId].
Future<void> _chooseReplace(
  WidgetTester tester,
  String workoutExerciseId,
  String exerciseId,
) async {
  await tester.tap(
    find.byKey(WorkoutScreen.exerciseOptionsButtonKey(workoutExerciseId)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(
    find.byKey(WorkoutScreen.replaceExerciseMenuItemKey(workoutExerciseId)),
  );
  await _settle(tester);
  await tester.pump(const Duration(milliseconds: 400));
  final pick = find.byKey(ExerciseCatalogPicker.selectButtonKey(exerciseId));
  await _waitFor(tester, () => pick.evaluate().isNotEmpty);
  await tester.tap(pick);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await _settle(tester);
}

/// The Workout Exercise ids of the cards, top to bottom.
List<String> _cardIds(WidgetTester tester) {
  const prefix = 'workout.exercise.';
  final cards = find.byWidgetPredicate((widget) {
    final key = widget.key;
    return widget is Material &&
        key is ValueKey<String> &&
        key.value.startsWith(prefix) &&
        !key.value.substring(prefix.length).contains('.');
  });
  final entries = <(double, String)>[
    for (final element in cards.evaluate())
      (
        tester.getTopLeft(find.byWidget(element.widget)).dy,
        (element.widget.key! as ValueKey<String>)
            .value
            .substring(prefix.length),
      ),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return <String>[for (final entry in entries) entry.$2];
}

List<String> _cardNames(WidgetTester tester) {
  return <String>[
    for (final id in _cardIds(tester))
      tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byKey(WorkoutScreen.exerciseCardKey(id)),
                  matching: find.byType(Text),
                )
                .first,
          )
          .data!,
  ];
}

void _expectCardText(String workoutExerciseId, String text) {
  expect(
    find.descendant(
      of: find.byKey(WorkoutScreen.exerciseCardKey(workoutExerciseId)),
      matching: find.text(text),
    ),
    findsOneWidget,
    reason: '$text on $workoutExerciseId',
  );
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

Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (condition()) {
      return;
    }
  }
  fail('Timed out; the cards read ${_cardNames(tester)}.');
}
