import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:perennia/api/perennia_api_client.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/settings/account_settings.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/activity/repositories/activity_feed_repository.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';
import 'package:perennia/features/sync/models/sync_status.dart';
import 'package:perennia/features/sync/repositories/sync_repository.dart';

void main() {
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
              'protocolVersion': 1,
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
      'protocolVersion': 1,
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
      MealDraft(
        mealType: 'Snack',
        startedAt: updatedAt,
        timezone: 'UTC',
        localDate: const NutritionDayDate(year: 2026, month: 6, day: 27),
      ),
      actor: 'tester',
    );
    final result = await repositories.nutrition.logFoodEntrySnapshot(
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
    await database.into(database.openFoodFactsCache).insert(
          OpenFoodFactsCacheCompanion.insert(
            lookupKey: 'barcode:3017620422003',
            foodId: '3017620422003',
            name: 'Original branded bar',
            nutrientValuesJson: _offNutrientsPer100().toJsonString(),
            isLiquid: const Value<bool>(false),
            servingLabel: const Value<String?>('serving'),
            servingSize: const Value<double?>(45),
            packageSize: const Value<double?>(60),
            fetchedAt: updatedAt,
            lastAccessedAt: updatedAt,
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
              'protocolVersion': 1,
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
    expect(
      pushedBodies.map((body) => body['entity']),
      isNot(contains(AppDatabase.openFoodFactsCacheTable)),
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
              'protocolVersion': 1,
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
    expect(await targetDatabase.select(targetDatabase.openFoodFactsCache).get(),
        isEmpty);
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
                'protocolVersion': 1,
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
              'protocolVersion': 1,
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
      'protocolVersion': 1,
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
      'protocolVersion': 1,
      'cursor': 'cursor-1',
      'limit': 100,
    });
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
      'protocolVersion': 1,
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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

  test('settings erase produces a logged set tombstone that pushes', () async {
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
          final deletedAt = change['deletedAt']! as String;
          expect(change['id'], setId);
          expect(deletedAt, isNotEmpty);
          expect((change['payload']! as Map<String, Object?>)['deleted_at'],
              deletedAt);
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': 1,
              'accepted': <String>[setId],
              'serverClock': '2026-06-22T08:00:01.000Z',
              'applied': <Object?>[
                <String, Object?>{
                  'id': setId,
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

    final result = await repository.pushPendingLoggedSets(
      session: _session(),
      deviceId: 'device-a',
    );
    final pendingRows = await (database.select(database.activityLog)
          ..where((row) => row.entityId.equals(setId))
          ..where((row) => row.syncAcknowledgedAt.isNull()))
        .get();

    expect(erasedSet.deletedAt, isNotNull);
    expect(erasedSet.syncPreviouslySynced, isTrue);
    expect(result.pushedCount, 1);
    expect(requests, hasLength(1));
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
                'protocolVersion': 1,
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
              'protocolVersion': 1,
              'cursor': '2000-01-01T00:00:00.000Z|expired-row',
              'limit': 100,
            });
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': 1,
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
                'protocolVersion': 1,
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
                'protocolVersion': 1,
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
                'protocolVersion': 1,
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
        startDate: DateTime.utc(2026, 7, 1),
        compoundIds: <String>[compound.compoundId],
        schedulesByCompoundId: <String, ScheduleDraft?>{
          compound.compoundId: const ScheduleDraft(
            doseAmountValue: 5,
            doseAmountEntered: '5',
            doseUnit: DoseUnit.gram,
            frequency: ScheduleFrequency.onceDaily,
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
              'protocolVersion': 1,
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
    expect(schedulePayload['dose_amount_entered'], '5');
    expect(schedulePayload['frequency'], ScheduleFrequency.onceDaily.name);

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
              'protocolVersion': 1,
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
    expect(pulledMember.schedule, isNotNull);
    expect(pulledMember.schedule!.doseAmountEntered, '5');
    expect(pulledMember.schedule!.frequency, ScheduleFrequency.onceDaily);
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
        startDate: DateTime.utc(2026, 7, 1),
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
              'protocolVersion': 1,
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
                    'start_date': '2026-07-01T00:00:00.000Z',
                    'end_date': null,
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
      MealDraft(
        mealType: mealTypeId,
        startedAt: DateTime.utc(2026, 7, 4, 8),
        timezone: 'Australia/Brisbane',
        localDate: const NutritionDayDate(year: 2026, month: 7, day: 4),
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
              'protocolVersion': 1,
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
              'protocolVersion': 1,
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
                'protocolVersion': 1,
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
              'protocolVersion': 1,
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
                  'protocolVersion': 1,
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
            'protocolVersion': 1,
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
