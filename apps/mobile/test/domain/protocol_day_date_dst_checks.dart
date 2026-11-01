/// The checks behind `protocol_day_date_dst_test.dart`, in plain Dart, so the
/// test can run them in its own process and, as a script, in one child Dart
/// VM per zone (`dart protocol_day_date_dst_checks.dart`, with `TZ` and
/// [childZoneVariable] set). Each check returns its failures; none is a pass.
///
/// The code under test (`protocols.dart`, `protocol_plan.dart`,
/// `protocol_plan_days.dart`, and `training_day.dart` for
/// [TrainingDayDate.addDays], which the training progress cores walk dates
/// with) imports nothing from Flutter, which is what lets
/// the child be a bare Dart VM: it builds nothing, so the zones run at once
/// without two `flutter test` runs colliding over the native-assets build.
library;

import 'dart:io';

import 'package:perennia/domain/protocols/protocol_plan.dart';
import 'package:perennia/domain/protocols/protocol_plan_days.dart';
import 'package:perennia/domain/protocols/protocols.dart';
import 'package:perennia/domain/training/training_day.dart';

/// The zones with daylight saving each child runs in:
///
/// * `America/Sao_Paulo` kept daylight saving until 2019, and changed at
///   midnight: 2018-11-04 had no 00:00, and 2019-02-16 had two 23:00s.
/// * `Europe/Lisbon` changes at 01:00 UTC: 2026-03-29 and 2026-10-25.
const List<String> dstZones = <String>['America/Sao_Paulo', 'Europe/Lisbon'];

/// Set on a child process to the zone it was started in.
const String childZoneVariable = 'PERENNIA_DST_TEST_ZONE';

/// One named check: its failures, or none.
typedef DstCheck = ({String name, List<String> Function() run});

/// Every check, and first, when [zone] is set, the proof that the process
/// runs in it, so a platform that ignored `TZ` fails rather than passing
/// without testing anything.
List<DstCheck> dstChecks({String? zone}) {
  return <DstCheck>[
    if (zone != null)
      (
        name: 'the process runs in $zone',
        run: () => _equal(
              _offsetsAcrossTheYear(),
              _expectedOffsets[zone],
              'TZ=$zone did not take effect in this process; UTC offsets',
            ),
      ),
    for (final change in _changes) ...<DstCheck>[
      (
        name: 'addDays(1) walks every date across ${change.name}',
        run: () => _equal(
              _walk(change.from, change.dates.length, step: 1),
              change.dates,
              'dates',
            ),
      ),
      (
        name: 'addDays(-1) walks every date back across ${change.name}',
        run: () => _equal(
              _walk(change.dates.last, change.dates.length, step: -1),
              change.dates.reversed.toList(),
              'dates',
            ),
      ),
      (
        name: 'TrainingDayDate.addDays walks every date both ways across '
            '${change.name}',
        run: () => <String>[
              ..._equal(
                _walkTraining(change.from, change.dates.length, step: 1),
                change.dates,
                'dates',
              ),
              ..._equal(
                _walkTraining(change.dates.last, change.dates.length,
                    step: -1),
                change.dates.reversed.toList(),
                'dates back',
              ),
            ],
      ),
      (
        name: 'daysBetween and addDays agree across ${change.name}',
        run: () {
          final first = ProtocolDayDate.parse(change.from);
          return <String>[
            for (var index = 0; index < change.dates.length; index += 1)
              ...() {
                final date = change.dates[index];
                final other = ProtocolDayDate.parse(date);
                return <String>[
                  ..._equal(
                      other.daysBetween(first), index, '$date daysBetween'),
                  ..._equal(first.daysBetween(other), -index, '$date back'),
                  ..._equal(first.addDays(index), other, '$date addDays'),
                ];
              }(),
          ];
        },
      ),
      (
        name: 'planDays plans each date once across ${change.name}',
        run: () => _plansEachDateOnce(change),
      ),
    ],
    (
      name: 'isoWeekday is the calendar weekday on a change day',
      run: () => <String>[
            for (final (date, weekday) in const <(String, int)>[
              ('2018-11-04', 7),
              ('2019-02-17', 7),
              ('2026-03-29', 7),
              ('2026-03-30', 1),
              ('2026-10-25', 7),
              ('2026-10-26', 1),
            ])
              ..._equal(
                ProtocolDayDate.parse(date).isoWeekday,
                weekday,
                '$date isoWeekday',
              ),
          ],
    ),
    (
      name: 'daysBetween spans a whole year with both changes',
      run: () => <String>[
            ..._equal(
              ProtocolDayDate.parse('2027-01-01')
                  .daysBetween(ProtocolDayDate.parse('2026-01-01')),
              365,
              'days in 2026',
            ),
            ..._equal(
              ProtocolDayDate.parse('2026-01-01').addDays(365),
              ProtocolDayDate.parse('2027-01-01'),
              '2026-01-01 + 365 days',
            ),
          ],
    ),
  ];
}

/// Run as a child: every check in the zone [childZoneVariable] names, each
/// failure on stderr, and a non-zero exit code when any fails.
void main() {
  final zone = Platform.environment[childZoneVariable];
  var failed = 0;
  for (final check in dstChecks(zone: zone)) {
    final failures = check.run();
    if (failures.isNotEmpty) {
      failed += 1;
      stderr.writeln('FAILED: ${check.name}');
      for (final failure in failures) {
        stderr.writeln('  $failure');
      }
    }
  }
  stdout.writeln(
      'TZ=$zone: ${failed == 0 ? 'all checks passed' : '$failed failed'}');
  exitCode = failed == 0 ? 0 : 1;
}

List<String> _plansEachDateOnce(_Change change) {
  // planDays walks with addDays(1), so a date that repeats would loop it
  // forever. Fail here instead of hanging the run.
  final walked = _equal(
    _walk(change.from, change.dates.length, step: 1),
    change.dates,
    'addDays(1) does not advance one date at a time; dates',
  );
  if (walked.isNotEmpty) {
    return walked;
  }
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
                amount: const PlanAmount(
                  amountValue: 1,
                  amountEntered: '1',
                  unit: DoseUnit.capsule,
                  route: DoseRoute.oral,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
    from,
    to,
  );
  return <String>[
    ..._equal(
      days.map((day) => day.localDate.storageValue).toList(),
      change.dates,
      'planned dates',
    ),
    ..._equal(
      days.every((day) => day.state == PlanDayState.planned),
      true,
      'every date planned',
    ),
  ];
}

/// No failure when [actual] equals [expected] (lists element by element),
/// else one naming [what].
List<String> _equal(Object? actual, Object? expected, String what) {
  final same = actual is List && expected is List
      ? actual.length == expected.length &&
          Iterable<int>.generate(actual.length)
              .every((index) => actual[index] == expected[index])
      : actual == expected;
  return same
      ? const <String>[]
      : <String>['$what: expected $expected, got $actual'];
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

List<String> _walkTraining(String start, int count, {required int step}) {
  final dates = <String>[];
  var date = TrainingDayDate.parse(start);
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
