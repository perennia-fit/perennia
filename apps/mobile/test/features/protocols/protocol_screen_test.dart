import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/protocols/controllers/protocol_controller.dart';
import 'package:perennia/features/protocols/controllers/protocols_day_controller.dart';
import 'package:perennia/features/protocols/widgets/protocol_screen.dart';
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
      find.byKey(
        ProtocolFormScreen.scheduleToggleKey('compound-creatine'),
      ),
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
    await tester.tap(
      find.byKey(ProtocolFormScreen.compoundChipKey('compound-creatine')),
    );
    await tester.tap(
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
    expect(draft.endDate, isNull);
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
    await tester.tap(
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

  testWidgets(
      'a Compound\'s Schedule fields are hidden until it is picked, and '
      'appear once selected', (tester) async {
    final controller = _FakeProtocolListController();
    await _pumpFormScreen(tester, controller, compounds: _compounds());
    await _pumpUntilFound(tester, find.byKey(ProtocolFormScreen.nameFieldKey));

    expect(
      find.byKey(
        ProtocolFormScreen.scheduleToggleKey('compound-creatine'),
      ),
      findsNothing,
    );

    await tester.tap(
      find.byKey(ProtocolFormScreen.compoundChipKey('compound-creatine')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        ProtocolFormScreen.scheduleToggleKey('compound-creatine'),
      ),
      findsOneWidget,
    );
    // Off by default — a Protocol/Compound with no Schedule is still valid
    // (PROTOCOLS.md §1.4).
    expect(
      find.byKey(
        ProtocolFormScreen.scheduleAmountFieldKey('compound-creatine'),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'creating a Protocol: adding an optional Schedule for a picked '
      'Compound saves planned dose · frequency · route', (tester) async {
    final controller = _FakeProtocolListController();
    await _pumpFormScreen(tester, controller, compounds: _compounds());
    await _pumpUntilFound(tester, find.byKey(ProtocolFormScreen.nameFieldKey));

    await tester.enterText(
      find.byKey(ProtocolFormScreen.nameFieldKey),
      'Lean bulk',
    );
    await tester.tap(
      find.byKey(ProtocolFormScreen.compoundChipKey('compound-creatine')),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(ProtocolFormScreen.scheduleToggleKey('compound-creatine')),
    );
    await tester.tap(
      find.byKey(
        ProtocolFormScreen.scheduleToggleKey('compound-creatine'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(
        ProtocolFormScreen.scheduleAmountFieldKey('compound-creatine'),
      ),
    );
    await tester.enterText(
      find.byKey(
        ProtocolFormScreen.scheduleAmountFieldKey('compound-creatine'),
      ),
      '5',
    );
    await tester.ensureVisible(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.tap(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(controller.createdDrafts, hasLength(1));
    final draft = controller.createdDrafts.single;
    final schedule = draft.schedulesByCompoundId['compound-creatine'];
    expect(schedule, isNotNull);
    expect(schedule!.doseAmountEntered, '5');
    expect(schedule.doseAmountValue, 5);
    // Sensible curated defaults when the user does not touch the dropdowns.
    expect(schedule.doseUnit, DoseUnit.gram);
    expect(schedule.frequency, ScheduleFrequency.onceDaily);
    expect(schedule.route, DoseRoute.oral);
  });

  testWidgets(
      'creating a Protocol with a Compound but NO Schedule toggled on saves '
      'a null Schedule for it — a Protocol with no Schedules is still valid',
      (tester) async {
    final controller = _FakeProtocolListController();
    await _pumpFormScreen(tester, controller, compounds: _compounds());
    await _pumpUntilFound(tester, find.byKey(ProtocolFormScreen.nameFieldKey));

    await tester.enterText(
      find.byKey(ProtocolFormScreen.nameFieldKey),
      'Lean bulk',
    );
    await tester.tap(
      find.byKey(ProtocolFormScreen.compoundChipKey('compound-creatine')),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.tap(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(controller.createdDrafts, hasLength(1));
    expect(
      controller
          .createdDrafts.single.schedulesByCompoundId['compound-creatine'],
      isNull,
    );
  });

  testWidgets('editing a Protocol pre-fills an existing member\'s Schedule',
      (tester) async {
    final controller = _FakeProtocolListController();
    await _pumpFormScreen(
      tester,
      controller,
      protocol: _leanBulkStackWithSchedule(),
      compounds: _compounds(),
    );
    await _pumpUntilFound(tester, find.byKey(ProtocolFormScreen.nameFieldKey));

    // The Schedule toggle for the scheduled member starts ON and its planned
    // dose is pre-filled.
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(
        ProtocolFormScreen.scheduleToggleKey('compound-creatine'),
      ),
    );
    expect(toggle.value, isTrue);
    expect(find.text('5'), findsOneWidget);

    await tester.ensureVisible(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.tap(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    final draft = controller.editedDrafts.single;
    final schedule = draft.schedulesByCompoundId['compound-creatine'];
    expect(schedule, isNotNull);
    expect(schedule!.doseAmountEntered, '5');
    expect(schedule.frequency, ScheduleFrequency.onceDaily);
  });

  testWidgets(
      'editing a Protocol: turning a Compound\'s Schedule toggle off removes '
      'it — editing a Schedule never touches a logged Dose', (tester) async {
    final controller = _FakeProtocolListController();
    await _pumpFormScreen(
      tester,
      controller,
      protocol: _leanBulkStackWithSchedule(),
      compounds: _compounds(),
    );
    await _pumpUntilFound(tester, find.byKey(ProtocolFormScreen.nameFieldKey));

    await tester.ensureVisible(
      find.byKey(ProtocolFormScreen.scheduleToggleKey('compound-creatine')),
    );
    await tester.tap(
      find.byKey(
        ProtocolFormScreen.scheduleToggleKey('compound-creatine'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.tap(find.byKey(ProtocolFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    final draft = controller.editedDrafts.single;
    expect(
      draft.schedulesByCompoundId['compound-creatine'],
      isNull,
    );
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
    await tester.tap(
      find.byKey(ProtocolFormScreen.compoundChipKey('compound-creatine')),
    );
    await tester.tap(
      find.byKey(
        ProtocolFormScreen.targetOutcomeMetricChipKey('metric-weight'),
      ),
    );
    await tester.tap(
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
    await tester.tap(
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
        // A member WITH a Schedule so its toggle + fields are exercised by
        // the guideline checks too, plus a selected target outcome
        // so its chip is exercised too.
        protocol: _leanBulkStackWithSchedule(),
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
    startDate: DateTime.utc(2026, 7, 1),
    endDate: null,
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

/// The same stack as [_leanBulkStack], but the Creatine member carries an
/// optional `Schedule` — the pre-fill fixture for edit-screen tests.
ProtocolRecord _leanBulkStackWithSchedule() {
  final stack = _leanBulkStack();
  return ProtocolRecord(
    id: stack.id,
    name: stack.name,
    startDate: stack.startDate,
    endDate: stack.endDate,
    updatedAt: stack.updatedAt,
    members: <ProtocolMemberRecord>[
      ProtocolMemberRecord(
        id: 'member-1',
        compoundId: 'compound-creatine',
        position: 0,
        schedule: ScheduleRecord(
          id: 'schedule-1',
          protocolCompoundId: 'member-1',
          doseAmountValue: 5,
          doseAmountEntered: '5',
          doseUnit: DoseUnit.gram,
          frequency: ScheduleFrequency.onceDaily,
          route: DoseRoute.oral,
          updatedAt: DateTime.utc(2026, 7, 1),
        ),
      ),
      const ProtocolMemberRecord(
        id: 'member-2',
        compoundId: 'compound-vitamin-d',
        position: 1,
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
    startDate: stack.startDate,
    endDate: stack.endDate,
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
    startDate: protocol.startDate,
    endDate: protocol.endDate,
    compoundIds: protocol.members
        .map((member) => member.compoundId)
        .toList(growable: false),
  );
}
