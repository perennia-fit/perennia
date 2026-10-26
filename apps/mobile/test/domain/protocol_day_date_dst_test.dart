import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/protocols/protocol_plan.dart';
import 'package:perennia/domain/protocols/protocol_plan_days.dart';
import 'package:perennia/domain/protocols/protocols.dart';

/// [ProtocolDayDate] arithmetic across both daylight-saving changes
/// (docs/designs/protocol-schedules-and-reminders.md, file 6). A local day is
/// 23 or 25 hours long on a change, so arithmetic on local `DateTime`s
/// repeats a date in autumn and skips one in spring; the arithmetic runs in
/// UTC so it cannot.
///
/// The bug only shows in a zone that changes its clocks, and a test process
/// cannot change its own zone, so the assertions below run in this process
/// and again in one child `flutter test` per zone, each started with the
/// `TZ` environment variable set:
///
/// * `America/Sao_Paulo` kept daylight saving until 2019, and changed at
///   midnight: 2018-11-04 had no 00:00, and 2019-02-16 had two 23:00s.
/// * `Europe/Lisbon` changes at 01:00 UTC: 2026-03-29 and 2026-10-25.
///
/// Each child first proves its zone took effect, so a platform that ignored
/// `TZ` would fail here rather than pass without testing anything.
const List<String> _zones = <String>['America/Sao_Paulo', 'Europe/Lisbon'];

/// Set on a child process to the zone it was started in.
const String _childZoneVariable = 'PERENNIA_DST_TEST_ZONE';

const String _thisFile = 'test/domain/protocol_day_date_dst_test.dart';

void main() {
  final childZone = Platform.environment[_childZoneVariable];

  group('ProtocolDayDate across daylight-saving changes '
      '(TZ=${Platform.environment['TZ'] ?? 'unset'})', () {
    if (childZone != null) {
      test('the process runs in $childZone', () {
        expect(
          _offsetsAcrossTheYear(),
          _expectedOffsets[childZone],
          reason: 'TZ=$childZone did not take effect in this process.',
        );
      });
    }

    for (final change in _changes) {
      test('addDays(1) walks every date across ${change.name}', () {
        expect(
          _walk(change.from, change.dates.length, step: 1),
          change.dates,
        );
      });

      test('addDays(-1) walks every date back across ${change.name}', () {
        expect(
          _walk(change.dates.last, change.dates.length, step: -1),
          change.dates.reversed.toList(),
        );
      });

      test('daysBetween and addDays agree across ${change.name}', () {
        final first = ProtocolDayDate.parse(change.from);
        for (var index = 0; index < change.dates.length; index += 1) {
          final other = ProtocolDayDate.parse(change.dates[index]);
          expect(other.daysBetween(first), index, reason: change.dates[index]);
          expect(first.daysBetween(other), -index, reason: change.dates[index]);
          expect(first.addDays(index), other, reason: change.dates[index]);
        }
      });

      test('planDays plans each date once across ${change.name}', () {
        // planDays walks with addDays(1), so a date that repeats would loop it
        // forever. Fail here instead of hanging the run.
        expect(
          _walk(change.from, change.dates.length, step: 1),
          change.dates,
          reason: 'addDays(1) does not advance one date at a time.',
        );
        final from = ProtocolDayDate.parse(change.from);
        final to = ProtocolDayDate.parse(change.dates.last);
        final days = planDays(
          <PlanProtocol>[
            PlanProtocol(
              protocolId: 'protocol-daily',
              startLocalDate: from,
              members: <PlanMember>[
                PlanMember(
                  memberId: 'member-x',
                  compoundId: 'compound-x',
                  versions: <ScheduleVersion>[
                    ScheduleVersion(
                      id: 'ver-x-1',
                      effectiveFrom: from,
                      rule: TimedScheduleRule(
                        days: const DailyScheduleDays(),
                        times: const <String>['02:30'],
                      ),
                      amountValue: 1,
                      amountEntered: '1',
                      unit: DoseUnit.capsule,
                      route: DoseRoute.oral,
                    ),
                  ],
                ),
              ],
            ),
          ],
          from,
          to,
        );
        expect(
          days.map((day) => day.localDate.storageValue).toList(),
          change.dates,
        );
        expect(
          days.every((day) => day.state == PlanDayState.planned),
          isTrue,
        );
      });
    }

    test('isoWeekday is the calendar weekday on a change day', () {
      expect(ProtocolDayDate.parse('2018-11-04').isoWeekday, 7);
      expect(ProtocolDayDate.parse('2019-02-17').isoWeekday, 7);
      expect(ProtocolDayDate.parse('2026-03-29').isoWeekday, 7);
      expect(ProtocolDayDate.parse('2026-03-30').isoWeekday, 1);
      expect(ProtocolDayDate.parse('2026-10-25').isoWeekday, 7);
      expect(ProtocolDayDate.parse('2026-10-26').isoWeekday, 1);
    });

    test('daysBetween spans a whole year with both changes', () {
      expect(
        ProtocolDayDate.parse('2027-01-01')
            .daysBetween(ProtocolDayDate.parse('2026-01-01')),
        365,
      );
      expect(
        ProtocolDayDate.parse('2026-01-01').addDays(365),
        ProtocolDayDate.parse('2027-01-01'),
      );
    });
  });

  if (childZone == null) {
    group('in each zone with daylight saving', () {
      for (final zone in _zones) {
        test(
          'TZ=$zone',
          () async {
            final result = await Process.run(
              'flutter',
              <String>['test', '--no-pub', _thisFile],
              environment: <String, String>{
                'TZ': zone,
                _childZoneVariable: zone,
              },
              runInShell: Platform.isWindows,
            );
            expect(
              result.exitCode,
              0,
              reason: 'flutter test $_thisFile failed under TZ=$zone:\n'
                  '${result.stdout}\n${result.stderr}',
            );
          },
          timeout: const Timeout(Duration(minutes: 5)),
        );
      }
    });
  }
}

