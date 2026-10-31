import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/protocols/protocol_plan_days.dart';
import 'package:perennia/features/protocols/controllers/protocol_controller.dart';
import 'package:perennia/features/protocols/controllers/protocols_day_controller.dart';
import 'package:perennia/features/protocols/controllers/protocols_lock_controller.dart';
import 'package:perennia/features/protocols/services/biometric_authenticator.dart';
import 'package:perennia/features/protocols/services/protocol_reminder_scheduler.dart';
import 'package:perennia/features/protocols/services/protocols_lock_store.dart';
import 'package:perennia/features/protocols/services/protocols_pin_hasher.dart';
import 'package:perennia/features/protocols/widgets/compound_list_screen.dart';
import 'package:perennia/features/protocols/widgets/protocols_lock_screen.dart';
import 'package:perennia/features/protocols/widgets/protocols_day_view.dart';
import 'package:perennia/features/training/services/timer_background_scheduler.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  testWidgets('Protocol Day view lists the day\'s doses', (tester) async {
    await _pumpView(tester, _dayWithDoses());
    await _pumpUntilFound(tester, find.byKey(ProtocolsDayView.doseListKey));

    expect(find.byKey(ProtocolsDayView.doseRowKey('dose-1')), findsOneWidget);
    expect(find.byKey(ProtocolsDayView.doseRowKey('dose-2')), findsOneWidget);
    expect(find.text('Creatine'), findsOneWidget);
    expect(find.text('Melatonin'), findsOneWidget);
    // Amount + unit + strength + route render from the Dose's own snapshot, with
    // the route always paired with text (color is never the sole signal).
    expect(find.textContaining('2 capsule'), findsOneWidget);
    // The frozen Compound strength snapshot renders from the Dose (§1.1)...
    expect(find.textContaining('5 mg/capsule'), findsOneWidget);
    // ...and the resolved active mass is derived on read (2 x 5 mg = 10 mg).
    expect(find.textContaining('10 mg'), findsOneWidget);
    expect(find.textContaining('Oral'), findsOneWidget);
    expect(find.textContaining('Sublingual'), findsOneWidget);
  });

  testWidgets('empty Protocol Day shows the empty state', (tester) async {
    await _pumpView(tester, _emptyDay());
    await _pumpUntilFound(tester, find.byKey(ProtocolsDayView.emptyStateKey));

    expect(find.byKey(ProtocolsDayView.emptyStateKey), findsOneWidget);
    expect(find.byKey(ProtocolsDayView.doseListKey), findsNothing);
  });

  testWidgets('opening the view triggers the OTC seed load', (tester) async {
    final controller = _FakeProtocolDayController(_emptyDay());
    await _pumpView(tester, _emptyDay(), controller: controller);
    await _pumpUntilFound(tester, find.byKey(ProtocolsDayView.emptyStateKey));

    // The seed library is loaded idempotently on first paint so the picker has
    // neutral starter Compounds (PROTOCOLS.md §3).
    expect(controller.seedCalls, greaterThanOrEqualTo(1));
  });

  testWidgets(
    'the FAB opens the Compound list — the ≤2-tap logging entry point '
    ': tap a Compound row there, then Save',
    (tester) async {
      final controller = _FakeProtocolDayController(_emptyDay());
      await _pumpView(
        tester,
        _emptyDay(),
        controller: controller,
        compounds: _seededCompounds(),
      );
      await _pumpUntilFound(tester, find.byKey(ProtocolsDayView.emptyStateKey));

      await tester.tap(find.byKey(ProtocolsDayView.logDoseButtonKey));
      await tester.pumpAndSettle();

      // Compound creation lives exclusively in `CompoundEditorSheet`;
      // logging always starts from an existing Compound in this reused
      // surface, never from a duplicate picker on the Day view itself.
      expect(find.byType(CompoundListScreen), findsOneWidget);
    },
  );

  testWidgets(
    'the Compound list the FAB opens is gated: re-locking while it is on '
    'top covers it with the lock screen',
    (tester) async {
      final lockStore = _FakeLockStore()
        ..enabled = true
        ..pinHash = await const ProtocolsPinHasher(iterations: 10).hash('1234');
      await _pumpView(
        tester,
        _emptyDay(),
        compounds: _seededCompounds(),
        lockStore: lockStore,
        home: const ProtocolsLockGate(child: ProtocolsDayView()),
        overrides: [
          biometricAuthenticatorProvider.overrideWith(
            (ref) => _NoBiometrics(),
          ),
          protocolsLockControllerProvider.overrideWith(
            () => ProtocolsLockController(
              hasher: const ProtocolsPinHasher(iterations: 10),
            ),
          ),
        ],
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(ProtocolsUnlockForm.pinFieldKey),
        '1234',
      );
      await tester.tap(find.byKey(ProtocolsUnlockForm.unlockPinButtonKey));
      await _pumpUntilFound(tester, find.byKey(ProtocolsDayView.emptyStateKey));

      await tester.tap(find.byKey(ProtocolsDayView.logDoseButtonKey));
      await tester.pumpAndSettle();
      expect(find.byType(CompoundListScreen), findsOneWidget);

      // The app leaves the foreground: the lock controller re-locks.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(find.byKey(ProtocolsLockGate.lockScreenKey), findsOneWidget);
      expect(find.byType(CompoundListScreen), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    },
  );

  testWidgets(
    'date header arrows and swipe move the selected Protocol Day',
    (tester) async {
      final controller = _FakeProtocolDayController(_dayWithDoses());
      await _pumpView(tester, _dayWithDoses(), controller: controller);
      await _pumpUntilFound(tester, find.byKey(ProtocolsDayView.dayHeaderKey));

      await tester.tap(find.byKey(ProtocolsDayView.previousDayButtonKey));
      await tester.pump();
      await tester.tap(find.byKey(ProtocolsDayView.nextDayButtonKey));
      await tester.pump();
      await tester.fling(
        find.byKey(ProtocolsDayView.dayHeaderKey),
        const Offset(400, 0),
        1000,
      );
      await tester.pump();
      await tester.fling(
        find.byKey(ProtocolsDayView.dayHeaderKey),
        const Offset(-400, 0),
        1000,
      );
      await tester.pump();

      expect(controller.previousDayCount, 2);
      expect(controller.nextDayCount, 2);
    },
  );

  testWidgets(
    'tapping a Dose row opens it for edit, prefilled from its own snapshot',
    (tester) async {
      await _pumpView(tester, _dayWithDoses());
      await _pumpUntilFound(
          tester, find.byKey(ProtocolsDayView.doseRowKey('dose-1')));

      await tester.tap(find.byKey(ProtocolsDayView.doseRowKey('dose-1')));
      await tester.pumpAndSettle();

      expect(find.byType(LogDoseSheet), findsOneWidget);
      // Prefilled straight from the Dose's OWN snapshot — no live Compound
      // lookup is needed (self-describing, PROTOCOLS.md §1.1).
      expect(find.text('Creatine'), findsWidgets);
      expect(find.text('2'), findsOneWidget);
      expect(
        _chipSelected(tester, LogDoseSheet.unitChipKey(DoseUnit.capsule)),
        isTrue,
      );
      expect(
        _chipSelected(tester, LogDoseSheet.routeChipKey(DoseRoute.oral)),
        isTrue,
      );
      // A Delete action is only offered in edit mode.
      expect(find.byKey(LogDoseSheet.deleteButtonKey), findsOneWidget);
    },
  );

  testWidgets(
    'editing a Dose and saving calls editDose, preserving the frozen local '
    'date and provenance',
    (tester) async {
      final controller = _FakeProtocolDayController(_dayWithDoses());
      await _pumpView(tester, _dayWithDoses(), controller: controller);
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolsDayView.doseRowKey('dose-1')),
      );

      await tester.tap(find.byKey(ProtocolsDayView.doseRowKey('dose-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(LogDoseSheet.incrementButtonKey));
      await tester.pump();
      await tester.ensureVisible(find.byKey(LogDoseSheet.saveButtonKey));
      await tester.tap(find.byKey(LogDoseSheet.saveButtonKey));
      await tester.pump();

      expect(controller.editedDoseIds, <String>['dose-1']);
      final draft = controller.editedDrafts.single;
      expect(draft.amountEntered, '3');
      expect(draft.localDate,
          const ProtocolDayDate(year: 2026, month: 6, day: 30));
      expect(draft.provenance, DoseProvenance.manual);
    },
  );

  testWidgets(
    'deleting a Dose from the editor asks for confirmation, then calls '
    'deleteDose',
    (tester) async {
      final controller = _FakeProtocolDayController(_dayWithDoses());
      await _pumpView(tester, _dayWithDoses(), controller: controller);
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolsDayView.doseRowKey('dose-2')),
      );

      await tester.tap(find.byKey(ProtocolsDayView.doseRowKey('dose-2')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(LogDoseSheet.deleteButtonKey));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.byKey(LogDoseSheet.confirmDeleteButtonKey));
      await tester.pumpAndSettle();

      expect(controller.deletedDoseIds, <String>['dose-2']);
    },
  );

  testWidgets(
    'the Dose editor and its delete confirmation meet accessibility '
    'guidelines in both themes',
    (tester) async {
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        final semantics = tester.ensureSemantics();
        await _pumpView(tester, _dayWithDoses(), theme: theme);
        await _pumpUntilFound(
          tester,
          find.byKey(ProtocolsDayView.doseRowKey('dose-1')),
        );

        await tester.tap(find.byKey(ProtocolsDayView.doseRowKey('dose-1')));
        await tester.pumpAndSettle();

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        await tester.tap(find.byKey(LogDoseSheet.deleteButtonKey));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        // Dismiss without deleting.
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  group('the reminder permission banner (CUJ 12)', () {
    Future<(ProtocolReminderScheduler, _BannerPermissions)> pumpWithReminders(
      WidgetTester tester, {
      TimerBackgroundPermissionStatus permission =
          TimerBackgroundPermissionStatus.notDetermined,
      bool deviceSwitchOn = true,
      bool remindersOn = true,
      ThemeData? theme,
    }) async {
      final permissions = _BannerPermissions(permission);
      final scheduler = ProtocolReminderScheduler(
        platform: _BannerPlatform(),
        permissions: permissions,
        readInputs: (from, to) async => <ProtocolReminderInput>[
          ProtocolReminderInput(
            protocolId: 'protocol-daily',
            compoundId: 'compound-trt',
            localDate: from,
            localTime: '23:59',
            remindersEnabled: remindersOn,
            filled: false,
          ),
        ],
        anyProtocolRemindersOn: () async => remindersOn,
        planChanges: () => const Stream<void>.empty(),
        lastSuccessfulSyncAt: () => const Stream<DateTime?>.empty(),
        deviceSwitchOn: () async => deviceSwitchOn,
        clock: () => _now,
      );
      addTearDown(scheduler.dispose);
      await tester.runAsync(scheduler.reconcile);
      await _pumpView(
        tester,
        _dayWithDoses(),
        theme: theme,
        overrides: <Override>[
          protocolReminderSchedulerProvider.overrideWithValue(scheduler),
        ],
      );
      await _pumpUntilFound(tester, find.byKey(ProtocolsDayView.dayHeaderKey));
      return (scheduler, permissions);
    }

    testWidgets(
      'shows "Reminders are off on this device" with Allow while this phone '
      'was never asked, and Allow asks once through the one permission path',
      (tester) async {
        final (_, permissions) = await pumpWithReminders(tester);
        await _pumpUntilFound(
          tester,
          find.byKey(ProtocolsDayView.reminderPermissionBannerKey),
        );

        expect(find.text('Reminders are off on this device'), findsOneWidget);
        expect(permissions.requests, 0, reason: 'showing it asks nothing');

        await tester
            .tap(find.byKey(ProtocolsDayView.reminderPermissionAllowKey));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        await tester.pump();

        expect(permissions.requests, 1);
        expect(
          find.byKey(ProtocolsDayView.reminderPermissionBannerKey),
          findsNothing,
        );
      },
    );

    testWidgets(
        'stays hidden once asked, with the device switch off, or '
        'with no Protocol asking for reminders', (tester) async {
      for (final (permission, device, reminders) in <(
        TimerBackgroundPermissionStatus,
        bool,
        bool,
      )>[
        (TimerBackgroundPermissionStatus.granted, true, true),
        (TimerBackgroundPermissionStatus.denied, true, true),
        (TimerBackgroundPermissionStatus.notDetermined, false, true),
        (TimerBackgroundPermissionStatus.notDetermined, true, false),
      ]) {
        await pumpWithReminders(
          tester,
          permission: permission,
          deviceSwitchOn: device,
          remindersOn: reminders,
        );
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          find.byKey(ProtocolsDayView.reminderPermissionBannerKey),
          findsNothing,
          reason: '$permission, device $device, reminders $reminders',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('meets accessibility guidelines in both themes',
        (tester) async {
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        final semantics = tester.ensureSemantics();
        await pumpWithReminders(tester, theme: theme);
        await _pumpUntilFound(
          tester,
          find.byKey(ProtocolsDayView.reminderPermissionBannerKey),
        );

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  });

  testWidgets('Protocol Day view meets accessibility guidelines in both themes',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();

      await _pumpView(tester, _dayWithDoses(), theme: theme);
      await _pumpUntilFound(tester, find.byKey(ProtocolsDayView.doseListKey));

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    "the day's Doses show in clock order: a later instant at an earlier clock "
    'time through its offset is listed first',
    (tester) async {
      final database = AppDatabase.inMemory();
      final repositories = TrainingRepositories(database);
      final day = ProtocolDayDate.fromDateTime(_cuj1Now);
      Future<String> logAt(DateTime tookAtUtc, int offset) async {
        final logged = await repositories.protocols.logDose(
          DoseSnapshotDraft(
            compoundName: 'Creatine',
            amountValue: 5,
            amountEntered: '5',
            unit: DoseUnit.gram,
            route: DoseRoute.oral,
            tookAt: tookAtUtc,
          ),
        );
        await (database.update(database.doses)
              ..where((row) => row.id.equals(logged.doseId)))
            .write(
          DosesCompanion(
            timezoneOffsetMinutes: Value<int?>(offset),
            localDate: Value<String>(day.storageValue),
          ),
        );
        return logged.doseId;
      }

      // Seeded on fake time. First in Tokyo (UTC+09:00): 21:00 there,
      // 12:00 UTC. Then in Honolulu (UTC−10:00): 08:30 there, 18:30 UTC, the
      // later instant at the earlier clock time.
      late final String tokyo;
      late final String honolulu;
      await _runOnFakeTime(tester, () async {
        tokyo = await logAt(DateTime.utc(2026, 10, 27, 12), 540);
        honolulu = await logAt(DateTime.utc(2026, 10, 27, 18, 30), -600);
      });

      await _pumpLiveView(tester, repositories, () => _cuj1Now);
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolsDayView.doseRowKey(honolulu)),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolsDayView.doseRowKey(tokyo)),
      );

      // `DateFormat.jm` may put a narrow no-break space before "AM".
      expect(
        find.descendant(
          of: find.byKey(ProtocolsDayView.doseRowKey(honolulu)),
          matching: find.textContaining(RegExp(r'8:30\sAM')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ProtocolsDayView.doseRowKey(tokyo)),
          matching: find.textContaining(RegExp(r'9:00\sPM')),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(ProtocolsDayView.doseRowKey(honolulu))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(ProtocolsDayView.doseRowKey(tokyo))).dy,
        ),
      );

      await _closeLive(tester, database);
    },
  );

  group('the Planned list (D6)', () {
    testWidgets(
      'today\'s rows read Logged or Pending, with the planned time or Any '
      'time and the amount, grouped under their Protocol',
      (tester) async {
        await _pumpView(
          tester,
          _emptyDay(_today),
          controller: _FakeProtocolDayController(
            _emptyDay(_today),
            plannedDay: _plannedDay(
              _today,
              doses: <PlanDose>[_planDose('c-trt', _today, '08:40')],
            ),
          ),
        );
        await _pumpUntilFound(
            tester, find.byKey(ProtocolsDayView.plannedListKey));

        expect(
          find.byKey(ProtocolsDayView.plannedGroupKey('protocol-daily')),
          findsOneWidget,
        );
        expect(
          find.byKey(ProtocolsDayView.plannedGroupKey('protocol-night')),
          findsOneWidget,
        );
        expect(find.text('Daily'), findsOneWidget);
        expect(find.text('Night'), findsOneWidget);
        expect(_rowLabel(tester, 'protocol-daily', 'c-trt'), 'Logged');
        expect(_rowLabel(tester, 'protocol-daily', 'c-agemate'), 'Pending');
        expect(_rowLabel(tester, 'protocol-daily', 'c-creatine'), 'Pending');
        expect(_rowLabel(tester, 'protocol-night', 'c-ghk'), 'Pending');
        expect(_rowLabel(tester, 'protocol-night', 'c-magnesium'), 'Pending');
        expect(_rowText(tester, 'protocol-daily', 'c-trt'),
            contains('0.5 mL · 9:00 AM'));
        expect(_rowText(tester, 'protocol-daily', 'c-creatine'),
            contains('5 g · 5:00 PM'));
        expect(_rowText(tester, 'protocol-night', 'c-magnesium'),
            contains('Any time'));
        expect(find.byKey(ProtocolsDayView.logAllPlannedButtonKey),
            findsOneWidget);
        expect(find.text('Log all planned'), findsOneWidget);
        // The logged Doses still list below; none are logged in this fixture.
        expect(find.byKey(ProtocolsDayView.emptyStateKey), findsOneWidget);
      },
    );

    testWidgets(
      'a past day\'s unfilled rows read Not logged, and it has no bulk action',
      (tester) async {
        await _pumpView(
          tester,
          _emptyDay(_yesterday),
          controller: _FakeProtocolDayController(
            _emptyDay(_yesterday),
            plannedDay: _plannedDay(
              _yesterday,
              doses: <PlanDose>[_planDose('c-trt', _yesterday, '09:05')],
            ),
          ),
        );
        await _pumpUntilFound(
            tester, find.byKey(ProtocolsDayView.plannedListKey));

        expect(_rowLabel(tester, 'protocol-daily', 'c-trt'), 'Logged');
        expect(_rowLabel(tester, 'protocol-daily', 'c-agemate'), 'Not logged');
        expect(_rowLabel(tester, 'protocol-night', 'c-ghk'), 'Not logged');
        expect(find.text('Pending'), findsNothing);
        expect(
            find.byKey(ProtocolsDayView.logAllPlannedButtonKey), findsNothing);
      },
    );

    testWidgets(
      'a future day shows its times and amounts with no label and no action',
      (tester) async {
        await _pumpView(
          tester,
          _emptyDay(_tomorrow),
          controller: _FakeProtocolDayController(
            _emptyDay(_tomorrow),
            plannedDay: _plannedDay(_tomorrow),
          ),
        );
        await _pumpUntilFound(
            tester, find.byKey(ProtocolsDayView.plannedListKey));

        expect(_rowText(tester, 'protocol-daily', 'c-trt'),
            contains('0.5 mL · 9:00 AM'));
        expect(_rowText(tester, 'protocol-night', 'c-magnesium'),
            contains('Any time'));
        for (final label in <String>['Logged', 'Pending', 'Not logged']) {
          expect(find.text(label), findsNothing);
        }
        expect(
            find.byKey(ProtocolsDayView.logAllPlannedButtonKey), findsNothing);

        await tester.tap(_rowFinder('protocol-daily', 'c-trt'));
        await tester.pumpAndSettle();
        expect(find.byType(LogDoseSheet), findsNothing);
      },
    );

    testWidgets('the list is hidden when the day has nothing planned', (
      tester,
    ) async {
      await _pumpView(
        tester,
        _emptyDay(_today),
        controller: _FakeProtocolDayController(
          _emptyDay(_today),
          plannedDay: _plannedDay(_today, protocols: const <PlanProtocol>[]),
        ),
      );
      await _pumpUntilFound(tester, find.byKey(ProtocolsDayView.emptyStateKey));

      expect(find.byKey(ProtocolsDayView.plannedListKey), findsNothing);
    });

    testWidgets(
      'a row logs in two taps: open it, then Save, at its planned amount and '
      'tagged with its Protocol, timed now on today',
      (tester) async {
        final controller = _FakeProtocolDayController(
          _emptyDay(_today),
          plannedDay: _plannedDay(_today),
        );
        await _pumpView(tester, _emptyDay(_today), controller: controller);
        await _pumpUntilFound(
            tester, find.byKey(ProtocolsDayView.plannedListKey));

        // Tap 1: the row.
        await tester.tap(_rowFinder('protocol-daily', 'c-agemate'));
        await tester.pumpAndSettle();
        expect(find.byType(LogDoseSheet), findsOneWidget);
        expect(find.text('Daily'), findsWidgets);

        // Tap 2: Save.
        await tester.ensureVisible(find.byKey(LogDoseSheet.saveButtonKey));
        await tester.tap(find.byKey(LogDoseSheet.saveButtonKey));
        await tester.pump();

        final dose = controller.loggedDoses.single;
        expect(dose.compoundId, 'c-agemate');
        expect(dose.compoundName, 'AgeMate');
        expect(dose.amountEntered, '1');
        expect(dose.unit, DoseUnit.capsule);
        expect(dose.route, DoseRoute.oral);
        expect(dose.protocolId, 'protocol-daily');
        expect(dose.protocolName, 'Daily');
        expect(dose.tookAt, _now);
      },
    );

    testWidgets(
      'a past day\'s row opens the sheet on that date at its planned time, '
      'both editable (CUJ 7)',
      (tester) async {
        final controller = _FakeProtocolDayController(
          _emptyDay(_yesterday),
          plannedDay: _plannedDay(_yesterday),
        );
        await _pumpView(tester, _emptyDay(_yesterday), controller: controller);
        await _pumpUntilFound(
            tester, find.byKey(ProtocolsDayView.plannedListKey));

        await tester.tap(_rowFinder('protocol-night', 'c-ghk'));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(LogDoseSheet.dateFieldKey),
            matching: find.text('Oct 26, 2026'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(LogDoseSheet.timeFieldKey),
            matching: find.text('9:00 PM'),
          ),
          findsOneWidget,
        );

        await tester.ensureVisible(find.byKey(LogDoseSheet.saveButtonKey));
        await tester.tap(find.byKey(LogDoseSheet.saveButtonKey));
        await tester.pump();

        final dose = controller.loggedDoses.single;
        expect(dose.tookAt, DateTime(2026, 10, 26, 21));
        expect(dose.protocolId, 'protocol-night');
      },
    );

    testWidgets(
      'an untimed row on a past day opens the sheet at 12:00 on that date',
      (tester) async {
        final controller = _FakeProtocolDayController(
          _emptyDay(_yesterday),
          plannedDay: _plannedDay(_yesterday),
        );
        await _pumpView(tester, _emptyDay(_yesterday), controller: controller);
        await _pumpUntilFound(
            tester, find.byKey(ProtocolsDayView.plannedListKey));

        await tester.tap(_rowFinder('protocol-night', 'c-magnesium'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(LogDoseSheet.saveButtonKey));
        await tester.tap(find.byKey(LogDoseSheet.saveButtonKey));
        await tester.pump();

        expect(
            controller.loggedDoses.single.tookAt, DateTime(2026, 10, 26, 12));
      },
    );

    testWidgets(
      'tapping a Logged row opens the Dose that fills it for edit, and saving '
      'it adds no Dose',
      (tester) async {
        final dose = _honoluluTrtDose();
        // A second TRT Dose that day, at 20:00 there, listed first: the
        // 08:40 Dose fills the one 09:00 slot and this one is an extra. The
        // row must open the Dose its fill names, not the day's first Dose or
        // the first of its Compound.
        final extra = DoseRecord(
          id: 'dose-trt-extra',
          compoundId: 'c-trt',
          compoundName: 'TRT',
          amountValue: 0.3,
          amountEntered: '0.3',
          unit: DoseUnit.milliliter,
          route: DoseRoute.intramuscular,
          tookAt: DateTime.utc(2026, 10, 28, 6),
          timezone: 'HST',
          localDate: _today,
          provenance: DoseProvenance.manual,
          updatedAt: DateTime.utc(2026, 10, 28, 6),
          timezoneOffsetMinutes: -600,
        );
        final day = ProtocolDayRecord(
          localDate: _today,
          doses: <DoseRecord>[extra, dose],
        );
        final controller = _FakeProtocolDayController(
          day,
          plannedDay: _plannedDay(
            _today,
            day: day,
            doses: <PlanDose>[
              PlanDose(
                doseId: extra.id,
                compoundId: 'c-trt',
                localDate: _today,
                localTime: extra.localTime,
                sequence: 0,
              ),
              PlanDose(
                doseId: dose.id,
                compoundId: 'c-trt',
                localDate: _today,
                localTime: dose.localTime,
                sequence: 1,
              ),
            ],
          ),
        );
        await _pumpView(tester, day, controller: controller);
        await _pumpUntilFound(
            tester, find.byKey(ProtocolsDayView.plannedListKey));
        expect(_rowLabel(tester, 'protocol-daily', 'c-trt'), 'Logged');

        await tester.tap(_rowFinder('protocol-daily', 'c-trt'));
        await tester.pumpAndSettle();

        // The edit sheet, on the Dose's own snapshot: Delete is offered only
        // in edit mode.
        expect(find.byType(LogDoseSheet), findsOneWidget);
        expect(find.byKey(LogDoseSheet.deleteButtonKey), findsOneWidget);
        expect(find.text('0.5'), findsOneWidget);

        await tester.ensureVisible(find.byKey(LogDoseSheet.saveButtonKey));
        await tester.tap(find.byKey(LogDoseSheet.saveButtonKey));
        await tester.pump();

        expect(controller.editedDoseIds, <String>[dose.id]);
        expect(controller.loggedDoses, isEmpty);
      },
    );

    testWidgets(
      'a Dose logged at another offset shows its own clock time, in its row '
      'and in its edit sheet',
      (tester) async {
        final dose = _honoluluTrtDose();
        final day = ProtocolDayRecord(
          localDate: _today,
          doses: <DoseRecord>[dose],
        );
        await _pumpView(tester, day);
        await _pumpUntilFound(
          tester,
          find.byKey(ProtocolsDayView.doseRowKey(dose.id)),
        );

        // 08:40 where it was taken (UTC−10:00), whatever the device's zone.
        // `DateFormat.jm` may put a narrow no-break space before "AM".
        expect(
          find.descendant(
            of: find.byKey(ProtocolsDayView.doseRowKey(dose.id)),
            matching: find.textContaining(RegExp(r'8:40\sAM')),
          ),
          findsOneWidget,
        );

        await tester.tap(find.byKey(ProtocolsDayView.doseRowKey(dose.id)));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(LogDoseSheet.timeFieldKey),
            matching: find.text('8:40 AM'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(LogDoseSheet.dateFieldKey),
            matching: find.text('Oct 27, 2026'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'every row label is a word beside its icon: color is never the only '
      'signal',
      (tester) async {
        await _pumpView(
          tester,
          _emptyDay(_today),
          controller: _FakeProtocolDayController(
            _emptyDay(_today),
            plannedDay: _plannedDay(
              _today,
              doses: <PlanDose>[_planDose('c-trt', _today, '09:00')],
            ),
          ),
        );
        await _pumpUntilFound(
            tester, find.byKey(ProtocolsDayView.plannedListKey));

        for (final (compoundId, label) in <(String, String)>[
          ('c-trt', 'Logged'),
          ('c-agemate', 'Pending'),
        ]) {
          final row = _rowFinder('protocol-daily', compoundId);
          final text = find.descendant(of: row, matching: find.text(label));
          expect(text, findsOneWidget);
          final labelRow =
              find.ancestor(of: text, matching: find.byType(Row)).first;
          expect(
            find.descendant(of: labelRow, matching: find.byType(Icon)),
            findsOneWidget,
          );
        }
        // The two labels differ in word as well as in icon color.
        expect(find.text('Logged'), findsOneWidget);
        expect(find.text('Pending'), findsNWidgets(4));
      },
    );

    testWidgets(
        'the Planned list meets accessibility guidelines in both themes',
        (tester) async {
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        final semantics = tester.ensureSemantics();
        await _pumpView(
          tester,
          _dayWithDoses(),
          theme: theme,
          controller: _FakeProtocolDayController(
            _dayWithDoses(),
            plannedDay: _plannedDay(
              _today,
              doses: <PlanDose>[_planDose('c-trt', _today, '09:00')],
            ),
          ),
        );
        await _pumpUntilFound(
            tester, find.byKey(ProtocolsDayView.plannedListKey));

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets(
      '"Log all planned" logs the due rows in one Batch and leaves a later '
      'row Pending (CUJ 1)',
      (tester) async {
        final database = AppDatabase.inMemory();
        final repositories = TrainingRepositories(database);
        await _seedOnFakeTime(tester, repositories);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              trainingRepositoriesProvider.overrideWith((ref) => repositories),
              protocolsClockProvider.overrideWithValue(() => _cuj1Now),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.light(),
              home: const ProtocolsDayView(),
            ),
          ),
        );
        await _pumpUntilFound(
          tester,
          find.byKey(ProtocolsDayView.logAllPlannedButtonKey),
        );
        expect(find.text('Pending'), findsNWidgets(3));

        await tester.tap(find.byKey(ProtocolsDayView.logAllPlannedButtonKey));
        await _pumpUntilFound(tester, find.text('Logged'));
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Logged'), findsNWidgets(2));
        expect(find.text('Pending'), findsOneWidget);
        expect(
          find.descendant(
            of: find.ancestor(
              of: find.text('Pending'),
              matching: find.byType(InkWell),
            ),
            matching: find.text('Creatine'),
          ),
          findsOneWidget,
        );
        // The two Doses list below, timed now, in one Batch.
        final doses = await database.select(database.doses).get();
        expect(
            doses.map((dose) => dose.compoundName).toSet(), {'TRT', 'AgeMate'});
        expect(
          doses.every((dose) => dose.tookAt.isAtSameMomentAs(_cuj1Now)),
          isTrue,
        );
        expect(doses.every((dose) => dose.protocolName == 'Daily'), isTrue);
        final entries = await repositories.activityLog.listEntries();
        final doseBatches = entries
            .where((entry) => entry.entityTable == AppDatabase.dosesTable)
            .map((entry) => entry.batchId)
            .toSet();
        expect(doseBatches, hasLength(1));

        // Unmount, then close the database on fake time: Drift's close waits
        // for its stream-cache timers, which only frames can fire.
        await tester.pumpWidget(const SizedBox.shrink());
        var closed = false;
        unawaited(database.close().then((_) => closed = true));
        for (var frame = 0; frame < 100 && !closed; frame += 1) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(closed, isTrue);
      },
    );

    testWidgets(
      'a double tap on "Log all planned" logs the due rows once',
      (tester) async {
        final database = AppDatabase.inMemory();
        final repositories = TrainingRepositories(database);
        await _seedOnFakeTime(tester, repositories);
        await _pumpLiveView(tester, repositories, () => _cuj1Now);
        await _pumpUntilFound(
          tester,
          find.byKey(ProtocolsDayView.logAllPlannedButtonKey),
        );

        // Two taps before any frame: both reach the button's handler.
        await tester.tap(find.byKey(ProtocolsDayView.logAllPlannedButtonKey));
        await tester.tap(find.byKey(ProtocolsDayView.logAllPlannedButtonKey));
        await _pumpUntilFound(tester, find.text('Logged'));
        await tester.pump(const Duration(milliseconds: 50));

        final doses = await database.select(database.doses).get();
        expect(doses.map((dose) => dose.compoundName).toList()..sort(),
            <String>['AgeMate', 'TRT']);
        expect(find.text('Logged'), findsNWidgets(2));

        await _closeLive(tester, database);
      },
    );

    testWidgets(
      'when local midnight passes, the day the view opened on reads as past: '
      'Not logged, with no bulk action',
      (tester) async {
        final database = AppDatabase.inMemory();
        final repositories = TrainingRepositories(database);
        await _seedOnFakeTime(tester, repositories);
        var now = _cuj1Now;
        await _pumpLiveView(tester, repositories, () => now);
        await _pumpUntilFound(
          tester,
          find.byKey(ProtocolsDayView.logAllPlannedButtonKey),
        );
        expect(find.text('Pending'), findsNWidgets(3));

        now = DateTime(2026, 10, 28, 8);
        await tester.pump(const Duration(minutes: 1));
        await _pumpUntilFound(tester, find.text('Not logged'));
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Not logged'), findsNWidgets(3));
        expect(find.text('Pending'), findsNothing);
        expect(
            find.byKey(ProtocolsDayView.logAllPlannedButtonKey), findsNothing);

        await _closeLive(tester, database);
      },
    );
  });

  group("Today's Protocols tab", () {
    const today = ProtocolDayDate(year: 2026, month: 6, day: 30);
    Widget tab() => const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: ProtocolsTodayBody(localDate: today),
          ),
        );

    testWidgets(
        'first run explains Protocols and offers New protocol and Log a dose',
        (tester) async {
      await _pumpView(
        tester,
        _emptyDay(),
        home: tab(),
        overrides: _protocolListOverrides(withProtocol: false),
      );
      await _pumpUntilFound(tester, find.byKey(ProtocolsTodayBody.introKey));

      expect(find.text('Plan what you take'), findsOneWidget);
      expect(
        find.byKey(ProtocolsTodayBody.newProtocolButtonKey),
        findsOneWidget,
      );
      expect(find.byKey(ProtocolsTodayBody.logDoseButtonKey), findsOneWidget);
    });

    testWidgets(
        "shows the day's logged Doses and the user's Protocols, with New "
        'protocol at the end of the list', (tester) async {
      await _pumpView(
        tester,
        _dayWithDoses(),
        home: tab(),
        overrides: _protocolListOverrides(),
      );
      await _pumpUntilFound(tester, find.text('Magnesium'));

      expect(find.byKey(ProtocolsDayView.doseRowKey('dose-1')), findsOneWidget);
      expect(find.byKey(ProtocolsTodayBody.introKey), findsNothing);
      expect(
        find.byKey(ProtocolsTodayBody.yourProtocolsKey),
        findsOneWidget,
      );
      expect(find.text('Sleep stack'), findsOneWidget);
      expect(find.text('Magnesium'), findsOneWidget);
      expect(find.text('New protocol'), findsOneWidget);
    });

    testWidgets('a set lock shows only the unlock form, never a Dose',
        (tester) async {
      final lockStore = _FakeLockStore()
        ..enabled = true
        ..pinHash = 'hash';
      await _pumpView(
        tester,
        _dayWithDoses(),
        home: tab(),
        lockStore: lockStore,
        overrides: [
          ..._protocolListOverrides(),
          biometricAuthenticatorProvider.overrideWith((ref) => _NoBiometrics()),
        ],
      );
      await _pumpUntilFound(tester, find.byKey(ProtocolsTodayBody.lockedKey));

      expect(find.text('Protocols are locked'), findsOneWidget);
      expect(find.byKey(ProtocolsUnlockForm.pinFieldKey), findsOneWidget);
      expect(find.text('Creatine'), findsNothing);
      expect(find.byKey(ProtocolsTodayBody.logDoseButtonKey), findsNothing);
    });

    testWidgets('Log a dose opens the Compound list on the tab\'s date',
        (tester) async {
      await _pumpView(
        tester,
        _emptyDay(),
        home: tab(),
        compounds: _seededCompounds(),
        overrides: _protocolListOverrides(withProtocol: false),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolsTodayBody.logDoseButtonKey),
      );

      await tester.tap(find.byKey(ProtocolsTodayBody.logDoseButtonKey));
      await tester.pumpAndSettle();

      final list = tester.widget<CompoundListScreen>(
        find.byType(CompoundListScreen),
      );
      expect(list.protocolDay, today);
    });

    for (final brightness in Brightness.values) {
      testWidgets('meets accessibility guidelines in ${brightness.name}',
          (tester) async {
        await _pumpView(
          tester,
          _dayWithDoses(),
          home: tab(),
          theme: brightness == Brightness.dark
              ? AppTheme.dark()
              : AppTheme.light(),
          overrides: _protocolListOverrides(),
        );
        await _pumpUntilFound(
          tester,
          find.byKey(ProtocolsTodayBody.yourProtocolsKey),
        );

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      });
    }
  });
}

/// Seeds the CUJ 1 stack in the test's own zone, with frames pumped until it
/// lands, so the database's queue and stream timers all run on fake time.
Future<void> _seedOnFakeTime(
  WidgetTester tester,
  TrainingRepositories repositories,
) {
  return _runOnFakeTime(tester, () => _seedDailyStack(repositories));
}

/// Runs [seed] in the test's own zone, with frames pumped until it lands, so
/// the database's queue and stream timers all run on fake time.
Future<void> _runOnFakeTime(
  WidgetTester tester,
  Future<void> Function() seed,
) async {
  var seeded = false;
  unawaited(seed().then((_) => seeded = true));
  for (var frame = 0; frame < 100 && !seeded; frame += 1) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(seeded, isTrue);
}

/// The Protocol Day view over a real repository and [clock].
Future<void> _pumpLiveView(
  WidgetTester tester,
  TrainingRepositories repositories,
  DateTime Function() clock,
) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
        protocolsClockProvider.overrideWithValue(clock),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: const ProtocolsDayView(),
      ),
    ),
  );
}

