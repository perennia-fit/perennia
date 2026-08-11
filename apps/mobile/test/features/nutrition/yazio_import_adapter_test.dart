import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/features/nutrition/import/cronometer_csv_import_adapter.dart'
    show NutritionImportFormatException;
import 'package:perennia/features/nutrition/import/nutrition_import.dart';
import 'package:perennia/features/nutrition/import/yazio_import_adapter.dart';

void main() {
  group('YazioImportAdapter', () {
    late YazioImportAdapter adapter;

    setUp(() {
      adapter = const YazioImportAdapter();
    });

    test('declares the Yazio provider, which resolves to its Food Source', () {
      expect(adapter.provider, 'Yazio');
      final resolution = resolveImportedFoodSource(adapter.provider);
      expect(resolution.foodSource, FoodSource.yazio);
      expect(resolution.importSource, 'yazio');
      expect(resolution.preservedProvider, isNull);
    });

    test('is a NutritionImportAdapter', () {
      expect(adapter, isA<NutritionImportAdapter>());
    });

    // A 100 g Oats serving: Yazio reports energy in kJ (389 kcal -> 1627.6 kJ).
    const json = '''
{
  "consumed_items": [
    {
      "id": "yz-1",
      "date": "2026-06-01T08:00:00Z",
      "daytime": "breakfast",
      "name": "Oats",
      "amount": 100,
      "nutrients": {
        "energy.energy": 1627.6,
        "nutrient.protein": 16.9,
        "nutrient.carb": 66.3,
        "nutrient.fat": 6.9
      }
    },
    {
      "id": "yz-2",
      "date": "2026-06-01T13:00:00Z",
      "daytime": "lunch",
      "name": "Chicken Breast",
      "amount": 200,
      "nutrients": {
        "energy.energy": 1380.7,
        "nutrient.protein": 62,
        "nutrient.carb": 0,
        "nutrient.fat": 7.2
      }
    }
  ]
}
''';

    test('parses the JSON export into Meals grouped by daytime', () {
      final batch = adapter.parse(json);
      expect(batch.meals, hasLength(2));
      expect(batch.meals.first.mealType, 'Breakfast');
      expect(batch.meals.first.entries.single.name, 'Oats');
      expect(batch.meals[1].mealType, 'Lunch');
    });

    test('normalises kilojoule energy into per-100 kcal', () {
      final oats = adapter.parse(json).meals.first.entries.single;
      // 1627.6 kJ / 4.184 = 389 kcal for the 100 g serving -> 389 per 100.
      expect(oats.nutrientsPer100[NutrientId.energy].isComplete, isTrue);
      expect(oats.nutrientsPer100[NutrientId.energy].value, closeTo(389, 0.5));
      expect(oats.portion.unit, PortionUnit.gram);
      expect(oats.portion.value, closeTo(100, 0.001));
    });

    test('normalises a non-100 amount to a per-100 vector', () {
      // Chicken: 200 g serving, protein 62 g -> 31 g per 100.
      final chicken = adapter.parse(json).meals[1].entries.single;
      expect(
          chicken.nutrientsPer100[NutrientId.protein].value, closeTo(31, 0.001));
    });

    test('an unreported nutrient is unknown, never zero (0 != unknown)', () {
      final oats = adapter.parse(json).meals.first.entries.single;
      // No sodium/calcium key reported -> unknown.
      expect(oats.nutrientsPer100[NutrientId.sodium].isComplete, isFalse);
      expect(oats.nutrientsPer100[NutrientId.calcium].isComplete, isFalse);
    });

    test('a genuine zero is complete, not unknown', () {
      final chicken = adapter.parse(json).meals[1].entries.single;
      final carbs = chicken.nutrientsPer100[NutrientId.carbohydrate];
      expect(carbs.isComplete, isTrue);
      expect(carbs.value, 0);
    });

    test('uses the provider id as a stable externalId', () {
      final ids = adapter
          .parse(json)
          .meals
          .expand((m) => m.entries)
          .map((e) => e.externalId)
          .toList();
      expect(ids, containsAll(<String>['yz-1', 'yz-2']));
    });

    test('accepts a top-level JSON array too', () {
      const arrayJson = '''
[
  {"id":"a","date":"2026-06-02","daytime":"snack","name":"Apple","amount":150,
   "nutrients":{"energy.energy":326,"nutrient.carb":21}}
]
''';
      final batch = adapter.parse(arrayJson);
      expect(batch.meals.single.mealType, 'Snack');
      expect(batch.meals.single.entries.single.name, 'Apple');
    });

    test('throws on invalid JSON', () {
      expect(
        () => adapter.parse('not json at all'),
        throwsA(isA<NutritionImportFormatException>()),
      );
    });

    test('throws when the shape is not a consumed-items list', () {
      expect(
        () => adapter.parse('{"unexpected": true}'),
        throwsA(isA<NutritionImportFormatException>()),
      );
    });

    test('returns an empty batch for empty content', () {
      expect(adapter.parse('').isEmpty, isTrue);
    });
  });
}
