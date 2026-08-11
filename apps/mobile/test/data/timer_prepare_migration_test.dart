import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// added the fire-once `prepareAlertFiredAt` marker in schema 47.
/// later makes interval timers source-neutral: a timer backed by the
/// retired plan tree is deliberately discarded while an independent Rest Timer
/// survives the full upgrade.
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

  group('rest/interval prepare-cue migration through the v55 cutover', () {
    test('preserves Rest Timer state and discards the retired interval source',
        () async {
      final directory = await Directory.systemTemp.createTemp(
        'prn_timer_prepare_migration_',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      final databaseFile = File('${directory.path}/v46.sqlite');

      _createV46TimerDatabase(databaseFile);

      final database = AppDatabase.openFile(databaseFile);
      addTearDown(database.close);

      // The Rest Timer keeps its marker. The interval table is rebuilt in its
      // source-neutral shape because the old row cannot outlive its plan.
      expect(
        await _columnNames(database, 'rest_timers'),
        contains('prepare_alert_fired_at'),
      );
      expect(
        await _columnNames(database, 'interval_timers'),
        contains('prepare_alert_fired_at'),
      );
      expect(
        await _columnNames(database, 'interval_timers'),
        isNot(contains('routine_day_id')),
      );

      final rest = await database.select(database.restTimers).getSingle();
      expect(rest.id, 'rest-1');
      expect(rest.durationSeconds, 120);
      expect(rest.status, 'running');
      expect(rest.alertFiredAt, isNull);
      expect(rest.prepareAlertFiredAt, isNull);

      expect(await database.select(database.intervalTimers).get(), isEmpty);
    });

    test('re-opening the migrated database is a no-op', () async {
      final directory = await Directory.systemTemp.createTemp(
        'prn_timer_prepare_migration_idempotent_',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      final databaseFile = File('${directory.path}/v46.sqlite');

      _createV46TimerDatabase(databaseFile);

      final first = AppDatabase.openFile(databaseFile);
      await first.customSelect('SELECT 1').get();
      await first.close();

      // Second open sees the current version; neither the guarded addColumn nor
      // the source-neutral table rebuild runs twice.
      final second = AppDatabase.openFile(databaseFile);
      addTearDown(second.close);
      final rest = await second.select(second.restTimers).getSingle();
      expect(rest.prepareAlertFiredAt, isNull);
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

void _createV46TimerDatabase(File file) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    database.execute('''
      PRAGMA foreign_keys = OFF;

      CREATE TABLE rest_timers (
        id TEXT NOT NULL PRIMARY KEY,
        workout_id TEXT NULL,
        source_set_id TEXT NULL,
        started_at INTEGER NOT NULL,
        deadline_at INTEGER NOT NULL,
        duration_seconds INTEGER NOT NULL,
        alert_volume REAL NOT NULL DEFAULT 1.0,
        status TEXT NOT NULL DEFAULT 'running',
        alert_fired_at INTEGER NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE TABLE interval_timers (
        id TEXT NOT NULL PRIMARY KEY,
        workout_id TEXT NOT NULL,
        routine_day_id TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        phase_started_at INTEGER NOT NULL,
        deadline_at INTEGER NOT NULL,
        current_step_index INTEGER NOT NULL DEFAULT 0,
        completed_set_count INTEGER NOT NULL DEFAULT 0,
        alert_volume REAL NOT NULL DEFAULT 1.0,
        phase TEXT NOT NULL DEFAULT 'work',
        status TEXT NOT NULL DEFAULT 'running',
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE INDEX interval_timers_workout_id_index
        ON interval_timers (workout_id);

      PRAGMA user_version = 46;
    ''');

    database.execute(
      '''
        INSERT INTO rest_timers (
          id, workout_id, source_set_id, started_at, deadline_at,
          duration_seconds, alert_volume, status, alert_fired_at,
          updated_at, deleted_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      ''',
      <Object?>[
        'rest-1',
        'workout-1',
        'set-1',
        _seconds(DateTime.utc(2026, 7, 4, 8)),
        _seconds(DateTime.utc(2026, 7, 4, 8, 2)),
        120,
        1.0,
        'running',
        null,
        _seconds(DateTime.utc(2026, 7, 4, 8)),
        null,
      ],
    );

    database.execute(
      '''
        INSERT INTO interval_timers (
          id, workout_id, routine_day_id, started_at, phase_started_at,
          deadline_at, current_step_index, completed_set_count, alert_volume,
          phase, status, updated_at, deleted_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      ''',
      <Object?>[
        'interval-1',
        'workout-1',
        'routine-day-1',
        _seconds(DateTime.utc(2026, 7, 4, 8)),
        _seconds(DateTime.utc(2026, 7, 4, 8)),
        _seconds(DateTime.utc(2026, 7, 4, 8, 0, 20)),
        0,
        0,
        1.0,
        'work',
        'running',
        _seconds(DateTime.utc(2026, 7, 4, 8)),
        null,
      ],
    );
  } finally {
    database.close();
  }
}

int _seconds(DateTime dateTime) =>
    dateTime.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;
