import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/protocols/protocol_plan_days.dart';
import 'package:perennia/features/protocols/services/protocol_reminder_plan.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// `desiredReminders` (D5, file 48): which reminders the phone should hold.
void main() {
  late tz.Location newYork;

  setUpAll(() {
    tz_data.initializeTimeZones();
    newYork = tz.getLocation('America/New_York');
  });

  tz.TZDateTime at(int year, int month, int day, int hour, [int minute = 0]) {
    return tz.TZDateTime(newYork, year, month, day, hour, minute);
  }

  const today = ProtocolDayDate(year: 2026, month: 10, day: 28);

  group('eligibility', () {
    test('CUJ 1: doses due at the same minute share one reminder', () {
      final desired = desiredReminders(
        <ProtocolReminderInput>[
          _input('trt', today, '09:00'),
          _input('agemate', today, '09:00'),
          _input('creatine', today, '17:00'),
        ],
        at(2026, 10, 28, 8),
      );

      expect(
        desired.reminders.map((r) => (r.localDate, r.localTime)),
        <(ProtocolDayDate, String)>[(today, '09:00'), (today, '17:00')],
      );
      expect(desired.reminders.first.id, protocolReminderId(today, '09:00'));
      expect(
        desired.reminders.first.scheduledAt,
        at(2026, 10, 28, 9),
      );
    });

    test('CUJ 2: a filled dose drops out, and its time stays while another '
        'dose at it is unfilled', () {
      final oneLogged = desiredReminders(
        <ProtocolReminderInput>[
          _input('trt', today, '09:00', filled: true),
          _input('agemate', today, '09:00'),
        ],
        at(2026, 10, 28, 8, 40),
      );
      expect(oneLogged.reminders.map((r) => r.localTime), <String>['09:00']);

      final bothLogged = desiredReminders(
        <ProtocolReminderInput>[
          _input('trt', today, '09:00', filled: true),
          _input('agemate', today, '09:00', filled: true),
        ],
        at(2026, 10, 28, 8, 40),
      );
      expect(bothLogged.reminders, isEmpty);
    });

    test('CUJ 3: no reminder on an off-cycle day, and it starts again on '
        'day 0 of the next cycle', () {
      final skin = PlanProtocol(
        protocolId: 'skin',
        startLocalDate: const ProtocolDayDate(year: 2026, month: 9, day: 1),
        remindersEnabled: true,
        period: ProtocolPeriod(
          cycle: ProtocolCycle(
            onDays: 60,
            offDays: 30,
            anchor: const ProtocolDayDate(year: 2026, month: 9, day: 1),
            anchorIsDefault: false,
          ),
        ),
        members: <PlanMember>[
          PlanMember(
            memberId: 'member-ghk',
            compoundId: 'ghk-cu',
            versions: <ScheduleVersion>[
              ScheduleVersion(
                id: 'version-ghk',
                effectiveFrom:
                    const ProtocolDayDate(year: 2026, month: 9, day: 1),
                rule: _dailyAt('21:00'),
              ),
            ],
          ),
        ],
      );

      const offCycleDay = ProtocolDayDate(year: 2026, month: 11, day: 5);
      final offCycle = desiredReminders(
        _futureInputs(<PlanProtocol>[skin], offCycleDay, 14),
        at(2026, 11, 5, 8),
      );
      expect(offCycle.reminders, isEmpty);
      // Nothing is due, so every day of the horizon fits.
      expect(offCycle.horizonEnd, offCycleDay.addDays(13));

      const lastOffDay = ProtocolDayDate(year: 2026, month: 11, day: 29);
      final restart = desiredReminders(
        _futureInputs(<PlanProtocol>[skin], lastOffDay, 3),
        at(2026, 11, 29, 8),
        horizonDays: 3,
      );
      expect(
        restart.reminders.map((r) => (r.localDate, r.localTime)),
        <(ProtocolDayDate, String)>[
          (const ProtocolDayDate(year: 2026, month: 11, day: 30), '21:00'),
          (const ProtocolDayDate(year: 2026, month: 12, day: 1), '21:00'),
        ],
      );
    });

    test('a time gets a reminder only from a reminders-on Protocol\'s '
        'unfilled dose', () {
      final desired = desiredReminders(
        <ProtocolReminderInput>[
          // Both Protocols plan 09:00; the reminders-on one is unfilled.
          _input('trt', today, '09:00', protocolId: 'daily'),
          _input('trt', today, '09:00',
              protocolId: 'quiet', remindersEnabled: false),
          // Only the reminders-off Protocol plans 21:00.
          _input('magnesium', today, '21:00',
              protocolId: 'quiet', remindersEnabled: false),
          // 13:00: the reminders-on dose is filled, the other is off.
          _input('creatine', today, '13:00', protocolId: 'daily', filled: true),
          _input('creatine', today, '13:00',
              protocolId: 'quiet', remindersEnabled: false),
        ],
        at(2026, 10, 28, 8),
      );

      expect(desired.reminders.map((r) => r.localTime), <String>['09:00']);
    });

    // Untimed planned doses never reach `desiredReminders`: an input always
    // has a time, and `reminderInputs` leaves untimed doses out. That, and
    // its off-cycle and paused filtering, is tested against the repository
    // in protocol_reminder_scheduler_test.dart.

    test('times already past get no reminder', () {
      final desired = desiredReminders(
        <ProtocolReminderInput>[
          _input('trt', today, '09:00'),
          _input('creatine', today, '17:00'),
          _input('trt', today.addDays(1), '09:00'),
        ],
        at(2026, 10, 28, 9),
      );

      expect(
        desired.reminders.map((r) => (r.localDate, r.localTime)),
        <(ProtocolDayDate, String)>[
          (today, '17:00'),
          (today.addDays(1), '09:00'),
        ],
      );
    });
  });

  group('horizon', () {
    List<ProtocolReminderInput> perDay(List<String> times, int days) {
      return <ProtocolReminderInput>[
        for (var day = 0; day < days; day += 1)
          for (final time in times) _input('c-$time', today.addDays(day), time),
      ];
    }

    test('runs 14 days when the cap allows', () {
      final desired = desiredReminders(
        perDay(<String>['09:00'], 20),
        at(2026, 10, 28, 8),
      );

      expect(desired.reminders, hasLength(14));
      expect(desired.horizonEnd, today.addDays(13));
      expect(desired.reminders.last.localDate, today.addDays(13));
    });

    test('CUJ 11: a cap that falls mid-day ends the horizon the day before',
        () {
      // Five times a day: nine days are 45; the tenth would make 50.
      final desired = desiredReminders(
        perDay(<String>['07:00', '09:00', '13:00', '17:00', '21:00'], 14),
        at(2026, 10, 28, 6),
      );

      expect(desired.reminders, hasLength(45));
      expect(desired.horizonEnd, today.addDays(8));
      expect(
        desired.reminders.every(
          (r) => r.localDate.compareTo(today.addDays(8)) <= 0,
        ),
        isTrue,
      );
    });

    test('a total exactly at the cap still adds the day', () {
      // Four a day: twelve days are exactly 48.
      final desired = desiredReminders(
        perDay(<String>['07:00', '09:00', '13:00', '21:00'], 14),
        at(2026, 10, 28, 6),
      );

      expect(desired.reminders, hasLength(48));
      expect(desired.horizonEnd, today.addDays(11));
    });

    test('a past time doesn\'t count against the cap', () {
      // At 10:00, today keeps only its 13:00 and 21:00.
      final desired = desiredReminders(
        perDay(<String>['07:00', '09:00', '13:00', '21:00'], 3),
        at(2026, 10, 28, 10),
        cap: 6,
      );

      expect(desired.reminders, hasLength(6));
      expect(desired.horizonEnd, today.addDays(1));
    });

    test('today alone over the cap schedules nothing, through yesterday', () {
      final desired = desiredReminders(
        perDay(<String>['09:00', '13:00', '21:00'], 1),
        at(2026, 10, 28, 6),
        cap: 2,
      );

      expect(desired.reminders, isEmpty);
      expect(desired.horizonEnd, today.addDays(-1));
    });
  });

  group('ids', () {
    test('follow -(days since 2000-01-01 * 1440 + minute of day) - 1', () {
      const epoch = ProtocolDayDate(year: 2000, month: 1, day: 1);
      expect(protocolReminderId(epoch, '00:00'), -1);
      expect(protocolReminderId(epoch, '00:01'), -2);
      expect(protocolReminderId(epoch, '23:59'), -1440);
      expect(protocolReminderId(epoch.addDays(1), '00:00'), -1441);
      // 2026-10-28 is 9797 days after 2000-01-01.
      expect(protocolReminderId(today, '09:00'), -(9797 * 1440 + 540) - 1);
      expect(protocolReminderId(today, '09:00'), -14108221);
    });

    test('are distinct for every date and minute, and a negative int32 for '
        'every date before 6000', () {
      const lastDate = ProtocolDayDate(year: 5999, month: 12, day: 31);
      final last = protocolReminderId(lastDate, '23:59');
      expect(last, lessThan(0));
      expect(last, greaterThanOrEqualTo(-0x80000000));

      final ids = <int>{};
      for (var day = 0; day < 3; day += 1) {
        for (var minute = 0; minute < 1440; minute += 1) {
          final time = planLocalTime(minute ~/ 60, minute % 60);
          final id = protocolReminderId(today.addDays(day), time);
          expect(id, lessThan(0));
          ids.add(id);
        }
      }
      expect(ids, hasLength(3 * 1440));
    });
  });

  group('daylight-saving change days', () {
    test('a time the spring change skips fires at the first minute after '
        'the gap', () {
      const springForward = ProtocolDayDate(year: 2026, month: 3, day: 8);
      final desired = desiredReminders(
        <ProtocolReminderInput>[
          _input('a', springForward, '02:30'),
          _input('b', springForward, '09:00'),
        ],
        at(2026, 3, 8, 0, 30),
      );

      expect(desired.reminders, hasLength(2));
      final gap = desired.reminders.first;
      expect(gap.localTime, '02:30');
      expect(gap.id, protocolReminderId(springForward, '02:30'));
      // 03:00 EDT, the first valid minute after 02:00-03:00.
      expect(gap.scheduledAt.toUtc(), DateTime.utc(2026, 3, 8, 7));
      expect((gap.scheduledAt.hour, gap.scheduledAt.minute), (3, 0));
      expect(
        desired.reminders.last.scheduledAt.toUtc(),
        DateTime.utc(2026, 3, 8, 13),
      );
    });

    test('the gap rule holds east of UTC too', () {
      final lisbon = tz.getLocation('Europe/Lisbon');
      const springForward = ProtocolDayDate(year: 2026, month: 3, day: 29);
      final desired = desiredReminders(
        <ProtocolReminderInput>[_input('a', springForward, '01:30')],
        tz.TZDateTime(lisbon, 2026, 3, 29, 0, 10),
      );

      // 01:00-02:00 is skipped; 02:00 WEST is 01:00 UTC.
      expect(
        desired.reminders.single.scheduledAt.toUtc(),
        DateTime.utc(2026, 3, 29, 1),
      );
      expect(
        protocolReminderInstant(
          tz.getLocation('Australia/Sydney'),
          const ProtocolDayDate(year: 2026, month: 10, day: 4),
          '02:15',
        ).toUtc(),
        // Sydney skips 02:00-03:00 on 2026-10-04: 03:00 AEDT is 16:00 UTC.
        DateTime.utc(2026, 10, 3, 16),
      );
    });

    test('a time the autumn change repeats fires once, at its first '
        'occurrence', () {
      const fallBack = ProtocolDayDate(year: 2026, month: 11, day: 1);
      final desired = desiredReminders(
        <ProtocolReminderInput>[_input('a', fallBack, '01:30')],
        at(2026, 11, 1, 0),
      );

      expect(desired.reminders, hasLength(1));
      // 01:30 EDT (UTC-4), not 01:30 EST an hour later.
      expect(
        desired.reminders.single.scheduledAt.toUtc(),
        DateTime.utc(2026, 11, 1, 5, 30),
      );
    });

    test('a repeated time already past at its first occurrence gets no '
        'second reminder', () {
      const fallBack = ProtocolDayDate(year: 2026, month: 11, day: 1);
      // 01:45 EST, the second 01:45 of the day (06:45 UTC).
      final now = tz.TZDateTime.from(DateTime.utc(2026, 11, 1, 6, 45), newYork);
      final desired = desiredReminders(
        <ProtocolReminderInput>[_input('a', fallBack, '01:30')],
        now,
      );

      expect(desired.reminders, isEmpty);
    });

    test('a change day still counts as one whole day of the horizon', () {
      const fallBack = ProtocolDayDate(year: 2026, month: 11, day: 1);
      final desired = desiredReminders(
        <ProtocolReminderInput>[
          for (var day = -1; day < 3; day += 1)
            _input('trt', fallBack.addDays(day), '09:00'),
        ],
        at(2026, 10, 31, 8),
        horizonDays: 3,
      );

      expect(
        desired.reminders.map((r) => r.scheduledAt.toUtc()),
        <DateTime>[
          DateTime.utc(2026, 10, 31, 13),
          DateTime.utc(2026, 11, 1, 14),
          DateTime.utc(2026, 11, 2, 14),
        ],
      );
      expect(desired.horizonEnd, fallBack.addDays(1));
    });
  });
}

