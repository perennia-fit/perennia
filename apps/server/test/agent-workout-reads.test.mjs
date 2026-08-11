import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  applyMigrations,
  createApp,
  createDatabaseClient,
  createDrizzleAgentReadStore,
  createDrizzleRateLimitBackend,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

test(
  "agent workouts read groups logged sets into bounded workout envelopes, date-filtered with limit/cursor/fields",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-workouts-read-user-${randomUUID()}`;
    const workoutIds = {
      first: randomUUID(),
      second: randomUUID(),
      third: randomUUID()
    };
    const app = createAgentWorkoutReadApp({
      agentReadStore: createDrizzleAgentReadStore(database.db),
      userId
    });

    try {
      await seedUser(database, userId);

      // Workout 1 (2026-06-01): two sets, two different exercises.
      await seedLoggedSet(database, {
        userId,
        id: randomUUID(),
        workoutId: workoutIds.first,
        startedAt: "2026-06-01T10:00:00.000Z",
        endedAt: "2026-06-01T11:00:00.000Z",
        comment: "Leg day",
        exerciseId: "user-back-squat",
        exerciseName: "Back Squat",
        position: 0,
        values: { load: { entered: "100", unit: "kilogram" }, reps: { entered: "5", unit: "repetition" } }
      });
      await seedLoggedSet(database, {
        userId,
        id: randomUUID(),
        workoutId: workoutIds.first,
        startedAt: "2026-06-01T10:00:00.000Z",
        endedAt: "2026-06-01T11:00:00.000Z",
        comment: "Leg day",
        exerciseId: "platform-bench-press",
        exerciseName: "Bench Press",
        position: 1,
        values: { load: { entered: "80", unit: "kilogram" }, reps: { entered: "6", unit: "repetition" } }
      });

      // Workout 2 (2026-06-08): one set.
      await seedLoggedSet(database, {
        userId,
        id: randomUUID(),
        workoutId: workoutIds.second,
        startedAt: "2026-06-08T10:00:00.000Z",
        endedAt: null,
        comment: null,
        exerciseId: "user-back-squat",
        exerciseName: "Back Squat",
        position: 0,
        values: { load: { entered: "120", unit: "kilogram" }, reps: { entered: "3", unit: "repetition" } }
      });

      // Workout 3 (2026-07-01): outside the requested date range.
      await seedLoggedSet(database, {
        userId,
        id: randomUUID(),
        workoutId: workoutIds.third,
        startedAt: "2026-07-01T10:00:00.000Z",
        endedAt: null,
        comment: null,
        exerciseId: "user-back-squat",
        exerciseName: "Back Squat",
        position: 0,
        values: { load: { entered: "50", unit: "kilogram" }, reps: { entered: "10", unit: "repetition" } }
      });

      // Minimal default fields.
      const defaultResponse = await getAgent(
        app,
        "/agent/workouts?from=2026-06-01T00:00:00.000Z&to=2026-06-30T00:00:00.000Z"
      );
      assert.equal(defaultResponse.status, 200);
      const defaultBody = await defaultResponse.json();
      assert.equal(defaultBody.totalMatched, 2);
      assert.equal(defaultBody.limit, 50);
      const firstWorkout = defaultBody.workouts.find(
        (workout) => workout.id === workoutIds.first
      );
      assert.ok(firstWorkout, "workout 1 should be present");
      // Minimal default field set: id, startedAt only unless more requested.
      assert.deepEqual(defaultBody.fields, ["id", "startedAt"]);
      assert.equal(firstWorkout.setCount, undefined);
      assert.equal(firstWorkout.exerciseNames, undefined);
      assert.equal(firstWorkout.endedAt, undefined);
      assert.equal(firstWorkout.comment, undefined);

      // fields projection widens the response.
      const projectedResponse = await getAgent(
        app,
        "/agent/workouts?from=2026-06-01T00:00:00.000Z&to=2026-06-30T00:00:00.000Z&fields=id,startedAt,endedAt,timezone,comment,setCount,exerciseNames"
      );
      assert.equal(projectedResponse.status, 200);
      const projectedBody = await projectedResponse.json();
      const projectedFirst = projectedBody.workouts.find(
        (workout) => workout.id === workoutIds.first
      );
      assert.equal(projectedFirst.endedAt, "2026-06-01T11:00:00.000Z");
      assert.equal(projectedFirst.timezone, "Australia/Brisbane");
      assert.equal(projectedFirst.comment, "Leg day");
      assert.equal(projectedFirst.setCount, 2);
      assert.deepEqual([...projectedFirst.exerciseNames].sort(), [
        "Back Squat",
        "Bench Press"
      ]);

      // limit + cursor pagination.
      const pagedFirst = await getAgent(
        app,
        "/agent/workouts?from=2026-06-01T00:00:00.000Z&to=2026-06-30T00:00:00.000Z&limit=1"
      );
      assert.equal(pagedFirst.status, 200);
      const pagedFirstBody = await pagedFirst.json();
      assert.equal(pagedFirstBody.workouts.length, 1);
      assert.ok(pagedFirstBody.nextCursor);

      const pagedSecond = await getAgent(
        app,
        `/agent/workouts?from=2026-06-01T00:00:00.000Z&to=2026-06-30T00:00:00.000Z&limit=1&cursor=${pagedFirstBody.nextCursor}`
      );
      assert.equal(pagedSecond.status, 200);
      const pagedSecondBody = await pagedSecond.json();
      assert.equal(pagedSecondBody.workouts.length, 1);
      assert.equal(pagedSecondBody.nextCursor, null);
      assert.notEqual(pagedSecondBody.workouts[0].id, pagedFirstBody.workouts[0].id);
    } finally {
      await database.close();
    }
  }
);

test(
  "agent workouts read excludes archived (tombstoned) sets from the derived envelope and isolates by account",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-workouts-read-tenant-user-${randomUUID()}`;
    const otherUserId = `agent-workouts-read-other-user-${randomUUID()}`;
    const workoutId = randomUUID();
    const app = createAgentWorkoutReadApp({
      agentReadStore: createDrizzleAgentReadStore(database.db),
      userId
    });

    try {
      await seedUser(database, userId);
      await seedUser(database, otherUserId);

      await seedLoggedSet(database, {
        userId,
        id: randomUUID(),
        workoutId,
        startedAt: "2026-06-10T10:00:00.000Z",
        endedAt: null,
        comment: null,
        exerciseId: "user-back-squat",
        exerciseName: "Back Squat",
        position: 0,
        values: { load: { entered: "100", unit: "kilogram" }, reps: { entered: "5", unit: "repetition" } }
      });
      const archivedSetId = randomUUID();
      await seedLoggedSet(database, {
        userId,
        id: archivedSetId,
        workoutId,
        startedAt: "2026-06-10T10:00:00.000Z",
        endedAt: null,
        comment: null,
        exerciseId: "platform-bench-press",
        exerciseName: "Bench Press",
        position: 1,
        values: { load: { entered: "80", unit: "kilogram" }, reps: { entered: "6", unit: "repetition" } },
        deletedAt: "2026-06-10T12:00:00.000Z"
      });
      await seedLoggedSet(database, {
        userId: otherUserId,
        id: randomUUID(),
        workoutId: randomUUID(),
        startedAt: "2026-06-10T10:00:00.000Z",
        endedAt: null,
        comment: null,
        exerciseId: "user-back-squat",
        exerciseName: "Back Squat",
        position: 0,
        values: { load: { entered: "999", unit: "kilogram" }, reps: { entered: "1", unit: "repetition" } }
      });

      const response = await getAgent(
        app,
        "/agent/workouts?from=2026-06-01T00:00:00.000Z&to=2026-06-30T00:00:00.000Z&fields=id,setCount,exerciseNames"
      );
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.totalMatched, 1);
      assert.equal(body.workouts[0].id, workoutId);
      assert.equal(body.workouts[0].setCount, 1);
      assert.deepEqual(body.workouts[0].exerciseNames, ["Back Squat"]);
    } finally {
      await database.close();
    }
  }
);

