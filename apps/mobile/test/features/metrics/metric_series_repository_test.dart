import 'dart:async';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
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

  group('MetricRepository.metricSeries', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('reads a metric series straight from its stored Readings', () async {
      final metricId = await _createCaloriesBurnedMetric(repositories);
      await _addReading(repositories, metricId, day: 24, value: 2400);
      await _addReading(repositories, metricId, day: 26, value: 2600);

      final series = await repositories.metrics.metricSeries(metricId);

      expect(series, isNotNull);
      expect(series!.metric.id, metricId);
      expect(series.metric.name, 'Calories Burned');
      // The Readings round-trip their stored, provenance-stamped values.
      expect(
        series.readings.map((r) => r.scalarValue),
        containsAll(<double>[2400, 2600]),
      );
      expect(
        series.readings.every(
          (r) => r.provenance == MetricReadingProvenance.integration,
        ),
        isTrue,
      );
    });

    test('scopes the series to the requested window', () async {
      final metricId = await _createCaloriesBurnedMetric(repositories);
      await _addReading(repositories, metricId, day: 10, value: 2000);
      await _addReading(repositories, metricId, day: 25, value: 2500);
      await _addReading(repositories, metricId, day: 26, value: 2600);

      final series = await repositories.metrics.metricSeries(
        metricId,
        from: DateTime.utc(2026, 6, 24),
        to: DateTime.utc(2026, 6, 27),
      );

      expect(series, isNotNull);
      expect(
        series!.readings.map((r) => r.scalarValue),
        <double>[2500, 2600],
      );
    });

    test('returns null for an unknown metric', () async {
      final series = await repositories.metrics.metricSeries('does-not-exist');
      expect(series, isNull);
    });

    test('reading the series performs no writes (no Activity Log entries)',
        () async {
      final metricId = await _createCaloriesBurnedMetric(repositories);
      await _addReading(repositories, metricId, day: 26, value: 2600);
      final before = await repositories.activityLog.listEntries();

      await repositories.metrics.metricSeries(metricId);

      final after = await repositories.activityLog.listEntries();
      expect(after.length, before.length);
    });

    test('findEnabledMetricByName resolves an enabled monitoring metric',
        () async {
      final metricId = await _createCaloriesBurnedMetric(repositories);

      final metric =
          await repositories.metrics.findEnabledMetricByName('Calories Burned');

      expect(metric, isNotNull);
      expect(metric!.id, metricId);
    });

    test('watchMetricSeries re-emits when a Reading is added', () async {
      final metricId = await _createCaloriesBurnedMetric(repositories);

      final stream = repositories.metrics.watchMetricSeries(metricId);
      // The first emission is the empty series; the next, after a Reading is
      // added, must carry the new stored value.
      final withReading = expectLater(
        stream,
        emitsThrough(
          predicate<MetricSeriesData?>(
            (series) =>
                series != null &&
                series.readings.any((r) => r.scalarValue == 2600),
            'a series containing the 2600 kcal Reading',
          ),
        ),
      );

      await _pumpEventQueue();
      await _addReading(repositories, metricId, day: 26, value: 2600);

      await withReading;
    });

    test('watchMetricSeries ignores unrelated metric Reading changes',
        () async {
      final targetMetricId = await _createCaloriesBurnedMetric(repositories);
      final unrelatedMetricId = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Resting Heart Rate',
          unit: 'beats/minute',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.monitoring,
          enabled: true,
          pinned: true,
        ),
      );

      final emissions = <MetricSeriesData?>[];
      final subscription = repositories.metrics
          .watchMetricSeries(targetMetricId)
          .listen(emissions.add);
      addTearDown(() {
        subscription.cancel().ignore();
      });
      await _waitFor(() => emissions.any((series) {
            return series?.metric.id == targetMetricId;
          }));
      await _pumpEventQueue(times: 5);

      emissions.clear();
      await _addReading(
        repositories,
        unrelatedMetricId,
        day: 26,
        value: 55,
        source: 'test-watch',
        externalId: 'rhr-26',
      );
      await _pumpEventQueue(times: 5);

      subscription.cancel().ignore();
      expect(emissions, isEmpty);
    });

    test(
        'watchMonitoringMetricSeriesByName ignores unrelated monitoring metric Reading changes',
        () async {
      final targetMetricId = await _createCaloriesBurnedMetric(repositories);
      await _addReading(repositories, targetMetricId, day: 25, value: 2500);
      final unrelatedMetricId = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Resting Heart Rate',
          unit: 'beats/minute',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.monitoring,
          enabled: true,
          pinned: true,
        ),
      );

      final emissions = <MetricSeriesData?>[];
      final subscription = repositories.metrics
          .watchMonitoringMetricSeriesByName(
            'Calories Burned',
            from: DateTime.utc(2026, 6, 24),
            to: DateTime.utc(2026, 6, 27),
          )
          .listen(emissions.add);
      addTearDown(() {
        subscription.cancel().ignore();
      });
      await _waitFor(() {
        return emissions.any(
          (series) =>
              series != null &&
              series.metric.id == targetMetricId &&
              series.readings.any((reading) => reading.scalarValue == 2500),
        );
      });
      await _pumpEventQueue(times: 5);

      emissions.clear();
      await _addReading(
        repositories,
        unrelatedMetricId,
        day: 26,
        value: 55,
        source: 'test-watch',
        externalId: 'rhr-26',
      );
      await _pumpEventQueue(times: 5);

      subscription.cancel().ignore();
      expect(emissions, isEmpty);
    });

    test(
        'watchEnabledMetricSeries ignores readings for metrics outside monitoring family',
        () async {
      final targetMetricId = await _createCaloriesBurnedMetric(repositories);
      await _addReading(repositories, targetMetricId, day: 25, value: 2500);
      final bodyFatMetricId = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Body Fat',
          unit: 'percent',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.bodyComposition,
          enabled: true,
          pinned: true,
        ),
      );

      final emissions = <List<MetricSeriesData>>[];
      final subscription = repositories.metrics
          .watchEnabledMetricSeries(
            from: DateTime.utc(2026, 6, 24),
            to: DateTime.utc(2026, 6, 27),
          )
          .listen(emissions.add);
      addTearDown(() {
        subscription.cancel().ignore();
      });
      await _waitFor(() {
        return emissions.any(
          (series) => series.any((data) => data.metric.id == targetMetricId),
        );
      });
      await _pumpEventQueue(times: 5);

      emissions.clear();
      await _addReading(
        repositories,
        bodyFatMetricId,
        day: 26,
        value: 20,
        source: 'test-scale',
        externalId: 'body-fat-26',
      );
      await _pumpEventQueue(times: 5);

      subscription.cancel().ignore();
      expect(emissions, isEmpty);
    });

    test('watchMonitoringSummaries ignores non-monitoring metric readings',
        () async {
      final targetMetricId = await _createCaloriesBurnedMetric(repositories);
      await _addReading(repositories, targetMetricId, day: 25, value: 2500);
      final bodyFatMetricId = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Body Fat',
          unit: 'percent',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.bodyComposition,
          enabled: true,
          pinned: true,
        ),
      );

      final emissions = <List<MonitoringMetricSummary>>[];
      final subscription =
          repositories.metrics.watchMonitoringSummaries().listen(emissions.add);
      addTearDown(() {
        subscription.cancel().ignore();
      });
      await _waitFor(() {
        return emissions.any(
          (summaries) => summaries.any(
            (summary) =>
                summary.metric.id == targetMetricId &&
                summary.latestReading.scalarValue == 2500,
          ),
        );
      });
      await _pumpEventQueue(times: 5);

      emissions.clear();
      await _addReading(
        repositories,
        bodyFatMetricId,
        day: 26,
        value: 20,
        source: 'test-scale',
        externalId: 'body-fat-26',
      );
      await _pumpEventQueue(times: 5);

      subscription.cancel().ignore();
      expect(emissions, isEmpty);
    });

    test('watchMetricSummaries ignores readings for archived metrics',
        () async {
      final targetMetricId = await _createCaloriesBurnedMetric(repositories);
      final archivedMetricId = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Archived Lactate',
          unit: 'mmol/L',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.custom,
          enabled: true,
          pinned: false,
        ),
      );
      await _archiveMetric(database, archivedMetricId);

      final emissions = <List<MetricSummary>>[];
      final subscription =
          repositories.metrics.watchMetricSummaries().listen(emissions.add);
      addTearDown(() {
        subscription.cancel().ignore();
      });
      await _waitFor(() {
        return emissions.any(
          (summaries) =>
              summaries.length == 1 &&
              summaries.single.metric.id == targetMetricId,
        );
      });
      await _pumpEventQueue(times: 5);

      emissions.clear();
      await _insertMetricReading(
        database,
        id: 'archived-metric-reading',
        metricId: archivedMetricId,
        valueEntered: '10',
        atTime: DateTime.utc(2026, 6, 26, 9),
      );
      await _pumpEventQueue(times: 5);

      subscription.cancel().ignore();
      expect(emissions, isEmpty);
    });
  });
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

