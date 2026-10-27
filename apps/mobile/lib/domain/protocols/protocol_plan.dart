/// The Protocol Plan core's data shapes (docs/designs/protocol-schedules-and-reminders.md,
/// "Data shapes" and "Shared core API"): the Schedule Rule, Protocol Period,
/// Pause and Schedule Version an authored plan is stored as, and the
/// `PlanProtocol` / `PlanDay` / `PlanDose` / `DayStatus` values the pure core
/// in `protocol_plan_days.dart` takes and returns.
///
/// Everything here is timezone-free (D2): dates are [ProtocolDayDate] local
/// dates and times are `HH:MM` wall-clock strings. Planned doses and Day
/// Statuses are derived, never stored or synced.
///
/// The JSON codecs are pinned by the shared golden vector
/// `packages/golden-vectors/vectors/m36-protocol-plan.json`, which the
/// TypeScript twin (`apps/server/src/protocol-plan.ts`) runs too. Stored rule
/// and period JSON uses snake_case keys (`anchor_is_default`, `on_days`);
/// the core's own values use the Agent API's camelCase. A decoder throws a
/// [FormatException] for any `v` other than 1, any unknown `kind`, and any
/// value of the wrong type, a date that is not a real `YYYY-MM-DD` date, or a
/// time that is not `HH:MM` in 00:00-23:59, exactly as the TypeScript twin's
/// decoders do. A whole number reads as an integer however it was written
/// (`2.0` is 2), because TypeScript's JSON.parse cannot tell them apart.
///
/// The ranges a decoder checks are plannability and the safe ceilings, both
/// from [ProtocolPlanValidationLimits], and the constructors check them, so
/// the core never has to: every N days with N below 1 or above
/// [ProtocolPlanValidationLimits.maxEveryNDays], an untimed count below 1 or
/// above [ProtocolPlanValidationLimits.maxUntimedCount], a timed rule with no
/// times or more than [ProtocolPlanValidationLimits.maxTimesPerDay], and a
/// cycle of no days at all or with an on- or off-period below 0 or above
/// [ProtocolPlanValidationLimits.maxCycleLengthDays]. A constructor throws an
/// [ArgumentError] (a [RangeError]) for them, in release builds too, and a
/// decoder a [FormatException]. The ceilings keep a synced row that was never
/// validated from planning a billion doses, or a day count beyond what both
/// languages hold exactly. Every other range check (an every-N of 1, a cycle
/// with no off-period) is validation's job (`protocol_plan_validation.dart`),
/// not the decoder's.
library;

import 'protocols.dart';

/// The only rule and period JSON version this core reads and writes.
const int protocolPlanJsonVersion = 1;

/// The plan validators' limits, and the decoders' and constructors' ceilings.
/// Kept in lockstep with the TypeScript `PROTOCOL_PLAN_VALIDATION_LIMITS` and
/// the golden vector's `limits` block. It lives here, not in
/// `protocol_plan_validation.dart` (which exports it), so the types below can
/// enforce the ceilings without an import cycle.
class ProtocolPlanValidationLimits {
  const ProtocolPlanValidationLimits._();

  /// The most clock times a timed rule may plan in a day.
  static const int maxTimesPerDay = 12;

  /// The largest count an untimed rule may plan in a day.
  static const int maxUntimedCount = 12;

  static const int minEveryNDays = 2;
  static const int maxEveryNDays = 365;

  /// The longest on-period, and the longest off-period, of a cycle.
  static const int maxCycleLengthDays = 3650;

  /// More times than this in a day is more often a typo than a plan.
  static const int warnTimesPerDay = 6;
}

final RegExp _localTimePattern = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

/// Whether [value] is an `HH:MM` wall-clock time in 00:00-23:59.
bool isPlanLocalTime(String value) => _localTimePattern.hasMatch(value);

/// Minutes after local midnight for an `HH:MM` time [value].
int planLocalTimeMinutes(String value) {
  if (!isPlanLocalTime(value)) {
    throw FormatException('Expected an HH:MM local time.', value);
  }
  return int.parse(value.substring(0, 2)) * 60 + int.parse(value.substring(3));
}

