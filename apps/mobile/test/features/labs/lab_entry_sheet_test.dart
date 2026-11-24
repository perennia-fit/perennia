import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/labs/widgets/lab_entry_sheet.dart';
import 'package:perennia/features/labs/widgets/lab_test_picker.dart';
import 'package:perennia/features/protocols/controllers/protocols_lock_controller.dart';
import 'package:perennia/features/protocols/services/protocols_pin_hasher.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

import 'lab_test_helpers.dart';

/// The lab entry sheet against a real in-memory database
/// (docs/designs/lab-results.md, PR 5, V11 and V12).
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

  // Today is 25 November 2026; the date picker opens on it.
  final now = labTestToday;
  const openKey = Key('test.openLabEntry');

  late LabScreenHarness harness;
  late AppDatabase database;
  late TrainingRepositories repositories;

  /// What the last opened sheet completed with, once it has.
  late _SheetResult sheet;

  setUp(() {
    harness = LabScreenHarness(clock: () => now);
    database = harness.database;
    repositories = harness.repositories;
    sheet = _SheetResult();
  });

  tearDown(() async {
    await harness.close();
  });

  Future<void> pumpHost(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        // A new scope each time, as after the app is killed and reopened.
        key: UniqueKey(),
        overrides: harness.overrides(),
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  key: openKey,
                  onPressed: () {
                    final result = _SheetResult();
                    sheet = result;
                    unawaited(
                      showLabEntrySheet(context).then((batchId) {
                        result
                          ..closed = true
                          ..batchId = batchId;
                      }),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<List<MetricReadingRow>> readings(WidgetTester tester) =>
      harness.readings(tester);

  Future<List<MetricRow>> metrics(WidgetTester tester) =>
      onFakeTime(tester, () => database.select(database.metrics).get());

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(openKey));
    await tester.pumpAndSettle();
    expect(find.byType(LabEntrySheet), findsOneWidget);
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, Key key, String text) async {
    final finder = find.byKey(key);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.enterText(finder, text);
    await tester.pump();
  }

  /// Chooses today in the date picker.
  Future<void> chooseToday(WidgetTester tester) async {
    await tapVisible(tester, find.byKey(LabEntrySheet.dateFieldKey));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  Future<void> chooseLabTest(
    WidgetTester tester,
    int row,
    String search,
    String labTestKey,
  ) async {
    await tapVisible(tester, find.byKey(LabEntrySheet.rowLabTestKey(row)));
    await tester.enterText(find.byKey(LabTestPicker.searchFieldKey), search);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(LabTestPicker.rowKey(labTestKey)));
    await tester.pumpAndSettle();
  }

  Future<void> addRow(WidgetTester tester) =>
      tapVisible(tester, find.byKey(LabEntrySheet.addRowButtonKey));

  Future<void> save(WidgetTester tester) =>
      tapVisible(tester, find.byKey(LabEntrySheet.saveButtonKey));

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byKey(openKey)));

  testWidgets('a hard reject shows on its row and writes nothing',
      (tester) async {
    await pumpHost(tester);
    await openSheet(tester);
    await chooseToday(tester);
    await chooseLabTest(tester, 0, 'crp', 'hs_crp');
    await enter(tester, LabEntrySheet.rowValueKey(0), '20000');

    await save(tester);

    expect(
      find.descendant(
        of: find.byKey(LabEntrySheet.rowValueKey(0)),
        matching: find.text('Value must be between 0 and 10000 mg/L.'),
      ),
      findsOneWidget,
    );
    expect(find.byType(LabEntrySheet), findsOneWidget);
    expect(find.byKey(LabEntrySheet.warningDialogKey), findsNothing);
    expect(await readings(tester), isEmpty);
    expect(await metrics(tester), isEmpty);
    expect(sheet.closed, isFalse);

    // Editing the row clears its error.
    await enter(tester, LabEntrySheet.rowValueKey(0), '2');
    expect(
      find.text('Value must be between 0 and 10000 mg/L.'),
      findsNothing,
    );
    await harness.unmount(tester);
  });

  testWidgets(
      'every soft warning is listed in one dialog, and Cancel writes nothing',
      (tester) async {
    await pumpHost(tester);
    await onFakeTime(
      tester,
      () => repositories.labResults.saveCollection(
        CollectionDraft(
          collectedDate: DateTime(2026, 11, 25),
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'testosterone_total', value: '20'),
          ],
        ),
        today: now,
      ),
    );
    expect(await readings(tester), hasLength(1));

    await openSheet(tester);
    await chooseToday(tester);
    await chooseLabTest(tester, 0, 'sodium', 'sodium');
    await enter(tester, LabEntrySheet.rowValueKey(0), '800');
    await addRow(tester);
    await chooseLabTest(tester, 1, 'testo', 'testosterone_total');
    await enter(tester, LabEntrySheet.rowValueKey(1), '25');

    await save(tester);

    final dialog = find.byKey(LabEntrySheet.warningDialogKey);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(
          'Sodium: Value is unusual for this Lab Test. Check it before '
          'saving.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(
          'Testosterone: This replaces a saved result for the same '
          'collection.',
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(LabEntrySheet.warningCancelKey));
    await tester.pumpAndSettle();

    expect(dialog, findsNothing);
    expect(find.byType(LabEntrySheet), findsOneWidget);
    expect(await readings(tester), hasLength(1));
    expect(sheet.closed, isFalse);
    await harness.unmount(tester);
  });

  testWidgets("the unit is a fixed label showing the Lab Test's unit",
      (tester) async {
    await pumpHost(tester);
    await openSheet(tester);

    final unit = find.byKey(LabEntrySheet.rowUnitKey(0));
    expect(tester.widget<Text>(unit).data, '–');

    await chooseLabTest(tester, 0, 'testosterone', 'testosterone_total');

    expect(tester.widget(unit), isA<Text>());
    expect(tester.widget<Text>(unit).data, 'nmol/L');
    expect(
      find.descendant(of: unit, matching: find.byType(EditableText)),
      findsNothing,
    );
    expect(
      find.ancestor(of: unit, matching: find.byType(TextField)),
      findsNothing,
    );
    await harness.unmount(tester);
  });

  testWidgets('choosing ≤ and typing 1 stores entered "<= 1"', (tester) async {
    await pumpHost(tester);
    await openSheet(tester);
    await chooseToday(tester);
    await chooseLabTest(tester, 0, 'hs-crp', 'hs_crp');
    await tapVisible(tester, find.byKey(LabEntrySheet.rowComparatorKey(0)));
    await tester.tap(find.text('≤').last);
    await tester.pumpAndSettle();
    await enter(tester, LabEntrySheet.rowValueKey(0), '1');

    await save(tester);

    expect(sheet.closed, isTrue);
    expect(sheet.batchId, isNotNull);
    final stored = (await readings(tester)).single;
    final valueJson = jsonDecode(stored.valueJson) as Map<String, Object?>;
    expect(valueJson['entered'], '<= 1');
    expect(stored.scalarValue, isNull);
    await harness.unmount(tester);
  });

  testWidgets('picker search for a variant finds the Lab Test', (
    tester,
  ) async {
    await pumpHost(tester);
    await openSheet(tester);
    await tapVisible(tester, find.byKey(LabEntrySheet.rowLabTestKey(0)));

    await tester.enterText(
      find.byKey(LabTestPicker.searchFieldKey),
      'alk phos',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(LabTestPicker.rowKey('alp')), findsOneWidget);
    expect(find.byKey(LabTestPicker.rowKey('alt')), findsNothing);
    expect(find.byKey(LabTestPicker.panelHeaderKey('Liver')), findsOneWidget);

    await tester.enterText(
      find.byKey(LabTestPicker.searchFieldKey),
      'Alk Phos',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(LabTestPicker.rowKey('alp')), findsOneWidget);

    await tester.tap(find.byKey(LabTestPicker.rowKey('alp')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(LabEntrySheet.rowLabTestKey(0)),
        matching: find.text('ALP'),
      ),
      findsOneWidget,
    );
    expect(tester.widget<Text>(find.byKey(LabEntrySheet.rowUnitKey(0))).data,
        'U/L');
    await harness.unmount(tester);
  });

  testWidgets('the same Lab Test on two rows is rejected and writes nothing',
      (tester) async {
    await pumpHost(tester);
    await openSheet(tester);
    await chooseToday(tester);
    await chooseLabTest(tester, 0, 'shbg', 'shbg');
    await enter(tester, LabEntrySheet.rowValueKey(0), '40');
    await addRow(tester);
    await chooseLabTest(tester, 1, 'shbg', 'shbg');
    await enter(tester, LabEntrySheet.rowValueKey(1), '41');

    await save(tester);

    expect(
      find.descendant(
        of: find.byKey(LabEntrySheet.rowLabTestErrorKey(1)),
        matching: find.text('This Lab Test is already in this collection.'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(LabEntrySheet.rowLabTestErrorKey(0)), findsNothing);
    expect(await readings(tester), isEmpty);
    expect(sheet.closed, isFalse);
    await harness.unmount(tester);
  });

  testWidgets('a valid three-row save writes one Batch holding the readings',
      (tester) async {
    await pumpHost(tester);
    await openSheet(tester);
    await chooseToday(tester);

    await chooseLabTest(tester, 0, 'testosterone', 'testosterone_total');
    await enter(tester, LabEntrySheet.rowValueKey(0), '20.0');
    await enter(tester, LabEntrySheet.rowPrintedRangeKey(0), '(10.0-30.0)');

    await addRow(tester);
    await chooseLabTest(tester, 1, 'crp', 'hs_crp');
    await tapVisible(tester, find.byKey(LabEntrySheet.rowComparatorKey(1)));
    await tester.tap(find.text('<').last);
    await tester.pumpAndSettle();
    await enter(tester, LabEntrySheet.rowValueKey(1), '1');

    await addRow(tester);
    await chooseLabTest(tester, 2, 'haemo', 'haemoglobin');
    await enter(tester, LabEntrySheet.rowValueKey(2), '150');
    await enter(tester, LabEntrySheet.rowPrintedFlagKey(2), '+');

    await save(tester);

    expect(find.byKey(LabEntrySheet.warningDialogKey), findsNothing);
    expect(sheet.closed, isTrue);
    final batchId = sheet.batchId;
    expect(batchId, isNotNull);
    expect(find.byType(LabEntrySheet), findsNothing);

    final entries =
        await onFakeTime(tester, repositories.activityLog.listEntries);
    expect(entries.map((entry) => entry.batchId).toSet(), <String>{batchId!});
    expect(
      entries.where((e) => e.entityTable == AppDatabase.metricReadingsTable),
      hasLength(3),
    );

    final stored = await readings(tester);
    expect(stored, hasLength(3));
    final labMetrics = await metrics(tester);
    final byKey = <String, Map<String, Object?>>{
      for (final reading in stored)
        labMetrics
            .singleWhere((metric) => metric.id == reading.metricId)
            .labTestKey!: jsonDecode(reading.valueJson) as Map<String, Object?>,
    };
    expect(byKey['testosterone_total']!['entered'], '20.0');
    expect(
      (byKey['testosterone_total']!['lab']! as Map)['printedRange'],
      '(10.0-30.0)',
    );
    expect((byKey['testosterone_total']!['lab']! as Map)['collected'],
        '2026-11-25');
    expect(byKey['hs_crp']!['entered'], '< 1');
    expect(byKey['haemoglobin']!['entered'], '150');
    expect((byKey['haemoglobin']!['lab']! as Map)['printedFlag'], '+');
    await harness.unmount(tester);
  });

  testWidgets('Save with no date shows the date error', (tester) async {
    await pumpHost(tester);
    await openSheet(tester);
    await chooseLabTest(tester, 0, 'shbg', 'shbg');
    await enter(tester, LabEntrySheet.rowValueKey(0), '40');

    await save(tester);

    expect(
      find.descendant(
        of: find.byKey(LabEntrySheet.dateErrorKey),
        matching: find.text('Give the collection date.'),
      ),
      findsOneWidget,
    );
    expect(await readings(tester), isEmpty);

    // The row rules run on the same Save, date or not: a second row's hard
    // reject shows with the date error, not on a later Save.
    await addRow(tester);
    await chooseLabTest(tester, 1, 'crp', 'hs_crp');
    await enter(tester, LabEntrySheet.rowValueKey(1), '20000');
    await save(tester);
    expect(
      find.descendant(
        of: find.byKey(LabEntrySheet.rowValueKey(1)),
        matching: find.text('Value must be between 0 and 10000 mg/L.'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(LabEntrySheet.dateErrorKey), findsOneWidget);
    expect(await readings(tester), isEmpty);

    // Choosing a date clears it.
    await chooseToday(tester);
    expect(find.byKey(LabEntrySheet.dateErrorKey), findsNothing);
    await harness.unmount(tester);
  });

  testWidgets('killed before Save, no Metric Reading exists', (tester) async {
    await pumpHost(tester);
    await openSheet(tester);
    await chooseToday(tester);
    await chooseLabTest(tester, 0, 'shbg', 'shbg');
    await enter(tester, LabEntrySheet.rowValueKey(0), '40');
    await addRow(tester);
    await chooseLabTest(tester, 1, 'testosterone', 'testosterone_total');
    await enter(tester, LabEntrySheet.rowValueKey(1), '20');

    // The process dies: a fresh widget tree and ProviderScope over the same
    // database.
    await pumpHost(tester);

    expect(find.byType(LabEntrySheet), findsNothing);
    expect(await readings(tester), isEmpty);
    expect(await metrics(tester), isEmpty);
    expect(
      await onFakeTime(tester, repositories.activityLog.listEntries),
      isEmpty,
    );
    await harness.unmount(tester);
  });

  testWidgets(
      'locking closes the sheet and discards its rows; reopening starts empty',
      (tester) async {
    final hash = await tester.runAsync(
      () => const ProtocolsPinHasher(iterations: 10).hash('1234'),
    );
    harness.lockStore
      ..enabled = true
      ..pinHash = hash;
    await pumpHost(tester);

    final scope = container(tester);
    final lock = scope.read(protocolsLockControllerProvider.notifier);
    Future<void> unlock() async {
      await onFakeTime(
        tester,
        () => scope.read(protocolsLockControllerProvider.future),
      );
      expect(
          await onFakeTime(tester, () => lock.unlockWithPin('1234')), isTrue);
      await tester.pumpAndSettle();
    }

    await unlock();
    await openSheet(tester);
    await chooseLabTest(tester, 0, 'shbg', 'shbg');
    await enter(tester, LabEntrySheet.rowValueKey(0), '40');

    lock
      ..didChangeAppLifecycleState(AppLifecycleState.paused)
      ..didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(scope.read(protocolsLockControllerProvider).value!.isLocked, isTrue);
    expect(find.byType(LabEntrySheet), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('SHBG'), findsNothing);
    expect(sheet.closed, isTrue);
    expect(sheet.batchId, isNull);

    await unlock();
    await openSheet(tester);

    expect(find.byKey(LabEntrySheet.rowKey(0)), findsOneWidget);
    expect(find.byKey(LabEntrySheet.rowKey(1)), findsNothing);
    expect(find.text('SHBG'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(LabEntrySheet.rowValueKey(0)))
          .controller!
          .text,
      isEmpty,
    );
    expect(
        tester.widget<Text>(find.byKey(LabEntrySheet.rowUnitKey(0))).data, '–');
    expect(await readings(tester), isEmpty);
    await harness.unmount(tester);
  });
  testWidgets(
      'locking closes the date picker, the time picker and the comparator menu with the sheet',
      (tester) async {
    final hash = await tester.runAsync(
      () => const ProtocolsPinHasher(iterations: 10).hash('1234'),
    );
    harness.lockStore
      ..enabled = true
      ..pinHash = hash;
    await pumpHost(tester);

    final scope = container(tester);
    final lock = scope.read(protocolsLockControllerProvider.notifier);
    Future<void> unlock() async {
      await onFakeTime(
        tester,
        () => scope.read(protocolsLockControllerProvider.future),
      );
      expect(
          await onFakeTime(tester, () => lock.unlockWithPin('1234')), isTrue);
      await tester.pumpAndSettle();
    }

    Future<void> lockApp() async {
      lock
        ..didChangeAppLifecycleState(AppLifecycleState.paused)
        ..didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
          scope.read(protocolsLockControllerProvider).value!.isLocked, isTrue);
      expect(find.byType(LabEntrySheet), findsNothing);
      expect(sheet.closed, isTrue);
    }

    // The date picker.
    await unlock();
    await openSheet(tester);
    await tapVisible(tester, find.byKey(LabEntrySheet.dateFieldKey));
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await lockApp();
    expect(find.byType(DatePickerDialog), findsNothing);

    // The time picker.
    await unlock();
    await openSheet(tester);
    await tapVisible(tester, find.byKey(LabEntrySheet.timeFieldKey));
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await lockApp();
    expect(find.byType(TimePickerDialog), findsNothing);

    // The comparator menu: its items are on screen twice while it is open
    // (the field and the menu), and not at all once the lock closes both.
    await unlock();
    await openSheet(tester);
    await tapVisible(tester, find.byKey(LabEntrySheet.rowComparatorKey(0)));
    expect(find.text('<'), findsWidgets);
    await lockApp();
    expect(find.text('<'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    await harness.unmount(tester);
  });
}

class _SheetResult {
  bool closed = false;
  String? batchId;
}
