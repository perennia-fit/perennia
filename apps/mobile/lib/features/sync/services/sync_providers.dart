import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
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
    ensureLibrarySeeded: () => ref
        .read(trainingRepositoriesProvider)
        .catalog
        .ensurePlatformLibrarySeeded(),
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
    clearReplacedSessionVerdict: repository.statusRepository.clearAuthExpired,
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
    final sessionChanged = previousSession?.token != nextSession?.token ||
        previousSession?.serverUrl != nextSession?.serverUrl;
    if (!sessionChanged) {
      return;
    }
    // An authExpired verdict belongs to the session it rejected. Once that
    // session is replaced (Sign in again, another account) or gone (sign
    // out), it must not make the new state look expired. The first load of
    // the stored session is not a change: the verdict about it still holds.
    if (previous?.hasValue ?? false) {
      // A failed clear is left for the new session's Sync Run to settle: its
      // success records over the verdict and a rejection is a fresh one.
      unawaited(
        repository.statusRepository
            .clearAuthExpired()
            .catchError((Object _) {}),
      );
    }
    if (nextSession != null) {
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
