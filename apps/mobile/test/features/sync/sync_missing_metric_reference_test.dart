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

/// These tests model a server with a pulled Protocol target outcome but without
/// its Metric. They pin down that the outcome waits on device B until its
/// Metric arrives, and is applied then.
void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  late AppDatabase databaseA;
  late AppDatabase databaseB;
  late TrainingRepositories repositoriesA;
  late _FakeSyncServer server;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  setUp(() {
    databaseA = AppDatabase.inMemory();
    databaseB = AppDatabase.inMemory();
    repositoriesA = TrainingRepositories(databaseA);
    server = _FakeSyncServer();
  });

  tearDown(() async {
    await databaseA.close();
    await databaseB.close();
  });

  Future<({String metricId, String protocolId, String outcomeId})>
      createProtocolTargetingOwnMetricOnA() async {
    final metricId = await repositoriesA.metrics.createMetric(
      MetricDraft(
        name: 'Resting heart rate',
        unit: 'bpm',
        valueShape: MetricValueShape.scalar,
        group: MetricGroup.bodyComposition,
        enabled: true,
        pinned: false,
      ),
    );
    final compound = await repositoriesA.protocols.createCompound(
      CompoundDraft(
        name: 'Magnesium',
        defaultUnit: DoseUnit.milligram,
        defaultRoute: DoseRoute.oral,
      ),
    );
    final protocol = await repositoriesA.protocols.createProtocol(
      ProtocolDraft(
        name: 'Recovery',
        startDate: DateTime.utc(2026, 6, 1),
        compoundIds: <String>[compound.compoundId],
        targetOutcomes: <ProtocolTargetOutcomeDraft>[
          ProtocolTargetOutcomeDraft.metric(metricId),
        ],
      ),
    );
    final outcome = await (databaseA.select(databaseA.protocolTargetOutcomes)
          ..where((row) => row.protocolId.equals(protocol.protocolId)))
        .getSingle();
    return (
      metricId: metricId,
      protocolId: protocol.protocolId,
      outcomeId: outcome.id,
    );
  }

  test(
      'a pulled target outcome whose Metric this device lacks waits for it '
      'instead of failing the pull', () async {
    final created = await createProtocolTargetingOwnMetricOnA();
    await server.push(databaseA, deviceId: 'device-a');
    expect(
      server.changes.map((change) => change['entity']),
      contains(AppDatabase.protocolTargetOutcomesTable),
    );

    // Before the guard this threw SqliteException(787) and rolled the whole
    // batch back, every time.
    final first = await server.pull(databaseB, deviceId: 'device-b');
    expect(first.appliedCount, greaterThan(0));

    final protocolsOnB = await databaseB.select(databaseB.protocols).get();
    expect(protocolsOnB.map((row) => row.id), <String>[created.protocolId]);
    expect(
      await databaseB.select(databaseB.protocolCompounds).get(),
      hasLength(1),
    );
    expect(await databaseB.select(databaseB.protocolTargetOutcomes).get(),
        isEmpty);
    final deferred =
        await databaseB.select(databaseB.deferredSyncChanges).get();
    expect(deferred.map((row) => row.entityId), <String>[created.outcomeId]);
    expect(deferred.single.missingEntityTable, AppDatabase.metricsTable);
    expect(deferred.single.missingEntityId, created.metricId);

    // The next pull carries the same rows again and still goes through.
    await server.pull(databaseB, deviceId: 'device-b');
    expect(await databaseB.select(databaseB.deferredSyncChanges).get(),
        hasLength(1));

    // Once the Metric reaches B (pushing metrics is the follow-up), the
    // outcome it was waiting on lands, logged like any other pulled change.
    await server.addServerMetric(databaseA, created.metricId,
        deviceId: 'device-a');
    await server.pull(databaseB, deviceId: 'device-b');

    final outcomesOnB =
        await databaseB.select(databaseB.protocolTargetOutcomes).get();
    expect(outcomesOnB.map((row) => row.id), <String>[created.outcomeId]);
    expect(outcomesOnB.single.metricId, created.metricId);
    expect(outcomesOnB.single.protocolId, created.protocolId);
    expect(outcomesOnB.single.syncDeviceId, 'device-a');
    expect(
        await databaseB.select(databaseB.deferredSyncChanges).get(), isEmpty);
    final outcomeActivity = await (databaseB.select(databaseB.activityLog)
          ..where(
            (row) =>
                row.entityTable
                    .equals(AppDatabase.protocolTargetOutcomesTable) &
                row.entityId.equals(created.outcomeId),
          ))
        .get();
    expect(outcomeActivity, hasLength(1));
    expect(outcomeActivity.single.afterImage, contains(created.metricId));
  });

  test('a deferred target outcome keeps the last-writer-wins version',
      () async {
    final created = await createProtocolTargetingOwnMetricOnA();
    await server.push(databaseA, deviceId: 'device-a');
    final original = server.changes.singleWhere(
      (change) => change['entity'] == AppDatabase.protocolTargetOutcomesTable,
    );
    final originalUpdatedAt = DateTime.parse(original['updatedAt']! as String);

    Map<String, Object?> outcomeVersion(DateTime updatedAt, int position) {
      final payload = Map<String, Object?>.from(
        original['payload']! as Map<String, Object?>,
      );
      payload['position'] = position;
      payload['updated_at'] = updatedAt.toIso8601String();
      return <String, Object?>{
        ...original,
        'payload': payload,
        'updatedAt': updatedAt.toIso8601String(),
      };
    }

    final newer = outcomeVersion(
      originalUpdatedAt.add(const Duration(minutes: 5)),
      7,
    );
    final older = outcomeVersion(
      originalUpdatedAt.subtract(const Duration(minutes: 5)),
      3,
    );

    server.changes
      ..remove(original)
      ..add(newer);
    await server.pull(databaseB, deviceId: 'device-b');
    server.changes
      ..remove(newer)
      ..add(older);
    await server.pull(databaseB, deviceId: 'device-b');

    server.changes.remove(older);
    await server.addServerMetric(databaseA, created.metricId,
        deviceId: 'device-a');
    await server.pull(databaseB, deviceId: 'device-b');

    final outcome =
        await databaseB.select(databaseB.protocolTargetOutcomes).getSingle();
    expect(outcome.position, 7);
    expect(
        await databaseB.select(databaseB.deferredSyncChanges).get(), isEmpty);
  });

  test('a full re-sync drops a deferred outcome the server no longer has',
      () async {
    final created = await createProtocolTargetingOwnMetricOnA();
    await server.push(databaseA, deviceId: 'device-a');
    await server.pull(databaseB, deviceId: 'device-b');
    expect(await databaseB.select(databaseB.deferredSyncChanges).get(),
        hasLength(1));

    server.changes.removeWhere(
      (change) => change['entity'] == AppDatabase.protocolTargetOutcomesTable,
    );
    await server.pull(databaseB, deviceId: 'device-b', fullResync: true);
    expect(
        await databaseB.select(databaseB.deferredSyncChanges).get(), isEmpty);

    await server.addServerMetric(databaseA, created.metricId,
        deviceId: 'device-a');
    await server.pull(databaseB, deviceId: 'device-b');
    expect(await databaseB.select(databaseB.protocolTargetOutcomes).get(),
        isEmpty);
  });
}

