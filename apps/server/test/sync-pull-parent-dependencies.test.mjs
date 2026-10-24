import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test, { after, before } from "node:test";

import { and, eq } from "drizzle-orm";

import { createMigratedServerApp, schema } from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl && process.env.CI === "true") {
  throw new Error(
    "DATABASE_URL must be set for server Postgres integration tests."
  );
}

// Every Drift FK between synced tables on the device, written out from
// `.references(` in apps/mobile/lib/data/local/app_database.dart. This is the
// device's contract, kept independent of the server's own table so a drift
// between the two fails here instead of stalling a fresh replica.
const DEVICE_FOREIGN_KEYS = [
  ["exercises", "category_id", "exercise_categories"],
  ["workout_exercises", "workout_id", "workout_sessions"],
  ["workout_exercises", "exercise_id", "exercises"],
  ["exercise_groups", "workout_id", "workout_sessions"],
  ["exercise_group_members", "group_id", "exercise_groups"],
  ["exercise_group_members", "workout_exercise_id", "workout_exercises"],
  ["logged_sets", "workout_id", "workout_sessions"],
  ["logged_sets", "exercise_id", "exercises"],
  ["food_entries", "meal_id", "meals"],
  ["metric_readings", "metric_id", "metrics"],
  ["protocol_compounds", "protocol_id", "protocols"],
  ["protocol_compounds", "compound_id", "compounds"],
  ["schedules", "protocol_compound_id", "protocol_compounds"],
  ["protocol_target_outcomes", "protocol_id", "protocols"],
  ["protocol_target_outcomes", "metric_id", "metrics"],
  ["template_exercises", "workout_template_id", "workout_templates"],
  ["template_exercises", "exercise_id", "exercises"],
  ["prescriptions", "template_exercise_id", "template_exercises"],
  ["template_groups", "workout_template_id", "workout_templates"],
  ["template_group_members", "group_id", "template_groups"],
  ["template_group_members", "template_exercise_id", "template_exercises"],
  ["routine_entries", "routine_id", "routines"],
  ["routine_entries", "workout_template_id", "workout_templates"],
  ["template_links", "workout_id", "workout_sessions"],
  ["template_links", "workout_template_id", "workout_templates"],
  ["template_links", "routine_id", "routines"]
].map(([child, key, parent]) => ({ child, key, parent }));

const OPAQUE_TABLES = {
  exercise_categories: schema.exerciseCategories,
  exercises: schema.exercises,
  workout_sessions: schema.workoutSessions,
  workout_exercises: schema.workoutExercises,
  exercise_groups: schema.exerciseGroups,
  exercise_group_members: schema.exerciseGroupMembers,
  logged_sets: schema.loggedSets,
  meals: schema.meals,
  food_entries: schema.foodEntries,
  compounds: schema.compounds,
  protocols: schema.protocols,
  protocol_compounds: schema.protocolCompounds,
  schedules: schema.schedules,
  protocol_target_outcomes: schema.protocolTargetOutcomes,
  workout_templates: schema.workoutTemplates,
  template_exercises: schema.templateExercises,
  prescriptions: schema.prescriptions,
  template_groups: schema.templateGroups,
  template_group_members: schema.templateGroupMembers,
  routines: schema.routines,
  routine_entries: schema.routineEntries,
  template_links: schema.templateLinks
};

let serverApp;
before(async () => {
  if (databaseUrl) {
    serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
  }
});
after(async () => {
  await serverApp?.database.close();
});

