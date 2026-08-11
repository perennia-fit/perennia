import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm, Value, driftRuntimeOptions;
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

  test('schema 52 reaches the v55 Routine model without duplicate adds',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'prn_routine_plan_migration_',
    );
    addTearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}/v52.sqlite');
    _createV52Database(file);

    final database = AppDatabase.openFile(file);
    addTearDown(database.close);
    await database.customSelect('SELECT 1').get();
    final freshDatabase = AppDatabase.inMemory();
    addTearDown(freshDatabase.close);
    await freshDatabase.customSelect('SELECT 1').get();

    expect(database.schemaVersion, 57);
    expect(
      await _tableNames(database),
      containsAll(<String>{
        AppDatabase.planRoutinesTable,
        AppDatabase.routineEntriesTable,
      }),
    );
    expect(await _tableNames(database), isNot(contains('routines')));
    expect(
      await _columnNames(database, AppDatabase.planRoutinesTable),
      <String>{
        'id',
        'name',
        'notes',
        'cadence_kind',
        'cadence_window',
        'sync_device_id',
        'sync_previously_synced',
        'updated_at',
        'deleted_at',
      },
    );
    expect(
      await _columnNames(database, AppDatabase.routineEntriesTable),
      <String>{
        'id',
        'routine_id',
        'workout_template_id',
        'position',
        'slot',
        'sync_device_id',
        'sync_previously_synced',
        'updated_at',
        'deleted_at',
      },
    );
    expect(
      await _indexNames(database, AppDatabase.planRoutinesTable),
      contains('plan_routines_name_index'),
    );
    expect(
      await _indexNames(database, AppDatabase.routineEntriesTable),
      containsAll(<String>{
        'routine_entries_routine_id_index',
        'routine_entries_template_id_index',
      }),
    );
    expect(
      await _foreignKeys(database, AppDatabase.routineEntriesTable),
      containsAll(<String>{
        'routine_id->plan_routines.id:NO ACTION',
        'workout_template_id->workout_templates.id:NO ACTION',
      }),
    );
    expect(
      await _foreignKeys(database, AppDatabase.templateLinksTable),
      contains('routine_id->plan_routines.id:NO ACTION'),
    );
    for (final tableName in <String>{
      AppDatabase.planRoutinesTable,
      AppDatabase.routineEntriesTable,
      AppDatabase.templateLinksTable,
    }) {
      expect(
        await _columnDefinitions(database, tableName),
        await _columnDefinitions(freshDatabase, tableName),
        reason: '$tableName column definitions differ from a fresh v55 DB',
      );
      expect(
        await _indexNames(database, tableName),
        await _indexNames(freshDatabase, tableName),
        reason: '$tableName indexes differ from a fresh v55 DB',
      );
      expect(
        await _foreignKeys(database, tableName),
        await _foreignKeys(freshDatabase, tableName),
        reason: '$tableName foreign keys differ from a fresh v55 DB',
      );
    }

    final preservedLink = await database.select(database.templateLinks).get();
    expect(preservedLink, hasLength(1));
    expect(preservedLink.single.id, 'link-v52');
    expect(preservedLink.single.routineId, isNull);
    expect(preservedLink.single.slot, 2);

    final now = DateTime.utc(2026, 7, 11, 12);
    await database.into(database.planRoutines).insert(
          PlanRoutinesCompanion.insert(
            id: 'plan-routine-v53',
            name: 'Hybrid week',
            updatedAt: now,
          ),
        );
    await database.into(database.routineEntries).insert(
          RoutineEntriesCompanion.insert(
            id: 'entry-v53-a',
            routineId: 'plan-routine-v53',
            workoutTemplateId: 'template-v52',
            position: 0,
            updatedAt: now,
          ),
        );
    // Duplicate references are deliberate: a later Cadence can place the same
    // Workout Template on more than one slot.
    await database.into(database.routineEntries).insert(
          RoutineEntriesCompanion.insert(
            id: 'entry-v53-b',
            routineId: 'plan-routine-v53',
            workoutTemplateId: 'template-v52',
            position: 1,
            updatedAt: now,
          ),
        );
    await database.into(database.templateLinks).insert(
          TemplateLinksCompanion.insert(
            id: 'linked-to-routine-v53',
            workoutId: 'workout-v52-b',
            workoutTemplateId: 'template-v52',
            routineId: const Value<String?>('plan-routine-v53'),
            updatedAt: now,
          ),
        );

    await expectLater(
      (database.delete(database.planRoutines)
            ..where((row) => row.id.equals('plan-routine-v53')))
          .go(),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(await database.select(database.routineEntries).get(), hasLength(2));
    expect(
      await database.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );
  });

  test('schema 53 adds nullable Cadence and slot fields in place', () async {
    final directory = await Directory.systemTemp.createTemp(
      'prn_routine_cadence_migration_',
    );
    addTearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}/v53.sqlite');
    _createV53Database(file);

    final database = AppDatabase.openFile(file);
    addTearDown(database.close);
    await database.customSelect('SELECT 1').get();

    expect(database.schemaVersion, 57);
    final routine = (await database.select(database.planRoutines).get()).single;
    expect(routine.id, 'routine-v53');
    expect(routine.cadenceKind, isNull);
    expect(routine.cadenceWindow, isNull);
    final entries = await (database.select(database.routineEntries)
          ..orderBy([(row) => OrderingTerm.asc(row.position)]))
        .get();
    expect(entries, hasLength(2));
    expect(entries.map((entry) => entry.slot), everyElement(isNull));
    expect(
      await _columnNames(database, AppDatabase.planRoutinesTable),
      isNot(contains(anyOf('cursor', 'current_slot', 'rotation_position'))),
    );
    expect(
      await _columnNames(database, AppDatabase.routineEntriesTable),
      isNot(contains(anyOf('cursor', 'current_slot', 'rotation_position'))),
    );
    expect(
      await database.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );
  });

  test('schema 54 drops the legacy tree and its interval source atomically',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'prn_routine_greenfield_cutover_',
    );
    addTearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}/v54.sqlite');
    _createV54LegacyRoutineDatabase(file);

    final database = AppDatabase.openFile(file);
    addTearDown(database.close);
    await database.customSelect('SELECT 1').get();
    final fresh = AppDatabase.inMemory();
    addTearDown(fresh.close);
    await fresh.customSelect('SELECT 1').get();

    expect(database.schemaVersion, 57);
    final tableNames = await _tableNames(database);
    for (final retiredTable in <String>{
      'routines',
      'routine_days',
      'routine_exercises',
      'predefined_sets',
      'routine_exercise_groups',
      'routine_exercise_group_members',
    }) {
      expect(tableNames, isNot(contains(retiredTable)), reason: retiredTable);
    }

    expect(
      await _columnNames(database, AppDatabase.intervalTimersTable),
      await _columnNames(fresh, AppDatabase.intervalTimersTable),
    );
    expect(
      await _columnNames(database, AppDatabase.intervalTimersTable),
      isNot(contains('routine_day_id')),
    );
    expect(
      await _indexNames(database, AppDatabase.intervalTimersTable),
      await _indexNames(fresh, AppDatabase.intervalTimersTable),
    );
    expect(
      await _foreignKeys(database, AppDatabase.intervalTimersTable),
      await _foreignKeys(fresh, AppDatabase.intervalTimersTable),
    );
    expect(await database.select(database.intervalTimers).get(), isEmpty);

    final activityRows = await database.select(database.activityLog).get();
    expect(activityRows, hasLength(1));
    expect(activityRows.single.id, 'current-set-activity-v54');
    expect(activityRows.single.entityTable, AppDatabase.loggedSetsTable);

    for (final preserved in <String>[
      "SELECT id FROM workout_sessions WHERE id = 'workout-v54'",
      "SELECT id FROM logged_sets WHERE id = 'set-v54'",
      "SELECT id FROM workout_templates WHERE id = 'template-v54'",
      "SELECT id FROM template_exercises WHERE id = 'template-exercise-v54'",
      "SELECT id FROM prescriptions WHERE id = 'prescription-v54'",
      "SELECT id FROM plan_routines WHERE id = 'plan-routine-v54'",
      "SELECT id FROM routine_entries WHERE id = 'entry-v54'",
      "SELECT id FROM template_links WHERE id = 'link-v54'",
    ]) {
      expect(
        await database.customSelect(preserved).getSingleOrNull(),
        isNotNull,
        reason: preserved,
      );
    }
    expect(
      await database.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );
    final staleSchemaReferences = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE sql LIKE '%routine_days%'",
        )
        .get();
    expect(staleSchemaReferences, isEmpty);
  });

  test('reopening schema 55 preserves Cadence and slot layout', () async {
    final directory = await Directory.systemTemp.createTemp(
      'prn_routine_plan_migration_reopen_',
    );
    addTearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}/v52.sqlite');
    _createV52Database(file);

    final first = AppDatabase.openFile(file);
    await first.customSelect('SELECT 1').get();
    final now = DateTime.utc(2026, 7, 11, 12);
    await first.into(first.planRoutines).insert(
          PlanRoutinesCompanion.insert(
            id: 'reopen-routine',
            name: 'Persisted collection',
            cadenceKind: const Value<String?>('weekly'),
            updatedAt: now,
          ),
        );
    for (var index = 0; index < 2; index += 1) {
      await first.into(first.routineEntries).insert(
            RoutineEntriesCompanion.insert(
              id: 'reopen-entry-$index',
              routineId: 'reopen-routine',
              workoutTemplateId: 'template-v52',
              position: index,
              slot: Value<int?>(index + 1),
              updatedAt: now,
            ),
          );
    }
    await first.into(first.templateLinks).insert(
          TemplateLinksCompanion.insert(
            id: 'reopen-link',
            workoutId: 'workout-v52-b',
            workoutTemplateId: 'template-v52',
            routineId: const Value<String?>('reopen-routine'),
            updatedAt: now,
          ),
        );
    await first.close();

    final second = AppDatabase.openFile(file);
    addTearDown(second.close);
    expect(second.schemaVersion, 57);
    final routines = await second.select(second.planRoutines).get();
    expect(routines, hasLength(1));
    expect(routines.single.cadenceKind, 'weekly');
    expect(routines.single.cadenceWindow, isNull);
    final entries = await (second.select(second.routineEntries)
          ..orderBy([(row) => OrderingTerm.asc(row.position)]))
        .get();
    expect(entries.map((entry) => entry.id), <String>[
      'reopen-entry-0',
      'reopen-entry-1',
    ]);
    expect(entries.map((entry) => entry.slot), <int?>[1, 2]);
    final links = await second.select(second.templateLinks).get();
    expect(links, hasLength(2));
    expect(
      links.singleWhere((link) => link.id == 'reopen-link').routineId,
      'reopen-routine',
    );
    await expectLater(
      (second.delete(second.planRoutines)
            ..where((row) => row.id.equals('reopen-routine')))
          .go(),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(
        await second.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}

Future<Set<String>> _tableNames(AppDatabase database) async {
  final rows = await database
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
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

Future<List<String>> _columnDefinitions(
  AppDatabase database,
  String tableName,
) async {
  final rows =
      await database.customSelect('PRAGMA table_info($tableName)').get();
  return rows
      .map(
        (row) => <Object?>[
          row.read<int>('cid'),
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

void _createV52Database(File file) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    database.execute('''
      PRAGMA foreign_keys = OFF;

      CREATE TABLE routines (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        notes TEXT NULL,
        position INTEGER NOT NULL,
        sync_device_id TEXT NULL,
        sync_previously_synced INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE TABLE workout_templates (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        notes TEXT NULL,
        sync_device_id TEXT NULL,
        sync_previously_synced INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE TABLE workout_sessions (
        id TEXT NOT NULL PRIMARY KEY,
        started_at INTEGER NOT NULL,
        timezone TEXT NOT NULL,
        local_date TEXT NOT NULL,
        ended_at INTEGER NULL,
        comment TEXT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE TABLE template_links (
        id TEXT NOT NULL PRIMARY KEY,
        workout_id TEXT NOT NULL REFERENCES workout_sessions (id),
        workout_template_id TEXT NOT NULL REFERENCES workout_templates (id),
        routine_id TEXT NULL,
        slot INTEGER NULL,
        sync_device_id TEXT NULL,
        sync_previously_synced INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );
      CREATE UNIQUE INDEX template_links_workout_id_unique
        ON template_links (workout_id);
      CREATE INDEX template_links_template_id_index
        ON template_links (workout_template_id);
      CREATE INDEX template_links_routine_id_index
        ON template_links (routine_id);

      INSERT INTO routines (
        id, name, position, updated_at
      ) VALUES ('legacy-routine-v52', 'Legacy routine', 0, 1783756800);
      INSERT INTO workout_templates (
        id, name, updated_at
      ) VALUES ('template-v52', 'Existing template', 1783756800);
      INSERT INTO workout_sessions (
        id, started_at, timezone, local_date, updated_at
      ) VALUES
        ('workout-v52-a', 1783753200, 'UTC', '2026-07-11', 1783756800),
        ('workout-v52-b', 1783756800, 'UTC', '2026-07-11', 1783756800);
      INSERT INTO template_links (
        id, workout_id, workout_template_id, routine_id, slot, updated_at
      ) VALUES (
        'link-v52', 'workout-v52-a', 'template-v52',
        'opaque-routine-v52', 2, 1783756800
      );

      PRAGMA user_version = 52;
    ''');
  } finally {
    database.close();
  }
}

void _createV54LegacyRoutineDatabase(File file) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    database.execute('''
      PRAGMA foreign_keys = OFF;

      CREATE TABLE exercises (
        id TEXT NOT NULL PRIMARY KEY
      );

      CREATE TABLE workout_sessions (
        id TEXT NOT NULL PRIMARY KEY,
        started_at INTEGER NOT NULL,
        timezone TEXT NOT NULL,
        local_date TEXT NOT NULL,
        ended_at INTEGER NULL,
        comment TEXT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE TABLE logged_sets (
        id TEXT NOT NULL PRIMARY KEY,
        workout_id TEXT NOT NULL REFERENCES workout_sessions (id),
        exercise_id TEXT NOT NULL REFERENCES exercises (id),
        position INTEGER NOT NULL,
        load_entered TEXT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE TABLE workout_templates (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        notes TEXT NULL,
        sync_device_id TEXT NULL,
        sync_previously_synced INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE TABLE template_exercises (
        id TEXT NOT NULL PRIMARY KEY,
        workout_template_id TEXT NOT NULL REFERENCES workout_templates (id),
        exercise_id TEXT NOT NULL REFERENCES exercises (id),
        position INTEGER NOT NULL,
        note TEXT NULL,
        sync_device_id TEXT NULL,
        sync_previously_synced INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE TABLE prescriptions (
        id TEXT NOT NULL PRIMARY KEY,
        template_exercise_id TEXT NOT NULL REFERENCES template_exercises (id),
        mode TEXT NOT NULL DEFAULT 'fixed',
        position INTEGER NOT NULL,
        repeat INTEGER NOT NULL DEFAULT 1,
        rest_after INTEGER NULL,
        load_value REAL NULL,
        load_unit TEXT NULL,
        load_entered TEXT NULL,
        reps_value REAL NULL,
        reps_unit TEXT NULL,
        reps_entered TEXT NULL,
        duration_value REAL NULL,
        duration_unit TEXT NULL,
        duration_entered TEXT NULL,
        distance_value REAL NULL,
        distance_unit TEXT NULL,
        distance_entered TEXT NULL,
        sync_device_id TEXT NULL,
        sync_previously_synced INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE TABLE plan_routines (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        notes TEXT NULL,
        cadence_kind TEXT NULL,
        cadence_window INTEGER NULL,
        sync_device_id TEXT NULL,
        sync_previously_synced INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE TABLE routine_entries (
        id TEXT NOT NULL PRIMARY KEY,
        routine_id TEXT NOT NULL REFERENCES plan_routines (id),
        workout_template_id TEXT NOT NULL REFERENCES workout_templates (id),
        position INTEGER NOT NULL,
        slot INTEGER NULL,
        sync_device_id TEXT NULL,
        sync_previously_synced INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE TABLE template_links (
        id TEXT NOT NULL PRIMARY KEY,
        workout_id TEXT NOT NULL REFERENCES workout_sessions (id),
        workout_template_id TEXT NOT NULL REFERENCES workout_templates (id),
        routine_id TEXT NULL REFERENCES plan_routines (id),
        slot INTEGER NULL,
        sync_device_id TEXT NULL,
        sync_previously_synced INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE TABLE routines (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        notes TEXT NULL,
        position INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );
      CREATE TABLE routine_days (
        id TEXT NOT NULL PRIMARY KEY,
        routine_id TEXT NOT NULL REFERENCES routines (id),
        name TEXT NOT NULL,
        position INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );
      CREATE TABLE routine_exercises (
        id TEXT NOT NULL PRIMARY KEY,
        routine_day_id TEXT NOT NULL REFERENCES routine_days (id),
        exercise_id TEXT NOT NULL REFERENCES exercises (id),
        position INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );
      CREATE TABLE predefined_sets (
        id TEXT NOT NULL PRIMARY KEY,
        routine_exercise_id TEXT NOT NULL REFERENCES routine_exercises (id),
        mode TEXT NOT NULL DEFAULT 'fixed',
        position INTEGER NOT NULL,
        repeat INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );
      CREATE TABLE routine_exercise_groups (
        id TEXT NOT NULL PRIMARY KEY,
        routine_day_id TEXT NOT NULL REFERENCES routine_days (id),
        name TEXT NOT NULL,
        color_hex TEXT NOT NULL,
        rounds INTEGER NOT NULL DEFAULT 1,
        position INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );
      CREATE TABLE routine_exercise_group_members (
        id TEXT NOT NULL PRIMARY KEY,
        group_id TEXT NOT NULL REFERENCES routine_exercise_groups (id),
        routine_exercise_id TEXT NOT NULL REFERENCES routine_exercises (id),
        position INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE TABLE interval_timers (
        id TEXT NOT NULL PRIMARY KEY,
        workout_id TEXT NOT NULL REFERENCES workout_sessions (id),
        routine_day_id TEXT NOT NULL REFERENCES routine_days (id),
        started_at INTEGER NOT NULL,
        phase_started_at INTEGER NOT NULL,
        deadline_at INTEGER NOT NULL,
        current_step_index INTEGER NOT NULL DEFAULT 0,
        completed_set_count INTEGER NOT NULL DEFAULT 0,
        alert_volume REAL NOT NULL DEFAULT 1.0,
        phase TEXT NOT NULL DEFAULT 'work',
        status TEXT NOT NULL DEFAULT 'running',
        prepare_alert_fired_at INTEGER NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );
      CREATE INDEX interval_timers_workout_id_index
        ON interval_timers (workout_id);

      CREATE TABLE activity_log (
        id TEXT NOT NULL PRIMARY KEY,
        actor TEXT NOT NULL,
        batch_id TEXT NOT NULL,
        entity_table TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        before_image TEXT NULL,
        after_image TEXT NULL,
        occurred_at INTEGER NOT NULL,
        sync_acknowledged_at INTEGER NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );
      CREATE INDEX activity_log_batch_id_index ON activity_log (batch_id);

      INSERT INTO exercises (id) VALUES ('exercise-v54');
      INSERT INTO workout_sessions (
        id, started_at, timezone, local_date, updated_at
      ) VALUES (
        'workout-v54', 1783753200, 'UTC', '2026-07-11', 1783753200
      );
      INSERT INTO logged_sets (
        id, workout_id, exercise_id, position, load_entered, updated_at
      ) VALUES (
        'set-v54', 'workout-v54', 'exercise-v54', 0, '80', 1783753200
      );
      INSERT INTO workout_templates (id, name, updated_at)
        VALUES ('template-v54', 'Current template', 1783753200);
      INSERT INTO template_exercises (
        id, workout_template_id, exercise_id, position, updated_at
      ) VALUES (
        'template-exercise-v54', 'template-v54', 'exercise-v54', 0, 1783753200
      );
      INSERT INTO prescriptions (
        id, template_exercise_id, position, load_entered, updated_at
      ) VALUES (
        'prescription-v54', 'template-exercise-v54', 0, '80', 1783753200
      );
      INSERT INTO plan_routines (id, name, cadence_kind, updated_at)
        VALUES ('plan-routine-v54', 'Current routine', 'weekly', 1783753200);
      INSERT INTO routine_entries (
        id, routine_id, workout_template_id, position, slot, updated_at
      ) VALUES (
        'entry-v54', 'plan-routine-v54', 'template-v54', 0, 2, 1783753200
      );
      INSERT INTO template_links (
        id, workout_id, workout_template_id, routine_id, slot, updated_at
      ) VALUES (
        'link-v54', 'workout-v54', 'template-v54',
        'plan-routine-v54', 2, 1783753200
      );

      INSERT INTO routines (id, name, position, updated_at)
        VALUES ('legacy-routine-v54', 'Legacy', 0, 1783753200);
      INSERT INTO routine_days (id, routine_id, name, position, updated_at)
        VALUES (
          'legacy-day-v54', 'legacy-routine-v54', 'Day', 0, 1783753200
        );
      INSERT INTO routine_exercises (
        id, routine_day_id, exercise_id, position, updated_at
      ) VALUES (
        'legacy-exercise-v54', 'legacy-day-v54', 'exercise-v54', 0, 1783753200
      );
      INSERT INTO predefined_sets (
        id, routine_exercise_id, position, updated_at
      ) VALUES (
        'legacy-set-v54', 'legacy-exercise-v54', 0, 1783753200
      );
      INSERT INTO routine_exercise_groups (
        id, routine_day_id, name, color_hex, position, updated_at
      ) VALUES (
        'legacy-group-v54', 'legacy-day-v54', 'Circuit', '#3366FF',
        0, 1783753200
      );
      INSERT INTO routine_exercise_group_members (
        id, group_id, routine_exercise_id, position, updated_at
      ) VALUES (
        'legacy-member-v54', 'legacy-group-v54',
        'legacy-exercise-v54', 0, 1783753200
      );
      INSERT INTO interval_timers (
        id, workout_id, routine_day_id, started_at, phase_started_at,
        deadline_at, updated_at
      ) VALUES (
        'legacy-timer-v54', 'workout-v54', 'legacy-day-v54',
        1783753200, 1783753200, 1783753230, 1783753200
      );

      INSERT INTO activity_log (
        id, actor, batch_id, entity_table, entity_id, occurred_at, updated_at
      ) VALUES
        ('legacy-routine-activity-v54', 'app', 'legacy-batch-v54',
          'routines', 'legacy-routine-v54', 1783753200, 1783753200),
        ('legacy-day-activity-v54', 'app', 'legacy-batch-v54',
          'routine_days', 'legacy-day-v54', 1783753200, 1783753200),
        ('legacy-exercise-activity-v54', 'app', 'legacy-batch-v54',
          'routine_exercises', 'legacy-exercise-v54', 1783753200, 1783753200),
        ('legacy-set-activity-v54', 'app', 'legacy-batch-v54',
          'predefined_sets', 'legacy-set-v54', 1783753200, 1783753200),
        ('legacy-group-activity-v54', 'app', 'legacy-batch-v54',
          'routine_exercise_groups', 'legacy-group-v54', 1783753200,
          1783753200),
        ('legacy-member-activity-v54', 'app', 'legacy-batch-v54',
          'routine_exercise_group_members', 'legacy-member-v54', 1783753200,
          1783753200),
        ('current-set-activity-v54', 'app', 'current-batch-v54',
          'logged_sets', 'set-v54', 1783753200, 1783753200);

      PRAGMA user_version = 54;
    ''');
  } finally {
    database.close();
  }
}

void _createV53Database(File file) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    database.execute('''
      PRAGMA foreign_keys = OFF;

      CREATE TABLE workout_templates (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        notes TEXT NULL,
        sync_device_id TEXT NULL,
        sync_previously_synced INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE TABLE plan_routines (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        notes TEXT NULL,
        sync_device_id TEXT NULL,
        sync_previously_synced INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );
      CREATE INDEX plan_routines_name_index ON plan_routines (name);

      CREATE TABLE routine_entries (
        id TEXT NOT NULL PRIMARY KEY,
        routine_id TEXT NOT NULL REFERENCES plan_routines (id),
        workout_template_id TEXT NOT NULL REFERENCES workout_templates (id),
        position INTEGER NOT NULL,
        sync_device_id TEXT NULL,
        sync_previously_synced INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );
      CREATE INDEX routine_entries_routine_id_index
        ON routine_entries (routine_id);
      CREATE INDEX routine_entries_template_id_index
        ON routine_entries (workout_template_id);

      INSERT INTO workout_templates (id, name, updated_at)
      VALUES ('template-v53', 'Template', 1783756800);
      INSERT INTO plan_routines (id, name, updated_at)
      VALUES ('routine-v53', 'Collection', 1783756800);
      INSERT INTO routine_entries (
        id, routine_id, workout_template_id, position, updated_at
      ) VALUES
        ('entry-v53-a', 'routine-v53', 'template-v53', 0, 1783756800),
        ('entry-v53-b', 'routine-v53', 'template-v53', 1, 1783756800);

      PRAGMA user_version = 53;
    ''');
  } finally {
    database.close();
  }
}
