import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/nutrition/controllers/nutrition_day_controller.dart';

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

  group('nutrition quick entry repository', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('opens Meal and Food Entry schema without a Nutrition Day table',
        () async {
      final columnsByTable = await database.describeSchema();

      expect(
        columnsByTable.keys,
        containsAll(<String>[
          AppDatabase.mealsTable,
          AppDatabase.mealTypesTable,
          AppDatabase.foodsTable,
          AppDatabase.foodEntriesTable,
        ]),
      );
      expect(columnsByTable.keys, isNot(contains('nutrition_days')));

      expect(
        columnsByTable[AppDatabase.mealTypesTable],
        containsAll(<String>[
          'id',
          'name',
          'sort_order',
          'sync_device_id',
          'sync_previously_synced',
          'updated_at',
          'deleted_at',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.mealsTable],
        containsAll(<String>[
          'id',
          'meal_type',
          'started_at',
          'timezone',
          'local_date',
          'ended_at',
          'sync_device_id',
          'sync_previously_synced',
          'updated_at',
          'deleted_at',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.foodsTable],
        containsAll(<String>[
          'id',
          'name',
          'food_source',
          'nutrient_values_json',
          'is_liquid',
          'serving_label',
          'serving_size',
          'package_size',
          'recipe_ingredients_json',
          'recipe_serving_count',
          'sync_device_id',
          'sync_previously_synced',
          'updated_at',
          'deleted_at',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.foodEntriesTable],
        containsAll(<String>[
          'id',
          'meal_id',
          'entry_kind',
          'position',
          'name',
          'nutrient_values_json',
          'food_id',
          'portion_json',
          'food_source',
          'is_liquid',
          'serving_label',
          'serving_size',
          'package_size',
          'sync_device_id',
          'sync_previously_synced',
          'updated_at',
          'deleted_at',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.foodEntriesTable],
        isNot(contains('started_at')),
      );
      expect(
        columnsByTable[AppDatabase.foodEntriesTable],
        isNot(contains('ended_at')),
      );
    });

    test('logs a Quick Entry into a Meal and reads the Nutrition Day',
        () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      final startedAt = DateTime.utc(2026, 6, 26, 7, 15);

      final result = await repositories.nutrition.logQuickEntry(
        meal: MealDraft(
          mealType: ' Breakfast ',
          startedAt: startedAt,
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
        entry: QuickFoodEntryDraft(
          name: ' Protein shake ',
          nutrients: _energyAndMacros(),
        ),
        actor: 'tester',
      );

      final day = await repositories.nutrition.nutritionDay(localDate);

      expect(day.localDate, localDate);
      expect(day.meals, hasLength(1));
      final meal = day.meals.single.meal;
      expect(meal.id, result.mealId);
      expect(meal.mealType, 'Breakfast');
      expect(meal.startedAt, startedAt);
      expect(meal.timezone, 'Australia/Brisbane');
      expect(meal.localDate, localDate);
      expect(meal.endedAt, isNull);
      expect(meal.deletedAt, isNull);

      final entry = day.meals.single.entries.single;
      expect(entry.id, result.foodEntryId);
      expect(entry.mealId, result.mealId);
      expect(entry.kind, FoodEntryKind.quickEntry);
      expect(entry.position, 0);
      expect(entry.name, 'Protein shake');
      expect(entry.foodId, isNull);
      expect(entry.portion, isNull);
      expect(entry.foodSource, isNull);
      expect(entry.isLiquid, isNull);
      expect(entry.servingLabel, isNull);
      expect(entry.servingSize, isNull);
      expect(entry.packageSize, isNull);
      expect(entry.nutrients[NutrientId.energy].value, 240);
      expect(entry.nutrients[NutrientId.energy].entered, '240');
      expect(entry.nutrients[NutrientId.energy].unit, NutrientUnit.kilocalorie);
      expect(entry.nutrients[NutrientId.protein].value, 32);
      expect(entry.nutrients[NutrientId.carbohydrate].value, 12);
      expect(entry.nutrients[NutrientId.fat].value, 4);
      expect(entry.nutrients[NutrientId.fiber].status,
          NutrientValueStatus.unknown);
      expect(entry.resolvedBaseQuantity, isNull);
      expect(entry.resolvedNutrients[NutrientId.energy].value, 240);

      final storedEntry = await (database.select(database.foodEntries)
            ..where((row) => row.id.equals(result.foodEntryId)))
          .getSingle();
      expect(storedEntry.foodSource, isNull);
      expect(storedEntry.isLiquid, isNull);
      expect(storedEntry.servingLabel, isNull);
      expect(storedEntry.servingSize, isNull);
      expect(storedEntry.packageSize, isNull);
      final nutrientJson =
          jsonDecode(storedEntry.nutrientValuesJson) as Map<String, Object?>;
      expect(
        nutrientJson.keys.toSet(),
        NutrientId.values.map((id) => id.storageKey).toSet(),
      );

      expect(await database.select(database.metrics).get(), isEmpty);
      expect(await database.select(database.metricReadings).get(), isEmpty);
    });

    test('applies the Meal and Quick Entry as exactly one Activity Log Batch',
        () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      final result = await repositories.nutrition.logQuickEntry(
        meal: MealDraft(
          mealType: 'Lunch',
          startedAt: DateTime.utc(2026, 6, 26, 12),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
        entry: QuickFoodEntryDraft(
          name: 'Rice bowl',
          nutrients: _energyAndMacros(),
        ),
        actor: 'tester',
      );

      final batch = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == result.batchId)
          .toList(growable: false);

      expect(batch, hasLength(2));
      expect(batch.map((entry) => entry.batchId).toSet(), hasLength(1));
      expect(batch.map((entry) => entry.actor), everyElement('tester'));
      expect(
        batch.map((entry) => entry.entityTable).toSet(),
        <String>{
          AppDatabase.mealsTable,
          AppDatabase.foodEntriesTable,
        },
      );
      expect(batch.map((entry) => entry.beforeImage), everyElement(isNull));

      final mealLog = batch.singleWhere(
        (entry) => entry.entityTable == AppDatabase.mealsTable,
      );
      expect(mealLog.entityId, result.mealId);
      expect(mealLog.afterImage?['meal_type'], 'Lunch');
      expect(mealLog.afterImage?['local_date'], localDate.storageValue);

      final entryLog = batch.singleWhere(
        (entry) => entry.entityTable == AppDatabase.foodEntriesTable,
      );
      expect(entryLog.entityId, result.foodEntryId);
      expect(entryLog.afterImage?['entry_kind'], FoodEntryKind.quickEntry.name);
      expect(entryLog.afterImage?['name'], 'Rice bowl');
      expect(entryLog.afterImage?['food_id'], isNull);
      expect(entryLog.afterImage?['portion_json'], isNull);
      expect(entryLog.afterImage?['food_source'], isNull);
      expect(entryLog.afterImage?['is_liquid'], isNull);
      expect(entryLog.afterImage?['serving_label'], isNull);
      expect(entryLog.afterImage?['serving_size'], isNull);
      expect(entryLog.afterImage?['package_size'], isNull);
      expect(entryLog.afterImage?['nutrient_values_json'], isA<String>());
    });

    test('hard-rejects impossible Quick Entry nutrients before writing',
        () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);

      expect(
        () => repositories.nutrition.logQuickEntry(
          meal: MealDraft(
            mealType: 'Snack',
            startedAt: DateTime.utc(2026, 6, 26, 10),
            timezone: 'Australia/Brisbane',
            localDate: localDate,
          ),
          entry: QuickFoodEntryDraft(
            name: 'Impossible snack',
            nutrients: _energyAndMacros(energy: 10001),
          ),
          actor: 'tester',
        ),
        throwsA(
          isA<NutrientValidationException>().having(
            (error) => error.errors.single.rule,
            'rule',
            'nutrient_energy_max_kilocalories',
          ),
        ),
      );

      final day = await repositories.nutrition.nutritionDay(localDate);
      expect(day.meals, isEmpty);
    });

    test('soft-warns Atwater mismatch while persisting Quick Entry', () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);

      final result = await repositories.nutrition.logQuickEntry(
        meal: MealDraft(
          mealType: 'Snack',
          startedAt: DateTime.utc(2026, 6, 26, 10),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
        entry: QuickFoodEntryDraft(
          name: 'Loose label',
          nutrients: _energyAndMacros(
            energy: 1000,
            protein: 10,
            carbohydrate: 10,
            fat: 10,
          ),
        ),
        actor: 'tester',
      );

      expect(
        result.warnings.map((warning) => warning.rule).toList(growable: false),
        <String>['energy_atwater_mismatch'],
      );
      final day = await repositories.nutrition.nutritionDay(localDate);
      expect(day.meals.single.entries.single.id, result.foodEntryId);
    });

    test('does not warn on Atwater mismatch when a macro is unknown', () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);

      final result = await repositories.nutrition.logQuickEntry(
        meal: MealDraft(
          mealType: 'Snack',
          startedAt: DateTime.utc(2026, 6, 26, 10),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
        entry: QuickFoodEntryDraft(
          name: 'Unknown carbs',
          nutrients: NutrientVector.energyAndMacros(
            energy: NutrientAmount.complete(
              value: 1000,
              entered: '1000',
              unit: NutrientUnit.kilocalorie,
            ),
            protein: NutrientAmount.complete(
              value: 10,
              entered: '10',
              unit: NutrientUnit.gram,
            ),
            carbohydrate: NutrientAmount.unknown(NutrientUnit.gram),
            fat: NutrientAmount.complete(
              value: 10,
              entered: '10',
              unit: NutrientUnit.gram,
            ),
          ),
        ),
        actor: 'tester',
      );

      expect(result.warnings, isEmpty);
      final entry = (await repositories.nutrition.nutritionDay(localDate))
          .meals
          .single
          .entries
          .single;
      expect(entry.nutrients[NutrientId.carbohydrate].status,
          NutrientValueStatus.unknown);
    });

    test('creates editable User Food with gated Portion units', () async {
      final foodId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: ' Greek yogurt ',
          nutrientsPer100: _foodPer100(),
          isLiquid: false,
          servingLabel: ' cup ',
          servingSize: 170,
          packageSize: 907,
        ),
        actor: 'tester',
      );

      final food = await repositories.nutrition.getUserFoodById(foodId);

      expect(food, isNotNull);
      expect(food!.name, 'Greek yogurt');
      expect(food.foodSource, FoodSource.user);
      expect(food.nutrientsPer100[NutrientId.energy].value, 100);
      expect(food.nutrientsPer100[NutrientId.protein].value, 10);
      expect(food.isLiquid, isFalse);
      expect(food.servingLabel, 'cup');
      expect(food.servingSize, 170);
      expect(food.packageSize, 907);
      expect(food.availablePortionUnits, <PortionUnit>[
        PortionUnit.gram,
        PortionUnit.ounce,
        PortionUnit.serving,
        PortionUnit.package,
      ]);
      expect(
        await repositories.nutrition.availablePortionUnits(foodId),
        food.availablePortionUnits,
      );
      expect(
        (await repositories.nutrition.listActiveUserFoods()).single.id,
        foodId,
      );
    });

    test('keeps the Food Source registry curated', () {
      expect(
          FoodSource.values,
          containsAll(<FoodSource>[
            FoodSource.usda,
            FoodSource.user,
          ]));
      expect(
        () => FoodSource.values.byName('community'),
        throwsArgumentError,
      );
    });

    test('forks read-only USDA Food into editable User Food on edit', () async {
      final source =
          await repositories.platformFoods.getUsdaFoodById('usda-fdc-171077');

      final foodId = await repositories.nutrition.forkUsdaFoodToUserFood(
        'usda-fdc-171077',
        edits: const UserFoodForkDraft(name: 'Meal-prep chicken breast'),
        actor: 'nutrition-agent',
      );

      final food = await repositories.nutrition.getUserFoodById(foodId);
      final unchangedSource =
          await repositories.platformFoods.getUsdaFoodById('usda-fdc-171077');
      final foodRows = await database.select(database.foods).get();
      final activity = await repositories.activityLog.listEntries();

      expect(source, isNotNull);
      expect(food, isNotNull);
      expect(food!.name, 'Meal-prep chicken breast');
      expect(food.foodSource, FoodSource.user);
      expect(food.isLiquid, source!.isLiquid);
      expect(food.servingLabel, source.servingLabel);
      expect(food.servingSize, source.servingSize);
      expect(food.packageSize, source.packageSize);
      expect(
        food.nutrientsPer100[NutrientId.vitaminB6].value,
        source.nutrientsPer100[NutrientId.vitaminB6].value,
      );
      expect(
        food.nutrientsPer100[NutrientId.selenium].value,
        source.nutrientsPer100[NutrientId.selenium].value,
      );

      expect(unchangedSource?.name, 'Chicken breast');
      expect(unchangedSource?.foodSource, FoodSource.usda);
      expect(foodRows, hasLength(1));
      expect(foodRows.single.foodSource, FoodSource.user.name);

      expect(activity, hasLength(1));
      final entry = activity.single;
      expect(entry.actor, 'nutrition-agent');
      expect(entry.entityTable, AppDatabase.foodsTable);
      expect(entry.afterImage?['food_source'], FoodSource.user.name);
      expect(entry.afterImage?['name'], 'Meal-prep chicken breast');
    });

    test('archives User Food without deleting rows or logged snapshots',
        () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      final foodId = await repositories.nutrition.forkUsdaFoodToUserFood(
        'usda-fdc-171077',
        actor: 'tester',
      );
      final mealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Lunch',
          startedAt: DateTime.utc(2026, 6, 26, 12),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
      );
      final result = await repositories.nutrition.logFoodEntry(
        entry: FoodEntryDraft(
          mealId: mealId,
          foodId: foodId,
          portion: Portion(
            value: 100,
            entered: '100',
            unit: PortionUnit.gram,
          ),
        ),
      );

      await repositories.nutrition.archiveUserFood(foodId, actor: 'tester');

      final archived = await repositories.nutrition.getUserFoodById(foodId);
      final foodRows = await database.select(database.foods).get();
      final entryRows = await database.select(database.foodEntries).get();
      final entry =
          await repositories.nutrition.getFoodEntryById(result.foodEntryId);

      expect(archived?.deletedAt, isNotNull);
      expect(await repositories.nutrition.listActiveUserFoods(), isEmpty);
      expect(foodRows, hasLength(1));
      expect(entryRows, hasLength(1));
      expect(entryRows.single.deletedAt, isNull);
      expect(entry?.foodId, foodId);
      expect(entry?.foodSource, FoodSource.user);
      expect(entry?.name, 'Chicken breast');
    });

    test('blocks duplicate active User Foods case-insensitively', () async {
      final firstId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Greek yogurt',
          nutrientsPer100: _foodPer100(),
          isLiquid: false,
        ),
        actor: 'tester',
      );

      await expectLater(
        repositories.nutrition.createUserFood(
          UserFoodDraft(
            name: ' greek YOGURT ',
            nutrientsPer100: _foodPer100(energy: 90),
            isLiquid: false,
          ),
          actor: 'tester',
        ),
        throwsA(isA<DuplicateUserFoodNameException>()),
      );

      await repositories.nutrition.archiveUserFood(firstId, actor: 'tester');
      final secondId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Greek yogurt',
          nutrientsPer100: _foodPer100(energy: 90),
          isLiquid: false,
        ),
        actor: 'tester',
      );

      expect(secondId, isNot(firstId));
      expect(await repositories.nutrition.listActiveUserFoods(), hasLength(1));
    });

    test('creates Recipe as User Food with derived unknown-aware nutrition',
        () async {
      final oatsId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Oats',
          nutrientsPer100: _foodPer100(
            energy: 100,
            protein: 10,
            carbohydrate: 20,
            fat: 5,
          ),
          isLiquid: false,
        ),
        actor: 'tester',
      );
      final powderId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Mystery powder',
          nutrientsPer100: _foodPer100WithUnknownProtein(
            energy: 200,
            carbohydrate: 0,
            fat: 0,
          ),
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
            _recipeIngredient(
              oats,
              Portion(value: 100, entered: '100', unit: PortionUnit.gram),
            ),
            _recipeIngredient(
              powder,
              Portion(value: 50, entered: '50', unit: PortionUnit.gram),
            ),
          ],
        ),
        actor: 'tester',
      );

      final recipe = await repositories.nutrition.getUserFoodById(recipeId);
      final stored = await (database.select(database.foods)
            ..where((row) => row.id.equals(recipeId)))
          .getSingle();
      final activity = await repositories.activityLog.listEntries();

      expect(recipe, isNotNull);
      expect(recipe!.name, 'Protein oats');
      expect(recipe.foodSource, FoodSource.user);
      expect(recipe.isRecipe, isTrue);
      expect(recipe.recipeServingCount, 2);
      expect(recipe.recipeIngredients, hasLength(2));
      expect(recipe.isLiquid, isFalse);
      expect(recipe.servingLabel, 'serving');
      expect(recipe.servingSize, closeTo(75, 0.000001));
      expect(recipe.packageSize, isNull);
      expect(recipe.availablePortionUnits, <PortionUnit>[
        PortionUnit.gram,
        PortionUnit.ounce,
        PortionUnit.serving,
      ]);
      expect(
        recipe.nutrientsPer100[NutrientId.energy].value,
        closeTo(133.333333, 0.000001),
      );
      expect(
        recipe.nutrientsPer100[NutrientId.carbohydrate].value,
        closeTo(13.333333, 0.000001),
      );
      expect(
        recipe.nutrientsPer100[NutrientId.protein].status,
        NutrientValueStatus.unknown,
      );

      expect(stored.foodSource, FoodSource.user.name);
      expect(stored.recipeIngredientsJson, isNotNull);
      expect(stored.recipeServingCount, 2);
      expect(
        activity.last.afterImage?['recipe_ingredients_json'],
        isA<String>(),
      );
      expect(activity.last.afterImage?['recipe_serving_count'], 2);
    });

    test('logs Recipe through Log Portion as an independent snapshot',
        () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      final mealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Breakfast',
          startedAt: DateTime.utc(2026, 6, 26, 8),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
        actor: 'tester',
      );
      final oatsId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Oats',
          nutrientsPer100: _foodPer100(
            energy: 100,
            protein: 10,
            carbohydrate: 20,
            fat: 5,
          ),
          isLiquid: false,
        ),
      );
      final powderId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Mystery powder',
          nutrientsPer100: _foodPer100WithUnknownProtein(
            energy: 200,
            carbohydrate: 0,
            fat: 0,
          ),
          isLiquid: false,
        ),
      );
      final oats = (await repositories.nutrition.getUserFoodById(oatsId))!;
      final powder = (await repositories.nutrition.getUserFoodById(powderId))!;
      final recipeId = await repositories.nutrition.createRecipe(
        RecipeDraft(
          name: 'Protein oats',
          servingCount: 2,
          ingredients: <RecipeIngredient>[
            _recipeIngredient(
              oats,
              Portion(value: 100, entered: '100', unit: PortionUnit.gram),
            ),
            _recipeIngredient(
              powder,
              Portion(value: 50, entered: '50', unit: PortionUnit.gram),
            ),
          ],
        ),
      );

      final result = await repositories.nutrition.logFoodEntry(
        entry: FoodEntryDraft(
          mealId: mealId,
          foodId: recipeId,
          portion: Portion(
            value: 1,
            entered: '1',
            unit: PortionUnit.serving,
          ),
        ),
      );
      await repositories.nutrition.updateUserFood(
        oatsId,
        UserFoodDraft(
          name: 'Edited oats',
          nutrientsPer100: _foodPer100(energy: 999, protein: 99),
          isLiquid: false,
        ),
      );
      await repositories.nutrition.archiveUserFood(powderId);

      final entry =
          await repositories.nutrition.getFoodEntryById(result.foodEntryId);
      final day = await repositories.nutrition.nutritionDay(localDate);

      expect(day.meals.single.entries.single.id, result.foodEntryId);
      expect(entry, isNotNull);
      expect(entry!.name, 'Protein oats');
      expect(entry.foodId, recipeId);
      expect(entry.foodSource, FoodSource.user);
      expect(entry.servingLabel, 'serving');
      expect(entry.servingSize, closeTo(75, 0.000001));
      expect(entry.packageSize, isNull);
      expect(entry.resolvedBaseQuantity, closeTo(75, 0.000001));
      expect(
        entry.nutrients[NutrientId.energy].value,
        closeTo(133.333333, 0.000001),
      );
      expect(
        entry.resolvedNutrients[NutrientId.energy].value,
        closeTo(100, 0.000001),
      );
      expect(
        entry.resolvedNutrients[NutrientId.protein].status,
        NutrientValueStatus.unknown,
      );
    });

    test('archives Recipe without cascading to ingredients or history',
        () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      final mealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Dinner',
          startedAt: DateTime.utc(2026, 6, 26, 19),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
      );
      final riceId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Rice',
          nutrientsPer100: _foodPer100(energy: 200, protein: 4),
          isLiquid: false,
        ),
      );
      final beansId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Beans',
          nutrientsPer100: _foodPer100(energy: 120, protein: 8),
          isLiquid: false,
        ),
      );
      final rice = (await repositories.nutrition.getUserFoodById(riceId))!;
      final beans = (await repositories.nutrition.getUserFoodById(beansId))!;
      final recipeId = await repositories.nutrition.createRecipe(
        RecipeDraft(
          name: 'Rice and beans',
          servingCount: 4,
          ingredients: <RecipeIngredient>[
            _recipeIngredient(
              rice,
              Portion(value: 300, entered: '300', unit: PortionUnit.gram),
            ),
            _recipeIngredient(
              beans,
              Portion(value: 200, entered: '200', unit: PortionUnit.gram),
            ),
          ],
        ),
      );
      final result = await repositories.nutrition.logFoodEntry(
        entry: FoodEntryDraft(
          mealId: mealId,
          foodId: recipeId,
          portion: Portion(
            value: 1,
            entered: '1',
            unit: PortionUnit.serving,
          ),
        ),
      );

      await repositories.nutrition.archiveUserFood(recipeId, actor: 'tester');

      final archivedRecipe =
          await repositories.nutrition.getUserFoodById(recipeId);
      final riceAfter = await repositories.nutrition.getUserFoodById(riceId);
      final beansAfter = await repositories.nutrition.getUserFoodById(beansId);
      final entry =
          await repositories.nutrition.getFoodEntryById(result.foodEntryId);
      final foodRows = await database.select(database.foods).get();

      expect(archivedRecipe?.isRecipe, isTrue);
      expect(archivedRecipe?.deletedAt, isNotNull);
      expect(riceAfter?.deletedAt, isNull);
      expect(beansAfter?.deletedAt, isNull);
      expect(entry?.deletedAt, isNull);
      expect(entry?.name, 'Rice and beans');
      expect(foodRows, hasLength(3));
      expect(
        (await repositories.nutrition.listActiveUserFoods())
            .map((food) => food.id),
        unorderedEquals(<String>[riceId, beansId]),
      );
    });

    test('rejects Recipe nesting for flat v1 composition', () async {
      final oatsId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Oats',
          nutrientsPer100: _foodPer100(),
          isLiquid: false,
        ),
      );
      final oats = (await repositories.nutrition.getUserFoodById(oatsId))!;
      final recipeId = await repositories.nutrition.createRecipe(
        RecipeDraft(
          name: 'Base oats',
          servingCount: 1,
          ingredients: <RecipeIngredient>[
            _recipeIngredient(
              oats,
              Portion(value: 100, entered: '100', unit: PortionUnit.gram),
            ),
          ],
        ),
      );
      final recipe = (await repositories.nutrition.getUserFoodById(recipeId))!;

      await expectLater(
        repositories.nutrition.createRecipe(
          RecipeDraft(
            name: 'Nested oats',
            servingCount: 1,
            ingredients: <RecipeIngredient>[
              _recipeIngredient(
                recipe,
                Portion(value: 1, entered: '1', unit: PortionUnit.serving),
              ),
            ],
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('logs Food Entry snapshot and derives nutrients on read', () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      final mealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Breakfast',
          startedAt: DateTime.utc(2026, 6, 26, 8),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
        actor: 'tester',
      );
      final foodId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Greek yogurt',
          nutrientsPer100: _foodPer100(),
          isLiquid: false,
          servingLabel: 'cup',
          servingSize: 170,
          packageSize: 907,
        ),
        actor: 'tester',
      );

      final result = await repositories.nutrition.logFoodEntry(
        entry: FoodEntryDraft(
          mealId: mealId,
          foodId: foodId,
          portion: Portion(
            value: 1.5,
            entered: '1.5',
            unit: PortionUnit.serving,
          ),
        ),
        actor: 'tester',
      );

      final day = await repositories.nutrition.nutritionDay(localDate);
      final entry = day.meals.single.entries.single;
      expect(entry.id, result.foodEntryId);
      expect(entry.kind, FoodEntryKind.food);
      expect(entry.name, 'Greek yogurt');
      expect(entry.foodId, foodId);
      expect(entry.portion?.value, 1.5);
      expect(entry.portion?.entered, '1.5');
      expect(entry.portion?.unit, PortionUnit.serving);
      expect(entry.foodSource, FoodSource.user);
      expect(entry.isLiquid, isFalse);
      expect(entry.servingLabel, 'cup');
      expect(entry.servingSize, 170);
      expect(entry.packageSize, 907);
      expect(entry.nutrients[NutrientId.energy].value, 100);
      expect(entry.resolvedBaseQuantity, closeTo(255, 0.000001));
      expect(
        entry.resolvedNutrients[NutrientId.energy].value,
        closeTo(255, 0.000001),
      );
      expect(entry.resolvedNutrients[NutrientId.energy].entered, '255');
      expect(
        entry.resolvedNutrients[NutrientId.protein].value,
        closeTo(25.5, 0.000001),
      );
      expect(
        entry.resolvedNutrients[NutrientId.carbohydrate].value,
        closeTo(76.5, 0.000001),
      );
      expect(
        entry.resolvedNutrients[NutrientId.fat].value,
        closeTo(10.2, 0.000001),
      );

      final storedEntry = await (database.select(database.foodEntries)
            ..where((row) => row.id.equals(result.foodEntryId)))
          .getSingle();
      expect(storedEntry.name, 'Greek yogurt');
      expect(
          storedEntry.nutrientValuesJson,
          (await (database.select(database.foods)
                    ..where((row) => row.id.equals(foodId)))
                  .getSingle())
              .nutrientValuesJson);
      expect(storedEntry.foodSource, FoodSource.user.name);
      expect(storedEntry.isLiquid, isFalse);
      expect(storedEntry.servingLabel, 'cup');
      expect(storedEntry.servingSize, 170);
      expect(storedEntry.packageSize, 907);

      final batch = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == result.batchId)
          .toList(growable: false);
      expect(batch, hasLength(1));
      final entryLog = batch.single;
      expect(entryLog.entityTable, AppDatabase.foodEntriesTable);
      expect(entryLog.beforeImage, isNull);
      expect(entryLog.afterImage?['food_id'], foodId);
      expect(entryLog.afterImage?['food_source'], FoodSource.user.name);
      expect(entryLog.afterImage?['is_liquid'], isFalse);
      expect(entryLog.afterImage?['serving_label'], 'cup');
      expect(entryLog.afterImage?['serving_size'], 170);
      expect(entryLog.afterImage?['package_size'], 907);

      expect(await database.select(database.metrics).get(), isEmpty);
      expect(await database.select(database.metricReadings).get(), isEmpty);
    });

    test('logs selected USDA Food snapshot without writing catalogue rows',
        () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      final mealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Lunch',
          startedAt: DateTime.utc(2026, 6, 26, 12),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
        actor: 'tester',
      );
      final food =
          await repositories.platformFoods.getUsdaFoodById('usda-fdc-171077');
      final source = food!;

      final result = await repositories.nutrition.logFoodEntrySnapshot(
        entry: FoodEntrySnapshotDraft(
          mealId: mealId,
          foodId: source.id,
          name: source.name,
          foodSource: source.foodSource,
          nutrientsPer100: source.nutrientsPer100,
          isLiquid: source.isLiquid,
          servingLabel: source.servingLabel,
          servingSize: source.servingSize,
          packageSize: source.packageSize,
          portion: Portion(
            value: 2,
            entered: '2',
            unit: PortionUnit.serving,
          ),
        ),
        actor: 'tester',
      );

      final entry =
          await repositories.nutrition.getFoodEntryById(result.foodEntryId);
      expect(entry, isNotNull);
      expect(entry!.foodId, 'usda-fdc-171077');
      expect(entry.name, 'Chicken breast');
      expect(entry.foodSource, FoodSource.usda);
      expect(entry.isLiquid, isFalse);
      expect(entry.servingLabel, 'piece');
      expect(entry.servingSize, 86);
      expect(entry.packageSize, isNull);
      expect(entry.nutrients[NutrientId.energy].value, 165);
      expect(entry.nutrients[NutrientId.selenium].value, 27.6);
      expect(entry.resolvedBaseQuantity, 172);
      expect(
        entry.resolvedNutrients[NutrientId.energy].value,
        closeTo(283.8, 0.000001),
      );
      expect(entry.resolvedNutrients[NutrientId.energy].entered, '283.8');

      final storedEntry = await (database.select(database.foodEntries)
            ..where((row) => row.id.equals(result.foodEntryId)))
          .getSingle();
      expect(storedEntry.foodSource, FoodSource.usda.name);
      expect(
        storedEntry.nutrientValuesJson,
        source.nutrientsPer100.toJsonString(),
      );
      expect(await database.select(database.foods).get(), isEmpty);

      final batch = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == result.batchId)
          .toList(growable: false);
      expect(batch, hasLength(1));
      expect(batch.single.entityTable, AppDatabase.foodEntriesTable);
      expect(batch.single.afterImage?['food_source'], FoodSource.usda.name);
      expect(batch.single.afterImage?['portion_json'], isA<String>());
    });

    test('repeated Open Food Facts logs stay entry-only without catalogue rows',
        () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 27);
      final mealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Snack',
          startedAt: DateTime.utc(2026, 6, 27, 15),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
      );

      final first = await repositories.nutrition.logFoodEntrySnapshot(
        entry: _offSnapshotDraft(mealId),
      );
      final second = await repositories.nutrition.logFoodEntrySnapshot(
        entry: _offSnapshotDraft(mealId),
      );

      final entries = await repositories.nutrition.listActiveEntriesForMeal(
        mealId,
      );
      final foodRows = await database.select(database.foods).get();
      final activity = await repositories.activityLog.listEntries();

      expect(entries.map((entry) => entry.id), <String>[
        first.foodEntryId,
        second.foodEntryId,
      ]);
      expect(
        entries.map((entry) => entry.foodSource),
        everyElement(FoodSource.openFoodFacts),
      );
      expect(foodRows, isEmpty);
      expect(
        activity.map((entry) => entry.entityTable),
        isNot(contains(AppDatabase.foodsTable)),
      );
      expect(await database.select(database.metrics).get(), isEmpty);
      expect(await database.select(database.metricReadings).get(), isEmpty);
    });

    test('selected User Food snapshot survives later catalogue edits',
        () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      final mealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Dinner',
          startedAt: DateTime.utc(2026, 6, 26, 19),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
      );
      final foodId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Rice',
          nutrientsPer100: _foodPer100(energy: 200, protein: 4),
          isLiquid: false,
          servingLabel: 'bowl',
          servingSize: 150,
        ),
      );
      final food = (await repositories.nutrition.getUserFoodById(foodId))!;

      final result = await repositories.nutrition.logFoodEntrySnapshot(
        entry: FoodEntrySnapshotDraft(
          mealId: mealId,
          foodId: food.id,
          name: food.name,
          foodSource: food.foodSource,
          nutrientsPer100: food.nutrientsPer100,
          isLiquid: food.isLiquid,
          servingLabel: food.servingLabel,
          servingSize: food.servingSize,
          packageSize: food.packageSize,
          portion: Portion(
            value: 2,
            entered: '2',
            unit: PortionUnit.serving,
          ),
        ),
      );

      await repositories.nutrition.updateUserFood(
        foodId,
        UserFoodDraft(
          name: 'Edited rice',
          nutrientsPer100: _foodPer100(energy: 999, protein: 99),
          isLiquid: true,
          servingLabel: 'cup',
          servingSize: 50,
          packageSize: 250,
        ),
      );
      await repositories.nutrition.archiveUserFood(foodId);

      final entry =
          await repositories.nutrition.getFoodEntryById(result.foodEntryId);
      expect(entry, isNotNull);
      expect(entry!.name, 'Rice');
      expect(entry.foodSource, FoodSource.user);
      expect(entry.isLiquid, isFalse);
      expect(entry.servingLabel, 'bowl');
      expect(entry.servingSize, 150);
      expect(entry.packageSize, isNull);
      expect(entry.nutrients[NutrientId.energy].value, 200);
      expect(entry.nutrients[NutrientId.protein].value, 4);
      expect(entry.resolvedBaseQuantity, 300);
      expect(entry.resolvedNutrients[NutrientId.energy].value, 600);
      expect(entry.resolvedNutrients[NutrientId.protein].value, 12);
    });

    test('soft-warns huge Food Entry Portion while persisting entry', () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      final mealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Lunch',
          startedAt: DateTime.utc(2026, 6, 26, 12),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
      );
      final foodId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Balanced rice',
          nutrientsPer100: _foodPer100(
            energy: 196,
            protein: 10,
            carbohydrate: 30,
            fat: 4,
          ),
          isLiquid: false,
        ),
      );

      final result = await repositories.nutrition.logFoodEntry(
        entry: FoodEntryDraft(
          mealId: mealId,
          foodId: foodId,
          portion: Portion(
            value: 2500,
            entered: '2500',
            unit: PortionUnit.gram,
          ),
        ),
      );

      expect(
        result.warnings.map((warning) => warning.rule).toList(growable: false),
        <String>['portion_size_improbable'],
      );
      final entry =
          await repositories.nutrition.getFoodEntryById(result.foodEntryId);
      expect(entry!.resolvedBaseQuantity, 2500);
    });

    test('computes Nutrition Day and Meal totals unknown-aware', () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      await repositories.nutrition.logQuickEntry(
        meal: MealDraft(
          mealType: 'Breakfast',
          startedAt: DateTime.utc(2026, 6, 26, 8),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
        entry: QuickFoodEntryDraft(
          name: 'Known calories, missing carbs',
          nutrients: NutrientVector.full(<NutrientId, NutrientAmount>{
            NutrientId.energy: NutrientAmount.complete(
              value: 100,
              entered: '100',
              unit: NutrientUnit.kilocalorie,
            ),
            NutrientId.protein: NutrientAmount.complete(
              value: 10,
              entered: '10',
              unit: NutrientUnit.gram,
            ),
            NutrientId.fat: NutrientAmount.complete(
              value: 3,
              entered: '3',
              unit: NutrientUnit.gram,
            ),
          }),
        ),
      );
      final lunchId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Lunch',
          startedAt: DateTime.utc(2026, 6, 26, 12),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
      );
      final foodId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Rice bowl',
          nutrientsPer100: _foodPer100(
            energy: 200,
            protein: 20,
            carbohydrate: 40,
            fat: 10,
          ),
          isLiquid: false,
        ),
      );
      await repositories.nutrition.logFoodEntry(
        entry: FoodEntryDraft(
          mealId: lunchId,
          foodId: foodId,
          portion: Portion(
            value: 50,
            entered: '50',
            unit: PortionUnit.gram,
          ),
        ),
      );

      final day = await repositories.nutrition.nutritionDay(localDate);

      expect(day.meals, hasLength(2));
      final breakfast = day.meals.first;
      final lunch = day.meals.last;
      expect(breakfast.meal.mealType, 'Breakfast');
      expect(lunch.meal.mealType, 'Lunch');

      expect(breakfast.totals[NutrientId.energy].value, 100);
      expect(breakfast.totals[NutrientId.energy].isComplete, isTrue);
      expect(breakfast.totals[NutrientId.carbohydrate].value, 0);
      expect(breakfast.totals[NutrientId.carbohydrate].isIncomplete, isTrue);

      expect(lunch.totals[NutrientId.energy].value, 100);
      expect(lunch.totals[NutrientId.protein].value, 10);
      expect(lunch.totals[NutrientId.carbohydrate].value, 20);
      expect(lunch.totals[NutrientId.carbohydrate].isComplete, isTrue);
      expect(lunch.totals[NutrientId.fat].value, 5);

      expect(day.totals[NutrientId.energy].value, 200);
      expect(day.totals[NutrientId.energy].isComplete, isTrue);
      expect(day.totals[NutrientId.protein].value, 20);
      expect(
        day.totals[NutrientId.carbohydrate].value,
        closeTo(20, 0.000001),
      );
      expect(day.totals[NutrientId.carbohydrate].isIncomplete, isTrue);
      expect(day.totals[NutrientId.fat].value, 8);
      expect(day.totals[NutrientId.fiber].isIncomplete, isTrue);

      final columnsByTable = await database.describeSchema();
      expect(columnsByTable[AppDatabase.mealsTable], isNot(contains('totals')));
      expect(
        columnsByTable[AppDatabase.foodEntriesTable],
        isNot(contains('resolved_energy')),
      );
      expect(await database.select(database.metrics).get(), isEmpty);
      expect(await database.select(database.metricReadings).get(), isEmpty);
    });

    test('stores multiple same-type Meals as distinct occasions', () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);

      final first = await repositories.nutrition.logQuickEntry(
        meal: MealDraft(
          mealType: 'Snack',
          startedAt: DateTime.utc(2026, 6, 26, 10),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
        entry: QuickFoodEntryDraft(
          name: 'Apple',
          nutrients: _energyAndMacros(energy: 80),
        ),
        actor: 'tester',
      );
      final second = await repositories.nutrition.logQuickEntry(
        meal: MealDraft(
          mealType: 'Snack',
          startedAt: DateTime.utc(2026, 6, 26, 15),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
        entry: QuickFoodEntryDraft(
          name: 'Yogurt',
          nutrients: _energyAndMacros(energy: 120),
        ),
        actor: 'tester',
      );
      final third = await repositories.nutrition.logQuickEntry(
        meal: MealDraft(
          mealType: 'Snack',
          startedAt: DateTime.utc(2026, 6, 26, 21),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
        entry: QuickFoodEntryDraft(
          name: 'Toast',
          nutrients: _energyAndMacros(energy: 160),
        ),
        actor: 'tester',
      );

      final day = await repositories.nutrition.nutritionDay(localDate);

      expect(day.meals, hasLength(3));
      expect(
        day.meals.map((meal) => meal.meal.id),
        <String>[first.mealId, second.mealId, third.mealId],
      );
      expect(
        day.meals.map((meal) => meal.meal.mealType),
        everyElement('Snack'),
      );
      expect(
        day.meals.map((meal) => meal.meal.startedAt),
        <DateTime>[
          DateTime.utc(2026, 6, 26, 10),
          DateTime.utc(2026, 6, 26, 15),
          DateTime.utc(2026, 6, 26, 21),
        ],
      );
      expect(
        day.meals.map((meal) => meal.entries.single.name),
        <String>['Apple', 'Yogurt', 'Toast'],
      );
      expect(
        day.meals.map((meal) => meal.entries.single.mealId),
        <String>[first.mealId, second.mealId, third.mealId],
      );
      expect(day.totals[NutrientId.energy].value, 360);
      expect(first.batchId, isNot(second.batchId));
      expect(second.batchId, isNot(third.batchId));
    });

    test('orders Nutrition Day Meals by Meal Type order then start instant',
        () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      await repositories.nutrition.ensureDefaultMealTypes();

      final lateBreakfastId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Breakfast',
          startedAt: DateTime.utc(2026, 6, 26, 20),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
      );
      final earlyLunchId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Lunch',
          startedAt: DateTime.utc(2026, 6, 26, 6),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
      );
      final earlySnackId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Snack',
          startedAt: DateTime.utc(2026, 6, 26, 7),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
      );
      final earlyBreakfastId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Breakfast',
          startedAt: DateTime.utc(2026, 6, 26, 8),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
      );

      final day = await repositories.nutrition.nutritionDay(localDate);

      expect(
        day.meals.map((meal) => meal.meal.id),
        <String>[
          earlyBreakfastId,
          lateBreakfastId,
          earlyLunchId,
          earlySnackId,
        ],
      );
    });

    test('Meal Types are configurable without rewriting logged Meals',
        () async {
      final mealTypes = await repositories.nutrition.listMealTypes();
      expect(
        mealTypes.map((type) => type.name),
        <String>['Breakfast', 'Lunch', 'Dinner', 'Snack'],
      );
      expect(
        mealTypes.map((type) => type.sortOrder),
        <int>[0, 1, 2, 3],
      );

      final snack = mealTypes.singleWhere((type) => type.name == 'Snack');
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      final mealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: snack.name,
          startedAt: DateTime.utc(2026, 6, 26, 15),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
      );

      await repositories.nutrition.updateMealType(
        snack.id,
        MealTypeDraft(name: 'Mini meal', sortOrder: snack.sortOrder),
        actor: 'tester',
      );

      final updatedTypes = await repositories.nutrition.listMealTypes();
      expect(
        updatedTypes.map((type) => type.name),
        <String>['Breakfast', 'Lunch', 'Dinner', 'Mini meal'],
      );

      final day = await repositories.nutrition.nutritionDay(localDate);
      expect(day.meals.single.meal.id, mealId);
      expect(day.meals.single.meal.mealType, 'Snack');

      final batch = (await repositories.activityLog.listEntries())
          .where((entry) => entry.entityId == snack.id)
          .toList(growable: false);
      expect(batch.last.entityTable, AppDatabase.mealTypesTable);
      expect(batch.last.beforeImage?['name'], 'Snack');
      expect(batch.last.afterImage?['name'], 'Mini meal');
    });

    test('rejects duplicate active Meal Type names', () async {
      final mealTypes = await repositories.nutrition.listMealTypes();
      final breakfast = mealTypes.singleWhere(
        (type) => type.name == 'Breakfast',
      );
      final snack = mealTypes.singleWhere((type) => type.name == 'Snack');

      expect(
        () => repositories.nutrition.createMealType(
          const MealTypeDraft(name: ' snack ', sortOrder: 99),
        ),
        throwsA(isA<DuplicateMealTypeNameException>()),
      );

      expect(
        () => repositories.nutrition.updateMealType(
          breakfast.id,
          MealTypeDraft(name: 'SNACK', sortOrder: breakfast.sortOrder),
        ),
        throwsA(isA<DuplicateMealTypeNameException>()),
      );

      await repositories.nutrition.updateMealType(
        snack.id,
        MealTypeDraft(name: ' Snack ', sortOrder: snack.sortOrder),
      );

      final updatedSnack =
          (await repositories.nutrition.listMealTypes()).singleWhere(
        (type) => type.id == snack.id,
      );
      expect(updatedSnack.name, 'Snack');
    });

    test('reorders and archives Meal Types while preserving Meal history',
        () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      final mealTypes = await repositories.nutrition.listMealTypes();
      final breakfast = mealTypes.singleWhere(
        (type) => type.name == 'Breakfast',
      );
      final lunch = mealTypes.singleWhere((type) => type.name == 'Lunch');
      final dinner = mealTypes.singleWhere((type) => type.name == 'Dinner');
      final snack = mealTypes.singleWhere((type) => type.name == 'Snack');
      final preWorkoutId = await repositories.nutrition.createMealType(
        const MealTypeDraft(name: 'Pre-workout', sortOrder: 99),
        actor: 'tester',
      );

      final breakfastMealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Breakfast',
          startedAt: DateTime.utc(2026, 6, 26, 8),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
      );
      final preWorkoutMealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Pre-workout',
          startedAt: DateTime.utc(2026, 6, 26, 7),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
      );

      await repositories.nutrition.reorderMealTypes(
        <String>[preWorkoutId, breakfast.id, lunch.id, dinner.id, snack.id],
        actor: 'tester',
      );

      final reorderedTypes = await repositories.nutrition.listMealTypes();
      expect(
        reorderedTypes.map((type) => type.name),
        <String>['Pre-workout', 'Breakfast', 'Lunch', 'Dinner', 'Snack'],
      );
      expect(
        reorderedTypes.map((type) => type.sortOrder),
        <int>[0, 1, 2, 3, 4],
      );
      expect(
        (await repositories.nutrition.nutritionDay(localDate))
            .meals
            .map((meal) => meal.meal.id),
        <String>[preWorkoutMealId, breakfastMealId],
      );

      await repositories.nutrition.archiveMealType(
        preWorkoutId,
        actor: 'tester',
      );

      final activeTypes = await repositories.nutrition.listMealTypes();
      expect(
        activeTypes.map((type) => type.name),
        <String>['Breakfast', 'Lunch', 'Dinner', 'Snack'],
      );
      final dayAfterArchive =
          await repositories.nutrition.nutritionDay(localDate);
      expect(dayAfterArchive.meals, hasLength(2));
      expect(
        dayAfterArchive.meals.map((meal) => meal.meal.mealType),
        contains('Pre-workout'),
      );

      final archiveEntry = (await repositories.activityLog.listEntries())
          .lastWhere((entry) => entry.entityId == preWorkoutId);
      expect(archiveEntry.entityTable, AppDatabase.mealTypesTable);
      expect(archiveEntry.beforeImage?['deleted_at'], isNull);
      expect(archiveEntry.afterImage?['deleted_at'], isNotNull);
    });

    test('logs a Quick Entry into an existing Meal using Meal timing',
        () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      final mealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Breakfast',
          startedAt: DateTime.utc(2026, 6, 26, 8),
          endedAt: DateTime.utc(2026, 6, 26, 8, 20),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
        actor: 'tester',
      );

      final result = await repositories.nutrition.logQuickEntryForMeal(
        mealId: mealId,
        entry: QuickFoodEntryDraft(
          name: 'Coffee',
          nutrients: _energyAndMacros(energy: 20),
        ),
        actor: 'tester',
      );

      final day = await repositories.nutrition.nutritionDay(localDate);
      final meal = day.meals.single.meal;
      final entry = day.meals.single.entries.single;

      expect(result.mealId, mealId);
      expect(meal.startedAt, DateTime.utc(2026, 6, 26, 8));
      expect(meal.endedAt, DateTime.utc(2026, 6, 26, 8, 20));
      expect(entry.name, 'Coffee');
      expect(entry.mealId, mealId);

      final columnsByTable = await database.describeSchema();
      expect(
        columnsByTable[AppDatabase.foodEntriesTable],
        isNot(contains('started_at')),
      );

      final batch = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == result.batchId)
          .toList(growable: false);
      expect(batch, hasLength(1));
      expect(batch.single.entityTable, AppDatabase.foodEntriesTable);
    });

    test('deletes a Meal and its Food Entries as one undoable Batch', () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      final mealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Dinner',
          startedAt: DateTime.utc(2026, 6, 26, 19),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
        actor: 'tester',
      );
      final first = await repositories.nutrition.logQuickEntryForMeal(
        mealId: mealId,
        entry: QuickFoodEntryDraft(
          name: 'Rice bowl',
          nutrients: _energyAndMacros(energy: 420),
        ),
        actor: 'tester',
      );
      final second = await repositories.nutrition.logQuickEntryForMeal(
        mealId: mealId,
        entry: QuickFoodEntryDraft(
          name: 'Yogurt',
          nutrients: _energyAndMacros(energy: 180),
        ),
        actor: 'tester',
      );

      final deleteBatchId = await repositories.nutrition.deleteMeal(
        mealId,
        actor: 'tester',
      );

      expect((await repositories.nutrition.nutritionDay(localDate)).meals,
          isEmpty);
      expect((await repositories.nutrition.getMealById(mealId))!.deletedAt,
          isNotNull);
      expect(
        (await repositories.nutrition.getFoodEntryById(first.foodEntryId))!
            .deletedAt,
        isNotNull,
      );
      expect(
        (await repositories.nutrition.getFoodEntryById(second.foodEntryId))!
            .deletedAt,
        isNotNull,
      );

      final deleteLogs = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == deleteBatchId)
          .toList(growable: false);
      expect(deleteLogs, hasLength(3));
      expect(deleteLogs.map((entry) => entry.batchId).toSet(), hasLength(1));
      expect(
        deleteLogs
            .where((entry) => entry.entityTable == AppDatabase.mealsTable),
        hasLength(1),
      );
      expect(
        deleteLogs.where(
            (entry) => entry.entityTable == AppDatabase.foodEntriesTable),
        hasLength(2),
      );
      expect(deleteLogs.map((entry) => entry.beforeImage?['deleted_at']),
          everyElement(isNull));
      expect(deleteLogs.map((entry) => entry.afterImage?['deleted_at']),
          everyElement(isNotNull));

      final undo = await repositories.activityLog.undoBatch(
        deleteBatchId,
        actor: 'tester',
      );

      expect(undo.hasConflicts, isFalse);
      expect(undo.appliedEntries, hasLength(3));
      final restoredDay = await repositories.nutrition.nutritionDay(localDate);
      expect(restoredDay.meals, hasLength(1));
      expect(restoredDay.meals.single.meal.id, mealId);
      expect(
        restoredDay.meals.single.entries.map((entry) => entry.id),
        <String>[first.foodEntryId, second.foodEntryId],
      );
    });

    test('deletes a Food Entry as its own tombstone Batch', () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      final mealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Snack',
          startedAt: DateTime.utc(2026, 6, 26, 15),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
        actor: 'tester',
      );
      final deleted = await repositories.nutrition.logQuickEntryForMeal(
        mealId: mealId,
        entry: QuickFoodEntryDraft(
          name: 'Apple',
          nutrients: _energyAndMacros(energy: 80),
        ),
        actor: 'tester',
      );
      final kept = await repositories.nutrition.logQuickEntryForMeal(
        mealId: mealId,
        entry: QuickFoodEntryDraft(
          name: 'Toast',
          nutrients: _energyAndMacros(energy: 160),
        ),
        actor: 'tester',
      );

      final deleteBatchId = await repositories.nutrition.deleteFoodEntry(
        deleted.foodEntryId,
        actor: 'tester',
      );

      final day = await repositories.nutrition.nutritionDay(localDate);
      expect(day.meals.single.meal.id, mealId);
      expect(day.meals.single.entries.map((entry) => entry.id),
          <String>[kept.foodEntryId]);
      expect(
        (await repositories.nutrition.getFoodEntryById(deleted.foodEntryId))!
            .deletedAt,
        isNotNull,
      );

      final deleteLogs = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == deleteBatchId)
          .toList(growable: false);
      expect(deleteLogs, hasLength(1));
      expect(deleteLogs.single.entityTable, AppDatabase.foodEntriesTable);
      expect(deleteLogs.single.beforeImage?['deleted_at'], isNull);
      expect(deleteLogs.single.afterImage?['deleted_at'], isNotNull);

      final undo = await repositories.activityLog.undoBatch(
        deleteBatchId,
        actor: 'tester',
      );
      expect(undo.hasConflicts, isFalse);
      expect(
        (await repositories.nutrition.nutritionDay(localDate))
            .meals
            .single
            .entries
            .map((entry) => entry.id),
        <String>[deleted.foodEntryId, kept.foodEntryId],
      );
    });

    test(
        'deletes Open Food Facts Food Entry as a tombstone without cache tombstone',
        () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 27);
      final startedAt = DateTime.utc(2026, 6, 27, 15);
      final mealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Snack',
          startedAt: startedAt,
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
      );
      final logged = await repositories.nutrition.logFoodEntrySnapshot(
        entry: _offSnapshotDraft(mealId),
        actor: 'tester',
      );
      await database.into(database.openFoodFactsCache).insert(
            OpenFoodFactsCacheCompanion.insert(
              lookupKey: 'barcode:3017620422003',
              foodId: '3017620422003',
              name: 'Original branded bar',
              nutrientValuesJson: _offNutrientsPer100().toJsonString(),
              isLiquid: const Value<bool>(false),
              servingLabel: const Value<String?>('serving'),
              servingSize: const Value<double?>(45),
              packageSize: const Value<double?>(60),
              fetchedAt: startedAt,
              lastAccessedAt: startedAt,
            ),
          );

      final deleteBatchId = await repositories.nutrition.deleteFoodEntry(
        logged.foodEntryId,
        actor: 'tester',
      );

      final deletedRow = await (database.select(database.foodEntries)
            ..where((row) => row.id.equals(logged.foodEntryId)))
          .getSingle();
      final cacheRows =
          await database.select(database.openFoodFactsCache).get();
      final deleteLogs = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == deleteBatchId)
          .toList(growable: false);

      expect(deletedRow.deletedAt, isNotNull);
      expect(deletedRow.foodSource, FoodSource.openFoodFacts.name);
      expect(cacheRows, hasLength(1));
      expect(cacheRows.single.foodId, '3017620422003');
      expect(deleteLogs, hasLength(1));
      expect(deleteLogs.single.entityTable, AppDatabase.foodEntriesTable);
      expect(deleteLogs.single.beforeImage?['food_source'],
          FoodSource.openFoodFacts.name);
      expect(deleteLogs.single.beforeImage?['deleted_at'], isNull);
      expect(deleteLogs.single.afterImage?['deleted_at'], isNotNull);
      expect(
        (await repositories.activityLog.listEntries()).map(
          (entry) => entry.entityTable,
        ),
        isNot(contains(AppDatabase.openFoodFactsCacheTable)),
      );
    });

    test('Food Entry snapshot survives Food edits and archive', () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      final mealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Dinner',
          startedAt: DateTime.utc(2026, 6, 26, 19),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
      );
      final foodId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Rice',
          nutrientsPer100: _foodPer100(energy: 200, protein: 4),
          isLiquid: false,
          servingLabel: 'bowl',
          servingSize: 150,
        ),
      );
      final result = await repositories.nutrition.logFoodEntry(
        entry: FoodEntryDraft(
          mealId: mealId,
          foodId: foodId,
          portion: Portion(
            value: 2,
            entered: '2',
            unit: PortionUnit.serving,
          ),
        ),
      );

      await repositories.nutrition.updateUserFood(
        foodId,
        UserFoodDraft(
          name: 'Edited rice',
          nutrientsPer100: _foodPer100(energy: 999, protein: 99),
          isLiquid: true,
          servingLabel: 'cup',
          servingSize: 50,
          packageSize: 250,
        ),
      );
      await repositories.nutrition.archiveUserFood(foodId);

      final food = await repositories.nutrition.getUserFoodById(foodId);
      expect(food!.name, 'Edited rice');
      expect(food.deletedAt, isNotNull);
      expect(await repositories.nutrition.listActiveUserFoods(), isEmpty);

      final entry =
          await repositories.nutrition.getFoodEntryById(result.foodEntryId);
      expect(entry, isNotNull);
      expect(entry!.name, 'Rice');
      expect(entry.foodSource, FoodSource.user);
      expect(entry.isLiquid, isFalse);
      expect(entry.servingLabel, 'bowl');
      expect(entry.servingSize, 150);
      expect(entry.packageSize, isNull);
      expect(entry.nutrients[NutrientId.energy].value, 200);
      expect(entry.nutrients[NutrientId.protein].value, 4);
      expect(entry.resolvedBaseQuantity, 300);
      expect(entry.resolvedNutrients[NutrientId.energy].value, 600);
      expect(entry.resolvedNutrients[NutrientId.protein].value, 12);
    });

    test('rejects unavailable Portion units for Food Entries', () async {
      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      final mealId = await repositories.nutrition.createMeal(
        MealDraft(
          mealType: 'Snack',
          startedAt: DateTime.utc(2026, 6, 26, 16),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
      );
      final solidFoodId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Almonds',
          nutrientsPer100: _foodPer100(),
          isLiquid: false,
        ),
      );
      final liquidFoodId = await repositories.nutrition.createUserFood(
        UserFoodDraft(
          name: 'Milk',
          nutrientsPer100: _foodPer100(energy: 60, protein: 3),
          isLiquid: true,
          servingLabel: 'glass',
          servingSize: 250,
          packageSize: 1000,
        ),
      );

      expect(
        await repositories.nutrition.availablePortionUnits(solidFoodId),
        <PortionUnit>[PortionUnit.gram, PortionUnit.ounce],
      );
      expect(
        await repositories.nutrition.availablePortionUnits(liquidFoodId),
        <PortionUnit>[
          PortionUnit.milliliter,
          PortionUnit.fluidOunce,
          PortionUnit.serving,
          PortionUnit.package,
        ],
      );
      expect(
        repositories.nutrition.createUserFood(
          UserFoodDraft(
            name: 'Invalid',
            nutrientsPer100: _foodPer100(),
            isLiquid: false,
            servingLabel: 'piece',
          ),
        ),
        throwsArgumentError,
      );
      expect(
        repositories.nutrition.logFoodEntry(
          entry: FoodEntryDraft(
            mealId: mealId,
            foodId: solidFoodId,
            portion: Portion(
              value: 1,
              entered: '1',
              unit: PortionUnit.serving,
            ),
          ),
        ),
        throwsArgumentError,
      );
      expect(
        repositories.nutrition.logFoodEntry(
          entry: FoodEntryDraft(
            mealId: mealId,
            foodId: liquidFoodId,
            portion: Portion(
              value: 100,
              entered: '100',
              unit: PortionUnit.gram,
            ),
          ),
        ),
        throwsArgumentError,
      );

      final result = await repositories.nutrition.logFoodEntry(
        entry: FoodEntryDraft(
          mealId: mealId,
          foodId: liquidFoodId,
          portion: Portion(
            value: 0.5,
            entered: '0.5',
            unit: PortionUnit.package,
          ),
        ),
      );
      final entry =
          await repositories.nutrition.getFoodEntryById(result.foodEntryId);
      expect(entry!.resolvedBaseQuantity, 500);
      expect(entry.resolvedNutrients[NutrientId.energy].value, 300);
    });

    test('controller logs through the repository path', () async {
      final container = ProviderContainer(
        overrides: [
          trainingRepositoriesProvider.overrideWith((ref) => repositories),
        ],
      );
      addTearDown(container.dispose);

      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      container.read(selectedNutritionDayProvider.notifier).select(localDate);

      final result = await container
          .read(nutritionDayControllerProvider.notifier)
          .logQuickEntry(
            meal: MealDraft(
              mealType: 'Dinner',
              startedAt: DateTime.utc(2026, 6, 26, 19),
              timezone: 'Australia/Brisbane',
              localDate: localDate,
            ),
            entry: QuickFoodEntryDraft(
              name: 'Quick omelette',
              nutrients: _energyAndMacros(),
            ),
          );

      final day = await repositories.nutrition.nutritionDay(localDate);
      expect(day.meals.single.meal.id, result.mealId);
      expect(day.meals.single.entries.single.id, result.foodEntryId);
    });

    test('reconstructs Meal and Quick Entry after kill-and-reopen', () async {
      final directory = await Directory.systemTemp.createTemp(
        'prn_nutrition_test_',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });

      final localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      final file = File('${directory.path}/nutrition.sqlite');
      final firstDatabase = AppDatabase.openFile(file);
      final firstRepositories = TrainingRepositories(firstDatabase);

      final result = await firstRepositories.nutrition.logQuickEntry(
        meal: MealDraft(
          mealType: 'Snack',
          startedAt: DateTime.utc(2026, 6, 26, 15, 30),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
        ),
        entry: QuickFoodEntryDraft(
          name: 'Greek yogurt',
          nutrients: _energyAndMacros(),
        ),
        actor: 'tester',
      );
      await firstDatabase.close();

      final reopenedDatabase = AppDatabase.openFile(file);
      addTearDown(reopenedDatabase.close);
      final reopenedRepositories = TrainingRepositories(reopenedDatabase);
      final reopenedDay =
          await reopenedRepositories.nutrition.nutritionDay(localDate);

      expect(reopenedDay.meals, hasLength(1));
      expect(reopenedDay.meals.single.meal.id, result.mealId);
      expect(reopenedDay.meals.single.meal.mealType, 'Snack');
      expect(reopenedDay.meals.single.entries, hasLength(1));
      final entry = reopenedDay.meals.single.entries.single;
      expect(entry.id, result.foodEntryId);
      expect(entry.name, 'Greek yogurt');
      expect(entry.foodId, isNull);
      expect(entry.portion, isNull);
      expect(entry.nutrients[NutrientId.energy].entered, '240');
      expect(entry.nutrients[NutrientId.fiber].status,
          NutrientValueStatus.unknown);
    });
  });

  group('nutrition goals repository', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('exposes a nutrition_goals LWW row with only configured target columns',
        () async {
      final columnsByTable = await database.describeSchema();

      expect(columnsByTable.keys, contains(AppDatabase.nutritionGoalsTable));
      expect(
        columnsByTable[AppDatabase.nutritionGoalsTable],
        containsAll(<String>[
          'id',
          'nutrient_id',
          'target_value',
          'target_entered',
          'unit',
          'sync_device_id',
          'sync_previously_synced',
          'updated_at',
          'deleted_at',
        ]),
      );
      // The Goal row stores only configured targets: no computed total column.
      expect(
        columnsByTable[AppDatabase.nutritionGoalsTable],
        isNot(
          anyElement(
            anyOf(
              contains('total'),
              contains('progress'),
              contains('consumed'),
              equals('value'),
            ),
          ),
        ),
      );
    });

    test('persists energy + macro targets and round-trips through the repository',
        () async {
      await repositories.nutrition.saveNutritionGoal(
        NutritionGoalTarget(
          nutrient: NutrientId.energy,
          value: 2400,
          entered: '2400',
        ),
      );
      await repositories.nutrition.saveNutritionGoal(
        NutritionGoalTarget(
          nutrient: NutrientId.protein,
          value: 180,
          entered: '180',
        ),
      );
      await repositories.nutrition.saveNutritionGoal(
        NutritionGoalTarget(
          nutrient: NutrientId.carbohydrate,
          value: 250,
          entered: '250',
        ),
      );
      await repositories.nutrition.saveNutritionGoal(
        NutritionGoalTarget(
          nutrient: NutrientId.fat,
          value: 70,
          entered: '70',
        ),
      );

      final goals = await repositories.nutrition.listNutritionGoals();
      expect(goals, hasLength(4));
      expect(
        goals.map((goal) => goal.nutrient).toSet(),
        <NutrientId>{
          NutrientId.energy,
          NutrientId.protein,
          NutrientId.carbohydrate,
          NutrientId.fat,
        },
      );

      final energy = goals.singleWhere(
        (goal) => goal.nutrient == NutrientId.energy,
      );
      expect(energy.target.value, 2400);
      expect(energy.target.entered, '2400');
      expect(energy.target.unit, NutrientUnit.kilocalorie);

      final protein = goals.singleWhere(
        (goal) => goal.nutrient == NutrientId.protein,
      );
      expect(protein.target.unit, NutrientUnit.gram);
    });

    test('upserts a single active LWW row per nutrient when edited', () async {
      final firstId = await repositories.nutrition.saveNutritionGoal(
        NutritionGoalTarget(
          nutrient: NutrientId.protein,
          value: 150,
          entered: '150',
        ),
      );
      final secondId = await repositories.nutrition.saveNutritionGoal(
        NutritionGoalTarget(
          nutrient: NutrientId.protein,
          value: 185,
          entered: '185',
        ),
      );

      expect(secondId, firstId);
      final goals = await repositories.nutrition.listNutritionGoals();
      expect(goals, hasLength(1));
      expect(goals.single.target.value, 185);
      expect(goals.single.target.entered, '185');

      // The edit is one Activity Log entry whose before-image carried the old
      // configured target, never a derived total.
      final logs = (await repositories.activityLog.listEntries())
          .where(
            (entry) => entry.entityTable == AppDatabase.nutritionGoalsTable,
          )
          .toList(growable: false);
      final editLog = logs.lastWhere((entry) => entry.entityId == firstId);
      expect(editLog.beforeImage?['target_value'], 150);
      expect(editLog.afterImage?['target_value'], 185);
    });

    test('never writes a derived analytic value onto the Goal row', () async {
      final id = await repositories.nutrition.saveNutritionGoal(
        NutritionGoalTarget(
          nutrient: NutrientId.energy,
          value: 2200,
          entered: '2200',
        ),
        actor: 'tester',
      );

      final log = (await repositories.activityLog.listEntries()).singleWhere(
        (entry) => entry.entityId == id,
      );
      final afterImage = log.afterImage!;
      // The persisted image holds exactly the configured target and LWW
      // bookkeeping — nothing derived (no total/progress/remaining).
      expect(
        afterImage.keys.toSet(),
        <String>{
          'id',
          'nutrient_id',
          'target_value',
          'target_entered',
          'unit',
          'updated_at',
          'deleted_at',
        },
      );
      expect(afterImage['target_value'], 2200);
      expect(afterImage['nutrient_id'], NutrientId.energy.storageKey);
    });

    test('hard-rejects an impossible target through the shared validator',
        () async {
      expect(
        () => repositories.nutrition.saveNutritionGoal(
          NutritionGoalTarget(
            nutrient: NutrientId.protein,
            value: -1,
            entered: '-1',
          ),
        ),
        throwsA(isA<NutrientValidationException>()),
      );
      expect(
        () => repositories.nutrition.saveNutritionGoal(
          NutritionGoalTarget(
            nutrient: NutrientId.energy,
            value: 10001,
            entered: '10001',
          ),
        ),
        throwsA(isA<NutrientValidationException>()),
      );

      // No row was written for the rejected targets.
      expect(await repositories.nutrition.listNutritionGoals(), isEmpty);
    });

    test('clearing a goal is a normal LWW soft-delete with a tombstone',
        () async {
      final id = await repositories.nutrition.saveNutritionGoal(
        NutritionGoalTarget(
          nutrient: NutrientId.fat,
          value: 70,
          entered: '70',
        ),
        actor: 'tester',
      );

      await repositories.nutrition.clearNutritionGoal(
        NutrientId.fat,
        actor: 'tester',
      );

      expect(await repositories.nutrition.listNutritionGoals(), isEmpty);
      expect(
        await repositories.nutrition.getNutritionGoal(NutrientId.fat),
        isNull,
      );

      final tombstone = (await repositories.activityLog.listEntries())
          .lastWhere((entry) => entry.entityId == id);
      expect(tombstone.entityTable, AppDatabase.nutritionGoalsTable);
      expect(tombstone.beforeImage?['deleted_at'], isNull);
      expect(tombstone.afterImage?['deleted_at'], isNotNull);

      // A later save re-creates a fresh active row rather than resurrecting.
      final reSaveId = await repositories.nutrition.saveNutritionGoal(
        NutritionGoalTarget(
          nutrient: NutrientId.fat,
          value: 80,
          entered: '80',
        ),
      );
      expect(reSaveId, isNot(id));
      final active = await repositories.nutrition.listNutritionGoals();
      expect(active, hasLength(1));
      expect(active.single.target.value, 80);
    });

    test('does not create any Metric or Reading for a nutrition target',
        () async {
      await repositories.nutrition.saveNutritionGoal(
        NutritionGoalTarget(
          nutrient: NutrientId.energy,
          value: 2400,
          entered: '2400',
        ),
      );

      expect(await repositories.metrics.listActive(), isEmpty);
      final goalLogs = (await repositories.activityLog.listEntries())
          .map((entry) => entry.entityTable)
          .toSet();
      expect(goalLogs, isNot(contains(AppDatabase.metricsTable)));
      expect(goalLogs, isNot(contains(AppDatabase.metricReadingsTable)));
      expect(goalLogs, contains(AppDatabase.nutritionGoalsTable));
    });
  });
}

