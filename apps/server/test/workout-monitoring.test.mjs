import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  createMigratedServerApp,
  decodeCanonicalSeriesBlob,
  encodeCanonicalSeriesBlob,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for Workout Monitoring tests.");
}

test(
  "linked workout monitoring exposes summaries, on-demand series, derived HR, and no write-back",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const { userId, sessionToken } = await createSignedInUser(serverApp);
    const otherUser = await createSignedInUser(serverApp);

    try {
      const now = new Date("2026-06-25T12:00:00.000Z");
      const workoutId = `workout-${randomUUID()}`;
      const externalActivityId = `external-activity-${randomUUID()}`;
      const linkId = `activity-link-${randomUUID()}`;
      const metricId = `metric-${randomUUID()}`;
      const readingId = `reading-${randomUUID()}`;
      const seriesId = `series-${randomUUID()}`;
      const timedSetId = `set-timed-${randomUUID()}`;
      const instantSetId = `set-instant-${randomUUID()}`;
      const untimedSetId = `set-untimed-${randomUUID()}`;
      const activityExternalId = `activity-${randomUUID()}`;
      const series = heartRateSeries({
        externalId: `hr-series-${randomUUID()}`,
        activityExternalId,
        samples: [
          { offsetSeconds: 600, value: { value: 120, unit: "beatsPerMinute" } },
          { offsetSeconds: 620, value: { value: 150, unit: "beatsPerMinute" } },
          { offsetSeconds: 660, value: { value: 180, unit: "beatsPerMinute" } },
          { offsetSeconds: 1200, value: { value: 165, unit: "beatsPerMinute" } }
        ]
      });
      const encoded = encodeCanonicalSeriesBlob(series);

      await serverApp.database.db.insert(schema.externalActivities).values({
        id: externalActivityId,
        userId,
        deviceId: "integration:test",
        source: "garmin",
        externalId: activityExternalId,
        startedAt: new Date("2026-06-23T20:00:00.000Z"),
        endedAt: new Date("2026-06-23T20:45:00.000Z"),
        timezone: "Australia/Brisbane",
        activityType: "strength_training",
        mappedExerciseId: null,
        summaryJson: { duration: { value: 2700, unit: "second" } },
        summaryMetricsJson: [],
        setsJson: null,
        updatedAt: now,
        deletedAt: null,
        receivedAt: now
      });
      await serverApp.database.db.insert(schema.activityLinks).values({
        id: linkId,
        userId,
        deviceId: "integration:test",
        workoutId,
        externalActivityId,
        linkKind: "time_overlap",
        updatedAt: now,
        deletedAt: null,
        receivedAt: now
      });
      await serverApp.database.db.insert(schema.metrics).values({
        id: metricId,
        userId,
        deviceId: "integration:test",
        name: "averageHeartRate",
        unit: "beatsPerMinute",
        valueShape: "scalar",
        metricGroup: "monitoring",
        goalType: null,
        goalTargetValue: null,
        enabled: true,
        pinned: false,
        sortOrder: 0,
        updatedAt: now,
        deletedAt: null,
        receivedAt: now
      });
      await serverApp.database.db.insert(schema.metricReadings).values({
        id: readingId,
        userId,
        deviceId: "integration:test",
        metricId,
        externalActivityId,
        valueJson: { value: 132, unit: "beatsPerMinute" },
        scalarValue: 132,
        scalarEntered: "132",
        atTime: null,
        windowStartedAt: new Date("2026-06-23T20:00:00.000Z"),
        windowEndedAt: new Date("2026-06-23T20:45:00.000Z"),
        provenance: "integration",
        source: "garmin",
        externalId: `summary-${randomUUID()}`,
        comment: null,
        updatedAt: now,
        deletedAt: null,
        receivedAt: now
      });
      await serverApp.database.db.insert(schema.monitoringSeries).values({
        id: seriesId,
        userId,
        deviceId: "integration:test",
        externalActivityId,
        source: series.source,
        externalId: series.externalId,
        seriesType: series.type,
        anchorJson: series.anchor,
        baseTime: new Date(series.baseTime),
        timezone: series.timezone,
        sampleCount: series.samples.length,
        encoding: encoded.encoding,
        compression: encoded.compression,
        blob: encoded.blob,
        uncompressedByteLength: encoded.uncompressedByteLength,
        compressedByteLength: encoded.compressedByteLength,
        sha256: encoded.sha256,
        provenance: "integration",
        updatedAt: now,
        deletedAt: null,
        receivedAt: now
      });
      await serverApp.database.db.insert(schema.loggedSets).values([
        loggedSetRow({
          id: timedSetId,
          userId,
          workoutId,
          position: 0,
          performedAt: "2026-06-23T20:10:00.000Z",
          values: {
            duration: { entered: "60", unit: "second" },
            reps: { entered: "1", unit: "repetition" }
          },
          updatedAt: now
        }),
        loggedSetRow({
          id: instantSetId,
          userId,
          workoutId,
          position: 1,
          performedAt: "2026-06-23T20:20:00.000Z",
          values: {
            load: { entered: "100", unit: "kilogram" },
            reps: { entered: "5", unit: "repetition" }
          },
          updatedAt: now
        }),
        loggedSetRow({
          id: untimedSetId,
          userId,
          workoutId,
          position: 2,
          performedAt: null,
          values: {
            load: { entered: "90", unit: "kilogram" },
            reps: { entered: "8", unit: "repetition" }
          },
          updatedAt: now
        })
      ]);

      const before = await rowSnapshot(serverApp, {
        timedSetId,
        userId
      });

      const response = await serverApp.app.request(
        `/monitoring/workouts/${workoutId}`,
        {
          method: "GET",
          headers: { authorization: `Bearer ${sessionToken}` }
        }
      );
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.workoutId, workoutId);
      assert.equal(body.linkedExternalActivities.length, 1);
      assert.equal(body.linkedExternalActivities[0].id, externalActivityId);
      assert.equal(body.linkedExternalActivities[0].linkId, linkId);
      assert.equal(body.linkedExternalActivities[0].linkKind, "time_overlap");
      assert.deepEqual(body.linkedExternalActivities[0].summaryReadings, [
        {
          id: readingId,
          metricId,
          metricKey: "averageHeartRate",
          unit: "beatsPerMinute",
          value: { value: 132, unit: "beatsPerMinute" },
          scalarValue: 132,
          scalarEntered: "132",
          atTime: null,
          windowStartedAt: "2026-06-23T20:00:00.000Z",
          windowEndedAt: "2026-06-23T20:45:00.000Z",
          provenance: "integration",
          source: "garmin",
          externalId: body.linkedExternalActivities[0].summaryReadings[0].externalId,
          comment: null,
          updatedAt: now.toISOString()
        }
      ]);
      assert.deepEqual(body.linkedExternalActivities[0].series, [
        {
          seriesId,
          source: "garmin",
          externalId: series.externalId,
          seriesType: "heartRate",
          externalActivityId,
          sampleCount: 4,
          encoding: "canonical-series-delta-json-v1",
          compression: "gzip",
          sha256: encoded.sha256,
          uncompressedByteLength: encoded.uncompressedByteLength,
          compressedByteLength: encoded.compressedByteLength,
          blobPath: `/monitoring/series/${seriesId}/blob`,
          updatedAt: now.toISOString()
        }
      ]);
      assert.equal("blobBase64" in body.linkedExternalActivities[0].series[0], false);
      assert.deepEqual(body.perSetHeartRate, [
        {
          setId: timedSetId,
          position: 0,
          seriesId,
          sampleCount: 3,
          windowStartedAt: "2026-06-23T20:10:00.000Z",
          windowEndedAt: "2026-06-23T20:11:00.000Z",
          average: { value: 150, unit: "beatsPerMinute" }
        },
        {
          setId: instantSetId,
          position: 1,
          seriesId,
          sampleCount: 1,
          windowStartedAt: "2026-06-23T20:20:00.000Z",
          windowEndedAt: "2026-06-23T20:20:00.000Z",
          average: { value: 165, unit: "beatsPerMinute" }
        }
      ]);
      assert.equal(
        body.perSetHeartRate.some((entry) => entry.setId === untimedSetId),
        false
      );

      const blobResponse = await serverApp.app.request(
        body.linkedExternalActivities[0].series[0].blobPath,
        {
          method: "GET",
          headers: { authorization: `Bearer ${sessionToken}` }
        }
      );
      assert.equal(blobResponse.status, 200);
      const blobBody = await blobResponse.json();
      assert.deepEqual(
        decodeCanonicalSeriesBlob(Buffer.from(blobBody.blobBase64, "base64")),
        series
      );

      assert.deepEqual(
        await rowSnapshot(serverApp, { timedSetId, userId }),
        before
      );

      const otherUserResponse = await serverApp.app.request(
        `/monitoring/workouts/${workoutId}`,
        {
          method: "GET",
          headers: { authorization: `Bearer ${otherUser.sessionToken}` }
        }
      );
      assert.equal(otherUserResponse.status, 404);
    } finally {
      await serverApp.database.close();
    }
  }
);

