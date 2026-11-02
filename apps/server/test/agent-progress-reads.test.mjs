import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  applyMigrations,
  createAgentMcpServer,
  createApp,
  createDatabaseClient,
  createDrizzleAgentProgressReadStore,
  createDrizzleAgentSettingsStore,
  createInMemoryAgentCatalogStore,
  schema
} from "../src/index.ts";
import { PLATFORM_EXERCISE_SEED_REDIRECTS } from "../src/data/platform-exercise-seed.generated.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

const skip = databaseUrl ? false : "DATABASE_URL is not set.";

// CUJ 13 (docs/designs/progress-overview.md): the week of Monday 26 October to
// Sunday 1 November 2026 against the weekly Routine "Hybrid block" (Monday
// Lower, Tuesday Run intervals, Thursday Upper, Saturday Long run), asked
// about October with today Sunday 1 November.
test(
  "CUJ 13: the training-days read returns October's Trained Days, time per Focus and this week's statuses",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-progress-${randomUUID()}`;
    try {
      await seedUser(database, userId);
      await seedHybridBlock(database, userId);
      await seedWorkouts(database, userId, [
        // This week (CUJ 1).
        workout("w-mon", "2026-10-26", "06:00", "07:00", "f-weights", "t-lower"),
        workout("w-tue", "2026-10-27", "06:00", "06:45", "f-endurance", "t-run"),
        workout("w-wed", "2026-10-28", "07:00", "07:30", null, null),
        workout("w-sat", "2026-10-31", "08:00", "09:00", "f-endurance", "t-spin"),
        // Earlier in October: two Focuses on one date, and an Open Workout.
        workout("w-oct5-am", "2026-10-05", "06:00", "07:00", "f-weights", "t-lower"),
        workout("w-oct5-pm", "2026-10-05", "18:00", "18:20", "f-mobility", null),
        workout("w-oct20-open", "2026-10-20", "06:00", null, "f-weights", null),
        // Started from a template and left with only incomplete Sets (CUJ 5).
        workout("w-oct12-abandoned", "2026-10-12", "06:00", "06:05", "f-weights", "t-lower", {
          sets: [{ is_completed: false }]
        }),
        // Its only completed Set is deleted.
        workout("w-oct13-deleted-set", "2026-10-13", "06:00", "06:30", null, null, {
          sets: [{ is_completed: true, deleted: true }]
        }),
        // Outside the range and outside the week.
        workout("w-sep30", "2026-09-30", "06:00", "07:00", "f-weights", null)
      ]);

      const result = await progressStore(database).readTrainingDays({
        userId,
        from: "2026-10-01",
        to: "2026-10-31",
        today: "2026-11-01"
      });

      assert.equal(result.days.length, 31);
      assert.equal(result.days[0].localDate, "2026-10-01");
      assert.equal(result.days[30].localDate, "2026-10-31");
      const trained = result.days.filter((day) => day.workoutCount > 0);
      assert.deepEqual(trained, [
        {
          localDate: "2026-10-05",
          workoutCount: 2,
          secondsByFocus: { "f-weights": 3600, "f-mobility": 1200 }
        },
        // An Open Workout counts but adds no time and no key.
        { localDate: "2026-10-20", workoutCount: 1, secondsByFocus: {} },
        { localDate: "2026-10-26", workoutCount: 1, secondsByFocus: { "f-weights": 3600 } },
        { localDate: "2026-10-27", workoutCount: 1, secondsByFocus: { "f-endurance": 2700 } },
        { localDate: "2026-10-28", workoutCount: 1, secondsByFocus: { none: 1800 } },
        { localDate: "2026-10-31", workoutCount: 1, secondsByFocus: { "f-endurance": 3600 } }
      ]);
      assert.ok(
        result.days.every((day) => day.workoutCount > 0 || Object.keys(day.secondsByFocus).length === 0)
      );
      assert.equal(result.trainedDayCount, 6);

      assert.deepEqual(result.week, {
        weekStart: "2026-10-26",
        comparedRoutineIds: [`${userId}-hybrid`],
        days: [
          weekDay("2026-10-26", "done", 1, 1, 1),
          weekDay("2026-10-27", "done", 1, 1, 1),
          weekDay("2026-10-28", "trained", 0, 0, 1),
          weekDay("2026-10-29", "not_done", 1, 0, 0),
          weekDay("2026-10-30", "rest", 0, 0, 0),
          weekDay("2026-10-31", "done_differently", 1, 0, 1),
          weekDay("2026-11-01", "rest", 0, 0, 0)
        ],
        counts: { done: 2, partlyDone: 0, doneDifferently: 1, notDone: 1, trained: 1 }
      });
    } finally {
      await database.close();
    }
  }
);

test(
  "a Set payload without is_completed is not performed, and a Set in a deleted Workout is ignored",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-progress-${randomUUID()}`;
    try {
      await seedUser(database, userId);
      await seedHybridBlock(database, userId);
      await seedWorkouts(database, userId, [
        // Linked to the planned template, so it would be Done if it counted.
        workout("w-mon-no-flag", "2026-10-26", "06:00", "07:00", "f-weights", "t-lower", {
          sets: [{}]
        }),
        workout("w-tue-deleted", "2026-10-27", "06:00", "06:45", "f-endurance", "t-run", {
          deleted: true
        })
      ]);

      const result = await progressStore(database).readTrainingDays({
        userId,
        from: "2026-10-26",
        to: "2026-10-28",
        today: "2026-10-28"
      });

      assert.deepEqual(
        result.days.map((day) => [day.localDate, day.workoutCount, day.secondsByFocus]),
        [
          ["2026-10-26", 0, {}],
          ["2026-10-27", 0, {}],
          ["2026-10-28", 0, {}]
        ]
      );
      assert.equal(result.trainedDayCount, 0);
      assert.deepEqual(
        result.week.days.slice(0, 3).map((day) => [day.localDate, day.status, day.workoutCount]),
        [
          ["2026-10-26", "not_done", 0],
          ["2026-10-27", "not_done", 0],
          ["2026-10-28", "rest", 0]
        ]
      );
    } finally {
      await database.close();
    }
  }
);

