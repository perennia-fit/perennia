import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/protocols/widgets/effect_timeline_chart.dart';
import 'package:perennia/theme/theme.dart';

/// the dose-overlay timeline widget. The pure day-offset projection
/// is covered by `effect_timeline_chart_data_test.dart`; this file only
/// verifies the widget renders fl_chart from that data (no live Drift
/// stream/CircularProgressIndicator here, so a plain `pumpWidget` + `pump()`
/// is enough — no `_pumpUntilFound` polling needed, mirrors the leaf-widget
/// convention rather than the screen-level fake-provider one).
void main() {
  testWidgets('shows a fallback with no outcome data and no logged Doses',
      (tester) async {
    final window = EffectWindow(
      duringStart: DateTime.utc(2026, 1, 15),
      duringEnd: DateTime.utc(2026, 1, 25),
      now: DateTime.utc(2026, 2, 4),
    );

    await _pumpChart(
      tester,
      window: window,
      samples: const <EffectSample>[],
      doses: const <DoseRecord>[],
    );

    expect(find.byKey(EffectTimelineChart.noDataKey), findsOneWidget);
    expect(find.byKey(EffectTimelineChart.chartKey), findsNothing);
  });

  testWidgets(
      'plots the outcome series and overlays the ACTUAL logged Dose times '
      'as vertical markers on the same axis', (tester) async {
    final window = EffectWindow(
      duringStart: DateTime.utc(2026, 1, 15),
      duringEnd: DateTime.utc(2026, 1, 25),
      now: DateTime.utc(2026, 2, 4),
    );
    final samples = <EffectSample>[
      EffectSample(at: DateTime.utc(2026, 1, 10), value: 82),
      EffectSample(at: DateTime.utc(2026, 1, 20), value: 79),
      EffectSample(at: DateTime.utc(2026, 1, 30), value: 80),
    ];
    final doses = <DoseRecord>[
      _dose(id: 'd1', tookAt: DateTime.utc(2026, 1, 16)),
      _dose(id: 'd2', tookAt: DateTime.utc(2026, 1, 18)),
    ];

    await _pumpChart(tester, window: window, samples: samples, doses: doses);

    expect(find.byKey(EffectTimelineChart.chartKey), findsOneWidget);
    expect(find.byKey(EffectTimelineChart.noDataKey), findsNothing);

    final lineChart = tester.widget<LineChart>(find.byType(LineChart));
    expect(lineChart.data.lineBarsData, hasLength(1));
    expect(lineChart.data.lineBarsData.single.spots, hasLength(3));
    // One vertical marker per ACTUAL logged Dose - never the plan/Schedule,
    // and never fewer/more than what was actually logged.
    expect(lineChart.data.extraLinesData.verticalLines, hasLength(2));

    expect(find.textContaining('2 logged Doses'), findsOneWidget);
  });

  testWidgets(
      'still overlays Dose markers when the outcome has no samples in the '
      'window (never fabricates a series to keep the chart non-empty)',
      (tester) async {
    final window = EffectWindow(
      duringStart: DateTime.utc(2026, 1, 15),
      duringEnd: DateTime.utc(2026, 1, 25),
      now: DateTime.utc(2026, 2, 4),
    );
    final doses = <DoseRecord>[_dose(id: 'd1', tookAt: DateTime.utc(2026, 1, 16))];

    await _pumpChart(
      tester,
      window: window,
      samples: const <EffectSample>[],
      doses: doses,
    );

    expect(find.byKey(EffectTimelineChart.chartKey), findsOneWidget);
    final lineChart = tester.widget<LineChart>(find.byType(LineChart));
    expect(lineChart.data.lineBarsData, isEmpty);
    expect(lineChart.data.extraLinesData.verticalLines, hasLength(1));
  });

  testWidgets('meets accessibility guidelines in both themes', (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final window = EffectWindow(
        duringStart: DateTime.utc(2026, 1, 15),
        duringEnd: DateTime.utc(2026, 1, 25),
        now: DateTime.utc(2026, 2, 4),
      );
      final semantics = tester.ensureSemantics();

      await _pumpChart(
        tester,
        window: window,
        samples: <EffectSample>[
          EffectSample(at: DateTime.utc(2026, 1, 18), value: 79),
        ],
        doses: <DoseRecord>[_dose(id: 'd1', tookAt: DateTime.utc(2026, 1, 16))],
        theme: theme,
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}

DoseRecord _dose({required String id, required DateTime tookAt}) {
  return DoseRecord(
    id: id,
    compoundName: 'Melatonin',
    amountValue: 3,
    amountEntered: '3',
    unit: DoseUnit.milligram,
    route: DoseRoute.oral,
    tookAt: tookAt,
    timezone: 'UTC',
    localDate: ProtocolDayDate.fromDateTime(tookAt),
    provenance: DoseProvenance.manual,
    updatedAt: tookAt,
  );
}

Future<void> _pumpChart(
  WidgetTester tester, {
  required EffectWindow window,
  required List<EffectSample> samples,
  required List<DoseRecord> doses,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: Scaffold(
        body: EffectTimelineChart(
          window: window,
          samples: samples,
          doses: doses,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 300));
}
