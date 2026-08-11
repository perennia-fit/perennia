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
  "User Food and Meal Type round-trip as LWW opaque rows, with tenant " +
    "isolation and archive (deletedAt) round-trip",
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
      const foodId = randomUUID();
      const mealTypeId = randomUUID();
      // Past timestamps so the server never clamps them to its wall-clock
      // serverClock (MAX_FUTURE_CLOCK_SKEW_MS); relative LWW ordering stays
      // honest regardless of when the test runs.
      const updatedAt = "2025-06-30T08:00:00.000Z";

      // Device A pushes a User Food and a Meal Type.
      const pushFood = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "foods",
        changes: [
          {
            id: foodId,
            payload: foodPayload(foodId, updatedAt),
            updatedAt,
            deletedAt: null
          }
        ]
      });
      assert.equal(pushFood.status, 200);
      assert.deepEqual((await pushFood.json()).accepted, [foodId]);

      const pushMealType = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "meal_types",
        changes: [
          {
            id: mealTypeId,
            payload: mealTypePayload(mealTypeId, updatedAt),
            updatedAt,
            deletedAt: null
          }
        ]
      });
      assert.equal(pushMealType.status, 200);
      assert.deepEqual((await pushMealType.json()).accepted, [mealTypeId]);

      // TENANT ISOLATION: user B cannot overwrite user A's Food keyed by the
      // same client PK. The push reports accepted (idempotent no-op) but the
      // stored row keeps user A's payload + ownership.
      const crossUserUpdatedAt = "2025-06-30T10:00:00.000Z";
      const crossPush = await syncPush(serverApp.app, userB.sessionToken, {
        deviceId: "device-b",
        entity: "foods",
        changes: [
          {
            id: foodId,
            payload: {
              ...foodPayload(foodId, crossUserUpdatedAt),
              name: "Hijacked"
            },
            updatedAt: crossUserUpdatedAt,
            deletedAt: null
          }
        ]
      });
      assert.equal(crossPush.status, 200);

      const storedFood = await serverApp.database.db
        .select()
        .from(schema.foods)
        .where(eq(schema.foods.id, foodId));
      assert.equal(storedFood.length, 1);
      assert.equal(storedFood[0].userId, userA.userId);
      assert.equal(storedFood[0].payload.name, "Chicken Breast");

      // TENANT ISOLATION on the Meal Type too.
      const crossMealTypePush = await syncPush(
        serverApp.app,
        userB.sessionToken,
        {
          deviceId: "device-b",
          entity: "meal_types",
          changes: [
            {
              id: mealTypeId,
              payload: {
                ...mealTypePayload(mealTypeId, crossUserUpdatedAt),
                name: "Hijacked"
              },
              updatedAt: crossUserUpdatedAt,
              deletedAt: null
            }
          ]
        }
      );
      assert.equal(crossMealTypePush.status, 200);
      const storedMealType = await serverApp.database.db
        .select()
        .from(schema.mealTypes)
        .where(eq(schema.mealTypes.id, mealTypeId));
      assert.equal(storedMealType.length, 1);
      assert.equal(storedMealType[0].userId, userA.userId);
      assert.equal(storedMealType[0].payload.name, "Second Breakfast");

      // Device B (same user A account, different device) pulls its own rows;
      // both the Food and Meal Type round-trip.
      const pulled = await pullAll(serverApp.app, userA.sessionToken);
      const pulledFood = pulled.find(
        (change) => change.entity === "foods" && change.id === foodId
      );
      const pulledMealType = pulled.find(
        (change) => change.entity === "meal_types" && change.id === mealTypeId
      );
      assert.ok(pulledFood, "food should round-trip");
      assert.ok(pulledMealType, "meal type should round-trip");
      assert.equal(pulledFood.payload.name, "Chicken Breast");
      assert.equal(pulledMealType.payload.name, "Second Breakfast");
      assert.equal(pulledFood.deletedAt, null);

      // User B pulls and sees NEITHER row — strict per-user scoping on read.
      const userBPulled = await pullAll(serverApp.app, userB.sessionToken);
      assert.equal(
        userBPulled.filter(
          (change) => change.id === foodId || change.id === mealTypeId
        ).length,
        0
      );

      // A newer Food edit wins LWW; an older replay loses.
      const newerUpdatedAt = "2025-06-30T12:00:00.000Z";
      const newerPush = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "foods",
        changes: [
          {
            id: foodId,
            payload: {
              ...foodPayload(foodId, newerUpdatedAt),
              name: "Grilled Chicken Breast"
            },
            updatedAt: newerUpdatedAt,
            deletedAt: null
          }
        ]
      });
      assert.equal(newerPush.status, 200);
      const stalePush = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "foods",
        changes: [
          {
            id: foodId,
            payload: {
              ...foodPayload(foodId, "2025-06-30T09:00:00.000Z"),
              name: "Stale Name"
            },
            updatedAt: "2025-06-30T09:00:00.000Z",
            deletedAt: null
          }
        ]
      });
      assert.equal(stalePush.status, 200);
      const afterLww = await serverApp.database.db
        .select()
        .from(schema.foods)
        .where(eq(schema.foods.id, foodId));
      assert.equal(afterLww[0].payload.name, "Grilled Chicken Breast");

      // Archiving the Food (a tombstone via deleted_at) round-trips without
      // cascading to the Meal Type row.
      const deletedAt = "2025-06-30T13:00:00.000Z";
      const archivePush = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "foods",
        changes: [
          {
            id: foodId,
            payload: {
              ...foodPayload(foodId, deletedAt),
              deleted_at: deletedAt
            },
            updatedAt: deletedAt,
            deletedAt
          }
        ]
      });
      assert.equal(archivePush.status, 200);
      assert.deepEqual((await archivePush.json()).accepted, [foodId]);
      const archivedFood = await serverApp.database.db
        .select()
        .from(schema.foods)
        .where(eq(schema.foods.id, foodId));
      assert.notEqual(archivedFood[0].deletedAt, null);
      const mealTypeStillLive = await serverApp.database.db
        .select()
        .from(schema.mealTypes)
        .where(eq(schema.mealTypes.id, mealTypeId));
      assert.equal(mealTypeStillLive.length, 1);
      assert.equal(mealTypeStillLive[0].deletedAt, null);

      // Archived Food round-trips its tombstone on the next pull too (device
      // B -> server -> device A confirmation of the archive).
      const pulledAfterArchive = await pullAll(serverApp.app, userA.sessionToken);
      const pulledArchivedFood = pulledAfterArchive.find(
        (change) => change.entity === "foods" && change.id === foodId
      );
      assert.ok(pulledArchivedFood, "archived food should round-trip");
      assert.notEqual(pulledArchivedFood.deletedAt, null);
    } finally {
      await serverApp.database.close();
    }
  }
);

function foodPayload(id, updatedAt) {
  return {
    id,
    name: "Chicken Breast",
    food_source: "user",
    nutrient_values_json: JSON.stringify({ energy_kcal: { entered: "165" } }),
    is_liquid: false,
    serving_label: "serving",
    serving_size: 100,
    package_size: null,
    recipe_ingredients_json: null,
    recipe_serving_count: null,
    updated_at: updatedAt,
    deleted_at: null
  };
}

function mealTypePayload(id, updatedAt) {
  return {
    id,
    name: "Second Breakfast",
    sort_order: 4,
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
    name: "Foods/Meal Types Lifecycle Sync User",
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