test(
  "a Routine or entry whose payload cannot be decoded plans nothing instead of failing the read",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-progress-${randomUUID()}`;
    const id = (suffix) => `${userId}-${suffix}`;
    try {
      await seedUser(database, userId);
      await seedHybridBlock(database, userId);
      await database.db.insert(schema.routines).values(
        // A rotating Cadence without its window: cadenceFromRow throws on it.
        opaqueRow({
          id: id("broken-rotation"),
          userId,
          payload: { name: "Broken", cadence_kind: "rotating" }
        })
      );
      await database.db.insert(schema.routineEntries).values(
        // A Wednesday entry of the weekly Routine with no Workout Template.
        opaqueRow({
          id: id("e-broken"),
          userId,
          payload: { routine_id: id("hybrid"), position: 7, slot: 3 }
        })
      );

      const result = await progressStore(database).readTrainingDays({
        userId,
        from: "2026-10-26",
        to: "2026-11-01",
        today: "2026-11-01"
      });

      assert.deepEqual(result.week.comparedRoutineIds, [id("hybrid")]);
      // The Hybrid block's Monday, Tuesday, Thursday and Saturday still plan.
      assert.deepEqual(
        result.week.days.map((day) => day.plannedCount),
        [1, 1, 0, 1, 0, 1, 0]
      );
    } finally {
      await database.close();
    }
  }
);

test(
  "a Sunday weekStartDay starts the week on the Sunday holding today",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-progress-${randomUUID()}`;
    try {
      await seedUser(database, userId);
      await seedHybridBlock(database, userId);
      await database.db.insert(schema.userSettings).values(
        opaqueRow({
          id: `user-settings:${userId}`,
          userId,
          payload: { week_start_day: "sunday" }
        })
      );
      await seedWorkouts(database, userId, [
        workout("w-sun", "2026-11-01", "06:00", "07:00", "f-weights", null),
        // Before the Sunday week, so only the range sees it.
        workout("w-sat", "2026-10-31", "08:00", "09:00", "f-endurance", "t-long")
      ]);

      const result = await progressStore(database).readTrainingDays({
        userId,
        from: "2026-10-31",
        to: "2026-11-01",
        today: "2026-11-01"
      });

      assert.equal(result.trainedDayCount, 2);
      assert.equal(result.week.weekStart, "2026-11-01");
      assert.deepEqual(
        result.week.days.map((day) => [day.localDate, day.status]),
        [
          ["2026-11-01", "trained"],
          ["2026-11-02", "planned"],
          ["2026-11-03", "planned"],
          ["2026-11-04", "rest"],
          ["2026-11-05", "planned"],
          ["2026-11-06", "rest"],
          ["2026-11-07", "planned"]
        ]
      );
      assert.deepEqual(result.week.counts, {
        done: 0,
        partlyDone: 0,
        doneDifferently: 0,
        notDone: 0,
        trained: 1
      });
    } finally {
      await database.close();
    }
  }
);

