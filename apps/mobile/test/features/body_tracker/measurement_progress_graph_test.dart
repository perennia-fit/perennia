import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/body_tracker/models/measurement_progress_graph.dart';

void main() {
  group('measurement progress graph', () {
    test('projects measurement history into chronological graph points', () {
      final measurement = _measurement(
        goalType: MeasurementGoalType.target,
        targetValue: 80,
      );
      final graph = MeasurementProgressGraph.fromHistory(
        measurement: measurement,
        entries: <MeasurementHistoryEntry>[
          _historyEntry(measurement, id: 'entry-2', day: 2, value: 81),
          _historyEntry(measurement, id: 'entry-1', day: 1, value: 83),
        ],
      );

      expect(
        graph.rawPoints.map((point) => point.entryId),
        <String>['entry-1', 'entry-2'],
      );
      expect(graph.rawPoints.map((point) => point.value), <double>[83, 81]);
      expect(graph.renderPoints, hasLength(2));
      expect(graph.hasTargetLine, isTrue);
      expect(graph.targetValue, 80);
    });

    test('does not expose target lines for increase or decrease goals', () {
      final increaseGraph = MeasurementProgressGraph.fromHistory(
        measurement: _measurement(goalType: MeasurementGoalType.increase),
        entries: const <MeasurementHistoryEntry>[],
      );
      final decreaseGraph = MeasurementProgressGraph.fromHistory(
        measurement: _measurement(goalType: MeasurementGoalType.decrease),
        entries: const <MeasurementHistoryEntry>[],
      );

      expect(increaseGraph.hasTargetLine, isFalse);
      expect(increaseGraph.targetValue, isNull);
      expect(decreaseGraph.hasTargetLine, isFalse);
      expect(decreaseGraph.targetValue, isNull);
    });

    test('downsamples large histories with LTTB and preserves endpoints', () {
      final measurement = _measurement();
      final entries = List<MeasurementHistoryEntry>.generate(
        420,
        (index) => _historyEntry(
          measurement,
          id: 'entry-$index',
          day: index,
          value: index == 213 ? 1000 : (index % 30).toDouble(),
        ),
        growable: false,
      );

      final graph = MeasurementProgressGraph.fromHistory(
        measurement: measurement,
        entries: entries.reversed.toList(growable: false),
        downsampleThreshold: 40,
      );

      expect(graph.isDownsampled, isTrue);
      expect(graph.rawPoints, hasLength(420));
      expect(graph.renderPoints, hasLength(40));
      expect(graph.renderPoints.first.entryId, 'entry-0');
      expect(graph.renderPoints.last.entryId, 'entry-419');
      expect(
        graph.renderPoints.map((point) => point.entryId),
        contains('entry-213'),
      );
      final renderIndex = graph.renderPoints.indexWhere(
        (point) => point.entryId == 'entry-213',
      );
      expect(graph.inspectRawPoint(renderIndex).value, 1000);
    });
  });
}

MeasurementRecord _measurement({
  MeasurementGoalType goalType = MeasurementGoalType.decrease,
  double? targetValue,
}) {
  return MeasurementRecord(
    id: 'measurement-1',
    name: 'Body Weight',
    unit: MeasurementUnit.kilogram,
    goalType: goalType,
    targetValue: targetValue,
    enabled: true,
    sortOrder: 0,
    updatedAt: DateTime.utc(2026, 6, 23),
  );
}

MeasurementHistoryEntry _historyEntry(
  MeasurementRecord measurement, {
  required String id,
  required int day,
  required double value,
}) {
  return MeasurementHistoryEntry(
    measurement: measurement,
    entry: MeasurementEntryRecord(
      id: id,
      measurementId: measurement.id,
      value: value,
      valueEntered: _formatValue(value),
      measuredAt: DateTime.utc(2026, 1, 1).add(Duration(days: day)),
      updatedAt: DateTime.utc(2026, 1, 1).add(Duration(days: day)),
    ),
  );
}

String _formatValue(double value) {
  final fixed = value.toStringAsFixed(5);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}
