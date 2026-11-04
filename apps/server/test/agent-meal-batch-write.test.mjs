import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  applyMigrations,
  createApp,
  createDatabaseClient,
  createDrizzleAgentMealBatchWriteStore,
  prepareAgentMealBatchWrite,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;
const FAKE_NOW = new Date("2026-06-24T05:00:01.000Z");

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

test("agent meal batch write snapshots entries, returns warnings, and calls the write store once", async () => {
  const writes = [];
  const app = createAgentMealApp({
    agentMealBatchWriteStore: recordingMealStore(writes)
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
    agentMealBatchWriteStore: recordingMealStore(writes)
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
    agentMealBatchWriteStore: recordingMealStore(writes)
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
    agentMealBatchWriteStore: recordingMealStore(writes)
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
    agentMealBatchWriteStore: recordingMealStore(),
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
    agentMealBatchWriteStore: recordingMealStore(writes),
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
    agentMealBatchWriteStore: recordingMealStore(writes)
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

// ----- Partial writes: prepareAgentMealBatchWrite field rules (pure) -----

const USER = "user-1";
const MEAL_ID = "018f6a90-6d7f-7d63-bfc1-6f1025e0d800";

test("prepare: a create with only an IANA zone derives the offset and localDate", () => {
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({
      meal: {
        id: MEAL_ID,
        mealType: "Dinner",
        startedAt: "2026-06-24T15:30:00.000Z",
        timezone: "Australia/Brisbane"
      },
      entries: [quickEntry()]
    }),
    emptyStored(),
    FAKE_NOW_LATER
  );

  assert.equal(prepared.accepted, true);
  assert.deepEqual(prepared.meal.payload, {
    id: MEAL_ID,
    meal_type: "Dinner",
    started_at: "2026-06-24T15:30:00.000Z",
    timezone: "Australia/Brisbane",
    local_date: "2026-06-25",
    ended_at: null,
    updated_at: FAKE_NOW_LATER.toISOString(),
    deleted_at: null,
    timezone_offset_minutes: 600,
    time_precision: "instant"
  });
  assert.equal(prepared.meal.updatedAt, FAKE_NOW_LATER.toISOString());
  assert.equal(prepared.entries.length, 1);
  assert.equal(prepared.entries[0].payload.meal_id, MEAL_ID);
  assert.equal(prepared.entries[0].deletedAt, null);
});

test("prepare: a sent offset wins over the zone, ignores a sent localDate, and labels an offset-only zone", () => {
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({
      meal: {
        id: MEAL_ID,
        mealType: "Lunch",
        startedAt: "2026-06-24T23:30:00.000Z",
        timezoneOffsetMinutes: -180,
        localDate: "2030-01-01"
      }
    }),
    emptyStored(),
    FAKE_NOW_LATER
  );

  assert.equal(prepared.accepted, true);
  assert.equal(prepared.meal.payload.timezone_offset_minutes, -180);
  assert.equal(prepared.meal.payload.local_date, "2026-06-24");
  assert.equal(prepared.meal.payload.timezone, "UTC-03:00");
});

test("prepare: a create with only an abbreviation and a localDate stores a null offset and that date", () => {
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({
      meal: {
        id: MEAL_ID,
        mealType: "Dinner",
        startedAt: "2026-06-25T01:00:00.000Z",
        timezone: "BRT",
        localDate: "2026-06-24"
      }
    }),
    emptyStored(),
    FAKE_NOW_LATER
  );

  assert.equal(prepared.accepted, true);
  assert.equal(prepared.meal.payload.timezone, "BRT");
  assert.equal(prepared.meal.payload.timezone_offset_minutes, null);
  assert.equal(prepared.meal.payload.local_date, "2026-06-24");
});

test("prepare: an abbreviation without localDate is 422 meal_offset_unknown", () => {
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({
      meal: {
        id: MEAL_ID,
        mealType: "Dinner",
        startedAt: "2026-06-25T01:00:00.000Z",
        timezone: "BRT"
      }
    }),
    emptyStored(),
    FAKE_NOW_LATER
  );

  assert.equal(prepared.accepted, false);
  assert.equal(prepared.status, 422);
  assert.deepEqual(rules(prepared.errors), ["meal_offset_unknown"]);
  assert.equal(prepared.errors[0].field, "meal.localDate");
  assert.equal(prepared.errors[0].itemIndex, null);
  assert.equal(prepared.errors[0].entryId, null);
  assert.equal(prepared.errors[0].nutrient, null);
});

test("prepare: a create without mealType or without the time block is 422 meal_create_incomplete", () => {
  const noType = prepareAgentMealBatchWrite(
    resolvedRequest({
      meal: {
        id: MEAL_ID,
        startedAt: "2026-06-24T05:00:00.000Z",
        timezone: "Australia/Brisbane"
      }
    }),
    emptyStored(),
    FAKE_NOW_LATER
  );
  assert.equal(noType.accepted, false);
  assert.equal(noType.status, 422);
  assert.deepEqual(rules(noType.errors), ["meal_create_incomplete"]);
  assert.equal(noType.errors[0].field, "meal.mealType");

  const noTime = prepareAgentMealBatchWrite(
    resolvedRequest({ meal: { id: MEAL_ID, mealType: "Lunch" } }),
    emptyStored(),
    FAKE_NOW_LATER
  );
  assert.equal(noTime.accepted, false);
  assert.equal(noTime.status, 422);
  assert.deepEqual(rules(noTime.errors), ["meal_create_incomplete"]);
  assert.equal(noTime.errors[0].field, "meal.startedAt");
});

