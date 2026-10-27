import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// The v61 cutover to the Protocol plan shape: Protocol plans entered before
/// it (Protocols, their members, Schedules and target outcomes) are cleared
/// once, with their Activity Log, deferred and quarantined sync rows, while
/// Compounds and Doses survive untouched.
void main() {
  final previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
  });

  const planTables = <String>[
    AppDatabase.protocolsTable,
    AppDatabase.protocolCompoundsTable,
    AppDatabase.schedulesTable,
    AppDatabase.protocolTargetOutcomesTable,
  ];

  late Directory directory;
  late AppDatabase database;
  late AppDatabase fresh;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'prn_protocol_plan_migration_',
    );
    final file = File('${directory.path}/v60.sqlite');
    _createV60Database(file);
    database = AppDatabase.openFile(file);
    await database.customSelect('SELECT 1').get();
    fresh = AppDatabase.inMemory();
    await fresh.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await database.close();
    await fresh.close();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  test('schema 60 upgrades to the current schema', () async {
    final userVersion =
        await database.customSelect('PRAGMA user_version').getSingle();
    expect(userVersion.read<int>('user_version'), fresh.schemaVersion);
    expect(fresh.schemaVersion, 62);
  });

  test('Compounds and Doses survive unchanged, Protocol tag included',
      () async {
    final compound =
        await database.customSelect('SELECT * FROM compounds').getSingle();
    expect(compound.data, <String, Object?>{
      'id': 'compound-v60',
      'name': 'Creatine',
      'default_unit': 'gram',
      'default_route': 'oral',
      'strength': null,
      'is_favorite': 0,
      'sync_device_id': 'device-a',
      'sync_previously_synced': 1,
      'updated_at': 1783731600,
      'deleted_at': null,
    });

    final dose = await database.customSelect('SELECT * FROM doses').getSingle();
    expect(dose.data, <String, Object?>{
      'id': 'dose-v60',
      'compound_id': 'compound-v60',
      'compound_name': 'Creatine',
      'compound_strength': null,
      'amount_value': 5.0,
      'amount_entered': '5',
      'unit': 'gram',
      'route': 'oral',
      'took_at': 1783731600,
      'timezone': 'BRT',
      'local_date': '2026-07-11',
      'provenance': 'manual',
      'protocol_id': 'protocol-v60',
      'protocol_name': 'Lean bulk',
      'sync_device_id': 'device-a',
      'sync_previously_synced': 1,
      'updated_at': 1783731600,
      'deleted_at': null,
      // The new column, added in place: a Dose logged before it has none.
      'timezone_offset_minutes': null,
    });
  });

  test(
      'the four plan tables, and their Activity Log, deferred and '
      'quarantined rows, are gone', () async {
    for (final table in planTables) {
      expect(
        await database.customSelect('SELECT * FROM $table').get(),
        isEmpty,
        reason: table,
      );
    }

    final activity = await database
        .customSelect('SELECT id, entity_table FROM activity_log')
        .get();
    expect(
      activity.map((row) => row.read<String>('id')),
      <String>['activity-dose-v60'],
    );
    final deferred = await database
        .customSelect('SELECT entity_table FROM deferred_sync_changes')
        .get();
    expect(
      deferred.map((row) => row.read<String>('entity_table')),
      <String>[AppDatabase.dosesTable],
    );
    final quarantined = await database
        .customSelect('SELECT entity_table FROM quarantined_sync_changes')
        .get();
    expect(
      quarantined.map((row) => row.read<String>('entity_table')),
      <String>[AppDatabase.dosesTable],
    );
  });

  test('nothing is pending sync, and the foreign key check is clean', () async {
    final pending = await database
        .customSelect(
          'SELECT id FROM activity_log '
          'WHERE deleted_at IS NULL '
          'AND sync_acknowledged_at IS NULL '
          'AND after_image IS NOT NULL',
        )
        .get();
    expect(pending, isEmpty);
    expect(
      await database.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );
  });

  test('the upgraded plan tables equal a fresh database', () async {
    for (final table in <String>[
      ...planTables,
      AppDatabase.compoundsTable,
      AppDatabase.dosesTable,
    ]) {
      expect(
        await _columnDefinitions(database, table),
        unorderedEquals(await _columnDefinitions(fresh, table)),
        reason: '$table column definitions differ from a fresh database',
      );
      expect(
        await _indexNames(database, table),
        await _indexNames(fresh, table),
        reason: '$table indexes differ from a fresh database',
      );
      expect(
        await _foreignKeys(database, table),
        await _foreignKeys(fresh, table),
        reason: '$table foreign keys differ from a fresh database',
      );
    }
    expect(
      await _columnNames(database, AppDatabase.protocolsTable),
      isNot(contains(anyOf('start_date', 'end_date'))),
    );
    expect(
      await _columnNames(database, AppDatabase.schedulesTable),
      isNot(contains('frequency')),
    );
    expect(
      await _indexNames(database, AppDatabase.schedulesTable),
      contains('schedules_protocol_compound_effective_from_index'),
    );
  });

  test('the new plan shape accepts a Protocol, a member and a version',
      () async {
    await database.customStatement('''
      INSERT INTO protocols (id, name, start_local_date, updated_at)
        VALUES ('protocol-v61', 'Daily', '2026-07-01', 1783731600);
      INSERT INTO protocol_compounds (
        id, protocol_id, compound_id, position, updated_at
      ) VALUES ('member-v61', 'protocol-v61', 'compound-v60', 0, 1783731600);
      INSERT INTO schedules (
        id, protocol_compound_id, effective_from, rule, updated_at
      ) VALUES (
        'version-v61', 'member-v61', '2026-07-01',
        '{"v":1,"kind":"as_needed"}', 1783731600
      );
    ''');

    final protocol = await database.select(database.protocols).getSingle();
    expect(protocol.remindersEnabled, isFalse);
    expect(protocol.period, isNull);
    expect(protocol.archivedOn, isNull);
    final version = await database.select(database.schedules).getSingle();
    expect(version.doseAmountValue, isNull);
    expect(
      await database.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );
  });
}

