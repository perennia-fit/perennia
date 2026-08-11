import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart'
    show DuplicateMealTypeNameException;
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/features/nutrition/controllers/nutrition_day_controller.dart';
import 'package:perennia/features/nutrition/repositories/add_food_repository.dart';
import 'package:perennia/features/nutrition/widgets/add_food_picker.dart';
import 'package:perennia/features/nutrition/widgets/barcode_scanner.dart';
import 'package:perennia/features/nutrition/widgets/log_portion_screen.dart';
import 'package:perennia/features/nutrition/widgets/nutrition_day_view.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  testWidgets('renders unknown macro totals as dash instead of zero', (
    tester,
  ) async {
    final totals = NutrientTotals.fromEntries(
      <FoodEntryRecord>[_foodEntryWithMissingCarbs()],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: NutritionDaySummary(totals: totals),
        ),
      ),
    );

    expect(find.byKey(NutritionDayView.daySummaryKey), findsOneWidget);
    expect(find.text('Calories'), findsOneWidget);
    expect(find.text('Protein'), findsOneWidget);
    expect(find.text('Carbs'), findsOneWidget);
    expect(find.text('Fat'), findsOneWidget);
    expect(
      _summaryValueText(tester, NutrientId.energy),
      '100 kcal',
    );
    expect(
      _summaryValueText(tester, NutrientId.protein),
      '10 g',
    );
    expect(
      _summaryValueText(tester, NutrientId.fat),
      '3 g',
    );
    expect(
      _summaryValueText(tester, NutrientId.carbohydrate),
      _unknownTotalLabel,
    );
    expect(
      find.byKey(
        NutritionDayView.incompleteMarkerKey(NutrientId.carbohydrate),
      ),
      findsOneWidget,
    );
    expect(find.text('0 g'), findsNothing);
  });

  testWidgets(
      'Nutrition Day view meets accessibility guidelines in both themes',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nutritionDayControllerProvider.overrideWith(
              () => _FakeNutritionDayController(
                _nutritionDayWithMissingCarbs(),
              ),
            ),
            mealTypeListProvider.overrideWith(
              (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
            ),
          ],
          child: MaterialApp(
            theme: theme,
            home: const NutritionDayView(),
          ),
        ),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(
          NutritionDayView.incompleteMarkerKey(NutrientId.carbohydrate),
        ),
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Meal cards list Food Entry rows with amount and derived energy',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionDayControllerProvider.overrideWith(
            () => _FakeNutritionDayController(
              _nutritionDayWithFoodEntryRows(),
            ),
          ),
          mealTypeListProvider.overrideWith(
            (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NutritionDayView(),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(NutritionDayView.mealCardKey('meal-breakfast')),
    );

    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('125 g'), findsOneWidget);
    expect(find.text('65 kcal'), findsWidgets);
    expect(find.text('Quick calories'), findsOneWidget);
    expect(find.text('Quick entry'), findsOneWidget);
    expect(find.text('90 kcal'), findsOneWidget);
    expect(find.text('Mystery bar'), findsOneWidget);
    expect(find.text('50 g'), findsOneWidget);
    expect(find.text(_unknownTotalLabel), findsNWidgets(3));
  });

  testWidgets(
      'imported entries surface the preserved provider string and a '
      'non-blocking review-flag marker', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionDayControllerProvider.overrideWith(
            () => _FakeNutritionDayController(_nutritionDayWithImportedEntry()),
          ),
          mealTypeListProvider.overrideWith(
            (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NutritionDayView(),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(NutritionDayView.mealCardKey('meal-breakfast')),
    );

    // Generic Imported origin shows the preserved provider string, not a bare
    // "Imported".
    expect(
      find.byKey(NutritionDayView.importedEntryBadgeKey('entry-imported')),
      findsOneWidget,
    );
    expect(find.textContaining('Acme Diet Tracker'), findsOneWidget);
    // The soft-warn review flag surfaces inline, never as a blocking dialog.
    expect(
      find.byKey(NutritionDayView.reviewFlagMarkerKey('entry-imported')),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
      'imported-entry day view meets accessibility guidelines in both themes',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nutritionDayControllerProvider.overrideWith(
              () =>
                  _FakeNutritionDayController(_nutritionDayWithImportedEntry()),
            ),
            mealTypeListProvider.overrideWith(
              (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
            ),
          ],
          child: MaterialApp(
            theme: theme,
            home: const NutritionDayView(),
          ),
        ),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(NutritionDayView.importedEntryBadgeKey('entry-imported')),
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('date strip arrows and swipe move the selected Nutrition Day',
      (tester) async {
    final controller = _FakeNutritionDayController(
      _nutritionDayWithFoodEntryRows(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionDayControllerProvider.overrideWith(() => controller),
          mealTypeListProvider.overrideWith(
            (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NutritionDayView(),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.byKey(NutritionDayView.dayHeaderKey));

    await tester.tap(find.byKey(NutritionDayView.previousDayButtonKey));
    await tester.pump();
    await tester.tap(find.byKey(NutritionDayView.nextDayButtonKey));
    await tester.pump();
    await tester.fling(
      find.byKey(NutritionDayView.dayHeaderKey),
      const Offset(400, 0),
      1000,
    );
    await tester.pump();
    await tester.fling(
      find.byKey(NutritionDayView.dayHeaderKey),
      const Offset(-400, 0),
      1000,
    );
    await tester.pump();

    expect(controller.previousDayCount, 2);
    expect(controller.nextDayCount, 2);
  });

  testWidgets('lists same-type Meals as separate occasions and targets actions',
      (tester) async {
    final controller = _FakeNutritionDayController(
      _nutritionDayWithThreeSnacks(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionDayControllerProvider.overrideWith(() => controller),
          addFoodRepositoryProvider.overrideWith(
            (ref) => const _EmptyAddFoodRepository(),
          ),
          mealTypeListProvider.overrideWith(
            (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NutritionDayView(),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.byKey(NutritionDayView.daySummaryKey));
    final thirdSnackCard = find.byKey(
      NutritionDayView.mealCardKey('meal-snack-3'),
    );
    await tester.scrollUntilVisible(
      thirdSnackCard,
      400,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Snack'), findsWidgets);
    expect(find.text('9:00 PM'), findsOneWidget);
    expect(thirdSnackCard, findsOneWidget);

    final startSnackButton = find.byKey(
      NutritionDayView.startMealButtonKey('meal-type-snack'),
    );
    await tester.scrollUntilVisible(
      startSnackButton,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -96));
    await tester.pumpAndSettle();
    await tester.tap(startSnackButton);
    await tester.pump();
    expect(controller.startedMealTypes, <String>['Snack']);

    final addFoodButton = find.byKey(
      NutritionDayView.addFoodButtonKey('meal-snack-2'),
    );
    await tester.scrollUntilVisible(
      addFoodButton,
      -400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(addFoodButton);
    await tester.pumpAndSettle();
    await tester.tap(addFoodButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AddFoodPicker.quickAddButtonKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(NutritionDayView.quickEntryNameFieldKey),
      'Crackers',
    );
    await tester.enterText(
      find.byKey(NutritionDayView.quickEntryEnergyFieldKey),
      '90',
    );
    await tester.tap(find.byKey(NutritionDayView.quickEntrySaveButtonKey));
    await tester.pump();

    expect(controller.loggedMealIds, <String>['meal-snack-2']);
  });

  testWidgets(
      'starting a Meal uses the tapped Meal Type without auto-assigning',
      (tester) async {
    final controller = _FakeNutritionDayController(_emptyNutritionDay());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionDayControllerProvider.overrideWith(() => controller),
          mealTypeListProvider.overrideWith(
            (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NutritionDayView(),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.byKey(NutritionDayView.daySummaryKey));

    final dinnerButton = find.byKey(
      NutritionDayView.startMealButtonKey('meal-type-dinner'),
    );
    await tester.scrollUntilVisible(
      dinnerButton,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(dinnerButton);
    await tester.pump();

    expect(controller.startedMealTypes, <String>['Dinner']);
  });

  testWidgets('Meal Type manager adds renames archives and exposes reorder', (
    tester,
  ) async {
    final controller = _FakeNutritionDayController(_emptyNutritionDay());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionDayControllerProvider.overrideWith(() => controller),
          mealTypeListProvider.overrideWith(
            (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NutritionDayView(),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.byKey(NutritionDayView.daySummaryKey));

    final manageButton = find.byKey(NutritionDayView.manageMealTypesButtonKey);
    await tester.scrollUntilVisible(
      manageButton,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(manageButton);
    await tester.pumpAndSettle();

    expect(find.text('Manage Meal Types'), findsOneWidget);
    expect(
      find.byKey(
        NutritionDayView.mealTypeReorderHandleKey('meal-type-breakfast'),
      ),
      findsOneWidget,
    );
    final reorderableList = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    reorderableList.onReorderItem!(0, 2);
    await tester.pump();

    expect(
      controller.reorderedMealTypeIds,
      <List<String>>[
        <String>[
          'meal-type-lunch',
          'meal-type-dinner',
          'meal-type-breakfast',
          'meal-type-snack',
        ],
      ],
    );

    await tester.tap(find.byKey(NutritionDayView.addMealTypeButtonKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(NutritionDayView.mealTypeNameFieldKey),
      'Pre-workout',
    );
    await tester.tap(find.byKey(NutritionDayView.saveMealTypeButtonKey));
    await tester.pumpAndSettle();

    expect(controller.createdMealTypeNames, <String>['Pre-workout']);

    await tester.tap(
      find.byKey(NutritionDayView.editMealTypeButtonKey('meal-type-snack')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(NutritionDayView.mealTypeNameFieldKey),
      'Mini meal',
    );
    await tester.tap(find.byKey(NutritionDayView.saveMealTypeButtonKey));
    await tester.pumpAndSettle();

    expect(
      controller.renamedMealTypes,
      <String>['meal-type-snack:Mini meal'],
    );

    await tester.tap(
      find.byKey(NutritionDayView.archiveMealTypeButtonKey('meal-type-snack')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(NutritionDayView.confirmArchiveMealTypeButtonKey),
    );
    await tester.pumpAndSettle();

    expect(controller.archivedMealTypeIds, <String>['meal-type-snack']);
  });

  testWidgets('Meal Type form shows duplicate-name errors inline', (
    tester,
  ) async {
    final controller = _FakeNutritionDayController(
      _emptyNutritionDay(),
      duplicateMealTypeNames: <String>{'snack'},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionDayControllerProvider.overrideWith(() => controller),
          mealTypeListProvider.overrideWith(
            (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NutritionDayView(),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.byKey(NutritionDayView.daySummaryKey));

    final manageButton = find.byKey(NutritionDayView.manageMealTypesButtonKey);
    await tester.scrollUntilVisible(
      manageButton,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(manageButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(NutritionDayView.addMealTypeButtonKey));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(NutritionDayView.mealTypeNameFieldKey),
      ' Snack ',
    );
    await tester.tap(find.byKey(NutritionDayView.saveMealTypeButtonKey));
    await tester.pump();

    expect(find.text('Meal Type already exists'), findsOneWidget);
    expect(find.text('New Meal Type'), findsOneWidget);
    expect(controller.createdMealTypeNames, isEmpty);
  });

  testWidgets(
      'Meal Type management surfaces meet accessibility guidelines in both themes',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();
      final controller = _FakeNutritionDayController(_emptyNutritionDay());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nutritionDayControllerProvider.overrideWith(() => controller),
            mealTypeListProvider.overrideWith(
              (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
            ),
          ],
          child: MaterialApp(
            theme: theme,
            home: const NutritionDayView(),
          ),
        ),
      );
      await _pumpUntilFound(tester, find.byKey(NutritionDayView.daySummaryKey));

      final manageButton =
          find.byKey(NutritionDayView.manageMealTypesButtonKey);
      await tester.scrollUntilVisible(
        manageButton,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(manageButton);
      await tester.pumpAndSettle();

      expect(find.byKey(NutritionDayView.mealTypeTileKey('meal-type-snack')),
          findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.tap(find.byKey(NutritionDayView.addMealTypeButtonKey));
      await tester.pumpAndSettle();
      expect(find.text('New Meal Type'), findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          NutritionDayView.archiveMealTypeButtonKey('meal-type-snack'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Archive Snack?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Archive'), findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('selected Recent Food opens prefilled Log Portion and saves',
      (tester) async {
    final controller = _FakeNutritionDayController(
      _nutritionDayWithThreeSnacks(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionDayControllerProvider.overrideWith(() => controller),
          addFoodRepositoryProvider.overrideWith(
            (ref) => _SingleFoodRepository(_pickerFood()),
          ),
          mealTypeListProvider.overrideWith(
            (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NutritionDayView(),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(NutritionDayView.mealCardKey('meal-snack-2')),
    );

    final addFoodButton = find.byKey(
      NutritionDayView.addFoodButtonKey('meal-snack-2'),
    );
    await tester.scrollUntilVisible(
      addFoodButton,
      -400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(addFoodButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        AddFoodPicker.resultKey(AddFoodPickerFilter.recent, 'usda-chicken'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chicken breast'), findsOneWidget);
    expect(
      find.byKey(LogPortionScreen.unitChipKey(PortionUnit.gram)),
      findsOneWidget,
    );
    expect(_logPortionAmountText(tester), '1.5');
    expect(
      _logPortionReadoutValue(tester, NutrientId.energy),
      '212.8 kcal',
    );

    await tester.tap(find.byKey(LogPortionScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(controller.loggedFoodEntries, hasLength(1));
    final entry = controller.loggedFoodEntries.single;
    expect(entry.mealId, 'meal-snack-2');
    expect(entry.foodId, 'usda-chicken');
    expect(entry.name, 'Chicken breast');
    expect(entry.foodSource, FoodSource.usda);
    expect(entry.nutrientsPer100[NutrientId.energy].value, 165);
    expect(entry.isLiquid, isFalse);
    expect(entry.servingLabel, 'piece');
    expect(entry.servingSize, 86);
    expect(entry.packageSize, isNull);
    expect(entry.portion.value, 1.5);
    expect(entry.portion.entered, '1.5');
    expect(entry.portion.unit, PortionUnit.serving);
  });

  testWidgets('barcode scan opens Log Portion with Open Food Facts snapshot',
      (tester) async {
    final controller = _FakeNutritionDayController(
      _nutritionDayWithThreeSnacks(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionDayControllerProvider.overrideWith(() => controller),
          addFoodRepositoryProvider.overrideWith(
            (ref) => _BarcodeFoodRepository(_openFoodFactsBar()),
          ),
          barcodeScannerProvider.overrideWith(
            (ref) => const _FakeBarcodeScanner('3017620422003'),
          ),
          mealTypeListProvider.overrideWith(
            (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NutritionDayView(),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(NutritionDayView.mealCardKey('meal-snack-2')),
    );

    final addFoodButton = find.byKey(
      NutritionDayView.addFoodButtonKey('meal-snack-2'),
    );
    await tester.scrollUntilVisible(
      addFoodButton,
      -400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(addFoodButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AddFoodPicker.scanBarcodeButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Hazelnut cocoa spread'), findsOneWidget);
    expect(
      find.byKey(LogPortionScreen.unitChipKey(PortionUnit.serving)),
      findsOneWidget,
    );
    expect(
      find.byKey(LogPortionScreen.unitChipKey(PortionUnit.package)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(LogPortionScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(controller.loggedFoodEntries, hasLength(1));
    final entry = controller.loggedFoodEntries.single;
    expect(entry.mealId, 'meal-snack-2');
    expect(entry.foodId, '3017620422003');
    expect(entry.name, 'Hazelnut cocoa spread');
    expect(entry.foodSource, FoodSource.openFoodFacts);
    expect(entry.nutrientsPer100[NutrientId.energy].value, 539);
    expect(entry.nutrientsPer100[NutrientId.protein].value, 6.3);
    expect(entry.isLiquid, isFalse);
    expect(entry.servingLabel, 'serving');
    expect(entry.servingSize, 15);
    expect(entry.packageSize, 400);
    expect(entry.portion.value, 100);
    expect(entry.portion.entered, '100');
    expect(entry.portion.unit, PortionUnit.gram);
  });
}

const _unknownTotalLabel = '\u2014';

class _FakeNutritionDayController extends NutritionDayController {
  _FakeNutritionDayController(
    this.day, {
    Set<String>? duplicateMealTypeNames,
  }) : duplicateMealTypeNames = duplicateMealTypeNames ?? const <String>{};

  final NutritionDayRecord day;
  final Set<String> duplicateMealTypeNames;
  final startedMealTypes = <String>[];
  final loggedMealIds = <String>[];
  final loggedFoodEntries = <FoodEntrySnapshotDraft>[];
  final createdMealTypeNames = <String>[];
  final renamedMealTypes = <String>[];
  final reorderedMealTypeIds = <List<String>>[];
  final archivedMealTypeIds = <String>[];
  var previousDayCount = 0;
  var nextDayCount = 0;

  @override
  Stream<NutritionDayState> build() {
    return Stream<NutritionDayState>.value(NutritionDayState(day: day));
  }

  @override
  Future<String> startMeal({
    required MealTypeRecord mealType,
    DateTime? startedAt,
    NutritionDayDate? localDate,
  }) async {
    startedMealTypes.add(mealType.name);
    return 'created-meal-id';
  }

  @override
  Future<String> createMealType({
    required String name,
  }) async {
    _throwIfDuplicateMealTypeName(name);
    createdMealTypeNames.add(name);
    return 'created-meal-type';
  }

  @override
  Future<void> renameMealType({
    required MealTypeRecord mealType,
    required String name,
  }) async {
    _throwIfDuplicateMealTypeName(name);
    renamedMealTypes.add('${mealType.id}:$name');
  }

  void _throwIfDuplicateMealTypeName(String name) {
    if (duplicateMealTypeNames.contains(name.trim().toLowerCase())) {
      throw DuplicateMealTypeNameException(name);
    }
  }

  @override
  Future<void> reorderMealTypes(List<String> orderedIds) async {
    reorderedMealTypeIds.add(List<String>.unmodifiable(orderedIds));
  }

  @override
  Future<void> archiveMealType(String id) async {
    archivedMealTypeIds.add(id);
  }

  @override
  Future<LogQuickEntryResult> logQuickEntryForMeal({
    required String mealId,
    required QuickFoodEntryDraft entry,
  }) async {
    loggedMealIds.add(mealId);
    return LogQuickEntryResult(
      batchId: 'batch-$mealId',
      mealId: mealId,
      foodEntryId: 'entry-$mealId',
    );
  }

  @override
  Future<LogFoodEntryResult> logFoodEntrySnapshot({
    required FoodEntrySnapshotDraft entry,
  }) async {
    loggedFoodEntries.add(entry);
    return LogFoodEntryResult(
      batchId: 'batch-${entry.mealId}',
      mealId: entry.mealId,
      foodEntryId: 'entry-${entry.mealId}',
    );
  }

  @override
  void showPreviousDay() {
    previousDayCount += 1;
  }

  @override
  void showNextDay() {
    nextDayCount += 1;
  }
}

class _EmptyAddFoodRepository implements AddFoodRepository {
  const _EmptyAddFoodRepository();

  @override
  Future<List<FoodPickerItem>> search({
    required AddFoodPickerFilter filter,
    required String query,
    int limit = 50,
  }) async {
    return const <FoodPickerItem>[];
  }
}

class _SingleFoodRepository implements AddFoodRepository {
  const _SingleFoodRepository(this.food);

  final FoodPickerItem food;

  @override
  Future<List<FoodPickerItem>> search({
    required AddFoodPickerFilter filter,
    required String query,
    int limit = 50,
  }) async {
    if (filter != food.filter) {
      return const <FoodPickerItem>[];
    }
    return <FoodPickerItem>[food];
  }
}

class _BarcodeFoodRepository implements AddFoodRepository {
  const _BarcodeFoodRepository(this.food);

  final FoodPickerItem food;

  @override
  Future<List<FoodPickerItem>> search({
    required AddFoodPickerFilter filter,
    required String query,
    int limit = 50,
  }) async {
    if (filter == AddFoodPickerFilter.openFoodFacts &&
        query == '3017620422003') {
      return <FoodPickerItem>[food];
    }
    return const <FoodPickerItem>[];
  }
}

class _FakeBarcodeScanner implements BarcodeScanner {
  const _FakeBarcodeScanner(this.result);

  final String? result;

  @override
  Future<String?> scan(BuildContext context) async => result;
}

String? _summaryValueText(WidgetTester tester, NutrientId id) {
  return tester
      .widget<Text>(find.byKey(NutritionDayView.summaryValueKey(id)))
      .data;
}

String? _logPortionAmountText(WidgetTester tester) {
  return tester
      .widget<TextField>(find.byKey(LogPortionScreen.amountFieldKey))
      .controller
      ?.text;
}

String? _logPortionReadoutValue(WidgetTester tester, NutrientId id) {
  return tester
      .widget<Text>(find.byKey(LogPortionScreen.readoutValueKey(id)))
      .data;
}

NutritionDayRecord _emptyNutritionDay() {
  return NutritionDayRecord(
    localDate: const NutritionDayDate(year: 2026, month: 6, day: 26),
    meals: const <NutritionDayMealRecord>[],
  );
}

FoodEntryRecord _foodEntryWithMissingCarbs() {
  return FoodEntryRecord(
    id: 'food-entry-1',
    mealId: 'meal-1',
    kind: FoodEntryKind.quickEntry,
    position: 0,
    name: 'Known calories, missing carbs',
    nutrients: NutrientVector.full(<NutrientId, NutrientAmount>{
      NutrientId.energy: NutrientAmount.complete(
        value: 100,
        entered: '100',
        unit: NutrientUnit.kilocalorie,
      ),
      NutrientId.protein: NutrientAmount.complete(
        value: 10,
        entered: '10',
        unit: NutrientUnit.gram,
      ),
      NutrientId.fat: NutrientAmount.complete(
        value: 3,
        entered: '3',
        unit: NutrientUnit.gram,
      ),
    }),
    updatedAt: DateTime.utc(2026, 6, 26),
  );
}

NutritionDayRecord _nutritionDayWithMissingCarbs() {
  const localDate = NutritionDayDate(year: 2026, month: 6, day: 26);

  return NutritionDayRecord(
    localDate: localDate,
    meals: [
      NutritionDayMealRecord(
        meal: MealRecord(
          id: 'meal-1',
          mealType: 'Breakfast',
          startedAt: DateTime.utc(2026, 6, 26, 7),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
          updatedAt: DateTime.utc(2026, 6, 26, 7),
        ),
        entries: [_foodEntryWithMissingCarbs()],
      ),
    ],
  );
}

NutritionDayRecord _nutritionDayWithThreeSnacks() {
  const localDate = NutritionDayDate(year: 2026, month: 6, day: 26);

  return NutritionDayRecord(
    localDate: localDate,
    meals: [
      _snackMeal(
        id: 'meal-snack-1',
        startedAt: DateTime(2026, 6, 26, 10),
        entryName: 'Apple',
      ),
      _snackMeal(
        id: 'meal-snack-2',
        startedAt: DateTime(2026, 6, 26, 15),
        entryName: 'Yogurt',
      ),
      _snackMeal(
        id: 'meal-snack-3',
        startedAt: DateTime(2026, 6, 26, 21),
        entryName: 'Toast',
      ),
    ],
  );
}

NutritionDayRecord _nutritionDayWithFoodEntryRows() {
  const localDate = NutritionDayDate(year: 2026, month: 6, day: 26);

  return NutritionDayRecord(
    localDate: localDate,
    meals: [
      NutritionDayMealRecord(
        meal: MealRecord(
          id: 'meal-breakfast',
          mealType: 'Breakfast',
          startedAt: DateTime(2026, 6, 26, 8),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
          updatedAt: DateTime.utc(2026, 6, 26, 8),
        ),
        entries: [
          FoodEntryRecord(
            id: 'entry-apple',
            mealId: 'meal-breakfast',
            kind: FoodEntryKind.food,
            position: 0,
            name: 'Apple',
            nutrients: NutrientVector.energyAndMacros(
              energy: NutrientAmount.complete(
                value: 52,
                entered: '52',
                unit: NutrientUnit.kilocalorie,
              ),
              protein: NutrientAmount.complete(
                value: 0.3,
                entered: '0.3',
                unit: NutrientUnit.gram,
              ),
              carbohydrate: NutrientAmount.complete(
                value: 14,
                entered: '14',
                unit: NutrientUnit.gram,
              ),
              fat: NutrientAmount.complete(
                value: 0.2,
                entered: '0.2',
                unit: NutrientUnit.gram,
              ),
            ),
            foodId: 'food-apple',
            portion: Portion(
              value: 125,
              entered: '125',
              unit: PortionUnit.gram,
            ),
            foodSource: FoodSource.user,
            isLiquid: false,
            updatedAt: DateTime.utc(2026, 6, 26, 8),
          ),
          FoodEntryRecord(
            id: 'entry-quick-calories',
            mealId: 'meal-breakfast',
            kind: FoodEntryKind.quickEntry,
            position: 1,
            name: 'Quick calories',
            nutrients: NutrientVector.energyAndMacros(
              energy: NutrientAmount.complete(
                value: 90,
                entered: '90',
                unit: NutrientUnit.kilocalorie,
              ),
              protein: NutrientAmount.complete(
                value: 0,
                entered: '0',
                unit: NutrientUnit.gram,
              ),
              carbohydrate: NutrientAmount.complete(
                value: 20,
                entered: '20',
                unit: NutrientUnit.gram,
              ),
              fat: NutrientAmount.complete(
                value: 1,
                entered: '1',
                unit: NutrientUnit.gram,
              ),
            ),
            updatedAt: DateTime.utc(2026, 6, 26, 8),
          ),
          FoodEntryRecord(
            id: 'entry-mystery-bar',
            mealId: 'meal-breakfast',
            kind: FoodEntryKind.food,
            position: 2,
            name: 'Mystery bar',
            nutrients: NutrientVector.energyAndMacros(
              energy: NutrientAmount.unknown(NutrientUnit.kilocalorie),
              protein: NutrientAmount.complete(
                value: 10,
                entered: '10',
                unit: NutrientUnit.gram,
              ),
              carbohydrate: NutrientAmount.complete(
                value: 20,
                entered: '20',
                unit: NutrientUnit.gram,
              ),
              fat: NutrientAmount.complete(
                value: 6,
                entered: '6',
                unit: NutrientUnit.gram,
              ),
            ),
            foodId: 'food-mystery-bar',
            portion: Portion(
              value: 50,
              entered: '50',
              unit: PortionUnit.gram,
            ),
            foodSource: FoodSource.user,
            isLiquid: false,
            updatedAt: DateTime.utc(2026, 6, 26, 8),
          ),
        ],
      ),
    ],
  );
}

NutritionDayMealRecord _snackMeal({
  required String id,
  required DateTime startedAt,
  required String entryName,
}) {
  const localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
  return NutritionDayMealRecord(
    meal: MealRecord(
      id: id,
      mealType: 'Snack',
      startedAt: startedAt,
      timezone: 'Australia/Brisbane',
      localDate: localDate,
      updatedAt: startedAt,
    ),
    entries: [
      FoodEntryRecord(
        id: 'entry-$id',
        mealId: id,
        kind: FoodEntryKind.quickEntry,
        position: 0,
        name: entryName,
        nutrients: NutrientVector.energyAndMacros(
          energy: NutrientAmount.complete(
            value: 100,
            entered: '100',
            unit: NutrientUnit.kilocalorie,
          ),
          protein: NutrientAmount.complete(
            value: 1,
            entered: '1',
            unit: NutrientUnit.gram,
          ),
          carbohydrate: NutrientAmount.complete(
            value: 20,
            entered: '20',
            unit: NutrientUnit.gram,
          ),
          fat: NutrientAmount.complete(
            value: 2,
            entered: '2',
            unit: NutrientUnit.gram,
          ),
        ),
        updatedAt: startedAt,
      ),
    ],
  );
}

NutritionDayRecord _nutritionDayWithImportedEntry() {
  const localDate = NutritionDayDate(year: 2026, month: 6, day: 26);

  return NutritionDayRecord(
    localDate: localDate,
    meals: [
      NutritionDayMealRecord(
        meal: MealRecord(
          id: 'meal-breakfast',
          mealType: 'Breakfast',
          startedAt: DateTime(2026, 6, 26, 8),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
          updatedAt: DateTime.utc(2026, 6, 26, 8),
        ),
        entries: [
          FoodEntryRecord(
            id: 'entry-imported',
            mealId: 'meal-breakfast',
            kind: FoodEntryKind.food,
            position: 0,
            name: 'Imported oats',
            nutrients: NutrientVector.energyAndMacros(
              energy: NutrientAmount.complete(
                value: 150,
                entered: '150',
                unit: NutrientUnit.kilocalorie,
              ),
              protein: NutrientAmount.complete(
                value: 5,
                entered: '5',
                unit: NutrientUnit.gram,
              ),
              carbohydrate: NutrientAmount.complete(
                value: 27,
                entered: '27',
                unit: NutrientUnit.gram,
              ),
              fat: NutrientAmount.complete(
                value: 3,
                entered: '3',
                unit: NutrientUnit.gram,
              ),
            ),
            portion: Portion(
              value: 40,
              entered: '40',
              unit: PortionUnit.gram,
            ),
            // Generic Imported origin with the exact provider string preserved.
            foodSource: FoodSource.imported,
            isLiquid: false,
            importSource: 'acme-diet-tracker',
            importExternalId: 'row-1',
            importProvider: 'Acme Diet Tracker',
            reviewFlags: const <NutritionReviewFlag>[
              NutritionReviewFlag(
                rule: 'portionImprobable',
                message: 'Portion is unusually large.',
              ),
            ],
            updatedAt: DateTime.utc(2026, 6, 26, 8),
          ),
        ],
      ),
    ],
  );
}

List<MealTypeRecord> _mealTypes() {
  return <MealTypeRecord>[
    MealTypeRecord(
      id: 'meal-type-breakfast',
      name: 'Breakfast',
      sortOrder: 0,
      updatedAt: DateTime.utc(2026, 6, 26),
    ),
    MealTypeRecord(
      id: 'meal-type-lunch',
      name: 'Lunch',
      sortOrder: 1,
      updatedAt: DateTime.utc(2026, 6, 26),
    ),
    MealTypeRecord(
      id: 'meal-type-dinner',
      name: 'Dinner',
      sortOrder: 2,
      updatedAt: DateTime.utc(2026, 6, 26),
    ),
    MealTypeRecord(
      id: 'meal-type-snack',
      name: 'Snack',
      sortOrder: 3,
      updatedAt: DateTime.utc(2026, 6, 26),
    ),
  ];
}

FoodPickerItem _pickerFood() {
  return FoodPickerItem(
    id: 'usda-chicken',
    name: 'Chicken breast',
    filter: AddFoodPickerFilter.recent,
    foodSource: FoodSource.usda,
    nutrientsPer100: NutrientVector.energyAndMacros(
      energy: NutrientAmount.complete(
        value: 165,
        entered: '165',
        unit: NutrientUnit.kilocalorie,
      ),
      protein: NutrientAmount.complete(
        value: 31,
        entered: '31',
        unit: NutrientUnit.gram,
      ),
      carbohydrate: NutrientAmount.complete(
        value: 0,
        entered: '0',
        unit: NutrientUnit.gram,
      ),
      fat: NutrientAmount.complete(
        value: 3.6,
        entered: '3.6',
        unit: NutrientUnit.gram,
      ),
    ),
    isLiquid: false,
    servingLabel: 'piece',
    servingSize: 86,
    lastPortion: Portion(
      value: 1.5,
      entered: '1.5',
      unit: PortionUnit.serving,
    ),
  );
}

FoodPickerItem _openFoodFactsBar() {
  return FoodPickerItem(
    id: '3017620422003',
    name: 'Hazelnut cocoa spread',
    filter: AddFoodPickerFilter.openFoodFacts,
    foodSource: FoodSource.openFoodFacts,
    nutrientsPer100: NutrientVector.energyAndMacros(
      energy: NutrientAmount.complete(
        value: 539,
        entered: '539',
        unit: NutrientUnit.kilocalorie,
      ),
      protein: NutrientAmount.complete(
        value: 6.3,
        entered: '6.3',
        unit: NutrientUnit.gram,
      ),
      carbohydrate: NutrientAmount.complete(
        value: 56.3,
        entered: '56.3',
        unit: NutrientUnit.gram,
      ),
      fat: NutrientAmount.complete(
        value: 30.9,
        entered: '30.9',
        unit: NutrientUnit.gram,
      ),
    ),
    isLiquid: false,
    servingLabel: 'serving',
    servingSize: 15,
    packageSize: 400,
  );
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 20,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Could not find $finder.');
}
