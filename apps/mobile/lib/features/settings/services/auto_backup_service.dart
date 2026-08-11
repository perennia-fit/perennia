import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import '../../../data/repositories/training_repositories.dart';
import '../repositories/settings_repository.dart';

final autoBackupFolderAccessProvider = Provider<AutoBackupFolderAccess>(
  (ref) => const MethodChannelAutoBackupFolderAccess(),
);

final autoBackupSchedulerProvider = Provider<AutoBackupScheduler>(
  (ref) => const MethodChannelAutoBackupScheduler(),
);

final autoBackupServiceProvider = Provider<AutoBackupService>((ref) {
  return AutoBackupService(
    settingsRepository: ref.watch(settingsRepositoryProvider),
    repositories: ref.watch(trainingRepositoriesProvider),
    folderAccess: ref.watch(autoBackupFolderAccessProvider),
    scheduler: ref.watch(autoBackupSchedulerProvider),
  );
});

abstract interface class AutoBackupFolderAccess {
  Future<AutoBackupFolderGrant?> chooseFolder();

  Future<bool> canWrite(String folderUri);

  Future<void> writeFile({
    required String folderUri,
    required String fileName,
    required List<int> bytes,
  });

  Future<List<AutoBackupFolderFile>> listFiles(String folderUri);

  Future<void> deleteFile({
    required String folderUri,
    required String fileName,
  });
}

abstract interface class AutoBackupScheduler {
  Future<AutoBackupScheduleStatus> schedule(AutoBackupSchedule schedule);

  Future<void> cancel();
}

class AutoBackupService {
  AutoBackupService({
    required SettingsRepository settingsRepository,
    required TrainingRepositories repositories,
    required AutoBackupFolderAccess folderAccess,
    required AutoBackupScheduler scheduler,
    DateTime Function()? clock,
  })  : _settingsRepository = settingsRepository,
        _repositories = repositories,
        _folderAccess = folderAccess,
        _scheduler = scheduler,
        _clock = clock ?? (() => DateTime.now().toUtc());

  static const keepFileCount = 5;
  static const filePrefix = 'open-workout-logger-auto-backup-';
  static const fileExtension = '.zip';

  final SettingsRepository _settingsRepository;
  final TrainingRepositories _repositories;
  final AutoBackupFolderAccess _folderAccess;
  final AutoBackupScheduler _scheduler;
  final DateTime Function() _clock;

  Future<AutoBackupScheduleStatus> applySchedule(AppSettings settings) {
    if (!settings.autoBackupEnabled || settings.autoBackupFolderUri == null) {
      return _scheduler.cancel().then(
            (_) => AutoBackupScheduleStatus.cancelled,
          );
    }
    return _scheduler.schedule(
      AutoBackupSchedule(
        folderUri: settings.autoBackupFolderUri!,
        keepFileCount: keepFileCount,
      ),
    );
  }