/// Unmounts, then closes the database on fake time: Drift's close waits for
/// its stream-cache timers, which only frames can fire.
Future<void> _closeLive(WidgetTester tester, AppDatabase database) async {
  await tester.pumpWidget(const SizedBox.shrink());
  var closed = false;
  unawaited(database.close().then((_) => closed = true));
  for (var frame = 0; frame < 100 && !closed; frame += 1) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(closed, isTrue);
}

Future<void> _pumpView(
  WidgetTester tester,
  ProtocolDayRecord day, {
  ThemeData? theme,
  _FakeProtocolDayController? controller,
  List<CompoundRecord> compounds = const <CompoundRecord>[],
  List<Override> overrides = const <Override>[],
  ProtocolsLockStore? lockStore,
  Widget home = const ProtocolsDayView(),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overrides,
        // The Compound list and Protocol list open behind
        // `ProtocolsLockGate`; the default store has no lock, which keeps
        // them off the secure-storage plugin.
        protocolsLockStoreProvider.overrideWith(
          (ref) => lockStore ?? _FakeLockStore(),
        ),
        protocolDayControllerProvider.overrideWith(
          () => controller ?? _FakeProtocolDayController(day),
        ),
        compoundListProvider.overrideWith(
          (ref) => Stream<List<CompoundRecord>>.value(compounds),
        ),
        recentCompoundIdsProvider.overrideWith(
          (ref) => Stream<List<String>>.value(const <String>[]),
        ),
        // LogDoseSheet's OPTIONAL Protocol tag picker reads this;
        // no Protocols fixture here, so it renders "None (ad-hoc)" only.
        protocolOptionListProvider.overrideWith(
          (ref) => Stream<List<ProtocolOptionRecord>>.value(
            const <ProtocolOptionRecord>[],
          ),
        ),
        protocolsClockProvider.overrideWithValue(() => _now),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme ?? AppTheme.light(),
        home: home,
      ),
    ),
  );
}

