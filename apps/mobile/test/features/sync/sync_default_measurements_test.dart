import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:perennia/api/perennia_api_client.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';
import 'package:perennia/features/sync/repositories/sync_repository.dart';

/// The server's canonical import (Garmin and other trackers) creates its own
/// Body Weight and Body Fat under a stable per-user id, and metrics only ever
/// flow server → device. These tests pull such a server copy onto a device
/// that seeds its own defaults, and pin down that the device ends with one
/// Body Weight and one Body Fat, not two of each.
void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  late AppDatabase database;
  late TrainingRepositories repositories;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  setUp(() {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(database);
  });

  tearDown(() async {
    await database.close();
  });

  test(
      'folds the default this device seeded into a pulled canonical-import '
      'Body Weight, keeping both histories', () async {
    await repositories.measurements.ensureDefaultMeasurements(
      bodyWeightUnit: MeasurementUnit.kilogram,
    );
    final local = await _activeByName(repositories);
    final localBodyWeightId = local['Body Weight']!.single.id;
    await repositories.measurements.createEntry(
      MeasurementEntryDraft(
        measurementId: localBodyWeightId,
        valueEntered: '82.0',
        measuredAt: DateTime.utc(2026, 6, 1, 7),
      ),
    );
    // The user put Body Fat first in Body Tracker.
    await repositories.measurements.reorderMeasurements(<String>[
      local['Body Fat']!.single.id,
      localBodyWeightId,
    ]);
    final compound = await repositories.protocols.createCompound(
      CompoundDraft(
        name: 'Creatine',
        defaultUnit: DoseUnit.gram,
        defaultRoute: DoseRoute.oral,
      ),
    );
    final protocol = await repositories.protocols.createProtocol(
      ProtocolDraft(
        name: 'Cut',
        startLocalDate: const ProtocolDayDate(year: 2026, month: 6, day: 1),
        compoundIds: <String>[compound.compoundId],
        targetOutcomes: <ProtocolTargetOutcomeDraft>[
          ProtocolTargetOutcomeDraft.metric(localBodyWeightId),
        ],
      ),
    );
    await _acknowledgeAllActivity(database);

    final pull = _serverPull(<Map<String, Object?>>[
      _serverMetricChange(
        id: _serverBodyWeightId,
        name: 'Body Weight',
        unit: 'kilogram',
      ),
      _serverReadingChange(
        id: 'reading-server-1',
        metricId: _serverBodyWeightId,
        entered: '80.5',
        atTime: DateTime.utc(2026, 6, 3, 7),
      ),
    ]);
    await pull(database);

    final active = await _activeByName(repositories);
    expect(active['Body Weight']!.map((m) => m.id), [_serverBodyWeightId]);
    expect(active['Body Fat'], hasLength(1));

    // Body Tracker keeps showing Body Weight, with the device's own settings
    // rather than the import's unpinned, disabled catalog defaults.
    final bodyTracker = await repositories.measurements.listEnabled();
    final bodyWeight = bodyTracker.singleWhere((m) => m.name == 'Body Weight');
    expect(bodyWeight.id, _serverBodyWeightId);
    expect(bodyWeight.sortOrder, 1);
    expect(bodyTracker.map((m) => m.name), <String>['Body Fat', 'Body Weight']);
    final history = await repositories.measurements
        .listHistoryEntries(measurementId: _serverBodyWeightId);
    expect(
      history.map((entry) => entry.entry.valueEntered),
      unorderedEquals(<String>['82.0', '80.5']),
    );

    // The device's copy is archived, not deleted, and nothing live points at
    // it any more.
    final archived = await (database.select(database.metrics)
          ..where((row) => row.id.equals(localBodyWeightId)))
        .getSingle();
    expect(archived.deletedAt, isNotNull);
    final readingMetricIds =
        (await database.select(database.metricReadings).get())
            .map((row) => row.metricId)
            .toSet();
    expect(readingMetricIds, isNot(contains(localBodyWeightId)));
    final readingActivity = await (database.select(database.activityLog)
          ..where(
            (row) => row.entityTable.equals(AppDatabase.metricReadingsTable),
          ))
        .get();
    expect(readingActivity, isNotEmpty);
    for (final row in readingActivity) {
      expect(row.afterImage ?? '', isNot(contains(localBodyWeightId)));
    }

    // The Protocol target outcome follows, and the re-point is queued for
    // push so other devices stop referencing an id only this device had.
    final outcomes = await (database.select(database.protocolTargetOutcomes)
          ..where((row) => row.protocolId.equals(protocol.protocolId)))
        .get();
    expect(outcomes.single.metricId, _serverBodyWeightId);
    final pendingOutcomeRows = await (database.select(database.activityLog)
          ..where(
            (row) =>
                row.entityTable
                    .equals(AppDatabase.protocolTargetOutcomesTable) &
                row.syncAcknowledgedAt.isNull(),
          ))
        .get();
    expect(pendingOutcomeRows, hasLength(1));
    expect(
      jsonDecode(pendingOutcomeRows.single.afterImage!)['metric_id'],
      _serverBodyWeightId,
    );

    // The import's version of the row is the recoverable loser in the
    // Activity Log.
    final serverMetricRows = await (database.select(database.activityLog)
          ..where((row) => row.entityId.equals(_serverBodyWeightId))
          ..orderBy([(row) => OrderingTerm.asc(row.occurredAt)]))
        .get();
    expect(
      serverMetricRows.map((row) => row.beforeImage == null),
      contains(false),
    );
    final mergeRow = serverMetricRows.lastWhere(
      (row) => row.beforeImage != null,
    );
    expect(jsonDecode(mergeRow.beforeImage!)['pinned'], isFalse);
    expect(jsonDecode(mergeRow.afterImage!)['pinned'], isTrue);

    // Pulling the same server rows again, as a full resync would, changes
    // nothing.
    await pull(database);
    final again = await _activeByName(repositories);
    expect(again['Body Weight']!.map((m) => m.id), [_serverBodyWeightId]);
    expect(
      (await repositories.measurements.listEnabled()).map((m) => m.id),
      <String>[active['Body Fat']!.single.id, _serverBodyWeightId],
    );
  });

  test('keeps a pulled Body Weight separate when its unit differs', () async {
    await repositories.measurements.ensureDefaultMeasurements(
      bodyWeightUnit: MeasurementUnit.pound,
    );
    final localPoundId =
        (await _activeByName(repositories))['Body Weight']!.single.id;

    await _serverPull(<Map<String, Object?>>[
      _serverMetricChange(
        id: _serverBodyWeightId,
        name: 'Body Weight',
        unit: 'kilogram',
      ),
    ])(database);

    // A kilogram value relabelled as pounds would be wrong, so both stay.
    final bodyWeights = (await _activeByName(repositories))['Body Weight']!;
    expect(
      bodyWeights.map((m) => m.unit),
      unorderedEquals(<MeasurementUnit>[
        MeasurementUnit.pound,
        MeasurementUnit.kilogram,
      ]),
    );
    final bodyTracker = await repositories.measurements.listEnabled();
    expect(
      bodyTracker.where((m) => m.name == 'Body Weight').map((m) => m.id),
      [localPoundId],
    );
  });

  test(
      'seeds Body Tracker from a pulled Body Weight when the pull lands '
      'before Body Tracker is first opened', () async {
    await _serverPull(<Map<String, Object?>>[
      _serverMetricChange(
        id: _serverBodyWeightId,
        name: 'Body Weight',
        unit: 'kilogram',
      ),
      _serverMetricChange(
        id: _serverBodyFatId,
        name: 'Body Fat',
        unit: 'percent',
      ),
    ])(database);

    await repositories.measurements.ensureDefaultMeasurements(
      bodyWeightUnit: MeasurementUnit.kilogram,
    );

    final active = await _activeByName(repositories);
    expect(active['Body Weight']!.map((m) => m.id), [_serverBodyWeightId]);
    expect(active['Body Fat']!.map((m) => m.id), [_serverBodyFatId]);
    final bodyTracker = await repositories.measurements.listEnabled();
    expect(
      bodyTracker.map((m) => m.id),
      <String>[_serverBodyWeightId, _serverBodyFatId],
    );

    // Opening Body Tracker again leaves it as it is.
    await repositories.measurements.ensureDefaultMeasurements(
      bodyWeightUnit: MeasurementUnit.kilogram,
    );
    expect(
      (await repositories.measurements.listActive()).map((m) => m.id),
      <String>[_serverBodyWeightId, _serverBodyFatId],
    );
  });

  test('seeds its own Body Weight when the pulled one is in a different unit',
      () async {
    await _serverPull(<Map<String, Object?>>[
      _serverMetricChange(
        id: _serverBodyWeightId,
        name: 'Body Weight',
        unit: 'kilogram',
      ),
    ])(database);

    await repositories.measurements.ensureDefaultMeasurements(
      bodyWeightUnit: MeasurementUnit.pound,
    );

    final bodyTracker = await repositories.measurements.listEnabled();
    final bodyWeight = bodyTracker.singleWhere((m) => m.name == 'Body Weight');
    expect(bodyWeight.unit, MeasurementUnit.pound);
    expect(bodyWeight.id, isNot(_serverBodyWeightId));
  });

  test('leaves the device default alone when the pulled copy is archived',
      () async {
    await repositories.measurements.ensureDefaultMeasurements(
      bodyWeightUnit: MeasurementUnit.kilogram,
    );
    final localBodyWeightId =
        (await _activeByName(repositories))['Body Weight']!.single.id;

    await _serverPull(<Map<String, Object?>>[
      _serverMetricChange(
        id: _serverBodyWeightId,
        name: 'Body Weight',
        unit: 'kilogram',
        deletedAt: DateTime.utc(2026, 6, 2, 9),
      ),
    ])(database);

    expect(
      (await _activeByName(repositories))['Body Weight']!.map((m) => m.id),
      [localBodyWeightId],
    );
  });
}

