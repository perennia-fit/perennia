import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  final previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
  });

  test('schema 51 migrates Template Groups identically to a fresh schema',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'prn_template_group_migration_',
    );
    addTearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}/v51.sqlite');
    _createV51Database(file);

    final database = AppDatabase.openFile(file);
    await database.customSelect('SELECT 1').get();
    expect(database.schemaVersion, 57);
    expect(
      (await database
          .customSelect(
            "SELECT name FROM workout_templates WHERE id = 'template-v51'",
          )
          .getSingleOrNull()),
      isNotNull,
    );
    expect(
      await _tableNames(database),
      containsAll(<String>{
        AppDatabase.templateGroupsTable,
        AppDatabase.templateGroupMembersTable,
      }),
    );
    expect(
      await _columnNames(database, AppDatabase.templateGroupsTable),
      containsAll(<String>{
        'workout_template_id',
        'name',
        'color_hex',
        'rounds',
        'position',
        'sync_device_id',
        'sync_previously_synced',
        'updated_at',
        'deleted_at',
      }),
    );
    expect(
      await _columnNames(database, AppDatabase.templateGroupMembersTable),
      containsAll(<String>{
        'group_id',
        'template_exercise_id',
        'position',
        'sync_device_id',
        'sync_previously_synced',
        'updated_at',
        'deleted_at',
      }),
    );
    expect(
      await _indexNames(database, AppDatabase.templateGroupsTable),
      contains('template_groups_template_id_index'),
    );
    expect(
      await _indexNames(database, AppDatabase.templateGroupMembersTable),
      containsAll(<String>{
        'template_group_members_group_id_index',
        'template_group_members_template_exercise_id_index',
        'template_group_members_active_exercise_unique',
      }),
    );
    expect(
      await _foreignKeyTargets(database, AppDatabase.templateGroupsTable),
      contains('workout_template_id->workout_templates.id'),
    );
    expect(
      await _foreignKeyTargets(
        database,
        AppDatabase.templateGroupMembersTable,
      ),
      containsAll(<String>{
        'group_id->template_groups.id',
        'template_exercise_id->template_exercises.id',
      }),
    );
    final groupSql = await database
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'table' "
          "AND name = '${AppDatabase.templateGroupsTable}'",
        )
        .getSingle();
    expect(groupSql.read<String>('sql'), contains('CHECK (rounds >= 1)'));

    final now = DateTime.utc(2026, 7, 11, 10);
    await database.into(database.templateGroups).insert(
          TemplateGroupsCompanion.insert(
            id: 'group-v52',
            workoutTemplateId: 'template-v51',
            name: 'Circuit',
            colorHex: '#4A8FE0',
            rounds: const Value<int>(3),
            position: 0,
            updatedAt: now,
          ),
        );
    await database.into(database.templateGroupMembers).insert(
          TemplateGroupMembersCompanion.insert(
            id: 'member-v52',
            groupId: 'group-v52',
            templateExerciseId: 'entry-v51',
            position: 0,
            updatedAt: now,
          ),
        );
    await expectLater(
      database.into(database.templateGroups).insert(
            TemplateGroupsCompanion.insert(
              id: 'invalid-rounds',
              workoutTemplateId: 'template-v51',
              name: 'Invalid',
              colorHex: '#4A8FE0',
              rounds: const Value<int>(0),
              position: 1,
              updatedAt: now,
            ),
          ),
      throwsA(isA<sqlite.SqliteException>()),
    );
    await expectLater(
      database.into(database.templateGroupMembers).insert(
            TemplateGroupMembersCompanion.insert(
              id: 'duplicate-active-member',
              groupId: 'group-v52',
              templateExerciseId: 'entry-v51',
              position: 1,
              updatedAt: now,
            ),
          ),
      throwsA(isA<sqlite.SqliteException>()),
    );

    final fresh = AppDatabase.inMemory();
    await fresh.customSelect('SELECT 1').get();
    expect(
      await _indexNames(database, AppDatabase.templateGroupsTable),
      await _indexNames(fresh, AppDatabase.templateGroupsTable),
    );
    expect(
      await _indexNames(database, AppDatabase.templateGroupMembersTable),
      await _indexNames(fresh, AppDatabase.templateGroupMembersTable),
    );
    await fresh.close();
    await database.close();

    final reopened = AppDatabase.openFile(file);
    addTearDown(reopened.close);
    expect(await reopened.select(reopened.templateGroups).get(), hasLength(1));
    expect(
      await reopened.select(reopened.templateGroupMembers).get(),
      hasLength(1),
    );
  });

  test('schema 56 adds the pending Activity Log sync index', () async {
    final directory = await Directory.systemTemp.createTemp(
      'prn_activity_log_index_migration_',
    );
    addTearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}/v56.sqlite');
    final legacy = sqlite.sqlite3.open(file.path);
    try {
      legacy.execute('''
        CREATE TABLE activity_log (
          id TEXT NOT NULL PRIMARY KEY,
          entity_table TEXT NOT NULL,
          deleted_at INTEGER,
          sync_acknowledged_at INTEGER,
          after_image TEXT
        );
        PRAGMA user_version = 56;
      ''');
    } finally {
      legacy.close();
    }

    final database = AppDatabase.openFile(file);
    addTearDown(database.close);
    await database.customSelect('SELECT 1').get();

    expect(database.schemaVersion, 57);
    expect(
      await _indexNames(database, AppDatabase.activityLogTable),
      contains('activity_log_pending_sync_index'),
    );
  });
}