test(
  "a past range and the current week are read apart, and nothing between them is",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-progress-${randomUUID()}`;
    try {
      await seedUser(database, userId);
      await seedHybridBlock(database, userId);
      await seedWorkouts(database, userId, [
        workout("w-mar", "2026-03-10", "06:00", "07:00", "f-weights", null),
        // Between the range and the week: in neither answer.
        workout("w-jun", "2026-06-10", "06:00", "07:00", "f-weights", null),
        workout("w-mon", "2026-10-26", "06:00", "07:00", "f-weights", "t-lower")
      ]);

      const result = await progressStore(database).readTrainingDays({
        userId,
        from: "2026-03-01",
        to: "2026-03-31",
        today: "2026-11-01"
      });

      assert.deepEqual(
        result.days.filter((day) => day.workoutCount > 0),
        [{ localDate: "2026-03-10", workoutCount: 1, secondsByFocus: { "f-weights": 3600 } }]
      );
      assert.equal(result.week.weekStart, "2026-10-26");
      assert.deepEqual(
        result.week.days.map((day) => [day.localDate, day.status, day.workoutCount]),
        [
          ["2026-10-26", "done", 1],
          ["2026-10-27", "not_done", 0],
          ["2026-10-28", "rest", 0],
          ["2026-10-29", "not_done", 0],
          ["2026-10-30", "rest", 0],
          ["2026-10-31", "not_done", 0],
          ["2026-11-01", "rest", 0]
        ]
      );
    } finally {
      await database.close();
    }
  }
);

// The app's Drift columns hold whole epoch seconds, so the server reads every
// instant at that precision: the same seconds by Focus, and the same Template
// Link when two were updated within one second (the highest id wins a tie).
test(
  "instants are read to the whole second, as the app stores them",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-progress-${randomUUID()}`;
    const id = (suffix) => `${userId}-${suffix}`;
    try {
      await seedUser(database, userId);
      await seedHybridBlock(database, userId);
      const workoutId = id("w-mon");
      await database.db.insert(schema.workoutSessions).values(
        opaqueRow({
          id: workoutId,
          userId,
          payload: {
            local_date: "2026-10-26",
            // 3 599.2 s at millisecond precision; 3 600 s to the second.
            started_at: "2026-10-26T06:00:00.900Z",
            ended_at: "2026-10-26T07:00:00.100Z",
            focus_id: "f-weights"
          }
        })
      );
      await database.db.insert(schema.loggedSets).values(
        opaqueRow({
          id: `${workoutId}-set-0`,
          userId,
          payload: { workout_id: workoutId, exercise_id: "exercise-1", position: 0, is_completed: true }
        })
      );
      const link = (suffix, template, updatedAt) => ({
        ...opaqueRow({
          id: `${workoutId}-${suffix}`,
          userId,
          payload: {
            workout_id: workoutId,
            workout_template_id: id(template),
            routine_id: null,
            slot: null
          }
        }),
        updatedAt: new Date(updatedAt)
      });
      await database.db.insert(schema.templateLinks).values([
        // Later by milliseconds only, so the same second as link-b.
        link("link-a", "t-lower", "2026-10-26T08:00:00.900Z"),
        link("link-b", "t-run", "2026-10-26T08:00:00.100Z")
      ]);

      const result = await progressStore(database).readTrainingDays({
        userId,
        from: "2026-10-26",
        to: "2026-10-26",
        today: "2026-10-27"
      });

      assert.deepEqual(result.days, [
        { localDate: "2026-10-26", workoutCount: 1, secondsByFocus: { "f-weights": 3600 } }
      ]);
      // Linked to Run intervals, not the planned Lower.
      assert.equal(result.week.days[0].status, "done_differently");
    } finally {
      await database.close();
    }
  }
);

