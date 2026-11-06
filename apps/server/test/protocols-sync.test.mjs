import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { eq } from "drizzle-orm";

import {
  createMigratedServerApp,
  schema,
  SYNC_PROTOCOL_VERSION
} from "../src/index.ts";

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

      // A Dose logged before offsets were frozen has no
      // `timezone_offset_minutes` key; it is still a well-formed Dose.
      const legacyDoseId = randomUUID();
      const { timezone_offset_minutes: _omitted, ...legacyDose } = dosePayload(
        legacyDoseId,
        updatedAt
      );
      const pushDose = await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "doses",
        changes: [
          {
            id: doseId,
            payload: dosePayload(doseId, updatedAt),
            updatedAt,
            deletedAt: null
          },
          {
            id: legacyDoseId,
            payload: legacyDose,
            updatedAt,
            deletedAt: null
          }
        ]
      });
      assert.equal(pushDose.status, 200);
      assert.deepEqual((await pushDose.json()).accepted, [doseId, legacyDoseId]);

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
      assert.equal(pulledDose.payload.timezone_offset_minutes, 60);
      assert.equal(pulledDose.deletedAt, null);
      const pulledLegacyDose = pulled.find(
        (change) => change.entity === "doses" && change.id === legacyDoseId
      );
      assert.ok(pulledLegacyDose, "a Dose without an offset should round-trip");
      assert.equal("timezone_offset_minutes" in pulledLegacyDose.payload, false);

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

// docs/designs/compound-purposes.md, D1, D2 and CUJ 6.
const SEED_STAMP = "2026-10-24T00:00:00.000Z";
const CREATINE = "019200ff-0000-7000-8000-000000000001";
const COGNITION = "019200ff-0000-7000-8000-000000000105";
const PERFORMANCE = "019200ff-0000-7000-8000-000000000103";

