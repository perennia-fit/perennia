/// The User Profile tier of the **single shared two-tier validator**
/// (docs/designs/user-profile.md, Validation). Its verdicts, rule ids and
/// messages must agree with the TypeScript twin
/// (`validateUserProfileSection` in apps/server/src/agent-validation.ts) against
/// the shared golden vector
/// (packages/golden-vectors/vectors/m41-user-profile-validation.json). It runs
/// on the merged values of a section, before every device write and in the
/// agent route. The server does not run it at push: a change the server won't
/// accept stays pending and stalls every later Sync Run.
///
/// A hard reject flips [UserProfileValidationResult.accepted] to false, and
/// [UserProfileValidationResult.throwIfRejected] throws so nothing persists. A
/// soft warning leaves the result accepted, for the caller to confirm.
///
/// A field of the wrong JSON type is skipped as unset: the agent route's strict
/// schema refuses one, and the device merges over tolerantly read values.
/// Issues follow the section's field order and, within a field, the order of
/// the Validation table, with each rule at most once per field.
library;

import 'user_profile.dart';

/// Kept in lockstep with the TS `USER_PROFILE_VALIDATION_LIMITS` and the golden
/// vector's `limits` block.
class UserProfileValidationLimits {
  const UserProfileValidationLimits._();

  static const birthYearMaxAgeYears = 130;
  static const birthYearWarnMinAgeYears = 13;
  static const birthYearWarnMaxAgeYears = 100;
  static const heightMaxCentimetres = 300;
  static const heightWarnMinCentimetres = 120;
  static const heightWarnMaxCentimetres = 220;
  static const cmPerInch = centimetresPerInch;
  static const daysPerWeekMin = 1;
  static const daysPerWeekMax = 7;
  static const sessionMinutesMin = 1;
  static const sessionMinutesMax = 600;
  static const sessionMinutesWarnMax = 240;
  static const equipmentIdMaxLength = profileEquipmentIdMaxLength;
  static const healthLimitationsTextMaxLength = 1000;
  static const generalNotesTextMaxLength = 2000;

  static final List<String> heightUnits = _wireNames(
    HeightUnit.values,
    (unit) => unit.wireName,
  );
  static final List<String> trainingGoalIds = _wireNames(
    TrainingGoalId.values,
    (goal) => goal.wireName,
  );
  static final List<String> sexes = _wireNames(
    ProfileSex.values,
    (sex) => sex.wireName,
  );
  static final List<String> experienceLevels = _wireNames(
    ExperienceLevel.values,
    (level) => level.wireName,
  );

  static List<String> _wireNames<T>(
    List<T> values,
    String Function(T value) wireNameOf,
  ) {
    return List<String>.unmodifiable(values.map(wireNameOf));
  }
}

class UserProfileValidationIssue {
  const UserProfileValidationIssue({
    required this.field,
    required this.rule,
    required this.message,
    this.limit,
    this.placeholder,
  });

  /// The field's sync-payload name, for example `birth_year`.
  final String field;
  final String rule;
  final String message;
  final Object? limit;

  /// The value the rule's message names, for translated copy: the age (an int)
  /// for `birth_year.improbable_age`, the formatted `<value> <unit>` string for
  /// `height.improbable`. Dart only: the TypeScript twin and the golden vector
  /// have no such field.
  final Object? placeholder;
}

class UserProfileValidationResult {
  UserProfileValidationResult({
    required Iterable<UserProfileValidationIssue> errors,
    required Iterable<UserProfileValidationIssue> warnings,
  })  : errors = List<UserProfileValidationIssue>.unmodifiable(errors),
        warnings = List<UserProfileValidationIssue>.unmodifiable(warnings);

  final List<UserProfileValidationIssue> errors;
  final List<UserProfileValidationIssue> warnings;

  bool get accepted => errors.isEmpty;

  void throwIfRejected() {
    if (errors.isEmpty) {
      return;
    }
    throw UserProfileValidationException(errors: errors, warnings: warnings);
  }
}

class UserProfileValidationException implements Exception {
  UserProfileValidationException({
    required Iterable<UserProfileValidationIssue> errors,
    Iterable<UserProfileValidationIssue> warnings =
        const <UserProfileValidationIssue>[],
  })  : errors = List<UserProfileValidationIssue>.unmodifiable(errors),
        warnings = List<UserProfileValidationIssue>.unmodifiable(warnings);

  final List<UserProfileValidationIssue> errors;
  final List<UserProfileValidationIssue> warnings;

  String get message => 'User Profile section failed hard validation.';

  @override
  String toString() {
    final rules = errors.map((error) => error.rule).join(', ');
    return 'UserProfileValidationException: $message ($rules)';
  }
}

