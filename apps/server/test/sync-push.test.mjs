import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  createApp,
  createDrizzleIntegrationCredentialStore,
  createMigratedServerApp,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

test("sync push accepts one logged set through the route contract", async () => {
  const pushedBatches = [];
  const app = createApp({
    logger: { info() {}, error() {} },
    syncStore: {
      async verifyBearerToken(token) {
        return token === "session-token" ? { userId: "user-1" } : null;
      },
      async pushLoggedSets(batch) {
        pushedBatches.push(batch);
        return {
          accepted: batch.changes.map((change) => change.id),
          serverClock: "2026-06-22T08:00:01.000Z",
          applied: batch.changes.map((change) => ({
            id: change.id,
            updatedAt: "2026-06-22T08:00:00.000Z",
            deviceId: batch.deviceId
          }))
        };
      }
    }
  });
  const setId = "018f6a90-6d7f-7d63-bfc1-6f1025e0c001";

  const response = await app.request("/sync/push", {
    method: "POST",
    headers: {
      authorization: "Bearer session-token",
      "content-type": "application/json",
      "x-correlation-id": "corr-sync-push"
    },
    body: JSON.stringify({
      protocolVersion: 1,
      deviceId: "device-a",
      entity: "logged_sets",
      changes: [
        {
          id: setId,
          payload: {
            id: setId,
            updated_at: "2026-06-22T08:00:00.000Z",
            deleted_at: null
          },
          updatedAt: "2026-06-22T08:00:00.000Z",
          deletedAt: null
        }
      ]
    })
  });

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    protocolVersion: 1,
    accepted: [setId],
    serverClock: "2026-06-22T08:00:01.000Z",
    applied: [
      {
        id: setId,
        updatedAt: "2026-06-22T08:00:00.000Z",
        deviceId: "device-a"
      }
    ]
  });
  assert.equal(pushedBatches.length, 1);
  assert.equal(pushedBatches[0].userId, "user-1");
  assert.equal(pushedBatches[0].deviceId, "device-a");
  assert.equal(pushedBatches[0].correlationId, "corr-sync-push");
  assert.equal(pushedBatches[0].changes[0].id, setId);
});

test("sync push accepts Open Food Facts Food Entry snapshots through the route contract", async () => {
  const pushedBatches = [];
  const app = createApp({
    logger: { info() {}, error() {} },
    syncStore: {
      async verifyBearerToken(token) {
        return token === "session-token" ? { userId: "user-1" } : null;
      },
      async pushFoodEntries(batch) {
        pushedBatches.push(batch);
        return {
          accepted: batch.changes.map((change) => change.id),
          serverClock: "2026-06-27T08:00:01.000Z",
          applied: batch.changes.map((change) => ({
            id: change.id,
            updatedAt: change.updatedAt,
            deviceId: batch.deviceId
          }))
        };
      }
    }
  });
  const entryId = "018f6a90-6d7f-7d63-bfc1-6f1025e0f001";

  const response = await app.request("/sync/push", {
    method: "POST",
    headers: {
      authorization: "Bearer session-token",
      "content-type": "application/json",
      "x-correlation-id": "corr-food-entry"
    },
    body: JSON.stringify({
      protocolVersion: 1,
      deviceId: "device-a",
      entity: "food_entries",
      changes: [
        {
          id: entryId,
          payload: {
            id: entryId,
            meal_id: "meal-1",
            entry_kind: "food",
            position: 0,
            name: "Original branded bar",
            nutrient_values_json: "{}",
            food_id: "3017620422003",
            portion_json: "{}",
            food_source: "openFoodFacts",
            is_liquid: false,
            serving_label: "serving",
            serving_size: 45,
            package_size: 60,
            updated_at: "2026-06-27T08:00:00.000Z",
            deleted_at: null
          },
          updatedAt: "2026-06-27T08:00:00.000Z",
          deletedAt: null
        }
      ]
    })
  });

  assert.equal(response.status, 200);
  assert.equal(pushedBatches.length, 1);
  assert.equal(pushedBatches[0].userId, "user-1");
  assert.equal(pushedBatches[0].deviceId, "device-a");
  assert.equal(pushedBatches[0].correlationId, "corr-food-entry");
  assert.equal(pushedBatches[0].changes[0].payload.food_source, "openFoodFacts");
  assert.deepEqual(await response.json(), {
    protocolVersion: 1,
    accepted: [entryId],
    serverClock: "2026-06-27T08:00:01.000Z",
    applied: [
      {
        id: entryId,
        updatedAt: "2026-06-27T08:00:00.000Z",
        deviceId: "device-a"
      }
    ]
  });
});

test("sync pull returns one cursor window through the route contract", async () => {
  const pulledBatches = [];
  const setId = "018f6a90-6d7f-7d63-bfc1-6f1025e0c001";
  const app = createApp({
    logger: { info() {}, error() {} },
    syncStore: {
      async verifyBearerToken(token) {
        return token === "session-token" ? { userId: "user-1" } : null;
      },
      async pullChanges(batch) {
        pulledBatches.push(batch);
        return {
          nextCursor: "2026-06-22T08:00:00.000Z|set-1",
          changes: [
            {
              entity: "logged_sets",
              id: setId,
              deviceId: "device-a",
              payload: {
                id: setId,
                updated_at: "2026-06-22T08:00:00.000Z",
                deleted_at: null
              },
              updatedAt: "2026-06-22T08:00:00.000Z",
              deletedAt: null
            }
          ],
          serverClock: "2026-06-22T08:00:01.000Z"
        };
      }
    }
  });

  const response = await app.request("/sync/pull", {
    method: "POST",
    headers: {
      authorization: "Bearer session-token",
      "content-type": "application/json",
      "x-correlation-id": "corr-sync-pull"
    },
    body: JSON.stringify({
      protocolVersion: 1,
      cursor: null,
      limit: 1
    })
  });

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    protocolVersion: 1,
    fullResyncRequired: false,
    nextCursor: "2026-06-22T08:00:00.000Z|set-1",
    changes: [
      {
        entity: "logged_sets",
        id: setId,
        deviceId: "device-a",
        payload: {
          id: setId,
          updated_at: "2026-06-22T08:00:00.000Z",
          deleted_at: null
        },
        updatedAt: "2026-06-22T08:00:00.000Z",
        deletedAt: null
      }
    ],
    serverClock: "2026-06-22T08:00:01.000Z"
  });
  assert.equal(pulledBatches.length, 1);
  assert.equal(pulledBatches[0].userId, "user-1");
  assert.equal(pulledBatches[0].correlationId, "corr-sync-pull");
  assert.equal(pulledBatches[0].cursor, null);
  assert.equal(pulledBatches[0].limit, 1);
  assert.equal(pulledBatches[0].mode, "delta");
});

