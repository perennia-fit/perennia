import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, Value, driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:perennia/api/perennia_api_client.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/otc_compound_seed.dart';
import 'package:perennia/features/activity/repositories/activity_feed_repository.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';
import 'package:perennia/features/protocols/controllers/protocols_day_controller.dart';
import 'package:perennia/features/sync/repositories/sync_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  group('protocols repository', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('opens Compound and Dose schema without a Protocol Day table',
        () async {
      final columnsByTable = await database.describeSchema();

      expect(
        columnsByTable.keys,
        containsAll(<String>[
          AppDatabase.compoundsTable,
          AppDatabase.dosesTable,
        ]),
      );
      // The Protocol Day is derived on read; never a stored table.
      expect(columnsByTable.keys, isNot(contains('protocol_days')));

      expect(
        columnsByTable[AppDatabase.compoundsTable],
        containsAll(<String>[
          'id',
          'name',
          'default_unit',
          'default_route',
          'strength',
          'updated_at',
          'deleted_at',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.dosesTable],
        containsAll(<String>[
          'id',
          'compound_id',
          'compound_name',
          // The strength snapshot makes a Dose self-describing: the
          // resolved meaning travels with the Dose, not via a live Compound join.
          'compound_strength',
          'amount_value',
          'amount_entered',
          'unit',
          'route',
          'took_at',
          'timezone',
          'local_date',
          'provenance',
          'updated_at',
          'deleted_at',
        ]),
      );
    });

    test(
        'creates a Compound with a name and default unit/route, stored offline',
        () async {
      final result = await repositories.protocols.createCompound(
        CompoundDraft(
          name: 'Vitamin D',
          defaultUnit: DoseUnit.internationalUnit,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('1000 IU/capsule'),
        ),
      );

      final compounds = await repositories.protocols.listCompounds();
      expect(compounds, hasLength(1));
      final compound = compounds.single;
      expect(compound.id, result.compoundId);
      expect(compound.name, 'Vitamin D');
      expect(compound.defaultUnit, DoseUnit.internationalUnit);
      expect(compound.defaultRoute, DoseRoute.oral);
      // The structured strength round-trips through storage (curated units).
      expect(compound.strength, CompoundStrength.parse('1000 IU/capsule'));
      expect(compound.strength!.massUnit, DoseUnit.internationalUnit);
      expect(compound.strength!.perUnit, DoseUnit.capsule);
      expect(compound.isArchived, isFalse);
    });

    test('logs a Dose against a Compound that persists offline', () async {
      final compound = await repositories.protocols.createCompound(
        CompoundDraft(
          name: 'Creatine',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('5 g/capsule'),
        ),
      );

      final tookAt = DateTime.utc(2026, 6, 30, 8);
      final result = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: compound.compoundId,
          compoundName: 'Creatine',
          compoundStrength: CompoundStrength.parse('5 g/capsule'),
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: tookAt,
        ),
      );

      final localDate = ProtocolDayDate.fromDateTime(tookAt);
      final day = await repositories.protocols.protocolDay(localDate);
      expect(day.doses, hasLength(1));
      final dose = day.doses.single;
      expect(dose.id, result.doseId);
      expect(dose.compoundId, compound.compoundId);
      expect(dose.compoundName, 'Creatine');
      // The strength snapshot is captured at log time alongside the name (§1.1).
      expect(dose.compoundStrength, CompoundStrength.parse('5 g/capsule'));
      expect(dose.amountValue, 5);
      expect(dose.amountEntered, '5');
      expect(dose.unit, DoseUnit.gram);
      expect(dose.route, DoseRoute.oral);
      expect(dose.provenance, DoseProvenance.manual);
      expect(result.warnings, isEmpty);
    });

    test(
        'snapshots the Compound name and strength from the Compound at log time',
        () async {
      final compound = await repositories.protocols.createCompound(
        CompoundDraft(
          name: 'Vitamin D',
          defaultUnit: DoseUnit.internationalUnit,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('1000 IU/capsule'),
        ),
      );

      final tookAt = DateTime.utc(2026, 6, 30, 8);
      // The draft snapshots the LIVE Compound: the convenience constructor reads
      // the Compound's name + strength so callers cannot forget to capture them.
      final loaded = (await repositories.protocols.listCompounds()).single;
      await repositories.protocols.logDose(
        DoseSnapshotDraft.fromCompound(
          compound: loaded,
          amountValue: 1,
          amountEntered: '1',
          unit: DoseUnit.internationalUnit,
          route: DoseRoute.oral,
          tookAt: tookAt,
        ),
      );

      final dose = (await repositories.protocols
              .protocolDay(ProtocolDayDate.fromDateTime(tookAt)))
          .doses
          .single;
      expect(dose.compoundId, compound.compoundId);
      expect(dose.compoundName, 'Vitamin D');
      expect(dose.compoundStrength, CompoundStrength.parse('1000 IU/capsule'));
    });

    test(
        'a Compound carries an optional structured strength; storage holds the '
        'canonical curated label, never free text', () async {
      await repositories.protocols.createCompound(
        CompoundDraft(
          name: 'Testosterone cypionate',
          defaultUnit: DoseUnit.milliliter,
          defaultRoute: DoseRoute.intramuscular,
          strength: CompoundStrength.parse('250 mg/mL'),
        ),
      );

      // The raw stored column carries the canonical curated label.
      final row = await database.select(database.compounds).getSingle();
      expect(row.strength, '250 mg/mL');

      final compound = (await repositories.protocols.listCompounds()).single;
      expect(compound.strength!.amount, 250);
      expect(compound.strength!.massUnit, DoseUnit.milligram);
      expect(compound.strength!.perUnit, DoseUnit.milliliter);
    });

    test('a Compound may carry no strength at all', () async {
      await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Magnesium',
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
        ),
      );

      final compound = (await repositories.protocols.listCompounds()).single;
      expect(compound.strength, isNull);
      final row = await database.select(database.compounds).getSingle();
      expect(row.strength, isNull);
    });

    test(
        'a free-text unit/route outside the curated registry is rejected on '
        'read', () async {
      // Simulate a malformed row reaching the read model (e.g. a corrupt/foreign
      // sync payload): the registry chokepoint rejects it rather than surfacing
      // free text as data.
      final timestamp = DateTime.utc(2026, 6, 30, 8);
      await database.into(database.doses).insert(
            DosesCompanion.insert(
              id: 'bad-unit-dose',
              compoundName: 'Mystery',
              amountValue: 1,
              amountEntered: '1',
              unit: 'scoops', // outside the curated registry
              route: 'oral',
              tookAt: timestamp,
              timezone: 'UTC',
              localDate: const Value<String>('2026-06-30'),
              updatedAt: timestamp,
            ),
          );

      expect(
        () => repositories.protocols.protocolDay(
          const ProtocolDayDate(year: 2026, month: 6, day: 30),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('resolved active mass is derived on read and is NOT a stored column',
        () async {
      // The schema has no active-mass / resolved column anywhere — it is always
      // computed.
      final columnsByTable = await database.describeSchema();
      final doseColumns = columnsByTable[AppDatabase.dosesTable]!;
      expect(
        doseColumns.where(
          (c) => c.contains('active') || c.contains('resolved'),
        ),
        isEmpty,
      );

      final compound = await repositories.protocols.createCompound(
        CompoundDraft(
          name: 'Vitamin D',
          defaultUnit: DoseUnit.capsule,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('5 mg/capsule'),
        ),
      );

      final tookAt = DateTime.utc(2026, 6, 30, 8);
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: compound.compoundId,
          compoundName: 'Vitamin D',
          compoundStrength: CompoundStrength.parse('5 mg/capsule'),
          amountValue: 2,
          amountEntered: '2',
          unit: DoseUnit.capsule,
          route: DoseRoute.oral,
          tookAt: tookAt,
        ),
      );

      final dose = (await repositories.protocols
              .protocolDay(ProtocolDayDate.fromDateTime(tookAt)))
          .doses
          .single;
      // "2 capsule" x "5 mg/capsule" -> 10 mg, computed on read.
      expect(dose.resolvedActiveMass, isNotNull);
      expect(dose.resolvedActiveMass!.value, 10);
      expect(dose.resolvedActiveMass!.unit, DoseUnit.milligram);
    });

    test(
        'a Dose with no resolvable strength still logs (active mass unresolved)',
        () async {
      final tookAt = DateTime.utc(2026, 6, 30, 9);
      // Ad-hoc Dose, no strength: it must log fine and simply read back a null
      // active mass (non-blocking, PROTOCOLS.md §1.3).
      final result = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundName: 'Mystery blend',
          amountValue: 1,
          amountEntered: '1',
          unit: DoseUnit.capsule,
          route: DoseRoute.oral,
          tookAt: tookAt,
        ),
      );
      expect(result.doseId, isNotEmpty);

      final dose = (await repositories.protocols
              .protocolDay(ProtocolDayDate.fromDateTime(tookAt)))
          .doses
          .single;
      expect(dose.compoundStrength, isNull);
      expect(dose.resolvedActiveMass, isNull);
    });

    test('an ad-hoc Dose may carry no strength snapshot', () async {
      final tookAt = DateTime.utc(2026, 6, 30, 21);
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundName: 'Melatonin',
          amountValue: 3,
          amountEntered: '3',
          unit: DoseUnit.milligram,
          route: DoseRoute.sublingual,
          tookAt: tookAt,
        ),
      );

      final dose = (await repositories.protocols
              .protocolDay(ProtocolDayDate.fromDateTime(tookAt)))
          .doses
          .single;
      expect(dose.compoundStrength, isNull);
    });

    test('an ad-hoc Dose (no Compound) renders from its own snapshot',
        () async {
      final tookAt = DateTime.utc(2026, 6, 30, 21);
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundName: 'Melatonin',
          amountValue: 3,
          amountEntered: '3',
          unit: DoseUnit.milligram,
          route: DoseRoute.sublingual,
          tookAt: tookAt,
        ),
      );

      final day = await repositories.protocols.protocolDay(
        ProtocolDayDate.fromDateTime(tookAt),
      );
      final dose = day.doses.single;
      // The Dose stands alone (no mandatory container, PROTOCOLS.md §1.2) and
      // renders without a Compound (self-describing snapshot, §1.1).
      expect(dose.compoundId, isNull);
      expect(dose.compoundName, 'Melatonin');
      expect(dose.amountLabel, '3 mg');
    });

    test('a Compound create writes exactly one Activity Log batch', () async {
      final result = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Magnesium',
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
        ),
      );

      final all = await repositories.activityLog.listEntries();
      final batchEntries =
          all.where((e) => e.batchId == result.batchId).toList();
      expect(batchEntries, hasLength(1));
      final entry = batchEntries.single;
      expect(entry.entityTable, AppDatabase.compoundsTable);
      expect(entry.entityId, result.compoundId);
      expect(entry.beforeImage, isNull);
      expect(entry.afterImage, isNotNull);
      expect(entry.afterImage!['name'], 'Magnesium');
    });

    test('a Dose log writes exactly one Activity Log batch', () async {
      final result = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundName: 'Caffeine',
          amountValue: 200,
          amountEntered: '200',
          unit: DoseUnit.milligram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 6),
        ),
      );

      final all = await repositories.activityLog.listEntries();
      final batchEntries =
          all.where((e) => e.batchId == result.batchId).toList();
      expect(batchEntries, hasLength(1));
      final entry = batchEntries.single;
      expect(entry.entityTable, AppDatabase.dosesTable);
      expect(entry.entityId, result.doseId);
      expect(entry.afterImage!['compound_name'], 'Caffeine');
    });

    test('distinct writes carry distinct batch ids', () async {
      final first = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Zinc',
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
        ),
      );
      final second = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: first.compoundId,
          compoundName: 'Zinc',
          amountValue: 15,
          amountEntered: '15',
          unit: DoseUnit.milligram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 9),
        ),
      );

      expect(first.batchId, isNot(second.batchId));
    });

    test('Protocol Day groups Doses by frozen local date', () async {
      // Two doses on the same UTC instant family but different local days, plus
      // a same-day pair — the day-view buckets strictly by frozen local_date.
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundName: 'Morning vitamin',
          amountValue: 1,
          amountEntered: '1',
          unit: DoseUnit.tablet,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 7),
          localDate: const ProtocolDayDate(year: 2026, month: 6, day: 30),
        ),
      );
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundName: 'Evening melatonin',
          amountValue: 3,
          amountEntered: '3',
          unit: DoseUnit.milligram,
          route: DoseRoute.sublingual,
          tookAt: DateTime.utc(2026, 6, 30, 22),
          localDate: const ProtocolDayDate(year: 2026, month: 6, day: 30),
        ),
      );
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundName: 'Next day dose',
          amountValue: 1,
          amountEntered: '1',
          unit: DoseUnit.capsule,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 7, 1, 7),
          localDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
        ),
      );

      final day30 = await repositories.protocols.protocolDay(
        const ProtocolDayDate(year: 2026, month: 6, day: 30),
      );
      final day1 = await repositories.protocols.protocolDay(
        const ProtocolDayDate(year: 2026, month: 7, day: 1),
      );

      expect(day30.doseCount, 2);
      expect(
        day30.doses.map((d) => d.compoundName),
        <String>['Morning vitamin', 'Evening melatonin'],
      );
      expect(day1.doseCount, 1);
      expect(day1.doses.single.compoundName, 'Next day dose');
    });

    test('a Dose freezes its timezone and local date at log time', () async {
      // A timezone-bearing instant: the stored UTC instant and the captured
      // timezone are independent of the frozen local date.
      final tookAt = DateTime.utc(2026, 6, 30, 23, 30);
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundName: 'Fish oil',
          amountValue: 1,
          amountEntered: '1',
          unit: DoseUnit.capsule,
          route: DoseRoute.oral,
          tookAt: tookAt,
          timezone: 'Australia/Brisbane',
          localDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
        ),
      );

      final day = await repositories.protocols.protocolDay(
        const ProtocolDayDate(year: 2026, month: 7, day: 1),
      );
      final dose = day.doses.single;
      expect(dose.timezone, 'Australia/Brisbane');
      expect(dose.localDate.storageValue, '2026-07-01');
      // Drift returns DateTimes in local time; compare the instant, not the
      // tagged zone (the same UTC moment was stored).
      expect(dose.tookAt.toUtc(), tookAt);
      // The dose does NOT show up on the UTC day of its instant.
      final utcDay = await repositories.protocols.protocolDay(
        const ProtocolDayDate(year: 2026, month: 6, day: 30),
      );
      expect(utcDay.doses, isEmpty);
    });

    test('omitted timezone/local date are captured from the dose instant',
        () async {
      final tookAt = DateTime(2026, 6, 30, 8); // local wall-clock
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundName: 'Vitamin C',
          amountValue: 500,
          amountEntered: '500',
          unit: DoseUnit.milligram,
          route: DoseRoute.oral,
          tookAt: tookAt,
        ),
      );

      final day = await repositories.protocols.protocolDay(
        ProtocolDayDate.fromDateTime(tookAt),
      );
      final dose = day.doses.single;
      expect(dose.timezone, isNotEmpty);
      expect(
        dose.localDate,
        ProtocolDayDate.fromDateTime(tookAt),
      );
    });

    test('undo reverses a Dose log via the Activity Log batch', () async {
      const localDate = ProtocolDayDate(year: 2026, month: 6, day: 30);
      final result = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundName: 'Ashwagandha',
          amountValue: 600,
          amountEntered: '600',
          unit: DoseUnit.milligram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 20),
          localDate: localDate,
        ),
      );

      expect(
        (await repositories.protocols.protocolDay(localDate)).doseCount,
        1,
      );

      await repositories.activityLog.undoBatch(result.batchId);

      // The new table is registered in both undo image arms, so the dose is
      // reversed to its (absent) prior state rather than throwing
      // "Unsupported activity entity table".
      expect(
        (await repositories.protocols.protocolDay(localDate)).doses,
        isEmpty,
      );
    });
  });

  // the tiny OTC seed Compound library (PROTOCOLS.md §3).
  group('protocols OTC seed library', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('seeds the neutral OTC Compounds with default unit/route', () async {
      await repositories.protocols.ensureOtcLibrarySeeded();

      final compounds = await repositories.protocols.listCompounds();
      // The curated neutral starter set (PROTOCOLS.md §3).
      expect(
        compounds.map((c) => c.name).toSet(),
        <String>{
          'Creatine',
          'Vitamin D',
          'Caffeine',
          'Magnesium',
          'Melatonin',
          'Fish oil',
        },
      );

      // Each row ships with a sensible default unit/route from the curated
      // registries.
      final creatine = compounds.firstWhere((c) => c.name == 'Creatine');
      expect(creatine.defaultUnit, DoseUnit.gram);
      expect(creatine.defaultRoute, DoseRoute.oral);
      final melatonin = compounds.firstWhere((c) => c.name == 'Melatonin');
      expect(melatonin.defaultUnit, DoseUnit.milligram);
      expect(melatonin.defaultRoute, DoseRoute.sublingual);
      final vitaminD = compounds.firstWhere((c) => c.name == 'Vitamin D');
      expect(vitaminD.defaultUnit, DoseUnit.internationalUnit);
      expect(vitaminD.strength, CompoundStrength.parse('1000 IU/capsule'));
    });

    test('the seed carries NO type/legality categorization field', () async {
      await repositories.protocols.ensureOtcLibrarySeeded();

      // The neutral-instrument posture is structural: the Compound schema has no
      // column that names a substance type or legality. The genericity IS the
      // legal posture — a reviewer rejects any such field.
      final columnsByTable = await database.describeSchema();
      final compoundColumns = columnsByTable[AppDatabase.compoundsTable]!;
      for (final forbidden in <String>[
        'type',
        'class',
        'category',
        'schedule',
        'controlled',
        'legality',
        'kind',
      ]) {
        expect(
          compoundColumns.any((c) => c.contains(forbidden)),
          isFalse,
          reason: 'Compound must never categorize by "$forbidden".',
        );
      }
    });

    test('re-running the seed is idempotent — no duplicate Compounds',
        () async {
      await repositories.protocols.ensureOtcLibrarySeeded();
      final firstCount = (await repositories.protocols.listCompounds()).length;
      expect(firstCount, 6);

      // A second seed source instance (fresh in-process future) re-runs the seed
      // against the SAME database — the seed-load precedent (usda/platform):
      // re-running must not duplicate rows.
      final reseed = TrainingRepositories(database);
      await reseed.protocols.ensureOtcLibrarySeeded();

      final compounds = await repositories.protocols.listCompounds();
      expect(compounds, hasLength(6));
      // Each Compound id appears exactly once.
      final ids = compounds.map((c) => c.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('a user can pick a seed Compound and log a Dose against it', () async {
      await repositories.protocols.ensureOtcLibrarySeeded();

      // "Pick" = read the seed Compound from the picker source (listCompounds),
      // then log a Dose snapshotting it (the same self-describing path as any
      // Dose).
      final creatine = (await repositories.protocols.listCompounds())
          .firstWhere((c) => c.name == 'Creatine');

      final tookAt = DateTime.utc(2026, 6, 30, 8);
      final result = await repositories.protocols.logDose(
        DoseSnapshotDraft.fromCompound(
          compound: creatine,
          amountValue: 5,
          amountEntered: '5',
          unit: creatine.defaultUnit,
          route: creatine.defaultRoute,
          tookAt: tookAt,
        ),
      );

      final dose = (await repositories.protocols
              .protocolDay(ProtocolDayDate.fromDateTime(tookAt)))
          .doses
          .single;
      expect(dose.id, result.doseId);
      // The Dose points at the seed Compound and carries its snapshot.
      expect(dose.compoundId, creatine.id);
      expect(dose.compoundName, 'Creatine');
      expect(dose.unit, DoseUnit.gram);
      expect(dose.route, DoseRoute.oral);
    });

    test('the seed loads idempotently even after a seed Compound is archived',
        () async {
      await repositories.protocols.ensureOtcLibrarySeeded();
      final magnesium = (await repositories.protocols.listCompounds())
          .firstWhere((c) => c.name == 'Magnesium');

      await repositories.protocols.archiveCompound(magnesium.id);
      // Archived: it drops from the active picker.
      expect(
        (await repositories.protocols.listCompounds()).map((c) => c.name),
        isNot(contains('Magnesium')),
      );

      // Re-seeding must NOT resurrect the archived Compound (idempotent by
      // stable id), and must not insert a duplicate.
      await TrainingRepositories(database).protocols.ensureOtcLibrarySeeded();

      final active = await repositories.protocols.listCompounds();
      expect(active.map((c) => c.name), isNot(contains('Magnesium')));
      // The archived row still exists in storage (history survives), exactly
      // once — not duplicated by the re-seed.
      final allRows = await database.select(database.compounds).get();
      final magnesiumRows = allRows.where((r) => r.id == magnesium.id).toList();
      expect(magnesiumRows, hasLength(1));
      expect(magnesiumRows.single.deletedAt, isNotNull);
    });
  });

  // docs/designs/compound-purposes.md, D1, D2, D3 and D8.
  group('Compound Purposes', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    const creatineId = '019200ff-0000-7000-8000-000000000001';
    const vitaminDId = '019200ff-0000-7000-8000-000000000002';
    const sleepId = '019200ff-0000-7000-8000-000000000101';
    const performanceId = '019200ff-0000-7000-8000-000000000103';
    const generalHealthId = '019200ff-0000-7000-8000-000000000106';
    final seedStamp = DateTime.utc(2026, 10, 24);

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    Future<CompoundRow> compoundRow(String id) {
      return (database.select(database.compounds)
            ..where((row) => row.id.equals(id)))
          .getSingle();
    }

    Future<PurposeRow> purposeRow(String id) {
      return (database.select(database.purposes)
            ..where((row) => row.id.equals(id)))
          .getSingle();
    }

    Future<List<ActivityLogRow>> logFor(String table, String id) async {
      final rows = await (database.select(database.activityLog)
            ..where((row) => row.entityId.equals(id)))
          .get();
      return rows
          .where((row) => row.entityTable == table)
          .toList(growable: false);
    }

    /// A device on schema 65: the six rows exist, untagged, and each has only
    /// its `otc_seed` Activity Log entry, which is what the 65 to 66 upgrade
    /// leaves behind.
    Future<void> seedAsUpgradedDevice() async {
      await repositories.protocols.ensureOtcLibrarySeeded();
      await database.customStatement(
        "UPDATE compounds SET purpose_ids = '[]', updated_at = 1000",
      );
    }

    CompoundDraft draftOf(
      CompoundRow row, {
      String? name,
      List<String>? purposeIds,
    }) {
      return CompoundDraft(
        name: name ?? row.name,
        defaultUnit: doseUnitFromName(row.defaultUnit),
        defaultRoute: doseRouteFromName(row.defaultRoute),
        strength: CompoundStrength.tryParse(row.strength),
        purposeIds: purposeIds,
      );
    }

    group('seeding', () {
      test('the starter Purposes are seeded once, in order, at the fixed stamp',
          () async {
        await repositories.protocols.ensureOtcLibrarySeeded();
        await TrainingRepositories(database)
            .protocols
            .ensureOtcLibrarySeeded();

        final purposes = await repositories.protocols.purposes.listActive();
        expect(
          purposes.map((purpose) => purpose.name),
          <String>[
            'Sleep',
            'Body composition',
            'Performance',
            'Recovery',
            'Cognition',
            'General health',
          ],
        );
        expect(
          purposes.map((p) => p.id).toSet(),
          starterPurposes.map((s) => s.id).toSet(),
        );
        expect(
          purposes.every((purpose) => purpose.updatedAt == seedStamp),
          isTrue,
        );
        final log = await logFor(AppDatabase.purposesTable, sleepId);
        expect(log.map((entry) => entry.actor), <String>['otc_seed']);
      });

      test('the starter Purposes are seeded even with an empty OTC source',
          () async {
        final empty = TrainingRepositories(
          database,
          otcCompoundSeedSource: const _EmptyOtcCompoundSeedSource(),
        );

        await empty.protocols.ensureOtcLibrarySeeded();

        expect(await empty.protocols.purposes.listActive(), hasLength(6));
        expect(await database.select(database.compounds).get(), isEmpty);
      });

      test('a renamed or archived starter Purpose is left alone', () async {
        await repositories.protocols.ensureOtcLibrarySeeded();
        await repositories.protocols.purposes.rename(sleepId, name: 'Rest');
        await repositories.protocols.purposes.archive(performanceId);
        final renamed = await purposeRow(sleepId);
        final archived = await purposeRow(performanceId);

        await TrainingRepositories(database)
            .protocols
            .ensureOtcLibrarySeeded();

        expect(await purposeRow(sleepId), renamed);
        expect(await purposeRow(performanceId), archived);
      });

      test('a fresh seed inserts the six rows tagged, at the fixed timestamp',
          () async {
        await repositories.protocols.ensureOtcLibrarySeeded();

        final rows = await database.select(database.compounds).get();
        expect(rows, hasLength(6));
        expect(rows.every((row) => row.updatedAt.toUtc() == seedStamp), isTrue);
        expect(
          (await compoundRow(creatineId)).purposeIds,
          jsonEncode(<String>[performanceId]),
        );
        final records = await repositories.protocols.listCompounds();
        expect(
          records.singleWhere((c) => c.id == vitaminDId).purposeIds,
          <String>[generalHealthId],
        );
      });
    });

    group('backfill', () {
      test('an untouched upgraded row is tagged once, with its own entry',
          () async {
        await seedAsUpgradedDevice();

        await repositories.protocols.backfillSeedPurposes();

        final tagged = await compoundRow(creatineId);
        expect(tagged.purposeIds, jsonEncode(<String>[performanceId]));
        expect(tagged.updatedAt.isAfter(seedStamp), isTrue);
        final log = await logFor(AppDatabase.compoundsTable, creatineId);
        expect(
          log.map((entry) => entry.actor),
          unorderedEquals(<String>['otc_seed', 'otc_purpose_seed']),
        );
        final entry = log.singleWhere((e) => e.actor == 'otc_purpose_seed');
        expect(
          (jsonDecode(entry.afterImage!) as Map)['purpose_ids'],
          tagged.purposeIds,
        );
        expect(entry.syncAcknowledgedAt, isNull);

        // A second run does nothing.
        final logCount =
            (await database.select(database.activityLog).get()).length;
        await repositories.protocols.backfillSeedPurposes();
        expect(await compoundRow(creatineId), tagged);
        expect(
          await database.select(database.activityLog).get(),
          hasLength(logCount),
        );
      });

      test('the batch can be undone, and the row then stays touched', () async {
        await seedAsUpgradedDevice();
        await repositories.protocols.backfillSeedPurposes();
        final entry = (await logFor(AppDatabase.compoundsTable, creatineId))
            .singleWhere((e) => e.actor == 'otc_purpose_seed');

        final result = await repositories.activityLog.undoBatch(entry.batchId);

        expect(result.conflicts, isEmpty);
        expect((await compoundRow(creatineId)).purposeIds, '[]');
        await repositories.protocols.backfillSeedPurposes();
        expect((await compoundRow(creatineId)).purposeIds, '[]');
      });

      test(
          'with onlyNeverSynced, the stamp is one second past the row, not the '
          'current time, and the batch can still be undone', () async {
        await seedAsUpgradedDevice();
        final before = await compoundRow(creatineId);

        await repositories.protocols.backfillSeedPurposes(
          onlyNeverSynced: true,
        );

        final tagged = await compoundRow(creatineId);
        expect(tagged.purposeIds, jsonEncode(<String>[performanceId]));
        expect(
          tagged.updatedAt.isAtSameMomentAs(
            before.updatedAt.add(const Duration(seconds: 1)),
          ),
          isTrue,
        );
        final entry = (await logFor(AppDatabase.compoundsTable, creatineId))
            .singleWhere((e) => e.actor == 'otc_purpose_seed');
        final image = jsonDecode(entry.afterImage!) as Map<String, Object?>;
        expect(
          DateTime.parse(image['updated_at']! as String)
              .isAtSameMomentAs(tagged.updatedAt),
          isTrue,
        );

        final result = await repositories.activityLog.undoBatch(entry.batchId);

        expect(result.conflicts, isEmpty);
        expect((await compoundRow(creatineId)).purposeIds, '[]');
      });

      test('a fresh install has nothing to backfill', () async {
        await repositories.protocols.ensureOtcLibrarySeeded();
        final logCount =
            (await database.select(database.activityLog).get()).length;

        await repositories.protocols.backfillSeedPurposes();

        expect(
          await database.select(database.activityLog).get(),
          hasLength(logCount),
        );
      });

      test('a renamed row is left alone', () async {
        await seedAsUpgradedDevice();
        await repositories.protocols.editCompound(
          creatineId,
          draftOf(await compoundRow(creatineId), name: 'Creatine HCl'),
        );

        await repositories.protocols.backfillSeedPurposes();

        expect((await compoundRow(creatineId)).purposeIds, '[]');
        // The others are still untouched.
        expect(
          (await compoundRow(vitaminDId)).purposeIds,
          jsonEncode(<String>[generalHealthId]),
        );
      });

      test('a row whose name matches but has a user edit is left alone',
          () async {
        await seedAsUpgradedDevice();
        await repositories.protocols.setFavorite(creatineId, isFavorite: true);

        await repositories.protocols.backfillSeedPurposes();

        expect((await compoundRow(creatineId)).purposeIds, '[]');
      });

      test('a row with no Activity Log entry is left alone', () async {
        await seedAsUpgradedDevice();
        await (database.delete(database.activityLog)
              ..where((row) => row.entityId.equals(creatineId)))
            .go();

        await repositories.protocols.backfillSeedPurposes();

        expect((await compoundRow(creatineId)).purposeIds, '[]');
      });

      Map<String, Object?> pulledSeedImage(CompoundRow row) {
        // A schema-65 device's push: no `purpose_ids` key.
        return <String, Object?>{
          'id': row.id,
          'name': row.name,
          'default_unit': row.defaultUnit,
          'default_route': row.defaultRoute,
          'strength': row.strength,
          'is_favorite': row.isFavorite,
          'updated_at': DateTime.utc(2026, 11).toIso8601String(),
          'deleted_at': null,
        };
      }

      for (final actor in <String>['sync', 'agent:agent-key-1']) {
        test('a row with a pulled $actor entry is left alone', () async {
          await seedAsUpgradedDevice();
          await repositories.protocols.applySyncImage(
            entityTable: AppDatabase.compoundsTable,
            image: pulledSeedImage(await compoundRow(creatineId)),
            deviceId: 'device-b',
            batchId: 'batch-pulled',
            actor: actor,
          );

          await repositories.protocols.backfillSeedPurposes();

          expect((await compoundRow(creatineId)).purposeIds, '[]');
        });
      }

      test('an entry pulled with actor otc_seed leaves the row untouched',
          () async {
        await seedAsUpgradedDevice();
        await repositories.protocols.applySyncImage(
          entityTable: AppDatabase.compoundsTable,
          image: pulledSeedImage(await compoundRow(creatineId)),
          deviceId: 'device-b',
          batchId: 'batch-pulled',
          actor: 'otc_seed',
        );

        await repositories.protocols.backfillSeedPurposes();

        expect(
          (await compoundRow(creatineId)).purposeIds,
          jsonEncode(<String>[performanceId]),
        );
      });

      test('a list the user emptied stays empty', () async {
        await repositories.protocols.ensureOtcLibrarySeeded();
        await repositories.protocols.editCompound(
          creatineId,
          draftOf(
            await compoundRow(creatineId),
            purposeIds: const <String>[],
          ),
        );

        await TrainingRepositories(database)
            .protocols
            .ensureOtcLibrarySeeded();
        await repositories.protocols.backfillSeedPurposes();

        expect((await compoundRow(creatineId)).purposeIds, '[]');
      });

      test('a row the user emptied stays empty after Erase, and an untouched '
          'row is still backfilled', () async {
        await repositories.protocols.ensureOtcLibrarySeeded();
        await repositories.protocols.editCompound(
          creatineId,
          draftOf(
            await compoundRow(creatineId),
            purposeIds: const <String>[],
          ),
        );
        await database.customStatement(
          "UPDATE compounds SET purpose_ids = '[]' WHERE id = '$vitaminDId'",
        );

        await repositories.eraseAllData();
        await repositories.protocols.backfillSeedPurposes();

        expect((await compoundRow(creatineId)).purposeIds, '[]');
        expect(
          (await compoundRow(vitaminDId)).purposeIds,
          jsonEncode(<String>[generalHealthId]),
        );
      });
    });

    group('Compound writes', () {
      Future<String> create([List<String>? purposeIds]) async {
        final created = await repositories.protocols.createCompound(
          CompoundDraft(
            name: 'Ashwagandha',
            defaultUnit: DoseUnit.milligram,
            defaultRoute: DoseRoute.oral,
            purposeIds: purposeIds,
          ),
        );
        return created.compoundId;
      }

      test('creating with no list stores an empty one', () async {
        final id = await create();

        expect((await compoundRow(id)).purposeIds, '[]');
        final log = await logFor(AppDatabase.compoundsTable, id);
        expect(
          (jsonDecode(log.single.afterImage!) as Map)['purpose_ids'],
          '[]',
        );
      });

      test('creating keeps the order and collapses repeats', () async {
        final id = await create(<String>['b', 'a', 'b', 'c']);

        expect((await compoundRow(id)).purposeIds, '["b","a","c"]');
        final record = (await repositories.protocols.listCompounds()).single;
        expect(record.purposeIds, <String>['b', 'a', 'c']);
      });

      test('an unchanged edit including the list writes nothing', () async {
        final id = await create(<String>['b', 'a']);
        final before = await compoundRow(id);
        final logCount = (await logFor(AppDatabase.compoundsTable, id)).length;

        final batchId = await repositories.protocols.editCompound(
          id,
          draftOf(before, purposeIds: <String>['b', 'a', 'b']),
        );

        expect(batchId, isNull);
        expect(await compoundRow(id), before);
        expect(
          await logFor(AppDatabase.compoundsTable, id),
          hasLength(logCount),
        );
      });

      test('a changed order is a change', () async {
        final id = await create(<String>['b', 'a']);

        final batchId = await repositories.protocols.editCompound(
          id,
          draftOf(await compoundRow(id), purposeIds: <String>['a', 'b']),
        );

        expect(batchId, isNotNull);
        expect((await compoundRow(id)).purposeIds, '["a","b"]');
      });

      test('a draft with no list leaves the stored list alone', () async {
        final id = await create(<String>['a']);

        final unchanged = await repositories.protocols.editCompound(
          id,
          draftOf(await compoundRow(id)),
        );
        expect(unchanged, isNull);

        final renamed = await repositories.protocols.editCompound(
          id,
          draftOf(await compoundRow(id), name: 'KSM-66'),
        );
        expect(renamed, isNotNull);
        final row = await compoundRow(id);
        expect(row.name, 'KSM-66');
        expect(row.purposeIds, '["a"]');
      });

      for (final stored in <String>['not json', '{"a":1}']) {
        test('a stored list reading $stored reads as no tags, and stays stored',
            () async {
          // Sync and portable archives pass the string through unchecked.
          final id = await create(<String>['a']);
          await database.customStatement(
            'UPDATE compounds SET purpose_ids = ? WHERE id = ?',
            <Object?>[stored, id],
          );

          final compounds = await repositories.protocols.listCompounds();

          expect(
            compounds.singleWhere((compound) => compound.id == id).purposeIds,
            isEmpty,
          );
          expect((await compoundRow(id)).purposeIds, stored);
        });
      }

      test('a pull with no purpose_ids key keeps the stored list', () async {
        final id = await create(<String>['a']);
        final row = await compoundRow(id);

        await repositories.protocols.applySyncImage(
          entityTable: AppDatabase.compoundsTable,
          image: <String, Object?>{
            'id': id,
            'name': 'Renamed elsewhere',
            'default_unit': row.defaultUnit,
            'default_route': row.defaultRoute,
            'strength': null,
            'is_favorite': false,
            'updated_at': DateTime.utc(2026, 12).toIso8601String(),
            'deleted_at': null,
          },
          deviceId: 'device-b',
          batchId: 'batch-pulled',
        );

        final pulled = await compoundRow(id);
        expect(pulled.name, 'Renamed elsewhere');
        expect(pulled.purposeIds, '["a"]');
      });

      test('a pull with no purpose_ids key inserts the column default',
          () async {
        await repositories.protocols.applySyncImage(
          entityTable: AppDatabase.compoundsTable,
          image: <String, Object?>{
            'id': 'pulled-compound',
            'name': 'Pulled',
            'default_unit': DoseUnit.milligram.name,
            'default_route': DoseRoute.oral.name,
            'strength': null,
            'is_favorite': false,
            'updated_at': DateTime.utc(2026, 12).toIso8601String(),
            'deleted_at': null,
          },
          deviceId: 'device-b',
          batchId: 'batch-pulled',
        );

        expect((await compoundRow('pulled-compound')).purposeIds, '[]');
      });

      test('an undo image from before schema 66 still undoes', () async {
        final id = await create();
        final batchId = await repositories.protocols.editCompound(
          id,
          draftOf(await compoundRow(id), name: 'KSM-66'),
        );
        // Rewrite the entry as a schema-65 build wrote it.
        final entry = (await (database.select(database.activityLog)
                  ..where((row) => row.batchId.equals(batchId!)))
                .get())
            .single;
        String withoutKey(String image) => jsonEncode(
              (jsonDecode(image) as Map<String, Object?>)..remove('purpose_ids'),
            );
        await (database.update(database.activityLog)
              ..where((row) => row.id.equals(entry.id)))
            .write(
          ActivityLogCompanion(
            beforeImage: Value<String?>(withoutKey(entry.beforeImage!)),
            afterImage: Value<String?>(withoutKey(entry.afterImage!)),
          ),
        );

        final result = await repositories.activityLog.undoBatch(batchId!);

        expect(result.conflicts, isEmpty);
        expect((await compoundRow(id)).name, 'Ashwagandha');
        expect((await compoundRow(id)).purposeIds, '[]');
      });
    });

    group('Purpose writes', () {
      test('create appends at the end, stores the name trimmed, actor manual',
          () async {
        await repositories.protocols.ensureOtcLibrarySeeded();

        final id = await repositories.protocols.purposes.create('  Joints ');

        final purposes = await repositories.protocols.purposes.listActive();
        expect(purposes.last.id, id);
        expect(purposes.last.name, 'Joints');
        expect(purposes.last.sortOrder, 6);
        expect(starterPurposes.map((s) => s.id), isNot(contains(id)));
        final log = await logFor(AppDatabase.purposesTable, id);
        expect(log.single.actor, 'manual');
      });

      test('an empty name is rejected', () async {
        final id = await repositories.protocols.purposes.create('Joints');

        await expectLater(
          repositories.protocols.purposes.create('   '),
          throwsA(
            isA<PurposeNameException>()
                .having((e) => e.code, 'code', 'purpose_name_required'),
          ),
        );
        await expectLater(
          repositories.protocols.purposes.rename(id, name: ''),
          throwsA(
            isA<PurposeNameException>()
                .having((e) => e.code, 'code', 'purpose_name_required'),
          ),
        );
      });

      test('a duplicate name in another case is rejected', () async {
        await repositories.protocols.purposes.create('Joints');
        final other = await repositories.protocols.purposes.create('Skin');

        await expectLater(
          repositories.protocols.purposes.create(' jOINTS '),
          throwsA(
            isA<PurposeNameException>()
                .having((e) => e.code, 'code', 'duplicate_purpose_name'),
          ),
        );
        await expectLater(
          repositories.protocols.purposes.rename(other, name: 'joints'),
          throwsA(
            isA<PurposeNameException>()
                .having((e) => e.code, 'code', 'duplicate_purpose_name'),
          ),
        );
      });

      test('an archived name is free, and renaming in place is allowed',
          () async {
        final id = await repositories.protocols.purposes.create('Joints');
        await repositories.protocols.purposes.archive(id);

        final reused = await repositories.protocols.purposes.create('joints');
        await repositories.protocols.purposes.rename(reused, name: 'JOINTS');

        expect((await purposeRow(reused)).name, 'JOINTS');
      });

      test('an unchanged rename writes nothing', () async {
        final id = await repositories.protocols.purposes.create('Joints');

        await repositories.protocols.purposes.rename(id, name: ' Joints ');

        expect(await logFor(AppDatabase.purposesTable, id), hasLength(1));
      });

      test('reorder stores the new order in one batch, and needs every active '
          'id', () async {
        final a = await repositories.protocols.purposes.create('A');
        final b = await repositories.protocols.purposes.create('B');

        await repositories.protocols.purposes.reorder(<String>[b, a]);

        expect(
          (await repositories.protocols.purposes.listActive())
              .map((purpose) => purpose.id),
          <String>[b, a],
        );
        await expectLater(
          repositories.protocols.purposes.reorder(<String>[a]),
          throwsArgumentError,
        );
      });

      test('archiving keeps the id on a tagged Compound', () async {
        final id = await repositories.protocols.purposes.create('Joints');
        final created = await repositories.protocols.createCompound(
          CompoundDraft(
            name: 'Collagen',
            defaultUnit: DoseUnit.gram,
            defaultRoute: DoseRoute.oral,
            purposeIds: <String>[id],
          ),
        );

        await repositories.protocols.purposes.archive(id);

        expect(await repositories.protocols.purposes.listActive(), isEmpty);
        expect(
          (await compoundRow(created.compoundId)).purposeIds,
          jsonEncode(<String>[id]),
        );
        expect((await purposeRow(id)).deletedAt, isNotNull);
      });

      test('undoing an archive restores the Purpose', () async {
        final id = await repositories.protocols.purposes.create('Joints');
        await repositories.protocols.purposes.archive(id);
        final entry = (await logFor(AppDatabase.purposesTable, id))
            .singleWhere((e) => e.beforeImage != null);

        final result = await repositories.activityLog.undoBatch(entry.batchId);

        expect(result.conflicts, isEmpty);
        expect((await purposeRow(id)).deletedAt, isNull);
      });

      test('undoing an archive into a duplicate name is not applied', () async {
        final id = await repositories.protocols.purposes.create('Joints');
        await repositories.protocols.purposes.archive(id);
        final entry = (await logFor(AppDatabase.purposesTable, id))
            .singleWhere((e) => e.beforeImage != null);
        await repositories.protocols.purposes.create('JOINTS');

        final result = await repositories.activityLog.undoBatch(entry.batchId);

        expect(result.undoBatchId, isNull);
        expect(
          result.conflicts.map((conflict) => conflict.reason),
          <ActivityLogUndoConflictReason>[
            ActivityLogUndoConflictReason.duplicatePurposeName,
          ],
        );
        expect((await purposeRow(id)).deletedAt, isNotNull);
      });

      test('undoing a rename into a duplicate name is not applied', () async {
        final id = await repositories.protocols.purposes.create('Joints');
        await repositories.protocols.purposes.rename(id, name: 'Skin');
        final entry = (await logFor(AppDatabase.purposesTable, id))
            .singleWhere((e) => e.beforeImage != null);
        await repositories.protocols.purposes.create('Joints');

        final result = await repositories.activityLog.undoBatch(entry.batchId);

        expect(
          result.conflicts.single.reason,
          ActivityLogUndoConflictReason.duplicatePurposeName,
        );
        expect((await purposeRow(id)).name, 'Skin');
      });

      test('undoing a reorder ignores a name two rows already share', () async {
        final a = await repositories.protocols.purposes.create('A');
        final b = await repositories.protocols.purposes.create('B');
        await repositories.protocols.purposes.reorder(<String>[b, a]);
        final entry = (await logFor(AppDatabase.purposesTable, a))
            .singleWhere((e) => e.beforeImage != null);
        // Two devices can each name a Purpose the same through LWW sync.
        await repositories.protocols.purposes.create('C');
        await database.customStatement(
          "UPDATE purposes SET name = 'A' WHERE name = 'C'",
        );

        final result = await repositories.activityLog.undoBatch(entry.batchId);

        expect(result.conflicts, isEmpty);
      });

      test('a pulled Purpose applies last-writer-wins on the generic path',
          () async {
        Map<String, Object?> image(String name, DateTime at) {
          return <String, Object?>{
            'id': sleepId,
            'name': name,
            'sort_order': 0,
            'updated_at': at.toIso8601String(),
            'deleted_at': null,
          };
        }

        Future<bool> apply(Map<String, Object?> pulled) {
          return repositories.activityLog.applyPlanSyncImage(
            entityTable: AppDatabase.purposesTable,
            image: pulled,
            deviceId: 'device-b',
            localDeviceId: 'device-a',
            batchId: 'batch-pulled',
          );
        }

        await repositories.protocols.ensureOtcLibrarySeeded();
        expect(await apply(image('Older', DateTime.utc(2026, 1))), isFalse);
        expect((await purposeRow(sleepId)).name, 'Sleep');

        expect(await apply(image('Rest', DateTime.utc(2026, 11))), isTrue);
        final pulled = await purposeRow(sleepId);
        expect(pulled.name, 'Rest');
        expect(pulled.syncDeviceId, 'device-b');
        expect(pulled.syncPreviouslySynced, isTrue);
      });
    });
  });

  // the Compound archive lifecycle (PROTOCOLS.md §7). "User-facing
  // delete = archive" is a repository semantic over the deletedAt tombstone,
  // never a separate flag, and never cascades to logged Doses.
  group('protocols Compound archive lifecycle', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('archive is the deletedAt tombstone, not a separate isArchived flag',
        () async {
      // The archive semantic rides on the same deletedAt column as Exercise/Food
      // — the schema has no separate is_archived/archived flag.
      final columnsByTable = await database.describeSchema();
      final compoundColumns = columnsByTable[AppDatabase.compoundsTable]!;
      expect(compoundColumns, contains('deleted_at'));
      expect(
        compoundColumns.any((c) => c.contains('archiv')),
        isFalse,
        reason: 'Archive must be the deletedAt tombstone, not a flag.',
      );
    });

    test(
        'archiving a Compound removes it from pickers but its history survives',
        () async {
      final compound = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Zinc',
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
        ),
      );

      // Present in the picker before archiving.
      expect(
        (await repositories.protocols.listCompounds()).map((c) => c.name),
        contains('Zinc'),
      );

      await repositories.protocols.archiveCompound(compound.compoundId);

      // Dropped from the active picker...
      expect(await repositories.protocols.listCompounds(), isEmpty);
      // ...but the row survives in storage with a tombstone (history survives;
      // no destructive delete).
      final row = await (database.select(database.compounds)
            ..where((r) => r.id.equals(compound.compoundId)))
          .getSingle();
      expect(row.deletedAt, isNotNull);
      expect(row.name, 'Zinc');
    });

    test('archiving writes exactly one reversible Activity Log batch',
        () async {
      final compound = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Zinc',
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
        ),
      );

      final batchId =
          await repositories.protocols.archiveCompound(compound.compoundId);

      final batchEntries = (await repositories.activityLog.listEntries())
          .where((e) => e.batchId == batchId)
          .toList();
      expect(batchEntries, hasLength(1));
      final entry = batchEntries.single;
      expect(entry.entityTable, AppDatabase.compoundsTable);
      expect(entry.beforeImage!['deleted_at'], isNull);
      expect(entry.afterImage!['deleted_at'], isNotNull);

      // The archive is reversible through the Activity Log (no destructive
      // delete): undoing the batch restores it to the picker.
      await repositories.activityLog.undoBatch(batchId);
      expect(
        (await repositories.protocols.listCompounds()).map((c) => c.name),
        contains('Zinc'),
      );
    });

    test('archiving a Compound never cascades to or alters logged Doses',
        () async {
      final compound = await repositories.protocols.createCompound(
        CompoundDraft(
          name: 'Vitamin D',
          defaultUnit: DoseUnit.internationalUnit,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('1000 IU/capsule'),
        ),
      );

      final tookAt = DateTime.utc(2026, 6, 30, 8);
      final loaded = (await repositories.protocols.listCompounds()).single;
      final logged = await repositories.protocols.logDose(
        DoseSnapshotDraft.fromCompound(
          compound: loaded,
          amountValue: 1,
          amountEntered: '1',
          unit: DoseUnit.capsule,
          route: DoseRoute.oral,
          tookAt: tookAt,
          localDate: ProtocolDayDate.fromDateTime(tookAt),
        ),
      );

      // Capture the persisted Dose row image before archiving.
      final beforeRow = await (database.select(database.doses)
            ..where((r) => r.id.equals(logged.doseId)))
          .getSingle();

      await repositories.protocols.archiveCompound(compound.compoundId);

      // The Compound is archived (dropped from the picker)...
      expect(await repositories.protocols.listCompounds(), isEmpty);

      // ...the Dose is NOT tombstoned (no cascade) and is byte-for-byte
      // unchanged: archiving never reached into the self-describing snapshot.
      final afterRow = await (database.select(database.doses)
            ..where((r) => r.id.equals(logged.doseId)))
          .getSingle();
      expect(afterRow.deletedAt, isNull);
      expect(afterRow.compoundName, beforeRow.compoundName);
      expect(afterRow.compoundStrength, beforeRow.compoundStrength);
      expect(afterRow.amountValue, beforeRow.amountValue);
      expect(afterRow.updatedAt, beforeRow.updatedAt);

      // And it still renders on its Protocol Day from its own snapshot.
      final dose = (await repositories.protocols
              .protocolDay(ProtocolDayDate.fromDateTime(tookAt)))
          .doses
          .single;
      expect(dose.compoundName, 'Vitamin D');
      expect(dose.compoundStrength, CompoundStrength.parse('1000 IU/capsule'));
    });
  });

  // The load-bearing invariant of the domain (PROTOCOLS.md §1.1): a
  // logged Dose snapshots its Compound and reads from its OWN snapshot forever.
  // Mutating, archiving, or deleting the Compound never rewrites a logged Dose.
  group('protocols dose snapshot immutability', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    /// Logs one Dose snapshotting [compound], then returns the captured snapshot
    /// image straight from the Activity Log so a later assertion can prove it is
    /// byte-for-byte unchanged regardless of what happens to the Compound.
    Future<({String doseId, Map<String, Object?> snapshot})> logSnapshotted(
      CreateCompoundResult compound, {
      required String name,
      required CompoundStrength? strength,
    }) async {
      final result = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: compound.compoundId,
          compoundName: name,
          compoundStrength: strength,
          amountValue: 1,
          amountEntered: '1',
          unit: DoseUnit.capsule,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 8),
          localDate: const ProtocolDayDate(year: 2026, month: 6, day: 30),
        ),
      );
      final entry = (await repositories.activityLog.listEntries())
          .firstWhere((e) => e.entityId == result.doseId);
      return (doseId: result.doseId, snapshot: entry.afterImage!);
    }

    Future<DoseRecord> readDose(String doseId) async {
      final day = await repositories.protocols.protocolDay(
        const ProtocolDayDate(year: 2026, month: 6, day: 30),
      );
      return day.doses.firstWhere((d) => d.id == doseId);
    }

    test('renaming the Compound never alters a previously logged Dose',
        () async {
      final compound = await repositories.protocols.createCompound(
        CompoundDraft(
          name: 'Vitamin D',
          defaultUnit: DoseUnit.internationalUnit,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('1000 IU/capsule'),
        ),
      );
      final logged = await logSnapshotted(
        compound,
        name: 'Vitamin D',
        strength: CompoundStrength.parse('1000 IU/capsule'),
      );

      await repositories.protocols.editCompound(
        compound.compoundId,
        CompoundDraft(
          name: 'Cholecalciferol',
          defaultUnit: DoseUnit.internationalUnit,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('1000 IU/capsule'),
        ),
      );

      // The Compound row changed...
      final live = (await repositories.protocols.listCompounds()).single;
      expect(live.name, 'Cholecalciferol');
      // ...but the Dose still reads its frozen snapshot.
      final dose = await readDose(logged.doseId);
      expect(dose.compoundName, 'Vitamin D');
    });

    test('changing the Compound strength never alters a previously logged Dose',
        () async {
      final compound = await repositories.protocols.createCompound(
        CompoundDraft(
          name: 'Vitamin D',
          defaultUnit: DoseUnit.internationalUnit,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('1000 IU/capsule'),
        ),
      );
      final logged = await logSnapshotted(
        compound,
        name: 'Vitamin D',
        strength: CompoundStrength.parse('1000 IU/capsule'),
      );

      await repositories.protocols.editCompound(
        compound.compoundId,
        CompoundDraft(
          name: 'Vitamin D',
          defaultUnit: DoseUnit.internationalUnit,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('5000 IU/capsule'),
        ),
      );

      final live = (await repositories.protocols.listCompounds()).single;
      expect(live.strength, CompoundStrength.parse('5000 IU/capsule'));
      final dose = await readDose(logged.doseId);
      expect(dose.compoundStrength, CompoundStrength.parse('1000 IU/capsule'));
    });

    test('archiving the Compound never alters or removes a logged Dose',
        () async {
      final compound = await repositories.protocols.createCompound(
        CompoundDraft(
          name: 'Vitamin D',
          defaultUnit: DoseUnit.internationalUnit,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('1000 IU/capsule'),
        ),
      );
      final logged = await logSnapshotted(
        compound,
        name: 'Vitamin D',
        strength: CompoundStrength.parse('1000 IU/capsule'),
      );

      await repositories.protocols.archiveCompound(compound.compoundId);

      // The Compound drops out of pickers (archived)...
      expect(await repositories.protocols.listCompounds(), isEmpty);
      // ...but the Dose survives unchanged and still renders from its snapshot.
      final dose = await readDose(logged.doseId);
      expect(dose.compoundName, 'Vitamin D');
      expect(dose.compoundStrength, CompoundStrength.parse('1000 IU/capsule'));
    });

    test('deleting the Compound never alters or removes a logged Dose',
        () async {
      final compound = await repositories.protocols.createCompound(
        CompoundDraft(
          name: 'Vitamin D',
          defaultUnit: DoseUnit.internationalUnit,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('1000 IU/capsule'),
        ),
      );
      final logged = await logSnapshotted(
        compound,
        name: 'Vitamin D',
        strength: CompoundStrength.parse('1000 IU/capsule'),
      );

      await repositories.protocols.deleteCompound(compound.compoundId);

      final dose = await readDose(logged.doseId);
      expect(dose.compoundName, 'Vitamin D');
      expect(dose.compoundStrength, CompoundStrength.parse('1000 IU/capsule'));
    });

    test(
        'the Dose snapshot is byte-for-byte unchanged across rename, strength '
        'change, archive, AND delete', () async {
      final compound = await repositories.protocols.createCompound(
        CompoundDraft(
          name: 'Vitamin D',
          defaultUnit: DoseUnit.internationalUnit,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('1000 IU/capsule'),
        ),
      );
      final logged = await logSnapshotted(
        compound,
        name: 'Vitamin D',
        strength: CompoundStrength.parse('1000 IU/capsule'),
      );
      final original = Map<String, Object?>.from(logged.snapshot);

      await repositories.protocols.editCompound(
        compound.compoundId,
        CompoundDraft(
          name: 'Cholecalciferol',
          defaultUnit: DoseUnit.internationalUnit,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('5000 IU/capsule'),
        ),
      );
      await repositories.protocols.archiveCompound(compound.compoundId);
      await repositories.protocols.deleteCompound(compound.compoundId);

      // The persisted Dose row is identical to the moment it was logged: nothing
      // in the Compound lifecycle ever reached back into the Dose.
      final row = await (database.select(database.doses)
            ..where((r) => r.id.equals(logged.doseId)))
          .getSingle();
      final current = _doseImageForTest(row);
      expect(current, equals(original));
    });

    test('the Dose renders from its snapshot with the Compound absent',
        () async {
      // Log a Dose whose soft compoundId points at a Compound that never existed
      // / was hard-deleted: the read path must NEVER join the live Compound row.
      final tookAt = DateTime.utc(2026, 6, 30, 8);
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: 'missing-compound-id',
          compoundName: 'Vitamin D',
          compoundStrength: CompoundStrength.parse('1000 IU/capsule'),
          amountValue: 1,
          amountEntered: '1',
          unit: DoseUnit.internationalUnit,
          route: DoseRoute.oral,
          tookAt: tookAt,
        ),
      );

      // No Compound row backs this Dose at all.
      expect(await repositories.protocols.listCompounds(), isEmpty);
      final dose = (await repositories.protocols
              .protocolDay(ProtocolDayDate.fromDateTime(tookAt)))
          .doses
          .single;
      expect(dose.compoundName, 'Vitamin D');
      expect(dose.compoundStrength, CompoundStrength.parse('1000 IU/capsule'));
      expect(dose.amountLabel, '1 IU');
    });
  });

  // the SHARED two-tier validator guards the logging path (PROTOCOLS.md
  // §6) — a hard-reject throws before any row persists; a soft-warn is
  // non-blocking and surfaces on the result. This proves the repository consumes
  // the shared validator, not a separate fork.
  group('protocols dose logging-path validation', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('a hard-reject (negative amount) throws and persists nothing',
        () async {
      await expectLater(
        () => repositories.protocols.logDose(
          DoseSnapshotDraft(
            compoundName: 'Caffeine',
            amountValue: -1,
            amountEntered: '-1',
            unit: DoseUnit.milligram,
            route: DoseRoute.oral,
            tookAt: DateTime.utc(2026, 6, 30, 6),
          ),
        ),
        throwsA(
          isA<DoseValidationException>().having(
            (e) => e.errors.single.rule,
            'rule',
            'dose_amount_non_negative',
          ),
        ),
      );

      // Nothing was written: no Dose row and no Activity Log entry.
      expect(await database.select(database.doses).get(), isEmpty);
      expect(await repositories.activityLog.listEntries(), isEmpty);
    });

    test('a hard-reject (absurd per-dose amount) throws and persists nothing',
        () async {
      await expectLater(
        () => repositories.protocols.logDose(
          DoseSnapshotDraft(
            compoundName: 'Creatine',
            amountValue: 2000,
            amountEntered: '2000',
            unit: DoseUnit.gram,
            route: DoseRoute.oral,
            tookAt: DateTime.utc(2026, 6, 30, 6),
          ),
        ),
        throwsA(
          isA<DoseValidationException>().having(
            (e) => e.errors.single.rule,
            'rule',
            'dose_amount_max_per_dose',
          ),
        ),
      );

      expect(await database.select(database.doses).get(), isEmpty);
    });

    test('a soft-warn (out-of-range amount) logs and surfaces the warning',
        () async {
      final tookAt = DateTime.utc(2026, 6, 30, 6);
      final result = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundName: 'Multivitamin',
          amountValue: 60,
          amountEntered: '60',
          unit: DoseUnit.tablet,
          route: DoseRoute.oral,
          tookAt: tookAt,
        ),
      );

      // Accepted: the Dose persisted...
      expect(result.doseId, isNotEmpty);
      final dose = (await repositories.protocols
              .protocolDay(ProtocolDayDate.fromDateTime(tookAt)))
          .doses
          .single;
      expect(dose.amountEntered, '60');
      // ...and the soft warning is surfaced (non-blocking, confirmable).
      expect(result.warnings, <String>['dose_amount_out_of_range_for_unit']);
    });

    test('an ordinary in-range Dose logs with no warnings', () async {
      final result = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 6),
        ),
      );

      expect(result.doseId, isNotEmpty);
      expect(result.warnings, isEmpty);
    });

    test(
        'deleting a Dose tombstones it (deletedAt) without removing the row and '
        'never cascades to its Compound (PROTOCOLS.md §7)', () async {
      final compound = await repositories.protocols.createCompound(
        CompoundDraft(
          name: 'Magnesium',
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
        ),
      );
      final tookAt = DateTime.utc(2026, 6, 30, 21);
      final dose = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: compound.compoundId,
          compoundName: 'Magnesium',
          amountValue: 200,
          amountEntered: '200',
          unit: DoseUnit.milligram,
          route: DoseRoute.oral,
          tookAt: tookAt,
        ),
      );

      final batchId = await repositories.protocols.deleteDose(dose.doseId);

      // The row survives as a tombstone — it is never physically removed.
      final row = await (database.select(database.doses)
            ..where((r) => r.id.equals(dose.doseId)))
          .getSingle();
      expect(row.deletedAt, isNotNull);
      // It drops from the derived Protocol Day day-view.
      final localDate = ProtocolDayDate.fromDateTime(tookAt);
      final day = await repositories.protocols.protocolDay(localDate);
      expect(day.doses, isEmpty);
      // NO CASCADE: the Compound is untouched and still active.
      final compounds = await repositories.protocols.listCompounds();
      expect(compounds.map((c) => c.id), contains(compound.compoundId));
      // The delete is one undoable Activity Log batch (before/after images).
      final entries = await repositories.activityLog.listEntries();
      final deleteEntry = entries.singleWhere(
        (e) => e.batchId == batchId && e.entityId == dose.doseId,
      );
      expect(deleteEntry.entityTable, AppDatabase.dosesTable);
      expect(deleteEntry.beforeImage!['deleted_at'], isNull);
      expect(deleteEntry.afterImage!['deleted_at'], isNotNull);
    });

    test('a tombstoned Dose is recoverable from the Activity Log (undo)',
        () async {
      final tookAt = DateTime.utc(2026, 6, 30, 7);
      final dose = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundName: 'Caffeine',
          compoundStrength: CompoundStrength.parse('100 mg/capsule'),
          amountValue: 1,
          amountEntered: '1',
          unit: DoseUnit.capsule,
          route: DoseRoute.oral,
          tookAt: tookAt,
        ),
      );
      final batchId = await repositories.protocols.deleteDose(dose.doseId);

      final feed = ActivityFeedRepository(repositories);
      final undo = await feed.undoBatch(batchId);

      expect(undo.conflicts, isEmpty);
      // The Dose returns to the derived Protocol Day, snapshot intact.
      final localDate = ProtocolDayDate.fromDateTime(tookAt);
      final day = await repositories.protocols.protocolDay(localDate);
      expect(day.doses, hasLength(1));
      final restored = day.doses.single;
      expect(restored.id, dose.doseId);
      expect(restored.compoundName, 'Caffeine');
      expect(restored.deletedAt, isNull);
      expect(
        restored.compoundStrength,
        CompoundStrength.parse('100 mg/capsule'),
      );
    });

    test('every Compound and Dose write stamps its provenance', () async {
      final compound = await repositories.protocols.createCompound(
        CompoundDraft(
          name: 'Zinc',
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
        ),
      );
      // A Dose carries an explicit provenance stamp (manual/integration/agent).
      final dose = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: compound.compoundId,
          compoundName: 'Zinc',
          amountValue: 15,
          amountEntered: '15',
          unit: DoseUnit.milligram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 9),
          provenance: DoseProvenance.agent,
        ),
        actor: 'agent:key-1',
      );

      final row = await (database.select(database.doses)
            ..where((r) => r.id.equals(dose.doseId)))
          .getSingle();
      expect(row.provenance, DoseProvenance.agent.name);
    });
  });

  // the Protocol Day review surface edits a Dose in place through the
  // repository (never bypassing the Activity Log), and grouping must stay
  // stable across a device timezone change.
  group('protocols Dose editing (review surface)', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test(
        'editDose updates amount/unit/route/time in place, keeping the same '
        'Dose id and appending a distinct Activity Log batch', () async {
      final tookAt = DateTime.utc(2026, 6, 30, 8);
      final logged = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: tookAt,
        ),
      );
      final localDate = ProtocolDayDate.fromDateTime(tookAt);
      final original =
          (await repositories.protocols.protocolDay(localDate)).doses.single;

      final editBatchId = await repositories.protocols.editDose(
        original.id,
        DoseSnapshotDraft(
          compoundId: original.compoundId,
          compoundName: original.compoundName,
          compoundStrength: original.compoundStrength,
          amountValue: 10,
          amountEntered: '10',
          unit: DoseUnit.gram,
          route: DoseRoute.sublingual,
          tookAt: original.tookAt,
          timezone: original.timezone,
          localDate: original.localDate,
          provenance: original.provenance,
        ),
      );

      expect(editBatchId, isNot(logged.batchId));
      final day = await repositories.protocols.protocolDay(localDate);
      expect(day.doses, hasLength(1));
      final edited = day.doses.single;
      expect(edited.id, original.id);
      expect(edited.amountEntered, '10');
      expect(edited.route, DoseRoute.sublingual);

      final entries = await repositories.activityLog.listEntries();
      final editEntry = entries.singleWhere(
        (e) => e.batchId == editBatchId && e.entityId == original.id,
      );
      expect(editEntry.beforeImage!['amount_entered'], '5');
      expect(editEntry.afterImage!['amount_entered'], '10');
    });

    test(
        'editDose runs the shared two-tier validator and rejects an '
        'impossible edit, persisting nothing', () async {
      final tookAt = DateTime.utc(2026, 6, 30, 8);
      final logged = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: tookAt,
        ),
      );
      final before = (await repositories.protocols.protocolDay(
        ProtocolDayDate.fromDateTime(tookAt),
      ))
          .doses
          .single;

      await expectLater(
        () => repositories.protocols.editDose(
          logged.doseId,
          DoseSnapshotDraft(
            compoundId: before.compoundId,
            compoundName: before.compoundName,
            compoundStrength: before.compoundStrength,
            amountValue: -1,
            amountEntered: '-1',
            unit: DoseUnit.gram,
            route: DoseRoute.oral,
            tookAt: before.tookAt,
            timezone: before.timezone,
            localDate: before.localDate,
            provenance: before.provenance,
          ),
        ),
        throwsA(isA<DoseValidationException>()),
      );

      final after = (await repositories.protocols.protocolDay(
        ProtocolDayDate.fromDateTime(tookAt),
      ))
          .doses
          .single;
      expect(after.amountEntered, '5');
    });

    test(
        'editDose keeps a Dose pinned to its ALREADY-FROZEN local date even '
        'when the edited instant would recompute to a DIFFERENT calendar day '
        'under the device\'s current timezone (stability)', () async {
      final tookAt = DateTime.utc(2026, 6, 30, 23, 30);
      // Deliberately frozen ONE DAY AWAY from whatever this process's local
      // timezone would naively compute for this instant — simulating a Dose
      // logged while the device was in a DIFFERENT timezone than the one this
      // test (or a later edit) now runs under. Computed at runtime so the
      // scenario holds regardless of the host machine's own timezone.
      final frozenLocalDate = ProtocolDayDate.fromDateTime(tookAt).addDays(1);
      final logged = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundName: 'Fish oil',
          amountValue: 1,
          amountEntered: '1',
          unit: DoseUnit.capsule,
          route: DoseRoute.oral,
          tookAt: tookAt,
          timezone: 'Australia/Brisbane',
          localDate: frozenLocalDate,
        ),
      );
      final original =
          (await repositories.protocols.protocolDay(frozenLocalDate))
              .doses
              .single;

      // Naively recomputing from the stored UTC instant (as if under the
      // device's CURRENT, changed timezone) lands on a DIFFERENT day than
      // what was frozen at log time — the sanity check that this fixture
      // actually exercises the tz-change scenario.
      final naiveRecompute = ProtocolDayDate.fromDateTime(tookAt);
      expect(naiveRecompute, isNot(original.localDate));

      // Editing only the amount (never touching the date) must NOT move the
      // Dose to the naively-recomputed day.
      await repositories.protocols.editDose(
        logged.doseId,
        DoseSnapshotDraft(
          compoundId: original.compoundId,
          compoundName: original.compoundName,
          compoundStrength: original.compoundStrength,
          amountValue: 2,
          amountEntered: '2',
          unit: original.unit,
          route: original.route,
          tookAt: original.tookAt,
          timezone: original.timezone,
          localDate: original.localDate,
          provenance: original.provenance,
        ),
      );

      final frozenDay =
          await repositories.protocols.protocolDay(frozenLocalDate);
      expect(frozenDay.doses, hasLength(1));
      expect(frozenDay.doses.single.amountEntered, '2');

      final naiveDay = await repositories.protocols.protocolDay(naiveRecompute);
      expect(naiveDay.doses, isEmpty);
    });

    test(
        'editDose falls back to the Dose\'s already-frozen local date when '
        'the draft omits one — never re-deriving from the edited instant',
        () async {
      final tookAt = DateTime.utc(2026, 6, 30, 23, 30);
      // Same runtime-relative construction as above: frozen one day away from
      // whatever this process's local timezone naively computes.
      final frozenLocalDate = ProtocolDayDate.fromDateTime(tookAt).addDays(1);
      final naiveRecompute = ProtocolDayDate.fromDateTime(tookAt);
      final logged = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundName: 'Fish oil',
          amountValue: 1,
          amountEntered: '1',
          unit: DoseUnit.capsule,
          route: DoseRoute.oral,
          tookAt: tookAt,
          timezone: 'Australia/Brisbane',
          localDate: frozenLocalDate,
        ),
      );

      // Omits both timezone and localDate on the edit draft.
      await repositories.protocols.editDose(
        logged.doseId,
        DoseSnapshotDraft(
          compoundName: 'Fish oil',
          amountValue: 2,
          amountEntered: '2',
          unit: DoseUnit.capsule,
          route: DoseRoute.oral,
          tookAt: tookAt,
        ),
      );

      final frozenDay =
          await repositories.protocols.protocolDay(frozenLocalDate);
      expect(frozenDay.doses, hasLength(1));
      expect(frozenDay.doses.single.amountEntered, '2');

      final naiveDay = await repositories.protocols.protocolDay(naiveRecompute);
      expect(naiveDay.doses, isEmpty);
    });
  });

  group('protocols Compound favourites', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('a new Compound defaults to not favourited', () async {
      final result = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Creatine',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.oral,
        ),
      );

      final compounds = await repositories.protocols.listCompounds();
      final compound = compounds.firstWhere((c) => c.id == result.compoundId);
      expect(compound.isFavorite, isFalse);
    });

    test('setFavorite toggles the flag and writes one Activity Log batch',
        () async {
      final created = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Creatine',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.oral,
        ),
      );

      await repositories.protocols.setFavorite(
        created.compoundId,
        isFavorite: true,
      );

      var compounds = await repositories.protocols.listCompounds();
      expect(
        compounds.firstWhere((c) => c.id == created.compoundId).isFavorite,
        isTrue,
      );

      final entries = await repositories.activityLog.listEntries();
      final favoriteEntry = entries.firstWhere(
        (e) =>
            e.entityId == created.compoundId &&
            e.afterImage?['is_favorite'] == true,
      );
      expect(favoriteEntry.beforeImage?['is_favorite'], isFalse);

      await repositories.protocols.setFavorite(
        created.compoundId,
        isFavorite: false,
      );
      compounds = await repositories.protocols.listCompounds();
      expect(
        compounds.firstWhere((c) => c.id == created.compoundId).isFavorite,
        isFalse,
      );
    });

    test('setFavorite is a no-op when already at the requested value',
        () async {
      final created = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Creatine',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.oral,
        ),
      );
      final beforeEntryCount =
          (await repositories.activityLog.listEntries()).length;

      await repositories.protocols.setFavorite(
        created.compoundId,
        isFavorite: false,
      );

      final afterEntryCount =
          (await repositories.activityLog.listEntries()).length;
      expect(afterEntryCount, beforeEntryCount);
    });

    test('watchCompounds re-emits a Compound\'s isFavorite change', () async {
      final created = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Creatine',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.oral,
        ),
      );

      final states = <bool>[];
      final subscription = repositories.protocols.watchCompounds().listen((
        compounds,
      ) {
        final match =
            compounds.where((c) => c.id == created.compoundId).firstOrNull;
        if (match != null) {
          states.add(match.isFavorite);
        }
      });
      addTearDown(subscription.cancel);

      await repositories.protocols.setFavorite(
        created.compoundId,
        isFavorite: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(states, contains(true));
    });

    test('watchCompoundOptions ignores non-label Compound edits', () async {
      final created = await repositories.protocols.createCompound(
        CompoundDraft(
          name: 'Creatine',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('5 g/capsule'),
        ),
      );

      final emissions = <List<CompoundOptionRecord>>[];
      final subscription =
          repositories.protocols.watchCompoundOptions().listen(emissions.add);
      addTearDown(subscription.cancel);

      await _waitFor(() => emissions.isNotEmpty);
      expect(emissions.last.single.id, created.compoundId);
      expect(emissions.last.single.name, 'Creatine');

      emissions.clear();
      await repositories.protocols.setFavorite(
        created.compoundId,
        isFavorite: true,
      );
      await pumpEventQueue(times: 5);
      expect(emissions, isEmpty);

      await repositories.protocols.editCompound(
        created.compoundId,
        CompoundDraft(
          name: 'Creatine',
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.sublingual,
          strength: CompoundStrength.parse('5000 mg/capsule'),
        ),
      );
      await pumpEventQueue(times: 5);
      expect(emissions, isEmpty);

      await repositories.protocols.editCompound(
        created.compoundId,
        CompoundDraft(
          name: 'Creatine monohydrate',
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.sublingual,
          strength: CompoundStrength.parse('5000 mg/capsule'),
        ),
      );
      await _waitFor(
        () => emissions.any(
          (options) => options.single.name == 'Creatine monohydrate',
        ),
      );
    });

    test('watchCompoundNamesByIds ignores unrelated Compound changes',
        () async {
      final creatine = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Creatine',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.oral,
        ),
      );
      final vitaminD = await repositories.protocols.createCompound(
        CompoundDraft(
          name: 'Vitamin D',
          defaultUnit: DoseUnit.internationalUnit,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('1000 IU/capsule'),
        ),
      );
      final unrelated = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Magnesium',
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
        ),
      );

      final emissions = <Map<String, String>>[];
      final subscription = repositories.protocols.watchCompoundNamesByIds(
        <String>{creatine.compoundId, vitaminD.compoundId},
      ).listen(emissions.add);
      addTearDown(subscription.cancel);

      await _waitFor(() => emissions.isNotEmpty);
      expect(
        emissions.last,
        <String, String>{
          creatine.compoundId: 'Creatine',
          vitaminD.compoundId: 'Vitamin D',
        },
      );

      emissions.clear();
      await repositories.protocols.editCompound(
        unrelated.compoundId,
        const CompoundDraft(
          name: 'Magnesium glycinate',
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
        ),
      );
      await pumpEventQueue(times: 5);

      expect(emissions, isEmpty);

      await repositories.protocols.editCompound(
        creatine.compoundId,
        const CompoundDraft(
          name: 'Creatine monohydrate',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.oral,
        ),
      );
      await _waitFor(
        () => emissions.any(
          (names) => names[creatine.compoundId] == 'Creatine monohydrate',
        ),
      );
    });

    test(
        'a pulled Agent Compound create, whose payload has no is_favorite, '
        'can be undone on the device', () async {
      // The Agent write has no favourite field, so the server stores no
      // `is_favorite` for a Compound it creates; the device reads it as false.
      const compoundId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c0a1';
      const batchId = 'agent-compound-batch';
      const wroteAt = '2026-06-03T07:00:00.000Z';
      final payload = <String, Object?>{
        'id': compoundId,
        'name': 'Creatine',
        'default_unit': 'gram',
        'default_route': 'oral',
        'strength': null,
        'updated_at': wroteAt,
        'deleted_at': null,
      };
      final repository = SyncRepository(
        database: database,
        apiClientFactory: (baseUrl) => PerenniaApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((request) async {
            final cursor = jsonDecode(request.body)['cursor'];
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': syncProtocolVersion,
                'nextCursor': 'cursor-agent-compound',
                'serverClock': '2026-06-03T08:00:00.000Z',
                'changes': cursor == null
                    ? <Object?>[
                        <String, Object?>{
                          'entity': AppDatabase.compoundsTable,
                          'id': compoundId,
                          'deviceId': 'agent-device',
                          'payload': payload,
                          'updatedAt': wroteAt,
                          'deletedAt': null,
                          'activityLogId':
                              'agent:$batchId:compound:$compoundId',
                          'actor': 'agent',
                          'batchId': batchId,
                          'beforeImage': null,
                          'afterImage': payload,
                          'occurredAt': wroteAt,
                        },
                      ]
                    : <Object?>[],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        ),
      );
      await repository.pullLoggedSetChanges(
        session: AuthSession(
          provider: AuthSessionProvider.email,
          serverUrl: Uri.parse('https://sync.example/'),
          token: 'session-token',
          userEmail: 'user@example.com',
          userId: 'user-1',
          userName: 'Sync User',
        ),
        deviceId: 'device-a',
      );
      final pulled = (await repositories.protocols.listCompounds())
          .singleWhere((compound) => compound.id == compoundId);
      expect(pulled.isFavorite, isFalse);

      final undo = await repositories.activityLog.undoBatch(batchId);

      // The device's image carries `is_favorite: false`; the Agent's
      // after-image has no such key, and undo must still find it current.
      expect(undo.conflicts, isEmpty);
      expect(
        undo.appliedEntries.map((entry) => entry.entityId),
        <String>[compoundId],
      );
      final row = await (database.select(database.compounds)
            ..where((compound) => compound.id.equals(compoundId)))
          .getSingle();
      expect(row.deletedAt, isNotNull);
    });
  });

  group('protocols recent Compounds (derived-never-stored)', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('recentCompounds orders by each Compound\'s most recent Dose',
        () async {
      final creatine = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Creatine',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.oral,
        ),
      );
      final vitaminD = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Vitamin D',
          defaultUnit: DoseUnit.internationalUnit,
          defaultRoute: DoseRoute.oral,
        ),
      );
      // Untouched Compound: no Dose logged, so it never appears in recents.
      await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Never Logged',
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
        ),
      );

      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatine.compoundId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 28, 8),
        ),
      );
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: vitaminD.compoundId,
          compoundName: 'Vitamin D',
          amountValue: 1,
          amountEntered: '1',
          unit: DoseUnit.internationalUnit,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 8),
        ),
      );

      final recent = await repositories.protocols.recentCompounds();
      final recentIds = await repositories.protocols.recentCompoundIds();

      expect(recent.map((c) => c.name), <String>['Vitamin D', 'Creatine']);
      expect(recentIds, <String>[vitaminD.compoundId, creatine.compoundId]);
    });

    test('an archived Compound drops out of recents even with recent Doses',
        () async {
      final creatine = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Creatine',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.oral,
        ),
      );
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatine.compoundId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 8),
        ),
      );

      await repositories.protocols.archiveCompound(creatine.compoundId);

      final recent = await repositories.protocols.recentCompounds();
      final recentIds = await repositories.protocols.recentCompoundIds();
      expect(recent, isEmpty);
      expect(recentIds, isEmpty);
    });

    test('watchRecentCompounds re-emits when a new Dose is logged', () async {
      final creatine = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Creatine',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.oral,
        ),
      );

      final emissions = <List<String>>[];
      final subscription =
          repositories.protocols.watchRecentCompounds().listen((compounds) {
        emissions.add(compounds.map((c) => c.name).toList());
      });
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);

      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatine.compoundId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 8),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emissions.last, <String>['Creatine']);
    });

    test(
      'watchRecentCompoundIds re-emits for Dose recency but ignores Compound details',
      () async {
        final creatine = await repositories.protocols.createCompound(
          const CompoundDraft(
            name: 'Creatine',
            defaultUnit: DoseUnit.gram,
            defaultRoute: DoseRoute.oral,
          ),
        );

        final emissions = <List<String>>[];
        final subscription = repositories.protocols
            .watchRecentCompoundIds()
            .listen(emissions.add);
        addTearDown(subscription.cancel);
        await Future<void>.delayed(Duration.zero);

        await repositories.protocols.logDose(
          DoseSnapshotDraft(
            compoundId: creatine.compoundId,
            compoundName: 'Creatine',
            amountValue: 5,
            amountEntered: '5',
            unit: DoseUnit.gram,
            route: DoseRoute.oral,
            tookAt: DateTime.utc(2026, 6, 30, 8),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(emissions.last, <String>[creatine.compoundId]);

        final emissionCount = emissions.length;
        await repositories.protocols.setFavorite(
          creatine.compoundId,
          isFavorite: true,
        );
        await Future<void>.delayed(Duration.zero);

        expect(emissions, hasLength(emissionCount));
      },
    );
  });

  group('protocols last Dose prefill (derived-never-stored)', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('lastDoseFor returns null for a Compound with no prior Dose',
        () async {
      final vitaminD = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Vitamin D',
          defaultUnit: DoseUnit.internationalUnit,
          defaultRoute: DoseRoute.oral,
        ),
      );

      final lastDose =
          await repositories.protocols.lastDoseFor(vitaminD.compoundId);

      expect(lastDose, isNull);
    });

    test('lastDoseFor returns the most recently logged Dose for that Compound',
        () async {
      final creatine = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Creatine',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.oral,
        ),
      );
      // A different Compound's Dose must never leak into this Compound's
      // prefill.
      final vitaminD = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Vitamin D',
          defaultUnit: DoseUnit.internationalUnit,
          defaultRoute: DoseRoute.oral,
        ),
      );
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: vitaminD.compoundId,
          compoundName: 'Vitamin D',
          amountValue: 1,
          amountEntered: '1',
          unit: DoseUnit.internationalUnit,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 29, 8),
        ),
      );
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatine.compoundId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 28, 8),
        ),
      );
      final latest = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatine.compoundId,
          compoundName: 'Creatine',
          amountValue: 10,
          amountEntered: '10',
          unit: DoseUnit.gram,
          route: DoseRoute.sublingual,
          tookAt: DateTime.utc(2026, 6, 30, 8),
        ),
      );

      final lastDose =
          await repositories.protocols.lastDoseFor(creatine.compoundId);

      expect(lastDose, isNotNull);
      expect(lastDose!.id, latest.doseId);
      expect(lastDose.amountValue, 10);
      expect(lastDose.unit, DoseUnit.gram);
      expect(lastDose.route, DoseRoute.sublingual);
    });

    test('lastDoseFor excludes a tombstoned (deleted) Dose', () async {
      final creatine = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Creatine',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.oral,
        ),
      );
      final logged = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatine.compoundId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 8),
        ),
      );

      await repositories.protocols.deleteDose(logged.doseId);

      final lastDose =
          await repositories.protocols.lastDoseFor(creatine.compoundId);
      expect(lastDose, isNull);
    });

    test('watchLastDose re-emits when a new Dose logs for that Compound',
        () async {
      final creatine = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Creatine',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.oral,
        ),
      );

      final emissions = <double?>[];
      final subscription = repositories.protocols
          .watchLastDose(creatine.compoundId)
          .listen((dose) {
        emissions.add(dose?.amountValue);
      });
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);

      expect(emissions.last, isNull);

      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatine.compoundId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 8),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emissions.last, 5);
    });
  });

  // the `Protocol` plan-layer entity (PROTOCOLS.md §1.4) — a named,
  // time-bounded course grouping one or more Compounds (a stack). A MUTABLE
  // PLAN: creating/editing it never reads or writes a logged Dose. Schedules,
  // target outcomes, the Dose tag, and sync are later M28 slices.
  group('Protocol (plan-layer entity)', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    Future<String> createCompoundId(String name) async {
      final result = await repositories.protocols.createCompound(
        CompoundDraft(
          name: name,
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
        ),
      );
      return result.compoundId;
    }

    test('watchProtocol ignores unrelated Protocol plan changes', () async {
      final creatineId = await createCompoundId('Creatine');
      final magnesiumId = await createCompoundId('Magnesium');
      final watched = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
        ),
      );
      final unrelated = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Recovery',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[magnesiumId],
        ),
      );

      final emissions = <ProtocolRecord?>[];
      final subscription = repositories.protocols
          .watchProtocol(watched.protocolId)
          .listen(emissions.add);
      addTearDown(subscription.cancel);
      await _waitFor(() => emissions.isNotEmpty);
      expect(emissions.single?.name, 'Lean bulk');
      final initialEmissionCount = emissions.length;

      await repositories.protocols.editProtocol(
        unrelated.protocolId,
        ProtocolDraft(
          name: 'Recovery',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[magnesiumId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            magnesiumId: ScheduleDraft(
              rule: _onceDaily,
              doseAmountValue: 400,
              doseAmountEntered: '400',
              doseUnit: DoseUnit.milligram,
              route: DoseRoute.oral,
            ),
          },
        ),
      );
      await pumpEventQueue(times: 5);

      expect(emissions, hasLength(initialEmissionCount));

      await repositories.protocols.editProtocol(
        watched.protocolId,
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            creatineId: ScheduleDraft(
              rule: _onceDaily,
              doseAmountValue: 5,
              doseAmountEntered: '5',
              doseUnit: DoseUnit.gram,
              route: DoseRoute.oral,
            ),
          },
        ),
      );

      await _waitFor(() => emissions.length > initialEmissionCount);
      expect(emissions.last?.members.single.currentVersion, isNotNull);
    });

    test('opens a Protocol/ProtocolCompound schema with no archive flag column',
        () async {
      final columnsByTable = await database.describeSchema();

      expect(
        columnsByTable.keys,
        containsAll(<String>[
          AppDatabase.protocolsTable,
          AppDatabase.protocolCompoundsTable,
        ]),
      );
      expect(
        columnsByTable[AppDatabase.protocolsTable],
        containsAll(<String>[
          'id',
          'name',
          'start_local_date',
          'end_local_date',
          'period',
          'reminders_enabled',
          'archived_on',
          'updated_at',
          'deleted_at',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.protocolsTable],
        isNot(contains(anyOf('start_date', 'end_date'))),
      );
      expect(
        columnsByTable[AppDatabase.protocolCompoundsTable],
        containsAll(<String>[
          'id',
          'protocol_id',
          'compound_id',
          'position',
          'archived_on',
          'updated_at',
          'deleted_at',
        ]),
      );
      // Archive is the deletedAt tombstone, not a separate flag (mirrors
      // Compound/Exercise/Food): `archived_on` only freezes the archive's
      // local date beside it.
      expect(
        columnsByTable[AppDatabase.protocolsTable]!
            .where((c) => c.contains('archiv'))
            .toList(),
        <String>['archived_on'],
      );
    });

    test('creates a named, time-bounded Protocol with one Compound', () async {
      final creatineId = await createCompoundId('Creatine');
      const startDate = ProtocolDayDate(year: 2026, month: 7, day: 1);
      const endDate = ProtocolDayDate(year: 2026, month: 9, day: 1);

      final result = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: startDate,
          endLocalDate: endDate,
          compoundIds: <String>[creatineId],
        ),
      );

      final protocols = await repositories.protocols.listProtocols();
      expect(protocols, hasLength(1));
      final protocol = protocols.single;
      expect(protocol.id, result.protocolId);
      expect(protocol.name, 'Lean bulk');
      // Local dates, stored and read back as written: no instant, so no
      // timezone can move them.
      expect(protocol.startLocalDate, startDate);
      expect(protocol.endLocalDate, endDate);
      expect(protocol.period, isNull);
      expect(protocol.remindersEnabled, isFalse);
      expect(protocol.isArchived, isFalse);
      expect(protocol.isStack, isFalse);
      expect(protocol.members, hasLength(1));
      expect(protocol.members.single.compoundId, creatineId);
      expect(protocol.members.single.position, 0);
    });

    test('a multi-Compound Protocol is a stack, ordered by position', () async {
      final creatineId = await createCompoundId('Creatine');
      final vitaminDId = await createCompoundId('Vitamin D');
      final magnesiumId = await createCompoundId('Magnesium');

      final result = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Off-season stack',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId, vitaminDId, magnesiumId],
        ),
      );

      final protocol = (await repositories.protocols.listProtocols())
          .firstWhere((p) => p.id == result.protocolId);
      expect(protocol.isStack, isTrue);
      expect(protocol.endLocalDate, isNull); // open-ended (ongoing) course
      expect(
        protocol.members.map((m) => m.compoundId),
        <String>[creatineId, vitaminDId, magnesiumId],
      );
      expect(protocol.members.map((m) => m.position), <int>[0, 1, 2]);
    });

    test('creating a Protocol requires at least one Compound', () async {
      await expectLater(
        () => repositories.protocols.createProtocol(
          ProtocolDraft(
            name: 'Empty',
            startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
            compoundIds: const <String>[],
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(await repositories.protocols.listProtocols(), isEmpty);
    });

    test('creating a Protocol requires a non-empty name', () async {
      final creatineId = await createCompoundId('Creatine');
      await expectLater(
        () => repositories.protocols.createProtocol(
          ProtocolDraft(
            name: '   ',
            startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
            compoundIds: <String>[creatineId],
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('creating a Protocol rejects an end date before the start date',
        () async {
      final creatineId = await createCompoundId('Creatine');
      await expectLater(
        () => repositories.protocols.createProtocol(
          ProtocolDraft(
            name: 'Backwards window',
            startLocalDate: const ProtocolDayDate(year: 2026, month: 9, day: 1),
            endLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
            compoundIds: <String>[creatineId],
          ),
        ),
        // The shared plan validator's `bounds_order` (D7).
        throwsA(
          isA<DoseValidationException>().having(
            (error) => error.errors.map((issue) => issue.rule),
            'rules',
            <String>['bounds_order'],
          ),
        ),
      );

      expect(await repositories.protocols.listProtocols(), isEmpty);
    });

    test('creating a Protocol rejects a Compound id that does not exist',
        () async {
      await expectLater(
        () => repositories.protocols.createProtocol(
          ProtocolDraft(
            name: 'Ghost stack',
            startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
            compoundIds: const <String>['missing-compound'],
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('creating a Protocol rejects duplicate Compound ids', () async {
      final creatineId = await createCompoundId('Creatine');
      await expectLater(
        () => repositories.protocols.createProtocol(
          ProtocolDraft(
            name: 'Doubled up',
            startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
            compoundIds: <String>[creatineId, creatineId],
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('editing a Protocol updates its name and window', () async {
      final creatineId = await createCompoundId('Creatine');
      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
        ),
      );

      const newStart = ProtocolDayDate(year: 2026, month: 8, day: 1);
      const newEnd = ProtocolDayDate(year: 2026, month: 10, day: 1);
      final period = ProtocolPeriod(
        pauses: const <ProtocolPause>[
          ProtocolPause(
            from: ProtocolDayDate(year: 2026, month: 8, day: 10),
            to: ProtocolDayDate(year: 2026, month: 8, day: 16),
          ),
        ],
      );
      await repositories.protocols.editProtocol(
        created.protocolId,
        ProtocolDraft(
          name: 'Lean bulk v2',
          startLocalDate: newStart,
          endLocalDate: newEnd,
          period: period,
          remindersEnabled: true,
          compoundIds: <String>[creatineId],
        ),
      );

      final protocol = (await repositories.protocols.listProtocols()).single;
      expect(protocol.name, 'Lean bulk v2');
      expect(protocol.startLocalDate, newStart);
      expect(protocol.endLocalDate, newEnd);
      expect(protocol.remindersEnabled, isTrue);
      expect(protocol.period!.cycle, isNull);
      expect(protocol.period!.pauses.single.from, period.pauses.single.from);
      expect(protocol.period!.pauses.single.to, period.pauses.single.to);
    });

    test('editing a Protocol supports adding and removing Compounds', () async {
      final creatineId = await createCompoundId('Creatine');
      final vitaminDId = await createCompoundId('Vitamin D');
      final magnesiumId = await createCompoundId('Magnesium');

      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Stack',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId, vitaminDId],
        ),
      );

      // Drop Vitamin D, add Magnesium, and re-order: Magnesium first.
      await repositories.protocols.editProtocol(
        created.protocolId,
        ProtocolDraft(
          name: 'Stack',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[magnesiumId, creatineId],
        ),
      );

      final protocol = (await repositories.protocols.listProtocols()).single;
      expect(
        protocol.members.map((m) => m.compoundId),
        <String>[magnesiumId, creatineId],
      );
      expect(
        protocol.members.map((m) => m.compoundId),
        isNot(contains(vitaminDId)),
      );
    });

    test('creating and editing a Protocol never reads or writes a logged Dose',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final logged = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 8),
        ),
      );
      final beforeRow = await (database.select(database.doses)
            ..where((r) => r.id.equals(logged.doseId)))
          .getSingle();

      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
        ),
      );
      await repositories.protocols.editProtocol(
        created.protocolId,
        ProtocolDraft(
          name: 'Lean bulk v2',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          endLocalDate: const ProtocolDayDate(year: 2026, month: 9, day: 1),
          compoundIds: <String>[creatineId],
        ),
      );

      // The Dose row is byte-for-byte unchanged: Protocol create/edit touched
      // only the protocols/protocol_compounds tables.
      final afterRow = await (database.select(database.doses)
            ..where((r) => r.id.equals(logged.doseId)))
          .getSingle();
      expect(afterRow.updatedAt, beforeRow.updatedAt);
      expect(afterRow.amountValue, beforeRow.amountValue);
      expect(afterRow.deletedAt, isNull);
    });

    test('a user can still log an ad-hoc Dose with no Protocol at all',
        () async {
      final result = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundName: 'Melatonin',
          amountValue: 3,
          amountEntered: '3',
          unit: DoseUnit.milligram,
          route: DoseRoute.sublingual,
          tookAt: DateTime.utc(2026, 6, 30, 21),
        ),
      );

      expect(result.doseId, isNotEmpty);
      expect(await repositories.protocols.listProtocols(), isEmpty);
    });

    test(
        'archiving a Protocol removes it from the active list but its '
        'history survives, with no cascade to a logged Dose', () async {
      final creatineId = await createCompoundId('Creatine');
      final logged = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 8),
        ),
      );
      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
        ),
      );

      await repositories.protocols.archiveProtocol(created.protocolId);

      expect(await repositories.protocols.listProtocols(), isEmpty);
      final row = await (database.select(database.protocols)
            ..where((r) => r.id.equals(created.protocolId)))
          .getSingle();
      expect(row.deletedAt, isNotNull);
      expect(row.name, 'Lean bulk');

      // No cascade: the Dose is untouched.
      final doseRow = await (database.select(database.doses)
            ..where((r) => r.id.equals(logged.doseId)))
          .getSingle();
      expect(doseRow.deletedAt, isNull);
    });

    test('creating a Protocol writes one reversible Activity Log batch',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final vitaminDId = await createCompoundId('Vitamin D');

      final result = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Stack',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId, vitaminDId],
        ),
      );

      final batchEntries = (await repositories.activityLog.listEntries())
          .where((e) => e.batchId == result.batchId)
          .toList();
      // One entry for the Protocol row plus one per member row.
      expect(batchEntries, hasLength(3));
      expect(
        batchEntries.map((e) => e.entityTable).toSet(),
        <String>{
          AppDatabase.protocolsTable,
          AppDatabase.protocolCompoundsTable,
        },
      );

      await repositories.activityLog.undoBatch(result.batchId);
      expect(await repositories.protocols.listProtocols(), isEmpty);
    });

    test('archiving a Protocol writes one reversible Activity Log batch',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
        ),
      );

      final batchId =
          await repositories.protocols.archiveProtocol(created.protocolId);

      await repositories.activityLog.undoBatch(batchId);
      expect(
        (await repositories.protocols.listProtocols()).map((p) => p.id),
        contains(created.protocolId),
      );
    });

    test('watchProtocols re-emits when a Protocol is created', () async {
      final creatineId = await createCompoundId('Creatine');
      final emissions = <int>[];
      final subscription = repositories.protocols.watchProtocols().listen(
            (protocols) => emissions.add(protocols.length),
          );
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);

      expect(emissions.last, 0);

      await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emissions.last, 1);
    });

    test('watchProtocolSummaries ignores member Schedule detail changes',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
        ),
      );

      final emissions = <List<ProtocolSummaryRecord>>[];
      final subscription =
          repositories.protocols.watchProtocolSummaries().listen(
                emissions.add,
              );
      addTearDown(subscription.cancel);
      await _waitFor(() => emissions.isNotEmpty);

      expect(emissions.single.single.id, created.protocolId);
      expect(emissions.single.single.compoundIds, <String>[creatineId]);
      final initialEmissionCount = emissions.length;

      await repositories.protocols.editProtocol(
        created.protocolId,
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            creatineId: ScheduleDraft(
              rule: _onceDaily,
              doseAmountValue: 5,
              doseAmountEntered: '5',
              doseUnit: DoseUnit.gram,
              route: DoseRoute.oral,
            ),
          },
        ),
      );
      await pumpEventQueue(times: 5);

      expect(emissions, hasLength(initialEmissionCount));

      await repositories.protocols.editProtocol(
        created.protocolId,
        ProtocolDraft(
          name: 'Lean bulk, revised',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            creatineId: ScheduleDraft(
              rule: _onceDaily,
              doseAmountValue: 5,
              doseAmountEntered: '5',
              doseUnit: DoseUnit.gram,
              route: DoseRoute.oral,
            ),
          },
        ),
      );

      await _waitFor(() => emissions.length > initialEmissionCount);
      expect(emissions.last.single.name, 'Lean bulk, revised');
    });
  });

  // the OPTIONAL `Schedule` per member Compound (PROTOCOLS.md §1.4) —
  // the `Prescription` analog: planned dose · frequency · route. Purely
  // prescriptive; a Protocol with no Schedules is still fully valid, and
  // creating/editing a Schedule never reads or writes a logged `Dose`.
  group('Schedule Versions (per-member plan history)', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    const start = ProtocolDayDate(year: 2026, month: 7, day: 1);
    // Every write below passes "today" explicitly, so a version's date never
    // depends on the machine's clock.
    const today = ProtocolDayDate(year: 2026, month: 7, day: 20);
    const tomorrow = ProtocolDayDate(year: 2026, month: 7, day: 21);

    Future<String> createCompoundId(String name) async {
      final result = await repositories.protocols.createCompound(
        CompoundDraft(
          name: name,
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
        ),
      );
      return result.compoundId;
    }

    ScheduleDraft timed(
      List<String> times, {
      String amount = '5',
      ScheduleDays days = const DailyScheduleDays(),
      DoseRoute route = DoseRoute.oral,
    }) {
      return ScheduleDraft(
        rule: TimedScheduleRule(days: days, times: times),
        doseAmountValue: double.parse(amount),
        doseAmountEntered: amount,
        doseUnit: DoseUnit.gram,
        route: route,
      );
    }

    ProtocolDraft draft(
      List<String> compoundIds, {
      Map<String, ScheduleDraft?> schedules = const <String, ScheduleDraft?>{},
      ProtocolDayDate startLocalDate = start,
      ProtocolPeriod? period,
    }) {
      return ProtocolDraft(
        name: 'Daily',
        startLocalDate: startLocalDate,
        period: period,
        compoundIds: compoundIds,
        schedulesByCompoundId: schedules,
      );
    }

    Future<ProtocolMemberRecord> memberOf(
      String protocolId,
      String compoundId,
    ) async {
      final protocol = (await repositories.protocols.listProtocols())
          .singleWhere((protocol) => protocol.id == protocolId);
      return protocol.members
          .singleWhere((member) => member.compoundId == compoundId);
    }

    Future<List<ScheduleRow>> versionRows({String? memberId}) {
      final query = database.select(database.schedules)
        ..orderBy([
          (row) => OrderingTerm.asc(row.effectiveFrom),
          (row) => OrderingTerm.asc(row.id),
        ]);
      if (memberId != null) {
        query.where((row) => row.protocolCompoundId.equals(memberId));
      }
      return query.get();
    }

    Future<ProtocolCompoundRow> memberRow(String compoundId) {
      return (database.select(database.protocolCompounds)
            ..where((row) => row.compoundId.equals(compoundId)))
          .getSingle();
    }

    test('stores one Schedule Version per row, with no frequency column',
        () async {
      final columnsByTable = await database.describeSchema();

      expect(
        columnsByTable[AppDatabase.schedulesTable],
        <String>{
          'id',
          'protocol_compound_id',
          'effective_from',
          'rule',
          'dose_amount_value',
          'dose_amount_entered',
          'dose_unit',
          'route',
          'sync_device_id',
          'sync_previously_synced',
          'updated_at',
          'deleted_at',
        },
      );
    });

    test('a Protocol with no Schedules at all is still valid', () async {
      final creatineId = await createCompoundId('Creatine');
      final result = await repositories.protocols.createProtocol(
        draft(<String>[creatineId]),
        today: today,
      );

      final member = await memberOf(result.protocolId, creatineId);
      expect(member.currentVersion, isNull);
      expect(member.versionInEffectToday, isNull);
      expect(await versionRows(), isEmpty);
    });

    test(
        "a member created with its Protocol plans from the Protocol's start, "
        'even a start in the past', () async {
      final creatineId = await createCompoundId('Creatine');
      final vitaminDId = await createCompoundId('Vitamin D');

      final result = await repositories.protocols.createProtocol(
        draft(
          <String>[creatineId, vitaminDId],
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['09:00']),
          },
        ),
        today: today,
      );

      final creatine = await memberOf(result.protocolId, creatineId);
      final version = creatine.currentVersion!;
      expect(version.effectiveFrom, start);
      expect((version.rule as TimedScheduleRule).times, <String>['09:00']);
      expect(version.doseAmountValue, 5);
      expect(version.doseAmountEntered, '5');
      expect(version.doseUnit, DoseUnit.gram);
      expect(version.route, DoseRoute.oral);
      // Vitamin D carries no Schedule — optional, and still a valid member.
      expect((await memberOf(result.protocolId, vitaminDId)).currentVersion,
          isNull);
    });

    test('a changed edit inserts a new version dated today and edits nothing',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final created = await repositories.protocols.createProtocol(
        draft(
          <String>[creatineId],
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['09:00']),
          },
        ),
        today: today,
      );
      final original = (await versionRows()).single;

      await repositories.protocols.editProtocol(
        created.protocolId,
        draft(
          <String>[creatineId],
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['07:00'], amount: '10'),
          },
        ),
        today: today,
      );

      final rows = await versionRows();
      expect(rows, hasLength(2));
      // The first version is untouched: same id, same content, same stamp.
      expect(rows.first.id, original.id);
      expect(rows.first.rule, original.rule);
      expect(rows.first.doseAmountEntered, '5');
      expect(rows.first.updatedAt, original.updatedAt);
      expect(rows.last.effectiveFrom, today.storageValue);
      expect(rows.last.doseAmountEntered, '10');

      final member = await memberOf(created.protocolId, creatineId);
      expect(member.currentVersion!.id, rows.last.id);
      expect(
        (member.currentVersion!.rule as TimedScheduleRule).times,
        <String>['07:00'],
      );
    });

    test('two changed edits on the same day insert two versions', () async {
      final creatineId = await createCompoundId('Creatine');
      final created = await repositories.protocols.createProtocol(
        draft(
          <String>[creatineId],
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['09:00']),
          },
        ),
        today: today,
      );

      for (final time in <String>['08:00', '07:00']) {
        await repositories.protocols.editProtocol(
          created.protocolId,
          draft(
            <String>[creatineId],
            schedules: <String, ScheduleDraft?>{
              creatineId: timed(<String>[time]),
            },
          ),
          today: today,
        );
      }

      final rows = await versionRows();
      expect(rows, hasLength(3));
      expect(
        rows.skip(1).map((row) => row.effectiveFrom),
        <String>[today.storageValue, today.storageValue],
      );
      // Same date: the larger id, the later edit, wins.
      final member = await memberOf(created.protocolId, creatineId);
      expect(member.currentVersion!.id, rows.last.id);
      expect(
        (member.currentVersion!.rule as TimedScheduleRule).times,
        <String>['07:00'],
      );
    });

    test('an unchanged save inserts no version and logs no Schedule entry',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final created = await repositories.protocols.createProtocol(
        draft(
          <String>[creatineId],
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['09:00']),
          },
        ),
        today: today,
      );

      final batchId = await repositories.protocols.editProtocol(
        created.protocolId,
        draft(
          <String>[creatineId],
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['09:00']),
          },
        ),
        today: tomorrow,
      );

      expect(await versionRows(), hasLength(1));
      expect(
        (await repositories.activityLog.listEntries())
            .where((entry) => entry.batchId == batchId),
        isEmpty,
      );
    });

    test(
        'a rule and period stored with their keys in another order (an Agent '
        'write, pulled from jsonb) still save as unchanged', () async {
      final creatineId = await createCompoundId('Creatine');
      final period = ProtocolPeriod(
        cycle: ProtocolCycle(
          onDays: 60,
          offDays: 30,
          anchor: start,
          anchorIsDefault: true,
        ),
      );
      ProtocolDraft unchanged() => draft(
            <String>[creatineId],
            period: period,
            schedules: <String, ScheduleDraft?>{
              creatineId: timed(<String>['09:00']),
            },
          );
      final created = await repositories.protocols.createProtocol(
        unchanged(),
        today: today,
      );
      // Postgres jsonb orders keys by length, then bytes; a pull re-encodes
      // the object in that order.
      await database.update(database.schedules).write(
            const SchedulesCompanion(
              rule: Value<String>(
                '{"v":1,"days":{"kind":"daily"},"kind":"timed",'
                '"times":["09:00"]}',
              ),
            ),
          );
      await (database.update(database.protocols)
            ..where((row) => row.id.equals(created.protocolId)))
          .write(
        const ProtocolsCompanion(
          period: Value<String?>(
            '{"v":1,"cycle":{"anchor":"2026-07-01","on_days":60,'
            '"off_days":30,"anchor_is_default":true},"pauses":[]}',
          ),
        ),
      );
      final protocolBefore = await (database.select(database.protocols)
            ..where((row) => row.id.equals(created.protocolId)))
          .getSingle();

      final batchId = await repositories.protocols.editProtocol(
        created.protocolId,
        unchanged(),
        today: tomorrow,
      );

      expect(await versionRows(), hasLength(1));
      final protocolAfter = await (database.select(database.protocols)
            ..where((row) => row.id.equals(created.protocolId)))
          .getSingle();
      expect(protocolAfter.updatedAt, protocolBefore.updatedAt);
      expect(protocolAfter.period, protocolBefore.period);
      expect(
        (await repositories.activityLog.listEntries())
            .where((entry) => entry.batchId == batchId),
        isEmpty,
      );
    });

    test(
        'a period whose default cycle anchor stores another date (an Agent '
        'write) still saves as unchanged: the anchor reads as the start (D4)',
        () async {
      final creatineId = await createCompoundId('Creatine');
      ProtocolDraft unchanged() => draft(
            <String>[creatineId],
            period: ProtocolPeriod(
              cycle: ProtocolCycle(
                onDays: 60,
                offDays: 30,
                anchor: start,
                anchorIsDefault: true,
              ),
            ),
            schedules: <String, ScheduleDraft?>{
              creatineId: timed(<String>['09:00']),
            },
          );
      final created = await repositories.protocols.createProtocol(
        unchanged(),
        today: today,
      );
      // An Agent stored a default anchor dated before the start; it is
      // never read, since a default anchor plans from the start.
      await (database.update(database.protocols)
            ..where((row) => row.id.equals(created.protocolId)))
          .write(
        const ProtocolsCompanion(
          period: Value<String?>(
            '{"v":1,"cycle":{"on_days":60,"off_days":30,'
            '"anchor":"2026-06-01","anchor_is_default":true},"pauses":[]}',
          ),
        ),
      );
      final protocolBefore = await (database.select(database.protocols)
            ..where((row) => row.id.equals(created.protocolId)))
          .getSingle();

      final batchId = await repositories.protocols.editProtocol(
        created.protocolId,
        unchanged(),
        today: tomorrow,
      );

      final protocolAfter = await (database.select(database.protocols)
            ..where((row) => row.id.equals(created.protocolId)))
          .getSingle();
      expect(protocolAfter.updatedAt, protocolBefore.updatedAt);
      expect(protocolAfter.period, protocolBefore.period);
      expect(
        (await repositories.activityLog.listEntries())
            .where((entry) => entry.batchId == batchId),
        isEmpty,
      );
    });

    test(
        'a member added mid-course plans from today; one added before the '
        'start plans from the start', () async {
      final creatineId = await createCompoundId('Creatine');
      final vitaminDId = await createCompoundId('Vitamin D');
      final magnesiumId = await createCompoundId('Magnesium');
      final started = await repositories.protocols.createProtocol(
        draft(<String>[creatineId]),
        today: today,
      );
      const futureStart = ProtocolDayDate(year: 2026, month: 8, day: 1);
      final upcoming = await repositories.protocols.createProtocol(
        draft(<String>[creatineId], startLocalDate: futureStart),
        today: today,
      );

      await repositories.protocols.editProtocol(
        started.protocolId,
        draft(
          <String>[creatineId, vitaminDId],
          schedules: <String, ScheduleDraft?>{
            vitaminDId: timed(<String>['09:00']),
          },
        ),
        today: today,
      );
      await repositories.protocols.editProtocol(
        upcoming.protocolId,
        draft(
          <String>[creatineId, magnesiumId],
          startLocalDate: futureStart,
          schedules: <String, ScheduleDraft?>{
            magnesiumId: timed(<String>['21:00']),
          },
        ),
        today: today,
      );

      expect(
        (await memberOf(started.protocolId, vitaminDId))
            .currentVersion!
            .effectiveFrom,
        today,
      );
      final magnesium = await memberOf(upcoming.protocolId, magnesiumId);
      expect(magnesium.currentVersion!.effectiveFrom, futureStart);
    });

    test(
        'an edit while the start is still ahead is dated from the start, and '
        'the editor reads it as the current version', () async {
      final creatineId = await createCompoundId('Creatine');
      // Reads judge "today" by the device clock, so this test does too.
      final realToday = ProtocolDayDate.fromDateTime(DateTime.now());
      final futureStart = realToday.addDays(30);
      final created = await repositories.protocols.createProtocol(
        draft(
          <String>[creatineId],
          startLocalDate: futureStart,
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['09:00']),
          },
        ),
        today: realToday,
      );

      await repositories.protocols.editProtocol(
        created.protocolId,
        draft(
          <String>[creatineId],
          startLocalDate: futureStart,
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['07:00']),
          },
        ),
        today: realToday,
      );

      final rows = await versionRows();
      expect(rows, hasLength(2));
      // max(today, the latest effective_from): never behind the first one.
      expect(rows.last.effectiveFrom, futureStart.storageValue);
      final member = await memberOf(created.protocolId, creatineId);
      expect(member.currentVersion!.id, rows.last.id);
      expect(member.versionInEffectToday, isNull);
    });

    test(
        'a null draft inserts an unscheduled version, and inserts nothing for '
        'a member with no versions', () async {
      final creatineId = await createCompoundId('Creatine');
      final vitaminDId = await createCompoundId('Vitamin D');
      final created = await repositories.protocols.createProtocol(
        draft(
          <String>[creatineId, vitaminDId],
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['09:00']),
          },
        ),
        today: today,
      );

      await repositories.protocols.editProtocol(
        created.protocolId,
        draft(
          <String>[creatineId, vitaminDId],
          schedules: <String, ScheduleDraft?>{
            creatineId: null,
            vitaminDId: null,
          },
        ),
        today: today,
      );

      final creatineRows =
          await versionRows(memberId: (await memberRow(creatineId)).id);
      expect(creatineRows, hasLength(2));
      final cleared = creatineRows.last;
      expect(cleared.effectiveFrom, today.storageValue);
      expect(
        jsonDecode(cleared.rule),
        <String, Object?>{'v': 1, 'kind': 'unscheduled'},
      );
      expect(cleared.doseAmountValue, isNull);
      expect(cleared.doseAmountEntered, isNull);
      expect(cleared.doseUnit, isNull);
      expect(cleared.route, isNull);
      expect(
        (await memberOf(created.protocolId, creatineId)).currentVersion!.rule,
        isA<UnscheduledScheduleRule>(),
      );
      expect(
        await versionRows(memberId: (await memberRow(vitaminDId)).id),
        isEmpty,
      );
    });

    test(
        'removing a member archives it with a frozen archived_on and leaves '
        'its versions', () async {
      final creatineId = await createCompoundId('Creatine');
      final vitaminDId = await createCompoundId('Vitamin D');
      final created = await repositories.protocols.createProtocol(
        draft(
          <String>[creatineId, vitaminDId],
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['09:00']),
          },
        ),
        today: today,
      );

      await repositories.protocols.editProtocol(
        created.protocolId,
        draft(<String>[vitaminDId]),
        today: today,
      );

      final protocol = (await repositories.protocols.listProtocols()).single;
      expect(protocol.members.single.compoundId, vitaminDId);
      final removed = await memberRow(creatineId);
      expect(removed.deletedAt, isNotNull);
      expect(removed.archivedOn, today.storageValue);
      final rows = await versionRows(memberId: removed.id);
      expect(rows, hasLength(1));
      expect(rows.single.deletedAt, isNull);
    });

    test('archiving a Protocol freezes archived_on and keeps its versions',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final created = await repositories.protocols.createProtocol(
        draft(
          <String>[creatineId],
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['09:00']),
          },
        ),
        today: today,
      );

      await repositories.protocols.archiveProtocol(
        created.protocolId,
        today: today,
      );

      final row = await database.select(database.protocols).getSingle();
      expect(row.deletedAt, isNotNull);
      expect(row.archivedOn, today.storageValue);
      expect((await versionRows()).single.deletedAt, isNull);
      expect((await memberRow(creatineId)).deletedAt, isNull);
    });

    test('editing or archiving an archived Protocol throws', () async {
      final creatineId = await createCompoundId('Creatine');
      final created = await repositories.protocols.createProtocol(
        draft(
          <String>[creatineId],
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['09:00']),
          },
        ),
        today: today,
      );
      await repositories.protocols.archiveProtocol(
        created.protocolId,
        today: today,
      );
      final archived = await database.select(database.protocols).getSingle();

      await expectLater(
        repositories.protocols.archiveProtocol(
          created.protocolId,
          today: today.addDays(3),
        ),
        throwsStateError,
      );
      await expectLater(
        repositories.protocols.editProtocol(
          created.protocolId,
          draft(
            <String>[creatineId],
            schedules: <String, ScheduleDraft?>{
              creatineId: timed(<String>['07:00']),
            },
          ),
          today: today,
        ),
        throwsStateError,
      );

      final row = await database.select(database.protocols).getSingle();
      expect(row.archivedOn, archived.archivedOn);
      expect(row.deletedAt, archived.deletedAt);
      expect(row.updatedAt, archived.updatedAt);
    });

    test('undoing an edit tombstones the version it inserted', () async {
      final creatineId = await createCompoundId('Creatine');
      final created = await repositories.protocols.createProtocol(
        draft(
          <String>[creatineId],
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['09:00']),
          },
        ),
        today: today,
      );
      final batchId = await repositories.protocols.editProtocol(
        created.protocolId,
        draft(
          <String>[creatineId],
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['07:00']),
          },
        ),
        today: today,
      );

      await repositories.activityLog.undoBatch(batchId);

      final rows = await versionRows();
      expect(rows, hasLength(2));
      expect(rows.first.deletedAt, isNull);
      expect(rows.last.deletedAt, isNotNull);
      final member = await memberOf(created.protocolId, creatineId);
      expect(member.currentVersion!.id, rows.first.id);
    });

    test(
        'unsorted times and weekdays are stored sorted, and an as-needed '
        'draft stores no amount', () async {
      final creatineId = await createCompoundId('Creatine');
      final magnesiumId = await createCompoundId('Magnesium');

      await repositories.protocols.createProtocol(
        draft(
          <String>[creatineId, magnesiumId],
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(
              <String>['21:00', '09:00'],
              days: WeekdayScheduleDays(<int>[5, 1, 3]),
            ),
            magnesiumId: const ScheduleDraft(
              rule: AsNeededScheduleRule(),
              doseAmountValue: 400,
              doseAmountEntered: '400',
              doseUnit: DoseUnit.milligram,
              route: DoseRoute.oral,
            ),
          },
        ),
        today: today,
      );

      final creatine =
          (await versionRows(memberId: (await memberRow(creatineId)).id))
              .single;
      expect(jsonDecode(creatine.rule), <String, Object?>{
        'v': 1,
        'kind': 'timed',
        'days': <String, Object?>{
          'kind': 'weekdays',
          'weekdays': <Object?>[1, 3, 5],
        },
        'times': <Object?>['09:00', '21:00'],
      });
      final magnesium =
          (await versionRows(memberId: (await memberRow(magnesiumId)).id))
              .single;
      expect(
        jsonDecode(magnesium.rule),
        <String, Object?>{'v': 1, 'kind': 'as_needed'},
      );
      expect(magnesium.doseAmountValue, isNull);
      expect(magnesium.doseAmountEntered, isNull);
      expect(magnesium.doseUnit, isNull);
      expect(magnesium.route, isNull);
    });

    test('moving the start later inserts no version', () async {
      final creatineId = await createCompoundId('Creatine');
      final created = await repositories.protocols.createProtocol(
        draft(
          <String>[creatineId],
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['09:00']),
          },
        ),
        today: today,
      );
      final originals = await versionRows();

      // D1: the version that applies on the new start is already the latest
      // one dated on or before it, and the days before it read `outside`.
      const newStart = ProtocolDayDate(year: 2026, month: 7, day: 10);
      await repositories.protocols.editProtocol(
        created.protocolId,
        draft(
          <String>[creatineId],
          startLocalDate: newStart,
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['09:00']),
          },
        ),
        today: today,
      );

      final rows = await versionRows();
      expect(rows.map((row) => row.id), originals.map((row) => row.id));
      expect(rows.single.effectiveFrom, start.storageValue);
      final protocol = (await repositories.protocols.listProtocols()).single;
      expect(protocol.startLocalDate, newStart);
      expect(
        (await memberOf(created.protocolId, creatineId)).currentVersion!.id,
        rows.single.id,
      );
    });

    test(
        'after a later start move, an unchanged save of a member whose '
        'current version has a default every-N anchor inserts nothing',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final vitaminDId = await createCompoundId('Vitamin D');
      const userAnchor = ProtocolDayDate(year: 2026, month: 6, day: 2);
      final everyThreeDays = timed(
        <String>['09:00'],
        days:
            EveryNDaysScheduleDays(n: 3, anchor: start, anchorIsDefault: true),
      );
      final everyTwoDays = timed(
        <String>['21:00'],
        days: EveryNDaysScheduleDays(
          n: 2,
          anchor: userAnchor,
          anchorIsDefault: false,
        ),
      );
      final period = ProtocolPeriod(
        cycle: ProtocolCycle(
          onDays: 60,
          offDays: 30,
          anchor: start,
          anchorIsDefault: true,
        ),
      );
      final created = await repositories.protocols.createProtocol(
        draft(
          <String>[creatineId, vitaminDId],
          period: period,
          schedules: <String, ScheduleDraft?>{
            creatineId: everyThreeDays,
            vitaminDId: everyTwoDays,
          },
        ),
        today: today,
      );
      final originals = await versionRows();

      const newStart = ProtocolDayDate(year: 2026, month: 7, day: 10);
      ProtocolDraft moved() => draft(
            <String>[creatineId, vitaminDId],
            startLocalDate: newStart,
            period: period,
            schedules: <String, ScheduleDraft?>{
              creatineId: everyThreeDays,
              vitaminDId: everyTwoDays,
            },
          );
      await repositories.protocols.editProtocol(
        created.protocolId,
        moved(),
        today: today,
      );
      // A second unchanged save, as the editor sends one, still inserts
      // nothing: the stored default anchor (the old start) is never read.
      await repositories.protocols.editProtocol(
        created.protocolId,
        moved(),
        today: today,
      );

      final rows = await versionRows();
      expect(rows.map((row) => row.id), originals.map((row) => row.id));
      // The version was never edited: its default anchor still stores the
      // old start, which the core reads as the new start (D4).
      final creatineRow =
          (await versionRows(memberId: (await memberRow(creatineId)).id))
              .single;
      final storedDays = (jsonDecode(creatineRow.rule)
          as Map<String, Object?>)['days']! as Map<String, Object?>;
      expect(storedDays['anchor'], start.storageValue);
      expect(storedDays['anchor_is_default'], isTrue);

      // A changed save still inserts a version.
      await repositories.protocols.editProtocol(
        created.protocolId,
        draft(
          <String>[creatineId, vitaminDId],
          startLocalDate: newStart,
          period: period,
          schedules: <String, ScheduleDraft?>{
            creatineId: everyThreeDays,
            vitaminDId: timed(
              <String>['20:00'],
              days: EveryNDaysScheduleDays(
                n: 2,
                anchor: userAnchor,
                anchorIsDefault: false,
              ),
            ),
          },
        ),
        today: today,
      );
      expect(await versionRows(), hasLength(originals.length + 1));
    });

    test(
        "moving the start earlier inserts a copy of each member's earliest "
        'version, dated from the new start', () async {
      final creatineId = await createCompoundId('Creatine');
      final created = await repositories.protocols.createProtocol(
        draft(
          <String>[creatineId],
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['09:00']),
          },
        ),
        today: today,
      );
      await repositories.protocols.editProtocol(
        created.protocolId,
        draft(
          <String>[creatineId],
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['07:00']),
          },
        ),
        today: today,
      );

      const newStart = ProtocolDayDate(year: 2026, month: 6, day: 15);
      await repositories.protocols.editProtocol(
        created.protocolId,
        draft(
          <String>[creatineId],
          startLocalDate: newStart,
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['07:00']),
          },
        ),
        today: today,
      );

      final rows = await versionRows();
      expect(rows, hasLength(3));
      expect(rows.first.effectiveFrom, newStart.storageValue);
      // A copy of the earliest version (09:00), not of the latest.
      expect(
        (jsonDecode(rows.first.rule) as Map<String, Object?>)['times'],
        <Object?>['09:00'],
      );
      expect(rows[1].effectiveFrom, start.storageValue);
      expect(rows.last.effectiveFrom, today.storageValue);
      final member = await memberOf(created.protocolId, creatineId);
      expect(member.currentVersion!.id, rows.last.id);
    });

    test(
        'moving the start earlier copies a member planned from the old start, '
        'an archived one and one the same save removes, but not a member '
        'added mid-course or one with no versions', () async {
      final planned = await createCompoundId('Creatine');
      final archived = await createCompoundId('Magnesium');
      final removedNow = await createCompoundId('Zinc');
      final midCourse = await createCompoundId('Vitamin D');
      final unscheduled = await createCompoundId('Fish oil');
      final created = await repositories.protocols.createProtocol(
        draft(
          <String>[planned, archived, removedNow, unscheduled],
          schedules: <String, ScheduleDraft?>{
            planned: timed(<String>['09:00']),
            archived: timed(<String>['12:00']),
            removedNow: timed(<String>['18:00']),
          },
        ),
        today: today,
      );
      // Remove one member and add another mid-course, the start unchanged.
      await repositories.protocols.editProtocol(
        created.protocolId,
        draft(
          <String>[planned, removedNow, unscheduled, midCourse],
          schedules: <String, ScheduleDraft?>{
            planned: timed(<String>['09:00']),
            removedNow: timed(<String>['18:00']),
            midCourse: timed(<String>['21:00']),
          },
        ),
        today: today,
      );

      // Move the start earlier, removing another member in the same save.
      const newStart = ProtocolDayDate(year: 2026, month: 6, day: 15);
      await repositories.protocols.editProtocol(
        created.protocolId,
        draft(
          <String>[planned, unscheduled, midCourse],
          startLocalDate: newStart,
          schedules: <String, ScheduleDraft?>{
            planned: timed(<String>['09:00']),
            midCourse: timed(<String>['21:00']),
          },
        ),
        today: today,
      );

      Future<List<String>> datesOf(String compoundId) async => [
            for (final row in await versionRows(
              memberId: (await memberRow(compoundId)).id,
            ))
              row.effectiveFrom,
          ];

      final copied = <String>[newStart.storageValue, start.storageValue];
      expect(await datesOf(planned), copied);
      expect(await datesOf(archived), copied);
      expect(await datesOf(removedNow), copied);
      // A copy is of the earliest version, with its rule and amount.
      final removedRows =
          await versionRows(memberId: (await memberRow(removedNow)).id);
      expect(
        (jsonDecode(removedRows.first.rule) as Map<String, Object?>)['times'],
        <Object?>['18:00'],
      );
      expect(removedRows.first.doseAmountEntered, '5');
      // The member this save removed is archived after its copy.
      final removedMember = await memberRow(removedNow);
      expect(removedMember.deletedAt, isNotNull);
      expect(removedMember.archivedOn, today.storageValue);
      // Added mid-course: keeps its own first date. No versions: no copy.
      expect(await datesOf(midCourse), <String>[today.storageValue]);
      expect(await datesOf(unscheduled), isEmpty);
    });

    test(
        'moving the start earlier gives no copy to a member archived before '
        'its earliest version, and still gives one to a member the same save '
        'removes', () async {
      final kept = await createCompoundId('Creatine');
      final removedEarly = await createCompoundId('Magnesium');
      final removedNow = await createCompoundId('Zinc');
      // The start is still ahead, so every member's first version is dated
      // from it (D1).
      const futureStart = ProtocolDayDate(year: 2026, month: 8, day: 1);
      final created = await repositories.protocols.createProtocol(
        draft(
          <String>[kept, removedEarly, removedNow],
          startLocalDate: futureStart,
          schedules: <String, ScheduleDraft?>{
            kept: timed(<String>['09:00']),
            removedEarly: timed(<String>['12:00']),
            removedNow: timed(<String>['18:00']),
          },
        ),
        today: today,
      );
      // Removed before the start came: archived_on (today) is before its
      // earliest version (the future start), so it planned no day.
      await repositories.protocols.editProtocol(
        created.protocolId,
        draft(
          <String>[kept, removedNow],
          startLocalDate: futureStart,
          schedules: <String, ScheduleDraft?>{
            kept: timed(<String>['09:00']),
            removedNow: timed(<String>['18:00']),
          },
        ),
        today: today,
      );
      expect((await memberRow(removedEarly)).archivedOn, today.storageValue);

      // Move the start earlier, removing another member in the same save.
      await repositories.protocols.editProtocol(
        created.protocolId,
        draft(
          <String>[kept],
          schedules: <String, ScheduleDraft?>{
            kept: timed(<String>['09:00']),
          },
        ),
        today: today,
      );

      Future<List<String>> datesOf(String compoundId) async => [
            for (final row in await versionRows(
              memberId: (await memberRow(compoundId)).id,
            ))
              row.effectiveFrom,
          ];

      final copied = <String>[start.storageValue, futureStart.storageValue];
      expect(await datesOf(kept), copied);
      // Its archived_on is read as stored before the save, so the member
      // this save removes still gets its copy, and is then archived.
      expect(await datesOf(removedNow), copied);
      expect((await memberRow(removedNow)).archivedOn, today.storageValue);
      // Removed before it planned anything: no copy.
      expect(await datesOf(removedEarly), <String>[futureStart.storageValue]);
    });

    test(
        'a hard-reject throws and persists nothing — the planned amount runs '
        'the SAME shared two-tier validator as a logged Dose', () async {
      final creatineId = await createCompoundId('Creatine');

      for (final schedule in <ScheduleDraft>[
        timed(<String>['09:00'], amount: '-1'),
        ScheduleDraft(rule: _onceDaily),
        timed(<String>['09:00', '09:00']),
      ]) {
        await expectLater(
          () => repositories.protocols.createProtocol(
            draft(
              <String>[creatineId],
              schedules: <String, ScheduleDraft?>{creatineId: schedule},
            ),
            today: today,
          ),
          throwsA(isA<DoseValidationException>()),
        );
      }
      await expectLater(
        () => repositories.protocols.createProtocol(
          draft(
            <String>[creatineId],
            schedules: <String, ScheduleDraft?>{
              creatineId: timed(<String>['09:00'], amount: '-1'),
            },
          ),
          today: today,
        ),
        throwsA(
          isA<DoseValidationException>().having(
            (error) => error.errors.map((issue) => issue.rule),
            'rules',
            <String>['amount_required'],
          ),
        ),
      );

      expect(await repositories.protocols.listProtocols(), isEmpty);
      expect(await versionRows(), isEmpty);
    });

    test('creating a Schedule writes one reversible Activity Log entry',
        () async {
      final creatineId = await createCompoundId('Creatine');

      final result = await repositories.protocols.createProtocol(
        draft(
          <String>[creatineId],
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['09:00']),
          },
        ),
        today: today,
      );

      final batchEntries = (await repositories.activityLog.listEntries())
          .where((e) => e.batchId == result.batchId)
          .toList();
      final scheduleEntry = batchEntries.singleWhere(
        (e) => e.entityTable == AppDatabase.schedulesTable,
      );
      expect(scheduleEntry.beforeImage, isNull);
      expect(scheduleEntry.afterImage!['dose_amount_entered'], '5');
      expect(scheduleEntry.afterImage!['effective_from'], start.storageValue);
      expect(
        jsonDecode(scheduleEntry.afterImage!['rule']! as String),
        TimedScheduleRule(
          days: const DailyScheduleDays(),
          times: const <String>['09:00'],
        ).toJson(),
      );
      expect(scheduleEntry.afterImage, isNot(contains('frequency')));

      // Reversible: undoing the whole creation batch retires the Protocol and
      // its version together (tombstoned, never a physical row removal).
      await repositories.activityLog.undoBatch(result.batchId);
      expect(await repositories.protocols.listProtocols(), isEmpty);
      expect((await versionRows()).single.deletedAt, isNotNull);
    });

    test('creating and editing a Schedule never reads or writes a logged Dose',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final logged = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 8),
        ),
      );
      final beforeRow = await (database.select(database.doses)
            ..where((r) => r.id.equals(logged.doseId)))
          .getSingle();

      final created = await repositories.protocols.createProtocol(
        draft(
          <String>[creatineId],
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['09:00']),
          },
        ),
        today: today,
      );
      await repositories.protocols.editProtocol(
        created.protocolId,
        draft(
          <String>[creatineId],
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['09:00', '21:00'], amount: '10'),
          },
        ),
        today: today,
      );

      final afterRow = await (database.select(database.doses)
            ..where((r) => r.id.equals(logged.doseId)))
          .getSingle();
      expect(afterRow.updatedAt, beforeRow.updatedAt);
      expect(afterRow.amountValue, beforeRow.amountValue);
      expect(afterRow.deletedAt, isNull);
    });

    test('watchProtocols re-emits when a member\'s Schedule changes', () async {
      final creatineId = await createCompoundId('Creatine');
      final created = await repositories.protocols.createProtocol(
        draft(<String>[creatineId]),
        today: today,
      );

      final emissions = <bool>[];
      final subscription = repositories.protocols.watchProtocols().listen(
            (protocols) => emissions.add(
              protocols.single.members.single.currentVersion != null,
            ),
          );
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);
      expect(emissions.last, isFalse);

      await repositories.protocols.editProtocol(
        created.protocolId,
        draft(
          <String>[creatineId],
          schedules: <String, ScheduleDraft?>{
            creatineId: timed(<String>['09:00']),
          },
        ),
        today: today,
      );
      await Future<void>.delayed(Duration.zero);

      expect(emissions.last, isTrue);
    });

    test(
      'watchProtocolOptions ignores detail edits and emits on visible changes',
      () async {
        final creatineId = await createCompoundId('Creatine');
        final created = await repositories.protocols.createProtocol(
          draft(<String>[creatineId]),
          today: today,
        );

        final emissions = <List<ProtocolOptionRecord>>[];
        final subscription =
            repositories.protocols.watchProtocolOptions().listen(emissions.add);
        addTearDown(subscription.cancel);
        await Future<void>.delayed(Duration.zero);
        expect(
          emissions.map((options) => options.single.name),
          <String>['Daily'],
        );

        await repositories.protocols.editProtocol(
          created.protocolId,
          draft(
            <String>[creatineId],
            schedules: <String, ScheduleDraft?>{
              creatineId: timed(<String>['09:00']),
            },
          ),
          today: today,
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          emissions.map((options) => options.single.name),
          <String>['Daily'],
        );

        await repositories.protocols.editProtocol(
          created.protocolId,
          ProtocolDraft(
            name: 'Maintenance',
            startLocalDate: start,
            compoundIds: <String>[creatineId],
            schedulesByCompoundId: <String, ScheduleDraft?>{
              creatineId: timed(<String>['09:00']),
            },
          ),
          today: today,
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          emissions.map((options) => options.single.name),
          <String>['Daily', 'Maintenance'],
        );
      },
    );

    test('the Effect window comes from the local-date bounds', () async {
      final creatineId = await createCompoundId('Creatine');
      await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Course',
          startLocalDate: start,
          endLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 14),
          compoundIds: <String>[creatineId],
        ),
        today: today,
      );
      final protocol = (await repositories.protocols.listProtocols()).single;
      final now = DateTime.utc(2026, 8, 1);

      final window = repositories.effect.windowForProtocol(protocol, now: now);

      final offset = now.toLocal().timeZoneOffset;
      expect(
        window.duringStart.toUtc(),
        DateTime.utc(2026, 7, 1).subtract(offset),
      );
      // The end is inclusive: DURING runs to the start of the next day.
      expect(
        window.duringEnd!.toUtc(),
        DateTime.utc(2026, 7, 15).subtract(offset),
      );
    });
  });

  group('Protocol target outcomes', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    Future<String> createCompoundId(String name) async {
      final result = await repositories.protocols.createCompound(
        CompoundDraft(
          name: name,
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
        ),
      );
      return result.compoundId;
    }

    Future<String> createMetricId(String name) async {
      return repositories.metrics.createMetric(
        MetricDraft(
          name: name,
          unit: 'kilogram',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.bodyComposition,
          enabled: true,
          pinned: false,
        ),
      );
    }

    test('watchProtocolSummaries ignores target-outcome detail changes',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final weightMetricId = await createMetricId('Body Weight');
      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
        ),
      );

      final emissions = <List<ProtocolSummaryRecord>>[];
      final subscription =
          repositories.protocols.watchProtocolSummaries().listen(
                emissions.add,
              );
      addTearDown(subscription.cancel);
      await _waitFor(() => emissions.isNotEmpty);

      expect(emissions.single.single.name, 'Lean bulk');
      final initialEmissionCount = emissions.length;

      await repositories.protocols.editProtocol(
        created.protocolId,
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
          targetOutcomes: <ProtocolTargetOutcomeDraft>[
            ProtocolTargetOutcomeDraft.metric(weightMetricId),
          ],
        ),
      );
      await pumpEventQueue(times: 5);

      expect(emissions, hasLength(initialEmissionCount));
    });

    test('opens a ProtocolTargetOutcomes schema with no archive flag column',
        () async {
      final columnsByTable = await database.describeSchema();

      expect(
        columnsByTable.keys,
        contains(AppDatabase.protocolTargetOutcomesTable),
      );
      expect(
        columnsByTable[AppDatabase.protocolTargetOutcomesTable],
        containsAll(<String>[
          'id',
          'protocol_id',
          'kind',
          'metric_id',
          'position',
          'updated_at',
          'deleted_at',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.protocolTargetOutcomesTable]!
            .any((c) => c.contains('archiv')),
        isFalse,
      );
    });

    test('a Protocol with no target outcomes at all is still valid', () async {
      final creatineId = await createCompoundId('Creatine');
      final result = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
        ),
      );

      final protocol = (await repositories.protocols.listProtocols())
          .firstWhere((p) => p.id == result.protocolId);
      expect(protocol.targetOutcomes, isEmpty);
    });

    test('creating a Protocol declares a metric target outcome', () async {
      final creatineId = await createCompoundId('Creatine');
      final weightMetricId = await createMetricId('Body Weight');

      final result = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
          targetOutcomes: <ProtocolTargetOutcomeDraft>[
            ProtocolTargetOutcomeDraft.metric(weightMetricId),
          ],
        ),
      );

      final protocol = (await repositories.protocols.listProtocols())
          .firstWhere((p) => p.id == result.protocolId);
      expect(protocol.targetOutcomes, hasLength(1));
      expect(protocol.targetOutcomes.single.kind, ProtocolOutcomeKind.metric);
      expect(protocol.targetOutcomes.single.metricId, weightMetricId);
    });

    test('creating a Protocol declares a performance target outcome', () async {
      final creatineId = await createCompoundId('Creatine');

      final result = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
          targetOutcomes: <ProtocolTargetOutcomeDraft>[
            ProtocolTargetOutcomeDraft.performance,
          ],
        ),
      );

      final protocol = (await repositories.protocols.listProtocols())
          .firstWhere((p) => p.id == result.protocolId);
      expect(protocol.targetOutcomes, hasLength(1));
      expect(
        protocol.targetOutcomes.single.kind,
        ProtocolOutcomeKind.performance,
      );
      expect(protocol.targetOutcomes.single.metricId, isNull);
    });

    test('a Protocol may declare multiple target outcomes, ordered', () async {
      final creatineId = await createCompoundId('Creatine');
      final weightMetricId = await createMetricId('Body Weight');
      final sleepMetricId = await createMetricId('Sleep');

      final result = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
          targetOutcomes: <ProtocolTargetOutcomeDraft>[
            ProtocolTargetOutcomeDraft.metric(weightMetricId),
            ProtocolTargetOutcomeDraft.metric(sleepMetricId),
            ProtocolTargetOutcomeDraft.performance,
          ],
        ),
      );

      final protocol = (await repositories.protocols.listProtocols())
          .firstWhere((p) => p.id == result.protocolId);
      expect(
        protocol.targetOutcomes.map((o) => o.metricId),
        <String?>[weightMetricId, sleepMetricId, null],
      );
      expect(
        protocol.targetOutcomes.map((o) => o.position),
        <int>[0, 1, 2],
      );
    });

    test('a metric target outcome requires a Metric id', () async {
      final creatineId = await createCompoundId('Creatine');
      await expectLater(
        () => repositories.protocols.createProtocol(
          ProtocolDraft(
            name: 'Lean bulk',
            startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
            compoundIds: <String>[creatineId],
            targetOutcomes: <ProtocolTargetOutcomeDraft>[
              const ProtocolTargetOutcomeDraft(
                kind: ProtocolOutcomeKind.metric,
              ),
            ],
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await repositories.protocols.listProtocols(), isEmpty);
    });

    test('a target outcome must reference an active Metric', () async {
      final creatineId = await createCompoundId('Creatine');
      await expectLater(
        () => repositories.protocols.createProtocol(
          ProtocolDraft(
            name: 'Lean bulk',
            startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
            compoundIds: <String>[creatineId],
            targetOutcomes: <ProtocolTargetOutcomeDraft>[
              ProtocolTargetOutcomeDraft.metric('missing-metric-id'),
            ],
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await repositories.protocols.listProtocols(), isEmpty);
    });

    test('a Protocol cannot declare the same target outcome twice', () async {
      final creatineId = await createCompoundId('Creatine');
      final weightMetricId = await createMetricId('Body Weight');
      await expectLater(
        () => repositories.protocols.createProtocol(
          ProtocolDraft(
            name: 'Lean bulk',
            startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
            compoundIds: <String>[creatineId],
            targetOutcomes: <ProtocolTargetOutcomeDraft>[
              ProtocolTargetOutcomeDraft.metric(weightMetricId),
              ProtocolTargetOutcomeDraft.metric(weightMetricId),
            ],
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await repositories.protocols.listProtocols(), isEmpty);
    });

    test('a target outcome referencing an archived Metric is rejected',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final weightMetricId = await createMetricId('Body Weight');
      // No public archive path exists for a Metric yet; simulate the
      // soft-deleted state directly, mirroring how the repository itself
      // tombstones a row (`deletedAt`).
      await (database.update(database.metrics)
            ..where((row) => row.id.equals(weightMetricId)))
          .write(
        MetricsCompanion(deletedAt: Value<DateTime?>(DateTime.now().toUtc())),
      );

      await expectLater(
        () => repositories.protocols.createProtocol(
          ProtocolDraft(
            name: 'Lean bulk',
            startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
            compoundIds: <String>[creatineId],
            targetOutcomes: <ProtocolTargetOutcomeDraft>[
              ProtocolTargetOutcomeDraft.metric(weightMetricId),
            ],
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('editing a Protocol replaces its target outcomes', () async {
      final creatineId = await createCompoundId('Creatine');
      final weightMetricId = await createMetricId('Body Weight');
      final sleepMetricId = await createMetricId('Sleep');

      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
          targetOutcomes: <ProtocolTargetOutcomeDraft>[
            ProtocolTargetOutcomeDraft.metric(weightMetricId),
          ],
        ),
      );

      await repositories.protocols.editProtocol(
        created.protocolId,
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
          targetOutcomes: <ProtocolTargetOutcomeDraft>[
            ProtocolTargetOutcomeDraft.metric(sleepMetricId),
            ProtocolTargetOutcomeDraft.performance,
          ],
        ),
      );

      final protocol = (await repositories.protocols.listProtocols())
          .firstWhere((p) => p.id == created.protocolId);
      expect(
        protocol.targetOutcomes.map((o) => (o.kind, o.metricId)),
        <(ProtocolOutcomeKind, String?)>[
          (ProtocolOutcomeKind.metric, sleepMetricId),
          (ProtocolOutcomeKind.performance, null),
        ],
      );
    });

    test('editing a Protocol to declare no target outcomes clears them all',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final weightMetricId = await createMetricId('Body Weight');

      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
          targetOutcomes: <ProtocolTargetOutcomeDraft>[
            ProtocolTargetOutcomeDraft.metric(weightMetricId),
          ],
        ),
      );

      await repositories.protocols.editProtocol(
        created.protocolId,
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
        ),
      );

      final protocol = (await repositories.protocols.listProtocols())
          .firstWhere((p) => p.id == created.protocolId);
      expect(protocol.targetOutcomes, isEmpty);
    });

    test(
        'creating and editing target outcomes never reads or writes a '
        'logged Dose', () async {
      final creatineId = await createCompoundId('Creatine');
      final weightMetricId = await createMetricId('Body Weight');
      final logged = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 8),
        ),
      );
      final beforeRow = await (database.select(database.doses)
            ..where((r) => r.id.equals(logged.doseId)))
          .getSingle();

      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
          targetOutcomes: <ProtocolTargetOutcomeDraft>[
            ProtocolTargetOutcomeDraft.metric(weightMetricId),
          ],
        ),
      );
      await repositories.protocols.editProtocol(
        created.protocolId,
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
          targetOutcomes: <ProtocolTargetOutcomeDraft>[
            ProtocolTargetOutcomeDraft.performance,
          ],
        ),
      );

      final afterRow = await (database.select(database.doses)
            ..where((r) => r.id.equals(logged.doseId)))
          .getSingle();
      expect(afterRow.updatedAt, beforeRow.updatedAt);
      expect(afterRow.deletedAt, isNull);
    });

    test('creating a target outcome writes one reversible Activity Log entry',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final weightMetricId = await createMetricId('Body Weight');

      await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
          targetOutcomes: <ProtocolTargetOutcomeDraft>[
            ProtocolTargetOutcomeDraft.metric(weightMetricId),
          ],
        ),
      );

      final entries = await (database.select(database.activityLog)
            ..where(
              (row) => row.entityTable
                  .equals(AppDatabase.protocolTargetOutcomesTable),
            ))
          .get();
      expect(entries, hasLength(1));
      expect(entries.single.beforeImage, isNull);
    });

    test('watchProtocols re-emits when target outcomes change', () async {
      final creatineId = await createCompoundId('Creatine');
      final weightMetricId = await createMetricId('Body Weight');
      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
        ),
      );

      final emissions = <int>[];
      final subscription = repositories.protocols.watchProtocols().listen(
            (protocols) =>
                emissions.add(protocols.single.targetOutcomes.length),
          );
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);
      expect(emissions.last, 0);

      await repositories.protocols.editProtocol(
        created.protocolId,
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
          targetOutcomes: <ProtocolTargetOutcomeDraft>[
            ProtocolTargetOutcomeDraft.metric(weightMetricId),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emissions.last, 1);
    });

    test(
      'watchProtocolEffectOptions ignores Schedules and emits target outcomes',
      () async {
        final creatineId = await createCompoundId('Creatine');
        final weightMetricId = await createMetricId('Body Weight');
        final created = await repositories.protocols.createProtocol(
          ProtocolDraft(
            name: 'Lean bulk',
            startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
            compoundIds: <String>[creatineId],
          ),
        );

        final emissions = <List<ProtocolEffectOptionRecord>>[];
        final subscription = repositories.protocols
            .watchProtocolEffectOptions()
            .listen(emissions.add);
        addTearDown(subscription.cancel);
        await Future<void>.delayed(Duration.zero);
        expect(
          emissions.map((options) => options.single.targetOutcomes.length),
          <int>[0],
        );

        await repositories.protocols.editProtocol(
          created.protocolId,
          ProtocolDraft(
            name: 'Lean bulk',
            startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
            compoundIds: <String>[creatineId],
            schedulesByCompoundId: <String, ScheduleDraft?>{
              creatineId: ScheduleDraft(
                rule: _onceDaily,
                doseAmountValue: 5,
                doseAmountEntered: '5',
                doseUnit: DoseUnit.gram,
                route: DoseRoute.oral,
              ),
            },
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          emissions.map((options) => options.single.targetOutcomes.length),
          <int>[0],
        );

        await repositories.protocols.editProtocol(
          created.protocolId,
          ProtocolDraft(
            name: 'Lean bulk',
            startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
            compoundIds: <String>[creatineId],
            schedulesByCompoundId: <String, ScheduleDraft?>{
              creatineId: ScheduleDraft(
                rule: _onceDaily,
                doseAmountValue: 5,
                doseAmountEntered: '5',
                doseUnit: DoseUnit.gram,
                route: DoseRoute.oral,
              ),
            },
            targetOutcomes: <ProtocolTargetOutcomeDraft>[
              ProtocolTargetOutcomeDraft.metric(weightMetricId),
            ],
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          emissions.map((options) => options.single.targetOutcomes.length),
          <int>[0, 1],
        );
      },
    );
  });

  group('Dose Protocol tag', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    Future<String> createCompoundId(String name) async {
      final result = await repositories.protocols.createCompound(
        CompoundDraft(
          name: name,
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
        ),
      );
      return result.compoundId;
    }

    Future<CreateProtocolResult> createProtocolFor(String compoundId) {
      return repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[compoundId],
        ),
      );
    }

    test('an ad-hoc Dose with no Protocol tag remains fully first-class',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final logged = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 8),
        ),
      );

      final day = await repositories.protocols
          .protocolDay(ProtocolDayDate.fromDateTime(DateTime.utc(2026, 6, 30)));
      final dose = day.doses.firstWhere((d) => d.id == logged.doseId);
      expect(dose.protocolId, isNull);
      expect(dose.protocolName, isNull);
      expect(dose.isTaggedToProtocol, isFalse);
    });

    test('logging a Dose can tag it to a Protocol at log time', () async {
      final creatineId = await createCompoundId('Creatine');
      final protocol = await createProtocolFor(creatineId);

      final logged = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 8),
          protocolId: protocol.protocolId,
          protocolName: 'Lean bulk',
        ),
      );

      final day = await repositories.protocols
          .protocolDay(ProtocolDayDate.fromDateTime(DateTime.utc(2026, 6, 30)));
      final dose = day.doses.firstWhere((d) => d.id == logged.doseId);
      expect(dose.protocolId, protocol.protocolId);
      expect(dose.protocolName, 'Lean bulk');
      expect(dose.isTaggedToProtocol, isTrue);
    });

    test('a Dose tagged with a Protocol id requires its name snapshot',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final protocol = await createProtocolFor(creatineId);

      await expectLater(
        () => repositories.protocols.logDose(
          DoseSnapshotDraft(
            compoundId: creatineId,
            compoundName: 'Creatine',
            amountValue: 5,
            amountEntered: '5',
            unit: DoseUnit.gram,
            route: DoseRoute.oral,
            tookAt: DateTime.utc(2026, 6, 30, 8),
            protocolId: protocol.protocolId,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('tagDoseToProtocol tags an already-logged ad-hoc Dose after the fact',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final protocol = await createProtocolFor(creatineId);
      final logged = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 8),
        ),
      );

      await repositories.protocols.tagDoseToProtocol(
        logged.doseId,
        protocolId: protocol.protocolId,
      );

      final row = await (database.select(database.doses)
            ..where((r) => r.id.equals(logged.doseId)))
          .getSingle();
      expect(row.protocolId, protocol.protocolId);
      expect(row.protocolName, 'Lean bulk');
    });

    test(
        'tagDoseToProtocol resolves the Protocol\'s CURRENT name, not a '
        'stale one', () async {
      final creatineId = await createCompoundId('Creatine');
      final protocol = await createProtocolFor(creatineId);
      await repositories.protocols.editProtocol(
        protocol.protocolId,
        ProtocolDraft(
          name: 'Renamed course',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
        ),
      );
      final logged = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 8),
        ),
      );

      await repositories.protocols.tagDoseToProtocol(
        logged.doseId,
        protocolId: protocol.protocolId,
      );

      final row = await (database.select(database.doses)
            ..where((r) => r.id.equals(logged.doseId)))
          .getSingle();
      expect(row.protocolName, 'Renamed course');
    });

    test('tagDoseToProtocol can untag a Dose back to ad-hoc', () async {
      final creatineId = await createCompoundId('Creatine');
      final protocol = await createProtocolFor(creatineId);
      final logged = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 8),
          protocolId: protocol.protocolId,
          protocolName: 'Lean bulk',
        ),
      );

      await repositories.protocols.tagDoseToProtocol(
        logged.doseId,
        protocolId: null,
      );

      final row = await (database.select(database.doses)
            ..where((r) => r.id.equals(logged.doseId)))
          .getSingle();
      expect(row.protocolId, isNull);
      expect(row.protocolName, isNull);
    });

    test(
        'renaming/archiving/deleting the tagged Protocol never rewrites an '
        'already-tagged Dose (self-description holds)', () async {
      final creatineId = await createCompoundId('Creatine');
      final protocol = await createProtocolFor(creatineId);
      final logged = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 8),
          protocolId: protocol.protocolId,
          protocolName: 'Lean bulk',
        ),
      );

      await repositories.protocols.editProtocol(
        protocol.protocolId,
        ProtocolDraft(
          name: 'Renamed course',
          startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
          compoundIds: <String>[creatineId],
        ),
      );
      await repositories.protocols.archiveProtocol(protocol.protocolId);

      final row = await (database.select(database.doses)
            ..where((r) => r.id.equals(logged.doseId)))
          .getSingle();
      // The Dose's OWN frozen snapshot is untouched — it never depends on the
      // live Protocol row (self-description holds, PROTOCOLS.md §1.1).
      expect(row.protocolId, protocol.protocolId);
      expect(row.protocolName, 'Lean bulk');
    });

    test(
        'editDose preserves an existing Protocol tag when the draft carries '
        'it forward', () async {
      final creatineId = await createCompoundId('Creatine');
      final protocol = await createProtocolFor(creatineId);
      final logged = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 8),
          protocolId: protocol.protocolId,
          protocolName: 'Lean bulk',
        ),
      );

      final day = await repositories.protocols
          .protocolDay(ProtocolDayDate.fromDateTime(DateTime.utc(2026, 6, 30)));
      final existing = day.doses.firstWhere((d) => d.id == logged.doseId);

      await repositories.protocols.editDose(
        logged.doseId,
        DoseSnapshotDraft(
          compoundId: existing.compoundId,
          compoundName: existing.compoundName,
          compoundStrength: existing.compoundStrength,
          amountValue: 10,
          amountEntered: '10',
          unit: existing.unit,
          route: existing.route,
          tookAt: existing.tookAt,
          timezone: existing.timezone,
          localDate: existing.localDate,
          provenance: existing.provenance,
          protocolId: existing.protocolId,
          protocolName: existing.protocolName,
        ),
      );

      final row = await (database.select(database.doses)
            ..where((r) => r.id.equals(logged.doseId)))
          .getSingle();
      expect(row.protocolId, protocol.protocolId);
      expect(row.amountValue, 10);
    });

    test(
        'tagDoseToProtocol writes one reversible Activity Log batch and '
        'undo restores the untagged state', () async {
      final creatineId = await createCompoundId('Creatine');
      final protocol = await createProtocolFor(creatineId);
      final logged = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 8),
        ),
      );

      final batchId = await repositories.protocols.tagDoseToProtocol(
        logged.doseId,
        protocolId: protocol.protocolId,
      );

      await repositories.activityLog.undoBatch(batchId);

      final row = await (database.select(database.doses)
            ..where((r) => r.id.equals(logged.doseId)))
          .getSingle();
      expect(row.protocolId, isNull);
      expect(row.protocolName, isNull);
    });
  });
  group('Dose offsets, bulk logging and plan sync images', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    DoseSnapshotDraft creatineAt(DateTime tookAt, {String amount = '5'}) {
      return DoseSnapshotDraft(
        compoundName: 'Creatine',
        amountValue: double.tryParse(amount) ?? 0,
        amountEntered: amount,
        unit: DoseUnit.gram,
        route: DoseRoute.oral,
        tookAt: tookAt,
      );
    }

    Future<DoseRow> doseRow(String id) {
      return (database.select(database.doses)..where((r) => r.id.equals(id)))
          .getSingle();
    }

    test('logDoses writes every Dose in one Activity Log batch', () async {
      final results = await repositories.protocols.logDoses(<DoseSnapshotDraft>[
        creatineAt(DateTime(2026, 7, 1, 9)),
        creatineAt(DateTime(2026, 7, 1, 9, 1)),
      ]);

      expect(results, hasLength(2));
      expect(results.map((result) => result.batchId).toSet(), hasLength(1));
      final entries = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == results.first.batchId)
          .toList();
      expect(entries, hasLength(2));
      expect(await database.select(database.doses).get(), hasLength(2));
    });

    test('logDoses is all-or-nothing: one hard-reject writes no Dose',
        () async {
      await expectLater(
        () => repositories.protocols.logDoses(<DoseSnapshotDraft>[
          creatineAt(DateTime(2026, 7, 1, 9)),
          creatineAt(DateTime(2026, 7, 1, 9, 1), amount: '-1'),
        ]),
        throwsA(isA<DoseValidationException>()),
      );

      expect(await database.select(database.doses).get(), isEmpty);
      expect(await repositories.activityLog.listEntries(), isEmpty);
    });

    test('a logged Dose freezes the UTC offset of its local time', () async {
      final tookAt = DateTime(2026, 7, 1, 21, 5);
      final logged = await repositories.protocols.logDose(creatineAt(tookAt));

      final row = await doseRow(logged.doseId);
      expect(row.timezoneOffsetMinutes, tookAt.timeZoneOffset.inMinutes);
      final dose = (await repositories.protocols.protocolDay(
        ProtocolDayDate.fromDateTime(tookAt),
      ))
          .doses
          .single;
      expect(dose.timezoneOffsetMinutes, tookAt.timeZoneOffset.inMinutes);
      expect(dose.localTime, '21:05');
    });

    test(
        'editing a Dose re-freezes its local date and offset when the time '
        'changes, and keeps them otherwise', () async {
      final logged = await repositories.protocols.logDose(
        creatineAt(DateTime(2026, 7, 1, 21, 5)),
      );
      // A Dose logged before the offset existed: no offset, a foreign label.
      await (database.update(database.doses)
            ..where((r) => r.id.equals(logged.doseId)))
          .write(
        const DosesCompanion(
          timezoneOffsetMinutes: Value<int?>(null),
          timezone: Value<String>('BRT'),
        ),
      );

      // Same time, new amount: the frozen values (a null offset too) stay.
      await repositories.protocols.editDose(
        logged.doseId,
        creatineAt(DateTime(2026, 7, 1, 21, 5), amount: '6'),
      );
      var row = await doseRow(logged.doseId);
      expect(row.amountEntered, '6');
      expect(row.timezoneOffsetMinutes, isNull);
      expect(row.timezone, 'BRT');
      expect(row.localDate, '2026-07-01');

      // A new time on another day: all three are frozen again from it.
      final moved = DateTime(2026, 6, 30, 21);
      await repositories.protocols.editDose(logged.doseId, creatineAt(moved));
      row = await doseRow(logged.doseId);
      expect(row.localDate, '2026-06-30');
      expect(row.timezoneOffsetMinutes, moved.timeZoneOffset.inMinutes);
      expect(row.timezone, moved.timeZoneName);
    });

    test(
        'editing the time of a Dose logged at another offset keeps that '
        'offset and its label, and freezes the local date from it', () async {
      final logged = await repositories.protocols.logDose(
        creatineAt(DateTime(2026, 7, 1, 21, 5)),
      );
      // Logged in Honolulu (UTC−10:00): 08:30 on 2026-07-01 there.
      const offset = -600;
      await (database.update(database.doses)
            ..where((r) => r.id.equals(logged.doseId)))
          .write(
        DosesCompanion(
          tookAt: Value<DateTime>(DateTime.utc(2026, 7, 1, 18, 30)),
          timezoneOffsetMinutes: const Value<int?>(offset),
          timezone: const Value<String>('HST'),
          localDate: const Value<String>('2026-07-01'),
        ),
      );

      // 23:30 that evening in Honolulu is 09:30 UTC the next day, a later
      // date in UTC and in every zone east of UTC−10:00.
      await repositories.protocols.editDose(
        logged.doseId,
        creatineAt(DateTime.utc(2026, 7, 2, 9, 30)),
      );
      var row = await doseRow(logged.doseId);
      expect(row.tookAt.toUtc(), DateTime.utc(2026, 7, 2, 9, 30));
      expect(row.timezoneOffsetMinutes, offset);
      expect(row.timezone, 'HST');
      expect(row.localDate, '2026-07-01');
      var dose = (await repositories.protocols.protocolDay(
        const ProtocolDayDate(year: 2026, month: 7, day: 1),
      ))
          .doses
          .single;
      expect(dose.localTime, '23:30');

      // Past midnight in Honolulu: the local date moves to the next day
      // there, at the same offset.
      await repositories.protocols.editDose(
        logged.doseId,
        creatineAt(DateTime.utc(2026, 7, 2, 10, 15)),
      );
      row = await doseRow(logged.doseId);
      expect(row.timezoneOffsetMinutes, offset);
      expect(row.timezone, 'HST');
      expect(row.localDate, '2026-07-02');
      dose = (await repositories.protocols.protocolDay(
        const ProtocolDayDate(year: 2026, month: 7, day: 2),
      ))
          .doses
          .single;
      expect(dose.localTime, '00:15');
    });

    test(
        "a Protocol Day's Doses are listed in clock order, local time and then "
        'id, not instant order', () async {
      final compound = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Creatine',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.oral,
        ),
      );
      const day = ProtocolDayDate(year: 2026, month: 7, day: 1);
      const nextDay = ProtocolDayDate(year: 2026, month: 7, day: 2);
      Future<String> logAt(
        DateTime tookAtUtc,
        int offset, {
        ProtocolDayDate on = day,
      }) async {
        final logged = await repositories.protocols.logDose(
          DoseSnapshotDraft(
            compoundId: compound.compoundId,
            compoundName: 'Creatine',
            amountValue: 5,
            amountEntered: '5',
            unit: DoseUnit.gram,
            route: DoseRoute.oral,
            tookAt: tookAtUtc,
          ),
        );
        await (database.update(database.doses)
              ..where((r) => r.id.equals(logged.doseId)))
            .write(
          DosesCompanion(
            timezoneOffsetMinutes: Value<int?>(offset),
            localDate: Value<String>(on.storageValue),
          ),
        );
        return logged.doseId;
      }

      // Logged first, in Tokyo (UTC+09:00): 21:00 there, 12:00 UTC.
      final tokyo = await logAt(DateTime.utc(2026, 7, 1, 12), 540);
      // Logged later, in Honolulu (UTC−10:00): 08:30 there, 18:30 UTC. The
      // later instant and the later id, at the earlier clock time.
      final honolulu = await logAt(DateTime.utc(2026, 7, 1, 18, 30), -600);
      expect(honolulu.compareTo(tokyo), greaterThan(0));

      final watched = await repositories.protocols.watchProtocolDay(day).first;
      expect(
        watched.doses.map((dose) => dose.localTime),
        <String>['08:30', '21:00'],
      );
      expect(
        watched.doses.map((dose) => dose.id),
        <String>[honolulu, tokyo],
      );
      final read = await repositories.protocols.protocolDay(day);
      expect(read.doses.map((dose) => dose.id), <String>[honolulu, tokyo]);

      // The next day, two Doses at the same clock minute through different
      // offsets: 21:00 in Tokyo (UTC+09:00, 12:00 UTC), logged first, then
      // 21:00 at UTC+10:00 (11:00 UTC). The larger id has the earlier
      // instant, so only the id tie-break lists them in log order.
      final first = await logAt(DateTime.utc(2026, 7, 2, 12), 540, on: nextDay);
      final second =
          await logAt(DateTime.utc(2026, 7, 2, 11), 600, on: nextDay);
      expect(second.compareTo(first), greaterThan(0));
      final tied = await repositories.protocols.protocolDay(nextDay);
      expect(tied.doses.map((dose) => dose.localTime), <String>[
        '21:00',
        '21:00',
      ]);
      expect(tied.doses.map((dose) => dose.id), <String>[first, second]);

      final consistency = await repositories.protocolPlan
          .watchConsistency(compound.compoundId, day, nextDay, today: nextDay)
          .first;
      expect(
        consistency.doses.map((dose) => dose.id),
        <String>[honolulu, tokyo, first, second],
      );
    });

    test('a Dose sync image without an offset applies with a null offset',
        () async {
      final updatedAt = DateTime.utc(2026, 7, 1, 12);
      await repositories.protocols.applySyncImage(
        entityTable: AppDatabase.dosesTable,
        image: <String, Object?>{
          'id': 'dose-before-offsets',
          'compound_id': null,
          'compound_name': 'Creatine',
          'compound_strength': null,
          'amount_value': 5,
          'amount_entered': '5',
          'unit': 'gram',
          'route': 'oral',
          'took_at': '2026-07-01T12:00:00.000Z',
          'timezone': 'BRT',
          'local_date': '2026-07-01',
          'provenance': 'manual',
          'protocol_id': null,
          'protocol_name': null,
          'updated_at': updatedAt.toIso8601String(),
          'deleted_at': null,
        },
        deviceId: 'device-b',
        batchId: 'batch-sync',
      );

      final row = await doseRow('dose-before-offsets');
      expect(row.timezoneOffsetMinutes, isNull);
      expect(row.amountEntered, '5');
    });

    test(
        'a strength an Agent stored as an object, before the label was used, '
        'applies as the label on a Compound and on a Dose snapshot', () async {
      final updatedAt = DateTime.utc(2026, 7, 1, 12).toIso8601String();
      final agentStrength = <String, Object?>{
        'value': 5,
        'massUnit': 'milligram',
        'perUnit': 'capsule',
      };
      await repositories.protocols.applySyncImage(
        entityTable: AppDatabase.compoundsTable,
        image: <String, Object?>{
          'id': 'agent-compound',
          'name': 'Zinc',
          'default_unit': 'capsule',
          'default_route': 'oral',
          'strength': agentStrength,
          'updated_at': updatedAt,
          'deleted_at': null,
        },
        deviceId: 'agent',
        batchId: 'batch-agent',
      );
      await repositories.protocols.applySyncImage(
        entityTable: AppDatabase.dosesTable,
        image: <String, Object?>{
          'id': 'agent-dose',
          'compound_id': 'agent-compound',
          'compound_name': 'Zinc',
          'compound_strength': <String, Object?>{
            'value': 0.5,
            'massUnit': 'internationalUnit',
            'perUnit': 'drop',
          },
          'amount_value': 2,
          'amount_entered': '2',
          'unit': 'drop',
          'route': 'oral',
          'took_at': '2026-07-01T12:00:00.000Z',
          'timezone': 'UTC',
          'local_date': '2026-07-01',
          'provenance': 'agent',
          'protocol_id': null,
          'protocol_name': null,
          'updated_at': updatedAt,
          'deleted_at': null,
        },
        deviceId: 'agent',
        batchId: 'batch-agent',
      );

      final compound = await (database.select(database.compounds)
            ..where((row) => row.id.equals('agent-compound')))
          .getSingle();
      expect(compound.strength, '5 mg/capsule');
      final listed = (await repositories.protocols.listCompounds()).singleWhere(
        (compound) => compound.id == 'agent-compound',
      );
      expect(listed.strength, CompoundStrength.parse('5 mg/capsule'));
      expect((await doseRow('agent-dose')).compoundStrength, '0.5 IU/drop');

      // An object the label can't hold (a unit outside the registry, a
      // non-positive amount) is a FormatException, which a pull quarantines.
      for (final strength in <Map<String, Object?>>[
        <String, Object?>{'value': 5, 'massUnit': 'mg', 'perUnit': 'capsule'},
        <String, Object?>{
          'value': 0,
          'massUnit': 'milligram',
          'perUnit': 'capsule',
        },
        <String, Object?>{'value': '5', 'massUnit': 'milligram'},
      ]) {
        await expectLater(
          () => repositories.protocols.applySyncImage(
            entityTable: AppDatabase.compoundsTable,
            image: <String, Object?>{
              'id': 'bad-compound',
              'name': 'Bad',
              'default_unit': 'capsule',
              'default_route': 'oral',
              'strength': strength,
              'updated_at': updatedAt,
              'deleted_at': null,
            },
            deviceId: 'agent',
            batchId: 'batch-agent',
          ),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test(
        'a pull page holding Agent-written strength objects applies the '
        'readable one, quarantines the other, and the Agent write can be '
        'undone', () async {
      const updatedAt = '2026-07-01T12:00:00.000Z';
      const batchId = 'agent-strength-batch';
      Map<String, Object?> agentCompound(
        String id,
        Map<String, Object?> strength,
      ) {
        final payload = <String, Object?>{
          'id': id,
          'name': id,
          'default_unit': 'capsule',
          'default_route': 'oral',
          'strength': strength,
          // No `is_favorite`: the Agent write has no favourite field.
          'updated_at': updatedAt,
          'deleted_at': null,
        };
        return <String, Object?>{
          'entity': AppDatabase.compoundsTable,
          'id': id,
          'deviceId': 'agent-device',
          'payload': payload,
          'updatedAt': updatedAt,
          'deletedAt': null,
          'activityLogId': 'agent:$batchId:compound:$id',
          'actor': 'agent',
          'batchId': batchId,
          'beforeImage': null,
          'afterImage': payload,
          'occurredAt': updatedAt,
        };
      }

      final repository = SyncRepository(
        database: database,
        apiClientFactory: (baseUrl) => PerenniaApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((request) async {
            final cursor = jsonDecode(request.body)['cursor'];
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': syncProtocolVersion,
                'nextCursor': 'cursor-strength',
                'serverClock': '2026-07-01T12:00:01.000Z',
                'changes': cursor == null
                    ? <Object?>[
                        agentCompound('agent-zinc', <String, Object?>{
                          'value': 5,
                          'massUnit': 'milligram',
                          'perUnit': 'capsule',
                        }),
                        agentCompound('agent-scoop', <String, Object?>{
                          'value': 5,
                          'massUnit': 'scoop',
                          'perUnit': 'capsule',
                        }),
                      ]
                    : <Object?>[],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        ),
      );

      // Before the fix the object threw a StateError, which the pull doesn't
      // quarantine, so the whole page failed on every pull.
      final result = await repository.pullLoggedSetChanges(
        session: AuthSession(
          provider: AuthSessionProvider.email,
          serverUrl: Uri.parse('https://sync.example/'),
          token: 'session-token',
          userEmail: 'user@example.com',
          userId: 'user-1',
          userName: 'Sync User',
        ),
        deviceId: 'device-a',
      );

      expect(result.appliedCount, 1);
      final compounds = await database.select(database.compounds).get();
      expect(
        compounds.map((row) => (row.id, row.strength)),
        <(String, String?)>[('agent-zinc', '5 mg/capsule')],
      );
      final held = await database.select(database.quarantinedSyncChanges).get();
      expect(held.map((row) => row.entityId), <String>['agent-scoop']);
      expect(held.single.failureKind, 'format');

      // The Agent's after-image still holds the object; undo reads it as the
      // label the row holds, so it isn't reported stale.
      final undo = await repositories.activityLog.undoBatch(batchId);
      expect(undo.conflicts, isEmpty);
      expect(
        undo.appliedEntries.map((entry) => entry.entityId),
        <String>['agent-zinc'],
      );
    });

    test(
        'a plan written by the server, with `rule` and `period` as JSON '
        'objects rather than JSON text, applies and reads back', () async {
      final compound = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'GHK-Cu',
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.subcutaneous,
        ),
      );
      final updatedAt = DateTime.utc(2026, 10, 1, 9).toIso8601String();
      Future<void> apply(String table, Map<String, Object?> image) {
        return repositories.protocols.applySyncImage(
          entityTable: table,
          image: image,
          deviceId: 'agent-device',
          batchId: 'batch-agent',
        );
      }

      await apply(AppDatabase.protocolsTable, <String, Object?>{
        'id': 'agent-protocol',
        'name': 'Skin',
        'start_local_date': '2026-10-01',
        'end_local_date': null,
        'period': <String, Object?>{
          'v': 1,
          'cycle': <String, Object?>{
            'on_days': 60,
            'off_days': 30,
            'anchor': '2026-10-01',
            'anchor_is_default': true,
          },
          'pauses': <Object?>[],
        },
        'reminders_enabled': false,
        'archived_on': null,
        'updated_at': updatedAt,
        'deleted_at': null,
      });
      await apply(AppDatabase.protocolCompoundsTable, <String, Object?>{
        'id': 'agent-member',
        'protocol_id': 'agent-protocol',
        'compound_id': compound.compoundId,
        'position': 0,
        'archived_on': null,
        'updated_at': updatedAt,
        'deleted_at': null,
      });
      await apply(AppDatabase.schedulesTable, <String, Object?>{
        'id': 'agent-version',
        'protocol_compound_id': 'agent-member',
        'effective_from': '2026-10-01',
        'rule': <String, Object?>{
          'v': 1,
          'kind': 'timed',
          'days': <String, Object?>{'kind': 'daily'},
          'times': <Object?>['21:00'],
        },
        'dose_amount_value': 1,
        'dose_amount_entered': '1',
        'dose_unit': 'milligram',
        'route': 'subcutaneous',
        'updated_at': updatedAt,
        'deleted_at': null,
      });

      final protocol = (await repositories.protocols.listProtocols()).single;
      expect(protocol.period?.cycle?.onDays, 60);
      final version = protocol.members.single.currentVersion!;
      expect(version.effectiveFrom, ProtocolDayDate.parse('2026-10-01'));
      expect((version.rule as TimedScheduleRule).times, <String>['21:00']);
    });

    test(
        'a pulled Protocol or Schedule in the shape before the plan is '
        'quarantined, and nothing is applied', () async {
      final updatedAt = DateTime.utc(2026, 7, 1, 9);
      Map<String, Object?> pulled(
        String entity,
        String id,
        Map<String, Object?> payload,
      ) {
        return <String, Object?>{
          'entity': entity,
          'id': id,
          'deviceId': 'device-b',
          'payload': payload,
          'updatedAt': updatedAt.toIso8601String(),
          'deletedAt': null,
        };
      }

      final repository = SyncRepository(
        database: database,
        apiClientFactory: (baseUrl) => PerenniaApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((request) async {
            final cursor = jsonDecode(request.body)['cursor'];
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': syncProtocolVersion,
                'nextCursor': 'cursor-old-shape',
                'serverClock': '2026-07-01T09:00:01.000Z',
                'changes': cursor == null
                    ? <Object?>[
                        pulled(AppDatabase.protocolsTable, 'old-protocol', {
                          'id': 'old-protocol',
                          'name': 'Lean bulk',
                          'start_date': '2026-07-01T00:00:00.000Z',
                          'end_date': null,
                          'updated_at': updatedAt.toIso8601String(),
                          'deleted_at': null,
                        }),
                      ]
                    : <Object?>[],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        ),
      );

      final result = await repository.pullLoggedSetChanges(
        session: AuthSession(
          provider: AuthSessionProvider.email,
          serverUrl: Uri.parse('https://sync.example/'),
          token: 'session-token',
          userEmail: 'user@example.com',
          userId: 'user-1',
          userName: 'Sync User',
        ),
        deviceId: 'device-a',
      );

      expect(result.appliedCount, 0);
      expect(await database.select(database.protocols).get(), isEmpty);
      final held = await database.select(database.quarantinedSyncChanges).get();
      expect(held, hasLength(1));
      expect(held.single.entityTable, AppDatabase.protocolsTable);
      expect(held.single.entityId, 'old-protocol');
      expect(held.single.failureKind, 'format');

      // The same holds for a Schedule carrying `frequency` and no rule.
      await expectLater(
        () => repositories.protocols.applySyncImage(
          entityTable: AppDatabase.schedulesTable,
          image: <String, Object?>{
            'id': 'old-schedule',
            'protocol_compound_id': 'member-1',
            'dose_amount_value': 5,
            'dose_amount_entered': '5',
            'dose_unit': 'gram',
            'frequency': 'onceDaily',
            'route': 'oral',
            'updated_at': updatedAt.toIso8601String(),
            'deleted_at': null,
          },
          deviceId: 'device-b',
          batchId: 'batch-sync',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(await database.select(database.schedules).get(), isEmpty);
    });
  });

  group('Deleting a Protocol (D8)', () {
    late AppDatabase database;
    late TrainingRepositories repositories;
    const start = ProtocolDayDate(year: 2026, month: 7, day: 1);

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    Future<String> createCompoundId(String name) async {
      final result = await repositories.protocols.createCompound(
        CompoundDraft(
          name: name,
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
        ),
      );
      return result.compoundId;
    }

    ScheduleDraft daily() => ScheduleDraft(
          rule: _onceDaily,
          doseAmountValue: 5,
          doseAmountEntered: '5',
          doseUnit: DoseUnit.gram,
          route: DoseRoute.oral,
        );

    Future<String> createProtocol(
      List<String> compoundIds, {
      ProtocolDayDate? endLocalDate,
    }) async {
      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: start,
          endLocalDate: endLocalDate,
          compoundIds: compoundIds,
          schedulesByCompoundId: <String, ScheduleDraft?>{
            for (final id in compoundIds) id: daily(),
          },
          targetOutcomes: const <ProtocolTargetOutcomeDraft>[
            ProtocolTargetOutcomeDraft.performance,
          ],
        ),
        today: start,
      );
      return created.protocolId;
    }

    Future<LogDoseResult> logDose(
      String compoundId,
      DateTime tookAt, {
      String? protocolId,
    }) {
      return repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: compoundId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: tookAt,
          protocolId: protocolId,
          protocolName: protocolId == null ? null : 'Lean bulk',
        ),
      );
    }

    Future<ProtocolRow> protocolRow(String id) =>
        (database.select(database.protocols)..where((r) => r.id.equals(id)))
            .getSingle();

    Future<List<Object>> childRows() async => <Object>[
          ...await database.select(database.protocolCompounds).get(),
          ...await database.select(database.schedules).get(),
          ...await database.select(database.protocolTargetOutcomes).get(),
          ...await database.select(database.doses).get(),
        ];

    test(
        'writes one protocols row and one Activity Log entry, and leaves '
        'members, Schedule Versions and target outcomes untouched', () async {
      final creatineId = await createCompoundId('Creatine');
      final protocolId = await createProtocol(<String>[creatineId]);
      final childrenBefore = await childRows();
      final before = await protocolRow(protocolId);

      expect(
          await repositories.protocols.protocolHasHistory(protocolId), isFalse);
      final batchId = await repositories.protocols.deleteProtocol(protocolId);

      final after = await protocolRow(protocolId);
      expect(after.deletedAt, isNotNull);
      expect(after.archivedOn, isNull);
      expect(after.updatedAt, after.deletedAt);
      expect(after.updatedAt.isBefore(before.updatedAt), isFalse);
      expect(after.name, before.name);
      expect(await childRows(), childrenBefore);

      final entries = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == batchId)
          .toList();
      expect(entries, hasLength(1));
      expect(entries.single.entityTable, AppDatabase.protocolsTable);
      expect(entries.single.entityId, protocolId);

      expect(await repositories.protocols.listProtocols(), isEmpty);
    });

    test('undoBatch restores a live Protocol exactly', () async {
      final creatineId = await createCompoundId('Creatine');
      final protocolId = await createProtocol(<String>[creatineId]);
      final before = await protocolRow(protocolId);

      final batchId = await repositories.protocols.deleteProtocol(protocolId);
      await repositories.activityLog.undoBatch(batchId);

      final restored = await protocolRow(protocolId);
      expect(restored.deletedAt, isNull);
      expect(restored.archivedOn, isNull);
      expect(restored.name, before.name);
      expect(restored.startLocalDate, before.startLocalDate);
      final listed = await repositories.protocols.listProtocols();
      expect(listed.single.id, protocolId);
      expect(listed.single.members.single.compoundId, creatineId);
      expect(listed.single.members.single.currentVersion, isNotNull);
      expect(listed.single.targetOutcomes, hasLength(1));
    });

    test(
        'an archived Protocol with no history can be deleted, which clears '
        'its archive date, and undo restores it archived', () async {
      final creatineId = await createCompoundId('Creatine');
      final protocolId = await createProtocol(<String>[creatineId]);
      // archiveProtocol accepts a Protocol with no history.
      await repositories.protocols.archiveProtocol(
        protocolId,
        today: const ProtocolDayDate(year: 2026, month: 7, day: 3),
      );
      final archived = await protocolRow(protocolId);
      expect(archived.archivedOn, '2026-07-03');

      final batchId = await repositories.protocols.deleteProtocol(protocolId);
      final deleted = await protocolRow(protocolId);
      expect(deleted.archivedOn, isNull);
      expect(deleted.deletedAt, isNotNull);

      await repositories.activityLog.undoBatch(batchId);
      final restored = await protocolRow(protocolId);
      expect(restored.archivedOn, '2026-07-03');
      expect(restored.deletedAt, archived.deletedAt);
      expect(await repositories.protocols.listProtocols(), isEmpty);
    });

    test('archiveProtocol still accepts a Protocol with no history', () async {
      final creatineId = await createCompoundId('Creatine');
      final protocolId = await createProtocol(<String>[creatineId]);
      expect(
          await repositories.protocols.protocolHasHistory(protocolId), isFalse);

      await repositories.protocols.archiveProtocol(protocolId);

      final row = await protocolRow(protocolId);
      expect(row.deletedAt, isNotNull);
      expect(row.archivedOn, isNotNull);
    });

    test('refuses a Protocol with a tagged Dose, even of another Compound',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final zincId = await createCompoundId('Zinc');
      final protocolId = await createProtocol(<String>[creatineId]);
      // Before the start, and not a member Compound: only the tag counts.
      await logDose(zincId, DateTime(2026, 6, 1, 8), protocolId: protocolId);

      expect(
          await repositories.protocols.protocolHasHistory(protocolId), isTrue);
      await expectLater(
        repositories.protocols.deleteProtocol(protocolId),
        throwsA(
          isA<ProtocolHasHistoryException>()
              .having((e) => e.protocolId, 'protocolId', protocolId),
        ),
      );
      final row = await protocolRow(protocolId);
      expect(row.deletedAt, isNull);
    });

    test(
        'refuses a Protocol with an untagged Dose of a member Compound inside '
        'its dates', () async {
      final creatineId = await createCompoundId('Creatine');
      final protocolId = await createProtocol(<String>[creatineId]);
      await logDose(creatineId, DateTime(2026, 7, 5, 8));

      expect(
          await repositories.protocols.protocolHasHistory(protocolId), isTrue);
      await expectLater(
        repositories.protocols.deleteProtocol(protocolId),
        throwsA(isA<ProtocolHasHistoryException>()),
      );
      expect((await protocolRow(protocolId)).deletedAt, isNull);
    });

    test('an archived member counts, an undo-removed member does not',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final zincId = await createCompoundId('Zinc');
      final magnesiumId = await createCompoundId('Magnesium');
      final protocolId = await createProtocol(<String>[creatineId, zincId]);
      ProtocolDraft draft(List<String> compoundIds) => ProtocolDraft(
            name: 'Lean bulk',
            startLocalDate: start,
            compoundIds: compoundIds,
            schedulesByCompoundId: <String, ScheduleDraft?>{
              for (final id in compoundIds) id: daily(),
            },
          );

      // Magnesium is added, then the edit is undone: its member row never
      // existed (D1), so its Dose is no history.
      final added = await repositories.protocols.editProtocol(
        protocolId,
        draft(<String>[creatineId, zincId, magnesiumId]),
        today: const ProtocolDayDate(year: 2026, month: 7, day: 2),
      );
      await repositories.activityLog.undoBatch(added);
      await logDose(magnesiumId, DateTime(2026, 7, 5, 8));
      expect(
          await repositories.protocols.protocolHasHistory(protocolId), isFalse);

      // Zinc is removed, so its member row is archived; it still counts.
      await repositories.protocols.editProtocol(
        protocolId,
        draft(<String>[creatineId]),
        today: const ProtocolDayDate(year: 2026, month: 7, day: 3),
      );
      await logDose(zincId, DateTime(2026, 7, 10, 8));
      expect(
          await repositories.protocols.protocolHasHistory(protocolId), isTrue);
    });

    test(
        'an untagged Dose outside its dates, and a deleted Dose, are not '
        'history', () async {
      final creatineId = await createCompoundId('Creatine');
      final protocolId = await createProtocol(
        <String>[creatineId],
        endLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 31),
      );
      await logDose(creatineId, DateTime(2026, 6, 30, 8));
      await logDose(creatineId, DateTime(2026, 8, 1, 8));
      final deleted = await logDose(creatineId, DateTime(2026, 7, 5, 8));
      expect(
          await repositories.protocols.protocolHasHistory(protocolId), isTrue);
      await repositories.protocols.deleteDose(deleted.doseId);
      expect(
          await repositories.protocols.protocolHasHistory(protocolId), isFalse);

      await repositories.protocols.deleteProtocol(protocolId);
      expect((await protocolRow(protocolId)).deletedAt, isNotNull);
    });

    test('a Dose after the archive date is not history', () async {
      final creatineId = await createCompoundId('Creatine');
      final protocolId = await createProtocol(<String>[creatineId]);
      await repositories.protocols.archiveProtocol(
        protocolId,
        today: const ProtocolDayDate(year: 2026, month: 7, day: 3),
      );
      await logDose(creatineId, DateTime(2026, 7, 4, 8));
      expect(
          await repositories.protocols.protocolHasHistory(protocolId), isFalse);
      await logDose(creatineId, DateTime(2026, 7, 3, 20));
      expect(
          await repositories.protocols.protocolHasHistory(protocolId), isTrue);
    });

    test('refuses an unknown id, and one already deleted', () async {
      await expectLater(
        repositories.protocols.deleteProtocol('missing'),
        throwsStateError,
      );

      final creatineId = await createCompoundId('Creatine');
      final protocolId = await createProtocol(<String>[creatineId]);
      await repositories.protocols.deleteProtocol(protocolId);
      final entries = (await repositories.activityLog.listEntries()).length;

      await expectLater(
        repositories.protocols.deleteProtocol(protocolId),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Protocol is deleted: $protocolId.',
          ),
        ),
      );
      expect((await repositories.activityLog.listEntries()).length, entries);
    });

    test('watchProtocolHasHistory re-emits when a Dose is logged', () async {
      final creatineId = await createCompoundId('Creatine');
      final protocolId = await createProtocol(<String>[creatineId]);
      final emissions = <bool>[];
      final subscription = repositories.protocols
          .watchProtocolHasHistory(protocolId)
          .listen(emissions.add);
      addTearDown(subscription.cancel);
      await _waitFor(() => emissions.isNotEmpty);
      expect(emissions.last, isFalse);

      await logDose(creatineId, DateTime(2026, 7, 5, 8));

      await _waitFor(() => emissions.last);
      expect(emissions, <bool>[false, true]);
    });
  });

  group('Skips (D8)', () {
    late AppDatabase database;
    late TrainingRepositories repositories;
    late String creatineId;
    late String protocolId;
    const start = ProtocolDayDate(year: 2026, month: 7, day: 1);
    const today = ProtocolDayDate(year: 2026, month: 7, day: 10);
    const yesterday = ProtocolDayDate(year: 2026, month: 7, day: 9);

    setUp(() async {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
      creatineId = (await repositories.protocols.createCompound(
        CompoundDraft(
          name: 'Creatine',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.oral,
        ),
      ))
          .compoundId;
      protocolId = (await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startLocalDate: start,
          compoundIds: <String>[creatineId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            creatineId: ScheduleDraft(
              rule: TimedScheduleRule(
                days: const DailyScheduleDays(),
                times: const <String>['08:00', '21:00'],
              ),
              doseAmountValue: 5,
              doseAmountEntered: '5',
              doseUnit: DoseUnit.gram,
              route: DoseRoute.oral,
            ),
          },
        ),
        today: start,
      ))
          .protocolId;
    });

    tearDown(() async {
      await database.close();
    });

    ProtocolSkipDraft draft({
      ProtocolDayDate localDate = today,
      String? plannedLocalTime = '21:00',
      String? protocol,
    }) =>
        ProtocolSkipDraft(
          protocolId: protocol ?? protocolId,
          compoundId: creatineId,
          localDate: localDate,
          plannedLocalTime: plannedLocalTime,
        );

    Future<List<ProtocolSkipRow>> skipRows() =>
        (database.select(database.protocolSkips)
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();

    Future<ProtocolSkipRow> skipRow(String id) =>
        (database.select(database.protocolSkips)
              ..where((row) => row.id.equals(id)))
            .getSingle();

    /// Writes a Skip and returns its id.
    Future<String> skip(ProtocolSkipDraft value) async {
      final before = (await skipRows()).map((row) => row.id).toSet();
      await repositories.protocols.skipPlannedDose(value, today: today);
      return (await skipRows())
          .map((row) => row.id)
          .toSet()
          .difference(before)
          .single;
    }

    Future<List<ActivityLogEntry>> batchEntries(String batchId) async =>
        (await repositories.activityLog.listEntries())
            .where((entry) => entry.batchId == batchId)
            .toList();

    DoseSnapshotDraft creatineDose(DateTime tookAt) => DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: tookAt,
          protocolId: protocolId,
          protocolName: 'Lean bulk',
        );

    test(
        'skipPlannedDose writes one row and one Activity Log entry in one '
        'batch, and the day reads it', () async {
      final batchId = await repositories.protocols.skipPlannedDose(
        draft(),
        today: today,
      );

      final row = (await skipRows()).single;
      expect(row.protocolId, protocolId);
      expect(row.compoundId, creatineId);
      expect(row.localDate, '2026-07-10');
      expect(row.plannedLocalTime, '21:00');
      expect(row.deletedAt, equals(null));
      expect(row.syncPreviouslySynced, isFalse);

      final entries = await batchEntries(batchId);
      expect(entries, hasLength(1));
      expect(entries.single.entityTable, AppDatabase.protocolSkipsTable);
      expect(entries.single.entityId, row.id);
      expect(entries.single.beforeImage, equals(null));
      expect(
        entries.single.afterImage!.keys,
        unorderedEquals(<String>[
          'id',
          'protocol_id',
          'compound_id',
          'local_date',
          'planned_local_time',
          'updated_at',
          'deleted_at',
        ]),
      );

      final day = await repositories.protocols.protocolDay(today);
      expect(day.skips.single.id, row.id);
      expect(day.skips.single.plannedLocalTime, '21:00');
      expect(day.isEmpty, isTrue, reason: 'a Skip records no intake');
      expect(
          (await repositories.protocols.protocolDay(yesterday)).skips, isEmpty);
    });

    test(
        'skipPlannedDose validates: a malformed time or a date after today '
        'throws and writes nothing', () async {
      await expectLater(
        repositories.protocols.skipPlannedDose(
          draft(plannedLocalTime: '25:00'),
          today: today,
        ),
        throwsA(
          isA<DoseValidationException>().having(
            (e) => e.errors.map((issue) => issue.rule),
            'rules',
            <String>['skip_time_format'],
          ),
        ),
      );
      await expectLater(
        repositories.protocols.skipPlannedDose(
          draft(localDate: today.addDays(1)),
          today: today,
        ),
        throwsA(
          isA<DoseValidationException>().having(
            (e) => e.errors.map((issue) => issue.rule),
            'rules',
            <String>['skip_future'],
          ),
        ),
      );
      expect(await skipRows(), isEmpty);

      // An untimed Skip, and one for a past day, are valid.
      await skip(draft(plannedLocalTime: null));
      await skip(draft(localDate: yesterday));
      expect(await skipRows(), hasLength(2));
    });

    test(
        'skipPlannedDose refuses a missing or deleted Protocol and accepts '
        'an archived one', () async {
      await expectLater(
        repositories.protocols.skipPlannedDose(
          draft(protocol: 'missing'),
          today: today,
        ),
        throwsStateError,
      );

      await repositories.protocols.archiveProtocol(protocolId, today: today);
      final archivedSkip = await skip(draft(localDate: yesterday));
      expect((await skipRow(archivedSkip)).protocolId, protocolId);

      final other = (await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Unused',
          startLocalDate: start,
          compoundIds: <String>[creatineId],
        ),
        today: start,
      ))
          .protocolId;
      await repositories.protocols.deleteProtocol(other);
      await expectLater(
        repositories.protocols.skipPlannedDose(
          draft(protocol: other),
          today: today,
        ),
        throwsStateError,
      );
      expect(await skipRows(), hasLength(1));
    });

    test(
        'unskipPlannedDose removes every Skip with the timed key, one '
        'Activity Log entry each in one batch, and leaves the others',
        () async {
      final first = await skip(draft());
      // Another device's Skip of the same planned dose, synced in.
      final sibling = await skip(draft());
      final otherTime = await skip(draft(plannedLocalTime: '08:00'));
      final otherDay = await skip(draft(localDate: yesterday));

      final batchId = await repositories.protocols.unskipPlannedDose(first);

      expect((await skipRow(first)).deletedAt, isNotNull);
      expect((await skipRow(sibling)).deletedAt, isNotNull);
      expect(
          (await skipRow(first)).updatedAt, (await skipRow(first)).deletedAt);
      expect((await skipRow(otherTime)).deletedAt, equals(null));
      expect((await skipRow(otherDay)).deletedAt, equals(null));
      final entries = await batchEntries(batchId);
      expect(
        entries.map((entry) => entry.entityId),
        unorderedEquals(<String>[first, sibling]),
      );
      for (final entry in entries) {
        expect(entry.entityTable, AppDatabase.protocolSkipsTable);
        expect(entry.beforeImage!['deleted_at'], equals(null));
        expect(entry.afterImage!['deleted_at'], isNotNull);
      }
      expect(
        (await repositories.protocols.protocolDay(today))
            .skips
            .map((skip) => skip.id),
        <String>[otherTime],
      );
    });

    test('unskipPlannedDose removes only the named untimed Skip', () async {
      final first = await skip(draft(plannedLocalTime: null));
      final second = await skip(draft(plannedLocalTime: null));

      final batchId = await repositories.protocols.unskipPlannedDose(second);

      expect((await skipRow(second)).deletedAt, isNotNull);
      expect((await skipRow(first)).deletedAt, equals(null));
      expect(await batchEntries(batchId), hasLength(1));
    });

    test(
        'unskipPlannedDose of a Skip already removed still sweeps its '
        'timed siblings and never brings it back; an unknown id throws',
        () async {
      final first = await skip(draft());
      await repositories.protocols.unskipPlannedDose(first);
      final removedAt = (await skipRow(first)).deletedAt;
      final sibling = await skip(draft());

      final batchId = await repositories.protocols.unskipPlannedDose(first);

      expect((await skipRow(first)).deletedAt, removedAt);
      expect((await skipRow(sibling)).deletedAt, isNotNull);
      expect(
        (await batchEntries(batchId)).map((entry) => entry.entityId),
        <String>[sibling],
      );
      await expectLater(
        repositories.protocols.unskipPlannedDose('missing'),
        throwsStateError,
      );
    });

    test(
        'logDose(unskipId:) logs the Dose and removes the Skip with its '
        'timed siblings in one transaction and batch', () async {
      final skipId = await skip(draft());
      final sibling = await skip(draft());

      final result = await repositories.protocols.logDose(
        creatineDose(DateTime(2026, 7, 10, 21, 5)),
        unskipId: skipId,
      );

      expect((await skipRow(skipId)).deletedAt, isNotNull);
      expect((await skipRow(sibling)).deletedAt, isNotNull);
      final entries = await batchEntries(result.batchId);
      expect(
        entries.map((entry) => (entry.entityTable, entry.entityId)),
        unorderedEquals(<(String, String)>[
          (AppDatabase.dosesTable, result.doseId),
          (AppDatabase.protocolSkipsTable, skipId),
          (AppDatabase.protocolSkipsTable, sibling),
        ]),
      );
      final day = await repositories.protocols.protocolDay(today);
      expect(day.doses.single.id, result.doseId);
      expect(day.skips, isEmpty);
    });

    test('logDose(unskipId:) with an unknown Skip throws and writes no Dose',
        () async {
      await expectLater(
        repositories.protocols.logDose(
          creatineDose(DateTime(2026, 7, 10, 21, 5)),
          unskipId: 'missing',
        ),
        throwsStateError,
      );
      expect(await database.select(database.doses).get(), isEmpty);
    });

    test('undo reverses a skip, an unskip and a log-with-unskip', () async {
      // Undoing the skip tombstones the Skip.
      final skipBatch = await repositories.protocols.skipPlannedDose(
        draft(),
        today: today,
      );
      final skipId = (await skipRows()).single.id;
      final undoSkip = await repositories.activityLog.undoBatch(skipBatch);
      expect(undoSkip.conflicts, isEmpty);
      expect((await skipRow(skipId)).deletedAt, isNotNull);
      expect((await repositories.protocols.protocolDay(today)).skips, isEmpty);

      // Undoing an unskip brings both timed Skips back.
      final first = await skip(draft(localDate: yesterday));
      final sibling = await skip(draft(localDate: yesterday));
      final unskipBatch = await repositories.protocols.unskipPlannedDose(first);
      final undoUnskip = await repositories.activityLog.undoBatch(unskipBatch);
      expect(undoUnskip.conflicts, isEmpty);
      expect((await skipRow(first)).deletedAt, equals(null));
      expect((await skipRow(sibling)).deletedAt, equals(null));

      // Undoing a log-with-unskip removes the Dose and restores the Skip.
      final logged = await repositories.protocols.logDose(
        creatineDose(DateTime(2026, 7, 9, 21, 5)),
        unskipId: first,
      );
      final undoLog = await repositories.activityLog.undoBatch(logged.batchId);
      expect(undoLog.conflicts, isEmpty);
      final day = await repositories.protocols.protocolDay(yesterday);
      expect(day.doses, isEmpty);
      expect(
        day.skips.map((skip) => skip.id),
        unorderedEquals(<String>[first, sibling]),
      );
    });

    test(
        'a Skip is not history: a Protocol with only Skips can be deleted, '
        'its Skips stay stored, and undo brings the Protocol back', () async {
      final skipId = await skip(draft(localDate: yesterday));
      await skip(draft(plannedLocalTime: '08:00'));

      expect(
          await repositories.protocols.protocolHasHistory(protocolId), isFalse);
      final batchId = await repositories.protocols.deleteProtocol(protocolId);

      final skips = await skipRows();
      expect(skips, hasLength(2));
      expect(skips.every((row) => row.deletedAt == null), isTrue);
      expect(await batchEntries(batchId), hasLength(1));

      await repositories.activityLog.undoBatch(batchId);
      expect(
        (await repositories.protocols.listProtocols()).single.id,
        protocolId,
      );
      expect((await skipRow(skipId)).deletedAt, equals(null));
    });

    test('watchProtocolDay re-emits when a Skip is written or removed',
        () async {
      final emissions = <ProtocolDayRecord>[];
      final subscription =
          repositories.protocols.watchProtocolDay(today).listen(emissions.add);
      addTearDown(subscription.cancel);
      await _waitFor(() => emissions.isNotEmpty);
      expect(emissions.last.skips, isEmpty);

      final skipId = await skip(draft());
      await _waitFor(() => emissions.last.skips.isNotEmpty);
      expect(emissions.last.skips.single.id, skipId);

      await repositories.protocols.unskipPlannedDose(skipId);
      await _waitFor(() => emissions.last.skips.isEmpty);
    });
  });

  group('Compound editing and archived members (D4)', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    const start = ProtocolDayDate(year: 2026, month: 7, day: 1);

    Future<String> createCompoundId(String name) async {
      final result = await repositories.protocols.createCompound(
        CompoundDraft(
          name: name,
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
        ),
      );
      return result.compoundId;
    }

    Future<String> createProtocolId(List<String> compoundIds) async {
      final result = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Sleep',
          startLocalDate: start,
          compoundIds: compoundIds,
        ),
      );
      return result.protocolId;
    }

    Future<void> editProtocol(
      String protocolId,
      List<String> compoundIds, {
      String name = 'Sleep',
    }) {
      return repositories.protocols.editProtocol(
        protocolId,
        ProtocolDraft(
          name: name,
          startLocalDate: start,
          compoundIds: compoundIds,
        ),
      );
    }

    Future<ProtocolSummaryRecord> summaryOf(String protocolId) async {
      final summaries = await repositories.protocols.listProtocolSummaries();
      return summaries.singleWhere((summary) => summary.id == protocolId);
    }

    test('saving a Protocol with a member whose Compound is archived succeeds',
        () async {
      final magnesium = await createCompoundId('Magnesium');
      final glycine = await createCompoundId('Glycine');
      final protocolId = await createProtocolId(<String>[magnesium, glycine]);
      await repositories.protocols.archiveCompound(magnesium);

      await editProtocol(
        protocolId,
        <String>[magnesium, glycine],
        name: 'Better sleep',
      );

      final summary = await summaryOf(protocolId);
      expect(summary.name, 'Better sleep');
      expect(summary.compoundIds, <String>[magnesium, glycine]);
    });

    test('adding an archived Compound is rejected, and nothing is written',
        () async {
      final magnesium = await createCompoundId('Magnesium');
      final glycine = await createCompoundId('Glycine');
      final protocolId = await createProtocolId(<String>[magnesium]);
      await repositories.protocols.archiveCompound(glycine);

      await expectLater(
        editProtocol(protocolId, <String>[magnesium, glycine]),
        throwsArgumentError,
      );

      expect(
        (await summaryOf(protocolId)).compoundIds,
        <String>[magnesium],
      );
    });

    test('a member removed earlier counts as added: it must be active',
        () async {
      final magnesium = await createCompoundId('Magnesium');
      final glycine = await createCompoundId('Glycine');
      final protocolId = await createProtocolId(<String>[magnesium, glycine]);
      await editProtocol(protocolId, <String>[magnesium]);
      await repositories.protocols.archiveCompound(glycine);

      await expectLater(
        editProtocol(protocolId, <String>[magnesium, glycine]),
        throwsArgumentError,
      );
    });

    test('creating a Protocol with an archived Compound is still rejected',
        () async {
      final magnesium = await createCompoundId('Magnesium');
      await repositories.protocols.archiveCompound(magnesium);

      await expectLater(
        createProtocolId(<String>[magnesium]),
        throwsArgumentError,
      );
    });

    test('a live member whose Compound row is gone is still rejected',
        () async {
      final magnesium = await createCompoundId('Magnesium');
      final protocolId = await createProtocolId(<String>[magnesium]);
      // A foreign key normally prevents this; a guard still must not crash on
      // a null row if the database ever disagrees.
      await database.customStatement('PRAGMA foreign_keys = OFF');
      await database.customStatement(
        'DELETE FROM ${AppDatabase.compoundsTable} WHERE id = ?',
        <Object>[magnesium],
      );

      await expectLater(
        editProtocol(protocolId, <String>[magnesium]),
        throwsArgumentError,
      );
    });

    test('the draft\'s member order is kept across archived and added members',
        () async {
      final a = await createCompoundId('A');
      final b = await createCompoundId('B');
      final c = await createCompoundId('C');
      final added = await createCompoundId('D');
      final protocolId = await createProtocolId(<String>[a, b, c]);
      await repositories.protocols.archiveCompound(b);

      await editProtocol(protocolId, <String>[c, added, b, a]);

      expect(
        (await summaryOf(protocolId)).compoundIds,
        <String>[c, added, b, a],
      );
    });

    test('watchCompoundsByIds emits empty for an empty set', () async {
      await createCompoundId('Magnesium');

      expect(
        await repositories.protocols.watchCompoundsByIds(<String>{}).first,
        isEmpty,
      );
    });

    test(
        'watchCompoundsByIds returns archived Compounds with isArchived, '
        're-emits on archive, and ignores fields it does not carry', () async {
      final magnesium = await createCompoundId('Magnesium');
      final glycine = await createCompoundId('Glycine');
      final unrelated = await createCompoundId('Zinc');
      await repositories.protocols.archiveCompound(glycine);

      final emissions = <List<CompoundScheduleOptionRecord>>[];
      final subscription = repositories.protocols
          .watchCompoundsByIds(<String>{magnesium, glycine}).listen(
        emissions.add,
      );
      addTearDown(subscription.cancel);
      await _waitFor(() => emissions.isNotEmpty);

      expect(
        emissions.single.map((option) => (option.id, option.isArchived)),
        <(String, bool)>[(glycine, true), (magnesium, false)],
      );

      emissions.clear();
      await repositories.protocols.setFavorite(magnesium, isFavorite: true);
      await repositories.protocols.archiveCompound(unrelated);
      await pumpEventQueue(times: 5);
      expect(emissions, isEmpty);

      await repositories.protocols.archiveCompound(magnesium);
      await _waitFor(() => emissions.isNotEmpty);
      expect(
        emissions.last.every((option) => option.isArchived),
        isTrue,
      );
    });

    test('watchCompoundNamesByIds still leaves archived Compounds out',
        () async {
      final magnesium = await createCompoundId('Magnesium');
      await repositories.protocols.archiveCompound(magnesium);

      expect(
        await repositories.protocols
            .watchCompoundNamesByIds(<String>{magnesium}).first,
        isEmpty,
      );
    });

    test(
        'an unchanged editCompound writes nothing and returns null, with the '
        'name compared trimmed', () async {
      final created = await repositories.protocols.createCompound(
        CompoundDraft(
          name: 'Magnesium',
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('200 mg/capsule'),
        ),
      );
      final updatedAt =
          (await repositories.protocols.listCompounds()).single.updatedAt;
      final entries = (await repositories.activityLog.listEntries()).length;

      final batchId = await repositories.protocols.editCompound(
        created.compoundId,
        CompoundDraft(
          name: '  Magnesium ',
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('200 mg/capsule'),
        ),
      );

      expect(batchId, isNull);
      expect(
        (await repositories.protocols.listCompounds()).single.updatedAt,
        updatedAt,
      );
      expect(await repositories.activityLog.listEntries(), hasLength(entries));
    });

    test('an editCompound that changes any one field writes one Batch',
        () async {
      final created = await repositories.protocols.createCompound(
        CompoundDraft(
          name: 'Magnesium',
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('200 mg/capsule'),
        ),
      );
      final drafts = <CompoundDraft>[
        CompoundDraft(
          name: 'Magnesium glycinate',
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('200 mg/capsule'),
        ),
        CompoundDraft(
          name: 'Magnesium glycinate',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('200 mg/capsule'),
        ),
        CompoundDraft(
          name: 'Magnesium glycinate',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.sublingual,
          strength: CompoundStrength.parse('200 mg/capsule'),
        ),
        const CompoundDraft(
          name: 'Magnesium glycinate',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.sublingual,
        ),
      ];

      for (final draft in drafts) {
        final batchId = await repositories.protocols.editCompound(
          created.compoundId,
          draft,
        );

        expect(batchId, isNotNull);
        final batch = (await repositories.activityLog.listEntries())
            .where((entry) => entry.batchId == batchId);
        expect(batch, hasLength(1));
      }
    });

    test('a strength\'s storageValue parses back unchanged, for every unit',
        () {
      for (final massUnit in DoseUnit.values) {
        for (final perUnit in DoseUnit.values) {
          for (final amount in <String>['5', '0.5', '1000']) {
            final strength = CompoundStrength(
              amount: double.parse(amount),
              amountEntered: amount,
              massUnit: massUnit,
              perUnit: perUnit,
            );

            final parsed = CompoundStrength.parse(strength.storageValue);

            expect(parsed, strength);
            expect(parsed.storageValue, strength.storageValue);
          }
        }
      }
    });

    group('the Protocol Day controller', () {
      late ProviderContainer container;

      setUp(() {
        container = ProviderContainer(
          overrides: [
            trainingRepositoriesProvider.overrideWith((ref) => repositories),
          ],
        );
      });

      tearDown(() {
        container.dispose();
      });

      ProtocolDayController controller() =>
          container.read(protocolDayControllerProvider.notifier);

      test('countProtocolsWithCompound counts active Protocols that hold it',
          () async {
        final magnesium = await createCompoundId('Magnesium');
        final glycine = await createCompoundId('Glycine');
        final removed = await createProtocolId(<String>[magnesium, glycine]);
        await createProtocolId(<String>[magnesium]);
        final archived = await createProtocolId(<String>[magnesium]);
        await repositories.protocols.archiveProtocol(archived);

        expect(await controller().countProtocolsWithCompound(magnesium), 2);
        expect(await controller().countProtocolsWithCompound(glycine), 1);

        await editProtocol(removed, <String>[magnesium]);
        expect(await controller().countProtocolsWithCompound(glycine), 0);
      });

      test('latestDoseAmounts takes each last Dose and skips ids with none',
          () async {
        final magnesium = await createCompoundId('Magnesium');
        final glycine = await createCompoundId('Glycine');
        for (final (amount, tookAt) in <(double, DateTime)>[
          (200, DateTime.utc(2026, 6, 1, 8)),
          (400, DateTime.utc(2026, 6, 2, 8)),
        ]) {
          await repositories.protocols.logDose(
            DoseSnapshotDraft(
              compoundId: magnesium,
              compoundName: 'Magnesium',
              amountValue: amount,
              amountEntered: amount.toStringAsFixed(0),
              unit: DoseUnit.milligram,
              route: DoseRoute.oral,
              tookAt: tookAt,
            ),
          );
        }

        final amounts = await controller().latestDoseAmounts(
          <String>{magnesium, glycine},
        );

        expect(amounts.keys, <String>[magnesium]);
        expect(amounts[magnesium]!.amount, 400);
        expect(amounts[magnesium]!.unit, DoseUnit.milligram);
      });
    });
  });
}