/// Validates one section's values, in the snake_case wire shape. [referenceYear]
/// is an input so a result never depends on the clock: the device passes its
/// local calendar year, the agent route the server's UTC year.
UserProfileValidationResult validateUserProfileSection(
  UserProfileSection section,
  Map<String, Object?> values, {
  required int referenceYear,
}) {
  final errors = <UserProfileValidationIssue>[];
  final warnings = <UserProfileValidationIssue>[];

  switch (section) {
    case UserProfileSection.aboutYou:
      _validateSex(values['sex'], errors);
      _validateBirthYear(values['birth_year'], referenceYear, errors, warnings);
      _validateHeight(values['height'], errors, warnings);
    case UserProfileSection.trainingGoals:
      _validateGoals(values['goals'], errors);
    case UserProfileSection.experience:
      _validateLevels(values['levels'], errors);
    case UserProfileSection.trainingSetup:
      _validateEquipment(values['equipment'], errors);
      _validateDaysPerWeek(values['days_per_week'], errors);
      _validateSessionMinutes(values['session_minutes'], errors, warnings);
    case UserProfileSection.healthLimitations:
      _validateText(
        values['text'],
        UserProfileValidationLimits.healthLimitationsTextMaxLength,
        errors,
      );
    case UserProfileSection.generalNotes:
      _validateText(
        values['text'],
        UserProfileValidationLimits.generalNotesTextMaxLength,
        errors,
      );
  }

  return UserProfileValidationResult(errors: errors, warnings: warnings);
}

void _validateSex(Object? value, List<UserProfileValidationIssue> errors) {
  if (value is! String || UserProfileValidationLimits.sexes.contains(value)) {
    return;
  }
  errors.add(
    const UserProfileValidationIssue(
      field: 'sex',
      rule: 'sex.unknown',
      message: 'Sex must be Female, Male or Not set.',
    ),
  );
}

void _validateBirthYear(
  Object? value,
  int referenceYear,
  List<UserProfileValidationIssue> errors,
  List<UserProfileValidationIssue> warnings,
) {
  final birthYear = _finiteNumber(value);
  if (birthYear == null) {
    return;
  }
  if (birthYear > referenceYear) {
    errors.add(
      UserProfileValidationIssue(
        field: 'birth_year',
        rule: 'birth_year.future',
        message: "Birth year can't be in the future.",
        limit: referenceYear,
      ),
    );
    return;
  }
  final oldest =
      referenceYear - UserProfileValidationLimits.birthYearMaxAgeYears;
  if (birthYear < oldest) {
    errors.add(
      UserProfileValidationIssue(
        field: 'birth_year',
        rule: 'birth_year.too_old',
        message: "Birth year can't be more than 130 years ago.",
        limit: oldest,
      ),
    );
    return;
  }
  final age = referenceYear - birthYear;
  if (age < UserProfileValidationLimits.birthYearWarnMinAgeYears ||
      age > UserProfileValidationLimits.birthYearWarnMaxAgeYears) {
    warnings.add(
      UserProfileValidationIssue(
        field: 'birth_year',
        rule: 'birth_year.improbable_age',
        message: 'That makes you ${_formatNumber(age)}. Check the birth year.',
        placeholder: referenceYear - birthYear.toInt(),
      ),
    );
  }
}

void _validateHeight(
  Object? value,
  List<UserProfileValidationIssue> errors,
  List<UserProfileValidationIssue> warnings,
) {
  if (value is! Map) {
    return;
  }
  final unit = value['unit'];
  if (!UserProfileValidationLimits.heightUnits.contains(unit)) {
    errors.add(
      const UserProfileValidationIssue(
        field: 'height',
        rule: 'height.unit',
        message: 'Height must be in cm or in.',
      ),
    );
    return;
  }
  final height = _finiteNumber(value['value']);
  if (height == null || height <= 0) {
    errors.add(
      const UserProfileValidationIssue(
        field: 'height',
        rule: 'height.non_positive',
        message: 'Height must be more than zero.',
      ),
    );
    return;
  }
  final centimetres = unit == HeightUnit.cm.wireName
      ? height
      : height * UserProfileValidationLimits.cmPerInch;
  if (centimetres > UserProfileValidationLimits.heightMaxCentimetres) {
    errors.add(
      const UserProfileValidationIssue(
        field: 'height',
        rule: 'height.too_tall',
        message: 'Height must be 300 cm (118.1 in) or less.',
        limit: UserProfileValidationLimits.heightMaxCentimetres,
      ),
    );
    return;
  }
  if (centimetres < UserProfileValidationLimits.heightWarnMinCentimetres ||
      centimetres > UserProfileValidationLimits.heightWarnMaxCentimetres) {
    final formatted = '${_formatNumber(height)} $unit';
    warnings.add(
      UserProfileValidationIssue(
        field: 'height',
        rule: 'height.improbable',
        message: 'A height of $formatted is unusual. Check it.',
        placeholder: formatted,
      ),
    );
  }
}