test("prepare: a zero-entry create writes the Meal alone", () => {
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({
      meal: {
        id: MEAL_ID,
        mealType: "Snack",
        startedAt: "2026-06-24T05:00:00.000Z",
        timezone: "Australia/Brisbane"
      }
    }),
    emptyStored(),
    FAKE_NOW_LATER
  );

  assert.equal(prepared.accepted, true);
  assert.equal(prepared.meal.id, MEAL_ID);
  assert.deepEqual(prepared.entries, []);
  assert.deepEqual(prepared.warnings, []);
});

test("prepare: an update with only the time block moves the derived localDate across midnight and keeps the other fields", () => {
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({
      meal: {
        id: MEAL_ID,
        startedAt: "2026-06-24T23:10:00.000Z",
        timezoneOffsetMinutes: 60
      }
    }),
    storedState({
      meal: storedRow(USER, {
        id: MEAL_ID,
        meal_type: "Dinner",
        started_at: "2026-06-24T22:50:00.000Z",
        timezone: "BST",
        local_date: "2026-06-24",
        ended_at: null,
        updated_at: "2026-06-24T22:55:00.000Z",
        deleted_at: null,
        timezone_offset_minutes: 60,
        time_precision: "instant",
        later_key: "kept"
      })
    }),
    FAKE_NOW_LATER
  );

  assert.equal(prepared.accepted, true);
  assert.equal(prepared.meal.payload.started_at, "2026-06-24T23:10:00.000Z");
  assert.equal(prepared.meal.payload.local_date, "2026-06-25");
  assert.equal(prepared.meal.payload.timezone_offset_minutes, 60);
  assert.equal(prepared.meal.payload.timezone, "UTC+01:00");
  assert.equal(prepared.meal.payload.meal_type, "Dinner");
  assert.equal(prepared.meal.payload.later_key, "kept");
  assert.equal(prepared.meal.payload.updated_at, FAKE_NOW_LATER.toISOString());
});

test("prepare: an update without the time block keeps it, and a legacy payload reads as instant with a null offset", () => {
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({ meal: { id: MEAL_ID, mealType: "Brunch" } }),
    storedState({
      meal: storedRow(USER, {
        id: MEAL_ID,
        meal_type: "Breakfast",
        started_at: "2026-06-24T01:00:00.000Z",
        timezone: "AEST",
        local_date: "2026-06-24",
        ended_at: null,
        updated_at: "2026-06-24T01:00:00.000Z",
        deleted_at: null
      })
    }),
    FAKE_NOW_LATER
  );

  assert.equal(prepared.accepted, true);
  assert.equal(prepared.meal.payload.meal_type, "Brunch");
  assert.equal(prepared.meal.payload.started_at, "2026-06-24T01:00:00.000Z");
  assert.equal(prepared.meal.payload.timezone, "AEST");
  assert.equal(prepared.meal.payload.local_date, "2026-06-24");
  assert.equal(prepared.meal.payload.timezone_offset_minutes, null);
  assert.equal(prepared.meal.payload.time_precision, "instant");
});

test("prepare: timePrecision may be sent alone, and sending startedAt resets it to instant unless sent", () => {
  const stored = storedState({ meal: storedRow(USER, legacyMealPayload()) });
  const dateOnly = prepareAgentMealBatchWrite(
    resolvedRequest({ meal: { id: MEAL_ID, timePrecision: "date" } }),
    stored,
    FAKE_NOW_LATER
  );
  assert.equal(dateOnly.meal.payload.time_precision, "date");

  const retimed = prepareAgentMealBatchWrite(
    resolvedRequest({
      meal: {
        id: MEAL_ID,
        startedAt: "2026-06-24T02:00:00.000Z",
        timezone: "Australia/Brisbane"
      }
    }),
    storedState({
      meal: storedRow(USER, { ...legacyMealPayload(), time_precision: "date" })
    }),
    FAKE_NOW_LATER
  );
  assert.equal(retimed.meal.payload.time_precision, "instant");
});

test("prepare: null clears endedAt; an absent endedAt keeps it", () => {
  const stored = storedState({
    meal: storedRow(USER, {
      ...legacyMealPayload(),
      ended_at: "2026-06-24T01:30:00.000Z"
    })
  });
  const cleared = prepareAgentMealBatchWrite(
    resolvedRequest({ meal: { id: MEAL_ID, endedAt: null } }),
    stored,
    FAKE_NOW_LATER
  );
  assert.equal(cleared.accepted, true);
  assert.equal(cleared.meal.payload.ended_at, null);

  const kept = prepareAgentMealBatchWrite(
    resolvedRequest({ meal: { id: MEAL_ID, mealType: "Lunch" } }),
    stored,
    FAKE_NOW_LATER
  );
  assert.equal(kept.meal.payload.ended_at, "2026-06-24T01:30:00.000Z");
});

test("prepare: an end before the start is 422 meal_ended_before_start at Meal level", () => {
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({ meal: { id: MEAL_ID, endedAt: "2026-06-24T00:30:00.000Z" } }),
    storedState({ meal: storedRow(USER, legacyMealPayload()) }),
    FAKE_NOW_LATER
  );

  assert.equal(prepared.accepted, false);
  assert.equal(prepared.status, 422);
  assert.deepEqual(rules(prepared.errors), ["meal_ended_before_start"]);
  assert.equal(prepared.errors[0].field, "meal.endedAt");
  assert.equal(prepared.errors[0].itemIndex, null);
});

test("prepare: an entries-only request for a stored Meal leaves the Meal row unwritten", () => {
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({ meal: { id: MEAL_ID }, entries: [quickEntry()] }),
    storedState({ meal: storedRow(USER, legacyMealPayload()) }),
    FAKE_NOW_LATER
  );

  assert.equal(prepared.accepted, true);
  assert.equal(prepared.meal, null);
  assert.equal(prepared.entries.length, 1);
  assert.equal(prepared.entries[0].payload.meal_id, MEAL_ID);
});

