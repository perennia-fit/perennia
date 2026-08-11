import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { eq, inArray, sql } from "drizzle-orm";

import { createMigratedServerApp, schema } from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error(
    "DATABASE_URL must be set for server Postgres integration tests."
  );
}

const skip = databaseUrl ? false : "DATABASE_URL is not set.";

test("the cutover migration discards retained legacy Routine payloads", async () => {
  const migrationSql = await readFile(
    new URL("../drizzle/0027_sweet_sphinx.sql", import.meta.url),
    "utf8"
  );

  assert.match(migrationSql, /TRUNCATE TABLE "routines"/);
});

test(
  "the complete plan tree round-trips as tenant-isolated LWW opaque rows with recoverable losers",
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
      const ids = {
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
      const planRows = planTreeRows(ids, "2025-06-30T08:00:00.000Z");

      const oldTables = await serverApp.database.db.execute(sql`
        select table_name
        from information_schema.tables
        where table_schema = 'public'
          and table_name in (
            'routine_days',
            'routine_exercises',
            'predefined_sets',
            'routine_exercise_groups',
            'routine_exercise_group_members'
          )
      `);
      assert.equal(oldTables.length, 0, "legacy routine tables must be gone");

      for (const row of planRows) {
        const result = await syncPushOk(serverApp.app, userA.sessionToken, {
          deviceId: "device-a",
          entity: row.entity,
          changes: [change(row, row.payload.updated_at)]
        });
        assert.deepEqual(result.accepted, [row.id]);
      }

      const pulled = await pullAll(serverApp.app, userA.sessionToken);
      for (const row of planRows) {
        const roundTripped = pulled.find(
          (candidate) =>
            candidate.entity === row.entity && candidate.id === row.id
        );
        assert.ok(roundTripped, `${row.entity} should round-trip`);
        assert.deepEqual(roundTripped.payload, row.payload);
      }

      // The same client primary key can never be claimed by another user,
      // across every plan table.
      for (const row of planRows) {
        const crossUser = await syncPushOk(
          serverApp.app,
          userB.sessionToken,
          {
            deviceId: "device-other-user",
            entity: row.entity,
            changes: [
              change(
                {
                  ...row,
                  payload: { ...row.payload, revision: "hijacked" }
                },
                "2025-06-30T12:00:00.000Z"
              )
            ]
          }
        );
        assert.deepEqual(crossUser.accepted, []);
        const stored = await serverApp.database.db
          .select()
          .from(row.table)
          .where(eq(row.table.id, row.id));
        assert.equal(stored.length, 1);
        assert.equal(stored[0].userId, userA.userId);
        assert.notEqual(stored[0].payload.revision, "hijacked");
      }
      const userBPulled = await pullAll(serverApp.app, userB.sessionToken);
      assert.equal(
        userBPulled.filter((candidate) =>
          planRows.some((row) => row.id === candidate.id)
        ).length,
        0
      );

      // Device B wins every concurrent row deterministically. Device A's
      // stale replays remain inspectable in Activity Log as recoverable losers.
      const staleActivityIds = [];
      for (const row of planRows) {
        const winnerPayload = {
          ...row.payload,
          revision: "device-b",
          updated_at: "2025-06-30T10:00:00.000Z"
        };
        await syncPushOk(serverApp.app, userA.sessionToken, {
          deviceId: "device-b",
          entity: row.entity,
          changes: [change({ ...row, payload: winnerPayload }, winnerPayload.updated_at)]
        });

        const activityLogId = randomUUID();
        staleActivityIds.push(activityLogId);
        const stalePayload = {
          ...row.payload,
          revision: "stale-device-a",
          updated_at: "2025-06-30T09:00:00.000Z"
        };
        await syncPushOk(serverApp.app, userA.sessionToken, {
          deviceId: "device-a",
          entity: row.entity,
          changes: [
            {
              ...change({ ...row, payload: stalePayload }, stalePayload.updated_at),
              activityLogId,
              actor: "app",
              batchId: "plan-tree-stale-replay",
              beforeImage: row.payload,
              afterImage: stalePayload,
              occurredAt: "2025-06-30T09:00:00.000Z"
            }
          ]
        });

        const stored = await serverApp.database.db
          .select()
          .from(row.table)
          .where(eq(row.table.id, row.id));
        assert.equal(stored[0].payload.revision, "device-b");
      }
      const loserActivity = await serverApp.database.db
        .select()
        .from(schema.activityLog)
        .where(inArray(schema.activityLog.id, staleActivityIds));
      assert.equal(loserActivity.length, planRows.length);
      assert.ok(
        loserActivity.every(
          (entry) =>
            entry.beforeImage !== null &&
            entry.afterImage?.revision === "stale-device-a"
        )
      );

      // Template Links are first-class synced provenance and archive as an LWW
      // tombstone without touching the materialized Workout history.
      const loggedSetId = randomUUID();
      await syncPushOk(serverApp.app, userA.sessionToken, {
        deviceId: "device-b",
        entity: "logged_sets",
        changes: [
          {
            id: loggedSetId,
            payload: loggedSetPayload(
              loggedSetId,
              ids.workout,
              ids.exercise,
              "2025-06-30T10:30:00.000Z"
            ),
            updatedAt: "2025-06-30T10:30:00.000Z",
            deletedAt: null
          }
        ]
      });
      const deletedAt = "2025-06-30T11:00:00.000Z";
      const templateLink = planRows.find(
        (row) => row.entity === "template_links"
      );
      await syncPushOk(serverApp.app, userA.sessionToken, {
        deviceId: "device-b",
        entity: templateLink.entity,
        changes: [
          {
            id: templateLink.id,
            payload: {
              ...templateLink.payload,
              updated_at: deletedAt,
              deleted_at: deletedAt
            },
            updatedAt: deletedAt,
            deletedAt
          }
        ]
      });
      const storedLink = await serverApp.database.db
        .select()
        .from(schema.templateLinks)
        .where(eq(schema.templateLinks.id, ids.templateLink));
      assert.notEqual(storedLink[0].deletedAt, null);
      const storedSet = await serverApp.database.db
        .select()
        .from(schema.loggedSets)
        .where(eq(schema.loggedSets.id, loggedSetId));
      assert.equal(storedSet[0].deletedAt, null);
    } finally {
      await serverApp.database.close();
    }
  }
);

