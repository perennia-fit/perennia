import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart'
    show BooleanExpressionOperators, OrderingTerm, Value, driftRuntimeOptions;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:perennia/api/perennia_api_client.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/platform_exercise_seed.dart';
import 'package:perennia/domain/settings/account_settings.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/activity/repositories/activity_feed_repository.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';
import 'package:perennia/features/sync/models/sync_status.dart';
import 'package:perennia/features/sync/repositories/sync_repository.dart';
import 'package:perennia/features/sync/services/sync_cycle_runner.dart';

void main() {
  // Erase loads the bundled Platform Library seed from assets.
  TestWidgetsFlutterBinding.ensureInitialized();

  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  late AppDatabase database;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  setUp(() {
    database = AppDatabase.inMemory();
  });

  tearDown(() async {
    await database.close();
  });

  // docs/designs/compound-purposes.md, D1 to D3 and CUJ 6.
  group('Compound Purposes sync', () {
    test('a seeded device pushes its Purposes before its Compounds', () async {
      final repositories = TrainingRepositories(database);
      await repositories.protocols.ensureOtcLibrarySeeded();
      final pushes = <Map<String, Object?>>[];
      final repository = SyncRepository(
        database: database,
        apiClientFactory: _acceptingSyncApi(pushes: pushes),
      );

      final result = await repository.pushPendingLoggedSets(
        session: _session(),
        deviceId: 'device-a',
      );

      final entities = pushes.map((body) => body['entity']).toList();
      expect(
        entities.indexOf(AppDatabase.purposesTable),
        lessThan(entities.indexOf(AppDatabase.compoundsTable)),
      );
      final purposes = pushes
          .firstWhere((body) => body['entity'] == AppDatabase.purposesTable);
      final pushed =
          (purposes['changes']! as List<Object?>).cast<Map<String, Object?>>();
      expect(pushed, hasLength(starterPurposes.length));
      expect(
        (pushed.first['payload']! as Map<String, Object?>).keys,
        unorderedEquals(<String>[
          'id',
          'name',
          'sort_order',
          'updated_at',
          'deleted_at',
        ]),
      );
      expect(result.pushedCount, 12);
      final synced = await _purposeRow(database, _cognitionId);
      expect(synced.syncPreviouslySynced, isTrue);
      expect(synced.syncDeviceId, 'device-a');
      expect(await repository.hasPendingChanges(), isFalse);
    });

    test('a full resync pushes Purposes before Compounds too', () async {
      final repositories = TrainingRepositories(database);
      await repositories.protocols.ensureOtcLibrarySeeded();
      final entities = <Object?>[];
      final repository = SyncRepository(
        database: database,
        apiClientFactory: (baseUrl) => PerenniaApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, Object?>;
            if (request.url.path == '/sync/push') {
              entities.add(body['entity']);
              final changes = (body['changes']! as List<Object?>)
                  .cast<Map<String, Object?>>();
              return http.Response(
                jsonEncode(<String, Object?>{
                  'protocolVersion': syncProtocolVersion,
                  'accepted': changes
                      .map((change) => change['id']! as String)
                      .toList(growable: false),
                  'serverClock': '2026-11-01T00:00:01.000Z',
                  'applied': const <Object?>[],
                }),
                200,
                headers: const {'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': syncProtocolVersion,
                'fullResyncRequired': body['mode'] != 'snapshot',
                'nextCursor': 'snapshot-cursor',
                'serverClock': '2026-11-01T00:00:02.000Z',
                'changes': const <Object?>[],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        ),
      );

      final result = await repository.pullLoggedSetChanges(
        session: _session(),
        deviceId: 'device-a',
      );

      expect(result.fullResyncRequired, isTrue);
      expect(
        entities.indexOf(AppDatabase.purposesTable),
        lessThan(entities.indexOf(AppDatabase.compoundsTable)),
      );
    });

    test('a pull applies a Purpose, with its Activity Log entry', () async {
      final updatedAt = DateTime.utc(2026, 11, 1, 8).toIso8601String();
      await _pullChangeInto(
        database,
        localDeviceId: 'device-b',
        change: _purposePullChange(
          id: 'purpose-user-1',
          name: 'Joints',
          sortOrder: 6,
          updatedAt: updatedAt,
          deviceId: 'device-a',
        ),
      );

      final row = await _purposeRow(database, 'purpose-user-1');
      expect(row.name, 'Joints');
      expect(row.sortOrder, 6);
      expect(row.syncDeviceId, 'device-a');
      expect(row.syncPreviouslySynced, isTrue);
      final log = await (database.select(database.activityLog)
            ..where((entry) => entry.entityId.equals('purpose-user-1')))
          .getSingle();
      expect(log.entityTable, AppDatabase.purposesTable);
      expect(log.actor, 'manual');
    });

    test('an older Purpose from a pull loses to the local rename', () async {
      final repositories = TrainingRepositories(database);
      await repositories.protocols.ensureOtcLibrarySeeded();
      await repositories.protocols.purposes
          .rename(_cognitionId, name: 'Memory');

      await _pullChangeInto(
        database,
        localDeviceId: 'device-b',
        change: _purposePullChange(
          id: _cognitionId,
          name: 'Cognition',
          sortOrder: 4,
          updatedAt: compoundSeedTimestamp.toIso8601String(),
          deviceId: 'device-a',
          actor: 'otc_seed',
        ),
      );

      expect((await _purposeRow(database, _cognitionId)).name, 'Memory');
    });

    test('a Compound payload with no purpose_ids keeps the local list',
        () async {
      final repositories = TrainingRepositories(database);
      await repositories.protocols.ensureOtcLibrarySeeded();
      final before = await _compoundRow(database, _creatineId);
      expect(before.purposeIds, jsonEncode(<String>[_performanceId]));

      await _pullChangeInto(
        database,
        localDeviceId: 'device-b',
        change: _compoundPullChange(
          before,
          updatedAt: DateTime.utc(2026, 11, 1, 8).toIso8601String(),
          deviceId: 'device-a',
          actor: 'manual',
          changes: const <String, Object?>{
            'name': 'Creatine monohydrate',
            'purpose_ids': _absent,
          },
        ),
      );

      final after = await _compoundRow(database, _creatineId);
      expect(after.name, 'Creatine monohydrate');
      expect(after.purposeIds, before.purposeIds);
    });

    test('a new Compound whose payload has no purpose_ids starts with none',
        () async {
      // An Agent-created Compound with no `purposeIds` has no such key.
      final repositories = TrainingRepositories(database);
      await repositories.protocols.ensureOtcLibrarySeeded();
      final row = await _compoundRow(database, _creatineId);
      await database.customStatement(
        'DELETE FROM compounds WHERE id = ?',
        <Object?>[_creatineId],
      );

      await _pullChangeInto(
        database,
        localDeviceId: 'device-b',
        change: _compoundPullChange(
          row,
          updatedAt: DateTime.utc(2026, 11, 1, 8).toIso8601String(),
          deviceId: 'device-a',
          actor: 'agent',
          changes: const <String, Object?>{'purpose_ids': _absent},
        ),
      );

      expect((await _compoundRow(database, _creatineId)).purposeIds, '[]');
    });

    test('a Compound payload with an explicit empty list clears the local one',
        () async {
      final repositories = TrainingRepositories(database);
      await repositories.protocols.ensureOtcLibrarySeeded();
      final before = await _compoundRow(database, _creatineId);

      await _pullChangeInto(
        database,
        localDeviceId: 'device-b',
        change: _compoundPullChange(
          before,
          updatedAt: DateTime.utc(2026, 11, 1, 8).toIso8601String(),
          deviceId: 'device-a',
          actor: 'manual',
          changes: const <String, Object?>{'purpose_ids': '[]'},
        ),
      );

      expect((await _compoundRow(database, _creatineId)).purposeIds, '[]');
    });

    test(
        "a full pull of this device's own unchanged seed rows doesn't touch "
        'them, so the backfill still tags them', () async {
      final repositories = TrainingRepositories(database);
      await _seedAsSyncedUpgradedDevice(
        repositories,
        database,
        deviceId: 'device-a',
      );
      final rowsBefore = await database.select(database.compounds).get();
      final logBefore = await database.select(database.activityLog).get();
      expect(rowsBefore, isNotEmpty);
      final pushes = <Map<String, Object?>>[];
      final repository = SyncRepository(
        database: database,
        trainingRepositories: repositories,
        apiClientFactory: _acceptingSyncApi(
          pushes: pushes,
          pullChanges: <Map<String, Object?>>[
            for (final row in rowsBefore)
              _compoundPullChange(
                row,
                updatedAt: row.updatedAt.toUtc().toIso8601String(),
                deviceId: 'device-a',
                actor: 'otc_seed',
                changes: const <String, Object?>{'purpose_ids': _absent},
              ),
          ],
        ),
      );

      final pull = await repository.pullLoggedSetChanges(
        session: _session(),
        deviceId: 'device-a',
      );

      // A last-writer-wins tie against this device's own write: nothing moves,
      // and the row gets no entry that would make it read as touched.
      expect(pull.appliedCount, 0);
      expect(await database.select(database.compounds).get(), rowsBefore);
      expect(await database.select(database.activityLog).get(), logBefore);

      await repository.backfillSeedPurposes();

      final tagged = await _compoundRow(database, _creatineId);
      expect(tagged.purposeIds, jsonEncode(<String>[_performanceId]));
      final entries = await (database.select(database.activityLog)
            ..where((entry) => entry.entityId.equals(_creatineId)))
          .get();
      expect(
        entries.map((entry) => entry.actor),
        unorderedEquals(<String>['otc_seed', 'otc_purpose_seed']),
      );
    });

    test('a Sync Run with nothing else to do pushes the backfill it wrote',
        () async {
      final repositories = TrainingRepositories(database);
      await _seedAsSyncedUpgradedDevice(
        repositories,
        database,
        deviceId: 'device-a',
      );
      final pushes = <Map<String, Object?>>[];
      final repository = SyncRepository(
        database: database,
        trainingRepositories: repositories,
        apiClientFactory: _acceptingSyncApi(pushes: pushes),
      );
      expect(await repository.hasPendingChanges(), isFalse);

      final result = await RepositorySyncCycleRunner(
        repository: repository,
        statusRepository: SyncStatusRepository(database),
      ).run(session: _session(), deviceId: 'device-a');

      expect(result.pushedCount, seedCompoundPurposeIds.length);
      final pushedCompounds = pushes
          .where((body) => body['entity'] == AppDatabase.compoundsTable)
          .expand((body) => body['changes']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .toList();
      final creatine =
          pushedCompounds.singleWhere((change) => change['id'] == _creatineId);
      expect(
        (creatine['payload']! as Map<String, Object?>)['purpose_ids'],
        jsonEncode(<String>[_performanceId]),
      );
      expect(creatine['actor'], 'otc_purpose_seed');
      expect(await repository.hasPendingChanges(), isFalse);
    });

    test(
        'a full pull restores the tags an older build dropped from a row it '
        'applied, and the next edit pushes them', () async {
      // One account, upgraded a device at a time. Device A's backfill reached
      // device B while B was still on the older build, which stored the version
      // but had no column for the tags.
      final repositories = TrainingRepositories(database);
      await _seedAsSyncedUpgradedDevice(
        repositories,
        database,
        deviceId: 'device-b',
      );
      final seeded = await _compoundRow(database, _creatineId);
      final taggedAt = DateTime.utc(2026, 11, 1, 8);
      final tags = jsonEncode(<String>[_performanceId]);
      Map<String, Object?> backfill(Object? purposeIds) => _compoundPullChange(
            seeded,
            updatedAt: taggedAt.toIso8601String(),
            deviceId: 'device-a',
            actor: 'otc_purpose_seed',
            changes: <String, Object?>{'purpose_ids': purposeIds},
          );
      await _pullChangeInto(
        database,
        localDeviceId: 'device-b',
        change: backfill(_absent),
      );
      final dropped = await _compoundRow(database, _creatineId);
      expect(dropped.purposeIds, '[]');
      expect(dropped.syncDeviceId, 'device-a');
      expect(dropped.updatedAt.isAtSameMomentAs(taggedAt), isTrue);

      Future<List<ActivityLogRow>> creatineLog() =>
          (database.select(database.activityLog)
                ..where((entry) => entry.entityId.equals(_creatineId)))
              .get();
      final logBefore = await creatineLog();

      // B upgrades: the `from < 66` step clears the cursor, so the first Sync
      // Run pulls in full.
      await database.customStatement(
        'UPDATE sync_states SET pull_cursor = NULL',
      );
      final pushes = <Map<String, Object?>>[];
      final repository = SyncRepository(
        database: database,
        trainingRepositories: repositories,
        apiClientFactory: _acceptingSyncApi(
          pushes: pushes,
          pullChanges: <Map<String, Object?>>[backfill(tags)],
        ),
      );
      final runner = RepositorySyncCycleRunner(
        repository: repository,
        statusRepository: SyncStatusRepository(database),
      );
      List<Map<String, Object?>> pushedCreatine() => pushes
          .where((body) => body['entity'] == AppDatabase.compoundsTable)
          .expand((body) => body['changes']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .where((change) => change['id'] == _creatineId)
          .toList();

      await runner.run(session: _session(), deviceId: 'device-b');

      // Only the tags moved: the version stands, nothing new is logged or
      // pushed, and the backfill has nothing left to do for this row.
      final restored = await _compoundRow(database, _creatineId);
      expect(restored.purposeIds, tags);
      expect(restored.syncDeviceId, 'device-a');
      expect(restored.updatedAt.isAtSameMomentAs(taggedAt), isTrue);
      expect(await creatineLog(), logBefore);
      expect(pushedCreatine(), isEmpty);

      await repositories.protocols.setFavorite(_creatineId, isFavorite: true);
      await runner.run(session: _session(), deviceId: 'device-b');

      final pushed = pushedCreatine().single;
      expect(
        (pushed['payload']! as Map<String, Object?>)['purpose_ids'],
        tags,
      );
    });

    group('a pull that loses last-writer-wins restores no tags', () {
      final localAt = DateTime.utc(2026, 11, 1, 8);
      final tags = jsonEncode(<String>[_performanceId]);

      Future<CompoundRow> pullAgainst({
        required String localPurposeIds,
        required DateTime incomingAt,
        required String incomingDeviceId,
      }) async {
        final repositories = TrainingRepositories(database);
        await _seedAsSyncedUpgradedDevice(
          repositories,
          database,
          deviceId: 'device-b',
        );
        await (database.update(database.compounds)
              ..where((row) => row.id.equals(_creatineId)))
            .write(
          CompoundsCompanion(
            purposeIds: Value<String>(localPurposeIds),
            updatedAt: Value<DateTime>(localAt),
          ),
        );
        final local = await _compoundRow(database, _creatineId);
        await _pullChangeInto(
          database,
          localDeviceId: 'device-b',
          change: _compoundPullChange(
            local,
            updatedAt: incomingAt.toIso8601String(),
            deviceId: incomingDeviceId,
            actor: 'manual',
            changes: <String, Object?>{'purpose_ids': tags},
          ),
        );
        return _compoundRow(database, _creatineId);
      }

      test('an older version', () async {
        final row = await pullAgainst(
          localPurposeIds: '[]',
          incomingAt: localAt.subtract(const Duration(hours: 1)),
          incomingDeviceId: 'device-a',
        );
        expect(row.purposeIds, '[]');
      });

      test('the same stamp from another device', () async {
        final row = await pullAgainst(
          localPurposeIds: '[]',
          incomingAt: localAt,
          incomingDeviceId: 'device-a',
        );
        expect(row.purposeIds, '[]');
      });

      test('the same version over a row that holds a list', () async {
        final other = jsonEncode(<String>[_cognitionId]);
        final row = await pullAgainst(
          localPurposeIds: other,
          incomingAt: localAt,
          incomingDeviceId: 'device-b',
        );
        expect(row.purposeIds, other);
      });
    });

    for (final upgraded in <bool>[false, true]) {
      test(
          'CUJ 6: a removed seed tag stays removed on a '
          "${upgraded ? 'device upgrading from 65' : 'fresh device'}",
          () async {
        final repositories = TrainingRepositories(database);
        if (upgraded) {
          await _seedAsSyncedUpgradedDevice(
            repositories,
            database,
            deviceId: 'device-b',
          );
        } else {
          await repositories.protocols.ensureOtcLibrarySeeded();
        }
        final local = await _compoundRow(database, _creatineId);
        final editedAt = DateTime.utc(2026, 11, 1, 8).toIso8601String();
        final repository = SyncRepository(
          database: database,
          trainingRepositories: repositories,
          // The server holds device A's newer rows, so it applies nothing
          // pushed by this device.
          apiClientFactory: _acceptingSyncApi(
            pushes: <Map<String, Object?>>[],
            applyPushes: false,
            pullChanges: <Map<String, Object?>>[
              _purposePullChange(
                id: _cognitionId,
                name: 'Memory',
                sortOrder: 4,
                updatedAt: editedAt,
                deviceId: 'device-a',
              ),
              _compoundPullChange(
                local,
                updatedAt: editedAt,
                deviceId: 'device-a',
                actor: 'manual',
                changes: const <String, Object?>{'purpose_ids': '[]'},
              ),
            ],
          ),
        );

        await RepositorySyncCycleRunner(
          repository: repository,
          statusRepository: SyncStatusRepository(database),
        ).run(session: _session(), deviceId: 'device-b');

        expect((await _compoundRow(database, _creatineId)).purposeIds, '[]');
        final purposes = await repositories.protocols.purposes.listActive();
        expect(purposes.map((purpose) => purpose.name), contains('Memory'));
        expect(
          purposes.map((purpose) => purpose.name),
          isNot(contains('Cognition')),
        );
      });
    }

    group('a device that backfilled with no account, then signs in', () {
      // Before any edit below, as a schema-65 device stamped its seed.
      final seededAt =
          DateTime.now().toUtc().subtract(const Duration(days: 30));

      Future<TrainingRepositories> backfilledSignedOut() async {
        final repositories = TrainingRepositories(database);
        await _seedAsNeverSyncedUpgradedDevice(
          repositories,
          database,
          seededAt: seededAt,
        );
        await repositories.protocols.backfillSeedPurposes(
          onlyNeverSynced: true,
        );
        return repositories;
      }

      test(
          "CUJ 6: loses to another device's removal and rename, on both "
          'devices', () async {
        final repositories = await backfilledSignedOut();
        final local = await _compoundRow(database, _creatineId);
        expect(local.purposeIds, jsonEncode(<String>[_performanceId]));
        final editedAt = DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 1))
            .toIso8601String();
        final server = <String, Map<String, Object?>>{
          _creatineId: _compoundPullChange(
            local,
            updatedAt: editedAt,
            deviceId: 'device-a',
            actor: 'manual',
            changes: const <String, Object?>{
              'name': 'Creatine monohydrate',
              'purpose_ids': '[]',
            },
          ),
        };
        final repository = SyncRepository(
          database: database,
          trainingRepositories: repositories,
          apiClientFactory: _lwwCompoundServer(
            server,
            otherPullChanges: <Map<String, Object?>>[
              _purposePullChange(
                id: _cognitionId,
                name: 'Memory',
                sortOrder: 4,
                updatedAt: editedAt,
                deviceId: 'device-a',
              ),
            ],
          ),
        );

        await RepositorySyncCycleRunner(
          repository: repository,
          statusRepository: SyncStatusRepository(database),
        ).run(session: _session(), deviceId: 'device-b');

        // Device A's next pull reads this row, so its edit stands there too.
        final held = server[_creatineId]!;
        expect(held['deviceId'], 'device-a');
        expect(held['updatedAt'], editedAt);
        final payload = held['payload']! as Map<String, Object?>;
        expect(payload['purpose_ids'], '[]');
        expect(payload['name'], 'Creatine monohydrate');

        final after = await _compoundRow(database, _creatineId);
        expect(after.purposeIds, '[]');
        expect(after.name, 'Creatine monohydrate');
        expect(after.syncDeviceId, 'device-a');
        final purposes = await repositories.protocols.purposes.listActive();
        expect(purposes.map((purpose) => purpose.name), contains('Memory'));
      });

      test('an account with no edit to the row still receives the tags',
          () async {
        final repositories = await backfilledSignedOut();
        final server = <String, Map<String, Object?>>{};
        final repository = SyncRepository(
          database: database,
          trainingRepositories: repositories,
          apiClientFactory: _lwwCompoundServer(server),
        );

        await RepositorySyncCycleRunner(
          repository: repository,
          statusRepository: SyncStatusRepository(database),
        ).run(session: _session(), deviceId: 'device-b');

        expect(server.keys, unorderedEquals(seedCompoundPurposeIds.keys));
        final held = server[_creatineId]!['payload']! as Map<String, Object?>;
        expect(held['purpose_ids'], jsonEncode(<String>[_performanceId]));
        final after = await _compoundRow(database, _creatineId);
        expect(after.purposeIds, jsonEncode(<String>[_performanceId]));
        expect(after.syncDeviceId, 'device-b');
      });

      test('the tags go up one second after the seed entry they amend',
          () async {
        // The server drops a tie on (stamp, device), so a stamp left unchanged
        // would lose to this device's pending `otc_seed` entry.
        final repositories = await backfilledSignedOut();
        final pushes = <Map<String, Object?>>[];
        final repository = SyncRepository(
          database: database,
          trainingRepositories: repositories,
          apiClientFactory: _acceptingSyncApi(pushes: pushes),
        );

        await RepositorySyncCycleRunner(
          repository: repository,
          statusRepository: SyncStatusRepository(database),
        ).run(session: _session(), deviceId: 'device-b');

        final creatine = pushes
            .where((body) => body['entity'] == AppDatabase.compoundsTable)
            .expand((body) => body['changes']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .where((change) => change['id'] == _creatineId)
            .toList();
        expect(
          creatine.map((change) => change['actor']),
          <String>['otc_seed', 'otc_purpose_seed'],
        );
        final seed = DateTime.parse(creatine.first['updatedAt']! as String);
        final tags = DateTime.parse(creatine.last['updatedAt']! as String);
        expect(tags.difference(seed), const Duration(seconds: 1));
      });
    });

    test('a snapshot leaves never-synced seeded Purposes alone', () async {
      final repositories = TrainingRepositories(database);
      await repositories.protocols.ensureOtcLibrarySeeded();
      // Nothing to push first, so the rows reach the snapshot never synced.
      await database.customStatement(
        'UPDATE activity_log SET sync_acknowledged_at = 1000',
      );
      final before = await database.select(database.purposes).get();
      final repository = _snapshotRepository(database, const <Object?>[]);

      await repository.pullLoggedSetChanges(
        session: _session(),
        deviceId: 'device-a',
      );

      expect(await database.select(database.purposes).get(), before);
    });

    test(
        'a snapshot tombstones a synced Purpose it no longer holds, and keeps '
        'one it does', () async {
      final repositories = TrainingRepositories(database);
      await repositories.protocols.ensureOtcLibrarySeeded();
      await database.customStatement(
        "UPDATE purposes SET sync_device_id = 'device-a', "
        'sync_previously_synced = 1',
      );
      await database.customStatement(
        'UPDATE activity_log SET sync_acknowledged_at = 1000',
      );
      final stamp = compoundSeedTimestamp.toIso8601String();
      final repository = _snapshotRepository(database, <Object?>[
        for (final starter in starterPurposes)
          if (starter.id != _cognitionId)
            _purposePullChange(
              id: starter.id,
              name: starter.name,
              sortOrder: starter.sortOrder,
              updatedAt: stamp,
              deviceId: 'device-a',
              actor: 'otc_seed',
            ),
      ]);

      await repository.pullLoggedSetChanges(
        session: _session(),
        deviceId: 'device-a',
      );

      expect((await _purposeRow(database, _cognitionId)).deletedAt, isNotNull);
      expect((await _purposeRow(database, _performanceId)).deletedAt, isNull);
    });
  });

  test('pending-change watch ignores local-only Activity Log entities',
      () async {
    final updatedAt = DateTime.utc(2026, 7, 28, 10);
    await database.into(database.activityLog).insert(
          ActivityLogCompanion.insert(
            id: 'rest-timer-activity',
            actor: 'app',
            batchId: 'rest-timer-batch',
            entityTable: AppDatabase.restTimersTable,
            entityId: 'rest-timer-1',
            beforeImage: const Value<String?>(null),
            afterImage: const Value<String?>('{}'),
            occurredAt: updatedAt,
            updatedAt: updatedAt,
          ),
        );
    final repository = SyncRepository(database: database);
    final counts = StreamIterator(repository.watchPendingChangeCount());
    addTearDown(counts.cancel);

    expect(await counts.moveNext(), isTrue);
    expect(counts.current, 0);

    await _insertActivityLogEntry(
      database,
      id: 'logged-set-activity',
      entityId: 'logged-set-1',
      updatedAt: updatedAt,
    );

    expect(await counts.moveNext(), isTrue);
    expect(counts.current, 1);
  });

  test('registers the signed-in device push token through the sync API',
      () async {
    final requests = <http.Request>[];
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(<String, Object?>{'registered': true}),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final result = await repository.registerDevicePushToken(
      session: _session(),
      deviceId: 'device-a',
      platform: 'android',
      token: 'fcm-token-1',
    );

    expect(result.registered, isTrue);
    expect(requests.single.method, 'POST');
    expect(
      requests.single.url.toString(),
      'https://sync.example/sync/device-push-token',
    );
    expect(requests.single.headers['authorization'], 'Bearer session-token');
    expect(jsonDecode(requests.single.body), <String, Object?>{
      'deviceId': 'device-a',
      'platform': 'android',
      'token': 'fcm-token-1',
    });
  });

  test('pushes unacknowledged logged set changes and acknowledges on success',
      () async {
    final updatedAt = DateTime.utc(2026, 6, 22, 8);
    const setId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c001';
    await _insertActivityLogEntry(
      database,
      id: 'activity-1',
      entityId: setId,
      updatedAt: updatedAt,
    );
    final requests = <http.Request>[];
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'accepted': <String>[setId],
              'serverClock': '2026-06-22T08:00:01.000Z',
              'applied': <Object?>[
                <String, Object?>{
                  'id': setId,
                  'updatedAt': updatedAt.toIso8601String(),
                  'deviceId': 'device-a',
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final result = await repository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );

    expect(result.pushedCount, 1);
    expect(result.acknowledgedActivityLogIds, <String>['activity-1']);
    expect(result.serverClock, '2026-06-22T08:00:01.000Z');
    expect(requests.single.method, 'POST');
    expect(requests.single.url.toString(), 'https://sync.example/sync/push');
    expect(requests.single.headers['authorization'], 'Bearer session-token');
    expect(jsonDecode(requests.single.body), <String, Object?>{
      'protocolVersion': syncProtocolVersion,
      'deviceId': 'device-a',
      'entity': AppDatabase.loggedSetsTable,
      'changes': <Object?>[
        <String, Object?>{
          'id': setId,
          'payload': <String, Object?>{
            'id': setId,
            'workout_id': 'workout-1',
            'exercise_id': 'exercise-1',
            'position': 0,
            'is_completed': false,
            'updated_at': updatedAt.toIso8601String(),
            'deleted_at': null,
          },
          'updatedAt': updatedAt.toIso8601String(),
          'deletedAt': null,
          'activityLogId': 'activity-1',
          'actor': 'app',
          'batchId': 'batch-1',
          'beforeImage': null,
          'afterImage': <String, Object?>{
            'id': setId,
            'workout_id': 'workout-1',
            'exercise_id': 'exercise-1',
            'position': 0,
            'is_completed': false,
            'updated_at': updatedAt.toIso8601String(),
            'deleted_at': null,
          },
          'occurredAt': updatedAt.toIso8601String(),
        },
      ],
    });
    final entry = await _activityLogEntry(database, 'activity-1');
    final status = await SyncStatusRepository(database).loadStatus(
      observedAt: DateTime.utc(2026, 6, 22, 8, 1),
    );

    expect(entry.syncAcknowledgedAt != null, true);
    expect(status.kind, SyncStatusKind.synced);
    expect(
      status.lastSuccessfulSyncAt,
      DateTime.parse('2026-06-22T08:00:01.000Z').toUtc(),
    );
  });

  test(
      'syncs Open Food Facts Food Entry snapshots without redistributing cache rows',
      () async {
    final updatedAt = DateTime.utc(2026, 6, 27, 8);
    final repositories = TrainingRepositories(database);
    final mealId = await repositories.nutrition.createMeal(
      PendingMeal(
        id: repositories.nutrition.newMealId(),
        startedAt: updatedAt,
        mealTypeName: 'Snack',
      ),
      actor: 'tester',
    );
    final result = await repositories.nutrition.logFoodEntrySnapshot(
      target: ExistingMealTarget(mealId),
      entry: FoodEntrySnapshotDraft(
        mealId: mealId,
        foodId: '3017620422003',
        name: 'Original branded bar',
        foodSource: FoodSource.openFoodFacts,
        nutrientsPer100: _offNutrientsPer100(),
        isLiquid: false,
        servingLabel: 'serving',
        servingSize: 45,
        packageSize: 60,
        portion: Portion(
          value: 1,
          entered: '1',
          unit: PortionUnit.serving,
        ),
      ),
      actor: 'tester',
    );
    final pushRequests = <http.Request>[];
    final pushRepository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          pushRequests.add(request);
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final changes = body['changes']! as List<Object?>;
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'accepted': changes
                  .map((change) =>
                      (change! as Map<String, Object?>)['id']! as String)
                  .toList(growable: false),
              'serverClock': '2026-06-27T08:00:01.000Z',
              'applied': changes.map((change) {
                final changeJson = change! as Map<String, Object?>;
                return <String, Object?>{
                  'id': changeJson['id'],
                  'updatedAt': changeJson['updatedAt'],
                  'deviceId': 'device-a',
                };
              }).toList(growable: false),
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final pushResult = await pushRepository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );
    final pushedBodies = pushRequests
        .map((request) => jsonDecode(request.body) as Map<String, Object?>)
        .toList(growable: false);
    final pushedChanges = pushedBodies
        .expand((body) => body['changes']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .toList(growable: false);
    final pushedFoodEntry = pushedChanges
        .singleWhere((change) => change['id'] == result.foodEntryId);
    final foodPayload = pushedFoodEntry['payload']! as Map<String, Object?>;

    expect(pushResult.pushedCount, 2);
    expect(
      pushedBodies.map((body) => body['entity']),
      <String>[AppDatabase.mealsTable, AppDatabase.foodEntriesTable],
    );
    expect(foodPayload['food_source'], FoodSource.openFoodFacts.name);
    expect(foodPayload['food_id'], '3017620422003');
    expect(foodPayload['name'], 'Original branded bar');
    expect(foodPayload.keys, isNot(contains('resolved_nutrients_json')));
    expect(await database.select(database.foods).get(), isEmpty);

    final targetDatabase = AppDatabase.inMemory();
    addTearDown(targetDatabase.close);
    final targetRepository = SyncRepository(
      database: targetDatabase,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-off-1',
              'serverClock': '2026-06-27T08:00:02.000Z',
              'changes': <Object?>[
                _pulledChangeFromPush(
                  entity: AppDatabase.foodEntriesTable,
                  deviceId: 'device-a',
                  change: pushedFoodEntry,
                ),
                _pulledChangeFromPush(
                  entity: AppDatabase.mealsTable,
                  deviceId: 'device-a',
                  change: pushedChanges.singleWhere(
                    (change) => change['id'] == mealId,
                  ),
                ),
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    final pullResult = await targetRepository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-b',
    );
    final targetRepositories = TrainingRepositories(targetDatabase);
    final pulledMeal = await targetRepositories.nutrition.getMealById(mealId);
    final pulledEntry = await targetRepositories.nutrition.getFoodEntryById(
      result.foodEntryId,
    );
    final storedEntry = await (targetDatabase.select(targetDatabase.foodEntries)
          ..where((row) => row.id.equals(result.foodEntryId)))
        .getSingle();

    expect(pullResult.appliedCount, 2);
    expect(pulledMeal?.mealType, 'Snack');
    expect(pulledEntry, isNotNull);
    expect(pulledEntry!.mealId, mealId);
    expect(pulledEntry.name, 'Original branded bar');
    expect(pulledEntry.foodId, '3017620422003');
    expect(pulledEntry.foodSource, FoodSource.openFoodFacts);
    expect(pulledEntry.nutrients[NutrientId.energy].value, 250);
    expect(pulledEntry.resolvedNutrients[NutrientId.energy].value, 112.5);
    expect(storedEntry.syncDeviceId, 'device-a');
    expect(storedEntry.syncPreviouslySynced, isTrue);
    expect(await targetDatabase.select(targetDatabase.foods).get(), isEmpty);
    expect(await targetDatabase.select(targetDatabase.metrics).get(), isEmpty);
    expect(await targetDatabase.select(targetDatabase.metricReadings).get(),
        isEmpty);
  });

  test('leaves journal entries unacknowledged after a failed push', () async {
    final updatedAt = DateTime.utc(2026, 6, 22, 8);
    await _insertActivityLogEntry(
      database,
      id: 'activity-1',
      entityId: '018f6a90-6d7f-7d63-bfc1-6f1025e0c001',
      updatedAt: updatedAt,
    );
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response('unavailable', 503),
        ),
      ),
    );

    await expectLater(
      repository.pushPendingLoggedSets(
        session: _session(),
        deviceId: 'device-a',
      ),
      throwsA(isA<ApiException>()),
    );

    final entry = await _activityLogEntry(database, 'activity-1');
    final status = await SyncStatusRepository(database).loadStatus(
      observedAt: DateTime.utc(2026, 6, 22, 9),
    );

    expect(entry.syncAcknowledgedAt == null, true);
    expect(status.kind, SyncStatusKind.failed);
    expect(status.showsFailureBanner, isFalse);
    expect(status.lastFailureMessage, 'Sync failed with HTTP 503.');
  });

  test('records auth-expired sync status after unauthorized responses',
      () async {
    final updatedAt = DateTime.utc(2026, 6, 22, 8);
    await _insertActivityLogEntry(
      database,
      id: 'activity-1',
      entityId: '018f6a90-6d7f-7d63-bfc1-6f1025e0c001',
      updatedAt: updatedAt,
    );
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response('unauthorized', 401),
        ),
      ),
    );

    await expectLater(
      repository.pushPendingLoggedSets(
        session: _session(),
        deviceId: 'device-a',
      ),
      throwsA(isA<ApiException>()),
    );

    final status = await SyncStatusRepository(database).loadStatus(
      observedAt: DateTime.utc(2026, 6, 22, 9),
    );

    expect(status.kind, SyncStatusKind.authExpired);
    expect(status.showsFailureBanner, isTrue);
  });

  test(
      'account deletion unauthorized response keeps local replica and marks '
      'Local-only status', () async {
    final updatedAt = DateTime.utc(2026, 6, 22, 8);
    const setId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c001';
    await _insertLoggedSetDependencies(database, updatedAt: updatedAt);
    await _insertLoggedSet(
      database,
      id: setId,
      updatedAt: updatedAt,
      repsEntered: '5',
      syncDeviceId: 'device-a',
      syncPreviouslySynced: true,
    );
    await _insertActivityLogEntry(
      database,
      id: 'pending-after-deletion',
      entityId: setId,
      updatedAt: updatedAt,
    );
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'code': 'sync_unauthorized',
              'message':
                  'Account deletion was requested. This device is now in Local-only Mode and its local data remains on the device.',
            }),
            401,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    await expectLater(
      repository.pushPendingLoggedSets(
        session: _session(),
        deviceId: 'device-a',
      ),
      throwsA(isA<ApiException>()),
    );

    final localSet = await _loggedSet(database, setId);
    final pendingEntry =
        await _activityLogEntry(database, 'pending-after-deletion');
    final status = await SyncStatusRepository(database).loadStatus(
      observedAt: DateTime.utc(2026, 6, 22, 9),
    );

    expect(localSet.repsEntered, '5');
    expect(localSet.deletedAt, isNull);
    expect(pendingEntry.syncAcknowledgedAt, isNull);
    expect(status.kind, SyncStatusKind.authExpired);
    expect(status.showsFailureBanner, isTrue);
    expect(
      status.lastFailureMessage,
      'Account deletion was requested. This device is now in Local-only Mode and its local data remains on the device.',
    );
  });

  test('acknowledges LWW-superseded logged set changes after push', () async {
    final updatedAt = DateTime.utc(2026, 6, 22, 8);
    const setId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c001';
    await _insertActivityLogEntry(
      database,
      id: 'activity-1',
      entityId: setId,
      updatedAt: updatedAt,
    );
    final requests = <http.Request>[];
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'accepted': <String>[setId],
              'serverClock': '2026-06-22T08:00:01.000Z',
              'applied': <Object?>[],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final firstResult = await repository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );
    final secondResult = await repository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );
    final entry = await _activityLogEntry(database, 'activity-1');

    expect(firstResult.pushedCount, 1);
    expect(firstResult.acknowledgedActivityLogIds, <String>['activity-1']);
    expect(firstResult.acceptedEntityIds, <String>[setId]);
    expect(secondResult.pushedCount, 0);
    expect(secondResult.acknowledgedActivityLogIds, isEmpty);
    expect(requests, hasLength(1));
    expect(entry.syncAcknowledgedAt, isNotNull);
  });

  test('chunks pending logged set pushes to the protocol limit', () async {
    final updatedAt = DateTime.utc(2026, 6, 22, 8);
    for (var index = 0; index < 101; index += 1) {
      await _insertActivityLogEntry(
        database,
        id: 'activity-$index',
        entityId: 'set-$index',
        updatedAt: updatedAt.add(Duration(seconds: index)),
      );
    }
    final batchSizes = <int>[];
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final changes = body['changes']! as List<Object?>;
          batchSizes.add(changes.length);
          expect(changes.length, lessThanOrEqualTo(100));
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'accepted': changes
                  .cast<Map<String, Object?>>()
                  .map((change) => change['id']! as String)
                  .toList(),
              'serverClock': '2026-06-22T08:00:01.000Z',
              'applied': <Object?>[],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final result = await repository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );
    final pendingRows = await (database.select(database.activityLog)
          ..where((row) => row.syncAcknowledgedAt.isNull()))
        .get();

    expect(result.pushedCount, 101);
    expect(result.acknowledgedActivityLogIds, hasLength(101));
    expect(batchSizes, <int>[100, 1]);
    expect(pendingRows, isEmpty);
  });

  test('pulls logged set changes and advances the stored cursor', () async {
    final updatedAt = DateTime.utc(2026, 6, 22, 8);
    const setId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c001';
    await _insertLoggedSetDependencies(database, updatedAt: updatedAt);
    final requests = <http.Request>[];
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          requests.add(request);
          if (requests.length == 1) {
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': syncProtocolVersion,
                'nextCursor': 'cursor-1',
                'serverClock': '2026-06-22T08:00:01.000Z',
                'changes': <Object?>[
                  <String, Object?>{
                    'entity': AppDatabase.loggedSetsTable,
                    'id': setId,
                    'deviceId': 'device-a',
                    'payload': _loggedSetPayload(setId, updatedAt),
                    'updatedAt': updatedAt.toIso8601String(),
                    'deletedAt': null,
                  },
                ],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }

          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-1',
              'serverClock': '2026-06-22T08:00:02.000Z',
              'changes': <Object?>[],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final firstResult = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );
    final pulledSet = await _loggedSet(database, setId);
    final storedCursor = await _storedPullCursor(database);

    expect(firstResult.appliedCount, 1);
    expect(firstResult.nextCursor, 'cursor-1');
    expect(firstResult.serverClock, '2026-06-22T08:00:01.000Z');
    expect(pulledSet.repsEntered, '5');
    expect(pulledSet.syncDeviceId, 'device-a');
    expect(pulledSet.deletedAt, isNull);
    expect(storedCursor, 'cursor-1');
    expect(requests.first.method, 'POST');
    expect(requests.first.url.toString(), 'https://sync.example/sync/pull');
    expect(requests.first.headers['authorization'], 'Bearer session-token');
    expect(jsonDecode(requests.first.body), <String, Object?>{
      'protocolVersion': syncProtocolVersion,
      'cursor': null,
      'limit': 100,
    });

    final secondResult = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );

    expect(secondResult.appliedCount, 0);
    expect(secondResult.nextCursor, 'cursor-1');
    expect(secondResult.serverClock, '2026-06-22T08:00:02.000Z');
    expect(requests, hasLength(2));
    expect(jsonDecode(requests.last.body), <String, Object?>{
      'protocolVersion': syncProtocolVersion,
      'cursor': 'cursor-1',
      'limit': 100,
    });
  });

  test('skips an unknown entity type and still advances the cursor', () async {
    final updatedAt = DateTime.utc(2026, 6, 22, 9);
    const firstSetId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c011';
    const secondSetId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c012';
    await _insertLoggedSetDependencies(database, updatedAt: updatedAt);
    final requests = <http.Request>[];
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          requests.add(request);
          final cursor = jsonDecode(request.body)['cursor'];
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-unknown-1',
              'serverClock': '2026-06-22T09:00:01.000Z',
              'changes': cursor == null
                  ? <Object?>[
                      _pulledChange(
                        id: firstSetId,
                        updatedAt: updatedAt,
                        repsEntered: '5',
                        deviceId: 'device-b',
                      ),
                      <String, Object?>{
                        'entity': 'entity_from_a_newer_server',
                        'id': 'future-row-1',
                        'deviceId': 'device-b',
                        'payload': <String, Object?>{'secret': 'not logged'},
                        'updatedAt': updatedAt.toIso8601String(),
                        'deletedAt': null,
                      },
                      _pulledChange(
                        id: secondSetId,
                        updatedAt: updatedAt,
                        repsEntered: '8',
                        deviceId: 'device-b',
                      ),
                    ]
                  : <Object?>[],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final firstResult = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );

    expect(firstResult.appliedCount, 2);
    expect((await _loggedSet(database, firstSetId)).repsEntered, '5');
    expect((await _loggedSet(database, secondSetId)).repsEntered, '8');
    expect(await _storedPullCursor(database), 'cursor-unknown-1');

    final secondResult = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );

    expect(secondResult.appliedCount, 0);
    expect(requests, hasLength(2));
    expect(jsonDecode(requests.last.body)['cursor'], 'cursor-unknown-1');
  });

  test(
      'quarantines a known-type change that fails to apply and still '
      'advances the cursor', () async {
    final logs = _captureDebugPrint();
    final updatedAt = DateTime.utc(2026, 6, 22, 9);
    const firstSetId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c011';
    const brokenSetId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c013';
    const secondSetId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c012';
    await _insertLoggedSetDependencies(database, updatedAt: updatedAt);
    final brokenChange = <String, Object?>{
      ..._pulledChange(
        id: brokenSetId,
        updatedAt: updatedAt,
        repsEntered: '6',
        deviceId: 'device-b',
      ),
      'payload': <String, Object?>{
        ..._loggedSetPayload(brokenSetId, updatedAt, repsEntered: '6'),
        'comment': 'private-protocol-note',
      },
      // Parses as an envelope, fails DateTime.parse while applying.
      'updatedAt': 'not-a-timestamp',
    };
    final requests = <http.Request>[];
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          requests.add(request);
          final cursor = jsonDecode(request.body)['cursor'];
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-broken-1',
              'serverClock': '2026-06-22T09:00:01.000Z',
              'changes': cursor == null
                  ? <Object?>[
                      _pulledChange(
                        id: firstSetId,
                        updatedAt: updatedAt,
                        repsEntered: '5',
                        deviceId: 'device-b',
                      ),
                      brokenChange,
                      _pulledChange(
                        id: secondSetId,
                        updatedAt: updatedAt,
                        repsEntered: '8',
                        deviceId: 'device-b',
                      ),
                    ]
                  : <Object?>[],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final firstResult = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );

    expect(firstResult.appliedCount, 2);
    expect((await _loggedSet(database, firstSetId)).repsEntered, '5');
    expect((await _loggedSet(database, secondSetId)).repsEntered, '8');
    expect(
      await (database.select(database.loggedSets)
            ..where((row) => row.id.equals(brokenSetId)))
          .getSingleOrNull(),
      isNull,
    );
    expect(await _storedPullCursor(database), 'cursor-broken-1');
    final held = await _quarantinedChanges(database);
    expect(held, hasLength(1));
    expect(held.single.entityTable, AppDatabase.loggedSetsTable);
    expect(held.single.entityId, brokenSetId);
    expect(held.single.failureKind, 'format');
    final heldChange =
        jsonDecode(held.single.changeJson) as Map<String, Object?>;
    expect(heldChange['payload'], brokenChange['payload']);
    expect(heldChange['updatedAt'], 'not-a-timestamp');
    expect(
      (await SyncStatusRepository(database).loadStatus())
          .quarantinedChangeCount,
      1,
    );
    expect(logs, isNotEmpty);
    expect(logs.join('\n'), isNot(contains('private-protocol-note')));
    expect(logs.join('\n'), isNot(contains('not-a-timestamp')));

    final secondResult = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );

    expect(secondResult.appliedCount, 0);
    expect(requests, hasLength(2));
    expect(jsonDecode(requests.last.body)['cursor'], 'cursor-broken-1');
    expect(await _quarantinedChanges(database), hasLength(1));
  });

  test('quarantines a malformed change envelope and still advances the cursor',
      () async {
    final updatedAt = DateTime.utc(2026, 6, 22, 9);
    const firstSetId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c011';
    const brokenSetId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c013';
    await _insertLoggedSetDependencies(database, updatedAt: updatedAt);
    final missingDeviceId = _pulledChange(
      id: brokenSetId,
      updatedAt: updatedAt,
      repsEntered: '6',
      deviceId: 'device-b',
    )..remove('deviceId');
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-envelope-1',
              'serverClock': '2026-06-22T09:00:01.000Z',
              'changes': <Object?>[
                missingDeviceId,
                'not-an-object',
                _pulledChange(
                  id: firstSetId,
                  updatedAt: updatedAt,
                  repsEntered: '5',
                  deviceId: 'device-b',
                ),
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final result = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
      limit: 3,
    );

    expect(result.appliedCount, 1);
    // Malformed entries still filled the page, so there may be more.
    expect(result.hasMore, isTrue);
    expect((await _loggedSet(database, firstSetId)).repsEntered, '5');
    expect(await _storedPullCursor(database), 'cursor-envelope-1');
    final held = await _quarantinedChanges(database);
    expect(
      held.map((row) => (row.entityTable, row.entityId, row.failureKind)),
      <(String?, String?, String)>[
        (AppDatabase.loggedSetsTable, brokenSetId, 'envelope'),
        (null, null, 'envelope'),
      ],
    );
    expect(jsonDecode(held.first.changeJson), missingDeviceId);
    expect(jsonDecode(held.last.changeJson), 'not-an-object');
  });

  test('a later valid version of a quarantined row supersedes it', () async {
    final updatedAt = DateTime.utc(2026, 6, 22, 9);
    const setId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c013';
    await _insertLoggedSetDependencies(database, updatedAt: updatedAt);
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          final cursor = jsonDecode(request.body)['cursor'];
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': cursor == null ? 'cursor-1' : 'cursor-2',
              'serverClock': '2026-06-22T09:00:01.000Z',
              'changes': <Object?>[
                if (cursor == null)
                  <String, Object?>{
                    ..._pulledChange(
                      id: setId,
                      updatedAt: updatedAt,
                      repsEntered: '6',
                      deviceId: 'device-b',
                    ),
                    'updatedAt': 'not-a-timestamp',
                  }
                else
                  _pulledChange(
                    id: setId,
                    updatedAt: updatedAt.add(const Duration(minutes: 1)),
                    repsEntered: '7',
                    deviceId: 'device-b',
                  ),
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );
    expect(await _quarantinedChanges(database), hasLength(1));

    final result = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );

    expect(result.appliedCount, 1);
    expect((await _loggedSet(database, setId)).repsEntered, '7');
    expect(await _quarantinedChanges(database), isEmpty);
    expect(await _storedPullCursor(database), 'cursor-2');
  });

  test('retries a quarantined change at the end of the next pull', () async {
    final updatedAt = DateTime.utc(2026, 6, 22, 9);
    const setId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c013';
    await _insertLoggedSetDependencies(database, updatedAt: updatedAt);
    // Held by an earlier build that could not apply it; this one can.
    await database.into(database.quarantinedSyncChanges).insert(
          QuarantinedSyncChangesCompanion.insert(
            entityTable: const Value<String?>(AppDatabase.loggedSetsTable),
            entityId: const Value<String?>(setId),
            changeJson: jsonEncode(
              _pulledChange(
                id: setId,
                updatedAt: updatedAt,
                repsEntered: '6',
                deviceId: 'device-b',
              ),
            ),
            failureKind: 'format',
            quarantinedAt: updatedAt,
          ),
        );
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-1',
              'serverClock': '2026-06-22T09:00:01.000Z',
              'changes': <Object?>[],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final result = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );

    expect(result.appliedCount, 1);
    expect((await _loggedSet(database, setId)).repsEntered, '6');
    expect(await _quarantinedChanges(database), isEmpty);
  });

  test('holds a change whose parent row is missing until the parent exists',
      () async {
    final updatedAt = DateTime.utc(2026, 6, 22, 9);
    const setId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c013';
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          final cursor = jsonDecode(request.body)['cursor'];
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-1',
              'serverClock': '2026-06-22T09:00:01.000Z',
              'changes': cursor == null
                  ? <Object?>[
                      _pulledChange(
                        id: setId,
                        updatedAt: updatedAt,
                        repsEntered: '6',
                        deviceId: 'device-b',
                      ),
                    ]
                  : <Object?>[],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    // The Logged Set's Workout and Exercise (Drift FKs) are not here yet.
    final firstResult = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );

    expect(firstResult.appliedCount, 0);
    expect(await _storedPullCursor(database), 'cursor-1');
    expect(
      (await _quarantinedChanges(database))
          .map((row) => (row.entityId, row.failureKind)),
      <(String?, String)>[(setId, 'constraint')],
    );
    // Its savepoint rolled back: nothing of the failed apply is left behind.
    expect(
      await (database.select(database.activityLog)
            ..where((row) => row.entityId.equals(setId)))
          .get(),
      isEmpty,
    );

    await _insertLoggedSetDependencies(database, updatedAt: updatedAt);
    final secondResult = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );

    expect(secondResult.appliedCount, 1);
    expect((await _loggedSet(database, setId)).repsEntered, '6');
    expect(await _quarantinedChanges(database), isEmpty);
  });

  test(
      'full re-sync keeps local rows when a snapshot entry is unidentifiable '
      'and drops quarantined changes it did not resend', () async {
    final updatedAt = DateTime.utc(2026, 6, 22, 8);
    const brokenSetId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c001';
    const absentSetId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c002';
    const staleHeldSetId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c003';
    await _insertLoggedSetDependencies(database, updatedAt: updatedAt);
    for (final id in <String>[brokenSetId, absentSetId]) {
      await _insertLoggedSet(
        database,
        id: id,
        updatedAt: updatedAt,
        repsEntered: '4',
        syncDeviceId: 'device-b',
        syncPreviouslySynced: true,
      );
    }
    await database.into(database.quarantinedSyncChanges).insert(
          QuarantinedSyncChangesCompanion.insert(
            entityTable: const Value<String?>(AppDatabase.loggedSetsTable),
            entityId: const Value<String?>(staleHeldSetId),
            changeJson: jsonEncode('held-by-an-earlier-pull'),
            failureKind: 'envelope',
            quarantinedAt: updatedAt,
          ),
        );
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          if (body['mode'] != 'snapshot') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': syncProtocolVersion,
                'fullResyncRequired': true,
                'nextCursor': null,
                'serverClock': '2026-06-22T09:00:00.000Z',
                'changes': <Object?>[],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'snapshot-cursor-1',
              'serverClock': '2026-06-22T09:00:02.000Z',
              'changes': body['cursor'] == null
                  ? <Object?>[
                      <String, Object?>{
                        ..._pulledChange(
                          id: brokenSetId,
                          updatedAt: updatedAt,
                          repsEntered: '9',
                          deviceId: 'device-b',
                        ),
                        'updatedAt': 'not-a-timestamp',
                      },
                      42,
                    ]
                  : <Object?>[],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final result = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );

    expect(result.fullResyncRequired, isTrue);
    expect(await _storedPullCursor(database), 'snapshot-cursor-1');
    expect((await _loggedSet(database, brokenSetId)).deletedAt, isNull);
    // The unidentifiable entry could have been this row, so the snapshot
    // does not prove it deleted.
    expect((await _loggedSet(database, absentSetId)).deletedAt, isNull);
    expect(
      (await _quarantinedChanges(database))
          .map((row) => (row.entityId, row.failureKind)),
      <(String?, String)>[(null, 'envelope'), (brokenSetId, 'format')],
    );
  });

  test('pulls Metric definitions before Metric Readings', () async {
    final updatedAt = DateTime.utc(2026, 6, 25, 7);
    const metricId = 'metric-resting-heart-rate';
    const readingId = 'reading-resting-heart-rate-2026-06-25';
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-metrics-1',
              'serverClock': '2026-06-25T07:00:01.000Z',
              'changes': <Object?>[
                <String, Object?>{
                  'entity': AppDatabase.metricReadingsTable,
                  'id': readingId,
                  'deviceId': 'integration:garmin',
                  'payload': <String, Object?>{
                    'id': readingId,
                    'metric_id': metricId,
                    'external_activity_id': null,
                    'value_json': <String, Object?>{
                      'shape': 'scalar',
                      'value': 58,
                      'entered': '58',
                    },
                    'scalar_value': 58,
                    'scalar_entered': '58',
                    'at_time': updatedAt.toIso8601String(),
                    'window_started_at': null,
                    'window_ended_at': null,
                    'provenance': MetricReadingProvenance.integration.name,
                    'source': 'garmin',
                    'external_id': 'garmindb:resting_hr:2026-06-25',
                    'comment': null,
                    'updated_at': updatedAt.toIso8601String(),
                    'deleted_at': null,
                  },
                  'updatedAt': updatedAt.toIso8601String(),
                  'deletedAt': null,
                  'activityLogId':
                      'integration:f8870c000c5503eb5055e12a2649910a',
                  'actor': 'integration',
                  'batchId':
                      'garmindb-fit:33df7b9d7148070f4e61bb97db6bba49a2860aa60f74562872961addb861e3ae',
                  'beforeImage': null,
                  'afterImage': <String, Object?>{
                    'id': readingId,
                    'metricId': metricId,
                    'valueJson': <String, Object?>{
                      'shape': 'scalar',
                      'value': 58,
                      'entered': '58',
                    },
                    'scalarValue': 58,
                    'scalarEntered': '58',
                    'atTime': updatedAt.toIso8601String(),
                    'windowStartedAt': null,
                    'windowEndedAt': null,
                    'provenance': MetricReadingProvenance.integration.name,
                    'source': 'garmin',
                    'externalId': 'garmindb:resting_hr:2026-06-25',
                    'comment': null,
                    'updatedAt': updatedAt.toIso8601String(),
                    'deletedAt': null,
                  },
                  'occurredAt': updatedAt.toIso8601String(),
                },
                <String, Object?>{
                  'entity': AppDatabase.metricsTable,
                  'id': metricId,
                  'deviceId': 'integration:garmin',
                  'payload': <String, Object?>{
                    'id': metricId,
                    'name': 'Resting Heart Rate',
                    'unit': 'beatsPerMinute',
                    'value_shape': MetricValueShape.scalar.name,
                    'metric_group': MetricGroup.monitoring.name,
                    'goal_type': null,
                    'goal_target_value': null,
                    'enabled': true,
                    'pinned': false,
                    'sort_order': 100,
                    'updated_at': updatedAt.toIso8601String(),
                    'deleted_at': null,
                  },
                  'updatedAt': updatedAt.toIso8601String(),
                  'deletedAt': null,
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final result = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );
    final metric = await (database.select(database.metrics)
          ..where((row) => row.id.equals(metricId)))
        .getSingle();
    final reading = await (database.select(database.metricReadings)
          ..where((row) => row.id.equals(readingId)))
        .getSingle();
    final activityRows = await (database.select(database.activityLog)
          ..where(
            (row) => row.entityTable.isIn([
              AppDatabase.metricsTable,
              AppDatabase.metricReadingsTable,
            ]),
          ))
        .get();

    expect(result.appliedCount, 2);
    expect(metric.name, 'Resting Heart Rate');
    expect(metric.syncDeviceId, 'integration:garmin');
    expect(metric.syncPreviouslySynced, isTrue);
    expect(reading.metricId, metricId);
    expect(reading.scalarEntered, '58');
    expect(reading.valueJson, contains('"value":58'));
    expect(reading.syncDeviceId, 'integration:garmin');
    expect(reading.syncPreviouslySynced, isTrue);
    expect(activityRows, hasLength(2));
  });

  test('pulls activity-imported Logged Sets with materialized Workout parent',
      () async {
    final updatedAt = DateTime.utc(2026, 7, 1, 7, 30, 16, 289);
    const workoutId = 'materialized-workout:41fb3d70690ead72c4f0651fea297caa';
    const setId = 'materialized-set:1f35d61d3143503db43c38712856ba14';
    await database.into(database.exercises).insert(
          ExercisesCompanion.insert(
            id: 'exercise-1',
            libraryOrigin: const Value<String>('platform'),
            name: 'Strength Training',
            dimensionIds: '["load","reps"]',
            updatedAt: updatedAt,
          ),
        );
    final payload = <String, Object?>{
      'id': setId,
      'workout_id': workoutId,
      'exercise_id': 'exercise-1',
      'position': 0,
      'load_unit': 'kilogram',
      'load_entered': '0',
      'reps_unit': 'repetition',
      'reps_entered': '4',
      'comment': null,
      'side': null,
      'rpe': null,
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': null,
      'workout_started_at': '2026-05-25T23:09:39.000Z',
      'workout_ended_at': '2026-05-26T00:35:16.933Z',
      'workout_timezone': 'Australia/Brisbane',
      'workout_local_date': '2026-05-26',
      'workout_comment': null,
    };
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-imported-set-1',
              'serverClock': '2026-07-01T07:30:17.000Z',
              'changes': <Object?>[
                <String, Object?>{
                  'entity': AppDatabase.loggedSetsTable,
                  'id': setId,
                  'deviceId': 'integration:garmin',
                  'payload': payload,
                  'updatedAt': updatedAt.toIso8601String(),
                  'deletedAt': null,
                  'activityLogId':
                      'integration:24e7f29b97ea57c1a153c9530ee180c4',
                  'actor': 'integration',
                  'batchId':
                      'garmindb-fit:33df7b9d7148070f4e61bb97db6bba49a2860aa60f74562872961addb861e3ae',
                  'beforeImage': null,
                  'afterImage': payload,
                  'occurredAt': updatedAt.toIso8601String(),
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final result = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );
    final workout = await (database.select(database.workoutSessions)
          ..where((row) => row.id.equals(workoutId)))
        .getSingle();
    final loggedSet = await (database.select(database.loggedSets)
          ..where((row) => row.id.equals(setId)))
        .getSingle();
    final activity = await _activityLogEntry(
      database,
      'integration:24e7f29b97ea57c1a153c9530ee180c4',
    );

    expect(result.appliedCount, 1);
    expect(workout.timezone, 'Australia/Brisbane');
    expect(workout.localDate, '2026-05-26');
    expect(workout.endedAt?.toUtc(), DateTime.utc(2026, 5, 26, 0, 35, 16));
    expect(loggedSet.workoutId, workoutId);
    expect(loggedSet.isCompleted, isFalse);
    expect(loggedSet.syncPreviouslySynced, isTrue);
    expect(activity.afterImage, contains('"is_completed":false'));
  });

  test('pulls integration data-class consent rows and advances the cursor',
      () async {
    final updatedAt = DateTime.utc(2026, 6, 25, 10);
    const consentId = 'garmin-heart-rate-consent';
    final requests = <http.Request>[];
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-consent-1',
              'serverClock': '2026-06-25T10:00:01.000Z',
              'changes': <Object?>[
                _pulledIntegrationConsentChange(
                  id: consentId,
                  dataClass: 'heartRate',
                  enabled: true,
                  updatedAt: updatedAt,
                  deviceId: 'edge:garmin-sidecar',
                ),
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final result = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );
    final row = await _integrationConsent(database, consentId);
    final storedCursor = await _storedPullCursor(database);
    final syncEntries = await (database.select(database.activityLog)
          ..where((entry) => entry.entityTable.equals(
                AppDatabase.integrationDataClassConsentsTable,
              )))
        .get();

    expect(result.appliedCount, 1);
    expect(result.nextCursor, 'cursor-consent-1');
    expect(storedCursor, 'cursor-consent-1');
    expect(row.credentialId, 'credential-garmin-1');
    expect(row.dataClass, 'heartRate');
    expect(row.enabled, isTrue);
    expect(row.syncDeviceId, 'edge:garmin-sidecar');
    expect(row.syncPreviouslySynced, isTrue);
    expect(syncEntries, hasLength(1));
    expect(syncEntries.single.syncAcknowledgedAt, isNotNull);
    expect(jsonDecode(requests.single.body), <String, Object?>{
      'protocolVersion': syncProtocolVersion,
      'cursor': null,
      'limit': 100,
    });
  });

  test('pushes pending integration data-class consent changes', () async {
    final updatedAt = DateTime.utc(2026, 6, 25, 10);
    const consentId = 'garmin-heart-rate-consent';
    await _insertIntegrationConsent(
      database,
      id: consentId,
      dataClass: 'heartRate',
      enabled: true,
      updatedAt: updatedAt,
    );
    await _insertIntegrationConsentActivityLogEntry(
      database,
      id: 'consent-activity-1',
      entityId: consentId,
      dataClass: 'heartRate',
      enabled: true,
      updatedAt: updatedAt,
    );
    final requests = <http.Request>[];
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          requests.add(request);
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final changes = body['changes']! as List<Object?>;
          final change = changes.single! as Map<String, Object?>;
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'accepted': <String>[consentId],
              'serverClock': '2026-06-25T10:00:01.000Z',
              'applied': <Object?>[
                <String, Object?>{
                  'id': consentId,
                  'updatedAt': change['updatedAt'],
                  'deviceId': 'device-a',
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final result = await repository.pushPendingIntegrationDataClassConsents(
      session: _session(),
      deviceId: 'device-a',
    );
    final requestBody =
        jsonDecode(requests.single.body) as Map<String, Object?>;
    final change = (requestBody['changes']! as List<Object?>).single!
        as Map<String, Object?>;
    final payload = change['payload']! as Map<String, Object?>;
    final entry = await _activityLogEntry(database, 'consent-activity-1');
    final row = await _integrationConsent(database, consentId);

    expect(result.pushedCount, 1);
    expect(result.acknowledgedActivityLogIds, <String>['consent-activity-1']);
    expect(
        requestBody['entity'], AppDatabase.integrationDataClassConsentsTable);
    expect(payload['credential_id'], 'credential-garmin-1');
    expect(payload['data_class'], 'heartRate');
    expect(payload['enabled'], isTrue);
    expect(entry.syncAcknowledgedAt, isNotNull);
    expect(row.syncDeviceId, 'device-a');
    expect(row.syncPreviouslySynced, isTrue);
  });

  test('applies pulled tombstones as soft deletes', () async {
    final updatedAt = DateTime.utc(2026, 6, 22, 8);
    final deletedAt = DateTime.utc(2026, 6, 22, 9);
    const setId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c001';
    await _insertLoggedSetDependencies(database, updatedAt: updatedAt);
    await database.into(database.loggedSets).insert(
          LoggedSetsCompanion.insert(
            id: setId,
            workoutId: 'workout-1',
            exerciseId: 'exercise-1',
            position: 0,
            repsValue: const Value<double?>(5),
            repsUnit: const Value<String?>('rep'),
            repsEntered: const Value<String?>('5'),
            isCompleted: const Value<bool>(false),
            updatedAt: updatedAt,
          ),
        );
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-1',
              'serverClock': '2026-06-22T08:00:01.000Z',
              'changes': <Object?>[
                <String, Object?>{
                  'entity': AppDatabase.loggedSetsTable,
                  'id': setId,
                  'deviceId': 'device-b',
                  'payload': _loggedSetPayload(
                    setId,
                    deletedAt,
                    deletedAt: deletedAt,
                  ),
                  'updatedAt': deletedAt.toIso8601String(),
                  'deletedAt': deletedAt.toIso8601String(),
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    final result = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );
    final pulledSet = await _loggedSet(database, setId);

    expect(result.appliedCount, 1);
    expect(pulledSet.deletedAt?.toUtc(), deletedAt);
    expect(pulledSet.syncDeviceId, 'device-b');
  });

  test('settings erase pushes a tombstone for every erased synced row',
      () async {
    final updatedAt = DateTime.utc(2026, 6, 22, 8);
    const setId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c001';
    await _insertLoggedSetDependencies(database, updatedAt: updatedAt);
    await _insertLoggedSet(
      database,
      id: setId,
      updatedAt: updatedAt,
      repsEntered: '5',
      syncDeviceId: 'device-a',
      syncPreviouslySynced: true,
    );
    await TrainingRepositories(database).eraseAllData();
    final erasedSet = await _loggedSet(database, setId);
    final pushedIdsByEntity = <String, Set<String>>{};
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final changes =
              (body['changes']! as List<Object?>).cast<Map<String, Object?>>();
          for (final change in changes) {
            final deletedAt = change['deletedAt'] as String?;
            expect(deletedAt, isNotNull, reason: '${body['entity']}');
            expect(
              (change['payload']! as Map<String, Object?>)['deleted_at'],
              deletedAt,
            );
            pushedIdsByEntity
                .putIfAbsent(body['entity']! as String, () => <String>{})
                .add(change['id']! as String);
          }
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'accepted': <String>[
                for (final change in changes) change['id']! as String,
              ],
              'serverClock': '2026-06-22T08:00:01.000Z',
              'applied': <Object?>[
                for (final change in changes)
                  <String, Object?>{
                    'id': change['id'],
                    'updatedAt': change['updatedAt'],
                    'deviceId': 'device-a',
                  },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await repository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );
    final pendingRows = await (database.select(database.activityLog)
          ..where((row) => row.syncAcknowledgedAt.isNull()))
        .get();

    expect(erasedSet.deletedAt, isNotNull);
    expect(erasedSet.syncPreviouslySynced, isTrue);
    expect(pushedIdsByEntity, <String, Set<String>>{
      AppDatabase.exercisesTable: <String>{'exercise-1'},
      AppDatabase.workoutSessionsTable: <String>{'workout-1'},
      AppDatabase.loggedSetsTable: <String>{setId},
    });
    expect(pendingRows, isEmpty);
  });

  test('does not re-push stale live copy after a tombstone wins', () async {
    final updatedAt = DateTime.utc(2026, 6, 22, 8);
    final deletedAt = DateTime.utc(2026, 6, 22, 9);
    const setId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c001';
    await _insertLoggedSetDependencies(database, updatedAt: updatedAt);
    await _insertLoggedSet(
      database,
      id: setId,
      updatedAt: updatedAt,
      repsEntered: '5',
      syncDeviceId: 'device-a',
      syncPreviouslySynced: true,
    );
    await _insertActivityLogEntry(
      database,
      id: 'stale-live-activity',
      entityId: setId,
      updatedAt: updatedAt,
    );
    final requests = <http.Request>[];
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/sync/pull') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': syncProtocolVersion,
                'nextCursor': 'cursor-1',
                'serverClock': '2026-06-22T09:00:01.000Z',
                'changes': <Object?>[
                  <String, Object?>{
                    'entity': AppDatabase.loggedSetsTable,
                    'id': setId,
                    'deviceId': 'device-b',
                    'payload': _loggedSetPayload(
                      setId,
                      deletedAt,
                      deletedAt: deletedAt,
                    ),
                    'updatedAt': deletedAt.toIso8601String(),
                    'deletedAt': deletedAt.toIso8601String(),
                  },
                ],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          fail('Stale live copy should not be pushed after tombstone.');
        }),
      ),
    );

    final pullResult = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );
    final pushResult = await repository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );
    final pulledSet = await _loggedSet(database, setId);
    final staleEntry = await _activityLogEntry(database, 'stale-live-activity');

    expect(pullResult.appliedCount, 1);
    expect(pulledSet.deletedAt?.toUtc(), deletedAt);
    expect(pulledSet.syncPreviouslySynced, isTrue);
    expect(pushResult.pushedCount, 0);
    expect(pushResult.acknowledgedActivityLogIds, <String>[
      'stale-live-activity',
    ]);
    expect(staleEntry.syncAcknowledgedAt, isNotNull);
    expect(requests.map((request) => request.url.path), <String>[
      '/sync/pull',
    ]);
  });

  test('forced full resync pushes journal then snapshots live server rows',
      () async {
    final localUpdatedAt = DateTime.utc(2026, 6, 22, 8);
    final snapshotUpdatedAt = DateTime.utc(2026, 6, 22, 9);
    const pendingSetId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c001';
    const keptSetId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c002';
    const missingSetId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c003';
    const localOnlySetId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c004';
    await _insertLoggedSetDependencies(database, updatedAt: localUpdatedAt);
    await _insertLoggedSet(
      database,
      id: missingSetId,
      updatedAt: localUpdatedAt,
      repsEntered: '4',
      syncDeviceId: 'device-b',
      syncPreviouslySynced: true,
    );
    await _insertLoggedSet(
      database,
      id: localOnlySetId,
      updatedAt: localUpdatedAt,
      repsEntered: '7',
      syncDeviceId: 'device-a',
      syncPreviouslySynced: false,
    );
    await _insertActivityLogEntry(
      database,
      id: 'pending-local-write',
      entityId: pendingSetId,
      updatedAt: localUpdatedAt,
    );
    await database.into(database.syncStates).insert(
          SyncStatesCompanion.insert(
            id: syncStateId,
            pullCursor: const Value<String?>(
              '2000-01-01T00:00:00.000Z|expired-row',
            ),
            updatedAt: localUpdatedAt,
          ),
        );

    final requests = <http.Request>[];
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          requests.add(request);
          final body = jsonDecode(request.body) as Map<String, Object?>;

          if (request.url.path == '/sync/pull' && requests.length == 1) {
            expect(body, <String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'cursor': '2000-01-01T00:00:00.000Z|expired-row',
              'limit': 100,
            });
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': syncProtocolVersion,
                'fullResyncRequired': true,
                'nextCursor': '2000-01-01T00:00:00.000Z|expired-row',
                'serverClock': '2026-06-22T09:00:00.000Z',
                'changes': <Object?>[],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }

          if (request.url.path == '/sync/push') {
            final changes = body['changes']! as List<Object?>;
            expect(changes, hasLength(1));
            expect(
                (changes.single! as Map<String, Object?>)['id'], pendingSetId);
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': syncProtocolVersion,
                'accepted': <String>[pendingSetId],
                'serverClock': '2026-06-22T09:00:01.000Z',
                'applied': <Object?>[
                  <String, Object?>{
                    'id': pendingSetId,
                    'updatedAt': localUpdatedAt.toIso8601String(),
                    'deviceId': 'device-a',
                  },
                ],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }

          if (request.url.path == '/sync/pull' &&
              body['mode'] == 'snapshot' &&
              body['cursor'] == null) {
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': syncProtocolVersion,
                'fullResyncRequired': false,
                'nextCursor': 'snapshot-cursor-1',
                'serverClock': '2026-06-22T09:00:02.000Z',
                'changes': <Object?>[
                  _pulledChange(
                    id: pendingSetId,
                    updatedAt: localUpdatedAt,
                    repsEntered: '5',
                    deviceId: 'device-a',
                  ),
                  _pulledChange(
                    id: keptSetId,
                    updatedAt: snapshotUpdatedAt,
                    repsEntered: '9',
                    deviceId: 'device-b',
                  ),
                ],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }

          if (request.url.path == '/sync/pull' &&
              body['mode'] == 'snapshot' &&
              body['cursor'] == 'snapshot-cursor-1') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': syncProtocolVersion,
                'fullResyncRequired': false,
                'nextCursor': 'snapshot-cursor-1',
                'serverClock': '2026-06-22T09:00:03.000Z',
                'changes': <Object?>[],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }

          fail('Unexpected sync request: ${request.url.path} ${request.body}');
        }),
      ),
    );

    final result = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );
    final pendingSet = await _loggedSet(database, pendingSetId);
    final keptSet = await _loggedSet(database, keptSetId);
    final missingSet = await _loggedSet(database, missingSetId);
    final localOnlySet = await _loggedSet(database, localOnlySetId);
    final pendingEntry =
        await _activityLogEntry(database, 'pending-local-write');
    final storedCursor = await _storedPullCursor(database);

    expect(result.fullResyncRequired, isTrue);
    expect(result.appliedCount, 2);
    expect(result.nextCursor, 'snapshot-cursor-1');
    expect(pendingSet.deletedAt, isNull);
    expect(pendingSet.syncPreviouslySynced, isTrue);
    expect(keptSet.repsEntered, '9');
    expect(keptSet.deletedAt, isNull);
    expect(missingSet.deletedAt, isNotNull);
    expect(localOnlySet.deletedAt, isNull);
    expect(localOnlySet.syncPreviouslySynced, isFalse);
    expect(pendingEntry.syncAcknowledgedAt, isNotNull);
    expect(storedCursor, 'snapshot-cursor-1');
    expect(requests.map((request) => request.url.path), <String>[
      '/sync/pull',
      '/sync/push',
      '/sync/pull',
      '/sync/pull',
    ]);
  });

  test('pull apply converges by updated_at and device id in either order',
      () async {
    final updatedAt = DateTime.utc(2026, 6, 22, 8);
    const setId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c001';

    final firstOrder = await _runTwoDevicePullOrder(
      setId: setId,
      updatedAt: updatedAt,
      firstPullDeviceId: 'device-a',
    );
    final secondOrder = await _runTwoDevicePullOrder(
      setId: setId,
      updatedAt: updatedAt,
      firstPullDeviceId: 'device-b',
    );

    expect(firstOrder, <String, String>{
      'device-a': '6',
      'device-b': '6',
    });
    expect(secondOrder, <String, String>{
      'device-a': '6',
      'device-b': '6',
    });
  });

  test(
      'records sync-overwritten values in activity feed and undo restores them',
      () async {
    final localUpdatedAt = DateTime.utc(2026, 6, 22, 8);
    final remoteUpdatedAt = DateTime.utc(2026, 6, 22, 8, 1);
    const setId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c001';
    await _insertLoggedSetDependencies(database, updatedAt: localUpdatedAt);
    await _insertLoggedSet(
      database,
      id: setId,
      updatedAt: localUpdatedAt,
      repsEntered: '5',
      syncDeviceId: 'device-a',
    );
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-1',
              'serverClock': '2026-06-22T08:01:01.000Z',
              'changes': <Object?>[
                _pulledChange(
                  id: setId,
                  updatedAt: remoteUpdatedAt,
                  repsEntered: '6',
                  deviceId: 'device-b',
                ),
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    final result = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );
    final pulledSet = await _loggedSet(database, setId);
    final repositories = TrainingRepositories(database);
    final feedRepository = ActivityFeedRepository(repositories);
    final syncBatch = (await feedRepository.listRecentBatches()).singleWhere(
      (batch) => batch.actor == 'sync',
    );
    final syncEntry = syncBatch.entries.single;
    final rawSyncEntry = await _activityLogEntry(database, syncEntry.id);

    expect(result.appliedCount, 1);
    expect(pulledSet.repsEntered, '6');
    expect(syncEntry.entityTable, AppDatabase.loggedSetsTable);
    expect(syncEntry.entityId, setId);
    expect(syncEntry.beforeImage!['reps_entered'], '5');
    expect(syncEntry.afterImage!['reps_entered'], '6');
    expect(
        syncEntry.beforeImage!['updated_at'], localUpdatedAt.toIso8601String());
    expect(
        syncEntry.afterImage!['updated_at'], remoteUpdatedAt.toIso8601String());
    expect(rawSyncEntry.syncAcknowledgedAt, isNotNull);

    final undo = await feedRepository.undoBatch(syncBatch.batchId);
    final restoredSet = await _loggedSet(database, setId);

    expect(undo.conflicts, isEmpty);
    expect(undo.appliedEntries.map((entry) => entry.entityId), <String>[
      setId,
    ]);
    expect(restoredSet.repsEntered, '5');
  });

  test(
      'preserves a pulled agent batch as one activity entry and undo propagates',
      () async {
    final updatedAt = DateTime.utc(2026, 6, 24, 5);
    const firstSetId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c201';
    const secondSetId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c202';
    const batchId = 'agent-batch-1';
    const deviceId = 'agent:agent-key-1';
    await _insertLoggedSetDependencies(database, updatedAt: updatedAt);

    final firstAfterImage = <String, Object?>{
      ..._loggedSetPayload(firstSetId, updatedAt, repsEntered: '5'),
      'exercise_name': 'Back Squat',
    };
    final secondAfterImage = <String, Object?>{
      ..._loggedSetPayload(secondSetId, updatedAt, repsEntered: '8'),
      'exercise_name': 'Back Squat',
    };
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-1',
              'serverClock': '2026-06-24T05:00:01.000Z',
              'changes': <Object?>[
                _pulledChange(
                  id: firstSetId,
                  updatedAt: updatedAt,
                  repsEntered: '5',
                  deviceId: deviceId,
                  actor: 'agent',
                  batchId: batchId,
                  activityLogId: 'agent:$batchId:$firstSetId',
                  beforeImage: null,
                  afterImage: firstAfterImage,
                  occurredAt: updatedAt,
                ),
                _pulledChange(
                  id: secondSetId,
                  updatedAt: updatedAt,
                  repsEntered: '8',
                  deviceId: deviceId,
                  actor: 'agent',
                  batchId: batchId,
                  activityLogId: 'agent:$batchId:$secondSetId',
                  beforeImage: null,
                  afterImage: secondAfterImage,
                  occurredAt: updatedAt,
                ),
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    final result = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );
    final repositories = TrainingRepositories(database);
    final feedRepository = ActivityFeedRepository(repositories);
    final agentBatch = (await feedRepository.listRecentBatches()).singleWhere(
      (batch) => batch.batchId == batchId,
    );

    expect(result.appliedCount, 2);
    expect(agentBatch.actor, deviceId);
    expect(agentBatch.entries, hasLength(2));
    expect(agentBatch.affectedEntitySummary, 'Logged 2 sets');
    expect(
      agentBatch.entries.map((entry) => entry.id),
      <String>[
        'agent:$batchId:$firstSetId',
        'agent:$batchId:$secondSetId',
      ],
    );
    expect(
      agentBatch.entries.map((entry) => entry.afterImage!['exercise_name']),
      everyElement(isNull),
    );

    final undo = await feedRepository.undoBatch(batchId);
    final firstSet = await _loggedSet(database, firstSetId);
    final secondSet = await _loggedSet(database, secondSetId);
    final undoBatchId = undo.undoBatchId!;
    final undoRows = await (database.select(database.activityLog)
          ..where((row) => row.batchId.equals(undoBatchId)))
        .get();

    expect(undo.conflicts, isEmpty);
    expect(undo.appliedEntries.map((entry) => entry.entityId), <String>[
      secondSetId,
      firstSetId,
    ]);
    expect(firstSet.deletedAt, isNotNull);
    expect(secondSet.deletedAt, isNotNull);
    expect(undoRows, hasLength(2));
    expect(undoRows.every((row) => row.syncAcknowledgedAt == null), isTrue);
    expect(
      undoRows.map((row) {
        final afterImage = jsonDecode(row.afterImage!) as Map<String, Object?>;
        return afterImage['deleted_at'];
      }),
      everyElement(isNotNull),
    );
  });

  test('agent batch undo reports a per-row conflict when a row changed',
      () async {
    final updatedAt = DateTime.utc(2026, 6, 24, 5);
    const setId = '018f6a90-6d7f-7d63-bfc1-6f1025e0c301';
    const batchId = 'agent-batch-conflict';
    await _insertLoggedSetDependencies(database, updatedAt: updatedAt);
    final afterImage = <String, Object?>{
      ..._loggedSetPayload(setId, updatedAt, repsEntered: '5'),
      'exercise_name': 'Back Squat',
    };
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-1',
              'serverClock': '2026-06-24T05:00:01.000Z',
              'changes': <Object?>[
                _pulledChange(
                  id: setId,
                  updatedAt: updatedAt,
                  repsEntered: '5',
                  deviceId: 'agent:agent-key-1',
                  actor: 'agent',
                  batchId: batchId,
                  activityLogId: 'agent:$batchId:$setId',
                  beforeImage: null,
                  afterImage: afterImage,
                  occurredAt: updatedAt,
                ),
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );
    final repositories = TrainingRepositories(database);
    await repositories.sets.updateValues(
      setId,
      values: _repsSet('7'),
      actor: 'app',
    );
    final feedRepository = ActivityFeedRepository(repositories);

    final undo = await feedRepository.undoBatch(batchId);
    final changedSet = await _loggedSet(database, setId);

    expect(undo.appliedEntries, isEmpty);
    expect(undo.undoBatchId, isNull);
    expect(undo.conflicts, hasLength(1));
    expect(undo.conflicts.single.entityTable, AppDatabase.loggedSetsTable);
    expect(undo.conflicts.single.entityId, setId);
    expect(undo.conflicts.single.reason, ActivityLogUndoConflictReason.stale);
    expect(changedSet.repsEntered, '7');
  });

  test(
      'round-trips a logged Compound and Dose as LWW rows with provenance, '
      'with the Dose self-contained when its Compound is absent', () async {
    final repositories = TrainingRepositories(database);
    final tookAt = DateTime.utc(2026, 6, 30, 8);
    final compound = await repositories.protocols.createCompound(
      CompoundDraft(
        name: 'Vitamin D',
        defaultUnit: DoseUnit.internationalUnit,
        defaultRoute: DoseRoute.oral,
        strength: CompoundStrength.parse('1000 IU/capsule'),
      ),
      actor: 'manual',
    );
    final dose = await repositories.protocols.logDose(
      DoseSnapshotDraft.fromCompound(
        compound: (await repositories.protocols.listCompounds()).single,
        amountValue: 1,
        amountEntered: '1',
        unit: DoseUnit.capsule,
        route: DoseRoute.oral,
        tookAt: tookAt,
        provenance: DoseProvenance.manual,
      ),
      actor: 'manual',
    );

    final pushRequests = <http.Request>[];
    final pushRepository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          pushRequests.add(request);
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final changes = body['changes']! as List<Object?>;
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'accepted': changes
                  .cast<Map<String, Object?>>()
                  .map((change) => change['id']! as String)
                  .toList(growable: false),
              'serverClock': '2026-06-30T08:00:01.000Z',
              'applied': changes.cast<Map<String, Object?>>().map((change) {
                return <String, Object?>{
                  'id': change['id'],
                  'updatedAt': change['updatedAt'],
                  'deviceId': 'device-a',
                };
              }).toList(growable: false),
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final pushResult = await pushRepository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );
    final pushedBodies = pushRequests
        .map((request) => jsonDecode(request.body) as Map<String, Object?>)
        .toList(growable: false);
    final pushedChanges = pushedBodies
        .expand((body) => body['changes']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .toList(growable: false);
    final pushedCompound =
        pushedChanges.singleWhere((c) => c['id'] == compound.compoundId);
    final pushedDose = pushedChanges.singleWhere((c) => c['id'] == dose.doseId);
    final compoundPayload = pushedCompound['payload']! as Map<String, Object?>;
    final dosePayload = pushedDose['payload']! as Map<String, Object?>;

    expect(pushResult.pushedCount, 2);
    expect(
      pushedBodies.map((body) => body['entity']),
      <String>[AppDatabase.compoundsTable, AppDatabase.dosesTable],
    );
    expect(compoundPayload['name'], 'Vitamin D');
    // A Dose carries its own snapshot + provenance.
    expect(dosePayload['compound_name'], 'Vitamin D');
    expect(dosePayload['compound_strength'], '1000 IU/capsule');
    expect(dosePayload['provenance'], DoseProvenance.manual.name);

    // Second device pulls ONLY the Dose — the Compound row is absent here, yet
    // the self-contained snapshot round-trips (no Compound dependency).
    final targetDatabase = AppDatabase.inMemory();
    addTearDown(targetDatabase.close);
    final targetRepository = SyncRepository(
      database: targetDatabase,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-dose-1',
              'serverClock': '2026-06-30T08:00:02.000Z',
              'changes': <Object?>[
                _pulledChangeFromPush(
                  entity: AppDatabase.dosesTable,
                  deviceId: 'device-a',
                  change: pushedDose,
                ),
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    final pullResult = await targetRepository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-b',
    );
    final targetRepositories = TrainingRepositories(targetDatabase);
    final localDate = ProtocolDayDate.fromDateTime(tookAt);
    final pulledDay = await targetRepositories.protocols.protocolDay(localDate);
    final storedDose = await (targetDatabase.select(targetDatabase.doses)
          ..where((row) => row.id.equals(dose.doseId)))
        .getSingle();

    expect(pullResult.appliedCount, 1);
    expect(pulledDay.doses, hasLength(1));
    final pulledDose = pulledDay.doses.single;
    expect(pulledDose.id, dose.doseId);
    expect(pulledDose.compoundName, 'Vitamin D');
    expect(
        pulledDose.compoundStrength, CompoundStrength.parse('1000 IU/capsule'));
    expect(pulledDose.provenance, DoseProvenance.manual);
    expect(storedDose.syncDeviceId, 'device-a');
    expect(storedDose.syncPreviouslySynced, isTrue);
    // No Compound was resurrected by the Dose pull (Dose is self-contained).
    expect(await targetRepositories.protocols.listCompounds(), isEmpty);
  });

  test('pulled Dose tombstone soft-deletes the local row without cascade',
      () async {
    final repositories = TrainingRepositories(database);
    final tookAt = DateTime.utc(2026, 6, 30, 8);
    final compound = await repositories.protocols.createCompound(
      CompoundDraft(
        name: 'Creatine',
        defaultUnit: DoseUnit.gram,
        defaultRoute: DoseRoute.oral,
      ),
    );
    final dose = await repositories.protocols.logDose(
      DoseSnapshotDraft(
        compoundId: compound.compoundId,
        compoundName: 'Creatine',
        amountValue: 5,
        amountEntered: '5',
        unit: DoseUnit.gram,
        route: DoseRoute.oral,
        tookAt: tookAt,
      ),
    );
    await (database.update(database.doses)
          ..where((row) => row.id.equals(dose.doseId)))
        .write(
      DosesCompanion(
        syncDeviceId: const Value<String?>('device-a'),
        syncPreviouslySynced: const Value<bool>(true),
        updatedAt: Value<DateTime>(DateTime.utc(2026, 6, 30, 8, 30)),
      ),
    );
    final deletedAt = DateTime.utc(2026, 6, 30, 9);

    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-dose-tombstone',
              'serverClock': '2026-06-30T09:00:01.000Z',
              'changes': <Object?>[
                <String, Object?>{
                  'entity': AppDatabase.dosesTable,
                  'id': dose.doseId,
                  'deviceId': 'device-b',
                  'payload': _doseTombstonePayload(
                    dose.doseId,
                    deletedAt: deletedAt,
                  ),
                  'updatedAt': deletedAt.toIso8601String(),
                  'deletedAt': deletedAt.toIso8601String(),
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    final result = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );
    final pulledDose = await (database.select(database.doses)
          ..where((row) => row.id.equals(dose.doseId)))
        .getSingle();
    final survivingCompounds = await repositories.protocols.listCompounds();

    expect(result.appliedCount, 1);
    expect(pulledDose.deletedAt?.toUtc(), deletedAt);
    expect(pulledDose.syncDeviceId, 'device-b');
    // No cascade: the Compound remains.
    expect(survivingCompounds.map((c) => c.id), contains(compound.compoundId));
  });

  test('LWW keeps the newer Dose snapshot when an older pulled change loses',
      () async {
    final repositories = TrainingRepositories(database);
    final tookAt = DateTime.utc(2026, 6, 30, 8);
    final dose = await repositories.protocols.logDose(
      DoseSnapshotDraft(
        compoundName: 'Caffeine',
        amountValue: 2,
        amountEntered: '2',
        unit: DoseUnit.capsule,
        route: DoseRoute.oral,
        tookAt: tookAt,
      ),
    );
    // Make the local row a previously-synced winner with a newer updated_at.
    final newerUpdatedAt = DateTime.utc(2026, 6, 30, 12);
    await (database.update(database.doses)
          ..where((row) => row.id.equals(dose.doseId)))
        .write(
      DosesCompanion(
        amountValue: const Value<double>(2),
        amountEntered: const Value<String>('2'),
        syncDeviceId: const Value<String?>('device-a'),
        syncPreviouslySynced: const Value<bool>(true),
        updatedAt: Value<DateTime>(newerUpdatedAt),
      ),
    );
    final olderUpdatedAt = DateTime.utc(2026, 6, 30, 9);

    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-lww',
              'serverClock': '2026-06-30T12:00:01.000Z',
              'changes': <Object?>[
                <String, Object?>{
                  'entity': AppDatabase.dosesTable,
                  'id': dose.doseId,
                  'deviceId': 'device-b',
                  'payload': _dosePayload(
                    dose.doseId,
                    amountEntered: '99',
                    updatedAt: olderUpdatedAt,
                  ),
                  'updatedAt': olderUpdatedAt.toIso8601String(),
                  'deletedAt': null,
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    final result = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );
    final keptDose = await (database.select(database.doses)
          ..where((row) => row.id.equals(dose.doseId)))
        .getSingle();

    // The older pulled change loses LWW: it is not applied, local stays '2'.
    expect(result.appliedCount, 0);
    expect(keptDose.amountEntered, '2');
    expect(keptDose.updatedAt.toUtc(), newerUpdatedAt);
  });

  test(
      'pushes a Skip after the Doses and then its removal, and a second '
      'device pulls both onto its Protocol Day (D8)', () async {
    final repositories = TrainingRepositories(database);
    const localDate = ProtocolDayDate(year: 2026, month: 6, day: 30);
    final compound = await repositories.protocols.createCompound(
      CompoundDraft(
        name: 'Creatine',
        defaultUnit: DoseUnit.gram,
        defaultRoute: DoseRoute.oral,
      ),
    );
    final protocol = await repositories.protocols.createProtocol(
      ProtocolDraft(
        name: 'Daily',
        startLocalDate: localDate,
        compoundIds: <String>[compound.compoundId],
      ),
      today: localDate,
    );
    await repositories.protocols.skipPlannedDose(
      ProtocolSkipDraft(
        protocolId: protocol.protocolId,
        compoundId: compound.compoundId,
        localDate: localDate,
        plannedLocalTime: '21:00',
      ),
      today: localDate,
    );
    final skipId =
        (await database.select(database.protocolSkips).get()).single.id;

    final pushRequests = <http.Request>[];
    final pushRepository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          pushRequests.add(request);
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final changes =
              (body['changes']! as List<Object?>).cast<Map<String, Object?>>();
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'accepted': changes
                  .map((change) => change['id']! as String)
                  .toList(growable: false),
              'serverClock': '2026-06-30T08:00:01.000Z',
              'applied': changes
                  .map(
                    (change) => <String, Object?>{
                      'id': change['id'],
                      'updatedAt': change['updatedAt'],
                      'deviceId': 'device-a',
                    },
                  )
                  .toList(growable: false),
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );
    List<Map<String, Object?>> bodies() => pushRequests
        .map((request) => jsonDecode(request.body) as Map<String, Object?>)
        .toList(growable: false);

    await pushRepository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );
    final entities = bodies().map((body) => body['entity']).toList();
    expect(entities, contains(AppDatabase.protocolSkipsTable));
    expect(
      entities.indexOf(AppDatabase.protocolSkipsTable),
      greaterThan(entities.indexOf(AppDatabase.compoundsTable)),
    );
    final skipBody = bodies().singleWhere(
        (body) => body['entity'] == AppDatabase.protocolSkipsTable);
    final pushedSkip = (skipBody['changes']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .single;
    expect(pushedSkip['id'], skipId);
    expect(pushedSkip['payload'], <String, Object?>{
      'id': skipId,
      'protocol_id': protocol.protocolId,
      'compound_id': compound.compoundId,
      'local_date': '2026-06-30',
      'planned_local_time': '21:00',
      'updated_at': pushedSkip['updatedAt'],
      'deleted_at': null,
    });
    final storedSkip =
        await database.select(database.protocolSkips).getSingle();
    expect(storedSkip.syncPreviouslySynced, isTrue);
    expect(storedSkip.syncDeviceId, 'device-a');

    // Undo skip pushes the tombstone, and nothing else is pending. Stored
    // stamps have whole seconds, so the pause keeps the removal's after the
    // Skip's, as a user's later tap would; a tie would lose LWW.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await repositories.protocols.unskipPlannedDose(skipId);
    pushRequests.clear();
    await pushRepository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );
    expect(
      bodies().map((body) => body['entity']),
      <String>[AppDatabase.protocolSkipsTable],
    );
    final pushedRemoval = (bodies().single['changes']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .single;
    expect(pushedRemoval['deletedAt'], isNotNull);

    // A second device, with no Protocol or Compound rows, pulls the Skip and
    // then its removal: both are soft references.
    final targetDatabase = AppDatabase.inMemory();
    addTearDown(targetDatabase.close);
    var page = 0;
    final targetRepository = SyncRepository(
      database: targetDatabase,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((_) async {
          page += 1;
          final change = page == 1 ? pushedSkip : pushedRemoval;
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-skip-$page',
              'serverClock': '2026-06-30T08:00:0$page.000Z',
              'changes': <Object?>[
                _pulledChangeFromPush(
                  entity: AppDatabase.protocolSkipsTable,
                  deviceId: 'device-a',
                  change: change,
                ),
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );
    final targetRepositories = TrainingRepositories(targetDatabase);

    final first = await targetRepository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-b',
    );
    expect(first.appliedCount, 1);
    final pulledDay = await targetRepositories.protocols.protocolDay(localDate);
    expect(pulledDay.skips.single.id, skipId);
    expect(pulledDay.skips.single.plannedLocalTime, '21:00');
    final pulledRow =
        await targetDatabase.select(targetDatabase.protocolSkips).getSingle();
    expect(pulledRow.syncDeviceId, 'device-a');
    expect(pulledRow.syncPreviouslySynced, isTrue);
    expect(
      (await targetRepositories.activityLog.listEntries())
          .map((entry) => entry.entityTable),
      contains(AppDatabase.protocolSkipsTable),
    );

    final second = await targetRepository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-b',
    );
    expect(second.appliedCount, 1);
    expect(
      (await targetRepositories.protocols.protocolDay(localDate)).skips,
      isEmpty,
    );
  });

  test(
      'a full re-sync tombstones a previously synced Skip the snapshot no '
      'longer has, and keeps a local-only one (D8)', () async {
    final localUpdatedAt = DateTime.utc(2026, 6, 22, 8);
    final snapshotUpdatedAt = DateTime.utc(2026, 6, 22, 9);
    const keptId = '018f6a90-6d7f-7d63-bfc1-6f1025e0d001';
    const missingId = '018f6a90-6d7f-7d63-bfc1-6f1025e0d002';
    const localOnlyId = '018f6a90-6d7f-7d63-bfc1-6f1025e0d003';
    Future<void> insertSkip(String id, {required bool previouslySynced}) {
      return database.into(database.protocolSkips).insert(
            ProtocolSkipsCompanion.insert(
              id: id,
              protocolId: 'protocol-1',
              compoundId: 'compound-1',
              localDate: '2026-06-21',
              plannedLocalTime: const Value<String?>('09:00'),
              syncDeviceId: const Value<String?>('device-b'),
              syncPreviouslySynced: Value<bool>(previouslySynced),
              updatedAt: localUpdatedAt,
            ),
          );
    }

    await insertSkip(keptId, previouslySynced: true);
    await insertSkip(missingId, previouslySynced: true);
    await insertSkip(localOnlyId, previouslySynced: false);
    await database.into(database.syncStates).insert(
          SyncStatesCompanion.insert(
            id: syncStateId,
            pullCursor: const Value<String?>(
              '2000-01-01T00:00:00.000Z|expired-row',
            ),
            updatedAt: localUpdatedAt,
          ),
        );

    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          if (request.url.path == '/sync/pull' && body['mode'] == null) {
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': syncProtocolVersion,
                'fullResyncRequired': true,
                'nextCursor': '2000-01-01T00:00:00.000Z|expired-row',
                'serverClock': '2026-06-22T09:00:00.000Z',
                'changes': <Object?>[],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/sync/pull' &&
              body['mode'] == 'snapshot' &&
              body['cursor'] == null) {
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': syncProtocolVersion,
                'fullResyncRequired': false,
                'nextCursor': 'snapshot-cursor-1',
                'serverClock': '2026-06-22T09:00:02.000Z',
                'changes': <Object?>[
                  <String, Object?>{
                    'entity': AppDatabase.protocolSkipsTable,
                    'id': keptId,
                    'deviceId': 'device-b',
                    'payload': <String, Object?>{
                      'id': keptId,
                      'protocol_id': 'protocol-1',
                      'compound_id': 'compound-1',
                      'local_date': '2026-06-21',
                      'planned_local_time': '09:00',
                      'updated_at': snapshotUpdatedAt.toIso8601String(),
                      'deleted_at': null,
                    },
                    'updatedAt': snapshotUpdatedAt.toIso8601String(),
                    'deletedAt': null,
                  },
                ],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/sync/pull' &&
              body['mode'] == 'snapshot' &&
              body['cursor'] == 'snapshot-cursor-1') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': syncProtocolVersion,
                'fullResyncRequired': false,
                'nextCursor': 'snapshot-cursor-1',
                'serverClock': '2026-06-22T09:00:03.000Z',
                'changes': <Object?>[],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          fail('Unexpected sync request: ${request.url.path} ${request.body}');
        }),
      ),
    );

    final result = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );
    Future<ProtocolSkipRow> row(String id) =>
        (database.select(database.protocolSkips)
              ..where((row) => row.id.equals(id)))
            .getSingle();

    expect(result.fullResyncRequired, isTrue);
    expect((await row(keptId)).deletedAt, isNull);
    expect((await row(keptId)).updatedAt.toUtc(), snapshotUpdatedAt);
    expect((await row(missingId)).deletedAt, isNotNull);
    expect((await row(localOnlyId)).deletedAt, isNull);
  });

  test(
      'round-trips a Protocol and its member Schedule as LWW rows with '
      'provenance', () async {
    final repositories = TrainingRepositories(database);
    final compound = await repositories.protocols.createCompound(
      CompoundDraft(
        name: 'Creatine',
        defaultUnit: DoseUnit.gram,
        defaultRoute: DoseRoute.oral,
      ),
    );
    final created = await repositories.protocols.createProtocol(
      ProtocolDraft(
        name: 'Lean bulk',
        startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
        compoundIds: <String>[compound.compoundId],
        schedulesByCompoundId: <String, ScheduleDraft?>{
          compound.compoundId: ScheduleDraft(
            rule: TimedScheduleRule(
              days: const DailyScheduleDays(),
              times: const <String>['09:00'],
            ),
            doseAmountValue: 5,
            doseAmountEntered: '5',
            doseUnit: DoseUnit.gram,
            route: DoseRoute.oral,
          ),
        },
        targetOutcomes: const <ProtocolTargetOutcomeDraft>[
          ProtocolTargetOutcomeDraft.performance,
        ],
      ),
    );

    final pushRequests = <http.Request>[];
    final pushRepository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          pushRequests.add(request);
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final changes = body['changes']! as List<Object?>;
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'accepted': changes
                  .cast<Map<String, Object?>>()
                  .map((change) => change['id']! as String)
                  .toList(growable: false),
              'serverClock': '2026-07-01T00:00:01.000Z',
              'applied': changes.cast<Map<String, Object?>>().map((change) {
                return <String, Object?>{
                  'id': change['id'],
                  'updatedAt': change['updatedAt'],
                  'deviceId': 'device-a',
                };
              }).toList(growable: false),
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final pushResult = await pushRepository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );
    final pushedBodies = pushRequests
        .map((request) => jsonDecode(request.body) as Map<String, Object?>)
        .toList(growable: false);
    final pushedChanges = pushedBodies
        .expand((body) => body['changes']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .toList(growable: false);
    Map<String, Object?> pushedChangeFor(String id) =>
        pushedChanges.singleWhere((change) => change['id'] == id);
    final pushedCompound = pushedChangeFor(compound.compoundId);
    final pushedProtocol = pushedChangeFor(created.protocolId);
    final protocolCompoundRow = await (database.select(
      database.protocolCompounds,
    )..where((row) => row.protocolId.equals(created.protocolId)))
        .getSingle();
    final scheduleRow = await (database.select(database.schedules)
          ..where(
            (row) => row.protocolCompoundId.equals(protocolCompoundRow.id),
          ))
        .getSingle();
    final targetOutcomeRow = await (database.select(
      database.protocolTargetOutcomes,
    )..where((row) => row.protocolId.equals(created.protocolId)))
        .getSingle();
    final pushedProtocolCompound = pushedChangeFor(protocolCompoundRow.id);
    final pushedSchedule = pushedChangeFor(scheduleRow.id);
    final pushedTargetOutcome = pushedChangeFor(targetOutcomeRow.id);

    expect(pushResult.pushedCount, 5);
    expect(
      pushedBodies.map((body) => body['entity']),
      <String>[
        AppDatabase.compoundsTable,
        AppDatabase.protocolsTable,
        AppDatabase.protocolCompoundsTable,
        AppDatabase.protocolTargetOutcomesTable,
        AppDatabase.schedulesTable,
      ],
    );
    final protocolPayload = pushedProtocol['payload']! as Map<String, Object?>;
    final schedulePayload = pushedSchedule['payload']! as Map<String, Object?>;
    expect(protocolPayload['name'], 'Lean bulk');
    expect(protocolPayload['start_local_date'], '2026-07-01');
    expect(protocolPayload['end_local_date'], isNull);
    expect(protocolPayload['period'], isNull);
    expect(protocolPayload['reminders_enabled'], isFalse);
    expect(schedulePayload['dose_amount_entered'], '5');
    expect(schedulePayload['effective_from'], '2026-07-01');
    expect(
      jsonDecode(schedulePayload['rule']! as String),
      <String, Object?>{
        'v': 1,
        'kind': 'timed',
        'days': <String, Object?>{'kind': 'daily'},
        'times': <Object?>['09:00'],
      },
    );
    expect(schedulePayload, isNot(contains('frequency')));

    // Second device pulls the Compound, the Protocol, its member, its target
    // outcome, and its Schedule — a Drift FK chain (Protocol ->
    // ProtocolCompound -> Schedule) that must apply in dependency order.
    final targetDatabase = AppDatabase.inMemory();
    addTearDown(targetDatabase.close);
    final targetRepository = SyncRepository(
      database: targetDatabase,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-protocol-1',
              'serverClock': '2026-07-01T00:00:02.000Z',
              'changes': <Object?>[
                _pulledChangeFromPush(
                  entity: AppDatabase.compoundsTable,
                  deviceId: 'device-a',
                  change: pushedCompound,
                ),
                _pulledChangeFromPush(
                  entity: AppDatabase.protocolsTable,
                  deviceId: 'device-a',
                  change: pushedProtocol,
                ),
                _pulledChangeFromPush(
                  entity: AppDatabase.protocolCompoundsTable,
                  deviceId: 'device-a',
                  change: pushedProtocolCompound,
                ),
                _pulledChangeFromPush(
                  entity: AppDatabase.protocolTargetOutcomesTable,
                  deviceId: 'device-a',
                  change: pushedTargetOutcome,
                ),
                _pulledChangeFromPush(
                  entity: AppDatabase.schedulesTable,
                  deviceId: 'device-a',
                  change: pushedSchedule,
                ),
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    final pullResult = await targetRepository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-b',
    );
    final targetRepositories = TrainingRepositories(targetDatabase);
    final pulledProtocols = await targetRepositories.protocols.listProtocols();
    final storedProtocol = await (targetDatabase.select(
      targetDatabase.protocols,
    )..where((row) => row.id.equals(created.protocolId)))
        .getSingle();

    expect(pullResult.appliedCount, 5);
    expect(pulledProtocols, hasLength(1));
    final pulledProtocol = pulledProtocols.single;
    expect(pulledProtocol.name, 'Lean bulk');
    expect(pulledProtocol.members, hasLength(1));
    final pulledMember = pulledProtocol.members.single;
    expect(pulledMember.compoundId, compound.compoundId);
    final pulledVersion = pulledMember.currentVersion;
    expect(pulledVersion, isNotNull);
    expect(pulledVersion!.doseAmountEntered, '5');
    expect(
      pulledVersion.effectiveFrom,
      const ProtocolDayDate(year: 2026, month: 7, day: 1),
    );
    expect(
      (pulledVersion.rule as TimedScheduleRule).times,
      <String>['09:00'],
    );
    expect(pulledProtocol.targetOutcomes, hasLength(1));
    expect(
      pulledProtocol.targetOutcomes.single.kind,
      ProtocolOutcomeKind.performance,
    );
    expect(storedProtocol.syncDeviceId, 'device-a');
    expect(storedProtocol.syncPreviouslySynced, isTrue);
  });

  test(
      'pulled Protocol archive tombstone soft-deletes the local row without '
      'cascading to a Dose', () async {
    final repositories = TrainingRepositories(database);
    final compound = await repositories.protocols.createCompound(
      CompoundDraft(
        name: 'Creatine',
        defaultUnit: DoseUnit.gram,
        defaultRoute: DoseRoute.oral,
      ),
    );
    final created = await repositories.protocols.createProtocol(
      ProtocolDraft(
        name: 'Lean bulk',
        startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
        compoundIds: <String>[compound.compoundId],
      ),
    );
    final dose = await repositories.protocols.logDose(
      DoseSnapshotDraft(
        compoundId: compound.compoundId,
        compoundName: 'Creatine',
        amountValue: 5,
        amountEntered: '5',
        unit: DoseUnit.gram,
        route: DoseRoute.oral,
        tookAt: DateTime.utc(2026, 7, 1, 8),
        protocolId: created.protocolId,
        protocolName: 'Lean bulk',
      ),
    );
    await (database.update(database.protocols)
          ..where((row) => row.id.equals(created.protocolId)))
        .write(
      ProtocolsCompanion(
        syncDeviceId: const Value<String?>('device-a'),
        syncPreviouslySynced: const Value<bool>(true),
        updatedAt: Value<DateTime>(DateTime.utc(2026, 7, 1, 8, 30)),
      ),
    );
    final deletedAt = DateTime.utc(2026, 7, 1, 9);

    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-protocol-tombstone',
              'serverClock': '2026-07-01T09:00:01.000Z',
              'changes': <Object?>[
                <String, Object?>{
                  'entity': AppDatabase.protocolsTable,
                  'id': created.protocolId,
                  'deviceId': 'device-b',
                  'payload': <String, Object?>{
                    'id': created.protocolId,
                    'name': 'Lean bulk',
                    'start_local_date': '2026-07-01',
                    'end_local_date': null,
                    'period': null,
                    'reminders_enabled': false,
                    'archived_on': '2026-07-01',
                    'updated_at': deletedAt.toIso8601String(),
                    'deleted_at': deletedAt.toIso8601String(),
                  },
                  'updatedAt': deletedAt.toIso8601String(),
                  'deletedAt': deletedAt.toIso8601String(),
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    final result = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );
    final pulledProtocol = await (database.select(database.protocols)
          ..where((row) => row.id.equals(created.protocolId)))
        .getSingle();
    final doseRow = await (database.select(database.doses)
          ..where((row) => row.id.equals(dose.doseId)))
        .getSingle();

    expect(result.appliedCount, 1);
    expect(pulledProtocol.deletedAt?.toUtc(), deletedAt);
    expect(pulledProtocol.archivedOn, '2026-07-01');
    expect(pulledProtocol.syncDeviceId, 'device-b');
    // No cascade: the tagged Dose keeps its tag and remains intact.
    expect(doseRow.deletedAt, isNull);
    expect(doseRow.protocolId, created.protocolId);
    expect(doseRow.protocolName, 'Lean bulk');
  });

  test(
      'round-trips an ExerciseCategory and its member Exercise as LWW rows '
      'with provenance', () async {
    final repositories = TrainingRepositories(database);
    final categoryId = await repositories.catalog.createCategory(
      const ExerciseCategoryDraft(name: 'Back', colorHex: '#3366CC'),
    );
    final exerciseId = await repositories.exercises.create(
      ExerciseDraft(
        name: 'Barbell Row',
        type: ExerciseType(<DimensionId>[
          DimensionId.load,
          DimensionId.reps,
        ]),
        categoryId: categoryId,
      ),
    );
    final pushRequests = <http.Request>[];
    final pushRepository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          pushRequests.add(request);
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final changes = body['changes']! as List<Object?>;
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'accepted': changes
                  .cast<Map<String, Object?>>()
                  .map((change) => change['id']! as String)
                  .toList(growable: false),
              'serverClock': '2026-07-01T00:00:01.000Z',
              'applied': changes.cast<Map<String, Object?>>().map((change) {
                return <String, Object?>{
                  'id': change['id'],
                  'updatedAt': change['updatedAt'],
                  'deviceId': 'device-a',
                };
              }).toList(growable: false),
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final pushResult = await pushRepository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );
    final pushedBodies = pushRequests
        .map((request) => jsonDecode(request.body) as Map<String, Object?>)
        .toList(growable: false);
    final pushedChanges = pushedBodies
        .expand((body) => body['changes']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .toList(growable: false);
    Map<String, Object?> pushedChangeFor(String id) =>
        pushedChanges.singleWhere((change) => change['id'] == id);
    final pushedCategory = pushedChangeFor(categoryId);
    final pushedExercise = pushedChangeFor(exerciseId);

    expect(pushResult.pushedCount, 2);
    expect(
      pushedBodies.map((body) => body['entity']),
      <String>[
        AppDatabase.exerciseCategoriesTable,
        AppDatabase.exercisesTable,
      ],
    );
    final categoryPayload = pushedCategory['payload']! as Map<String, Object?>;
    final exercisePayload = pushedExercise['payload']! as Map<String, Object?>;
    expect(categoryPayload['name'], 'Back');
    expect(exercisePayload['name'], 'Barbell Row');
    expect(exercisePayload['category_id'], categoryId);
    expect(exercisePayload['library_origin'], 'user');

    // Second device pulls the ExerciseCategory before its member Exercise — a
    // Drift FK (`categoryId`) that must apply in dependency order.
    final targetDatabase = AppDatabase.inMemory();
    addTearDown(targetDatabase.close);
    final targetRepository = SyncRepository(
      database: targetDatabase,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-catalog-1',
              'serverClock': '2026-07-01T00:00:02.000Z',
              'changes': <Object?>[
                _pulledChangeFromPush(
                  entity: AppDatabase.exerciseCategoriesTable,
                  deviceId: 'device-a',
                  change: pushedCategory,
                ),
                _pulledChangeFromPush(
                  entity: AppDatabase.exercisesTable,
                  deviceId: 'device-a',
                  change: pushedExercise,
                ),
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    final pullResult = await targetRepository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-b',
    );
    final storedCategory = await (targetDatabase.select(
      targetDatabase.exerciseCategories,
    )..where((row) => row.id.equals(categoryId)))
        .getSingle();
    final storedExercise = await (targetDatabase.select(
      targetDatabase.exercises,
    )..where((row) => row.id.equals(exerciseId)))
        .getSingle();

    expect(pullResult.appliedCount, 2);
    expect(storedCategory.name, 'Back');
    expect(storedCategory.syncDeviceId, 'device-a');
    expect(storedCategory.syncPreviouslySynced, isTrue);
    expect(storedExercise.name, 'Barbell Row');
    expect(storedExercise.categoryId, categoryId);
    expect(storedExercise.syncDeviceId, 'device-a');
    expect(storedExercise.syncPreviouslySynced, isTrue);
  });

  test(
      'pulled Exercise archive tombstone soft-deletes the local row without '
      'cascading to the ExerciseCategory', () async {
    final repositories = TrainingRepositories(database);
    final categoryId = await repositories.catalog.createCategory(
      const ExerciseCategoryDraft(name: 'Legs'),
    );
    final exerciseId = await repositories.exercises.create(
      ExerciseDraft(
        name: 'Back Squat',
        type: ExerciseType(<DimensionId>[
          DimensionId.load,
          DimensionId.reps,
        ]),
        categoryId: categoryId,
      ),
    );
    await (database.update(database.exercises)
          ..where((row) => row.id.equals(exerciseId)))
        .write(
      ExercisesCompanion(
        syncDeviceId: const Value<String?>('device-a'),
        syncPreviouslySynced: const Value<bool>(true),
        updatedAt: Value<DateTime>(DateTime.utc(2026, 7, 1, 0, 30)),
      ),
    );
    final deletedAt = DateTime.utc(2026, 7, 1, 1);

    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-exercise-tombstone',
              'serverClock': '2026-07-01T01:00:01.000Z',
              'changes': <Object?>[
                <String, Object?>{
                  'entity': AppDatabase.exercisesTable,
                  'id': exerciseId,
                  'deviceId': 'device-b',
                  'payload': _exerciseTombstonePayload(
                    exerciseId,
                    categoryId: categoryId,
                    deletedAt: deletedAt,
                  ),
                  'updatedAt': deletedAt.toIso8601String(),
                  'deletedAt': deletedAt.toIso8601String(),
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    final result = await repository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-a',
    );
    final pulledExercise = await (database.select(database.exercises)
          ..where((row) => row.id.equals(exerciseId)))
        .getSingle();
    final categoryRow = await (database.select(database.exerciseCategories)
          ..where((row) => row.id.equals(categoryId)))
        .getSingle();

    expect(result.appliedCount, 1);
    expect(pulledExercise.deletedAt?.toUtc(), deletedAt);
    expect(pulledExercise.syncDeviceId, 'device-b');
    // No cascade: the ExerciseCategory remains live.
    expect(categoryRow.deletedAt, isNull);
  });

  test(
      'does not push a Platform Library exercise even after '
      'seeding writes an Activity Log entry', () async {
    final repositories = TrainingRepositories(database);
    final categoryId = await repositories.catalog.createCategory(
      const ExerciseCategoryDraft(name: 'Chest'),
    );
    // Simulate a Platform Library row the way the bundled seed creates one:
    // `libraryOrigin: platform`, with an Activity Log entry recorded exactly
    // like a user write (ensurePlatformLibrarySeeded appends one per row).
    const platformExerciseId = 'platform-exercise-1';
    final seededAt = DateTime.utc(2026, 7, 1);
    await database.into(database.exercises).insert(
          ExercisesCompanion.insert(
            id: platformExerciseId,
            libraryOrigin: const Value<String>('platform'),
            name: 'Bench Press',
            dimensionIds: jsonEncode(<String>['load', 'reps']),
            categoryId: Value<String?>(categoryId),
            updatedAt: seededAt,
          ),
        );
    await database.into(database.activityLog).insert(
          ActivityLogCompanion.insert(
            id: 'activity-platform-seed',
            actor: 'platform_seed',
            batchId: 'batch-platform-seed',
            entityTable: AppDatabase.exercisesTable,
            entityId: platformExerciseId,
            beforeImage: const Value<String?>(null),
            afterImage: Value<String?>(
              jsonEncode(<String, Object?>{
                'id': platformExerciseId,
                'library_origin': 'platform',
                'name': 'Bench Press',
                'category_id': categoryId,
                'updated_at': seededAt.toIso8601String(),
                'deleted_at': null,
              }),
            ),
            occurredAt: seededAt,
            updatedAt: seededAt,
          ),
        );

    final pushRequests = <http.Request>[];
    final repository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          pushRequests.add(request);
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'accepted': <String>[],
              'serverClock': '2026-07-01T00:00:01.000Z',
              'applied': <Object?>[],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final pushResult = await repository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );
    final acknowledgedEntry = await (database.select(database.activityLog)
          ..where((row) => row.id.equals('activity-platform-seed')))
        .getSingle();

    // The Platform row is never pushed to the server — no request
    // carries its entity/id — but its Activity Log entry is acknowledged so
    // it is never retried. (The Category push above is a legitimate,
    // unrelated User Library write and is not part of this assertion.)
    expect(
      pushRequests.any((request) {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        if (body['entity'] != AppDatabase.exercisesTable) {
          return false;
        }
        final changes =
            (body['changes']! as List<Object?>).cast<Map<String, Object?>>();
        return changes.any((change) => change['id'] == platformExerciseId);
      }),
      isFalse,
    );
    expect(
      pushResult.acceptedEntityIds.contains(platformExerciseId),
      isFalse,
    );
    expect(acknowledgedEntry.syncAcknowledgedAt, isNotNull);
  });

  test(
      'pushes a saved Nutrition Goal, and a second device pulls it back and '
      'sees a cleared Goal as a tombstone', () async {
    final repositories = TrainingRepositories(database);
    final goalId = await repositories.nutrition.saveNutritionGoal(
      NutritionGoalTarget(
        nutrient: NutrientId.energy,
        value: 2200,
        entered: '2200',
      ),
      actor: 'app',
    );

    final pushRequests = <http.Request>[];
    final pushRepository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          pushRequests.add(request);
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final changes = body['changes']! as List<Object?>;
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'accepted': changes
                  .cast<Map<String, Object?>>()
                  .map((change) => change['id']! as String)
                  .toList(growable: false),
              'serverClock': '2026-06-30T08:00:01.000Z',
              'applied': changes.cast<Map<String, Object?>>().map((change) {
                return <String, Object?>{
                  'id': change['id'],
                  'updatedAt': change['updatedAt'],
                  'deviceId': 'device-a',
                };
              }).toList(growable: false),
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final pushResult = await pushRepository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );
    final pushedBodies = pushRequests
        .map((request) => jsonDecode(request.body) as Map<String, Object?>)
        .toList(growable: false);
    final goalPushBody = pushedBodies.singleWhere(
      (body) => body['entity'] == AppDatabase.nutritionGoalsTable,
    );
    final pushedChanges = (goalPushBody['changes']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final pushedGoal = pushedChanges.singleWhere((c) => c['id'] == goalId);
    final goalPayload = pushedGoal['payload']! as Map<String, Object?>;

    expect(pushResult.pushedCount, greaterThanOrEqualTo(1));
    expect(goalPayload['nutrient_id'], 'energy');
    expect(goalPayload['target_value'], 2200);

    // Second device pulls the Goal.
    final targetDatabase = AppDatabase.inMemory();
    addTearDown(targetDatabase.close);
    final targetRepository = SyncRepository(
      database: targetDatabase,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-goal-1',
              'serverClock': '2026-06-30T08:00:02.000Z',
              'changes': <Object?>[
                _pulledChangeFromPush(
                  entity: AppDatabase.nutritionGoalsTable,
                  deviceId: 'device-a',
                  change: pushedGoal,
                ),
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    final pullResult = await targetRepository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-b',
    );
    final targetRepositories = TrainingRepositories(targetDatabase);
    final pulledGoal = await targetRepositories.nutrition.getNutritionGoal(
      NutrientId.energy,
    );

    expect(pullResult.appliedCount, 1);
    // A non-Settings pull must NOT flag userSettingsApplied — no
    // spurious settingsControllerProvider invalidation.
    expect(pullResult.userSettingsApplied, isFalse);
    expect(pulledGoal, isNotNull);
    expect(pulledGoal!.target.value, 2200);

    // Clearing the Goal locally (tombstone via deleted_at) pushes and the
    // second device's pull soft-deletes its local row — no cascade, ordinary
    // archive semantics. `clearNutritionGoal` stamps `updatedAt`
    // from the real clock, which can tie the create's `updatedAt` at
    // whole-second resolution; force it forward deterministically so this
    // test's LWW ordering never depends on real elapsed wall time.
    await repositories.nutrition.clearNutritionGoal(
      NutrientId.energy,
      actor: 'app',
    );
    // `clearNutritionGoal` stamps `updatedAt` from the real clock, which can
    // tie the create's `updatedAt` at whole-second resolution and lose LWW
    // (same device id). Force both the row and its not-yet-pushed Activity
    // Log afterImage forward deterministically so this test's LWW ordering
    // never depends on real elapsed wall time.
    final clearedUpdatedAt =
        DateTime.now().toUtc().add(const Duration(days: 1));
    await (database.update(database.nutritionGoals)
          ..where((row) => row.id.equals(goalId)))
        .write(
      NutritionGoalsCompanion(updatedAt: Value<DateTime>(clearedUpdatedAt)),
    );
    final pendingClearLogRow = await (database.select(database.activityLog)
          ..where((row) => row.entityId.equals(goalId))
          ..where((row) => row.syncAcknowledgedAt.isNull()))
        .getSingle();
    final pendingAfterImage =
        jsonDecode(pendingClearLogRow.afterImage!) as Map<String, Object?>;
    await (database.update(database.activityLog)
          ..where((row) => row.id.equals(pendingClearLogRow.id)))
        .write(
      ActivityLogCompanion(
        afterImage: Value<String?>(
          jsonEncode(<String, Object?>{
            ...pendingAfterImage,
            'updated_at': clearedUpdatedAt.toIso8601String(),
            'deleted_at': clearedUpdatedAt.toIso8601String(),
          }),
        ),
      ),
    );
    pushRequests.clear();
    final clearPushResult = await pushRepository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );
    final clearPushedBodies = pushRequests
        .map((request) => jsonDecode(request.body) as Map<String, Object?>)
        .toList(growable: false);
    final clearGoalPushBody = clearPushedBodies.singleWhere(
      (body) => body['entity'] == AppDatabase.nutritionGoalsTable,
    );
    final clearPushedChanges = (clearGoalPushBody['changes']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final clearPushedGoal =
        clearPushedChanges.singleWhere((c) => c['id'] == goalId);
    expect(clearPushResult.pushedCount, greaterThanOrEqualTo(1));
    expect(clearPushedGoal['deletedAt'], isNotNull);

    final targetRepositoryRound2 = SyncRepository(
      database: targetDatabase,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-goal-2',
              'serverClock': '2026-06-30T08:00:03.000Z',
              'changes': <Object?>[
                _pulledChangeFromPush(
                  entity: AppDatabase.nutritionGoalsTable,
                  deviceId: 'device-a',
                  change: clearPushedGoal,
                ),
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );
    final clearPullResult = await targetRepositoryRound2.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-b',
    );
    final pulledGoalAfterClear =
        await targetRepositories.nutrition.getNutritionGoal(NutrientId.energy);

    expect(clearPullResult.appliedCount, 1);
    expect(pulledGoalAfterClear, isNull);
  });

  test(
      'pushes account-level Settings (user_settings singleton) and a second '
      'device pulls the change back onto its account row', () async {
    final repositories = TrainingRepositories(database);
    // A local account-level Settings write mints the synced singleton row and
    // its pending Activity Log entry (the same path the settings UI/agent take).
    await repositories.accountSettings.save(
      const AccountSettings(
        themePreference: 'dark',
        unitSystem: 'imperial',
        weekStartDay: 'sunday',
        defaultWeightIncrement: 5,
        homeScreenDisplay: 'compact',
        prTrackingEnabled: false,
        markSetsCompleteByDefault: true,
        autoSelectNextSet: false,
      ),
      actor: 'app',
    );
    final settingsRow =
        (await database.select(database.userSettings).get()).single;
    final settingsId = settingsRow.id;

    final pushRequests = <http.Request>[];
    final pushRepository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          pushRequests.add(request);
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final changes = body['changes']! as List<Object?>;
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'accepted': changes
                  .cast<Map<String, Object?>>()
                  .map((change) => change['id']! as String)
                  .toList(growable: false),
              'serverClock': '2026-06-30T08:00:01.000Z',
              'applied': changes.cast<Map<String, Object?>>().map((change) {
                return <String, Object?>{
                  'id': change['id'],
                  'updatedAt': change['updatedAt'],
                  'deviceId': 'device-a',
                };
              }).toList(growable: false),
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final pushResult = await pushRepository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );

    // The push carries the user_settings entity with the account payload —
    // exercising _pushPendingUserSettingsWithClient / _loadPendingUserSettingsRows.
    final pushedBodies = pushRequests
        .map((request) => jsonDecode(request.body) as Map<String, Object?>)
        .toList(growable: false);
    final settingsPushBody = pushedBodies.singleWhere(
      (body) => body['entity'] == AppDatabase.userSettingsTable,
    );
    final pushedChanges = (settingsPushBody['changes']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final pushedSettings =
        pushedChanges.singleWhere((c) => c['id'] == settingsId);
    final settingsPayload = pushedSettings['payload']! as Map<String, Object?>;

    expect(pushResult.pushedCount, greaterThanOrEqualTo(1));
    expect(settingsPayload['theme_preference'], 'dark');
    expect(settingsPayload['unit_system'], 'imperial');
    expect(settingsPayload['auto_select_next_set'], false);

    // The pushed Activity Log entry is acknowledged so it is never retried —
    // exercising _acknowledgeUserSettingsPushResponse.
    final acknowledged = await (database.select(database.activityLog)
          ..where((row) => row.entityId.equals(settingsId)))
        .getSingle();
    expect(acknowledged.syncAcknowledgedAt, isNotNull);

    // A second device pulls the change through the dispatcher, which routes the
    // user_settings entity to _applyPulledUserSettingsChange /
    // AccountSettingsRepository.applySyncImage.
    final targetDatabase = AppDatabase.inMemory();
    addTearDown(targetDatabase.close);
    final targetRepository = SyncRepository(
      database: targetDatabase,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-settings-1',
              'serverClock': '2026-06-30T08:00:02.000Z',
              'changes': <Object?>[
                _pulledChangeFromPush(
                  entity: AppDatabase.userSettingsTable,
                  deviceId: 'device-a',
                  change: pushedSettings,
                ),
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    final pullResult = await targetRepository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-b',
    );
    final targetRepositories = TrainingRepositories(targetDatabase);
    final pulledSettings = await targetRepositories.accountSettings.load();

    expect(pullResult.appliedCount, 1);
    // The pull reports it touched account Settings so the Riverpod callers can
    // invalidate settingsControllerProvider.
    expect(pullResult.userSettingsApplied, isTrue);
    expect(pulledSettings, isNotNull);
    expect(pulledSettings!.themePreference, 'dark');
    expect(pulledSettings.unitSystem, 'imperial');
    expect(pulledSettings.weekStartDay, 'sunday');
    expect(pulledSettings.defaultWeightIncrement, 5);
    expect(pulledSettings.homeScreenDisplay, 'compact');
    expect(pulledSettings.prTrackingEnabled, isFalse);
    expect(pulledSettings.markSetsCompleteByDefault, isTrue);
    expect(pulledSettings.autoSelectNextSet, isFalse);
  });

  test(
      'a second device does not overwrite a newer local account Settings row on '
      'pull (LWW; user_settings)', () async {
    // Seed the pulling device with a NEWER local account row; an older pulled
    // change must lose LWW and leave the local value intact — the same
    // _applyPulledUserSettingsChange path, exercised for the loser branch.
    final localRepositories = TrainingRepositories(database);
    await localRepositories.accountSettings.save(
      const AccountSettings(
        themePreference: 'light',
        unitSystem: 'metric',
        weekStartDay: 'monday',
        defaultWeightIncrement: 2.5,
        homeScreenDisplay: 'comfortable',
        prTrackingEnabled: true,
        markSetsCompleteByDefault: false,
        autoSelectNextSet: true,
      ),
      actor: 'app',
    );
    final localRow =
        (await database.select(database.userSettings).get()).single;
    // Force the local row's updated_at far into the future so it wins LWW.
    final newerUpdatedAt =
        DateTime.now().toUtc().add(const Duration(days: 3650));
    await (database.update(database.userSettings)
          ..where((row) => row.id.equals(localRow.id)))
        .write(UserSettingsCompanion(
      updatedAt: Value<DateTime>(newerUpdatedAt),
    ));

    final targetRepository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-settings-lww',
              'serverClock': '2026-06-30T08:00:02.000Z',
              'changes': <Object?>[
                <String, Object?>{
                  'entity': AppDatabase.userSettingsTable,
                  'id': localRow.id,
                  'deviceId': 'device-remote',
                  'payload': <String, Object?>{
                    'id': localRow.id,
                    'theme_preference': 'dark',
                    'unit_system': 'imperial',
                    'week_start_day': 'sunday',
                    'default_weight_increment': 5,
                    'home_screen_display': 'compact',
                    'pr_tracking_enabled': false,
                    'mark_sets_complete_by_default': true,
                    'auto_select_next_set': false,
                    'updated_at': '2020-01-01T00:00:00.000Z',
                    'deleted_at': null,
                  },
                  'updatedAt': '2020-01-01T00:00:00.000Z',
                  'deletedAt': null,
                  'activityLogId': 'remote-log-1',
                  'actor': 'sync',
                  'batchId': 'remote-batch-1',
                  'beforeImage': null,
                  'afterImage': null,
                  'occurredAt': '2020-01-01T00:00:00.000Z',
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    await targetRepository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-b',
    );

    // The older pulled change lost LWW: the local (newer) values survive.
    final afterPull = await localRepositories.accountSettings.load();
    expect(afterPull, isNotNull);
    expect(afterPull!.themePreference, 'light');
    expect(afterPull.unitSystem, 'metric');
  });

  test(
      'pushes a created User Food and Meal Type, and a second device pulls '
      'them back as ordinary LWW rows', () async {
    final repositories = TrainingRepositories(database);
    final foodId = await repositories.nutrition.createUserFood(
      UserFoodDraft(
        name: 'Chicken Breast',
        nutrientsPer100: _offNutrientsPer100(),
        isLiquid: false,
        servingLabel: 'serving',
        servingSize: 100,
      ),
    );
    final mealTypeId = await repositories.nutrition.createMealType(
      const MealTypeDraft(name: 'Second Breakfast', sortOrder: 4),
    );

    final pushRequests = <http.Request>[];
    final pushRepository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          pushRequests.add(request);
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final changes = body['changes']! as List<Object?>;
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'accepted': changes
                  .cast<Map<String, Object?>>()
                  .map((change) => change['id']! as String)
                  .toList(growable: false),
              'serverClock': '2026-07-04T08:00:01.000Z',
              'applied': changes.cast<Map<String, Object?>>().map((change) {
                return <String, Object?>{
                  'id': change['id'],
                  'updatedAt': change['updatedAt'],
                  'deviceId': 'device-a',
                };
              }).toList(growable: false),
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final pushResult = await pushRepository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );
    final pushedBodies = pushRequests
        .map((request) => jsonDecode(request.body) as Map<String, Object?>)
        .toList(growable: false);
    Map<String, Object?> pushedChangeFor(String table, String id) {
      final matchingBody = pushedBodies.singleWhere(
        (body) => body['entity'] == table,
      );
      final changes = (matchingBody['changes']! as List<Object?>)
          .cast<Map<String, Object?>>();
      return changes.singleWhere((change) => change['id'] == id);
    }

    final pushedFood = pushedChangeFor(AppDatabase.foodsTable, foodId);
    final pushedMealType =
        pushedChangeFor(AppDatabase.mealTypesTable, mealTypeId);

    expect(pushResult.pushedCount, greaterThanOrEqualTo(2));
    expect(
      (pushedFood['payload']! as Map<String, Object?>)['name'],
      'Chicken Breast',
    );
    expect(
      (pushedFood['payload']! as Map<String, Object?>)['food_source'],
      'user',
    );
    expect(
      (pushedMealType['payload']! as Map<String, Object?>)['name'],
      'Second Breakfast',
    );

    final storedFood = await (database.select(database.foods)
          ..where((row) => row.id.equals(foodId)))
        .getSingle();
    expect(storedFood.syncPreviouslySynced, isTrue);
    expect(storedFood.syncDeviceId, 'device-a');

    // Second device pulls the Food and the Meal Type back.
    final targetDatabase = AppDatabase.inMemory();
    addTearDown(targetDatabase.close);
    final targetRepository = SyncRepository(
      database: targetDatabase,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-food-meal-type-1',
              'serverClock': '2026-07-04T08:00:02.000Z',
              'changes': <Object?>[
                _pulledChangeFromPush(
                  entity: AppDatabase.foodsTable,
                  deviceId: 'device-a',
                  change: pushedFood,
                ),
                _pulledChangeFromPush(
                  entity: AppDatabase.mealTypesTable,
                  deviceId: 'device-a',
                  change: pushedMealType,
                ),
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    final pullResult = await targetRepository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-b',
    );
    final targetRepositories = TrainingRepositories(targetDatabase);
    final pulledFood =
        await targetRepositories.nutrition.getUserFoodById(foodId);
    final pulledMealType =
        await targetRepositories.nutrition.getMealTypeById(mealTypeId);

    expect(pullResult.appliedCount, 2);
    expect(pulledFood, isNotNull);
    expect(pulledFood!.name, 'Chicken Breast');
    expect(pulledMealType, isNotNull);
    expect(pulledMealType!.name, 'Second Breakfast');

    // Archiving the Food locally (tombstone via deleted_at) pushes and
    // round-trips to the second device without cascading to the Meal Type.
    await repositories.nutrition.archiveUserFood(foodId, actor: 'app');
    final archivedFoodRow = await (database.select(database.foods)
          ..where((row) => row.id.equals(foodId)))
        .getSingle();
    // `archiveUserFood` stamps `updatedAt` from the real clock, which can tie
    // the create's `updatedAt` at whole-second resolution and lose LWW (same
    // device id). Force both the row and its not-yet-pushed Activity Log
    // afterImage forward deterministically so this test's LWW ordering never
    // depends on real elapsed wall time.
    final archivedUpdatedAt =
        DateTime.now().toUtc().add(const Duration(days: 1));
    await (database.update(database.foods)
          ..where((row) => row.id.equals(foodId)))
        .write(FoodsCompanion(updatedAt: Value<DateTime>(archivedUpdatedAt)));
    final pendingArchiveLogRow = await (database.select(database.activityLog)
          ..where((row) => row.entityId.equals(foodId))
          ..where((row) => row.syncAcknowledgedAt.isNull()))
        .getSingle();
    final pendingAfterImage =
        jsonDecode(pendingArchiveLogRow.afterImage!) as Map<String, Object?>;
    await (database.update(database.activityLog)
          ..where((row) => row.id.equals(pendingArchiveLogRow.id)))
        .write(
      ActivityLogCompanion(
        afterImage: Value<String?>(
          jsonEncode(<String, Object?>{
            ...pendingAfterImage,
            'updated_at': archivedUpdatedAt.toIso8601String(),
            'deleted_at': archivedUpdatedAt.toIso8601String(),
          }),
        ),
      ),
    );
    expect(archivedFoodRow.id, foodId);
    pushRequests.clear();
    final archivePushResult = await pushRepository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );
    final archivePushedBodies = pushRequests
        .map((request) => jsonDecode(request.body) as Map<String, Object?>)
        .toList(growable: false);
    final archivedPushedFood = archivePushedBodies.singleWhere(
            (body) => body['entity'] == AppDatabase.foodsTable)['changes']!
        as List<Object?>;
    final archivedFoodChange = archivedPushedFood
        .cast<Map<String, Object?>>()
        .singleWhere((change) => change['id'] == foodId);
    expect(archivePushResult.pushedCount, greaterThanOrEqualTo(1));
    expect(archivedFoodChange['deletedAt'], isNotNull);

    final targetRepositoryRound2 = SyncRepository(
      database: targetDatabase,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-food-meal-type-2',
              'serverClock': '2026-07-04T08:00:03.000Z',
              'changes': <Object?>[
                _pulledChangeFromPush(
                  entity: AppDatabase.foodsTable,
                  deviceId: 'device-a',
                  change: archivedFoodChange,
                ),
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );
    final archivePullResult = await targetRepositoryRound2.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-b',
    );
    final targetFoodRowAfterArchive = await (targetDatabase.select(
      targetDatabase.foods,
    )..where((row) => row.id.equals(foodId)))
        .getSingle();
    final targetMealTypeRowAfterArchive = await (targetDatabase.select(
      targetDatabase.mealTypes,
    )..where((row) => row.id.equals(mealTypeId)))
        .getSingle();

    expect(archivePullResult.appliedCount, 1);
    expect(targetFoodRowAfterArchive.deletedAt, isNotNull);
    // No cascade: the Meal Type remains live.
    expect(targetMealTypeRowAfterArchive.deletedAt, isNull);
  });

  test(
      'a Food Entry logged against a synced Food remains a self-describing '
      'snapshot usable on a second device with no hard dependency on the '
      'Food row', () async {
    final repositories = TrainingRepositories(database);
    final mealTypeId = await repositories.nutrition.createMealType(
      const MealTypeDraft(name: 'Second Breakfast', sortOrder: 4),
    );
    final mealId = await repositories.nutrition.createMeal(
      PendingMeal(
        id: repositories.nutrition.newMealId(),
        startedAt: DateTime(2026, 7, 4, 8),
        mealTypeName: mealTypeId,
      ),
    );
    final foodId = await repositories.nutrition.createUserFood(
      UserFoodDraft(
        name: 'Chicken Breast',
        nutrientsPer100: _offNutrientsPer100(),
        isLiquid: false,
        servingLabel: 'serving',
        servingSize: 100,
      ),
    );
    final loggedEntry = await repositories.nutrition.logFoodEntry(
      entry: FoodEntryDraft(
        mealId: mealId,
        foodId: foodId,
        portion: Portion(value: 150, entered: '150', unit: PortionUnit.gram),
      ),
    );

    final pushRequests = <http.Request>[];
    final pushRepository = SyncRepository(
      database: database,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          pushRequests.add(request);
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final changes = body['changes']! as List<Object?>;
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'accepted': changes
                  .cast<Map<String, Object?>>()
                  .map((change) => change['id']! as String)
                  .toList(growable: false),
              'serverClock': '2026-07-04T08:00:01.000Z',
              'applied': changes.cast<Map<String, Object?>>().map((change) {
                return <String, Object?>{
                  'id': change['id'],
                  'updatedAt': change['updatedAt'],
                  'deviceId': 'device-a',
                };
              }).toList(growable: false),
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await pushRepository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );
    final pushedBodies = pushRequests
        .map((request) => jsonDecode(request.body) as Map<String, Object?>)
        .toList(growable: false);
    Map<String, Object?> pushedChangeFor(String table, String id) {
      final matchingBody = pushedBodies.singleWhere(
        (body) => body['entity'] == table,
      );
      final changes = (matchingBody['changes']! as List<Object?>)
          .cast<Map<String, Object?>>();
      return changes.singleWhere((change) => change['id'] == id);
    }

    final pushedFood = pushedChangeFor(AppDatabase.foodsTable, foodId);
    final pushedMealType =
        pushedChangeFor(AppDatabase.mealTypesTable, mealTypeId);
    final pushedMeal = pushedChangeFor(AppDatabase.mealsTable, mealId);
    final pushedEntry = pushedChangeFor(
      AppDatabase.foodEntriesTable,
      loggedEntry.foodEntryId,
    );

    // Device B pulls everything EXCEPT the Food row — the Food Entry must
    // still be a usable, fully self-describing snapshot (analog):
    // it never re-derives its nutrient values from a live Food lookup.
    final targetDatabase = AppDatabase.inMemory();
    addTearDown(targetDatabase.close);
    final targetRepository = SyncRepository(
      database: targetDatabase,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-food-entry-1',
              'serverClock': '2026-07-04T08:00:02.000Z',
              'changes': <Object?>[
                _pulledChangeFromPush(
                  entity: AppDatabase.mealTypesTable,
                  deviceId: 'device-a',
                  change: pushedMealType,
                ),
                _pulledChangeFromPush(
                  entity: AppDatabase.mealsTable,
                  deviceId: 'device-a',
                  change: pushedMeal,
                ),
                _pulledChangeFromPush(
                  entity: AppDatabase.foodEntriesTable,
                  deviceId: 'device-a',
                  change: pushedEntry,
                ),
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    final pullResult = await targetRepository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-b',
    );
    final targetRepositories = TrainingRepositories(targetDatabase);
    final pulledEntry = await targetRepositories.nutrition.getFoodEntryById(
      loggedEntry.foodEntryId,
    );
    final targetFoodRows = await targetDatabase
        .select(
          targetDatabase.foods,
        )
        .get();

    expect(pullResult.appliedCount, 3);
    expect(pulledEntry, isNotNull);
    expect(pulledEntry!.foodId, foodId);
    expect(pulledEntry.name, 'Chicken Breast');
    expect(pulledEntry.nutrients[NutrientId.energy].value, 250);
    // The Food row was never pulled onto device B — the entry did not need
    // it to be usable.
    expect(targetFoodRows, isEmpty);

    // Confirm the Food row DOES independently sync too (round-trips on its
    // own, unconnected to the entry's snapshot).
    expect(pushedFood['payload'], isNotNull);
  });

  test(
      'the complete plan tree pushes and pulls in FK order while authored '
      'writes remain local', () async {
    final repositories = TrainingRepositories(database);
    var clientCreations = 0;
    final pushedChanges = <Map<String, Object?>>[];
    final pushEntities = <String>[];
    final syncRepository = SyncRepository(
      database: database,
      trainingRepositories: repositories,
      apiClientFactory: (baseUrl) {
        clientCreations += 1;
        return PerenniaApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, Object?>;
            final entity = body['entity']! as String;
            final changes = (body['changes']! as List<Object?>)
                .cast<Map<String, Object?>>();
            pushEntities.add(entity);
            for (final change in changes) {
              pushedChanges.add(<String, Object?>{
                'entity': entity,
                'id': change['id'],
                'deviceId': 'device-a',
                'payload': change['payload'],
                'updatedAt': change['updatedAt'],
                'deletedAt': change['deletedAt'],
                if (change['activityLogId'] != null) ...<String, Object?>{
                  'activityLogId': change['activityLogId'],
                  'actor': change['actor'],
                  'batchId': change['batchId'],
                  'beforeImage': change['beforeImage'],
                  'afterImage': change['afterImage'],
                  'occurredAt': change['occurredAt'],
                },
              });
            }
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': syncProtocolVersion,
                'accepted': changes.map((change) => change['id']).toList(),
                'serverClock': '2026-07-22T10:00:00.000Z',
                'applied': changes
                    .map(
                      (change) => <String, Object?>{
                        'id': change['id'],
                        'updatedAt': change['updatedAt'],
                        'deviceId': 'device-a',
                      },
                    )
                    .toList(),
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        );
      },
    );

    final exerciseId = await repositories.exercises.create(
      ExerciseDraft(
        name: 'Bench Press',
        type: ExerciseType(
          const <DimensionId>[DimensionId.load, DimensionId.reps],
        ),
      ),
    );
    final accessoryExerciseId = await repositories.exercises.create(
      ExerciseDraft(
        name: 'Push-up',
        type: ExerciseType(
          const <DimensionId>[DimensionId.reps],
        ),
      ),
    );
    final templateId = await repositories.workoutTemplates.create(
      const WorkoutTemplateDraft(name: 'Push A'),
    );
    final templateExerciseId = await repositories.workoutTemplates.addExercise(
      templateId,
      exerciseId,
    );
    final accessoryTemplateExerciseId =
        await repositories.workoutTemplates.addExercise(
      templateId,
      accessoryExerciseId,
    );
    final emptyTemplateId = await repositories.workoutTemplates.create(
      const WorkoutTemplateDraft(name: 'Empty Push Day'),
    );
    await repositories.workoutTemplates.addExercise(
      emptyTemplateId,
      accessoryExerciseId,
    );
    await repositories.workoutTemplates.addPrescription(
      templateExerciseId,
      PrescriptionDraft(
        mode: PrescriptionMode.fixed,
        values: LoggedSet.fromValues(const <SetDimensionValue>[
          SetDimensionValue(
            dimension: DimensionId.load,
            entered: '100',
            unit: TrainingUnit.kilogram,
          ),
          SetDimensionValue(
            dimension: DimensionId.reps,
            entered: '5',
            unit: TrainingUnit.repetition,
          ),
        ]),
        repeat: 1,
      ),
    );
    await repositories.workoutTemplates.createTemplateGroup(
      templateId,
      TemplateGroupDraft(
        name: 'Main lift',
        colorHex: '#0891B2',
        rounds: 1,
        orderedTemplateExerciseIds: <String>[
          templateExerciseId,
          accessoryTemplateExerciseId,
        ],
      ),
    );
    final routineId = await repositories.routinePlans.create(
      const RoutinePlanDraft(name: 'Strength week'),
    );
    await repositories.routinePlans.addTemplateReference(
      routineId,
      templateId,
    );
    final materialized = await repositories.templateMaterialize.materialize(
      TemplateMaterializeRequest(
        workoutTemplateId: templateId,
        routineId: routineId,
      ),
      now: DateTime.utc(2026, 7, 22, 8),
      timezone: 'UTC',
    );
    final emptyMaterialized =
        await repositories.templateMaterialize.materialize(
      TemplateMaterializeRequest(workoutTemplateId: emptyTemplateId),
      now: DateTime.utc(2026, 7, 22, 9),
      timezone: 'UTC',
    );

    final emptyWorkoutSets = await (database.select(database.loggedSets)
          ..where((row) => row.workoutId.equals(emptyMaterialized.workoutId)))
        .get();
    expect(emptyWorkoutSets, isEmpty);

    expect(
      clientCreations,
      0,
      reason: 'ordinary plan writes must never touch the network',
    );

    await syncRepository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );

    const authoredEntitiesInOrder = <String>[
      AppDatabase.workoutSessionsTable,
      AppDatabase.workoutExercisesTable,
      AppDatabase.exerciseGroupsTable,
      AppDatabase.exerciseGroupMembersTable,
      AppDatabase.workoutTemplatesTable,
      AppDatabase.templateExercisesTable,
      AppDatabase.prescriptionsTable,
      AppDatabase.templateGroupsTable,
      AppDatabase.templateGroupMembersTable,
      'routines',
      AppDatabase.routineEntriesTable,
      AppDatabase.templateLinksTable,
    ];
    expect(
      pushEntities.where(authoredEntitiesInOrder.contains).toList(),
      authoredEntitiesInOrder,
    );
    expect(
      pushEntities.indexOf(AppDatabase.exerciseGroupMembersTable),
      lessThan(pushEntities.indexOf(AppDatabase.loggedSetsTable)),
    );
    expect(
      pushEntities.indexOf(AppDatabase.loggedSetsTable),
      lessThan(pushEntities.indexOf(AppDatabase.templateLinksTable)),
    );
    final pushedMaterializedLink = pushedChanges.singleWhere(
      (change) =>
          change['entity'] == AppDatabase.templateLinksTable &&
          change['id'] == materialized.templateLinkId,
    );
    final pushedMaterializedLinkPayload =
        pushedMaterializedLink['payload']! as Map<String, Object?>;
    expect(
      pushedMaterializedLinkPayload['workout_exercises'],
      isA<List<Object?>>().having((rows) => rows.length, 'length', 2),
    );
    expect(
      pushedMaterializedLinkPayload['workout_exercise_groups'],
      isA<List<Object?>>().having((rows) => rows.length, 'length', 1),
    );
    expect(
      pushedMaterializedLinkPayload['workout_exercise_group_members'],
      isA<List<Object?>>().having((rows) => rows.length, 'length', 2),
    );

    final targetDatabase = AppDatabase.inMemory();
    addTearDown(targetDatabase.close);
    final targetRepository = SyncRepository(
      database: targetDatabase,
      apiClientFactory: (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'plan-tree-cursor',
              'serverClock': '2026-07-22T10:00:00.000Z',
              'changes': pushedChanges.reversed.toList(),
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    await targetRepository.pullLoggedSetChanges(
      session: _session(),
      deviceId: 'device-b',
    );

    expect(await targetDatabase.select(targetDatabase.workoutTemplates).get(),
        hasLength(2));
    expect(await targetDatabase.select(targetDatabase.templateExercises).get(),
        hasLength(3));
    expect(await targetDatabase.select(targetDatabase.prescriptions).get(),
        hasLength(1));
    expect(await targetDatabase.select(targetDatabase.templateGroups).get(),
        hasLength(1));
    expect(
      await targetDatabase.select(targetDatabase.templateGroupMembers).get(),
      hasLength(2),
    );
    expect(await targetDatabase.select(targetDatabase.planRoutines).get(),
        hasLength(1));
    expect(await targetDatabase.select(targetDatabase.routineEntries).get(),
        hasLength(1));
    final links =
        await targetDatabase.select(targetDatabase.templateLinks).get();
    expect(links, hasLength(2));
    final routineLink = links.singleWhere(
      (link) => link.id == materialized.templateLinkId,
    );
    expect(routineLink.workoutId, materialized.workoutId);
    expect(routineLink.routineId, routineId);
    final emptyLink = links.singleWhere(
      (link) => link.id == emptyMaterialized.templateLinkId,
    );
    expect(emptyLink.workoutId, emptyMaterialized.workoutId);
    expect(emptyLink.routineId, isNull);

    final pulledEmptyWorkout =
        await (targetDatabase.select(targetDatabase.workoutSessions)
              ..where((row) => row.id.equals(emptyMaterialized.workoutId)))
            .getSingle();
    expect(pulledEmptyWorkout.startedAt.toUtc(), DateTime.utc(2026, 7, 22, 9));
    expect(pulledEmptyWorkout.timezone, 'UTC');
    expect(pulledEmptyWorkout.localDate, '2026-07-22');
    expect(pulledEmptyWorkout.syncPreviouslySynced, isTrue);

    final pulledWorkoutExercises =
        await (targetDatabase.select(targetDatabase.workoutExercises)
              ..where((row) => row.workoutId.equals(materialized.workoutId))
              ..orderBy([(row) => OrderingTerm.asc(row.position)]))
            .get();
    expect(
      pulledWorkoutExercises.map((row) => row.exerciseId),
      <String>[exerciseId, accessoryExerciseId],
    );
    expect(
      pulledWorkoutExercises.map((row) => row.position),
      <int>[0, 1],
    );
    final pulledExerciseGroups =
        await (targetDatabase.select(targetDatabase.exerciseGroups)
              ..where((row) => row.workoutId.equals(materialized.workoutId)))
            .get();
    expect(pulledExerciseGroups, hasLength(1));
    expect(pulledExerciseGroups.single.name, 'Main lift');
    final pulledExerciseGroupMembers =
        await (targetDatabase.select(targetDatabase.exerciseGroupMembers)
              ..where(
                (row) => row.groupId.equals(pulledExerciseGroups.single.id),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.position)]))
            .get();
    expect(
      pulledExerciseGroupMembers.map((row) => row.workoutExerciseId),
      pulledWorkoutExercises.map((row) => row.id),
    );

    final pulledEmptyWorkoutExercises =
        await (targetDatabase.select(targetDatabase.workoutExercises)
              ..where(
                (row) => row.workoutId.equals(emptyMaterialized.workoutId),
              ))
            .get();
    expect(pulledEmptyWorkoutExercises, hasLength(1));
    expect(pulledEmptyWorkoutExercises.single.exerciseId, accessoryExerciseId);
    expect(pulledEmptyWorkoutExercises.single.position, 0);
  });

  test('plan-tree LWW ties converge by device id in either delivery order',
      () async {
    Future<String> pullNames(List<Map<String, Object?>> changes) async {
      final replica = AppDatabase.inMemory();
      try {
        final repository = SyncRepository(
          database: replica,
          apiClientFactory: (baseUrl) => PerenniaApiClient(
            baseUrl: baseUrl,
            httpClient: MockClient(
              (_) async => http.Response(
                jsonEncode(<String, Object?>{
                  'protocolVersion': syncProtocolVersion,
                  'nextCursor': 'tie-cursor',
                  'serverClock': '2026-07-22T10:00:00.000Z',
                  'changes': changes,
                }),
                200,
                headers: const {'content-type': 'application/json'},
              ),
            ),
          ),
        );
        await repository.pullLoggedSetChanges(
          session: _session(),
          deviceId: 'local-device',
        );
        return (await replica.select(replica.workoutTemplates).getSingle())
            .name;
      } finally {
        await replica.close();
      }
    }

    final updatedAt = DateTime.utc(2026, 7, 22, 9).toIso8601String();
    Map<String, Object?> change(String deviceId, String name) =>
        <String, Object?>{
          'entity': AppDatabase.workoutTemplatesTable,
          'id': 'template-tie',
          'deviceId': deviceId,
          'payload': <String, Object?>{
            'id': 'template-tie',
            'name': name,
            'notes': null,
            'updated_at': updatedAt,
            'deleted_at': null,
          },
          'updatedAt': updatedAt,
          'deletedAt': null,
        };

    final deviceA = change('device-a', 'Device A');
    final deviceB = change('device-b', 'Device B');
    expect(
        await pullNames(<Map<String, Object?>>[deviceA, deviceB]), 'Device B');
    expect(
        await pullNames(<Map<String, Object?>>[deviceB, deviceA]), 'Device B');
  });
  group('Meal time keys (docs/designs/meal-logging.md §10)', () {
    // A Meal image as an app or server from before schema 65 writes it: no
    // `timezone_offset_minutes`, no `time_precision`.
    Map<String, Object?> olderMealImage(
      String id, {
      required DateTime updatedAt,
      String mealType = 'Lunch',
      String startedAt = '2026-06-26T02:00:00.000Z',
      Object? localDate = '2026-06-26',
    }) {
      return <String, Object?>{
        'id': id,
        'meal_type': mealType,
        'started_at': startedAt,
        'timezone': 'AEST',
        if (localDate != null) 'local_date': localDate,
        'ended_at': null,
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': null,
      };
    }

    Map<String, Object?> mealChange(
      Map<String, Object?> payload, {
      String batchId = 'remote-meal-batch',
    }) {
      return <String, Object?>{
        'entity': AppDatabase.mealsTable,
        'id': payload['id'],
        'deviceId': 'device-old',
        'payload': payload,
        'updatedAt': payload['updated_at'],
        'deletedAt': null,
        'activityLogId': 'remote-log-${payload['id']}',
        'actor': 'agent',
        'batchId': batchId,
        'beforeImage': null,
        'afterImage': payload,
        'occurredAt': payload['updated_at'],
      };
    }

    Future<int> pullMeals(List<Map<String, Object?>> changes) async {
      final repository = SyncRepository(
        database: database,
        apiClientFactory: (baseUrl) => PerenniaApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': syncProtocolVersion,
                'nextCursor': 'cursor-meals',
                'serverClock': '2026-06-26T08:00:00.000Z',
                'changes': changes,
              }),
              200,
              headers: const {'content-type': 'application/json'},
            ),
          ),
        ),
      );
      final result = await repository.pullLoggedSetChanges(
        session: _session(),
        deviceId: 'device-a',
      );
      return result.appliedCount;
    }

    Future<MealRow> storedMeal(String id) {
      return (database.select(database.meals)
            ..where((row) => row.id.equals(id)))
          .getSingle();
    }

    test('an older image inserts a Meal with the column defaults', () async {
      const mealId = '018f6a90-6d7f-7d63-bfc1-6f1025e0d001';
      final applied = await pullMeals(<Map<String, Object?>>[
        mealChange(
          olderMealImage(mealId, updatedAt: DateTime.utc(2026, 6, 26, 3)),
        ),
      ]);

      final meal = await storedMeal(mealId);
      expect(applied, 1);
      expect(meal.mealType, 'Lunch');
      expect(meal.localDate, '2026-06-26');
      expect(meal.timezoneOffsetMinutes, isNull);
      expect(meal.timePrecision, 'instant');
    });

    test('an older image updates a Meal and leaves both columns as stored',
        () async {
      // An app write can't choose its offset (it is the device zone's), so
      // the stored Meal is seeded as a row: +10:00 and `date` precision.
      const mealId = '018f6a90-6d7f-7d63-bfc1-6f1025e0d005';
      await database.into(database.meals).insert(
            MealsCompanion.insert(
              id: mealId,
              mealType: 'Breakfast',
              startedAt: DateTime.utc(2026, 6, 25, 14),
              timezone: 'AEST',
              localDate: const Value<String>('2026-06-26'),
              timezoneOffsetMinutes: const Value<int?>(600),
              timePrecision: const Value<String>('date'),
              updatedAt: DateTime.utc(2026, 6, 25, 14),
            ),
          );
      final newer = DateTime.now().toUtc().add(const Duration(days: 1));

      final applied = await pullMeals(<Map<String, Object?>>[
        mealChange(
          olderMealImage(
            mealId,
            updatedAt: newer,
            mealType: 'Brunch',
            startedAt: '2026-06-25T14:00:00.000Z',
            localDate: '2026-06-26',
          ),
        ),
      ]);

      final meal = await storedMeal(mealId);
      expect(applied, 1);
      expect(meal.mealType, 'Brunch');
      expect(meal.timezoneOffsetMinutes, 600);
      expect(meal.timePrecision, 'date');
    });

    test('a pulled image with both keys stores them', () async {
      const mealId = '018f6a90-6d7f-7d63-bfc1-6f1025e0d002';
      await pullMeals(<Map<String, Object?>>[
        mealChange(<String, Object?>{
          ...olderMealImage(mealId, updatedAt: DateTime.utc(2026, 6, 26, 3)),
          'timezone_offset_minutes': -300,
          'time_precision': 'date',
        }),
      ]);

      final meal = await storedMeal(mealId);
      expect(meal.timezoneOffsetMinutes, -300);
      expect(meal.timePrecision, 'date');
    });

    test('a malformed or missing local date is re-derived, not thrown',
        () async {
      const malformedId = '018f6a90-6d7f-7d63-bfc1-6f1025e0d003';
      const missingId = '018f6a90-6d7f-7d63-bfc1-6f1025e0d004';
      final applied = await pullMeals(<Map<String, Object?>>[
        mealChange(<String, Object?>{
          ...olderMealImage(
            malformedId,
            updatedAt: DateTime.utc(2026, 6, 26, 3),
            startedAt: '2026-06-26T22:00:00.000Z',
            localDate: '2026-02-30',
          ),
          'timezone_offset_minutes': 600,
        }),
        mealChange(
          olderMealImage(
            missingId,
            updatedAt: DateTime.utc(2026, 6, 26, 3),
            startedAt: '2026-06-26T02:00:00.000Z',
            localDate: null,
          ),
        ),
      ]);

      expect(applied, 2);
      // 22:00 UTC at +10:00 is the next day.
      expect((await storedMeal(malformedId)).localDate, '2026-06-27');
      // A null offset reads in the device zone.
      expect(
        (await storedMeal(missingId)).localDate,
        NutritionDayDate.fromDateTime(DateTime.utc(2026, 6, 26, 2))
            .storageValue,
      );
    });

    test('push images carry the offset and the time precision', () async {
      final repositories = TrainingRepositories(database);
      final startedAt = DateTime(2026, 6, 26, 12, 30);
      final mealId = await repositories.nutrition.createMeal(
        PendingMeal(
          id: repositories.nutrition.newMealId(),
          startedAt: startedAt,
          mealTypeName: 'Lunch',
        ),
      );
      final pushRequests = <http.Request>[];
      final repository = SyncRepository(
        database: database,
        apiClientFactory: (baseUrl) => PerenniaApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((request) async {
            pushRequests.add(request);
            final body = jsonDecode(request.body) as Map<String, Object?>;
            final changes = (body['changes']! as List<Object?>)
                .cast<Map<String, Object?>>();
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': syncProtocolVersion,
                'accepted': changes
                    .map((change) => change['id']! as String)
                    .toList(growable: false),
                'serverClock': '2026-06-26T08:00:01.000Z',
                'applied': changes
                    .map(
                      (change) => <String, Object?>{
                        'id': change['id'],
                        'updatedAt': change['updatedAt'],
                        'deviceId': 'device-a',
                      },
                    )
                    .toList(growable: false),
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        ),
      );

      await repository.pushPendingLoggedSets(
        session: _session(),
        deviceId: 'device-a',
      );

      final pushedMeal = pushRequests
          .map((request) => jsonDecode(request.body) as Map<String, Object?>)
          .where((body) => body['entity'] == AppDatabase.mealsTable)
          .expand((body) => body['changes']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .singleWhere((change) => change['id'] == mealId);
      final offset = startedAt.timeZoneOffset.inMinutes;
      for (final image in <Object?>[
        pushedMeal['payload'],
        pushedMeal['afterImage'],
      ]) {
        final map = image! as Map<String, Object?>;
        expect(map['timezone_offset_minutes'], offset);
        expect(map['time_precision'], 'instant');
      }
    });

    test('undo of a Batch whose Meal images predate the keys is not stale',
        () async {
      const mealId = '018f6a90-6d7f-7d63-bfc1-6f1025e0d005';
      const batchId = 'older-meal-batch';
      await pullMeals(<Map<String, Object?>>[
        mealChange(
          olderMealImage(mealId, updatedAt: DateTime.utc(2026, 6, 26, 3)),
          batchId: batchId,
        ),
      ]);
      final feedRepository =
          ActivityFeedRepository(TrainingRepositories(database));

      final undo = await feedRepository.undoBatch(batchId);

      expect(undo.conflicts, isEmpty);
      expect(undo.undoBatchId, isNotNull);
      expect((await storedMeal(mealId)).deletedAt, isNotNull);
    });

    test(
        'undo of the Batch that created a Meal is refused once a pulled food '
        'joined it (meal-logging.md §7)', () async {
      final repositories = TrainingRepositories(database);
      final meal = PendingMeal(
        id: repositories.nutrition.newMealId(),
        startedAt: DateTime(2026, 6, 26, 12, 30),
        mealTypeName: 'Lunch',
      );
      final first = await repositories.nutrition.logQuickEntry(
        target: NewMealTarget(meal),
        entry: QuickFoodEntryDraft(
          name: 'Soup',
          nutrients: _offNutrientsPer100(),
        ),
      );
      final localEntry = (await repositories.activityLog.listEntries())
          .singleWhere(
            (entry) =>
                entry.batchId == first.batchId &&
                entry.entityTable == AppDatabase.foodEntriesTable,
          )
          .afterImage!;
      const pulledEntryId = '018f6a90-6d7f-7d63-bfc1-6f1025e0d0f1';
      final pulledAt = DateTime.now().toUtc().add(const Duration(minutes: 1));
      final pulledEntry = <String, Object?>{
        ...localEntry,
        'id': pulledEntryId,
        'position': 1,
        'name': 'Bread',
        'updated_at': pulledAt.toIso8601String(),
      };

      final applied = await pullMeals(<Map<String, Object?>>[
        <String, Object?>{
          'entity': AppDatabase.foodEntriesTable,
          'id': pulledEntryId,
          'deviceId': 'device-b',
          'payload': pulledEntry,
          'updatedAt': pulledEntry['updated_at'],
          'deletedAt': null,
          'activityLogId': 'remote-log-$pulledEntryId',
          'actor': 'app',
          'batchId': 'remote-food-batch',
          'beforeImage': null,
          'afterImage': pulledEntry,
          'occurredAt': pulledEntry['updated_at'],
        },
      ]);
      expect(applied, 1);

      final undo =
          await ActivityFeedRepository(repositories).undoBatch(first.batchId);

      expect(undo.undoBatchId, isNull);
      expect(undo.appliedEntries, isEmpty);
      expect(
        undo.conflicts.single.reason,
        ActivityLogUndoConflictReason.dependent,
      );
      expect(undo.conflicts.single.entityId, meal.id);
      expect((await storedMeal(meal.id)).deletedAt, isNull);
      expect(
        (await repositories.nutrition.listActiveEntriesForMeal(meal.id))
            .map((entry) => entry.id),
        <String>[first.foodEntryId, pulledEntryId],
      );
    });
  });

  // docs/designs/platform-library-updates.md: "Hide, do not delete", "Keep in
  // place" and "Timestamps make devices agree".
  group('Retired Exercises across sync', () {
    late AppDatabase other;

    setUp(() {
      other = AppDatabase.inMemory();
    });

    tearDown(() async {
      await other.close();
    });

    test('a pulled Set on a hidden id applies, and the next launch keeps it',
        () async {
      await _launchLibrary(database, _updatedLibrary);
      final updatedAt = DateTime.utc(2026, 2, 1, 8);
      await _insertLoggedSetDependencies(database, updatedAt: updatedAt);

      await _pullChangeInto(
        database,
        localDeviceId: 'device-b',
        change: _pulledChange(
          id: 'late-set',
          updatedAt: updatedAt,
          repsEntered: '8',
          deviceId: 'device-a',
          afterImage: <String, Object?>{
            ..._loggedSetPayload('late-set', updatedAt, repsEntered: '8'),
            'exercise_id': _plankExerciseId,
          },
        ),
      );

      expect(
        (await _loggedSet(database, 'late-set')).exerciseId,
        _plankExerciseId,
      );
      expect(await _quarantinedChanges(database), isEmpty);
      _expectHiddenPlank(await _exerciseRow(database, _plankExerciseId));

      await _launchLibrary(database, _updatedLibrary);

      _expectKeptPlank(await _exerciseRow(database, _plankExerciseId));
    });

    test(
        'a pulled Template entry on a hidden id applies, and the next launch '
        'keeps it', () async {
      await _launchLibrary(database, _updatedLibrary);
      final updatedAt = DateTime.utc(2026, 2, 1, 8);
      await database.into(database.workoutTemplates).insert(
            WorkoutTemplatesCompanion.insert(
              id: 'late-template',
              name: 'Core',
              updatedAt: updatedAt,
            ),
          );

      await _pullChangeInto(
        database,
        localDeviceId: 'device-b',
        change: <String, Object?>{
          'entity': AppDatabase.templateExercisesTable,
          'id': 'late-entry',
          'deviceId': 'device-a',
          'payload': <String, Object?>{
            'id': 'late-entry',
            'workout_template_id': 'late-template',
            'exercise_id': _plankExerciseId,
            'position': 0,
            'note': null,
            'updated_at': updatedAt.toIso8601String(),
            'deleted_at': null,
          },
          'updatedAt': updatedAt.toIso8601String(),
          'deletedAt': null,
        },
      );

      final entry = await (database.select(database.templateExercises)
            ..where((row) => row.id.equals('late-entry')))
          .getSingle();
      expect(entry.exerciseId, _plankExerciseId);
      expect(await _quarantinedChanges(database), isEmpty);
      _expectHiddenPlank(await _exerciseRow(database, _plankExerciseId));

      await _launchLibrary(database, _updatedLibrary);

      _expectKeptPlank(await _exerciseRow(database, _plankExerciseId));
    });

    test('a pulled kept row applies over a hidden one', () async {
      await _keepPlankOn(other);
      final kept = _lastExerciseChange(
        await _pushExerciseChanges(other, deviceId: 'device-a'),
        _plankExerciseId,
      );
      await _launchLibrary(database, _updatedLibrary);
      _expectHiddenPlank(await _exerciseRow(database, _plankExerciseId));

      await _pullChangeInto(
        database,
        localDeviceId: 'device-b',
        change: _pulledChangeFromPush(
          entity: AppDatabase.exercisesTable,
          deviceId: 'device-a',
          change: kept,
        ),
      );

      final pulled = await _exerciseRow(database, _plankExerciseId);
      _expectKeptPlank(pulled);
      expect(pulled.syncDeviceId, 'device-a');

      // Later launches leave it alone: it is a User Library row now.
      final entriesBefore = await database.select(database.activityLog).get();
      await _launchLibrary(database, _updatedLibrary);
      expect(await _exerciseRow(database, _plankExerciseId), pulled);
      expect(await database.select(database.activityLog).get(), entriesBefore);
    });

    test(
        "a Sync Run seeds first, so a favorite's later stamp does not beat the "
        'pulled kept row', () async {
      await _keepPlankOn(other);
      final kept = _lastExerciseChange(
        await _pushExerciseChanges(other, deviceId: 'device-a'),
        _plankExerciseId,
      );
      final installed = await _launchLibrary(database, _updatedLibrary);
      await installed.exercises.setFavorite(_plankExerciseId, isFavorite: true);
      final favorited = await _exerciseRow(database, _plankExerciseId);
      expect(favorited.updatedAt.toUtc().isAfter(_plankRetiredAt), isTrue);

      final nextLaunch = TrainingRepositories(
        database,
        platformSeedSource: _LibrarySource(_updatedLibrary),
      );
      final pushes = <Map<String, Object?>>[];
      final repository = SyncRepository(
        database: database,
        apiClientFactory: _acceptingSyncApi(
          pushes: pushes,
          pullChanges: <Map<String, Object?>>[
            _pulledChangeFromPush(
              entity: AppDatabase.exercisesTable,
              deviceId: 'device-a',
              change: kept,
            ),
          ],
        ),
      );

      await RepositorySyncCycleRunner(
        repository: repository,
        statusRepository: repository.statusRepository,
        ensureLibrarySeeded: nextLaunch.catalog.ensurePlatformLibrarySeeded,
      ).run(session: _session(), deviceId: 'device-b');

      _expectKeptPlank(await _exerciseRow(database, _plankExerciseId));
    });

    test("a device's automatic keep loses to a later pulled rename (CUJ 8)",
        () async {
      // Device A updates first, and the user renames the kept exercise there.
      final deviceA = await _keepPlankOn(other);
      await deviceA.exercises.rename(_plankExerciseId, name: 'Forearm Hold');
      final renamedRow = await _exerciseRow(other, _plankExerciseId);
      expect(renamedRow.updatedAt.toUtc().isAfter(_plankRetiredAt), isTrue);
      final renamed = _lastExerciseChange(
        await _pushExerciseChanges(other, deviceId: 'device-a'),
        _plankExerciseId,
      );

      // Device B updates later. Its automatic keep goes out first and the
      // server drops it, then the rename comes back in the same Sync Run.
      await _logPlankOnOlderLibrary(database);
      final nextLaunch = TrainingRepositories(
        database,
        platformSeedSource: _LibrarySource(_updatedLibrary),
      );
      final pushes = <Map<String, Object?>>[];
      final repository = SyncRepository(
        database: database,
        apiClientFactory: _acceptingSyncApi(
          pushes: pushes,
          applyPushes: false,
          pullChanges: <Map<String, Object?>>[
            _pulledChangeFromPush(
              entity: AppDatabase.exercisesTable,
              deviceId: 'device-a',
              change: renamed,
            ),
          ],
        ),
      );

      await RepositorySyncCycleRunner(
        repository: repository,
        statusRepository: repository.statusRepository,
        ensureLibrarySeeded: nextLaunch.catalog.ensurePlatformLibrarySeeded,
      ).run(session: _session(), deviceId: 'device-b');

      final automaticKeep = _lastExerciseChange(
        _exerciseChangesIn(pushes),
        _plankExerciseId,
      );
      expect(
        (automaticKeep['payload']! as Map<String, Object?>)['name'],
        'Plank',
      );
      final deviceBRow = await _exerciseRow(database, _plankExerciseId);
      expect(deviceBRow.name, 'Forearm Hold');
      expect(deviceBRow.libraryOrigin, ExerciseLibraryOrigin.user.name);
      expect(deviceBRow.syncDeviceId, 'device-a');
      expect(deviceBRow.updatedAt, renamedRow.updatedAt);
      expect(await repository.hasPendingChanges(), isFalse);

      // Were device A to pull device B's automatic keep, it would lose there.
      await _pullChangeInto(
        other,
        localDeviceId: 'device-a',
        change: _pulledChangeFromPush(
          entity: AppDatabase.exercisesTable,
          deviceId: 'device-b',
          change: automaticKeep,
        ),
      );
      expect(
        (await _exerciseRow(other, _plankExerciseId)).name,
        'Forearm Hold',
      );
    });

    for (final firstPull in <String>['device-a', 'device-b']) {
      test(
          "two devices' kept rows at one stamp converge by the device-id "
          'tie-break, with $firstPull pulling first', () async {
        // Only `isFavorite` can differ between two kept rows, which is what
        // shows here whose row won.
        await _logPlankOnOlderLibrary(other);
        await (other.update(other.exercises)
              ..where((row) => row.id.equals(_plankExerciseId)))
            .write(const ExercisesCompanion(isFavorite: Value<bool>(true)));
        await _launchLibrary(other, _updatedLibrary);
        await _keepPlankOn(database);
        expect(
          (await _exerciseRow(other, _plankExerciseId)).updatedAt,
          (await _exerciseRow(database, _plankExerciseId)).updatedAt,
        );

        final fromA = _pulledChangeFromPush(
          entity: AppDatabase.exercisesTable,
          deviceId: 'device-a',
          change: _lastExerciseChange(
            await _pushExerciseChanges(other, deviceId: 'device-a'),
            _plankExerciseId,
          ),
        );
        final fromB = _pulledChangeFromPush(
          entity: AppDatabase.exercisesTable,
          deviceId: 'device-b',
          change: _lastExerciseChange(
            await _pushExerciseChanges(database, deviceId: 'device-b'),
            _plankExerciseId,
          ),
        );

        Future<void> pullIntoA() => _pullChangeInto(
              other,
              localDeviceId: 'device-a',
              change: fromB,
            );
        Future<void> pullIntoB() => _pullChangeInto(
              database,
              localDeviceId: 'device-b',
              change: fromA,
            );
        if (firstPull == 'device-a') {
          await pullIntoA();
          await pullIntoB();
        } else {
          await pullIntoB();
          await pullIntoA();
        }

        final deviceARow = await _exerciseRow(other, _plankExerciseId);
        final deviceBRow = await _exerciseRow(database, _plankExerciseId);
        _expectKeptPlank(deviceARow);
        _expectKeptPlank(deviceBRow);
        // 'device-b' sorts later, so its row, with no favorite, wins on both.
        expect(deviceARow.isFavorite, isFalse);
        expect(deviceBRow.isFavorite, isFalse);
        expect(deviceARow.syncDeviceId, 'device-b');
        expect(deviceBRow.syncDeviceId, 'device-b');
      });
    }

    test('the kept row pushes, and a hidden row does not', () async {
      await _keepPlankOn(database);
      _expectHiddenRow(await _exerciseRow(database, _sideBendExerciseId));

      final changes =
          await _pushExerciseChanges(database, deviceId: 'device-a');

      // Only the kept image goes out: not the entries the row queued while it
      // was a Platform row, not the hidden row, not the live Platform row.
      expect(changes.map((change) => change['id']), <String>[_plankExerciseId]);
      final payload = changes.single['payload']! as Map<String, Object?>;
      expect(payload['library_origin'], ExerciseLibraryOrigin.user.name);
      expect(payload['name'], 'Plank');
      expect(payload['deleted_at'], isNull);
      expect(
        DateTime.parse(payload['updated_at']! as String).toUtc(),
        _plankRetiredAt,
      );

      // The guard acknowledges the entries of every Platform row, so none is
      // retried, and the accepted push acknowledges the kept row's.
      final pendingExerciseEntries =
          await (database.select(database.activityLog)
                ..where(
                  (row) =>
                      row.entityTable.equals(AppDatabase.exercisesTable) &
                      row.syncAcknowledgedAt.isNull(),
                ))
              .get();
      expect(pendingExerciseEntries, isEmpty);
      final hiddenEntries = await (database.select(database.activityLog)
            ..where((row) => row.entityId.equals(_sideBendExerciseId)))
          .get();
      expect(hiddenEntries, isNotEmpty);
    });
  });
}

