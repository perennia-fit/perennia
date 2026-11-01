import 'package:drift/drift.dart' show driftRuntimeOptions;
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
    final now = DateTime.utc(2026, 7, 1);

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

    test('lists Food History first, then never-logged User Foods by name',
        () async {
      for (final name in <String>['banana', 'Apple', 'cherry']) {
        await repositories.nutrition.createUserFood(
          UserFoodDraft(
            name: name,
            nutrientsPer100: _nutrients(energy: 80, protein: 1),
            isLiquid: false,
          ),
        );
      }
      final zucchiniId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Zucchini',
          nutrientsPer100: _nutrients(energy: 17, protein: 1.2),
          isLiquid: false,
        ),
      );
      final mealId = await _meal(repositories, DateTime.utc(2026, 6, 26, 8));
      await _logSnapshot(
        repositories,
        mealId: mealId,
        foodId: zucchiniId,
        name: 'Zucchini',
        foodSource: FoodSource.user,
        portion: _grams(120),
      );
      await _logSnapshot(
        repositories,
        mealId: mealId,
        foodId: 'usda-milk',
        name: 'Milk, whole',
        foodSource: FoodSource.usda,
        portion:
            Portion(value: 250, entered: '250', unit: PortionUnit.milliliter),
        isLiquid: true,
      );
      await _insertUserFoods(database, 60);

      final yourFoods = await addFoodRepository.loadYourFoods(now: now);

      expect(yourFoods.items, hasLength(2 + 3 + 60));
      expect(
        yourFoods.items.take(5).map((item) => item.name),
        ['Zucchini', 'Milk, whole', 'Apple', 'banana', 'cherry'],
      );
      expect(
        yourFoods.items.take(2).map((item) => item.origin),
        everyElement(FoodPickerOrigin.history),
      );
      expect(
        yourFoods.items.skip(2).map((item) => item.origin),
        everyElement(FoodPickerOrigin.userFood),
      );
      expect(yourFoods.items.first.lastPortion?.entered, '120');
      expect(yourFoods.items.first.lastLoggedAt, DateTime.utc(2026, 6, 26, 8));
      expect(yourFoods.items.skip(2).map((item) => item.lastPortion),
          everyElement(isNull));
      expect(
        yourFoods.lastPortionFor(FoodSource.usda, 'usda-milk')?.unit,
        PortionUnit.milliliter,
      );
      expect(yourFoods.lastPortionFor(FoodSource.usda, 'usda-chicken'), isNull);
    });

    test('shows an edited User Food as it is now', () async {
      final foodId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Protein oats',
          nutrientsPer100: _nutrients(energy: 150, protein: 20),
          isLiquid: false,
        ),
      );
      await _logSnapshot(
        repositories,
        mealId: await _meal(repositories, DateTime.utc(2026, 6, 25, 7)),
        foodId: foodId,
        name: 'Protein oats',
        foodSource: FoodSource.user,
        portion: _grams(250),
      );
      await repositories.nutrition.updateUserFood(
        foodId,
        UserFoodDraft(
          name: 'Overnight oats',
          nutrientsPer100: _nutrients(energy: 150, protein: 25),
          isLiquid: false,
        ),
      );

      final yourFoods = await addFoodRepository.loadYourFoods(now: now);
      final item = yourFoods.items.single;

      expect(item.name, 'Overnight oats');
      expect(item.origin, FoodPickerOrigin.history);
      expect(item.nutrientsPer100[NutrientId.protein].value, 25);
      expect(item.lastPortion?.entered, '250');
      for (final filter in <AddFoodPickerFilter>[
        AddFoodPickerFilter.all,
        AddFoodPickerFilter.yours,
      ]) {
        final overnight = await addFoodRepository.search(
          filter: filter,
          query: 'overnight',
          yourFoods: yourFoods,
        );
        final oldName = await addFoodRepository.search(
          filter: filter,
          query: 'protein oats',
          yourFoods: yourFoods,
        );
        expect(overnight.map((item) => item.id), [foodId]);
        expect(overnight.single.lastPortion?.entered, '250');
        expect(oldName, isEmpty);
      }
    });

    test('takes an Open Food Facts row from the device product', () async {
      final repository = RepositoryAddFoodRepository(
        repositories,
        openFoodFacts: _RecordingOpenFoodFactsRepository(
          stored: [_offRecord('9300633603427', 'Weet-Bix Original')],
        ),
      );
      await _logSnapshot(
        repositories,
        mealId: await _meal(repositories, DateTime.utc(2026, 6, 25, 7)),
        foodId: '9300633603427',
        name: 'Weet-Bix',
        foodSource: FoodSource.openFoodFacts,
        portion: _grams(30),
      );

      final item = (await repository.loadYourFoods(now: now)).items.single;

      expect(item.name, 'Weet-Bix Original');
      expect(item.brand, 'Sanitarium');
      expect(item.origin, FoodPickerOrigin.history);
      expect(item.foodSource, FoodSource.openFoodFacts);
      expect(item.nutrientsPer100[NutrientId.energy].value, 352);
      expect(item.lastPortion?.entered, '30');
    });

    test('falls back to the latest snapshot for a product not on the device',
        () async {
      final repository = RepositoryAddFoodRepository(
        repositories,
        openFoodFacts: _RecordingOpenFoodFactsRepository(),
      );
      await _logSnapshot(
        repositories,
        mealId: await _meal(repositories, DateTime.utc(2026, 6, 20, 7)),
        foodId: '5000112637922',
        name: 'Old cola',
        foodSource: FoodSource.openFoodFacts,
        portion: _grams(330),
      );
      await _logSnapshot(
        repositories,
        mealId: await _meal(repositories, DateTime.utc(2026, 6, 25, 7)),
        foodId: '5000112637922',
        name: 'Cola',
        foodSource: FoodSource.openFoodFacts,
        portion: _grams(500),
      );

      final item = (await repository.loadYourFoods(now: now)).items.single;

      expect(item.name, 'Cola');
      expect(item.brand, isNull);
      expect(item.origin, FoodPickerOrigin.history);
      expect(item.nutrientsPer100[NutrientId.energy].value, 50);
      expect(item.lastPortion?.entered, '500');
    });

    test('All with a blank query lists Your foods only, up to 200', () async {
      final openFoodFacts = _RecordingOpenFoodFactsRepository(
        local: [_offRecord('9300633603427', 'Weet-Bix')],
      );
      final repository = RepositoryAddFoodRepository(
        repositories,
        openFoodFacts: openFoodFacts,
      );
      await _insertUserFoods(database, 210);
      final yourFoods = await repository.loadYourFoods(now: now);

      for (final query in <String>['', '   ', '!!!']) {
        final all = await repository.search(
          filter: AddFoodPickerFilter.all,
          query: query,
          yourFoods: yourFoods,
        );
        final yours = await repository.search(
          filter: AddFoodPickerFilter.yours,
          query: query,
          yourFoods: yourFoods,
        );
        expect(all, hasLength(yourFoodsLimit), reason: query);
        expect(all.map((item) => item.origin),
            everyElement(FoodPickerOrigin.userFood));
        expect(yours.map((item) => item.key), all.map((item) => item.key));
      }
      expect(yourFoods.items, hasLength(210));
      expect(openFoodFacts.localQueries, isEmpty);
    });

    test('the Your foods filter matches by name, up to 200', () async {
      await _insertUserFoods(database, 210);
      final yourFoods = await addFoodRepository.loadYourFoods(now: now);

      final snacks = await addFoodRepository.search(
        filter: AddFoodPickerFilter.yours,
        query: 'snack',
        yourFoods: yourFoods,
      );
      final one = await addFoodRepository.search(
        filter: AddFoodPickerFilter.yours,
        query: 'snack 007',
        yourFoods: yourFoods,
      );

      expect(snacks, hasLength(yourFoodsLimit));
      expect(one.map((item) => item.name), ['Snack 007']);
    });

    test('a typed All search lists Your foods, barcode, USDA, then FTS rows',
        () async {
      final openFoodFacts = _RecordingOpenFoodFactsRepository(
        local: [
          _offRecord('123456', 'Granola bar'),
          _offRecord('1234567', 'Cereal bar 123456'),
        ],
      );
      final repository = RepositoryAddFoodRepository(
        repositories,
        openFoodFacts: openFoodFacts,
      );
      await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Snack 123456',
          nutrientsPer100: _nutrients(energy: 300, protein: 10),
          isLiquid: false,
        ),
      );
      final yourFoods = await repository.loadYourFoods(now: now);

      final items = await repository.search(
        filter: AddFoodPickerFilter.all,
        query: '123456',
        yourFoods: yourFoods,
      );

      expect(items.map((item) => (item.origin, item.name)), [
        (FoodPickerOrigin.userFood, 'Snack 123456'),
        (FoodPickerOrigin.openFoodFacts, 'Granola bar'),
        (FoodPickerOrigin.usda, 'Test bar 123456'),
        (FoodPickerOrigin.openFoodFacts, 'Cereal bar 123456'),
      ]);
      expect(openFoodFacts.localQueries, ['123456']);
    });

    test('a logged generic Food is listed once, as its Your foods row',
        () async {
      final repository = RepositoryAddFoodRepository(
        repositories,
        openFoodFacts: _RecordingOpenFoodFactsRepository(
          local: [_offRecord('7394376616037', 'Oat milk', brand: 'Oatly')],
        ),
      );
      await _logSnapshot(
        repositories,
        mealId: await _meal(repositories, DateTime.utc(2026, 6, 25, 7)),
        foodId: 'usda-milk',
        name: 'Milk, whole',
        foodSource: FoodSource.usda,
        portion:
            Portion(value: 200, entered: '200', unit: PortionUnit.milliliter),
        isLiquid: true,
      );
      await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Milk – office fridge',
          nutrientsPer100: _nutrients(energy: 64, protein: 3.3),
          isLiquid: true,
        ),
      );
      final yourFoods = await repository.loadYourFoods(now: now);

      final items = await repository.search(
        filter: AddFoodPickerFilter.all,
        query: 'milk',
        yourFoods: yourFoods,
      );

      expect(items.map((item) => (item.origin, item.name)), [
        (FoodPickerOrigin.history, 'Milk, whole'),
        (FoodPickerOrigin.userFood, 'Milk – office fridge'),
        (FoodPickerOrigin.usda, 'Milk, skim'),
        (FoodPickerOrigin.openFoodFacts, 'Oat milk'),
      ]);
      expect(items.first.lastPortion?.entered, '200');
    });

    test('a barcode in Your foods returns that Your foods row first', () async {
      final product = _offRecord('9300633603427', 'Weet-Bix');
      final repository = RepositoryAddFoodRepository(
        repositories,
        openFoodFacts: _RecordingOpenFoodFactsRepository(
          local: [product],
          stored: [product],
        ),
      );
      await _logSnapshot(
        repositories,
        mealId: await _meal(repositories, DateTime.utc(2026, 6, 25, 7)),
        foodId: '9300633603427',
        name: 'Weet-Bix',
        foodSource: FoodSource.openFoodFacts,
        portion: _grams(30),
      );
      final yourFoods = await repository.loadYourFoods(now: now);

      final items = await repository.search(
        filter: AddFoodPickerFilter.all,
        query: '9300633603427',
        yourFoods: yourFoods,
      );

      expect(items.map((item) => (item.origin, item.id)), [
        (FoodPickerOrigin.history, '9300633603427'),
      ]);
      expect(items.single.lastPortion?.entered, '30');
    });

    test('a typed All search is capped at 50 with at most 20 Your foods rows',
        () async {
      await _insertUserFoods(database, 30);
      final repository = RepositoryAddFoodRepository(
        repositories,
        openFoodFacts: _RecordingOpenFoodFactsRepository(
          local: [
            for (var index = 0; index < 60; index += 1)
              _offRecord('${900000 + index}', 'Snack bar $index'),
          ],
        ),
      );
      final yourFoods = await repository.loadYourFoods(now: now);

      final items = await repository.search(
        filter: AddFoodPickerFilter.all,
        query: 'snack',
        yourFoods: yourFoods,
      );

      expect(items, hasLength(searchResultLimit));
      expect(
        items.where((item) => item.origin == FoodPickerOrigin.userFood),
        hasLength(yourFoodsInSearchLimit),
      );
      expect(items.take(yourFoodsInSearchLimit).map((item) => item.origin),
          everyElement(FoodPickerOrigin.userFood));
    });

    test('a failing device search still returns Your foods and USDA rows',
        () async {
      final repository = RepositoryAddFoodRepository(
        repositories,
        openFoodFacts: _RecordingOpenFoodFactsRepository(failLocal: true),
      );
      await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Milk – office fridge',
          nutrientsPer100: _nutrients(energy: 64, protein: 3.3),
          isLiquid: true,
        ),
      );
      final yourFoods = await repository.loadYourFoods(now: now);

      final items = await repository.search(
        filter: AddFoodPickerFilter.all,
        query: 'milk',
        yourFoods: yourFoods,
      );

      expect(items.map((item) => item.name), [
        'Milk – office fridge',
        'Milk, whole',
        'Milk, skim',
      ]);
      await expectLater(
        repository.search(
          filter: AddFoodPickerFilter.openFoodFacts,
          query: 'milk',
          yourFoods: yourFoods,
        ),
        throwsStateError,
      );
    });

    test('the USDA filter takes Last Portions from Your foods', () async {
      await _logSnapshot(
        repositories,
        mealId: await _meal(repositories, DateTime.utc(2026, 6, 25, 12)),
        foodId: 'usda-chicken',
        name: 'Chicken breast',
        foodSource: FoodSource.usda,
        portion: _grams(150),
      );
      final yourFoods = await addFoodRepository.loadYourFoods(now: now);

      final chicken = await addFoodRepository.search(
        filter: AddFoodPickerFilter.usda,
        query: 'chick',
        yourFoods: yourFoods,
      );
      final everything = await addFoodRepository.search(
        filter: AddFoodPickerFilter.usda,
        query: '',
        yourFoods: yourFoods,
      );

      expect(chicken.map((item) => item.name), [
        'Chicken breast',
        'Chickpeas, boiled',
      ]);
      expect(chicken.map((item) => item.origin),
          everyElement(FoodPickerOrigin.usda));
      expect(chicken.first.lastPortion?.entered, '150');
      expect(chicken.last.lastPortion, isNull);
      expect(everything, hasLength(5));
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
        yourFoods: YourFoods.empty,
      );

      expect(results.map((item) => item.name), <String>['Chicken breast']);
      expect(await database.select(database.activityLog).get(),
          hasLength(activityLogBefore.length));
      expect(await database.select(database.foods).get(),
          hasLength(foodsBefore.length));
      expect(await database.select(database.foodEntries).get(),
          hasLength(entriesBefore.length));
    });

    test('lists Recipes in Your foods with derived serving nutrition',
        () async {
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
      final yourFoods = await addFoodRepository.loadYourFoods(now: now);

      final results = await addFoodRepository.search(
        filter: AddFoodPickerFilter.yours,
        query: 'protein oats',
        yourFoods: yourFoods,
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

    test('keeps the Last Portion separate from current User Food unit gating',
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
      final mealId = await _meal(repositories, DateTime.utc(2026, 6, 25, 19));
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

      final item =
          (await addFoodRepository.loadYourFoods(now: now)).items.single;

      expect(item.servingLabel, isNull);
      expect(item.servingSize, isNull);
      expect(item.availablePortionUnits, isNot(contains(PortionUnit.serving)));
      expect(item.lastPortion?.value, 2);
      expect(item.lastPortion?.entered, '2');
      expect(item.lastPortion?.unit, PortionUnit.serving);
      expect(await database.select(database.metrics).get(), isEmpty);
      expect(await database.select(database.metricReadings).get(), isEmpty);
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
      final firstMealId =
          await _meal(repositories, DateTime.utc(2026, 6, 25, 15));
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
      final yourFoods = await addFoodRepository.loadYourFoods(now: now);
      final recentItem = (await addFoodRepository.search(
        filter: AddFoodPickerFilter.all,
        query: 'yogurt',
        yourFoods: yourFoods,
      ))
          .single;
      final repeatMealId =
          await _meal(repositories, DateTime.utc(2026, 6, 26, 15));

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
      expect(repeatEntry.portion?.value, 1.25);
      expect(repeatEntry.portion?.entered, '1.25');
      expect(repeatEntry.portion?.unit, PortionUnit.serving);
      expect(repeatEntry.name, 'Greek yogurt');
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
      await _logSnapshot(
        repositories,
        mealId: await _meal(repositories, DateTime.utc(2026, 6, 25, 7)),
        foodId: '9300633603427',
        name: 'Weet-Bix',
        foodSource: FoodSource.openFoodFacts,
        portion: _grams(45),
      );
      final yourFoods = await repository.loadYourFoods(now: now);

      final items = await repository.search(
        filter: AddFoodPickerFilter.openFoodFacts,
        query: 'weet',
        yourFoods: yourFoods,
      );
      final blank = await repository.search(
        filter: AddFoodPickerFilter.openFoodFacts,
        query: '',
        yourFoods: yourFoods,
      );

      expect(openFoodFacts.localQueries, <String>['weet']);
      expect(items.single.id, '9300633603427');
      expect(items.single.origin, FoodPickerOrigin.openFoodFacts);
      expect(items.single.brand, 'Sanitarium');
      expect(items.single.isLiveResult, isFalse);
      expect(items.single.lastPortion?.entered, '45');
      expect(blank, isEmpty);
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

        final online = await repository.searchOnline(
          'weet bix',
          yourFoods: YourFoods.empty,
        );
        await repository.lookupBarcode(
          '9300633603427',
          yourFoods: YourFoods.empty,
        );

        expect(openFoodFacts.allowOnline, <bool>[enabled, enabled]);
        expect(online.items.every((item) => item.isLiveResult), isTrue);
        expect(
          online.items.map((item) => item.origin),
          everyElement(FoodPickerOrigin.openFoodFacts),
        );
      }
    });

    test('without an Open Food Facts repository the filter finds nothing',
        () async {
      final items = await addFoodRepository.search(
        filter: AddFoodPickerFilter.openFoodFacts,
        query: 'weet',
        yourFoods: YourFoods.empty,
      );
      final online = await addFoodRepository.searchOnline(
        'weet',
        yourFoods: YourFoods.empty,
      );
      final barcode = await addFoodRepository.lookupBarcode(
        '9300633603427',
        yourFoods: YourFoods.empty,
      );

      expect(items, isEmpty);
      expect(online.status, OnlineSearchStatus.disabled);
      expect(barcode.status, BarcodeLookupOutcome.disabled);
    });
  });
}

