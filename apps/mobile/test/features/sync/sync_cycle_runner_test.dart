import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';
import 'package:perennia/features/sync/repositories/sync_repository.dart';
import 'package:perennia/features/sync/services/sync_cycle_runner.dart';

void main() {
  test('fails a Sync Run that cannot make progress on a pending row', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = _NoProgressSyncRepository();
    final runner = RepositorySyncCycleRunner(
      repository: repository,
      statusRepository: SyncStatusRepository(database),
    );

    await expectLater(
      runner.run(session: _session, deviceId: 'mobile:pixel-8'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('no progress'),
        ),
      ),
    );

    expect(repository.authoredPushCalls, 2);
    expect(repository.pullCalls, 2);
  });

  test('invalidates Settings after a Sync Run applies user settings', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    var settingsInvalidations = 0;
    final runner = RepositorySyncCycleRunner(
      repository: _OneCycleSyncRepository(
        pullResult: const SyncPullResult(
          appliedCount: 1,
          nextCursor: null,
          serverClock: '2026-07-29T00:00:00.000Z',
          fullResyncRequired: false,
          hasMore: false,
          userSettingsApplied: true,
        ),
      ),
      statusRepository: SyncStatusRepository(database),
      onUserSettingsApplied: () => settingsInvalidations += 1,
    );

    await runner.run(session: _session, deviceId: 'mobile:pixel-8');

    expect(settingsInvalidations, 1);
  });

  test('does not invalidate Settings when no user settings were applied',
      () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    var settingsInvalidations = 0;
    final runner = RepositorySyncCycleRunner(
      repository: _OneCycleSyncRepository(
        pullResult: const SyncPullResult(
          appliedCount: 1,
          nextCursor: null,
          serverClock: '2026-07-29T00:00:00.000Z',
          fullResyncRequired: false,
          hasMore: false,
        ),
      ),
      statusRepository: SyncStatusRepository(database),
      onUserSettingsApplied: () => settingsInvalidations += 1,
    );

    await runner.run(session: _session, deviceId: 'mobile:pixel-8');

    expect(settingsInvalidations, 0);
  });
}

final class _NoProgressSyncRepository implements SyncCycleRepository {
  var authoredPushCalls = 0;
  var pullCalls = 0;

  @override
  Future<bool> hasPendingChanges() async => true;

  @override
  Future<SyncPullResult> pullLoggedSetChanges({
    required AuthSession session,
    required String deviceId,
    int limit = 100,
    bool manageStatus = true,
  }) async {
    pullCalls += 1;
    return const SyncPullResult(
      appliedCount: 0,
      nextCursor: null,
      serverClock: '2026-07-29T00:00:00.000Z',
      fullResyncRequired: false,
      hasMore: false,
    );
  }

  @override
  Future<SyncPushResult> pushPendingIntegrationDataClassConsents({
    required AuthSession session,
    required String deviceId,
    bool manageStatus = true,
  }) async =>
      _emptyPush;

  @override
  Future<SyncPushResult> pushPendingLoggedSets({
    required AuthSession session,
    required String deviceId,
    bool manageStatus = true,
  }) async {
    authoredPushCalls += 1;
    return _emptyPush;
  }
}

final class _OneCycleSyncRepository implements SyncCycleRepository {
  _OneCycleSyncRepository({required this.pullResult});

  final SyncPullResult pullResult;

  @override
  Future<bool> hasPendingChanges() async => false;

  @override
  Future<SyncPullResult> pullLoggedSetChanges({
    required AuthSession session,
    required String deviceId,
    int limit = 100,
    bool manageStatus = true,
  }) async =>
      pullResult;

  @override
  Future<SyncPushResult> pushPendingIntegrationDataClassConsents({
    required AuthSession session,
    required String deviceId,
    bool manageStatus = true,
  }) async =>
      _emptyPush;

  @override
  Future<SyncPushResult> pushPendingLoggedSets({
    required AuthSession session,
    required String deviceId,
    bool manageStatus = true,
  }) async =>
      _emptyPush;
}

const _emptyPush = SyncPushResult(
  pushedCount: 0,
  acknowledgedActivityLogIds: <String>[],
  acceptedEntityIds: <String>[],
  serverClock: null,
);

final _session = AuthSession(
  provider: AuthSessionProvider.email,
  serverUrl: Uri.parse('https://sync.example/'),
  token: 'session-token',
  userEmail: 'sync@example.com',
  userId: 'user-1',
  userName: 'Sync User',
);
