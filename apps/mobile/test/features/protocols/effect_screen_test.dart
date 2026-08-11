import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/protocols/controllers/effect_controller.dart';
import 'package:perennia/features/protocols/controllers/protocol_controller.dart';
import 'package:perennia/features/protocols/controllers/protocols_day_controller.dart';
import 'package:perennia/features/protocols/widgets/effect_screen.dart';
import 'package:perennia/features/protocols/widgets/effect_timeline_chart.dart';
import 'package:perennia/theme/theme.dart';

/// the `Effect` view's window/outcome picker + minimal
/// before/during/after render.
///
/// Mirrors `compound_list_screen_test.dart`/`protocols_day_view_test.dart`'s
/// fake-provider convention rather than wiring a real `AppDatabase` — the
/// screen's live Drift `.watch()` stream providers plus its
/// `CircularProgressIndicator` loading state make `pumpAndSettle()` hang and
/// leave pending Timers in a widget test. The real read path (window
/// derivation from actual logged Doses never the Schedule, samplesFor
/// metric/performance outcomes, computeOutcome never writing back, target-
/// outcome seeding) is already covered against a real in-memory Drift
/// database by `effect_repository_test.dart`, and the delta computation
/// itself by `effect_window_golden_test.dart`. This file only verifies the
/// SCREEN'S wiring: picking a source/outcome drives selection -> recompute ->
/// render, against canned fixtures.
void main() {
  testWidgets('shows the empty state with no Protocol or Compound yet',
      (tester) async {
    await _pumpEffectScreen(
      tester,
      protocols: const <ProtocolRecord>[],
      compounds: const <CompoundRecord>[],
      metrics: const <MetricRecord>[],
    );
    await _pumpUntilFound(tester, find.byKey(EffectScreen.noSourcesKey));

    expect(find.byKey(EffectScreen.noSourcesKey), findsOneWidget);
    expect(find.byKey(EffectScreen.noSourcePickedKey), findsOneWidget);

    await _disposeCleanly(tester);
  });

  testWidgets(
      'picking a Protocol seeds its declared target outcomes and renders '
      'before/during/after deltas from the canned computation',
      (tester) async {
    final metric = _metric('metric-1', 'Body Weight');
    final compound = _compound('compound-1', 'Creatine');
    final protocol = _protocolWithTargetOutcomes(
      id: 'protocol-1',
      name: 'Lean bulk',
      metricId: metric.id,
    );

    await _pumpEffectScreen(
      tester,
      protocols: <ProtocolRecord>[protocol],
      compounds: <CompoundRecord>[compound],
      metrics: <MetricRecord>[metric],
      computations: <EffectWindowSource, EffectComputation>{
        EffectWindowSource.protocol(protocol.id):
            _computationWithDeltas(metricId: metric.id),
      },
    );
    await _pumpUntilFound(
      tester,
      find.byKey(EffectScreen.protocolChipKey(protocol.id)),
    );

    await tester.tap(find.byKey(EffectScreen.protocolChipKey(protocol.id)));
    await tester.pump();
    await tester.pump();

    // Both declared target outcomes are seeded as selected chips.
    final metricChip = tester.widget<FilterChip>(
      find.byKey(EffectScreen.metricOutcomeChipKey(metric.id)),
    );
    expect(metricChip.selected, isTrue);
    final performanceChip = tester.widget<FilterChip>(
      find.byKey(EffectScreen.performanceOutcomeChipKey),
    );
    expect(performanceChip.selected, isTrue);

    await _pumpUntilFound(
      tester,
      find.byKey(EffectScreen.resultCardKey('metric-${metric.id}')),
    );

    expect(find.byKey(EffectScreen.windowSummaryKey), findsOneWidget);
    expect(find.textContaining('During:'), findsOneWidget);
    // Before mean 82, during mean 79 -> a during delta renders (never
    // fabricated, never colored as good/bad — just a magnitude + direction).
    expect(find.textContaining('During Δ'), findsWidgets);

    await _disposeCleanly(tester);
  });

  testWidgets(
      'the outcome result card renders the dose-overlay timeline '
      'with the ACTUAL logged Dose times, never the plan/Schedule',
      (tester) async {
    final metric = _metric('metric-1', 'Body Weight');
    final compound = _compound('compound-1', 'Creatine');
    final protocol = _protocolWithTargetOutcomes(
      id: 'protocol-1',
      name: 'Lean bulk',
      metricId: metric.id,
    );

    await _pumpEffectScreen(
      tester,
      protocols: <ProtocolRecord>[protocol],
      compounds: <CompoundRecord>[compound],
      metrics: <MetricRecord>[metric],
      computations: <EffectWindowSource, EffectComputation>{
        EffectWindowSource.protocol(protocol.id):
            _computationWithDeltas(metricId: metric.id),
      },
    );
    await _pumpUntilFound(
      tester,
      find.byKey(EffectScreen.protocolChipKey(protocol.id)),
    );

    await tester.tap(find.byKey(EffectScreen.protocolChipKey(protocol.id)));
    await tester.pump();
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(EffectScreen.resultCardKey('metric-${metric.id}')),
    );
    // Let fl_chart's bounded entrance animation settle (never an
    // unbounded/perpetual scheduler, so a fixed pump is safe here).
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(EffectTimelineChart.chartKey), findsWidgets);

    final lineChart = tester.widget<LineChart>(find.byType(LineChart).first);
    // Exactly the two Dose markers canned in the fixture — the real logged
    // times, never a plan/Schedule-derived count.
    expect(lineChart.data.extraLinesData.verticalLines, hasLength(2));
    expect(find.textContaining('2 logged Doses'), findsWidgets);

    await _disposeCleanly(tester);
  });

  testWidgets(
      'the outcome result card renders the dose-response table '
      'grouped by the ACTUAL logged Dose level, never the plan/Schedule',
      (tester) async {
    final metric = _metric('metric-1', 'Body Weight');
    final compound = _compound('compound-1', 'Creatine');
    final protocol = _protocolWithTargetOutcomes(
      id: 'protocol-1',
      name: 'Lean bulk',
      metricId: metric.id,
    );

    await _pumpEffectScreen(
      tester,
      protocols: <ProtocolRecord>[protocol],
      compounds: <CompoundRecord>[compound],
      metrics: <MetricRecord>[metric],
      computations: <EffectWindowSource, EffectComputation>{
        EffectWindowSource.protocol(protocol.id):
            _computationWithDeltas(metricId: metric.id),
      },
    );
    await _pumpUntilFound(
      tester,
      find.byKey(EffectScreen.protocolChipKey(protocol.id)),
    );

    await tester.tap(find.byKey(EffectScreen.protocolChipKey(protocol.id)));
    await tester.pump();
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(EffectScreen.resultCardKey('metric-${metric.id}')),
    );

    expect(find.textContaining('Dose response'), findsWidgets);
    // Two distinct dose levels canned in the fixture (5 mg, 10 mg) -> two
    // rows, never a plan/Schedule-derived count.
    expect(find.textContaining('5 mg'), findsWidgets);
    expect(find.textContaining('10 mg'), findsWidgets);

    await _disposeCleanly(tester);
  });

  testWidgets(
      'a manually-entered biomarker Metric can be picked AD HOC '
      '(not seeded from a Protocol) and its sparse Readings render '
      'gracefully — no fabricated during/after value', (tester) async {
    final biomarker = _biomarkerMetric('metric-testo', 'Testosterone');
    final compound = _compound('compound-trt', 'Testosterone Cyp');

    await _pumpEffectScreen(
      tester,
      protocols: const <ProtocolRecord>[],
      compounds: <CompoundRecord>[compound],
      metrics: <MetricRecord>[biomarker],
      computations: <EffectWindowSource, EffectComputation>{
        EffectWindowSource.compound(compound.id):
            _computationWithSparseBefore(metricId: biomarker.id),
      },
    );
    await _pumpUntilFound(
      tester,
      find.byKey(EffectScreen.compoundChipKey(compound.id)),
    );

    await tester.tap(find.byKey(EffectScreen.compoundChipKey(compound.id)));
    await tester.pump();
    await tester.pump();

    // Nothing is seeded for an ad-hoc Compound source (no target outcomes)
    // -> the biomarker chip starts unselected until the user picks it.
    final unselectedChip = tester.widget<FilterChip>(
      find.byKey(EffectScreen.metricOutcomeChipKey(biomarker.id)),
    );
    expect(unselectedChip.selected, isFalse);

    await tester.tap(
      find.byKey(EffectScreen.metricOutcomeChipKey(biomarker.id)),
    );
    await tester.pump();
    await tester.pump();

    final selectedChip = tester.widget<FilterChip>(
      find.byKey(EffectScreen.metricOutcomeChipKey(biomarker.id)),
    );
    expect(selectedChip.selected, isTrue);

    await _pumpUntilFound(
      tester,
      find.byKey(EffectScreen.resultCardKey('metric-${biomarker.id}')),
    );

    // Once as the outcome chip's label, once as the result card's heading.
    expect(find.text('Testosterone'), findsNWidgets(2));
    // One BEFORE sample, zero during/after -> a real before value alongside
    // a null (never fabricated) during/after mean, rendered as '—'.
    expect(find.text('620'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.textContaining('During Δ: —'), findsOneWidget);
    expect(find.textContaining('After Δ: —'), findsOneWidget);

    await _disposeCleanly(tester);
  });

  testWidgets(
      'an ad-hoc biomarker outcome with no computed samples yet '
      'shows "No data." rather than crashing or fabricating a value',
      (tester) async {
    final biomarker = _biomarkerMetric('metric-estr', 'Estradiol');
    final compound = _compound('compound-trt', 'Testosterone Cyp');

    await _pumpEffectScreen(
      tester,
      protocols: const <ProtocolRecord>[],
      compounds: <CompoundRecord>[compound],
      metrics: <MetricRecord>[biomarker],
      computations: <EffectWindowSource, EffectComputation>{
        EffectWindowSource.compound(compound.id): EffectComputation(
          window: EffectWindow(
            duringStart: DateTime.utc(2026, 1, 15),
            duringEnd: DateTime.utc(2026, 2, 14),
            now: DateTime.utc(2026, 2, 20),
          ),
          results: const <EffectOutcomeSelection, OutcomeEffectResult>{},
        ),
      },
    );
    await _pumpUntilFound(
      tester,
      find.byKey(EffectScreen.compoundChipKey(compound.id)),
    );

    await tester.tap(find.byKey(EffectScreen.compoundChipKey(compound.id)));
    await tester.pump();
    await tester.pump();
    await tester.tap(
      find.byKey(EffectScreen.metricOutcomeChipKey(biomarker.id)),
    );
    await tester.pump();
    await tester.pump();

    await _pumpUntilFound(
      tester,
      find.byKey(EffectScreen.resultCardKey('metric-${biomarker.id}')),
    );
    expect(find.text('No data.'), findsOneWidget);

    await _disposeCleanly(tester);
  });

  testWidgets(
      'picking a Compound with no logged Dose shows there is no window to '
      'derive yet (never fabricates one)', (tester) async {
    final compound = _compound('compound-2', 'Vitamin D');

    await _pumpEffectScreen(
      tester,
      protocols: const <ProtocolRecord>[],
      compounds: <CompoundRecord>[compound],
      metrics: const <MetricRecord>[],
      // No entry for this Compound's source -> the fake mirrors the real
      // repository's null-window case (no logged Dose to derive from).
      computations: const <EffectWindowSource, EffectComputation>{},
    );
    await _pumpUntilFound(
      tester,
      find.byKey(EffectScreen.compoundChipKey(compound.id)),
    );

    await tester.tap(find.byKey(EffectScreen.compoundChipKey(compound.id)));
    await tester.pump();
    await tester.pump();

    await _pumpUntilFound(tester, find.byKey(EffectScreen.noWindowKey));
    expect(find.byKey(EffectScreen.noWindowKey), findsOneWidget);

    await _disposeCleanly(tester);
  });

  testWidgets(
      'the one-time neutral disclaimer is present regardless of '
      'selection state, and never duplicated', (tester) async {
    await _pumpEffectScreen(
      tester,
      protocols: const <ProtocolRecord>[],
      compounds: const <CompoundRecord>[],
      metrics: const <MetricRecord>[],
    );
    await _pumpUntilFound(tester, find.byKey(EffectScreen.noSourcesKey));

    // Present even before any Protocol/Compound exists — it's a property of
    // the screen, not something gated behind having data.
    expect(find.byKey(EffectScreen.disclaimerKey), findsOneWidget);
    expect(find.textContaining('personal tracking'), findsOneWidget);
    expect(find.textContaining('not medical advice'), findsOneWidget);

    await _disposeCleanly(tester);
  });

  testWidgets(
      'the disclaimer stays a single instance once a window with '
      'outcome results renders', (tester) async {
    final metric = _metric('metric-1', 'Body Weight');
    final compound = _compound('compound-1', 'Creatine');
    final protocol = _protocolWithTargetOutcomes(
      id: 'protocol-1',
      name: 'Lean bulk',
      metricId: metric.id,
    );

    await _pumpEffectScreen(
      tester,
      protocols: <ProtocolRecord>[protocol],
      compounds: <CompoundRecord>[compound],
      metrics: <MetricRecord>[metric],
      computations: <EffectWindowSource, EffectComputation>{
        EffectWindowSource.protocol(protocol.id):
            _computationWithDeltas(metricId: metric.id),
      },
    );
    await _pumpUntilFound(
      tester,
      find.byKey(EffectScreen.protocolChipKey(protocol.id)),
    );
    await tester.tap(find.byKey(EffectScreen.protocolChipKey(protocol.id)));
    await tester.pump();
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(EffectScreen.resultCardKey('metric-${metric.id}')),
    );

    expect(find.byKey(EffectScreen.disclaimerKey), findsOneWidget);

    await _disposeCleanly(tester);
  });

  testWidgets(
      'confounders are surfaced once, in copy, alongside a '
      'rendered window — descriptive, never a verdict', (tester) async {
    final metric = _metric('metric-1', 'Body Weight');
    final compound = _compound('compound-1', 'Creatine');
    final protocol = _protocolWithTargetOutcomes(
      id: 'protocol-1',
      name: 'Lean bulk',
      metricId: metric.id,
    );

    await _pumpEffectScreen(
      tester,
      protocols: <ProtocolRecord>[protocol],
      compounds: <CompoundRecord>[compound],
      metrics: <MetricRecord>[metric],
      computations: <EffectWindowSource, EffectComputation>{
        EffectWindowSource.protocol(protocol.id):
            _computationWithDeltas(metricId: metric.id),
      },
    );
    await _pumpUntilFound(
      tester,
      find.byKey(EffectScreen.protocolChipKey(protocol.id)),
    );
    await tester.tap(find.byKey(EffectScreen.protocolChipKey(protocol.id)));
    await tester.pump();
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(EffectScreen.resultCardKey('metric-${metric.id}')),
    );

    expect(find.byKey(EffectScreen.confounderNoteKey), findsOneWidget);
    final note = tester
        .widget<Text>(find.byKey(EffectScreen.confounderNoteKey))
        .data!
        .toLowerCase();
    expect(note, contains('not a verdict'));
    for (final confounder in <String>[
      'diet',
      'training',
      'sleep',
      'regression to the mean',
      'placebo',
    ]) {
      expect(
        note,
        contains(confounder),
        reason: 'confounder note is missing "$confounder": $note',
      );
    }

    await _disposeCleanly(tester);
  });

  testWidgets(
      'rendered copy never states or implies causation or '
      'efficacy, anywhere on the Effect view', (tester) async {
    final metric = _metric('metric-1', 'Body Weight');
    final compound = _compound('compound-1', 'Creatine');
    final protocol = _protocolWithTargetOutcomes(
      id: 'protocol-1',
      name: 'Lean bulk',
      metricId: metric.id,
    );

    await _pumpEffectScreen(
      tester,
      protocols: <ProtocolRecord>[protocol],
      compounds: <CompoundRecord>[compound],
      metrics: <MetricRecord>[metric],
      computations: <EffectWindowSource, EffectComputation>{
        EffectWindowSource.protocol(protocol.id):
            _computationWithDeltas(metricId: metric.id),
      },
    );
    await _pumpUntilFound(
      tester,
      find.byKey(EffectScreen.protocolChipKey(protocol.id)),
    );
    await tester.tap(find.byKey(EffectScreen.protocolChipKey(protocol.id)));
    await tester.pump();
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(EffectScreen.resultCardKey('metric-${metric.id}')),
    );
    // Let the timeline chart + dose-response table settle so their copy is
    // present in the tree too.
    await tester.pump(const Duration(milliseconds: 300));

    final allText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join(' \n ')
        .toLowerCase();
    for (final forbidden in <String>[
      'works',
      'caused',
      'causes',
      'efficacy',
      'effective',
      'improves because',
      'proven',
    ]) {
      expect(
        allText.contains(forbidden),
        isFalse,
        reason: 'found forbidden causal/efficacy word "$forbidden" in '
            'rendered Effect view copy',
      );
    }

    await _disposeCleanly(tester);
  });

  testWidgets('Effect view meets accessibility guidelines in both themes',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final metric = _metric('metric-1', 'Body Weight');
      final compound = _compound('compound-1', 'Creatine');
      final protocol = _protocolWithTargetOutcomes(
        id: 'protocol-1',
        name: 'Lean bulk',
        metricId: metric.id,
      );

      final semantics = tester.ensureSemantics();

      await _pumpEffectScreen(
        tester,
        protocols: <ProtocolRecord>[protocol],
        compounds: <CompoundRecord>[compound],
        metrics: <MetricRecord>[metric],
        computations: <EffectWindowSource, EffectComputation>{
          EffectWindowSource.protocol(protocol.id):
              _computationWithDeltas(metricId: metric.id),
        },
        theme: theme,
      );
      await _pumpUntilFound(
        tester,
        find.byKey(EffectScreen.protocolChipKey(protocol.id)),
      );
      await tester.tap(find.byKey(EffectScreen.protocolChipKey(protocol.id)));
      await tester.pump();
      await tester.pump();
      await _pumpUntilFound(
        tester,
        find.byKey(EffectScreen.resultCardKey('metric-${metric.id}')),
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await _disposeCleanly(tester);
    }
  });
}