  Future<AutoBackupRunResult> runScheduledBackup({
    AutoBackupRunMode mode = AutoBackupRunMode.localOnly,
  }) async {
    final settings = await _settingsRepository.load();
    if (!settings.autoBackupEnabled || settings.autoBackupFolderUri == null) {
      return _recordSkippedMissingGrant(settings, mode: mode);
    }

    final folderUri = settings.autoBackupFolderUri!;
    if (!await _folderAccess.canWrite(folderUri)) {
      return _recordSkippedMissingGrant(settings, mode: mode);
    }

    final runAt = _clock().toUtc();
    try {
      final encryptionPassphrase =
          settings.autoBackupEncryptionPassphrase?.trim();
      final bytes = await _repositories.portableArchives.exportPortableArchive(
        createdAt: runAt,
        encryption: encryptionPassphrase == null || encryptionPassphrase.isEmpty
            ? null
            : PortableArchiveEncryptionOptions(
                passphrase: encryptionPassphrase,
              ),
      );
      final fileName = _fileNameFor(runAt);
      await _folderAccess.writeFile(
        folderUri: folderUri,
        fileName: fileName,
        bytes: bytes,
      );
      final prunedFileNames = await _pruneOldBackups(folderUri);
      final nextSettings = settings.copyWith(
        autoBackupLastRunAt: runAt,
        autoBackupLastSuccessfulRunAt: runAt,
        autoBackupLastStatus: AutoBackupStatus.succeeded,
      );
      await _settingsRepository.save(nextSettings);
      return AutoBackupRunResult(
        status: AutoBackupStatus.succeeded,
        mode: mode,
        folderUri: folderUri,
        fileName: fileName,
        prunedFileNames: prunedFileNames,
        runAt: runAt,
      );
    } on MissingPluginException {
      final failedAt = _clock().toUtc();
      await _settingsRepository.save(
        settings.copyWith(
          autoBackupLastRunAt: failedAt,
          autoBackupLastStatus: AutoBackupStatus.unsupported,
        ),
      );
      return AutoBackupRunResult(
        status: AutoBackupStatus.unsupported,
        mode: mode,
        folderUri: folderUri,
        runAt: failedAt,
      );
    } on Object catch (error) {
      final failedAt = _clock().toUtc();
      await _settingsRepository.save(
        settings.copyWith(
          autoBackupLastRunAt: failedAt,
          autoBackupLastStatus: AutoBackupStatus.failed,
        ),
      );
      return AutoBackupRunResult(
        status: AutoBackupStatus.failed,
        mode: mode,
        folderUri: folderUri,
        runAt: failedAt,
        error: error,
      );
    }
  }

  Future<AutoBackupFolderGrant?> chooseFolder() {
    return _folderAccess.chooseFolder();
  }

  Future<List<String>> _pruneOldBackups(String folderUri) async {
    final autoBackupFiles = (await _folderAccess.listFiles(folderUri))
        .where((file) => _isAutoBackupFile(file.fileName))
        .toList(growable: false)
      ..sort((left, right) {
        final modifiedComparison = right.modifiedAt.compareTo(left.modifiedAt);
        if (modifiedComparison != 0) {
          return modifiedComparison;
        }
        return right.fileName.compareTo(left.fileName);
      });

    if (autoBackupFiles.length <= keepFileCount) {
      return const <String>[];
    }

    final pruned = <String>[];
    for (final file in autoBackupFiles.skip(keepFileCount)) {
      await _folderAccess.deleteFile(
        folderUri: folderUri,
        fileName: file.fileName,
      );
      pruned.add(file.fileName);
    }
    return List<String>.unmodifiable(pruned);
  }

  Future<AutoBackupRunResult> _recordSkippedMissingGrant(
    AppSettings settings, {
    required AutoBackupRunMode mode,
  }) async {
    final skippedAt = _clock().toUtc();
    await _settingsRepository.save(
      settings.copyWith(
        autoBackupLastRunAt: skippedAt,
        autoBackupLastStatus: AutoBackupStatus.skippedMissingFolderGrant,
      ),
    );
    return AutoBackupRunResult(
      status: AutoBackupStatus.skippedMissingFolderGrant,
      mode: mode,
      folderUri: settings.autoBackupFolderUri,
      runAt: skippedAt,
    );
  }

  static String _fileNameFor(DateTime runAt) {
    final utc = runAt.toUtc();
    final stamp = [
      utc.year.toString().padLeft(4, '0'),
      utc.month.toString().padLeft(2, '0'),
      utc.day.toString().padLeft(2, '0'),
      'T',
      utc.hour.toString().padLeft(2, '0'),
      utc.minute.toString().padLeft(2, '0'),
      utc.second.toString().padLeft(2, '0'),
      'Z',
    ].join();
    return '$filePrefix$stamp$fileExtension';
  }

  static bool _isAutoBackupFile(String fileName) {
    return fileName.startsWith(filePrefix) && fileName.endsWith(fileExtension);
  }
}

class AutoBackupFolderGrant {
  const AutoBackupFolderGrant({
    required this.uri,
    required this.label,
  });

  final String uri;
  final String label;
}

class AutoBackupFolderFile {
  const AutoBackupFolderFile({
    required this.fileName,
    required this.modifiedAt,
  });

  final String fileName;
  final DateTime modifiedAt;
}

class AutoBackupSchedule {
  const AutoBackupSchedule({
    required this.folderUri,
    required this.keepFileCount,
    this.interval = const Duration(days: 1),
  });

