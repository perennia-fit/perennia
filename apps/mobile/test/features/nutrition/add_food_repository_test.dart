import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/open_food_facts_repository.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/usda_food_seed.dart';
import 'package:perennia/features/nutrition/repositories/add_food_repository.dart';

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

  group('Add Food repository', () {
    late AppDatabase database;
    late TrainingRepositories repositories;
    late RepositoryAddFoodRepository addFoodRepository;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(
        database,
        usdaFoodSeedSource: const _FakeUsdaFoodSeedSource(),
      );
      addFoodRepository = RepositoryAddFoodRepository(repositories);
    });

    tearDown(() async {
      await database.close();
    });

    test('scopes partial multi-term searches by picker source', () async {
      final userChickenId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Meal prep chicken',
          nutrientsPer100: _nutrients(energy: 180, protein: 28),
          isLiquid: false,
          servingLabel: 'bowl',
          servingSize: 250,
        ),
        actor: 'tester',
      );
      await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Greek yogurt',
          nutrientsPer100: _nutrients(energy: 100, protein: 10),
          isLiquid: false,
        ),
        actor: 'tester',
      );
      final mealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Lunch',
          startedAt: DateTime.utc(2026, 6, 26, 12),
          timezone: 'Australia/Brisbane',
          localDate: const NutritionDayDate(year: 2026, month: 6, day: 26),
        ),
        actor: 'tester',
      );
      await repositories.nutrition.logFoodEntry(
        entry: FoodEntryDraft(
          mealId: mealId,
          foodId: userChickenId,
          portion: Portion(
            value: 100,
            entered: '100',
            unit: PortionUnit.gram,
          ),
        ),
        actor: 'tester',
      );

      final recentResults = await addFoodRepository.search(
        filter: AddFoodPickerFilter.recent,
        query: 'prep chick',
      );
      final userResults = await addFoodRepository.search(
        filter: AddFoodPickerFilter.user,
        query: 'prep chick',
      );
      final usdaResults = await addFoodRepository.search(
        filter: AddFoodPickerFilter.usda,
        query: 'chick boil',
      );

      expect(recentResults, hasLength(1));
      expect(recentResults.single.id, userChickenId);
      expect(recentResults.single.name, 'Meal prep chicken');
      expect(recentResults.single.filter, AddFoodPickerFilter.recent);
      expect(recentResults.single.foodSource, FoodSource.user);

      expect(userResults.map((item) => item.name), <String>[
        'Meal prep chicken',
      ]);
      expect(userResults.single.filter, AddFoodPickerFilter.user);
      expect(userResults.single.foodSource, FoodSource.user);

      expect(usdaResults.map((item) => item.name), <String>[
        'Chickpeas, boiled',
      ]);
      expect(usdaResults.single.id, 'usda-chickpeas');
      expect(usdaResults.single.filter, AddFoodPickerFilter.usda);
      expect(usdaResults.single.foodSource, FoodSource.usda);
    });

    test('scopes Your Food search before materializing User Food rows',
        () async {
      final matchingFoodId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Meal prep oats',
          nutrientsPer100: _nutrients(energy: 120, protein: 5),
          isLiquid: false,
        ),
        actor: 'tester',
      );
      await database.into(database.foods).insert(
            FoodsCompanion.insert(
              id: 'malformed-unmatched-food',
              name: 'Malformed soup',
              nutrientValuesJson:
                  _nutrients(energy: 10, protein: 1).toJsonString(),
              recipeIngredientsJson: const Value<String?>('not json'),
              recipeServingCount: const Value<double?>(1),
              updatedAt: DateTime.utc(2026, 6, 26, 13),
            ),
          );

      final results = await addFoodRepository.search(
        filter: AddFoodPickerFilter.user,
        query: 'prep oats',
      );

      expect(results.map((item) => item.id), <String>[matchingFoodId]);
      expect(results.single.name, 'Meal prep oats');
    });

    test('searching bundled USDA data does not write local user data',
        () async {
      final activityLogBefore =
          await database.select(database.activityLog).get();
      final foodsBefore = await database.select(database.foods).get();
      final entriesBefore = await database.select(database.foodEntries).get();

      final results = await addFoodRepository.search(
        filter: AddFoodPickerFilter.usda,
        query: 'chick brea',
      );

      expect(results.map((item) => item.name), <String>['Chicken breast']);
      expect(await database.select(database.activityLog).get(),
          hasLength(activityLogBefore.length));
      expect(await database.select(database.foods).get(),
          hasLength(foodsBefore.length));
      expect(await database.select(database.foodEntries).get(),
          hasLength(entriesBefore.length));
    });

    test('shows Recipes as Your Food with derived serving nutrition', () async {
      final oatsId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Oats',
          nutrientsPer100: _nutrients(energy: 120, protein: 5),
          isLiquid: false,
        ),
        actor: 'tester',
      );
      final powderId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Protein powder',
          nutrientsPer100: _nutrients(energy: 200, protein: 50),
          isLiquid: false,
        ),
        actor: 'tester',
      );
      final oats = (await repositories.nutrition.getUserFoodById(oatsId))!;
      final powder = (await repositories.nutrition.getUserFoodById(powderId))!;
      final recipeId = await repositories.nutrition.createRecipe(
        RecipeDraft(
          name: 'Protein oats',
          servingCount: 2,
          ingredients: <RecipeIngredient>[
            _ingredientFromFood(
              oats,
              Portion(value: 100, entered: '100', unit: PortionUnit.gram),
            ),
            _ingredientFromFood(
              powder,
              Portion(value: 50, entered: '50', unit: PortionUnit.gram),
            ),
          ],
        ),
        actor: 'tester',
      );

      final results = await addFoodRepository.search(
        filter: AddFoodPickerFilter.user,
        query: 'protein oats',
      );

      expect(results, hasLength(1));
      expect(results.single.id, recipeId);
      expect(results.single.name, 'Protein oats');
      expect(results.single.foodSource, FoodSource.user);
      expect(results.single.servingLabel, 'serving');
      expect(results.single.servingSize, closeTo(75, 0.000001));
      expect(
        results.single.availablePortionUnits,
        contains(PortionUnit.serving),
      );
      expect(
        results.single.nutrientsPer100[NutrientId.energy].value,
        closeTo(146.666667, 0.000001),
      );
      expect(
        results.single.nutrientsPer100[NutrientId.protein].value,
        closeTo(20, 0.000001),
      );
    });

    test(
        'hydrates last logged Portion from local Food Entry history without storing analytics',
        () async {
      final foodId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Meal prep oats',
          nutrientsPer100: _nutrients(energy: 120, protein: 5),
          isLiquid: false,
          servingLabel: 'bowl',
          servingSize: 160,
        ),
        actor: 'tester',
      );
      final breakfastId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Breakfast',
          startedAt: DateTime.utc(2026, 6, 25, 8),
          timezone: 'Australia/Brisbane',
          localDate: const NutritionDayDate(year: 2026, month: 6, day: 25),
        ),
        actor: 'tester',
      );
      await repositories.nutrition.logFoodEntry(
        entry: FoodEntryDraft(
          mealId: breakfastId,
          foodId: foodId,
          portion: Portion(
            value: 80,
            entered: '80',
            unit: PortionUnit.gram,
          ),
        ),
        actor: 'tester',
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final snackId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Snack',
          startedAt: DateTime.utc(2026, 6, 26, 15),
          timezone: 'Australia/Brisbane',
          localDate: const NutritionDayDate(year: 2026, month: 6, day: 26),
        ),
        actor: 'tester',
      );
      await repositories.nutrition.logFoodEntry(
        entry: FoodEntryDraft(
          mealId: snackId,
          foodId: foodId,
          portion: Portion(
            value: 1.5,
            entered: '1.5',
            unit: PortionUnit.serving,
          ),
        ),
        actor: 'tester',
      );

      final recentResults = await addFoodRepository.search(
        filter: AddFoodPickerFilter.recent,
        query: 'prep oats',
      );
      final userResults = await addFoodRepository.search(
        filter: AddFoodPickerFilter.user,
        query: 'prep oats',
      );

      expect(recentResults, hasLength(1));
      expect(recentResults.single.lastPortion?.value, 1.5);
      expect(recentResults.single.lastPortion?.entered, '1.5');
      expect(recentResults.single.lastPortion?.unit, PortionUnit.serving);
      expect(userResults, hasLength(1));
      expect(userResults.single.lastPortion?.value, 1.5);
      expect(userResults.single.lastPortion?.entered, '1.5');
      expect(userResults.single.lastPortion?.unit, PortionUnit.serving);
      expect(await database.select(database.metrics).get(), isEmpty);
      expect(await database.select(database.metricReadings).get(), isEmpty);
    });

    test('keeps last Portion separate from current User Food unit gating',
        () async {
      final foodId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Editable rice',
          nutrientsPer100: _nutrients(energy: 130, protein: 3),
          isLiquid: false,
          servingLabel: 'bowl',
          servingSize: 150,
        ),
        actor: 'tester',
      );
      final mealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Dinner',
          startedAt: DateTime.utc(2026, 6, 25, 19),
          timezone: 'Australia/Brisbane',
          localDate: const NutritionDayDate(year: 2026, month: 6, day: 25),
        ),
        actor: 'tester',
      );
      await repositories.nutrition.logFoodEntry(
        entry: FoodEntryDraft(
          mealId: mealId,
          foodId: foodId,
          portion: Portion(
            value: 2,
            entered: '2',
            unit: PortionUnit.serving,
          ),
        ),
        actor: 'tester',
      );
      await repositories.nutrition.updateUserFood(
        foodId,
        UserFoodDraft(
          name: 'Editable rice',
          nutrientsPer100: _nutrients(energy: 140, protein: 4),
          isLiquid: false,
        ),
        actor: 'tester',
      );

      final userResults = await addFoodRepository.search(
        filter: AddFoodPickerFilter.user,
        query: 'editable',
      );

      expect(userResults, hasLength(1));
      expect(userResults.single.servingLabel, isNull);
      expect(userResults.single.servingSize, isNull);
      expect(userResults.single.availablePortionUnits,
          isNot(contains(PortionUnit.serving)));
      expect(userResults.single.lastPortion?.value, 2);
      expect(userResults.single.lastPortion?.entered, '2');
      expect(userResults.single.lastPortion?.unit, PortionUnit.serving);
    });

    test('repeat prefill writes a new independent Food Entry snapshot',
        () async {
      final foodId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Greek yogurt',
          nutrientsPer100: _nutrients(energy: 105, protein: 11),
          isLiquid: false,
          servingLabel: 'cup',
          servingSize: 170,
        ),
        actor: 'tester',
      );
      final firstMealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Snack',
          startedAt: DateTime.utc(2026, 6, 25, 15),
          timezone: 'Australia/Brisbane',
          localDate: const NutritionDayDate(year: 2026, month: 6, day: 25),
        ),
        actor: 'tester',
      );
      final firstResult = await repositories.nutrition.logFoodEntry(
        entry: FoodEntryDraft(
          mealId: firstMealId,
          foodId: foodId,
          portion: Portion(
            value: 1.25,
            entered: '1.25',
            unit: PortionUnit.serving,
          ),
        ),
        actor: 'tester',
      );
      final recentItem = (await addFoodRepository.search(
        filter: AddFoodPickerFilter.recent,
        query: 'yogurt',
      ))
          .single;
      final repeatMealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Snack',
          startedAt: DateTime.utc(2026, 6, 26, 15),
          timezone: 'Australia/Brisbane',
          localDate: const NutritionDayDate(year: 2026, month: 6, day: 26),
        ),
        actor: 'tester',
      );

      final repeatResult = await repositories.nutrition.logFoodEntrySnapshot(
        entry: FoodEntrySnapshotDraft(
          mealId: repeatMealId,
          foodId: recentItem.id,
          name: recentItem.name,
          foodSource: recentItem.foodSource,
          nutrientsPer100: recentItem.nutrientsPer100,
          isLiquid: recentItem.isLiquid,
          servingLabel: recentItem.servingLabel,
          servingSize: recentItem.servingSize,
          packageSize: recentItem.packageSize,
          portion: recentItem.lastPortion!,
        ),
        actor: 'tester',
      );

      final firstEntry = (await repositories.nutrition.getFoodEntryById(
        firstResult.foodEntryId,
      ))!;
      final repeatEntry = (await repositories.nutrition.getFoodEntryById(
        repeatResult.foodEntryId,
      ))!;
      expect(repeatEntry.id, isNot(firstEntry.id));
      expect(firstEntry.mealId, firstMealId);
      expect(repeatEntry.mealId, repeatMealId);
      expect(firstEntry.portion?.value, 1.25);
      expect(firstEntry.portion?.entered, '1.25');
      expect(firstEntry.portion?.unit, PortionUnit.serving);
      expect(repeatEntry.portion?.value, 1.25);
      expect(repeatEntry.portion?.entered, '1.25');
      expect(repeatEntry.portion?.unit, PortionUnit.serving);
      expect(firstEntry.name, 'Greek yogurt');
      expect(repeatEntry.name, 'Greek yogurt');
      expect(firstEntry.nutrients[NutrientId.energy].value, 105);
      expect(repeatEntry.nutrients[NutrientId.energy].value, 105);
      expect(
        await repositories.nutrition.listActiveEntriesForMeal(firstMealId),
        hasLength(1),
      );
      expect(
        await repositories.nutrition.listActiveEntriesForMeal(repeatMealId),
        hasLength(1),
      );
    });

    test('the Open Food Facts filter searches the device list', () async {
      final openFoodFacts = _RecordingOpenFoodFactsRepository(
        local: <PlatformFoodRecord>[_offRecord('9300633603427', 'Weet-Bix')],
      );
      final repository = RepositoryAddFoodRepository(
        repositories,
        openFoodFacts: openFoodFacts,
      );

      final items = await repository.search(
        filter: AddFoodPickerFilter.openFoodFacts,
        query: 'weet',
      );

      expect(openFoodFacts.localQueries, <String>['weet']);
      expect(items.single.id, '9300633603427');
      expect(items.single.brand, 'Sanitarium');
      expect(items.single.isLiveResult, isFalse);
    });

    test('passes the online setting to Open Food Facts as allowOnline',
        () async {
      for (final enabled in <bool>[true, false]) {
        final openFoodFacts = _RecordingOpenFoodFactsRepository();
        final repository = RepositoryAddFoodRepository(
          repositories,
          openFoodFacts: openFoodFacts,
          onlineLookupsEnabled: () async => enabled,
        );

        final online = await repository.searchOnline('weet bix');
        await repository.lookupBarcode('9300633603427');

        expect(openFoodFacts.allowOnline, <bool>[enabled, enabled]);
        expect(online.items.every((item) => item.isLiveResult), isTrue);
      }
    });

    test('without an Open Food Facts repository the filter finds nothing',
        () async {
      final items = await addFoodRepository.search(
        filter: AddFoodPickerFilter.openFoodFacts,
        query: 'weet',
      );
      final online = await addFoodRepository.searchOnline('weet');
      final barcode = await addFoodRepository.lookupBarcode('9300633603427');

      expect(items, isEmpty);
      expect(online.status, OnlineSearchStatus.disabled);
      expect(barcode.status, BarcodeLookupOutcome.disabled);
    });
  });
}

