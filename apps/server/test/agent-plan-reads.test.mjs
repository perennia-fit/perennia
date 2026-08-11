import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { eq } from "drizzle-orm";

import {
  applyMigrations,
  createAgentMcpServer,
  createApp,
  createDatabaseClient,
  createDrizzleAgentPlanReadStore,
  deriveAgentRoutineUpNext,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

const skip = databaseUrl ? false : "DATABASE_URL is not set.";

test("server Up-next derivation matches the app's shared fixtures", async () => {
  const vector = JSON.parse(
    await readFile(
      new URL("../../../packages/golden-vectors/vectors/m34-routine-up-next.json", import.meta.url),
      "utf8"
    )
  );

  for (const vectorCase of vector.cases) {
    const input = vectorCase.input;
    const cadence =
      input.cadence.kind === "weekly"
        ? { kind: "weekly", window: null }
        : { kind: "rotating", window: input.cadence.window };
    const actual = deriveAgentRoutineUpNext({
      cadence,
      entries: input.entries.map((entry) => ({
        routineEntryId: entry.routineEntryId,
        workoutTemplateId: entry.workoutTemplateId,
        workoutTemplateName: entry.templateName,
        slot: entry.slot
      })),
      links: input.links.map((link) => ({
        workoutTemplateId: link.workoutTemplateId,
        slot: link.slot,
        sequence: link.sequence,
        workoutLocalDate: link.workoutLocalDate ?? null
      })),
      selectedDate: input.selectedDate
    });

    assert.deepEqual(portableSuggestion(actual), vectorCase.expected, vectorCase.name);
  }
});

test(
  "agent plan REST reads are tenant-isolated, projected, cursor-bounded, detail-capped, and derive Routine Up next from Template Links",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userA = `agent-plan-a-${randomUUID()}`;
    const userB = `agent-plan-b-${randomUUID()}`;
    const store = createDrizzleAgentPlanReadStore(database.db);
    const app = createPlanApp({ userId: userA, store });

    try {
      await seedUser(database, userA);
      await seedUser(database, userB);
      await seedPlan(database, userA, "a");
      await seedPlan(database, userB, "b");

      const firstPageResponse = await agentGet(app, "/agent/workout-templates?limit=1");
      assert.equal(firstPageResponse.status, 200);
      const firstPage = await firstPageResponse.json();
      assert.equal(firstPage.workoutTemplates.length, 1);
      assert.deepEqual(firstPage.fields, ["id", "name", "exerciseCount"]);
      assert.equal("notes" in firstPage.workoutTemplates[0], false);
      assert.ok(firstPage.nextCursor);
      assert.ok(firstPage.workoutTemplates.every((template) => template.id.startsWith("a-")));

      const secondPageResponse = await agentGet(
        app,
        `/agent/workout-templates?limit=1&cursor=${encodeURIComponent(
          firstPage.nextCursor
        )}&fields=id,name,notes,groupCount`
      );
      const secondPage = await secondPageResponse.json();
      assert.equal(secondPageResponse.status, 200);
      assert.equal(secondPage.workoutTemplates.length, 1);
      assert.notEqual(
        secondPage.workoutTemplates[0].id,
        firstPage.workoutTemplates[0].id
      );
      assert.deepEqual(secondPage.fields, ["id", "name", "notes", "groupCount"]);
      assert.equal("notes" in secondPage.workoutTemplates[0], true);

      const invalidCursor = await agentGet(
        app,
        "/agent/workout-templates?cursor=not-a-real-template"
      );
      assert.equal(invalidCursor.status, 400);
      assert.equal((await invalidCursor.json()).code, "agent_plan_invalid_cursor");

      const detailResponse = await agentGet(
        app,
        "/agent/workout-templates/a-template-am?componentLimit=2"
      );
      assert.equal(detailResponse.status, 200);
      const detail = (await detailResponse.json()).workoutTemplate;
      assert.equal(detail.componentLimit, 2);
      assert.equal(detail.componentsReturned, 2);
      assert.equal(detail.componentsTruncated, true);
      assert.equal(detail.exercises.length, 1);
      assert.equal(detail.exercises[0].prescriptions.length, 1);

      const routineResponse = await agentGet(
        app,
        "/agent/routines/a-routine?selectedDate=2026-07-06"
      );
      assert.equal(routineResponse.status, 200);
      const routine = (await routineResponse.json()).routine;
      assert.equal(routine.cadence.kind, "rotating");
      assert.equal(routine.slotLayout.length, 4);
      assert.deepEqual(
        routine.slotLayout.map((slot) => slot.entries.length),
        [1, 0, 2, 1]
      );
      // The latest linked Workout was an out-of-order materialization of slot
      // 4, so fact re-anchors the rotation and slot 1 is Up next.
      assert.equal(routine.upNext.slot, 1);
      assert.equal(routine.upNext.cards[0].workoutTemplateId, "a-template-am");

      const defaultDateRoutineResponse = await agentGet(
        app,
        "/agent/routines/a-routine"
      );
      assert.equal(defaultDateRoutineResponse.status, 200);
      const defaultDateRoutine = (await defaultDateRoutineResponse.json()).routine;
      assert.match(defaultDateRoutine.upNext.selectedDate, /^\d{4}-\d{2}-\d{2}$/);

      const truncatedRoutineResponse = await agentGet(
        app,
        "/agent/routines/a-routine?selectedDate=2026-07-06&componentLimit=1"
      );
      const truncatedRoutine = (await truncatedRoutineResponse.json()).routine;
      assert.equal(truncatedRoutine.entries.length, 1);
      assert.equal(truncatedRoutine.entriesTruncated, true);
      assert.deepEqual(
        truncatedRoutine.slotLayout.map((slot) => slot.entries.length),
        [1, 0, 2, 1]
      );

      const halfDoneResponse = await agentGet(
        app,
        "/agent/routines/a-multi-routine?selectedDate=2026-07-06"
      );
      const halfDone = (await halfDoneResponse.json()).routine;
      assert.equal(halfDone.upNext.slot, 2);
      assert.deepEqual(
        halfDone.upNext.cards.map((card) => [card.workoutTemplateId, card.isDone]),
        [
          ["a-template-pm", false],
          ["a-template-am", true]
        ]
      );

      const binaryOrderedResponse = await agentGet(
        app,
        "/agent/routines/a-binary-routine?selectedDate=2026-07-06"
      );
      const binaryOrdered = (await binaryOrderedResponse.json()).routine;
      assert.equal(binaryOrdered.upNext.slot, 1);

      const routines = await (await agentGet(app, "/agent/routines?limit=100")).json();
      assert.ok(routines.routines.length >= 2);
      assert.ok(routines.routines.every((routineItem) => routineItem.id.startsWith("a-")));

      const missing = await agentGet(app, "/agent/workout-templates/b-template-am");
      assert.equal(missing.status, 404);
      assert.equal((await missing.json()).code, "agent_workout_template_not_found");

      const archivedTemplate = await agentGet(
        app,
        "/agent/workout-templates/a-archived-template"
      );
      assert.equal(archivedTemplate.status, 404);
      assert.equal(
        (
          await agentGet(
            app,
            "/agent/workout-templates/a-archived-template?includeArchived=true"
          )
        ).status,
        200
      );

      await database.db
        .update(schema.workoutTemplates)
        .set({ deletedAt: new Date("2026-07-06T09:00:00.000Z") })
        .where(eq(schema.workoutTemplates.id, firstPage.nextCursor));
      const staleCursor = await agentGet(
        app,
        `/agent/workout-templates?limit=1&cursor=${encodeURIComponent(
          firstPage.nextCursor
        )}`
      );
      assert.equal(staleCursor.status, 400);
      assert.equal((await staleCursor.json()).code, "agent_plan_invalid_cursor");

      const archivedRoutine = await agentGet(app, "/agent/routines/a-archived-routine");
      assert.equal(archivedRoutine.status, 404);
      assert.equal(
        (
          await agentGet(
            app,
            "/agent/routines/a-archived-routine?includeArchived=true"
          )
        ).status,
        200
      );
    } finally {
      await database.close();
    }
  }
);

