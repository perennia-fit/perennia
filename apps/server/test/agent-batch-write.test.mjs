import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  applyMigrations,
  createApp,
  createDatabaseClient,
  createDrizzleAgentWorkoutBatchWriteStore,
  createDrizzleRateLimitBackend,
  createInMemoryAgentCatalogStore,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

test("agent workout batch write resolves exercises, returns warnings, and calls the write store once", async () => {
  const writes = [];
  const app = createAgentBatchApp({
    agentWorkoutBatchWriteStore: {
      async writeWorkoutBatch(input) {
        writes.push(input);
        return {
          duplicate: false,
          serverClock: "2026-06-24T05:00:01.000Z",
          applied: input.sets.map((set) => ({
            id: set.id,
            updatedAt: set.updatedAt,
            deviceId: input.deviceId
          }))
        };
      }
    }
  });
  const request = batchRequest({
    idempotencyKey: "agent-batch-route-test",
    sets: [
      {
        id: "018f6a90-6d7f-7d63-bfc1-6f1025e0c001",
        exerciseName: "Back Squat",
        position: 0,
        values: {
          load: { entered: "400", unit: "kilogram" },
          reps: { entered: "5", unit: "repetition" }
        },
        plannedRestAfter: 180,
        performedAt: "2026-06-24T05:15:00.000Z",
        isCompleted: false
      }
    ]
  });

  const response = await postAgentBatch(app, request, {
    "x-correlation-id": "corr-agent-batch"
  });

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.accepted, true);
  assert.equal(body.duplicate, false);
  assert.equal(body.batchId, "agent-batch-route-test");
  assert.equal(body.sets.length, 1);
  assert.equal(body.sets[0].exerciseId, "user-back-squat");
  assert.deepEqual(
    body.sets[0].warnings.map((warning) => warning.rule),
    ["added_load_improbable"]
  );

  assert.equal(writes.length, 1);
  assert.equal(writes[0].userId, "user-1");
  assert.equal(writes[0].batchId, "agent-batch-route-test");
  assert.equal(writes[0].deviceId, "agent:agent-key-1");
  assert.equal(writes[0].correlationId, "corr-agent-batch");
  assert.equal(writes[0].sets[0].payload.exercise_id, "user-back-squat");
  assert.equal(writes[0].sets[0].payload.exercise_name, "Back Squat");
  assert.equal(writes[0].sets[0].payload.load_entered, "400");
  assert.equal(writes[0].sets[0].payload.reps_entered, "5");
  assert.equal(writes[0].sets[0].payload.planned_rest_after, 180);
  assert.equal(
    writes[0].sets[0].payload.performed_at,
    "2026-06-24T05:15:00.000Z"
  );
  assert.equal(writes[0].sets[0].payload.is_completed, false);
});

test("agent workout batch write accepts a nullable deletedAt per set and passes it through to the store as an LWW tombstone", async () => {
  const writes = [];
  const app = createAgentBatchApp({
    agentWorkoutBatchWriteStore: {
      async writeWorkoutBatch(input) {
        writes.push(input);
        return {
          duplicate: false,
          serverClock: "2026-06-24T05:00:01.000Z",
          applied: input.sets.map((set) => ({
            id: set.id,
            updatedAt: set.updatedAt,
            deviceId: input.deviceId
          }))
        };
      }
    }
  });
  const request = batchRequest({
    idempotencyKey: "agent-batch-archive-route-test",
    sets: [
      {
        id: "018f6a90-6d7f-7d63-bfc1-6f1025e0c005",
        exerciseName: "Back Squat",
        position: 0,
        values: {
          load: { entered: "100", unit: "kilogram" },
          reps: { entered: "5", unit: "repetition" }
        },
        updatedAt: "2026-06-24T06:00:00.000Z",
        deletedAt: "2026-06-24T06:00:00.000Z"
      }
    ]
  });

  const response = await postAgentBatch(app, request);

  assert.equal(response.status, 200);
  assert.equal(writes.length, 1);
  assert.equal(writes[0].sets[0].deletedAt, "2026-06-24T06:00:00.000Z");
  assert.equal(writes[0].sets[0].payload.deleted_at, "2026-06-24T06:00:00.000Z");
});

