import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../repositories/settings_repository.dart';

final backupFileSaverProvider = Provider<BackupFileSaver>(
  (ref) => const MethodChannelBackupFileSaver(),
);

final backupExportServiceProvider = Provider<BackupExportService>((ref) {
  return BackupExportService(
    settingsRepository: ref.watch(settingsRepositoryProvider),
    repositories: ref.watch(trainingRepositoriesProvider),
    saver: ref.watch(backupFileSaverProvider),
  );
});

/// Names a backup file `<prefix><UTC stamp>.zip`, e.g.
/// `perennia-backup-20261024T081500Z.zip`. The stamp sorts lexically in
/// time order and carries no characters a file system rejects.
String backupFileName({required String prefix, required DateTime createdAt}) {
  final utc = createdAt.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '$prefix${utc.year.toString().padLeft(4, '0')}${two(utc.month)}'
      '${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z'
      '.zip';
}

/// Hands one finished file to the platform's own save dialog, where the user
/// picks where it goes (Downloads, a cloud drive, Files).
abstract interface class BackupFileSaver {
  Future<BackupSaveOutcome> save({
    required String fileName,
    required List<int> bytes,
  });
}

enum BackupSaveOutcome {
  saved,

  /// The user closed the save dialog without choosing a place.
  cancelled,

  /// This platform has no save dialog wired up.
  unsupported,

  /// The archive was built but writing it failed.
  failed,
}

class BackupExportResult {
  const BackupExportResult({
    required this.outcome,
    required this.fileName,
    this.error,
  });

  final BackupSaveOutcome outcome;
  final String fileName;
  final Object? error;
}

/// Settings → Backup & restore → Back up now: exports the portable archive
/// and hands it to the platform save dialog.
///
/// This, not the scheduled folder backup, is how a user gets a backup off a
/// phone. `AutoBackupService` was written against a native folder channel
/// (Android SAF tree grant + WorkManager, iOS security-scoped bookmark) that
/// no platform implements, and finishing it is a much larger job than its
/// method list suggests:
///
/// * A scheduled run happens with the app closed, so the export (Dart, over
///   Drift) needs a headless Flutter engine started from a WorkManager
///   worker, plus a new androidx.work dependency, plus a second SQLite
///   connection that can race the UI's when the app is open.
/// * iOS has no periodic background slot to put it in. BGTaskScheduler runs
///   opportunistically, if at all, so "daily" would be a promise the app
///   cannot keep there.
///
/// A foreground save covers the job that matters before the first release,
/// moving data to a new phone, with platform code that only runs while the
/// user is looking at it: Android's `ACTION_CREATE_DOCUMENT` and iOS's
/// document export picker. Both are system UI, so the backup can land in any
/// place the user's document providers offer, and neither needs a new
/// dependency. The resulting .zip is exactly what Restore reads.
///
/// Backups made here use the same passphrase setting as auto-backup, so a
/// user who sets one gets encrypted files from both paths.
class BackupExportService {
  BackupExportService({
    required SettingsRepository settingsRepository,
    required TrainingRepositories repositories,
    required BackupFileSaver saver,
    DateTime Function()? clock,
  })  : _settingsRepository = settingsRepository,
        _repositories = repositories,
        _saver = saver,
        _clock = clock ?? (() => DateTime.now().toUtc());

  static const filePrefix = 'perennia-backup-';

  final SettingsRepository _settingsRepository;
  final TrainingRepositories _repositories;
  final BackupFileSaver _saver;
  final DateTime Function() _clock;

  Future<BackupExportResult> backUpNow() async {
    final createdAt = _clock().toUtc();
    final fileName = backupFileName(prefix: filePrefix, createdAt: createdAt);
    try {
      final settings = await _settingsRepository.load();
      final passphrase = settings.autoBackupEncryptionPassphrase?.trim();
      final bytes = await _repositories.portableArchives.exportPortableArchive(
        createdAt: createdAt,
        encryption: passphrase == null || passphrase.isEmpty
            ? null
            : PortableArchiveEncryptionOptions(passphrase: passphrase),
      );
      final outcome = await _saver.save(fileName: fileName, bytes: bytes);
      return BackupExportResult(outcome: outcome, fileName: fileName);
    } on Object catch (error) {
      return BackupExportResult(
        outcome: BackupSaveOutcome.failed,
        fileName: fileName,
        error: error,
      );
    }
  }
}

/// Talks to `perennia/backup_export`, handled in `MainActivity.kt` and
/// `AppDelegate.swift`. `saveFile` answers `saved`, `cancelled` or
/// `unsupported` (no save screen on this device), and fails with a
/// [PlatformException] when the chosen place cannot be written.
class MethodChannelBackupFileSaver implements BackupFileSaver {
  const MethodChannelBackupFileSaver({
    MethodChannel channel = _defaultChannel,
  }) : _channel = channel;

  static const _defaultChannel = MethodChannel('perennia/backup_export');

  final MethodChannel _channel;

  @override
  Future<BackupSaveOutcome> save({
    required String fileName,
    required List<int> bytes,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'saveFile',
        <String, Object?>{
          'fileName': fileName,
          'mimeType': 'application/zip',
          'bytes': Uint8List.fromList(bytes),
        },
      );
      return switch (result) {
        'saved' => BackupSaveOutcome.saved,
        'cancelled' => BackupSaveOutcome.cancelled,
        'unsupported' => BackupSaveOutcome.unsupported,
        _ => BackupSaveOutcome.failed,
      };
    } on MissingPluginException {
      return BackupSaveOutcome.unsupported;
    }
  }
}