Future<void> _addReading(
  TrainingRepositories repositories,
  String metricId, {
  required int day,
  required double value,
  String source = 'test-tracker',
  String? externalId,
}) async {
  await repositories.metrics.upsertIntegrationReadings(
    <IntegrationMetricReadingDraft>[
      IntegrationMetricReadingDraft.scalar(
        metricId: metricId,
        valueEntered: value.toStringAsFixed(0),
        source: source,
        externalId: externalId ?? 'calories-$day',
        atTime: DateTime.utc(2026, 6, day, 9),
      ),
    ],
  );
}

Future<void> _archiveMetric(AppDatabase database, String metricId) {
  final deletedAt = DateTime.utc(2026, 6, 25, 9);
  return (database.update(database.metrics)
        ..where((row) => row.id.equals(metricId)))
      .write(
    MetricsCompanion(
      updatedAt: Value<DateTime>(deletedAt),
      deletedAt: Value<DateTime?>(deletedAt),
    ),
  );
}

Future<void> _insertMetricReading(
  AppDatabase database, {
  required String id,
  required String metricId,
  required String valueEntered,
  required DateTime atTime,
}) {
  final scalarValue = double.parse(valueEntered);
  return database.into(database.metricReadings).insert(
        MetricReadingsCompanion.insert(
          id: id,
          metricId: metricId,
          valueJson: '{"shape":"scalar","value":$scalarValue,'
              '"entered":"$valueEntered"}',
          scalarValue: Value<double?>(scalarValue),
          scalarEntered: Value<String?>(valueEntered),
          atTime: Value<DateTime?>(atTime),
          provenance: MetricReadingProvenance.integration.name,
          source: 'test-import',
          externalId: Value<String?>('$id-external'),
          updatedAt: atTime,
        ),
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
