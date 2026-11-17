import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/repositories/auth_repository.dart';
import '../models/sync_status.dart';
import '../repositories/sync_repository.dart';

export '../models/sync_status.dart';

final syncNowProvider = Provider<DateTime Function()>((ref) {
  return () => DateTime.now().toUtc();
});

final syncStatusControllerProvider =
    StreamNotifierProvider<SyncStatusController, SyncStatusState>(
  SyncStatusController.new,
);

class SyncStatusController extends StreamNotifier<SyncStatusState> {
  @override
  Stream<SyncStatusState> build() {
    final repository = ref.watch(syncStatusRepositoryProvider);
    final now = ref.watch(syncNowProvider);
    return repository.watchStatus(now: now);
  }
}

/// True when this device holds a session the server last rejected as
/// unauthorized: it looks signed in, but nothing syncs until the user signs in
/// again.
///
/// The one place the screens read this from, so the Home dot, the Account &
/// app sheet, the Account screen and the Sync screen cannot disagree. The
/// verdict is held across retries with the same session and dropped when the
/// session is replaced or signed out (see [SyncStatusRepository.recordSyncing]
/// and [SyncStatusRepository.clearAuthExpired]).
final sessionExpiredProvider = Provider<bool>((ref) {
  final hasSession = ref.watch(
    authControllerProvider.select((auth) => auth.value?.session != null),
  );
  if (!hasSession) {
    return false;
  }
  return ref.watch(
    syncStatusControllerProvider.select(
      (status) => status.value?.kind == SyncStatusKind.authExpired,
    ),
  );
});
