import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';

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

  group('nutrition trends range read', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('reads every requested day, padding empty days with no meals',
        () async {
      await _logDay(repositories, day: 24, energy: 1900);
      await _logDay(repositories, day: 26, energy: 2100);

      final range = NutritionDayRange(
        start: const NutritionDayDate(year: 2026, month: 6, day: 24),
        end: const NutritionDayDate(year: 2026, month: 6, day: 26),
      );
      final days = await repositories.nutrition.nutritionDaysInRange(range);

      expect(days, hasLength(3));
      expect(
        days.map((day) => day.localDate.day),
        <int>[24, 25, 26],
      );
      // The middle day had no meals logged — it is a genuine empty day, not a
      // gap; its energy total is a complete zero.
      final empty = days[1];
      expect(empty.localDate.day, 25);
      expect(empty.meals, isEmpty);
      expect(empty.totals[NutrientId.energy].value, 0);
      expect(empty.totals[NutrientId.energy].isComplete, isTrue);

      // The logged days round-trip their derived totals straight off snapshots.
      expect(days.first.totals[NutrientId.energy].value, 1900);
      expect(days.last.totals[NutrientId.energy].value, 2100);
    });

    test('a trend over the range distinguishes unknown from genuinely zero',
        () async {
      // 25th: a full quick entry with known carbs.
      await _logDay(repositories, day: 25, energy: 2000, carbohydrate: 220);
      // 26th: a quick entry that only recorded energy — carbs unknown.
      await _logEnergyOnly(repositories, day: 26, energy: 1500);

      final range = NutritionDayRange(
        start: const NutritionDayDate(year: 2026, month: 6, day: 25),
        end: const NutritionDayDate(year: 2026, month: 6, day: 26),
      );
      final days = await repositories.nutrition.nutritionDaysInRange(range);

      final trend = NutritionTrend.forNutrient(
        nutrient: NutrientId.carbohydrate,
        range: range,
        days: days,
        target: NutritionGoalTarget(
          nutrient: NutrientId.carbohydrate,
          value: 250,
          entered: '250',
        ),
      );

      final known = trend.points.firstWhere((p) => p.localDate.day == 25);
      final unknown = trend.points.firstWhere((p) => p.localDate.day == 26);
      expect(known.isUnknown, isFalse);
      expect(known.total.value, 220);
      // The energy-only day must not read as 0 g carbs.
      expect(unknown.isUnknown, isTrue);
      expect(trend.completePoints.map((p) => p.localDate.day), <int>[25]);
    });

    test('the range read performs no writes (no Activity Log entries)',
        () async {
      await _logDay(repositories, day: 26, energy: 2100);
      final before = await repositories.activityLog.listEntries();

      final range = NutritionDayRange.trailing(
        const NutritionDayDate(year: 2026, month: 6, day: 26),
        days: 7,
      );
      await repositories.nutrition.nutritionDaysInRange(range);

      final after = await repositories.activityLog.listEntries();
      expect(after.length, before.length);
    });

    test('watchNutritionDay emits an empty day with no logged meals', () async {
      const localDate = NutritionDayDate(year: 2026, month: 6, day: 26);

      final emissions = <NutritionDayRecord>[];
      final subscription = repositories.nutrition
          .watchNutritionDay(localDate)
          .listen(emissions.add);
      addTearDown(() {
        subscription.cancel().ignore();
      });

      await _waitFor(() => emissions.isNotEmpty);

      final day = emissions.last;
      expect(day.localDate, localDate);
      expect(day.meals, isEmpty);
      expect(day.totals[NutrientId.energy].value, 0);
      subscription.cancel().ignore();
    });

    test('watchNutritionDaysInRange emits empty days with no logged meals',
        () async {
      final range = NutritionDayRange(
        start: const NutritionDayDate(year: 2026, month: 6, day: 25),
        end: const NutritionDayDate(year: 2026, month: 6, day: 26),
      );

      final emissions = <List<NutritionDayRecord>>[];
      final subscription = repositories.nutrition
          .watchNutritionDaysInRange(range)
          .listen(emissions.add);
      addTearDown(() {
        subscription.cancel().ignore();
      });

      await _waitFor(() => emissions.isNotEmpty);

      final days = emissions.last;
      expect(days, hasLength(2));
      expect(days.map((day) => day.localDate.day), <int>[25, 26]);
      expect(days.expand((day) => day.meals), isEmpty);
      expect(days.last.totals[NutrientId.energy].value, 0);
      subscription.cancel().ignore();
    });

    test('watchNutritionDaysInRange re-emits when a Food Entry changes',
        () async {
      final range = NutritionDayRange(
        start: const NutritionDayDate(year: 2026, month: 6, day: 25),
        end: const NutritionDayDate(year: 2026, month: 6, day: 26),
      );

      final emissions = <List<NutritionDayRecord>>[];
      final subscription = repositories.nutrition
          .watchNutritionDaysInRange(range)
          .listen(emissions.add);

      await _pumpEventQueue();
      await _logDay(repositories, day: 26, energy: 2100);
      await _pumpEventQueue();

      await subscription.cancel();

      expect(emissions, isNotEmpty);
      final latest = emissions.last;
      expect(latest, hasLength(2));
      expect(latest.last.totals[NutrientId.energy].value, 2100);
    });

    test('watchNutritionDay ignores Food Entry changes on other local dates',
        () async {
      const localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
      await _logDay(repositories, day: 26, energy: 2100);

      final emissions = <NutritionDayRecord>[];
      final subscription = repositories.nutrition
          .watchNutritionDay(localDate)
          .listen(emissions.add);
      addTearDown(() {
        subscription.cancel().ignore();
      });

      await _waitFor(() => emissions.any(
            (day) => day.totals[NutrientId.energy].value == 2100,
          ));
      await _pumpEventQueue(times: 5);
      emissions.clear();

      await _logDay(repositories, day: 27, energy: 2500);
      await _pumpEventQueue(times: 5);

      expect(emissions, isEmpty);
      subscription.cancel().ignore();
    });

    test('watchNutritionDaysInRange ignores Food Entry changes outside range',
        () async {
      final range = NutritionDayRange(
        start: const NutritionDayDate(year: 2026, month: 6, day: 25),
        end: const NutritionDayDate(year: 2026, month: 6, day: 26),
      );
      await _logDay(repositories, day: 26, energy: 2100);

      final emissions = <List<NutritionDayRecord>>[];
      final subscription = repositories.nutrition
          .watchNutritionDaysInRange(range)
          .listen(emissions.add);
      addTearDown(() {
        subscription.cancel().ignore();
      });

      await _waitFor(() => emissions.any(
            (days) => days.last.totals[NutrientId.energy].value == 2100,
          ));
      await _pumpEventQueue(times: 5);
      emissions.clear();

      await _logDay(repositories, day: 27, energy: 2500);
      await _pumpEventQueue(times: 5);

      expect(emissions, isEmpty);
      subscription.cancel().ignore();
    });
  });
}

