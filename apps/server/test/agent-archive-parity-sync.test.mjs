import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { createMigratedServerApp, schema } from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error(
    "DATABASE_URL must be set for server Postgres integration tests."
  );
}

const skip = databaseUrl ? false : "DATABASE_URL is not set.";

test(
  "an agent-archived Logged Set round-trips to a device sync pull as a tombstone",
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
      const user = await createSignedInUser(serverApp, "Archive Parity Workout User");
      const agentSecret = await createAgentKey(serverApp, user.sessionToken);
      const setId = randomUUID();

      const createResponse = await postAgentWorkoutBatch(serverApp.app, agentSecret, {
        idempotencyKey: `agent-workout-archive-create-${randomUUID()}`,
        workout: {
          id: randomUUID(),
          startedAt: "2026-06-24T05:00:00.000Z",
          endedAt: null,
          timezone: "Australia/Brisbane",
          comment: null
        },
        sets: [
          {
            id: setId,
            exerciseName: "Deadlift",
            position: 0,
            values: {
              load: { entered: "100", unit: "kilogram" },
              reps: { entered: "5", unit: "repetition" }
            },
            updatedAt: "2026-06-24T05:00:00.000Z"
          }
        ]
      });
      assert.equal(createResponse.status, 200);

      // The device pulls the live (non-tombstoned) row first.
      const pulledBeforeArchive = await pullAll(serverApp.app, user.sessionToken);
      const liveSet = pulledBeforeArchive.find(
        (change) => change.entity === "logged_sets" && change.id === setId
      );
      assert.ok(liveSet, "created set should round-trip to the device");
      assert.equal(liveSet.deletedAt, null);

      // Archive via the agent batch-write path (a second batch with deletedAt set).
      const archivedAt = "2026-06-24T06:00:00.000Z";
      const archiveResponse = await postAgentWorkoutBatch(serverApp.app, agentSecret, {
        idempotencyKey: `agent-workout-archive-delete-${randomUUID()}`,
        workout: {
          id: randomUUID(),
          startedAt: "2026-06-24T05:00:00.000Z",
          endedAt: null,
          timezone: "Australia/Brisbane",
          comment: null
        },
        sets: [
          {
            id: setId,
            exerciseName: "Deadlift",
            position: 0,
            values: {
              load: { entered: "100", unit: "kilogram" },
              reps: { entered: "5", unit: "repetition" }
            },
            updatedAt: archivedAt,
            deletedAt: archivedAt
          }
        ]
      });
      assert.equal(archiveResponse.status, 200);

      // The device's next pull sees the row as a tombstone.
      const pulledAfterArchive = await pullAll(serverApp.app, user.sessionToken);
      const tombstoned = pulledAfterArchive.find(
        (change) => change.entity === "logged_sets" && change.id === setId
      );
      assert.ok(tombstoned, "archived set should still round-trip (as a tombstone)");
      assert.notEqual(tombstoned.deletedAt, null);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "an agent-archived Meal and Food Entry round-trip to a device sync pull as tombstones",
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
      const user = await createSignedInUser(serverApp, "Archive Parity Meal User");
      const agentSecret = await createAgentKey(serverApp, user.sessionToken);
      const mealId = randomUUID();
      const entryId = randomUUID();

      const createResponse = await postAgentMealBatch(serverApp.app, agentSecret, {
        idempotencyKey: `agent-meal-archive-create-${randomUUID()}`,
        meal: {
          id: mealId,
          mealType: "Lunch",
          startedAt: "2026-06-24T05:00:00.000Z",
          endedAt: null,
          timezone: "Australia/Brisbane",
          localDate: "2026-06-24"
        },
        entries: [
          {
            id: entryId,
            position: 0,
            name: "Protein shake",
            nutrients: {
              energy: { status: "complete", value: 160, entered: "160", unit: "kilocalorie" },
              protein: { status: "complete", value: 30, entered: "30", unit: "gram" }
            },
            isLiquid: true,
            foodId: null,
            foodSource: null,
            portion: null,
            updatedAt: "2026-06-24T05:00:00.000Z"
          }
        ]
      });
      assert.equal(createResponse.status, 200);

      const archivedAt = "2026-06-24T06:00:00.000Z";
      const archiveResponse = await postAgentMealBatch(serverApp.app, agentSecret, {
        idempotencyKey: `agent-meal-archive-delete-${randomUUID()}`,
        meal: {
          id: mealId,
          mealType: "Lunch",
          startedAt: "2026-06-24T05:00:00.000Z",
          endedAt: null,
          timezone: "Australia/Brisbane",
          localDate: "2026-06-24",
          deletedAt: archivedAt
        },
        entries: [
          {
            id: entryId,
            position: 0,
            name: "Protein shake",
            nutrients: {
              energy: { status: "complete", value: 160, entered: "160", unit: "kilocalorie" },
              protein: { status: "complete", value: 30, entered: "30", unit: "gram" }
            },
            isLiquid: true,
            foodId: null,
            foodSource: null,
            portion: null,
            updatedAt: archivedAt,
            deletedAt: archivedAt
          }
        ]
      });
      assert.equal(archiveResponse.status, 200);

      const pulled = await pullAll(serverApp.app, user.sessionToken);
      const tombstonedMeal = pulled.find(
        (change) => change.entity === "meals" && change.id === mealId
      );
      const tombstonedEntry = pulled.find(
        (change) => change.entity === "food_entries" && change.id === entryId
      );
      assert.ok(tombstonedMeal, "archived meal should round-trip (as a tombstone)");
      assert.ok(tombstonedEntry, "archived food entry should round-trip (as a tombstone)");
      assert.notEqual(tombstonedMeal.deletedAt, null);
      assert.notEqual(tombstonedEntry.deletedAt, null);
    } finally {
      await serverApp.database.close();
    }
  }
);

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

async function createSignedInUser(serverApp, name) {
  const userId = `user-${randomUUID()}`;
  const sessionToken = `session-${randomUUID()}`;

  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name,
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

function postAgentWorkoutBatch(app, agentSecret, body) {
  return app.request("/agent/workouts/batch-write", {
    method: "POST",
    headers: {
      authorization: `Bearer ${agentSecret}`,
      "content-type": "application/json"
    },
    body: JSON.stringify(body)
  });
}

function postAgentMealBatch(app, agentSecret, body) {
  return app.request("/agent/meals/batch-write", {
    method: "POST",
    headers: {
      authorization: `Bearer ${agentSecret}`,
      "content-type": "application/json"
    },
    body: JSON.stringify(body)
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
