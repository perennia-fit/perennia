import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  applyMigrations,
  agentProtocolsBatchMarkerId,
  createApp,
  createDatabaseClient,
  createDrizzleAgentActivityStore,
  createDrizzleAgentWorkoutBatchWriteStore,
  createInMemoryAgentCatalogStore,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

test("GET /agent/activity authenticates and passes the bounded query contract to the store", async () => {
  const reads = [];
  const app = createAgentActivityApp({
    agentActivityStore: {
      async listActivity(input) {
        reads.push(input);
        return {
          batches: [
            {
              batchId: "batch-1",
              actor: "agent",
              occurredAt: "2026-06-24T05:00:00.000Z",
              entries: [
                {
                  id: "agent:batch-1:set-1",
                  entityTable: "logged_sets",
                  entityId: "set-1",
                  beforeImage: null,
                  afterImage: { id: "set-1", deleted_at: null },
                  occurredAt: "2026-06-24T05:00:00.000Z"
                }
              ]
            }
          ],
          limit: input.query.limit,
          nextCursor: null,
          totalMatched: 1
        };
      },
      async undoBatch() {
        throw new Error("undoBatch should not be called.");
      }
    }
  });

  const response = await getAgent(
    app,
    "/agent/activity?actor=agent&entityTable=logged_sets&from=2026-06-01T00:00:00.000Z&to=2026-06-30T00:00:00.000Z&limit=25"
  );

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.batches.length, 1);
  assert.equal(body.batches[0].batchId, "batch-1");
  assert.equal(body.batches[0].entries[0].entityTable, "logged_sets");
  assert.equal(body.totalMatched, 1);

  assert.equal(reads.length, 1);
  assert.equal(reads[0].userId, "user-1");
  assert.equal(reads[0].query.actor, "agent");
  assert.equal(reads[0].query.entityTable, "logged_sets");
  assert.equal(reads[0].query.from, "2026-06-01T00:00:00.000Z");
  assert.equal(reads[0].query.to, "2026-06-30T00:00:00.000Z");
  assert.equal(reads[0].query.limit, 25);
});

test("GET /agent/activity rejects a missing agent key", async () => {
  const app = createAgentActivityApp({
    agentActivityStore: {
      async listActivity() {
        throw new Error("listActivity should not be called.");
      },
      async undoBatch() {
        throw new Error("undoBatch should not be called.");
      }
    }
  });

  const response = await app.request("/agent/activity", { method: "GET" });
  assert.equal(response.status, 401);
});

test("POST /agent/activity/undo-batch passes the contract through and enqueues a sync nudge", async () => {
  const undos = [];
  const nudges = [];
  const app = createAgentActivityApp({
    agentActivityStore: {
      async listActivity() {
        throw new Error("listActivity should not be called.");
      },
      async undoBatch(input) {
        undos.push(input);
        return {
          accepted: true,
          applied: true,
          duplicate: false,
          serverClock: "2026-06-24T06:00:00.000Z",
          undoBatchId: input.idempotencyKey,
          activityLogEntries: 1,
          appliedRows: [
            { id: "set-1", updatedAt: "2026-06-24T06:00:00.000Z", deviceId: input.deviceId }
          ],
          entries: [
            {
              entryId: "agent:batch-1:logged_sets:set-1",
              entityTable: "logged_sets",
              entityId: "set-1",
              outcome: "reverted"
            }
          ]
        };
      }
    },
    syncNudgePublisher: {
      async enqueueSyncNudge(input) {
        nudges.push(input);
        return { enqueued: true, jobId: `undo-nudge-${nudges.length}` };
      }
    }
  });

  const response = await postUndo(app, {
    batchId: "batch-1",
    idempotencyKey: "undo-key-1"
  });

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.accepted, true);
  assert.equal(body.undoBatchId, "undo-key-1");
  assert.equal(body.entries[0].outcome, "reverted");

  assert.equal(undos.length, 1);
  assert.equal(undos[0].userId, "user-1");
  assert.equal(undos[0].batchId, "batch-1");
  assert.equal(undos[0].idempotencyKey, "undo-key-1");
  assert.equal(undos[0].deviceId, "agent:agent-key-1");

  assert.deepEqual(nudges, [
    { userId: "user-1", sourceDeviceId: "agent:agent-key-1", reason: "agent_write" }
  ]);
});

