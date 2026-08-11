import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/protocols/models/effect_timeline_chart_data.dart';

/// the dose-overlay timeline's pure data prep — projecting the
/// outcome's actual samples and the actual logged `Dose` timeline into a
/// shared, origin-relative time axis so the fl_chart widget only has to plot
/// numbers, never touch a `DateTime`/Drift read itself. Pure — no widget
/// harness needed (mirrors `measurement_progress_graph_test.dart`).
void main() {
  group('EffectTimelineChartData', () {
    test(
        'projects samples and doses onto one shared day-offset axis, '
        'sorted chronologically regardless of input order', () {
      final window = EffectWindow(
        duringStart: DateTime.utc(2026, 1, 15),
        duringEnd: DateTime.utc(2026, 1, 25),
        now: DateTime.utc(2026, 2, 4),
      );
      // beforeStart = 2026-01-05, afterEnd = 2026-02-04 (10-day mirrored span).

      final data = EffectTimelineChartData.build(
        window: window,
        samples: <EffectSample>[
          EffectSample(at: DateTime.utc(2026, 1, 20), value: 80),
          EffectSample(at: DateTime.utc(2026, 1, 10), value: 82),
        ],
        doses: <DoseRecord>[
          _dose(id: 'd2', tookAt: DateTime.utc(2026, 1, 22)),
          _dose(id: 'd1', tookAt: DateTime.utc(2026, 1, 16)),
        ],
      );

      expect(data.points.map((p) => p.value), <double>[82, 80]);
      // day offset relative to window.beforeStart (2026-01-05).
      expect(data.points[0].daysSinceOrigin, closeTo(5.0, 1e-9));
      expect(data.points[1].daysSinceOrigin, closeTo(15.0, 1e-9));

      expect(data.markers.map((m) => m.at), <DateTime>[
        DateTime.utc(2026, 1, 16),
        DateTime.utc(2026, 1, 22),
      ]);
      expect(data.markers[0].daysSinceOrigin, closeTo(11.0, 1e-9));
      expect(data.markers[1].daysSinceOrigin, closeTo(17.0, 1e-9));

      expect(data.minX, closeTo(0.0, 1e-9));
      expect(data.maxX, closeTo(30.0, 1e-9));
      expect(data.hasSeries, isTrue);
      expect(data.hasMarkers, isTrue);
      expect(data.hasAnyData, isTrue);
      expect(data.hasRenderableSpan, isTrue);
      expect(() => data.points.clear(), throwsUnsupportedError);
      expect(() => data.markers.clear(), throwsUnsupportedError);
      expect(
        () => data.points[0] = const EffectTimelinePoint(
          daysSinceOrigin: 99,
          value: 99,
        ),
        throwsUnsupportedError,
      );
      expect(
        () => data.markers[0] = EffectTimelineMarker(
          daysSinceOrigin: 99,
          at: DateTime.utc(2026, 1, 1),
          dose: _dose(id: 'replacement', tookAt: DateTime.utc(2026, 1, 1)),
        ),
        throwsUnsupportedError,
      );
    });

    test(
        'degrades gracefully with no outcome samples but real Dose markers '
        '(never fabricates a series)', () {
      final window = EffectWindow(
        duringStart: DateTime.utc(2026, 1, 15),
        duringEnd: DateTime.utc(2026, 1, 25),
        now: DateTime.utc(2026, 2, 4),
      );

      final data = EffectTimelineChartData.build(
        window: window,
        samples: const <EffectSample>[],
        doses: <DoseRecord>[_dose(id: 'd1', tookAt: DateTime.utc(2026, 1, 18))],
      );

      expect(data.points, isEmpty);
      expect(data.hasSeries, isFalse);
      expect(data.markers, hasLength(1));
      expect(data.hasMarkers, isTrue);
      expect(data.hasAnyData, isTrue);
    });

    test('reports no data when there are neither samples nor Doses', () {
      final window = EffectWindow(
        duringStart: DateTime.utc(2026, 1, 15),
        duringEnd: DateTime.utc(2026, 1, 25),
        now: DateTime.utc(2026, 2, 4),
      );

      final data = EffectTimelineChartData.build(
        window: window,
        samples: const <EffectSample>[],
        doses: const <DoseRecord>[],
      );

      expect(data.hasAnyData, isFalse);
    });

    test(
        'hasRenderableSpan is false for a degenerate zero-length window '
        '(never divides by zero / plots a single point as a full chart)', () {
      final instant = DateTime.utc(2026, 1, 15);
      final window = EffectWindow(
        duringStart: instant,
        duringEnd: instant,
        now: instant,
      );

      final data = EffectTimelineChartData.build(
        window: window,
        samples: const <EffectSample>[],
        doses: const <DoseRecord>[],
      );

      expect(data.hasRenderableSpan, isFalse);
    });
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
