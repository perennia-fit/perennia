import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import test from "node:test";

import { eq } from "drizzle-orm";

import {
  CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS,
  GARMIN_BACKFILL_JOB_NAME,
  GARMIN_CONSENT_DATA_CLASSES_ROUTE_PATH,
  GARMIN_OFFICIAL_ACQUISITION_ADAPTER,
  GARMIN_RECONCILIATION_JOB_NAME,
  GARMIN_WEBHOOK_JOB_NAME,
  GARMIN_WEBHOOK_ROUTE_PATH,
  GarminOAuthGrantExpiredError,
  GarminRateLimitError,
  applyMigrations,
  createApp,
  createAcquisitionAdapterRegistry,
  createDefaultAcquisitionAdapterRegistry,
  createDatabaseClient,
  createDrizzleCanonicalImportStore,
  createDrizzleGarminConnectorConsentStore,
  createDrizzleGarminOAuthConnectionStore,
  createDrizzleIntegrationStatusStore,
  createGarminBackfillJobHandler,
  createGarminOAuthTokenCipher,
  createGarminReconciliationDispatchHandler,
  createGarminReconciliationJobHandler,
  createGarminWebhookJobHandler,
  listGarminConnectorConsentDataClassAccess,
  mapGarminOfficialActivityPayloadsToCanonicalImport,
  parseGarminFitActivityFile,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;
const timezone = "Australia/Brisbane";
const startedAt = "2026-06-23T20:00:00.000Z";
const firstRecordAt = "2026-06-23T20:00:10.000Z";

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for Garmin webhook tests.");
}

test("Garmin webhook route enqueues a pg-boss ingestion job", async () => {
  const sends = [];
  const jobs = {
    async start() {},
    async stop() {},
    async ensureQueue() {},
    async schedule() {},
    async send(input) {
      sends.push(input);
      return "queued-garmin-job-1";
    },
    async work() {}
  };
  const app = createApp({
    garminWebhookConfig: { sharedSecret: "hook-secret" },
    garminWebhookJobQueue: jobs,
    logger: { info() {}, error() {} }
  });

  const unauthorized = await app.request(GARMIN_WEBHOOK_ROUTE_PATH, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      providerUserId: "garmin-user-1",
      eventId: "event-1",
      activityIds: ["activity-1"]
    })
  });
  assert.equal(unauthorized.status, 401);

  const response = await app.request(GARMIN_WEBHOOK_ROUTE_PATH, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-garmin-webhook-secret": "hook-secret"
    },
    body: JSON.stringify({
      providerUserId: "garmin-user-1",
      eventId: "event-1",
      activityIds: ["activity-1"]
    })
  });

  assert.equal(response.status, 202);
  const body = await response.json();
  assert.equal(body.accepted, true);
  assert.equal(body.jobId, "queued-garmin-job-1");
  assert.equal(body.idempotencyKey.startsWith("garmin-webhook:"), true);
  assert.deepEqual(sends, [
    {
      name: GARMIN_WEBHOOK_JOB_NAME,
      data: {
        providerUserId: "garmin-user-1",
        eventId: "event-1",
        activityIds: ["activity-1"],
        idempotencyKey: body.idempotencyKey
      },
      options: {
        singletonKey: body.idempotencyKey,
        singletonSeconds: 2_592_000,
        retryLimit: 3
      }
    }
  ]);
});

test("Garmin consent data-class route shows premium classes offered but locked", async () => {
  const app = createApp({
    garminOAuthStore: {
      createOAuthState() {
        throw new Error("not used");
      },
      readOAuthState() {
        throw new Error("not used");
      },
      async upsertConnection() {
        throw new Error("not used");
      },
      async findActiveConnectionForUser() {
        return {
          id: "connection-1",
          source: "garmin",
          credentialName: "Garmin official connector",
          providerUserId: "provider-user-1",
          scope: "activity",
          connected: true,
          connectedAt: "2026-06-01T00:00:00.000Z",
          revokedAt: null,
          updatedAt: "2026-06-26T09:30:00.000Z"
        };
      },
      async findActiveConnectionByProviderUserId() {
        throw new Error("not used");
      },
      async listActiveConnectorConnections() {
        return [];
      },
      async decryptRefreshTokenForConnectorJob() {
        throw new Error("not used");
      },
      async forgetRefreshToken() {
        return false;
      }
    },
    garminConsentStore: {
      async listEnabledDataClasses() {
        return ["activities", "sleepWellness", "bodyComposition"];
      }
    },
    garminEntitlementStore: {
      async hasActivePaidTier() {
        return false;
      }
    },
    logger: { info() {}, error() {} },
    syncStore: {
      async verifyBearerToken(token) {
        return token === "session-token" ? { userId: "user-1" } : null;
      },
      async explainUnauthorizedBearerToken() {
        return "The session bearer token is invalid or expired.";
      }
    }
  });

  const unauthorized = await app.request(GARMIN_CONSENT_DATA_CLASSES_ROUTE_PATH);
  assert.equal(unauthorized.status, 401);

  const response = await app.request(GARMIN_CONSENT_DATA_CLASSES_ROUTE_PATH, {
    headers: { authorization: "Bearer session-token" }
  });
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.connectionId, "connection-1");
  assert.deepEqual(
    body.dataClasses.map((item) => [
      item.dataClass,
      item.enabled,
      item.locked,
      item.lockReason
    ]),
    [
      ["activities", true, false, null],
      ["heartRate", false, false, null],
      ["gps", false, false, null],
      ["sleepWellness", false, true, "paid_tier_required"],
      ["bodyComposition", false, true, "paid_tier_required"]
    ]
  );
});

test("Acquisition adapter registry exposes Garmin and accepts a second vendor without downstream changes", () => {
  const registry = createDefaultAcquisitionAdapterRegistry();
  const seededRegistry = createAcquisitionAdapterRegistry([
    GARMIN_OFFICIAL_ACQUISITION_ADAPTER
  ]);

  const garmin = registry.get("garmin");
  assert.equal(seededRegistry.get("garmin").sourceKey, "garmin");
  assert.deepEqual(garmin, GARMIN_OFFICIAL_ACQUISITION_ADAPTER);
  assert.equal(garmin.sourceKey, "garmin");
  assert.equal(garmin.adapterKind, "integration");
  assert.deepEqual(garmin.consentDataClasses, [
    "activities",
    "heartRate",
    "gps",
    "sleepWellness",
    "bodyComposition"
  ]);
  assert.deepEqual(garmin.exerciseMappings.slice(0, 3), [
    {
      vendorActivityType: "strength_training",
      canonicalExerciseId:
        CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.strengthTraining
    },
    {
      vendorActivityType: "running",
      canonicalExerciseId: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.running
    },
    {
      vendorActivityType: "cycling",
      canonicalExerciseId: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.cycling
    }
  ]);

  registry.register({
    sourceKey: "stub-second-vendor",
    adapterKind: "integration",
    exerciseMappings: [
      {
        vendorActivityType: "functional_strength",
        canonicalExerciseId:
          CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.strengthTraining
      }
    ],
    consentDataClasses: ["activities", "heartRate", "sleepWellness"]
  });

  assert.deepEqual(
    registry.list().map((adapter) => adapter.sourceKey),
    ["garmin", "stub-second-vendor"]
  );
  assert.throws(
    () => registry.register(GARMIN_OFFICIAL_ACQUISITION_ADAPTER),
    /already registered/
  );
});