test("prepare: an entries-only request for an unknown Meal id is 404 meal_not_found", () => {
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({ meal: { id: MEAL_ID }, entries: [quickEntry()] }),
    emptyStored(),
    FAKE_NOW_LATER
  );

  assert.equal(prepared.accepted, false);
  assert.equal(prepared.status, 404);
  assert.deepEqual(rules(prepared.errors), ["meal_not_found"]);
  assert.equal(prepared.errors[0].field, "meal.id");
});

test("prepare: an unsent entry deletedAt keeps the stored value; null for a new entry", () => {
  const archivedAt = "2026-06-24T06:00:00.000Z";
  const stored = storedState({
    meal: storedRow(USER, legacyMealPayload()),
    entries: [
      [
        "entry-stored",
        storedRow(
          USER,
          { id: "entry-stored", meal_id: MEAL_ID, deleted_at: archivedAt },
          archivedAt
        )
      ]
    ]
  });
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({
      meal: { id: MEAL_ID },
      entries: [quickEntry({ id: "entry-stored" }), quickEntry({ id: "entry-new" })]
    }),
    stored,
    FAKE_NOW_LATER
  );

  assert.equal(prepared.accepted, true);
  assert.equal(prepared.entries[0].deletedAt, archivedAt);
  assert.equal(prepared.entries[0].payload.deleted_at, archivedAt);
  assert.equal(prepared.entries[1].deletedAt, null);
  // Import keys are never added here: the sync carry-forward keeps them.
  assert.equal("import_source" in prepared.entries[0].payload, false);
});

test("prepare: active entries into an archived Meal are 422 meal_archived, accepted when the request sends deletedAt: null", () => {
  const archivedAt = "2026-06-24T06:00:00.000Z";
  const stored = storedState({
    meal: storedRow(
      USER,
      { ...legacyMealPayload(), deleted_at: archivedAt },
      archivedAt
    )
  });

  const rejected = prepareAgentMealBatchWrite(
    resolvedRequest({ meal: { id: MEAL_ID }, entries: [quickEntry()] }),
    stored,
    FAKE_NOW_LATER
  );
  assert.equal(rejected.accepted, false);
  assert.equal(rejected.status, 422);
  assert.deepEqual(rules(rejected.errors), ["meal_archived"]);
  assert.equal(rejected.errors[0].field, "meal.deletedAt");

  const archivedEntry = prepareAgentMealBatchWrite(
    resolvedRequest({
      meal: { id: MEAL_ID },
      entries: [quickEntry({ deletedAt: archivedAt })]
    }),
    stored,
    FAKE_NOW_LATER
  );
  assert.equal(archivedEntry.accepted, true);

  const unarchived = prepareAgentMealBatchWrite(
    resolvedRequest({ meal: { id: MEAL_ID, deletedAt: null }, entries: [quickEntry()] }),
    stored,
    FAKE_NOW_LATER
  );
  assert.equal(unarchived.accepted, true);
  assert.equal(unarchived.meal.deletedAt, null);
  assert.equal(unarchived.meal.payload.deleted_at, null);
  assert.equal(unarchived.entries.length, 1);
});

test("prepare: archiving a Meal with a stored active entry missing from the request is 422 meal_archived", () => {
  const archivedAt = "2026-06-25T11:00:00.000Z";
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({ meal: { id: MEAL_ID, deletedAt: archivedAt } }),
    storedState({
      meal: storedRow(USER, legacyMealPayload()),
      activeEntryIds: ["entry-active"]
    }),
    FAKE_NOW_LATER
  );

  assert.equal(prepared.accepted, false);
  assert.equal(prepared.status, 422);
  assert.deepEqual(rules(prepared.errors), ["meal_archived"]);
  assert.equal(prepared.errors[0].field, "meal.deletedAt");
  assert.match(prepared.errors[0].message, /entry-active/);
});

test("prepare: archiving a Meal is accepted when the request tombstones every stored active entry", () => {
  const archivedAt = "2026-06-25T11:00:00.000Z";
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({
      meal: { id: MEAL_ID, deletedAt: archivedAt },
      entries: [quickEntry({ id: "entry-active", deletedAt: archivedAt })]
    }),
    storedState({
      meal: storedRow(USER, legacyMealPayload()),
      entries: [
        ["entry-active", storedRow(USER, { id: "entry-active", meal_id: MEAL_ID })]
      ],
      activeEntryIds: ["entry-active"]
    }),
    FAKE_NOW_LATER
  );

  assert.equal(prepared.accepted, true);
  assert.equal(prepared.meal.deletedAt, archivedAt);
  assert.equal(prepared.meal.payload.deleted_at, archivedAt);
  assert.equal(prepared.entries.length, 1);
  assert.equal(prepared.entries[0].id, "entry-active");
  assert.equal(prepared.entries[0].deletedAt, archivedAt);
  assert.equal(prepared.entries[0].payload.deleted_at, archivedAt);
});

test("prepare: an entry sent without deletedAt keeps its stored null and does not count as tombstoned", () => {
  const archivedAt = "2026-06-25T11:00:00.000Z";
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({
      meal: { id: MEAL_ID, deletedAt: archivedAt },
      entries: [quickEntry({ id: "entry-active" })]
    }),
    storedState({
      meal: storedRow(USER, legacyMealPayload()),
      entries: [
        ["entry-active", storedRow(USER, { id: "entry-active", meal_id: MEAL_ID })]
      ],
      activeEntryIds: ["entry-active"]
    }),
    FAKE_NOW_LATER
  );

  assert.equal(prepared.accepted, false);
  assert.equal(prepared.status, 422);
  assert.ok(rules(prepared.errors).every((rule) => rule === "meal_archived"));
  assert.ok(
    prepared.errors.some((issue) => /not tombstoned: entry-active/.test(issue.message))
  );
});

