import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/protocols/controllers/protocol_controller.dart';
import 'package:perennia/features/protocols/controllers/protocols_day_controller.dart';
import 'package:perennia/features/protocols/widgets/protocols_day_view.dart';
import 'package:perennia/theme/theme.dart';

/// The Track-tab analog for logging a `Dose` (PROTOCOLS.md §5): an
/// amount stepper + unit/route chips + a time picker, prefilled from the
/// Compound's last logged Dose so a repeat Dose is ≤2 taps (open the Compound
/// → Save). These tests exercise `LogDoseSheet` directly, the way a caller
/// (the Compound list row / Protocol Day FAB) hands it an already-resolved
/// Compound + last Dose — the repository-level derivation itself is covered by
/// protocols_repository_test.dart.
void main() {
  testWidgets(
    'first-time logging (no prior Dose) falls back to the Compound\'s '
    'default unit/route',
    (tester) async {
      final controller = _FakeProtocolDayController();
      await _pumpSheet(
        tester,
        compound: _vitaminD(),
        lastDose: null,
        controller: controller,
      );

      expect(find.text('1'), findsOneWidget);
      expect(
          _chipSelected(
              tester, LogDoseSheet.unitChipKey(DoseUnit.internationalUnit)),
          isTrue);
      expect(_chipSelected(tester, LogDoseSheet.routeChipKey(DoseRoute.oral)),
          isTrue);

      await tester.ensureVisible(find.byKey(LogDoseSheet.saveButtonKey));
      await tester.tap(find.byKey(LogDoseSheet.saveButtonKey));
      await tester.pump();

      expect(controller.loggedDoses, hasLength(1));
      final dose = controller.loggedDoses.single;
      expect(dose.unit, DoseUnit.internationalUnit);
      expect(dose.route, DoseRoute.oral);
    },
  );

  testWidgets(
    'prefill-from-last seeds amount/unit/route from the Compound\'s last Dose',
    (tester) async {
      final controller = _FakeProtocolDayController();
      final lastDose = _doseRecord(
        amountValue: 2,
        amountEntered: '2',
        unit: DoseUnit.capsule,
        route: DoseRoute.sublingual,
      );
      await _pumpSheet(
        tester,
        compound: _vitaminD(),
        lastDose: lastDose,
        controller: controller,
      );

      expect(find.text('2'), findsOneWidget);
      expect(_chipSelected(tester, LogDoseSheet.unitChipKey(DoseUnit.capsule)),
          isTrue);
      expect(
          _chipSelected(
              tester, LogDoseSheet.routeChipKey(DoseRoute.sublingual)),
          isTrue);
    },
  );

  testWidgets(
    'logging a repeat Dose takes <=2 taps and confirms locally within one '
    'frame — no spinner on the logging path',
    (tester) async {
      final controller = _FakeProtocolDayController();
      final lastDose = _doseRecord(
        amountValue: 2,
        amountEntered: '2',
        unit: DoseUnit.capsule,
        route: DoseRoute.sublingual,
      );
      await _pumpSheet(
        tester,
        compound: _vitaminD(),
        lastDose: lastDose,
        controller: controller,
      );

      // Tap 1 was "open the Compound" (already established by pumping the
      // prefilled sheet). Tap 2 is Save — a single frame confirms the write,
      // no spinner ever appears on the logging path.
      await tester.ensureVisible(find.byKey(LogDoseSheet.saveButtonKey));
      await tester.tap(find.byKey(LogDoseSheet.saveButtonKey));
      await tester.pump();

      expect(controller.loggedDoses, hasLength(1));
      final dose = controller.loggedDoses.single;
      expect(dose.compoundId, 'compound-vitamin-d');
      expect(dose.amountValue, 2);
      expect(dose.amountEntered, '2');
      expect(dose.unit, DoseUnit.capsule);
      expect(dose.route, DoseRoute.sublingual);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('the amount stepper increments and decrements the amount', (
    tester,
  ) async {
    final controller = _FakeProtocolDayController();
    // Capsule steps by a whole unit (1), unlike IU's coarser 100-unit step —
    // a clean fixture for asserting the exact stepped value.
    await _pumpSheet(
      tester,
      compound: _creatineCapsule(),
      lastDose: null,
      controller: controller,
    );

    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byKey(LogDoseSheet.incrementButtonKey));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byKey(LogDoseSheet.decrementButtonKey));
    await tester.pump();
    await tester.tap(find.byKey(LogDoseSheet.decrementButtonKey));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets(
    'unit and route chips are drawn ONLY from the curated registries',
    (tester) async {
      final controller = _FakeProtocolDayController();
      await _pumpSheet(
        tester,
        compound: _vitaminD(),
        lastDose: null,
        controller: controller,
      );

      for (final unit in DoseUnit.values) {
        expect(find.byKey(LogDoseSheet.unitChipKey(unit)), findsOneWidget);
      }
      for (final route in DoseRoute.values) {
        expect(find.byKey(LogDoseSheet.routeChipKey(route)), findsOneWidget);
      }
      expect(
          find.byType(ChoiceChip),
          findsNWidgets(
            DoseUnit.values.length + DoseRoute.values.length,
          ));
    },
  );

  testWidgets('the time field defaults to now and opens a picker to adjust', (
    tester,
  ) async {
    final controller = _FakeProtocolDayController();
    await _pumpSheet(
      tester,
      compound: _vitaminD(),
      lastDose: null,
      controller: controller,
    );

    expect(find.byKey(LogDoseSheet.timeFieldKey), findsOneWidget);

    await tester.tap(find.byKey(LogDoseSheet.timeFieldKey));
    await tester.pumpAndSettle();

    // A native time picker dialog opened for adjustment.
    expect(find.byType(TimePickerDialog), findsOneWidget);

    // Dismiss without changing anything.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'an untagged ad-hoc Dose defaults its Protocol picker to None',
    (tester) async {
      final controller = _FakeProtocolDayController();
      await _pumpSheet(
        tester,
        compound: _vitaminD(),
        lastDose: null,
        controller: controller,
        protocolOptions: <ProtocolOptionRecord>[_leanBulkProtocolOption()],
      );

      expect(find.byKey(LogDoseSheet.protocolFieldKey), findsOneWidget);
      expect(find.text('None (ad-hoc)'), findsOneWidget);

      await tester.ensureVisible(find.byKey(LogDoseSheet.saveButtonKey));
      await tester.tap(find.byKey(LogDoseSheet.saveButtonKey));
      await tester.pump();

      expect(controller.loggedDoses.single.protocolId, isNull);
      expect(controller.loggedDoses.single.protocolName, isNull);
    },
  );

  testWidgets(
    'logging a Dose can tag it to a Protocol at log time',
    (tester) async {
      final controller = _FakeProtocolDayController();
      await _pumpSheet(
        tester,
        compound: _vitaminD(),
        lastDose: null,
        controller: controller,
        protocolOptions: <ProtocolOptionRecord>[_leanBulkProtocolOption()],
      );

      await tester.tap(find.byKey(LogDoseSheet.protocolFieldKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lean bulk').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(LogDoseSheet.saveButtonKey));
      await tester.tap(find.byKey(LogDoseSheet.saveButtonKey));
      await tester.pump();

      expect(controller.loggedDoses, hasLength(1));
      expect(controller.loggedDoses.single.protocolId, 'protocol-1');
      expect(controller.loggedDoses.single.protocolName, 'Lean bulk');
    },
  );

  testWidgets(
    'editing an already-tagged Dose pre-selects its Protocol',
    (tester) async {
      final controller = _FakeProtocolDayController();
      final taggedDose = DoseRecord(
        id: 'dose-tagged',
        compoundId: 'compound-vitamin-d',
        compoundName: 'Vitamin D',
        amountValue: 1,
        amountEntered: '1',
        unit: DoseUnit.internationalUnit,
        route: DoseRoute.oral,
        tookAt: DateTime.utc(2026, 6, 30, 8),
        timezone: 'Australia/Brisbane',
        localDate: const ProtocolDayDate(year: 2026, month: 6, day: 30),
        provenance: DoseProvenance.manual,
        updatedAt: DateTime.utc(2026, 6, 30, 8),
        protocolId: 'protocol-1',
        protocolName: 'Lean bulk',
      );
      await _pumpEditSheet(
        tester,
        dose: taggedDose,
        controller: controller,
        protocolOptions: <ProtocolOptionRecord>[_leanBulkProtocolOption()],
      );

      expect(find.text('Lean bulk'), findsOneWidget);
    },
  );

  testWidgets(
    'editing a Dose can untag it back to ad-hoc',
    (tester) async {
      final controller = _FakeProtocolDayController();
      final taggedDose = DoseRecord(
        id: 'dose-tagged',
        compoundId: 'compound-vitamin-d',
        compoundName: 'Vitamin D',
        amountValue: 1,
        amountEntered: '1',
        unit: DoseUnit.internationalUnit,
        route: DoseRoute.oral,
        tookAt: DateTime.utc(2026, 6, 30, 8),
        timezone: 'Australia/Brisbane',
        localDate: const ProtocolDayDate(year: 2026, month: 6, day: 30),
        provenance: DoseProvenance.manual,
        updatedAt: DateTime.utc(2026, 6, 30, 8),
        protocolId: 'protocol-1',
        protocolName: 'Lean bulk',
      );
      await _pumpEditSheet(
        tester,
        dose: taggedDose,
        controller: controller,
        protocolOptions: <ProtocolOptionRecord>[_leanBulkProtocolOption()],
      );

      await tester.tap(find.byKey(LogDoseSheet.protocolFieldKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('None (ad-hoc)').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(LogDoseSheet.saveButtonKey));
      await tester.tap(find.byKey(LogDoseSheet.saveButtonKey));
      await tester.pump();

      expect(controller.editedDoses, hasLength(1));
      expect(controller.editedDoses.single.draft.protocolId, isNull);
      expect(controller.editedDoses.single.draft.protocolName, isNull);
    },
  );

  testWidgets('Log Dose sheet meets accessibility guidelines in both themes', (
    tester,
  ) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();
      final controller = _FakeProtocolDayController();
      final lastDose = _doseRecord(
        amountValue: 2,
        amountEntered: '2',
        unit: DoseUnit.capsule,
        route: DoseRoute.sublingual,
      );

      await _pumpSheet(
        tester,
        compound: _vitaminD(),
        lastDose: lastDose,
        controller: controller,
        theme: theme,
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

bool _chipSelected(WidgetTester tester, Key key) {
  final chip = tester.widget<ChoiceChip>(find.byKey(key));
  return chip.selected;
}

CompoundRecord _vitaminD() {
  return CompoundRecord(
    id: 'compound-vitamin-d',
    name: 'Vitamin D',
    defaultUnit: DoseUnit.internationalUnit,
    defaultRoute: DoseRoute.oral,
    strength: CompoundStrength.parse('1000 IU/capsule'),
    updatedAt: DateTime.utc(2026, 6, 30),
  );
}

CompoundRecord _creatineCapsule() {
  return CompoundRecord(
    id: 'compound-creatine',
    name: 'Creatine',
    defaultUnit: DoseUnit.capsule,
    defaultRoute: DoseRoute.oral,
    updatedAt: DateTime.utc(2026, 6, 30),
  );
}

DoseRecord _doseRecord({
  required double amountValue,
  required String amountEntered,
  required DoseUnit unit,
  required DoseRoute route,
}) {
  return DoseRecord(
    id: 'dose-last',
    compoundId: 'compound-vitamin-d',
    compoundName: 'Vitamin D',
    compoundStrength: CompoundStrength.parse('1000 IU/capsule'),
    amountValue: amountValue,
    amountEntered: amountEntered,
    unit: unit,
    route: route,
    tookAt: DateTime.utc(2026, 6, 28, 8),
    timezone: 'Australia/Brisbane',
    localDate: const ProtocolDayDate(year: 2026, month: 6, day: 28),
    provenance: DoseProvenance.manual,
    updatedAt: DateTime.utc(2026, 6, 28, 8),
  );
}

ProtocolOptionRecord _leanBulkProtocolOption() {
  return const ProtocolOptionRecord(
    id: 'protocol-1',
    name: 'Lean bulk',
  );
}

class _FakeProtocolDayController extends ProtocolDayController {
  final loggedDoses = <DoseSnapshotDraft>[];
  final editedDoses = <({String doseId, DoseSnapshotDraft draft})>[];

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
  Future<LogDoseResult> logDose(DoseSnapshotDraft draft) async {
    loggedDoses.add(draft);
    return LogDoseResult(
      batchId: 'batch-${loggedDoses.length}',
      doseId: 'dose-${loggedDoses.length}',
    );
  }

  @override
  Future<String> editDose(String doseId, DoseSnapshotDraft draft) async {
    editedDoses.add((doseId: doseId, draft: draft));
    return 'batch-edit-${editedDoses.length}';
  }
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required CompoundRecord compound,
  required DoseRecord? lastDose,
  required _FakeProtocolDayController controller,
  ThemeData? theme,
  List<ProtocolOptionRecord> protocolOptions = const <ProtocolOptionRecord>[],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        protocolDayControllerProvider.overrideWith(() => controller),
        protocolOptionListProvider.overrideWith(
          (ref) => Stream<List<ProtocolOptionRecord>>.value(protocolOptions),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: Scaffold(
          body: LogDoseSheet(compound: compound, lastDose: lastDose),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpEditSheet(
  WidgetTester tester, {
  required DoseRecord dose,
  required _FakeProtocolDayController controller,
  ThemeData? theme,
  List<ProtocolOptionRecord> protocolOptions = const <ProtocolOptionRecord>[],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        protocolDayControllerProvider.overrideWith(() => controller),
        protocolOptionListProvider.overrideWith(
          (ref) => Stream<List<ProtocolOptionRecord>>.value(protocolOptions),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: Scaffold(
          body: LogDoseSheet.edit(dose: dose),
        ),
      ),
    ),
  );
  await tester.pump();
}
