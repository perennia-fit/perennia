import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { eq } from "drizzle-orm";
import {
  CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS,
  createCanonicalIngestionPipeline,
  createDrizzleExternalActivityStore,
  createMigratedServerApp,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for canonical ingestion tests.");
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

const series = {
  source: "garmin",
  externalId: "activity-123:heart-rate-series",
  type: "heartRate",
  anchor: {
    kind: "activity",
    source: "garmin",
    externalId: "activity-123"
  },
  baseTime: "2026-06-23T20:00:00.000Z",
  timezone: "Australia/Brisbane",
  samples: [
    {
      offsetSeconds: 0,
      value: { value: 104, unit: "beatsPerMinute" }
    },
    {
      offsetSeconds: 60,
      value: { value: 118, unit: "beatsPerMinute" }
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

test("canonical ingestion normalizes and stores source observations", async () => {
  const externalActivityStore = createRecordingExternalActivityStore();
  const pipeline = createCanonicalIngestionPipeline({ externalActivityStore });
  const result = await pipeline.ingestCanonicalBatch({
    userId: "user-1",
    deviceId: "integration:garmin",
    importedAt: new Date("2026-06-25T07:30:00.000Z"),
    consentedDataClasses: ["activities", "heartRate"],
    activities: [
      {
        ...activity,
        personalRecord: true,
        acquisitionAdapterScratch: "ignored but reported"
      }
    ],
    series: [series],
    metricReadings: [metricReading]
  });

  assert.equal(result.accepted, true);
  assert.equal(result.activities.length, 1);
  assert.equal(result.activities[0].status, "created");
  assert.equal(result.activities[0].stored?.id, "external-1");
  assert.equal(result.activities[0].source, "garmin");
  assert.equal(result.activities[0].externalId, "activity-123");
  assert.equal(result.storedExternalActivities.length, 1);
  assert.deepEqual(result.series, [series]);
  assert.deepEqual(result.metricReadings, [metricReading]);
  assert.deepEqual(result.materializedWorkouts, []);
  assert.deepEqual(result.activityLinks, []);

  assert.equal(externalActivityStore.calls.length, 1);
  assert.equal(externalActivityStore.calls[0].deviceId, "integration:garmin");
  assert.equal(externalActivityStore.calls[0].activity.source, "garmin");
  assert.equal(
    externalActivityStore.calls[0].activity.activityType,
    "STRENGTH_TRAINING_CUSTOM_VENDOR_STRING"
  );
  assert.equal("personalRecord" in externalActivityStore.calls[0].activity, false);
  assert.equal(
    "acquisitionAdapterScratch" in externalActivityStore.calls[0].activity,
    false
  );
  assert.equal(
    result.reviewFlags.some(
      (flag) =>
        flag.itemType === "activity" &&
        flag.rule === "canonical_activity_shape"
    ),
    true
  );
});

test("canonical ingestion maps vendor activity types to Platform exercises", async () => {
  const externalActivityStore = createRecordingExternalActivityStore();
  const pipeline = createCanonicalIngestionPipeline({ externalActivityStore });
  const vendorActivities = [
    {
      ...activity,
      source: "garmin",
      externalId: "garmin-trail",
      activityType: "trail_running"
    },
    {
      ...activity,
      source: "coros",
      externalId: "coros-trail",
      activityType: "trail run"
    },
    {
      ...activity,
      source: "strava",
      externalId: "strava-trail",
      activityType: "TrailRun"
    }
  ];

  const result = await pipeline.ingestCanonicalBatch({
    userId: "user-1",
    deviceId: "integration:trail-watch",
    importedAt: new Date("2026-06-25T07:30:10.000Z"),
    consentedDataClasses: ["activities", "heartRate"],
    activities: vendorActivities
  });

  assert.deepEqual(
    result.activities.map((activityResult) => activityResult.status),
    ["created", "created", "created"]
  );
  assert.deepEqual(
    externalActivityStore.calls.map((call) => call.activity.mappedExerciseId),
    [
      CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning,
      CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning,
      CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning
    ]
  );
  assert.deepEqual(
    externalActivityStore.calls.map((call) => call.activity.activityType),
    ["trail_running", "trail run", "TrailRun"]
  );
  assert.deepEqual(
    result.storedExternalActivities.map((stored) => stored.mappedExerciseId),
    [
      CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning,
      CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning,
      CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning
    ]
  );
});

test("canonical ingestion falls back unmapped vendor types to the family generic", async () => {
  const externalActivityStore = createRecordingExternalActivityStore();
  const pipeline = createCanonicalIngestionPipeline({ externalActivityStore });

  const result = await pipeline.ingestCanonicalBatch({
    userId: "user-1",
    deviceId: "integration:garmin",
    importedAt: new Date("2026-06-25T07:30:20.000Z"),
    consentedDataClasses: ["activities", "heartRate"],
    activities: [
      {
        ...activity,
        externalId: "unknown-running-variant",
        activityType: "mountain_running_ultra"
      }
    ]
  });

  assert.equal(result.activities[0].status, "created");
  assert.equal(
    externalActivityStore.calls[0].activity.mappedExerciseId,
    CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.running
  );
  assert.equal(
    result.activities[0].stored?.mappedExerciseId,
    CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.running
  );
  assert.equal(
    result.activities[0].stored?.activityType,
    "mountain_running_ultra"
  );
});

test("canonical ingestion materializes cardio activities through the store-time-link stage", async () => {
  const externalActivityStore = createRecordingExternalActivityStore();
  const activityMaterializationStore = createRecordingActivityMaterializationStore();
  const pipeline = createCanonicalIngestionPipeline({
    externalActivityStore,
    activityMaterializationStore
  });

  const result = await pipeline.ingestCanonicalBatch({
    userId: "user-1",
    deviceId: "integration:garmin",
    importedAt: new Date("2026-06-25T07:30:25.000Z"),
    consentedDataClasses: ["activities", "heartRate"],
    activities: [
      {
        ...activity,
        externalId: "trail-run-cardio",
        activityType: "trail_running",
        summary: {
          duration: { value: 1800, unit: "second" },
          distance: { value: 5, unit: "kilometer" }
        },
        sets: undefined
      }
    ]
  });

  assert.equal(activityMaterializationStore.calls.length, 1);
  assert.equal(
    activityMaterializationStore.calls[0].activity.mappedExerciseId,
    CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning
  );
  assert.equal(
    activityMaterializationStore.calls[0].externalActivity.id,
    "external-1"
  );
  assert.deepEqual(result.materializedWorkouts, [
    {
      workoutId: "workout-external-1",
      setIds: ["set-external-1"],
      externalActivityId: "external-1",
      source: "garmin",
      externalId: "trail-run-cardio",
      exerciseId: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning,
      status: "created"
    }
  ]);
  assert.deepEqual(result.activityLinks, [
    {
      id: "link-external-1",
      workoutId: "workout-external-1",
      externalActivityId: "external-1",
      linkKind: "materialized_source",
      status: "created"
    }
  ]);
});

test("canonical ingestion gates FIT strength sets through shared validation", async () => {
  const externalActivityStore = createRecordingExternalActivityStore();
  const activityMaterializationStore = createRecordingActivityMaterializationStore();
  const pipeline = createCanonicalIngestionPipeline({
    externalActivityStore,
    activityMaterializationStore
  });

  const result = await pipeline.ingestCanonicalBatch({
    userId: "user-1",
    deviceId: "integration:garmin",
    importedAt: new Date("2026-06-25T07:30:27.000Z"),
    consentedDataClasses: ["activities", "heartRate"],
    activities: [
      {
        ...activity,
        externalId: "fit-strength",
        activityType: "strength_training",
        summary: {
          duration: { value: 2700, unit: "second" }
        },
        sets: [
          {
            ...activity.sets[0],
            externalId: "fit-strength:set-clean",
            dimensions: {
              load: { value: 100, unit: "kilogram" },
              reps: { value: 5, unit: "repetition" }
            }
          },
          {
            ...activity.sets[0],
            externalId: "fit-strength:set-soft",
            dimensions: {
              load: { value: 351, unit: "kilogram" },
              reps: { value: 3, unit: "repetition" }
            }
          },
          {
            ...activity.sets[0],
            externalId: "fit-strength:set-hard",
            dimensions: {
              load: { value: 1000.01, unit: "kilogram" },
              reps: { value: 1, unit: "repetition" }
            }
          }
        ]
      }
    ]
  });

  assert.equal(activityMaterializationStore.strengthCalls.length, 1);
  assert.equal(activityMaterializationStore.strengthCalls[0].sets.length, 2);
  assert.deepEqual(
    activityMaterializationStore.strengthCalls[0].sets.map((set) => set.externalId),
    ["fit-strength:set-clean", "fit-strength:set-soft"]
  );
  assert.deepEqual(
    activityMaterializationStore.strengthCalls[0].sets.map((set) =>
      set.warnings.map((warning) => warning.rule)
    ),
    [[], ["added_load_improbable"]]
  );
  assert.deepEqual(result.materializedWorkouts, [
    {
      workoutId: "workout-external-1",
      setIds: ["set-external-1-0", "set-external-1-1"],
      externalActivityId: "external-1",
      source: "garmin",
      externalId: "fit-strength",
      exerciseId: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.strengthTraining,
      status: "created"
    }
  ]);
  assert.equal(
    result.reviewFlags.some(
      (flag) =>
        flag.severity === "warning" &&
        flag.rule === "added_load_improbable" &&
        flag.field === "activities[0].sets[1].dimensions.load.value"
    ),
    true
  );
  assert.equal(
    result.reviewFlags.some(
      (flag) =>
        flag.severity === "error" &&
        flag.rule === "load_max_kilograms" &&
        flag.field === "activities[0].sets[2].dimensions.load.value"
    ),
    true
  );
});

test("canonical ingestion flags invalid observations without aborting the batch", async () => {
  const externalActivityStore = createRecordingExternalActivityStore();
  const pipeline = createCanonicalIngestionPipeline({ externalActivityStore });
  const invalidActivity = {
    ...activity,
    externalId: "invalid-activity"
  };
  delete invalidActivity.timezone;

  const result = await pipeline.ingestCanonicalBatch({
    userId: "user-1",
    deviceId: "integration:garmin",
    importedAt: new Date("2026-06-25T07:30:30.000Z"),
    consentedDataClasses: ["activities", "heartRate"],
    activities: [invalidActivity, activity]
  });

  assert.deepEqual(
    result.activities.map((activityResult) => activityResult.status),
    ["notStored", "created"]
  );
  assert.equal(result.activities[0].stored, null);
  assert.equal(result.activities[1].stored?.id, "external-1");
  assert.equal(externalActivityStore.calls.length, 1);
  assert.equal(
    result.activities[0].reviewFlags.some(
      (flag) =>
        flag.severity === "error" &&
        flag.rule === "canonical_activity_unstored" &&
        flag.field === "activities[0].timezone"
    ),
    true
  );
});

test("canonical ingestion flags reversed activity windows while storing the observation", async () => {
  const externalActivityStore = createRecordingExternalActivityStore();
  const pipeline = createCanonicalIngestionPipeline({ externalActivityStore });
  const result = await pipeline.ingestCanonicalBatch({
    userId: "user-1",
    deviceId: "integration:garmin",
    importedAt: new Date("2026-06-25T07:30:45.000Z"),
    consentedDataClasses: ["activities", "heartRate"],
    activities: [
      {
        ...activity,
        externalId: "reversed-activity",
        startedAt: "2026-06-23T20:45:00.000Z",
        endedAt: "2026-06-23T20:00:00.000Z"
      }
    ]
  });

  assert.equal(result.activities[0].status, "created");
  assert.equal(result.activities[0].stored?.externalId, "reversed-activity");
  assert.equal(
    result.reviewFlags.some(
      (flag) =>
        flag.severity === "warning" &&
        flag.rule === "activity_window_reversed" &&
        flag.field === "activities[0].endedAt"
    ),
    true
  );
});

test("canonical ingestion flags and drops invalid series and metric readings", async () => {
  const externalActivityStore = createRecordingExternalActivityStore();
  const pipeline = createCanonicalIngestionPipeline({ externalActivityStore });
  const invalidSeries = {
    ...series,
    externalId: "invalid-series",
    samples: []
  };
  const invalidMetricReading = {
    ...metricReading,
    externalId: "invalid-metric-reading"
  };
  delete invalidMetricReading.metricKey;

  const result = await pipeline.ingestCanonicalBatch({
    userId: "user-1",
    deviceId: "integration:garmin",
    importedAt: new Date("2026-06-25T07:30:50.000Z"),
    consentedDataClasses: ["activities", "heartRate"],
    activities: [activity],
    series: [series, invalidSeries],
    metricReadings: [metricReading, invalidMetricReading]
  });

  assert.deepEqual(result.series, [series]);
  assert.deepEqual(result.metricReadings, [metricReading]);
  assert.equal(
    result.reviewFlags.some(
      (flag) =>
        flag.itemType === "series" &&
        flag.rule === "canonical_series_shape" &&
        flag.field === "series[1].samples"
    ),
    true
  );
  assert.equal(
    result.reviewFlags.some(
      (flag) =>
        flag.itemType === "metricReading" &&
        flag.rule === "canonical_metric_reading_shape" &&
        flag.field === "metricReadings[1].metricKey"
    ),
    true
  );
});

test("canonical ingestion drops non-consented import data classes in the shared pipeline", async () => {
  const externalActivityStore = createRecordingExternalActivityStore();
  const pipeline = createCanonicalIngestionPipeline({ externalActivityStore });
  const sleepReading = {
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
  const bodyCompositionReading = {
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
  const cadenceSeries = {
    ...series,
    externalId: "activity-123:cadence-series",
    type: "cadence"
  };

  const result = await pipeline.ingestCanonicalBatch({
    userId: "user-1",
    deviceId: "integration:garmin",
    importedAt: new Date("2026-06-25T07:31:30.000Z"),
    consentedDataClasses: [
      "activities",
      "sleepWellness",
      "bodyComposition"
    ],
    activities: [activity],
    series: [series, cadenceSeries],
    metricReadings: [
      metricReading,
      sleepReading,
      bodyCompositionReading
    ]
  });

  assert.equal(result.activities[0].status, "created");
  assert.equal(result.storedExternalActivities.length, 1);
  assert.deepEqual(result.storedExternalActivities[0].summaryMetrics, []);
  assert.deepEqual(result.metricReadings, [
    sleepReading,
    bodyCompositionReading
  ]);
  assert.deepEqual(result.series, [cadenceSeries]);
  assert.equal(
    result.reviewFlags.some(
      (flag) =>
        flag.itemType === "activity" &&
        flag.rule === "monitoring_data_not_consented" &&
        flag.field === "activities[0].summaryMetrics[0]"
    ),
    true
  );
  assert.equal(
    result.reviewFlags.some(
      (flag) =>
        flag.itemType === "metricReading" &&
        flag.rule === "monitoring_data_not_consented" &&
        flag.field === "metricReadings[0]"
    ),
    true
  );
  assert.equal(
    result.reviewFlags.some(
      (flag) =>
        flag.itemType === "series" &&
        flag.rule === "monitoring_data_not_consented" &&
        flag.field === "series[0]"
    ),
    true
  );
});

test("canonical ingestion refreshes duplicates and respects tombstones", async () => {
  const externalActivityStore = createRecordingExternalActivityStore({
    tombstonedKeys: new Set(["user-1:garmin:tombstoned-activity"])
  });
  const pipeline = createCanonicalIngestionPipeline({ externalActivityStore });
  const result = await pipeline.ingestCanonicalBatch({
    userId: "user-1",
    deviceId: "integration:garmin",
    importedAt: new Date("2026-06-25T07:31:00.000Z"),
    consentedDataClasses: ["activities", "heartRate"],
    activities: [
      activity,
      {
        ...activity,
        activityType: "UPDATED_VENDOR_TYPE",
        summary: {
          ...activity.summary,
          duration: { value: 2760, unit: "second" }
        }
      },
      {
        ...activity,
        externalId: "tombstoned-activity",
        activityType: "TOMBSTONE_ATTEMPT"
      }
    ]
  });

  assert.deepEqual(
    result.activities.map((activityResult) => activityResult.status),
    ["created", "refreshed", "tombstoned"]
  );
  assert.equal(result.activities[0].stored?.id, result.activities[1].stored?.id);
  assert.equal(result.activities[1].stored?.activityType, "UPDATED_VENDOR_TYPE");
  assert.equal(result.activities[2].stored, null);
  assert.equal(externalActivityStore.rows.size, 1);
});

test(
  "canonical ingestion persists and refreshes External Activities through Postgres",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const externalActivityStore = createDrizzleExternalActivityStore(
      serverApp.database.db
    );
    const pipeline = createCanonicalIngestionPipeline({ externalActivityStore });
    const userId = await createUser(serverApp);

    try {
      const result = await pipeline.ingestCanonicalBatch({
        userId,
        deviceId: "integration:garmin",
        importedAt: new Date("2026-06-25T07:32:00.000Z"),
        consentedDataClasses: ["activities", "heartRate"],
        activities: [
          activity,
          {
            ...activity,
            activityType: "UPDATED_VENDOR_TYPE",
            summary: {
              ...activity.summary,
              duration: { value: 2760, unit: "second" }
            }
          }
        ]
      });

      assert.deepEqual(
        result.activities.map((activityResult) => activityResult.status),
        ["created", "refreshed"]
      );
      assert.equal(
        result.activities[0].stored?.id,
        result.activities[1].stored?.id
      );

      const rows = await serverApp.database.sql`
        select id, activity_type, summary_json
        from external_activities
        where user_id = ${userId}
          and source = ${activity.source}
          and external_id = ${activity.externalId}
      `;
      assert.equal(rows.length, 1);
      assert.equal(rows[0].activity_type, "UPDATED_VENDOR_TYPE");
      assert.deepEqual(rows[0].summary_json, {
        ...activity.summary,
        duration: { value: 2760, unit: "second" }
      });

      await serverApp.database.db
        .update(schema.externalActivities)
        .set({
          deletedAt: new Date("2026-06-25T07:33:00.000Z"),
          updatedAt: new Date("2026-06-25T07:33:00.000Z")
        })
        .where(eq(schema.externalActivities.id, rows[0].id));

      const tombstoneResult = await pipeline.ingestCanonicalBatch({
        userId,
        deviceId: "integration:garmin",
        importedAt: new Date("2026-06-25T07:34:00.000Z"),
        consentedDataClasses: ["activities", "heartRate"],
        activities: [
          {
            ...activity,
            activityType: "RESURRECTION_ATTEMPT"
          }
        ]
      });

      assert.equal(tombstoneResult.activities[0].status, "tombstoned");
      assert.equal(tombstoneResult.activities[0].stored, null);
      const readBack = await externalActivityStore.findExternalActivity({
        userId,
        source: activity.source,
        externalId: activity.externalId
      });
      assert.equal(readBack, null);
    } finally {
      await serverApp.database.close();
    }
  }
);

function createRecordingExternalActivityStore({ tombstonedKeys = new Set() } = {}) {
  const rows = new Map();
  const calls = [];

  return {
    calls,
    rows,
    async storeCanonicalActivity({ userId, deviceId, activity, importedAt }) {
      calls.push({ userId, deviceId, activity, importedAt });
      const key = `${userId}:${activity.source}:${activity.externalId}`;
      if (tombstonedKeys.has(key)) {
        return null;
      }

      const existing = rows.get(key);
      const stored = {
        id: existing?.id ?? `external-${rows.size + 1}`,
        userId,
        deviceId,
        source: activity.source,
        externalId: activity.externalId,
        startedAt: activity.startedAt,
        endedAt: activity.endedAt,
        timezone: activity.timezone,
        activityType: activity.activityType,
        mappedExerciseId: activity.mappedExerciseId ?? null,
        summary: activity.summary,
        summaryMetrics: activity.summaryMetrics,
        sets: activity.sets,
        updatedAt: (importedAt ?? new Date()).toISOString(),
        deletedAt: null
      };
      rows.set(key, stored);

      return stored;
    },
    async findExternalActivity({ userId, source, externalId }) {
      return rows.get(`${userId}:${source}:${externalId}`) ?? null;
    }
  };
}

function createRecordingActivityMaterializationStore() {
  const calls = [];
  const strengthCalls = [];

  return {
    calls,
    strengthCalls,
    async linkActivityByTimeOverlap() {
      return { kind: "none" };
    },
    async materializeCardioActivity(input) {
      calls.push(input);

      return {
        workout: {
          workoutId: `workout-${input.externalActivity.id}`,
          setIds: [`set-${input.externalActivity.id}`],
          externalActivityId: input.externalActivity.id,
          source: input.activity.source,
          externalId: input.activity.externalId,
          exerciseId: input.activity.mappedExerciseId,
          status: "created"
        },
        activityLink: {
          id: `link-${input.externalActivity.id}`,
          workoutId: `workout-${input.externalActivity.id}`,
          externalActivityId: input.externalActivity.id,
          linkKind: "materialized_source",
          status: "created"
        }
      };
    },
    async materializeStrengthActivity(input) {
      strengthCalls.push(input);

      return {
        workout: {
          workoutId: `workout-${input.externalActivity.id}`,
          setIds: input.sets.map(
            (_set, index) => `set-${input.externalActivity.id}-${index}`
          ),
          externalActivityId: input.externalActivity.id,
          source: input.activity.source,
          externalId: input.activity.externalId,
          exerciseId: input.activity.mappedExerciseId,
          status: "created"
        },
        activityLink: {
          id: `link-${input.externalActivity.id}`,
          workoutId: `workout-${input.externalActivity.id}`,
          externalActivityId: input.externalActivity.id,
          linkKind: "materialized_source",
          status: "created"
        }
      };
    }
  };
}

async function createUser(serverApp) {
  const userId = `canonical-ingestion-user-${randomUUID()}`;

  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: "Canonical Ingestion User",
    email: `${userId}@example.com`,
    emailVerified: true
  });

  return userId;
}
