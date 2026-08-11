import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { createApp, createMigratedServerApp, schema } from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

test("agent API key routes expose one-time secret and protected bearer auth", async () => {
  const createdKey = {
    id: "agent-key-1",
    name: "Garage coach",
    prefix: "prn_agent_",
    start: "prn_agent_a",
    createdAt: "2026-06-24T00:00:00.000Z",
    lastUsedAt: null,
    revoked: false
  };
  let revoked = false;
  const app = createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: {
      async authenticateAgentApiKey(secret) {
        if (secret !== "prn_agent_secret" || revoked) {
          return null;
        }

        return {
          userId: "user-1",
          keyId: createdKey.id,
          keyName: createdKey.name
        };
      },
      async createAgentApiKey(input) {
        assert.deepEqual(input, {
          userId: "user-1",
          name: "Garage coach"
        });

        return {
          key: createdKey,
          secret: "prn_agent_secret"
        };
      },
      async listAgentApiKeys(userId) {
        assert.equal(userId, "user-1");

        return [{ ...createdKey, revoked }];
      },
      async revokeAgentApiKey(input) {
        assert.deepEqual(input, {
          userId: "user-1",
          keyId: createdKey.id
        });
        revoked = true;

        return true;
      },
      async verifySessionBearerToken(token) {
        return token === "session-token" ? { userId: "user-1" } : null;
      }
    }
  });

  const missingSessionResponse = await app.request("/agent/api-keys", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ name: "Garage coach" })
  });
  assert.equal(missingSessionResponse.status, 401);

  const createResponse = await app.request("/agent/api-keys", {
    method: "POST",
    headers: {
      authorization: "Bearer session-token",
      "content-type": "application/json"
    },
    body: JSON.stringify({ name: "Garage coach" })
  });
  assert.equal(createResponse.status, 201);
  const created = await createResponse.json();
  assert.equal(created.secret, "prn_agent_secret");

  const listResponse = await app.request("/agent/api-keys", {
    headers: { authorization: "Bearer session-token" }
  });
  assert.equal(listResponse.status, 200);
  const listed = await listResponse.json();
  assert.equal(listed.keys.length, 1);
  assert.equal(Object.hasOwn(listed.keys[0], "secret"), false);

  const probeResponse = await app.request("/agent/probe", {
    headers: { authorization: "Bearer prn_agent_secret" }
  });
  assert.equal(probeResponse.status, 200);
  assert.deepEqual(await probeResponse.json(), {
    authenticated: true,
    userId: "user-1",
    keyId: createdKey.id,
    keyName: createdKey.name
  });

  const revokeResponse = await app.request(`/agent/api-keys/${createdKey.id}`, {
    method: "DELETE",
    headers: { authorization: "Bearer session-token" }
  });
  assert.equal(revokeResponse.status, 200);
  assert.deepEqual(await revokeResponse.json(), { revoked: true });

  const revokedProbeResponse = await app.request("/agent/probe", {
    headers: { authorization: "Bearer prn_agent_secret" }
  });
  assert.equal(revokedProbeResponse.status, 401);
});

test(
  "agent API keys can be created, listed, authenticated, and revoked",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
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
    const { userId, sessionToken } = await createSignedInUser(serverApp);

    try {
      const createResponse = await serverApp.app.request("/agent/api-keys", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({ name: "Garage coach" })
      });

      assert.equal(createResponse.status, 201);
      const created = await createResponse.json();
      assert.equal(created.key.name, "Garage coach");
      assert.equal(created.key.revoked, false);
      assert.equal(typeof created.key.createdAt, "string");
      assert.equal(created.key.lastUsedAt, null);
      assert.equal(typeof created.secret, "string");
      assert.match(created.secret, /^prn_agent_/);

      const listResponse = await serverApp.app.request("/agent/api-keys", {
        headers: {
          authorization: `Bearer ${sessionToken}`
        }
      });

      assert.equal(listResponse.status, 200);
      const listed = await listResponse.json();
      assert.equal(listed.keys.length, 1);
      assert.equal(listed.keys[0].id, created.key.id);
      assert.equal(listed.keys[0].name, "Garage coach");
      assert.equal(listed.keys[0].lastUsedAt, null);
      assert.equal(Object.hasOwn(listed.keys[0], "secret"), false);

      const probeResponse = await serverApp.app.request("/agent/probe", {
        headers: {
          authorization: `Bearer ${created.secret}`
        }
      });

      assert.equal(probeResponse.status, 200);
      const probe = await probeResponse.json();
      assert.deepEqual(probe, {
        authenticated: true,
        userId,
        keyId: created.key.id,
        keyName: "Garage coach"
      });

      const listAfterUseResponse = await serverApp.app.request("/agent/api-keys", {
        headers: {
          authorization: `Bearer ${sessionToken}`
        }
      });

      assert.equal(listAfterUseResponse.status, 200);
      const listedAfterUse = await listAfterUseResponse.json();
      assert.equal(typeof listedAfterUse.keys[0].lastUsedAt, "string");
      assert.equal(Object.hasOwn(listedAfterUse.keys[0], "secret"), false);

      const revokeResponse = await serverApp.app.request(
        `/agent/api-keys/${encodeURIComponent(created.key.id)}`,
        {
          method: "DELETE",
          headers: {
            authorization: `Bearer ${sessionToken}`
          }
        }
      );

      assert.equal(revokeResponse.status, 200);
      assert.deepEqual(await revokeResponse.json(), { revoked: true });

      const revokedProbeResponse = await serverApp.app.request("/agent/probe", {
        headers: {
          authorization: `Bearer ${created.secret}`
        }
      });
      assert.equal(revokedProbeResponse.status, 401);

      const unknownProbeResponse = await serverApp.app.request("/agent/probe", {
        headers: {
          authorization: "Bearer prn_agent_unknown"
        }
      });
      assert.equal(unknownProbeResponse.status, 401);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "agent API keys cannot be listed or revoked across accounts",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
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
    const userA = await createSignedInUser(serverApp);
    const userB = await createSignedInUser(serverApp);

    try {
      const createResponse = await serverApp.app.request("/agent/api-keys", {
        method: "POST",
        headers: {
          authorization: `Bearer ${userA.sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({ name: "User A coach" })
      });

      assert.equal(createResponse.status, 201);
      const created = await createResponse.json();

      const userBListResponse = await serverApp.app.request("/agent/api-keys", {
        headers: {
          authorization: `Bearer ${userB.sessionToken}`
        }
      });
      assert.equal(userBListResponse.status, 200);
      assert.deepEqual(await userBListResponse.json(), { keys: [] });

      const userBRevokeResponse = await serverApp.app.request(
        `/agent/api-keys/${encodeURIComponent(created.key.id)}`,
        {
          method: "DELETE",
          headers: {
            authorization: `Bearer ${userB.sessionToken}`
          }
        }
      );
      assert.equal(userBRevokeResponse.status, 404);

      const userAProbeResponse = await serverApp.app.request("/agent/probe", {
        headers: {
          authorization: `Bearer ${created.secret}`
        }
      });
      assert.equal(userAProbeResponse.status, 200);
      assert.deepEqual(await userAProbeResponse.json(), {
        authenticated: true,
        userId: userA.userId,
        keyId: created.key.id,
        keyName: "User A coach"
      });
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
    name: "Agent Key User",
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
