import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { normalizeMetricReading } from "../src/metric-reading-normalization.ts";

test("server Metric Reading normalization matches the shared golden vectors", async () => {
  const vector = await readReadingNormalizationVector();

  assert.ok(vector.cases.length > 0);
  assert.ok(
    vector.cases.some((vectorCase) => vectorCase.expected.rejected === true),
    "m12 has at least one rejected case"
  );
  assert.ok(
    vector.cases.some((vectorCase) => vectorCase.expected.rejected !== true),
    "m12 has at least one accepted case"
  );
  assert.ok(
    vector.cases.some((vectorCase) => typeof vectorCase.input.metric.labTestKey === "string"),
    "m12 has at least one Lab Metric case"
  );
  for (const vectorCase of vector.cases) {
    if (vectorCase.expected.rejected === true) {
      assert.throws(
        () => normalizeMetricReading(vectorCase.input),
        (error) =>
          error instanceof Error &&
          error.message.startsWith(vectorCase.expected.error),
        vectorCase.name
      );
      continue;
    }
    const result = normalizeMetricReading(vectorCase.input);
    assert.deepEqual(result, vectorCase.expected, vectorCase.name);
  }
});

test("rejects a long digit run with trailing text promptly", () => {
  assert.throws(
    () =>
      normalizeMetricReading({
        metric: { valueShape: "scalar", unit: "kilogram" },
        value: {
          shape: "scalar",
          entered: "1".repeat(100000) + "x",
          unit: "kilogram"
        },
        timeAnchor: { atTime: "2026-06-25T07:30:00Z" }
      }),
    (error) =>
      error instanceof Error &&
      error.message.startsWith("Metric Reading value must be finite")
  );
});

test("server drift check catches a perturbed normalized output", async () => {
  const vector = await readReadingNormalizationVector();
  const expected = vector.cases[0].expected;
  const perturbed = { ...expected, valueJson: "{}" };

  assert.throws(() => {
    assert.deepEqual(perturbed, expected);
  });
});

async function readReadingNormalizationVector() {
  const raw = await readFile(
    new URL(
      "../../../packages/golden-vectors/vectors/m12-reading-normalization.json",
      import.meta.url
    ),
    "utf8"
  );
  return JSON.parse(raw);
}