/// Which days a Schedule Rule plans on (D4): every day, chosen ISO weekdays,
/// or every N days from an anchor date.
sealed class ScheduleDays {
  const ScheduleDays();

  factory ScheduleDays.fromJson(Object? json) {
    final map = _object(json, 'days');
    final kind = map['kind'];
    return switch (kind) {
      'daily' => const DailyScheduleDays(),
      'weekdays' => WeekdayScheduleDays(
          _intList(map['weekdays'], 'weekdays'),
        ),
      'every_n_days' => _plannable(
          'every N days',
          json,
          () => EveryNDaysScheduleDays(
            n: _int(map['n'], 'n'),
            anchor: _date(map['anchor'], 'anchor'),
            anchorIsDefault:
                _bool(map['anchor_is_default'], 'anchor_is_default'),
          ),
        ),
      _ => throw FormatException('Unknown Schedule days kind.', kind),
    };
  }

  /// Whether this rule's days include [date].
  bool includes(ProtocolDayDate date);

  Map<String, Object?> toJson();
}

/// Every day the Protocol is in effect.
class DailyScheduleDays extends ScheduleDays {
  const DailyScheduleDays();

  @override
  bool includes(ProtocolDayDate date) => true;

  @override
  Map<String, Object?> toJson() => const <String, Object?>{'kind': 'daily'};
}

/// Chosen ISO 8601 weekdays, 1 = Monday through 7 = Sunday, stored sorted.
class WeekdayScheduleDays extends ScheduleDays {
  WeekdayScheduleDays(Iterable<int> weekdays)
      : weekdays = List<int>.unmodifiable(weekdays);

  final List<int> weekdays;

  @override
  bool includes(ProtocolDayDate date) => weekdays.contains(date.isoWeekday);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': 'weekdays',
        'weekdays': weekdays,
      };
}

/// Every [n] days, counted from [anchor] (day 0). The anchor is always
/// stored; [anchorIsDefault] marks one the editor set to the Protocol's
/// start, which moves with the start (D1). [n] is 1 to
/// [ProtocolPlanValidationLimits.maxEveryNDays]; anything else throws a
/// [RangeError].
class EveryNDaysScheduleDays extends ScheduleDays {
  EveryNDaysScheduleDays({
    required int n,
    required this.anchor,
    required this.anchorIsDefault,
  }) : n = RangeError.checkValueInInterval(
          n,
          1,
          ProtocolPlanValidationLimits.maxEveryNDays,
          'n',
        );

  final int n;
  final ProtocolDayDate anchor;
  final bool anchorIsDefault;

  /// A date before the anchor counts backwards from it: Dart's `%` is never
  /// negative for a positive divisor, so day −3 of an every-3-days rule is
  /// planned just like day 3.
  @override
  bool includes(ProtocolDayDate date) => date.daysBetween(anchor) % n == 0;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': 'every_n_days',
        'n': n,
        'anchor': anchor.storageValue,
        'anchor_is_default': anchorIsDefault,
      };
}

/// The days-and-times part of a Schedule (CONTEXT.md `Schedule Rule`).
sealed class ScheduleRule {
  const ScheduleRule();

  /// Decodes the stored `rule` JSON. Throws a [FormatException] for any `v`
  /// other than 1, an unknown rule or days `kind`, or a malformed value.
  factory ScheduleRule.fromJson(Object? json) {
    final map = _object(json, 'rule');
    _requireVersion(map);
    final kind = map['kind'];
    return switch (kind) {
      'timed' => _plannable(
          'timed rule',
          json,
          () => TimedScheduleRule(
            days: ScheduleDays.fromJson(map['days']),
            times: _timeList(map['times']),
          ),
        ),
      'untimed' => _plannable(
          'untimed rule',
          json,
          () => UntimedScheduleRule(
            days: ScheduleDays.fromJson(map['days']),
            count: _int(map['count'], 'count'),
          ),
        ),
      'as_needed' => const AsNeededScheduleRule(),
      'unscheduled' => const UnscheduledScheduleRule(),
      _ => throw FormatException('Unknown Schedule Rule kind.', kind),
    };
  }

