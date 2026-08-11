import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { eq } from "drizzle-orm";
import {
  CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS,
  createDrizzleExternalActivityStore,
  createMigratedServerApp,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for External Activity tests.");
}

const activity = {
  source: "garmin",
  externalId: "activity-123",
  startedAt: "2026-06-23T20:00:00.000Z",
  endedAt: "2026-06-23T20:45:00.000Z",
  timezone: "Australia/Brisbane",
  activityType: "STRENGTH_TRAINING_CUSTOM_VENDOR_STRING",
  summary: {
    duration: { value: 2700, unit: "second" },
    distance: { value: 0, unit: "meter" }
  },
  summaryMetrics: [
    {
      source: "garmin",
      externalId: "activity-123:average-heart-rate",
      metricKey: "averageHeartRate",
      value: { value: 132, unit: "beatsPerMinute" },
      at: {
        kind: "window",
        startedAt: "2026-06-23T20:00:00.000Z",
        endedAt: "2026-06-23T20:45:00.000Z",
        timezone: "Australia/Brisbane"
      }
    }
  ],
  sets: [
    {
      source: "garmin",
      externalId: "activity-123:set-1",
      timezone: "Australia/Brisbane",
      performedAt: "2026-06-23T20:12:30.000Z",
      dimensions: {
        load: { value: 100, unit: "kilogram" },
        reps: { value: 5, unit: "repetition" }
      }
    }
  ]
};

