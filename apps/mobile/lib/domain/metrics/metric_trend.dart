/// The Trend core (docs/designs/progress-overview.md, D5): a time-weighted
/// moving average of a Metric's Readings, so a single day's swing on the
/// scale moves the line little while a lasting change shows within about two
/// weeks. Progress Overview's Body card reads these functions, and so does
/// the Agent readings list when asked for `includeTrend`.
///
/// Pure: no I/O, no clock. Readings are not converted between units. Nothing
/// returned here is stored or synced.
///
/// [metricTrend] is pinned against the TypeScript twin
/// (`apps/server/src/analytics/metric-trend.ts`) by
/// `packages/golden-vectors/vectors/m37-metric-trend.json`. [trendChange] is
/// Dart only, because only the Body card shows a change over the period.
library;

import 'dart:math' as math;

/// The fraction of the gap a Reading one day after the previous one leaves
/// unclosed: each daily Reading moves the Trend 10% of the way towards it.
const double _dailyRetention = 0.9;

const int _millisecondsPerDay = 86400000;

/// One Reading as the Trend sees it. [value] is null when the Reading has no
/// scalar value; [metricTrend] skips it, and skips a non-finite one too.
///
/// Not the metrics feature's `MetricReadingPoint`: the core must not depend
/// on feature record types.
final class TrendInput {
  const TrendInput({required this.id, required this.at, required this.value});

  final String id;
  final DateTime at;
  final double? value;
}

/// A kept Reading with the Trend at its time.
final class TrendPoint {
  const TrendPoint({
    required this.id,
    required this.at,
    required this.value,
    required this.trend,
  });

  final String id;
  final DateTime at;
  final double value;
  final double trend;
}

/// The Trend at each Reading with a finite value (D5), ordered by (at, id).
///
/// The first Trend value is the first Reading's value; each later one moves
/// `a = 1 - 0.9 ^ days` of the way from the previous Trend towards the
/// Reading, where `days` is the time since the previous kept Reading in
/// fractional days. Time is taken in milliseconds, as the TypeScript twin
/// has it, so the two agree on sub-millisecond instants.
List<TrendPoint> metricTrend(Iterable<TrendInput> readings) {
  final kept = <TrendInput>[
    for (final reading in readings)
      if (reading.value case final double value when value.isFinite) reading,
  ]..sort((a, b) {
      final byAt = a.at.compareTo(b.at);
      return byAt != 0 ? byAt : a.id.compareTo(b.id);
    });

  final points = <TrendPoint>[];
  for (final reading in kept) {
    final value = reading.value!;
    final double trend;
    if (points.isEmpty) {
      trend = value;
    } else {
      final previous = points.last;
      final days = (reading.at.millisecondsSinceEpoch -
              previous.at.millisecondsSinceEpoch) /
          _millisecondsPerDay;
      final weight = 1 - math.pow(_dailyRetention, days);
      trend = previous.trend + weight * (value - previous.trend);
    }
    points.add(
      TrendPoint(id: reading.id, at: reading.at, value: value, trend: trend),
    );
  }
  return List<TrendPoint>.unmodifiable(points);
}

/// The Trend's change over the period [start, end) (D5), or null when no
/// point falls in it. [points] are in [metricTrend]'s order.
///
/// [start] is the beginning of the period's first local day and [end] the
/// beginning of the day after its last. The change is the Trend at the last
/// point before [end] minus the Trend at the last point before [start]; with
/// no point before [start], the first point in the period is the baseline.
double? trendChange(List<TrendPoint> points, DateTime start, DateTime end) {
  TrendPoint? before;
  TrendPoint? first;
  TrendPoint? last;
  for (final point in points) {
    if (point.at.isBefore(start)) {
      before = point;
    } else if (point.at.isBefore(end)) {
      first ??= point;
      last = point;
    } else {
      break;
    }
  }
  if (last == null) {
    return null;
  }
  return last.trend - (before ?? first!).trend;
}