test("agent workout batch write enqueues a best-effort sync nudge after a committed write", async () => {
  const nudges = [];
  const app = createAgentBatchApp({
    agentWorkoutBatchWriteStore: {
      async writeWorkoutBatch(input) {
        return {
          duplicate: false,
          serverClock: "2026-06-24T05:00:01.000Z",
          applied: input.sets.map((set) => ({
            id: set.id,
            updatedAt: set.updatedAt,
            deviceId: input.deviceId
          }))
        };
      }
    },
    syncNudgePublisher: {
      async enqueueSyncNudge(input) {
        nudges.push(input);
        return { enqueued: true, jobId: "agent-nudge-job-1" };
      }
    }
  });

  const response = await postAgentBatch(
    app,
    batchRequest({
      idempotencyKey: "agent-batch-nudge-route-test",
      sets: [
        {
          id: "018f6a90-6d7f-7d63-bfc1-6f1025e0c010",
          exerciseName: "Back Squat",
          position: 0,
          values: {
            load: { entered: "100", unit: "kilogram" },
            reps: { entered: "5", unit: "repetition" }
          }
        }
      ]
    })
  );

  assert.equal(response.status, 200);
  assert.deepEqual(nudges, [
    {
      userId: "user-1",
      sourceDeviceId: "agent:agent-key-1",
      reason: "agent_write"
    }
  ]);
});

test("agent workout batch write hard-rejects one invalid item before storage", async () => {
  let writeCalled = false;
  const nudges = [];
  const app = createAgentBatchApp({
    agentWorkoutBatchWriteStore: {
      async writeWorkoutBatch() {
        writeCalled = true;
        throw new Error("writeWorkoutBatch should not be called.");
      }
    },
    syncNudgePublisher: {
      async enqueueSyncNudge(input) {
        nudges.push(input);
        return { enqueued: true, jobId: "unexpected-nudge" };
      }
    }
  });
  const request = batchRequest({
    idempotencyKey: "agent-batch-invalid-route-test",
    sets: [
      {
        id: "018f6a90-6d7f-7d63-bfc1-6f1025e0c002",
        exerciseName: "Back Squat",
        position: 0,
        values: {
          reps: { entered: "10001", unit: "repetition" }
        }
      }
    ]
  });

  const response = await postAgentBatch(app, request);

  assert.equal(response.status, 422);
  const body = await response.json();
  assert.equal(body.code, "agent_batch_write_failed");
  assert.equal(body.errors.length, 1);
  assert.equal(body.errors[0].itemIndex, 0);
  assert.equal(body.errors[0].rule, "reps_max");
  assert.equal(writeCalled, false);
  assert.deepEqual(nudges, []);
});

