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
  "NutritionGoal round-trips as an LWW opaque row, with tenant isolation " +
    "and archive (deletedAt) round-trip",
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
      const goalId = randomUUID();
      // Past timestamps so the server never clamps them to its wall-clock
      // serverClock (MAX_FUTURE_CLOCK_SKEW_MS); relative LWW ordering stays
      // honest regardless of when the test runs.
      const updatedAt = "2025-06-30T08:00:00.000Z";

      const pushGoal = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "nutrition_goals",
        changes: [
          {
            id: goalId,
            payload: goalPayload(goalId, "energy", 2200, updatedAt),
            updatedAt,
            deletedAt: null
          }
        ]
      });
      assert.equal(pushGoal.status, 200);
      assert.deepEqual((await pushGoal.json()).accepted, [goalId]);

      // TENANT ISOLATION: user B cannot overwrite user A's Goal keyed by the
      // same client PK. The push reports accepted (idempotent no-op) but the
      // stored row keeps user A's payload + ownership.
      const crossUserUpdatedAt = "2025-06-30T10:00:00.000Z";
      const crossPush = await syncPush(serverApp.app, userB.sessionToken, {
        deviceId: "device-b",
        entity: "nutrition_goals",
        changes: [
          {
            id: goalId,
            payload: goalPayload(goalId, "energy", 9999, crossUserUpdatedAt),
            updatedAt: crossUserUpdatedAt,
            deletedAt: null
          }
        ]
      });
      assert.equal(crossPush.status, 200);
      const storedGoal = await serverApp.database.db
        .select()
        .from(schema.nutritionGoals)
        .where(eq(schema.nutritionGoals.id, goalId));
      assert.equal(storedGoal.length, 1);
      assert.equal(storedGoal[0].userId, userA.userId);
      assert.equal(storedGoal[0].payload.target_value, 2200);

      // Device B (same user A account, different device) pulls its own rows;
      // the Goal round-trips.
      const pulled = await pullAll(serverApp.app, userA.sessionToken);
      const pulledGoal = pulled.find(
        (change) => change.entity === "nutrition_goals" && change.id === goalId
      );
      assert.ok(pulledGoal, "goal should round-trip");
      assert.equal(pulledGoal.payload.nutrient_id, "energy");
      assert.equal(pulledGoal.payload.target_value, 2200);
      assert.equal(pulledGoal.deletedAt, null);

      // User B pulls and sees none of user A's rows — strict per-user scoping.
      const userBPulled = await pullAll(serverApp.app, userB.sessionToken);
      assert.equal(
        userBPulled.filter((change) => change.id === goalId).length,
        0
      );

      // A newer edit wins LWW; an older replay loses.
      const newerUpdatedAt = "2025-06-30T12:00:00.000Z";
      const newerPush = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "nutrition_goals",
        changes: [
          {
            id: goalId,
            payload: goalPayload(goalId, "energy", 2400, newerUpdatedAt),
            updatedAt: newerUpdatedAt,
            deletedAt: null
          }
        ]
      });
      assert.equal(newerPush.status, 200);
      const stalePush = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "nutrition_goals",
        changes: [
          {
            id: goalId,
            payload: goalPayload(
              goalId,
              "energy",
              1000,
              "2025-06-30T09:00:00.000Z"
            ),
            updatedAt: "2025-06-30T09:00:00.000Z",
            deletedAt: null
          }
        ]
      });
      assert.equal(stalePush.status, 200);
      const afterLww = await serverApp.database.db
        .select()
        .from(schema.nutritionGoals)
        .where(eq(schema.nutritionGoals.id, goalId));
      assert.equal(afterLww[0].payload.target_value, 2400);

      // Archiving the Goal (a tombstone via deleted_at) round-trips.
      const deletedAt = "2025-06-30T13:00:00.000Z";
      const archivePush = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "nutrition_goals",
        changes: [
          {
            id: goalId,
            payload: {
              ...goalPayload(goalId, "energy", 2400, deletedAt),
              deleted_at: deletedAt
            },
            updatedAt: deletedAt,
            deletedAt
          }
        ]
      });
      assert.equal(archivePush.status, 200);
      assert.deepEqual((await archivePush.json()).accepted, [goalId]);
      const archivedGoal = await serverApp.database.db
        .select()
        .from(schema.nutritionGoals)
        .where(eq(schema.nutritionGoals.id, goalId));
      assert.notEqual(archivedGoal[0].deletedAt, null);

      const pulledAfterArchive = await pullAll(serverApp.app, userA.sessionToken);
      const pulledArchivedGoal = pulledAfterArchive.find(
        (change) => change.entity === "nutrition_goals" && change.id === goalId
      );
      assert.ok(pulledArchivedGoal, "archived goal should round-trip");
      assert.notEqual(pulledArchivedGoal.deletedAt, null);
    } finally {
      await serverApp.database.close();
    }
  }
);

function goalPayload(id, nutrientId, targetValue, updatedAt) {
  return {
    id,
    nutrient_id: nutrientId,
    target_value: targetValue,
    target_entered: String(targetValue),
    unit: "kilocalorie",
    updated_at: updatedAt,
    deleted_at: null
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
    name: "Nutrition Goals Lifecycle Sync User",
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
