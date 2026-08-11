import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  AGENT_PLAN_TREE_BATCH_ENTITY,
  applyMigrations,
  createAgentMcpServer,
  createApp,
  createDatabaseClient,
  createDrizzleAgentActivityStore,
  createDrizzleAgentPlanTreeBatchWriteStore,
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

test("agent plan-tree batch write accepts the full authored tree and returns soft warnings per item", async () => {
  const writes = [];
  const request = fullTreeRequest({
    idempotencyKey: "agent-plan-tree-full",
    prefix: "full",
  });
  const store = inMemoryPlanTreeStore({
    writes,
    writeResult(input) {
      return {
        duplicate: false,
        serverClock: "2026-07-24T02:00:01.000Z",
        appliedKeys: appliedKeys(input.rows),
      };
    },
  });
  const app = createPlanTreeApp({ agentPlanTreeBatchWriteStore: store });

  const response = await postPlanTreeBatch(app, request);

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.accepted, true);
  assert.equal(body.dryRun, false);
  assert.equal(body.duplicate, false);
  assert.equal(body.batchId, request.idempotencyKey);
  assert.equal(body.items.length, 11);
  assert.ok(body.items.every((item) => item.outcome === "applied"));
  assert.ok(
    body.items
      .flatMap((item) => item.warnings)
      .some((warning) => warning.rule === "prescription_repeat_improbable"),
  );
  assert.ok(
    body.items
      .flatMap((item) => item.warnings)
      .some((warning) => warning.rule === "cadence_window_improbable"),
  );

  assert.equal(writes.length, 1);
  assert.equal(writes[0].userId, "user-1");
  assert.equal(writes[0].deviceId, "agent:agent-key-1");
  assert.equal(writes[0].rows.workoutTemplates.length, 2);
  assert.equal(writes[0].rows.templateExercises.length, 2);
  assert.equal(writes[0].rows.prescriptions.length, 1);
  assert.equal(writes[0].rows.templateGroups.length, 1);
  assert.equal(writes[0].rows.templateGroupMembers.length, 2);
  assert.equal(writes[0].rows.routines.length, 1);
  assert.equal(writes[0].rows.routineEntries.length, 2);
  assert.equal(
    writes[0].rows.prescriptions[0].payload.template_exercise_id,
    request.templateExercises[0].id,
  );
  assert.equal(writes[0].rows.routines[0].payload.cadence_kind, "rotating");
});

test("agent plan-tree dry run validates the complete tree without consuming the write", async () => {
  const writes = [];
  const nudges = [];
  const request = fullTreeRequest({
    idempotencyKey: "agent-plan-tree-dry-run",
    prefix: "dry-run",
  });
  const app = createPlanTreeApp({
    agentPlanTreeBatchWriteStore: inMemoryPlanTreeStore({ writes }),
    syncNudgePublisher: {
      async enqueueSyncNudge(input) {
        nudges.push(input);
        return { enqueued: true, jobId: "unexpected" };
      },
    },
  });

  const dryRunResponse = await postPlanTreeBatch(app, {
    ...request,
    dryRun: true,
  });

  assert.equal(dryRunResponse.status, 200);
  const dryRun = await dryRunResponse.json();
  assert.equal(dryRun.accepted, true);
  assert.equal(dryRun.dryRun, true);
  assert.equal(dryRun.duplicate, false);
  assert.equal(dryRun.batchId, null);
  assert.deepEqual(dryRun.expectedCounts, request.expectedCounts);
  assert.deepEqual(dryRun.actualCounts, request.expectedCounts);
  assert.ok(dryRun.items.every((item) => item.outcome === "validated"));
  assert.deepEqual(writes, []);
  assert.deepEqual(nudges, []);

  const applyResponse = await postPlanTreeBatch(app, request);

  assert.equal(applyResponse.status, 200);
  const applied = await applyResponse.json();
  assert.equal(applied.dryRun, false);
  assert.equal(applied.batchId, request.idempotencyKey);
  assert.ok(applied.items.every((item) => item.outcome === "applied"));
  assert.equal(writes.length, 1);
});