PlatformFoodRecord _offRecord(String code, String name) {
  return PlatformFoodRecord(
    id: code,
    name: name,
    foodSource: FoodSource.openFoodFacts,
    nutrientsPer100: NutrientVector.full(<NutrientId, NutrientAmount>{
      NutrientId.energy: NutrientAmount.complete(
        value: 352,
        entered: '352',
        unit: NutrientUnit.kilocalorie,
      ),
    }),
    isLiquid: false,
    brand: 'Sanitarium',
    sourceModifiedAt: DateTime.utc(2026, 10, 1),
    scans: 40,
  );
}

/// Records what the add-food repository asks of Open Food Facts.
class _RecordingOpenFoodFactsRepository extends StubOpenFoodFactsRepository {
  _RecordingOpenFoodFactsRepository({
    this.local = const <PlatformFoodRecord>[],
  });

  final List<PlatformFoodRecord> local;
  final localQueries = <String>[];
  final allowOnline = <bool>[];

  @override
  Future<List<PlatformFoodRecord>> searchLocal(
    String query, {
    int limit = 50,
  }) async {
    localQueries.add(query);
    return local;
  }

  @override
  Future<({OnlineSearchStatus status, List<PlatformFoodRecord> products})>
      searchOnline(String query, {required bool allowOnline}) async {
    this.allowOnline.add(allowOnline);
    return (
      status: OnlineSearchStatus.ok,
      products: <PlatformFoodRecord>[_offRecord('9300633603427', 'Weet-Bix')],
    );
  }

