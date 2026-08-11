import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  final previousWarningSetting =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarningSetting;
  });

  test('representative schema 50 data survives the plan-table migration',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'prn_workout_template_migration_',
    );
    addTearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}/v50.sqlite');
    _createV50Database(file);

    final database = AppDatabase.openFile(file);
    addTearDown(database.close);
    await database.customSelect('SELECT 1').get();

    expect(database.schemaVersion, 57);
    final existingExercise =
        await database.select(database.exercises).getSingle();
    final existingWorkout =
        await database.select(database.workoutSessions).getSingle();
    final existingSet = await database.select(database.loggedSets).getSingle();
    expect(existingExercise.id, 'exercise-v50');
    expect(existingExercise.name, 'Existing Bench Press');
    expect(existingExercise.dimensionIds, '["load","reps"]');
    expect(existingWorkout.id, 'workout-v50');
    expect(existingWorkout.comment, 'Existing workout survives');
    expect(existingSet.id, 'set-v50');
    expect(existingSet.loadEntered, '80');
    expect(existingSet.repsEntered, '8');
    expect(
      await _tableNames(database),
      containsAll(<String>{
        AppDatabase.workoutTemplatesTable,
        AppDatabase.templateExercisesTable,
        AppDatabase.prescriptionsTable,
        AppDatabase.templateLinksTable,
      }),
    );
    expect(
      await _columnNames(database, AppDatabase.workoutTemplatesTable),
      containsAll(<String>{
        'id',
        'name',
        'notes',
        'sync_device_id',
        'sync_previously_synced',
        'updated_at',
        'deleted_at',
      }),
    );
    expect(
      await _columnNames(database, AppDatabase.templateExercisesTable),
      containsAll(<String>{
        'workout_template_id',
        'exercise_id',
        'position',
        'note',
      }),
    );
    expect(
      await _columnNames(database, AppDatabase.prescriptionsTable),
      containsAll(<String>{
        'template_exercise_id',
        'mode',
        'repeat',
        'rest_after',
        'load_entered',
        'reps_entered',
        'duration_entered',
        'distance_entered',
      }),
    );
    expect(
      await _columnNames(database, AppDatabase.templateLinksTable),
      containsAll(<String>{
        'workout_id',
        'workout_template_id',
        'routine_id',
        'slot',
      }),
    );
    expect(
      await _indexNames(database, AppDatabase.workoutTemplatesTable),
      contains('workout_templates_name_index'),
    );
    expect(
      await _indexNames(database, AppDatabase.templateExercisesTable),
      containsAll(<String>{
        'template_exercises_template_id_index',
        'template_exercises_exercise_id_index',
        'template_exercises_active_exercise_unique',
      }),
    );
    expect(
      await _indexNames(database, AppDatabase.prescriptionsTable),
      contains('prescriptions_template_exercise_id_index'),
    );
    expect(
      await _indexNames(database, AppDatabase.templateLinksTable),
      containsAll(<String>{
        'template_links_workout_id_unique',
        'template_links_template_id_index',
        'template_links_routine_id_index',
      }),
    );
    expect(
      await _uniqueIndexNames(database, AppDatabase.templateLinksTable),
      contains('template_links_workout_id_unique'),
    );

    expect(
      await _foreignKeyTargets(database, AppDatabase.templateExercisesTable),
      containsAll(<String>{
        'workout_template_id->workout_templates.id',
        'exercise_id->exercises.id',
      }),
    );
    expect(
      await _foreignKeyTargets(database, AppDatabase.prescriptionsTable),
      contains('template_exercise_id->template_exercises.id'),
    );
    expect(
      await _foreignKeyTargets(database, AppDatabase.templateLinksTable),
      containsAll(<String>{
        'workout_id->workout_sessions.id',
        'workout_template_id->workout_templates.id',
      }),
    );

    final timestamp = DateTime.utc(2026, 7, 11, 9);
    await database.into(database.workoutTemplates).insert(
          WorkoutTemplatesCompanion.insert(
            id: 'template-after-migration',
            name: 'Migrated Push',
            updatedAt: timestamp,
          ),
        );
    await database.into(database.templateExercises).insert(
          TemplateExercisesCompanion.insert(
            id: 'template-exercise-after-migration',
            workoutTemplateId: 'template-after-migration',
            exerciseId: 'exercise-v50',
            position: 0,
            updatedAt: timestamp,
          ),
        );
    await database.into(database.prescriptions).insert(
          PrescriptionsCompanion.insert(
            id: 'prescription-after-migration',
            templateExerciseId: 'template-exercise-after-migration',
            position: 0,
            loadEntered: const Value<String?>('80'),
            loadValue: const Value<double?>(80),
            loadUnit: const Value<String?>('kilogram'),
            repsEntered: const Value<String?>('8'),
            repsValue: const Value<double?>(8),
            repsUnit: const Value<String?>('repetition'),
            updatedAt: timestamp,
          ),
        );
    await database.into(database.templateLinks).insert(
          TemplateLinksCompanion.insert(
            id: 'template-link-after-migration',
            workoutId: 'workout-v50',
            workoutTemplateId: 'template-after-migration',
            updatedAt: timestamp,
          ),
        );
    expect(
      await database.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );

    await expectLater(
      database.into(database.templateExercises).insert(
            TemplateExercisesCompanion.insert(
              id: 'invalid-template-exercise',
              workoutTemplateId: 'missing-template',
              exerciseId: 'exercise-v50',
              position: 1,
              updatedAt: timestamp,
            ),
          ),
      throwsA(isA<sqlite.SqliteException>()),
    );
    await expectLater(
      database.into(database.templateExercises).insert(
            TemplateExercisesCompanion.insert(
              id: 'duplicate-active-template-exercise',
              workoutTemplateId: 'template-after-migration',
              exerciseId: 'exercise-v50',
              position: 1,
              updatedAt: timestamp,
            ),
          ),
      throwsA(isA<sqlite.SqliteException>()),
    );
    await database.into(database.templateExercises).insert(
          TemplateExercisesCompanion.insert(
            id: 'archived-duplicate-template-exercise',
            workoutTemplateId: 'template-after-migration',
            exerciseId: 'exercise-v50',
            position: 1,
            updatedAt: timestamp,
            deletedAt: Value<DateTime?>(timestamp),
          ),
        );
    await expectLater(
      database.into(database.templateLinks).insert(
            TemplateLinksCompanion.insert(
              id: 'duplicate-workout-link',
              workoutId: 'workout-v50',
              workoutTemplateId: 'template-after-migration',
              updatedAt: timestamp,
            ),
          ),
      throwsA(isA<sqlite.SqliteException>()),
    );
  });

  test('reopening the migrated schema is a no-op', () async {
    final directory = await Directory.systemTemp.createTemp(
      'prn_workout_template_migration_idempotent_',
    );
    addTearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}/v50.sqlite');
    _createV50Database(file);

    final first = AppDatabase.openFile(file);
    await first.customSelect('SELECT 1').get();
    await first.close();

    final second = AppDatabase.openFile(file);
    addTearDown(second.close);
    expect(
      await _tableNames(second),
      contains(AppDatabase.workoutTemplatesTable),
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

Future<Set<String>> _uniqueIndexNames(
  AppDatabase database,
  String tableName,
) async {
  final rows =
      await database.customSelect('PRAGMA index_list($tableName)').get();
  return rows
      .where((row) => row.read<int>('unique') == 1)
      .map((row) => row.read<String>('name'))
      .toSet();
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

void _createV50Database(File file) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    database.execute('''
      PRAGMA foreign_keys = OFF;

      CREATE TABLE exercise_categories (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        color_hex TEXT NOT NULL,
        sync_device_id TEXT NULL,
        sync_previously_synced INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE TABLE exercises (
        id TEXT NOT NULL PRIMARY KEY,
        library_origin TEXT NOT NULL DEFAULT 'user',
        name TEXT NOT NULL,
        dimension_ids TEXT NOT NULL,
        default_load_unit TEXT NOT NULL DEFAULT 'kilogram',
        load_mode TEXT NOT NULL DEFAULT 'added',
        record_profile TEXT NOT NULL DEFAULT 'repMax',
        is_favorite INTEGER NOT NULL DEFAULT 0,
        is_unilateral INTEGER NOT NULL DEFAULT 0,
        uses_rpe INTEGER NOT NULL DEFAULT 0,
        category_id TEXT NULL REFERENCES exercise_categories (id),
        equipment_ids TEXT NOT NULL DEFAULT '[]',
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
        local_date TEXT NOT NULL DEFAULT '1970-01-01',
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
        planned_rest_after INTEGER NULL,
        performed_at INTEGER NULL,
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
        comment TEXT NULL,
        side TEXT NULL,
        rpe REAL NULL,
        is_completed INTEGER NOT NULL DEFAULT 0,
        sync_device_id TEXT NULL,
        sync_previously_synced INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE INDEX logged_sets_workout_id_index
        ON logged_sets (workout_id);
      CREATE INDEX logged_sets_exercise_id_index
        ON logged_sets (exercise_id);

      PRAGMA user_version = 50;
    ''');

    final updatedAt = _seconds(DateTime.utc(2026, 7, 10, 8));
    database.execute(
      '''
        INSERT INTO exercises (
          id, name, dimension_ids, notes, sync_previously_synced, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?);
      ''',
      <Object?>[
        'exercise-v50',
        'Existing Bench Press',
        '["load","reps"]',
        'Existing cue',
        1,
        updatedAt,
      ],
    );
    database.execute(
      '''
        INSERT INTO workout_sessions (
          id, started_at, timezone, local_date, ended_at, comment, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?);
      ''',
      <Object?>[
        'workout-v50',
        _seconds(DateTime.utc(2026, 7, 10, 8)),
        'UTC',
        '2026-07-10',
        _seconds(DateTime.utc(2026, 7, 10, 9)),
        'Existing workout survives',
        updatedAt,
      ],
    );
    database.execute(
      '''
        INSERT INTO logged_sets (
          id, workout_id, exercise_id, position,
          load_value, load_unit, load_entered,
          reps_value, reps_unit, reps_entered,
          is_completed, sync_previously_synced, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      ''',
      <Object?>[
        'set-v50',
        'workout-v50',
        'exercise-v50',
        0,
        80.0,
        'kilogram',
        '80',
        8.0,
        'repetition',
        '8',
        1,
        1,
        updatedAt,
      ],
    );
  } finally {
    database.close();
  }
}

int _seconds(DateTime dateTime) =>
    dateTime.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;