test("POST /agent/activity/undo-batch returns 404 for an unknown batch and does not nudge", async () => {
  const nudges = [];
  const app = createAgentActivityApp({
    agentActivityStore: {
      async listActivity() {
        throw new Error("listActivity should not be called.");
      },
      async undoBatch() {
        return { accepted: false, code: "activity_batch_not_found" };
      }
    },
    syncNudgePublisher: {
      async enqueueSyncNudge(input) {
        nudges.push(input);
        return { enqueued: true, jobId: "unexpected" };
      }
    }
  });

  const response = await postUndo(app, {
    batchId: "missing-batch",
    idempotencyKey: "undo-missing-1"
  });

  assert.equal(response.status, 404);
  const body = await response.json();
  assert.equal(body.code, "activity_batch_not_found");
  assert.deepEqual(nudges, []);
});

test(
  "agent write -> read -> undo reverts rows as a NEW ordinary batch, is idempotent, undo-of-undo works, and never hard-deletes",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-activity-user-${randomUUID()}`;
    const nudges = [];
    const app = createAgentActivityApp({
      userId,
      agentWorkoutBatchWriteStore: createDrizzleAgentWorkoutBatchWriteStore(
        database.db
      ),
      agentActivityStore: createDrizzleAgentActivityStore(database.db),
      syncNudgePublisher: {
        async enqueueSyncNudge(input) {
          nudges.push(input);
          return { enqueued: true, jobId: `nudge-${nudges.length}` };
        }
      }
    });

    const setId = uniqueSetId();
    const workoutId = uniqueWorkoutId();
    const writeBatchId = `agent-activity-write-${randomUUID()}`;
    const writeRequest = workoutBatchRequest({
      idempotencyKey: writeBatchId,
      workoutId,
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
        name: "Agent Activity User",
        email: `${userId}@example.com`,
        emailVerified: true
      });

      // 1) Agent write creates the logged set.
      const writeResponse = await postWorkoutBatch(app, writeRequest);
      assert.equal(writeResponse.status, 200);
      const liveRows = await database.sql`
        select id, deleted_at from logged_sets where id = ${setId}
      `;
      assert.equal(liveRows.length, 1);
      assert.equal(liveRows[0].deleted_at, null);

      // 2) Read the Activity Log back through the agent surface.
      const activityResponse = await getAgent(
        app,
        `/agent/activity?entityTable=logged_sets`
      );
      assert.equal(activityResponse.status, 200);
      const activityBody = await activityResponse.json();
      const writeBatch = activityBody.batches.find(
        (batch) => batch.batchId === writeBatchId
      );
      assert.ok(writeBatch, "the write batch is visible");
      assert.equal(writeBatch.actor, "agent");
      assert.equal(writeBatch.entries.length, 1);
      assert.equal(writeBatch.entries[0].entityId, setId);
      assert.equal(writeBatch.entries[0].beforeImage, null);
      assert.equal(writeBatch.entries[0].afterImage.id, setId);

      const nudgesBeforeUndo = nudges.length;

      // 3) Undo the write batch -> the set is tombstoned (archived, not purged).
      const undoBatchId = `agent-activity-undo-${randomUUID()}`;
      const undoResponse = await postUndo(app, {
        batchId: writeBatchId,
        idempotencyKey: undoBatchId
      });
      assert.equal(undoResponse.status, 200);
      const undoBody = await undoResponse.json();
      assert.equal(undoBody.accepted, true);
      assert.equal(undoBody.duplicate, false);
      assert.equal(undoBody.undoBatchId, undoBatchId);
      assert.equal(undoBody.entries.length, 3);
      assert.deepEqual(
        new Set(undoBody.entries.map((entry) => entry.entityTable)),
        new Set(["workout_sessions", "workout_exercises", "logged_sets"])
      );
      assert.ok(
        undoBody.entries.some(
          (entry) =>
            entry.entityTable === "logged_sets" &&
            entry.entityId === setId &&
            entry.outcome === "reverted"
        )
      );

      // The row is archived (soft-deleted), still present (no hard delete).
      const afterUndoRows = await database.sql`
        select id, deleted_at from logged_sets where id = ${setId}
      `;
      assert.equal(afterUndoRows.length, 1);
      assert.notEqual(afterUndoRows[0].deleted_at, null);

      // A NEW Activity Log batch was recorded for the undo.
      const undoActivityRows = await database.sql`
        select entity_table, entity_id, before_image, after_image
        from activity_log
        where batch_id = ${undoBatchId}
        order by entity_table, entity_id
      `;
      assert.equal(undoActivityRows.length, 3);
      assert.deepEqual(
        new Set(undoActivityRows.map((row) => row.entity_table)),
        new Set(["workout_sessions", "workout_exercises", "logged_sets"])
      );
      const undoneSet = undoActivityRows.find(
        (row) => row.entity_table === "logged_sets" && row.entity_id === setId
      );
      assert.ok(undoneSet);
      assert.equal(undoneSet.before_image.deleted_at, null);
      assert.notEqual(undoneSet.after_image.deleted_at, null);

      // The undo applied writes -> a sync nudge fired.
      assert.equal(nudges.length, nudgesBeforeUndo + 1);
      assert.equal(nudges[nudges.length - 1].userId, userId);
      assert.equal(
        nudges[nudges.length - 1].sourceDeviceId,
        "agent:agent-key-1"
      );

      // 4) Replaying the same undo idempotency key does not append a second batch.
      const replayResponse = await postUndo(app, {
        batchId: writeBatchId,
        idempotencyKey: undoBatchId
      });
      assert.equal(replayResponse.status, 200);
      const replayBody = await replayResponse.json();
      assert.equal(replayBody.duplicate, true);
      const undoActivityAfterReplay = await database.sql`
        select id from activity_log where batch_id = ${undoBatchId}
      `;
      assert.equal(undoActivityAfterReplay.length, 3);

      // 5) Undo-of-undo: reverting the undo batch resurrects the set.
      const undoOfUndoBatchId = `agent-activity-undo2-${randomUUID()}`;
      const undoOfUndoResponse = await postUndo(app, {
        batchId: undoBatchId,
        idempotencyKey: undoOfUndoBatchId
      });
      assert.equal(undoOfUndoResponse.status, 200);
      const undoOfUndoBody = await undoOfUndoResponse.json();
      assert.equal(undoOfUndoBody.entries.length, 3);
      assert.ok(
        undoOfUndoBody.entries.some(
          (entry) =>
            entry.entityTable === "logged_sets" &&
            entry.entityId === setId &&
            entry.outcome === "reverted"
        )
      );
      const resurrectedRows = await database.sql`
        select id, deleted_at from logged_sets where id = ${setId}
      `;
      assert.equal(resurrectedRows.length, 1);
      assert.equal(resurrectedRows[0].deleted_at, null);
    } finally {
      await database.close();
    }
  }
);

test(
  "POST /agent/activity/undo-batch surfaces a per-row skip when the current row no longer matches the after-image (LWW)",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-activity-stale-user-${randomUUID()}`;
    const app = createAgentActivityApp({
      userId,
      agentWorkoutBatchWriteStore: createDrizzleAgentWorkoutBatchWriteStore(
        database.db
      ),
      agentActivityStore: createDrizzleAgentActivityStore(database.db)
    });

    const setId = uniqueSetId();
    const workoutId = uniqueWorkoutId();
    const writeBatchId = `agent-activity-stale-write-${randomUUID()}`;
    const writeRequest = workoutBatchRequest({
      idempotencyKey: writeBatchId,
      workoutId,
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
        name: "Agent Activity Stale User",
        email: `${userId}@example.com`,
        emailVerified: true
      });

      const writeResponse = await postWorkoutBatch(app, writeRequest);
      assert.equal(writeResponse.status, 200);

      // A newer write changes the row after the write batch -> the after-image
      // no longer matches the live row, so undo must skip it (LWW conflict).
      const editRequest = workoutBatchRequest({
        idempotencyKey: `agent-activity-stale-edit-${randomUUID()}`,
        workoutId,
        sets: [
          {
            id: setId,
            exerciseName: "Back Squat",
            position: 0,
            values: {
              load: { entered: "140", unit: "kilogram" },
              reps: { entered: "5", unit: "repetition" }
            },
            updatedAt: "2026-06-24T06:00:00.000Z"
          }
        ]
      });
      const editResponse = await postWorkoutBatch(app, editRequest);
      assert.equal(editResponse.status, 200);

      const undoResponse = await postUndo(app, {
        batchId: writeBatchId,
        idempotencyKey: `agent-activity-stale-undo-${randomUUID()}`
      });
      assert.equal(undoResponse.status, 200);
      const undoBody = await undoResponse.json();
      assert.equal(undoBody.entries.length, 3);
      assert.ok(
        undoBody.entries.every((entry) => entry.outcome === "skipped_stale")
      );
      assert.ok(
        undoBody.entries.some(
          (entry) =>
            entry.entityTable === "logged_sets" && entry.entityId === setId
        )
      );

      // The stale-skipped row is untouched (still the edited value, still live).
      const rows = await database.sql`
        select payload, deleted_at from logged_sets where id = ${setId}
      `;
      assert.equal(rows[0].deleted_at, null);
      assert.equal(rows[0].payload.load_entered, "140");
    } finally {
      await database.close();
    }
  }
);

