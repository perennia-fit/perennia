import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/analytics/energy_balance.dart';
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

  group('energyBalanceProvider', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('computes the net on demand from energy-in (derived) and energy-out '
        '(a Metric), read from their own sources', () async {
      const anchor = NutritionDayDate(year: 2026, month: 6, day: 26);

      final metricId = await _createCaloriesBurnedMetric(repositories);
      await _addBurnReading(repositories, metricId, day: 26, value: 2600);
      await _logEnergy(repositories, day: 26, energy: 2100);

      final balance = await _readBalance(repositories, anchor);

      expect(balance.status, EnergyBalanceStatus.computed);
      expect(balance.energyInValue, 2100);
      expect(balance.energyOutValue, 2600);
      expect(balance.net, 2100 - 2600);
      expect(balance.isDeficit, isTrue);
    });

    test('energy-out is sourced from the Metric, never reconstructed from '
        'authored intake', () async {
      const anchor = NutritionDayDate(year: 2026, month: 6, day: 26);

      final metricId = await _createCaloriesBurnedMetric(repositories);
      await _addBurnReading(repositories, metricId, day: 26, value: 2500);
      // Intake differs from the burn — the out-side must equal the Metric, not
      // the logged energy.
      await _logEnergy(repositories, day: 26, energy: 1800);

      final balance = await _readBalance(repositories, anchor);

      expect(balance.energyOutValue, 2500);
      expect(balance.energyInValue, 1800);
    });

    test('energy balance ignores unrelated monitoring Metric Reading changes',
        () async {
      const anchor = NutritionDayDate(year: 2026, month: 6, day: 26);

      final metricId = await _createCaloriesBurnedMetric(repositories);
      await _addBurnReading(repositories, metricId, day: 26, value: 2600);
      final unrelatedMetricId = await _createRestingHeartRateMetric(
        repositories,
      );
      await _logEnergy(repositories, day: 26, energy: 2100);

      final container = ProviderContainer(
        overrides: [
          trainingRepositoriesProvider.overrideWith((ref) => repositories),
        ],
      );
      addTearDown(container.dispose);
      container.read(selectedNutritionDayProvider.notifier).select(anchor);

      final emissions = <EnergyBalance>[];
      final subscriptions = <ProviderSubscription<Object?>>[
        container.listen(caloriesBurnedMetricSeriesProvider, (_, __) {}),
        container.listen(nutritionTrendsControllerProvider, (_, __) {}),
      ];
      final balanceSubscription = container.listen<AsyncValue<EnergyBalance>>(
        energyBalanceProvider,
        (_, next) {
          final data = next.asData?.value;
          if (data != null) {
            emissions.add(data);
          }
        },
      );
      addTearDown(() {
        for (final subscription in subscriptions) {
          subscription.close();
        }
        balanceSubscription.close();
      });

      await _waitFor(() {
        return emissions.any(
          (balance) =>
              balance.energyInValue == 2100 && balance.energyOutValue == 2600,
        );
      });
      await _pumpEventQueue(times: 5);

      emissions.clear();
      await _addMetricReading(
        repositories,
        unrelatedMetricId,
        day: 26,
        value: 55,
        source: 'test-watch',
        externalId: 'rhr-26',
      );
      await _pumpEventQueue(times: 5);

      expect(emissions, isEmpty);
    });

    test('a day with no calories-burned Reading yields an indeterminate net, '
        'never an implicit zero out-side', () async {
      const anchor = NutritionDayDate(year: 2026, month: 6, day: 26);

      // A calories-burned Metric exists, but no Reading on the anchor day.
      final metricId = await _createCaloriesBurnedMetric(repositories);
      await _addBurnReading(repositories, metricId, day: 20, value: 2600);
      await _logEnergy(repositories, day: 26, energy: 2100);

      final balance = await _readBalance(repositories, anchor);

      expect(balance.status, EnergyBalanceStatus.indeterminate);
      expect(balance.net, isNull);
      expect(balance.energyOutValue, isNull);
      // The known in-side is still surfaced.
      expect(balance.energyInValue, 2100);
    });

    test('reading the balance stores no balance value and no in/out '
        'association — the join exists only at read time', () async {
      const anchor = NutritionDayDate(year: 2026, month: 6, day: 26);

      final metricId = await _createCaloriesBurnedMetric(repositories);
      await _addBurnReading(repositories, metricId, day: 26, value: 2600);
      await _logEnergy(repositories, day: 26, energy: 2100);

      // The Activity Log is the write ledger; reading the derived balance must
      // not append to it ("join, never merge", NUTRITION.md §8).
      final before = await repositories.activityLog.listEntries();

      final balance = await _readBalance(repositories, anchor);
      expect(balance.status, EnergyBalanceStatus.computed);
      // Read it again — still no new writes.
      await _readBalance(repositories, anchor);

      final after = await repositories.activityLog.listEntries();
      expect(after.length, before.length);
    });

    test('an incomplete energy-in yields an indeterminate net, never an '
        'implicit zero in-side', () async {
      const anchor = NutritionDayDate(year: 2026, month: 6, day: 26);

      final metricId = await _createCaloriesBurnedMetric(repositories);
      await _addBurnReading(repositories, metricId, day: 26, value: 2600);
      // A logged entry that omits energy makes the day's energy-in incomplete.
      await _logEnergylessEntry(repositories, day: 26);

      final balance = await _readBalance(repositories, anchor);

      expect(balance.status, EnergyBalanceStatus.indeterminate);
      expect(balance.net, isNull);
      expect(balance.energyInValue, isNull);
      // The known out-side is still surfaced.
      expect(balance.energyOutValue, 2600);
    });
  });
}

