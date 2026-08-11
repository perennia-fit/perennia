import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/analytics/series_families.dart';
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

  group('seriesFamiliesProvider', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('joins a stored Metric series and a derived nutrition series, '
        'from their own sources, without merging', () async {
      const anchor = NutritionDayDate(year: 2026, month: 6, day: 26);

      // Metric family: a stored Reading on a calories-burned Metric.
      final metricId = await _createCaloriesBurnedMetric(repositories);
      await _addBurnReading(repositories, metricId, day: 26, value: 2600);

      // Nutrition family: a logged meal → derived energy-in analytic.
      await _logEnergy(repositories, day: 26, energy: 2100);

      final container = ProviderContainer(
        overrides: [
          trainingRepositoriesProvider.overrideWith((ref) => repositories),
        ],
      );
      addTearDown(container.dispose);
      container.read(selectedNutritionDayProvider.notifier).select(anchor);

      final families = await _readFamilies(container);

      // Both families are present, each from its own source.
      expect(families.hasBothFamilies, isTrue);

      final metricSeries = families.metricSeries.single;
      expect(metricSeries.family, SeriesFamily.metric);
      expect(metricSeries.name, 'Calories Burned');
      expect(
        metricSeries.data.map((d) => d.value),
        contains(2600),
      );

      final energySeries = families.nutritionSeries.firstWhere(
        (s) => s.name == 'Calories',
      );
      expect(energySeries.family, SeriesFamily.nutritionAnalytic);
      final anchorPoint = energySeries.data.firstWhere(
        (d) => d.localDate == anchor,
      );
      expect(anchorPoint.value, 2100);

      // The families never collapse into one list — the metric value is not in
      // the nutrition family and vice-versa.
      expect(
        families.nutritionSeries.expand((s) => s.data).map((d) => d.value),
        isNot(contains(2600)),
      );
      expect(
        families.metricSeries.expand((s) => s.data).map((d) => d.value),
        isNot(contains(2100)),
      );
    });

    test('preserves a nutrition unknown gap and never blends it into a '
        'Metric value', () async {
      const anchor = NutritionDayDate(year: 2026, month: 6, day: 26);

      final metricId = await _createCaloriesBurnedMetric(repositories);
      await _addBurnReading(repositories, metricId, day: 26, value: 2600);
      // Energy-only quick entry on the anchor: carbs are unknown.
      await _logEnergy(repositories, day: 26, energy: 2100);

      final container = ProviderContainer(
        overrides: [
          trainingRepositoriesProvider.overrideWith((ref) => repositories),
        ],
      );
      addTearDown(container.dispose);
      container.read(selectedNutritionDayProvider.notifier).select(anchor);

      final families = await _readFamilies(container);

      final carbSeries = families.nutritionSeries.firstWhere(
        (s) => s.name == 'Carbs',
      );
      final anchorCarb = carbSeries.data.firstWhere(
        (d) => d.localDate == anchor,
      );
      // The unknown carb total is a gap (null), never a coerced 0 and never the
      // Metric's 2600.
      expect(anchorCarb.isUnknown, isTrue);
      expect(anchorCarb.value, isNull);
    });

    test('reads the metric family even with no logged nutrition', () async {
      const anchor = NutritionDayDate(year: 2026, month: 6, day: 26);
      final metricId = await _createCaloriesBurnedMetric(repositories);
      await _addBurnReading(repositories, metricId, day: 26, value: 2600);

      final container = ProviderContainer(
        overrides: [
          trainingRepositoriesProvider.overrideWith((ref) => repositories),
        ],
      );
      addTearDown(container.dispose);
      container.read(selectedNutritionDayProvider.notifier).select(anchor);

      final families = await _readFamilies(container);

      expect(families.hasMetricFamily, isTrue);
      expect(families.metricSeries.single.name, 'Calories Burned');
    });
  });
}

Future<TwoSeriesFamilies> _readFamilies(ProviderContainer container) async {
  // Keep the dependency graph (both family streams + the combined provider)
  // alive while their reactive streams produce their first values.
  final subscriptions = <ProviderSubscription<Object?>>[
    container.listen(metricSeriesFamilyProvider, (_, __) {}),
    container.listen(nutritionTrendsControllerProvider, (_, __) {}),
    container.listen(seriesFamiliesProvider, (_, __) {}),
  ];
  addTearDown(() {
    for (final subscription in subscriptions) {
      subscription.close();
    }
  });

  for (var attempt = 0; attempt < 100; attempt += 1) {
    final data = container.read(seriesFamiliesProvider).asData?.value;
    if (data != null) {
      return data;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('seriesFamiliesProvider never produced data');
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
        atTime: DateTime.utc(2026, 6, day, 18),
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
