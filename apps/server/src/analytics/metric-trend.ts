// The Trend core (docs/designs/progress-overview.md, D5): a time-weighted
// moving average of a Metric's Readings. The TypeScript twin of
// apps/mobile/lib/domain/metrics/metric_trend.dart, pinned with it by
// packages/golden-vectors/vectors/m37-metric-trend.json, so the Agent readings
// list's `trendValue` and Progress Overview's Body card never disagree.
//
// Pure: no I/O, no clock. Instants are ISO-8601 strings, returned as given.
// Readings are not converted between units. Nothing returned here is stored.
// Id order is the Protocol plan core's code-unit order, which matches Dart's
// String.compareTo.

import { compareIds } from "../protocol-plan.js";

/**
 * One Reading as the Trend sees it. `value` is null when the Reading has no
 * scalar value; `metricTrend` skips it, and skips a non-finite one too.
 */
export type TrendInput = {
  id: string;
  at: string;
  value: number | null;
};

/** A kept Reading with the Trend at its time. */
export type TrendPoint = {
  id: string;
  at: string;
  value: number;
  trend: number;
};

// Each daily Reading moves the Trend 10% of the way towards it.
const DAILY_RETENTION = 0.9;
const MILLISECONDS_PER_DAY = 86_400_000;

/**
 * The Trend at each Reading with a finite value (D5), ordered by (at, id).
 * The first Trend value is the first Reading's value; each later one moves
 * `a = 1 - 0.9 ^ days` of the way from the previous Trend towards the
 * Reading, where `days` is the time since the previous kept Reading in
 * fractional days.
 */
export function metricTrend(readings: Iterable<TrendInput>): TrendPoint[] {
  const kept: { id: string; at: string; atMs: number; value: number }[] = [];
  for (const reading of readings) {
    if (reading.value !== null && Number.isFinite(reading.value)) {
      kept.push({ id: reading.id, at: reading.at, atMs: Date.parse(reading.at), value: reading.value });
    }
  }
  kept.sort((left, right) => left.atMs - right.atMs || compareIds(left.id, right.id));

  const points: TrendPoint[] = [];
  let previous: { atMs: number; trend: number } | null = null;
  for (const reading of kept) {
    let trend = reading.value;
    if (previous !== null) {
      const days = (reading.atMs - previous.atMs) / MILLISECONDS_PER_DAY;
      const weight = 1 - DAILY_RETENTION ** days;
      trend = previous.trend + weight * (reading.value - previous.trend);
    }
    previous = { atMs: reading.atMs, trend };
    points.push({ id: reading.id, at: reading.at, value: reading.value, trend });
  }
  return points;
}
