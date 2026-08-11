import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/usda_food_seed.dart';

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

  group('USDA platform food repository', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('bundled USDA asset carries versioned attribution', () async {
      final seed = await const AssetUsdaFoodSeedSource().load();

      expect(seed.metadata.foodSource, FoodSource.usda);
      expect(seed.metadata.datasetVersion, 'fdc-foundation-sr-legacy-2026-04');
      expect(seed.metadata.sourceName, 'USDA FoodData Central');
      expect(seed.metadata.sourceUrl, 'https://fdc.nal.usda.gov/');
      expect(seed.metadata.licenseName, contains('Public domain'));
      expect(seed.metadata.attributionText, contains('USDA FoodData Central'));
      expect(seed.foods.map((food) => food.name), contains('Chicken breast'));
    });

    test('round-trips USDA Food fields and full nutrient vectors', () async {
      final seed = await const AssetUsdaFoodSeedSource().load();
      final reparsed = UsdaFoodSeed.fromJson(
        jsonDecode(jsonEncode(seed.toJson())) as Map<String, Object?>,
      );

      final chicken = reparsed.foods.singleWhere(
        (food) => food.name == 'Chicken breast',
      );

      expect(chicken.id, 'usda-fdc-171077');
      expect(chicken.foodSource, FoodSource.usda);
      expect(chicken.isLiquid, isFalse);
      expect(chicken.servingLabel, 'piece');
      expect(chicken.servingSize, 86);
      expect(chicken.packageSize, isNull);
      expect(chicken.availablePortionUnits, <PortionUnit>[
        PortionUnit.gram,
        PortionUnit.ounce,
        PortionUnit.serving,
      ]);
      expect(
        chicken.nutrientsPer100.amounts.keys.toSet(),
        NutrientId.values.toSet(),
      );
      expect(chicken.nutrientsPer100[NutrientId.energy].value, 165);
      expect(chicken.nutrientsPer100[NutrientId.protein].value, 31.02);
      expect(chicken.nutrientsPer100[NutrientId.vitaminB6].value, 0.6);
      expect(chicken.nutrientsPer100[NutrientId.selenium].value, 27.6);
      expect(
        chicken.nutrientsPer100[NutrientId.caffeine].status,
        NutrientValueStatus.unknown,
      );

      final milk = reparsed.foods.singleWhere(
        (food) => food.name == 'Milk, whole',
      );
      expect(milk.isLiquid, isTrue);
      expect(milk.servingLabel, 'cup');
      expect(milk.servingSize, 244);
      expect(milk.packageSize, 3785.41);
      expect(milk.availablePortionUnits, <PortionUnit>[
        PortionUnit.milliliter,
        PortionUnit.fluidOunce,
        PortionUnit.serving,
        PortionUnit.package,
      ]);
      expect(milk.nutrientsPer100[NutrientId.calcium].value, 113);
    });

    test('searches partial multi-term names without local writes', () async {
      final results = await repositories.platformFoods.searchUsdaFoods(
        ' chick   brea ',
      );

      expect(results, hasLength(1));
      final result = results.single;
      expect(result.id, 'usda-fdc-171077');
      expect(result.name, 'Chicken breast');
      expect(result.foodSource, FoodSource.usda);
      expect(result.nutrientsPer100[NutrientId.potassium].value, 256);

      expect(await database.select(database.foods).get(), isEmpty);
      expect(await database.select(database.foodEntries).get(), isEmpty);
      expect(await database.select(database.activityLog).get(), isEmpty);
    });

    test('lists USDA Foods and resolves them by id', () async {
      final foods = await repositories.platformFoods.listUsdaFoods();
      final chicken =
          await repositories.platformFoods.getUsdaFoodById('usda-fdc-171077');
      final missing =
          await repositories.platformFoods.getUsdaFoodById('usda-fdc-missing');

      expect(foods.map((food) => food.id), contains('usda-fdc-171077'));
      expect(chicken?.name, 'Chicken breast');
      expect(chicken?.foodSource, FoodSource.usda);
      expect(missing, isNull);
    });

    test('exposes searchable USDA metadata without network dependencies',
        () async {
      final metadata = await repositories.platformFoods.usdaMetadata();
      final chickpeaResults =
          await repositories.platformFoods.searchUsdaFoods('chick boil');

      expect(metadata.datasetVersion, 'fdc-foundation-sr-legacy-2026-04');
      expect(metadata.attributionText, contains('USDA'));
      expect(
        chickpeaResults.map((food) => food.name),
        <String>['Chickpeas, boiled'],
      );
      expect(
        chickpeaResults.single.nutrientsPer100[NutrientId.folate].value,
        172,
      );
    });
  });
}
