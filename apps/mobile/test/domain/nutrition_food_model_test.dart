import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';

void main() {
  test('Nutrition food models expose immutable snapshots', () {
    final ingredient = RecipeIngredient(
      foodId: 'food-1',
      name: 'Oats',
      foodSource: FoodSource.user,
      nutrientsPer100:
          NutrientVector.full(const <NutrientId, NutrientAmount>{}),
      isLiquid: false,
      portion: Portion(value: 100, entered: '100', unit: PortionUnit.gram),
    );
    const flag = NutritionReviewFlag(
      rule: 'portionImprobable',
      message: 'Portion is unusually large.',
    );

    final recipeIngredients = <RecipeIngredient>[ingredient];
    final draft = RecipeDraft(
      name: 'Protein oats',
      ingredients: recipeIngredients,
      servingCount: 2,
    );
    final recordIngredients = <RecipeIngredient>[ingredient];
    final food = UserFoodRecord(
      id: 'recipe-1',
      name: 'Protein oats',
      foodSource: FoodSource.user,
      nutrientsPer100:
          NutrientVector.full(const <NutrientId, NutrientAmount>{}),
      isLiquid: false,
      updatedAt: DateTime.utc(2026, 7, 9),
      recipeIngredients: recordIngredients,
      recipeServingCount: 2,
    );
    final snapshotFlags = <NutritionReviewFlag>[flag];
    final snapshot = FoodEntrySnapshotDraft(
      mealId: 'meal-1',
      foodId: null,
      name: 'Imported oats',
      foodSource: FoodSource.imported,
      nutrientsPer100:
          NutrientVector.full(const <NutrientId, NutrientAmount>{}),
      isLiquid: false,
      portion: Portion(value: 100, entered: '100', unit: PortionUnit.gram),
      reviewFlags: snapshotFlags,
    );
    final entryFlags = <NutritionReviewFlag>[flag];
    final entry = FoodEntryRecord(
      id: 'entry-1',
      mealId: 'meal-1',
      kind: FoodEntryKind.quickEntry,
      position: 0,
      name: 'Quick oats',
      nutrients: NutrientVector.full(const <NutrientId, NutrientAmount>{}),
      updatedAt: DateTime.utc(2026, 7, 9),
      reviewFlags: entryFlags,
    );

    recipeIngredients.clear();
    recordIngredients.clear();
    snapshotFlags.clear();
    entryFlags.clear();

    expect(draft.ingredients, <RecipeIngredient>[ingredient]);
    expect(food.recipeIngredients, <RecipeIngredient>[ingredient]);
    expect(snapshot.reviewFlags, <NutritionReviewFlag>[flag]);
    expect(entry.reviewFlags, <NutritionReviewFlag>[flag]);
    expect(() => draft.ingredients.clear(), throwsUnsupportedError);
    expect(() => food.recipeIngredients.clear(), throwsUnsupportedError);
    expect(() => snapshot.reviewFlags.clear(), throwsUnsupportedError);
    expect(() => entry.reviewFlags.clear(), throwsUnsupportedError);
  });
}