function planTreeRows(ids, updatedAt) {
  return [
    {
      entity: "workout_templates",
      table: schema.workoutTemplates,
      id: ids.workoutTemplate,
      payload: image(ids.workoutTemplate, updatedAt, {
        name: "Strength A",
        notes: null
      })
    },
    {
      entity: "template_exercises",
      table: schema.templateExercises,
      id: ids.templateExercise,
      payload: image(ids.templateExercise, updatedAt, {
        workout_template_id: ids.workoutTemplate,
        exercise_id: ids.exercise,
        position: 0,
        note: null
      })
    },
    {
      entity: "prescriptions",
      table: schema.prescriptions,
      id: ids.prescription,
      payload: image(ids.prescription, updatedAt, {
        template_exercise_id: ids.templateExercise,
        mode: "fixed",
        position: 0,
        repeat: 1,
        rest_after: null,
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
      table: schema.templateGroups,
      id: ids.templateGroup,
      payload: image(ids.templateGroup, updatedAt, {
        workout_template_id: ids.workoutTemplate,
        name: "Superset A",
        color_hex: "#FF5733",
        rounds: 3,
        position: 0
      })
    },
    {
      entity: "template_group_members",
      table: schema.templateGroupMembers,
      id: ids.templateGroupMember,
      payload: image(ids.templateGroupMember, updatedAt, {
        group_id: ids.templateGroup,
        template_exercise_id: ids.templateExercise,
        position: 0
      })
    },
    {
      entity: "routines",
      table: schema.routines,
      id: ids.routine,
      payload: image(ids.routine, updatedAt, {
        name: "Three-day strength",
        notes: null,
        cadence_kind: "weekly",
        cadence_window: 7
      })
    },
    {
      entity: "routine_entries",
      table: schema.routineEntries,
      id: ids.routineEntry,
      payload: image(ids.routineEntry, updatedAt, {
        routine_id: ids.routine,
        workout_template_id: ids.workoutTemplate,
        position: 0,
        slot: 1
      })
    },
    {
      entity: "template_links",
      table: schema.templateLinks,
      id: ids.templateLink,
      payload: image(ids.templateLink, updatedAt, {
        workout_id: ids.workout,
        workout_template_id: ids.workoutTemplate,
        routine_id: ids.routine,
        slot: 1
      })
    }
  ];
}

function image(id, updatedAt, fields) {
  return {
    id,
    ...fields,
    updated_at: updatedAt,
    deleted_at: null
  };
}

function change(row, updatedAt) {
  return {
    id: row.id,
    payload: row.payload,
    updatedAt,
    deletedAt: row.payload.deleted_at ?? null
  };
}

function loggedSetPayload(id, workoutId, exerciseId, updatedAt) {
  return image(id, updatedAt, {
    workout_id: workoutId,
    exercise_id: exerciseId,
    position: 0,
    planned_rest_after: null,
    is_completed: true,
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
    distance_entered: null,
    comment: null,
    side: null,
    rpe: null
  });
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
  const responseBody = await response.text();
  assert.equal(response.status, 200, `${body.entity}: ${responseBody}`);
  return JSON.parse(responseBody);
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
    name: "Plan Tree Sync User",
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
