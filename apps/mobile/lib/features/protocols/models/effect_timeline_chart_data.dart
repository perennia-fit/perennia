import '../../../data/repositories/training_repositories.dart';

/// The dose-overlay timeline's pure data prep (PROTOCOLS.md §4):
/// projects the chosen outcome's actual samples and the ACTUAL logged `Dose`
/// timeline for the same `Effect` window onto one shared, origin-relative day
/// axis — "join, never merge" (§2). Pure — no I/O, nothing stored;
/// the fl_chart widget only ever sees plain numbers built here, never a
/// `DateTime`/Drift read of its own.
///
/// [DoseRecord.tookAt] is used verbatim — the real (tz-frozen) dose instant,
/// never the plan/Schedule (§1.4). A missing/sparse outcome series degrades
/// gracefully to an empty [points] list rather than fabricating a point
/// (§4: "no fabricated data").
class EffectTimelineChartData {
  EffectTimelineChartData._({
    required this.minX,
    required this.maxX,
    required Iterable<EffectTimelinePoint> points,
    required Iterable<EffectTimelineMarker> markers,
  })  : points = List<EffectTimelinePoint>.unmodifiable(points),
        markers = List<EffectTimelineMarker>.unmodifiable(markers);

  /// Builds the chart data for [window], scoped to the SAME
  /// before-through-after span `EffectRepository.samplesFor`/`doseMarkersFor`
  /// already read [samples]/[doses] over — this only re-projects what was
  /// already fetched, it never re-queries or re-filters by time itself.
  factory EffectTimelineChartData.build({
    required EffectWindow window,
    required List<EffectSample> samples,
    required List<DoseRecord> doses,
  }) {
    final origin = window.beforeStart;
    double daysSince(DateTime at) =>
        at.difference(origin).inMicroseconds / Duration.microsecondsPerDay;

    final sortedSamples = List<EffectSample>.of(samples)
      ..sort((a, b) => a.at.compareTo(b.at));
    final sortedDoses = List<DoseRecord>.of(doses)
      ..sort((a, b) => a.tookAt.compareTo(b.tookAt));

    return EffectTimelineChartData._(
      minX: daysSince(window.beforeStart),
      maxX: daysSince(window.afterEnd),
      points: sortedSamples.map(
        (sample) => EffectTimelinePoint(
          daysSinceOrigin: daysSince(sample.at),
          value: sample.value,
        ),
      ),
      markers: sortedDoses.map(
        (dose) => EffectTimelineMarker(
          daysSinceOrigin: daysSince(dose.tookAt),
          at: dose.tookAt,
          dose: dose,
        ),
      ),
    );
  }

  /// The window's own `beforeStart`, expressed as a day offset — always `0`.
  final double minX;

  /// The window's own `afterEnd`, expressed as a day offset from
  /// `beforeStart`.
  final double maxX;

  /// The outcome's actual samples, chronological, projected onto the day
  /// axis. Empty when the outcome has no Reading in the window (never
  /// fabricated).
  final List<EffectTimelinePoint> points;

  /// The ACTUAL logged `Dose` markers, chronological, projected onto the SAME
  /// day axis as [points].
  final List<EffectTimelineMarker> markers;

  bool get hasSeries => points.isNotEmpty;

  bool get hasMarkers => markers.isNotEmpty;

  bool get hasAnyData => hasSeries || hasMarkers;

  /// `false` for a degenerate zero-length window (e.g. an instantaneous
  /// during span) — never divides by zero or renders a single point as if it
  /// were a full timeline.
  bool get hasRenderableSpan => maxX > minX;
}

/// One outcome sample, projected onto the shared timeline's day axis.
class EffectTimelinePoint {
  const EffectTimelinePoint({
    required this.daysSinceOrigin,
    required this.value,
  });

  final double daysSinceOrigin;
  final double value;
}

/// One logged `Dose`, projected onto the shared timeline's day axis. Carries
/// the source [dose] so the marker can render a label (compound + amount)
/// without a second lookup.
class EffectTimelineMarker {
  const EffectTimelineMarker({
    required this.daysSinceOrigin,
    required this.at,
    required this.dose,
  });

  final double daysSinceOrigin;
  final DateTime at;
  final DoseRecord dose;
}
