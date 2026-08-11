import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/repositories/auth_repository.dart';
import '../../sync/services/sync_coordinator.dart';
import '../../sync/services/sync_providers.dart';

typedef GarminFitFilePicker = Future<List<XFile>> Function();
typedef SettingsSyncNow = Future<SyncCycleResult> Function({
  required AuthSession session,
  required String deviceId,
});

final garminFitFilePickerProvider = Provider<GarminFitFilePicker>((ref) {
  return () {
    return openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'FIT',
          extensions: ['fit'],
        ),
      ],
    );
  };
});

final settingsSyncNowProvider = Provider<SettingsSyncNow>((ref) {
  final coordinator = ref.watch(syncCoordinatorProvider);
  return ({
    required AuthSession session,
    required String deviceId,
  }) {
    return coordinator.synchronizeNowWith(
      trigger: SyncTrigger.manual,
      session: session,
      deviceId: deviceId,
    );
  };
});