test(
  "agent workout batch write persists rows, records one Activity Log batch, replays idempotently, and rolls back invalid batches",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-batch-user-${randomUUID()}`;
    const app = createAgentBatchApp({
      agentWorkoutBatchWriteStore: createDrizzleAgentWorkoutBatchWriteStore(
        database.db
      ),
      userId
    });
    const request = batchRequest({
      idempotencyKey: `agent-batch-${randomUUID()}`,
      sets: [
        {
          id: "018f6a90-6d7f-7d63-bfc1-6f1025e0c101",
          exerciseName: "Back Squat",
          position: 0,
          values: {
            load: { entered: "400", unit: "kilogram" },
            reps: { entered: "5", unit: "repetition" }
          }
        },
        {
          id: "018f6a90-6d7f-7d63-bfc1-6f1025e0c102",
          exerciseName: "Bench Press",
          position: 1,
          values: {
            load: { entered: "100", unit: "kilogram" },
            reps: { entered: "8", unit: "repetition" }
          }
        }
      ]
    });

    try {
      await database.db.insert(schema.user).values({
        id: userId,
        name: "Agent Batch User",
        email: `${userId}@example.com`,
        emailVerified: true
      });

      const response = await postAgentBatch(app, request);

      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.accepted, true);
      assert.equal(body.duplicate, false);
      assert.equal(body.sets.length, 2);
      assert.deepEqual(
        body.sets[0].warnings.map((warning) => warning.rule),
        ["added_load_improbable"]
      );

      const rows = await database.sql`
        select id, user_id, device_id, payload, updated_at, deleted_at
        from logged_sets
        where id in (${request.sets[0].id}, ${request.sets[1].id})
        order by id
      `;
      assert.equal(rows.length, 2);
      assert.equal(rows[0].user_id, userId);
      assert.equal(rows[0].device_id, "agent:agent-key-1");
      assert.equal(rows[0].payload.workout_id, request.workout.id);
      assert.equal(rows[0].payload.exercise_id, "user-back-squat");
      assert.equal(rows[0].payload.load_entered, "400");
      assert.equal(rows[0].deleted_at, null);

      const workoutRows = await database.sql`
        select payload
        from workout_sessions
        where id = ${request.workout.id}
          and user_id = ${userId}
      `;
      assert.equal(workoutRows.length, 1);
      assert.equal(workoutRows[0].payload.started_at, request.workout.startedAt);
      assert.equal(workoutRows[0].payload.timezone, request.workout.timezone);
      assert.equal(workoutRows[0].payload.local_date, "2026-06-24");

      const workoutExerciseRows = await database.sql`
        select payload
        from workout_exercises
        where user_id = ${userId}
          and payload ->> 'workout_id' = ${request.workout.id}
        order by (payload ->> 'position')::int
      `;
      assert.equal(workoutExerciseRows.length, 2);
      assert.deepEqual(
        workoutExerciseRows.map((row) => row.payload.exercise_id),
        ["user-back-squat", "platform-bench-press"]
      );

      const activityRows = await database.sql`
        select actor, batch_id, entity_table, entity_id, before_image, after_image
        from activity_log
        where batch_id = ${request.idempotencyKey}
        order by entity_id
      `;
      assert.equal(activityRows.length, 5);
      assert.equal(new Set(activityRows.map((row) => row.batch_id)).size, 1);
      assert.deepEqual(
        Object.fromEntries(
          ["workout_sessions", "workout_exercises", "logged_sets"].map(
            (entityTable) => [
              entityTable,
              activityRows.filter((row) => row.entity_table === entityTable)
                .length
            ]
          )
        ),
        {
          workout_sessions: 1,
          workout_exercises: 2,
          logged_sets: 2
        }
      );
      const setActivityRows = activityRows.filter(
        (row) => row.entity_table === "logged_sets"
      );
      assert.equal(setActivityRows[0].actor, "agent");
      assert.equal(setActivityRows[0].before_image, null);
      assert.equal(
        setActivityRows[0].after_image.exercise_id,
        "user-back-squat"
      );

      const replayResponse = await postAgentBatch(app, request);
      assert.equal(replayResponse.status, 200);
      const replayBody = await replayResponse.json();
      assert.equal(replayBody.accepted, true);
      assert.equal(replayBody.duplicate, true);
      assert.deepEqual(
        replayBody.sets.map((set) => set.id),
        body.sets.map((set) => set.id)
      );

      const replayActivityRows = await database.sql`
        select id
        from activity_log
        where batch_id = ${request.idempotencyKey}
      `;
      assert.equal(replayActivityRows.length, 5);

      const invalidRequest = batchRequest({
        idempotencyKey: `agent-batch-invalid-${randomUUID()}`,
        sets: [
          {
            id: "018f6a90-6d7f-7d63-bfc1-6f1025e0c103",
            exerciseName: "Back Squat",
            position: 0,
            values: {
              reps: { entered: "10001", unit: "repetition" }
            }
          }
        ]
      });
      const invalidResponse = await postAgentBatch(app, invalidRequest);
      assert.equal(invalidResponse.status, 422);

      const invalidRows = await database.sql`
        select id
        from logged_sets
        where id = ${invalidRequest.sets[0].id}
      `;
      assert.equal(invalidRows.length, 0);
      const invalidActivityRows = await database.sql`
        select id
        from activity_log
        where batch_id = ${invalidRequest.idempotencyKey}
      `;
      assert.equal(invalidActivityRows.length, 0);
    } finally {
      await database.close();
    }
  }
);

test(
  "agent workout batch write archives a Workout and Set as explicit LWW tombstones, and still records a superseded Set loser",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-batch-archive-user-${randomUUID()}`;
    const app = createAgentBatchApp({
      agentWorkoutBatchWriteStore: createDrizzleAgentWorkoutBatchWriteStore(
        database.db
      ),
      userId
    });
    const setId = "018f6a90-6d7f-7d63-bfc1-6f1025e0c501";
    const workoutId = randomUUID();
    const exerciseGroupId = randomUUID();
    const exerciseGroupMemberId = randomUUID();
    const createRequest = batchRequest({
      idempotencyKey: `agent-batch-archive-create-${randomUUID()}`,
      workout: { id: workoutId },
      sets: [
        {
          id: setId,
          exerciseName: "Back Squat",
          position: 0,
          values: {
            load: { entered: "100", unit: "kilogram" },
            reps: { entered: "5", unit: "repetition" }
          },
          updatedAt: "2026-06-24T05:00:00.000Z"
        }
      ]
    });

    try {
      await database.db.insert(schema.user).values({
        id: userId,
        name: "Agent Batch Archive User",
        email: `${userId}@example.com`,
        emailVerified: true
      });

      const createResponse = await postAgentBatch(app, createRequest);
      assert.equal(createResponse.status, 200);
      const workoutExerciseRows = await database.sql`
        select id
        from workout_exercises
        where user_id = ${userId}
          and payload ->> 'workout_id' = ${workoutId}
      `;
      assert.equal(workoutExerciseRows.length, 1);
      const structureCreatedAt = new Date("2026-06-24T05:00:00.000Z");
      await database.db.insert(schema.exerciseGroups).values({
        id: exerciseGroupId,
        userId,
        deviceId: "phone-a",
        payload: {
          id: exerciseGroupId,
          workout_id: workoutId,
          name: "Main circuit",
          position: 0,
          updated_at: structureCreatedAt.toISOString(),
          deleted_at: null
        },
        updatedAt: structureCreatedAt
      });
      await database.db.insert(schema.exerciseGroupMembers).values({
        id: exerciseGroupMemberId,
        userId,
        deviceId: "phone-a",
        payload: {
          id: exerciseGroupMemberId,
          group_id: exerciseGroupId,
          workout_exercise_id: workoutExerciseRows[0].id,
          position: 0,
          updated_at: structureCreatedAt.toISOString(),
          deleted_at: null
        },
        updatedAt: structureCreatedAt
      });

      // Archive the set (deletedAt tombstone) in a second agent batch.
      const archiveRequest = batchRequest({
        idempotencyKey: `agent-batch-archive-delete-${randomUUID()}`,
        workout: {
          id: workoutId,
          deletedAt: "2026-06-24T06:00:00.000Z"
        },
        sets: [
          {
            id: setId,
            exerciseName: "Back Squat",
            position: 0,
            values: {
              load: { entered: "100", unit: "kilogram" },
              reps: { entered: "5", unit: "repetition" }
            },
            updatedAt: "2026-06-24T06:00:00.000Z",
            deletedAt: "2026-06-24T06:00:00.000Z"
          }
        ]
      });
      const archiveResponse = await postAgentBatch(app, archiveRequest);
      assert.equal(archiveResponse.status, 200);

      const archivedRows = await database.sql`
        select id, deleted_at, payload
        from logged_sets
        where id = ${setId}
      `;
      assert.equal(archivedRows.length, 1);
      assert.notEqual(archivedRows[0].deleted_at, null);
      assert.equal(archivedRows[0].payload.deleted_at, "2026-06-24T06:00:00.000Z");
      const archivedWorkoutRows = await database.sql`
        select deleted_at, payload
        from workout_sessions
        where id = ${archiveRequest.workout.id}
          and user_id = ${userId}
      `;
      assert.equal(archivedWorkoutRows.length, 1);
      assert.notEqual(archivedWorkoutRows[0].deleted_at, null);
      assert.equal(
        archivedWorkoutRows[0].payload.deleted_at,
        "2026-06-24T06:00:00.000Z"
      );
      const archivedStructureRows = await database.sql`
        select 'workout_exercises' as entity, deleted_at
        from workout_exercises
        where user_id = ${userId}
          and payload ->> 'workout_id' = ${workoutId}
        union all
        select 'exercise_groups' as entity, deleted_at
        from exercise_groups
        where user_id = ${userId}
          and payload ->> 'workout_id' = ${workoutId}
        union all
        select 'exercise_group_members' as entity, deleted_at
        from exercise_group_members
        where user_id = ${userId}
          and id = ${exerciseGroupMemberId}
      `;
      assert.deepEqual(
        archivedStructureRows.map((row) => row.entity).sort(),
        [
          "exercise_group_members",
          "exercise_groups",
          "workout_exercises"
        ]
      );
      assert.ok(
        archivedStructureRows.every((row) => row.deleted_at !== null)
      );

      const archiveActivityRows = await database.sql`
        select before_image, after_image
        from activity_log
        where batch_id = ${archiveRequest.idempotencyKey}
          and entity_table = 'logged_sets'
      `;
      assert.equal(archiveActivityRows.length, 1);
      assert.equal(archiveActivityRows[0].before_image.deleted_at, null);
      assert.equal(
        archiveActivityRows[0].after_image.deleted_at,
        "2026-06-24T06:00:00.000Z"
      );

      // A later attempted "un-archive" without a fresher clock is a
      // superseded loser: it is recorded in the Activity Log but does not
      // resurrect the row (still archived).
      const staleUndeleteRequest = batchRequest({
        idempotencyKey: `agent-batch-archive-stale-undelete-${randomUUID()}`,
        workout: { id: workoutId },
        sets: [
          {
            id: setId,
            exerciseName: "Back Squat",
            position: 0,
            values: {
              load: { entered: "100", unit: "kilogram" },
              reps: { entered: "5", unit: "repetition" }
            },
            updatedAt: "2026-06-24T05:30:00.000Z",
            deletedAt: null
          }
        ]
      });
      const staleResponse = await postAgentBatch(app, staleUndeleteRequest);
      assert.equal(staleResponse.status, 200);

      const stillArchivedRows = await database.sql`
        select deleted_at
        from logged_sets
        where id = ${setId}
      `;
      assert.notEqual(stillArchivedRows[0].deleted_at, null);

      const staleActivityRows = await database.sql`
        select before_image, after_image
        from activity_log
        where batch_id = ${staleUndeleteRequest.idempotencyKey}
          and entity_table = 'logged_sets'
      `;
      assert.equal(staleActivityRows.length, 1, "superseded loser is still recorded");
      assert.equal(staleActivityRows[0].after_image.deleted_at, null);
    } finally {
      await database.close();
    }
  }
);

