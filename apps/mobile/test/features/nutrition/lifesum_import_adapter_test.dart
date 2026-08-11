import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/features/nutrition/import/cronometer_csv_import_adapter.dart'
    show NutritionImportFormatException;
import 'package:perennia/features/nutrition/import/lifesum_import_adapter.dart';
import 'package:perennia/features/nutrition/import/nutrition_import.dart';

void main() {
  group('LifesumImportAdapter', () {
    late LifesumImportAdapter adapter;

    setUp(() {
      adapter = const LifesumImportAdapter();
    });

    test('declares the Lifesum provider, which resolves to its Food Source', () {
      expect(adapter.provider, 'Lifesum');
      final resolution = resolveImportedFoodSource(adapter.provider);
      expect(resolution.foodSource, FoodSource.lifesum);
      expect(resolution.importSource, 'lifesum');
      expect(resolution.preservedProvider, isNull);
    });

    test('is a NutritionImportAdapter', () {
      expect(adapter, isA<NutritionImportAdapter>());
    });

    // Lifesum CSV: DD/MM/YYYY dates, explicit amount + unit, absolute amounts.
    const csv = '''
Date,Meal,Food,Amount,Unit,Calories (kcal),Carbs (g),Protein (g),Fat (g)
01/06/2026,Breakfast,Oats,100,g,389,66.3,16.9,6.9
01/06/2026,Lunch,Chicken Breast,200,g,330,0,62,7.2
''';

    // Lifesum JSON of the SAME two rows, to assert format-invariant landing.
    const json = '''
{
  "food_items": [
    {"date":"2026-06-01","meal":"breakfast","name":"Oats","amount":100,"unit":"g",
     "nutrients":{"calories (kcal)":389,"carbs (g)":66.3,"protein (g)":16.9,"fat (g)":6.9}},
    {"date":"2026-06-01","meal":"lunch","name":"Chicken Breast","amount":200,"unit":"g",
     "nutrients":{"calories (kcal)":330,"carbs (g)":0,"protein (g)":62,"fat (g)":7.2}}
  ]
}
''';

    test('parses the CSV export into Meals grouped by meal', () {
      final batch = adapter.parse(csv);
      expect(batch.meals, hasLength(2));
      expect(batch.meals.first.mealType, 'Breakfast');
      expect(batch.meals.first.entries.single.name, 'Oats');
    });

    test('CSV uses DD/MM/YYYY (European) date order', () {
      final meal = adapter.parse(csv).meals.first;
      expect(meal.localDate, const NutritionDayDate(year: 2026, month: 6, day: 1));
    });

    test('normalises absolute amounts to a self-describing per-100 vector', () {
      final oats = adapter.parse(csv).meals.first.entries.single;
      expect(oats.portion.unit, PortionUnit.gram);
      expect(oats.portion.value, closeTo(100, 0.001));
      expect(oats.nutrientsPer100[NutrientId.energy].value, closeTo(389, 0.001));

      final chicken = adapter.parse(csv).meals[1].entries.single;
      // 200 g serving, protein 62 g -> 31 per 100.
      expect(
          chicken.nutrientsPer100[NutrientId.protein].value, closeTo(31, 0.001));
    });

    test('an unreported nutrient is unknown, never zero (0 != unknown)', () {
      final oats = adapter.parse(csv).meals.first.entries.single;
      // No sodium/calcium column -> unknown.
      expect(oats.nutrientsPer100[NutrientId.sodium].isComplete, isFalse);
      expect(oats.nutrientsPer100[NutrientId.calcium].isComplete, isFalse);
    });

    test('a genuine zero is complete, not unknown', () {
      final chicken = adapter.parse(csv).meals[1].entries.single;
      final carbs = chicken.nutrientsPer100[NutrientId.carbohydrate];
      expect(carbs.isComplete, isTrue);
      expect(carbs.value, 0);
    });

    test(
        'the JSON path lands the SAME canonical shape as the CSV path '
        '(format-invariant)', () {
      final fromCsv = adapter.parse(csv);
      final fromJson = adapter.parse(json);

      expect(fromJson.meals.map((m) => m.mealType).toList(),
          fromCsv.meals.map((m) => m.mealType).toList());

      final csvOats = fromCsv.meals.first.entries.single;
      final jsonOats = fromJson.meals.first.entries.single;
      expect(jsonOats.name, csvOats.name);
      expect(jsonOats.nutrientsPer100[NutrientId.energy].value,
          closeTo(csvOats.nutrientsPer100[NutrientId.energy].value!, 0.001));
      expect(jsonOats.nutrientsPer100[NutrientId.protein].value,
          closeTo(csvOats.nutrientsPer100[NutrientId.protein].value!, 0.001));
      // Same unknown-vs-known classification regardless of format.
      expect(jsonOats.nutrientsPer100[NutrientId.sodium].isComplete,
          csvOats.nutrientsPer100[NutrientId.sodium].isComplete);
    });

    test('treats a millilitre unit as a liquid portion', () {
      const liquidCsv = '''
Date,Meal,Food,Amount,Unit,Calories (kcal),Protein (g)
01/06/2026,Breakfast,Milk,250,ml,160,8.4
''';
      final entry = adapter.parse(liquidCsv).meals.single.entries.single;
      expect(entry.isLiquid, isTrue);
      expect(entry.portion.unit, PortionUnit.milliliter);
    });

    test('throws on a CSV missing required columns', () {
      expect(
        () => adapter.parse('Foo,Bar\n1,2\n'),
        throwsA(isA<NutritionImportFormatException>()),
      );
    });

    test('throws on invalid JSON', () {
      expect(
        () => adapter.parse('{ not valid'),
        throwsA(isA<NutritionImportFormatException>()),
      );
    });

    test('returns an empty batch for empty content', () {
      expect(adapter.parse('').isEmpty, isTrue);
    });
  });
}
