import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  applyMigrations,
  buildPlatformCatalogExercises,
  createApp,
  createDatabaseClient,
  createDrizzleAgentCatalogStore,
  createDrizzleAgentProgressReadStore,
  createDrizzleAgentReadStore,
  createDrizzleAgentSettingsStore,
  createDrizzleRateLimitBackend,
  createInMemoryAgentCatalogStore,
  encodeCanonicalSeriesBlob,
  schema
} from "../src/index.ts";
import { PLATFORM_EXERCISE_SEED_REDIRECTS } from "../src/data/platform-exercise-seed.generated.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

test(
  "agent analytics read computes records, bounded series, and period stats",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-read-analytics-user-${randomUUID()}`;
    const setIds = {
      squatFive: randomUUID(),
      squatTriple: randomUUID(),
      squatEight: randomUUID(),
      bench: randomUUID()
    };
    const app = createAgentReadApp({
      agentReadStore: createDrizzleAgentReadStore(database.db),
      userId
    });

    try {
      await seedUser(database, userId);
      await seedLoggedSet(database, {
        userId,
        id: setIds.squatFive,
        exerciseId: "user-back-squat",
        exerciseName: "Back Squat",
        performedAt: "2026-06-01T10:00:00.000Z",
        position: 0,
        values: {
          load: { entered: "100", unit: "kilogram" },
          reps: { entered: "5", unit: "repetition" }
        }
      });
      await seedLoggedSet(database, {
        userId,
        id: setIds.squatTriple,
        exerciseId: "user-back-squat",
        exerciseName: "Back Squat",
        performedAt: "2026-06-08T10:00:00.000Z",
        position: 1,
        values: {
          load: { entered: "120", unit: "kilogram" },
          reps: { entered: "3", unit: "repetition" }
        }
      });
      await seedLoggedSet(database, {
        userId,
        id: setIds.squatEight,
        exerciseId: "user-back-squat",
        exerciseName: "Back Squat",
        performedAt: "2026-06-15T10:00:00.000Z",
        position: 2,
        values: {
          load: { entered: "110", unit: "kilogram" },
          reps: { entered: "8", unit: "repetition" }
        }
      });
      await seedLoggedSet(database, {
        userId,
        id: setIds.bench,
        exerciseId: "platform-bench-press",
        exerciseName: "Bench Press",
        performedAt: "2026-06-15T11:00:00.000Z",
        position: 0,
        values: {
          load: { entered: "80", unit: "kilogram" },
          reps: { entered: "6", unit: "repetition" }
        }
      });

      const response = await getAgent(
        app,
        "/agent/analytics/exercises/user-back-squat?maxPoints=2"
      );

      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.exercise.id, "user-back-squat");
      assert.equal(body.totalSetCount, 3);
      assert.equal(body.seriesPointLimit, 2);
      assert.equal(body.headlineRecord.setId, setIds.squatTriple);
      assert.equal(body.headlineRecord.profile, "repMax");
      assert.deepEqual(
        body.recordCatalog.repMaxRecords.map((record) => record.setId),
        [setIds.squatTriple, setIds.squatEight]
      );
      assert.equal(body.recordCatalog.maxLoad.setId, setIds.squatTriple);
      assert.deepEqual(
        body.estimatedOneRepMax.points.map((point) => point.setId),
        [setIds.squatTriple, setIds.squatEight]
      );
      assert.equal(body.volume.points.length, 2);
      assert.equal(body.maxLoadSeries.total, 120);
      assert.equal(body.volume.total, 1740);
      assert.equal(body.periodStats.setCount, 3);
      assert.equal(body.periodStats.totalReps, 16);
      assert.equal(body.periodStats.totalVolumeKilograms, 1740);
      assert.ok(
        Math.abs(body.periodStats.maxEstimatedOneRepMaxKilograms - 136.551724) <
          0.000001
      );
    } finally {
      await database.close();
    }
  }
);

test(
  "agent history read filters by exercise, category, thresholds, and cursor",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-read-history-user-${randomUUID()}`;
    const setIds = {
      squatFive: randomUUID(),
      squatTriple: randomUUID(),
      squatEight: randomUUID(),
      bench: randomUUID()
    };
    const app = createAgentReadApp({
      agentReadStore: createDrizzleAgentReadStore(database.db),
      userId
    });

    try {
      await seedUser(database, userId);
      await seedLoggedSet(database, {
        userId,
        id: setIds.squatFive,
        exerciseId: "user-back-squat",
        exerciseName: "Back Squat",
        performedAt: "2026-06-01T10:00:00.000Z",
        position: 0,
        values: {
          load: { entered: "100", unit: "kilogram" },
          reps: { entered: "5", unit: "repetition" }
        }
      });
      await seedLoggedSet(database, {
        userId,
        id: setIds.squatTriple,
        exerciseId: "user-back-squat",
        exerciseName: "Back Squat",
        performedAt: "2026-06-08T10:00:00.000Z",
        position: 1,
        values: {
          load: { entered: "120", unit: "kilogram" },
          reps: { entered: "3", unit: "repetition" }
        }
      });
      await seedLoggedSet(database, {
        userId,
        id: setIds.squatEight,
        exerciseId: "user-back-squat",
        exerciseName: "Back Squat",
        performedAt: "2026-06-15T10:00:00.000Z",
        position: 2,
        values: {
          load: { entered: "110", unit: "kilogram" },
          reps: { entered: "8", unit: "repetition" }
        }
      });
      await seedLoggedSet(database, {
        userId,
        id: setIds.bench,
        exerciseId: "platform-bench-press",
        exerciseName: "Bench Press",
        performedAt: "2026-06-15T11:00:00.000Z",
        position: 0,
        values: {
          load: { entered: "80", unit: "kilogram" },
          reps: { entered: "6", unit: "repetition" }
        }
      });

      const defaultPage = await getAgent(app, "/agent/history/sets");
      assert.equal(defaultPage.status, 200);
      const defaultBody = await defaultPage.json();
      assert.equal(defaultBody.limit, 50);
      assert.equal(defaultBody.totalMatched, 4);

      const firstPage = await getAgent(
        app,
        "/agent/history/sets?exerciseId=user-back-squat&category=Strength&from=2026-06-05T00%3A00%3A00.000Z&to=2026-06-20T00%3A00%3A00.000Z&minLoadKilograms=105&limit=1"
      );

      assert.equal(firstPage.status, 200);
      const firstBody = await firstPage.json();
      assert.equal(firstBody.totalMatched, 2);
      assert.equal(firstBody.limit, 1);
      assert.deepEqual(
        firstBody.sets.map((set) => set.id),
        [setIds.squatEight]
      );
      assert.equal(firstBody.nextCursor, setIds.squatEight);
      assert.equal(firstBody.sets[0].category.name, "Strength");

      const secondPage = await getAgent(
        app,
        `/agent/history/sets?exerciseId=user-back-squat&category=Strength&from=2026-06-05T00%3A00%3A00.000Z&to=2026-06-20T00%3A00%3A00.000Z&minLoadKilograms=105&limit=1&cursor=${setIds.squatEight}`
      );

      assert.equal(secondPage.status, 200);
      const secondBody = await secondPage.json();
      assert.equal(secondBody.totalMatched, 2);
      assert.deepEqual(
        secondBody.sets.map((set) => set.id),
        [setIds.squatTriple]
      );
      assert.equal(secondBody.nextCursor, null);
    } finally {
      await database.close();
    }
  }
);

