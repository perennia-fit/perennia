import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { createMigratedServerApp, schema } from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error(
    "DATABASE_URL must be set for server Postgres integration tests."
  );
}

const skip = databaseUrl ? false : "DATABASE_URL is not set.";

// Every install seeds these rows under the SAME fixed ids and pushes them as
// ordinary LWW rows, so two accounts routinely hold a row with the same id:
// - the Platform "Chest" Exercise Category (assets/seeds/platform_exercises.json)
// - the default "Breakfast" Meal Type (NutritionRepository._defaultMealTypes)
// - the OTC "Creatine" Compound (lib/data/seeds/otc_compound_seed.dart)
const SEEDED_ROWS = [
  {
    entity: "exercise_categories",
    id: "01910000-0000-7000-8000-000000000007",
    seededName: "Chest",
    extra: { sort_order: 0, color_hex: "#E06C5A" }
  },
  {
    entity: "meal_types",
    id: "meal-type-breakfast",
    seededName: "Breakfast",
    extra: { sort_order: 0 }
  },
  {
    entity: "compounds",
    id: "019200ff-0000-7000-8000-000000000001",
    seededName: "Creatine",
    extra: { default_unit: "gram", default_route: "oral", strength: null }
  }
];

for (const seeded of SEEDED_ROWS) {
  test(
    `two accounts each keep their own edit of the seeded ${seeded.entity} row ${seeded.id}`,
    { skip },
    async () => {
      const serverApp = await migratedApp();
      try {
        const userA = await createSignedInUser(serverApp);
        const userB = await createSignedInUser(serverApp);
        const seededAt = "2026-06-29T00:00:00.000Z";

        // Both devices push the bundled seed row on first sync.
        for (const [user, deviceId] of [
          [userA, "device-a"],
          [userB, "device-b"]
        ]) {
          const push = await syncPush(serverApp.app, user.sessionToken, {
            deviceId,
            entity: seeded.entity,
            changes: [change(seeded, seeded.seededName, seededAt)]
          });
          assert.equal(push.status, 200);
          assert.deepEqual((await push.json()).accepted, [seeded.id]);
        }

        // Then each account renames it, B after A.
        const renames = [
          [userA, "device-a", `${seeded.seededName} (A)`, "2026-07-01T00:00:00.000Z"],
          [userB, "device-b", `${seeded.seededName} (B)`, "2026-07-02T00:00:00.000Z"]
        ];
        for (const [user, deviceId, name, updatedAt] of renames) {
          const push = await syncPush(serverApp.app, user.sessionToken, {
            deviceId,
            entity: seeded.entity,
            changes: [change(seeded, name, updatedAt)]
          });
          assert.equal(push.status, 200);
          const body = await push.json();
          assert.deepEqual(body.accepted, [seeded.id]);
          assert.deepEqual(
            body.applied.map((applied) => applied.id),
            [seeded.id],
            `${name} must be applied, not silently dropped`
          );
        }

        for (const [user, , name] of renames) {
          for (const mode of ["delta", "snapshot"]) {
            const pulled = (await pullAll(serverApp.app, user.sessionToken, mode)).filter(
              (pulledChange) =>
                pulledChange.entity === seeded.entity &&
                pulledChange.id === seeded.id
            );
            assert.equal(pulled.length, 1, `${mode} pull returns one ${seeded.id}`);
            assert.equal(pulled[0].payload.name, name);
          }
        }

        // A stale push from A never touches B's row (and vice versa): each
        // account's LWW clock is its own.
        const staleA = await syncPush(serverApp.app, userA.sessionToken, {
          deviceId: "device-a",
          entity: seeded.entity,
          changes: [change(seeded, "stale", "2026-06-30T00:00:00.000Z")]
        });
        assert.equal(staleA.status, 200);
        assert.deepEqual((await staleA.json()).applied, []);
        const afterStale = (await pullAll(serverApp.app, userB.sessionToken)).find(
          (pulledChange) => pulledChange.id === seeded.id
        );
        assert.equal(afterStale.payload.name, `${seeded.seededName} (B)`);
      } finally {
        await serverApp.database.close();
      }
    }
  );
}

