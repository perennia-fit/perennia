import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/domain/nutrition/nutrition_import.dart';

void main() {
  test('Nutrition import read models expose immutable snapshots', () {
    const localDate = NutritionDayDate(year: 2026, month: 7, day: 9);
    final entry = NutritionImportFoodEntry(
      externalId: 'external-1',
      name: 'Imported oats',
      nutrientsPer100:
          NutrientVector.full(const <NutrientId, NutrientAmount>{}),
      isLiquid: false,
      portion: Portion(value: 100, entered: '100', unit: PortionUnit.gram),
    );

    final entries = <NutritionImportFoodEntry>[entry];
    final meal = NutritionImportMeal(
      mealType: 'Breakfast',
      startedAt: DateTime.utc(2026, 7, 9, 8),
      localDate: localDate,
      entries: entries,
    );
    final meals = <NutritionImportMeal>[meal];
    final batch = NutritionImportBatch(meals: meals);
    final mealIds = <String>['meal-1'];
    final foodEntryIds = <String>['entry-1'];
    final result = NutritionImportResult(
      batchId: 'batch-1',
      mealIds: mealIds,
      foodEntryIds: foodEntryIds,
      importedCount: 1,
      updatedCount: 0,
      skippedTombstoned: 0,
      rejectedCount: 0,
    );

    entries.clear();
    meals.clear();
    mealIds.clear();
    foodEntryIds.clear();

    expect(meal.entries, <NutritionImportFoodEntry>[entry]);
    expect(batch.meals, <NutritionImportMeal>[meal]);
    expect(result.mealIds, <String>['meal-1']);
    expect(result.foodEntryIds, <String>['entry-1']);
    expect(() => meal.entries.clear(), throwsUnsupportedError);
    expect(() => batch.meals.clear(), throwsUnsupportedError);
    expect(() => result.mealIds.clear(), throwsUnsupportedError);
    expect(() => result.foodEntryIds.clear(), throwsUnsupportedError);
  });
}