for (const reference of DEVICE_FOREIGN_KEYS) {
  for (const mode of ["delta", "snapshot"]) {
    test(
      `a ${mode} pull page carries the ${reference.parent} a ${reference.child}.${reference.key} references when the parent was received later`,
      { skip: databaseUrl ? false : "DATABASE_URL is not set." },
      async () => {
        const owner = await createSignedInUser(serverApp);
        const db = serverApp.database.db;
        const clock = receiveClock();

        // The child's whole ancestry exists first, then the child, then the
        // referenced parent is edited — so the parent's receivedAt is newer
        // than the child's and, at one row per page, on a later page.
        const child = await insertWithAncestors(db, owner.userId, {
          entity: reference.child,
          clock
        });
        const parentId = child.fields[reference.key];
        await editRow(db, owner.userId, {
          entity: reference.parent,
          id: parentId,
          receivedAt: clock()
        });

        const pages = await pullPages(serverApp.app, owner.sessionToken, {
          mode,
          limit: 1
        });
        const device = new ForeignKeyCheckedReplica();
        for (const page of pages) {
          device.applyPage(page);
        }

        const childPageIndex = pages.findIndex(
          (page) => page.at(-1)?.id === child.id
        );
        assert.notEqual(childPageIndex, -1, "the child is a base row");
        const parentPageIndex = pages.findIndex(
          (page) =>
            page.at(-1)?.entity === reference.parent &&
            page.at(-1)?.id === parentId
        );
        assert.ok(
          parentPageIndex > childPageIndex,
          "the edited parent's own base page follows the child's"
        );

        const childPage = pages[childPageIndex];
        const carriedParent = childPage.findIndex(
          (change) =>
            change.entity === reference.parent && change.id === parentId
        );
        assert.ok(
          carriedParent !== -1 && carriedParent < childPage.length - 1,
          `the ${reference.child} page carries its ${reference.parent} ahead of it`
        );
        assert.equal(
          childPage[carriedParent].payload.label,
          "edited",
          "the carried parent is the current server row"
        );
      }
    );
  }
}

test(
  "parents are carried transitively and a tombstoned parent is carried as its tombstone",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const owner = await createSignedInUser(serverApp);
    const db = serverApp.database.db;
    const clock = receiveClock();
    const schedule = await insertWithAncestors(db, owner.userId, {
      entity: "schedules",
      clock
    });
    const protocolCompoundId = schedule.fields.protocol_compound_id;
    const [protocolCompound] = await db
      .select()
      .from(schema.protocolCompounds)
      .where(eq(schema.protocolCompounds.id, protocolCompoundId));
    const protocolId = protocolCompound.payload.protocol_id;
    const compoundId = protocolCompound.payload.compound_id;

    // Every ancestor moves past the Schedule; the Compound is archived.
    const later = clock();
    await editRow(db, owner.userId, {
      entity: "protocol_compounds",
      id: protocolCompoundId,
      receivedAt: later
    });
    await editRow(db, owner.userId, {
      entity: "protocols",
      id: protocolId,
      receivedAt: later
    });
    await editRow(db, owner.userId, {
      entity: "compounds",
      id: compoundId,
      receivedAt: later,
      deletedAt: later
    });

    const pages = await pullPages(serverApp.app, owner.sessionToken, {
      mode: "delta",
      limit: 1
    });
    const schedulePage = pages.find((page) => page.at(-1)?.id === schedule.id);
    assert.deepEqual(
      schedulePage.map((change) => change.entity),
      ["compounds", "protocols", "protocol_compounds", "schedules"]
    );
    const compound = schedulePage.find(
      (change) => change.entity === "compounds"
    );
    assert.notEqual(compound.deletedAt, null);
    new ForeignKeyCheckedReplica().applyPage(schedulePage);
  }
);

/**
 * Applies a pull page the way the device does: in one transaction, with every
 * Drift FK enforced. A row may reference a parent stored earlier or anywhere
 * in the same page (the device sorts each page parents-first); anything else
 * would roll the page back and freeze the cursor.
 */
class ForeignKeyCheckedReplica {
  constructor() {
    this.rows = new Map();
  }

  applyPage(page) {
    const staged = new Map(this.rows);
    for (const change of page) {
      staged.set(`${change.entity}:${change.id}`, change);
    }
    for (const change of page) {
      for (const reference of DEVICE_FOREIGN_KEYS) {
        const parentId = change.payload[reference.key];
        if (reference.child !== change.entity || typeof parentId !== "string") {
          continue;
        }
        assert.ok(
          staged.has(`${reference.parent}:${parentId}`),
          `page rolled back: ${change.entity} ${change.id} references a missing ${reference.parent}`
        );
      }
    }
    this.rows = staged;
  }
}