// CUJ 9 (docs/designs/progress-overview.md): before the period the fastest
// "5 km run" was 5:22 /km; on Saturday 31 October they ran 5:04 /km. Each Set
// that would beat it without counting is ignored: an incomplete one, one in a
// deleted Workout, and another account's.
test(
  "CUJ 9: the New Bests read judges the period against earlier history and reads only Performed Sets",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-progress-${randomUUID()}`;
    const otherUserId = `agent-progress-${randomUUID()}`;
    const id = (suffix) => `${userId}-${suffix}`;
    const run = id("5k-run");
    const squat = id("squat");
    try {
      await seedUser(database, userId);
      await seedUser(database, otherUserId);
      await seedWorkouts(database, userId, [
        // Before the period: 5:22 /km, then a slower 5:30 /km.
        workout("w-sep26", "2026-09-26", "07:00", "07:30", null, null, {
          sets: [runSet(run, 1610)]
        }),
        workout("w-oct17", "2026-10-17", "07:00", "07:30", null, null, {
          sets: [runSet(run, 1650)]
        }),
        // Faster, but not Performed.
        workout("w-oct29", "2026-10-29", "07:00", "07:30", null, null, {
          sets: [runSet(run, 1400, { is_completed: false })]
        }),
        // Faster, but its Workout is deleted.
        workout("w-oct30-deleted", "2026-10-30", "07:00", "07:30", null, null, {
          deleted: true,
          sets: [runSet(run, 1400)]
        }),
        // Saturday: 5:04 /km, a New Best.
        workout("w-oct31", "2026-10-31", "07:00", "07:30", null, null, {
          sets: [runSet(run, 1520)]
        }),
        // A heavier squat on 28 October is a New Best for e1RM (Brzycki:
        // 100 x 5 is 112.5 kg, 110 x 5 is 123.75 kg).
        workout("w-oct3", "2026-10-03", "06:00", "07:00", null, null, {
          sets: [squatSet(squat, 100, 5)]
        }),
        workout("w-oct28", "2026-10-28", "06:00", "07:00", null, null, {
          sets: [squatSet(squat, 110, 5)]
        })
      ]);
      // Another account's faster run on the same exercise id.
      await seedWorkouts(database, otherUserId, [
        workout("w-oct30", "2026-10-30", "07:00", "07:30", null, null, {
          sets: [runSet(run, 1300)]
        })
      ]);

      const result = await progressStore(database, [
        catalogExercise(userId, run, "5 km run", {
          dimensions: ["distance", "duration"],
          recordProfile: "fastestPace",
          favorite: true
        }),
        catalogExercise(userId, squat, "Back squat")
      ]).readNewBests({ userId, from: "2026-10-05", to: "2026-11-01" });

      assert.deepEqual(result, {
        newBests: [
          {
            exerciseId: run,
            exerciseName: "5 km run",
            measure: "fastestPace",
            workoutId: id("w-oct31"),
            localDate: "2026-10-31",
            startedAt: "2026-10-31T07:00:00.000Z",
            setId: `${id("w-oct31")}-set-0`,
            value: 304,
            unit: "second"
          },
          {
            exerciseId: squat,
            exerciseName: "Back squat",
            measure: "estimatedOneRepMax",
            workoutId: id("w-oct28"),
            localDate: "2026-10-28",
            startedAt: "2026-10-28T06:00:00.000Z",
            setId: `${id("w-oct28")}-set-0`,
            value: 123.75,
            unit: "kilogram"
          }
        ]
      });

      // A period after the bests has none, and one holding only the first
      // squat has none either: the first point is never a New Best.
      for (const [from, to] of [
        ["2026-11-01", "2026-11-01"],
        ["2026-10-01", "2026-10-05"]
      ]) {
        assert.deepEqual(
          await progressStore(database, [
            catalogExercise(userId, run, "5 km run", {
              dimensions: ["distance", "duration"],
              recordProfile: "fastestPace"
            }),
            catalogExercise(userId, squat, "Back squat")
          ]).readNewBests({ userId, from, to }),
          { newBests: [] }
        );
      }
    } finally {
      await database.close();
    }
  }
);

test(
  "an archived user exercise has no New Bests, but its Workouts still count as Trained Days",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-progress-${randomUUID()}`;
    const id = (suffix) => `${userId}-${suffix}`;
    const archived = id("old-squat");
    try {
      await seedUser(database, userId);
      await seedWorkouts(database, userId, [
        workout("w-oct3", "2026-10-03", "06:00", "07:00", "f-weights", null, {
          sets: [squatSet(archived, 100, 5)]
        }),
        workout("w-oct28", "2026-10-28", "06:00", "07:00", "f-weights", null, {
          sets: [squatSet(archived, 120, 5)]
        })
      ]);
      const store = progressStore(database, [
        catalogExercise(userId, archived, "Old squat", { active: false })
      ]);

      assert.deepEqual(
        await store.readNewBests({ userId, from: "2026-10-01", to: "2026-10-31" }),
        { newBests: [] }
      );
      const days = await store.readTrainingDays({
        userId,
        from: "2026-10-01",
        to: "2026-10-31",
        today: "2026-11-01"
      });
      assert.equal(days.trainedDayCount, 2);
    } finally {
      await database.close();
    }
  }
);

