import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";
import { and, eq, inArray } from "drizzle-orm";

import {
  CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS,
  createApp,
  createDrizzleIntegrationCredentialStore,
  createMigratedServerApp,
  decodeCanonicalSeriesBlob,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for imported data purge tests.");
}

test("imported data purge route requires a session and delegates as an app action", async () => {
  const calls = [];
  const nudges = [];
  const app = createApp({
    logger: { info() {}, error() {} },
    syncStore: {
      async verifyBearerToken(token) {
        return token === "session-token" ? { userId: "user-1" } : null;
      }
    },
    importedDataPurgeStore: {
      async purgeImportedData(input) {
        calls.push(input);
        return {
          accepted: true,
          duplicate: false,
          batchId: input.batchId,
          serverClock: "2026-06-26T01:00:00.000Z",
          source: input.source,
          scope: input.scope,
          tombstonedCounts: {
            externalActivities: 1,
            metricReadings: 1,
            monitoringSeries: 1,
            materializedSets: 1,
            activityLinks: 1
          },
          applied: [{ entityTable: "metric_readings", entityId: "reading-1" }]
        };
      }
    },
    syncNudgePublisher: {
      async enqueueSyncNudge(input) {
        nudges.push(input);
        return { enqueued: true, jobId: "nudge-1" };
      }
    }
  });

  const missingResponse = await postImportedDataPurge(app, "", {
    idempotencyKey: "purge-route-1",
    source: "garmin",
    scope: "all"
  });
  assert.equal(missingResponse.status, 401);

  const invalidResponse = await postImportedDataPurge(app, "wrong-token", {
    idempotencyKey: "purge-route-1",
    source: "garmin",
    scope: "all"
  });
  assert.equal(invalidResponse.status, 401);

  const response = await postImportedDataPurge(app, "session-token", {
    idempotencyKey: "purge-route-1",
    source: "garmin",
    scope: "all"
  });
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.accepted, true);
  assert.equal(body.batchId, "purge-route-1");
  assert.equal(body.source, "garmin");
  assert.equal(body.scope, "all");
  assert.deepEqual(calls, [
    {
      userId: "user-1",
      actor: "app",
      batchId: "purge-route-1",
      deviceId: "app:imported-data-purge",
      source: "garmin",
      scope: "all"
    }
  ]);
  assert.deepEqual(nudges, [
    {
      userId: "user-1",
      sourceDeviceId: "app:imported-data-purge",
      reason: "integration_purge"
    }
  ]);
});