Future<void> _logDay(
  TrainingRepositories repositories, {
  required int day,
  required double energy,
  double? carbohydrate,
}) async {
  final localDate = NutritionDayDate(year: 2026, month: 6, day: day);
  await repositories.nutrition.logQuickEntry(
    meal: MealDraft(
      mealType: 'Breakfast',
      startedAt: DateTime.utc(2026, 6, day, 8),
      timezone: 'UTC',
      localDate: localDate,
    ),
    entry: QuickFoodEntryDraft(
      name: 'Logged food',
      nutrients: NutrientVector.energyAndMacros(
        energy: NutrientAmount.complete(
          value: energy,
          entered: energy.toStringAsFixed(0),
          unit: NutrientUnit.kilocalorie,
        ),
        protein: NutrientAmount.complete(
          value: 100,
          entered: '100',
          unit: NutrientUnit.gram,
        ),
        carbohydrate: carbohydrate == null
            ? NutrientAmount.unknown(NutrientUnit.gram)
            : NutrientAmount.complete(
                value: carbohydrate,
                entered: carbohydrate.toStringAsFixed(0),
                unit: NutrientUnit.gram,
              ),
        fat: NutrientAmount.complete(
          value: 60,
          entered: '60',
          unit: NutrientUnit.gram,
        ),
      ),
    ),
    actor: 'tester',
  );
}

Future<void> _logEnergyOnly(
  TrainingRepositories repositories, {
  required int day,
  required double energy,
}) async {
  final localDate = NutritionDayDate(year: 2026, month: 6, day: day);
  await repositories.nutrition.logQuickEntry(
    meal: MealDraft(
      mealType: 'Snack',
      startedAt: DateTime.utc(2026, 6, day, 15),
      timezone: 'UTC',
      localDate: localDate,
    ),
    entry: QuickFoodEntryDraft(
      name: 'Quick calories',
      nutrients: NutrientVector.full(<NutrientId, NutrientAmount>{
        NutrientId.energy: NutrientAmount.complete(
          value: energy,
          entered: energy.toStringAsFixed(0),
          unit: NutrientUnit.kilocalorie,
        ),
      }),
    ),
    actor: 'tester',
  );
}

Future<void> _pumpEventQueue({int times = 1}) async {
  for (var i = 0; i < times; i += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for repository stream.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