// D9 (docs/designs/progress-overview.md): progressSeries is read through its
// own store method over the whole history, not the request's from/to window or
// the 200-Set page, and is null when the progress store is not configured.
test(
  "agent analytics progressSeries covers the whole history and is null without the progress store",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-read-progress-user-${randomUUID()}`;
    const workoutCount = 210;
    const workoutId = (index) => `${userId}-w-${index}`;
    const localDate = (index) =>
      new Date(Date.UTC(2026, 0, 1) + index * 86_400_000).toISOString().slice(0, 10);

    try {
      await seedUser(database, userId);
      const at = new Date("2026-08-01T00:00:00.000Z");
      const row = (id, payload) => ({
        id,
        userId,
        deviceId: "device-agent-read-test",
        updatedAt: at,
        deletedAt: null,
        receivedAt: at,
        payload: { id, ...payload, updated_at: at.toISOString(), deleted_at: null }
      });
      const indexes = Array.from({ length: workoutCount }, (_, index) => index);
      await database.db.insert(schema.workoutSessions).values(
        indexes.map((index) =>
          row(workoutId(index), {
            local_date: localDate(index),
            started_at: `${localDate(index)}T06:00:00.000Z`,
            ended_at: `${localDate(index)}T07:00:00.000Z`
          })
        )
      );
      // One five-rep Set a day, a kilogram heavier each day but the last.
      await database.db.insert(schema.loggedSets).values(
        indexes.map((index) =>
          row(`${workoutId(index)}-set`, {
            workout_id: workoutId(index),
            performed_at: `${localDate(index)}T06:00:00.000Z`,
            exercise_id: "user-back-squat",
            position: 0,
            is_completed: true,
            values: {
              load: {
                entered: String(index === workoutCount - 1 ? 50 : 60 + index),
                unit: "kilogram"
              },
              reps: { entered: "5", unit: "repetition" }
            }
          })
        )
      );
      const catalogStore = createInMemoryAgentCatalogStore(catalogFixtures(userId));
      const path = `/agent/analytics/exercises/user-back-squat?from=${localDate(200)}T00:00:00.000Z`;

      const withProgress = createApp({
        logger: { info() {}, error() {} },
        agentApiKeyStore: createAgentKeyStore(userId, {}, "agent-read-key-1"),
        agentCatalogStore: catalogStore,
        agentReadStore: createDrizzleAgentReadStore(database.db),
        agentProgressReadStore: createDrizzleAgentProgressReadStore({
          db: database.db,
          settingsStore: createDrizzleAgentSettingsStore(database.db),
          catalogStore
        })
      });
      const response = await getAgent(withProgress, path);
      assert.equal(response.status, 200);
      const body = await response.json();
      // The request's window holds the last ten Sets; the series holds all.
      assert.equal(body.totalSetCount, 10);
      const series = body.progressSeries;
      assert.equal(series.exerciseId, "user-back-squat");
      assert.equal(series.measure, "estimatedOneRepMax");
      assert.equal(series.betterIs, "higher");
      assert.equal(series.points.length, workoutCount);
      assert.deepEqual(series.points[0], {
        workoutId: workoutId(0),
        localDate: localDate(0),
        startedAt: `${localDate(0)}T06:00:00.000Z`,
        setId: `${workoutId(0)}-set`,
        value: 67.5,
        unit: "kilogram",
        isNewBest: false
      });
      assert.ok(series.points.slice(1, -1).every((point) => point.isNewBest));
      assert.equal(series.points.at(-1).isNewBest, false);

      const withoutProgress = createAgentReadApp({
        agentReadStore: createDrizzleAgentReadStore(database.db),
        userId
      });
      const without = await getAgent(withoutProgress, path);
      assert.equal(without.status, 200);
      assert.equal((await without.json()).progressSeries, null);
    } finally {
      await database.close();
    }
  }
);

test(
  "agent read surface isolates analytics and history by authenticated account",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const otherUserId = `agent-read-other-user-${randomUUID()}`;
    const userId = `agent-read-isolated-user-${randomUUID()}`;
    const otherSetId = randomUUID();
    const ownSetId = randomUUID();
    const app = createAgentReadApp({
      agentReadStore: createDrizzleAgentReadStore(database.db),
      userId
    });

    try {
      await seedUser(database, otherUserId);
      await seedUser(database, userId);
      await seedLoggedSet(database, {
        userId: otherUserId,
        id: otherSetId,
        exerciseId: "user-back-squat",
        exerciseName: "Back Squat",
        performedAt: "2026-06-01T10:00:00.000Z",
        position: 0,
        values: {
          load: { entered: "200", unit: "kilogram" },
          reps: { entered: "5", unit: "repetition" }
        }
      });
      await seedLoggedSet(database, {
        userId,
        id: ownSetId,
        exerciseId: "user-back-squat",
        exerciseName: "Back Squat",
        performedAt: "2026-06-08T10:00:00.000Z",
        position: 0,
        values: {
          load: { entered: "100", unit: "kilogram" },
          reps: { entered: "5", unit: "repetition" }
        }
      });

      const analyticsResponse = await getAgent(
        app,
        "/agent/analytics/exercises/user-back-squat"
      );
      assert.equal(analyticsResponse.status, 200);
      const analyticsBody = await analyticsResponse.json();
      assert.equal(analyticsBody.totalSetCount, 1);
      assert.equal(analyticsBody.headlineRecord.setId, ownSetId);
      assert.equal(analyticsBody.recordCatalog.maxLoad.setId, ownSetId);
      assert.deepEqual(
        analyticsBody.volume.points.map((point) => point.setId),
        [ownSetId]
      );
      assert.equal(
        analyticsBody.recordCatalog.repMaxRecords.some(
          (record) => record.setId === otherSetId
        ),
        false
      );

      const historyResponse = await getAgent(
        app,
        "/agent/history/sets?exerciseId=user-back-squat"
      );
      assert.equal(historyResponse.status, 200);
      const historyBody = await historyResponse.json();
      assert.equal(historyBody.totalMatched, 1);
      assert.deepEqual(
        historyBody.sets.map((set) => set.id),
        [ownSetId]
      );
    } finally {
      await database.close();
    }
  }
);

test(
  "agent monitoring read returns derived summaries without exposing raw GPS payloads",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-read-monitoring-user-${randomUUID()}`;
    const activityId = randomUUID();
    const averageHeartRateMetricId = randomUUID();
    const logs = [];
    const app = createAgentReadApp({
      agentKeyId: "agent-read-monitoring-key",
      agentReadStore: createDrizzleAgentReadStore(database.db),
      logger: captureLogger(logs),
      userId
    });

    try {
      await seedUser(database, userId);
      await seedExternalActivity(database, {
        userId,
        id: activityId,
        externalId: "garmin-ride-aggregate",
        startedAt: "2026-06-20T10:00:00.000Z",
        endedAt: "2026-06-20T10:05:00.000Z"
      });
      await seedMetric(database, {
        userId,
        id: averageHeartRateMetricId,
        name: "averageHeartRate",
        unit: "beatsPerMinute"
      });
      await seedMetricReading(database, {
        userId,
        id: randomUUID(),
        metricId: averageHeartRateMetricId,
        externalActivityId: activityId,
        externalId: "garmin-ride-aggregate-average-heart-rate",
        value: { value: 149, unit: "beatsPerMinute" },
        scalarValue: 149,
        scalarEntered: "149",
        windowStartedAt: "2026-06-20T10:00:00.000Z",
        windowEndedAt: "2026-06-20T10:05:00.000Z"
      });
      await seedMonitoringSeries(database, {
        userId,
        id: randomUUID(),
        externalActivityId: activityId,
        series: heartRateSeries({
          externalId: "garmin-ride-aggregate-heart-rate",
          activityExternalId: "garmin-ride-aggregate",
          samples: [
            { offsetSeconds: 0, value: { value: 110, unit: "beatsPerMinute" } },
            { offsetSeconds: 60, value: { value: 130, unit: "beatsPerMinute" } },
            { offsetSeconds: 120, value: { value: 150, unit: "beatsPerMinute" } },
            { offsetSeconds: 180, value: { value: 170, unit: "beatsPerMinute" } },
            { offsetSeconds: 240, value: { value: 185, unit: "beatsPerMinute" } }
          ]
        })
      });
      await seedMonitoringSeries(database, {
        userId,
        id: randomUUID(),
        externalActivityId: activityId,
        series: locationSeries({
          externalId: "garmin-ride-aggregate-location",
          activityExternalId: "garmin-ride-aggregate",
          samples: [
            locationSample(0, -27.4698, 153.0251),
            locationSample(60, -27.4698, 153.0261),
            locationSample(120, -27.4688, 153.0261)
          ]
        })
      });

      const response = await getAgent(
        app,
        `/agent/monitoring/activities/${activityId}`
      );

      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.externalActivity.id, activityId);
      assert.equal(body.externalActivity.activityType, "cycling");
      assert.deepEqual(
        body.summaryReadings.map((reading) => [
          reading.metricKey,
          reading.scalarValue,
          reading.unit
        ]),
        [["averageHeartRate", 149, "beatsPerMinute"]]
      );
      assert.deepEqual(
        body.seriesSummaries.map((series) => [
          series.seriesType,
          series.sampleCount
        ]),
        [
          ["heartRate", 5],
          ["location", 3]
        ]
      );
      assert.equal(body.heartRate.sampleCount, 5);
      assert.equal(body.heartRate.averageBpm, 149);
      assert.deepEqual(body.heartRate.zoneSeconds, {
        below120: 60,
        bpm120To139: 60,
        bpm140To159: 60,
        bpm160To179: 60,
        bpm180Plus: 60
      });
      assert.equal(body.route.sampleCount, 3);
      assert.equal(body.route.seriesCount, 1);
      assert.ok(body.route.distanceKilometers > 0);
      assert.ok(body.route.averagePaceSecondsPerKilometer > 0);

      const serialized = JSON.stringify(body);
      for (const forbidden of [
        "samples",
        "blob",
        "blobBase64",
        "blobPath",
        "encoding",
        "compression",
        "sha256",
        "-27.4698",
        "153.0251"
      ]) {
        assert.equal(
          serialized.includes(forbidden),
          false,
          `agent monitoring response leaked ${forbidden}`
        );
      }

      const auditRows = await database.sql`
        select actor, entity_table, entity_id, after_image
        from activity_log
        where user_id = ${userId}
          and entity_table = 'agent_monitoring_reads'
      `;
      assert.equal(auditRows.length, 1);
      assert.equal(auditRows[0].actor, "agent");
      assert.equal(auditRows[0].entity_id, activityId);
      assert.deepEqual(auditRows[0].after_image, {
        externalActivityId: activityId,
        keyId: "agent-read-monitoring-key",
        routeSummaryReturned: true,
        heartRateSummaryReturned: true,
        summaryReadingCount: 1,
        seriesTypes: ["heartRate", "location"]
      });

      const logText = JSON.stringify([...logs, auditRows[0].after_image]);
      for (const forbidden of ["samples", "blob", "-27.4698", "153.0251"]) {
        assert.equal(
          logText.includes(forbidden),
          false,
          `logs leaked ${forbidden}`
        );
      }
    } finally {
      await database.close();
    }
  }
);