test("agent plan-tree batch rejects an incomplete serialization before storage", async () => {
  const writes = [];
  const request = fullTreeRequest({
    idempotencyKey: "agent-plan-tree-incomplete",
    prefix: "incomplete",
  });
  request.templateExercises.pop();
  const app = createPlanTreeApp({
    agentPlanTreeBatchWriteStore: inMemoryPlanTreeStore({ writes }),
  });

  const response = await postPlanTreeBatch(app, request);

  assert.equal(response.status, 400);
  const body = await response.json();
  assert.match(JSON.stringify(body), /Expected 2 templateExercises rows but received 1/);
  assert.deepEqual(writes, []);
});

test("agent plan-tree batch write hard-rejects the whole request before storage or a sync nudge", async () => {
  const writes = [];
  const nudges = [];
  const request = fullTreeRequest({
    idempotencyKey: "agent-plan-tree-invalid",
    prefix: "invalid",
  });
  request.prescriptions[0].repeat = 0;
  const app = createPlanTreeApp({
    agentPlanTreeBatchWriteStore: inMemoryPlanTreeStore({ writes }),
    syncNudgePublisher: {
      async enqueueSyncNudge(input) {
        nudges.push(input);
        return { enqueued: true, jobId: "unexpected" };
      },
    },
  });

  const response = await postPlanTreeBatch(app, request);

  assert.equal(response.status, 422);
  const body = await response.json();
  assert.equal(body.code, "agent_plan_tree_batch_write_failed");
  assert.ok(
    body.errors.some((issue) => issue.rule === "prescription_repeat_min"),
  );
  assert.deepEqual(writes, []);
  assert.deepEqual(nudges, []);
});

test("agent plan-tree batch write rejects an invalid Prescription mode as a per-item hard error", async () => {
  const writes = [];
  const request = fullTreeRequest({
    idempotencyKey: "agent-plan-tree-invalid-mode",
    prefix: "invalid-mode",
  });
  request.prescriptions[0].mode = "not-a-mode";
  const app = createPlanTreeApp({
    agentPlanTreeBatchWriteStore: inMemoryPlanTreeStore({ writes }),
  });

  const response = await postPlanTreeBatch(app, request);

  assert.equal(response.status, 422);
  const body = await response.json();
  assert.ok(
    body.errors.some((issue) => issue.rule === "prescription_mode_invalid"),
  );
  assert.deepEqual(writes, []);
});

test("plan-tree uniqueness errors identify the later request item that introduced each conflict", async () => {
  const templateId = "attribution-template";
  const duplicateExerciseRequest = {
    idempotencyKey: "agent-plan-tree-duplicate-exercise-attribution",
    workoutTemplates: [
      {
        id: templateId,
        name: "Attribution",
        notes: null,
        deletedAt: null,
      },
    ],
    templateExercises: [
      {
        id: "attribution-exercise-first",
        workoutTemplateId: templateId,
        exerciseId: "platform-back-squat",
        position: 0,
        note: null,
        deletedAt: null,
      },
      {
        id: "attribution-exercise-second",
        workoutTemplateId: templateId,
        exerciseId: "platform-back-squat",
        position: 1,
        note: null,
        deletedAt: null,
      },
    ],
    prescriptions: [],
    templateGroups: [],
    templateGroupMembers: [],
    routines: [],
    routineEntries: [],
  };
  const duplicateExerciseResponse = await postPlanTreeBatch(
    createPlanTreeApp({
      agentPlanTreeBatchWriteStore: inMemoryPlanTreeStore(),
    }),
    duplicateExerciseRequest,
  );

  assert.equal(duplicateExerciseResponse.status, 422);
  const duplicateExercise = await duplicateExerciseResponse.json();
  const exerciseIssue = duplicateExercise.errors.find(
    (issue) => issue.rule === "template_exercise_active_unique",
  );
  assert.equal(exerciseIssue.itemIndex, 1);
  assert.equal(exerciseIssue.entityId, "attribution-exercise-second");

  const membershipRequest = {
    idempotencyKey: "agent-plan-tree-duplicate-membership-attribution",
    workoutTemplates: duplicateExerciseRequest.workoutTemplates,
    templateExercises: [
      duplicateExerciseRequest.templateExercises[0],
      {
        ...duplicateExerciseRequest.templateExercises[1],
        exerciseId: "user-bench-press",
      },
    ],
    prescriptions: [],
    templateGroups: [
      {
        id: "attribution-group-first",
        workoutTemplateId: templateId,
        name: "First",
        colorHex: "#336699",
        rounds: 2,
        position: 0,
        deletedAt: null,
      },
      {
        id: "attribution-group-second",
        workoutTemplateId: templateId,
        name: "Second",
        colorHex: "#663399",
        rounds: 2,
        position: 1,
        deletedAt: null,
      },
    ],
    templateGroupMembers: [
      {
        id: "attribution-member-squat-first",
        groupId: "attribution-group-first",
        templateExerciseId: "attribution-exercise-first",
        position: 0,
        deletedAt: null,
      },
      {
        id: "attribution-member-bench-first",
        groupId: "attribution-group-first",
        templateExerciseId: "attribution-exercise-second",
        position: 1,
        deletedAt: null,
      },
      {
        id: "attribution-member-bench-second",
        groupId: "attribution-group-second",
        templateExerciseId: "attribution-exercise-second",
        position: 0,
        deletedAt: null,
      },
      {
        id: "attribution-member-squat-second",
        groupId: "attribution-group-second",
        templateExerciseId: "attribution-exercise-first",
        position: 1,
        deletedAt: null,
      },
    ],
    routines: [],
    routineEntries: [],
  };
  const membershipResponse = await postPlanTreeBatch(
    createPlanTreeApp({
      agentPlanTreeBatchWriteStore: inMemoryPlanTreeStore(),
    }),
    membershipRequest,
  );

  assert.equal(membershipResponse.status, 422);
  const membership = await membershipResponse.json();
  const membershipIssues = membership.errors
    .filter((issue) => issue.rule === "template_group_membership_active_unique")
    .sort((left, right) => left.itemIndex - right.itemIndex);
  assert.deepEqual(
    membershipIssues.map((issue) => [issue.itemIndex, issue.entityId]),
    [
      [2, "attribution-member-bench-second"],
      [3, "attribution-member-squat-second"],
    ],
  );
});

