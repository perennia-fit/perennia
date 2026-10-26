import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { effectBoundsFromLocalDates } from "../src/agent-protocols.ts";
import {
  ProtocolPlanCodecError,
  dayStatuses,
  decodeProtocolPeriod,
  decodeScheduleRule,
  dueUnfilled,
  encodeProtocolPeriod,
  encodeScheduleRule,
  planDays
} from "../src/index.ts";

// Moves with the vector file's `schemaVersion` and its schema's constant, and
// with the app runner's (apps/mobile/test/domain/protocol_plan_golden_test.dart):
// an incompatible case-shape change bumps all of them together.
const PROTOCOL_PLAN_GOLDEN_SCHEMA_VERSION = 1;

// One entry per `function` the vector file uses. A case naming anything else
// fails loudly rather than being skipped.
const RUNNERS_BY_FUNCTION = new Map([
  ["rule_codec", (input) => runCodec(() => encodeScheduleRule(decodeScheduleRule(input.json)))],
  [
    "period_codec",
    (input) => runCodec(() => encodeProtocolPeriod(decodeProtocolPeriod(input.json)))
  ],
  [
    "plan_days",
    (input) => planDays(input.protocols.map(decodePlanProtocol), input.from, input.to)
  ],
  ["day_statuses", (input) => dayStatuses(input.planDays, input.doses, input.today)],
  ["due_unfilled", (input) => dueUnfilled(input.dayStatuses, input.today, input.nowLocalTime)],
  [
    "effect_bounds",
    (input) => {
      const bounds = effectBoundsFromLocalDates(
        input.startLocalDate,
        input.endLocalDate,
        input.timezoneOffsetMinutes
      );
      return {
        startDate: bounds.startDate.toISOString(),
        endDate: bounds.endDate?.toISOString() ?? null
      };
    }
  ]
]);

// The app runs the same file, so an Agent read and the app never disagree on
// what was planned on a date or how a day's Doses lined up with it.
test("the Protocol Plan core matches the shared M36 golden vectors", async () => {
  const vector = JSON.parse(
    await readFile(
      new URL(
        "../../../packages/golden-vectors/vectors/m36-protocol-plan.json",
        import.meta.url
      ),
      "utf8"
    )
  );

  assert.equal(vector.domain, "protocol-plan");
  assert.equal(vector.schemaVersion, PROTOCOL_PLAN_GOLDEN_SCHEMA_VERSION);
  assert.equal(vector.schema, "m36-protocol-plan.schema.json");
  assert.ok(vector.cases.length > 0);

  for (const vectorCase of vector.cases) {
    const run = RUNNERS_BY_FUNCTION.get(vectorCase.function);
    assert.ok(run, `${vectorCase.name}: unknown function ${String(vectorCase.function)}`);
    assert.deepEqual(run(vectorCase.input), vectorCase.expected, vectorCase.name);
  }
});

// Rule and period columns reach the core through the codecs, as stored rows do.
function decodePlanProtocol(protocol) {
  return {
    ...protocol,
    period: decodeProtocolPeriod(protocol.period),
    members: protocol.members.map((member) => ({
      ...member,
      versions: member.versions.map((version) => ({
        ...version,
        rule: decodeScheduleRule(version.rule)
      }))
    }))
  };
}

function runCodec(decodeAndEncode) {
  try {
    return decodeAndEncode();
  } catch (error) {
    if (error instanceof ProtocolPlanCodecError) {
      return { rejects: true };
    }
    throw error;
  }
}
