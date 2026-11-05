import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/nutrition/controllers/meal_screen_controller.dart';

import '../support/kill_point_snapshot_interceptor.dart';

/// Kill-and-reopen for Meal logging (docs/designs/meal-logging.md,
/// Reliability), following the standing scenario
/// (`test/data/plan_tree_reopen_test.dart`): a database file that is closed
/// and opened again.
///
/// A process kill mid-write can't be staged inside one test process, so the
/// kill is taken as what it leaves on disk. A query interceptor copies the
/// database file and its journal at moments inside the write: after the Meal
/// row is inserted, between the copied entries of a Log again, and just
/// before the commit. Each copy is exactly the disk a kill at that moment
/// leaves behind, and opening it runs SQLite's crash recovery. A copy taken
/// after the commit must hold the whole action.
void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  group('Meal logging across a kill and reopen', () {
    late Directory directory;
    late File file;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'prn_meal_logging_reopen_',
      );
      file = File('${directory.path}/meals.sqlite');
    });

    tearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    test(
        'a first food into a new Meal leaves the Meal and its entry together, '
        'or neither', () async {
      final killPoints = _KillPointInterceptor(file, directory);
      final database = AppDatabase(
        NativeDatabase(file).interceptWith(killPoints),
      );
      final repositories = TrainingRepositories(database);
      final meal = PendingMeal(
        id: repositories.nutrition.newMealId(),
        startedAt: DateTime(2026, 6, 26, 12, 30),
        mealTypeName: 'Lunch',
      );
      killPoints.arm();

      final result = await repositories.nutrition.logFoodEntrySnapshot(
        target: NewMealTarget(meal),
        entry: FoodEntrySnapshotDraft(
          mealId: meal.id,
          foodId: 'usda-173944',
          name: 'Banana, raw',
          foodSource: FoodSource.usda,
          nutrientsPer100: _per100(),
          isLiquid: false,
          portion: Portion(value: 120, entered: '120', unit: PortionUnit.gram),
        ),
      );
      killPoints.disarm();
      await database.close();
      // A kill after the commit: the whole action must survive.
      killPoints.snapshot('committed');

      expect(
        killPoints.snapshots.keys.toSet(),
        <String>{'after-meal', 'after-entry-1', 'before-commit', 'committed'},
      );
      for (final entry in killPoints.snapshots.entries) {
        final reopened = AppDatabase.openFile(entry.value);
        try {
          final meals = await reopened.select(reopened.meals).get();
          final entries = await reopened.select(reopened.foodEntries).get();
          final activity = await reopened.select(reopened.activityLog).get();
          if (entry.key == 'committed') {
            expect(meals.map((row) => row.id), <String>[meal.id]);
            expect(entries.map((row) => row.id), <String>[result.foodEntryId]);
            expect(entries.single.mealId, meal.id);
            expect(activity.map((row) => row.batchId).toSet(), {
              result.batchId,
            });
            expect(activity, hasLength(2));
          } else {
            expect(meals, isEmpty, reason: 'killed ${entry.key}: no Meal');
            expect(entries, isEmpty, reason: 'killed ${entry.key}: no entry');
            expect(activity, isEmpty, reason: 'killed ${entry.key}');
          }
        } finally {
          await reopened.close();
        }
      }
    });

    test('a Log again leaves every copy or none of them', () async {
      // Seed the source Meal through the plain file first.
      final seedDatabase = AppDatabase.openFile(file);
      final seedRepositories = TrainingRepositories(seedDatabase);
      final sourceId = await seedRepositories.nutrition.createMeal(
        PendingMeal(
          id: seedRepositories.nutrition.newMealId(),
          startedAt: DateTime(2026, 6, 25, 8),
          mealTypeName: 'Breakfast',
        ),
      );
      for (final name in <String>['Toast', 'Eggs', 'Coffee', 'Juice']) {
        await seedRepositories.nutrition.logQuickEntry(
          target: ExistingMealTarget(sourceId),
          entry: QuickFoodEntryDraft(name: name, nutrients: _per100()),
        );
      }
      final seededActivity =
          (await seedDatabase.select(seedDatabase.activityLog).get()).length;
      await seedDatabase.close();

      final killPoints = _KillPointInterceptor(file, directory);
      final database = AppDatabase(
        NativeDatabase(file).interceptWith(killPoints),
      );
      final repositories = TrainingRepositories(database);
      final target = PendingMeal(
        id: repositories.nutrition.newMealId(),
        startedAt: DateTime(2026, 6, 26, 8),
        mealTypeName: 'Breakfast',
      );
      killPoints.arm();

      final result = await repositories.nutrition.logMealAgain(
        sourceId,
        NewMealTarget(target),
      );
      killPoints.disarm();
      await database.close();
      // A kill after the commit: the whole action must survive.
      killPoints.snapshot('committed');

      expect(result.foodEntryIds, hasLength(4));
      expect(
        killPoints.snapshots.keys.toSet(),
        <String>{
          'after-meal',
          'after-entry-1',
          'after-entry-2',
          'after-entry-3',
          'before-commit',
          'committed',
        },
      );
      for (final entry in killPoints.snapshots.entries) {
        final reopened = AppDatabase.openFile(entry.value);
        final reopenedRepositories = TrainingRepositories(reopened);
        try {
          final targetMeal =
              await reopenedRepositories.nutrition.getMealById(target.id);
          final copies = await reopenedRepositories.nutrition
              .listActiveEntriesForMeal(target.id);
          final activity =
              (await reopened.select(reopened.activityLog).get()).length;
          final sourceEntries = await reopenedRepositories.nutrition
              .listActiveEntriesForMeal(sourceId);
          expect(sourceEntries, hasLength(4), reason: 'killed ${entry.key}');
          if (entry.key == 'committed') {
            expect(targetMeal, isNotNull);
            expect(copies.map((copy) => copy.id), result.foodEntryIds);
            expect(
              copies.map((copy) => copy.name),
              <String>['Toast', 'Eggs', 'Coffee', 'Juice'],
            );
            expect(activity, seededActivity + 5);
          } else {
            expect(targetMeal, isNull, reason: 'killed ${entry.key}');
            expect(copies, isEmpty, reason: 'killed ${entry.key}');
            expect(activity, seededActivity, reason: 'killed ${entry.key}');
          }
        } finally {
          await reopened.close();
        }
      }
    });

    test(
        'the Meal screen logging a first food into a new Meal leaves the Meal '
        'and its entry together, or neither', () async {
      final killPoints = _KillPointInterceptor(file, directory);
      final database = AppDatabase(
        NativeDatabase(file).interceptWith(killPoints),
      );
      final repositories = TrainingRepositories(database);
      final container = ProviderContainer(
        overrides: [
          trainingRepositoriesProvider.overrideWith((ref) => repositories),
        ],
      );
      addTearDown(container.dispose);
      final args = MealScreenArgs.newMeal(
        NutritionDayDate.fromDateTime(DateTime.now()),
      );
      container.listen(mealScreenControllerProvider(args), (_, __) {});
      final controller =
          container.read(mealScreenControllerProvider(args).notifier);
      final mealId =
          container.read(mealScreenControllerProvider(args)).target.mealId;
      killPoints.arm();

      final result = (await controller.logFoodSnapshot(
        FoodEntrySnapshotDraft(
          mealId: mealId,
          foodId: 'usda-173944',
          name: 'Banana, raw',
          foodSource: FoodSource.usda,
          nutrientsPer100: _per100(),
          isLiquid: false,
          portion: Portion(value: 120, entered: '120', unit: PortionUnit.gram),
        ),
      ))!;
      killPoints.disarm();
      container.dispose();
      await database.close();
      // A kill after the commit: the whole action must survive.
      killPoints.snapshot('committed');

      expect(result.mealId, mealId);
      expect(
        killPoints.snapshots.keys.toSet(),
        <String>{'after-meal', 'after-entry-1', 'before-commit', 'committed'},
      );
      for (final entry in killPoints.snapshots.entries) {
        final reopened = AppDatabase.openFile(entry.value);
        try {
          final meals = await reopened.select(reopened.meals).get();
          final entries = await reopened.select(reopened.foodEntries).get();
          final activity = await reopened.select(reopened.activityLog).get();
          if (entry.key == 'committed') {
            expect(meals.map((row) => row.id), <String>[mealId]);
            expect(entries.map((row) => row.id), <String>[result.foodEntryId]);
            expect(entries.single.mealId, mealId);
            expect(activity.map((row) => row.batchId).toSet(), {
              result.batchId,
            });
            expect(activity, hasLength(2));
          } else {
            expect(meals, isEmpty, reason: 'killed ${entry.key}: no Meal');
            expect(entries, isEmpty, reason: 'killed ${entry.key}: no entry');
            expect(activity, isEmpty, reason: 'killed ${entry.key}');
          }
        } finally {
          await reopened.close();
        }
      }
    });

    test('the Meal screen logging a meal again leaves every copy or none',
        () async {
      // Seed the source Meal through the plain file first.
      final seedDatabase = AppDatabase.openFile(file);
      final seedRepositories = TrainingRepositories(seedDatabase);
      final sourceStartedAt = DateTime(2026, 6, 25, 8);
      final sourceId = await seedRepositories.nutrition.createMeal(
        PendingMeal(
          id: seedRepositories.nutrition.newMealId(),
          startedAt: sourceStartedAt,
          mealTypeName: 'Breakfast',
        ),
      );
      for (final name in <String>['Toast', 'Eggs', 'Coffee', 'Juice']) {
        await seedRepositories.nutrition.logQuickEntry(
          target: ExistingMealTarget(sourceId),
          entry: QuickFoodEntryDraft(name: name, nutrients: _per100()),
        );
      }
      final seededActivity =
          (await seedDatabase.select(seedDatabase.activityLog).get()).length;
      await seedDatabase.close();

      final killPoints = _KillPointInterceptor(file, directory);
      final database = AppDatabase(
        NativeDatabase(file).interceptWith(killPoints),
      );
      final repositories = TrainingRepositories(database);
      final container = ProviderContainer(
        overrides: [
          trainingRepositoriesProvider.overrideWith((ref) => repositories),
        ],
      );
      addTearDown(container.dispose);
      final args = MealScreenArgs.newMeal(
        NutritionDayDate.fromDateTime(DateTime.now()),
      );
      container.listen(mealScreenControllerProvider(args), (_, __) {});
      final controller =
          container.read(mealScreenControllerProvider(args).notifier);
      final targetId =
          container.read(mealScreenControllerProvider(args)).target.mealId;
      killPoints.arm();

      final result = (await controller.logAgain(
        MealHistoryRecord(
          foods: const <MealHistoryFood>[],
          count: 2,
          lastMealId: sourceId,
          lastStartedAt: sourceStartedAt.toUtc(),
        ),
      ))!;
      killPoints.disarm();
      container.dispose();
      await database.close();
      // A kill after the commit: the whole action must survive.
      killPoints.snapshot('committed');

      expect(result.mealId, targetId);
      expect(result.foodEntryIds, hasLength(4));
      expect(
        killPoints.snapshots.keys.toSet(),
        <String>{
          'after-meal',
          'after-entry-1',
          'after-entry-2',
          'after-entry-3',
          'before-commit',
          'committed',
        },
      );
      for (final entry in killPoints.snapshots.entries) {
        final reopened = AppDatabase.openFile(entry.value);
        final reopenedRepositories = TrainingRepositories(reopened);
        try {
          final targetMeal =
              await reopenedRepositories.nutrition.getMealById(targetId);
          final copies = await reopenedRepositories.nutrition
              .listActiveEntriesForMeal(targetId);
          final activity =
              (await reopened.select(reopened.activityLog).get()).length;
          final sourceEntries = await reopenedRepositories.nutrition
              .listActiveEntriesForMeal(sourceId);
          expect(sourceEntries, hasLength(4), reason: 'killed ${entry.key}');
          if (entry.key == 'committed') {
            expect(targetMeal, isNotNull);
            expect(copies.map((copy) => copy.id), result.foodEntryIds);
            expect(
              copies.map((copy) => copy.name),
              <String>['Toast', 'Eggs', 'Coffee', 'Juice'],
            );
            expect(activity, seededActivity + 5);
          } else {
            expect(targetMeal, isNull, reason: 'killed ${entry.key}');
            expect(copies, isEmpty, reason: 'killed ${entry.key}');
            expect(activity, seededActivity, reason: 'killed ${entry.key}');
          }
        } finally {
          await reopened.close();
        }
      }
    });
  });
}

