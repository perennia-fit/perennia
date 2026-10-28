import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  applyMigrations,
  createApp,
  createUuidV7,
  createDatabaseClient,
  computeEffectWindowSegments,
  createDrizzleAgentProtocolsStore,
  deriveEffectWindow,
  prepareAgentCompoundBatchWrite,
  prepareAgentDoseBatchWrite,
  prepareAgentProtocolBatchWrite,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error(
    "DATABASE_URL must be set for server Postgres integration tests."
  );
}

const skip = databaseUrl ? false : "DATABASE_URL is not set.";

// ---------------------------------------------------------------------------
// Pure prepare functions
// ---------------------------------------------------------------------------

test("prepareAgentDoseBatchWrite stamps provenance agent, snapshots self-describingly, and validates through the shared dose validator", () => {
  const prepared = prepareAgentDoseBatchWrite({
    request: {
      idempotencyKey: "k",
      doses: [
        {
          id: "d1",
          compoundId: "c1",
          compoundName: "Creatine",
          compoundStrength: null,
          amount: "5",
          unit: "gram",
          route: "oral",
          tookAt: "2026-06-30T08:00:00.000Z",
          timezone: "UTC",
          localDate: "2026-06-30",
          protocolId: "p1",
          protocolName: "Lean bulk",
          deletedAt: null
        }
      ]
    },
    now: new Date("2026-06-30T09:00:00.000Z")
  });
  assert.equal(prepared.accepted, true);
  const payload = prepared.doses[0].payload;
  assert.equal(payload.provenance, "agent");
  assert.equal(payload.compound_name, "Creatine");
  assert.equal(payload.amount_value, 5);
  assert.equal(payload.amount_entered, "5");
  assert.equal(payload.protocol_id, "p1");
  assert.equal(payload.protocol_name, "Lean bulk");
  assert.equal(payload.updated_at, "2026-06-30T09:00:00.000Z");
  assert.equal(prepared.responseDoses[0].outcome, undefined);
});

test("prepareAgentDoseBatchWrite hard-rejects an out-of-registry unit and an absurd amount", () => {
  const badUnit = prepareAgentDoseBatchWrite({
    request: {
      idempotencyKey: "k",
      doses: [
        {
          id: "d1",
          compoundName: "X",
          amount: "5",
          unit: "scoops",
          route: "oral",
          tookAt: "2026-06-30T08:00:00.000Z",
          timezone: "UTC",
          localDate: "2026-06-30"
        }
      ]
    }
  });
  assert.equal(badUnit.accepted, false);
  assert.ok(badUnit.errors.some((e) => e.rule === "dose_unit_allowed"));

  const absurd = prepareAgentDoseBatchWrite({
    request: {
      idempotencyKey: "k",
      doses: [
        {
          id: "d1",
          compoundName: "X",
          amount: "999999",
          unit: "gram",
          route: "oral",
          tookAt: "2026-06-30T08:00:00.000Z",
          timezone: "UTC",
          localDate: "2026-06-30"
        }
      ]
    }
  });
  assert.equal(absurd.accepted, false);
  assert.ok(absurd.errors.some((e) => e.rule === "dose_amount_max_per_dose"));
});

test("prepareAgentDoseBatchWrite surfaces a soft warning but still accepts", () => {
  const prepared = prepareAgentDoseBatchWrite({
    request: {
      idempotencyKey: "k",
      doses: [
        {
          id: "d1",
          compoundName: "X",
          amount: "200",
          unit: "gram",
          route: "oral",
          tookAt: "2026-06-30T08:00:00.000Z",
          timezone: "UTC",
          localDate: "2026-06-30"
        }
      ]
    }
  });
  assert.equal(prepared.accepted, true);
  assert.deepEqual(
    prepared.responseDoses[0].warnings.map((w) => w.rule),
    ["dose_amount_out_of_range_for_unit"]
  );
});

test("prepareAgentProtocolBatchWrite builds protocol + members + Schedule Versions + target outcomes without touching Doses", () => {
  const prepared = prepareAgentProtocolBatchWrite({
    request: {
      idempotencyKey: "k",
      today: "2026-10-27",
      protocols: [
        {
          id: "p1",
          name: "Lean bulk",
          startLocalDate: "2026-06-01",
          endLocalDate: null,
          period: { v: 1, cycle: null, pauses: [] },
          remindersEnabled: true,
          archived: false,
          members: [{ id: "m1", compoundId: "c1", position: 0, archived: false }],
          schedules: [
            {
              id: "s1",
              protocolCompoundId: "m1",
              rule: timedDailyRule(["09:00"]),
              doseAmountValue: 5,
              doseAmountEntered: "5",
              doseUnit: "gram",
              route: "oral"
            }
          ],
          targetOutcomes: [{ id: "t1", metricId: "metric-weight", outcomeKind: "metric" }]
        }
      ]
    },
    now: new Date("2026-10-27T09:00:00.000Z")
  });
  assert.equal(prepared.accepted, true);
  assert.equal(prepared.today, "2026-10-27");
  assert.deepEqual(prepared.warnings, []);
  assert.equal(prepared.protocols.length, 1);
  const protocol = prepared.protocols[0].payload;
  assert.equal(protocol.start_local_date, "2026-06-01");
  assert.equal(protocol.end_local_date, null);
  // No cycle and no Pause is stored as null, as the app writes it.
  assert.equal(protocol.period, null);
  assert.equal(protocol.reminders_enabled, true);
  assert.equal("start_date" in protocol, false);
  assert.equal(prepared.members[0].payload.protocol_id, "p1");
  const schedule = prepared.schedules[0].payload;
  // Stored as JSON text in the codec's encoding (Data shapes), as the app
  // stores it.
  assert.equal(schedule.rule, JSON.stringify(timedDailyRule(["09:00"])));
  assert.equal("frequency" in schedule, false);
  // The store dates the version from stored data (D1).
  assert.equal(schedule.effective_from, null);
  assert.equal(prepared.targetOutcomes[0].payload.metric_id, "metric-weight");
});

test("prepareAgentProtocolBatchWrite rejects and warns through the shared plan validators (D7)", () => {
  const request = (schedule, protocol = {}) => ({
    idempotencyKey: "k",
    today: "2026-10-27",
    protocols: [
      {
        id: "p1",
        name: "Daily",
        startLocalDate: "2026-10-01",
        endLocalDate: null,
        period: null,
        remindersEnabled: false,
        archived: false,
        members: [{ id: "m1", compoundId: "c1", position: 0, archived: false }],
        schedules: [{ id: "s1", protocolCompoundId: "m1", ...schedule }],
        targetOutcomes: [],
        ...protocol
      }
    ]
  });
  const now = new Date("2026-10-27T09:00:00.000Z");

  const badTimes = prepareAgentProtocolBatchWrite({
    request: request({ rule: timedDailyRule(["9:00", "21:00"]), ...creatineAmount }),
    now
  });
  assert.equal(badTimes.accepted, false);
  assert.deepEqual(
    badTimes.errors.map((issue) => [issue.rule, issue.field, issue.entityId]),
    [["times_format", "protocols[0].schedules[0].rule.times", "s1"]]
  );

  const manyTimes = prepareAgentProtocolBatchWrite({
    request: request({
      rule: timedDailyRule(["06:00", "08:00", "10:00", "12:00", "14:00", "16:00", "18:00"]),
      ...creatineAmount
    }),
    now
  });
  assert.equal(manyTimes.accepted, true);
  assert.deepEqual(
    manyTimes.warnings.map((issue) => issue.rule),
    ["times_many"]
  );

  const asNeededWithAmount = prepareAgentProtocolBatchWrite({
    request: request({ rule: { v: 1, kind: "as_needed" }, ...creatineAmount }),
    now
  });
  assert.deepEqual(
    asNeededWithAmount.errors.map((issue) => issue.rule),
    ["amount_absent"]
  );

  const timedWithoutAmount = prepareAgentProtocolBatchWrite({
    request: request({ rule: timedDailyRule(["09:00"]) }),
    now
  });
  assert.deepEqual(
    timedWithoutAmount.errors.map((issue) => issue.rule),
    ["amount_required"]
  );

  const badPeriod = prepareAgentProtocolBatchWrite({
    request: request(
      { rule: timedDailyRule(["09:00"]), ...creatineAmount },
      {
        endLocalDate: "2026-09-30",
        period: {
          v: 1,
          cycle: { on_days: 60, off_days: 30, anchor: "2026-02-30", anchor_is_default: false },
          pauses: []
        }
      }
    ),
    now
  });
  assert.deepEqual(
    badPeriod.errors.map((issue) => [issue.rule, issue.field]),
    [
      ["anchor_date", "protocols[0].period.cycle.anchor"],
      ["bounds_order", "protocols[0].endLocalDate"]
    ]
  );
});

test("prepareAgentProtocolBatchWrite rejects a today more than one day from the server's UTC date", () => {
  const now = new Date("2026-10-27T23:30:00.000Z");
  const write = (today) =>
    prepareAgentProtocolBatchWrite({
      request: {
        idempotencyKey: "k",
        today,
        protocols: [
          {
            id: "p1",
            name: "Daily",
            startLocalDate: "2026-10-01",
            endLocalDate: null,
            period: null,
            remindersEnabled: false,
            archived: false,
            members: [],
            schedules: [],
            targetOutcomes: []
          }
        ]
      },
      now
    });
  // UTC+14 is already the 28th, UTC-12 still the 27th: both are within a day.
  for (const today of ["2026-10-26", "2026-10-27", "2026-10-28"]) {
    assert.equal(write(today).accepted, true, today);
  }
  for (const today of ["2026-10-25", "2026-10-29"]) {
    const rejected = write(today);
    assert.equal(rejected.accepted, false, today);
    assert.deepEqual(
      rejected.errors.map((issue) => [issue.rule, issue.field]),
      [["today_out_of_range", "today"]]
    );
  }
});

test("prepareAgentDoseBatchWrite freezes the offset: the Agent's own wins, else it is derived from an IANA timezone", () => {
  const prepare = (dose) =>
    prepareAgentDoseBatchWrite({
      request: {
        idempotencyKey: "k",
        doses: [{ ...doseFixture("d1", "Creatine", dose.tookAt), ...dose }]
      }
    }).doses[0].payload.timezone_offset_minutes;

  // Supplied: wins over the zone.
  assert.equal(
    prepare({
      tookAt: "2026-06-30T08:00:00.000Z",
      timezone: "America/Sao_Paulo",
      timezoneOffsetMinutes: 60
    }),
    60
  );
  // Derived from an IANA zone at tookAt, daylight saving included.
  assert.equal(
    prepare({ tookAt: "2026-06-30T08:00:00.000Z", timezone: "America/Sao_Paulo" }),
    -180
  );
  assert.equal(
    prepare({ tookAt: "2026-06-30T08:00:00.000Z", timezone: "Europe/Lisbon" }),
    60
  );
  assert.equal(
    prepare({ tookAt: "2026-01-15T08:00:00.000Z", timezone: "Europe/Lisbon" }),
    0
  );
  // An abbreviation can't be converted, so the offset stays null.
  assert.equal(
    prepare({ tookAt: "2026-06-30T08:00:00.000Z", timezone: "BRT" }),
    null
  );
});

