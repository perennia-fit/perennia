import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";
import { and, eq, inArray } from "drizzle-orm";

import {
  CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS,
  DEFAULT_IMPORT_SCOPED_INTEGRATION_CREDENTIAL_SCOPE,
  INTEGRATION_CREDENTIAL_ACTOR,
  SYNC_NUDGE_JOB_NAME,
  buildAgentExerciseAnalyticsResponse,
  createApp,
  createDrizzleAgentReadStore,
  createDrizzleIntegrationCredentialStore,
  createJobQueueSyncNudgePublisher,
  createMigratedServerApp,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for canonical import endpoint tests.");
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
  ]
};

const metricReading = {
  source: "garmin",
  externalId: "daily-2026-06-23:resting-heart-rate",
  metricKey: "restingHeartRate",
  value: { value: 56, unit: "beatsPerMinute" },
  at: {
    kind: "instant",
    at: "2026-06-23T08:00:00.000Z",
    timezone: "Australia/Brisbane"
  }
};

test("canonical import endpoint requires an Integration credential and delegates with actor identity", async () => {
  const calls = [];
  const nudges = [];
  const app = createApp({
    logger: { info() {}, error() {} },
    integrationCredentialStore: {
      async authenticateIntegrationCredential(secret) {
        if (secret !== "prn_integration_secret") {
          return null;
        }

        return {
          actor: INTEGRATION_CREDENTIAL_ACTOR,
          userId: "user-1",
          credentialId: "credential-1",
          credentialName: "Garmin sidecar",
          scope: DEFAULT_IMPORT_SCOPED_INTEGRATION_CREDENTIAL_SCOPE,
          rateLimitEnabled: true,
          rateLimitTimeWindow: 60 * 1000,
          rateLimitMax: 1
        };
      }
    },
    canonicalImportStore: {
      async importCanonicalBatch(input) {
        calls.push(input);
        return {
          accepted: true,
          duplicate: false,
          idempotencyKey: input.idempotencyKey,
          batchId: input.idempotencyKey,
          serverClock: "2026-06-25T08:30:00.000Z",
          activities: [],
          metricReadings: [],
          seriesAccepted: 0,
          reviewFlags: [],
          materializedWorkouts: [],
          activityLinks: [],
          activityLinkSuggestions: [],
          applied: []
        };
      }
    },
    rateLimitBackend: {
      async recordHit(input) {
        return {
          allowed: true,
          key: input.key,
          limit: input.limit,
          remaining: 0,
          resetAt: "2026-06-25T08:31:00.000Z",
          retryAfterMs: 0
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

  const missingResponse = await app.request("/integrations/canonical-import", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ idempotencyKey: "batch-1", activities: [] })
  });
  assert.equal(missingResponse.status, 401);

  const invalidResponse = await app.request("/integrations/canonical-import", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_integration_wrong",
      "content-type": "application/json"
    },
    body: JSON.stringify({ idempotencyKey: "batch-1", activities: [] })
  });
  assert.equal(invalidResponse.status, 401);

  const response = await app.request("/integrations/canonical-import", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_integration_secret",
      "content-type": "application/json"
    },
    body: JSON.stringify({
      idempotencyKey: "batch-1",
      activities: [activity],
      metricReadings: [metricReading]
    })
  });

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("x-rate-limit-limit"), "1");
  assert.equal(calls.length, 1);
  assert.equal(calls[0].userId, "user-1");
  assert.equal(calls[0].actor, "integration");
  assert.equal(calls[0].credentialId, "credential-1");
  assert.equal(calls[0].deviceId, "integration:credential-1");
  assert.deepEqual(calls[0].request.activities, [activity]);
  assert.deepEqual(nudges, []);
});

test("canonical import nudge logging never includes Monitoring Data values", async () => {
  const logEntries = [];
  const app = createApp({
    logger: {
      info() {},
      error(data, message) {
        logEntries.push({ data, message });
      }
    },
    integrationCredentialStore: {
      async authenticateIntegrationCredential(secret) {
        if (secret !== "prn_integration_secret") {
          return null;
        }

        return {
          actor: INTEGRATION_CREDENTIAL_ACTOR,
          userId: "user-1",
          credentialId: "credential-1",
          credentialName: "Garmin sidecar",
          scope: DEFAULT_IMPORT_SCOPED_INTEGRATION_CREDENTIAL_SCOPE,
          rateLimitEnabled: false,
          rateLimitTimeWindow: 60 * 1000,
          rateLimitMax: 100
        };
      }
    },
    canonicalImportStore: {
      async importCanonicalBatch(input) {
        return {
          accepted: true,
          duplicate: false,
          idempotencyKey: input.idempotencyKey,
          batchId: input.idempotencyKey,
          serverClock: "2026-06-25T08:30:00.000Z",
          activities: [],
          metricReadings: [],
          seriesAccepted: 0,
          reviewFlags: [],
          materializedWorkouts: [],
          activityLinks: [],
          activityLinkSuggestions: [],
          applied: [{ entityTable: "metric_readings", entityId: "reading-1" }]
        };
      }
    },
    syncNudgePublisher: {
      async enqueueSyncNudge() {
        throw new Error("push provider unavailable");
      }
    }
  });

  const response = await app.request("/integrations/canonical-import", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_integration_secret",
      "content-type": "application/json"
    },
    body: JSON.stringify({
      idempotencyKey: "batch-sensitive-values",
      consentedDataClasses: ["activities", "heartRate"],
      activities: [activity],
      metricReadings: [metricReading]
    })
  });

  assert.equal(response.status, 200);
  assert.equal(logEntries.length, 1);
  const serialized = JSON.stringify(logEntries);
  assert.doesNotMatch(
    serialized,
    /"value":132|"value":56|beatsPerMinute|averageHeartRate/
  );
});

test("canonical import logs and crash reports never carry raw Monitoring Data payloads", async () => {
  const logEntries = [];
  const crashReports = [];
  const sensitiveActivity = {
    ...activity,
    externalId: "activity-sensitive-observability",
    rawPayloadMarker: "RAW_IMPORT_PAYLOAD_SHOULD_NOT_LOG",
    summaryMetrics: [
      {
        source: "garmin",
        externalId: "activity-sensitive-observability:average-heart-rate",
        metricKey: "averageHeartRate",
        value: { value: 987654321, unit: "beatsPerMinute" },
        at: {
          kind: "window",
          startedAt: "2026-06-23T20:00:00.000Z",
          endedAt: "2026-06-23T20:45:00.000Z",
          timezone: "Australia/Brisbane"
        }
      }
    ]
  };
  const sensitiveMetricReading = {
    source: "garmin",
    externalId: "daily-sensitive-observability:resting-heart-rate",
    metricKey: "restingHeartRate",
    rawPayloadMarker: "RAW_IMPORT_PAYLOAD_SHOULD_NOT_LOG",
    value: { value: 123456789, unit: "beatsPerMinute" },
    at: {
      kind: "instant",
      at: "2026-06-23T08:00:00.000Z",
      timezone: "Australia/Brisbane"
    }
  };
  const sensitiveHeartRateSeries = {
    source: "garmin",
    externalId: "series-sensitive-observability:heart-rate",
    type: "heartRate",
    rawPayloadMarker: "RAW_IMPORT_PAYLOAD_SHOULD_NOT_LOG",
    anchor: {
      kind: "timeWindow",
      startedAt: "2026-06-23T20:00:00.000Z",
      endedAt: "2026-06-23T20:45:00.000Z",
      timezone: "Australia/Brisbane"
    },
    baseTime: "2026-06-23T20:00:00.000Z",
    timezone: "Australia/Brisbane",
    samples: [
      {
        offsetSeconds: 0,
        value: { value: 987654321, unit: "beatsPerMinute" }
      }
    ]
  };
  const sensitiveLocationSeries = {
    ...gpsLocationSeries({
      externalId: "series-sensitive-observability:location",
      activityExternalId: "activity-sensitive-observability"
    }),
    rawPayloadMarker: "RAW_IMPORT_PAYLOAD_SHOULD_NOT_LOG"
  };
  const request = {
    idempotencyKey: "batch-sensitive-observability",
    consentedDataClasses: ["activities", "heartRate", "gps"],
    activities: [sensitiveActivity],
    metricReadings: [sensitiveMetricReading],
    series: [sensitiveHeartRateSeries, sensitiveLocationSeries]
  };
  const app = createApp({
    logger: {
      info(data, message) {
        logEntries.push({ data, message });
      },
      error(data, message) {
        logEntries.push({ data, message });
      }
    },
    crashReporter: {
      captureException(error, context) {
        crashReports.push({
          errorName: error instanceof Error ? error.name : typeof error,
          errorMessage: error instanceof Error ? error.message : String(error),
          context
        });
      }
    },
    integrationCredentialStore: {
      async authenticateIntegrationCredential(secret) {
        if (secret !== "prn_integration_secret") {
          return null;
        }

        return {
          actor: INTEGRATION_CREDENTIAL_ACTOR,
          userId: "user-1",
          credentialId: "credential-1",
          credentialName: "Garmin sidecar",
          scope: DEFAULT_IMPORT_SCOPED_INTEGRATION_CREDENTIAL_SCOPE,
          rateLimitEnabled: false,
          rateLimitTimeWindow: 60 * 1000,
          rateLimitMax: 100
        };
      }
    },
    canonicalImportStore: {
      async importCanonicalBatch(input) {
        assert.equal(input.request.series.length, 2);
        const error = new Error(
          "RAW_IMPORT_PAYLOAD_SHOULD_NOT_LOG 987654321 -27.46981234"
        );
        error.rawImportPayload = input.request;
        throw error;
      }
    }
  });

  const response = await app.request("/integrations/canonical-import", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_integration_secret",
      "content-type": "application/json"
    },
    body: JSON.stringify(request)
  });

  assert.equal(response.status, 500);
  assert.equal(crashReports.length, 1);
  const receivedLog = logEntries.find(
    (entry) => entry.message === "canonical import received"
  );
  assert.deepEqual(receivedLog?.data.canonicalImport.counts, {
    activityCount: 1,
    metricReadingCount: 1,
    seriesCount: 2,
    consentedDataClassCount: 3
  });
  assert.deepEqual(
    receivedLog?.data.canonicalImport.references.metricReadings.items,
    [
      {
        source: "garmin",
        externalId: "daily-sensitive-observability:resting-heart-rate"
      }
    ]
  );
  assert.equal(
    crashReports[0].context.canonicalImport.batchId,
    "batch-sensitive-observability"
  );

  const serialized = JSON.stringify({ logEntries, crashReports });
  assert.match(serialized, /batch-sensitive-observability/);
  assert.match(serialized, /activity-sensitive-observability/);
  assert.match(serialized, /daily-sensitive-observability:resting-heart-rate/);
  assert.match(serialized, /series-sensitive-observability:location/);
  assert.doesNotMatch(
    serialized,
    /RAW_IMPORT_PAYLOAD_SHOULD_NOT_LOG|987654321|123456789|-27\.4698|153\.0251|beatsPerMinute|latitude|longitude|samples/
  );
});

