import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  AGENT_PLAN_MATERIALIZE_BATCH_ENTITY,
  AGENT_PLAN_MATERIALIZE_MAX_SETS,
  applyMigrations,
  createAgentMcpServer,
  createApp,
  createDatabaseClient,
  createDrizzleAgentActivityStore,
  createDrizzleAgentCatalogStore,
  createDrizzleAgentPlanMaterializeStore,
  createDrizzleAgentPlanReadStore,
  createInMemoryAgentCatalogStore,
  materializeAgentTemplateContent,
  schema,
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error(
    "DATABASE_URL must be set for server Postgres integration tests.",
  );
}

const skip = databaseUrl ? false : "DATABASE_URL is not set.";

test("TypeScript materialize semantics match every shared M34 app fixture", async () => {
  const fixture = JSON.parse(
    await readFile(
      new URL(
        "../../../packages/golden-vectors/vectors/m34-plan-materialize.json",
        import.meta.url,
      ),
      "utf8",
    ),
  );

  for (const fixtureCase of fixture.cases) {
    assert.deepEqual(
      materializeAgentTemplateContent(fixtureCase.input),
      fixtureCase.expected,
      fixtureCase.name,
    );
  }
});

test("materialize rejects an expansion above the 100-Set cap before writing or nudging", async () => {
  const writes = [];
  const nudges = [];
  const source = materializeSource({
    prescriptions: [
      planRow("prescription-cap", {
        template_exercise_id: "template-exercise-cap",
        mode: "fixed",
        position: 0,
        repeat: AGENT_PLAN_MATERIALIZE_MAX_SETS + 1,
        rest_after: 120,
        load_value: 100,
        load_unit: "kilogram",
        load_entered: "100",
        reps_value: 5,
        reps_unit: "repetition",
        reps_entered: "5",
      }),
    ],
  });
  const app = createMaterializeApp({
    agentPlanMaterializeStore: inMemoryMaterializeStore({ source, writes }),
    syncNudgePublisher: {
      async enqueueSyncNudge(input) {
        nudges.push(input);
        return { enqueued: true, jobId: "unexpected" };
      },
    },
  });

  const response = await postMaterialize(app, materializeRequest("cap-key"));

  assert.equal(response.status, 422);
  const body = await response.json();
  assert.equal(body.code, "agent_plan_materialize_failed");
  assert.ok(
    body.errors.some((issue) => issue.rule === "materialize_set_cap_exceeded"),
  );
  assert.equal(body.limits.maxSets, AGENT_PLAN_MATERIALIZE_MAX_SETS);
  assert.deepEqual(writes, []);
  assert.deepEqual(nudges, []);
});

test("materialize rejects a startedAt beyond the server clock-skew allowance", async () => {
  const writes = [];
  const nudges = [];
  const app = createMaterializeApp({
    agentPlanMaterializeStore: inMemoryMaterializeStore({
      source: materializeSource({ prescriptions: [] }),
      writes,
    }),
    syncNudgePublisher: {
      async enqueueSyncNudge(input) {
        nudges.push(input);
        return { enqueued: true, jobId: "unexpected" };
      },
    },
  });

  const response = await postMaterialize(app, {
    ...materializeRequest("future-key"),
    startedAt: "2100-01-01T00:00:00.000Z",
  });

  assert.equal(response.status, 422);
  const body = await response.json();
  assert.ok(
    body.errors.some(
      (issue) => issue.rule === "materialize_started_at_in_future",
    ),
  );
  assert.deepEqual(writes, []);
  assert.deepEqual(nudges, []);
});