void _validateGoals(Object? value, List<UserProfileValidationIssue> errors) {
  if (value is! List) {
    return;
  }
  if (value.any(
    (goal) => !UserProfileValidationLimits.trainingGoalIds.contains(goal),
  )) {
    errors.add(
      const UserProfileValidationIssue(
        field: 'goals',
        rule: 'goals.unknown',
        message: 'Unknown Training Goal.',
      ),
    );
  }
  if (_hasDuplicate(value.whereType<String>())) {
    errors.add(
      const UserProfileValidationIssue(
        field: 'goals',
        rule: 'goals.duplicate',
        message: 'Each item can appear once.',
      ),
    );
  }
}

void _validateEquipment(
  Object? value,
  List<UserProfileValidationIssue> errors,
) {
  if (value is! List) {
    return;
  }
  if (value.any(
    (id) =>
        id is! String ||
        id.isEmpty ||
        id.length > UserProfileValidationLimits.equipmentIdMaxLength,
  )) {
    errors.add(
      const UserProfileValidationIssue(
        field: 'equipment',
        rule: 'equipment.invalid',
        message: 'Equipment ids must be 1 to 64 characters.',
        limit: UserProfileValidationLimits.equipmentIdMaxLength,
      ),
    );
  }
  if (_hasDuplicate(value.whereType<String>().where((id) => id.isNotEmpty))) {
    errors.add(
      const UserProfileValidationIssue(
        field: 'equipment',
        rule: 'equipment.duplicate',
        message: 'Each item can appear once.',
      ),
    );
  }
}

void _validateLevels(Object? value, List<UserProfileValidationIssue> errors) {
  if (value is! List) {
    return;
  }
  final entries = value.map(
    (entry) => entry is Map ? entry : const <String, Object?>{},
  );
  if (entries.any(
    (entry) =>
        !UserProfileValidationLimits.experienceLevels.contains(entry['level']),
  )) {
    errors.add(
      const UserProfileValidationIssue(
        field: 'levels',
        rule: 'levels.unknown_level',
        message: 'Level must be Beginner, Intermediate or Advanced.',
      ),
    );
  }
  final focusIds = entries.map((entry) => entry['focus_id']);
  if (focusIds.any((id) => id is! String || id.isEmpty)) {
    errors.add(
      const UserProfileValidationIssue(
        field: 'levels',
        rule: 'levels.invalid_focus',
        message: 'Each level needs a Focus.',
      ),
    );
  }
  if (_hasDuplicate(
      focusIds.whereType<String>().where((id) => id.isNotEmpty))) {
    errors.add(
      const UserProfileValidationIssue(
        field: 'levels',
        rule: 'levels.duplicate_focus',
        message: 'Each Focus can have one level.',
      ),
    );
  }
}

void _validateDaysPerWeek(
  Object? value,
  List<UserProfileValidationIssue> errors,
) {
  final days = _finiteNumber(value);
  if (days == null) {
    return;
  }
  if (days < UserProfileValidationLimits.daysPerWeekMin ||
      days > UserProfileValidationLimits.daysPerWeekMax) {
    errors.add(
      const UserProfileValidationIssue(
        field: 'days_per_week',
        rule: 'days_per_week.range',
        message: 'Days per week must be 1 to 7.',
      ),
    );
  }
}

void _validateSessionMinutes(
  Object? value,
  List<UserProfileValidationIssue> errors,
  List<UserProfileValidationIssue> warnings,
) {
  final minutes = _finiteNumber(value);
  if (minutes == null) {
    return;
  }
  if (minutes < UserProfileValidationLimits.sessionMinutesMin ||
      minutes > UserProfileValidationLimits.sessionMinutesMax) {
    errors.add(
      const UserProfileValidationIssue(
        field: 'session_minutes',
        rule: 'session_minutes.range',
        message: 'Session length must be 1 to 600 minutes.',
      ),
    );
    return;
  }
  if (minutes > UserProfileValidationLimits.sessionMinutesWarnMax) {
    warnings.add(
      const UserProfileValidationIssue(
        field: 'session_minutes',
        rule: 'session_minutes.improbable',
        message: 'Sessions over 4 hours are unusual. Check the length.',
      ),
    );
  }
}

/// [limit] counts UTF-16 code units, which is what String `.length` gives in
/// both languages, so an astral-plane character counts as 2 in each.
void _validateText(
  Object? value,
  int limit,
  List<UserProfileValidationIssue> errors,
) {
  if (value is! String || value.length <= limit) {
    return;
  }
  errors.add(
    UserProfileValidationIssue(
      field: 'text',
      rule: 'text.too_long',
      message: 'Keep this under $limit characters.',
      limit: limit,
    ),
  );
}

num? _finiteNumber(Object? value) =>
    value is num && value.isFinite ? value : null;

bool _hasDuplicate(Iterable<String> values) {
  final seen = <String>{};
  return values.any((value) => !seen.add(value));
}

/// As JavaScript formats a number: a whole number has no trailing `.0`, so a
/// message reads the same from the app and from the agent route.
String _formatNumber(num value) {
  return value == value.truncateToDouble()
      ? value.toInt().toString()
      : value.toString();
}