test(
  "agent workout batch write enforces a per-key Postgres rate limit before side effects",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-batch-rate-limit-user-${randomUUID()}`;
    const nudges = [];
    const app = createAgentBatchApp({
      agentRateLimit: {
        rateLimitEnabled: true,
        rateLimitTimeWindow: 60 * 1000,
        rateLimitMax: 1
      },
      agentWorkoutBatchWriteStore: createDrizzleAgentWorkoutBatchWriteStore(
        database.db
      ),
      rateLimitBackend: createDrizzleRateLimitBackend(database.db),
      syncNudgePublisher: {
        async enqueueSyncNudge(input) {
          nudges.push(input);
          return { enqueued: true, jobId: `nudge-${nudges.length}` };
        }
      },
      userId
    });
    const firstRequest = batchRequest({
      idempotencyKey: `agent-batch-rate-limit-first-${randomUUID()}`,
      sets: [
        {
          id: "018f6a90-6d7f-7d63-bfc1-6f1025e0c401",
          exerciseName: "Back Squat",
          position: 0,
          values: {
            load: { entered: "100", unit: "kilogram" },
            reps: { entered: "5", unit: "repetition" }
          }
        }
      ]
    });
    const overLimitRequest = batchRequest({
      idempotencyKey: `agent-batch-rate-limit-second-${randomUUID()}`,
      sets: [
        {
          id: "018f6a90-6d7f-7d63-bfc1-6f1025e0c402",
          exerciseName: "Bench Press",
          position: 0,
          values: {
            load: { entered: "80", unit: "kilogram" },
            reps: { entered: "8", unit: "repetition" }
          }
        }
      ]
    });

    try {
      await database.db.insert(schema.user).values({
        id: userId,
        name: "Agent Batch Rate Limit User",
        email: `${userId}@example.com`,
        emailVerified: true
      });

      const firstResponse = await postAgentBatch(app, firstRequest);
      assert.equal(firstResponse.status, 200);
      assert.equal(firstResponse.headers.get("x-rate-limit-limit"), "1");
      assert.equal(firstResponse.headers.get("x-rate-limit-remaining"), "0");
      assert.ok(firstResponse.headers.get("x-rate-limit-reset"));

      const overLimitResponse = await postAgentBatch(app, overLimitRequest);
      assert.equal(overLimitResponse.status, 429);
      assert.equal(overLimitResponse.headers.get("x-rate-limit-limit"), "1");
      assert.equal(overLimitResponse.headers.get("x-rate-limit-remaining"), "0");
      assert.ok(overLimitResponse.headers.get("x-rate-limit-reset"));
      assert.equal(overLimitResponse.headers.get("retry-after"), "60");
      assert.deepEqual(await overLimitResponse.json(), {
        code: "rate_limited",
        message: "Too many requests.",
        limit: 1,
        retryAfterSeconds: 60
      });

      const firstRows = await database.sql`
        select id
        from logged_sets
        where id = ${firstRequest.sets[0].id}
      `;
      assert.equal(firstRows.length, 1);
      const overLimitRows = await database.sql`
        select id
        from logged_sets
        where id = ${overLimitRequest.sets[0].id}
      `;
      assert.equal(overLimitRows.length, 0);

      const overLimitActivityRows = await database.sql`
        select id
        from activity_log
        where batch_id = ${overLimitRequest.idempotencyKey}
      `;
      assert.equal(overLimitActivityRows.length, 0);
      assert.deepEqual(nudges, [
        {
          userId,
          sourceDeviceId: "agent:agent-key-1",
          reason: "agent_write"
        }
      ]);

      const rateLimitRows = await database.sql`
        select coalesce(sum(count), 0)::int as total_hits
        from rate_limit_windows
        where key = 'agent-api-key:agent-key-1'
      `;
      assert.equal(rateLimitRows[0].total_hits, 2);
    } finally {
      await database.close();
    }
  }
);

test(
  "agent workout batch write keeps committed rows when sync nudge enqueue fails",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-batch-nudge-user-${randomUUID()}`;
    const logEvents = [];
    const app = createAgentBatchApp({
      agentWorkoutBatchWriteStore: createDrizzleAgentWorkoutBatchWriteStore(
        database.db
      ),
      logger: {
        info() {},
        error(payload, message) {
          logEvents.push({ payload, message });
        }
      },
      syncNudgePublisher: {
        async enqueueSyncNudge() {
          throw new Error("queue unavailable");
        }
      },
      userId
    });
    const request = batchRequest({
      idempotencyKey: `agent-batch-nudge-failure-${randomUUID()}`,
      sets: [
        {
          id: "018f6a90-6d7f-7d63-bfc1-6f1025e0c301",
          exerciseName: "Back Squat",
          position: 0,
          values: {
            load: { entered: "100", unit: "kilogram" },
            reps: { entered: "5", unit: "repetition" }
          }
        }
      ]
    });

    try {
      await database.db.insert(schema.user).values({
        id: userId,
        name: "Agent Batch Nudge User",
        email: `${userId}@example.com`,
        emailVerified: true
      });

      const response = await postAgentBatch(app, request);
      assert.equal(response.status, 200);

      const rows = await database.sql`
        select id
        from logged_sets
        where id = ${request.sets[0].id}
      `;
      assert.equal(rows.length, 1);
      const activityRows = await database.sql`
        select id
        from activity_log
        where batch_id = ${request.idempotencyKey}
          and entity_table = 'logged_sets'
      `;
      assert.equal(activityRows.length, 1);
      assert.equal(logEvents.length, 1);
      assert.equal(logEvents[0].message, "agent sync nudge enqueue failed");
    } finally {
      await database.close();
    }
  }
);