NutrientVector _energyAndMacros({
  double energy = 240,
  double protein = 32,
  double carbohydrate = 12,
  double fat = 4,
}) {
  return NutrientVector.energyAndMacros(
    energy: NutrientAmount.complete(
      value: energy,
      entered: _enteredNumber(energy),
      unit: NutrientUnit.kilocalorie,
    ),
    protein: NutrientAmount.complete(
      value: protein,
      entered: _enteredNumber(protein),
      unit: NutrientUnit.gram,
    ),
    carbohydrate: NutrientAmount.complete(
      value: carbohydrate,
      entered: _enteredNumber(carbohydrate),
      unit: NutrientUnit.gram,
    ),
    fat: NutrientAmount.complete(
      value: fat,
      entered: _enteredNumber(fat),
      unit: NutrientUnit.gram,
    ),
  );
}

String _enteredNumber(double value) {
  final rounded = value.roundToDouble();
  if ((value - rounded).abs() < 0.000001) {
    return rounded.toInt().toString();
  }
  return value.toString();
}

NutrientVector _foodPer100({
  double energy = 100,
  double protein = 10,
  double carbohydrate = 30,
  double fat = 4,
}) {
  return NutrientVector.energyAndMacros(
    energy: NutrientAmount.complete(
      value: energy,
      entered: '$energy',
      unit: NutrientUnit.kilocalorie,
    ),
    protein: NutrientAmount.complete(
      value: protein,
      entered: '$protein',
      unit: NutrientUnit.gram,
    ),
    carbohydrate: NutrientAmount.complete(
      value: carbohydrate,
      entered: '$carbohydrate',
      unit: NutrientUnit.gram,
    ),
    fat: NutrientAmount.complete(
      value: fat,
      entered: '$fat',
      unit: NutrientUnit.gram,
    ),
  );
}

