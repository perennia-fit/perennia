import '../../../data/repositories/training_repositories.dart';

/// The Consistency chart's pure data prep (D6, Phase 4 file 42): each logged
/// Dose's time of day against the planned times, for one Compound over a date
/// range. Pure, with no I/O and nothing stored: the fl_chart widget only sees
/// the plain numbers built here, the way `EffectTimelineChartData` feeds the
/// Effect timeline.
///
/// **Axes.** X is the date: day `i` of the range spans `[i, i + 1)`, so a
/// planned time that applies over several days is a segment as wide as them,
/// and a Dose sits in the middle of its day. Y is the time of day in minutes
/// after local midnight, `0` to [minutesPerDay]. Untimed planned doses have
/// no time, so they get a band of their own above the day, from
/// [minutesPerDay] to [untimedBandTop], labelled "Any time" by the widget.
///
/// **What is drawn.**
/// * Each logged Dose of the range is a point at its frozen local date and
///   time. A Dose that filled no slot of a day with a Day Status is an extra
///   ([ConsistencyDosePoint.isExtra]); every other Dose is not.
/// * Each planned time is a horizontal segment over the run of consecutive
///   days it is planned on, read from the PlanDays, so a Schedule Version
///   change moves the line on the day it applies from (CUJ 6). Two Protocols
///   planning the same time on a day draw one segment.
/// * Days with an untimed planned dose are a segment in the untimed band.
/// * Paused and off-cycle days, by their Day Status, are shaded runs that
///   carry their kind for the widget to label (CUJ 3 and 5). A day after
///   today has no Day Status, so it is never shaded.
class ConsistencyChartData {
  ConsistencyChartData._({
    required this.from,
    required this.dayCount,
    required this.hasUntimedBand,
    required Iterable<ConsistencyDosePoint> points,
    required Iterable<ConsistencyPlannedSegment> plannedSegments,
    required Iterable<ConsistencyDayRun> untimedRuns,
    required Iterable<ConsistencyShade> shades,
  })  : points = List<ConsistencyDosePoint>.unmodifiable(points),
        plannedSegments =
            List<ConsistencyPlannedSegment>.unmodifiable(plannedSegments),
        untimedRuns = List<ConsistencyDayRun>.unmodifiable(untimedRuns),
        shades = List<ConsistencyShade>.unmodifiable(shades);

  /// Builds the chart for [from] through [to], inclusive, from one
  /// Compound's [planDays], [dayStatuses] and [doses]: the same read the day
  /// list shows. Anything dated outside the range is left out; nothing is
  /// re-queried here.
  factory ConsistencyChartData.build({
    required ProtocolDayDate from,
    required ProtocolDayDate to,
    required Iterable<PlanDay> planDays,
    required Iterable<DayStatus> dayStatuses,
    required Iterable<DoseRecord> doses,
  }) {
    if (from.compareTo(to) > 0) {
      throw ArgumentError('A chart range starts on or before its end.');
    }
    final dayCount = to.daysBetween(from) + 1;
    int? indexOf(ProtocolDayDate date) {
      final index = date.daysBetween(from);
      return index < 0 || index >= dayCount ? null : index;
    }

    // Which statuses exist, so a Dose is an extra only on a day that has
    // slots to fill (D6: a Dose with no PlanDay is never an extra).
    final statusByIndex = <int, DayStatus>{};
    final filledDoseIds = <String>{};
    for (final status in dayStatuses) {
      final index = indexOf(status.localDate);
      if (index == null) {
        continue;
      }
      statusByIndex[index] = status;
      for (final fill in status.fills) {
        final doseId = fill.doseId;
        if (doseId != null) {
          filledDoseIds.add(doseId);
        }
      }
    }

    final points = <ConsistencyDosePoint>[];
    for (final dose in doses) {
      final index = indexOf(dose.localDate);
      if (index == null) {
        continue;
      }
      points.add(
        ConsistencyDosePoint(
          x: index + 0.5,
          y: planLocalTimeMinutes(dose.localTime).toDouble(),
          dose: dose,
          isExtra: statusByIndex.containsKey(index) &&
              !filledDoseIds.contains(dose.id),
        ),
      );
    }
    points.sort((a, b) {
      final byX = a.x.compareTo(b.x);
      if (byX != 0) {
        return byX;
      }
      final byY = a.y.compareTo(b.y);
      return byY != 0 ? byY : a.dose.id.compareTo(b.dose.id);
    });

    // Each day's distinct planned times, and whether it plans an untimed dose.
    final timedDaysByTime = <String, Set<int>>{};
    final untimedDays = <int>{};
    for (final day in planDays) {
      final index = indexOf(day.localDate);
      if (index == null) {
        continue;
      }
      for (final planned in day.planned) {
        final time = planned.localTime;
        if (time == null) {
          untimedDays.add(index);
        } else {
          timedDaysByTime.putIfAbsent(time, () => <int>{}).add(index);
        }
      }
    }

    final plannedSegments = <ConsistencyPlannedSegment>[
      for (final entry in timedDaysByTime.entries)
        for (final run in _runs(entry.value))
          ConsistencyPlannedSegment(
            run: run,
            localTime: entry.key,
            y: planLocalTimeMinutes(entry.key).toDouble(),
          ),
    ]..sort((a, b) {
        final byStart = a.run.startIndex.compareTo(b.run.startIndex);
        return byStart != 0 ? byStart : a.y.compareTo(b.y);
      });

    final shadeKinds = <ConsistencyShadeKind, Set<int>>{};
    for (final entry in statusByIndex.entries) {
      final kind = switch (entry.value.status) {
        DayStatusKind.paused => ConsistencyShadeKind.paused,
        DayStatusKind.offCycle => ConsistencyShadeKind.offCycle,
        _ => null,
      };
      if (kind != null) {
        shadeKinds.putIfAbsent(kind, () => <int>{}).add(entry.key);
      }
    }
    final shades = <ConsistencyShade>[
      for (final entry in shadeKinds.entries)
        for (final run in _runs(entry.value))
          ConsistencyShade(run: run, kind: entry.key),
    ]..sort((a, b) => a.run.startIndex.compareTo(b.run.startIndex));

    return ConsistencyChartData._(
      from: from,
      dayCount: dayCount,
      hasUntimedBand: untimedDays.isNotEmpty,
      points: points,
      plannedSegments: plannedSegments,
      untimedRuns: _runs(untimedDays),
      shades: shades,
    );
  }

