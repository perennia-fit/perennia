import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  createMigratedServerApp,
  createSyncTombstoneGcWorker,
  createDrizzleSyncTombstoneGcStore,
  schema,
  SYNC_TOMBSTONE_GC_JOB_NAME,
  SYNC_TOMBSTONE_GC_SCHEDULE_CRON,
  SYNC_TOMBSTONE_GC_SCHEDULE_KEY
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

test("tombstone GC worker schedules the daily job and logs GC counts", async () => {
  const operations = [];
  const handlers = new Map();
  const logEvents = [];
  const worker = createSyncTombstoneGcWorker({
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
    tombstoneGcStore: {
      async collectExpiredLoggedSetTombstones(input) {
        assert.equal(
          input.now.toISOString(),
          "2026-06-22T15:00:00.000Z"
        );
        return {
          deletedCount: 3,
          markerCount: 3,
          cutoff: "2025-12-24T15:00:00.000Z"
        };
      }
    },
    logger: {
      info(payload, message) {
        logEvents.push({ payload, message });
      }
    },
    clock: () => new Date("2026-06-22T15:00:00.000Z")
  });

  await worker.start();
  await handlers.get(SYNC_TOMBSTONE_GC_JOB_NAME)({
    id: "gc-job-1",
    name: SYNC_TOMBSTONE_GC_JOB_NAME,
    data: {}
  });

  assert.deepEqual(operations, [
    { type: "ensureQueue", name: SYNC_TOMBSTONE_GC_JOB_NAME },
    { type: "work", name: SYNC_TOMBSTONE_GC_JOB_NAME },
    {
      type: "schedule",
      name: SYNC_TOMBSTONE_GC_JOB_NAME,
      cron: SYNC_TOMBSTONE_GC_SCHEDULE_CRON,
      key: SYNC_TOMBSTONE_GC_SCHEDULE_KEY,
      data: { source: "sync-tombstone-gc" }
    }
  ]);
  assert.ok(
    logEvents.some(
      (event) =>
        event.message === "sync tombstone GC completed" &&
        event.payload.deletedCount === 3 &&
        event.payload.markerCount === 3
    )
  );
});

