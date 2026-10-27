/// Validation for the Protocol plan (docs/designs/protocol-schedules-and-reminders.md,
/// D7): a Schedule Version's rule and amount, and a Protocol's bounds and
/// Period, in the shared two-tier module.
///
/// Both validators read the stored rule and period JSON rather than the
/// decoded `protocol_plan.dart` types, because they must judge values a
/// decoded type cannot hold (an anchor of `2026-02-30`, a time of `9:00`).
/// The JSON's `v` and `kind`s are the decoder's to reject; these validators
/// assume a known shape and judge its values. Results reuse the Dose
/// validator's issue type, the Protocols domain's own, so every issue's
/// `rule` is a stable check id below. The TypeScript twin lives in
/// `apps/server/src/agent-validation.ts`; both consume the shared
/// `m36-protocol-plan-validation.json` golden vector.
///
/// Hard-reject checks, in the order they are reported: `times_format`,
/// `times_count`, `times_distinct`, `untimed_count`, `weekdays_valid`,
/// `every_n_range`, `anchor_date`, `amount_required`, `amount_absent`,
/// `cycle_lengths`, `bounds_order`, `pause_count`, `pause_order`,
/// `pause_bounds`, `pause_overlap`. Soft-warn check: `times_many`.
library;

import 'dose_validation.dart';
import 'protocol_plan.dart';
import 'protocols.dart';

// The limits are defined beside the types whose ceilings they also are, and
// exported here, where the validators that judge them live.
export 'protocol_plan.dart' show ProtocolPlanValidationLimits;

/// Validates one Schedule Version: its stored [rule] JSON, and the planned
/// amount, unit and route that a `timed` or `untimed` rule requires and an
/// `as_needed` or `unscheduled` rule must not carry.
/// [amountValue] is the amount's numeric projection (a `num` or numeric
/// `String`); [unit] and [route] are raw registry names.
DoseValidationResult validateScheduleRule(
  Map<String, Object?> rule, {
  required Object? amountValue,
  required String? amountEntered,
  required String? unit,
  required String? route,
}) {
  final errors = <DoseValidationIssue>[];
  final warnings = <DoseValidationIssue>[];
  final kind = rule['kind'];
  if (kind != 'timed' && kind != 'untimed') {
    // `as_needed` and `unscheduled` plan nothing, so the stored shape keeps
    // their amount fields null (`amount_absent`): an amount here is one
    // nothing would ever read.
    if (amountValue != null ||
        amountEntered != null ||
        unit != null ||
        route != null) {
      errors.add(
        const DoseValidationIssue(
          field: 'amount',
          rule: 'amount_absent',
          message: 'An as-needed or unscheduled rule carries no amount, unit '
              'or route.',
          limit: 'absent',
        ),
      );
    }
    return DoseValidationResult(
      errors: List<DoseValidationIssue>.unmodifiable(errors),
      warnings: List<DoseValidationIssue>.unmodifiable(warnings),
    );
  }

  if (kind == 'timed') {
    _validateTimes(rule['times'], errors, warnings);
  } else {
    final count = planWholeNumber(rule['count']);
    if (count == null ||
        count < 1 ||
        count > ProtocolPlanValidationLimits.maxUntimedCount) {
      errors.add(
        const DoseValidationIssue(
          field: 'rule.count',
          rule: 'untimed_count',
          message: 'An untimed rule plans 1 to '
              '${ProtocolPlanValidationLimits.maxUntimedCount} doses a day.',
          limit: ProtocolPlanValidationLimits.maxUntimedCount,
        ),
      );
    }
  }

  _validateDays(rule['days'], errors);

  if (!_amountIsValid(amountValue, amountEntered, unit, route)) {
    errors.add(
      const DoseValidationIssue(
        field: 'amount',
        rule: 'amount_required',
        message: 'A timed or untimed rule needs a valid amount, unit and '
            'route.',
        limit: 'amount|unit|route',
      ),
    );
  }

  return DoseValidationResult(
    errors: List<DoseValidationIssue>.unmodifiable(errors),
    warnings: List<DoseValidationIssue>.unmodifiable(warnings),
  );
}

