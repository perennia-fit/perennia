import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  applyMigrations,
  createApp,
  createDatabaseClient,
  createDrizzleAgentCatalogStore,
  createDrizzleAgentExerciseCatalogBatchWriteStore,
  createDrizzleRateLimitBackend,
  createInMemoryAgentCatalogStore,
  schema,
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

test("agent exercise catalog batch write creates a category and an exercise referencing it", async () => {
  const writes = [];
  const app = createAgentExerciseCatalogApp({
    agentExerciseCatalogBatchWriteStore: {
      async writeExerciseCatalogBatch(input) {
        writes.push(input);
        return {
          duplicate: false,
          serverClock: "2026-07-03T05:00:01.000Z",
          applied: [...input.categories, ...input.exercises].map((row) => ({
            id: row.id,
            updatedAt: row.updatedAt,
            deviceId: input.deviceId,
          })),
        };
      },
    },
  });

  const request = batchRequest({
    idempotencyKey: "agent-exercise-catalog-batch-create",
    categories: [
      {
        id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d001",
        name: "Mobility",
      },
    ],
    exercises: [
      {
        id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d002",
        name: "Couch Stretch",
        categoryId: "018f6a90-6d7f-7d63-bfc1-6f1025e0d001",
        dimensions: ["duration"],
      },
    ],
  });

  const response = await postAgentExerciseCatalogBatch(app, request);

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.accepted, true);
  assert.equal(body.duplicate, false);
  assert.equal(body.batchId, "agent-exercise-catalog-batch-create");
  assert.equal(body.categories.length, 1);
  assert.equal(body.categories[0].name, "Mobility");
  assert.equal(body.exercises.length, 1);
  assert.equal(body.exercises[0].name, "Couch Stretch");
  assert.equal(body.exercises[0].library, "user");

  assert.equal(writes.length, 1);
  assert.equal(writes[0].userId, "user-1");
  assert.equal(writes[0].deviceId, "agent:agent-key-1");
  assert.equal(writes[0].categories[0].payload.name, "Mobility");
  assert.equal(writes[0].exercises[0].payload.name, "Couch Stretch");
  assert.equal(writes[0].exercises[0].payload.library_origin, "user");
  assert.equal(
    writes[0].exercises[0].payload.category_id,
    "018f6a90-6d7f-7d63-bfc1-6f1025e0d001",
  );
  assert.deepEqual(
    JSON.parse(writes[0].exercises[0].payload.dimension_ids),
    ["duration"],
  );
  // completion-only default profile does not apply here (duration present).
  assert.equal(writes[0].exercises[0].payload.record_profile, "maxDuration");
});

test("agent exercise catalog batch write hard-rejects a dimension outside the curated registry at the schema layer", async () => {
  let writeCalled = false;
  const app = createAgentExerciseCatalogApp({
    agentExerciseCatalogBatchWriteStore: {
      async writeExerciseCatalogBatch() {
        writeCalled = true;
        throw new Error("writeExerciseCatalogBatch should not be called.");
      },
    },
  });

  const request = batchRequest({
    idempotencyKey: "agent-exercise-catalog-batch-bad-dimension",
    exercises: [
      {
        id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d010",
        name: "Bad Dimension Exercise",
        dimensions: ["velocity"],
      },
    ],
  });

  const response = await postAgentExerciseCatalogBatch(app, request);

  // Dimensions are constrained to the curated registry
  // {load,reps,duration,distance} by the request Zod schema itself, so an
  // out-of-registry value is a malformed request (400), not a semantic
  // batch-item failure (422) — the same "hard-reject impossible" tier, one
  // layer earlier.
  assert.equal(response.status, 400);
  assert.equal(writeCalled, false);
});

test("agent exercise catalog batch write hard-rejects an empty exercise name at the schema layer", async () => {
  const app = createAgentExerciseCatalogApp({
    agentExerciseCatalogBatchWriteStore: {
      async writeExerciseCatalogBatch() {
        throw new Error("writeExerciseCatalogBatch should not be called.");
      },
    },
  });

  const request = batchRequest({
    idempotencyKey: "agent-exercise-catalog-batch-empty-name",
    exercises: [
      {
        id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d011",
        name: "   ",
        dimensions: [],
      },
    ],
  });

  const response = await postAgentExerciseCatalogBatch(app, request);

  assert.equal(response.status, 400);
});

