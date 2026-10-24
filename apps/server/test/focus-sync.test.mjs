import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { eq } from "drizzle-orm";

import {
  createAgentMcpServer,
  createApp,
  createInMemoryAgentCatalogStore,
  createMigratedServerApp,
  mergeAgentFocuses,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error(
    "DATABASE_URL must be set for server Postgres integration tests."
  );
}

const skip = databaseUrl ? false : "DATABASE_URL is not set.";

// Starter Focus ids are fixed and shared with every device's bundled seed.
const WEIGHTS = "01910000-0000-7000-8000-000000000401";
const ENDURANCE = "01910000-0000-7000-8000-000000000402";
const FUNCTIONAL = "01910000-0000-7000-8000-000000000403";
const CALISTHENICS = "01910000-0000-7000-8000-000000000404";
const MOBILITY = "01910000-0000-7000-8000-000000000405";
// "4-count burpees" in the bundled Platform Library (reps-only).
const PLATFORM_BURPEES = "01910000-0000-7000-8000-000000200997";

test("starter Focuses merge with user rows: renames and reorders override, archives hide, new rows join", () => {
  const merged = mergeAgentFocuses([
    { id: ENDURANCE, name: "Cardio", sortOrder: 9, deleted: false },
    { id: MOBILITY, name: "Mobility", sortOrder: 4, deleted: true },
    { id: "user-focus-yoga", name: "Yoga", sortOrder: 1, deleted: false },
    { id: "user-focus-gone", name: "Gone", sortOrder: 0, deleted: true }
  ]);

  assert.deepEqual(merged, [
    { id: WEIGHTS, name: "Weights", sortOrder: 0, starter: true },
    { id: "user-focus-yoga", name: "Yoga", sortOrder: 1, starter: false },
    { id: FUNCTIONAL, name: "Functional", sortOrder: 2, starter: true },
    { id: CALISTHENICS, name: "Calisthenics", sortOrder: 3, starter: true },
    { id: ENDURANCE, name: "Cardio", sortOrder: 9, starter: true }
  ]);
});

test("GET /agent/focuses and agent_list_focuses return the caller's merged Focuses only", async () => {
  const store = createInMemoryAgentCatalogStore(
    [],
    [],
    [
      {
        ownerUserId: "user-1",
        id: WEIGHTS,
        name: "Strength",
        sortOrder: 0,
        deleted: false
      },
      {
        ownerUserId: "user-2",
        id: "other-user-focus",
        name: "Not yours",
        sortOrder: 0,
        deleted: false
      }
    ]
  );
  const logger = { info() {}, error() {} };
  const agentApiKeyStore = createAgentKeyStore("user-1");
  const app = createApp({
    logger,
    agentApiKeyStore,
    agentCatalogStore: store,
    createMcpServer: () =>
      createAgentMcpServer({ agentApiKeyStore, agentCatalogStore: store, logger })
  });

  const response = await app.request("/agent/focuses", {
    headers: { authorization: "Bearer prn_agent_secret" }
  });
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.deepEqual(
    body.focuses.map((focus) => [focus.id, focus.name]),
    [
      [WEIGHTS, "Strength"],
      [ENDURANCE, "Endurance"],
      [FUNCTIONAL, "Functional"],
      [CALISTHENICS, "Calisthenics"],
      [MOBILITY, "Mobility"]
    ]
  );

  const unauthorized = await app.request("/agent/focuses");
  assert.equal(unauthorized.status, 401);

  const mcpResponse = await app.request("/mcp", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_agent_secret",
      "content-type": "application/json",
      accept: "application/json, text/event-stream"
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "tools/call",
      params: { name: "agent_list_focuses", arguments: {} }
    })
  });
  assert.equal(mcpResponse.status, 200);
  const mcpBody = await mcpResponse.json();
  assert.equal(mcpBody.result.isError, undefined);
  assert.deepEqual(mcpBody.result.structuredContent, body);
});