test("plan MCP tools mirror the REST store and require transport auth, not an apiKey argument", async () => {
  const calls = [];
  const planStore = {
    async listWorkoutTemplates(input) {
      calls.push(["listWorkoutTemplates", input]);
      return {
        workoutTemplates: [],
        fields: ["id", "name", "exerciseCount"],
        limit: 20,
        nextCursor: null,
        totalMatched: 0
      };
    },
    async getWorkoutTemplate() {
      throw new Error("not used");
    },
    async listRoutines() {
      throw new Error("not used");
    },
    async getRoutine(input) {
      calls.push(["getRoutine", input]);
      return routineFixture(input.routineId, input.query.selectedDate);
    }
  };
  const agentApiKeyStore = createAgentKeyStore("user-1");
  const app = createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore,
    agentPlanReadStore: planStore,
    createMcpServer: () =>
      createAgentMcpServer({
        agentApiKeyStore,
        agentPlanReadStore: planStore,
        logger: { info() {}, error() {} }
      })
  });

  const toolsResponse = await postMcp(
    app,
    { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} },
    { authorization: "Bearer prn_agent_secret" }
  );
  const tools = (await toolsResponse.json()).result.tools;
  const routineTool = tools.find((tool) => tool.name === "agent_get_routine");
  assert.ok(routineTool);
  assert.equal("apiKey" in routineTool.inputSchema.properties, false);
  assert.ok(tools.some((tool) => tool.name === "agent_list_workout_templates"));
  assert.ok(tools.some((tool) => tool.name === "agent_get_workout_template"));
  assert.ok(tools.some((tool) => tool.name === "agent_list_routines"));

  const callResponse = await postMcp(
    app,
    {
      jsonrpc: "2.0",
      id: 2,
      method: "tools/call",
      params: {
        name: "agent_get_routine",
        arguments: {
          params: { routineId: "routine-1" },
          query: { selectedDate: "2026-07-06" }
        }
      }
    },
    { authorization: "Bearer prn_agent_secret" }
  );
  assert.equal(callResponse.status, 200);
  const callBody = await callResponse.json();
  assert.equal(callBody.result.isError, undefined);
  assert.equal(callBody.result.structuredContent.routine.id, "routine-1");
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], "getRoutine");
  assert.equal(calls[0][1].userId, "user-1");
});

