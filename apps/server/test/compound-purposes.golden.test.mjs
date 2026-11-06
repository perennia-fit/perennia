import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  normalizePurposeIds,
  PurposeNameError,
  STARTER_PURPOSES,
  validatePurposeName
} from "../src/compound-purposes.ts";

// Moves with the vector file's `schemaVersion` and its schema's constant, and
// with the app runner's (apps/mobile/test/domain/compound_purposes_golden_test.dart):
// an incompatible case-shape change bumps all of them together.
const COMPOUND_PURPOSES_GOLDEN_SCHEMA_VERSION = 1;

function runValidatePurposeName(input) {
  try {
    return { accepted: validatePurposeName(input.name, input.activeNamesExcludingSelf) };
  } catch (error) {
    assert.ok(error instanceof PurposeNameError, String(error));
    return { rejected: error.code };
  }
}

// One entry per `function` the vector file uses. A case naming anything else
// fails loudly rather than being skipped.
const RUNNERS_BY_FUNCTION = new Map([
  ["starterPurposes", () => STARTER_PURPOSES.map((purpose) => ({ ...purpose }))],
  ["validatePurposeName", runValidatePurposeName],
  ["normalizePurposeIds", (input) => normalizePurposeIds(input.ids)]
]);

// The app runs the same file, so the app and an Agent agree on the starter set
// and on which Purpose names are allowed.
test("the Compound Purposes core matches the shared M40 golden vectors", async () => {
  const vector = JSON.parse(
    await readFile(
      new URL("../../../packages/golden-vectors/vectors/m40-compound-purposes.json", import.meta.url),
      "utf8"
    )
  );

  assert.equal(vector.name, "m40-compound-purposes");
  assert.equal(vector.domain, "compound-purposes");
  assert.equal(vector.schemaVersion, COMPOUND_PURPOSES_GOLDEN_SCHEMA_VERSION);
  assert.equal(vector.schema, "m40-compound-purposes.schema.json");
  assert.ok(vector.cases.length > 0);

  for (const vectorCase of vector.cases) {
    const run = RUNNERS_BY_FUNCTION.get(vectorCase.function);
    assert.ok(run, `${vectorCase.name}: unknown function ${String(vectorCase.function)}`);
    assert.deepEqual(run(vectorCase.input), vectorCase.expected, vectorCase.name);
  }
});
