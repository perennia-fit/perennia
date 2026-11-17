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
  createDrizzleAgentMealTypesReadStore,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

test(
  "agent Meal Types lists the caller's active Meal Types by sortOrder then id",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-meal-types-user-${randomUUID()}`;
    const otherUserId = `agent-meal-types-other-${randomUUID()}`;
    const store = createDrizzleAgentMealTypesReadStore(database.db);
    const app = createApp({
      logger: { info() {}, error() {} },
      agentApiKeyStore: createAgentKeyStore(userId),
      agentMealTypesReadStore: store
    });
    const { client, close } = await createMcpClient(
      createAgentMcpServer({
        agentApiKeyStore: createAgentKeyStore(userId),
        agentMealTypesReadStore: store,
        logger: { info() {}, error() {} }
      })
    );

    try {
      await seedUser(database, userId);
      await seedUser(database, otherUserId);
      // Inserted out of order; two share sortOrder 1, so id breaks the tie.
      await seedMealType(database, { userId, id: "mt-dinner", name: "Dinner", sortOrder: 2 });
      await seedMealType(database, { userId, id: "mt-lunch-b", name: "Pre-workout", sortOrder: 1 });
      await seedMealType(database, { userId, id: "mt-breakfast", name: "Breakfast", sortOrder: 0 });
      await seedMealType(database, { userId, id: "mt-lunch-a", name: "Lunch", sortOrder: 1 });
      // An archived Meal Type is left out.
      await seedMealType(database, {
        userId,
        id: "mt-archived",
        name: "Second breakfast",
        sortOrder: 0,
        deletedAt: new Date()
      });
      // Another user's Meal Type never shows.
      await seedMealType(database, {
        userId: otherUserId,
        id: "mt-other",
        name: "Other user's type",
        sortOrder: 0
      });

      const response = await getAgent(app, "/agent/meal-types");
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.deepEqual(body, {
        mealTypes: [
          { id: "mt-breakfast", name: "Breakfast", sortOrder: 0 },
          { id: "mt-lunch-a", name: "Lunch", sortOrder: 1 },
          { id: "mt-lunch-b", name: "Pre-workout", sortOrder: 1 },
          { id: "mt-dinner", name: "Dinner", sortOrder: 2 }
        ]
      });

      const unauthorized = await app.request("/agent/meal-types");
      assert.equal(unauthorized.status, 401);
      assert.equal((await unauthorized.json()).code, "agent_unauthorized");

      const mcpResponse = await client.callTool({
        name: "agent_list_meal_types",
        arguments: { apiKey: "prn_agent_secret" }
      });
      assert.equal(mcpResponse.isError, undefined, JSON.stringify(mcpResponse.content));
      assert.deepEqual(mcpResponse.structuredContent, body);
    } finally {
      await close();
      await database.close();
    }
  }
);

test("agent Meal Types answers 401 without a valid agent key", async () => {
  const app = createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore("user-1"),
    agentMealTypesReadStore: {
      async listMealTypes() {
        throw new Error("listMealTypes should not be called without a key.");
      }
    }
  });

  const missing = await app.request("/agent/meal-types");
  assert.equal(missing.status, 401);
  assert.equal((await missing.json()).code, "agent_unauthorized");

  const wrong = await app.request("/agent/meal-types", {
    headers: { authorization: "Bearer prn_agent_wrong" }
  });
  assert.equal(wrong.status, 401);
});

test("agent Meal Types without its store answers 503 on REST and MCP", async () => {
  const app = createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore("user-1")
  });
  const response = await getAgent(app, "/agent/meal-types");
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
      name: "agent_list_meal_types",
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
    { name: "agent-meal-types-test-client", version: "0.0.0" },
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
      return { userId, keyId: "agent-meal-types-key-1", keyName: "Kitchen coach" };
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
    name: "Agent Meal Types User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
}

async function seedMealType({ db }, { userId, id, name, sortOrder, deletedAt = null }) {
  const updatedAt = deletedAt ?? new Date();
  await db.insert(schema.mealTypes).values({
    id,
    userId,
    deviceId: "device-agent-meal-types-test",
    updatedAt,
    receivedAt: updatedAt,
    deletedAt,
    payload: {
      id,
      name,
      sort_order: sortOrder,
      updated_at: updatedAt.toISOString(),
      deleted_at: deletedAt === null ? null : deletedAt.toISOString()
    }
  });
}
