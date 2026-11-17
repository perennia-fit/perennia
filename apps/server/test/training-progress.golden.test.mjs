import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  summarizeTrainingWeek,
  trainingDays,
  trainingWeek
} from "../src/analytics/training-progress.ts";

// Moves with the vector file's `schemaVersion` and its schema's constant, and
// with the app runner's (apps/mobile/test/domain/training_progress_golden_test.dart):
// an incompatible case-shape change bumps all of them together.
const TRAINING_PROGRESS_GOLDEN_SCHEMA_VERSION = 1;

// One entry per `function` the vector file uses. A case naming anything else
// fails loudly rather than being skipped.
const RUNNERS_BY_FUNCTION = new Map([
  ["training_week", (input) => argumentOrResult(() => trainingWeek(input))],
  ["summarize_training_week", (input) => summarizeTrainingWeek(input.days)],
  ["training_days", (input) => argumentOrResult(() => trainingDays(input))]
]);

// The app runs the same file, so an Agent read and Progress Overview never
// disagree about how the week went or which dates were Trained Days.
test("the training progress core matches the shared M37 golden vectors", async () => {
  const vector = JSON.parse(
    await readFile(
      new URL(
        "../../../packages/golden-vectors/vectors/m37-training-progress.json",
        import.meta.url
      ),
      "utf8"
    )
  );

  assert.equal(vector.name, "m37-training-progress");
  assert.equal(vector.domain, "training-progress");
  assert.equal(vector.schemaVersion, TRAINING_PROGRESS_GOLDEN_SCHEMA_VERSION);
  assert.equal(vector.schema, "m37-training-progress.schema.json");
  assert.ok(vector.cases.length > 0);

  for (const vectorCase of vector.cases) {
    const run = RUNNERS_BY_FUNCTION.get(vectorCase.function);
    assert.ok(run, `${vectorCase.name}: unknown function ${String(vectorCase.function)}`);
    assert.deepEqual(run(vectorCase.input), vectorCase.expected, vectorCase.name);
  }
});

// The core rejects an argument with a RangeError, as the Dart twin throws an
// ArgumentError; both map to the vector's {"error": "argument"}.
function argumentOrResult(run) {
  try {
    return run();
  } catch (error) {
    if (error instanceof RangeError) {
      return { error: "argument" };
    }
    throw error;
  }
}