Future<EnergyBalance> _readBalance(
  TrainingRepositories repositories,
  NutritionDayDate anchor,
) async {
  final container = ProviderContainer(
    overrides: [
      trainingRepositoriesProvider.overrideWith((ref) => repositories),
    ],
  );
  addTearDown(container.dispose);
  container.read(selectedNutritionDayProvider.notifier).select(anchor);

  final subscriptions = <ProviderSubscription<Object?>>[
    container.listen(caloriesBurnedMetricSeriesProvider, (_, __) {}),
    container.listen(nutritionTrendsControllerProvider, (_, __) {}),
    container.listen(energyBalanceProvider, (_, __) {}),
  ];
  addTearDown(() {
    for (final subscription in subscriptions) {
      subscription.close();
    }
  });

  for (var attempt = 0; attempt < 100; attempt += 1) {
    final data = container.read(energyBalanceProvider).asData?.value;
    if (data != null) {
      return data;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('energyBalanceProvider never produced data');
}

Future<String> _createCaloriesBurnedMetric(
  TrainingRepositories repositories,
) {
  return repositories.metrics.createMetric(
    const MetricDraft(
      name: 'Calories Burned',
      unit: 'kilocalorie',
      valueShape: MetricValueShape.scalar,
      group: MetricGroup.monitoring,
      enabled: true,
      pinned: true,
    ),
  );
}

Future<String> _createRestingHeartRateMetric(
  TrainingRepositories repositories,
) {
  return repositories.metrics.createMetric(
    const MetricDraft(
      name: 'Resting Heart Rate',
      unit: 'beats/minute',
      valueShape: MetricValueShape.scalar,
      group: MetricGroup.monitoring,
      enabled: true,
      pinned: true,
    ),
  );
}

Future<void> _addBurnReading(
  TrainingRepositories repositories,
  String metricId, {
  required int day,
  required double value,
}) async {
  await repositories.metrics.upsertIntegrationReadings(
    <IntegrationMetricReadingDraft>[
      IntegrationMetricReadingDraft.scalar(
        metricId: metricId,
        valueEntered: value.toStringAsFixed(0),
        source: 'test-tracker',
        externalId: 'burn-$day',
        // Local noon so the Reading buckets onto the intended local day
        // regardless of the test machine's timezone offset — the same
        // local-day alignment the balance uses for both sides.
        atTime: DateTime(2026, 6, day, 12),
      ),
    ],
  );
}

Future<void> _addMetricReading(
  TrainingRepositories repositories,
  String metricId, {
  required int day,
  required double value,
  required String source,
  required String externalId,
}) async {
  await repositories.metrics.upsertIntegrationReadings(
    <IntegrationMetricReadingDraft>[
      IntegrationMetricReadingDraft.scalar(
        metricId: metricId,
        valueEntered: value.toStringAsFixed(0),
        source: source,
        externalId: externalId,
        atTime: DateTime(2026, 6, day, 12),
      ),
    ],
  );
}

Future<void> _logEnergy(
  TrainingRepositories repositories, {
  required int day,
  required double energy,
}) async {
  final localDate = NutritionDayDate(year: 2026, month: 6, day: day);
  await repositories.nutrition.logQuickEntry(
    meal: MealDraft(
      mealType: 'Dinner',
      startedAt: DateTime.utc(2026, 6, day, 19),
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

/// Logs a Food Entry that omits energy, making the day's energy-in incomplete.
Future<void> _logEnergylessEntry(
  TrainingRepositories repositories, {
  required int day,
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
      name: 'Mystery snack',
      nutrients: NutrientVector.full(<NutrientId, NutrientAmount>{
        // Only protein recorded; energy is left Unknown.
        NutrientId.protein: NutrientAmount.complete(
          value: 12,
          entered: '12',
          unit: NutrientUnit.gram,
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
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (condition()) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  fail('Timed out waiting for condition.');
}
