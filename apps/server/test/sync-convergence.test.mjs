import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { inArray } from "drizzle-orm";

import { createApp, createMigratedServerApp, schema } from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;
const protocolVersion = 1;
const entity = "logged_sets";
const scenarioSeed = 0x5eed2026;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error(
    "DATABASE_URL must be set for sync convergence simulation tests."
  );
}

test("seeded replicas converge without data loss across conflicts, tombstones, and full resync", async () => {
  const server = await createConvergenceServer();
  const rng = createPrng(scenarioSeed);
  const sharedSetId = randomUUID();
  const tombstonedSetId = randomUUID();
  const aOnlySetId = randomUUID();
  const cOnlySetId = randomUUID();

  try {
    const replicaA = new SimulatedReplica({
      name: "Replica A",
      deviceId: "device-a",
      server
    });
    const replicaB = new SimulatedReplica({
      name: "Replica B",
      deviceId: "device-b",
      server
    });
    const replicaC = new SimulatedReplica({
      name: "Replica C",
      deviceId: "device-c",
      server
    });
    const replicas = [replicaA, replicaB, replicaC];

    replicaA.writeLive({
      id: sharedSetId,
      repsEntered: "5",
      updatedAt: "2026-06-22T08:00:00.000Z",
      writeId: "baseline-shared"
    });
    replicaA.writeLive({
      id: tombstonedSetId,
      repsEntered: "10",
      updatedAt: "2026-06-22T08:00:01.000Z",
      writeId: "baseline-delete-target"
    });
    await settleReplicas(replicas, rng);

    replicaA.writeLive({
      id: sharedSetId,
      repsEntered: "6",
      updatedAt: "2026-06-22T09:00:00.000Z",
      writeId: "losing-conflict-edit"
    });
    replicaB.writeLive({
      id: sharedSetId,
      repsEntered: "7",
      updatedAt: "2026-06-22T09:00:00.000Z",
      writeId: "winning-conflict-edit"
    });
    replicaB.writeLive({
      id: tombstonedSetId,
      repsEntered: "11",
      updatedAt: "2026-06-22T09:05:00.000Z",
      writeId: "stale-live-edit"
    });
    replicaA.deleteRow({
      id: tombstonedSetId,
      updatedAt: "2026-06-22T09:10:00.000Z",
      writeId: "winning-tombstone"
    });
    replicaA.writeLive({
      id: aOnlySetId,
      repsEntered: "12",
      updatedAt: "2026-06-22T09:20:00.000Z",
      writeId: "a-only-live"
    });
    replicaC.writeLive({
      id: cOnlySetId,
      repsEntered: "13",
      updatedAt: "2026-06-22T09:30:00.000Z",
      writeId: "c-only-live"
    });

    for (const replica of seededShuffle([replicaA, replicaB], rng)) {
      await replica.pushPending();
    }

    replicaC.cursor = "2000-01-01T00:00:00.000Z|expired-row";
    await replicaC.pullUntilSettled({ limit: 2 });
    assert.equal(replicaC.fullResyncCount, 1);

    await settleReplicas(replicas, rng);

    const observer = new SimulatedReplica({
      name: "Observer",
      deviceId: "device-observer",
      server
    });
    await observer.pullSnapshot({ limit: 2 });

    const finalState = observer.liveStateSignature();
    assert.notEqual(finalState, "[]");
    assert.deepEqual(
      replicas.map((replica) => replica.liveStateSignature()),
      [finalState, finalState, finalState]
    );

    const liveRows = observer.liveRowsById();
    assert.equal(liveRows.get(sharedSetId).payload.reps_entered, "7");
    assert.equal(
      liveRows.get(sharedSetId).payload.client_write_id,
      "winning-conflict-edit"
    );
    assert.equal(liveRows.get(aOnlySetId).payload.client_write_id, "a-only-live");
    assert.equal(liveRows.get(cOnlySetId).payload.client_write_id, "c-only-live");
    assert.equal(liveRows.has(tombstonedSetId), false);

    for (const replica of replicas) {
      assert.equal(replica.pending.length, 0, `${replica.name} has no pending writes`);
      assert.equal(
        replica.rows.get(tombstonedSetId)?.deletedAt !== null,
        true,
        `${replica.name} kept the tombstone instead of resurrecting stale live data`
      );
    }

    assertConflictLoser(replicaA, {
      writeId: "losing-conflict-edit",
      winningWriteId: "winning-conflict-edit"
    });
    assertConflictLoser(replicaB, {
      writeId: "stale-live-edit",
      winningWriteId: "winning-tombstone"
    });
    assert.equal(replicaC.rows.get(tombstonedSetId).deletedAt !== null, true);
  } finally {
    await server.close();
  }
});

