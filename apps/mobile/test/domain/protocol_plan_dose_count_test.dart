import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/protocols/protocol_plan.dart';
import 'package:perennia/domain/protocols/protocol_plan_days.dart';
import 'package:perennia/domain/protocols/protocols.dart';

/// The "N doses" helper (docs/designs/protocol-schedules-and-reminders.md,
/// D6): the date of a member's Nth planned dose from the Protocol's start,
/// which the editor stores as the Protocol's end date. Dart only, so it has
/// no golden vector.
void main() {
  ProtocolDayDate date(String value) => ProtocolDayDate.parse(value);

  TimedScheduleRule timed(List<String> times, {ScheduleDays? days}) =>
      TimedScheduleRule(days: days ?? const DailyScheduleDays(), times: times);

  ProtocolDayDate? endDate(
    String start,
    ScheduleRule rule,
    int doseCount, {
    ProtocolPeriod? period,
  }) {
    return endDateForDoseCount(
      startLocalDate: date(start),
      rule: rule,
      doseCount: doseCount,
      period: period,
    );
  }

  group('endDateForDoseCount', () {
    test('CUJ 4: 20 doses at 21:00 daily from 2026-10-26 end on 2026-11-14',
        () {
      expect(endDate('2026-10-26', timed(['21:00']), 20), date('2026-11-14'));
    });

    test('it counts doses, not days: 08:00 and 20:00 reach 20 on day 10', () {
      expect(
        endDate('2026-10-01', timed(['08:00', '20:00']), 20),
        date('2026-10-10'),
      );
      // An odd count ends on the day its first dose falls.
      expect(
        endDate('2026-10-01', timed(['08:00', '20:00']), 19),
        date('2026-10-10'),
      );
    });

    test('an untimed count counts like any other planned dose', () {
      expect(
        endDate(
          '2026-10-01',
          const UntimedScheduleRule(days: DailyScheduleDays(), count: 3),
          7,
        ),
        date('2026-10-03'),
      );
    });

    test('a single dose ends on the start date', () {
      expect(endDate('2026-10-26', timed(['21:00']), 1), date('2026-10-26'));
    });

    test('only the rule days count', () {
      // Monday, Wednesday and Friday from Monday 2026-10-19: the 4th dose is
      // the next Monday.
      expect(
        endDate(
          '2026-10-19',
          timed(['07:00'], days: WeekdayScheduleDays([1, 3, 5])),
          4,
        ),
        date('2026-10-26'),
      );
      // Every 3 days from an anchor before the start: 2026-10-02 is day 2,
      // so the first dose is 2026-10-03 (day 3) and the third 2026-10-09.
      expect(
        endDate(
          '2026-10-02',
          timed(
            ['08:00'],
            days: EveryNDaysScheduleDays(
              n: 3,
              anchor: date('2026-09-30'),
              anchorIsDefault: false,
            ),
          ),
          3,
        ),
        date('2026-10-09'),
      );
    });

    test('off-cycle days are skipped', () {
      // 3 on / 2 off from the start: doses on 09-01..03, 09-06..08, 09-11.
      final period = ProtocolPeriod(
        cycle: ProtocolCycle(
          onDays: 3,
          offDays: 2,
          anchor: date('2026-09-01'),
          anchorIsDefault: true,
        ),
      );
      expect(
        endDate('2026-09-01', timed(['21:00']), 7, period: period),
        date('2026-09-11'),
      );
    });

    test('a cycle anchored before the start counts from its anchor', () {
      // 2026-09-01 is cycle day 2 (on); days 3-4 are off; 09-04 is day 0.
      final period = ProtocolPeriod(
        cycle: ProtocolCycle(
          onDays: 3,
          offDays: 2,
          anchor: date('2026-08-30'),
          anchorIsDefault: false,
        ),
      );
      expect(
        endDate('2026-09-01', timed(['21:00']), 4, period: period),
        date('2026-09-06'),
      );
    });

    test('paused days are skipped, and a Pause does not shift the cycle', () {
      final pauseOnly = ProtocolPeriod(
        pauses: [
          ProtocolPause(from: date('2026-10-03'), to: date('2026-10-05')),
        ],
      );
      expect(
        endDate('2026-10-01', timed(['21:00']), 5, period: pauseOnly),
        date('2026-10-08'),
      );

      // 3 on / 2 off from 09-01 with 09-02 paused: doses on 09-01, 09-03,
      // then the next on-period 09-06..08.
      final cycleAndPause = ProtocolPeriod(
        cycle: ProtocolCycle(
          onDays: 3,
          offDays: 2,
          anchor: date('2026-09-01'),
          anchorIsDefault: true,
        ),
        pauses: [
          ProtocolPause(from: date('2026-09-02'), to: date('2026-09-02')),
        ],
      );
      expect(
        endDate('2026-09-01', timed(['21:00']), 3, period: cycleAndPause),
        date('2026-09-06'),
      );
    });

    test('a Pause far after the doses run out changes nothing', () {
      final period = ProtocolPeriod(
        pauses: [
          ProtocolPause(from: date('2027-06-01'), to: date('2027-06-30')),
        ],
      );
      expect(
        endDate('2026-10-26', timed(['21:00']), 20, period: period),
        date('2026-11-14'),
      );
    });

    test('long rules finish without walking every day', () {
      expect(endDate('2026-01-01', timed(['09:00']), 1000), date('2028-09-26'));
      expect(
        endDate(
          '2026-01-01',
          timed(
            ['09:00'],
            days: EveryNDaysScheduleDays(
              n: 365,
              anchor: date('2026-01-01'),
              anchorIsDefault: true,
            ),
          ),
          1000,
        ),
        date('3024-05-04'),
      );
    });

    test('as_needed and unscheduled rules are unavailable', () {
      expect(endDate('2026-10-26', const AsNeededScheduleRule(), 20), isNull);
      expect(
        endDate('2026-10-26', const UnscheduledScheduleRule(), 20),
        isNull,
      );
    });

    test('a rule whose days never fall on an on-cycle day is unavailable', () {
      // Cycle on-days are even offsets from 09-01; every 2 days from 09-02
      // plans only odd offsets.
      final period = ProtocolPeriod(
        cycle: ProtocolCycle(
          onDays: 1,
          offDays: 1,
          anchor: date('2026-09-01'),
          anchorIsDefault: true,
        ),
      );
      final rule = timed(
        ['09:00'],
        days: EveryNDaysScheduleDays(
          n: 2,
          anchor: date('2026-09-02'),
          anchorIsDefault: false,
        ),
      );
      expect(endDate('2026-09-01', rule, 5, period: period), isNull);
    });

    test('a rule that is never on is unavailable however far a Pause reaches',
        () {
      // On Tuesdays only (anchored on Tuesday 2026-01-06), but the rule plans
      // Mondays; the Pause near the last date must not be walked day by day.
      final period = ProtocolPeriod(
        cycle: ProtocolCycle(
          onDays: 1,
          offDays: 6,
          anchor: date('2026-01-06'),
          anchorIsDefault: false,
        ),
        pauses: [
          ProtocolPause(from: date('9999-12-30'), to: date('9999-12-31')),
        ],
      );
      final rule = timed(['09:00'], days: WeekdayScheduleDays(const [1]));
      expect(endDate('2026-01-01', rule, 20, period: period), isNull);
    });

    test('an every-365-days rule on a decade-long cycle skips its off years',
        () {
      // 3650 on / 3649 off repeats with every 365 days only every 2,664,135
      // days. Doses 1-10 fall in the first on-period (day 0 to 3285), and
      // doses 11-20 in the second (day 7300 to 10585). Checked by brute force.
      final period = ProtocolPeriod(
        cycle: ProtocolCycle(
          onDays: 3650,
          offDays: 3649,
          anchor: date('2026-01-01'),
          anchorIsDefault: true,
        ),
      );
      final rule = timed(
        ['09:00'],
        days: EveryNDaysScheduleDays(
          n: 365,
          anchor: date('2026-01-01'),
          anchorIsDefault: true,
        ),
      );
      expect(
        endDate('2026-01-01', rule, 11, period: period),
        date('2045-12-27'),
      );
      expect(
        endDate('2026-01-01', rule, 20, period: period),
        date('2054-12-25'),
      );
      expect(
        endDate('2026-01-01', rule, 1000, period: period),
        date('4013-09-06'),
      );
    });

    test('a dose after 9999-12-31 is unavailable', () {
      // One dose every 3650 days: the 1000th would fall near year 12000.
      final period = ProtocolPeriod(
        cycle: ProtocolCycle(
          onDays: 1,
          offDays: 3649,
          anchor: date('2026-01-01'),
          anchorIsDefault: true,
        ),
      );
      final rule = timed(
        ['09:00'],
        days: EveryNDaysScheduleDays(
          n: 365,
          anchor: date('2026-01-01'),
          anchorIsDefault: true,
        ),
      );
      expect(
          endDate('2026-01-01', rule, 2, period: period), date('2035-12-30'));
      expect(endDate('2026-01-01', rule, 1000, period: period), isNull);
    });

    test('a doseCount outside 1-1000 is rejected', () {
      expect(
        () => endDate('2026-10-26', timed(['21:00']), 0),
        throwsRangeError,
      );
      expect(
        () => endDate('2026-10-26', timed(['21:00']), 1001),
        throwsRangeError,
      );
      expect(
        () => endDate('2026-10-26', timed(['21:00']), -5),
        throwsRangeError,
      );
    });
  });
}
