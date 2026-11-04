/// The Meal-time tier of the **single shared two-tier validator**.
///
/// This is NOT a nutrition-specific fork: it mirrors `validateDose`
/// (dose_validation.dart) in shape (a two-tier result with stable,
/// machine-readable `rule` ids) and produces verdicts that must agree with the
/// TypeScript twin (`validateAgentMealTime` in
/// apps/server/src/agent-validation.ts) against the shared golden vector
/// (packages/golden-vectors/vectors/m39-meal-validation.json). It runs against
/// the Meal as it will be stored, on every app and agent Meal write.
///
/// Tiers:
/// - **Hard-reject (impossible):** an end time that is not after the start
///   time (`meal_ended_before_start`), and an empty Meal Type label
///   (`meal_type_required`). These add an error and flip
///   [MealValidationResult.accepted] to false;
///   [MealValidationResult.throwIfRejected] throws so nothing persists.
/// - **Soft-warn (improbable):** a start time more than
///   [MealValidationLimits.futureToleranceMinutes] after `now`
///   (`meal_time_in_future`). A warning is recorded but the result stays
///   accepted and never throws.
///
/// `MealValidationLimits` is kept in lockstep with the TS
/// `MEAL_VALIDATION_LIMITS` and the golden vector's `limits` block.
library;

/// The Meal-time validator's limits. Kept in lockstep with the TS
/// `MEAL_VALIDATION_LIMITS` and the golden vector's `limits` block.
class MealValidationLimits {
  const MealValidationLimits._();

  /// How far after `now` a Meal may start before `meal_time_in_future` warns.
  /// Exclusive: a start exactly this many minutes ahead does not warn.
  static const int futureToleranceMinutes = 5;
}

/// The Meal fields the time rules read, as the Meal will be stored.
class MealTimeInput {
  const MealTimeInput({
    required this.startedAt,
    this.endedAt,
    required this.mealType,
  });

  final DateTime startedAt;
  final DateTime? endedAt;

  /// The Meal Type label (for example `Breakfast`).
  final String mealType;
}

/// A single Meal validation issue with a STABLE machine-readable [rule] id
/// (the shared identifier the Dart and TS validators and the golden vector all
/// agree on). Mirrors `DoseValidationIssue`.
class MealValidationIssue {
  const MealValidationIssue({
    required this.field,
    required this.rule,
    required this.message,
    required this.limit,
  });

  /// The input field that triggered the rule (`startedAt`, `endedAt`,
  /// `mealType`).
  final String field;

  /// The stable machine-readable rule id (identical across Dart, TS, vector).
  final String rule;

  /// The human-readable explanation of the rule.
  final String message;

  /// The rule limit, or null when the rule has none.
  final Object? limit;
}

/// The two-tier result of validating one candidate Meal's time fields.
/// `accepted` is true only when there are no hard errors; soft warnings never
/// flip it. Mirrors `DoseValidationResult`.
class MealValidationResult {
  MealValidationResult({
    required Iterable<MealValidationIssue> errors,
    required Iterable<MealValidationIssue> warnings,
  })  : errors = List<MealValidationIssue>.unmodifiable(errors),
        warnings = List<MealValidationIssue>.unmodifiable(warnings);

  final List<MealValidationIssue> errors;
  final List<MealValidationIssue> warnings;

  /// True when no hard-reject rule fired; soft warnings keep this true.
  bool get accepted => errors.isEmpty;

  /// Throws a [MealValidationException] iff a hard-reject rule fired, so a
  /// write path can guard itself with a single call and never persist an
  /// impossible Meal. A soft-warn-only result returns without throwing.
  void throwIfRejected() {
    if (errors.isEmpty) {
      return;
    }
    throw MealValidationException(errors: errors, warnings: warnings);
  }
}

/// Thrown by [MealValidationResult.throwIfRejected] when a Meal fails one or
/// more hard-reject rules. Mirrors `DoseValidationException`.
class MealValidationException implements Exception {
  MealValidationException({
    required Iterable<MealValidationIssue> errors,
    Iterable<MealValidationIssue> warnings = const <MealValidationIssue>[],
  })  : errors = List<MealValidationIssue>.unmodifiable(errors),
        warnings = List<MealValidationIssue>.unmodifiable(warnings);

  final List<MealValidationIssue> errors;
  final List<MealValidationIssue> warnings;

  String get message => 'Meal failed hard validation.';

  @override
  String toString() {
    final rules = errors.map((error) => error.rule).join(', ');
    return 'MealValidationException: $message ($rules)';
  }
}

/// Validates one candidate Meal's time fields through the shared two-tier
/// validator, against [now].
///
/// Rules, in this order (the order the golden vector pins):
/// - `meal_ended_before_start` (hard, `endedAt`): [MealTimeInput.endedAt] is
///   set and not after [MealTimeInput.startedAt]. An end equal to the start is
///   rejected.
/// - `meal_type_required` (hard, `mealType`): the Meal Type label is empty or
///   whitespace.
/// - `meal_time_in_future` (soft, `startedAt`): the start is more than
///   [MealValidationLimits.futureToleranceMinutes] after [now].
MealValidationResult validateMealTime(
  MealTimeInput input, {
  required DateTime now,
}) {
  final errors = <MealValidationIssue>[];
  final warnings = <MealValidationIssue>[];

  final endedAt = input.endedAt;
  if (endedAt != null && !endedAt.isAfter(input.startedAt)) {
    errors.add(
      const MealValidationIssue(
        field: 'endedAt',
        rule: 'meal_ended_before_start',
        message: 'Meal end time must be after its start time.',
        limit: null,
      ),
    );
  }

  if (input.mealType.trim().isEmpty) {
    errors.add(
      const MealValidationIssue(
        field: 'mealType',
        rule: 'meal_type_required',
        message: 'Meal Type is required.',
        limit: null,
      ),
    );
  }

  const tolerance =
      Duration(minutes: MealValidationLimits.futureToleranceMinutes);
  if (input.startedAt.difference(now) > tolerance) {
    warnings.add(
      const MealValidationIssue(
        field: 'startedAt',
        rule: 'meal_time_in_future',
        message: 'Meal start time is in the future.',
        limit: MealValidationLimits.futureToleranceMinutes,
      ),
    );
  }

  return MealValidationResult(errors: errors, warnings: warnings);
}
