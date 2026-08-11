import { z } from "@hono/zod-openapi";

type OpenApiSchemaRegistry = {
  register<T extends z.ZodType>(refId: string, zodSchema: T): T;
};

export const CanonicalSourceSchema = z.string().min(1).openapi("CanonicalSource", {
  description:
    "Stable acquisition source identifier, such as garmin. Carries provenance from ingestion onward."
});

export const CanonicalExternalIdSchema = z
  .string()
  .min(1)
  .openapi("CanonicalExternalId", {
    description:
      "Stable source-provided id for idempotent import and last-import-wins replacement."
  });

export const CanonicalUtcInstantSchema = z
  .string()
  .datetime({ offset: false })
  .openapi("CanonicalUtcInstant", {
    description: "UTC instant encoded as ISO-8601 with a trailing Z.",
    format: "date-time"
  });

export const CanonicalTimezoneSchema = z
  .string()
  .min(1)
  .openapi("CanonicalTimezone", {
    description:
      "IANA timezone for the user's local context at the observed instant or window."
  });

export const CanonicalScalarValueSchema = z
  .object({
    value: z.number().finite().openapi({
      description: "Vendor-reported numeric value."
    }),
    unit: z.string().min(1).openapi({
      description: "Canonical unit for the value."
    })
  })
  .strict()
  .openapi("CanonicalScalarValue");

export const CanonicalStructuredValueSchema = z
  .record(z.string().min(1), CanonicalScalarValueSchema)
  .openapi("CanonicalStructuredValue", {
    description:
      "Structured metric value, such as latitude and longitude components for a location sample."
  });

export const CanonicalMetricValueSchema = z
  .union([CanonicalScalarValueSchema, CanonicalStructuredValueSchema])
  .openapi("CanonicalMetricValue", undefined, {
    unionPreferredType: "oneOf"
  });

const nonNegativeNumber = z.number().finite().min(0);

const loadValueSchema = z
  .object({
    value: nonNegativeNumber,
    unit: z.enum(["kilogram", "pound"])
  })
  .strict();

const repsValueSchema = z
  .object({
    value: z.number().int().min(0),
    unit: z.literal("repetition")
  })
  .strict();

const durationValueSchema = z
  .object({
    value: nonNegativeNumber,
    unit: z.literal("second")
  })
  .strict();

const distanceValueSchema = z
  .object({
    value: nonNegativeNumber,
    unit: z.enum(["meter", "kilometer", "mile"])
  })
  .strict();

export const CanonicalTrainingDimensionsSchema = z
  .object({
    load: loadValueSchema.optional().openapi({
      description: "Training load as observed by the source."
    }),
    reps: repsValueSchema.optional().openapi({
      description: "Training repetition count as observed by the source."
    }),
    duration: durationValueSchema.optional().openapi({
      description: "Training duration as observed by the source."
    }),
    distance: distanceValueSchema.optional().openapi({
      description: "Training distance as observed by the source."
    })
  })
  .strict()
  .openapi("CanonicalTrainingDimensions", {
    description:
      "Set training dimensions only. Monitoring Data such as heart rate, GPS, cadence, and power never appears here."
  });

export const CanonicalSetSchema = z
  .object({
    source: CanonicalSourceSchema,
    externalId: CanonicalExternalIdSchema,
    timezone: CanonicalTimezoneSchema,
    performedAt: CanonicalUtcInstantSchema.optional().openapi({
      description:
        "Optional observed set timestamp in UTC. Position/order is still supplied by materialization, never inferred from time."
    }),
    dimensions: CanonicalTrainingDimensionsSchema.default({}).openapi({
      description:
        "Training dimensions available from the source. The set may be completion-only."
    })
  })
  .strict()
  .openapi("CanonicalSet", {
    description:
      "Optional canonical set structure carried by sources such as FIT files. It is training data only, not Monitoring Data."
  });