test("the exercise list filters by Focus id or name and exposes focusIds", async () => {
  const store = createInMemoryAgentCatalogStore(
    [
      exerciseFixture({ id: "pull-up", name: "Pull-up", focusIds: [CALISTHENICS] }),
      exerciseFixture({ id: "row", name: "Row", focusIds: [ENDURANCE, WEIGHTS] }),
      exerciseFixture({ id: "legacy", name: "Legacy" })
    ],
    [],
    [
      {
        ownerUserId: "user-1",
        id: ENDURANCE,
        name: "Cardio",
        sortOrder: 1,
        deleted: false
      }
    ]
  );

  const byId = await store.listExercises({
    userId: "user-1",
    focus: CALISTHENICS,
    activeOnly: true,
    limit: 50,
    fields: ["focusIds"]
  });
  assert.deepEqual(
    byId.exercises.map((exercise) => [exercise.id, exercise.focusIds]),
    [["pull-up", [CALISTHENICS]]]
  );

  // A renamed starter is reachable by the user's name for it.
  const byName = await store.listExercises({
    userId: "user-1",
    focus: "cardio",
    activeOnly: true,
    limit: 50,
    fields: []
  });
  assert.deepEqual(byName.exercises.map((exercise) => exercise.id), ["row"]);

  const legacy = await store.getExerciseById({
    userId: "user-1",
    exerciseId: "legacy"
  });
  assert.deepEqual(legacy.focusIds, []);
});

