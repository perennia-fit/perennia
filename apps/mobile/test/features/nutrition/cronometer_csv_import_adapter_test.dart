import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/features/nutrition/import/cronometer_csv_import_adapter.dart';
import 'package:perennia/features/nutrition/import/nutrition_import.dart';

void main() {
  group('CronometerCsvImportAdapter', () {
    late CronometerCsvImportAdapter adapter;

    setUp(() {
      adapter = const CronometerCsvImportAdapter();
    });

    test('declares the Cronometer provider, which resolves to its Food Source',
        () {
      expect(adapter.provider, 'Cronometer');
      final resolution = resolveImportedFoodSource(adapter.provider);
      expect(resolution.foodSource, FoodSource.cronometer);
      expect(resolution.importSource, 'cronometer');
      expect(resolution.preservedProvider, isNull);
    });

    test('maps rows into Meals grouped by the CSV meal grouping', () {
      const csv = '''
Day,Time,Group,Food Name,Amount,Energy (kcal),Protein (g),Carbs (g),Fat (g)
2026-06-01,08:00,Breakfast,Oats,100 g,389,16.9,66.3,6.9
2026-06-01,08:05,Breakfast,Banana,118 g,105,1.3,27,0.4
2026-06-01,13:00,Lunch,Chicken Breast,200 g,330,62,0,7.2
''';

      final batch = adapter.parse(csv);

      expect(batch.meals, hasLength(2));
      final breakfast = batch.meals.first;
      expect(breakfast.mealType, 'Breakfast');
      expect(breakfast.entries.map((e) => e.name),
          containsAllInOrder(<String>['Oats', 'Banana']));
      final lunch = batch.meals[1];
      expect(lunch.mealType, 'Lunch');
      expect(lunch.entries.single.name, 'Chicken Breast');
    });

    test('stores a self-describing per-100 nutrient snapshot', () {
      const csv = '''
Day,Time,Group,Food Name,Amount,Energy (kcal),Protein (g),Carbs (g),Fat (g)
2026-06-01,08:00,Breakfast,Oats,200 g,778,33.8,132.6,13.8
''';

      final entry = adapter.parse(csv).meals.single.entries.single;

      // The CSV reports the absolute amount for a 200 g serving; the snapshot
      // is normalized to per-100 so it is self-describing and scale-free.
      expect(entry.nutrientsPer100[NutrientId.energy].isComplete, isTrue);
      expect(entry.nutrientsPer100[NutrientId.energy].value, closeTo(389, 0.5));
      expect(
          entry.nutrientsPer100[NutrientId.protein].value, closeTo(16.9, 0.1));
      expect(entry.portion.unit, PortionUnit.gram);
      expect(entry.portion.value, closeTo(200, 0.001));
    });

    test('an unreported column is unknown, never zero (0 != unknown)', () {
      const csv = '''
Day,Time,Group,Food Name,Amount,Energy (kcal),Protein (g),Carbs (g),Fat (g),Calcium (mg),Iron (mg)
2026-06-01,08:00,Breakfast,Oats,100 g,389,16.9,66.3,6.9,,5.4
''';

      final entry = adapter.parse(csv).meals.single.entries.single;

      // Calcium column present but blank -> unknown.
      expect(entry.nutrientsPer100[NutrientId.calcium].isComplete, isFalse);
      // Iron reported -> complete.
      expect(entry.nutrientsPer100[NutrientId.iron].isComplete, isTrue);
      // Sodium column absent entirely -> unknown.
      expect(entry.nutrientsPer100[NutrientId.sodium].isComplete, isFalse);
    });

    test('a genuine zero is complete, not unknown', () {
      const csv = '''
Day,Time,Group,Food Name,Amount,Energy (kcal),Protein (g),Carbs (g),Fat (g)
2026-06-01,13:00,Lunch,Chicken,100 g,165,31,0,3.6
''';

      final entry = adapter.parse(csv).meals.single.entries.single;
      final carbs = entry.nutrientsPer100[NutrientId.carbohydrate];
      expect(carbs.isComplete, isTrue);
      expect(carbs.value, 0);
    });

    test('derives a stable externalId, distinct per row', () {
      const csv = '''
Day,Time,Group,Food Name,Amount,Energy (kcal),Protein (g),Carbs (g),Fat (g)
2026-06-01,08:00,Breakfast,Oats,100 g,389,16.9,66.3,6.9
2026-06-01,08:05,Breakfast,Banana,118 g,105,1.3,27,0.4
''';

      final entries = adapter.parse(csv).meals.single.entries;
      final ids = entries.map((e) => e.externalId).toSet();
      expect(ids, hasLength(2));
      expect(ids.every((id) => id.isNotEmpty), isTrue);

      // Re-parsing the same CSV yields the same externalIds (idempotency).
      final again = adapter.parse(csv).meals.single.entries;
      expect(again.map((e) => e.externalId).toList(),
          entries.map((e) => e.externalId).toList());
    });

    test('handles quoted fields containing commas', () {
      const csv = '''
Day,Time,Group,Food Name,Amount,Energy (kcal),Protein (g),Carbs (g),Fat (g)
2026-06-01,08:00,Breakfast,"Yogurt, plain",150 g,90,9,12,0.6
''';

      final entry = adapter.parse(csv).meals.single.entries.single;
      expect(entry.name, 'Yogurt, plain');
    });

    test('treats a fluid amount as a milliliter liquid portion', () {
      const csv = '''
Day,Time,Group,Food Name,Amount,Energy (kcal),Protein (g),Carbs (g),Fat (g)
2026-06-01,08:00,Breakfast,Milk,250 ml,160,8.4,12,8.5
''';

      final entry = adapter.parse(csv).meals.single.entries.single;
      expect(entry.isLiquid, isTrue);
      expect(entry.portion.unit, PortionUnit.milliliter);
      expect(entry.portion.value, closeTo(250, 0.001));
    });

    test('throws on an unrecognized header', () {
      const csv = '''
Foo,Bar,Baz
1,2,3
''';
      expect(
        () => adapter.parse(csv),
        throwsA(isA<NutritionImportFormatException>()),
      );
    });

    test('returns an empty batch for a header-only file', () {
      const csv = 'Day,Time,Group,Food Name,Amount,Energy (kcal)\n';
      final batch = adapter.parse(csv);
      expect(batch.isEmpty, isTrue);
      expect(batch.entryCount, 0);
    });

    test('is a NutritionImportAdapter', () {
      expect(adapter, isA<NutritionImportAdapter>());
    });
  });
}