export const CanonicalTimeAnchorSchema = z
  .discriminatedUnion("kind", [
    z
      .object({
        kind: z.literal("instant"),
        at: CanonicalUtcInstantSchema,
        timezone: CanonicalTimezoneSchema
      })
      .strict(),
    z
      .object({
        kind: z.literal("window"),
        startedAt: CanonicalUtcInstantSchema,
        endedAt: CanonicalUtcInstantSchema,
        timezone: CanonicalTimezoneSchema
      })
      .strict()
  ])
  .openapi("CanonicalTimeAnchor", undefined, {
    unionPreferredType: "oneOf"
  });

export const CanonicalSummaryMetricSchema = z
  .object({
    source: CanonicalSourceSchema,
    externalId: CanonicalExternalIdSchema,
    metricKey: z.string().min(1).openapi({
      description:
        "Canonical Metric key for the vendor-reported summary, such as averageHeartRate or activeKilocalories."
    }),
    value: CanonicalMetricValueSchema,
    at: CanonicalTimeAnchorSchema
  })
  .strict()
  .openapi("CanonicalSummaryMetric", {
    description:
      "Vendor-reported activity summary metric that will become a provenance-stamped Metric Reading."
  });

export const CanonicalActivitySummarySchema = z
  .object({
    distance: distanceValueSchema.optional().openapi({
      description: "Vendor-reported activity distance."
    }),
    duration: durationValueSchema.optional().openapi({
      description: "Vendor-reported activity duration."
    })
  })
  .strict()
  .openapi("CanonicalActivitySummary", {
    description:
      "Activity summary dimensions used for materialization. Monitoring summaries live in summaryMetrics."
  });

export const CanonicalActivitySchema = z
  .object({
    source: CanonicalSourceSchema,
    externalId: CanonicalExternalIdSchema,
    startedAt: CanonicalUtcInstantSchema.openapi({
      description: "Activity start instant in UTC."
    }),
    endedAt: CanonicalUtcInstantSchema.openapi({
      description: "Activity end instant in UTC."
    }),
    timezone: CanonicalTimezoneSchema,
    activityType: z.string().min(1).openapi({
      description:
        "Raw vendor activity type string preserved verbatim for mapping and later promotion."
    }),
    summary: CanonicalActivitySummarySchema.default({}),
    summaryMetrics: z.array(CanonicalSummaryMetricSchema).default([]).openapi({
      description:
        "Vendor-reported Monitoring Summary metrics, separate from Set training dimensions."
    }),
    sets: z.array(CanonicalSetSchema).optional().openapi({
      description:
        "Optional set structure when the source carries it. Omitted for activities without sets."
    })
  })
  .strict()
  .openapi("CanonicalActivity", {
    description:
      "Vendor-neutral activity contract emitted by Acquisition adapters and consumed by shared Ingestion."
  });

export const CanonicalSeriesTypeSchema = z
  .enum([
    "heartRate",
    "location",
    "cadence",
    "power",
    "speed",
    "elevation",
    "temperature",
    "steps"
  ])
  .openapi("CanonicalSeriesType");

export const CanonicalImportConsentDataClassSchema = z
  .enum(["activities", "heartRate", "gps", "sleepWellness", "bodyComposition"])
  .openapi("CanonicalImportConsentDataClass", {
    description:
      "Import data classes that are controlled by persisted per-Integration consent. Every class defaults off, with gps independently opt-in."
  });

export const CanonicalImportDataClassSchema = z
  .enum([
    "activities",
    "heartRate",
    "gps",
    "sleepWellness",
    "bodyComposition"
  ])
  .openapi("CanonicalImportDataClass", {
    description:
      "Canonical import data class used by ingestion consent filtering. Persisted per-Integration consent is authoritative for every class."
  });

export const CANONICAL_IMPORT_CONSENT_DATA_CLASSES =
  CanonicalImportConsentDataClassSchema.options;

export const CanonicalSeriesAnchorSchema = z
  .discriminatedUnion("kind", [
    z
      .object({
        kind: z.literal("activity"),
        source: CanonicalSourceSchema,
        externalId: CanonicalExternalIdSchema
      })
      .strict(),
    z
      .object({
        kind: z.literal("timeWindow"),
        startedAt: CanonicalUtcInstantSchema,
        endedAt: CanonicalUtcInstantSchema,
        timezone: CanonicalTimezoneSchema
      })
      .strict()
  ])
  .openapi("CanonicalSeriesAnchor", undefined, {
    unionPreferredType: "oneOf"
  });

