import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  ACTIVITY_LOG_RETENTION_JOB_NAME,
  ACTIVITY_LOG_RETENTION_SCHEDULE_CRON,
  ACTIVITY_LOG_RETENTION_SCHEDULE_KEY,
  createActivityLogRetentionWorker,
  createDrizzleActivityLogRetentionStore,
  createMigratedServerApp,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

test("activity log retention worker schedules the prune job and logs counts", async () => {
  const operations = [];
  const handlers = new Map();
  const logEvents = [];
  const worker = createActivityLogRetentionWorker({
    jobs: {
      async start() {},
      async stop() {},
      async ensureQueue(input) {
        operations.push({ type: "ensureQueue", ...input });
      },
      async schedule(input) {
        operations.push({ type: "schedule", ...input });
      },
      async send() {
        return null;
      },
      async work(name, handler) {
        operations.push({ type: "work", name });
        handlers.set(name, handler);
      }
    },
    activityLogRetentionStore: {
      async pruneExpiredActivityLogEntries(input) {
        assert.equal(
          input.now.toISOString(),
          "2026-06-22T15:30:00.000Z"
        );
        return {
          prunedCount: 7,
          cutoff: "2025-12-24T15:30:00.000Z",
          batchSize: 500
        };
      }
    },
    logger: {
      info(payload, message) {
        logEvents.push({ payload, message });
      }
    },
    clock: () => new Date("2026-06-22T15:30:00.000Z")
  });

  await worker.start();
  await handlers.get(ACTIVITY_LOG_RETENTION_JOB_NAME)({
    id: "activity-retention-job-1",
    name: ACTIVITY_LOG_RETENTION_JOB_NAME,
    data: {}
  });

  assert.deepEqual(operations, [
    { type: "ensureQueue", name: ACTIVITY_LOG_RETENTION_JOB_NAME },
    { type: "work", name: ACTIVITY_LOG_RETENTION_JOB_NAME },
    {
      type: "schedule",
      name: ACTIVITY_LOG_RETENTION_JOB_NAME,
      cron: ACTIVITY_LOG_RETENTION_SCHEDULE_CRON,
      key: ACTIVITY_LOG_RETENTION_SCHEDULE_KEY,
      data: { source: "activity-log-retention" }
    }
  ]);
  assert.ok(
    logEvents.some(
      (event) =>
        event.message === "activity log retention prune completed" &&
        event.payload.prunedCount === 7
    )
  );
});

test(
  "activity log retention prunes 181-day entries and keeps 179-day entries",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const store = createDrizzleActivityLogRetentionStore(serverApp.database.db, {
      batchSize: 1
    });
    const userId = await createUser(serverApp);
    const now = new Date("2026-06-22T15:30:00.000Z");
    const oldEntryId = randomUUID();
    const recentEntryId = randomUUID();
    const exactCutoffEntryId = randomUUID();

    try {
      await insertActivityLog(serverApp, {
        id: oldEntryId,
        userId,
        batchId: "old-batch",
        occurredAt: new Date(now.getTime() - 181 * 24 * 60 * 60 * 1000)
      });
      await insertActivityLog(serverApp, {
        id: recentEntryId,
        userId,
        batchId: "recent-batch",
        occurredAt: new Date(now.getTime() - 179 * 24 * 60 * 60 * 1000)
      });
      await insertActivityLog(serverApp, {
        id: exactCutoffEntryId,
        userId,
        batchId: "cutoff-batch",
        occurredAt: new Date(now.getTime() - 180 * 24 * 60 * 60 * 1000)
      });

      const first = await store.pruneExpiredActivityLogEntries({ now });
      const second = await store.pruneExpiredActivityLogEntries({ now });
      const rows = await serverApp.database.sql`
        select id
        from activity_log
        where id in (${oldEntryId}, ${recentEntryId}, ${exactCutoffEntryId})
        order by id
      `;

      assert.equal(first.prunedCount, 1);
      assert.equal(first.batchSize, 1);
      assert.equal(first.cutoff, "2025-12-24T15:30:00.000Z");
      assert.equal(second.prunedCount, 0);
      assert.deepEqual(
        rows.map((row) => row.id).sort(),
        [exactCutoffEntryId, recentEntryId].sort()
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "activity log retention keeps in-window batch images recoverable after prune",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const store = createDrizzleActivityLogRetentionStore(serverApp.database.db);
    const userId = await createUser(serverApp);
    const now = new Date("2026-06-22T15:30:00.000Z");
    const keptBatchId = `batch-${randomUUID()}`;
    const keptEntryId = randomUUID();

    try {
      await insertActivityLog(serverApp, {
        id: keptEntryId,
        userId,
        batchId: keptBatchId,
        beforeImage: { id: "set-1", reps_entered: "5" },
        afterImage: { id: "set-1", reps_entered: "6" },
        occurredAt: new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000)
      });
      await insertActivityLog(serverApp, {
        id: randomUUID(),
        userId,
        batchId: "expired-batch",
        occurredAt: new Date(now.getTime() - 181 * 24 * 60 * 60 * 1000)
      });

      await store.pruneExpiredActivityLogEntries({ now });
      const rows = await serverApp.database.sql`
        select id, batch_id, before_image, after_image
        from activity_log
        where batch_id = ${keptBatchId}
      `;

      assert.equal(rows.length, 1);
      assert.equal(rows[0].id, keptEntryId);
      assert.deepEqual(rows[0].before_image, {
        id: "set-1",
        reps_entered: "5"
      });
      assert.deepEqual(rows[0].after_image, {
        id: "set-1",
        reps_entered: "6"
      });
    } finally {
      await serverApp.database.close();
    }
  }
);

async function createUser(serverApp) {
  const userId = `user-${randomUUID()}`;

  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: "Activity Retention User",
    email: `${userId}@example.com`,
    emailVerified: true
  });

  return userId;
}

function insertActivityLog(
  serverApp,
  {
    id,
    userId,
    batchId,
    beforeImage = { id: "set-1", reps_entered: "4" },
    afterImage = { id: "set-1", reps_entered: "5" },
    occurredAt
  }
) {
  return serverApp.database.db.insert(schema.activityLog).values({
    id,
    userId,
    actor: "sync",
    batchId,
    entityTable: "logged_sets",
    entityId: "set-1",
    beforeImage,
    afterImage,
    occurredAt
  });
}
