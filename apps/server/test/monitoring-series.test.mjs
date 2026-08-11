import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";
import { and, eq, inArray } from "drizzle-orm";

import {
  createDrizzleIntegrationCredentialStore,
  createMigratedServerApp,
  decodeCanonicalSeriesBlob,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for Monitoring Series tests.");
}

test(
  "canonical import stores Monitoring Series as on-demand compressed blobs outside sync delta",
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
    const otherUser = await createSignedInUser(serverApp);

    try {
      const issued = await credentialStore.issueIntegrationCredential({
        userId,
        name: "Garmin sidecar"
      });
      await enableIntegrationConsents(serverApp, {
        userId,
        credentialId: issued.credential.id,
        dataClasses: ["activities", "heartRate"]
      });
      const activity = canonicalActivity(`activity-${randomUUID()}`);
      const series = heartRateSeries({
        externalId: `series-${randomUUID()}`,
        activityExternalId: activity.externalId,
        samples: [
          { offsetSeconds: 0, value: { value: 101, unit: "beatsPerMinute" } },
          { offsetSeconds: 5, value: { value: 104, unit: "beatsPerMinute" } },
          { offsetSeconds: 11, value: { value: 106, unit: "beatsPerMinute" } }
        ]
      });
      const unconsentedGpsSeries = {
        source: "garmin",
        externalId: `gps-${randomUUID()}`,
        type: "location",
        anchor: {
          kind: "activity",
          source: "garmin",
          externalId: activity.externalId
        },
        baseTime: series.baseTime,
        timezone: series.timezone,
        samples: [
          {
            offsetSeconds: 0,
            value: {
              latitude: { value: -27.4698, unit: "degree" },
              longitude: { value: 153.0251, unit: "degree" }
            }
          }
        ]
      };

      const response = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        {
          idempotencyKey: `series-import-${randomUUID()}`,
          consentedDataClasses: ["activities", "heartRate", "gps"],
          activities: [activity],
          series: [series, unconsentedGpsSeries]
        }
      );
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.seriesAccepted, 1);
      assert.equal(
        body.reviewFlags.some(
          (flag) =>
            flag.itemType === "series" &&
            flag.rule === "monitoring_data_not_consented" &&
            flag.field === "series[1]"
        ),
        true
      );

      const seriesRows = await serverApp.database.sql`
        select id, external_activity_id, source, external_id, series_type, sample_count,
               encoding, compression, blob, uncompressed_byte_length,
               compressed_byte_length, sha256, deleted_at
        from monitoring_series
        where user_id = ${userId}
      `;
      assert.equal(seriesRows.length, 1);
      assert.equal(seriesRows[0].source, "garmin");
      assert.equal(seriesRows[0].external_id, series.externalId);
      assert.equal(seriesRows[0].series_type, "heartRate");
      assert.equal(seriesRows[0].sample_count, 3);
      assert.equal(seriesRows[0].encoding, "canonical-series-delta-json-v1");
      assert.equal(seriesRows[0].compression, "gzip");
      assert.equal(
        seriesRows[0].compressed_byte_length,
        Buffer.from(seriesRows[0].blob).byteLength
      );
      assert.deepEqual(decodeCanonicalSeriesBlob(seriesRows[0].blob), series);

      const logRows = await serverApp.database.sql`
        select entity_table, after_image
        from activity_log
        where user_id = ${userId}
          and entity_table = 'monitoring_series'
      `;
      assert.equal(logRows.length, 1);
      assert.equal(logRows[0].after_image.sampleCount, 3);
      assert.equal("blob" in logRows[0].after_image, false);
      assert.equal("samples" in logRows[0].after_image, false);

      await enableIntegrationConsents(serverApp, {
        userId,
        credentialId: issued.credential.id,
        dataClasses: ["gps"]
      });
      const gpsReimportResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        {
          idempotencyKey: `series-gps-reimport-${randomUUID()}`,
          consentedDataClasses: [],
          activities: [activity],
          series: [unconsentedGpsSeries]
        }
      );
      assert.equal(gpsReimportResponse.status, 200);
      const gpsReimportBody = await gpsReimportResponse.json();
      assert.deepEqual(
        gpsReimportBody.activities.map((result) => result.status),
        ["refreshed"]
      );
      assert.equal(gpsReimportBody.seriesAccepted, 1);

      const gpsSeriesRows = await serverApp.database.sql`
        select id, external_activity_id, series_type, sample_count, blob
        from monitoring_series
        where user_id = ${userId}
        order by series_type
      `;
      assert.deepEqual(
        gpsSeriesRows.map((row) => [
          row.series_type,
          row.sample_count,
          row.external_activity_id
        ]),
        [
          ["heartRate", 3, seriesRows[0].external_activity_id],
          ["location", 1, seriesRows[0].external_activity_id]
        ]
      );
      assert.deepEqual(
        decodeCanonicalSeriesBlob(gpsSeriesRows[1].blob),
        unconsentedGpsSeries
      );

      const gpsLogRows = await serverApp.database.sql`
        select after_image
        from activity_log
        where user_id = ${userId}
          and entity_table = 'monitoring_series'
          and entity_id = ${gpsSeriesRows[1].id}
      `;
      assert.equal(gpsLogRows.length, 1);
      assert.equal(gpsLogRows[0].after_image.seriesType, "location");
      assert.equal("blob" in gpsLogRows[0].after_image, false);
      assert.equal("samples" in gpsLogRows[0].after_image, false);

      const fetchResponse = await serverApp.app.request(
        `/monitoring/series/${seriesRows[0].id}/blob`,
        {
          method: "GET",
          headers: { authorization: `Bearer ${sessionToken}` }
        }
      );
      assert.equal(fetchResponse.status, 200);
      const fetchBody = await fetchResponse.json();
      assert.equal(fetchBody.seriesId, seriesRows[0].id);
      assert.equal(fetchBody.externalActivityId, seriesRows[0].external_activity_id);
      assert.deepEqual(
        decodeCanonicalSeriesBlob(Buffer.from(fetchBody.blobBase64, "base64")),
        series
      );

      const otherUserFetchResponse = await serverApp.app.request(
        `/monitoring/series/${seriesRows[0].id}/blob`,
        {
          method: "GET",
          headers: { authorization: `Bearer ${otherUser.sessionToken}` }
        }
      );
      assert.equal(otherUserFetchResponse.status, 404);

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
          (change) => change.entity === "monitoring_series"
        ),
        false
      );

      const refreshedSeries = {
        ...series,
        samples: [
          { offsetSeconds: 0, value: { value: 111, unit: "beatsPerMinute" } },
          { offsetSeconds: 5, value: { value: 114, unit: "beatsPerMinute" } }
        ]
      };
      const refreshResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        {
          idempotencyKey: `series-refresh-${randomUUID()}`,
          consentedDataClasses: ["heartRate"],
          series: [refreshedSeries]
        }
      );
      assert.equal(refreshResponse.status, 200);
      assert.equal((await refreshResponse.json()).seriesAccepted, 1);

      const refreshedRows = await serverApp.database.sql`
        select id, sample_count, blob, sha256
        from monitoring_series
        where user_id = ${userId}
          and external_id = ${series.externalId}
      `;
      assert.equal(refreshedRows.length, 1);
      assert.equal(refreshedRows[0].id, seriesRows[0].id);
      assert.equal(refreshedRows[0].sample_count, 2);
      assert.notEqual(refreshedRows[0].sha256, seriesRows[0].sha256);
      assert.deepEqual(
        decodeCanonicalSeriesBlob(refreshedRows[0].blob),
        refreshedSeries
      );

      const tombstoneAt = new Date("2026-06-25T09:00:00.000Z");
      const tombstoneAtIso = tombstoneAt.toISOString();
      await serverApp.database.sql`
        update monitoring_series
        set updated_at = ${tombstoneAtIso}, deleted_at = ${tombstoneAtIso}
        where id = ${seriesRows[0].id}
      `;
      const tombstoneResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        {
          idempotencyKey: `series-tombstone-${randomUUID()}`,
          consentedDataClasses: ["heartRate"],
          series: [
            {
              ...refreshedSeries,
              samples: [
                {
                  offsetSeconds: 0,
                  value: { value: 118, unit: "beatsPerMinute" }
                }
              ]
            }
          ]
        }
      );
      assert.equal(tombstoneResponse.status, 200);
      assert.equal((await tombstoneResponse.json()).seriesAccepted, 0);

      const tombstonedRows = await serverApp.database.sql`
        select sample_count, deleted_at
        from monitoring_series
        where id = ${seriesRows[0].id}
      `;
      assert.equal(tombstonedRows[0].sample_count, 2);
      assert.equal(
        new Date(tombstonedRows[0].deleted_at).toISOString(),
        tombstoneAt.toISOString()
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

async function createSignedInUser(serverApp) {
  const userId = `monitoring-series-user-${randomUUID()}`;
  const sessionToken = `session-${randomUUID()}`;

  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: "Monitoring Series User",
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

function canonicalActivity(externalId) {
  return {
    source: "garmin",
    externalId,
    startedAt: "2026-06-23T20:00:00.000Z",
    endedAt: "2026-06-23T20:45:00.000Z",
    timezone: "Australia/Brisbane",
    activityType: "STRENGTH_TRAINING_CUSTOM_VENDOR_STRING",
    summary: {
      duration: { value: 2700, unit: "second" }
    },
    summaryMetrics: []
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

async function postCanonicalImport(app, secret, body) {
  return app.request("/integrations/canonical-import", {
    method: "POST",
    headers: {
      authorization: `Bearer ${secret}`,
      "content-type": "application/json"
    },
    body: JSON.stringify(body)
  });
}
