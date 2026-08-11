import 'dart:convert';
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

  group('Measurement to Metric migration', () {
    test('preserves goals, comments, timestamps, archive state, and ids',
        () async {
      final directory = await Directory.systemTemp.createTemp(
        'prn_metric_migration_',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      final databaseFile = File('${directory.path}/v24.sqlite');

      _createV24MeasurementDatabase(databaseFile);

      final database = AppDatabase.openFile(databaseFile);
      addTearDown(database.close);

      final metrics = await database.select(database.metrics).get();
      final metricsById = <String, MetricRow>{
        for (final metric in metrics) metric.id: metric,
      };
      final readings = await _metricReadingRows(database);
      final readingsById = <String, Map<String, Object?>>{
        for (final reading in readings) reading['id']! as String: reading,
      };
      final measurements = await database.select(database.measurements).get();
      final entries = await database.select(database.measurementEntries).get();

      final bodyWeight = metricsById['0196f0a0-0000-7000-8000-000000000101']!;
      expect(metrics, hasLength(3));
      expect(bodyWeight.name, 'Body Weight');
      expect(bodyWeight.unit, 'kilogram');
      expect(bodyWeight.valueShape, 'scalar');
      expect(bodyWeight.metricGroup, 'bodyComposition');
      expect(bodyWeight.goalType, 'target');
      expect(bodyWeight.goalTargetValue, 80);
      expect(bodyWeight.enabled, isTrue);
      expect(bodyWeight.pinned, isTrue);
      expect(bodyWeight.sortOrder, 0);
      expect(bodyWeight.updatedAt.toUtc(), DateTime.utc(2026, 6, 20, 8));
      expect(bodyWeight.deletedAt, isNull);
      expect(_isUuidV7(bodyWeight.id), isTrue);

      final bodyFat = metricsById['0196f0a0-0000-7000-8000-000000000102']!;
      expect(bodyFat.name, 'Body Fat');
      expect(bodyFat.unit, 'percent');
      expect(bodyFat.goalType, 'decrease');
      expect(bodyFat.goalTargetValue, isNull);
      expect(bodyFat.enabled, isTrue);
      expect(bodyFat.pinned, isTrue);
      expect(bodyFat.sortOrder, 1);

      final archived = metricsById['0196f0a0-0000-7000-8000-000000000103']!;
      expect(archived.name, 'Waist');
      expect(archived.unit, 'centimeter');
      expect(archived.goalType, 'increase');
      expect(archived.goalTargetValue, 92.5);
      expect(archived.enabled, isFalse);
      expect(archived.pinned, isFalse);
      expect(archived.sortOrder, 2);
      expect(archived.updatedAt.toUtc(), DateTime.utc(2026, 6, 20, 10));
      expect(archived.deletedAt?.toUtc(), DateTime.utc(2026, 6, 21, 10));

      expect(readings, hasLength(2));
      final weightReading =
          readingsById['0196f0a0-0000-7000-8000-000000000201']!;
      expect(
        weightReading['metric_id'],
        '0196f0a0-0000-7000-8000-000000000101',
      );
      expect(_isUuidV7(weightReading['id']! as String), isTrue);
      expect(weightReading['scalar_value'], 82.125);
      expect(weightReading['scalar_entered'], '82.125');
      expect(weightReading['at_time'], _seconds(DateTime.utc(2026, 6, 20, 7)));
      expect(weightReading['window_started_at'], isNull);
      expect(weightReading['window_ended_at'], isNull);
      expect(weightReading['provenance'], 'manual');
      expect(weightReading['source'], 'manual');
      expect(
        weightReading['external_id'],
        '0196f0a0-0000-7000-8000-000000000201',
      );
      expect(weightReading['comment'], 'after breakfast');
      expect(
        weightReading['updated_at'],
        _seconds(DateTime.utc(2026, 6, 20, 7, 5)),
      );
      expect(weightReading['deleted_at'], isNull);
      expect(
        jsonDecode(weightReading['value_json']! as String),
        <String, Object?>{
          'shape': 'scalar',
          'value': 82.125,
          'entered': '82.125',
        },
      );

      final archivedReading =
          readingsById['0196f0a0-0000-7000-8000-000000000202']!;
      expect(
        archivedReading['metric_id'],
        '0196f0a0-0000-7000-8000-000000000103',
      );
      expect(archivedReading['comment'], 'archived note');
      expect(
        archivedReading['updated_at'],
        _seconds(DateTime.utc(2026, 6, 20, 10, 5)),
      );
      expect(
        archivedReading['deleted_at'],
        _seconds(DateTime.utc(2026, 6, 21, 10, 5)),
      );

      expect(measurements, hasLength(3));
      expect(entries, hasLength(2));
      expect(
        entries.singleWhere((entry) => entry.id == weightReading['id']).comment,
        'after breakfast',
      );
    });

    test('can rerun without duplicating Metrics or Readings', () async {
      final directory = await Directory.systemTemp.createTemp(
        'prn_metric_migration_idempotent_',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      final databaseFile = File('${directory.path}/v24.sqlite');

      _createV24MeasurementDatabase(databaseFile);

      final database = AppDatabase.openFile(databaseFile);
      addTearDown(database.close);

      await database.backfillMetricsFromMeasurements();
      final firstSnapshot = await _metricSnapshot(database);

      await database.backfillMetricsFromMeasurements();

      expect(await _metricSnapshot(database), firstSnapshot);
    });
  });
}

Future<List<Map<String, Object?>>> _metricSnapshot(AppDatabase database) async {
  final rows = await database.customSelect(
    '''
          SELECT
            'metric' AS row_type,
            id,
            name,
            unit,
            value_shape,
            metric_group,
            goal_type,
            goal_target_value,
            enabled,
            pinned,
            sort_order,
            updated_at,
            deleted_at,
            NULL AS metric_id,
            NULL AS value_json,
            NULL AS scalar_value,
            NULL AS scalar_entered,
            NULL AS at_time,
            NULL AS window_started_at,
            NULL AS window_ended_at,
            NULL AS provenance,
            NULL AS source,
            NULL AS external_id,
            NULL AS comment
          FROM metrics
          UNION ALL
          SELECT
            'reading' AS row_type,
            id,
            NULL AS name,
            NULL AS unit,
            NULL AS value_shape,
            NULL AS metric_group,
            NULL AS goal_type,
            NULL AS goal_target_value,
            NULL AS enabled,
            NULL AS pinned,
            NULL AS sort_order,
            updated_at,
            deleted_at,
            metric_id,
            value_json,
            scalar_value,
            scalar_entered,
            at_time,
            window_started_at,
            window_ended_at,
            provenance,
            source,
            external_id,
            comment
          FROM metric_readings
          ORDER BY row_type, id
        ''',
  ).get();
  return rows.map((row) => Map<String, Object?>.from(row.data)).toList();
}

Future<List<Map<String, Object?>>> _metricReadingRows(
  AppDatabase database,
) async {
  final rows = await database.customSelect(
    '''
          SELECT
            id,
            metric_id,
            value_json,
            scalar_value,
            scalar_entered,
            at_time,
            window_started_at,
            window_ended_at,
            provenance,
            source,
            external_id,
            comment,
            updated_at,
            deleted_at
          FROM metric_readings
          ORDER BY id
        ''',
  ).get();
  return rows.map((row) => Map<String, Object?>.from(row.data)).toList();
}

void _createV24MeasurementDatabase(File file) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    database.execute('''
      PRAGMA foreign_keys = OFF;

      CREATE TABLE measurements (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        unit TEXT NOT NULL,
        goal_type TEXT NOT NULL,
        target_value REAL NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE INDEX measurements_sort_order_index
        ON measurements (sort_order);

      CREATE TABLE measurement_entries (
        id TEXT NOT NULL PRIMARY KEY,
        measurement_id TEXT NOT NULL REFERENCES measurements (id),
        value REAL NOT NULL,
        value_entered TEXT NOT NULL,
        measured_at INTEGER NOT NULL,
        comment TEXT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE INDEX measurement_entries_measurement_id_index
        ON measurement_entries (measurement_id);

      CREATE INDEX measurement_entries_measured_at_index
        ON measurement_entries (measured_at);

      PRAGMA user_version = 24;
    ''');

    _insertMeasurement(
      database,
      id: '0196f0a0-0000-7000-8000-000000000101',
      name: 'Body Weight',
      unit: 'kilogram',
      goalType: 'target',
      targetValue: 80,
      enabled: true,
      sortOrder: 0,
      updatedAt: DateTime.utc(2026, 6, 20, 8),
    );
    _insertMeasurement(
      database,
      id: '0196f0a0-0000-7000-8000-000000000102',
      name: 'Body Fat',
      unit: 'percent',
      goalType: 'decrease',
      enabled: true,
      sortOrder: 1,
      updatedAt: DateTime.utc(2026, 6, 20, 9),
    );
    _insertMeasurement(
      database,
      id: '0196f0a0-0000-7000-8000-000000000103',
      name: 'Waist',
      unit: 'centimeter',
      goalType: 'increase',
      targetValue: 92.5,
      enabled: false,
      sortOrder: 2,
      updatedAt: DateTime.utc(2026, 6, 20, 10),
      deletedAt: DateTime.utc(2026, 6, 21, 10),
    );

    _insertMeasurementEntry(
      database,
      id: '0196f0a0-0000-7000-8000-000000000201',
      measurementId: '0196f0a0-0000-7000-8000-000000000101',
      value: 82.125,
      valueEntered: '82.125',
      measuredAt: DateTime.utc(2026, 6, 20, 7),
      comment: 'after breakfast',
      updatedAt: DateTime.utc(2026, 6, 20, 7, 5),
    );
    _insertMeasurementEntry(
      database,
      id: '0196f0a0-0000-7000-8000-000000000202',
      measurementId: '0196f0a0-0000-7000-8000-000000000103',
      value: 91.5,
      valueEntered: '91.5',
      measuredAt: DateTime.utc(2026, 6, 20, 10),
      comment: 'archived note',
      updatedAt: DateTime.utc(2026, 6, 20, 10, 5),
      deletedAt: DateTime.utc(2026, 6, 21, 10, 5),
    );
  } finally {
    database.close();
  }
}