test(
  "POST /agent/activity/undo-batch is batch-atomic: any stale entry aborts the whole undo, leaving clean rows untouched and recording no new batch",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-activity-atomic-user-${randomUUID()}`;
    const nudges = [];
    const app = createAgentActivityApp({
      userId,
      agentWorkoutBatchWriteStore: createDrizzleAgentWorkoutBatchWriteStore(
        database.db
      ),
      agentActivityStore: createDrizzleAgentActivityStore(database.db),
      syncNudgePublisher: {
        async enqueueSyncNudge(input) {
          nudges.push(input);
          return { enqueued: true, jobId: `nudge-${nudges.length}` };
        }
      }
    });

    const cleanSetId = uniqueSetId();
    const staleSetId = uniqueSetId();
    const workoutId = uniqueWorkoutId();
    const writeBatchId = `agent-activity-atomic-write-${randomUUID()}`;
    const writeRequest = workoutBatchRequest({
      idempotencyKey: writeBatchId,
      workoutId,
      sets: [
        {
          id: cleanSetId,
          exerciseName: "Back Squat",
          position: 0,
          values: {
            load: { entered: "100", unit: "kilogram" },
            reps: { entered: "5", unit: "repetition" }
          },
          updatedAt: "2026-06-24T05:00:00.000Z"
        },
        {
          id: staleSetId,
          exerciseName: "Back Squat",
          position: 1,
          values: {
            load: { entered: "120", unit: "kilogram" },
            reps: { entered: "3", unit: "repetition" }
          },
          updatedAt: "2026-06-24T05:00:00.000Z"
        }
      ]
    });

    try {
      await database.db.insert(schema.user).values({
        id: userId,
        name: "Agent Activity Atomic User",
        email: `${userId}@example.com`,
        emailVerified: true
      });

      // A single batch creates two Logged Sets.
      const writeResponse = await postWorkoutBatch(app, writeRequest);
      assert.equal(writeResponse.status, 200);

      // One of the two is edited afterward, so its recorded after-image is now
      // stale — the other remains clean.
      const editResponse = await postWorkoutBatch(
        app,
        workoutBatchRequest({
          idempotencyKey: `agent-activity-atomic-edit-${randomUUID()}`,
          workoutId,
          sets: [
            {
              id: staleSetId,
              exerciseName: "Back Squat",
              position: 1,
              values: {
                load: { entered: "140", unit: "kilogram" },
                reps: { entered: "3", unit: "repetition" }
              },
              updatedAt: "2026-06-24T06:00:00.000Z"
            }
          ]
        })
      );
      assert.equal(editResponse.status, 200);

      const nudgesBeforeUndo = nudges.length;
      const undoBatchId = `agent-activity-atomic-undo-${randomUUID()}`;
      const undoResponse = await postUndo(app, {
        batchId: writeBatchId,
        idempotencyKey: undoBatchId
      });
      assert.equal(undoResponse.status, 200);
      const undoBody = await undoResponse.json();

      // Mirroring the app's undoBatch: any conflict aborts the ENTIRE undo.
      // Nothing is applied and no undo batch id is issued. The later edit
      // rewrote the Workout, Workout Exercise, and stale Set, so all three
      // conflicts are surfaced.
      assert.equal(undoBody.applied, false);
      assert.equal(undoBody.undoBatchId, null);
      assert.equal(undoBody.duplicate, false);
      assert.equal(undoBody.entries.length, 3);
      assert.ok(
        undoBody.entries.every((entry) => entry.outcome === "skipped_stale")
      );
      assert.ok(
        undoBody.entries.some(
          (entry) =>
            entry.entityTable === "logged_sets" &&
            entry.entityId === staleSetId
        )
      );

      // The clean row is left LIVE and unreverted — no straddled half-undo.
      const cleanRows = await database.sql`
        select deleted_at from logged_sets where id = ${cleanSetId}
      `;
      assert.equal(cleanRows.length, 1);
      assert.equal(cleanRows[0].deleted_at, null);

      // The stale row is untouched too (still the edited value, still live).
      const staleRows = await database.sql`
        select payload, deleted_at from logged_sets where id = ${staleSetId}
      `;
      assert.equal(staleRows[0].deleted_at, null);
      assert.equal(staleRows[0].payload.load_entered, "140");

      // No second Activity Log batch was recorded, and no sync nudge fired.
      const undoActivityRows = await database.sql`
        select id from activity_log where batch_id = ${undoBatchId}
      `;
      assert.equal(undoActivityRows.length, 0);
      assert.equal(nudges.length, nudgesBeforeUndo);
    } finally {
      await database.close();
    }
  }
);

test(
  "GET /agent/activity excludes import, monitoring-read, and Protocol idempotency bookkeeping rows",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-activity-marker-user-${randomUUID()}`;
    const app = createAgentActivityApp({
      userId,
      agentActivityStore: createDrizzleAgentActivityStore(database.db)
    });

    try {
      await database.db.insert(schema.user).values({
        id: userId,
        name: "Agent Activity Marker User",
        email: `${userId}@example.com`,
        emailVerified: true
      });

      const now = new Date("2026-06-24T05:00:00.000Z");
      // A canonical-import bookkeeping row (actor 'integration').
      await database.db.insert(schema.activityLog).values({
        id: `canonical-import-batch:${randomUUID()}`,
        userId,
        actor: "integration",
        batchId: `canonical-import-${randomUUID()}`,
        entityTable: "canonical_import_batches",
        entityId: randomUUID(),
        beforeImage: null,
        afterImage: { idempotencyKey: "ik", status: "accepted_noop" },
        occurredAt: now,
        createdAt: now
      });
      // A monitoring-read audit row — crucially actor 'agent', so it would leak
      // under the natural ?actor=agent filter if not marker-excluded.
      await database.db.insert(schema.activityLog).values({
        id: `agent-monitoring-read:${randomUUID()}`,
        userId,
        actor: "agent",
        batchId: `agent-monitoring-read:${randomUUID()}`,
        entityTable: "agent_monitoring_reads",
        entityId: randomUUID(),
        beforeImage: null,
        afterImage: { keyId: "agent-key-1", summaryReadingCount: 3 },
        occurredAt: now,
        createdAt: now
      });
      // Protocol batch receipts are actor 'agent' too, but are internal
      // concurrency/idempotency bookkeeping rather than an undoable mutation.
      const protocolBatchId = `agent-protocols-${randomUUID()}`;
      await database.db.insert(schema.activityLog).values({
        id: agentProtocolsBatchMarkerId(userId, protocolBatchId),
        userId,
        actor: "agent",
        batchId: protocolBatchId,
        entityTable: "agent_protocol_batches",
        entityId: protocolBatchId,
        beforeImage: null,
        afterImage: {
          idempotencyKey: protocolBatchId,
          kind: "doses",
          requestFingerprint: "fixture-request-fingerprint"
        },
        occurredAt: now,
        createdAt: now
      });

      // Unfiltered read surfaces neither bookkeeping row as a batch.
      const listResponse = await getAgent(app, "/agent/activity");
      assert.equal(listResponse.status, 200);
      const listBody = await listResponse.json();
      assert.equal(listBody.batches.length, 0);
      assert.equal(listBody.totalMatched, 0);

      // The natural agent filter must not surface the monitoring-read rows.
      const agentResponse = await getAgent(app, "/agent/activity?actor=agent");
      assert.equal(agentResponse.status, 200);
      const agentBody = await agentResponse.json();
      assert.equal(
        agentBody.batches.some(
          (batch) => batch.entries.length > 0
        ),
        false
      );
      assert.equal(agentBody.batches.length, 0);
    } finally {
      await database.close();
    }
  }
);

