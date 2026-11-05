import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/nutrition/meal_type_proposal.dart';
import 'package:perennia/features/nutrition/controllers/meal_screen_controller.dart';

/// The Meal screen controller against a real in-memory database
/// (docs/designs/meal-logging.md §3, §4, §6).
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

  const today = NutritionDayDate(year: 2026, month: 6, day: 26);
  const yesterday = NutritionDayDate(year: 2026, month: 6, day: 25);
  const todayArgs = MealScreenArgs.newMeal(today);

  late AppDatabase database;
  late TrainingRepositories repositories;
  late ProviderContainer container;
  late DateTime now;

  setUp(() async {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(database);
    await repositories.nutrition.ensureDefaultMealTypes();
    now = DateTime(2026, 6, 26, 12, 40);
    container = ProviderContainer(
      overrides: [
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
        mealScreenClockProvider.overrideWith((ref) => () => now),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  MealScreenController open(MealScreenArgs args) {
    container.listen(mealScreenControllerProvider(args), (_, __) {});
    return container.read(mealScreenControllerProvider(args).notifier);
  }

  MealScreenState stateOf(MealScreenArgs args) {
    return container.read(mealScreenControllerProvider(args));
  }

  Future<List<MealRow>> mealRows() => database.select(database.meals).get();

  Future<List<ActivityLogEntry>> activity() {
    return repositories.activityLog.listEntries();
  }

  QuickFoodEntryDraft quick(String name) {
    return QuickFoodEntryDraft(name: name, nutrients: _energy(120));
  }

  /// A source Meal yesterday with two Quick Entries, as Your meals offers it.
  Future<MealHistoryRecord> seedSourceMeal() async {
    final sourceId = await repositories.nutrition.createMeal(
      PendingMeal(
        id: repositories.nutrition.newMealId(),
        startedAt: DateTime(2026, 6, 25, 12, 30),
        mealTypeName: 'Lunch',
      ),
    );
    for (final name in <String>['Rice', 'Chicken']) {
      await repositories.nutrition.logQuickEntry(
        target: ExistingMealTarget(sourceId),
        entry: quick(name),
      );
    }
    return MealHistoryRecord(
      foods: const <MealHistoryFood>[],
      count: 2,
      lastMealId: sourceId,
      lastStartedAt: DateTime(2026, 6, 25, 12, 30).toUtc(),
    );
  }

  group('the Meal Type proposal (§4)', () {
    test(
        'follows the pending time until the first write, then stays fixed '
        'even after a time change', () async {
      final controller = open(todayArgs);
      final types = await repositories.nutrition.listMealTypes();

      expect(controller.proposedMealType(types), 'Lunch');
      controller.setPendingTime(DateTime(2026, 6, 26, 19));
      expect(controller.proposedMealType(types), 'Dinner');
      controller.setPendingTime(DateTime(2026, 6, 26, 7, 30));
      expect(controller.proposedMealType(types), 'Breakfast');
      expect(
        (stateOf(todayArgs).target as NewMealTarget).meal.mealTypeName,
        isNull,
        reason: 'the proposal is resolved by the write, not sent',
      );

      final mealId = await controller.addFoodsLater();

      final saved = (await repositories.nutrition.getMealById(mealId!))!;
      expect(saved.mealType, 'Breakfast');
      expect(saved.startedAt, DateTime(2026, 6, 26, 7, 30).toUtc());
      expect(stateOf(todayArgs).phase, MealScreenPhase.saved);
      expect(stateOf(todayArgs).target, isA<ExistingMealTarget>());

      await controller.changeTime(DateTime(2026, 6, 26, 19));

      final moved = (await repositories.nutrition.getMealById(mealId))!;
      expect(moved.startedAt, DateTime(2026, 6, 26, 19).toUtc());
      expect(moved.mealType, 'Breakfast');
    });

    test('a hand-picked Meal Type is stored in place of the proposal',
        () async {
      final controller = open(todayArgs);
      controller.setPendingMealType('Dinner');

      final mealId = await controller.addFoodsLater();

      expect(
        (await repositories.nutrition.getMealById(mealId!))!.mealType,
        'Dinner',
      );
    });
  });

  test('an unchosen time resolves to now at the write, not at screen open',
      () async {
    final controller = open(todayArgs);
    expect(stateOf(todayArgs).pendingStart, isNull);

    final before = DateTime.now().toUtc();
    final mealId = await controller.addFoodsLater();
    final after = DateTime.now().toUtc();

    final saved = (await repositories.nutrition.getMealById(mealId!))!;
    expect(saved.startedAt, isNot(now.toUtc()));
    expect(
      saved.startedAt.isBefore(before.subtract(const Duration(seconds: 1))),
      isFalse,
    );
    expect(
      saved.startedAt.isAfter(after.add(const Duration(seconds: 1))),
      isFalse,
    );
    expect(
      saved.mealType,
      proposeMealType(
        saved.clock,
        await repositories.nutrition.listMealTypes(),
      ),
    );
  });

  test('time-shift buttons replace the time instead of stacking', () {
    final controller = open(todayArgs);

    controller.shiftTime(const Duration(minutes: 15));
    controller.shiftTime(const Duration(minutes: 30));

    expect(
      stateOf(todayArgs).pendingStart,
      DateTime(2026, 6, 26, 12, 10),
    );
  });

  group('the recent-Meal shortcut (§6)', () {
    Future<NutritionDayMealRecord?> shortcut([
      MealScreenArgs args = todayArgs,
    ]) {
      final provider = recentMealShortcutProvider(args);
      container.listen(provider, (_, __) {});
      return container.read(provider.future);
    }

    Future<String> mealAt(Duration beforeNow) {
      return repositories.nutrition.createMeal(
        PendingMeal(
          id: repositories.nutrition.newMealId(),
          startedAt: now.subtract(beforeNow),
          mealTypeName: 'Lunch',
        ),
      );
    }

    test('offers a Meal that started now', () async {
      final mealId = await mealAt(Duration.zero);

      expect((await shortcut())?.meal.id, mealId);
    });

    test('offers a Meal that started exactly 30 minutes ago', () async {
      final mealId = await mealAt(const Duration(minutes: 30));

      expect((await shortcut())?.meal.id, mealId);
    });

    test('does not offer a Meal that started 31 minutes ago', () async {
      await mealAt(const Duration(minutes: 31));

      expect(await shortcut(), isNull);
    });

    test('does not offer a date Meal', () async {
      final startedAt = now.subtract(const Duration(minutes: 10)).toUtc();
      await database.into(database.meals).insert(
            MealsCompanion.insert(
              id: 'meal-date',
              mealType: 'Lunch',
              startedAt: startedAt,
              timezone: 'UTC',
              localDate: Value<String>(today.storageValue),
              timezoneOffsetMinutes: Value<int?>(
                now.timeZoneOffset.inMinutes,
              ),
              timePrecision: const Value<String>('date'),
              updatedAt: startedAt,
            ),
          );

      expect(await shortcut(), isNull);
    });

    test('does not offer a Meal that starts in the future', () async {
      await mealAt(const Duration(minutes: -1));

      expect(await shortcut(), isNull);
    });

    test('offers a Meal with no Food Entries, the most recent first', () async {
      final older = await mealAt(const Duration(minutes: 20));
      await repositories.nutrition.logQuickEntry(
        target: ExistingMealTarget(older),
        entry: quick('Coffee'),
      );
      final empty = await mealAt(const Duration(minutes: 10));

      final offered = (await shortcut())!;
      expect(offered.meal.id, empty);
      expect(offered.entries, isEmpty);
    });

    test('is not offered on another day or on a saved Meal', () async {
      final mealId = await mealAt(const Duration(minutes: 5));

      expect(await shortcut(const MealScreenArgs.newMeal(yesterday)), isNull);
      expect(await shortcut(MealScreenArgs.existing(mealId)), isNull);
    });
  });

  test('closing the screen before any action writes nothing', () async {
    final controller = open(todayArgs);
    controller.setPendingTime(DateTime(2026, 6, 26, 12));
    final pendingId = stateOf(todayArgs).pendingMealId!;
    final activityBefore = (await activity()).length;

    container.dispose();
    container = ProviderContainer();

    expect(await mealRows(), isEmpty);
    expect(await repositories.nutrition.getMealById(pendingId), isNull);
    expect(await activity(), hasLength(activityBefore));
  });

  test('a double tap on a Your meals row writes one Meal in one Batch',
      () async {
    final record = await seedSourceMeal();
    final controller = open(todayArgs);
    final batchesBefore =
        (await activity()).map((entry) => entry.batchId).toSet();

    final first = controller.logAgain(record);
    final second = controller.logAgain(record);

    expect(await second, isNull);
    final result = (await first)!;
    expect(result.foodEntryIds, hasLength(2));
    expect(
      (await mealRows()).map((row) => row.id).toSet(),
      {record.lastMealId, result.mealId},
    );
    final newBatches = (await activity())
        .map((entry) => entry.batchId)
        .toSet()
        .difference(batchesBefore);
    expect(newBatches, {result.batchId});
    expect(stateOf(todayArgs).phase, MealScreenPhase.saved);
    expect(stateOf(todayArgs).savedMealId, result.mealId);
    expect(stateOf(todayArgs).firstBatchId, result.batchId);
    expect(stateOf(todayArgs).writing, isFalse);
  });

  test('a pending Meal that already exists switches the screen to saved',
      () async {
    final controller = open(todayArgs);
    final pendingId = stateOf(todayArgs).pendingMealId!;
    await repositories.nutrition.createMeal(
      PendingMeal(id: pendingId, startedAt: DateTime(2026, 6, 26, 12, 30)),
    );

    final result = await controller.logQuickEntry(quick('Coffee'));

    expect(result, isNull);
    expect(stateOf(todayArgs).phase, MealScreenPhase.saved);
    expect(stateOf(todayArgs).savedMealId, pendingId);
    expect(stateOf(todayArgs).writing, isFalse);
    expect(
      await repositories.nutrition.listActiveEntriesForMeal(pendingId),
      isEmpty,
    );
  });

  test(
      'undoing the first Batch returns the screen to a new Meal with a fresh '
      'pending id', () async {
    final record = await seedSourceMeal();
    final controller = open(todayArgs);
    final firstPendingId = stateOf(todayArgs).pendingMealId!;
    final logged = (await controller.logAgain(record))!;
    expect(logged.mealId, firstPendingId);

    final undo = (await controller.undo(logged.batchId))!;

    expect(undo.hasConflicts, isFalse);
    final state = stateOf(todayArgs);
    expect(state.phase, MealScreenPhase.newMeal);
    expect(state.savedMealId, isNull);
    expect(state.firstBatchId, isNull);
    expect(state.pendingMealId, isNot(firstPendingId));
    expect(state.target, isA<NewMealTarget>());
    expect(
      (await repositories.nutrition.getMealById(firstPendingId))!.deletedAt,
      isNotNull,
    );

    // The fresh id writes a new Meal rather than hitting the archived one.
    final again = (await controller.logAgain(record))!;
    expect(again.mealId, state.pendingMealId);
  });

  test('an undo refused because another Batch added a food is dependent',
      () async {
    final controller = open(todayArgs);
    final first = (await controller.logQuickEntry(quick('Rice')))!;
    await controller.logQuickEntry(quick('Dessert'));

    final undo = (await controller.undo(first.batchId))!;

    expect(
      undo.conflicts.map((conflict) => conflict.reason),
      contains(ActivityLogUndoConflictReason.dependent),
    );
    expect(stateOf(todayArgs).phase, MealScreenPhase.saved);
    expect(stateOf(todayArgs).savedMealId, first.mealId);
    expect(
      (await repositories.nutrition.getMealById(first.mealId))!.deletedAt,
      isNull,
    );
  });

  test('removing the last entry keeps the Meal saved', () async {
    final controller = open(todayArgs);
    final logged = (await controller.logQuickEntry(quick('Apple')))!;

    final batchId = await controller.removeEntry(logged.foodEntryId);

    expect(batchId, isNotNull);
    expect(stateOf(todayArgs).phase, MealScreenPhase.saved);
    expect(stateOf(todayArgs).savedMealId, logged.mealId);
    final provider = savedMealProvider(logged.mealId);
    container.listen(provider, (_, __) {});
    final shown = (await container.read(provider.future))!;
    expect(shown.meal.id, logged.mealId);
    expect(shown.entries, isEmpty);
  });

  test('a past-day screen cannot pick until a time is chosen', () async {
    const args = MealScreenArgs.newMeal(yesterday);
    final controller = open(args);

    expect(controller.isToday, isFalse);
    expect(stateOf(args).timeChosen, isFalse);
    expect(stateOf(args).canPick, isFalse);
    expect(stateOf(todayArgs).canPick, isTrue);

    controller.setPendingTime(DateTime(2026, 6, 25, 7, 30));

    expect(stateOf(args).canPick, isTrue);
    final mealId = await controller.addFoodsLater();
    final saved = (await repositories.nutrition.getMealById(mealId!))!;
    expect(saved.localDate, yesterday);
    expect(saved.mealType, 'Breakfast');
  });

  test('a screen opened on a saved Meal writes into it', () async {
    final mealId = await repositories.nutrition.createMeal(
      PendingMeal(
        id: repositories.nutrition.newMealId(),
        startedAt: DateTime(2026, 6, 26, 12, 30),
        mealTypeName: 'Lunch',
      ),
    );
    final args = MealScreenArgs.existing(mealId);
    final controller = open(args);
    expect(stateOf(args).phase, MealScreenPhase.saved);
    expect(stateOf(args).canPick, isTrue);

    final logged = (await controller.logQuickEntry(quick('Coffee')))!;
    await controller.changeType('Snack');

    expect(logged.mealId, mealId);
    expect(stateOf(args).firstBatchId, isNull);
    expect(
        (await repositories.nutrition.getMealById(mealId))!.mealType, 'Snack');
  });

  test('MealScreenArgs compare by value', () {
    expect(
      const MealScreenArgs.newMeal(today),
      MealScreenArgs.newMeal(NutritionDayDate.parse('2026-06-26')),
    );
    expect(
      const MealScreenArgs.existing('a').hashCode,
      MealScreenArgs.existing(String.fromCharCodes('a'.codeUnits)).hashCode,
    );
    expect(
      const MealScreenArgs.newMeal(today),
      isNot(const MealScreenArgs.newMeal(yesterday)),
    );
  });
}

NutrientVector _energy(double kilocalories) {
  return NutrientVector.energyAndMacros(
    energy: NutrientAmount.complete(
      value: kilocalories,
      entered: kilocalories.toString(),
      unit: NutrientUnit.kilocalorie,
    ),
    protein: NutrientAmount.complete(
      value: 1,
      entered: '1',
      unit: NutrientUnit.gram,
    ),
    carbohydrate: NutrientAmount.complete(
      value: 20,
      entered: '20',
      unit: NutrientUnit.gram,
    ),
    fat: NutrientAmount.complete(
      value: 1,
      entered: '1',
      unit: NutrientUnit.gram,
    ),
  );
}