test(
  "an agent undo of a seeded Exercise Category edit reverts only the caller's row",
  { skip },
  async () => {
    const serverApp = await migratedApp();
    try {
      const seeded = SEEDED_ROWS[0];
      const userA = await createSignedInUser(serverApp);
      const userB = await createSignedInUser(serverApp);

      // A edits Chest first, so A's row exists before B's.
      await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: seeded.entity,
        changes: [change(seeded, "Pecs", "2026-07-01T00:00:00.000Z")]
      });

      // B's agent renames B's Chest through the catalog batch write.
      const agentSecret = await createAgentKey(serverApp, userB.sessionToken);
      const batchId = `seeded-category-rename-${randomUUID()}`;
      const write = await agentPost(
        serverApp.app,
        agentSecret,
        "/agent/exercises/batch-write",
        {
          idempotencyKey: batchId,
          categories: [
            {
              id: seeded.id,
              name: "Upper chest",
              sortOrder: 0,
              colorHex: "#E06C5A",
              deletedAt: null
            }
          ],
          exercises: []
        }
      );
      assert.equal(write.status, 200, await write.clone().text());

      const undo = await agentPost(
        serverApp.app,
        agentSecret,
        "/agent/activity/undo-batch",
        { batchId, idempotencyKey: randomUUID() }
      );
      assert.equal(undo.status, 200, await undo.clone().text());
      const undone = await undo.json();
      assert.deepEqual(
        undone.entries.map((entry) => entry.outcome),
        ["reverted"]
      );

      // Undo of B's create archives B's row; A's rename is untouched.
      const pulledA = (await pullAll(serverApp.app, userA.sessionToken)).find(
        (pulledChange) => pulledChange.id === seeded.id
      );
      assert.equal(pulledA.payload.name, "Pecs");
      assert.equal(pulledA.deletedAt, null);
      const pulledB = (await pullAll(serverApp.app, userB.sessionToken)).find(
        (pulledChange) => pulledChange.id === seeded.id
      );
      assert.equal(pulledB.payload.name, "Upper chest");
      assert.notEqual(pulledB.deletedAt, null);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "an agent can rename its own seeded OTC Compound when another account already holds that id",
  { skip },
  async () => {
    const serverApp = await migratedApp();
    try {
      const seeded = SEEDED_ROWS[2];
      const userA = await createSignedInUser(serverApp);
      const userB = await createSignedInUser(serverApp);

      await syncPush(serverApp.app, userA.sessionToken, {
        deviceId: "device-a",
        entity: seeded.entity,
        changes: [change(seeded, "Creatine monohydrate", "2026-07-01T00:00:00.000Z")]
      });

      // A's row must not read as "owned by another user" for B's agent.
      const agentSecret = await createAgentKey(serverApp, userB.sessionToken);
      const write = await agentPost(
        serverApp.app,
        agentSecret,
        "/agent/protocols/compounds/batch-write",
        {
          idempotencyKey: `seeded-compound-rename-${randomUUID()}`,
          compounds: [
            {
              id: seeded.id,
              name: "Creatine HCl",
              defaultUnit: "gram",
              defaultRoute: "oral"
            }
          ]
        }
      );
      assert.equal(write.status, 200, await write.clone().text());
      assert.equal((await write.json()).accepted, true);

      const pulledA = (await pullAll(serverApp.app, userA.sessionToken)).find(
        (pulledChange) => pulledChange.id === seeded.id
      );
      assert.equal(pulledA.payload.name, "Creatine monohydrate");
      const pulledB = (await pullAll(serverApp.app, userB.sessionToken)).find(
        (pulledChange) => pulledChange.id === seeded.id
      );
      assert.equal(pulledB.payload.name, "Creatine HCl");
    } finally {
      await serverApp.database.close();
    }
  }
);

function change(seeded, name, updatedAt) {
  return {
    id: seeded.id,
    payload: {
      id: seeded.id,
      name,
      ...seeded.extra,
      updated_at: updatedAt,
      deleted_at: null
    },
    updatedAt,
    deletedAt: null
  };
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

async function createSignedInUser(serverApp) {
  const userId = `user-${randomUUID()}`;
  const sessionToken = `session-${randomUUID()}`;
  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: "Seeded Row Tenancy User",
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

async function createAgentKey(serverApp, sessionToken) {
  const response = await serverApp.app.request("/agent/api-keys", {
    method: "POST",
    headers: {
      authorization: `Bearer ${sessionToken}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({ name: "Seeded row coach" })
  });
  assert.equal(response.status, 201);
  return (await response.json()).secret;
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
