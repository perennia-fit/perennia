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
  "ExerciseCategory and Exercise round-trip as LWW opaque rows, with " +
    "tenant isolation and archive (deletedAt) round-trip",
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
      const categoryId = randomUUID();
      const exerciseId = randomUUID();
      // Past timestamps so the server never clamps them to its wall-clock
      // serverClock (MAX_FUTURE_CLOCK_SKEW_MS); relative LWW ordering stays
      // honest regardless of when the test runs.
      const updatedAt = "2025-06-30T08:00:00.000Z";

      // Device A pushes a user ExerciseCategory and a user Exercise.
      const pushCategory = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "exercise_categories",
        changes: [
          {
            id: categoryId,
            payload: categoryPayload(categoryId, updatedAt),
            updatedAt,
            deletedAt: null
          }
        ]
      });
      assert.equal(pushCategory.status, 200);
      assert.deepEqual((await pushCategory.json()).accepted, [categoryId]);

      const pushExercise = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "exercises",
        changes: [
          {
            id: exerciseId,
            payload: exercisePayload(exerciseId, categoryId, updatedAt),
            updatedAt,
            deletedAt: null
          }
        ]
      });
      assert.equal(pushExercise.status, 200);
      assert.deepEqual((await pushExercise.json()).accepted, [exerciseId]);

      // TENANT ISOLATION: user B cannot overwrite user A's Exercise keyed by
      // the same client PK. The push reports accepted (idempotent no-op) but
      // the stored row keeps user A's payload + ownership.
      const crossUserUpdatedAt = "2025-06-30T10:00:00.000Z";
      const crossPush = await syncPush(serverApp.app, userB.sessionToken, {
        deviceId: "device-b",
        entity: "exercises",
        changes: [
          {
            id: exerciseId,
            payload: {
              ...exercisePayload(exerciseId, categoryId, crossUserUpdatedAt),
              name: "Hijacked"
            },
            updatedAt: crossUserUpdatedAt,
            deletedAt: null
          }
        ]
      });
      assert.equal(crossPush.status, 200);

      const storedExercise = await serverApp.database.db
        .select()
        .from(schema.exercises)
        .where(eq(schema.exercises.id, exerciseId));
      assert.equal(storedExercise.length, 1);
      assert.equal(storedExercise[0].userId, userA.userId);
      assert.equal(storedExercise[0].payload.name, "Barbell Row");

      // TENANT ISOLATION on the category too.
      const crossCategoryPush = await syncPush(
        serverApp.app,
        userB.sessionToken,
        {
          deviceId: "device-b",
          entity: "exercise_categories",
          changes: [
            {
              id: categoryId,
              payload: {
                ...categoryPayload(categoryId, crossUserUpdatedAt),
                name: "Hijacked"
              },
              updatedAt: crossUserUpdatedAt,
              deletedAt: null
            }
          ]
        }
      );
      assert.equal(crossCategoryPush.status, 200);
      const storedCategory = await serverApp.database.db
        .select()
        .from(schema.exerciseCategories)
        .where(eq(schema.exerciseCategories.id, categoryId));
      assert.equal(storedCategory.length, 1);
      assert.equal(storedCategory[0].userId, userA.userId);
      assert.equal(storedCategory[0].payload.name, "Back");

      // Device B (same user A account, different device) pulls its own rows;
      // both the ExerciseCategory and Exercise round-trip.
      const pulled = await pullAll(serverApp.app, userA.sessionToken);
      const pulledCategory = pulled.find(
        (change) =>
          change.entity === "exercise_categories" && change.id === categoryId
      );
      const pulledExercise = pulled.find(
        (change) => change.entity === "exercises" && change.id === exerciseId
      );
      assert.ok(pulledCategory, "category should round-trip");
      assert.ok(pulledExercise, "exercise should round-trip");
      assert.equal(pulledCategory.payload.name, "Back");
      assert.equal(pulledExercise.payload.name, "Barbell Row");
      assert.equal(pulledExercise.payload.category_id, categoryId);
      assert.equal(pulledExercise.deletedAt, null);

      // User B pulls and sees NEITHER row — strict per-user scoping on read.
      const userBPulled = await pullAll(serverApp.app, userB.sessionToken);
      assert.equal(
        userBPulled.filter(
          (change) => change.id === exerciseId || change.id === categoryId
        ).length,
        0
      );

      // A newer Exercise edit wins LWW; an older replay loses.
      const newerUpdatedAt = "2025-06-30T12:00:00.000Z";
      const newerPush = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "exercises",
        changes: [
          {
            id: exerciseId,
            payload: {
              ...exercisePayload(exerciseId, categoryId, newerUpdatedAt),
              name: "Pendlay Row"
            },
            updatedAt: newerUpdatedAt,
            deletedAt: null
          }
        ]
      });
      assert.equal(newerPush.status, 200);
      const stalePush = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "exercises",
        changes: [
          {
            id: exerciseId,
            payload: {
              ...exercisePayload(
                exerciseId,
                categoryId,
                "2025-06-30T09:00:00.000Z"
              ),
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
        .from(schema.exercises)
        .where(eq(schema.exercises.id, exerciseId));
      assert.equal(afterLww[0].payload.name, "Pendlay Row");

      // Archiving the Exercise (a tombstone via deleted_at) propagates without
      // cascading to the ExerciseCategory row.
      const deletedAt = "2025-06-30T13:00:00.000Z";
      const archivePush = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "exercises",
        changes: [
          {
            id: exerciseId,
            payload: {
              ...exercisePayload(exerciseId, categoryId, deletedAt),
              deleted_at: deletedAt
            },
            updatedAt: deletedAt,
            deletedAt
          }
        ]
      });
      assert.equal(archivePush.status, 200);
      assert.deepEqual((await archivePush.json()).accepted, [exerciseId]);
      const archivedExercise = await serverApp.database.db
        .select()
        .from(schema.exercises)
        .where(eq(schema.exercises.id, exerciseId));
      assert.notEqual(archivedExercise[0].deletedAt, null);
      const categoryStillLive = await serverApp.database.db
        .select()
        .from(schema.exerciseCategories)
        .where(eq(schema.exerciseCategories.id, categoryId));
      assert.equal(categoryStillLive.length, 1);
      assert.equal(categoryStillLive[0].deletedAt, null);

      // Archived Exercise round-trips its tombstone on the next pull too
      // (device B -> server -> device A confirmation of the archive).
      const pulledAfterArchive = await pullAll(serverApp.app, userA.sessionToken);
      const pulledArchivedExercise = pulledAfterArchive.find(
        (change) => change.entity === "exercises" && change.id === exerciseId
      );
      assert.ok(pulledArchivedExercise, "archived exercise should round-trip");
      assert.notEqual(pulledArchivedExercise.deletedAt, null);
    } finally {
      await serverApp.database.close();
    }
  }
);

function categoryPayload(id, updatedAt) {
  return {
    id,
    name: "Back",
    sort_order: 1,
    color_hex: "#3366CC",
    updated_at: updatedAt,
    deleted_at: null
  };
}

function exercisePayload(id, categoryId, updatedAt) {
  return {
    id,
    library_origin: "user",
    name: "Barbell Row",
    dimension_ids: JSON.stringify(["load", "reps"]),
    default_load_unit: "kilogram",
    load_mode: "added",
    record_profile: "repMax",
    is_favorite: false,
    is_unilateral: false,
    uses_rpe: false,
    category_id: categoryId,
    equipment_ids: JSON.stringify([]),
    notes: null,
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
    name: "Exercises Lifecycle Sync User",
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
