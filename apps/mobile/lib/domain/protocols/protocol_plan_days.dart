/// The Protocol Plan core (docs/designs/protocol-schedules-and-reminders.md,
/// D1, D4 and D6): what was planned on a range of dates, and how the logged
/// Doses line up with it. Every surface (the Planned list, the Consistency
/// view, the reminder reconciler) asks these functions instead of reading a
/// Schedule directly.
///
/// Pure and timezone-free: no I/O, no clock, no timezone. Dates are local
/// [ProtocolDayDate]s, times are `HH:MM` strings, and "today" and "now" are
/// inputs. Nothing returned here is stored or synced.
///
/// [planDays], [dayStatuses] and [dueUnfilled] are pinned against the
/// TypeScript twin (`apps/server/src/protocol-plan.ts`) by
/// `packages/golden-vectors/vectors/m36-protocol-plan.json`.
/// [endDateForDoseCount] is Dart only, because no Agent operation uses it.
library;

import 'dart:math';

import 'protocol_plan.dart';
import 'protocols.dart';

/// What each Protocol plans for each of its Compounds on every date from
/// [from] through [to], inclusive. Returns one [PlanDay] per Protocol,
/// Compound and date, ordered by date, then Protocol id, then Compound id.
///
/// A date is decided for one Protocol and Compound in this order (D4):
/// 1. outside the Protocol's bounds (end inclusive) → `outside`;
/// 2. inside a Pause → `paused`;
/// 3. in the cycle's off-period → `off_cycle`;
/// 4. after the Protocol's `archivedOn`, or no member row of the Compound
///    covers the date → `removed`;
/// 5. the member's Schedule Version for the date: none, or `unscheduled` →
///    `no_schedule`; `as_needed` → `as_needed`; days that exclude the date
///    → `not_scheduled_today`; otherwise `planned`.
List<PlanDay> planDays(
  Iterable<PlanProtocol> protocols,
  ProtocolDayDate from,
  ProtocolDayDate to,
) {
  final plans = protocols.map(_ProtocolPlan.new).toList()
    ..sort((a, b) => a.protocol.protocolId.compareTo(b.protocol.protocolId));
  final days = <PlanDay>[];
  for (var date = from; date.compareTo(to) <= 0; date = date.addDays(1)) {
    for (final plan in plans) {
      for (final compoundId in plan.compoundIds) {
        days.add(_planDay(plan, compoundId, date));
      }
    }
  }
  return List<PlanDay>.unmodifiable(days);
}

PlanDay _planDay(
  _ProtocolPlan plan,
  String compoundId,
  ProtocolDayDate date,
) {
  final protocol = plan.protocol;
  PlanDay state(
    PlanDayState state, [
    List<PlannedDose> planned = const <PlannedDose>[],
  ]) =>
      PlanDay(
        protocolId: protocol.protocolId,
        compoundId: compoundId,
        localDate: date,
        state: state,
        planned: planned,
      );

  final end = protocol.endLocalDate;
  if (date.compareTo(protocol.startLocalDate) < 0 ||
      (end != null && date.compareTo(end) > 0)) {
    return state(PlanDayState.outside);
  }
  final period = protocol.period;
  if (period != null && period.isPaused(date)) {
    return state(PlanDayState.paused);
  }
  final cycle = period?.cycle;
  if (cycle != null && !cycle.isOn(date)) {
    return state(PlanDayState.offCycle);
  }
  final archivedOn = protocol.archivedOn;
  if (archivedOn != null && date.compareTo(archivedOn) > 0) {
    return state(PlanDayState.removed);
  }
  final row = plan.coveringRow(compoundId, date);
  if (row == null) {
    return state(PlanDayState.removed);
  }

  final version = row.applyingVersion(date);
  if (version == null) {
    return state(PlanDayState.noSchedule);
  }
  final rule = version.version.rule;
  final ScheduleDays days;
  switch (rule) {
    case UnscheduledScheduleRule():
      return state(PlanDayState.noSchedule);
    case AsNeededScheduleRule():
      return state(PlanDayState.asNeeded);
    case TimedScheduleRule():
      days = rule.days;
    case UntimedScheduleRule():
      days = rule.days;
  }
  if (!days.includes(date)) {
    return state(PlanDayState.notScheduledToday);
  }
  return state(PlanDayState.planned, version.planned);
}

