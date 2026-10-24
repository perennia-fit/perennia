import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { createMigratedServerApp, schema } from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

const skip = databaseUrl ? false : "DATABASE_URL is not set.";

test(
  "a pushed default that folds is reported as merged, and an archive through its alias leaves the survivor live",
  { skip },
  async () => {
    const server = await createServer();
    try {
      const user = await createSignedInUser(server);
      const survivorId = randomUUID();
      const copyId = randomUUID();
      await push(server, user, "device-a", "metrics", [
        metricChange({ id: survivorId, at: "2026-07-01T08:00:00.000Z" })
      ]);

      const fold = await push(server, user, "device-b", "metrics", [
        metricChange({
          id: copyId,
          at: "2026-07-01T09:00:00.000Z",
          goalTargetValue: 75,
          activityLogId: randomUUID()
        })
      ]);
      assert.deepEqual(fold.accepted, [copyId]);
      assert.deepEqual(fold.merged, [{ id: copyId, intoId: survivorId }]);

      const metrics = await metricRows(server, user);
      assert.deepEqual(
        metrics.map((row) => [row.id, row.goal_target_value, row.deleted_at]),
        [[survivorId, 75, null]],
        "the copy's newer goal landed on the survivor; no row for the copy"
      );
      const [activity] = await server.database.sql`
        select entity_id, after_image from activity_log
        where user_id = ${user.userId} and entity_table = 'metrics'
      `;
      assert.equal(activity.entity_id, survivorId);
      assert.equal(activity.after_image.id, survivorId);

      const archive = await push(server, user, "device-b", "metrics", [
        metricChange({
          id: copyId,
          at: "2026-07-01T10:00:00.000Z",
          deletedAt: "2026-07-01T10:00:00.000Z"
        })
      ]);
      assert.deepEqual(archive.accepted, [copyId]);
      assert.deepEqual(archive.applied, []);
      assert.equal((await metricRows(server, user))[0].deleted_at, null);
    } finally {
      await server.database.close();
    }
  }
);

test(
  "only defaults fold: a hand-made measurement and a different unit stay their own rows",
  { skip },
  async () => {
    const server = await createServer();
    try {
      const user = await createSignedInUser(server);
      const ids = [randomUUID(), randomUUID(), randomUUID(), randomUUID()];
      await push(server, user, "device-a", "metrics", [
        metricChange({ id: ids[0], name: "Waist", unit: "centimeter" }),
        metricChange({ id: ids[1] })
      ]);
      const response = await push(server, user, "device-b", "metrics", [
        metricChange({ id: ids[2], name: "Waist", unit: "centimeter" }),
        metricChange({ id: ids[3], unit: "pound" })
      ]);

      assert.deepEqual(response.merged, []);
      assert.deepEqual(
        (await metricRows(server, user)).map((row) => row.id).sort(),
        [...ids].sort()
      );
    } finally {
      await server.database.close();
    }
  }
);

test(
  "a reading waits for its Metric, follows an alias, and keeps an integration reading's values",
  { skip },
  async () => {
    const server = await createServer();
    try {
      const user = await createSignedInUser(server);
      const survivorId = randomUUID();
      const copyId = randomUUID();
      const early = readingChange({ metricId: copyId, value: 80 });

      const beforeMetric = await push(server, user, "device-b", "metric_readings", [
        early
      ]);
      assert.deepEqual(
        beforeMetric.accepted,
        [],
        "a reading whose Metric the server lacks stays pending on the device"
      );

      await push(server, user, "device-a", "metrics", [
        metricChange({ id: survivorId })
      ]);
      await push(server, user, "device-b", "metrics", [
        metricChange({ id: copyId, at: "2026-07-01T08:00:01.000Z" })
      ]);
      const afterMetric = await push(server, user, "device-b", "metric_readings", [
        { ...early, ...activityEnvelope(early) }
      ]);
      assert.deepEqual(afterMetric.accepted, [early.id]);
      const [stored] = await readingRows(server, user);
      assert.equal(stored.metric_id, survivorId);
      assert.deepEqual(stored.value_json, { value: 80 });
      const [activity] = await server.database.sql`
        select after_image from activity_log
        where user_id = ${user.userId} and entity_table = 'metric_readings'
      `;
      assert.equal(activity.after_image.metric_id, survivorId);

      const importedId = randomUUID();
      await server.database.db.insert(schema.metricReadings).values({
        id: importedId,
        userId: user.userId,
        deviceId: "server-import",
        metricId: survivorId,
        valueJson: { value: 81 },
        scalarValue: 81,
        atTime: new Date("2026-07-02T07:00:00.000Z"),
        provenance: "integration",
        source: "garmin",
        externalId: "weigh-in-1",
        updatedAt: new Date("2026-07-02T07:00:00.000Z")
      });
      await push(server, user, "device-b", "metric_readings", [
        readingChange({
          id: importedId,
          metricId: survivorId,
          value: 99,
          provenance: "integration",
          at: "2026-07-02T08:00:00.000Z",
          deletedAt: "2026-07-02T08:00:00.000Z"
        })
      ]);
      const imported = (await readingRows(server, user)).find(
        (row) => row.id === importedId
      );
      assert.notEqual(imported.deleted_at, null, "the device may archive an import");
      assert.equal(imported.scalar_value, 81, "but never rewrites its value");
      assert.equal(imported.source, "garmin");
    } finally {
      await server.database.close();
    }
  }
);