NutrientVector _foodPer100WithUnknownProtein({
  double energy = 100,
  double carbohydrate = 30,
  double fat = 4,
}) {
  return NutrientVector.energyAndMacros(
    energy: NutrientAmount.complete(
      value: energy,
      entered: '$energy',
      unit: NutrientUnit.kilocalorie,
    ),
    protein: NutrientAmount.unknown(NutrientUnit.gram),
    carbohydrate: NutrientAmount.complete(
      value: carbohydrate,
      entered: '$carbohydrate',
      unit: NutrientUnit.gram,
    ),
    fat: NutrientAmount.complete(
      value: fat,
      entered: '$fat',
      unit: NutrientUnit.gram,
    ),
  );
}

FoodEntrySnapshotDraft _offSnapshotDraft(String mealId) {
  return FoodEntrySnapshotDraft(
    mealId: mealId,
    foodId: '3017620422003',
    name: 'Original branded bar',
    foodSource: FoodSource.openFoodFacts,
    nutrientsPer100: _offNutrientsPer100(),
    isLiquid: false,
    servingLabel: 'serving',
    servingSize: 45,
    packageSize: 60,
    portion: Portion(
      value: 1,
      entered: '1',
      unit: PortionUnit.serving,
    ),
  );
}

NutrientVector _offNutrientsPer100() {
  return NutrientVector.energyAndMacros(
    energy: NutrientAmount.complete(
      value: 250,
      entered: '250',
      unit: NutrientUnit.kilocalorie,
    ),
    protein: NutrientAmount.complete(
      value: 8,
      entered: '8',
      unit: NutrientUnit.gram,
    ),
    carbohydrate: NutrientAmount.complete(
      value: 28,
      entered: '28',
      unit: NutrientUnit.gram,
    ),
    fat: NutrientAmount.complete(
      value: 11,
      entered: '11',
      unit: NutrientUnit.gram,
    ),
  );
}

RecipeIngredient _recipeIngredient(
  UserFoodRecord food,
  Portion portion,
) {
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