/// A Sync API that asks for a full resync and then serves [snapshot].
SyncRepository _snapshotRepository(
  AppDatabase database,
  List<Object?> snapshot,
) {
  return SyncRepository(
    database: database,
    apiClientFactory: (baseUrl) => PerenniaApiClient(
      baseUrl: baseUrl,
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode(<String, Object?>{
            'protocolVersion': syncProtocolVersion,
            'fullResyncRequired': body['mode'] != 'snapshot',
            'nextCursor': 'snapshot-cursor',
            'serverClock': '2026-11-01T00:00:02.000Z',
            'changes': body['mode'] == 'snapshot' && body['cursor'] == null
                ? snapshot
                : const <Object?>[],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    ),
  );
}

const _creatineId = '019200ff-0000-7000-8000-000000000001';
const _cognitionId = '019200ff-0000-7000-8000-000000000105';
const _performanceId = '019200ff-0000-7000-8000-000000000103';

/// A device on schema 65 that has already synced: the six seed Compounds are
/// untagged, last written and pushed by this device, and each has only its
/// `otc_seed` Activity Log entry, acknowledged.
Future<void> _seedAsSyncedUpgradedDevice(
  TrainingRepositories repositories,
  AppDatabase database, {
  required String deviceId,
}) async {
  await repositories.protocols.ensureOtcLibrarySeeded();
  await database.customStatement(
    "UPDATE compounds SET purpose_ids = '[]', updated_at = 1000, "
    "sync_device_id = '$deviceId', sync_previously_synced = 1",
  );
  await database.customStatement(
    "UPDATE purposes SET sync_device_id = '$deviceId', "
    'sync_previously_synced = 1',
  );
  await database.customStatement(
    'UPDATE activity_log SET sync_acknowledged_at = 1000',
  );
}

/// A device on schema 65 with no account: the six seed Compounds are untagged,
/// stamped when it seeded, never synced, and each has only its pending
/// `otc_seed` entry, whose image has no `purpose_ids` key.
Future<void> _seedAsNeverSyncedUpgradedDevice(
  TrainingRepositories repositories,
  AppDatabase database, {
  required DateTime seededAt,
}) async {
  await repositories.protocols.ensureOtcLibrarySeeded();
  // Drift stores a DateTime as whole seconds.
  final seconds = seededAt.millisecondsSinceEpoch ~/ 1000;
  final image = DateTime.fromMillisecondsSinceEpoch(
    seconds * 1000,
    isUtc: true,
  ).toIso8601String();
  await database.customStatement(
    "UPDATE compounds SET purpose_ids = '[]', updated_at = $seconds",
  );
  await database.customStatement(
    'UPDATE activity_log SET occurred_at = $seconds, after_image = '
    "json_set(json_remove(after_image, '\$.purpose_ids'), "
    "'\$.updated_at', '$image') "
    "WHERE entity_table = '${AppDatabase.compoundsTable}'",
  );
}

/// A Sync API that holds Compound rows in [rows] and applies the server's rule
/// to each pushed one: it wins only on (stamp, device), and a payload with no
/// `purpose_ids` key keeps the stored list. A pull serves [rows] and
/// [otherPullChanges] once. Pushes of every other entity are accepted and not
/// applied.
PerenniaApiClient Function(Uri) _lwwCompoundServer(
  Map<String, Map<String, Object?>> rows, {
  List<Map<String, Object?>> otherPullChanges = const <Map<String, Object?>>[],
}) {
  bool wins(Map<String, Object?> incoming, Map<String, Object?> held) {
    final byStamp = DateTime.parse(incoming['updatedAt']! as String)
        .compareTo(DateTime.parse(held['updatedAt']! as String));
    if (byStamp != 0) {
      return byStamp > 0;
    }
    return (incoming['deviceId']! as String)
            .compareTo(held['deviceId']! as String) >
        0;
  }

  return (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          if (request.url.path == '/sync/push') {
            final changes = (body['changes']! as List<Object?>)
                .cast<Map<String, Object?>>();
            final applied = <Map<String, Object?>>[];
            if (body['entity'] == AppDatabase.compoundsTable) {
              for (final change in changes) {
                final id = change['id']! as String;
                final incoming = <String, Object?>{
                  ...change,
                  'entity': AppDatabase.compoundsTable,
                  'deviceId': body['deviceId'],
                };
                final held = rows[id];
                if (held != null && !wins(incoming, held)) {
                  continue;
                }
                final payload = <String, Object?>{
                  ...change['payload']! as Map<String, Object?>,
                };
                final heldPayload = held?['payload'] as Map<String, Object?>?;
                if (!payload.containsKey('purpose_ids') &&
                    heldPayload != null &&
                    heldPayload.containsKey('purpose_ids')) {
                  payload['purpose_ids'] = heldPayload['purpose_ids'];
                }
                rows[id] = <String, Object?>{...incoming, 'payload': payload};
                applied.add(<String, Object?>{
                  'id': id,
                  'updatedAt': change['updatedAt'],
                  'deviceId': body['deviceId'],
                });
              }
            }
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': syncProtocolVersion,
                'accepted': changes
                    .map((change) => change['id']! as String)
                    .toList(growable: false),
                'serverClock': DateTime.now().toUtc().toIso8601String(),
                'applied': applied,
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-1',
              'serverClock': DateTime.now().toUtc().toIso8601String(),
              'changes': body['cursor'] == null
                  ? <Object?>[...otherPullChanges, ...rows.values]
                  : <Object?>[],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );
}

/// A Sync API that accepts every push and serves [pullChanges] once. Bodies of
/// the pushes land in [pushes].
PerenniaApiClient Function(Uri) _acceptingSyncApi({
  required List<Map<String, Object?>> pushes,
  List<Map<String, Object?>> pullChanges = const <Map<String, Object?>>[],
  bool applyPushes = true,
}) {
  return (baseUrl) => PerenniaApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          if (request.url.path == '/sync/push') {
            pushes.add(body);
            final changes = (body['changes']! as List<Object?>)
                .cast<Map<String, Object?>>();
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': syncProtocolVersion,
                'accepted': changes
                    .map((change) => change['id']! as String)
                    .toList(growable: false),
                'serverClock': '2026-11-01T00:00:01.000Z',
                'applied': applyPushes
                    ? changes
                        .map(
                          (change) => <String, Object?>{
                            'id': change['id'],
                            'updatedAt': change['updatedAt'],
                            'deviceId': body['deviceId'],
                          },
                        )
                        .toList(growable: false)
                    : const <Object?>[],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': syncProtocolVersion,
              'nextCursor': 'cursor-1',
              'serverClock': '2026-11-01T00:00:02.000Z',
              'changes': body['cursor'] == null ? pullChanges : <Object?>[],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );
}

Map<String, Object?> _purposePullChange({
  required String id,
  required String name,
  required int sortOrder,
  required String updatedAt,
  required String deviceId,
  String actor = 'manual',
}) {
  final payload = <String, Object?>{
    'id': id,
    'name': name,
    'sort_order': sortOrder,
    'updated_at': updatedAt,
    'deleted_at': null,
  };
  return <String, Object?>{
    'entity': AppDatabase.purposesTable,
    'id': id,
    'deviceId': deviceId,
    'payload': payload,
    'updatedAt': updatedAt,
    'deletedAt': null,
    'activityLogId': 'activity-$id-$updatedAt',
    'actor': actor,
    'batchId': 'batch-$id-$updatedAt',
    'beforeImage': null,
    'afterImage': payload,
    'occurredAt': updatedAt,
  };
}

/// [row] as another device's pull would carry it, with [changes] over its
/// image. A key mapped to [_absent] is left out, as an older app's push does.
Map<String, Object?> _compoundPullChange(
  CompoundRow row, {
  required String updatedAt,
  required String deviceId,
  required String actor,
  String activityLogId = '',
  Map<String, Object?> changes = const <String, Object?>{},
}) {
  final payload = <String, Object?>{
    'id': row.id,
    'name': row.name,
    'default_unit': row.defaultUnit,
    'default_route': row.defaultRoute,
    'strength': row.strength,
    'is_favorite': row.isFavorite,
    'purpose_ids': row.purposeIds,
    'updated_at': updatedAt,
    'deleted_at': null,
    ...changes,
  }..removeWhere((_, value) => identical(value, _absent));
  final logId =
      activityLogId.isEmpty ? 'activity-${row.id}-$actor' : activityLogId;
  return <String, Object?>{
    'entity': AppDatabase.compoundsTable,
    'id': row.id,
    'deviceId': deviceId,
    'payload': payload,
    'updatedAt': updatedAt,
    'deletedAt': null,
    'activityLogId': logId,
    'actor': actor,
    'batchId': 'batch-${row.id}-$actor',
    'beforeImage': null,
    'afterImage': payload,
    'occurredAt': updatedAt,
  };
}

const Object _absent = Object();

Future<CompoundRow> _compoundRow(AppDatabase database, String id) {
  return (database.select(database.compounds)
        ..where((row) => row.id.equals(id)))
      .getSingle();
}

Future<PurposeRow> _purposeRow(AppDatabase database, String id) {
  return (database.select(database.purposes)..where((row) => row.id.equals(id)))
      .getSingle();
}

Future<void> _insertActivityLogEntry(
  AppDatabase database, {
  required String id,
  required String entityId,
  required DateTime updatedAt,
}) {
  return database.into(database.activityLog).insert(
        ActivityLogCompanion.insert(
          id: id,
          actor: 'app',
          batchId: 'batch-1',
          entityTable: AppDatabase.loggedSetsTable,
          entityId: entityId,
          beforeImage: const Value<String?>(null),
          afterImage: Value<String?>(
            jsonEncode(<String, Object?>{
              'id': entityId,
              'workout_id': 'workout-1',
              'exercise_id': 'exercise-1',
              'position': 0,
              'is_completed': false,
              'updated_at': updatedAt.toIso8601String(),
              'deleted_at': null,
            }),
          ),
          occurredAt: updatedAt,
          updatedAt: updatedAt,
        ),
      );
}

Future<void> _insertIntegrationConsentActivityLogEntry(
  AppDatabase database, {
  required String id,
  required String entityId,
  required String dataClass,
  required bool enabled,
  required DateTime updatedAt,
}) {
  return database.into(database.activityLog).insert(
        ActivityLogCompanion.insert(
          id: id,
          actor: 'app',
          batchId: 'batch-1',
          entityTable: AppDatabase.integrationDataClassConsentsTable,
          entityId: entityId,
          beforeImage: const Value<String?>(null),
          afterImage: Value<String?>(
            jsonEncode(
              _integrationConsentPayload(
                entityId,
                dataClass: dataClass,
                enabled: enabled,
                updatedAt: updatedAt,
              ),
            ),
          ),
          occurredAt: updatedAt,
          updatedAt: updatedAt,
        ),
      );
}

Future<void> _insertIntegrationConsent(
  AppDatabase database, {
  required String id,
  required String dataClass,
  required bool enabled,
  required DateTime updatedAt,
}) {
  return database.into(database.integrationDataClassConsents).insert(
        IntegrationDataClassConsentsCompanion.insert(
          id: id,
          credentialId: 'credential-garmin-1',
          dataClass: dataClass,
          enabled: Value<bool>(enabled),
          updatedAt: updatedAt,
        ),
      );
}

Future<Map<String, String>> _runTwoDevicePullOrder({
  required String setId,
  required DateTime updatedAt,
  required String firstPullDeviceId,
}) async {
  final deviceADatabase = AppDatabase.inMemory();
  final deviceBDatabase = AppDatabase.inMemory();

  try {
    await _insertLoggedSetDependencies(deviceADatabase, updatedAt: updatedAt);
    await _insertLoggedSetDependencies(deviceBDatabase, updatedAt: updatedAt);
    await _insertLoggedSet(
      deviceADatabase,
      id: setId,
      updatedAt: updatedAt,
      repsEntered: '5',
      syncDeviceId: 'device-a',
    );
    await _insertLoggedSet(
      deviceBDatabase,
      id: setId,
      updatedAt: updatedAt,
      repsEntered: '6',
      syncDeviceId: 'device-b',
    );

    final deviceAChange = _pulledChange(
      id: setId,
      updatedAt: updatedAt,
      repsEntered: '5',
      deviceId: 'device-a',
    );
    final deviceBChange = _pulledChange(
      id: setId,
      updatedAt: updatedAt,
      repsEntered: '6',
      deviceId: 'device-b',
    );

    if (firstPullDeviceId == 'device-a') {
      await _pullChangeInto(
        deviceADatabase,
        localDeviceId: 'device-a',
        change: deviceBChange,
      );
      await _pullChangeInto(
        deviceBDatabase,
        localDeviceId: 'device-b',
        change: deviceAChange,
      );
    } else {
      await _pullChangeInto(
        deviceBDatabase,
        localDeviceId: 'device-b',
        change: deviceAChange,
      );
      await _pullChangeInto(
        deviceADatabase,
        localDeviceId: 'device-a',
        change: deviceBChange,
      );
    }

    return <String, String>{
      'device-a': (await _loggedSet(deviceADatabase, setId)).repsEntered!,
      'device-b': (await _loggedSet(deviceBDatabase, setId)).repsEntered!,
    };
  } finally {
    await deviceADatabase.close();
    await deviceBDatabase.close();
  }
}

Future<void> _pullChangeInto(
  AppDatabase database, {
  required String localDeviceId,
  required Map<String, Object?> change,
}) async {
  final repository = SyncRepository(
    database: database,
    apiClientFactory: (baseUrl) => PerenniaApiClient(
      baseUrl: baseUrl,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{
            'protocolVersion': syncProtocolVersion,
            'nextCursor': 'cursor-1',
            'serverClock': '2026-06-22T08:00:01.000Z',
            'changes': <Object?>[change],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    ),
  );

  await repository.pullLoggedSetChanges(
    session: _session(),
    deviceId: localDeviceId,
  );
}

Map<String, Object?> _pulledChange({
  required String id,
  required DateTime updatedAt,
  required String repsEntered,
  required String deviceId,
  String? actor,
  String? batchId,
  String? activityLogId,
  Map<String, Object?>? beforeImage,
  Map<String, Object?>? afterImage,
  DateTime? occurredAt,
}) {
  final payload =
      afterImage ?? _loggedSetPayload(id, updatedAt, repsEntered: repsEntered);
  return <String, Object?>{
    'entity': AppDatabase.loggedSetsTable,
    'id': id,
    'deviceId': deviceId,
    'payload': payload,
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': null,
    if (activityLogId != null) 'activityLogId': activityLogId,
    if (actor != null) 'actor': actor,
    if (batchId != null) 'batchId': batchId,
    if (activityLogId != null) 'beforeImage': beforeImage,
    if (activityLogId != null) 'afterImage': payload,
    if (occurredAt != null) 'occurredAt': occurredAt.toIso8601String(),
  };
}

Map<String, Object?> _pulledChangeFromPush({
  required String entity,
  required String deviceId,
  required Map<String, Object?> change,
}) {
  return <String, Object?>{
    'entity': entity,
    'id': change['id'],
    'deviceId': deviceId,
    'payload': change['payload'],
    'updatedAt': change['updatedAt'],
    'deletedAt': change['deletedAt'],
    'activityLogId': change['activityLogId'],
    'actor': change['actor'],
    'batchId': change['batchId'],
    'beforeImage': change['beforeImage'],
    'afterImage': change['afterImage'],
    'occurredAt': change['occurredAt'],
  };
}

Future<void> _insertLoggedSet(
  AppDatabase database, {
  required String id,
  required DateTime updatedAt,
  required String repsEntered,
  required String syncDeviceId,
  bool syncPreviouslySynced = false,
}) {
  return database.into(database.loggedSets).insert(
        LoggedSetsCompanion.insert(
          id: id,
          workoutId: 'workout-1',
          exerciseId: 'exercise-1',
          position: 0,
          repsValue: Value<double?>(double.parse(repsEntered)),
          repsUnit: const Value<String?>('rep'),
          repsEntered: Value<String?>(repsEntered),
          isCompleted: const Value<bool>(false),
          syncDeviceId: Value<String?>(syncDeviceId),
          syncPreviouslySynced: Value<bool>(syncPreviouslySynced),
          updatedAt: updatedAt,
        ),
      );
}

Future<ActivityLogRow> _activityLogEntry(
  AppDatabase database,
  String id,
) {
  return (database.select(database.activityLog)
        ..where((row) => row.id.equals(id)))
      .getSingle();
}

Future<void> _insertLoggedSetDependencies(
  AppDatabase database, {
  required DateTime updatedAt,
}) async {
  await database.into(database.exercises).insert(
        ExercisesCompanion.insert(
          id: 'exercise-1',
          libraryOrigin: const Value<String>('user'),
          name: 'Back Squat',
          dimensionIds: '["reps"]',
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.workoutSessions).insert(
        WorkoutSessionsCompanion.insert(
          id: 'workout-1',
          startedAt: updatedAt,
          timezone: 'UTC',
          localDate: const Value<String>('2026-06-22'),
          updatedAt: updatedAt,
        ),
      );
}

Map<String, Object?> _loggedSetPayload(
  String id,
  DateTime updatedAt, {
  String repsEntered = '5',
  DateTime? deletedAt,
}) {
  return <String, Object?>{
    'id': id,
    'workout_id': 'workout-1',
    'exercise_id': 'exercise-1',
    'position': 0,
    'planned_rest_after': null,
    'load_value': null,
    'load_unit': null,
    'load_entered': null,
    'reps_value': double.parse(repsEntered),
    'reps_unit': 'rep',
    'reps_entered': repsEntered,
    'duration_value': null,
    'duration_unit': null,
    'duration_entered': null,
    'distance_value': null,
    'distance_unit': null,
    'distance_entered': null,
    'comment': null,
    'side': null,
    'rpe': null,
    'is_completed': false,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };
}

Map<String, Object?> _dosePayload(
  String id, {
  required DateTime updatedAt,
  String amountEntered = '1',
  String compoundName = 'Caffeine',
  String? compoundStrength,
  DateTime? deletedAt,
}) {
  return <String, Object?>{
    'id': id,
    'compound_id': null,
    'compound_name': compoundName,
    'compound_strength': compoundStrength,
    'amount_value': double.parse(amountEntered),
    'amount_entered': amountEntered,
    'unit': DoseUnit.capsule.name,
    'route': DoseRoute.oral.name,
    'took_at': updatedAt.toIso8601String(),
    'timezone': 'UTC',
    'local_date': ProtocolDayDate.fromDateTime(updatedAt).storageValue,
    'provenance': DoseProvenance.manual.name,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };
}

Map<String, Object?> _doseTombstonePayload(
  String id, {
  required DateTime deletedAt,
}) {
  return _dosePayload(
    id,
    amountEntered: '5',
    compoundName: 'Creatine',
    updatedAt: deletedAt,
    deletedAt: deletedAt,
  );
}

Map<String, Object?> _exerciseTombstonePayload(
  String id, {
  required String categoryId,
  required DateTime deletedAt,
}) {
  return <String, Object?>{
    'id': id,
    'library_origin': 'user',
    'name': 'Back Squat',
    'dimension_ids': jsonEncode(<String>['load', 'reps']),
    'default_load_unit': TrainingUnit.kilogram.name,
    'load_mode': ExerciseLoadMode.added.name,
    'record_profile': RecordProfile.repMax.name,
    'is_favorite': false,
    'is_unilateral': false,
    'uses_rpe': false,
    'category_id': categoryId,
    'equipment_ids': '[]',
    'notes': null,
    'updated_at': deletedAt.toIso8601String(),
    'deleted_at': deletedAt.toIso8601String(),
  };
}

Map<String, Object?> _pulledIntegrationConsentChange({
  required String id,
  required String dataClass,
  required bool enabled,
  required DateTime updatedAt,
  required String deviceId,
}) {
  return <String, Object?>{
    'entity': AppDatabase.integrationDataClassConsentsTable,
    'id': id,
    'deviceId': deviceId,
    'payload': _integrationConsentPayload(
      id,
      dataClass: dataClass,
      enabled: enabled,
      updatedAt: updatedAt,
    ),
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': null,
  };
}

Map<String, Object?> _integrationConsentPayload(
  String id, {
  required String dataClass,
  required bool enabled,
  required DateTime updatedAt,
  DateTime? deletedAt,
}) {
  return <String, Object?>{
    'id': id,
    'credential_id': 'credential-garmin-1',
    'data_class': dataClass,
    'enabled': enabled,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };
}

Future<IntegrationDataClassConsentRow> _integrationConsent(
  AppDatabase database,
  String id,
) {
  return (database.select(database.integrationDataClassConsents)
        ..where((row) => row.id.equals(id)))
      .getSingle();
}

Future<LoggedSetRow> _loggedSet(AppDatabase database, String id) {
  return (database.select(database.loggedSets)
        ..where((row) => row.id.equals(id)))
      .getSingle();
}

Future<List<QuarantinedSyncChangeRow>> _quarantinedChanges(
  AppDatabase database,
) {
  return (database.select(database.quarantinedSyncChanges)
        ..orderBy([(row) => OrderingTerm.asc(row.id)]))
      .get();
}

/// Records what `debugPrint` is asked to print for the rest of the test.
List<String> _captureDebugPrint() {
  final logs = <String>[];
  final original = debugPrint;
  debugPrint = (message, {wrapWidth}) {
    if (message != null) {
      logs.add(message);
    }
  };
  addTearDown(() => debugPrint = original);
  return logs;
}

Future<String?> _storedPullCursor(AppDatabase database) async {
  final row = await (database.select(database.syncStates)
        ..where((state) => state.id.equals(syncStateId)))
      .getSingleOrNull();
  return row?.pullCursor;
}

AuthSession _session() {
  return AuthSession(
    provider: AuthSessionProvider.email,
    serverUrl: Uri.parse('https://sync.example/'),
    token: 'session-token',
    userEmail: 'user@example.com',
    userId: 'user-1',
    userName: 'Sync User',
  );
}

LoggedSet _repsSet(String reps) {
  return LoggedSet.fromValues(
    <SetDimensionValue>[
      SetDimensionValue(
        dimension: DimensionId.reps,
        entered: reps,
        unit: TrainingUnit.repetition,
      ),
    ],
  );
}

NutrientVector _offNutrientsPer100() {
  return NutrientVector.energyAndMacros(
    energy: NutrientAmount.complete(
      value: 250,
      entered: '250',
      unit: NutrientUnit.kilocalorie,
    ),
    protein: NutrientAmount.complete(
      value: 8,
      entered: '8',
      unit: NutrientUnit.gram,
    ),
    carbohydrate: NutrientAmount.complete(
      value: 28,
      entered: '28',
      unit: NutrientUnit.gram,
    ),
    fat: NutrientAmount.complete(
      value: 11,
      entered: '11',
      unit: NutrientUnit.gram,
    ),
  );
}

const _coreCategoryId = '01910000-0000-7000-8000-000000000002';
const _fullPlankExerciseId = '01910000-0000-7000-8000-000000000102';
const _plankExerciseId = '01910000-0000-7000-8000-000000000201';
const _sideBendExerciseId = '01910000-0000-7000-8000-000000000202';

final _libraryStamp = DateTime.utc(2026, 1, 1);

/// Earlier than any clock a test runs under, so a user's edit stamps later.
final _plankRetiredAt = DateTime.utc(2026, 1, 5);

final _olderLibrary = PlatformExerciseSeed(
  categories: _libraryCategories,
  exercises: <SeedExercise>[
    _fullPlankInLibrary,
    SeedExercise(
      id: _plankExerciseId,
      name: 'Plank (old name)',
      dimensions: const <DimensionId>[DimensionId.reps],
      categoryId: _coreCategoryId,
      notes: 'An older note.',
      updatedAt: _libraryStamp,
    ),
    SeedExercise(
      id: _sideBendExerciseId,
      name: 'Side Bend',
      dimensions: const <DimensionId>[DimensionId.reps],
      categoryId: _coreCategoryId,
      notes: null,
      updatedAt: _libraryStamp,
    ),
  ],
);

/// The same library after it merged `Plank` and removed `Side Bend`.
final _updatedLibrary = PlatformExerciseSeed(
  categories: _libraryCategories,
  exercises: <SeedExercise>[_fullPlankInLibrary],
  retired: <SeedRetiredExercise>[
    SeedRetiredExercise(
      id: _plankExerciseId,
      name: 'Plank',
      dimensions: const <DimensionId>[DimensionId.reps],
      categoryId: _coreCategoryId,
      equipment: const <ExerciseEquipment>[ExerciseEquipment.gymMat],
      notes: 'Hold it.',
      updatedAt: _libraryStamp,
      retiredAt: _plankRetiredAt,
    ),
    SeedRetiredExercise(
      id: _sideBendExerciseId,
      name: 'Side Bend',
      dimensions: const <DimensionId>[DimensionId.reps],
      categoryId: _coreCategoryId,
      notes: null,
      updatedAt: _libraryStamp,
      retiredAt: _plankRetiredAt,
    ),
  ],
);

final _libraryCategories = <SeedExerciseCategory>[
  SeedExerciseCategory(
    id: _coreCategoryId,
    name: 'Core',
    sortOrder: 0,
    colorHex: '#1F9D55',
    updatedAt: _libraryStamp,
  ),
];

final _fullPlankInLibrary = SeedExercise(
  id: _fullPlankExerciseId,
  name: 'Full Plank',
  dimensions: const <DimensionId>[DimensionId.reps],
  categoryId: _coreCategoryId,
  notes: null,
  updatedAt: _libraryStamp,
);

class _LibrarySource implements PlatformExerciseSeedSource {
  const _LibrarySource(this.seed);

  final PlatformExerciseSeed seed;

  @override
  Future<PlatformExerciseSeed> load() async => seed;
}

/// One launch: the pass is memoized per instance, so a rerun needs a new one.
Future<TrainingRepositories> _launchLibrary(
  AppDatabase database,
  PlatformExerciseSeed seed,
) async {
  final repositories = TrainingRepositories(
    database,
    platformSeedSource: _LibrarySource(seed),
  );
  await repositories.catalog.ensurePlatformLibrarySeeded();
  return repositories;
}

/// A device on the older library that logged a Set against `Plank`.
Future<void> _logPlankOnOlderLibrary(AppDatabase database) async {
  final repositories = await _launchLibrary(database, _olderLibrary);
  final workoutId = await repositories.workoutSessions.create(
    WorkoutSessionDraft(
      startedAt: DateTime.utc(2026, 1, 2, 8),
      timezone: 'UTC',
    ),
  );
  await repositories.workoutExercises.create(
    WorkoutExerciseDraft(workoutId: workoutId, exerciseId: _plankExerciseId),
  );
  await repositories.sets.create(
    LoggedSetDraft(
      workoutId: workoutId,
      exerciseId: _plankExerciseId,
      position: 0,
      values: _repsSet('10'),
      isCompleted: true,
    ),
  );
}

/// [_logPlankOnOlderLibrary], then the launch on the updated library.
Future<TrainingRepositories> _keepPlankOn(AppDatabase database) async {
  await _logPlankOnOlderLibrary(database);
  final repositories = await _launchLibrary(database, _updatedLibrary);
  _expectKeptPlank(await _exerciseRow(database, _plankExerciseId));
  return repositories;
}

void _expectKeptPlank(ExerciseRow row) {
  expect(row.libraryOrigin, ExerciseLibraryOrigin.user.name);
  expect(row.deletedAt, isNull);
  expect(row.name, 'Plank');
  expect(row.categoryId, _coreCategoryId);
  expect(row.equipmentIds, '["gymMat"]');
  expect(row.notes, 'Hold it.');
  expect(row.updatedAt.toUtc(), _plankRetiredAt);
}

void _expectHiddenPlank(ExerciseRow row) {
  _expectHiddenRow(row);
  expect(row.name, 'Plank');
}

void _expectHiddenRow(ExerciseRow row) {
  expect(row.libraryOrigin, ExerciseLibraryOrigin.platform.name);
  expect(row.deletedAt?.toUtc(), _plankRetiredAt);
  expect(row.updatedAt.toUtc(), _libraryStamp);
}

Future<ExerciseRow> _exerciseRow(AppDatabase database, String id) {
  return (database.select(database.exercises)
        ..where((row) => row.id.equals(id)))
      .getSingle();
}

/// Pushes everything pending on [database] to a server that accepts it, and
/// returns the Exercise changes it sent.
Future<List<Map<String, Object?>>> _pushExerciseChanges(
  AppDatabase database, {
  required String deviceId,
}) async {
  final pushes = <Map<String, Object?>>[];
  await SyncRepository(
    database: database,
    apiClientFactory: _acceptingSyncApi(pushes: pushes),
  ).pushPendingLoggedSets(session: _session(), deviceId: deviceId);
  return _exerciseChangesIn(pushes);
}

List<Map<String, Object?>> _exerciseChangesIn(
  List<Map<String, Object?>> pushes,
) {
  return <Map<String, Object?>>[
    for (final body in pushes)
      if (body['entity'] == AppDatabase.exercisesTable)
        ...(body['changes']! as List<Object?>).cast<Map<String, Object?>>(),
  ];
}

Map<String, Object?> _lastExerciseChange(
  List<Map<String, Object?>> changes,
  String id,
) {
  return changes.lastWhere((change) => change['id'] == id);
}
