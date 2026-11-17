import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { metricTrend } from "../src/analytics/metric-trend.ts";

// Moves with the vector file's `schemaVersion` and its schema's constant, and
// with the app runner's (apps/mobile/test/domain/metric_trend_golden_test.dart):
// an incompatible case-shape change bumps all of them together.
const METRIC_TREND_GOLDEN_SCHEMA_VERSION = 1;

// JSON has no non-finite numbers, so the vector spells them as strings.
const NON_FINITE_BY_NAME = new Map([
  ["NaN", Number.NaN],
  ["Infinity", Number.POSITIVE_INFINITY],
  ["-Infinity", Number.NEGATIVE_INFINITY]
]);

function decodeValue(value) {
  if (typeof value !== "string") {
    return value;
  }
  assert.ok(NON_FINITE_BY_NAME.has(value), `unknown non-finite value ${value}`);
  return NON_FINITE_BY_NAME.get(value);
}

// One entry per `function` the vector file uses. A case naming anything else
// fails loudly rather than being skipped.
const RUNNERS_BY_FUNCTION = new Map([
  [
    "metric_trend",
    (input) =>
      metricTrend(input.readings.map((reading) => ({ ...reading, value: decodeValue(reading.value) })))
  ]
]);

// `trend` is compared within the file's tolerance, because pow can differ in
// the last bit between Dart and JavaScript; everything else exactly.
function assertTrendPoints(actual, expected, tolerance, name) {
  const withoutTrend = (points) => points.map(({ trend: _trend, ...rest }) => rest);
  assert.deepEqual(withoutTrend(actual), withoutTrend(expected), name);
  actual.forEach((point, index) => {
    const want = expected[index].trend;
    assert.ok(
      Math.abs(point.trend - want) <= tolerance,
      `${name}: point ${index} trend ${point.trend} is not within ${tolerance} of ${want}`
    );
  });
}

// The app runs the same file, so the Agent readings list's `trendValue` and
// Progress Overview's Body card never disagree about a Metric's Trend.
test("the Trend core matches the shared M37 golden vectors", async () => {
  const vector = JSON.parse(
    await readFile(
      new URL("../../../packages/golden-vectors/vectors/m37-metric-trend.json", import.meta.url),
      "utf8"
    )
  );

  assert.equal(vector.name, "m37-metric-trend");
  assert.equal(vector.domain, "metric-trend");
  assert.equal(vector.schemaVersion, METRIC_TREND_GOLDEN_SCHEMA_VERSION);
  assert.equal(vector.schema, "m37-metric-trend.schema.json");
  assert.equal(vector.tolerance, 1e-9);
  assert.ok(vector.cases.length > 0);

  for (const vectorCase of vector.cases) {
    const run = RUNNERS_BY_FUNCTION.get(vectorCase.function);
    assert.ok(run, `${vectorCase.name}: unknown function ${String(vectorCase.function)}`);
    assertTrendPoints(run(vectorCase.input), vectorCase.expected, vector.tolerance, vectorCase.name);
  }
});
