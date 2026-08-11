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
  throw new Error(
    "DATABASE_URL must be set for server Postgres integration tests."
  );
}

const dbTest = test;

dbTest(
  "agent nutrition totals: computes per-day + period totals from Food Entry snapshots, no stored total",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-nutrition-user-${randomUUID()}`;
    const app = createNutritionApp({
      agentNutritionReadStore: createDrizzleAgentNutritionReadStore(database.db),
      userId
    });

    try {
      await insertUser(database, userId);

      // Day 1: a reference banana (2 servings of 118 g = 236 g of an 89 kcal/100 g food)
      // and a protein shake quick entry.
      await insertMeal(database, {
        userId,
        id: mealId("d1m1"),
        mealType: "Breakfast",
        startedAt: "2026-06-24T05:00:00.000Z",
        localDate: "2026-06-24"
      });
      await insertFoodEntry(database, {
        userId,
        id: entryId("d1e1"),
        mealId: mealId("d1m1"),
        kind: "food",
        name: "Banana",
        nutrients: macros({ energy: 89, protein: 1.1, carbohydrate: 23, fat: 0.3 }),
        portion: { value: 2, entered: "2", unit: "serving" },
        servingSize: 118
      });
      await insertFoodEntry(database, {
        userId,
        id: entryId("d1e2"),
        mealId: mealId("d1m1"),
        kind: "quickEntry",
        name: "Protein shake",
        nutrients: macros({ energy: 160, protein: 30, carbohydrate: 5, fat: 2.5 })
      });

      // Day 2: one quick entry.
      await insertMeal(database, {
        userId,
        id: mealId("d2m1"),
        mealType: "Lunch",
        startedAt: "2026-06-25T05:00:00.000Z",
        localDate: "2026-06-25"
      });
      await insertFoodEntry(database, {
        userId,
        id: entryId("d2e1"),
        mealId: mealId("d2m1"),
        kind: "quickEntry",
        name: "Rice bowl",
        nutrients: macros({ energy: 400, protein: 12, carbohydrate: 70, fat: 6 })
      });

      const response = await getTotals(app, {
        from: "2026-06-24",
        to: "2026-06-25"
      });
      assert.equal(response.status, 200);
      const body = await response.json();

      // Range is two days inclusive.
      assert.equal(body.dayCount, 2);
      assert.equal(body.days.length, 2);

      const day1 = body.days.find((day) => day.localDate === "2026-06-24");
      assert.ok(day1);
      assert.equal(day1.mealCount, 1);
      assert.equal(day1.entryCount, 2);

      // Banana energy scaled by 236/100 = 2.36 -> 89 * 2.36 = 210.04; + shake 160.
      const day1Energy = totalFor(day1.totals, "energy");
      assert.equal(day1Energy.complete, true);
      assert.ok(Math.abs(day1Energy.value - (89 * 2.36 + 160)) < 1e-6);

      const day1Protein = totalFor(day1.totals, "protein");
      assert.ok(Math.abs(day1Protein.value - (1.1 * 2.36 + 30)) < 1e-6);

      // Period aggregates both days.
      assert.equal(body.period.mealCount, 2);
      assert.equal(body.period.entryCount, 3);
      assert.equal(body.period.loggedDayCount, 2);
      const periodEnergy = totalFor(body.period.totals, "energy");
      assert.ok(Math.abs(periodEnergy.value - (89 * 2.36 + 160 + 400)) < 1e-6);

      // Pure read: no Activity Log entry written for the read.
      const activityRows = await database.sql`
        select id from activity_log where user_id = ${userId}
      `;
      assert.equal(activityRows.length, 0);
    } finally {
      await database.close();
    }
  }
);

dbTest(
  "agent nutrition totals: empty days report a genuine complete zero",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-nutrition-empty-${randomUUID()}`;
    const app = createNutritionApp({
      agentNutritionReadStore: createDrizzleAgentNutritionReadStore(database.db),
      userId
    });

    try {
      await insertUser(database, userId);

      const response = await getTotals(app, {
        from: "2026-07-01",
        to: "2026-07-03"
      });
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.days.length, 3);
      assert.equal(body.period.loggedDayCount, 0);
      for (const day of body.days) {
        const energy = totalFor(day.totals, "energy");
        assert.equal(energy.value, 0);
        // A day with no meals is genuinely complete-zero, not unknown.
        assert.equal(energy.complete, true);
      }
    } finally {
      await database.close();
    }
  }
);

