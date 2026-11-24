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

test(
  "agent metric readings carry the Trend over the Metric's whole live history when includeTrend is true",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-metric-trend-${randomUUID()}`;
    const otherUserId = `agent-metric-trend-other-${randomUUID()}`;
    const app = createAgentMetricApp({
      userId,
      agentMetricStore: createDrizzleAgentMetricStore(database.db)
    });
    const metricId = `metric-trend-${randomUUID()}`;
    const ids = {
      first: `reading-first-${randomUUID()}`,
      archived: `reading-archived-${randomUUID()}`,
      windowed: `reading-windowed-${randomUUID()}`,
      otherUser: `reading-other-user-${randomUUID()}`,
      valueJsonOnly: `reading-value-json-${randomUUID()}`,
      structured: `reading-structured-${randomUUID()}`
    };
    // One Reading a day, so each moves the Trend 10% of the way towards it:
    // 80, then 80 + 0.1 * (81 - 80) = 80.1, then 80.1 + 0.1 * (82 - 80.1) = 80.29.
    // The archived Reading and the other account's Reading would change the
    // last two if they took part.
    const expectedTrend = {
      [ids.first]: 80,
      [ids.windowed]: 80.1,
      [ids.valueJsonOnly]: 80.29
    };

    try {
      await seedUser(database, userId);
      await seedUser(database, otherUserId);
      await insertBodyWeightMetric(database, { id: metricId, userId });
      await insertReading(database, {
        id: ids.first,
        userId,
        metricId,
        scalarValue: 80,
        atTime: new Date("2026-06-01T06:00:00.000Z")
      });
      await insertReading(database, {
        id: ids.archived,
        userId,
        metricId,
        scalarValue: 100,
        atTime: new Date("2026-06-01T18:00:00.000Z"),
        deletedAt: new Date("2026-06-02T00:00:00.000Z")
      });
      await insertReading(database, {
        id: ids.windowed,
        userId,
        metricId,
        scalarValue: 81,
        atTime: null,
        windowStartedAt: new Date("2026-06-02T06:00:00.000Z")
      });
      await insertReading(database, {
        id: ids.otherUser,
        userId: otherUserId,
        metricId,
        scalarValue: 1000,
        atTime: new Date("2026-06-02T18:00:00.000Z")
      });
      await insertReading(database, {
        id: ids.valueJsonOnly,
        userId,
        metricId,
        scalarValue: null,
        valueJson: { value: 82, unit: "kilogram" },
        atTime: new Date("2026-06-03T06:00:00.000Z")
      });
      await insertReading(database, {
        id: ids.structured,
        userId,
        metricId,
        scalarValue: null,
        valueJson: { shape: "structured", unit: "kilogram", fields: { left: 1 } },
        atTime: new Date("2026-06-04T06:00:00.000Z")
      });

      const readingsPath = (query) =>
        `/agent/metrics/readings?metricId=${metricId}&${query}`;

      const pageResponse = await getAgent(
        app,
        readingsPath("from=2026-06-03T00:00:00.000Z&includeTrend=true")
      );
      assert.equal(pageResponse.status, 200);
      const pageBody = await pageResponse.json();
      assert.deepEqual(
        pageBody.readings.map((reading) => reading.id),
        [ids.valueJsonOnly, ids.structured]
      );
      assertTrend(pageBody.readings[0], expectedTrend[ids.valueJsonOnly]);
      assert.equal("trendValue" in pageBody.readings[1], false);

      const projectedResponse = await getAgent(
        app,
        readingsPath("from=2026-06-03T00:00:00.000Z&includeTrend=true&fields=id,metricId")
      );
      assert.equal(projectedResponse.status, 200);
      const projectedBody = await projectedResponse.json();
      assert.deepEqual(projectedBody.fields, ["id", "metricId"]);
      assert.deepEqual(Object.keys(projectedBody.readings[0]).sort(), [
        "id",
        "metricId",
        "trendValue"
      ]);
      assertTrend(projectedBody.readings[0], expectedTrend[ids.valueJsonOnly]);

      for (const query of ["includeTrend=false", "includeArchived=true"]) {
        const withoutTrendResponse = await getAgent(app, readingsPath(query));
        assert.equal(withoutTrendResponse.status, 200);
        const withoutTrendBody = await withoutTrendResponse.json();
        assert.ok(withoutTrendBody.readings.length > 0);
        assert.ok(
          withoutTrendBody.readings.every((reading) => !("trendValue" in reading)),
          query
        );
      }

      const archivedResponse = await getAgent(
        app,
        readingsPath("includeArchived=true&includeTrend=true")
      );
      assert.equal(archivedResponse.status, 200);
      const archivedBody = await archivedResponse.json();
      const byId = new Map(archivedBody.readings.map((reading) => [reading.id, reading]));
      assert.deepEqual(
        [...byId.keys()].sort(),
        [ids.first, ids.archived, ids.windowed, ids.valueJsonOnly, ids.structured].sort()
      );
      assert.equal("trendValue" in byId.get(ids.archived), false);
      assert.equal("trendValue" in byId.get(ids.structured), false);
      for (const [id, trend] of Object.entries(expectedTrend)) {
        assertTrend(byId.get(id), trend);
      }

      // Paged one Reading at a time, each page still carries the Trend over
      // the whole history, not over the page's slice.
      const pagedTrends = new Map();
      let cursor = null;
      do {
        const pagedResponse = await getAgent(
          app,
          readingsPath(`limit=1&includeTrend=true${cursor ? `&cursor=${cursor}` : ""}`)
        );
        assert.equal(pagedResponse.status, 200);
        const pagedBody = await pagedResponse.json();
        assert.equal(pagedBody.readings.length, 1);
        pagedTrends.set(pagedBody.readings[0].id, pagedBody.readings[0]);
        cursor = pagedBody.nextCursor;
      } while (cursor !== null);
      // The list's own order is not the Trend's (D5), so only the set is
      // checked here.
      assert.deepEqual(
        [...pagedTrends.keys()].sort(),
        [ids.first, ids.windowed, ids.valueJsonOnly, ids.structured].sort()
      );
      for (const [id, trend] of Object.entries(expectedTrend)) {
        assertTrend(pagedTrends.get(id), trend);
      }
      assert.equal("trendValue" in pagedTrends.get(ids.structured), false);

      // The app stores Reading times as whole seconds, so two Readings in one
      // second are ordered by id, not by millisecond: "a" (82) comes first and
      // seeds the Trend, and "b" (80), at the same instant, does not move it.
      const sameSecondMetricId = `metric-trend-same-second-${randomUUID()}`;
      const sameSecond = {
        a: `reading-same-second-a-${randomUUID()}`,
        b: `reading-same-second-b-${randomUUID()}`
      };
      await insertBodyWeightMetric(database, { id: sameSecondMetricId, userId });
      await insertReading(database, {
        id: sameSecond.a,
        userId,
        metricId: sameSecondMetricId,
        scalarValue: 82,
        atTime: new Date("2026-06-01T07:00:00.900Z")
      });
      await insertReading(database, {
        id: sameSecond.b,
        userId,
        metricId: sameSecondMetricId,
        scalarValue: 80,
        atTime: new Date("2026-06-01T07:00:00.100Z")
      });
      const sameSecondResponse = await getAgent(
        app,
        `/agent/metrics/readings?metricId=${sameSecondMetricId}&includeTrend=true`
      );
      assert.equal(sameSecondResponse.status, 200);
      const sameSecondBody = await sameSecondResponse.json();
      const sameSecondById = new Map(
        sameSecondBody.readings.map((reading) => [reading.id, reading])
      );
      assertTrend(sameSecondById.get(sameSecond.a), 82);
      assertTrend(sameSecondById.get(sameSecond.b), 82);

      const invalidResponse = await getAgent(app, readingsPath("includeTrend=yes"));
      assert.equal(invalidResponse.status, 400);
    } finally {
      await database.close();
    }
  }
);

// Lab Results by Lab Test (docs/designs/lab-results.md, "Agent surface" and
// "Finding the Lab Metric for a Lab Test").

const databaseSkip = databaseUrl ? false : "DATABASE_URL is not set.";

test(
  "a lab write by Lab Test creates one Lab Metric, logs it, reports it and reuses it",
  { skip: databaseSkip },
  async () => {
    await withLabUser(async ({ database, userId, app }) => {
      await insertBodyWeightMetric(database, { id: `bw-${randomUUID()}`, userId });
      const labMetricId = stableScopedId("metric", userId, "lab:testosterone_total");
      const idempotencyKey = `lab-create-${randomUUID()}`;
      const reading = labReading();

      const response = await postAgentMetrics(app, labBatch(idempotencyKey, [reading]));
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.duplicate, false);
      assert.equal(body.metrics.length, 1);
      assert.deepEqual(body.metrics[0], {
        id: labMetricId,
        name: "Testosterone",
        valueShape: "scalar",
        unit: "nmol/L",
        metricGroup: "custom",
        applied: true,
        outcome: "applied"
      });
      assert.equal(body.readings[0].metricId, labMetricId);
      assert.equal(body.readings[0].outcome, "applied");

      const [metric] = await database.sql`select * from metrics where id = ${labMetricId}`;
      assert.equal(metric.user_id, userId);
      assert.equal(metric.lab_test_key, "testosterone_total");
      assert.equal(metric.name, "Testosterone");
      assert.equal(metric.unit, "nmol/L");
      assert.equal(metric.value_shape, "scalar");
      assert.equal(metric.metric_group, "custom");
      assert.equal(metric.enabled, true);
      assert.equal(metric.pinned, false);
      assert.equal(metric.goal_type, null);
      assert.equal(metric.goal_target_value, null);
      // One more than the Body Weight Metric's sort order 0.
      assert.equal(metric.sort_order, 1);
      assert.equal(metric.deleted_at, null);

      const [stored] = await database.sql`
        select * from metric_readings where id = ${reading.id}
      `;
      assert.equal(stored.metric_id, labMetricId);
      assert.equal(stored.scalar_value, 20.4);
      assert.equal(stored.scalar_entered, "20.4");
      assert.deepEqual(stored.value_json.lab, {
        collected: "2026-03-04T08:15",
        limit: null,
        printedRange: "10.0-30.0",
        printedFlag: null,
        reportStatus: "final",
        fasting: null,
        labName: "Example Pathology"
      });

      const activity = await database.sql`
        select entity_table, entity_id, after_image from activity_log
        where user_id = ${userId} and batch_id = ${idempotencyKey}
        order by entity_table
      `;
      assert.deepEqual(
        activity.map((row) => row.entity_table),
        ["agent_metric_batches", "metric_readings", "metrics"]
      );
      const metricEntry = activity.find((row) => row.entity_table === "metrics");
      assert.equal(metricEntry.entity_id, labMetricId);
      assert.equal(metricEntry.after_image.canonicalKey, "testosterone_total");
      assert.deepEqual(metricEntry.after_image.aliases, []);
      assert.equal(metricEntry.after_image.dataClass, null);

      const second = labReading({ collected: "2026-05-06" });
      const secondResponse = await postAgentMetrics(
        app,
        labBatch(`lab-reuse-${randomUUID()}`, [second])
      );
      assert.equal(secondResponse.status, 200);
      const secondBody = await secondResponse.json();
      assert.deepEqual(secondBody.metrics, []);
      assert.equal(secondBody.readings[0].metricId, labMetricId);
      const labMetrics = await database.sql`
        select id from metrics where user_id = ${userId} and lab_test_key = 'testosterone_total'
      `;
      assert.equal(labMetrics.length, 1);
      const [secondStored] = await database.sql`
        select at_time from metric_readings where id = ${second.id}
      `;
      // A date-only collection is anchored at noon local (+10:00).
      assert.equal(new Date(secondStored.at_time).toISOString(), "2026-05-06T02:00:00.000Z");
    });
  }
);

test(
  "a lab write unarchives the stable-id Lab Metric, and keys a live one that lost its key",
  { skip: databaseSkip },
  async () => {
    await withLabUser(async ({ database, userId, app }) => {
      const archivedId = stableScopedId("metric", userId, "lab:testosterone_total");
      const unkeyedId = stableScopedId("metric", userId, "lab:shbg");
      await insertLabMetricRow(database, {
        id: archivedId,
        userId,
        name: "Testosterone",
        labTestKey: "testosterone_total",
        deletedAt: new Date("2026-06-02T00:00:00.000Z")
      });
      await insertLabMetricRow(database, {
        id: unkeyedId,
        userId,
        name: "SHBG",
        labTestKey: null,
        deletedAt: null
      });

      const response = await postAgentMetrics(
        app,
        labBatch(`lab-restore-${randomUUID()}`, [
          labReading(),
          labReading({ labTestKey: "shbg", entered: "40" })
        ])
      );
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.deepEqual(
        body.metrics.map((metric) => [metric.id, metric.outcome]),
        [
          [archivedId, "applied"],
          [unkeyedId, "applied"]
        ]
      );
      assert.deepEqual(
        body.readings.map((reading) => reading.metricId),
        [archivedId, unkeyedId]
      );

      const rows = await database.sql`
        select id, lab_test_key, deleted_at from metrics
        where user_id = ${userId} order by name desc
      `;
      assert.deepEqual(
        rows.map((row) => [row.id, row.lab_test_key, row.deleted_at]),
        [
          [archivedId, "testosterone_total", null],
          [unkeyedId, "shbg", null]
        ]
      );
    });
  }
);

test(
  "a replayed lab write returns duplicate and writes nothing",
  { skip: databaseSkip },
  async () => {
    await withLabUser(async ({ database, userId, app }) => {
      const request = labBatch(`lab-replay-${randomUUID()}`, [labReading()]);
      const first = await postAgentMetrics(app, request);
      assert.equal(first.status, 200);
      const firstBody = await first.json();
      const counts = await labRowCounts(database, userId);

      const replay = await postAgentMetrics(app, request);
      assert.equal(replay.status, 200);
      const replayBody = await replay.json();
      assert.equal(replayBody.duplicate, true);
      assert.equal(replayBody.readings.length, 1);
      assert.equal(replayBody.readings[0].metricId, firstBody.readings[0].metricId);
      assert.equal(replayBody.readings[0].outcome, "duplicate");
      assert.deepEqual(replayBody.readings[0].warnings, []);
      assert.deepEqual(await labRowCounts(database, userId), counts);
    });
  }
);

test(
  "lab request and reading rules reject with their own codes",
  { skip: databaseSkip },
  async () => {
    await withLabUser(async ({ database, userId, app }) => {
      const bodyWeightId = `bw-${randomUUID()}`;
      await insertBodyWeightMetric(database, { id: bodyWeightId, userId });
      const stored = labReading();
      const seeded = await postAgentMetrics(
        app,
        labBatch(`lab-seed-${randomUUID()}`, [stored])
      );
      assert.equal(seeded.status, 200);
      const labMetricId = (await seeded.json()).readings[0].metricId;

      const expectRejected = async (request, rule, field) => {
        const response = await postAgentMetrics(app, request);
        assert.equal(response.status, 422, rule);
        const body = await response.json();
        assert.equal(body.code, "agent_metric_batch_write_failed");
        assert.equal(body.errors[0].rule, rule);
        if (field !== undefined) {
          assert.equal(body.errors[0].field, field, rule);
        }
        return body.errors[0];
      };
      const batch = (readings, metrics = []) =>
        labBatch(`lab-reject-${randomUUID()}`, readings, metrics);
      const customMetric = {
        id: `custom-${randomUUID()}`,
        name: "Morning energy",
        unit: "score",
        valueShape: "scalar",
        metricGroup: "custom"
      };
      const { labTestKey: _key, ...withoutKey } = labReading();

      await expectRejected(
        batch([{ ...labReading(), metricId: labMetricId }]),
        "lab_target_ambiguous",
        "readings[0]"
      );
      await expectRejected(batch([withoutKey]), "lab_target_ambiguous", "readings[0]");
      const unknown = await expectRejected(
        batch([labReading({ labTestKey: "not_a_lab_test" })]),
        "lab_test_unknown",
        "readings[0].labTestKey"
      );
      assert.match(unknown.message, /agent_list_lab_tests/);
      await expectRejected(
        batch([
          {
            id: randomUUID(),
            metricId: labMetricId,
            value: { shape: "scalar", entered: "20.4", unit: "nmol/L" },
            timeAnchor: { atTime: "2026-03-04T08:15:00.000Z" }
          }
        ]),
        "lab_metric_id_not_allowed",
        "readings[0].metricId"
      );
      await expectRejected(
        batch([], [{ ...customMetric, id: labMetricId, name: "Testosterone" }]),
        "lab_metric_upsert_not_allowed",
        "metrics[0]"
      );
      await expectRejected(
        batch([], [{ ...customMetric, labTestKey: "testosterone_total" }]),
        "lab_metric_upsert_not_allowed",
        "metrics[0]"
      );
      await expectRejected(
        batch([
          {
            id: randomUUID(),
            metricId: bodyWeightId,
            value: {
              shape: "scalar",
              entered: "80",
              unit: "kilogram",
              lab: { collected: "2026-03-04" }
            },
            timeAnchor: { atTime: "2026-03-04T08:15:00.000Z" }
          }
        ]),
        "lab_fields_on_non_lab_metric",
        "readings[0].value.lab"
      );
      await expectRejected(
        batch([labReading({ id: stored.id, collected: "2026-07-08" })]),
        "lab_result_exists",
        "readings[0].id"
      );
      await expectRejected(
        batch([labReading({ deletedAt: "2026-07-08T00:00:00.000Z" })]),
        "lab_archive_not_allowed",
        "readings[0].deletedAt"
      );
      const unit = await expectRejected(
        batch([labReading({ unit: "ng/dL" })]),
        "lab_unit_not_accepted",
        "readings[0].value.unit"
      );
      assert.equal(unit.message, "Unit not accepted. Use nmol/L, nmol/l.");
      await expectRejected(
        batch([labReading({ lab: { collected: 20260304 } })]),
        "lab_collected_invalid",
        "readings[0].value.lab.collected"
      );
      await expectRejected(
        batch([labReading({ lab: { reportStatus: "draft" } })]),
        "lab_report_status_invalid",
        "readings[0].value.lab.reportStatus"
      );

      const accepted = labReading({ unit: "nmol/l", collected: "2026-07-09" });
      const acceptedResponse = await postAgentMetrics(app, batch([accepted]));
      assert.equal(acceptedResponse.status, 200);
      const [acceptedRow] = await database.sql`
        select value_json from metric_readings where id = ${accepted.id}
      `;
      assert.equal(acceptedRow.value_json.unit, "nmol/L");
      assert.equal(acceptedRow.value_json.enteredUnit, "nmol/l");
    });
  }
);

test(
  "lab_result_replaces warns about a changed value for a saved collection, and the batch applies",
  { skip: databaseSkip },
  async () => {
    await withLabUser(async ({ database, userId, app }) => {
      const interim = labReading({ lab: { reportStatus: "interim" } });
      assert.equal(
        (await postAgentMetrics(app, labBatch(`lab-interim-${randomUUID()}`, [interim]))).status,
        200
      );

      const same = labReading();
      const sameBody = await (
        await postAgentMetrics(app, labBatch(`lab-same-${randomUUID()}`, [same]))
      ).json();
      assert.deepEqual(sameBody.readings[0].warnings, []);

      const revised = labReading({ entered: "21.0" });
      const revisedResponse = await postAgentMetrics(
        app,
        labBatch(`lab-revised-${randomUUID()}`, [revised])
      );
      assert.equal(revisedResponse.status, 200);
      const revisedBody = await revisedResponse.json();
      assert.deepEqual(revisedBody.readings[0].warnings, ["lab_result_replaces"]);
      assert.equal(revisedBody.readings[0].outcome, "applied");

      const limit = labReading({ entered: "< 1" });
      const limitBody = await (
        await postAgentMetrics(app, labBatch(`lab-limit-${randomUUID()}`, [limit]))
      ).json();
      assert.deepEqual(limitBody.readings[0].warnings, ["lab_result_replaces"]);

      const rows = await database.sql`
        select id from metric_readings where user_id = ${userId} and deleted_at is null
      `;
      assert.equal(rows.length, 4);
    });
  }
);

test(
  "one rejected lab reading rejects the whole batch",
  { skip: databaseSkip },
  async () => {
    await withLabUser(async ({ database, userId, app }) => {
      const response = await postAgentMetrics(
        app,
        labBatch(`lab-all-or-nothing-${randomUUID()}`, [
          labReading(),
          labReading({ labTestKey: "shbg", unit: "ng/dL" })
        ])
      );
      assert.equal(response.status, 422);
      const body = await response.json();
      assert.deepEqual(
        body.errors.map((error) => [error.rule, error.itemIndex]),
        [["lab_unit_not_accepted", 1]]
      );
      assert.deepEqual(await labRowCounts(database, userId), {
        metrics: 0,
        readings: 0,
        activity: 0
      });
    });
  }
);

test(
  "the server sets a lab result's updatedAt, provenance, source and lab.limit",
  { skip: databaseSkip },
  async () => {
    await withLabUser(async ({ database, app }) => {
      const before = Date.now();
      const limit = labReading({
        entered: "< 1",
        lab: { limit: { comparator: ">", bound: 99 } },
        provenance: "manual",
        source: "labEntry",
        updatedAt: "2020-01-01T00:00:00.000Z"
      });
      const number = labReading({
        labTestKey: "shbg",
        entered: "40",
        lab: { limit: { comparator: "<", bound: 5 } }
      });
      const response = await postAgentMetrics(
        app,
        labBatch(`lab-server-set-${randomUUID()}`, [limit, number])
      );
      assert.equal(response.status, 200);

      const [limitRow] = await database.sql`
        select * from metric_readings where id = ${limit.id}
      `;
      assert.equal(limitRow.provenance, "agent");
      assert.equal(limitRow.source, "agent");
      assert.ok(new Date(limitRow.updated_at).getTime() >= before - 1000);
      assert.equal(limitRow.scalar_value, null);
      assert.equal(limitRow.scalar_entered, "< 1");
      assert.equal(limitRow.value_json.value, null);
      assert.deepEqual(limitRow.value_json.lab.limit, { comparator: "<", bound: 1 });

      const [numberRow] = await database.sql`
        select * from metric_readings where id = ${number.id}
      `;
      assert.equal(numberRow.value_json.lab.limit, null);
      assert.equal(numberRow.scalar_value, 40);
    });
  }
);

test(
  "two concurrent first lab writes for one Lab Test create one Lab Metric",
  { skip: databaseSkip },
  async () => {
    await applyMigrations(databaseUrl);
    const first = createDatabaseClient(databaseUrl);
    const second = createDatabaseClient(databaseUrl);
    const userId = `agent-lab-${randomUUID()}`;
    const appFor = (database) =>
      createAgentMetricApp({
        userId,
        agentMetricStore: createDrizzleAgentMetricStore(database.db)
      });

    try {
      await seedUser(first, userId);
      const responses = await Promise.all([
        postAgentMetrics(appFor(first), labBatch(`lab-race-a-${randomUUID()}`, [labReading()])),
        postAgentMetrics(
          appFor(second),
          labBatch(`lab-race-b-${randomUUID()}`, [labReading({ collected: "2026-05-06" })])
        )
      ]);
      assert.deepEqual(
        responses.map((response) => response.status),
        [200, 200]
      );
      const bodies = await Promise.all(responses.map((response) => response.json()));
      assert.equal(bodies[0].readings[0].metricId, bodies[1].readings[0].metricId);
      assert.equal(bodies[0].metrics.length + bodies[1].metrics.length, 1);
      const metrics = await first.sql`
        select id from metrics where user_id = ${userId}
      `;
      assert.equal(metrics.length, 1);
    } finally {
      await first.close();
      await second.close();
    }
  }
);

// Lab Results read by key (docs/designs/lab-results.md, "Agent surface",
// "Result identity and the collapse" and "The display", No Trend).

test(
  "lab readings join two Lab Metrics by key, collapse, page over the collapsed list and drop archived rows",
  { skip: databaseSkip },
  async () => {
    await withLabUser(async ({ database, userId, app }) => {
      const fixture = await seedTwoLabMetrics(database, { userId, app });
      const { ids, metricA, metricB } = fixture;

      for (const query of [
        "metricKey=testosterone_total",
        `metricId=${encodeURIComponent(metricA)}`,
        `metricId=${encodeURIComponent(metricB)}`,
        `metricId=${encodeURIComponent(metricB)}&metricKey=testosterone_total`
      ]) {
        const response = await getAgent(
          app,
          `/agent/metrics/readings?${query}&includeArchived=true&includeTrend=true`
        );
        assert.equal(response.status, 200, query);
        const body = await response.json();
        // The interim is hidden by its final on the other Lab Metric, and
        // the archived row never comes back, whatever includeArchived says.
        assert.deepEqual(
          body.readings.map((reading) => [reading.id, reading.metricId]),
          [
            [ids.final, metricB],
            [ids.april, metricB]
          ],
          query
        );
        assert.equal(body.totalMatched, 2, query);
        assert.equal(body.nextCursor, null, query);
        for (const reading of body.readings) {
          assert.equal("trendValue" in reading, false, query);
        }
        assert.equal(body.readings[0].valueJson.lab.reportStatus, "final");
      }

      // limit=1 walks the collapsed list through the cursor.
      const firstPage = await (
        await getAgent(app, "/agent/metrics/readings?metricKey=testosterone_total&limit=1")
      ).json();
      assert.deepEqual(
        firstPage.readings.map((reading) => reading.id),
        [ids.final]
      );
      assert.equal(firstPage.totalMatched, 2);
      assert.equal(firstPage.nextCursor, ids.final);
      const secondPage = await (
        await getAgent(
          app,
          `/agent/metrics/readings?metricKey=testosterone_total&limit=1&cursor=${encodeURIComponent(firstPage.nextCursor)}`
        )
      ).json();
      assert.deepEqual(
        secondPage.readings.map((reading) => reading.id),
        [ids.april]
      );
      assert.equal(secondPage.totalMatched, 2);
      assert.equal(secondPage.nextCursor, null);

      // The date filter applies after the collapse: the final is outside it,
      // and its interim inside it stays hidden.
      const windowed = await (
        await getAgent(
          app,
          "/agent/metrics/readings?metricKey=testosterone_total&from=2026-03-01T00:00:00.000Z&to=2026-03-31T00:00:00.000Z"
        )
      ).json();
      assert.deepEqual(windowed.readings, []);
      assert.equal(windowed.totalMatched, 0);

      // metricId and metricKey naming different keys answer nothing.
      const conflicting = await (
        await getAgent(
          app,
          `/agent/metrics/readings?metricId=${encodeURIComponent(metricA)}&metricKey=shbg`
        )
      ).json();
      assert.deepEqual(conflicting.readings, []);
      assert.equal(conflicting.totalMatched, 0);
    });
  }
);

test(
  "includeTrend adds no trendValue to lab readings while a body-weight reading still gets one",
  { skip: databaseSkip },
  async () => {
    await withLabUser(async ({ database, userId, app }) => {
      const { ids } = await seedTwoLabMetrics(database, { userId, app });
      const bodyWeightId = `bw-${randomUUID()}`;
      const weightReadingId = `bw-reading-${randomUUID()}`;
      await insertBodyWeightMetric(database, { id: bodyWeightId, userId });
      await insertReading(database, {
        id: weightReadingId,
        userId,
        metricId: bodyWeightId,
        scalarValue: 80,
        atTime: new Date("2026-03-05T00:00:00.000Z")
      });

      const response = await getAgent(app, "/agent/metrics/readings?includeTrend=true");
      assert.equal(response.status, 200);
      const body = await response.json();
      const byId = new Map(body.readings.map((reading) => [reading.id, reading]));
      assertTrend(byId.get(weightReadingId), 80);
      // An unfiltered read is not collapsed, but no lab reading has a Trend.
      for (const id of [ids.interim, ids.final, ids.april]) {
        assert.ok(byId.has(id), id);
        assert.equal("trendValue" in byId.get(id), false, id);
      }
    });
  }
);

test(
  "a catalogue metricKey finds Lab Metrics only, never a custom Metric with the Lab Test's name",
  { skip: databaseSkip },
  async () => {
    await withLabUser(async ({ database, userId, app }) => {
      const { ids, metricA, metricB } = await seedTwoLabMetrics(database, { userId, app });
      const customIds = [];
      for (const name of ["Testosterone", "Testosterone Total"]) {
        const customId = `custom-${randomUUID()}`;
        customIds.push(customId);
        await insertLabMetricRow(database, { id: customId, userId, name, labTestKey: null, deletedAt: null });
        await insertReading(database, {
          id: `custom-reading-${randomUUID()}`,
          userId,
          metricId: customId,
          scalarValue: 999,
          valueJson: { value: 999, unit: "nmol/L" },
          atTime: new Date("2026-03-04T00:00:00.000Z")
        });
      }

      const readings = await (
        await getAgent(app, "/agent/metrics/readings?metricKey=testosterone_total")
      ).json();
      assert.deepEqual(
        readings.readings.map((reading) => reading.id),
        [ids.final, ids.april]
      );

      const metrics = await (
        await getAgent(app, "/agent/metrics?metricKey=testosterone_total")
      ).json();
      assert.deepEqual(
        metrics.metrics.map((metric) => metric.id).sort(),
        [metricA, metricB].sort()
      );
      for (const metric of metrics.metrics) {
        assert.equal(metric.canonicalKey, "testosterone_total");
      }

      // A custom Metric's own name still finds it, and not the Lab Metrics.
      const byName = await (await getAgent(app, "/agent/metrics?metricKey=Testosterone")).json();
      assert.deepEqual(
        byName.metrics.map((metric) => metric.id),
        [customIds[0]]
      );
    });
  }
);

/**
 * Two Lab Metrics for Testosterone: [metricA] created by an Agent write of an
 * interim result, and [metricB] inserted directly, as an offline device's
 * push would, holding the final of the same collection, a later result and an
 * archived one.
 */
async function seedTwoLabMetrics(database, { userId, app }) {
  const ids = {
    interim: randomUUID(),
    final: `final-${randomUUID()}`,
    april: `april-${randomUUID()}`,
    archived: `archived-${randomUUID()}`
  };
  const metricA = stableScopedId("metric", userId, "lab:testosterone_total");
  const metricB = `device-lab-metric-${randomUUID()}`;
  const response = await postAgentMetrics(
    app,
    labBatch(`lab-read-${randomUUID()}`, [
      labReading({ id: ids.interim, lab: { reportStatus: "interim" } })
    ])
  );
  assert.equal(response.status, 200);
  await insertLabMetricRow(database, {
    id: metricB,
    userId,
    name: "Testosterone",
    labTestKey: "testosterone_total",
    deletedAt: null
  });
  const labValue = (value, collected, reportStatus = "final") => ({
    value,
    unit: "nmol/L",
    lab: {
      collected,
      limit: null,
      printedRange: null,
      printedFlag: null,
      reportStatus,
      fasting: null,
      labName: null
    }
  });
  // The same collection as the interim, anchored outside March (entered
  // later at another offset, say), so a March date filter holds only the
  // interim, which the final still hides.
  await insertReading(database, {
    id: ids.final,
    userId,
    metricId: metricB,
    scalarValue: 21,
    valueJson: labValue(21, "2026-03-04T08:15"),
    atTime: new Date("2026-04-02T00:00:00.000Z")
  });
  await insertReading(database, {
    id: ids.april,
    userId,
    metricId: metricB,
    scalarValue: 18,
    valueJson: labValue(18, "2026-04-10"),
    atTime: new Date("2026-04-10T02:00:00.000Z")
  });
  await insertReading(database, {
    id: ids.archived,
    userId,
    metricId: metricA,
    scalarValue: 19,
    valueJson: labValue(19, "2026-05-01"),
    atTime: new Date("2026-05-01T02:00:00.000Z"),
    deletedAt: new Date("2026-06-05T00:00:00.000Z")
  });
  return { ids, metricA, metricB };
}

async function withLabUser(run) {
  await applyMigrations(databaseUrl);
  const database = createDatabaseClient(databaseUrl);
  const userId = `agent-lab-${randomUUID()}`;
  const app = createAgentMetricApp({
    userId,
    agentMetricStore: createDrizzleAgentMetricStore(database.db)
  });
  try {
    await seedUser(database, userId);
    await run({ database, userId, app });
  } finally {
    await database.close();
  }
}

/**
 * One lab reading by Lab Test, `lab.collected` anchored as the spec expands
 * it: a date at T12:00:00, a time with :00 seconds, here at +10:00.
 */
function labReading({
  id = randomUUID(),
  labTestKey = "testosterone_total",
  entered = "20.4",
  unit = "nmol/L",
  collected = "2026-03-04T08:15",
  lab = {},
  ...rest
} = {}) {
  return {
    id,
    labTestKey,
    value: {
      shape: "scalar",
      entered,
      unit,
      lab: {
        collected,
        printedRange: " 10.0-30.0 ",
        reportStatus: "final",
        labName: "Example Pathology",
        ...lab
      }
    },
    timeAnchor: {
      localDateTime: collected.length === 10 ? `${collected}T12:00:00` : `${collected}:00`,
      timezoneOffsetMinutes: 600
    },
    ...rest
  };
}

function labBatch(idempotencyKey, readings, metrics = []) {
  return { idempotencyKey, metrics, readings };
}

async function insertLabMetricRow(database, { id, userId, name, labTestKey, deletedAt }) {
  const updatedAt = new Date("2026-06-01T00:00:00.000Z");
  await database.db.insert(schema.metrics).values({
    id,
    userId,
    deviceId: "device-lab",
    name,
    unit: "nmol/L",
    valueShape: "scalar",
    metricGroup: "custom",
    goalType: null,
    goalTargetValue: null,
    enabled: true,
    pinned: false,
    sortOrder: 0,
    labTestKey,
    updatedAt,
    deletedAt,
    receivedAt: updatedAt
  });
}

async function labRowCounts(database, userId) {
  const [metrics] = await database.sql`
    select count(*)::int as count from metrics where user_id = ${userId}
  `;
  const [readings] = await database.sql`
    select count(*)::int as count from metric_readings where user_id = ${userId}
  `;
  const [activity] = await database.sql`
    select count(*)::int as count from activity_log where user_id = ${userId}
  `;
  return {
    metrics: metrics.count,
    readings: readings.count,
    activity: activity.count
  };
}

function assertTrend(reading, expected) {
  assert.equal(typeof reading.trendValue, "number", reading.id);
  assert.ok(
    Math.abs(reading.trendValue - expected) < 1e-9,
    `${reading.id}: ${reading.trendValue} is not ${expected}`
  );
}

async function insertBodyWeightMetric(database, { id, userId }) {
  const updatedAt = new Date("2026-06-01T00:00:00.000Z");
  await database.db.insert(schema.metrics).values({
    id,
    userId,
    deviceId: "device-trend",
    name: "Body Weight",
    unit: "kilogram",
    valueShape: "scalar",
    metricGroup: "body",
    goalType: null,
    goalTargetValue: null,
    enabled: true,
    pinned: true,
    sortOrder: 0,
    updatedAt,
    deletedAt: null,
    receivedAt: updatedAt
  });
}

async function insertReading(
  database,
  {
    id,
    userId,
    metricId,
    scalarValue,
    valueJson = { value: scalarValue, unit: "kilogram" },
    atTime,
    windowStartedAt = null,
    deletedAt = null,
    updatedAt = new Date("2026-06-05T00:00:00.000Z")
  }
) {
  await database.db.insert(schema.metricReadings).values({
    id,
    userId,
    deviceId: "device-trend",
    metricId,
    externalActivityId: null,
    valueJson,
    scalarValue,
    scalarEntered: scalarValue === null ? null : String(scalarValue),
    atTime,
    windowStartedAt,
    windowEndedAt: null,
    provenance: "manual",
    source: "perennia",
    externalId: null,
    comment: null,
    updatedAt,
    deletedAt,
    receivedAt: updatedAt
  });
}

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
