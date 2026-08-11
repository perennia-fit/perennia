import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { createApp, createMigratedServerApp, schema } from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for account deletion tests.");
}

test("account deletion endpoint marks the account through the route contract", async () => {
  const requests = [];
  const app = createApp({
    logger: { info() {}, error() {} },
    accountDeletionStore: {
      async requestAccountDeletion(token) {
        requests.push(token);
        return token === "session-token"
          ? {
              userId: "user-1",
              deletionRequestedAt: "2026-06-22T16:00:00.000Z"
            }
          : null;
      }
    }
  });

  const response = await app.request("/account/deletion", {
    method: "POST",
    headers: {
      authorization: "Bearer session-token"
    }
  });

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    deletionRequestedAt: "2026-06-22T16:00:00.000Z",
    localReplicaPreserved: true
  });
  assert.deepEqual(requests, ["session-token"]);
});

test("account deletion endpoint rejects missing or invalid bearer tokens", async () => {
  const app = createApp({
    logger: { info() {}, error() {} },
    accountDeletionStore: {
      async requestAccountDeletion() {
        return null;
      }
    }
  });

  const missingResponse = await app.request("/account/deletion", {
    method: "POST"
  });
  assert.equal(missingResponse.status, 401);

  const invalidResponse = await app.request("/account/deletion", {
    method: "POST",
    headers: {
      authorization: "Bearer expired-token"
    }
  });
  assert.equal(invalidResponse.status, 401);
});

test(
  "deleted accounts stop syncing while server data remains for the purge job",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const { userId, sessionToken } = await createSignedInUser(serverApp);
    const setId = randomUUID();
    const updatedAt = new Date("2026-06-22T08:00:00.000Z");

    try {
      await serverApp.database.db.insert(schema.loggedSets).values({
        id: setId,
        userId,
        deviceId: "device-a",
        payload: {
          id: setId,
          reps_entered: "5",
          updated_at: updatedAt.toISOString(),
          deleted_at: null
        },
        updatedAt,
        deletedAt: null,
        receivedAt: updatedAt
      });

      const deletionResponse = await serverApp.app.request("/account/deletion", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`
        }
      });

      assert.equal(deletionResponse.status, 200);
      const deletionBody = await deletionResponse.json();
      assert.equal(typeof deletionBody.deletionRequestedAt, "string");
      assert.equal(deletionBody.localReplicaPreserved, true);

      const userRows = await serverApp.database.sql`
        select deletion_requested_at
        from "user"
        where id = ${userId}
      `;
      assert.equal(userRows.length, 1);
      assert.equal(typeof userRows[0].deletion_requested_at, "string");
      const deletionRequestedAt = new Date(userRows[0].deletion_requested_at);
      assert.equal(
        deletionRequestedAt.toISOString(),
        deletionBody.deletionRequestedAt
      );

      const syncResponse = await serverApp.app.request("/sync/pull", {
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

      assert.equal(syncResponse.status, 401);
      assert.deepEqual(await syncResponse.json(), {
        code: "sync_unauthorized",
        message:
          "Account deletion was requested. This device is now in Local-only Mode and its local data remains on the device."
      });

      const loggedSetRows = await serverApp.database.sql`
        select id, payload
        from logged_sets
        where user_id = ${userId}
      `;
      assert.equal(loggedSetRows.length, 1);
      assert.equal(loggedSetRows[0].id, setId);
      assert.equal(loggedSetRows[0].payload.reps_entered, "5");
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
    name: "Deletion User",
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
