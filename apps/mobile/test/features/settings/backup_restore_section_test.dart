import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/features/settings/widgets/backup_restore_section.dart';
import 'package:perennia/features/settings/widgets/backup_settings_screen.dart';
import 'package:perennia/features/settings/widgets/settings_providers.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  late AppDatabase database;
  late TrainingRepositories repositories;

  setUp(() {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(database);
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('Backup & restore offers restore from a backup file', (
    tester,
  ) async {
    await _pump(
      tester,
      repositories: repositories,
      picker: () async => null,
      home: const BackupSettingsScreen(),
    );

    await tester.scrollUntilVisible(
      find.byKey(BackupRestoreSection.restoreButtonKey),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Restore from backup'), findsOneWidget);
    expect(find.textContaining('nothing on this device is erased'),
        findsOneWidget);
  });

  testWidgets(
      'shows what a backup holds, merges it into the defaults this device '
      'seeded, and reports the result', (tester) async {
    final archive = await tester.runAsync(
      () => _archiveWithBodyWeight(<String>['84.0', '83.5']),
    );
    await tester.runAsync(
      () => repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      ),
    );
    await _pump(
      tester,
      repositories: repositories,
      picker: () async => _backupFile(archive!),
    );

    await tester.tap(find.byKey(BackupRestoreSection.restoreButtonKey));
    await _pumpUntilFound(tester, find.text('Restore this backup?'));

    expect(find.textContaining('Made '), findsOneWidget);
    expect(find.text('0 workouts'), findsOneWidget);
    expect(find.text('0 sets'), findsOneWidget);
    expect(find.text('0 food entries'), findsOneWidget);
    expect(find.text('2 metric readings'), findsOneWidget);
    expect(find.textContaining('Nothing here is erased'), findsOneWidget);
    expect(find.textContaining('Replace'), findsNothing);

    await tester.tap(find.byKey(BackupRestoreSection.confirmButtonKey));
    await _pumpUntilFound(tester, find.text('Backup restored'));

    expect(find.textContaining('items added or updated'), findsOneWidget);

    final bodyWeights = (await tester.runAsync(
      () => repositories.measurements.listActive(),
    ))!
        .where((measurement) => measurement.name == 'Body Weight')
        .toList();
    expect(bodyWeights, hasLength(1));
    final history = await tester.runAsync(
      () => repositories.measurements.listHistoryEntries(
        measurementId: bodyWeights.single.id,
      ),
    );
    expect(
      history!.map((entry) => entry.entry.valueEntered),
      unorderedEquals(<String>['84.0', '83.5']),
    );

    await tester.tap(find.byKey(BackupRestoreSection.doneButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('Backup restored'), findsNothing);
  });

  testWidgets('cancelling the review writes nothing', (tester) async {
    final archive = await tester.runAsync(
      () => _archiveWithBodyWeight(<String>['84.0']),
    );
    await _pump(
      tester,
      repositories: repositories,
      picker: () async => _backupFile(archive!),
    );

    await tester.tap(find.byKey(BackupRestoreSection.restoreButtonKey));
    await _pumpUntilFound(tester, find.text('Restore this backup?'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Restore this backup?'), findsNothing);
    final metrics = await tester.runAsync(
      () => database.select(database.metrics).get(),
    );
    expect(metrics, isEmpty);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(BackupRestoreSection.restoreButtonKey),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('asks for the passphrase of an encrypted backup again when wrong',
      (tester) async {
    final archive = await tester.runAsync(
      () => _archiveWithBodyWeight(
        <String>['84.0'],
        passphrase: 'correct horse',
      ),
    );
    await _pump(
      tester,
      repositories: repositories,
      picker: () async => _backupFile(archive!),
    );

    await tester.tap(find.byKey(BackupRestoreSection.restoreButtonKey));
    await _pumpUntilFound(tester, find.text('Encrypted backup'));
    expect(
      tester
          .widget<FilledButton>(
              find.byKey(BackupRestoreSection.unlockButtonKey))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(BackupRestoreSection.passphraseFieldKey),
      'wrong horse',
    );
    await tester.pump();
    await tester.tap(find.byKey(BackupRestoreSection.unlockButtonKey));
    await _pumpUntilFound(
      tester,
      find.text("That passphrase didn't unlock this backup."),
    );

    await tester.enterText(
      find.byKey(BackupRestoreSection.passphraseFieldKey),
      'correct horse',
    );
    await tester.pump();
    await tester.tap(find.byKey(BackupRestoreSection.unlockButtonKey));
    await _pumpUntilFound(tester, find.text('Restore this backup?'));
    expect(find.text('1 metric reading'), findsOneWidget);

    await tester.tap(find.byKey(BackupRestoreSection.confirmButtonKey));
    await _pumpUntilFound(tester, find.text('Backup restored'));

    final readings = await tester.runAsync(
      () => database.select(database.metricReadings).get(),
    );
    expect(readings, hasLength(1));
  });

  testWidgets('cancelling the passphrase prompt writes nothing', (
    tester,
  ) async {
    final archive = await tester.runAsync(
      () => _archiveWithBodyWeight(<String>['84.0'], passphrase: 'secret'),
    );
    await _pump(
      tester,
      repositories: repositories,
      picker: () async => _backupFile(archive!),
    );

    await tester.tap(find.byKey(BackupRestoreSection.restoreButtonKey));
    await _pumpUntilFound(tester, find.text('Encrypted backup'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Encrypted backup'), findsNothing);
    expect(find.text('Restore this backup?'), findsNothing);
    final metrics = await tester.runAsync(
      () => database.select(database.metrics).get(),
    );
    expect(metrics, isEmpty);
  });

  testWidgets('reports a file that is not a backup without changing anything',
      (tester) async {
    await _pump(
      tester,
      repositories: repositories,
      picker: () async => _backupFile(utf8.encode('not a backup')),
    );

    await tester.tap(find.byKey(BackupRestoreSection.restoreButtonKey));
    await _pumpUntilFound(tester, find.text("Couldn't restore this backup"));

    expect(
      find.text(
        "This file isn't a Perennia backup, or it's damaged. Nothing on this "
        'device was changed.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(BackupRestoreSection.doneButtonKey));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't restore this backup"), findsNothing);
  });

  testWidgets('restore section meets accessibility guidelines in both themes',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        repositories: repositories,
        picker: () async => null,
        theme: theme,
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
    }
  });

  testWidgets('dismissing the file picker does nothing', (tester) async {
    var picks = 0;
    await _pump(
      tester,
      repositories: repositories,
      picker: () async {
        picks += 1;
        return null;
      },
    );

    await tester.tap(find.byKey(BackupRestoreSection.restoreButtonKey));
    await tester.pumpAndSettle();

    expect(picks, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required TrainingRepositories repositories,
  required BackupArchiveFilePicker picker,
  Widget? home,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
        settingsRepositoryProvider.overrideWith(
          (ref) => InMemorySettingsRepository(),
        ),
        backupArchiveFilePickerProvider.overrideWith((ref) => picker),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home ??
            Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(AppDimens.base),
                children: const [BackupRestoreSection()],
              ),
            ),
      ),
    ),
  );
  await tester.pump();
}

/// An archive from another install: its own default measurements (random
/// ids, unlike this device's) with Body Weight readings.
Future<List<int>> _archiveWithBodyWeight(
  List<String> values, {
  String? passphrase,
}) async {
  final sourceDatabase = AppDatabase.inMemory();
  try {
    final source = TrainingRepositories(sourceDatabase);
    await source.measurements.ensureDefaultMeasurements(
      bodyWeightUnit: MeasurementUnit.kilogram,
    );
    final bodyWeight = (await source.measurements.listActive())
        .singleWhere((measurement) => measurement.name == 'Body Weight');
    for (final (index, value) in values.indexed) {
      await source.measurements.createEntry(
        MeasurementEntryDraft(
          measurementId: bodyWeight.id,
          valueEntered: value,
          measuredAt: DateTime.utc(2026, 5, 1 + index, 7),
        ),
      );
    }
    return await source.portableArchives.exportPortableArchive(
      createdAt: DateTime.utc(2026, 10, 1, 9),
      encryption: passphrase == null
          ? null
          : PortableArchiveEncryptionOptions(passphrase: passphrase),
    );
  } finally {
    await sourceDatabase.close();
  }
}

XFile _backupFile(List<int> bytes) {
  return XFile.fromData(
    Uint8List.fromList(bytes),
    name: 'perennia-auto-backup-20261001T090000Z.zip',
  );
}

/// Restore mixes real I/O (sqlite) with work scheduled on the test's fake
/// clock (key derivation yields through timers), so advance both between
/// frames until [finder] shows up.
Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 600; attempt += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 300));
      return;
    }
  }
  fail('Timed out waiting for $finder');
}