test("prepare: archiving a Meal with no stored active entries is accepted", () => {
  const archivedAt = "2026-06-25T11:00:00.000Z";
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({ meal: { id: MEAL_ID, deletedAt: archivedAt } }),
    storedState({ meal: storedRow(USER, legacyMealPayload()) }),
    FAKE_NOW_LATER
  );

  assert.equal(prepared.accepted, true);
  assert.equal(prepared.meal.deletedAt, archivedAt);
  assert.deepEqual(prepared.entries, []);
});

test("prepare: a Meal-fields-only edit of an archived Meal that still holds stored active entries is 422 meal_archived", () => {
  const archivedAt = "2026-06-24T06:00:00.000Z";
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({ meal: { id: MEAL_ID, mealType: "Lunch" } }),
    storedState({
      meal: storedRow(
        USER,
        { ...legacyMealPayload(), deleted_at: archivedAt },
        archivedAt
      ),
      activeEntryIds: ["entry-b", "entry-a"]
    }),
    FAKE_NOW_LATER
  );

  assert.equal(prepared.accepted, false);
  assert.equal(prepared.status, 422);
  assert.deepEqual(rules(prepared.errors), ["meal_archived"]);
  assert.equal(prepared.errors[0].field, "meal.deletedAt");
  assert.match(prepared.errors[0].message, /not tombstoned: entry-a, entry-b\.$/);
});

test("prepare: un-archiving a Meal with stored active entries is accepted", () => {
  const archivedAt = "2026-06-24T06:00:00.000Z";
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({ meal: { id: MEAL_ID, deletedAt: null } }),
    storedState({
      meal: storedRow(
        USER,
        { ...legacyMealPayload(), deleted_at: archivedAt },
        archivedAt
      ),
      activeEntryIds: ["entry-active"]
    }),
    FAKE_NOW_LATER
  );

  assert.equal(prepared.accepted, true);
  assert.equal(prepared.meal.deletedAt, null);
});

test("prepare: another account's Meal id and entry id are 409, ahead of 404 and 422 issues", () => {
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({
      meal: { id: MEAL_ID },
      entries: [quickEntry({ id: "entry-mine-elsewhere" }), quickEntry({ id: "entry-theirs" })]
    }),
    storedState({
      meal: storedRow("user-2", legacyMealPayload()),
      entries: [
        [
          "entry-mine-elsewhere",
          storedRow(USER, { id: "entry-mine-elsewhere", meal_id: "other-meal" })
        ],
        ["entry-theirs", storedRow("user-2", { id: "entry-theirs", meal_id: MEAL_ID })]
      ]
    }),
    FAKE_NOW_LATER
  );

  assert.equal(prepared.accepted, false);
  assert.equal(prepared.status, 409);
  assert.deepEqual(rules(prepared.errors), ["meal_id_conflict", "entry_id_conflict"]);
  assert.equal(prepared.errors[0].itemIndex, null);
  assert.equal(prepared.errors[1].itemIndex, 1);
  assert.equal(prepared.errors[1].entryId, "entry-theirs");

  const entryOnly = prepareAgentMealBatchWrite(
    resolvedRequest({
      meal: { id: MEAL_ID },
      entries: [quickEntry({ id: "entry-theirs" })]
    }),
    storedState({
      meal: null,
      entries: [["entry-theirs", storedRow("user-2", { id: "entry-theirs", meal_id: "x" })]]
    }),
    FAKE_NOW_LATER
  );
  assert.equal(entryOnly.status, 409);
  assert.deepEqual(rules(entryOnly.errors), ["entry_id_conflict"]);
});

test("prepare: an existing entry under a different Meal is 422 entry_meal_mismatch", () => {
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({
      meal: { id: MEAL_ID },
      entries: [quickEntry(), quickEntry({ id: "entry-elsewhere" })]
    }),
    storedState({
      meal: storedRow(USER, legacyMealPayload()),
      entries: [
        ["entry-elsewhere", storedRow(USER, { id: "entry-elsewhere", meal_id: "other-meal" })]
      ]
    }),
    FAKE_NOW_LATER
  );

  assert.equal(prepared.accepted, false);
  assert.equal(prepared.status, 422);
  assert.deepEqual(rules(prepared.errors), ["entry_meal_mismatch"]);
  assert.equal(prepared.errors[0].itemIndex, 1);
  assert.equal(prepared.errors[0].entryId, "entry-elsewhere");
  assert.equal(prepared.errors[0].field, "entries[1].id");
});

test("prepare: a future startedAt is a top-level Meal warning and still writes", () => {
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({
      meal: {
        id: MEAL_ID,
        mealType: "Dinner",
        startedAt: "2026-06-24T06:00:00.000Z",
        timezone: "Australia/Brisbane"
      }
    }),
    emptyStored(),
    FAKE_NOW
  );

  assert.equal(prepared.accepted, true);
  assert.deepEqual(rules(prepared.warnings), ["meal_time_in_future"]);
  assert.equal(prepared.warnings[0].field, "meal.startedAt");
  assert.equal(prepared.warnings[0].limit, 5);
  assert.equal(prepared.warnings[0].itemIndex, null);
});

test("prepare: an entries-only request into a future-started stored Meal returns the top-level warning", () => {
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({ meal: { id: MEAL_ID }, entries: [quickEntry()] }),
    storedState({
      meal: storedRow(USER, {
        ...legacyMealPayload(),
        started_at: "2026-06-24T05:20:00.000Z"
      })
    }),
    FAKE_NOW
  );

  assert.equal(prepared.accepted, true);
  assert.equal(prepared.meal, null);
  assert.equal(prepared.entries.length, 1);
  assert.deepEqual(rules(prepared.warnings), ["meal_time_in_future"]);
  assert.equal(prepared.warnings[0].field, "meal.startedAt");
  assert.equal(prepared.warnings[0].itemIndex, null);
});