/// An in-memory `ProtocolsLockStore`: no lock unless a test sets one.
class _FakeLockStore implements ProtocolsLockStore {
  bool enabled = false;
  String? pinHash;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled(bool value) async {
    enabled = value;
  }

  @override
  Future<String?> readPinHash() async => pinHash;

  @override
  Future<void> writePinHash(String hash) async {
    pinHash = hash;
  }

  @override
  Future<void> clearPin() async {
    pinHash = null;
  }
}

class _NoBiometrics implements BiometricAuthenticator {
  @override
  Future<bool> isSupported() async => false;

  @override
  Future<bool> authenticate({required String reason}) async => false;
}

class _BannerPermissions implements TimerBackgroundScheduler {
  _BannerPermissions(this.status);

  TimerBackgroundPermissionStatus status;
  int requests = 0;

  @override
  Future<TimerBackgroundPermissionStatus> notificationPermissionStatus() async {
    return status;
  }

  @override
  Future<TimerBackgroundPermissionStatus> requestPermissionIfNeeded() async {
    requests += 1;
    status = TimerBackgroundPermissionStatus.granted;
    return status;
  }

  @override
  Future<TimerBackgroundPermissionStatus> schedule(
    TimerBackgroundSchedule schedule,
  ) async {
    return status;
  }

