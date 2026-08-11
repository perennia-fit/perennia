import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  applyMigrations,
  createApp,
  createDatabaseClient,
  createDrizzleAgentNutritionGoalStore,
  createDrizzleAgentNutritionReadStore,
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
  "agent nutrition totals/trends use stored Goals by default and report the source",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-goal-totals-user-${randomUUID()}`;
    const app = createApp({
      logger: { info() {}, error() {} },
      agentApiKeyStore: createAgentKeyStore(userId),
      agentNutritionReadStore: createDrizzleAgentNutritionReadStore(database.db),
      agentNutritionGoalStore: createDrizzleAgentNutritionGoalStore(database.db)
    });

    try {
      await database.db.insert(schema.user).values({
        id: userId,
        name: "Agent Goal Totals User",
        email: `${userId}@example.com`,
        emailVerified: true
      });

      const goalId = randomUUID();
      await database.db.insert(schema.nutritionGoals).values({
        id: goalId,
        userId,
        deviceId: "device-a",
        payload: {
          id: goalId,
          nutrient_id: "energy",
          target_value: 2000,
          target_entered: "2000",
          unit: "kilocalorie",
          updated_at: "2026-06-20T00:00:00.000Z",
          deleted_at: null
        },
        updatedAt: new Date("2026-06-20T00:00:00.000Z"),
        deletedAt: null
      });

      const mealId = `meal-${randomUUID()}`;
      await database.db.insert(schema.meals).values({
        id: mealId,
        userId,
        deviceId: "device-a",
        payload: {
          id: mealId,
          meal_type: "Breakfast",
          started_at: "2026-06-24T05:00:00.000Z",
          timezone: "Australia/Brisbane",
          local_date: "2026-06-24",
          ended_at: null,
          updated_at: "2026-06-24T05:00:00.000Z",
          deleted_at: null
        },
        updatedAt: new Date("2026-06-24T05:00:00.000Z"),
        deletedAt: null
      });
      const entryId = `entry-${randomUUID()}`;
      await database.db.insert(schema.foodEntries).values({
        id: entryId,
        userId,
        deviceId: "device-a",
        payload: {
          id: entryId,
          meal_id: mealId,
          entry_kind: "quickEntry",
          position: 0,
          name: "Rice bowl",
          nutrient_values_json: JSON.stringify({
            energy: {
              status: "complete",
              value: 1800,
              entered: "1800",
              unit: "kilocalorie"
            }
          }),
          food_id: null,
          portion_json: null,
          food_source: null,
          is_liquid: false,
          serving_label: null,
          serving_size: null,
          package_size: null,
          updated_at: "2026-06-24T05:00:00.000Z",
          deleted_at: null
        },
        updatedAt: new Date("2026-06-24T05:00:00.000Z"),
        deletedAt: null
      });

      // No goal query params: the stored Goal (2000 kcal) is used by default.
      const totalsResponse = await app.request(
        "/agent/nutrition/totals?from=2026-06-24&to=2026-06-24",
        { method: "GET", headers: { authorization: "Bearer prn_agent_secret" } }
      );
      assert.equal(totalsResponse.status, 200);
      const totalsBody = await totalsResponse.json();
      assert.equal(totalsBody.goalSource, "stored");
      const periodEnergyGoal = totalsBody.period.goalProgress.find(
        (entry) => entry.nutrient === "energy"
      );
      assert.ok(periodEnergyGoal);
      assert.equal(periodEnergyGoal.target.value, 2000);
      assert.equal(periodEnergyGoal.status, "below");

      // Explicit query param overrides the stored Goal.
      const overrideResponse = await app.request(
        "/agent/nutrition/totals?from=2026-06-24&to=2026-06-24&energyGoal=1500",
        { method: "GET", headers: { authorization: "Bearer prn_agent_secret" } }
      );
      assert.equal(overrideResponse.status, 200);
      const overrideBody = await overrideResponse.json();
      assert.equal(overrideBody.goalSource, "query");
      const overrideEnergyGoal = overrideBody.period.goalProgress.find(
        (entry) => entry.nutrient === "energy"
      );
      assert.equal(overrideEnergyGoal.target.value, 1500);
      assert.equal(overrideEnergyGoal.status, "over");

      // Trends: same stored-goal default + source reporting.
      const trendsResponse = await app.request(
        "/agent/nutrition/trends?from=2026-06-24&to=2026-06-24",
        { method: "GET", headers: { authorization: "Bearer prn_agent_secret" } }
      );
      assert.equal(trendsResponse.status, 200);
      const trendsBody = await trendsResponse.json();
      assert.equal(trendsBody.goalSource, "stored");
      const energyTrend = trendsBody.trends.find(
        (trend) => trend.nutrient === "energy"
      );
      assert.ok(energyTrend);
      assert.equal(energyTrend.target.value, 2000);
    } finally {
      await database.close();
    }
  }
);

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
