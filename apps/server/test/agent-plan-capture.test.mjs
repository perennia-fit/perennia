import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  AGENT_PLAN_CAPTURE_BATCH_ENTITY,
  AGENT_PLAN_UPDATE_BATCH_ENTITY,
  AgentPlanCaptureConflictError,
  applyMigrations,
  createAgentMcpServer,
  createApp,
  createDatabaseClient,
  createDrizzleAgentCatalogStore,
  createDrizzleAgentPlanCaptureStore,
  createInMemoryAgentCatalogStore,
  schema,
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl && process.env.CI === "true") {
  throw new Error(
    "DATABASE_URL must be set for server Postgres integration tests.",
  );
}
const skip = databaseUrl ? false : "DATABASE_URL is not set.";

test("capture REST writes fixed repeat-collapsed content plus collection placement once", async () => {
  const writes = [];
  const nudges = [];
  const store = inMemoryCaptureStore({
    workout: workoutSnapshot(),
    routine: routineState(),
    writes,
  });
  const app = createCaptureApp({
    store,
    syncNudgePublisher: nudgeRecorder(nudges),
  });
  const request = {
    idempotencyKey: "capture-key",
    workoutId: "workout-1",
    routineId: "routine-1",
    slot: null,
  };

  const first = await postCapture(app, request);
  assert.equal(first.status, 200);
  const firstBody = await first.json();
  assert.equal(firstBody.accepted, true);
  assert.equal(firstBody.duplicate, false);
  assert.equal(firstBody.exerciseCount, 2);
  assert.equal(firstBody.prescriptionCount, 2);
  assert.equal(firstBody.groupCount, 1);
  assert.ok(firstBody.routineEntryId);

  assert.equal(writes.length, 1);
  const mutation = writes[0];
  assert.equal(mutation.kind, "capture");
  assert.equal(mutation.rows.workoutTemplates.length, 1);
  assert.equal(
    mutation.rows.workoutTemplates[0].payload.name,
    "Bench Press + Cable Row",
  );
  assert.equal(mutation.rows.templateExercises.length, 2);
  assert.equal(mutation.rows.prescriptions.length, 2);
  assert.equal(mutation.rows.templateGroups.length, 1);
  assert.equal(mutation.rows.templateGroupMembers.length, 2);
  assert.equal(mutation.rows.routineEntries.length, 1);
  assert.equal(mutation.rows.routineEntries[0].payload.position, 1);
  assert.equal(mutation.rows.routineEntries[0].payload.slot, null);

  const benchPrescription = mutation.rows.prescriptions.find(
    (row) => row.payload.reps_entered === "5",
  );
  assert.equal(benchPrescription.payload.mode, "fixed");
  assert.equal(benchPrescription.payload.repeat, 2);
  assert.equal(benchPrescription.payload.rest_after, 90);
  assert.equal("comment" in benchPrescription.payload, false);
  assert.equal("rpe" in benchPrescription.payload, false);
  assert.equal("side" in benchPrescription.payload, false);
  assert.deepEqual(nudges, [
    {
      userId: "user-1",
      sourceDeviceId: "agent:agent-key-1",
      reason: "agent_write",
    },
  ]);

  const replay = await postCapture(app, request);
  assert.equal(replay.status, 200);
  const replayBody = await replay.json();
  assert.equal(replayBody.duplicate, true);
  assert.equal(replayBody.workoutTemplateId, firstBody.workoutTemplateId);
  assert.equal(replayBody.routineEntryId, firstBody.routineEntryId);
  assert.equal(writes.length, 1);
  assert.equal(nudges.length, 1);
});

test("update-from-workout preserves identity, memberships, links, and copyPrevious mode", async () => {
  const writes = [];
  const nudges = [];
  const linked = linkedTemplateState();
  const store = inMemoryCaptureStore({
    workout: workoutSnapshot(),
    linked,
    writes,
  });
  const app = createCaptureApp({
    store,
    syncNudgePublisher: nudgeRecorder(nudges),
  });
  const request = {
    idempotencyKey: "update-key",
    workoutId: "workout-1",
  };

  const response = await postUpdate(app, request);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.accepted, true);
  assert.equal(body.duplicate, false);
  assert.equal(body.workoutTemplateId, "template-linked");
  assert.deepEqual(body.divergence, {
    addedExercises: [
      {
        exerciseId: "exercise-row",
        exerciseName: "Cable Row",
      },
    ],
    removedExercises: [],
    changedExercises: [],
    groupsChanged: true,
  });

  assert.equal(writes.length, 1);
  const mutation = writes[0];
  assert.equal(mutation.kind, "update");
  assert.deepEqual(mutation.rows.workoutTemplates, []);
  assert.deepEqual(mutation.rows.routineEntries, []);

  const oldExercise = mutation.rows.templateExercises.find(
    (row) => row.id === "template-exercise-bench",
  );
  const oldPrescription = mutation.rows.prescriptions.find(
    (row) => row.id === "prescription-copy",
  );
  assert.ok(oldExercise.deletedAt);
  assert.ok(oldPrescription.deletedAt);

  const newCopyPrevious = mutation.rows.prescriptions.find(
    (row) =>
      row.id !== "prescription-copy" &&
      row.payload.template_exercise_id !== undefined &&
      row.payload.mode === "copy-previous",
  );
  assert.ok(newCopyPrevious);
  assert.equal(newCopyPrevious.payload.repeat, 2);
  assert.equal(newCopyPrevious.payload.rest_after, 90);
  assert.equal(newCopyPrevious.payload.load_entered, null);
  assert.equal(newCopyPrevious.payload.reps_entered, null);

  // These are outside the mutation by construction: Update never rewrites
  // the Template row, Routine memberships, or the provenance Link.
  assert.equal(linked.workoutTemplate.payload.name, "Original identity");
  assert.equal(linked.workoutTemplate.payload.notes, "Keep these notes");
  assert.equal(linked.templateLink.payload.workout_template_id, "template-linked");
  assert.equal(nudges.length, 1);

  const replay = await postUpdate(app, request);
  assert.equal(replay.status, 200);
  assert.equal((await replay.json()).duplicate, true);
  assert.equal(writes.length, 1);
  assert.equal(nudges.length, 1);
});