  @override
  Future<void> cancel(String timerId) async {}
}

class _BannerPlatform implements ProtocolReminderPlatform {
  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {}

  @override
  Future<String?> launchPayload() async => null;

  @override
  Future<tz.Location> localLocation() async => tz.UTC;

  @override
  Future<List<PendingProtocolNotification>> pendingNotifications() async {
    return const <PendingProtocolNotification>[];
  }

  @override
  Future<void> schedule(ProtocolReminderNotification notification) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> openNotificationSettings() async {}
}

List<CompoundRecord> _seededCompounds() {
  return <CompoundRecord>[
    CompoundRecord(
      id: 'seed-creatine',
      name: 'Creatine',
      defaultUnit: DoseUnit.gram,
      defaultRoute: DoseRoute.oral,
      updatedAt: DateTime.utc(2026, 6, 30),
    ),
    CompoundRecord(
      id: 'seed-vitamin-d',
      name: 'Vitamin D',
      defaultUnit: DoseUnit.internationalUnit,
      defaultRoute: DoseRoute.oral,
      strength: CompoundStrength.parse('1000 IU/capsule'),
      updatedAt: DateTime.utc(2026, 6, 30),
    ),
  ];
}

class _FakeProtocolDayController extends ProtocolDayController {
  _FakeProtocolDayController(this.day, {this.plannedDay});