test(
  "agent Workout and history reads hydrate mobile-synced Exercise identity and preserve Set execution fields",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-mobile-workout-read-user-${randomUUID()}`;
    const workoutId = randomUUID();
    const setId = randomUUID();
    const exerciseId = "01910000-0000-7000-8000-802196414109";
    const app = createAgentWorkoutReadApp({
      agentReadStore: createDrizzleAgentReadStore(database.db),
      userId
    });

    try {
      await seedUser(database, userId);
      await database.db.insert(schema.loggedSets).values({
        id: setId,
        userId,
        deviceId: "phone-mobile-payload",
        updatedAt: new Date("2026-07-26T07:33:14.000Z"),
        receivedAt: new Date("2026-07-26T07:33:15.000Z"),
        deletedAt: null,
        payload: {
          id: setId,
          workout_id: workoutId,
          exercise_id: exerciseId,
          position: 0,
          planned_rest_after: 90,
          performed_at: null,
          is_completed: false,
          load_value: 8,
          load_unit: "kilogram",
          load_entered: "8",
          reps_value: 3,
          reps_unit: "repetition",
          reps_entered: "3",
          comment: null,
          side: null,
          rpe: null,
          updated_at: "2026-07-26T07:33:14.000Z",
          deleted_at: null
        }
      });

      const historyResponse = await getAgent(
        app,
        `/agent/history/sets?exerciseId=${exerciseId}&limit=10`
      );
      assert.equal(historyResponse.status, 200);
      const history = await historyResponse.json();
      assert.equal(history.sets.length, 1);
      assert.equal(history.sets[0].exerciseName, "Kettlebell Turkish Get Up");
      assert.equal(history.sets[0].performedAt, null);
      assert.equal(history.sets[0].isCompleted, false);
      assert.equal(history.sets[0].plannedRestAfter, 90);

      const workoutsResponse = await getAgent(
        app,
        "/agent/workouts?fields=id,startedAt,setCount,exerciseNames"
      );
      assert.equal(workoutsResponse.status, 200);
      const workouts = await workoutsResponse.json();
      assert.equal(workouts.workouts[0].id, workoutId);
      assert.deepEqual(workouts.workouts[0].exerciseNames, [
        "Kettlebell Turkish Get Up"
      ]);
    } finally {
      await database.close();
    }
  }
);

test(
  "agent Workout detail prefers synchronized Workout metadata and structure over Set inference",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-authoritative-workout-read-user-${randomUUID()}`;
    const workoutId = randomUUID();
    const emptyWorkoutId = randomUUID();
    const workoutExerciseId = randomUUID();
    const groupId = randomUUID();
    const memberId = randomUUID();
    const setId = randomUUID();
    const exerciseId = "01910000-0000-7000-8000-802196414109";
    const app = createAgentWorkoutReadApp({
      agentReadStore: createDrizzleAgentReadStore(database.db),
      userId
    });
    const updatedAt = new Date("2026-07-26T08:30:00.000Z");
    const opaqueEnvelope = {
      userId,
      deviceId: "phone-authoritative-workout",
      updatedAt,
      receivedAt: new Date("2026-07-26T08:30:01.000Z"),
      deletedAt: null
    };

    try {
      await seedUser(database, userId);
      await database.db.insert(schema.workoutSessions).values({
        ...opaqueEnvelope,
        id: workoutId,
        payload: {
          id: workoutId,
          started_at: "2026-07-26T07:20:00.000Z",
          timezone: "Australia/Brisbane",
          local_date: "2026-07-26",
          ended_at: "2026-07-26T08:30:00.000Z",
          comment: "Authoritative phone Workout",
          updated_at: updatedAt.toISOString(),
          deleted_at: null
        }
      });
      await database.db.insert(schema.workoutSessions).values({
        ...opaqueEnvelope,
        id: emptyWorkoutId,
        payload: {
          id: emptyWorkoutId,
          started_at: "2026-07-27T07:20:00.000Z",
          timezone: "Australia/Brisbane",
          local_date: "2026-07-27",
          ended_at: null,
          comment: "Empty but authoritative",
          updated_at: updatedAt.toISOString(),
          deleted_at: null
        }
      });
      await database.db.insert(schema.workoutExercises).values({
        ...opaqueEnvelope,
        id: workoutExerciseId,
        payload: {
          id: workoutExerciseId,
          workout_id: workoutId,
          exercise_id: exerciseId,
          position: 0,
          updated_at: updatedAt.toISOString(),
          deleted_at: null
        }
      });
      await database.db.insert(schema.exerciseGroups).values({
        ...opaqueEnvelope,
        id: groupId,
        payload: {
          id: groupId,
          workout_id: workoutId,
          name: "Turkish get-up",
          color_hex: "#123456",
          position: 0,
          updated_at: updatedAt.toISOString(),
          deleted_at: null
        }
      });
      await database.db.insert(schema.exerciseGroupMembers).values({
        ...opaqueEnvelope,
        id: memberId,
        payload: {
          id: memberId,
          group_id: groupId,
          workout_exercise_id: workoutExerciseId,
          position: 0,
          updated_at: updatedAt.toISOString(),
          deleted_at: null
        }
      });
      await database.db.insert(schema.loggedSets).values({
        ...opaqueEnvelope,
        id: setId,
        payload: {
          id: setId,
          workout_id: workoutId,
          exercise_id: exerciseId,
          position: 0,
          planned_rest_after: 90,
          performed_at: "2026-07-26T07:33:14.000Z",
          is_completed: true,
          load_entered: "8",
          load_unit: "kilogram",
          reps_entered: "3",
          reps_unit: "repetition",
          updated_at: updatedAt.toISOString(),
          deleted_at: null
        }
      });

      const response = await getAgent(app, `/agent/workouts/${workoutId}`);
      assert.equal(response.status, 200);
      const detail = await response.json();
      assert.equal(detail.workout.startedAt, "2026-07-26T07:20:00.000Z");
      assert.equal(detail.workout.comment, "Authoritative phone Workout");
      assert.equal(detail.workoutExercises[0].id, workoutExerciseId);
      assert.equal(detail.exerciseGroups[0].members[0].id, memberId);
      assert.equal(detail.exerciseCatalog[0].name, "Kettlebell Turkish Get Up");
      assert.deepEqual(detail.coverage, {
        workoutMetadata: "authoritative",
        structure: "authoritative",
        exerciseIdentity: "complete",
        unresolvedExerciseIds: [],
        truncated: false
      });

      const listResponse = await getAgent(
        app,
        "/agent/workouts?fields=id,startedAt,comment,setCount,exerciseNames"
      );
      assert.equal(listResponse.status, 200);
      const list = await listResponse.json();
      const listedWorkout = list.workouts.find((row) => row.id === workoutId);
      assert.equal(listedWorkout.startedAt, "2026-07-26T07:20:00.000Z");
      const listedEmptyWorkout = list.workouts.find(
        (row) => row.id === emptyWorkoutId
      );
      assert.ok(listedEmptyWorkout);
      assert.equal(listedEmptyWorkout.setCount, 0);
      assert.deepEqual(listedEmptyWorkout.exerciseNames, []);

      const emptyDetailResponse = await getAgent(
        app,
        `/agent/workouts/${emptyWorkoutId}`
      );
      assert.equal(emptyDetailResponse.status, 200);
      const emptyDetail = await emptyDetailResponse.json();
      assert.deepEqual(emptyDetail.sets, []);
      assert.deepEqual(emptyDetail.workoutExercises, []);
      assert.deepEqual(emptyDetail.exerciseCatalog, []);
      assert.equal(emptyDetail.coverage.exerciseIdentity, "complete");
    } finally {
      await database.close();
    }
  }
);

