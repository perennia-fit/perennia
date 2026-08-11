import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  applyMigrations,
  createApp,
  createDatabaseClient,
  createDrizzleAgentCrossDomainReadStore,
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
const skip = databaseUrl ? false : "DATABASE_URL is not set.";

dbTest(
  "energy balance: joins derived nutrition energy with calories-burned Readings, computed on demand",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `xdomain-balance-${randomUUID()}`;
    const app = createCrossDomainApp(database, userId);

    try {
      await insertUser(database, userId);

      // Day 1: 2300 kcal in (banana 236 g of an 89 kcal/100 g food = 210.04 +
      // shake 160 + bowl 1929.96), and 500 kcal burned across two Readings.
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
        kind: "quickEntry",
        name: "Big bowl",
        nutrients: macros({ energy: 2300, protein: 120, carbohydrate: 250, fat: 60 })
      });
      await insertCaloriesBurnedMetric(database, userId);
      await insertCaloriesBurnedReading(database, {
        userId,
        id: readingId("d1r1"),
        atTime: "2026-06-24T07:00:00.000Z",
        value: 300
      });
      await insertCaloriesBurnedReading(database, {
        userId,
        id: readingId("d1r2"),
        atTime: "2026-06-24T19:00:00.000Z",
        value: 200
      });

      const response = await getEnergyBalance(app, {
        from: "2026-06-24",
        to: "2026-06-24"
      });
      assert.equal(response.status, 200);
      const body = await response.json();

      assert.equal(body.unit, "kilocalorie");
      assert.equal(body.caloriesBurnedMetricName, "Calories Burned");
      assert.equal(body.days.length, 1);
      const day = body.days[0];
      assert.equal(day.status, "computed");
      assert.equal(day.energyIn, 2300);
      assert.equal(day.energyOut, 500); // two Readings summed onto the day
      assert.equal(day.net, 1800);

      assert.equal(body.summary.computedDayCount, 1);
      assert.equal(body.summary.averageNet, 1800);
      assert.equal(body.summary.cumulativeNet, 1800);

      // Computed on demand: no Activity Log entry, no rows mutated by the read.
      assert.equal(await activityLogCount(database, userId), 0);
      // No Activity Link created for the meal<->reading proximity.
      assert.equal(await activityLinkCount(database, userId), 0);
    } finally {
      await database.close();
    }
  }
);

dbTest(
  "energy balance: unknown-aware — incomplete in-side or missing Reading is indeterminate, never zeroed",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `xdomain-unknown-${randomUUID()}`;
    const app = createCrossDomainApp(database, userId);

    try {
      await insertUser(database, userId);
      await insertCaloriesBurnedMetric(database, userId);

      // Day 1: energy unknown in the meal but a Reading exists -> indeterminate.
      await insertMeal(database, {
        userId,
        id: mealId("u1m1"),
        mealType: "Lunch",
        startedAt: "2026-06-24T05:00:00.000Z",
        localDate: "2026-06-24"
      });
      await insertFoodEntry(database, {
        userId,
        id: entryId("u1e1"),
        mealId: mealId("u1m1"),
        kind: "quickEntry",
        name: "Mystery",
        // protein stated, energy NOT stated -> energy-in unknown.
        nutrients: {
          protein: { status: "complete", value: 30, entered: "30", unit: "gram" }
        }
      });
      await insertCaloriesBurnedReading(database, {
        userId,
        id: readingId("u1r1"),
        atTime: "2026-06-24T12:00:00.000Z",
        value: 450
      });

      // Day 2: a complete meal but NO Reading -> indeterminate (unknown out-side).
      await insertMeal(database, {
        userId,
        id: mealId("u2m1"),
        mealType: "Lunch",
        startedAt: "2026-06-25T05:00:00.000Z",
        localDate: "2026-06-25"
      });
      await insertFoodEntry(database, {
        userId,
        id: entryId("u2e1"),
        mealId: mealId("u2m1"),
        kind: "quickEntry",
        name: "Bowl",
        nutrients: macros({ energy: 1800, protein: 90, carbohydrate: 200, fat: 50 })
      });

      const response = await getEnergyBalance(app, {
        from: "2026-06-24",
        to: "2026-06-25"
      });
      assert.equal(response.status, 200);
      const body = await response.json();

      const day1 = body.days.find((day) => day.localDate === "2026-06-24");
      assert.equal(day1.status, "indeterminate");
      assert.equal(day1.energyIn, null); // unknown energy-in held out, not 0
      assert.equal(day1.net, null);

      const day2 = body.days.find((day) => day.localDate === "2026-06-25");
      assert.equal(day2.status, "indeterminate");
      assert.equal(day2.energyIn, 1800);
      assert.equal(day2.energyOut, null); // no Reading -> unknown, not implicit 0
      assert.equal(day2.net, null);

      // Neither day is computed -> period rollup withholds averages, not 0.
      assert.equal(body.summary.computedDayCount, 0);
      assert.equal(body.summary.averageNet, null);
      assert.equal(body.summary.cumulativeNet, null);
    } finally {
      await database.close();
    }
  }
);