  final ProtocolDayRecord day;
  final PlannedDay? plannedDay;
  final loggedDoses = <DoseSnapshotDraft>[];
  int seedCalls = 0;
  int previousDayCount = 0;
  int nextDayCount = 0;
  final editedDoseIds = <String>[];
  final editedDrafts = <DoseSnapshotDraft>[];
  final deletedDoseIds = <String>[];

  @override
  Stream<ProtocolDayState> build() {
    return Stream<ProtocolDayState>.value(
      ProtocolDayState(day: day, plannedDay: plannedDay),
    );
  }

  @override
  Future<LogDoseResult> logDose(DoseSnapshotDraft draft) async {
    loggedDoses.add(draft);
    return LogDoseResult(
      batchId: 'batch-log-${loggedDoses.length}',
      doseId: 'dose-log-${loggedDoses.length}',
    );
  }

  @override
  Future<void> ensureOtcLibrarySeeded() async {
    seedCalls += 1;
  }

  @override
  void showPreviousDay() {
    previousDayCount += 1;
  }

  @override
  void showNextDay() {
    nextDayCount += 1;
  }

  @override
  Future<String> editDose(String doseId, DoseSnapshotDraft draft) async {
    editedDoseIds.add(doseId);
    editedDrafts.add(draft);
    return 'batch-edit-${editedDoseIds.length}';
  }