test("official Garmin FIT payload maps identically to the M15 sidecar parser", () => {
  const fitFile = garminStrengthFitFixture();
  const sidecarCanonical = parseGarminFitActivityFile(fitFile, { timezone });
  const officialCanonical = mapGarminOfficialActivityPayloadsToCanonicalImport(
    [
      {
        kind: "fit",
        fitFileBase64: fitFile.toString("base64"),
        timezone
      }
    ],
    { defaultTimezone: "UTC" }
  );

  assert.deepEqual(officialCanonical, sidecarCanonical);
});

test("Garmin hosted connector requests and imports only effective consented data classes", async () => {
  const requestedLists = [];
  const requestedFetches = [];
  const imports = [];
  const handler = createGarminBackfillJobHandler({
    canonicalImportStore: captureCanonicalImports(imports),
    garminOAuthClient: garminOAuthClientReturning("access-token"),
    garminOAuthStore: garminOAuthStoreWithRefreshToken("refresh-token"),
    garminConsentStore: {
      async listEnabledDataClasses() {
        return ["activities", "heartRate"];
      }
    },
    garminEntitlementStore: {
      async hasActivePaidTier() {
        return false;
      }
    },
    garminOfficialClient: {
      async listActivityIds(input) {
        requestedLists.push(input);
        return { activityIds: ["activity-1"] };
      },
      async fetchActivityPayloads(input) {
        requestedFetches.push(input);
        return [mixedCanonicalGarminPayload()];
      }
    },
    logger: { info() {}, warn() {}, error() {} }
  });

  await handler(garminWindowJob("garmin-consent-heart-rate"));

  assert.deepEqual(requestedLists.map((input) => input.dataClasses), [
    ["activities", "heartRate"]
  ]);
  assert.deepEqual(requestedFetches.map((input) => input.dataClasses), [
    ["activities", "heartRate"]
  ]);
  assert.equal(imports.length, 1);
  assert.deepEqual(imports[0].request.consentedDataClasses, [
    "activities",
    "heartRate"
  ]);
  assert.deepEqual(
    imports[0].request.activities[0].summaryMetrics.map(
      (metric) => metric.metricKey
    ),
    ["averageHeartRate"]
  );
  assert.deepEqual(
    imports[0].request.metricReadings.map((reading) => reading.metricKey),
    ["restingHeartRate"]
  );
  assert.deepEqual(
    imports[0].request.series.map((series) => series.type),
    ["heartRate", "cadence"]
  );
});

test("Garmin hosted connector treats GPS as a separate explicit opt-in", async () => {
  const imports = [];
  const requestedFetches = [];
  const handler = createGarminBackfillJobHandler({
    canonicalImportStore: captureCanonicalImports(imports),
    garminOAuthClient: garminOAuthClientReturning("access-token"),
    garminOAuthStore: garminOAuthStoreWithRefreshToken("refresh-token"),
    garminConsentStore: {
      async listEnabledDataClasses() {
        return ["activities", "heartRate", "gps"];
      }
    },
    garminEntitlementStore: {
      async hasActivePaidTier() {
        return false;
      }
    },
    garminOfficialClient: {
      async listActivityIds() {
        return { activityIds: ["activity-1"] };
      },
      async fetchActivityPayloads(input) {
        requestedFetches.push(input);
        return [mixedCanonicalGarminPayload()];
      }
    },
    logger: { info() {}, warn() {}, error() {} }
  });

  await handler(garminWindowJob("garmin-consent-gps"));

  assert.deepEqual(requestedFetches[0].dataClasses, [
    "activities",
    "heartRate",
    "gps"
  ]);
  assert.deepEqual(
    imports[0].request.series.map((series) => series.type),
    ["heartRate", "location", "cadence"]
  );
});

test("Garmin hosted connector offers premium classes locked without paid tier and excludes them until entitlement changes", async () => {
  let paidTier = false;
  const imports = [];
  const requestedFetches = [];
  const consentStore = {
    async listEnabledDataClasses() {
      return ["activities", "sleepWellness", "bodyComposition"];
    }
  };
  const entitlementStore = {
    async hasActivePaidTier() {
      return paidTier;
    }
  };
  const accessWithoutEntitlement =
    await listGarminConnectorConsentDataClassAccess({
      credentialId: "connection-1",
      entitlementStore,
      consentStore,
      userId: "user-1"
    });
  assert.deepEqual(
    accessWithoutEntitlement
      .filter(
        (item) =>
          item.dataClass === "sleepWellness" ||
          item.dataClass === "bodyComposition"
      )
      .map((item) => ({
        dataClass: item.dataClass,
        enabled: item.enabled,
        locked: item.locked,
        lockReason: item.lockReason
      })),
    [
      {
        dataClass: "sleepWellness",
        enabled: false,
        locked: true,
        lockReason: "paid_tier_required"
      },
      {
        dataClass: "bodyComposition",
        enabled: false,
        locked: true,
        lockReason: "paid_tier_required"
      }
    ]
  );
  const handler = createGarminBackfillJobHandler({
    canonicalImportStore: captureCanonicalImports(imports),
    garminOAuthClient: garminOAuthClientReturning("access-token"),
    garminOAuthStore: garminOAuthStoreWithRefreshToken("refresh-token"),
    garminConsentStore: consentStore,
    garminEntitlementStore: entitlementStore,
    garminOfficialClient: {
      async listActivityIds() {
        return { activityIds: ["activity-1"] };
      },
      async fetchActivityPayloads(input) {
        requestedFetches.push(input);
        return [mixedCanonicalGarminPayload()];
      }
    },
    logger: { info() {}, warn() {}, error() {} }
  });

  await handler(garminWindowJob("garmin-premium-locked"));
  paidTier = true;
  await handler(garminWindowJob("garmin-premium-unlocked"));

  assert.deepEqual(requestedFetches.map((input) => input.dataClasses), [
    ["activities"],
    ["activities", "sleepWellness", "bodyComposition"]
  ]);
  assert.deepEqual(
    imports[0].request.metricReadings.map((reading) => reading.metricKey),
    []
  );
  assert.deepEqual(
    imports[1].request.metricReadings.map((reading) => reading.metricKey),
    ["bodyWeight", "sleepDuration"]
  );
});