void _validateTimes(
  Object? rawTimes,
  List<DoseValidationIssue> errors,
  List<DoseValidationIssue> warnings,
) {
  final times = rawTimes is List<Object?> ? rawTimes : const <Object?>[];
  if (times.any((time) => time is! String || !isPlanLocalTime(time))) {
    errors.add(
      const DoseValidationIssue(
        field: 'rule.times',
        rule: 'times_format',
        message: 'Each time must be HH:MM, from 00:00 to 23:59.',
        limit: 'HH:MM',
      ),
    );
  }
  if (times.isEmpty ||
      times.length > ProtocolPlanValidationLimits.maxTimesPerDay) {
    errors.add(
      const DoseValidationIssue(
        field: 'rule.times',
        rule: 'times_count',
        message: 'A timed rule plans 1 to '
            '${ProtocolPlanValidationLimits.maxTimesPerDay} times a day.',
        limit: ProtocolPlanValidationLimits.maxTimesPerDay,
      ),
    );
  }
  if (times.toSet().length != times.length) {
    errors.add(
      const DoseValidationIssue(
        field: 'rule.times',
        rule: 'times_distinct',
        message: 'A timed rule cannot plan the same time twice.',
        limit: 'unique',
      ),
    );
  }
  if (times.length > ProtocolPlanValidationLimits.warnTimesPerDay) {
    warnings.add(
      const DoseValidationIssue(
        field: 'rule.times',
        rule: 'times_many',
        message: 'More than ${ProtocolPlanValidationLimits.warnTimesPerDay} '
            'times a day is unusual.',
        limit: ProtocolPlanValidationLimits.warnTimesPerDay,
      ),
    );
  }
}

void _validateDays(Object? rawDays, List<DoseValidationIssue> errors) {
  final days =
      rawDays is Map<String, Object?> ? rawDays : const <String, Object?>{};
  switch (days['kind']) {
    case 'weekdays':
      final weekdays = days['weekdays'];
      final values = weekdays is List<Object?>
          ? weekdays.map(planWholeNumber).toList()
          : const <int?>[];
      if (values.isEmpty ||
          values.any((day) => day == null || day < 1 || day > 7) ||
          values.toSet().length != values.length) {
        errors.add(
          const DoseValidationIssue(
            field: 'rule.days.weekdays',
            rule: 'weekdays_valid',
            message: 'Choose at least one weekday, each from 1 (Monday) to 7 '
                '(Sunday), once.',
            limit: '1-7',
          ),
        );
      }
    case 'every_n_days':
      final n = planWholeNumber(days['n']);
      if (n == null ||
          n < ProtocolPlanValidationLimits.minEveryNDays ||
          n > ProtocolPlanValidationLimits.maxEveryNDays) {
        errors.add(
          const DoseValidationIssue(
            field: 'rule.days.n',
            rule: 'every_n_range',
            message: 'Every N days takes N from '
                '${ProtocolPlanValidationLimits.minEveryNDays} to '
                '${ProtocolPlanValidationLimits.maxEveryNDays}.',
            limit: '${ProtocolPlanValidationLimits.minEveryNDays}-'
                '${ProtocolPlanValidationLimits.maxEveryNDays}',
          ),
        );
      }
      if (_dateOrNull(days['anchor']) == null) {
        errors.add(_anchorDateIssue('rule.days.anchor'));
      }
  }
}

/// `amount_required`: all of amount, entered amount, unit and route are
/// present, and the Dose validator accepts them. Its soft warnings are left
/// to the Dose logged against the plan.
bool _amountIsValid(
  Object? amountValue,
  String? amountEntered,
  String? unit,
  String? route,
) {
  if (amountValue == null ||
      amountEntered == null ||
      amountEntered.trim().isEmpty ||
      unit == null ||
      route == null) {
    return false;
  }
  return validateDose(amount: amountValue, unit: unit, route: route).accepted;
}

