import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  applyMigrations,
  createApp,
  createDatabaseClient,
  createDrizzleAgentSettingsStore,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error(
    "DATABASE_URL must be set for server Postgres integration tests."
  );
}

const skip = databaseUrl ? false : "DATABASE_URL is not set.";

test(
  "agent settings read returns defaults, batch write updates the singleton, records one Activity Log batch, replays idempotently, and merges partial writes",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-settings-user-${randomUUID()}`;
    const nudges = [];
    const app = createAgentSettingsApp({
      userId,
      agentSettingsStore: createDrizzleAgentSettingsStore(database.db),
      syncNudgePublisher: {
        async enqueueSyncNudge(input) {
          nudges.push(input);
          return { enqueued: true, jobId: `nudge-${nudges.length}` };
        }
      }
    });

    try {
      await seedUser(database, userId);

      // Fresh account: read returns canonical defaults with a null clock.
      const initial = await getAgentSettings(app);
      assert.equal(initial.status, 200);
      const initialBody = await initial.json();
      assert.equal(initialBody.settings.themePreference, "system");
      assert.equal(initialBody.settings.unitSystem, "metric");
      assert.equal(initialBody.settings.defaultWeightIncrement, 2.5);
      assert.equal(initialBody.updatedAt, null);

      // First write changes a subset; omitted keys keep their defaults.
      const idempotencyKey = `agent-settings-${randomUUID()}`;
      const writeResponse = await postAgentSettings(app, {
        idempotencyKey,
        fields: { unitSystem: "imperial", defaultWeightIncrement: 5 }
      });
      assert.equal(writeResponse.status, 200);
      const writeBody = await writeResponse.json();
      assert.equal(writeBody.accepted, true);
      assert.equal(writeBody.duplicate, false);
      assert.equal(writeBody.batchId, idempotencyKey);
      assert.equal(writeBody.settings.unitSystem, "imperial");
      assert.equal(writeBody.settings.defaultWeightIncrement, 5);
      assert.equal(writeBody.settings.themePreference, "system");

      // Read reflects the write.
      const afterWrite = await getAgentSettings(app);
      const afterWriteBody = await afterWrite.json();
      assert.equal(afterWriteBody.settings.unitSystem, "imperial");
      assert.equal(afterWriteBody.settings.defaultWeightIncrement, 5);
      assert.ok(afterWriteBody.updatedAt);

      // Exactly one Activity Log batch, on the user_settings table.
      const activityRows = await database.sql`
        select entity_table, batch_id
        from activity_log
        where user_id = ${userId}
      `;
      assert.equal(activityRows.length, 1);
      assert.equal(activityRows[0].entity_table, "user_settings");
      assert.equal(activityRows[0].batch_id, idempotencyKey);
      assert.equal(nudges.length, 1);
      assert.equal(nudges[0].userId, userId);

      // Idempotent replay: no new Activity Log batch, no new nudge.
      const retry = await postAgentSettings(app, {
        idempotencyKey,
        fields: { unitSystem: "imperial", defaultWeightIncrement: 5 }
      });
      assert.equal(retry.status, 200);
      const retryBody = await retry.json();
      assert.equal(retryBody.duplicate, true);
      const activityAfterRetry = await database.sql`
        select id from activity_log where user_id = ${userId}
      `;
      assert.equal(activityAfterRetry.length, 1);
      assert.equal(nudges.length, 1);

      // A second, distinct write merges onto the current row (one settings row).
      const secondKey = `agent-settings-${randomUUID()}`;
      const second = await postAgentSettings(app, {
        idempotencyKey: secondKey,
        fields: { themePreference: "dark" }
      });
      assert.equal(second.status, 200);
      const secondBody = await second.json();
      assert.equal(secondBody.settings.themePreference, "dark");
      // The earlier imperial unit survives the partial merge.
      assert.equal(secondBody.settings.unitSystem, "imperial");

      const settingsRows = await database.sql`
        select id from user_settings where user_id = ${userId} and deleted_at is null
      `;
      assert.equal(settingsRows.length, 1);

      // Hard-reject: an unknown enum member fails the shared validator, no write.
      const reject = await postAgentSettings(app, {
        idempotencyKey: `agent-settings-reject-${randomUUID()}`,
        fields: { themePreference: "midnight" }
      });
      assert.equal(reject.status, 422);
      const rejectBody = await reject.json();
      assert.equal(rejectBody.errors[0].rule, "setting_enum_membership");

      // Hard-reject: a non-positive increment.
      const rejectIncrement = await postAgentSettings(app, {
        idempotencyKey: `agent-settings-reject2-${randomUUID()}`,
        fields: { defaultWeightIncrement: 0 }
      });
      assert.equal(rejectIncrement.status, 422);
      const rejectIncrementBody = await rejectIncrement.json();
      assert.equal(
        rejectIncrementBody.errors[0].rule,
        "setting_weight_increment_positive"
      );
    } finally {
      await database.close();
    }
  }
);

test(
  "agent settings batch write is tenant-isolated: one user's key cannot read or overwrite another user's settings singleton",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userA = `agent-settings-tenant-a-${randomUUID()}`;
    const userB = `agent-settings-tenant-b-${randomUUID()}`;
    const store = createDrizzleAgentSettingsStore(database.db);
    const appA = createAgentSettingsApp({ userId: userA, agentSettingsStore: store });
    const appB = createAgentSettingsApp({ userId: userB, agentSettingsStore: store });

    try {
      await seedUser(database, userA);
      await seedUser(database, userB);

      const writeA = await postAgentSettings(appA, {
        idempotencyKey: `agent-settings-tenant-a-${randomUUID()}`,
        fields: { unitSystem: "imperial", defaultWeightIncrement: 5 }
      });
      assert.equal(writeA.status, 200);

      // User B writes their own settings (distinct singleton row).
      const writeB = await postAgentSettings(appB, {
        idempotencyKey: `agent-settings-tenant-b-${randomUUID()}`,
        fields: { unitSystem: "metric", defaultWeightIncrement: 1 }
      });
      assert.equal(writeB.status, 200);

      // Each user has exactly one row, scoped to their own userId.
      const rowsA = await database.sql`
        select id, payload from user_settings where user_id = ${userA}
      `;
      const rowsB = await database.sql`
        select id, payload from user_settings where user_id = ${userB}
      `;
      assert.equal(rowsA.length, 1);
      assert.equal(rowsB.length, 1);
      assert.notEqual(rowsA[0].id, rowsB[0].id);
      assert.equal(rowsA[0].payload.unit_system, "imperial");
      assert.equal(rowsB[0].payload.unit_system, "metric");

      // User B's read never surfaces user A's imperial choice.
      const readB = await getAgentSettings(appB);
      const readBBody = await readB.json();
      assert.equal(readBBody.settings.unitSystem, "metric");

      // User A's read is unaffected.
      const readA = await getAgentSettings(appA);
      const readABody = await readA.json();
      assert.equal(readABody.settings.unitSystem, "imperial");
    } finally {
      await database.close();
    }
  }
);

function createAgentSettingsApp({
  agentSettingsStore,
  syncNudgePublisher,
  userId = "user-1"
}) {
  return createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore(userId),
    agentSettingsStore,
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

function getAgentSettings(app) {
  return app.request("/agent/settings", {
    headers: { authorization: "Bearer prn_agent_secret" }
  });
}

function postAgentSettings(app, body) {
  return app.request("/agent/settings/batch-write", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_agent_secret",
      "content-type": "application/json"
    },
    body: JSON.stringify(body)
  });
}

async function seedUser(database, userId) {
  await database.db.insert(schema.user).values({
    id: userId,
    name: "Agent Settings User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
}