// D4: a Platform exercise hidden by a same-named User Library exercise is
// still active in the app, so its New Bests are listed here too.
test(
  "a Platform exercise shadowed by a same-named user exercise keeps its New Bests",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-progress-${randomUUID()}`;
    const platform = `${userId}-platform-bench`;
    try {
      await seedUser(database, userId);
      await seedWorkouts(database, userId, [
        workout("w-oct3", "2026-10-03", "06:00", "07:00", null, null, {
          sets: [squatSet(platform, 100, 5)]
        }),
        workout("w-oct28", "2026-10-28", "06:00", "07:00", null, null, {
          sets: [squatSet(platform, 110, 5)]
        })
      ]);
      const result = await progressStore(database, [
        { ...catalogExercise(null, platform, "Bench press"), library: "platform" },
        catalogExercise(userId, `${userId}-user-bench`, "Bench press")
      ]).readNewBests({ userId, from: "2026-10-05", to: "2026-10-31" });

      assert.deepEqual(
        result.newBests.map((best) => [best.exerciseId, best.exerciseName, best.workoutId]),
        [[platform, "Bench press", `${userId}-w-oct28`]]
      );
    } finally {
      await database.close();
    }
  }
);

// D9: the exercise read filters Sets in SQL by exercise id, so it must still
// find a Set logged under a seed redirect's old id, and no other exercise's.
test(
  "the exercise progress read takes Sets logged under a redirected id and no other exercise's",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-progress-${randomUUID()}`;
    const [redirect] = PLATFORM_EXERCISE_SEED_REDIRECTS;
    try {
      await seedUser(database, userId);
      await seedWorkouts(database, userId, [
        workout("w-oct3", "2026-10-03", "06:00", "07:00", null, null, {
          sets: [squatSet(redirect.fromExerciseId, 100, 5)]
        }),
        workout("w-oct28", "2026-10-28", "06:00", "07:00", null, null, {
          sets: [squatSet(redirect.toExerciseId, 110, 5), squatSet(`${userId}-other`, 200, 5)]
        })
      ]);
      const workouts = await progressStore(database).readExerciseProgressSets({
        userId,
        exerciseId: redirect.toExerciseId
      });

      assert.deepEqual(
        workouts
          .map((one) => [one.workoutId, one.sets.map((set) => set.id)])
          .sort(([left], [right]) => left.localeCompare(right)),
        [
          [`${userId}-w-oct28`, [`${userId}-w-oct28-set-0`]],
          [`${userId}-w-oct3`, [`${userId}-w-oct3-set-0`]]
        ]
      );
    } finally {
      await database.close();
    }
  }
);

test("the New Bests read refuses a bad range with 400 before the store, as REST and MCP", async () => {
  const { app, calls } = progressApp();
  const today = utcToday();
  const refused = [
    // 367 dates, both ends included.
    { fromLocalDate: addDays(today, -366), toLocalDate: today },
    // fromLocalDate after toLocalDate.
    { fromLocalDate: today, toLocalDate: addDays(today, -1) }
  ];
  for (const query of refused) {
    const response = await agentGet(app, newBestsPath(query));
    assert.equal(response.status, 400, JSON.stringify(query));
    const body = await response.json();
    assert.equal(body.code, "agent_progress_read_invalid_range", JSON.stringify(query));
    assert.ok(body.message.length > 0);

    const tool = await callTool(app, "agent_list_new_bests", query);
    assert.equal(tool.isError, true, JSON.stringify(query));
    assert.equal(tool.structuredContent.code, "agent_progress_read_invalid_range");
    assert.equal(tool.structuredContent.message, body.message);
  }
  for (const bad of ["2026-02-30", "26-10-01", ""]) {
    for (const query of [
      { fromLocalDate: bad, toLocalDate: today },
      { fromLocalDate: today, toLocalDate: bad }
    ]) {
      const response = await agentGet(app, newBestsPath(query));
      assert.equal(response.status, 400, JSON.stringify(query));
      assert.equal((await response.json()).success, false, JSON.stringify(query));
    }
  }
  assert.deepEqual(calls, []);

  // 366 dates, both ends included, is accepted.
  const accepted = { fromLocalDate: addDays(today, -365), toLocalDate: today };
  const response = await agentGet(app, newBestsPath(accepted));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { newBests: [] });
  const tool = await callTool(app, "agent_list_new_bests", accepted);
  assert.equal(tool.isError, undefined);
  assert.deepEqual(tool.structuredContent, { newBests: [] });
  assert.deepEqual(calls, [
    { userId: "user-1", from: accepted.fromLocalDate, to: today },
    { userId: "user-1", from: accepted.fromLocalDate, to: today }
  ]);
});

