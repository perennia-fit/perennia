import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  applyMigrations,
  createApp,
  createDatabaseClient,
  createDrizzleAgentMealBatchWriteStore,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

test("agent meal batch write snapshots entries, returns warnings, and calls the write store once", async () => {
  const writes = [];
  const app = createAgentMealApp({
    agentMealBatchWriteStore: {
      async writeMealBatch(input) {
        writes.push(input);
        return {
          duplicate: false,
          serverClock: "2026-06-24T05:00:01.000Z",
          applied: [
            {
              id: input.meal.id,
              updatedAt: input.meal.updatedAt,
              deviceId: input.deviceId
            },
            ...input.entries.map((entry) => ({
              id: entry.id,
              updatedAt: entry.updatedAt,
              deviceId: input.deviceId
            }))
          ]
        };
      }
    }
  });
  const request = mealRequest({
    idempotencyKey: "agent-meal-route-test",
    entries: [referenceFoodEntry(), quickEntry()]
  });

  const response = await postAgentMeal(app, request, {
    "x-correlation-id": "corr-agent-meal"
  });

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.accepted, true);
  assert.equal(body.duplicate, false);
  assert.equal(body.batchId, "agent-meal-route-test");
  assert.equal(body.mealId, request.meal.id);
  assert.equal(body.entries.length, 2);
  assert.equal(body.entries[0].kind, "food");
  assert.equal(body.entries[1].kind, "quickEntry");

  assert.equal(writes.length, 1);
  assert.equal(writes[0].userId, "user-1");
  assert.equal(writes[0].batchId, "agent-meal-route-test");
  assert.equal(writes[0].deviceId, "agent:agent-key-1");
  assert.equal(writes[0].correlationId, "corr-agent-meal");

  // Meal snapshot fields.
  assert.equal(writes[0].meal.payload.meal_type, "Lunch");
  assert.equal(writes[0].meal.payload.started_at, request.meal.startedAt);
  assert.equal(writes[0].meal.payload.local_date, request.meal.localDate);

  // Reference Food entry: self-describing snapshot + semantic Portion; no totals.
  const foodPayload = writes[0].entries[0].payload;
  assert.equal(foodPayload.meal_id, request.meal.id);
  assert.equal(foodPayload.entry_kind, "food");
  assert.equal(foodPayload.name, "Banana");
  assert.equal(foodPayload.food_id, "food-banana");
  assert.equal(foodPayload.food_source, "usda");
  assert.equal(foodPayload.is_liquid, false);
  assert.equal(foodPayload.serving_size, 118);
  const portion = JSON.parse(foodPayload.portion_json);
  assert.deepEqual(portion, { value: 2, entered: "2", unit: "serving" });
  const foodNutrients = JSON.parse(foodPayload.nutrient_values_json);
  assert.equal(foodNutrients.energy.status, "complete");
  assert.equal(foodNutrients.energy.value, 89);
  // No nutrition totals are stored on the row.
  assert.equal(foodPayload.total_energy, undefined);
  assert.equal(foodPayload.energy, undefined);

  // Quick Entry: nutrient vector directly, no Portion, no food id/source.
  const quickPayload = writes[0].entries[1].payload;
  assert.equal(quickPayload.entry_kind, "quickEntry");
  assert.equal(quickPayload.food_id, null);
  assert.equal(quickPayload.food_source, null);
  assert.equal(quickPayload.portion_json, null);
});

test("agent meal batch write keeps unknown nutrients unknown and never coerces to zero", async () => {
  const writes = [];
  const app = createAgentMealApp({
    agentMealBatchWriteStore: {
      async writeMealBatch(input) {
        writes.push(input);
        return {
          duplicate: false,
          serverClock: "2026-06-24T05:00:01.000Z",
          applied: [{ id: input.meal.id, updatedAt: input.meal.updatedAt, deviceId: input.deviceId }]
        };
      }
    }
  });
  // A Quick Entry that only states energy: fiber must stay unknown, not 0.
  const request = mealRequest({
    idempotencyKey: "agent-meal-unknown-test",
    entries: [
      quickEntry({
        nutrients: {
          energy: { status: "complete", value: 120, entered: "120", unit: "kilocalorie" }
        }
      })
    ]
  });

  const response = await postAgentMeal(app, request);
  assert.equal(response.status, 200);

  const stored = JSON.parse(writes[0].entries[0].payload.nutrient_values_json);
  assert.equal(stored.energy.status, "complete");
  assert.equal(stored.energy.value, 120);
  // Omitted nutrients are explicit unknowns, not zero.
  assert.equal(stored.fiber.status, "unknown");
  assert.equal(stored.fiber.value, null);
  assert.equal(stored.protein.status, "unknown");
  assert.equal(stored.protein.value, null);
});