test(
  "canonical import enqueues the existing sync nudge job after applied Integration rows",
  async () => {
    const sentJobs = [];
    const app = createApp({
      logger: { info() {}, error() {} },
      integrationCredentialStore: {
        async authenticateIntegrationCredential(secret) {
          if (secret !== "prn_integration_secret") {
            return null;
          }

          return {
            actor: INTEGRATION_CREDENTIAL_ACTOR,
            userId: "user-1",
            credentialId: "credential-1",
            credentialName: "Garmin sidecar",
            scope: DEFAULT_IMPORT_SCOPED_INTEGRATION_CREDENTIAL_SCOPE,
            rateLimitEnabled: false,
            rateLimitTimeWindow: 60 * 1000,
            rateLimitMax: 100
          };
        }
      },
      canonicalImportStore: {
        async importCanonicalBatch(input) {
          return {
            accepted: true,
            duplicate: false,
            idempotencyKey: input.idempotencyKey,
            batchId: input.idempotencyKey,
            serverClock: "2026-06-25T08:30:00.000Z",
            activities: [
              {
                itemIndex: 0,
                source: "garmin",
                externalId: "activity-123",
                status: "created",
                externalActivityId: "external-activity-1",
                reviewFlags: []
              }
            ],
            metricReadings: [],
            seriesAccepted: 0,
            reviewFlags: [],
            materializedWorkouts: [],
            activityLinks: [],
            activityLinkSuggestions: [],
            applied: [
              {
                entityTable: "external_activities",
                entityId: "external-activity-1"
              }
            ]
          };
        }
      },
      syncNudgePublisher: createJobQueueSyncNudgePublisher({
        async start() {},
        async stop() {},
        async ensureQueue() {},
        async schedule() {},
        async send(input) {
          sentJobs.push(input);
          return "sync-nudge-job-1";
        },
        async work() {}
      })
    });

    const response = await app.request("/integrations/canonical-import", {
      method: "POST",
      headers: {
        authorization: "Bearer prn_integration_secret",
        "content-type": "application/json"
      },
      body: JSON.stringify({
        idempotencyKey: "batch-nudge-job",
        consentedDataClasses: ["activities"],
        activities: [activity]
      })
    });

    assert.equal(response.status, 200);
    assert.deepEqual(sentJobs, [
      {
        name: SYNC_NUDGE_JOB_NAME,
        data: {
          userId: "user-1",
          sourceDeviceId: "integration:credential-1",
          reason: "integration_import"
        },
        options: {
          retryLimit: 0
        }
      }
    ]);
  }
);