test(
  "plan-tree replicas converge across every entity, membership races, archives, and tenant attacks",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const server = await createConvergenceServer();
    assert.notEqual(server.database, null);

    try {
      const otherUser = await createSignedInUser({
        database: server.database
      });
      const otherUserServer = {
        ...server,
        sessionToken: otherUser.sessionToken
      };
      const concurrentRows = planTreeRows(
        createPlanTreeIds(),
        "2026-07-01T08:00:00.000Z",
        "concurrent"
      );
      const archiveRaceRows = planTreeRows(
        createPlanTreeIds(),
        "2026-07-01T08:00:00.000Z",
        "archive-race"
      );
      const replicaA = new PlanTreeReplica({
        name: "Plan Replica A",
        deviceId: "device-a",
        server
      });
      const replicaB = new PlanTreeReplica({
        name: "Plan Replica B",
        deviceId: "device-b",
        server
      });
      const replicaC = new PlanTreeReplica({
        name: "Plan Replica C",
        deviceId: "device-c",
        server
      });
      const replicas = [replicaA, replicaB, replicaC];

      for (const row of [...concurrentRows, ...archiveRaceRows]) {
        replicaA.writeRow({
          row,
          updatedAt: row.payload.updated_at,
          revision: "baseline"
        });
      }
      await settlePlanReplicas(replicas);

      // Upsert-by-client-primary-key must not let another tenant claim any
      // plan entity, even when its incoming clock is newer.
      for (const row of concurrentRows) {
        const response = await syncRequest(otherUserServer, "/sync/push", {
          protocolVersion,
          deviceId: "device-other-user",
          entity: row.entity,
          changes: [
            planChange({
              row,
              updatedAt: "2026-07-01T09:00:00.000Z",
              revision: "tenant-hijack"
            })
          ]
        });
        assert.deepEqual(response.accepted, [], row.entity);
      }
      const otherUserPull = await syncRequest(otherUserServer, "/sync/pull", {
        protocolVersion,
        cursor: null,
        limit: 100
      });
      assert.deepEqual(otherUserPull.changes, []);

      // Every plan entity receives equal-clock edits from two offline
      // replicas. The device-id tiebreak makes device B the stable winner.
      const loserActivityIds = [];
      for (const row of concurrentRows) {
        const activityLogId = randomUUID();
        loserActivityIds.push(activityLogId);
        replicaA.writeRow({
          row,
          updatedAt: "2026-07-01T10:00:00.000Z",
          revision: "losing-device-a",
          activityLogId
        });
        replicaB.writeRow({
          row,
          updatedAt: "2026-07-01T10:00:00.000Z",
          revision: "winning-device-b"
        });
      }

      // Concurrent membership additions have distinct identity, so neither
      // can overwrite the other even though both target the same Routine.
      const routineRow = concurrentRows.find(
        (row) => row.entity === "routines"
      );
      const templateRow = concurrentRows.find(
        (row) => row.entity === "workout_templates"
      );
      assert.notEqual(routineRow, undefined);
      assert.notEqual(templateRow, undefined);
      const membershipA = routineEntryRow({
        id: randomUUID(),
        routineId: routineRow.id,
        workoutTemplateId: templateRow.id,
        position: 1,
        slot: 3,
        updatedAt: "2026-07-01T10:05:00.000Z"
      });
      const membershipB = routineEntryRow({
        id: randomUUID(),
        routineId: routineRow.id,
        workoutTemplateId: templateRow.id,
        position: 2,
        slot: 5,
        updatedAt: "2026-07-01T10:05:00.000Z"
      });
      replicaA.writeRow({
        row: membershipA,
        updatedAt: membershipA.payload.updated_at,
        revision: "membership-a"
      });
      replicaB.writeRow({
        row: membershipB,
        updatedAt: membershipB.payload.updated_at,
        revision: "membership-b"
      });

      // Push the deterministic winner first so every later losing replay is
      // also retained by the server Activity Log.
      await replicaB.pushPending();
      await replicaA.pushPending();
      await settlePlanReplicas(replicas);

      for (const row of concurrentRows) {
        assert.equal(
          replicaC.row(row.entity, row.id)?.payload.revision,
          "winning-device-b",
          row.entity
        );
      }
      assertRoutineMembership(replicaC, membershipA);
      assertRoutineMembership(replicaC, membershipB);

      // A second complete tree exercises edit-vs-archive races on every plan
      // entity. Equal clocks still choose device B, this time preserving all
      // eight tombstones instead of resurrecting Replica A's live edits.
      for (const row of archiveRaceRows) {
        const activityLogId = randomUUID();
        loserActivityIds.push(activityLogId);
        replicaA.writeRow({
          row,
          updatedAt: "2026-07-01T11:00:00.000Z",
          revision: "losing-live-edit",
          activityLogId
        });
        replicaB.writeRow({
          row,
          updatedAt: "2026-07-01T11:00:00.000Z",
          revision: "winning-archive",
          deletedAt: "2026-07-01T11:00:00.000Z"
        });
      }
      await replicaB.pushPending();
      await replicaA.pushPending();
      await settlePlanReplicas(replicas);

      for (const row of archiveRaceRows) {
        const observed = replicaC.row(row.entity, row.id);
        assert.notEqual(observed, undefined, row.entity);
        assert.notEqual(observed.deletedAt, null, row.entity);
      }

      // Archiving only the two authored roots must not cascade into their
      // exercises, prescriptions, groups, membership, entries, or provenance.
      for (const entityName of ["workout_templates", "routines"]) {
        const row = concurrentRows.find(
          (candidate) => candidate.entity === entityName
        );
        const activityLogId = randomUUID();
        loserActivityIds.push(activityLogId);
        replicaA.writeRow({
          row,
          updatedAt: "2026-07-01T12:00:00.000Z",
          revision: "losing-root-edit",
          activityLogId
        });
        replicaB.writeRow({
          row,
          updatedAt: "2026-07-01T12:00:00.000Z",
          revision: "winning-root-archive",
          deletedAt: "2026-07-01T12:00:00.000Z"
        });
      }
      await replicaB.pushPending();
      await replicaA.pushPending();
      await settlePlanReplicas(replicas);

      const observer = new PlanTreeReplica({
        name: "Plan Observer",
        deviceId: "device-observer",
        server
      });
      await observer.pullUntilSettled({ limit: 3 });
      const finalState = observer.stateSignature();
      assert.deepEqual(
        replicas.map((replica) => replica.stateSignature()),
        [finalState, finalState, finalState]
      );

      for (const row of concurrentRows) {
        const observed = observer.row(row.entity, row.id);
        assert.notEqual(observed, undefined, row.entity);
        if (row.entity === "workout_templates" || row.entity === "routines") {
          assert.notEqual(observed.deletedAt, null, row.entity);
        } else {
          assert.equal(observed.deletedAt, null, row.entity);
        }
      }
      assertRoutineMembership(observer, membershipA);
      assertRoutineMembership(observer, membershipB);

      const loserActivity = await server.database.db
        .select()
        .from(schema.activityLog)
        .where(inArray(schema.activityLog.id, loserActivityIds));
      assert.equal(loserActivity.length, loserActivityIds.length);
      assert.deepEqual(
        new Set(loserActivity.map((entry) => entry.id)),
        new Set(loserActivityIds)
      );
      assert.ok(
        loserActivity.every(
          (entry) =>
            entry.beforeImage !== null &&
            typeof entry.afterImage?.revision === "string"
        )
      );
    } finally {
      await server.close();
    }
  }
);