test(
  "Garmin webhook job mints a token, fetches FIT data, and imports one idempotent canonical batch",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `garmin-webhook-user-${randomUUID()}`;
    const refreshToken = `garmin-refresh-${randomUUID()}`;
    const accessToken = `garmin-access-${randomUUID()}`;
    const syncNudges = [];
    const tokenRefreshes = [];
    const fetches = [];
    const store = createDrizzleGarminOAuthConnectionStore({
      cipher: createGarminOAuthTokenCipher(randomBytes(32)),
      db: database.db
    });

    try {
      await seedUser(database, userId);
      const connection = await store.upsertConnection({
        accessTokenExpiresAt: null,
        providerUserId: "garmin-provider-user-1",
        refreshToken,
        scope: "activity heartrate",
        userId
      });
      await enableConnectionConsents(database, {
        userId,
        credentialId: connection.id,
        dataClasses: ["activities", "heartRate", "gps"]
      });

      const handler = createGarminWebhookJobHandler({
        canonicalImportStore: createDrizzleCanonicalImportStore(database.db),
        garminOAuthClient: {
          async exchangeCode() {
            throw new Error("webhook jobs must not exchange authorization codes");
          },
          async refreshAccessToken(input) {
            tokenRefreshes.push(input);
            return { accessToken, expiresInSeconds: 3600 };
          },
          async revokeRefreshToken() {
            return { revoked: false };
          }
        },
        garminOAuthStore: store,
        garminConsentStore: createDrizzleGarminConnectorConsentStore(database.db),
        garminOfficialClient: {
          async listActivityIds() {
            throw new Error("webhook jobs must not list historical activity ids");
          },
          async fetchActivityPayloads(input) {
            fetches.push(input);
            return [
              {
                kind: "fit",
                fitFileBase64: garminStrengthFitFixture().toString("base64"),
                timezone
              }
            ];
          }
        },
        logger: { info() {}, warn() {}, error() {} },
        syncNudgePublisher: {
          async enqueueSyncNudge(input) {
            syncNudges.push(input);
            return { enqueued: true, jobId: `nudge-${syncNudges.length}` };
          }
        }
      });
      const job = {
        id: "garmin-webhook-job-1",
        name: GARMIN_WEBHOOK_JOB_NAME,
        data: {
          providerUserId: "garmin-provider-user-1",
          eventId: "event-1",
          activityIds: ["activity-1"],
          idempotencyKey: `garmin-webhook-${randomUUID()}`
        }
      };

      const firstResult = await handler(job);
      assert.equal(firstResult?.accepted, true);
      assert.equal(firstResult?.duplicate, false);
      assert.equal(firstResult?.materializedWorkouts.length, 1);
      assert.equal(
        firstResult?.materializedWorkouts[0].exerciseId,
        CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.strengthTraining
      );
      assert.deepEqual(tokenRefreshes, [{ refreshToken }]);
      assert.deepEqual(fetches, [
        {
          accessToken,
          activityIds: ["activity-1"],
          dataClasses: ["activities", "heartRate", "gps"],
          providerUserId: "garmin-provider-user-1"
        }
      ]);

      const activityRows = await database.sql`
        select id, source, external_id, activity_type
        from external_activities
        where user_id = ${userId}
      `;
      assert.equal(activityRows.length, 1);
      assert.equal(activityRows[0].source, "garmin");
      assert.equal(activityRows[0].external_id, `fit:123456789:${startedAt}`);
      assert.equal(activityRows[0].activity_type, "strength_training");

      const setRows = await database.sql`
        select payload
        from logged_sets
        where user_id = ${userId}
        order by payload->>'position'
      `;
      assert.equal(setRows.length, 2);
      assert.equal(setRows[0].payload.source, "garmin");
      assert.equal(setRows[0].payload.values.load.entered, "100");
      assert.equal(setRows[0].payload.values.reps.entered, "5");

      const metricRows = await database.sql`
        select metric_id
        from metric_readings
        where user_id = ${userId}
      `;
      assert.equal(metricRows.length, 5);

      const seriesRows = await database.sql`
        select series_type, sample_count
        from monitoring_series
        where user_id = ${userId}
        order by series_type
      `;
      assert.deepEqual(
        seriesRows.map((row) => [row.series_type, row.sample_count]),
        [
          ["cadence", 2],
          ["heartRate", 2],
          ["location", 2]
        ]
      );

      const logRows = await database.sql`
        select batch_id, entity_table
        from activity_log
        where user_id = ${userId} and batch_id = ${job.data.idempotencyKey}
      `;
      assert.equal(logRows.length, 12);
      assert.equal(new Set(logRows.map((row) => row.batch_id)).size, 1);
      assert.equal(syncNudges.length, 1);
      assert.deepEqual(syncNudges[0], {
        userId,
        sourceDeviceId: `integration:${connection.id}`,
        reason: "integration_import"
      });

      const replayResult = await handler({
        ...job,
        id: "garmin-webhook-job-redelivery"
      });
      assert.equal(replayResult?.duplicate, true);
      const replayLogRows = await database.sql`
        select count(*)::int as count
        from activity_log
        where user_id = ${userId} and batch_id = ${job.data.idempotencyKey}
      `;
      assert.equal(replayLogRows[0].count, 12);
      assert.equal(syncNudges.length, 1);
    } finally {
      await database.close();
    }
  }
);

