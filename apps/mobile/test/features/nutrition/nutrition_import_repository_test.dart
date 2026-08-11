import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/nutrition/import/cronometer_csv_import_adapter.dart';

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

  group('nutrition import landing path', () {
    late AppDatabase database;
    late TrainingRepositories repositories;
    const adapter = CronometerCsvImportAdapter();

    const csv = '''
Day,Time,Group,Food Name,Amount,Energy (kcal),Protein (g),Carbs (g),Fat (g),Calcium (mg)
2026-06-01,08:00,Breakfast,Oats,100 g,389,16.9,66.3,6.9,
2026-06-01,08:05,Breakfast,Banana,118 g,105,1.3,27,0.4,6
2026-06-01,13:00,Lunch,Chicken Breast,200 g,330,62,0,7.2,
''';

    Future<NutritionImportResult> land({bool consent = true}) {
      return repositories.nutrition.importNutritionBatch(
        batch: adapter.parse(csv),
        provider: adapter.provider,
        consentCheck: () async => consent,
      );
    }

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('lands Meals + read-only Food Entries with Food Source = Cronometer',
        () async {
      final result = await land();

      expect(result.importedCount, 3);
      expect(result.mealIds, hasLength(2));

      final day = await repositories.nutrition.nutritionDay(
        const NutritionDayDate(year: 2026, month: 6, day: 1),
      );
      expect(day.meals, hasLength(2));
      final entries = day.meals.expand((meal) => meal.entries).toList();
      expect(entries, hasLength(3));
      for (final entry in entries) {
        expect(entry.foodSource, FoodSource.cronometer);
        expect(entry.kind, FoodEntryKind.food);
        expect(entry.importSource, 'cronometer');
        expect(entry.isImported, isTrue);
      }
    });

    test('never auto-creates a User Food', () async {
      await land();
      final foods = await repositories.nutrition.listActiveUserFoods();
      expect(foods, isEmpty);
    });

    test('stores a self-describing snapshot; unknown stays unknown not zero',
        () async {
      await land();
      final day = await repositories.nutrition.nutritionDay(
        const NutritionDayDate(year: 2026, month: 6, day: 1),
      );
      final oats = day.meals
          .expand((meal) => meal.entries)
          .firstWhere((entry) => entry.name == 'Oats');
      // Calcium was a blank column -> unknown, never 0.
      expect(oats.nutrients[NutrientId.calcium].isComplete, isFalse);
      // Energy reported -> complete.
      expect(oats.nutrients[NutrientId.energy].isComplete, isTrue);

      final banana = day.meals
          .expand((meal) => meal.entries)
          .firstWhere((entry) => entry.name == 'Banana');
      // Calcium reported for Banana -> complete.
      expect(banana.nutrients[NutrientId.calcium].isComplete, isTrue);
    });

    test('lands as exactly one reversible Activity Log batch', () async {
      final result = await land();
      final entries = await repositories.activityLog.listEntries();
      final batchIds = entries.map((entry) => entry.batchId).toSet();
      expect(batchIds, contains(result.batchId));
      // All writes (2 meals + 3 food entries) share the one import batch.
      final importEntries =
          entries.where((entry) => entry.batchId == result.batchId).toList();
      expect(importEntries.every((entry) => entry.actor == 'import'), isTrue);
      expect(importEntries, hasLength(5));
    });

    test('the single batch undoes the whole import for free', () async {
      final result = await land();
      await repositories.activityLog.undoBatch(result.batchId);

      final day = await repositories.nutrition.nutritionDay(
        const NutritionDayDate(year: 2026, month: 6, day: 1),
      );
      expect(day.meals, isEmpty);
    });

    test('re-importing the same CSV is idempotent by (source, externalId)',
        () async {
      final first = await land();
      expect(first.importedCount, 3);

      final second = await land();
      expect(second.importedCount, 0);
      expect(second.updatedCount, 3);

      final day = await repositories.nutrition.nutritionDay(
        const NutritionDayDate(year: 2026, month: 6, day: 1),
      );
      final entries = day.meals.expand((meal) => meal.entries).toList();
      // No duplicates: still exactly 3 entries, 2 meals.
      expect(entries, hasLength(3));
      expect(day.meals, hasLength(2));
    });

    test('re-import respects a deletion tombstone (never resurrects)',
        () async {
      await land();
      final day = await repositories.nutrition.nutritionDay(
        const NutritionDayDate(year: 2026, month: 6, day: 1),
      );
      final oats = day.meals
          .expand((meal) => meal.entries)
          .firstWhere((entry) => entry.name == 'Oats');
      await repositories.nutrition.deleteFoodEntry(oats.id);

      // Re-import: the deleted Oats entry must NOT come back.
      final result = await land();
      expect(result.skippedTombstoned, 1);

      final after = await repositories.nutrition.nutritionDay(
        const NutritionDayDate(year: 2026, month: 6, day: 1),
      );
      final names =
          after.meals.expand((meal) => meal.entries).map((e) => e.name).toSet();
      expect(names, isNot(contains('Oats')));
      expect(names, containsAll(<String>['Banana', 'Chicken Breast']));
    });

    test('refuses to land anything when un-consented (edge gate)', () async {
      await expectLater(
        land(consent: false),
        throwsA(isA<NutritionImportConsentRequiredException>()),
      );
      final entries = await repositories.activityLog.listEntries();
      expect(entries, isEmpty);
      final day = await repositories.nutrition.nutritionDay(
        const NutritionDayDate(year: 2026, month: 6, day: 1),
      );
      expect(day.meals, isEmpty);
    });

    test('a hard-reject row is dropped while the rest of the batch lands',
        () async {
      // Energy cap is 10000 kcal; 100 g at 50000 kcal/100g resolves to 50000.
      const badCsv = '''
Day,Time,Group,Food Name,Amount,Energy (kcal),Protein (g),Carbs (g),Fat (g)
2026-06-02,08:00,Breakfast,Reasonable,100 g,389,16.9,66.3,6.9
2026-06-02,08:05,Breakfast,Impossible,100 g,50000,16.9,66.3,6.9
''';
      final result = await repositories.nutrition.importNutritionBatch(
        batch: adapter.parse(badCsv),
        provider: adapter.provider,
        consentCheck: () async => true,
      );
      expect(result.rejectedCount, 1);
      expect(result.importedCount, 1);

      final day = await repositories.nutrition.nutritionDay(
        const NutritionDayDate(year: 2026, month: 6, day: 2),
      );
      final names =
          day.meals.expand((meal) => meal.entries).map((e) => e.name).toList();
      expect(names, <String>['Reasonable']);
    });

    test('a soft-warn lands as a non-blocking persisted review flag', () async {
      // A 100 g serving past the portion soft-warn (2000 g) triggers a warning
      // but is NOT hard-rejected, so it lands with a review flag.
      const warnCsv = '''
Day,Time,Group,Food Name,Amount,Energy (kcal),Protein (g),Carbs (g),Fat (g)
2026-06-03,08:00,Breakfast,BigBowl,3000 g,300,12,40,5
''';
      final result = await repositories.nutrition.importNutritionBatch(
        batch: adapter.parse(warnCsv),
        provider: adapter.provider,
        consentCheck: () async => true,
      );
      expect(result.importedCount, 1);
      expect(result.reviewFlagCount, greaterThan(0));

      final day = await repositories.nutrition.nutritionDay(
        const NutritionDayDate(year: 2026, month: 6, day: 3),
      );
      final entry = day.meals.single.entries.single;
      expect(entry.reviewFlags, isNotEmpty);
    });

    test('no nutrition total is stored — totals derive on read', () async {
      await land();
      final columnsByTable = await database.describeSchema();
      // The Food Entries table carries no stored total column.
      expect(
        columnsByTable[AppDatabase.foodEntriesTable],
        isNot(anyElement(contains('total'))),
      );
      // Derived day total is computed from the entries.
      final day = await repositories.nutrition.nutritionDay(
        const NutritionDayDate(year: 2026, month: 6, day: 1),
      );
      expect(day.totals[NutrientId.energy].value, closeTo(389 + 105 + 330, 1));
    });
  });
}
