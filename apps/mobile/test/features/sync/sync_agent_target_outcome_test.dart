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

/// An Agent writes Protocol target outcomes through the server, which stores
/// them as opaque sync payloads. Before
/// docs/designs/protocol-target-outcome-sync-shape.md the Agent stored
/// `outcome_kind` and no `position`, and the app's decoder threw a
/// `StateError` on it: the pull failed the whole page, every time, so one
/// such row stopped the device receiving anything else. These tests pull
/// Agent-written outcomes onto a device alongside the Protocol they belong to
/// and pin down that the page applies and the cursor moves.
void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  late AppDatabase databaseA;
  late AppDatabase databaseB;
  late _FakeSyncServer server;
  late String protocolId;
  late String metricId;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  setUp(() async {
    databaseA = AppDatabase.inMemory();
    databaseB = AppDatabase.inMemory();
    server = _FakeSyncServer();
    final repositoriesA = TrainingRepositories(databaseA);
    metricId = await repositoriesA.metrics.createMetric(
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
        startLocalDate: const ProtocolDayDate(year: 2026, month: 6, day: 1),
        compoundIds: <String>[compound.compoundId],
      ),
    );
    protocolId = protocol.protocolId;
    await server.push(databaseA, deviceId: 'device-a');
  });

  tearDown(() async {
    await databaseA.close();
    await databaseB.close();
  });

  Future<String?> pullCursorOnB() async {
    final state = await databaseB.select(databaseB.syncStates).getSingle();
    return state.pullCursor;
  }

  test('an outcome in the Agent shape applies with its kind and position',
      () async {
    server.addAgentOutcome(<String, Object?>{
      'id': _outcomeId,
      'protocol_id': protocolId,
      'kind': 'performance',
      'metric_id': null,
      'position': 2,
      'updated_at': _agentWroteAt,
      'deleted_at': null,
    });

    await server.pull(databaseB, deviceId: 'device-b');

    expect(await pullCursorOnB(), _FakeSyncServer.cursor);
    expect(await databaseB.select(databaseB.quarantinedSyncChanges).get(),
        isEmpty);
    final protocols =
        await TrainingRepositories(databaseB).protocols.listProtocols();
    expect(protocols.map((protocol) => protocol.id), <String>[protocolId]);
    final outcome = protocols.single.targetOutcomes.single;
    expect(outcome.id, _outcomeId);
    expect(outcome.kind, ProtocolOutcomeKind.performance);
    expect(outcome.metricId, isNull);
    expect(outcome.position, 2);
  });

  test(
      'an outcome an Agent stored before the fix (outcome_kind, no position) '
      'applies at position 0 and no longer stalls the pull', () async {
    // The shape prepareAgentProtocolBatchWrite stored before the fix.
    server.addAgentOutcome(<String, Object?>{
      'id': _outcomeId,
      'protocol_id': protocolId,
      'metric_id': null,
      'outcome_kind': 'performance',
      'updated_at': _agentWroteAt,
      'deleted_at': null,
    });

    // Before the fix this threw StateError('Activity image field kind must
    // be a string.') and rolled the Protocol on the same page back with it.
    await server.pull(databaseB, deviceId: 'device-b');

    expect(await pullCursorOnB(), _FakeSyncServer.cursor);
    expect(await databaseB.select(databaseB.quarantinedSyncChanges).get(),
        isEmpty);
    final stored =
        await databaseB.select(databaseB.protocolTargetOutcomes).getSingle();
    expect(stored.kind, 'performance');
    expect(stored.position, 0);
    final protocols =
        await TrainingRepositories(databaseB).protocols.listProtocols();
    expect(protocols.map((protocol) => protocol.id), <String>[protocolId]);
    expect(
      protocols.single.targetOutcomes.single.kind,
      ProtocolOutcomeKind.performance,
    );
  });

  test('an outcome with a kind outside the registry is quarantined', () async {
    server.addAgentOutcome(<String, Object?>{
      'id': _outcomeId,
      'protocol_id': protocolId,
      'kind': 'mood',
      'metric_id': null,
      'position': 0,
      'updated_at': _agentWroteAt,
      'deleted_at': null,
    });

    await server.pull(databaseB, deviceId: 'device-b');

    expect(await pullCursorOnB(), _FakeSyncServer.cursor);
    final held = await databaseB.select(databaseB.quarantinedSyncChanges).get();
    expect(held.map((row) => row.entityId), <String>[_outcomeId]);
    expect(held.single.failureKind, 'argument');
    expect(await databaseB.select(databaseB.protocolTargetOutcomes).get(),
        isEmpty);
    // The rest of the page applied, and the Protocols read still works.
    final protocols =
        await TrainingRepositories(databaseB).protocols.listProtocols();
    expect(protocols.map((protocol) => protocol.id), <String>[protocolId]);
    expect(protocols.single.targetOutcomes, isEmpty);
  });

  test('an outcome with no kind at all is quarantined', () async {
    server.addAgentOutcome(<String, Object?>{
      'id': _outcomeId,
      'protocol_id': protocolId,
      'metric_id': null,
      'position': 0,
      'updated_at': _agentWroteAt,
      'deleted_at': null,
    });

    await server.pull(databaseB, deviceId: 'device-b');

    expect(await pullCursorOnB(), _FakeSyncServer.cursor);
    final held = await databaseB.select(databaseB.quarantinedSyncChanges).get();
    expect(held.map((row) => row.entityId), <String>[_outcomeId]);
    expect(held.single.failureKind, 'format');
    expect(await databaseB.select(databaseB.protocols).get(), hasLength(1));
  });

  test(
      'a held outcome the app cannot read is quarantined when its Metric '
      'arrives, without failing that pull', () async {
    final metric = server.takeMetric(metricId);
    server.addAgentOutcome(<String, Object?>{
      'id': _outcomeId,
      'protocol_id': protocolId,
      'kind': 'mood',
      'metric_id': metricId,
      'position': 0,
      'updated_at': _agentWroteAt,
      'deleted_at': null,
    });

    await server.pull(databaseB, deviceId: 'device-b');
    final deferred =
        await databaseB.select(databaseB.deferredSyncChanges).get();
    expect(deferred.map((row) => row.entityId), <String>[_outcomeId]);

    server.changes.add(metric);
    await server.pull(databaseB, deviceId: 'device-b');

    expect(
        await databaseB.select(databaseB.deferredSyncChanges).get(), isEmpty);
    final held = await databaseB.select(databaseB.quarantinedSyncChanges).get();
    expect(held.map((row) => row.entityId), <String>[_outcomeId]);
    expect(held.single.failureKind, 'argument');
    expect(
      (jsonDecode(held.single.changeJson) as Map<String, Object?>)['id'],
      _outcomeId,
    );
    // The page that brought the Metric applied.
    expect(
      (await databaseB.select(databaseB.metrics).get()).map((row) => row.id),
      contains(metricId),
    );
    expect(await databaseB.select(databaseB.protocolTargetOutcomes).get(),
        isEmpty);
  });

  test('an Agent create stored before the fix can be undone on the device',
      () async {
    const batchId = 'agent-batch-1';
    final payload = <String, Object?>{
      'id': _outcomeId,
      'protocol_id': protocolId,
      'metric_id': null,
      'outcome_kind': 'performance',
      'updated_at': _agentWroteAt,
      'deleted_at': null,
    };
    server.addAgentOutcome(
      payload,
      activity: <String, Object?>{
        'activityLogId': 'agent:$batchId:outcome:$_outcomeId',
        'actor': 'agent',
        'batchId': batchId,
        'beforeImage': null,
        'afterImage': payload,
        'occurredAt': _agentWroteAt,
      },
    );
    await server.pull(databaseB, deviceId: 'device-b');

    final undo =
        await TrainingRepositories(databaseB).activityLog.undoBatch(batchId);

    // Before the fix the device's image (kind, position) never matched the
    // Agent's after-image (outcome_kind), so undo reported it stale.
    expect(undo.conflicts, isEmpty);
    expect(undo.appliedEntries.map((entry) => entry.entityId),
        <String>[_outcomeId]);
    final outcome =
        await databaseB.select(databaseB.protocolTargetOutcomes).getSingle();
    expect(outcome.deletedAt, isNotNull);
  });
}