test(
  "a Purpose round-trips as an account-keyed LWW row, tombstone included",
  { skip },
  async () => {
    const serverApp = await migratedApp();
    try {
      const user = await createSignedInUser(serverApp);
      const id = randomUUID();
      const updatedAt = "2025-06-30T08:00:00.000Z";
      const push = await syncPush(serverApp.app, user.sessionToken, {
        deviceId: "device-a",
        entity: "purposes",
        changes: [purposeChange(id, "Joints", 6, updatedAt)]
      });
      assert.equal(push.status, 200);
      assert.deepEqual((await push.json()).accepted, [id]);

      const pulled = (await pullAll(serverApp.app, user.sessionToken)).filter(
        (change) => change.entity === "purposes"
      );
      assert.equal(pulled.length, 1);
      assert.equal(pulled[0].id, id);
      assert.equal(pulled[0].deviceId, "device-a");
      assert.equal(pulled[0].payload.name, "Joints");
      assert.equal(pulled[0].payload.sort_order, 6);

      // An older write loses, a newer one wins.
      const stale = await syncPush(serverApp.app, user.sessionToken, {
        deviceId: "device-b",
        entity: "purposes",
        changes: [purposeChange(id, "Stale", 6, "2025-06-29T08:00:00.000Z")]
      });
      assert.deepEqual((await stale.json()).applied, []);

      const archivedAt = "2025-07-01T08:00:00.000Z";
      await syncPush(serverApp.app, user.sessionToken, {
        deviceId: "device-a",
        entity: "purposes",
        changes: [
          {
            id,
            payload: {
              id,
              name: "Joints",
              sort_order: 6,
              updated_at: archivedAt,
              deleted_at: archivedAt
            },
            updatedAt: archivedAt,
            deletedAt: archivedAt
          }
        ]
      });
      const [delta] = (await pullAll(serverApp.app, user.sessionToken)).filter(
        (change) => change.entity === "purposes"
      );
      assert.equal(delta.payload.name, "Joints");
      assert.notEqual(delta.deletedAt, null);
      const snapshot = (
        await pullAll(serverApp.app, user.sessionToken, "snapshot")
      ).filter((change) => change.entity === "purposes");
      assert.deepEqual(snapshot, []);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "a Purpose is pulled before a Compound that shares its receive timestamp",
  { skip },
  async () => {
    const serverApp = await migratedApp();
    try {
      const user = await createSignedInUser(serverApp);
      const updatedAt = "2025-06-30T08:00:00.000Z";
      const receivedAt = new Date("2025-06-30T09:00:00.000Z");
      await serverApp.database.db.insert(schema.compounds).values({
        id: CREATINE,
        userId: user.userId,
        deviceId: "device-a",
        payload: compoundPayload(CREATINE, updatedAt),
        updatedAt: new Date(updatedAt),
        receivedAt
      });
      await serverApp.database.db.insert(schema.purposes).values({
        id: PERFORMANCE,
        userId: user.userId,
        deviceId: "device-a",
        payload: purposeChange(PERFORMANCE, "Performance", 2, updatedAt).payload,
        updatedAt: new Date(updatedAt),
        receivedAt
      });

      const pulled = await pullAll(serverApp.app, user.sessionToken);

      assert.deepEqual(
        pulled.map((change) => change.entity),
        ["purposes", "compounds"]
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "a Compound push without purpose_ids keeps the stored list, and an " +
    "explicit '[]' clears it",
  { skip },
  async () => {
    const serverApp = await migratedApp();
    try {
      const user = await createSignedInUser(serverApp);
      const tags = JSON.stringify([PERFORMANCE]);
      const pushCreatine = async (updatedAt, keys) => {
        const response = await syncPush(serverApp.app, user.sessionToken, {
          deviceId: "device-a",
          entity: "compounds",
          changes: [
            {
              id: CREATINE,
              payload: { ...compoundPayload(CREATINE, updatedAt), ...keys },
              updatedAt,
              deletedAt: null
            }
          ]
        });
        assert.equal(response.status, 200);
        assert.deepEqual(
          (await response.json()).applied.map((applied) => applied.id),
          [CREATINE]
        );
      };
      const storedPayload = async () => {
        const [change] = (await pullAll(serverApp.app, user.sessionToken)).filter(
          (pulled) => pulled.entity === "compounds"
        );
        return change.payload;
      };

      await pushCreatine("2025-06-30T08:00:00.000Z", { purpose_ids: tags });
      assert.equal((await storedPayload()).purpose_ids, tags);

      // An older app, or an Agent edit that omits the key.
      await pushCreatine("2025-06-30T09:00:00.000Z", { name: "Creatine HCl" });
      const carried = await storedPayload();
      assert.equal(carried.name, "Creatine HCl");
      assert.equal(carried.purpose_ids, tags);

      await pushCreatine("2025-06-30T10:00:00.000Z", { purpose_ids: "[]" });
      assert.equal((await storedPayload()).purpose_ids, "[]");

      // Staying cleared is not the same as absent.
      await pushCreatine("2025-06-30T11:00:00.000Z", { name: "Creatine" });
      assert.equal((await storedPayload()).purpose_ids, "[]");
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "CUJ 6: a removed seed tag and a renamed starter survive a second " +
    "device's first sync",
  { skip },
  async () => {
    const serverApp = await migratedApp();
    try {
      const user = await createSignedInUser(serverApp);
      const seedTags = JSON.stringify([PERFORMANCE]);
      const seedCreatine = () => ({
        id: CREATINE,
        payload: {
          ...compoundPayload(CREATINE, SEED_STAMP),
          name: "Creatine",
          purpose_ids: seedTags
        },
        updatedAt: SEED_STAMP,
        deletedAt: null
      });
      const seedCognition = () =>
        purposeChange(COGNITION, "Cognition", 4, SEED_STAMP);
      const push = async (deviceId, entity, changes) => {
        const response = await syncPush(serverApp.app, user.sessionToken, {
          deviceId,
          entity,
          changes
        });
        assert.equal(response.status, 200);
        return response.json();
      };

      // Device A seeds and syncs, then empties Creatine's list and renames
      // Cognition, and syncs again.
      await push("device-a", "purposes", [seedCognition()]);
      await push("device-a", "compounds", [seedCreatine()]);
      const editedAt = "2026-10-25T08:00:00.000Z";
      await push("device-a", "purposes", [
        purposeChange(COGNITION, "Memory", 4, editedAt)
      ]);
      const emptied = {
        ...seedCreatine().payload,
        purpose_ids: "[]",
        updated_at: editedAt
      };
      await push("device-a", "compounds", [
        {
          id: CREATINE,
          payload: emptied,
          updatedAt: editedAt,
          deletedAt: null,
          activityLogId: randomUUID(),
          actor: "manual",
          batchId: randomUUID(),
          beforeImage: seedCreatine().payload,
          afterImage: emptied,
          occurredAt: editedAt
        }
      ]);

      // Device B seeds at the fixed stamp, so its first push loses to both
      // edits instead of overwriting them.
      const purposePush = await push("device-b", "purposes", [seedCognition()]);
      assert.deepEqual(purposePush.applied, []);
      const compoundPush = await push("device-b", "compounds", [seedCreatine()]);
      assert.deepEqual(compoundPush.applied, []);

      // Its full pull brings both edits. The pulled Creatine carries an entry
      // that isn't otc_seed, so device B's backfill reads the row as touched
      // and writes nothing: there is no third push to make.
      const pulled = await pullAll(serverApp.app, user.sessionToken);
      const creatine = pulled.find((change) => change.id === CREATINE);
      assert.equal(creatine.payload.purpose_ids, "[]");
      assert.equal(creatine.actor, "manual");
      const purposes = pulled.filter((change) => change.entity === "purposes");
      assert.equal(purposes.length, 1);
      assert.equal(purposes[0].payload.name, "Memory");

      // Both devices read the same rows, however they ask.
      const snapshot = await pullAll(
        serverApp.app,
        user.sessionToken,
        "snapshot"
      );
      assert.equal(
        snapshot.find((change) => change.id === CREATINE).payload.purpose_ids,
        "[]"
      );
      assert.equal(
        snapshot.find((change) => change.id === COGNITION).payload.name,
        "Memory"
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

async function migratedApp() {
  return createMigratedServerApp({
    databaseUrl,
    logger: { info() {}, error() {} },
    auth: false
  });
}

function purposeChange(id, name, sortOrder, updatedAt) {
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
    timezone: "Europe/Lisbon",
    timezone_offset_minutes: 60,
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
    body: JSON.stringify({ protocolVersion: SYNC_PROTOCOL_VERSION, ...body })
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
      body: JSON.stringify({ protocolVersion: SYNC_PROTOCOL_VERSION, cursor, limit: 100, mode })
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
