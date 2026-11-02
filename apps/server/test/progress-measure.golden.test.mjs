import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { newBestsBetween, progressSeries } from "../src/analytics/progress-measure.ts";

// Moves with the vector file's `schemaVersion` and its schema's constant, and
// with the app runner's (apps/mobile/test/domain/progress_measure_golden_test.dart):
// an incompatible case-shape change bumps all of them together.
const PROGRESS_MEASURE_GOLDEN_SCHEMA_VERSION = 1;

// One entry per `function` the vector file uses. A case naming anything else
// fails loudly rather than being skipped. The vector gives the profile's
// dimensions as `dimensions`, as m4-analytics-pr-e1rm-volume.json does; the
// engine's profile calls them `type`.
const RUNNERS_BY_FUNCTION = new Map([
  [
    "progress_series",
    (input) =>
      progressSeries({
        exerciseId: input.exerciseId,
        profile: {
          type: input.profile.dimensions,
          loadMode: input.profile.loadMode,
          recordProfile: input.profile.recordProfile
        },
        workouts: input.workouts
      })
  ],
  ["new_bests_between", (input) => newBestsBetween(input.series, input.from, input.to)]
]);

// The app runs the same file, so an Agent read and Progress Overview never
// disagree about an exercise's Progress Measure or which Workouts were New
// Bests.
test("the Progress Measure core matches the shared M37 golden vectors", async () => {
  const vector = JSON.parse(
    await readFile(
      new URL(
        "../../../packages/golden-vectors/vectors/m37-progress-measure.json",
        import.meta.url
      ),
      "utf8"
    )
  );

  assert.equal(vector.name, "m37-progress-measure");
  assert.equal(vector.domain, "progress-measure");
  assert.equal(vector.schemaVersion, PROGRESS_MEASURE_GOLDEN_SCHEMA_VERSION);
  assert.equal(vector.schema, "m37-progress-measure.schema.json");
  assert.ok(vector.cases.length > 0);

  for (const vectorCase of vector.cases) {
    const run = RUNNERS_BY_FUNCTION.get(vectorCase.function);
    assert.ok(run, `${vectorCase.name}: unknown function ${String(vectorCase.function)}`);
    assert.deepEqual(run(vectorCase.input), vectorCase.expected, vectorCase.name);
  }
});