test(
  "an archived synchronized Workout is not resurrected by live historical Sets",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-archived-workout-read-user-${randomUUID()}`;
    const workoutId = randomUUID();
    const archivedAt = "2026-07-27T08:30:00.000Z";
    const app = createAgentWorkoutReadApp({
      agentReadStore: createDrizzleAgentReadStore(database.db),
      userId
    });

    try {
      await seedUser(database, userId);
      await seedLoggedSet(database, {
        userId,
        id: randomUUID(),
        workoutId,
        startedAt: "2026-07-27T07:20:00.000Z",
        endedAt: "2026-07-27T08:15:00.000Z",
        comment: "Historical session",
        exerciseId: "01910000-0000-7000-8000-802196414109",
        exerciseName: "Kettlebell Turkish Get Up",
        position: 0,
        values: {
          load: { entered: "8", unit: "kilogram" },
          reps: { entered: "3", unit: "repetition" }
        }
      });
      await database.db.insert(schema.workoutSessions).values({
        id: workoutId,
        userId,
        deviceId: "phone-archive-workout",
        payload: {
          id: workoutId,
          started_at: "2026-07-27T07:20:00.000Z",
          updated_at: archivedAt,
          deleted_at: archivedAt
        },
        updatedAt: new Date(archivedAt),
        receivedAt: new Date(archivedAt),
        deletedAt: new Date(archivedAt)
      });

      const response = await getAgent(
        app,
        "/agent/workouts?fields=id,startedAt,setCount,exerciseNames"
      );
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(
        body.workouts.some((workout) => workout.id === workoutId),
        false
      );
    } finally {
      await database.close();
    }
  }
);

test(
  "session-only structure recovers Exercise identity from Sets without claiming authority",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-session-only-workout-user-${randomUUID()}`;
    const workoutId = randomUUID();
    const setId = randomUUID();
    const exerciseId = "01910000-0000-7000-8000-802196414109";
    const updatedAt = new Date("2026-07-28T08:30:00.000Z");
    const app = createAgentWorkoutReadApp({
      agentReadStore: createDrizzleAgentReadStore(database.db),
      userId
    });

    try {
      await seedUser(database, userId);
      await database.db.insert(schema.workoutSessions).values({
        id: workoutId,
        userId,
        deviceId: "phone-session-only",
        payload: {
          id: workoutId,
          started_at: "2026-07-28T07:20:00.000Z",
          timezone: "Australia/Brisbane",
          local_date: "2026-07-28",
          updated_at: updatedAt.toISOString(),
          deleted_at: null
        },
        updatedAt,
        receivedAt: updatedAt,
        deletedAt: null
      });
      await database.db.insert(schema.loggedSets).values({
        id: setId,
        userId,
        deviceId: "phone-session-only",
        payload: {
          id: setId,
          workout_id: workoutId,
          exercise_id: exerciseId,
          position: 0,
          load_entered: "8",
          load_unit: "kilogram",
          reps_entered: "3",
          reps_unit: "repetition",
          updated_at: updatedAt.toISOString(),
          deleted_at: null
        },
        updatedAt,
        receivedAt: updatedAt,
        deletedAt: null
      });

      const response = await getAgent(app, `/agent/workouts/${workoutId}`);
      assert.equal(response.status, 200);
      const detail = await response.json();
      assert.equal(detail.workoutExercises.length, 1);
      assert.equal(detail.workoutExercises[0].exerciseId, exerciseId);
      assert.equal(detail.exerciseCatalog[0].name, "Kettlebell Turkish Get Up");
      assert.equal(detail.coverage.structure, "unavailable");
      assert.equal(detail.coverage.exerciseIdentity, "complete");
    } finally {
      await database.close();
    }
  }
);