test("the training-days read refuses a bad range with 400 before the store, as REST and MCP", async () => {
  const { app, calls } = progressApp();
  const today = utcToday();
  const refused = [
    // 367 dates, both ends included.
    { fromLocalDate: addDays(today, -366), toLocalDate: today, today },
    // fromLocalDate after toLocalDate.
    { fromLocalDate: today, toLocalDate: addDays(today, -1), today },
    // toLocalDate after today.
    { fromLocalDate: today, toLocalDate: addDays(today, 1), today },
    // today two days from the server's UTC date.
    {
      fromLocalDate: addDays(today, -1),
      toLocalDate: addDays(today, 2),
      today: addDays(today, 2)
    }
  ];
  for (const query of refused) {
    const response = await agentGet(app, trainingDaysPath(query));
    assert.equal(response.status, 400, JSON.stringify(query));
    const body = await response.json();
    assert.equal(body.code, "agent_progress_read_invalid_range", JSON.stringify(query));
    assert.ok(body.message.length > 0);

    const tool = await callTrainingDaysTool(app, query);
    assert.equal(tool.isError, true, JSON.stringify(query));
    assert.equal(tool.structuredContent.code, "agent_progress_read_invalid_range");
    assert.equal(tool.structuredContent.message, body.message);
    // In this read's terms: a training read has no Protocol Day Status.
    assert.doesNotMatch(body.message, /Day Status/);
  }
  assert.deepEqual(calls, []);

  // 366 dates, both ends included, is accepted.
  const accepted = { fromLocalDate: addDays(today, -365), toLocalDate: today, today };
  const response = await agentGet(app, trainingDaysPath(accepted));
  assert.equal(response.status, 200);
  const tool = await callTrainingDaysTool(app, accepted);
  assert.equal(tool.isError, undefined);
  assert.deepEqual(tool.structuredContent, await response.json());
  assert.deepEqual(calls, [
    { userId: "user-1", from: accepted.fromLocalDate, to: today, today },
    { userId: "user-1", from: accepted.fromLocalDate, to: today, today }
  ]);
});

test("the training-days read refuses a date that is not a real YYYY-MM-DD date in the validator's own 400 body", async () => {
  const { app, calls } = progressApp();
  const today = utcToday();
  for (const bad of ["2026-02-30", "2026-13-01", "26-10-01", ""]) {
    for (const query of [
      { fromLocalDate: bad, toLocalDate: today, today },
      { fromLocalDate: today, toLocalDate: bad, today },
      { fromLocalDate: today, toLocalDate: today, today: bad }
    ]) {
      const response = await agentGet(app, trainingDaysPath(query));
      assert.equal(response.status, 400, JSON.stringify(query));
      const body = await response.json();
      assert.equal(body.success, false, JSON.stringify(query));
      assert.equal(body.code, undefined, JSON.stringify(query));
    }
  }
  // today is required.
  const missing = await agentGet(
    app,
    trainingDaysPath({ fromLocalDate: today, toLocalDate: today })
  );
  assert.equal(missing.status, 400);
  assert.deepEqual(calls, []);
});