  @override
  Future<({BarcodeLookupOutcome status, PlatformFoodRecord? product})>
      lookupBarcode(String raw, {required bool allowOnline}) async {
    this.allowOnline.add(allowOnline);
    return (status: BarcodeLookupOutcome.notFound, product: null);
  }
}

class _FakeUsdaFoodSeedSource implements UsdaFoodSeedSource {
  const _FakeUsdaFoodSeedSource();

  @override
  Future<UsdaFoodSeed> load() async {
    return UsdaFoodSeed(
      metadata: const UsdaFoodSeedMetadata(
        datasetVersion: 'test-usda',
        sourceName: 'USDA FoodData Central',
        sourceUrl: 'https://fdc.nal.usda.gov/',
        licenseName: 'Public domain',
        attributionText: 'USDA FoodData Central',
      ),
      foods: <PlatformFoodRecord>[
        PlatformFoodRecord(
          id: 'usda-chicken',
          name: 'Chicken breast',
          foodSource: FoodSource.usda,
          nutrientsPer100: _nutrients(energy: 165, protein: 31.02),
          isLiquid: false,
          servingLabel: 'piece',
          servingSize: 86,
        ),
        PlatformFoodRecord(
          id: 'usda-chickpeas',
          name: 'Chickpeas, boiled',
          foodSource: FoodSource.usda,
          nutrientsPer100: _nutrients(energy: 164, protein: 8.86),
          isLiquid: false,
        ),
        PlatformFoodRecord(
          id: 'usda-milk',
          name: 'Milk, whole',
          foodSource: FoodSource.usda,
          nutrientsPer100: _nutrients(energy: 61, protein: 3.15),
          isLiquid: true,
          servingLabel: 'cup',
          servingSize: 244,
        ),
      ],
    );
  }
}

NutrientVector _nutrients({
  required double energy,
  required double protein,
}) {
  return NutrientVector.energyAndMacros(
    energy: _complete(NutrientId.energy, energy),
    protein: _complete(NutrientId.protein, protein),
    carbohydrate: _complete(NutrientId.carbohydrate, 0),
    fat: _complete(NutrientId.fat, 0),
  );
}

NutrientAmount _complete(NutrientId id, double value) {
  final entered = value.toString().replaceFirst(RegExp(r'\.0$'), '');
  return NutrientAmount.complete(
    value: value,
    entered: entered,
    unit: id.defaultUnit,
  );
}

RecipeIngredient _ingredientFromFood(UserFoodRecord food, Portion portion) {
  return RecipeIngredient(
    foodId: food.id,
    name: food.name,
    foodSource: food.foodSource,
    nutrientsPer100: food.nutrientsPer100,
    isLiquid: food.isLiquid,
    portion: portion,
    servingLabel: food.servingLabel,
    servingSize: food.servingSize,
    packageSize: food.packageSize,
  );
}
