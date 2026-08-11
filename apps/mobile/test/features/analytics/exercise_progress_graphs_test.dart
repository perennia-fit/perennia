import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/analytics/exercise_analytics.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/analytics/models/exercise_progress_graphs.dart';

void main() {
  group('exercise progress graphs', () {
    test('LTTB downsampling preserves endpoints and a sharp shape change', () {
      final rawPoints = List<ExerciseGraphPoint>.generate(
        420,
        (index) => ExerciseGraphPoint(
          rawIndex: index,
          setId: 'set-$index',
          achievedAt: DateTime.utc(2026, 1, 1).add(Duration(days: index)),
          value: index == 213 ? 1000 : (index % 30).toDouble(),
          unit: TrainingUnit.kilogram,
        ),
        growable: false,
      );

      final series = ExerciseGraphSeries.fromRawPoints(
        kind: ExerciseGraphKind.volume,
        rawPoints: rawPoints,
        downsampleThreshold: 40,
      );

      expect(series.isDownsampled, isTrue);
      expect(series.renderPoints, hasLength(40));
      expect(series.renderPoints.first.rawIndex, 0);
      expect(series.renderPoints.last.rawIndex, 419);
      expect(
        series.renderPoints.map((point) => point.rawIndex),
        contains(213),
      );
    });

    test('tap inspection returns the raw value represented by a render point',
        () {
      final rawPoints = List<ExerciseGraphPoint>.generate(
        360,
        (index) => ExerciseGraphPoint(
          rawIndex: index,
          setId: 'set-$index',
          achievedAt: DateTime.utc(2026, 1, 1).add(Duration(days: index)),
          value: index == 117 ? 900 : index.toDouble(),
          unit: TrainingUnit.kilogram,
        ),
        growable: false,
      );
      final series = ExerciseGraphSeries.fromRawPoints(
        kind: ExerciseGraphKind.estimatedOneRepMax,
        rawPoints: rawPoints,
        downsampleThreshold: 30,
      );
      final renderIndex = series.renderPoints.indexWhere(
        (point) => point.rawIndex == 117,
      );

      expect(renderIndex, isNonNegative);
      expect(series.inspectRawPoint(renderIndex).setId, 'set-117');
      expect(series.inspectRawPoint(renderIndex).value, 900);
    });

    test('graph collection snapshots caller-provided series lists', () {
      final sourceSeries = <ExerciseGraphSeries>[
        ExerciseGraphSeries.fromRawPoints(
          kind: ExerciseGraphKind.volume,
          rawPoints: <ExerciseGraphPoint>[],
        ),
      ];

      final graphs = ExerciseProgressGraphs(series: sourceSeries);
      sourceSeries.add(
        ExerciseGraphSeries.fromRawPoints(
          kind: ExerciseGraphKind.estimatedOneRepMax,
          rawPoints: <ExerciseGraphPoint>[],
        ),
      );

      expect(graphs.series, hasLength(1));
      expect(() => graphs.series.clear(), throwsUnsupportedError);
    });

    test('analytics result exposes exactly the alpha graph series', () {
      final result = ExerciseAnalyticsResult(
        profile: ExerciseAnalyticsProfile.defaults(
          type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
        ),
        recordCatalog: RecordCatalog(
          repMaxRecords: <AnalyticsRecord>[],
          minAssistanceRecords: <AnalyticsRecord>[],
          maxLoad: null,
          maxReps: null,
          maxDuration: null,
          minDuration: null,
          maxDistance: null,
          fastestPace: null,
        ),
        headlineRecords: <AnalyticsRecord>[
          AnalyticsRecord(
            profile: RecordProfile.repMax,
            setId: 'record',
            achievedAt: DateTime.utc(2026, 1, 1),
            sequence: 0,
            value: 100,
            unit: TrainingUnit.kilogram,
            reps: 5,
          ),
        ],
        estimatedOneRepMax: DerivedSeries.defined(<AnalyticsPoint>[
          AnalyticsPoint(
            setId: 'e1rm',
            achievedAt: DateTime.utc(2026, 1, 2),
            value: 116.1,
            unit: TrainingUnit.kilogram,
          ),
        ]),
        volume: DerivedSeries.defined(<AnalyticsPoint>[
          AnalyticsPoint(
            setId: 'volume',
            achievedAt: DateTime.utc(2026, 1, 3),
            value: 500,
            unit: TrainingUnit.kilogram,
          ),
        ]),
      );

      final graphs = ExerciseProgressGraphs.fromAnalytics(result);

      expect(
        graphs.series.map((series) => series.kind),
        <ExerciseGraphKind>[
          ExerciseGraphKind.headlineRecordTrend,
          ExerciseGraphKind.volume,
          ExerciseGraphKind.estimatedOneRepMax,
        ],
      );
    });

    test('50k-point graph downsampling stays under the overview budget', () {
      final rawPoints = List<ExerciseGraphPoint>.generate(
        50000,
        (index) => ExerciseGraphPoint(
          rawIndex: index,
          setId: 'set-$index',
          achievedAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: index)),
          value: (index % 100).toDouble(),
          unit: TrainingUnit.kilogram,
        ),
        growable: false,
      );
      final stopwatch = Stopwatch()..start();

      final series = ExerciseGraphSeries.fromRawPoints(
        kind: ExerciseGraphKind.volume,
        rawPoints: rawPoints,
      );
      stopwatch.stop();

      expect(series.rawPoints, hasLength(50000));
      expect(series.renderPoints, hasLength(exerciseGraphDownsampleThreshold));
      expect(stopwatch.elapsedMilliseconds, lessThan(300));
    });
  });
}