test("agent exercise catalog batch write hard-rejects an exercise referencing an unknown category", async () => {
  const app = createAgentExerciseCatalogApp({
    agentExerciseCatalogBatchWriteStore: {
      async writeExerciseCatalogBatch() {
        throw new Error("writeExerciseCatalogBatch should not be called.");
      },
    },
  });

  const request = batchRequest({
    idempotencyKey: "agent-exercise-catalog-batch-unknown-category",
    exercises: [
      {
        id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d012",
        name: "Orphan Exercise",
        categoryId: "not-a-real-category",
        dimensions: [],
      },
    ],
  });

  const response = await postAgentExerciseCatalogBatch(app, request);

  assert.equal(response.status, 422);
  const body = await response.json();
  assert.equal(body.errors[0].rule, "category_not_found");
});

test("agent exercise catalog batch write customizing a platform exercise creates a shadowing user row and never mutates the platform row", async () => {
  const writes = [];
  const app = createAgentExerciseCatalogApp({
    agentExerciseCatalogBatchWriteStore: {
      async writeExerciseCatalogBatch(input) {
        writes.push(input);
        return {
          duplicate: false,
          serverClock: "2026-07-03T05:00:01.000Z",
          applied: [...input.categories, ...input.exercises].map((row) => ({
            id: row.id,
            updatedAt: row.updatedAt,
            deviceId: input.deviceId,
          })),
        };
      },
    },
  });

  const request = batchRequest({
    idempotencyKey: "agent-exercise-catalog-batch-customize",
    exercises: [
      {
        id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d020",
        name: "Deadlift (deficit)",
        categoryId: null,
        dimensions: ["load", "reps"],
        customizesExerciseId: "platform-deadlift",
      },
    ],
  });

  const response = await postAgentExerciseCatalogBatch(app, request);

  assert.equal(response.status, 200);
  assert.equal(writes.length, 1);
  assert.equal(writes[0].exercises[0].payload.library_origin, "user");
  assert.equal(writes[0].exercises[0].id, "018f6a90-6d7f-7d63-bfc1-6f1025e0d020");
  assert.notEqual(writes[0].exercises[0].id, "platform-deadlift");
});

test("agent exercise catalog batch write hard-rejects customizing a non-platform exercise id", async () => {
  const app = createAgentExerciseCatalogApp({
    agentExerciseCatalogBatchWriteStore: {
      async writeExerciseCatalogBatch() {
        throw new Error("writeExerciseCatalogBatch should not be called.");
      },
    },
  });

  const request = batchRequest({
    idempotencyKey: "agent-exercise-catalog-batch-customize-invalid",
    exercises: [
      {
        id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d021",
        name: "Not a platform customization",
        dimensions: [],
        customizesExerciseId: "user-back-squat",
      },
    ],
  });

  const response = await postAgentExerciseCatalogBatch(app, request);

  assert.equal(response.status, 422);
  const body = await response.json();
  assert.equal(body.errors[0].rule, "customized_exercise_not_platform");
});

test("agent exercise catalog batch write archives an exercise via nullable deletedAt", async () => {
  const writes = [];
  const app = createAgentExerciseCatalogApp({
    agentExerciseCatalogBatchWriteStore: {
      async writeExerciseCatalogBatch(input) {
        writes.push(input);
        return {
          duplicate: false,
          serverClock: "2026-07-03T05:00:01.000Z",
          applied: [...input.categories, ...input.exercises].map((row) => ({
            id: row.id,
            updatedAt: row.updatedAt,
            deviceId: input.deviceId,
          })),
        };
      },
    },
  });

  const request = batchRequest({
    idempotencyKey: "agent-exercise-catalog-batch-archive",
    exercises: [
      {
        id: "user-back-squat",
        name: "Back Squat",
        dimensions: ["load", "reps"],
        deletedAt: "2026-07-03T06:00:00.000Z",
      },
    ],
  });

  const response = await postAgentExerciseCatalogBatch(app, request);

  assert.equal(response.status, 200);
  assert.equal(writes[0].exercises[0].payload.deleted_at, "2026-07-03T06:00:00.000Z");
});