PlatformFoodRecord _offRecord(
  String code,
  String name, {
  String brand = 'Sanitarium',
}) {
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
    brand: brand,
    sourceModifiedAt: DateTime.utc(2026, 10, 1),
    scans: 40,
  );
}

/// Records what the add-food repository asks of Open Food Facts.
class _RecordingOpenFoodFactsRepository extends StubOpenFoodFactsRepository {
  _RecordingOpenFoodFactsRepository({
    this.local = const <PlatformFoodRecord>[],
    this.stored = const <PlatformFoodRecord>[],
    this.failLocal = false,
  });

  /// What `searchLocal` returns, whatever the query.
  final List<PlatformFoodRecord> local;

  /// The device's products, by code, for `localProductsByCodes`.
  final List<PlatformFoodRecord> stored;
  final bool failLocal;
  final localQueries = <String>[];
  final allowOnline = <bool>[];

  @override
  Future<List<PlatformFoodRecord>> searchLocal(
    String query, {
    int limit = 50,
  }) async {
    localQueries.add(query);
    if (failLocal) {
      throw StateError('The device food list is unavailable.');
    }
    return local.take(limit).toList();
  }

  @override
  Future<List<PlatformFoodRecord>> localProductsByCodes(
    List<String> codes,
  ) async {
    return [
      for (final product in stored)
        if (codes.contains(product.id)) product,
    ];
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

  static const skimMilkId = 'usda-skim-milk';
  static const testBarId = 'usda-test-bar';

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
        PlatformFoodRecord(
          id: skimMilkId,
          name: 'Milk, skim',
          foodSource: FoodSource.usda,
          nutrientsPer100: _nutrients(energy: 34, protein: 3.37),
          isLiquid: true,
        ),
        PlatformFoodRecord(
          id: testBarId,
          name: 'Test bar 123456',
          foodSource: FoodSource.usda,
          nutrientsPer100: _nutrients(energy: 400, protein: 20),
          isLiquid: false,
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

Future<String> _meal(TrainingRepositories repositories, DateTime startedAt) {
  return repositories.nutrition.createMeal(
    MealDraft(
      mealType: 'Breakfast',
      startedAt: startedAt,
      timezone: 'UTC',
      localDate: NutritionDayDate(
        year: startedAt.year,
        month: startedAt.month,
        day: startedAt.day,
      ),
    ),
  );
}

/// Logs a snapshot the way the picker does.
Future<String> _logSnapshot(
  TrainingRepositories repositories, {
  required String mealId,
  required String foodId,
  required String name,
  required FoodSource foodSource,
  required Portion portion,
  bool isLiquid = false,
}) async {
  final result = await repositories.nutrition.logFoodEntrySnapshot(
    entry: FoodEntrySnapshotDraft(
      mealId: mealId,
      foodId: foodId,
      name: name,
      foodSource: foodSource,
      nutrientsPer100: _nutrients(energy: 50, protein: 1),
      isLiquid: isLiquid,
      portion: portion,
    ),
  );
  return result.foodEntryId;
}

Portion _grams(double value) {
  return Portion(
    value: value,
    entered: value.toString().replaceFirst(RegExp(r'\.0$'), ''),
    unit: PortionUnit.gram,
  );
}

/// User Food rows written straight to the table, for counts that would be
/// slow through the repository.
Future<void> _insertUserFoods(AppDatabase database, int count) async {
  for (var index = 0; index < count; index += 1) {
    final number = index.toString().padLeft(3, '0');
    await database.into(database.foods).insert(
          FoodsCompanion.insert(
            id: 'bulk-$number',
            name: 'Snack $number',
            nutrientValuesJson:
                _nutrients(energy: 100, protein: 1).toJsonString(),
            updatedAt: DateTime.utc(2026, 6, 1),
          ),
        );
  }
}