MetricRecord _metric(String id, String name) {
  return MetricRecord(
    id: id,
    name: name,
    unit: 'kilogram',
    valueShape: MetricValueShape.scalar,
    group: MetricGroup.bodyComposition,
    enabled: true,
    pinned: false,
    sortOrder: 0,
    updatedAt: DateTime.utc(2026, 6, 30),
  );
}

/// A manually-entered biomarker Metric: `MetricGroup.custom` with
/// a lab unit — never `bodyComposition` — proving the outcome picker and
/// result rendering are generic across the Metric umbrella, not special-
/// cased to weight/sleep/HRV.
MetricRecord _biomarkerMetric(String id, String name) {
  return MetricRecord(
    id: id,
    name: name,
    unit: 'ng/dL',
    valueShape: MetricValueShape.scalar,
    group: MetricGroup.custom,
    enabled: true,
    pinned: false,
    sortOrder: 0,
    updatedAt: DateTime.utc(2026, 6, 30),
  );
}

CompoundRecord _compound(String id, String name) {
  return CompoundRecord(
    id: id,
    name: name,
    defaultUnit: DoseUnit.gram,
    defaultRoute: DoseRoute.oral,
    updatedAt: DateTime.utc(2026, 6, 30),
  );
}

ProtocolRecord _protocolWithTargetOutcomes({
  required String id,
  required String name,
  required String metricId,
}) {
  return ProtocolRecord(
    id: id,
    name: name,
    startDate: DateTime.utc(2026, 1, 15),
    endDate: DateTime.utc(2026, 2, 14),
    members: const <ProtocolMemberRecord>[],
    updatedAt: DateTime.utc(2026, 6, 30),
    targetOutcomes: <ProtocolTargetOutcomeRecord>[
      ProtocolTargetOutcomeRecord(
        id: 'target-metric',
        kind: ProtocolOutcomeKind.metric,
        position: 0,
        metricId: metricId,
      ),
      const ProtocolTargetOutcomeRecord(
        id: 'target-performance',
        kind: ProtocolOutcomeKind.performance,
        position: 1,
      ),
    ],
  );
}

