/// The `Effect` view's pure delta computation (PROTOCOLS.md §4,
///) — the foundation of the Protocols payoff screen.
///
/// This is **derived analytics only**: a time-join of a chosen `Protocol`/
/// `Compound` window against an outcome's samples (existing `Metric`
/// Readings, or a performance proxy from Workout analytics), computed on
/// demand and NEVER stored, cached to disk, or synced ("join, never merge",
/// §2). Nothing in this file touches persistence — it is a pure function of
/// its inputs, which is what makes it golden-vectorable (a fixed sample
/// dataset in `test/fixtures/effect_window_golden.json` pins its behavior so a
/// later M30 agent surface can reuse the identical fixture).
///
/// The window itself is always derived from the **actual logged `Dose`s**
/// (or a `Protocol`'s declared start/end), never from a `Schedule`/plan — that
/// distinction is load-bearing (§1.4) and is enforced by the repository layer
/// that builds an [EffectWindow], not by this file, which only consumes
/// whatever start/end it is given.
///
/// [computeDoseResponseTable] is the same discipline applied to a
/// second derived view: it groups outcome behavior by the **actual logged
/// `Dose` level** (resolved active mass where the Compound strength
/// resolves it) — never by a `Schedule`/plan, which is what lets
/// dose-response work without formal phases/titration steps (§1.4, §12).
library;

import '../protocols/protocols.dart' show DoseRecord;

/// Which of the three segments an `Effect` window splits into (PROTOCOLS.md
/// §4): the period immediately BEFORE a course, the course itself (DURING),
/// and the period immediately AFTER it.
enum EffectSegment { before, during, after }

/// One observed outcome sample: a real value at a real instant. Every
/// [EffectSample] must trace back to something the user actually logged — a
/// `Metric` Reading's `atTime`/`scalarValue`, or a performance data point
/// (e.g. one Workout's computed volume) — never an invented/interpolated
/// point (PROTOCOLS.md §4: "no fabricated data").
class EffectSample {
  const EffectSample({required this.at, required this.value});

  final DateTime at;
  final double value;
}

/// An `Effect` window (PROTOCOLS.md §4): a DURING span (a `Protocol`'s
/// declared start/end, or the actual logged Dose timeline's bounds for an
/// ad-hoc `Compound`) plus the mirrored BEFORE/AFTER spans of the same
/// length immediately surrounding it.
///
/// `duringEnd == null` means an ongoing/open-ended course (PROTOCOLS.md
/// §1.4): [now] stands in for computing the mirrored before/after span length
/// and for where DURING currently ends, so an ongoing course still yields a
/// BEFORE segment and a (so-far-empty) AFTER segment rather than failing.
///
/// All three segments are half-open (`[start, end)`), so a sample landing
/// exactly on a shared boundary (e.g. a Dose logged at the exact moment a
/// Protocol ends) belongs to exactly one segment, never two.
class EffectWindow {
  EffectWindow({
    required this.duringStart,
    required this.duringEnd,
    required DateTime now,
  })  : assert(
          duringEnd == null || !duringEnd.isBefore(duringStart),
          'duringEnd must not precede duringStart.',
        ),
        duringEndOrNow = duringEnd ?? now {
    assert(
      !duringEndOrNow.isBefore(duringStart),
      'now must not precede duringStart for an ongoing window.',
    );
    final duringLength = duringEndOrNow.difference(duringStart);
    beforeStart = duringStart.subtract(duringLength);
    beforeEnd = duringStart;
    afterStart = duringEndOrNow;
    afterEnd = duringEndOrNow.add(duringLength);
  }

  /// The course's declared/derived start (a `Protocol.startDate`, or the
  /// earliest logged `Dose` for an ad-hoc `Compound` window).
  final DateTime duringStart;

  /// The course's declared/derived end, or `null` for an ongoing/open-ended
  /// course (a `Protocol` with no `endDate`).
  final DateTime? duringEnd;

  /// [duringEnd], or the clock time passed at construction when the course is
  /// still ongoing — where DURING currently ends and AFTER currently begins.
  final DateTime duringEndOrNow;

  bool get isOngoing => duringEnd == null;

  late final DateTime beforeStart;
  late final DateTime beforeEnd;
  late final DateTime afterStart;
  late final DateTime afterEnd;