Future<Set<String>> _columnNames(
  AppDatabase database,
  String tableName,
) async {
  final rows =
      await database.customSelect('PRAGMA table_info($tableName)').get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

/// Each column's name, type, nullability, default and key: everything but
/// its position, since a column added in place sits last.
Future<List<String>> _columnDefinitions(
  AppDatabase database,
  String tableName,
) async {
  final rows =
      await database.customSelect('PRAGMA table_info($tableName)').get();
  return rows
      .map(
        (row) => <Object?>[
          row.read<String>('name'),
          row.read<String>('type'),
          row.read<int>('notnull'),
          row.data['dflt_value'],
          row.read<int>('pk'),
        ].join('|'),
      )
      .toList(growable: false);
}

Future<Set<String>> _indexNames(
  AppDatabase database,
  String tableName,
) async {
  final rows =
      await database.customSelect('PRAGMA index_list($tableName)').get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

Future<Set<String>> _foreignKeys(
  AppDatabase database,
  String tableName,
) async {
  final rows =
      await database.customSelect('PRAGMA foreign_key_list($tableName)').get();
  return rows
      .map(
        (row) => '${row.read<String>('from')}->'
            '${row.read<String>('table')}.${row.read<String>('to')}:'
            '${row.read<String>('on_delete')}',
      )
      .toSet();
}

/// The schema-60 shape of every table the cutover touches, as a fresh v60
/// database created it, seeded with one plan in the old shape, a Compound
/// and a Dose tagged to it, and pending, deferred and quarantined sync rows
/// for the four plan tables beside rows for other tables that must survive.
void _createV60Database(File file) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    database.execute('''
      CREATE TABLE "metrics" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "unit" TEXT NOT NULL, "value_shape" TEXT NOT NULL, "metric_group" TEXT NOT NULL, "goal_type" TEXT NULL, "goal_target_value" REAL NULL, "enabled" INTEGER NOT NULL DEFAULT 1 CHECK ("enabled" IN (0, 1)), "pinned" INTEGER NOT NULL DEFAULT 0 CHECK ("pinned" IN (0, 1)), "sort_order" INTEGER NOT NULL, "sync_device_id" TEXT NULL, "sync_previously_synced" INTEGER NOT NULL DEFAULT 0 CHECK ("sync_previously_synced" IN (0, 1)), "updated_at" INTEGER NOT NULL, "deleted_at" INTEGER NULL, PRIMARY KEY ("id"));
      CREATE INDEX metrics_sort_order_index ON metrics (sort_order);
      CREATE TABLE "compounds" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "default_unit" TEXT NOT NULL, "default_route" TEXT NOT NULL, "strength" TEXT NULL, "is_favorite" INTEGER NOT NULL DEFAULT 0 CHECK ("is_favorite" IN (0, 1)), "sync_device_id" TEXT NULL, "sync_previously_synced" INTEGER NOT NULL DEFAULT 0 CHECK ("sync_previously_synced" IN (0, 1)), "updated_at" INTEGER NOT NULL, "deleted_at" INTEGER NULL, PRIMARY KEY ("id"));
      CREATE INDEX compounds_name_index ON compounds (name);
      CREATE TABLE "doses" ("id" TEXT NOT NULL, "compound_id" TEXT NULL, "compound_name" TEXT NOT NULL, "compound_strength" TEXT NULL, "amount_value" REAL NOT NULL, "amount_entered" TEXT NOT NULL, "unit" TEXT NOT NULL, "route" TEXT NOT NULL, "took_at" INTEGER NOT NULL, "timezone" TEXT NOT NULL, "local_date" TEXT NOT NULL DEFAULT '1970-01-01', "provenance" TEXT NOT NULL DEFAULT 'manual', "protocol_id" TEXT NULL, "protocol_name" TEXT NULL, "sync_device_id" TEXT NULL, "sync_previously_synced" INTEGER NOT NULL DEFAULT 0 CHECK ("sync_previously_synced" IN (0, 1)), "updated_at" INTEGER NOT NULL, "deleted_at" INTEGER NULL, PRIMARY KEY ("id"));
      CREATE INDEX doses_compound_id_index ON doses (compound_id);
      CREATE INDEX doses_local_date_index ON doses (local_date);
      CREATE TABLE "protocols" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "start_date" INTEGER NOT NULL, "end_date" INTEGER NULL, "sync_device_id" TEXT NULL, "sync_previously_synced" INTEGER NOT NULL DEFAULT 0 CHECK ("sync_previously_synced" IN (0, 1)), "updated_at" INTEGER NOT NULL, "deleted_at" INTEGER NULL, PRIMARY KEY ("id"));
      CREATE TABLE "protocol_compounds" ("id" TEXT NOT NULL, "protocol_id" TEXT NOT NULL REFERENCES protocols (id), "compound_id" TEXT NOT NULL REFERENCES compounds (id), "position" INTEGER NOT NULL, "sync_device_id" TEXT NULL, "sync_previously_synced" INTEGER NOT NULL DEFAULT 0 CHECK ("sync_previously_synced" IN (0, 1)), "updated_at" INTEGER NOT NULL, "deleted_at" INTEGER NULL, PRIMARY KEY ("id"));
      CREATE INDEX protocol_compounds_compound_id_index ON protocol_compounds (compound_id);
      CREATE INDEX protocol_compounds_protocol_id_index ON protocol_compounds (protocol_id);
      CREATE TABLE "schedules" ("id" TEXT NOT NULL, "protocol_compound_id" TEXT NOT NULL REFERENCES protocol_compounds (id), "dose_amount_value" REAL NOT NULL, "dose_amount_entered" TEXT NOT NULL, "dose_unit" TEXT NOT NULL, "frequency" TEXT NOT NULL, "route" TEXT NOT NULL, "sync_device_id" TEXT NULL, "sync_previously_synced" INTEGER NOT NULL DEFAULT 0 CHECK ("sync_previously_synced" IN (0, 1)), "updated_at" INTEGER NOT NULL, "deleted_at" INTEGER NULL, PRIMARY KEY ("id"));
      CREATE INDEX schedules_protocol_compound_id_index ON schedules (protocol_compound_id);
      CREATE TABLE "protocol_target_outcomes" ("id" TEXT NOT NULL, "protocol_id" TEXT NOT NULL REFERENCES protocols (id), "kind" TEXT NOT NULL, "metric_id" TEXT NULL REFERENCES metrics (id), "position" INTEGER NOT NULL, "sync_device_id" TEXT NULL, "sync_previously_synced" INTEGER NOT NULL DEFAULT 0 CHECK ("sync_previously_synced" IN (0, 1)), "updated_at" INTEGER NOT NULL, "deleted_at" INTEGER NULL, PRIMARY KEY ("id"));
      CREATE INDEX protocol_target_outcomes_protocol_id_index ON protocol_target_outcomes (protocol_id);
      CREATE TABLE "activity_log" ("id" TEXT NOT NULL, "actor" TEXT NOT NULL, "batch_id" TEXT NOT NULL, "entity_table" TEXT NOT NULL, "entity_id" TEXT NOT NULL, "before_image" TEXT NULL, "after_image" TEXT NULL, "occurred_at" INTEGER NOT NULL, "sync_acknowledged_at" INTEGER NULL, "updated_at" INTEGER NOT NULL, "deleted_at" INTEGER NULL, PRIMARY KEY ("id"));
      CREATE INDEX activity_log_batch_id_index ON activity_log (batch_id);
      CREATE INDEX activity_log_pending_sync_index ON activity_log (entity_table) WHERE deleted_at IS NULL AND sync_acknowledged_at IS NULL AND after_image IS NOT NULL;
      CREATE TABLE "deferred_sync_changes" ("entity_table" TEXT NOT NULL, "entity_id" TEXT NOT NULL, "missing_entity_table" TEXT NOT NULL, "missing_entity_id" TEXT NOT NULL, "change_json" TEXT NOT NULL, "updated_at" INTEGER NOT NULL, "device_id" TEXT NOT NULL, "deferred_at" INTEGER NOT NULL, PRIMARY KEY ("entity_table", "entity_id"));
      CREATE INDEX deferred_sync_changes_missing_entity_index ON deferred_sync_changes (missing_entity_table, missing_entity_id);
      CREATE TABLE "quarantined_sync_changes" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "entity_table" TEXT NULL, "entity_id" TEXT NULL, "change_json" TEXT NOT NULL, "failure_kind" TEXT NOT NULL, "quarantined_at" INTEGER NOT NULL);
      CREATE UNIQUE INDEX quarantined_sync_changes_entity_index ON quarantined_sync_changes (entity_table, entity_id);

      INSERT INTO metrics (
        id, name, unit, value_shape, metric_group, sort_order, updated_at
      ) VALUES (
        'metric-v60', 'Body Weight', 'kg', 'scalar', 'body_composition', 0,
        1783731600
      );
      INSERT INTO compounds (
        id, name, default_unit, default_route, sync_device_id,
        sync_previously_synced, updated_at
      ) VALUES (
        'compound-v60', 'Creatine', 'gram', 'oral', 'device-a', 1, 1783731600
      );
      INSERT INTO protocols (id, name, start_date, updated_at)
        VALUES ('protocol-v60', 'Lean bulk', 1782864000, 1783731600);
      INSERT INTO protocol_compounds (
        id, protocol_id, compound_id, position, updated_at
      ) VALUES ('member-v60', 'protocol-v60', 'compound-v60', 0, 1783731600);
      INSERT INTO schedules (
        id, protocol_compound_id, dose_amount_value, dose_amount_entered,
        dose_unit, frequency, route, updated_at
      ) VALUES (
        'schedule-v60', 'member-v60', 5, '5', 'gram', 'onceDaily', 'oral',
        1783731600
      );
      INSERT INTO protocol_target_outcomes (
        id, protocol_id, kind, metric_id, position, updated_at
      ) VALUES (
        'outcome-v60', 'protocol-v60', 'metric', 'metric-v60', 0, 1783731600
      );
      INSERT INTO doses (
        id, compound_id, compound_name, amount_value, amount_entered, unit,
        route, took_at, timezone, local_date, protocol_id, protocol_name,
        sync_device_id, sync_previously_synced, updated_at
      ) VALUES (
        'dose-v60', 'compound-v60', 'Creatine', 5, '5', 'gram', 'oral',
        1783731600, 'BRT', '2026-07-11', 'protocol-v60', 'Lean bulk',
        'device-a', 1, 1783731600
      );

      INSERT INTO activity_log (
        id, actor, batch_id, entity_table, entity_id, before_image,
        after_image, occurred_at, sync_acknowledged_at, updated_at
      ) VALUES
        ('activity-protocol-v60', 'manual', 'batch-v60', 'protocols',
          'protocol-v60', NULL, '{"start_date":"2026-07-01T00:00:00.000Z"}',
          1783731600, NULL, 1783731600),
        ('activity-member-v60', 'manual', 'batch-v60', 'protocol_compounds',
          'member-v60', NULL, '{}', 1783731600, NULL, 1783731600),
        ('activity-schedule-v60', 'manual', 'batch-v60', 'schedules',
          'schedule-v60', NULL, '{"frequency":"onceDaily"}', 1783731600, NULL,
          1783731600),
        ('activity-outcome-v60', 'manual', 'batch-v60',
          'protocol_target_outcomes', 'outcome-v60', NULL, '{}', 1783731600,
          NULL, 1783731600),
        ('activity-dose-v60', 'manual', 'batch-dose-v60', 'doses', 'dose-v60',
          NULL, '{}', 1783731600, 1783731601, 1783731600);
      INSERT INTO deferred_sync_changes (
        entity_table, entity_id, missing_entity_table, missing_entity_id,
        change_json, updated_at, device_id, deferred_at
      ) VALUES
        ('schedules', 'schedule-remote', 'protocol_compounds', 'member-remote',
          '{}', 1783731600, 'device-b', 1783731600),
        ('doses', 'dose-remote', 'compounds', 'compound-remote', '{}',
          1783731600, 'device-b', 1783731600);
      INSERT INTO quarantined_sync_changes (
        entity_table, entity_id, change_json, failure_kind, quarantined_at
      ) VALUES
        ('protocols', 'protocol-remote', '{}', 'format', 1783731600),
        ('doses', 'dose-broken', '{}', 'format', 1783731600);

      PRAGMA user_version = 60;
    ''');
  } finally {
    database.close();
  }
}
