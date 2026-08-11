import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';

/// — the cross-cutting lifecycle/provenance CONTRACT every nutrition
/// importer obeys: Food Source resolution + preserved provider string,
/// immutability (edit blocked / delete-to-correct), no User Food auto-create.
/// (Idempotency, tombstone-respect, hard-reject and soft-warn-as-review-flag
/// are covered alongside the foundation in nutrition_import_repository_test.)
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

  group('imported Food Entry contract', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    const localDate = NutritionDayDate(year: 2026, month: 6, day: 1);

    NutritionImportBatch batchFor(String name, {String externalId = 'row-1'}) {
      return NutritionImportBatch(
        meals: <NutritionImportMeal>[
          NutritionImportMeal(
            mealType: 'Breakfast',
            startedAt: DateTime(2026, 6, 1, 8),
            localDate: localDate,
            entries: <NutritionImportFoodEntry>[
              NutritionImportFoodEntry(
                externalId: externalId,
                name: name,
                nutrientsPer100: NutrientVector.full(<NutrientId, NutrientAmount>{
                  NutrientId.energy: NutrientAmount.complete(
                    value: 389,
                    entered: '389',
                    unit: NutrientId.energy.defaultUnit,
                  ),
                }),
                isLiquid: false,
                portion: Portion(
                  value: 100,
                  entered: '100',
                  unit: PortionUnit.gram,
                ),
              ),
            ],
          ),
        ],
      );
    }

    Future<NutritionImportResult> land({
      required String provider,
      NutritionImportBatch? batch,
      bool consent = true,
    }) {
      return repositories.nutrition.importNutritionBatch(
        batch: batch ?? batchFor('Oats'),
        provider: provider,
        consentCheck: () async => consent,
      );
    }

    Future<FoodEntryRecord> singleEntry() async {
      final day = await repositories.nutrition.nutritionDay(localDate);
      return day.meals.expand((meal) => meal.entries).single;
    }

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('a recognised provider resolves to its specific Food Source with no '
        'preserved string', () async {
      await land(provider: 'Cronometer');
      final entry = await singleEntry();

      expect(entry.foodSource, FoodSource.cronometer);
      expect(entry.importSource, 'cronometer');
      // A recognised provider needs no free-text preservation.
      expect(entry.importProvider, isNull);
      expect(entry.isImported, isTrue);
    });

    test('an unrecognised provider resolves to generic Imported and PRESERVES '
        'the exact provider string', () async {
      await land(provider: 'Acme Diet Tracker');
      final entry = await singleEntry();

      expect(entry.foodSource, FoodSource.imported);
      expect(entry.importProvider, 'Acme Diet Tracker');
      // The dedup source is the normalised id, distinct from the preserved
      // human-facing string.
      expect(entry.importSource, 'acme-diet-tracker');
      expect(entry.isImported, isTrue);
    });

    test('import never auto-creates a User Food (recognised or generic)',
        () async {
      await land(provider: 'Acme Diet Tracker');
      final foods = await repositories.nutrition.listActiveUserFoods();
      expect(foods, isEmpty);

      final entry = await singleEntry();
      // The snapshot is self-describing and never references a catalogue Food.
      expect(entry.foodId, isNull);
    });

    test('the preserved provider string survives the undo -> redo round-trip',
        () async {
      final result = await land(provider: 'Acme Diet Tracker');

      // Undo the import (a recoverable batch): the entry tombstones away.
      final undo = await repositories.activityLog.undoBatch(result.batchId);
      var day = await repositories.nutrition.nutritionDay(localDate);
      expect(
        day.meals.expand((meal) => meal.entries),
        isEmpty,
      );

      // Redo by undoing the undo (the Activity Log path, NOT a re-import which
      // would respect the tombstone): the preserved string + generic Imported
      // origin come back intact, proving they round-trip through the image.
      expect(undo.undoBatchId, isNotNull);
      await repositories.activityLog.undoBatch(undo.undoBatchId!);
      final entry = await singleEntry();
      expect(entry.foodSource, FoodSource.imported);
      expect(entry.importProvider, 'Acme Diet Tracker');
      expect(entry.importSource, 'acme-diet-tracker');
    });

    test('a re-import after undo respects the undo tombstone (no resurrection)',
        () async {
      final result = await land(provider: 'Acme Diet Tracker');
      await repositories.activityLog.undoBatch(result.batchId);

      // Re-importing the same export must NOT bring the undone entry back.
      final second = await land(provider: 'Acme Diet Tracker');
      expect(second.skippedTombstoned, 1);
      expect(second.importedCount, 0);

      final day = await repositories.nutrition.nutritionDay(localDate);
      expect(day.meals.expand((meal) => meal.entries), isEmpty);
    });

    test('an imported Food Entry is immutable — in-place edit is BLOCKED',
        () async {
      await land(provider: 'Cronometer');
      final entry = await singleEntry();
      expect(entry.isImported, isTrue);

      await expectLater(
        repositories.nutrition.updateFoodEntryPortion(
          id: entry.id,
          portion: Portion(value: 200, entered: '200', unit: PortionUnit.gram),
        ),
        throwsA(isA<ImportedEntryImmutableException>()),
      );

      // Unchanged: the portion the import landed is preserved.
      final after = await singleEntry();
      expect(after.portion?.value, 100);
    });

    test('correction path is delete-and-add-manual; the manual entry IS '
        'editable', () async {
      await land(provider: 'Cronometer');
      final imported = await singleEntry();
      final mealId = imported.mealId;

      // Delete (hard-delete -> tombstone) the imported observation.
      await repositories.nutrition.deleteFoodEntry(imported.id);

      // Add a manual replacement to the same Meal.
      final logged = await repositories.nutrition.logFoodEntrySnapshot(
        entry: FoodEntrySnapshotDraft(
          mealId: mealId,
          foodId: null,
          name: 'Oats (corrected)',
          foodSource: FoodSource.user,
          nutrientsPer100: NutrientVector.full(<NutrientId, NutrientAmount>{
            NutrientId.energy: NutrientAmount.complete(
              value: 389,
              entered: '389',
              unit: NutrientId.energy.defaultUnit,
            ),
          }),
          isLiquid: false,
          portion: Portion(value: 100, entered: '100', unit: PortionUnit.gram),
        ),
      );

      // The manual entry is NOT imported, so in-place edit is allowed.
      final result = await repositories.nutrition.updateFoodEntryPortion(
        id: logged.foodEntryId,
        portion: Portion(value: 150, entered: '150', unit: PortionUnit.gram),
      );
      expect(result.foodEntryId, logged.foodEntryId);

      final entry =
          await repositories.nutrition.getFoodEntryById(logged.foodEntryId);
      expect(entry!.isImported, isFalse);
      expect(entry.portion?.value, 150);
    });

    test('deleting an imported entry tombstones it (recoverable, no cascade) '
        'and re-import does not resurrect it', () async {
      await land(provider: 'Cronometer');
      final imported = await singleEntry();
      final mealId = imported.mealId;

      await repositories.nutrition.deleteFoodEntry(imported.id);
      var day = await repositories.nutrition.nutritionDay(localDate);
      // No cascade: the grouping Meal survives the entry delete.
      expect(day.meals, hasLength(1));
      expect(day.meals.single.meal.id, mealId);
      expect(day.meals.single.entries, isEmpty);

      // Re-import respects the tombstone.
      final result = await land(provider: 'Cronometer');
      expect(result.skippedTombstoned, 1);
      day = await repositories.nutrition.nutritionDay(localDate);
      expect(day.meals.single.entries, isEmpty);

      // The tombstone is recoverable via the Activity Log (the deletion is its
      // own reversible batch).
      final deletionBatch = (await repositories.activityLog.listEntries())
          .where((e) => e.entityId == imported.id)
          .map((e) => e.batchId)
          .toList();
      expect(deletionBatch, isNotEmpty);
    });

    test('a recognised vs unrecognised re-import is deduped per (source, '
        'externalId)', () async {
      // Same externalId under two different providers are DISTINCT keys.
      await land(provider: 'Cronometer', batch: batchFor('Oats'));
      await land(provider: 'Acme Diet Tracker', batch: batchFor('Oats'));

      final day = await repositories.nutrition.nutritionDay(localDate);
      final entries = day.meals.expand((meal) => meal.entries).toList();
      expect(entries, hasLength(2));
      expect(
        entries.map((e) => e.foodSource).toSet(),
        <FoodSource>{FoodSource.cronometer, FoodSource.imported},
      );
    });
  });
}
