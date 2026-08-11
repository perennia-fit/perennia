import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  applyMigrations,
  createApp,
  createDatabaseClient,
  createDrizzleAgentNutritionGoalStore,
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
  "agent nutrition goal batch write creates/updates/clears targets, records one Activity Log batch, replays idempotently, and lists back",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-nutrition-goal-user-${randomUUID()}`;
    const nudges = [];
    const app = createAgentNutritionGoalApp({
      userId,
      agentNutritionGoalStore: createDrizzleAgentNutritionGoalStore(database.db),
      syncNudgePublisher: {
        async enqueueSyncNudge(input) {
          nudges.push(input);
          return { enqueued: true, jobId: `nudge-${nudges.length}` };
        }
      }
    });

    const energyGoalId = randomUUID();
    const proteinGoalId = randomUUID();
    const idempotencyKey = `agent-nutrition-goal-${randomUUID()}`;

    try {
      await seedUser(database, userId);

      const request = {
        idempotencyKey,
        targets: [
          { id: energyGoalId, nutrient: "energy", value: 2200 },
          { id: proteinGoalId, nutrient: "protein", value: 160 }
        ]
      };
      const response = await postAgentNutritionGoals(app, request);
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.accepted, true);
      assert.equal(body.duplicate, false);
      assert.equal(body.batchId, idempotencyKey);
      assert.equal(body.targets.length, 2);
      assert.equal(body.targets[0].outcome, "applied");
      assert.equal(body.targets[1].outcome, "applied");

      // Reads back via GET /agent/nutrition/goals.
      const listResponse = await app.request("/agent/nutrition/goals", {
        headers: { authorization: "Bearer prn_agent_secret" }
      });
      assert.equal(listResponse.status, 200);
      const listBody = await listResponse.json();
      const energyGoal = listBody.goals.find((goal) => goal.nutrient === "energy");
      const proteinGoal = listBody.goals.find(
        (goal) => goal.nutrient === "protein"
      );
      assert.ok(energyGoal);
      assert.equal(energyGoal.value, 2200);
      assert.equal(energyGoal.unit, "kilocalorie");
      assert.ok(proteinGoal);
      assert.equal(proteinGoal.value, 160);

      const activityRows = await database.sql`
        select entity_table, entity_id, batch_id
        from activity_log
        where user_id = ${userId}
        order by entity_id
      `;
      assert.ok(
        activityRows.every(
          (row) =>
            row.batch_id === idempotencyKey &&
            row.entity_table === "nutrition_goals"
        )
      );
      assert.equal(activityRows.length, 2);

      assert.equal(nudges.length, 1);
      assert.equal(nudges[0].userId, userId);

      // Idempotent replay: no duplicate Activity Log batch, no new sync nudge.
      const retryResponse = await postAgentNutritionGoals(app, request);
      assert.equal(retryResponse.status, 200);
      const retryBody = await retryResponse.json();
      assert.equal(retryBody.duplicate, true);
      assert.equal(retryBody.targets[0].outcome, "duplicate");
      const activityRowsAfterRetry = await database.sql`
        select id from activity_log where user_id = ${userId}
      `;
      assert.equal(activityRowsAfterRetry.length, 2);
      assert.equal(nudges.length, 1);

      // Clearing a goal (deletedAt set) tombstones it — it drops out of the list.
      const clearIdempotencyKey = `agent-nutrition-goal-clear-${randomUUID()}`;
      const clearResponse = await postAgentNutritionGoals(app, {
        idempotencyKey: clearIdempotencyKey,
        targets: [
          {
            id: proteinGoalId,
            nutrient: "protein",
            value: 160,
            deletedAt: new Date().toISOString()
          }
        ]
      });
      assert.equal(clearResponse.status, 200);
      const listAfterClear = await app.request("/agent/nutrition/goals", {
        headers: { authorization: "Bearer prn_agent_secret" }
      });
      const listAfterClearBody = await listAfterClear.json();
      assert.equal(
        listAfterClearBody.goals.some((goal) => goal.nutrient === "protein"),
        false
      );
      assert.ok(
        listAfterClearBody.goals.some((goal) => goal.nutrient === "energy")
      );

      // Hard-reject: an absurd macro value fails the shared validator with no write.
      const rejectResponse = await postAgentNutritionGoals(app, {
        idempotencyKey: `agent-nutrition-goal-reject-${randomUUID()}`,
        targets: [{ id: randomUUID(), nutrient: "fat", value: 2001 }]
      });
      assert.equal(rejectResponse.status, 422);
      const rejectBody = await rejectResponse.json();
      assert.equal(rejectBody.errors[0].rule, "nutrient_macro_max_grams");
    } finally {
      await database.close();
    }
  }
);

test(
  "agent nutrition goal batch write is tenant-isolated: one user's key cannot overwrite or read another user's Goal row",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userA = `agent-nutrition-goal-tenant-a-${randomUUID()}`;
    const userB = `agent-nutrition-goal-tenant-b-${randomUUID()}`;
    const store = createDrizzleAgentNutritionGoalStore(database.db);
    const appA = createAgentNutritionGoalApp({
      userId: userA,
      agentNutritionGoalStore: store
    });
    const appB = createAgentNutritionGoalApp({
      userId: userB,
      agentNutritionGoalStore: store
    });
    const goalId = randomUUID();

    try {
      await seedUser(database, userA);
      await seedUser(database, userB);

      const createResponse = await postAgentNutritionGoals(appA, {
        idempotencyKey: `agent-nutrition-goal-tenant-create-${randomUUID()}`,
        targets: [{ id: goalId, nutrient: "energy", value: 2200 }]
      });
      assert.equal(createResponse.status, 200);

      // User B's key writing the SAME client-PK id must not overwrite user A's
      // row (tenant isolation on write, standing review gate).
      const hijackResponse = await postAgentNutritionGoals(appB, {
        idempotencyKey: `agent-nutrition-goal-tenant-hijack-${randomUUID()}`,
        targets: [{ id: goalId, nutrient: "energy", value: 9999 }]
      });
      assert.equal(hijackResponse.status, 200);

      const storedRows = await database.sql`
        select user_id, payload from nutrition_goals where id = ${goalId}
      `;
      assert.equal(storedRows.length, 1);
      assert.equal(storedRows[0].user_id, userA);
      assert.equal(storedRows[0].payload.target_value, 2200);

      // User B's list must never see user A's Goal.
      const listB = await appB.request("/agent/nutrition/goals", {
        headers: { authorization: "Bearer prn_agent_secret" }
      });
      const listBBody = await listB.json();
      assert.equal(listBBody.goals.length, 0);

      // User A's list is unaffected.
      const listA = await appA.request("/agent/nutrition/goals", {
        headers: { authorization: "Bearer prn_agent_secret" }
      });
      const listABody = await listA.json();
      assert.equal(listABody.goals.length, 1);
      assert.equal(listABody.goals[0].value, 2200);
    } finally {
      await database.close();
    }
  }
);

function createAgentNutritionGoalApp({
  agentNutritionGoalStore,
  syncNudgePublisher,
  userId = "user-1"
}) {
  return createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore(userId),
    agentNutritionGoalStore,
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

function postAgentNutritionGoals(app, body) {
  return app.request("/agent/nutrition/goals/batch-write", {
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
    name: "Agent Nutrition Goal User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
}