/// Stores pushed rows opaquely, as the real server does, and hands every one
/// back on pull. No foreign keys are checked on the way through.
class _FakeSyncServer {
  final changes = <Map<String, Object?>>[];

  static final _session = AuthSession(
    provider: AuthSessionProvider.email,
    serverUrl: Uri.parse('https://sync.example/'),
    token: 'session-token',
    userEmail: 'user@example.com',
    userId: 'user-1',
    userName: 'Sync User',
  );

  Future<void> push(AppDatabase database, {required String deviceId}) async {
    final result = await _repository(database).pushPendingLoggedSets(
      session: _session,
      deviceId: deviceId,
    );
    expect(result.pushedCount, greaterThan(0));
    // The regular sync cycle pushes Metrics before outcomes. Remove the Metric
    // here to model a server response where that referenced row has not arrived.
    changes.removeWhere(
      (change) => change['entity'] == AppDatabase.metricsTable,
    );
  }

  Future<SyncPullResult> pull(
    AppDatabase database, {
    required String deviceId,
    bool fullResync = false,
  }) {
    return _repository(database, fullResync: fullResync).pullLoggedSetChanges(
      session: _session,
      deviceId: deviceId,
    );
  }

  /// Puts device A's own Metric on the server, standing in for the metrics
  /// push that does not exist yet.
  Future<void> addServerMetric(
    AppDatabase database,
    String metricId, {
    required String deviceId,
  }) async {
    final row = await (database.select(database.metrics)
          ..where((row) => row.id.equals(metricId)))
        .getSingle();
    changes.add(<String, Object?>{
      'entity': AppDatabase.metricsTable,
      'id': row.id,
      'deviceId': deviceId,
      'payload': <String, Object?>{
        'id': row.id,
        'name': row.name,
        'unit': row.unit,
        'value_shape': row.valueShape,
        'metric_group': row.metricGroup,
        'goal_type': row.goalType,
        'goal_target_value': row.goalTargetValue,
        'enabled': row.enabled,
        'pinned': row.pinned,
        'sort_order': row.sortOrder,
        'updated_at': row.updatedAt.toUtc().toIso8601String(),
        'deleted_at': null,
      },
      'updatedAt': row.updatedAt.toUtc().toIso8601String(),
      'deletedAt': null,
    });
  }