export const CanonicalSeriesSampleSchema = z
  .object({
    offsetSeconds: z.number().finite().min(0).openapi({
      description:
        "Seconds after baseTime. Offsets make dense samples delta-encodable."
    }),
    value: CanonicalMetricValueSchema
  })
  .strict()
  .openapi("CanonicalSeriesSample");

export const CanonicalSeriesSchema = z
  .object({
    source: CanonicalSourceSchema,
    externalId: CanonicalExternalIdSchema,
    type: CanonicalSeriesTypeSchema,
    anchor: CanonicalSeriesAnchorSchema,
    baseTime: CanonicalUtcInstantSchema.openapi({
      description: "UTC instant from which sample offsets are measured."
    }),
    timezone: CanonicalTimezoneSchema,
    samples: z.array(CanonicalSeriesSampleSchema).min(1)
  })
  .strict()
  .openapi("CanonicalSeries", {
    description:
      "Dense Monitoring Data series. Stored out-of-band later, never as Set fields."
  });

export const CanonicalMetricReadingSchema = z
  .object({
    source: CanonicalSourceSchema,
    externalId: CanonicalExternalIdSchema,
    metricKey: z.string().min(1).openapi({
      description:
        "Canonical Metric key, such as restingHeartRate, sleepDuration, bodyWeight, or activeKilocalories."
    }),
    value: CanonicalMetricValueSchema,
    at: CanonicalTimeAnchorSchema
  })
  .strict()
  .openapi("CanonicalMetricReading", {
    description:
      "Time-anchored Metric Reading imported from a tracker or Import Adapter."
  });

const canonicalImportOpenApiSchemas = [
  ["CanonicalSource", CanonicalSourceSchema],
  ["CanonicalExternalId", CanonicalExternalIdSchema],
  ["CanonicalUtcInstant", CanonicalUtcInstantSchema],
  ["CanonicalTimezone", CanonicalTimezoneSchema],
  ["CanonicalScalarValue", CanonicalScalarValueSchema],
  ["CanonicalStructuredValue", CanonicalStructuredValueSchema],
  ["CanonicalMetricValue", CanonicalMetricValueSchema],
  ["CanonicalTrainingDimensions", CanonicalTrainingDimensionsSchema],
  ["CanonicalSet", CanonicalSetSchema],
  ["CanonicalTimeAnchor", CanonicalTimeAnchorSchema],
  ["CanonicalSummaryMetric", CanonicalSummaryMetricSchema],
  ["CanonicalActivitySummary", CanonicalActivitySummarySchema],
  ["CanonicalActivity", CanonicalActivitySchema],
  ["CanonicalSeriesType", CanonicalSeriesTypeSchema],
  ["CanonicalImportConsentDataClass", CanonicalImportConsentDataClassSchema],
  ["CanonicalImportDataClass", CanonicalImportDataClassSchema],
  ["CanonicalSeriesAnchor", CanonicalSeriesAnchorSchema],
  ["CanonicalSeriesSample", CanonicalSeriesSampleSchema],
  ["CanonicalSeries", CanonicalSeriesSchema],
  ["CanonicalMetricReading", CanonicalMetricReadingSchema]
] as const;

export function registerCanonicalImportOpenApiSchemas(
  registry: OpenApiSchemaRegistry
) {
  for (const [name, schema] of canonicalImportOpenApiSchemas) {
    registry.register(name, schema);
  }
}

export type CanonicalActivity = z.infer<typeof CanonicalActivitySchema>;
export type CanonicalSet = z.infer<typeof CanonicalSetSchema>;
export type CanonicalSeries = z.infer<typeof CanonicalSeriesSchema>;
export type CanonicalMetricReading = z.infer<
  typeof CanonicalMetricReadingSchema
>;
export type CanonicalImportConsentDataClass = z.infer<
  typeof CanonicalImportConsentDataClassSchema
>;
export type CanonicalImportDataClass = z.infer<
  typeof CanonicalImportDataClassSchema
>;
