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

function syncTest(name, body) {
  test(name, { skip }, async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    try {
      await body(serverApp);
    } finally {
      await serverApp.database.close();
    }
  });
}

syncTest(
  "a section pushes and pulls as an LWW opaque row, with a newer edit winning and an older replay losing",
  async (serverApp) => {
    const user = await createSignedInUser(serverApp);
    const id = randomUUID();
    const updatedAt = "2025-06-30T08:00:00.000Z";

    const push = await syncPush(serverApp.app, user.sessionToken, {
      deviceId: "device-a",
      entity: "user_profile_sections",
      changes: [change(id, "about_you", { sex: "female" }, updatedAt)]
    });
    assert.equal(push.status, 200);
    assert.deepEqual((await push.json()).accepted, [id]);

    const pulled = await pullAll(serverApp.app, user.sessionToken);
    const row = pulled.find((candidate) => candidate.id === id);
    assert.equal(row.entity, "user_profile_sections");
    assert.equal(row.payload.section, "about_you");
    assert.deepEqual(row.payload.values, { sex: "female" });
    assert.equal(row.deletedAt, null);

    const newerAt = "2025-06-30T12:00:00.000Z";
    await syncPush(serverApp.app, user.sessionToken, {
      deviceId: "device-a",
      entity: "user_profile_sections",
      changes: [change(id, "about_you", { sex: "male" }, newerAt)]
    });
    await syncPush(serverApp.app, user.sessionToken, {
      deviceId: "device-b",
      entity: "user_profile_sections",
      changes: [change(id, "about_you", { sex: "female" }, updatedAt)]
    });
    const stored = await storedRow(serverApp, id);
    assert.deepEqual(stored.payload.values, { sex: "male" });
    assert.equal(stored.updatedAt.toISOString(), newerAt);
  }
);

syncTest(
  "tenant isolation: a pushed id another user owns is dropped",
  async (serverApp) => {
    const userA = await createSignedInUser(serverApp);
    const userB = await createSignedInUser(serverApp);
    const id = randomUUID();

    await syncPush(serverApp.app, userA.sessionToken, {
      deviceId: "device-a",
      entity: "user_profile_sections",
      changes: [
        change(id, "general_notes", { text: "A's note" }, "2025-06-30T08:00:00.000Z")
      ]
    });
    const crossPush = await syncPush(serverApp.app, userB.sessionToken, {
      deviceId: "device-b",
      entity: "user_profile_sections",
      changes: [
        change(id, "general_notes", { text: "B's note" }, "2025-06-30T10:00:00.000Z")
      ]
    });
    assert.equal(crossPush.status, 200);

    const stored = await storedRow(serverApp, id);
    assert.equal(stored.userId, userA.userId);
    assert.deepEqual(stored.payload.values, { text: "A's note" });

    const userBPulled = await pullAll(serverApp.app, userB.sessionToken);
    assert.equal(userBPulled.filter((row) => row.id === id).length, 0);
  }
);

syncTest(
  "push runs no domain rules: a value they would reject is still accepted and stored as sent",
  async (serverApp) => {
    const user = await createSignedInUser(serverApp);
    const id = randomUUID();
    const values = {
      sex: "other",
      birth_year: 2999,
      height: { value: -1, unit: "furlongs" },
      from_a_newer_app: true
    };

    const push = await syncPush(serverApp.app, user.sessionToken, {
      deviceId: "device-a",
      entity: "user_profile_sections",
      changes: [change(id, "about_you", values, "2025-06-30T08:00:00.000Z")]
    });
    assert.equal(push.status, 200);
    assert.deepEqual((await push.json()).accepted, [id]);
    assert.deepEqual((await storedRow(serverApp, id)).payload.values, values);
  }
);