test("update-from-workout reports empty divergence and writes no plan rows", async () => {
  const writes = [];
  const nudges = [];
  const store = inMemoryCaptureStore({
    workout: matchingWorkoutSnapshot(),
    linked: linkedTemplateState(),
    writes,
  });
  const app = createCaptureApp({
    store,
    syncNudgePublisher: nudgeRecorder(nudges),
  });
  const request = {
    idempotencyKey: "update-no-op",
    workoutId: "workout-1",
  };

  const response = await postUpdate(app, request);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.duplicate, false);
  assert.deepEqual(body.divergence, {
    addedExercises: [],
    removedExercises: [],
    changedExercises: [],
    groupsChanged: false,
  });
  assert.equal(writes.length, 1);
  assert.ok(
    Object.values(writes[0].rows).every((rows) => rows.length === 0),
  );
  assert.deepEqual(nudges, []);

  const replay = await postUpdate(app, request);
  assert.equal(replay.status, 200);
  assert.equal((await replay.json()).duplicate, true);
  assert.equal(writes.length, 1);
});

test("capture maps Workout integrity failures to structured 422 errors", async () => {
  const writes = [];
  const workout = workoutSnapshot();
  workout.exercises[1].sourceWorkoutExerciseId =
    workout.exercises[0].sourceWorkoutExerciseId;
  const app = createCaptureApp({
    store: inMemoryCaptureStore({ workout, writes }),
  });

  const response = await postCapture(app, {
    idempotencyKey: "invalid-workout-integrity",
    workoutId: "workout-1",
    routineId: null,
    slot: null,
  });

  assert.equal(response.status, 422);
  const body = await response.json();
  assert.equal(body.code, "agent_plan_capture_failed");
  assert.ok(
    body.errors.some(
      (issue) =>
        issue.rule === "capture_workout_exercise_id_duplicate",
    ),
  );
  assert.deepEqual(writes, []);
});

test("update-from-workout returns typed LWW conflicts with superseded row IDs", async () => {
  const writes = [];
  const app = createCaptureApp({
    store: inMemoryCaptureStore({
      workout: workoutSnapshot(),
      linked: linkedTemplateState(),
      writes,
      conflict: [
        {
          entityType: "prescription",
          id: "prescription-copy",
        },
      ],
    }),
  });

  const response = await postUpdate(app, {
    idempotencyKey: "update-conflict",
    workoutId: "workout-1",
  });

  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), {
    code: "agent_plan_update_from_workout_conflict",
    message:
      "A newer plan row won the LWW race. Nothing from this atomic operation was committed; reload the plan tree before retrying.",
    retryable: true,
    superseded: [
      {
        entityType: "prescription",
        id: "prescription-copy",
      },
    ],
  });
});

test("capture rejects an empty Workout before it can wipe reusable content", async () => {
  const writes = [];
  const app = createCaptureApp({
    store: inMemoryCaptureStore({
      workout: {
        workoutId: "workout-1",
        exercises: [],
        groups: [],
      },
      writes,
    }),
  });

  const response = await postCapture(app, {
    idempotencyKey: "empty-workout",
    workoutId: "workout-1",
    routineId: null,
    slot: null,
  });

  assert.equal(response.status, 422);
  const body = await response.json();
  assert.ok(
    body.errors.some(
      (issue) => issue.rule === "capture_workout_exercises_required",
    ),
  );
  assert.deepEqual(writes, []);
});

test("capture rejects Cadence placement through the shared validator without writing", async () => {
  const writes = [];
  const store = inMemoryCaptureStore({
    workout: workoutSnapshot(),
    routine: {
      routine: planRow("routine-1", {
        name: "Weekly",
        notes: null,
        cadence_kind: "weekly",
        cadence_window: null,
      }),
      entries: [],
    },
    writes,
  });
  const app = createCaptureApp({ store });

  const response = await postCapture(app, {
    idempotencyKey: "invalid-placement",
    workoutId: "workout-1",
    name: "Captured strength",
    routineId: "routine-1",
    slot: null,
  });

  assert.equal(response.status, 422);
  const body = await response.json();
  assert.equal(body.code, "agent_plan_capture_failed");
  assert.ok(
    body.errors.some(
      (issue) => issue.rule === "routine_entry_slot_required",
    ),
  );
  assert.deepEqual(writes, []);
});

