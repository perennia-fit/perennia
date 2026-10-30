import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/catalog/repositories/exercise_catalog_repository.dart';
import 'package:perennia/features/catalog/widgets/exercise_catalog_picker.dart';
import 'package:perennia/features/focus/repositories/focus_feature_repository.dart';
import 'package:perennia/features/focus/widgets/focused_exercise_list.dart';
import 'package:perennia/features/home/repositories/home_repository.dart';
import 'package:perennia/features/home/widgets/start_workout_sheet.dart';
import 'package:perennia/features/home/widgets/workout_screen.dart';
import 'package:perennia/features/template_picker/repositories/template_picker_feature_repository.dart';
import 'package:perennia/features/up_next/repositories/up_next_feature_repository.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

const _weightsId = '01910000-0000-7000-8000-000000000401';
const _enduranceId = '01910000-0000-7000-8000-000000000402';
const _legsId = '01910000-0000-7000-8000-000000000009';
const _squatId = '01910000-0000-7000-8000-000000000201';
const _deadliftId = '01910000-0000-7000-8000-000000000202';
const _rowId = '01910000-0000-7000-8000-000000000203';

final _focuses = <FocusRecord>[
  FocusRecord(
    id: _weightsId,
    name: 'Weights',
    sortOrder: 0,
    updatedAt: DateTime.utc(2026, 10, 24),
  ),
  FocusRecord(
    id: _enduranceId,
    name: 'Endurance',
    sortOrder: 1,
    updatedAt: DateTime.utc(2026, 10, 24),
  ),
];

