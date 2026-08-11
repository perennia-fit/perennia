import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:perennia/data/local/app_database.dart';
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

    test(
        'looks up Open Food Facts barcode misses over the network then hits local unsynced cache',
        () async {
      final requests = <http.Request>[];
      final httpClient = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(_offProductResponse(
            code: '3017620422003',
            name: 'Hazelnut cocoa spread',
            servingQuantity: 15,
            servingQuantityUnit: 'g',
            packageQuantity: 400,
            packageQuantityUnit: 'g',
            nutriments: <String, Object?>{
              'energy-kcal_100g': 539,
              'proteins_100g': 6.3,
              'carbohydrates_100g': 0,
              'fat_100g': 30.9,
              'sugars_100g': 56.3,
            },
          )),
          200,
          headers: const {'content-type': 'application/json'},
        );
      });
      repositories = TrainingRepositories(
        database,
        usdaFoodSeedSource: const _FakeUsdaFoodSeedSource(),
        openFoodFactsBaseUrl: Uri.parse('https://off.test/'),
        openFoodFactsHttpClient: httpClient,
      );
      addFoodRepository = RepositoryAddFoodRepository(repositories);

      final firstLookup = await addFoodRepository.search(
        filter: AddFoodPickerFilter.openFoodFacts,
        query: '3017620422003',
      );
      final secondLookup = await addFoodRepository.search(
        filter: AddFoodPickerFilter.openFoodFacts,
        query: '3017620422003',
      );

      expect(requests, hasLength(1));
      expect(
        requests.single.url.path,
        '/api/v2/product/3017620422003.json',
      );
      expect(requests.single.url.queryParameters, contains('fields'));
      expect(firstLookup, hasLength(1));
      expect(secondLookup, hasLength(1));
      expect(secondLookup.single.id, '3017620422003');
      expect(secondLookup.single.name, 'Hazelnut cocoa spread');
      expect(secondLookup.single.filter, AddFoodPickerFilter.openFoodFacts);
      expect(secondLookup.single.foodSource, FoodSource.openFoodFacts);
      expect(secondLookup.single.isLiquid, isFalse);
      expect(secondLookup.single.servingLabel, 'serving');
      expect(secondLookup.single.servingSize, 15);
      expect(secondLookup.single.packageSize, 400);
      expect(
        secondLookup.single.nutrientsPer100[NutrientId.energy].value,
        539,
      );
      expect(
        secondLookup.single.nutrientsPer100[NutrientId.carbohydrate].status,
        NutrientValueStatus.complete,
      );
      expect(
        secondLookup.single.nutrientsPer100[NutrientId.carbohydrate].value,
        0,
      );
      expect(
        secondLookup.single.nutrientsPer100[NutrientId.fiber].status,
        NutrientValueStatus.unknown,
      );
      expect(await database.select(database.openFoodFactsCache).get(),
          hasLength(1));
      expect(await database.select(database.foods).get(), isEmpty);
      expect(await database.select(database.activityLog).get(), isEmpty);
      expect(
        AppDatabase.tableNames,
        isNot(contains(AppDatabase.openFoodFactsCacheTable)),
      );
      expect(
        AppDatabase.schemaTableNames,
        contains(AppDatabase.openFoodFactsCacheTable),
      );
    });

    test(
        'looks up branded Open Food Facts names through search and caches them',
        () async {
      final requests = <http.Request>[];
      final httpClient = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, Object?>{
            'products': <Object?>[
              _offProduct(
                code: 'branded-cereal-1',
                name: 'Branded cereal',
                servingQuantity: 30,
                servingQuantityUnit: 'g',
                packageQuantity: 500,
                packageQuantityUnit: 'g',
                nutriments: <String, Object?>{
                  'energy-kcal_100g': 380,
                  'proteins_100g': 8,
                  'carbohydrates_100g': 72,
                  'fat_100g': 4,
                },
              ),
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      });
      repositories = TrainingRepositories(
        database,
        usdaFoodSeedSource: const _FakeUsdaFoodSeedSource(),
        openFoodFactsBaseUrl: Uri.parse('https://off.test/'),
        openFoodFactsHttpClient: httpClient,
      );
      addFoodRepository = RepositoryAddFoodRepository(repositories);

      final firstLookup = await addFoodRepository.search(
        filter: AddFoodPickerFilter.openFoodFacts,
        query: 'branded cereal',
      );
      final secondLookup = await addFoodRepository.search(
        filter: AddFoodPickerFilter.openFoodFacts,
        query: 'branded cereal',
      );

      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/cgi/search.pl');
      expect(
          requests.single.url.queryParameters,
          containsPair(
            'search_terms',
            'branded cereal',
          ));
      expect(firstLookup.single.name, 'Branded cereal');
      expect(firstLookup.single.foodSource, FoodSource.openFoodFacts);
      expect(secondLookup.single.id, firstLookup.single.id);
      expect(await database.select(database.openFoodFactsCache).get(),
          hasLength(1));
    });

    test('Open Food Facts 404 misses write no cache row and do not throw',
        () async {
      final requests = <http.Request>[];
      final httpClient = MockClient((request) async {
        requests.add(request);
        return http.Response('not found', 404);
      });
      repositories = TrainingRepositories(
        database,
        usdaFoodSeedSource: const _FakeUsdaFoodSeedSource(),
        openFoodFactsBaseUrl: Uri.parse('https://off.test/'),
        openFoodFactsHttpClient: httpClient,
      );
      addFoodRepository = RepositoryAddFoodRepository(repositories);

      final results = await addFoodRepository.search(
        filter: AddFoodPickerFilter.openFoodFacts,
        query: '3017620422003',
      );

      expect(results, isEmpty);
      expect(requests, hasLength(1));
      expect(await database.select(database.openFoodFactsCache).get(), isEmpty);
    });

    test(
        'Open Food Facts non-2xx misses throw without poisoning the cache and retry',
        () async {
      var requestCount = 0;
      final httpClient = MockClient((request) async {
        requestCount += 1;
        if (requestCount == 1) {
          return http.Response('temporarily down', 500);
        }
        return http.Response(
          jsonEncode(_offProductResponse(
            code: '3017620422003',
            name: 'Recovered branded food',
            servingQuantity: 100,
            servingQuantityUnit: 'g',
            packageQuantity: 100,
            packageQuantityUnit: 'g',
            nutriments: <String, Object?>{
              'energy-kcal_100g': 210,
              'proteins_100g': 7,
              'carbohydrates_100g': 20,
              'fat_100g': 10,
            },
          )),
          200,
          headers: const {'content-type': 'application/json'},
        );
      });
      repositories = TrainingRepositories(
        database,
        usdaFoodSeedSource: const _FakeUsdaFoodSeedSource(),
        openFoodFactsBaseUrl: Uri.parse('https://off.test/'),
        openFoodFactsHttpClient: httpClient,
      );
      addFoodRepository = RepositoryAddFoodRepository(repositories);

      await expectLater(
        addFoodRepository.search(
          filter: AddFoodPickerFilter.openFoodFacts,
          query: '3017620422003',
        ),
        throwsA(isA<http.ClientException>()),
      );
      expect(await database.select(database.openFoodFactsCache).get(), isEmpty);

      final retryResults = await addFoodRepository.search(
        filter: AddFoodPickerFilter.openFoodFacts,
        query: '3017620422003',
      );

      expect(requestCount, 2);
      expect(retryResults.single.name, 'Recovered branded food');
      expect(await database.select(database.openFoodFactsCache).get(),
          hasLength(1));
    });

    test('Open Food Facts product status zero is a cache-free miss', () async {
      final httpClient = MockClient((_) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'status': 0,
            'status_verbose': 'product not found',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      });
      repositories = TrainingRepositories(
        database,
        usdaFoodSeedSource: const _FakeUsdaFoodSeedSource(),
        openFoodFactsBaseUrl: Uri.parse('https://off.test/'),
        openFoodFactsHttpClient: httpClient,
      );
      addFoodRepository = RepositoryAddFoodRepository(repositories);

      final results = await addFoodRepository.search(
        filter: AddFoodPickerFilter.openFoodFacts,
        query: '3017620422003',
      );

      expect(results, isEmpty);
      expect(await database.select(database.openFoodFactsCache).get(), isEmpty);
    });

    test(
        'Open Food Facts branded search misses on empty or unparseable products',
        () async {
      var requestCount = 0;
      final httpClient = MockClient((_) async {
        requestCount += 1;
        final products = requestCount == 1
            ? const <Object?>[]
            : <Object?>[
                <String, Object?>{
                  'code': 'missing-name',
                  'nutriments': <String, Object?>{
                    'energy-kcal_100g': 120,
                  },
                },
              ];
        return http.Response(
          jsonEncode(<String, Object?>{'products': products}),
          200,
          headers: const {'content-type': 'application/json'},
        );
      });
      repositories = TrainingRepositories(
        database,
        usdaFoodSeedSource: const _FakeUsdaFoodSeedSource(),
        openFoodFactsBaseUrl: Uri.parse('https://off.test/'),
        openFoodFactsHttpClient: httpClient,
      );
      addFoodRepository = RepositoryAddFoodRepository(repositories);

      final emptyResults = await addFoodRepository.search(
        filter: AddFoodPickerFilter.openFoodFacts,
        query: 'empty branded search',
      );
      final unparseableResults = await addFoodRepository.search(
        filter: AddFoodPickerFilter.openFoodFacts,
        query: 'unparseable branded search',
      );

      expect(emptyResults, isEmpty);
      expect(unparseableResults, isEmpty);
      expect(await database.select(database.openFoodFactsCache).get(), isEmpty);
    });

    test('Open Food Facts malformed JSON throws and writes no cache row',
        () async {
      final httpClient = MockClient((_) async {
        return http.Response(
          jsonEncode(<Object?>['not', 'an', 'object']),
          200,
          headers: const {'content-type': 'application/json'},
        );
      });
      repositories = TrainingRepositories(
        database,
        usdaFoodSeedSource: const _FakeUsdaFoodSeedSource(),
        openFoodFactsBaseUrl: Uri.parse('https://off.test/'),
        openFoodFactsHttpClient: httpClient,
      );
      addFoodRepository = RepositoryAddFoodRepository(repositories);

      await expectLater(
        addFoodRepository.search(
          filter: AddFoodPickerFilter.openFoodFacts,
          query: '3017620422003',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(await database.select(database.openFoodFactsCache).get(), isEmpty);
    });

    test('Open Food Facts cache evicts least-recently-used rows over its bound',
        () async {
      final requests = <http.Request>[];
      var now = DateTime.utc(2026, 6, 27, 12);
      final httpClient = MockClient((request) async {
        requests.add(request);
        final code = request.url.pathSegments
            .lastWhere((segment) => segment.endsWith('.json'))
            .replaceFirst('.json', '');
        return http.Response(
          jsonEncode(_offProductResponse(
            code: code,
            name: 'Cached food $code',
            servingQuantity: 100,
            servingQuantityUnit: 'g',
            packageQuantity: 100,
            packageQuantityUnit: 'g',
            nutriments: <String, Object?>{
              'energy-kcal_100g': 100,
              'proteins_100g': 1,
              'carbohydrates_100g': 2,
              'fat_100g': 3,
            },
          )),
          200,
          headers: const {'content-type': 'application/json'},
        );
      });
      repositories = TrainingRepositories(
        database,
        usdaFoodSeedSource: const _FakeUsdaFoodSeedSource(),
        openFoodFactsBaseUrl: Uri.parse('https://off.test/'),
        openFoodFactsHttpClient: httpClient,
        openFoodFactsMaxCacheEntries: 1,
        openFoodFactsClock: () => now,
      );
      addFoodRepository = RepositoryAddFoodRepository(repositories);

      await addFoodRepository.search(
        filter: AddFoodPickerFilter.openFoodFacts,
        query: '11111111',
      );
      now = now.add(const Duration(minutes: 1));
      await addFoodRepository.search(
        filter: AddFoodPickerFilter.openFoodFacts,
        query: '22222222',
      );
      now = now.add(const Duration(minutes: 1));
      await addFoodRepository.search(
        filter: AddFoodPickerFilter.openFoodFacts,
        query: '11111111',
      );

      final cacheRows =
          await database.select(database.openFoodFactsCache).get();
      expect(cacheRows, hasLength(1));
      expect(cacheRows.single.foodId, '11111111');
      expect(requests.map((request) => request.url.path), <String>[
        '/api/v2/product/11111111.json',
        '/api/v2/product/22222222.json',
        '/api/v2/product/11111111.json',
      ]);
    });

    test(
        'Open Food Facts Food Entry snapshot stays immutable after cache eviction and source change',
        () async {
      final requestsByCode = <String, int>{};
      var now = DateTime.utc(2026, 6, 27, 12);
      final httpClient = MockClient((request) async {
        final code = request.url.pathSegments
            .lastWhere((segment) => segment.endsWith('.json'))
            .replaceFirst('.json', '');
        requestsByCode[code] = (requestsByCode[code] ?? 0) + 1;
        final requestCount = requestsByCode[code]!;
        if (code == '3017620422003' && requestCount == 1) {
          return http.Response(
            jsonEncode(_offProductResponse(
              code: code,
              name: 'Original branded bar',
              servingQuantity: 45,
              servingQuantityUnit: 'g',
              packageQuantity: 60,
              packageQuantityUnit: 'g',
              nutriments: <String, Object?>{
                'energy-kcal_100g': 250,
                'proteins_100g': 8,
                'carbohydrates_100g': 28,
                'fat_100g': 11,
              },
            )),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(_offProductResponse(
            code: code,
            name: code == '3017620422003'
                ? 'Corrected branded bar'
                : 'Evicting branded food',
            servingQuantity: code == '3017620422003' ? 50 : 100,
            servingQuantityUnit: 'g',
            packageQuantity: code == '3017620422003' ? 70 : 100,
            packageQuantityUnit: 'g',
            nutriments: <String, Object?>{
              'energy-kcal_100g': code == '3017620422003' ? 300 : 100,
              'proteins_100g': code == '3017620422003' ? 12 : 1,
              'carbohydrates_100g': code == '3017620422003' ? 30 : 2,
              'fat_100g': code == '3017620422003' ? 14 : 3,
            },
          )),
          200,
          headers: const {'content-type': 'application/json'},
        );
      });
      repositories = TrainingRepositories(
        database,
        usdaFoodSeedSource: const _FakeUsdaFoodSeedSource(),
        openFoodFactsBaseUrl: Uri.parse('https://off.test/'),
        openFoodFactsHttpClient: httpClient,
        openFoodFactsMaxCacheEntries: 1,
        openFoodFactsClock: () => now,
      );
      addFoodRepository = RepositoryAddFoodRepository(repositories);
      final firstLookup = (await addFoodRepository.search(
        filter: AddFoodPickerFilter.openFoodFacts,
        query: '3017620422003',
      ))
          .single;
      final mealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Snack',
          startedAt: DateTime.utc(2026, 6, 26, 15),
          timezone: 'Australia/Brisbane',
          localDate: const NutritionDayDate(year: 2026, month: 6, day: 26),
        ),
      );
      final result = await repositories.nutrition.logFoodEntrySnapshot(
        entry: FoodEntrySnapshotDraft(
          mealId: mealId,
          foodId: firstLookup.id,
          name: firstLookup.name,
          foodSource: firstLookup.foodSource,
          nutrientsPer100: firstLookup.nutrientsPer100,
          isLiquid: firstLookup.isLiquid,
          servingLabel: firstLookup.servingLabel,
          servingSize: firstLookup.servingSize,
          packageSize: firstLookup.packageSize,
          portion: Portion(
            value: 1,
            entered: '1',
            unit: PortionUnit.serving,
          ),
        ),
      );

      expect(requestsByCode['3017620422003'], 1);
      now = now.add(const Duration(minutes: 1));
      await addFoodRepository.search(
        filter: AddFoodPickerFilter.openFoodFacts,
        query: '22222222',
      );
      now = now.add(const Duration(minutes: 1));
      final correctedLookup = (await addFoodRepository.search(
        filter: AddFoodPickerFilter.openFoodFacts,
        query: '3017620422003',
      ))
          .single;
      final entry = (await repositories.nutrition.getFoodEntryById(
        result.foodEntryId,
      ))!;
      final foodEntryLogs = (await database.select(database.activityLog).get())
          .where((log) => log.entityTable == AppDatabase.foodEntriesTable)
          .toList(growable: false);

      expect(requestsByCode['3017620422003'], 2);
      expect(correctedLookup.name, 'Corrected branded bar');
      expect(correctedLookup.nutrientsPer100[NutrientId.energy].value, 300);
      expect(entry.name, 'Original branded bar');
      expect(entry.foodId, '3017620422003');
      expect(entry.foodSource, FoodSource.openFoodFacts);
      expect(entry.nutrients[NutrientId.energy].value, 250);
      expect(entry.nutrients[NutrientId.protein].value, 8);
      expect(entry.isLiquid, isFalse);
      expect(entry.servingLabel, 'serving');
      expect(entry.servingSize, 45);
      expect(entry.packageSize, 60);
      expect(entry.portion?.value, 1);
      expect(entry.portion?.entered, '1');
      expect(entry.portion?.unit, PortionUnit.serving);
      expect(foodEntryLogs.single.actor, 'app');
    });
  });
}

Map<String, Object?> _offProductResponse({
  required String code,
  required String name,
  required double servingQuantity,
  required String servingQuantityUnit,
  required double packageQuantity,
  required String packageQuantityUnit,
  required Map<String, Object?> nutriments,
}) {
  return <String, Object?>{
    'status': 1,
    'product': _offProduct(
      code: code,
      name: name,
      servingQuantity: servingQuantity,
      servingQuantityUnit: servingQuantityUnit,
      packageQuantity: packageQuantity,
      packageQuantityUnit: packageQuantityUnit,
      nutriments: nutriments,
    ),
  };
}

Map<String, Object?> _offProduct({
  required String code,
  required String name,
  required double servingQuantity,
  required String servingQuantityUnit,
  required double packageQuantity,
  required String packageQuantityUnit,
  required Map<String, Object?> nutriments,
}) {
  return <String, Object?>{
    'code': code,
    'product_name': name,
    'serving_quantity': servingQuantity,
    'serving_quantity_unit': servingQuantityUnit,
    'product_quantity': packageQuantity,
    'product_quantity_unit': packageQuantityUnit,
    'nutriments': nutriments,
  };
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
