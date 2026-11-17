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

/// Body Tracker measurements (Metrics) and their readings push like every
/// other authored entity, so a second device gets them. The one twist is a
/// default measurement the server already has under another id: the server
/// folds the pushed copy into its own and says so in `merged`, and the
/// device keeps the copy device-only until the pull folds it in too.
void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  late AppDatabase database;
  late TrainingRepositories repositories;
  late _FakeSyncServer server;
  late SyncRepository sync;

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
    server = _FakeSyncServer();
    sync = SyncRepository(
      database: database,
      trainingRepositories: repositories,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(server.handle),
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
      'pushes Metrics, then their readings, before Protocol target outcomes, '
      'and acknowledges both', () async {
    await repositories.measurements.ensureDefaultMeasurements(
      bodyWeightUnit: MeasurementUnit.kilogram,
    );
    final bodyWeightId = await _bodyWeightId(repositories);
    final readingId = await repositories.measurements.createEntry(
      MeasurementEntryDraft(
        measurementId: bodyWeightId,
        valueEntered: '82.0',
        measuredAt: DateTime.utc(2026, 6, 1, 7),
      ),
    );
    final compound = await repositories.protocols.createCompound(
      CompoundDraft(
        name: 'Creatine',
        defaultUnit: DoseUnit.gram,
        defaultRoute: DoseRoute.oral,
      ),
    );
    await repositories.protocols.createProtocol(
      ProtocolDraft(
        name: 'Cut',
        startLocalDate: const ProtocolDayDate(year: 2026, month: 6, day: 1),
        compoundIds: <String>[compound.compoundId],
        targetOutcomes: <ProtocolTargetOutcomeDraft>[
          ProtocolTargetOutcomeDraft.metric(bodyWeightId),
        ],
      ),
    );
    expect(await sync.hasPendingChanges(), isTrue);

    await sync.pushPendingLoggedSets(session: _session, deviceId: 'device-a');

    final entities = server.pushes.map((push) => push.entity).toList();
    expect(
      entities.indexOf(AppDatabase.metricsTable),
      lessThan(entities.indexOf(AppDatabase.metricReadingsTable)),
    );
    expect(
      entities.indexOf(AppDatabase.metricReadingsTable),
      lessThan(entities.indexOf(AppDatabase.protocolTargetOutcomesTable)),
    );
    final metricPush = server.pushes
        .singleWhere((push) => push.entity == AppDatabase.metricsTable);
    expect(
      metricPush.changes.map((change) => change['id']),
      contains(bodyWeightId),
    );
    final readingPush = server.pushes
        .singleWhere((push) => push.entity == AppDatabase.metricReadingsTable);
    final pushedReading = readingPush.changes.single;
    expect(pushedReading['id'], readingId);
    final payload = pushedReading['payload']! as Map<String, Object?>;
    expect(payload['metric_id'], bodyWeightId);
    expect(payload['provenance'], MetricReadingProvenance.manual.name);
    expect(pushedReading['activityLogId'], isA<String>());

    expect(await sync.hasPendingChanges(), isFalse);
    final metric = await (database.select(database.metrics)
          ..where((row) => row.id.equals(bodyWeightId)))
        .getSingle();
    expect(metric.syncPreviouslySynced, isTrue);
    expect(metric.syncDeviceId, 'device-a');
    final reading = await (database.select(database.metricReadings)
          ..where((row) => row.id.equals(readingId)))
        .getSingle();
    expect(reading.syncPreviouslySynced, isTrue);
    expect(reading.syncDeviceId, 'device-a');
    expect(reading.updatedAt.toUtc(), server.appliedUpdatedAt);
  });

  test(
      'keeps a Metric the server merged device-only, so the next pull folds '
      'it into the survivor and pushes the curation', () async {
    await repositories.measurements.ensureDefaultMeasurements(
      bodyWeightUnit: MeasurementUnit.kilogram,
    );
    final copyId = await _bodyWeightId(repositories);
    await repositories.measurements.createEntry(
      MeasurementEntryDraft(
        measurementId: copyId,
        valueEntered: '82.0',
        measuredAt: DateTime.utc(2026, 6, 1, 7),
      ),
    );
    server.mergeInto[copyId] = _survivorId;

    await sync.pushPendingLoggedSets(session: _session, deviceId: 'device-b');

    expect(await sync.hasPendingChanges(), isFalse);
    final copy = await (database.select(database.metrics)
          ..where((row) => row.id.equals(copyId)))
        .getSingle();
    expect(copy.syncPreviouslySynced, isFalse);
    expect(copy.deletedAt, isNull);

    server.pullChanges.add(_survivorChange());
    await sync.pullLoggedSetChanges(session: _session, deviceId: 'device-b');

    final bodyWeights = (await repositories.measurements.listActive())
        .where((measurement) => measurement.name == 'Body Weight');
    expect(bodyWeights.map((m) => m.id), [_survivorId]);
    final history = await repositories.measurements
        .listHistoryEntries(measurementId: _survivorId);
    expect(history.map((entry) => entry.entry.valueEntered), ['82.0']);

    // The fold's own changes go to the server next: the survivor with this
    // device's Body Tracker curation, and the copy's archive. Readings move
    // in place: the server already stores them under the survivor.
    final pendingByTable = <String, List<ActivityLogRow>>{};
    for (final row in await (database.select(database.activityLog)
          ..where((row) => row.syncAcknowledgedAt.isNull()))
        .get()) {
      pendingByTable.putIfAbsent(row.entityTable, () => []).add(row);
    }
    expect(pendingByTable.keys, [AppDatabase.metricsTable]);
    final pendingImages = pendingByTable[AppDatabase.metricsTable]!
        .map((row) => jsonDecode(row.afterImage!) as Map<String, Object?>);
    final survivorImage =
        pendingImages.singleWhere((image) => image['id'] == _survivorId);
    expect(survivorImage['pinned'], isTrue);
    expect(survivorImage['enabled'], isTrue);
    final copyImage =
        pendingImages.singleWhere((image) => image['id'] == copyId);
    expect(copyImage['deleted_at'], isNotNull);

    server.pushes.clear();
    await sync.pushPendingLoggedSets(session: _session, deviceId: 'device-b');
    expect(server.pushes.map((push) => push.entity), [
      AppDatabase.metricsTable,
    ]);
    expect(await sync.hasPendingChanges(), isFalse);
  });

  test('a Metric the server stores under its own id is synced, not merged',
      () async {
    await repositories.measurements.ensureDefaultMeasurements(
      bodyWeightUnit: MeasurementUnit.kilogram,
    );
    final bodyWeightId = await _bodyWeightId(repositories);

    await sync.pushPendingLoggedSets(session: _session, deviceId: 'device-a');
    // Another device's Body Weight arriving later is the server's to
    // reconcile, so this device's synced copy stays as it is.
    server.pullChanges.add(_survivorChange());
    await sync.pullLoggedSetChanges(session: _session, deviceId: 'device-a');

    final bodyWeights = (await repositories.measurements.listActive())
        .where((measurement) => measurement.name == 'Body Weight')
        .map((measurement) => measurement.id);
    expect(bodyWeights, unorderedEquals(<String>[bodyWeightId, _survivorId]));
  });
}

