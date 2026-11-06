import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/protocols/controllers/protocol_controller.dart';
import 'package:perennia/features/protocols/controllers/protocols_day_controller.dart';
import 'package:perennia/features/protocols/controllers/protocols_lock_controller.dart';
import 'package:perennia/features/protocols/services/protocols_lock_store.dart';
import 'package:perennia/features/protocols/widgets/compound_list_screen.dart';
import 'package:perennia/features/protocols/widgets/compound_picker_sheet.dart';
import 'package:perennia/features/protocols/widgets/protocol_screen.dart';
import 'package:perennia/features/protocols/widgets/protocols_lock_screen.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  testWidgets('Protocol list shows the empty state with no Protocols',
      (tester) async {
    await _pumpListScreen(tester, _FakeProtocolListController());
    await _pumpUntilFound(tester, find.byKey(ProtocolListScreen.emptyStateKey));

    expect(find.byKey(ProtocolListScreen.emptyStateKey), findsOneWidget);
    expect(find.byKey(ProtocolListScreen.listKey), findsNothing);
  });

  testWidgets('Protocol list shows a stack\'s name, window, and member count',
      (tester) async {
    final controller = _FakeProtocolListController(
      protocols: <ProtocolRecord>[_leanBulkStack()],
    );
    await _pumpListScreen(tester, controller);
    await _pumpUntilFound(tester, find.byKey(ProtocolListScreen.listKey));

    expect(
      find.byKey(ProtocolListScreen.rowKey('protocol-1')),
      findsOneWidget,
    );
    expect(find.text('Lean bulk'), findsOneWidget);
    // A multi-Compound Protocol is a stack (PROTOCOLS.md §1.4): the member
    // count renders, paired with text (never color-only).
    expect(find.textContaining('2 Compounds'), findsOneWidget);
  });

  testWidgets('Protocol list resolves member names from a scoped lookup',
      (tester) async {
    final controller = _FakeProtocolListController(
      protocols: <ProtocolRecord>[_leanBulkStack()],
    );
    await _pumpListScreen(
      tester,
      controller,
      compoundNames: const <String, String>{
        'compound-creatine': 'Creatine',
        'compound-vitamin-d': 'Vitamin D',
      },
    );
    await _pumpUntilFound(tester, find.byKey(ProtocolListScreen.listKey));
    await _pumpUntilFound(tester, find.text('Creatine, Vitamin D'));

    expect(find.text('Creatine, Vitamin D'), findsOneWidget);
  });

  testWidgets('Protocol row opens the editor from scoped detail',
      (tester) async {
    final controller = _FakeProtocolListController(
      protocols: <ProtocolRecord>[_leanBulkStackWithSchedule()],
    );
    await _pumpListScreen(tester, controller);
    await _pumpUntilFound(tester, find.byKey(ProtocolListScreen.listKey));

    await tester.tap(find.byKey(ProtocolListScreen.rowKey('protocol-1')));
    await _pumpUntilFound(tester, find.byKey(ProtocolFormScreen.nameFieldKey));

    final nameField = tester.widget<TextField>(
      find.byKey(ProtocolFormScreen.nameFieldKey),
    );
    expect(nameField.controller?.text, 'Lean bulk');
    expect(
      find.byKey(ProtocolFormScreen.memberRowKey('compound-creatine')),
      findsOneWidget,
    );
  });

  testWidgets(
      'creating a Protocol: naming it, picking Compounds, and saving calls '
      'the controller', (tester) async {
    final controller = _FakeProtocolListController();
    await _pumpFormScreen(
      tester,
      controller,
      compounds: _compounds(),
      dayController: _FakeProtocolDayController(
        lastDoses: <String, ({double amount, DoseUnit unit})>{
          'compound-creatine': (amount: 5, unit: DoseUnit.gram),
          'compound-vitamin-d': (
            amount: 1000,
            unit: DoseUnit.internationalUnit,
          ),
        },
      ),
    );
    await _pumpUntilFound(tester, find.byKey(ProtocolFormScreen.nameFieldKey));

    await tester.enterText(
      find.byKey(ProtocolFormScreen.nameFieldKey),
      'Lean bulk',
    );
    await _addMembers(
      tester,
      <String>['compound-creatine', 'compound-vitamin-d'],
    );

    await tester.ensureVisible(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.tap(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(controller.createdDrafts, hasLength(1));
    final draft = controller.createdDrafts.single;
    expect(draft.name, 'Lean bulk');
    expect(
      draft.compoundIds,
      <String>['compound-creatine', 'compound-vitamin-d'],
    );
    // No end date picked: an open-ended (ongoing) course by default.
    expect(draft.endLocalDate, isNull);
  });

  testWidgets('creating a Protocol requires at least one Compound',
      (tester) async {
    final controller = _FakeProtocolListController();
    await _pumpFormScreen(tester, controller, compounds: _compounds());
    await _pumpUntilFound(tester, find.byKey(ProtocolFormScreen.nameFieldKey));

    await tester.enterText(
      find.byKey(ProtocolFormScreen.nameFieldKey),
      'Lean bulk',
    );
    await tester.ensureVisible(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.tap(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(controller.createdDrafts, isEmpty);
    expect(find.textContaining('at least one Compound'), findsOneWidget);
  });

  testWidgets(
      'editing a Protocol pre-fills its name and membership, and supports '
      'removing a Compound', (tester) async {
    final controller = _FakeProtocolListController();
    await _pumpFormScreen(
      tester,
      controller,
      protocol: _leanBulkStack(),
      compounds: _compounds(),
    );
    await _pumpUntilFound(tester, find.byKey(ProtocolFormScreen.nameFieldKey));

    expect(find.text('Lean bulk'), findsOneWidget);
    // Editing the window never touches a logged Dose — this screen only
    // reads/writes the Protocol row + its membership (PROTOCOLS.md §1.4).
    await _tap(
      tester,
      find.byKey(ProtocolFormScreen.removeMemberKey('compound-vitamin-d')),
    );
    expect(
      find.byKey(ProtocolFormScreen.memberRowKey('compound-vitamin-d')),
      findsNothing,
    );

    await tester.ensureVisible(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.tap(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(controller.editedProtocolIds, <String>['protocol-1']);
    final draft = controller.editedDrafts.single;
    expect(draft.compoundIds, <String>['compound-creatine']);
  });

  testWidgets('archiving a Protocol from the edit screen calls the controller',
      (tester) async {
    final controller = _FakeProtocolListController();
    await _pumpFormScreen(
      tester,
      controller,
      protocol: _leanBulkStack(),
      compounds: _compounds(),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(ProtocolFormScreen.archiveButtonKey),
    );

    await tester.ensureVisible(find.byKey(ProtocolFormScreen.archiveButtonKey));
    await tester.tap(find.byKey(ProtocolFormScreen.archiveButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ProtocolFormScreen.confirmArchiveButtonKey));
    await tester.pumpAndSettle();

    expect(controller.archivedProtocolIds, <String>['protocol-1']);
  });

  group('Archive or Delete (D8)', () {
    Future<void> openSaved(
      WidgetTester tester,
      _FakeProtocolListController controller, {
      required Stream<bool> Function() hasHistory,
      ThemeData? theme,
    }) async {
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _leanBulkStack(),
        compounds: _compounds(),
        hasHistory: hasHistory,
        theme: theme,
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.saveButtonKey),
      );
    }

    testWidgets(
        'a Protocol with no history shows Delete, not Archive, and asks '
        'before deleting', (tester) async {
      final controller = _FakeProtocolListController();
      await openSaved(
        tester,
        controller,
        hasHistory: () => Stream<bool>.value(false),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.deleteButtonKey),
      );
      expect(find.byKey(ProtocolFormScreen.archiveButtonKey), findsNothing);

      await _tap(tester, find.byKey(ProtocolFormScreen.deleteButtonKey));
      expect(find.text('Delete Lean bulk?'), findsOneWidget);
      expect(
        find.text(
          'Nothing has been logged for this Protocol, so it is removed '
          'completely. You can still recover it from the Activity Log.',
        ),
        findsOneWidget,
      );

      // Cancel writes nothing.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.deletedProtocolIds, isEmpty);
      expect(controller.archivedProtocolIds, isEmpty);

      await _tap(tester, find.byKey(ProtocolFormScreen.deleteButtonKey));
      await tester.tap(find.byKey(ProtocolFormScreen.confirmDeleteButtonKey));
      await tester.pumpAndSettle();

      expect(controller.deletedProtocolIds, <String>['protocol-1']);
      expect(controller.archivedProtocolIds, isEmpty);
    });

    testWidgets(
        'a Protocol with history shows Archive, not Delete, and asks before '
        'archiving', (tester) async {
      final controller = _FakeProtocolListController();
      await openSaved(
        tester,
        controller,
        hasHistory: () => Stream<bool>.value(true),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.archiveButtonKey),
      );
      expect(find.byKey(ProtocolFormScreen.deleteButtonKey), findsNothing);

      await _tap(tester, find.byKey(ProtocolFormScreen.archiveButtonKey));
      expect(find.text('Archive Lean bulk?'), findsOneWidget);
      expect(
        find.text(
          'Doses you logged stay in your history. From tomorrow it plans '
          "nothing, and today's doses you haven't logged are no longer "
          'expected.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.archivedProtocolIds, isEmpty);

      await _tap(tester, find.byKey(ProtocolFormScreen.archiveButtonKey));
      await tester.tap(find.byKey(ProtocolFormScreen.confirmArchiveButtonKey));
      await tester.pumpAndSettle();

      expect(controller.archivedProtocolIds, <String>['protocol-1']);
      expect(controller.deletedProtocolIds, isEmpty);
    });

    testWidgets(
        'neither shows while the history read loads, nor on a new '
        'Protocol', (tester) async {
      final pending = StreamController<bool>();
      addTearDown(pending.close);
      await openSaved(
        tester,
        _FakeProtocolListController(),
        hasHistory: () => pending.stream,
      );
      expect(find.byKey(ProtocolFormScreen.archiveButtonKey), findsNothing);
      expect(find.byKey(ProtocolFormScreen.deleteButtonKey), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpFormScreen(
        tester,
        _FakeProtocolListController(),
        compounds: _compounds(),
        hasHistory: () => Stream<bool>.value(false),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.saveButtonKey),
      );
      expect(find.byKey(ProtocolFormScreen.archiveButtonKey), findsNothing);
      expect(find.byKey(ProtocolFormScreen.deleteButtonKey), findsNothing);
    });

    testWidgets(
        'a delete refused for history shows the snack bar, and the button '
        'follows the fresh read', (tester) async {
      final history = StreamController<bool>();
      addTearDown(history.close);
      final controller = _FakeProtocolListController()
        ..deleteError = const ProtocolHasHistoryException('protocol-1');
      await openSaved(tester, controller, hasHistory: () => history.stream);
      history.add(false);
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.deleteButtonKey),
      );

      await _tap(tester, find.byKey(ProtocolFormScreen.deleteButtonKey));
      await tester.tap(find.byKey(ProtocolFormScreen.confirmDeleteButtonKey));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.text(
          'Something was logged for this Protocol, so it can only be '
          'archived.',
        ),
        findsOneWidget,
      );
      expect(controller.deletedProtocolIds, isEmpty);
      // The screen stays open.
      expect(find.byKey(ProtocolFormScreen.saveButtonKey), findsOneWidget);

      // The synced Dose reaches the history read.
      history.add(true);
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.archiveButtonKey),
      );
      expect(find.byKey(ProtocolFormScreen.deleteButtonKey), findsNothing);
    });

    testWidgets(
        'a delete that fails for another reason re-enables the buttons and '
        'says why', (tester) async {
      final controller = _FakeProtocolListController()
        ..deleteError = Exception('disk full');
      await openSaved(
        tester,
        controller,
        hasHistory: () => Stream<bool>.value(false),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.deleteButtonKey),
      );

      await _tap(tester, find.byKey(ProtocolFormScreen.deleteButtonKey));
      await tester.tap(find.byKey(ProtocolFormScreen.confirmDeleteButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not delete the Protocol: Exception: disk full'),
        findsOneWidget,
      );
      final delete = tester.widget<ButtonStyleButton>(
        find.byKey(ProtocolFormScreen.deleteButtonKey),
      );
      expect(delete.onPressed, isNotNull);
      final save = tester.widget<ButtonStyleButton>(
        find.byKey(ProtocolFormScreen.saveButtonKey),
      );
      expect(save.onPressed, isNotNull);
    });

    testWidgets(
        'a Protocol already deleted on another device closes the editor '
        'instead of leaving it disabled', (tester) async {
      final controller = _FakeProtocolListController()
        ..deleteError = StateError('Protocol is deleted: protocol-1.');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            protocolListControllerProvider.overrideWith(() => controller),
            protocolHasHistoryProvider.overrideWith(
              (ref, protocolId) => Stream<bool>.value(false),
            ),
            compoundsByIdsProvider.overrideWith(
              (ref, request) =>
                  Stream<List<CompoundScheduleOptionRecord>>.value(
                _compounds()
                    .map(_compoundScheduleOptionFromCompound)
                    .toList(growable: false),
              ),
            ),
            metricOptionListProvider.overrideWith(
              (ref) => Stream<List<MetricOptionRecord>>.value(
                const <MetricOptionRecord>[],
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ProtocolFormScreen(protocol: _leanBulkStack()),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.deleteButtonKey),
      );

      await _tap(tester, find.byKey(ProtocolFormScreen.deleteButtonKey));
      await tester.tap(find.byKey(ProtocolFormScreen.confirmDeleteButtonKey));
      await tester.pumpAndSettle();

      expect(find.byType(ProtocolFormScreen), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets(
        'Delete and Archive are 48 dp targets with text in both themes, so '
        'the destructive color is never the only signal', (tester) async {
      // Tall enough not to scroll: a row half under the app bar reads as a
      // small tap target.
      tester.view.physicalSize = const Size(2400, 4800);
      addTearDown(tester.view.resetPhysicalSize);
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        for (final hasHistory in <bool>[false, true]) {
          final semantics = tester.ensureSemantics();
          await openSaved(
            tester,
            _FakeProtocolListController(),
            hasHistory: () => Stream<bool>.value(hasHistory),
            theme: theme,
          );
          final button = find.byKey(
            hasHistory
                ? ProtocolFormScreen.archiveButtonKey
                : ProtocolFormScreen.deleteButtonKey,
          );
          await _pumpUntilFound(tester, button);
          await _reveal(tester, button);

          final size = tester.getSize(button);
          expect(size.height, greaterThanOrEqualTo(AppDimens.touchTarget));
          expect(
            find.descendant(
              of: button,
              matching: find.text(hasHistory ? 'Archive' : 'Delete'),
            ),
            findsOneWidget,
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

          // The confirmation's buttons too.
          await tester.tap(button);
          await tester.pumpAndSettle();
          final confirm = find.byKey(
            hasHistory
                ? ProtocolFormScreen.confirmArchiveButtonKey
                : ProtocolFormScreen.confirmDeleteButtonKey,
          );
          expect(
            tester.getSize(confirm).height,
            greaterThanOrEqualTo(AppDimens.touchTarget),
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

          semantics.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    });
  });

  group('Schedule editor', () {
    testWidgets(
        'an added Compound\'s Schedule editor opens from its row, in a sheet',
        (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(tester, controller, compounds: _compounds());
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      await _addMembers(tester, <String>['compound-creatine']);
      expect(
        find.byKey(ProtocolFormScreen.scheduleEditorKey('compound-creatine')),
        findsNothing,
      );

      await _openSchedule(tester, 'compound-creatine');
      expect(find.text('Creatine Schedule'), findsOneWidget);
    });

    testWidgets(
        'creating a Protocol with a Compound left at "No schedule" saves a '
        'null Schedule, an ongoing course and no Period', (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(tester, controller, compounds: _compounds());
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      await tester.enterText(
        find.byKey(ProtocolFormScreen.nameFieldKey),
        'Lean bulk',
      );
      await _addMembers(tester, <String>['compound-creatine']);
      await _openSchedule(tester, 'compound-creatine');
      await _tap(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleRuleChipKey(
            'compound-creatine',
            ProtocolScheduleRuleChoice.none,
          ),
        ),
      );
      await _closeSheet(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      final draft = controller.createdDrafts.single;
      expect(draft.schedulesByCompoundId['compound-creatine'], isNull);
      expect(draft.endLocalDate, isNull);
      expect(draft.period, isNull);
      expect(draft.remindersEnabled, isFalse);
    });

    testWidgets(
        'a timed Schedule saves its daily times and the planned amount, with '
        'the Compound\'s default unit and route', (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(tester, controller, compounds: _compounds());
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      await tester.enterText(
        find.byKey(ProtocolFormScreen.nameFieldKey),
        'Daily',
      );
      await _addMembers(tester, <String>['compound-creatine']);
      await _openSchedule(tester, 'compound-creatine');
      // A new timed Schedule starts every day, with one time to edit.
      expect(
        _daysChip(
          tester,
          'compound-creatine',
          ProtocolScheduleDaysChoice.daily,
        ).selected,
        isTrue,
      );
      expect(find.text('9:00 AM'), findsOneWidget);

      await _enterText(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleAmountFieldKey('compound-creatine'),
        ),
        '5',
      );
      await _closeSheet(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      final schedule = controller
          .createdDrafts.single.schedulesByCompoundId['compound-creatine']!;
      final rule = schedule.rule as TimedScheduleRule;
      expect(rule.days, isA<DailyScheduleDays>());
      expect(rule.times, <String>['09:00']);
      expect(schedule.doseAmountEntered, '5');
      expect(schedule.doseAmountValue, 5);
      expect(schedule.doseUnit, DoseUnit.gram);
      expect(schedule.route, DoseRoute.oral);
    });

    testWidgets(
        'adding and removing times keeps the list sorted, as it is stored',
        (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _leanBulkStackWithSchedule(),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );
      await _openSchedule(tester, 'compound-creatine');

      await _tap(
        tester,
        find.byKey(ProtocolFormScreen.scheduleAddTimeKey('compound-creatine')),
      );
      // The picker suggests an hour after the last time.
      await _tap(tester, find.text('OK'));
      expect(find.text('9:00 AM'), findsOneWidget);
      expect(find.text('10:00 AM'), findsOneWidget);

      await _tap(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleRemoveTimeKey('compound-creatine', 0),
        ),
      );
      expect(find.text('9:00 AM'), findsNothing);
      await _closeSheet(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      final rule = controller
          .editedDrafts
          .single
          .schedulesByCompoundId['compound-creatine']!
          .rule as TimedScheduleRule;
      expect(rule.times, <String>['10:00']);
    });

    testWidgets(
        'an untimed Schedule on chosen weekdays saves the weekdays sorted and '
        'its count', (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(
        tester,
        controller,
        // Starts Wednesday 2026-07-01.
        protocol: _leanBulkStack(),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );
      await _openSchedule(tester, 'compound-creatine');

      await _tap(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleRuleChipKey(
            'compound-creatine',
            ProtocolScheduleRuleChoice.untimed,
          ),
        ),
      );
      await _tap(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleDaysChipKey(
            'compound-creatine',
            ProtocolScheduleDaysChoice.weekdays,
          ),
        ),
      );
      // The start's weekday is offered first.
      expect(_weekdayChip(tester, 'compound-creatine', 3).selected, isTrue);
      await _tap(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleWeekdayChipKey('compound-creatine', 5),
        ),
      );
      await _tap(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleWeekdayChipKey('compound-creatine', 1),
        ),
      );
      await _enterText(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleCountFieldKey('compound-creatine'),
        ),
        '2',
      );
      await _enterText(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleAmountFieldKey('compound-creatine'),
        ),
        '3',
      );
      await _closeSheet(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      final rule = controller
          .editedDrafts
          .single
          .schedulesByCompoundId['compound-creatine']!
          .rule as UntimedScheduleRule;
      expect(rule.count, 2);
      expect((rule.days as WeekdayScheduleDays).weekdays, <int>[1, 3, 5]);
      // A member with no Schedule yet takes its Compound's defaults.
      final schedule = controller
          .editedDrafts.single.schedulesByCompoundId['compound-creatine']!;
      expect(schedule.doseUnit, DoseUnit.gram);
      expect(schedule.route, DoseRoute.oral);
    });

    testWidgets(
        'every N days counts from the start by default, and a start move '
        'carries a default anchor with it', (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _leanBulkStackWithSchedule(),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );
      await _openSchedule(tester, 'compound-creatine');

      await _tap(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleDaysChipKey(
            'compound-creatine',
            ProtocolScheduleDaysChoice.everyNDays,
          ),
        ),
      );
      await _enterText(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleEveryNFieldKey('compound-creatine'),
        ),
        '3',
      );
      expect(find.text('Jul 1, 2026 (the start date)'), findsOneWidget);
      await _closeSheet(tester);

      await _expandPeriod(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.startDateFieldKey));
      await _tap(tester, find.text('15'));
      await _tap(tester, find.text('OK'));
      await _openSchedule(tester, 'compound-creatine');
      expect(find.text('Jul 15, 2026 (the start date)'), findsOneWidget);

      await _closeSheet(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      final draft = controller.editedDrafts.single;
      expect(
        draft.startLocalDate,
        const ProtocolDayDate(year: 2026, month: 7, day: 15),
      );
      final days = (draft.schedulesByCompoundId['compound-creatine']!.rule
              as TimedScheduleRule)
          .days as EveryNDaysScheduleDays;
      expect(days.n, 3);
      expect(days.anchor, const ProtocolDayDate(year: 2026, month: 7, day: 15));
      expect(days.anchorIsDefault, isTrue);
    });

    testWidgets('"As needed" clears the amount, unit and route, and saves none',
        (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _leanBulkStackWithSchedule(),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );
      await _openSchedule(tester, 'compound-creatine');

      final amountField = find.byKey(
        ProtocolFormScreen.scheduleAmountFieldKey('compound-creatine'),
      );
      expect(amountField, findsOneWidget);
      await _tap(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleRuleChipKey(
            'compound-creatine',
            ProtocolScheduleRuleChoice.asNeeded,
          ),
        ),
      );
      expect(amountField, findsNothing);

      // Back to times: the old amount is gone, not silently kept.
      await _tap(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleRuleChipKey(
            'compound-creatine',
            ProtocolScheduleRuleChoice.timed,
          ),
        ),
      );
      expect(tester.widget<TextField>(amountField).controller?.text, isEmpty);
      await _tap(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleRuleChipKey(
            'compound-creatine',
            ProtocolScheduleRuleChoice.asNeeded,
          ),
        ),
      );
      await _closeSheet(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      final schedule = controller
          .editedDrafts.single.schedulesByCompoundId['compound-creatine']!;
      expect(schedule.rule, isA<AsNeededScheduleRule>());
      expect(schedule.doseAmountValue, isNull);
      expect(schedule.doseAmountEntered, isNull);
      expect(schedule.doseUnit, isNull);
      expect(schedule.route, isNull);
    });

    testWidgets(
        '"No schedule" on a member that had one saves a null Schedule — the '
        'repository records the clearing as a new version', (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _leanBulkStackWithSchedule(),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );
      await _openSchedule(tester, 'compound-creatine');

      await _tap(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleRuleChipKey(
            'compound-creatine',
            ProtocolScheduleRuleChoice.none,
          ),
        ),
      );
      expect(
        find.byKey(
          ProtocolFormScreen.scheduleAmountFieldKey('compound-creatine'),
        ),
        findsNothing,
      );
      await _closeSheet(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      expect(
        controller
            .editedDrafts.single.schedulesByCompoundId['compound-creatine'],
        isNull,
      );
    });

    testWidgets(
        'editing a Protocol pre-fills a member\'s current Schedule Version, '
        'and an untouched save sends it back unchanged', (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _leanBulkStackWithSchedule(),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );
      await _openSchedule(tester, 'compound-creatine');

      expect(
        _ruleChip(
          tester,
          'compound-creatine',
          ProtocolScheduleRuleChoice.timed,
        ).selected,
        isTrue,
      );
      expect(find.text('9:00 AM'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(
        find.byKey(
          ProtocolFormScreen.scheduleCurrentVersionKey('compound-creatine'),
        ),
        findsOneWidget,
      );

      await _closeSheet(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      final draft = controller.editedDrafts.single;
      final schedule = draft.schedulesByCompoundId['compound-creatine']!;
      expect(schedule.doseAmountEntered, '5');
      expect(schedule.doseUnit, DoseUnit.gram);
      expect(schedule.rule.toJson(), _creatineVersion().rule.toJson());
      // A member with no Schedule stays without one.
      expect(draft.schedulesByCompoundId['compound-vitamin-d'], isNull);
    });

    testWidgets(
        'the editor shows the current version, not the one in effect today, '
        'for a Protocol whose start is in the future', (tester) async {
      final controller = _FakeProtocolListController();
      const start = ProtocolDayDate(year: 2099, month: 1, day: 1);
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _protocol(
          start: start,
          members: <ProtocolMemberRecord>[
            ProtocolMemberRecord(
              id: 'member-1',
              compoundId: 'compound-creatine',
              position: 0,
              currentVersion: _version(
                effectiveFrom: start,
                rule: UntimedScheduleRule(
                  days: const DailyScheduleDays(),
                  count: 2,
                ),
              ),
            ),
          ],
        ),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );
      await _openSchedule(tester, 'compound-creatine');

      expect(
        _ruleChip(
          tester,
          'compound-creatine',
          ProtocolScheduleRuleChoice.untimed,
        ).selected,
        isTrue,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(
                ProtocolFormScreen.scheduleCountFieldKey('compound-creatine'),
              ),
            )
            .controller
            ?.text,
        '2',
      );
      expect(
        find.text('Current Schedule applies from Jan 1, 2099'),
        findsOneWidget,
      );
    });
  });

  group('validation', () {
    testWidgets(
        'a timed Schedule with no amount, and every N of 1, show inline '
        'rejects and block the save', (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _leanBulkStack(),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );
      await _openSchedule(tester, 'compound-creatine');

      await _tap(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleRuleChipKey(
            'compound-creatine',
            ProtocolScheduleRuleChoice.timed,
          ),
        ),
      );
      await _tap(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleDaysChipKey(
            'compound-creatine',
            ProtocolScheduleDaysChoice.everyNDays,
          ),
        ),
      );
      await _enterText(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleEveryNFieldKey('compound-creatine'),
        ),
        '1',
      );
      // Rejects wait for a save attempt, so a half-filled Schedule doesn't
      // open with errors.
      expect(
        find.byKey(
          ProtocolFormScreen.scheduleIssueKey(
            'compound-creatine',
            'amount_required',
          ),
        ),
        findsNothing,
      );

      await _closeSheet(tester);
      expect(
        find.byKey(ProtocolFormScreen.memberFixKey('compound-creatine')),
        findsNothing,
      );
      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      expect(controller.editedDrafts, isEmpty);
      expect(find.byKey(ProtocolFormScreen.errorTextKey), findsOneWidget);
      // The form says which member, and the sheet says what is wrong.
      expect(
        find.byKey(ProtocolFormScreen.memberFixKey('compound-creatine')),
        findsOneWidget,
      );
      await _openSchedule(tester, 'compound-creatine');
      expect(
        find.byKey(
          ProtocolFormScreen.scheduleIssueKey(
            'compound-creatine',
            'every_n_range',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ProtocolFormScreen.scheduleIssueKey(
            'compound-creatine',
            'amount_required',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Every N days takes a number from 2 to 365.'),
          findsOneWidget);

      // Fixing both lets the save through.
      await _enterText(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleEveryNFieldKey('compound-creatine'),
        ),
        '2',
      );
      await _enterText(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleAmountFieldKey('compound-creatine'),
        ),
        '5',
      );
      expect(
        find.byKey(
          ProtocolFormScreen.scheduleIssueKey(
            'compound-creatine',
            'amount_required',
          ),
        ),
        findsNothing,
      );
      await _closeSheet(tester);
      expect(
        find.byKey(ProtocolFormScreen.memberFixKey('compound-creatine')),
        findsNothing,
      );
      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));
      expect(controller.editedDrafts, hasLength(1));
    });

    testWidgets(
        'more than six times a day shows a warning at once, and still saves',
        (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _protocol(
          members: <ProtocolMemberRecord>[
            ProtocolMemberRecord(
              id: 'member-1',
              compoundId: 'compound-creatine',
              position: 0,
              currentVersion: _version(
                rule: TimedScheduleRule(
                  days: const DailyScheduleDays(),
                  times: const <String>[
                    '06:00',
                    '08:00',
                    '10:00',
                    '12:00',
                    '14:00',
                    '16:00',
                    '18:00',
                  ],
                ),
              ),
            ),
          ],
        ),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );
      await _openSchedule(tester, 'compound-creatine');

      expect(
        find.byKey(
          ProtocolFormScreen.scheduleIssueKey(
              'compound-creatine', 'times_many'),
        ),
        findsOneWidget,
      );
      await _closeSheet(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));
      expect(controller.editedDrafts, hasLength(1));
    });

    testWidgets(
        'an end before the start, a cycle with no lengths and a Pause outside '
        'the dates show their rejects under the Period', (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _protocol(
          start: const ProtocolDayDate(year: 2026, month: 9, day: 1),
          end: const ProtocolDayDate(year: 2026, month: 8, day: 31),
          period: ProtocolPeriod(
            pauses: const <ProtocolPause>[
              ProtocolPause(
                from: ProtocolDayDate(year: 2026, month: 8, day: 1),
                to: ProtocolDayDate(year: 2026, month: 8, day: 5),
              ),
            ],
          ),
          members: const <ProtocolMemberRecord>[
            ProtocolMemberRecord(
              id: 'member-1',
              compoundId: 'compound-creatine',
              position: 0,
            ),
          ],
        ),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      await _expandPeriod(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.cycleToggleKey));
      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      expect(controller.editedDrafts, isEmpty);
      for (final rule in <String>[
        'cycle_lengths',
        'bounds_order',
        'pause_bounds',
      ]) {
        expect(
          find.byKey(ProtocolFormScreen.periodIssueKey(rule)),
          findsOneWidget,
          reason: rule,
        );
      }
    });
  });

  group('Period', () {
    testWidgets(
        'a cycle saves its lengths, with the anchor defaulting to the start',
        (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _leanBulkStack(),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      await _expandPeriod(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.cycleToggleKey));
      await _enterText(
        tester,
        find.byKey(ProtocolFormScreen.cycleOnDaysFieldKey),
        '60',
      );
      await _enterText(
        tester,
        find.byKey(ProtocolFormScreen.cycleOffDaysFieldKey),
        '30',
      );
      expect(find.text('Jul 1, 2026 (the start date)'), findsOneWidget);
      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      final cycle = controller.editedDrafts.single.period!.cycle!;
      expect(cycle.onDays, 60);
      expect(cycle.offDays, 30);
      expect(cycle.anchor, const ProtocolDayDate(year: 2026, month: 7, day: 1));
      expect(cycle.anchorIsDefault, isTrue);
    });

    testWidgets('a cycle anchor the user picks stays when the start moves',
        (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _protocol(
          start: const ProtocolDayDate(year: 2026, month: 9, day: 1),
          period: ProtocolPeriod(
            cycle: ProtocolCycle(
              onDays: 60,
              offDays: 30,
              anchor: const ProtocolDayDate(year: 2026, month: 9, day: 1),
              anchorIsDefault: true,
            ),
          ),
        ),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      await _expandPeriod(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.cycleAnchorFieldKey));
      await _tap(tester, find.text('10'));
      await _tap(tester, find.text('OK'));
      expect(find.text('Sep 10, 2026'), findsOneWidget);

      await _tap(tester, find.byKey(ProtocolFormScreen.startDateFieldKey));
      await _tap(tester, find.text('5'));
      await _tap(tester, find.text('OK'));
      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      final draft = controller.editedDrafts.single;
      expect(
        draft.startLocalDate,
        const ProtocolDayDate(year: 2026, month: 9, day: 5),
      );
      final cycle = draft.period!.cycle!;
      expect(
          cycle.anchor, const ProtocolDayDate(year: 2026, month: 9, day: 10));
      expect(cycle.anchorIsDefault, isFalse);
    });

    testWidgets(
        'a default anchor whose stored date is an old start shows the '
        'current start', (tester) async {
      // D4: a default anchor is read as the start, whatever date it stores.
      // After a start move from 2026-09-01 to 2026-09-05, nothing rewrote
      // the stored anchors, so they still hold the old start.
      const oldStart = ProtocolDayDate(year: 2026, month: 9, day: 1);
      const start = ProtocolDayDate(year: 2026, month: 9, day: 5);
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _protocol(
          start: start,
          period: ProtocolPeriod(
            cycle: ProtocolCycle(
              onDays: 3,
              offDays: 2,
              anchor: oldStart,
              anchorIsDefault: true,
            ),
          ),
          members: <ProtocolMemberRecord>[
            ProtocolMemberRecord(
              id: 'member-1',
              compoundId: 'compound-creatine',
              position: 0,
              currentVersion: _version(
                effectiveFrom: oldStart,
                rule: TimedScheduleRule(
                  days: EveryNDaysScheduleDays(
                    n: 3,
                    anchor: oldStart,
                    anchorIsDefault: true,
                  ),
                  times: const <String>['09:00'],
                ),
              ),
            ),
          ],
        ),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );
      await _expandPeriod(tester);
      await _openSchedule(tester, 'compound-creatine');

      expect(
        find.text('Sep 5, 2026 (the start date)', skipOffstage: false),
        findsNWidgets(2),
      );
      // The old start shows only as the date the version applies from.
      expect(
        find.text('Sep 1, 2026 (the start date)', skipOffstage: false),
        findsNothing,
      );

      await _closeSheet(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      final draft = controller.editedDrafts.single;
      final cycle = draft.period!.cycle!;
      expect(cycle.anchor, start);
      expect(cycle.anchorIsDefault, isTrue);
      final days = (draft.schedulesByCompoundId['compound-creatine']!.rule
              as TimedScheduleRule)
          .days as EveryNDaysScheduleDays;
      expect(days.anchor, start);
      expect(days.anchorIsDefault, isTrue);
    });

    testWidgets('the "N doses" helper turns 20 doses into an end date (CUJ 4)',
        (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _shoulderCourse(),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      await _expandPeriod(tester);
      expect(find.byKey(ProtocolFormScreen.endDateFieldKey), findsNothing);
      await _tap(tester, find.byKey(ProtocolFormScreen.doseCountHelperKey));
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(ProtocolFormScreen.doseCountApplyKey),
            )
            .onPressed,
        isNull,
      );
      await _enterText(
        tester,
        find.byKey(ProtocolFormScreen.doseCountFieldKey),
        '20',
      );
      expect(find.text('Ends Nov 14, 2026'), findsOneWidget);
      await _tap(tester, find.byKey(ProtocolFormScreen.doseCountApplyKey));

      expect(find.byKey(ProtocolFormScreen.endDateFieldKey), findsOneWidget);
      expect(find.text('Nov 14, 2026'), findsOneWidget);
      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      expect(
        controller.editedDrafts.single.endLocalDate,
        const ProtocolDayDate(year: 2026, month: 11, day: 14),
      );
    });

    testWidgets(
        'the "N doses" helper reads "Unavailable" for an as-needed member, '
        'and for a count out of range asks for 1 to 1000', (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _shoulderCourse(),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      await _openSchedule(tester, 'compound-bpc');
      await _tap(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleRuleChipKey(
            'compound-bpc',
            ProtocolScheduleRuleChoice.asNeeded,
          ),
        ),
      );
      await _closeSheet(tester);
      await _expandPeriod(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.doseCountHelperKey));
      await _enterText(
        tester,
        find.byKey(ProtocolFormScreen.doseCountFieldKey),
        '1001',
      );
      expect(find.text('Enter a number from 1 to 1000'), findsOneWidget);
      await _enterText(
        tester,
        find.byKey(ProtocolFormScreen.doseCountFieldKey),
        '20',
      );
      expect(find.text('Unavailable for this Schedule'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(ProtocolFormScreen.doseCountApplyKey),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('the "N doses" helper skips paused days', (tester) async {
      final controller = _FakeProtocolListController();
      final course = _shoulderCourse();
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _protocol(
          name: course.name,
          start: course.startLocalDate,
          members: course.members,
          period: ProtocolPeriod(
            pauses: const <ProtocolPause>[
              ProtocolPause(
                from: ProtocolDayDate(year: 2026, month: 10, day: 28),
                to: ProtocolDayDate(year: 2026, month: 10, day: 30),
              ),
            ],
          ),
        ),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      await _expandPeriod(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.doseCountHelperKey));
      await _enterText(
        tester,
        find.byKey(ProtocolFormScreen.doseCountFieldKey),
        '20',
      );
      // Three paused days push the 20th dose three days later.
      expect(find.text('Ends Nov 17, 2026'), findsOneWidget);
    });

    testWidgets('a Pause can be removed, and one can be added', (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _protocol(
          start: const ProtocolDayDate(year: 2026, month: 9, day: 1),
          period: ProtocolPeriod(
            pauses: const <ProtocolPause>[
              ProtocolPause(
                from: ProtocolDayDate(year: 2026, month: 10, day: 10),
                to: ProtocolDayDate(year: 2026, month: 10, day: 16),
              ),
            ],
          ),
        ),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      await _expandPeriod(tester);
      expect(find.text('Oct 10, 2026 – Oct 16, 2026'), findsOneWidget);
      await _tap(tester, find.byKey(ProtocolFormScreen.removePauseKey(0)));
      expect(find.byKey(ProtocolFormScreen.pauseRowKey(0)), findsNothing);

      await _tap(tester, find.byKey(ProtocolFormScreen.addPauseKey));
      await _tap(tester, find.byTooltip('Switch to input'));
      final rangeFields = find.descendant(
        of: find.byType(DateRangePickerDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(rangeFields.at(0), '11/02/2026');
      await tester.enterText(rangeFields.at(1), '11/04/2026');
      await _tap(tester, find.text('OK'));
      expect(find.text('Nov 2, 2026 – Nov 4, 2026'), findsOneWidget);

      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      final period = controller.editedDrafts.single.period!;
      expect(period.cycle, isNull);
      expect(period.pauses, hasLength(1));
      expect(
        period.pauses.single.from,
        const ProtocolDayDate(year: 2026, month: 11, day: 2),
      );
      expect(
        period.pauses.single.to,
        const ProtocolDayDate(year: 2026, month: 11, day: 4),
      );
    });

    testWidgets('tapping a Pause edits its dates', (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _protocol(
          start: const ProtocolDayDate(year: 2026, month: 9, day: 1),
          period: ProtocolPeriod(
            pauses: const <ProtocolPause>[
              ProtocolPause(
                from: ProtocolDayDate(year: 2026, month: 10, day: 10),
                to: ProtocolDayDate(year: 2026, month: 10, day: 16),
              ),
            ],
          ),
        ),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      await _expandPeriod(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.pauseRowKey(0)));
      await _tap(tester, find.byTooltip('Switch to input'));
      final rangeFields = find.descendant(
        of: find.byType(DateRangePickerDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(rangeFields.at(1), '10/12/2026');
      await _tap(tester, find.text('OK'));
      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      final pause = controller.editedDrafts.single.period!.pauses.single;
      expect(pause.from, const ProtocolDayDate(year: 2026, month: 10, day: 10));
      expect(pause.to, const ProtocolDayDate(year: 2026, month: 10, day: 12));
    });

    testWidgets('removing the only Pause, with no cycle, saves no Period',
        (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _protocol(
          start: const ProtocolDayDate(year: 2026, month: 9, day: 1),
          period: ProtocolPeriod(
            pauses: const <ProtocolPause>[
              ProtocolPause(
                from: ProtocolDayDate(year: 2026, month: 10, day: 10),
                to: ProtocolDayDate(year: 2026, month: 10, day: 16),
              ),
            ],
          ),
        ),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      await _expandPeriod(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.removePauseKey(0)));
      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      expect(controller.editedDrafts.single.period, isNull);
    });

    testWidgets(
        'turning "Until" on sets an end date, and the reminders flag is kept',
        (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _protocol(remindersEnabled: true),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      await _expandPeriod(tester);
      expect(find.text('Ongoing, with no end date'), findsOneWidget);
      await _tap(tester, find.byKey(ProtocolFormScreen.untilToggleKey));
      expect(find.byKey(ProtocolFormScreen.endDateFieldKey), findsOneWidget);
      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      final draft = controller.editedDrafts.single;
      expect(draft.endLocalDate, draft.startLocalDate);
      expect(draft.remindersEnabled, isTrue);
    });
  });

  testWidgets(
      'a Compound\'s Schedule fields are hidden until it is picked, and '
      'appear once selected — Target outcomes chips are hidden until Metrics '
      'load', (tester) async {
    final controller = _FakeProtocolListController();
    await _pumpFormScreen(
      tester,
      controller,
      compounds: _compounds(),
      metrics: _metrics(),
    );
    await _pumpUntilFound(tester, find.byKey(ProtocolFormScreen.nameFieldKey));

    expect(
      find.byKey(
        ProtocolFormScreen.targetOutcomeMetricChipKey('metric-weight'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(ProtocolFormScreen.targetOutcomePerformanceChipKey),
      findsOneWidget,
    );
  });

  testWidgets(
      'creating a Protocol: declaring a metric and the performance target '
      'outcome saves both', (tester) async {
    final controller = _FakeProtocolListController();
    await _pumpFormScreen(
      tester,
      controller,
      compounds: _compounds(),
      metrics: _metrics(),
      dayController: _FakeProtocolDayController(
        lastDoses: <String, ({double amount, DoseUnit unit})>{
          'compound-creatine': (amount: 5, unit: DoseUnit.gram),
        },
      ),
    );
    await _pumpUntilFound(tester, find.byKey(ProtocolFormScreen.nameFieldKey));

    await tester.enterText(
      find.byKey(ProtocolFormScreen.nameFieldKey),
      'Lean bulk',
    );
    await _addMembers(tester, <String>['compound-creatine']);
    await _tap(
      tester,
      find.byKey(
        ProtocolFormScreen.targetOutcomeMetricChipKey('metric-weight'),
      ),
    );
    await _tap(
      tester,
      find.byKey(ProtocolFormScreen.targetOutcomePerformanceChipKey),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.tap(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(controller.createdDrafts, hasLength(1));
    final outcomes = controller.createdDrafts.single.targetOutcomes;
    expect(outcomes, hasLength(2));
    expect(
      outcomes.map((o) => (o.kind, o.metricId)),
      containsAll(<(ProtocolOutcomeKind, String?)>[
        (ProtocolOutcomeKind.metric, 'metric-weight'),
        (ProtocolOutcomeKind.performance, null),
      ]),
    );
  });

  testWidgets(
      'creating a Protocol with no target outcomes selected saves an empty '
      'list — declaring them is optional', (tester) async {
    final controller = _FakeProtocolListController();
    await _pumpFormScreen(
      tester,
      controller,
      compounds: _compounds(),
      metrics: _metrics(),
      dayController: _FakeProtocolDayController(
        lastDoses: <String, ({double amount, DoseUnit unit})>{
          'compound-creatine': (amount: 5, unit: DoseUnit.gram),
        },
      ),
    );
    await _pumpUntilFound(tester, find.byKey(ProtocolFormScreen.nameFieldKey));

    await tester.enterText(
      find.byKey(ProtocolFormScreen.nameFieldKey),
      'Lean bulk',
    );
    await _addMembers(tester, <String>['compound-creatine']);

    await tester.ensureVisible(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.tap(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(controller.createdDrafts.single.targetOutcomes, isEmpty);
  });

  testWidgets(
      'editing a Protocol pre-selects its already-declared target outcomes',
      (tester) async {
    final controller = _FakeProtocolListController();
    await _pumpFormScreen(
      tester,
      controller,
      protocol: _leanBulkStackWithTargetOutcomes(),
      compounds: _compounds(),
      metrics: _metrics(),
    );
    await _pumpUntilFound(tester, find.byKey(ProtocolFormScreen.nameFieldKey));

    final metricChip = tester.widget<FilterChip>(
      find.byKey(
        ProtocolFormScreen.targetOutcomeMetricChipKey('metric-weight'),
      ),
    );
    expect(metricChip.selected, isTrue);
    final performanceChip = tester.widget<FilterChip>(
      find.byKey(ProtocolFormScreen.targetOutcomePerformanceChipKey),
    );
    expect(performanceChip.selected, isFalse);

    await tester.ensureVisible(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.tap(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    final outcomes = controller.editedDrafts.single.targetOutcomes;
    expect(outcomes, hasLength(1));
    expect(outcomes.single.kind, ProtocolOutcomeKind.metric);
    expect(outcomes.single.metricId, 'metric-weight');
  });

  group('Member rows (D5)', () {
    testWidgets(
        'CUJ 1: a Compound created in the picker joins the form, the name '
        'stays, and the rows summarize both', (tester) async {
      final controller = _FakeProtocolListController();
      final day = _FakeProtocolDayController(
        lastDoses: <String, ({double amount, DoseUnit unit})>{
          'compound-melatonin': (amount: 3, unit: DoseUnit.milligram),
        },
      );
      await _pumpFormScreen(
        tester,
        controller,
        compounds: <CompoundRecord>[_melatonin()],
        dayController: day,
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      await tester.enterText(
        find.byKey(ProtocolFormScreen.nameFieldKey),
        'Sleep stack',
      );
      await _tap(tester, find.byKey(ProtocolFormScreen.addCompoundsKey));
      await tester.tap(
        find.byKey(
          CompoundPickerSheet.rowKey(
            CompoundPickerSection.all,
            'compound-melatonin',
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(CompoundPickerSheet.searchFieldKey),
        'Glyc',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CompoundPickerSheet.createRowKey));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(CompoundEditorSheet.nameFieldKey),
        'Glycine',
      );
      await tester.tap(find.byKey(CompoundEditorSheet.unitFieldKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('g').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CompoundEditorSheet.saveButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CompoundPickerSheet.doneButtonKey));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(ProtocolFormScreen.nameFieldKey))
            .controller
            ?.text,
        'Sleep stack',
      );
      expect(_memberIds(tester), <String>['compound-melatonin', 'created-1']);
      expect(
        _rowText('compound-melatonin', 'Melatonin'),
        findsOneWidget,
      );
      expect(
        _rowText('compound-melatonin', 'Every day · 9:00 AM · 3 mg'),
        findsOneWidget,
      );
      expect(_rowText('created-1', 'Glycine'), findsOneWidget);
      expect(
        _rowText('created-1', 'Every day · 9:00 AM · Add an amount'),
        findsOneWidget,
      );
      // Only the Compounds new to this form were looked up, once.
      expect(
        day.requestedLastDoseIds.single,
        <String>{'compound-melatonin', 'created-1'},
      );
      expect(day.created.single.name, 'Glycine');
      expect(day.created.single.defaultUnit, DoseUnit.gram);
    });

    testWidgets(
        'CUJ 2: one Schedule sheet at a time, the row follows it live, and '
        'closing it keeps the changes', (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(
        tester,
        controller,
        compounds: <CompoundRecord>[_melatonin(), _glycine()],
        dayController: _FakeProtocolDayController(
          lastDoses: <String, ({double amount, DoseUnit unit})>{
            'compound-melatonin': (amount: 3, unit: DoseUnit.milligram),
          },
        ),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );
      await tester.enterText(
        find.byKey(ProtocolFormScreen.nameFieldKey),
        'Sleep stack',
      );
      await _addMembers(
        tester,
        <String>['compound-melatonin', 'compound-glycine'],
      );

      await _openSchedule(tester, 'compound-glycine');
      expect(
        find.byKey(ProtocolFormScreen.scheduleEditorKey('compound-melatonin')),
        findsNothing,
      );

      // 22:00, through the picker's text input.
      await _tap(
        tester,
        find.byKey(ProtocolFormScreen.scheduleTimeKey('compound-glycine', 0)),
      );
      await tester.tap(find.byTooltip('Switch to text input mode'));
      await tester.pumpAndSettle();
      final timeFields = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(timeFields.at(0), '10');
      await tester.enterText(timeFields.at(1), '00');
      await tester.tap(find.text('PM'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        _rowText('compound-glycine', 'Every day · 10:00 PM · Add an amount'),
        findsOneWidget,
      );

      await _enterText(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleAmountFieldKey('compound-glycine'),
        ),
        '3',
      );
      // The row under the open sheet has already changed.
      expect(
        _rowText('compound-glycine', 'Every day · 10:00 PM · 3 g'),
        findsOneWidget,
      );

      await _closeSheet(tester);
      expect(
        find.byKey(ProtocolFormScreen.scheduleEditorKey('compound-glycine')),
        findsNothing,
      );
      expect(
        _rowText('compound-glycine', 'Every day · 10:00 PM · 3 g'),
        findsOneWidget,
      );

      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));
      final schedule = controller
          .createdDrafts.single.schedulesByCompoundId['compound-glycine']!;
      expect((schedule.rule as TimedScheduleRule).times, <String>['22:00']);
      expect(schedule.doseAmountEntered, '3');
      expect(schedule.doseUnit, DoseUnit.gram);
    });

    testWidgets(
        'a missing amount turns the error color, and the row says to fix its '
        'Schedule, once a save was tried', (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(tester, controller, compounds: _compounds());
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );
      await tester.enterText(
        find.byKey(ProtocolFormScreen.nameFieldKey),
        'Lean bulk',
      );
      await _addMembers(tester, <String>['compound-creatine']);

      final summary = _rowText(
        'compound-creatine',
        'Every day · 9:00 AM · Add an amount',
      );
      Color? amountColor() {
        final span = tester.widget<Text>(summary).textSpan! as TextSpan;
        return (span.children?.last as TextSpan?)?.style?.color;
      }

      expect(amountColor(), isNull);
      expect(
        find.byKey(ProtocolFormScreen.memberFixKey('compound-creatine')),
        findsNothing,
      );

      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      expect(controller.createdDrafts, isEmpty);
      final error = Theme.of(
        tester.element(find.byType(ProtocolFormScreen)),
      ).colorScheme.error;
      expect(amountColor(), error);
      expect(
        tester
            .widget<Text>(
              find.byKey(ProtocolFormScreen.memberFixKey('compound-creatine')),
            )
            .style
            ?.color,
        error,
      );
      expect(find.text('Fix this Schedule'), findsOneWidget);

      // A sheet opened after the attempt shows the issue itself.
      await _openSchedule(tester, 'compound-creatine');
      expect(
        find.byKey(
          ProtocolFormScreen.scheduleIssueKey(
            'compound-creatine',
            'amount_required',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'CUJ 7: an archived member keeps its real name and place through the '
        'picker, and the Protocol still saves', (tester) async {
      final controller = _FakeProtocolListController();
      final day = _FakeProtocolDayController(
        lastDoses: <String, ({double amount, DoseUnit unit})>{
          'compound-bpc': (amount: 250, unit: DoseUnit.microgram),
        },
      );
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _protocol(
          name: 'Training days',
          members: <ProtocolMemberRecord>[
            ProtocolMemberRecord(
              id: 'member-1',
              compoundId: 'compound-creatine',
              position: 0,
              currentVersion: _creatineVersion(),
            ),
            ProtocolMemberRecord(
              id: 'member-2',
              compoundId: 'compound-caffeine',
              position: 1,
              currentVersion: _version(
                rule: TimedScheduleRule(
                  days: const DailyScheduleDays(),
                  times: const <String>['07:00'],
                ),
                amountEntered: '200',
                unit: DoseUnit.milligram,
              ),
            ),
            const ProtocolMemberRecord(
              id: 'member-3',
              compoundId: 'compound-vitamin-d',
              position: 2,
            ),
          ],
        ),
        compounds: _compounds(),
        archivedCompounds: <CompoundScheduleOptionRecord>[_caffeine()],
        dayController: day,
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      expect(_rowText('compound-caffeine', 'Caffeine'), findsOneWidget);
      expect(_rowText('compound-caffeine', 'Archived'), findsOneWidget);
      expect(
        _rowText('compound-caffeine', 'Every day · 7:00 AM · 200 mg'),
        findsOneWidget,
      );
      expect(_rowText('compound-creatine', 'Archived'), findsNothing);

      await _tap(tester, find.byKey(ProtocolFormScreen.addCompoundsKey));
      // The picker never sees it, and counts only what it lists.
      expect(
        find.byKey(
          CompoundPickerSheet.rowKey(
            CompoundPickerSection.all,
            'compound-caffeine',
          ),
        ),
        findsNothing,
      );
      expect(find.text('Done · 2'), findsOneWidget);
      await tester.tap(
        find.byKey(
          CompoundPickerSheet.rowKey(
            CompoundPickerSection.all,
            'compound-vitamin-d',
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          CompoundPickerSheet.rowKey(CompoundPickerSection.all, 'compound-bpc'),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(CompoundPickerSheet.doneButtonKey));
      await tester.pumpAndSettle();

      expect(_memberIds(tester), <String>[
        'compound-creatine',
        'compound-caffeine',
        'compound-bpc',
      ]);
      expect(_rowText('compound-caffeine', 'Archived'), findsOneWidget);

      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      final draft = controller.editedDrafts.single;
      expect(draft.compoundIds, <String>[
        'compound-creatine',
        'compound-caffeine',
        'compound-bpc',
      ]);
      final caffeine = draft.schedulesByCompoundId['compound-caffeine']!;
      expect(caffeine.doseAmountEntered, '200');
      expect((caffeine.rule as TimedScheduleRule).times, <String>['07:00']);
    });

    testWidgets('the "N doses" helper names an archived member', (
      tester,
    ) async {
      await _pumpFormScreen(
        tester,
        _FakeProtocolListController(),
        protocol: _protocol(
          members: const <ProtocolMemberRecord>[
            ProtocolMemberRecord(
              id: 'member-1',
              compoundId: 'compound-caffeine',
              position: 0,
            ),
          ],
        ),
        compounds: _compounds(),
        archivedCompounds: <CompoundScheduleOptionRecord>[_caffeine()],
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      await _expandPeriod(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.doseCountHelperKey));

      expect(
        find.descendant(
          of: find.byKey(ProtocolFormScreen.doseCountMemberFieldKey),
          matching: find.text('Caffeine'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'a row stays blank while its Compound loads, and says "Compound" only '
        'once the read found nothing', (tester) async {
      final answer = StreamController<List<CompoundScheduleOptionRecord>>();
      addTearDown(answer.close);
      await _pumpFormScreen(
        tester,
        _FakeProtocolListController(),
        protocol: _protocol(),
        compounds: _compounds(),
        compoundsByIds: answer.stream,
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      expect(_rowText('compound-creatine', 'Compound'), findsNothing);

      answer.add(const <CompoundScheduleOptionRecord>[]);
      await tester.pump();
      await tester.pump();

      expect(_rowText('compound-creatine', 'Compound'), findsOneWidget);
    });

    testWidgets(
        'closes the Schedule sheet when the app locks, with no exception', (
      tester,
    ) async {
      final lock = _SwitchableLockController();
      await _pumpFormScreen(
        tester,
        _FakeProtocolListController(),
        protocol: _leanBulkStackWithSchedule(),
        compounds: _compounds(),
        lock: lock,
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );
      await _openSchedule(tester, 'compound-creatine');
      // Focused, so the amount's controller is bound and listening.
      await _enterText(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleAmountFieldKey('compound-creatine'),
        ),
        '6',
      );

      lock.set(ProtocolsLockStatus.locked);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(ProtocolFormScreen.scheduleEditorKey('compound-creatine')),
        findsNothing,
      );
      expect(find.text('Creatine Schedule'), findsNothing);
      expect(find.byKey(ProtocolsLockGate.lockScreenKey), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  group('locking while Add Compounds reads', () {
    Future<_SwitchableLockController> pickCreatine(
      WidgetTester tester, {
      required _FakeProtocolDayController day,
      Stream<List<CompoundScheduleOptionRecord>>? compoundsByIds,
    }) async {
      final lock = _SwitchableLockController();
      await _pumpFormScreen(
        tester,
        _FakeProtocolListController(),
        compounds: _compounds(),
        dayController: day,
        compoundsByIds: compoundsByIds,
        lock: lock,
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );
      await _tap(tester, find.byKey(ProtocolFormScreen.addCompoundsKey));
      await tester.tap(
        find.byKey(
          CompoundPickerSheet.rowKey(
            CompoundPickerSection.all,
            'compound-creatine',
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(CompoundPickerSheet.doneButtonKey));
      await tester.pumpAndSettle();
      return lock;
    }

    testWidgets('the latest Doses: stops, with no exception', (tester) async {
      final answer = Completer<void>();
      final day = _FakeProtocolDayController()..lastDosesGate = answer.future;
      final lock = await pickCreatine(tester, day: day);
      expect(day.requestedLastDoseIds, hasLength(1));

      lock.set(ProtocolsLockStatus.locked);
      await tester.pump();
      answer.complete();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(ProtocolsLockGate.lockScreenKey), findsOneWidget);
    });

    testWidgets('the new Compounds: stops, with no exception', (tester) async {
      final answer =
          StreamController<List<CompoundScheduleOptionRecord>>.broadcast();
      addTearDown(answer.close);
      final lock = await pickCreatine(
        tester,
        day: _FakeProtocolDayController(),
        compoundsByIds: answer.stream,
      );

      lock.set(ProtocolsLockStatus.locked);
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(ProtocolsLockGate.lockScreenKey), findsOneWidget);
    });
  });

  group('the added-member default (D5)', () {
    Future<_FakeProtocolDayController> addCreatine(
      WidgetTester tester, {
      ({double amount, DoseUnit unit})? lastDose,
    }) async {
      final day = _FakeProtocolDayController(
        lastDoses: <String, ({double amount, DoseUnit unit})>{
          if (lastDose != null) 'compound-creatine': lastDose,
        },
      );
      await _pumpFormScreen(
        tester,
        _FakeProtocolListController(),
        compounds: _compounds(),
        dayController: day,
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );
      await _addMembers(tester, <String>['compound-creatine']);
      return day;
    }

    testWidgets(
        'starts at set times, every day at 9:00, in the default unit and '
        'route, with a matching last Dose\'s amount', (tester) async {
      await addCreatine(
        tester,
        lastDose: (amount: 5, unit: DoseUnit.gram),
      );

      expect(
        _rowText('compound-creatine', 'Every day · 9:00 AM · 5 g'),
        findsOneWidget,
      );

      await _openSchedule(tester, 'compound-creatine');
      expect(
        _ruleChip(
          tester,
          'compound-creatine',
          ProtocolScheduleRuleChoice.timed,
        ).selected,
        isTrue,
      );
      expect(
        _daysChip(
          tester,
          'compound-creatine',
          ProtocolScheduleDaysChoice.daily,
        ).selected,
        isTrue,
      );
      expect(find.text('9:00 AM'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(
                ProtocolFormScreen.scheduleAmountFieldKey('compound-creatine'),
              ),
            )
            .controller
            ?.text,
        '5',
      );
      expect(
        find.descendant(
          of: find.byKey(
            ProtocolFormScreen.scheduleRouteFieldKey('compound-creatine'),
          ),
          matching: find.text('Oral'),
        ),
        findsOneWidget,
      );
      // It is new, so there is no Schedule Version to name.
      expect(
        find.byKey(
          ProtocolFormScreen.scheduleCurrentVersionKey('compound-creatine'),
        ),
        findsNothing,
      );
    });

    testWidgets('keeps a fractional last amount as it is', (tester) async {
      await addCreatine(
        tester,
        lastDose: (amount: 2.5, unit: DoseUnit.gram),
      );

      expect(
        _rowText('compound-creatine', 'Every day · 9:00 AM · 2.5 g'),
        findsOneWidget,
      );
    });

    testWidgets('asks for an amount when the last Dose used another unit', (
      tester,
    ) async {
      await addCreatine(
        tester,
        lastDose: (amount: 5000, unit: DoseUnit.milligram),
      );

      expect(
        _rowText('compound-creatine', 'Every day · 9:00 AM · Add an amount'),
        findsOneWidget,
      );
    });

    testWidgets('asks for an amount with no Dose yet', (tester) async {
      await addCreatine(tester);

      expect(
        _rowText('compound-creatine', 'Every day · 9:00 AM · Add an amount'),
        findsOneWidget,
      );
    });

    testWidgets('"No schedule" is one tap away in the sheet', (tester) async {
      await addCreatine(tester);

      await _openSchedule(tester, 'compound-creatine');
      await _tap(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleRuleChipKey(
            'compound-creatine',
            ProtocolScheduleRuleChoice.none,
          ),
        ),
      );

      expect(_rowText('compound-creatine', 'No schedule'), findsOneWidget);
    });

    testWidgets(
        'a member with no Schedule Version keeps "No schedule", also after '
        'removing and re-adding it', (tester) async {
      final day = _FakeProtocolDayController(
        lastDoses: <String, ({double amount, DoseUnit unit})>{
          'compound-vitamin-d': (
            amount: 1000,
            unit: DoseUnit.internationalUnit,
          ),
        },
      );
      await _pumpFormScreen(
        tester,
        _FakeProtocolListController(),
        protocol: _leanBulkStackWithSchedule(),
        compounds: _compounds(),
        dayController: day,
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      expect(_rowText('compound-vitamin-d', 'No schedule'), findsOneWidget);

      await _tap(
        tester,
        find.byKey(ProtocolFormScreen.removeMemberKey('compound-vitamin-d')),
      );
      expect(
        find.byKey(ProtocolFormScreen.memberRowKey('compound-vitamin-d')),
        findsNothing,
      );
      await _addMembers(tester, <String>['compound-vitamin-d']);

      expect(_rowText('compound-vitamin-d', 'No schedule'), findsOneWidget);
      expect(day.requestedLastDoseIds, isEmpty);
    });

    testWidgets(
        'a member with a Schedule Version gets it back after removing and '
        're-adding it', (tester) async {
      await _pumpFormScreen(
        tester,
        _FakeProtocolListController(),
        protocol: _leanBulkStackWithSchedule(),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      await _tap(
        tester,
        find.byKey(ProtocolFormScreen.removeMemberKey('compound-creatine')),
      );
      await _addMembers(tester, <String>['compound-creatine']);

      // Back in the order the picker returned it: after the member kept.
      expect(
        _memberIds(tester),
        <String>['compound-vitamin-d', 'compound-creatine'],
      );
      expect(
        _rowText('compound-creatine', 'Every day · 9:00 AM · 5 g'),
        findsOneWidget,
      );
      await _openSchedule(tester, 'compound-creatine');
      expect(
        find.byKey(
          ProtocolFormScreen.scheduleCurrentVersionKey('compound-creatine'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('dismissing the picker changes nothing', (tester) async {
      await _pumpFormScreen(
        tester,
        _FakeProtocolListController(),
        protocol: _leanBulkStackWithSchedule(),
        compounds: _compounds(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      await _tap(tester, find.byKey(ProtocolFormScreen.addCompoundsKey));
      await tester.tap(
        find.byKey(
          CompoundPickerSheet.rowKey(
            CompoundPickerSection.all,
            'compound-creatine',
          ),
        ),
      );
      await tester.pump();
      await _closeSheet(tester);

      expect(
        _memberIds(tester),
        <String>['compound-creatine', 'compound-vitamin-d'],
      );
    });
  });

  group('the When section (D5)', () {
    final now = DateTime(2026, 11, 6);
    const nov4 = ProtocolDayDate(year: 2026, month: 11, day: 4);
    const dec31 = ProtocolDayDate(year: 2026, month: 12, day: 31);
    final summary = find.byKey(ProtocolFormScreen.periodSummaryKey);

    Future<void> openWith(WidgetTester tester, ProtocolRecord protocol) async {
      await _pumpFormScreen(
        tester,
        _FakeProtocolListController(),
        protocol: protocol,
        compounds: _compounds(),
        now: now,
      );
      await _pumpUntilFound(tester, summary);
    }

    Finder summaryText(String text) =>
        find.descendant(of: summary, matching: find.text(text));

    const twoPauses = <ProtocolPause>[
      ProtocolPause(
        from: ProtocolDayDate(year: 2026, month: 11, day: 10),
        to: ProtocolDayDate(year: 2026, month: 11, day: 12),
      ),
      ProtocolPause(
        from: ProtocolDayDate(year: 2026, month: 12, day: 1),
        to: ProtocolDayDate(year: 2026, month: 12, day: 2),
      ),
    ];

    testWidgets('an ongoing Protocol reads its start and Ongoing', (
      tester,
    ) async {
      await openWith(tester, _protocol(start: nov4));
      expect(summaryText('Starts Nov 4 · Ongoing'), findsOneWidget);
    });

    testWidgets('a full period reads its end, cycle and Pauses', (
      tester,
    ) async {
      await openWith(
        tester,
        _protocol(
          start: nov4,
          end: dec31,
          period: ProtocolPeriod(
            cycle: ProtocolCycle(
              onDays: 5,
              offDays: 2,
              anchor: nov4,
              anchorIsDefault: true,
            ),
            pauses: twoPauses,
          ),
        ),
      );
      expect(
        summaryText('Starts Nov 4 · until Dec 31 · 5 on, 2 off · 2 Pauses'),
        findsOneWidget,
      );
    });

    testWidgets('one Pause is singular', (tester) async {
      await openWith(
        tester,
        _protocol(
          start: nov4,
          period: ProtocolPeriod(pauses: twoPauses.sublist(0, 1)),
        ),
      );
      expect(summaryText('Starts Nov 4 · Ongoing · 1 Pause'), findsOneWidget);
    });

    testWidgets('an end date before the clock\'s today reads Ended', (
      tester,
    ) async {
      await openWith(
        tester,
        _protocol(
          start: const ProtocolDayDate(year: 2026, month: 1, day: 1),
          end: const ProtocolDayDate(year: 2026, month: 11, day: 5),
          period: ProtocolPeriod(pauses: twoPauses),
        ),
      );
      expect(summaryText('Ended Nov 5'), findsOneWidget);
    });

    testWidgets('an end date of today has not ended yet', (tester) async {
      await openWith(
        tester,
        _protocol(
          start: nov4,
          end: const ProtocolDayDate(year: 2026, month: 11, day: 6),
        ),
      );
      expect(summaryText('Starts Nov 4 · until Nov 6'), findsOneWidget);
    });

    testWidgets(
        'it opens collapsed, is a 48 dp button with an expanded state, and '
        'shows the controls in place when tapped', (tester) async {
      final semantics = tester.ensureSemantics();
      await openWith(tester, _protocol(start: nov4));

      expect(find.byKey(ProtocolFormScreen.startDateFieldKey), findsNothing);
      expect(
        tester.getSize(summary).height,
        greaterThanOrEqualTo(AppDimens.touchTarget),
      );
      expect(
        tester.getSemantics(summary),
        isSemantics(
          label: 'Starts Nov 4 · Ongoing',
          isButton: true,
          hasTapAction: true,
          hasExpandedState: true,
          isExpanded: false,
        ),
      );

      await _tap(tester, summary);

      for (final key in <Key>[
        ProtocolFormScreen.startDateFieldKey,
        ProtocolFormScreen.untilToggleKey,
        ProtocolFormScreen.doseCountHelperKey,
        ProtocolFormScreen.cycleToggleKey,
        ProtocolFormScreen.addPauseKey,
      ]) {
        expect(find.byKey(key), findsOneWidget);
      }
      expect(
        tester.getSemantics(summary),
        isSemantics(hasExpandedState: true, isExpanded: true),
      );

      // The row follows the controls, and folds them away again.
      await _tap(tester, find.byKey(ProtocolFormScreen.untilToggleKey));
      expect(summaryText('Ended Nov 4'), findsOneWidget);
      await _tap(tester, summary);
      expect(find.byKey(ProtocolFormScreen.startDateFieldKey), findsNothing);
      semantics.dispose();
    });

    testWidgets('a save attempt that finds a period issue expands it', (
      tester,
    ) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(
        tester,
        controller,
        protocol: _protocol(
          start: const ProtocolDayDate(year: 2026, month: 9, day: 1),
          end: const ProtocolDayDate(year: 2026, month: 8, day: 31),
        ),
        compounds: _compounds(),
        now: now,
      );
      await _pumpUntilFound(tester, summary);
      final issue =
          find.byKey(ProtocolFormScreen.periodIssueKey('bounds_order'));
      expect(issue, findsNothing);

      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      expect(controller.editedDrafts, isEmpty);
      expect(find.byKey(ProtocolFormScreen.startDateFieldKey), findsOneWidget);
      expect(issue, findsOneWidget);
    });

    testWidgets('a save rejected only for a Schedule leaves it collapsed', (
      tester,
    ) async {
      await _pumpFormScreen(
        tester,
        _FakeProtocolListController(),
        compounds: _compounds(),
        now: now,
      );
      await _pumpUntilFound(tester, summary);
      await tester.enterText(
        find.byKey(ProtocolFormScreen.nameFieldKey),
        'Stack',
      );
      // An added member starts with no amount, which a save rejects.
      await _addMembers(tester, <String>['compound-creatine']);

      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      expect(
        find.byKey(ProtocolFormScreen.memberFixKey('compound-creatine')),
        findsOneWidget,
      );
      expect(find.byKey(ProtocolFormScreen.startDateFieldKey), findsNothing);
    });
  });

  group('unsaved changes (CUJ 3)', () {
    final dialog = find.byType(AlertDialog);
    final nameField = find.byKey(ProtocolFormScreen.nameFieldKey);

    Future<void> openNew(
      WidgetTester tester,
      _FakeProtocolListController controller, {
      _FakeProtocolDayController? dayController,
    }) async {
      await _pumpFormScreen(
        tester,
        controller,
        compounds: _compounds(),
        dayController: dayController,
        pushed: true,
      );
      await _pumpUntilFound(tester, nameField);
    }

    Future<void> openSaved(
      WidgetTester tester,
      _FakeProtocolListController controller, {
      ProtocolRecord? protocol,
      Stream<bool> Function()? hasHistory,
    }) async {
      await _pumpFormScreen(
        tester,
        controller,
        protocol: protocol ?? _leanBulkStackWithSchedule(),
        compounds: _compounds(),
        metrics: _metrics(),
        hasHistory: hasHistory,
        pushed: true,
      );
      await _pumpUntilFound(tester, nameField);
    }

    testWidgets(
        'a new Protocol with a name and a member asks, Keep editing returns '
        'to the form as it was, and Discard closes it', (tester) async {
      final controller = _FakeProtocolListController();
      await openNew(tester, controller);
      await tester.enterText(nameField, 'Sleep stack');
      await _addMembers(tester, <String>['compound-creatine']);

      await _pressBack(tester);

      expect(dialog, findsOneWidget);
      expect(find.text('Discard this Protocol?'), findsOneWidget);
      expect(find.text('Keep editing'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(find.byType(ProtocolFormScreen), findsOneWidget);

      await tester.tap(find.byKey(ProtocolFormScreen.discardKeepEditingKey));
      await tester.pumpAndSettle();

      expect(dialog, findsNothing);
      expect(
        tester.widget<TextField>(nameField).controller?.text,
        'Sleep stack',
      );
      expect(_memberIds(tester), <String>['compound-creatine']);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProtocolFormScreen.discardConfirmKey));
      await tester.pumpAndSettle();

      _expectFormClosed();
      expect(controller.createdDrafts, isEmpty);
    });

    testWidgets('a name alone is a change', (tester) async {
      await openNew(tester, _FakeProtocolListController());
      await tester.enterText(nameField, 'Sleep stack');
      await tester.pump();

      await _pressBack(tester);

      expect(find.text('Discard this Protocol?'), findsOneWidget);
    });

    testWidgets('editing a saved Protocol asks with its own title', (
      tester,
    ) async {
      await openSaved(tester, _FakeProtocolListController());
      await tester.enterText(nameField, 'Renamed');
      await tester.pump();

      await _pressBack(tester);

      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.text('Discard this Protocol?'), findsNothing);
    });

    testWidgets('every other input counts as a change', (tester) async {
      final edits = <String, Future<void> Function()>{
        'a Schedule amount': () async {
          await _openSchedule(tester, 'compound-creatine');
          await _enterText(
            tester,
            find.byKey(
              ProtocolFormScreen.scheduleAmountFieldKey('compound-creatine'),
            ),
            '6',
          );
          await _closeSheet(tester);
        },
        'the period': () async {
          await _expandPeriod(tester);
          await _tap(tester, find.byKey(ProtocolFormScreen.untilToggleKey));
        },
        'a cycle': () async {
          await _expandPeriod(tester);
          await _tap(tester, find.byKey(ProtocolFormScreen.cycleToggleKey));
        },
        'a target outcome': () async {
          await _tap(
            tester,
            find.byKey(ProtocolFormScreen.targetOutcomePerformanceChipKey),
          );
        },
        'removing a member': () async {
          await _tap(
            tester,
            find.byKey(
                ProtocolFormScreen.removeMemberKey('compound-vitamin-d')),
          );
        },
      };
      for (final MapEntry(key: label, value: edit) in edits.entries) {
        await openSaved(tester, _FakeProtocolListController());
        await edit();
        await _pressBack(tester);
        expect(find.text('Discard changes?'), findsOneWidget, reason: label);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('a form with no changes closes without asking', (
      tester,
    ) async {
      await openNew(tester, _FakeProtocolListController());
      await _pressBack(tester);
      _expectFormClosed();

      await tester.pumpWidget(const SizedBox.shrink());
      // A Schedule, a default anchor and a stored unit all compare equal to
      // what the form opened with.
      await openSaved(tester, _FakeProtocolListController());
      await _pressBack(tester);
      _expectFormClosed();
    });

    testWidgets('adding a member and removing it again is no change', (
      tester,
    ) async {
      await openNew(tester, _FakeProtocolListController());
      await _addMembers(tester, <String>['compound-creatine']);
      await _tap(
        tester,
        find.byKey(ProtocolFormScreen.removeMemberKey('compound-creatine')),
      );

      await _pressBack(tester);

      _expectFormClosed();
    });

    testWidgets(
        'removing and re-adding a stored member with no Schedule is no change',
        (tester) async {
      await openSaved(
        tester,
        _FakeProtocolListController(),
        protocol: _leanBulkStack(),
      );
      await _tap(
        tester,
        find.byKey(ProtocolFormScreen.removeMemberKey('compound-vitamin-d')),
      );
      await _addMembers(tester, <String>['compound-vitamin-d']);

      await _pressBack(tester);

      _expectFormClosed();
    });

    testWidgets('turning a cycle on and off again is no change', (
      tester,
    ) async {
      await openNew(tester, _FakeProtocolListController());
      await _expandPeriod(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.cycleToggleKey));
      await _enterText(
        tester,
        find.byKey(ProtocolFormScreen.cycleOnDaysFieldKey),
        '5',
      );
      await _tap(tester, find.byKey(ProtocolFormScreen.cycleToggleKey));

      await _pressBack(tester);

      _expectFormClosed();
    });

    testWidgets('saving closes without asking', (tester) async {
      final controller = _FakeProtocolListController();
      await openSaved(tester, controller);
      await tester.enterText(nameField, 'Renamed');
      await tester.pump();

      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      expect(controller.editedDrafts.single.name, 'Renamed');
      _expectFormClosed();
    });

    testWidgets(
        'Back while a save runs does nothing, so the save closes the form and '
        'not a dialog', (tester) async {
      final controller = _FakeProtocolListController();
      final gate = Completer<void>();
      controller.createGate = gate.future;
      await openNew(tester, controller);
      await tester.enterText(nameField, 'Sleep stack');
      await _addMembers(tester, <String>['compound-creatine']);
      await _openSchedule(tester, 'compound-creatine');
      await _enterText(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleAmountFieldKey('compound-creatine'),
        ),
        '5',
      );
      await _closeSheet(tester);
      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      await _pressBack(tester);
      expect(dialog, findsNothing);
      expect(find.byType(ProtocolFormScreen), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      expect(controller.createdDrafts, hasLength(1));
      _expectFormClosed();
    });

    testWidgets('Archive closes a dirty form without asking', (tester) async {
      final controller = _FakeProtocolListController();
      await openSaved(tester, controller);
      await tester.enterText(nameField, 'Renamed');
      await tester.pump();
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.archiveButtonKey),
      );

      await _tap(tester, find.byKey(ProtocolFormScreen.archiveButtonKey));
      await tester.tap(find.byKey(ProtocolFormScreen.confirmArchiveButtonKey));
      await tester.pumpAndSettle();

      expect(controller.archivedProtocolIds, <String>['protocol-1']);
      _expectFormClosed();
    });

    testWidgets(
        'a Protocol already archived on another device closes a dirty form',
        (tester) async {
      final controller = _FakeProtocolListController()
        ..archiveError = StateError('Protocol is archived: protocol-1.');
      await openSaved(tester, controller);
      await tester.enterText(nameField, 'Renamed');
      await tester.pump();
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.archiveButtonKey),
      );

      await _tap(tester, find.byKey(ProtocolFormScreen.archiveButtonKey));
      await tester.tap(find.byKey(ProtocolFormScreen.confirmArchiveButtonKey));
      await tester.pumpAndSettle();

      _expectFormClosed();
    });

    testWidgets(
        'an archive that fails for another reason says why, and Back still '
        'asks before discarding', (tester) async {
      final controller = _FakeProtocolListController()
        ..archiveError = Exception('disk full');
      await openSaved(tester, controller);
      await tester.enterText(nameField, 'Renamed');
      await tester.pump();
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.archiveButtonKey),
      );

      await _tap(tester, find.byKey(ProtocolFormScreen.archiveButtonKey));
      await tester.tap(find.byKey(ProtocolFormScreen.confirmArchiveButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not archive the Protocol: Exception: disk full'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(ProtocolFormScreen.archiveButtonKey),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(ProtocolFormScreen.saveButtonKey),
            )
            .onPressed,
        isNotNull,
      );

      await _pressBack(tester);
      await tester.tap(find.byKey(ProtocolFormScreen.discardConfirmKey));
      await tester.pumpAndSettle();
      _expectFormClosed();
    });

    testWidgets('Delete closes a dirty form without asking', (tester) async {
      final controller = _FakeProtocolListController();
      await openSaved(
        tester,
        controller,
        hasHistory: () => Stream<bool>.value(false),
      );
      await tester.enterText(nameField, 'Renamed');
      await tester.pump();
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.deleteButtonKey),
      );

      await _tap(tester, find.byKey(ProtocolFormScreen.deleteButtonKey));
      await tester.tap(find.byKey(ProtocolFormScreen.confirmDeleteButtonKey));
      await tester.pumpAndSettle();

      expect(controller.deletedProtocolIds, <String>['protocol-1']);
      _expectFormClosed();
    });

    testWidgets('a Compound created in the picker survives Discard', (
      tester,
    ) async {
      final day = _FakeProtocolDayController();
      await openNew(tester, _FakeProtocolListController(), dayController: day);
      await _tap(tester, find.byKey(ProtocolFormScreen.addCompoundsKey));
      await tester.enterText(
        find.byKey(CompoundPickerSheet.searchFieldKey),
        'Glycine',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CompoundPickerSheet.createRowKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CompoundEditorSheet.saveButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CompoundPickerSheet.doneButtonKey));
      await tester.pumpAndSettle();
      expect(_memberIds(tester), <String>['created-1']);

      await _pressBack(tester);
      await tester.tap(find.byKey(ProtocolFormScreen.discardConfirmKey));
      await tester.pumpAndSettle();

      _expectFormClosed();
      expect(day.created.single.name, 'Glycine');
    });

    testWidgets('the dialog closes with the form when the app locks', (
      tester,
    ) async {
      final lock = _SwitchableLockController();
      await _pumpFormScreen(
        tester,
        _FakeProtocolListController(),
        compounds: _compounds(),
        lock: lock,
        pushed: true,
      );
      await _pumpUntilFound(tester, nameField);
      await tester.enterText(nameField, 'Sleep stack');
      await tester.pump();
      await _pressBack(tester);
      expect(dialog, findsOneWidget);

      lock.set(ProtocolsLockStatus.locked);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(dialog, findsNothing);
      expect(find.byType(ProtocolFormScreen), findsNothing);
    });
  });

  testWidgets('Protocol list meets accessibility guidelines in both themes',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();

      await _pumpListScreen(
        tester,
        _FakeProtocolListController(
          protocols: <ProtocolRecord>[_leanBulkStack()],
        ),
        theme: theme,
      );
      await _pumpUntilFound(tester, find.byKey(ProtocolListScreen.listKey));

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'Protocol form, its sheets and its dialog meet accessibility guidelines '
      'in both themes, at 320 dp and 1.3x text', (tester) async {
    Future<void> checkGuidelines() async {
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    }

    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    // Tall enough not to scroll: a row half under the app bar reads as a small
    // tap target. A layout overflow at either size fails the test by itself.
    tester.view.devicePixelRatio = 1;
    for (final (width, textScale) in <(double, double)>[
      (800, 1),
      (320, 1.3),
    ]) {
      tester.view.physicalSize = Size(width, 2400);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        final semantics = tester.ensureSemantics();

        await _pumpFormScreen(
          tester,
          _FakeProtocolListController(),
          theme: theme,
          // A member WITH a timed Schedule, a cycle and a Pause, so the rule,
          // time, Period and Pause controls are exercised by the guideline
          // checks too, plus a selected target outcome so its chip is
          // exercised too.
          protocol: _accessibilityFixture(),
          compounds: _compounds(),
          metrics: _metrics(),
          pushed: true,
        );
        await _pumpUntilFound(
          tester,
          find.byKey(ProtocolFormScreen.saveButtonKey),
        );

        await checkGuidelines();

        // The period controls live behind the When row.
        await _expandPeriod(tester);
        await checkGuidelines();

        // The rule and time controls live in the member's Schedule sheet.
        await _openSchedule(tester, 'compound-creatine');
        await checkGuidelines();
        await _closeSheet(tester);

        // The picker, and the Compound editor sheet it opens.
        await _tap(tester, find.byKey(ProtocolFormScreen.addCompoundsKey));
        await checkGuidelines();
        await tester.enterText(
          find.byKey(CompoundPickerSheet.searchFieldKey),
          'Glycine',
        );
        await tester.pumpAndSettle();
        await checkGuidelines();
        await tester.tap(find.byKey(CompoundPickerSheet.createRowKey));
        await tester.pumpAndSettle();
        await checkGuidelines();
        await _closeSheet(tester);
        await _closeSheet(tester);

        // The discard dialog.
        await tester.enterText(
          find.byKey(ProtocolFormScreen.nameFieldKey),
          'Renamed',
        );
        await tester.pump();
        await _pressBack(tester);
        expect(find.text('Discard changes?'), findsOneWidget);
        await checkGuidelines();

        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });
}

Future<void> _pumpListScreen(
  WidgetTester tester,
  _FakeProtocolListController controller, {
  ThemeData? theme,
  List<CompoundRecord> compounds = const <CompoundRecord>[],
  Map<String, String> compoundNames = const <String, String>{},
  bool hasHistory = true,
}) async {
  final memberIds = controller.protocols
      .expand((protocol) => protocol.members)
      .map((member) => member.compoundId);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        protocolListControllerProvider.overrideWith(() => controller),
        protocolHasHistoryProvider.overrideWith(
          (ref, protocolId) => Stream<bool>.value(hasHistory),
        ),
        compoundListProvider.overrideWith(
          (ref) => Stream<List<CompoundRecord>>.value(compounds),
        ),
        metricOptionListProvider.overrideWith(
          (ref) => Stream<List<MetricOptionRecord>>.value(
            const <MetricOptionRecord>[],
          ),
        ),
        protocolMemberCompoundNamesProvider(
          CompoundNameLookupRequest(memberIds),
        ).overrideWith(
          (ref) => Stream<Map<String, String>>.value(compoundNames),
        ),
        compoundsByIdsProvider.overrideWith(
          (ref, request) => Stream<List<CompoundScheduleOptionRecord>>.value(
            compounds
                .where((compound) => request.ids.contains(compound.id))
                .map(_compoundScheduleOptionFromCompound)
                .toList(growable: false),
          ),
        ),
        // The editor and the Effect view open behind `ProtocolsLockGate`; a
        // store with no lock keeps them off the secure-storage plugin.
        protocolsLockStoreProvider.overrideWith((ref) => _NoLockStore()),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ProtocolListScreen(),
      ),
    ),
  );
}

Future<void> _pumpFormScreen(
  WidgetTester tester,
  _FakeProtocolListController controller, {
  ThemeData? theme,
  ProtocolRecord? protocol,
  List<CompoundRecord> compounds = const <CompoundRecord>[],
  List<CompoundScheduleOptionRecord> archivedCompounds =
      const <CompoundScheduleOptionRecord>[],
  List<MetricRecord> metrics = const <MetricRecord>[],
  Stream<bool> Function()? hasHistory,
  _FakeProtocolDayController? dayController,
  Stream<List<CompoundScheduleOptionRecord>>? compoundsByIds,
  ProtocolsLockController? lock,
  DateTime? now,
  bool pushed = false,
}) async {
  final day = dayController ?? _FakeProtocolDayController();
  final form = ProtocolFormScreen(protocol: protocol);
  final screen = lock == null ? form : ProtocolsLockGate(child: form);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        protocolListControllerProvider.overrideWith(() => controller),
        // The editor's Archive or Delete (D8). A Protocol with history by
        // default, so the editor shows Archive as it did before D8.
        protocolHasHistoryProvider.overrideWith(
          (ref, protocolId) => hasHistory?.call() ?? Stream<bool>.value(true),
        ),
        metricOptionListProvider.overrideWith(
          (ref) => Stream<List<MetricOptionRecord>>.value(
            metrics.map(_metricOptionFromMetric).toList(growable: false),
          ),
        ),
        // The member rows, and a Compound created in the picker, read by id:
        // an archived Compound and a just-created one are only found this way.
        compoundsByIdsProvider.overrideWith(
          (ref, request) =>
              compoundsByIds ??
              Stream<List<CompoundScheduleOptionRecord>>.value(
                <CompoundScheduleOptionRecord>[
                  ...compounds.map(_compoundScheduleOptionFromCompound),
                  ...day.created.map(_compoundScheduleOptionFromCompound),
                  ...archivedCompounds,
                ]
                    .where((option) => request.ids.contains(option.id))
                    .toList(growable: false),
              ),
        ),
        // The picker's list, and Add Compounds' latest Doses.
        compoundListProvider.overrideWith(
          (ref) => Stream<List<CompoundRecord>>.value(compounds),
        ),
        recentCompoundIdsProvider.overrideWith(
          (ref) => Stream<List<String>>.value(const <String>[]),
        ),
        protocolDayControllerProvider.overrideWith(() => day),
        // The sheets sit behind `ProtocolsLockSheetGuard`; a store with no
        // lock keeps them off the secure-storage plugin.
        protocolsLockStoreProvider.overrideWith((ref) => _NoLockStore()),
        if (lock != null)
          protocolsLockControllerProvider.overrideWith(() => lock),
        if (now != null) protocolsClockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: pushed
            ? Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      key: _openFormKey,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => screen),
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              )
            : screen,
      ),
    ),
  );
  if (pushed) {
    await tester.tap(find.byKey(_openFormKey));
    await tester.pumpAndSettle();
  }
}

/// On the route under a form pumped with `pushed: true`.
const _openFormKey = Key('test.form.open');

/// Presses the system Back button and settles.
Future<void> _pressBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

/// The form was closed, with no discard dialog left in its place.
void _expectFormClosed() {
  expect(find.byType(ProtocolFormScreen), findsNothing);
  expect(find.byType(AlertDialog), findsNothing);
  expect(find.byKey(_openFormKey), findsOneWidget);
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 20,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Could not find $finder.');
}

/// Scrolls [finder] to the middle of its scroll view, so a tap lands inside
/// the screen however long the form grows. Settles first: text just entered
/// schedules a scroll that keeps its caret on screen, which would otherwise
/// undo this one.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(finder.evaluate().single, alignment: 0.5);
  await tester.pumpAndSettle();
}

/// Scrolls [finder] into view, taps it and settles.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enterText(WidgetTester tester, Finder finder, String text) async {
  await _reveal(tester, finder);
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

/// Opens the When section: the period's controls are collapsed when the form
/// opens.
Future<void> _expandPeriod(WidgetTester tester) async {
  await _tap(tester, find.byKey(ProtocolFormScreen.periodSummaryKey));
  expect(find.byKey(ProtocolFormScreen.startDateFieldKey), findsOneWidget);
}

/// Adds [compoundIds] through the picker, as the only way a form gains a member.
Future<void> _addMembers(WidgetTester tester, List<String> compoundIds) async {
  await _tap(tester, find.byKey(ProtocolFormScreen.addCompoundsKey));
  for (final compoundId in compoundIds) {
    await tester.tap(
      find.byKey(
        CompoundPickerSheet.rowKey(CompoundPickerSection.all, compoundId),
      ),
    );
    await tester.pump();
  }
  await tester.tap(find.byKey(CompoundPickerSheet.doneButtonKey));
  await tester.pumpAndSettle();
  for (final compoundId in compoundIds) {
    await _pumpUntilFound(
      tester,
      find.byKey(ProtocolFormScreen.memberRowKey(compoundId)),
    );
  }
}

/// Taps a member's row and waits for its Schedule sheet.
Future<void> _openSchedule(WidgetTester tester, String compoundId) async {
  await _tap(tester, find.byKey(ProtocolFormScreen.memberRowKey(compoundId)));
  expect(
    find.byKey(ProtocolFormScreen.scheduleEditorKey(compoundId)),
    findsOneWidget,
  );
}

/// Closes the sheet on top by tapping the strip of the screen above it.
Future<void> _closeSheet(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
}

/// [text] inside the row of member [compoundId], on or under an open sheet.
Finder _rowText(String compoundId, String text) {
  return find.descendant(
    of: find.byKey(ProtocolFormScreen.memberRowKey(compoundId)),
    matching: find.text(text),
  );
}

/// The member rows' Compound ids, top to bottom.
List<String> _memberIds(WidgetTester tester) {
  const prefix = 'protocols.form.member-';
  final rows = find
      .byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.startsWith(prefix);
      })
      .evaluate()
      .toList()
    ..sort((a, b) {
      final top = tester.getTopLeft(find.byWidget(a.widget)).dy;
      return top.compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy);
    });
  return <String>[
    for (final row in rows)
      (row.widget.key! as ValueKey<String>).value.substring(prefix.length),
  ];
}

ChoiceChip _ruleChip(
  WidgetTester tester,
  String compoundId,
  ProtocolScheduleRuleChoice choice,
) {
  return tester.widget<ChoiceChip>(
    find.byKey(ProtocolFormScreen.scheduleRuleChipKey(compoundId, choice)),
  );
}

ChoiceChip _daysChip(
  WidgetTester tester,
  String compoundId,
  ProtocolScheduleDaysChoice choice,
) {
  return tester.widget<ChoiceChip>(
    find.byKey(ProtocolFormScreen.scheduleDaysChipKey(compoundId, choice)),
  );
}

FilterChip _weekdayChip(WidgetTester tester, String compoundId, int weekday) {
  return tester.widget<FilterChip>(
    find.byKey(ProtocolFormScreen.scheduleWeekdayChipKey(compoundId, weekday)),
  );
}

List<CompoundRecord> _compounds() {
  return <CompoundRecord>[
    CompoundRecord(
      id: 'compound-creatine',
      name: 'Creatine',
      defaultUnit: DoseUnit.gram,
      defaultRoute: DoseRoute.oral,
      updatedAt: DateTime.utc(2026, 6, 30),
    ),
    CompoundRecord(
      id: 'compound-bpc',
      name: 'BPC-157',
      defaultUnit: DoseUnit.microgram,
      defaultRoute: DoseRoute.subcutaneous,
      updatedAt: DateTime.utc(2026, 6, 30),
    ),
    CompoundRecord(
      id: 'compound-vitamin-d',
      name: 'Vitamin D',
      defaultUnit: DoseUnit.internationalUnit,
      defaultRoute: DoseRoute.oral,
      strength: CompoundStrength.parse('1000 IU/capsule'),
      updatedAt: DateTime.utc(2026, 6, 30),
    ),
  ];
}

CompoundRecord _melatonin() {
  return CompoundRecord(
    id: 'compound-melatonin',
    name: 'Melatonin',
    defaultUnit: DoseUnit.milligram,
    defaultRoute: DoseRoute.oral,
    updatedAt: DateTime.utc(2026, 6, 30),
  );
}

CompoundRecord _glycine() {
  return CompoundRecord(
    id: 'compound-glycine',
    name: 'Glycine',
    defaultUnit: DoseUnit.gram,
    defaultRoute: DoseRoute.oral,
    updatedAt: DateTime.utc(2026, 6, 30),
  );
}

CompoundScheduleOptionRecord _caffeine() {
  return const CompoundScheduleOptionRecord(
    id: 'compound-caffeine',
    name: 'Caffeine',
    defaultUnit: DoseUnit.milligram,
    defaultRoute: DoseRoute.oral,
    isArchived: true,
  );
}

ProtocolRecord _leanBulkStack() {
  return ProtocolRecord(
    id: 'protocol-1',
    name: 'Lean bulk',
    startLocalDate: const ProtocolDayDate(year: 2026, month: 7, day: 1),
    updatedAt: DateTime.utc(2026, 7, 1),
    members: const <ProtocolMemberRecord>[
      ProtocolMemberRecord(
        id: 'member-1',
        compoundId: 'compound-creatine',
        position: 0,
      ),
      ProtocolMemberRecord(
        id: 'member-2',
        compoundId: 'compound-vitamin-d',
        position: 1,
      ),
    ],
  );
}

/// The same stack as [_leanBulkStack], but the Creatine member carries a
/// Schedule Version (daily at 09:00, 5 g oral): the pre-fill fixture for
/// edit-screen tests.
ProtocolRecord _leanBulkStackWithSchedule() {
  final stack = _leanBulkStack();
  return ProtocolRecord(
    id: stack.id,
    name: stack.name,
    startLocalDate: stack.startLocalDate,
    endLocalDate: stack.endLocalDate,
    updatedAt: stack.updatedAt,
    members: <ProtocolMemberRecord>[
      ProtocolMemberRecord(
        id: 'member-1',
        compoundId: 'compound-creatine',
        position: 0,
        currentVersion: _creatineVersion(),
        versionInEffectToday: _creatineVersion(),
      ),
      const ProtocolMemberRecord(
        id: 'member-2',
        compoundId: 'compound-vitamin-d',
        position: 1,
      ),
    ],
  );
}

ScheduleRecord _creatineVersion() {
  return _version(
    rule: TimedScheduleRule(
      days: const DailyScheduleDays(),
      times: const <String>['09:00'],
    ),
  );
}

ScheduleRecord _version({
  required ScheduleRule rule,
  ProtocolDayDate effectiveFrom =
      const ProtocolDayDate(year: 2026, month: 7, day: 1),
  String amountEntered = '5',
  DoseUnit unit = DoseUnit.gram,
  DoseRoute route = DoseRoute.oral,
}) {
  return ScheduleRecord(
    id: 'schedule-1',
    protocolCompoundId: 'member-1',
    effectiveFrom: effectiveFrom,
    rule: rule,
    doseAmountValue: double.parse(amountEntered),
    doseAmountEntered: amountEntered,
    doseUnit: unit,
    route: route,
    updatedAt: DateTime.utc(2026, 7, 1),
  );
}

/// A one-member Protocol for the Period and validation tests.
ProtocolRecord _protocol({
  String name = 'Skin',
  ProtocolDayDate start = const ProtocolDayDate(year: 2026, month: 7, day: 1),
  ProtocolDayDate? end,
  ProtocolPeriod? period,
  bool remindersEnabled = false,
  List<ProtocolMemberRecord> members = const <ProtocolMemberRecord>[
    ProtocolMemberRecord(
      id: 'member-1',
      compoundId: 'compound-creatine',
      position: 0,
    ),
  ],
}) {
  return ProtocolRecord(
    id: 'protocol-1',
    name: name,
    startLocalDate: start,
    endLocalDate: end,
    period: period,
    remindersEnabled: remindersEnabled,
    updatedAt: DateTime.utc(2026, 7, 1),
    members: members,
  );
}

/// CUJ 4: BPC-157 at 21:00 daily from 2026-10-26, with no end yet.
ProtocolRecord _shoulderCourse() {
  const start = ProtocolDayDate(year: 2026, month: 10, day: 26);
  return _protocol(
    name: 'Shoulder',
    start: start,
    members: <ProtocolMemberRecord>[
      ProtocolMemberRecord(
        id: 'member-1',
        compoundId: 'compound-bpc',
        position: 0,
        currentVersion: _version(
          effectiveFrom: start,
          rule: TimedScheduleRule(
            days: const DailyScheduleDays(),
            times: const <String>['21:00'],
          ),
          amountEntered: '250',
          unit: DoseUnit.microgram,
          route: DoseRoute.subcutaneous,
        ),
      ),
    ],
  );
}

ProtocolRecord _accessibilityFixture() {
  final stack = _leanBulkStackWithSchedule();
  return ProtocolRecord(
    id: stack.id,
    name: stack.name,
    startLocalDate: stack.startLocalDate,
    endLocalDate: const ProtocolDayDate(year: 2026, month: 12, day: 31),
    period: ProtocolPeriod(
      cycle: ProtocolCycle(
        onDays: 60,
        offDays: 30,
        anchor: stack.startLocalDate,
        anchorIsDefault: true,
      ),
      pauses: const <ProtocolPause>[
        ProtocolPause(
          from: ProtocolDayDate(year: 2026, month: 8, day: 10),
          to: ProtocolDayDate(year: 2026, month: 8, day: 16),
        ),
      ],
    ),
    updatedAt: stack.updatedAt,
    members: stack.members,
    targetOutcomes: const <ProtocolTargetOutcomeRecord>[
      ProtocolTargetOutcomeRecord(
        id: 'outcome-1',
        kind: ProtocolOutcomeKind.metric,
        metricId: 'metric-weight',
        position: 0,
      ),
    ],
  );
}

List<MetricRecord> _metrics() {
  return <MetricRecord>[
    MetricRecord(
      id: 'metric-weight',
      name: 'Body Weight',
      unit: 'kilogram',
      valueShape: MetricValueShape.scalar,
      group: MetricGroup.bodyComposition,
      enabled: true,
      pinned: false,
      sortOrder: 0,
      updatedAt: DateTime.utc(2026, 6, 30),
    ),
  ];
}

MetricOptionRecord _metricOptionFromMetric(MetricRecord metric) {
  return MetricOptionRecord(id: metric.id, name: metric.name);
}

CompoundScheduleOptionRecord _compoundScheduleOptionFromCompound(
  CompoundRecord compound,
) {
  return CompoundScheduleOptionRecord(
    id: compound.id,
    name: compound.name,
    defaultUnit: compound.defaultUnit,
    defaultRoute: compound.defaultRoute,
  );
}

/// The same stack as [_leanBulkStack], but declaring a `metric` target
/// outcome — the pre-fill fixture for edit-screen tests.
ProtocolRecord _leanBulkStackWithTargetOutcomes() {
  final stack = _leanBulkStack();
  return ProtocolRecord(
    id: stack.id,
    name: stack.name,
    startLocalDate: stack.startLocalDate,
    endLocalDate: stack.endLocalDate,
    updatedAt: stack.updatedAt,
    members: stack.members,
    targetOutcomes: const <ProtocolTargetOutcomeRecord>[
      ProtocolTargetOutcomeRecord(
        id: 'outcome-1',
        kind: ProtocolOutcomeKind.metric,
        metricId: 'metric-weight',
        position: 0,
      ),
    ],
  );
}

class _FakeProtocolListController extends ProtocolListController {
  _FakeProtocolListController({
    this.protocols = const <ProtocolRecord>[],
  });

  final List<ProtocolRecord> protocols;
  final createdDrafts = <ProtocolDraft>[];
  final editedProtocolIds = <String>[];
  final editedDrafts = <ProtocolDraft>[];
  final archivedProtocolIds = <String>[];
  final deletedProtocolIds = <String>[];

  /// When set, [createProtocol] answers only after this completes.
  Future<void>? createGate;

  /// Thrown by [archiveProtocol] instead of archiving, when set.
  Object? archiveError;

  /// Thrown by [deleteProtocol] instead of deleting, when set: the refusal
  /// the repository gives when a Dose made the Protocol history (D8).
  Object? deleteError;

  @override
  Stream<List<ProtocolSummaryRecord>> build() {
    return Stream<List<ProtocolSummaryRecord>>.value(
      protocols.map(_protocolSummaryFromProtocol).toList(growable: false),
    );
  }

  @override
  Future<CreateProtocolResult> createProtocol(ProtocolDraft draft) async {
    await createGate;
    createdDrafts.add(draft);
    return CreateProtocolResult(
      batchId: 'batch-${createdDrafts.length}',
      protocolId: 'created-${createdDrafts.length}',
    );
  }

  @override
  Future<String> editProtocol(String protocolId, ProtocolDraft draft) async {
    editedProtocolIds.add(protocolId);
    editedDrafts.add(draft);
    return 'batch-edit-${editedDrafts.length}';
  }

  @override
  Future<String> archiveProtocol(String protocolId) async {
    final error = archiveError;
    if (error != null) {
      throw error;
    }
    archivedProtocolIds.add(protocolId);
    return 'batch-archive-${archivedProtocolIds.length}';
  }

  @override
  Future<String> deleteProtocol(String protocolId) async {
    final error = deleteError;
    if (error != null) {
      throw error;
    }
    deletedProtocolIds.add(protocolId);
    return 'batch-delete-${deletedProtocolIds.length}';
  }

  @override
  Future<ProtocolRecord?> loadProtocolDetail(String protocolId) async {
    for (final protocol in protocols) {
      if (protocol.id == protocolId) {
        return protocol;
      }
    }
    return null;
  }
}

ProtocolSummaryRecord _protocolSummaryFromProtocol(ProtocolRecord protocol) {
  return ProtocolSummaryRecord(
    id: protocol.id,
    name: protocol.name,
    startLocalDate: protocol.startLocalDate,
    endLocalDate: protocol.endLocalDate,
    compoundIds: protocol.members
        .map((member) => member.compoundId)
        .toList(growable: false),
  );
}

/// The Protocols day controller as the editor and its picker use it: last Doses
/// from a map, and created Compounds kept for the by-id read to find.
class _FakeProtocolDayController extends ProtocolDayController {
  _FakeProtocolDayController({
    this.lastDoses = const <String, ({double amount, DoseUnit unit})>{},
  });

  final Map<String, ({double amount, DoseUnit unit})> lastDoses;
  final requestedLastDoseIds = <Set<String>>[];
  final created = <CompoundRecord>[];

  /// When set, the latest Doses answer only after this completes.
  Future<void>? lastDosesGate;

  @override
  Stream<ProtocolDayState> build() {
    return Stream<ProtocolDayState>.value(
      ProtocolDayState(
        day: ProtocolDayRecord(
          localDate: const ProtocolDayDate(year: 2026, month: 6, day: 30),
          doses: <DoseRecord>[],
        ),
      ),
    );
  }

  @override
  Future<Map<String, ({double amount, DoseUnit unit})>> latestDoseAmounts(
    Set<String> compoundIds,
  ) async {
    requestedLastDoseIds.add(compoundIds);
    await lastDosesGate;
    return <String, ({double amount, DoseUnit unit})>{
      for (final compoundId in compoundIds)
        if (lastDoses[compoundId] case final dose?) compoundId: dose,
    };
  }

  @override
  Future<CreateCompoundResult> createCompound(CompoundDraft draft) async {
    final id = 'created-${created.length + 1}';
    created.add(
      CompoundRecord(
        id: id,
        name: draft.name,
        defaultUnit: draft.defaultUnit,
        defaultRoute: draft.defaultRoute,
        updatedAt: DateTime.utc(2026, 6, 30),
      ),
    );
    return CreateCompoundResult(batchId: 'batch', compoundId: id);
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

/// An in-memory `ProtocolsLockStore` fake that never reports a configured
/// lock — keeps `ProtocolsLockGate` off the real secure-storage plugin
/// channel in widget tests that don't care about the lock itself.
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
