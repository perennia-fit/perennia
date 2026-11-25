import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/metrics/controllers/metrics_controller.dart';

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

  test(
      'the explorer leaves out Lab Metrics and keeps a custom Metric of the '
      'same name (lab-results.md, Excluded elsewhere)', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repositories = TrainingRepositories(database);
    MetricDraft draft({String? labTestKey}) => MetricDraft(
          name: 'Ferritin',
          unit: 'ng/mL',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.custom,
          enabled: true,
          pinned: false,
          labTestKey: labTestKey,
        );
    final labMetricId = await repositories.metrics.createMetric(
      draft(labTestKey: 'ferritin'),
    );
    final customMetricId = await repositories.metrics.createMetric(draft());
    final container = ProviderContainer(
      overrides: [
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
      ],
    );
    addTearDown(container.dispose);

    final subscription = container.listen(
      metricsControllerProvider,
      (previous, next) {},
    );
    addTearDown(subscription.close);
    final state = await container.read(metricsControllerProvider.future);

    final ids = state.summaries.map((summary) => summary.metric.id);
    expect(ids, contains(customMetricId));
    expect(ids, isNot(contains(labMetricId)));
    // Other readers of active Metrics, such as the Effect outcome picker,
    // still list the Lab Metric.
    expect(
      (await repositories.metrics.listMetricOptions()).map((m) => m.id),
      containsAll(<String>[labMetricId, customMetricId]),
    );
  });

  test('metrics state defensively copies summaries', () {
    final summaries = <MetricSummary>[
      MetricSummary(
        metric: _metricRecord(
          id: 'metric-resting-heart-rate',
          name: 'Resting Heart Rate',
          unit: 'bpm',
        ),
      ),
    ];

    final state = MetricsState(summaries: summaries);

    summaries.clear();

    expect(state.summaries, hasLength(1));
    expect(() => state.summaries.clear(), throwsUnsupportedError);
  });
}

MetricRecord _metricRecord({
  required String id,
  required String name,
  required String unit,
}) {
  return MetricRecord(
    id: id,
    name: name,
    unit: unit,
    valueShape: MetricValueShape.scalar,
    group: MetricGroup.custom,
    enabled: true,
    pinned: false,
    sortOrder: 0,
    updatedAt: DateTime.utc(2026, 7, 9),
  );
}