test(
  "Garmin backfill and reconciliation import missed activities through the same idempotent canonical path",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `garmin-backfill-user-${randomUUID()}`;
    const refreshToken = `garmin-refresh-${randomUUID()}`;
    const accessToken = `garmin-access-${randomUUID()}`;
    const tokenRefreshes = [];
    const listedWindows = [];
    const fetches = [];
    const statusReports = [];
    const store = createDrizzleGarminOAuthConnectionStore({
      cipher: createGarminOAuthTokenCipher(randomBytes(32)),
      db: database.db
    });
    const statusStore = createDrizzleIntegrationStatusStore(database.db);

    try {
      await seedUser(database, userId);
      const connection = await store.upsertConnection({
        accessTokenExpiresAt: null,
        providerUserId: "garmin-provider-user-backfill",
        refreshToken,
        scope: "activity heartrate",
        userId
      });
      await enableConnectionConsents(database, {
        userId,
        credentialId: connection.id,
        dataClasses: ["activities", "heartRate", "gps"]
      });
      const commonOptions = {
        canonicalImportStore: createDrizzleCanonicalImportStore(database.db),
        garminOAuthClient: {
          async exchangeCode() {
            throw new Error("connector jobs must not exchange authorization codes");
          },
          async refreshAccessToken(input) {
            tokenRefreshes.push(input);
            return { accessToken, expiresInSeconds: 3600 };
          },
          async revokeRefreshToken() {
            return { revoked: false };
          }
        },
        garminOAuthStore: store,
        garminConsentStore: createDrizzleGarminConnectorConsentStore(database.db),
        garminOfficialClient: {
          async listActivityIds(input) {
            listedWindows.push(input);
            if (input.windowStart === "2026-06-01T00:00:00.000Z") {
              return { activityIds: ["backfill-activity-1"] };
            }
            return { activityIds: ["reconciled-activity-2"] };
          },
          async fetchActivityPayloads(input) {
            fetches.push(input);
            const serial =
              input.activityIds[0] === "backfill-activity-1"
                ? 123456789
                : 987654321;
            const activityStartedAt =
              input.activityIds[0] === "backfill-activity-1"
                ? startedAt
                : "2026-06-24T20:00:00.000Z";
            return [
              {
                kind: "fit",
                fitFileBase64: garminStrengthFitFixture({
                  activityStartedAt,
                  serial
                }).toString("base64"),
                timezone
              }
            ];
          }
        },
        integrationStatusStore: {
          async recordIntegrationStatus(input) {
            statusReports.push(input);
            return statusStore.recordIntegrationStatus(input);
          },
          async listIntegrationStatuses(userIdForList) {
            return statusStore.listIntegrationStatuses(userIdForList);
          }
        },
        logger: { info() {}, warn() {}, error() {} }
      };
      const backfillHandler = createGarminBackfillJobHandler(commonOptions);
      const reconciliationHandler =
        createGarminReconciliationJobHandler(commonOptions);
      const backfillJob = {
        id: "garmin-backfill-job-1",
        name: GARMIN_BACKFILL_JOB_NAME,
        data: {
          connectionId: connection.id,
          providerUserId: "garmin-provider-user-backfill",
          userId,
          windowStart: "2026-06-01T00:00:00.000Z",
          windowEnd: "2026-07-01T00:00:00.000Z",
          idempotencyKey: `garmin-backfill-${randomUUID()}`
        }
      };

      const firstBackfillResult = await backfillHandler(backfillJob);
      assert.equal(firstBackfillResult?.accepted, true);
      assert.equal(firstBackfillResult?.duplicate, false);
      assert.equal(firstBackfillResult?.materializedWorkouts.length, 1);

      const replayBackfillResult = await backfillHandler({
        ...backfillJob,
        id: "garmin-backfill-job-replay"
      });
      assert.equal(replayBackfillResult?.duplicate, true);

      const reconciliationResult = await reconciliationHandler({
        id: "garmin-reconciliation-job-1",
        name: GARMIN_RECONCILIATION_JOB_NAME,
        data: {
          connectionId: connection.id,
          providerUserId: "garmin-provider-user-backfill",
          userId,
          windowStart: "2026-07-01T00:00:00.000Z",
          windowEnd: "2026-07-02T00:00:00.000Z",
          idempotencyKey: `garmin-reconciliation-${randomUUID()}`
        }
      });
      assert.equal(reconciliationResult?.accepted, true);
      assert.equal(reconciliationResult?.duplicate, false);

      const activityRows = await database.sql`
        select source, external_id, activity_type
        from external_activities
        where user_id = ${userId}
        order by external_id
      `;
      assert.deepEqual(
        activityRows.map((row) => row.external_id),
        [
          `fit:123456789:${startedAt}`,
          "fit:987654321:2026-06-24T20:00:00.000Z"
        ]
      );
      assert.equal(activityRows.every((row) => row.source === "garmin"), true);
      assert.equal(
        activityRows.every((row) => row.activity_type === "strength_training"),
        true
      );

      const backfillLogRows = await database.sql`
        select count(*)::int as count
        from activity_log
        where user_id = ${userId} and batch_id = ${backfillJob.data.idempotencyKey}
      `;
      assert.equal(backfillLogRows[0].count, 12);
      assert.deepEqual(
        listedWindows.map((window) => ({
          dataClasses: window.dataClasses,
          providerUserId: window.providerUserId,
          windowStart: window.windowStart,
          windowEnd: window.windowEnd
        })),
        [
          {
            dataClasses: ["activities", "heartRate", "gps"],
            providerUserId: "garmin-provider-user-backfill",
            windowStart: "2026-06-01T00:00:00.000Z",
            windowEnd: "2026-07-01T00:00:00.000Z"
          },
          {
            dataClasses: ["activities", "heartRate", "gps"],
            providerUserId: "garmin-provider-user-backfill",
            windowStart: "2026-06-01T00:00:00.000Z",
            windowEnd: "2026-07-01T00:00:00.000Z"
          },
          {
            dataClasses: ["activities", "heartRate", "gps"],
            providerUserId: "garmin-provider-user-backfill",
            windowStart: "2026-07-01T00:00:00.000Z",
            windowEnd: "2026-07-02T00:00:00.000Z"
          }
        ]
      );
      assert.deepEqual(fetches.map((fetch) => fetch.activityIds), [
        ["backfill-activity-1"],
        ["backfill-activity-1"],
        ["reconciled-activity-2"]
      ]);
      assert.deepEqual(fetches.map((fetch) => fetch.dataClasses), [
        ["activities", "heartRate", "gps"],
        ["activities", "heartRate", "gps"],
        ["activities", "heartRate", "gps"]
      ]);
      assert.deepEqual(tokenRefreshes, [
        { refreshToken },
        { refreshToken },
        { refreshToken }
      ]);
      assert.deepEqual(
        statusReports.map((input) => ({
          credentialId: input.credentialId,
          condition: input.report.condition,
          trigger: input.report.trigger
        })),
        [
          {
            credentialId: connection.id,
            condition: "ok",
            trigger: "backfill"
          },
          {
            credentialId: connection.id,
            condition: "ok",
            trigger: "backfill"
          },
          {
            credentialId: connection.id,
            condition: "ok",
            trigger: "scheduled"
          }
        ]
      );
    } finally {
      await database.close();
    }
  }
);

test("Garmin connector jobs back off via pg-boss and status on provider rate limits", async () => {
  const sentJobs = [];
  const statuses = [];
  const handler = createGarminBackfillJobHandler({
    canonicalImportStore: {
      async importCanonicalBatch() {
        throw new Error("rate-limited jobs must not touch core import");
      }
    },
    garminOAuthClient: {
      async exchangeCode() {
        throw new Error("connector jobs must not exchange authorization codes");
      },
      async refreshAccessToken() {
        return { accessToken: "access-token", expiresInSeconds: 3600 };
      },
      async revokeRefreshToken() {
        return { revoked: false };
      }
    },
    garminOAuthStore: {
      createOAuthState() {
        throw new Error("not used");
      },
      readOAuthState() {
        throw new Error("not used");
      },
      async upsertConnection() {
        throw new Error("not used");
      },
      async findActiveConnectionForUser() {
        throw new Error("not used");
      },
      async findActiveConnectionByProviderUserId() {
        throw new Error("not used");
      },
      async listActiveConnectorConnections() {
        return [];
      },
      async decryptRefreshTokenForConnectorJob() {
        return "refresh-token";
      },
      async forgetRefreshToken() {
        return false;
      }
    },
    garminOfficialClient: {
      async listActivityIds() {
        throw new GarminRateLimitError({ retryAfterSeconds: 120 });
      },
      async fetchActivityPayloads() {
        throw new Error("rate-limited jobs must not fetch activities");
      }
    },
    integrationStatusStore: {
      async recordIntegrationStatus(input) {
        statuses.push(input);
        return {
          id: "status-1",
          source: "garmin",
          credentialId: input.credentialId,
          credentialName: input.credentialName,
          condition: input.report.condition,
          recoveryAction: "backoff",
          lastSuccessfulAt: null,
          firstFailureAt: "2026-06-26T08:30:00.000Z",
          lastFailureAt: "2026-06-26T08:30:00.000Z",
          failureKind: input.report.failureKind ?? null,
          retryAfterSeconds: input.report.retryAfterSeconds ?? null,
          nextAttemptAt: "2026-06-26T08:32:00.000Z",
          updatedAt: "2026-06-26T08:30:00.000Z",
          manualFitImportFallback: true
        };
      },
      async listIntegrationStatuses() {
        return [];
      }
    },
    jobs: {
      async start() {},
      async stop() {},
      async ensureQueue() {},
      async schedule() {},
      async send(input) {
        sentJobs.push(input);
        return "retry-job-1";
      },
      async work() {}
    },
    logger: { info() {}, warn() {}, error() {} }
  });
  const job = {
    id: "rate-limited-backfill",
    name: GARMIN_BACKFILL_JOB_NAME,
    data: {
      connectionId: "connection-1",
      providerUserId: "provider-user-1",
      userId: "user-1",
      windowStart: "2026-06-01T00:00:00.000Z",
      windowEnd: "2026-07-01T00:00:00.000Z",
      idempotencyKey: "garmin-backfill:connection-1:rate-limit"
    }
  };

  const result = await handler(job);

  assert.equal(result, null);
  assert.deepEqual(statuses, [
    {
      credentialId: "connection-1",
      credentialName: "Garmin official connector",
      userId: "user-1",
      report: {
        source: "garmin",
        condition: "rate_limited",
        failureKind: "rate_limit",
        trigger: "backfill",
        retryAfterSeconds: 120
      }
    }
  ]);
  assert.deepEqual(sentJobs, [
    {
      name: GARMIN_BACKFILL_JOB_NAME,
      data: job.data,
      options: {
        singletonKey: "garmin-backfill:connection-1:rate-limit:retry",
        singletonSeconds: 120,
        retryLimit: 3
      }
    }
  ]);
});