test("the progress reads answer 503 when the progress store is not configured", async () => {
  const agentApiKeyStore = createAgentKeyStore("user-1");
  const app = createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore,
    createMcpServer: () =>
      createAgentMcpServer({ agentApiKeyStore, logger: { info() {}, error() {} } })
  });
  const today = utcToday();
  const query = { fromLocalDate: today, toLocalDate: today, today };

  const response = await agentGet(app, trainingDaysPath(query));
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), {
    code: "agent_progress_read_unavailable",
    message: "Agent progress read storage is not configured."
  });

  const tool = await callTrainingDaysTool(app, query);
  assert.equal(tool.isError, true);
  assert.equal(tool.structuredContent.code, "agent_progress_read_unavailable");

  const newBestsQuery = { fromLocalDate: today, toLocalDate: today };
  const newBests = await agentGet(app, newBestsPath(newBestsQuery));
  assert.equal(newBests.status, 503);
  assert.equal((await newBests.json()).code, "agent_progress_read_unavailable");
  const newBestsTool = await callTool(app, "agent_list_new_bests", newBestsQuery);
  assert.equal(newBestsTool.isError, true);
  assert.equal(newBestsTool.structuredContent.code, "agent_progress_read_unavailable");
});

function progressApp() {
  const calls = [];
  const store = {
    async readTrainingDays(input) {
      calls.push(input);
      return emptyResponse(input.today);
    },
    async readNewBests(input) {
      calls.push(input);
      return { newBests: [] };
    },
    async readExerciseProgressSets() {
      throw new Error("readExerciseProgressSets should not be called.");
    }
  };
  const agentApiKeyStore = createAgentKeyStore("user-1");
  const app = createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore,
    agentProgressReadStore: store,
    createMcpServer: () =>
      createAgentMcpServer({
        agentApiKeyStore,
        agentProgressReadStore: store,
        logger: { info() {}, error() {} }
      })
  });
  return { app, calls };
}

function emptyResponse(today) {
  return {
    days: [],
    trainedDayCount: 0,
    week: {
      weekStart: today,
      days: Array.from({ length: 7 }, (_, index) =>
        weekDay(addDays(today, index), "no_plan", 0, 0, 0)
      ),
      counts: { done: 0, partlyDone: 0, doneDifferently: 0, notDone: 0, trained: 0 },
      comparedRoutineIds: []
    }
  };
}

function progressStore(database, exercises = []) {
  return createDrizzleAgentProgressReadStore({
    db: database.db,
    settingsStore: createDrizzleAgentSettingsStore(database.db),
    catalogStore: createInMemoryAgentCatalogStore(exercises)
  });
}

function catalogExercise(
  userId,
  id,
  name,
  { dimensions = ["load", "reps"], recordProfile = "repMax", favorite = false, active = true } = {}
) {
  return {
    id,
    library: "user",
    ownerUserId: userId,
    name,
    category: null,
    dimensions,
    equipment: [],
    loadMode: "added",
    recordProfile,
    favorite,
    active,
    shadowedPlatformExerciseId: null
  };
}

function runSet(exerciseId, seconds, fields = {}) {
  return {
    is_completed: true,
    exercise_id: exerciseId,
    values: {
      distance: { entered: "5", unit: "kilometer" },
      duration: { entered: String(seconds), unit: "second" }
    },
    ...fields
  };
}

function squatSet(exerciseId, kilograms, reps) {
  return {
    is_completed: true,
    exercise_id: exerciseId,
    values: {
      load: { entered: String(kilograms), unit: "kilogram" },
      reps: { entered: String(reps), unit: "repetition" }
    }
  };
}

function weekDay(localDate, status, plannedCount, matchedCount, workoutCount) {
  return { localDate, status, plannedCount, matchedCount, workoutCount };
}