test(
  "POST /agent/activity/undo-batch cannot revert another account's batch (tenant isolation)",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const ownerId = `agent-activity-owner-${randomUUID()}`;
    const attackerId = `agent-activity-attacker-${randomUUID()}`;

    const ownerApp = createAgentActivityApp({
      userId: ownerId,
      agentWorkoutBatchWriteStore: createDrizzleAgentWorkoutBatchWriteStore(
        database.db
      ),
      agentActivityStore: createDrizzleAgentActivityStore(database.db)
    });
    const attackerApp = createAgentActivityApp({
      userId: attackerId,
      keyId: "agent-key-2",
      agentActivityStore: createDrizzleAgentActivityStore(database.db)
    });

    const setId = uniqueSetId();
    const workoutId = uniqueWorkoutId();
    const writeBatchId = `agent-activity-tenant-write-${randomUUID()}`;

    try {
      for (const [id, name] of [
        [ownerId, "Owner"],
        [attackerId, "Attacker"]
      ]) {
        await database.db.insert(schema.user).values({
          id,
          name,
          email: `${id}@example.com`,
          emailVerified: true
        });
      }

      const writeResponse = await postWorkoutBatch(
        ownerApp,
        workoutBatchRequest({
          idempotencyKey: writeBatchId,
          workoutId,
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
        })
      );
      assert.equal(writeResponse.status, 200);

      // The attacker cannot even see the owner's batch.
      const attackerListResponse = await getAgent(attackerApp, "/agent/activity");
      assert.equal(attackerListResponse.status, 200);
      const attackerList = await attackerListResponse.json();
      assert.equal(
        attackerList.batches.some((batch) => batch.batchId === writeBatchId),
        false
      );

      // The attacker's undo of the owner's batch is a 404 (not found in scope),
      // and must not touch the owner's row.
      const attackerUndo = await postUndo(attackerApp, {
        batchId: writeBatchId,
        idempotencyKey: `agent-activity-tenant-undo-${randomUUID()}`
      });
      assert.equal(attackerUndo.status, 404);

      const rows = await database.sql`
        select id, deleted_at from logged_sets where id = ${setId}
      `;
      assert.equal(rows.length, 1);
      assert.equal(rows[0].deleted_at, null);
    } finally {
      await database.close();
    }
  }
);