test("agent exercise catalog batch write enqueues a best-effort sync nudge after a committed write", async () => {
  const nudges = [];
  const app = createAgentExerciseCatalogApp({
    agentExerciseCatalogBatchWriteStore: {
      async writeExerciseCatalogBatch(input) {
        return {
          duplicate: false,
          serverClock: "2026-07-03T05:00:01.000Z",
          applied: [...input.categories, ...input.exercises].map((row) => ({
            id: row.id,
            updatedAt: row.updatedAt,
            deviceId: input.deviceId,
          })),
        };
      },
    },
    syncNudgePublisher: {
      async enqueueSyncNudge(input) {
        nudges.push(input);
        return { enqueued: true, jobId: "agent-nudge-job-1" };
      },
    },
  });

  const response = await postAgentExerciseCatalogBatch(
    app,
    batchRequest({
      idempotencyKey: "agent-exercise-catalog-batch-nudge",
      exercises: [
        {
          id: "018f6a90-6d7f-7d63-bfc1-6f1025e0d030",
          name: "Nudge Exercise",
          dimensions: [],
        },
      ],
    }),
  );

  assert.equal(response.status, 200);
  assert.deepEqual(nudges, [
    {
      userId: "user-1",
      sourceDeviceId: "agent:agent-key-1",
      reason: "agent_write",
    },
  ]);
});

