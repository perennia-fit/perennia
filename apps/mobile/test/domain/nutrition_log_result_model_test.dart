import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';

void main() {
  test('nutrition log results expose immutable warning snapshots', () {
    const warning = NutrientValidationIssue(
      field: 'nutrients.energy',
      nutrient: NutrientId.energy,
      rule: 'energy_high',
      message: 'Energy looks unusually high.',
      limit: 10000,
    );

    final quickWarnings = <NutrientValidationIssue>[warning];
    final foodWarnings = <NutrientValidationIssue>[warning];

    final quickResult = LogQuickEntryResult(
      batchId: 'batch-quick',
      mealId: 'meal-quick',
      foodEntryId: 'entry-quick',
      warnings: quickWarnings,
    );
    final foodResult = LogFoodEntryResult(
      batchId: 'batch-food',
      mealId: 'meal-food',
      foodEntryId: 'entry-food',
      warnings: foodWarnings,
    );

    quickWarnings.clear();
    foodWarnings.clear();

    expect(quickResult.warnings, <NutrientValidationIssue>[warning]);
    expect(foodResult.warnings, <NutrientValidationIssue>[warning]);

    expect(() => quickResult.warnings.clear(), throwsUnsupportedError);
    expect(() => foodResult.warnings.clear(), throwsUnsupportedError);
  });
}