function receiveClock() {
  let tick = 0;
  return () => {
    tick += 1;
    return new Date(Date.UTC(2026, 6, 1, 8, 0, tick));
  };
}

/**
 * Inserts one row of `entity` after a fresh row for every parent it (and,
 * recursively, each parent) references, each received in topological order.
 */
async function insertWithAncestors(db, userId, { entity, clock }) {
  const fields = {};
  for (const reference of DEVICE_FOREIGN_KEYS) {
    if (reference.child !== entity) {
      continue;
    }
    const parent = await insertWithAncestors(db, userId, {
      entity: reference.parent,
      clock
    });
    fields[reference.key] = parent.id;
  }
  const id = randomUUID();
  await insertRow(db, userId, { entity, id, fields, receivedAt: clock() });
  return { entity, id, fields };
}

async function insertRow(db, userId, { entity, id, fields, receivedAt }) {
  const updatedAt = new Date("2026-07-01T07:00:00.000Z");
  if (entity === "metrics") {
    await db.insert(schema.metrics).values({
      id,
      userId,
      deviceId: "integration:garmin",
      name: "original",
      unit: "kilogram",
      valueShape: "scalar",
      metricGroup: "body",
      enabled: true,
      pinned: false,
      sortOrder: 0,
      updatedAt,
      deletedAt: null,
      receivedAt
    });
    return;
  }
  if (entity === "metric_readings") {
    await db.insert(schema.metricReadings).values({
      id,
      userId,
      deviceId: "integration:garmin",
      metricId: fields.metric_id,
      valueJson: { value: 80, unit: "kilogram" },
      scalarValue: 80,
      scalarEntered: "80",
      atTime: updatedAt,
      windowStartedAt: null,
      windowEndedAt: null,
      provenance: "imported",
      source: "garmin",
      updatedAt,
      deletedAt: null,
      receivedAt
    });
    return;
  }
  await db.insert(OPAQUE_TABLES[entity]).values({
    id,
    userId,
    deviceId: "phone-a",
    payload: {
      id,
      ...fields,
      label: "original",
      updated_at: updatedAt.toISOString(),
      deleted_at: null
    },
    updatedAt,
    deletedAt: null,
    receivedAt
  });
}

/** A later edit (or archive) of a row, received after everything before it. */
async function editRow(db, userId, { entity, id, receivedAt, deletedAt = null }) {
  const updatedAt = receivedAt;
  if (entity === "metrics") {
    await db
      .update(schema.metrics)
      .set({ name: "edited", updatedAt, deletedAt, receivedAt })
      .where(and(eq(schema.metrics.id, id), eq(schema.metrics.userId, userId)));
    return;
  }
  const table = OPAQUE_TABLES[entity];
  const [existing] = await db.select().from(table).where(eq(table.id, id));
  await db
    .update(table)
    .set({
      payload: {
        ...existing.payload,
        label: "edited",
        updated_at: updatedAt.toISOString(),
        deleted_at: deletedAt?.toISOString() ?? null
      },
      updatedAt,
      deletedAt,
      receivedAt
    })
    .where(and(eq(table.id, id), eq(table.userId, userId)));
}

async function pullPages(app, token, { mode, limit }) {
  const pages = [];
  let cursor = null;
  for (let index = 0; index < 200; index += 1) {
    const response = await app.request("/sync/pull", {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json"
      },
      body: JSON.stringify({ protocolVersion: 1, cursor, limit, mode })
    });
    assert.equal(response.status, 200, await response.clone().text());
    const window = await response.json();
    if (window.changes.length === 0) {
      return pages;
    }
    pages.push(
      window.changes.map((change) =>
        change.entity === "metrics"
          ? { ...change, payload: { ...change.payload, label: change.payload.name } }
          : change
      )
    );
    assert.notEqual(window.nextCursor, cursor);
    cursor = window.nextCursor;
  }
  assert.fail("pull did not settle");
}

async function createSignedInUser(serverApp) {
  const userId = `pull-parent-user-${randomUUID()}`;
  const sessionToken = `pull-parent-session-${randomUUID()}`;
  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: "Pull Parent User",
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