const _serverBodyWeightId = 'metric-server-body-weight';
const _serverBodyFatId = 'metric-server-body-fat';

Future<Map<String, List<MeasurementRecord>>> _activeByName(
  TrainingRepositories repositories,
) async {
  final byName = <String, List<MeasurementRecord>>{};
  for (final measurement in await repositories.measurements.listActive()) {
    byName.putIfAbsent(measurement.name, () => []).add(measurement);
  }
  return byName;
}

/// Marks every Activity Log row as already pushed, so a test can tell which
/// rows the pull itself queued for the next push.
Future<void> _acknowledgeAllActivity(AppDatabase database) async {
  await database.update(database.activityLog).write(
        ActivityLogCompanion(
          syncAcknowledgedAt: Value<DateTime?>(DateTime.utc(2026, 6, 2)),
        ),
      );
}

Future<void> Function(AppDatabase) _serverPull(
  List<Map<String, Object?>> changes,
) {
  return (database) async {
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': null,
              'serverClock': '2026-06-03T08:00:00.000Z',
              'changes': changes,
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
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
  };
}

/// A metric row shaped like the one `storeMetricDefinitionForReading` in the
/// server's canonical-import-endpoint.ts inserts for a body-composition
/// reading: the catalog's display name, goal type, and its unpinned,
/// disabled defaults.
Map<String, Object?> _serverMetricChange({
  required String id,
  required String name,
  required String unit,
  DateTime? deletedAt,
}) {
  final updatedAt = DateTime.utc(2026, 6, 2, 8);
  return <String, Object?>{
    'entity': AppDatabase.metricsTable,
    'id': id,
    'deviceId': 'integration:garmin',
    'payload': <String, Object?>{
      'id': id,
      'name': name,
      'unit': unit,
      'value_shape': MetricValueShape.scalar.name,
      'metric_group': MetricGroup.bodyComposition.name,
      'goal_type': MeasurementGoalType.decrease.name,
      'goal_target_value': null,
      'enabled': false,
      'pinned': false,
      'sort_order': 500,
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    },
    'updatedAt': (deletedAt ?? updatedAt).toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };
}

Map<String, Object?> _serverReadingChange({
  required String id,
  required String metricId,
  required String entered,
  required DateTime atTime,
}) {
  final value = double.parse(entered);
  return <String, Object?>{
    'entity': AppDatabase.metricReadingsTable,
    'id': id,
    'deviceId': 'integration:garmin',
    'payload': <String, Object?>{
      'id': id,
      'metric_id': metricId,
      'external_activity_id': null,
      'value_json': <String, Object?>{
        'shape': 'scalar',
        'value': value,
        'entered': entered,
      },
      'scalar_value': value,
      'scalar_entered': entered,
      'at_time': atTime.toIso8601String(),
      'window_started_at': null,
      'window_ended_at': null,
      'provenance': MetricReadingProvenance.integration.name,
      'source': 'garmin',
      'external_id': 'garmin:weight:$id',
      'comment': null,
      'updated_at': atTime.toIso8601String(),
      'deleted_at': null,
    },
    'updatedAt': atTime.toIso8601String(),
    'deletedAt': null,
  };
}
