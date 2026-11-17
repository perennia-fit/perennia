import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';
import 'package:perennia/features/sync/services/sync_coordinator.dart';

void main() {
  test(
    'a trigger arriving during a Sync Run is serialized into one follow-up run',
    () async {
      final firstRun = Completer<SyncCycleResult>();
      final secondRun = Completer<SyncCycleResult>();
      var runCount = 0;
      final coordinator = SyncCoordinator(
        loadSession: () async => _session,
        loadDeviceId: () async => 'mobile:pixel-8',
        runCycle: ({required session, required deviceId}) {
          expect(session, same(_session));
          expect(deviceId, 'mobile:pixel-8');
          runCount += 1;
          return runCount == 1 ? firstRun.future : secondRun.future;
        },
      );
      addTearDown(coordinator.dispose);

      final manualRun = coordinator.synchronizeNow(SyncTrigger.manual);
      await _waitFor(() => runCount == 1);

      coordinator.requestSync(SyncTrigger.serverNudge);
      expect(runCount, 1);

      firstRun.complete(const SyncCycleResult(appliedCount: 2));
      await _waitFor(() => runCount == 2);

      secondRun.complete(const SyncCycleResult(appliedCount: 3));
      final result = await manualRun;

      expect(result.appliedCount, 5);
      expect(runCount, 2);
    },
  );

  test('concurrent manual requests schedule one follow-up Sync Run', () async {
    final firstCycle = Completer<SyncCycleResult>();
    final secondCycle = Completer<SyncCycleResult>();
    var runCount = 0;
    final coordinator = SyncCoordinator(
      loadSession: () async => _session,
      loadDeviceId: () async => 'mobile:pixel-8',
      runCycle: ({required session, required deviceId}) {
        runCount += 1;
        return runCount == 1 ? firstCycle.future : secondCycle.future;
      },
    );
    addTearDown(coordinator.dispose);

    final first = coordinator.synchronizeNow(SyncTrigger.manual);
    final second = coordinator.synchronizeNow(SyncTrigger.manual);
    await _waitFor(() => runCount == 1);

    firstCycle.complete(const SyncCycleResult(appliedCount: 4));
    await _waitFor(() => runCount == 2);
    secondCycle.complete(const SyncCycleResult(appliedCount: 5));

    expect((await first).appliedCount, 9);
    expect((await second).appliedCount, 9);
    expect(runCount, 2);
  });

  test('credential loader failure is recorded for background work', () async {
    final failure = Completer<Object>();
    final coordinator = SyncCoordinator(
      loadSession: () => Future<AuthSession?>.error(
        StateError('credential store unavailable'),
      ),
      loadDeviceId: () async => 'mobile:pixel-8',
      runCycle: ({required session, required deviceId}) async =>
          const SyncCycleResult(appliedCount: 0),
      recordCredentialFailure: (error) async {
        failure.complete(error);
      },
    );
    addTearDown(coordinator.dispose);

    coordinator.requestSync(SyncTrigger.appLaunch);

    expect(
      await failure.future,
      isA<StateError>().having(
        (error) => error.message,
        'message',
        'credential store unavailable',
      ),
    );
  });

  test(
      'a cycle that fails with a session replaced meanwhile drops its verdict '
      'and runs again at once with the new session', () async {
    var current = _session;
    final staleCycle = Completer<SyncCycleResult>();
    final usedTokens = <String>[];
    var verdictsCleared = 0;
    final coordinator = SyncCoordinator(
      loadSession: () async => current,
      loadDeviceId: () async => 'mobile:pixel-8',
      runCycle: ({required session, required deviceId}) {
        usedTokens.add(session.token);
        return session.token == _session.token
            ? staleCycle.future
            : Future<SyncCycleResult>.value(
                const SyncCycleResult(appliedCount: 0, pushedCount: 3),
              );
      },
      clearReplacedSessionVerdict: () async {
        verdictsCleared += 1;
      },
    );
    addTearDown(coordinator.dispose);

    final run = coordinator.synchronizeNow(SyncTrigger.periodic);
    await _waitFor(() => usedTokens.length == 1);

    // Sign in again lands while the old session's request is in flight,
    // then that request is rejected.
    current = _freshSession;
    coordinator.requestSync(SyncTrigger.authChanged);
    staleCycle.completeError(StateError('401 for the old session'));

    final result = await run;
    expect(usedTokens, <String>['session-token', 'fresh-token']);
    expect(result.pushedCount, 3);
    expect(verdictsCleared, 1);
  });

  test(
      'a Sync now or nudge run with fixed credentials that the user replaces '
      'meanwhile recovers with the new session', () async {
    var current = _session;
    final staleCycle = Completer<SyncCycleResult>();
    final usedTokens = <String>[];
    var verdictsCleared = 0;
    final coordinator = SyncCoordinator(
      loadSession: () async => current,
      loadDeviceId: () async => 'mobile:pixel-8',
      runCycle: ({required session, required deviceId}) {
        usedTokens.add(session.token);
        return session.token == _session.token
            ? staleCycle.future
            : Future<SyncCycleResult>.value(
                const SyncCycleResult(appliedCount: 0, pushedCount: 2),
              );
      },
      clearReplacedSessionVerdict: () async {
        verdictsCleared += 1;
      },
    );
    addTearDown(coordinator.dispose);

    final run = coordinator.synchronizeNowWith(
      trigger: SyncTrigger.manual,
      session: _session,
      deviceId: 'mobile:pixel-8',
    );
    await _waitFor(() => usedTokens.length == 1);

    current = _freshSession;
    coordinator.requestSync(SyncTrigger.authChanged);
    staleCycle.completeError(StateError('401 for the old session'));

    final result = await run;
    expect(usedTokens, <String>['session-token', 'fresh-token']);
    expect(result.pushedCount, 2);
    expect(verdictsCleared, 1);
  });

  test(
      'the follow-up to a fixed-credentials run uses the session that '
      'replaced them', () async {
    var current = _session;
    final firstCycle = Completer<SyncCycleResult>();
    final usedTokens = <String>[];
    final coordinator = SyncCoordinator(
      loadSession: () async => current,
      loadDeviceId: () async => 'mobile:pixel-8',
      runCycle: ({required session, required deviceId}) {
        usedTokens.add(session.token);
        return usedTokens.length == 1
            ? firstCycle.future
            : Future<SyncCycleResult>.value(
                const SyncCycleResult(appliedCount: 1),
              );
      },
    );
    addTearDown(coordinator.dispose);

    final run = coordinator.synchronizeNowWith(
      trigger: SyncTrigger.serverNudge,
      session: _session,
      deviceId: 'mobile:pixel-8',
    );
    await _waitFor(() => usedTokens.length == 1);

    current = _freshSession;
    coordinator.requestSync(SyncTrigger.authChanged);
    firstCycle.complete(const SyncCycleResult(appliedCount: 0));

    await run;
    expect(usedTokens, <String>['session-token', 'fresh-token']);
  });

  test('a cycle that fails with the current session still fails', () async {
    var verdictsCleared = 0;
    final coordinator = SyncCoordinator(
      loadSession: () async => _session,
      loadDeviceId: () async => 'mobile:pixel-8',
      runCycle: ({required session, required deviceId}) =>
          Future<SyncCycleResult>.error(StateError('401')),
      clearReplacedSessionVerdict: () async {
        verdictsCleared += 1;
      },
    );
    addTearDown(coordinator.dispose);

    await expectLater(
      coordinator.synchronizeNow(SyncTrigger.manual),
      throwsStateError,
    );
    expect(verdictsCleared, 0);
  });

  test('signed-out triggers do not attempt a Sync Run', () async {
    var runCount = 0;
    final coordinator = SyncCoordinator(
      loadSession: () async => null,
      loadDeviceId: () async => 'mobile:pixel-8',
      runCycle: ({required session, required deviceId}) async {
        runCount += 1;
        return const SyncCycleResult(appliedCount: 1);
      },
    );
    addTearDown(coordinator.dispose);

    final result = await coordinator.synchronizeNow(SyncTrigger.appLaunch);

    expect(result, SyncCycleResult.skipped);
    expect(runCount, 0);
  });
}

final _session = AuthSession(
  provider: AuthSessionProvider.email,
  serverUrl: Uri.parse('https://sync.example/'),
  token: 'session-token',
  userEmail: 'sync@example.com',
  userId: 'user-1',
  userName: 'Sync User',
);

final _freshSession = AuthSession(
  provider: AuthSessionProvider.email,
  serverUrl: Uri.parse('https://sync.example/'),
  token: 'fresh-token',
  userEmail: 'sync@example.com',
  userId: 'user-1',
  userName: 'Sync User',
);

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not met.');
}
