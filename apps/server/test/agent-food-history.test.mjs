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
  createDrizzleAgentFoodHistoryReadStore,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

const DAY_MS = 24 * 60 * 60 * 1000;

test(
  "agent Food History returns the caller's Foods in picker order, bounded by limit",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-food-history-user-${randomUUID()}`;
    const otherUserId = `agent-food-history-other-${randomUUID()}`;
    const store = createDrizzleAgentFoodHistoryReadStore(database.db);
    const app = createApp({
      logger: { info() {}, error() {} },
      agentApiKeyStore: createAgentKeyStore(userId),
      agentFoodHistoryReadStore: store
    });
    const { client, close } = await createMcpClient(
      createAgentMcpServer({
        agentApiKeyStore: createAgentKeyStore(userId),
        agentFoodHistoryReadStore: store,
        logger: { info() {}, error() {} }
      })
    );
    const prefix = randomUUID();
    const oatMilk = `oat-milk-${prefix}`;
    const banana = `banana-${prefix}`;
    const archivedBar = `archived-bar-${prefix}`;
    const now = Date.now();

    try {
      await seedUser(database, userId);
      await seedUser(database, otherUserId);
      // Oat milk on three recent mornings; banana once, more recently.
      for (const daysAgo of [3, 2, 1]) {
        const mealId = randomUUID();
        await seedMeal(database, { userId, id: mealId, startedAt: now - daysAgo * DAY_MS });
        await seedEntry(database, {
          userId,
          mealId,
          foodSource: "openFoodFacts",
          foodId: oatMilk,
          name: "Oat milk",
          portion: { value: 250, entered: "250", unit: "milliliter" },
          isLiquid: true
        });
      }
      const recentMealId = randomUUID();
      await seedMeal(database, { userId, id: recentMealId, startedAt: now - DAY_MS / 2 });
      await seedEntry(database, {
        userId,
        mealId: recentMealId,
        foodSource: "usda",
        foodId: banana,
        name: "Banana, raw",
        portion: { value: 118, entered: "118", unit: "gram" }
      });
      // An archived User Food: its entry stays, but it is not offered.
      await seedEntry(database, {
        userId,
        mealId: recentMealId,
        position: 1,
        foodSource: "user",
        foodId: archivedBar,
        name: "Old protein bar",
        portion: { value: 60, entered: "60", unit: "gram" }
      });
      await seedFood(database, { userId, id: archivedBar, deletedAt: new Date(now) });
      // Another user's Food never shows.
      const otherMealId = randomUUID();
      await seedMeal(database, { userId: otherUserId, id: otherMealId, startedAt: now });
      await seedEntry(database, {
        userId: otherUserId,
        mealId: otherMealId,
        foodSource: "usda",
        foodId: `other-${prefix}`,
        name: "Other user's food",
        portion: null
      });

      const response = await getAgent(app, "/agent/foods/history");
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.limit, 50);
      assert.equal(body.totalMatched, 2);
      assert.deepEqual(
        body.items.map((item) => [item.foodSource, item.foodId, item.recentCount]),
        [
          ["openFoodFacts", oatMilk, 3],
          ["usda", banana, 1]
        ]
      );
      assert.equal(body.items[0].lastLoggedName, "Oat milk");
      assert.deepEqual(body.items[0].lastPortion, {
        value: 250,
        entered: "250",
        unit: "milliliter"
      });
      // Whole seconds, as the app stores them.
      assert.equal(
        body.items[0].lastLoggedAt,
        new Date(Math.floor((now - DAY_MS) / 1000) * 1000).toISOString()
      );

      const limited = await getAgent(app, "/agent/foods/history?limit=1");
      assert.equal(limited.status, 200);
      const limitedBody = await limited.json();
      assert.equal(limitedBody.limit, 1);
      assert.equal(limitedBody.totalMatched, 2);
      assert.deepEqual(
        limitedBody.items.map((item) => item.foodId),
        [oatMilk]
      );

      const unauthorized = await app.request("/agent/foods/history");
      assert.equal(unauthorized.status, 401);

      const mcpResponse = await client.callTool({
        name: "agent_list_food_history",
        arguments: { apiKey: "prn_agent_secret" }
      });
      assert.equal(mcpResponse.isError, undefined, JSON.stringify(mcpResponse.content));
      assert.deepEqual(mcpResponse.structuredContent, body);

      const mcpLimited = await client.callTool({
        name: "agent_list_food_history",
        arguments: { apiKey: "prn_agent_secret", limit: 1 }
      });
      assert.deepEqual(mcpLimited.structuredContent, limitedBody);
    } finally {
      await close();
      await database.close();
    }
  }
);

test("agent Food History without its store answers 503 on REST and MCP", async () => {
  const app = createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore("user-1")
  });
  const response = await getAgent(app, "/agent/foods/history");
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
      name: "agent_list_food_history",
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
    { name: "agent-food-history-test-client", version: "0.0.0" },
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
      return { userId, keyId: "agent-food-history-key-1", keyName: "Kitchen coach" };
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
    name: "Agent Food History User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
}

async function seedMeal({ db }, { userId, id, startedAt }) {
  const started = new Date(startedAt);
  await db.insert(schema.meals).values({
    id,
    userId,
    deviceId: "device-agent-food-history-test",
    updatedAt: started,
    receivedAt: started,
    payload: {
      id,
      meal_type: "Breakfast",
      started_at: started.toISOString(),
      ended_at: null,
      timezone: "UTC",
      local_date: started.toISOString().slice(0, 10),
      updated_at: started.toISOString(),
      deleted_at: null
    }
  });
}

async function seedEntry(
  { db },
  { userId, mealId, foodSource, foodId, name, portion, position = 0, isLiquid = false }
) {
  const id = randomUUID();
  const updatedAt = new Date();
  await db.insert(schema.foodEntries).values({
    id,
    userId,
    deviceId: "device-agent-food-history-test",
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
      portion_json: portion === null ? null : JSON.stringify(portion),
      food_source: foodSource,
      is_liquid: isLiquid,
      serving_label: null,
      serving_size: null,
      package_size: null,
      updated_at: updatedAt.toISOString(),
      deleted_at: null
    }
  });
}

async function seedFood({ db }, { userId, id, deletedAt }) {
  await db.insert(schema.foods).values({
    id,
    userId,
    deviceId: "device-agent-food-history-test",
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