test(
  "imported data purge tombstones all Garmin import rows and prevents re-import resurrection",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const nudges = [];
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false,
      syncNudgePublisher: {
        async enqueueSyncNudge(input) {
          nudges.push(input);
          return { enqueued: true, jobId: `nudge-${nudges.length}` };
        }
      }
    });
    const credentialStore = createDrizzleIntegrationCredentialStore(
      serverApp.database.db
    );
    const { userId, sessionToken } = await createSignedInUser(serverApp);

    try {
      const issued = await credentialStore.issueIntegrationCredential({
        userId,
        name: "Garmin purge sidecar"
      });
      await enableIntegrationConsents(serverApp, {
        userId,
        credentialId: issued.credential.id,
        dataClasses: ["activities", "heartRate", "gps"]
      });

      const externalId = `purge-all-run-${randomUUID()}`;
      const importBody = {
        idempotencyKey: `purge-all-import-${randomUUID()}`,
        activities: [trailRunActivity(externalId, 5)],
        series: [
          gpsLocationSeries({
            externalId: `${externalId}:location`,
            activityExternalId: externalId
          })
        ]
      };
      const importResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        importBody
      );
      assert.equal(importResponse.status, 200);
      const imported = await importResponse.json();
      assert.deepEqual(
        imported.activities.map((activity) => activity.status),
        ["created"]
      );
      assert.deepEqual(
        imported.materializedWorkouts.map((workout) => workout.status),
        ["created"]
      );
      assert.equal(imported.metricReadings.length, 1);
      assert.equal(imported.seriesAccepted, 1);

      const beforeRows = await importedGarminStateRows(serverApp, userId, {
        externalId
      });
      assert.equal(beforeRows.activities.length, 1);
      assert.equal(beforeRows.metricReadings.length, 1);
      assert.equal(beforeRows.loggedSets.length, 1);
      assert.equal(beforeRows.activityLinks.length, 1);
      assert.equal(beforeRows.monitoringSeries.length, 1);

      const purgeKey = `purge-all-${randomUUID()}`;
      const purgeResponse = await postImportedDataPurge(
        serverApp.app,
        sessionToken,
        {
          idempotencyKey: purgeKey,
          source: "garmin",
          scope: "all"
        }
      );
      assert.equal(purgeResponse.status, 200);
      const purgeBody = await purgeResponse.json();
      assert.equal(purgeBody.accepted, true);
      assert.equal(purgeBody.duplicate, false);
      assert.equal(purgeBody.batchId, purgeKey);
      assert.deepEqual(purgeBody.tombstonedCounts, {
        externalActivities: 1,
        metricReadings: 1,
        monitoringSeries: 1,
        materializedSets: 1,
        activityLinks: 1
      });

      const afterRows = await importedGarminStateRows(serverApp, userId, {
        externalId
      });
      assertAllTombstoned(afterRows.activities);
      assertAllTombstoned(afterRows.metricReadings);
      assertAllTombstoned(afterRows.loggedSets);
      assertAllTombstoned(afterRows.activityLinks);
      assertAllTombstoned(afterRows.monitoringSeries);

      const logRows = await serverApp.database.sql`
        select actor, batch_id, entity_table, entity_id, before_image, after_image
        from activity_log
        where user_id = ${userId}
          and batch_id = ${purgeKey}
      `;
      assert.equal(logRows.length, 1);
      assert.equal(logRows[0].actor, "app");
      assert.equal(logRows[0].entity_table, "imported_data_purges");
      assert.equal(logRows[0].entity_id, purgeKey);
      assert.deepEqual(logRows[0].after_image.tombstonedCounts, {
        externalActivities: 1,
        metricReadings: 1,
        monitoringSeries: 1,
        materializedSets: 1,
        activityLinks: 1
      });
      assert.doesNotMatch(
        JSON.stringify(logRows),
        /latitude|longitude|-27\.4698|153\.0251|degree|beatsPerMinute|averageHeartRate/
      );

      const syncPullResponse = await serverApp.app.request("/sync/pull", {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          protocolVersion: 1,
          cursor: null,
          limit: 100
        })
      });
      assert.equal(syncPullResponse.status, 200);
      const syncPullBody = await syncPullResponse.json();
      assert.equal(
        syncPullBody.changes.some(
          (change) =>
            change.entity === "metric_readings" &&
            change.id === beforeRows.metricReadings[0].id &&
            change.deletedAt !== null
        ),
        true
      );
      assert.equal(
        syncPullBody.changes.some(
          (change) =>
            change.entity === "logged_sets" &&
            change.id === beforeRows.loggedSets[0].id &&
            change.deletedAt !== null
        ),
        true
      );

      const reimportResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        {
          ...importBody,
          idempotencyKey: `purge-all-reimport-${randomUUID()}`
        }
      );
      assert.equal(reimportResponse.status, 200);
      const reimportBody = await reimportResponse.json();
      assert.deepEqual(
        reimportBody.activities.map((activity) => activity.status),
        ["tombstoned"]
      );
      assert.deepEqual(reimportBody.metricReadings, []);
      assert.deepEqual(reimportBody.materializedWorkouts, []);
      assert.deepEqual(reimportBody.activityLinks, []);
      assert.equal(reimportBody.seriesAccepted, 0);

      const afterReimportRows = await importedGarminStateRows(
        serverApp,
        userId,
        {
          externalId
        }
      );
      assert.equal(afterReimportRows.metricReadings.length, 1);
      assert.equal(
        afterReimportRows.metricReadings[0].id,
        beforeRows.metricReadings[0].id
      );
      assertAllTombstoned(afterReimportRows.activities);
      assertAllTombstoned(afterReimportRows.metricReadings);
      assertAllTombstoned(afterReimportRows.loggedSets);
      assertAllTombstoned(afterReimportRows.activityLinks);
      assertAllTombstoned(afterReimportRows.monitoringSeries);

      const duplicateResponse = await postImportedDataPurge(
        serverApp.app,
        sessionToken,
        {
          idempotencyKey: purgeKey,
          source: "garmin",
          scope: "all"
        }
      );
      assert.equal(duplicateResponse.status, 200);
      assert.equal((await duplicateResponse.json()).duplicate, true);
      const duplicateLogRows = await serverApp.database.sql`
        select id
        from activity_log
        where user_id = ${userId}
          and batch_id = ${purgeKey}
      `;
      assert.equal(duplicateLogRows.length, 1);
      assert.deepEqual(
        nudges.filter((nudge) => nudge.reason === "integration_purge"),
        [
          {
            userId,
            sourceDeviceId: "app:imported-data-purge",
            reason: "integration_purge"
          }
        ]
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "full imported data purge leaves hand-authored sets and metrics live",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const credentialStore = createDrizzleIntegrationCredentialStore(
      serverApp.database.db
    );
    const { userId, sessionToken } = await createSignedInUser(serverApp);

    try {
      const issued = await credentialStore.issueIntegrationCredential({
        userId,
        name: "Garmin purge survival sidecar"
      });
      await enableIntegrationConsents(serverApp, {
        userId,
        credentialId: issued.credential.id,
        dataClasses: ["activities", "heartRate", "gps"]
      });

      const externalId = `purge-hand-survival-run-${randomUUID()}`;
      const importResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        {
          idempotencyKey: `purge-hand-survival-import-${randomUUID()}`,
          activities: [trailRunActivity(externalId, 5)],
          series: [
            gpsLocationSeries({
              externalId: `${externalId}:location`,
              activityExternalId: externalId
            })
          ]
        }
      );
      assert.equal(importResponse.status, 200);

      const handRows = await insertHandAuthoredRows(serverApp, {
        userId,
        source: "garmin"
      });
      const purgeResponse = await postImportedDataPurge(
        serverApp.app,
        sessionToken,
        {
          idempotencyKey: `purge-hand-survival-${randomUUID()}`,
          source: "garmin",
          scope: "all"
        }
      );
      assert.equal(purgeResponse.status, 200);
      assert.deepEqual((await purgeResponse.json()).tombstonedCounts, {
        externalActivities: 1,
        metricReadings: 1,
        monitoringSeries: 1,
        materializedSets: 1,
        activityLinks: 1
      });

      const importedRows = await importedGarminStateRows(serverApp, userId, {
        externalId
      });
      assertAllTombstoned(importedRows.metricReadings);
      assertAllTombstoned(importedRows.loggedSets);

      const survivingRows = await handAuthoredStateRows(serverApp, handRows);
      assert.equal(survivingRows.loggedSets.length, 1);
      assert.equal(survivingRows.loggedSets[0].deleted_at, null);
      assert.equal(survivingRows.metricReadings.length, 1);
      assert.equal(survivingRows.metricReadings[0].deleted_at, null);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "GPS-only purge removes only location Monitoring Series and leaves the activity usable",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const credentialStore = createDrizzleIntegrationCredentialStore(
      serverApp.database.db
    );
    const { userId, sessionToken } = await createSignedInUser(serverApp);

    try {
      const issued = await credentialStore.issueIntegrationCredential({
        userId,
        name: "Garmin GPS purge sidecar"
      });
      await enableIntegrationConsents(serverApp, {
        userId,
        credentialId: issued.credential.id,
        dataClasses: ["activities", "heartRate", "gps"]
      });

      const externalId = `purge-gps-run-${randomUUID()}`;
      const locationSeries = gpsLocationSeries({
        externalId: `${externalId}:location`,
        activityExternalId: externalId
      });
      const importBody = {
        idempotencyKey: `purge-gps-import-${randomUUID()}`,
        activities: [trailRunActivity(externalId, 5)],
        series: [locationSeries]
      };
      const importResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        importBody
      );
      assert.equal(importResponse.status, 200);
      assert.equal((await importResponse.json()).seriesAccepted, 1);

      const beforeRows = await importedGarminStateRows(serverApp, userId, {
        externalId
      });
      assert.equal(beforeRows.activities.length, 1);
      assert.equal(beforeRows.metricReadings.length, 1);
      assert.equal(beforeRows.loggedSets.length, 1);
      assert.equal(beforeRows.activityLinks.length, 1);
      assert.equal(beforeRows.monitoringSeries.length, 1);
      assert.deepEqual(
        decodeCanonicalSeriesBlob(beforeRows.monitoringSeries[0].blob),
        locationSeries
      );

      const purgeKey = `purge-gps-${randomUUID()}`;
      const purgeResponse = await postImportedDataPurge(
        serverApp.app,
        sessionToken,
        {
          idempotencyKey: purgeKey,
          source: "garmin",
          scope: "gpsOnly"
        }
      );
      assert.equal(purgeResponse.status, 200);
      const purgeBody = await purgeResponse.json();
      assert.deepEqual(purgeBody.tombstonedCounts, {
        externalActivities: 0,
        metricReadings: 0,
        monitoringSeries: 1,
        materializedSets: 0,
        activityLinks: 0
      });

      const afterRows = await importedGarminStateRows(serverApp, userId, {
        externalId
      });
      assert.equal(afterRows.activities[0].deleted_at, null);
      assert.equal(afterRows.metricReadings[0].deleted_at, null);
      assert.equal(afterRows.loggedSets[0].deleted_at, null);
      assert.equal(afterRows.activityLinks[0].deleted_at, null);
      assertAllTombstoned(afterRows.monitoringSeries);

      const blobResponse = await serverApp.app.request(
        `/monitoring/series/${beforeRows.monitoringSeries[0].id}/blob`,
        {
          method: "GET",
          headers: { authorization: `Bearer ${sessionToken}` }
        }
      );
      assert.equal(blobResponse.status, 404);

      const logRows = await serverApp.database.sql`
        select entity_table, before_image, after_image
        from activity_log
        where user_id = ${userId}
          and batch_id = ${purgeKey}
      `;
      assert.equal(logRows.length, 1);
      assert.equal(logRows[0].entity_table, "imported_data_purges");
      assert.doesNotMatch(
        JSON.stringify(logRows),
        /latitude|longitude|-27\.4698|153\.0251|degree|beatsPerMinute|averageHeartRate/
      );

      const reimportResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        {
          ...importBody,
          idempotencyKey: `purge-gps-reimport-${randomUUID()}`
        }
      );
      assert.equal(reimportResponse.status, 200);
      const reimportBody = await reimportResponse.json();
      assert.deepEqual(
        reimportBody.activities.map((activity) => activity.status),
        ["refreshed"]
      );
      assert.deepEqual(
        reimportBody.materializedWorkouts.map((workout) => workout.status),
        ["existing"]
      );
      assert.equal(reimportBody.metricReadings.length, 1);
      assert.equal(reimportBody.seriesAccepted, 0);
    } finally {
      await serverApp.database.close();
    }
  }
);

