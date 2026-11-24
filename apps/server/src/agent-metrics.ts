import { createRoute, z } from "@hono/zod-openapi";
import { and, asc, eq, inArray, isNotNull, isNull, max } from "drizzle-orm";

import {
  agentBatchRequestFingerprint,
  claimAgentBatchReceipt
} from "./agent-batch-receipt.js";
import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import { validateLabResult } from "./agent-validation.js";
import {
  labTestByKey,
  type LabTestEntry
} from "./data/lab-test-catalogue.generated.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import {
  collapseLabResults,
  decodeLab,
  parseEntered,
  type LabReadingRef
} from "./lab-results.js";
import {
  findLabMetric,
  labMetricIds,
  lockMetricIdentity,
  stableMetricId
} from "./metric-identity.js";
import {
  normalizeMetricReading,
  type MetricReadingNormalizationInput
} from "./metric-reading-normalization.js";
import {
  normalizeMetricLookupKey,
  PRN_METRIC_SCHEMAS,
  owlMetricSchemaForImportKey,
  type PerenniaMetricSchema
} from "./metric-catalog.js";
import { metricTrend, type TrendInput } from "./analytics/metric-trend.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";
import { METRICS_SYNC_ENTITY, METRIC_READINGS_SYNC_ENTITY } from "./sync.js";

export const AGENT_METRIC_DEFAULT_PAGE_LIMIT = 50;
export const AGENT_METRIC_MAX_PAGE_LIMIT = 200;
export const AGENT_METRIC_BATCH_WRITE_MAX_METRICS = 50;
export const AGENT_METRIC_BATCH_WRITE_MAX_READINGS = 200;
export const AGENT_METRIC_BATCH_ENTITY = "agent_metric_batches";
export const METRICS_AGENT_ENTITY = METRICS_SYNC_ENTITY;

const AGENT_METRIC_LIST_FIELDS = [
  "id",
  "name",
  "canonicalKey",
  "aliases",
  "dataClass",
  "unit",
  "valueShape",
  "metricGroup",
  "goalType",
  "goalTargetValue",
  "enabled",
  "pinned",
  "sortOrder",
  "updatedAt",
  "deletedAt"
] as const;
const AGENT_METRIC_READING_FIELDS = [
  "id",
  "metricId",
  "externalActivityId",
  "valueShape",
  "unit",
  "valueJson",
  "scalarValue",
  "scalarEntered",
  "atTime",
  "windowStartedAt",
  "windowEndedAt",
  "provenance",
  "source",
  "externalId",
  "comment",
  "warnings",
  "updatedAt",
  "deletedAt"
] as const;

const ISO8601StringSchema = z.string().min(1).openapi({
  description: "ISO-8601 timestamp."
});

const MetricValueShapeSchema = z
  .enum(["scalar", "structured", "series"])
  .openapi("AgentMetricValueShape");

export const AgentMetricSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1),
    canonicalKey: z.string().min(1).nullable(),
    aliases: z.array(z.string().min(1)),
    dataClass: z.string().min(1).nullable(),
    unit: z.string().min(1),
    valueShape: MetricValueShapeSchema,
    metricGroup: z.string().min(1),
    goalType: z.string().min(1).nullable(),
    goalTargetValue: z.number().nullable(),
    enabled: z.boolean(),
    pinned: z.boolean(),
    sortOrder: z.number().int(),
    updatedAt: ISO8601StringSchema,
    deletedAt: ISO8601StringSchema.nullable()
  })
  .openapi("AgentMetric");

const AgentMetricListFieldSchema = z
  .enum(AGENT_METRIC_LIST_FIELDS)
  .openapi("AgentMetricListField");

const AgentMetricListItemSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1),
    canonicalKey: z.string().min(1).nullable().optional(),
    aliases: z.array(z.string().min(1)).optional(),
    dataClass: z.string().min(1).nullable().optional(),
    unit: z.string().min(1).optional(),
    valueShape: MetricValueShapeSchema.optional(),
    metricGroup: z.string().min(1).optional(),
    goalType: z.string().min(1).nullable().optional(),
    goalTargetValue: z.number().nullable().optional(),
    enabled: z.boolean().optional(),
    pinned: z.boolean().optional(),
    sortOrder: z.number().int().optional(),
    updatedAt: ISO8601StringSchema.optional(),
    deletedAt: ISO8601StringSchema.nullable().optional()
  })
  .openapi("AgentMetricListItem");

export const AgentMetricReadingSchema = z
  .object({
    id: z.string().min(1),
    metricId: z.string().min(1),
    externalActivityId: z.string().min(1).nullable(),
    valueShape: MetricValueShapeSchema,
    unit: z.string().min(1),
    valueJson: z.record(z.string(), z.unknown()),
    scalarValue: z.number().nullable(),
    scalarEntered: z.string().nullable(),
    atTime: ISO8601StringSchema.nullable(),
    windowStartedAt: ISO8601StringSchema.nullable(),
    windowEndedAt: ISO8601StringSchema.nullable(),
    provenance: z.string().min(1),
    source: z.string().min(1),
    externalId: z.string().min(1).nullable(),
    comment: z.string().nullable(),
    warnings: z.array(z.string().min(1)).default([]),
    updatedAt: ISO8601StringSchema,
    deletedAt: ISO8601StringSchema.nullable()
  })
  .openapi("AgentMetricReading");

const AgentMetricReadingFieldSchema = z
  .enum(AGENT_METRIC_READING_FIELDS)
  .openapi("AgentMetricReadingField");

const AgentMetricReadingListItemSchema = z
  .object({
    id: z.string().min(1),
    metricId: z.string().min(1),
    externalActivityId: z.string().min(1).nullable().optional(),
    valueShape: MetricValueShapeSchema.optional(),
    unit: z.string().min(1).optional(),
    valueJson: z.record(z.string(), z.unknown()).optional(),
    scalarValue: z.number().nullable().optional(),
    scalarEntered: z.string().nullable().optional(),
    atTime: ISO8601StringSchema.nullable().optional(),
    windowStartedAt: ISO8601StringSchema.nullable().optional(),
    windowEndedAt: ISO8601StringSchema.nullable().optional(),
    provenance: z.string().min(1).optional(),
    source: z.string().min(1).optional(),
    externalId: z.string().min(1).nullable().optional(),
    comment: z.string().nullable().optional(),
    warnings: z.array(z.string().min(1)).optional(),
    updatedAt: ISO8601StringSchema.optional(),
    deletedAt: ISO8601StringSchema.nullable().optional(),
    trendValue: z.number().optional().openapi({
      description:
        "The Metric's Trend at this Reading: a time-weighted moving average over all of the Metric's live Readings with a scalar value, not only this page. Present only when includeTrend is true, on live Readings with a scalar value. Not one of the selectable fields; it is added after the fields projection. Readings are not converted between units."
    })
  })
  .openapi("AgentMetricReadingListItem");

const metricListFieldSet = new Set<string>(AGENT_METRIC_LIST_FIELDS);
const metricReadingFieldSet = new Set<string>(AGENT_METRIC_READING_FIELDS);

export const AgentMetricListQuerySchema = z
  .object({
    search: z.string().trim().min(1).optional().openapi({
      param: { name: "search", in: "query" },
      description:
        "Optional case-insensitive Metric name, canonical key, alias, unit, Metric Group, or data class filter."
    }),
    metricKey: z.string().trim().min(1).optional().openapi({
      param: { name: "metricKey", in: "query" },
      description:
        "Optional canonical Metric key or catalog alias filter, for example hrv, restingHeartRate, sleepScore, or bodyWeight."
    }),
    metricGroup: z.string().trim().min(1).optional().openapi({
      param: { name: "metricGroup", in: "query" },
      description: "Optional Metric Group filter."
    }),
    enabledOnly: z.coerce.boolean().default(false).openapi({
      param: { name: "enabledOnly", in: "query" },
      description: "When true, archived and disabled Metrics are excluded."
    }),
    includeArchived: z.coerce.boolean().default(false).openapi({
      param: { name: "includeArchived", in: "query" },
      description: "When true, archived Metrics are included."
    }),
    limit: z.coerce
      .number()
      .int()
      .min(1)
      .max(AGENT_METRIC_MAX_PAGE_LIMIT)
      .default(AGENT_METRIC_DEFAULT_PAGE_LIMIT)
      .openapi({
        param: { name: "limit", in: "query" },
        description: "Maximum Metric rows to return."
      }),
    cursor: z.string().trim().min(1).optional().openapi({
      param: { name: "cursor", in: "query" },
      description: "Opaque cursor returned by the previous page."
    }),
    fields: z
      .string()
      .trim()
      .min(1)
      .optional()
      .refine(
        (value) =>
          value === undefined ||
          value
            .split(",")
            .map((field) => field.trim())
            .every((field) => metricListFieldSet.has(field)),
        "fields must be a comma-separated list of known Metric fields"
      )
      .openapi({
        param: { name: "fields", in: "query" },
        description:
          "Comma-separated list of Metric fields to return. id and name are always returned; omitting fields returns the full Metric row."
      })
  })
  .openapi("AgentMetricListQuery");

export const AgentMetricReadingsQuerySchema = z
  .object({
    metricId: z.string().trim().min(1).optional().openapi({
      param: { name: "metricId", in: "query" },
      description: "Optional Metric id filter."
    }),
    metricKey: z.string().trim().min(1).optional().openapi({
      param: { name: "metricKey", in: "query" },
      description:
        "Optional canonical Metric key or catalog alias filter, for example hrv, restingHeartRate, sleepScore, or bodyWeight."
    }),
    from: z.string().trim().min(1).optional().openapi({
      param: { name: "from", in: "query" },
      description: "Optional inclusive ISO-8601 lower bound."
    }),
    to: z.string().trim().min(1).optional().openapi({
      param: { name: "to", in: "query" },
      description: "Optional inclusive ISO-8601 upper bound."
    }),
    provenance: z.string().trim().min(1).optional().openapi({
      param: { name: "provenance", in: "query" },
      description: "Optional Provenance filter."
    }),
    source: z.string().trim().min(1).optional().openapi({
      param: { name: "source", in: "query" },
      description: "Optional source filter."
    }),
    includeArchived: z.coerce.boolean().default(false).openapi({
      param: { name: "includeArchived", in: "query" },
      description: "When true, archived Readings are included."
    }),
    // Not z.coerce.boolean(): it reads "false" as true (D9 in
    // docs/designs/progress-overview.md).
    includeTrend: z
      .enum(["true", "false"])
      .default("false")
      .openapi({
        param: { name: "includeTrend", in: "query" },
        description:
          "When true, each returned live Reading with a scalar value carries trendValue, the Metric's Trend computed over all of that Metric's live Readings."
      }),
    limit: z.coerce
      .number()
      .int()
      .min(1)
      .max(AGENT_METRIC_MAX_PAGE_LIMIT)
      .default(AGENT_METRIC_DEFAULT_PAGE_LIMIT)
      .openapi({
        param: { name: "limit", in: "query" },
        description: "Maximum Reading rows to return."
      }),
    cursor: z.string().trim().min(1).optional().openapi({
      param: { name: "cursor", in: "query" },
      description: "Opaque cursor returned by the previous page."
    }),
    fields: z
      .string()
      .trim()
      .min(1)
      .optional()
      .refine(
        (value) =>
          value === undefined ||
          value
            .split(",")
            .map((field) => field.trim())
            .every((field) => metricReadingFieldSet.has(field)),
        "fields must be a comma-separated list of known Metric Reading fields"
      )
      .openapi({
        param: { name: "fields", in: "query" },
        description:
          "Comma-separated list of Metric Reading fields to return. id and metricId are always returned; omitting fields returns the full Reading row."
      })
  })
  .openapi("AgentMetricReadingsQuery");