/// A run of consecutive calendar dates that crosses one change.
typedef _Change = ({String name, String from, List<String> dates});

final List<_Change> _changes = <_Change>[
  (
    name: 'São Paulo spring forward at midnight (2018-11-04)',
    from: '2018-11-01',
    dates: _consecutive('2018-11', 1, 7),
  ),
  (
    name: 'São Paulo fall back at midnight (2019-02-17)',
    from: '2019-02-14',
    dates: _consecutive('2019-02', 14, 20),
  ),
  (
    name: 'Lisbon spring forward (2026-03-29)',
    from: '2026-03-26',
    dates: <String>[
      ..._consecutive('2026-03', 26, 31),
      ..._consecutive('2026-04', 1, 2),
    ],
  ),
  (
    name: 'Lisbon fall back (2026-10-25)',
    from: '2026-10-22',
    dates: _consecutive('2026-10', 22, 28),
  ),
];

List<String> _consecutive(String yearMonth, int firstDay, int lastDay) {
  return <String>[
    for (var day = firstDay; day <= lastDay; day += 1)
      '$yearMonth-${day.toString().padLeft(2, '0')}',
  ];
}

List<String> _walk(String start, int count, {required int step}) {
  final dates = <String>[];
  var date = ProtocolDayDate.parse(start);
  for (var index = 0; index < count; index += 1) {
    dates.add(date.storageValue);
    date = date.addDays(step);
  }
  return dates;
}

/// The process zone's UTC offsets, in minutes, on a winter and a summer day
/// of each zone's daylight-saving years.
List<int> _offsetsAcrossTheYear() {
  return <DateTime>[
    DateTime(2019, 1, 15, 12),
    DateTime(2019, 7, 15, 12),
    DateTime(2026, 1, 15, 12),
    DateTime(2026, 7, 15, 12),
  ].map((moment) => moment.timeZoneOffset.inMinutes).toList();
}

const Map<String, List<int>> _expectedOffsets = <String, List<int>>{
  // Summer time (UTC-2) in January 2019; none since 2019.
  'America/Sao_Paulo': <int>[-120, -180, -180, -180],
  'Europe/Lisbon': <int>[0, 60, 0, 60],
};