test("prepare: an entries-only request into a stored Meal that breaks a hard rule is 422", () => {
  const prepared = prepareAgentMealBatchWrite(
    resolvedRequest({ meal: { id: MEAL_ID }, entries: [quickEntry()] }),
    storedState({
      meal: storedRow(USER, {
        ...legacyMealPayload(),
        meal_type: "",
        ended_at: "2026-06-24T00:30:00.000Z"
      })
    }),
    FAKE_NOW_LATER
  );

  assert.equal(prepared.accepted, false);
  assert.equal(prepared.status, 422);
  assert.deepEqual(rules(prepared.errors).sort(), [
    "meal_ended_before_start",
    "meal_type_required"
  ]);
  assert.equal(prepared.errors[0].itemIndex, null);
});

// ----- Partial writes: request shape (400) and route mapping -----

test("agent meal batch write rejects malformed partial requests with 400 before authentication", async () => {
  const app = createAgentMealApp({
    agentMealBatchWriteStore: {
      async writeMealBatch() {
        throw new Error("writeMealBatch should not be called.");
      }
    }
  });
  const cases = [
    { name: "id only, no entries", meal: { id: MEAL_ID }, entries: [] },
    {
      name: "startedAt without offset or timezone",
      meal: { id: MEAL_ID, mealType: "Lunch", startedAt: "2026-06-24T05:00:00.000Z" },
      entries: []
    },
    { name: "offset without startedAt", meal: { id: MEAL_ID, timezoneOffsetMinutes: 60 }, entries: [] },
    { name: "localDate without startedAt", meal: { id: MEAL_ID, localDate: "2026-06-24" }, entries: [] },
    { name: "timezone without startedAt", meal: { id: MEAL_ID, timezone: "Australia/Brisbane" }, entries: [] },
    {
      name: "offset out of range",
      meal: {
        id: MEAL_ID,
        mealType: "Lunch",
        startedAt: "2026-06-24T05:00:00.000Z",
        timezoneOffsetMinutes: 900
      },
      entries: []
    },
    {
      name: "malformed localDate",
      meal: {
        id: MEAL_ID,
        mealType: "Lunch",
        startedAt: "2026-06-24T05:00:00.000Z",
        timezone: "BRT",
        localDate: "2026-13-01"
      },
      entries: []
    }
  ];

  for (const { name, meal, entries } of cases) {
    const body = { idempotencyKey: `agent-meal-400-${name}`, meal, entries };
    const response = await postAgentMeal(app, body);
    assert.equal(response.status, 400, name);
    const unauthenticated = await app.request("/agent/meals/batch-write", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body)
    });
    assert.equal(unauthenticated.status, 400, `${name} (no key)`);
  }
});

test("agent meal batch write accepts timePrecision or endedAt alone", async () => {
  const writes = [];
  const app = createAgentMealApp({
    agentMealBatchWriteStore: {
      async writeMealBatch(input) {
        writes.push(input);
        return {
          status: "written",
          duplicate: false,
          serverClock: "2026-06-24T05:00:01.000Z",
          applied: [],
          warnings: []
        };
      }
    }
  });

  for (const meal of [
    { id: MEAL_ID, timePrecision: "date" },
    { id: MEAL_ID, endedAt: null },
    { id: MEAL_ID, deletedAt: null },
    { id: MEAL_ID, mealType: "Supper" }
  ]) {
    const response = await postAgentMeal(app, {
      idempotencyKey: `agent-meal-alone-${Object.keys(meal)[1]}`,
      meal,
      entries: []
    });
    assert.equal(response.status, 200, JSON.stringify(meal));
  }
  assert.equal(writes.length, 4);
  // Absent fields stay absent: nothing is defaulted before the store.
  assert.equal("endedAt" in writes[0].request.meal, false);
  assert.equal("deletedAt" in writes[0].request.meal, false);
});

test("agent meal batch write maps a store rejection to its HTTP status and returns Meal warnings on success", async () => {
  const issue = (rule) => ({
    field: "meal.id",
    nutrient: null,
    rule,
    message: rule,
    limit: null,
    itemIndex: null,
    entryId: null
  });
  for (const [httpStatus, rule] of [
    [404, "meal_not_found"],
    [409, "meal_id_conflict"],
    [422, "meal_archived"]
  ]) {
    const nudges = [];
    const app = createAgentMealApp({
      agentMealBatchWriteStore: {
        async writeMealBatch() {
          return { status: "rejected", httpStatus, errors: [issue(rule)], warnings: [] };
        }
      },
      syncNudgePublisher: {
        async enqueueSyncNudge(input) {
          nudges.push(input);
          return { enqueued: true, jobId: "unexpected" };
        }
      }
    });
    const response = await postAgentMeal(app, {
      idempotencyKey: `agent-meal-reject-${httpStatus}`,
      meal: { id: MEAL_ID },
      entries: [quickEntry()]
    });
    assert.equal(response.status, httpStatus);
    const body = await response.json();
    assert.equal(body.code, "agent_meal_batch_write_failed");
    assert.deepEqual(rules(body.errors), [rule]);
    assert.equal(body.errors[0].itemIndex, null);
    assert.ok(body.limits);
    assert.deepEqual(nudges, []);
  }

  const app = createAgentMealApp({ agentMealBatchWriteStore: recordingMealStore([]) });
  const response = await postAgentMeal(app, {
    idempotencyKey: "agent-meal-future-warning",
    meal: {
      id: MEAL_ID,
      mealType: "Dinner",
      startedAt: "2026-06-24T06:00:00.000Z",
      timezone: "Australia/Brisbane"
    },
    entries: []
  });
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.deepEqual(rules(body.warnings), ["meal_time_in_future"]);
  assert.deepEqual(body.entries, []);
});

