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
  "Protocol and Schedule round-trip as LWW opaque rows, with provenance, " +
    "tenant isolation, and no cascade to a logged Dose",
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
      const protocolId = randomUUID();
      const protocolCompoundId = randomUUID();
      const scheduleId = randomUUID();
      const doseId = randomUUID();
      const updatedAt = "2025-06-30T08:00:00.000Z";

      // User A pushes the catalogue Compound, the Protocol plan, its member,
      // and the member's optional Schedule.
      await syncPushOk(serverApp.app, userA.sessionToken, {
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
      await syncPushOk(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "protocols",
        changes: [
          {
            id: protocolId,
            payload: protocolPayload(protocolId, updatedAt),
            updatedAt,
            deletedAt: null
          }
        ]
      });
      await syncPushOk(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "protocol_compounds",
        changes: [
          {
            id: protocolCompoundId,
            payload: protocolCompoundPayload(
              protocolCompoundId,
              protocolId,
              compoundId,
              updatedAt
            ),
            updatedAt,
            deletedAt: null
          }
        ]
      });
      await syncPushOk(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "schedules",
        changes: [
          {
            id: scheduleId,
            payload: schedulePayload(
              scheduleId,
              protocolCompoundId,
              updatedAt
            ),
            updatedAt,
            deletedAt: null
          }
        ]
      });
      // A Dose tagged to the Protocol — proves archiving the
      // Protocol later never cascades to it.
      await syncPushOk(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "doses",
        changes: [
          {
            id: doseId,
            payload: dosePayload(doseId, protocolId, updatedAt),
            updatedAt,
            deletedAt: null
          }
        ]
      });

      // TENANT ISOLATION: user B cannot overwrite user A's Protocol keyed by
      // the same client PK.
      const crossUserUpdatedAt = "2025-06-30T10:00:00.000Z";
      const crossPush = await syncPush(serverApp.app, userB.sessionToken, {
        deviceId: "device-b",
        entity: "protocols",
        changes: [
          {
            id: protocolId,
            payload: {
              ...protocolPayload(protocolId, crossUserUpdatedAt),
              name: "Hijacked"
            },
            updatedAt: crossUserUpdatedAt,
            deletedAt: null
          }
        ]
      });
      assert.equal(crossPush.status, 200);
      const storedProtocol = await serverApp.database.db
        .select()
        .from(schema.protocols)
        .where(eq(schema.protocols.id, protocolId));
      assert.equal(storedProtocol.length, 1);
      assert.equal(storedProtocol[0].userId, userA.userId);
      assert.equal(storedProtocol[0].payload.name, "Lean bulk");

      // User A pulls back its own rows; the Protocol/ProtocolCompound/
      // Schedule all round-trip with provenance intact.
      const pulled = await pullAll(serverApp.app, userA.sessionToken);
      const pulledProtocol = pulled.find(
        (change) => change.entity === "protocols" && change.id === protocolId
      );
      const pulledMember = pulled.find(
        (change) =>
          change.entity === "protocol_compounds" &&
          change.id === protocolCompoundId
      );
      const pulledSchedule = pulled.find(
        (change) => change.entity === "schedules" && change.id === scheduleId
      );
      const pulledDose = pulled.find(
        (change) => change.entity === "doses" && change.id === doseId
      );
      assert.ok(pulledProtocol, "protocol should round-trip");
      assert.ok(pulledMember, "protocol_compound should round-trip");
      assert.ok(pulledSchedule, "schedule should round-trip");
      assert.equal(pulledProtocol.payload.name, "Lean bulk");
      assert.equal(pulledMember.payload.compound_id, compoundId);
      assert.equal(pulledSchedule.payload.dose_amount_entered, "5");
      assert.equal(pulledSchedule.payload.frequency, "onceDaily");
      assert.equal(pulledDose.payload.protocol_id, protocolId);

      // User B pulls and sees none of user A's rows — strict per-user scoping.
      const userBPulled = await pullAll(serverApp.app, userB.sessionToken);
      assert.equal(
        userBPulled.filter(
          (change) =>
            [protocolId, protocolCompoundId, scheduleId, doseId].includes(
              change.id
            )
        ).length,
        0
      );

      // Archiving the Protocol (a tombstone via deleted_at) propagates without
      // cascading to the tagged Dose — the Dose row is untouched.
      const deletedAt = "2025-06-30T13:00:00.000Z";
      const archivePush = await syncPushOk(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: "protocols",
        changes: [
          {
            id: protocolId,
            payload: {
              ...protocolPayload(protocolId, deletedAt),
              deleted_at: deletedAt
            },
            updatedAt: deletedAt,
            deletedAt
          }
        ]
      });
      assert.deepEqual(archivePush.accepted, [protocolId]);
      const archivedProtocol = await serverApp.database.db
        .select()
        .from(schema.protocols)
        .where(eq(schema.protocols.id, protocolId));
      assert.notEqual(archivedProtocol[0].deletedAt, null);
      const doseStillLive = await serverApp.database.db
        .select()
        .from(schema.doses)
        .where(eq(schema.doses.id, doseId));
      assert.equal(doseStillLive.length, 1);
      assert.equal(doseStillLive[0].deletedAt, null);
      assert.equal(doseStillLive[0].payload.protocol_id, protocolId);
    } finally {
      await serverApp.database.close();
    }
  }
);

function compoundPayload(id, updatedAt) {
  return {
    id,
    name: "Creatine",
    default_unit: "gram",
    default_route: "oral",
    strength: null,
    updated_at: updatedAt,
    deleted_at: null
  };
}

function protocolPayload(id, updatedAt) {
  return {
    id,
    name: "Lean bulk",
    start_date: updatedAt,
    end_date: null,
    updated_at: updatedAt,
    deleted_at: null
  };
}

function protocolCompoundPayload(id, protocolId, compoundId, updatedAt) {
  return {
    id,
    protocol_id: protocolId,
    compound_id: compoundId,
    position: 0,
    updated_at: updatedAt,
    deleted_at: null
  };
}

function schedulePayload(id, protocolCompoundId, updatedAt) {
  return {
    id,
    protocol_compound_id: protocolCompoundId,
    dose_amount_value: 5,
    dose_amount_entered: "5",
    dose_unit: "gram",
    frequency: "onceDaily",
    route: "oral",
    updated_at: updatedAt,
    deleted_at: null
  };
}

function dosePayload(id, protocolId, updatedAt) {
  return {
    id,
    compound_id: null,
    compound_name: "Creatine",
    compound_strength: null,
    amount_value: 5,
    amount_entered: "5",
    unit: "gram",
    route: "oral",
    took_at: updatedAt,
    timezone: "UTC",
    local_date: "2026-06-30",
    provenance: "manual",
    protocol_id: protocolId,
    protocol_name: "Lean bulk",
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

async function syncPushOk(app, sessionToken, body) {
  const response = await syncPush(app, sessionToken, body);
  assert.equal(response.status, 200);
  return response.json();
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

async function createSignedInUser(serverApp) {
  const userId = `user-${randomUUID()}`;
  const sessionToken = `session-${randomUUID()}`;

  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: "Protocols Lifecycle Sync User",
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
