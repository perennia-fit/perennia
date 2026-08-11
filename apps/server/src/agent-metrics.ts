import { createHash } from "node:crypto";
import { createRoute, z } from "@hono/zod-openapi";
import { and, asc, eq, inArray, isNull } from "drizzle-orm";

import {
  agentBatchRequestFingerprint,
  claimAgentBatchReceipt
} from "./agent-batch-receipt.js";
import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
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
    deletedAt: ISO8601StringSchema.nullable().optional()
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
    deletedAt: ISO8601StringSchema.nullable().default(null)
  })
  .openapi("AgentMetricBatchWriteMetric");

const AgentMetricReadingScalarValueSchema = z
  .object({
    shape: z.literal("scalar"),
    entered: z.string().trim().min(1),
    unit: z.string().trim().min(1).optional()
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
    metricId: z.string().min(1),
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
    "Returns a bounded Metric catalogue page for code-mode agents. Metrics describe how Metric Readings should be normalized; derived analytics are still computed on read.",
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
    "Returns normalized Metric Readings for code-mode agents with server-side bounds and filters. Raw Monitoring Series blobs are intentionally out of scope.",
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
    "Authenticated agent write path for Metric definitions and Readings. Readings are normalized with the same Metric normalization module used by imported data, then written atomically with one Activity Log batch and a best-effort sync nudge. Derived metrics, analytics, and repair recalculations are not stored.",
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

type PreparedMetric = {
  id: string;
  updatedAt: Date;
  deletedAt: Date | null;
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

      return AgentMetricReadingsResponseSchema.parse({
        readings: page.map((row) =>
          projectMetricReadingRow(serializeMetricReadingRow(row, []), fields)
        ),
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
        const prepared = await prepareMetricBatch({
          transaction,
          userId,
          deviceId,
          request,
          serverClock
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

          if (existing === undefined) {
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

async function prepareMetricBatch({
  transaction,
  userId,
  deviceId,
  request,
  serverClock
}: {
  transaction: MutationDatabase;
  userId: string;
  deviceId: string;
  request: AgentMetricBatchWriteRequest;
  serverClock: Date;
}): Promise<PreparedMetricBatch> {
  const errors: AgentMetricBatchWriteIssue[] = [];
  const warnings: AgentMetricBatchWriteIssue[] = [];
  const seenMetricIds = new Set<string>();
  const seenReadingIds = new Set<string>();
  const metricIds = [
    ...new Set([
      ...request.metrics.map((metric) => metric.id),
      ...request.readings.map((reading) => reading.metricId)
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
      updatedAt,
      deletedAt
    };
    requestMetricDefinitions.set(metric.id, definition);
    const afterImage = serializeMetricDefinition(definition);
    preparedMetrics.push({
      id: metric.id,
      updatedAt,
      deletedAt,
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
          metricId: reading.metricId,
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
          metricId: reading.metricId,
          rule: "reading_id_not_visible",
          message:
            "Metric Reading is not visible to the authenticated account."
        })
      );
      continue;
    }

    const requestMetric = requestMetricDefinitions.get(reading.metricId);
    const existingMetric = existingMetricRows.get(reading.metricId);
    const metric =
      requestMetric ?? existingMetricDefinition(existingMetric);
    if (
      metric === null ||
      (requestMetric === undefined && existingMetric?.userId !== userId)
    ) {
      errors.push(
        readingIssue({
          field: `readings[${itemIndex}].metricId`,
          itemIndex,
          readingId: reading.id,
          metricId: reading.metricId,
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
          metricId: reading.metricId,
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
          metricId: reading.metricId,
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
          metricId: reading.metricId,
          rule: "metric_reading_normalization_failed",
          message:
            error instanceof Error
              ? error.message
              : "Metric Reading could not be normalized."
        })
      );
      continue;
    }

    for (const warning of normalized.warnings) {
      warnings.push(
        readingIssue({
          field: `readings[${itemIndex}].timeAnchor`,
          itemIndex,
          readingId: reading.id,
          metricId: reading.metricId,
          rule: warning,
          message: warning
        })
      );
    }

    const valueJson = JSON.parse(normalized.valueJson) as Record<string, unknown>;
    const afterImage = serializePreparedMetricReading({
      reading,
      valueShape: normalized.valueShape as "scalar" | "structured" | "series",
      unit: normalized.unit,
      valueJson,
      scalarValue: normalized.scalarValue,
      scalarEntered:
        reading.value.shape === "scalar" ? reading.value.entered.trim() : null,
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
        metricId: reading.metricId,
        externalActivityId: reading.externalActivityId,
        valueJson,
        scalarValue: normalized.scalarValue,
        scalarEntered:
          reading.value.shape === "scalar" ? reading.value.entered.trim() : null,
        atTime:
          normalized.atTime === null ? null : new Date(normalized.atTime),
        windowStartedAt:
          normalized.windowStartedAt === null
            ? null
            : new Date(normalized.windowStartedAt),
        windowEndedAt:
          normalized.windowEndedAt === null
            ? null
            : new Date(normalized.windowEndedAt),
        provenance: reading.provenance,
        source: reading.source,
        externalId: reading.externalId,
        comment: reading.comment,
        updatedAt,
        deletedAt,
        receivedAt: serverClock
      },
      afterImage,
      result: AgentMetricBatchWriteReadingResultSchema.parse({
        id: reading.id,
        metricId: reading.metricId,
        valueShape: normalized.valueShape,
        unit: normalized.unit,
        warnings: normalized.warnings,
        applied: true,
        outcome: "applied"
      })
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

function existingMetricDefinition(row: MetricRow | undefined) {
  if (row === undefined) {
    return null;
  }

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
    metricGroup: row.metricGroup
  });
}

function metricCatalogMetadataForDefinition(
  metric: MetricDefinition
): MetricCatalogMetadata {
  return metricCatalogMetadataForIdentity({
    id: metric.id,
    name: metric.name,
    unit: metric.unit,
    metricGroup: metric.metricGroup
  });
}

function metricCatalogMetadataForIdentity({
  userId,
  id,
  name,
  unit,
  metricGroup
}: {
  userId?: string;
  id: string;
  name: string;
  unit: string;
  metricGroup: string;
}): MetricCatalogMetadata {
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

function metricMatchesMetricKey(
  row: MetricRow,
  userId: string,
  metricKey: string
) {
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

function stableMetricId(userId: string, metricKey: string) {
  return stableScopedId("metric", userId, metricKey);
}

function stableScopedId(prefix: string, ...parts: string[]) {
  return `${prefix}:${hashParts(parts)}`;
}

function hashParts(parts: string[]) {
  const hash = createHash("sha256");
  for (const part of parts) {
    hash.update(part);
    hash.update("\0");
  }

  return hash.digest("hex").slice(0, 32);
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
  reading: z.infer<typeof AgentMetricBatchWriteReadingSchema>;
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
    metricId: reading.metricId,
    externalActivityId: reading.externalActivityId,
    valueShape,
    unit,
    valueJson,
    scalarValue,
    scalarEntered,
    atTime,
    windowStartedAt,
    windowEndedAt,
    provenance: reading.provenance,
    source: reading.source,
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
  metricId: string;
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
