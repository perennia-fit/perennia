/// The one shared two-tier validator (AGENTS.md invariant) for account-level
/// Settings values, golden-vectored against the TypeScript
/// `validateAgentSettings` (`packages/golden-vectors/vectors/`
/// `m35-settings-validation.json`). Account-level Settings become a synced
/// singleton the agent can write, so both the UI write path and the
/// agent batch-write must reject the same impossible values here — an unknown
/// enum member or an out-of-range default weight increment — with no
/// agent-only parallel check.
///
/// Settings have no soft-warn tier: a preference is either a known enum member
/// / an in-range number, or it is a hard reject; there is no "improbable but
/// allowed" middle for a theme name or a plate increment.
library;

/// Bounds and closed enum registries for account-level Settings. Mirrors the
/// TypeScript `SETTINGS_VALIDATION_LIMITS` exactly; the golden vector's
/// `limits` block must agree with both.
class SettingsValidationLimits {
  const SettingsValidationLimits._();

  static const weightIncrementMinKilograms = 0.0;
  static const weightIncrementMaxKilograms = 100.0;

  static const themePreferences = <String>['system', 'light', 'dark'];
  static const unitSystems = <String>['metric', 'imperial'];
  static const weekStartDays = <String>['monday', 'sunday'];
  static const homeScreenDisplays = <String>['comfortable', 'compact'];
}

class SettingsValidationIssue {
  const SettingsValidationIssue({
    required this.field,
    required this.rule,
    required this.message,
    this.limit,
  });

  final String field;
  final String rule;
  final String message;
  final Object? limit;
}

class SettingsValidationResult {
  SettingsValidationResult({
    required Iterable<SettingsValidationIssue> errors,
    required Iterable<SettingsValidationIssue> warnings,
  })  : errors = List<SettingsValidationIssue>.unmodifiable(errors),
        warnings = List<SettingsValidationIssue>.unmodifiable(warnings);

  final List<SettingsValidationIssue> errors;
  final List<SettingsValidationIssue> warnings;

  bool get accepted => errors.isEmpty;

  void throwIfRejected() {
    if (errors.isEmpty) {
      return;
    }
    throw SettingsValidationException(errors: errors, warnings: warnings);
  }
}

class SettingsValidationException implements Exception {
  SettingsValidationException({
    required Iterable<SettingsValidationIssue> errors,
    Iterable<SettingsValidationIssue> warnings =
        const <SettingsValidationIssue>[],
  })  : errors = List<SettingsValidationIssue>.unmodifiable(errors),
        warnings = List<SettingsValidationIssue>.unmodifiable(warnings);

  final List<SettingsValidationIssue> errors;
  final List<SettingsValidationIssue> warnings;

  String get message => 'Account Settings failed hard validation.';

  @override
  String toString() {
    final rules = errors.map((error) => error.rule).join(', ');
    return 'SettingsValidationException: $message ($rules)';
  }
}

/// A single account-level Settings field to validate. Only the fields present
/// in a write are checked; a partial write validates only the keys it carries.
class SettingsFieldValue {
  SettingsFieldValue.enumMember({
    required this.field,
    required Iterable<String> allowed,
    required String? value,
  })  : allowed = List<String>.unmodifiable(allowed),
        stringValue = value,
        numberValue = null;

  const SettingsFieldValue.number({
    required this.field,
    required double? value,
  })  : allowed = const <String>[],
        stringValue = null,
        numberValue = value;

  final String field;
  final List<String> allowed;
  final String? stringValue;
  final double? numberValue;
}

/// Validates a bag of account-level Settings values. Iterates the supplied
/// fields in the caller-provided order (callers pass them in the canonical
/// field order so the golden vectors are deterministic across both languages).
SettingsValidationResult validateSettingsFields(
  Iterable<SettingsFieldValue> fields,
) {
  final errors = <SettingsValidationIssue>[];

  for (final field in fields) {
    if (field.field == 'defaultWeightIncrement') {
      _validateWeightIncrement(field.numberValue, errors);
      continue;
    }
    _validateEnumMembership(field, errors);
  }

  return SettingsValidationResult(
    errors: List<SettingsValidationIssue>.unmodifiable(errors),
    warnings: const <SettingsValidationIssue>[],
  );
}

void _validateEnumMembership(
  SettingsFieldValue field,
  List<SettingsValidationIssue> errors,
) {
  final value = field.stringValue;
  if (value == null || field.allowed.contains(value)) {
    return;
  }
  errors.add(
    SettingsValidationIssue(
      field: field.field,
      rule: 'setting_enum_membership',
      message: '${field.field} must be one of: ${field.allowed.join(', ')}.',
      limit: field.allowed,
    ),
  );
}

void _validateWeightIncrement(
  double? value,
  List<SettingsValidationIssue> errors,
) {
  if (value == null) {
    return;
  }
  if (!value.isFinite ||
      value <= SettingsValidationLimits.weightIncrementMinKilograms) {
    errors.add(
      const SettingsValidationIssue(
        field: 'defaultWeightIncrement',
        rule: 'setting_weight_increment_positive',
        message: 'Default weight increment must be greater than 0.',
        limit: SettingsValidationLimits.weightIncrementMinKilograms,
      ),
    );
    return;
  }
  if (value > SettingsValidationLimits.weightIncrementMaxKilograms) {
    errors.add(
      const SettingsValidationIssue(
        field: 'defaultWeightIncrement',
        rule: 'setting_weight_increment_max',
        message: 'Default weight increment must be no more than 100.',
        limit: SettingsValidationLimits.weightIncrementMaxKilograms,
      ),
    );
  }
}
