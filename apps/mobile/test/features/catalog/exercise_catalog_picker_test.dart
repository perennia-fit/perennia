import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/platform_exercise_seed.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/catalog/repositories/exercise_catalog_repository.dart';
import 'package:perennia/features/catalog/widgets/exercise_catalog_picker.dart';
import 'package:perennia/features/catalog/widgets/exercise_editor_screen.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  testWidgets('picker meets accessibility guidelines in both themes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      await _pumpPicker(
        tester,
        sections: _accessibilitySections,
        waitForText: 'Barbell Press',
        theme: theme,
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.enterText(
        find.byKey(ExerciseCatalogPicker.searchFieldKey),
        'Nordic Curl',
      );
      await _pumpSearchDebounce(tester);
      expect(
        find.byKey(ExerciseCatalogPicker.createExerciseButtonKey),
        findsOneWidget,
      );
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('offers Exercise creation while browsing the catalog', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repositories = TrainingRepositories(
      database,
      platformSeedSource: const _EmptyPickerSeedSource(),
    );

    await _pumpPicker(tester, repositories: repositories);

    expect(
      find.byKey(ExerciseCatalogPicker.createExerciseButtonKey),
      findsOneWidget,
    );
    expect(find.text('Create exercise'), findsOneWidget);

    await tester.tap(
      find.byKey(ExerciseCatalogPicker.createExerciseButtonKey),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseEditorScreen), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(ExerciseEditorScreen.nameFieldKey))
          .controller
          ?.text,
      isEmpty,
    );
  });

  testWidgets(
    'offers prefilled Exercise creation while partial matches remain visible',
    (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repositories = TrainingRepositories(
        database,
        platformSeedSource: const _EmptyPickerSeedSource(),
      );

      await _pumpPicker(tester, repositories: repositories);

      await tester.enterText(
        find.byKey(ExerciseCatalogPicker.searchFieldKey),
        'Barbell',
      );
      await tester.pump();

      expect(find.text('Barbell Press'), findsOneWidget);
      expect(find.text('Barbell Squat'), findsOneWidget);
      expect(find.text('Create "Barbell"'), findsOneWidget);

      await tester.tap(
        find.byKey(ExerciseCatalogPicker.createExerciseButtonKey),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ExerciseEditorScreen), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(ExerciseEditorScreen.nameFieldKey))
            .controller
            ?.text,
        'Barbell',
      );
    },
  );

  testWidgets('filters exercises by type, body part, and equipment', (
    tester,
  ) async {
    await _pumpPicker(tester);

    expect(find.text('Barbell Squat'), findsOneWidget);
    expect(find.text('Barbell Press'), findsOneWidget);
    expect(find.text('Mobility Flow'), findsOneWidget);
    expect(find.text('Run'), findsOneWidget);

    await _selectDropdownOption(
      tester,
      dropdownKey: ExerciseCatalogPicker.typeFilterKey,
      optionText: 'Strength',
    );

    expect(find.text('Barbell Squat'), findsOneWidget);
    expect(find.text('Barbell Press'), findsOneWidget);
    expect(find.text('Mobility Flow'), findsNothing);
    expect(find.text('Run'), findsNothing);

    await _selectDropdownOption(
      tester,
      dropdownKey: ExerciseCatalogPicker.bodyPartFilterKey,
      optionText: 'Chest',
    );

    expect(find.text('Barbell Press'), findsOneWidget);
    expect(find.text('Barbell Squat'), findsNothing);

    await _selectDropdownOption(
      tester,
      dropdownKey: ExerciseCatalogPicker.equipmentFilterKey,
      optionText: 'Bench',
    );

    expect(find.text('Barbell Press'), findsOneWidget);

    await _selectDropdownOption(
      tester,
      dropdownKey: ExerciseCatalogPicker.typeFilterKey,
      optionText: 'Cardio',
    );

    expect(find.text('Barbell Press'), findsNothing);
    expect(
      find.text('No exercises match your search and filters'),
      findsOneWidget,
    );
  });

  testWidgets('filters exercises with partial multi-term search', (
    tester,
  ) async {
    await _pumpPicker(tester);

    await tester.enterText(
      find.byKey(ExerciseCatalogPicker.searchFieldKey),
      'ba pr',
    );
    await _pumpSearchDebounce(tester);

    expect(find.text('Barbell Press'), findsOneWidget);
    expect(find.text('Barbell Squat'), findsNothing);
    expect(find.text('Mobility Flow'), findsNothing);

    await tester.enterText(
      find.byKey(ExerciseCatalogPicker.searchFieldKey),
      'PR BA',
    );
    await _pumpSearchDebounce(tester);

    expect(find.text('Barbell Press'), findsOneWidget);
    expect(find.text('Barbell Squat'), findsNothing);
  });

  testWidgets('keeps creation available when filters hide a catalog match', (
    tester,
  ) async {
    await _pumpPicker(tester);

    await _selectDropdownOption(
      tester,
      dropdownKey: ExerciseCatalogPicker.typeFilterKey,
      optionText: 'Cardio',
    );
    await tester.enterText(
      find.byKey(ExerciseCatalogPicker.searchFieldKey),
      'Barbell Press',
    );
    await _pumpSearchDebounce(tester);

    expect(
      find.text('No exercises match your search and filters'),
      findsOneWidget,
    );
    expect(
      find.byKey(ExerciseCatalogPicker.createExerciseButtonKey),
      findsOneWidget,
    );
    expect(find.text('Create "Barbell Press"'), findsOneWidget);
  });

  testWidgets('debounces exercise search before filtering the local catalog', (
    tester,
  ) async {
    await _pumpPicker(tester);

    await tester.enterText(
      find.byKey(ExerciseCatalogPicker.searchFieldKey),
      'ba pr',
    );
    await tester.pump(ExerciseCatalogPicker.searchDebounceDuration ~/ 2);

    expect(find.text('Barbell Press'), findsOneWidget);
    expect(find.text('Barbell Squat'), findsOneWidget);

    await _pumpSearchDebounce(tester);

    expect(find.text('Barbell Press'), findsOneWidget);
    expect(find.text('Barbell Squat'), findsNothing);
  });

  testWidgets(
    'submitting exercise search applies before the debounce elapses',
    (tester) async {
      await _pumpPicker(tester);

      await tester.enterText(
        find.byKey(ExerciseCatalogPicker.searchFieldKey),
        'ba pr',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.text('Barbell Press'), findsOneWidget);
      expect(find.text('Barbell Squat'), findsNothing);
    },
  );

  testWidgets(
    'creates an unmatched search as a User Library Exercise and selects it',
    (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repositories = TrainingRepositories(
        database,
        platformSeedSource: const _EmptyPickerSeedSource(),
      );
      final selectedExercises = <ExerciseRecord>[];

      await _pumpPicker(
        tester,
        repositories: repositories,
        onExerciseSelected: selectedExercises.add,
      );

      await tester.enterText(
        find.byKey(ExerciseCatalogPicker.searchFieldKey),
        'Nordic Curl',
      );
      await _pumpSearchDebounce(tester);

      expect(
        find.byKey(ExerciseCatalogPicker.createExerciseButtonKey),
        findsOneWidget,
      );
      expect(find.text('Create "Nordic Curl"'), findsOneWidget);

      await tester.tap(
        find.byKey(ExerciseCatalogPicker.createExerciseButtonKey),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ExerciseEditorScreen), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(ExerciseEditorScreen.nameFieldKey),
            )
            .controller
            ?.text,
        'Nordic Curl',
      );

      await tester.scrollUntilVisible(
        find.byKey(ExerciseEditorScreen.saveButtonKey),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(ExerciseEditorScreen.saveButtonKey));
      await tester.pumpAndSettle();

      expect(selectedExercises, hasLength(1));
      expect(selectedExercises.single.name, 'Nordic Curl');
      expect(selectedExercises.single.origin, ExerciseLibraryOrigin.user);

      final matchingRows = (await database.select(database.exercises).get())
          .where((row) => row.name == 'Nordic Curl')
          .toList(growable: false);
      expect(matchingRows, hasLength(1));
      expect(
        matchingRows.single.libraryOrigin,
        ExerciseLibraryOrigin.user.name,
      );
    },
  );

  testWidgets('empty library keeps creation visible without empty filters', (
    tester,
  ) async {
    await _pumpPicker(
      tester,
      sections: const <ExerciseCatalogSectionRecord>[],
      waitForText: 'Create exercise',
    );

    expect(find.text('No exercises in your library yet'), findsOneWidget);
    expect(
      find.byKey(ExerciseCatalogPicker.createExerciseButtonKey),
      findsOneWidget,
    );
    expect(find.byKey(ExerciseCatalogPicker.typeFilterKey), findsNothing);
    expect(find.byKey(ExerciseCatalogPicker.bodyPartFilterKey), findsNothing);
    expect(find.byKey(ExerciseCatalogPicker.equipmentFilterKey), findsNothing);
  });

  testWidgets('keeps virtual favorites out of targeted filters', (
    tester,
  ) async {
    await _pumpPicker(tester);

    await tester.tap(find.byKey(ExerciseCatalogPicker.bodyPartFilterKey));
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        ExerciseCatalogPicker.bodyPartFilterOptionKey(
          ExerciseCatalogSectionRecord.favoritesId,
        ),
      ),
      findsNothing,
    );

    await tester.tap(find.text('All body parts').last);
    await tester.pumpAndSettle();
  });

  testWidgets('loads more exercises as the picker scrolls', (
    tester,
  ) async {
    final sections = <ExerciseCatalogSectionRecord>[
      ExerciseCatalogSectionRecord(
        category: ExerciseCategoryRecord(
          id: _chestCategoryId,
          name: 'Chest',
          sortOrder: 0,
          colorHex: '#2F6FED',
          updatedAt: _updatedAt,
        ),
        exercises: List<ExerciseRecord>.generate(
          ExerciseCatalogPicker.pageSize + 1,
          (index) => _exerciseRecord(
            id: '01910000-0000-7000-8000-${(100000 + index).toString().padLeft(12, '0')}',
            name: 'Paged Exercise ${index + 1}',
            categoryId: _chestCategoryId,
          ),
        ),
      ),
    ];

    await _pumpPicker(
      tester,
      sections: sections,
      waitForText: 'Paged Exercise 1',
    );

    expect(find.byKey(ExerciseCatalogPicker.pageSummaryKey), findsOneWidget);
    expect(find.text('Showing 1-30 of 31'), findsOneWidget);
    expect(find.text('Paged Exercise 1'), findsOneWidget);
    expect(find.text('Paged Exercise 31'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Paged Exercise 30'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Showing 1-31 of 31'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Paged Exercise 31'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Paged Exercise 31'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(ExerciseCatalogPicker.searchFieldKey),
      -400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(ExerciseCatalogPicker.searchFieldKey),
      '31',
    );
    await _pumpSearchDebounce(tester);

    expect(find.text('Showing 1-1 of 1'), findsOneWidget);
    expect(find.text('Paged Exercise 1'), findsNothing);
    expect(find.text('Paged Exercise 31'), findsOneWidget);
  });

  testWidgets('selects an exercise by tapping the row without a plus button', (
    tester,
  ) async {
    final selectedExerciseIds = <String>[];

    await _pumpPicker(
      tester,
      onExerciseSelected: (exercise) {
        selectedExerciseIds.add(exercise.id);
      },
    );

    final squatRow = find.byKey(
      ExerciseCatalogPicker.selectButtonKey(
        '01910000-0000-7000-8000-000000000101',
      ),
    );
    expect(squatRow, findsOneWidget);
    expect(
      find.descendant(
        of: squatRow,
        matching: find.byIcon(Icons.add_circle_outline),
      ),
      findsNothing,
    );

    await tester.tap(squatRow);
    await tester.pump();

    expect(selectedExerciseIds, <String>[
      '01910000-0000-7000-8000-000000000101',
    ]);
  });

  testWidgets('shows customized badge and platform restore actions', (
    tester,
  ) async {
    await _pumpPicker(tester, sections: _shadowSections);

    expect(find.byIcon(Icons.lock_outline), findsNothing);
    expect(
      find.text('Customized - overrides a platform exercise'),
      findsOneWidget,
    );
    expect(
      find.byKey(ExerciseCatalogPicker.restorePlatformButtonKey(_shadowId)),
      findsOneWidget,
    );
    expect(
      find.byKey(ExerciseCatalogPicker.customizeButtonKey(_platformPressId)),
      findsOneWidget,
    );
    expect(
      find.byKey(ExerciseCatalogPicker.restorePlatformButtonKey(_plainUserId)),
      findsNothing,
    );
  });
}

