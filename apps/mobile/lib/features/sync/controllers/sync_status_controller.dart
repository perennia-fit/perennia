import 'package:flutter_riverpod/flutter_riverpod.dart';

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