test(
  "agent exercise catalog batch write persists rows, records one Activity Log batch, replays idempotently, keeps archived exercise history intact, and enforces tenant isolation",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-exercise-catalog-user-${randomUUID()}`;
    const otherUserId = `agent-exercise-catalog-other-user-${randomUUID()}`;
    const categoryId = randomUUID();
    const exerciseId = randomUUID();

    const app = createAgentExerciseCatalogApp({
      agentCatalogStore: createDrizzleAgentCatalogStore(database.db),
      agentExerciseCatalogBatchWriteStore:
        createDrizzleAgentExerciseCatalogBatchWriteStore(database.db),
      userId,
    });

    const createRequest = batchRequest({
      idempotencyKey: `agent-exercise-catalog-batch-${randomUUID()}`,
      categories: [{ id: categoryId, name: "Powerlifting" }],
      exercises: [
        {
          id: exerciseId,
          name: "Comp Squat",
          categoryId,
          dimensions: ["load", "reps"],
        },
      ],
    });

    try {
      await database.db.insert(schema.user).values([
        {
          id: userId,
          name: "Agent Exercise Catalog User",
          email: `${userId}@example.com`,
          emailVerified: true,
        },
        {
          id: otherUserId,
          name: "Other User",
          email: `${otherUserId}@example.com`,
          emailVerified: true,
        },
      ]);

      const response = await postAgentExerciseCatalogBatch(app, createRequest);
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.accepted, true);
      assert.equal(body.duplicate, false);

      const categoryRows = await database.sql`
        select user_id, payload, deleted_at from exercise_categories where id = ${categoryId}
      `;
      assert.equal(categoryRows.length, 1);
      assert.equal(categoryRows[0].user_id, userId);
      assert.equal(categoryRows[0].payload.name, "Powerlifting");
      assert.equal(categoryRows[0].deleted_at, null);

      const exerciseRows = await database.sql`
        select user_id, payload, deleted_at from exercises where id = ${exerciseId}
      `;
      assert.equal(exerciseRows.length, 1);
      assert.equal(exerciseRows[0].user_id, userId);
      assert.equal(exerciseRows[0].payload.name, "Comp Squat");
      assert.equal(exerciseRows[0].payload.category_id, categoryId);

      const activityRows = await database.sql`
        select actor, batch_id, entity_table, entity_id, before_image, after_image
        from activity_log
        where batch_id = ${createRequest.idempotencyKey}
        order by entity_id
      `;
      assert.equal(activityRows.length, 2);
      assert.equal(
        new Set(activityRows.map((row) => row.batch_id)).size,
        1,
      );
      assert.ok(
        activityRows.every((row) => row.actor === "agent"),
      );
      assert.ok(
        activityRows.some((row) => row.entity_table === "exercises"),
      );
      assert.ok(
        activityRows.some((row) => row.entity_table === "exercise_categories"),
      );

      // Replay: idempotency key already used -> duplicate, no new Activity Log rows.
      const replayResponse = await postAgentExerciseCatalogBatch(
        app,
        createRequest,
      );
      assert.equal(replayResponse.status, 200);
      const replayBody = await replayResponse.json();
      assert.equal(replayBody.duplicate, true);

      const replayActivityRows = await database.sql`
        select id from activity_log where batch_id = ${createRequest.idempotencyKey}
      `;
      assert.equal(replayActivityRows.length, 2);

      // Now log a Logged Set against the exercise directly (simulating the app),
      // then archive the exercise via the agent batch-write and confirm the
      // set row still references it (archive keeps history).
      const setId = randomUUID();
      await database.db.insert(schema.loggedSets).values({
        id: setId,
        userId,
        deviceId: "device-1",
        payload: {
          id: setId,
          exercise_id: exerciseId,
          exercise_name: "Comp Squat",
          load_entered: "200",
          load_unit: "kilogram",
          reps_entered: "3",
          reps_unit: "repetition",
          updated_at: "2026-07-03T06:00:00.000Z",
          deleted_at: null,
        },
        updatedAt: new Date("2026-07-03T06:00:00.000Z"),
        deletedAt: null,
        receivedAt: new Date("2026-07-03T06:00:00.000Z"),
      });

      const archiveRequest = batchRequest({
        idempotencyKey: `agent-exercise-catalog-archive-${randomUUID()}`,
        exercises: [
          {
            id: exerciseId,
            name: "Comp Squat",
            categoryId,
            dimensions: ["load", "reps"],
            deletedAt: "2026-07-03T07:00:00.000Z",
          },
        ],
      });
      const archiveResponse = await postAgentExerciseCatalogBatch(
        app,
        archiveRequest,
      );
      assert.equal(archiveResponse.status, 200);

      const archivedExerciseRows = await database.sql`
        select deleted_at from exercises where id = ${exerciseId}
      `;
      assert.notEqual(archivedExerciseRows[0].deleted_at, null);

      const setRowsAfterArchive = await database.sql`
        select payload from logged_sets where id = ${setId}
      `;
      assert.equal(setRowsAfterArchive.length, 1);
      assert.equal(setRowsAfterArchive[0].payload.exercise_id, exerciseId);

      // Tenant isolation: a second user's push must never overwrite the
      // first user's row keyed by the same client PK.
      const otherApp = createAgentExerciseCatalogApp({
        agentCatalogStore: createDrizzleAgentCatalogStore(database.db),
        agentExerciseCatalogBatchWriteStore:
          createDrizzleAgentExerciseCatalogBatchWriteStore(database.db),
        userId: otherUserId,
      });
      const hijackRequest = batchRequest({
        idempotencyKey: `agent-exercise-catalog-hijack-${randomUUID()}`,
        exercises: [
          {
            id: exerciseId,
            name: "Hijacked Name",
            dimensions: [],
          },
        ],
      });
      const hijackResponse = await postAgentExerciseCatalogBatch(
        otherApp,
        hijackRequest,
      );
      assert.equal(hijackResponse.status, 200);

      const postHijackRows = await database.sql`
        select user_id, payload from exercises where id = ${exerciseId}
      `;
      assert.equal(postHijackRows[0].user_id, userId);
      assert.equal(postHijackRows[0].payload.name, "Comp Squat");
    } finally {
      await database.close();
    }
  },
);

test(
  "agent exercise catalog batch write accepts a reference to an existing, caller-visible Category that has zero exercises filed under it",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-exercise-catalog-empty-category-user-${randomUUID()}`;
    const categoryId = randomUUID();
    const exerciseId = randomUUID();

    const app = createAgentExerciseCatalogApp({
      agentCatalogStore: createDrizzleAgentCatalogStore(database.db),
      agentExerciseCatalogBatchWriteStore:
        createDrizzleAgentExerciseCatalogBatchWriteStore(database.db),
      userId,
    });

    try {
      await database.db.insert(schema.user).values({
        id: userId,
        name: "Agent Exercise Catalog Empty Category User",
        email: `${userId}@example.com`,
        emailVerified: true,
      });

      // A Category that already exists and is visible to the caller, but has
      // no Exercise currently filed under it (a brand-new empty Category, or
      // the first Exercise about to be filed into it) — created out-of-band
      // from the batch, exactly as it would be via ordinary sync.
      await database.db.insert(schema.exerciseCategories).values({
        id: categoryId,
        userId,
        deviceId: "device-1",
        payload: {
          id: categoryId,
          name: "Empty Category",
          sort_order: 0,
          color_hex: "#607D8B",
          updated_at: "2026-07-03T00:00:00.000Z",
          deleted_at: null,
        },
        updatedAt: new Date("2026-07-03T00:00:00.000Z"),
        deletedAt: null,
        receivedAt: new Date("2026-07-03T00:00:00.000Z"),
      });

      const request = batchRequest({
        idempotencyKey: `agent-exercise-catalog-empty-category-${randomUUID()}`,
        exercises: [
          {
            id: exerciseId,
            name: "First Exercise In Category",
            categoryId,
            dimensions: ["load", "reps"],
          },
        ],
      });

      const response = await postAgentExerciseCatalogBatch(app, request);

      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.accepted, true);
      assert.equal(body.exercises[0].name, "First Exercise In Category");

      const exerciseRows = await database.sql`
        select payload from exercises where id = ${exerciseId}
      `;
      assert.equal(exerciseRows.length, 1);
      assert.equal(exerciseRows[0].payload.category_id, categoryId);
    } finally {
      await database.close();
    }
  },
);

