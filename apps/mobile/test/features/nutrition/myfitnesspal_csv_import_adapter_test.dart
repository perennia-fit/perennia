import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/features/nutrition/import/cronometer_csv_import_adapter.dart'
    show NutritionImportFormatException;
import 'package:perennia/features/nutrition/import/myfitnesspal_csv_import_adapter.dart';
import 'package:perennia/features/nutrition/import/nutrition_import.dart';

void main() {
  group('MyFitnessPalCsvImportAdapter', () {
    late MyFitnessPalCsvImportAdapter adapter;

    setUp(() {
      adapter = const MyFitnessPalCsvImportAdapter();
    });

    test('declares the MyFitnessPal provider, which resolves to its Food Source',
        () {
      expect(adapter.provider, 'MyFitnessPal');
      final resolution = resolveImportedFoodSource(adapter.provider);
      expect(resolution.foodSource, FoodSource.myFitnessPal);
      expect(resolution.importSource, 'myfitnesspal');
      // Recognised provider: the enum names it, no preserved string.
      expect(resolution.preservedProvider, isNull);
    });

    test('is a NutritionImportAdapter', () {
      expect(adapter, isA<NutritionImportAdapter>());
    });

    test('maps rows into Meals grouped by the MyFitnessPal meal name', () {
      const csv = '''
Date,Meal,Food,Calories,Fat (g),Carbohydrates (g),Protein (g)
2026-06-01,Breakfast,Oats,389,6.9,66.3,16.9
2026-06-01,breakfast,Banana,105,0.4,27,1.3
2026-06-01,Lunch,Chicken Breast,330,7.2,0,62
''';

      final batch = adapter.parse(csv);

      // Mixed casing of "Breakfast"/"breakfast" collapses to one canonical meal.
      expect(batch.meals, hasLength(2));
      final breakfast = batch.meals.first;
      expect(breakfast.mealType, 'Breakfast');
      expect(breakfast.entries.map((e) => e.name),
          containsAllInOrder(<String>['Oats', 'Banana']));
      final lunch = batch.meals[1];
      expect(lunch.mealType, 'Lunch');
      expect(lunch.entries.single.name, 'Chicken Breast');
    });

    test(
        'snapshots the reported per-serving totals as a self-describing vector',
        () {
      const csv = '''
Date,Meal,Food,Calories,Fat (g),Carbohydrates (g),Protein (g)
2026-06-01,Breakfast,Oats,389,6.9,66.3,16.9
''';

      final entry = adapter.parse(csv).meals.single.entries.single;

      // MFP reports the already-totalled values; the snapshot lands them
      // verbatim via a 1-serving portion whose base quantity is 100.
      expect(entry.portion.unit, PortionUnit.serving);
      expect(entry.portion.value, 1);
      expect(entry.servingSize, 100);
      expect(entry.nutrientsPer100[NutrientId.energy].isComplete, isTrue);
      expect(entry.nutrientsPer100[NutrientId.energy].value, closeTo(389, 0.001));
      expect(
          entry.nutrientsPer100[NutrientId.protein].value, closeTo(16.9, 0.001));
    });

    test(
        'free-export micros land UNKNOWN, never zero (most columns absent)',
        () {
      // The free/typical export has macros + sodium only — no calcium, iron,
      // vitamins, etc. Those absent columns must be unknown, not zero.
      const csv = '''
Date,Meal,Food,Calories,Fat (g),Carbohydrates (g),Protein (g),Sodium (mg)
2026-06-01,Breakfast,Oats,389,6.9,66.3,16.9,2
''';

      final vector = adapter.parse(csv).meals.single.entries.single
          .nutrientsPer100;

      // Reported columns are complete.
      expect(vector[NutrientId.energy].isComplete, isTrue);
      expect(vector[NutrientId.sodium].isComplete, isTrue);
      // The vast majority of micros are simply absent -> unknown.
      const expectedUnknown = <NutrientId>[
        NutrientId.calcium,
        NutrientId.iron,
        NutrientId.vitaminA,
        NutrientId.vitaminC,
        NutrientId.vitaminD,
        NutrientId.magnesium,
        NutrientId.zinc,
        NutrientId.folate,
        NutrientId.vitaminB12,
        NutrientId.potassium,
      ];
      for (final id in expectedUnknown) {
        expect(vector[id].isComplete, isFalse,
            reason: '${id.name} should be unknown, not zero');
      }
      // And at least three quarters of the registry is unknown for this export.
      final unknownCount = NutrientId.values
          .where((id) => !vector[id].isComplete)
          .length;
      expect(unknownCount, greaterThan(NutrientId.values.length * 3 ~/ 4));
    });

    test('a genuine zero is complete, not unknown', () {
      const csv = '''
Date,Meal,Food,Calories,Fat (g),Carbohydrates (g),Protein (g)
2026-06-01,Lunch,Chicken,165,3.6,0,31
''';

      final carbs = adapter.parse(csv).meals.single.entries.single
          .nutrientsPer100[NutrientId.carbohydrate];
      expect(carbs.isComplete, isTrue);
      expect(carbs.value, 0);
    });

    test('normalises a US MM/DD/YYYY date into the local day', () {
      const csv = '''
Date,Meal,Food,Calories,Protein (g)
06/01/2026,Breakfast,Oats,389,16.9
''';

      final meal = adapter.parse(csv).meals.single;
      expect(meal.localDate, const NutritionDayDate(year: 2026, month: 6, day: 1));
    });

    test('derives a stable externalId, distinct per row and idempotent', () {
      const csv = '''
Date,Meal,Food,Calories,Protein (g)
2026-06-01,Breakfast,Oats,389,16.9
2026-06-01,Breakfast,Banana,105,1.3
''';

      final entries = adapter.parse(csv).meals.single.entries;
      final ids = entries.map((e) => e.externalId).toSet();
      expect(ids, hasLength(2));

      final again = adapter.parse(csv).meals.single.entries;
      expect(again.map((e) => e.externalId).toList(),
          entries.map((e) => e.externalId).toList());
    });

    test('throws on an unrecognized header', () {
      const csv = 'Foo,Bar,Baz\n1,2,3\n';
      expect(
        () => adapter.parse(csv),
        throwsA(isA<NutritionImportFormatException>()),
      );
    });

    test('returns an empty batch for a header-only file', () {
      const csv = 'Date,Meal,Food,Calories,Protein (g)\n';
      final batch = adapter.parse(csv);
      expect(batch.isEmpty, isTrue);
    });
  });
}