Future<Set<String>> _tableNames(AppDatabase database) async {
  final rows = await database
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      )
      .get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

Future<Set<String>> _columnNames(
  AppDatabase database,
  String tableName,
) async {
  final rows =
      await database.customSelect('PRAGMA table_info($tableName)').get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

Future<Set<String>> _indexNames(
  AppDatabase database,
  String tableName,
) async {
  final rows =
      await database.customSelect('PRAGMA index_list($tableName)').get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

Future<Set<String>> _foreignKeyTargets(
  AppDatabase database,
  String tableName,
) async {
  final rows =
      await database.customSelect('PRAGMA foreign_key_list($tableName)').get();
  return rows
      .map(
        (row) => '${row.read<String>('from')}->'
            '${row.read<String>('table')}.${row.read<String>('to')}',
      )
      .toSet();
}

void _createV51Database(File file) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    database.execute('''
      PRAGMA foreign_keys = OFF;
      CREATE TABLE workout_templates (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        notes TEXT,
        sync_device_id TEXT,
        sync_previously_synced INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      );
      CREATE TABLE workout_sessions (
        id TEXT NOT NULL PRIMARY KEY,
        started_at INTEGER NOT NULL,
        timezone TEXT NOT NULL,
        local_date TEXT NOT NULL,
        ended_at INTEGER,
        comment TEXT,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      );
      CREATE TABLE exercises (
        id TEXT NOT NULL PRIMARY KEY
      );
      CREATE TABLE template_exercises (
        id TEXT NOT NULL PRIMARY KEY,
        workout_template_id TEXT NOT NULL REFERENCES workout_templates(id),
        exercise_id TEXT NOT NULL REFERENCES exercises(id),
        position INTEGER NOT NULL,
        note TEXT,
        sync_device_id TEXT,
        sync_previously_synced INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      );
      CREATE TABLE template_links (
        id TEXT NOT NULL PRIMARY KEY,
        workout_id TEXT NOT NULL REFERENCES workout_sessions(id),
        workout_template_id TEXT NOT NULL REFERENCES workout_templates(id),
        routine_id TEXT,
        slot INTEGER,
        sync_device_id TEXT,
        sync_previously_synced INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      );
      CREATE UNIQUE INDEX template_links_workout_id_unique
        ON template_links (workout_id);
      CREATE INDEX template_links_template_id_index
        ON template_links (workout_template_id);
      CREATE INDEX template_links_routine_id_index
        ON template_links (routine_id);
      INSERT INTO workout_templates (
        id, name, updated_at
      ) VALUES ('template-v51', 'Existing template', 1783731600);
      INSERT INTO exercises (id) VALUES ('exercise-v51');
      INSERT INTO template_exercises (
        id, workout_template_id, exercise_id, position, updated_at
      ) VALUES (
        'entry-v51', 'template-v51', 'exercise-v51', 0, 1783731600
      );
      PRAGMA user_version = 51;
    ''');
  } finally {
    database.close();
  }
}
