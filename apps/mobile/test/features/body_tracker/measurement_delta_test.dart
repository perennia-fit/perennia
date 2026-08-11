import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/body_tracker/controllers/measurement_delta.dart';

void main() {
  group('deriveMeasurementDelta', () {
    test('returns no delta when there is only one entry', () {
      final delta = deriveMeasurementDelta(
        summary: _summary(
          goalType: MeasurementGoalType.decrease,
          latest: 82,
        ),
      );

      expect(delta, isNull);
    });

    test('maps increase goals by positive progress', () {
      final good = _derive(
        goalType: MeasurementGoalType.increase,
        latest: 44.25,
        previous: 42,
      );
      final bad = _derive(
        goalType: MeasurementGoalType.increase,
        latest: 40,
        previous: 42,
      );

      expect(good.value, 2.25);
      expect(good.valueEntered, '+2.25');
      expect(good.direction, MeasurementDeltaDirection.good);
      expect(bad.valueEntered, '-2');
      expect(bad.direction, MeasurementDeltaDirection.bad);
    });

    test('maps decrease goals by negative progress', () {
      final good = _derive(
        goalType: MeasurementGoalType.decrease,
        latest: 80,
        previous: 82,
      );
      final bad = _derive(
        goalType: MeasurementGoalType.decrease,
        latest: 84,
        previous: 82,
      );

      expect(good.valueEntered, '-2');
      expect(good.direction, MeasurementDeltaDirection.good);
      expect(bad.valueEntered, '+2');
      expect(bad.direction, MeasurementDeltaDirection.bad);
    });

    test('maps target goals by movement toward the target value', () {
      final toward = _derive(
        goalType: MeasurementGoalType.target,
        latest: 90,
        previous: 100,
        targetValue: 80,
      );
      final away = _derive(
        goalType: MeasurementGoalType.target,
        latest: 110,
        previous: 100,
        targetValue: 80,
      );
      final sameDistance = _derive(
        goalType: MeasurementGoalType.target,
        latest: 70,
        previous: 90,
        targetValue: 80,
      );

      expect(toward.valueEntered, '-10');
      expect(toward.direction, MeasurementDeltaDirection.good);
      expect(away.valueEntered, '+10');
      expect(away.direction, MeasurementDeltaDirection.bad);
      expect(sameDistance.valueEntered, '-20');
      expect(sameDistance.direction, MeasurementDeltaDirection.neutral);
    });

    test('keeps target goals neutral until a target value is available', () {
      final delta = _derive(
        goalType: MeasurementGoalType.target,
        latest: 90,
        previous: 100,
      );

      expect(delta.valueEntered, '-10');
      expect(delta.direction, MeasurementDeltaDirection.neutral);
    });

    test('maps equal values to neutral', () {
      final delta = _derive(
        goalType: MeasurementGoalType.decrease,
        latest: 82,
        previous: 82,
      );

      expect(delta.value, 0);
      expect(delta.valueEntered, '0');
      expect(delta.direction, MeasurementDeltaDirection.neutral);
    });

    test('matches the shared golden vectors', () async {
      final vector = jsonDecode(
        await _vectorFile('m9-measurement-delta.json').readAsString(),
      ) as Map<String, Object?>;
      final cases = vector['cases']! as List<Object?>;

      for (final caseObject in cases) {
        final caseData = caseObject! as Map<String, Object?>;
        final input = caseData['input']! as Map<String, Object?>;
        final expected = caseData['expected']! as Map<String, Object?>;
        final reason = caseData['name']! as String;

        final delta = deriveMeasurementDelta(
          summary: _summary(
            goalType: MeasurementGoalType.values.byName(
              input['goalType']! as String,
            ),
            latest: input['latest']! as double,
            previous: input['previous'] as double?,
          ),
          targetValue: input['target'] as double?,
        );

        if (expected['delta'] == null && expected.containsKey('delta')) {
          expect(delta, isNull, reason: reason);
          continue;
        }

        expect(delta, isNotNull, reason: reason);
        expect(delta!.value, expected['value'], reason: reason);
        expect(delta.valueEntered, expected['valueEntered'], reason: reason);
        expect(delta.direction.name, expected['direction'], reason: reason);
      }
    });
  });
}

MeasurementDelta _derive({
  required MeasurementGoalType goalType,
  required double latest,
  required double previous,
  double? targetValue,
}) {
  return deriveMeasurementDelta(
    summary: _summary(
      goalType: goalType,
      latest: latest,
      previous: previous,
    ),
    targetValue: targetValue,
  )!;
}

MeasurementTrackSummary _summary({
  required MeasurementGoalType goalType,
  required double latest,
  double? previous,
}) {
  final measurement = MeasurementRecord(
    id: 'measurement-1',
    name: 'Body Weight',
    unit: MeasurementUnit.kilogram,
    goalType: goalType,
    enabled: true,
    sortOrder: 0,
    updatedAt: _baseTime,
  );

  return MeasurementTrackSummary(
    measurement: measurement,
    latestEntry: _entry(
      id: 'entry-latest',
      measurementId: measurement.id,
      value: latest,
      measuredAt: _baseTime.add(const Duration(days: 1)),
    ),
    previousEntry: previous == null
        ? null
        : _entry(
            id: 'entry-previous',
            measurementId: measurement.id,
            value: previous,
            measuredAt: _baseTime,
          ),
  );
}

MeasurementEntryRecord _entry({
  required String id,
  required String measurementId,
  required double value,
  required DateTime measuredAt,
}) {
  return MeasurementEntryRecord(
    id: id,
    measurementId: measurementId,
    value: value,
    valueEntered: _enteredValue(value),
    measuredAt: measuredAt,
    updatedAt: measuredAt,
  );
}

String _enteredValue(double value) {
  final text = value.toStringAsFixed(5);
  return text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

final _baseTime = DateTime.utc(2026, 6, 23, 7, 30);

File _vectorFile(String name) {
  var directory = Directory.current;
  for (var depth = 0; depth < 6; depth += 1) {
    final candidate = File(
      '${directory.path}${Platform.pathSeparator}packages'
      '${Platform.pathSeparator}golden-vectors'
      '${Platform.pathSeparator}vectors'
      '${Platform.pathSeparator}$name',
    );
    if (candidate.existsSync()) {
      return candidate;
    }
    directory = directory.parent;
  }
  throw StateError('Golden vector not found: $name.');
}