test(
  "Garmin expired grants surface reauth then reauthorization replaces the token and resumes import",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `garmin-reauth-user-${randomUUID()}`;
    const expiredRefreshToken = `expired-refresh-${randomUUID()}`;
    const reauthorizedRefreshToken = `reauthorized-refresh-${randomUUID()}`;
    const accessToken = `garmin-access-${randomUUID()}`;
    const tokenRefreshes = [];
    const listedWindows = [];
    const fetches = [];
    const statusReports = [];
    const logs = [];
    const store = createDrizzleGarminOAuthConnectionStore({
      cipher: createGarminOAuthTokenCipher(randomBytes(32)),
      db: database.db
    });
    const statusStore = createDrizzleIntegrationStatusStore(database.db);

    try {
      await seedUser(database, userId);
      const connection = await store.upsertConnection({
        accessTokenExpiresAt: null,
        providerUserId: "garmin-provider-user-reauth",
        refreshToken: expiredRefreshToken,
        scope: "activity heartrate",
        userId
      });
      await enableConnectionConsents(database, {
        userId,
        credentialId: connection.id,
        dataClasses: ["activities", "heartRate", "gps"]
      });

      const handler = createGarminBackfillJobHandler({
        canonicalImportStore: createDrizzleCanonicalImportStore(database.db),
        garminOAuthClient: {
          async exchangeCode() {
            throw new Error("connector jobs must not exchange authorization codes");
          },
          async refreshAccessToken(input) {
            tokenRefreshes.push(input);
            if (input.refreshToken === expiredRefreshToken) {
              throw new GarminOAuthGrantExpiredError({
                providerError: "invalid_grant",
                status: 400
              });
            }
            assert.equal(input.refreshToken, reauthorizedRefreshToken);
            return { accessToken, expiresInSeconds: 3600 };
          },
          async revokeRefreshToken() {
            return { revoked: false };
          }
        },
        garminOAuthStore: store,
        garminConsentStore: createDrizzleGarminConnectorConsentStore(database.db),
        garminOfficialClient: {
          async listActivityIds(input) {
            listedWindows.push(input);
            return { activityIds: ["reauth-activity-1"] };
          },
          async fetchActivityPayloads(input) {
            fetches.push(input);
            return [
              {
                kind: "fit",
                fitFileBase64: garminStrengthFitFixture().toString("base64"),
                timezone
              }
            ];
          }
        },
        integrationStatusStore: {
          async recordIntegrationStatus(input) {
            statusReports.push(input);
            return statusStore.recordIntegrationStatus(input);
          },
          async listIntegrationStatuses(userIdForList) {
            return statusStore.listIntegrationStatuses(userIdForList);
          }
        },
        logger: captureLogger(logs)
      });
      const job = {
        id: "garmin-backfill-reauth-1",
        name: GARMIN_BACKFILL_JOB_NAME,
        data: {
          connectionId: connection.id,
          providerUserId: "garmin-provider-user-reauth",
          userId,
          windowStart: "2026-06-01T00:00:00.000Z",
          windowEnd: "2026-07-01T00:00:00.000Z",
          idempotencyKey: `garmin-backfill-reauth-${randomUUID()}`
        }
      };

      assert.equal(await handler(job), null);
      assert.deepEqual(
        statusReports.map((input) => input.report),
        [
          {
            source: "garmin",
            condition: "reauth_required",
            failureKind: "token_expired",
            trigger: "backfill"
          }
        ]
      );
      assert.deepEqual(tokenRefreshes, [{ refreshToken: expiredRefreshToken }]);
      assert.deepEqual(listedWindows, []);
      assert.deepEqual(fetches, []);
      assert.equal(JSON.stringify(logs).includes(expiredRefreshToken), false);

      const reauthorizedConnection = await store.upsertConnection({
        accessTokenExpiresAt: new Date("2026-06-26T12:00:00.000Z"),
        providerUserId: "garmin-provider-user-reauth",
        refreshToken: reauthorizedRefreshToken,
        scope: "activity heartrate",
        userId
      });
      assert.equal(reauthorizedConnection.id, connection.id);
      assert.equal(
        await store.decryptRefreshTokenForConnectorJob({
          connectionId: connection.id,
          userId
        }),
        reauthorizedRefreshToken
      );

      const resumedResult = await handler({
        ...job,
        id: "garmin-backfill-reauth-resumed"
      });
      assert.equal(resumedResult?.accepted, true);
      assert.equal(resumedResult?.duplicate, false);
      assert.deepEqual(tokenRefreshes, [
        { refreshToken: expiredRefreshToken },
        { refreshToken: reauthorizedRefreshToken }
      ]);
      assert.deepEqual(
        statusReports.map((input) => input.report.condition),
        ["reauth_required", "ok"]
      );
      assert.deepEqual(fetches.map((fetch) => fetch.activityIds), [
        ["reauth-activity-1"]
      ]);

      const statusRows = await statusStore.listIntegrationStatuses(userId);
      assert.equal(statusRows[0].condition, "ok");
      assert.equal(statusRows[0].recoveryAction, "none");
      assert.equal(statusRows[0].failureKind, null);
      const activityRows = await database.sql`
        select source, external_id
        from external_activities
        where user_id = ${userId}
      `;
      assert.equal(activityRows.length, 1);
      assert.equal(activityRows[0].source, "garmin");
    } finally {
      await database.close();
    }
  }
);

