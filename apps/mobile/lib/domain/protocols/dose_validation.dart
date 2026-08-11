/// The dose tier of the **single shared two-tier validator** (PROTOCOLS.md §6).
///
/// This is NOT a Protocols-specific fork: it mirrors `validateFoodEntryNutrition`
/// / `NutrientValidation*` (set_validation.dart) exactly in shape — a two-tier
/// result with stable, machine-readable `rule` ids — and produces verdicts that
/// must agree byte-for-byte with the TypeScript twin (`validateAgentDose` in
/// apps/server/src/agent-validation.ts) against the shared golden vector
/// (packages/golden-vectors/vectors/m26-dose-validation.json). The repository
/// logging path consumes THIS module; there is no parallel dose validation.
///
/// Tiers (PROTOCOLS.md §6):
/// - **Hard-reject (impossible):** negative amount, a non-finite amount, an
/// absurd per-dose cap, and a malformed unit/route (outside's curated
///   registries). These add an error and flip [DoseValidationResult.accepted] to
///   false; [DoseValidationResult.throwIfRejected] throws so nothing persists.
/// - **Soft-warn (improbable):** an amount out of range for the entered unit. A
///   warning is recorded but the result stays accepted and never throws — the UI
///   (and the future agent API) confirm rather than block.
///
/// `DoseValidationLimits` is kept in lockstep with the TS `DOSE_VALIDATION_LIMITS`
/// and the golden vector's `limits` block.
library;

import 'protocols.dart';

/// The per-dose numeric thresholds, keyed by curated [DoseUnit]. `warnAbove` is
/// the improbable (soft-warn) boundary; `maxPerDose` is the absurd (hard-reject)
/// cap. Both are exclusive-greater. Identical to the TS `DOSE_VALIDATION_LIMITS`
/// and the golden vector's `limits`.
class DoseUnitLimit {
  const DoseUnitLimit({
    required this.warnAbove,
    required this.maxPerDose,
  });

  final double warnAbove;
  final double maxPerDose;
}

/// The dose validator's limits. Kept in lockstep with the TS
/// `DOSE_VALIDATION_LIMITS` and the golden vector's `limits` block.
class DoseValidationLimits {
  const DoseValidationLimits._();

  /// The minimum acceptable amount: an amount below this is hard-rejected.
  static const double amountMin = 0.0;

  /// The per-unit thresholds. Every curated [DoseUnit] member has an entry, so
  /// a unit inside the registry always resolves a limit.
  static const Map<DoseUnit, DoseUnitLimit> units = <DoseUnit, DoseUnitLimit>{
    DoseUnit.milligram:
        DoseUnitLimit(warnAbove: 5000, maxPerDose: 100000),
    DoseUnit.microgram:
        DoseUnitLimit(warnAbove: 5000000, maxPerDose: 100000000),
    DoseUnit.gram: DoseUnitLimit(warnAbove: 100, maxPerDose: 1000),
    DoseUnit.internationalUnit:
        DoseUnitLimit(warnAbove: 100000, maxPerDose: 10000000),
    DoseUnit.milliliter: DoseUnitLimit(warnAbove: 100, maxPerDose: 1000),
    DoseUnit.tablet: DoseUnitLimit(warnAbove: 20, maxPerDose: 100),
    DoseUnit.capsule: DoseUnitLimit(warnAbove: 20, maxPerDose: 100),
    DoseUnit.drop: DoseUnitLimit(warnAbove: 100, maxPerDose: 1000),
    DoseUnit.spray: DoseUnitLimit(warnAbove: 20, maxPerDose: 100),
    DoseUnit.puff: DoseUnitLimit(warnAbove: 20, maxPerDose: 100),
    DoseUnit.patch: DoseUnitLimit(warnAbove: 10, maxPerDose: 100),
    DoseUnit.unit: DoseUnitLimit(warnAbove: 1000, maxPerDose: 100000),
  };
}

/// A single dose validation issue with a STABLE machine-readable [rule] id (the
/// shared identifier the Dart and TS validators and the golden vector all agree
/// on). Mirrors `NutrientValidationIssue` / `SetValidationIssue`.
class DoseValidationIssue {
  const DoseValidationIssue({
    required this.field,
    required this.rule,
    required this.message,
    required this.limit,
  });

  /// The input field path that triggered the rule (`amount`, `unit`, `route`).
  final String field;

  /// The stable machine-readable rule id (identical across Dart, TS, vector).
  final String rule;

  /// The human-readable explanation of the rule.
  final String message;

  /// The rule limit or allowed-value summary.
  final Object? limit;
}

/// The two-tier result of validating one candidate `Dose`. `accepted` is true
/// only when there are no hard errors; soft warnings never flip it. Mirrors
/// `NutrientValidationResult`.
class DoseValidationResult {
  DoseValidationResult({
    required Iterable<DoseValidationIssue> errors,
    required Iterable<DoseValidationIssue> warnings,
  })  : errors = List<DoseValidationIssue>.unmodifiable(errors),
        warnings = List<DoseValidationIssue>.unmodifiable(warnings);

  final List<DoseValidationIssue> errors;
  final List<DoseValidationIssue> warnings;

  /// True when no hard-reject rule fired — soft warnings keep this true.
  bool get accepted => errors.isEmpty;

