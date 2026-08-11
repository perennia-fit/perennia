import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/protocols/dose_validation.dart';
import 'package:perennia/domain/protocols/protocols.dart';

void main() {
  group('dose validation', () {
    test('hard-rejects a negative amount', () {
      final result = validateDose(amount: '-1', unit: 'milligram', route: 'oral');

      expect(result.accepted, isFalse);
      expect(
        result.errors.map((error) => error.rule).toList(growable: false),
        <String>['dose_amount_non_negative'],
      );
      expect(result.throwIfRejected, throwsA(isA<DoseValidationException>()));
    });

    test('hard-rejects a non-finite amount', () {
      final result =
          validateDose(amount: 'not-a-number', unit: 'milligram', route: 'oral');

      expect(result.accepted, isFalse);
      expect(
        result.errors.map((error) => error.rule).toList(growable: false),
        <String>['numeric_finite'],
      );
    });

    test('hard-rejects an absurd per-dose amount', () {
      final result = validateDose(amount: '2000', unit: 'gram', route: 'oral');

      expect(result.accepted, isFalse);
      expect(
        result.errors.map((error) => error.rule).toList(growable: false),
        <String>['dose_amount_max_per_dose'],
      );
    });

    test('hard-rejects a malformed unit outside the curated registry', () {
      final result = validateDose(amount: '1', unit: 'scoops', route: 'oral');

      expect(result.accepted, isFalse);
      expect(
        result.errors.map((error) => error.rule).toList(growable: false),
        <String>['dose_unit_allowed'],
      );
    });

    test('hard-rejects a malformed route outside the curated registry', () {
      final result =
          validateDose(amount: '1', unit: 'milligram', route: 'smoked');

      expect(result.accepted, isFalse);
      expect(
        result.errors.map((error) => error.rule).toList(growable: false),
        <String>['dose_route_allowed'],
      );
    });

    test('soft-warns an out-of-range amount while staying accepted', () {
      final result = validateDose(amount: '60', unit: 'tablet', route: 'oral');

      expect(result.accepted, isTrue);
      expect(result.errors, isEmpty);
      expect(
        result.warnings.map((warning) => warning.rule).toList(growable: false),
        <String>['dose_amount_out_of_range_for_unit'],
      );
      // A soft-warn-only result never throws (non-blocking, confirmable).
      expect(result.throwIfRejected, returnsNormally);
    });

    test('accepts an ordinary in-range dose with no issues', () {
      final result = validateDose(amount: '5', unit: 'gram', route: 'oral');

      expect(result.accepted, isTrue);
      expect(result.errors, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('the limits cover every curated dose unit', () {
      // The per-unit table must resolve a limit for every registry member, so a
      // unit inside the registry can always be range-checked.
      for (final unit in DoseUnit.values) {
        expect(
          DoseValidationLimits.units[unit],
          isNotNull,
          reason: 'Missing dose limit for ${unit.name}.',
        );
      }
    });

    test('matches the shared golden vectors', () async {
      final vector = jsonDecode(
        await _vectorFile('m26-dose-validation.json').readAsString(),
      ) as Map<String, Object?>;

      // The Dart limits and the vector's limits block must agree exactly so the
      // two implementations and the spec stay in lockstep.
      final limits = vector['limits']! as Map<String, Object?>;
      expect(
        (limits['amountMin']! as num).toDouble(),
        DoseValidationLimits.amountMin,
      );
      final unitLimits = limits['units']! as Map<String, Object?>;
      for (final unit in DoseUnit.values) {
        final entry = unitLimits[unit.name]! as Map<String, Object?>;
        final dartLimit = DoseValidationLimits.units[unit]!;
        expect(
          (entry['warnAbove']! as num).toDouble(),
          dartLimit.warnAbove,
          reason: '${unit.name} warnAbove drift',
        );
        expect(
          (entry['maxPerDose']! as num).toDouble(),
          dartLimit.maxPerDose,
          reason: '${unit.name} maxPerDose drift',
        );
      }

      final cases = vector['cases']! as List<Object?>;
      for (final caseObject in cases) {
        final caseData = caseObject! as Map<String, Object?>;
        final input = caseData['input']! as Map<String, Object?>;
        final expected = caseData['expected']! as Map<String, Object?>;
        final result = validateDose(
          amount: input['amount'],
          unit: input['unit']! as String,
          route: input['route']! as String,
        );
        final reason = caseData['name']! as String;

        expect(result.accepted, expected['accepted'], reason: reason);
        expect(
          result.warnings
              .map((warning) => warning.rule)
              .toList(growable: false),
          expected['warningRules'],
          reason: reason,
        );
        expect(
          result.errors.map((error) => error.rule).toList(growable: false),
          expected['errorRules'],
          reason: reason,
        );
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