  /// Classifies [at] into the segment it falls in, or `null` when it falls
  /// outside all three (further in the past than BEFORE, or further in the
  /// future than AFTER) — such a sample is silently excluded, never
  /// reassigned to the nearest segment.
  EffectSegment? segmentFor(DateTime at) {
    if (!at.isBefore(beforeStart) && at.isBefore(beforeEnd)) {
      return EffectSegment.before;
    }
    if (!at.isBefore(duringStart) && at.isBefore(duringEndOrNow)) {
      return EffectSegment.during;
    }
    if (!at.isBefore(afterStart) && at.isBefore(afterEnd)) {
      return EffectSegment.after;
    }
    return null;
  }
}

/// One segment's aggregate over whatever [EffectSample]s landed in it. A
/// segment with zero samples has a `null` [mean] — degrading gracefully
/// rather than fabricating a value (PROTOCOLS.md §4).
class EffectSegmentStats {
  const EffectSegmentStats({required this.mean, required this.sampleCount});

  final double? mean;
  final int sampleCount;

  bool get hasData => sampleCount > 0;
}

/// The before/during/after aggregates for ONE outcome over ONE [EffectWindow]
/// — the payoff of the `Effect` view (PROTOCOLS.md §4). Strictly descriptive:
/// these are deltas in the outcome's own unit, never a causal or efficacy
/// claim — the caller is responsible for framing them that way.
class OutcomeEffectResult {
  const OutcomeEffectResult({
    required this.before,
    required this.during,
    required this.after,
  });

  final EffectSegmentStats before;
  final EffectSegmentStats during;
  final EffectSegmentStats after;

  /// DURING mean minus BEFORE mean — "what changed once the course started."
  /// `null` when either segment has no samples (never fabricated).
  double? get duringDelta {
    final beforeMean = before.mean;
    final duringMean = during.mean;
    if (beforeMean == null || duringMean == null) {
      return null;
    }
    return duringMean - beforeMean;
  }

  /// AFTER mean minus DURING mean — "what changed once the course ended."
  /// `null` when either segment has no samples.
  double? get afterDelta {
    final duringMean = during.mean;
    final afterMean = after.mean;
    if (duringMean == null || afterMean == null) {
      return null;
    }
    return afterMean - duringMean;
  }

  /// AFTER mean minus BEFORE mean — the whole-window "before vs. after" read.
  /// `null` when either segment has no samples.
  double? get overallDelta {
    final beforeMean = before.mean;
    final afterMean = after.mean;
    if (beforeMean == null || afterMean == null) {
      return null;
    }
    return afterMean - beforeMean;
  }
}

/// The `Effect` delta computation (PROTOCOLS.md §4): buckets
/// [samples] into [window]'s before/during/after segments and averages each.
/// Pure — no I/O, nothing stored — which is what makes it golden-vectorable.
OutcomeEffectResult computeOutcomeEffect({
  required EffectWindow window,
  required List<EffectSample> samples,
}) {
  final beforeValues = <double>[];
  final duringValues = <double>[];
  final afterValues = <double>[];

  for (final sample in samples) {
    switch (window.segmentFor(sample.at)) {
      case EffectSegment.before:
        beforeValues.add(sample.value);
      case EffectSegment.during:
        duringValues.add(sample.value);
      case EffectSegment.after:
        afterValues.add(sample.value);
      case null:
        break;
    }
  }

  return OutcomeEffectResult(
    before: _segmentStats(beforeValues),
    during: _segmentStats(duringValues),
    after: _segmentStats(afterValues),
  );
}

EffectSegmentStats _segmentStats(List<double> values) {
  if (values.isEmpty) {
    return const EffectSegmentStats(mean: null, sampleCount: 0);
  }
  final sum = values.fold<double>(0, (total, value) => total + value);
  return EffectSegmentStats(
    mean: sum / values.length,
    sampleCount: values.length,
  );
}

/// One row of the `Effect` view's dose-response table (PROTOCOLS.md §4,
///): one distinct ACTUAL logged `Dose` level — [compoundName] +
/// [levelLabel] — paired with the outcome behavior observed at that level
/// over the window. Strictly descriptive: a mean + sample count,
/// never a causal/efficacy claim.
class DoseResponseRow {
  const DoseResponseRow({
    required this.compoundName,
    required this.levelLabel,
    required this.levelValue,
    required this.doseCount,
    required this.stats,
  });

  /// The Dose's snapshotted Compound name (self-describing, §1.1) — kept
  /// alongside the level so a multi-Compound `Protocol` stack's levels never
  /// get conflated across different Compounds that happen to share a
  /// numeric amount.
  final String compoundName;

  /// The dose level as the user reads it (e.g. "5 mg", "1000 IU") — the
  /// resolved active mass when the Dose's Compound strength
  /// resolves it, else the entered amount + unit verbatim.
  final String levelLabel;