test("prepareAgentCompoundBatchWrite rejects a duplicate id in one batch", () => {
  const prepared = prepareAgentCompoundBatchWrite({
    request: {
      idempotencyKey: "k",
      compounds: [
        { id: "c1", name: "A", defaultUnit: "gram", defaultRoute: "oral", strength: null },
        { id: "c1", name: "B", defaultUnit: "gram", defaultRoute: "oral", strength: null }
      ]
    }
  });
  assert.equal(prepared.accepted, false);
  assert.ok(prepared.errors.some((e) => e.rule === "duplicate_compound_id"));
});

// ---------------------------------------------------------------------------
// Deterministic effect-window computation fixture (the window derivation and
// count/mean are pinned across languages by effect-window.golden.test.mjs;
// these cover the agent-only min/max)
// ---------------------------------------------------------------------------

test("computeEffectWindowSegments buckets samples into before/during/after with count/min/max/mean", () => {
  // DURING = first dose (day 10) → last dose (day 20); length 10 days.
  // BEFORE = [day 0, day 10); AFTER = [day 20, day 30).
  const d = (day) => new Date(Date.UTC(2026, 0, day));
  const window = deriveEffectWindow(
    { kind: "compound", doseTimes: [d(10), d(15), d(20)] },
    d(31)
  );
  const segments = computeEffectWindowSegments({
    window,
    samples: [
      { at: d(1), value: 100 }, // before
      { at: d(5), value: 102 }, // before
      { at: d(12), value: 90 }, // during
      { at: d(18), value: 94 }, // during
      { at: d(20), value: 999 }, // boundary: afterStart, half-open → after
      { at: d(25), value: 88 }, // after
      { at: d(40), value: 1 } // outside AFTER → excluded
    ]
  });

  assert.equal(window.duringStart.toISOString(), d(10).toISOString());
  assert.equal(window.duringEnd.toISOString(), d(20).toISOString());

  assert.deepEqual(segments.before, { count: 2, min: 100, max: 102, mean: 101 });
  assert.deepEqual(segments.during, { count: 2, min: 90, max: 94, mean: 92 });
  // day20 (999) lands in AFTER (half-open), plus day25 (88).
  assert.deepEqual(segments.after, {
    count: 2,
    min: 88,
    max: 999,
    mean: (999 + 88) / 2
  });
});

test("computeEffectWindowSegments returns empty aggregates with a null window when there are no doses", () => {
  const window = deriveEffectWindow(
    { kind: "compound", doseTimes: [] },
    new Date(Date.UTC(2026, 0, 1))
  );
  assert.equal(window, null);
  const segments = computeEffectWindowSegments({
    window,
    samples: [{ at: new Date(Date.UTC(2026, 0, 1)), value: 1 }]
  });
  assert.deepEqual(segments.before, { count: 0, min: null, max: null, mean: null });
  assert.deepEqual(segments.during, { count: 0, min: null, max: null, mean: null });
  assert.deepEqual(segments.after, { count: 0, min: null, max: null, mean: null });
});

// ---------------------------------------------------------------------------
// Route-level tests with a stubbed store (no DB)
// ---------------------------------------------------------------------------

test("dose batch-write route validates, calls the store once, and nudges sync after applied writes", async () => {
  const writes = [];
  const nudges = [];
  const app = createProtocolsApp({
    store: stubStore({
      async writeDoseBatch(input) {
        writes.push(input);
        return {
          duplicate: false,
          idempotencyConflict: false,
          receiptUnavailable: false,
          serverClock: "2026-06-30T09:00:01.000Z",
          accepted: input.doses.map((dose) => dose.id),
          applied: input.doses.map((dose) => ({
            id: dose.id,
            updatedAt: dose.updatedAt,
            deviceId: input.deviceId
          })),
          validationErrors: []
        };
      }
    }),
    syncNudgePublisher: {
      async enqueueSyncNudge(input) {
        nudges.push(input);
        return { enqueued: true, jobId: "j1" };
      }
    }
  });

  const response = await post(app, "/agent/protocols/doses/batch-write", {
    idempotencyKey: "dose-batch-1",
    doses: [
      {
        id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d001",
        compoundName: "Creatine",
        amount: "5",
        unit: "gram",
        route: "oral",
        tookAt: "2026-06-30T08:00:00.000Z",
        timezone: "UTC",
        localDate: "2026-06-30"
      }
    ]
  });

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.accepted, true);
  assert.equal(body.doses[0].compoundName, "Creatine");
  assert.equal(body.doses[0].outcome, "applied");
  assert.equal(writes.length, 1);
  assert.equal(writes[0].deviceId, "agent:agent-key-1");
  assert.equal(writes[0].doses[0].payload.provenance, "agent");
  assert.deepEqual(nudges, [
    { userId: "user-1", sourceDeviceId: "agent:agent-key-1", reason: "agent_write" }
  ]);
});

test("dose batch-write route hard-rejects an invalid dose before the store is called", async () => {
  const app = createProtocolsApp({
    store: stubStore({
      async writeDoseBatch() {
        throw new Error("writeDoseBatch must not be called.");
      }
    })
  });
  const response = await post(app, "/agent/protocols/doses/batch-write", {
    idempotencyKey: "dose-batch-bad",
    doses: [
      {
        id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d002",
        compoundName: "X",
        amount: "-1",
        unit: "gram",
        route: "oral",
        tookAt: "2026-06-30T08:00:00.000Z",
        timezone: "UTC",
        localDate: "2026-06-30"
      }
    ]
  });
  assert.equal(response.status, 422);
  const body = await response.json();
  assert.equal(body.code, "agent_dose_batch_write_failed");
  assert.ok(body.errors.some((e) => e.rule === "dose_amount_non_negative"));
  assert.ok(body.limits.units.gram.maxPerDose > 0);
});

test("protocol write routes surface stored row-id validation through the shared 422 shape", async () => {
  const invalidStoredIdResult = {
    duplicate: false,
    idempotencyConflict: false,
    receiptUnavailable: false,
    serverClock: "2026-06-30T09:00:01.000Z",
    accepted: [],
    applied: [],
    validationErrors: [
      {
        field: "id",
        rule: "new_row_id_must_be_uuidv7",
        message: "New Protocols rows require a client-supplied UUIDv7.",
        itemIndex: 0,
        entityId: "legacy-new-id"
      }
    ]
  };
  const app = createProtocolsApp({
    store: stubStore({
      async writeDoseBatch() {
        return invalidStoredIdResult;
      },
      async writeCompoundBatch() {
        return invalidStoredIdResult;
      },
      async writeProtocolBatch() {
        return invalidStoredIdResult;
      }
    })
  });
  const uuidV4 = "70e1d7a5-0b49-4e50-a55d-1d48c07c09ef";
  const requests = [
    [
      "/agent/protocols/doses/batch-write",
      {
        idempotencyKey: "invalid-dose-id",
        doses: [
          {
            ...doseFixture(uuidV4, "Creatine", "2026-06-30T08:00:00.000Z")
          }
        ]
      }
    ],
    [
      "/agent/protocols/compounds/batch-write",
      {
        idempotencyKey: "invalid-compound-id",
        compounds: [
          {
            id: uuidV4,
            name: "Creatine",
            defaultUnit: "gram",
            defaultRoute: "oral"
          }
        ]
      }
    ],
    [
      "/agent/protocols/batch-write",
      {
        idempotencyKey: "invalid-protocol-member-id",
        today: utcToday(),
        protocols: [
          {
            id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d003",
            name: "Base",
            startLocalDate: utcToday(),
            members: [{ id: uuidV4, compoundId: "compound-id", position: 0 }],
            schedules: [],
            targetOutcomes: []
          }
        ]
      }
    ]
  ];
  for (const [path, body] of requests) {
    const response = await post(app, path, body);
    assert.equal(response.status, 422);
    const responseBody = await response.json();
    assert.equal(responseBody.code, "agent_protocols_batch_write_failed");
    assert.equal(responseBody.errors[0].rule, "new_row_id_must_be_uuidv7");
  }
});

test("effect-window route maps a store validation failure to a 422 error body", async () => {
  const app = createProtocolsApp({
    store: stubStore({
      async readEffectWindow() {
        return { ok: false, message: "Provide exactly one of compoundId or protocolId." };
      }
    })
  });
  const response = await app.request(
    "/agent/protocols/effect-window?from=2026-01-01T00:00:00.000Z&to=2026-02-01T00:00:00.000Z&metricId=m1",
    { headers: authHeaders() }
  );
  assert.equal(response.status, 422);
  const body = await response.json();
  assert.equal(body.code, "agent_effect_window_invalid_request");
});

test("unauthorized requests are rejected on every protocols path", async () => {
  const app = createProtocolsApp({ store: stubStore({}) });
  for (const path of [
    "/agent/protocols/compounds",
    "/agent/protocols",
    "/agent/protocols/doses"
  ]) {
    const response = await app.request(path);
    assert.equal(response.status, 401);
  }
});

test("protocol batch-write is strict: frequency, deletedAt, effectiveFrom, a missing today and a non-date bound are 400s before the store", async () => {
  const app = createProtocolsApp({
    store: stubStore({
      async writeProtocolBatch() {
        throw new Error("writeProtocolBatch must not be called.");
      }
    })
  });
  const base = protocolWriteRequest();
  const variants = {
    "Schedule frequency": withSchedule(base, { frequency: "onceDaily" }),
    "Schedule effectiveFrom": withSchedule(base, { effectiveFrom: "2026-01-01" }),
    "Schedule deletedAt": withSchedule(base, { deletedAt: null }),
    "Protocol deletedAt": withProtocol(base, { deletedAt: "2026-07-01T00:00:00.000Z" }),
    "Protocol startDate": withProtocol(base, { startDate: "2026-06-01T00:00:00.000Z" }),
    "Member deletedAt": withProtocol(base, {
      members: [{ ...base.protocols[0].members[0], deletedAt: null }]
    }),
    "missing today": (({ today: _today, ...rest }) => rest)(base),
    "impossible startLocalDate": withProtocol(base, { startLocalDate: "2026-02-30" }),
    "non-date endLocalDate": withProtocol(base, { endLocalDate: "2026-10-01T00:00:00Z" }),
    "non-date today": { ...base, today: "27/10/2026" },
    "unknown rule version": withSchedule(base, {
      rule: { ...timedDailyRule(["09:00"]), v: 2 }
    }),
    "unknown rule kind": withSchedule(base, { rule: { v: 1, kind: "daily" } })
  };
  for (const [name, body] of Object.entries(variants)) {
    const response = await post(app, "/agent/protocols/batch-write", body);
    assert.equal(response.status, 400, name);
  }
});

test("protocol batch-write passes today to the store and returns the plan validators' warnings", async () => {
  const writes = [];
  const app = createProtocolsApp({
    store: stubStore({
      async writeProtocolBatch(input) {
        writes.push(input);
        return {
          duplicate: false,
          idempotencyConflict: false,
          receiptUnavailable: false,
          serverClock: new Date().toISOString(),
          accepted: input.protocols.map((row) => row.id),
          applied: input.protocols.map((row) => ({
            id: row.id,
            updatedAt: row.updatedAt,
            deviceId: input.deviceId
          })),
          validationErrors: []
        };
      }
    })
  });
  const body = withSchedule(protocolWriteRequest(), {
    rule: timedDailyRule(["06:00", "08:00", "10:00", "12:00", "14:00", "16:00", "18:00"])
  });
  const response = await post(app, "/agent/protocols/batch-write", body);
  assert.equal(response.status, 200);
  const responseBody = await response.json();
  assert.equal(responseBody.protocols[0].outcome, "applied");
  assert.deepEqual(
    responseBody.warnings.map((issue) => [issue.rule, issue.field]),
    [["times_many", "protocols[0].schedules[0].rule.times"]]
  );
  assert.equal(writes.length, 1);
  assert.equal(writes[0].today, body.today);
});

