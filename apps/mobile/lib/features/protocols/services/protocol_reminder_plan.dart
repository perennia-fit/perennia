/// Which reminders the device should hold (docs/designs/
/// protocol-schedules-and-reminders.md, D5 and file 48): one per planned
/// clock time, over a rolling scheduling horizon. Pure: no I/O and no
/// plugin. The reminder reconciler (`protocol_reminder_scheduler.dart`)
/// diffs this against what the phone has pending.
///
/// The Protocol Plan core is timezone-free (D2); this is the one place where
/// a wall-clock planned time becomes an instant, in the phone's zone, which
/// is why it takes `now` as a [tz.TZDateTime].
library;

import 'package:timezone/timezone.dart' as tz;

import '../../../data/repositories/training_repositories.dart';

/// The longest scheduling horizon, in whole days counted from today (D5).
const int protocolReminderHorizonDays = 14;

/// The most reminders pending at once (D5). iOS keeps at most 64 pending
/// notifications per app; 48 leaves 16 for the rest timer, which uses 2 per
/// timer.
const int protocolReminderCap = 48;

/// The date reminder ids count from (file 48).
const ProtocolDayDate protocolReminderIdEpoch =
    ProtocolDayDate(year: 2000, month: 1, day: 1);

/// The minutes in a day, the stride of the reminder id formula.
const int _minutesPerDay = 1440;

/// The notification id of the reminder at [localTime] on [localDate]:
/// `-(daysBetween(2000-01-01, localDate) * 1440 + minuteOfDay) - 1`
/// (file 48).
///
/// One id per date and minute, so re-running the reconciler replaces a
/// reminder rather than duplicating it. Every date from 2000-01-01 to
/// 5999-12-31 gives a negative int32, from -1 down; the rest timer's ids are
/// non-negative, so the two never collide.
int protocolReminderId(ProtocolDayDate localDate, String localTime) {
  final days = localDate.daysBetween(protocolReminderIdEpoch);
  return -(days * _minutesPerDay + planLocalTimeMinutes(localTime)) - 1;
}

/// The instant [localTime] on [localDate] names in [location] (D2):
///
/// * a time that doesn't exist, because a daylight-saving change skips it,
///   is the first valid minute after the gap, so 02:30 fires at 03:00;
/// * a time that occurs twice, because a change repeats it, is its first
///   occurrence, so it fires once.
tz.TZDateTime protocolReminderInstant(
  tz.Location location,
  ProtocolDayDate localDate,
  String localTime,
) {
  final minutes = planLocalTimeMinutes(localTime);
  final wall = DateTime.utc(
    localDate.year,
    localDate.month,
    localDate.day,
    minutes ~/ 60,
    minutes % 60,
  ).millisecondsSinceEpoch;

  // A zone's offset changes at most once within a day of any wall time, so
  // the offsets a day either side are the only ones that can name it. Each
  // that maps back to itself is a valid reading; the earliest is the first
  // occurrence.
  const day = Duration.millisecondsPerDay;
  int? earliest;
  for (final probe in <int>[wall - day, wall, wall + day]) {
    final offset = location.timeZone(probe).offset.inMilliseconds;
    final instant = wall - offset;
    if (location.timeZone(instant).offset.inMilliseconds != offset) {
      continue;
    }
    if (earliest == null || instant < earliest) {
      earliest = instant;
    }
  }
  if (earliest != null) {
    return tz.TZDateTime.fromMillisecondsSinceEpoch(location, earliest);
  }

  // In a gap: read with the offset before the change, the wall time falls
  // inside the period after it, which starts at the change itself, the
  // first valid minute after the gap.
  final before = location.timeZone(wall - day).offset.inMilliseconds;
  final after = location.lookupTimeZone(wall - before);
  return tz.TZDateTime.fromMillisecondsSinceEpoch(location, after.start);
}

/// One reminder the device should hold: every unfilled planned dose due at
/// [localTime] on [localDate] shares it (D5).
final class ReminderSpec {
  const ReminderSpec({
    required this.id,
    required this.localDate,
    required this.localTime,
    required this.scheduledAt,
  });

  /// [protocolReminderId] of [localDate] and [localTime].
  final int id;
  final ProtocolDayDate localDate;

  /// The planned `HH:MM` time the reminder is for.
  final String localTime;

  /// When it fires, by [protocolReminderInstant].
  final tz.TZDateTime scheduledAt;

  @override
  bool operator ==(Object other) =>
      other is ReminderSpec &&
      other.id == id &&
      other.localDate == localDate &&
      other.localTime == localTime &&
      other.scheduledAt.isAtSameMomentAs(scheduledAt);

  @override
  int get hashCode => Object.hash(id, localDate, localTime);

  @override
  String toString() =>
      'ReminderSpec($id, ${localDate.storageValue} $localTime, $scheduledAt)';
}

/// What [desiredReminders] returns: the reminders, in firing order, and the
/// last day of the scheduling horizon.
final class DesiredReminders {
  DesiredReminders({
    required Iterable<ReminderSpec> reminders,
    required this.horizonEnd,
  }) : reminders = List<ReminderSpec>.unmodifiable(reminders);

  final List<ReminderSpec> reminders;

  /// The last day whose reminders are all included: the date the Protocol
  /// screen shows as "Reminders scheduled through" (CUJ 11). The day before
  /// today when not even today's reminders fit under the cap.
  final ProtocolDayDate horizonEnd;
}

/// The reminders the device should hold at [now] (D5, file 48).
///
/// * **Eligibility.** A planned time on a date gets one reminder when at
///   least one unfilled planned dose at that time belongs to a Protocol with
///   reminders on, and the time is still to come. [inputs] are timed planned
///   doses only (untimed ones never get a reminder).
/// * **Horizon.** Whole days only, from today in [now]'s zone: days are
///   added in date order while the total stays at or under [cap], up to
///   [horizonDays] days, and the horizon ends on the last day added. A day
///   whose reminders would take the total over [cap] is left out whole,
///   with every day after it.
DesiredReminders desiredReminders(
  Iterable<ProtocolReminderInput> inputs,
  tz.TZDateTime now, {
  int horizonDays = protocolReminderHorizonDays,
  int cap = protocolReminderCap,
}) {
  final today = ProtocolDayDate(year: now.year, month: now.month, day: now.day);

  // The times that get a reminder, by date. Only the horizon's dates are
  // read below, so inputs outside it drop out there.
  final timesByDate = <ProtocolDayDate, Set<String>>{};
  for (final input in inputs) {
    if (!input.remindersEnabled || input.filled) {
      continue;
    }
    timesByDate.putIfAbsent(input.localDate, () => <String>{}).add(
          input.localTime,
        );
  }

  final reminders = <ReminderSpec>[];
  var horizonEnd = today.addDays(-1);
  for (var offset = 0; offset < horizonDays; offset += 1) {
    final date = today.addDays(offset);
    final times = (timesByDate[date] ?? const <String>{}).toList()
      ..sort((a, b) => planLocalTimeMinutes(a).compareTo(
            planLocalTimeMinutes(b),
          ));
    final day = <ReminderSpec>[];
    for (final time in times) {
      final at = protocolReminderInstant(now.location, date, time);
      if (at.isAfter(now)) {
        day.add(
          ReminderSpec(
            id: protocolReminderId(date, time),
            localDate: date,
            localTime: time,
            scheduledAt: at,
          ),
        );
      }
    }
    if (reminders.length + day.length > cap) {
      break;
    }
    reminders.addAll(day);
    horizonEnd = date;
  }
  return DesiredReminders(reminders: reminders, horizonEnd: horizonEnd);
}