dbTest(
  "agent nutrition totals: unknown nutrient propagates incompleteness, never reported as zero",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-nutrition-unknown-${randomUUID()}`;
    const app = createNutritionApp({
      agentNutritionReadStore: createDrizzleAgentNutritionReadStore(database.db),
      userId
    });

    try {
      await insertUser(database, userId);

      await insertMeal(database, {
        userId,
        id: mealId("u1m1"),
        mealType: "Snack",
        startedAt: "2026-06-24T05:00:00.000Z",
        localDate: "2026-06-24"
      });
      // One entry states energy only; fiber stays unknown on the row.
      await insertFoodEntry(database, {
        userId,
        id: entryId("u1e1"),
        mealId: mealId("u1m1"),
        kind: "quickEntry",
        name: "Mystery bar",
        nutrients: {
          energy: { status: "complete", value: 200, entered: "200", unit: "kilocalorie" }
        }
      });
      // A second entry that DOES state fiber: the day total for fiber is still
      // incomplete because the first entry lacked it.
      await insertFoodEntry(database, {
        userId,
        id: entryId("u1e2"),
        mealId: mealId("u1m1"),
        kind: "quickEntry",
        name: "Oats",
        nutrients: {
          energy: { status: "complete", value: 150, entered: "150", unit: "kilocalorie" },
          fiber: { status: "complete", value: 4, entered: "4", unit: "gram" }
        }
      });

      const response = await getTotals(app, {
        from: "2026-06-24",
        to: "2026-06-24"
      });
      assert.equal(response.status, 200);
      const body = await response.json();
      const day = body.days[0];

      // Energy is complete (both entries stated it).
      const energy = totalFor(day.totals, "energy");
      assert.equal(energy.complete, true);
      assert.equal(energy.value, 350);

      // Fiber is incomplete: the bar omitted it. Never reported as 0 with complete=true.
      const fiber = totalFor(day.totals, "fiber");
      assert.equal(fiber.complete, false);

      // Period total carries the same incompleteness.
      const periodFiber = totalFor(body.period.totals, "fiber");
      assert.equal(periodFiber.complete, false);
    } finally {
      await database.close();
    }
  }
);

dbTest(
  "agent nutrition totals: goal progress derives against supplied v1 targets, unknown-aware",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-nutrition-goals-${randomUUID()}`;
    const app = createNutritionApp({
      agentNutritionReadStore: createDrizzleAgentNutritionReadStore(database.db),
      userId
    });

    try {
      await insertUser(database, userId);

      await insertMeal(database, {
        userId,
        id: mealId("g1m1"),
        mealType: "Dinner",
        startedAt: "2026-06-24T05:00:00.000Z",
        localDate: "2026-06-24"
      });
      // Energy stated, protein NOT stated -> protein goal progress is unknown.
      await insertFoodEntry(database, {
        userId,
        id: entryId("g1e1"),
        mealId: mealId("g1m1"),
        kind: "quickEntry",
        name: "Energy only",
        nutrients: {
          energy: { status: "complete", value: 1800, entered: "1800", unit: "kilocalorie" }
        }
      });

      const response = await getTotals(app, {
        from: "2026-06-24",
        to: "2026-06-24",
        energyGoal: 2000,
        proteinGoal: 150
      });
      assert.equal(response.status, 200);
      const body = await response.json();
      const day = body.days[0];

      const energyGoal = goalFor(day.goalProgress, "energy");
      assert.equal(energyGoal.status, "below");
      assert.ok(Math.abs(energyGoal.ratio - 0.9) < 1e-6);
      assert.equal(energyGoal.remaining, 200);
      assert.equal(energyGoal.target.value, 2000);

      // Protein total is unknown -> goal progress is unknown, no ratio/remaining.
      const proteinGoal = goalFor(day.goalProgress, "protein");
      assert.equal(proteinGoal.status, "unknown");
      assert.equal(proteinGoal.ratio, null);
      assert.equal(proteinGoal.remaining, null);

      // Carb has no supplied target -> noGoal.
      const carbGoal = goalFor(day.goalProgress, "carbohydrate");
      assert.equal(carbGoal.status, "noGoal");
      assert.equal(carbGoal.target, null);
    } finally {
      await database.close();
    }
  }
);

