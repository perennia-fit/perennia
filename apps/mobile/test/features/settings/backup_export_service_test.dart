import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/features/settings/services/auto_backup_service.dart';
import 'package:perennia/features/settings/services/backup_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  group('back up now', () {
    late AppDatabase database;
    late TrainingRepositories repositories;
    late _MemoryBackupFileSaver saver;
    final now = DateTime.utc(2026, 10, 24, 8, 15, 30);

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
      saver = _MemoryBackupFileSaver();
    });

    tearDown(() async {
      await database.close();
    });

    BackupExportService service({String? passphrase}) {
      return BackupExportService(
        settingsRepository: InMemorySettingsRepository(
          AppSettings.defaults.copyWith(
            autoBackupEncryptionPassphrase: passphrase,
          ),
        ),
        repositories: repositories,
        saver: saver,
        clock: () => now,
      );
    }

    test('hands a named backup to the save dialog', () async {
      final result = await service().backUpNow();

      expect(result.outcome, BackupSaveOutcome.saved);
      expect(result.fileName, 'perennia-backup-20261024T081530Z.zip');
      expect(saver.savedFileNames, [result.fileName]);
      final manifest = await repositories.portableArchives
          .inspectPortableArchive(saver.savedBytes.single);
      expect(manifest.createdAt, now);
      expect(manifest.appVersion, PortableArchiveRepository.appVersion);
    });

    test('the saved file restores on another device', () async {
      await _logBodyWeight(repositories, const ['81.2', '80.9']);

      await service().backUpNow();

      final otherDatabase = AppDatabase.inMemory();
      addTearDown(otherDatabase.close);
      final other = TrainingRepositories(otherDatabase);
      final result = await other.portableArchives
          .importPortableArchive(saver.savedBytes.single);

      expect(result.changedRowsByTable[AppDatabase.metricReadingsTable], 2);
    });

    test('encrypts with the backup passphrase when one is set', () async {
      await service(passphrase: '  correct horse  ').backUpNow();
      final bytes = saver.savedBytes.single;

      expect(
        repositories.portableArchives.isEncryptedPortableArchive(bytes),
        isTrue,
      );
      final manifest = await repositories.portableArchives
          .inspectPortableArchive(bytes, passphrase: 'correct horse');
      expect(manifest.createdAt, now);
      await expectLater(
        repositories.portableArchives.inspectPortableArchive(bytes),
        throwsA(isA<PortableArchiveException>()),
      );
    });

    test('a blank passphrase leaves the backup unencrypted', () async {
      await service(passphrase: '   ').backUpNow();

      expect(
        repositories.portableArchives
            .isEncryptedPortableArchive(saver.savedBytes.single),
        isFalse,
      );
    });

    test('passes the save dialog outcome through', () async {
      for (final outcome in [
        BackupSaveOutcome.cancelled,
        BackupSaveOutcome.unsupported,
      ]) {
        saver.outcome = outcome;
        final result = await service().backUpNow();
        expect(result.outcome, outcome);
        expect(result.error, isNull);
      }
    });

    test('a failed write reports failed with the error', () async {
      final error = PlatformException(code: 'write_failed');
      saver.error = error;

      final result = await service().backUpNow();

      expect(result.outcome, BackupSaveOutcome.failed);
      expect(result.error, same(error));
    });
  });

  test('backup file names sort in time order and use UTC', () {
    expect(
      backupFileName(
        prefix: 'perennia-backup-',
        createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      ),
      'perennia-backup-20260102T030405Z.zip',
    );
    expect(
      backupFileName(
        prefix: AutoBackupService.filePrefix,
        createdAt: DateTime.parse('2026-06-22T10:00:00+02:00'),
      ),
      'perennia-auto-backup-20260622T080000Z.zip',
    );
  });

  group('backup export channel', () {
    const channel = MethodChannel('perennia/backup_export');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('sends the file name, MIME type and bytes', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return 'saved';
      });

      final outcome = await const MethodChannelBackupFileSaver().save(
        fileName: 'perennia-backup-20261024T081530Z.zip',
        bytes: const [80, 75, 3, 4],
      );

      expect(outcome, BackupSaveOutcome.saved);
      expect(calls.single.method, 'saveFile');
      final arguments = calls.single.arguments as Map<Object?, Object?>;
      expect(arguments['fileName'], 'perennia-backup-20261024T081530Z.zip');
      expect(arguments['mimeType'], 'application/zip');
      expect(arguments['bytes'], Uint8List.fromList(const [80, 75, 3, 4]));
    });

    test('maps the platform answers', () async {
      for (final (answer, outcome) in [
        ('saved', BackupSaveOutcome.saved),
        ('cancelled', BackupSaveOutcome.cancelled),
        ('unsupported', BackupSaveOutcome.unsupported),
        (null, BackupSaveOutcome.failed),
      ]) {
        messenger.setMockMethodCallHandler(channel, (call) async => answer);
        expect(
          await const MethodChannelBackupFileSaver()
              .save(fileName: 'a.zip', bytes: const []),
          outcome,
        );
      }
    });

    test('a platform without the handler is unsupported', () async {
      expect(
        await const MethodChannelBackupFileSaver()
            .save(fileName: 'a.zip', bytes: const []),
        BackupSaveOutcome.unsupported,
      );
    });

    test('a write error reaches the caller', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'write_failed');
      });

      await expectLater(
        const MethodChannelBackupFileSaver()
            .save(fileName: 'a.zip', bytes: const []),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('auto-backup folder availability', () {
    const channel = MethodChannel('perennia/auto_backup_folder');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('is unavailable when no platform handler answers', () async {
      expect(
        await const MethodChannelAutoBackupFolderAccess().isAvailable(),
        isFalse,
      );
    });

    test('is available when the platform handler answers true', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        return call.method == 'isAvailable';
      });

      expect(
        await const MethodChannelAutoBackupFolderAccess().isAvailable(),
        isTrue,
      );
    });
  });
}

Future<void> _logBodyWeight(
  TrainingRepositories repositories,
  List<String> values,
) async {
  await repositories.measurements.ensureDefaultMeasurements(
    bodyWeightUnit: MeasurementUnit.kilogram,
  );
  final bodyWeight = (await repositories.measurements.listActive())
      .singleWhere((measurement) => measurement.name == 'Body Weight');
  for (final (index, value) in values.indexed) {
    await repositories.measurements.createEntry(
      MeasurementEntryDraft(
        measurementId: bodyWeight.id,
        valueEntered: value,
        measuredAt: DateTime.utc(2026, 10, 1 + index, 7),
      ),
    );
  }
}

class _MemoryBackupFileSaver implements BackupFileSaver {
  final savedFileNames = <String>[];
  final savedBytes = <List<int>>[];
  BackupSaveOutcome outcome = BackupSaveOutcome.saved;
  Object? error;

  @override
  Future<BackupSaveOutcome> save({
    required String fileName,
    required List<int> bytes,
  }) async {
    final error = this.error;
    if (error != null) {
      throw error;
    }
    if (outcome == BackupSaveOutcome.saved) {
      savedFileNames.add(fileName);
      savedBytes.add(List<int>.unmodifiable(bytes));
    }
    return outcome;
  }
}
