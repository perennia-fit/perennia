import '../../../domain/analytics/exercise_analytics.dart';
import '../../../domain/training/training_dimensions.dart';
import 'lttb_downsampler.dart';

const exerciseGraphDownsampleThreshold = graphDownsampleThreshold;

class ExerciseProgressGraphs {
  ExerciseProgressGraphs({required Iterable<ExerciseGraphSeries> series})
      : series = List<ExerciseGraphSeries>.unmodifiable(series);

  final List<ExerciseGraphSeries> series;

  factory ExerciseProgressGraphs.fromAnalytics(
    ExerciseAnalyticsResult analytics, {
    int downsampleThreshold = exerciseGraphDownsampleThreshold,
  }) {
    final series = <ExerciseGraphSeries>[
      ExerciseGraphSeries.fromRawPoints(
        kind: ExerciseGraphKind.headlineRecordTrend,
        rawPoints: _recordPoints(analytics.headlineRecords),
        downsampleThreshold: downsampleThreshold,
      ),
    ];

    if (analytics.volume.isDefined) {
      series.add(
        ExerciseGraphSeries.fromRawPoints(
          kind: ExerciseGraphKind.volume,
          rawPoints: _analyticsPoints(analytics.volume.points),
          downsampleThreshold: downsampleThreshold,
        ),
      );
    }

    if (analytics.estimatedOneRepMax.isDefined) {
      series.add(
        ExerciseGraphSeries.fromRawPoints(
          kind: ExerciseGraphKind.estimatedOneRepMax,
          rawPoints: _analyticsPoints(analytics.estimatedOneRepMax.points),
          downsampleThreshold: downsampleThreshold,
        ),
      );
    }

    return ExerciseProgressGraphs(
      series: List<ExerciseGraphSeries>.unmodifiable(series),
    );
  }
}

enum ExerciseGraphKind {
  headlineRecordTrend,
  volume,
  estimatedOneRepMax;

  String get id {
    return switch (this) {
      ExerciseGraphKind.headlineRecordTrend => 'headlineRecordTrend',
      ExerciseGraphKind.volume => 'volume',
      ExerciseGraphKind.estimatedOneRepMax => 'estimatedOneRepMax',
    };
  }

  String get title {
    return switch (this) {
      ExerciseGraphKind.headlineRecordTrend => 'Headline record trend',
      ExerciseGraphKind.volume => 'Volume',
      ExerciseGraphKind.estimatedOneRepMax => 'e1RM',
    };
  }

  String get emptyLabel {
    return switch (this) {
      ExerciseGraphKind.headlineRecordTrend => 'No headline records yet',
      ExerciseGraphKind.volume => 'No volume data yet',
      ExerciseGraphKind.estimatedOneRepMax => 'No e1RM data yet',
    };
  }
}

class ExerciseGraphSeries {
  ExerciseGraphSeries._({
    required this.kind,
    required this.rawPoints,
    required this.renderPoints,
  });

  factory ExerciseGraphSeries.fromRawPoints({
    required ExerciseGraphKind kind,
    required List<ExerciseGraphPoint> rawPoints,
    int downsampleThreshold = exerciseGraphDownsampleThreshold,
  }) {
    final orderedRawPoints = rawPoints.toList(growable: false)
      ..sort(_comparePoints);
    final indexedRawPoints = <ExerciseGraphPoint>[
      for (var index = 0; index < orderedRawPoints.length; index += 1)
        orderedRawPoints[index].copyWith(rawIndex: index),
    ];

    return ExerciseGraphSeries._(
      kind: kind,
      rawPoints: List<ExerciseGraphPoint>.unmodifiable(indexedRawPoints),
      renderPoints: List<ExerciseGraphPoint>.unmodifiable(
        lttbDownsample<ExerciseGraphPoint>(
          indexedRawPoints,
          downsampleThreshold,
          xValue: (point) => point.rawIndex.toDouble(),
          yValue: (point) => point.value,
        ),
      ),
    );
  }

  final ExerciseGraphKind kind;
  final List<ExerciseGraphPoint> rawPoints;
  final List<ExerciseGraphPoint> renderPoints;

  bool get isDownsampled => renderPoints.length < rawPoints.length;

  ExerciseGraphPoint inspectRawPoint(int renderIndex) {
    final renderPoint = renderPoints[renderIndex];
    return rawPoints[renderPoint.rawIndex];
  }
}

class ExerciseGraphPoint {
  const ExerciseGraphPoint({
    required this.rawIndex,
    required this.setId,
    required this.achievedAt,
    required this.value,
    required this.unit,
  });

  final int rawIndex;
  final String setId;
  final DateTime achievedAt;
  final double value;
  final TrainingUnit unit;

  ExerciseGraphPoint copyWith({int? rawIndex}) {
    return ExerciseGraphPoint(
      rawIndex: rawIndex ?? this.rawIndex,
      setId: setId,
      achievedAt: achievedAt,
      value: value,
      unit: unit,
    );
  }
}

List<ExerciseGraphPoint> _recordPoints(List<AnalyticsRecord> records) {
  return <ExerciseGraphPoint>[
    for (var index = 0; index < records.length; index += 1)
      ExerciseGraphPoint(
        rawIndex: index,
        setId: records[index].setId,
        achievedAt: records[index].achievedAt,
        value: records[index].value,
        unit: records[index].unit,
      ),
  ];
}

List<ExerciseGraphPoint> _analyticsPoints(List<AnalyticsPoint> points) {
  return <ExerciseGraphPoint>[
    for (var index = 0; index < points.length; index += 1)
      ExerciseGraphPoint(
        rawIndex: index,
        setId: points[index].setId,
        achievedAt: points[index].achievedAt,
        value: points[index].value,
        unit: points[index].unit,
      ),
  ];
}

int _comparePoints(ExerciseGraphPoint left, ExerciseGraphPoint right) {
  final timeComparison = left.achievedAt.compareTo(right.achievedAt);
  if (timeComparison != 0) {
    return timeComparison;
  }
  if (left.rawIndex != right.rawIndex) {
    return left.rawIndex.compareTo(right.rawIndex);
  }
  return left.setId.compareTo(right.setId);
}