  /// Throws a [DoseValidationException] iff a hard-reject rule fired, so the
  /// logging path can guard a write with a single call and never persist an
  /// impossible Dose. A soft-warn-only result returns without throwing.
  void throwIfRejected() {
    if (errors.isEmpty) {
      return;
    }
    throw DoseValidationException(errors: errors, warnings: warnings);
  }
}

/// Thrown by [DoseValidationResult.throwIfRejected] when a `Dose` fails one or
/// more hard-reject rules. Mirrors `NutrientValidationException`.
class DoseValidationException implements Exception {
  DoseValidationException({
    required Iterable<DoseValidationIssue> errors,
    Iterable<DoseValidationIssue> warnings = const <DoseValidationIssue>[],
  })  : errors = List<DoseValidationIssue>.unmodifiable(errors),
        warnings = List<DoseValidationIssue>.unmodifiable(warnings);

  final List<DoseValidationIssue> errors;
  final List<DoseValidationIssue> warnings;

  String get message => 'Dose failed hard validation.';

  @override
  String toString() {
    final rules = errors.map((error) => error.rule).join(', ');
    return 'DoseValidationException: $message ($rules)';
  }
}

/// Validates one candidate `Dose` through the shared two-tier validator
/// (PROTOCOLS.md §6). [amount] is the as-entered amount (a `num` or numeric
/// `String`); [unit] and [route] are the raw stored/entered registry names — so
/// a value OUTSIDE the curated [DoseUnit]/[DoseRoute] registries is detectable
/// and hard-rejected here rather than silently round-tripping.
///
/// Hard-reject rules (errors): `numeric_finite`, `dose_amount_non_negative`,
/// `dose_amount_max_per_dose`, `dose_unit_allowed`, `dose_route_allowed`.
/// Soft-warn rule (warnings): `dose_amount_out_of_range_for_unit`.
DoseValidationResult validateDose({
  required Object? amount,
  required String unit,
  required String route,
}) {
  final errors = <DoseValidationIssue>[];
  final warnings = <DoseValidationIssue>[];

  final resolvedUnit = _doseUnitOrNull(unit);
  if (resolvedUnit == null) {
    errors.add(
      DoseValidationIssue(
        field: 'unit',
        rule: 'dose_unit_allowed',
        message: 'Unit is not in the curated dose unit registry.',
        limit: DoseUnit.values.map((unit) => unit.name).join('|'),
      ),
    );
  }

  if (_doseRouteOrNull(route) == null) {
    errors.add(
      DoseValidationIssue(
        field: 'route',
        rule: 'dose_route_allowed',
        message: 'Route is not in the curated dose route registry.',
        limit: DoseRoute.values.map((route) => route.name).join('|'),
      ),
    );
  }

  _validateAmount(
    amount: amount,
    unit: resolvedUnit,
    errors: errors,
    warnings: warnings,
  );

  return DoseValidationResult(
    errors: List<DoseValidationIssue>.unmodifiable(errors),
    warnings: List<DoseValidationIssue>.unmodifiable(warnings),
  );
}

void _validateAmount({
  required Object? amount,
  required DoseUnit? unit,
  required List<DoseValidationIssue> errors,
  required List<DoseValidationIssue> warnings,
}) {
  final value = _parseAmount(amount);
  if (value == null || !value.isFinite) {
    errors.add(
      const DoseValidationIssue(
        field: 'amount',
        rule: 'numeric_finite',
        message: 'Dose amount must be a finite number.',
        limit: 'finite',
      ),
    );
    return;
  }
  if (value < DoseValidationLimits.amountMin) {
    errors.add(
      const DoseValidationIssue(
        field: 'amount',
        rule: 'dose_amount_non_negative',
        message: 'Dose amount must be non-negative.',
        limit: DoseValidationLimits.amountMin,
      ),
    );
    return;
  }

  // The per-unit caps only apply when the unit resolved; a malformed unit is
  // already hard-rejected above, and suppresses the unit-relative range checks
  // (we have no scale to judge the amount against).
  final limit = unit == null ? null : DoseValidationLimits.units[unit];
  if (limit == null) {
    return;
  }

  if (value > limit.maxPerDose) {
    errors.add(
      DoseValidationIssue(
        field: 'amount',
        rule: 'dose_amount_max_per_dose',
        message: 'Dose amount is above the maximum for the entered unit.',
        limit: limit.maxPerDose,
      ),
    );
    return;
  }
  if (value > limit.warnAbove) {
    warnings.add(
      DoseValidationIssue(
        field: 'amount',
        rule: 'dose_amount_out_of_range_for_unit',
        message: 'Dose amount is out of the usual range for the entered unit.',
        limit: limit.warnAbove,
      ),
    );
  }
}

double? _parseAmount(Object? rawValue) {
  return switch (rawValue) {
    final num value => value.toDouble(),
    final String value when value.trim().isNotEmpty =>
      double.tryParse(value.trim()),
    _ => null,
  };
}

DoseUnit? _doseUnitOrNull(String name) {
  for (final unit in DoseUnit.values) {
    if (unit.name == name) {
      return unit;
    }
  }
  return null;
}

DoseRoute? _doseRouteOrNull(String name) {
  for (final route in DoseRoute.values) {
    if (route.name == name) {
      return route;
    }
  }
  return null;
}
