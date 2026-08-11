import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { createOpenApiDocument } from "../../../apps/server/src/index.ts";
import {
  CanonicalActivitySchema,
  CanonicalMetricReadingSchema,
  CanonicalSeriesSchema,
  CanonicalSetSchema
} from "../src/index.ts";

const source = "garmin";
const timezone = "Australia/Brisbane";
const startedAt = "2026-06-23T20:00:00Z";
const endedAt = "2026-06-23T20:45:00Z";

const scalarValue = (value, unit) => ({ value, unit });

const validSet = {
  source,
  externalId: "activity-123:set-1",
  timezone,
  performedAt: "2026-06-23T20:12:30Z",
  dimensions: {
    load: scalarValue(100, "kilogram"),
    reps: scalarValue(5, "repetition")
  }
};

const validMetricReading = {
  source,
  externalId: "daily-2026-06-24:resting-hr",
  metricKey: "restingHeartRate",
  value: scalarValue(60, "beatsPerMinute"),
  at: {
    kind: "instant",
    at: "2026-06-24T06:30:00Z",
    timezone
  }
};

const validActivity = {
  source,
  externalId: "activity-123",
  startedAt,
  endedAt,
  timezone,
  activityType: "STRENGTH_TRAINING_CUSTOM_VENDOR_STRING",
  summary: {
    duration: scalarValue(2700, "second"),
    distance: scalarValue(0, "meter")
  },
  summaryMetrics: [
    {
      source,
      externalId: "activity-123:average-heart-rate",
      metricKey: "averageHeartRate",
      value: scalarValue(132, "beatsPerMinute"),
      at: {
        kind: "window",
        startedAt,
        endedAt,
        timezone
      }
    }
  ],
  sets: [validSet]
};

test("canonical Garmin-shaped activity and set payloads validate without reshaping", () => {
  const parsed = CanonicalActivitySchema.parse(validActivity);

  assert.equal(
    parsed.activityType,
    "STRENGTH_TRAINING_CUSTOM_VENDOR_STRING"
  );
  assert.equal(parsed.sets[0].performedAt, "2026-06-23T20:12:30Z");

  const withoutSets = CanonicalActivitySchema.parse({
    ...validActivity,
    sets: undefined
  });
  assert.equal(withoutSets.sets, undefined);
});

test("canonical monitoring series and metric readings validate dense imported observations", () => {
  const parsedSeries = CanonicalSeriesSchema.parse({
    source,
    externalId: "activity-123:heart-rate-series",
    type: "heartRate",
    anchor: {
      kind: "activity",
      source,
      externalId: "activity-123"
    },
    baseTime: startedAt,
    timezone,
    samples: [
      {
        offsetSeconds: 0,
        value: scalarValue(98, "beatsPerMinute")
      },
      {
        offsetSeconds: 15,
        value: scalarValue(102, "beatsPerMinute")
      }
    ]
  });

  assert.equal(parsedSeries.anchor.kind, "activity");

  const parsedReading = CanonicalMetricReadingSchema.parse(validMetricReading);
  assert.equal(parsedReading.metricKey, "restingHeartRate");
});

test("canonical timestamps must be UTC instants and carry explicit timezone context", () => {
  assert.equal(
    CanonicalActivitySchema.safeParse({
      ...validActivity,
      startedAt: "2026-06-24T06:00:00+10:00"
    }).success,
    false
  );
  assert.equal(
    CanonicalMetricReadingSchema.safeParse({
      ...validMetricReading,
      at: { kind: "instant", at: "2026-06-24T06:30:00Z" }
    }).success,
    false
  );
});

test("training dimensions stay structurally separate from Monitoring Data", () => {
  assert.equal(
    CanonicalSetSchema.safeParse({
      ...validSet,
      metricKey: "averageHeartRate"
    }).success,
    false
  );
  assert.equal(
    CanonicalMetricReadingSchema.safeParse({
      ...validMetricReading,
      dimensions: {
        reps: scalarValue(5, "repetition")
      }
    }).success,
    false
  );
  assert.equal(
    CanonicalSeriesSchema.safeParse({
      source,
      externalId: "activity-123:location-series",
      type: "location",
      anchor: {
        kind: "activity",
        source,
        externalId: "activity-123"
      },
      baseTime: startedAt,
      timezone,
      dimensions: {
        distance: scalarValue(100, "meter")
      },
      samples: [
        {
          offsetSeconds: 0,
          value: {
            latitude: scalarValue(-27.4689, "degree"),
            longitude: scalarValue(153.0235, "degree")
          }
        }
      ]
    }).success,
    false
  );
});

test("canonical shapes reject derived analytics and behavioral fields", () => {
  assert.equal(
    CanonicalActivitySchema.safeParse({
      ...validActivity,
      personalRecord: true
    }).success,
    false
  );
  assert.equal(
    CanonicalMetricReadingSchema.safeParse({
      ...validMetricReading,
      trendDelta: -2
    }).success,
    false
  );
  assert.equal(
    CanonicalSetSchema.safeParse({
      ...validSet,
      estimatedOneRepMax: scalarValue(116.7, "kilogram")
    }).success,
    false
  );
});

test("canonical schemas are emitted into the committed OpenAPI contract without drift", async () => {
  const committed = JSON.parse(
    await readFile(new URL("../openapi.json", import.meta.url), "utf8")
  );
  const generated = await createOpenApiDocument();
  const schemaNames = [
    "CanonicalActivity",
    "CanonicalSet",
    "CanonicalSeries",
    "CanonicalMetricReading"
  ];

  for (const schemaName of schemaNames) {
    assert.deepEqual(
      committed.components?.schemas?.[schemaName],
      generated.components?.schemas?.[schemaName],
      `${schemaName} must be regenerated from the Zod source`
    );
  }

  const canonicalPaths = Object.keys(generated.paths ?? {}).filter((path) =>
    path.toLowerCase().includes("canonical")
  );
  assert.deepEqual(canonicalPaths, ["/integrations/canonical-import"]);
});
