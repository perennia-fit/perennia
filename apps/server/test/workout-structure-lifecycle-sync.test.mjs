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

test(
  "a pull window includes the ancestors of a structure child received first",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });

    try {
      const owner = await createSignedInUser(serverApp);
      const ids = {
        workout: randomUUID(),
        workoutExercise: randomUUID(),
        group: randomUUID(),
        member: randomUUID(),
        exercise: randomUUID()
      };
      const updatedAt = "2026-07-27T08:30:00.000Z";
      const rowsInReceiveOrder = [
        {
          entity: "exercise_group_members",
          id: ids.member,
          payload: image(ids.member, updatedAt, {
            group_id: ids.group,
            workout_exercise_id: ids.workoutExercise,
            position: 0
          })
        },
        {
          entity: "workout_exercises",
          id: ids.workoutExercise,
          payload: image(ids.workoutExercise, updatedAt, {
            workout_id: ids.workout,
            exercise_id: ids.exercise,
            position: 0
          })
        },
        {
          entity: "exercise_groups",
          id: ids.group,
          payload: image(ids.group, updatedAt, {
            workout_id: ids.workout,
            name: "Main circuit",
            position: 0
          })
        },
        {
          entity: "workout_sessions",
          id: ids.workout,
          payload: image(ids.workout, updatedAt, {
            started_at: "2026-07-27T07:20:00.000Z",
            timezone: "Australia/Brisbane",
            local_date: "2026-07-27"
          })
        },
        {
          entity: "exercises",
          id: ids.exercise,
          payload: image(ids.exercise, updatedAt, {
            name: "Back Squat",
            category_id: null
          })
        }
      ];

      for (const row of rowsInReceiveOrder) {
        const response = await push(serverApp.app, owner.sessionToken, {
          deviceId: "phone-a",
          entity: row.entity,
          changes: [
            {
              id: row.id,
              payload: row.payload,
              updatedAt,
              deletedAt: null
            }
          ]
        });
        assert.equal(response.status, 200, await response.text());
      }

      const response = await serverApp.app.request("/sync/pull", {
        method: "POST",
        headers: {
          authorization: `Bearer ${owner.sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          cursor: null,
          limit: 1
        })
      });
      assert.equal(response.status, 200, await response.clone().text());
      const window = await response.json();
      assert.deepEqual(
        window.changes.map((change) => change.entity),
        [
          "exercises",
          "workout_sessions",
          "workout_exercises",
          "exercise_groups",
          "exercise_group_members"
        ]
      );
      assert.notEqual(window.nextCursor, null);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "Workout metadata and structure round-trip as tenant-isolated LWW sync rows",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });

    try {
      const owner = await createSignedInUser(serverApp);
      const other = await createSignedInUser(serverApp);
      const ids = {
        workout: randomUUID(),
        workoutExercise: randomUUID(),
        group: randomUUID(),
        member: randomUUID(),
        exercise: randomUUID()
      };
      const updatedAt = "2026-07-26T08:30:00.000Z";
      const rows = [
        {
          entity: "workout_sessions",
          table: schema.workoutSessions,
          id: ids.workout,
          payload: image(ids.workout, updatedAt, {
            started_at: "2026-07-26T07:20:00.000Z",
            timezone: "Australia/Brisbane",
            local_date: "2026-07-26",
            ended_at: "2026-07-26T08:30:00.000Z",
            comment: "Phone Workout"
          })
        },
        {
          entity: "workout_exercises",
          table: schema.workoutExercises,
          id: ids.workoutExercise,
          payload: image(ids.workoutExercise, updatedAt, {
            workout_id: ids.workout,
            exercise_id: ids.exercise,
            position: 0
          })
        },
        {
          entity: "exercise_groups",
          table: schema.exerciseGroups,
          id: ids.group,
          payload: image(ids.group, updatedAt, {
            workout_id: ids.workout,
            name: "Main circuit",
            color_hex: "#123456",
            position: 0
          })
        },
        {
          entity: "exercise_group_members",
          table: schema.exerciseGroupMembers,
          id: ids.member,
          payload: image(ids.member, updatedAt, {
            group_id: ids.group,
            workout_exercise_id: ids.workoutExercise,
            position: 0
          })
        }
      ];

      for (const row of rows) {
        const response = await push(serverApp.app, owner.sessionToken, {
          deviceId: "phone-a",
          entity: row.entity,
          changes: [
            {
              id: row.id,
              payload: row.payload,
              updatedAt,
              deletedAt: null
            }
          ]
        });
        assert.equal(response.status, 200, await response.text());
      }

      const pulled = await pullAll(serverApp.app, owner.sessionToken);
      assert.deepEqual(
        pulled
          .filter((change) => rows.some((row) => row.id === change.id))
          .map((change) => change.entity),
        rows.map((row) => row.entity)
      );
      for (const row of rows) {
        const roundTripped = pulled.find((change) => change.id === row.id);
        assert.deepEqual(roundTripped?.payload, row.payload);
      }

      for (const row of rows) {
        const response = await push(serverApp.app, other.sessionToken, {
          deviceId: "other-phone",
          entity: row.entity,
          changes: [
            {
              id: row.id,
              payload: { ...row.payload, comment: "hijacked" },
              updatedAt: "2026-07-26T09:00:00.000Z",
              deletedAt: null
            }
          ]
        });
        assert.equal(response.status, 200);
        assert.deepEqual((await response.json()).accepted, []);
        const stored = await serverApp.database.db
          .select()
          .from(row.table)
          .where(eq(row.table.id, row.id));
        assert.equal(stored[0].userId, owner.userId);
      }
    } finally {
      await serverApp.database.close();
    }
  }
);

function image(id, updatedAt, fields) {
  return {
    id,
    ...fields,
    updated_at: updatedAt,
    deleted_at: null
  };
}

function push(app, token, body) {
  return app.request("/sync/push", {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({ protocolVersion: 1, ...body })
  });
}

async function pullAll(app, token) {
  const changes = [];
  let cursor = null;
  for (let index = 0; index < 20; index += 1) {
    const response = await app.request("/sync/pull", {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
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
  const userId = `workout-sync-user-${randomUUID()}`;
  const sessionToken = `workout-sync-session-${randomUUID()}`;
  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: "Workout Sync User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
  await serverApp.database.db.insert(schema.session).values({
    id: randomUUID(),
    token: sessionToken,
    userId,
    expiresAt: new Date("2099-01-01T00:00:00.000Z")
  });
  return { userId, sessionToken };
}