  Map<String, Object?> toJson();
}

/// 1 to [ProtocolPlanValidationLimits.maxTimesPerDay] `HH:MM` clock times on
/// each planned day, stored sorted; any other number throws a [RangeError].
class TimedScheduleRule extends ScheduleRule {
  TimedScheduleRule({required this.days, required Iterable<String> times})
      : times = _plannableTimes(times);

  static List<String> _plannableTimes(Iterable<String> times) {
    final list = List<String>.unmodifiable(times);
    RangeError.checkValueInInterval(
      list.length,
      1,
      ProtocolPlanValidationLimits.maxTimesPerDay,
      'times.length',
    );
    return list;
  }

  final ScheduleDays days;
  final List<String> times;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'v': protocolPlanJsonVersion,
        'kind': 'timed',
        'days': days.toJson(),
        'times': times,
      };
}

/// A count of untimed doses on each planned day, 1 to
/// [ProtocolPlanValidationLimits.maxUntimedCount]; anything else throws a
/// [RangeError]. Untimed planned doses count like any other, but never get a
/// reminder.
class UntimedScheduleRule extends ScheduleRule {
  UntimedScheduleRule({required this.days, required int count})
      : count = RangeError.checkValueInInterval(
          count,
          1,
          ProtocolPlanValidationLimits.maxUntimedCount,
          'count',
        );

  final ScheduleDays days;
  final int count;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'v': protocolPlanJsonVersion,
        'kind': 'untimed',
        'days': days.toJson(),
        'count': count,
      };
}

/// "As needed": plans nothing, and reads `as_needed`.
class AsNeededScheduleRule extends ScheduleRule {
  const AsNeededScheduleRule();

  @override
  Map<String, Object?> toJson() => const <String, Object?>{
        'v': protocolPlanJsonVersion,
        'kind': 'as_needed',
      };
}

/// The member has no Schedule: plans nothing, and reads `no_schedule`.
/// Clearing a Schedule in the editor inserts a version with this rule (D1).
class UnscheduledScheduleRule extends ScheduleRule {
  const UnscheduledScheduleRule();

  @override
  Map<String, Object?> toJson() => const <String, Object?>{
        'v': protocolPlanJsonVersion,
        'kind': 'unscheduled',
      };
}

/// A repeating on/off cycle (D4): [onDays] on, then [offDays] off, counted
/// from cycle day 0 at [anchor]. A date is on-cycle when
/// `(date − anchor) mod (onDays + offDays) < onDays`, so the cycle is at
/// least 1 day long. Each period is 0 to
/// [ProtocolPlanValidationLimits.maxCycleLengthDays] days; anything else, or
/// a cycle of no days at all, throws an [ArgumentError].
class ProtocolCycle {
  ProtocolCycle({
    required int onDays,
    required int offDays,
    required this.anchor,
    required this.anchorIsDefault,
  })  : onDays = RangeError.checkValueInInterval(
          onDays,
          0,
          ProtocolPlanValidationLimits.maxCycleLengthDays,
          'onDays',
        ),
        offDays = RangeError.checkValueInInterval(
          offDays,
          0,
          ProtocolPlanValidationLimits.maxCycleLengthDays,
          'offDays',
        ) {
    if (onDays + offDays < 1) {
      throw ArgumentError('A cycle is at least 1 day long.');
    }
  }

  factory ProtocolCycle.fromJson(Object? json) {
    final map = _object(json, 'cycle');
    return _plannable(
      'cycle',
      json,
      () => ProtocolCycle(
        onDays: _int(map['on_days'], 'on_days'),
        offDays: _int(map['off_days'], 'off_days'),
        anchor: _date(map['anchor'], 'anchor'),
        anchorIsDefault: _bool(map['anchor_is_default'], 'anchor_is_default'),
      ),
    );
  }

  final int onDays;
  final int offDays;
  final ProtocolDayDate anchor;
  final bool anchorIsDefault;

