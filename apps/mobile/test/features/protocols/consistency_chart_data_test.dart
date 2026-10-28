import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/protocols/protocol_plan_days.dart';
import 'package:perennia/features/protocols/models/consistency_chart_data.dart';

void main() {
  group('ConsistencyChartData', () {
    test(
        'the planned line moves from 09:00 to 07:00 on the day a new '
        'Schedule Version applies (CUJ 6)', () {
      final protocol = PlanProtocol(
        protocolId: 'p-daily',
        startLocalDate: _date(2026, 9, 1),
        members: <PlanMember>[
          PlanMember(
            memberId: 'm-trt',
            compoundId: 'c-trt',
            versions: <ScheduleVersion>[
              _version('v-1', _date(2026, 9, 1), _daily(<String>['09:00'])),
              _version(
                'v-2',
                _date(2026, 10, 19),
                TimedScheduleRule(
                  days: WeekdayScheduleDays(const <int>[1, 3, 5]),
                  times: const <String>['07:00'],
                ),
              ),
            ],
          ),
        ],
      );
      final from = _date(2026, 10, 12);
      final to = _date(2026, 10, 25);
      final data = _build(<PlanProtocol>[protocol], from, to);

      expect(data.dayCount, 14);
      expect(
        _segments(data),
        <(String, int, int)>[
          // Daily at 09:00 from Monday 12 October through Sunday 18th.
          ('09:00', 0, 6),
          // Then Monday, Wednesday and Friday at 07:00 from the 19th.
          ('07:00', 7, 7),
          ('07:00', 9, 9),
          ('07:00', 11, 11),
        ],
      );
      final nineAm = data.plannedSegments.first;
      expect(nineAm.y, 9 * 60);
      expect(nineAm.run.startX, 0);
      expect(nineAm.run.endX, 7);
      expect(data.plannedSegments[1].y, 7 * 60);
      expect(data.hasUntimedBand, isFalse);
      expect(data.maxY, ConsistencyChartData.minutesPerDay);
      expect(data.shades, isEmpty);
      // Nothing to shade on Tuesday the 20th: it is "Not planned", not a
      // break in the plan.
      final statuses = dayStatuses(
        planDays(<PlanProtocol>[protocol], from, to),
        const <PlanDose>[],
        to,
      );
      final tuesday =
          statuses.singleWhere((status) => status.localDate == from.addDays(8));
      expect(tuesday.status, DayStatusKind.notPlanned);
      expect(tuesday.notPlannedReason, NotPlannedReason.notScheduledToday);
    });

    test('two Protocols planning the same time on a day draw one segment', () {
      PlanProtocol protocol(String id) => PlanProtocol(
            protocolId: id,
            startLocalDate: _date(2026, 10, 1),
            members: <PlanMember>[
              PlanMember(
                memberId: 'm-$id',
                compoundId: 'c-creatine',
                versions: <ScheduleVersion>[
                  _version(
                    'v-$id',
                    _date(2026, 10, 1),
                    _daily(<String>['09:00']),
                  ),
                ],
              ),
            ],
          );
      final data = _build(
        <PlanProtocol>[protocol('p-a'), protocol('p-b')],
        _date(2026, 10, 1),
        _date(2026, 10, 5),
      );

      expect(_segments(data), <(String, int, int)>[('09:00', 0, 4)]);
    });

    test('untimed planned doses are a band along the top, labelled apart', () {
      final protocol = PlanProtocol(
        protocolId: 'p-night',
        startLocalDate: _date(2026, 10, 3),
        endLocalDate: _date(2026, 10, 6),
        members: <PlanMember>[
          PlanMember(
            memberId: 'm-mag',
            compoundId: 'c-mag',
            versions: <ScheduleVersion>[
              _version(
                'v-mag',
                _date(2026, 10, 3),
                UntimedScheduleRule(days: const DailyScheduleDays(), count: 2),
              ),
            ],
          ),
        ],
      );
      final data = _build(
        <PlanProtocol>[protocol],
        _date(2026, 10, 1),
        _date(2026, 10, 8),
      );

      expect(data.hasUntimedBand, isTrue);
      expect(data.maxY, ConsistencyChartData.untimedBandTop);
      expect(
        ConsistencyChartData.untimedBandY,
        greaterThan(ConsistencyChartData.minutesPerDay),
      );
      // The Protocol's dates are the 3rd to the 6th: one run, days 2 to 5.
      expect(
        data.untimedRuns,
        const <ConsistencyDayRun>[
          ConsistencyDayRun(startIndex: 2, endIndex: 5),
        ],
      );
      expect(data.plannedSegments, isEmpty);
    });

    test(
        'off-cycle days are shaded and stay apart from the on days around '
        'them (CUJ 3)', () {
      // GHK-Cu at 21:00 daily, 60 days on and 30 off from 1 September: cycle
      // day 60, the first off day, is 31 October.
      final protocol = _skin();
      final from = _date(2026, 10, 28);
      final to = _date(2026, 11, 5);
      final data = _build(<PlanProtocol>[protocol], from, to);

      expect(data.shades, hasLength(1));
      expect(data.shades.single.kind, DayStatusKind.offCycle);
      // From day 3, 31 October.
      expect(
        data.shades.single.run,
        const ConsistencyDayRun(startIndex: 3, endIndex: 8),
      );
      expect(from.addDays(3), _date(2026, 10, 31));
      expect(_segments(data), <(String, int, int)>[('21:00', 0, 2)]);
    });

    test(
        'paused days are shaded, and the cycle does not shift around the '
        'Pause (CUJ 5)', () {
      final protocol = _skin(
        pauses: <ProtocolPause>[
          ProtocolPause(from: _date(2026, 10, 10), to: _date(2026, 10, 16)),
        ],
      );
      final from = _date(2026, 10, 8);
      final to = _date(2026, 10, 18);
      final data = _build(<PlanProtocol>[protocol], from, to);

      expect(data.shades, hasLength(1));
      expect(data.shades.single.kind, DayStatusKind.paused);
      // The seven paused days, 10 to 16 October.
      expect(
        data.shades.single.run,
        const ConsistencyDayRun(startIndex: 2, endIndex: 8),
      );
      expect(data.shades.single.run.dayCount, 7);
      expect(
        _segments(data),
        <(String, int, int)>[('21:00', 0, 1), ('21:00', 9, 10)],
      );
    });

    test('a day after today has no Day Status, so it is never shaded', () {
      final protocol = _skin();
      final from = _date(2026, 10, 30);
      final to = _date(2026, 11, 2);
      final days = planDays(<PlanProtocol>[protocol], from, to);
      final data = ConsistencyChartData.build(
        from: from,
        to: to,
        planDays: days,
        dayStatuses: dayStatuses(days, const <PlanDose>[], _date(2026, 10, 31)),
        doses: const <DoseRecord>[],
        extraDoseIds: const <String>{},
      );

      // Only the 31st, today, reads "Off cycle"; the 1st and 2nd are after it.
      expect(
        data.shades.map((shade) => shade.run),
        const <ConsistencyDayRun>[
          ConsistencyDayRun(startIndex: 1, endIndex: 1),
        ],
      );
    });

    test(
        'each Dose is a point at its date and time; one that filled no slot '
        'is an extra', () {
      final protocol = PlanProtocol(
        protocolId: 'p-daily',
        startLocalDate: _date(2026, 10, 1),
        members: <PlanMember>[
          PlanMember(
            memberId: 'm-trt',
            compoundId: 'c-trt',
            versions: <ScheduleVersion>[
              _version('v-1', _date(2026, 10, 1), _daily(<String>['09:00'])),
            ],
          ),
        ],
      );
      final from = _date(2026, 10, 1);
      final to = _date(2026, 10, 3);
      final doses = <DoseRecord>[
        _dose('d-1', _date(2026, 10, 2), 9, 10),
        _dose('d-2', _date(2026, 10, 2), 21, 30),
        _dose('d-3', _date(2026, 10, 3), 8, 0),
        // Outside the range: never drawn.
        _dose('d-4', _date(2026, 10, 9), 9, 0),
      ];
      final data = _build(<PlanProtocol>[protocol], from, to, doses: doses);

      expect(
        data.points
            .map((point) => (point.dose.id, point.x, point.y, point.isExtra)),
        <(String, double, double, bool)>[
          ('d-1', 1.5, 9 * 60 + 10, false),
          ('d-2', 1.5, 21 * 60 + 30, true),
          ('d-3', 2.5, 8 * 60, false),
        ],
      );
    });

    test(
        'a Dose is drawn at its frozen local date and time, not at its '
        "instant in the device's zone", () {
      // Logged in Los Angeles (UTC-7) at 08:30 on 2 October: 15:30 UTC.
      final tookAt = DateTime.utc(2026, 10, 2, 15, 30);
      final abroad = DoseRecord(
        id: 'd-abroad',
        compoundId: 'c-trt',
        compoundName: 'TRT',
        amountValue: 1,
        amountEntered: '1',
        unit: DoseUnit.milligram,
        route: DoseRoute.oral,
        tookAt: tookAt,
        timezone: 'America/Los_Angeles',
        localDate: _date(2026, 10, 2),
        timezoneOffsetMinutes: -7 * 60,
        provenance: DoseProvenance.manual,
        updatedAt: tookAt,
      );
      final data = _build(
        const <PlanProtocol>[],
        _date(2026, 10, 1),
        _date(2026, 10, 3),
        doses: <DoseRecord>[abroad],
      );

      expect(
        data.points.map((point) => (point.x, point.y)),
        <(double, double)>[(1.5, 8 * 60 + 30)],
      );
    });

    test("planned segments end on the Protocol's end date", () {
      final protocol = PlanProtocol(
        protocolId: 'p-daily',
        startLocalDate: _date(2026, 10, 1),
        endLocalDate: _date(2026, 10, 4),
        members: <PlanMember>[
          PlanMember(
            memberId: 'm-trt',
            compoundId: 'c-trt',
            versions: <ScheduleVersion>[
              _version('v-1', _date(2026, 10, 1), _daily(<String>['09:00'])),
            ],
          ),
        ],
      );
      final data = _build(
        <PlanProtocol>[protocol],
        _date(2026, 9, 29),
        _date(2026, 10, 7),
      );

      // 1 to 4 October, both included: days 2 to 5. Nothing is shaded
      // outside the Protocol's dates: they are "Not planned".
      expect(_segments(data), <(String, int, int)>[('09:00', 2, 5)]);
      expect(data.shades, isEmpty);
    });

    test(
        'planned segments end on the day a member is removed, and on the day '
        'a Protocol is archived', () {
      PlanProtocol protocol({
        ProtocolDayDate? memberArchivedOn,
        ProtocolDayDate? protocolArchivedOn,
      }) =>
          PlanProtocol(
            protocolId: 'p-daily',
            startLocalDate: _date(2026, 10, 1),
            archivedOn: protocolArchivedOn,
            members: <PlanMember>[
              PlanMember(
                memberId: 'm-trt',
                compoundId: 'c-trt',
                archivedOn: memberArchivedOn,
                versions: <ScheduleVersion>[
                  _version(
                    'v-1',
                    _date(2026, 10, 1),
                    _daily(<String>['09:00', '21:00']),
                  ),
                ],
              ),
            ],
          );
      final from = _date(2026, 10, 1);
      final to = _date(2026, 10, 8);

      // Removed on the 3rd: the archive day itself is still planned (D1).
      final removed = _build(
        <PlanProtocol>[protocol(memberArchivedOn: _date(2026, 10, 3))],
        from,
        to,
      );
      expect(
        _segments(removed),
        <(String, int, int)>[('09:00', 0, 2), ('21:00', 0, 2)],
      );
      expect(removed.shades, isEmpty);

      final archived = _build(
        <PlanProtocol>[protocol(protocolArchivedOn: _date(2026, 10, 5))],
        from,
        to,
      );
      expect(
        _segments(archived),
        <(String, int, int)>[('09:00', 0, 4), ('21:00', 0, 4)],
      );
    });

    test(
        'a Dose is an extra exactly when the day list counts it as one: the '
        "chart reads the range's own extras", () {
      final protocol = PlanProtocol(
        protocolId: 'p-daily',
        startLocalDate: _date(2026, 10, 1),
        members: <PlanMember>[
          PlanMember(
            memberId: 'm-trt',
            compoundId: 'c-trt',
            versions: <ScheduleVersion>[
              _version('v-1', _date(2026, 10, 1), _daily(<String>['09:00'])),
            ],
          ),
        ],
      );
      final range = _range(
        <PlanProtocol>[protocol],
        _date(2026, 10, 1),
        _date(2026, 10, 2),
        <DoseRecord>[
          _dose('d-1', _date(2026, 10, 1), 9, 0),
          _dose('d-2', _date(2026, 10, 1), 9, 30),
          _dose('d-3', _date(2026, 10, 2), 22, 0),
        ],
      );
      final data = ConsistencyChartData.of(range);

      final listed = <String>{
        for (final day in range.days)
          for (final dose in day.extraDoses) dose.id,
      };
      expect(listed, <String>{'d-2'});
      expect(
        {
          for (final point in data.points)
            if (point.isExtra) point.dose.id,
        },
        listed,
      );
      // Built once per range: the same emission gives the same model.
      expect(identical(ConsistencyChartData.of(range), data), isTrue);
    });

    test(
        'a Compound in no Protocol has no PlanDays: its Doses are drawn, and '
        'none is an extra', () {
      final from = _date(2026, 10, 1);
      final to = _date(2026, 10, 2);
      final data = _build(
        const <PlanProtocol>[],
        from,
        to,
        doses: <DoseRecord>[
          _dose('d-1', from, 7, 0),
          _dose('d-2', from, 7, 30),
        ],
      );

      expect(data.points, hasLength(2));
      expect(data.points.every((point) => !point.isExtra), isTrue);
      expect(data.plannedSegments, isEmpty);
      expect(data.hasAnyData, isTrue);
    });

    test('an empty range has nothing to draw', () {
      final data = ConsistencyChartData.build(
        from: _date(2026, 10, 1),
        to: _date(2026, 10, 1),
        planDays: const <PlanDay>[],
        dayStatuses: const <DayStatus>[],
        doses: const <DoseRecord>[],
        extraDoseIds: const <String>{},
      );

      expect(data.hasAnyData, isFalse);
      expect(data.dayCount, 1);
    });

    test('a range that ends before it starts throws', () {
      expect(
        () => ConsistencyChartData.build(
          from: _date(2026, 10, 2),
          to: _date(2026, 10, 1),
          planDays: const <PlanDay>[],
          dayStatuses: const <DayStatus>[],
          doses: const <DoseRecord>[],
          extraDoseIds: const <String>{},
        ),
        throwsArgumentError,
      );
    });
  });
}