test("agent_materialize_workout_template mirrors REST over bearer-authenticated MCP", async () => {
  const writes = [];
  const nudges = [];
  const agentApiKeyStore = createAgentKeyStore("user-1");
  const agentCatalogStore = materializeCatalog("user-1");
  const source = materializeSource({
    prescriptions: [
      planRow("prescription-mcp", {
        template_exercise_id: "template-exercise-cap",
        mode: "fixed",
        position: 0,
        repeat: 1,
        rest_after: 90,
        load_value: 60,
        load_unit: "kilogram",
        load_entered: "60",
        reps_value: 8,
        reps_unit: "repetition",
        reps_entered: "8",
      }),
    ],
  });
  const agentPlanMaterializeStore = {
    async readMaterializeReceipt() {
      return null;
    },
    async loadMaterializeSource() {
      return source;
    },
    async loadMaterializeHistory() {
      return {
        lastPerformedValuesByExerciseId: {},
        defaultLoadUnitsByExerciseId: {},
      };
    },
    async writeMaterialization(input) {
      writes.push(input);
      return {
        duplicate: false,
        applied: input.sets.length + 1,
        receipt: {
          ...input.receipt,
          serverClock: "2026-07-24T02:00:01.000Z",
        },
      };
    },
  };
  const logger = { info() {}, error() {} };
  const syncNudgePublisher = {
    async enqueueSyncNudge(input) {
      nudges.push(input);
      return { enqueued: true, jobId: "mcp-nudge" };
    },
  };
  const app = createApp({
    logger,
    agentApiKeyStore,
    createMcpServer: () =>
      createAgentMcpServer({
        agentApiKeyStore,
        agentCatalogStore,
        agentPlanMaterializeStore,
        logger,
        syncNudgePublisher,
      }),
  });
  const request = materializeRequest("mcp-materialize-key");

  const response = await postMcp(
    app,
    {
      jsonrpc: "2.0",
      id: 1,
      method: "tools/call",
      params: {
        name: "agent_materialize_workout_template",
        arguments: { request },
      },
    },
    { authorization: "Bearer prn_agent_secret" },
  );

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.result.isError, undefined);
  assert.equal(body.result.structuredContent.accepted, true);
  assert.equal(
    body.result.structuredContent.idempotencyKey,
    request.idempotencyKey,
  );
  assert.equal(body.result.structuredContent.setCount, 1);
  assert.equal(writes.length, 1);
  assert.deepEqual(nudges, [
    {
      userId: "user-1",
      sourceDeviceId: "agent:agent-key-1",
      reason: "agent_write",
    },
  ]);
});