/// One Protocol as [planDays] reads it on every date, worked out once per
/// call: its Compound ids in order, and each Compound's member rows.
class _ProtocolPlan {
  _ProtocolPlan._(this.protocol, this.compoundIds, this._rowsByCompound);

  factory _ProtocolPlan(PlanProtocol protocol) {
    final rowsByCompound = <String, List<_MemberRow>>{};
    for (final member in protocol.members) {
      rowsByCompound
          .putIfAbsent(member.compoundId, () => [])
          .add(_MemberRow(member));
    }
    for (final rows in rowsByCompound.values) {
      rows.sort((a, b) => b.memberId.compareTo(a.memberId));
    }
    return _ProtocolPlan._(
      protocol,
      rowsByCompound.keys.toList()..sort(),
      rowsByCompound,
    );
  }

  final PlanProtocol protocol;
  final List<String> compoundIds;

  /// Each Compound's rows, the larger member id first.
  final Map<String, List<_MemberRow>> _rowsByCompound;

  /// The member row of [compoundId] that covers [date], or null when none
  /// does (D1). When two rows cover one date (removed and re-added that
  /// day), the larger member id, the newer UUIDv7 row, wins, and rows are
  /// kept in that order, so the first that covers it is the one.
  _MemberRow? coveringRow(String compoundId, ProtocolDayDate date) {
    for (final row in _rowsByCompound[compoundId] ?? const <_MemberRow>[]) {
      if (row.covers(date)) {
        return row;
      }
    }
    return null;
  }
}

/// One member row, with its versions in `effectiveFrom` order, then id
/// order, and each version's planned doses built once.
class _MemberRow {
  _MemberRow(PlanMember member)
      : memberId = member.memberId,
        archivedOn = member.archivedOn,
        _versions = [
          for (final version in member.versions) _VersionPlan(version),
        ]..sort(_VersionPlan.compare);

  final String memberId;
  final ProtocolDayDate? archivedOn;
  final List<_VersionPlan> _versions;

  /// A row covers its first version's `effectiveFrom` through its
  /// `archivedOn`, both inclusive; a row with no versions has no first date,
  /// so it covers every date through its `archivedOn` and plans nothing.
  bool covers(ProtocolDayDate date) {
    final archivedOn = this.archivedOn;
    if (archivedOn != null && date.compareTo(archivedOn) > 0) {
      return false;
    }
    return _versions.isEmpty ||
        date.compareTo(_versions.first.version.effectiveFrom) >= 0;
  }

  /// The Schedule Version that applies on [date] (D1): the latest
  /// `effectiveFrom` on or before it, and on a shared date the larger id,
  /// which is the latest edit because ids are UUIDv7. In version order, that
  /// is the last one on or before [date].
  _VersionPlan? applyingVersion(ProtocolDayDate date) {
    for (var index = _versions.length - 1; index >= 0; index -= 1) {
      if (_versions[index].version.effectiveFrom.compareTo(date) <= 0) {
        return _versions[index];
      }
    }
    return null;
  }
}

/// One Schedule Version and the planned doses it plans on each of its days,
/// shared by every date it plans (empty for a rule that plans nothing).
class _VersionPlan {
  _VersionPlan(this.version)
      : planned = List<PlannedDose>.unmodifiable(
          _plannedTimes(version.rule).map(
            (localTime) =>
                PlannedDose(localTime: localTime, amount: version.amount),
          ),
        );

  final ScheduleVersion version;
  final List<PlannedDose> planned;

  static List<String?> _plannedTimes(ScheduleRule rule) => switch (rule) {
        TimedScheduleRule() => rule.times,
        UntimedScheduleRule() => List<String?>.filled(rule.count, null),
        AsNeededScheduleRule() ||
        UnscheduledScheduleRule() =>
          const <String?>[],
      };

  static int compare(_VersionPlan a, _VersionPlan b) {
    final byDate = a.version.effectiveFrom.compareTo(b.version.effectiveFrom);
    return byDate != 0 ? byDate : a.version.id.compareTo(b.version.id);
  }
}