export const AgentMetricListResponseSchema = z
  .object({
    metrics: z.array(AgentMetricListItemSchema),
    fields: z.array(AgentMetricListFieldSchema),
    limit: z.number().int().min(1).max(AGENT_METRIC_MAX_PAGE_LIMIT),
    nextCursor: z.string().min(1).nullable(),
    totalMatched: z.number().int().min(0)
  })
  .openapi("AgentMetricListResponse");

export const AgentMetricReadingsResponseSchema = z
  .object({
    readings: z.array(AgentMetricReadingListItemSchema),
    fields: z.array(AgentMetricReadingFieldSchema),
    limit: z.number().int().min(1).max(AGENT_METRIC_MAX_PAGE_LIMIT),
    nextCursor: z.string().min(1).nullable(),
    totalMatched: z.number().int().min(0)
  })
  .openapi("AgentMetricReadingsResponse");

const AgentMetricBatchWriteMetricSchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "Client-supplied UUIDv7 Metric id."
    }),
    name: z.string().trim().min(1),
    unit: z.string().trim().min(1),
    valueShape: MetricValueShapeSchema,
    metricGroup: z.string().trim().min(1),
    goalType: z.string().trim().min(1).nullable().default(null),
    goalTargetValue: z.number().nullable().default(null),
    enabled: z.boolean().default(true),
    pinned: z.boolean().default(false),
    sortOrder: z.number().int().default(0),
    updatedAt: ISO8601StringSchema.optional(),
    deletedAt: ISO8601StringSchema.nullable().default(null),
    // Declared only so it is not stripped: without it zod would drop the
    // field and an Agent that sent it would silently get a custom Metric.
    labTestKey: z.unknown().optional().openapi({
      description:
        "Not accepted: Lab Metrics can't be upserted; sending it rejects the batch with lab_metric_upsert_not_allowed."
    })
  })
  .openapi("AgentMetricBatchWriteMetric");

/**
 * A field a lab rule judges for itself (docs/designs/lab-results.md,
 * "Agent surface"): any JSON scalar passes the schema, so a malformed value
 * reaches `validateLabResult` and gets its own code (`lab_collected_invalid`,
 * `lab_report_status_invalid`, `lab_fasting_invalid`) instead of a generic
 * 400.
 */
const AgentLabRuleCheckedFieldSchema = z.union([
  z.string(),
  z.number(),
  z.boolean(),
  z.null()
]);

/**
 * The `lab` object of a Lab Result as an Agent sends it. Permissive on
 * purpose (see AgentLabRuleCheckedFieldSchema), with two exceptions: the text
 * fields are `string | null`, because no lab rule judges a text field's type
 * and the normaliser would write a non-string as null without a word, and
 * `limit` is accepted only to be overwritten. Unknown keys pass the schema
 * and the normaliser drops them.
 */
const AgentMetricReadingLabSchema = z
  .object({
    collected: AgentLabRuleCheckedFieldSchema.optional().openapi({
      description:
        "The collection date as printed, local, no offset: YYYY-MM-DD or YYYY-MM-DDTHH:mm. Required for a lab result."
    }),
    reportStatus: AgentLabRuleCheckedFieldSchema.optional().openapi({
      description: "final (the default) or interim."
    }),
    fasting: AgentLabRuleCheckedFieldSchema.optional().openapi({
      description: "true when the sample was taken fasting; otherwise null or absent."
    }),
    printedRange: z.string().nullable().optional().openapi({
      description: "The reference range as printed on the report, at most 120 characters."
    }),
    printedFlag: z.string().nullable().optional().openapi({
      description: "The flag as printed (for example H, L, +), at most 8 characters."
    }),
    labName: z.string().nullable().optional().openapi({
      description: "The lab's name, never the patient's, at most 80 characters."
    }),
    limit: z.unknown().optional().openapi({
      description:
        "Output only: the server derives it from entered (\"< 1\") and overwrites any value sent."
    })
  })
  .passthrough()
  .openapi({
    description:
      "A Lab Result's lab fields, accepted only on a reading written by labTestKey. Each malformed field is reported with its own lab_* rule code. lab.limit is derived from entered; unknown keys are dropped."
  });

const AgentMetricReadingScalarValueSchema = z
  .object({
    shape: z.literal("scalar"),
    entered: z.string().trim().min(1),
    unit: z.string().trim().min(1).optional(),
    lab: AgentMetricReadingLabSchema.nullable().optional()
  })
  .openapi("AgentMetricReadingScalarValue");

const AgentMetricReadingStructuredValueSchema = z
  .object({
    shape: z.literal("structured"),
    fields: z.record(
      z.string().min(1),
      z.object({
        entered: z.string().trim().min(1),
        unit: z.string().trim().min(1).optional()
      })
    )
  })
  .openapi("AgentMetricReadingStructuredValue");

const AgentMetricReadingSeriesValueSchema = z
  .object({
    shape: z.literal("series"),
    samples: z.array(
      z.object({
        offsetSeconds: z.number(),
        entered: z.string().trim().min(1),
        unit: z.string().trim().min(1).optional()
      })
    )
  })
  .openapi("AgentMetricReadingSeriesValue");

const AgentMetricReadingValueSchema = z
  .discriminatedUnion("shape", [
    AgentMetricReadingScalarValueSchema,
    AgentMetricReadingStructuredValueSchema,
    AgentMetricReadingSeriesValueSchema
  ])
  .openapi("AgentMetricReadingValue");

const AgentMetricReadingTimeAnchorSchema = z
  .object({
    atTime: ISO8601StringSchema.optional(),
    windowStartedAt: ISO8601StringSchema.optional(),
    windowEndedAt: ISO8601StringSchema.optional(),
    localDateTime: z.string().trim().min(1).optional(),
    timezoneOffsetMinutes: z.number().int().optional()
  })
  .openapi("AgentMetricReadingTimeAnchor");

const AgentMetricBatchWriteReadingSchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "Client-supplied UUIDv7 Metric Reading id."
    }),
    metricId: z.string().min(1).optional().openapi({
      description:
        "The Metric this Reading belongs to. Give exactly one of metricId and labTestKey (lab_target_ambiguous otherwise); a Lab Metric's id is rejected (lab_metric_id_not_allowed)."
    }),
    labTestKey: z.string().min(1).optional().openapi({
      description:
        "Write a lab result by Lab Test key (list keys with agent_list_lab_tests) instead of metricId. The server finds or creates the user's Lab Metric for the key."
    }),
    value: AgentMetricReadingValueSchema,
    timeAnchor: AgentMetricReadingTimeAnchorSchema,
    provenance: z.string().trim().min(1).default("agent"),
    source: z.string().trim().min(1).default("agent"),
    externalId: z.string().trim().min(1).nullable().default(null),
    externalActivityId: z.string().trim().min(1).nullable().default(null),
    comment: z.string().nullable().default(null),
    updatedAt: ISO8601StringSchema.optional(),
    deletedAt: ISO8601StringSchema.nullable().default(null)
  })
  .openapi("AgentMetricBatchWriteReading");

export const AgentMetricBatchWriteRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200).openapi({
      description:
        "Stable key for this agent request. Replays with the same key do not append another Activity Log batch."
    }),
    metrics: z
      .array(AgentMetricBatchWriteMetricSchema)
      .max(AGENT_METRIC_BATCH_WRITE_MAX_METRICS)
      .default([])
      .openapi({
        description:
          "Metric definitions to upsert before readings in this same batch."
      }),
    readings: z
      .array(AgentMetricBatchWriteReadingSchema)
      .max(AGENT_METRIC_BATCH_WRITE_MAX_READINGS)
      .default([])
      .openapi({
        description:
          "Metric Readings to normalize and apply atomically with the Metric definitions."
      })
  })
  .refine((request) => request.metrics.length + request.readings.length > 0, {
    message: "A Metric batch must include at least one Metric or Reading."
  })
  .openapi("AgentMetricBatchWriteRequest");

export const AgentMetricBatchWriteIssueSchema = z
  .object({
    field: z.string().min(1),
    rule: z.string().min(1),
    message: z.string().min(1),
    itemIndex: z.number().int().min(0),
    metricId: z.string().min(1).nullable(),
    readingId: z.string().min(1).nullable(),
    limit: z.union([z.string(), z.number(), z.null()])
  })
  .openapi("AgentMetricBatchWriteIssue");

const AgentMetricBatchWriteMetricResultSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1),
    valueShape: MetricValueShapeSchema,
    unit: z.string().min(1),
    metricGroup: z.string().min(1),
    applied: z.boolean(),
    outcome: z.enum(["applied", "superseded", "duplicate"])
  })
  .openapi("AgentMetricBatchWriteMetricResult");

const AgentMetricBatchWriteReadingResultSchema = z
  .object({
    id: z.string().min(1),
    metricId: z.string().min(1),
    valueShape: MetricValueShapeSchema,
    unit: z.string().min(1),
    warnings: z.array(z.string().min(1)),
    applied: z.boolean(),
    outcome: z.enum(["applied", "superseded", "duplicate"])
  })
  .openapi("AgentMetricBatchWriteReadingResult");

export const AgentMetricBatchWriteResponseSchema = z
  .object({
    accepted: z.literal(true),
    duplicate: z.boolean(),
    idempotencyKey: z.string().min(1),
    batchId: z.string().min(1),
    serverClock: z.string().min(1),
    metrics: z.array(AgentMetricBatchWriteMetricResultSchema),
    readings: z.array(AgentMetricBatchWriteReadingResultSchema)
  })
  .openapi("AgentMetricBatchWriteResponse");

export const AgentMetricBatchWriteErrorResponseSchema = z
  .object({
    code: z.literal("agent_metric_batch_write_failed"),
    message: z.string().min(1),
    errors: z.array(AgentMetricBatchWriteIssueSchema),
    warnings: z.array(AgentMetricBatchWriteIssueSchema)
  })
  .openapi("AgentMetricBatchWriteErrorResponse");

export const AgentMetricUnavailableResponseSchema = z
  .object({
    code: z.literal("agent_metric_unavailable"),
    message: z.string().min(1)
  })
  .openapi("AgentMetricUnavailableResponse");