test("agent meal batch write returns per-item warnings while still persisting", async () => {
  const writes = [];
  const app = createAgentMealApp({
    agentMealBatchWriteStore: {
      async writeMealBatch(input) {
        writes.push(input);
        return {
          duplicate: false,
          serverClock: "2026-06-24T05:00:01.000Z",
          applied: [{ id: input.meal.id, updatedAt: input.meal.updatedAt, deviceId: input.deviceId }]
        };
      }
    }
  });
  // Energy far from the Atwater estimate -> soft warn, still persists.
  const request = mealRequest({
    idempotencyKey: "agent-meal-warning-test",
    entries: [
      quickEntry({
        nutrients: {
          energy: { status: "complete", value: 900, entered: "900", unit: "kilocalorie" },
          protein: { status: "complete", value: 10, entered: "10", unit: "gram" },
          carbohydrate: { status: "complete", value: 10, entered: "10", unit: "gram" },
          fat: { status: "complete", value: 5, entered: "5", unit: "gram" }
        }
      })
    ]
  });

  const response = await postAgentMeal(app, request);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.entries.length, 1);
  assert.deepEqual(
    body.entries[0].warnings.map((warning) => warning.rule),
    ["energy_atwater_mismatch"]
  );
  // Soft-warned item still persisted.
  assert.equal(writes.length, 1);
  assert.equal(writes[0].entries.length, 1);
});

test("agent meal batch write accepts a nullable deletedAt on the meal and each entry, passing it through as an LWW tombstone", async () => {
  const writes = [];
  const app = createAgentMealApp({
    agentMealBatchWriteStore: {
      async writeMealBatch(input) {
        writes.push(input);
        return {
          duplicate: false,
          serverClock: "2026-06-24T05:00:01.000Z",
          applied: [
            { id: input.meal.id, updatedAt: input.meal.updatedAt, deviceId: input.deviceId },
            ...input.entries.map((entry) => ({
              id: entry.id,
              updatedAt: entry.updatedAt,
              deviceId: input.deviceId
            }))
          ]
        };
      }
    }
  });
  const archivedAt = "2026-06-24T06:00:00.000Z";
  const request = {
    idempotencyKey: "agent-meal-archive-route-test",
    meal: {
      id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d900",
      mealType: "Lunch",
      startedAt: "2026-06-24T05:00:00.000Z",
      endedAt: null,
      timezone: "Australia/Brisbane",
      localDate: "2026-06-24",
      deletedAt: archivedAt
    },
    entries: [quickEntry({ updatedAt: archivedAt, deletedAt: archivedAt })]
  };

  const response = await postAgentMeal(app, request);

  assert.equal(response.status, 200);
  assert.equal(writes.length, 1);
  assert.equal(writes[0].meal.deletedAt, archivedAt);
  assert.equal(writes[0].meal.payload.deleted_at, archivedAt);
  assert.equal(writes[0].entries[0].deletedAt, archivedAt);
  assert.equal(writes[0].entries[0].payload.deleted_at, archivedAt);
});