test(
  "materialize resolves history, writes one agent batch/link, nudges once, and concurrent retries advance rotation once",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-materialize-${randomUUID()}`;
    const ids = materializeIds();
    const at = new Date("2026-07-24T02:00:00.000Z");
    const nudges = [];
    const app = createMaterializeApp({
      userId,
      agentCatalogStore: createDrizzleAgentCatalogStore(database.db),
      agentActivityStore: createDrizzleAgentActivityStore(database.db),
      agentPlanReadStore: createDrizzleAgentPlanReadStore(database.db),
      agentPlanMaterializeStore: createDrizzleAgentPlanMaterializeStore(
        database.db,
      ),
      syncNudgePublisher: {
        async enqueueSyncNudge(input) {
          nudges.push(input);
          return { enqueued: true, jobId: `nudge-${nudges.length}` };
        },
      },
    });

    try {
      await seedMaterializeScenario(database, { userId, ids, at });
      const request = {
        idempotencyKey: `materialize-${randomUUID()}`,
        workoutTemplateId: ids.template,
        routineId: ids.routine,
        slot: 1,
        startedAt: "2026-07-23T16:30:00.000Z",
        timezone: "Australia/Brisbane",
      };

      const responses = await Promise.all([
        postMaterialize(app, request),
        postMaterialize(app, request),
      ]);
      assert.ok(responses.every((response) => response.status === 200));
      const bodies = await Promise.all(
        responses.map((response) => response.json()),
      );
      assert.deepEqual(bodies.map((body) => body.duplicate).sort(), [
        false,
        true,
      ]);
      assert.equal(bodies[0].workoutId, bodies[1].workoutId);
      assert.equal(bodies[0].templateLinkId, bodies[1].templateLinkId);
      assert.deepEqual(bodies[0].setIds, bodies[1].setIds);
      assert.equal(bodies[0].setCount, 3);
      assert.equal(bodies[0].localDate, "2026-07-24");
      assert.equal(bodies[0].workoutId[14], "7");
      assert.equal(bodies[0].templateLinkId[14], "7");

      const setRows = await database.sql`
        select id, device_id, payload
        from logged_sets
        where user_id = ${userId}
          and payload ->> 'workout_id' = ${bodies[0].workoutId}
        order by payload ->> 'exercise_id', (payload ->> 'position')::int
      `;
      assert.equal(setRows.length, 3);
      assert.ok(setRows.every((row) => row.device_id === "agent:agent-key-1"));
      const historySets = setRows.filter(
        (row) => row.payload.exercise_id === ids.historyExercise,
      );
      assert.equal(historySets.length, 2);
      assert.ok(
        historySets.every(
          (row) =>
            row.payload.load_entered === "142.5" &&
            row.payload.reps_entered === "3" &&
            row.payload.planned_rest_after === 180 &&
            row.payload.is_completed === false,
        ),
      );
      const zeroSet = setRows.find(
        (row) => row.payload.exercise_id === ids.zeroExercise,
      );
      assert.equal(zeroSet.payload.load_entered, "0");
      assert.equal(zeroSet.payload.load_unit, "pound");
      assert.equal(zeroSet.payload.reps_entered, "0");
      assert.equal(zeroSet.payload.workout_local_date, "2026-07-24");
      assert.equal(
        Object.hasOwn(zeroSet.payload, "workout_exercise_position"),
        false,
      );

      const linkRows = await database.sql`
        select device_id, payload
        from template_links
        where user_id = ${userId}
          and payload ->> 'workout_id' = ${bodies[0].workoutId}
      `;
      assert.equal(linkRows.length, 1);
      assert.equal(linkRows[0].device_id, "agent:agent-key-1");
      assert.equal(linkRows[0].payload.workout_template_id, ids.template);
      assert.equal(linkRows[0].payload.routine_id, ids.routine);
      assert.equal(linkRows[0].payload.slot, 1);
      assert.equal(linkRows[0].payload.workout_local_date, "2026-07-24");
      assert.deepEqual(
        linkRows[0].payload.workout_exercises.map((row) => ({
          exerciseId: row.exercise_id,
          position: row.position,
        })),
        [
          { exerciseId: ids.historyExercise, position: 0 },
          { exerciseId: ids.zeroExercise, position: 1 },
        ],
      );
      assert.equal(linkRows[0].payload.workout_exercise_groups.length, 1);
      assert.equal(
        linkRows[0].payload.workout_exercise_groups[0].name,
        "Main pair",
      );
      assert.equal(
        linkRows[0].payload.workout_exercise_group_members.length,
        2,
      );

      const activityRows = await database.sql`
        select actor, entity_table
        from activity_log
        where user_id = ${userId} and batch_id = ${request.idempotencyKey}
      `;
      assert.equal(activityRows.length, 11);
      assert.ok(activityRows.every((row) => row.actor === "agent"));
      assert.equal(
        activityRows.filter(
          (row) => row.entity_table === AGENT_PLAN_MATERIALIZE_BATCH_ENTITY,
        ).length,
        1,
      );

      const visibleActivityResponse = await getAgent(
        app,
        `/agent/activity?batchId=${encodeURIComponent(request.idempotencyKey)}`,
      );
      assert.equal(visibleActivityResponse.status, 200);
      const visibleActivity = await visibleActivityResponse.json();
      assert.equal(visibleActivity.batches.length, 1);
      assert.equal(visibleActivity.batches[0].entries.length, 10);
      assert.ok(
        visibleActivity.batches[0].entries.every(
          (entry) => entry.entityTable !== AGENT_PLAN_MATERIALIZE_BATCH_ENTITY,
        ),
      );

      const routineResponse = await getAgent(
        app,
        `/agent/routines/${ids.routine}`,
      );
      assert.equal(routineResponse.status, 200);
      const routine = (await routineResponse.json()).routine;
      assert.equal(routine.upNext.slot, 2);
      assert.equal(routine.upNext.cards[0].workoutTemplateId, ids.nextTemplate);

      const linkCount = await database.sql`
        select count(*)::int as count
        from template_links
        where user_id = ${userId}
          and payload ->> 'routine_id' = ${ids.routine}
      `;
      assert.equal(linkCount[0].count, 1);
      assert.equal(nudges.length, 1);
      assert.deepEqual(nudges[0], {
        userId,
        reason: "agent_write",
        sourceDeviceId: "agent:agent-key-1",
      });
    } finally {
      await database.close();
    }
  },
);

test(
  "materialize storage reports only LWW-applied rows when a newer Set already wins",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-materialize-superseded-${randomUUID()}`;
    const setId = `set-${randomUUID()}`;
    const linkId = `link-${randomUUID()}`;
    const batchId = `batch-${randomUUID()}`;
    const existingAt = new Date(Date.now() - 60_000);
    const incomingAt = new Date(existingAt.getTime() - 60_000);
    const existingSet = loggedSetRow({
      id: setId,
      userId,
      exerciseId: `exercise-${randomUUID()}`,
      at: existingAt,
      performedAt: existingAt.toISOString(),
      isCompleted: true,
      loadEntered: "100",
      repsEntered: "5",
    });

    try {
      await database.db.insert(schema.user).values({
        id: userId,
        name: "Agent Materialize Superseded User",
        email: `${userId}@example.com`,
        emailVerified: true,
      });
      await database.db.insert(schema.loggedSets).values(existingSet);

      const store = createDrizzleAgentPlanMaterializeStore(database.db);
      const result = await store.writeMaterialization({
        userId,
        batchId,
        deviceId: "agent:agent-key-1",
        receipt: {
          workoutId: "incoming-workout",
          templateLinkId: linkId,
          setIds: [setId],
          startedAt: incomingAt.toISOString(),
          timezone: "UTC",
          localDate: incomingAt.toISOString().slice(0, 10),
          workoutTemplateId: "incoming-template",
          routineId: null,
          slot: null,
          warnings: [],
        },
        sets: [
          {
            id: setId,
            updatedAt: incomingAt.toISOString(),
            payload: {
              ...existingSet.payload,
              workout_id: "incoming-workout",
              updated_at: incomingAt.toISOString(),
            },
          },
        ],
        templateLink: {
          id: linkId,
          updatedAt: incomingAt.toISOString(),
          payload: {
            id: linkId,
            workout_id: "incoming-workout",
            workout_template_id: "incoming-template",
            routine_id: null,
            slot: null,
            updated_at: incomingAt.toISOString(),
            deleted_at: null,
          },
        },
      });

      assert.equal(result.duplicate, false);
      assert.equal(result.applied, 2);
      const storedSets = await database.sql`
        select device_id, payload
        from logged_sets
        where user_id = ${userId} and id = ${setId}
      `;
      assert.equal(storedSets[0].device_id, "device-a");
      assert.equal(
        storedSets[0].payload.workout_id,
        `history-workout-${setId}`,
      );
      const storedLinks = await database.sql`
        select id
        from template_links
        where user_id = ${userId} and id = ${linkId}
      `;
      assert.equal(storedLinks.length, 1);
    } finally {
      await database.close();
    }
  },
);

