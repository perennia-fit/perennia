import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  createDrizzleJobHeartbeatStore,
  createJobSpine,
  createMigratedServerApp,
  createPgBossOptions,
  JOB_SPINE_CRON_HEARTBEAT,
  JOB_SPINE_CRON_SCHEDULE_KEY,
  JOB_SPINE_ENQUEUED_HEARTBEAT,
  JOB_SPINE_ENQUEUED_MARKER,
  JOB_SPINE_SCHEDULE_CRON
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

test("job spine uses the Jobs port for queue setup, scheduling, and work", async () => {
  const operations = [];
  const workers = new Map();
  const seenMarkers = new Set();
  const heartbeatCalls = [];
  const logEvents = [];
  const jobs = {
    async start() {
      operations.push({ type: "start" });
    },
    async stop() {
      operations.push({ type: "stop" });
    },
    async ensureQueue(input) {
      operations.push({ type: "ensureQueue", ...input });
    },
    async schedule(input) {
      operations.push({ type: "schedule", ...input });
    },
    async send(input) {
      operations.push({ type: "send", ...input });
      return "queued-job-id";
    },
    async work(name, handler) {
      workers.set(name, handler);
      operations.push({ type: "work", name });
    }
  };
  const heartbeatStore = {
    async recordHeartbeat(input) {
      heartbeatCalls.push(input);
      const key = `${input.jobName}:${input.marker}`;
      const inserted = !seenMarkers.has(key);
      seenMarkers.add(key);

      return {
        inserted,
        id: inserted ? `heartbeat-${heartbeatCalls.length}` : null
      };
    }
  };
  const spine = createJobSpine({
    jobs,
    heartbeatStore,
    logger: {
      info(payload, message) {
        logEvents.push({ payload, message });
      }
    },
    clock: () => new Date("2026-06-23T08:00:00.000Z")
  });

  await spine.start();

  assert.deepEqual(
    operations.filter((operation) => operation.type === "ensureQueue"),
    [
      { type: "ensureQueue", name: JOB_SPINE_CRON_HEARTBEAT },
      { type: "ensureQueue", name: JOB_SPINE_ENQUEUED_HEARTBEAT }
    ]
  );
  assert.deepEqual(
    operations.filter((operation) => operation.type === "work"),
    [
      { type: "work", name: JOB_SPINE_CRON_HEARTBEAT },
      { type: "work", name: JOB_SPINE_ENQUEUED_HEARTBEAT }
    ]
  );
  assert.deepEqual(
    operations.find((operation) => operation.type === "schedule"),
    {
      type: "schedule",
      name: JOB_SPINE_CRON_HEARTBEAT,
      cron: JOB_SPINE_SCHEDULE_CRON,
      key: JOB_SPINE_CRON_SCHEDULE_KEY,
      data: { source: "worker-spine" }
    }
  );
  assert.deepEqual(operations.find((operation) => operation.type === "send"), {
    type: "send",
    name: JOB_SPINE_ENQUEUED_HEARTBEAT,
    data: { marker: JOB_SPINE_ENQUEUED_MARKER, source: "worker-spine" },
    options: {
      singletonKey: JOB_SPINE_ENQUEUED_MARKER,
      singletonSeconds: 31_536_000,
      retryLimit: 3
    }
  });

  await workers.get(JOB_SPINE_CRON_HEARTBEAT)({
    id: "cron-job-id",
    name: JOB_SPINE_CRON_HEARTBEAT,
    data: { source: "scheduler" }
  });
  await workers.get(JOB_SPINE_ENQUEUED_HEARTBEAT)({
    id: "queued-job-id-1",
    name: JOB_SPINE_ENQUEUED_HEARTBEAT,
    data: { marker: JOB_SPINE_ENQUEUED_MARKER }
  });
  await workers.get(JOB_SPINE_ENQUEUED_HEARTBEAT)({
    id: "queued-job-id-2",
    name: JOB_SPINE_ENQUEUED_HEARTBEAT,
    data: { marker: JOB_SPINE_ENQUEUED_MARKER }
  });

  assert.deepEqual(
    heartbeatCalls.map((call) => ({
      jobName: call.jobName,
      marker: call.marker,
      kind: call.kind,
      payload: call.payload
    })),
    [
      {
        jobName: JOB_SPINE_CRON_HEARTBEAT,
        marker: "cron-job-id",
        kind: "scheduled",
        payload: { jobId: "cron-job-id", source: "scheduler" }
      },
      {
        jobName: JOB_SPINE_ENQUEUED_HEARTBEAT,
        marker: JOB_SPINE_ENQUEUED_MARKER,
        kind: "enqueued",
        payload: { jobId: "queued-job-id-1" }
      },
      {
        jobName: JOB_SPINE_ENQUEUED_HEARTBEAT,
        marker: JOB_SPINE_ENQUEUED_MARKER,
        kind: "enqueued",
        payload: { jobId: "queued-job-id-2" }
      }
    ]
  );
  assert.ok(
    logEvents.some((event) => event.message === "job heartbeat recorded")
  );
  assert.ok(
    logEvents.some((event) => event.message === "job heartbeat already recorded")
  );

  await spine.stop();
  assert.equal(operations.at(-1).type, "stop");
});

test("pg-boss options enable migrations on worker start", () => {
  const options = createPgBossOptions(
    "postgres://postgres:postgres@localhost/perennia_test"
  );

  assert.equal(
    options.connectionString,
    "postgres://postgres:postgres@localhost/perennia_test"
  );
  assert.equal(options.application_name, "perennia-worker");
  assert.equal(options.schema, "pgboss");
  assert.equal(options.migrate, true);
  assert.equal(options.schedule, true);
});

test(
  "job heartbeat store records each job marker once",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const heartbeatStore = createDrizzleJobHeartbeatStore(serverApp.database.db);
    const marker = `marker-${randomUUID()}`;

    try {
      const first = await heartbeatStore.recordHeartbeat({
        jobName: JOB_SPINE_ENQUEUED_HEARTBEAT,
        marker,
        kind: "enqueued",
        payload: { jobId: "first" },
        ranAt: new Date("2026-06-23T08:00:00.000Z")
      });
      const second = await heartbeatStore.recordHeartbeat({
        jobName: JOB_SPINE_ENQUEUED_HEARTBEAT,
        marker,
        kind: "enqueued",
        payload: { jobId: "second" },
        ranAt: new Date("2026-06-23T08:00:01.000Z")
      });

      assert.equal(first.inserted, true);
      assert.equal(typeof first.id, "string");
      assert.equal(second.inserted, false);
      assert.equal(second.id, null);

      const rows = await serverApp.database.sql`
        select job_name, marker, kind, payload, ran_at
        from job_heartbeats
        where job_name = ${JOB_SPINE_ENQUEUED_HEARTBEAT}
          and marker = ${marker}
      `;
      assert.equal(rows.length, 1);
      assert.equal(rows[0].job_name, JOB_SPINE_ENQUEUED_HEARTBEAT);
      assert.equal(rows[0].marker, marker);
      assert.equal(rows[0].kind, "enqueued");
      assert.equal(rows[0].payload.jobId, "first");
      assert.equal(
        new Date(rows[0].ran_at).toISOString(),
        "2026-06-23T08:00:00.000Z"
      );
    } finally {
      await serverApp.database.close();
    }
  }
);
