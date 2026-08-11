import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/nutrition/import/lifesum_import_adapter.dart';
import 'package:perennia/features/nutrition/import/myfitnesspal_csv_import_adapter.dart';
import 'package:perennia/features/nutrition/import/nutrition_import.dart';
import 'package:perennia/features/nutrition/import/yazio_import_adapter.dart';

/// One landing-path scenario per new provider, asserting the SAME
/// shared contract holds for each: correct Food Source, idempotency by
/// (source, externalId), one reversible Activity Log batch, hard-reject drop,
/// never auto-creating a User Food. The provider only differs in its parser;
/// the contract below is identical (INTEGRATIONS.md §14 invariance).
class _ProviderCase {
  const _ProviderCase({
    required this.name,
    required this.adapter,
    required this.foodSource,
    required this.importSource,
    required this.goodFile,
    required this.rejectFile,
    required this.day,
    required this.expectedNames,
  });

  final String name;
  final NutritionImportAdapter adapter;
  final FoodSource foodSource;
  final String importSource;

  /// A two-entry file (Oats + Chicken Breast on the same day).
  final String goodFile;

  /// A two-entry file where the second row exceeds the energy hard-reject cap.
  final String rejectFile;
  final NutritionDayDate day;
  final List<String> expectedNames;
}

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

  final cases = <_ProviderCase>[
    _ProviderCase(
      name: 'MyFitnessPal',
      adapter: const MyFitnessPalCsvImportAdapter(),
      foodSource: FoodSource.myFitnessPal,
      importSource: 'myfitnesspal',
      day: const NutritionDayDate(year: 2026, month: 6, day: 1),
      expectedNames: const ['Oats', 'Chicken Breast'],
      goodFile: '''
Date,Meal,Food,Calories,Carbohydrates (g),Protein (g),Fat (g),Sodium (mg)
2026-06-01,Breakfast,Oats,389,66.3,16.9,6.9,2
2026-06-01,Lunch,Chicken Breast,330,0,62,7.2,74
''',
      rejectFile: '''
Date,Meal,Food,Calories,Protein (g)
2026-06-02,Breakfast,Reasonable,389,16.9
2026-06-02,Breakfast,Impossible,50000,16.9
''',
    ),
    _ProviderCase(
      name: 'Yazio',
      adapter: const YazioImportAdapter(),
      foodSource: FoodSource.yazio,
      importSource: 'yazio',
      day: const NutritionDayDate(year: 2026, month: 6, day: 1),
      expectedNames: const ['Oats', 'Chicken Breast'],
      goodFile: '''
{"consumed_items":[
  {"id":"y1","date":"2026-06-01","daytime":"breakfast","name":"Oats","amount":100,
   "nutrients":{"energy.energy":1627.6,"nutrient.protein":16.9,"nutrient.carb":66.3,"nutrient.fat":6.9}},
  {"id":"y2","date":"2026-06-01","daytime":"lunch","name":"Chicken Breast","amount":200,
   "nutrients":{"energy.energy":1380.7,"nutrient.protein":62,"nutrient.carb":0,"nutrient.fat":7.2}}
]}
''',
      rejectFile: '''
{"consumed_items":[
  {"id":"r1","date":"2026-06-02","daytime":"breakfast","name":"Reasonable","amount":100,
   "nutrients":{"energy.energy":1627.6,"nutrient.protein":16.9}},
  {"id":"r2","date":"2026-06-02","daytime":"breakfast","name":"Impossible","amount":100,
   "nutrients":{"energy.energy":209200,"nutrient.protein":16.9}}
]}
''',
    ),
    _ProviderCase(
      name: 'Lifesum',
      adapter: const LifesumImportAdapter(),
      foodSource: FoodSource.lifesum,
      importSource: 'lifesum',
      day: const NutritionDayDate(year: 2026, month: 6, day: 1),
      expectedNames: const ['Oats', 'Chicken Breast'],
      goodFile: '''
Date,Meal,Food,Amount,Unit,Calories (kcal),Carbs (g),Protein (g),Fat (g)
01/06/2026,Breakfast,Oats,100,g,389,66.3,16.9,6.9
01/06/2026,Lunch,Chicken Breast,200,g,330,0,62,7.2
''',
      rejectFile: '''
Date,Meal,Food,Amount,Unit,Calories (kcal),Protein (g)
02/06/2026,Breakfast,Reasonable,100,g,389,16.9
02/06/2026,Breakfast,Impossible,100,g,50000,16.9
''',
    ),
  ];

  for (final testCase in cases) {
    group('${testCase.name} landing path', () {
      late AppDatabase database;
      late TrainingRepositories repositories;

      Future<NutritionImportResult> land(String file, {bool consent = true}) {
        return repositories.nutrition.importNutritionBatch(
          batch: testCase.adapter.parse(file),
          provider: testCase.adapter.provider,
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

      test('lands read-only Food Entries with the correct provider Food Source',
          () async {
        final result = await land(testCase.goodFile);
        expect(result.importedCount, 2);

        final day = await repositories.nutrition.nutritionDay(testCase.day);
        final entries = day.meals.expand((m) => m.entries).toList();
        expect(entries, hasLength(2));
        expect(
          entries.map((e) => e.name).toSet(),
          testCase.expectedNames.toSet(),
        );
        for (final entry in entries) {
          expect(entry.foodSource, testCase.foodSource);
          expect(entry.importSource, testCase.importSource);
          expect(entry.isImported, isTrue);
          expect(entry.kind, FoodEntryKind.food);
        }
      });

      test('never auto-creates a User Food', () async {
        await land(testCase.goodFile);
        final foods = await repositories.nutrition.listActiveUserFoods();
        expect(foods, isEmpty);
      });

      test('lands as exactly one reversible Activity Log batch', () async {
        final result = await land(testCase.goodFile);
        final entries = await repositories.activityLog.listEntries();
        final importEntries =
            entries.where((e) => e.batchId == result.batchId).toList();
        // 2 meals + 2 food entries share the one import batch.
        expect(importEntries, hasLength(4));
        expect(importEntries.every((e) => e.actor == 'import'), isTrue);

        // The single batch undoes the whole import for free.
        await repositories.activityLog.undoBatch(result.batchId);
        final day = await repositories.nutrition.nutritionDay(testCase.day);
        expect(day.meals, isEmpty);
      });

      test('is idempotent by (source, externalId) on re-import', () async {
        final first = await land(testCase.goodFile);
        expect(first.importedCount, 2);

        final second = await land(testCase.goodFile);
        expect(second.importedCount, 0);
        expect(second.updatedCount, 2);

        final day = await repositories.nutrition.nutritionDay(testCase.day);
        final entries = day.meals.expand((m) => m.entries).toList();
        expect(entries, hasLength(2));
      });

      test('re-import respects a deletion tombstone (never resurrects)',
          () async {
        await land(testCase.goodFile);
        final day = await repositories.nutrition.nutritionDay(testCase.day);
        final oats = day.meals
            .expand((m) => m.entries)
            .firstWhere((e) => e.name == 'Oats');
        await repositories.nutrition.deleteFoodEntry(oats.id);

        final result = await land(testCase.goodFile);
        expect(result.skippedTombstoned, 1);

        final after = await repositories.nutrition.nutritionDay(testCase.day);
        final names =
            after.meals.expand((m) => m.entries).map((e) => e.name).toSet();
        expect(names, isNot(contains('Oats')));
      });

      test('refuses to land anything when un-consented (edge gate)', () async {
        await expectLater(
          land(testCase.goodFile, consent: false),
          throwsA(isA<NutritionImportConsentRequiredException>()),
        );
        final entries = await repositories.activityLog.listEntries();
        expect(entries, isEmpty);
      });

      test('a hard-reject row is dropped while the rest of the batch lands',
          () async {
        final result = await land(testCase.rejectFile);
        expect(result.rejectedCount, 1);
        expect(result.importedCount, 1);

        final day = await repositories.nutrition.nutritionDay(
          const NutritionDayDate(year: 2026, month: 6, day: 2),
        );
        final names =
            day.meals.expand((m) => m.entries).map((e) => e.name).toList();
        expect(names, <String>['Reasonable']);
      });

      test('no nutrition total is stored — totals derive on read', () async {
        await land(testCase.goodFile);
        final day = await repositories.nutrition.nutritionDay(testCase.day);
        // Oats 389 + Chicken 330 = 719 kcal, computed from the entries.
        expect(day.totals[NutrientId.energy].value, closeTo(719, 1));
      });
    });
  }

  group('MyFitnessPal free-export micros render unknown, not zero', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('absent micro columns land unknown and a day total over them is '
        'unknown ("—"), never coerced to 0', () async {
      const adapter = MyFitnessPalCsvImportAdapter();
      const csv = '''
Date,Meal,Food,Calories,Carbohydrates (g),Protein (g),Fat (g),Sodium (mg)
2026-06-01,Breakfast,Oats,389,66.3,16.9,6.9,2
''';
      await repositories.nutrition.importNutritionBatch(
        batch: adapter.parse(csv),
        provider: adapter.provider,
        consentCheck: () async => true,
      );

      final day = await repositories.nutrition.nutritionDay(
        const NutritionDayDate(year: 2026, month: 6, day: 1),
      );
      final entry = day.meals.single.entries.single;
      // Calcium/iron/vitamins absent in the export -> unknown on the entry.
      expect(entry.nutrients[NutrientId.calcium].isComplete, isFalse);
      expect(entry.nutrients[NutrientId.iron].isComplete, isFalse);
      // And the derived day total over an all-unknown micro stays unknown,
      // i.e. it will render "—" not 0 (NUTRITION.md §4).
      expect(day.totals[NutrientId.calcium].isComplete, isFalse);
      // A reported nutrient's total is, by contrast, complete.
      expect(day.totals[NutrientId.energy].isComplete, isTrue);
    });
  });
}