test("effect-window route rejects an offset outside -720 to +840 with 400 before the store", async () => {
  const reads = [];
  const app = createProtocolsApp({
    store: stubStore({
      async readEffectWindow(input) {
        reads.push(input.query.timezoneOffsetMinutes);
        return { ok: false, message: "The requested Metric was not found." };
      }
    })
  });
  const path = (offset) =>
    `/agent/protocols/effect-window?protocolId=p1&metricId=m1&from=2026-01-01T00:00:00.000Z&to=2026-02-01T00:00:00.000Z${
      offset === undefined ? "" : `&timezoneOffsetMinutes=${offset}`
    }`;
  for (const offset of [-721, 841, 1.5]) {
    const response = await app.request(path(offset), { headers: authHeaders() });
    assert.equal(response.status, 400, String(offset));
  }
  assert.deepEqual(reads, []);
  for (const offset of [undefined, -720, 840]) {
    const response = await app.request(path(offset), { headers: authHeaders() });
    assert.equal(response.status, 422, String(offset));
  }
  assert.deepEqual(reads, [0, -720, 840]);
});

// ---------------------------------------------------------------------------
// DB-backed: round-trip, idempotency, tenant isolation, no cascade, reads
// ---------------------------------------------------------------------------

test(
  "new Protocols rows require UUIDv7 across every authored row type",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-protocols-uuidv7-${randomUUID()}`;
    const app = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId
    });
    const uuidV4 = "70e1d7a5-0b49-4e50-a55d-1d48c07c09ef";
    const compoundReference = createUuidV7();
    const protocolId = createUuidV7();
    const memberId = createUuidV7();
    const requests = [
      [
        "/agent/protocols/doses/batch-write",
        {
          idempotencyKey: `invalid-dose-${randomUUID()}`,
          doses: [
            doseFixture(uuidV4, "Creatine", "2026-06-30T08:00:00.000Z")
          ]
        }
      ],
      [
        "/agent/protocols/compounds/batch-write",
        {
          idempotencyKey: `invalid-compound-${randomUUID()}`,
          compounds: [
            {
              id: uuidV4,
              name: "Creatine",
              defaultUnit: "gram",
              defaultRoute: "oral"
            }
          ]
        }
      ],
      [
        "/agent/protocols/batch-write",
        {
          idempotencyKey: `invalid-protocol-${randomUUID()}`,
          today: utcToday(),
          protocols: [
            {
              id: uuidV4,
              name: "Base",
              startLocalDate: utcToday(),
              members: [],
              schedules: [],
              targetOutcomes: []
            }
          ]
        }
      ],
      [
        "/agent/protocols/batch-write",
        {
          idempotencyKey: `invalid-member-${randomUUID()}`,
          today: utcToday(),
          protocols: [
            {
              id: protocolId,
              name: "Base",
              startLocalDate: utcToday(),
              members: [
                { id: uuidV4, compoundId: compoundReference, position: 0 }
              ],
              schedules: [],
              targetOutcomes: []
            }
          ]
        }
      ],
      [
        "/agent/protocols/batch-write",
        {
          idempotencyKey: `invalid-schedule-${randomUUID()}`,
          today: utcToday(),
          protocols: [
            {
              id: protocolId,
              name: "Base",
              startLocalDate: utcToday(),
              members: [
                { id: memberId, compoundId: compoundReference, position: 0 }
              ],
              schedules: [
                {
                  id: uuidV4,
                  protocolCompoundId: memberId,
                  rule: { v: 1, kind: "as_needed" }
                }
              ],
              targetOutcomes: []
            }
          ]
        }
      ],
      [
        "/agent/protocols/batch-write",
        {
          idempotencyKey: `invalid-outcome-${randomUUID()}`,
          today: utcToday(),
          protocols: [
            {
              id: protocolId,
              name: "Base",
              startLocalDate: utcToday(),
              members: [],
              schedules: [],
              targetOutcomes: [
                {
                  id: uuidV4,
                  metricId: "metric-weight",
                  outcomeKind: "metric"
                }
              ]
            }
          ]
        }
      ]
    ];

    try {
      await insertUser(database, userId);
      for (const [path, body] of requests) {
        const response = await post(app, path, body);
        assert.equal(response.status, 422);
        const responseBody = await response.json();
        assert.ok(
          responseBody.errors.some(
            (error) => error.rule === "new_row_id_must_be_uuidv7"
          )
        );
      }
    } finally {
      await database.close();
    }
  }
);

test(
  "existing legacy Dose, Compound, and Protocol ids remain editable and archivable",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-protocols-legacy-ids-${randomUUID()}`;
    const app = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId
    });
    const updatedAt = new Date("2026-06-01T00:00:00.000Z");

    try {
      await insertUser(database, userId);
      await insertOpaqueFixture(database, schema.doses, {
        id: "legacy-dose-id",
        userId,
        updatedAt,
        payload: {
          id: "legacy-dose-id",
          compound_name: "Creatine",
          amount_value: 5,
          amount_entered: "5",
          unit: "gram",
          route: "oral",
          took_at: updatedAt.toISOString(),
          timezone: "UTC",
          local_date: "2026-06-01",
          provenance: "agent",
          updated_at: updatedAt.toISOString(),
          deleted_at: null
        }
      });
      await insertOpaqueFixture(database, schema.compounds, {
        id: "legacy-compound-id",
        userId,
        updatedAt,
        payload: {
          id: "legacy-compound-id",
          name: "Creatine",
          default_unit: "gram",
          default_route: "oral",
          updated_at: updatedAt.toISOString(),
          deleted_at: null
        }
      });
      await insertOpaqueFixture(database, schema.protocols, {
        id: "legacy-protocol-id",
        userId,
        updatedAt,
        payload: {
          id: "legacy-protocol-id",
          name: "Base",
          start_local_date: "2026-06-01",
          end_local_date: null,
          period: null,
          reminders_enabled: false,
          archived_on: null,
          updated_at: updatedAt.toISOString(),
          deleted_at: null
        }
      });

      const dose = await post(app, "/agent/protocols/doses/batch-write", {
        idempotencyKey: `legacy-dose-edit-${randomUUID()}`,
        doses: [
          doseFixture(
            "legacy-dose-id",
            "Creatine monohydrate",
            "2026-06-02T08:00:00.000Z"
          )
        ]
      });
      assert.equal(dose.status, 200);
      assert.equal((await dose.json()).doses[0].outcome, "applied");

      const compound = await post(app, "/agent/protocols/compounds/batch-write", {
        idempotencyKey: `legacy-compound-edit-${randomUUID()}`,
        compounds: [
          {
            id: "legacy-compound-id",
            name: "Creatine monohydrate",
            defaultUnit: "gram",
            defaultRoute: "oral"
          }
        ]
      });
      assert.equal(compound.status, 200);
      assert.equal((await compound.json()).compounds[0].outcome, "applied");

      const protocol = await post(app, "/agent/protocols/batch-write", {
        idempotencyKey: `legacy-protocol-archive-${randomUUID()}`,
        today: utcToday(),
        protocols: [
          {
            id: "legacy-protocol-id",
            name: "Base",
            startLocalDate: "2026-06-01",
            archived: true,
            members: [],
            schedules: [],
            targetOutcomes: []
          }
        ]
      });
      assert.equal(protocol.status, 200);
      assert.equal((await protocol.json()).protocols[0].outcome, "applied");
      const [archivedLegacy] = await database.sql`
        select deleted_at, payload from protocols where id = 'legacy-protocol-id'
      `;
      assert.notEqual(archivedLegacy.deleted_at, null);
      assert.equal(archivedLegacy.payload.archived_on, utcToday());
    } finally {
      await database.close();
    }
  }
);

test(
  "legacy Protocols references must resolve in-tenant while Metric ids stay opaque",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-protocols-references-${randomUUID()}`;
    const app = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId
    });

    try {
      await insertUser(database, userId);
      const missingCompound = await post(
        app,
        "/agent/protocols/doses/batch-write",
        {
          idempotencyKey: `missing-compound-${randomUUID()}`,
          doses: [
            {
              ...doseFixture(
                createUuidV7(),
                "Creatine",
                "2026-06-30T08:00:00.000Z"
              ),
              compoundId: "missing-legacy-compound"
            }
          ]
        }
      );
      assert.equal(missingCompound.status, 422);
      assert.equal(
        (await missingCompound.json()).errors[0].rule,
        "legacy_reference_not_found"
      );

      const missingMember = await post(app, "/agent/protocols/batch-write", {
        idempotencyKey: `missing-member-${randomUUID()}`,
        today: utcToday(),
        protocols: [
          {
            id: createUuidV7(),
            name: "Base",
            startLocalDate: utcToday(),
            members: [],
            schedules: [
              {
                id: createUuidV7(),
                protocolCompoundId: "missing-legacy-member",
                rule: { v: 1, kind: "as_needed" }
              }
            ],
            targetOutcomes: []
          }
        ]
      });
      assert.equal(missingMember.status, 422);
      assert.equal(
        (await missingMember.json()).errors[0].rule,
        "legacy_reference_not_found"
      );

      const opaqueMetric = await post(app, "/agent/protocols/batch-write", {
        idempotencyKey: `opaque-metric-${randomUUID()}`,
        today: utcToday(),
        protocols: [
          {
            id: createUuidV7(),
            name: "Base",
            startLocalDate: utcToday(),
            members: [],
            schedules: [],
            targetOutcomes: [
              {
                id: createUuidV7(),
                metricId: "metric-weight",
                outcomeKind: "metric"
              }
            ]
          }
        ]
      });
      assert.equal(opaqueMetric.status, 200);
    } finally {
      await database.close();
    }
  }
);

test(
  "a non-Protocols Activity Log batch may reuse the same idempotency key",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-protocols-cross-domain-${randomUUID()}`;
    const app = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId
    });
    const batchId = `shared-key-${randomUUID()}`;
    const doseId = createUuidV7();

    try {
      await insertUser(database, userId);
      await database.db.insert(schema.activityLog).values({
        id: `agent-metric:${randomUUID()}`,
        userId,
        actor: "agent",
        batchId,
        entityTable: "metrics",
        entityId: createUuidV7(),
        beforeImage: null,
        afterImage: { id: createUuidV7() },
        occurredAt: new Date("2026-06-01T00:00:00.000Z")
      });

      const response = await post(app, "/agent/protocols/doses/batch-write", {
        idempotencyKey: batchId,
        doses: [
          doseFixture(doseId, "Creatine", "2026-06-30T08:00:00.000Z")
        ]
      });
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.duplicate, false);
      assert.equal(body.doses[0].outcome, "applied");
    } finally {
      await database.close();
    }
  }
);

