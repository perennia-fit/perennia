import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/settings/settings_validation.dart';

void main() {
  group('validateSettingsFields', () {
    test('accepts a fully valid account-settings write', () {
      final result = validateSettingsFields(<SettingsFieldValue>[
        SettingsFieldValue.enumMember(
          field: 'themePreference',
          allowed: SettingsValidationLimits.themePreferences,
          value: 'dark',
        ),
        const SettingsFieldValue.number(
          field: 'defaultWeightIncrement',
          value: 2.5,
        ),
      ]);
      expect(result.accepted, isTrue);
      expect(result.errors, isEmpty);
    });

    test('hard-rejects an unknown enum member', () {
      final result = validateSettingsFields(<SettingsFieldValue>[
        SettingsFieldValue.enumMember(
          field: 'themePreference',
          allowed: SettingsValidationLimits.themePreferences,
          value: 'midnight',
        ),
      ]);
      expect(result.accepted, isFalse);
      expect(
        result.errors.map((error) => error.rule),
        <String>['setting_enum_membership'],
      );
    });

    test('throwIfRejected raises for an out-of-range increment', () {
      expect(
        () => validateSettingsFields(<SettingsFieldValue>[
          const SettingsFieldValue.number(
            field: 'defaultWeightIncrement',
            value: 0,
          ),
        ]).throwIfRejected(),
        throwsA(isA<SettingsValidationException>()),
      );
    });

    test('enum fields expose immutable allowed-value snapshots', () {
      final allowed = <String>['system', 'light'];
      final field = SettingsFieldValue.enumMember(
        field: 'themePreference',
        allowed: allowed,
        value: 'dark',
      );

      allowed.add('dark');

      expect(field.allowed, <String>['system', 'light']);
      expect(() => field.allowed.clear(), throwsUnsupportedError);

      final result = validateSettingsFields(<SettingsFieldValue>[field]);
      expect(result.accepted, isFalse);
      expect(result.errors.single.limit, <String>['system', 'light']);
      expect(() => (result.errors.single.limit! as List<String>).clear(),
          throwsUnsupportedError);
    });

    test('matches the shared golden vectors', () async {
      final vector = jsonDecode(
        await _vectorFile('m35-settings-validation.json').readAsString(),
      ) as Map<String, Object?>;
      final cases = vector['cases']! as List<Object?>;

      for (final caseObject in cases) {
        final caseData = caseObject! as Map<String, Object?>;
        final input = caseData['input']! as Map<String, Object?>;
        final expected = caseData['expected']! as Map<String, Object?>;
        final result = validateSettingsFields(
          _fieldsFromVector(input['fields']! as Map<String, Object?>),
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

/// Converts the golden vector's `fields` map into the canonical-order list the
/// validator iterates, so the error ordering is deterministic across both
/// languages. Only keys present in the vector are emitted.
List<SettingsFieldValue> _fieldsFromVector(Map<String, Object?> fields) {
  final values = <SettingsFieldValue>[];
  if (fields.containsKey('themePreference')) {
    values.add(
      SettingsFieldValue.enumMember(
        field: 'themePreference',
        allowed: SettingsValidationLimits.themePreferences,
        value: fields['themePreference'] as String?,
      ),
    );
  }
  if (fields.containsKey('unitSystem')) {
    values.add(
      SettingsFieldValue.enumMember(
        field: 'unitSystem',
        allowed: SettingsValidationLimits.unitSystems,
        value: fields['unitSystem'] as String?,
      ),
    );
  }
  if (fields.containsKey('weekStartDay')) {
    values.add(
      SettingsFieldValue.enumMember(
        field: 'weekStartDay',
        allowed: SettingsValidationLimits.weekStartDays,
        value: fields['weekStartDay'] as String?,
      ),
    );
  }
  if (fields.containsKey('defaultWeightIncrement')) {
    values.add(
      SettingsFieldValue.number(
        field: 'defaultWeightIncrement',
        value: (fields['defaultWeightIncrement']! as num).toDouble(),
      ),
    );
  }
  if (fields.containsKey('homeScreenDisplay')) {
    values.add(
      SettingsFieldValue.enumMember(
        field: 'homeScreenDisplay',
        allowed: SettingsValidationLimits.homeScreenDisplays,
        value: fields['homeScreenDisplay'] as String?,
      ),
    );
  }
  return values;
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
