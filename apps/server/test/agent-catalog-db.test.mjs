import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { createMigratedServerApp, schema } from "../src/index.ts";
import { CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS } from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error(
    "DATABASE_URL must be set for server Postgres integration tests."
  );
}

const skip = databaseUrl ? false : "DATABASE_URL is not set.";

test(
  "the DB-backed AgentCatalogStore serves the previously-503 agent catalog " +
    "paths from synced user rows merged over the bundled Platform Library",
  { skip },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: {
        baseUrl: "http://localhost",
        secret: "test-secret-at-least-thirty-two-characters",
        emailSender: null
      },
      rateLimit: false
    });

    try {
      const userA = await createSignedInUser(serverApp);
      const userB = await createSignedInUser(serverApp);
      const agentSecretA = await createAgentKey(serverApp, userA.sessionToken);
      const agentSecretB = await createAgentKey(serverApp, userB.sessionToken);

      const categoryId = randomUUID();
      const userSquatId = randomUUID();
      const userCurlId = randomUUID();
      const updatedAt = "2025-06-30T08:00:00.000Z";

      // User A syncs a Category, a User Library "Barbell Squat" (which shadows the
      // Platform "Barbell Squat" by name), and an archived "Curl".
      await syncPushOk(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "exercise_categories",
        changes: [
          {
            id: categoryId,
            payload: categoryPayload(categoryId, "Strength", updatedAt),
            updatedAt,
            deletedAt: null
          }
        ]
      });
      await syncPushOk(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "exercises",
        changes: [
          {
            id: userSquatId,
            payload: exercisePayload({
              id: userSquatId,
              name: "Barbell Squat",
              categoryId,
              favorite: true,
              updatedAt
            }),
            updatedAt,
            deletedAt: null
          }
        ]
      });
      const curlUpdatedAt = "2025-06-30T09:00:00.000Z";
      await syncPushOk(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "exercises",
        changes: [
          {
            id: userCurlId,
            payload: exercisePayload({
              id: userCurlId,
              name: "Wrist Curl Machine",
              categoryId,
              updatedAt: curlUpdatedAt,
              deletedAt: curlUpdatedAt
            }),
            updatedAt: curlUpdatedAt,
            deletedAt: curlUpdatedAt
          }
        ]
      });

      // resolve: a Platform exercise the user has not customized resolves to the
      // Platform Library row (matched, library platform).
      const platformResolve = await getAgent(
        serverApp.app,
        agentSecretA,
        "/agent/exercises/resolve?name=Deadlift"
      );
      assert.equal(platformResolve.status, 200);
      const platformResolveBody = await platformResolve.json();
      assert.equal(platformResolveBody.resolution, "matched");
      assert.equal(platformResolveBody.matchedExercise.library, "platform");
      assert.equal(platformResolveBody.matchedExercise.name, "Deadlift");
      assert.deepEqual(platformResolveBody.matchedExercise.dimensions, [
        "load",
        "reps"
      ]);
      assert.equal(
        platformResolveBody.matchedExercise.recordProfile,
        "repMax"
      );

      // resolve: a User Library customization wins over the shadowed Platform
      // row, and carries the shadowed platform id.
      const userResolve = await getAgent(
        serverApp.app,
        agentSecretA,
        "/agent/exercises/resolve?name=Barbell%20Squat"
      );
      assert.equal(userResolve.status, 200);
      const userResolveBody = await userResolve.json();
      assert.equal(userResolveBody.resolution, "matched");
      assert.equal(userResolveBody.matchedExercise.id, userSquatId);
      assert.equal(userResolveBody.matchedExercise.library, "user");
      assert.equal(userResolveBody.matchedExercise.favorite, true);
      assert.equal(
        typeof userResolveBody.matchedExercise.shadowedPlatformExerciseId,
        "string"
      );

      // list: the shadowed Platform "Barbell Squat" is hidden; the user row shows.
      const listResponse = await getAgent(
        serverApp.app,
        agentSecretA,
        "/agent/exercises?search=Barbell%20Squat&limit=100"
      );
      assert.equal(listResponse.status, 200);
      const listBody = await listResponse.json();
      const backSquats = listBody.exercises.filter(
        (exercise) => exercise.name === "Barbell Squat"
      );
      assert.equal(backSquats.length, 1);
      assert.equal(backSquats[0].id, userSquatId);
      assert.equal(backSquats[0].library, "user");

      // list: activeOnly=false surfaces the archived user exercise.
      const archivedList = await getAgent(
        serverApp.app,
        agentSecretA,
        "/agent/exercises?search=Wrist%20Curl%20Machine&activeOnly=false"
      );
      assert.equal(archivedList.status, 200);
      const archivedBody = await archivedList.json();
      assert.deepEqual(
        archivedBody.exercises.map((exercise) => exercise.id),
        [userCurlId]
      );
      const activeOnly = await getAgent(
        serverApp.app,
        agentSecretA,
        "/agent/exercises?search=Wrist%20Curl%20Machine"
      );
      assert.deepEqual(
        (await activeOnly.json()).exercises.map((exercise) => exercise.id),
        []
      );

      // getById on a Platform exercise via the analytics read path (previously
      // 503) now resolves the exercise and returns analytics for zero sets.
      const analytics = await getAgent(
        serverApp.app,
        agentSecretA,
        `/agent/analytics/exercises/${CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning}`
      );
      assert.equal(analytics.status, 200);
      const analyticsBody = await analytics.json();
      assert.equal(
        analyticsBody.exercise.id,
        CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning
      );
      assert.equal(analyticsBody.exercise.library, "platform");

      // batch-write (previously 503): resolves a Platform name and a User name
      // and persists Logged Sets against the resolved exercise ids.
      const batchKey = `agent-catalog-batch-${randomUUID()}`;
      const platformSetId = randomUUID();
      const userSetId = randomUUID();
      const batchResponse = await serverApp.app.request(
        "/agent/workouts/batch-write",
        {
          method: "POST",
          headers: {
            authorization: `Bearer ${agentSecretA}`,
            "content-type": "application/json"
          },
          body: JSON.stringify({
            idempotencyKey: batchKey,
            workout: {
              id: randomUUID(),
              startedAt: "2026-06-24T05:00:00.000Z",
              endedAt: null,
              timezone: "Australia/Brisbane",
              comment: null
            },
            sets: [
              {
                id: platformSetId,
                exerciseName: "Deadlift",
                position: 0,
                comment: null,
                values: {
                  load: { entered: "140", unit: "kilogram" },
                  reps: { entered: "5", unit: "repetition" }
                }
              },
              {
                id: userSetId,
                exerciseName: "Barbell Squat",
                position: 1,
                comment: null,
                values: {
                  load: { entered: "120", unit: "kilogram" },
                  reps: { entered: "5", unit: "repetition" }
                }
              }
            ]
          })
        }
      );
      assert.equal(batchResponse.status, 200);
      const batchBody = await batchResponse.json();
      assert.equal(batchBody.accepted, true);
      assert.equal(batchBody.sets.length, 2);
      // The user's "Barbell Squat" resolved to the User Library row, not Platform.
      const userResultSet = batchBody.sets.find(
        (set) => set.requestedExerciseName === "Barbell Squat"
      );
      assert.equal(userResultSet.exerciseId, userSquatId);

      // TENANT ISOLATION: user B never sees user A's rows. Their catalog is the
      // pure Platform Library, so "Barbell Squat" resolves to the Platform row and
      // user A's archived "Wrist Curl Machine" is invisible.
      const userBResolve = await getAgent(
        serverApp.app,
        agentSecretB,
        "/agent/exercises/resolve?name=Barbell%20Squat"
      );
      const userBResolveBody = await userBResolve.json();
      assert.equal(userBResolveBody.resolution, "matched");
      assert.equal(userBResolveBody.matchedExercise.library, "platform");
      assert.notEqual(userBResolveBody.matchedExercise.id, userSquatId);

      const userBList = await getAgent(
        serverApp.app,
        agentSecretB,
        "/agent/exercises?search=Wrist%20Curl%20Machine&activeOnly=false&limit=100"
      );
      assert.deepEqual(
        (await userBList.json()).exercises.map((exercise) => exercise.id),
        []
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

function categoryPayload(id, name, updatedAt) {
  return {
    id,
    name,
    sort_order: 1,
    color_hex: "#3366CC",
    updated_at: updatedAt,
    deleted_at: null
  };
}

function exercisePayload({
  id,
  name,
  categoryId,
  favorite = false,
  updatedAt,
  deletedAt = null
}) {
  return {
    id,
    library_origin: "user",
    name,
    dimension_ids: JSON.stringify(["load", "reps"]),
    default_load_unit: "kilogram",
    load_mode: "added",
    record_profile: "repMax",
    is_favorite: favorite,
    is_unilateral: false,
    uses_rpe: false,
    category_id: categoryId,
    equipment_ids: JSON.stringify(["barbell"]),
    notes: null,
    updated_at: updatedAt,
    deleted_at: deletedAt
  };
}

async function createAgentKey(serverApp, sessionToken) {
  const response = await serverApp.app.request("/agent/api-keys", {
    method: "POST",
    headers: {
      authorization: `Bearer ${sessionToken}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({ name: "Garage coach" })
  });
  assert.equal(response.status, 201);
  const body = await response.json();
  return body.secret;
}

function getAgent(app, agentSecret, path) {
  return app.request(path, {
    headers: { authorization: `Bearer ${agentSecret}` }
  });
}

async function syncPushOk(app, sessionToken, body) {
  const response = await app.request("/sync/push", {
    method: "POST",
    headers: {
      authorization: `Bearer ${sessionToken}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({ protocolVersion: 1, ...body })
  });
  assert.equal(response.status, 200);
  return response;
}

async function createSignedInUser(serverApp) {
  const userId = `user-${randomUUID()}`;
  const sessionToken = `session-${randomUUID()}`;

  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: "Agent Catalog DB User",
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