test(
  "a Metric push can't reach another user's Metric, by id or by alias",
  { skip },
  async () => {
    const server = await createServer();
    try {
      const owner = await createSignedInUser(server);
      const attacker = await createSignedInUser(server);
      const ownerMetricId = randomUUID();
      await push(server, owner, "device-a", "metrics", [
        metricChange({ id: ownerMetricId })
      ]);

      const overwrite = await push(server, attacker, "device-x", "metrics", [
        metricChange({ id: ownerMetricId, at: "2026-07-09T00:00:00.000Z", unit: "pound" })
      ]);
      assert.deepEqual(overwrite.accepted, []);
      const reading = await push(server, attacker, "device-x", "metric_readings", [
        readingChange({ metricId: ownerMetricId, value: 1 })
      ]);
      assert.deepEqual(reading.accepted, []);

      const attackerDefault = await push(server, attacker, "device-x", "metrics", [
        metricChange({ id: randomUUID() })
      ]);
      assert.deepEqual(attackerDefault.merged, [], "never folds across users");
      assert.equal((await metricRows(server, owner))[0].unit, "kilogram");
      assert.equal((await readingRows(server, owner)).length, 0);
    } finally {
      await server.database.close();
    }
  }
);

async function createServer() {
  return createMigratedServerApp({
    databaseUrl,
    logger: { info() {}, error() {} },
    auth: false
  });
}

async function createSignedInUser(serverApp) {
  const userId = `user-${randomUUID()}`;
  const sessionToken = `session-${randomUUID()}`;
  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: "Metrics Push User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
  await serverApp.database.db.insert(schema.session).values({
    id: `session-row-${randomUUID()}`,
    token: sessionToken,
    userId,
    expiresAt: new Date("2099-01-01T00:00:00.000Z")
  });
  return { userId, sessionToken };
}

async function push(serverApp, user, deviceId, entity, changes) {
  const response = await serverApp.app.request("/sync/push", {
    method: "POST",
    headers: {
      authorization: `Bearer ${user.sessionToken}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({ protocolVersion: 1, deviceId, entity, changes })
  });
  assert.equal(response.status, 200, await response.clone().text());
  return response.json();
}

function metricChange({
  id,
  name = "Body Weight",
  unit = "kilogram",
  at = "2026-07-01T08:00:00.000Z",
  deletedAt = null,
  goalTargetValue = null,
  activityLogId
}) {
  const payload = {
    id,
    name,
    unit,
    value_shape: "scalar",
    metric_group: "bodyComposition",
    goal_type: "decrease",
    goal_target_value: goalTargetValue,
    enabled: true,
    pinned: true,
    sort_order: 0,
    updated_at: at,
    deleted_at: deletedAt
  };
  const change = { id, payload, updatedAt: at, deletedAt };
  return activityLogId === undefined
    ? change
    : { ...change, ...activityEnvelope(change, activityLogId) };
}

function readingChange({
  id = randomUUID(),
  metricId,
  value,
  provenance = "manual",
  at = "2026-07-01T09:00:00.000Z",
  deletedAt = null
}) {
  const payload = {
    id,
    metric_id: metricId,
    // As the app sends it: the value object as JSON text.
    value_json: JSON.stringify({ value }),
    scalar_value: value,
    scalar_entered: String(value),
    at_time: "2026-07-01T07:00:00.000Z",
    window_started_at: null,
    window_ended_at: null,
    provenance,
    source: provenance === "manual" ? "manual" : "garmin",
    external_id: null,
    comment: null,
    updated_at: at,
    deleted_at: deletedAt
  };
  return { id, payload, updatedAt: at, deletedAt };
}

function activityEnvelope(change, activityLogId = randomUUID()) {
  return {
    activityLogId,
    actor: "app",
    batchId: `batch-${activityLogId}`,
    beforeImage: null,
    afterImage: change.payload,
    occurredAt: change.updatedAt
  };
}

function metricRows(serverApp, user) {
  return serverApp.database.sql`
    select id, unit, goal_target_value, deleted_at from metrics
    where user_id = ${user.userId}
    order by id
  `;
}

function readingRows(serverApp, user) {
  return serverApp.database.sql`
    select id, metric_id, value_json, scalar_value, source, deleted_at
    from metric_readings
    where user_id = ${user.userId}
    order by id
  `;
}
