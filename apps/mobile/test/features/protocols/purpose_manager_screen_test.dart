import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/protocols/controllers/protocols_lock_controller.dart';
import 'package:perennia/features/protocols/services/protocols_lock_store.dart';
import 'package:perennia/features/protocols/widgets/compound_list_screen.dart';
import 'package:perennia/features/protocols/widgets/purpose_filter_row.dart';
import 'package:perennia/features/protocols/widgets/purpose_manager_screen.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

// The manager against real repositories, because CUJ 8's outcome is what the
// filter rows read back, and the undo refusal is the Activity Log's.
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

  final sleepId = starterPurposes[0].id;
  final generalHealthId = starterPurposes[5].id;

  // Database work runs here, or under tester.runAsync, outside the widget
  // test's fake clock.
  setUp(() async {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(database);
    await repositories.protocols.ensureOtcLibrarySeeded();
  });

  Future<List<PurposeRecord>> active(WidgetTester tester) async {
    return (await tester.runAsync(repositories.protocols.purposes.listActive))!;
  }

  Future<List<String>> activeNames(WidgetTester tester) async {
    return (await active(tester)).map((purpose) => purpose.name).toList();
  }

  Future<void> openMenu(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(PurposeManagerScreen.menuButtonKey(id)));
    await _settle(tester);
  }

  Future<void> submitName(WidgetTester tester, String name) async {
    await tester.enterText(
      find.byKey(PurposeManagerScreen.nameFieldKey),
      name,
    );
    await tester.tap(find.byKey(PurposeManagerScreen.saveNameButtonKey));
    await _settle(tester);
  }

  Future<void> add(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(PurposeManagerScreen.addButtonKey));
    await _settle(tester);
    await submitName(tester, name);
  }

  Future<void> archive(WidgetTester tester, String id) async {
    await openMenu(tester, id);
    await tester.tap(find.byKey(PurposeManagerScreen.archiveMenuKey(id)));
    await _settle(tester);
    await tester.tap(find.byKey(PurposeManagerScreen.archiveConfirmButtonKey));
    await _settle(tester);
  }

  /// Presses and holds a row, then drags it to the top of the list.
  Future<void> dragToTop(WidgetTester tester, String id) async {
    final row = find.byKey(PurposeManagerScreen.rowKey(id));
    final top = tester.getCenter(
      find.byKey(PurposeManagerScreen.rowKey((await active(tester)).first.id)),
    );
    final start = tester.getCenter(row);
    final gesture = await tester.startGesture(start);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    final distance = top.dy - start.dy - 40;
    for (var step = 1; step <= 10; step += 1) {
      await gesture.moveBy(Offset(0, distance / 10));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await gesture.up();
    await _settle(tester);
  }

  testWidgets(
      'CUJ 8: archive General health, add Skin, drag it to the top; the filter '
      'rows follow and the tag survives', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, repositories, home: const CompoundListScreen());

    await tester.tap(find.byKey(CompoundListScreen.menuButtonKey));
    await _settle(tester);
    await tester.tap(find.byKey(CompoundListScreen.purposesMenuKey));
    await _settle(tester);
    expect(find.byType(PurposeManagerScreen), findsOneWidget);

    await archive(tester, generalHealthId);
    expect(find.text('General health'), findsNothing);

    await add(tester, 'Skin');
    final skinId = (await active(tester)).last.id;
    expect(find.text('Skin'), findsOneWidget);

    await dragToTop(tester, skinId);
    expect((await activeNames(tester)).first, 'Skin');

    await tester.pageBack();
    await _settle(tester);

    final chips = tester
        .widgetList<FilterChip>(
          find.descendant(
            of: find.byKey(PurposeFilterRow.rowKey),
            matching: find.byType(FilterChip),
          ),
        )
        .map((chip) => (chip.label as Text).data)
        .toList();
    expect(chips, <String>[
      'All',
      'Skin',
      'Sleep',
      'Body composition',
      'Performance',
      'Recovery',
      'Cognition',
    ]);

    // Vitamin D and Fish oil keep the archived tag.
    final compounds = (await tester.runAsync(
      repositories.protocols.listCompounds,
    ))!;
    expect(
      compounds.where((c) => c.purposeIds.contains(generalHealthId)),
      hasLength(2),
    );

    await _closeDatabase(tester, database);
  });

  testWidgets('undoing an archive restores the Purpose and the filter chip', (
    tester,
  ) async {
    await _pump(tester, repositories);
    await archive(tester, generalHealthId);
    expect(find.text('General health'), findsNothing);

    final entries = (await tester.runAsync(
      repositories.activityLog.listEntries,
    ))!;
    final entry = entries.firstWhere(
      (entry) =>
          entry.entityTable == AppDatabase.purposesTable &&
          entry.entityId == generalHealthId &&
          entry.afterImage?['deleted_at'] != null,
    );
    final result = (await tester.runAsync(
      () => repositories.activityLog.undoBatch(entry.batchId),
    ))!;
    expect(result.conflicts, isEmpty);
    await _settle(tester);

    expect(find.text('General health'), findsOneWidget);
    await _closeDatabase(tester, database);
  });

  testWidgets('undoing into a name in use again is refused', (tester) async {
    await _pump(tester, repositories);
    await archive(tester, generalHealthId);
    await add(tester, 'General health');

    final entries = (await tester.runAsync(
      repositories.activityLog.listEntries,
    ))!;
    final entry = entries.firstWhere(
      (entry) =>
          entry.entityTable == AppDatabase.purposesTable &&
          entry.entityId == generalHealthId &&
          entry.afterImage?['deleted_at'] != null,
    );
    final result = (await tester.runAsync(
      () => repositories.activityLog.undoBatch(entry.batchId),
    ))!;
    expect(
      result.conflicts.single.reason,
      ActivityLogUndoConflictReason.duplicatePurposeName,
    );
    await _closeDatabase(tester, database);
  });

  testWidgets('rename stores the new name, and leaves tags alone', (
    tester,
  ) async {
    await _pump(tester, repositories);

    await openMenu(tester, sleepId);
    await tester.tap(find.byKey(PurposeManagerScreen.renameMenuKey(sleepId)));
    await _settle(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(PurposeManagerScreen.nameFieldKey))
          .controller
          ?.text,
      'Sleep',
    );
    await submitName(tester, '  Rest  ');

    expect(find.byKey(PurposeManagerScreen.nameFieldKey), findsNothing);
    expect(find.text('Rest'), findsOneWidget);
    expect((await activeNames(tester)).first, 'Rest');
    final compounds = (await tester.runAsync(
      repositories.protocols.listCompounds,
    ))!;
    expect(
      compounds.where((c) => c.purposeIds.contains(sleepId)),
      hasLength(2),
    );
    await _closeDatabase(tester, database);
  });

  testWidgets('an empty name shows inline and saves nothing', (tester) async {
    await _pump(tester, repositories);
    final before = await activeNames(tester);

    await tester.tap(find.byKey(PurposeManagerScreen.addButtonKey));
    await _settle(tester);
    await submitName(tester, '   ');

    expect(find.text('Enter a name.'), findsOneWidget);
    expect(find.byKey(PurposeManagerScreen.nameFieldKey), findsOneWidget);
    expect(await activeNames(tester), before);

    // Typing clears the error, and the dialog can still save.
    await submitName(tester, 'Skin');
    expect(find.byKey(PurposeManagerScreen.nameFieldKey), findsNothing);
    expect(find.text('Skin'), findsOneWidget);
    await _closeDatabase(tester, database);
  });

  testWidgets('a duplicate name shows inline, in any case, on add and rename', (
    tester,
  ) async {
    await _pump(tester, repositories);
    final before = await activeNames(tester);

    await tester.tap(find.byKey(PurposeManagerScreen.addButtonKey));
    await _settle(tester);
    await submitName(tester, 'sLEEP');
    expect(
      find.text('A purpose with that name already exists.'),
      findsOneWidget,
    );
    expect(await activeNames(tester), before);
    await tester.tap(find.text('Cancel'));
    await _settle(tester);

    final recoveryId = starterPurposes[3].id;
    await openMenu(tester, recoveryId);
    await tester.tap(
      find.byKey(PurposeManagerScreen.renameMenuKey(recoveryId)),
    );
    await _settle(tester);
    await submitName(tester, 'Sleep');
    expect(
      find.text('A purpose with that name already exists.'),
      findsOneWidget,
    );
    expect(await activeNames(tester), before);
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    await _closeDatabase(tester, database);
  });

  testWidgets('the archive dialog never pairs the name with a verb', (
    tester,
  ) async {
    await _pump(tester, repositories);

    await openMenu(tester, sleepId);
    await tester.tap(find.byKey(PurposeManagerScreen.archiveMenuKey(sleepId)));
    await _settle(tester);

    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.text('Sleep')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(
          'Archive this purpose? Compounds keep the tag; it stops showing.',
        ),
      ),
      findsOneWidget,
    );

    // Cancelling archives nothing.
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(await activeNames(tester), contains('Sleep'));
    await _closeDatabase(tester, database);
  });

  group('a re-lock', () {
    Future<void> expectClosedOnLock(
      WidgetTester tester, {
      required _SwitchableLockController lock,
      required Finder dialog,
    }) async {
      expect(dialog, findsOneWidget);
      lock.set(ProtocolsLockStatus.locked);
      await _settle(tester);
      expect(dialog, findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      await _closeDatabase(tester, database);
    }

    testWidgets('closes the name dialog', (tester) async {
      final lock = _SwitchableLockController();
      await _pump(tester, repositories, lock: lock);

      await openMenu(tester, sleepId);
      await tester.tap(find.byKey(PurposeManagerScreen.renameMenuKey(sleepId)));
      await _settle(tester);

      await expectClosedOnLock(
        tester,
        lock: lock,
        dialog: find.byKey(PurposeManagerScreen.nameFieldKey),
      );
    });

    testWidgets('closes the archive dialog', (tester) async {
      final lock = _SwitchableLockController();
      await _pump(tester, repositories, lock: lock);

      await openMenu(tester, sleepId);
      await tester.tap(
        find.byKey(PurposeManagerScreen.archiveMenuKey(sleepId)),
      );
      await _settle(tester);

      await expectClosedOnLock(
        tester,
        lock: lock,
        dialog: find.byKey(PurposeManagerScreen.archiveConfirmButtonKey),
      );
    });
  });
}

