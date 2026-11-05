import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";

import {
  applyMigrations,
  createAgentMcpServer,
  createApp,
  createDatabaseClient,
  createDrizzleAgentMealHistoryReadStore,
  schema
} from "../src/index.ts";
import { buildMealHistory } from "../src/meal-history.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

const DAY_MS = 24 * 60 * 60 * 1000;

test(
  "agent Meal History returns the caller's repeated meals, matching buildMealHistory",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-meal-history-user-${randomUUID()}`;
    const otherUserId = `agent-meal-history-other-${randomUUID()}`;
    const store = createDrizzleAgentMealHistoryReadStore(database.db);
    const app = createApp({
      logger: { info() {}, error() {} },
      agentApiKeyStore: createAgentKeyStore(userId),
      agentMealHistoryReadStore: store
    });
    const { client, close } = await createMcpClient(
      createAgentMcpServer({
        agentApiKeyStore: createAgentKeyStore(userId),
        agentMealHistoryReadStore: store,
        logger: { info() {}, error() {} }
      })
    );
    const prefix = randomUUID();
    const oatMilk = `oat-milk-${prefix}`;
    const porridge = `porridge-${prefix}`;
    const banana = `banana-${prefix}`;
    const toast = `toast-${prefix}`;
    const archivedBar = `archived-bar-${prefix}`;
    const now = Date.now();
    // The rows as buildMealHistory reads them, kept alongside the seeding so
    // the route's answer can be compared with the pure function's.
    const meals = [];
    const entries = [];

    async function meal({ owner = userId, daysAgo, timePrecision }) {
      const id = randomUUID();
      const startedAt = new Date(now - daysAgo * DAY_MS);
      await seedMeal(database, { userId: owner, id, startedAt, timePrecision });
      if (owner === userId) {
        meals.push({
          id,
          startedAt: startedAt.toISOString(),
          timePrecision,
          deletedAt: null
        });
      }
      return id;
    }

    async function entry({ owner = userId, mealId, position, foodSource, foodId, name }) {
      const id = await seedEntry(database, {
        userId: owner,
        mealId,
        position,
        foodSource,
        foodId,
        name
      });
      if (owner === userId) {
        entries.push({
          id,
          mealId,
          kind: "food",
          position,
          foodSource,
          foodId,
          isLiquid: false,
          name,
          deletedAt: null
        });
      }
    }

    try {
      await seedUser(database, userId);
      await seedUser(database, otherUserId);
      // Porridge with oat milk on three mornings, the latest with new names.
      for (const [daysAgo, porridgeName] of [
        [5, "Porridge"],
        [4, "Porridge"],
        [3, "Porridge oats"]
      ]) {
        const mealId = await meal({ daysAgo });
        await entry({ mealId, position: 0, foodSource: "user", foodId: porridge, name: porridgeName });
        await entry({ mealId, position: 1, foodSource: "openFoodFacts", foodId: oatMilk, name: "Oat milk" });
      }
      // Banana on toast once, more recently, and once before the window.
      for (const daysAgo of [1, 91]) {
        const mealId = await meal({ daysAgo });
        await entry({ mealId, position: 0, foodSource: "usda", foodId: banana, name: "Banana, raw" });
        await entry({ mealId, position: 1, foodSource: "user", foodId: toast, name: "Toast" });
      }
      // A payload written before Meals carried a time precision reads as instant.
      const legacyMealId = await meal({ daysAgo: 2 });
      await entry({ mealId: legacyMealId, position: 0, foodSource: "usda", foodId: banana, name: "Banana, raw" });
      await entry({ mealId: legacyMealId, position: 1, foodSource: "openFoodFacts", foodId: oatMilk, name: "Oat milk" });
      // A date-only Meal never counts.
      const dateMealId = await meal({ daysAgo: 2, timePrecision: "date" });
      await entry({ mealId: dateMealId, position: 0, foodSource: "user", foodId: porridge, name: "Porridge" });
      await entry({ mealId: dateMealId, position: 1, foodSource: "user", foodId: toast, name: "Toast" });
      // An archived User Food leaves the Meal with one Food: it doesn't qualify.
      const archivedFoodMealId = await meal({ daysAgo: 1 });
      await entry({ mealId: archivedFoodMealId, position: 0, foodSource: "user", foodId: toast, name: "Toast" });
      await entry({ mealId: archivedFoodMealId, position: 1, foodSource: "user", foodId: archivedBar, name: "Old protein bar" });
      await seedFood(database, { userId, id: archivedBar, deletedAt: new Date(now) });
      // Another user's meals never show, though they repeat more often.
      for (const daysAgo of [1, 2, 3, 4]) {
        const mealId = await meal({ owner: otherUserId, daysAgo: daysAgo / 2 });
        await entry({ owner: otherUserId, mealId, position: 0, foodSource: "user", foodId: `other-a-${prefix}`, name: "Other A" });
        await entry({ owner: otherUserId, mealId, position: 1, foodSource: "user", foodId: `other-b-${prefix}`, name: "Other B" });
      }

      const response = await getAgent(app, "/agent/meals/history");
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.deepEqual(Object.keys(body), ["items"]);
      assert.deepEqual(
        body.items.map((item) => [item.foods.map((food) => food.foodId), item.count]),
        [
          [[oatMilk, porridge], 3],
          [[banana, toast], 1],
          [[oatMilk, banana], 1]
        ]
      );
      assert.deepEqual(body.items[0].foods, [
        { foodSource: "openFoodFacts", foodId: oatMilk, name: "Oat milk" },
        { foodSource: "user", foodId: porridge, name: "Porridge oats" }
      ]);
      assert.equal(typeof body.items[0].lastMealId, "string");
      // Whole seconds, as the app stores them.
      assert.equal(
        body.items[0].lastStartedAt,
        new Date(Math.floor((now - 3 * DAY_MS) / 1000) * 1000).toISOString()
      );
      for (const item of body.items) {
        for (const food of item.foods) {
          assert.ok(!food.foodId.startsWith("other-"), "another user's Food was returned");
        }
      }

      // The route answers what the pure function computes over the same rows.
      const expected = buildMealHistory(
        { meals, entries, archivedUserFoodIds: [archivedBar] },
        { now: new Date(now), limit: 20 }
      );
      assert.deepEqual(body.items, expected);

      const limited = await getAgent(app, "/agent/meals/history?limit=1");
      assert.equal(limited.status, 200);
      const limitedBody = await limited.json();
      assert.deepEqual(limitedBody.items, body.items.slice(0, 1));

      const atMaximum = await getAgent(app, "/agent/meals/history?limit=50");
      assert.equal(atMaximum.status, 200);
      assert.deepEqual((await atMaximum.json()).items, body.items);

      const overMaximum = await getAgent(app, "/agent/meals/history?limit=51");
      assert.equal(overMaximum.status, 400);
      const belowMinimum = await getAgent(app, "/agent/meals/history?limit=0");
      assert.equal(belowMinimum.status, 400);

      const unauthorized = await app.request("/agent/meals/history");
      assert.equal(unauthorized.status, 401);
      const wrongKey = await app.request("/agent/meals/history", {
        headers: { authorization: "Bearer prn_agent_wrong" }
      });
      assert.equal(wrongKey.status, 401);

      const mcpResponse = await client.callTool({
        name: "agent_list_meal_history",
        arguments: { apiKey: "prn_agent_secret" }
      });
      assert.equal(mcpResponse.isError, undefined, JSON.stringify(mcpResponse.content));
      assert.deepEqual(mcpResponse.structuredContent, body);

      const mcpLimited = await client.callTool({
        name: "agent_list_meal_history",
        arguments: { apiKey: "prn_agent_secret", limit: 1 }
      });
      assert.deepEqual(mcpLimited.structuredContent, limitedBody);

      // The other user sees only their own meal.
      const otherApp = createApp({
        logger: { info() {}, error() {} },
        agentApiKeyStore: createAgentKeyStore(otherUserId),
        agentMealHistoryReadStore: store
      });
      const otherBody = await (await getAgent(otherApp, "/agent/meals/history")).json();
      assert.deepEqual(
        otherBody.items.map((item) => [item.foods.map((food) => food.foodId), item.count]),
        [[[`other-a-${prefix}`, `other-b-${prefix}`], 4]]
      );
    } finally {
      await close();
      await database.close();
    }
  }
);

test("agent Meal History defaults limit to 20 and passes it to the store", async () => {
  const calls = [];
  const store = {
    async listMealHistory(input) {
      calls.push(input);
      return { items: [] };
    }
  };
  const app = createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore("user-1"),
    agentMealHistoryReadStore: store
  });
  const response = await getAgent(app, "/agent/meals/history");
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { items: [] });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].userId, "user-1");
  assert.equal(calls[0].limit, 20);
  assert.ok(calls[0].now instanceof Date);

  const atMaximum = await getAgent(app, "/agent/meals/history?limit=50");
  assert.equal(atMaximum.status, 200);
  assert.equal(calls[1].limit, 50);

  const overMaximum = await getAgent(app, "/agent/meals/history?limit=51");
  assert.equal(overMaximum.status, 400);
  assert.equal(calls.length, 2);

  const unauthorized = await app.request("/agent/meals/history");
  assert.equal(unauthorized.status, 401);
  assert.equal(calls.length, 2);

  const { client, close } = await createMcpClient(
    createAgentMcpServer({
      agentApiKeyStore: createAgentKeyStore("user-1"),
      agentMealHistoryReadStore: store,
      logger: { info() {}, error() {} }
    })
  );
  try {
    const mcpResponse = await client.callTool({
      name: "agent_list_meal_history",
      arguments: { apiKey: "prn_agent_secret" }
    });
    assert.deepEqual(mcpResponse.structuredContent, { items: [] });
    assert.equal(calls[2].limit, 20);

    const mcpOverMaximum = await client.callTool({
      name: "agent_list_meal_history",
      arguments: { apiKey: "prn_agent_secret", limit: 51 }
    });
    assert.equal(mcpOverMaximum.isError, true);
    assert.equal(calls.length, 3);
  } finally {
    await close();
  }
});

test("agent Meal History without its store answers 503 on REST and MCP", async () => {
  const app = createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore("user-1")
  });
  const response = await getAgent(app, "/agent/meals/history");
  assert.equal(response.status, 503);
  assert.equal((await response.json()).code, "agent_nutrition_read_unavailable");

  const { client, close } = await createMcpClient(
    createAgentMcpServer({
      agentApiKeyStore: createAgentKeyStore("user-1"),
      logger: { info() {}, error() {} }
    })
  );
  try {
    const mcpResponse = await client.callTool({
      name: "agent_list_meal_history",
      arguments: { apiKey: "prn_agent_secret" }
    });
    assert.equal(mcpResponse.isError, true);
    assert.equal(
      mcpResponse.structuredContent?.code ??
        JSON.parse(mcpResponse.content[0].text).code,
      "agent_nutrition_read_unavailable"
    );
  } finally {
    await close();
  }
});

async function createMcpClient(server) {
  const client = new Client(
    { name: "agent-meal-history-test-client", version: "0.0.0" },
    { capabilities: {} }
  );
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await Promise.all([server.connect(serverTransport), client.connect(clientTransport)]);
  return {
    client,
    async close() {
      await Promise.all([client.close(), server.close()]);
    }
  };
}

function createAgentKeyStore(userId) {
  return {
    async authenticateAgentApiKey(secret) {
      if (secret !== "prn_agent_secret") {
        return null;
      }
      return { userId, keyId: "agent-meal-history-key-1", keyName: "Kitchen coach" };
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
    name: "Agent Meal History User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
}

async function seedMeal({ db }, { userId, id, startedAt, timePrecision }) {
  const payload = {
    id,
    meal_type: "Breakfast",
    started_at: startedAt.toISOString(),
    ended_at: null,
    timezone: "UTC",
    local_date: startedAt.toISOString().slice(0, 10),
    updated_at: startedAt.toISOString(),
    deleted_at: null
  };
  // Leaving the key out stands for a payload written before Meals carried
  // a time precision.
  if (timePrecision !== undefined) {
    payload.timezone_offset_minutes = 0;
    payload.time_precision = timePrecision;
  }
  await db.insert(schema.meals).values({
    id,
    userId,
    deviceId: "device-agent-meal-history-test",
    updatedAt: startedAt,
    receivedAt: startedAt,
    payload
  });
}

async function seedEntry({ db }, { userId, mealId, foodSource, foodId, name, position }) {
  const id = randomUUID();
  const updatedAt = new Date();
  await db.insert(schema.foodEntries).values({
    id,
    userId,
    deviceId: "device-agent-meal-history-test",
    updatedAt,
    receivedAt: updatedAt,
    payload: {
      id,
      meal_id: mealId,
      entry_kind: "food",
      position,
      name,
      nutrient_values_json: JSON.stringify({
        energy: { status: "complete", value: 100, entered: "100", unit: "kilocalorie" }
      }),
      food_id: foodId,
      portion_json: JSON.stringify({ value: 100, entered: "100", unit: "gram" }),
      food_source: foodSource,
      is_liquid: false,
      serving_label: null,
      serving_size: null,
      package_size: null,
      updated_at: updatedAt.toISOString(),
      deleted_at: null
    }
  });
  return id;
}

async function seedFood({ db }, { userId, id, deletedAt }) {
  await db.insert(schema.foods).values({
    id,
    userId,
    deviceId: "device-agent-meal-history-test",
    updatedAt: deletedAt,
    receivedAt: deletedAt,
    deletedAt,
    payload: {
      id,
      name: "Old protein bar",
      food_source: "user",
      updated_at: deletedAt.toISOString(),
      deleted_at: deletedAt.toISOString()
    }
  });
}
