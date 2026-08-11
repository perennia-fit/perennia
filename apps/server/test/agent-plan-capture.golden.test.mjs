import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  captureAgentWorkout,
  compareAgentTemplateToWorkout,
} from "../src/agent-plan-capture.ts";

test("agent capture matches the shared M33 Workout capture vectors", async () => {
  const vector = await readVector("m33-workout-capture.json");

  assert.equal(vector.domain, "workout-capture");
  assert.equal(vector.schemaVersion, 1);
  for (const vectorCase of vector.cases) {
    assert.deepEqual(
      captureAgentWorkout(vectorCase.input),
      vectorCase.expected,
      vectorCase.name,
    );
  }
});

test("agent update matches the shared M34 divergence/update vectors", async () => {
  const vector = await readVector("m34-plan-divergence.json");

  assert.equal(vector.domain, "plan-divergence");
  assert.equal(vector.schemaVersion, 1);
  for (const vectorCase of vector.cases) {
    assert.deepEqual(
      compareAgentTemplateToWorkout({
        template: vectorCase.template,
        workout: vectorCase.workout,
      }),
      vectorCase.expected,
      vectorCase.name,
    );
  }
});

async function readVector(name) {
  return JSON.parse(
    await readFile(
      new URL(`../../../packages/golden-vectors/vectors/${name}`, import.meta.url),
      "utf8",
    ),
  );
}