test("agent meal batch write hard-rejects one invalid item before storage", async () => {
  let writeCalled = false;
  const nudges = [];
  const app = createAgentMealApp({
    agentMealBatchWriteStore: {
      async writeMealBatch() {
        writeCalled = true;
        throw new Error("writeMealBatch should not be called.");
      }
    },
    syncNudgePublisher: {
      async enqueueSyncNudge(input) {
        nudges.push(input);
        return { enqueued: true, jobId: "unexpected-nudge" };
      }
    }
  });
  const request = mealRequest({
    idempotencyKey: "agent-meal-invalid-test",
    entries: [
      quickEntry({
        nutrients: {
          energy: { status: "complete", value: -5, entered: "-5", unit: "kilocalorie" }
        }
      })
    ]
  });

  const response = await postAgentMeal(app, request);

  assert.equal(response.status, 422);
  const body = await response.json();
  assert.equal(body.code, "agent_meal_batch_write_failed");
  assert.equal(body.errors.length, 1);
  assert.equal(body.errors[0].itemIndex, 0);
  assert.equal(body.errors[0].rule, "nutrient_non_negative");
  assert.ok(body.limits);
  assert.equal(writeCalled, false);
  assert.deepEqual(nudges, []);
});

test("agent meal batch write enqueues a best-effort sync nudge after a committed write", async () => {
  const nudges = [];
  const app = createAgentMealApp({
    agentMealBatchWriteStore: {
      async writeMealBatch(input) {
        return {
          duplicate: false,
          serverClock: "2026-06-24T05:00:01.000Z",
          applied: [{ id: input.meal.id, updatedAt: input.meal.updatedAt, deviceId: input.deviceId }]
        };
      }
    },
    syncNudgePublisher: {
      async enqueueSyncNudge(input) {
        nudges.push(input);
        return { enqueued: true, jobId: "agent-nudge-job-1" };
      }
    }
  });

  const response = await postAgentMeal(
    app,
    mealRequest({
      idempotencyKey: "agent-meal-nudge-route-test",
      entries: [quickEntry()]
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

test(
  "agent meal batch write persists rows, records one Activity Log batch, replays idempotently, and rolls back invalid batches",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-meal-user-${randomUUID()}`;
    const app = createAgentMealApp({
      agentMealBatchWriteStore: createDrizzleAgentMealBatchWriteStore(
        database.db
      ),
      userId
    });
    const request = mealRequest({
      idempotencyKey: `agent-meal-${randomUUID()}`,
      mealId: "018f6a90-6d7f-7d63-bfc1-6f1025e0d200",
      entries: [
        referenceFoodEntry({ id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d101" }),
        quickEntry({ id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d102" })
      ]
    });

    try {
      await database.db.insert(schema.user).values({
        id: userId,
        name: "Agent Meal User",
        email: `${userId}@example.com`,
        emailVerified: true
      });

      const response = await postAgentMeal(app, request);
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.accepted, true);
      assert.equal(body.duplicate, false);
      assert.equal(body.entries.length, 2);

      // Meal row persisted with snapshot, no totals.
      const mealRows = await database.sql`
        select id, user_id, device_id, payload, deleted_at
        from meals
        where id = ${request.meal.id}
      `;
      assert.equal(mealRows.length, 1);
      assert.equal(mealRows[0].user_id, userId);
      assert.equal(mealRows[0].device_id, "agent:agent-key-1");
      assert.equal(mealRows[0].payload.meal_type, "Lunch");
      assert.equal(mealRows[0].deleted_at, null);

      // Food Entry rows persisted with self-describing snapshot + Portion.
      const entryRows = await database.sql`
        select id, user_id, payload, deleted_at
        from food_entries
        where id in (${request.entries[0].id}, ${request.entries[1].id})
        order by id
      `;
      assert.equal(entryRows.length, 2);
      const foodRow = entryRows.find(
        (row) => row.payload.entry_kind === "food"
      );
      assert.equal(foodRow.payload.food_source, "usda");
      assert.equal(foodRow.payload.is_liquid, false);
      const storedNutrients = JSON.parse(foodRow.payload.nutrient_values_json);
      assert.equal(storedNutrients.energy.value, 89);
      assert.equal(foodRow.payload.total_energy, undefined);

      // Exactly one Activity Log batch (one batch_id) covering all rows.
      const activityRows = await database.sql`
        select actor, batch_id, entity_table, entity_id, before_image, after_image
        from activity_log
        where batch_id = ${request.idempotencyKey}
        order by entity_table, entity_id
      `;
      assert.equal(activityRows.length, 3);
      assert.equal(new Set(activityRows.map((row) => row.batch_id)).size, 1);
      assert.ok(activityRows.every((row) => row.actor === "agent"));
      const tables = new Set(activityRows.map((row) => row.entity_table));
      assert.ok(tables.has("meals"));
      assert.ok(tables.has("food_entries"));
      assert.ok(activityRows.every((row) => row.before_image === null));

      // Idempotent replay: same result, no new rows, no second batch.
      const replayResponse = await postAgentMeal(app, request);
      assert.equal(replayResponse.status, 200);
      const replayBody = await replayResponse.json();
      assert.equal(replayBody.duplicate, true);
      assert.deepEqual(
        replayBody.entries.map((entry) => entry.id),
        body.entries.map((entry) => entry.id)
      );

      const replayActivityRows = await database.sql`
        select id from activity_log where batch_id = ${request.idempotencyKey}
      `;
      assert.equal(replayActivityRows.length, 3);
      const replayEntryRows = await database.sql`
        select id from food_entries
        where id in (${request.entries[0].id}, ${request.entries[1].id})
      `;
      assert.equal(replayEntryRows.length, 2);

      // Hard reject on any item rolls back the whole batch.
      const invalidRequest = mealRequest({
        idempotencyKey: `agent-meal-invalid-${randomUUID()}`,
        mealId: "018f6a90-6d7f-7d63-bfc1-6f1025e0d300",
        entries: [
          referenceFoodEntry({ id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d301" }),
          quickEntry({
            id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d302",
            nutrients: {
              energy: { status: "complete", value: -1, entered: "-1", unit: "kilocalorie" }
            }
          })
        ]
      });
      const invalidResponse = await postAgentMeal(app, invalidRequest);
      assert.equal(invalidResponse.status, 422);

      const invalidMealRows = await database.sql`
        select id from meals where id = ${invalidRequest.meal.id}
      `;
      assert.equal(invalidMealRows.length, 0);
      const invalidEntryRows = await database.sql`
        select id from food_entries
        where id in (${invalidRequest.entries[0].id}, ${invalidRequest.entries[1].id})
      `;
      assert.equal(invalidEntryRows.length, 0);
      const invalidActivityRows = await database.sql`
        select id from activity_log where batch_id = ${invalidRequest.idempotencyKey}
      `;
      assert.equal(invalidActivityRows.length, 0);
    } finally {
      await database.close();
    }
  }
);

test("agent meal batch write resolves the nutrient snapshot server-side from a Food reference when nutrients are omitted", async () => {
  const writes = [];
  const app = createAgentMealApp({
    agentMealBatchWriteStore: {
      async writeMealBatch(input) {
        writes.push(input);
        return {
          duplicate: false,
          serverClock: "2026-07-04T05:00:01.000Z",
          applied: [
            { id: input.meal.id, updatedAt: input.meal.updatedAt, deviceId: input.deviceId },
            ...input.entries.map((entry) => ({
              id: entry.id,
              updatedAt: entry.updatedAt,
              deviceId: input.deviceId
            }))
          ]
        };
      }
    },
    agentFoodCatalogStore: {
      async getFoodById({ foodId }) {
        assert.equal(foodId, "food-banana");
        return {
          id: "food-banana",
          name: "Banana",
          foodSource: "user",
          nutrientsPer100: {
            energy: { status: "complete", value: 89, entered: "89", unit: "kilocalorie" },
            protein: { status: "complete", value: 1.1, entered: "1.1", unit: "gram" }
          },
          isLiquid: false,
          servingLabel: "medium",
          servingSize: 118,
          packageSize: null,
          isRecipe: false,
          recipeServingCount: null,
          updatedAt: "2026-07-01T00:00:00.000Z",
          deletedAt: null
        };
      }
    }
  });

  const request = mealRequest({
    idempotencyKey: "agent-meal-resolve-by-reference",
    entries: [
      {
        id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d001",
        position: 0,
        foodId: "food-banana",
        foodSource: "user",
        portion: { value: 2, entered: "2", unit: "serving" },
        updatedAt: "2026-06-24T05:00:00.000Z"
      }
    ]
  });

  const response = await postAgentMeal(app, request);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.entries[0].name, "Banana");
  assert.equal(body.entries[0].kind, "food");

  const foodPayload = writes[0].entries[0].payload;
  assert.equal(foodPayload.name, "Banana");
  assert.equal(foodPayload.food_id, "food-banana");
  assert.equal(foodPayload.food_source, "user");
  assert.equal(foodPayload.is_liquid, false);
  assert.equal(foodPayload.serving_size, 118);
  const portion = JSON.parse(foodPayload.portion_json);
  assert.deepEqual(portion, { value: 2, entered: "2", unit: "serving" });
  // The resolved per-100 vector is scaled by nothing here — the Food Entry
  // stores the SAME per-100 vector the Food carries (mirrors the app: the
  // Portion is resolved at read time, not baked into the stored vector).
  const storedNutrients = JSON.parse(foodPayload.nutrient_values_json);
  assert.equal(storedNutrients.energy.value, 89);
});

test("agent meal batch write hard-rejects a Food reference to a Food that does not exist or is not visible to the caller", async () => {
  const app = createAgentMealApp({
    agentMealBatchWriteStore: {
      async writeMealBatch() {
        throw new Error("writeMealBatch should not be called.");
      }
    },
    agentFoodCatalogStore: {
      async getFoodById() {
        return null;
      }
    }
  });

  const request = mealRequest({
    idempotencyKey: "agent-meal-resolve-missing",
    entries: [
      {
        id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d001",
        position: 0,
        foodId: "food-missing",
        foodSource: "user",
        portion: { value: 1, entered: "1", unit: "serving" },
        updatedAt: "2026-06-24T05:00:00.000Z"
      }
    ]
  });

  const response = await postAgentMeal(app, request);
  assert.equal(response.status, 422);
  const body = await response.json();
  assert.equal(body.errors[0].rule, "food_reference_not_found");
});

test("agent meal batch write still accepts an explicit nutrient vector for a Food reference, unchanged from the earlier behaviour", async () => {
  const writes = [];
  const app = createAgentMealApp({
    agentMealBatchWriteStore: {
      async writeMealBatch(input) {
        writes.push(input);
        return {
          duplicate: false,
          serverClock: "2026-06-24T05:00:01.000Z",
          applied: [
            { id: input.meal.id, updatedAt: input.meal.updatedAt, deviceId: input.deviceId },
            ...input.entries.map((entry) => ({
              id: entry.id,
              updatedAt: entry.updatedAt,
              deviceId: input.deviceId
            }))
          ]
        };
      }
    }
  });
  const request = mealRequest({
    idempotencyKey: "agent-meal-explicit-still-works",
    entries: [referenceFoodEntry()]
  });

  const response = await postAgentMeal(app, request);
  assert.equal(response.status, 200);
  assert.equal(writes.length, 1);
  assert.equal(writes[0].entries[0].payload.food_id, "food-banana");
});

test(
  "agent meal batch write archives a Meal and Food Entry as LWW tombstones with correct Activity Log before/after images",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-meal-archive-user-${randomUUID()}`;
    const app = createAgentMealApp({
      agentMealBatchWriteStore: createDrizzleAgentMealBatchWriteStore(
        database.db
      ),
      userId
    });
    const mealId = "018f6a90-6d7f-7d63-bfc1-6f1025e0d500";
    const entryId = "018f6a90-6d7f-7d63-bfc1-6f1025e0d501";
    const createRequest = mealRequest({
      idempotencyKey: `agent-meal-archive-create-${randomUUID()}`,
      mealId,
      entries: [quickEntry({ id: entryId })]
    });

    try {
      await database.db.insert(schema.user).values({
        id: userId,
        name: "Agent Meal Archive User",
        email: `${userId}@example.com`,
        emailVerified: true
      });

      const createResponse = await postAgentMeal(app, createRequest);
      assert.equal(createResponse.status, 200);

      const archivedAt = "2026-06-24T06:00:00.000Z";
      const archiveRequest = {
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
        entries: [quickEntry({ id: entryId, updatedAt: archivedAt, deletedAt: archivedAt })]
      };
      const archiveResponse = await postAgentMeal(app, archiveRequest);
      assert.equal(archiveResponse.status, 200);

      const archivedMealRows = await database.sql`
        select deleted_at, payload from meals where id = ${mealId}
      `;
      assert.notEqual(archivedMealRows[0].deleted_at, null);
      assert.equal(archivedMealRows[0].payload.deleted_at, archivedAt);

      const archivedEntryRows = await database.sql`
        select deleted_at, payload from food_entries where id = ${entryId}
      `;
      assert.notEqual(archivedEntryRows[0].deleted_at, null);
      assert.equal(archivedEntryRows[0].payload.deleted_at, archivedAt);

      const archiveActivityRows = await database.sql`
        select entity_table, before_image, after_image
        from activity_log
        where batch_id = ${archiveRequest.idempotencyKey}
        order by entity_table
      `;
      assert.equal(archiveActivityRows.length, 2);
      const mealActivity = archiveActivityRows.find(
        (row) => row.entity_table === "meals"
      );
      const entryActivity = archiveActivityRows.find(
        (row) => row.entity_table === "food_entries"
      );
      assert.equal(mealActivity.before_image.deleted_at, null);
      assert.equal(mealActivity.after_image.deleted_at, archivedAt);
      assert.equal(entryActivity.before_image.deleted_at, null);
      assert.equal(entryActivity.after_image.deleted_at, archivedAt);
    } finally {
      await database.close();
    }
  }
);

function createAgentMealApp({
  agentMealBatchWriteStore,
  agentFoodCatalogStore,
  logger = { info() {}, error() {} },
  syncNudgePublisher,
  userId = "user-1"
}) {
  return createApp({
    logger,
    agentApiKeyStore: createAgentKeyStore(userId),
    agentMealBatchWriteStore,
    agentFoodCatalogStore,
    syncNudgePublisher
  });
}

function createAgentKeyStore(userId) {
  return {
    async authenticateAgentApiKey(secret) {
      if (secret !== "prn_agent_secret") {
        return null;
      }

      return {
        userId,
        keyId: "agent-key-1",
        keyName: "Garage coach"
      };
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

function postAgentMeal(app, body, headers = {}) {
  return app.request("/agent/meals/batch-write", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_agent_secret",
      "content-type": "application/json",
      ...headers
    },
    body: JSON.stringify(body)
  });
}

function mealRequest({
  idempotencyKey,
  mealId = "018f6a90-6d7f-7d63-bfc1-6f1025e0d200",
  entries
}) {
  return {
    idempotencyKey,
    meal: {
      id: mealId,
      mealType: "Lunch",
      startedAt: "2026-06-24T05:00:00.000Z",
      endedAt: null,
      timezone: "Australia/Brisbane",
      localDate: "2026-06-24"
    },
    entries
  };
}

function referenceFoodEntry(overrides = {}) {
  return {
    id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d001",
    position: 0,
    name: "Banana",
    nutrients: {
      energy: { status: "complete", value: 89, entered: "89", unit: "kilocalorie" },
      protein: { status: "complete", value: 1.1, entered: "1.1", unit: "gram" },
      carbohydrate: { status: "complete", value: 23, entered: "23", unit: "gram" },
      fat: { status: "complete", value: 0.3, entered: "0.3", unit: "gram" }
    },
    isLiquid: false,
    foodId: "food-banana",
    foodSource: "usda",
    portion: { value: 2, entered: "2", unit: "serving" },
    servingLabel: "medium",
    servingSize: 118,
    packageSize: null,
    updatedAt: "2026-06-24T05:00:00.000Z",
    ...overrides
  };
}

function quickEntry(overrides = {}) {
  return {
    id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d002",
    position: 1,
    name: "Protein shake",
    nutrients: {
      energy: { status: "complete", value: 160, entered: "160", unit: "kilocalorie" },
      protein: { status: "complete", value: 30, entered: "30", unit: "gram" },
      carbohydrate: { status: "complete", value: 5, entered: "5", unit: "gram" },
      fat: { status: "complete", value: 2.5, entered: "2.5", unit: "gram" }
    },
    isLiquid: true,
    foodId: null,
    foodSource: null,
    portion: null,
    servingLabel: null,
    servingSize: null,
    packageSize: null,
    updatedAt: "2026-06-24T05:00:00.000Z",
    ...overrides
  };
}
