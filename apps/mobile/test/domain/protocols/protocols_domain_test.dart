import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/protocols/protocols.dart';

void main() {
  group('curated Dose unit registry (never free-text)', () {
    test('every member has an exhaustive label', () {
      for (final unit in DoseUnit.values) {
        expect(doseUnitLabel(unit), isNotEmpty);
      }
    });

    test('a registry name round-trips to the same enum member', () {
      for (final unit in DoseUnit.values) {
        expect(doseUnitFromName(unit.name), unit);
      }
    });

    test('a free-text unit outside the registry is rejected', () {
      expect(
        () => doseUnitFromName('scoop'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => doseUnitFromName('mg/capsule'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('curated Dose route registry (never free-text)', () {
    test('every member has an exhaustive label', () {
      for (final route in DoseRoute.values) {
        expect(doseRouteLabel(route), isNotEmpty);
      }
    });

    test('a registry name round-trips to the same enum member', () {
      for (final route in DoseRoute.values) {
        expect(doseRouteFromName(route.name), route);
      }
    });

    test('a free-text route outside the registry is rejected', () {
      expect(
        () => doseRouteFromName('injected-somehow'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('CompoundStrength (optional, curated units, never free-text)', () {
    test('carries an amount + mass unit per a countable unit', () {
      final strength = CompoundStrength(
        amount: 5,
        amountEntered: '5',
        massUnit: DoseUnit.milligram,
        perUnit: DoseUnit.capsule,
      );
      expect(strength.amount, 5);
      expect(strength.massUnit, DoseUnit.milligram);
      expect(strength.perUnit, DoseUnit.capsule);
    });

    test('serializes to a canonical, human-readable label', () {
      final strength = CompoundStrength(
        amount: 250,
        amountEntered: '250',
        massUnit: DoseUnit.milligram,
        perUnit: DoseUnit.milliliter,
      );
      expect(strength.storageValue, '250 mg/mL');
    });

    test('parses its own canonical form back to structure', () {
      final parsed = CompoundStrength.parse('5 mg/capsule');
      expect(parsed.amount, 5);
      expect(parsed.amountEntered, '5');
      expect(parsed.massUnit, DoseUnit.milligram);
      expect(parsed.perUnit, DoseUnit.capsule);
    });

    test('round-trips storageValue -> parse -> storageValue', () {
      for (final raw in <String>[
        '5 mg/capsule',
        '250 mg/mL',
        '1000 IU/tablet'
      ]) {
        expect(CompoundStrength.parse(raw).storageValue, raw);
      }
    });

    test('rejects a strength whose units are outside the registry', () {
      expect(
        () => CompoundStrength.parse('5 mg/scoop'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CompoundStrength.parse('5 grams/capsule'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a malformed (non per-unit) strength', () {
      expect(
        () => CompoundStrength.parse('5 mg'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CompoundStrength.parse('mg/capsule'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a non-positive amount', () {
      expect(
        () => CompoundStrength(
          amount: 0,
          amountEntered: '0',
          massUnit: DoseUnit.milligram,
          perUnit: DoseUnit.capsule,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('resolveDoseActiveMass (derived on read)', () {
    test('"1 capsule" x "5 mg/capsule" resolves to 5 mg', () {
      final strength = CompoundStrength.parse('5 mg/capsule');
      final resolved = resolveDoseActiveMass(
        amount: 1,
        unit: DoseUnit.capsule,
        strength: strength,
      );
      expect(resolved, isNotNull);
      expect(resolved!.value, 5);
      expect(resolved.unit, DoseUnit.milligram);
    });

    test('"0.5 mL" x "250 mg/mL" resolves to 125 mg', () {
      final strength = CompoundStrength.parse('250 mg/mL');
      final resolved = resolveDoseActiveMass(
        amount: 0.5,
        unit: DoseUnit.milliliter,
        strength: strength,
      );
      expect(resolved, isNotNull);
      expect(resolved!.value, 125);
      expect(resolved.unit, DoseUnit.milligram);
    });

    test('a dose already in the active-mass unit resolves to itself', () {
      // 250 mg of a "5 mg/capsule" compound is already an active mass.
      final strength = CompoundStrength.parse('5 mg/capsule');
      final resolved = resolveDoseActiveMass(
        amount: 250,
        unit: DoseUnit.milligram,
        strength: strength,
      );
      expect(resolved, isNotNull);
      expect(resolved!.value, 250);
      expect(resolved.unit, DoseUnit.milligram);
    });

    test('with no strength the active mass is simply unresolved (null)', () {
      final resolved = resolveDoseActiveMass(
        amount: 1,
        unit: DoseUnit.capsule,
        strength: null,
      );
      expect(resolved, isNull);
    });

    test(
        'a unit that matches neither the per-unit nor the mass unit is '
        'unresolved (non-blocking)', () {
      final strength = CompoundStrength.parse('5 mg/capsule');
      // The dose is logged in tablets but the strength is per-capsule: we cannot
      // resolve, but the Dose is never blocked on it.
      final resolved = resolveDoseActiveMass(
        amount: 1,
        unit: DoseUnit.tablet,
        strength: strength,
      );
      expect(resolved, isNull);
    });
  });

  group('DoseRecord.resolvedActiveMass (derived on read, never stored)', () {
    DoseRecord doseWith({
      String? compoundStrength,
      required double amountValue,
      required DoseUnit unit,
    }) {
      return DoseRecord(
        id: 'd',
        compoundName: 'X',
        compoundStrength: CompoundStrength.tryParse(compoundStrength),
        amountValue: amountValue,
        amountEntered: amountValue.toString(),
        unit: unit,
        route: DoseRoute.oral,
        tookAt: DateTime.utc(2026, 6, 30, 8),
        timezone: 'UTC',
        localDate: const ProtocolDayDate(year: 2026, month: 6, day: 30),
        provenance: DoseProvenance.manual,
        updatedAt: DateTime.utc(2026, 6, 30, 8),
      );
    }

    test('resolves from the frozen strength snapshot + amount + unit', () {
      final dose = doseWith(
        compoundStrength: '5 mg/capsule',
        amountValue: 2,
        unit: DoseUnit.capsule,
      );
      final resolved = dose.resolvedActiveMass;
      expect(resolved, isNotNull);
      expect(resolved!.value, 10);
      expect(resolved.unit, DoseUnit.milligram);
    });

    test('an unresolvable Dose reads back a null active mass (non-blocking)',
        () {
      final dose = doseWith(
        compoundStrength: null,
        amountValue: 3,
        unit: DoseUnit.milligram,
      );
      expect(dose.resolvedActiveMass, isNull);
    });
  });

  // the `Protocol` plan-layer entity (PROTOCOLS.md §1.4) — a named,
  // time-bounded course grouping one or more Compounds. Pure data-holder unit
  // tests for the derived getters; the write/read path is covered at the
  // repository layer (protocols_repository_test.dart).
  group('ProtocolRecord (plan-layer entity, PROTOCOLS.md §1.4)', () {
    ProtocolRecord protocolWith({
      List<ProtocolMemberRecord> members = const <ProtocolMemberRecord>[],
      DateTime? deletedAt,
    }) {
      return ProtocolRecord(
        id: 'p1',
        name: 'Lean bulk',
        startDate: DateTime.utc(2026, 7, 1),
        members: members,
        updatedAt: DateTime.utc(2026, 7, 1),
        deletedAt: deletedAt,
      );
    }

    test('a single-Compound Protocol is not a stack', () {
      final protocol = protocolWith(
        members: const <ProtocolMemberRecord>[
          ProtocolMemberRecord(id: 'm1', compoundId: 'c1', position: 0),
        ],
      );
      expect(protocol.isStack, isFalse);
    });

    test('a multi-Compound Protocol IS a stack (PROTOCOLS.md §1.4)', () {
      final protocol = protocolWith(
        members: const <ProtocolMemberRecord>[
          ProtocolMemberRecord(id: 'm1', compoundId: 'c1', position: 0),
          ProtocolMemberRecord(id: 'm2', compoundId: 'c2', position: 1),
        ],
      );
      expect(protocol.isStack, isTrue);
    });

    test('isArchived reflects the deletedAt tombstone, not a separate flag',
        () {
      expect(protocolWith().isArchived, isFalse);
      expect(
          protocolWith(deletedAt: DateTime.utc(2026, 8, 1)).isArchived, isTrue);
    });

    test('a Protocol with no Schedules at all is still a valid stack', () {
      final protocol = protocolWith(
        members: const <ProtocolMemberRecord>[
          ProtocolMemberRecord(id: 'm1', compoundId: 'c1', position: 0),
          ProtocolMemberRecord(id: 'm2', compoundId: 'c2', position: 1),
        ],
      );
      expect(protocol.members.every((m) => m.schedule == null), isTrue);
    });

    test('list-backed Protocol read models are immutable snapshots', () {
      final member = const ProtocolMemberRecord(
        id: 'm1',
        compoundId: 'c1',
        position: 0,
      );
      final outcome = const ProtocolTargetOutcomeRecord(
        id: 'outcome-1',
        kind: ProtocolOutcomeKind.performance,
        position: 0,
      );
      final members = <ProtocolMemberRecord>[member];
      final targetOutcomes = <ProtocolTargetOutcomeRecord>[outcome];

      final protocol = ProtocolRecord(
        id: 'p1',
        name: 'Lean bulk',
        startDate: DateTime.utc(2026, 7, 1),
        members: members,
        targetOutcomes: targetOutcomes,
        updatedAt: DateTime.utc(2026, 7, 1),
      );
      members.clear();
      targetOutcomes.clear();

      expect(protocol.members, <ProtocolMemberRecord>[member]);
      expect(protocol.targetOutcomes, <ProtocolTargetOutcomeRecord>[outcome]);
      expect(() => protocol.members.clear(), throwsUnsupportedError);
      expect(() => protocol.targetOutcomes.clear(), throwsUnsupportedError);

      final dose = DoseRecord(
        id: 'dose-1',
        compoundName: 'Creatine',
        amountValue: 5,
        amountEntered: '5',
        unit: DoseUnit.gram,
        route: DoseRoute.oral,
        tookAt: DateTime.utc(2026, 7, 1, 8),
        timezone: 'UTC',
        localDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
        provenance: DoseProvenance.manual,
        updatedAt: DateTime.utc(2026, 7, 1, 8),
      );
      final doses = <DoseRecord>[dose];
      final day = ProtocolDayRecord(
        localDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
        doses: doses,
      );
      doses.clear();

      expect(day.doses, <DoseRecord>[dose]);
      expect(() => day.doses.clear(), throwsUnsupportedError);
    });
  });

  // the curated `ScheduleFrequency` registry (PROTOCOLS.md §1.4) —
  // never free-text, mirroring DoseUnit/DoseRoute.
  group('curated Schedule frequency registry (never free-text)', () {
    test('every member has an exhaustive label', () {
      for (final frequency in ScheduleFrequency.values) {
        expect(scheduleFrequencyLabel(frequency), isNotEmpty);
      }
    });

    test('a registry name round-trips to the same enum member', () {
      for (final frequency in ScheduleFrequency.values) {
        expect(scheduleFrequencyFromName(frequency.name), frequency);
      }
    });

    test('a free-text frequency outside the registry is rejected', () {
      expect(
        () => scheduleFrequencyFromName('every-full-moon'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // `Schedule` — the Prescription analog (PROTOCOLS.md §1.4): an
  // OPTIONAL planned dose · frequency · route attached to a Protocol's member
  // Compound. Purely prescriptive; dose-response is always derived from the
  // ACTUAL logged Doses, never the Schedule.
  group('ScheduleRecord (optional plan-only template, PROTOCOLS.md §1.4)', () {
    ScheduleRecord scheduleWith({DateTime? deletedAt}) {
      return ScheduleRecord(
        id: 's1',
        protocolCompoundId: 'member-1',
        doseAmountValue: 5,
        doseAmountEntered: '5',
        doseUnit: DoseUnit.gram,
        frequency: ScheduleFrequency.onceDaily,
        route: DoseRoute.oral,
        updatedAt: DateTime.utc(2026, 7, 1),
        deletedAt: deletedAt,
      );
    }

    test('carries the planned dose + frequency + route', () {
      final schedule = scheduleWith();
      expect(schedule.doseAmountValue, 5);
      expect(schedule.doseAmountEntered, '5');
      expect(schedule.doseUnit, DoseUnit.gram);
      expect(schedule.frequency, ScheduleFrequency.onceDaily);
      expect(schedule.route, DoseRoute.oral);
    });

    test('renders a human-facing planned dose label', () {
      final schedule = scheduleWith();
      expect(schedule.doseLabel, '5 g');
    });

    test('isArchived reflects the deletedAt tombstone', () {
      expect(scheduleWith().isArchived, isFalse);
      expect(
        scheduleWith(deletedAt: DateTime.utc(2026, 8, 1)).isArchived,
        isTrue,
      );
    });
  });
}