const _survivorId = 'metric-server-body-weight';

final _session = AuthSession(
  provider: AuthSessionProvider.email,
  serverUrl: Uri.parse('https://sync.example/'),
  token: 'session-token',
  userEmail: 'user@example.com',
  userId: 'user-1',
  userName: 'Sync User',
);

Future<String> _bodyWeightId(TrainingRepositories repositories) async {
  return (await repositories.measurements.listActive())
      .singleWhere((measurement) => measurement.name == 'Body Weight')
      .id;
}

/// Another device's Body Weight as the server returns it: pinned, enabled,
/// written after this device seeded its own.
Map<String, Object?> _survivorChange() {
  final updatedAt = DateTime.utc(2026, 6, 2, 8).toIso8601String();
  return <String, Object?>{
    'entity': AppDatabase.metricsTable,
    'id': _survivorId,
    'deviceId': 'device-other',
    'payload': <String, Object?>{
      'id': _survivorId,
      'name': 'Body Weight',
      'unit': 'kilogram',
      'value_shape': MetricValueShape.scalar.name,
      'metric_group': MetricGroup.bodyComposition.name,
      'goal_type': MeasurementGoalType.decrease.name,
      'goal_target_value': null,
      'enabled': false,
      'pinned': false,
      'sort_order': 3,
      'updated_at': updatedAt,
      'deleted_at': null,
    },
    'updatedAt': updatedAt,
    'deletedAt': null,
  };
}

class _Push {
  const _Push(this.entity, this.changes);

  final String entity;
  final List<Map<String, Object?>> changes;
}

/// Accepts and applies every pushed change, except that an id listed in
/// [mergeInto] is reported as merged into its survivor; serves
/// [pullChanges] once.
class _FakeSyncServer {
  final pushes = <_Push>[];
  final mergeInto = <String, String>{};
  final pullChanges = <Map<String, Object?>>[];
  final appliedUpdatedAt = DateTime.utc(2026, 6, 1, 9);

  Future<http.Response> handle(http.Request request) async {
    final body = jsonDecode(request.body) as Map<String, Object?>;
    if (request.url.path.endsWith('/sync/pull')) {
      final changes = List<Map<String, Object?>>.of(pullChanges);
      pullChanges.clear();
      return _json(<String, Object?>{
        'protocolVersion': syncProtocolVersion,
        'nextCursor': changes.isEmpty ? body['cursor'] : 'cursor-1',
        'serverClock': '2026-06-03T08:00:00.000Z',
        'changes': changes,
      });
    }

    final entity = body['entity']! as String;
    final changes = (body['changes']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .toList(growable: false);
    pushes.add(_Push(entity, changes));
    final ids = changes.map((change) => change['id']! as String).toList();
    return _json(<String, Object?>{
      'protocolVersion': syncProtocolVersion,
      'accepted': ids,
      'serverClock': '2026-06-01T09:00:00.000Z',
      'applied': <Map<String, Object?>>[
        for (final id in ids)
          <String, Object?>{
            'id': id,
            'updatedAt': appliedUpdatedAt.toIso8601String(),
            'deviceId': body['deviceId'],
          },
      ],
      'merged': <Map<String, Object?>>[
        for (final id in ids)
          if (mergeInto.containsKey(id))
            <String, Object?>{'id': id, 'intoId': mergeInto[id]},
      ],
    });
  }

  http.Response _json(Map<String, Object?> body) {
    return http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
}
