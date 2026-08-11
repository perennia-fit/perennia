import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/perennia_api_client.dart';
import '../../../data/local/app_database.dart';
import '../../../data/repositories/training_repositories.dart';
import '../../../data/sync/sync_lww.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../settings/repositories/integration_consent_repository.dart';
import '../models/sync_status.dart';

const syncProtocolVersion = 1;
const syncStateId = 'default';
const _syncPushBatchLimit = 100;
const _routinesSyncEntity = 'routines';
const _workoutStructureSyncEntities = <_PlanSyncEntity>[
  _PlanSyncEntity(
    localEntityTable: AppDatabase.workoutSessionsTable,
    remoteEntity: AppDatabase.workoutSessionsTable,
  ),
  _PlanSyncEntity(
    localEntityTable: AppDatabase.workoutExercisesTable,
    remoteEntity: AppDatabase.workoutExercisesTable,
  ),
  _PlanSyncEntity(
    localEntityTable: AppDatabase.exerciseGroupsTable,
    remoteEntity: AppDatabase.exerciseGroupsTable,
  ),
  _PlanSyncEntity(
    localEntityTable: AppDatabase.exerciseGroupMembersTable,
    remoteEntity: AppDatabase.exerciseGroupMembersTable,
  ),
];
const _planTreeSyncEntities = <_PlanSyncEntity>[
  _PlanSyncEntity(
    localEntityTable: AppDatabase.workoutTemplatesTable,
    remoteEntity: AppDatabase.workoutTemplatesTable,
  ),
  _PlanSyncEntity(
    localEntityTable: AppDatabase.templateExercisesTable,
    remoteEntity: AppDatabase.templateExercisesTable,
  ),
  _PlanSyncEntity(
    localEntityTable: AppDatabase.prescriptionsTable,
    remoteEntity: AppDatabase.prescriptionsTable,
  ),
  _PlanSyncEntity(
    localEntityTable: AppDatabase.templateGroupsTable,
    remoteEntity: AppDatabase.templateGroupsTable,
  ),
  _PlanSyncEntity(
    localEntityTable: AppDatabase.templateGroupMembersTable,
    remoteEntity: AppDatabase.templateGroupMembersTable,
  ),
  _PlanSyncEntity(
    localEntityTable: AppDatabase.planRoutinesTable,
    remoteEntity: _routinesSyncEntity,
  ),
  _PlanSyncEntity(
    localEntityTable: AppDatabase.routineEntriesTable,
    remoteEntity: AppDatabase.routineEntriesTable,
  ),
];
const _templateLinksSyncEntity = _PlanSyncEntity(
  localEntityTable: AppDatabase.templateLinksTable,
  remoteEntity: AppDatabase.templateLinksTable,
);
const _outboundSyncActivityTables = <String>[
  AppDatabase.exerciseCategoriesTable,
  AppDatabase.exercisesTable,
  AppDatabase.workoutSessionsTable,
  AppDatabase.workoutExercisesTable,
  AppDatabase.exerciseGroupsTable,
  AppDatabase.exerciseGroupMembersTable,
  AppDatabase.workoutTemplatesTable,
  AppDatabase.templateExercisesTable,
  AppDatabase.prescriptionsTable,
  AppDatabase.templateGroupsTable,
  AppDatabase.templateGroupMembersTable,
  AppDatabase.planRoutinesTable,
  AppDatabase.routineEntriesTable,
  AppDatabase.templateLinksTable,
  AppDatabase.loggedSetsTable,
  AppDatabase.foodsTable,
  AppDatabase.mealTypesTable,
  AppDatabase.mealsTable,
  AppDatabase.foodEntriesTable,
  AppDatabase.compoundsTable,
  AppDatabase.dosesTable,
  AppDatabase.protocolsTable,
  AppDatabase.protocolCompoundsTable,
  AppDatabase.protocolTargetOutcomesTable,
  AppDatabase.schedulesTable,
  AppDatabase.nutritionGoalsTable,
  AppDatabase.userSettingsTable,
  AppDatabase.integrationDataClassConsentsTable,
];

final syncStatusRepositoryProvider = Provider<SyncStatusRepository>((ref) {
  return SyncStatusRepository(ref.watch(appDatabaseProvider));
});

final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return SyncRepository(
    database: database,
    statusRepository: ref.watch(syncStatusRepositoryProvider),
  );
});

typedef SyncApiClientFactory = PerenniaApiClient Function(Uri baseUrl);