// ----- Partial writes against Postgres -----

test(
  "agent meal batch write creates a zero-entry Meal from an IANA zone, then an entries-only request leaves the Meal row untouched (CUJ 7)",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await withMealDatabase(async ({ database, app }) => {
      const mealId = randomUUID();
      const create = await postAgentMeal(app, {
        idempotencyKey: `agent-meal-cuj7-create-${randomUUID()}`,
        meal: {
          id: mealId,
          mealType: "Dinner",
          startedAt: "2026-06-24T11:40:00.000Z",
          timezone: "Australia/Brisbane"
        },
        entries: []
      });
      assert.equal(create.status, 200);
      const createBody = await create.json();
      assert.deepEqual(createBody.entries, []);
      assert.deepEqual(createBody.warnings, []);

      // The phone moves the Meal to 12:30 and syncs: modelled by a time edit.
      const retime = await postAgentMeal(app, {
        idempotencyKey: `agent-meal-cuj7-retime-${randomUUID()}`,
        meal: {
          id: mealId,
          startedAt: "2026-06-24T02:30:00.000Z",
          timezoneOffsetMinutes: 600
        },
        entries: []
      });
      assert.equal(retime.status, 200);

      const [before] = await database.sql`
        select payload, updated_at from meals where id = ${mealId}
      `;
      assert.equal(before.payload.local_date, "2026-06-24");
      assert.equal(before.payload.timezone_offset_minutes, 600);
      assert.equal(before.payload.started_at, "2026-06-24T02:30:00.000Z");
      assert.equal(before.payload.meal_type, "Dinner");

      const addKey = `agent-meal-cuj7-add-${randomUUID()}`;
      const coffeeId = randomUUID();
      const add = await postAgentMeal(app, {
        idempotencyKey: addKey,
        meal: { id: mealId },
        entries: [quickEntry({ id: coffeeId, name: "Coffee" })]
      });
      assert.equal(add.status, 200);
      const addBody = await add.json();
      assert.equal(addBody.entries[0].id, coffeeId);

      const [after] = await database.sql`
        select payload, updated_at from meals where id = ${mealId}
      `;
      assert.deepEqual(after.payload, before.payload);
      assert.equal(String(after.updated_at), String(before.updated_at));

      const activity = await database.sql`
        select entity_table from activity_log where batch_id = ${addKey}
      `;
      assert.deepEqual(
        activity.map((row) => row.entity_table),
        ["food_entries"]
      );
      const [entry] = await database.sql`
        select payload from food_entries where id = ${coffeeId}
      `;
      assert.equal(entry.payload.meal_id, mealId);

      // Idempotent replay of the entries-only request.
      const replay = await postAgentMeal(app, {
        idempotencyKey: addKey,
        meal: { id: mealId },
        entries: [quickEntry({ id: coffeeId, name: "Coffee" })]
      });
      assert.equal(replay.status, 200);
      assert.equal((await replay.json()).duplicate, true);

      // An entries-only request for an id that doesn't exist.
      const missing = await postAgentMeal(app, {
        idempotencyKey: `agent-meal-cuj7-missing-${randomUUID()}`,
        meal: { id: randomUUID() },
        entries: [quickEntry({ id: randomUUID() })]
      });
      assert.equal(missing.status, 404);
      assert.deepEqual(rules((await missing.json()).errors), ["meal_not_found"]);
    });
  }
);

test(
  "agent meal batch write keeps an unsent entry deletedAt and the stored import keys, and null clears endedAt",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await withMealDatabase(async ({ database, app }) => {
      const mealId = randomUUID();
      const entryId = randomUUID();
      const archivedAt = "2026-06-24T06:00:00.000Z";
      const create = await postAgentMeal(app, {
        idempotencyKey: `agent-meal-keys-create-${randomUUID()}`,
        meal: {
          id: mealId,
          mealType: "Lunch",
          startedAt: "2026-06-24T02:00:00.000Z",
          endedAt: "2026-06-24T02:30:00.000Z",
          timezone: "Australia/Brisbane"
        },
        entries: [quickEntry({ id: entryId, deletedAt: archivedAt, updatedAt: archivedAt })]
      });
      assert.equal(create.status, 200);
      await database.sql`
        update food_entries
        set payload = payload || ${JSON.stringify({
          import_source: "myFitnessPal",
          import_external_id: "mfp-row-1"
        })}::jsonb
        where id = ${entryId}
      `;

      const update = await postAgentMeal(app, {
        idempotencyKey: `agent-meal-keys-update-${randomUUID()}`,
        meal: { id: mealId, endedAt: null },
        entries: [
          quickEntry({ id: entryId, name: "Protein shake (large)", updatedAt: "2026-06-24T07:00:00.000Z" })
        ]
      });
      assert.equal(update.status, 200);

      const [entry] = await database.sql`
        select payload, deleted_at from food_entries where id = ${entryId}
      `;
      assert.equal(entry.payload.name, "Protein shake (large)");
      assert.equal(entry.payload.deleted_at, archivedAt);
      assert.notEqual(entry.deleted_at, null);
      assert.equal(entry.payload.import_source, "myFitnessPal");
      assert.equal(entry.payload.import_external_id, "mfp-row-1");

      const [meal] = await database.sql`
        select payload from meals where id = ${mealId}
      `;
      assert.equal(meal.payload.ended_at, null);
      assert.equal(meal.payload.meal_type, "Lunch");
      assert.equal(meal.payload.started_at, "2026-06-24T02:00:00.000Z");
    });
  }
);

