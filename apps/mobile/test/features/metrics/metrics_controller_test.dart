import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/metrics/controllers/metrics_controller.dart';

void main() {
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
