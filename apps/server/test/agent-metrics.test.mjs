import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import test from "node:test";

import {
  applyMigrations,
  createApp,
  createDatabaseClient,
  createDrizzleAgentMetricStore,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

test("agent metric routes authenticate and pass bounded query/write contracts to the store", async () => {
  const writes = [];
  const app = createAgentMetricApp({
    agentMetricStore: {
      async listMetrics(input) {
        assert.equal(input.userId, "user-1");
        assert.equal(input.query.search, "body");
        assert.equal(input.query.metricKey, "bodyWeight");
        return {
          metrics: [
            {
              id: "metric-body-weight",
              name: "Body Weight",
              canonicalKey: "bodyWeight",
              aliases: ["bodyMass", "weight"],
              dataClass: "bodyComposition",
              unit: "kilogram",
              valueShape: "scalar",
              metricGroup: "body",
              goalType: null,
              goalTargetValue: null,
              enabled: true,
              pinned: true,
              sortOrder: 0,
              updatedAt: "2026-06-24T05:00:00.000Z",
              deletedAt: null
            }
          ],
          fields: [
            "id",
            "name",
            "canonicalKey",
            "aliases",
            "dataClass",
            "unit",
            "valueShape",
            "metricGroup",
            "goalType",
            "goalTargetValue",
            "enabled",
            "pinned",
            "sortOrder",
            "updatedAt",
            "deletedAt"
          ],
          limit: input.query.limit,
          nextCursor: null,
          totalMatched: 1
        };
      },
      async listMetricReadings(input) {
        assert.equal(input.userId, "user-1");
        assert.equal(input.query.metricId, "metric-body-weight");
        assert.equal(input.query.metricKey, "bodyWeight");
        return {
          readings: [],
          fields: [
            "id",
            "metricId",
            "externalActivityId",
            "valueShape",
            "unit",
            "valueJson",
            "scalarValue",
            "scalarEntered",
            "atTime",
            "windowStartedAt",
            "windowEndedAt",
            "provenance",
            "source",
            "externalId",
            "comment",
            "warnings",
            "updatedAt",
            "deletedAt"
          ],
          limit: input.query.limit,
          nextCursor: null,
          totalMatched: 0
        };
      },
      async writeMetricBatch(input) {
        writes.push(input);
        return {
          accepted: true,
          duplicate: false,
          serverClock: "2026-06-24T05:00:01.000Z",
          activityLogEntries: input.request.metrics.length + input.request.readings.length,
          applied: input.request.readings.map((reading) => ({
            id: reading.id,
            updatedAt: reading.updatedAt ?? "2026-06-24T05:00:00.000Z",
            deviceId: input.deviceId
          })),
          metrics: input.request.metrics.map((metric) => ({
            id: metric.id,
            name: metric.name,
            valueShape: metric.valueShape,
            unit: metric.unit,
            metricGroup: metric.metricGroup,
            applied: true,
            outcome: "applied"
          })),
          readings: input.request.readings.map((reading) => ({
            id: reading.id,
            metricId: reading.metricId,
            valueShape: reading.value.shape,
            unit: "kilogram",
            warnings: [],
            applied: true,
            outcome: "applied"
          }))
        };
      }
    }
  });

  const listResponse = await getAgent(
    app,
    "/agent/metrics?search=body&metricKey=bodyWeight&limit=10"
  );
  assert.equal(listResponse.status, 200);
  assert.equal((await listResponse.json()).metrics[0].name, "Body Weight");

  const readingListResponse = await getAgent(
    app,
    "/agent/metrics/readings?metricId=metric-body-weight&metricKey=bodyWeight&limit=5"
  );
  assert.equal(readingListResponse.status, 200);

  const request = metricBatchRequest({
    idempotencyKey: "agent-metric-route-test"
  });
  const writeResponse = await postAgentMetrics(app, request, {
    "x-correlation-id": "corr-agent-metric"
  });

  assert.equal(writeResponse.status, 200);
  const body = await writeResponse.json();
  assert.equal(body.accepted, true);
  assert.equal(body.batchId, "agent-metric-route-test");
  assert.equal(body.metrics[0].id, "metric-body-weight");
  assert.equal(body.readings[0].id, "reading-body-weight");

  assert.equal(writes.length, 1);
  assert.equal(writes[0].userId, "user-1");
  assert.equal(writes[0].batchId, "agent-metric-route-test");
  assert.equal(writes[0].deviceId, "agent:agent-key-1");
  assert.equal(writes[0].correlationId, "corr-agent-metric");
});

test(
  "agent metric batch write normalizes readings, records one Activity Log batch, replays idempotently, and reads back",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-metric-user-${randomUUID()}`;
    const nudges = [];
    const app = createAgentMetricApp({
      userId,
      agentMetricStore: createDrizzleAgentMetricStore(database.db),
      syncNudgePublisher: {
        async enqueueSyncNudge(input) {
          nudges.push(input);
          return { enqueued: true, jobId: `agent-metric-nudge-${nudges.length}` };
        }
      }
    });
    const idempotencyKey = `agent-metric-${randomUUID()}`;
    const request = metricBatchRequest({ idempotencyKey });

    try {
      await seedUser(database, userId);

      const response = await postAgentMetrics(app, request);
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.accepted, true);
      assert.equal(body.duplicate, false);
      assert.equal(body.metrics[0].name, "Body Weight");
      assert.equal(body.metrics[0].applied, true);
      assert.equal(body.metrics[0].outcome, "applied");
      assert.equal(body.readings[0].valueShape, "scalar");
      assert.equal(body.readings[0].unit, "kilogram");
      assert.equal(body.readings[0].applied, true);
      assert.equal(body.readings[0].outcome, "applied");

      const metricRows = await database.sql`
        select * from metrics where id = ${request.metrics[0].id}
      `;
      assert.equal(metricRows.length, 1);
      assert.equal(metricRows[0].user_id, userId);
      assert.equal(metricRows[0].name, "Body Weight");

      const readingRows = await database.sql`
        select * from metric_readings where id = ${request.readings[0].id}
      `;
      assert.equal(readingRows.length, 1);
      assert.equal(readingRows[0].user_id, userId);
      assert.equal(readingRows[0].metric_id, request.metrics[0].id);
      assert.equal(readingRows[0].scalar_entered, "200");
      assert.ok(Math.abs(readingRows[0].scalar_value - 90.718474) < 0.000001);
      assert.equal(readingRows[0].value_json.unit, "kilogram");
      assert.equal(readingRows[0].value_json.enteredUnit, "pound");
      assert.equal(readingRows[0].source, "agent");
      assert.equal(readingRows[0].provenance, "agent");

      const activityRows = await database.sql`
        select entity_table, entity_id, batch_id
        from activity_log
        where user_id = ${userId}
        order by entity_table, entity_id
      `;
      assert.deepEqual(
        activityRows.map((row) => row.entity_table).sort(),
        ["agent_metric_batches", "metric_readings", "metrics"]
      );
      assert.ok(activityRows.every((row) => row.batch_id === idempotencyKey));

      assert.equal(nudges.length, 1);
      assert.equal(nudges[0].userId, userId);
      assert.equal(nudges[0].sourceDeviceId, "agent:agent-key-1");

      const retryResponse = await postAgentMetrics(app, request);
      assert.equal(retryResponse.status, 200);
      const retryBody = await retryResponse.json();
      assert.equal(retryBody.duplicate, true);
      assert.equal(retryBody.metrics[0].applied, false);
      assert.equal(retryBody.metrics[0].outcome, "duplicate");
      const activityRowsAfterRetry = await database.sql`
        select id from activity_log where user_id = ${userId}
      `;
      assert.equal(activityRowsAfterRetry.length, 3);

      const conflictResponse = await postAgentMetrics(app, {
        ...request,
        readings: [
          {
            ...request.readings[0],
            comment: "same idempotency key, different body"
          }
        ]
      });
      assert.equal(conflictResponse.status, 422);
      const conflictBody = await conflictResponse.json();
      assert.equal(
        conflictBody.errors[0].rule,
        "idempotency_key_conflict"
      );

      const staleResponse = await postAgentMetrics(
        app,
        metricBatchRequest({
          idempotencyKey: `agent-metric-stale-${randomUUID()}`,
          metrics: [
            {
              ...request.metrics[0],
              updatedAt: "2026-06-24T04:59:00.000Z"
            }
          ],
          readings: [
            {
              ...request.readings[0],
              value: { shape: "scalar", entered: "300", unit: "pound" },
              updatedAt: "2026-06-24T04:59:00.000Z"
            }
          ]
        })
      );
      assert.equal(staleResponse.status, 200);
      const staleBody = await staleResponse.json();
      assert.equal(staleBody.metrics[0].applied, false);
      assert.equal(staleBody.metrics[0].outcome, "superseded");
      assert.equal(staleBody.readings[0].applied, false);
      assert.equal(staleBody.readings[0].outcome, "superseded");
      assert.equal(nudges.length, 2);

      const readingRowsAfterStale = await database.sql`
        select scalar_entered from metric_readings where id = ${request.readings[0].id}
      `;
      assert.equal(readingRowsAfterStale[0].scalar_entered, "200");

      const listResponse = await getAgent(app, "/agent/metrics?search=body");
      assert.equal(listResponse.status, 200);
      const listBody = await listResponse.json();
      assert.equal(listBody.metrics.length, 1);
      assert.deepEqual(listBody.fields.slice(0, 2), ["id", "name"]);
      assert.equal(listBody.metrics[0].id, request.metrics[0].id);

      const readingsResponse = await getAgent(
        app,
        `/agent/metrics/readings?metricId=${request.metrics[0].id}&fields=id,metricId,scalarValue`
      );
      assert.equal(readingsResponse.status, 200);
      const readingsBody = await readingsResponse.json();
      assert.equal(readingsBody.readings.length, 1);
      assert.deepEqual(readingsBody.fields, ["id", "metricId", "scalarValue"]);
      assert.equal(readingsBody.readings[0].id, request.readings[0].id);

      const rejectedResponse = await postAgentMetrics(
        app,
        metricBatchRequest({
          idempotencyKey: `agent-metric-invalid-${randomUUID()}`,
          metrics: [],
          readings: [
            {
              ...request.readings[0],
              id: "missing-metric-reading",
              metricId: "missing-metric"
            }
          ]
        })
      );
      assert.equal(rejectedResponse.status, 422);
      assert.equal((await rejectedResponse.json()).code, "agent_metric_batch_write_failed");
    } finally {
      await database.close();
    }
  }
);

test(
  "agent metric reads resolve catalog keys and aliases for imported Metrics",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-metric-catalog-${randomUUID()}`;
    const app = createAgentMetricApp({
      userId,
      agentMetricStore: createDrizzleAgentMetricStore(database.db)
    });
    const metricId = stableScopedId("metric", userId, "hrv");
    const readingId = randomUUID();
    const receivedAt = new Date("2026-06-24T05:00:00.000Z");

    try {
      await seedUser(database, userId);
      await database.db.insert(schema.metrics).values({
        id: metricId,
        userId,
        deviceId: "integration:garmin",
        name: "Heart Rate Variability",
        unit: "millisecond",
        valueShape: "scalar",
        metricGroup: "monitoring",
        goalType: null,
        goalTargetValue: null,
        enabled: true,
        pinned: false,
        sortOrder: 130,
        updatedAt: receivedAt,
        deletedAt: null,
        receivedAt
      });
      await database.db.insert(schema.metricReadings).values({
        id: readingId,
        userId,
        deviceId: "integration:garmin",
        metricId,
        externalActivityId: null,
        valueJson: {
          value: 44,
          unit: "millisecond",
          entered: "44"
        },
        scalarValue: 44,
        scalarEntered: "44",
        atTime: receivedAt,
        windowStartedAt: null,
        windowEndedAt: null,
        provenance: "integration",
        source: "garmin",
        externalId: "daily-2026-06-24:last-night-hrv",
        comment: null,
        updatedAt: receivedAt,
        deletedAt: null,
        receivedAt
      });

      const byAliasResponse = await getAgent(
        app,
        "/agent/metrics?metricKey=lastNightHrv&fields=id,name,canonicalKey,aliases,dataClass"
      );
      assert.equal(byAliasResponse.status, 200);
      const byAliasBody = await byAliasResponse.json();
      assert.equal(byAliasBody.metrics.length, 1);
      assert.equal(byAliasBody.metrics[0].id, metricId);
      assert.equal(byAliasBody.metrics[0].canonicalKey, "hrv");
      assert.equal(byAliasBody.metrics[0].dataClass, "heartRate");
      assert.ok(byAliasBody.metrics[0].aliases.includes("lastNightAverageHrv"));

      const bySearchResponse = await getAgent(
        app,
        "/agent/metrics?search=hrv&fields=id,name,canonicalKey"
      );
      assert.equal(bySearchResponse.status, 200);
      const bySearchBody = await bySearchResponse.json();
      assert.equal(bySearchBody.metrics.length, 1);
      assert.equal(bySearchBody.metrics[0].canonicalKey, "hrv");

      const readingsResponse = await getAgent(
        app,
        "/agent/metrics/readings?metricKey=lastNightAverageHrv&fields=id,metricId,scalarValue"
      );
      assert.equal(readingsResponse.status, 200);
      const readingsBody = await readingsResponse.json();
      assert.deepEqual(readingsBody.fields, ["id", "metricId", "scalarValue"]);
      assert.equal(readingsBody.readings.length, 1);
      assert.equal(readingsBody.readings[0].id, readingId);
      assert.equal(readingsBody.readings[0].metricId, metricId);
      assert.equal(readingsBody.readings[0].scalarValue, 44);
    } finally {
      await database.close();
    }
  }
);