function createAgentBatchApp({
  agentRateLimit,
  agentWorkoutBatchWriteStore,
  logger = { info() {}, error() {} },
  rateLimitBackend,
  syncNudgePublisher,
  userId = "user-1"
}) {
  return createApp({
    logger,
    agentApiKeyStore: createAgentKeyStore(userId, agentRateLimit),
    agentCatalogStore: createInMemoryAgentCatalogStore(catalogFixtures(userId)),
    agentWorkoutBatchWriteStore,
    rateLimitBackend,
    syncNudgePublisher
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
        keyId: "agent-key-1",
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

function postAgentBatch(app, body, headers = {}) {
  return app.request("/agent/workouts/batch-write", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_agent_secret",
      "content-type": "application/json",
      ...headers
    },
    body: JSON.stringify(body)
  });
}

function batchRequest({ idempotencyKey, sets, workout = {} }) {
  return {
    idempotencyKey,
    workout: {
      id: "018f6a90-6d7f-7d63-bfc1-6f1025e0c200",
      startedAt: "2026-06-24T05:00:00.000Z",
      endedAt: null,
      timezone: "Australia/Brisbane",
      comment: null,
      ...workout
    },
    sets: sets.map((set) => ({
      updatedAt: "2026-06-24T05:00:00.000Z",
      comment: null,
      rpe: undefined,
      side: undefined,
      ...set
    }))
  };
}

function catalogFixtures(userId = "user-1") {
  return [
    exercise({
      id: "platform-back-squat",
      library: "platform",
      name: "Back Squat",
      categoryId: "cat-strength"
    }),
    exercise({
      id: "user-back-squat",
      library: "user",
      ownerUserId: userId,
      name: "Back Squat",
      categoryId: "cat-strength",
      shadowedPlatformExerciseId: "platform-back-squat"
    }),
    exercise({
      id: "platform-bench-press",
      library: "platform",
      name: "Bench Press",
      categoryId: "cat-strength"
    })
  ];
}

function exercise({
  id,
  library,
  ownerUserId = null,
  name,
  categoryId,
  active = true,
  favorite = false,
  equipment = ["barbell"],
  shadowedPlatformExerciseId = null
}) {
  return {
    id,
    library,
    ownerUserId,
    name,
    category: {
      id: categoryId,
      name: categoryId === "cat-strength" ? "Strength" : "Other"
    },
    dimensions: ["load", "reps"],
    equipment,
    loadMode: "added",
    recordProfile: "repMax",
    favorite,
    active,
    shadowedPlatformExerciseId
  };
}
