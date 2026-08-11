import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/repositories/auth_repository.dart';
import '../repositories/sync_repository.dart';
import 'sync_coordinator.dart';
import 'sync_providers.dart';

const syncNudgeMessageType = 'sync_nudge';

typedef SynchronizeAfterNudge = Future<SyncCycleResult> Function({
  required AuthSession session,
  required String deviceId,
});

final syncNudgeHandlerProvider = Provider<SyncNudgeHandler>((ref) {
  final coordinator = ref.watch(syncCoordinatorProvider);
  return SyncNudgeHandler(
    synchronize: ({
      required session,
      required deviceId,
    }) =>
        coordinator.synchronizeNowWith(
      trigger: SyncTrigger.serverNudge,
      session: session,
      deviceId: deviceId,
    ),
  );
});

class SyncNudgeHandler {
  const SyncNudgeHandler({
    required SynchronizeAfterNudge synchronize,
  }) : _synchronize = synchronize;

  final SynchronizeAfterNudge _synchronize;

  Future<SyncCycleResult?> handleSilentPush({
    required Map<String, Object?> data,
    required AuthSession? session,
    required String deviceId,
  }) async {
    final signedInSession = session;
    if (!_isSyncNudge(data) || signedInSession == null) {
      return null;
    }

    return _synchronize(
      session: signedInSession,
      deviceId: deviceId,
    );
  }
}

bool _isSyncNudge(Map<String, Object?> data) {
  final type = data['type'];
  final protocolVersion = data['protocolVersion'];

  return type == syncNudgeMessageType &&
      _readProtocolVersion(protocolVersion) == syncProtocolVersion;
}

int? _readProtocolVersion(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