test(
  "a legacy Protocols replay mints one stable server-clock receipt",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-protocols-legacy-receipt-${randomUUID()}`;
    const app = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId
    });
    const batchId = `legacy-batch-${randomUUID()}`;
    const doseId = createUuidV7();
    const request = {
      idempotencyKey: batchId,
      doses: [
        doseFixture(doseId, "Creatine", "2026-06-30T08:00:00.000Z")
      ]
    };

    try {
      await insertUser(database, userId);
      await database.db.insert(schema.activityLog).values({
        id: `legacy-dose-activity:${randomUUID()}`,
        userId,
        actor: "agent",
        batchId,
        entityTable: "doses",
        entityId: doseId,
        beforeImage: null,
        afterImage: { id: doseId },
        occurredAt: new Date("1999-01-01T00:00:00.000Z")
      });

      const first = await post(app, "/agent/protocols/doses/batch-write", request);
      const second = await post(app, "/agent/protocols/doses/batch-write", request);
      assert.equal(first.status, 200);
      assert.equal(second.status, 200);
      const firstBody = await first.json();
      const secondBody = await second.json();
      assert.equal(firstBody.duplicate, true);
      assert.equal(secondBody.duplicate, true);
      assert.equal(firstBody.serverClock, secondBody.serverClock);
      assert.notEqual(firstBody.serverClock, "1999-01-01T00:00:00.000Z");
    } finally {
      await database.close();
    }
  }
);

test(
  "dose batch-write persists rows, records one Activity Log batch, and replays idempotently",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-protocols-user-${randomUUID()}`;
    const app = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId
    });
    const doseId = createUuidV7();
    const request = {
      idempotencyKey: `dose-${randomUUID()}`,
      doses: [
        {
          id: doseId,
          compoundName: "Creatine",
          amount: "5",
          unit: "gram",
          route: "oral",
          tookAt: "2026-06-30T08:00:00.000Z",
          timezone: "UTC",
          localDate: "2026-06-30",
          protocolId: null
        }
      ]
    };

    try {
      await insertUser(database, userId);

      const response = await post(app, "/agent/protocols/doses/batch-write", request);
      assert.equal(response.status, 200);
      const firstBody = await response.json();
      assert.equal(firstBody.duplicate, false);
      assert.equal(firstBody.doses[0].outcome, "applied");

      const doseRows = await database.sql`
        select id, user_id, device_id, payload from doses where id = ${doseId}
      `;
      assert.equal(doseRows.length, 1);
      assert.equal(doseRows[0].user_id, userId);
      assert.equal(doseRows[0].device_id, "agent:agent-key-1");
      assert.equal(doseRows[0].payload.provenance, "agent");

      const activityRows = await database.sql`
        select actor, batch_id, entity_table from activity_log
        where batch_id = ${request.idempotencyKey}
          and entity_table = 'doses'
      `;
      assert.equal(activityRows.length, 1);
      assert.equal(activityRows[0].actor, "agent");
      assert.equal(activityRows[0].entity_table, "doses");

      // Idempotent replay: duplicate=true, no second Activity Log batch row.
      const replay = await post(app, "/agent/protocols/doses/batch-write", request);
      assert.equal(replay.status, 200);
      const replayBody = await replay.json();
      assert.equal(replayBody.duplicate, true);
      assert.equal(replayBody.serverClock, firstBody.serverClock);
      assert.equal(replayBody.doses[0].outcome, "duplicate");
      const replayActivity = await database.sql`
        select entity_table from activity_log
        where batch_id = ${request.idempotencyKey}
      `;
      assert.deepEqual(
        replayActivity.map((row) => row.entity_table).sort(),
        ["agent_protocol_batches", "doses"]
      );

      // Reusing the key for different work is a typed conflict, not a false
      // duplicate response that echoes rows the server never wrote.
      const conflictingDoseId = createUuidV7();
      const conflict = await post(app, "/agent/protocols/doses/batch-write", {
        ...request,
        doses: [
          doseFixture(
            conflictingDoseId,
            "Magnesium",
            "2026-06-30T09:00:00.000Z"
          )
        ]
      });
      assert.equal(conflict.status, 422);
      const conflictBody = await conflict.json();
      assert.equal(conflictBody.code, "agent_protocols_batch_write_failed");
      assert.equal(conflictBody.errors[0].rule, "idempotency_key_conflict");
      const conflictingRows = await database.sql`
        select id from doses where id = ${conflictingDoseId}
      `;
      assert.equal(conflictingRows.length, 0);
    } finally {
      await database.close();
    }
  }
);

test(
  "simultaneous Dose batch retries claim one atomic receipt and never double-log",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-protocols-race-${randomUUID()}`;
    const app = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId
    });
    const doseId = createUuidV7();
    const request = {
      idempotencyKey: `dose-race-${randomUUID()}`,
      doses: [
        doseFixture(doseId, "Creatine", "2026-06-30T08:00:00.000Z")
      ]
    };

    try {
      await insertUser(database, userId);

      const responses = await Promise.all([
        post(app, "/agent/protocols/doses/batch-write", request),
        post(app, "/agent/protocols/doses/batch-write", request)
      ]);
      assert.deepEqual(
        responses.map((response) => response.status),
        [200, 200]
      );
      const bodies = await Promise.all(responses.map((response) => response.json()));
      assert.deepEqual(
        bodies.map((body) => body.duplicate).sort(),
        [false, true]
      );
      assert.equal(bodies[0].serverClock, bodies[1].serverClock);
      assert.deepEqual(
        bodies.map((body) => body.doses[0].outcome).sort(),
        ["applied", "duplicate"]
      );

      const doseRows = await database.sql`
        select id from doses where id = ${doseId}
      `;
      assert.equal(doseRows.length, 1);
      const activityRows = await database.sql`
        select entity_table from activity_log
        where user_id = ${userId}
          and batch_id = ${request.idempotencyKey}
      `;
      assert.deepEqual(
        activityRows.map((row) => row.entity_table).sort(),
        ["agent_protocol_batches", "doses"]
      );
    } finally {
      await database.close();
    }
  }
);

test(
  "dose batch-write is tenant-isolated: a second user's batch cannot overwrite the first user's Dose row",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userA = `agent-protocols-a-${randomUUID()}`;
    const userB = `agent-protocols-b-${randomUUID()}`;
    const appA = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId: userA
    });
    const appB = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId: userB
    });
    const doseId = createUuidV7();

    try {
      await insertUser(database, userA);
      await insertUser(database, userB);

      await post(appA, "/agent/protocols/doses/batch-write", {
        idempotencyKey: `a-${randomUUID()}`,
        doses: [doseFixture(doseId, "Creatine", "2026-06-30T08:00:00.000Z")]
      });
      // User B pushes the SAME client PK with a later clock; must not overwrite.
      const refusedBatchId = `b-${randomUUID()}`;
      const bResponse = await post(appB, "/agent/protocols/doses/batch-write", {
        idempotencyKey: refusedBatchId,
        doses: [doseFixture(doseId, "Hijacked", "2026-07-30T08:00:00.000Z")]
      });
      assert.equal(bResponse.status, 422);
      const bBody = await bResponse.json();
      assert.equal(bBody.errors[0].rule, "row_owned_by_another_user");

      const rows = await database.sql`
        select user_id, payload from doses where id = ${doseId}
      `;
      assert.equal(rows.length, 1);
      assert.equal(rows[0].user_id, userA);
      assert.equal(rows[0].payload.compound_name, "Creatine");
      const refusedActivity = await database.sql`
        select id from activity_log
        where user_id = ${userB}
          and batch_id = ${refusedBatchId}
      `;
      assert.equal(refusedActivity.length, 0);
    } finally {
      await database.close();
    }
  }
);

test(
  "protocol batch-write archive is a plan edit that never cascades to a tagged logged Dose",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-protocols-cascade-${randomUUID()}`;
    const app = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId
    });
    const protocolId = createUuidV7();
    const doseId = createUuidV7();

    try {
      await insertUser(database, userId);
      // Create the Protocol and a Dose tagged to it.
      await post(app, "/agent/protocols/batch-write", {
        idempotencyKey: `proto-${randomUUID()}`,
        today: utcToday(),
        protocols: [
          {
            id: protocolId,
            name: "Lean bulk",
            startLocalDate: "2026-06-01",
            endLocalDate: null,
            members: [],
            schedules: [],
            targetOutcomes: []
          }
        ]
      });
      await post(app, "/agent/protocols/doses/batch-write", {
        idempotencyKey: `dose-${randomUUID()}`,
        doses: [
          {
            ...doseFixture(doseId, "Creatine", "2026-06-30T08:00:00.000Z"),
            protocolId,
            protocolName: "Lean bulk"
          }
        ]
      });

      // Archive the Protocol.
      const archive = await post(app, "/agent/protocols/batch-write", {
        idempotencyKey: `archive-${randomUUID()}`,
        today: utcToday(),
        protocols: [
          {
            id: protocolId,
            name: "Lean bulk",
            startLocalDate: "2026-06-01",
            endLocalDate: null,
            archived: true,
            members: [],
            schedules: [],
            targetOutcomes: []
          }
        ]
      });
      assert.equal(archive.status, 200);

      const protocolRows = await database.sql`
        select deleted_at from protocols where id = ${protocolId}
      `;
      assert.notEqual(protocolRows[0].deleted_at, null);

      // The tagged Dose is untouched — no cascade.
      const doseRows = await database.sql`
        select deleted_at, payload from doses where id = ${doseId}
      `;
      assert.equal(doseRows[0].deleted_at, null);
      assert.equal(doseRows[0].payload.protocol_id, protocolId);
    } finally {
      await database.close();
    }
  }
);