test("agent Workout detail returns authoritative structure, catalogue identity, and provenance", async () => {
  const workoutId = "019f9d51-08e3-7001-96d8-bb059f165ad1";
  const app = createAgentWorkoutReadApp({
    agentReadStore: {
      async getWorkout() {
        return {
          workout: {
            id: workoutId,
            startedAt: "2026-07-26T07:20:00.000Z",
            timezone: "Australia/Brisbane",
            localDate: "2026-07-26",
            endedAt: "2026-07-26T08:30:00.000Z",
            comment: "Kettlebell session",
            updatedAt: "2026-07-26T08:30:00.000Z",
            active: true
          },
          sets: [
            {
              id: "set-1",
              workoutId,
              performedAt: "2026-07-26T07:33:14.000Z",
              updatedAt: "2026-07-26T07:33:14.000Z",
              exerciseId: "legacy-side-bend",
              exerciseName: "Dumbbell Side Bends",
              category: { id: "core", name: "Core" },
              position: 0,
              plannedRestAfter: 90,
              isCompleted: true,
              values: {
                load: { entered: "28", unit: "kilogram" },
                reps: { entered: "12", unit: "repetition" }
              },
              rpe: null,
              side: null,
              comment: null
            }
          ],
          workoutExercises: [
            {
              id: "workout-exercise-1",
              exerciseId: "legacy-side-bend",
              position: 0,
              active: true
            }
          ],
          exerciseGroups: [
            {
              id: "group-1",
              name: "Core circuit",
              colorHex: "#123456",
              position: 0,
              active: true,
              members: [
                {
                  id: "member-1",
                  workoutExerciseId: "workout-exercise-1",
                  position: 0,
                  active: true
                }
              ]
            }
          ],
          exerciseCatalog: [
            {
              requestedId: "legacy-side-bend",
              canonicalId: "canonical-side-bend",
              resolution: "redirected",
              name: "Dumbbell Side Bends",
              library: "platform",
              category: { id: "core", name: "Core" },
              dimensions: ["load", "reps"],
              equipment: ["dumbbell"],
              loadMode: "added",
              recordProfile: "repMax",
              active: true
            }
          ],
          templateLink: {
            id: "template-link-1",
            workoutTemplateId: "template-1",
            routineId: "routine-1",
            slot: 2,
            active: true
          },
          coverage: {
            workoutMetadata: "authoritative",
            structure: "authoritative",
            exerciseIdentity: "complete",
            unresolvedExerciseIds: [],
            truncated: false
          }
        };
      },
      async listHistory() {
        throw new Error("listHistory should not be called.");
      },
      async listWorkouts() {
        throw new Error("listWorkouts should not be called.");
      },
      async readExerciseSets() {
        throw new Error("readExerciseSets should not be called.");
      },
      async readMonitoringActivity() {
        throw new Error("readMonitoringActivity should not be called.");
      }
    }
  });

  const response = await getAgent(app, `/agent/workouts/${workoutId}`);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.workout.startedAt, "2026-07-26T07:20:00.000Z");
  assert.equal(body.sets[0].exerciseName, "Dumbbell Side Bends");
  assert.equal(body.sets[0].isCompleted, true);
  assert.equal(body.exerciseCatalog[0].resolution, "redirected");
  assert.equal(body.workoutExercises[0].position, 0);
  assert.equal(
    body.exerciseGroups[0].members[0].workoutExerciseId,
    "workout-exercise-1"
  );
  assert.equal(body.templateLink.workoutTemplateId, "template-1");
  assert.deepEqual(body.coverage, {
    workoutMetadata: "authoritative",
    structure: "authoritative",
    exerciseIdentity: "complete",
    unresolvedExerciseIds: [],
    truncated: false
  });
});