/// Validates a Protocol's bounds ([endLocalDate] is inclusive, null for
/// ongoing) and its stored [period] JSON, or null for no cycle and no Pause.
DoseValidationResult validateProtocolPeriod({
  required ProtocolDayDate startLocalDate,
  required ProtocolDayDate? endLocalDate,
  required Map<String, Object?>? period,
}) {
  final errors = <DoseValidationIssue>[];
  final cycle = period?['cycle'];
  final rawPauses = period?['pauses'];
  final pauses = rawPauses is List<Object?> ? rawPauses : const <Object?>[];

  if (cycle is Map<String, Object?>) {
    if (_dateOrNull(cycle['anchor']) == null) {
      errors.add(_anchorDateIssue('period.cycle.anchor'));
    }
    final onDays = planWholeNumber(cycle['on_days']);
    final offDays = planWholeNumber(cycle['off_days']);
    bool inRange(int? days) =>
        days != null &&
        days >= 1 &&
        days <= ProtocolPlanValidationLimits.maxCycleLengthDays;
    if (!inRange(onDays) || !inRange(offDays)) {
      errors.add(
        const DoseValidationIssue(
          field: 'period.cycle',
          rule: 'cycle_lengths',
          message: 'A cycle is 1 to '
              '${ProtocolPlanValidationLimits.maxCycleLengthDays} days on and '
              '1 to ${ProtocolPlanValidationLimits.maxCycleLengthDays} days '
              'off.',
          limit: ProtocolPlanValidationLimits.maxCycleLengthDays,
        ),
      );
    }
  }

  if (endLocalDate != null && endLocalDate.compareTo(startLocalDate) < 0) {
    errors.add(
      const DoseValidationIssue(
        field: 'endLocalDate',
        rule: 'bounds_order',
        message: 'A Protocol cannot end before it starts.',
        limit: 'startLocalDate',
      ),
    );
  }

  // `pause_count` bounds the list before anything walks or sorts it; an
  // over-long list reports only that, and the other Pause checks don't run.
  if (pauses.length > ProtocolPlanValidationLimits.maxPauses) {
    errors.add(
      const DoseValidationIssue(
        field: 'period.pauses',
        rule: 'pause_count',
        message: 'A Protocol holds at most '
            '${ProtocolPlanValidationLimits.maxPauses} Pauses.',
        limit: ProtocolPlanValidationLimits.maxPauses,
      ),
    );
    return DoseValidationResult(
      errors: List<DoseValidationIssue>.unmodifiable(errors),
      warnings: const <DoseValidationIssue>[],
    );
  }

  // A Pause whose dates do not parse cannot be ordered, so it fails
  // `pause_order`, and the bounds and overlap checks skip it.
  final ranges = <({ProtocolDayDate from, ProtocolDayDate to})>[];
  var unordered = false;
  for (final pause in pauses) {
    final map =
        pause is Map<String, Object?> ? pause : const <String, Object?>{};
    final from = _dateOrNull(map['from']);
    final to = _dateOrNull(map['to']);
    if (from == null || to == null || from.compareTo(to) > 0) {
      unordered = true;
    }
    if (from != null && to != null) {
      ranges.add((from: from, to: to));
    }
  }
  if (unordered) {
    errors.add(
      const DoseValidationIssue(
        field: 'period.pauses',
        rule: 'pause_order',
        message: 'A Pause cannot end before it starts.',
        limit: 'from<=to',
      ),
    );
  }

  if (ranges.any(
    (range) =>
        range.from.compareTo(startLocalDate) < 0 ||
        range.to.compareTo(startLocalDate) < 0 ||
        (endLocalDate != null &&
            (range.from.compareTo(endLocalDate) > 0 ||
                range.to.compareTo(endLocalDate) > 0)),
  )) {
    errors.add(
      const DoseValidationIssue(
        field: 'period.pauses',
        rule: 'pause_bounds',
        message: 'A Pause must fall within the Protocol\'s dates.',
        limit: 'startLocalDate..endLocalDate',
      ),
    );
  }

  // Pauses are inclusive at both ends, so two that share a day overlap.
  final byStart = List.of(ranges)..sort((a, b) => a.from.compareTo(b.from));
  ProtocolDayDate? latestEnd;
  var overlaps = false;
  for (final range in byStart) {
    if (latestEnd != null && range.from.compareTo(latestEnd) <= 0) {
      overlaps = true;
    }
    if (latestEnd == null || range.to.compareTo(latestEnd) > 0) {
      latestEnd = range.to;
    }
  }
  if (overlaps) {
    errors.add(
      const DoseValidationIssue(
        field: 'period.pauses',
        rule: 'pause_overlap',
        message: 'Two Pauses cannot overlap.',
        limit: 'disjoint',
      ),
    );
  }

  return DoseValidationResult(
    errors: List<DoseValidationIssue>.unmodifiable(errors),
    warnings: const <DoseValidationIssue>[],
  );
}

DoseValidationIssue _anchorDateIssue(String field) {
  return DoseValidationIssue(
    field: field,
    rule: 'anchor_date',
    message: 'An anchor must be a real YYYY-MM-DD date.',
    limit: 'YYYY-MM-DD',
  );
}

ProtocolDayDate? _dateOrNull(Object? value) {
  if (value is! String) {
    return null;
  }
  try {
    return ProtocolDayDate.parse(value);
  } on FormatException {
    return null;
  }
}