test(
  "agent meal batch write refuses active entries into an archived Meal until the same request un-archives it",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await withMealDatabase(async ({ database, app }) => {
      const mealId = randomUUID();
      const create = await postAgentMeal(app, {
        idempotencyKey: `agent-meal-archived-create-${randomUUID()}`,
        meal: {
          id: mealId,
          mealType: "Lunch",
          startedAt: "2026-06-24T02:00:00.000Z",
          timezone: "Australia/Brisbane"
        },
        entries: []
      });
      assert.equal(create.status, 200);
      const archive = await postAgentMeal(app, {
        idempotencyKey: `agent-meal-archived-archive-${randomUUID()}`,
        meal: { id: mealId, deletedAt: "2026-06-24T06:00:00.000Z" },
        entries: []
      });
      assert.equal(archive.status, 200);

      const entryId = randomUUID();
      const rejectedKey = `agent-meal-archived-add-${randomUUID()}`;
      const rejected = await postAgentMeal(app, {
        idempotencyKey: rejectedKey,
        meal: { id: mealId },
        entries: [quickEntry({ id: entryId })]
      });
      assert.equal(rejected.status, 422);
      assert.deepEqual(rules((await rejected.json()).errors), ["meal_archived"]);
      assert.equal(
        (await database.sql`select id from food_entries where id = ${entryId}`).length,
        0
      );
      assert.equal(
        (await database.sql`select id from activity_log where batch_id = ${rejectedKey}`).length,
        0
      );

      const accepted = await postAgentMeal(app, {
        idempotencyKey: `agent-meal-archived-unarchive-${randomUUID()}`,
        meal: { id: mealId, deletedAt: null },
        entries: [quickEntry({ id: entryId })]
      });
      assert.equal(accepted.status, 200);
      const [meal] = await database.sql`
        select deleted_at, payload from meals where id = ${mealId}
      `;
      assert.equal(meal.deleted_at, null);
      assert.equal(meal.payload.deleted_at, null);
      assert.equal(
        (await database.sql`select id from food_entries where id = ${entryId}`).length,
        1
      );
    });
  }
);

test(
  "agent meal batch write archives a Meal only when the request tombstones its stored active entries",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await withMealDatabase(async ({ database, app }) => {
      const mealId = randomUUID();
      const firstId = randomUUID();
      const secondId = randomUUID();
      const create = await postAgentMeal(app, {
        idempotencyKey: `agent-meal-archive-tombstones-create-${randomUUID()}`,
        meal: {
          id: mealId,
          mealType: "Lunch",
          startedAt: "2026-06-24T02:00:00.000Z",
          timezone: "Australia/Brisbane"
        },
        entries: [
          quickEntry({ id: firstId, position: 1 }),
          quickEntry({ id: secondId, position: 2 })
        ]
      });
      assert.equal(create.status, 200);

      // Another account's Food Entry that names this Meal id never blocks
      // the archive: the rule reads only the caller's rows.
      const otherUserId = `agent-meal-partial-other-${randomUUID()}`;
      await insertUser(database, otherUserId);
      const otherEntryId = randomUUID();
      await database.db.insert(schema.foodEntries).values({
        id: otherEntryId,
        userId: otherUserId,
        deviceId: "other-device",
        payload: { id: otherEntryId, meal_id: mealId, deleted_at: null },
        updatedAt: new Date("2026-06-24T05:00:00.000Z"),
        deletedAt: null
      });

      const archivedAt = "2026-06-24T06:00:00.000Z";
      const rejectedKey = `agent-meal-archive-tombstones-partial-${randomUUID()}`;
      const rejected = await postAgentMeal(app, {
        idempotencyKey: rejectedKey,
        meal: { id: mealId, deletedAt: archivedAt },
        entries: [
          quickEntry({ id: firstId, position: 1, deletedAt: archivedAt, updatedAt: archivedAt })
        ]
      });
      assert.equal(rejected.status, 422);
      const rejectedBody = await rejected.json();
      assert.deepEqual(rules(rejectedBody.errors), ["meal_archived"]);
      assert.match(rejectedBody.errors[0].message, new RegExp(secondId));
      assert.doesNotMatch(rejectedBody.errors[0].message, new RegExp(otherEntryId));
      const [mealAfterReject] = await database.sql`
        select deleted_at from meals where id = ${mealId}
      `;
      assert.equal(mealAfterReject.deleted_at, null);
      const activeAfterReject = await database.sql`
        select id from food_entries
        where id in (${firstId}, ${secondId}) and deleted_at is null
      `;
      assert.equal(activeAfterReject.length, 2);
      assert.equal(
        (await database.sql`select id from activity_log where batch_id = ${rejectedKey}`).length,
        0
      );

      const acceptedKey = `agent-meal-archive-tombstones-all-${randomUUID()}`;
      const accepted = await postAgentMeal(app, {
        idempotencyKey: acceptedKey,
        meal: { id: mealId, deletedAt: archivedAt },
        entries: [
          quickEntry({ id: firstId, position: 1, deletedAt: archivedAt, updatedAt: archivedAt }),
          quickEntry({ id: secondId, position: 2, deletedAt: archivedAt, updatedAt: archivedAt })
        ]
      });
      assert.equal(accepted.status, 200);
      const [mealAfterAccept] = await database.sql`
        select deleted_at from meals where id = ${mealId}
      `;
      assert.notEqual(mealAfterAccept.deleted_at, null);
      const activeAfterAccept = await database.sql`
        select id from food_entries
        where id in (${firstId}, ${secondId}) and deleted_at is null
      `;
      assert.equal(activeAfterAccept.length, 0);
      assert.equal(
        (await database.sql`select id from activity_log where batch_id = ${acceptedKey}`).length,
        3
      );
      const [otherEntry] = await database.sql`
        select deleted_at from food_entries where id = ${otherEntryId}
      `;
      assert.equal(otherEntry.deleted_at, null);
    });
  }
);