async function createConvergenceServer() {
  if (databaseUrl) {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const { sessionToken } = await createSignedInUser(serverApp);
    return {
      app: serverApp.app,
      sessionToken,
      database: serverApp.database,
      close: () => serverApp.database.close()
    };
  }

  const sessionToken = "session-token";
  const syncStore = new InMemorySyncStore({
    sessionToken,
    userId: "user-1"
  });
  return {
    app: createApp({
      logger: { info() {}, error() {} },
      syncStore
    }),
    sessionToken,
    database: null,
    close: async () => {}
  };
}

async function createSignedInUser(serverApp) {
  const userId = `user-${randomUUID()}`;
  const sessionToken = `session-${randomUUID()}`;

  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: "Sync Convergence User",
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

class SyncReplicaHarness {
  constructor({ name, deviceId, server, entityOrder, keyFor }) {
    this.name = name;
    this.deviceId = deviceId;
    this.server = server;
    this.entityOrder = [...entityOrder];
    this.keyFor = keyFor;
    this.cursor = null;
    this.rows = new Map();
    this.pending = [];
  }

  row(entityName, id) {
    return this.rows.get(this.keyFor(entityName, id));
  }

  stageChange(entityName, change) {
    this.rows.set(
      this.keyFor(entityName, change.id),
      syncReplicaRow({
        entityName,
        change,
        deviceId: this.deviceId,
        previouslySynced: false
      })
    );
    this.pending.push({ entity: entityName, change });
  }

  async pushPending() {
    const pendingEntities = [
      ...new Set(this.pending.map((pending) => pending.entity))
    ].sort(
      (left, right) =>
        this.entityOrder.indexOf(left) - this.entityOrder.indexOf(right)
    );

    for (const entityName of pendingEntities) {
      const changes = this.pending
        .filter((pending) => pending.entity === entityName)
        .map((pending) => pending.change);
      const response = await syncRequest(this.server, "/sync/push", {
        protocolVersion,
        deviceId: this.deviceId,
        entity: entityName,
        changes
      });
      const acceptedIds = new Set(response.accepted);
      this.pending = this.pending.filter(
        (pending) =>
          pending.entity !== entityName || !acceptedIds.has(pending.change.id)
      );

      for (const id of acceptedIds) {
        const row = this.row(entityName, id);
        if (row !== undefined) {
          row.previouslySynced = true;
        }
      }
      for (const applied of response.applied) {
        const row = this.row(entityName, applied.id);
        if (row !== undefined) {
          row.deviceId = applied.deviceId;
          row.updatedAt = applied.updatedAt;
          row.payload = {
            ...row.payload,
            updated_at: applied.updatedAt
          };
        }
      }
    }
  }

  async pullUntilSettled({ limit = 100 } = {}) {
    while (true) {
      const response = await syncRequest(this.server, "/sync/pull", {
        protocolVersion,
        cursor: this.cursor,
        limit
      });

      if (response.fullResyncRequired) {
        await this.performFullResync({ limit });
        return;
      }

      for (const change of response.changes) {
        this.applyPulledChange(change);
      }
      this.cursor = response.nextCursor;
      if (response.changes.length === 0) {
        return;
      }
    }
  }

  async performFullResync() {
    assert.fail(`${this.name} unexpectedly required a full resync`);
  }

  applyPulledChange(change) {
    if (!this.entityOrder.includes(change.entity)) {
      return;
    }
    const incoming = syncReplicaRow({
      entityName: change.entity,
      change,
      deviceId: change.deviceId,
      previouslySynced: true
    });
    const key = this.keyFor(change.entity, change.id);
    const existing = this.rows.get(key);

    if (
      existing !== undefined &&
      !lwwWins(
        incoming.updatedAt,
        incoming.deviceId,
        existing.updatedAt,
        existing.deviceId
      )
    ) {
      return;
    }

    if (existing !== undefined && !sameReplicaRow(existing, incoming)) {
      this.recordConflict(change, existing, incoming);
    }
    this.rows.set(key, incoming);
  }

  recordConflict() {}
}

class SimulatedReplica extends SyncReplicaHarness {
  constructor({ name, deviceId, server }) {
    super({
      name,
      deviceId,
      server,
      entityOrder: [entity],
      keyFor: (_entityName, id) => id
    });
    this.fullResyncCount = 0;
    this.conflictLog = [];
  }

  writeLive({ id, repsEntered, updatedAt, writeId }) {
    const change = {
      id,
      payload: loggedSetPayload({
        id,
        repsEntered,
        updatedAt,
        deletedAt: null,
        writeId
      }),
      updatedAt,
      deletedAt: null
    };
    this.stageChange(entity, change);
  }

  deleteRow({ id, updatedAt, writeId }) {
    const existing = this.rows.get(id);
    assert.notEqual(existing, undefined, `${this.name} cannot delete unknown row ${id}`);
    const change = {
      id,
      payload: loggedSetPayload({
        id,
        repsEntered: existing.payload.reps_entered,
        updatedAt,
        deletedAt: updatedAt,
        writeId
      }),
      updatedAt,
      deletedAt: updatedAt
    };
    this.stageChange(entity, change);
  }

  async performFullResync({ limit = 100 } = {}) {
    this.fullResyncCount += 1;
    await this.pushPending();
    await this.pullSnapshot({ limit });
  }

  async pullSnapshot({ limit = 100 } = {}) {
    const liveSnapshotIds = new Set();
    let snapshotCursor = null;
    let nextCursor = null;
    let serverClock = null;

    while (true) {
      const response = await syncRequest(this.server, "/sync/pull", {
        protocolVersion,
        cursor: snapshotCursor,
        limit,
        mode: "snapshot"
      });
      assert.equal(response.fullResyncRequired, false);

      for (const change of response.changes) {
        liveSnapshotIds.add(change.id);
        this.applyPulledChange(change);
      }

      nextCursor = response.nextCursor;
      serverClock = response.serverClock;
      if (response.changes.length === 0) {
        break;
      }
      assert.notEqual(response.nextCursor, snapshotCursor);
      snapshotCursor = response.nextCursor;
    }

    assert.notEqual(serverClock, null);
    for (const row of this.rows.values()) {
      if (
        row.previouslySynced &&
        row.deletedAt === null &&
        !liveSnapshotIds.has(row.id)
      ) {
        row.updatedAt = serverClock;
        row.deletedAt = serverClock;
        row.payload = {
          ...row.payload,
          updated_at: serverClock,
          deleted_at: serverClock
        };
      }
    }
    this.cursor = nextCursor;
  }

  recordConflict(change, existing, incoming) {
    this.conflictLog.push({
      id: change.id,
      before: cloneRow(existing),
      after: cloneRow(incoming)
    });
  }

  liveRowsById() {
    return new Map(
      [...this.rows.entries()].filter(([, row]) => row.deletedAt === null)
    );
  }

  liveStateSignature() {
    return JSON.stringify(
      [...this.liveRowsById().values()]
        .map((row) => ({
          id: row.id,
          deviceId: row.deviceId,
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          payload: canonicalize(row.payload)
        }))
        .sort((left, right) => left.id.localeCompare(right.id))
    );
  }
}

class PlanTreeReplica extends SyncReplicaHarness {
  constructor({ name, deviceId, server }) {
    super({
      name,
      deviceId,
      server,
      entityOrder: planEntityOrder,
      keyFor: planRowKey
    });
  }

  writeRow({ row, updatedAt, revision, deletedAt = null, activityLogId }) {
    const existing = this.row(row.entity, row.id);
    const payload = {
      ...(existing?.payload ?? row.payload),
      revision,
      updated_at: updatedAt,
      deleted_at: deletedAt
    };
    const change = {
      id: row.id,
      payload,
      updatedAt,
      deletedAt
    };
    if (activityLogId !== undefined) {
      Object.assign(change, {
        activityLogId,
        actor: "app",
        batchId: "per-302-plan-convergence",
        beforeImage: existing?.payload ?? row.payload,
        afterImage: payload,
        occurredAt: updatedAt
      });
    }

    this.stageChange(row.entity, change);
  }

  stateSignature() {
    return JSON.stringify(
      [...this.rows.values()]
        .map((row) => ({
          entity: row.entity,
          id: row.id,
          deviceId: row.deviceId,
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          payload: canonicalize(row.payload)
        }))
        .sort((left, right) =>
          `${left.entity}:${left.id}`.localeCompare(
            `${right.entity}:${right.id}`
          )
        )
    );
  }
}

class InMemorySyncStore {
  constructor({ sessionToken, userId }) {
    this.sessionToken = sessionToken;
    this.userId = userId;
    this.rows = new Map();
    this.tick = 0;
  }

  async verifyBearerToken(token) {
    return token === this.sessionToken ? { userId: this.userId } : null;
  }

  async pushLoggedSets({ userId, deviceId, changes }) {
    const serverClock = this.nextServerClock();
    const accepted = [];
    const applied = [];

    for (const change of changes) {
      const updatedAt = normalizeIncomingUpdatedAt(
        new Date(change.updatedAt),
        serverClock
      );
      const deletedAt =
        change.deletedAt === null ? null : new Date(change.deletedAt);
      const existing = this.rows.get(change.id);

      if (existing !== undefined && existing.userId !== userId) {
        continue;
      }
      if (
        existing !== undefined &&
        !lwwWins(
          updatedAt.toISOString(),
          deviceId,
          existing.updatedAt,
          existing.deviceId
        )
      ) {
        accepted.push(change.id);
        continue;
      }

      const row = {
        id: change.id,
        userId,
        deviceId,
        payload: syncPayloadClock(change.payload, updatedAt, deletedAt),
        updatedAt: updatedAt.toISOString(),
        deletedAt: deletedAt?.toISOString() ?? null,
        receivedAt: serverClock.toISOString()
      };
      this.rows.set(change.id, row);
      accepted.push(change.id);
      applied.push({
        id: change.id,
        updatedAt: row.updatedAt,
        deviceId
      });
    }

    return {
      accepted,
      applied,
      serverClock: serverClock.toISOString()
    };
  }

  async pullChanges({ userId, cursor, limit, mode }) {
    const serverClock = this.nextServerClock();
    const cursorPosition = cursor === null ? null : decodeCursor(cursor);

    if (
      mode === "delta" &&
      cursorPosition !== null &&
      cursorPosition.receivedAt.getTime() <
        serverClock.getTime() - 180 * 24 * 60 * 60 * 1000
    ) {
      return {
        fullResyncRequired: true,
        changes: [],
        nextCursor: cursor,
        serverClock: serverClock.toISOString()
      };
    }

    const rows = [...this.rows.values()]
      .filter((row) => row.userId === userId)
      .filter((row) => mode !== "snapshot" || row.deletedAt === null)
      .filter((row) => cursorPosition === null || rowAfterCursor(row, cursorPosition))
      .sort(compareByReceivedAtThenId)
      .slice(0, limit);
    const lastRow = rows.at(-1);

    return {
      fullResyncRequired: false,
      changes: rows.map((row) => ({
        entity,
        id: row.id,
        deviceId: row.deviceId,
        payload: syncPayloadClock(
          row.payload,
          new Date(row.updatedAt),
          row.deletedAt === null ? null : new Date(row.deletedAt)
        ),
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt
      })),
      nextCursor:
        lastRow === undefined ? cursor : encodeCursor(lastRow.receivedAt, lastRow.id),
      serverClock: serverClock.toISOString()
    };
  }

  nextServerClock() {
    const timestamp = new Date(Date.UTC(2026, 5, 22, 13, 0, this.tick));
    this.tick += 1;
    return timestamp;
  }
}

async function settleReplicas(replicas, rng) {
  for (const replica of seededShuffle(replicas, rng)) {
    await replica.pushPending();
  }
  for (const replica of seededShuffle(replicas, rng)) {
    await replica.pullUntilSettled({ limit: 2 });
  }
}

async function settlePlanReplicas(replicas) {
  for (const replica of replicas) {
    await replica.pushPending();
  }
  for (const replica of replicas) {
    await replica.pullUntilSettled({ limit: 3 });
  }
}

async function syncRequest(server, path, body) {
  const response = await server.app.request(path, {
    method: "POST",
    headers: {
      authorization: `Bearer ${server.sessionToken}`,
      "content-type": "application/json"
    },
    body: JSON.stringify(body)
  });
  assert.equal(response.status, 200, `${path} returned ${response.status}`);
  return response.json();
}

function assertConflictLoser(replica, { writeId, winningWriteId }) {
  const entry = replica.conflictLog.find(
    (candidate) => candidate.before.payload.client_write_id === writeId
  );
  assert.notEqual(
    entry,
    undefined,
    `${replica.name} did not record conflict loser ${writeId}`
  );
  assert.equal(entry.after.payload.client_write_id, winningWriteId);
}

function assertRoutineMembership(replica, expected) {
  const observed = replica.row("routine_entries", expected.id);
  assert.notEqual(
    observed,
    undefined,
    `${replica.name} is missing Routine Entry ${expected.id}`
  );
  assert.equal(observed.deletedAt, null);
  assert.equal(observed.payload.position, expected.payload.position);
  assert.equal(observed.payload.slot, expected.payload.slot);
}

function loggedSetPayload({ id, repsEntered, updatedAt, deletedAt, writeId }) {
  return {
    id,
    workout_id: "018f6a90-6d7f-7d63-bfc1-6f1025e0c010",
    exercise_id: "018f6a90-6d7f-7d63-bfc1-6f1025e0c020",
    position: 0,
    reps_value: Number.parseInt(repsEntered, 10),
    reps_unit: "rep",
    reps_entered: repsEntered,
    is_completed: false,
    client_write_id: writeId,
    updated_at: updatedAt,
    deleted_at: deletedAt
  };
}

const planEntityOrder = [
  "workout_templates",
  "template_exercises",
  "prescriptions",
  "template_groups",
  "template_group_members",
  "routines",
  "routine_entries",
  "template_links"
];

function createPlanTreeIds() {
  return {
    workoutTemplate: randomUUID(),
    templateExercise: randomUUID(),
    prescription: randomUUID(),
    templateGroup: randomUUID(),
    templateGroupMember: randomUUID(),
    routine: randomUUID(),
    routineEntry: randomUUID(),
    templateLink: randomUUID(),
    workout: randomUUID(),
    exercise: randomUUID()
  };
}

function planTreeRows(ids, updatedAt, label) {
  return [
    {
      entity: "workout_templates",
      id: ids.workoutTemplate,
      payload: planImage(ids.workoutTemplate, updatedAt, {
        name: `${label} Template`,
        notes: null
      })
    },
    {
      entity: "template_exercises",
      id: ids.templateExercise,
      payload: planImage(ids.templateExercise, updatedAt, {
        workout_template_id: ids.workoutTemplate,
        exercise_id: ids.exercise,
        position: 0,
        note: null
      })
    },
    {
      entity: "prescriptions",
      id: ids.prescription,
      payload: planImage(ids.prescription, updatedAt, {
        template_exercise_id: ids.templateExercise,
        mode: "fixed",
        position: 0,
        repeat: 3,
        rest_after: 120,
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
      })
    },
    {
      entity: "template_groups",
      id: ids.templateGroup,
      payload: planImage(ids.templateGroup, updatedAt, {
        workout_template_id: ids.workoutTemplate,
        name: `${label} Group`,
        color_hex: "#4A8FE0",
        rounds: 3,
        position: 0
      })
    },
    {
      entity: "template_group_members",
      id: ids.templateGroupMember,
      payload: planImage(ids.templateGroupMember, updatedAt, {
        group_id: ids.templateGroup,
        template_exercise_id: ids.templateExercise,
        position: 0
      })
    },
    {
      entity: "routines",
      id: ids.routine,
      payload: planImage(ids.routine, updatedAt, {
        name: `${label} Routine`,
        notes: null,
        cadence_kind: "weekly",
        cadence_window: 7
      })
    },
    routineEntryRow({
      id: ids.routineEntry,
      routineId: ids.routine,
      workoutTemplateId: ids.workoutTemplate,
      position: 0,
      slot: 1,
      updatedAt
    }),
    {
      entity: "template_links",
      id: ids.templateLink,
      payload: planImage(ids.templateLink, updatedAt, {
        workout_id: ids.workout,
        workout_template_id: ids.workoutTemplate,
        routine_id: ids.routine,
        slot: 1
      })
    }
  ];
}

function routineEntryRow({
  id,
  routineId,
  workoutTemplateId,
  position,
  slot,
  updatedAt
}) {
  return {
    entity: "routine_entries",
    id,
    payload: planImage(id, updatedAt, {
      routine_id: routineId,
      workout_template_id: workoutTemplateId,
      position,
      slot
    })
  };
}

function planImage(id, updatedAt, fields) {
  return {
    id,
    ...fields,
    updated_at: updatedAt,
    deleted_at: null
  };
}

function planChange({ row, updatedAt, revision, deletedAt = null }) {
  return {
    id: row.id,
    payload: {
      ...row.payload,
      revision,
      updated_at: updatedAt,
      deleted_at: deletedAt
    },
    updatedAt,
    deletedAt
  };
}

function planRowKey(entityName, id) {
  return `${entityName}:${id}`;
}

function syncReplicaRow({
  entityName,
  change,
  deviceId,
  previouslySynced
}) {
  return {
    entity: entityName,
    id: change.id,
    deviceId,
    payload: { ...change.payload },
    updatedAt: change.updatedAt,
    deletedAt: change.deletedAt,
    previouslySynced
  };
}

function sameReplicaRow(left, right) {
  return (
    JSON.stringify({
      deviceId: left.deviceId,
      updatedAt: left.updatedAt,
      deletedAt: left.deletedAt,
      payload: canonicalize(left.payload)
    }) ===
    JSON.stringify({
      deviceId: right.deviceId,
      updatedAt: right.updatedAt,
      deletedAt: right.deletedAt,
      payload: canonicalize(right.payload)
    })
  );
}

function cloneRow(row) {
  return {
    ...row,
    payload: { ...row.payload }
  };
}

function lwwWins(incomingUpdatedAt, incomingDeviceId, existingUpdatedAt, existingDeviceId) {
  const timestampComparison =
    new Date(incomingUpdatedAt).getTime() - new Date(existingUpdatedAt).getTime();
  if (timestampComparison !== 0) {
    return timestampComparison > 0;
  }

  return incomingDeviceId > existingDeviceId;
}

function normalizeIncomingUpdatedAt(updatedAt, serverClock) {
  const maxAcceptedTime = serverClock.getTime() + 5 * 60 * 1000;
  return updatedAt.getTime() > maxAcceptedTime ? serverClock : updatedAt;
}

function syncPayloadClock(payload, updatedAt, deletedAt) {
  return {
    ...payload,
    updated_at: updatedAt.toISOString(),
    deleted_at: deletedAt?.toISOString() ?? null
  };
}

function canonicalize(value) {
  if (Array.isArray(value)) {
    return value.map(canonicalize);
  }
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, child]) => [key, canonicalize(child)])
    );
  }
  return value;
}