dbTest(
  "agent nutrition trends: per-day trend nulls incomplete days and never dumps raw entries",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-nutrition-trends-${randomUUID()}`;
    const app = createNutritionApp({
      agentNutritionReadStore: createDrizzleAgentNutritionReadStore(database.db),
      userId
    });

    try {
      await insertUser(database, userId);

      // Day 1: complete energy.
      await insertMeal(database, {
        userId,
        id: mealId("t1m1"),
        mealType: "Lunch",
        startedAt: "2026-06-24T05:00:00.000Z",
        localDate: "2026-06-24"
      });
      await insertFoodEntry(database, {
        userId,
        id: entryId("t1e1"),
        mealId: mealId("t1m1"),
        kind: "quickEntry",
        name: "Bowl",
        nutrients: macros({ energy: 500, protein: 20, carbohydrate: 60, fat: 15 })
      });
      // Day 2: protein unknown (energy only) -> protein trend point incomplete.
      await insertMeal(database, {
        userId,
        id: mealId("t2m1"),
        mealType: "Lunch",
        startedAt: "2026-06-25T05:00:00.000Z",
        localDate: "2026-06-25"
      });
      await insertFoodEntry(database, {
        userId,
        id: entryId("t2e1"),
        mealId: mealId("t2m1"),
        kind: "quickEntry",
        name: "Energy only",
        nutrients: {
          energy: { status: "complete", value: 300, entered: "300", unit: "kilocalorie" }
        }
      });

      const response = await getTrends(app, {
        from: "2026-06-24",
        to: "2026-06-26",
        energyGoal: 2200
      });
      assert.equal(response.status, 200);
      const body = await response.json();

      // The response never exposes raw meal-by-meal entries.
      assert.equal(JSON.stringify(body).includes('"name":"Bowl"'), false);
      assert.equal("meals" in body, false);
      assert.equal("entries" in body, false);

      const energyTrend = body.trends.find((trend) => trend.nutrient === "energy");
      assert.ok(energyTrend);
      assert.equal(energyTrend.points.length, 3);
      assert.equal(energyTrend.points[0].value, 500);
      assert.equal(energyTrend.points[0].complete, true);
      // Day 3 had no meals -> a genuine complete zero.
      assert.equal(energyTrend.points[2].value, 0);
      assert.equal(energyTrend.points[2].complete, true);
      assert.equal(energyTrend.target.value, 2200);

      const proteinTrend = body.trends.find(
        (trend) => trend.nutrient === "protein"
      );
      assert.ok(proteinTrend);
      // Day 1 protein complete, day 2 protein incomplete -> null (not 0).
      assert.equal(proteinTrend.points[0].value, 20);
      assert.equal(proteinTrend.points[1].value, null);
      assert.equal(proteinTrend.points[1].complete, false);
    } finally {
      await database.close();
    }
  }
);

dbTest(
  "agent nutrition reads: read-only, reject invalid/oversized ranges, require auth",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-nutrition-guard-${randomUUID()}`;
    const app = createNutritionApp({
      agentNutritionReadStore: createDrizzleAgentNutritionReadStore(database.db),
      userId
    });

    try {
      await insertUser(database, userId);

      // Inverted range -> 422.
      const inverted = await getTotals(app, {
        from: "2026-06-25",
        to: "2026-06-24"
      });
      assert.equal(inverted.status, 422);
      const invertedBody = await inverted.json();
      assert.equal(invertedBody.code, "agent_nutrition_read_invalid_range");

      // Oversized range (> 366 days) -> 422.
      const oversized = await getTotals(app, {
        from: "2024-01-01",
        to: "2026-01-01"
      });
      assert.equal(oversized.status, 422);

      // Unauthenticated -> 401.
      const noAuth = await app.request(
        "/agent/nutrition/totals?from=2026-06-24&to=2026-06-24",
        { method: "GET" }
      );
      assert.equal(noAuth.status, 401);

      // No rows mutated and no Activity Log written by any read attempt.
      const activityRows = await database.sql`
        select id from activity_log where user_id = ${userId}
      `;
      assert.equal(activityRows.length, 0);
    } finally {
      await database.close();
    }
  }
);