export const agentMetricListRoute = createRoute({
  method: "get",
  path: "/agent/metrics",
  operationId: "listAgentMetrics",
  tags: ["Agent Reads"],
  summary: "List the caller's Metrics.",
  description:
    "Returns a bounded Metric catalogue page for code-mode agents. Metrics describe how Metric Readings should be normalized; derived analytics are still computed on read. A Lab Metric's canonicalKey is its Lab Test key, and a Lab Test key as metricKey matches only Lab Metrics with that key. The list may hold two Metrics for one Lab Test (created on two offline devices); readings join them by key.",
  security: [{ bearerAuth: [] }],
  request: {
    query: AgentMetricListQuerySchema
  },
  responses: {
    200: {
      description: "A bounded page of Metrics.",
      content: {
        "application/json": {
          schema: AgentMetricListResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid agent API key.",
      content: {
        "application/json": {
          schema: AgentUnauthorizedResponseSchema
        }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key or Metric storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentMetricUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export const agentMetricReadingsRoute = createRoute({
  method: "get",
  path: "/agent/metrics/readings",
  operationId: "listAgentMetricReadings",
  tags: ["Agent Reads"],
  summary: "List a bounded page of Metric Readings.",
  description:
    "Returns normalized Metric Readings for code-mode agents with server-side bounds and filters. Raw Monitoring Series blobs are intentionally out of scope. A Lab Metric filter (its metricId, or a Lab Test key as metricKey) returns the collapsed results of every Metric with that key: one per collection, a final beating an interim, each keeping its own metricId; the cursor and totalMatched count the collapsed list. Archived lab rows are never returned, even with includeArchived. Lab Metrics get no trendValue.",
  security: [{ bearerAuth: [] }],
  request: {
    query: AgentMetricReadingsQuerySchema
  },
  responses: {
    200: {
      description: "A bounded page of Metric Readings.",
      content: {
        "application/json": {
          schema: AgentMetricReadingsResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid agent API key.",
      content: {
        "application/json": {
          schema: AgentUnauthorizedResponseSchema
        }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key or Metric storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentMetricUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export const agentMetricBatchWriteRoute = createRoute({
  method: "post",
  path: "/agent/metrics/batch-write",
  operationId: "batchWriteAgentMetrics",
  tags: ["Agent Writes"],
  summary: "Batch-write Metrics and Metric Readings as one Activity Log batch.",
  description:
    "Authenticated agent write path for Metric definitions and Readings. Readings are normalized with the same Metric normalization module used by imported data, then written atomically with one Activity Log batch and a best-effort sync nudge. Derived metrics, analytics, and repair recalculations are not stored. Lab results: write each by labTestKey (list keys with agent_list_lab_tests), never by metricId, with value.lab.collected and a matching timeAnchor (localDateTime = collected expanded, a date as T12:00:00 and a time with :00 seconds, plus timezoneOffsetMinutes). Use only a listed unit or unit alias, and send a limit as entered \"< 1\". The server sets updatedAt, provenance, source and lab.limit. A stored Lab Result cannot be overwritten or archived: to correct one, write a new final result for the same collection.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: AgentMetricBatchWriteRequestSchema
        }
      }
    }
  },
  responses: {
    200: {
      description:
        "The batch was accepted, or recognized as an idempotent replay.",
      content: {
        "application/json": {
          schema: AgentMetricBatchWriteResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid agent API key.",
      content: {
        "application/json": {
          schema: AgentUnauthorizedResponseSchema
        }
      }
    },
    422: {
      description:
        "One or more Metrics or Readings failed hard validation; no rows were written.",
      content: {
        "application/json": {
          schema: AgentMetricBatchWriteErrorResponseSchema
        }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key or Metric storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentMetricUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export type AgentMetricListQuery = z.infer<typeof AgentMetricListQuerySchema>;
export type AgentMetricReadingsQuery = z.infer<
  typeof AgentMetricReadingsQuerySchema
>;
export type AgentMetricBatchWriteRequest = z.infer<
  typeof AgentMetricBatchWriteRequestSchema
>;
export type AgentMetricBatchWriteIssue = z.infer<
  typeof AgentMetricBatchWriteIssueSchema
>;
export type AgentMetricBatchWriteResponse = z.infer<
  typeof AgentMetricBatchWriteResponseSchema
>;
export type AgentMetricStore = {
  listMetrics(input: {
    userId: string;
    query: AgentMetricListQuery;
  }): Promise<z.infer<typeof AgentMetricListResponseSchema>>;
  listMetricReadings(input: {
    userId: string;
    query: AgentMetricReadingsQuery;
  }): Promise<z.infer<typeof AgentMetricReadingsResponseSchema>>;
  writeMetricBatch(input: {
    userId: string;
    batchId: string;
    correlationId?: string;
    deviceId: string;
    request: AgentMetricBatchWriteRequest;
  }): Promise<
    | {
        accepted: true;
        duplicate: boolean;
        serverClock: string;
        activityLogEntries: number;
        applied: { id: string; updatedAt: string; deviceId: string }[];
        metrics: z.infer<typeof AgentMetricBatchWriteMetricResultSchema>[];
        readings: z.infer<typeof AgentMetricBatchWriteReadingResultSchema>[];
      }
    | {
        accepted: false;
        errors: AgentMetricBatchWriteIssue[];
        warnings: AgentMetricBatchWriteIssue[];
      }
  >;
};

type MutationDatabase = Pick<ServerDatabase, "select" | "insert" | "update">;
type MetricRow = typeof schema.metrics.$inferSelect;
type MetricReadingRow = typeof schema.metricReadings.$inferSelect;

type AgentMetricBatchWriteReading = z.infer<
  typeof AgentMetricBatchWriteReadingSchema
>;

type PreparedMetric = {
  id: string;
  updatedAt: Date;
  deletedAt: Date | null;
  /**
   * True for a Lab Metric the batch creates: its insert is ON CONFLICT DO
   * NOTHING on id (docs/designs/lab-results.md, "Finding the Lab Metric for
   * a Lab Test").
   */
  insertOnConflictDoNothing: boolean;
  values: typeof schema.metrics.$inferInsert;
  afterImage: Record<string, unknown>;
  result: z.infer<typeof AgentMetricBatchWriteMetricResultSchema>;
};

type PreparedReading = {
  id: string;
  updatedAt: Date;
  deletedAt: Date | null;
  values: typeof schema.metricReadings.$inferInsert;
  afterImage: Record<string, unknown>;
  result: z.infer<typeof AgentMetricBatchWriteReadingResultSchema>;
};

type PreparedMetricBatch =
  | {
      accepted: true;
      metrics: PreparedMetric[];
      readings: PreparedReading[];
    }
  | {
      accepted: false;
      errors: AgentMetricBatchWriteIssue[];
      warnings: AgentMetricBatchWriteIssue[];
    };

type MetricDefinition = {
  id: string;
  name: string;
  unit: string;
  valueShape: "scalar" | "structured" | "series";
  metricGroup: string;
  goalType: string | null;
  goalTargetValue: number | null;
  enabled: boolean;
  pinned: boolean;
  sortOrder: number;
  /** Non-null for a Lab Metric: the Lab Test its readings are results of. */
  labTestKey: string | null;
  updatedAt: Date;
  deletedAt: Date | null;
};

export function createDrizzleAgentMetricStore(db: ServerDatabase): AgentMetricStore {
  return {
    async listMetrics({ userId, query }) {
      const fields = resolveMetricFieldSelection(query.fields);
      const rows = await db
        .select()
        .from(schema.metrics)
        .where(eq(schema.metrics.userId, userId))
        .orderBy(
          asc(schema.metrics.sortOrder),
          asc(schema.metrics.name),
          asc(schema.metrics.id)
        );

      const search = query.search;
      const filtered = rows.filter((row) => {
        if (!query.includeArchived && row.deletedAt !== null) {
          return false;
        }
        if (query.enabledOnly && !row.enabled) {
          return false;
        }
        if (query.metricGroup !== undefined && row.metricGroup !== query.metricGroup) {
          return false;
        }
        if (
          query.metricKey !== undefined &&
          !metricMatchesMetricKey(row, userId, query.metricKey)
        ) {
          return false;
        }
        if (search !== undefined && !metricMatchesSearch(row, userId, search)) {
          return false;
        }

        return true;
      });
      const start = cursorOffset(filtered, query.cursor);
      const page = filtered.slice(start, start + query.limit);

      return AgentMetricListResponseSchema.parse({
        metrics: page.map((row) => projectMetricRow(row, fields)),
        fields,
        limit: query.limit,
        nextCursor:
          start + page.length >= filtered.length
            ? null
            : page[page.length - 1]?.id ?? null,
        totalMatched: filtered.length
      });
    },
    async listMetricReadings({ userId, query }) {
      const fields = resolveMetricReadingFieldSelection(query.fields);
      const labTarget = await resolveLabReadingTarget(db, userId, query);
      if (labTarget !== null) {
        return listLabMetricReadings(db, { userId, query, fields, labTarget });
      }
      const metricKeyIds =
        query.metricKey === undefined
          ? null
          : await resolveMetricIdsForMetricKey(db, userId, query.metricKey);
      const baseWhere = query.includeArchived
        ? eq(schema.metricReadings.userId, userId)
        : and(
            eq(schema.metricReadings.userId, userId),
            isNull(schema.metricReadings.deletedAt)
          );
      const rows = await db
        .select()
        .from(schema.metricReadings)
        .where(baseWhere)
        .orderBy(
          asc(schema.metricReadings.atTime),
          asc(schema.metricReadings.windowStartedAt),
          asc(schema.metricReadings.updatedAt),
          asc(schema.metricReadings.id)
        );

      const from = parseOptionalDate(query.from);
      const to = parseOptionalDate(query.to);
      const filtered = rows.filter((row) => {
        if (query.metricId !== undefined && row.metricId !== query.metricId) {
          return false;
        }
        if (metricKeyIds !== null && !metricKeyIds.has(row.metricId)) {
          return false;
        }
        if (query.provenance !== undefined && row.provenance !== query.provenance) {
          return false;
        }
        if (query.source !== undefined && row.source !== query.source) {
          return false;
        }
        const anchor = readingAnchor(row);
        if (from !== null && anchor < from) {
          return false;
        }
        if (to !== null && anchor > to) {
          return false;
        }

        return true;
      });
      const start = cursorOffset(filtered, query.cursor);
      const page = filtered.slice(start, start + query.limit);

      const trendByReadingId =
        query.includeTrend === "true"
          ? readingTrendsForPage(rows, page, await userLabMetricIds(db, userId))
          : null;

      return AgentMetricReadingsResponseSchema.parse({
        readings: page.map((row) => {
          const projected = projectMetricReadingRow(
            serializeMetricReadingRow(row, []),
            fields
          );
          const trendValue = trendByReadingId?.get(row.id);
          return trendValue === undefined ? projected : { ...projected, trendValue };
        }),
        fields,
        limit: query.limit,
        nextCursor:
          start + page.length >= filtered.length
            ? null
            : page[page.length - 1]?.id ?? null,
        totalMatched: filtered.length
      });
    },
    async writeMetricBatch({
      userId,
      batchId,
      correlationId,
      deviceId,
      request
    }) {
      const serverClock = new Date();
      const requestFingerprint = fingerprintAgentMetricRequest(request);

      return db.transaction(async (transaction) => {
        // Replay first: an exact replay of a lab write must not be judged by
        // the lab rules, which would reject its now-stored reading ids with
        // lab_result_exists (docs/designs/lab-results.md, "Agent surface").
        // The marker claim below still decides duplicate and writes nothing.
        const replay = await agentMetricBatchReceiptMatches(transaction, {
          userId,
          batchId,
          requestFingerprint
        });
        const prepared = await prepareMetricBatch({
          transaction,
          userId,
          deviceId,
          request,
          serverClock,
          replay
        });
        if (!prepared.accepted) {
          return prepared;
        }

        const markerResult = await insertAgentMetricBatchMarker(transaction, {
          userId,
          batchId,
          requestFingerprint,
          correlationId: correlationId ?? null,
          occurredAt: serverClock
        });

        if (markerResult === "conflict") {
          return {
            accepted: false,
            errors: [
              batchIssue({
                field: "idempotencyKey",
                rule: "idempotency_key_conflict",
                message:
                  "Idempotency key has already been used with a different request body."
              })
            ],
            warnings: []
          };
        }

        if (markerResult === "duplicate") {
          return {
            accepted: true,
            duplicate: true,
            serverClock: serverClock.toISOString(),
            activityLogEntries: 0,
            applied: [],
            metrics: prepared.metrics.map((metric) =>
              metricResultWithOutcome(metric.result, "duplicate")
            ),
            readings: prepared.readings.map((reading) =>
              readingResultWithOutcome(reading.result, "duplicate")
            )
          };
        }

        const existingMetricRows = await readMetricRowsById(
          transaction,
          prepared.metrics.map((metric) => metric.id)
        );
        const existingReadingRows = await readMetricReadingRowsById(
          transaction,
          prepared.readings.map((reading) => reading.id)
        );
        const applied: { id: string; updatedAt: string; deviceId: string }[] = [];
        const metricResults: z.infer<
          typeof AgentMetricBatchWriteMetricResultSchema
        >[] = [];
        const readingResults: z.infer<
          typeof AgentMetricBatchWriteReadingResultSchema
        >[] = [];
        let activityLogEntries = 0;

        for (const metric of prepared.metrics) {
          const existing = existingMetricRows.get(metric.id);
          if (
            existing !== undefined &&
            !lwwWins(metric.updatedAt, deviceId, existing.updatedAt, existing.deviceId)
          ) {
            await recordActivityLog(transaction, {
              id: `agent:${batchId}:metric:${metric.id}`,
              userId,
              batchId,
              entityTable: METRICS_AGENT_ENTITY,
              entityId: metric.id,
              beforeImage: serializeMetricRow(existing),
              afterImage: metric.afterImage,
              occurredAt: metric.updatedAt
            });
            activityLogEntries += 1;
            metricResults.push(
              metricResultWithOutcome(metric.result, "superseded")
            );
            continue;
          }

          if (existing === undefined && metric.insertOnConflictDoNothing) {
            await transaction
              .insert(schema.metrics)
              .values(metric.values)
              .onConflictDoNothing({ target: schema.metrics.id });
          } else if (existing === undefined) {
            await transaction.insert(schema.metrics).values(metric.values);
          } else {
            await transaction
              .update(schema.metrics)
              .set(metric.values)
              .where(
                and(
                  eq(schema.metrics.id, metric.id),
                  eq(schema.metrics.userId, userId)
                )
              );
          }
          await recordActivityLog(transaction, {
            id: `agent:${batchId}:metric:${metric.id}`,
            userId,
            batchId,
            entityTable: METRICS_AGENT_ENTITY,
            entityId: metric.id,
            beforeImage:
              existing === undefined ? null : serializeMetricRow(existing),
            afterImage: metric.afterImage,
            occurredAt: metric.updatedAt
          });
          activityLogEntries += 1;
          applied.push({
            id: metric.id,
            updatedAt: metric.updatedAt.toISOString(),
            deviceId
          });
          metricResults.push(metricResultWithOutcome(metric.result, "applied"));
        }

        for (const reading of prepared.readings) {
          const existing = existingReadingRows.get(reading.id);
          if (
            existing !== undefined &&
            !lwwWins(
              reading.updatedAt,
              deviceId,
              existing.updatedAt,
              existing.deviceId
            )
          ) {
            await recordActivityLog(transaction, {
              id: `agent:${batchId}:reading:${reading.id}`,
              userId,
              batchId,
              entityTable: METRIC_READINGS_SYNC_ENTITY,
              entityId: reading.id,
              beforeImage: serializeMetricReadingRow(existing, []),
              afterImage: reading.afterImage,
              occurredAt: reading.updatedAt
            });
            activityLogEntries += 1;
            readingResults.push(
              readingResultWithOutcome(reading.result, "superseded")
            );
            continue;
          }

          if (existing === undefined) {
            await transaction.insert(schema.metricReadings).values(reading.values);
          } else {
            await transaction
              .update(schema.metricReadings)
              .set(reading.values)
              .where(
                and(
                  eq(schema.metricReadings.id, reading.id),
                  eq(schema.metricReadings.userId, userId)
                )
              );
          }
          await recordActivityLog(transaction, {
            id: `agent:${batchId}:reading:${reading.id}`,
            userId,
            batchId,
            entityTable: METRIC_READINGS_SYNC_ENTITY,
            entityId: reading.id,
            beforeImage:
              existing === undefined ? null : serializeMetricReadingRow(existing, []),
            afterImage: reading.afterImage,
            occurredAt: reading.updatedAt
          });
          activityLogEntries += 1;
          applied.push({
            id: reading.id,
            updatedAt: reading.updatedAt.toISOString(),
            deviceId
          });
          readingResults.push(
            readingResultWithOutcome(reading.result, "applied")
          );
        }

        return {
          accepted: true,
          duplicate: false,
          serverClock: serverClock.toISOString(),
          activityLogEntries,
          applied,
          metrics: metricResults,
          readings: readingResults
        };
      });
    }
  };
}

/**
 * Validates a batch and builds every row it would write, without writing.
 *
 * A reading names its Metric by `metricId` or, for a lab result, by
 * `labTestKey` (docs/designs/lab-results.md, "Agent surface"). A lab reading
 * runs the request rules and the shared reading rules (`validateLabResult`)
 * before normalisation, in the Validation table's order, and each issue keeps
 * its rule as its code. Only a batch with no error so far finds or creates
 * the Lab Metric ("Finding the Lab Metric for a Lab Test").
 *
 * [replay] is true when the idempotency receipt already holds this exact
 * request: a lab reading then skips every lab rule and Lab Metric lookup and
 * is answered from its stored row, because the original write made its id an
 * existing reading and the rules would reject it with `lab_result_exists`.
 */
async function prepareMetricBatch({
  transaction,
  userId,
  deviceId,
  request,
  serverClock,
  replay
}: {
  transaction: MutationDatabase;
  userId: string;
  deviceId: string;
  request: AgentMetricBatchWriteRequest;
  serverClock: Date;
  replay: boolean;
}): Promise<PreparedMetricBatch> {
  const errors: AgentMetricBatchWriteIssue[] = [];
  const warnings: AgentMetricBatchWriteIssue[] = [];
  const seenMetricIds = new Set<string>();
  const seenReadingIds = new Set<string>();
  const metricIds = [
    ...new Set([
      ...request.metrics.map((metric) => metric.id),
      ...request.readings.flatMap((reading) =>
        reading.metricId === undefined ? [] : [reading.metricId]
      )
    ])
  ];
  const readingIds = [...new Set(request.readings.map((reading) => reading.id))];
  const existingMetricRows = await readMetricRowsById(transaction, metricIds);
  const existingReadingRows = await readMetricReadingRowsById(
    transaction,
    readingIds
  );
  const requestMetricDefinitions = new Map<string, MetricDefinition>();
  const preparedMetrics: PreparedMetric[] = [];
  const preparedReadings: PreparedReading[] = [];
  // The server's UTC date: "today" for lab_collected_future.
  const today = serverClock.toISOString().slice(0, 10);
  const labMetricsByKey = new Map<string, MetricDefinition>();
  const savedLabResultsByKey = new Map<string, SavedLabResult[]>();
  let metricIdentityLocked = false;
  let nextLabMetricSortOrder: number | null = null;

  /**
   * The user's Lab Metric for [labTestKey], found or prepared once per key per
   * batch (docs/designs/lab-results.md, "Finding the Lab Metric for a Lab
   * Test"). `lockMetricIdentity` serializes this per user for the rest of the
   * transaction, so two concurrent first writes of one key create one row: the
   * second waits, then finds the first's. With no live Lab Metric the row at
   * `stableMetricId(userId, "lab:" + key)` is created, unarchived or given its
   * key, and goes through `preparedMetrics`, so it gets an Activity Log entry,
   * is undone with the Batch and appears in `metrics[]`. Null after pushing an
   * error.
   */
  async function resolveLabMetric(
    labTestKey: string,
    labTest: LabTestEntry
  ): Promise<MetricDefinition | null> {
    const cached = labMetricsByKey.get(labTestKey);
    if (cached !== undefined) {
      return cached;
    }
    if (!metricIdentityLocked) {
      await lockMetricIdentity(transaction, userId);
      metricIdentityLocked = true;
    }
    const live = await findLabMetric(transaction, { userId, labTestKey });
    if (live !== null) {
      const definition = existingMetricDefinition(live);
      labMetricsByKey.set(labTestKey, definition);
      return definition;
    }

    const id = stableMetricId(userId, `lab:${labTestKey}`);
    if (seenMetricIds.has(id)) {
      const itemIndex = request.metrics.findIndex((metric) => metric.id === id);
      errors.push(
        metricIssue({
          field: `metrics[${itemIndex}]`,
          itemIndex,
          metricId: id,
          rule: "lab_metric_upsert_not_allowed",
          message: "Lab Metrics can't be changed."
        })
      );
      return null;
    }
    const stored = (await readMetricRowsById(transaction, [id])).get(id);
    if (stored !== undefined && stored.userId !== userId) {
      // The id hashes the user id in, so this is unreachable in practice.
      throw new Error("Lab Metric id is owned by another account.");
    }
    if (
      stored !== undefined &&
      stored.labTestKey !== null &&
      stored.labTestKey !== labTestKey
    ) {
      // The id hashes the key in and the key is write-once.
      throw new Error("Lab Metric id holds another Lab Test.");
    }

    // The server clock, unless the stored row is already later (a device
    // clock ahead of the server's): then one millisecond after it, so the
    // unarchive or the key is never lost to last-writer-wins.
    const updatedAt =
      stored !== undefined && stored.updatedAt.getTime() >= serverClock.getTime()
        ? new Date(stored.updatedAt.getTime() + 1)
        : serverClock;
    let definition: MetricDefinition;
    if (stored === undefined) {
      if (nextLabMetricSortOrder === null) {
        const rows = await transaction
          .select({ highest: max(schema.metrics.sortOrder) })
          .from(schema.metrics)
          .where(eq(schema.metrics.userId, userId));
        const highest = rows[0]?.highest ?? null;
        nextLabMetricSortOrder = highest === null ? 0 : highest + 1;
      }
      definition = {
        id,
        name: labTest.name,
        unit: labTest.unit,
        valueShape: "scalar",
        metricGroup: "custom",
        goalType: null,
        goalTargetValue: null,
        enabled: true,
        pinned: false,
        sortOrder: nextLabMetricSortOrder,
        labTestKey,
        updatedAt,
        deletedAt: null
      };
      nextLabMetricSortOrder += 1;
    } else {
      definition = {
        ...existingMetricDefinition(stored),
        labTestKey,
        updatedAt,
        deletedAt: null
      };
    }

    preparedMetrics.push({
      id,
      updatedAt,
      deletedAt: null,
      // A new row is inserted with ON CONFLICT DO NOTHING on id, as the spec
      // says; the lock above already makes a conflict unreachable.
      insertOnConflictDoNothing: true,
      values: {
        id,
        userId,
        deviceId,
        name: definition.name,
        unit: definition.unit,
        valueShape: definition.valueShape,
        metricGroup: definition.metricGroup,
        goalType: definition.goalType,
        goalTargetValue: definition.goalTargetValue,
        enabled: definition.enabled,
        pinned: definition.pinned,
        sortOrder: definition.sortOrder,
        labTestKey,
        updatedAt,
        deletedAt: null,
        receivedAt: serverClock
      },
      afterImage: serializeMetricDefinition(definition),
      result: AgentMetricBatchWriteMetricResultSchema.parse({
        id,
        name: definition.name,
        valueShape: definition.valueShape,
        unit: definition.unit,
        metricGroup: definition.metricGroup,
        applied: true,
        outcome: "applied"
      })
    });
    labMetricsByKey.set(labTestKey, definition);
    return definition;
  }

  /**
   * The user's saved Lab Results for [labTestKey], collapsed: the live
   * readings of every Metric with the key, archived Lab Metrics included,
   * because identity is per user and per Lab Test, not per row
   * (docs/designs/lab-results.md, "Result identity and the collapse").
   */
  async function savedLabResults(labTestKey: string) {
    const cached = savedLabResultsByKey.get(labTestKey);
    if (cached !== undefined) {
      return cached;
    }
    const ids = await labMetricIds(transaction, { userId, labTestKey });
    const rows =
      ids.length === 0
        ? []
        : await transaction
            .select()
            .from(schema.metricReadings)
            .where(
              and(
                eq(schema.metricReadings.userId, userId),
                inArray(schema.metricReadings.metricId, ids),
                isNull(schema.metricReadings.deletedAt)
              )
            );
    const saved = collapseLabResults(
      rows.map((row) => ({
        id: row.id,
        labTestKey,
        lab: row.valueJson?.lab ?? null,
        atTime: readingAnchor(row).toISOString(),
        updatedAt: row.updatedAt.toISOString(),
        deletedAt: null,
        scalarValue: row.scalarValue
      }))
    );
    savedLabResultsByKey.set(labTestKey, saved);
    return saved;
  }

  function pushPreparedReading({
    reading,
    itemIndex,
    metricId,
    normalized,
    scalarEntered,
    provenance,
    source,
    updatedAt,
    deletedAt,
    ruleWarnings
  }: {
    reading: AgentMetricBatchWriteReading;
    itemIndex: number;
    metricId: string;
    normalized: ReturnType<typeof normalizeMetricReading>;
    scalarEntered: string | null;
    provenance: string;
    source: string;
    updatedAt: Date;
    deletedAt: Date | null;
    ruleWarnings: string[];
  }) {
    for (const warning of normalized.warnings) {
      warnings.push(
        readingIssue({
          field: `readings[${itemIndex}].timeAnchor`,
          itemIndex,
          readingId: reading.id,
          metricId,
          rule: warning,
          message: warning
        })
      );
    }

    const valueJson = JSON.parse(normalized.valueJson) as Record<string, unknown>;
    const atTime = normalized.atTime === null ? null : new Date(normalized.atTime);
    const windowStartedAt =
      normalized.windowStartedAt === null ? null : new Date(normalized.windowStartedAt);
    const windowEndedAt =
      normalized.windowEndedAt === null ? null : new Date(normalized.windowEndedAt);
    const afterImage = serializePreparedMetricReading({
      reading,
      metricId,
      provenance,
      source,
      valueShape: normalized.valueShape as "scalar" | "structured" | "series",
      unit: normalized.unit,
      valueJson,
      scalarValue: normalized.scalarValue,
      scalarEntered,
      atTime: normalized.atTime,
      windowStartedAt: normalized.windowStartedAt,
      windowEndedAt: normalized.windowEndedAt,
      updatedAt,
      deletedAt
    });
    preparedReadings.push({
      id: reading.id,
      updatedAt,
      deletedAt,
      values: {
        id: reading.id,
        userId,
        deviceId,
        metricId,
        externalActivityId: reading.externalActivityId,
        valueJson,
        scalarValue: normalized.scalarValue,
        scalarEntered,
        atTime,
        windowStartedAt,
        windowEndedAt,
        provenance,
        source,
        externalId: reading.externalId,
        comment: reading.comment,
        updatedAt,
        deletedAt,
        receivedAt: serverClock
      },
      afterImage,
      result: AgentMetricBatchWriteReadingResultSchema.parse({
        id: reading.id,
        metricId,
        valueShape: normalized.valueShape,
        unit: normalized.unit,
        warnings: [...ruleWarnings, ...normalized.warnings],
        applied: true,
        outcome: "applied"
      })
    });
  }

  for (const [itemIndex, metric] of request.metrics.entries()) {
    if (seenMetricIds.has(metric.id)) {
      errors.push(
        metricIssue({
          field: `metrics[${itemIndex}].id`,
          itemIndex,
          metricId: metric.id,
          rule: "duplicate_metric_id",
          message: "A Metric id may appear only once per batch."
        })
      );
      continue;
    }
    seenMetricIds.add(metric.id);

    const existing = existingMetricRows.get(metric.id);
    if (existing !== undefined && existing.userId !== userId) {
      errors.push(
        metricIssue({
          field: `metrics[${itemIndex}].id`,
          itemIndex,
          metricId: metric.id,
          rule: "metric_id_not_visible",
          message: "Metric is not visible to the authenticated account."
        })
      );
      continue;
    }
    // A Lab Metric is a container the Agent cannot upsert
    // (docs/designs/lab-results.md, "Storage" and "Agent surface"): neither
    // by its id nor by sending a key, which would otherwise be stripped and
    // leave a custom Metric. A replay skips this: its original was accepted.
    if (
      !replay &&
      (metric.labTestKey !== undefined ||
        (existing !== undefined && existing.labTestKey !== null))
    ) {
      errors.push(
        metricIssue({
          field: `metrics[${itemIndex}]`,
          itemIndex,
          metricId: metric.id,
          rule: "lab_metric_upsert_not_allowed",
          message: "Lab Metrics can't be changed."
        })
      );
      continue;
    }

    const updatedAt = parseIncomingDate(
      metric.updatedAt ?? serverClock.toISOString(),
      serverClock
    );
    const deletedAt =
      metric.deletedAt === null
        ? null
        : parseIncomingNullableDate(metric.deletedAt, serverClock);
    if (updatedAt === null || deletedAt === undefined) {
      errors.push(
        metricIssue({
          field: `metrics[${itemIndex}].updatedAt`,
          itemIndex,
          metricId: metric.id,
          rule: "invalid_metric_timestamp",
          message: "Metric timestamps must be valid ISO-8601 values."
        })
      );
      continue;
    }

    const definition: MetricDefinition = {
      id: metric.id,
      name: metric.name,
      unit: metric.unit,
      valueShape: metric.valueShape,
      metricGroup: metric.metricGroup,
      goalType: metric.goalType,
      goalTargetValue: metric.goalTargetValue,
      enabled: metric.enabled,
      pinned: metric.pinned,
      sortOrder: metric.sortOrder,
      labTestKey: null,
      updatedAt,
      deletedAt
    };
    requestMetricDefinitions.set(metric.id, definition);
    const afterImage = serializeMetricDefinition(definition);
    preparedMetrics.push({
      id: metric.id,
      updatedAt,
      deletedAt,
      insertOnConflictDoNothing: false,
      values: {
        id: metric.id,
        userId,
        deviceId,
        name: metric.name,
        unit: metric.unit,
        valueShape: metric.valueShape,
        metricGroup: metric.metricGroup,
        goalType: metric.goalType,
        goalTargetValue: metric.goalTargetValue,
        enabled: metric.enabled,
        pinned: metric.pinned,
        sortOrder: metric.sortOrder,
        updatedAt,
        deletedAt,
        receivedAt: serverClock
      },
      afterImage,
      result: AgentMetricBatchWriteMetricResultSchema.parse({
        id: metric.id,
        name: metric.name,
        valueShape: metric.valueShape,
        unit: metric.unit,
        metricGroup: metric.metricGroup,
        applied: true,
        outcome: "applied"
      })
    });
  }

  for (const [itemIndex, reading] of request.readings.entries()) {
    if (seenReadingIds.has(reading.id)) {
      errors.push(
        readingIssue({
          field: `readings[${itemIndex}].id`,
          itemIndex,
          readingId: reading.id,
          metricId: reading.metricId ?? null,
          rule: "duplicate_reading_id",
          message: "A Metric Reading id may appear only once per batch."
        })
      );
      continue;
    }
    seenReadingIds.add(reading.id);

    const existingReading = existingReadingRows.get(reading.id);
    if (existingReading !== undefined && existingReading.userId !== userId) {
      errors.push(
        readingIssue({
          field: `readings[${itemIndex}].id`,
          itemIndex,
          readingId: reading.id,
          metricId: reading.metricId ?? null,
          rule: "reading_id_not_visible",
          message:
            "Metric Reading is not visible to the authenticated account."
        })
      );
      continue;
    }

    // A replayed lab reading is answered from the row its original wrote,
    // before any lab rule: lab_result_exists would reject it otherwise. The
    // receipt claim then returns `duplicate`, so nothing is written.
    if (replay && reading.labTestKey !== undefined && existingReading !== undefined) {
      preparedReadings.push(replayedLabReading(existingReading));
      continue;
    }

    if ((reading.metricId === undefined) === (reading.labTestKey === undefined)) {
      errors.push(
        readingIssue({
          field: `readings[${itemIndex}]`,
          itemIndex,
          readingId: reading.id,
          metricId: reading.metricId ?? null,
          rule: "lab_target_ambiguous",
          message: "Give exactly one of metricId and labTestKey."
        })
      );
      continue;
    }

    if (reading.labTestKey !== undefined) {
      // A lab result by Lab Test (docs/designs/lab-results.md, "Agent
      // surface" and "Validation"): the request rules, then the shared
      // reading rules, then lab_result_replaces, all before normalisation.
      const labTestKey = reading.labTestKey;
      const labIssue = (field: string, rule: string, message: string) =>
        readingIssue({
          field,
          itemIndex,
          readingId: reading.id,
          metricId: null,
          rule,
          message
        });
      const labTest = labTestByKey(labTestKey);
      if (labTest === null) {
        errors.push(
          labIssue(
            `readings[${itemIndex}].labTestKey`,
            "lab_test_unknown",
            "Unknown Lab Test. List Lab Tests with agent_list_lab_tests."
          )
        );
        continue;
      }
      const value = reading.value;
      if (value.shape !== "scalar") {
        errors.push(
          labIssue(
            `readings[${itemIndex}].value`,
            "lab_value_invalid",
            "Enter a number, optionally after <, <=, > or >=."
          )
        );
        continue;
      }
      if (reading.deletedAt !== null) {
        errors.push(
          labIssue(
            `readings[${itemIndex}].deletedAt`,
            "lab_archive_not_allowed",
            "Agents can't archive lab results."
          )
        );
        continue;
      }
      if (existingReading !== undefined) {
        errors.push(
          labIssue(
            `readings[${itemIndex}].id`,
            "lab_result_exists",
            "Lab results can't be changed. Write a new result."
          )
        );
        continue;
      }

      const lab = value.lab ?? null;
      const validation = validateLabResult(
        {
          labTestKey,
          entered: value.entered,
          // An omitted unit is the Lab Test's own, as the normaliser reads an
          // omitted unit as its Metric's.
          enteredUnit: value.unit ?? labTest.unit,
          lab,
          timeAnchor: reading.timeAnchor
        },
        { today }
      );
      for (const issue of validation.errors) {
        errors.push(
          labIssue(labIssueWirePath(itemIndex, issue.field), issue.rule, issue.message)
        );
      }
      if (validation.errors.length > 0 || lab === null) {
        continue;
      }
      const ruleWarnings: string[] = [];
      for (const issue of validation.warnings) {
        warnings.push(
          labIssue(labIssueWirePath(itemIndex, issue.field), issue.rule, issue.message)
        );
        ruleWarnings.push(issue.rule);
      }

      // lab_result_replaces, as the app's `previewCollection` computes it:
      // the kept saved result with this collection, when its value differs.
      const collected = lab.collected as string;
      const replaced = (await savedLabResults(labTestKey)).find(
        (saved) => decodeLab(saved.lab)?.collected === collected
      );
      if (replaced !== undefined && labValueDiffers(replaced, value.entered)) {
        warnings.push(
          labIssue(
            `readings[${itemIndex}].value.entered`,
            "lab_result_replaces",
            "This replaces a saved result for the same collection."
          )
        );
        ruleWarnings.push("lab_result_replaces");
      }

      if (errors.length > 0) {
        continue;
      }
      const labMetric = await resolveLabMetric(labTestKey, labTest);
      if (labMetric === null) {
        continue;
      }

      let normalized: ReturnType<typeof normalizeMetricReading>;
      try {
        // The normaliser derives lab.limit from entered, overwriting any sent.
        normalized = normalizeMetricReading({
          metric: {
            valueShape: labMetric.valueShape,
            unit: labMetric.unit,
            labTestKey: labMetric.labTestKey
          },
          value: value as MetricReadingNormalizationInput["value"],
          timeAnchor:
            reading.timeAnchor as MetricReadingNormalizationInput["timeAnchor"]
        });
      } catch (error) {
        // Unreachable when the rules above agree with the normaliser.
        errors.push(
          readingIssue({
            field: `readings[${itemIndex}]`,
            itemIndex,
            readingId: reading.id,
            metricId: labMetric.id,
            rule: "metric_reading_normalization_failed",
            message:
              error instanceof Error
                ? error.message
                : "Metric Reading could not be normalized."
          })
        );
        continue;
      }

      const storedEntered = JSON.parse(normalized.valueJson).entered;
      // The server sets updatedAt, provenance and source of a lab result,
      // whatever the request sends.
      pushPreparedReading({
        reading,
        itemIndex,
        metricId: labMetric.id,
        normalized,
        scalarEntered:
          typeof storedEntered === "string" ? storedEntered : value.entered.trim(),
        provenance: "agent",
        source: "agent",
        updatedAt: serverClock,
        deletedAt: null,
        ruleWarnings
      });
      continue;
    }

    const metricId = reading.metricId as string;
    if (!replay) {
      const storedMetric = existingMetricRows.get(metricId);
      if (
        storedMetric !== undefined &&
        storedMetric.userId === userId &&
        storedMetric.labTestKey !== null
      ) {
        errors.push(
          readingIssue({
            field: `readings[${itemIndex}].metricId`,
            itemIndex,
            readingId: reading.id,
            metricId,
            rule: "lab_metric_id_not_allowed",
            message: "Write lab results by labTestKey."
          })
        );
        continue;
      }
      if (reading.value.shape === "scalar" && reading.value.lab != null) {
        errors.push(
          readingIssue({
            field: `readings[${itemIndex}].value.lab`,
            itemIndex,
            readingId: reading.id,
            metricId,
            rule: "lab_fields_on_non_lab_metric",
            message: "This Metric is not a Lab Test."
          })
        );
        continue;
      }
    }

    const requestMetric = requestMetricDefinitions.get(metricId);
    const existingMetric = existingMetricRows.get(metricId);
    const metric =
      requestMetric ??
      (existingMetric === undefined ? null : existingMetricDefinition(existingMetric));
    if (
      metric === null ||
      (requestMetric === undefined && existingMetric?.userId !== userId)
    ) {
      errors.push(
        readingIssue({
          field: `readings[${itemIndex}].metricId`,
          itemIndex,
          readingId: reading.id,
          metricId,
          rule: "metric_not_found",
          message: "Metric Reading references a Metric that is not visible."
        })
      );
      continue;
    }
    if (metric.deletedAt !== null) {
      errors.push(
        readingIssue({
          field: `readings[${itemIndex}].metricId`,
          itemIndex,
          readingId: reading.id,
          metricId,
          rule: "metric_archived",
          message: "Metric Reading cannot be written against an archived Metric."
        })
      );
      continue;
    }

    const updatedAt = parseIncomingDate(
      reading.updatedAt ?? serverClock.toISOString(),
      serverClock
    );
    const deletedAt =
      reading.deletedAt === null
        ? null
        : parseIncomingNullableDate(reading.deletedAt, serverClock);
    if (updatedAt === null || deletedAt === undefined) {
      errors.push(
        readingIssue({
          field: `readings[${itemIndex}].updatedAt`,
          itemIndex,
          readingId: reading.id,
          metricId,
          rule: "invalid_reading_timestamp",
          message: "Metric Reading timestamps must be valid ISO-8601 values."
        })
      );
      continue;
    }

    let normalized: ReturnType<typeof normalizeMetricReading>;
    try {
      normalized = normalizeMetricReading({
        metric: {
          valueShape: metric.valueShape,
          unit: metric.unit
        },
        value: reading.value as MetricReadingNormalizationInput["value"],
        timeAnchor:
          reading.timeAnchor as MetricReadingNormalizationInput["timeAnchor"]
      });
    } catch (error) {
      errors.push(
        readingIssue({
          field: `readings[${itemIndex}]`,
          itemIndex,
          readingId: reading.id,
          metricId,
          rule: "metric_reading_normalization_failed",
          message:
            error instanceof Error
              ? error.message
              : "Metric Reading could not be normalized."
        })
      );
      continue;
    }

    pushPreparedReading({
      reading,
      itemIndex,
      metricId,
      normalized,
      scalarEntered:
        reading.value.shape === "scalar" ? reading.value.entered.trim() : null,
      provenance: reading.provenance,
      source: reading.source,
      updatedAt,
      deletedAt,
      ruleWarnings: []
    });
  }

  if (errors.length > 0) {
    return { accepted: false, errors, warnings };
  }

  return {
    accepted: true,
    metrics: preparedMetrics,
    readings: preparedReadings
  };
}

/** A saved Lab Result as `lab_result_replaces` compares it. */
type SavedLabResult = LabReadingRef & { scalarValue: number | null };

/**
 * Whether [entered] states a different value from [saved], the rule of the
 * app's `previewCollection`: numbers compare numerically, limits by
 * comparator and bound, and a number never equals a limit.
 */
function labValueDiffers(saved: SavedLabResult, entered: string) {
  const parsed = parseEntered(entered.trim());
  if (parsed === null) {
    return false;
  }
  const number = Number(parsed.number);
  const limit = decodeLab(saved.lab)?.limit ?? null;
  if (limit !== null) {
    return !(parsed.comparator === limit.comparator && number === limit.bound);
  }
  return !(
    parsed.comparator === null &&
    saved.scalarValue !== null &&
    number === saved.scalarValue
  );
}

/**
 * The wire path of a `validateLabResult` issue field for reading [itemIndex]:
 * `entered` and `enteredUnit` live on the value, `lab.*` under the value, and
 * the time anchor on the reading.
 */
function labIssueWirePath(itemIndex: number, field: string) {
  const reading = `readings[${itemIndex}]`;
  if (field === "entered") return `${reading}.value.entered`;
  if (field === "enteredUnit") return `${reading}.value.unit`;
  if (field.startsWith("lab.") || field === "lab") return `${reading}.value.${field}`;
  if (field === "timeAnchor") return `${reading}.timeAnchor`;
  return `${reading}.${field}`;
}

/**
 * A replayed lab reading, answered from the row its original request wrote:
 * its Metric, value shape and unit, and no warnings. It is reported as a
 * duplicate and never written.
 */
function replayedLabReading(stored: MetricReadingRow): PreparedReading {
  const serialized = serializeMetricReadingRow(stored, []);
  return {
    id: stored.id,
    updatedAt: stored.updatedAt,
    deletedAt: stored.deletedAt,
    values: { ...stored },
    afterImage: serialized,
    result: AgentMetricBatchWriteReadingResultSchema.parse({
      id: stored.id,
      metricId: stored.metricId,
      valueShape: serialized.valueShape,
      unit: serialized.unit,
      warnings: [],
      applied: true,
      outcome: "applied"
    })
  };
}

/**
 * Whether this user's receipt for [batchId] already holds this exact request,
 * read without writing, with the same match as `claimAgentBatchReceipt`.
 * Read before validation so that a replay of a lab write is answered as a
 * duplicate rather than rejected by `lab_result_exists`
 * (docs/designs/lab-results.md, "Agent surface").
 */
async function agentMetricBatchReceiptMatches(
  transaction: MutationDatabase,
  {
    userId,
    batchId,
    requestFingerprint
  }: { userId: string; batchId: string; requestFingerprint: string }
) {
  const rows = await transaction
    .select({ afterImage: schema.activityLog.afterImage })
    .from(schema.activityLog)
    .where(
      and(
        eq(schema.activityLog.id, `agent:${batchId}:batch`),
        eq(schema.activityLog.userId, userId),
        eq(schema.activityLog.actor, "agent"),
        eq(schema.activityLog.batchId, batchId),
        eq(schema.activityLog.entityTable, AGENT_METRIC_BATCH_ENTITY),
        eq(schema.activityLog.entityId, batchId)
      )
    )
    .limit(1);
  const receipt = rows[0];
  return (
    receipt !== undefined &&
    receipt.afterImage?.kind === "agent_metric_batch" &&
    receipt.afterImage.requestFingerprint === requestFingerprint
  );
}

async function readMetricRowsById(
  transaction: MutationDatabase,
  ids: readonly string[]
) {
  if (ids.length === 0) {
    return new Map<string, MetricRow>();
  }
  const rows = await transaction
    .select()
    .from(schema.metrics)
    .where(inArray(schema.metrics.id, [...ids]));

  return new Map(rows.map((row) => [row.id, row]));
}

async function readMetricReadingRowsById(
  transaction: MutationDatabase,
  ids: readonly string[]
) {
  if (ids.length === 0) {
    return new Map<string, MetricReadingRow>();
  }
  const rows = await transaction
    .select()
    .from(schema.metricReadings)
    .where(inArray(schema.metricReadings.id, [...ids]));

  return new Map(rows.map((row) => [row.id, row]));
}

async function recordActivityLog(
  transaction: MutationDatabase,
  {
    id,
    userId,
    batchId,
    entityTable,
    entityId,
    beforeImage,
    afterImage,
    occurredAt
  }: {
    id: string;
    userId: string;
    batchId: string;
    entityTable: string;
    entityId: string;
    beforeImage: Record<string, unknown> | null;
    afterImage: Record<string, unknown>;
    occurredAt: Date;
  }
) {
  await transaction
    .insert(schema.activityLog)
    .values({
      id,
      userId,
      actor: "agent",
      batchId,
      entityTable,
      entityId,
      beforeImage,
      afterImage,
      occurredAt
    })
    .onConflictDoNothing({ target: schema.activityLog.id });
}

async function insertAgentMetricBatchMarker(
  transaction: MutationDatabase,
  {
    userId,
    batchId,
    requestFingerprint,
    correlationId,
    occurredAt
  }: {
    userId: string;
    batchId: string;
    requestFingerprint: string;
    correlationId: string | null;
    occurredAt: Date;
  }
): Promise<"inserted" | "duplicate" | "conflict"> {
  const claim = await claimAgentBatchReceipt(transaction, {
    markerId: `agent:${batchId}:batch`,
    userId,
    batchId,
    entityTable: AGENT_METRIC_BATCH_ENTITY,
    kind: "agent_metric_batch",
    requestFingerprint,
    occurredAt,
    metadata: { correlationId }
  });
  return claim.status === "unavailable" ? "conflict" : claim.status;
}

function existingMetricDefinition(row: MetricRow): MetricDefinition {
  return {
    id: row.id,
    name: row.name,
    unit: row.unit,
    valueShape: metricValueShape(row.valueShape),
    metricGroup: row.metricGroup,
    goalType: row.goalType,
    goalTargetValue: row.goalTargetValue,
    enabled: row.enabled,
    pinned: row.pinned,
    sortOrder: row.sortOrder,
    labTestKey: row.labTestKey,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt
  };
}

function metricValueShape(value: string): "scalar" | "structured" | "series" {
  if (value === "scalar" || value === "structured" || value === "series") {
    return value;
  }

  return "scalar";
}

type MetricCatalogMetadata = {
  schema: PerenniaMetricSchema | null;
  canonicalKey: string | null;
  aliases: readonly string[];
  dataClass: string | null;
};

function metricCatalogMetadataForRow(row: MetricRow): MetricCatalogMetadata {
  return metricCatalogMetadataForIdentity({
    userId: row.userId,
    id: row.id,
    name: row.name,
    unit: row.unit,
    metricGroup: row.metricGroup,
    labTestKey: row.labTestKey
  });
}

function metricCatalogMetadataForDefinition(
  metric: MetricDefinition
): MetricCatalogMetadata {
  return metricCatalogMetadataForIdentity({
    id: metric.id,
    name: metric.name,
    unit: metric.unit,
    metricGroup: metric.metricGroup,
    labTestKey: metric.labTestKey
  });
}

/**
 * A Metric's catalog identity. A Lab Metric's canonical key is its Lab Test
 * key, with no aliases and no data class, decided before any catalog match:
 * a Lab Metric is never a catalog Metric, whatever its name
 * (docs/designs/lab-results.md, "Finding the Lab Metric for a Lab Test").
 */
function metricCatalogMetadataForIdentity({
  userId,
  id,
  name,
  unit,
  metricGroup,
  labTestKey = null
}: {
  userId?: string;
  id: string;
  name: string;
  unit: string;
  metricGroup: string;
  labTestKey?: string | null;
}): MetricCatalogMetadata {
  if (labTestKey !== null) {
    return { schema: null, canonicalKey: labTestKey, aliases: [], dataClass: null };
  }
  const schemaByStableId =
    userId === undefined
      ? null
      : PRN_METRIC_SCHEMAS.find(
          (candidate) => stableMetricId(userId, candidate.canonicalKey) === id
        ) ?? null;
  const schema =
    schemaByStableId ??
    PRN_METRIC_SCHEMAS.find((candidate) =>
      metricIdentityMatchesCatalogSchema({ name, unit, metricGroup }, candidate)
    ) ??
    null;

  return {
    schema,
    canonicalKey: schema?.canonicalKey ?? null,
    aliases: schema?.aliases ?? [],
    dataClass: schema?.dataClass ?? null
  };
}

function metricIdentityMatchesCatalogSchema(
  metric: { name: string; unit: string; metricGroup: string },
  candidate: PerenniaMetricSchema
) {
  if (
    normalizeMetricLookupKey(metric.name) !==
    normalizeMetricLookupKey(candidate.displayName)
  ) {
    return false;
  }

  return (
    metric.metricGroup === candidate.metricGroup || metric.unit === candidate.defaultUnit
  );
}

/**
 * Whether [row] answers the `metricKey` filter. Lab Metrics match by key
 * only (docs/designs/lab-results.md, "Finding the Lab Metric for a Lab
 * Test", Matching by key): a row with a `labTestKey` matches exactly that
 * key, and a catalogue Lab Test key matches only rows with that
 * `labTestKey`, never a custom Metric whose name or stable id happens to
 * match and never a PRN schema (the catalogue generator keeps Lab Test keys
 * and PRN keys apart). Without the first rule a Lab Metric found by its name
 * would be read uncollapsed.
 */
function metricMatchesMetricKey(
  row: MetricRow,
  userId: string,
  metricKey: string
) {
  if (row.labTestKey !== null) {
    return row.labTestKey === metricKey;
  }
  if (labTestByKey(metricKey) !== null) {
    return false;
  }
  const schemaForKey = owlMetricSchemaForImportKey(metricKey);
  const metadata = metricCatalogMetadataForRow(row);
  if (schemaForKey !== null) {
    return metadata.canonicalKey === schemaForKey.canonicalKey;
  }

  const normalizedMetricKey = normalizeMetricLookupKey(metricKey);
  return (
    row.id === stableMetricId(userId, metricKey) ||
    normalizeMetricLookupKey(row.name) === normalizedMetricKey ||
    metricSearchTokens(row, metadata).some(
      (token) => normalizeMetricLookupKey(token) === normalizedMetricKey
    )
  );
}

function metricMatchesSearch(row: MetricRow, userId: string, search: string) {
  const metadata = metricCatalogMetadataForRow(row);
  const foldedSearch = search.toLocaleLowerCase("en-US");
  const normalizedSearch = normalizeMetricLookupKey(search);
  const stableUnknownMetricId = stableMetricId(userId, search);

  return (
    row.id === stableUnknownMetricId ||
    metricSearchTokens(row, metadata).some((token) => {
      const foldedToken = token.toLocaleLowerCase("en-US");
      return (
        foldedToken.includes(foldedSearch) ||
        normalizeMetricLookupKey(token).includes(normalizedSearch)
      );
    })
  );
}

function metricSearchTokens(row: MetricRow, metadata: MetricCatalogMetadata) {
  return [
    row.name,
    row.unit,
    row.metricGroup,
    metadata.canonicalKey,
    metadata.dataClass,
    ...metadata.aliases
  ].filter((value): value is string => typeof value === "string" && value.length > 0);
}

async function resolveMetricIdsForMetricKey(
  db: ServerDatabase,
  userId: string,
  metricKey: string
) {
  const rows = await db
    .select()
    .from(schema.metrics)
    .where(eq(schema.metrics.userId, userId));

  return new Set(
    rows
      .filter((row) => metricMatchesMetricKey(row, userId, metricKey))
      .map((row) => row.id)
  );
}

/** The ids of every Metric of the user with a `labTestKey`, archived included. */
async function userLabMetricIds(db: ServerDatabase, userId: string) {
  const rows = await db
    .select({ id: schema.metrics.id })
    .from(schema.metrics)
    .where(
      and(eq(schema.metrics.userId, userId), isNotNull(schema.metrics.labTestKey))
    );
  return new Set(rows.map((row) => row.id));
}

/**
 * What a readings request reads when it filters by a Lab Metric: `lab` with
 * the Lab Test key, `empty` when `metricId` and `metricKey` name different
 * keys (no reading can answer both), or null for any other read.
 *
 * `metricId` is a lab filter when it names a Metric with a `labTestKey`.
 * `metricKey` is one when it is a catalogue Lab Test key, or the key of one
 * of the user's Lab Metrics that this build's catalogue does not know
 * (written by a later build), which [metricMatchesMetricKey] matches by key
 * the same way.
 */
type LabReadingTarget = { kind: "lab"; labTestKey: string } | { kind: "empty" };

async function resolveLabReadingTarget(
  db: ServerDatabase,
  userId: string,
  query: AgentMetricReadingsQuery
): Promise<LabReadingTarget | null> {
  let idKey: string | null = null;
  if (query.metricId !== undefined) {
    const [row] = await db
      .select({ labTestKey: schema.metrics.labTestKey })
      .from(schema.metrics)
      .where(
        and(eq(schema.metrics.userId, userId), eq(schema.metrics.id, query.metricId))
      )
      .limit(1);
    idKey = row?.labTestKey ?? null;
  }
  let keyKey: string | null = null;
  if (query.metricKey !== undefined) {
    if (labTestByKey(query.metricKey) !== null) {
      keyKey = query.metricKey;
    } else {
      const [row] = await db
        .select({ id: schema.metrics.id })
        .from(schema.metrics)
        .where(
          and(
            eq(schema.metrics.userId, userId),
            eq(schema.metrics.labTestKey, query.metricKey)
          )
        )
        .limit(1);
      keyKey = row === undefined ? null : query.metricKey;
    }
  }
  if (idKey === null && keyKey === null) {
    return null;
  }
  if (query.metricId !== undefined && query.metricKey !== undefined && idKey !== keyKey) {
    return { kind: "empty" };
  }
  return { kind: "lab", labTestKey: (idKey ?? keyKey)! };
}

/**
 * A readings page for one Lab Test (docs/designs/lab-results.md, "Agent
 * surface" and "Result identity and the collapse").
 *
 * Reads the readings of every Metric with the key ([labMetricIds], archived
 * Lab Metrics included), archived readings included whatever
 * `includeArchived` says, and collapses the whole key series first: the
 * collapse drops archived rows, and a final outside the date filter must
 * still hide its interim inside it. Then the `provenance`, `source` and
 * date filters, the endpoint's order and the cursor apply, so the cursor
 * pages over the collapsed list and `totalMatched` counts it. Each reading
 * keeps its own `metricId`; no reading carries `trendValue`.
 */
async function listLabMetricReadings(
  db: ServerDatabase,
  {
    userId,
    query,
    fields,
    labTarget
  }: {
    userId: string;
    query: AgentMetricReadingsQuery;
    fields: (typeof AGENT_METRIC_READING_FIELDS)[number][];
    labTarget: LabReadingTarget;
  }
) {
  let rows: MetricReadingRow[] = [];
  if (labTarget.kind === "lab") {
    const ids = await labMetricIds(db, { userId, labTestKey: labTarget.labTestKey });
    rows =
      ids.length === 0
        ? []
        : await db
            .select()
            .from(schema.metricReadings)
            .where(
              and(
                eq(schema.metricReadings.userId, userId),
                inArray(schema.metricReadings.metricId, ids)
              )
            );
  }
  const labTestKey = labTarget.kind === "lab" ? labTarget.labTestKey : "";
  const collapsed = collapseLabResults(
    rows.map((row) => ({
      id: row.id,
      labTestKey,
      lab: row.valueJson?.lab ?? null,
      atTime: readingAnchor(row).toISOString(),
      updatedAt: row.updatedAt.toISOString(),
      deletedAt: row.deletedAt?.toISOString() ?? null,
      row
    }))
  ).map((ref) => ref.row);

  const from = parseOptionalDate(query.from);
  const to = parseOptionalDate(query.to);
  const filtered = collapsed
    .filter((row) => {
      if (query.provenance !== undefined && row.provenance !== query.provenance) {
        return false;
      }
      if (query.source !== undefined && row.source !== query.source) {
        return false;
      }
      const anchor = readingAnchor(row);
      if (from !== null && anchor < from) {
        return false;
      }
      if (to !== null && anchor > to) {
        return false;
      }
      return true;
    })
    .sort(compareReadingListOrder);
  const start = cursorOffset(filtered, query.cursor);
  const page = filtered.slice(start, start + query.limit);

  return AgentMetricReadingsResponseSchema.parse({
    readings: page.map((row) =>
      projectMetricReadingRow(serializeMetricReadingRow(row, []), fields)
    ),
    fields,
    limit: query.limit,
    nextCursor:
      start + page.length >= filtered.length ? null : page[page.length - 1]?.id ?? null,
    totalMatched: filtered.length
  });
}

/**
 * The readings list's order, as its SQL sorts it: `atTime`, then
 * `windowStartedAt` (nulls last, as Postgres sorts ascending), then
 * `updatedAt`, then id by code-unit order.
 */
function compareReadingListOrder(left: MetricReadingRow, right: MetricReadingRow) {
  return (
    compareNullableDates(left.atTime, right.atTime) ||
    compareNullableDates(left.windowStartedAt, right.windowStartedAt) ||
    left.updatedAt.getTime() - right.updatedAt.getTime() ||
    (left.id < right.id ? -1 : left.id > right.id ? 1 : 0)
  );
}

function compareNullableDates(left: Date | null, right: Date | null) {
  if (left === null || right === null) {
    return left === right ? 0 : left === null ? 1 : -1;
  }
  return left.getTime() - right.getTime();
}

function serializeMetricRow(row: MetricRow) {
  const metadata = metricCatalogMetadataForRow(row);
  return AgentMetricSchema.parse({
    id: row.id,
    name: row.name,
    canonicalKey: metadata.canonicalKey,
    aliases: [...metadata.aliases],
    dataClass: metadata.dataClass,
    unit: row.unit,
    valueShape: metricValueShape(row.valueShape),
    metricGroup: row.metricGroup,
    goalType: row.goalType,
    goalTargetValue: row.goalTargetValue,
    enabled: row.enabled,
    pinned: row.pinned,
    sortOrder: row.sortOrder,
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  });
}

function serializeMetricDefinition(metric: MetricDefinition) {
  const metadata = metricCatalogMetadataForDefinition(metric);
  return AgentMetricSchema.parse({
    id: metric.id,
    name: metric.name,
    canonicalKey: metadata.canonicalKey,
    aliases: [...metadata.aliases],
    dataClass: metadata.dataClass,
    unit: metric.unit,
    valueShape: metric.valueShape,
    metricGroup: metric.metricGroup,
    goalType: metric.goalType,
    goalTargetValue: metric.goalTargetValue,
    enabled: metric.enabled,
    pinned: metric.pinned,
    sortOrder: metric.sortOrder,
    updatedAt: metric.updatedAt.toISOString(),
    deletedAt: metric.deletedAt?.toISOString() ?? null
  });
}

function serializeMetricReadingRow(row: MetricReadingRow, warnings: string[]) {
  return AgentMetricReadingSchema.parse({
    id: row.id,
    metricId: row.metricId,
    externalActivityId: row.externalActivityId,
    valueShape: metricValueShape(
      typeof row.valueJson.shape === "string" ? row.valueJson.shape : "scalar"
    ),
    unit: typeof row.valueJson.unit === "string" ? row.valueJson.unit : "unknown",
    valueJson: row.valueJson,
    scalarValue: row.scalarValue,
    scalarEntered: row.scalarEntered,
    atTime: row.atTime?.toISOString() ?? null,
    windowStartedAt: row.windowStartedAt?.toISOString() ?? null,
    windowEndedAt: row.windowEndedAt?.toISOString() ?? null,
    provenance: row.provenance,
    source: row.source,
    externalId: row.externalId,
    comment: row.comment,
    warnings,
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  });
}

function projectMetricRow(
  row: MetricRow,
  fields: readonly (typeof AGENT_METRIC_LIST_FIELDS)[number][]
) {
  const serialized = serializeMetricRow(row);
  return AgentMetricListItemSchema.parse(projectFields(serialized, fields));
}

function projectMetricReadingRow(
  reading: z.infer<typeof AgentMetricReadingSchema>,
  fields: readonly (typeof AGENT_METRIC_READING_FIELDS)[number][]
) {
  return AgentMetricReadingListItemSchema.parse(projectFields(reading, fields));
}

function projectFields<T extends Record<string, unknown>>(
  value: T,
  fields: readonly string[]
) {
  return Object.fromEntries(
    fields
      .filter((field) => field in value)
      .map((field) => [field, value[field]])
  );
}

function resolveMetricFieldSelection(value: string | undefined) {
  return resolveFieldSelection(value, AGENT_METRIC_LIST_FIELDS, ["id", "name"]);
}

function resolveMetricReadingFieldSelection(value: string | undefined) {
  return resolveFieldSelection(value, AGENT_METRIC_READING_FIELDS, [
    "id",
    "metricId"
  ]);
}

function resolveFieldSelection<const T extends readonly string[]>(
  value: string | undefined,
  allFields: T,
  requiredFields: readonly T[number][]
): T[number][] {
  if (value === undefined) {
    return [...allFields];
  }

  return [
    ...new Set<T[number]>([
      ...requiredFields,
      ...(value
        .split(",")
        .map((field) => field.trim())
        .filter((field): field is T[number] =>
          (allFields as readonly string[]).includes(field)
        ) as T[number][])
    ])
  ];
}

function metricResultWithOutcome(
  result: z.infer<typeof AgentMetricBatchWriteMetricResultSchema>,
  outcome: "applied" | "superseded" | "duplicate"
) {
  return AgentMetricBatchWriteMetricResultSchema.parse({
    ...result,
    applied: outcome === "applied",
    outcome
  });
}

function readingResultWithOutcome(
  result: z.infer<typeof AgentMetricBatchWriteReadingResultSchema>,
  outcome: "applied" | "superseded" | "duplicate"
) {
  return AgentMetricBatchWriteReadingResultSchema.parse({
    ...result,
    applied: outcome === "applied",
    outcome
  });
}

function serializePreparedMetricReading({
  reading,
  metricId,
  provenance,
  source,
  valueShape,
  unit,
  valueJson,
  scalarValue,
  scalarEntered,
  atTime,
  windowStartedAt,
  windowEndedAt,
  updatedAt,
  deletedAt
}: {
  reading: AgentMetricBatchWriteReading;
  metricId: string;
  provenance: string;
  source: string;
  valueShape: "scalar" | "structured" | "series";
  unit: string;
  valueJson: Record<string, unknown>;
  scalarValue: number | null;
  scalarEntered: string | null;
  atTime: string | null;
  windowStartedAt: string | null;
  windowEndedAt: string | null;
  updatedAt: Date;
  deletedAt: Date | null;
}) {
  return AgentMetricReadingSchema.parse({
    id: reading.id,
    metricId,
    externalActivityId: reading.externalActivityId,
    valueShape,
    unit,
    valueJson,
    scalarValue,
    scalarEntered,
    atTime,
    windowStartedAt,
    windowEndedAt,
    provenance,
    source,
    externalId: reading.externalId,
    comment: reading.comment,
    warnings: [],
    updatedAt: updatedAt.toISOString(),
    deletedAt: deletedAt?.toISOString() ?? null
  });
}

function metricIssue({
  field,
  itemIndex,
  metricId,
  rule,
  message,
  limit = null
}: {
  field: string;
  itemIndex: number;
  metricId: string;
  rule: string;
  message: string;
  limit?: string | number | null;
}) {
  return AgentMetricBatchWriteIssueSchema.parse({
    field,
    rule,
    message,
    itemIndex,
    metricId,
    readingId: null,
    limit
  });
}

function batchIssue({
  field,
  rule,
  message,
  limit = null
}: {
  field: string;
  rule: string;
  message: string;
  limit?: string | number | null;
}) {
  return AgentMetricBatchWriteIssueSchema.parse({
    field,
    rule,
    message,
    itemIndex: 0,
    metricId: null,
    readingId: null,
    limit
  });
}

function readingIssue({
  field,
  itemIndex,
  metricId,
  readingId,
  rule,
  message,
  limit = null
}: {
  field: string;
  itemIndex: number;
  metricId: string | null;
  readingId: string;
  rule: string;
  message: string;
  limit?: string | number | null;
}) {
  return AgentMetricBatchWriteIssueSchema.parse({
    field,
    rule,
    message,
    itemIndex,
    metricId,
    readingId,
    limit
  });
}

function cursorOffset<T extends { id: string }>(
  rows: readonly T[],
  cursor: string | undefined
) {
  if (cursor === undefined) {
    return 0;
  }

  const index = rows.findIndex((row) => row.id === cursor);
  return index < 0 ? 0 : index + 1;
}

/**
 * The Trend (D5) at each live page Reading that has a scalar value, keyed by
 * Reading id. Each Metric on the page gets its Trend over all of its live
 * Readings, not only the page. `rows` is the list's own read of every Reading
 * the account has, before the query's filters, so it already holds that
 * history and no second query is made; if those filters ever move into SQL,
 * this needs its own read, bounded to the page's Metric ids.
 */
function readingTrendsForPage(
  rows: readonly MetricReadingRow[],
  page: readonly MetricReadingRow[],
  labMetricIdSet: ReadonlySet<string>
) {
  // No Trend for a Lab Metric (docs/designs/lab-results.md, "The display",
  // No Trend): its readings are Lab Results, not a daily series, and an
  // uncollapsed read would smooth an interim and its final together.
  const pageMetricIds = new Set(
    page
      .filter((row) => row.deletedAt === null && !labMetricIdSet.has(row.metricId))
      .map((row) => row.metricId)
  );
  const inputsByMetricId = new Map<string, TrendInput[]>();
  for (const row of rows) {
    if (row.deletedAt !== null || !pageMetricIds.has(row.metricId)) {
      continue;
    }
    const inputs = inputsByMetricId.get(row.metricId) ?? [];
    inputs.push({
      id: row.id,
      at: wholeSecondIso(row.atTime ?? row.windowStartedAt ?? row.updatedAt),
      value: readingScalarValue(row)
    });
    inputsByMetricId.set(row.metricId, inputs);
  }

  const trendByReadingId = new Map<string, number>();
  for (const inputs of inputsByMetricId.values()) {
    for (const point of metricTrend(inputs)) {
      // Finite inputs keep the Trend finite unless the sum overflows; an
      // overflowed value would serialize as null, so it is left off.
      if (Number.isFinite(point.trend)) {
        trendByReadingId.set(point.id, point.trend);
      }
    }
  }
  return trendByReadingId;
}

/**
 * [at] truncated to whole seconds, as ISO-8601. The app stores Reading times
 * as whole Unix seconds, so the Trend is computed at that precision here too:
 * two Readings in the same second are then ordered by id on both sides, and
 * `trendValue` matches the Body card (D5).
 */
function wholeSecondIso(at: Date) {
  return new Date(Math.trunc(at.getTime() / 1000) * 1000).toISOString();
}

/**
 * A Reading's scalar value, the rule the app's `_metricReadingScalarValue`
 * applies: `scalarValue`, or else a numeric `value` key in `valueJson`. Null
 * when it has neither, so a structured, series or malformed Reading is skipped
 * by the Trend rather than failing the read.
 */
function readingScalarValue(row: MetricReadingRow) {
  if (row.scalarValue !== null) {
    return row.scalarValue;
  }
  const value = row.valueJson?.value;
  return typeof value === "number" ? value : null;
}

function readingAnchor(row: MetricReadingRow) {
  return row.atTime ?? row.windowStartedAt ?? row.windowEndedAt ?? row.updatedAt;
}

function parseOptionalDate(value: string | undefined) {
  if (value === undefined) {
    return null;
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

const MAX_FUTURE_CLOCK_SKEW_MS = 5 * 60 * 1000;

function parseIncomingDate(value: string, serverClock: Date) {
  const parsed = parseOptionalDate(value);
  if (parsed === null) {
    return null;
  }
  const maxAcceptedTime = serverClock.getTime() + MAX_FUTURE_CLOCK_SKEW_MS;
  if (parsed.getTime() > maxAcceptedTime) {
    return serverClock;
  }

  return parsed;
}

function parseIncomingNullableDate(value: string, serverClock: Date) {
  return parseIncomingDate(value, serverClock) ?? undefined;
}

function fingerprintAgentMetricRequest(request: AgentMetricBatchWriteRequest) {
  return agentBatchRequestFingerprint(request);
}

function lwwWins(
  incomingUpdatedAt: Date,
  incomingDeviceId: string,
  existingUpdatedAt: Date,
  existingDeviceId: string
) {
  const timestampComparison =
    incomingUpdatedAt.getTime() - existingUpdatedAt.getTime();
  if (timestampComparison !== 0) {
    return timestampComparison > 0;
  }

  return incomingDeviceId > existingDeviceId;
}
