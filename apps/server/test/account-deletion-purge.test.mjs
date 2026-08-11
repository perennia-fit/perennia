import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { eq } from "drizzle-orm";
import {
  ACCOUNT_DELETION_PURGE_JOB_NAME,
  ACCOUNT_DELETION_PURGE_SCHEDULE_CRON,
  ACCOUNT_DELETION_PURGE_SCHEDULE_KEY,
  createAccountDeletionPurgeWorker,
  createDrizzleAccountDeletionPurgeStore,
  createMigratedServerApp,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;
const DAY_MS = 24 * 60 * 60 * 1000;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for account purge tests.");
}

test("account deletion purge worker schedules the job and logs accounts", async () => {
  const operations = [];
  const handlers = new Map();
  const logEvents = [];
  const worker = createAccountDeletionPurgeWorker({
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
    accountDeletionPurgeStore: {
      async purgeExpiredDeletedAccounts(input) {
        assert.equal(input.now.toISOString(), "2026-06-22T15:30:00.000Z");
        return {
          purgedCount: 2,
          purgedUserIds: ["user-old-1", "user-old-2"],
          cutoff: "2026-05-23T15:30:00.000Z",
          batchSize: 100
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
  await handlers.get(ACCOUNT_DELETION_PURGE_JOB_NAME)({
    id: "account-purge-job-1",
    name: ACCOUNT_DELETION_PURGE_JOB_NAME,
    data: {}
  });

  assert.deepEqual(operations, [
    { type: "ensureQueue", name: ACCOUNT_DELETION_PURGE_JOB_NAME },
    { type: "work", name: ACCOUNT_DELETION_PURGE_JOB_NAME },
    {
      type: "schedule",
      name: ACCOUNT_DELETION_PURGE_JOB_NAME,
      cron: ACCOUNT_DELETION_PURGE_SCHEDULE_CRON,
      key: ACCOUNT_DELETION_PURGE_SCHEDULE_KEY,
      data: { source: "account-deletion-purge" }
    }
  ]);
  assert.ok(
    logEvents.some(
      (event) =>
        event.message === "account deletion purge completed" &&
        event.payload.purgedCount === 2 &&
        event.payload.purgedUserIds.includes("user-old-1")
    )
  );
});

test(
  "account deletion purge hard-deletes expired accounts and keeps grace accounts",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const store = createDrizzleAccountDeletionPurgeStore(serverApp.database.db, {
      batchSize: 1
    });
    const now = new Date("2026-06-22T15:30:00.000Z");
    const oldUser = await createSignedInUser(serverApp, {
      deletionRequestedAt: new Date(now.getTime() - 31 * DAY_MS)
    });
    const cutoffUser = await createSignedInUser(serverApp, {
      deletionRequestedAt: new Date(now.getTime() - 30 * DAY_MS)
    });
    const recentUser = await createSignedInUser(serverApp, {
      deletionRequestedAt: new Date(now.getTime() - 29 * DAY_MS)
    });
    const activeUser = await createSignedInUser(serverApp);

    try {
      await Promise.all([
        insertServerDataForUser(serverApp, oldUser.userId),
        insertServerDataForUser(serverApp, cutoffUser.userId),
        insertServerDataForUser(serverApp, recentUser.userId)
      ]);

      const first = await store.purgeExpiredDeletedAccounts({ now });
      const second = await store.purgeExpiredDeletedAccounts({ now });

      assert.deepEqual(first.purgedUserIds, [oldUser.userId]);
      assert.equal(first.purgedCount, 1);
      assert.equal(first.batchSize, 1);
      assert.equal(first.cutoff, "2026-05-23T15:30:00.000Z");
      assert.equal(second.purgedCount, 0);
      assert.deepEqual(second.purgedUserIds, []);

      const remainingUsers = await serverApp.database.sql`
        select id
        from "user"
        where id in (
          ${oldUser.userId},
          ${cutoffUser.userId},
          ${recentUser.userId},
          ${activeUser.userId}
        )
        order by id
      `;
      assert.deepEqual(
        remainingUsers.map((row) => row.id).sort(),
        [activeUser.userId, cutoffUser.userId, recentUser.userId].sort()
      );
      assert.deepEqual(await countServerRowsForUser(serverApp, oldUser.userId), {
        accounts: 0,
        activityLogEntries: 0,
        devicePushTokens: 0,
        loggedSetTombstoneGcMarkers: 0,
        loggedSets: 0,
        sessions: 0,
        users: 0
      });
      assert.deepEqual(
        await countServerRowsForUser(serverApp, recentUser.userId),
        {
          accounts: 1,
          activityLogEntries: 1,
          devicePushTokens: 1,
          loggedSetTombstoneGcMarkers: 1,
          loggedSets: 1,
          sessions: 1,
          users: 1
        }
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "delete then grace purge removes server data while the local replica remains",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const store = createDrizzleAccountDeletionPurgeStore(serverApp.database.db);
    const now = new Date("2026-06-22T15:30:00.000Z");
    const { userId, sessionToken } = await createSignedInUser(serverApp);
    const setId = randomUUID();
    const localReplica = new Map([
      [
        setId,
        {
          id: setId,
          repsEntered: "5",
          updatedAt: "2026-06-22T08:00:00.000Z"
        }
      ]
    ]);

    try {
      await insertServerDataForUser(serverApp, userId, { setId });

      const deletionResponse = await serverApp.app.request("/account/deletion", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`
        }
      });
      assert.equal(deletionResponse.status, 200);

      await serverApp.database.db
        .update(schema.user)
        .set({
          deletionRequestedAt: new Date(now.getTime() - 31 * DAY_MS)
        })
        .where(eq(schema.user.id, userId));

      const result = await store.purgeExpiredDeletedAccounts({ now });
      const serverRows = await countServerRowsForUser(serverApp, userId);

      assert.deepEqual(result.purgedUserIds, [userId]);
      assert.deepEqual(serverRows, {
        accounts: 0,
        activityLogEntries: 0,
        devicePushTokens: 0,
        loggedSetTombstoneGcMarkers: 0,
        loggedSets: 0,
        sessions: 0,
        users: 0
      });
      assert.deepEqual(localReplica.get(setId), {
        id: setId,
        repsEntered: "5",
        updatedAt: "2026-06-22T08:00:00.000Z"
      });
    } finally {
      await serverApp.database.close();
    }
  }
);

async function createSignedInUser(
  serverApp,
  { deletionRequestedAt = null } = {}
) {
  const userId = `user-${randomUUID()}`;
  const sessionToken = `session-${randomUUID()}`;
  const userValues = {
    id: userId,
    name: "Account Purge User",
    email: `${userId}@example.com`,
    emailVerified: true
  };

  if (deletionRequestedAt !== null) {
    userValues.deletionRequestedAt = deletionRequestedAt;
  }

  await serverApp.database.db.insert(schema.user).values(userValues);
  await serverApp.database.db.insert(schema.session).values({
    id: `session-row-${randomUUID()}`,
    token: sessionToken,
    userId,
    expiresAt: new Date("2099-01-01T00:00:00.000Z")
  });

  return { userId, sessionToken };
}

async function insertServerDataForUser(serverApp, userId, { setId } = {}) {
  const loggedSetId = setId ?? randomUUID();
  const updatedAt = new Date("2026-06-22T08:00:00.000Z");

  await serverApp.database.db.insert(schema.account).values({
    id: `account-${randomUUID()}`,
    accountId: `oauth-${randomUUID()}`,
    providerId: "google",
    userId
  });
  await serverApp.database.db.insert(schema.devicePushTokens).values({
    id: `token-${randomUUID()}`,
    userId,
    deviceId: "device-a",
    platform: "android",
    token: `push-${randomUUID()}`,
    createdAt: updatedAt,
    updatedAt
  });
  await serverApp.database.db.insert(schema.loggedSets).values({
    id: loggedSetId,
    userId,
    deviceId: "device-a",
    payload: {
      id: loggedSetId,
      reps_entered: "5",
      updated_at: updatedAt.toISOString(),
      deleted_at: null
    },
    updatedAt,
    deletedAt: null,
    receivedAt: updatedAt
  });
  await serverApp.database.db.insert(schema.activityLog).values({
    id: `activity-${randomUUID()}`,
    userId,
    actor: "sync",
    batchId: `batch-${randomUUID()}`,
    entityTable: "logged_sets",
    entityId: loggedSetId,
    beforeImage: null,
    afterImage: { id: loggedSetId, reps_entered: "5" },
    occurredAt: updatedAt
  });
  await serverApp.database.db.insert(schema.loggedSetTombstoneGcMarkers).values({
    id: `marker-${randomUUID()}`,
    userId,
    loggedSetId,
    deviceId: "device-a",
    tombstoneUpdatedAt: updatedAt,
    deletedAt: updatedAt,
    gcAt: updatedAt
  });
}

async function countServerRowsForUser(serverApp, userId) {
  const [
    accountRows,
    activityLogRows,
    devicePushTokenRows,
    markerRows,
    loggedSetRows,
    sessionRows,
    userRows
  ] = await Promise.all([
    serverApp.database.sql`
      select count(*)::int as count
      from "account"
      where "userId" = ${userId}
    `,
    serverApp.database.sql`
      select count(*)::int as count
      from activity_log
      where user_id = ${userId}
    `,
    serverApp.database.sql`
      select count(*)::int as count
      from device_push_tokens
      where user_id = ${userId}
    `,
    serverApp.database.sql`
      select count(*)::int as count
      from logged_set_tombstone_gc_markers
      where user_id = ${userId}
    `,
    serverApp.database.sql`
      select count(*)::int as count
      from logged_sets
      where user_id = ${userId}
    `,
    serverApp.database.sql`
      select count(*)::int as count
      from "session"
      where "userId" = ${userId}
    `,
    serverApp.database.sql`
      select count(*)::int as count
      from "user"
      where id = ${userId}
    `
  ]);

  return {
    accounts: Number(accountRows[0].count),
    activityLogEntries: Number(activityLogRows[0].count),
    devicePushTokens: Number(devicePushTokenRows[0].count),
    loggedSetTombstoneGcMarkers: Number(markerRows[0].count),
    loggedSets: Number(loggedSetRows[0].count),
    sessions: Number(sessionRows[0].count),
    users: Number(userRows[0].count)
  };
}