dbTest(
  "training-day nutrition: protein cohorts + pre/post fuelling joined by time, no stored link",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `xdomain-training-${randomUUID()}`;
    const app = createCrossDomainApp(database, userId);

    try {
      await insertUser(database, userId);

      // 2026-06-24 is a TRAINING day: a logged set in a workout that started 17:00.
      await insertLoggedSet(database, {
        userId,
        id: setId("w1s1"),
        workoutId: "workout-1",
        workoutStartedAt: "2026-06-24T17:00:00.000Z",
        exerciseId: "exercise-bench"
      });
      // 150 g protein on the training day, across two meals around the workout.
      await insertMeal(database, {
        userId,
        id: mealId("t1m1"),
        mealType: "Pre",
        startedAt: "2026-06-24T15:30:00.000Z", // 90 min before -> pre fuelling
        localDate: "2026-06-24"
      });
      await insertFoodEntry(database, {
        userId,
        id: entryId("t1e1"),
        mealId: mealId("t1m1"),
        kind: "quickEntry",
        name: "Pre shake",
        nutrients: macros({ energy: 200, protein: 40, carbohydrate: 10, fat: 2 })
      });
      await insertMeal(database, {
        userId,
        id: mealId("t1m2"),
        mealType: "Post",
        startedAt: "2026-06-24T17:30:00.000Z", // 30 min after -> post fuelling
        localDate: "2026-06-24"
      });
      await insertFoodEntry(database, {
        userId,
        id: entryId("t1e2"),
        mealId: mealId("t1m2"),
        kind: "quickEntry",
        name: "Post meal",
        nutrients: macros({ energy: 800, protein: 110, carbohydrate: 80, fat: 20 })
      });

      // 2026-06-25 is a REST day (no workout): 60 g protein.
      await insertMeal(database, {
        userId,
        id: mealId("r1m1"),
        mealType: "Lunch",
        startedAt: "2026-06-25T12:00:00.000Z",
        localDate: "2026-06-25"
      });
      await insertFoodEntry(database, {
        userId,
        id: entryId("r1e1"),
        mealId: mealId("r1m1"),
        kind: "quickEntry",
        name: "Lunch",
        nutrients: macros({ energy: 600, protein: 60, carbohydrate: 70, fat: 15 })
      });

      const response = await getTrainingDayNutrition(app, {
        from: "2026-06-24",
        to: "2026-06-25",
        preWindowMinutes: 120,
        postWindowMinutes: 120
      });
      assert.equal(response.status, 200);
      const body = await response.json();

      assert.equal(body.proteinUnit, "gram");
      assert.equal(body.trainingDayCount, 1);

      // Training cohort: one day with 150 g protein.
      assert.equal(body.protein.trainingDays.dayCount, 1);
      assert.equal(body.protein.trainingDays.averageProtein, 150);
      // Rest cohort: one day with 60 g.
      assert.equal(body.protein.restDays.dayCount, 1);
      assert.equal(body.protein.restDays.averageProtein, 60);

      // Fuelling: the workout had one pre-meal and one post-meal.
      assert.equal(body.fuelling.summary.workoutCount, 1);
      assert.equal(body.fuelling.summary.workoutsWithPreMeal, 1);
      assert.equal(body.fuelling.summary.workoutsWithPostMeal, 1);
      const workout = body.fuelling.perWorkout[0];
      assert.equal(workout.workoutId, "workout-1");
      assert.equal(workout.preWorkoutMealCount, 1);
      assert.equal(workout.postWorkoutMealCount, 1);
      assert.equal(workout.minutesSincePreWorkoutMeal, 90);
      assert.equal(workout.minutesUntilPostWorkoutMeal, 30);

      // No stored association: no Activity Link and no Activity Log written for
      // the meal<->workout proximity ("join, never merge").
      assert.equal(await activityLinkCount(database, userId), 0);
      assert.equal(await activityLogCount(database, userId), 0);
    } finally {
      await database.close();
    }
  }
);