function createMaterializeApp({
  agentActivityStore,
  agentCatalogStore = materializeCatalog("user-1"),
  agentPlanMaterializeStore,
  agentPlanReadStore,
  syncNudgePublisher,
  userId = "user-1",
}) {
  return createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore(userId),
    agentActivityStore,
    agentCatalogStore,
    agentPlanMaterializeStore,
    agentPlanReadStore,
    syncNudgePublisher,
  });
}

function materializeCatalog(userId) {
  return createInMemoryAgentCatalogStore([
    exerciseFixture({
      id: "exercise-cap",
      library: "user",
      ownerUserId: userId,
      name: "Back Squat",
    }),
  ]);
}

function exerciseFixture({
  id,
  library = "platform",
  ownerUserId = null,
  name,
}) {
  return {
    id,
    library,
    ownerUserId,
    name,
    category: { id: "strength", name: "Strength" },
    dimensions: ["load", "reps"],
    equipment: ["barbell"],
    loadMode: "added",
    recordProfile: "repMax",
    favorite: false,
    active: true,
    shadowedPlatformExerciseId: null,
  };
}

function inMemoryMaterializeStore({ source, writes = [] }) {
  return {
    async readMaterializeReceipt() {
      return null;
    },
    async loadMaterializeSource() {
      return source;
    },
    async loadMaterializeHistory() {
      return {
        lastPerformedValuesByExerciseId: {},
        defaultLoadUnitsByExerciseId: {},
      };
    },
    async writeMaterialization(input) {
      writes.push(input);
      throw new Error("writeMaterialization should not be called.");
    },
  };
}