class _KillPointInterceptor extends KillPointSnapshotInterceptor {
  _KillPointInterceptor(super.file, super.directory);

  var _armed = false;
  var _mealInserts = 0;
  var _entryInserts = 0;

  void arm() => _armed = true;

  void disarm() => _armed = false;

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final inserted = await super.runInsert(executor, statement, args);
    if (_armed) {
      if (statement.contains('"meals"')) {
        _mealInserts += 1;
        snapshot('after-meal');
      } else if (statement.contains('"food_entries"')) {
        _entryInserts += 1;
        // Between copies of a Log again: after the first, second and third
        // entry of four.
        if (_mealInserts > 0 && _entryInserts < 4) {
          snapshot('after-entry-$_entryInserts');
        }
      }
    }
    return inserted;
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) {
    if (_armed && _mealInserts > 0) {
      snapshot('before-commit');
    }
    return super.commitTransaction(inner);
  }
}

NutrientVector _per100() {
  return NutrientVector.energyAndMacros(
    energy: NutrientAmount.complete(
      value: 89,
      entered: '89',
      unit: NutrientUnit.kilocalorie,
    ),
    protein: NutrientAmount.complete(
      value: 1,
      entered: '1',
      unit: NutrientUnit.gram,
    ),
    carbohydrate: NutrientAmount.complete(
      value: 23,
      entered: '23',
      unit: NutrientUnit.gram,
    ),
    fat: NutrientAmount.complete(
      value: 0.3,
      entered: '0.3',
      unit: NutrientUnit.gram,
    ),
  );
}
