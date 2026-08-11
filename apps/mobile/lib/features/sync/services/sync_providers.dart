import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/repositories/auth_repository.dart';
import '../../settings/repositories/settings_repository.dart';
import '../repositories/sync_device_id_repository.dart';
import '../repositories/sync_repository.dart';
import 'sync_coordinator.dart';
import 'sync_cycle_runner.dart';

final syncCycleRunnerProvider = Provider<RepositorySyncCycleRunner>((ref) {
  final repository = ref.watch(syncRepositoryProvider);
  return RepositorySyncCycleRunner(
    repository: repository,
    statusRepository: repository.statusRepository,
    onUserSettingsApplied: () => ref.invalidate(settingsControllerProvider),
  );
});

final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final repository = ref.watch(syncRepositoryProvider);
  final runner = ref.watch(syncCycleRunnerProvider);
  final coordinator = SyncCoordinator(
    loadSession: () async => ref.read(authControllerProvider).value?.session,
    loadDeviceId: () => ref.read(syncDeviceIdProvider.future),
    runCycle: runner.run,
    recordCredentialFailure: repository.statusRepository.recordFailure,
  );

  StreamSubscription<int>? pendingSubscription;
  Timer? pendingRetryTimer;
  String? configuredIdentity;

  void subscribeToPendingChanges() {
    pendingRetryTimer?.cancel();
    pendingRetryTimer = null;
    pendingSubscription = repository.watchPendingChangeCount().listen(
      (pendingCount) {
        if (pendingCount > 0) {
          coordinator.requestSync(SyncTrigger.localWrite);
        }
      },
      onError: (Object _, StackTrace __) {
        final subscription = pendingSubscription;
        pendingSubscription = null;
        if (subscription != null) {
          unawaited(subscription.cancel());
        }
        pendingRetryTimer = Timer(
          const Duration(seconds: 5),
          subscribeToPendingChanges,
        );
      },
    );
  }

  void configureSignedInTriggers(AuthSession? session) {
    final identity = session == null
        ? null
        : '${session.userId}\n${session.serverUrl}\n${session.token}';
    if (identity == configuredIdentity) {
      return;
    }
    configuredIdentity = identity;
    pendingRetryTimer?.cancel();
    pendingRetryTimer = null;
    final subscription = pendingSubscription;
    pendingSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }

    if (session == null) {
      coordinator.stopPeriodic();
      return;
    }

    coordinator.startPeriodic();
    subscribeToPendingChanges();
  }

  configureSignedInTriggers(
    ref.read(authControllerProvider).value?.session,
  );
  ref.listen<AsyncValue<AuthState>>(authControllerProvider, (previous, next) {
    final previousSession = previous?.value?.session;
    final nextSession = next.value?.session;
    configureSignedInTriggers(nextSession);
    if (nextSession != null &&
        (previousSession?.token != nextSession.token ||
            previousSession?.serverUrl != nextSession.serverUrl)) {
      coordinator.requestSync(SyncTrigger.authChanged);
    }
  });
  ref.onDispose(() {
    coordinator.dispose();
    pendingRetryTimer?.cancel();
    final subscription = pendingSubscription;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  });
  return coordinator;
});
