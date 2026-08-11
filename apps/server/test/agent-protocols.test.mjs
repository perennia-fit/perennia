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

test("prepareAgentProtocolBatchWrite builds protocol + members + schedules + target outcomes without touching Doses", () => {
  const prepared = prepareAgentProtocolBatchWrite({
    request: {
      idempotencyKey: "k",
      protocols: [
        {
          id: "p1",
          name: "Lean bulk",
          startDate: "2026-06-01T00:00:00.000Z",
          endDate: null,
          members: [{ id: "m1", compoundId: "c1", position: 0 }],
          schedules: [
            {
              id: "s1",
              protocolCompoundId: "m1",
              doseAmountValue: 5,
              doseAmountEntered: "5",
              doseUnit: "gram",
              frequency: "onceDaily",
              route: "oral"
            }
          ],
          targetOutcomes: [{ id: "t1", metricId: "metric-weight", outcomeKind: "metric" }]
        }
      ]
    }
  });
  assert.equal(prepared.accepted, true);
  assert.equal(prepared.protocols.length, 1);
  assert.equal(prepared.members[0].payload.protocol_id, "p1");
  assert.equal(prepared.schedules[0].payload.frequency, "onceDaily");
  assert.equal(prepared.targetOutcomes[0].payload.metric_id, "metric-weight");
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
// Deterministic effect-window computation fixture
// ---------------------------------------------------------------------------

test("computeEffectWindowSegments buckets samples into before/during/after with count/min/max/mean", () => {
  // DURING = first dose (day 10) → last dose (day 20); length 10 days.
  // BEFORE = [day 0, day 10); AFTER = [day 20, day 30).
  const d = (day) => new Date(Date.UTC(2026, 0, day));
  const segments = computeEffectWindowSegments({
    doses: [{ tookAt: d(10) }, { tookAt: d(15) }, { tookAt: d(20) }],
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

  assert.equal(segments.duringStart.toISOString(), d(10).toISOString());
  assert.equal(segments.duringEnd.toISOString(), d(20).toISOString());

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
  const segments = computeEffectWindowSegments({ doses: [], samples: [] });
  assert.equal(segments.duringStart, null);
  assert.equal(segments.duringEnd, null);
  assert.deepEqual(segments.before, { count: 0, min: null, max: null, mean: null });
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
        protocols: [
          {
            id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d003",
            name: "Base",
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
          protocols: [
            {
              id: uuidV4,
              name: "Base",
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
          protocols: [
            {
              id: protocolId,
              name: "Base",
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
          protocols: [
            {
              id: protocolId,
              name: "Base",
              members: [
                { id: memberId, compoundId: compoundReference, position: 0 }
              ],
              schedules: [
                {
                  id: uuidV4,
                  protocolCompoundId: memberId,
                  frequency: "onceDaily"
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
          protocols: [
            {
              id: protocolId,
              name: "Base",
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
        protocols: [
          {
            id: "legacy-protocol-id",
            name: "Base",
            deletedAt: "2026-06-03T00:00:00.000Z",
            members: [],
            schedules: [],
            targetOutcomes: []
          }
        ]
      });
      assert.equal(protocol.status, 200);
      assert.equal((await protocol.json()).protocols[0].outcome, "applied");
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
        protocols: [
          {
            id: createUuidV7(),
            name: "Base",
            members: [],
            schedules: [
              {
                id: createUuidV7(),
                protocolCompoundId: "missing-legacy-member",
                frequency: "onceDaily"
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
        protocols: [
          {
            id: createUuidV7(),
            name: "Base",
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
        protocols: [
          {
            id: protocolId,
            name: "Lean bulk",
            startDate: "2026-06-01T00:00:00.000Z",
            endDate: null,
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
        protocols: [
          {
            id: protocolId,
            name: "Lean bulk",
            startDate: "2026-06-01T00:00:00.000Z",
            endDate: null,
            deletedAt: "2026-07-01T00:00:00.000Z",
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
        protocols: [
          {
            id: protocolId,
            name: "Lean bulk",
            startDate: "2026-06-01T00:00:00.000Z",
            endDate: null,
            members: [{ id: memberId, compoundId: compoundIds[0], position: 0 }],
            schedules: [
              {
                id: scheduleId,
                protocolCompoundId: memberId,
                doseAmountValue: 5,
                doseAmountEntered: "5",
                doseUnit: "gram",
                frequency: "onceDaily",
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
      assert.equal(protocol.members.length, 1);
      assert.equal(protocol.members[0].compoundId, compoundIds[0]);
      assert.equal(protocol.schedules.length, 1);
      assert.equal(protocol.schedules[0].frequency, "onceDaily");
      assert.equal(protocol.targetOutcomes.length, 1);
      assert.equal(protocol.targetOutcomes[0].metricId, "metric-weight");
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function isoDay(day) {
  return new Date(Date.UTC(2026, 0, day)).toISOString();
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