class SyncStatusRepository {
  SyncStatusRepository(
    this._database, {
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final AppDatabase _database;
  final DateTime Function() _clock;

  Stream<SyncStatusState> watchStatus({DateTime Function()? now}) {
    final observedAt = now ?? _clock;
    return (_database.select(_database.syncStates)
          ..where((state) => state.id.equals(syncStateId)))
        .watch()
        .map((rows) => _stateFromRow(
            rows.isEmpty ? null : rows.single, observedAt().toUtc()));
  }

  Future<SyncStatusState> loadStatus({DateTime? observedAt}) async {
    return _stateFromRow(
      await _loadRow(),
      (observedAt ?? _clock()).toUtc(),
    );
  }

  Future<void> recordSyncing({DateTime? at}) {
    final timestamp = (at ?? _clock()).toUtc();
    return _upsert(
      SyncStatesCompanion.insert(
        id: syncStateId,
        syncStatus: Value<String>(SyncStatusKind.syncing.name),
        updatedAt: timestamp,
      ),
    );
  }

  Future<void> recordSuccess({
    String? serverClock,
    DateTime? at,
  }) {
    final timestamp = (at ?? _clock()).toUtc();
    final lastSuccessfulSyncAt = _parseServerClock(serverClock) ?? timestamp;
    return _upsert(
      SyncStatesCompanion.insert(
        id: syncStateId,
        syncStatus: Value<String>(SyncStatusKind.synced.name),
        lastSuccessfulSyncAt: Value<DateTime?>(lastSuccessfulSyncAt),
        firstFailureAt: const Value<DateTime?>(null),
        lastFailureAt: const Value<DateTime?>(null),
        lastFailureMessage: const Value<String?>(null),
        updatedAt: timestamp,
      ),
    );
  }

  Future<void> recordFailure(Object error, {DateTime? at}) {
    if (_isAuthExpired(error)) {
      return recordAuthExpired(error, at: at);
    }
    return _recordFailure(
      error,
      kind: SyncStatusKind.failed,
      at: at,
    );
  }

  Future<void> recordAuthExpired(Object error, {DateTime? at}) {
    return _recordFailure(
      error,
      kind: SyncStatusKind.authExpired,
      at: at,
    );
  }

  Future<void> _recordFailure(
    Object error, {
    required SyncStatusKind kind,
    DateTime? at,
  }) async {
    final timestamp = (at ?? _clock()).toUtc();
    final current = await _loadRow();
    await _upsert(
      SyncStatesCompanion.insert(
        id: syncStateId,
        syncStatus: Value<String>(kind.name),
        firstFailureAt: Value<DateTime?>(
          current?.firstFailureAt?.toUtc() ?? timestamp,
        ),
        lastFailureAt: Value<DateTime?>(timestamp),
        lastFailureMessage: Value<String?>(_failureMessage(error, kind)),
        updatedAt: timestamp,
      ),
    );
  }

  Future<SyncStateRow?> _loadRow() {
    return (_database.select(_database.syncStates)
          ..where((state) => state.id.equals(syncStateId)))
        .getSingleOrNull();
  }

  Future<void> _upsert(SyncStatesCompanion companion) {
    return _database.into(_database.syncStates).insertOnConflictUpdate(
          companion,
        );
  }

  SyncStatusState _stateFromRow(SyncStateRow? row, DateTime observedAt) {
    if (row == null) {
      return SyncStatusState.initial(observedAt);
    }
    return SyncStatusState(
      kind: _syncStatusKind(row.syncStatus),
      lastSuccessfulSyncAt: row.lastSuccessfulSyncAt?.toUtc(),
      firstFailureAt: row.firstFailureAt?.toUtc(),
      lastFailureAt: row.lastFailureAt?.toUtc(),
      lastFailureMessage: row.lastFailureMessage,
      observedAt: observedAt,
    );
  }
}

abstract interface class SyncCycleRepository {
  Future<SyncPushResult> pushPendingLoggedSets({
    required AuthSession session,
    required String deviceId,
    bool manageStatus = true,
  });

  Future<SyncPushResult> pushPendingIntegrationDataClassConsents({
    required AuthSession session,
    required String deviceId,
    bool manageStatus = true,
  });

  Future<SyncPullResult> pullLoggedSetChanges({
    required AuthSession session,
    required String deviceId,
    int limit = 100,
    bool manageStatus = true,
  });

  Future<bool> hasPendingChanges();
}

class SyncRepository implements SyncCycleRepository {
  SyncRepository({
    required AppDatabase database,
    SyncApiClientFactory? apiClientFactory,
    SyncStatusRepository? statusRepository,
    TrainingRepositories? trainingRepositories,
  })  : _database = database,
        _repositories = trainingRepositories ?? TrainingRepositories(database),
        _statusRepository = statusRepository ?? SyncStatusRepository(database),
        _apiClientFactory = apiClientFactory ?? _defaultApiClient;

  final AppDatabase _database;
  final TrainingRepositories _repositories;
  final SyncStatusRepository _statusRepository;
  final SyncApiClientFactory _apiClientFactory;

  SyncStatusRepository get statusRepository => _statusRepository;

  Stream<int> watchPendingChangeCount() {
    final query = _database.selectOnly(_database.activityLog)
      ..addColumns(<Expression<Object>>[_database.activityLog.id])
      ..where(
        _database.activityLog.deletedAt.isNull() &
            _database.activityLog.syncAcknowledgedAt.isNull() &
            _database.activityLog.afterImage.isNotNull() &
            _database.activityLog.entityTable.isIn(
              _outboundSyncActivityTables,
            ),
      )
      ..limit(1);
    return query.watch().map((rows) => rows.isEmpty ? 0 : 1).distinct();
  }

  @override
  Future<bool> hasPendingChanges() async {
    if (await _hasPendingAuthoredLogRows()) {
      return true;
    }
    return (await _loadPendingIntegrationConsentRows()).isNotEmpty;
  }

  Future<DevicePushTokenRegistrationResult> registerDevicePushToken({
    required AuthSession session,
    required String deviceId,
    required String platform,
    required String token,
  }) async {
    final client = _apiClientFactory(session.serverUrl);
    try {
      final response = await client.registerDevicePushToken(
        bearerToken: session.token,
        deviceId: deviceId,
        platform: platform,
        token: token,
      );
      return DevicePushTokenRegistrationResult(
        registered: response.registered,
      );
    } finally {
      client.close();
    }
  }

  @override
  Future<SyncPushResult> pushPendingLoggedSets({
    required AuthSession session,
    required String deviceId,
    bool manageStatus = true,
  }) async {
    if (!await _hasPendingAuthoredLogRows()) {
      return const SyncPushResult(
        pushedCount: 0,
        acknowledgedActivityLogIds: <String>[],
        acceptedEntityIds: <String>[],
        serverClock: null,
      );
    }

    if (manageStatus) {
      await _statusRepository.recordSyncing();
    }
    final client = _apiClientFactory(session.serverUrl);
    try {
      final exerciseCategoriesResult =
          await _pushPendingExerciseCategoriesWithClient(
        client: client,
        session: session,
        deviceId: deviceId,
      );
      final exercisesResult = await _pushPendingExercisesWithClient(
        client: client,
        session: session,
        deviceId: deviceId,
      );
      final workoutStructureResults = <SyncPushResult>[];
      for (final entity in _workoutStructureSyncEntities) {
        workoutStructureResults.add(
          await _pushPendingPlanEntityWithClient(
            client: client,
            session: session,
            deviceId: deviceId,
            entity: entity,
          ),
        );
      }
      final planTreeResults = <SyncPushResult>[];
      for (final entity in _planTreeSyncEntities) {
        planTreeResults.add(
          await _pushPendingPlanEntityWithClient(
            client: client,
            session: session,
            deviceId: deviceId,
            entity: entity,
          ),
        );
      }
      final loggedSetsResult = await _pushPendingLoggedSetsWithClient(
        client: client,
        session: session,
        deviceId: deviceId,
      );
      final templateLinksResult = await _pushPendingPlanEntityWithClient(
        client: client,
        session: session,
        deviceId: deviceId,
        entity: _templateLinksSyncEntity,
      );
      final foodsResult = await _pushPendingFoodsWithClient(
        client: client,
        session: session,
        deviceId: deviceId,
      );
      final mealTypesResult = await _pushPendingMealTypesWithClient(
        client: client,
        session: session,
        deviceId: deviceId,
      );
      final mealsResult = await _pushPendingMealsWithClient(
        client: client,
        session: session,
        deviceId: deviceId,
      );
      final foodEntriesResult = await _pushPendingFoodEntriesWithClient(
        client: client,
        session: session,
        deviceId: deviceId,
      );
      final compoundsResult = await _pushPendingCompoundsWithClient(
        client: client,
        session: session,
        deviceId: deviceId,
      );
      final dosesResult = await _pushPendingDosesWithClient(
        client: client,
        session: session,
        deviceId: deviceId,
      );
      final protocolsResult = await _pushPendingProtocolsWithClient(
        client: client,
        session: session,
        deviceId: deviceId,
      );
      final protocolCompoundsResult =
          await _pushPendingProtocolCompoundsWithClient(
        client: client,
        session: session,
        deviceId: deviceId,
      );
      final protocolTargetOutcomesResult =
          await _pushPendingProtocolTargetOutcomesWithClient(
        client: client,
        session: session,
        deviceId: deviceId,
      );
      final schedulesResult = await _pushPendingSchedulesWithClient(
        client: client,
        session: session,
        deviceId: deviceId,
      );
      final nutritionGoalsResult = await _pushPendingNutritionGoalsWithClient(
        client: client,
        session: session,
        deviceId: deviceId,
      );
      final userSettingsResult = await _pushPendingUserSettingsWithClient(
        client: client,
        session: session,
        deviceId: deviceId,
      );
      final result = _mergePushResults(<SyncPushResult>[
        exerciseCategoriesResult,
        exercisesResult,
        ...workoutStructureResults,
        ...planTreeResults,
        loggedSetsResult,
        templateLinksResult,
        foodsResult,
        mealTypesResult,
        mealsResult,
        foodEntriesResult,
        compoundsResult,
        dosesResult,
        protocolsResult,
        protocolCompoundsResult,
        protocolTargetOutcomesResult,
        schedulesResult,
        nutritionGoalsResult,
        userSettingsResult,
      ]);
      if (manageStatus) {
        await _statusRepository.recordSuccess(serverClock: result.serverClock);
      }
      return result;
    } on Object catch (error) {
      if (manageStatus) {
        await _statusRepository.recordFailure(error);
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  @override
  Future<SyncPushResult> pushPendingIntegrationDataClassConsents({
    required AuthSession session,
    required String deviceId,
    bool manageStatus = true,
  }) async {
    final pendingRows = await _loadPendingIntegrationConsentRows();
    if (pendingRows.isEmpty) {
      return const SyncPushResult(
        pushedCount: 0,
        acknowledgedActivityLogIds: <String>[],
        acceptedEntityIds: <String>[],
        serverClock: null,
      );
    }

    if (manageStatus) {
      await _statusRepository.recordSyncing();
    }
    final client = _apiClientFactory(session.serverUrl);
    try {
      final result = await _pushPendingIntegrationConsentsWithClient(
        client: client,
        session: session,
        deviceId: deviceId,
      );
      if (manageStatus) {
        await _statusRepository.recordSuccess(serverClock: result.serverClock);
      }
      return result;
    } on Object catch (error) {
      if (manageStatus) {
        await _statusRepository.recordFailure(error);
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<SyncPushResult> _pushPendingLoggedSetsWithClient({
    required PerenniaApiClient client,
    required AuthSession session,
    required String deviceId,
  }) {
    return _pushPendingEntityRowsWithClient(
      client: client,
      session: session,
      deviceId: deviceId,
      entity: AppDatabase.loggedSetsTable,
      loadPendingRows: _loadPendingLoggedSetRows,
      guardPendingRows: _guardAgainstStaleLiveResurrection,
      acknowledgePushResponse: _acknowledgeLoggedSetPushResponse,
    );
  }

  Future<SyncPushResult> _pushPendingFoodsWithClient({
    required PerenniaApiClient client,
    required AuthSession session,
    required String deviceId,
  }) {
    return _pushPendingEntityRowsWithClient(
      client: client,
      session: session,
      deviceId: deviceId,
      entity: AppDatabase.foodsTable,
      loadPendingRows: _loadPendingFoodRows,
      acknowledgePushResponse: _acknowledgeFoodPushResponse,
    );
  }

  Future<SyncPushResult> _pushPendingMealTypesWithClient({
    required PerenniaApiClient client,
    required AuthSession session,
    required String deviceId,
  }) {
    return _pushPendingEntityRowsWithClient(
      client: client,
      session: session,
      deviceId: deviceId,
      entity: AppDatabase.mealTypesTable,
      loadPendingRows: _loadPendingMealTypeRows,
      acknowledgePushResponse: _acknowledgeMealTypePushResponse,
    );
  }

  Future<SyncPushResult> _pushPendingMealsWithClient({
    required PerenniaApiClient client,
    required AuthSession session,
    required String deviceId,
  }) {
    return _pushPendingEntityRowsWithClient(
      client: client,
      session: session,
      deviceId: deviceId,
      entity: AppDatabase.mealsTable,
      loadPendingRows: _loadPendingMealRows,
      acknowledgePushResponse: _acknowledgeMealPushResponse,
    );
  }

  Future<SyncPushResult> _pushPendingFoodEntriesWithClient({
    required PerenniaApiClient client,
    required AuthSession session,
    required String deviceId,
  }) {
    return _pushPendingEntityRowsWithClient(
      client: client,
      session: session,
      deviceId: deviceId,
      entity: AppDatabase.foodEntriesTable,
      loadPendingRows: _loadPendingFoodEntryRows,
      guardPendingRows: _guardAgainstStaleFoodEntryResurrection,
      acknowledgePushResponse: _acknowledgeFoodEntryPushResponse,
    );
  }

  Future<SyncPushResult> _pushPendingExerciseCategoriesWithClient({
    required PerenniaApiClient client,
    required AuthSession session,
    required String deviceId,
  }) {
    return _pushPendingEntityRowsWithClient(
      client: client,
      session: session,
      deviceId: deviceId,
      entity: AppDatabase.exerciseCategoriesTable,
      loadPendingRows: _loadPendingExerciseCategoryRows,
      acknowledgePushResponse: _acknowledgeExerciseCategoryPushResponse,
    );
  }

  Future<SyncPushResult> _pushPendingExercisesWithClient({
    required PerenniaApiClient client,
    required AuthSession session,
    required String deviceId,
  }) {
    return _pushPendingEntityRowsWithClient(
      client: client,
      session: session,
      deviceId: deviceId,
      entity: AppDatabase.exercisesTable,
      loadPendingRows: _loadPendingExerciseRows,
      // The Platform Library never syncs — only User Library rows
      // and shadowing customizations do.
      guardPendingRows: _guardAgainstPlatformExerciseRows,
      acknowledgePushResponse: _acknowledgeExercisePushResponse,
    );
  }

  Future<SyncPushResult> _pushPendingCompoundsWithClient({
    required PerenniaApiClient client,
    required AuthSession session,
    required String deviceId,
  }) {
    return _pushPendingEntityRowsWithClient(
      client: client,
      session: session,
      deviceId: deviceId,
      entity: AppDatabase.compoundsTable,
      loadPendingRows: _loadPendingCompoundRows,
      acknowledgePushResponse: _acknowledgeCompoundPushResponse,
    );
  }

  Future<SyncPushResult> _pushPendingDosesWithClient({
    required PerenniaApiClient client,
    required AuthSession session,
    required String deviceId,
  }) {
    return _pushPendingEntityRowsWithClient(
      client: client,
      session: session,
      deviceId: deviceId,
      entity: AppDatabase.dosesTable,
      loadPendingRows: _loadPendingDoseRows,
      // A Dose hard-deletes to a tombstone; guard against re-pushing a stale live
      // copy once a tombstone has already won locally (mirrors food entries).
      guardPendingRows: _guardAgainstStaleDoseResurrection,
      acknowledgePushResponse: _acknowledgeDosePushResponse,
    );
  }

  Future<SyncPushResult> _pushPendingProtocolsWithClient({
    required PerenniaApiClient client,
    required AuthSession session,
    required String deviceId,
  }) {
    return _pushPendingEntityRowsWithClient(
      client: client,
      session: session,
      deviceId: deviceId,
      entity: AppDatabase.protocolsTable,
      loadPendingRows: _loadPendingProtocolRows,
      acknowledgePushResponse: _acknowledgeProtocolPushResponse,
    );
  }

  Future<SyncPushResult> _pushPendingProtocolCompoundsWithClient({
    required PerenniaApiClient client,
    required AuthSession session,
    required String deviceId,
  }) {
    return _pushPendingEntityRowsWithClient(
      client: client,
      session: session,
      deviceId: deviceId,
      entity: AppDatabase.protocolCompoundsTable,
      loadPendingRows: _loadPendingProtocolCompoundRows,
      acknowledgePushResponse: _acknowledgeProtocolCompoundPushResponse,
    );
  }

  Future<SyncPushResult> _pushPendingProtocolTargetOutcomesWithClient({
    required PerenniaApiClient client,
    required AuthSession session,
    required String deviceId,
  }) {
    return _pushPendingEntityRowsWithClient(
      client: client,
      session: session,
      deviceId: deviceId,
      entity: AppDatabase.protocolTargetOutcomesTable,
      loadPendingRows: _loadPendingProtocolTargetOutcomeRows,
      acknowledgePushResponse: _acknowledgeProtocolTargetOutcomePushResponse,
    );
  }

  Future<SyncPushResult> _pushPendingSchedulesWithClient({
    required PerenniaApiClient client,
    required AuthSession session,
    required String deviceId,
  }) {
    return _pushPendingEntityRowsWithClient(
      client: client,
      session: session,
      deviceId: deviceId,
      entity: AppDatabase.schedulesTable,
      loadPendingRows: _loadPendingScheduleRows,
      acknowledgePushResponse: _acknowledgeSchedulePushResponse,
    );
  }

  Future<SyncPushResult> _pushPendingNutritionGoalsWithClient({
    required PerenniaApiClient client,
    required AuthSession session,
    required String deviceId,
  }) {
    return _pushPendingEntityRowsWithClient(
      client: client,
      session: session,
      deviceId: deviceId,
      entity: AppDatabase.nutritionGoalsTable,
      loadPendingRows: _loadPendingNutritionGoalRows,
      acknowledgePushResponse: _acknowledgeNutritionGoalPushResponse,
    );
  }

  Future<SyncPushResult> _pushPendingUserSettingsWithClient({
    required PerenniaApiClient client,
    required AuthSession session,
    required String deviceId,
  }) {
    return _pushPendingEntityRowsWithClient(
      client: client,
      session: session,
      deviceId: deviceId,
      entity: AppDatabase.userSettingsTable,
      loadPendingRows: _loadPendingUserSettingsRows,
      acknowledgePushResponse: _acknowledgeUserSettingsPushResponse,
    );
  }

  Future<SyncPushResult> _pushPendingPlanEntityWithClient({
    required PerenniaApiClient client,
    required AuthSession session,
    required String deviceId,
    required _PlanSyncEntity entity,
  }) {
    return _pushPendingEntityRowsWithClient(
      client: client,
      session: session,
      deviceId: deviceId,
      entity: entity.remoteEntity,
      loadPendingRows: () => _loadPendingPlanRows(entity.localEntityTable),
      acknowledgePushResponse: (rows, response) => _acknowledgePlanPushResponse(
        entity.localEntityTable,
        rows,
        response,
      ),
    );
  }

  Future<SyncPushResult> _pushPendingEntityRowsWithClient({
    required PerenniaApiClient client,
    required AuthSession session,
    required String deviceId,
    required String entity,
    required Future<List<ActivityLogRow>> Function() loadPendingRows,
    required Future<List<String>> Function(
      List<ActivityLogRow>,
      SyncPushResponse,
    ) acknowledgePushResponse,
    Future<_GuardedPendingRows> Function(List<ActivityLogRow>)?
        guardPendingRows,
  }) async {
    final pendingRows = await loadPendingRows();
    if (pendingRows.isEmpty) {
      return const SyncPushResult(
        pushedCount: 0,
        acknowledgedActivityLogIds: <String>[],
        acceptedEntityIds: <String>[],
        serverClock: null,
      );
    }

    var pushedCount = 0;
    final acknowledgedActivityLogIds = <String>[];
    final acceptedEntityIds = <String>[];
    String? serverClock;

    while (true) {
      final pendingRows = await loadPendingRows();
      if (pendingRows.isEmpty) {
        break;
      }
      final guarded = guardPendingRows == null
          ? _GuardedPendingRows(
              rows: pendingRows,
              acknowledgedActivityLogIds: const <String>[],
            )
          : await guardPendingRows(pendingRows);
      acknowledgedActivityLogIds.addAll(guarded.acknowledgedActivityLogIds);
      final batchRows = guarded.rows;
      if (batchRows.isEmpty) {
        continue;
      }

      final changes = batchRows.map(_changeFromActivityLogRow).toList();
      final response = await client.pushSync(
        bearerToken: session.token,
        protocolVersion: syncProtocolVersion,
        deviceId: deviceId,
        entity: entity,
        changes: changes,
      );
      pushedCount += changes.length;
      serverClock = response.serverClock;
      acceptedEntityIds.addAll(response.accepted);
      acknowledgedActivityLogIds.addAll(
        await acknowledgePushResponse(batchRows, response),
      );

      if (response.accepted.isEmpty) {
        break;
      }
    }

    return SyncPushResult(
      pushedCount: pushedCount,
      acknowledgedActivityLogIds: List<String>.unmodifiable(
        acknowledgedActivityLogIds,
      ),
      acceptedEntityIds: List<String>.unmodifiable(acceptedEntityIds),
      serverClock: serverClock,
    );
  }

  Future<SyncPushResult> _pushPendingIntegrationConsentsWithClient({
    required PerenniaApiClient client,
    required AuthSession session,
    required String deviceId,
  }) async {
    final pendingRows = await _loadPendingIntegrationConsentRows();
    if (pendingRows.isEmpty) {
      return const SyncPushResult(
        pushedCount: 0,
        acknowledgedActivityLogIds: <String>[],
        acceptedEntityIds: <String>[],
        serverClock: null,
      );
    }

    var pushedCount = 0;
    final acknowledgedActivityLogIds = <String>[];
    final acceptedEntityIds = <String>[];
    String? serverClock;

    while (true) {
      final batchRows = await _loadPendingIntegrationConsentRows();
      if (batchRows.isEmpty) {
        break;
      }

      final changes = batchRows.map(_changeFromActivityLogRow).toList();
      final response = await client.pushSync(
        bearerToken: session.token,
        protocolVersion: syncProtocolVersion,
        deviceId: deviceId,
        entity: AppDatabase.integrationDataClassConsentsTable,
        changes: changes,
      );
      pushedCount += changes.length;
      serverClock = response.serverClock;
      acceptedEntityIds.addAll(response.accepted);
      acknowledgedActivityLogIds.addAll(
        await _acknowledgeIntegrationConsentPushResponse(batchRows, response),
      );

      if (response.accepted.isEmpty) {
        break;
      }
    }

    return SyncPushResult(
      pushedCount: pushedCount,
      acknowledgedActivityLogIds: List<String>.unmodifiable(
        acknowledgedActivityLogIds,
      ),
      acceptedEntityIds: List<String>.unmodifiable(acceptedEntityIds),
      serverClock: serverClock,
    );
  }

  @override
  Future<SyncPullResult> pullLoggedSetChanges({
    required AuthSession session,
    required String deviceId,
    int limit = 100,
    bool manageStatus = true,
  }) async {
    final cursor = await _loadPullCursor();
    if (manageStatus) {
      await _statusRepository.recordSyncing();
    }
    final client = _apiClientFactory(session.serverUrl);
    try {
      final response = await client.pullSync(
        bearerToken: session.token,
        protocolVersion: syncProtocolVersion,
        cursor: cursor,
        limit: limit,
      );
      if (response.fullResyncRequired) {
        await _pushPendingExerciseCategoriesWithClient(
          client: client,
          session: session,
          deviceId: deviceId,
        );
        await _pushPendingExercisesWithClient(
          client: client,
          session: session,
          deviceId: deviceId,
        );
        for (final entity in _workoutStructureSyncEntities) {
          await _pushPendingPlanEntityWithClient(
            client: client,
            session: session,
            deviceId: deviceId,
            entity: entity,
          );
        }
        for (final entity in _planTreeSyncEntities) {
          await _pushPendingPlanEntityWithClient(
            client: client,
            session: session,
            deviceId: deviceId,
            entity: entity,
          );
        }
        await _pushPendingLoggedSetsWithClient(
          client: client,
          session: session,
          deviceId: deviceId,
        );
        await _pushPendingPlanEntityWithClient(
          client: client,
          session: session,
          deviceId: deviceId,
          entity: _templateLinksSyncEntity,
        );
        await _pushPendingFoodsWithClient(
          client: client,
          session: session,
          deviceId: deviceId,
        );
        await _pushPendingMealTypesWithClient(
          client: client,
          session: session,
          deviceId: deviceId,
        );
        await _pushPendingMealsWithClient(
          client: client,
          session: session,
          deviceId: deviceId,
        );
        await _pushPendingFoodEntriesWithClient(
          client: client,
          session: session,
          deviceId: deviceId,
        );
        await _pushPendingCompoundsWithClient(
          client: client,
          session: session,
          deviceId: deviceId,
        );
        await _pushPendingDosesWithClient(
          client: client,
          session: session,
          deviceId: deviceId,
        );
        await _pushPendingProtocolsWithClient(
          client: client,
          session: session,
          deviceId: deviceId,
        );
        await _pushPendingProtocolCompoundsWithClient(
          client: client,
          session: session,
          deviceId: deviceId,
        );
        await _pushPendingProtocolTargetOutcomesWithClient(
          client: client,
          session: session,
          deviceId: deviceId,
        );
        await _pushPendingSchedulesWithClient(
          client: client,
          session: session,
          deviceId: deviceId,
        );
        await _pushPendingNutritionGoalsWithClient(
          client: client,
          session: session,
          deviceId: deviceId,
        );
        await _pushPendingUserSettingsWithClient(
          client: client,
          session: session,
          deviceId: deviceId,
        );
        await _pushPendingIntegrationConsentsWithClient(
          client: client,
          session: session,
          deviceId: deviceId,
        );
        final snapshot = await _pullFullLoggedSetSnapshot(
          client: client,
          session: session,
          deviceId: deviceId,
          limit: limit,
        );
        final result = SyncPullResult(
          appliedCount: snapshot.appliedCount,
          nextCursor: snapshot.nextCursor,
          serverClock: snapshot.serverClock,
          fullResyncRequired: true,
          hasMore: false,
          // A full resync re-pulls every entity, including user_settings.
          userSettingsApplied: true,
        );
        if (manageStatus) {
          await _statusRepository.recordSuccess(
              serverClock: result.serverClock);
        }
        return result;
      }

      final applied = await _applyPulledSyncChanges(
        response.changes,
        deviceId: deviceId,
        persistCursor: true,
        cursorToSave: response.nextCursor,
      );

      final result = SyncPullResult(
        appliedCount: applied.appliedCount,
        nextCursor: response.nextCursor,
        serverClock: response.serverClock,
        fullResyncRequired: false,
        hasMore: response.changes.length == limit,
        userSettingsApplied: applied.userSettingsApplied,
      );
      if (manageStatus) {
        await _statusRepository.recordSuccess(serverClock: result.serverClock);
      }
      return result;
    } on Object catch (error) {
      if (manageStatus) {
        await _statusRepository.recordFailure(error);
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<_FullResyncSnapshotResult> _pullFullLoggedSetSnapshot({
    required PerenniaApiClient client,
    required AuthSession session,
    required String deviceId,
    required int limit,
  }) async {
    final liveExerciseCategorySnapshotIds = <String>{};
    final liveExerciseSnapshotIds = <String>{};
    final liveLoggedSetSnapshotIds = <String>{};
    final liveFoodSnapshotIds = <String>{};
    final liveMealTypeSnapshotIds = <String>{};
    final liveMealSnapshotIds = <String>{};
    final liveFoodEntrySnapshotIds = <String>{};
    final liveMetricSnapshotIds = <String>{};
    final liveMetricReadingSnapshotIds = <String>{};
    final liveCompoundSnapshotIds = <String>{};
    final liveDoseSnapshotIds = <String>{};
    final liveProtocolSnapshotIds = <String>{};
    final liveProtocolCompoundSnapshotIds = <String>{};
    final liveProtocolTargetOutcomeSnapshotIds = <String>{};
    final liveScheduleSnapshotIds = <String>{};
    final liveNutritionGoalSnapshotIds = <String>{};
    final liveIntegrationConsentSnapshotIds = <String>{};
    final livePlanSnapshotIds = <String, Set<String>>{
      for (final entity in <_PlanSyncEntity>[
        ..._workoutStructureSyncEntities,
        ..._planTreeSyncEntities,
        _templateLinksSyncEntity,
      ])
        entity.remoteEntity: <String>{},
    };
    var appliedCount = 0;
    String? cursor;
    String? nextCursor;
    String? serverClock;

    while (true) {
      final response = await client.pullSync(
        bearerToken: session.token,
        protocolVersion: syncProtocolVersion,
        cursor: cursor,
        limit: limit,
        mode: 'snapshot',
      );
      if (response.fullResyncRequired) {
        throw const FormatException(
          'Snapshot pull unexpectedly requested another full re-sync.',
        );
      }

      for (final change in response.changes) {
        livePlanSnapshotIds[change.entity]?.add(change.id);
        if (change.entity == AppDatabase.exerciseCategoriesTable) {
          liveExerciseCategorySnapshotIds.add(change.id);
        }
        if (change.entity == AppDatabase.exercisesTable) {
          liveExerciseSnapshotIds.add(change.id);
        }
        if (change.entity == AppDatabase.loggedSetsTable) {
          liveLoggedSetSnapshotIds.add(change.id);
        }
        if (change.entity == AppDatabase.foodsTable) {
          liveFoodSnapshotIds.add(change.id);
        }
        if (change.entity == AppDatabase.mealTypesTable) {
          liveMealTypeSnapshotIds.add(change.id);
        }
        if (change.entity == AppDatabase.mealsTable) {
          liveMealSnapshotIds.add(change.id);
        }
        if (change.entity == AppDatabase.foodEntriesTable) {
          liveFoodEntrySnapshotIds.add(change.id);
        }
        if (change.entity == AppDatabase.metricsTable) {
          liveMetricSnapshotIds.add(change.id);
        }
        if (change.entity == AppDatabase.metricReadingsTable) {
          liveMetricReadingSnapshotIds.add(change.id);
        }
        if (change.entity == AppDatabase.compoundsTable) {
          liveCompoundSnapshotIds.add(change.id);
        }
        if (change.entity == AppDatabase.dosesTable) {
          liveDoseSnapshotIds.add(change.id);
        }
        if (change.entity == AppDatabase.protocolsTable) {
          liveProtocolSnapshotIds.add(change.id);
        }
        if (change.entity == AppDatabase.protocolCompoundsTable) {
          liveProtocolCompoundSnapshotIds.add(change.id);
        }
        if (change.entity == AppDatabase.protocolTargetOutcomesTable) {
          liveProtocolTargetOutcomeSnapshotIds.add(change.id);
        }
        if (change.entity == AppDatabase.schedulesTable) {
          liveScheduleSnapshotIds.add(change.id);
        }
        if (change.entity == AppDatabase.nutritionGoalsTable) {
          liveNutritionGoalSnapshotIds.add(change.id);
        }
        if (change.entity == AppDatabase.integrationDataClassConsentsTable) {
          liveIntegrationConsentSnapshotIds.add(change.id);
        }
      }
      appliedCount += (await _applyPulledSyncChanges(
        response.changes,
        deviceId: deviceId,
      ))
          .appliedCount;
      nextCursor = response.nextCursor;
      serverClock = response.serverClock;

      if (response.changes.isEmpty) {
        break;
      }
      if (response.nextCursor == cursor) {
        throw const FormatException('Snapshot cursor did not advance.');
      }
      cursor = response.nextCursor;
    }

    final snapshotServerClock = serverClock;
    await _database.transaction(() async {
      await _markPreviouslySyncedExerciseCategoryRowsAbsentFromSnapshotDeleted(
        liveExerciseCategorySnapshotIds,
        DateTime.parse(snapshotServerClock).toUtc(),
      );
      await _markPreviouslySyncedExerciseRowsAbsentFromSnapshotDeleted(
        liveExerciseSnapshotIds,
        DateTime.parse(snapshotServerClock).toUtc(),
      );
      await _markPreviouslySyncedRowsAbsentFromSnapshotDeleted(
        liveLoggedSetSnapshotIds,
        DateTime.parse(snapshotServerClock).toUtc(),
      );
      await _markPreviouslySyncedFoodRowsAbsentFromSnapshotDeleted(
        liveFoodSnapshotIds,
        DateTime.parse(snapshotServerClock).toUtc(),
      );
      await _markPreviouslySyncedMealTypeRowsAbsentFromSnapshotDeleted(
        liveMealTypeSnapshotIds,
        DateTime.parse(snapshotServerClock).toUtc(),
      );
      await _markPreviouslySyncedMealRowsAbsentFromSnapshotDeleted(
        liveMealSnapshotIds,
        DateTime.parse(snapshotServerClock).toUtc(),
      );
      await _markPreviouslySyncedFoodEntryRowsAbsentFromSnapshotDeleted(
        liveFoodEntrySnapshotIds,
        DateTime.parse(snapshotServerClock).toUtc(),
      );
      await _markPreviouslySyncedMetricRowsAbsentFromSnapshotDeleted(
        liveMetricSnapshotIds,
        DateTime.parse(snapshotServerClock).toUtc(),
      );
      await _markPreviouslySyncedMetricReadingRowsAbsentFromSnapshotDeleted(
        liveMetricReadingSnapshotIds,
        DateTime.parse(snapshotServerClock).toUtc(),
      );
      await _markPreviouslySyncedCompoundRowsAbsentFromSnapshotDeleted(
        liveCompoundSnapshotIds,
        DateTime.parse(snapshotServerClock).toUtc(),
      );
      await _markPreviouslySyncedDoseRowsAbsentFromSnapshotDeleted(
        liveDoseSnapshotIds,
        DateTime.parse(snapshotServerClock).toUtc(),
      );
      await _markPreviouslySyncedProtocolRowsAbsentFromSnapshotDeleted(
        liveProtocolSnapshotIds,
        DateTime.parse(snapshotServerClock).toUtc(),
      );
      await _markPreviouslySyncedProtocolCompoundRowsAbsentFromSnapshotDeleted(
        liveProtocolCompoundSnapshotIds,
        DateTime.parse(snapshotServerClock).toUtc(),
      );
      await _markPreviouslySyncedProtocolTargetOutcomeRowsAbsentFromSnapshotDeleted(
        liveProtocolTargetOutcomeSnapshotIds,
        DateTime.parse(snapshotServerClock).toUtc(),
      );
      await _markPreviouslySyncedScheduleRowsAbsentFromSnapshotDeleted(
        liveScheduleSnapshotIds,
        DateTime.parse(snapshotServerClock).toUtc(),
      );
      await _markPreviouslySyncedNutritionGoalRowsAbsentFromSnapshotDeleted(
        liveNutritionGoalSnapshotIds,
        DateTime.parse(snapshotServerClock).toUtc(),
      );
      await _markPreviouslySyncedConsentRowsAbsentFromSnapshotDeleted(
        liveIntegrationConsentSnapshotIds,
        DateTime.parse(snapshotServerClock).toUtc(),
      );
      for (final entity in <_PlanSyncEntity>[
        _templateLinksSyncEntity,
        ..._planTreeSyncEntities.reversed,
        ..._workoutStructureSyncEntities.reversed,
      ]) {
        await _repositories.activityLog.markPlanRowsAbsentFromSnapshotDeleted(
          entityTable: entity.localEntityTable,
          liveSnapshotIds: livePlanSnapshotIds[entity.remoteEntity]!,
          timestamp: DateTime.parse(snapshotServerClock).toUtc(),
        );
      }
      await _savePullCursor(nextCursor);
    });

    return _FullResyncSnapshotResult(
      appliedCount: appliedCount,
      nextCursor: nextCursor,
      serverClock: snapshotServerClock,
    );
  }

  Future<({int appliedCount, bool userSettingsApplied})>
      _applyPulledSyncChanges(
    List<SyncPulledChange> changes, {
    required String deviceId,
    bool persistCursor = false,
    String? cursorToSave,
  }) async {
    var appliedCount = 0;
    var userSettingsApplied = false;
    final syncBatchId = _repositories.createId(DateTime.now().toUtc());
    final orderedChanges = changes.toList(growable: false)
      ..sort(_comparePulledChangesForApply);
    await _database.transaction(() async {
      for (final change in orderedChanges) {
        if (change.entity == AppDatabase.exerciseCategoriesTable) {
          final applied = await _applyPulledExerciseCategoryChange(
            change,
            deviceId: deviceId,
            syncBatchId: syncBatchId,
          );
          if (applied) {
            appliedCount += 1;
          }
          continue;
        }
        if (change.entity == AppDatabase.exercisesTable) {
          final applied = await _applyPulledExerciseChange(
            change,
            deviceId: deviceId,
            syncBatchId: syncBatchId,
          );
          if (applied) {
            appliedCount += 1;
          }
          continue;
        }
        if (change.entity == AppDatabase.loggedSetsTable) {
          final applied = await _applyPulledLoggedSetChange(
            change,
            deviceId: deviceId,
            syncBatchId: syncBatchId,
          );
          if (applied) {
            appliedCount += 1;
          }
          continue;
        }
        if (change.entity == AppDatabase.foodsTable) {
          final applied = await _applyPulledFoodChange(
            change,
            deviceId: deviceId,
            syncBatchId: syncBatchId,
          );
          if (applied) {
            appliedCount += 1;
          }
          continue;
        }
        if (change.entity == AppDatabase.mealTypesTable) {
          final applied = await _applyPulledMealTypeChange(
            change,
            deviceId: deviceId,
            syncBatchId: syncBatchId,
          );
          if (applied) {
            appliedCount += 1;
          }
          continue;
        }
        if (change.entity == AppDatabase.mealsTable) {
          final applied = await _applyPulledMealChange(
            change,
            deviceId: deviceId,
            syncBatchId: syncBatchId,
          );
          if (applied) {
            appliedCount += 1;
          }
          continue;
        }
        if (change.entity == AppDatabase.foodEntriesTable) {
          final applied = await _applyPulledFoodEntryChange(
            change,
            deviceId: deviceId,
            syncBatchId: syncBatchId,
          );
          if (applied) {
            appliedCount += 1;
          }
          continue;
        }
        if (change.entity == AppDatabase.metricsTable) {
          final applied = await _applyPulledMetricChange(
            change,
            deviceId: deviceId,
            syncBatchId: syncBatchId,
          );
          if (applied) {
            appliedCount += 1;
          }
          continue;
        }
        if (change.entity == AppDatabase.metricReadingsTable) {
          final applied = await _applyPulledMetricReadingChange(
            change,
            deviceId: deviceId,
            syncBatchId: syncBatchId,
          );
          if (applied) {
            appliedCount += 1;
          }
          continue;
        }
        if (change.entity == AppDatabase.compoundsTable) {
          final applied = await _applyPulledCompoundChange(
            change,
            deviceId: deviceId,
            syncBatchId: syncBatchId,
          );
          if (applied) {
            appliedCount += 1;
          }
          continue;
        }
        if (change.entity == AppDatabase.dosesTable) {
          final applied = await _applyPulledDoseChange(
            change,
            deviceId: deviceId,
            syncBatchId: syncBatchId,
          );
          if (applied) {
            appliedCount += 1;
          }
          continue;
        }
        if (change.entity == AppDatabase.protocolsTable) {
          final applied = await _applyPulledProtocolChange(
            change,
            deviceId: deviceId,
            syncBatchId: syncBatchId,
          );
          if (applied) {
            appliedCount += 1;
          }
          continue;
        }
        if (change.entity == AppDatabase.protocolCompoundsTable) {
          final applied = await _applyPulledProtocolCompoundChange(
            change,
            deviceId: deviceId,
            syncBatchId: syncBatchId,
          );
          if (applied) {
            appliedCount += 1;
          }
          continue;
        }
        if (change.entity == AppDatabase.protocolTargetOutcomesTable) {
          final applied = await _applyPulledProtocolTargetOutcomeChange(
            change,
            deviceId: deviceId,
            syncBatchId: syncBatchId,
          );
          if (applied) {
            appliedCount += 1;
          }
          continue;
        }
        if (change.entity == AppDatabase.schedulesTable) {
          final applied = await _applyPulledScheduleChange(
            change,
            deviceId: deviceId,
            syncBatchId: syncBatchId,
          );
          if (applied) {
            appliedCount += 1;
          }
          continue;
        }
        if (change.entity == AppDatabase.userSettingsTable) {
          final applied = await _applyPulledUserSettingsChange(
            change,
            deviceId: deviceId,
            syncBatchId: syncBatchId,
          );
          if (applied) {
            appliedCount += 1;
            userSettingsApplied = true;
          }
          continue;
        }
        if (change.entity == AppDatabase.nutritionGoalsTable) {
          final applied = await _applyPulledNutritionGoalChange(
            change,
            deviceId: deviceId,
            syncBatchId: syncBatchId,
          );
          if (applied) {
            appliedCount += 1;
          }
          continue;
        }
        if (change.entity == AppDatabase.integrationDataClassConsentsTable) {
          final applied = await _applyPulledIntegrationConsentChange(
            change,
            deviceId: deviceId,
            syncBatchId: syncBatchId,
          );
          if (applied) {
            appliedCount += 1;
          }
          continue;
        }
        final planEntity = _planSyncEntityForRemote(change.entity);
        if (planEntity != null) {
          final applied = await _repositories.activityLog.applyPlanSyncImage(
            entityTable: planEntity.localEntityTable,
            image: _syncImageFromPull(change),
            deviceId: change.deviceId,
            localDeviceId: deviceId,
            actor: _actorForPulledChange(change),
            batchId: change.batchId ?? syncBatchId,
            activityLogId: change.activityLogId,
            activityBeforeImage: change.beforeImage,
            activityAfterImage: change.afterImage,
            activityOccurredAt: change.occurredAt == null
                ? null
                : DateTime.parse(change.occurredAt!).toUtc(),
          );
          if (applied) {
            appliedCount += 1;
          }
          continue;
        }

        throw FormatException('Unsupported sync entity: ${change.entity}.');
      }
      if (persistCursor) {
        await _savePullCursor(cursorToSave);
      }
    });
    return (
      appliedCount: appliedCount,
      userSettingsApplied: userSettingsApplied
    );
  }

  Future<bool> _applyPulledFoodChange(
    SyncPulledChange change, {
    required String deviceId,
    required String syncBatchId,
  }) async {
    final existing = await (_database.select(_database.foods)
          ..where((row) => row.id.equals(change.id)))
        .getSingleOrNull();
    final incomingUpdatedAt = DateTime.parse(change.updatedAt).toUtc();
    final existingDeviceId = existing?.syncDeviceId ?? deviceId;
    if (existing != null &&
        !_lwwWins(
          incomingUpdatedAt,
          change.deviceId,
          existing.updatedAt.toUtc(),
          existingDeviceId,
        )) {
      return false;
    }

    await _repositories.nutrition.applySyncImage(
      entityTable: AppDatabase.foodsTable,
      image: _syncImageFromPull(change),
      deviceId: change.deviceId,
      actor: _actorForPulledChange(change),
      batchId: change.batchId ?? syncBatchId,
      activityLogId: change.activityLogId,
      activityBeforeImage: change.beforeImage,
      activityAfterImage: change.afterImage,
      activityOccurredAt: change.occurredAt == null
          ? null
          : DateTime.parse(change.occurredAt!).toUtc(),
    );
    return true;
  }

  Future<bool> _applyPulledMealTypeChange(
    SyncPulledChange change, {
    required String deviceId,
    required String syncBatchId,
  }) async {
    final existing = await (_database.select(_database.mealTypes)
          ..where((row) => row.id.equals(change.id)))
        .getSingleOrNull();
    final incomingUpdatedAt = DateTime.parse(change.updatedAt).toUtc();
    final existingDeviceId = existing?.syncDeviceId ?? deviceId;
    if (existing != null &&
        !_lwwWins(
          incomingUpdatedAt,
          change.deviceId,
          existing.updatedAt.toUtc(),
          existingDeviceId,
        )) {
      return false;
    }

    await _repositories.nutrition.applySyncImage(
      entityTable: AppDatabase.mealTypesTable,
      image: _syncImageFromPull(change),
      deviceId: change.deviceId,
      actor: _actorForPulledChange(change),
      batchId: change.batchId ?? syncBatchId,
      activityLogId: change.activityLogId,
      activityBeforeImage: change.beforeImage,
      activityAfterImage: change.afterImage,
      activityOccurredAt: change.occurredAt == null
          ? null
          : DateTime.parse(change.occurredAt!).toUtc(),
    );
    return true;
  }

  Future<bool> _applyPulledMealChange(
    SyncPulledChange change, {
    required String deviceId,
    required String syncBatchId,
  }) async {
    final existing = await (_database.select(_database.meals)
          ..where((row) => row.id.equals(change.id)))
        .getSingleOrNull();
    final incomingUpdatedAt = DateTime.parse(change.updatedAt).toUtc();
    final existingDeviceId = existing?.syncDeviceId ?? deviceId;
    if (existing != null &&
        !_lwwWins(
          incomingUpdatedAt,
          change.deviceId,
          existing.updatedAt.toUtc(),
          existingDeviceId,
        )) {
      return false;
    }

    await _repositories.nutrition.applySyncImage(
      entityTable: AppDatabase.mealsTable,
      image: _syncImageFromPull(change),
      deviceId: change.deviceId,
      actor: _actorForPulledChange(change),
      batchId: change.batchId ?? syncBatchId,
      activityLogId: change.activityLogId,
      activityBeforeImage: change.beforeImage,
      activityAfterImage: change.afterImage,
      activityOccurredAt: change.occurredAt == null
          ? null
          : DateTime.parse(change.occurredAt!).toUtc(),
    );
    return true;
  }

  Future<bool> _applyPulledFoodEntryChange(
    SyncPulledChange change, {
    required String deviceId,
    required String syncBatchId,
  }) async {
    final existing = await (_database.select(_database.foodEntries)
          ..where((row) => row.id.equals(change.id)))
        .getSingleOrNull();
    final incomingUpdatedAt = DateTime.parse(change.updatedAt).toUtc();
    final existingDeviceId = existing?.syncDeviceId ?? deviceId;
    if (existing != null &&
        !_lwwWins(
          incomingUpdatedAt,
          change.deviceId,
          existing.updatedAt.toUtc(),
          existingDeviceId,
        )) {
      return false;
    }

    await _repositories.nutrition.applySyncImage(
      entityTable: AppDatabase.foodEntriesTable,
      image: _syncImageFromPull(change),
      deviceId: change.deviceId,
      actor: _actorForPulledChange(change),
      batchId: change.batchId ?? syncBatchId,
      activityLogId: change.activityLogId,
      activityBeforeImage: change.beforeImage,
      activityAfterImage: change.afterImage,
      activityOccurredAt: change.occurredAt == null
          ? null
          : DateTime.parse(change.occurredAt!).toUtc(),
    );
    return true;
  }

  Future<bool> _applyPulledMetricChange(
    SyncPulledChange change, {
    required String deviceId,
    required String syncBatchId,
  }) async {
    final existing = await (_database.select(_database.metrics)
          ..where((row) => row.id.equals(change.id)))
        .getSingleOrNull();
    final incomingUpdatedAt = DateTime.parse(change.updatedAt).toUtc();
    final existingDeviceId = existing?.syncDeviceId ?? deviceId;
    if (existing != null &&
        !_lwwWins(
          incomingUpdatedAt,
          change.deviceId,
          existing.updatedAt.toUtc(),
          existingDeviceId,
        )) {
      return false;
    }

    await _repositories.metrics.applySyncImage(
      entityTable: AppDatabase.metricsTable,
      image: _syncImageFromPull(change),
      deviceId: change.deviceId,
      actor: _actorForPulledChange(change),
      batchId: change.batchId ?? syncBatchId,
      activityLogId: change.activityLogId,
      activityBeforeImage: change.beforeImage,
      activityAfterImage: change.afterImage,
      activityOccurredAt: change.occurredAt == null
          ? null
          : DateTime.parse(change.occurredAt!).toUtc(),
    );
    return true;
  }

  Future<bool> _applyPulledMetricReadingChange(
    SyncPulledChange change, {
    required String deviceId,
    required String syncBatchId,
  }) async {
    final existing = await (_database.select(_database.metricReadings)
          ..where((row) => row.id.equals(change.id)))
        .getSingleOrNull();
    final incomingUpdatedAt = DateTime.parse(change.updatedAt).toUtc();
    final existingDeviceId = existing?.syncDeviceId ?? deviceId;
    if (existing != null &&
        !_lwwWins(
          incomingUpdatedAt,
          change.deviceId,
          existing.updatedAt.toUtc(),
          existingDeviceId,
        )) {
      return false;
    }

    await _repositories.metrics.applySyncImage(
      entityTable: AppDatabase.metricReadingsTable,
      image: _metricReadingImageFromPull(change),
      deviceId: change.deviceId,
      actor: _actorForPulledChange(change),
      batchId: change.batchId ?? syncBatchId,
      activityLogId: change.activityLogId,
      activityBeforeImage: _normalizedMetricReadingActivityImage(
        change.beforeImage,
      ),
      activityAfterImage: _normalizedMetricReadingActivityImage(
        change.afterImage,
      ),
      activityOccurredAt: change.occurredAt == null
          ? null
          : DateTime.parse(change.occurredAt!).toUtc(),
    );
    return true;
  }

  Future<bool> _applyPulledCompoundChange(
    SyncPulledChange change, {
    required String deviceId,
    required String syncBatchId,
  }) async {
    final existing = await (_database.select(_database.compounds)
          ..where((row) => row.id.equals(change.id)))
        .getSingleOrNull();
    final incomingUpdatedAt = DateTime.parse(change.updatedAt).toUtc();
    final existingDeviceId = existing?.syncDeviceId ?? deviceId;
    if (existing != null &&
        !_lwwWins(
          incomingUpdatedAt,
          change.deviceId,
          existing.updatedAt.toUtc(),
          existingDeviceId,
        )) {
      return false;
    }

    await _repositories.protocols.applySyncImage(
      entityTable: AppDatabase.compoundsTable,
      image: _syncImageFromPull(change),
      deviceId: change.deviceId,
      actor: _actorForPulledChange(change),
      batchId: change.batchId ?? syncBatchId,
      activityLogId: change.activityLogId,
      activityBeforeImage: change.beforeImage,
      activityAfterImage: change.afterImage,
      activityOccurredAt: change.occurredAt == null
          ? null
          : DateTime.parse(change.occurredAt!).toUtc(),
    );
    return true;
  }

  Future<bool> _applyPulledDoseChange(
    SyncPulledChange change, {
    required String deviceId,
    required String syncBatchId,
  }) async {
    final existing = await (_database.select(_database.doses)
          ..where((row) => row.id.equals(change.id)))
        .getSingleOrNull();
    final incomingUpdatedAt = DateTime.parse(change.updatedAt).toUtc();
    final existingDeviceId = existing?.syncDeviceId ?? deviceId;
    if (existing != null &&
        !_lwwWins(
          incomingUpdatedAt,
          change.deviceId,
          existing.updatedAt.toUtc(),
          existingDeviceId,
        )) {
      return false;
    }

    // A Dose round-trips on its own self-contained snapshot — no Compound row
    // need exist on this device.
    await _repositories.protocols.applySyncImage(
      entityTable: AppDatabase.dosesTable,
      image: _syncImageFromPull(change),
      deviceId: change.deviceId,
      actor: _actorForPulledChange(change),
      batchId: change.batchId ?? syncBatchId,
      activityLogId: change.activityLogId,
      activityBeforeImage: change.beforeImage,
      activityAfterImage: change.afterImage,
      activityOccurredAt: change.occurredAt == null
          ? null
          : DateTime.parse(change.occurredAt!).toUtc(),
    );
    return true;
  }

  Future<bool> _applyPulledProtocolChange(
    SyncPulledChange change, {
    required String deviceId,
    required String syncBatchId,
  }) async {
    final existing = await (_database.select(_database.protocols)
          ..where((row) => row.id.equals(change.id)))
        .getSingleOrNull();
    final incomingUpdatedAt = DateTime.parse(change.updatedAt).toUtc();
    final existingDeviceId = existing?.syncDeviceId ?? deviceId;
    if (existing != null &&
        !_lwwWins(
          incomingUpdatedAt,
          change.deviceId,
          existing.updatedAt.toUtc(),
          existingDeviceId,
        )) {
      return false;
    }

    await _repositories.protocols.applySyncImage(
      entityTable: AppDatabase.protocolsTable,
      image: _syncImageFromPull(change),
      deviceId: change.deviceId,
      actor: _actorForPulledChange(change),
      batchId: change.batchId ?? syncBatchId,
      activityLogId: change.activityLogId,
      activityBeforeImage: change.beforeImage,
      activityAfterImage: change.afterImage,
      activityOccurredAt: change.occurredAt == null
          ? null
          : DateTime.parse(change.occurredAt!).toUtc(),
    );
    return true;
  }

  Future<bool> _applyPulledProtocolCompoundChange(
    SyncPulledChange change, {
    required String deviceId,
    required String syncBatchId,
  }) async {
    final existing = await (_database.select(_database.protocolCompounds)
          ..where((row) => row.id.equals(change.id)))
        .getSingleOrNull();
    final incomingUpdatedAt = DateTime.parse(change.updatedAt).toUtc();
    final existingDeviceId = existing?.syncDeviceId ?? deviceId;
    if (existing != null &&
        !_lwwWins(
          incomingUpdatedAt,
          change.deviceId,
          existing.updatedAt.toUtc(),
          existingDeviceId,
        )) {
      return false;
    }

    await _repositories.protocols.applySyncImage(
      entityTable: AppDatabase.protocolCompoundsTable,
      image: _syncImageFromPull(change),
      deviceId: change.deviceId,
      actor: _actorForPulledChange(change),
      batchId: change.batchId ?? syncBatchId,
      activityLogId: change.activityLogId,
      activityBeforeImage: change.beforeImage,
      activityAfterImage: change.afterImage,
      activityOccurredAt: change.occurredAt == null
          ? null
          : DateTime.parse(change.occurredAt!).toUtc(),
    );
    return true;
  }

  Future<bool> _applyPulledProtocolTargetOutcomeChange(
    SyncPulledChange change, {
    required String deviceId,
    required String syncBatchId,
  }) async {
    final existing = await (_database.select(_database.protocolTargetOutcomes)
          ..where((row) => row.id.equals(change.id)))
        .getSingleOrNull();
    final incomingUpdatedAt = DateTime.parse(change.updatedAt).toUtc();
    final existingDeviceId = existing?.syncDeviceId ?? deviceId;
    if (existing != null &&
        !_lwwWins(
          incomingUpdatedAt,
          change.deviceId,
          existing.updatedAt.toUtc(),
          existingDeviceId,
        )) {
      return false;
    }

    await _repositories.protocols.applySyncImage(
      entityTable: AppDatabase.protocolTargetOutcomesTable,
      image: _syncImageFromPull(change),
      deviceId: change.deviceId,
      actor: _actorForPulledChange(change),
      batchId: change.batchId ?? syncBatchId,
      activityLogId: change.activityLogId,
      activityBeforeImage: change.beforeImage,
      activityAfterImage: change.afterImage,
      activityOccurredAt: change.occurredAt == null
          ? null
          : DateTime.parse(change.occurredAt!).toUtc(),
    );
    return true;
  }

  Future<bool> _applyPulledScheduleChange(
    SyncPulledChange change, {
    required String deviceId,
    required String syncBatchId,
  }) async {
    final existing = await (_database.select(_database.schedules)
          ..where((row) => row.id.equals(change.id)))
        .getSingleOrNull();
    final incomingUpdatedAt = DateTime.parse(change.updatedAt).toUtc();
    final existingDeviceId = existing?.syncDeviceId ?? deviceId;
    if (existing != null &&
        !_lwwWins(
          incomingUpdatedAt,
          change.deviceId,
          existing.updatedAt.toUtc(),
          existingDeviceId,
        )) {
      return false;
    }

    // A Schedule's parent `ProtocolCompound` member applies before it
    // (`_syncApplyOrder`), so the Drift FK it references already exists on
    // this device.
    await _repositories.protocols.applySyncImage(
      entityTable: AppDatabase.schedulesTable,
      image: _syncImageFromPull(change),
      deviceId: change.deviceId,
      actor: _actorForPulledChange(change),
      batchId: change.batchId ?? syncBatchId,
      activityLogId: change.activityLogId,
      activityBeforeImage: change.beforeImage,
      activityAfterImage: change.afterImage,
      activityOccurredAt: change.occurredAt == null
          ? null
          : DateTime.parse(change.occurredAt!).toUtc(),
    );
    return true;
  }

  Future<bool> _applyPulledNutritionGoalChange(
    SyncPulledChange change, {
    required String deviceId,
    required String syncBatchId,
  }) async {
    final existing = await (_database.select(_database.nutritionGoals)
          ..where((row) => row.id.equals(change.id)))
        .getSingleOrNull();
    final incomingUpdatedAt = DateTime.parse(change.updatedAt).toUtc();
    final existingDeviceId = existing?.syncDeviceId ?? deviceId;
    if (existing != null &&
        !_lwwWins(
          incomingUpdatedAt,
          change.deviceId,
          existing.updatedAt.toUtc(),
          existingDeviceId,
        )) {
      return false;
    }

    await _repositories.nutrition.applySyncImage(
      entityTable: AppDatabase.nutritionGoalsTable,
      image: _syncImageFromPull(change),
      deviceId: change.deviceId,
      actor: _actorForPulledChange(change),
      batchId: change.batchId ?? syncBatchId,
      activityLogId: change.activityLogId,
      activityBeforeImage: change.beforeImage,
      activityAfterImage: change.afterImage,
      activityOccurredAt: change.occurredAt == null
          ? null
          : DateTime.parse(change.occurredAt!).toUtc(),
    );
    return true;
  }

  Future<bool> _applyPulledUserSettingsChange(
    SyncPulledChange change, {
    required String deviceId,
    required String syncBatchId,
  }) async {
    final existing = await (_database.select(_database.userSettings)
          ..where((row) => row.id.equals(change.id)))
        .getSingleOrNull();
    final incomingUpdatedAt = DateTime.parse(change.updatedAt).toUtc();
    final existingDeviceId = existing?.syncDeviceId ?? deviceId;
    if (existing != null &&
        !_lwwWins(
          incomingUpdatedAt,
          change.deviceId,
          existing.updatedAt.toUtc(),
          existingDeviceId,
        )) {
      return false;
    }

    await _repositories.accountSettings.applySyncImage(
      image: _syncImageFromPull(change),
      deviceId: change.deviceId,
      actor: _actorForPulledChange(change),
      batchId: change.batchId ?? syncBatchId,
      activityLogId: change.activityLogId,
      activityBeforeImage: change.beforeImage,
      activityAfterImage: change.afterImage,
      activityOccurredAt: change.occurredAt == null
          ? null
          : DateTime.parse(change.occurredAt!).toUtc(),
    );
    return true;
  }

  Future<bool> _applyPulledExerciseCategoryChange(
    SyncPulledChange change, {
    required String deviceId,
    required String syncBatchId,
  }) async {
    final existing = await (_database.select(_database.exerciseCategories)
          ..where((row) => row.id.equals(change.id)))
        .getSingleOrNull();
    final incomingUpdatedAt = DateTime.parse(change.updatedAt).toUtc();
    final existingDeviceId = existing?.syncDeviceId ?? deviceId;
    if (existing != null &&
        !_lwwWins(
          incomingUpdatedAt,
          change.deviceId,
          existing.updatedAt.toUtc(),
          existingDeviceId,
        )) {
      return false;
    }

    await _repositories.catalog.applySyncImage(
      entityTable: AppDatabase.exerciseCategoriesTable,
      image: _syncImageFromPull(change),
      deviceId: change.deviceId,
      actor: _actorForPulledChange(change),
      batchId: change.batchId ?? syncBatchId,
      activityLogId: change.activityLogId,
      activityBeforeImage: change.beforeImage,
      activityAfterImage: change.afterImage,
      activityOccurredAt: change.occurredAt == null
          ? null
          : DateTime.parse(change.occurredAt!).toUtc(),
    );
    return true;
  }

  Future<bool> _applyPulledExerciseChange(
    SyncPulledChange change, {
    required String deviceId,
    required String syncBatchId,
  }) async {
    final existing = await (_database.select(_database.exercises)
          ..where((row) => row.id.equals(change.id)))
        .getSingleOrNull();
    final incomingUpdatedAt = DateTime.parse(change.updatedAt).toUtc();
    final existingDeviceId = existing?.syncDeviceId ?? deviceId;
    if (existing != null &&
        !_lwwWins(
          incomingUpdatedAt,
          change.deviceId,
          existing.updatedAt.toUtc(),
          existingDeviceId,
        )) {
      return false;
    }

    // A pulled Exercise is always a User Library row or a shadowing
    // customization — the Platform Library never syncs, so the
    // incoming image always carries `library_origin: "user"`.
    await _repositories.catalog.applySyncImage(
      entityTable: AppDatabase.exercisesTable,
      image: _syncImageFromPull(change),
      deviceId: change.deviceId,
      actor: _actorForPulledChange(change),
      batchId: change.batchId ?? syncBatchId,
      activityLogId: change.activityLogId,
      activityBeforeImage: change.beforeImage,
      activityAfterImage: change.afterImage,
      activityOccurredAt: change.occurredAt == null
          ? null
          : DateTime.parse(change.occurredAt!).toUtc(),
    );
    return true;
  }

  Future<bool> _applyPulledLoggedSetChange(
    SyncPulledChange change, {
    required String deviceId,
    required String syncBatchId,
  }) async {
    final existing = await (_database.select(_database.loggedSets)
          ..where((row) => row.id.equals(change.id)))
        .getSingleOrNull();
    final incomingUpdatedAt = DateTime.parse(change.updatedAt).toUtc();
    final existingDeviceId = existing?.syncDeviceId ?? deviceId;
    if (existing != null &&
        !_lwwWins(
          incomingUpdatedAt,
          change.deviceId,
          existing.updatedAt.toUtc(),
          existingDeviceId,
        )) {
      return false;
    }

    await _repositories.sets.applySyncImage(
      image: _loggedSetImageFromPull(change),
      deviceId: change.deviceId,
      actor: _actorForPulledChange(change),
      batchId: change.batchId ?? syncBatchId,
      activityLogId: change.activityLogId,
      activityBeforeImage: change.beforeImage,
      activityAfterImage: change.afterImage,
      activityOccurredAt: change.occurredAt == null
          ? null
          : DateTime.parse(change.occurredAt!).toUtc(),
    );
    return true;
  }

  Future<bool> _applyPulledIntegrationConsentChange(
    SyncPulledChange change, {
    required String deviceId,
    required String syncBatchId,
  }) async {
    final image = _integrationConsentImageFromPull(change);
    final existing = await (_database.select(
      _database.integrationDataClassConsents,
    )..where((row) => row.id.equals(change.id)))
        .getSingleOrNull();
    final incomingUpdatedAt = DateTime.parse(change.updatedAt).toUtc();
    final existingDeviceId = existing?.syncDeviceId ?? deviceId;
    if (existing != null &&
        !_lwwWins(
          incomingUpdatedAt,
          change.deviceId,
          existing.updatedAt.toUtc(),
          existingDeviceId,
        )) {
      return false;
    }

    final beforeImage =
        existing == null ? null : integrationConsentImage(existing);
    await _database.into(_database.integrationDataClassConsents).insert(
          IntegrationDataClassConsentsCompanion.insert(
            id: change.id,
            credentialId: _requiredString(image, 'credential_id'),
            dataClass: _requiredImportDataClass(image),
            enabled: Value<bool>(_requiredBool(image, 'enabled')),
            syncDeviceId: Value<String?>(change.deviceId),
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: incomingUpdatedAt,
            deletedAt: Value<DateTime?>(
              change.deletedAt == null
                  ? null
                  : DateTime.parse(change.deletedAt!).toUtc(),
            ),
          ),
          mode: InsertMode.insertOrReplace,
        );
    final after = await (_database.select(
      _database.integrationDataClassConsents,
    )..where((row) => row.id.equals(change.id)))
        .getSingle();
    await _appendSyncActivityLog(
      entityTable: AppDatabase.integrationDataClassConsentsTable,
      entityId: change.id,
      beforeImage: change.beforeImage ?? beforeImage,
      afterImage: change.afterImage ?? integrationConsentImage(after),
      actor: _actorForPulledChange(change),
      batchId: change.batchId ?? syncBatchId,
      activityLogId: change.activityLogId,
      occurredAt: change.occurredAt == null
          ? incomingUpdatedAt
          : DateTime.parse(change.occurredAt!).toUtc(),
      syncAcknowledgedAt: incomingUpdatedAt,
    );
    return true;
  }

  Future<void>
      _markPreviouslySyncedExerciseCategoryRowsAbsentFromSnapshotDeleted(
    Set<String> liveSnapshotIds,
    DateTime timestamp,
  ) async {
    final localRows = await (_database.select(_database.exerciseCategories)
          ..where(
            (row) =>
                row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull(),
          ))
        .get();
    for (final row in localRows) {
      if (liveSnapshotIds.contains(row.id)) {
        continue;
      }
      await (_database.update(_database.exerciseCategories)
            ..where((table) => table.id.equals(row.id)))
          .write(
        ExerciseCategoriesCompanion(
          updatedAt: Value<DateTime>(timestamp),
          deletedAt: Value<DateTime?>(timestamp),
        ),
      );
    }
  }

  Future<void> _markPreviouslySyncedExerciseRowsAbsentFromSnapshotDeleted(
    Set<String> liveSnapshotIds,
    DateTime timestamp,
  ) async {
    final localRows = await (_database.select(_database.exercises)
          ..where(
            (row) =>
                row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull(),
          ))
        .get();
    for (final row in localRows) {
      if (liveSnapshotIds.contains(row.id)) {
        continue;
      }
      await (_database.update(_database.exercises)
            ..where((table) => table.id.equals(row.id)))
          .write(
        ExercisesCompanion(
          updatedAt: Value<DateTime>(timestamp),
          deletedAt: Value<DateTime?>(timestamp),
        ),
      );
    }
  }

  Future<void> _markPreviouslySyncedRowsAbsentFromSnapshotDeleted(
    Set<String> liveSnapshotIds,
    DateTime timestamp,
  ) async {
    final localRows = await (_database.select(_database.loggedSets)
          ..where(
            (row) =>
                row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull(),
          ))
        .get();
    for (final row in localRows) {
      if (liveSnapshotIds.contains(row.id)) {
        continue;
      }
      await (_database.update(_database.loggedSets)
            ..where((table) => table.id.equals(row.id)))
          .write(
        LoggedSetsCompanion(
          updatedAt: Value<DateTime>(timestamp),
          deletedAt: Value<DateTime?>(timestamp),
        ),
      );
    }
  }

  Future<void> _markPreviouslySyncedFoodRowsAbsentFromSnapshotDeleted(
    Set<String> liveSnapshotIds,
    DateTime timestamp,
  ) async {
    final localRows = await (_database.select(_database.foods)
          ..where(
            (row) =>
                row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull(),
          ))
        .get();
    for (final row in localRows) {
      if (liveSnapshotIds.contains(row.id)) {
        continue;
      }
      await (_database.update(_database.foods)
            ..where((table) => table.id.equals(row.id)))
          .write(
        FoodsCompanion(
          updatedAt: Value<DateTime>(timestamp),
          deletedAt: Value<DateTime?>(timestamp),
        ),
      );
    }
  }

  Future<void> _markPreviouslySyncedMealTypeRowsAbsentFromSnapshotDeleted(
    Set<String> liveSnapshotIds,
    DateTime timestamp,
  ) async {
    final localRows = await (_database.select(_database.mealTypes)
          ..where(
            (row) =>
                row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull(),
          ))
        .get();
    for (final row in localRows) {
      if (liveSnapshotIds.contains(row.id)) {
        continue;
      }
      await (_database.update(_database.mealTypes)
            ..where((table) => table.id.equals(row.id)))
          .write(
        MealTypesCompanion(
          updatedAt: Value<DateTime>(timestamp),
          deletedAt: Value<DateTime?>(timestamp),
        ),
      );
    }
  }

  Future<void> _markPreviouslySyncedMealRowsAbsentFromSnapshotDeleted(
    Set<String> liveSnapshotIds,
    DateTime timestamp,
  ) async {
    final localRows = await (_database.select(_database.meals)
          ..where(
            (row) =>
                row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull(),
          ))
        .get();
    for (final row in localRows) {
      if (liveSnapshotIds.contains(row.id)) {
        continue;
      }
      await (_database.update(_database.meals)
            ..where((table) => table.id.equals(row.id)))
          .write(
        MealsCompanion(
          updatedAt: Value<DateTime>(timestamp),
          deletedAt: Value<DateTime?>(timestamp),
        ),
      );
    }
  }

  Future<void> _markPreviouslySyncedFoodEntryRowsAbsentFromSnapshotDeleted(
    Set<String> liveSnapshotIds,
    DateTime timestamp,
  ) async {
    final localRows = await (_database.select(_database.foodEntries)
          ..where(
            (row) =>
                row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull(),
          ))
        .get();
    for (final row in localRows) {
      if (liveSnapshotIds.contains(row.id)) {
        continue;
      }
      await (_database.update(_database.foodEntries)
            ..where((table) => table.id.equals(row.id)))
          .write(
        FoodEntriesCompanion(
          updatedAt: Value<DateTime>(timestamp),
          deletedAt: Value<DateTime?>(timestamp),
        ),
      );
    }
  }

  Future<void> _markPreviouslySyncedMetricRowsAbsentFromSnapshotDeleted(
    Set<String> liveSnapshotIds,
    DateTime timestamp,
  ) async {
    final localRows = await (_database.select(_database.metrics)
          ..where(
            (row) =>
                row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull(),
          ))
        .get();
    for (final row in localRows) {
      if (liveSnapshotIds.contains(row.id)) {
        continue;
      }
      await (_database.update(_database.metrics)
            ..where((table) => table.id.equals(row.id)))
          .write(
        MetricsCompanion(
          updatedAt: Value<DateTime>(timestamp),
          deletedAt: Value<DateTime?>(timestamp),
        ),
      );
    }
  }

  Future<void> _markPreviouslySyncedMetricReadingRowsAbsentFromSnapshotDeleted(
    Set<String> liveSnapshotIds,
    DateTime timestamp,
  ) async {
    final localRows = await (_database.select(_database.metricReadings)
          ..where(
            (row) =>
                row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull(),
          ))
        .get();
    for (final row in localRows) {
      if (liveSnapshotIds.contains(row.id)) {
        continue;
      }
      await (_database.update(_database.metricReadings)
            ..where((table) => table.id.equals(row.id)))
          .write(
        MetricReadingsCompanion(
          updatedAt: Value<DateTime>(timestamp),
          deletedAt: Value<DateTime?>(timestamp),
        ),
      );
    }
  }

  Future<void> _markPreviouslySyncedCompoundRowsAbsentFromSnapshotDeleted(
    Set<String> liveSnapshotIds,
    DateTime timestamp,
  ) async {
    final localRows = await (_database.select(_database.compounds)
          ..where(
            (row) =>
                row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull(),
          ))
        .get();
    for (final row in localRows) {
      if (liveSnapshotIds.contains(row.id)) {
        continue;
      }
      await (_database.update(_database.compounds)
            ..where((table) => table.id.equals(row.id)))
          .write(
        CompoundsCompanion(
          updatedAt: Value<DateTime>(timestamp),
          deletedAt: Value<DateTime?>(timestamp),
        ),
      );
    }
  }

  Future<void> _markPreviouslySyncedDoseRowsAbsentFromSnapshotDeleted(
    Set<String> liveSnapshotIds,
    DateTime timestamp,
  ) async {
    final localRows = await (_database.select(_database.doses)
          ..where(
            (row) =>
                row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull(),
          ))
        .get();
    for (final row in localRows) {
      if (liveSnapshotIds.contains(row.id)) {
        continue;
      }
      await (_database.update(_database.doses)
            ..where((table) => table.id.equals(row.id)))
          .write(
        DosesCompanion(
          updatedAt: Value<DateTime>(timestamp),
          deletedAt: Value<DateTime?>(timestamp),
        ),
      );
    }
  }

  Future<void> _markPreviouslySyncedProtocolRowsAbsentFromSnapshotDeleted(
    Set<String> liveSnapshotIds,
    DateTime timestamp,
  ) async {
    final localRows = await (_database.select(_database.protocols)
          ..where(
            (row) =>
                row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull(),
          ))
        .get();
    for (final row in localRows) {
      if (liveSnapshotIds.contains(row.id)) {
        continue;
      }
      await (_database.update(_database.protocols)
            ..where((table) => table.id.equals(row.id)))
          .write(
        ProtocolsCompanion(
          updatedAt: Value<DateTime>(timestamp),
          deletedAt: Value<DateTime?>(timestamp),
        ),
      );
    }
  }

  Future<void>
      _markPreviouslySyncedProtocolCompoundRowsAbsentFromSnapshotDeleted(
    Set<String> liveSnapshotIds,
    DateTime timestamp,
  ) async {
    final localRows = await (_database.select(_database.protocolCompounds)
          ..where(
            (row) =>
                row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull(),
          ))
        .get();
    for (final row in localRows) {
      if (liveSnapshotIds.contains(row.id)) {
        continue;
      }
      await (_database.update(_database.protocolCompounds)
            ..where((table) => table.id.equals(row.id)))
          .write(
        ProtocolCompoundsCompanion(
          updatedAt: Value<DateTime>(timestamp),
          deletedAt: Value<DateTime?>(timestamp),
        ),
      );
    }
  }

  Future<void>
      _markPreviouslySyncedProtocolTargetOutcomeRowsAbsentFromSnapshotDeleted(
    Set<String> liveSnapshotIds,
    DateTime timestamp,
  ) async {
    final localRows = await (_database.select(_database.protocolTargetOutcomes)
          ..where(
            (row) =>
                row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull(),
          ))
        .get();
    for (final row in localRows) {
      if (liveSnapshotIds.contains(row.id)) {
        continue;
      }
      await (_database.update(_database.protocolTargetOutcomes)
            ..where((table) => table.id.equals(row.id)))
          .write(
        ProtocolTargetOutcomesCompanion(
          updatedAt: Value<DateTime>(timestamp),
          deletedAt: Value<DateTime?>(timestamp),
        ),
      );
    }
  }

  Future<void> _markPreviouslySyncedScheduleRowsAbsentFromSnapshotDeleted(
    Set<String> liveSnapshotIds,
    DateTime timestamp,
  ) async {
    final localRows = await (_database.select(_database.schedules)
          ..where(
            (row) =>
                row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull(),
          ))
        .get();
    for (final row in localRows) {
      if (liveSnapshotIds.contains(row.id)) {
        continue;
      }
      await (_database.update(_database.schedules)
            ..where((table) => table.id.equals(row.id)))
          .write(
        SchedulesCompanion(
          updatedAt: Value<DateTime>(timestamp),
          deletedAt: Value<DateTime?>(timestamp),
        ),
      );
    }
  }

  Future<void> _markPreviouslySyncedNutritionGoalRowsAbsentFromSnapshotDeleted(
    Set<String> liveSnapshotIds,
    DateTime timestamp,
  ) async {
    final localRows = await (_database.select(_database.nutritionGoals)
          ..where(
            (row) =>
                row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull(),
          ))
        .get();
    for (final row in localRows) {
      if (liveSnapshotIds.contains(row.id)) {
        continue;
      }
      await (_database.update(_database.nutritionGoals)
            ..where((table) => table.id.equals(row.id)))
          .write(
        NutritionGoalsCompanion(
          updatedAt: Value<DateTime>(timestamp),
          deletedAt: Value<DateTime?>(timestamp),
        ),
      );
    }
  }

  Future<void> _markPreviouslySyncedConsentRowsAbsentFromSnapshotDeleted(
    Set<String> liveSnapshotIds,
    DateTime timestamp,
  ) async {
    final localRows = await (_database.select(
      _database.integrationDataClassConsents,
    )..where(
            (row) =>
                row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull(),
          ))
        .get();
    for (final row in localRows) {
      if (liveSnapshotIds.contains(row.id)) {
        continue;
      }
      await (_database.update(_database.integrationDataClassConsents)
            ..where((table) => table.id.equals(row.id)))
          .write(
        IntegrationDataClassConsentsCompanion(
          enabled: const Value<bool>(false),
          updatedAt: Value<DateTime>(timestamp),
          deletedAt: Value<DateTime?>(timestamp),
        ),
      );
    }
  }

  Future<String?> _loadPullCursor() async {
    final row = await (_database.select(_database.syncStates)
          ..where((state) => state.id.equals(syncStateId)))
        .getSingleOrNull();
    return row?.pullCursor;
  }

  Future<void> _savePullCursor(String? cursor) {
    return _database.into(_database.syncStates).insertOnConflictUpdate(
          SyncStatesCompanion.insert(
            id: syncStateId,
            pullCursor: Value<String?>(cursor),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<bool> _hasPendingAuthoredLogRows() async {
    final authoredTables = _outboundSyncActivityTables
        .where(
          (table) => table != AppDatabase.integrationDataClassConsentsTable,
        )
        .toList(growable: false);
    final query = _database.selectOnly(_database.activityLog)
      ..addColumns(<Expression<Object>>[_database.activityLog.id])
      ..where(
        _database.activityLog.deletedAt.isNull() &
            _database.activityLog.syncAcknowledgedAt.isNull() &
            _database.activityLog.afterImage.isNotNull() &
            _database.activityLog.entityTable.isIn(authoredTables),
      )
      ..limit(1);
    return (await query.get()).isNotEmpty;
  }

  Future<List<ActivityLogRow>> _loadPendingPlanRows(String entityTable) {
    return (_database.select(_database.activityLog)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.syncAcknowledgedAt.isNull() &
                row.entityTable.equals(entityTable) &
                row.afterImage.isNotNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.occurredAt),
            (row) => OrderingTerm.asc(row.id),
          ])
          ..limit(_syncPushBatchLimit))
        .get();
  }

  Future<List<ActivityLogRow>> _loadPendingExerciseCategoryRows() {
    return (_database.select(_database.activityLog)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.syncAcknowledgedAt.isNull() &
                row.entityTable.equals(AppDatabase.exerciseCategoriesTable) &
                row.afterImage.isNotNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.occurredAt),
            (row) => OrderingTerm.asc(row.id),
          ])
          ..limit(_syncPushBatchLimit))
        .get();
  }

  Future<List<ActivityLogRow>> _loadPendingExerciseRows() {
    return (_database.select(_database.activityLog)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.syncAcknowledgedAt.isNull() &
                row.entityTable.equals(AppDatabase.exercisesTable) &
                row.afterImage.isNotNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.occurredAt),
            (row) => OrderingTerm.asc(row.id),
          ])
          ..limit(_syncPushBatchLimit))
        .get();
  }

  Future<List<ActivityLogRow>> _loadPendingLoggedSetRows() {
    return (_database.select(_database.activityLog)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.syncAcknowledgedAt.isNull() &
                row.entityTable.equals(AppDatabase.loggedSetsTable) &
                row.afterImage.isNotNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.occurredAt),
            (row) => OrderingTerm.asc(row.id),
          ])
          ..limit(_syncPushBatchLimit))
        .get();
  }

  Future<List<ActivityLogRow>> _loadPendingFoodRows() {
    return (_database.select(_database.activityLog)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.syncAcknowledgedAt.isNull() &
                row.entityTable.equals(AppDatabase.foodsTable) &
                row.afterImage.isNotNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.occurredAt),
            (row) => OrderingTerm.asc(row.id),
          ])
          ..limit(_syncPushBatchLimit))
        .get();
  }

  Future<List<ActivityLogRow>> _loadPendingMealTypeRows() {
    return (_database.select(_database.activityLog)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.syncAcknowledgedAt.isNull() &
                row.entityTable.equals(AppDatabase.mealTypesTable) &
                row.afterImage.isNotNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.occurredAt),
            (row) => OrderingTerm.asc(row.id),
          ])
          ..limit(_syncPushBatchLimit))
        .get();
  }

  Future<List<ActivityLogRow>> _loadPendingMealRows() {
    return (_database.select(_database.activityLog)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.syncAcknowledgedAt.isNull() &
                row.entityTable.equals(AppDatabase.mealsTable) &
                row.afterImage.isNotNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.occurredAt),
            (row) => OrderingTerm.asc(row.id),
          ])
          ..limit(_syncPushBatchLimit))
        .get();
  }

  Future<List<ActivityLogRow>> _loadPendingFoodEntryRows() {
    return (_database.select(_database.activityLog)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.syncAcknowledgedAt.isNull() &
                row.entityTable.equals(AppDatabase.foodEntriesTable) &
                row.afterImage.isNotNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.occurredAt),
            (row) => OrderingTerm.asc(row.id),
          ])
          ..limit(_syncPushBatchLimit))
        .get();
  }

  Future<List<ActivityLogRow>> _loadPendingCompoundRows() {
    return (_database.select(_database.activityLog)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.syncAcknowledgedAt.isNull() &
                row.entityTable.equals(AppDatabase.compoundsTable) &
                row.afterImage.isNotNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.occurredAt),
            (row) => OrderingTerm.asc(row.id),
          ])
          ..limit(_syncPushBatchLimit))
        .get();
  }

  Future<List<ActivityLogRow>> _loadPendingDoseRows() {
    return (_database.select(_database.activityLog)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.syncAcknowledgedAt.isNull() &
                row.entityTable.equals(AppDatabase.dosesTable) &
                row.afterImage.isNotNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.occurredAt),
            (row) => OrderingTerm.asc(row.id),
          ])
          ..limit(_syncPushBatchLimit))
        .get();
  }

  Future<List<ActivityLogRow>> _loadPendingProtocolRows() {
    return (_database.select(_database.activityLog)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.syncAcknowledgedAt.isNull() &
                row.entityTable.equals(AppDatabase.protocolsTable) &
                row.afterImage.isNotNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.occurredAt),
            (row) => OrderingTerm.asc(row.id),
          ])
          ..limit(_syncPushBatchLimit))
        .get();
  }

  Future<List<ActivityLogRow>> _loadPendingProtocolCompoundRows() {
    return (_database.select(_database.activityLog)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.syncAcknowledgedAt.isNull() &
                row.entityTable.equals(AppDatabase.protocolCompoundsTable) &
                row.afterImage.isNotNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.occurredAt),
            (row) => OrderingTerm.asc(row.id),
          ])
          ..limit(_syncPushBatchLimit))
        .get();
  }

  Future<List<ActivityLogRow>> _loadPendingProtocolTargetOutcomeRows() {
    return (_database.select(_database.activityLog)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.syncAcknowledgedAt.isNull() &
                row.entityTable
                    .equals(AppDatabase.protocolTargetOutcomesTable) &
                row.afterImage.isNotNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.occurredAt),
            (row) => OrderingTerm.asc(row.id),
          ])
          ..limit(_syncPushBatchLimit))
        .get();
  }

  Future<List<ActivityLogRow>> _loadPendingScheduleRows() {
    return (_database.select(_database.activityLog)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.syncAcknowledgedAt.isNull() &
                row.entityTable.equals(AppDatabase.schedulesTable) &
                row.afterImage.isNotNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.occurredAt),
            (row) => OrderingTerm.asc(row.id),
          ])
          ..limit(_syncPushBatchLimit))
        .get();
  }

  Future<List<ActivityLogRow>> _loadPendingNutritionGoalRows() {
    return (_database.select(_database.activityLog)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.syncAcknowledgedAt.isNull() &
                row.entityTable.equals(AppDatabase.nutritionGoalsTable) &
                row.afterImage.isNotNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.occurredAt),
            (row) => OrderingTerm.asc(row.id),
          ])
          ..limit(_syncPushBatchLimit))
        .get();
  }

  Future<List<ActivityLogRow>> _loadPendingUserSettingsRows() {
    return (_database.select(_database.activityLog)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.syncAcknowledgedAt.isNull() &
                row.entityTable.equals(AppDatabase.userSettingsTable) &
                row.afterImage.isNotNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.occurredAt),
            (row) => OrderingTerm.asc(row.id),
          ])
          ..limit(_syncPushBatchLimit))
        .get();
  }

  Future<List<ActivityLogRow>> _loadPendingIntegrationConsentRows() {
    return (_database.select(_database.activityLog)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.syncAcknowledgedAt.isNull() &
                row.entityTable.equals(
                  AppDatabase.integrationDataClassConsentsTable,
                ) &
                row.afterImage.isNotNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.occurredAt),
            (row) => OrderingTerm.asc(row.id),
          ])
          ..limit(_syncPushBatchLimit))
        .get();
  }

  Future<List<String>> _acknowledgePlanPushResponse(
    String entityTable,
    List<ActivityLogRow> pendingRows,
    SyncPushResponse response,
  ) async {
    final acceptedEntityIds = response.accepted.toSet();
    final appliedById = <String, SyncAppliedChange>{
      for (final change in response.applied) change.id: change,
    };
    final acknowledgedRows = pendingRows
        .where((row) => acceptedEntityIds.contains(row.entityId))
        .toList(growable: false);
    final acknowledgedAt = DateTime.now().toUtc();

    await _database.transaction(() async {
      for (final row in acknowledgedRows) {
        final applied = appliedById[row.entityId];
        await (_database.update(_database.activityLog)
              ..where((table) => table.id.equals(row.id)))
            .write(
          ActivityLogCompanion(
            syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
            afterImage: applied == null
                ? const Value.absent()
                : Value<String?>(
                    _imageWithUpdatedAt(row.afterImage, applied.updatedAt),
                  ),
          ),
        );
        await _repositories.activityLog.markPlanRowSynced(
          entityTable: entityTable,
          id: row.entityId,
          deviceId: applied?.deviceId,
          updatedAt: applied == null
              ? null
              : DateTime.parse(applied.updatedAt).toUtc(),
        );
      }
    });

    return List<String>.unmodifiable(acknowledgedRows.map((row) => row.id));
  }

  Future<List<String>> _acknowledgeLoggedSetPushResponse(
    List<ActivityLogRow> pendingRows,
    SyncPushResponse response,
  ) async {
    final acceptedEntityIds = response.accepted.toSet();
    final appliedById = <String, SyncAppliedChange>{
      for (final change in response.applied) change.id: change,
    };
    final acknowledgedRows = pendingRows
        .where((row) => acceptedEntityIds.contains(row.entityId))
        .toList(growable: false);
    final acknowledgedAt = DateTime.now().toUtc();

    await _database.transaction(() async {
      for (final row in acknowledgedRows) {
        final applied = appliedById[row.entityId];
        await (_database.update(_database.activityLog)
              ..where((table) => table.id.equals(row.id)))
            .write(
          ActivityLogCompanion(
            syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
            afterImage: applied == null
                ? const Value.absent()
                : Value<String?>(
                    _imageWithUpdatedAt(row.afterImage, applied.updatedAt),
                  ),
          ),
        );
        await (_database.update(_database.loggedSets)
              ..where((table) => table.id.equals(row.entityId)))
            .write(
          const LoggedSetsCompanion(
            syncPreviouslySynced: Value<bool>(true),
          ),
        );
      }
      for (final change in response.applied) {
        await (_database.update(_database.loggedSets)
              ..where((row) => row.id.equals(change.id)))
            .write(
          LoggedSetsCompanion(
            syncDeviceId: Value<String?>(change.deviceId),
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: Value<DateTime>(
              DateTime.parse(change.updatedAt).toUtc(),
            ),
          ),
        );
      }
    });

    return List<String>.unmodifiable(acknowledgedRows.map((row) => row.id));
  }

  Future<List<String>> _acknowledgeFoodPushResponse(
    List<ActivityLogRow> pendingRows,
    SyncPushResponse response,
  ) async {
    final acceptedEntityIds = response.accepted.toSet();
    final appliedById = <String, SyncAppliedChange>{
      for (final change in response.applied) change.id: change,
    };
    final acknowledgedRows = pendingRows
        .where((row) => acceptedEntityIds.contains(row.entityId))
        .toList(growable: false);
    final acknowledgedAt = DateTime.now().toUtc();

    await _database.transaction(() async {
      for (final row in acknowledgedRows) {
        final applied = appliedById[row.entityId];
        await (_database.update(_database.activityLog)
              ..where((table) => table.id.equals(row.id)))
            .write(
          ActivityLogCompanion(
            syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
            afterImage: applied == null
                ? const Value.absent()
                : Value<String?>(
                    _imageWithUpdatedAt(row.afterImage, applied.updatedAt),
                  ),
          ),
        );
        await (_database.update(_database.foods)
              ..where((table) => table.id.equals(row.entityId)))
            .write(
          const FoodsCompanion(
            syncPreviouslySynced: Value<bool>(true),
          ),
        );
      }
      for (final change in response.applied) {
        await (_database.update(_database.foods)
              ..where((row) => row.id.equals(change.id)))
            .write(
          FoodsCompanion(
            syncDeviceId: Value<String?>(change.deviceId),
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: Value<DateTime>(
              DateTime.parse(change.updatedAt).toUtc(),
            ),
          ),
        );
      }
    });

    return List<String>.unmodifiable(acknowledgedRows.map((row) => row.id));
  }

  Future<List<String>> _acknowledgeMealTypePushResponse(
    List<ActivityLogRow> pendingRows,
    SyncPushResponse response,
  ) async {
    final acceptedEntityIds = response.accepted.toSet();
    final appliedById = <String, SyncAppliedChange>{
      for (final change in response.applied) change.id: change,
    };
    final acknowledgedRows = pendingRows
        .where((row) => acceptedEntityIds.contains(row.entityId))
        .toList(growable: false);
    final acknowledgedAt = DateTime.now().toUtc();

    await _database.transaction(() async {
      for (final row in acknowledgedRows) {
        final applied = appliedById[row.entityId];
        await (_database.update(_database.activityLog)
              ..where((table) => table.id.equals(row.id)))
            .write(
          ActivityLogCompanion(
            syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
            afterImage: applied == null
                ? const Value.absent()
                : Value<String?>(
                    _imageWithUpdatedAt(row.afterImage, applied.updatedAt),
                  ),
          ),
        );
        await (_database.update(_database.mealTypes)
              ..where((table) => table.id.equals(row.entityId)))
            .write(
          const MealTypesCompanion(
            syncPreviouslySynced: Value<bool>(true),
          ),
        );
      }
      for (final change in response.applied) {
        await (_database.update(_database.mealTypes)
              ..where((row) => row.id.equals(change.id)))
            .write(
          MealTypesCompanion(
            syncDeviceId: Value<String?>(change.deviceId),
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: Value<DateTime>(
              DateTime.parse(change.updatedAt).toUtc(),
            ),
          ),
        );
      }
    });

    return List<String>.unmodifiable(acknowledgedRows.map((row) => row.id));
  }

  Future<List<String>> _acknowledgeMealPushResponse(
    List<ActivityLogRow> pendingRows,
    SyncPushResponse response,
  ) async {
    final acceptedEntityIds = response.accepted.toSet();
    final appliedById = <String, SyncAppliedChange>{
      for (final change in response.applied) change.id: change,
    };
    final acknowledgedRows = pendingRows
        .where((row) => acceptedEntityIds.contains(row.entityId))
        .toList(growable: false);
    final acknowledgedAt = DateTime.now().toUtc();

    await _database.transaction(() async {
      for (final row in acknowledgedRows) {
        final applied = appliedById[row.entityId];
        await (_database.update(_database.activityLog)
              ..where((table) => table.id.equals(row.id)))
            .write(
          ActivityLogCompanion(
            syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
            afterImage: applied == null
                ? const Value.absent()
                : Value<String?>(
                    _imageWithUpdatedAt(row.afterImage, applied.updatedAt),
                  ),
          ),
        );
        await (_database.update(_database.meals)
              ..where((table) => table.id.equals(row.entityId)))
            .write(
          const MealsCompanion(
            syncPreviouslySynced: Value<bool>(true),
          ),
        );
      }
      for (final change in response.applied) {
        await (_database.update(_database.meals)
              ..where((row) => row.id.equals(change.id)))
            .write(
          MealsCompanion(
            syncDeviceId: Value<String?>(change.deviceId),
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: Value<DateTime>(
              DateTime.parse(change.updatedAt).toUtc(),
            ),
          ),
        );
      }
    });

    return List<String>.unmodifiable(acknowledgedRows.map((row) => row.id));
  }

  Future<List<String>> _acknowledgeFoodEntryPushResponse(
    List<ActivityLogRow> pendingRows,
    SyncPushResponse response,
  ) async {
    final acceptedEntityIds = response.accepted.toSet();
    final appliedById = <String, SyncAppliedChange>{
      for (final change in response.applied) change.id: change,
    };
    final acknowledgedRows = pendingRows
        .where((row) => acceptedEntityIds.contains(row.entityId))
        .toList(growable: false);
    final acknowledgedAt = DateTime.now().toUtc();

    await _database.transaction(() async {
      for (final row in acknowledgedRows) {
        final applied = appliedById[row.entityId];
        await (_database.update(_database.activityLog)
              ..where((table) => table.id.equals(row.id)))
            .write(
          ActivityLogCompanion(
            syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
            afterImage: applied == null
                ? const Value.absent()
                : Value<String?>(
                    _imageWithUpdatedAt(row.afterImage, applied.updatedAt),
                  ),
          ),
        );
        await (_database.update(_database.foodEntries)
              ..where((table) => table.id.equals(row.entityId)))
            .write(
          const FoodEntriesCompanion(
            syncPreviouslySynced: Value<bool>(true),
          ),
        );
      }
      for (final change in response.applied) {
        await (_database.update(_database.foodEntries)
              ..where((row) => row.id.equals(change.id)))
            .write(
          FoodEntriesCompanion(
            syncDeviceId: Value<String?>(change.deviceId),
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: Value<DateTime>(
              DateTime.parse(change.updatedAt).toUtc(),
            ),
          ),
        );
      }
    });

    return List<String>.unmodifiable(acknowledgedRows.map((row) => row.id));
  }

  Future<List<String>> _acknowledgeExerciseCategoryPushResponse(
    List<ActivityLogRow> pendingRows,
    SyncPushResponse response,
  ) async {
    final acceptedEntityIds = response.accepted.toSet();
    final appliedById = <String, SyncAppliedChange>{
      for (final change in response.applied) change.id: change,
    };
    final acknowledgedRows = pendingRows
        .where((row) => acceptedEntityIds.contains(row.entityId))
        .toList(growable: false);
    final acknowledgedAt = DateTime.now().toUtc();

    await _database.transaction(() async {
      for (final row in acknowledgedRows) {
        final applied = appliedById[row.entityId];
        await (_database.update(_database.activityLog)
              ..where((table) => table.id.equals(row.id)))
            .write(
          ActivityLogCompanion(
            syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
            afterImage: applied == null
                ? const Value.absent()
                : Value<String?>(
                    _imageWithUpdatedAt(row.afterImage, applied.updatedAt),
                  ),
          ),
        );
        await (_database.update(_database.exerciseCategories)
              ..where((table) => table.id.equals(row.entityId)))
            .write(
          const ExerciseCategoriesCompanion(
            syncPreviouslySynced: Value<bool>(true),
          ),
        );
      }
      for (final change in response.applied) {
        await (_database.update(_database.exerciseCategories)
              ..where((row) => row.id.equals(change.id)))
            .write(
          ExerciseCategoriesCompanion(
            syncDeviceId: Value<String?>(change.deviceId),
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: Value<DateTime>(
              DateTime.parse(change.updatedAt).toUtc(),
            ),
          ),
        );
      }
    });

    return List<String>.unmodifiable(acknowledgedRows.map((row) => row.id));
  }

  Future<List<String>> _acknowledgeExercisePushResponse(
    List<ActivityLogRow> pendingRows,
    SyncPushResponse response,
  ) async {
    final acceptedEntityIds = response.accepted.toSet();
    final appliedById = <String, SyncAppliedChange>{
      for (final change in response.applied) change.id: change,
    };
    final acknowledgedRows = pendingRows
        .where((row) => acceptedEntityIds.contains(row.entityId))
        .toList(growable: false);
    final acknowledgedAt = DateTime.now().toUtc();

    await _database.transaction(() async {
      for (final row in acknowledgedRows) {
        final applied = appliedById[row.entityId];
        await (_database.update(_database.activityLog)
              ..where((table) => table.id.equals(row.id)))
            .write(
          ActivityLogCompanion(
            syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
            afterImage: applied == null
                ? const Value.absent()
                : Value<String?>(
                    _imageWithUpdatedAt(row.afterImage, applied.updatedAt),
                  ),
          ),
        );
        await (_database.update(_database.exercises)
              ..where((table) => table.id.equals(row.entityId)))
            .write(
          const ExercisesCompanion(
            syncPreviouslySynced: Value<bool>(true),
          ),
        );
      }
      for (final change in response.applied) {
        await (_database.update(_database.exercises)
              ..where((row) => row.id.equals(change.id)))
            .write(
          ExercisesCompanion(
            syncDeviceId: Value<String?>(change.deviceId),
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: Value<DateTime>(
              DateTime.parse(change.updatedAt).toUtc(),
            ),
          ),
        );
      }
    });

    return List<String>.unmodifiable(acknowledgedRows.map((row) => row.id));
  }

  Future<List<String>> _acknowledgeCompoundPushResponse(
    List<ActivityLogRow> pendingRows,
    SyncPushResponse response,
  ) async {
    final acceptedEntityIds = response.accepted.toSet();
    final appliedById = <String, SyncAppliedChange>{
      for (final change in response.applied) change.id: change,
    };
    final acknowledgedRows = pendingRows
        .where((row) => acceptedEntityIds.contains(row.entityId))
        .toList(growable: false);
    final acknowledgedAt = DateTime.now().toUtc();

    await _database.transaction(() async {
      for (final row in acknowledgedRows) {
        final applied = appliedById[row.entityId];
        await (_database.update(_database.activityLog)
              ..where((table) => table.id.equals(row.id)))
            .write(
          ActivityLogCompanion(
            syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
            afterImage: applied == null
                ? const Value.absent()
                : Value<String?>(
                    _imageWithUpdatedAt(row.afterImage, applied.updatedAt),
                  ),
          ),
        );
        await (_database.update(_database.compounds)
              ..where((table) => table.id.equals(row.entityId)))
            .write(
          const CompoundsCompanion(
            syncPreviouslySynced: Value<bool>(true),
          ),
        );
      }
      for (final change in response.applied) {
        await (_database.update(_database.compounds)
              ..where((row) => row.id.equals(change.id)))
            .write(
          CompoundsCompanion(
            syncDeviceId: Value<String?>(change.deviceId),
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: Value<DateTime>(
              DateTime.parse(change.updatedAt).toUtc(),
            ),
          ),
        );
      }
    });

    return List<String>.unmodifiable(acknowledgedRows.map((row) => row.id));
  }

  Future<List<String>> _acknowledgeDosePushResponse(
    List<ActivityLogRow> pendingRows,
    SyncPushResponse response,
  ) async {
    final acceptedEntityIds = response.accepted.toSet();
    final appliedById = <String, SyncAppliedChange>{
      for (final change in response.applied) change.id: change,
    };
    final acknowledgedRows = pendingRows
        .where((row) => acceptedEntityIds.contains(row.entityId))
        .toList(growable: false);
    final acknowledgedAt = DateTime.now().toUtc();

    await _database.transaction(() async {
      for (final row in acknowledgedRows) {
        final applied = appliedById[row.entityId];
        await (_database.update(_database.activityLog)
              ..where((table) => table.id.equals(row.id)))
            .write(
          ActivityLogCompanion(
            syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
            afterImage: applied == null
                ? const Value.absent()
                : Value<String?>(
                    _imageWithUpdatedAt(row.afterImage, applied.updatedAt),
                  ),
          ),
        );
        await (_database.update(_database.doses)
              ..where((table) => table.id.equals(row.entityId)))
            .write(
          const DosesCompanion(
            syncPreviouslySynced: Value<bool>(true),
          ),
        );
      }
      for (final change in response.applied) {
        await (_database.update(_database.doses)
              ..where((row) => row.id.equals(change.id)))
            .write(
          DosesCompanion(
            syncDeviceId: Value<String?>(change.deviceId),
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: Value<DateTime>(
              DateTime.parse(change.updatedAt).toUtc(),
            ),
          ),
        );
      }
    });

    return List<String>.unmodifiable(acknowledgedRows.map((row) => row.id));
  }

  Future<List<String>> _acknowledgeProtocolPushResponse(
    List<ActivityLogRow> pendingRows,
    SyncPushResponse response,
  ) async {
    final acceptedEntityIds = response.accepted.toSet();
    final appliedById = <String, SyncAppliedChange>{
      for (final change in response.applied) change.id: change,
    };
    final acknowledgedRows = pendingRows
        .where((row) => acceptedEntityIds.contains(row.entityId))
        .toList(growable: false);
    final acknowledgedAt = DateTime.now().toUtc();

    await _database.transaction(() async {
      for (final row in acknowledgedRows) {
        final applied = appliedById[row.entityId];
        await (_database.update(_database.activityLog)
              ..where((table) => table.id.equals(row.id)))
            .write(
          ActivityLogCompanion(
            syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
            afterImage: applied == null
                ? const Value.absent()
                : Value<String?>(
                    _imageWithUpdatedAt(row.afterImage, applied.updatedAt),
                  ),
          ),
        );
        await (_database.update(_database.protocols)
              ..where((table) => table.id.equals(row.entityId)))
            .write(
          const ProtocolsCompanion(
            syncPreviouslySynced: Value<bool>(true),
          ),
        );
      }
      for (final change in response.applied) {
        await (_database.update(_database.protocols)
              ..where((row) => row.id.equals(change.id)))
            .write(
          ProtocolsCompanion(
            syncDeviceId: Value<String?>(change.deviceId),
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: Value<DateTime>(
              DateTime.parse(change.updatedAt).toUtc(),
            ),
          ),
        );
      }
    });

    return List<String>.unmodifiable(acknowledgedRows.map((row) => row.id));
  }

  Future<List<String>> _acknowledgeProtocolCompoundPushResponse(
    List<ActivityLogRow> pendingRows,
    SyncPushResponse response,
  ) async {
    final acceptedEntityIds = response.accepted.toSet();
    final appliedById = <String, SyncAppliedChange>{
      for (final change in response.applied) change.id: change,
    };
    final acknowledgedRows = pendingRows
        .where((row) => acceptedEntityIds.contains(row.entityId))
        .toList(growable: false);
    final acknowledgedAt = DateTime.now().toUtc();

    await _database.transaction(() async {
      for (final row in acknowledgedRows) {
        final applied = appliedById[row.entityId];
        await (_database.update(_database.activityLog)
              ..where((table) => table.id.equals(row.id)))
            .write(
          ActivityLogCompanion(
            syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
            afterImage: applied == null
                ? const Value.absent()
                : Value<String?>(
                    _imageWithUpdatedAt(row.afterImage, applied.updatedAt),
                  ),
          ),
        );
        await (_database.update(_database.protocolCompounds)
              ..where((table) => table.id.equals(row.entityId)))
            .write(
          const ProtocolCompoundsCompanion(
            syncPreviouslySynced: Value<bool>(true),
          ),
        );
      }
      for (final change in response.applied) {
        await (_database.update(_database.protocolCompounds)
              ..where((row) => row.id.equals(change.id)))
            .write(
          ProtocolCompoundsCompanion(
            syncDeviceId: Value<String?>(change.deviceId),
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: Value<DateTime>(
              DateTime.parse(change.updatedAt).toUtc(),
            ),
          ),
        );
      }
    });

    return List<String>.unmodifiable(acknowledgedRows.map((row) => row.id));
  }

  Future<List<String>> _acknowledgeProtocolTargetOutcomePushResponse(
    List<ActivityLogRow> pendingRows,
    SyncPushResponse response,
  ) async {
    final acceptedEntityIds = response.accepted.toSet();
    final appliedById = <String, SyncAppliedChange>{
      for (final change in response.applied) change.id: change,
    };
    final acknowledgedRows = pendingRows
        .where((row) => acceptedEntityIds.contains(row.entityId))
        .toList(growable: false);
    final acknowledgedAt = DateTime.now().toUtc();

    await _database.transaction(() async {
      for (final row in acknowledgedRows) {
        final applied = appliedById[row.entityId];
        await (_database.update(_database.activityLog)
              ..where((table) => table.id.equals(row.id)))
            .write(
          ActivityLogCompanion(
            syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
            afterImage: applied == null
                ? const Value.absent()
                : Value<String?>(
                    _imageWithUpdatedAt(row.afterImage, applied.updatedAt),
                  ),
          ),
        );
        await (_database.update(_database.protocolTargetOutcomes)
              ..where((table) => table.id.equals(row.entityId)))
            .write(
          const ProtocolTargetOutcomesCompanion(
            syncPreviouslySynced: Value<bool>(true),
          ),
        );
      }
      for (final change in response.applied) {
        await (_database.update(_database.protocolTargetOutcomes)
              ..where((row) => row.id.equals(change.id)))
            .write(
          ProtocolTargetOutcomesCompanion(
            syncDeviceId: Value<String?>(change.deviceId),
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: Value<DateTime>(
              DateTime.parse(change.updatedAt).toUtc(),
            ),
          ),
        );
      }
    });

    return List<String>.unmodifiable(acknowledgedRows.map((row) => row.id));
  }

  Future<List<String>> _acknowledgeSchedulePushResponse(
    List<ActivityLogRow> pendingRows,
    SyncPushResponse response,
  ) async {
    final acceptedEntityIds = response.accepted.toSet();
    final appliedById = <String, SyncAppliedChange>{
      for (final change in response.applied) change.id: change,
    };
    final acknowledgedRows = pendingRows
        .where((row) => acceptedEntityIds.contains(row.entityId))
        .toList(growable: false);
    final acknowledgedAt = DateTime.now().toUtc();

    await _database.transaction(() async {
      for (final row in acknowledgedRows) {
        final applied = appliedById[row.entityId];
        await (_database.update(_database.activityLog)
              ..where((table) => table.id.equals(row.id)))
            .write(
          ActivityLogCompanion(
            syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
            afterImage: applied == null
                ? const Value.absent()
                : Value<String?>(
                    _imageWithUpdatedAt(row.afterImage, applied.updatedAt),
                  ),
          ),
        );
        await (_database.update(_database.schedules)
              ..where((table) => table.id.equals(row.entityId)))
            .write(
          const SchedulesCompanion(
            syncPreviouslySynced: Value<bool>(true),
          ),
        );
      }
      for (final change in response.applied) {
        await (_database.update(_database.schedules)
              ..where((row) => row.id.equals(change.id)))
            .write(
          SchedulesCompanion(
            syncDeviceId: Value<String?>(change.deviceId),
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: Value<DateTime>(
              DateTime.parse(change.updatedAt).toUtc(),
            ),
          ),
        );
      }
    });

    return List<String>.unmodifiable(acknowledgedRows.map((row) => row.id));
  }

  Future<List<String>> _acknowledgeNutritionGoalPushResponse(
    List<ActivityLogRow> pendingRows,
    SyncPushResponse response,
  ) async {
    final acceptedEntityIds = response.accepted.toSet();
    final appliedById = <String, SyncAppliedChange>{
      for (final change in response.applied) change.id: change,
    };
    final acknowledgedRows = pendingRows
        .where((row) => acceptedEntityIds.contains(row.entityId))
        .toList(growable: false);
    final acknowledgedAt = DateTime.now().toUtc();

    await _database.transaction(() async {
      for (final row in acknowledgedRows) {
        final applied = appliedById[row.entityId];
        await (_database.update(_database.activityLog)
              ..where((table) => table.id.equals(row.id)))
            .write(
          ActivityLogCompanion(
            syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
            afterImage: applied == null
                ? const Value.absent()
                : Value<String?>(
                    _imageWithUpdatedAt(row.afterImage, applied.updatedAt),
                  ),
          ),
        );
        await (_database.update(_database.nutritionGoals)
              ..where((table) => table.id.equals(row.entityId)))
            .write(
          const NutritionGoalsCompanion(
            syncPreviouslySynced: Value<bool>(true),
          ),
        );
      }
      for (final change in response.applied) {
        await (_database.update(_database.nutritionGoals)
              ..where((row) => row.id.equals(change.id)))
            .write(
          NutritionGoalsCompanion(
            syncDeviceId: Value<String?>(change.deviceId),
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: Value<DateTime>(
              DateTime.parse(change.updatedAt).toUtc(),
            ),
          ),
        );
      }
    });

    return List<String>.unmodifiable(acknowledgedRows.map((row) => row.id));
  }

  Future<List<String>> _acknowledgeUserSettingsPushResponse(
    List<ActivityLogRow> pendingRows,
    SyncPushResponse response,
  ) async {
    final acceptedEntityIds = response.accepted.toSet();
    final appliedById = <String, SyncAppliedChange>{
      for (final change in response.applied) change.id: change,
    };
    final acknowledgedRows = pendingRows
        .where((row) => acceptedEntityIds.contains(row.entityId))
        .toList(growable: false);
    final acknowledgedAt = DateTime.now().toUtc();

    await _database.transaction(() async {
      for (final row in acknowledgedRows) {
        final applied = appliedById[row.entityId];
        await (_database.update(_database.activityLog)
              ..where((table) => table.id.equals(row.id)))
            .write(
          ActivityLogCompanion(
            syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
            afterImage: applied == null
                ? const Value.absent()
                : Value<String?>(
                    _imageWithUpdatedAt(row.afterImage, applied.updatedAt),
                  ),
          ),
        );
        await (_database.update(_database.userSettings)
              ..where((table) => table.id.equals(row.entityId)))
            .write(
          const UserSettingsCompanion(
            syncPreviouslySynced: Value<bool>(true),
          ),
        );
      }
      for (final change in response.applied) {
        await (_database.update(_database.userSettings)
              ..where((row) => row.id.equals(change.id)))
            .write(
          UserSettingsCompanion(
            syncDeviceId: Value<String?>(change.deviceId),
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: Value<DateTime>(
              DateTime.parse(change.updatedAt).toUtc(),
            ),
          ),
        );
      }
    });

    return List<String>.unmodifiable(acknowledgedRows.map((row) => row.id));
  }

  Future<List<String>> _acknowledgeIntegrationConsentPushResponse(
    List<ActivityLogRow> pendingRows,
    SyncPushResponse response,
  ) async {
    final acceptedEntityIds = response.accepted.toSet();
    final appliedById = <String, SyncAppliedChange>{
      for (final change in response.applied) change.id: change,
    };
    final acknowledgedRows = pendingRows
        .where((row) => acceptedEntityIds.contains(row.entityId))
        .toList(growable: false);
    final acknowledgedAt = DateTime.now().toUtc();

    await _database.transaction(() async {
      for (final row in acknowledgedRows) {
        final applied = appliedById[row.entityId];
        await (_database.update(_database.activityLog)
              ..where((table) => table.id.equals(row.id)))
            .write(
          ActivityLogCompanion(
            syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
            afterImage: applied == null
                ? const Value.absent()
                : Value<String?>(
                    _imageWithUpdatedAt(row.afterImage, applied.updatedAt),
                  ),
          ),
        );
        await (_database.update(_database.integrationDataClassConsents)
              ..where((table) => table.id.equals(row.entityId)))
            .write(
          const IntegrationDataClassConsentsCompanion(
            syncPreviouslySynced: Value<bool>(true),
          ),
        );
      }
      for (final change in response.applied) {
        await (_database.update(_database.integrationDataClassConsents)
              ..where((row) => row.id.equals(change.id)))
            .write(
          IntegrationDataClassConsentsCompanion(
            syncDeviceId: Value<String?>(change.deviceId),
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: Value<DateTime>(
              DateTime.parse(change.updatedAt).toUtc(),
            ),
          ),
        );
      }
    });

    return List<String>.unmodifiable(acknowledgedRows.map((row) => row.id));
  }

  Future<void> _appendSyncActivityLog({
    required String entityTable,
    required String entityId,
    required Map<String, Object?>? beforeImage,
    required Map<String, Object?>? afterImage,
    required String actor,
    required String batchId,
    required String? activityLogId,
    required DateTime occurredAt,
    required DateTime syncAcknowledgedAt,
  }) {
    return _database.into(_database.activityLog).insert(
          ActivityLogCompanion.insert(
            id: activityLogId ?? _repositories.createId(syncAcknowledgedAt),
            actor: actor,
            batchId: batchId,
            entityTable: entityTable,
            entityId: entityId,
            beforeImage: Value<String?>(
              beforeImage == null ? null : jsonEncode(beforeImage),
            ),
            afterImage: Value<String?>(
              afterImage == null ? null : jsonEncode(afterImage),
            ),
            occurredAt: occurredAt,
            syncAcknowledgedAt: Value<DateTime?>(syncAcknowledgedAt),
            updatedAt: syncAcknowledgedAt,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<_GuardedPendingRows> _guardAgainstStaleLiveResurrection(
    List<ActivityLogRow> pendingRows,
  ) async {
    final guardedActivityLogIds = <String>[];
    final pushableRows = <ActivityLogRow>[];

    for (final row in pendingRows) {
      final image = _decodeImage(row.afterImage);
      if (image == null || image['deleted_at'] != null) {
        pushableRows.add(row);
        continue;
      }

      final current = await (_database.select(_database.loggedSets)
            ..where((table) => table.id.equals(row.entityId)))
          .getSingleOrNull();
      if (current != null &&
          current.syncPreviouslySynced &&
          current.deletedAt != null) {
        guardedActivityLogIds.add(row.id);
        continue;
      }

      pushableRows.add(row);
    }

    if (guardedActivityLogIds.isNotEmpty) {
      final acknowledgedAt = DateTime.now().toUtc();
      await (_database.update(_database.activityLog)
            ..where((row) => row.id.isIn(guardedActivityLogIds)))
          .write(
        ActivityLogCompanion(
          syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
        ),
      );
    }

    return _GuardedPendingRows(
      rows: List<ActivityLogRow>.unmodifiable(pushableRows),
      acknowledgedActivityLogIds:
          List<String>.unmodifiable(guardedActivityLogIds),
    );
  }

  ///the Platform Library is a deterministic bundled seed
  // that never crosses the server — only User Library exercises (and user
  // customizations of a Platform exercise, i.e. a shadowing copy per
  //) sync. `ensurePlatformLibrarySeeded` appends Activity Log rows
  // for the seeded Platform rows too, so this guard keeps them off the wire
  // by checking the CURRENT row's `libraryOrigin` (not the stale image, since
  // shadowing/promotion can change origin after the write that queued this
  // entry) and acknowledging them so they are never retried.
  Future<_GuardedPendingRows> _guardAgainstPlatformExerciseRows(
    List<ActivityLogRow> pendingRows,
  ) async {
    final guardedActivityLogIds = <String>[];
    final pushableRows = <ActivityLogRow>[];

    for (final row in pendingRows) {
      final current = await (_database.select(_database.exercises)
            ..where((table) => table.id.equals(row.entityId)))
          .getSingleOrNull();
      if (current != null &&
          current.libraryOrigin == ExerciseLibraryOrigin.platform.name) {
        guardedActivityLogIds.add(row.id);
        continue;
      }

      pushableRows.add(row);
    }

    if (guardedActivityLogIds.isNotEmpty) {
      final acknowledgedAt = DateTime.now().toUtc();
      await (_database.update(_database.activityLog)
            ..where((row) => row.id.isIn(guardedActivityLogIds)))
          .write(
        ActivityLogCompanion(
          syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
        ),
      );
    }

    return _GuardedPendingRows(
      rows: List<ActivityLogRow>.unmodifiable(pushableRows),
      acknowledgedActivityLogIds:
          List<String>.unmodifiable(guardedActivityLogIds),
    );
  }

  Future<_GuardedPendingRows> _guardAgainstStaleFoodEntryResurrection(
    List<ActivityLogRow> pendingRows,
  ) async {
    final guardedActivityLogIds = <String>[];
    final pushableRows = <ActivityLogRow>[];

    for (final row in pendingRows) {
      final image = _decodeImage(row.afterImage);
      if (image == null || image['deleted_at'] != null) {
        pushableRows.add(row);
        continue;
      }

      final current = await (_database.select(_database.foodEntries)
            ..where((table) => table.id.equals(row.entityId)))
          .getSingleOrNull();
      if (current != null &&
          current.syncPreviouslySynced &&
          current.deletedAt != null) {
        guardedActivityLogIds.add(row.id);
        continue;
      }

      pushableRows.add(row);
    }

    if (guardedActivityLogIds.isNotEmpty) {
      final acknowledgedAt = DateTime.now().toUtc();
      await (_database.update(_database.activityLog)
            ..where((row) => row.id.isIn(guardedActivityLogIds)))
          .write(
        ActivityLogCompanion(
          syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
        ),
      );
    }

    return _GuardedPendingRows(
      rows: List<ActivityLogRow>.unmodifiable(pushableRows),
      acknowledgedActivityLogIds:
          List<String>.unmodifiable(guardedActivityLogIds),
    );
  }

  Future<_GuardedPendingRows> _guardAgainstStaleDoseResurrection(
    List<ActivityLogRow> pendingRows,
  ) async {
    final guardedActivityLogIds = <String>[];
    final pushableRows = <ActivityLogRow>[];

    for (final row in pendingRows) {
      final image = _decodeImage(row.afterImage);
      if (image == null || image['deleted_at'] != null) {
        pushableRows.add(row);
        continue;
      }

      final current = await (_database.select(_database.doses)
            ..where((table) => table.id.equals(row.entityId)))
          .getSingleOrNull();
      if (current != null &&
          current.syncPreviouslySynced &&
          current.deletedAt != null) {
        guardedActivityLogIds.add(row.id);
        continue;
      }

      pushableRows.add(row);
    }

    if (guardedActivityLogIds.isNotEmpty) {
      final acknowledgedAt = DateTime.now().toUtc();
      await (_database.update(_database.activityLog)
            ..where((row) => row.id.isIn(guardedActivityLogIds)))
          .write(
        ActivityLogCompanion(
          syncAcknowledgedAt: Value<DateTime?>(acknowledgedAt),
        ),
      );
    }

    return _GuardedPendingRows(
      rows: List<ActivityLogRow>.unmodifiable(pushableRows),
      acknowledgedActivityLogIds:
          List<String>.unmodifiable(guardedActivityLogIds),
    );
  }
}

final class _PlanSyncEntity {
  const _PlanSyncEntity({
    required this.localEntityTable,
    required this.remoteEntity,
  });

  final String localEntityTable;
  final String remoteEntity;
}

_PlanSyncEntity? _planSyncEntityForRemote(String remoteEntity) {
  if (remoteEntity == _templateLinksSyncEntity.remoteEntity) {
    return _templateLinksSyncEntity;
  }
  for (final entity in <_PlanSyncEntity>[
    ..._workoutStructureSyncEntities,
    ..._planTreeSyncEntities,
  ]) {
    if (entity.remoteEntity == remoteEntity) {
      return entity;
    }
  }
  return null;
}

class _GuardedPendingRows {
  const _GuardedPendingRows({
    required this.rows,
    required this.acknowledgedActivityLogIds,
  });

  final List<ActivityLogRow> rows;
  final List<String> acknowledgedActivityLogIds;
}

class _FullResyncSnapshotResult {
  const _FullResyncSnapshotResult({
    required this.appliedCount,
    required this.nextCursor,
    required this.serverClock,
  });

  final int appliedCount;
  final String? nextCursor;
  final String serverClock;
}

class SyncPushResult {
  const SyncPushResult({
    required this.pushedCount,
    required this.acknowledgedActivityLogIds,
    required this.acceptedEntityIds,
    required this.serverClock,
  });

  final int pushedCount;
  final List<String> acknowledgedActivityLogIds;
  final List<String> acceptedEntityIds;
  final String? serverClock;
}

class DevicePushTokenRegistrationResult {
  const DevicePushTokenRegistrationResult({
    required this.registered,
  });

  final bool registered;
}

class SyncPullResult {
  const SyncPullResult({
    required this.appliedCount,
    required this.nextCursor,
    required this.serverClock,
    required this.fullResyncRequired,
    required this.hasMore,
    this.userSettingsApplied = false,
  });

  final int appliedCount;
  final String? nextCursor;
  final String serverClock;
  final bool fullResyncRequired;

  /// True when the remote pull window was full and another request is needed
  /// to prove the replica is caught up. This is deliberately independent of
  /// [appliedCount]: LWW losers and already-current rows still consume space
  /// in the server page.
  final bool hasMore;

  /// True when this pull applied at least one account-level Settings
  /// (`user_settings`) change — a sync pull, agent write, or another device.
  /// Riverpod callers use this to invalidate
  /// `settingsControllerProvider` so the merged `AppSettings` the UI reads
  /// reflects the pulled account row without an explicit reload. A full resync
  /// re-pulls every entity, so it is treated as having touched settings.
  final bool userSettingsApplied;
}

SyncPushResult _mergePushResults(List<SyncPushResult> results) {
  var pushedCount = 0;
  final acknowledgedActivityLogIds = <String>[];
  final acceptedEntityIds = <String>[];
  String? serverClock;

  for (final result in results) {
    pushedCount += result.pushedCount;
    acknowledgedActivityLogIds.addAll(result.acknowledgedActivityLogIds);
    acceptedEntityIds.addAll(result.acceptedEntityIds);
    serverClock = result.serverClock ?? serverClock;
  }

  return SyncPushResult(
    pushedCount: pushedCount,
    acknowledgedActivityLogIds: List<String>.unmodifiable(
      acknowledgedActivityLogIds,
    ),
    acceptedEntityIds: List<String>.unmodifiable(acceptedEntityIds),
    serverClock: serverClock,
  );
}

SyncPushChange _changeFromActivityLogRow(ActivityLogRow row) {
  final image = _decodeImage(row.afterImage);
  if (image == null) {
    throw StateError('Activity entry has no after image: ${row.id}.');
  }
  final beforeImage = _decodeImage(row.beforeImage);
  final id = _requiredString(image, 'id');
  final updatedAt = _requiredString(image, 'updated_at');
  final deletedAt = image['deleted_at'];
  if (deletedAt != null && deletedAt is! String) {
    throw const FormatException(
      'deleted_at must be null or an ISO-8601 string.',
    );
  }

  return SyncPushChange(
    id: id,
    payload: image,
    updatedAt: updatedAt,
    activityLogId: row.id,
    actor: row.actor,
    batchId: row.batchId,
    beforeImage: beforeImage,
    afterImage: image,
    occurredAt: row.occurredAt.toUtc().toIso8601String(),
    deletedAt: deletedAt as String?,
  );
}

Map<String, Object?> _syncImageFromPull(SyncPulledChange change) {
  return <String, Object?>{
    ...change.payload,
    'id': change.id,
    'updated_at': change.updatedAt,
    'deleted_at': change.deletedAt,
  };
}

Map<String, Object?> _metricReadingImageFromPull(SyncPulledChange change) {
  return _normalizedMetricReadingActivityImage(_syncImageFromPull(change))!;
}

Map<String, Object?>? _normalizedMetricReadingActivityImage(
  Map<String, Object?>? image,
) {
  if (image == null) {
    return null;
  }
  final valueJson = image['value_json'];
  return <String, Object?>{
    ...image,
    if (valueJson is! String) 'value_json': jsonEncode(valueJson),
  };
}

Map<String, Object?> _loggedSetImageFromPull(SyncPulledChange change) {
  return <String, Object?>{
    ...change.payload,
    'updated_at': change.updatedAt,
    'deleted_at': change.deletedAt,
  };
}

Map<String, Object?> _integrationConsentImageFromPull(
  SyncPulledChange change,
) {
  return <String, Object?>{
    ...change.payload,
    'id': change.id,
    'updated_at': change.updatedAt,
    'deleted_at': change.deletedAt,
  };
}

String _actorForPulledChange(SyncPulledChange change) {
  if (change.actor == 'agent' && change.deviceId.startsWith('agent:')) {
    return change.deviceId;
  }
  return change.actor ?? 'sync';
}

int _comparePulledChangesForApply(
  SyncPulledChange left,
  SyncPulledChange right,
) {
  return _syncApplyOrder(left.entity).compareTo(_syncApplyOrder(right.entity));
}

int _syncApplyOrder(String entity) {
  return switch (entity) {
    // An ExerciseCategory before its Exercises (a Drift FK, `categoryId`,
    //).
    AppDatabase.exerciseCategoriesTable => 0,
    AppDatabase.exercisesTable => 1,
    AppDatabase.workoutSessionsTable => 2,
    AppDatabase.workoutExercisesTable => 3,
    AppDatabase.exerciseGroupsTable => 4,
    AppDatabase.exerciseGroupMembersTable => 5,
    // A Food before its Food Entries — a Food Entry's `foodId` is a soft
    // reference (never a Drift FK), so this is cosmetic ordering only.
    // A Meal Type before its Meals for the same reason.
    AppDatabase.foodsTable => 6,
    AppDatabase.mealTypesTable => 7,
    AppDatabase.mealsTable => 8,
    AppDatabase.foodEntriesTable => 9,
    AppDatabase.metricsTable => 10,
    AppDatabase.metricReadingsTable => 11,
    // A Compound before its Doses for tidy ordering — though a Dose is
    // self-contained and never depends on its Compound row.
    AppDatabase.compoundsTable => 12,
    AppDatabase.dosesTable => 13,
    // A Protocol before its ProtocolCompound members before its Schedules
    // (a Drift FK chain) — ProtocolTargetOutcomes only need the
    // Protocol itself.
    AppDatabase.protocolsTable => 14,
    AppDatabase.protocolCompoundsTable => 15,
    AppDatabase.protocolTargetOutcomesTable => 16,
    AppDatabase.schedulesTable => 17,
    AppDatabase.nutritionGoalsTable => 18,
    AppDatabase.workoutTemplatesTable => 19,
    AppDatabase.templateExercisesTable => 20,
    AppDatabase.prescriptionsTable => 21,
    AppDatabase.templateGroupsTable => 22,
    AppDatabase.templateGroupMembersTable => 23,
    _routinesSyncEntity => 24,
    AppDatabase.routineEntriesTable => 25,
    AppDatabase.loggedSetsTable => 26,
    AppDatabase.templateLinksTable => 27,
    _ => 28,
  };
}

bool _lwwWins(
  DateTime incomingUpdatedAt,
  String incomingDeviceId,
  DateTime existingUpdatedAt,
  String existingDeviceId,
) {
  return syncLwwWins(
    incomingUpdatedAt,
    incomingDeviceId,
    existingUpdatedAt,
    existingDeviceId,
  );
}

String? _imageWithUpdatedAt(String? encoded, String updatedAt) {
  final image = _decodeImage(encoded);
  if (image == null) {
    return null;
  }
  return jsonEncode(<String, Object?>{
    ...image,
    'updated_at': updatedAt,
  });
}

Map<String, Object?>? _decodeImage(String? encoded) {
  if (encoded == null) {
    return null;
  }

  final decoded = jsonDecode(encoded);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Activity image must be a JSON object.');
  }
  return decoded;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('$key must be a non-empty string.');
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('$key must be a boolean.');
}

String _requiredImportDataClass(Map<String, Object?> json) {
  final value = _requiredString(json, 'data_class');
  if (importDataClassFromName(value) == null) {
    throw FormatException('Unsupported integration data class: $value.');
  }
  return value;
}

PerenniaApiClient _defaultApiClient(Uri baseUrl) {
  return PerenniaApiClient(baseUrl: baseUrl);
}

SyncStatusKind _syncStatusKind(String rawValue) {
  for (final kind in SyncStatusKind.values) {
    if (kind.name == rawValue) {
      return kind;
    }
  }
  return SyncStatusKind.idle;
}

bool _isAuthExpired(Object error) {
  return error is ApiException && error.statusCode == 401;
}

String _failureMessage(Object error, SyncStatusKind kind) {
  if (kind == SyncStatusKind.authExpired) {
    return _syncUnauthorizedMessage(error) ??
        'Session expired or account removed. '
            'You are now in Local-only Mode; local data remains on this device.';
  }
  if (error is ApiException) {
    return 'Sync failed with HTTP ${error.statusCode}.';
  }
  if (kDebugMode) {
    return 'Sync failed: $error';
  }
  return 'Sync failed. Local changes are saved on this device.';
}

String? _syncUnauthorizedMessage(Object error) {
  if (error is! ApiException) {
    return null;
  }

  try {
    final decoded = jsonDecode(error.body);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    if (decoded['code'] != 'sync_unauthorized') {
      return null;
    }

    final message = decoded['message'];
    if (message is String && message.isNotEmpty) {
      return message;
    }
  } on FormatException {
    return null;
  }

  return null;
}

DateTime? _parseServerClock(String? serverClock) {
  if (serverClock == null || serverClock.isEmpty) {
    return null;
  }
  return DateTime.parse(serverClock).toUtc();
}
