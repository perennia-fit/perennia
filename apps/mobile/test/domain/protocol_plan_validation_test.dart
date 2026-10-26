import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/protocols/dose_validation.dart';
import 'package:perennia/domain/protocols/protocol_plan_validation.dart';
import 'package:perennia/domain/protocols/protocols.dart';

/// The schema version this runner reads. It moves together with the vector
/// file's `schemaVersion` and its schema's constant
/// (packages/golden-vectors/vectors/README.md).
const int _schemaVersion = 1;

void main() {
  group('protocol plan validation', () {
    test('a valid timed rule with an improbable amount is still accepted', () {
      // The Dose validator's soft warning is for the Dose logged against the
      // plan; the plan itself only needs an amount the Dose validator accepts.
      final result = validateScheduleRule(
        const <String, Object?>{
          'v': 1,
          'kind': 'timed',
          'days': <String, Object?>{'kind': 'daily'},
          'times': <String>['09:00'],
        },
        amountValue: 6000,
        amountEntered: '6000',
        unit: 'milligram',
        route: 'oral',
      );
      expect(result.accepted, isTrue);
      expect(result.warnings, isEmpty);
    });

    test('an amount the Dose validator rejects fails amount_required', () {
      final result = validateScheduleRule(
        const <String, Object?>{
          'v': 1,
          'kind': 'untimed',
          'days': <String, Object?>{'kind': 'daily'},
          'count': 1,
        },
        amountValue: 20,
        amountEntered: '20',
        unit: 'furlong',
        route: 'oral',
      );
      expect(result.errors.map((issue) => issue.rule), <String>[
        'amount_required',
      ]);
    });

    test('matches the shared protocol-plan-validation golden vectors', () {
      final vector = jsonDecode(
        _vectorFile('m36-protocol-plan-validation.json').readAsStringSync(),
      ) as Map<String, Object?>;
      expect(vector['domain'], 'protocol-plan-validation');
      expect(vector['schemaVersion'], _schemaVersion);
      expect(vector['schema'], 'm36-protocol-plan-validation.schema.json');
      expect(
        vector['limits'],
        <String, Object?>{
          'maxTimesPerDay': ProtocolPlanValidationLimits.maxTimesPerDay,
          'maxUntimedCount': ProtocolPlanValidationLimits.maxUntimedCount,
          'minEveryNDays': ProtocolPlanValidationLimits.minEveryNDays,
          'maxEveryNDays': ProtocolPlanValidationLimits.maxEveryNDays,
          'maxCycleLengthDays': ProtocolPlanValidationLimits.maxCycleLengthDays,
          'warnTimesPerDay': ProtocolPlanValidationLimits.warnTimesPerDay,
        },
      );

      final cases = vector['cases']! as List<Object?>;
      expect(cases, isNotEmpty);
      for (final caseObject in cases) {
        final caseData = caseObject! as Map<String, Object?>;
        final input = caseData['input']! as Map<String, Object?>;
        final expected = caseData['expected']! as Map<String, Object?>;
        final reason = caseData['name']! as String;
        final validator = caseData['validator']! as String;
        final DoseValidationResult result = switch (validator) {
          'schedule_rule' => validateScheduleRule(
              input['rule']! as Map<String, Object?>,
              amountValue: input['amountValue'],
              amountEntered: input['amountEntered'] as String?,
              unit: input['unit'] as String?,
              route: input['route'] as String?,
            ),
          'protocol_period' => validateProtocolPeriod(
              startLocalDate:
                  ProtocolDayDate.parse(input['startLocalDate']! as String),
              endLocalDate: _nullableDate(input['endLocalDate']),
              period: input['period'] as Map<String, Object?>?,
            ),
          _ => throw StateError('Unknown plan validator: $validator.'),
        };

        expect(result.accepted, expected['accepted'], reason: reason);
        expect(
          result.warnings.map((issue) => issue.rule).toList(growable: false),
          expected['warningRules'],
          reason: reason,
        );
        expect(
          result.errors.map((issue) => issue.rule).toList(growable: false),
          expected['errorRules'],
          reason: reason,
        );
      }
    });
  });
}

ProtocolDayDate? _nullableDate(Object? value) =>
    value == null ? null : ProtocolDayDate.parse(value as String);

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