  /// The same level's bare numeric value, kept only to sort rows
  /// numerically within a Compound (never shown on its own — [levelLabel]
  /// is always the display form, since it carries the unit).
  final double levelValue;

  /// How many ACTUAL logged `Dose`s landed at this level.
  final int doseCount;

  /// The outcome's samples attributed to this level, aggregated the same
  /// way as an `Effect` window segment (`null` mean when none attribute —
  /// degrading gracefully, never fabricated, PROTOCOLS.md §4).
  final EffectSegmentStats stats;
}

/// Groups [samples] by the ACTUAL logged `Dose` level in [doses] — NEVER by
/// the `Schedule`/plan (PROTOCOLS.md §1.4, load-bearing) — for the `Effect`
/// view's dose-response table (§4).
///
/// Each [DoseRecord] contributes a level: its [DoseRecord.resolvedActiveMass]
/// when the Compound strength resolves it, else the amount +
/// unit as entered — so a Dose logged without a resolvable strength still
/// groups fine (non-blocking, §1.3). Doses sharing a Compound + level are
/// merged into one row ([DoseResponseRow.doseCount] counts them).
///
/// Each outcome [EffectSample] is attributed to the level of the MOST
/// RECENT Dose at or before its instant — "what level was last taken when
/// this was observed." A sample with no preceding Dose in [doses] is
/// excluded, never attributed to an invented baseline (§4: "no fabricated
/// data"). A dose level with no attributed samples still appears (dose
/// count visible, `stats.mean` null) rather than being silently dropped.
///
/// Pure — no I/O, nothing stored — which is what makes it
/// golden-vectorable, mirroring [computeOutcomeEffect].
List<DoseResponseRow> computeDoseResponseTable({
  required List<DoseRecord> doses,
  required List<EffectSample> samples,
}) {
  if (doses.isEmpty) {
    return const <DoseResponseRow>[];
  }

  final sortedDoses = List<DoseRecord>.of(doses)
    ..sort((a, b) => a.tookAt.compareTo(b.tookAt));

  final order = <String>[];
  final compoundNameByKey = <String, String>{};
  final labelByKey = <String, String>{};
  final valueByKey = <String, double>{};
  final doseCountByKey = <String, int>{};
  final valuesByKey = <String, List<double>>{};

  String keyFor(DoseRecord dose, String label) => '${dose.compoundName}|$label';

  for (final dose in sortedDoses) {
    final level = _doseLevel(dose);
    final key = keyFor(dose, level.label);
    if (!doseCountByKey.containsKey(key)) {
      order.add(key);
      compoundNameByKey[key] = dose.compoundName;
      labelByKey[key] = level.label;
      valueByKey[key] = level.value;
      doseCountByKey[key] = 0;
      valuesByKey[key] = <double>[];
    }
    doseCountByKey[key] = doseCountByKey[key]! + 1;
  }

  for (final sample in samples) {
    DoseRecord? mostRecent;
    for (final dose in sortedDoses) {
      if (dose.tookAt.isAfter(sample.at)) {
        break;
      }
      mostRecent = dose;
    }
    if (mostRecent == null) {
      continue;
    }
    final level = _doseLevel(mostRecent);
    final key = keyFor(mostRecent, level.label);
    valuesByKey[key]!.add(sample.value);
  }

  final rows = order
      .map(
        (key) => DoseResponseRow(
          compoundName: compoundNameByKey[key]!,
          levelLabel: labelByKey[key]!,
          levelValue: valueByKey[key]!,
          doseCount: doseCountByKey[key]!,
          stats: _segmentStats(valuesByKey[key]!),
        ),
      )
      .toList(growable: false)
    ..sort((a, b) {
      final byCompound = a.compoundName.compareTo(b.compoundName);
      if (byCompound != 0) {
        return byCompound;
      }
      return a.levelValue.compareTo(b.levelValue);
    });
  return List<DoseResponseRow>.unmodifiable(rows);
}

/// The label + bare numeric value for one Dose's level (PROTOCOLS.md §1.3,
///): the resolved active mass when it resolves, else the entered
/// amount + unit — mirrors [DoseRecord.amountLabel]/[DoseRecord.resolvedActiveMass].
({String label, double value}) _doseLevel(DoseRecord dose) {
  final resolved = dose.resolvedActiveMass;
  if (resolved != null) {
    return (label: resolved.label, value: resolved.value);
  }
  return (label: dose.amountLabel, value: dose.amountValue);
}
