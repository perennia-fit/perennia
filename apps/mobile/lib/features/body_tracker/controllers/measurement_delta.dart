import '../../../data/repositories/training_repositories.dart';

enum MeasurementDeltaDirection {
  good,
  bad,
  neutral,
}

class MeasurementDelta {
  const MeasurementDelta({
    required this.value,
    required this.valueEntered,
    required this.direction,
  });

  final double value;
  final String valueEntered;
  final MeasurementDeltaDirection direction;
}

MeasurementDelta? deriveMeasurementDelta({
  required MeasurementTrackSummary summary,
  double? targetValue,
}) {
  final latestEntry = summary.latestEntry;
  final previousEntry = summary.previousEntry;
  if (latestEntry == null || previousEntry == null) {
    return null;
  }

  final rawDelta = latestEntry.value - previousEntry.value;
  final delta = _compare(rawDelta, 0) == 0 ? 0.0 : rawDelta;
  return MeasurementDelta(
    value: delta,
    valueEntered: _formatSignedDelta(delta),
    direction: _directionFor(
      goalType: summary.measurement.goalType,
      delta: delta,
      latestValue: latestEntry.value,
      previousValue: previousEntry.value,
      targetValue: targetValue ?? summary.measurement.targetValue,
    ),
  );
}

MeasurementDeltaDirection _directionFor({
  required MeasurementGoalType goalType,
  required double delta,
  required double latestValue,
  required double previousValue,
  required double? targetValue,
}) {
  if (_compare(delta, 0) == 0) {
    return MeasurementDeltaDirection.neutral;
  }

  return switch (goalType) {
    MeasurementGoalType.increase => delta > 0
        ? MeasurementDeltaDirection.good
        : MeasurementDeltaDirection.bad,
    MeasurementGoalType.decrease => delta < 0
        ? MeasurementDeltaDirection.good
        : MeasurementDeltaDirection.bad,
    MeasurementGoalType.target => _targetDirection(
        latestValue: latestValue,
        previousValue: previousValue,
        targetValue: targetValue,
      ),
  };
}

MeasurementDeltaDirection _targetDirection({
  required double latestValue,
  required double previousValue,
  required double? targetValue,
}) {
  if (targetValue == null) {
    return MeasurementDeltaDirection.neutral;
  }

  final previousDistance = (previousValue - targetValue).abs();
  final latestDistance = (latestValue - targetValue).abs();
  final comparison = _compare(latestDistance, previousDistance);
  if (comparison == 0) {
    return MeasurementDeltaDirection.neutral;
  }
  return comparison < 0
      ? MeasurementDeltaDirection.good
      : MeasurementDeltaDirection.bad;
}

String _formatSignedDelta(double value) {
  if (_compare(value, 0) == 0) {
    return '0';
  }

  final formatted = _stripTrailingZeros(value.toStringAsFixed(5));
  return value > 0 ? '+$formatted' : formatted;
}

String _stripTrailingZeros(String value) {
  var result = value;
  while (result.contains('.') && result.endsWith('0')) {
    result = result.substring(0, result.length - 1);
  }
  if (result.endsWith('.')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

int _compare(double left, double right) {
  const epsilon = 0.000000001;
  final difference = left - right;
  if (difference.abs() < epsilon) {
    return 0;
  }
  return difference < 0 ? -1 : 1;
}