test(
  "Garmin disconnect forgets the token, stops future import, and keeps imported data",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `garmin-disconnect-user-${randomUUID()}`;
    const sessionToken = `session-${randomUUID()}`;
    const refreshToken = `garmin-refresh-${randomUUID()}`;
    const accessToken = `garmin-access-${randomUUID()}`;
    const tokenRefreshes = [];
    const fetches = [];
    const revocations = [];
    const store = createDrizzleGarminOAuthConnectionStore({
      cipher: createGarminOAuthTokenCipher(randomBytes(32)),
      db: database.db
    });

    try {
      await seedUser(database, userId);
      const connection = await store.upsertConnection({
        accessTokenExpiresAt: null,
        providerUserId: "garmin-provider-user-disconnect",
        refreshToken,
        scope: "activity heartrate",
        userId
      });
      await enableConnectionConsents(database, {
        userId,
        credentialId: connection.id,
        dataClasses: ["activities", "heartRate", "gps"]
      });
      const garminOAuthClient = {
        async exchangeCode() {
          throw new Error("not used");
        },
        async refreshAccessToken(input) {
          tokenRefreshes.push(input);
          return { accessToken, expiresInSeconds: 3600 };
        },
        async revokeRefreshToken(token) {
          revocations.push(token);
          return { revoked: true };
        }
      };
      const handler = createGarminWebhookJobHandler({
        canonicalImportStore: createDrizzleCanonicalImportStore(database.db),
        garminOAuthClient,
        garminOAuthStore: store,
        garminConsentStore: createDrizzleGarminConnectorConsentStore(database.db),
        garminOfficialClient: {
          async listActivityIds() {
            throw new Error("webhook jobs must not list historical activity ids");
          },
          async fetchActivityPayloads(input) {
            fetches.push(input);
            return [
              {
                kind: "fit",
                fitFileBase64: garminStrengthFitFixture().toString("base64"),
                timezone
              }
            ];
          }
        },
        logger: { info() {}, warn() {}, error() {} }
      });
      const job = {
        id: "garmin-webhook-disconnect-1",
        name: GARMIN_WEBHOOK_JOB_NAME,
        data: {
          providerUserId: "garmin-provider-user-disconnect",
          eventId: "event-1",
          activityIds: ["activity-1"],
          idempotencyKey: `garmin-webhook-disconnect-${randomUUID()}`
        }
      };

      const imported = await handler(job);
      assert.equal(imported?.accepted, true);
      assert.equal(imported?.duplicate, false);
      assert.deepEqual(await garminImportRowCounts(database, userId), {
        externalActivities: 1,
        materializedWorkouts: 1,
        loggedSets: 2,
        metricReadings: 5,
        monitoringSeries: 3,
        activityLinks: 1
      });

      const app = createApp({
        garminOAuthClient,
        garminOAuthStore: store,
        logger: { info() {}, error() {} },
        syncStore: {
          async verifyBearerToken(token) {
            return token === sessionToken ? { userId } : null;
          },
          async explainUnauthorizedBearerToken() {
            return "The session bearer token is invalid or expired.";
          }
        }
      });
      const disconnectResponse = await app.request(
        "/integrations/garmin/oauth/disconnect",
        {
          method: "POST",
          headers: { authorization: `Bearer ${sessionToken}` }
        }
      );
      assert.equal(disconnectResponse.status, 200);
      assert.deepEqual(revocations, [refreshToken]);
      assert.equal(
        await store.decryptRefreshTokenForConnectorJob({
          connectionId: connection.id,
          userId
        }),
        null
      );
      assert.deepEqual(await garminImportRowCounts(database, userId), {
        externalActivities: 1,
        materializedWorkouts: 1,
        loggedSets: 2,
        metricReadings: 5,
        monitoringSeries: 3,
        activityLinks: 1
      });

      const skipped = await handler({
        ...job,
        id: "garmin-webhook-after-disconnect",
        data: {
          ...job.data,
          eventId: "event-after-disconnect",
          idempotencyKey: `garmin-webhook-after-disconnect-${randomUUID()}`
        }
      });
      assert.equal(skipped, null);
      assert.deepEqual(tokenRefreshes, [{ refreshToken }]);
      assert.equal(fetches.length, 1);
      assert.deepEqual(await garminImportRowCounts(database, userId), {
        externalActivities: 1,
        materializedWorkouts: 1,
        loggedSets: 2,
        metricReadings: 5,
        monitoringSeries: 3,
        activityLinks: 1
      });
    } finally {
      await database.close();
    }
  }
);

test(
  "Garmin reconnect resumes idempotently without clobbering or resurrecting materialized Workouts",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `garmin-reconnect-user-${randomUUID()}`;
    const initialRefreshToken = `initial-refresh-${randomUUID()}`;
    const reconnectRefreshToken = `reconnect-refresh-${randomUUID()}`;
    const accessToken = `garmin-access-${randomUUID()}`;
    const store = createDrizzleGarminOAuthConnectionStore({
      cipher: createGarminOAuthTokenCipher(randomBytes(32)),
      db: database.db
    });

    try {
      await seedUser(database, userId);
      const connection = await store.upsertConnection({
        accessTokenExpiresAt: null,
        providerUserId: "garmin-provider-user-reconnect",
        refreshToken: initialRefreshToken,
        scope: "activity heartrate",
        userId
      });
      await enableConnectionConsents(database, {
        userId,
        credentialId: connection.id,
        dataClasses: ["activities", "heartRate", "gps"]
      });
      const handler = createGarminBackfillJobHandler({
        canonicalImportStore: createDrizzleCanonicalImportStore(database.db),
        garminOAuthClient: {
          async exchangeCode() {
            throw new Error("not used");
          },
          async refreshAccessToken() {
            return { accessToken, expiresInSeconds: 3600 };
          },
          async revokeRefreshToken() {
            return { revoked: true };
          }
        },
        garminOAuthStore: store,
        garminConsentStore: createDrizzleGarminConnectorConsentStore(database.db),
        garminOfficialClient: {
          async listActivityIds() {
            return { activityIds: ["reconnect-activity-1"] };
          },
          async fetchActivityPayloads() {
            return [
              {
                kind: "fit",
                fitFileBase64: garminStrengthFitFixture().toString("base64"),
                timezone
              }
            ];
          }
        },
        integrationStatusStore: createDrizzleIntegrationStatusStore(database.db),
        logger: { info() {}, warn() {}, error() {} }
      });

      const initialResult = await handler({
        id: "garmin-reconnect-initial",
        name: GARMIN_BACKFILL_JOB_NAME,
        data: {
          connectionId: connection.id,
          providerUserId: "garmin-provider-user-reconnect",
          userId,
          windowStart: "2026-06-01T00:00:00.000Z",
          windowEnd: "2026-07-01T00:00:00.000Z",
          idempotencyKey: `garmin-reconnect-initial-${randomUUID()}`
        }
      });
      assert.deepEqual(
        initialResult?.materializedWorkouts.map((workout) => workout.status),
        ["created"]
      );

      const editableRows = await database.sql`
        select id, payload
        from logged_sets
        where user_id = ${userId}
        order by payload->>'position'
        limit 1
      `;
      assert.equal(editableRows.length, 1);
      const editedPayload = {
        ...editableRows[0].payload,
        comment: "Edited after import."
      };
      await database.db
        .update(schema.loggedSets)
        .set({
          payload: editedPayload,
          updatedAt: new Date("2026-06-26T10:00:00.000Z")
        })
        .where(eq(schema.loggedSets.id, editableRows[0].id));
      await store.forgetRefreshToken({
        connectionId: connection.id,
        userId
      });
      const reconnected = await store.upsertConnection({
        accessTokenExpiresAt: null,
        providerUserId: "garmin-provider-user-reconnect",
        refreshToken: reconnectRefreshToken,
        scope: "activity heartrate",
        userId
      });
      assert.equal(reconnected.id, connection.id);

      const reconnectResult = await handler({
        id: "garmin-reconnect-refresh",
        name: GARMIN_BACKFILL_JOB_NAME,
        data: {
          connectionId: connection.id,
          providerUserId: "garmin-provider-user-reconnect",
          userId,
          windowStart: "2026-06-01T00:00:00.000Z",
          windowEnd: "2026-07-01T00:00:00.000Z",
          idempotencyKey: `garmin-reconnect-refresh-${randomUUID()}`
        }
      });
      assert.deepEqual(
        reconnectResult?.materializedWorkouts.map((workout) => workout.status),
        ["existing"]
      );
      assert.deepEqual(
        reconnectResult?.activityLinks.map((link) => link.status),
        ["existing"]
      );
      const editedAfterReconnect = await database.sql`
        select payload, deleted_at
        from logged_sets
        where id = ${editableRows[0].id}
      `;
      assert.equal(editedAfterReconnect[0].payload.comment, "Edited after import.");
      assert.equal(editedAfterReconnect[0].deleted_at, null);

      const tombstoneAt = "2026-06-26T10:05:00.000Z";
      await database.sql`
        update logged_sets
        set updated_at = ${tombstoneAt}, deleted_at = ${tombstoneAt}
        where user_id = ${userId}
      `;
      const tombstoneResult = await handler({
        id: "garmin-reconnect-tombstone",
        name: GARMIN_BACKFILL_JOB_NAME,
        data: {
          connectionId: connection.id,
          providerUserId: "garmin-provider-user-reconnect",
          userId,
          windowStart: "2026-06-01T00:00:00.000Z",
          windowEnd: "2026-07-01T00:00:00.000Z",
          idempotencyKey: `garmin-reconnect-tombstone-${randomUUID()}`
        }
      });
      assert.deepEqual(
        tombstoneResult?.materializedWorkouts.map((workout) => workout.status),
        ["tombstoned"]
      );
      const rowsAfterTombstone = await database.sql`
        select count(*)::int as count
        from logged_sets
        where user_id = ${userId}
      `;
      assert.equal(rowsAfterTombstone[0].count, 2);
    } finally {
      await database.close();
    }
  }
);