syncTest(
  "a push whose payload isn't a section is refused by its shape, not its values",
  async (serverApp) => {
    const user = await createSignedInUser(serverApp);
    const updatedAt = "2025-06-30T08:00:00.000Z";
    for (const payload of [
      { section: "favourites", values: {} },
      { section: "about_you" },
      { section: "about_you", values: ["not", "an", "object"] }
    ]) {
      const id = randomUUID();
      const response = await syncPush(serverApp.app, user.sessionToken, {
        deviceId: "device-a",
        entity: "user_profile_sections",
        changes: [
          {
            id,
            payload: { id, ...payload, updated_at: updatedAt, deleted_at: null },
            updatedAt,
            deletedAt: null
          }
        ]
      }).catch((error) => error);
      assert.ok(
        response instanceof Error || response.status >= 400,
        JSON.stringify(payload)
      );
      assert.equal(await storedRow(serverApp, id), undefined);
    }
  }
);

syncTest(
  "a full re-sync snapshot includes live rows and leaves tombstones out",
  async (serverApp) => {
    const user = await createSignedInUser(serverApp);
    const liveId = randomUUID();
    const archivedId = randomUUID();
    const updatedAt = "2025-06-30T08:00:00.000Z";
    await syncPush(serverApp.app, user.sessionToken, {
      deviceId: "device-a",
      entity: "user_profile_sections",
      changes: [
        change(liveId, "training_goals", { goals: [] }, updatedAt),
        {
          ...change(archivedId, "experience", { levels: [] }, updatedAt),
          deletedAt: updatedAt
        }
      ]
    });

    const delta = await pullAll(serverApp.app, user.sessionToken);
    assert.ok(delta.some((row) => row.id === archivedId), "delta has the tombstone");

    const snapshot = await pullAll(serverApp.app, user.sessionToken, "snapshot");
    assert.ok(snapshot.some((row) => row.id === liveId));
    assert.ok(!snapshot.some((row) => row.id === archivedId));
  }
);

syncTest(
  "a pull page breaks between sections without losing one",
  async (serverApp) => {
    const user = await createSignedInUser(serverApp);
    const updatedAt = "2025-06-30T08:00:00.000Z";
    const ids = [randomUUID(), randomUUID(), randomUUID()];
    await syncPush(serverApp.app, user.sessionToken, {
      deviceId: "device-a",
      entity: "nutrition_goals",
      changes: [
        {
          id: randomUUID(),
          payload: { nutrient_id: "energy", target_value: 2000 },
          updatedAt,
          deletedAt: null
        }
      ]
    });
    await syncPush(serverApp.app, user.sessionToken, {
      deviceId: "device-a",
      entity: "user_profile_sections",
      changes: ids.map((id) => change(id, "general_notes", { text: id }, updatedAt))
    });

    const pulled = await pullAll(serverApp.app, user.sessionToken, "delta", 1);
    assert.deepEqual(
      pulled
        .filter((row) => row.entity === "user_profile_sections")
        .map((row) => row.id)
        .sort(),
      [...ids].sort()
    );
  }
);

function change(id, section, values, updatedAt) {
  return {
    id,
    payload: { id, section, values, updated_at: updatedAt, deleted_at: null },
    updatedAt,
    deletedAt: null
  };
}

async function storedRow(serverApp, id) {
  const rows = await serverApp.database.db
    .select()
    .from(schema.userProfileSections)
    .where(eq(schema.userProfileSections.id, id));
  return rows[0];
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

async function pullAll(app, sessionToken, mode, limit = 100) {
  const changes = [];
  let cursor = null;
  for (let i = 0; i < 50; i += 1) {
    const response = await app.request("/sync/pull", {
      method: "POST",
      headers: {
        authorization: `Bearer ${sessionToken}`,
        "content-type": "application/json"
      },
      body: JSON.stringify({
        protocolVersion: SYNC_PROTOCOL_VERSION,
        cursor,
        limit,
        ...(mode === undefined ? {} : { mode })
      })
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
    name: "User Profile Sync User",
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