  final String folderUri;
  final int keepFileCount;
  final Duration interval;

  Map<String, Object?> toPlatformMap() {
    return <String, Object?>{
      'folderUri': folderUri,
      'intervalMinutes': interval.inMinutes,
      'keepFileCount': keepFileCount,
    };
  }
}

class AutoBackupRunResult {
  AutoBackupRunResult({
    required this.status,
    required this.mode,
    required this.runAt,
    this.folderUri,
    this.fileName,
    List<String> prunedFileNames = const <String>[],
    this.error,
  }) : prunedFileNames = List<String>.unmodifiable(prunedFileNames);

  final AutoBackupStatus status;
  final AutoBackupRunMode mode;
  final DateTime runAt;
  final String? folderUri;
  final String? fileName;
  final List<String> prunedFileNames;
  final Object? error;
}

enum AutoBackupRunMode {
  localOnly,
  synced,
}

enum AutoBackupScheduleStatus {
  scheduled,
  cancelled,
  unsupported,
}

class MethodChannelAutoBackupFolderAccess implements AutoBackupFolderAccess {
  const MethodChannelAutoBackupFolderAccess({
    MethodChannel channel = _defaultChannel,
  }) : _channel = channel;

  static const _defaultChannel = MethodChannel(
    'open_workout_logger/auto_backup_folder',
  );

  final MethodChannel _channel;

  @override
  Future<AutoBackupFolderGrant?> chooseFolder() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'chooseFolder',
      );
      if (result == null) {
        return null;
      }
      final uri = result['uri'];
      final label = result['label'];
      if (uri is! String || uri.isEmpty) {
        return null;
      }
      return AutoBackupFolderGrant(
        uri: uri,
        label: label is String && label.isNotEmpty ? label : uri,
      );
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> canWrite(String folderUri) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'canWrite',
        <String, Object?>{'folderUri': folderUri},
      );
      return result == true;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> writeFile({
    required String folderUri,
    required String fileName,
    required List<int> bytes,
  }) async {
    await _channel.invokeMethod<void>('writeFile', <String, Object?>{
      'folderUri': folderUri,
      'fileName': fileName,
      'bytes': Uint8List.fromList(bytes),
    });
  }

  @override
  Future<List<AutoBackupFolderFile>> listFiles(String folderUri) async {
    try {
      final result = await _channel.invokeListMethod<Object?>(
        'listFiles',
        <String, Object?>{'folderUri': folderUri},
      );
      return (result ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map((rawFile) {
            final fileName = rawFile['fileName'];
            final modifiedAtMillis = rawFile['modifiedAtMillis'];
            if (fileName is! String || modifiedAtMillis is! int) {
              return null;
            }
            return AutoBackupFolderFile(
              fileName: path.basename(fileName),
              modifiedAt: DateTime.fromMillisecondsSinceEpoch(
                modifiedAtMillis,
                isUtc: true,
              ),
            );
          })
          .whereType<AutoBackupFolderFile>()
          .toList(growable: false);
    } on MissingPluginException {
      return const <AutoBackupFolderFile>[];
    }
  }

  @override
  Future<void> deleteFile({
    required String folderUri,
    required String fileName,
  }) async {
    await _channel.invokeMethod<void>('deleteFile', <String, Object?>{
      'folderUri': folderUri,
      'fileName': fileName,
    });
  }
}

class MethodChannelAutoBackupScheduler implements AutoBackupScheduler {
  const MethodChannelAutoBackupScheduler({
    MethodChannel channel = _defaultChannel,
  }) : _channel = channel;

  static const _defaultChannel = MethodChannel(
    'open_workout_logger/auto_backup_scheduler',
  );

  final MethodChannel _channel;

  @override
  Future<AutoBackupScheduleStatus> schedule(AutoBackupSchedule schedule) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'scheduleAutoBackup',
        schedule.toPlatformMap(),
      );
      return result == 'scheduled'
          ? AutoBackupScheduleStatus.scheduled
          : AutoBackupScheduleStatus.unsupported;
    } on MissingPluginException {
      return AutoBackupScheduleStatus.unsupported;
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancelAutoBackup');
    } on MissingPluginException {
      return;
    }
  }
}