/// One Day Status per Compound and date in [planDays], for dates up to and
/// including [today]; later dates are not returned. Ordered by date, then
/// Compound id. [doses] are the Compound's non-archived logged Doses, tagged
/// with a Protocol or not; the tag never decides whether a Dose counts.
///
/// Matching, for one Compound on one date (D6):
/// 1. Every planned dose of every Protocol is numbered as a slot, ordered by
///    time (untimed last), then Protocol id, then position in its PlanDay.
/// 2. The Doses are taken in local-time order, then [PlanDose.sequence].
/// 3. Each fills the unfilled timed slot nearest its time (the earlier slot
///    on a tie); with no timed slot unfilled, the first unfilled untimed
///    slot; with nothing unfilled, it is an extra.
List<DayStatus> dayStatuses(
  Iterable<PlanDay> planDays,
  Iterable<PlanDose> doses,
  ProtocolDayDate today,
) {
  final daysByKey = <_CompoundDate, List<PlanDay>>{};
  for (final day in planDays) {
    if (day.localDate.compareTo(today) > 0) {
      continue;
    }
    daysByKey
        .putIfAbsent(_CompoundDate(day.compoundId, day.localDate), () => [])
        .add(day);
  }
  final dosesByKey = <_CompoundDate, List<PlanDose>>{};
  for (final dose in doses) {
    dosesByKey
        .putIfAbsent(_CompoundDate(dose.compoundId, dose.localDate), () => [])
        .add(dose);
  }

  final keys = daysByKey.keys.toList()
    ..sort((a, b) {
      final byDate = a.localDate.compareTo(b.localDate);
      return byDate != 0 ? byDate : a.compoundId.compareTo(b.compoundId);
    });
  return List<DayStatus>.unmodifiable(
    keys.map(
      (key) => _dayStatus(
        key,
        daysByKey[key]!,
        dosesByKey[key] ?? const <PlanDose>[],
        today,
      ),
    ),
  );
}

DayStatus _dayStatus(
  _CompoundDate key,
  List<PlanDay> days,
  List<PlanDose> doses,
  ProtocolDayDate today,
) {
  final slots = <_Slot>[
    for (final day in days)
      if (day.state == PlanDayState.planned)
        for (var position = 0; position < day.planned.length; position += 1)
          _Slot(day.protocolId, position, day.planned[position]),
  ]..sort(_Slot.compare);

  final orderedDoses = List<PlanDose>.of(doses)
    ..sort((a, b) {
      final byTime = a.localTime.compareTo(b.localTime);
      if (byTime != 0) {
        return byTime;
      }
      final bySequence = a.sequence.compareTo(b.sequence);
      return bySequence != 0 ? bySequence : a.doseId.compareTo(b.doseId);
    });

  final filledBy = List<String?>.filled(slots.length, null);
  var loggedCount = 0;
  for (final dose in orderedDoses) {
    final slot = _slotFor(dose, slots, filledBy);
    if (slot != null) {
      filledBy[slot] = dose.doseId;
      loggedCount += 1;
    }
  }

  final plannedCount = slots.length;
  final (status, reason) = plannedCount > 0
      ? (_plannedStatus(plannedCount, loggedCount, key.localDate, today), null)
      : _unplannedStatus(days);

  return DayStatus(
    compoundId: key.compoundId,
    localDate: key.localDate,
    status: status,
    notPlannedReason: reason,
    plannedCount: plannedCount,
    loggedCount: loggedCount,
    extraCount: orderedDoses.length - loggedCount,
    fills: [
      for (var index = 0; index < slots.length; index += 1)
        PlanSlotFill(
          slot: index,
          protocolId: slots[index].protocolId,
          plannedLocalTime: slots[index].dose.localTime,
          amount: slots[index].dose.amount,
          doseId: filledBy[index],
        ),
    ],
  );
}

/// The slot [dose] fills, or null when it is an extra (D6 step 3).
int? _slotFor(PlanDose dose, List<_Slot> slots, List<String?> filledBy) {
  final doseMinutes = planLocalTimeMinutes(dose.localTime);
  int? nearest;
  int? nearestDistance;
  int? firstUntimed;
  for (var index = 0; index < slots.length; index += 1) {
    if (filledBy[index] != null) {
      continue;
    }
    final minutes = slots[index].minutes;
    if (minutes == null) {
      firstUntimed ??= index;
      continue;
    }
    final distance = (minutes - doseMinutes).abs();
    // Strictly nearer only: slots are in time order, so on a tie the earlier
    // slot, found first, keeps it.
    if (nearestDistance == null || distance < nearestDistance) {
      nearest = index;
      nearestDistance = distance;
    }
  }
  return nearest ?? firstUntimed;
}