/// The chart of [protocols] over [from] through [to], with today on [to],
/// built as the screen builds it: from the range the repository would emit,
/// so its extras are the day list's.
ConsistencyChartData _build(
  List<PlanProtocol> protocols,
  ProtocolDayDate from,
  ProtocolDayDate to, {
  List<DoseRecord> doses = const <DoseRecord>[],
}) {
  return ConsistencyChartData.of(_range(protocols, from, to, doses));
}

/// One Compound's Consistency read over [from] through [to], with today on
/// [to]. Each Dose is numbered among its date's Doses, as matching does.
ConsistencyRange _range(
  List<PlanProtocol> protocols,
  ProtocolDayDate from,
  ProtocolDayDate to,
  List<DoseRecord> doses,
) {
  final days = planDays(protocols, from, to);
  final sequenceByDate = <ProtocolDayDate, int>{};
  final planDoses = <PlanDose>[
    for (final dose in doses)
      PlanDose(
        doseId: dose.id,
        compoundId: dose.compoundId!,
        localDate: dose.localDate,
        localTime: dose.localTime,
        sequence: sequenceByDate.update(
          dose.localDate,
          (sequence) => sequence + 1,
          ifAbsent: () => 0,
        ),
      ),
  ];
  return ConsistencyRange(
    compoundId: 'c-trt',
    from: from,
    to: to,
    today: to,
    planDays: days,
    dayStatuses: dayStatuses(days, planDoses, to),
    doses: doses,
    compound: null,
    protocols: const <String, ProtocolOptionRecord>{},
  );
}