test(
  "sync push persists one logged set for a signed-in device",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const { userId, sessionToken } = await createSignedInUser(serverApp);
    const setId = randomUUID();
    const activityLogId = randomUUID();
    const updatedAt = "2026-06-22T08:00:00.000Z";
    const afterImage = {
      id: setId,
      workout_id: "018f6a90-6d7f-7d63-bfc1-6f1025e0c010",
      exercise_id: "018f6a90-6d7f-7d63-bfc1-6f1025e0c020",
      position: 0,
      reps_value: 5,
      reps_unit: "rep",
      reps_entered: "5",
      updated_at: updatedAt,
      deleted_at: null
    };

    try {
      const response = await serverApp.app.request("/sync/push", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          deviceId: "device-a",
          entity: "logged_sets",
          changes: [
            {
              id: setId,
              payload: afterImage,
              updatedAt,
              deletedAt: null,
              activityLogId,
              actor: "app",
              batchId: "batch-1",
              beforeImage: null,
              afterImage,
              occurredAt: updatedAt
            }
          ]
        })
      });

      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.protocolVersion, 1);
      assert.deepEqual(body.accepted, [setId]);
      assert.equal(typeof body.serverClock, "string");
      assert.deepEqual(body.applied, [
        {
          id: setId,
          updatedAt,
          deviceId: "device-a"
        }
      ]);

      const rows = await serverApp.database.sql`
        select id, user_id, device_id, payload, updated_at, deleted_at
        from logged_sets
        where id = ${setId}
      `;
      assert.equal(rows.length, 1);
      assert.equal(rows[0].id, setId);
      assert.equal(rows[0].user_id, userId);
      assert.equal(rows[0].device_id, "device-a");
      assert.equal(rows[0].payload.reps_entered, "5");
      assert.equal(new Date(rows[0].updated_at).toISOString(), updatedAt);
      assert.equal(rows[0].deleted_at, null);

      const activityRows = await serverApp.database.sql`
        select id, user_id, actor, batch_id, entity_table, entity_id,
          before_image, after_image, occurred_at
        from activity_log
        where id = ${activityLogId}
      `;
      assert.equal(activityRows.length, 1);
      assert.equal(activityRows[0].id, activityLogId);
      assert.equal(activityRows[0].user_id, userId);
      assert.equal(activityRows[0].actor, "app");
      assert.equal(activityRows[0].batch_id, "batch-1");
      assert.equal(activityRows[0].entity_table, "logged_sets");
      assert.equal(activityRows[0].entity_id, setId);
      assert.equal(activityRows[0].before_image, null);
      assert.equal(activityRows[0].after_image.reps_entered, "5");
      assert.equal(
        new Date(activityRows[0].occurred_at).toISOString(),
        updatedAt
      );

      const pullResponse = await serverApp.app.request("/sync/pull", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          cursor: null,
          limit: 10
        })
      });
      assert.equal(pullResponse.status, 200);
      const pullBody = await pullResponse.json();
      assert.equal(pullBody.changes.length, 1);
      assert.equal(pullBody.changes[0].activityLogId, activityLogId);
      assert.equal(pullBody.changes[0].actor, "app");
      assert.equal(pullBody.changes[0].batchId, "batch-1");
      assert.equal(pullBody.changes[0].beforeImage, null);
      assert.equal(pullBody.changes[0].afterImage.reps_entered, "5");
      assert.equal(pullBody.changes[0].occurredAt, updatedAt);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "sync push skips logged sets owned by another user",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const owner = await createSignedInUser(serverApp);
    const otherUser = await createSignedInUser(serverApp);
    const setId = randomUUID();
    const originalUpdatedAt = "2026-06-22T08:00:00.000Z";
    const attemptedUpdatedAt = "2026-06-22T09:00:00.000Z";

    try {
      await serverApp.database.db.insert(schema.loggedSets).values({
        id: setId,
        userId: owner.userId,
        deviceId: "owner-device",
        payload: {
          id: setId,
          reps_entered: "5",
          updated_at: originalUpdatedAt,
          deleted_at: null
        },
        updatedAt: new Date(originalUpdatedAt),
        deletedAt: null
      });

      const response = await serverApp.app.request("/sync/push", {
        method: "POST",
        headers: {
          authorization: `Bearer ${otherUser.sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          deviceId: "other-device",
          entity: "logged_sets",
          changes: [
            {
              id: setId,
              payload: {
                id: setId,
                reps_entered: "99",
                updated_at: attemptedUpdatedAt,
                deleted_at: null
              },
              updatedAt: attemptedUpdatedAt,
              deletedAt: null
            }
          ]
        })
      });

      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.protocolVersion, 1);
      assert.deepEqual(body.accepted, []);
      assert.equal(typeof body.serverClock, "string");
      assert.deepEqual(body.applied, []);

      const rows = await serverApp.database.sql`
        select id, user_id, device_id, payload, updated_at, deleted_at
        from logged_sets
        where id = ${setId}
      `;
      assert.equal(rows.length, 1);
      assert.equal(rows[0].id, setId);
      assert.equal(rows[0].user_id, owner.userId);
      assert.equal(rows[0].device_id, "owner-device");
      assert.equal(rows[0].payload.reps_entered, "5");
      assert.equal(
        new Date(rows[0].updated_at).toISOString(),
        originalUpdatedAt
      );
      assert.equal(rows[0].deleted_at, null);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "sync pull skips logged sets owned by another user",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const owner = await createSignedInUser(serverApp);
    const otherUser = await createSignedInUser(serverApp);
    const ownerFirstSetId = randomUUID();
    const ownerSecondSetId = randomUUID();
    const otherFirstSetId = randomUUID();
    const otherSecondSetId = randomUUID();
    const ownerFirstReceivedAt = new Date("2026-06-22T08:00:00.000Z");
    const otherFirstReceivedAt = new Date("2026-06-22T08:00:01.000Z");
    const ownerSecondReceivedAt = new Date("2026-06-22T08:00:02.000Z");
    const otherSecondReceivedAt = new Date("2026-06-22T08:00:03.000Z");

    try {
      await serverApp.database.db.insert(schema.loggedSets).values([
        {
          id: ownerFirstSetId,
          userId: owner.userId,
          deviceId: "owner-device",
          payload: _loggedSetPayload(ownerFirstSetId, "5", ownerFirstReceivedAt),
          updatedAt: ownerFirstReceivedAt,
          deletedAt: null,
          receivedAt: ownerFirstReceivedAt
        },
        {
          id: otherFirstSetId,
          userId: otherUser.userId,
          deviceId: "other-device",
          payload: _loggedSetPayload(otherFirstSetId, "6", otherFirstReceivedAt),
          updatedAt: otherFirstReceivedAt,
          deletedAt: null,
          receivedAt: otherFirstReceivedAt
        },
        {
          id: ownerSecondSetId,
          userId: owner.userId,
          deviceId: "owner-device",
          payload: _loggedSetPayload(ownerSecondSetId, "7", ownerSecondReceivedAt),
          updatedAt: ownerSecondReceivedAt,
          deletedAt: null,
          receivedAt: ownerSecondReceivedAt
        },
        {
          id: otherSecondSetId,
          userId: otherUser.userId,
          deviceId: "other-device",
          payload: _loggedSetPayload(otherSecondSetId, "8", otherSecondReceivedAt),
          updatedAt: otherSecondReceivedAt,
          deletedAt: null,
          receivedAt: otherSecondReceivedAt
        }
      ]);

      const firstResponse = await serverApp.app.request("/sync/pull", {
        method: "POST",
        headers: {
          authorization: `Bearer ${otherUser.sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          cursor: null,
          limit: 1
        })
      });

      assert.equal(firstResponse.status, 200);
      const firstBody = await firstResponse.json();
      assert.deepEqual(
        firstBody.changes.map((change) => change.id),
        [otherFirstSetId]
      );
      assert.equal(typeof firstBody.nextCursor, "string");

      const secondResponse = await serverApp.app.request("/sync/pull", {
        method: "POST",
        headers: {
          authorization: `Bearer ${otherUser.sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          cursor: firstBody.nextCursor,
          limit: 10
        })
      });

      assert.equal(secondResponse.status, 200);
      const secondBody = await secondResponse.json();
      assert.deepEqual(
        secondBody.changes.map((change) => change.id),
        [otherSecondSetId]
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "sync push skips Meals owned by another user",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const owner = await createSignedInUser(serverApp);
    const otherUser = await createSignedInUser(serverApp);
    const mealId = randomUUID();
    const originalUpdatedAt = "2026-06-27T08:00:00.000Z";
    const attemptedUpdatedAt = "2026-06-27T09:00:00.000Z";

    try {
      await serverApp.database.db.insert(schema.meals).values({
        id: mealId,
        userId: owner.userId,
        deviceId: "owner-device",
        payload: _mealPayload(mealId, "Snack", new Date(originalUpdatedAt)),
        updatedAt: new Date(originalUpdatedAt),
        deletedAt: null
      });

      const response = await serverApp.app.request("/sync/push", {
        method: "POST",
        headers: {
          authorization: `Bearer ${otherUser.sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          deviceId: "other-device",
          entity: "meals",
          changes: [
            {
              id: mealId,
              payload: _mealPayload(
                mealId,
                "Dinner",
                new Date(attemptedUpdatedAt)
              ),
              updatedAt: attemptedUpdatedAt,
              deletedAt: null
            }
          ]
        })
      });

      assert.equal(response.status, 200);
      const body = await response.json();
      assert.deepEqual(body.accepted, []);
      assert.deepEqual(body.applied, []);

      const rows = await serverApp.database.sql`
        select id, user_id, device_id, payload, updated_at, deleted_at
        from meals
        where id = ${mealId}
      `;
      assert.equal(rows.length, 1);
      assert.equal(rows[0].id, mealId);
      assert.equal(rows[0].user_id, owner.userId);
      assert.equal(rows[0].device_id, "owner-device");
      assert.equal(rows[0].payload.meal_type, "Snack");
      assert.equal(
        new Date(rows[0].updated_at).toISOString(),
        originalUpdatedAt
      );
      assert.equal(rows[0].deleted_at, null);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "sync push skips Food Entries owned by another user",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const owner = await createSignedInUser(serverApp);
    const otherUser = await createSignedInUser(serverApp);
    const entryId = randomUUID();
    const mealId = randomUUID();
    const originalUpdatedAt = "2026-06-27T08:00:00.000Z";
    const attemptedUpdatedAt = "2026-06-27T09:00:00.000Z";

    try {
      await serverApp.database.db.insert(schema.foodEntries).values({
        id: entryId,
        userId: owner.userId,
        deviceId: "owner-device",
        payload: _foodEntryPayload(
          entryId,
          mealId,
          "Original branded bar",
          new Date(originalUpdatedAt)
        ),
        updatedAt: new Date(originalUpdatedAt),
        deletedAt: null
      });

      const response = await serverApp.app.request("/sync/push", {
        method: "POST",
        headers: {
          authorization: `Bearer ${otherUser.sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          deviceId: "other-device",
          entity: "food_entries",
          changes: [
            {
              id: entryId,
              payload: _foodEntryPayload(
                entryId,
                mealId,
                "Wrong user's branded bar",
                new Date(attemptedUpdatedAt)
              ),
              updatedAt: attemptedUpdatedAt,
              deletedAt: null
            }
          ]
        })
      });

      assert.equal(response.status, 200);
      const body = await response.json();
      assert.deepEqual(body.accepted, []);
      assert.deepEqual(body.applied, []);

      const rows = await serverApp.database.sql`
        select id, user_id, device_id, payload, updated_at, deleted_at
        from food_entries
        where id = ${entryId}
      `;
      assert.equal(rows.length, 1);
      assert.equal(rows[0].id, entryId);
      assert.equal(rows[0].user_id, owner.userId);
      assert.equal(rows[0].device_id, "owner-device");
      assert.equal(rows[0].payload.name, "Original branded bar");
      assert.equal(rows[0].payload.food_source, "openFoodFacts");
      assert.equal(
        new Date(rows[0].updated_at).toISOString(),
        originalUpdatedAt
      );
      assert.equal(rows[0].deleted_at, null);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "sync pull skips Meals and Food Entries owned by another user",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const owner = await createSignedInUser(serverApp);
    const otherUser = await createSignedInUser(serverApp);
    const ownerMealId = randomUUID();
    const ownerEntryId = randomUUID();
    const otherMealId = randomUUID();
    const otherEntryId = randomUUID();
    const ownerMealReceivedAt = new Date("2026-06-27T08:00:00.000Z");
    const otherMealReceivedAt = new Date("2026-06-27T08:00:01.000Z");
    const ownerEntryReceivedAt = new Date("2026-06-27T08:00:02.000Z");
    const otherEntryReceivedAt = new Date("2026-06-27T08:00:03.000Z");

    try {
      await serverApp.database.db.insert(schema.meals).values([
        {
          id: ownerMealId,
          userId: owner.userId,
          deviceId: "owner-device",
          payload: _mealPayload(ownerMealId, "Snack", ownerMealReceivedAt),
          updatedAt: ownerMealReceivedAt,
          deletedAt: null,
          receivedAt: ownerMealReceivedAt
        },
        {
          id: otherMealId,
          userId: otherUser.userId,
          deviceId: "other-device",
          payload: _mealPayload(otherMealId, "Snack", otherMealReceivedAt),
          updatedAt: otherMealReceivedAt,
          deletedAt: null,
          receivedAt: otherMealReceivedAt
        }
      ]);
      await serverApp.database.db.insert(schema.foodEntries).values([
        {
          id: ownerEntryId,
          userId: owner.userId,
          deviceId: "owner-device",
          payload: _foodEntryPayload(
            ownerEntryId,
            ownerMealId,
            "Owner branded bar",
            ownerEntryReceivedAt
          ),
          updatedAt: ownerEntryReceivedAt,
          deletedAt: null,
          receivedAt: ownerEntryReceivedAt
        },
        {
          id: otherEntryId,
          userId: otherUser.userId,
          deviceId: "other-device",
          payload: _foodEntryPayload(
            otherEntryId,
            otherMealId,
            "Other branded bar",
            otherEntryReceivedAt
          ),
          updatedAt: otherEntryReceivedAt,
          deletedAt: null,
          receivedAt: otherEntryReceivedAt
        }
      ]);

      const response = await serverApp.app.request("/sync/pull", {
        method: "POST",
        headers: {
          authorization: `Bearer ${otherUser.sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          cursor: null,
          limit: 10
        })
      });

      assert.equal(response.status, 200);
      const body = await response.json();
      assert.deepEqual(
        body.changes.map((change) => [change.entity, change.id]),
        [
          ["meals", otherMealId],
          ["food_entries", otherEntryId]
        ]
      );
      assert.equal(
        body.changes.some((change) => change.id === ownerMealId),
        false
      );
      assert.equal(
        body.changes.some((change) => change.id === ownerEntryId),
        false
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "sync push resolves conflicts by updated_at then device id",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const { userId, sessionToken } = await createSignedInUser(serverApp);
    const setId = randomUUID();
    const winningTimestamp = new Date("2026-06-22T08:00:00.000Z");
    const staleTimestamp = new Date("2026-06-22T07:59:59.000Z");

    try {
      await serverApp.database.db.insert(schema.loggedSets).values({
        id: setId,
        userId,
        deviceId: "device-a",
        payload: _loggedSetPayload(setId, "5", winningTimestamp),
        updatedAt: winningTimestamp,
        deletedAt: null,
        receivedAt: winningTimestamp
      });

      const staleResponse = await serverApp.app.request("/sync/push", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          deviceId: "device-z",
          entity: "logged_sets",
          changes: [
            {
              id: setId,
              payload: _loggedSetPayload(setId, "99", staleTimestamp),
              updatedAt: staleTimestamp.toISOString(),
              deletedAt: null
            }
          ]
        })
      });

      assert.equal(staleResponse.status, 200);
      const staleBody = await staleResponse.json();
      assert.deepEqual(staleBody.accepted, [setId]);
      assert.deepEqual(staleBody.applied, []);

      const tieBreakerResponse = await serverApp.app.request("/sync/push", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          deviceId: "device-b",
          entity: "logged_sets",
          changes: [
            {
              id: setId,
              payload: _loggedSetPayload(setId, "7", winningTimestamp),
              updatedAt: winningTimestamp.toISOString(),
              deletedAt: null
            }
          ]
        })
      });

      assert.equal(tieBreakerResponse.status, 200);
      const tieBreakerBody = await tieBreakerResponse.json();
      assert.deepEqual(tieBreakerBody.accepted, [setId]);
      assert.deepEqual(tieBreakerBody.applied, [
        {
          id: setId,
          updatedAt: winningTimestamp.toISOString(),
          deviceId: "device-b"
        }
      ]);

      const rows = await serverApp.database.sql`
        select device_id, payload, updated_at
        from logged_sets
        where id = ${setId}
      `;
      assert.equal(rows.length, 1);
      assert.equal(rows[0].device_id, "device-b");
      assert.equal(rows[0].payload.reps_entered, "7");
      assert.equal(
        new Date(rows[0].updated_at).toISOString(),
        winningTimestamp.toISOString()
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "sync push clamps an obviously incorrect future clock",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const { sessionToken } = await createSignedInUser(serverApp);
    const setId = randomUUID();
    const futureTimestamp = new Date("2099-01-01T00:00:00.000Z");

    try {
      const futureResponse = await serverApp.app.request("/sync/push", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          deviceId: "bad-clock-device",
          entity: "logged_sets",
          changes: [
            {
              id: setId,
              payload: _loggedSetPayload(setId, "99", futureTimestamp),
              updatedAt: futureTimestamp.toISOString(),
              deletedAt: null
            }
          ]
        })
      });

      assert.equal(futureResponse.status, 200);
      const futureBody = await futureResponse.json();
      assert.deepEqual(futureBody.accepted, [setId]);
      assert.equal(futureBody.applied[0].id, setId);
      assert.notEqual(
        futureBody.applied[0].updatedAt,
        futureTimestamp.toISOString()
      );
      assert.ok(new Date(futureBody.applied[0].updatedAt) < futureTimestamp);

      const normalizedFutureTimestamp = new Date(
        futureBody.applied[0].updatedAt
      );
      const normalTimestamp = new Date(
        normalizedFutureTimestamp.getTime() + 60 * 1000
      );
      const normalResponse = await serverApp.app.request("/sync/push", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          deviceId: "normal-device",
          entity: "logged_sets",
          changes: [
            {
              id: setId,
              payload: _loggedSetPayload(setId, "5", normalTimestamp),
              updatedAt: normalTimestamp.toISOString(),
              deletedAt: null
            }
          ]
        })
      });

      assert.equal(normalResponse.status, 200);
      const normalBody = await normalResponse.json();
      assert.deepEqual(normalBody.accepted, [setId]);
      assert.deepEqual(normalBody.applied, [
        {
          id: setId,
          updatedAt: normalTimestamp.toISOString(),
          deviceId: "normal-device"
        }
      ]);

      const rows = await serverApp.database.sql`
        select device_id, payload, updated_at
        from logged_sets
        where id = ${setId}
      `;
      assert.equal(rows.length, 1);
      assert.equal(rows[0].device_id, "normal-device");
      assert.equal(rows[0].payload.reps_entered, "5");
      assert.equal(
        new Date(rows[0].updated_at).toISOString(),
        normalTimestamp.toISOString()
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "sync push does not resurrect a row after a newer tombstone",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const { userId, sessionToken } = await createSignedInUser(serverApp);
    const setId = randomUUID();
    const liveTimestamp = new Date("2026-06-22T08:00:00.000Z");
    const deletedTimestamp = new Date("2026-06-22T09:00:00.000Z");

    try {
      await serverApp.database.db.insert(schema.loggedSets).values({
        id: setId,
        userId,
        deviceId: "device-a",
        payload: _loggedSetPayload(
          setId,
          "5",
          deletedTimestamp,
          deletedTimestamp
        ),
        updatedAt: deletedTimestamp,
        deletedAt: deletedTimestamp,
        receivedAt: deletedTimestamp
      });

      const response = await serverApp.app.request("/sync/push", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          deviceId: "device-b",
          entity: "logged_sets",
          changes: [
            {
              id: setId,
              payload: _loggedSetPayload(setId, "5", liveTimestamp),
              updatedAt: liveTimestamp.toISOString(),
              deletedAt: null
            }
          ]
        })
      });

      assert.equal(response.status, 200);
      const body = await response.json();
      assert.deepEqual(body.accepted, [setId]);
      assert.deepEqual(body.applied, []);

      const rows = await serverApp.database.sql`
        select device_id, payload, updated_at, deleted_at
        from logged_sets
        where id = ${setId}
      `;
      assert.equal(rows.length, 1);
      assert.equal(rows[0].device_id, "device-a");
      assert.equal(rows[0].payload.deleted_at, deletedTimestamp.toISOString());
      assert.equal(
        new Date(rows[0].updated_at).toISOString(),
        deletedTimestamp.toISOString()
      );
      assert.equal(
        new Date(rows[0].deleted_at).toISOString(),
        deletedTimestamp.toISOString()
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "sync pull signals forced full resync for an expired cursor",
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
          cursor: "2000-01-01T00:00:00.000Z|expired-row",
          limit: 100
        })
      });

      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.protocolVersion, 1);
      assert.equal(body.fullResyncRequired, true);
      assert.deepEqual(body.changes, []);
      assert.equal(body.nextCursor, "2000-01-01T00:00:00.000Z|expired-row");
      assert.equal(typeof body.serverClock, "string");
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "sync pull snapshot returns live rows without tombstones",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const { userId, sessionToken } = await createSignedInUser(serverApp);
    const liveSetId = randomUUID();
    const deletedSetId = randomUUID();
    const liveReceivedAt = new Date("2026-06-22T08:00:00.000Z");
    const deletedReceivedAt = new Date("2026-06-22T08:00:01.000Z");

    try {
      await serverApp.database.db.insert(schema.loggedSets).values([
        {
          id: liveSetId,
          userId,
          deviceId: "device-a",
          payload: _loggedSetPayload(liveSetId, "5", liveReceivedAt),
          updatedAt: liveReceivedAt,
          deletedAt: null,
          receivedAt: liveReceivedAt
        },
        {
          id: deletedSetId,
          userId,
          deviceId: "device-a",
          payload: _loggedSetPayload(
            deletedSetId,
            "6",
            deletedReceivedAt,
            deletedReceivedAt
          ),
          updatedAt: deletedReceivedAt,
          deletedAt: deletedReceivedAt,
          receivedAt: deletedReceivedAt
        }
      ]);

      const response = await serverApp.app.request("/sync/pull", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          cursor: null,
          limit: 100,
          mode: "snapshot"
        })
      });

      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.fullResyncRequired, false);
      assert.deepEqual(
        body.changes.map((change) => change.id),
        [liveSetId]
      );
      assert.equal(body.changes[0].deletedAt, null);
      assert.equal(typeof body.nextCursor, "string");
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "sync pull pages logged sets with a stable cursor window",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const { userId, sessionToken } = await createSignedInUser(serverApp);
    const otherUser = await createSignedInUser(serverApp);
    const firstSetId = randomUUID();
    const secondSetId = randomUUID();
    const otherSetId = randomUUID();
    const firstReceivedAt = new Date("2026-06-22T08:00:00.000Z");
    const secondReceivedAt = new Date("2026-06-22T08:00:01.000Z");

    try {
      await serverApp.database.db.insert(schema.loggedSets).values([
        {
          id: firstSetId,
          userId,
          deviceId: "server-device",
          payload: _loggedSetPayload(firstSetId, "5", firstReceivedAt),
          updatedAt: firstReceivedAt,
          deletedAt: null,
          receivedAt: firstReceivedAt
        },
        {
          id: secondSetId,
          userId,
          deviceId: "server-device",
          payload: _loggedSetPayload(secondSetId, "6", secondReceivedAt),
          updatedAt: secondReceivedAt,
          deletedAt: null,
          receivedAt: secondReceivedAt
        },
        {
          id: otherSetId,
          userId: otherUser.userId,
          deviceId: "other-device",
          payload: _loggedSetPayload(otherSetId, "99", firstReceivedAt),
          updatedAt: firstReceivedAt,
          deletedAt: null,
          receivedAt: firstReceivedAt
        }
      ]);

      const firstResponse = await serverApp.app.request("/sync/pull", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          cursor: null,
          limit: 1
        })
      });

      assert.equal(firstResponse.status, 200);
      const firstBody = await firstResponse.json();
      assert.equal(firstBody.protocolVersion, 1);
      assert.equal(typeof firstBody.serverClock, "string");
      assert.equal(firstBody.changes.length, 1);
      assert.equal(firstBody.changes[0].id, firstSetId);
      assert.equal(firstBody.changes[0].entity, "logged_sets");
      assert.equal(firstBody.changes[0].deviceId, "server-device");
      assert.equal(firstBody.changes[0].payload.reps_entered, "5");
      assert.equal(typeof firstBody.nextCursor, "string");

      const secondResponse = await serverApp.app.request("/sync/pull", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          cursor: firstBody.nextCursor,
          limit: 10
        })
      });

      assert.equal(secondResponse.status, 200);
      const secondBody = await secondResponse.json();
      assert.equal(typeof secondBody.serverClock, "string");
      assert.equal(secondBody.changes.length, 1);
      assert.equal(secondBody.changes[0].id, secondSetId);
      assert.equal(secondBody.changes[0].deviceId, "server-device");
      assert.equal(secondBody.changes[0].payload.reps_entered, "6");
      assert.equal(typeof secondBody.nextCursor, "string");

      const emptyResponse = await serverApp.app.request("/sync/pull", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          cursor: secondBody.nextCursor,
          limit: 10
        })
      });

      assert.equal(emptyResponse.status, 200);
      const emptyBody = await emptyResponse.json();
      assert.equal(emptyBody.protocolVersion, 1);
      assert.deepEqual(emptyBody.changes, []);
      assert.equal(emptyBody.nextCursor, secondBody.nextCursor);
      assert.equal(typeof emptyBody.serverClock, "string");
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "sync pull cursor advances by time before entity rank",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const { userId, sessionToken } = await createSignedInUser(serverApp);
    const consentId = randomUUID();
    const metricId = randomUUID();
    const readingId = randomUUID();
    const consentReceivedAt = new Date("2026-06-22T08:00:00.000Z");
    const metricReceivedAt = new Date("2026-06-22T08:00:01.000Z");

    try {
      await serverApp.database.db
        .insert(schema.integrationDataClassConsents)
        .values({
          id: consentId,
          userId,
          deviceId: "server:integration-credential",
          credentialId: "credential-1",
          dataClass: "activities",
          enabled: true,
          updatedAt: consentReceivedAt,
          deletedAt: null,
          receivedAt: consentReceivedAt
        });
      await serverApp.database.db.insert(schema.metrics).values({
        id: metricId,
        userId,
        deviceId: "integration:garmin",
        name: "Steps",
        unit: "count",
        valueShape: "scalar",
        metricGroup: "monitoring",
        goalType: null,
        goalTargetValue: null,
        enabled: true,
        pinned: false,
        sortOrder: 0,
        updatedAt: metricReceivedAt,
        deletedAt: null,
        receivedAt: metricReceivedAt
      });
      await serverApp.database.db.insert(schema.metricReadings).values({
        id: readingId,
        userId,
        deviceId: "integration:garmin",
        metricId,
        externalActivityId: null,
        valueJson: {
          value: 1234,
          unit: "count",
          entered: "1234"
        },
        scalarValue: 1234,
        scalarEntered: "1234",
        atTime: metricReceivedAt,
        windowStartedAt: null,
        windowEndedAt: null,
        provenance: "integration",
        source: "garmin",
        externalId: "daily-2026-06-22:steps",
        comment: null,
        updatedAt: metricReceivedAt,
        deletedAt: null,
        receivedAt: metricReceivedAt
      });

      const response = await serverApp.app.request("/sync/pull", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          cursor: `${consentReceivedAt.toISOString()}|integration_data_class_consents|${consentId}`,
          limit: 100
        })
      });

      assert.equal(response.status, 200);
      const body = await response.json();
      assert.deepEqual(
        body.changes.map((change) => [change.entity, change.id]),
        [
          ["metrics", metricId],
          ["metric_readings", readingId]
        ]
      );
      assert.equal(
        body.nextCursor,
        `${metricReceivedAt.toISOString()}|metric_readings|${readingId}`
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "sync pull returns Metrics and Metric Readings as ordinary sync rows",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const { userId, sessionToken } = await createSignedInUser(serverApp);
    const otherUser = await createSignedInUser(serverApp);
    const metricId = randomUUID();
    const otherMetricId = randomUUID();
    const liveReadingId = randomUUID();
    const deletedReadingId = randomUUID();
    const otherUserReadingId = randomUUID();
    const liveReceivedAt = new Date("2026-06-22T08:00:00.000Z");
    const deletedReceivedAt = new Date("2026-06-22T08:00:01.000Z");

    try {
      await serverApp.database.db.insert(schema.metrics).values([
        {
          id: metricId,
          userId,
          deviceId: "integration:garmin",
          name: "averageHeartRate",
          unit: "beatsPerMinute",
          valueShape: "scalar",
          metricGroup: "monitoring",
          goalType: null,
          goalTargetValue: null,
          enabled: true,
          pinned: false,
          sortOrder: 0,
          updatedAt: liveReceivedAt,
          deletedAt: null,
          receivedAt: liveReceivedAt
        },
        {
          id: otherMetricId,
          userId: otherUser.userId,
          deviceId: "integration:garmin",
          name: "averageHeartRate",
          unit: "beatsPerMinute",
          valueShape: "scalar",
          metricGroup: "monitoring",
          goalType: null,
          goalTargetValue: null,
          enabled: true,
          pinned: false,
          sortOrder: 0,
          updatedAt: liveReceivedAt,
          deletedAt: null,
          receivedAt: liveReceivedAt
        }
      ]);
      await serverApp.database.db.insert(schema.metricReadings).values([
        {
          id: liveReadingId,
          userId,
          deviceId: "integration:garmin",
          metricId,
          externalActivityId: "external-activity-1",
          valueJson: {
            value: 132,
            unit: "beatsPerMinute",
            entered: "132"
          },
          scalarValue: 132,
          scalarEntered: "132",
          atTime: null,
          windowStartedAt: liveReceivedAt,
          windowEndedAt: new Date("2026-06-22T08:45:00.000Z"),
          provenance: "integration",
          source: "garmin",
          externalId: "activity-123:average-heart-rate",
          comment: null,
          updatedAt: liveReceivedAt,
          deletedAt: null,
          receivedAt: liveReceivedAt
        },
        {
          id: deletedReadingId,
          userId,
          deviceId: "integration:garmin",
          metricId,
          externalActivityId: null,
          valueJson: {
            value: 56,
            unit: "beatsPerMinute",
            entered: "56"
          },
          scalarValue: 56,
          scalarEntered: "56",
          atTime: deletedReceivedAt,
          windowStartedAt: null,
          windowEndedAt: null,
          provenance: "integration",
          source: "garmin",
          externalId: "daily-2026-06-22:resting-heart-rate",
          comment: null,
          updatedAt: deletedReceivedAt,
          deletedAt: deletedReceivedAt,
          receivedAt: deletedReceivedAt
        },
        {
          id: otherUserReadingId,
          userId: otherUser.userId,
          deviceId: "integration:garmin",
          metricId: otherMetricId,
          externalActivityId: null,
          valueJson: {
            value: 199,
            unit: "beatsPerMinute",
            entered: "199"
          },
          scalarValue: 199,
          scalarEntered: "199",
          atTime: liveReceivedAt,
          windowStartedAt: null,
          windowEndedAt: null,
          provenance: "integration",
          source: "garmin",
          externalId: "other-user:average-heart-rate",
          comment: null,
          updatedAt: liveReceivedAt,
          deletedAt: null,
          receivedAt: liveReceivedAt
        }
      ]);

      const deltaResponse = await serverApp.app.request("/sync/pull", {
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

      assert.equal(deltaResponse.status, 200);
      const deltaBody = await deltaResponse.json();
      assert.deepEqual(
        deltaBody.changes.map((change) => change.entity),
        ["metrics", "metric_readings", "metric_readings"]
      );
      assert.equal(deltaBody.changes[0].id, metricId);
      assert.equal(deltaBody.changes[0].payload.name, "averageHeartRate");
      assert.equal(deltaBody.changes[0].payload.value_shape, "scalar");
      assert.equal(deltaBody.changes[0].payload.metric_group, "monitoring");
      assert.equal(deltaBody.changes[1].id, liveReadingId);
      assert.equal(deltaBody.changes[1].deviceId, "integration:garmin");
      assert.equal(deltaBody.changes[1].payload.metric_id, metricId);
      assert.equal(
        deltaBody.changes[1].payload.external_activity_id,
        "external-activity-1"
      );
      assert.equal(deltaBody.changes[1].payload.provenance, "integration");
      assert.equal(deltaBody.changes[1].payload.source, "garmin");
      assert.equal(deltaBody.changes[1].payload.scalar_value, 132);
      assert.equal(deltaBody.changes[1].payload.value_json.value, 132);
      assert.equal(deltaBody.changes[1].payload.reps_entered, undefined);
      assert.equal(deltaBody.changes[2].deletedAt, deletedReceivedAt.toISOString());
      assert.equal(
        deltaBody.changes.some((change) => change.id === otherUserReadingId),
        false
      );

      const snapshotResponse = await serverApp.app.request("/sync/pull", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          cursor: null,
          limit: 100,
          mode: "snapshot"
        })
      });

      assert.equal(snapshotResponse.status, 200);
      const snapshotBody = await snapshotResponse.json();
      assert.deepEqual(
        snapshotBody.changes.map((change) => change.id),
        [metricId, liveReadingId]
      );
      assert.equal(snapshotBody.changes[0].deletedAt, null);
      assert.equal(snapshotBody.changes[1].deletedAt, null);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "sync round-trips Integration data-class consent rows",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const credentialStore = createDrizzleIntegrationCredentialStore(
      serverApp.database.db
    );
    const { userId, sessionToken } = await createSignedInUser(serverApp);

    try {
      const issued = await credentialStore.issueIntegrationCredential({
        userId,
        name: "Garmin sidecar"
      });

      const initialPullResponse = await serverApp.app.request("/sync/pull", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          cursor: null,
          limit: 100,
          mode: "snapshot"
        })
      });
      assert.equal(initialPullResponse.status, 200);
      const initialPull = await initialPullResponse.json();
      const consentChanges = initialPull.changes.filter(
        (change) => change.entity === "integration_data_class_consents"
      ).sort((left, right) =>
        left.payload.data_class.localeCompare(right.payload.data_class)
      );
      assert.deepEqual(
        consentChanges.map((change) => [
          change.payload.credential_id,
          change.payload.data_class,
          change.payload.enabled,
          change.deletedAt
        ]),
        [
          [issued.credential.id, "activities", false, null],
          [issued.credential.id, "bodyComposition", false, null],
          [issued.credential.id, "gps", false, null],
          [issued.credential.id, "heartRate", false, null],
          [issued.credential.id, "sleepWellness", false, null]
        ]
      );

      const heartRateConsent = consentChanges.find(
        (change) => change.payload.data_class === "heartRate"
      );
      assert.ok(heartRateConsent);
      const toggledAt = new Date(
        Date.parse(heartRateConsent.updatedAt) + 1000
      ).toISOString();
      const pushResponse = await serverApp.app.request("/sync/push", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          deviceId: "device-a",
          entity: "integration_data_class_consents",
          changes: [
            {
              id: heartRateConsent.id,
              payload: {
                ...heartRateConsent.payload,
                enabled: true,
                updated_at: toggledAt,
                deleted_at: null
              },
              updatedAt: toggledAt,
              deletedAt: null
            }
          ]
        })
      });
      assert.equal(pushResponse.status, 200);
      const pushBody = await pushResponse.json();
      assert.deepEqual(pushBody.accepted, [heartRateConsent.id]);
      assert.deepEqual(pushBody.applied, [
        {
          id: heartRateConsent.id,
          updatedAt: toggledAt,
          deviceId: "device-a"
        }
      ]);

      const consentRows = await serverApp.database.sql`
        select device_id, enabled, updated_at, deleted_at
        from integration_data_class_consents
        where id = ${heartRateConsent.id}
      `;
      assert.equal(consentRows.length, 1);
      assert.equal(consentRows[0].device_id, "device-a");
      assert.equal(consentRows[0].enabled, true);
      assert.equal(new Date(consentRows[0].updated_at).toISOString(), toggledAt);
      assert.equal(consentRows[0].deleted_at, null);

      const afterTogglePullResponse = await serverApp.app.request("/sync/pull", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          cursor: null,
          limit: 100,
          mode: "snapshot"
        })
      });
      assert.equal(afterTogglePullResponse.status, 200);
      const afterTogglePull = await afterTogglePullResponse.json();
      const syncedHeartRateConsent = afterTogglePull.changes.find(
        (change) =>
          change.entity === "integration_data_class_consents" &&
          change.id === heartRateConsent.id
      );
      assert.ok(syncedHeartRateConsent);
      assert.equal(syncedHeartRateConsent.deviceId, "device-a");
      assert.equal(syncedHeartRateConsent.payload.enabled, true);
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
    name: "Sync User",
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

function _mealPayload(id, mealType, updatedAt, deletedAt = null) {
  return {
    id,
    meal_type: mealType,
    started_at: "2026-06-27T08:00:00.000Z",
    timezone: "UTC",
    local_date: "2026-06-27",
    ended_at: null,
    updated_at: updatedAt.toISOString(),
    deleted_at: deletedAt?.toISOString() ?? null
  };
}

function _foodEntryPayload(id, mealId, name, updatedAt, deletedAt = null) {
  return {
    id,
    meal_id: mealId,
    entry_kind: "food",
    position: 0,
    name,
    nutrient_values_json: JSON.stringify({
      energy: {
        status: "complete",
        value: 250,
        entered: "250",
        unit: "kilocalorie"
      }
    }),
    food_id: "3017620422003",
    portion_json: JSON.stringify({
      value: 1,
      entered: "1",
      unit: "serving"
    }),
    food_source: "openFoodFacts",
    is_liquid: false,
    serving_label: "serving",
    serving_size: 45,
    package_size: 60,
    updated_at: updatedAt.toISOString(),
    deleted_at: deletedAt?.toISOString() ?? null
  };
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
