import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  group('logged set performed-at/index migrations', () {
    test('adds performedAt as nullable and preserves existing rows', () async {
      final directory = await Directory.systemTemp.createTemp(
        'prn_logged_set_performed_at_migration_',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      final databaseFile = File('${directory.path}/v48.sqlite');

      _createV48LoggedSetDatabase(databaseFile);

      final database = AppDatabase.openFile(databaseFile);
      addTearDown(database.close);

      expect(
        await _columnNames(database, AppDatabase.loggedSetsTable),
        contains('performed_at'),
      );

      final set = await database.select(database.loggedSets).getSingle();
      expect(set.id, 'set-1');
      expect(set.workoutId, 'workout-1');
      expect(set.exerciseId, 'exercise-1');
      expect(set.position, 0);
      expect(set.plannedRestAfter, 90);
      expect(set.performedAt, isNull);
      expect(set.repsEntered, '10');
      expect(set.syncPreviouslySynced, isTrue);
      expect(
        await _indexNames(database, AppDatabase.loggedSetsTable),
        contains('logged_sets_exercise_id_index'),
      );
    });

    test('re-opening the migrated database is a no-op', () async {
      final directory = await Directory.systemTemp.createTemp(
        'prn_logged_set_performed_at_migration_idempotent_',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      final databaseFile = File('${directory.path}/v48.sqlite');

      _createV48LoggedSetDatabase(databaseFile);

      final first = AppDatabase.openFile(databaseFile);
      await first.customSelect('SELECT 1').get();
      await first.close();

      final second = AppDatabase.openFile(databaseFile);
      addTearDown(second.close);
      final set = await second.select(second.loggedSets).getSingle();
      expect(set.performedAt, isNull);
    });

    test('adds the exercise history index to v49 databases', () async {
      final directory = await Directory.systemTemp.createTemp(
        'prn_logged_set_exercise_index_migration_',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      final databaseFile = File('${directory.path}/v49.sqlite');

      _createV49LoggedSetDatabase(databaseFile);

      final database = AppDatabase.openFile(databaseFile);
      addTearDown(database.close);

      expect(
        await _indexNames(database, AppDatabase.loggedSetsTable),
        contains('logged_sets_exercise_id_index'),
      );
    });
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

Future<Set<String>> _indexNames(
  AppDatabase database,
  String tableName,
) async {
  final rows =
      await database.customSelect('PRAGMA index_list($tableName)').get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

void _createV49LoggedSetDatabase(File file) {
  _createV48LoggedSetDatabase(file);
  final database = sqlite.sqlite3.open(file.path);
  try {
    database.execute('''
      ALTER TABLE logged_sets ADD COLUMN performed_at INTEGER NULL;
      PRAGMA user_version = 49;
    ''');
  } finally {
    database.close();
  }
}

void _createV48LoggedSetDatabase(File file) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    database.execute('''
      PRAGMA foreign_keys = OFF;

      CREATE TABLE logged_sets (
        id TEXT NOT NULL PRIMARY KEY,
        workout_id TEXT NOT NULL REFERENCES workout_sessions (id),
        exercise_id TEXT NOT NULL REFERENCES exercises (id),
        position INTEGER NOT NULL,
        planned_rest_after INTEGER NULL,
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

      PRAGMA user_version = 48;
    ''');

    database.execute(
      '''
        INSERT INTO logged_sets (
          id, workout_id, exercise_id, position, planned_rest_after,
          load_value, load_unit, load_entered, reps_value, reps_unit,
          reps_entered, duration_value, duration_unit, duration_entered,
          distance_value, distance_unit, distance_entered, comment, side, rpe,
          is_completed, sync_device_id, sync_previously_synced, updated_at,
          deleted_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
          ?, ?, ?, ?, ?);
      ''',
      <Object?>[
        'set-1',
        'workout-1',
        'exercise-1',
        0,
        90,
        null,
        null,
        null,
        10.0,
        'repetition',
        '10',
        null,
        null,
        null,
        null,
        null,
        null,
        'steady',
        null,
        7.0,
        1,
        'device-a',
        1,
        _seconds(DateTime.utc(2026, 7, 8, 10)),
        null,
      ],
    );
  } finally {
    database.close();
  }
}

int _seconds(DateTime dateTime) =>
    dateTime.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;