/// A canned [EffectComputation] with a real before/during delta (before mean
/// 82, during mean 79) so the delta-rendering assertions have something to
/// find, mirroring the fixture the repository test derives from actual
/// logged Metric Readings. Also carries the raw samples + two ACTUAL logged
/// Dose markers so the dose-overlay timeline has something to
/// plot too.
EffectComputation _computationWithDeltas({required String metricId}) {
  final window = EffectWindow(
    duringStart: DateTime.utc(2026, 1, 15),
    duringEnd: DateTime.utc(2026, 2, 14),
    now: DateTime.utc(2026, 2, 20),
  );
  final metricOutcome = EffectOutcomeSelection.metric(metricId);
  return EffectComputation(
    window: window,
    results: <EffectOutcomeSelection, OutcomeEffectResult>{
      metricOutcome: const OutcomeEffectResult(
        before: EffectSegmentStats(mean: 82, sampleCount: 1),
        during: EffectSegmentStats(mean: 79, sampleCount: 1),
        after: EffectSegmentStats(mean: null, sampleCount: 0),
      ),
      const EffectOutcomeSelection.performance(): const OutcomeEffectResult(
        before: EffectSegmentStats(mean: null, sampleCount: 0),
        during: EffectSegmentStats(mean: null, sampleCount: 0),
        after: EffectSegmentStats(mean: null, sampleCount: 0),
      ),
    },
    samples: <EffectOutcomeSelection, List<EffectSample>>{
      metricOutcome: <EffectSample>[
        EffectSample(at: DateTime.utc(2026, 1, 1), value: 82),
        EffectSample(at: DateTime.utc(2026, 1, 20), value: 79),
      ],
    },
    doses: <DoseRecord>[
      _dose(id: 'dose-1', tookAt: DateTime.utc(2026, 1, 16)),
      _dose(id: 'dose-2', tookAt: DateTime.utc(2026, 1, 30)),
    ],
    doseResponseTables: <EffectOutcomeSelection, List<DoseResponseRow>>{
      // Two distinct ACTUAL logged Dose levels — canned to mirror
      // what `computeDoseResponseTable` would derive from the two Doses
      // above, without re-running the pure function here (already covered
      // by `dose_response_table_golden_test.dart`).
      metricOutcome: <DoseResponseRow>[
        const DoseResponseRow(
          compoundName: 'Creatine',
          levelLabel: '5 mg',
          levelValue: 5,
          doseCount: 1,
          stats: EffectSegmentStats(mean: 82, sampleCount: 1),
        ),
        const DoseResponseRow(
          compoundName: 'Creatine',
          levelLabel: '10 mg',
          levelValue: 10,
          doseCount: 1,
          stats: EffectSegmentStats(mean: null, sampleCount: 0),
        ),
      ],
    },
  );
}