  /// Whether [date] falls in an on-period. A Pause never shifts this: the
  /// anchor stays where it is (CUJ 5).
  bool isOn(ProtocolDayDate date) {
    return date.daysBetween(anchor) % (onDays + offDays) < onDays;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'on_days': onDays,
        'off_days': offDays,
        'anchor': anchor.storageValue,
        'anchor_is_default': anchorIsDefault,
      };
}

/// A date range, inclusive at both ends, when a Protocol plans nothing.
class ProtocolPause {
  const ProtocolPause({required this.from, required this.to});

  factory ProtocolPause.fromJson(Object? json) {
    final map = _object(json, 'pause');
    return ProtocolPause(
      from: _date(map['from'], 'from'),
      to: _date(map['to'], 'to'),
    );
  }

  final ProtocolDayDate from;
  final ProtocolDayDate to;

  bool contains(ProtocolDayDate date) =>
      from.compareTo(date) <= 0 && date.compareTo(to) <= 0;

  Map<String, Object?> toJson() => <String, Object?>{
        'from': from.storageValue,
        'to': to.storageValue,
      };
}

/// The cycle and Pauses part of a Protocol Period (D4). The start and end
/// dates live in their own columns, beside this JSON.
class ProtocolPeriod {
  ProtocolPeriod({this.cycle, Iterable<ProtocolPause> pauses = const []})
      : pauses = List<ProtocolPause>.unmodifiable(pauses);

  /// Decodes the stored `period` JSON. A null column means no cycle and no
  /// Pause, and decodes to null; the equivalent `{"v":1,"cycle":null,
  /// "pauses":[]}` form is read too. Throws a [FormatException] for any `v`
  /// other than 1 or a malformed value.
  static ProtocolPeriod? fromJson(Object? json) {
    if (json == null) {
      return null;
    }
    final map = _object(json, 'period');
    _requireVersion(map);
    final cycle = map['cycle'];
    final pauses = map['pauses'];
    if (pauses is! List<Object?>) {
      throw FormatException('Expected a pauses list.', pauses);
    }
    return ProtocolPeriod(
      cycle: cycle == null ? null : ProtocolCycle.fromJson(cycle),
      pauses: pauses.map(ProtocolPause.fromJson),
    );
  }

  final ProtocolCycle? cycle;
  final List<ProtocolPause> pauses;

  bool isPaused(ProtocolDayDate date) =>
      pauses.any((pause) => pause.contains(date));

  Map<String, Object?> toJson() => <String, Object?>{
        'v': protocolPlanJsonVersion,
        'cycle': cycle?.toJson(),
        'pauses': pauses.map((pause) => pause.toJson()).toList(),
      };
}

/// The planned amount, unit and route that a Schedule Version, a planned
/// dose, a slot fill and a "Log all planned" row each carry, the twin of
/// the TypeScript `PlanAmount`. All four are present for `timed` and
/// `untimed` rules and null for `as_needed` and `unscheduled` (D7
/// `amount_required`). Its JSON is flat: the four keys sit in the carrier's
/// own object, in this order.
class PlanAmount {
  const PlanAmount({
    this.amountValue,
    this.amountEntered,
    this.unit,
    this.route,
  });

  /// Reads the four keys from [map], the carrier's own JSON object.
  factory PlanAmount.fromJson(Map<String, Object?> map) {
    return PlanAmount(
      amountValue: _nullableDouble(map['amountValue'], 'amountValue'),
      amountEntered: _nullableString(map['amountEntered'], 'amountEntered'),
      unit: _nullableUnit(map['unit']),
      route: _nullableRoute(map['route']),
    );
  }

  /// No amount: what `as_needed` and `unscheduled` versions carry.
  static const PlanAmount none = PlanAmount();

  final double? amountValue;
  final String? amountEntered;
  final DoseUnit? unit;
  final DoseRoute? route;

  Map<String, Object?> toJson() => <String, Object?>{
        'amountValue': amountValue,
        'amountEntered': amountEntered,
        'unit': unit?.name,
        'route': route?.name,
      };
}