/// Each planned segment as its `HH:MM` time and its first and last day.
List<(String, int, int)> _segments(ConsistencyChartData data) =>
    <(String, int, int)>[
      for (final segment in data.plannedSegments)
        (
          _hhmm(segment.y),
          segment.run.startIndex,
          segment.run.endIndex,
        ),
    ];

String _hhmm(double minutes) {
  final value = minutes.round();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${two(value ~/ 60)}:${two(value % 60)}';
}

/// "Skin": GHK-Cu at 21:00 daily, 60 days on and 30 off, anchored on 1
/// September 2026 (CUJ 3).
PlanProtocol _skin({List<ProtocolPause> pauses = const <ProtocolPause>[]}) {
  final start = _date(2026, 9, 1);
  return PlanProtocol(
    protocolId: 'p-skin',
    startLocalDate: start,
    period: ProtocolPeriod(
      cycle: ProtocolCycle(
        onDays: 60,
        offDays: 30,
        anchor: start,
        anchorIsDefault: true,
      ),
      pauses: pauses,
    ),
    members: <PlanMember>[
      PlanMember(
        memberId: 'm-ghk',
        compoundId: 'c-ghk',
        versions: <ScheduleVersion>[
          _version('v-ghk', start, _daily(<String>['21:00'])),
        ],
      ),
    ],
  );
}

