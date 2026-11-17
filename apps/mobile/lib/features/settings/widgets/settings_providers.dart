import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/repositories/auth_repository.dart';
import '../../sync/services/sync_coordinator.dart';
import '../../sync/services/sync_providers.dart';

typedef GarminFitFilePicker = Future<List<XFile>> Function();
typedef BackupArchiveFilePicker = Future<XFile?> Function();
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

/// Picks one backup .zip for restore. The type group carries extensions,
/// MIME types and a UTI because each platform filters on a different one
/// (Android: MIME, iOS: UTI). Android document providers do not agree on a
/// zip's MIME type (cloud drives often report `application/octet-stream`),
/// so the filter errs wide; restore itself rejects a file that is not a
/// backup.
final backupArchiveFilePickerProvider = Provider<BackupArchiveFilePicker>((
  ref,
) {
  return () {
    return openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Perennia backup',
          extensions: ['zip'],
          mimeTypes: [
            'application/zip',
            'application/x-zip-compressed',
            'application/octet-stream',
          ],
          uniformTypeIdentifiers: ['public.zip-archive'],
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