/// One stored state of a Protocol Member's Schedule (CONTEXT.md `Schedule
/// Version`), applying from [effectiveFrom]. Versions are insert-only (D1).
class ScheduleVersion {
  const ScheduleVersion({
    required this.id,
    required this.effectiveFrom,
    required this.rule,
    this.amount = PlanAmount.none,
  });

  factory ScheduleVersion.fromJson(Object? json) {
    final map = _object(json, 'version');
    return ScheduleVersion(
      id: _string(map['id'], 'id'),
      effectiveFrom: _date(map['effectiveFrom'], 'effectiveFrom'),
      rule: ScheduleRule.fromJson(map['rule']),
      amount: PlanAmount.fromJson(map),
    );
  }

  final String id;
  final ProtocolDayDate effectiveFrom;
  final ScheduleRule rule;
  final PlanAmount amount;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'effectiveFrom': effectiveFrom.storageValue,
        'rule': rule.toJson(),
        ...amount.toJson(),
      };
}

/// One Compound inside a Protocol, with its Schedule Versions (CONTEXT.md
/// `Protocol Member`). A member row covers the dates from its first
/// version's `effectiveFrom` through [archivedOn], the local date its
/// removal was frozen at (D1).
class PlanMember {
  PlanMember({
    required this.memberId,
    required this.compoundId,
    required Iterable<ScheduleVersion> versions,
    this.archivedOn,
  }) : versions = List<ScheduleVersion>.unmodifiable(versions);

  factory PlanMember.fromJson(Object? json) {
    final map = _object(json, 'member');
    return PlanMember(
      memberId: _string(map['memberId'], 'memberId'),
      compoundId: _string(map['compoundId'], 'compoundId'),
      archivedOn: _nullableDate(map['archivedOn'], 'archivedOn'),
      versions:
          _list(map['versions'], 'versions').map(ScheduleVersion.fromJson),
    );
  }

  final String memberId;
  final String compoundId;
  final ProtocolDayDate? archivedOn;
  final List<ScheduleVersion> versions;

  Map<String, Object?> toJson() => <String, Object?>{
        'memberId': memberId,
        'compoundId': compoundId,
        'archivedOn': archivedOn?.storageValue,
        'versions': versions.map((version) => version.toJson()).toList(),
      };
}

/// One Protocol as the core reads it: its local-date bounds (end inclusive),
/// its Period, the frozen local date of its archive, and its members. Rows
/// tombstoned by undo are left out by the caller.
class PlanProtocol {
  PlanProtocol({
    required this.protocolId,
    required this.startLocalDate,
    required Iterable<PlanMember> members,
    this.endLocalDate,
    this.period,
    this.archivedOn,
    this.remindersEnabled = false,
  }) : members = List<PlanMember>.unmodifiable(members);

  factory PlanProtocol.fromJson(Object? json) {
    final map = _object(json, 'protocol');
    return PlanProtocol(
      protocolId: _string(map['protocolId'], 'protocolId'),
      startLocalDate: _date(map['startLocalDate'], 'startLocalDate'),
      endLocalDate: _nullableDate(map['endLocalDate'], 'endLocalDate'),
      period: ProtocolPeriod.fromJson(map['period']),
      archivedOn: _nullableDate(map['archivedOn'], 'archivedOn'),
      remindersEnabled: _bool(map['remindersEnabled'], 'remindersEnabled'),
      members: _list(map['members'], 'members').map(PlanMember.fromJson),
    );
  }

  final String protocolId;
  final ProtocolDayDate startLocalDate;
  final ProtocolDayDate? endLocalDate;
  final ProtocolPeriod? period;
  final ProtocolDayDate? archivedOn;
  final bool remindersEnabled;
  final List<PlanMember> members;

  Map<String, Object?> toJson() => <String, Object?>{
        'protocolId': protocolId,
        'startLocalDate': startLocalDate.storageValue,
        'endLocalDate': endLocalDate?.storageValue,
        'period': period?.toJson(),
        'archivedOn': archivedOn?.storageValue,
        'remindersEnabled': remindersEnabled,
        'members': members.map((member) => member.toJson()).toList(),
      };
}