/// A canned [EffectComputation] with exactly ONE BEFORE sample and zero
/// during/after samples — a sparse manually-entered biomarker series (PER-
/// 252): mirrors what a real lab draw taken before starting a course, with
/// no follow-up draw yet, would produce. Nothing here fabricates a during/
/// after value; both stay `null`.
EffectComputation _computationWithSparseBefore({required String metricId}) {
  final window = EffectWindow(
    duringStart: DateTime.utc(2026, 1, 15),
    duringEnd: DateTime.utc(2026, 2, 14),
    now: DateTime.utc(2026, 2, 20),
  );
  final metricOutcome = EffectOutcomeSelection.metric(metricId);
  return EffectComputation(
    window: window,
    results: <EffectOutcomeSelection, OutcomeEffectResult>{
      metricOutcome: const OutcomeEffectResult(
        before: EffectSegmentStats(mean: 620, sampleCount: 1),
        during: EffectSegmentStats(mean: null, sampleCount: 0),
        after: EffectSegmentStats(mean: null, sampleCount: 0),
      ),
    },
    samples: <EffectOutcomeSelection, List<EffectSample>>{
      metricOutcome: <EffectSample>[
        EffectSample(at: DateTime.utc(2026, 1, 1), value: 620),
      ],
    },
  );
}