async function createSignedInUser(serverApp) {
  const userId = `workout-monitoring-user-${randomUUID()}`;
  const sessionToken = `session-${randomUUID()}`;

  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: "Workout Monitoring User",
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

function loggedSetRow({
  id,
  performedAt,
  position,
  updatedAt,
  userId,
  values,
  workoutId
}) {
  return {
    id,
    userId,
    deviceId: "device:test",
    payload: {
      id,
      workout_id: workoutId,
      workout_started_at: "2026-06-23T20:00:00.000Z",
      workout_ended_at: "2026-06-23T20:45:00.000Z",
      workout_timezone: "Australia/Brisbane",
      workout_comment: null,
      performed_at: performedAt,
      exercise_id: "platform:strength",
      exercise_name: "Strength",
      exercise_category_id: "strength",
      exercise_category_name: "Strength",
      exercise_library: "platform",
      exercise_query: "Strength",
      position,
      values,
      rpe: null,
      side: null,
      comment: null,
      updated_at: updatedAt.toISOString(),
      deleted_at: null
    },
    updatedAt,
    deletedAt: null,
    receivedAt: updatedAt
  };
}

function heartRateSeries({ externalId, activityExternalId, samples }) {
  return {
    source: "garmin",
    externalId,
    type: "heartRate",
    anchor: {
      kind: "activity",
      source: "garmin",
      externalId: activityExternalId
    },
    baseTime: "2026-06-23T20:00:00.000Z",
    timezone: "Australia/Brisbane",
    samples
  };
}

async function rowSnapshot(serverApp, { timedSetId, userId }) {
  const [counts, setRows] = await Promise.all([
    serverApp.database.sql`
      select
        (select count(*)::int from logged_sets where user_id = ${userId}) as logged_sets,
        (select count(*)::int from metric_readings where user_id = ${userId}) as metric_readings,
        (select count(*)::int from monitoring_series where user_id = ${userId}) as monitoring_series,
        (select count(*)::int from activity_links where user_id = ${userId}) as activity_links
    `,
    serverApp.database.sql`
      select payload
      from logged_sets
      where id = ${timedSetId}
    `
  ]);

  return {
    counts: counts[0],
    timedPayload: setRows[0].payload
  };
}
