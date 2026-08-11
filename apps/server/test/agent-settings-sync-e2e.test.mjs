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
  "an agent account-Settings write lands on a device sync pull as the synced " +
    "user_settings singleton row",
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
      const user = await createSignedInUser(serverApp, "Agent Settings E2E User");
      const agentSecret = await createAgentKey(serverApp, user.sessionToken);

      // The agent changes the account-level unit system + week start.
      const writeResponse = await serverApp.app.request(
        "/agent/settings/batch-write",
        {
          method: "POST",
          headers: {
            authorization: `Bearer ${agentSecret}`,
            "content-type": "application/json"
          },
          body: JSON.stringify({
            idempotencyKey: `agent-settings-e2e-${randomUUID()}`,
            fields: { unitSystem: "imperial", weekStartDay: "sunday" }
          })
        }
      );
      assert.equal(writeResponse.status, 200);
      const writeBody = await writeResponse.json();
      assert.equal(writeBody.settings.unitSystem, "imperial");

      // The device pulls the synced Settings singleton, carrying the change a
      // device would merge into its AppSettings (the Dart merge is covered by
      // split_settings_repository_test).
      const pulled = await pullAll(serverApp.app, user.sessionToken);
      const settingsRow = pulled.find(
        (change) => change.entity === "user_settings"
      );
      assert.ok(settingsRow, "agent settings write should reach a device pull");
      assert.equal(settingsRow.payload.unit_system, "imperial");
      assert.equal(settingsRow.payload.week_start_day, "sunday");
      assert.equal(settingsRow.deletedAt, null);

      // The agent read reflects the same singleton.
      const readResponse = await serverApp.app.request("/agent/settings", {
        headers: { authorization: `Bearer ${agentSecret}` }
      });
      assert.equal(readResponse.status, 200);
      const readBody = await readResponse.json();
      assert.equal(readBody.settings.unitSystem, "imperial");
      assert.equal(readBody.settings.weekStartDay, "sunday");
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
