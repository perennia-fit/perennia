import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/protocols/services/protocols_lock_store.dart';
import 'package:perennia/features/protocols/widgets/compound_list_screen.dart';
import 'package:perennia/features/protocols/widgets/compound_picker_sheet.dart';
import 'package:perennia/features/protocols/widgets/protocol_screen.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

// The picker's list against a real database, opened more than once. Nothing else
// listens to its providers from the Protocol editor, so Riverpod pauses them
// between opens, and only real Drift watches show what that does to a later open.
void main() {
  late AppDatabase database;
  late TrainingRepositories repositories;

  setUp(() {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(database);
  });

  Future<void> pumpForm(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trainingRepositoriesProvider.overrideWith((ref) => repositories),
          protocolsLockStoreProvider.overrideWith((ref) => _NoLockStore()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ProtocolFormScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.byKey(ProtocolFormScreen.addCompoundsKey));
    await tester.pumpAndSettle();
  }

  Future<void> closePicker(WidgetTester tester) async {
    await tester.tap(find.byKey(CompoundPickerSheet.doneButtonKey));
    await tester.pumpAndSettle();
  }

  Future<String> createCompound(String name) async {
    final created = await repositories.protocols.createCompound(
      CompoundDraft(
        name: name,
        defaultUnit: DoseUnit.milligram,
        defaultRoute: DoseRoute.oral,
      ),
    );
    return created.compoundId;
  }

  /// Drift's stream-cache timers fire only on frames here, on fake time, so a
  /// write has to pump while it waits.
  Future<T> onFakeTime<T>(
    WidgetTester tester,
    Future<T> Function() write,
  ) async {
    late T result;
    var done = false;
    unawaited(
      write().then((value) {
        result = value;
        done = true;
      }),
    );
    for (var frame = 0; frame < 100 && !done; frame += 1) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(done, isTrue);
    return result;
  }

  /// Unmounts first: the form's Drift watches hold the database open until then.
  Future<void> closeDatabase(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await onFakeTime(tester, database.close);
  }

  Finder rowOf(CompoundPickerSection section, String id) =>
      find.byKey(CompoundPickerSheet.rowKey(section, id));

  testWidgets(
      'a Compound created inline is listed and counted on the next open',
      (tester) async {
    await pumpForm(tester);

    await openPicker(tester);
    await tester.enterText(
      find.byKey(CompoundPickerSheet.searchFieldKey),
      'Glycine',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CompoundPickerSheet.createRowKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CompoundEditorSheet.saveButtonKey));
    await tester.pumpAndSettle();
    await closePicker(tester);
    expect(find.text('Glycine'), findsOneWidget);

    await openPicker(tester);
    final id = (await onFakeTime(tester, repositories.protocols.listCompounds))
        .single
        .id;
    expect(rowOf(CompoundPickerSection.all, id), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(rowOf(CompoundPickerSection.all, id))
          .value,
      isTrue,
    );
    expect(
      find.descendant(
        of: find.byKey(CompoundPickerSheet.doneButtonKey),
        matching: find.text('Done · 1'),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(CompoundPickerSheet.searchFieldKey),
      'Glycine',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(CompoundPickerSheet.createRowKey), findsNothing);

    // Unticking works, so the member can leave through the picker.
    await tester.tap(rowOf(CompoundPickerSection.all, id));
    await tester.pumpAndSettle();
    await closePicker(tester);
    expect(find.text('Glycine'), findsNothing);

    await closeDatabase(tester);
  });

  testWidgets('a later open shows writes made while the sheet was closed',
      (tester) async {
    final kept = await onFakeTime(tester, () => createCompound('Creatine'));
    final archived = await onFakeTime(tester, () => createCompound('Caffeine'));
    await pumpForm(tester);

    await openPicker(tester);
    expect(rowOf(CompoundPickerSection.all, kept), findsOneWidget);
    expect(rowOf(CompoundPickerSection.all, archived), findsOneWidget);
    expect(rowOf(CompoundPickerSection.recent, kept), findsNothing);
    await closePicker(tester);

    // Written with no sheet open, as a sync pull or an Activity Log undo is.
    final added = await onFakeTime(tester, () => createCompound('Taurine'));
    await onFakeTime(tester, () async {
      await repositories.protocols.archiveCompound(archived);
      await repositories.protocols.logDose(
        DoseSnapshotDraft.fromCompound(
          compound: (await repositories.protocols.listCompounds())
              .singleWhere((compound) => compound.id == kept),
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 8),
        ),
      );
    });
    await tester.pumpAndSettle();

    await openPicker(tester);
    expect(rowOf(CompoundPickerSection.all, added), findsOneWidget);
    expect(rowOf(CompoundPickerSection.all, archived), findsNothing);
    expect(rowOf(CompoundPickerSection.recent, kept), findsOneWidget);
    await closePicker(tester);

    await closeDatabase(tester);
  });
}

class _NoLockStore implements ProtocolsLockStore {
  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<void> setEnabled(bool enabled) async {}

  @override
  Future<String?> readPinHash() async => null;

  @override
  Future<void> writePinHash(String hash) async {}

  @override
  Future<void> clearPin() async {}
}
