import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/features/settings/services/backup_export_service.dart';
import 'package:perennia/features/settings/widgets/backup_now_section.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  late AppDatabase database;
  late TrainingRepositories repositories;
  late InMemorySettingsRepository settingsRepository;
  late _RecordingSaver saver;

  setUp(() {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(database);
    settingsRepository = InMemorySettingsRepository();
    saver = _RecordingSaver();
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> pump(WidgetTester tester, {ThemeData? theme}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trainingRepositoriesProvider.overrideWith((ref) => repositories),
          settingsRepositoryProvider.overrideWith((ref) => settingsRepository),
          backupFileSaverProvider.overrideWith((ref) => saver),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(AppDimens.base),
              children: const [BackupNowSection()],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The export runs real sqlite I/O, so let it finish outside the fake
  /// clock before pumping the result onto the screen.
  Future<void> backUpNow(WidgetTester tester) async {
    await tester.tap(find.byKey(BackupNowSection.backUpNowButtonKey));
    await tester.runAsync(() => saver.saved.future);
    await tester.pumpAndSettle();
  }

  testWidgets('saves a backup and confirms it', (tester) async {
    await pump(tester);

    await backUpNow(tester);

    expect(saver.fileNames.single, startsWith('perennia-backup-'));
    expect(find.text('Backup saved.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('says nothing when the save dialog is dismissed', (tester) async {
    saver.outcome = BackupSaveOutcome.cancelled;
    await pump(tester);

    await backUpNow(tester);

    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('explains a failed write', (tester) async {
    saver.error = PlatformException(code: 'write_failed');
    await pump(tester);

    await backUpNow(tester);

    expect(find.text("Couldn't save the backup"), findsOneWidget);
    expect(
      find.text(
        "The backup file couldn't be written there. Try again, or choose "
        'another place.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(BackupNowSection.failureDoneButtonKey));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('explains a platform that cannot save files', (tester) async {
    saver.outcome = BackupSaveOutcome.unsupported;
    await pump(tester);

    await backUpNow(tester);

    expect(find.text("This device can't save a backup file."), findsOneWidget);
  });

  testWidgets('the passphrase field stores the backup passphrase', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(
      find.byKey(BackupNowSection.passphraseFieldKey),
      'correct horse',
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(
      (await settingsRepository.load()).autoBackupEncryptionPassphrase,
      'correct horse',
    );
  });

  testWidgets('meets accessibility guidelines in both themes', (tester) async {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();
      await pump(tester, theme: theme);

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

class _RecordingSaver implements BackupFileSaver {
  final fileNames = <String>[];
  final saved = Completer<void>();
  BackupSaveOutcome outcome = BackupSaveOutcome.saved;
  Object? error;

  @override
  Future<BackupSaveOutcome> save({
    required String fileName,
    required List<int> bytes,
  }) async {
    fileNames.add(fileName);
    saved.complete();
    final error = this.error;
    if (error != null) {
      throw error;
    }
    return outcome;
  }
}