test("agent plan-tree batch write enforces the aggregate 500-row cap", async () => {
  const writes = [];
  const app = createPlanTreeApp({
    agentPlanTreeBatchWriteStore: inMemoryPlanTreeStore({ writes }),
  });
  const response = await postPlanTreeBatch(app, {
    idempotencyKey: "agent-plan-tree-over-cap",
    workoutTemplates: Array.from({ length: 501 }, (_, index) => ({
      id: `template-${index}`,
      name: `Template ${index}`,
      notes: null,
      deletedAt: null,
    })),
    templateExercises: [],
    prescriptions: [],
    templateGroups: [],
    templateGroupMembers: [],
    routines: [],
    routineEntries: [],
  });

  assert.equal(response.status, 400);
  assert.deepEqual(writes, []);
});

test("an idempotent replay returns from its durable receipt before catalog or relationship validation", async () => {
  const request = fullTreeRequest({
    idempotencyKey: "agent-plan-tree-receipt-replay",
    prefix: "receipt",
  });
  const app = createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore("user-1"),
    agentPlanTreeBatchWriteStore: {
      async readPlanTreeBatchReceipt(input) {
        assert.equal(input.batchId, request.idempotencyKey);
        return { serverClock: "2026-07-24T02:00:01.000Z" };
      },
      async loadPlanTreeBatchReferences() {
        throw new Error("replay must not load plan references");
      },
      async writePlanTreeBatch() {
        throw new Error("replay must not write");
      },
    },
  });

  const response = await postPlanTreeBatch(app, request);

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.duplicate, true);
  assert.equal(body.items.length, 11);
  assert.ok(body.items.every((item) => item.outcome === "duplicate"));
});

