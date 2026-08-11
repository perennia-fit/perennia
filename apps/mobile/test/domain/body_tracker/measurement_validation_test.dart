import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/body_tracker/measurement_validation.dart';

void main() {
  group('measurement validation', () {
    test('hard-rejects impossible numeric values', () {
      expect(
        () => validateMeasurementValue(entered: '-0.1', unit: 'kilogram'),
        throwsA(isA<MeasurementValueException>()),
      );
      expect(
        () => validateMeasurementValue(entered: 'NaN', unit: 'kilogram'),
        throwsA(isA<MeasurementValueException>()),
      );
      expect(
        () => validateMeasurementValue(entered: '1.123456', unit: 'kilogram'),
        throwsA(isA<MeasurementValueException>()),
      );
    });

    test('soft-warns suspicious values from unit thresholds', () {
      final result = validateMeasurementValue(
        entered: '5000',
        unit: 'kilogram',
      );

      expect(result.value, 5000);
      expect(result.valueEntered, '5000');
      expect(result.warnings, hasLength(1));
      expect(
        result.warnings.single.code,
        MeasurementValidationWarningCode.suspiciouslyHigh,
      );
      expect(result.warnings.single.threshold, 500);
    });

    test('allows zero and boundary values without warnings', () {
      expect(
        validateMeasurementValue(entered: '0', unit: 'kilogram').warnings,
        isEmpty,
      );
      expect(
        validateMeasurementValue(entered: '500', unit: 'kilogram').warnings,
        isEmpty,
      );
      expect(
        validateMeasurementValue(entered: '100', unit: 'percent').warnings,
        isEmpty,
      );
    });

    test('hard-rejects invalid target-goal targets', () {
      expect(
        () => validateMeasurementTargetValue(
          goalType: 'target',
          targetValue: null,
        ),
        throwsA(isA<MeasurementValueException>()),
      );
      expect(
        () => validateMeasurementTargetValue(
          goalType: 'target',
          targetValue: -1,
        ),
        throwsA(isA<MeasurementValueException>()),
      );
      expect(
        () => validateMeasurementTargetValue(
          goalType: 'target',
          targetValue: double.nan,
        ),
        throwsA(isA<MeasurementValueException>()),
      );
    });

    test('accepts valid target-goal targets', () {
      expect(
        validateMeasurementTargetValue(
          goalType: 'target',
          targetValue: 80,
        ),
        80,
      );
      expect(
        validateMeasurementTargetValue(
          goalType: 'decrease',
          targetValue: 80,
        ),
        isNull,
      );
    });

    test('matches the shared golden vectors', () async {
      final vector = jsonDecode(
        await _vectorFile(
          'm9-measurement-validation.json',
        ).readAsString(),
      ) as Map<String, Object?>;
      final cases = vector['cases']! as List<Object?>;

      for (final caseObject in cases) {
        final caseData = caseObject! as Map<String, Object?>;
        final input = caseData['input']! as Map<String, Object?>;
        final expected = caseData['expected']! as Map<String, Object?>;
        final reason = caseData['name']! as String;

        final expectedError = expected['error'];
        if (input.containsKey('goalType')) {
          double? targetValue;
          final inputTargetValue = input['targetValue'];
          if (inputTargetValue is num) {
            targetValue = inputTargetValue.toDouble();
          }

          if (expectedError != null) {
            expect(
              () => validateMeasurementTargetValue(
                goalType: input['goalType']! as String,
                targetValue: targetValue,
              ),
              throwsA(isA<MeasurementValueException>()),
              reason: reason,
            );
            continue;
          }

          final result = validateMeasurementTargetValue(
            goalType: input['goalType']! as String,
            targetValue: targetValue,
          );
          expect(result, expected['targetValue'], reason: reason);
          continue;
        }

        if (expectedError != null) {
          expect(
            () => validateMeasurementValue(
              entered: input['entered']! as String,
              unit: input['unit']! as String,
            ),
            throwsA(isA<MeasurementValueException>()),
            reason: reason,
          );
          continue;
        }

        final result = validateMeasurementValue(
          entered: input['entered']! as String,
          unit: input['unit']! as String,
        );
        expect(result.value, expected['value'], reason: reason);
        expect(result.valueEntered, expected['valueEntered'], reason: reason);

        final expectedWarnings = expected['warnings']! as List<Object?>;
        expect(result.warnings, hasLength(expectedWarnings.length));
        for (var index = 0; index < expectedWarnings.length; index += 1) {
          final expectedWarning =
              expectedWarnings[index]! as Map<String, Object?>;
          final actualWarning = result.warnings[index];
          expect(
            actualWarning.code.name,
            expectedWarning['code'],
            reason: reason,
          );
          expect(actualWarning.unit, expectedWarning['unit'], reason: reason);
          expect(
            actualWarning.threshold,
            expectedWarning['threshold'],
            reason: reason,
          );
        }
      }
    });
  });
}

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