dbTest(
  "training-day nutrition: incomplete protein day is held out of the cohort average",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `xdomain-incomplete-${randomUUID()}`;
    const app = createCrossDomainApp(database, userId);

    try {
      await insertUser(database, userId);

      // Training day 1: protein unknown -> held out of the average.
      await insertLoggedSet(database, {
        userId,
        id: setId("i1s1"),
        workoutId: "workout-a",
        workoutStartedAt: "2026-06-24T17:00:00.000Z",
        exerciseId: "exercise-x"
      });
      await insertMeal(database, {
        userId,
        id: mealId("i1m1"),
        mealType: "Dinner",
        startedAt: "2026-06-24T18:00:00.000Z",
        localDate: "2026-06-24"
      });
      await insertFoodEntry(database, {
        userId,
        id: entryId("i1e1"),
        mealId: mealId("i1m1"),
        kind: "quickEntry",
        name: "Energy only",
        nutrients: {
          energy: { status: "complete", value: 700, entered: "700", unit: "kilocalorie" }
        }
      });

      // Training day 2: complete protein 120 g.
      await insertLoggedSet(database, {
        userId,
        id: setId("i2s1"),
        workoutId: "workout-b",
        workoutStartedAt: "2026-06-25T17:00:00.000Z",
        exerciseId: "exercise-y"
      });
      await insertMeal(database, {
        userId,
        id: mealId("i2m1"),
        mealType: "Dinner",
        startedAt: "2026-06-25T18:00:00.000Z",
        localDate: "2026-06-25"
      });
      await insertFoodEntry(database, {
        userId,
        id: entryId("i2e1"),
        mealId: mealId("i2m1"),
        kind: "quickEntry",
        name: "Steak",
        nutrients: macros({ energy: 900, protein: 120, carbohydrate: 0, fat: 50 })
      });

      const response = await getTrainingDayNutrition(app, {
        from: "2026-06-24",
        to: "2026-06-25"
      });
      assert.equal(response.status, 200);
      const body = await response.json();

      assert.equal(body.trainingDayCount, 2);
      const cohort = body.protein.trainingDays;
      assert.equal(cohort.dayCount, 2);
      assert.equal(cohort.completeDayCount, 1);
      assert.equal(cohort.incompleteDayCount, 1);
      // Average over the ONE complete day only; the unknown day is not 0.
      assert.equal(cohort.averageProtein, 120);
      assert.equal(cohort.totalProtein, 120);
    } finally {
      await database.close();
    }
  }
);