test(
  "canonical import endpoint stores consented Monitoring Summary readings as sync-ready observations",
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
    const userId = await createUser(serverApp);

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
      const idempotencyKey = `canonical-import-${randomUUID()}`;
      const mappedActivity = {
        ...activity,
        activityType: "trail_running",
        summary: {
          duration: { value: 1800, unit: "second" },
          distance: { value: 5, unit: "kilometer" }
        }
      };
      const unconsentedMetricReading = {
        source: "garmin",
        externalId: "daily-2026-06-23:body-weight",
        metricKey: "bodyWeight",
        value: { value: 84.2, unit: "kilogram" },
        at: {
          kind: "instant",
          at: "2026-06-23T07:00:00.000Z",
          timezone: "Australia/Brisbane"
        }
      };
      const gpsSummaryReading = {
        source: "garmin",
        externalId: "activity-123:gps-latitude",
        metricKey: "gpsLatitude",
        value: { value: -27.4698, unit: "degree" },
        at: {
          kind: "instant",
          at: "2026-06-23T20:00:00.000Z",
          timezone: "Australia/Brisbane"
        }
      };
      const requestBody = {
        idempotencyKey,
        consentedDataClasses: ["activities", "heartRate", "gps"],
        activities: [
          {
            ...mappedActivity,
            acquisitionAdapterScratch: "reported as a review flag"
          }
        ],
        metricReadings: [
          metricReading,
          unconsentedMetricReading,
          gpsSummaryReading
        ],
        series: []
      };

      const response = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        requestBody
      );
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.accepted, true);
      assert.equal(body.duplicate, false);
      assert.equal(body.batchId, idempotencyKey);
      assert.deepEqual(
        body.activities.map((result) => result.status),
        ["created"]
      );
      assert.equal(body.materializedWorkouts.length, 1);
      assert.equal(
        body.materializedWorkouts[0].exerciseId,
        CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning
      );
      assert.equal(body.materializedWorkouts[0].status, "created");
      assert.equal(body.materializedWorkouts[0].setIds.length, 1);
      assert.equal(body.activityLinks.length, 1);
      assert.equal(
        body.activityLinks[0].workoutId,
        body.materializedWorkouts[0].workoutId
      );
      assert.equal(body.metricReadings.length, 2);
      assert.equal(
        body.reviewFlags.some(
          (flag) =>
            flag.itemType === "metricReading" &&
            flag.rule === "monitoring_data_not_consented"
        ),
        true
      );
      assert.equal(
        body.reviewFlags.some(
          (flag) =>
            flag.itemType === "metricReading" &&
            flag.rule === "gps_summary_not_supported"
        ),
        true
      );
      assert.equal(
        body.reviewFlags.some(
          (flag) =>
            flag.itemType === "activity" &&
            flag.rule === "canonical_activity_shape"
        ),
        true
      );

      const activityRows = await serverApp.database.sql`
        select id, user_id, device_id, source, external_id, activity_type, mapped_exercise_id, summary_json, summary_metrics_json
        from external_activities
        where user_id = ${userId}
      `;
      assert.equal(activityRows.length, 1);
      assert.equal(activityRows[0].device_id, `integration:${issued.credential.id}`);
      assert.equal(activityRows[0].source, "garmin");
      assert.equal(activityRows[0].external_id, "activity-123");
      assert.equal(activityRows[0].activity_type, "trail_running");
      assert.equal(
        activityRows[0].mapped_exercise_id,
        CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning
      );
      assert.deepEqual(activityRows[0].summary_json, mappedActivity.summary);
      assert.equal(activityRows[0].summary_metrics_json.length, 1);

      const setRows = await serverApp.database.sql`
        select id, user_id, device_id, payload, deleted_at
        from logged_sets
        where user_id = ${userId}
      `;
      assert.equal(setRows.length, 1);
      assert.equal(setRows[0].device_id, `integration:${issued.credential.id}`);
      assert.equal(setRows[0].deleted_at, null);
      assert.equal(
        setRows[0].payload.exercise_id,
        CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning
      );
      assert.equal(setRows[0].payload.exercise_name, "Trail Running");
      assert.equal(setRows[0].payload.exercise_category_name, "Running");
      assert.equal(setRows[0].payload.source, "garmin");
      assert.equal(setRows[0].payload.provenance, "integration");
      assert.equal(setRows[0].payload.external_activity_id, activityRows[0].id);
      assert.equal(setRows[0].payload.values.distance.entered, "5");
      assert.equal(setRows[0].payload.values.distance.unit, "kilometer");
      assert.equal(setRows[0].payload.values.duration.entered, "1800");
      assert.equal(setRows[0].payload.values.duration.unit, "second");

      const linkRows = await serverApp.database.sql`
        select id, user_id, device_id, workout_id, external_activity_id, link_kind, deleted_at
        from activity_links
        where user_id = ${userId}
      `;
      assert.equal(linkRows.length, 1);
      assert.equal(linkRows[0].device_id, `integration:${issued.credential.id}`);
      assert.equal(linkRows[0].workout_id, setRows[0].payload.workout_id);
      assert.equal(linkRows[0].external_activity_id, activityRows[0].id);
      assert.equal(linkRows[0].link_kind, "materialized_source");
      assert.equal(linkRows[0].deleted_at, null);

      const agentReadStore = createDrizzleAgentReadStore(serverApp.database.db);
      const exerciseSets = await agentReadStore.readExerciseSets({
        userId,
        exerciseId: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning
      });
      assert.equal(exerciseSets.length, 1);
      const analytics = buildAgentExerciseAnalyticsResponse({
        exercise: trailRunningExercise(),
        maxPoints: 10,
        sets: exerciseSets
      });
      assert.equal(analytics.totalSetCount, 1);
      assert.equal(analytics.headlineRecord.setId, setRows[0].id);
      assert.equal(analytics.headlineRecord.profile, "fastestPace");
      assert.equal(analytics.recordCatalog.maxDistance.setId, setRows[0].id);
      assert.equal(analytics.volume.points[0].setId, setRows[0].id);
      assert.equal(analytics.volume.points[0].value, 5);
      assert.equal(analytics.volume.points[0].unit, "kilometer");
      assert.equal(analytics.volume.total, 5);

      const locallyEditedSetPayload = {
        ...setRows[0].payload,
        comment: "User corrected this after import.",
        values: {
          ...setRows[0].payload.values,
          distance: {
            ...setRows[0].payload.values.distance,
            entered: "5.2"
          }
        },
        distance_entered: "5.2"
      };
      await serverApp.database.db
        .update(schema.loggedSets)
        .set({
          payload: locallyEditedSetPayload,
          updatedAt: new Date("2026-06-25T08:45:00.000Z")
        })
        .where(eq(schema.loggedSets.id, setRows[0].id));

      const editedSetRows = await serverApp.database.sql`
        select payload
        from logged_sets
        where id = ${setRows[0].id}
      `;
      assert.equal(
        editedSetRows[0].payload.comment,
        "User corrected this after import."
      );
      assert.equal(editedSetRows[0].payload.values.distance.entered, "5.2");

      const externalActivityAfterSetEditRows = await serverApp.database.sql`
        select activity_type, summary_json
        from external_activities
        where id = ${activityRows[0].id}
      `;
      assert.equal(
        externalActivityAfterSetEditRows[0].activity_type,
        "trail_running"
      );
      assert.deepEqual(
        externalActivityAfterSetEditRows[0].summary_json,
        mappedActivity.summary
      );

      const metricRows = await serverApp.database.sql`
        select mr.id, mr.external_activity_id, mr.source, mr.external_id, m.name as metric_name,
               mr.provenance, mr.scalar_value, mr.value_json
        from metric_readings mr
        inner join metrics m on m.id = mr.metric_id
        where mr.user_id = ${userId}
        order by mr.external_id
      `;
      assert.equal(metricRows.length, 2);
      assert.match(
        metricRows[0].id,
        /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
      );
      assert.deepEqual(
        metricRows.map((row) => row.external_id),
        [
          "activity-123:average-heart-rate",
          "daily-2026-06-23:resting-heart-rate"
        ]
      );
      assert.equal(metricRows[0].metric_name, "Average Heart Rate");
      assert.equal(metricRows[0].provenance, "integration");
      assert.equal(metricRows[0].scalar_value, 132);
      assert.equal(metricRows[0].external_activity_id, activityRows[0].id);
      assert.equal(metricRows[1].external_activity_id, null);
      assert.equal(metricRows.some((row) => row.metric_name === "bodyWeight"), false);
      assert.equal(metricRows[0].value_json.value, 132);
      assert.equal(metricRows[0].value_json.unit, "beatsPerMinute");
      assert.equal(metricRows[0].value_json.entered, "132");
      assert.equal(metricRows[0].value_json.reps_entered, undefined);

      const logRows = await serverApp.database.sql`
        select actor, batch_id, entity_table, before_image, after_image
        from activity_log
        where user_id = ${userId} and batch_id = ${idempotencyKey}
        order by entity_table, entity_id
      `;
      assert.equal(logRows.length, 5);
      assert.equal(new Set(logRows.map((row) => row.batch_id)).size, 1);
      assert.equal(logRows.every((row) => row.actor === "integration"), true);
      assert.deepEqual(
        logRows.map((row) => row.entity_table).sort(),
        [
          "activity_links",
          "external_activities",
          "logged_sets",
          "metric_readings",
          "metric_readings"
        ]
      );
      assert.equal(logRows.every((row) => row.before_image === null), true);
      assert.equal(
        logRows
          .filter((row) => row.entity_table !== "activity_links")
          .every((row) => row.after_image.source === "garmin"),
        true
      );
      assert.equal(
        logRows.some(
          (row) =>
            row.entity_table === "metric_readings" &&
            row.after_image.externalActivityId === activityRows[0].id
        ),
        true
      );
      assert.equal(
        logRows.some(
          (row) =>
            row.entity_table === "external_activities" &&
            row.after_image.mappedExerciseId ===
              CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning &&
            row.after_image.activityType === "trail_running"
        ),
        true
      );
      assert.equal(
        logRows.some(
          (row) =>
            row.entity_table === "logged_sets" &&
            row.after_image.external_activity_id === activityRows[0].id &&
            row.after_image.exercise_id ===
              CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning
        ),
        true
      );
      assert.equal(
        logRows.some(
          (row) =>
            row.entity_table === "activity_links" &&
            row.after_image.workoutId === setRows[0].payload.workout_id &&
            row.after_image.externalActivityId === activityRows[0].id
        ),
        true
      );

      const replayResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        requestBody
      );
      assert.equal(replayResponse.status, 200);
      const replayBody = await replayResponse.json();
      assert.equal(replayBody.accepted, true);
      assert.equal(replayBody.duplicate, true);
      assert.equal(replayBody.batchId, idempotencyKey);

      const replayLogRows = await serverApp.database.sql`
        select id
        from activity_log
        where user_id = ${userId} and batch_id = ${idempotencyKey}
      `;
      assert.equal(replayLogRows.length, 5);
      const replayMetricRows = await serverApp.database.sql`
        select id
        from metric_readings
        where user_id = ${userId}
      `;
      assert.equal(replayMetricRows.length, 2);
      assert.deepEqual(nudges, [
        {
          userId,
          sourceDeviceId: `integration:${issued.credential.id}`,
          reason: "integration_import"
        }
      ]);

      const refreshIdempotencyKey = `canonical-import-refresh-${randomUUID()}`;
      const refreshedRequestBody = {
        ...requestBody,
        idempotencyKey: refreshIdempotencyKey,
        activities: [
          {
            ...mappedActivity,
            summaryMetrics: [
              {
                ...activity.summaryMetrics[0],
                value: { value: 136, unit: "beatsPerMinute" }
              }
            ]
          }
        ],
        metricReadings: [
          {
            ...metricReading,
            value: { value: 57, unit: "beatsPerMinute" }
          }
        ]
      };
      const refreshResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        refreshedRequestBody
      );
      assert.equal(refreshResponse.status, 200);
      const refreshBody = await refreshResponse.json();
      assert.deepEqual(
        refreshBody.metricReadings.map((result) => result.status),
        ["refreshed", "refreshed"]
      );
      assert.deepEqual(
        refreshBody.materializedWorkouts.map((result) => result.status),
        ["existing"]
      );
      assert.deepEqual(
        refreshBody.activityLinks.map((result) => result.status),
        ["existing"]
      );

      const editedSetAfterRefreshRows = await serverApp.database.sql`
        select payload
        from logged_sets
        where id = ${setRows[0].id}
      `;
      assert.equal(
        editedSetAfterRefreshRows[0].payload.comment,
        "User corrected this after import."
      );
      assert.equal(
        editedSetAfterRefreshRows[0].payload.values.distance.entered,
        "5.2"
      );

      const refreshedMetricRows = await serverApp.database.sql`
        select id, external_id, scalar_value, deleted_at
        from metric_readings
        where user_id = ${userId}
        order by external_id
      `;
      assert.deepEqual(
        refreshedMetricRows.map((row) => row.id),
        metricRows.map((row) => row.id)
      );
      assert.deepEqual(
        refreshedMetricRows.map((row) => row.scalar_value),
        [136, 57]
      );

      const refreshMetricLogRows = await serverApp.database.sql`
        select before_image, after_image
        from activity_log
        where user_id = ${userId}
          and batch_id = ${refreshIdempotencyKey}
          and entity_table = 'metric_readings'
      `;
      assert.equal(refreshMetricLogRows.length, 2);
      assert.equal(
        refreshMetricLogRows.every((row) => row.before_image !== null),
        true
      );

      const refreshMaterializationLogRows = await serverApp.database.sql`
        select entity_table
        from activity_log
        where user_id = ${userId}
          and batch_id = ${refreshIdempotencyKey}
          and entity_table in ('logged_sets', 'activity_links')
      `;
      assert.equal(refreshMaterializationLogRows.length, 0);

      const tombstoneAt = new Date("2026-06-25T09:00:00.000Z");
      const tombstoneAtIso = tombstoneAt.toISOString();
      await serverApp.database.sql`
        update metric_readings
        set updated_at = ${tombstoneAtIso}, deleted_at = ${tombstoneAtIso}
        where user_id = ${userId}
          and external_id = ${metricReading.externalId}
      `;

      const tombstoneResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        {
          idempotencyKey: `canonical-import-tombstone-${randomUUID()}`,
          consentedDataClasses: ["heartRate"],
          metricReadings: [
            {
              ...metricReading,
              value: { value: 58, unit: "beatsPerMinute" }
            }
          ]
        }
      );
      assert.equal(tombstoneResponse.status, 200);
      const tombstoneBody = await tombstoneResponse.json();
      assert.deepEqual(
        tombstoneBody.metricReadings.map((result) => result.status),
        ["tombstoned"]
      );

      const tombstonedRows = await serverApp.database.sql`
        select scalar_value, deleted_at
        from metric_readings
        where user_id = ${userId}
          and external_id = ${metricReading.externalId}
      `;
      assert.equal(tombstonedRows.length, 1);
      assert.equal(tombstonedRows[0].scalar_value, 57);
      assert.equal(
        new Date(tombstonedRows[0].deleted_at).toISOString(),
        tombstoneAt.toISOString()
      );

      const unauthorizedResponse = await postCanonicalImport(
        serverApp.app,
        "prn_integration_invalid",
        {
          idempotencyKey: `canonical-import-rejected-${randomUUID()}`,
          activities: [activity]
        }
      );
      assert.equal(unauthorizedResponse.status, 401);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "canonical import stores consented body composition readings without forcing Body Tracker curation",
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
    const userId = await createUser(serverApp);

    try {
      const issued = await credentialStore.issueIntegrationCredential({
        userId,
        name: "Garmin scale sidecar"
      });
      await enableIntegrationConsents(serverApp, {
        userId,
        credentialId: issued.credential.id,
        dataClasses: ["bodyComposition"]
      });

      const trackedWeightMetricId = `body-weight-${randomUUID()}`;
      await serverApp.database.db.insert(schema.metrics).values({
        id: trackedWeightMetricId,
        userId,
        deviceId: "device:phone",
        name: "Body Weight",
        unit: "kilogram",
        valueShape: "scalar",
        metricGroup: "bodyComposition",
        goalType: "decrease",
        goalTargetValue: null,
        enabled: true,
        pinned: true,
        sortOrder: 0,
        updatedAt: new Date("2026-06-23T07:00:00.000Z"),
        deletedAt: null,
        receivedAt: new Date("2026-06-23T07:00:00.000Z")
      });

      const bodyWeightReading = {
        source: "garmin",
        externalId: `scale-${randomUUID()}:body-weight`,
        metricKey: "bodyWeight",
        value: { value: 84.2, unit: "kilogram" },
        at: {
          kind: "instant",
          at: "2026-06-24T07:00:00.000Z",
          timezone: "Australia/Brisbane"
        }
      };
      const bodyFatReading = {
        source: "garmin",
        externalId: `scale-${randomUUID()}:body-fat`,
        metricKey: "bodyFat",
        value: { value: 19.5, unit: "percent" },
        at: {
          kind: "instant",
          at: "2026-06-24T07:00:00.000Z",
          timezone: "Australia/Brisbane"
        }
      };

      const response = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        {
          idempotencyKey: `body-composition-${randomUUID()}`,
          activities: [],
          metricReadings: [bodyWeightReading, bodyFatReading],
          series: []
        }
      );
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.deepEqual(
        body.metricReadings.map((reading) => reading.status),
        ["created", "created"]
      );

      const metricRows = await serverApp.database.sql`
        select id, name, unit, metric_group, goal_type, enabled, pinned, sort_order
        from metrics
        where user_id = ${userId}
        order by name
      `;
      assert.deepEqual(
        metricRows.map((row) => ({
          name: row.name,
          group: row.metric_group,
          enabled: row.enabled,
          pinned: row.pinned
        })),
        [
          {
            name: "Body Fat",
            group: "bodyComposition",
            enabled: false,
            pinned: false
          },
          {
            name: "Body Weight",
            group: "bodyComposition",
            enabled: true,
            pinned: true
          }
        ]
      );
      assert.equal(
        metricRows.find((row) => row.name === "Body Fat").goal_type,
        "decrease"
      );
      assert.equal(
        metricRows.find((row) => row.name === "Body Weight").id,
        trackedWeightMetricId
      );

      const readingRows = await serverApp.database.sql`
        select mr.metric_id, mr.external_id, mr.provenance, mr.source, mr.scalar_value, mr.at_time
        from metric_readings mr
        where mr.user_id = ${userId}
      `;
      assert.equal(readingRows.length, 2);
      const bodyWeightRow = readingRows.find(
        (row) => row.external_id === bodyWeightReading.externalId
      );
      const bodyFatRow = readingRows.find(
        (row) => row.external_id === bodyFatReading.externalId
      );
      assert.ok(bodyWeightRow);
      assert.ok(bodyFatRow);
      assert.equal(
        bodyWeightRow.metric_id,
        trackedWeightMetricId
      );
      assert.equal(bodyWeightRow.scalar_value, 84.2);
      assert.equal(bodyFatRow.scalar_value, 19.5);
      assert.equal(
        readingRows.every(
          (row) => row.provenance === "integration" && row.source === "garmin"
        ),
        true
      );

      const visibleBodyTrackerRows = await serverApp.database.sql`
        select name
        from metrics
        where user_id = ${userId}
          and metric_group = 'bodyComposition'
          and goal_type is not null
          and enabled = true
          and pinned = true
          and deleted_at is null
      `;
      assert.deepEqual(
        visibleBodyTrackerRows.map((row) => row.name),
        ["Body Weight"]
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "canonical import re-import respects current persisted consent without resurrecting toggled-off classes",
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
    const userId = await createUser(serverApp);

    try {
      const issued = await credentialStore.issueIntegrationCredential({
        userId,
        name: "Garmin consent sidecar"
      });
      await enableIntegrationConsents(serverApp, {
        userId,
        credentialId: issued.credential.id,
        dataClasses: ["activities", "heartRate", "sleepWellness"]
      });
      await disableIntegrationConsents(serverApp, {
        userId,
        credentialId: issued.credential.id,
        dataClasses: ["heartRate"]
      });

      const consentedSleepReading = {
        source: "garmin",
        externalId: "daily-2026-06-23:sleep-duration",
        metricKey: "sleepDuration",
        value: { value: 7.5, unit: "hour" },
        at: {
          kind: "window",
          startedAt: "2026-06-22T22:00:00.000Z",
          endedAt: "2026-06-23T05:30:00.000Z",
          timezone: "Australia/Brisbane"
        }
      };
      const unconsentedBodyReading = {
        source: "garmin",
        externalId: "daily-2026-06-23:body-weight",
        metricKey: "bodyWeight",
        value: { value: 84.2, unit: "kilogram" },
        at: {
          kind: "instant",
          at: "2026-06-23T07:00:00.000Z",
          timezone: "Australia/Brisbane"
        }
      };
      const importBody = {
        idempotencyKey: `canonical-consent-off-${randomUUID()}`,
        consentedDataClasses: ["activities", "heartRate", "sleepWellness"],
        activities: [activity],
        metricReadings: [
          metricReading,
          consentedSleepReading,
          unconsentedBodyReading
        ],
        series: []
      };

      const response = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        importBody
      );
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.deepEqual(
        body.activities.map((result) => result.status),
        ["created"]
      );
      assert.deepEqual(
        body.metricReadings.map((result) => result.metricKey),
        ["sleepDuration"]
      );
      assert.equal(
        body.reviewFlags.some(
          (flag) =>
            flag.rule === "monitoring_data_not_consented" &&
            flag.field === "metricReadings[0]"
        ),
        true
      );
      assert.equal(
        body.reviewFlags.some(
          (flag) =>
            flag.rule === "monitoring_data_not_consented" &&
            flag.field === "metricReadings[2]"
        ),
        true
      );

      const metricRows = await serverApp.database.sql`
        select m.name as metric_name, mr.external_id, mr.scalar_value
        from metric_readings mr
        inner join metrics m on m.id = mr.metric_id
        where mr.user_id = ${userId}
        order by mr.external_id
      `;
      assert.deepEqual(
        metricRows.map((row) => [
          row.metric_name,
          row.external_id,
          row.scalar_value
        ]),
        [["Sleep Duration", consentedSleepReading.externalId, 7.5]]
      );

      const replayResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        {
          ...importBody,
          idempotencyKey: `canonical-consent-off-reimport-${randomUUID()}`,
          metricReadings: [
            {
              ...metricReading,
              value: { value: 58, unit: "beatsPerMinute" }
            },
            { ...consentedSleepReading, value: { value: 8, unit: "hour" } },
            unconsentedBodyReading
          ]
        }
      );
      assert.equal(replayResponse.status, 200);
      const replayBody = await replayResponse.json();
      assert.deepEqual(
        replayBody.metricReadings.map((result) => result.metricKey),
        ["sleepDuration"]
      );

      const afterReplayRows = await serverApp.database.sql`
        select m.name as metric_name, mr.external_id, mr.scalar_value
        from metric_readings mr
        inner join metrics m on m.id = mr.metric_id
        where mr.user_id = ${userId}
        order by mr.external_id
      `;
      assert.deepEqual(
        afterReplayRows.map((row) => [
          row.metric_name,
          row.external_id,
          row.scalar_value
        ]),
        [["Sleep Duration", consentedSleepReading.externalId, 8]]
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "canonical import gates GPS series on persisted consent independently of activities and heart rate",
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
    const userId = await createUser(serverApp);

    try {
      const issued = await credentialStore.issueIntegrationCredential({
        userId,
        name: "Garmin GPS consent sidecar"
      });
      await enableIntegrationConsents(serverApp, {
        userId,
        credentialId: issued.credential.id,
        dataClasses: ["activities", "heartRate"]
      });

      const externalId = `gps-consent-run-${randomUUID()}`;
      const run = {
        ...trailRunActivity(externalId, 5),
        summaryMetrics: [
          {
            ...activity.summaryMetrics[0],
            externalId: `${externalId}:average-heart-rate`
          }
        ]
      };
      const locationSeries = gpsLocationSeries({
        externalId: `${externalId}:location`,
        activityExternalId: externalId
      });

      const gpsOffResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        {
          idempotencyKey: `gps-off-${randomUUID()}`,
          consentedDataClasses: ["activities", "heartRate", "gps"],
          activities: [run],
          series: [locationSeries]
        }
      );
      assert.equal(gpsOffResponse.status, 200);
      const gpsOffBody = await gpsOffResponse.json();
      assert.deepEqual(
        gpsOffBody.activities.map((result) => result.status),
        ["created"]
      );
      assert.equal(gpsOffBody.metricReadings.length, 1);
      assert.equal(gpsOffBody.metricReadings[0].metricKey, "averageHeartRate");
      assert.deepEqual(
        gpsOffBody.materializedWorkouts.map((workout) => workout.status),
        ["created"]
      );
      assert.deepEqual(
        gpsOffBody.activityLinks.map((link) => link.status),
        ["created"]
      );
      assert.equal(gpsOffBody.seriesAccepted, 0);
      assert.equal(
        gpsOffBody.reviewFlags.some(
          (flag) =>
            flag.itemType === "series" &&
            flag.field === "series[0]" &&
            flag.rule === "monitoring_data_not_consented"
        ),
        true
      );

      const gpsOffRows = await integrationGpsStateRows(serverApp, userId, {
        externalId
      });
      assert.equal(gpsOffRows.activities.length, 1);
      assert.equal(gpsOffRows.activities[0].summary_metrics_json.length, 1);
      assert.equal(gpsOffRows.metricReadings.length, 1);
      assert.equal(gpsOffRows.loggedSets.length, 1);
      assert.equal(gpsOffRows.activityLinks.length, 1);
      assert.equal(gpsOffRows.monitoringSeries.length, 0);

      const gpsOffLogRows = await serverApp.database.sql`
        select entity_table, before_image, after_image
        from activity_log
        where user_id = ${userId}
          and batch_id = ${gpsOffBody.batchId}
        order by entity_table
      `;
      assert.deepEqual(
        gpsOffLogRows.map((row) => row.entity_table).sort(),
        [
          "activity_links",
          "external_activities",
          "logged_sets",
          "metric_readings"
        ]
      );
      assert.doesNotMatch(
        JSON.stringify(gpsOffLogRows),
        /latitude|longitude|-27\.4698|153\.0251|degree/
      );

      await enableIntegrationConsents(serverApp, {
        userId,
        credentialId: issued.credential.id,
        dataClasses: ["gps"]
      });
      const gpsOnResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        {
          idempotencyKey: `gps-on-${randomUUID()}`,
          consentedDataClasses: ["activities", "heartRate", "gps"],
          activities: [run],
          series: [locationSeries]
        }
      );
      assert.equal(gpsOnResponse.status, 200);
      const gpsOnBody = await gpsOnResponse.json();
      assert.deepEqual(
        gpsOnBody.activities.map((result) => result.status),
        ["refreshed"]
      );
      assert.equal(gpsOnBody.metricReadings.length, 1);
      assert.deepEqual(
        gpsOnBody.materializedWorkouts.map((workout) => workout.status),
        ["existing"]
      );
      assert.deepEqual(
        gpsOnBody.activityLinks.map((link) => link.status),
        ["existing"]
      );
      assert.equal(gpsOnBody.seriesAccepted, 1);

      const gpsOnRows = await integrationGpsStateRows(serverApp, userId, {
        externalId
      });
      assert.equal(gpsOnRows.activities.length, 1);
      assert.equal(gpsOnRows.metricReadings.length, 1);
      assert.equal(gpsOnRows.loggedSets.length, 1);
      assert.equal(gpsOnRows.activityLinks.length, 1);
      assert.equal(gpsOnRows.monitoringSeries.length, 1);
      assert.equal(gpsOnRows.monitoringSeries[0].series_type, "location");
      assert.equal(gpsOnRows.monitoringSeries[0].sample_count, 2);
      assert.equal(
        gpsOnRows.monitoringSeries[0].external_activity_id,
        gpsOnRows.activities[0].id
      );

      const gpsOnLogRows = await serverApp.database.sql`
        select entity_table, before_image, after_image
        from activity_log
        where user_id = ${userId}
          and batch_id = ${gpsOnBody.batchId}
        order by entity_table
      `;
      assert.deepEqual(
        gpsOnLogRows.map((row) => row.entity_table).sort(),
        ["external_activities", "metric_readings", "monitoring_series"]
      );
      assert.equal(
        gpsOnLogRows.some(
          (row) =>
            row.entity_table === "monitoring_series" &&
            row.after_image.seriesType === "location" &&
            row.after_image.sampleCount === 2 &&
            !("blob" in row.after_image) &&
            !("samples" in row.after_image)
        ),
        true
      );
      assert.doesNotMatch(
        JSON.stringify(gpsOnLogRows),
        /latitude|longitude|-27\.4698|153\.0251|degree/
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "canonical re-import respects materialized Workout and External Activity tombstones",
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
    const userId = await createUser(serverApp);

    try {
      const issued = await credentialStore.issueIntegrationCredential({
        userId,
        name: "Garmin re-import sidecar"
      });
      await enableIntegrationConsents(serverApp, {
        userId,
        credentialId: issued.credential.id,
        dataClasses: ["activities"]
      });
      const editableExternalId = `editable-reimport-${randomUUID()}`;
      const editableActivity = trailRunActivity(editableExternalId, 5);
      const importBody = {
        idempotencyKey: `canonical-reimport-editable-${randomUUID()}`,
        consentedDataClasses: ["activities"],
        activities: [editableActivity],
        metricReadings: [],
        series: []
      };
      const initialResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        importBody
      );
      assert.equal(initialResponse.status, 200);
      const initialBody = await initialResponse.json();
      assert.deepEqual(
        initialBody.materializedWorkouts.map((workout) => workout.status),
        ["created"]
      );

      const editableActivityRows = await serverApp.database.sql`
        select id, summary_json, deleted_at
        from external_activities
        where user_id = ${userId}
          and external_id = ${editableExternalId}
      `;
      assert.equal(editableActivityRows.length, 1);
      const editableSetRows = await serverApp.database.sql`
        select id, payload, deleted_at
        from logged_sets
        where user_id = ${userId}
          and payload->>'external_activity_id' = ${editableActivityRows[0].id}
      `;
      assert.equal(editableSetRows.length, 1);
      const editableLinkRows = await serverApp.database.sql`
        select id, deleted_at
        from activity_links
        where user_id = ${userId}
          and external_activity_id = ${editableActivityRows[0].id}
      `;
      assert.equal(editableLinkRows.length, 1);

      const editedPayload = {
        ...editableSetRows[0].payload,
        comment: "User edit survives re-import.",
        values: {
          ...editableSetRows[0].payload.values,
          distance: {
            ...editableSetRows[0].payload.values.distance,
            entered: "5.2"
          }
        },
        distance_entered: "5.2"
      };
      await serverApp.database.db
        .update(schema.loggedSets)
        .set({
          payload: editedPayload,
          updatedAt: new Date("2026-06-25T10:00:00.000Z")
        })
        .where(eq(schema.loggedSets.id, editableSetRows[0].id));

      const refreshIdempotencyKey = `canonical-reimport-refresh-${randomUUID()}`;
      const refreshBody = {
        ...importBody,
        idempotencyKey: refreshIdempotencyKey,
        activities: [trailRunActivity(editableExternalId, 6)]
      };
      const refreshResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        refreshBody
      );
      assert.equal(refreshResponse.status, 200);
      const refreshJson = await refreshResponse.json();
      assert.deepEqual(
        refreshJson.activities.map((activity) => activity.status),
        ["refreshed"]
      );
      assert.deepEqual(
        refreshJson.materializedWorkouts.map((workout) => workout.status),
        ["existing"]
      );
      assert.deepEqual(
        refreshJson.activityLinks.map((link) => link.status),
        ["existing"]
      );

      const refreshedActivityRows = await serverApp.database.sql`
        select summary_json, deleted_at
        from external_activities
        where id = ${editableActivityRows[0].id}
      `;
      assert.equal(refreshedActivityRows[0].summary_json.distance.value, 6);
      assert.equal(refreshedActivityRows[0].deleted_at, null);
      const refreshedSetRows = await serverApp.database.sql`
        select payload, deleted_at
        from logged_sets
        where id = ${editableSetRows[0].id}
      `;
      assert.equal(refreshedSetRows[0].payload.comment, "User edit survives re-import.");
      assert.equal(refreshedSetRows[0].payload.values.distance.entered, "5.2");
      assert.equal(refreshedSetRows[0].deleted_at, null);

      const refreshLogRows = await serverApp.database.sql`
        select entity_table, before_image, after_image
        from activity_log
        where user_id = ${userId}
          and batch_id = ${refreshIdempotencyKey}
        order by entity_table
      `;
      assert.deepEqual(
        refreshLogRows.map((row) => row.entity_table),
        ["external_activities"]
      );
      assert.notEqual(refreshLogRows[0].before_image, null);
      assert.equal(refreshLogRows[0].after_image.summary.distance.value, 6);

      const refreshReplay = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        refreshBody
      );
      assert.equal(refreshReplay.status, 200);
      assert.equal((await refreshReplay.json()).duplicate, true);
      const refreshReplayLogRows = await serverApp.database.sql`
        select id
        from activity_log
        where user_id = ${userId}
          and batch_id = ${refreshIdempotencyKey}
      `;
      assert.equal(refreshReplayLogRows.length, 1);

      const workoutTombstoneAt = new Date("2026-06-25T10:05:00.000Z");
      const workoutTombstoneIso = workoutTombstoneAt.toISOString();
      await serverApp.database.sql`
        update logged_sets
        set updated_at = ${workoutTombstoneIso}, deleted_at = ${workoutTombstoneIso}
        where id = ${editableSetRows[0].id}
      `;
      const workoutTombstoneImportKey =
        `canonical-reimport-workout-tombstone-${randomUUID()}`;
      const workoutTombstoneResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        {
          ...importBody,
          idempotencyKey: workoutTombstoneImportKey,
          activities: [trailRunActivity(editableExternalId, 7)]
        }
      );
      assert.equal(workoutTombstoneResponse.status, 200);
      const workoutTombstoneJson = await workoutTombstoneResponse.json();
      assert.deepEqual(
        workoutTombstoneJson.materializedWorkouts.map(
          (workout) => workout.status
        ),
        ["tombstoned"]
      );
      assert.deepEqual(
        workoutTombstoneJson.activityLinks.map((link) => link.status),
        ["existing"]
      );
      const tombstonedWorkoutRows = await serverApp.database.sql`
        select payload, deleted_at
        from logged_sets
        where id = ${editableSetRows[0].id}
      `;
      assert.equal(tombstonedWorkoutRows.length, 1);
      assert.equal(tombstonedWorkoutRows[0].payload.values.distance.entered, "5.2");
      assert.equal(
        new Date(tombstonedWorkoutRows[0].deleted_at).toISOString(),
        workoutTombstoneAt.toISOString()
      );
      const activityAfterWorkoutTombstoneRows = await serverApp.database.sql`
        select summary_json, deleted_at
        from external_activities
        where id = ${editableActivityRows[0].id}
      `;
      assert.equal(activityAfterWorkoutTombstoneRows[0].summary_json.distance.value, 7);
      assert.equal(activityAfterWorkoutTombstoneRows[0].deleted_at, null);
      const workoutTombstoneLogRows = await serverApp.database.sql`
        select entity_table
        from activity_log
        where user_id = ${userId}
          and batch_id = ${workoutTombstoneImportKey}
        order by entity_table
      `;
      assert.deepEqual(
        workoutTombstoneLogRows.map((row) => row.entity_table),
        ["external_activities"]
      );

      const externalTombstoneId = `external-tombstone-${randomUUID()}`;
      const externalTombstoneActivity = trailRunActivity(externalTombstoneId, 4);
      const externalImportResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        {
          idempotencyKey: `canonical-reimport-external-${randomUUID()}`,
          consentedDataClasses: ["activities"],
          activities: [externalTombstoneActivity],
          metricReadings: [],
          series: []
        }
      );
      assert.equal(externalImportResponse.status, 200);
      const externalActivityRows = await serverApp.database.sql`
        select id, summary_json
        from external_activities
        where user_id = ${userId}
          and external_id = ${externalTombstoneId}
      `;
      assert.equal(externalActivityRows.length, 1);
      const externalSetRows = await serverApp.database.sql`
        select id, payload, deleted_at
        from logged_sets
        where user_id = ${userId}
          and payload->>'external_activity_id' = ${externalActivityRows[0].id}
      `;
      assert.equal(externalSetRows.length, 1);
      const externalLinkRows = await serverApp.database.sql`
        select id, deleted_at
        from activity_links
        where user_id = ${userId}
          and external_activity_id = ${externalActivityRows[0].id}
      `;
      assert.equal(externalLinkRows.length, 1);

      const externalTombstoneAt = new Date("2026-06-25T10:10:00.000Z");
      const externalTombstoneIso = externalTombstoneAt.toISOString();
      await serverApp.database.sql`
        update external_activities
        set updated_at = ${externalTombstoneIso}, deleted_at = ${externalTombstoneIso}
        where id = ${externalActivityRows[0].id}
      `;
      const externalTombstoneImportBody = {
        idempotencyKey: `canonical-reimport-external-tombstone-${randomUUID()}`,
        consentedDataClasses: ["activities"],
        activities: [trailRunActivity(externalTombstoneId, 9)],
        metricReadings: [],
        series: []
      };
      const nudgesBeforeNoop = nudges.length;
      const externalTombstoneResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        externalTombstoneImportBody
      );
      assert.equal(externalTombstoneResponse.status, 200);
      const externalTombstoneJson = await externalTombstoneResponse.json();
      assert.deepEqual(
        externalTombstoneJson.activities.map((activity) => activity.status),
        ["tombstoned"]
      );
      assert.deepEqual(externalTombstoneJson.materializedWorkouts, []);
      assert.deepEqual(externalTombstoneJson.activityLinks, []);

      const externalAfterTombstoneRows = await serverApp.database.sql`
        select summary_json, deleted_at
        from external_activities
        where id = ${externalActivityRows[0].id}
      `;
      assert.equal(externalAfterTombstoneRows[0].summary_json.distance.value, 4);
      assert.equal(
        new Date(externalAfterTombstoneRows[0].deleted_at).toISOString(),
        externalTombstoneAt.toISOString()
      );
      const setAfterExternalTombstoneRows = await serverApp.database.sql`
        select payload, deleted_at
        from logged_sets
        where id = ${externalSetRows[0].id}
      `;
      assert.equal(setAfterExternalTombstoneRows[0].deleted_at, null);
      assert.equal(
        setAfterExternalTombstoneRows[0].payload.external_activity_id,
        externalActivityRows[0].id
      );
      const linkAfterExternalTombstoneRows = await serverApp.database.sql`
        select deleted_at
        from activity_links
        where id = ${externalLinkRows[0].id}
      `;
      assert.equal(linkAfterExternalTombstoneRows[0].deleted_at, null);

      const externalTombstoneLogRows = await serverApp.database.sql`
        select entity_table, before_image, after_image
        from activity_log
        where user_id = ${userId}
          and batch_id = ${externalTombstoneImportBody.idempotencyKey}
      `;
      assert.deepEqual(
        externalTombstoneLogRows.map((row) => row.entity_table),
        ["canonical_import_batches"]
      );
      assert.equal(externalTombstoneLogRows[0].before_image, null);
      assert.equal(externalTombstoneLogRows[0].after_image.status, "accepted_noop");

      const externalTombstoneReplay = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        externalTombstoneImportBody
      );
      assert.equal(externalTombstoneReplay.status, 200);
      assert.equal((await externalTombstoneReplay.json()).duplicate, true);
      assert.equal(nudges.length, nudgesBeforeNoop);
      const externalTombstoneReplayRows = await serverApp.database.sql`
        select id
        from activity_log
        where user_id = ${userId}
          and batch_id = ${externalTombstoneImportBody.idempotencyKey}
      `;
      assert.equal(externalTombstoneReplayRows.length, 1);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "canonical import re-import respects current data-class consent without deleting imported history",
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
    const userId = await createUser(serverApp);

    try {
      const issued = await credentialStore.issueIntegrationCredential({
        userId,
        name: "Garmin consent re-import sidecar"
      });
      await enableIntegrationConsents(serverApp, {
        userId,
        credentialId: issued.credential.id,
        dataClasses: ["activities", "heartRate"]
      });
      const externalId = `consent-reimport-${randomUUID()}`;
      const firstActivity = {
        ...activity,
        externalId,
        summaryMetrics: [
          {
            ...activity.summaryMetrics[0],
            externalId: `${externalId}:average-heart-rate`,
            value: { value: 132, unit: "beatsPerMinute" }
          }
        ]
      };
      const firstMetricReading = {
        ...metricReading,
        externalId: `${externalId}:resting-heart-rate`,
        value: { value: 56, unit: "beatsPerMinute" }
      };

      const firstResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        {
          idempotencyKey: `consent-reimport-first-${randomUUID()}`,
          activities: [firstActivity],
          metricReadings: [firstMetricReading],
          series: []
        }
      );
      assert.equal(firstResponse.status, 200);
      assert.equal((await firstResponse.json()).metricReadings.length, 2);

      await disableIntegrationConsents(serverApp, {
        userId,
        credentialId: issued.credential.id,
        dataClasses: ["heartRate"]
      });

      const secondResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        {
          idempotencyKey: `consent-reimport-second-${randomUUID()}`,
          activities: [
            {
              ...firstActivity,
              summaryMetrics: [
                {
                  ...firstActivity.summaryMetrics[0],
                  value: { value: 199, unit: "beatsPerMinute" }
                }
              ]
            }
          ],
          metricReadings: [
            {
              ...firstMetricReading,
              value: { value: 44, unit: "beatsPerMinute" }
            }
          ],
          series: []
        }
      );
      assert.equal(secondResponse.status, 200);
      const secondBody = await secondResponse.json();
      assert.deepEqual(
        secondBody.activities.map((result) => result.status),
        ["refreshed"]
      );
      assert.equal(secondBody.metricReadings.length, 0);
      assert.equal(
        secondBody.reviewFlags.some(
          (flag) =>
            flag.rule === "monitoring_data_not_consented" &&
            flag.field === "activities[0].summaryMetrics[0]"
        ),
        true
      );
      assert.equal(
        secondBody.reviewFlags.some(
          (flag) =>
            flag.rule === "monitoring_data_not_consented" &&
            flag.field === "metricReadings[0]"
        ),
        true
      );

      const metricRows = await serverApp.database.sql`
        select mr.external_id, mr.scalar_value
        from metric_readings mr
        where mr.user_id = ${userId}
        order by mr.external_id
      `;
      assert.deepEqual(
        metricRows.map((row) => [row.external_id, row.scalar_value]),
        [
          [`${externalId}:average-heart-rate`, 132],
          [`${externalId}:resting-heart-rate`, 56]
        ]
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "canonical import endpoint materializes FIT strength sets through shared validation",
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
    const userId = await createUser(serverApp);

    try {
      const issued = await credentialStore.issueIntegrationCredential({
        userId,
        name: "Garmin FIT sidecar"
      });
      await enableIntegrationConsents(serverApp, {
        userId,
        credentialId: issued.credential.id,
        dataClasses: ["activities"]
      });
      const idempotencyKey = `canonical-import-fit-strength-${randomUUID()}`;
      const fitStrengthActivity = {
        ...activity,
        externalId: "fit-strength-activity",
        activityType: "strength_training",
        summary: {
          duration: { value: 2700, unit: "second" }
        },
        sets: [
          {
            source: "garmin",
            externalId: "fit-strength-activity:set-clean",
            timezone: "Australia/Brisbane",
            performedAt: "2026-06-23T20:10:00.000Z",
            dimensions: {
              load: { value: 100, unit: "kilogram" },
              reps: { value: 5, unit: "repetition" }
            }
          },
          {
            source: "garmin",
            externalId: "fit-strength-activity:set-soft",
            timezone: "Australia/Brisbane",
            performedAt: "2026-06-23T20:15:00.000Z",
            dimensions: {
              load: { value: 351, unit: "kilogram" },
              reps: { value: 3, unit: "repetition" }
            }
          },
          {
            source: "garmin",
            externalId: "fit-strength-activity:set-hard",
            timezone: "Australia/Brisbane",
            performedAt: "2026-06-23T20:20:00.000Z",
            dimensions: {
              load: { value: 1000.01, unit: "kilogram" },
              reps: { value: 1, unit: "repetition" }
            }
          }
        ]
      };

      const response = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        {
          idempotencyKey,
          consentedDataClasses: ["activities"],
          activities: [fitStrengthActivity],
          metricReadings: [],
          series: []
        }
      );

      assert.equal(response.status, 200);
      const body = await response.json();
      assert.deepEqual(
        body.activities.map((result) => result.status),
        ["created"]
      );
      assert.equal(body.materializedWorkouts.length, 1);
      assert.equal(
        body.materializedWorkouts[0].exerciseId,
        CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.strengthTraining
      );
      assert.equal(body.materializedWorkouts[0].setIds.length, 2);
      assert.equal(body.activityLinks.length, 1);
      assert.equal(
        body.reviewFlags.some(
          (flag) =>
            flag.severity === "warning" &&
            flag.rule === "added_load_improbable" &&
            flag.field === "activities[0].sets[1].dimensions.load.value"
        ),
        true
      );
      assert.equal(
        body.reviewFlags.some(
          (flag) =>
            flag.severity === "error" &&
            flag.rule === "load_max_kilograms" &&
            flag.field === "activities[0].sets[2].dimensions.load.value"
        ),
        true
      );

      const activityRows = await serverApp.database.sql`
        select id, source, external_id, activity_type, mapped_exercise_id, sets_json
        from external_activities
        where user_id = ${userId}
      `;
      assert.equal(activityRows.length, 1);
      assert.equal(activityRows[0].activity_type, "strength_training");
      assert.equal(
        activityRows[0].mapped_exercise_id,
        CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.strengthTraining
      );
      assert.equal(activityRows[0].sets_json.length, 3);

      const setRows = await serverApp.database.sql`
        select id, payload
        from logged_sets
        where user_id = ${userId}
        order by payload->>'position'
      `;
      assert.equal(setRows.length, 2);
      assert.equal(
        setRows[0].payload.exercise_id,
        CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.strengthTraining
      );
      assert.equal(setRows[0].payload.exercise_name, "Strength Training");
      assert.equal(setRows[0].payload.exercise_category_name, "Strength");
      assert.equal(setRows[0].payload.source, "garmin");
      assert.equal(setRows[0].payload.provenance, "integration");
      assert.equal(setRows[0].payload.external_activity_id, activityRows[0].id);
      assert.equal(
        setRows[0].payload.external_set_external_id,
        "fit-strength-activity:set-clean"
      );
      assert.equal(setRows[0].payload.values.load.entered, "100");
      assert.equal(setRows[0].payload.values.load.unit, "kilogram");
      assert.equal(setRows[0].payload.values.reps.entered, "5");
      assert.equal(setRows[0].payload.values.reps.unit, "repetition");
      assert.deepEqual(setRows[0].payload.review_flags, []);
      assert.equal(
        setRows[1].payload.external_set_external_id,
        "fit-strength-activity:set-soft"
      );
      assert.equal(setRows[1].payload.values.load.entered, "351");
      assert.deepEqual(
        setRows[1].payload.review_flags.map((flag) => flag.rule),
        ["added_load_improbable"]
      );

      const agentReadStore = createDrizzleAgentReadStore(serverApp.database.db);
      const exerciseSets = await agentReadStore.readExerciseSets({
        userId,
        exerciseId: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.strengthTraining
      });
      const analytics = buildAgentExerciseAnalyticsResponse({
        exercise: strengthTrainingExercise(),
        maxPoints: 10,
        sets: exerciseSets
      });
      assert.equal(analytics.totalSetCount, 2);
      assert.equal(analytics.recordCatalog.maxLoad.setId, setRows[1].id);
      assert.equal(analytics.volume.total, 1553);

      const logRows = await serverApp.database.sql`
        select entity_table
        from activity_log
        where user_id = ${userId} and batch_id = ${idempotencyKey}
        order by entity_table, entity_id
      `;
      assert.deepEqual(
        logRows.map((row) => row.entity_table).sort(),
        ["activity_links", "external_activities", "logged_sets", "logged_sets"]
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "canonical import auto-links External Activities to overlapping hand-logged Workouts",
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
    const userId = await createUser(serverApp);
    const sessionToken = await createSession(serverApp, userId);

    try {
      const scope = randomUUID();
      const setId = (name) => `set-${name}-${scope}`;
      const workoutId = (name) => `workout-${name}-${scope}`;
      const issued = await credentialStore.issueIntegrationCredential({
        userId,
        name: "Garmin sidecar"
      });
      await enableIntegrationConsents(serverApp, {
        userId,
        credentialId: issued.credential.id,
        dataClasses: ["activities"]
      });
      await insertHandLoggedSet(serverApp, {
        userId,
        id: setId("strong"),
        workoutId: workoutId("strong"),
        startedAt: "2026-06-24T20:00:00.000Z",
        endedAt: "2026-06-24T21:00:00.000Z"
      });
      await insertHandLoggedSet(serverApp, {
        userId,
        id: setId("open"),
        workoutId: workoutId("open"),
        startedAt: "2026-06-24T22:00:00.000Z",
        endedAt: null
      });
      await insertHandLoggedSet(serverApp, {
        userId,
        id: setId("best-short"),
        workoutId: workoutId("best-short"),
        startedAt: "2026-06-24T23:00:00.000Z",
        endedAt: "2026-06-24T23:25:00.000Z"
      });
      await insertHandLoggedSet(serverApp, {
        userId,
        id: setId("best-long"),
        workoutId: workoutId("best-long"),
        startedAt: "2026-06-24T23:00:00.000Z",
        endedAt: "2026-06-25T00:10:00.000Z"
      });
      await insertHandLoggedSet(serverApp, {
        userId,
        id: setId("ambiguous-a"),
        workoutId: workoutId("ambiguous-a"),
        startedAt: "2026-06-25T01:00:00.000Z",
        endedAt: "2026-06-25T02:00:00.000Z"
      });
      await insertHandLoggedSet(serverApp, {
        userId,
        id: setId("ambiguous-b"),
        workoutId: workoutId("ambiguous-b"),
        startedAt: "2026-06-25T01:00:00.000Z",
        endedAt: "2026-06-25T02:00:00.000Z"
      });

      const linkedActivities = [
        linkedTrailRun("overlap-strong", {
          startedAt: "2026-06-24T20:05:00.000Z",
          endedAt: "2026-06-24T20:55:00.000Z"
        }),
        linkedTrailRun("overlap-strong-second", {
          startedAt: "2026-06-24T20:10:00.000Z",
          endedAt: "2026-06-24T20:20:00.000Z"
        }),
        linkedTrailRun("open-session-match", {
          startedAt: "2026-06-24T22:20:00.000Z",
          endedAt: "2026-06-24T22:50:00.000Z"
        }),
        linkedTrailRun("best-overlap", {
          startedAt: "2026-06-24T23:15:00.000Z",
          endedAt: "2026-06-24T23:55:00.000Z"
        }),
        linkedTrailRun("ambiguous-overlap", {
          startedAt: "2026-06-25T01:05:00.000Z",
          endedAt: "2026-06-25T01:55:00.000Z"
        })
      ];
      const idempotencyKey = `canonical-import-linking-${randomUUID()}`;
      const response = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        {
          idempotencyKey,
          consentedDataClasses: ["activities"],
          activities: linkedActivities,
          metricReadings: [],
          series: []
        }
      );

      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.materializedWorkouts.length, 0);
      assert.deepEqual(
        body.activityLinks.map((link) => link.workoutId).sort(),
        [
          workoutId("best-long"),
          workoutId("open"),
          workoutId("strong"),
          workoutId("strong")
        ]
      );
      assert.equal(
        body.activityLinks.every((link) => link.linkKind === "time_overlap"),
        true
      );
      assert.equal(body.activityLinkSuggestions.length, 1);
      assert.equal(
        body.activityLinkSuggestions[0].externalId,
        "ambiguous-overlap"
      );
      assert.deepEqual(
        body.activityLinkSuggestions[0].candidateWorkoutIds.sort(),
        [workoutId("ambiguous-a"), workoutId("ambiguous-b")]
      );

      const activityRows = await serverApp.database.sql`
        select id, external_id, summary_json
        from external_activities
        where user_id = ${userId}
        order by external_id
      `;
      assert.equal(activityRows.length, 5);
      const ambiguousActivity = activityRows.find(
        (row) => row.external_id === "ambiguous-overlap"
      );
      assert.ok(ambiguousActivity);

      const linkRows = await serverApp.database.sql`
        select id, workout_id, external_activity_id, link_kind, deleted_at
        from activity_links
        where user_id = ${userId}
        order by workout_id, external_activity_id
      `;
      assert.equal(linkRows.length, 4);
      assert.equal(
        linkRows.every((row) => row.link_kind === "time_overlap"),
        true
      );
      assert.equal(
        linkRows.filter((row) => row.workout_id === workoutId("strong")).length,
        2
      );
      assert.equal(
        linkRows.some(
          (row) => row.external_activity_id === ambiguousActivity.id
        ),
        false
      );

      const handLoggedRows = await serverApp.database.sql`
        select id, payload
        from logged_sets
        where user_id = ${userId}
        order by id
      `;
      assert.equal(handLoggedRows.length, 6);
      assert.equal(
        handLoggedRows.some(
          (row) => row.payload.external_activity_id !== undefined
        ),
        false
      );
      assert.deepEqual(
        activityRows.find((row) => row.external_id === "overlap-strong")
          .summary_json,
        linkedActivities[0].summary
      );

      const acceptResponse = await postActivityLink(serverApp.app, sessionToken, {
        idempotencyKey: `accept-ambiguous-${randomUUID()}`,
        externalActivityId: ambiguousActivity.id,
        workoutId: workoutId("ambiguous-a")
      });
      assert.equal(acceptResponse.status, 200);
      const accepted = await acceptResponse.json();
      assert.equal(accepted.activityLink.workoutId, workoutId("ambiguous-a"));
      assert.equal(accepted.activityLink.linkKind, "time_overlap");

      const cardinalityResponse = await postActivityLink(
        serverApp.app,
        sessionToken,
        {
          idempotencyKey: `accept-ambiguous-conflict-${randomUUID()}`,
          externalActivityId: ambiguousActivity.id,
          workoutId: workoutId("ambiguous-b")
        }
      );
      assert.equal(cardinalityResponse.status, 409);

      const unlinkResponse = await deleteActivityLink(
        serverApp.app,
        sessionToken,
        accepted.activityLink.id,
        {
          idempotencyKey: `unlink-ambiguous-${randomUUID()}`
        }
      );
      assert.equal(unlinkResponse.status, 200);
      const unlinked = await unlinkResponse.json();
      assert.equal(unlinked.activityLink.status, "tombstoned");

      const afterUnlinkRows = await serverApp.database.sql`
        select id, workout_id, external_activity_id, deleted_at
        from activity_links
        where id = ${accepted.activityLink.id}
      `;
      assert.equal(afterUnlinkRows.length, 1);
      assert.notEqual(afterUnlinkRows[0].deleted_at, null);
      const retainedActivityRows = await serverApp.database.sql`
        select id from external_activities where id = ${ambiguousActivity.id}
      `;
      assert.equal(retainedActivityRows.length, 1);
      const retainedSetRows = await serverApp.database.sql`
        select id from logged_sets where id = ${setId("ambiguous-a")}
      `;
      assert.equal(retainedSetRows.length, 1);

      const userActionLogRows = await serverApp.database.sql`
        select actor, batch_id, entity_table, before_image, after_image
        from activity_log
        where user_id = ${userId}
          and entity_table = 'activity_links'
          and actor = 'app'
        order by occurred_at
      `;
      assert.equal(userActionLogRows.length, 2);
      assert.equal(userActionLogRows[0].before_image, null);
      assert.equal(
        userActionLogRows[0].after_image.externalActivityId,
        ambiguousActivity.id
      );
      assert.equal(
        userActionLogRows[1].before_image.externalActivityId,
        ambiguousActivity.id
      );
      assert.notEqual(userActionLogRows[1].after_image.deletedAt, null);
    } finally {
      await serverApp.database.close();
    }
  }
);