async function createSignedInUser(serverApp) {
  const userId = `imported-purge-user-${randomUUID()}`;
  const sessionToken = `session-${randomUUID()}`;

  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: "Imported Data Purge User",
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

async function enableIntegrationConsents(
  serverApp,
  { userId, credentialId, dataClasses }
) {
  const updatedAt = new Date("2026-06-25T08:00:00.000Z");
  await serverApp.database.db
    .update(schema.integrationDataClassConsents)
    .set({
      enabled: true,
      updatedAt,
      deletedAt: null,
      receivedAt: updatedAt
    })
    .where(
      and(
        eq(schema.integrationDataClassConsents.userId, userId),
        eq(schema.integrationDataClassConsents.credentialId, credentialId),
        inArray(schema.integrationDataClassConsents.dataClass, dataClasses)
      )
    );
}

async function importedGarminStateRows(serverApp, userId, { externalId }) {
  const activities = await serverApp.database.sql`
    select id, external_id, deleted_at
    from external_activities
    where user_id = ${userId}
      and external_id = ${externalId}
  `;
  const metricReadings = await serverApp.database.sql`
    select mr.id, mr.external_activity_id, mr.external_id, mr.deleted_at
    from metric_readings mr
    where mr.user_id = ${userId}
      and mr.external_id = ${`${externalId}:average-heart-rate`}
  `;
  const loggedSets = await serverApp.database.sql`
    select id, payload, deleted_at
    from logged_sets
    where user_id = ${userId}
      and payload->>'external_activity_external_id' = ${externalId}
  `;
  const activityLinks = await serverApp.database.sql`
    select id, external_activity_id, deleted_at
    from activity_links
    where user_id = ${userId}
      and external_activity_id in (
        select id
        from external_activities
        where user_id = ${userId}
          and external_id = ${externalId}
      )
  `;
  const monitoringSeries = await serverApp.database.sql`
    select id, external_activity_id, external_id, series_type, sample_count, blob, deleted_at
    from monitoring_series
    where user_id = ${userId}
      and external_id = ${`${externalId}:location`}
  `;

  return {
    activities,
    metricReadings,
    loggedSets,
    activityLinks,
    monitoringSeries
  };
}

async function insertHandAuthoredRows(serverApp, { userId, source }) {
  const updatedAt = new Date("2026-06-25T10:00:00.000Z");
  const loggedSetId = `hand-set-${randomUUID()}`;
  const metricId = `hand-metric-${randomUUID()}`;
  const metricReadingId = `hand-reading-${randomUUID()}`;
  await serverApp.database.db.insert(schema.loggedSets).values({
    id: loggedSetId,
    userId,
    deviceId: "device:phone",
    payload: {
      id: loggedSetId,
      workout_id: `hand-workout-${randomUUID()}`,
      workout_started_at: "2026-06-25T09:00:00.000Z",
      workout_ended_at: "2026-06-25T09:45:00.000Z",
      workout_timezone: "Australia/Brisbane",
      exercise_id: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.strengthTraining,
      exercise_name: "Strength Training",
      exercise_category_id: "01910000-0000-7000-8000-000000000001",
      exercise_category_name: "Strength",
      position: 0,
      provenance: "manual",
      source,
      values: {
        reps: { entered: "5", unit: "repetition" }
      },
      reps_entered: "5",
      reps_unit: "repetition",
      updated_at: updatedAt.toISOString(),
      deleted_at: null
    },
    updatedAt,
    deletedAt: null,
    receivedAt: updatedAt
  });
  await serverApp.database.db.insert(schema.metrics).values({
    id: metricId,
    userId,
    deviceId: "device:phone",
    name: "Body Weight",
    unit: "kilogram",
    valueShape: "scalar",
    metricGroup: "body",
    goalType: null,
    goalTargetValue: null,
    enabled: true,
    pinned: true,
    sortOrder: 0,
    updatedAt,
    deletedAt: null,
    receivedAt: updatedAt
  });
  await serverApp.database.db.insert(schema.metricReadings).values({
    id: metricReadingId,
    userId,
    deviceId: "device:phone",
    metricId,
    externalActivityId: null,
    valueJson: { value: 80, unit: "kilogram", entered: "80" },
    scalarValue: 80,
    scalarEntered: "80",
    atTime: updatedAt,
    windowStartedAt: null,
    windowEndedAt: null,
    provenance: "manual",
    source,
    externalId: `hand-entered-${randomUUID()}`,
    comment: "Hand-entered body metric",
    updatedAt,
    deletedAt: null,
    receivedAt: updatedAt
  });

  return { loggedSetId, metricReadingId };
}

async function handAuthoredStateRows(
  serverApp,
  { loggedSetId, metricReadingId }
) {
  const loggedSets = await serverApp.database.sql`
    select id, deleted_at
    from logged_sets
    where id = ${loggedSetId}
  `;
  const metricReadings = await serverApp.database.sql`
    select id, deleted_at
    from metric_readings
    where id = ${metricReadingId}
  `;

  return { loggedSets, metricReadings };
}

function assertAllTombstoned(rows) {
  assert.equal(rows.length > 0, true);
  assert.equal(rows.every((row) => row.deleted_at !== null), true);
}

function trailRunActivity(externalId, kilometers) {
  return {
    source: "garmin",
    externalId,
    startedAt: "2026-06-23T20:00:00.000Z",
    endedAt: "2026-06-23T20:45:00.000Z",
    timezone: "Australia/Brisbane",
    activityType: "trail_running",
    summary: {
      duration: { value: 1800, unit: "second" },
      distance: { value: kilometers, unit: "kilometer" }
    },
    summaryMetrics: [
      {
        source: "garmin",
        externalId: `${externalId}:average-heart-rate`,
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
    mappedExerciseId: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning
  };
}

function gpsLocationSeries({ externalId, activityExternalId }) {
  return {
    source: "garmin",
    externalId,
    type: "location",
    anchor: {
      kind: "activity",
      source: "garmin",
      externalId: activityExternalId
    },
    baseTime: "2026-06-23T20:00:00.000Z",
    timezone: "Australia/Brisbane",
    samples: [
      {
        offsetSeconds: 0,
        value: {
          latitude: { value: -27.4698, unit: "degree" },
          longitude: { value: 153.0251, unit: "degree" }
        }
      },
      {
        offsetSeconds: 30,
        value: {
          latitude: { value: -27.4701, unit: "degree" },
          longitude: { value: 153.0264, unit: "degree" }
        }
      }
    ]
  };
}

function postCanonicalImport(app, secret, body) {
  return app.request("/integrations/canonical-import", {
    method: "POST",
    headers: {
      authorization: `Bearer ${secret}`,
      "content-type": "application/json"
    },
    body: JSON.stringify(body)
  });
}

function postImportedDataPurge(app, sessionToken, body) {
  return app.request("/integrations/imported-data/purge", {
    method: "POST",
    headers: {
      authorization: `Bearer ${sessionToken}`,
      "content-type": "application/json"
    },
    body: JSON.stringify(body)
  });
}