test(
  "bounded reads page and project fields, and the protocol read bundles plan detail",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-protocols-read-${randomUUID()}`;
    const app = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId
    });
    const compoundIds = [createUuidV7(), createUuidV7(), createUuidV7()].sort();
    const protocolId = createUuidV7();
    const memberId = createUuidV7();
    const scheduleId = createUuidV7();
    const outcomeId = createUuidV7();

    try {
      await insertUser(database, userId);
      await post(app, "/agent/protocols/compounds/batch-write", {
        idempotencyKey: `c-${randomUUID()}`,
        compounds: compoundIds.map((id, index) => ({
          id,
          name: `Compound ${index}`,
          defaultUnit: "gram",
          defaultRoute: "oral",
          strength: null
        }))
      });
      await post(app, "/agent/protocols/batch-write", {
        idempotencyKey: `p-${randomUUID()}`,
        today: utcToday(),
        protocols: [
          {
            id: protocolId,
            name: "Lean bulk",
            startLocalDate: "2026-06-01",
            endLocalDate: null,
            members: [{ id: memberId, compoundId: compoundIds[0], position: 0 }],
            schedules: [
              {
                id: scheduleId,
                protocolCompoundId: memberId,
                doseAmountValue: 5,
                doseAmountEntered: "5",
                doseUnit: "gram",
                rule: timedDailyRule(["09:00"]),
                route: "oral"
              }
            ],
            targetOutcomes: [
              { id: outcomeId, metricId: "metric-weight", outcomeKind: "metric" }
            ]
          }
        ]
      });

      // Compound read: limit + fields projection.
      const page = await app.request(
        "/agent/protocols/compounds?limit=2&fields=name",
        { headers: authHeaders() }
      );
      assert.equal(page.status, 200);
      const pageBody = await page.json();
      assert.equal(pageBody.compounds.length, 2);
      assert.equal(pageBody.totalMatched, 3);
      assert.notEqual(pageBody.nextCursor, null);
      // Projected: id + name only (defaultUnit omitted).
      assert.equal(pageBody.compounds[0].defaultUnit, undefined);
      assert.ok(pageBody.compounds[0].name.length > 0);

      const nextPage = await app.request(
        `/agent/protocols/compounds?limit=2&cursor=${pageBody.nextCursor}`,
        { headers: authHeaders() }
      );
      const nextBody = await nextPage.json();
      assert.equal(nextBody.compounds.length, 1);
      assert.equal(nextBody.nextCursor, null);

      // Protocol read: plan detail bundled.
      const protocols = await app.request("/agent/protocols", {
        headers: authHeaders()
      });
      const protocolBody = await protocols.json();
      const protocol = protocolBody.protocols.find((p) => p.id === protocolId);
      assert.ok(protocol);
      assert.equal(protocol.startLocalDate, "2026-06-01");
      assert.equal(protocol.members.length, 1);
      assert.equal(protocol.members[0].compoundId, compoundIds[0]);
      assert.equal(protocol.members[0].versions.length, 1);
      assert.equal(protocol.members[0].versions[0].id, scheduleId);
      assert.equal(protocol.members[0].versions[0].effectiveFrom, "2026-06-01");
      assert.deepEqual(protocol.members[0].versions[0].rule, timedDailyRule(["09:00"]));
      assert.equal(protocol.members[0].currentVersion.id, scheduleId);
      assert.equal("schedules" in protocol, false);
      assert.equal(protocol.targetOutcomes.length, 1);
      assert.equal(protocol.targetOutcomes[0].metricId, "metric-weight");
    } finally {
      await database.close();
    }
  }
);

test(
  "the protocol read decodes a plan the app synced, whose rule and period ride as JSON text",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-protocols-app-shape-${randomUUID()}`;
    const app = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId
    });
    const compoundId = createUuidV7();
    const protocolId = createUuidV7();
    const memberId = createUuidV7();
    const scheduleId = createUuidV7();
    const updatedAt = new Date("2026-10-01T09:00:00.000Z");
    const period = {
      v: 1,
      cycle: { on_days: 60, off_days: 30, anchor: "2026-10-01", anchor_is_default: true },
      pauses: [{ from: "2026-10-10", to: "2026-10-12" }]
    };
    const rule = timedDailyRule(["21:00"]);
    const stamps = { updated_at: updatedAt.toISOString(), deleted_at: null };

    try {
      await insertUser(database, userId);
      await insertOpaqueFixture(database, schema.compounds, {
        id: compoundId,
        userId,
        updatedAt,
        payload: {
          id: compoundId,
          name: "GHK-Cu",
          default_unit: "milligram",
          default_route: "subcutaneous",
          strength: null,
          ...stamps
        }
      });
      // The app's sync images carry `rule` and `period` as JSON text, the
      // way its columns store them.
      await insertOpaqueFixture(database, schema.protocols, {
        id: protocolId,
        userId,
        updatedAt,
        payload: {
          id: protocolId,
          name: "Skin",
          start_local_date: "2026-10-01",
          end_local_date: null,
          period: JSON.stringify(period),
          reminders_enabled: false,
          archived_on: null,
          ...stamps
        }
      });
      await insertOpaqueFixture(database, schema.protocolCompounds, {
        id: memberId,
        userId,
        updatedAt,
        payload: {
          id: memberId,
          protocol_id: protocolId,
          compound_id: compoundId,
          position: 0,
          archived_on: null,
          ...stamps
        }
      });
      await insertOpaqueFixture(database, schema.schedules, {
        id: scheduleId,
        userId,
        updatedAt,
        payload: {
          id: scheduleId,
          protocol_compound_id: memberId,
          effective_from: "2026-10-01",
          rule: JSON.stringify(rule),
          dose_amount_value: 1,
          dose_amount_entered: "1",
          dose_unit: "milligram",
          route: "subcutaneous",
          ...stamps
        }
      });

      const response = await app.request("/agent/protocols", {
        headers: authHeaders()
      });
      assert.equal(response.status, 200);
      const protocol = (await response.json()).protocols.find(
        (p) => p.id === protocolId
      );
      assert.ok(protocol);
      assert.deepEqual(protocol.period, period);
      assert.equal(protocol.members.length, 1);
      assert.equal(protocol.members[0].versions.length, 1);
      assert.deepEqual(protocol.members[0].versions[0].rule, rule);
      assert.equal(protocol.members[0].currentVersion.id, scheduleId);
    } finally {
      await database.close();
    }
  }
);

test(
  "effect-window read computes descriptive before/during/after aggregates over the real dose timeline",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-effect-${randomUUID()}`;
    const app = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId
    });
    const compoundId = createUuidV7();
    const metricId = randomUUID();

    try {
      await insertUser(database, userId);

      // A Metric + scalar Readings: before (day1), during (day12/18), after (day25).
      await database.db.insert(schema.metrics).values({
        id: metricId,
        userId,
        deviceId: "device-1",
        name: "Body Weight",
        unit: "kilogram",
        valueShape: "scalar",
        metricGroup: "body",
        sortOrder: 0,
        updatedAt: new Date("2026-01-01T00:00:00.000Z")
      });
      const reading = async (day, value) =>
        database.db.insert(schema.metricReadings).values({
          id: randomUUID(),
          userId,
          deviceId: "device-1",
          metricId,
          valueJson: { value },
          scalarValue: value,
          atTime: new Date(Date.UTC(2026, 0, day)),
          provenance: "manual",
          source: "manual",
          updatedAt: new Date(Date.UTC(2026, 0, day))
        });
      await reading(1, 100);
      await reading(12, 90);
      await reading(18, 94);
      await reading(25, 88);

      // Doses on day 10 and day 20 for the compound.
      await post(app, "/agent/protocols/doses/batch-write", {
        idempotencyKey: `dose-${randomUUID()}`,
        doses: [
          {
            ...doseFixture(createUuidV7(), "X", isoDay(10)),
            compoundId
          },
          {
            ...doseFixture(createUuidV7(), "X", isoDay(20)),
            compoundId
          }
        ]
      });

      const response = await app.request(
        `/agent/protocols/effect-window?compoundId=${compoundId}&metricId=${metricId}&from=${isoDay(1)}&to=${isoDay(31)}`,
        { headers: authHeaders() }
      );
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.descriptiveOnly, true);
      assert.equal(body.metric.id, metricId);
      assert.equal(body.window.duringStart, isoDay(10));
      assert.equal(body.window.duringEnd, isoDay(20));
      assert.equal(body.doses.length, 2);
      // before [day0,day10): day1=100. during [day10,day20): day12,day18.
      // after [day20,day30): day25=88.
      assert.deepEqual(body.segments.before, {
        count: 1,
        min: 100,
        max: 100,
        mean: 100
      });
      assert.deepEqual(body.segments.during, {
        count: 2,
        min: 90,
        max: 94,
        mean: 92
      });
      assert.deepEqual(body.segments.after, {
        count: 1,
        min: 88,
        max: 88,
        mean: 88
      });
    } finally {
      await database.close();
    }
  }
);

test(
  "effect-window read for a Protocol spans its declared course, not its tagged Doses, and the range only scopes the markers",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-effect-protocol-${randomUUID()}`;
    const app = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId
    });
    const protocolId = createUuidV7();
    const compoundId = createUuidV7();
    const metricId = randomUUID();
    const updatedAt = new Date("2026-01-01T00:00:00.000Z");

    try {
      await insertUser(database, userId);
      await database.db.insert(schema.metrics).values({
        id: metricId,
        userId,
        deviceId: "device-1",
        name: "Body Weight",
        unit: "kilogram",
        valueShape: "scalar",
        metricGroup: "body",
        sortOrder: 0,
        updatedAt
      });
      for (const [day, value] of [
        [1, 100],
        [8, 96],
        [12, 92],
        [22, 90],
        [30, 89]
      ]) {
        await database.db.insert(schema.metricReadings).values({
          id: randomUUID(),
          userId,
          deviceId: "device-1",
          metricId,
          valueJson: { value },
          scalarValue: value,
          atTime: new Date(isoDay(day)),
          provenance: "manual",
          source: "manual",
          updatedAt
        });
      }

      // Declared course: day 5 → day 25. The tagged Doses (day 10, day 15)
      // sit inside it and must not narrow it; the untagged Dose on day 2 is
      // not this Protocol's at all.
      await insertOpaqueFixture(database, schema.protocols, {
        id: protocolId,
        userId,
        updatedAt,
        payload: {
          name: "Cut",
          // Inclusive local dates: at offset 0, DURING is [day 5, day 25).
          start_local_date: isoDay(5).slice(0, 10),
          end_local_date: isoDay(24).slice(0, 10)
        }
      });
      for (const [day, tagged] of [
        [10, true],
        [15, true],
        [2, false]
      ]) {
        await insertOpaqueFixture(database, schema.doses, {
          id: createUuidV7(),
          userId,
          updatedAt,
          payload: {
            compound_id: compoundId,
            compound_name: "X",
            amount_value: 5,
            unit: "gram",
            route: "oral",
            took_at: isoDay(day),
            protocol_id: tagged ? protocolId : null
          }
        });
      }

      const response = await app.request(
        `/agent/protocols/effect-window?protocolId=${protocolId}&metricId=${metricId}&from=${isoDay(1)}&to=${isoDay(12)}`,
        { headers: authHeaders() }
      );
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.window.duringStart, isoDay(5));
      assert.equal(body.window.duringEnd, isoDay(25));
      // The range [day 1, day 12) lists only the day-10 marker.
      assert.deepEqual(
        body.doses.map((dose) => dose.tookAt),
        [isoDay(10)]
      );
      // before [Dec 16, day 5): day 1. during [day 5, day 25): day 8, 12, 22.
      // after [day 25, Feb 14): day 30.
      assert.deepEqual(body.segments.before, {
        count: 1,
        min: 100,
        max: 100,
        mean: 100
      });
      assert.deepEqual(body.segments.during, {
        count: 3,
        min: 90,
        max: 96,
        mean: (96 + 92 + 90) / 3
      });
      assert.deepEqual(body.segments.after, {
        count: 1,
        min: 89,
        max: 89,
        mean: 89
      });

      // The same local dates read in UTC-3 start and end three hours later.
      const saoPaulo = await app.request(
        `/agent/protocols/effect-window?protocolId=${protocolId}&metricId=${metricId}&from=${isoDay(1)}&to=${isoDay(12)}&timezoneOffsetMinutes=-180`,
        { headers: authHeaders() }
      );
      assert.equal(saoPaulo.status, 200);
      const saoPauloBody = await saoPaulo.json();
      assert.equal(saoPauloBody.window.duringStart, "2026-01-05T03:00:00.000Z");
      assert.equal(saoPauloBody.window.duringEnd, "2026-01-25T03:00:00.000Z");

      const missing = await app.request(
        `/agent/protocols/effect-window?protocolId=${createUuidV7()}&metricId=${metricId}&from=${isoDay(1)}&to=${isoDay(12)}`,
        { headers: authHeaders() }
      );
      assert.equal(missing.status, 422);
    } finally {
      await database.close();
    }
  }
);