test(
  "agent exercise catalog batch write still hard-rejects a reference to an archived Category",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-exercise-catalog-archived-category-user-${randomUUID()}`;
    const categoryId = randomUUID();

    const app = createAgentExerciseCatalogApp({
      agentCatalogStore: createDrizzleAgentCatalogStore(database.db),
      agentExerciseCatalogBatchWriteStore:
        createDrizzleAgentExerciseCatalogBatchWriteStore(database.db),
      userId,
    });

    try {
      await database.db.insert(schema.user).values({
        id: userId,
        name: "Agent Exercise Catalog Archived Category User",
        email: `${userId}@example.com`,
        emailVerified: true,
      });

      // A Category the caller previously archived (deleted_at set) is not a
      // valid reference target even though the row still exists.
      await database.db.insert(schema.exerciseCategories).values({
        id: categoryId,
        userId,
        deviceId: "device-1",
        payload: {
          id: categoryId,
          name: "Archived Category",
          sort_order: 0,
          color_hex: "#607D8B",
          updated_at: "2026-07-03T00:00:00.000Z",
          deleted_at: "2026-07-03T00:30:00.000Z",
        },
        updatedAt: new Date("2026-07-03T00:30:00.000Z"),
        deletedAt: new Date("2026-07-03T00:30:00.000Z"),
        receivedAt: new Date("2026-07-03T00:30:00.000Z"),
      });

      const request = batchRequest({
        idempotencyKey: `agent-exercise-catalog-archived-category-${randomUUID()}`,
        exercises: [
          {
            id: randomUUID(),
            name: "Orphaned By Archived Category",
            categoryId,
            dimensions: [],
          },
        ],
      });

      const response = await postAgentExerciseCatalogBatch(app, request);

      assert.equal(response.status, 422);
      const body = await response.json();
      assert.equal(body.errors[0].rule, "category_not_found");
    } finally {
      await database.close();
    }
  },
);

function createAgentExerciseCatalogApp({
  agentCatalogStore,
  agentExerciseCatalogBatchWriteStore,
  agentRateLimit,
  logger = { info() {}, error() {} },
  rateLimitBackend,
  syncNudgePublisher,
  userId = "user-1",
}) {
  return createApp({
    logger,
    agentApiKeyStore: createAgentKeyStore(userId, agentRateLimit),
    agentCatalogStore:
      agentCatalogStore ?? createInMemoryAgentCatalogStore(catalogFixtures(userId)),
    agentExerciseCatalogBatchWriteStore,
    rateLimitBackend,
    syncNudgePublisher,
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
        ...agentRateLimit,
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

function postAgentExerciseCatalogBatch(app, body, headers = {}) {
  return app.request("/agent/exercises/batch-write", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_agent_secret",
      "content-type": "application/json",
      ...headers,
    },
    body: JSON.stringify(body),
  });
}

function batchRequest({ idempotencyKey, categories = [], exercises = [] }) {
  return {
    idempotencyKey,
    categories: categories.map((category) => ({
      sortOrder: 0,
      colorHex: "#607D8B",
      deletedAt: null,
      ...category,
    })),
    exercises: exercises.map((exercise) => ({
      categoryId: null,
      defaultLoadUnit: "kilogram",
      loadMode: "added",
      isUnilateral: false,
      usesRpe: false,
      isFavorite: false,
      equipment: [],
      notes: null,
      customizesExerciseId: null,
      deletedAt: null,
      ...exercise,
    })),
  };
}

function catalogFixtures(userId = "user-1") {
  return [
    exercise({
      id: "platform-back-squat",
      library: "platform",
      name: "Back Squat",
      categoryId: "cat-strength",
    }),
    exercise({
      id: "user-back-squat",
      library: "user",
      ownerUserId: userId,
      name: "Back Squat",
      categoryId: "cat-strength",
      shadowedPlatformExerciseId: "platform-back-squat",
    }),
    exercise({
      id: "platform-deadlift",
      library: "platform",
      name: "Deadlift",
      categoryId: "cat-strength",
    }),
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
  shadowedPlatformExerciseId = null,
}) {
  return {
    id,
    library,
    ownerUserId,
    name,
    category: {
      id: categoryId,
      name: categoryId === "cat-strength" ? "Strength" : "Other",
    },
    dimensions: ["load", "reps"],
    equipment,
    loadMode: "added",
    recordProfile: "repMax",
    favorite,
    active,
    shadowedPlatformExerciseId,
  };
}