DoseRecord _dose({required String id, required DateTime tookAt}) {
  return DoseRecord(
    id: id,
    compoundName: 'Creatine',
    amountValue: 5,
    amountEntered: '5',
    unit: DoseUnit.gram,
    route: DoseRoute.oral,
    tookAt: tookAt,
    timezone: 'UTC',
    localDate: ProtocolDayDate.fromDateTime(tookAt),
    provenance: DoseProvenance.manual,
    updatedAt: tookAt,
  );
}

/// Unmounts the widget tree and pumps once more so nothing (including the
/// autoDispose `effectComputationProvider`'s teardown) is left pending before
/// the test framework's own end-of-test invariant check.
Future<void> _disposeCleanly(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Future<void> _pumpEffectScreen(
  WidgetTester tester, {
  required List<ProtocolRecord> protocols,
  required List<CompoundRecord> compounds,
  required List<MetricRecord> metrics,
  Map<EffectWindowSource, EffectComputation> computations =
      const <EffectWindowSource, EffectComputation>{},
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        protocolEffectOptionListProvider.overrideWith(
          (ref) => Stream<List<ProtocolEffectOptionRecord>>.value(
            protocols.map(_effectOptionFromProtocol).toList(growable: false),
          ),
        ),
        compoundOptionListProvider.overrideWith(
          (ref) => Stream<List<CompoundOptionRecord>>.value(
            compounds.map(_compoundOptionFromCompound).toList(growable: false),
          ),
        ),
        metricOptionListProvider.overrideWith(
          (ref) => Stream<List<MetricOptionRecord>>.value(
            metrics.map(_metricOptionFromMetric).toList(growable: false),
          ),
        ),
        // effectSelectionControllerProvider is left REAL — it is pure
        // in-memory selection state (no storage), so exercising it directly
        // is what proves a chip tap really drives selection -> recompute.
        effectComputationProvider.overrideWith((ref) async {
          final selection = ref.watch(effectSelectionControllerProvider);
          final source = selection.source;
          if (source == null) {
            return null;
          }
          return computations[source];
        }),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: const EffectScreen(),
      ),
    ),
  );
  await tester.pump();
}

ProtocolEffectOptionRecord _effectOptionFromProtocol(ProtocolRecord protocol) {
  return ProtocolEffectOptionRecord(
    id: protocol.id,
    name: protocol.name,
    targetOutcomes: protocol.targetOutcomes,
  );
}

CompoundOptionRecord _compoundOptionFromCompound(CompoundRecord compound) {
  return CompoundOptionRecord(id: compound.id, name: compound.name);
}

MetricOptionRecord _metricOptionFromMetric(MetricRecord metric) {
  return MetricOptionRecord(id: metric.id, name: metric.name);
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
