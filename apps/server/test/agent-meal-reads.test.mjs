import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  applyMigrations,
  createApp,
  createDatabaseClient,
  createDrizzleAgentNutritionReadStore,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

test(
  "agent meals read returns a bounded raw meal + entry list over a date range, limit/cursor/fields",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-meals-read-user-${randomUUID()}`;
    const mealIds = { first: randomUUID(), second: randomUUID(), third: randomUUID() };
    const app = createAgentMealReadApp({
      agentNutritionReadStore: createDrizzleAgentNutritionReadStore(database.db),
      userId
    });

    try {
      await seedUser(database, userId);

      await seedMeal(database, {
        userId,
        id: mealIds.first,
        mealType: "Breakfast",
        startedAt: "2026-06-01T07:00:00.000Z",
        localDate: "2026-06-01",
        entries: [
          entryPayload({ id: randomUUID(), mealId: mealIds.first, name: "Oats", position: 0 })
        ]
      });
      await seedMeal(database, {
        userId,
        id: mealIds.second,
        mealType: "Lunch",
        startedAt: "2026-06-08T12:00:00.000Z",
        localDate: "2026-06-08",
        entries: [
          entryPayload({ id: randomUUID(), mealId: mealIds.second, name: "Chicken", position: 0 }),
          entryPayload({ id: randomUUID(), mealId: mealIds.second, name: "Rice", position: 1 })
        ]
      });
      // Outside the requested range.
      await seedMeal(database, {
        userId,
        id: mealIds.third,
        mealType: "Dinner",
        startedAt: "2026-07-01T19:00:00.000Z",
        localDate: "2026-07-01",
        entries: [
          entryPayload({ id: randomUUID(), mealId: mealIds.third, name: "Salad", position: 0 })
        ]
      });

      const defaultResponse = await getAgent(
        app,
        "/agent/meals?from=2026-06-01T00:00:00.000Z&to=2026-06-30T00:00:00.000Z"
      );
      assert.equal(defaultResponse.status, 200);
      const defaultBody = await defaultResponse.json();
      assert.equal(defaultBody.totalMatched, 2);
      assert.equal(defaultBody.limit, 50);
      // Minimal default fields.
      assert.deepEqual(defaultBody.fields, ["id", "mealType", "startedAt"]);
      const firstMeal = defaultBody.meals.find((meal) => meal.id === mealIds.first);
      assert.ok(firstMeal, "meal 1 should be present");
      assert.equal(firstMeal.entries, undefined);

      const projectedResponse = await getAgent(
        app,
        "/agent/meals?from=2026-06-01T00:00:00.000Z&to=2026-06-30T00:00:00.000Z&fields=id,mealType,startedAt,localDate,entries"
      );
      assert.equal(projectedResponse.status, 200);
      const projectedBody = await projectedResponse.json();
      const secondMeal = projectedBody.meals.find((meal) => meal.id === mealIds.second);
      assert.equal(secondMeal.localDate, "2026-06-08");
      assert.equal(secondMeal.entries.length, 2);
      assert.deepEqual(
        secondMeal.entries.map((entry) => entry.name).sort(),
        ["Chicken", "Rice"]
      );

      // limit + cursor pagination.
      const pagedFirst = await getAgent(
        app,
        "/agent/meals?from=2026-06-01T00:00:00.000Z&to=2026-06-30T00:00:00.000Z&limit=1"
      );
      const pagedFirstBody = await pagedFirst.json();
      assert.equal(pagedFirstBody.meals.length, 1);
      assert.ok(pagedFirstBody.nextCursor);

      const pagedSecond = await getAgent(
        app,
        `/agent/meals?from=2026-06-01T00:00:00.000Z&to=2026-06-30T00:00:00.000Z&limit=1&cursor=${pagedFirstBody.nextCursor}`
      );
      const pagedSecondBody = await pagedSecond.json();
      assert.equal(pagedSecondBody.meals.length, 1);
      assert.equal(pagedSecondBody.nextCursor, null);
      assert.notEqual(pagedSecondBody.meals[0].id, pagedFirstBody.meals[0].id);
    } finally {
      await database.close();
    }
  }
);

test(
  "agent meals read excludes archived (tombstoned) meals/entries and isolates by account",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-meals-read-tenant-user-${randomUUID()}`;
    const otherUserId = `agent-meals-read-other-user-${randomUUID()}`;
    const liveMealId = randomUUID();
    const archivedMealId = randomUUID();
    const app = createAgentMealReadApp({
      agentNutritionReadStore: createDrizzleAgentNutritionReadStore(database.db),
      userId
    });

    try {
      await seedUser(database, userId);
      await seedUser(database, otherUserId);

      await seedMeal(database, {
        userId,
        id: liveMealId,
        mealType: "Breakfast",
        startedAt: "2026-06-10T07:00:00.000Z",
        localDate: "2026-06-10",
        entries: [
          entryPayload({ id: randomUUID(), mealId: liveMealId, name: "Oats", position: 0 })
        ]
      });
      await seedMeal(database, {
        userId,
        id: archivedMealId,
        mealType: "Lunch",
        startedAt: "2026-06-10T12:00:00.000Z",
        localDate: "2026-06-10",
        deletedAt: "2026-06-10T13:00:00.000Z",
        entries: [
          entryPayload({ id: randomUUID(), mealId: archivedMealId, name: "Soup", position: 0 })
        ]
      });
      await seedMeal(database, {
        userId: otherUserId,
        id: randomUUID(),
        mealType: "Breakfast",
        startedAt: "2026-06-10T07:00:00.000Z",
        localDate: "2026-06-10",
        entries: [
          entryPayload({ id: randomUUID(), mealId: randomUUID(), name: "Other user's food", position: 0 })
        ]
      });

      const response = await getAgent(
        app,
        "/agent/meals?from=2026-06-01T00:00:00.000Z&to=2026-06-30T00:00:00.000Z"
      );
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.totalMatched, 1);
      assert.equal(body.meals[0].id, liveMealId);
    } finally {
      await database.close();
    }
  }
);