  /// Minutes in a day: the top of the timed part of the Y axis.
  static const double minutesPerDay = 24 * 60;

  /// How tall the untimed band above the day is, in the Y axis's minutes.
  static const double untimedBandHeight = 4 * 60;

  /// The top of the untimed band.
  static const double untimedBandTop = minutesPerDay + untimedBandHeight;

  /// Where an untimed segment is drawn: the middle of the band.
  static const double untimedBandY = minutesPerDay + untimedBandHeight / 2;

  /// The first date of the range: day `0` on the X axis.
  final ProtocolDayDate from;

  /// The number of days in the range, so the X axis runs `0` to [maxX].
  final int dayCount;

  /// Whether any day of the range plans an untimed dose, so the Y axis
  /// reaches up to [untimedBandTop].
  final bool hasUntimedBand;

  /// Every logged Dose of the range, by date, then time, then id.
  final List<ConsistencyDosePoint> points;

  /// Every planned time, as a run of consecutive days, by start, then time.
  final List<ConsistencyPlannedSegment> plannedSegments;

  /// The runs of consecutive days that plan an untimed dose, by start.
  final List<ConsistencyDayRun> untimedRuns;

  /// The paused and off-cycle runs, by start.
  final List<ConsistencyShade> shades;

  double get minX => 0;
  double get maxX => dayCount.toDouble();
  double get minY => 0;
  double get maxY => hasUntimedBand ? untimedBandTop : minutesPerDay;

  /// Whether there is anything to draw: a Dose, a planned dose, or a
  /// shaded day.
  bool get hasAnyData =>
      points.isNotEmpty ||
      plannedSegments.isNotEmpty ||
      untimedRuns.isNotEmpty ||
      shades.isNotEmpty;

  /// The date of day [index] of the range.
  ProtocolDayDate dateAt(int index) => from.addDays(index);
}

/// A run of consecutive days of the range, `startIndex` through `endIndex`,
/// both inclusive; on the X axis it spans [startX] to [endX].
class ConsistencyDayRun {
  const ConsistencyDayRun({required this.startIndex, required this.endIndex});

  final int startIndex;
  final int endIndex;

  double get startX => startIndex.toDouble();
  double get endX => endIndex + 1.0;
  int get dayCount => endIndex - startIndex + 1;

  @override
  bool operator ==(Object other) =>
      other is ConsistencyDayRun &&
      other.startIndex == startIndex &&
      other.endIndex == endIndex;

  @override
  int get hashCode => Object.hash(startIndex, endIndex);

  @override
  String toString() => 'ConsistencyDayRun($startIndex..$endIndex)';
}

/// One logged Dose: in the middle of its day ([x]) at its time of day ([y]).
class ConsistencyDosePoint {
  const ConsistencyDosePoint({
    required this.x,
    required this.y,
    required this.dose,
    required this.isExtra,
  });

  final double x;
  final double y;
  final DoseRecord dose;

  /// True when the Dose filled no slot of a day that has a Day Status.
  final bool isExtra;
}

/// One planned time over a run of consecutive days it is planned on.
class ConsistencyPlannedSegment {
  const ConsistencyPlannedSegment({
    required this.run,
    required this.localTime,
    required this.y,
  });

  final ConsistencyDayRun run;

  /// The planned `HH:MM` time.
  final String localTime;
  final double y;
}

/// Why a run of days is shaded: its Day Status.
enum ConsistencyShadeKind { paused, offCycle }

/// A run of paused or off-cycle days.
class ConsistencyShade {
  const ConsistencyShade({required this.run, required this.kind});

  final ConsistencyDayRun run;
  final ConsistencyShadeKind kind;
}

/// The runs of consecutive indexes in [indexes], in order.
List<ConsistencyDayRun> _runs(Iterable<int> indexes) {
  final sorted = indexes.toSet().toList()..sort();
  final runs = <ConsistencyDayRun>[];
  for (var position = 0; position < sorted.length;) {
    final start = sorted[position];
    var end = start;
    position += 1;
    while (position < sorted.length && sorted[position] == end + 1) {
      end = sorted[position];
      position += 1;
    }
    runs.add(ConsistencyDayRun(startIndex: start, endIndex: end));
  }
  return runs;
}
