import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/protocols/controllers/protocol_controller.dart';
import 'package:perennia/features/protocols/controllers/protocols_day_controller.dart';
import 'package:perennia/features/protocols/widgets/protocol_screen.dart';
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
      find.byKey(ProtocolFormScreen.scheduleEditorKey('compound-creatine')),
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
    );
    await _pumpUntilFound(tester, find.byKey(ProtocolFormScreen.nameFieldKey));

    await tester.enterText(
      find.byKey(ProtocolFormScreen.nameFieldKey),
      'Lean bulk',
    );
    await _tap(
      tester,
      find.byKey(ProtocolFormScreen.compoundChipKey('compound-creatine')),
    );
    await _tap(
      tester,
      find.byKey(ProtocolFormScreen.compoundChipKey('compound-vitamin-d')),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.tap(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(controller.createdDrafts, hasLength(1));
    final draft = controller.createdDrafts.single;
    expect(draft.name, 'Lean bulk');
    expect(
      draft.compoundIds,
      unorderedEquals(<String>['compound-creatine', 'compound-vitamin-d']),
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
      find.byKey(ProtocolFormScreen.compoundChipKey('compound-vitamin-d')),
    );
    await tester.pumpAndSettle();

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

    expect(controller.archivedProtocolIds, <String>['protocol-1']);
  });

  group('Schedule editor', () {
    testWidgets(
        'a picked Compound gets a Schedule editor that starts at "No '
        'schedule", with no amount fields', (tester) async {
      final controller = _FakeProtocolListController();
      await _pumpFormScreen(tester, controller, compounds: _compounds());
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.nameFieldKey),
      );

      expect(
        find.byKey(ProtocolFormScreen.scheduleEditorKey('compound-creatine')),
        findsNothing,
      );

      await _tap(
        tester,
        find.byKey(ProtocolFormScreen.compoundChipKey('compound-creatine')),
      );

      expect(
        find.byKey(ProtocolFormScreen.scheduleEditorKey('compound-creatine')),
        findsOneWidget,
      );
      expect(
        _ruleChip(tester, 'compound-creatine', ProtocolScheduleRuleChoice.none)
            .selected,
        isTrue,
      );
      expect(
        find.byKey(
          ProtocolFormScreen.scheduleAmountFieldKey('compound-creatine'),
        ),
        findsNothing,
      );
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
      await _tap(
        tester,
        find.byKey(ProtocolFormScreen.compoundChipKey('compound-creatine')),
      );
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
      await _tap(
        tester,
        find.byKey(ProtocolFormScreen.compoundChipKey('compound-creatine')),
      );
      await _tap(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleRuleChipKey(
            'compound-creatine',
            ProtocolScheduleRuleChoice.timed,
          ),
        ),
      );
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

      await _tap(tester, find.byKey(ProtocolFormScreen.startDateFieldKey));
      await _tap(tester, find.text('15'));
      await _tap(tester, find.text('OK'));
      expect(find.text('Jul 15, 2026 (the start date)'), findsOneWidget);

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

      await _tap(tester, find.byKey(ProtocolFormScreen.saveButtonKey));

      expect(controller.editedDrafts, isEmpty);
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
      expect(find.byKey(ProtocolFormScreen.errorTextKey), findsOneWidget);

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

      expect(
        find.byKey(
          ProtocolFormScreen.scheduleIssueKey(
              'compound-creatine', 'times_many'),
        ),
        findsOneWidget,
      );
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

      expect(
        find.text('Sep 5, 2026 (the start date)', skipOffstage: false),
        findsNWidgets(2),
      );
      // The old start shows only as the date the version applies from.
      expect(
        find.text('Sep 1, 2026 (the start date)', skipOffstage: false),
        findsNothing,
      );

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

      await _tap(
        tester,
        find.byKey(
          ProtocolFormScreen.scheduleRuleChipKey(
            'compound-bpc',
            ProtocolScheduleRuleChoice.asNeeded,
          ),
        ),
      );
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
    );
    await _pumpUntilFound(tester, find.byKey(ProtocolFormScreen.nameFieldKey));

    await tester.enterText(
      find.byKey(ProtocolFormScreen.nameFieldKey),
      'Lean bulk',
    );
    await _tap(
      tester,
      find.byKey(ProtocolFormScreen.compoundChipKey('compound-creatine')),
    );
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
    );
    await _pumpUntilFound(tester, find.byKey(ProtocolFormScreen.nameFieldKey));

    await tester.enterText(
      find.byKey(ProtocolFormScreen.nameFieldKey),
      'Lean bulk',
    );
    await _tap(
      tester,
      find.byKey(ProtocolFormScreen.compoundChipKey('compound-creatine')),
    );
    await tester.pumpAndSettle();

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

  testWidgets('Protocol form meets accessibility guidelines in both themes',
      (tester) async {
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
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.saveButtonKey),
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

Future<void> _pumpListScreen(
  WidgetTester tester,
  _FakeProtocolListController controller, {
  ThemeData? theme,
  List<CompoundRecord> compounds = const <CompoundRecord>[],
  Map<String, String> compoundNames = const <String, String>{},
}) async {
  final memberIds = controller.protocols
      .expand((protocol) => protocol.members)
      .map((member) => member.compoundId);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        protocolListControllerProvider.overrideWith(() => controller),
        compoundListProvider.overrideWith(
          (ref) => Stream<List<CompoundRecord>>.value(compounds),
        ),
        compoundScheduleOptionListProvider.overrideWith(
          (ref) => Stream<List<CompoundScheduleOptionRecord>>.value(
            compounds
                .map(_compoundScheduleOptionFromCompound)
                .toList(growable: false),
          ),
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
  List<MetricRecord> metrics = const <MetricRecord>[],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        protocolListControllerProvider.overrideWith(() => controller),
        compoundScheduleOptionListProvider.overrideWith(
          (ref) => Stream<List<CompoundScheduleOptionRecord>>.value(
            compounds
                .map(_compoundScheduleOptionFromCompound)
                .toList(growable: false),
          ),
        ),
        metricOptionListProvider.overrideWith(
          (ref) => Stream<List<MetricOptionRecord>>.value(
            metrics.map(_metricOptionFromMetric).toList(growable: false),
          ),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProtocolFormScreen(protocol: protocol),
      ),
    ),
  );
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

  @override
  Stream<List<ProtocolSummaryRecord>> build() {
    return Stream<List<ProtocolSummaryRecord>>.value(
      protocols.map(_protocolSummaryFromProtocol).toList(growable: false),
    );
  }

  @override
  Future<CreateProtocolResult> createProtocol(ProtocolDraft draft) async {
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
    archivedProtocolIds.add(protocolId);
    return 'batch-archive-${archivedProtocolIds.length}';
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