Future<void> _pump(
  WidgetTester tester,
  TrainingRepositories repositories, {
  Widget home = const PurposeManagerScreen(),
  ProtocolsLockController? lock,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
        protocolsLockStoreProvider.overrideWith((ref) => _NoLockStore()),
        if (lock != null)
          protocolsLockControllerProvider.overrideWith(() => lock),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await _settle(tester);
}

/// Unmounts first, because the screen's Drift watches hold the database open
/// until then, and closes it on fake time, because their cleanup timers fire only
/// on frames here. A `tearDown` close would wait on those timers forever.
Future<void> _closeDatabase(WidgetTester tester, AppDatabase database) async {
  await tester.pumpWidget(const SizedBox.shrink());
  var closed = false;
  unawaited(database.close().then((_) => closed = true));
  for (var frame = 0; frame < 100 && !closed; frame += 1) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(closed, isTrue);
}

Future<void> _settle(WidgetTester tester) async {
  for (var pass = 0; pass < 3; pass += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
}

/// A lock whose state a test sets directly, the way the real controller moves
/// when the app backgrounds.
class _SwitchableLockController extends ProtocolsLockController {
  @override
  Future<ProtocolsLockState> build() async {
    return const ProtocolsLockState(
      status: ProtocolsLockStatus.unlocked,
      hasPin: true,
    );
  }

  void set(ProtocolsLockStatus status) {
    state = AsyncData<ProtocolsLockState>(
      ProtocolsLockState(status: status, hasPin: true),
    );
  }
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
