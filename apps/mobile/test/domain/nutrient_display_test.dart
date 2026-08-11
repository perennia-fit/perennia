import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';

void main() {
  test('nutrient registry is closed and every nutrient has one display tier',
      () {
    expect(
      NutrientId.values,
      <NutrientId>[
        NutrientId.energy,
        NutrientId.protein,
        NutrientId.carbohydrate,
        NutrientId.sugar,
        NutrientId.fat,
        NutrientId.saturatedFat,
        NutrientId.monounsaturatedFat,
        NutrientId.polyunsaturatedFat,
        NutrientId.fiber,
        NutrientId.sodium,
        NutrientId.cholesterol,
        NutrientId.vitaminA,
        NutrientId.vitaminC,
        NutrientId.vitaminD,
        NutrientId.vitaminE,
        NutrientId.vitaminK,
        NutrientId.thiamin,
        NutrientId.riboflavin,
        NutrientId.niacin,
        NutrientId.vitaminB6,
        NutrientId.folate,
        NutrientId.vitaminB12,
        NutrientId.calcium,
        NutrientId.iron,
        NutrientId.magnesium,
        NutrientId.phosphorus,
        NutrientId.potassium,
        NutrientId.zinc,
        NutrientId.copper,
        NutrientId.manganese,
        NutrientId.selenium,
        NutrientId.caffeine,
        NutrientId.water,
      ],
    );
    expect(
      () => NutrientId.byStorageKey('trans_fat'),
      throwsArgumentError,
    );

    expect(
      nutrientIdsForDisplayTier(NutrientDisplayTier.core),
      <NutrientId>[
        NutrientId.energy,
        NutrientId.protein,
        NutrientId.carbohydrate,
        NutrientId.fat,
      ],
    );
    expect(
      nutrientIdsForDisplayTier(NutrientDisplayTier.common),
      <NutrientId>[
        NutrientId.saturatedFat,
        NutrientId.sugar,
        NutrientId.fiber,
        NutrientId.sodium,
      ],
    );

    final tiered = <NutrientId>{
      for (final tier in NutrientDisplayTier.values)
        ...nutrientIdsForDisplayTier(tier),
    };
    expect(tiered, NutrientId.values.toSet());
    expect(tiered.length, NutrientId.values.length);
    expect(
        nutrientDisplayTier(NutrientId.vitaminB6), NutrientDisplayTier.detail);
    expect(nutrientDisplayLabel(NutrientId.vitaminB6), 'Vitamin B6');
  });

  test('nutrient vectors preserve complete zero distinctly from unknown', () {
    final vector = NutrientVector.full(<NutrientId, NutrientAmount>{
      NutrientId.fiber: NutrientAmount.complete(
        value: 0,
        entered: '0',
        unit: NutrientUnit.gram,
      ),
    });
    final reparsed = NutrientVector.fromJson(vector.toJson());

    expect(reparsed[NutrientId.fiber].status, NutrientValueStatus.complete);
    expect(reparsed[NutrientId.fiber].value, 0);
    expect(reparsed[NutrientId.fiber].entered, '0');
    expect(
      reparsed[NutrientId.caffeine].status,
      NutrientValueStatus.unknown,
    );
    expect(reparsed[NutrientId.caffeine].value, isNull);
  });

  test('food name search uses shared partial multi-term matching', () {
    expect(foodNameMatchesQuery('Chicken breast', 'chick brea'), isTrue);
    expect(foodNameMatchesQuery('Chicken breast', 'BREA CHICK'), isTrue);
    expect(foodNameMatchesQuery('Chickpeas, boiled', 'chick boil'), isTrue);
    expect(foodNameMatchesQuery('Greek yogurt', 'chick'), isFalse);
    expect(foodNameMatchesQuery('Greek yogurt', '   '), isTrue);
  });

  test('nutrition numbers share one compact display formatter', () {
    expect(formatNutritionNumber(165), '165');
    expect(formatNutritionNumber(31.02), '31');
    expect(formatNutritionNumber(3.57), '3.6');
    expect(formatNutritionNumber(0), '0');
  });
}