  @override
  Future<String> deleteDose(String doseId) async {
    deletedDoseIds.add(doseId);
    return 'batch-delete-${deletedDoseIds.length}';
  }
}

bool _chipSelected(WidgetTester tester, Key key) {
  final chip = tester.widget<ChoiceChip>(find.byKey(key));
  return chip.selected;
}

ProtocolDayRecord _emptyDay([
  ProtocolDayDate localDate = const ProtocolDayDate(
    year: 2026,
    month: 6,
    day: 30,
  ),
]) {
  return ProtocolDayRecord(localDate: localDate, doses: <DoseRecord>[]);
}

/// "Now" for the Planned list fixtures: the afternoon of 2026-10-27.
final DateTime _now = DateTime(2026, 10, 27, 15, 30);
const _today = ProtocolDayDate(year: 2026, month: 10, day: 27);
const _yesterday = ProtocolDayDate(year: 2026, month: 10, day: 26);
const _tomorrow = ProtocolDayDate(year: 2026, month: 10, day: 28);
const _start = ProtocolDayDate(year: 2026, month: 10, day: 1);

/// CUJ 1's moment: 09:30, after the 09:00 doses and before the 17:00 one.
final DateTime _cuj1Now = DateTime(2026, 10, 27, 9, 30);

PlanMember _member(
  String compoundId,
  ScheduleRule rule,
  PlanAmount amount,
) {
  return PlanMember(
    memberId: 'm-$compoundId',
    compoundId: compoundId,
    versions: <ScheduleVersion>[
      ScheduleVersion(
        id: 'v-$compoundId',
        effectiveFrom: _start,
        rule: rule,
        amount: amount,
      ),
    ],
  );
}