DayStatusKind _plannedStatus(
  int plannedCount,
  int loggedCount,
  ProtocolDayDate date,
  ProtocolDayDate today,
) {
  if (loggedCount >= plannedCount) {
    return DayStatusKind.logged;
  }
  if (date == today) {
    return DayStatusKind.pending;
  }
  return loggedCount > 0 ? DayStatusKind.partlyLogged : DayStatusKind.notLogged;
}

/// With nothing planned (D6): `paused` if any Protocol reports it, else
/// `off_cycle`, else `not_planned` with the first reason any Protocol
/// reports, in [NotPlannedReason]'s declared order.
(DayStatusKind, NotPlannedReason?) _unplannedStatus(List<PlanDay> days) {
  final states = days.map((day) => day.state).toSet();
  if (states.contains(PlanDayState.paused)) {
    return (DayStatusKind.paused, null);
  }
  if (states.contains(PlanDayState.offCycle)) {
    return (DayStatusKind.offCycle, null);
  }
  for (final reason in NotPlannedReason.values) {
    if (states.contains(reason.state)) {
      return (DayStatusKind.notPlanned, reason);
    }
  }
  // Every PlanDay of a group has a state, and with nothing planned it is one
  // of the states above, so a group always resolves before here.
  throw StateError('A Compound date with nothing planned has no reason.');
}

/// One planned dose that "Log all planned" would log now (D6).
class DueUnfilledDose {
  const DueUnfilledDose({
    required this.compoundId,
    required this.slot,
    required this.protocolId,
    this.amount = PlanAmount.none,
  });

  final String compoundId;
  final int slot;
  final String protocolId;
  final PlanAmount amount;

  Map<String, Object?> toJson() => <String, Object?>{
        'compoundId': compoundId,
        'slot': slot,
        'protocolId': protocolId,
        ...amount.toJson(),
      };
}

/// The planned doses "Log all planned" logs (D6): [today]'s unfilled slots
/// that are timed at or before [nowLocalTime], or untimed. Other dates are
/// ignored. Ordered by Compound id, then slot.
List<DueUnfilledDose> dueUnfilled(
  Iterable<DayStatus> dayStatuses,
  ProtocolDayDate today,
  String nowLocalTime,
) {
  final now = planLocalTimeMinutes(nowLocalTime);
  final todays = dayStatuses
      .where((status) => status.localDate == today)
      .toList()
    ..sort((a, b) => a.compoundId.compareTo(b.compoundId));
  final due = <DueUnfilledDose>[];
  for (final status in todays) {
    final fills = List<PlanSlotFill>.of(status.fills)
      ..sort((a, b) => a.slot.compareTo(b.slot));
    for (final fill in fills) {
      final time = fill.plannedLocalTime;
      if (fill.isFilled || (time != null && planLocalTimeMinutes(time) > now)) {
        continue;
      }
      due.add(
        DueUnfilledDose(
          compoundId: status.compoundId,
          slot: fill.slot,
          protocolId: fill.protocolId,
          amount: fill.amount,
        ),
      );
    }
  }
  return List<DueUnfilledDose>.unmodifiable(due);
}

/// The smallest and largest dose count [endDateForDoseCount] accepts.
const int minDoseCountForEndDate = 1;
const int maxDoseCountForEndDate = 1000;