test("Garmin reconciliation dispatch starts from each Integration's last successful import", async () => {
  const sentJobs = [];
  const handler = createGarminReconciliationDispatchHandler({
    garminOAuthStore: {
      async listActiveConnectorConnections() {
        return [
          {
            id: "connection-1",
            source: "garmin",
            credentialName: "Garmin official connector",
            providerUserId: "provider-user-1",
            scope: "activity",
            connected: true,
            connectedAt: "2026-06-01T00:00:00.000Z",
            revokedAt: null,
            updatedAt: "2026-06-26T08:00:00.000Z",
            userId: "user-1"
          }
        ];
      }
    },
    integrationStatusStore: {
      async recordIntegrationStatus() {
        throw new Error("dispatch does not record status");
      },
      async listIntegrationStatuses() {
        return [
          {
            id: "status-1",
            source: "garmin",
            credentialId: "connection-1",
            credentialName: "Garmin official connector",
            condition: "ok",
            recoveryAction: "none",
            lastSuccessfulAt: "2026-06-25T12:30:00.000Z",
            firstFailureAt: null,
            lastFailureAt: null,
            failureKind: null,
            retryAfterSeconds: null,
            nextAttemptAt: null,
            updatedAt: "2026-06-25T12:30:00.000Z",
            manualFitImportFallback: true
          }
        ];
      }
    },
    jobs: {
      async start() {},
      async stop() {},
      async ensureQueue() {},
      async schedule() {},
      async send(input) {
        sentJobs.push(input);
        return "reconciliation-job-1";
      },
      async work() {}
    },
    logger: { info() {}, warn() {}, error() {} },
    now: () => new Date("2026-06-26T08:30:00.000Z")
  });

  await handler({
    id: "dispatch-1",
    name: "integrations.garmin.reconciliation.dispatch",
    data: { source: "garmin" }
  });

  assert.equal(sentJobs.length, 1);
  assert.equal(sentJobs[0].name, GARMIN_RECONCILIATION_JOB_NAME);
  assert.equal(sentJobs[0].data.windowStart, "2026-06-25T12:30:00.000Z");
  assert.equal(sentJobs[0].data.windowEnd, "2026-06-26T08:30:00.000Z");
  assert.equal(
    sentJobs[0].data.idempotencyKey,
    "garmin-reconciliation:connection-1:2026-06-25T12-30-00-000Z:2026-06-26T08-30-00-000Z"
  );
});

async function garminImportRowCounts(database, userId) {
  const rows = await database.sql`
    select
      (select count(*)::int from external_activities where user_id = ${userId}) as external_activities,
      (select count(distinct payload->>'workout_id')::int from logged_sets where user_id = ${userId}) as materialized_workouts,
      (select count(*)::int from logged_sets where user_id = ${userId}) as logged_sets,
      (select count(*)::int from metric_readings where user_id = ${userId}) as metric_readings,
      (select count(*)::int from monitoring_series where user_id = ${userId}) as monitoring_series,
      (select count(*)::int from activity_links where user_id = ${userId}) as activity_links
  `;
  return {
    externalActivities: rows[0].external_activities,
    materializedWorkouts: rows[0].materialized_workouts,
    loggedSets: rows[0].logged_sets,
    metricReadings: rows[0].metric_readings,
    monitoringSeries: rows[0].monitoring_series,
    activityLinks: rows[0].activity_links
  };
}

function captureLogger(logs) {
  return {
    info(payload, message) {
      logs.push({ level: "info", payload, message });
    },
    warn(payload, message) {
      logs.push({ level: "warn", payload, message });
    },
    error(payload, message) {
      logs.push({ level: "error", payload, message });
    }
  };
}