test(
  "agent meal batch write returns 409 for another account's Meal or entry id and 422 for an entry under a different Meal",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await withMealDatabase(async ({ database, app, userId }) => {
      const mealId = randomUUID();
      const entryId = randomUUID();
      const create = await postAgentMeal(app, {
        idempotencyKey: `agent-meal-conflict-create-${randomUUID()}`,
        meal: {
          id: mealId,
          mealType: "Lunch",
          startedAt: "2026-06-24T02:00:00.000Z",
          timezone: "Australia/Brisbane"
        },
        entries: [quickEntry({ id: entryId })]
      });
      assert.equal(create.status, 200);

      // The same account, moving the entry to another Meal.
      const moved = await postAgentMeal(app, {
        idempotencyKey: `agent-meal-conflict-move-${randomUUID()}`,
        meal: {
          id: randomUUID(),
          mealType: "Dinner",
          startedAt: "2026-06-24T09:00:00.000Z",
          timezone: "Australia/Brisbane"
        },
        entries: [quickEntry({ id: entryId, updatedAt: "2026-06-24T09:00:00.000Z" })]
      });
      assert.equal(moved.status, 422);
      const movedBody = await moved.json();
      assert.deepEqual(rules(movedBody.errors), ["entry_meal_mismatch"]);
      assert.equal(movedBody.errors[0].entryId, entryId);

      // Another account.
      const otherUserId = `agent-meal-other-${randomUUID()}`;
      await insertUser(database, otherUserId);
      const otherApp = createAgentMealApp({
        agentMealBatchWriteStore: createDrizzleAgentMealBatchWriteStore(database.db),
        userId: otherUserId
      });
      const mealConflict = await postAgentMeal(otherApp, {
        idempotencyKey: `agent-meal-conflict-meal-${randomUUID()}`,
        meal: { id: mealId, mealType: "Hijack" },
        entries: []
      });
      assert.equal(mealConflict.status, 409);
      assert.deepEqual(rules((await mealConflict.json()).errors), ["meal_id_conflict"]);

      const entryConflict = await postAgentMeal(otherApp, {
        idempotencyKey: `agent-meal-conflict-entry-${randomUUID()}`,
        meal: {
          id: randomUUID(),
          mealType: "Lunch",
          startedAt: "2026-06-24T02:00:00.000Z",
          timezone: "Australia/Brisbane"
        },
        entries: [quickEntry({ id: entryId })]
      });
      assert.equal(entryConflict.status, 409);
      const entryConflictBody = await entryConflict.json();
      assert.deepEqual(rules(entryConflictBody.errors), ["entry_id_conflict"]);
      assert.equal(entryConflictBody.errors[0].itemIndex, 0);

      const [meal] = await database.sql`
        select user_id, payload from meals where id = ${mealId}
      `;
      assert.equal(meal.user_id, userId);
      assert.equal(meal.payload.meal_type, "Lunch");
    });
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

const FAKE_NOW_LATER = new Date("2026-06-25T12:00:00.000Z");

/**
 * A fake store that applies the pure field rules against empty stored state,
 * so route tests see the prepared rows without Postgres. Stored-state rules
 * are covered by the prepareAgentMealBatchWrite unit tests and the DB tests.
 */
function recordingMealStore(writes = [], { now = FAKE_NOW } = {}) {
  return {
    async writeMealBatch(input) {
      const prepared = prepareAgentMealBatchWrite(
        input.request,
        { userId: input.userId, meal: null, entries: new Map(), activeEntryIds: new Set() },
        now
      );
      writes.push({
        ...input,
        meal: prepared.accepted ? prepared.meal : null,
        entries: prepared.accepted ? prepared.entries : []
      });
      if (!prepared.accepted) {
        return {
          status: "rejected",
          httpStatus: prepared.status,
          errors: prepared.errors,
          warnings: prepared.warnings
        };
      }
      return {
        status: "written",
        duplicate: false,
        serverClock: now.toISOString(),
        applied: [...(prepared.meal === null ? [] : [prepared.meal]), ...prepared.entries].map(
          (row) => ({ id: row.id, updatedAt: row.updatedAt, deviceId: input.deviceId })
        ),
        warnings: prepared.warnings
      };
    }
  };
}

async function withMealDatabase(body) {
  await applyMigrations(databaseUrl);
  const database = createDatabaseClient(databaseUrl);
  const userId = `agent-meal-partial-${randomUUID()}`;
  const app = createAgentMealApp({
    agentMealBatchWriteStore: createDrizzleAgentMealBatchWriteStore(database.db),
    userId
  });
  try {
    await insertUser(database, userId);
    await body({ database, app, userId });
  } finally {
    await database.close();
  }
}

async function insertUser(database, userId) {
  await database.db.insert(schema.user).values({
    id: userId,
    name: "Agent Meal Partial User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
}

function rules(issues) {
  return issues.map((issue) => issue.rule);
}

/** A request as resolveAgentMealBatchEntries returns it (entries resolved). */
function resolvedRequest({ meal, entries = [] }) {
  return { idempotencyKey: "agent-meal-prepare", meal, entries };
}

function emptyStored() {
  return storedState({ meal: null });
}

function storedState({ meal, entries = [], activeEntryIds = [] }) {
  return {
    userId: USER,
    meal,
    entries: new Map(entries),
    activeEntryIds: new Set(activeEntryIds)
  };
}

function storedRow(userId, payload, deletedAt = null) {
  return { userId, payload, deletedAt };
}

function legacyMealPayload() {
  return {
    id: MEAL_ID,
    meal_type: "Breakfast",
    started_at: "2026-06-24T01:00:00.000Z",
    timezone: "AEST",
    local_date: "2026-06-24",
    ended_at: null,
    updated_at: "2026-06-24T01:00:00.000Z",
    deleted_at: null
  };
}