/// How one date is decided for one Protocol and Compound (D4), in the order
/// the core checks them. [wireName] is the value in the vectors and the
/// Agent API.
enum PlanDayState {
  planned('planned'),
  notScheduledToday('not_scheduled_today'),
  asNeeded('as_needed'),
  noSchedule('no_schedule'),
  removed('removed'),
  outside('outside'),
  paused('paused'),
  offCycle('off_cycle');

  const PlanDayState(this.wireName);

  final String wireName;

  static PlanDayState fromWireName(Object? name) =>
      _byWireName(values, (state) => state.wireName, name, 'PlanDay state');
}

/// One planned dose (CONTEXT.md `Planned dose`): derived, never stored.
/// [localTime] is null for an untimed planned dose.
class PlannedDose {
  const PlannedDose({required this.localTime, this.amount = PlanAmount.none});

  factory PlannedDose.fromJson(Object? json) {
    final map = _object(json, 'planned dose');
    return PlannedDose(
      localTime: _nullableTime(map['localTime'], 'localTime'),
      amount: PlanAmount.fromJson(map),
    );
  }

  final String? localTime;
  final PlanAmount amount;

  Map<String, Object?> toJson() => <String, Object?>{
        'localTime': localTime,
        ...amount.toJson(),
      };
}

/// What one Protocol plans for one Compound on one local date. [planned] is
/// non-empty exactly when [state] is [PlanDayState.planned].
class PlanDay {
  PlanDay({
    required this.protocolId,
    required this.compoundId,
    required this.localDate,
    required this.state,
    Iterable<PlannedDose> planned = const <PlannedDose>[],
  }) : planned = List<PlannedDose>.unmodifiable(planned);

  factory PlanDay.fromJson(Object? json) {
    final map = _object(json, 'plan day');
    return PlanDay(
      protocolId: _string(map['protocolId'], 'protocolId'),
      compoundId: _string(map['compoundId'], 'compoundId'),
      localDate: _date(map['localDate'], 'localDate'),
      state: PlanDayState.fromWireName(map['state']),
      planned: _list(map['planned'], 'planned').map(PlannedDose.fromJson),
    );
  }

  final String protocolId;
  final String compoundId;
  final ProtocolDayDate localDate;
  final PlanDayState state;
  final List<PlannedDose> planned;

  Map<String, Object?> toJson() => <String, Object?>{
        'protocolId': protocolId,
        'compoundId': compoundId,
        'localDate': localDate.storageValue,
        'state': state.wireName,
        'planned': planned.map((dose) => dose.toJson()).toList(),
      };
}

/// One logged Dose as matching sees it (D6). [sequence] is the Dose's index
/// among that Compound's Doses on [localDate], ordered by local time and
/// then id; UUIDv7 ids sort by creation time.
class PlanDose {
  const PlanDose({
    required this.doseId,
    required this.compoundId,
    required this.localDate,
    required this.localTime,
    required this.sequence,
  });

  factory PlanDose.fromJson(Object? json) {
    final map = _object(json, 'dose');
    return PlanDose(
      doseId: _string(map['doseId'], 'doseId'),
      compoundId: _string(map['compoundId'], 'compoundId'),
      localDate: _date(map['localDate'], 'localDate'),
      localTime: _time(map['localTime'], 'localTime'),
      sequence: _int(map['sequence'], 'sequence'),
    );
  }

  final String doseId;
  final String compoundId;
  final ProtocolDayDate localDate;
  final String localTime;
  final int sequence;

  Map<String, Object?> toJson() => <String, Object?>{
        'doseId': doseId,
        'compoundId': compoundId,
        'localDate': localDate.storageValue,
        'localTime': localTime,
        'sequence': sequence,
      };
}