function portableSuggestion(suggestion) {
  if (suggestion === null) {
    return null;
  }
  return {
    slot: suggestion.slot,
    cards: suggestion.cards.map((card) => ({
      routineEntryId: card.routineEntryId,
      workoutTemplateId: card.workoutTemplateId,
      templateName: card.workoutTemplateName,
      slot: card.slot,
      isDone: card.isDone
    }))
  };
}

function createPlanApp({ userId, store }) {
  return createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore(userId),
    agentPlanReadStore: store
  });
}

function createAgentKeyStore(userId) {
  return {
    async authenticateAgentApiKey(secret) {
      if (secret !== "prn_agent_secret") {
        return null;
      }
      return { userId, keyId: "agent-key-1", keyName: "Plan coach" };
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

function agentGet(app, path) {
  return app.request(path, {
    headers: { authorization: "Bearer prn_agent_secret" }
  });
}

async function seedUser(database, userId) {
  await database.db.insert(schema.user).values({
    id: userId,
    name: "Agent Plan User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
}

async function seedPlan(database, userId, prefix) {
  const at = new Date("2026-07-06T08:00:00.000Z");
  const templates = [
    ["template-am", "AM Lift"],
    ["template-pm", "PM Conditioning"],
    ["template-day-3", "Day 3"],
    ["template-day-4", "Day 4"]
  ];
  await database.db.insert(schema.workoutTemplates).values(
    templates.map(([suffix, name]) =>
      opaqueRow({
        id: `${prefix}-${suffix}`,
        userId,
        at,
        payload: { name, notes: `${name} notes` }
      })
    )
  );
  await database.db.insert(schema.workoutTemplates).values(
    opaqueRow({
      id: `${prefix}-archived-template`,
      userId,
      at,
      deletedAt: at,
      payload: { name: "Archived Template", notes: null }
    })
  );
  await database.db.insert(schema.templateExercises).values([
    opaqueRow({
      id: `${prefix}-exercise-1`,
      userId,
      at,
      payload: {
        workout_template_id: `${prefix}-template-am`,
        exercise_id: `${prefix}-catalog-exercise`,
        position: 0,
        note: null
      }
    }),
    opaqueRow({
      id: `${prefix}-exercise-2`,
      userId,
      at,
      payload: {
        workout_template_id: `${prefix}-template-am`,
        exercise_id: `${prefix}-catalog-exercise-2`,
        position: 1,
        note: null
      }
    })
  ]);
  await database.db.insert(schema.prescriptions).values(
    [1, 2].map((number, index) =>
      opaqueRow({
        id: `${prefix}-prescription-${number}`,
        userId,
        at,
        payload: {
          template_exercise_id: `${prefix}-exercise-${number}`,
          mode: "fixed",
          position: index,
          repeat: 1,
          rest_after: 60,
          load_value: 60,
          load_unit: "kg",
          load_entered: "60",
          reps_value: 5,
          reps_unit: "reps",
          reps_entered: "5",
          duration_value: null,
          duration_unit: null,
          duration_entered: null,
          distance_value: null,
          distance_unit: null,
          distance_entered: null
        }
      })
    )
  );
  await database.db.insert(schema.templateGroups).values(
    opaqueRow({
      id: `${prefix}-group-1`,
      userId,
      at,
      payload: {
        workout_template_id: `${prefix}-template-am`,
        name: "Superset",
        color_hex: "#FF5733",
        rounds: 3,
        position: 0
      }
    })
  );
  await database.db.insert(schema.templateGroupMembers).values(
    [1, 2].map((number, index) =>
      opaqueRow({
        id: `${prefix}-member-${number}`,
        userId,
        at,
        payload: {
          group_id: `${prefix}-group-1`,
          template_exercise_id: `${prefix}-exercise-${number}`,
          position: index
        }
      })
    )
  );
  await database.db.insert(schema.routines).values([
    opaqueRow({
      id: `${prefix}-routine`,
      userId,
      at,
      payload: {
        name: "Four-slot rotation",
        notes: null,
        cadence_kind: "rotating",
        cadence_window: 4
      }
    }),
    opaqueRow({
      id: `${prefix}-multi-routine`,
      userId,
      at,
      payload: {
        name: "Two-a-day",
        notes: null,
        cadence_kind: "rotating",
        cadence_window: 3
      }
    }),
    opaqueRow({
      id: `${prefix}-binary-routine`,
      userId,
      at,
      payload: {
        name: "Binary link order",
        notes: null,
        cadence_kind: "rotating",
        cadence_window: 2
      }
    }),
    opaqueRow({
      id: `${prefix}-archived-routine`,
      userId,
      at,
      deletedAt: at,
      payload: {
        name: "Archived Routine",
        notes: null,
        cadence_kind: null,
        cadence_window: null
      }
    })
  ]);
  await database.db
    .insert(schema.routineEntries)
    .values([
      routineEntry(prefix, userId, at, "entry-1", "routine", "template-am", 0, 1),
      routineEntry(prefix, userId, at, "entry-3a", "routine", "template-day-3", 1, 3),
      routineEntry(prefix, userId, at, "entry-3b", "routine", "template-pm", 2, 3),
      routineEntry(prefix, userId, at, "entry-4", "routine", "template-day-4", 3, 4),
      routineEntry(prefix, userId, at, "multi-am", "multi-routine", "template-am", 0, 2),
      routineEntry(prefix, userId, at, "multi-pm", "multi-routine", "template-pm", 1, 2),
      routineEntry(prefix, userId, at, "binary-am", "binary-routine", "template-am", 0, 1),
      routineEntry(prefix, userId, at, "binary-pm", "binary-routine", "template-pm", 1, 2)
    ]);
  await database.db
    .insert(schema.templateLinks)
    .values([
      templateLink(prefix, userId, at, "000-link-1", "routine", "template-am", 1),
      templateLink(prefix, userId, at, "999-link-4", "routine", "template-day-4", 4),
      templateLink(prefix, userId, at, "999-multi-am", "multi-routine", "template-am", 2),
      templateLink(prefix, userId, at, "binary-link-", "binary-routine", "template-am", 1),
      templateLink(prefix, userId, at, "binary-link_", "binary-routine", "template-pm", 2)
    ]);
}

function routineEntry(prefix, userId, at, id, routine, template, position, slot) {
  return opaqueRow({
    id: `${prefix}-${id}`,
    userId,
    at,
    payload: {
      routine_id: `${prefix}-${routine}`,
      workout_template_id: `${prefix}-${template}`,
      position,
      slot
    }
  });
}

function templateLink(prefix, userId, at, id, routine, template, slot) {
  return opaqueRow({
    id: `${prefix}-${id}`,
    userId,
    at,
    payload: {
      workout_id: `${prefix}-workout-${id}`,
      workout_template_id: `${prefix}-${template}`,
      routine_id: `${prefix}-${routine}`,
      slot,
      workout_local_date: "2026-07-06",
      workout_deleted_at: null
    }
  });
}

function opaqueRow({ id, userId, at, payload, deletedAt = null }) {
  return {
    id,
    userId,
    deviceId: "device-a",
    payload: {
      id,
      ...payload,
      updated_at: at.toISOString(),
      deleted_at: deletedAt?.toISOString() ?? null
    },
    updatedAt: at,
    deletedAt,
    receivedAt: at
  };
}

function routineFixture(id, selectedDate) {
  return {
    routine: {
      id,
      name: "Fixture Routine",
      notes: null,
      cadence: { kind: "weekly", window: null },
      entries: [],
      slotLayout: Array.from({ length: 7 }, (_, index) => ({
        slot: index + 1,
        entries: []
      })),
      upNext: null,
      entryLimit: 100,
      entryCount: 0,
      entriesReturned: 0,
      entriesTruncated: false,
      updatedAt: "2026-07-06T08:00:00.000Z",
      deletedAt: null
    },
    selectedDate
  };
}

function postMcp(app, body, headers = {}) {
  return app.request("/mcp", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      accept: "application/json, text/event-stream",
      ...headers
    },
    body: JSON.stringify(body)
  });
}
