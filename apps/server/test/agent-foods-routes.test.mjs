import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  applyMigrations,
  createApp,
  createDatabaseClient,
  createDrizzleAgentFoodBatchWriteStore,
  createDrizzleAgentFoodCatalogStore,
  createDrizzleAgentMealBatchWriteStore,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

test("agent food batch write creates a User Food, returns it from GET /agent/foods, and calls the write store once", async () => {
  const writes = [];
  const app = createAgentFoodsApp({
    agentFoodBatchWriteStore: {
      async writeFoodBatch(input) {
        writes.push(input);
        return {
          duplicate: false,
          serverClock: "2026-07-04T05:00:01.000Z",
          applied: input.foods.map((food) => ({
            id: food.id,
            updatedAt: food.updatedAt,
            deviceId: input.deviceId
          }))
        };
      }
    }
  });

  const response = await postAgentFoodBatch(
    app,
    foodBatchRequest({
      idempotencyKey: "agent-food-route-create",
      foods: [userFood()]
    }),
    { "x-correlation-id": "corr-agent-food" }
  );

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.accepted, true);
  assert.equal(body.duplicate, false);
  assert.equal(body.batchId, "agent-food-route-create");
  assert.equal(body.foods.length, 1);
  assert.equal(body.foods[0].isRecipe, false);

  assert.equal(writes.length, 1);
  assert.equal(writes[0].userId, "user-1");
  assert.equal(writes[0].deviceId, "agent:agent-key-1");
  assert.equal(writes[0].correlationId, "corr-agent-food");
  assert.equal(writes[0].foods[0].payload.name, "Banana");
  assert.equal(writes[0].foods[0].payload.food_source, "user");
});

test("agent food batch write hard-rejects one invalid item before storage and never nudges sync", async () => {
  let writeCalled = false;
  const nudges = [];
  const app = createAgentFoodsApp({
    agentFoodBatchWriteStore: {
      async writeFoodBatch() {
        writeCalled = true;
        throw new Error("writeFoodBatch should not be called.");
      }
    },
    syncNudgePublisher: {
      async enqueueSyncNudge(input) {
        nudges.push(input);
        return { enqueued: true, jobId: "unexpected-nudge" };
      }
    }
  });

  const response = await postAgentFoodBatch(
    app,
    foodBatchRequest({
      idempotencyKey: "agent-food-invalid",
      foods: [
        userFood({
          nutrientsPer100: {
            energy: {
              status: "complete",
              value: -5,
              entered: "-5",
              unit: "kilocalorie"
            }
          }
        })
      ]
    })
  );

  assert.equal(response.status, 422);
  const body = await response.json();
  assert.equal(body.code, "agent_food_batch_write_failed");
  assert.equal(body.errors[0].rule, "nutrient_non_negative");
  assert.ok(body.limits);
  assert.equal(writeCalled, false);
  assert.deepEqual(nudges, []);
});

test("agent food batch write enqueues a best-effort sync nudge after a committed write", async () => {
  const nudges = [];
  const app = createAgentFoodsApp({
    agentFoodBatchWriteStore: {
      async writeFoodBatch(input) {
        return {
          duplicate: false,
          serverClock: "2026-07-04T05:00:01.000Z",
          applied: input.foods.map((food) => ({
            id: food.id,
            updatedAt: food.updatedAt,
            deviceId: input.deviceId
          }))
        };
      }
    },
    syncNudgePublisher: {
      async enqueueSyncNudge(input) {
        nudges.push(input);
        return { enqueued: true, jobId: "agent-food-nudge-1" };
      }
    }
  });

  const response = await postAgentFoodBatch(
    app,
    foodBatchRequest({
      idempotencyKey: "agent-food-nudge-route-test",
      foods: [userFood()]
    })
  );

  assert.equal(response.status, 200);
  assert.deepEqual(nudges, [
    {
      userId: "user-1",
      sourceDeviceId: "agent:agent-key-1",
      reason: "agent_write"
    }
  ]);
});

test("GET /agent/foods/platform-search returns the bundled USDA catalog with attribution and requires auth", async () => {
  const app = createAgentFoodsApp({});

  const unauthorized = await app.request("/agent/foods/platform-search");
  assert.equal(unauthorized.status, 401);

  const response = await getAgent(app, "/agent/foods/platform-search?search=chicken");
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.ok(body.foods.length > 0);
  assert.ok(
    body.foods.every((food) =>
      food.name.toLowerCase().includes("chicken")
    )
  );
  assert.equal(body.attribution.source, "usda");
  assert.ok(body.attribution.attributionText.length > 0);
});