function createAgentMetricApp({
  agentMetricStore,
  syncNudgePublisher,
  userId = "user-1"
}) {
  return createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore(userId),
    agentMetricStore,
    syncNudgePublisher
  });
}

function createAgentKeyStore(userId, keyId = "agent-key-1") {
  return {
    async authenticateAgentApiKey(secret) {
      if (secret !== "prn_agent_secret") {
        return null;
      }

      return {
        userId,
        keyId,
        keyName: "Metric agent"
      };
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

function getAgent(app, path) {
  return app.request(path, {
    headers: {
      authorization: "Bearer prn_agent_secret"
    }
  });
}

function postAgentMetrics(app, body, headers = {}) {
  return app.request("/agent/metrics/batch-write", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_agent_secret",
      "content-type": "application/json",
      ...headers
    },
    body: JSON.stringify(body)
  });
}

function metricBatchRequest({
  idempotencyKey,
  metrics = [
    {
      id: "metric-body-weight",
      name: "Body Weight",
      unit: "kilogram",
      valueShape: "scalar",
      metricGroup: "body",
      goalType: null,
      goalTargetValue: null,
      enabled: true,
      pinned: true,
      sortOrder: 0,
      updatedAt: "2026-06-24T05:00:00.000Z",
      deletedAt: null
    }
  ],
  readings = [
    {
      id: "reading-body-weight",
      metricId: "metric-body-weight",
      value: { shape: "scalar", entered: "200", unit: "pound" },
      timeAnchor: { atTime: "2026-06-24T05:00:00.000Z" },
      provenance: "agent",
      source: "agent",
      externalId: null,
      externalActivityId: null,
      comment: null,
      updatedAt: "2026-06-24T05:00:00.000Z",
      deletedAt: null
    }
  ]
}) {
  return {
    idempotencyKey,
    metrics,
    readings
  };
}

async function seedUser(database, userId) {
  await database.db.insert(schema.user).values({
    id: userId,
    name: "Agent Metric User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
}

function stableScopedId(prefix, ...parts) {
  return `${prefix}:${hashParts(parts)}`;
}

function hashParts(parts) {
  const hash = createHash("sha256");
  for (const part of parts) {
    hash.update(part);
    hash.update("\0");
  }

  return hash.digest("hex").slice(0, 32);
}
