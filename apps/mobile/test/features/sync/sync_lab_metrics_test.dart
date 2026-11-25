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

/// A Lab Metric's `lab_test_key` travels in the Metric sync payload and is
/// write-once on the device (docs/designs/lab-results.md, Storage): a pull, an
/// undo or a restore never clears a stored key or moves it to another Lab
/// Test, and a null stored key takes the first key it is sent.
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

  Future<MetricRow> storedMetric(String id) {
    return (database.select(database.metrics)
          ..where((row) => row.id.equals(id)))
        .getSingle();
  }

  Future<String> createAndPush({String? labTestKey}) async {
    final id = await repositories.metrics.createMetric(
      _ferritinDraft(labTestKey: labTestKey),
    );
    await sync.pushPendingLoggedSets(session: _session, deviceId: 'device-a');
    server.pushes.clear();
    return id;
  }

  test('a created Lab Metric pushes its lab_test_key', () async {
    final id = await repositories.metrics.createMetric(
      _ferritinDraft(labTestKey: 'ferritin'),
    );

    await sync.pushPendingLoggedSets(session: _session, deviceId: 'device-a');

    final metricPush = server.pushes
        .singleWhere((push) => push.entity == AppDatabase.metricsTable);
    final change = metricPush.changes.singleWhere((c) => c['id'] == id);
    final payload = change['payload']! as Map<String, Object?>;
    expect(payload['lab_test_key'], 'ferritin');
    expect(await sync.hasPendingChanges(), isFalse);
  });

  for (final (label, keyEntry) in <(String, MapEntry<String, Object?>?)>[
    ('without the key', null),
    ('with a null key', const MapEntry<String, Object?>('lab_test_key', null)),
    (
      'with another key',
      const MapEntry<String, Object?>('lab_test_key', 'hemoglobin'),
    ),
  ]) {
    test('a pull $label keeps the stored key and applies the rest', () async {
      final id = await createAndPush(labTestKey: 'ferritin');

      server.pullChanges.add(
        _metricChange(
          id,
          name: 'Ferritin (renamed)',
          updatedAt: DateTime.utc(2030, 1, 2),
          keyEntry: keyEntry,
        ),
      );
      await sync.pullLoggedSetChanges(session: _session, deviceId: 'device-a');

      final metric = await storedMetric(id);
      expect(metric.name, 'Ferritin (renamed)');
      expect(metric.labTestKey, 'ferritin');
    });
  }

  test('a pull with a key fills a null stored key', () async {
    final id = await createAndPush();
    expect((await storedMetric(id)).labTestKey, isNull);

    server.pullChanges.add(
      _metricChange(
        id,
        name: 'Ferritin',
        updatedAt: DateTime.utc(2030, 1, 2),
        keyEntry: const MapEntry<String, Object?>('lab_test_key', 'ferritin'),
      ),
    );
    await sync.pullLoggedSetChanges(session: _session, deviceId: 'device-a');

    expect((await storedMetric(id)).labTestKey, 'ferritin');
  });

  test('a pulled new Lab Metric is stored with its key', () async {
    server.pullChanges.add(
      _metricChange(
        'metric-server-ferritin',
        name: 'Ferritin',
        updatedAt: DateTime.utc(2030, 1, 2),
        keyEntry: const MapEntry<String, Object?>('lab_test_key', 'ferritin'),
      ),
    );
    await sync.pullLoggedSetChanges(session: _session, deviceId: 'device-a');

    expect(
      (await storedMetric('metric-server-ferritin')).labTestKey,
      'ferritin',
    );
  });

  test('undo of a later edit restores the edit but never clears the key',
      () async {
    final id = await createAndPush(labTestKey: 'ferritin');
    final createdImage = <String, Object?>{
      ..._metricPayload(
        id,
        name: 'Ferritin',
        updatedAt: DateTime.utc(2026, 6, 1),
      ),
      'lab_test_key': null,
    };

    // Another device's edit, sent and logged with a null key, as a stray
    // null from another writer would be.
    final editUpdatedAt = DateTime.utc(2030, 1, 2);
    final change = _metricChange(
      id,
      name: 'Ferritin (renamed)',
      updatedAt: editUpdatedAt,
      keyEntry: const MapEntry<String, Object?>('lab_test_key', null),
    );
    server.pullChanges.add(
      <String, Object?>{
        ...change,
        'activityLogId': 'activity-edit',
        'actor': 'app',
        'batchId': 'batch-edit',
        'beforeImage': createdImage,
        'afterImage': <String, Object?>{
          ...(change['payload']! as Map<String, Object?>),
          'lab_test_key': 'ferritin',
        },
        'occurredAt': editUpdatedAt.toIso8601String(),
      },
    );
    await sync.pullLoggedSetChanges(session: _session, deviceId: 'device-a');
    expect((await storedMetric(id)).name, 'Ferritin (renamed)');

    final result = await repositories.activityLog.undoBatch('batch-edit');

    expect(result.conflicts, isEmpty);
    final metric = await storedMetric(id);
    expect(metric.name, 'Ferritin');
    expect(metric.labTestKey, 'ferritin');
  });
}

final _session = AuthSession(
  provider: AuthSessionProvider.email,
  serverUrl: Uri.parse('https://sync.example/'),
  token: 'session-token',
  userEmail: 'user@example.com',
  userId: 'user-1',
  userName: 'Sync User',
);

MetricDraft _ferritinDraft({String? labTestKey}) {
  return MetricDraft(
    name: 'Ferritin',
    unit: 'ng/mL',
    valueShape: MetricValueShape.scalar,
    group: MetricGroup.custom,
    enabled: true,
    pinned: false,
    labTestKey: labTestKey,
  );
}

/// A Metric payload without `lab_test_key`, as a server before schema 68
/// sends it.
Map<String, Object?> _metricPayload(
  String id, {
  required String name,
  required DateTime updatedAt,
}) {
  return <String, Object?>{
    'id': id,
    'name': name,
    'unit': 'ng/mL',
    'value_shape': MetricValueShape.scalar.name,
    'metric_group': MetricGroup.custom.name,
    'goal_type': null,
    'goal_target_value': null,
    'enabled': true,
    'pinned': false,
    'sort_order': 0,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': null,
  };
}

Map<String, Object?> _metricChange(
  String id, {
  required String name,
  required DateTime updatedAt,
  MapEntry<String, Object?>? keyEntry,
}) {
  return <String, Object?>{
    'entity': AppDatabase.metricsTable,
    'id': id,
    'deviceId': 'device-other',
    'payload': <String, Object?>{
      ..._metricPayload(id, name: name, updatedAt: updatedAt),
      if (keyEntry != null) keyEntry.key: keyEntry.value,
    },
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': null,
  };
}

class _Push {
  const _Push(this.entity, this.changes);

  final String entity;
  final List<Map<String, Object?>> changes;
}

/// Accepts every pushed change and serves [pullChanges] once.
class _FakeSyncServer {
  final pushes = <_Push>[];
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
        'serverClock': '2030-01-03T08:00:00.000Z',
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
      'merged': const <Map<String, Object?>>[],
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