test(
  "agent food lifecycle: create -> platform-search -> log a meal by Food reference end-to-end, with tenant isolation",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-food-user-${randomUUID()}`;
    const otherUserId = `agent-food-other-user-${randomUUID()}`;
    const foodId = randomUUID();

    const app = createAgentFoodsApp({
      agentFoodBatchWriteStore: createDrizzleAgentFoodBatchWriteStore(
        database.db
      ),
      agentFoodCatalogStore: createDrizzleAgentFoodCatalogStore(database.db),
      agentMealBatchWriteStore: createDrizzleAgentMealBatchWriteStore(
        database.db
      ),
      userId
    });

    try {
      await database.db.insert(schema.user).values([
        {
          id: userId,
          name: "Agent Food User",
          email: `${userId}@example.com`,
          emailVerified: true
        },
        {
          id: otherUserId,
          name: "Other User",
          email: `${otherUserId}@example.com`,
          emailVerified: true
        }
      ]);

      // 1. Create a User Food.
      const createResponse = await postAgentFoodBatch(
        app,
        foodBatchRequest({
          idempotencyKey: `agent-food-create-${randomUUID()}`,
          foods: [userFood({ id: foodId })]
        })
      );
      assert.equal(createResponse.status, 200);

      const foodRows = await database.sql`
        select user_id, payload, deleted_at from foods where id = ${foodId}
      `;
      assert.equal(foodRows.length, 1);
      assert.equal(foodRows[0].user_id, userId);
      assert.equal(foodRows[0].payload.name, "Banana");

      // 2. GET /agent/foods finds it by search.
      const listResponse = await getAgent(app, "/agent/foods?search=banana");
      assert.equal(listResponse.status, 200);
      const listBody = await listResponse.json();
      assert.ok(listBody.foods.some((food) => food.id === foodId));

      // 3. Platform search still resolves the bundled USDA catalog
      // independently of the user's own library.
      const platformResponse = await getAgent(
        app,
        "/agent/foods/platform-search?search=chicken"
      );
      assert.equal(platformResponse.status, 200);
      const platformBody = await platformResponse.json();
      assert.ok(platformBody.foods.length > 0);

      // 4. Log a Meal referencing the created Food by id ONLY — no nutrient
      // vector, name, or serving info supplied. The server resolves the full
      // self-describing Food Entry snapshot from the caller's own Food
      // ('s core acceptance criterion): log-a-meal-by-reference.
      const mealId = randomUUID();
      const entryId = randomUUID();
      const mealResponse = await app.request("/agent/meals/batch-write", {
        method: "POST",
        headers: {
          authorization: "Bearer prn_agent_secret",
          "content-type": "application/json"
        },
        body: JSON.stringify({
          idempotencyKey: `agent-food-log-meal-${randomUUID()}`,
          meal: {
            id: mealId,
            mealType: "Breakfast",
            startedAt: "2026-07-04T07:00:00.000Z",
            endedAt: null,
            timezone: "Australia/Brisbane",
            localDate: "2026-07-04"
          },
          entries: [
            {
              id: entryId,
              position: 0,
              foodId,
              foodSource: "user",
              portion: { value: 1, entered: "1", unit: "serving" }
            }
          ]
        })
      });
      assert.equal(mealResponse.status, 200);
      const mealBody = await mealResponse.json();
      assert.equal(mealBody.entries[0].name, "Banana");
      assert.equal(mealBody.entries[0].kind, "food");

      const entryRows = await database.sql`
        select payload from food_entries where id = ${entryId}
      `;
      assert.equal(entryRows.length, 1);
      assert.equal(entryRows[0].payload.food_id, foodId);
      assert.equal(entryRows[0].payload.name, "Banana");
      assert.equal(entryRows[0].payload.serving_size, 118);
      const resolvedNutrients = JSON.parse(
        entryRows[0].payload.nutrient_values_json
      );
      assert.equal(resolvedNutrients.energy.value, 89);

      // 5. Tenant isolation: a second user's push must never overwrite the
      // first user's Food row keyed by the same client PK.
      const otherApp = createAgentFoodsApp({
        agentFoodBatchWriteStore: createDrizzleAgentFoodBatchWriteStore(
          database.db
        ),
        agentFoodCatalogStore: createDrizzleAgentFoodCatalogStore(database.db),
        userId: otherUserId
      });
      const hijackResponse = await postAgentFoodBatch(
        otherApp,
        foodBatchRequest({
          idempotencyKey: `agent-food-hijack-${randomUUID()}`,
          foods: [userFood({ id: foodId, name: "Hijacked" })]
        })
      );
      assert.equal(hijackResponse.status, 200);

      const postHijackRows = await database.sql`
        select user_id, payload from foods where id = ${foodId}
      `;
      assert.equal(postHijackRows[0].user_id, userId);
      assert.equal(postHijackRows[0].payload.name, "Banana");

      // The other user's own list must never see the first user's Food.
      const otherListResponse = await getAgent(
        otherApp,
        "/agent/foods?includeArchived=true"
      );
      const otherListBody = await otherListResponse.json();
      assert.ok(!otherListBody.foods.some((food) => food.id === foodId));
    } finally {
      await database.close();
    }
  }
);

test(
  "agent food batch write archives a Food as an LWW tombstone with correct Activity Log before/after images",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-food-archive-user-${randomUUID()}`;
    const foodId = randomUUID();

    const app = createAgentFoodsApp({
      agentFoodBatchWriteStore: createDrizzleAgentFoodBatchWriteStore(
        database.db
      ),
      userId
    });

    try {
      await database.db.insert(schema.user).values({
        id: userId,
        name: "Agent Food Archive User",
        email: `${userId}@example.com`,
        emailVerified: true
      });

      const createdAt = "2026-07-04T05:00:00.000Z";
      const createResponse = await postAgentFoodBatch(
        app,
        foodBatchRequest({
          idempotencyKey: `agent-food-archive-create-${randomUUID()}`,
          foods: [userFood({ id: foodId, updatedAt: createdAt })]
        })
      );
      assert.equal(createResponse.status, 200);

      // Archive strictly after the create so the tombstone always wins LWW,
      // independent of the wall clock at test time (both timestamps are in the
      // past; a server-clock default for the create could otherwise be newer
      // than a hardcoded archive time and make the archive a superseded loser).
      const archivedAt = "2026-07-04T06:00:00.000Z";
      const archiveResponse = await postAgentFoodBatch(
        app,
        foodBatchRequest({
          idempotencyKey: `agent-food-archive-delete-${randomUUID()}`,
          foods: [
            userFood({ id: foodId, updatedAt: archivedAt, deletedAt: archivedAt })
          ]
        })
      );
      assert.equal(archiveResponse.status, 200);

      const archivedRows = await database.sql`
        select deleted_at, payload from foods where id = ${foodId}
      `;
      assert.notEqual(archivedRows[0].deleted_at, null);
      assert.equal(archivedRows[0].payload.deleted_at, archivedAt);

      const activityRows = await database.sql`
        select before_image, after_image
        from activity_log
        where entity_table = 'foods' and entity_id = ${foodId}
        order by created_at asc
      `;
      assert.ok(activityRows.length >= 2);
      const archiveActivity = activityRows[activityRows.length - 1];
      assert.equal(archiveActivity.before_image.deleted_at, null);
      assert.equal(archiveActivity.after_image.deleted_at, archivedAt);
    } finally {
      await database.close();
    }
  }
);