/// The single label for one Compound on one date (CONTEXT.md `Day Status`),
/// from a closed set. Never a score: UI copy and API fields carry statuses
/// and counts only.
enum DayStatusKind {
  notPlanned('not_planned'),
  paused('paused'),
  offCycle('off_cycle'),
  pending('pending'),
  logged('logged'),
  partlyLogged('partly_logged'),
  notLogged('not_logged');

  const DayStatusKind(this.wireName);

  final String wireName;

  static DayStatusKind fromWireName(Object? name) =>
      _byWireName(values, (status) => status.wireName, name, 'Day Status');
}

/// Why a [DayStatusKind.notPlanned] day has nothing planned, in the
/// precedence order D6 picks it across Protocols. Each is the [PlanDayState]
/// a Protocol reports for it, and shares that state's wire name.
enum NotPlannedReason {
  notScheduledToday(PlanDayState.notScheduledToday),
  asNeeded(PlanDayState.asNeeded),
  noSchedule(PlanDayState.noSchedule),
  removed(PlanDayState.removed),
  outside(PlanDayState.outside);

  const NotPlannedReason(this.state);

  final PlanDayState state;

  String get wireName => state.wireName;

  static NotPlannedReason fromWireName(Object? name) => _byWireName(
        values,
        (reason) => reason.wireName,
        name,
        'not-planned reason',
      );
}

/// One numbered planned dose (a slot) of a Compound on a date, and the Dose
/// that fills it, or null when it is unfilled.
class PlanSlotFill {
  const PlanSlotFill({
    required this.slot,
    required this.protocolId,
    required this.plannedLocalTime,
    required this.doseId,
    this.amount = PlanAmount.none,
  });

  factory PlanSlotFill.fromJson(Object? json) {
    final map = _object(json, 'fill');
    return PlanSlotFill(
      slot: _int(map['slot'], 'slot'),
      protocolId: _string(map['protocolId'], 'protocolId'),
      plannedLocalTime:
          _nullableTime(map['plannedLocalTime'], 'plannedLocalTime'),
      amount: PlanAmount.fromJson(map),
      doseId: _nullableString(map['doseId'], 'doseId'),
    );
  }

  final int slot;
  final String protocolId;
  final String? plannedLocalTime;
  final PlanAmount amount;
  final String? doseId;

  bool get isFilled => doseId != null;

  Map<String, Object?> toJson() => <String, Object?>{
        'slot': slot,
        'protocolId': protocolId,
        'plannedLocalTime': plannedLocalTime,
        ...amount.toJson(),
        'doseId': doseId,
      };
}

/// The Day Status of one Compound on one date, with its counts and every
/// slot (D6). Derived, never stored. [notPlannedReason] is set exactly when
/// [status] is [DayStatusKind.notPlanned]. Extra Doses are counted in
/// [extraCount] and never change [status].
class DayStatus {
  DayStatus({
    required this.compoundId,
    required this.localDate,
    required this.status,
    required this.plannedCount,
    required this.loggedCount,
    required this.extraCount,
    required Iterable<PlanSlotFill> fills,
    this.notPlannedReason,
  }) : fills = List<PlanSlotFill>.unmodifiable(fills);

  factory DayStatus.fromJson(Object? json) {
    final map = _object(json, 'day status');
    final reason = map['notPlannedReason'];
    return DayStatus(
      compoundId: _string(map['compoundId'], 'compoundId'),
      localDate: _date(map['localDate'], 'localDate'),
      status: DayStatusKind.fromWireName(map['status']),
      notPlannedReason:
          reason == null ? null : NotPlannedReason.fromWireName(reason),
      plannedCount: _int(map['plannedCount'], 'plannedCount'),
      loggedCount: _int(map['loggedCount'], 'loggedCount'),
      extraCount: _int(map['extraCount'], 'extraCount'),
      fills: _list(map['fills'], 'fills').map(PlanSlotFill.fromJson),
    );
  }

  final String compoundId;
  final ProtocolDayDate localDate;
  final DayStatusKind status;
  final NotPlannedReason? notPlannedReason;
  final int plannedCount;
  final int loggedCount;
  final int extraCount;
  final List<PlanSlotFill> fills;