function createAgentMealReadApp({
  agentNutritionReadStore,
  logger = { info() {}, error() {} },
  userId = "user-1"
}) {
  return createApp({
    logger,
    agentApiKeyStore: createAgentKeyStore(userId),
    agentNutritionReadStore
  });
}

function createAgentKeyStore(userId) {
  return {
    async authenticateAgentApiKey(secret) {
      if (secret !== "prn_agent_secret") {
        return null;
      }

      return { userId, keyId: "agent-meals-read-key-1", keyName: "Garage coach" };
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

function getAgent(app, path) {
  return app.request(path, {
    headers: { authorization: "Bearer prn_agent_secret" }
  });
}

async function seedUser(database, userId) {
  await database.db.insert(schema.user).values({
    id: userId,
    name: "Agent Meals Read User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
}

async function seedMeal(
  { db },
  { userId, id, mealType, startedAt, localDate, deletedAt = null, entries }
) {
  await db.insert(schema.meals).values({
    id,
    userId,
    deviceId: "device-agent-meals-read-test",
    updatedAt: new Date(startedAt),
    receivedAt: new Date(startedAt),
    deletedAt: deletedAt === null ? null : new Date(deletedAt),
    payload: {
      id,
      meal_type: mealType,
      started_at: startedAt,
      ended_at: null,
      timezone: "Australia/Brisbane",
      local_date: localDate,
      updated_at: startedAt,
      deleted_at: deletedAt
    }
  });

  for (const entry of entries) {
    await db.insert(schema.foodEntries).values({
      id: entry.id,
      userId,
      deviceId: "device-agent-meals-read-test",
      updatedAt: new Date(startedAt),
      receivedAt: new Date(startedAt),
      deletedAt: deletedAt === null ? null : new Date(deletedAt),
      payload: {
        ...entry.payload,
        deleted_at: deletedAt
      }
    });
  }
}

function entryPayload({ id, mealId, name, position }) {
  return {
    id,
    payload: {
      id,
      meal_id: mealId,
      entry_kind: "quickEntry",
      position,
      name,
      nutrient_values_json: JSON.stringify({
        energy: { status: "complete", value: 100, entered: "100", unit: "kilocalorie" }
      }),
      food_id: null,
      portion_json: null,
      food_source: null,
      is_liquid: false,
      serving_label: null,
      serving_size: null,
      package_size: null,
      updated_at: "2026-06-01T07:00:00.000Z"
    }
  };
}