function encodeCursor(receivedAt, id) {
  return `${new Date(receivedAt).toISOString()}|${id}`;
}

function decodeCursor(cursor) {
  const separatorIndex = cursor.indexOf("|");
  assert.notEqual(separatorIndex, -1);
  return {
    receivedAt: new Date(cursor.slice(0, separatorIndex)),
    id: cursor.slice(separatorIndex + 1)
  };
}

function rowAfterCursor(row, cursor) {
  const receivedAt = new Date(row.receivedAt);
  if (receivedAt.getTime() !== cursor.receivedAt.getTime()) {
    return receivedAt > cursor.receivedAt;
  }
  return row.id > cursor.id;
}

function compareByReceivedAtThenId(left, right) {
  const receivedAtComparison =
    new Date(left.receivedAt).getTime() - new Date(right.receivedAt).getTime();
  if (receivedAtComparison !== 0) {
    return receivedAtComparison;
  }
  return left.id.localeCompare(right.id);
}

function createPrng(seed) {
  let state = seed >>> 0;
  return () => {
    state += 0x6d2b79f5;
    let value = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

function seededShuffle(items, rng) {
  const shuffled = [...items];
  for (let index = shuffled.length - 1; index > 0; index -= 1) {
    const swapIndex = Math.floor(rng() * (index + 1));
    [shuffled[index], shuffled[swapIndex]] = [
      shuffled[swapIndex],
      shuffled[index]
    ];
  }
  return shuffled;
}