function createAgentWorkoutReadApp({
  agentRateLimit,
  agentReadStore,
  logger = { info() {}, error() {} },
  rateLimitBackend,
  userId = "user-1"
}) {
  return createApp({
    logger,
    agentApiKeyStore: createAgentKeyStore(userId, agentRateLimit),
    agentReadStore,
    rateLimitBackend
  });
}

function createAgentKeyStore(userId, agentRateLimit = {}) {
  return {
    async authenticateAgentApiKey(secret) {
      if (secret !== "prn_agent_secret") {
        return null;
      }

      return {
        userId,
        keyId: "agent-workouts-read-key-1",
        keyName: "Garage coach",
        ...agentRateLimit
      };
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
    name: "Agent Workouts Read User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
}

async function seedLoggedSet(
  { db },
  {
    userId,
    id,
    workoutId,
    startedAt,
    endedAt,
    comment,
    exerciseId,
    exerciseName,
    position,
    values,
    deletedAt = null
  }
) {
  await db.insert(schema.loggedSets).values({
    id,
    userId,
    deviceId: "device-agent-workouts-read-test",
    updatedAt: new Date(startedAt),
    receivedAt: new Date(startedAt),
    deletedAt: deletedAt === null ? null : new Date(deletedAt),
    payload: {
      id,
      workout_id: workoutId,
      workout_started_at: startedAt,
      workout_ended_at: endedAt,
      workout_timezone: "Australia/Brisbane",
      workout_comment: comment,
      exercise_id: exerciseId,
      exercise_name: exerciseName,
      exercise_category_id: "cat-strength",
      exercise_category_name: "Strength",
      position,
      values,
      comment: null,
      rpe: null,
      side: null,
      deleted_at: deletedAt,
      updated_at: startedAt,
      ...flatDimensionValues(values)
    }
  });
}

function flatDimensionValues(values) {
  return Object.fromEntries(
    Object.entries(values).flatMap(([dimension, value]) => [
      [`${dimension}_entered`, value.entered],
      [`${dimension}_unit`, value.unit]
    ])
  );
}
