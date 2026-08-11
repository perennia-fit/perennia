import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/activity/repositories/activity_feed_repository.dart';

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

    test('the seed carries NO type/legality categorization field',
        () async {
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

    test('watchCompoundScheduleOptions emits only for schedule seed data',
        () async {
      final created = await repositories.protocols.createCompound(
        CompoundDraft(
          name: 'Creatine',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('5 g/capsule'),
        ),
      );

      final emissions = <List<CompoundScheduleOptionRecord>>[];
      final subscription = repositories.protocols
          .watchCompoundScheduleOptions()
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      await _waitFor(() => emissions.isNotEmpty);
      expect(emissions.last.single.id, created.compoundId);
      expect(emissions.last.single.name, 'Creatine');
      expect(emissions.last.single.defaultUnit, DoseUnit.gram);
      expect(emissions.last.single.defaultRoute, DoseRoute.oral);

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
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.oral,
          strength: CompoundStrength.parse('10 g/capsule'),
        ),
      );
      await pumpEventQueue(times: 5);
      expect(emissions, isEmpty);

      await repositories.protocols.editCompound(
        created.compoundId,
        CompoundDraft(
          name: 'Creatine',
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.sublingual,
          strength: CompoundStrength.parse('10000 mg/capsule'),
        ),
      );
      await _waitFor(
        () => emissions.any(
          (options) =>
              options.single.defaultUnit == DoseUnit.milligram &&
              options.single.defaultRoute == DoseRoute.sublingual,
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
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId],
        ),
      );
      final unrelated = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Recovery',
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[magnesiumId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            magnesiumId: const ScheduleDraft(
              doseAmountValue: 400,
              doseAmountEntered: '400',
              doseUnit: DoseUnit.milligram,
              frequency: ScheduleFrequency.onceDaily,
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
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            creatineId: const ScheduleDraft(
              doseAmountValue: 5,
              doseAmountEntered: '5',
              doseUnit: DoseUnit.gram,
              frequency: ScheduleFrequency.onceDaily,
              route: DoseRoute.oral,
            ),
          },
        ),
      );

      await _waitFor(() => emissions.length > initialEmissionCount);
      expect(emissions.last?.members.single.schedule, isNotNull);
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
          'start_date',
          'end_date',
          'updated_at',
          'deleted_at',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.protocolCompoundsTable],
        containsAll(<String>[
          'id',
          'protocol_id',
          'compound_id',
          'position',
          'updated_at',
          'deleted_at',
        ]),
      );
      // Archive is the deletedAt tombstone, not a separate flag (mirrors
      // Compound/Exercise/Food, PROTOCOLS.md §7).
      expect(
        columnsByTable[AppDatabase.protocolsTable]!
            .any((c) => c.contains('archiv')),
        isFalse,
      );
    });

    test('creates a named, time-bounded Protocol with one Compound', () async {
      final creatineId = await createCompoundId('Creatine');
      final startDate = DateTime.utc(2026, 7, 1);
      final endDate = DateTime.utc(2026, 9, 1);

      final result = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startDate: startDate,
          endDate: endDate,
          compoundIds: <String>[creatineId],
        ),
      );

      final protocols = await repositories.protocols.listProtocols();
      expect(protocols, hasLength(1));
      final protocol = protocols.single;
      expect(protocol.id, result.protocolId);
      expect(protocol.name, 'Lean bulk');
      // Drift returns DateTimes in local time; compare the instant, not the
      // tagged zone (the same UTC moment was stored).
      expect(protocol.startDate.toUtc(), startDate);
      expect(protocol.endDate!.toUtc(), endDate);
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
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId, vitaminDId, magnesiumId],
        ),
      );

      final protocol = (await repositories.protocols.listProtocols())
          .firstWhere((p) => p.id == result.protocolId);
      expect(protocol.isStack, isTrue);
      expect(protocol.endDate, isNull); // open-ended (ongoing) course
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
            startDate: DateTime.utc(2026, 7, 1),
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
            startDate: DateTime.utc(2026, 7, 1),
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
            startDate: DateTime.utc(2026, 9, 1),
            endDate: DateTime.utc(2026, 7, 1),
            compoundIds: <String>[creatineId],
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(await repositories.protocols.listProtocols(), isEmpty);
    });

    test('creating a Protocol rejects a Compound id that does not exist',
        () async {
      await expectLater(
        () => repositories.protocols.createProtocol(
          ProtocolDraft(
            name: 'Ghost stack',
            startDate: DateTime.utc(2026, 7, 1),
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
            startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId],
        ),
      );

      final newStart = DateTime.utc(2026, 8, 1);
      final newEnd = DateTime.utc(2026, 10, 1);
      await repositories.protocols.editProtocol(
        created.protocolId,
        ProtocolDraft(
          name: 'Lean bulk v2',
          startDate: newStart,
          endDate: newEnd,
          compoundIds: <String>[creatineId],
        ),
      );

      final protocol = (await repositories.protocols.listProtocols()).single;
      expect(protocol.name, 'Lean bulk v2');
      expect(protocol.startDate.toUtc(), newStart);
      expect(protocol.endDate!.toUtc(), newEnd);
    });

    test('editing a Protocol supports adding and removing Compounds', () async {
      final creatineId = await createCompoundId('Creatine');
      final vitaminDId = await createCompoundId('Vitamin D');
      final magnesiumId = await createCompoundId('Magnesium');

      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Stack',
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId, vitaminDId],
        ),
      );

      // Drop Vitamin D, add Magnesium, and re-order: Magnesium first.
      await repositories.protocols.editProtocol(
        created.protocolId,
        ProtocolDraft(
          name: 'Stack',
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId],
        ),
      );
      await repositories.protocols.editProtocol(
        created.protocolId,
        ProtocolDraft(
          name: 'Lean bulk v2',
          startDate: DateTime.utc(2026, 7, 1),
          endDate: DateTime.utc(2026, 9, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            creatineId: const ScheduleDraft(
              doseAmountValue: 5,
              doseAmountEntered: '5',
              doseUnit: DoseUnit.gram,
              frequency: ScheduleFrequency.onceDaily,
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
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            creatineId: const ScheduleDraft(
              doseAmountValue: 5,
              doseAmountEntered: '5',
              doseUnit: DoseUnit.gram,
              frequency: ScheduleFrequency.onceDaily,
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
  group('Schedule (optional per-Compound plan)', () {
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

    test('opens a Schedules schema with no archive flag column', () async {
      final columnsByTable = await database.describeSchema();

      expect(columnsByTable.keys, contains(AppDatabase.schedulesTable));
      expect(
        columnsByTable[AppDatabase.schedulesTable],
        containsAll(<String>[
          'id',
          'protocol_compound_id',
          'dose_amount_value',
          'dose_amount_entered',
          'dose_unit',
          'frequency',
          'route',
          'updated_at',
          'deleted_at',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.schedulesTable]!
            .any((c) => c.contains('archiv')),
        isFalse,
      );
    });

    test('a Protocol with no Schedules at all is still valid', () async {
      final creatineId = await createCompoundId('Creatine');
      final result = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId],
        ),
      );

      final protocol = (await repositories.protocols.listProtocols())
          .firstWhere((p) => p.id == result.protocolId);
      expect(protocol.members.single.schedule, isNull);
    });

    test('creating a Protocol attaches an optional Schedule to a member',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final vitaminDId = await createCompoundId('Vitamin D');

      final result = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId, vitaminDId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            creatineId: const ScheduleDraft(
              doseAmountValue: 5,
              doseAmountEntered: '5',
              doseUnit: DoseUnit.gram,
              frequency: ScheduleFrequency.onceDaily,
              route: DoseRoute.oral,
            ),
          },
        ),
      );

      final protocol = (await repositories.protocols.listProtocols())
          .firstWhere((p) => p.id == result.protocolId);
      final creatineMember =
          protocol.members.firstWhere((m) => m.compoundId == creatineId);
      final vitaminDMember =
          protocol.members.firstWhere((m) => m.compoundId == vitaminDId);

      expect(creatineMember.schedule, isNotNull);
      expect(creatineMember.schedule!.doseAmountValue, 5);
      expect(creatineMember.schedule!.doseAmountEntered, '5');
      expect(creatineMember.schedule!.doseUnit, DoseUnit.gram);
      expect(creatineMember.schedule!.frequency, ScheduleFrequency.onceDaily);
      expect(creatineMember.schedule!.route, DoseRoute.oral);
      // Vitamin D carries no Schedule — optional, and still a valid member.
      expect(vitaminDMember.schedule, isNull);
    });

    test('editing a Protocol adds a Schedule to a member that had none',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId],
        ),
      );

      await repositories.protocols.editProtocol(
        created.protocolId,
        ProtocolDraft(
          name: 'Lean bulk',
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            creatineId: const ScheduleDraft(
              doseAmountValue: 5,
              doseAmountEntered: '5',
              doseUnit: DoseUnit.gram,
              frequency: ScheduleFrequency.twiceDaily,
              route: DoseRoute.oral,
            ),
          },
        ),
      );

      final protocol = (await repositories.protocols.listProtocols()).single;
      expect(protocol.members.single.schedule, isNotNull);
      expect(
        protocol.members.single.schedule!.frequency,
        ScheduleFrequency.twiceDaily,
      );
    });

    test('editing a Protocol updates an existing Schedule in place', () async {
      final creatineId = await createCompoundId('Creatine');
      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            creatineId: const ScheduleDraft(
              doseAmountValue: 5,
              doseAmountEntered: '5',
              doseUnit: DoseUnit.gram,
              frequency: ScheduleFrequency.onceDaily,
              route: DoseRoute.oral,
            ),
          },
        ),
      );
      final originalScheduleId = (await repositories.protocols.listProtocols())
          .single
          .members
          .single
          .schedule!
          .id;

      await repositories.protocols.editProtocol(
        created.protocolId,
        ProtocolDraft(
          name: 'Lean bulk',
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            creatineId: const ScheduleDraft(
              doseAmountValue: 10,
              doseAmountEntered: '10',
              doseUnit: DoseUnit.gram,
              frequency: ScheduleFrequency.twiceDaily,
              route: DoseRoute.sublingual,
            ),
          },
        ),
      );

      final protocol = (await repositories.protocols.listProtocols()).single;
      final schedule = protocol.members.single.schedule!;
      // Same identity, updated in place — not a new row.
      expect(schedule.id, originalScheduleId);
      expect(schedule.doseAmountEntered, '10');
      expect(schedule.frequency, ScheduleFrequency.twiceDaily);
      expect(schedule.route, DoseRoute.sublingual);
    });

    test('editing a Protocol removes a Schedule by mapping it to null',
        () async {
      final creatineId = await createCompoundId('Creatine');
      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            creatineId: const ScheduleDraft(
              doseAmountValue: 5,
              doseAmountEntered: '5',
              doseUnit: DoseUnit.gram,
              frequency: ScheduleFrequency.onceDaily,
              route: DoseRoute.oral,
            ),
          },
        ),
      );

      await repositories.protocols.editProtocol(
        created.protocolId,
        ProtocolDraft(
          name: 'Lean bulk',
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            creatineId: null,
          },
        ),
      );

      final protocol = (await repositories.protocols.listProtocols()).single;
      expect(protocol.members.single.schedule, isNull);

      // The row survives as a tombstone (never a hard delete of plan data).
      final rows = await database.select(database.schedules).get();
      expect(rows, hasLength(1));
      expect(rows.single.deletedAt, isNotNull);
    });

    test(
        'removing a Compound from a Protocol also retires its Schedule '
        '(no orphaned plan row)', () async {
      final creatineId = await createCompoundId('Creatine');
      final vitaminDId = await createCompoundId('Vitamin D');
      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Stack',
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId, vitaminDId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            creatineId: const ScheduleDraft(
              doseAmountValue: 5,
              doseAmountEntered: '5',
              doseUnit: DoseUnit.gram,
              frequency: ScheduleFrequency.onceDaily,
              route: DoseRoute.oral,
            ),
          },
        ),
      );

      // Drop Creatine (and its Schedule) from the stack.
      await repositories.protocols.editProtocol(
        created.protocolId,
        ProtocolDraft(
          name: 'Stack',
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[vitaminDId],
        ),
      );

      final protocol = (await repositories.protocols.listProtocols()).single;
      expect(protocol.members, hasLength(1));
      expect(protocol.members.single.compoundId, vitaminDId);

      final rows = await database.select(database.schedules).get();
      expect(rows, hasLength(1));
      expect(rows.single.deletedAt, isNotNull);
    });

    test(
        'a hard-reject (negative planned dose) throws and persists nothing — '
        'the SAME shared two-tier validator as a logged Dose (PROTOCOLS.md §6)',
        () async {
      final creatineId = await createCompoundId('Creatine');

      await expectLater(
        () => repositories.protocols.createProtocol(
          ProtocolDraft(
            name: 'Lean bulk',
            startDate: DateTime.utc(2026, 7, 1),
            compoundIds: <String>[creatineId],
            schedulesByCompoundId: <String, ScheduleDraft?>{
              creatineId: const ScheduleDraft(
                doseAmountValue: -1,
                doseAmountEntered: '-1',
                doseUnit: DoseUnit.gram,
                frequency: ScheduleFrequency.onceDaily,
                route: DoseRoute.oral,
              ),
            },
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

      expect(await repositories.protocols.listProtocols(), isEmpty);
      expect(await database.select(database.schedules).get(), isEmpty);
    });

    test('creating a Schedule writes one reversible Activity Log entry',
        () async {
      final creatineId = await createCompoundId('Creatine');

      final result = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            creatineId: const ScheduleDraft(
              doseAmountValue: 5,
              doseAmountEntered: '5',
              doseUnit: DoseUnit.gram,
              frequency: ScheduleFrequency.onceDaily,
              route: DoseRoute.oral,
            ),
          },
        ),
      );

      final batchEntries = (await repositories.activityLog.listEntries())
          .where((e) => e.batchId == result.batchId)
          .toList();
      final scheduleEntry = batchEntries.singleWhere(
        (e) => e.entityTable == AppDatabase.schedulesTable,
      );
      expect(scheduleEntry.beforeImage, isNull);
      expect(scheduleEntry.afterImage!['dose_amount_entered'], '5');
      expect(scheduleEntry.afterImage!['frequency'], 'onceDaily');

      // Reversible: undoing the whole creation batch retires the Protocol and
      // its Schedule together (tombstoned, mirroring every other create-undo
      // in this domain — never a physical row removal).
      await repositories.activityLog.undoBatch(result.batchId);
      expect(await repositories.protocols.listProtocols(), isEmpty);
      final scheduleRow = await database.select(database.schedules).getSingle();
      expect(scheduleRow.deletedAt, isNotNull);
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
        ProtocolDraft(
          name: 'Lean bulk',
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            creatineId: const ScheduleDraft(
              doseAmountValue: 5,
              doseAmountEntered: '5',
              doseUnit: DoseUnit.gram,
              frequency: ScheduleFrequency.onceDaily,
              route: DoseRoute.oral,
            ),
          },
        ),
      );
      await repositories.protocols.editProtocol(
        created.protocolId,
        ProtocolDraft(
          name: 'Lean bulk',
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            creatineId: const ScheduleDraft(
              doseAmountValue: 10,
              doseAmountEntered: '10',
              doseUnit: DoseUnit.gram,
              frequency: ScheduleFrequency.twiceDaily,
              route: DoseRoute.oral,
            ),
          },
        ),
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
        ProtocolDraft(
          name: 'Lean bulk',
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId],
        ),
      );

      final emissions = <bool>[];
      final subscription = repositories.protocols.watchProtocols().listen(
            (protocols) => emissions.add(
              protocols.single.members.single.schedule != null,
            ),
          );
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);
      expect(emissions.last, isFalse);

      await repositories.protocols.editProtocol(
        created.protocolId,
        ProtocolDraft(
          name: 'Lean bulk',
          startDate: DateTime.utc(2026, 7, 1),
          compoundIds: <String>[creatineId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            creatineId: const ScheduleDraft(
              doseAmountValue: 5,
              doseAmountEntered: '5',
              doseUnit: DoseUnit.gram,
              frequency: ScheduleFrequency.onceDaily,
              route: DoseRoute.oral,
            ),
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emissions.last, isTrue);
    });

    test(
      'watchProtocolOptions ignores detail edits and emits on visible changes',
      () async {
        final creatineId = await createCompoundId('Creatine');
        final created = await repositories.protocols.createProtocol(
          ProtocolDraft(
            name: 'Lean bulk',
            startDate: DateTime.utc(2026, 7, 1),
            compoundIds: <String>[creatineId],
          ),
        );

        final emissions = <List<ProtocolOptionRecord>>[];
        final subscription =
            repositories.protocols.watchProtocolOptions().listen(emissions.add);
        addTearDown(subscription.cancel);
        await Future<void>.delayed(Duration.zero);
        expect(
          emissions.map((options) => options.single.name),
          <String>['Lean bulk'],
        );

        await repositories.protocols.editProtocol(
          created.protocolId,
          ProtocolDraft(
            name: 'Lean bulk',
            startDate: DateTime.utc(2026, 7, 1),
            compoundIds: <String>[creatineId],
            schedulesByCompoundId: <String, ScheduleDraft?>{
              creatineId: const ScheduleDraft(
                doseAmountValue: 5,
                doseAmountEntered: '5',
                doseUnit: DoseUnit.gram,
                frequency: ScheduleFrequency.onceDaily,
                route: DoseRoute.oral,
              ),
            },
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          emissions.map((options) => options.single.name),
          <String>['Lean bulk'],
        );

        await repositories.protocols.editProtocol(
          created.protocolId,
          ProtocolDraft(
            name: 'Maintenance',
            startDate: DateTime.utc(2026, 7, 1),
            compoundIds: <String>[creatineId],
            schedulesByCompoundId: <String, ScheduleDraft?>{
              creatineId: const ScheduleDraft(
                doseAmountValue: 5,
                doseAmountEntered: '5',
                doseUnit: DoseUnit.gram,
                frequency: ScheduleFrequency.onceDaily,
                route: DoseRoute.oral,
              ),
            },
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          emissions.map((options) => options.single.name),
          <String>['Lean bulk', 'Maintenance'],
        );
      },
    );
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
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
            startDate: DateTime.utc(2026, 7, 1),
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
            startDate: DateTime.utc(2026, 7, 1),
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
            startDate: DateTime.utc(2026, 7, 1),
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
            startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
            startDate: DateTime.utc(2026, 7, 1),
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
            startDate: DateTime.utc(2026, 7, 1),
            compoundIds: <String>[creatineId],
            schedulesByCompoundId: <String, ScheduleDraft?>{
              creatineId: const ScheduleDraft(
                doseAmountValue: 5,
                doseAmountEntered: '5',
                doseUnit: DoseUnit.gram,
                frequency: ScheduleFrequency.onceDaily,
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
            startDate: DateTime.utc(2026, 7, 1),
            compoundIds: <String>[creatineId],
            schedulesByCompoundId: <String, ScheduleDraft?>{
              creatineId: const ScheduleDraft(
                doseAmountValue: 5,
                doseAmountEntered: '5',
                doseUnit: DoseUnit.gram,
                frequency: ScheduleFrequency.onceDaily,
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
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
          startDate: DateTime.utc(2026, 7, 1),
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
