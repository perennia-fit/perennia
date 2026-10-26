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
  final sortedProtocols = protocols.toList()
    ..sort((a, b) => a.protocolId.compareTo(b.protocolId));
  final compoundIdsByProtocol = [
    for (final protocol in sortedProtocols)
      protocol.members.map((member) => member.compoundId).toSet().toList()
        ..sort(),
  ];
  final days = <PlanDay>[];
  for (var date = from; date.compareTo(to) <= 0; date = date.addDays(1)) {
    for (var index = 0; index < sortedProtocols.length; index += 1) {
      for (final compoundId in compoundIdsByProtocol[index]) {
        days.add(_planDay(sortedProtocols[index], compoundId, date));
      }
    }
  }
  return List<PlanDay>.unmodifiable(days);
}

PlanDay _planDay(
  PlanProtocol protocol,
  String compoundId,
  ProtocolDayDate date,
) {
  PlanDay state(PlanDayState state) => PlanDay(
        protocolId: protocol.protocolId,
        compoundId: compoundId,
        localDate: date,
        state: state,
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
  final member = _coveringMember(protocol.members, compoundId, date);
  if (member == null) {
    return state(PlanDayState.removed);
  }

  final version = _applyingVersion(member.versions, date);
  if (version == null) {
    return state(PlanDayState.noSchedule);
  }
  final rule = version.rule;
  final ScheduleDays days;
  final List<String?> times;
  switch (rule) {
    case UnscheduledScheduleRule():
      return state(PlanDayState.noSchedule);
    case AsNeededScheduleRule():
      return state(PlanDayState.asNeeded);
    case TimedScheduleRule():
      days = rule.days;
      times = rule.times;
    case UntimedScheduleRule():
      days = rule.days;
      times = List<String?>.filled(rule.count, null);
  }
  if (!days.includes(date)) {
    return state(PlanDayState.notScheduledToday);
  }
  return PlanDay(
    protocolId: protocol.protocolId,
    compoundId: compoundId,
    localDate: date,
    state: PlanDayState.planned,
    planned: times.map(
      (localTime) => PlannedDose(
        localTime: localTime,
        amountValue: version.amountValue,
        amountEntered: version.amountEntered,
        unit: version.unit,
        route: version.route,
      ),
    ),
  );
}

/// The member row of [compoundId] that covers [date], or null when none
/// does (D1). A row covers its first version's `effectiveFrom` through its
/// `archivedOn`, both inclusive; a row with no versions has no first date,
/// so it covers every date through its `archivedOn` and plans nothing. When
/// two rows cover one date (removed and re-added that day), the larger
/// member id, the newer UUIDv7 row, wins.
PlanMember? _coveringMember(
  Iterable<PlanMember> members,
  String compoundId,
  ProtocolDayDate date,
) {
  PlanMember? covering;
  for (final member in members) {
    if (member.compoundId != compoundId) {
      continue;
    }
    final archivedOn = member.archivedOn;
    if (archivedOn != null && date.compareTo(archivedOn) > 0) {
      continue;
    }
    final firstDate = member.versions.isEmpty
        ? null
        : member.versions
            .map((version) => version.effectiveFrom)
            .reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
    if (firstDate != null && date.compareTo(firstDate) < 0) {
      continue;
    }
    if (covering == null || member.memberId.compareTo(covering.memberId) > 0) {
      covering = member;
    }
  }
  return covering;
}

/// The Schedule Version that applies on [date] (D1): the latest
/// `effectiveFrom` on or before it, and on a shared date the larger id,
/// which is the latest edit because ids are UUIDv7.
ScheduleVersion? _applyingVersion(
  Iterable<ScheduleVersion> versions,
  ProtocolDayDate date,
) {
  ScheduleVersion? applying;
  for (final version in versions) {
    if (version.effectiveFrom.compareTo(date) > 0) {
      continue;
    }
    if (applying == null) {
      applying = version;
      continue;
    }
    final byDate = version.effectiveFrom.compareTo(applying.effectiveFrom);
    if (byDate > 0 || (byDate == 0 && version.id.compareTo(applying.id) > 0)) {
      applying = version;
    }
  }
  return applying;
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
          amountValue: slots[index].dose.amountValue,
          amountEntered: slots[index].dose.amountEntered,
          unit: slots[index].dose.unit,
          route: slots[index].dose.route,
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
    if (states.contains(_stateForReason(reason))) {
      return (DayStatusKind.notPlanned, reason);
    }
  }
  // Every PlanDay of a group has a state, and with nothing planned it is one
  // of the states above, so a group always resolves before here.
  throw StateError('A Compound date with nothing planned has no reason.');
}

PlanDayState _stateForReason(NotPlannedReason reason) {
  return switch (reason) {
    NotPlannedReason.notScheduledToday => PlanDayState.notScheduledToday,
    NotPlannedReason.asNeeded => PlanDayState.asNeeded,
    NotPlannedReason.noSchedule => PlanDayState.noSchedule,
    NotPlannedReason.removed => PlanDayState.removed,
    NotPlannedReason.outside => PlanDayState.outside,
  };
}

/// One planned dose that "Log all planned" would log now (D6).
class DueUnfilledDose {
  const DueUnfilledDose({
    required this.compoundId,
    required this.slot,
    required this.protocolId,
    this.amountValue,
    this.amountEntered,
    this.unit,
    this.route,
  });

  final String compoundId;
  final int slot;
  final String protocolId;
  final double? amountValue;
  final String? amountEntered;
  final DoseUnit? unit;
  final DoseRoute? route;

  Map<String, Object?> toJson() => <String, Object?>{
        'compoundId': compoundId,
        'slot': slot,
        'protocolId': protocolId,
        ...planAmountJson(amountValue, amountEntered, unit, route),
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
          amountValue: fill.amountValue,
          amountEntered: fill.amountEntered,
          unit: fill.unit,
          route: fill.route,
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
  if (days == null || perDay <= 0) {
    return null;
  }
  final cycle = period?.cycle;
  final rulePeriod = switch (days) {
    DailyScheduleDays() => 1,
    WeekdayScheduleDays() => 7,
    EveryNDaysScheduleDays() => days.n,
  };
  final cycleLength = cycle == null ? 1 : cycle.onDays + cycle.offDays;
  if (rulePeriod < 1 || cycleLength < 1) {
    throw RangeError('A plan period is at least 1 day.');
  }

  // Days are counted as offsets from the start. Ignoring Pauses, which day
  // plans what repeats every `repeatDays`, so whole repeats are skipped
  // rather than walked, and only the rule's own days are visited: every N
  // days for an every-N rule, else every day. An every-365-days rule on a
  // long cycle repeats only every few million days, yet visits a few
  // thousand rule days per repeat.
  final repeatDays = _lcm(rulePeriod, cycleLength);
  final stride = days is EveryNDaysScheduleDays ? days.n : 1;
  final anchorOffset = days is EveryNDaysScheduleDays
      ? days.anchor.daysBetween(startLocalDate)
      : 0;
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
  final lastDay = const ProtocolDayDate(year: 9999, month: 12, day: 31)
      .daysBetween(startLocalDate);
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
