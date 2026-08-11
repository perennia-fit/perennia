import '../../../data/repositories/training_repositories.dart';
import '../../analytics/models/lttb_downsampler.dart';

const measurementGraphDownsampleThreshold = graphDownsampleThreshold;

class MeasurementProgressGraph {
  MeasurementProgressGraph._({
    required this.measurement,
    required this.rawPoints,
    required this.renderPoints,
    required this.targetValue,
  });

  factory MeasurementProgressGraph.fromHistory({
    required MeasurementRecord measurement,
    required List<MeasurementHistoryEntry> entries,
    int downsampleThreshold = measurementGraphDownsampleThreshold,
  }) {
    final orderedEntries = entries
        .where((item) => item.measurement.id == measurement.id)
        .toList(growable: false)
      ..sort(_compareHistoryEntries);
    final rawPoints = <MeasurementGraphPoint>[
      for (var index = 0; index < orderedEntries.length; index += 1)
        MeasurementGraphPoint.fromEntry(
          rawIndex: index,
          entry: orderedEntries[index].entry,
          unit: measurement.unit,
        ),
    ];

    return MeasurementProgressGraph._(
      measurement: measurement,
      rawPoints: List<MeasurementGraphPoint>.unmodifiable(rawPoints),
      renderPoints: List<MeasurementGraphPoint>.unmodifiable(
        lttbDownsample<MeasurementGraphPoint>(
          rawPoints,
          downsampleThreshold,
          xValue: (point) => point.rawIndex.toDouble(),
          yValue: (point) => point.value,
        ),
      ),
      targetValue: measurement.goalType == MeasurementGoalType.target
          ? measurement.targetValue
          : null,
    );
  }

  final MeasurementRecord measurement;
  final List<MeasurementGraphPoint> rawPoints;
  final List<MeasurementGraphPoint> renderPoints;
  final double? targetValue;

  bool get hasTargetLine => targetValue != null;

  bool get isDownsampled => renderPoints.length < rawPoints.length;

  MeasurementGraphPoint inspectRawPoint(int renderIndex) {
    final renderPoint = renderPoints[renderIndex];
    return rawPoints[renderPoint.rawIndex];
  }
}

class MeasurementGraphPoint {
  const MeasurementGraphPoint({
    required this.rawIndex,
    required this.entryId,
    required this.measuredAt,
    required this.value,
    required this.valueEntered,
    required this.unit,
    required this.provenance,
    required this.source,
  });

  factory MeasurementGraphPoint.fromEntry({
    required int rawIndex,
    required MeasurementEntryRecord entry,
    required MeasurementUnit unit,
  }) {
    return MeasurementGraphPoint(
      rawIndex: rawIndex,
      entryId: entry.id,
      measuredAt: entry.measuredAt,
      value: entry.value,
      valueEntered: entry.valueEntered,
      unit: unit,
      provenance: entry.provenance,
      source: entry.source,
    );
  }

  final int rawIndex;
  final String entryId;
  final DateTime measuredAt;
  final double value;
  final String valueEntered;
  final MeasurementUnit unit;
  final MetricReadingProvenance provenance;
  final String source;
}

int _compareHistoryEntries(
  MeasurementHistoryEntry left,
  MeasurementHistoryEntry right,
) {
  final timeComparison =
      left.entry.measuredAt.compareTo(right.entry.measuredAt);
  if (timeComparison != 0) {
    return timeComparison;
  }
  return left.entry.id.compareTo(right.entry.id);
}
