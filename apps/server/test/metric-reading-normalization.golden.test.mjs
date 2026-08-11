import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { normalizeMetricReading } from "../src/metric-reading-normalization.ts";

test("server Metric Reading normalization matches the shared golden vectors", async () => {
  const vector = await readReadingNormalizationVector();

  assert.ok(vector.cases.length > 0);
  for (const vectorCase of vector.cases) {
    const result = normalizeMetricReading(vectorCase.input);
    assert.deepEqual(result, vectorCase.expected, vectorCase.name);
  }
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