function materializeSource({ prescriptions }) {
  return {
    workoutTemplate: planRow("template-cap", {
      name: "Too many Sets",
      notes: null,
    }),
    templateExercises: [
      planRow("template-exercise-cap", {
        workout_template_id: "template-cap",
        exercise_id: "exercise-cap",
        position: 0,
        note: null,
      }),
    ],
    prescriptions,
    templateGroups: [],
    templateGroupMembers: [],
    routine: null,
    routineEntries: [],
  };
}

function planRow(id, payload) {
  const at = new Date("2026-07-24T02:00:00.000Z");
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

function materializeRequest(idempotencyKey) {
  return {
    idempotencyKey,
    workoutTemplateId: "template-cap",
    routineId: null,
    slot: null,
    startedAt: "2026-07-24T02:00:00.000Z",
    timezone: "Australia/Brisbane",
  };
}

function materializeIds() {
  const prefix = randomUUID();
  return {
    category: `category-${prefix}`,
    historyExercise: `history-exercise-${prefix}`,
    zeroExercise: `zero-exercise-${prefix}`,
    template: `template-${prefix}`,
    nextTemplate: `next-template-${prefix}`,
    historyTemplateExercise: `history-template-exercise-${prefix}`,
    zeroTemplateExercise: `zero-template-exercise-${prefix}`,
    historyPrescription: `history-prescription-${prefix}`,
    zeroPrescription: `zero-prescription-${prefix}`,
    templateGroup: `template-group-${prefix}`,
    historyGroupMember: `history-group-member-${prefix}`,
    zeroGroupMember: `zero-group-member-${prefix}`,
    routine: `routine-${prefix}`,
    routineEntry: `routine-entry-${prefix}`,
    nextRoutineEntry: `next-routine-entry-${prefix}`,
    completedSet: `completed-set-${prefix}`,
    incompleteSet: `incomplete-set-${prefix}`,
  };
}

async function seedMaterializeScenario(database, { userId, ids, at }) {
  await database.db.insert(schema.user).values({
    id: userId,
    name: "Agent Materialize User",
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
    exerciseRow({
      id: ids.historyExercise,
      userId,
      categoryId: ids.category,
      name: "History Squat",
      defaultLoadUnit: "kilogram",
      at,
    }),
    exerciseRow({
      id: ids.zeroExercise,
      userId,
      categoryId: ids.category,
      name: "Never Performed Row",
      defaultLoadUnit: "pound",
      at,
    }),
  ]);
  await database.db.insert(schema.workoutTemplates).values([
    opaqueRow({
      id: ids.template,
      userId,
      at,
      payload: { name: "Strength A", notes: null },
    }),
    opaqueRow({
      id: ids.nextTemplate,
      userId,
      at,
      payload: { name: "Strength B", notes: null },
    }),
  ]);
  await database.db.insert(schema.templateExercises).values([
    opaqueRow({
      id: ids.historyTemplateExercise,
      userId,
      at,
      payload: {
        workout_template_id: ids.template,
        exercise_id: ids.historyExercise,
        position: 0,
        note: null,
      },
    }),
    opaqueRow({
      id: ids.zeroTemplateExercise,
      userId,
      at,
      payload: {
        workout_template_id: ids.template,
        exercise_id: ids.zeroExercise,
        position: 1,
        note: null,
      },
    }),
  ]);
  await database.db.insert(schema.prescriptions).values([
    opaqueRow({
      id: ids.historyPrescription,
      userId,
      at,
      payload: prescriptionPayload({
        templateExerciseId: ids.historyTemplateExercise,
        repeat: 2,
        restAfter: 180,
      }),
    }),
    opaqueRow({
      id: ids.zeroPrescription,
      userId,
      at,
      payload: prescriptionPayload({
        templateExerciseId: ids.zeroTemplateExercise,
        repeat: 1,
        restAfter: null,
      }),
    }),
  ]);
  await database.db.insert(schema.templateGroups).values(
    opaqueRow({
      id: ids.templateGroup,
      userId,
      at,
      payload: {
        workout_template_id: ids.template,
        name: "Main pair",
        color_hex: "#0891B2",
        position: 0,
        rounds: 1,
      },
    }),
  );
  await database.db.insert(schema.templateGroupMembers).values([
    opaqueRow({
      id: ids.historyGroupMember,
      userId,
      at,
      payload: {
        group_id: ids.templateGroup,
        template_exercise_id: ids.historyTemplateExercise,
        position: 0,
      },
    }),
    opaqueRow({
      id: ids.zeroGroupMember,
      userId,
      at,
      payload: {
        group_id: ids.templateGroup,
        template_exercise_id: ids.zeroTemplateExercise,
        position: 1,
      },
    }),
  ]);
  await database.db.insert(schema.routines).values(
    opaqueRow({
      id: ids.routine,
      userId,
      at,
      payload: {
        name: "Two-day rotation",
        notes: null,
        cadence_kind: "rotating",
        cadence_window: 2,
      },
    }),
  );
  await database.db.insert(schema.routineEntries).values([
    opaqueRow({
      id: ids.routineEntry,
      userId,
      at,
      payload: {
        routine_id: ids.routine,
        workout_template_id: ids.template,
        position: 0,
        slot: 1,
      },
    }),
    opaqueRow({
      id: ids.nextRoutineEntry,
      userId,
      at,
      payload: {
        routine_id: ids.routine,
        workout_template_id: ids.nextTemplate,
        position: 1,
        slot: 2,
      },
    }),
  ]);
  await database.db.insert(schema.loggedSets).values([
    loggedSetRow({
      id: ids.completedSet,
      userId,
      exerciseId: ids.historyExercise,
      at: new Date("2026-07-23T05:00:00.000Z"),
      performedAt: "2026-07-23T05:00:00.000Z",
      isCompleted: true,
      loadEntered: "142.5",
      repsEntered: "3",
    }),
    loggedSetRow({
      id: ids.incompleteSet,
      userId,
      exerciseId: ids.historyExercise,
      at: new Date("2026-07-24T05:00:00.000Z"),
      performedAt: "2026-07-24T05:00:00.000Z",
      isCompleted: false,
      loadEntered: "999",
      repsEntered: "1",
    }),
  ]);
}

function exerciseRow({ id, userId, categoryId, name, defaultLoadUnit, at }) {
  return opaqueRow({
    id,
    userId,
    at,
    payload: {
      library_origin: "user",
      name,
      dimension_ids: JSON.stringify(["load", "reps"]),
      default_load_unit: defaultLoadUnit,
      load_mode: "added",
      record_profile: "repMax",
      is_favorite: false,
      is_unilateral: false,
      uses_rpe: false,
      category_id: categoryId,
      equipment_ids: JSON.stringify(["barbell"]),
      notes: null,
    },
  });
}

function prescriptionPayload({ templateExerciseId, repeat, restAfter }) {
  return {
    template_exercise_id: templateExerciseId,
    mode: "copy-previous",
    position: 0,
    repeat,
    rest_after: restAfter,
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
  };
}

function loggedSetRow({
  id,
  userId,
  exerciseId,
  at,
  performedAt,
  isCompleted,
  loadEntered,
  repsEntered,
}) {
  return opaqueRow({
    id,
    userId,
    at,
    payload: {
      workout_id: `history-workout-${id}`,
      workout_started_at: performedAt,
      workout_timezone: "UTC",
      workout_local_date: performedAt.slice(0, 10),
      exercise_id: exerciseId,
      position: 0,
      planned_rest_after: null,
      performed_at: performedAt,
      is_completed: isCompleted,
      load_value: Number(loadEntered),
      load_unit: "kilogram",
      load_entered: loadEntered,
      reps_value: Number(repsEntered),
      reps_unit: "repetition",
      reps_entered: repsEntered,
      duration_value: null,
      duration_unit: null,
      duration_entered: null,
      distance_value: null,
      distance_unit: null,
      distance_entered: null,
      comment: null,
      side: null,
      rpe: null,
    },
  });
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

function createAgentKeyStore(userId) {
  return {
    async authenticateAgentApiKey(secret) {
      if (secret !== "prn_agent_secret") {
        return null;
      }
      return {
        userId,
        keyId: "agent-key-1",
        keyName: "Garage coach",
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
    },
  };
}

function postMaterialize(app, body) {
  return app.request("/agent/workout-templates/materialize", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_agent_secret",
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

function getAgent(app, path) {
  return app.request(path, {
    headers: { authorization: "Bearer prn_agent_secret" },
  });
}

function postMcp(app, body, headers = {}) {
  return app.request("/mcp", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      accept: "application/json, text/event-stream",
      ...headers,
    },
    body: JSON.stringify(body),
  });
}