  SyncRepository _repository(AppDatabase database, {bool fullResync = false}) {
    return SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          if (request.url.path == '/sync/push') {
            final pushed = (body['changes']! as List<Object?>)
                .cast<Map<String, Object?>>();
            for (final change in pushed) {
              changes
                ..removeWhere(
                  (existing) =>
                      existing['entity'] == body['entity'] &&
                      existing['id'] == change['id'],
                )
                ..add(<String, Object?>{
                  ...change,
                  'entity': body['entity'],
                  'deviceId': body['deviceId'],
                });
            }
            return _json(<String, Object?>{
              'protocolVersion': 1,
              'accepted': pushed.map((change) => change['id']).toList(),
              'serverClock': '2026-06-03T08:00:00.000Z',
              'applied': <Object?>[
                for (final change in pushed)
                  <String, Object?>{
                    'id': change['id'],
                    'updatedAt': change['updatedAt'],
                    'deviceId': body['deviceId'],
                  },
              ],
            });
          }
          if (request.url.path == '/sync/pull') {
            final snapshot = body['mode'] == 'snapshot';
            if (fullResync && !snapshot) {
              return _json(<String, Object?>{
                'protocolVersion': 1,
                'fullResyncRequired': true,
                'nextCursor': null,
                'serverClock': '2026-06-03T08:00:00.000Z',
                'changes': <Object?>[],
              });
            }
            // A snapshot pages until it comes back empty.
            final cursor = body['cursor'];
            return _json(<String, Object?>{
              'protocolVersion': 1,
              'fullResyncRequired': false,
              'nextCursor': snapshot ? 'snapshot-done' : null,
              'serverClock': '2026-06-03T08:00:00.000Z',
              'changes': snapshot && cursor != null
                  ? <Object?>[]
                  : <Object?>[
                      for (final change in changes)
                        if (!snapshot || change['deletedAt'] == null) change,
                    ],
            });
          }
          fail('Unexpected sync request: ${request.url.path}');
        }),
      ),
    );
  }

  static http.Response _json(Map<String, Object?> body) {
    return http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
}