test("MCP mirrors capture and update over the same bearer-authenticated handlers", async () => {
  const writes = [];
  const store = inMemoryCaptureStore({
    workout: workoutSnapshot(),
    routine: routineState(),
    linked: linkedTemplateState(),
    writes,
  });
  const agentApiKeyStore = createAgentKeyStore("user-1");
  const agentCatalogStore = captureCatalog("user-1");
  const logger = { info() {}, error() {} };
  const app = createApp({
    logger,
    agentApiKeyStore,
    createMcpServer: () =>
      createAgentMcpServer({
        agentApiKeyStore,
        agentCatalogStore,
        agentPlanCaptureStore: store,
        logger,
      }),
  });

  const capture = await postMcp(app, {
    jsonrpc: "2.0",
    id: 1,
    method: "tools/call",
    params: {
      name: "agent_capture_workout_template",
      arguments: {
        request: {
          idempotencyKey: "mcp-capture",
          workoutId: "workout-1",
          name: "MCP capture",
          routineId: null,
          slot: null,
        },
      },
    },
  });
  assert.equal(capture.status, 200);
  const captureBody = await capture.json();
  assert.equal(captureBody.result.structuredContent.accepted, true);

  const update = await postMcp(app, {
    jsonrpc: "2.0",
    id: 2,
    method: "tools/call",
    params: {
      name: "agent_update_workout_template_from_workout",
      arguments: {
        request: {
          idempotencyKey: "mcp-update",
          workoutId: "workout-1",
        },
      },
    },
  });
  assert.equal(update.status, 200);
  const updateBody = await update.json();
  assert.equal(updateBody.result.structuredContent.accepted, true);
  assert.equal(
    updateBody.result.structuredContent.workoutTemplateId,
    "template-linked",
  );
  assert.deepEqual(
    writes.map((write) => write.kind),
    ["capture", "update"],
  );
});