function createAgentActivityApp({
  agentActivityStore,
  agentWorkoutBatchWriteStore,
  syncNudgePublisher,
  logger = { info() {}, error() {} },
  userId = "user-1",
  keyId = "agent-key-1"
}) {
  return createApp({
    logger,
    agentApiKeyStore: createAgentKeyStore(userId, keyId),
    agentCatalogStore: createInMemoryAgentCatalogStore(catalogFixtures(userId)),
    agentActivityStore,
    agentWorkoutBatchWriteStore,
    syncNudgePublisher
  });
}

function createAgentKeyStore(userId, keyId = "agent-key-1") {
  return {
    async authenticateAgentApiKey(secret) {
      if (secret !== "prn_agent_secret") {
        return null;
      }

      return {
        userId,
        keyId,
        keyName: "Garage coach"
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

function postUndo(app, body, headers = {}) {
  return app.request("/agent/activity/undo-batch", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_agent_secret",
      "content-type": "application/json",
      ...headers
    },
    body: JSON.stringify(body)
  });
}

function postWorkoutBatch(app, body, headers = {}) {
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

// Unique per-run entity ids so re-running the suite against a reused (non
// ephemeral) database never collides on a client PK, which would otherwise trip
// tenant isolation and skip the write. CI's ephemeral Postgres does not need
// this, but local `pnpm test` reuses one database across runs.
function uniqueSetId() {
  return `018f6a90-6d7f-7d63-bfc1-${randomUUID().replace(/-/g, "").slice(0, 12)}`;
}

function uniqueWorkoutId() {
  return `018f6a90-6d7f-7d63-bfc2-${randomUUID().replace(/-/g, "").slice(0, 12)}`;
}

function workoutBatchRequest({ idempotencyKey, workoutId, sets }) {
  return {
    idempotencyKey,
    workout: {
      id: workoutId,
      startedAt: "2026-06-24T05:00:00.000Z",
      endedAt: null,
      timezone: "Australia/Brisbane",
      comment: null
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