ScheduleVersion _version(
  String id,
  ProtocolDayDate effectiveFrom,
  ScheduleRule rule,
) {
  return ScheduleVersion(
    id: id,
    effectiveFrom: effectiveFrom,
    rule: rule,
    amount: const PlanAmount(
      amountValue: 1,
      amountEntered: '1',
      unit: DoseUnit.milligram,
      route: DoseRoute.oral,
    ),
  );
}

ScheduleRule _daily(List<String> times) =>
    TimedScheduleRule(days: const DailyScheduleDays(), times: times);

/// A Dose of `c-trt` at [hour]:[minute] on [date], with its offset frozen
/// at UTC so its local time reads the same on every test host.
DoseRecord _dose(String id, ProtocolDayDate date, int hour, int minute) {
  final tookAt = DateTime.utc(date.year, date.month, date.day, hour, minute);
  return DoseRecord(
    id: id,
    compoundId: 'c-trt',
    compoundName: 'TRT',
    amountValue: 1,
    amountEntered: '1',
    unit: DoseUnit.milligram,
    route: DoseRoute.oral,
    tookAt: tookAt,
    timezone: 'UTC',
    localDate: date,
    timezoneOffsetMinutes: 0,
    provenance: DoseProvenance.manual,
    updatedAt: tookAt,
  );
}

ProtocolDayDate _date(int year, int month, int day) =>
    ProtocolDayDate(year: year, month: month, day: day);