ScheduleRule _dailyAt(String time) => TimedScheduleRule(
      days: const DailyScheduleDays(),
      times: <String>[time],
    );

/// Two Protocols: "Daily" (TRT and AgeMate at 09:00, creatine at 17:00) and
/// "Night" (GHK-Cu at 21:00, and one untimed magnesium).
List<PlanProtocol> _protocols() {
  return <PlanProtocol>[
    PlanProtocol(
      protocolId: 'protocol-daily',
      startLocalDate: _start,
      members: <PlanMember>[
        _member(
          'c-trt',
          _dailyAt('09:00'),
          const PlanAmount(
            amountValue: 0.5,
            amountEntered: '0.5',
            unit: DoseUnit.milliliter,
            route: DoseRoute.intramuscular,
          ),
        ),
        _member(
          'c-agemate',
          _dailyAt('09:00'),
          const PlanAmount(
            amountValue: 1,
            amountEntered: '1',
            unit: DoseUnit.capsule,
            route: DoseRoute.oral,
          ),
        ),
        _member(
          'c-creatine',
          _dailyAt('17:00'),
          const PlanAmount(
            amountValue: 5,
            amountEntered: '5',
            unit: DoseUnit.gram,
            route: DoseRoute.oral,
          ),
        ),
      ],
    ),
    PlanProtocol(
      protocolId: 'protocol-night',
      startLocalDate: _start,
      members: <PlanMember>[
        _member(
          'c-ghk',
          _dailyAt('21:00'),
          const PlanAmount(
            amountValue: 2,
            amountEntered: '2',
            unit: DoseUnit.milligram,
            route: DoseRoute.topical,
          ),
        ),
        _member(
          'c-magnesium',
          UntimedScheduleRule(days: const DailyScheduleDays(), count: 1),
          const PlanAmount(
            amountValue: 400,
            amountEntered: '400',
            unit: DoseUnit.milligram,
            route: DoseRoute.oral,
          ),
        ),
      ],
    ),
  ];
}

/// The Planned list for [localDate] against [_today], built by the shared
/// core exactly as the repository builds it.
PlannedDay _plannedDay(
  ProtocolDayDate localDate, {
  List<PlanDose> doses = const <PlanDose>[],
  List<PlanProtocol>? protocols,
  ProtocolDayRecord? day,
}) {
  final days = planDays(protocols ?? _protocols(), localDate, localDate);
  final isFuture = localDate.compareTo(_today) > 0;
  final statuses =
      isFuture ? const <DayStatus>[] : dayStatuses(days, doses, _today);
  return PlannedDay(
    localDate: localDate,
    today: _today,
    day: day ?? _emptyDay(localDate),
    planDays: days,
    dayStatuses: statuses,
    rowStatuses:
        isFuture ? dayStatuses(days, const <PlanDose>[], localDate) : statuses,
    compounds: <String, CompoundRecord>{
      for (final (id, name, unit) in <(String, String, DoseUnit)>[
        ('c-trt', 'TRT', DoseUnit.milliliter),
        ('c-agemate', 'AgeMate', DoseUnit.capsule),
        ('c-creatine', 'Creatine', DoseUnit.gram),
        ('c-ghk', 'GHK-Cu', DoseUnit.milligram),
        ('c-magnesium', 'Magnesium', DoseUnit.milligram),
      ])
        id: CompoundRecord(
          id: id,
          name: name,
          defaultUnit: unit,
          defaultRoute: DoseRoute.oral,
          updatedAt: DateTime.utc(2026, 10, 1),
        ),
    },
    protocols: const <String, ProtocolOptionRecord>{
      'protocol-daily':
          ProtocolOptionRecord(id: 'protocol-daily', name: 'Daily'),
      'protocol-night':
          ProtocolOptionRecord(id: 'protocol-night', name: 'Night'),
    },
  );
}