test(
  "External Activity stores and reads back one canonical source observation",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const store = createDrizzleExternalActivityStore(serverApp.database.db);
    const userId = await createUser(serverApp);
    const mappedActivity = {
      ...activity,
      activityType: "trail_running",
      mappedExerciseId: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning
    };

    try {
      const stored = await store.storeCanonicalActivity({
        userId,
        deviceId: "integration:garmin",
        activity: mappedActivity,
        importedAt: new Date("2026-06-25T07:05:00.000Z")
      });
      const readBack = await store.findExternalActivity({
        userId,
        source: activity.source,
        externalId: activity.externalId
      });

      assert.ok(stored);
      assert.ok(readBack);
      assert.equal(stored.id, readBack.id);
      assert.match(
        stored.id,
        /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      );
      assert.equal(readBack.source, "garmin");
      assert.equal(readBack.externalId, "activity-123");
      assert.equal(readBack.activityType, "trail_running");
      assert.equal(
        readBack.mappedExerciseId,
        CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning
      );
      assert.equal(readBack.startedAt, activity.startedAt);
      assert.equal(readBack.endedAt, activity.endedAt);
      assert.equal(readBack.timezone, activity.timezone);
      assert.deepEqual(readBack.summary, activity.summary);
      assert.deepEqual(readBack.summaryMetrics, activity.summaryMetrics);
      assert.deepEqual(readBack.sets, activity.sets);
      assert.equal(readBack.deletedAt, null);

      const rows = await serverApp.database.sql`
        select source, external_id, activity_type, mapped_exercise_id, summary_json
        from external_activities
        where id = ${stored.id}
      `;
      assert.equal(rows.length, 1);
      assert.equal(rows[0].source, "garmin");
      assert.equal(rows[0].external_id, "activity-123");
      assert.equal(rows[0].activity_type, "trail_running");
      assert.equal(
        rows[0].mapped_exercise_id,
        CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning
      );
      assert.deepEqual(rows[0].summary_json, activity.summary);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "External Activity import is last-import-wins by source and externalId",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const store = createDrizzleExternalActivityStore(serverApp.database.db);
    const userId = await createUser(serverApp);
    const refreshedActivity = {
      ...activity,
      activityType: "updated_raw_vendor_type",
      summary: {
        ...activity.summary,
        duration: { value: 2760, unit: "second" }
      }
    };

    try {
      const first = await store.storeCanonicalActivity({
        userId,
        deviceId: "integration:garmin",
        activity,
        importedAt: new Date("2026-06-25T07:05:00.000Z")
      });
      const second = await store.storeCanonicalActivity({
        userId,
        deviceId: "integration:garmin",
        activity: refreshedActivity,
        importedAt: new Date("2026-06-25T07:06:00.000Z")
      });
      const readBack = await store.findExternalActivity({
        userId,
        source: activity.source,
        externalId: activity.externalId
      });

      assert.ok(first);
      assert.ok(second);
      assert.ok(readBack);
      assert.equal(second.id, first.id);
      assert.equal(readBack.id, first.id);
      assert.equal(readBack.activityType, "updated_raw_vendor_type");
      assert.deepEqual(readBack.summary, refreshedActivity.summary);
      assert.equal(readBack.updatedAt, "2026-06-25T07:06:00.000Z");

      const countRows = await serverApp.database.sql`
        select count(*)::int as count
        from external_activities
        where user_id = ${userId}
          and source = ${activity.source}
          and external_id = ${activity.externalId}
      `;
      assert.equal(Number(countRows[0].count), 1);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "External Activity source ids are isolated by user",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const store = createDrizzleExternalActivityStore(serverApp.database.db);
    const userAId = await createUser(serverApp);
    const userBId = await createUser(serverApp);
    const deletedAt = new Date("2026-06-25T07:09:00.000Z");
    const userAActivity = {
      ...activity,
      activityType: "user_a_vendor_type"
    };
    const userBActivity = {
      ...activity,
      activityType: "user_b_vendor_type",
      summary: {
        ...activity.summary,
        duration: { value: 2820, unit: "second" }
      }
    };

    try {
      const firstA = await store.storeCanonicalActivity({
        userId: userAId,
        deviceId: "integration:garmin",
        activity: userAActivity,
        importedAt: new Date("2026-06-25T07:05:00.000Z")
      });
      const firstB = await store.storeCanonicalActivity({
        userId: userBId,
        deviceId: "integration:garmin",
        activity: userBActivity,
        importedAt: new Date("2026-06-25T07:06:00.000Z")
      });
      const readA = await store.findExternalActivity({
        userId: userAId,
        source: activity.source,
        externalId: activity.externalId
      });
      const readB = await store.findExternalActivity({
        userId: userBId,
        source: activity.source,
        externalId: activity.externalId
      });

      assert.ok(firstA);
      assert.ok(firstB);
      assert.ok(readA);
      assert.ok(readB);
      assert.notEqual(firstA.id, firstB.id);
      assert.equal(readA.userId, userAId);
      assert.equal(readB.userId, userBId);
      assert.equal(readA.activityType, "user_a_vendor_type");
      assert.equal(readB.activityType, "user_b_vendor_type");

      await serverApp.database.db
        .update(schema.externalActivities)
        .set({
          deletedAt,
          updatedAt: deletedAt
        })
        .where(eq(schema.externalActivities.id, firstA.id));

      const secondB = await store.storeCanonicalActivity({
        userId: userBId,
        deviceId: "integration:garmin",
        activity: {
          ...userBActivity,
          activityType: "user_b_after_user_a_tombstone"
        },
        importedAt: new Date("2026-06-25T07:10:00.000Z")
      });
      const hiddenA = await store.findExternalActivity({
        userId: userAId,
        source: activity.source,
        externalId: activity.externalId
      });
      const refreshedB = await store.findExternalActivity({
        userId: userBId,
        source: activity.source,
        externalId: activity.externalId
      });
      const rows = await serverApp.database.sql`
        select id, user_id, activity_type, deleted_at
        from external_activities
        where source = ${activity.source}
          and external_id = ${activity.externalId}
          and (user_id = ${userAId} or user_id = ${userBId})
        order by user_id
      `;

      assert.ok(secondB);
      assert.ok(refreshedB);
      assert.equal(secondB.id, firstB.id);
      assert.equal(hiddenA, null);
      assert.equal(refreshedB.id, firstB.id);
      assert.equal(
        refreshedB.activityType,
        "user_b_after_user_a_tombstone"
      );
      assert.equal(rows.length, 2);

      const userARow = rows.find((row) => row.user_id === userAId);
      const userBRow = rows.find((row) => row.user_id === userBId);
      assert.ok(userARow);
      assert.ok(userBRow);
      assert.equal(userARow.id, firstA.id);
      assert.equal(userBRow.id, firstB.id);
      assert.equal(
        new Date(userARow.deleted_at).toISOString(),
        deletedAt.toISOString()
      );
      assert.equal(userBRow.deleted_at, null);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "External Activity import respects tombstones and does not resurrect a deleted observation",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const store = createDrizzleExternalActivityStore(serverApp.database.db);
    const userId = await createUser(serverApp);
    const deletedAt = new Date("2026-06-25T07:07:00.000Z");

    try {
      const first = await store.storeCanonicalActivity({
        userId,
        deviceId: "integration:garmin",
        activity,
        importedAt: new Date("2026-06-25T07:05:00.000Z")
      });
      assert.ok(first);

      await serverApp.database.db
        .update(schema.externalActivities)
        .set({
          deletedAt,
          updatedAt: deletedAt
        })
        .where(eq(schema.externalActivities.id, first.id));

      const resurrected = await store.storeCanonicalActivity({
        userId,
        deviceId: "integration:garmin",
        activity: {
          ...activity,
          activityType: "resurrection_attempt"
        },
        importedAt: new Date("2026-06-25T07:08:00.000Z")
      });
      const readBack = await store.findExternalActivity({
        userId,
        source: activity.source,
        externalId: activity.externalId
      });
      const rows = await serverApp.database.sql`
        select activity_type, updated_at, deleted_at
        from external_activities
        where id = ${first.id}
      `;

      assert.equal(resurrected, null);
      assert.equal(readBack, null);
      assert.equal(rows.length, 1);
      assert.equal(rows[0].activity_type, activity.activityType);
      assert.equal(
        new Date(rows[0].updated_at).toISOString(),
        deletedAt.toISOString()
      );
      assert.equal(
        new Date(rows[0].deleted_at).toISOString(),
        deletedAt.toISOString()
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

async function createUser(serverApp) {
  const userId = `external-activity-user-${randomUUID()}`;

  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: "External Activity User",
    email: `${userId}@example.com`,
    emailVerified: true
  });

  return userId;
}