dbTest(
  "cross-domain reads: data-minimizing — no raw Meal/Workout dump in the body",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `xdomain-minimizing-${randomUUID()}`;
    const app = createCrossDomainApp(database, userId);

    try {
      await insertUser(database, userId);
      await insertLoggedSet(database, {
        userId,
        id: setId("m1s1"),
        workoutId: "workout-secret",
        workoutStartedAt: "2026-06-24T17:00:00.000Z",
        exerciseId: "exercise-secret"
      });
      await insertMeal(database, {
        userId,
        id: mealId("m1m1"),
        mealType: "Dinner",
        startedAt: "2026-06-24T18:00:00.000Z",
        localDate: "2026-06-24"
      });
      await insertFoodEntry(database, {
        userId,
        id: entryId("m1e1"),
        mealId: mealId("m1m1"),
        kind: "quickEntry",
        name: "SecretFoodName",
        nutrients: macros({ energy: 500, protein: 40, carbohydrate: 30, fat: 10 })
      });

      const response = await getTrainingDayNutrition(app, {
        from: "2026-06-24",
        to: "2026-06-24"
      });
      const text = await response.text();
      // The food name and raw meal/entry collections are never exposed.
      assert.equal(text.includes("SecretFoodName"), false);
      assert.equal(text.includes("exercise-secret"), false);
      const body = JSON.parse(text);
      assert.equal("meals" in body, false);
      assert.equal("entries" in body, false);
      assert.equal("foodEntries" in body, false);
    } finally {
      await database.close();
    }
  }
);

dbTest(
  "cross-domain reads: read-only guards — auth required, invalid/oversized ranges rejected, account scoped",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `xdomain-guard-${randomUUID()}`;
    const otherUserId = `xdomain-other-${randomUUID()}`;
    const app = createCrossDomainApp(database, userId);

    try {
      await insertUser(database, userId);
      await insertUser(database, otherUserId);

      // Another account trains and eats on the same day.
      await insertLoggedSet(database, {
        userId: otherUserId,
        id: setId("o1s1"),
        workoutId: "other-workout",
        workoutStartedAt: "2026-06-24T17:00:00.000Z",
        exerciseId: "exercise-other"
      });
      await insertMeal(database, {
        userId: otherUserId,
        id: mealId("o1m1"),
        mealType: "Dinner",
        startedAt: "2026-06-24T18:00:00.000Z",
        localDate: "2026-06-24"
      });
      await insertFoodEntry(database, {
        userId: otherUserId,
        id: entryId("o1e1"),
        mealId: mealId("o1m1"),
        kind: "quickEntry",
        name: "Other meal",
        nutrients: macros({ energy: 999, protein: 99, carbohydrate: 99, fat: 99 })
      });

      // Inverted range -> 422.
      const inverted = await getEnergyBalance(app, {
        from: "2026-06-25",
        to: "2026-06-24"
      });
      assert.equal(inverted.status, 422);
      assert.equal((await inverted.json()).code, "agent_nutrition_read_invalid_range");

      // Oversized range (> 366 days) -> 422.
      const oversized = await getTrainingDayNutrition(app, {
        from: "2024-01-01",
        to: "2026-01-01"
      });
      assert.equal(oversized.status, 422);

      // Unauthenticated -> 401.
      const noAuth = await app.request(
        "/agent/cross-domain/energy-balance?from=2026-06-24&to=2026-06-24",
        { method: "GET" }
      );
      assert.equal(noAuth.status, 401);

      // Account scoping: the authenticated user sees none of the other account's
      // training days or protein.
      const scoped = await getTrainingDayNutrition(app, {
        from: "2026-06-24",
        to: "2026-06-24"
      });
      assert.equal(scoped.status, 200);
      const scopedBody = await scoped.json();
      assert.equal(scopedBody.trainingDayCount, 0);
      assert.equal(scopedBody.fuelling.summary.workoutCount, 0);
      // The authenticated account's one (empty) rest day is a genuine complete
      // zero — never the other account's 99 g protein.
      assert.equal(scopedBody.protein.restDays.totalProtein, 0);

      // No rows mutated and no Activity Log written by any read attempt.
      assert.equal(await activityLogCount(database, userId), 0);
    } finally {
      await database.close();
    }
  }
);