test(
  "Focuses round-trip as tenant-isolated LWW rows, archive as tombstones, and sort before Exercises",
  { skip },
  async () => {
    const serverApp = await migratedApp();
    try {
      const userA = await createSignedInUser(serverApp);
      const userB = await createSignedInUser(serverApp);
      const userFocusId = randomUUID();
      const updatedAt = "2025-06-30T08:00:00.000Z";

      const push = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "focuses",
        changes: [
          focusChange(userFocusId, "Climbing", 5, updatedAt),
          focusChange(ENDURANCE, "Cardio", 1, updatedAt)
        ]
      });
      assert.equal(push.status, 200);
      assert.deepEqual(
        new Set((await push.json()).accepted),
        new Set([userFocusId, ENDURANCE])
      );

      // Another account cannot overwrite user A's row under the same id.
      const hostile = await syncPush(serverApp.app, userB.sessionToken, {
        deviceId: "device-b",
        entity: "focuses",
        changes: [focusChange(userFocusId, "Hijacked", 0, "2025-07-01T00:00:00.000Z")]
      });
      assert.equal(hostile.status, 200);

      const pulled = await pullAll(serverApp.app, userA.sessionToken);
      const pulledFocus = pulled.find(
        (change) => change.entity === "focuses" && change.id === userFocusId
      );
      assert.ok(pulledFocus);
      assert.equal(pulledFocus.payload.name, "Climbing");
      assert.equal(pulledFocus.payload.sort_order, 5);
      assert.equal(pulledFocus.deletedAt, null);
      assert.equal(
        (await pullAll(serverApp.app, userB.sessionToken)).some(
          (change) => change.entity === "focuses" && change.payload.name === "Climbing"
        ),
        false
      );

      // Archive is the ordinary tombstone; snapshot pulls omit it.
      const archivedAt = "2025-06-30T09:00:00.000Z";
      const archive = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "focuses",
        changes: [
          {
            ...focusChange(userFocusId, "Climbing", 5, archivedAt),
            deletedAt: archivedAt,
            payload: {
              ...focusChange(userFocusId, "Climbing", 5, archivedAt).payload,
              deleted_at: archivedAt
            }
          }
        ]
      });
      assert.equal(archive.status, 200);
      const afterArchive = await pullAll(serverApp.app, userA.sessionToken);
      const tombstone = afterArchive.find(
        (change) => change.entity === "focuses" && change.id === userFocusId
      );
      assert.equal(tombstone.deletedAt, archivedAt);
      const snapshot = await pullAll(serverApp.app, userA.sessionToken, "snapshot");
      assert.equal(
        snapshot.some((change) => change.id === userFocusId),
        false
      );

      // GET /agent/focuses merges the synced rows over the starter set.
      const agentSecret = await createAgentKey(serverApp, userA.sessionToken);
      const focusesResponse = await agentGet(serverApp.app, agentSecret, "/agent/focuses");
      assert.equal(focusesResponse.status, 200);
      const { focuses } = await focusesResponse.json();
      assert.equal(focuses.find((focus) => focus.id === ENDURANCE).name, "Cardio");
      assert.equal(focuses.some((focus) => focus.id === userFocusId), false);
      assert.equal(focuses.length, 5);

      // Same receive instant: category, then Focus, then Exercise.
      const db = serverApp.database.db;
      const sameInstant = new Date("2025-06-30T10:00:00.000Z");
      const categoryId = randomUUID();
      const focusId = randomUUID();
      const exerciseId = randomUUID();
      const owner = await createSignedInUser(serverApp);
      for (const [table, id, payload] of [
        [schema.exercises, exerciseId, { id: exerciseId, name: "Rank", focus_ids: JSON.stringify([focusId]) }],
        [schema.focuses, focusId, { id: focusId, name: "Rank focus", sort_order: 0 }],
        [schema.exerciseCategories, categoryId, { id: categoryId, name: "Rank category" }]
      ]) {
        await db.insert(table).values({
          id,
          userId: owner.userId,
          deviceId: "device-rank",
          payload: { ...payload, updated_at: sameInstant.toISOString(), deleted_at: null },
          updatedAt: sameInstant,
          deletedAt: null,
          receivedAt: sameInstant
        });
      }
      const ranked = await pullAll(serverApp.app, owner.sessionToken);
      assert.deepEqual(
        ranked.map((change) => change.entity),
        ["exercise_categories", "focuses", "exercises"]
      );
      // focus_ids rides the Exercise payload verbatim, JSON-encoded.
      assert.equal(ranked[2].payload.focus_ids, JSON.stringify([focusId]));
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "agent Workout writes set, validate, and carry through a device-set focus_id",
  { skip },
  async () => {
    const serverApp = await migratedApp();
    try {
      const user = await createSignedInUser(serverApp);
      const agentSecret = await createAgentKey(serverApp, user.sessionToken);
      const workoutId = randomUUID();
      const setId = randomUUID();
      const startedAt = "2026-06-24T05:00:00.000Z";

      // The device logs the Workout under Calisthenics.
      const devicePush = await syncPush(serverApp.app, user.sessionToken, {
        deviceId: "device-a",
        entity: "workout_sessions",
        changes: [
          {
            id: workoutId,
            payload: {
              id: workoutId,
              started_at: startedAt,
              timezone: "Australia/Brisbane",
              local_date: "2026-06-24",
              ended_at: null,
              comment: null,
              focus_id: CALISTHENICS,
              updated_at: startedAt,
              deleted_at: null
            },
            updatedAt: startedAt,
            deletedAt: null
          }
        ]
      });
      assert.equal(devicePush.status, 200);

      // An agent edit that never mentions Focus keeps it.
      const edit = await agentPost(serverApp.app, agentSecret, "/agent/workouts/batch-write", {
        idempotencyKey: `focus-carry-${randomUUID()}`,
        workout: workoutBody(workoutId, startedAt, { comment: "Felt strong" }),
        sets: [setBody(setId)]
      });
      assert.equal(edit.status, 200, await edit.clone().text());
      assert.equal(await storedWorkoutFocus(serverApp, workoutId), CALISTHENICS);
      const detail = await agentGet(serverApp.app, agentSecret, `/agent/workouts/${workoutId}`);
      assert.equal(detail.status, 200);
      assert.equal((await detail.json()).workout.focusId, CALISTHENICS);
      const list = await agentGet(serverApp.app, agentSecret, "/agent/workouts?fields=focusId");
      assert.equal(
        (await list.json()).workouts.find((workout) => workout.id === workoutId).focusId,
        CALISTHENICS
      );

      // An unknown Focus is a hard reject; nothing is written.
      const rejected = await agentPost(serverApp.app, agentSecret, "/agent/workouts/batch-write", {
        idempotencyKey: `focus-missing-${randomUUID()}`,
        workout: workoutBody(workoutId, startedAt, { focusId: randomUUID() }),
        sets: [setBody(setId)]
      });
      assert.equal(rejected.status, 422);
      const rejectedBody = await rejected.json();
      assert.ok(
        rejectedBody.errors.some(
          (issue) => issue.rule === "focus_not_found" && issue.field === "workout.focusId"
        )
      );
      assert.equal(await storedWorkoutFocus(serverApp, workoutId), CALISTHENICS);

      // An explicit starter Focus sets it; an explicit null clears it.
      const setFocus = await agentPost(serverApp.app, agentSecret, "/agent/workouts/batch-write", {
        idempotencyKey: `focus-set-${randomUUID()}`,
        workout: workoutBody(workoutId, startedAt, { focusId: WEIGHTS }),
        sets: [setBody(setId)]
      });
      assert.equal(setFocus.status, 200);
      assert.equal(await storedWorkoutFocus(serverApp, workoutId), WEIGHTS);
      const cleared = await agentPost(serverApp.app, agentSecret, "/agent/workouts/batch-write", {
        idempotencyKey: `focus-clear-${randomUUID()}`,
        workout: workoutBody(workoutId, startedAt, { focusId: null }),
        sets: [setBody(setId)]
      });
      assert.equal(cleared.status, 200);
      assert.equal(await storedWorkoutFocus(serverApp, workoutId), null);

      // A Focus the user archived is no longer a valid reference.
      const archivedAt = "2025-06-30T09:00:00.000Z";
      await syncPush(serverApp.app, user.sessionToken, {
        deviceId: "device-a",
        entity: "focuses",
        changes: [
          {
            ...focusChange(MOBILITY, "Mobility", 4, archivedAt),
            deletedAt: archivedAt
          }
        ]
      });
      const archivedRef = await agentPost(serverApp.app, agentSecret, "/agent/workouts/batch-write", {
        idempotencyKey: `focus-archived-${randomUUID()}`,
        workout: workoutBody(workoutId, startedAt, { focusId: MOBILITY }),
        sets: [setBody(setId)]
      });
      assert.equal(archivedRef.status, 422);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "Workout Templates carry focusId through plan-tree writes and materialize it onto the new Workout",
  { skip },
  async () => {
    const serverApp = await migratedApp();
    try {
      const user = await createSignedInUser(serverApp);
      const agentSecret = await createAgentKey(serverApp, user.sessionToken);
      const templateId = randomUUID();
      const templateExerciseId = randomUUID();

      const create = await planTreeWrite(serverApp.app, agentSecret, {
        idempotencyKey: `focus-template-${randomUUID()}`,
        workoutTemplates: [{ id: templateId, name: "Bodyweight day", focusId: CALISTHENICS }],
        templateExercises: [
          {
            id: templateExerciseId,
            workoutTemplateId: templateId,
            exerciseId: PLATFORM_BURPEES,
            position: 0
          }
        ],
        prescriptions: [
          {
            id: randomUUID(),
            templateExerciseId,
            mode: "fixed",
            position: 0,
            repeat: 2,
            values: { reps: { entered: "10", unit: "repetition" } }
          }
        ]
      });
      assert.equal(create.status, 200, await create.clone().text());
      assert.equal(await storedTemplateFocus(serverApp, templateId), CALISTHENICS);

      // A rename that omits focusId keeps the stored Focus.
      const rename = await planTreeWrite(serverApp.app, agentSecret, {
        idempotencyKey: `focus-template-rename-${randomUUID()}`,
        workoutTemplates: [{ id: templateId, name: "Bodyweight A" }]
      });
      assert.equal(rename.status, 200, await rename.clone().text());
      assert.equal(await storedTemplateFocus(serverApp, templateId), CALISTHENICS);

      const detail = await agentGet(
        serverApp.app,
        agentSecret,
        `/agent/workout-templates/${templateId}`
      );
      assert.equal(detail.status, 200);
      assert.equal((await detail.json()).workoutTemplate.focusId, CALISTHENICS);
      const templates = await agentGet(
        serverApp.app,
        agentSecret,
        "/agent/workout-templates?fields=focusId"
      );
      assert.equal(
        (await templates.json()).workoutTemplates.find((row) => row.id === templateId)
          .focusId,
        CALISTHENICS
      );

      const unknown = await planTreeWrite(serverApp.app, agentSecret, {
        idempotencyKey: `focus-template-unknown-${randomUUID()}`,
        workoutTemplates: [{ id: templateId, name: "Bodyweight A", focusId: "no-such-focus" }]
      });
      assert.equal(unknown.status, 422);
      assert.ok(
        (await unknown.json()).errors.some((issue) => issue.rule === "focus_not_found")
      );

      const materialize = await agentPost(
        serverApp.app,
        agentSecret,
        "/agent/workout-templates/materialize",
        {
          idempotencyKey: `focus-materialize-${randomUUID()}`,
          workoutTemplateId: templateId,
          routineId: null,
          slot: null,
          startedAt: "2026-06-24T05:00:00.000Z",
          timezone: "Australia/Brisbane"
        }
      );
      assert.equal(materialize.status, 200, await materialize.clone().text());
      const { workoutId } = await materialize.json();
      assert.equal(await storedWorkoutFocus(serverApp, workoutId), CALISTHENICS);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "agent Exercise catalog writes validate focusIds and keep them when omitted",
  { skip },
  async () => {
    const serverApp = await migratedApp();
    try {
      const user = await createSignedInUser(serverApp);
      const agentSecret = await createAgentKey(serverApp, user.sessionToken);
      const userFocusId = randomUUID();
      const updatedAt = "2025-06-30T08:00:00.000Z";
      await syncPush(serverApp.app, user.sessionToken, {
        deviceId: "device-a",
        entity: "focuses",
        changes: [focusChange(userFocusId, "Climbing", 5, updatedAt)]
      });
      const exerciseId = randomUUID();

      const categoryId = randomUUID();
      const create = await agentPost(serverApp.app, agentSecret, "/agent/exercises/batch-write", {
        idempotencyKey: `focus-exercise-${randomUUID()}`,
        categories: [{ id: categoryId, name: "Fingers" }],
        exercises: [
          {
            id: exerciseId,
            name: "Campus board hangs",
            categoryId,
            dimensions: ["duration"],
            focusIds: [userFocusId, CALISTHENICS]
          }
        ]
      });
      assert.equal(create.status, 200, await create.clone().text());
      assert.equal(
        await storedExerciseFocusIds(serverApp, exerciseId),
        JSON.stringify([userFocusId, CALISTHENICS])
      );

      const rename = await agentPost(serverApp.app, agentSecret, "/agent/exercises/batch-write", {
        idempotencyKey: `focus-exercise-rename-${randomUUID()}`,
        exercises: [{ id: exerciseId, name: "Hangboard hangs", categoryId, dimensions: ["duration"] }]
      });
      assert.equal(rename.status, 200);
      assert.equal(
        await storedExerciseFocusIds(serverApp, exerciseId),
        JSON.stringify([userFocusId, CALISTHENICS])
      );

      const list = await agentGet(
        serverApp.app,
        agentSecret,
        `/agent/exercises?focus=climbing&fields=focusIds&limit=100`
      );
      assert.equal(list.status, 200);
      assert.deepEqual(
        (await list.json()).exercises.map((exercise) => [exercise.id, exercise.focusIds]),
        [[exerciseId, [userFocusId, CALISTHENICS]]]
      );

      const unknown = await agentPost(serverApp.app, agentSecret, "/agent/exercises/batch-write", {
        idempotencyKey: `focus-exercise-unknown-${randomUUID()}`,
        exercises: [
          { id: exerciseId, name: "Hangboard hangs", categoryId, dimensions: ["duration"], focusIds: ["nope"] }
        ]
      });
      assert.equal(unknown.status, 422);
      assert.ok(
        (await unknown.json()).errors.some((issue) => issue.rule === "focus_not_found")
      );

      const cleared = await agentPost(serverApp.app, agentSecret, "/agent/exercises/batch-write", {
        idempotencyKey: `focus-exercise-clear-${randomUUID()}`,
        exercises: [
          { id: exerciseId, name: "Hangboard hangs", categoryId, dimensions: ["duration"], focusIds: [] }
        ]
      });
      assert.equal(cleared.status, 200);
      assert.equal(await storedExerciseFocusIds(serverApp, exerciseId), "[]");
    } finally {
      await serverApp.database.close();
    }
  }
);

function exerciseFixture({ id, name, focusIds }) {
  return {
    id,
    library: "user",
    ownerUserId: "user-1",
    name,
    category: { id: "strength", name: "Strength" },
    dimensions: ["load", "reps"],
    equipment: [],
    ...(focusIds === undefined ? {} : { focusIds }),
    loadMode: "added",
    recordProfile: "repMax",
    favorite: false,
    active: true,
    shadowedPlatformExerciseId: null
  };
}

function focusChange(id, name, sortOrder, updatedAt) {
  return {
    id,
    payload: {
      id,
      name,
      sort_order: sortOrder,
      updated_at: updatedAt,
      deleted_at: null
    },
    updatedAt,
    deletedAt: null
  };
}

function workoutBody(id, startedAt, extra = {}) {
  return {
    id,
    startedAt,
    endedAt: null,
    timezone: "Australia/Brisbane",
    comment: null,
    ...extra
  };
}

function setBody(id) {
  return {
    id,
    exerciseName: "4-count burpees",
    position: 0,
    values: { reps: { entered: "10", unit: "repetition" } },
    updatedAt: "2026-06-24T05:00:00.000Z"
  };
}

async function storedWorkoutFocus(serverApp, workoutId) {
  const [row] = await serverApp.database.db
    .select({ payload: schema.workoutSessions.payload })
    .from(schema.workoutSessions)
    .where(eqId(schema.workoutSessions, workoutId));
  return row.payload.focus_id ?? null;
}

async function storedTemplateFocus(serverApp, templateId) {
  const [row] = await serverApp.database.db
    .select({ payload: schema.workoutTemplates.payload })
    .from(schema.workoutTemplates)
    .where(eqId(schema.workoutTemplates, templateId));
  return row.payload.focus_id ?? null;
}

async function storedExerciseFocusIds(serverApp, exerciseId) {
  const [row] = await serverApp.database.db
    .select({ payload: schema.exercises.payload })
    .from(schema.exercises)
    .where(eqId(schema.exercises, exerciseId));
  return row.payload.focus_ids;
}

function eqId(table, id) {
  return eq(table.id, id);
}

async function migratedApp() {
  return createMigratedServerApp({
    databaseUrl,
    logger: { info() {}, error() {} },
    auth: {
      baseUrl: "http://localhost",
      secret: "test-secret-at-least-thirty-two-characters",
      emailSender: null
    },
    rateLimit: false
  });
}

async function createAgentKey(serverApp, sessionToken) {
  const response = await serverApp.app.request("/agent/api-keys", {
    method: "POST",
    headers: {
      authorization: `Bearer ${sessionToken}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({ name: "Focus coach" })
  });
  assert.equal(response.status, 201);
  return (await response.json()).secret;
}

async function createSignedInUser(serverApp) {
  const userId = `user-${randomUUID()}`;
  const sessionToken = `session-${randomUUID()}`;
  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: "Focus Sync User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
  await serverApp.database.db.insert(schema.session).values({
    id: `session-row-${randomUUID()}`,
    token: sessionToken,
    userId,
    expiresAt: new Date("2099-01-01T00:00:00.000Z")
  });
  return { userId, sessionToken };
}

function createAgentKeyStore(userId) {
  return {
    async authenticateAgentApiKey(secret) {
      return secret === "prn_agent_secret"
        ? { userId, keyId: "agent-key-1", keyName: "Focus coach" }
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
    }
  };
}

function syncPush(app, sessionToken, body) {
  return app.request("/sync/push", {
    method: "POST",
    headers: {
      authorization: `Bearer ${sessionToken}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({ protocolVersion: 1, ...body })
  });
}

function agentPost(app, agentSecret, path, body) {
  return app.request(path, {
    method: "POST",
    headers: {
      authorization: `Bearer ${agentSecret}`,
      "content-type": "application/json"
    },
    body: JSON.stringify(body)
  });
}

function agentGet(app, agentSecret, path) {
  return app.request(path, {
    headers: { authorization: `Bearer ${agentSecret}` }
  });
}

function planTreeWrite(app, agentSecret, body) {
  const keys = [
    "workoutTemplates",
    "templateExercises",
    "prescriptions",
    "templateGroups",
    "templateGroupMembers",
    "routines",
    "routineEntries"
  ];
  return agentPost(app, agentSecret, "/agent/plan-tree/batch-write", {
    ...body,
    expectedCounts: Object.fromEntries(
      keys.map((key) => [key, (body[key] ?? []).length])
    )
  });
}

async function pullAll(app, sessionToken, mode = "delta") {
  const changes = [];
  let cursor = null;
  for (let i = 0; i < 50; i += 1) {
    const response = await app.request("/sync/pull", {
      method: "POST",
      headers: {
        authorization: `Bearer ${sessionToken}`,
        "content-type": "application/json"
      },
      body: JSON.stringify({ protocolVersion: 1, cursor, limit: 100, mode })
    });
    assert.equal(response.status, 200);
    const window = await response.json();
    changes.push(...window.changes);
    if (window.changes.length === 0 || window.nextCursor === cursor) {
      break;
    }
    cursor = window.nextCursor;
  }
  return changes;
}