test("agent_batch_write_plan_tree mirrors the REST write over bearer-authenticated MCP", async () => {
  const writes = [];
  const agentApiKeyStore = createAgentKeyStore("user-1");
  const agentCatalogStore = catalogStore("user-1");
  const agentPlanTreeBatchWriteStore = inMemoryPlanTreeStore({ writes });
  const logger = { info() {}, error() {} };
  const app = createApp({
    logger,
    agentApiKeyStore,
    createMcpServer: () =>
      createAgentMcpServer({
        agentApiKeyStore,
        agentCatalogStore,
        agentPlanTreeBatchWriteStore,
        logger,
      }),
  });
  const request = {
    idempotencyKey: "agent-plan-tree-mcp",
    workoutTemplates: [
      {
        id: "mcp-template",
        name: "MCP Template",
        notes: null,
        deletedAt: null,
      },
    ],
    templateExercises: [],
    prescriptions: [],
    templateGroups: [],
    templateGroupMembers: [],
    routines: [],
    routineEntries: [],
  };
  request.expectedCounts = planTreeCounts(request);

  const response = await postMcp(
    app,
    {
      jsonrpc: "2.0",
      id: 1,
      method: "tools/call",
      params: {
        name: "agent_batch_write_plan_tree",
        arguments: { request },
      },
    },
    { authorization: "Bearer prn_agent_secret" },
  );

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.result.isError, undefined);
  assert.equal(body.result.structuredContent.accepted, true);
  assert.equal(body.result.structuredContent.batchId, request.idempotencyKey);
  assert.equal(writes.length, 1);
});