async function seedUser(database, userId) {
  await database.db.insert(schema.user).values({
    id: userId,
    name: "Agent Progress User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
}

/**
 * "Hybrid block" (Monday Lower, Tuesday Run intervals, Thursday Upper,
 * Saturday Long run) plus what must plan nothing: an archived entry, an entry
 * with no slot, an entry of an archived template, and a rotating Routine.
 * Row ids are prefixed per user because ids are global.
 */
async function seedHybridBlock(database, userId) {
  const id = (suffix) => `${userId}-${suffix}`;
  await database.db.insert(schema.workoutTemplates).values([
    ...[
      ["t-lower", "Lower"],
      ["t-run", "Run intervals"],
      ["t-upper", "Upper"],
      ["t-long", "Long run"],
      ["t-spin", "Easy spin"]
    ].map(([suffix, name]) => opaqueRow({ id: id(suffix), userId, payload: { name } })),
    opaqueRow({
      id: id("t-archived"),
      userId,
      deleted: true,
      payload: { name: "Archived" }
    })
  ]);
  await database.db.insert(schema.routines).values([
    opaqueRow({
      id: id("hybrid"),
      userId,
      payload: { name: "Hybrid block", cadence_kind: "weekly", cadence_window: null }
    }),
    opaqueRow({
      id: id("rotation"),
      userId,
      payload: { name: "Rotation", cadence_kind: "rotating", cadence_window: 4 }
    })
  ]);
  const entry = (suffix, routine, template, position, slot, deleted = false) =>
    opaqueRow({
      id: id(suffix),
      userId,
      deleted,
      payload: {
        routine_id: id(routine),
        workout_template_id: id(template),
        position,
        slot
      }
    });
  await database.db.insert(schema.routineEntries).values([
    entry("e-lower", "hybrid", "t-lower", 0, 1),
    entry("e-run", "hybrid", "t-run", 1, 2),
    entry("e-upper", "hybrid", "t-upper", 2, 4),
    entry("e-long", "hybrid", "t-long", 3, 6),
    entry("e-archived", "hybrid", "t-upper", 4, 3, true),
    entry("e-no-slot", "hybrid", "t-upper", 5, null),
    entry("e-archived-template", "hybrid", "t-archived", 6, 5),
    entry("e-rotation", "rotation", "t-upper", 0, 7)
  ]);
}

function workout(suffix, localDate, start, end, focusId, templateSuffix, options = {}) {
  return { suffix, localDate, start, end, focusId, templateSuffix, ...options };
}

async function seedWorkouts(database, userId, workouts) {
  const id = (suffix) => `${userId}-${suffix}`;
  for (const entry of workouts) {
    const workoutId = id(entry.suffix);
    await database.db.insert(schema.workoutSessions).values(
      opaqueRow({
        id: workoutId,
        userId,
        deleted: entry.deleted ?? false,
        payload: {
          local_date: entry.localDate,
          started_at: `${entry.localDate}T${entry.start}:00.000Z`,
          ended_at: entry.end === null ? null : `${entry.localDate}T${entry.end}:00.000Z`,
          focus_id: entry.focusId
        }
      })
    );
    const sets = entry.sets ?? [{ is_completed: true }];
    await database.db.insert(schema.loggedSets).values(
      sets.map(({ deleted = false, ...fields }, index) =>
        opaqueRow({
          id: `${workoutId}-set-${index}`,
          userId,
          deleted,
          payload: { workout_id: workoutId, exercise_id: "exercise-1", position: index, ...fields }
        })
      )
    );
    if (entry.templateSuffix !== null) {
      await database.db.insert(schema.templateLinks).values(
        opaqueRow({
          id: `${workoutId}-link`,
          userId,
          payload: {
            workout_id: workoutId,
            workout_template_id: id(entry.templateSuffix),
            routine_id: null,
            slot: null
          }
        })
      );
    }
  }
}

function opaqueRow({ id, userId, payload, deleted = false }) {
  const at = new Date("2026-11-01T08:00:00.000Z");
  return {
    id,
    userId,
    deviceId: "device-a",
    payload: {
      id,
      ...payload,
      updated_at: at.toISOString(),
      deleted_at: deleted ? at.toISOString() : null
    },
    updatedAt: at,
    deletedAt: deleted ? at : null,
    receivedAt: at
  };
}

function createAgentKeyStore(userId) {
  return {
    async authenticateAgentApiKey(secret) {
      if (secret !== "prn_agent_secret") {
        return null;
      }
      return { userId, keyId: "agent-key-1", keyName: "Progress coach" };
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

function trainingDaysPath(query) {
  return `/agent/progress/training-days?${new URLSearchParams(query).toString()}`;
}

function agentGet(app, path) {
  return app.request(path, {
    headers: { authorization: "Bearer prn_agent_secret" }
  });
}

function newBestsPath(query) {
  return `/agent/progress/new-bests?${new URLSearchParams(query).toString()}`;
}

function callTrainingDaysTool(app, query) {
  return callTool(app, "agent_list_training_days", query);
}

async function callTool(app, name, query) {
  const response = await app.request("/mcp", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      accept: "application/json, text/event-stream",
      authorization: "Bearer prn_agent_secret"
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "tools/call",
      params: { name, arguments: { query } }
    })
  });
  assert.equal(response.status, 200);
  return (await response.json()).result;
}

function utcToday() {
  return new Date().toISOString().slice(0, 10);
}

function addDays(localDate, days) {
  const date = new Date(`${localDate}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}
