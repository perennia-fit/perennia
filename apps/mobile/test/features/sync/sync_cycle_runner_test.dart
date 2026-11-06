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

  // docs/designs/compound-purposes.md, D3: "When it runs".
  group('backfillSeedPurposes', () {
    RepositorySyncCycleRunner runnerFor(
      AppDatabase database,
      SyncCycleRepository repository,
    ) {
      return RepositorySyncCycleRunner(
        repository: repository,
        statusRepository: SyncStatusRepository(database),
      );
    }

    test('runs after the pull has drained, before the pending check', () async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repository = _ScriptedSyncRepository(pullPagesPerPass: 3);

      await runnerFor(database, repository)
          .run(session: _session, deviceId: 'mobile:pixel-8');

      expect(repository.events, <String>[
        'push',
        'pull',
        'pull',
        'pull',
        'backfill',
        'pending',
      ]);
    });

    test('runs after a full resync ends the pull', () async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repository = _ScriptedSyncRepository(fullResync: true);

      await runnerFor(database, repository)
          .run(session: _session, deviceId: 'mobile:pixel-8');

      expect(
          repository.events, <String>['push', 'pull', 'backfill', 'pending']);
    });

    test('does not run when a push fails', () async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repository = _ScriptedSyncRepository(pushFailure: StateError('x'));

      await expectLater(
        runnerFor(database, repository)
            .run(session: _session, deviceId: 'mobile:pixel-8'),
        throwsStateError,
      );

      expect(repository.events, isNot(contains('backfill')));
    });

    test('does not run when a pull fails', () async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repository = _ScriptedSyncRepository(pullFailure: StateError('x'));

      await expectLater(
        runnerFor(database, repository)
            .run(session: _session, deviceId: 'mobile:pixel-8'),
        throwsStateError,
      );

      expect(repository.events, isNot(contains('backfill')));
    });

    test('a failed backfill fails the Sync Run', () async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repository =
          _ScriptedSyncRepository(backfillFailure: StateError('x'));

      await expectLater(
        runnerFor(database, repository)
            .run(session: _session, deviceId: 'mobile:pixel-8'),
        throwsStateError,
      );
    });

    test(
        'pushes what it wrote in the same Sync Run, even after a pass with '
        'no progress', () async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repository = _ScriptedSyncRepository(backfillWritesRows: 6);

      final result = await runnerFor(database, repository)
          .run(session: _session, deviceId: 'mobile:pixel-8');

      expect(result.pushedCount, 6);
      expect(repository.events, <String>[
        'push',
        'pull',
        'backfill',
        'pending',
        'push',
        'pull',
        'backfill',
        'pending',
      ]);
    });
  });
}

final class _NoProgressSyncRepository implements SyncCycleRepository {
  var authoredPushCalls = 0;
  var pullCalls = 0;

  @override
  Future<void> backfillSeedPurposes() async {}

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
  Future<void> backfillSeedPurposes() async {}

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

/// Records the order of a Sync Run's calls. [backfillWritesRows] rows become
/// pending when the backfill first runs, and the next push clears them.
final class _ScriptedSyncRepository implements SyncCycleRepository {
  _ScriptedSyncRepository({
    this.pullPagesPerPass = 1,
    this.fullResync = false,
    this.pushFailure,
    this.pullFailure,
    this.backfillFailure,
    this.backfillWritesRows = 0,
  });

  final int pullPagesPerPass;
  final bool fullResync;
  final Object? pushFailure;
  final Object? pullFailure;
  final Object? backfillFailure;
  int backfillWritesRows;

  final events = <String>[];
  var _pending = 0;
  var _pagesLeft = 0;

  @override
  Future<void> backfillSeedPurposes() async {
    events.add('backfill');
    final failure = backfillFailure;
    if (failure != null) {
      throw failure;
    }
    _pending += backfillWritesRows;
    backfillWritesRows = 0;
  }

  @override
  Future<bool> hasPendingChanges() async {
    events.add('pending');
    return _pending > 0;
  }

  @override
  Future<SyncPullResult> pullLoggedSetChanges({
    required AuthSession session,
    required String deviceId,
    int limit = 100,
    bool manageStatus = true,
  }) async {
    events.add('pull');
    final failure = pullFailure;
    if (failure != null) {
      throw failure;
    }
    if (_pagesLeft == 0) {
      _pagesLeft = pullPagesPerPass;
    }
    _pagesLeft -= 1;
    return SyncPullResult(
      appliedCount: 0,
      nextCursor: 'cursor-${events.length}',
      serverClock: '2026-07-29T00:00:00.000Z',
      fullResyncRequired: fullResync,
      hasMore: _pagesLeft > 0,
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
    events.add('push');
    final failure = pushFailure;
    if (failure != null) {
      throw failure;
    }
    final pushed = _pending;
    _pending = 0;
    return SyncPushResult(
      pushedCount: pushed,
      acknowledgedActivityLogIds: const <String>[],
      acceptedEntityIds: const <String>[],
      serverClock: null,
    );
  }
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