test(
  "plan-tree batch persistence is atomic and idempotent, records one visible Activity batch, undoes the whole tree, and archives roots without cascading into children or Template Link history",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-plan-tree-${randomUUID()}`;
    const nudges = [];
    const planStore = createDrizzleAgentPlanTreeBatchWriteStore(database.db);
    const app = createPlanTreeApp({
      userId,
      agentPlanTreeBatchWriteStore: planStore,
      agentActivityStore: createDrizzleAgentActivityStore(database.db),
      syncNudgePublisher: {
        async enqueueSyncNudge(input) {
          nudges.push(input);
          return { enqueued: true, jobId: `nudge-${nudges.length}` };
        },
      },
    });
    const undoRequest = fullTreeRequest({
      idempotencyKey: `plan-tree-create-${randomUUID()}`,
      prefix: `undo-${randomUUID()}`,
    });
    const archiveRequest = fullTreeRequest({
      idempotencyKey: `plan-tree-create-${randomUUID()}`,
      prefix: `archive-${randomUUID()}`,
      updatedAt: "2026-07-24T03:00:00.000Z",
    });

    try {
      await database.db.insert(schema.user).values({
        id: userId,
        name: "Agent Plan Tree User",
        email: `${userId}@example.com`,
        emailVerified: true,
      });

      const createResponse = await postPlanTreeBatch(app, undoRequest);
      assert.equal(createResponse.status, 200);
      assert.equal((await createResponse.json()).duplicate, false);

      const directActivity = await database.sql`
        select actor, entity_table, entity_id
        from activity_log
        where user_id = ${userId} and batch_id = ${undoRequest.idempotencyKey}
      `;
      assert.equal(directActivity.length, 12);
      assert.equal(
        directActivity.filter(
          (row) => row.entity_table !== AGENT_PLAN_TREE_BATCH_ENTITY,
        ).length,
        11,
      );
      assert.ok(directActivity.every((row) => row.actor === "agent"));

      const visibleActivityResponse = await getAgent(
        app,
        `/agent/activity?batchId=${encodeURIComponent(
          undoRequest.idempotencyKey,
        )}`,
      );
      assert.equal(visibleActivityResponse.status, 200);
      const visibleActivity = await visibleActivityResponse.json();
      assert.equal(visibleActivity.batches.length, 1);
      assert.equal(visibleActivity.batches[0].entries.length, 11);
      assert.ok(
        visibleActivity.batches[0].entries.every(
          (entry) => entry.entityTable !== AGENT_PLAN_TREE_BATCH_ENTITY,
        ),
      );

      const replayResponse = await postPlanTreeBatch(app, undoRequest);
      assert.equal(replayResponse.status, 200);
      const replay = await replayResponse.json();
      assert.equal(replay.duplicate, true);
      assert.ok(replay.items.every((item) => item.outcome === "duplicate"));
      const replayActivity = await database.sql`
        select id from activity_log
        where user_id = ${userId} and batch_id = ${undoRequest.idempotencyKey}
      `;
      assert.equal(replayActivity.length, 12);

      const undoResponse = await postUndo(app, {
        batchId: undoRequest.idempotencyKey,
        idempotencyKey: `undo-${randomUUID()}`,
      });
      assert.equal(undoResponse.status, 200);
      const undo = await undoResponse.json();
      assert.equal(undo.applied, true);
      assert.equal(undo.entries.length, 11);
      assert.ok(undo.entries.every((entry) => entry.outcome === "reverted"));
      await assertTreeArchived(database, undoRequest);

      const secondCreateResponse = await postPlanTreeBatch(app, archiveRequest);
      assert.equal(secondCreateResponse.status, 200);

      const invalidMoveResponse = await postPlanTreeBatch(app, {
        idempotencyKey: `plan-tree-invalid-move-${randomUUID()}`,
        workoutTemplates: [],
        templateExercises: [
          {
            ...archiveRequest.templateExercises[0],
            workoutTemplateId: archiveRequest.workoutTemplates[1].id,
            updatedAt: "2026-07-24T03:01:00.000Z",
          },
        ],
        prescriptions: [],
        templateGroups: [],
        templateGroupMembers: [],
        routines: [],
        routineEntries: [],
      });
      assert.equal(invalidMoveResponse.status, 422);
      const invalidMove = await invalidMoveResponse.json();
      assert.ok(
        invalidMove.errors.some(
          (issue) => issue.rule === "template_group_member_template_mismatch",
        ),
      );
      const unmovedExerciseRows = await database.sql`
        select payload from template_exercises
        where id = ${archiveRequest.templateExercises[0].id}
      `;
      assert.equal(
        unmovedExerciseRows[0].payload.workout_template_id,
        archiveRequest.workoutTemplates[0].id,
      );

      const templateLinkId = `link-${randomUUID()}`;
      await database.db.insert(schema.templateLinks).values(
        opaquePlanRow({
          id: templateLinkId,
          userId,
          at: new Date("2026-07-24T03:05:00.000Z"),
          payload: {
            workout_id: `workout-${randomUUID()}`,
            workout_template_id: archiveRequest.workoutTemplates[0].id,
            routine_id: archiveRequest.routines[0].id,
            slot: 1,
            workout_local_date: "2026-07-24",
            workout_deleted_at: null,
          },
        }),
      );

      const archivedAt = "2026-07-24T04:00:00.000Z";
      const rootArchiveResponse = await postPlanTreeBatch(app, {
        idempotencyKey: `plan-tree-archive-${randomUUID()}`,
        workoutTemplates: [
          {
            ...archiveRequest.workoutTemplates[0],
            updatedAt: archivedAt,
            deletedAt: archivedAt,
          },
        ],
        templateExercises: [],
        prescriptions: [],
        templateGroups: [],
        templateGroupMembers: [],
        routines: [
          {
            ...archiveRequest.routines[0],
            updatedAt: archivedAt,
            deletedAt: archivedAt,
          },
        ],
        routineEntries: [],
      });
      assert.equal(rootArchiveResponse.status, 200);

      const archivedTemplateRows = await database.sql`
        select deleted_at from workout_templates
        where id = ${archiveRequest.workoutTemplates[0].id}
      `;
      const archivedRoutineRows = await database.sql`
        select deleted_at from routines
        where id = ${archiveRequest.routines[0].id}
      `;
      assert.notEqual(archivedTemplateRows[0].deleted_at, null);
      assert.notEqual(archivedRoutineRows[0].deleted_at, null);

      const childRows = await database.sql`
        select deleted_at from template_exercises
        where id in (
          ${archiveRequest.templateExercises[0].id},
          ${archiveRequest.templateExercises[1].id}
        )
      `;
      const entryRows = await database.sql`
        select deleted_at from routine_entries
        where id in (
          ${archiveRequest.routineEntries[0].id},
          ${archiveRequest.routineEntries[1].id}
        )
      `;
      assert.equal(childRows.length, 2);
      assert.ok(childRows.every((row) => row.deleted_at === null));
      assert.equal(entryRows.length, 2);
      assert.ok(entryRows.every((row) => row.deleted_at === null));

      const linkRows = await database.sql`
        select payload, deleted_at from template_links where id = ${templateLinkId}
      `;
      assert.equal(linkRows.length, 1);
      assert.equal(linkRows[0].deleted_at, null);
      assert.equal(
        linkRows[0].payload.workout_template_id,
        archiveRequest.workoutTemplates[0].id,
      );

      assert.equal(nudges.length, 4);
      assert.ok(
        nudges.every(
          (nudge) =>
            nudge.userId === userId &&
            nudge.sourceDeviceId === "agent:agent-key-1" &&
            nudge.reason === "agent_write",
        ),
      );
    } finally {
      await database.close();
    }
  },
);

test(
  "an older plan-tree write reports superseded and leaves the newer stored row intact",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-plan-tree-superseded-${randomUUID()}`;
    const nudges = [];
    const app = createPlanTreeApp({
      userId,
      agentPlanTreeBatchWriteStore: createDrizzleAgentPlanTreeBatchWriteStore(
        database.db,
      ),
      syncNudgePublisher: {
        async enqueueSyncNudge(input) {
          nudges.push(input);
          return { enqueued: true, jobId: `nudge-${nudges.length}` };
        },
      },
    });
    const templateId = `superseded-template-${randomUUID()}`;

    try {
      await database.db.insert(schema.user).values({
        id: userId,
        name: "Agent Plan Tree Superseded User",
        email: `${userId}@example.com`,
        emailVerified: true,
      });

      const newerResponse = await postPlanTreeBatch(app, {
        idempotencyKey: `plan-tree-newer-${randomUUID()}`,
        workoutTemplates: [
          {
            id: templateId,
            name: "Newer name",
            notes: null,
            updatedAt: "2026-07-20T02:00:00.000Z",
            deletedAt: null,
          },
        ],
        templateExercises: [],
        prescriptions: [],
        templateGroups: [],
        templateGroupMembers: [],
        routines: [],
        routineEntries: [],
      });
      assert.equal(newerResponse.status, 200);

      const olderResponse = await postPlanTreeBatch(app, {
        idempotencyKey: `plan-tree-older-${randomUUID()}`,
        workoutTemplates: [
          {
            id: templateId,
            name: "Older name",
            notes: null,
            updatedAt: "2026-07-19T02:00:00.000Z",
            deletedAt: null,
          },
        ],
        templateExercises: [],
        prescriptions: [],
        templateGroups: [],
        templateGroupMembers: [],
        routines: [],
        routineEntries: [],
      });
      assert.equal(olderResponse.status, 200);
      const older = await olderResponse.json();
      assert.equal(older.duplicate, false);
      assert.equal(older.items.length, 1);
      assert.equal(older.items[0].outcome, "superseded");

      const storedTemplates = await database.sql`
        select payload from workout_templates where id = ${templateId}
      `;
      assert.equal(storedTemplates[0].payload.name, "Newer name");
      assert.equal(nudges.length, 1);
    } finally {
      await database.close();
    }
  },
);

