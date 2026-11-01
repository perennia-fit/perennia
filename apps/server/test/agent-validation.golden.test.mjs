import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";

import {
  DOSE_VALIDATION_LIMITS,
  PLAN_VALIDATION_LIMITS,
  PROTOCOL_PLAN_VALIDATION_LIMITS,
  SETTINGS_VALIDATION_LIMITS,
  validateAgentDose,
  validateAgentFoodEntry,
  validateAgentNutritionGoalTargets,
  validateAgentPrescription,
  validateAgentProtocolPeriod,
  validateAgentRoutineCadence,
  validateAgentScheduleRule,
  validateAgentSet,
  validateAgentSettings,
  validateAgentTemplateGroup
} from "../src/index.ts";

// One entry per shared validation domain this runner implements. Dispatch is a
// lookup, not a fallthrough: a vector whose domain is missing here fails loudly
// rather than being judged by whichever validator happened to sit last.
const VALIDATORS_BY_DOMAIN = new Map([
  ["set-validation", (vectorCase) => validateAgentSet(vectorCase.input)],
  ["nutrient-validation", (vectorCase) => validateAgentFoodEntry(vectorCase.input)],
  ["dose-validation", (vectorCase) => validateAgentDose(vectorCase.input)],
  [
    "nutrition-goal-validation",
    (vectorCase) => validateAgentNutritionGoalTargets(vectorCase.input)
  ],
  ["plan-validation", (vectorCase) => validatePlanVectorCase(vectorCase)],
  ["settings-validation", (vectorCase) => validateAgentSettings(vectorCase.input)],
  ["protocol-plan-validation", (vectorCase) => validateProtocolPlanVectorCase(vectorCase)]
]);

// Every other domain under packages/golden-vectors, with who checks it. Every
// vector must land in exactly one place, so a domain in neither table is a
// vector no TypeScript code checks — the silent gap this guard exists to close.
const DOMAINS_OWNED_ELSEWHERE = new Set([
  "analytics", // analytics.golden.test.mjs (also claims vectors with no domain)
  "nutrition-analytics", // nutrition-analytics.golden.test.mjs
  "reading-normalization", // metric-reading-normalization.golden.test.mjs
  "workout-capture", // agent-plan-capture.golden.test.mjs
  "plan-divergence", // agent-plan-capture.golden.test.mjs
  "template-materialize", // agent-plan-materialize.test.mjs (needs Postgres)
  "routine-up-next", // agent-plan-reads.test.mjs (needs Postgres)
  "effect-window", // effect-window.golden.test.mjs
  "protocol-plan", // protocol-plan.golden.test.mjs
  "barcode-candidates", // barcode-candidates.golden.test.mjs
  "food-history", // food-history.golden.test.mjs
  // Dart only: Body Tracker measurements have no server implementation, so
  // these vectors pin the app against its own spec.
  "measurement-validation",
  "measurement-delta"
]);

test("server validation matches the shared golden vectors", async () => {
  const vectorsUrl = new URL("../../../packages/golden-vectors/vectors/", import.meta.url);
  const filenames = (await readdir(vectorsUrl)).filter(
    (name) => name.endsWith(".json") && !name.endsWith(".schema.json")
  );

  for (const filename of filenames) {
    const vector = JSON.parse(await readFile(new URL(filename, vectorsUrl), "utf8"));
    if (vector.domain === undefined || DOMAINS_OWNED_ELSEWHERE.has(vector.domain)) {
      continue;
    }
    const validate = VALIDATORS_BY_DOMAIN.get(vector.domain);
    assert.ok(
      validate,
      `${filename}: no TypeScript golden runner implements domain ` +
        `"${String(vector.domain)}". Add it to VALIDATORS_BY_DOMAIN, or to ` +
        "DOMAINS_OWNED_ELSEWHERE if another runner checks it."
    );

    // The TS limits and the vector's limits block must agree exactly so the
    // implementation and the spec stay in lockstep.
    if (vector.domain === "dose-validation") {
      assert.deepEqual(vector.limits, DOSE_VALIDATION_LIMITS, `${filename} limits`);
    }
    if (vector.domain === "plan-validation") {
      assert.deepEqual(
        vector.limits,
        PLAN_VALIDATION_LIMITS,
        `${filename} limits`
      );
    }
    if (vector.domain === "protocol-plan-validation") {
      // The schema version this runner reads; it moves together with the
      // vector file's `schemaVersion` and the Dart runner's constant
      // (packages/golden-vectors/vectors/README.md).
      assert.equal(vector.schemaVersion, 1, `${filename} schemaVersion`);
      assert.deepEqual(
        vector.limits,
        PROTOCOL_PLAN_VALIDATION_LIMITS,
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
      const result = validate(vectorCase);
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

// Rules and periods reach the validators as stored JSON, as they reach the
// Dart twin, so a value the codecs would reject (a time of "9:00", a count of
// 2.5) is still judged and reported under its check id.
function validateProtocolPlanVectorCase(vectorCase) {
  const { input } = vectorCase;
  if (vectorCase.validator === "schedule_rule") {
    return validateAgentScheduleRule(input.rule, {
      amountValue: input.amountValue,
      amountEntered: input.amountEntered,
      unit: input.unit,
      route: input.route
    });
  }
  if (vectorCase.validator === "protocol_period") {
    return validateAgentProtocolPeriod({
      startLocalDate: input.startLocalDate,
      endLocalDate: input.endLocalDate,
      period: input.period
    });
  }
  throw new Error(`Unknown protocol plan validator: ${String(vectorCase.validator)}.`);
}