test(
  "agent monitoring read returns no route summary when GPS was never imported",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-read-monitoring-no-gps-user-${randomUUID()}`;
    const activityId = randomUUID();
    const app = createAgentReadApp({
      agentReadStore: createDrizzleAgentReadStore(database.db),
      userId
    });

    try {
      await seedUser(database, userId);
      await seedExternalActivity(database, {
        userId,
        id: activityId,
        externalId: "garmin-run-no-gps",
        startedAt: "2026-06-21T10:00:00.000Z",
        endedAt: "2026-06-21T10:02:00.000Z"
      });
      await seedMonitoringSeries(database, {
        userId,
        id: randomUUID(),
        externalActivityId: activityId,
        series: heartRateSeries({
          externalId: "garmin-run-no-gps-heart-rate",
          activityExternalId: "garmin-run-no-gps",
          baseTime: "2026-06-21T10:00:00.000Z",
          samples: [
            { offsetSeconds: 0, value: { value: 122, unit: "beatsPerMinute" } },
            { offsetSeconds: 60, value: { value: 132, unit: "beatsPerMinute" } }
          ]
        })
      });

      const response = await getAgent(
        app,
        `/agent/monitoring/activities/${activityId}`
      );

      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.route, null);
      assert.equal(body.heartRate.sampleCount, 2);
      assert.deepEqual(
        body.seriesSummaries.map((series) => series.seriesType),
        ["heartRate"]
      );
    } finally {
      await database.close();
    }
  }
);

test(
  "agent read surface requires auth and enforces per-key rate limiting",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const app = createAgentReadApp({
      agentRateLimit: {
        rateLimitEnabled: true,
        rateLimitTimeWindow: 60 * 1000,
        rateLimitMax: 1
      },
      agentReadStore: createDrizzleAgentReadStore(database.db),
      rateLimitBackend: createDrizzleRateLimitBackend(database.db),
      userId: `agent-read-rate-limit-user-${randomUUID()}`
    });

    try {
      const unauthorizedResponse = await app.request("/agent/history/sets?limit=1");
      assert.equal(unauthorizedResponse.status, 401);

      const firstResponse = await getAgent(app, "/agent/history/sets?limit=1");
      assert.equal(firstResponse.status, 200);
      assert.equal(firstResponse.headers.get("x-rate-limit-limit"), "1");
      assert.equal(firstResponse.headers.get("x-rate-limit-remaining"), "0");

      const overLimitResponse = await getAgent(app, "/agent/history/sets?limit=1");
      assert.equal(overLimitResponse.status, 429);
      assert.equal(overLimitResponse.headers.get("retry-after"), "60");
      assert.deepEqual(await overLimitResponse.json(), {
        code: "rate_limited",
        message: "Too many requests.",
        limit: 1,
        retryAfterSeconds: 60
      });
    } finally {
      await database.close();
    }
  }
);

test(
  "a Set on a kept id joins the user's own row, and without a kept row joins through the redirect",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const keeperId = `agent-read-kept-user-${randomUUID()}`;
    const otherId = `agent-read-unkept-user-${randomUUID()}`;
    const [redirect] = PLATFORM_EXERCISE_SEED_REDIRECTS;
    const target = buildPlatformCatalogExercises().find(
      (exercise) => exercise.id === redirect.toExerciseId
    );
    const categoryId = randomUUID();
    const at = new Date("2026-11-05T00:00:00.000Z");
    const row = (id, userId, payload) => ({
      id,
      userId,
      deviceId: "device-agent-read-test",
      updatedAt: at,
      receivedAt: at,
      deletedAt: null,
      payload: { id, ...payload, updated_at: at.toISOString(), deleted_at: null }
    });

    try {
      await seedUser(database, keeperId);
      await seedUser(database, otherId);
      await database.db
        .insert(schema.exerciseCategories)
        .values(row(categoryId, keeperId, { name: "Kept Category" }));
      await database.db.insert(schema.exercises).values(
        row(redirect.fromExerciseId, keeperId, {
          library_origin: "user",
          name: "My Kept Exercise",
          category_id: categoryId,
          dimension_ids: JSON.stringify(["load", "reps"])
        })
      );
      for (const userId of [keeperId, otherId]) {
        await seedLoggedSet(database, {
          userId,
          id: randomUUID(),
          exerciseId: redirect.fromExerciseId,
          // Blank in the Set, so the name and category come from the join.
          exerciseName: null,
          exerciseCategoryId: null,
          exerciseCategoryName: null,
          performedAt: "2026-11-01T06:00:00.000Z",
          position: 0,
          values: {
            load: { entered: "100", unit: "kilogram" },
            reps: { entered: "5", unit: "repetition" }
          }
        });
      }
      const readSet = async (userId) => {
        const response = await getAgent(
          createAgentReadApp({
            agentReadStore: createDrizzleAgentReadStore(database.db),
            userId
          }),
          "/agent/history/sets?limit=1"
        );
        assert.equal(response.status, 200);
        const [set] = (await response.json()).sets;
        return set;
      };

      const keptSet = await readSet(keeperId);
      assert.equal(keptSet.exerciseId, redirect.fromExerciseId);
      assert.equal(keptSet.exerciseName, "My Kept Exercise");
      assert.deepEqual(keptSet.category, {
        id: categoryId,
        name: "Kept Category"
      });

      const redirectedSet = await readSet(otherId);
      assert.equal(redirectedSet.exerciseId, redirect.fromExerciseId);
      assert.equal(redirectedSet.exerciseName, target.name);
      assert.deepEqual(redirectedSet.category, target.category);
    } finally {
      await database.close();
    }
  }
);

// Platform Library Updates: the analytics read resolves its id through the
// caller's catalog and its progressSeries through the caller's kept rows, so
// the same two ids read differently for an account that holds the source id.
test(
  "the analytics read of a kept id is the user's own exercise and Sets, and without a kept row follows the redirect",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const keeperId = `agent-read-kept-user-${randomUUID()}`;
    const otherId = `agent-read-unkept-user-${randomUUID()}`;
    // A load-and-reps target, so the Sets below reach its Progress Measure.
    const catalog = buildPlatformCatalogExercises();
    const targetOf = (candidate) =>
      catalog.find((exercise) => exercise.id === candidate.toExerciseId);
    const redirect = PLATFORM_EXERCISE_SEED_REDIRECTS.find(
      (candidate) => targetOf(candidate).recordProfile === "repMax"
    );
    const target = targetOf(redirect);
    const at = new Date("2026-11-05T00:00:00.000Z");
    const row = (id, userId, payload) => ({
      id,
      userId,
      deviceId: "device-agent-read-test",
      updatedAt: at,
      receivedAt: at,
      deletedAt: null,
      payload: { id, ...payload, updated_at: at.toISOString(), deleted_at: null }
    });
    // One Workout on the redirect's source and one on its target; the Set ids
    // carry the account, so another account's Set cannot pass for this one's.
    const setId = (userId, exerciseId) => `${userId}-set-${exerciseId}`;
    const seedHistory = async (userId) => {
      const days = [
        [redirect.fromExerciseId, "2026-10-01", "100"],
        [redirect.toExerciseId, "2026-10-02", "110"]
      ];
      await database.db.insert(schema.workoutSessions).values(
        days.map(([exerciseId, localDate]) =>
          row(`${userId}-w-${exerciseId}`, userId, {
            local_date: localDate,
            started_at: `${localDate}T06:00:00.000Z`,
            ended_at: `${localDate}T07:00:00.000Z`
          })
        )
      );
      await database.db.insert(schema.loggedSets).values(
        days.map(([exerciseId, localDate, load]) =>
          row(setId(userId, exerciseId), userId, {
            workout_id: `${userId}-w-${exerciseId}`,
            performed_at: `${localDate}T06:00:00.000Z`,
            exercise_id: exerciseId,
            position: 0,
            is_completed: true,
            values: {
              load: { entered: load, unit: "kilogram" },
              reps: { entered: "5", unit: "repetition" }
            }
          })
        )
      );
    };

    try {
      await seedUser(database, keeperId);
      await seedUser(database, otherId);
      await seedHistory(keeperId);
      await seedHistory(otherId);
      const categoryId = randomUUID();
      await database.db
        .insert(schema.exerciseCategories)
        .values(row(categoryId, keeperId, { name: "Kept Category" }));
      await database.db.insert(schema.exercises).values(
        row(redirect.fromExerciseId, keeperId, {
          library_origin: "user",
          name: "My Kept Exercise",
          category_id: categoryId,
          dimension_ids: JSON.stringify(["load", "reps"])
        })
      );

      const catalogStore = createDrizzleAgentCatalogStore(database.db);
      const readAnalytics = async (userId, exerciseId) => {
        const response = await getAgent(
          createApp({
            logger: { info() {}, error() {} },
            agentApiKeyStore: createAgentKeyStore(userId, {}, "agent-read-key-1"),
            agentCatalogStore: catalogStore,
            agentReadStore: createDrizzleAgentReadStore(database.db),
            agentProgressReadStore: createDrizzleAgentProgressReadStore({
              db: database.db,
              settingsStore: createDrizzleAgentSettingsStore(database.db),
              catalogStore
            })
          }),
          `/agent/analytics/exercises/${exerciseId}`
        );
        assert.equal(response.status, 200);
        return response.json();
      };
      const seriesSetIds = (body) =>
        body.progressSeries.points.map((point) => point.setId);

      // The keeper's source id is their own exercise, with only its own Set.
      const kept = await readAnalytics(keeperId, redirect.fromExerciseId);
      assert.equal(kept.exercise.id, redirect.fromExerciseId);
      assert.equal(kept.exercise.name, "My Kept Exercise");
      assert.equal(kept.exercise.library, "user");
      assert.equal(kept.totalSetCount, 1);
      assert.equal(kept.progressSeries.exerciseId, redirect.fromExerciseId);
      assert.deepEqual(seriesSetIds(kept), [
        setId(keeperId, redirect.fromExerciseId)
      ]);

      // Their merge target does not include the kept exercise's Set.
      const keeperTarget = await readAnalytics(keeperId, redirect.toExerciseId);
      assert.equal(keeperTarget.exercise.id, redirect.toExerciseId);
      assert.equal(keeperTarget.totalSetCount, 1);
      assert.deepEqual(seriesSetIds(keeperTarget), [
        setId(keeperId, redirect.toExerciseId)
      ]);

      // With no kept row, the same source id is the merge target, and the
      // target's series folds the account's own Sets from both ids.
      const folded = [
        setId(otherId, redirect.fromExerciseId),
        setId(otherId, redirect.toExerciseId)
      ];
      const redirected = await readAnalytics(otherId, redirect.fromExerciseId);
      assert.equal(redirected.exercise.id, redirect.toExerciseId);
      assert.equal(redirected.exercise.name, target.name);
      assert.equal(redirected.exercise.library, "platform");
      assert.deepEqual(seriesSetIds(redirected), folded);
      assert.deepEqual(
        seriesSetIds(await readAnalytics(otherId, redirect.toExerciseId)),
        folded
      );
    } finally {
      await database.close();
    }
  }
);

function createAgentReadApp({
  agentRateLimit,
  agentKeyId = "agent-read-key-1",
  agentReadStore,
  logger = { info() {}, error() {} },
  rateLimitBackend,
  userId = "user-1"
}) {
  return createApp({
    logger,
    agentApiKeyStore: createAgentKeyStore(userId, agentRateLimit, agentKeyId),
    agentCatalogStore: createInMemoryAgentCatalogStore(catalogFixtures(userId)),
    agentReadStore,
    rateLimitBackend
  });
}

function createAgentKeyStore(userId, agentRateLimit = {}, keyId) {
  return {
    async authenticateAgentApiKey(secret) {
      if (secret !== "prn_agent_secret") {
        return null;
      }

      return {
        userId,
        keyId,
        keyName: "Garage coach",
        ...agentRateLimit
      };
    },
    async createAgentApiKey() {
      throw new Error("createAgentApiKey should not be called.");
    },
    async listAgentApiKeys() {
      throw new Error("listAgentApiKeys should not be called.");
    },
    async revokeAgentApiKey() {
      throw new Error("revokeAgentApiKey should not be called.");
    },
    async verifySessionBearerToken() {
      throw new Error("verifySessionBearerToken should not be called.");
    }
  };
}

function getAgent(app, path) {
  return app.request(path, {
    headers: {
      authorization: "Bearer prn_agent_secret"
    }
  });
}

async function seedUser(database, userId) {
  await database.db.insert(schema.user).values({
    id: userId,
    name: "Agent Read User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
}

async function seedLoggedSet({
  db
}, {
  userId,
  id,
  exerciseId,
  exerciseName,
  exerciseCategoryId = "cat-strength",
  exerciseCategoryName = "Strength",
  performedAt,
  position,
  values
}) {
  await db.insert(schema.loggedSets).values({
    id,
    userId,
    deviceId: "device-agent-read-test",
    updatedAt: new Date(performedAt),
    receivedAt: new Date(performedAt),
    deletedAt: null,
    payload: {
      id,
      workout_id: `workout-${id}`,
      workout_started_at: performedAt,
      workout_ended_at: null,
      workout_timezone: "Australia/Brisbane",
      exercise_id: exerciseId,
      exercise_name: exerciseName,
      exercise_category_id: exerciseCategoryId,
      exercise_category_name: exerciseCategoryName,
      position,
      values,
      comment: null,
      rpe: null,
      side: null,
      deleted_at: null,
      updated_at: performedAt,
      ...flatDimensionValues(values)
    }
  });
}

async function seedExternalActivity({
  db
}, {
  userId,
  id,
  externalId,
  startedAt,
  endedAt,
  source = "garmin"
}) {
  await db.insert(schema.externalActivities).values({
    id,
    userId,
    deviceId: "device-agent-read-test",
    source,
    externalId,
    startedAt: new Date(startedAt),
    endedAt: new Date(endedAt),
    timezone: "Australia/Brisbane",
    activityType: "cycling",
    mappedExerciseId: null,
    summaryJson: {},
    summaryMetricsJson: [],
    setsJson: null,
    updatedAt: new Date(endedAt),
    deletedAt: null,
    receivedAt: new Date(endedAt)
  });
}

async function seedMetric({
  db
}, {
  userId,
  id,
  name,
  unit
}) {
  await db.insert(schema.metrics).values({
    id,
    userId,
    deviceId: "device-agent-read-test",
    name,
    unit,
    valueShape: "scalar",
    metricGroup: "monitoring",
    goalType: null,
    goalTargetValue: null,
    enabled: true,
    pinned: false,
    sortOrder: 0,
    updatedAt: new Date("2026-06-20T10:00:00.000Z"),
    deletedAt: null,
    receivedAt: new Date("2026-06-20T10:00:00.000Z")
  });
}

async function seedMetricReading({
  db
}, {
  userId,
  id,
  metricId,
  externalActivityId,
  externalId,
  value,
  scalarValue,
  scalarEntered,
  windowStartedAt,
  windowEndedAt,
  source = "garmin"
}) {
  await db.insert(schema.metricReadings).values({
    id,
    userId,
    deviceId: "device-agent-read-test",
    metricId,
    externalActivityId,
    valueJson: value,
    scalarValue,
    scalarEntered,
    atTime: null,
    windowStartedAt: new Date(windowStartedAt),
    windowEndedAt: new Date(windowEndedAt),
    provenance: "integration",
    source,
    externalId,
    comment: null,
    updatedAt: new Date(windowEndedAt),
    deletedAt: null,
    receivedAt: new Date(windowEndedAt)
  });
}

async function seedMonitoringSeries({
  db
}, {
  userId,
  id,
  externalActivityId,
  series
}) {
  const encoded = encodeCanonicalSeriesBlob(series);
  await db.insert(schema.monitoringSeries).values({
    id,
    userId,
    deviceId: "device-agent-read-test",
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
    updatedAt: new Date(series.baseTime),
    deletedAt: null,
    receivedAt: new Date(series.baseTime)
  });
}

function heartRateSeries({
  externalId,
  activityExternalId,
  samples,
  baseTime = "2026-06-20T10:00:00.000Z"
}) {
  return {
    source: "garmin",
    externalId,
    type: "heartRate",
    anchor: {
      kind: "activity",
      source: "garmin",
      externalId: activityExternalId
    },
    baseTime,
    timezone: "Australia/Brisbane",
    samples
  };
}

function locationSeries({
  externalId,
  activityExternalId,
  samples,
  baseTime = "2026-06-20T10:00:00.000Z"
}) {
  return {
    source: "garmin",
    externalId,
    type: "location",
    anchor: {
      kind: "activity",
      source: "garmin",
      externalId: activityExternalId
    },
    baseTime,
    timezone: "Australia/Brisbane",
    samples
  };
}

function locationSample(offsetSeconds, latitude, longitude) {
  return {
    offsetSeconds,
    value: {
      latitude: { value: latitude, unit: "degree" },
      longitude: { value: longitude, unit: "degree" }
    }
  };
}

function captureLogger(logs) {
  return {
    info(payload, message) {
      logs.push({ level: "info", message, payload });
    },
    error(payload, message) {
      logs.push({ level: "error", message, payload });
    }
  };
}

function flatDimensionValues(values) {
  return Object.fromEntries(
    Object.entries(values).flatMap(([dimension, value]) => [
      [`${dimension}_entered`, value.entered],
      [`${dimension}_unit`, value.unit]
    ])
  );
}

function catalogFixtures(userId = "user-1") {
  return [
    exercise({
      id: "platform-back-squat",
      library: "platform",
      name: "Back Squat",
      categoryId: "cat-strength"
    }),
    exercise({
      id: "user-back-squat",
      library: "user",
      ownerUserId: userId,
      name: "Back Squat",
      categoryId: "cat-strength",
      shadowedPlatformExerciseId: "platform-back-squat"
    }),
    exercise({
      id: "platform-bench-press",
      library: "platform",
      name: "Bench Press",
      categoryId: "cat-strength"
    })
  ];
}

function exercise({
  id,
  library,
  ownerUserId = null,
  name,
  categoryId,
  active = true,
  favorite = false,
  equipment = ["barbell"],
  shadowedPlatformExerciseId = null
}) {
  return {
    id,
    library,
    ownerUserId,
    name,
    category: {
      id: categoryId,
      name: categoryId === "cat-strength" ? "Strength" : "Other"
    },
    dimensions: ["load", "reps"],
    equipment,
    loadMode: "added",
    recordProfile: "repMax",
    favorite,
    active,
    shadowedPlatformExerciseId
  };
}
