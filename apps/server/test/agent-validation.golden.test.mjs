import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";

import {
  DOSE_VALIDATION_LIMITS,
  PLAN_VALIDATION_LIMITS,
  PREDEFINED_SET_VALIDATION_LIMITS,
  SETTINGS_VALIDATION_LIMITS,
  validateAgentDose,
  validateAgentFoodEntry,
  validateAgentNutritionGoalTargets,
  validateAgentPrescription,
  validateAgentRoutineCadence,
  validateAgentPredefinedSet,
  validateAgentSet,
  validateAgentSettings,
  validateAgentTemplateGroup
} from "../src/index.ts";

const SHARED_VALIDATION_DOMAINS = new Set([
  "set-validation",
  "nutrient-validation",
  "dose-validation",
  "nutrition-goal-validation",
  "plan-validation",
  "predefined-set-validation",
  "settings-validation"
]);

test("server validation matches the shared golden vectors", async () => {
  const vectorsUrl = new URL("../../../packages/golden-vectors/vectors/", import.meta.url);
  const filenames = (await readdir(vectorsUrl)).filter((name) => name.endsWith(".json"));

  for (const filename of filenames) {
    const vector = JSON.parse(await readFile(new URL(filename, vectorsUrl), "utf8"));
    if (!SHARED_VALIDATION_DOMAINS.has(vector.domain)) {
      continue;
    }

    // The TS limits and the vector's limits block must agree exactly so the
    // implementation and the spec stay in lockstep.
    if (vector.domain === "dose-validation") {
      assert.deepEqual(vector.limits, DOSE_VALIDATION_LIMITS, `${filename} limits`);
    }
    if (vector.domain === "predefined-set-validation") {
      assert.deepEqual(
        vector.limits,
        PREDEFINED_SET_VALIDATION_LIMITS,
        `${filename} limits`
      );
    }
    if (vector.domain === "plan-validation") {
      assert.deepEqual(
        vector.limits,
        PLAN_VALIDATION_LIMITS,
        `${filename} limits`
      );
    }
    if (vector.domain === "settings-validation") {
      assert.deepEqual(
        vector.limits,
        SETTINGS_VALIDATION_LIMITS,
        `${filename} limits`
      );
    }

    for (const vectorCase of vector.cases) {
      const result =
        vector.domain === "set-validation"
          ? validateAgentSet(vectorCase.input)
          : vector.domain === "nutrient-validation"
            ? validateAgentFoodEntry(vectorCase.input)
            : vector.domain === "nutrition-goal-validation"
              ? validateAgentNutritionGoalTargets(vectorCase.input)
              : vector.domain === "predefined-set-validation"
                ? validateAgentPredefinedSet(vectorCase.input)
                : vector.domain === "plan-validation"
                  ? validatePlanVectorCase(vectorCase)
                : vector.domain === "settings-validation"
                  ? validateAgentSettings(vectorCase.input)
                  : validateAgentDose(vectorCase.input);
      const expected = vectorCase.expected;
      const reason = `${filename} ${vectorCase.name}`;

      assert.equal(result.errors.length === 0, expected.accepted, reason);
      assert.deepEqual(
        result.warnings.map((warning) => warning.rule),
        expected.warningRules,
        reason
      );
      assert.deepEqual(
        result.errors.map((error) => error.rule),
        expected.errorRules,
        reason
      );
    }
  }
});

test("plan validation rejects non-finite rest", () => {
  const result = validateAgentPrescription({
    mode: "copyPrevious",
    dimensions: ["duration"],
    loadMode: "added",
    repeat: 1,
    restAfterSeconds: Number.POSITIVE_INFINITY,
    values: {}
  });
  assert.deepEqual(
    result.errors.map((issue) => issue.rule),
    ["prescription_rest_after_finite"]
  );
});

test("Template Group validation rejects fractional and non-finite rounds", () => {
  for (const [rounds, expectedRule] of [
    [1.5, "template_group_rounds_integer"],
    [Number.POSITIVE_INFINITY, "template_group_rounds_finite"],
    [Number.NaN, "template_group_rounds_finite"]
  ]) {
    const result = validateAgentTemplateGroup({
      name: "Circuit",
      colorHex: "#2F6FED",
      rounds,
      memberIds: ["template-exercise-1", "template-exercise-2"]
    });
    assert.deepEqual(
      result.errors.map((issue) => issue.rule),
      [expectedRule],
      `rounds=${String(rounds)}`
    );
    assert.deepEqual(result.warnings, []);
  }
});

test("Routine Cadence validation rejects non-finite window and slots", () => {
  const window = validateAgentRoutineCadence({
    cadenceKind: "rotating",
    cadenceWindow: Number.POSITIVE_INFINITY,
    slots: [1]
  });
  assert.ok(
    window.errors.some((validationIssue) =>
      validationIssue.rule === "cadence_window_finite")
  );

  const slot = validateAgentRoutineCadence({
    cadenceKind: "weekly",
    cadenceWindow: null,
    slots: [Number.NaN]
  });
  assert.ok(
    slot.errors.some((validationIssue) =>
      validationIssue.rule === "routine_entry_slot_finite")
  );
});

function validatePlanVectorCase(vectorCase) {
  if (vectorCase.validator === "prescription") {
    return validateAgentPrescription(vectorCase.input);
  }
  if (vectorCase.validator === "templateGroup") {
    return validateAgentTemplateGroup(vectorCase.input);
  }
  if (vectorCase.validator === "routineCadence") {
    return validateAgentRoutineCadence(vectorCase.input);
  }
  throw new Error(`Unknown plan validator: ${String(vectorCase.validator)}.`);
}