function createAgentFoodsApp({
  agentFoodBatchWriteStore,
  agentFoodCatalogStore,
  agentMealBatchWriteStore,
  logger = { info() {}, error() {} },
  syncNudgePublisher,
  userId = "user-1"
}) {
  return createApp({
    logger,
    agentApiKeyStore: createAgentKeyStore(userId),
    agentFoodBatchWriteStore,
    agentFoodCatalogStore,
    agentMealBatchWriteStore,
    syncNudgePublisher
  });
}

function createAgentKeyStore(userId) {
  return {
    async authenticateAgentApiKey(secret) {
      if (secret !== "prn_agent_secret") {
        return null;
      }
      return { userId, keyId: "agent-key-1", keyName: "Garage coach" };
    },
    async createAgentApiKey() {
      throw new Error("createAgentApiKey should not be called.");
    },
    async listAgentApiKeys() {
      throw new Error("listAgentApiKeys should not be called.");
    },
    async revokeAgentApiKey() {
      throw new Error("revokeAgentApiKey should not be called.");
    },
    async verifySessionBearerToken() {
      throw new Error("verifySessionBearerToken should not be called.");
    }
  };
}

function postAgentFoodBatch(app, body, headers = {}) {
  return app.request("/agent/foods/batch-write", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_agent_secret",
      "content-type": "application/json",
      ...headers
    },
    body: JSON.stringify(body)
  });
}

function getAgent(app, path) {
  return app.request(path, {
    headers: { authorization: "Bearer prn_agent_secret" }
  });
}

function foodBatchRequest({ idempotencyKey, foods }) {
  return { idempotencyKey, foods };
}

function userFood(overrides = {}) {
  return {
    id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d001",
    name: "Banana",
    nutrientsPer100: {
      energy: {
        status: "complete",
        value: 89,
        entered: "89",
        unit: "kilocalorie"
      },
      protein: {
        status: "complete",
        value: 1.1,
        entered: "1.1",
        unit: "gram"
      }
    },
    isLiquid: false,
    servingLabel: "medium",
    servingSize: 118,
    packageSize: null,
    recipeIngredients: null,
    recipeServingCount: null,
    deletedAt: null,
    ...overrides
  };
}
