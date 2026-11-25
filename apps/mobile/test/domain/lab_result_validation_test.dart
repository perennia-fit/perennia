import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/labs/lab_result_validation.dart';

/// Moves with `schemaVersion` in m42-lab-result-validation.json, its schema's
/// constant and the server runner's
/// (apps/server/test/agent-validation.golden.test.mjs): an incompatible
/// case-shape change bumps all of them together.
const int labResultValidationGoldenSchemaVersion = 1;

void main() {
  group('Lab Result validation', () {
    test('matches the shared M42 golden vectors', () async {
      final vector = jsonDecode(
        await _vectorFile('m42-lab-result-validation.json').readAsString(),
      ) as Map<String, Object?>;

      expect(vector['name'], 'm42-lab-result-validation');
      expect(vector['domain'], 'lab-result-validation');
      expect(vector['schemaVersion'], labResultValidationGoldenSchemaVersion);
      expect(vector['schemaVersion'], labResultValidationSchemaVersion);
      expect(vector['schema'], 'm42-lab-result-validation.schema.json');
      final cases = vector['cases']! as List<Object?>;
      expect(cases, isNotEmpty);

      for (final caseObject in cases) {
        final caseData = caseObject! as Map<String, Object?>;
        final name = caseData['name']! as String;
        final input = caseData['input']! as Map<String, Object?>;
        final expected = caseData['expected']! as Map<String, Object?>;

        final result = validateLabResult(
          _input(input),
          today: DateTime.parse(caseData['today']! as String),
        );

        expect(result.accepted, expected['accepted'], reason: name);
        expect(
          result.errors.map((issue) => issue.rule).toList(),
          expected['errorRules'],
          reason: name,
        );
        expect(
          result.warnings.map((issue) => issue.rule).toList(),
          expected['warningRules'],
          reason: name,
        );
      }
    });

    test('messages carry the same text as the TypeScript module', () {
      final today = DateTime(2026, 3, 5);

      final outOfBounds = validateLabResult(
        _sodium(entered: '1000.1'),
        today: today,
      ).errors.single;
      expect(outOfBounds.rule, 'lab_value_out_of_bounds');
      expect(outOfBounds.field, 'entered');
      expect(outOfBounds.message, 'Value must be between 0 and 1000 mmol/L.');

      expect(
        validateLabResult(
          const LabResultInput(
            labTestKey: 'haematocrit',
            entered: '1.5',
            enteredUnit: 'L/L',
            lab: <String, Object?>{'collected': '2026-03-04T08:15'},
            timeAnchor: _anchor,
          ),
          today: today,
        ).errors.single.message,
        'Value must be between 0 and 1 L/L.',
      );

      final unit = validateLabResult(
        _sodium(enteredUnit: 'mg/dL'),
        today: today,
      ).errors.single;
      expect(unit.rule, 'lab_unit_not_accepted');
      expect(unit.field, 'enteredUnit');
      expect(unit.message, 'Unit not accepted. Use mmol/L, mmol/l.');

      expect(
        validateLabResult(
          const LabResultInput(
            labTestKey: 'wcc',
            entered: '6.2',
            enteredUnit: 'cells',
            lab: <String, Object?>{'collected': '2026-03-04T08:15'},
            timeAnchor: _anchor,
          ),
          today: today,
        ).errors.single.message,
        'Unit not accepted. Use x10^9/L, x10^9/l, 10^9/L, 10^9/l.',
      );

      expect(
        validateLabResult(
          LabResultInput(
            labTestKey: 'sodium',
            entered: '140',
            enteredUnit: 'mmol/L',
            lab: <String, Object?>{
              'collected': '2026-03-04T08:15',
              'labName': 'n' * 81,
            },
            timeAnchor: _anchor,
          ),
          today: today,
        ).errors.single.message,
        'lab.labName is too long.',
      );
    });

    test('an unknown Lab Test is a programming error', () {
      expect(
        () => validateLabResult(
          const LabResultInput(
            labTestKey: 'not_a_lab_test',
            entered: '1',
            enteredUnit: 'mmol/L',
            timeAnchor: _anchor,
          ),
          today: DateTime(2026, 3, 5),
        ),
        throwsArgumentError,
      );
    });
  });
}

const Map<String, Object?> _anchor = <String, Object?>{
  'localDateTime': '2026-03-04T08:15:00',
  'timezoneOffsetMinutes': 600,
};

LabResultInput _sodium(
        {String entered = '140', String enteredUnit = 'mmol/L'}) =>
    LabResultInput(
      labTestKey: 'sodium',
      entered: entered,
      enteredUnit: enteredUnit,
      lab: const <String, Object?>{'collected': '2026-03-04T08:15'},
      timeAnchor: _anchor,
    );

LabResultInput _input(Map<String, Object?> input) => LabResultInput(
      labTestKey: input['labTestKey']! as String,
      entered: input['entered']! as String,
      enteredUnit: input['enteredUnit']! as String,
      lab: input['lab'] as Map<String, Object?>?,
      timeAnchor: input['timeAnchor']! as Map<String, Object?>,
    );

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
