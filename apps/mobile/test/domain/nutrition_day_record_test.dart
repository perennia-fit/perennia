import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';

void main() {
  test('Nutrition Day read models expose immutable snapshots', () {
    const localDate = NutritionDayDate(year: 2026, month: 7, day: 9);
    final meal = MealRecord(
      id: 'meal-1',
      mealType: 'Breakfast',
      startedAt: DateTime.utc(2026, 7, 9, 8),
      timezone: 'UTC',
      localDate: localDate,
      updatedAt: DateTime.utc(2026, 7, 9, 8),
    );
    final entry = FoodEntryRecord(
      id: 'entry-1',
      mealId: meal.id,
      kind: FoodEntryKind.quickEntry,
      position: 0,
      name: 'Protein shake',
      nutrients: NutrientVector.energyAndMacros(
        energy: NutrientAmount.complete(
          value: 200,
          entered: '200',
          unit: NutrientUnit.kilocalorie,
        ),
        protein: NutrientAmount.complete(
          value: 30,
          entered: '30',
          unit: NutrientUnit.gram,
        ),
        carbohydrate: NutrientAmount.complete(
          value: 10,
          entered: '10',
          unit: NutrientUnit.gram,
        ),
        fat: NutrientAmount.complete(
          value: 4,
          entered: '4',
          unit: NutrientUnit.gram,
        ),
      ),
      updatedAt: DateTime.utc(2026, 7, 9, 8),
    );

    final entries = <FoodEntryRecord>[entry];
    final mealRecord = NutritionDayMealRecord(
      meal: meal,
      entries: entries,
    );
    final meals = <NutritionDayMealRecord>[mealRecord];
    final day = NutritionDayRecord(
      localDate: localDate,
      meals: meals,
    );
    entries.clear();
    meals.clear();

    expect(mealRecord.entries, <FoodEntryRecord>[entry]);
    expect(day.meals, <NutritionDayMealRecord>[mealRecord]);
    expect(day.totals[NutrientId.energy].value, 200);
    expect(() => mealRecord.entries.clear(), throwsUnsupportedError);
    expect(() => day.meals.clear(), throwsUnsupportedError);
  });
}