test(
  "tombstone GC removes only deleted logged sets older than 180 days",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const store = createDrizzleSyncTombstoneGcStore(serverApp.database.db);
    const { userId, sessionToken } = await createSignedInUser(serverApp);
    const expiredId = randomUUID();
    const recentId = randomUUID();
    const liveId = randomUUID();
    const now = new Date("2026-06-22T15:00:00.000Z");
    const expiredDeletedAt = new Date("2025-12-01T15:00:00.000Z");
    const recentDeletedAt = new Date("2026-01-15T15:00:00.000Z");
    const liveUpdatedAt = new Date("2026-06-01T15:00:00.000Z");

    try {
      await serverApp.database.db.insert(schema.loggedSets).values([
        {
          id: expiredId,
          userId,
          deviceId: "device-a",
          payload: _loggedSetPayload(expiredId, "5", expiredDeletedAt, expiredDeletedAt),
          updatedAt: expiredDeletedAt,
          deletedAt: expiredDeletedAt,
          receivedAt: expiredDeletedAt
        },
        {
          id: recentId,
          userId,
          deviceId: "device-a",
          payload: _loggedSetPayload(recentId, "6", recentDeletedAt, recentDeletedAt),
          updatedAt: recentDeletedAt,
          deletedAt: recentDeletedAt,
          receivedAt: recentDeletedAt
        },
        {
          id: liveId,
          userId,
          deviceId: "device-a",
          payload: _loggedSetPayload(liveId, "7", liveUpdatedAt),
          updatedAt: liveUpdatedAt,
          deletedAt: null,
          receivedAt: liveUpdatedAt
        }
      ]);

      const first = await store.collectExpiredLoggedSetTombstones({ now });
      const second = await store.collectExpiredLoggedSetTombstones({ now });
      const remainingRows = await serverApp.database.sql`
        select id, deleted_at
        from logged_sets
        where id in (${expiredId}, ${recentId}, ${liveId})
        order by id
      `;
      const markers = await serverApp.database.sql`
        select logged_set_id, tombstone_updated_at, gc_at
        from logged_set_tombstone_gc_markers
        where user_id = ${userId}
      `;
      const pullResponse = await serverApp.app.request("/sync/pull", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          cursor: null,
          limit: 100
        })
      });
      const pullBody = await pullResponse.json();

      assert.equal(first.deletedCount, 1);
      assert.equal(first.markerCount, 1);
      assert.equal(first.cutoff, "2025-12-24T15:00:00.000Z");
      assert.equal(second.deletedCount, 0);
      assert.equal(second.markerCount, 0);
      assert.deepEqual(
        remainingRows.map((row) => row.id).sort(),
        [liveId, recentId].sort()
      );
      assert.equal(markers.length, 1);
      assert.equal(markers[0].logged_set_id, expiredId);
      assert.equal(
        new Date(markers[0].tombstone_updated_at).toISOString(),
        expiredDeletedAt.toISOString()
      );
      assert.equal(new Date(markers[0].gc_at).toISOString(), now.toISOString());
      assert.equal(pullResponse.status, 200);
      assert.deepEqual(
        pullBody.changes.map((change) => change.id).sort(),
        [liveId, recentId].sort()
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "a stale live push cannot resurrect a logged set after tombstone GC",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const store = createDrizzleSyncTombstoneGcStore(serverApp.database.db);
    const { userId, sessionToken } = await createSignedInUser(serverApp);
    const setId = randomUUID();
    const tombstoneAt = new Date("2025-12-01T15:00:00.000Z");

    try {
      await serverApp.database.db.insert(schema.loggedSets).values({
        id: setId,
        userId,
        deviceId: "device-delete",
        payload: _loggedSetPayload(setId, "5", tombstoneAt, tombstoneAt),
        updatedAt: tombstoneAt,
        deletedAt: tombstoneAt,
        receivedAt: tombstoneAt
      });
      await store.collectExpiredLoggedSetTombstones({
        now: new Date("2026-06-22T15:00:00.000Z")
      });

      const response = await serverApp.app.request("/sync/push", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          deviceId: "lagging-device",
          entity: "logged_sets",
          changes: [
            {
              id: setId,
              payload: _loggedSetPayload(
                setId,
                "5",
                new Date("2025-11-01T15:00:00.000Z")
              ),
              updatedAt: "2025-11-01T15:00:00.000Z",
              deletedAt: null
            }
          ]
        })
      });
      const body = await response.json();
      const rows = await serverApp.database.sql`
        select id from logged_sets where id = ${setId}
      `;

      assert.equal(response.status, 200);
      assert.deepEqual(body.accepted, [setId]);
      assert.deepEqual(body.applied, []);
      assert.equal(rows.length, 0);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "a cursor older than the 180-day tombstone window forces full re-sync",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const { sessionToken } = await createSignedInUser(serverApp);

    try {
      const response = await serverApp.app.request("/sync/pull", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          cursor: "2025-01-01T00:00:00.000Z|stale-row",
          limit: 100
        })
      });
      const body = await response.json();

      assert.equal(response.status, 200);
      assert.equal(body.fullResyncRequired, true);
      assert.deepEqual(body.changes, []);
      assert.equal(body.nextCursor, "2025-01-01T00:00:00.000Z|stale-row");
    } finally {
      await serverApp.database.close();
    }
  }
);

async function createSignedInUser(serverApp) {
  const userId = `user-${randomUUID()}`;
  const sessionToken = `session-${randomUUID()}`;

  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: "Retention User",
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

function _loggedSetPayload(id, repsEntered, updatedAt, deletedAt = null) {
  return {
    id,
    workout_id: "018f6a90-6d7f-7d63-bfc1-6f1025e0c010",
    exercise_id: "018f6a90-6d7f-7d63-bfc1-6f1025e0c020",
    position: 0,
    reps_value: Number.parseInt(repsEntered, 10),
    reps_unit: "rep",
    reps_entered: repsEntered,
    is_completed: false,
    updated_at: updatedAt.toISOString(),
    deleted_at: deletedAt?.toISOString() ?? null
  };
}
