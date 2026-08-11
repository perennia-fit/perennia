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

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not met.');
}