function trailRunningExercise() {
  return {
    id: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning,
    library: "platform",
    name: "Trail Running",
    category: {
      id: "01910000-0000-7000-8000-000000000004",
      name: "Running"
    },
    dimensions: ["distance", "duration"],
    equipment: [],
    loadMode: "added",
    recordProfile: "fastestPace",
    favorite: false,
    active: true,
    shadowedPlatformExerciseId: null
  };
}

function strengthTrainingExercise() {
  return {
    id: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.strengthTraining,
    library: "platform",
    name: "Strength Training",
    category: {
      id: "01910000-0000-7000-8000-000000000001",
      name: "Strength"
    },
    dimensions: ["load", "reps"],
    equipment: [],
    loadMode: "added",
    recordProfile: "repMax",
    favorite: false,
    active: true,
    shadowedPlatformExerciseId: null
  };
}

async function createUser(serverApp) {
  const userId = `canonical-import-user-${randomUUID()}`;
  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: "Canonical Import User",
    email: `${userId}@example.com`,
    emailVerified: true
  });

  return userId;
}

async function createSession(serverApp, userId) {
  const sessionToken = `session-${randomUUID()}`;
  await serverApp.database.db.insert(schema.session).values({
    id: `session-row-${randomUUID()}`,
    token: sessionToken,
    userId,
    expiresAt: new Date("2099-01-01T00:00:00.000Z")
  });

  return sessionToken;
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

async function disableIntegrationConsents(
  serverApp,
  { userId, credentialId, dataClasses }
) {
  const updatedAt = new Date("2026-06-25T08:05:00.000Z");
  await serverApp.database.db
    .update(schema.integrationDataClassConsents)
    .set({
      enabled: false,
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

async function insertHandLoggedSet(
  serverApp,
  { userId, id, workoutId, startedAt, endedAt }
) {
  const updatedAt = new Date("2026-06-25T10:00:00.000Z");
  await serverApp.database.db.insert(schema.loggedSets).values({
    id,
    userId,
    deviceId: "device:phone",
    payload: {
      id,
      workout_id: workoutId,
      workout_started_at: startedAt,
      workout_ended_at: endedAt,
      workout_timezone: "Australia/Brisbane",
      workout_comment: null,
      exercise_id: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.strengthTraining,
      exercise_name: "Strength Training",
      exercise_category_id: "01910000-0000-7000-8000-000000000001",
      exercise_category_name: "Strength",
      exercise_library: "platform",
      exercise_query: "Strength Training",
      position: 0,
      values: {
        reps: {
          entered: "5",
          unit: "repetition"
        }
      },
      reps_entered: "5",
      reps_unit: "repetition",
      rpe: null,
      side: null,
      comment: null,
      updated_at: updatedAt.toISOString(),
      deleted_at: null
    },
    updatedAt,
    deletedAt: null,
    receivedAt: updatedAt
  });
}

function linkedTrailRun(externalId, { startedAt, endedAt }) {
  const durationSeconds = Math.round(
    (Date.parse(endedAt) - Date.parse(startedAt)) / 1000
  );
  return {
    ...activity,
    externalId,
    startedAt,
    endedAt,
    activityType: "trail_running",
    summary: {
      duration: { value: durationSeconds, unit: "second" },
      distance: { value: 5, unit: "kilometer" }
    },
    summaryMetrics: []
  };
}

function trailRunActivity(externalId, distanceKilometers) {
  return {
    ...activity,
    externalId,
    activityType: "trail_running",
    summary: {
      duration: { value: 1800, unit: "second" },
      distance: { value: distanceKilometers, unit: "kilometer" }
    },
    summaryMetrics: []
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

async function integrationGpsStateRows(serverApp, userId, { externalId }) {
  const activities = await serverApp.database.sql`
    select id, summary_metrics_json
    from external_activities
    where user_id = ${userId}
      and external_id = ${externalId}
  `;
  const metricReadings = await serverApp.database.sql`
    select mr.id, mr.external_activity_id, mr.external_id, m.name as metric_name
    from metric_readings mr
    inner join metrics m on m.id = mr.metric_id
    where mr.user_id = ${userId}
      and mr.external_id = ${`${externalId}:average-heart-rate`}
  `;
  const loggedSets = await serverApp.database.sql`
    select id, payload
    from logged_sets
    where user_id = ${userId}
      and payload->>'external_activity_external_id' = ${externalId}
  `;
  const activityLinks = await serverApp.database.sql`
    select id, external_activity_id
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
    select id, external_activity_id, external_id, series_type, sample_count
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

async function postActivityLink(app, sessionToken, body) {
  return app.request("/integrations/activity-links", {
    method: "POST",
    headers: {
      authorization: `Bearer ${sessionToken}`,
      "content-type": "application/json"
    },
    body: JSON.stringify(body)
  });
}

async function deleteActivityLink(app, sessionToken, linkId, body) {
  return app.request(`/integrations/activity-links/${linkId}`, {
    method: "DELETE",
    headers: {
      authorization: `Bearer ${sessionToken}`,
      "content-type": "application/json"
    },
    body: JSON.stringify(body)
  });
}
