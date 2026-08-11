import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/features/settings/services/auto_backup_service.dart';

void main() {
  group('auto-backup service', () {
    late AppDatabase database;
    late TrainingRepositories repositories;
    late InMemorySettingsRepository settingsRepository;
    late _MemoryAutoBackupFolderAccess folderAccess;
    late _MemoryAutoBackupScheduler scheduler;
    var now = DateTime.utc(2026, 6, 22, 8);

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
      settingsRepository = InMemorySettingsRepository(
        AppSettings.defaults.copyWith(
          autoBackupEnabled: true,
          autoBackupFolderUri: 'folder://backups',
          autoBackupFolderLabel: 'Backups',
        ),
      );
      folderAccess = _MemoryAutoBackupFolderAccess(clock: () => now);
      scheduler = _MemoryAutoBackupScheduler();
    });

    tearDown(() async {
      await database.close();
    });

    AutoBackupService service() {
      return AutoBackupService(
        settingsRepository: settingsRepository,
        repositories: repositories,
        folderAccess: folderAccess,
        scheduler: scheduler,
        clock: () => now,
      );
    }

    test('scheduled run writes a portable archive to the chosen folder',
        () async {
      final result = await service().runScheduledBackup();
      final stored = folderAccess.file(result.fileName!);
      final manifest = await repositories.portableArchives
          .inspectPortableArchive(stored.bytes, passphrase: null);
      final savedSettings = await settingsRepository.load();

      expect(result.status, AutoBackupStatus.succeeded);
      expect(result.mode, AutoBackupRunMode.localOnly);
      expect(result.fileName,
          'open-workout-logger-auto-backup-20260622T080000Z.zip');
      expect(manifest.appVersion, PortableArchiveRepository.appVersion);
      expect(savedSettings.autoBackupLastStatus, AutoBackupStatus.succeeded);
      expect(savedSettings.autoBackupLastSuccessfulRunAt, now);
    });

    test('scheduled run honors the configured encryption passphrase', () async {
      settingsRepository = InMemorySettingsRepository(
        AppSettings.defaults.copyWith(
          autoBackupEnabled: true,
          autoBackupFolderUri: 'folder://backups',
          autoBackupEncryptionPassphrase: 'correct horse',
        ),
      );

      final result = await service().runScheduledBackup();
      final stored = folderAccess.file(result.fileName!);
      final manifest = await repositories.portableArchives
          .inspectPortableArchive(stored.bytes, passphrase: 'correct horse');

      expect(result.status, AutoBackupStatus.succeeded);
      expect(manifest.appVersion, PortableArchiveRepository.appVersion);
      expect(
        repositories.portableArchives.inspectPortableArchive(
          stored.bytes,
          passphrase: null,
        ),
        throwsA(isA<PortableArchiveException>()),
      );
    });

    test('retention keeps exactly the last five auto-backup files', () async {
      for (var index = 1; index <= 6; index += 1) {
        final modifiedAt = DateTime.utc(2026, 6, index);
        folderAccess.putFile(
          'open-workout-logger-auto-backup-2026060${index}T080000Z.zip',
          modifiedAt: modifiedAt,
        );
      }
      folderAccess.putFile(
        'notes.txt',
        modifiedAt: DateTime.utc(2026, 6, 1),
      );
      now = DateTime.utc(2026, 6, 7, 8);

      final result = await service().runScheduledBackup();
      final fileNames = folderAccess.fileNames;

      expect(result.status, AutoBackupStatus.succeeded);
      expect(
        result.prunedFileNames,
        <String>[
          'open-workout-logger-auto-backup-20260602T080000Z.zip',
          'open-workout-logger-auto-backup-20260601T080000Z.zip',
        ],
      );
      expect(
        fileNames
            .where(
                (fileName) => fileName.startsWith(AutoBackupService.filePrefix))
            .toList(),
        <String>[
          'open-workout-logger-auto-backup-20260603T080000Z.zip',
          'open-workout-logger-auto-backup-20260604T080000Z.zip',
          'open-workout-logger-auto-backup-20260605T080000Z.zip',
          'open-workout-logger-auto-backup-20260606T080000Z.zip',
          'open-workout-logger-auto-backup-20260607T080000Z.zip',
        ],
      );
      expect(fileNames, contains('notes.txt'));
    });

    test('run result snapshots pruned file names', () {
      final prunedFileNames = <String>['old-backup.zip'];
      final result = AutoBackupRunResult(
        status: AutoBackupStatus.succeeded,
        mode: AutoBackupRunMode.localOnly,
        runAt: now,
        prunedFileNames: prunedFileNames,
      );

      prunedFileNames.add('new-backup.zip');

      expect(result.prunedFileNames, <String>['old-backup.zip']);
      expect(
        () => result.prunedFileNames.add('mutated.zip'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('missing or revoked folder grant skips without throwing', () async {
      folderAccess.canWriteGrant = false;

      final result = await service().runScheduledBackup();
      final savedSettings = await settingsRepository.load();

      expect(result.status, AutoBackupStatus.skippedMissingFolderGrant);
      expect(folderAccess.fileNames, isEmpty);
      expect(
        savedSettings.autoBackupLastStatus,
        AutoBackupStatus.skippedMissingFolderGrant,
      );
      expect(savedSettings.autoBackupNeedsFolderGrant, isTrue);
    });

    test('same runner succeeds in local-only and synced modes', () async {
      final localOnly = await service().runScheduledBackup(
        mode: AutoBackupRunMode.localOnly,
      );
      now = DateTime.utc(2026, 6, 22, 9);
      final synced = await service().runScheduledBackup(
        mode: AutoBackupRunMode.synced,
      );

      expect(localOnly.status, AutoBackupStatus.succeeded);
      expect(synced.status, AutoBackupStatus.succeeded);
      expect(localOnly.mode, AutoBackupRunMode.localOnly);
      expect(synced.mode, AutoBackupRunMode.synced);
      expect(folderAccess.fileNames, hasLength(2));
    });

    test('enabled settings schedule a daily native backup request', () async {
      final status =
          await service().applySchedule(await settingsRepository.load());

      expect(status, AutoBackupScheduleStatus.scheduled);
      expect(scheduler.scheduled.single.toPlatformMap(), <String, Object?>{
        'folderUri': 'folder://backups',
        'intervalMinutes': 1440,
        'keepFileCount': 5,
      });
    });
  });
}

class _MemoryAutoBackupFolderAccess implements AutoBackupFolderAccess {
  _MemoryAutoBackupFolderAccess({required DateTime Function() clock})
      : _clock = clock;

  final DateTime Function() _clock;
  final _files = <String, _StoredBackupFile>{};
  bool canWriteGrant = true;

  List<String> get fileNames => _files.keys.toList(growable: false)..sort();

  _StoredBackupFile file(String fileName) => _files[fileName]!;

  void putFile(
    String fileName, {
    required DateTime modifiedAt,
    List<int> bytes = const <int>[],
  }) {
    _files[fileName] = _StoredBackupFile(bytes: bytes, modifiedAt: modifiedAt);
  }

  @override
  Future<bool> canWrite(String folderUri) async => canWriteGrant;

  @override
  Future<AutoBackupFolderGrant?> chooseFolder() async {
    return const AutoBackupFolderGrant(
      uri: 'folder://backups',
      label: 'Backups',
    );
  }

  @override
  Future<void> deleteFile({
    required String folderUri,
    required String fileName,
  }) async {
    _files.remove(fileName);
  }

  @override
  Future<List<AutoBackupFolderFile>> listFiles(String folderUri) async {
    return [
      for (final entry in _files.entries)
        AutoBackupFolderFile(
          fileName: entry.key,
          modifiedAt: entry.value.modifiedAt,
        ),
    ];
  }

  @override
  Future<void> writeFile({
    required String folderUri,
    required String fileName,
    required List<int> bytes,
  }) async {
    _files[fileName] = _StoredBackupFile(
      bytes: List<int>.unmodifiable(bytes),
      modifiedAt: _clock(),
    );
  }
}

class _MemoryAutoBackupScheduler implements AutoBackupScheduler {
  final scheduled = <AutoBackupSchedule>[];
  var cancelCount = 0;

  @override
  Future<void> cancel() async {
    cancelCount += 1;
  }

  @override
  Future<AutoBackupScheduleStatus> schedule(AutoBackupSchedule schedule) async {
    scheduled.add(schedule);
    return AutoBackupScheduleStatus.scheduled;
  }
}

class _StoredBackupFile {
  const _StoredBackupFile({
    required this.bytes,
    required this.modifiedAt,
  });

  final List<int> bytes;
  final DateTime modifiedAt;
}
