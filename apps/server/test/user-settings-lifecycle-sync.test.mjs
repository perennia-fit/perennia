import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { eq } from "drizzle-orm";

import { createMigratedServerApp, schema } from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error(
    "DATABASE_URL must be set for server Postgres integration tests."
  );
}

const skip = databaseUrl ? false : "DATABASE_URL is not set.";

test(
  "the account-level Settings singleton round-trips as an LWW opaque row, " +
    "resolves last-writer-wins across devices, and is tenant-isolated",
  { skip },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });

    try {
      const userA = await createSignedInUser(serverApp);
      const userB = await createSignedInUser(serverApp);
      const settingsId = `user-settings:${userA.userId}`;
      const t0 = "2025-06-30T08:00:00.000Z";
      const t1 = "2025-06-30T09:00:00.000Z";

      // Device A pushes the account-level Settings singleton.
      await syncPushOk(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "user_settings",
        changes: [
          {
            id: settingsId,
            payload: settingsPayload(settingsId, { unit_system: "imperial" }, t0),
            updatedAt: t0,
            deletedAt: null
          }
        ]
      });

      // A pull surfaces the singleton as an opaque row.
      const pulledA = await pullAll(serverApp.app, userA.sessionToken);
      const settingsRows = pulledA.filter(
        (change) => change.entity === "user_settings"
      );
      assert.equal(settingsRows.length, 1);
      assert.equal(settingsRows[0].id, settingsId);
      assert.equal(settingsRows[0].payload.unit_system, "imperial");

      // Device B overwrites the SAME singleton with a newer clock; LWW picks it.
      await syncPushOk(serverApp.app, userA.sessionToken, {
        deviceId: "device-b",
        entity: "user_settings",
        changes: [
          {
            id: settingsId,
            payload: settingsPayload(settingsId, { unit_system: "metric" }, t1),
            updatedAt: t1,
            deletedAt: null
          }
        ]
      });
      const rowAfterB = await serverApp.database.db
        .select()
        .from(schema.userSettings)
        .where(eq(schema.userSettings.id, settingsId));
      assert.equal(rowAfterB.length, 1);
      assert.equal(rowAfterB[0].payload.unit_system, "metric");
      assert.equal(rowAfterB[0].deviceId, "device-b");

      // A stale re-push from device A (older clock) loses LWW and does not clobber.
      await syncPushOk(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "user_settings",
        changes: [
          {
            id: settingsId,
            payload: settingsPayload(settingsId, { unit_system: "imperial" }, t0),
            updatedAt: t0,
            deletedAt: null
          }
        ]
      });
      const rowAfterStale = await serverApp.database.db
        .select()
        .from(schema.userSettings)
        .where(eq(schema.userSettings.id, settingsId));
      assert.equal(rowAfterStale[0].payload.unit_system, "metric");

      // TENANT ISOLATION: user B cannot overwrite user A's singleton by pushing
      // the same client PK — the write is silently ignored (standing gate).
      await syncPushOk(serverApp.app, userB.sessionToken, {
        deviceId: "device-b-user-b",
        entity: "user_settings",
        changes: [
          {
            id: settingsId,
            payload: settingsPayload(settingsId, { unit_system: "imperial" }, t1),
            updatedAt: t1,
            deletedAt: null
          }
        ]
      });
      const rowAfterHijack = await serverApp.database.db
        .select()
        .from(schema.userSettings)
        .where(eq(schema.userSettings.id, settingsId));
      assert.equal(rowAfterHijack.length, 1);
      assert.equal(rowAfterHijack[0].userId, userA.userId);
      assert.equal(rowAfterHijack[0].payload.unit_system, "metric");

      // User B's pull never sees user A's settings row.
      const pulledB = await pullAll(serverApp.app, userB.sessionToken);
      assert.equal(
        pulledB.some((change) => change.entity === "user_settings"),
        false
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "kill-and-reopen mid-change: re-pushing the same Settings change after a " +
    "restart is an idempotent no-op, not a duplicate",
  { skip },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });

    try {
      const user = await createSignedInUser(serverApp);
      const settingsId = `user-settings:${user.userId}`;
      const activityLogId = randomUUID();
      const batchId = randomUUID();
      const updatedAt = "2025-06-30T08:00:00.000Z";
      const change = {
        id: settingsId,
        payload: settingsPayload(
          settingsId,
          { theme_preference: "dark" },
          updatedAt
        ),
        updatedAt,
        deletedAt: null,
        activityLogId,
        actor: "app",
        batchId,
        beforeImage: null,
        afterImage: settingsPayload(
          settingsId,
          { theme_preference: "dark" },
          updatedAt
        ),
        occurredAt: updatedAt
      };

      // The device saves the change locally and pushes, then "dies" before it
      // records the push acknowledgment — so on reopen it re-pushes the exact
      // same change (same activityLogId).
      await syncPushOk(serverApp.app, user.sessionToken, {
        deviceId: "device-a",
        entity: "user_settings",
        changes: [change]
      });
      await syncPushOk(serverApp.app, user.sessionToken, {
        deviceId: "device-a",
        entity: "user_settings",
        changes: [change]
      });

      // Exactly one settings row and exactly one Activity Log entry survive.
      const rows = await serverApp.database.db
        .select()
        .from(schema.userSettings)
        .where(eq(schema.userSettings.id, settingsId));
      assert.equal(rows.length, 1);
      assert.equal(rows[0].payload.theme_preference, "dark");

      const activityRows = await serverApp.database.db
        .select()
        .from(schema.activityLog)
        .where(eq(schema.activityLog.id, activityLogId));
      assert.equal(activityRows.length, 1);
      assert.equal(activityRows[0].entityTable, "user_settings");
    } finally {
      await serverApp.database.close();
    }
  }
);

function settingsPayload(id, overrides, updatedAt) {
  return {
    id,
    theme_preference: "system",
    unit_system: "metric",
    week_start_day: "monday",
    default_weight_increment: 2.5,
    home_screen_display: "comfortable",
    pr_tracking_enabled: true,
    mark_sets_complete_by_default: false,
    auto_select_next_set: true,
    updated_at: updatedAt,
    deleted_at: null,
    ...overrides
  };
}

async function syncPush(app, sessionToken, body) {
  return app.request("/sync/push", {
    method: "POST",
    headers: {
      authorization: `Bearer ${sessionToken}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({ protocolVersion: 1, ...body })
  });
}

async function syncPushOk(app, sessionToken, body) {
  const response = await syncPush(app, sessionToken, body);
  assert.equal(response.status, 200);
  return response.json();
}

async function pullAll(app, sessionToken) {
  const changes = [];
  let cursor = null;
  for (let i = 0; i < 50; i += 1) {
    const response = await app.request("/sync/pull", {
      method: "POST",
      headers: {
        authorization: `Bearer ${sessionToken}`,
        "content-type": "application/json"
      },
      body: JSON.stringify({ protocolVersion: 1, cursor, limit: 100 })
    });
    assert.equal(response.status, 200);
    const window = await response.json();
    changes.push(...window.changes);
    if (window.changes.length === 0 || window.nextCursor === cursor) {
      break;
    }
    cursor = window.nextCursor;
  }
  return changes;
}

async function createSignedInUser(serverApp) {
  const userId = `user-${randomUUID()}`;
  const sessionToken = `session-${randomUUID()}`;

  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: "User Settings Sync User",
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