/// A TRT Dose logged in Honolulu (UTC−10:00) at 08:40 on [_today] there,
/// which is 18:40 UTC.
DoseRecord _honoluluTrtDose() {
  return DoseRecord(
    id: 'dose-trt-honolulu',
    compoundId: 'c-trt',
    compoundName: 'TRT',
    amountValue: 0.5,
    amountEntered: '0.5',
    unit: DoseUnit.milliliter,
    route: DoseRoute.intramuscular,
    tookAt: DateTime.utc(2026, 10, 27, 18, 40),
    timezone: 'HST',
    localDate: _today,
    provenance: DoseProvenance.manual,
    updatedAt: DateTime.utc(2026, 10, 27, 18, 40),
    protocolId: 'protocol-daily',
    protocolName: 'Daily',
    timezoneOffsetMinutes: -600,
  );
}

int _sequence = 0;

PlanDose _planDose(String compoundId, ProtocolDayDate date, String time) {
  _sequence += 1;
  return PlanDose(
    doseId: 'dose-$compoundId-$_sequence',
    compoundId: compoundId,
    localDate: date,
    localTime: time,
    sequence: 0,
  );
}

/// A Planned list row; each fixture Compound has one slot, slot 0.
Finder _rowFinder(String protocolId, String compoundId) =>
    find.byKey(ProtocolsDayView.plannedRowKey(protocolId, compoundId, 0));

String _rowText(WidgetTester tester, String protocolId, String compoundId) {
  return tester
      .widgetList<Text>(
        find.descendant(
          of: _rowFinder(protocolId, compoundId),
          matching: find.byType(Text),
        ),
      )
      .map((text) => text.data)
      .join(' | ');
}

/// The row's label: its last Text.
String? _rowLabel(WidgetTester tester, String protocolId, String compoundId) {
  return tester
      .widgetList<Text>(
        find.descendant(
          of: _rowFinder(protocolId, compoundId),
          matching: find.byType(Text),
        ),
      )
      .last
      .data;
}

/// CUJ 1's "Daily" Protocol through the real repositories.
Future<void> _seedDailyStack(TrainingRepositories repositories) async {
  Future<String> compound(String name, DoseUnit unit, DoseRoute route) async {
    final result = await repositories.protocols.createCompound(
      CompoundDraft(name: name, defaultUnit: unit, defaultRoute: route),
    );
    return result.compoundId;
  }

  final trt = await compound(
    'TRT',
    DoseUnit.milliliter,
    DoseRoute.intramuscular,
  );
  final ageMate = await compound('AgeMate', DoseUnit.capsule, DoseRoute.oral);
  final creatine = await compound('Creatine', DoseUnit.gram, DoseRoute.oral);
  ScheduleDraft dailyAt(
      String time, String amount, DoseUnit unit, DoseRoute route) {
    return ScheduleDraft(
      rule: _dailyAt(time),
      doseAmountValue: double.parse(amount),
      doseAmountEntered: amount,
      doseUnit: unit,
      route: route,
    );
  }

  final today = ProtocolDayDate.fromDateTime(_cuj1Now);
  await repositories.protocols.createProtocol(
    ProtocolDraft(
      name: 'Daily',
      startLocalDate: today,
      compoundIds: <String>[trt, ageMate, creatine],
      remindersEnabled: true,
      schedulesByCompoundId: <String, ScheduleDraft?>{
        trt: dailyAt(
            '09:00', '0.5', DoseUnit.milliliter, DoseRoute.intramuscular),
        ageMate: dailyAt('09:00', '1', DoseUnit.capsule, DoseRoute.oral),
        creatine: dailyAt('17:00', '5', DoseUnit.gram, DoseRoute.oral),
      },
    ),
    today: today,
  );
}

ProtocolDayRecord _dayWithDoses() {
  const localDate = ProtocolDayDate(year: 2026, month: 6, day: 30);
  return ProtocolDayRecord(
    localDate: localDate,
    doses: <DoseRecord>[
      DoseRecord(
        id: 'dose-1',
        compoundId: 'compound-creatine',
        compoundName: 'Creatine',
        compoundStrength: CompoundStrength.parse('5 mg/capsule'),
        amountValue: 2,
        amountEntered: '2',
        unit: DoseUnit.capsule,
        route: DoseRoute.oral,
        tookAt: DateTime.utc(2026, 6, 30, 8),
        timezone: 'Australia/Brisbane',
        localDate: localDate,
        provenance: DoseProvenance.manual,
        updatedAt: DateTime.utc(2026, 6, 30, 8),
      ),
      DoseRecord(
        id: 'dose-2',
        compoundName: 'Melatonin',
        amountValue: 3,
        amountEntered: '3',
        unit: DoseUnit.milligram,
        route: DoseRoute.sublingual,
        tookAt: DateTime.utc(2026, 6, 30, 21),
        timezone: 'Australia/Brisbane',
        localDate: localDate,
        provenance: DoseProvenance.manual,
        updatedAt: DateTime.utc(2026, 6, 30, 21),
      ),
    ],
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

/// The Protocols tab's list of Protocols, faked so it never reaches a real
/// repository: one "Sleep stack" holding Magnesium, or none.
List<Override> _protocolListOverrides({bool withProtocol = true}) {
  return <Override>[
    protocolListControllerProvider.overrideWith(
      () => _StaticProtocolList(<ProtocolSummaryRecord>[
        if (withProtocol)
          ProtocolSummaryRecord(
            id: 'protocol-sleep',
            name: 'Sleep stack',
            startLocalDate: const ProtocolDayDate(year: 2026, month: 6, day: 1),
            compoundIds: const <String>['compound-magnesium'],
          ),
      ]),
    ),
    protocolMemberCompoundNamesProvider(
      CompoundNameLookupRequest(const <String>['compound-magnesium']),
    ).overrideWith(
      (ref) => Stream<Map<String, String>>.value(
        const <String, String>{'compound-magnesium': 'Magnesium'},
      ),
    ),
  ];
}

class _StaticProtocolList extends ProtocolListController {
  _StaticProtocolList(this.protocols);

  final List<ProtocolSummaryRecord> protocols;

  @override
  Stream<List<ProtocolSummaryRecord>> build() {
    return Stream<List<ProtocolSummaryRecord>>.value(protocols);
  }
}