test(
  "Agent Schedule Versions are dated as the app dates them (D1), insert-only, stored sorted, and kept when their member is archived",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-protocols-versions-${randomUUID()}`;
    const app = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId
    });
    const today = utcToday();
    const start = addDays(today, -30);
    const protocolId = createUuidV7();
    const memberId = createUuidV7();
    const laterMemberId = createUuidV7();
    const firstVersionId = createUuidV7();
    const protocol = {
      id: protocolId,
      name: "Daily",
      startLocalDate: start,
      members: [{ id: memberId, compoundId: createUuidV7(), position: 0 }],
      schedules: [],
      targetOutcomes: []
    };
    const write = (protocolFields, idempotencyKey = `versions-${randomUUID()}`) =>
      post(app, "/agent/protocols/batch-write", {
        idempotencyKey,
        today,
        protocols: [{ ...protocol, ...protocolFields }]
      });
    const storedVersion = async (id) =>
      (await database.sql`select payload, deleted_at from schedules where id = ${id}`)[0];

    try {
      await insertUser(database, userId);

      // A member created with its Protocol: its first version applies from
      // the Protocol's (past) start. Unsorted times and weekdays are stored
      // sorted.
      const created = await write({
        schedules: [
          {
            id: firstVersionId,
            protocolCompoundId: memberId,
            rule: {
              v: 1,
              kind: "timed",
              days: { kind: "weekdays", weekdays: [5, 1, 3] },
              times: ["21:00", "09:00"]
            },
            ...creatineAmount
          }
        ]
      });
      assert.equal(created.status, 200);
      const first = await storedVersion(firstVersionId);
      assert.equal(first.payload.effective_from, start);
      assert.deepEqual(storedJson(first.payload.rule).times, ["09:00", "21:00"]);
      assert.deepEqual(storedJson(first.payload.rule).days.weekdays, [1, 3, 5]);
      assert.equal("frequency" in first.payload, false);

      // Two edits the same day insert two versions, both from today. A
      // member added to the started Protocol starts today too, so its past
      // days don't read "Not logged".
      const [editA, editB, laterVersion] = [createUuidV7(), createUuidV7(), createUuidV7()];
      const edited = await write({
        members: [
          ...protocol.members,
          { id: laterMemberId, compoundId: createUuidV7(), position: 1 }
        ],
        schedules: [
          {
            id: editA,
            protocolCompoundId: memberId,
            rule: timedDailyRule(["07:00"]),
            ...creatineAmount
          },
          {
            id: editB,
            protocolCompoundId: memberId,
            rule: timedDailyRule(["08:00"]),
            ...creatineAmount
          },
          {
            id: laterVersion,
            protocolCompoundId: laterMemberId,
            rule: { v: 1, kind: "as_needed" }
          }
        ]
      });
      assert.equal(edited.status, 200);
      for (const id of [editA, editB, laterVersion]) {
        assert.equal((await storedVersion(id)).payload.effective_from, today, id);
      }
      assert.equal((await storedVersion(laterVersion)).payload.dose_unit, null);
      assert.equal((await storedVersion(firstVersionId)).payload.effective_from, start);

      // Versions are insert-only: a reused id refuses the whole batch, and
      // the refusal rolls its idempotency receipt back.
      const retryKey = `versions-retry-${randomUUID()}`;
      const reused = await write(
        {
          schedules: [
            {
              id: firstVersionId,
              protocolCompoundId: memberId,
              rule: timedDailyRule(["10:00"]),
              ...creatineAmount
            }
          ]
        },
        retryKey
      );
      assert.equal(reused.status, 422);
      assert.deepEqual(
        (await reused.json()).errors.map((issue) => issue.rule),
        ["schedule_version_exists"]
      );
      assert.equal(
        storedJson((await storedVersion(firstVersionId)).payload.rule).times.join(","),
        "09:00,21:00"
      );
      const corrected = await write({ schedules: [] }, retryKey);
      assert.equal(corrected.status, 200);
      assert.equal((await corrected.json()).duplicate, false);

      // A version for a member of another Protocol is refused.
      const stray = await post(app, "/agent/protocols/batch-write", {
        idempotencyKey: `versions-stray-${randomUUID()}`,
        today,
        protocols: [
          {
            id: createUuidV7(),
            name: "Other",
            startLocalDate: start,
            schedules: [
              {
                id: createUuidV7(),
                protocolCompoundId: memberId,
                rule: timedDailyRule(["10:00"]),
                ...creatineAmount
              }
            ]
          }
        ]
      });
      assert.equal(stray.status, 422);
      assert.deepEqual(
        (await stray.json()).errors.map((issue) => issue.rule),
        ["schedule_member_not_found"]
      );

      // Removing a member archives it: the server stamps the time and
      // freezes archivedOn as today; its versions are untouched.
      const beforeArchive = Date.now();
      const removed = await write({
        members: [
          { ...protocol.members[0], archived: true },
          { id: laterMemberId, compoundId: createUuidV7(), position: 1 }
        ]
      });
      assert.equal(removed.status, 200);
      const [member] = await database.sql`
        select deleted_at, payload from protocol_compounds where id = ${memberId}
      `;
      assert.notEqual(member.deleted_at, null);
      assert.ok(new Date(member.deleted_at).getTime() >= beforeArchive - 1000);
      assert.equal(member.payload.archived_on, today);
      for (const id of [firstVersionId, editA, editB]) {
        assert.equal((await storedVersion(id)).deleted_at, null, id);
      }

      // An archived member is never restored: the Compound comes back as a
      // new member row.
      const restored = await write({});
      assert.equal(restored.status, 422);
      assert.deepEqual(
        (await restored.json()).errors.map((issue) => issue.rule),
        ["archived_row_not_restorable"]
      );

      // The read returns the whole history and the version an editor shows.
      const read = await app.request("/agent/protocols", { headers: authHeaders() });
      assert.equal(read.status, 200);
      const readProtocol = (await read.json()).protocols.find(
        (candidate) => candidate.id === protocolId
      );
      const readMember = readProtocol.members.find((candidate) => candidate.id === memberId);
      assert.equal(readMember.archivedOn, today);
      const sameDay = [editA, editB].sort();
      assert.deepEqual(
        readMember.versions.map((version) => version.id),
        [firstVersionId, ...sameDay]
      );
      assert.equal(readMember.currentVersion.id, sameDay[1]);
      assert.deepEqual(readMember.versions[0].rule.days, {
        kind: "weekdays",
        weekdays: [1, 3, 5]
      });
    } finally {
      await database.close();
    }
  }
);

test(
  "moving a Protocol's start later inserts nothing, and moving it earlier copies each member's earliest version",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-protocols-start-move-${randomUUID()}`;
    const app = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId
    });
    const today = utcToday();
    const start = addDays(today, -30);
    const protocolId = createUuidV7();
    const defaultAnchorMember = createUuidV7();
    const setAnchorMember = createUuidV7();
    const setAnchor = addDays(today, -100);
    const members = [
      { id: defaultAnchorMember, compoundId: createUuidV7(), position: 0 },
      { id: setAnchorMember, compoundId: createUuidV7(), position: 1 }
    ];
    const everyThreeDays = (anchor, anchorIsDefault) => ({
      v: 1,
      kind: "timed",
      days: { kind: "every_n_days", n: 3, anchor, anchor_is_default: anchorIsDefault },
      times: ["21:00"]
    });
    const write = (startLocalDate, extra = {}, cycleAnchor = startLocalDate) =>
      post(app, "/agent/protocols/batch-write", {
        idempotencyKey: `start-move-${randomUUID()}`,
        today,
        protocols: [
          {
            id: protocolId,
            name: "Skin",
            startLocalDate,
            period: {
              v: 1,
              cycle: { on_days: 60, off_days: 30, anchor: cycleAnchor, anchor_is_default: true },
              pauses: []
            },
            members,
            ...extra
          }
        ]
      });
    const versionsOf = async (memberId) =>
      (
        await database.sql`
          select id, payload from schedules
          where user_id = ${userId}
            and payload->>'protocol_compound_id' = ${memberId}
          order by payload->>'effective_from', id
        `
      ).map((row) => row.payload);

    try {
      await insertUser(database, userId);
      assert.equal(
        (
          await write(start, {
            schedules: [
              {
                id: createUuidV7(),
                protocolCompoundId: defaultAnchorMember,
                rule: everyThreeDays(start, true),
                ...creatineAmount
              },
              {
                id: createUuidV7(),
                protocolCompoundId: setAnchorMember,
                rule: everyThreeDays(setAnchor, false),
                ...creatineAmount
              }
            ]
          })
        ).status,
        200
      );

      const anchors = async (memberId) =>
        (await versionsOf(memberId)).map((version) => [
          version.effective_from,
          storedJson(version.rule).days.anchor
        ]);

      // Later: nothing is inserted. The version that applies on the new
      // start is already the latest one dated on or before it, and a default
      // anchor is read as the start, so it needs no rewriting (D1, D4).
      const laterStart = addDays(today, -10);
      assert.equal((await write(laterStart)).status, 200);
      assert.deepEqual(await anchors(defaultAnchorMember), [[start, start]]);
      assert.deepEqual(await anchors(setAnchorMember), [[start, setAnchor]]);

      // Earlier: a copy of each member's earliest version, dated from the new
      // start. The copy stores the new start in a default anchor, as the
      // app's writes do; an anchor the Agent set stays. The write re-sends
      // the period's default cycle anchor at the old start, as a read of the
      // Protocol returns it, and the new start is stored there.
      const earlierStart = addDays(today, -40);
      assert.equal((await write(earlierStart, {}, laterStart)).status, 200);
      assert.deepEqual(await anchors(defaultAnchorMember), [
        [earlierStart, earlierStart],
        [start, start]
      ]);
      assert.deepEqual(await anchors(setAnchorMember), [
        [earlierStart, setAnchor],
        [start, setAnchor]
      ]);
      for (const version of [
        ...(await versionsOf(defaultAnchorMember)),
        ...(await versionsOf(setAnchorMember))
      ]) {
        assert.equal(version.dose_amount_entered, "5");
      }

      const [stored] = await database.sql`select payload from protocols where id = ${protocolId}`;
      assert.equal(stored.payload.start_local_date, earlierStart);
      assert.equal(storedJson(stored.payload.period).cycle.anchor, earlierStart);
    } finally {
      await database.close();
    }
  }
);