  /// The key is left out entirely, not null, when there is no reason.
  Map<String, Object?> toJson() => <String, Object?>{
        'compoundId': compoundId,
        'localDate': localDate.storageValue,
        'status': status.wireName,
        if (notPlannedReason != null)
          'notPlannedReason': notPlannedReason!.wireName,
        'plannedCount': plannedCount,
        'loggedCount': loggedCount,
        'extraCount': extraCount,
        'fills': fills.map((fill) => fill.toJson()).toList(),
      };
}

void _requireVersion(Map<String, Object?> map) {
  final version = map['v'];
  if (planWholeNumber(version) != protocolPlanJsonVersion) {
    throw FormatException('Unsupported plan JSON version.', version);
  }
}

T _byWireName<T>(
  List<T> values,
  String Function(T value) wireName,
  Object? name,
  String what,
) {
  for (final value in values) {
    if (wireName(value) == name) {
      return value;
    }
  }
  throw FormatException('Unknown $what.', name);
}

Map<String, Object?> _object(Object? json, String what) {
  if (json is Map<String, Object?>) {
    return json;
  }
  throw FormatException('Expected a $what object.', json);
}

List<Object?> _list(Object? value, String field) {
  if (value is List<Object?>) {
    return value;
  }
  throw FormatException('Expected a $field list.', value);
}

String _string(Object? value, String field) {
  if (value is String) {
    return value;
  }
  throw FormatException('Expected a $field string.', value);
}

String? _nullableString(Object? value, String field) =>
    value == null ? null : _string(value, field);

bool _bool(Object? value, String field) {
  if (value is bool) {
    return value;
  }
  throw FormatException('Expected a $field boolean.', value);
}

int _int(Object? value, String field) {
  final whole = planWholeNumber(value);
  if (whole != null) {
    return whole;
  }
  throw FormatException('Expected a $field integer.', value);
}

/// [construct]'s value, with the [ArgumentError] a constructor throws for a
/// value the core cannot plan on, or one above a ceiling, read as malformed
/// JSON: a decoder throws only [FormatException]s.
T _plannable<T>(String what, Object? json, T Function() construct) {
  try {
    return construct();
  } on ArgumentError catch (error) {
    throw FormatException('Expected a plannable $what: $error', json);
  }
}

/// [value] as an integer when it is a finite whole number, an `int` or a
/// `double` such as 2.0, else null; `Number.isInteger` reads JSON the same
/// way in TypeScript. The decoders and the validators share it.
int? planWholeNumber(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  return null;
}

double? _nullableDouble(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException('Expected a $field number.', value);
}

List<int> _intList(Object? value, String field) {
  return _list(value, field).map((item) => _int(item, field)).toList();
}

ProtocolDayDate _date(Object? value, String field) {
  return ProtocolDayDate.parse(_string(value, field));
}

ProtocolDayDate? _nullableDate(Object? value, String field) =>
    value == null ? null : _date(value, field);

String _time(Object? value, String field) {
  final time = _string(value, field);
  if (!isPlanLocalTime(time)) {
    throw FormatException('Expected an HH:MM $field.', time);
  }
  return time;
}

String? _nullableTime(Object? value, String field) =>
    value == null ? null : _time(value, field);

/// A timed rule's times; how many is the constructor's to check.
List<String> _timeList(Object? value) {
  return _list(value, 'times').map((item) => _time(item, 'time')).toList();
}

DoseUnit? _nullableUnit(Object? value) => value == null
    ? null
    : _fromRegistryName(doseUnitFromName, _string(value, 'unit'));

DoseRoute? _nullableRoute(Object? value) => value == null
    ? null
    : _fromRegistryName(doseRouteFromName, _string(value, 'route'));

/// [fromName]'s registry member for [name]. A name outside the registry is
/// malformed JSON here, so its [ArgumentError] reads as a [FormatException].
T _fromRegistryName<T>(T Function(String name) fromName, String name) {
  try {
    return fromName(name);
  } on ArgumentError catch (error) {
    throw FormatException(error.message.toString(), name);
  }
}