void main() {
  group('start a workout sheet', () {
    testWidgets('offers every Focus and returns the one tapped', (
      tester,
    ) async {
      final result = await _openStartSheet(tester);

      expect(find.text('Weights'), findsOneWidget);
      expect(find.text('Endurance'), findsOneWidget);
      // A screen reader can activate the tile, not just see it.
      expect(
        tester.getSemantics(
          find.byKey(StartWorkoutSheet.focusTileKey(_weightsId)),
        ),
        matchesSemantics(
          label: 'Start a workout: Weights',
          isButton: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(find.byKey(StartWorkoutSheet.focusTileKey(_weightsId)));
      await tester.pumpAndSettle();

      final choice = await result;
      expect(choice?.focusId, _weightsId);
    });

    testWidgets(
        "leaves planned workouts to Today's Up next and Routines, so the "
        'sheet is only the unplanned start', (tester) async {
      await _openStartSheet(
        tester,
        upNext: _UpNextRepository(<UpNextSuggestionView>[
          UpNextSuggestionView(
            routineId: 'routine-1',
            routineName: 'Hybrid block',
            cadenceKind: CadenceKind.rotating,
            slot: 2,
            cards: const <UpNextCardView>[
              UpNextCardView(
                routineEntryId: 'entry-1',
                workoutTemplateId: 'template-1',
                templateName: 'Lower strength',
                isDone: false,
              ),
            ],
          ),
        ]),
      );

      expect(find.text('Lower strength'), findsNothing);
      expect(find.text('Weights'), findsOneWidget);
      expect(find.byKey(StartWorkoutSheet.emptyWorkoutKey), findsOneWidget);
    });

    testWidgets('still starts an empty workout without a Focus', (
      tester,
    ) async {
      final result = await _openStartSheet(tester);

      await tester.tap(find.byKey(StartWorkoutSheet.emptyWorkoutKey));
      await tester.pumpAndSettle();

      final choice = await result;
      expect(choice, isNotNull);
      expect(choice!.focusId, isNull);
    });

    testWidgets('meets tap-target and contrast guidelines in both themes', (
      tester,
    ) async {
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        await _openStartSheet(tester, theme: theme);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  });

  testWidgets(
      'an empty Workout under a Focus opens on the exercises logged under it',
      (tester) async {
    final workout = HomeWorkoutSummary(
      id: 'workout-1',
      startedAt: DateTime.utc(2026, 10, 24, 7),
      focusId: _weightsId,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeRepositoryProvider.overrideWithValue(_WorkoutRepository(workout)),
          exerciseCatalogRepositoryProvider.overrideWithValue(
            StubExerciseCatalogRepository(sections: _catalogSections()),
          ),
          focusFeatureRepositoryProvider.overrideWithValue(
            _FocusRepository(
              uses: <FocusExerciseUse>[
                FocusExerciseUse(
                  exerciseId: _deadliftId,
                  lastPerformedAt:
                      DateTime.now().subtract(const Duration(days: 3)),
                  workoutCount: 1,
                ),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const WorkoutScreen(workoutId: 'workout-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recent under Weights'), findsOneWidget);
    expect(find.text('Add your first exercise'), findsOneWidget);
    expect(find.text('3 days ago · 1 workout'), findsOneWidget);
    expect(
      find.byKey(FocusedExerciseList.exerciseRowKey(_deadliftId)),
      findsOneWidget,
    );
    // The rest of the Focus follows the history; other Focuses stay out.
    expect(
      find.byKey(FocusedExerciseList.exerciseRowKey(_squatId)),
      findsOneWidget,
    );
    expect(
        find.byKey(FocusedExerciseList.exerciseRowKey(_rowId)), findsNothing);
    expect(find.text('Weights'), findsOneWidget);
    // The Focus control is its own button for a screen reader, not a part of
    // the header card's node.
    expect(
      tester
          .getSemantics(find.byKey(WorkoutScreen.focusButtonKey('workout-1'))),
      matchesSemantics(
        label: 'Focus: Weights. Change focus',
        isButton: true,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('with nothing logged yet, the Focus\'s staples lead', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exerciseCatalogRepositoryProvider.overrideWithValue(
            StubExerciseCatalogRepository(sections: _catalogSections()),
          ),
          focusFeatureRepositoryProvider.overrideWithValue(
            _FocusRepository(
              starters: const <String, List<String>>{
                _weightsId: <String>[_deadliftId, _squatId],
              },
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(
              children: [
                FocusedExerciseList(
                  focus: _focuses.first,
                  onExerciseSelected: (_) {},
                  onBrowseFocus: () {},
                  onSearchAll: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Alphabetically Barbell Squat would come first; the curated order wins.
    expect(
      tester.getTopLeft(find.text('Deadlift')).dy,
      lessThan(tester.getTopLeft(find.text('Barbell Squat')).dy),
    );
  });

  testWidgets('tapping a focused exercise hands it back to add', (
    tester,
  ) async {
    final selected = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exerciseCatalogRepositoryProvider.overrideWithValue(
            StubExerciseCatalogRepository(sections: _catalogSections()),
          ),
          focusFeatureRepositoryProvider.overrideWithValue(
            _FocusRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(
              children: [
                FocusedExerciseList(
                  focus: _focuses.first,
                  onExerciseSelected: (exercise) => selected.add(exercise.id),
                  onBrowseFocus: () {},
                  onSearchAll: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No history yet: the staples lead, with no empty "recent" label.
    expect(find.text('Recent under Weights'), findsNothing);
    await tester.tap(find.byKey(FocusedExerciseList.exerciseRowKey(_squatId)));
    expect(selected, <String>[_squatId]);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });

  testWidgets('the picker opens on the Workout\'s Focus and can show all', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exerciseCatalogRepositoryProvider.overrideWithValue(
            StubExerciseCatalogRepository(sections: _catalogSections()),
          ),
          focusFeatureRepositoryProvider.overrideWithValue(
            _FocusRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: ExerciseCatalogPicker(initialFocusId: _enduranceId),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rowing Machine'), findsOneWidget);
    expect(find.text('Barbell Squat'), findsNothing);

    await tester.tap(
      find.byKey(ExerciseCatalogPicker.focusFilterOptionKey(null)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rowing Machine'), findsOneWidget);
    expect(find.text('Barbell Squat'), findsOneWidget);

    // A search under a Focus looks everywhere, with the Focus's matches
    // first.
    await tester.tap(
      find.byKey(ExerciseCatalogPicker.focusFilterOptionKey(_enduranceId)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(ExerciseCatalogPicker.searchFieldKey),
      'a',
    );
    await tester.pump(ExerciseCatalogPicker.searchDebounceDuration);
    await tester.pumpAndSettle();

    expect(find.text('In Endurance'), findsOneWidget);
    expect(find.text('Other exercises'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Rowing Machine')).dy,
      lessThan(tester.getTopLeft(find.text('Barbell Squat')).dy),
    );
  });
}

Future<Future<StartWorkoutChoice?>> _openStartSheet(
  WidgetTester tester, {
  UpNextFeatureRepository upNext = const StubUpNextFeatureRepository(),
  ThemeData? theme,
}) async {
  late Future<StartWorkoutChoice?> result;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        upNextFeatureRepositoryProvider.overrideWithValue(upNext),
        templatePickerFeatureRepositoryProvider.overrideWithValue(
          const StubTemplatePickerFeatureRepository(),
        ),
        focusFeatureRepositoryProvider.overrideWithValue(
          StubFocusFeatureRepository(focuses: _focuses),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => result = showStartWorkoutSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

List<ExerciseCatalogSectionRecord> _catalogSections() {
  final legs = ExerciseCategoryRecord(
    id: _legsId,
    name: 'Legs',
    sortOrder: 0,
    colorHex: '#5FB05C',
    updatedAt: DateTime.utc(2026, 6, 29),
  );
  ExerciseRecord exercise(String id, String name, List<String> focusIds) {
    return ExerciseRecord(
      id: id,
      origin: ExerciseLibraryOrigin.platform,
      name: name,
      type:
          ExerciseType(const <DimensionId>[DimensionId.load, DimensionId.reps]),
      defaultLoadUnit: TrainingUnit.kilogram,
      loadMode: ExerciseLoadMode.added,
      recordProfile: RecordProfile.repMax,
      categoryId: _legsId,
      focusIds: focusIds,
      notes: null,
      isFavorite: false,
      updatedAt: DateTime.utc(2026, 6, 29),
    );
  }

  return <ExerciseCatalogSectionRecord>[
    ExerciseCatalogSectionRecord(
      category: legs,
      exercises: <ExerciseRecord>[
        exercise(_squatId, 'Barbell Squat', const <String>[_weightsId]),
        exercise(_deadliftId, 'Deadlift', const <String>[_weightsId]),
        exercise(_rowId, 'Rowing Machine', const <String>[_enduranceId]),
      ],
    ),
  ];
}

class _FocusRepository extends StubFocusFeatureRepository {
  _FocusRepository({
    this.uses = const <FocusExerciseUse>[],
    this.starters = const <String, List<String>>{},
  }) : super(focuses: _focuses);

  final List<FocusExerciseUse> uses;
  final Map<String, List<String>> starters;

  @override
  Future<Map<String, List<String>>> starterExerciseIds() async => starters;

  @override
  Stream<List<FocusExerciseUse>> watchRecentExerciseUses(String focusId) {
    return Stream<List<FocusExerciseUse>>.value(uses);
  }
}

class _WorkoutRepository extends StubHomeRepository {
  _WorkoutRepository(this.workout);

  final HomeWorkoutSummary workout;

  @override
  Stream<HomeWorkoutSummary?> watchWorkout(String workoutId) {
    return Stream<HomeWorkoutSummary?>.value(workout);
  }
}

class _UpNextRepository implements UpNextFeatureRepository {
  const _UpNextRepository(this.suggestions);

  final List<UpNextSuggestionView> suggestions;

  @override
  Stream<List<UpNextSuggestionView>> watchSuggestions(
    TrainingDayDate selectedDate,
  ) {
    return Stream<List<UpNextSuggestionView>>.value(suggestions);
  }
}