function createCrossDomainApp(database, userId) {
  return createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore(userId),
    agentNutritionReadStore: createDrizzleAgentNutritionReadStore(database.db),
    agentCrossDomainReadStore: createDrizzleAgentCrossDomainReadStore(database.db)
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

function getEnergyBalance(app, query) {
  return app.request(`/agent/cross-domain/energy-balance?${queryString(query)}`, {
    method: "GET",
    headers: { authorization: "Bearer prn_agent_secret" }
  });
}

function getTrainingDayNutrition(app, query) {
  return app.request(
    `/agent/cross-domain/training-day-nutrition?${queryString(query)}`,
    {
      method: "GET",
      headers: { authorization: "Bearer prn_agent_secret" }
    }
  );
}

function queryString(query) {
  return Object.entries(query)
    .map(([key, value]) => `${key}=${encodeURIComponent(value)}`)
    .join("&");
}

async function insertUser(database, userId) {
  await database.db.insert(schema.user).values({
    id: userId,
    name: "Cross Domain User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
}

async function insertMeal(database, { userId, id, mealType, startedAt, localDate }) {
  await database.db.insert(schema.meals).values({
    id,
    userId,
    deviceId: "agent:agent-key-1",
    payload: {
      id,
      meal_type: mealType,
      started_at: startedAt,
      timezone: "UTC",
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
  { userId, id, mealId: parentMealId, kind, name, nutrients }
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
}

async function insertLoggedSet(
  database,
  { userId, id, workoutId, workoutStartedAt, exerciseId }
) {
  await database.db.insert(schema.loggedSets).values({
    id,
    userId,
    deviceId: "agent:agent-key-1",
    payload: {
      id,
      workout_id: workoutId,
      workout_started_at: workoutStartedAt,
      exercise_id: exerciseId,
      exercise_name: exerciseId,
      position: 0,
      values: { reps: { entered: "5", unit: "repetition" } },
      updated_at: workoutStartedAt,
      deleted_at: null
    },
    updatedAt: new Date(workoutStartedAt),
    deletedAt: null
  });
}

async function insertCaloriesBurnedMetric(database, userId) {
  await database.db.insert(schema.metrics).values({
    id: metricId(userId),
    userId,
    deviceId: "agent:agent-key-1",
    name: "Calories Burned",
    unit: "kilocalorie",
    valueShape: "scalar",
    metricGroup: "energy",
    enabled: true,
    pinned: false,
    sortOrder: 0,
    updatedAt: new Date("2026-06-24T00:00:00.000Z"),
    deletedAt: null
  });
}

async function insertCaloriesBurnedReading(database, { userId, id, atTime, value }) {
  await database.db.insert(schema.metricReadings).values({
    id,
    userId,
    deviceId: "agent:agent-key-1",
    metricId: metricId(userId),
    valueJson: { value, unit: "kilocalorie" },
    scalarValue: value,
    scalarEntered: String(value),
    atTime: new Date(atTime),
    windowStartedAt: null,
    windowEndedAt: null,
    provenance: "imported",
    source: "garmin",
    updatedAt: new Date(atTime),
    deletedAt: null
  });
}

async function activityLogCount(database, userId) {
  const rows = await database.sql`
    select id from activity_log where user_id = ${userId}
  `;
  return rows.length;
}

async function activityLinkCount(database, userId) {
  const rows = await database.sql`
    select id from activity_links where user_id = ${userId}
  `;
  return rows.length;
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

const ID_RUN_PREFIX = randomUUID();

function mealId(suffix) {
  return `xmeal-${ID_RUN_PREFIX}-${suffix}`;
}

function entryId(suffix) {
  return `xentry-${ID_RUN_PREFIX}-${suffix}`;
}

function setId(suffix) {
  return `xset-${ID_RUN_PREFIX}-${suffix}`;
}

function readingId(suffix) {
  return `xreading-${ID_RUN_PREFIX}-${suffix}`;
}

function metricId(userId) {
  return `xmetric-${userId}`;
}