test(
  "concurrent replays with one idempotency key return applied plus duplicate without a 500",
  { skip },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-plan-tree-race-${randomUUID()}`;
    const nudges = [];
    const baseStore = createDrizzleAgentPlanTreeBatchWriteStore(database.db);
    let waitingReceiptReads = 0;
    let releaseReceiptReads;
    const receiptReadBarrier = new Promise((resolve) => {
      releaseReceiptReads = resolve;
    });
    const racingStore = {
      ...baseStore,
      async readPlanTreeBatchReceipt(input) {
        const receipt = await baseStore.readPlanTreeBatchReceipt(input);
        if (receipt !== null) {
          return receipt;
        }
        waitingReceiptReads += 1;
        if (waitingReceiptReads === 2) {
          releaseReceiptReads();
        }
        await receiptReadBarrier;
        return null;
      },
    };
    const app = createPlanTreeApp({
      userId,
      agentPlanTreeBatchWriteStore: racingStore,
      syncNudgePublisher: {
        async enqueueSyncNudge(input) {
          nudges.push(input);
          return { enqueued: true, jobId: `nudge-${nudges.length}` };
        },
      },
    });
    const request = fullTreeRequest({
      idempotencyKey: `plan-tree-race-${randomUUID()}`,
      prefix: `race-${randomUUID()}`,
      updatedAt: "2026-07-20T03:00:00.000Z",
    });

    try {
      await database.db.insert(schema.user).values({
        id: userId,
        name: "Agent Plan Tree Race User",
        email: `${userId}@example.com`,
        emailVerified: true,
      });

      const responses = await Promise.all([
        postPlanTreeBatch(app, request),
        postPlanTreeBatch(app, request),
      ]);
      assert.ok(responses.every((response) => response.status === 200));
      const bodies = await Promise.all(
        responses.map((response) => response.json()),
      );
      assert.deepEqual(bodies.map((body) => body.duplicate).sort(), [
        false,
        true,
      ]);
      assert.ok(
        bodies
          .find((body) => body.duplicate)
          .items.every((item) => item.outcome === "duplicate"),
      );

      const activityRows = await database.sql`
        select id from activity_log
        where user_id = ${userId} and batch_id = ${request.idempotencyKey}
      `;
      assert.equal(activityRows.length, 12);
      assert.equal(nudges.length, 1);
    } finally {
      await database.close();
    }
  },
);

function createPlanTreeApp({
  agentActivityStore,
  agentPlanTreeBatchWriteStore,
  syncNudgePublisher,
  userId = "user-1",
}) {
  return createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore(userId),
    agentActivityStore,
    agentCatalogStore: catalogStore(userId),
    agentPlanTreeBatchWriteStore,
    syncNudgePublisher,
  });
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

function catalogStore(userId) {
  return createInMemoryAgentCatalogStore([
    exerciseFixture({
      id: "platform-back-squat",
      name: "Back Squat",
    }),
    exerciseFixture({
      id: "user-bench-press",
      library: "user",
      ownerUserId: userId,
      name: "Bench Press",
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

function inMemoryPlanTreeStore({ writes, writeResult } = {}) {
  const recordedWrites = writes ?? [];
  return {
    async readPlanTreeBatchReceipt() {
      return null;
    },
    async loadPlanTreeBatchReferences() {
      return emptyReferences();
    },
    async writePlanTreeBatch(input) {
      recordedWrites.push(input);
      return (
        writeResult?.(input) ?? {
          duplicate: false,
          serverClock: "2026-07-24T02:00:01.000Z",
          appliedKeys: appliedKeys(input.rows),
        }
      );
    },
  };
}

function emptyReferences() {
  return {
    workoutTemplates: [],
    templateExercises: [],
    prescriptions: [],
    templateGroups: [],
    templateGroupMembers: [],
    routines: [],
    routineEntries: [],
  };
}

function appliedKeys(rows) {
  return [
    ...rows.workoutTemplates.map((row) => `workoutTemplate:${row.id}`),
    ...rows.templateExercises.map((row) => `templateExercise:${row.id}`),
    ...rows.prescriptions.map((row) => `prescription:${row.id}`),
    ...rows.templateGroups.map((row) => `templateGroup:${row.id}`),
    ...rows.templateGroupMembers.map((row) => `templateGroupMember:${row.id}`),
    ...rows.routines.map((row) => `routine:${row.id}`),
    ...rows.routineEntries.map((row) => `routineEntry:${row.id}`),
  ];
}

function fullTreeRequest({
  idempotencyKey,
  prefix,
  updatedAt = "2026-07-24T02:00:00.000Z",
}) {
  const templateOneId = `${prefix}-template-one`;
  const templateTwoId = `${prefix}-template-two`;
  const squatId = `${prefix}-template-exercise-squat`;
  const benchId = `${prefix}-template-exercise-bench`;
  const groupId = `${prefix}-group`;
  const routineId = `${prefix}-routine`;
  const syncFields = { updatedAt, deletedAt: null };
  const request = {
    idempotencyKey,
    workoutTemplates: [
      {
        id: templateOneId,
        name: "Strength A",
        notes: "Primary day",
        ...syncFields,
      },
      {
        id: templateTwoId,
        name: "Recovery",
        notes: null,
        ...syncFields,
      },
    ],
    templateExercises: [
      {
        id: squatId,
        workoutTemplateId: templateOneId,
        exerciseId: "platform-back-squat",
        position: 0,
        note: null,
        ...syncFields,
      },
      {
        id: benchId,
        workoutTemplateId: templateOneId,
        exerciseId: "user-bench-press",
        position: 1,
        note: "Pause",
        ...syncFields,
      },
    ],
    prescriptions: [
      {
        id: `${prefix}-prescription`,
        templateExerciseId: squatId,
        mode: "fixed",
        position: 0,
        repeat: 101,
        restAfterSeconds: 120,
        values: {
          load: { entered: "100", unit: "kilogram" },
          reps: { entered: "5", unit: "repetition" },
        },
        ...syncFields,
      },
    ],
    templateGroups: [
      {
        id: groupId,
        workoutTemplateId: templateOneId,
        name: "Main superset",
        colorHex: "#336699",
        rounds: 3,
        position: 0,
        ...syncFields,
      },
    ],
    templateGroupMembers: [
      {
        id: `${prefix}-group-member-squat`,
        groupId,
        templateExerciseId: squatId,
        position: 0,
        ...syncFields,
      },
      {
        id: `${prefix}-group-member-bench`,
        groupId,
        templateExerciseId: benchId,
        position: 1,
        ...syncFields,
      },
    ],
    routines: [
      {
        id: routineId,
        name: "Long rotation",
        notes: null,
        cadenceKind: "rotating",
        cadenceWindow: 32,
        ...syncFields,
      },
    ],
    routineEntries: [
      {
        id: `${prefix}-routine-entry-one`,
        routineId,
        workoutTemplateId: templateOneId,
        position: 0,
        slot: 1,
        ...syncFields,
      },
      {
        id: `${prefix}-routine-entry-two`,
        routineId,
        workoutTemplateId: templateTwoId,
        position: 1,
        slot: 32,
        ...syncFields,
      },
    ],
  };
  request.expectedCounts = planTreeCounts(request);
  return request;
}

async function assertTreeArchived(database, request) {
  const templates = await database.sql`
    select deleted_at from workout_templates
    where id in (
      ${request.workoutTemplates[0].id},
      ${request.workoutTemplates[1].id}
    )
  `;
  const exercises = await database.sql`
    select deleted_at from template_exercises
    where id in (
      ${request.templateExercises[0].id},
      ${request.templateExercises[1].id}
    )
  `;
  const prescriptions = await database.sql`
    select deleted_at from prescriptions where id = ${request.prescriptions[0].id}
  `;
  const groups = await database.sql`
    select deleted_at from template_groups where id = ${request.templateGroups[0].id}
  `;
  const members = await database.sql`
    select deleted_at from template_group_members
    where id in (
      ${request.templateGroupMembers[0].id},
      ${request.templateGroupMembers[1].id}
    )
  `;
  const routines = await database.sql`
    select deleted_at from routines where id = ${request.routines[0].id}
  `;
  const entries = await database.sql`
    select deleted_at from routine_entries
    where id in (
      ${request.routineEntries[0].id},
      ${request.routineEntries[1].id}
    )
  `;

  assert.equal(templates.length, 2);
  assert.equal(exercises.length, 2);
  assert.equal(prescriptions.length, 1);
  assert.equal(groups.length, 1);
  assert.equal(members.length, 2);
  assert.equal(routines.length, 1);
  assert.equal(entries.length, 2);
  assert.ok(
    [
      ...templates,
      ...exercises,
      ...prescriptions,
      ...groups,
      ...members,
      ...routines,
      ...entries,
    ].every((row) => row.deleted_at !== null),
  );
}

function opaquePlanRow({ id, userId, at, payload }) {
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

function getAgent(app, path) {
  return app.request(path, {
    headers: { authorization: "Bearer prn_agent_secret" },
  });
}

function postPlanTreeBatch(app, body) {
  const request = {
    ...body,
    expectedCounts: body.expectedCounts ?? planTreeCounts(body),
  };
  return app.request("/agent/plan-tree/batch-write", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_agent_secret",
      "content-type": "application/json",
    },
    body: JSON.stringify(request),
  });
}

function planTreeCounts(request) {
  return {
    workoutTemplates: request.workoutTemplates?.length ?? 0,
    templateExercises: request.templateExercises?.length ?? 0,
    prescriptions: request.prescriptions?.length ?? 0,
    templateGroups: request.templateGroups?.length ?? 0,
    templateGroupMembers: request.templateGroupMembers?.length ?? 0,
    routines: request.routines?.length ?? 0,
    routineEntries: request.routineEntries?.length ?? 0,
  };
}

function postUndo(app, body) {
  return app.request("/agent/activity/undo-batch", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_agent_secret",
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
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