test(
  "a start move copies only stored versions, and an edit in the same request keeps winning",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-protocols-start-move-batch-${randomUUID()}`;
    const app = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId
    });
    const today = utcToday();
    const versionsOf = async (memberId) =>
      (
        await database.sql`
          select id, payload from schedules
          where user_id = ${userId}
            and payload->>'protocol_compound_id' = ${memberId}
          order by payload->>'effective_from', id
        `
      ).map((row) => row.payload);
    const write = (protocol) =>
      post(app, "/agent/protocols/batch-write", {
        idempotencyKey: `start-move-batch-${randomUUID()}`,
        today,
        protocols: [protocol]
      });

    try {
      await insertUser(database, userId);

      // A started Protocol: moving its start earlier while adding a member.
      const startedId = createUuidV7();
      const start = addDays(today, -30);
      const kept = { id: createUuidV7(), compoundId: createUuidV7(), position: 0 };
      const added = { id: createUuidV7(), compoundId: createUuidV7(), position: 1 };
      const started = (startLocalDate, members, schedules) => ({
        id: startedId,
        name: "Daily",
        startLocalDate,
        members,
        schedules
      });
      assert.equal(
        (
          await write(
            started(start, [kept], [
              {
                id: createUuidV7(),
                protocolCompoundId: kept.id,
                rule: timedDailyRule(["09:00"]),
                ...creatineAmount
              }
            ])
          )
        ).status,
        200
      );
      const earlierStart = addDays(today, -45);
      assert.equal(
        (
          await write(
            started(earlierStart, [kept, added], [
              {
                id: createUuidV7(),
                protocolCompoundId: added.id,
                rule: timedDailyRule(["21:00"]),
                ...creatineAmount
              }
            ])
          )
        ).status,
        200
      );
      // D1: the kept member's earliest stored version is copied back to the
      // new start; the added member plans from today only, as in the app.
      assert.deepEqual(
        (await versionsOf(kept.id)).map((version) => version.effective_from),
        [earlierStart, start]
      );
      assert.deepEqual(
        (await versionsOf(added.id)).map((version) => version.effective_from),
        [today]
      );

      // A Protocol starting ahead: moving the start later while editing a
      // member. Nothing is copied, so the edit is dated by D1 from the latest
      // stored version (the old start, still ahead of today) and wins it by
      // id, so it is what plans from the new start.
      const aheadId = createUuidV7();
      const member = { id: createUuidV7(), compoundId: createUuidV7(), position: 0 };
      const aheadStart = addDays(today, 5);
      const ahead = (startLocalDate, schedules) => ({
        id: aheadId,
        name: "Cycle",
        startLocalDate,
        members: [member],
        schedules
      });
      assert.equal(
        (
          await write(
            ahead(aheadStart, [
              {
                id: createUuidV7(),
                protocolCompoundId: member.id,
                rule: timedDailyRule(["09:00"]),
                ...creatineAmount
              }
            ])
          )
        ).status,
        200
      );
      const laterStart = addDays(today, 10);
      const editId = createUuidV7();
      assert.equal(
        (
          await write(
            ahead(laterStart, [
              {
                id: editId,
                protocolCompoundId: member.id,
                rule: timedDailyRule(["07:00"]),
                ...creatineAmount
              }
            ])
          )
        ).status,
        200
      );
      const aheadVersions = await versionsOf(member.id);
      assert.deepEqual(
        aheadVersions.map((version) => [
          version.effective_from,
          storedJson(version.rule).times.join(",")
        ]),
        [
          [aheadStart, "09:00"],
          [aheadStart, "07:00"]
        ]
      );
      assert.equal(aheadVersions[1].id, editId);
    } finally {
      await database.close();
    }
  }
);

test(
  "moving the start earlier copies the members planned from the old start, archived ones and ones the same write archives, but not a member added mid-course or one with no versions",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-protocols-start-move-members-${randomUUID()}`;
    const app = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId
    });
    const today = utcToday();
    const start = addDays(today, -30);
    const protocolId = createUuidV7();
    const member = (position) => ({ id: createUuidV7(), compoundId: createUuidV7(), position });
    const planned = member(0);
    const archived = member(1);
    const removedNow = member(2);
    const unscheduled = member(3);
    const midCourse = member(4);
    const schedule = (memberRow, times) => ({
      id: createUuidV7(),
      protocolCompoundId: memberRow.id,
      rule: timedDailyRule(times),
      ...creatineAmount
    });
    const write = (startLocalDate, members, schedules = []) =>
      post(app, "/agent/protocols/batch-write", {
        idempotencyKey: `start-move-members-${randomUUID()}`,
        today,
        protocols: [{ id: protocolId, name: "Daily", startLocalDate, members, schedules }]
      });
    const datesOf = async (memberRow) =>
      (
        await database.sql`
          select payload from schedules
          where user_id = ${userId}
            and payload->>'protocol_compound_id' = ${memberRow.id}
          order by payload->>'effective_from', id
        `
      ).map((row) => row.payload.effective_from);

    try {
      await insertUser(database, userId);
      assert.equal(
        (
          await write(start, [planned, archived, removedNow, unscheduled], [
            schedule(planned, ["09:00"]),
            schedule(archived, ["12:00"]),
            schedule(removedNow, ["18:00"])
          ])
        ).status,
        200
      );
      // Archive one member and add another mid-course, the start unchanged.
      assert.equal(
        (
          await write(
            start,
            [planned, { ...archived, archived: true }, removedNow, unscheduled, midCourse],
            [schedule(midCourse, ["21:00"])]
          )
        ).status,
        200
      );

      // Move the start earlier, archiving another member in the same write.
      // The member archived before is left out of the write: a stored member
      // of the Protocol gets its copy whether or not the write lists it, as
      // the app copies from every member row it stores.
      const earlierStart = addDays(today, -45);
      assert.equal(
        (
          await write(earlierStart, [
            planned,
            { ...removedNow, archived: true },
            unscheduled,
            midCourse
          ])
        ).status,
        200
      );

      assert.deepEqual(await datesOf(planned), [earlierStart, start]);
      assert.deepEqual(await datesOf(archived), [earlierStart, start]);
      assert.deepEqual(await datesOf(removedNow), [earlierStart, start]);
      // A member added mid-course keeps its own first date, and one with no
      // versions already covers every date.
      assert.deepEqual(await datesOf(midCourse), [today]);
      assert.deepEqual(await datesOf(unscheduled), []);

      // The copy is of the earliest version, and the member this write
      // archived is archived after its copy.
      const [removedCopy] = await database.sql`
        select payload from schedules
        where user_id = ${userId}
          and payload->>'protocol_compound_id' = ${removedNow.id}
          and payload->>'effective_from' = ${earlierStart}
      `;
      assert.deepEqual(storedJson(removedCopy.payload.rule).times, ["18:00"]);
      assert.equal(removedCopy.payload.dose_amount_entered, "5");
      const [removedMember] = await database.sql`
        select deleted_at, payload from protocol_compounds where id = ${removedNow.id}
      `;
      assert.notEqual(removedMember.deleted_at, null);
      assert.equal(removedMember.payload.archived_on, today);
    } finally {
      await database.close();
    }
  }
);

test(
  "moving the start earlier gives no copy to a member archived before its earliest version, and still gives one to a member the same write archives",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-protocols-start-move-removed-early-${randomUUID()}`;
    const app = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId
    });
    const today = utcToday();
    // The start is still ahead, so every member's first version is dated
    // from it (D1).
    const futureStart = addDays(today, 10);
    const protocolId = createUuidV7();
    const member = (position) => ({ id: createUuidV7(), compoundId: createUuidV7(), position });
    const kept = member(0);
    const removedEarly = member(1);
    const removedNow = member(2);
    const schedule = (memberRow, times) => ({
      id: createUuidV7(),
      protocolCompoundId: memberRow.id,
      rule: timedDailyRule(times),
      ...creatineAmount
    });
    const write = (startLocalDate, members, schedules = []) =>
      post(app, "/agent/protocols/batch-write", {
        idempotencyKey: `start-move-removed-early-${randomUUID()}`,
        today,
        protocols: [{ id: protocolId, name: "Daily", startLocalDate, members, schedules }]
      });
    const datesOf = async (memberRow) =>
      (
        await database.sql`
          select payload from schedules
          where user_id = ${userId}
            and payload->>'protocol_compound_id' = ${memberRow.id}
          order by payload->>'effective_from', id
        `
      ).map((row) => row.payload.effective_from);

    try {
      await insertUser(database, userId);
      assert.equal(
        (
          await write(futureStart, [kept, removedEarly, removedNow], [
            schedule(kept, ["09:00"]),
            schedule(removedEarly, ["12:00"]),
            schedule(removedNow, ["18:00"])
          ])
        ).status,
        200
      );
      // Removed before the start came: its archived_on (today) is before its
      // earliest version (the future start), so it planned no day.
      assert.equal(
        (
          await write(futureStart, [kept, { ...removedEarly, archived: true }, removedNow])
        ).status,
        200
      );

      // Move the start earlier, archiving another member in the same write.
      const earlierStart = addDays(today, -20);
      assert.equal(
        (await write(earlierStart, [kept, { ...removedNow, archived: true }])).status,
        200
      );

      assert.deepEqual(await datesOf(kept), [earlierStart, futureStart]);
      // Its archived_on is read as stored before the write, so the member
      // this write archives still gets its copy, and is then archived.
      assert.deepEqual(await datesOf(removedNow), [earlierStart, futureStart]);
      const [removedNowRow] = await database.sql`
        select payload from protocol_compounds where id = ${removedNow.id}
      `;
      assert.equal(removedNowRow.payload.archived_on, today);
      // Removed before it planned anything: no copy.
      assert.deepEqual(await datesOf(removedEarly), [futureStart]);
    } finally {
      await database.close();
    }
  }
);

test(
  "an archived Protocol is read-only, an archived member is re-sent but never restored, and an equal Schedule is still inserted",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-protocols-archived-${randomUUID()}`;
    const app = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId
    });
    const today = utcToday();
    const start = addDays(today, -30);
    const protocolId = createUuidV7();
    const kept = { id: createUuidV7(), compoundId: createUuidV7(), position: 0 };
    const removed = { id: createUuidV7(), compoundId: createUuidV7(), position: 1 };
    const protocol = { id: protocolId, name: "Daily", startLocalDate: start };
    const write = (fields, writeToday = today) =>
      post(app, "/agent/protocols/batch-write", {
        idempotencyKey: `archived-${randomUUID()}`,
        today: writeToday,
        protocols: [{ ...protocol, ...fields }]
      });
    const rulesOf = async (body) => (await body.json()).errors.map((issue) => issue.rule);
    const versionsOf = async (memberId) =>
      database.sql`
        select id, payload from schedules
        where user_id = ${userId}
          and payload->>'protocol_compound_id' = ${memberId}
        order by payload->>'effective_from', id
      `;
    const memberStamp = async (memberId) =>
      (
        await database.sql`
          select deleted_at, payload from protocol_compounds where id = ${memberId}
        `
      )[0];

    try {
      await insertUser(database, userId);
      const firstVersionId = createUuidV7();
      assert.equal(
        (
          await write({
            members: [kept, removed],
            schedules: [
              {
                id: firstVersionId,
                protocolCompoundId: kept.id,
                rule: timedDailyRule(["09:00"]),
                ...creatineAmount
              }
            ]
          })
        ).status,
        200
      );

      // D6: an Agent Schedule is an explicit edit, so one equal to the
      // current version is inserted under the id the Agent chose.
      const equalVersionId = createUuidV7();
      assert.equal(
        (
          await write({
            members: [kept, removed],
            schedules: [
              {
                id: equalVersionId,
                protocolCompoundId: kept.id,
                rule: timedDailyRule(["09:00"]),
                ...creatineAmount
              }
            ]
          })
        ).status,
        200
      );
      const keptVersions = await versionsOf(kept.id);
      assert.deepEqual(
        keptVersions.map((row) => [row.id, row.payload.effective_from]),
        [
          [firstVersionId, start],
          [equalVersionId, today]
        ]
      );
      assert.equal(keptVersions[1].payload.rule, keptVersions[0].payload.rule);

      // Archive a member, then re-send it archived: accepted, and its first
      // stamp is kept, even under a later today.
      assert.equal(
        (await write({ members: [kept, { ...removed, archived: true }] })).status,
        200
      );
      const firstStamp = await memberStamp(removed.id);
      assert.equal(firstStamp.payload.archived_on, today);
      const resent = await write(
        { members: [kept, { ...removed, archived: true }] },
        addDays(today, 1)
      );
      assert.equal(resent.status, 200);
      const keptStamp = await memberStamp(removed.id);
      assert.equal(
        new Date(keptStamp.deleted_at).getTime(),
        new Date(firstStamp.deleted_at).getTime()
      );
      assert.equal(keptStamp.payload.archived_on, today);
      // archived: false on it is never a restore.
      const restored = await write({ members: [kept, { ...removed, archived: false }] });
      assert.equal(restored.status, 422);
      assert.deepEqual(await rulesOf(restored), ["archived_row_not_restorable"]);

      // Archive the Protocol: from then on any write naming it is refused,
      // whatever it sends, and the stored row is unchanged.
      assert.equal(
        (await write({ archived: true, members: [kept, { ...removed, archived: true }] })).status,
        200
      );
      const [archivedProtocol] = await database.sql`
        select deleted_at, payload from protocols where id = ${protocolId}
      `;
      assert.equal(archivedProtocol.payload.archived_on, today);
      for (const fields of [
        { archived: true },
        { archived: true, members: [kept, { ...removed, archived: true }] },
        { name: "Renamed" },
        {
          members: [kept],
          schedules: [
            {
              id: createUuidV7(),
              protocolCompoundId: kept.id,
              rule: timedDailyRule(["10:00"]),
              ...creatineAmount
            }
          ]
        }
      ]) {
        const refused = await write(fields);
        assert.equal(refused.status, 422, JSON.stringify(fields));
        assert.deepEqual(await rulesOf(refused), ["protocol_archived"], JSON.stringify(fields));
      }
      const [unchanged] = await database.sql`
        select deleted_at, payload from protocols where id = ${protocolId}
      `;
      assert.equal(unchanged.payload.name, "Daily");
      assert.equal(
        new Date(unchanged.deleted_at).getTime(),
        new Date(archivedProtocol.deleted_at).getTime()
      );
      assert.equal((await versionsOf(kept.id)).length, 2);

      // A Protocol tombstoned by undo (deleted_at with no archived_on) never
      // existed: a write naming it is refused whatever it sends, a re-sent
      // archived: true included, so it can't be edited or have its start
      // moved, and no version is inserted for its members.
      const undoneId = createUuidV7();
      const undoneMember = { id: createUuidV7(), compoundId: createUuidV7(), position: 0 };
      const writeUndone = (fields) =>
        post(app, "/agent/protocols/batch-write", {
          idempotencyKey: `archived-undone-${randomUUID()}`,
          today,
          protocols: [{ id: undoneId, name: "Undone", startLocalDate: start, ...fields }]
        });
      assert.equal(
        (
          await writeUndone({
            members: [undoneMember],
            schedules: [
              {
                id: createUuidV7(),
                protocolCompoundId: undoneMember.id,
                rule: timedDailyRule(["09:00"]),
                ...creatineAmount
              }
            ]
          })
        ).status,
        200
      );
      await database.sql`
        update protocols
        set deleted_at = now(),
            payload = payload || jsonb_build_object('deleted_at', now(), 'archived_on', null)
        where id = ${undoneId}
      `;
      for (const fields of [
        { archived: true },
        { archived: true, startLocalDate: addDays(start, -10), members: [undoneMember] },
        { archived: true, name: "Renamed" },
        { name: "Renamed" }
      ]) {
        const refused = await writeUndone(fields);
        assert.equal(refused.status, 422, JSON.stringify(fields));
        assert.deepEqual(
          await rulesOf(refused),
          ["archived_row_not_restorable"],
          JSON.stringify(fields)
        );
      }
      const [undone] = await database.sql`
        select payload from protocols where id = ${undoneId}
      `;
      assert.equal(undone.payload.name, "Undone");
      assert.equal(undone.payload.start_local_date, start);
      assert.equal(undone.payload.archived_on, null);
      assert.equal((await versionsOf(undoneMember.id)).length, 1);
    } finally {
      await database.close();
    }
  }
);