void _insertMeasurement(
  sqlite.Database database, {
  required String id,
  required String name,
  required String unit,
  required String goalType,
  required bool enabled,
  required int sortOrder,
  required DateTime updatedAt,
  double? targetValue,
  DateTime? deletedAt,
}) {
  database.execute(
    '''
      INSERT INTO measurements (
        id,
        name,
        unit,
        goal_type,
        target_value,
        enabled,
        sort_order,
        updated_at,
        deleted_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
    ''',
    <Object?>[
      id,
      name,
      unit,
      goalType,
      targetValue,
      enabled ? 1 : 0,
      sortOrder,
      _seconds(updatedAt),
      deletedAt == null ? null : _seconds(deletedAt),
    ],
  );
}

void _insertMeasurementEntry(
  sqlite.Database database, {
  required String id,
  required String measurementId,
  required double value,
  required String valueEntered,
  required DateTime measuredAt,
  required DateTime updatedAt,
  String? comment,
  DateTime? deletedAt,
}) {
  database.execute(
    '''
      INSERT INTO measurement_entries (
        id,
        measurement_id,
        value,
        value_entered,
        measured_at,
        comment,
        updated_at,
        deleted_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
    ''',
    <Object?>[
      id,
      measurementId,
      value,
      valueEntered,
      _seconds(measuredAt),
      comment,
      _seconds(updatedAt),
      deletedAt == null ? null : _seconds(deletedAt),
    ],
  );
}

int _seconds(DateTime dateTime) =>
    dateTime.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;

bool _isUuidV7(String value) {
  return RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(value);
}