/// The "N doses" helper (D6): the local date of the [doseCount]th planned
/// dose of one member under [rule], counted from [startLocalDate] and
/// skipping off-cycle and paused days. It counts doses, not days: a rule of
/// 08:00 and 20:00 reaches 20 doses on day 10. The Protocol's end date sets
/// nothing here; this computes it.
///
/// Returns null ("unavailable") for an `as_needed` or `unscheduled` rule, for
/// a rule whose days never fall on an on-cycle day, and when the dose would
/// fall after 9999-12-31, the last date a `YYYY-MM-DD` value holds. Throws a
/// [RangeError] when [doseCount] is outside 1-1000.
ProtocolDayDate? endDateForDoseCount({
  required ProtocolDayDate startLocalDate,
  required ScheduleRule rule,
  required int doseCount,
  ProtocolPeriod? period,
}) {
  RangeError.checkValueInInterval(
    doseCount,
    minDoseCountForEndDate,
    maxDoseCountForEndDate,
    'doseCount',
  );
  final (days, perDay) = switch (rule) {
    TimedScheduleRule() => (rule.days, rule.times.length),
    UntimedScheduleRule() => (rule.days, rule.count),
    AsNeededScheduleRule() || UnscheduledScheduleRule() => (null, 0),
  };
  if (days == null) {
    return null;
  }
  final cycle = period?.cycle;
  final cycleLength = cycle == null ? 1 : cycle.onDays + cycle.offDays;

  // Days are counted as offsets from the start. Ignoring Pauses, which day
  // plans what repeats every `repeatDays`, so whole repeats are skipped
  // rather than walked, and only the rule's own days are visited: every N
  // days for an every-N rule, else every day. An every-365-days rule on a
  // long cycle repeats only every few million days, yet visits a few
  // thousand rule days per repeat.
  final (rulePeriod, stride, anchorOffset) = switch (days) {
    DailyScheduleDays() => (1, 1, 0),
    WeekdayScheduleDays() => (7, 1, 0),
    EveryNDaysScheduleDays(:final n, :final anchor) => (
        n,
        n,
        anchor.daysBetween(startLocalDate),
      ),
  };
  final repeatDays = _lcm(rulePeriod, cycleLength);
  int firstRuleDay(int day) => day + (anchorOffset - day) % stride;
  bool plansOn(int day) {
    final date = startLocalDate.addDays(day);
    return days.includes(date) && (cycle == null || cycle.isOn(date));
  }

  var perRepeat = 0;
  for (var day = firstRuleDay(0); day < repeatDays; day += stride) {
    if (plansOn(day)) {
      perRepeat += perDay;
    }
  }
  if (perRepeat == 0) {
    return null;
  }

  // Walk the gaps between Pauses: step over each Pause at once, skip whole
  // repeats inside a gap, then visit the rule's days to the gap's end.
  final lastDay = ProtocolDayDate.max.daysBetween(startLocalDate);
  final pauses = [
    for (final pause in period?.pauses ?? const <ProtocolPause>[])
      (
        from: pause.from.daysBetween(startLocalDate),
        to: pause.to.daysBetween(startLocalDate),
      ),
  ]..sort((a, b) => a.from.compareTo(b.from));
  var remaining = doseCount;
  var day = 0;
  var nextPause = 0;
  while (true) {
    var gapEnd = lastDay;
    while (nextPause < pauses.length) {
      final pause = pauses[nextPause];
      if (pause.from > day) {
        gapEnd = min(lastDay, pause.from - 1);
        break;
      }
      day = max(day, pause.to + 1);
      nextPause += 1;
    }
    if (day > lastDay) {
      return null;
    }
    final repeats = min(
      (remaining - 1) ~/ perRepeat,
      (gapEnd - day + 1) ~/ repeatDays,
    );
    day += repeats * repeatDays;
    remaining -= repeats * perRepeat;
    for (var ruleDay = firstRuleDay(day);
        ruleDay <= gapEnd;
        ruleDay += stride) {
      if (plansOn(ruleDay)) {
        remaining -= perDay;
        if (remaining <= 0) {
          return startLocalDate.addDays(ruleDay);
        }
      }
    }
    day = gapEnd + 1;
  }
}

int _lcm(int a, int b) => a ~/ a.gcd(b) * b;

/// A Compound on a local date: the unit a Day Status is computed for.
class _CompoundDate {
  const _CompoundDate(this.compoundId, this.localDate);

  final String compoundId;
  final ProtocolDayDate localDate;

  @override
  bool operator ==(Object other) =>
      other is _CompoundDate &&
      other.compoundId == compoundId &&
      other.localDate == localDate;

  @override
  int get hashCode => Object.hash(compoundId, localDate);
}

/// One planned dose before it is numbered: its Protocol, its position in
/// that Protocol's PlanDay, and its time in minutes (null when untimed).
class _Slot {
  _Slot(this.protocolId, this.position, this.dose)
      : minutes = dose.localTime == null
            ? null
            : planLocalTimeMinutes(dose.localTime!);

  final String protocolId;
  final int position;
  final PlannedDose dose;
  final int? minutes;

  /// Time (untimed last), then Protocol id, then position (D6 step 1).
  static int compare(_Slot a, _Slot b) {
    final aMinutes = a.minutes;
    final bMinutes = b.minutes;
    if (aMinutes != bMinutes) {
      if (aMinutes == null) {
        return 1;
      }
      if (bMinutes == null) {
        return -1;
      }
      return aMinutes.compareTo(bMinutes);
    }
    final byProtocol = a.protocolId.compareTo(b.protocolId);
    return byProtocol != 0 ? byProtocol : a.position.compareTo(b.position);
  }
}