/// Reconstructs the persisted snapshot image of a `Dose` row for an immutability
/// assertion, mirroring the repository's private `_doseImage` (the same keys the
/// Activity Log stores). Kept here so the test compares like-for-like.
Map<String, Object?> _doseImageForTest(DoseRow row) {
  String iso(DateTime value) => value.toUtc().toIso8601String();
  return <String, Object?>{
    'id': row.id,
    'compound_id': row.compoundId,
    'compound_name': row.compoundName,
    'compound_strength': row.compoundStrength,
    'amount_value': row.amountValue,
    'amount_entered': row.amountEntered,
    'unit': row.unit,
    'route': row.route,
    'took_at': iso(row.tookAt),
    'timezone': row.timezone,
    'local_date': row.localDate,
    'timezone_offset_minutes': row.timezoneOffsetMinutes,
    'provenance': row.provenance,
    'protocol_id': row.protocolId,
    'protocol_name': row.protocolName,
    'updated_at': iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : iso(row.deletedAt!),
  };
}

Future<void> _waitFor(bool Function() condition) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > const Duration(seconds: 2)) {
      fail('Timed out waiting for condition.');
    }
    await pumpEventQueue();
  }
}

/// One untimed dose a day: the nearest Schedule Rule to "once daily".
final _onceDaily = UntimedScheduleRule(
  days: const DailyScheduleDays(),
  count: 1,
);

class _EmptyOtcCompoundSeedSource implements OtcCompoundSeedSource {
  const _EmptyOtcCompoundSeedSource();

  @override
  List<OtcCompoundSeedRow> load() => const <OtcCompoundSeedRow>[];
}