const _outcomeId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c099';
const _agentWroteAt = '2026-06-03T07:00:00.000Z';

/// Stores pushed rows opaquely, as the real server does, and hands every one
/// back on every pull, as one page.
class _FakeSyncServer {
  static const cursor = 'cursor-1';

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
  }

  Future<SyncPullResult> pull(AppDatabase database,
      {required String deviceId}) {
    return _repository(database).pullLoggedSetChanges(
      session: _session,
      deviceId: deviceId,
    );
  }

  /// A target outcome the Agent batch write stored, as a pull returns it,
  /// with its Activity Log fields when [activity] is given.
  void addAgentOutcome(
    Map<String, Object?> payload, {
    Map<String, Object?> activity = const <String, Object?>{},
  }) {
    changes.add(<String, Object?>{
      'entity': AppDatabase.protocolTargetOutcomesTable,
      'id': payload['id'],
      'deviceId': 'agent-device',
      'payload': payload,
      'updatedAt': payload['updated_at'],
      'deletedAt': payload['deleted_at'],
      ...activity,
    });
  }

  /// Takes a pushed Metric off the server, as if its push had not landed
  /// yet, and returns it for adding back.
  Map<String, Object?> takeMetric(String metricId) {
    final metric = changes.singleWhere(
      (change) =>
          change['entity'] == AppDatabase.metricsTable &&
          change['id'] == metricId,
    );
    changes.remove(metric);
    return metric;
  }

  SyncRepository _repository(AppDatabase database) {
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
              changes.add(<String, Object?>{
                ...change,
                'entity': body['entity'],
                'deviceId': body['deviceId'],
              });
            }
            return _json(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
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
            return _json(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'fullResyncRequired': false,
              'nextCursor': cursor,
              'serverClock': '2026-06-03T08:00:00.000Z',
              'changes': changes,
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
