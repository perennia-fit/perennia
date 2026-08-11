import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { eq } from "drizzle-orm";

import { createMigratedServerApp, schema } from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error(
    "DATABASE_URL must be set for server Postgres integration tests."
  );
}

const skip = databaseUrl ? false : "DATABASE_URL is not set.";

test(
  "Compound and Dose round-trip as LWW opaque rows, with the Dose " +
    "self-contained and tenant-isolated on push",
  { skip },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });

    try {
      const userA = await createSignedInUser(serverApp);
      const userB = await createSignedInUser(serverApp);
      const compoundId = randomUUID();
      const doseId = randomUUID();
      // Past timestamps so the server never clamps them to its wall-clock
      // serverClock (MAX_FUTURE_CLOCK_SKEW_MS); relative LWW ordering stays
      // honest regardless of when the test runs.
      const updatedAt = "2025-06-30T08:00:00.000Z";

      // User A pushes a Compound (catalogue) and a self-describing Dose.
      const pushCompound = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "compounds",
        changes: [
          {
            id: compoundId,
            payload: compoundPayload(compoundId, updatedAt),
            updatedAt,
            deletedAt: null
          }
        ]
      });
      assert.equal(pushCompound.status, 200);
      assert.deepEqual((await pushCompound.json()).accepted, [compoundId]);

      const pushDose = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "doses",
        changes: [
          {
            id: doseId,
            payload: dosePayload(doseId, updatedAt),
            updatedAt,
            deletedAt: null
          }
        ]
      });
      assert.equal(pushDose.status, 200);
      assert.deepEqual((await pushDose.json()).accepted, [doseId]);

      // TENANT ISOLATION: user B cannot overwrite user A's rows keyed by the
      // same client PK. The push reports accepted (idempotent no-op) but the
      // stored row keeps user A's payload + ownership.
      const crossUserUpdatedAt = "2025-06-30T10:00:00.000Z";
      const crossPush = await syncPush(serverApp.app, userB.sessionToken, {
        deviceId: "device-b",
        entity: "doses",
        changes: [
          {
            id: doseId,
            payload: {
              ...dosePayload(doseId, crossUserUpdatedAt),
              compound_name: "Hijacked"
            },
            updatedAt: crossUserUpdatedAt,
            deletedAt: null
          }
        ]
      });
      assert.equal(crossPush.status, 200);

      const storedDose = await serverApp.database.db
        .select()
        .from(schema.doses)
        .where(eqId(schema.doses.id, doseId));
      assert.equal(storedDose.length, 1);
      assert.equal(storedDose[0].userId, userA.userId);
      assert.equal(storedDose[0].payload.compound_name, "Vitamin D");

      // User A pulls back its own rows; the Dose carries its full snapshot.
      const pulled = await pullAll(serverApp.app, userA.sessionToken);
      const pulledCompound = pulled.find(
        (change) => change.entity === "compounds" && change.id === compoundId
      );
      const pulledDose = pulled.find(
        (change) => change.entity === "doses" && change.id === doseId
      );
      assert.ok(pulledCompound, "compound should round-trip");
      assert.ok(pulledDose, "dose should round-trip");
      assert.equal(pulledDose.payload.compound_name, "Vitamin D");
      assert.equal(pulledDose.payload.compound_strength, "1000 IU/capsule");
      assert.equal(pulledDose.payload.provenance, "manual");
      assert.equal(pulledDose.deletedAt, null);

      // User B pulls and sees NEITHER row — strict per-user scoping on read.
      const userBPulled = await pullAll(serverApp.app, userB.sessionToken);
      assert.equal(
        userBPulled.filter(
          (change) => change.id === doseId || change.id === compoundId
        ).length,
        0
      );

      // A newer Dose edit wins LWW; an older replay loses.
      const newerUpdatedAt = "2025-06-30T12:00:00.000Z";
      const newerPush = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "doses",
        changes: [
          {
            id: doseId,
            payload: {
              ...dosePayload(doseId, newerUpdatedAt),
              amount_entered: "2",
              amount_value: 2
            },
            updatedAt: newerUpdatedAt,
            deletedAt: null
          }
        ]
      });
      assert.equal(newerPush.status, 200);
      const stalePush = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "doses",
        changes: [
          {
            id: doseId,
            payload: {
              ...dosePayload(doseId, "2025-06-30T09:00:00.000Z"),
              amount_entered: "99",
              amount_value: 99
            },
            updatedAt: "2025-06-30T09:00:00.000Z",
            deletedAt: null
          }
        ]
      });
      assert.equal(stalePush.status, 200);
      const afterLww = await serverApp.database.db
        .select()
        .from(schema.doses)
        .where(eqId(schema.doses.id, doseId));
      assert.equal(afterLww[0].payload.amount_entered, "2");

      // A Dose tombstone (hard-delete to deletedAt) propagates without cascade —
      // the Compound row is untouched.
      const deletedAt = "2025-06-30T13:00:00.000Z";
      const tombstonePush = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "doses",
        changes: [
          {
            id: doseId,
            payload: { ...dosePayload(doseId, deletedAt), deleted_at: deletedAt },
            updatedAt: deletedAt,
            deletedAt
          }
        ]
      });
      assert.equal(tombstonePush.status, 200);
      const tombstoned = await serverApp.database.db
        .select()
        .from(schema.doses)
        .where(eqId(schema.doses.id, doseId));
      assert.notEqual(tombstoned[0].deletedAt, null);
      const compoundStillLive = await serverApp.database.db
        .select()
        .from(schema.compounds)
        .where(eqId(schema.compounds.id, compoundId));
      assert.equal(compoundStillLive.length, 1);
      assert.equal(compoundStillLive[0].deletedAt, null);
    } finally {
      await serverApp.database.close();
    }
  }
);

function compoundPayload(id, updatedAt) {
  return {
    id,
    name: "Vitamin D",
    default_unit: "internationalUnit",
    default_route: "oral",
    strength: "1000 IU/capsule",
    updated_at: updatedAt,
    deleted_at: null
  };
}

function dosePayload(id, updatedAt) {
  return {
    id,
    compound_id: null,
    compound_name: "Vitamin D",
    compound_strength: "1000 IU/capsule",
    amount_value: 1,
    amount_entered: "1",
    unit: "capsule",
    route: "oral",
    took_at: updatedAt,
    timezone: "UTC",
    local_date: "2026-06-30",
    provenance: "manual",
    updated_at: updatedAt,
    deleted_at: null
  };
}

async function syncPush(app, sessionToken, body) {
  return app.request("/sync/push", {
    method: "POST",
    headers: {
      authorization: `Bearer ${sessionToken}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({ protocolVersion: 1, ...body })
  });
}

async function pullAll(app, sessionToken) {
  const changes = [];
  let cursor = null;
  for (let i = 0; i < 50; i += 1) {
    const response = await app.request("/sync/pull", {
      method: "POST",
      headers: {
        authorization: `Bearer ${sessionToken}`,
        "content-type": "application/json"
      },
      body: JSON.stringify({ protocolVersion: 1, cursor, limit: 100 })
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

function eqId(column, value) {
  return eq(column, value);
}

async function createSignedInUser(serverApp) {
  const userId = `user-${randomUUID()}`;
  const sessionToken = `session-${randomUUID()}`;

  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: "Protocols Sync User",
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