test(
  "Postgres capture/update are atomic agent batches, idempotent, and preserve linked identity",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-capture-${randomUUID()}`;
    const ids = integrationIds();
    const at = new Date("2026-07-24T01:00:00.000Z");
    const nudges = [];
    const errors = [];
    const app = createApp({
      logger: {
        info() {},
        error(input, message) {
          errors.push({
            message,
            input: JSON.parse(
              JSON.stringify(input, (_key, value) =>
                value instanceof Error
                  ? {
                      name: value.name,
                      message: value.message,
                      stack: value.stack,
                      cause: value.cause,
                    }
                  : value,
              ),
            ),
          });
        },
      },
      agentApiKeyStore: createAgentKeyStore(userId),
      agentCatalogStore: createDrizzleAgentCatalogStore(database.db),
      agentPlanCaptureStore: createDrizzleAgentPlanCaptureStore(database.db),
      syncNudgePublisher: nudgeRecorder(nudges),
    });

    try {
      await seedCaptureScenario(database, { userId, ids, at });

      const captureRequest = {
        idempotencyKey: `capture-${randomUUID()}`,
        workoutId: ids.workout,
        name: "Captured from fact",
        routineId: ids.routine,
        slot: null,
      };
      const captureResponses = await Promise.all([
        postCapture(app, captureRequest),
        postCapture(app, captureRequest),
      ]);
      assert.ok(captureResponses.every((response) => response.status === 200));
      const captureBodies = await Promise.all(
        captureResponses.map((response) => response.json()),
      );
      assert.deepEqual(
        captureBodies.map((body) => body.duplicate).sort(),
        [false, true],
      );
      assert.equal(
        captureBodies[0].workoutTemplateId,
        captureBodies[1].workoutTemplateId,
      );
      assert.equal(
        captureBodies[0].routineEntryId,
        captureBodies[1].routineEntryId,
      );

      const capturedRows = await database.sql`
        select payload
        from prescriptions
        where user_id = ${userId}
          and deleted_at is null
          and payload ->> 'template_exercise_id' in (
            select id
            from template_exercises
            where user_id = ${userId}
              and deleted_at is null
              and payload ->> 'workout_template_id' = ${captureBodies[0].workoutTemplateId}
          )
      `;
      assert.equal(capturedRows.length, 2);
      const capturedSquat = capturedRows.find(
        (row) => row.payload.reps_entered === "5",
      );
      assert.equal(capturedSquat.payload.mode, "fixed");
      assert.equal(capturedSquat.payload.repeat, 2);
      assert.equal(capturedSquat.payload.rest_after, 90);

      const capturedGroupRows = await database.sql`
        select id
        from template_groups
        where user_id = ${userId}
          and deleted_at is null
          and payload ->> 'workout_template_id' = ${captureBodies[0].workoutTemplateId}
      `;
      assert.equal(capturedGroupRows.length, 1);
      const capturedGroupMemberRows = await database.sql`
        select id
        from template_group_members
        where user_id = ${userId}
          and deleted_at is null
          and payload ->> 'group_id' = ${capturedGroupRows[0].id}
      `;
      assert.equal(capturedGroupMemberRows.length, 2);

      const captureActivities = await database.sql`
        select actor, entity_table
        from activity_log
        where user_id = ${userId}
          and batch_id = ${captureRequest.idempotencyKey}
      `;
      assert.equal(
        captureActivities.filter(
          (row) => row.entity_table === AGENT_PLAN_CAPTURE_BATCH_ENTITY,
        ).length,
        1,
      );
      assert.ok(captureActivities.every((row) => row.actor === "agent"));

      const updateRequest = {
        idempotencyKey: `update-${randomUUID()}`,
        workoutId: ids.workout,
      };
      const updateResponses = await Promise.all([
        postUpdate(app, updateRequest),
        postUpdate(app, updateRequest),
      ]);
      const updateBodies = await Promise.all(
        updateResponses.map((response) => response.json()),
      );
      assert.ok(
        updateResponses.every((response) => response.status === 200),
        JSON.stringify({
          responses: updateResponses.map((response, index) => ({
            status: response.status,
            body: updateBodies[index],
          })),
          errors,
        }),
      );
      assert.deepEqual(
        updateBodies.map((body) => body.duplicate).sort(),
        [false, true],
      );
      assert.equal(updateBodies[0].workoutTemplateId, ids.linkedTemplate);
      assert.deepEqual(updateBodies[0].divergence, {
        addedExercises: [
          {
            exerciseId: ids.exerciseTwo,
            exerciseName: "Cable Row",
          },
        ],
        removedExercises: [],
        changedExercises: [],
        groupsChanged: true,
      });

      const identityRows = await database.sql`
        select id, payload
        from workout_templates
        where user_id = ${userId} and id = ${ids.linkedTemplate}
      `;
      assert.equal(identityRows[0].payload.name, "Original identity");
      assert.equal(identityRows[0].payload.notes, "Keep these notes");

      const membershipRows = await database.sql`
        select id, payload, deleted_at
        from routine_entries
        where user_id = ${userId}
          and payload ->> 'workout_template_id' = ${ids.linkedTemplate}
      `;
      assert.equal(membershipRows.length, 1);
      assert.equal(membershipRows[0].id, ids.linkedRoutineEntry);
      assert.equal(membershipRows[0].deleted_at, null);

      const linkRows = await database.sql`
        select id, payload, deleted_at
        from template_links
        where user_id = ${userId}
          and payload ->> 'workout_id' = ${ids.workout}
      `;
      assert.equal(linkRows.length, 1);
      assert.equal(linkRows[0].id, ids.templateLink);
      assert.equal(linkRows[0].payload.workout_template_id, ids.linkedTemplate);
      assert.equal(linkRows[0].deleted_at, null);

      const updatedPrescriptions = await database.sql`
        select id, payload
        from prescriptions
        where user_id = ${userId}
          and deleted_at is null
          and payload ->> 'template_exercise_id' in (
            select id
            from template_exercises
            where user_id = ${userId}
              and deleted_at is null
              and payload ->> 'workout_template_id' = ${ids.linkedTemplate}
          )
      `;
      assert.equal(updatedPrescriptions.length, 2);
      const updatedCopyPrevious = updatedPrescriptions.find(
        (row) => row.payload.mode === "copy-previous",
      );
      assert.ok(updatedCopyPrevious);
      assert.equal(updatedCopyPrevious.payload.repeat, 2);
      assert.equal(updatedCopyPrevious.payload.load_entered, null);
      assert.equal(updatedCopyPrevious.payload.reps_entered, null);

      const updatedGroupRows = await database.sql`
        select id
        from template_groups
        where user_id = ${userId}
          and deleted_at is null
          and payload ->> 'workout_template_id' = ${ids.linkedTemplate}
      `;
      assert.equal(updatedGroupRows.length, 1);
      const updatedGroupMemberRows = await database.sql`
        select id
        from template_group_members
        where user_id = ${userId}
          and deleted_at is null
          and payload ->> 'group_id' = ${updatedGroupRows[0].id}
      `;
      assert.equal(updatedGroupMemberRows.length, 2);

      const updateActivities = await database.sql`
        select actor, entity_table
        from activity_log
        where user_id = ${userId}
          and batch_id = ${updateRequest.idempotencyKey}
      `;
      assert.equal(
        updateActivities.filter(
          (row) => row.entity_table === AGENT_PLAN_UPDATE_BATCH_ENTITY,
        ).length,
        1,
      );
      assert.ok(updateActivities.every((row) => row.actor === "agent"));

      const phoneCapture = await postCapture(app, {
        idempotencyKey: `phone-capture-${randomUUID()}`,
        workoutId: ids.phoneWorkout,
        routineId: null,
        slot: null,
      });
      assert.equal(phoneCapture.status, 200);
      const phoneCaptureBody = await phoneCapture.json();
      assert.equal(phoneCaptureBody.groupCount, 0);
      assert.equal(
        phoneCaptureBody.warnings.some(
          (warning) =>
            warning.rule === "capture_workout_structure_unavailable",
        ),
        false,
      );

      const legacyCapture = await postCapture(app, {
        idempotencyKey: `legacy-capture-${randomUUID()}`,
        workoutId: ids.legacyWorkout,
        routineId: null,
        slot: null,
      });
      assert.equal(legacyCapture.status, 200);
      const legacyCaptureBody = await legacyCapture.json();
      assert.ok(
        legacyCaptureBody.warnings.some(
          (warning) =>
            warning.rule === "capture_workout_structure_unavailable",
        ),
      );

      await database.db.insert(schema.loggedSets).values(
        opaqueRow({
          id: ids.conflictSet,
          userId,
          at,
          payload: {
            ...(await captureLoggedSetPayload(database, userId, ids.setTwo)),
            id: ids.conflictSet,
            position: 2,
          },
        }),
      );
      const future = new Date("2099-01-01T00:00:00.000Z");
      await database.sql`
        update prescriptions
        set updated_at = ${future.toISOString()}::timestamptz,
            payload = jsonb_set(
              payload,
              '{updated_at}',
              to_jsonb(${future.toISOString()}::text)
            )
        where user_id = ${userId}
          and id = ${updatedCopyPrevious.id}
      `;

      const conflictBatchId = `update-conflict-${randomUUID()}`;
      const conflictResponse = await postUpdate(app, {
        idempotencyKey: conflictBatchId,
        workoutId: ids.workout,
      });
      assert.equal(conflictResponse.status, 409);
      const conflictBody = await conflictResponse.json();
      assert.equal(
        conflictBody.code,
        "agent_plan_update_from_workout_conflict",
      );
      assert.ok(
        conflictBody.superseded.some(
          (row) =>
            row.entityType === "prescription" &&
            row.id === updatedCopyPrevious.id,
        ),
      );
      const conflictMarkers = await database.sql`
        select id
        from activity_log
        where user_id = ${userId}
          and batch_id = ${conflictBatchId}
      `;
      assert.equal(conflictMarkers.length, 0);
      const activeRowsAfterConflict = await database.sql`
        select p.id
        from prescriptions p
        inner join template_exercises e
          on e.id = p.payload ->> 'template_exercise_id'
        where p.user_id = ${userId}
          and p.deleted_at is null
          and e.user_id = ${userId}
          and e.deleted_at is null
          and e.payload ->> 'workout_template_id' = ${ids.linkedTemplate}
      `;
      assert.equal(activeRowsAfterConflict.length, 2);
      assert.equal(nudges.length, 4);
    } finally {
      await database.close();
    }
  },
);

function createCaptureApp({ store, syncNudgePublisher }) {
  return createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore("user-1"),
    agentCatalogStore: captureCatalog("user-1"),
    agentPlanCaptureStore: store,
    syncNudgePublisher,
  });
}

function inMemoryCaptureStore({
  workout,
  routine = null,
  linked = null,
  writes,
  conflict = null,
}) {
  const receipts = new Map();
  return {
    async readPlanVerbReceipt({ userId, batchId, kind }) {
      return receipts.get(`${userId}:${kind}:${batchId}`) ?? null;
    },
    async loadWorkoutCaptureSource({ workoutId }) {
      return workoutId === workout.workoutId ? workout : null;
    },
    async loadCaptureRoutine({ routineId }) {
      return routine?.routine.id === routineId ? routine : null;
    },
    async loadLinkedTemplate({ workoutId }) {
      return workoutId === workout.workoutId ? linked : null;
    },
    async writePlanVerb(input) {
      if (conflict !== null) {
        throw new AgentPlanCaptureConflictError(conflict);
      }
      writes.push(input);
      const receipt = {
        ...input.receipt,
        serverClock: "2026-07-25T00:00:01.000Z",
      };
      receipts.set(
        `${input.userId}:${input.kind}:${input.batchId}`,
        receipt,
      );
      return {
        duplicate: false,
        applied: Object.values(input.rows).reduce(
          (count, rows) => count + rows.length,
          0,
        ),
        receipt,
      };
    },
  };
}

function workoutSnapshot() {
  return {
    workoutId: "workout-1",
    exercises: [
      {
        sourceWorkoutExerciseId: "workout-exercise-bench",
        exerciseId: "exercise-bench",
        exerciseName: "stale name",
        position: 0,
        sets: [
          {
            sourceSetId: "set-1",
            position: 0,
            values: {
              load: { entered: "100", unit: "kilogram" },
              reps: { entered: "5", unit: "repetition" },
            },
            plannedRestAfterSeconds: 90,
            comment: "stripped",
            rpe: 9,
            side: "left",
          },
          {
            sourceSetId: "set-2",
            position: 1,
            values: {
              load: { entered: "100", unit: "kilogram" },
              reps: { entered: "5", unit: "repetition" },
            },
            plannedRestAfterSeconds: 90,
            comment: "also stripped",
            rpe: 10,
            side: "right",
          },
        ],
      },
      {
        sourceWorkoutExerciseId: "workout-exercise-row",
        exerciseId: "exercise-row",
        exerciseName: "stale row",
        position: 1,
        sets: [
          {
            sourceSetId: "set-3",
            position: 0,
            values: {
              reps: { entered: "10", unit: "repetition" },
            },
            plannedRestAfterSeconds: null,
          },
        ],
      },
    ],
    groups: [
      {
        sourceGroupId: "workout-group-1",
        name: "Superset",
        colorHex: "#2F6FED",
        position: 0,
        memberSourceWorkoutExerciseIds: [
          "workout-exercise-bench",
          "workout-exercise-row",
        ],
      },
    ],
  };
}

function matchingWorkoutSnapshot() {
  return {
    workoutId: "workout-1",
    exercises: [workoutSnapshot().exercises[0]],
    groups: [],
  };
}

function routineState() {
  return {
    routine: planRow("routine-1", {
      name: "Collection",
      notes: null,
      cadence_kind: null,
      cadence_window: null,
    }),
    entries: [
      planRow("routine-entry-existing", {
        routine_id: "routine-1",
        workout_template_id: "another-template",
        position: 0,
        slot: null,
      }),
    ],
  };
}

function linkedTemplateState() {
  return {
    templateLink: planRow("template-link-1", {
      workout_id: "workout-1",
      workout_template_id: "template-linked",
      routine_id: "routine-keep",
      slot: 2,
    }),
    workoutTemplate: planRow("template-linked", {
      name: "Original identity",
      notes: "Keep these notes",
    }),
    templateExercises: [
      planRow("template-exercise-bench", {
        workout_template_id: "template-linked",
        exercise_id: "exercise-bench",
        position: 0,
        note: "content note is replaced",
      }),
    ],
    prescriptions: [
      planRow("prescription-copy", {
        template_exercise_id: "template-exercise-bench",
        mode: "copy-previous",
        position: 0,
        repeat: 2,
        rest_after: 90,
        load_value: null,
        load_unit: null,
        load_entered: null,
        reps_value: null,
        reps_unit: null,
        reps_entered: null,
        duration_value: null,
        duration_unit: null,
        duration_entered: null,
        distance_value: null,
        distance_unit: null,
        distance_entered: null,
      }),
    ],
    templateGroups: [],
    templateGroupMembers: [],
  };
}

function planRow(id, payload) {
  const at = new Date("2026-07-25T00:00:00.000Z");
  return {
    id,
    userId: "user-1",
    payload: {
      id,
      ...payload,
      updated_at: at.toISOString(),
      deleted_at: null,
    },
    updatedAt: at,
    deletedAt: null,
  };
}

function integrationIds() {
  const suffix = randomUUID();
  return {
    category: `category-${suffix}`,
    exercise: `exercise-${suffix}`,
    exerciseTwo: `exercise-two-${suffix}`,
    workout: `workout-${suffix}`,
    workoutExercise: `workout-exercise-${suffix}`,
    workoutExerciseTwo: `workout-exercise-two-${suffix}`,
    workoutGroup: `workout-group-${suffix}`,
    workoutGroupMemberOne: `workout-group-member-one-${suffix}`,
    workoutGroupMemberTwo: `workout-group-member-two-${suffix}`,
    setOne: `set-one-${suffix}`,
    setTwo: `set-two-${suffix}`,
    setThree: `set-three-${suffix}`,
    conflictSet: `conflict-set-${suffix}`,
    phoneWorkout: `phone-workout-${suffix}`,
    phoneWorkoutExercise: `phone-workout-exercise-${suffix}`,
    phoneSet: `phone-set-${suffix}`,
    legacyWorkout: `legacy-workout-${suffix}`,
    legacySet: `legacy-set-${suffix}`,
    linkedTemplate: `linked-template-${suffix}`,
    linkedTemplateExercise: `linked-template-exercise-${suffix}`,
    linkedPrescription: `linked-prescription-${suffix}`,
    templateLink: `template-link-${suffix}`,
    routine: `routine-${suffix}`,
    linkedRoutineEntry: `linked-routine-entry-${suffix}`,
  };
}

async function seedCaptureScenario(database, { userId, ids, at }) {
  await database.db.insert(schema.user).values({
    id: userId,
    name: "Agent Capture User",
    email: `${userId}@example.com`,
    emailVerified: true,
  });
  await database.db.insert(schema.exerciseCategories).values(
    opaqueRow({
      id: ids.category,
      userId,
      at,
      payload: {
        name: "Strength",
        sort_order: 0,
        color_hex: "#336699",
      },
    }),
  );
  await database.db.insert(schema.exercises).values([
    opaqueRow({
      id: ids.exercise,
      userId,
      at,
      payload: {
        library_origin: "user",
        name: "Back Squat",
        dimension_ids: JSON.stringify(["load", "reps"]),
        default_load_unit: "kilogram",
        load_mode: "added",
        record_profile: "repMax",
        is_favorite: false,
        is_unilateral: false,
        uses_rpe: false,
        category_id: ids.category,
        equipment_ids: JSON.stringify(["barbell"]),
        notes: null,
      },
    }),
    opaqueRow({
      id: ids.exerciseTwo,
      userId,
      at,
      payload: {
        library_origin: "user",
        name: "Cable Row",
        dimension_ids: JSON.stringify(["reps"]),
        default_load_unit: "kilogram",
        load_mode: "added",
        record_profile: "repMax",
        is_favorite: false,
        is_unilateral: false,
        uses_rpe: false,
        category_id: ids.category,
        equipment_ids: JSON.stringify(["cable"]),
        notes: null,
      },
    }),
  ]);
  await database.db.insert(schema.workoutSessions).values([
    opaqueRow({
      id: ids.workout,
      userId,
      at,
      payload: {
        started_at: "2026-07-25T01:00:00.000Z",
        timezone: "Australia/Brisbane",
        local_date: "2026-07-25",
        ended_at: "2026-07-25T02:00:00.000Z",
        comment: "Fact commentary",
      },
    }),
    opaqueRow({
      id: ids.phoneWorkout,
      userId,
      at,
      payload: {
        started_at: "2026-07-25T03:00:00.000Z",
        timezone: "Australia/Brisbane",
        local_date: "2026-07-25",
        ended_at: "2026-07-25T04:00:00.000Z",
        comment: "Phone Workout",
      },
    }),
  ]);
  await database.db.insert(schema.workoutExercises).values([
    opaqueRow({
      id: ids.workoutExercise,
      userId,
      at,
      payload: {
        workout_id: ids.workout,
        exercise_id: ids.exercise,
        position: 0,
      },
    }),
    opaqueRow({
      id: ids.workoutExerciseTwo,
      userId,
      at,
      payload: {
        workout_id: ids.workout,
        exercise_id: ids.exerciseTwo,
        position: 1,
      },
    }),
    opaqueRow({
      id: ids.phoneWorkoutExercise,
      userId,
      at,
      payload: {
        workout_id: ids.phoneWorkout,
        exercise_id: ids.exercise,
        position: 0,
      },
    }),
  ]);
  await database.db.insert(schema.exerciseGroups).values(
    opaqueRow({
      id: ids.workoutGroup,
      userId,
      at,
      payload: {
        workout_id: ids.workout,
        name: "Superset",
        color_hex: "#2F6FED",
        position: 0,
      },
    }),
  );
  await database.db.insert(schema.exerciseGroupMembers).values([
    opaqueRow({
      id: ids.workoutGroupMemberOne,
      userId,
      at,
      payload: {
        group_id: ids.workoutGroup,
        workout_exercise_id: ids.workoutExercise,
        position: 0,
      },
    }),
    opaqueRow({
      id: ids.workoutGroupMemberTwo,
      userId,
      at,
      payload: {
        group_id: ids.workoutGroup,
        workout_exercise_id: ids.workoutExerciseTwo,
        position: 1,
      },
    }),
  ]);
  await database.db.insert(schema.workoutTemplates).values(
    opaqueRow({
      id: ids.linkedTemplate,
      userId,
      at,
      payload: {
        name: "Original identity",
        notes: "Keep these notes",
      },
    }),
  );
  await database.db.insert(schema.templateExercises).values(
    opaqueRow({
      id: ids.linkedTemplateExercise,
      userId,
      at,
      payload: {
        workout_template_id: ids.linkedTemplate,
        exercise_id: ids.exercise,
        position: 0,
        note: "Replaced content note",
      },
    }),
  );
  await database.db.insert(schema.prescriptions).values(
    opaqueRow({
      id: ids.linkedPrescription,
      userId,
      at,
      payload: {
        template_exercise_id: ids.linkedTemplateExercise,
        mode: "copy-previous",
        position: 0,
        repeat: 2,
        rest_after: 90,
        load_value: null,
        load_unit: null,
        load_entered: null,
        reps_value: null,
        reps_unit: null,
        reps_entered: null,
        duration_value: null,
        duration_unit: null,
        duration_entered: null,
        distance_value: null,
        distance_unit: null,
        distance_entered: null,
      },
    }),
  );
  await database.db.insert(schema.routines).values(
    opaqueRow({
      id: ids.routine,
      userId,
      at,
      payload: {
        name: "Collection",
        notes: null,
        cadence_kind: null,
        cadence_window: null,
      },
    }),
  );
  await database.db.insert(schema.routineEntries).values(
    opaqueRow({
      id: ids.linkedRoutineEntry,
      userId,
      at,
      payload: {
        routine_id: ids.routine,
        workout_template_id: ids.linkedTemplate,
        position: 0,
        slot: null,
      },
    }),
  );
  const setPayload = ({
    id,
    workoutId = ids.workout,
    exerciseId = ids.exercise,
    exerciseName = "Back Squat",
    position,
    reps = "5",
    plannedRestAfter = 90,
    includeLoad = true,
  }) => ({
    id,
    workout_id: workoutId,
    workout_started_at: "2026-07-25T01:00:00.000Z",
    workout_timezone: "Australia/Brisbane",
    workout_local_date: "2026-07-25",
    exercise_id: exerciseId,
    exercise_name: exerciseName,
    position,
    planned_rest_after: plannedRestAfter,
    performed_at: `2026-07-25T01:0${position}:00.000Z`,
    is_completed: true,
    load_value: includeLoad ? 100 : null,
    load_unit: includeLoad ? "kilogram" : null,
    load_entered: includeLoad ? "100" : null,
    reps_value: Number(reps),
    reps_unit: "repetition",
    reps_entered: reps,
    duration_value: null,
    duration_unit: null,
    duration_entered: null,
    distance_value: null,
    distance_unit: null,
    distance_entered: null,
    comment: position === 0 ? "Strip me" : null,
    side: position === 0 ? "left" : "right",
    rpe: 9,
  });
  await database.db.insert(schema.loggedSets).values([
    opaqueRow({
      id: ids.setOne,
      userId,
      at,
      payload: setPayload({ id: ids.setOne, position: 0 }),
    }),
    opaqueRow({
      id: ids.setTwo,
      userId,
      at,
      payload: setPayload({ id: ids.setTwo, position: 1 }),
    }),
    opaqueRow({
      id: ids.setThree,
      userId,
      at,
      payload: setPayload({
        id: ids.setThree,
        exerciseId: ids.exerciseTwo,
        exerciseName: "Cable Row",
        position: 0,
        reps: "10",
        plannedRestAfter: null,
        includeLoad: false,
      }),
    }),
    opaqueRow({
      id: ids.phoneSet,
      userId,
      at,
      payload: setPayload({
        id: ids.phoneSet,
        workoutId: ids.phoneWorkout,
        position: 0,
      }),
    }),
    opaqueRow({
      id: ids.legacySet,
      userId,
      at,
      payload: setPayload({
        id: ids.legacySet,
        workoutId: ids.legacyWorkout,
        position: 0,
      }),
    }),
  ]);
  await database.db.insert(schema.templateLinks).values(
    opaqueRow({
      id: ids.templateLink,
      userId,
      at,
      payload: {
        workout_id: ids.workout,
        workout_template_id: ids.linkedTemplate,
        routine_id: ids.routine,
        slot: null,
        workout_started_at: "2026-07-25T01:00:00.000Z",
        workout_timezone: "Australia/Brisbane",
        workout_local_date: "2026-07-25",
        workout_ended_at: "2026-07-25T02:00:00.000Z",
        workout_comment: "Fact commentary",
        workout_updated_at: at.toISOString(),
        workout_deleted_at: null,
        workout_exercises: [
          {
            id: ids.workoutExercise,
            workout_id: ids.workout,
            exercise_id: ids.exercise,
            position: 0,
            updated_at: at.toISOString(),
            deleted_at: null,
          },
          {
            id: ids.workoutExerciseTwo,
            workout_id: ids.workout,
            exercise_id: ids.exerciseTwo,
            position: 1,
            updated_at: at.toISOString(),
            deleted_at: null,
          },
        ],
        workout_exercise_groups: [
          {
            id: ids.workoutGroup,
            workout_id: ids.workout,
            name: "Superset",
            color_hex: "#2F6FED",
            position: 0,
            updated_at: at.toISOString(),
            deleted_at: null,
          },
        ],
        workout_exercise_group_members: [
          {
            id: ids.workoutGroupMemberOne,
            group_id: ids.workoutGroup,
            workout_exercise_id: ids.workoutExercise,
            position: 0,
            updated_at: at.toISOString(),
            deleted_at: null,
          },
          {
            id: ids.workoutGroupMemberTwo,
            group_id: ids.workoutGroup,
            workout_exercise_id: ids.workoutExerciseTwo,
            position: 1,
            updated_at: at.toISOString(),
            deleted_at: null,
          },
        ],
      },
    }),
  );
}

async function captureLoggedSetPayload(database, userId, setId) {
  const rows = await database.sql`
    select payload
    from logged_sets
    where user_id = ${userId} and id = ${setId}
  `;
  assert.equal(rows.length, 1);
  return rows[0].payload;
}

function opaqueRow({ id, userId, at, payload }) {
  return {
    id,
    userId,
    deviceId: "device-a",
    payload: {
      id,
      ...payload,
      updated_at: at.toISOString(),
      deleted_at: null,
    },
    updatedAt: at,
    deletedAt: null,
    receivedAt: at,
  };
}

function captureCatalog(userId) {
  return createInMemoryAgentCatalogStore([
    exerciseFixture({
      id: "exercise-bench",
      ownerUserId: userId,
      name: "Bench Press",
      dimensions: ["load", "reps"],
    }),
    exerciseFixture({
      id: "exercise-row",
      ownerUserId: userId,
      name: "Cable Row",
      dimensions: ["reps"],
    }),
  ]);
}

function exerciseFixture({ id, ownerUserId, name, dimensions }) {
  return {
    id,
    library: "user",
    ownerUserId,
    name,
    category: { id: "strength", name: "Strength" },
    dimensions,
    equipment: [],
    loadMode: "added",
    recordProfile: "repMax",
    favorite: false,
    active: true,
    shadowedPlatformExerciseId: null,
  };
}

function nudgeRecorder(nudges) {
  return {
    async enqueueSyncNudge(input) {
      nudges.push(input);
      return { enqueued: true, jobId: `nudge-${nudges.length}` };
    },
  };
}

function createAgentKeyStore(userId) {
  return {
    async authenticateAgentApiKey(secret) {
      return secret === "prn_agent_secret"
        ? {
            userId,
            keyId: "agent-key-1",
            keyName: "Plan coach",
          }
        : null;
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
    },
  };
}

function postCapture(app, body) {
  return postAgent(app, "/agent/workout-templates/capture", body);
}

function postUpdate(app, body) {
  return postAgent(
    app,
    "/agent/workout-templates/update-from-workout",
    body,
  );
}

function postAgent(app, path, body) {
  return app.request(path, {
    method: "POST",
    headers: {
      authorization: "Bearer prn_agent_secret",
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

function postMcp(app, body) {
  return app.request("/mcp", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_agent_secret",
      "content-type": "application/json",
      accept: "application/json, text/event-stream",
    },
    body: JSON.stringify(body),
  });
}