function captureCanonicalImports(imports) {
  return {
    async importCanonicalBatch(input) {
      imports.push(input);
      return {
        accepted: true,
        duplicate: false,
        idempotencyKey: input.idempotencyKey,
        batchId: input.batchId,
        serverClock: "2026-06-26T09:30:00.000Z",
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
  };
}

function garminOAuthClientReturning(accessToken) {
  return {
    async exchangeCode() {
      throw new Error("connector jobs must not exchange authorization codes");
    },
    async refreshAccessToken() {
      return { accessToken, expiresInSeconds: 3600 };
    },
    async revokeRefreshToken() {
      return { revoked: false };
    }
  };
}

function garminOAuthStoreWithRefreshToken(refreshToken) {
  return {
    createOAuthState() {
      throw new Error("not used");
    },
    readOAuthState() {
      throw new Error("not used");
    },
    async upsertConnection() {
      throw new Error("not used");
    },
    async findActiveConnectionForUser() {
      throw new Error("not used");
    },
    async findActiveConnectionByProviderUserId() {
      throw new Error("not used");
    },
    async listActiveConnectorConnections() {
      return [];
    },
    async decryptRefreshTokenForConnectorJob() {
      return refreshToken;
    },
    async forgetRefreshToken() {
      return false;
    }
  };
}

function garminWindowJob(idempotencyKey) {
  return {
    id: `${idempotencyKey}-job`,
    name: GARMIN_BACKFILL_JOB_NAME,
    data: {
      connectionId: "connection-1",
      providerUserId: "provider-user-1",
      userId: "user-1",
      windowStart: "2026-06-01T00:00:00.000Z",
      windowEnd: "2026-07-01T00:00:00.000Z",
      idempotencyKey
    }
  };
}

function mixedCanonicalGarminPayload() {
  return {
    kind: "canonical",
    activities: [
      {
        source: "garmin",
        externalId: "activity-1",
        activityType: "running",
        startedAt,
        endedAt: "2026-06-23T21:00:00.000Z",
        timezone,
        summary: {},
        summaryMetrics: [
          canonicalMetric("averageHeartRate", "activity-1:average-hr"),
          canonicalMetric("bodyWeight", "activity-1:body-weight"),
          canonicalMetric("sleepDuration", "activity-1:sleep-duration")
        ],
        sets: []
      }
    ],
    metricReadings: [
      canonicalMetric("restingHeartRate", "reading-resting-hr"),
      canonicalMetric("bodyWeight", "reading-body-weight"),
      canonicalMetric("sleepDuration", "reading-sleep-duration")
    ],
    series: [
      canonicalSeries("heartRate"),
      canonicalSeries("location"),
      canonicalSeries("cadence")
    ]
  };
}

function canonicalMetric(metricKey, externalId) {
  return {
    source: "garmin",
    externalId,
    metricKey,
    value: { value: 1, unit: metricKey.toLowerCase().includes("heart") ? "beatsPerMinute" : "count" },
    at: {
      kind: "instant",
      at: startedAt,
      timezone
    }
  };
}

function canonicalSeries(type) {
  return {
    source: "garmin",
    externalId: `series-${type}`,
    type,
    baseTime: startedAt,
    timezone,
    anchor: {
      kind: "timeWindow",
      startedAt,
      endedAt: "2026-06-23T21:00:00.000Z",
      timezone
    },
    samples: [
      {
        offsetSeconds: 0,
        value:
          type === "location"
            ? {
                latitude: { value: -27.4698, unit: "degree" },
                longitude: { value: 153.0251, unit: "degree" }
              }
            : { value: 1, unit: type === "heartRate" ? "beatsPerMinute" : "count" }
      }
    ]
  };
}

async function seedUser(database, userId) {
  await database.db.insert(schema.user).values({
    id: userId,
    name: "Garmin Webhook Test User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
}

async function enableConnectionConsents(
  database,
  { userId, credentialId, dataClasses }
) {
  const now = new Date("2026-06-26T08:30:00.000Z");
  await database.db.insert(schema.integrationDataClassConsents).values(
    dataClasses.map((dataClass) => ({
      id: randomUUID(),
      userId,
      deviceId: "integration:garmin-oauth",
      credentialId,
      dataClass,
      enabled: true,
      updatedAt: now,
      deletedAt: null,
      receivedAt: now
    }))
  );
}

function garminStrengthFitFixture({
  activityStartedAt = startedAt,
  serial = 123456789
} = {}) {
  const builder = new FitBuilder();
  builder.define(0, 0, [
    [3, 4, BASE.uint32],
    [4, 4, BASE.uint32]
  ]);
  builder.message(0, [
    uint32(serial),
    dateTime("2026-06-23T19:59:00.000Z")
  ]);
  builder.define(1, 18, [
    [2, 4, BASE.uint32],
    [5, 1, BASE.enum],
    [6, 1, BASE.enum],
    [7, 4, BASE.uint32],
    [8, 4, BASE.uint32],
    [9, 4, BASE.uint32],
    [11, 2, BASE.uint16],
    [16, 1, BASE.uint8],
    [17, 1, BASE.uint8],
    [18, 1, BASE.uint8],
    [19, 1, BASE.uint8]
  ]);
  builder.message(1, [
    dateTime(activityStartedAt),
    uint8(10),
    uint8(20),
    uint32(2700_000),
    uint32(2700_000),
    uint32(0),
    uint16(410),
    uint8(132),
    uint8(166),
    uint8(84),
    uint8(102)
  ]);
  builder.define(2, 20, [
    [253, 4, BASE.uint32],
    [0, 4, BASE.sint32],
    [1, 4, BASE.sint32],
    [3, 1, BASE.uint8],
    [4, 1, BASE.uint8]
  ]);
  builder.message(2, [
    dateTime(firstRecordAt),
    semicircles(-27.4698),
    semicircles(153.0251),
    uint8(130),
    uint8(82)
  ]);
  builder.message(2, [
    dateTime("2026-06-23T20:00:20.000Z"),
    semicircles(-27.47),
    semicircles(153.0255),
    uint8(136),
    uint8(86)
  ]);
  builder.define(3, 225, [
    [0, 4, BASE.uint32],
    [2, 4, BASE.uint32],
    [3, 2, BASE.uint16],
    [4, 2, BASE.uint16]
  ]);
  builder.message(3, [
    uint32(60_000),
    dateTime("2026-06-23T20:10:00.000Z"),
    uint16(5),
    uint16(1600)
  ]);
  builder.message(3, [
    uint32(60_000),
    dateTime("2026-06-23T20:15:00.000Z"),
    uint16(3),
    uint16(5616)
  ]);
  builder.message(3, [
    uint32(60_000),
    dateTime("2026-06-23T20:20:00.000Z"),
    uint16(1),
    uint16(16016)
  ]);

  return builder.build();
}

const BASE = {
  enum: 0x00,
  uint8: 0x02,
  sint32: 0x85,
  uint16: 0x84,
  uint32: 0x86
};

class FitBuilder {
  #records = [];

  define(localMessageType, globalMessageNumber, fields) {
    const bytes = [
      0x40 | localMessageType,
      0,
      0,
      globalMessageNumber & 0xff,
      (globalMessageNumber >> 8) & 0xff,
      fields.length
    ];
    for (const [number, size, baseType] of fields) {
      bytes.push(number, size, baseType);
    }
    this.#records.push(Buffer.from(bytes));
  }

  message(localMessageType, fieldValues) {
    this.#records.push(Buffer.concat([Buffer.from([localMessageType]), ...fieldValues]));
  }

  build() {
    const data = Buffer.concat(this.#records);
    const header = Buffer.alloc(14);
    header.writeUInt8(14, 0);
    header.writeUInt8(0x10, 1);
    header.writeUInt16LE(0, 2);
    header.writeUInt32LE(data.length, 4);
    header.write(".FIT", 8, "ascii");
    return Buffer.concat([header, data, Buffer.alloc(2)]);
  }
}

function uint8(value) {
  return Buffer.from([value]);
}

function uint16(value) {
  const buffer = Buffer.alloc(2);
  buffer.writeUInt16LE(value);
  return buffer;
}

function uint32(value) {
  const buffer = Buffer.alloc(4);
  buffer.writeUInt32LE(value);
  return buffer;
}

function int32(value) {
  const buffer = Buffer.alloc(4);
  buffer.writeInt32LE(value);
  return buffer;
}

function dateTime(value) {
  return uint32(Math.round((Date.parse(value) - Date.UTC(1989, 11, 31)) / 1000));
}

function semicircles(degrees) {
  return int32(Math.round((degrees * 2 ** 31) / 180));
}
