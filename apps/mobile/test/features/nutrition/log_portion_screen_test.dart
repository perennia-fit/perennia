import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/nutrition/repositories/add_food_repository.dart';
import 'package:perennia/features/nutrition/widgets/log_portion_screen.dart';
import 'package:perennia/features/nutrition/widgets/nutrition_attribution.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  testWidgets('gates Portion units and updates the unknown-aware readout live',
      (
    tester,
  ) async {
    await _pumpLogPortion(tester, food: _solidFood());

    expect(
      find.byKey(LogPortionScreen.unitChipKey(PortionUnit.gram)),
      findsOneWidget,
    );
    expect(
      find.byKey(LogPortionScreen.unitChipKey(PortionUnit.ounce)),
      findsOneWidget,
    );
    expect(
      find.byKey(LogPortionScreen.unitChipKey(PortionUnit.serving)),
      findsOneWidget,
    );
    expect(
      find.byKey(LogPortionScreen.unitChipKey(PortionUnit.milliliter)),
      findsNothing,
    );
    expect(
      find.byKey(LogPortionScreen.unitChipKey(PortionUnit.fluidOunce)),
      findsNothing,
    );
    expect(
      find.byKey(LogPortionScreen.unitChipKey(PortionUnit.package)),
      findsNothing,
    );
    expect(_readoutValue(tester, NutrientId.energy), '200 kcal');
    expect(_readoutValue(tester, NutrientId.protein), _unknownLabel);

    await tester.tap(
      find.byKey(LogPortionScreen.unitChipKey(PortionUnit.serving)),
    );
    await tester.pump();

    expect(_amountText(tester), '1');
    expect(_readoutValue(tester, NutrientId.energy), '340 kcal');
    expect(_readoutValue(tester, NutrientId.protein), _unknownLabel);

    await tester.tap(find.byKey(LogPortionScreen.incrementButtonKey));
    await tester.pump();

    expect(_amountText(tester), '1.25');
    expect(_readoutValue(tester, NutrientId.energy), '425 kcal');
  });

  testWidgets('gates liquid Foods to liquid units and package when defined', (
    tester,
  ) async {
    await _pumpLogPortion(tester, food: _liquidFood());

    expect(
      find.byKey(LogPortionScreen.unitChipKey(PortionUnit.milliliter)),
      findsOneWidget,
    );
    expect(
      find.byKey(LogPortionScreen.unitChipKey(PortionUnit.fluidOunce)),
      findsOneWidget,
    );
    expect(
      find.byKey(LogPortionScreen.unitChipKey(PortionUnit.serving)),
      findsOneWidget,
    );
    expect(
      find.byKey(LogPortionScreen.unitChipKey(PortionUnit.package)),
      findsOneWidget,
    );
    expect(
      find.byKey(LogPortionScreen.unitChipKey(PortionUnit.gram)),
      findsNothing,
    );
    expect(
      find.byKey(LogPortionScreen.unitChipKey(PortionUnit.ounce)),
      findsNothing,
    );
  });

  testWidgets('prefills last Portion and resolves the readout before Save', (
    tester,
  ) async {
    await _pumpLogPortion(
      tester,
      food: _solidFood(
        lastPortion: Portion(
          value: 1.5,
          entered: '1.5',
          unit: PortionUnit.serving,
        ),
      ),
    );

    expect(_amountText(tester), '1.5');
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(LogPortionScreen.unitChipKey(PortionUnit.serving)),
          )
          .selected,
      isTrue,
    );
    expect(_readoutValue(tester, NutrientId.energy), '510 kcal');
  });

  testWidgets('falls back when the last Portion unit is no longer available', (
    tester,
  ) async {
    await _pumpLogPortion(
      tester,
      food: _solidFood(
        servingLabel: null,
        servingSize: null,
        lastPortion: Portion(
          value: 2,
          entered: '2',
          unit: PortionUnit.serving,
        ),
      ),
    );

    expect(_amountText(tester), '100');
    expect(
      find.byKey(LogPortionScreen.unitChipKey(PortionUnit.serving)),
      findsNothing,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(LogPortionScreen.unitChipKey(PortionUnit.gram)),
          )
          .selected,
      isTrue,
    );
    expect(_readoutValue(tester, NutrientId.energy), '200 kcal');
  });

  testWidgets('Save hands off a self-describing Food Entry snapshot', (
    tester,
  ) async {
    final saved = <FoodEntrySnapshotDraft>[];

    await _pumpLogPortion(
      tester,
      food: _solidFood(),
      onSave: (draft) async {
        saved.add(draft);
        return LogFoodEntryResult(
          batchId: 'batch-1',
          mealId: draft.mealId,
          foodEntryId: 'entry-1',
        );
      },
    );

    await tester.enterText(find.byKey(LogPortionScreen.amountFieldKey), '150');
    await tester.pump();
    await tester.tap(find.byKey(LogPortionScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(saved, hasLength(1));
    final draft = saved.single;
    expect(draft.mealId, 'meal-snack');
    expect(draft.foodId, 'usda-yogurt');
    expect(draft.name, 'Greek yogurt');
    expect(draft.foodSource, FoodSource.usda);
    expect(draft.nutrientsPer100[NutrientId.energy].value, 200);
    expect(draft.nutrientsPer100[NutrientId.protein].status,
        NutrientValueStatus.unknown);
    expect(draft.isLiquid, isFalse);
    expect(draft.servingLabel, 'cup');
    expect(draft.servingSize, 170);
    expect(draft.packageSize, isNull);
    expect(draft.portion.value, 150);
    expect(draft.portion.entered, '150');
    expect(draft.portion.unit, PortionUnit.gram);
  });

  testWidgets('Open Food Facts Food shows attribution in Log Portion', (
    tester,
  ) async {
    await _pumpLogPortion(tester, food: _openFoodFactsFood());

    expect(find.text('Hazelnut cocoa spread'), findsOneWidget);
    expect(
      find.byKey(
        NutritionAttributionKeys.foodSourceBadge(FoodSource.openFoodFacts),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(NutritionAttributionKeys.openFoodFactsNotice),
      findsOneWidget,
    );
    expect(
      find.byKey(NutritionAttributionKeys.openFoodFactsSourceLink),
      findsOneWidget,
    );
    expect(
      find.byKey(NutritionAttributionKeys.openFoodFactsOdblLink),
      findsOneWidget,
    );
    expect(find.textContaining('ODbL'), findsAtLeastNWidgets(1));
  });

  testWidgets(
      'hard-reject keeps Log Portion open, shows validation, and saves nothing',
      (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repositories = TrainingRepositories(database);
    final mealId = await repositories.nutrition.createMeal(
      MealDraft(
        mealType: 'Snack',
        startedAt: DateTime.utc(2026, 6, 26, 15),
        timezone: 'Australia/Brisbane',
        localDate: const NutritionDayDate(year: 2026, month: 6, day: 26),
      ),
    );
    final meal = (await repositories.nutrition.getMealById(mealId))!;

    await _pumpLogPortion(
      tester,
      food: _solidFood(),
      meal: meal,
      onSave: (draft) {
        return repositories.nutrition.logFoodEntrySnapshot(entry: draft);
      },
    );

    await tester.enterText(find.byKey(LogPortionScreen.amountFieldKey), '6000');
    await tester.pump();
    await tester.tap(find.byKey(LogPortionScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(
      find.text('Energy must be no more than 10000 kcal per Food Entry.'),
      findsOneWidget,
    );
    expect(find.text('Greek yogurt'), findsOneWidget);
    expect(
      await repositories.nutrition.listActiveEntriesForMeal(mealId),
      isEmpty,
    );
  });

  testWidgets('Log Portion meets accessibility guidelines in both themes', (
    tester,
  ) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();

      await _pumpLogPortion(tester, food: _solidFood(), theme: theme);

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'Open Food Facts badge and attribution meet accessibility guidelines',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();

      await _pumpLogPortion(
        tester,
        food: _openFoodFactsFood(),
        theme: theme,
      );

      expect(
        find.semantics.byLabel(RegExp(r'^Food Source: Open Food Facts')),
        findsOne,
      );
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

const _unknownLabel = '\u2014';

Future<void> _pumpLogPortion(
  WidgetTester tester, {
  ThemeData? theme,
  required FoodPickerItem food,
  MealRecord? meal,
  Future<LogFoodEntryResult> Function(FoodEntrySnapshotDraft draft)? onSave,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: Scaffold(
          body: SafeArea(
            child: LogPortionScreen(
              meal: meal ?? _meal(),
              food: food,
              onSave: onSave,
            ),
          ),
        ),
      ),
    ),
  );
}

String? _amountText(WidgetTester tester) {
  return tester
      .widget<TextField>(find.byKey(LogPortionScreen.amountFieldKey))
      .controller
      ?.text;
}

String? _readoutValue(WidgetTester tester, NutrientId id) {
  return tester
      .widget<Text>(find.byKey(LogPortionScreen.readoutValueKey(id)))
      .data;
}

MealRecord _meal() {
  return MealRecord(
    id: 'meal-snack',
    mealType: 'Snack',
    startedAt: DateTime.utc(2026, 6, 26, 15),
    timezone: 'Australia/Brisbane',
    localDate: const NutritionDayDate(year: 2026, month: 6, day: 26),
    updatedAt: DateTime.utc(2026, 6, 26, 15),
  );
}

FoodPickerItem _solidFood({
  String? servingLabel = 'cup',
  double? servingSize = 170,
  Portion? lastPortion,
}) {
  return FoodPickerItem(
    id: 'usda-yogurt',
    name: 'Greek yogurt',
    filter: AddFoodPickerFilter.usda,
    foodSource: FoodSource.usda,
    nutrientsPer100: _nutrients(
      energy: 200,
      protein: null,
      carbohydrate: 20,
      fat: 10,
    ),
    isLiquid: false,
    servingLabel: servingLabel,
    servingSize: servingSize,
    lastPortion: lastPortion,
  );
}

FoodPickerItem _liquidFood() {
  return FoodPickerItem(
    id: 'usda-milk',
    name: 'Milk, whole',
    filter: AddFoodPickerFilter.usda,
    foodSource: FoodSource.usda,
    nutrientsPer100: _nutrients(
      energy: 60,
      protein: 3,
      carbohydrate: 5,
      fat: 3,
    ),
    isLiquid: true,
    servingLabel: 'cup',
    servingSize: 244,
    packageSize: 3785.41,
  );
}

FoodPickerItem _openFoodFactsFood() {
  return FoodPickerItem(
    id: '3017620422003',
    name: 'Hazelnut cocoa spread',
    filter: AddFoodPickerFilter.openFoodFacts,
    foodSource: FoodSource.openFoodFacts,
    nutrientsPer100: _nutrients(
      energy: 539,
      protein: 6.3,
      carbohydrate: 56.3,
      fat: 30.9,
    ),
    isLiquid: false,
    servingLabel: 'serving',
    servingSize: 15,
    packageSize: 400,
  );
}

NutrientVector _nutrients({
  required double? energy,
  required double? protein,
  required double? carbohydrate,
  required double? fat,
}) {
  return NutrientVector.energyAndMacros(
    energy: _amount(NutrientId.energy, energy),
    protein: _amount(NutrientId.protein, protein),
    carbohydrate: _amount(NutrientId.carbohydrate, carbohydrate),
    fat: _amount(NutrientId.fat, fat),
  );
}

NutrientAmount _amount(NutrientId id, double? value) {
  if (value == null) {
    return NutrientAmount.unknown(id.defaultUnit);
  }
  return NutrientAmount.complete(
    value: value,
    entered: formatNutritionNumber(value),
    unit: id.defaultUnit,
  );
}
