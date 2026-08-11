import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';

final metricRepositoryProvider = Provider<MetricRepository>((ref) {
  return ref.watch(trainingRepositoriesProvider).metrics;
});

final metricsControllerProvider =
    StreamNotifierProvider<MetricsController, MetricsState>(
  MetricsController.new,
);

class MetricsController extends StreamNotifier<MetricsState> {
  @override
  Stream<MetricsState> build() async* {
    final repository = ref.watch(metricRepositoryProvider);

    yield* repository.watchMetricSummaries().map(
          (summaries) => MetricsState(summaries: summaries),
        );
  }

  /// Creates a manually-authored `Metric` — the general "Custom"
  /// counterpart to Body Tracker's bodyComposition-only creation flow. This
  /// is what lets a user get a biomarker (testosterone, estradiol, HbA1c…)
  /// into the catalogue at all: `unit` is free text (a lab unit like
  /// "ng/dL" isn't one of Body Tracker's fixed physical `MeasurementUnit`s),
  /// and the Metric lands in `MetricGroup.custom` since it isn't body
  /// composition, monitoring, or performance. Scalar-only for now — the
  /// only shape a manually-entered Reading can take.
  Future<String> createMetric({
    required String name,
    required String unit,
  }) {
    return ref.read(metricRepositoryProvider).createMetric(
          MetricDraft(
            name: name,
            unit: unit,
            valueShape: MetricValueShape.scalar,
            group: MetricGroup.custom,
            enabled: true,
            pinned: false,
          ),
        );
  }

  /// Logs a manually-entered scalar `Reading` against an existing `Metric`
  /// — the read path (`Effect` view, `Metric` detail chart/
  /// history) already treats any Metric's Readings uniformly regardless of
  /// group; this is the write path that had no UI entry point outside Body
  /// Tracker before this slice.
  Future<String> logReading({
    required String metricId,
    required String valueEntered,
    required DateTime measuredAt,
    String? comment,
  }) {
    return ref.read(metricRepositoryProvider).createManualReading(
          ManualMetricReadingDraft.scalar(
            metricId: metricId,
            valueEntered: valueEntered,
            atTime: measuredAt,
            source: 'manual',
            comment: comment == null || comment.isEmpty ? null : comment,
          ),
        );
  }
}

final class MetricsState {
  MetricsState({
    required List<MetricSummary> summaries,
  }) : summaries = List<MetricSummary>.unmodifiable(summaries);

  final List<MetricSummary> summaries;
}

final metricSeriesControllerProvider =
    StreamProvider.family<MetricSeriesData?, String>((ref, metricId) async* {
  final repository = ref.watch(metricRepositoryProvider);
  yield* repository.watchMetricSeries(metricId);
});