test(
  "rule and period are stored as JSON text, and a row stored as an object still reads and copies",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-protocols-json-text-${randomUUID()}`;
    const app = createProtocolsApp({
      store: createDrizzleAgentProtocolsStore(database.db),
      userId
    });
    const today = utcToday();
    const start = addDays(today, -30);
    const protocolId = createUuidV7();
    const memberId = createUuidV7();
    const versionId = createUuidV7();
    const period = {
      v: 1,
      cycle: { on_days: 60, off_days: 30, anchor: start, anchor_is_default: true },
      pauses: []
    };
    const rule = {
      v: 1,
      kind: "timed",
      days: { kind: "weekdays", weekdays: [1, 3, 5] },
      times: ["09:00", "21:00"]
    };
    const write = (startLocalDate, schedules = []) =>
      post(app, "/agent/protocols/batch-write", {
        idempotencyKey: `json-text-${randomUUID()}`,
        today,
        protocols: [
          {
            id: protocolId,
            name: "Skin",
            startLocalDate,
            // Always the period as first written: its default cycle anchor
            // stays at the first start, and a start move stores the new one.
            period,
            members: [{ id: memberId, compoundId: createUuidV7(), position: 0 }],
            schedules
          }
        ]
      });
    const readMember = async () => {
      const read = await app.request("/agent/protocols", { headers: authHeaders() });
      assert.equal(read.status, 200);
      const readProtocol = (await read.json()).protocols.find(
        (candidate) => candidate.id === protocolId
      );
      return {
        protocol: readProtocol,
        member: readProtocol.members.find((candidate) => candidate.id === memberId)
      };
    };

    try {
      await insertUser(database, userId);
      assert.equal(
        (
          await write(start, [
            { id: versionId, protocolCompoundId: memberId, rule, ...creatineAmount }
          ])
        ).status,
        200
      );

      // Both are the codec's encoding, as JSON text, as the app stores them.
      const [storedVersion] = await database.sql`
        select payload from schedules where id = ${versionId}
      `;
      assert.equal(storedVersion.payload.rule, JSON.stringify(rule));
      const [storedProtocol] = await database.sql`
        select payload from protocols where id = ${protocolId}
      `;
      assert.equal(storedProtocol.payload.period, JSON.stringify(period));

      // A row an earlier Agent write stored as an object still reads.
      await database.sql`
        update schedules
        set payload = jsonb_set(payload, '{rule}', (payload->>'rule')::jsonb)
        where id = ${versionId}
      `;
      await database.sql`
        update protocols
        set payload = jsonb_set(payload, '{period}', (payload->>'period')::jsonb)
        where id = ${protocolId}
      `;
      const [objectVersion] = await database.sql`
        select payload from schedules where id = ${versionId}
      `;
      assert.equal(typeof objectVersion.payload.rule, "object");
      const objectRead = await readMember();
      assert.deepEqual(objectRead.protocol.period, period);
      assert.deepEqual(objectRead.member.currentVersion.rule, rule);

      // A start move copies from the object row and writes the copy as text.
      const earlierStart = addDays(today, -40);
      assert.equal((await write(earlierStart)).status, 200);
      const [copy] = await database.sql`
        select payload from schedules
        where user_id = ${userId}
          and payload->>'protocol_compound_id' = ${memberId}
          and id <> ${versionId}
      `;
      assert.equal(copy.payload.effective_from, earlierStart);
      assert.deepEqual(storedJson(copy.payload.rule), rule);
      const copiedRead = await readMember();
      assert.deepEqual(
        copiedRead.member.versions.map((version) => version.effectiveFrom),
        [earlierStart, start]
      );
      assert.deepEqual(copiedRead.protocol.period.cycle.anchor, earlierStart);
    } finally {
      await database.close();
    }
  }
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function isoDay(day) {
  return new Date(Date.UTC(2026, 0, day)).toISOString();
}

/** The server's UTC date: always within the one day `today` may differ by. */
function utcToday() {
  return new Date().toISOString().slice(0, 10);
}

function addDays(localDate, days) {
  const date = new Date(`${localDate}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

/** A stored `rule` or `period`: JSON text, the form every writer stores. */
function storedJson(value) {
  assert.equal(typeof value, "string");
  return JSON.parse(value);
}

function timedDailyRule(times) {
  return { v: 1, kind: "timed", days: { kind: "daily" }, times };
}

const creatineAmount = {
  doseAmountValue: 5,
  doseAmountEntered: "5",
  doseUnit: "gram",
  route: "oral"
};

function protocolWriteRequest() {
  const memberId = createUuidV7();
  return {
    idempotencyKey: `protocol-${randomUUID()}`,
    today: utcToday(),
    protocols: [
      {
        id: createUuidV7(),
        name: "Daily",
        startLocalDate: addDays(utcToday(), -30),
        members: [{ id: memberId, compoundId: createUuidV7(), position: 0 }],
        schedules: [
          {
            id: createUuidV7(),
            protocolCompoundId: memberId,
            rule: timedDailyRule(["09:00"]),
            ...creatineAmount
          }
        ],
        targetOutcomes: []
      }
    ]
  };
}

function withProtocol(request, fields) {
  return { ...request, protocols: [{ ...request.protocols[0], ...fields }] };
}

function withSchedule(request, fields) {
  const protocol = request.protocols[0];
  return withProtocol(request, {
    schedules: [{ ...protocol.schedules[0], ...fields }]
  });
}

function doseFixture(id, compoundName, tookAt) {
  return {
    id,
    compoundName,
    amount: "5",
    unit: "gram",
    route: "oral",
    tookAt,
    timezone: "UTC",
    localDate: tookAt.slice(0, 10)
  };
}

function stubStore(overrides) {
  const notImplemented = (name) => async () => {
    throw new Error(`${name} not stubbed`);
  };
  return {
    listCompounds: notImplemented("listCompounds"),
    listProtocols: notImplemented("listProtocols"),
    listDoses: notImplemented("listDoses"),
    readEffectWindow: notImplemented("readEffectWindow"),
    writeDoseBatch: notImplemented("writeDoseBatch"),
    writeCompoundBatch: notImplemented("writeCompoundBatch"),
    writeProtocolBatch: notImplemented("writeProtocolBatch"),
    ...overrides
  };
}

function createProtocolsApp({ store, syncNudgePublisher, userId = "user-1" }) {
  return createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore(userId),
    agentProtocolsStore: store,
    syncNudgePublisher
  });
}

function createAgentKeyStore(userId) {
  return {
    async authenticateAgentApiKey(secret) {
      if (secret !== "prn_agent_secret") {
        return null;
      }
      return { userId, keyId: "agent-key-1", keyName: "Garage coach" };
    },
    async createAgentApiKey() {
      throw new Error("createAgentApiKey should not be called.");
    },
    async listAgentApiKeys() {
      throw new Error("listAgentApiKeys should not be called.");
    },
    async revokeAgentApiKey() {
      throw new Error("revokeAgentApiKey should not be called.");
    },
    async verifySessionBearerToken() {
      throw new Error("verifySessionBearerToken should not be called.");
    }
  };
}

function authHeaders(extra = {}) {
  return {
    authorization: "Bearer prn_agent_secret",
    "content-type": "application/json",
    ...extra
  };
}

function post(app, path, body) {
  return app.request(path, {
    method: "POST",
    headers: authHeaders(),
    body: JSON.stringify(body)
  });
}

async function insertUser(database, userId) {
  await database.db.insert(schema.user).values({
    id: userId,
    name: "Agent Protocols User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
}

function insertOpaqueFixture(
  database,
  table,
  { id, userId, updatedAt, payload }
) {
  return database.db.insert(table).values({
    id,
    userId,
    deviceId: "legacy-agent-device",
    payload,
    updatedAt,
    deletedAt: null,
    receivedAt: updatedAt
  });
}
