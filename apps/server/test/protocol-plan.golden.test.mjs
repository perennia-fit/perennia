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

// Not vector cases: TypeScript's types cannot stop a caller building a
// PlanProtocol from a cast payload, so planDays checks each Protocol's period
// and rules itself rather than planning on a NaN modulo.
test("planDays rejects an undecoded Protocol the core cannot plan on", () => {
  const protocol = (rule, period = null) => ({
    protocolId: "protocol-cast",
    startLocalDate: "2026-09-01",
    period,
    remindersEnabled: false,
    members: [
      {
        memberId: "member-cast",
        compoundId: "compound-cast",
        versions: [{ id: "version-cast", effectiveFrom: "2026-09-01", rule }]
      }
    ]
  });
  const daily = { v: 1, kind: "timed", days: { kind: "daily" }, times: ["09:00"] };
  const everyZeroDays = {
    v: 1,
    kind: "timed",
    days: { kind: "every_n_days", n: 0, anchor: "2026-09-01", anchor_is_default: true },
    times: ["09:00"]
  };
  const noDayCycle = {
    v: 1,
    cycle: { on_days: 0, off_days: 0, anchor: "2026-09-01", anchor_is_default: true },
    pauses: []
  };
  const billionDoses = { v: 1, kind: "untimed", days: { kind: "daily" }, count: 1e9 };

  for (const cast of [protocol(everyZeroDays), protocol(daily, noDayCycle), protocol(billionDoses)]) {
    assert.throws(() => planDays([cast], "2026-09-01", "2026-09-03"), ProtocolPlanCodecError);
  }
  assert.equal(planDays([protocol(daily)], "2026-09-01", "2026-09-03").length, 3);
});

test("the encoders write only the keys the stored shape names", () => {
  assert.deepEqual(
    encodeScheduleRule({
      v: 1,
      kind: "untimed",
      days: { kind: "daily", extra: true },
      count: 2,
      note: "dropped"
    }),
    { v: 1, kind: "untimed", days: { kind: "daily" }, count: 2 }
  );
  assert.deepEqual(
    encodeProtocolPeriod({
      v: 1,
      cycle: null,
      pauses: [{ from: "2026-10-10", to: "2026-10-16", why: "dropped" }],
      extra: 1
    }),
    { v: 1, cycle: null, pauses: [{ from: "2026-10-10", to: "2026-10-16" }] }
  );
  assert.equal(encodeProtocolPeriod(null), null);
});
