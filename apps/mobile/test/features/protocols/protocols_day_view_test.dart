import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/protocols/controllers/protocol_controller.dart';
import 'package:perennia/features/protocols/controllers/protocols_day_controller.dart';
import 'package:perennia/features/protocols/widgets/compound_list_screen.dart';
import 'package:perennia/features/protocols/widgets/protocols_day_view.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

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
      await _pumpUntilFound(tester, find.byKey(ProtocolsDayView.doseRowKey('dose-1')));

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
      expect(draft.localDate, const ProtocolDayDate(year: 2026, month: 6, day: 30));
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
}

Future<void> _pumpView(
  WidgetTester tester,
  ProtocolDayRecord day, {
  ThemeData? theme,
  _FakeProtocolDayController? controller,
  List<CompoundRecord> compounds = const <CompoundRecord>[],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
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
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme ?? AppTheme.light(),
        home: const ProtocolsDayView(),
      ),
    ),
  );
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
  _FakeProtocolDayController(this.day);

  final ProtocolDayRecord day;
  int seedCalls = 0;
  int previousDayCount = 0;
  int nextDayCount = 0;
  final editedDoseIds = <String>[];
  final editedDrafts = <DoseSnapshotDraft>[];
  final deletedDoseIds = <String>[];

  @override
  Stream<ProtocolDayState> build() {
    return Stream<ProtocolDayState>.value(ProtocolDayState(day: day));
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

ProtocolDayRecord _emptyDay() {
  return ProtocolDayRecord(
    localDate: const ProtocolDayDate(year: 2026, month: 6, day: 30),
    doses: <DoseRecord>[],
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