Future<void> _pumpSearchDebounce(WidgetTester tester) async {
  await tester.pump(ExerciseCatalogPicker.searchDebounceDuration);
  await tester.pumpAndSettle();
}

Future<void> _pumpPicker(
  WidgetTester tester, {
  List<ExerciseCatalogSectionRecord>? sections,
  ValueChanged<ExerciseRecord>? onExerciseSelected,
  TrainingRepositories? repositories,
  String waitForText = 'Barbell Squat',
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (repositories != null)
          trainingRepositoriesProvider.overrideWith(
            (ref) => repositories,
          ),
        exerciseCatalogRepositoryProvider.overrideWith(
          (ref) => StubExerciseCatalogRepository(
            sections: sections ?? _sections,
          ),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppDimens.base),
              child: SizedBox(
                height: 560,
                child: ExerciseCatalogPicker(
                  onExerciseSelected: onExerciseSelected,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _waitForFinder(tester, find.text(waitForText));
}

class _EmptyPickerSeedSource implements PlatformExerciseSeedSource {
  const _EmptyPickerSeedSource();

  @override
  Future<PlatformExerciseSeed> load() async {
    return const PlatformExerciseSeed(
      categories: <SeedExerciseCategory>[],
      exercises: <SeedExercise>[],
    );
  }
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

Future<void> _selectDropdownOption(
  WidgetTester tester, {
  required Key dropdownKey,
  required String optionText,
}) async {
  await tester.tap(find.byKey(dropdownKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(optionText).last);
  await tester.pumpAndSettle();
}

const _chestCategoryId = '01910000-0000-7000-8000-000000000001';
const _backCategoryId = '01910000-0000-7000-8000-000000000002';
const _mobilityCategoryId = '01910000-0000-7000-8000-000000000003';
const _cardioCategoryId = '01910000-0000-7000-8000-000000000004';
const _shadowId = '01910000-0000-7000-8000-000000000201';
const _plainUserId = '01910000-0000-7000-8000-000000000202';
const _platformPressId = '01910000-0000-7000-8000-000000000203';
final _updatedAt = DateTime.utc(2026);
final _barbellPress = ExerciseRecord(
  id: '01910000-0000-7000-8000-000000000103',
  origin: ExerciseLibraryOrigin.platform,
  name: 'Barbell Press',
  type: ExerciseType(
    const <DimensionId>[DimensionId.load, DimensionId.reps],
  ),
  defaultLoadUnit: TrainingUnit.kilogram,
  loadMode: ExerciseLoadMode.added,
  recordProfile: RecordProfile.repMax,
  categoryId: _chestCategoryId,
  equipment: const <ExerciseEquipment>[
    ExerciseEquipment.barbell,
    ExerciseEquipment.bench,
  ],
  notes: null,
  isFavorite: true,
  updatedAt: _updatedAt,
);

final _accessibilitySections = <ExerciseCatalogSectionRecord>[
  ExerciseCatalogSectionRecord(
    category: ExerciseCategoryRecord(
      id: _chestCategoryId,
      name: 'Chest',
      sortOrder: 0,
      colorHex: '#E06C5A',
      updatedAt: _updatedAt,
    ),
    exercises: <ExerciseRecord>[_barbellPress],
  ),
];

ExerciseRecord _exerciseRecord({
  required String id,
  required String name,
  required String categoryId,
}) {
  return ExerciseRecord(
    id: id,
    origin: ExerciseLibraryOrigin.platform,
    name: name,
    type: ExerciseType(
      const <DimensionId>[DimensionId.load, DimensionId.reps],
    ),
    defaultLoadUnit: TrainingUnit.kilogram,
    loadMode: ExerciseLoadMode.added,
    recordProfile: RecordProfile.repMax,
    categoryId: categoryId,
    notes: null,
    isFavorite: false,
    updatedAt: _updatedAt,
  );
}

final _sections = <ExerciseCatalogSectionRecord>[
  ExerciseCatalogSectionRecord.virtualFavorites(
    exercises: <ExerciseRecord>[_barbellPress],
  ),
  ExerciseCatalogSectionRecord(
    category: ExerciseCategoryRecord(
      id: _chestCategoryId,
      name: 'Chest',
      sortOrder: 0,
      colorHex: '#E06C5A',
      updatedAt: _updatedAt,
    ),
    exercises: <ExerciseRecord>[_barbellPress],
  ),
  ExerciseCatalogSectionRecord(
    category: ExerciseCategoryRecord(
      id: _backCategoryId,
      name: 'Back',
      sortOrder: 1,
      colorHex: '#2F6FED',
      updatedAt: _updatedAt,
    ),
    exercises: <ExerciseRecord>[
      ExerciseRecord(
        id: '01910000-0000-7000-8000-000000000101',
        origin: ExerciseLibraryOrigin.platform,
        name: 'Barbell Squat',
        type: ExerciseType(
          const <DimensionId>[DimensionId.load, DimensionId.reps],
        ),
        defaultLoadUnit: TrainingUnit.kilogram,
        loadMode: ExerciseLoadMode.added,
        recordProfile: RecordProfile.repMax,
        categoryId: _backCategoryId,
        equipment: const <ExerciseEquipment>[ExerciseEquipment.barbell],
        notes: null,
        isFavorite: false,
        updatedAt: _updatedAt,
      ),
    ],
  ),
  ExerciseCatalogSectionRecord(
    category: ExerciseCategoryRecord(
      id: _mobilityCategoryId,
      name: 'Mobility',
      sortOrder: 2,
      colorHex: '#1F9D55',
      updatedAt: _updatedAt,
    ),
    exercises: <ExerciseRecord>[
      ExerciseRecord(
        id: '01910000-0000-7000-8000-000000000102',
        origin: ExerciseLibraryOrigin.platform,
        name: 'Mobility Flow',
        type: ExerciseType.empty,
        defaultLoadUnit: TrainingUnit.kilogram,
        loadMode: ExerciseLoadMode.added,
        recordProfile: RecordProfile.completionStreak,
        categoryId: _mobilityCategoryId,
        equipment: const <ExerciseEquipment>[
          ExerciseEquipment.bodyweight,
          ExerciseEquipment.gymMat,
        ],
        notes: null,
        isFavorite: false,
        updatedAt: _updatedAt,
      ),
    ],
  ),
  ExerciseCatalogSectionRecord(
    category: ExerciseCategoryRecord(
      id: _cardioCategoryId,
      name: 'Cardio',
      sortOrder: 3,
      colorHex: '#E0608F',
      updatedAt: _updatedAt,
    ),
    exercises: <ExerciseRecord>[
      ExerciseRecord(
        id: '01910000-0000-7000-8000-000000000104',
        origin: ExerciseLibraryOrigin.platform,
        name: 'Run',
        type: ExerciseType(
          const <DimensionId>[DimensionId.duration, DimensionId.distance],
        ),
        defaultLoadUnit: TrainingUnit.kilogram,
        loadMode: ExerciseLoadMode.added,
        recordProfile: RecordProfile.fastestPace,
        categoryId: _cardioCategoryId,
        notes: null,
        isFavorite: false,
        updatedAt: _updatedAt,
      ),
    ],
  ),
];

final _shadowSections = <ExerciseCatalogSectionRecord>[
  ExerciseCatalogSectionRecord(
    category: ExerciseCategoryRecord(
      id: _backCategoryId,
      name: 'Back',
      sortOrder: 0,
      colorHex: '#2F6FED',
      updatedAt: _updatedAt,
    ),
    exercises: <ExerciseRecord>[
      ExerciseRecord(
        id: _shadowId,
        origin: ExerciseLibraryOrigin.user,
        name: 'Barbell Squat',
        type: ExerciseType(
          const <DimensionId>[DimensionId.load, DimensionId.reps],
        ),
        defaultLoadUnit: TrainingUnit.kilogram,
        loadMode: ExerciseLoadMode.added,
        recordProfile: RecordProfile.repMax,
        categoryId: _backCategoryId,
        equipment: const <ExerciseEquipment>[ExerciseEquipment.barbell],
        notes: null,
        isFavorite: false,
        shadowsPlatformExercise: true,
        updatedAt: _updatedAt,
      ),
      ExerciseRecord(
        id: _platformPressId,
        origin: ExerciseLibraryOrigin.platform,
        name: 'Barbell Press',
        type: ExerciseType(
          const <DimensionId>[DimensionId.load, DimensionId.reps],
        ),
        defaultLoadUnit: TrainingUnit.kilogram,
        loadMode: ExerciseLoadMode.added,
        recordProfile: RecordProfile.repMax,
        categoryId: _backCategoryId,
        equipment: const <ExerciseEquipment>[ExerciseEquipment.barbell],
        notes: null,
        isFavorite: false,
        updatedAt: _updatedAt,
      ),
      ExerciseRecord(
        id: _plainUserId,
        origin: ExerciseLibraryOrigin.user,
        name: 'Tempo Press',
        type: ExerciseType(
          const <DimensionId>[DimensionId.load, DimensionId.reps],
        ),
        defaultLoadUnit: TrainingUnit.kilogram,
        loadMode: ExerciseLoadMode.added,
        recordProfile: RecordProfile.repMax,
        categoryId: _backCategoryId,
        notes: null,
        isFavorite: false,
        updatedAt: _updatedAt,
      ),
    ],
  ),
];