dbTest(
  "agent nutrition reads: scoped to the authenticated account",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-nutrition-self-${randomUUID()}`;
    const otherUserId = `agent-nutrition-other-${randomUUID()}`;
    const app = createNutritionApp({
      agentNutritionReadStore: createDrizzleAgentNutritionReadStore(database.db),
      userId
    });

    try {
      await insertUser(database, userId);
      await insertUser(database, otherUserId);

      // Another account logs a meal on the same day.
      await insertMeal(database, {
        userId: otherUserId,
        id: mealId("o1m1"),
        mealType: "Lunch",
        startedAt: "2026-06-24T05:00:00.000Z",
        localDate: "2026-06-24"
      });
      await insertFoodEntry(database, {
        userId: otherUserId,
        id: entryId("o1e1"),
        mealId: mealId("o1m1"),
        kind: "quickEntry",
        name: "Other user meal",
        nutrients: macros({ energy: 999, protein: 99, carbohydrate: 99, fat: 99 })
      });

      const response = await getTotals(app, {
        from: "2026-06-24",
        to: "2026-06-24"
      });
      assert.equal(response.status, 200);
      const body = await response.json();
      // The authenticated account sees none of the other account's data.
      assert.equal(body.period.entryCount, 0);
      assert.equal(totalFor(body.days[0].totals, "energy").value, 0);
    } finally {
      await database.close();
    }
  }
);

function createNutritionApp({ agentNutritionReadStore, userId = "user-1" }) {
  return createApp({
    logger: { info() {}, error() {} },
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

function getTotals(app, query) {
  return app.request(`/agent/nutrition/totals?${queryString(query)}`, {
    method: "GET",
    headers: { authorization: "Bearer prn_agent_secret" }
  });
}

function getTrends(app, query) {
  return app.request(`/agent/nutrition/trends?${queryString(query)}`, {
    method: "GET",
    headers: { authorization: "Bearer prn_agent_secret" }
  });
}

function queryString(query) {
  return Object.entries(query)
    .map(([key, value]) => `${key}=${encodeURIComponent(value)}`)
    .join("&");
}

async function insertUser(database, userId) {
  await database.db.insert(schema.user).values({
    id: userId,
    name: "Agent Nutrition User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
}

async function insertMeal(
  database,
  { userId, id, mealType, startedAt, localDate }
) {
  await database.db.insert(schema.meals).values({
    id,
    userId,
    deviceId: "agent:agent-key-1",
    payload: {
      id,
      meal_type: mealType,
      started_at: startedAt,
      timezone: "Australia/Brisbane",
      local_date: localDate,
      ended_at: null,
      updated_at: startedAt,
      deleted_at: null
    },
    updatedAt: new Date(startedAt),
    deletedAt: null
  });
}

async function insertFoodEntry(
  database,
  { userId, id, mealId: parentMealId, kind, name, nutrients, portion, servingSize }
) {
  await database.db.insert(schema.foodEntries).values({
    id,
    userId,
    deviceId: "agent:agent-key-1",
    payload: {
      id,
      meal_id: parentMealId,
      entry_kind: kind,
      position: 0,
      name,
      nutrient_values_json: JSON.stringify(nutrientStorage(nutrients)),
      food_id: kind === "food" ? "food-x" : null,
      portion_json: portion === undefined ? null : JSON.stringify(portion),
      food_source: kind === "food" ? "usda" : null,
      is_liquid: false,
      serving_label: servingSize === undefined ? null : "serving",
      serving_size: servingSize ?? null,
      package_size: null,
      updated_at: "2026-06-24T05:00:00.000Z",
      deleted_at: null
    },
    updatedAt: new Date("2026-06-24T05:00:00.000Z"),
    deletedAt: null
  });
}

const ALL_NUTRIENT_KEYS = [
  "energy",
  "protein",
  "carbohydrate",
  "sugar",
  "fat",
  "saturated_fat",
  "monounsaturated_fat",
  "polyunsaturated_fat",
  "fiber",
  "sodium",
  "cholesterol",
  "vitamin_a",
  "vitamin_c",
  "vitamin_d",
  "vitamin_e",
  "vitamin_k",
  "thiamin",
  "riboflavin",
  "niacin",
  "vitamin_b6",
  "folate",
  "vitamin_b12",
  "calcium",
  "iron",
  "magnesium",
  "phosphorus",
  "potassium",
  "zinc",
  "copper",
  "manganese",
  "selenium",
  "caffeine",
  "water"
];

const DEFAULT_UNIT_BY_KEY = {
  energy: "kilocalorie",
  protein: "gram",
  carbohydrate: "gram",
  sugar: "gram",
  fat: "gram",
  saturated_fat: "gram",
  monounsaturated_fat: "gram",
  polyunsaturated_fat: "gram",
  fiber: "gram",
  sodium: "milligram",
  cholesterol: "milligram",
  vitamin_a: "microgram",
  vitamin_c: "milligram",
  vitamin_d: "microgram",
  vitamin_e: "milligram",
  vitamin_k: "microgram",
  thiamin: "milligram",
  riboflavin: "milligram",
  niacin: "milligram",
  vitamin_b6: "milligram",
  folate: "microgram",
  vitamin_b12: "microgram",
  calcium: "milligram",
  iron: "milligram",
  magnesium: "milligram",
  phosphorus: "milligram",
  potassium: "milligram",
  zinc: "milligram",
  copper: "milligram",
  manganese: "milligram",
  selenium: "microgram",
  caffeine: "milligram",
  water: "milliliter"
};

function macros({ energy, protein, carbohydrate, fat }) {
  return {
    energy: { status: "complete", value: energy, entered: String(energy), unit: "kilocalorie" },
    protein: { status: "complete", value: protein, entered: String(protein), unit: "gram" },
    carbohydrate: {
      status: "complete",
      value: carbohydrate,
      entered: String(carbohydrate),
      unit: "gram"
    },
    fat: { status: "complete", value: fat, entered: String(fat), unit: "gram" }
  };
}

// Render the device-canonical full nutrient vector: every fixed key present,
// omitted ones stored as explicit unknown (never coerced to zero).
function nutrientStorage(nutrients) {
  const storage = {};
  for (const key of ALL_NUTRIENT_KEYS) {
    const amount = nutrients[key];
    const unit = amount?.unit ?? DEFAULT_UNIT_BY_KEY[key];
    if (amount === undefined || amount.status === "unknown") {
      storage[key] = { status: "unknown", value: null, entered: null, unit };
    } else {
      storage[key] = {
        status: "complete",
        value: amount.value,
        entered: amount.entered ?? String(amount.value),
        unit
      };
    }
  }

  return storage;
}

function totalFor(totals, nutrient) {
  const total = totals.find((entry) => entry.nutrient === nutrient);
  assert.ok(total, `expected a total for ${nutrient}`);
  return total;
}

function goalFor(goalProgress, nutrient) {
  const progress = goalProgress.find((entry) => entry.nutrient === nutrient);
  assert.ok(progress, `expected goal progress for ${nutrient}`);
  return progress;
}

// Row primary keys are text; uniqueness across the persistent test DB matters
// more than UUID shape, so namespace every logical id under a per-run prefix.
const ID_RUN_PREFIX = randomUUID();

function mealId(suffix) {
  return `meal-${ID_RUN_PREFIX}-${suffix}`;
}

function entryId(suffix) {
  return `entry-${ID_RUN_PREFIX}-${suffix}`;
}