ProtocolReminderInput _input(
  String compoundId,
  ProtocolDayDate localDate,
  String localTime, {
  String protocolId = 'daily',
  bool remindersEnabled = true,
  bool filled = false,
}) {
  return ProtocolReminderInput(
    protocolId: protocolId,
    compoundId: compoundId,
    localDate: localDate,
    localTime: localTime,
    remindersEnabled: remindersEnabled,
    filled: filled,
  );
}

ScheduleRule _dailyAt(String time) => TimedScheduleRule(
      days: const DailyScheduleDays(),
      times: <String>[time],
    );

/// A fixture for `desiredReminders`: each timed planned dose the core plans
/// on dates with no Doses, unfilled, as `reminderInputs` builds them. It is
/// not the repository read, which is tested over in-memory SQLite in
/// protocol_reminder_scheduler_test.dart.
List<ProtocolReminderInput> _futureInputs(
  List<PlanProtocol> protocols,
  ProtocolDayDate from,
  int days,
) {
  final enabled = <String, bool>{
    for (final protocol in protocols)
      protocol.protocolId: protocol.remindersEnabled,
  };
  return <ProtocolReminderInput>[
    for (final day in planDays(protocols, from, from.addDays(days - 1)))
      if (day.state == PlanDayState.planned)
        for (final dose in day.planned)
          if (dose.localTime != null)
            ProtocolReminderInput(
              protocolId: day.protocolId,
              compoundId: day.compoundId,
              localDate: day.localDate,
              localTime: dose.localTime!,
              remindersEnabled: enabled[day.protocolId]!,
              filled: false,
            ),
  ];
}
