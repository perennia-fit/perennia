import { randomUUID } from "node:crypto";
import { createRoute, z } from "@hono/zod-openapi";
import { and, asc, eq, inArray, isNull, sql } from "drizzle-orm";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import {
  AgentCatalogUnavailableResponseSchema,
  AgentExerciseSchema,
  createDrizzleAgentCatalogStore,
  resolvePlatformExerciseId,
  type AgentExercise
} from "./agent-catalog.js";
import { AgentSetValidationValuesSchema } from "./agent-validation.js";
import {
  ExerciseAnalyticsEngine,
  normalizedMetricValue,
  type AnalyticsPoint,
  type AnalyticsRecord,
  type AnalyticsSet,
  type DimensionId,
  type ExerciseAnalyticsResult,
  type LoggedSetValues,
  type TrainingUnit
} from "./analytics/exercise-analytics.js";
import type { CanonicalSeries } from "./canonical-import.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import { decodeCanonicalSeriesBlob } from "./monitoring-series.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";

export const AGENT_HISTORY_DEFAULT_PAGE_LIMIT = 50;
export const AGENT_HISTORY_MAX_PAGE_LIMIT = 200;
export const AGENT_ANALYTICS_DEFAULT_POINT_LIMIT = 100;
export const AGENT_ANALYTICS_MAX_POINT_LIMIT = 500;
export const AGENT_MONITORING_READS_ACTIVITY_LOG_ENTITY =
  "agent_monitoring_reads";

const DimensionIdSchema = z
  .enum(["load", "reps", "duration", "distance"])
  .openapi("AgentReadDimensionId");

const TrainingUnitSchema = z
  .enum(["kilogram", "pound", "repetition", "second", "kilometer", "mile"])
  .openapi("AgentReadTrainingUnit");

const RecordProfileSchema = z
  .enum([
    "repMax",
    "maxLoad",
    "maxReps",
    "maxDuration",
    "minDuration",
    "maxDistance",
    "fastestPace",
    "minAssistancePerRepCount",
    "completionStreak"
  ])
  .openapi("AgentReadRecordProfile");

const ExerciseAnalyticsProfileSchema = z
  .object({
    type: z.array(DimensionIdSchema).max(4),
    loadMode: z.enum(["added", "assisted"]),
    recordProfile: RecordProfileSchema
  })
  .openapi("AgentReadExerciseAnalyticsProfile");

export const AgentAnalyticsRecordSchema = z
  .object({
    profile: RecordProfileSchema,
    setId: z.string().min(1),
    achievedAt: z.string().min(1),
    sequence: z.number().int().min(0),
    value: z.number(),
    unit: TrainingUnitSchema,
    reps: z.number().int().min(1).optional()
  })
  .openapi("AgentAnalyticsRecord");

const NullableAgentAnalyticsRecordSchema = z
  .union([AgentAnalyticsRecordSchema, z.null()])
  .openapi("NullableAgentAnalyticsRecord");

export const AgentAnalyticsPointSchema = z
  .object({
    setId: z.string().min(1),
    achievedAt: z.string().min(1),
    value: z.number(),
    unit: TrainingUnitSchema
  })
  .openapi("AgentAnalyticsPoint");

export const AgentDerivedSeriesSchema = z
  .object({
    isDefined: z.boolean(),
    points: z.array(AgentAnalyticsPointSchema),
    total: z.number().nullable()
  })
  .openapi("AgentDerivedSeries");

export const AgentRecordCatalogSchema = z
  .object({
    repMaxRecords: z.array(AgentAnalyticsRecordSchema),
    minAssistanceRecords: z.array(AgentAnalyticsRecordSchema),
    maxLoad: NullableAgentAnalyticsRecordSchema,
    maxReps: NullableAgentAnalyticsRecordSchema,
    maxDuration: NullableAgentAnalyticsRecordSchema,
    minDuration: NullableAgentAnalyticsRecordSchema,
    maxDistance: NullableAgentAnalyticsRecordSchema,
    fastestPace: NullableAgentAnalyticsRecordSchema
  })
  .openapi("AgentRecordCatalog");

export const AgentPeriodStatsSchema = z
  .object({
    setCount: z.number().int().min(0),
    firstPerformedAt: z.string().min(1).nullable(),
    lastPerformedAt: z.string().min(1).nullable(),
    totalVolumeKilograms: z.number().nullable(),
    totalReps: z.number().nullable(),
    totalDurationSeconds: z.number().nullable(),
    totalDistanceKilometers: z.number().nullable(),
    maxEstimatedOneRepMaxKilograms: z.number().nullable()
  })
  .openapi("AgentPeriodStats");

export const AgentExerciseAnalyticsResponseSchema = z
  .object({
    exercise: AgentExerciseSchema,
    profile: ExerciseAnalyticsProfileSchema,
    totalSetCount: z.number().int().min(0),
    seriesPointLimit: z.number().int().min(1).max(AGENT_ANALYTICS_MAX_POINT_LIMIT),
    headlineRecord: NullableAgentAnalyticsRecordSchema,
    headlineRecords: z.array(AgentAnalyticsRecordSchema),
    recordCatalog: AgentRecordCatalogSchema,
    estimatedOneRepMax: AgentDerivedSeriesSchema,
    volume: AgentDerivedSeriesSchema,
    maxLoadSeries: AgentDerivedSeriesSchema,
    repMaxSeries: z.array(AgentAnalyticsRecordSchema),
    periodStats: AgentPeriodStatsSchema
  })
  .openapi("AgentExerciseAnalyticsResponse");

export const AgentHistorySetCategorySchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1)
  })
  .openapi("AgentHistorySetCategory");

const NullableAgentHistorySetCategorySchema = z
  .union([AgentHistorySetCategorySchema, z.null()])
  .openapi("NullableAgentHistorySetCategory");

export const AgentHistorySetSchema = z
  .object({
    id: z.string().min(1),
    workoutId: z.string().min(1).nullable(),
    performedAt: z.string().min(1).nullable(),
    updatedAt: z.string().min(1),
    exerciseId: z.string().min(1),
    exerciseName: z.string().min(1).nullable(),
    category: NullableAgentHistorySetCategorySchema,
    position: z.number().int().min(0),
    plannedRestAfter: z.number().int().min(0).nullable(),
    isCompleted: z.boolean(),
    values: AgentSetValidationValuesSchema,
    rpe: z.union([z.string(), z.number()]).nullable(),
    side: z.enum(["left", "right"]).nullable(),
    comment: z.string().nullable()
  })
  .openapi("AgentHistorySet");

export const AgentHistorySetsResponseSchema = z
  .object({
    sets: z.array(AgentHistorySetSchema),
    limit: z.number().int().min(1).max(AGENT_HISTORY_MAX_PAGE_LIMIT),
    nextCursor: z.string().min(1).nullable(),
    totalMatched: z.number().int().min(0)
  })
  .openapi("AgentHistorySetsResponse");

export const AGENT_WORKOUT_LIST_FIELDS = [
  "id",
  "startedAt",
  "endedAt",
  "timezone",
  "comment",
  "setCount",
  "exerciseNames"
] as const;

const AgentWorkoutListFieldSchema = z
  .enum(AGENT_WORKOUT_LIST_FIELDS)
  .openapi("AgentWorkoutListField");

export const AgentWorkoutListItemSchema = z
  .object({
    id: z.string().min(1),
    startedAt: z.string().min(1).optional(),
    endedAt: z.string().min(1).nullable().optional(),
    timezone: z.string().min(1).nullable().optional(),
    comment: z.string().nullable().optional(),
    setCount: z.number().int().min(0).optional(),
    exerciseNames: z.array(z.string().min(1)).optional()
  })
  .openapi("AgentWorkoutListItem");

const workoutListFieldSet = new Set<string>(AGENT_WORKOUT_LIST_FIELDS);

export const AgentWorkoutListQuerySchema = z.object({
  from: z.string().trim().min(1).optional().openapi({
    param: { name: "from", in: "query" },
    description: "Optional inclusive ISO-8601 lower bound for the Workout start."
  }),
  to: z.string().trim().min(1).optional().openapi({
    param: { name: "to", in: "query" },
    description: "Optional inclusive ISO-8601 upper bound for the Workout start."
  }),
  limit: z.coerce
    .number()
    .int()
    .min(1)
    .max(AGENT_HISTORY_MAX_PAGE_LIMIT)
    .default(AGENT_HISTORY_DEFAULT_PAGE_LIMIT)
    .openapi({
      param: { name: "limit", in: "query" },
      description: "Maximum Workout envelopes to return, bounded to 200."
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
          .every((field) => workoutListFieldSet.has(field)),
      "fields must be a comma-separated list of known Workout fields"
    )
    .openapi({
      param: { name: "fields", in: "query" },
      description:
        "Comma-separated list of Workout fields to return. id and startedAt are always returned; omitting fields returns the minimal default."
    })
});

export const AgentWorkoutListResponseSchema = z
  .object({
    workouts: z.array(AgentWorkoutListItemSchema),
    fields: z.array(AgentWorkoutListFieldSchema),
    limit: z.number().int().min(1).max(AGENT_HISTORY_MAX_PAGE_LIMIT),
    nextCursor: z.string().min(1).nullable(),
    totalMatched: z.number().int().min(0)
  })
  .openapi("AgentWorkoutListResponse");

export const AgentWorkoutDetailParamsSchema = z.object({
  workoutId: z.string().min(1).openapi({
    param: { name: "workoutId", in: "path" },
    description: "Stable Workout id."
  })
});

export const AgentWorkoutDetailWorkoutSchema = z
  .object({
    id: z.string().min(1),
    startedAt: z.string().min(1),
    timezone: z.string().min(1).nullable(),
    localDate: z.string().min(1).nullable(),
    endedAt: z.string().min(1).nullable(),
    comment: z.string().nullable(),
    updatedAt: z.string().min(1),
    active: z.boolean()
  })
  .openapi("AgentWorkoutDetailWorkout");

export const AgentWorkoutExerciseSchema = z
  .object({
    id: z.string().min(1),
    exerciseId: z.string().min(1),
    position: z.number().int().min(0),
    active: z.boolean()
  })
  .openapi("AgentWorkoutExercise");

export const AgentWorkoutExerciseGroupMemberSchema = z
  .object({
    id: z.string().min(1),
    workoutExerciseId: z.string().min(1),
    position: z.number().int().min(0),
    active: z.boolean()
  })
  .openapi("AgentWorkoutExerciseGroupMember");

export const AgentWorkoutExerciseGroupSchema = z
  .object({
    id: z.string().min(1),
    name: z.string(),
    colorHex: z.string().min(1),
    position: z.number().int().min(0),
    active: z.boolean(),
    members: z.array(AgentWorkoutExerciseGroupMemberSchema)
  })
  .openapi("AgentWorkoutExerciseGroup");

export const AgentWorkoutExerciseCatalogEntrySchema = z
  .object({
    requestedId: z.string().min(1),
    canonicalId: z.string().min(1).nullable(),
    resolution: z.enum(["matched", "redirected", "unresolved"]),
    name: z.string().min(1).nullable(),
    library: z.enum(["user", "platform"]).nullable(),
    category: NullableAgentHistorySetCategorySchema,
    dimensions: z.array(DimensionIdSchema),
    equipment: z.array(z.string().min(1)),
    loadMode: z.enum(["added", "assisted"]).nullable(),
    recordProfile: z
      .enum([
        "repMax",
        "maxLoad",
        "maxReps",
        "maxDuration",
        "minDuration",
        "maxDistance",
        "fastestPace",
        "minAssistancePerRepCount",
        "completionStreak"
      ])
      .nullable(),
    active: z.boolean().nullable()
  })
  .openapi("AgentWorkoutExerciseCatalogEntry");

export const AgentWorkoutTemplateLinkSchema = z
  .object({
    id: z.string().min(1),
    workoutTemplateId: z.string().min(1),
    routineId: z.string().min(1).nullable(),
    slot: z.union([z.string().min(1), z.number().int().min(0)]).nullable(),
    active: z.boolean()
  })
  .openapi("AgentWorkoutTemplateLink");

export const AgentWorkoutDetailCoverageSchema = z
  .object({
    workoutMetadata: z.enum(["authoritative", "inferred_from_sets"]),
    structure: z.enum([
      "authoritative",
      "template_link_snapshot",
      "unavailable"
    ]),
    exerciseIdentity: z.enum(["complete", "partial", "unavailable"]),
    unresolvedExerciseIds: z.array(z.string().min(1)),
    truncated: z.boolean()
  })
  .openapi("AgentWorkoutDetailCoverage");

export const AgentWorkoutDetailResponseSchema = z
  .object({
    workout: AgentWorkoutDetailWorkoutSchema,
    sets: z.array(AgentHistorySetSchema),
    workoutExercises: z.array(AgentWorkoutExerciseSchema),
    exerciseGroups: z.array(AgentWorkoutExerciseGroupSchema),
    exerciseCatalog: z.array(AgentWorkoutExerciseCatalogEntrySchema),
    templateLink: z.union([AgentWorkoutTemplateLinkSchema, z.null()]),
    coverage: AgentWorkoutDetailCoverageSchema
  })
  .openapi("AgentWorkoutDetailResponse");

export const AgentWorkoutDetailNotFoundResponseSchema = z
  .object({
    code: z.literal("agent_workout_not_found"),
    message: z.string().min(1)
  })
  .openapi("AgentWorkoutDetailNotFoundResponse");

export const AgentMonitoringExternalActivitySchema = z
  .object({
    id: z.string().min(1),
    source: z.string().min(1),
    externalId: z.string().min(1),
    activityType: z.string().min(1),
    startedAt: z.string().min(1),
    endedAt: z.string().min(1),
    timezone: z.string().min(1)
  })
  .strict()
  .openapi("AgentMonitoringExternalActivity");

export const AgentMonitoringSummaryReadingSchema = z
  .object({
    id: z.string().min(1),
    metricId: z.string().min(1),
    metricKey: z.string().min(1),
    unit: z.string().min(1),
    scalarValue: z.number().finite().nullable(),
    scalarEntered: z.string().nullable(),
    atTime: z.string().min(1).nullable(),
    windowStartedAt: z.string().min(1).nullable(),
    windowEndedAt: z.string().min(1).nullable(),
    provenance: z.string().min(1),
    source: z.string().min(1),
    externalId: z.string().min(1).nullable(),
    updatedAt: z.string().min(1)
  })
  .strict()
  .openapi("AgentMonitoringSummaryReading");

export const AgentMonitoringSeriesSummarySchema = z
  .object({
    seriesType: z.string().min(1),
    sampleCount: z.number().int().min(1),
    firstSampleAt: z.string().min(1),
    lastSampleAt: z.string().min(1)
  })
  .strict()
  .openapi("AgentMonitoringSeriesSummary");

export const AgentMonitoringHeartRateZoneSecondsSchema = z
  .object({
    below120: z.number().finite().min(0),
    bpm120To139: z.number().finite().min(0),
    bpm140To159: z.number().finite().min(0),
    bpm160To179: z.number().finite().min(0),
    bpm180Plus: z.number().finite().min(0)
  })
  .strict()
  .openapi("AgentMonitoringHeartRateZoneSeconds");

export const AgentMonitoringHeartRateTrendSchema = z
  .object({
    firstBpm: z.number().finite(),
    lastBpm: z.number().finite(),
    deltaBpm: z.number().finite()
  })
  .strict()
  .openapi("AgentMonitoringHeartRateTrend");

export const AgentMonitoringHeartRateSummarySchema = z
  .object({
    seriesCount: z.number().int().min(1),
    sampleCount: z.number().int().min(1),
    minimumBpm: z.number().finite(),
    averageBpm: z.number().finite(),
    maximumBpm: z.number().finite(),
    zoneSeconds: AgentMonitoringHeartRateZoneSecondsSchema,
    trend: AgentMonitoringHeartRateTrendSchema
  })
  .strict()
  .openapi("AgentMonitoringHeartRateSummary");

const NullableAgentMonitoringHeartRateSummarySchema = z
  .union([AgentMonitoringHeartRateSummarySchema, z.null()])
  .openapi("NullableAgentMonitoringHeartRateSummary");

export const AgentMonitoringRouteSummarySchema = z
  .object({
    seriesCount: z.number().int().min(1),
    sampleCount: z.number().int().min(1),
    distanceKilometers: z.number().finite().min(0),
    durationSeconds: z.number().finite().min(0),
    averagePaceSecondsPerKilometer: z.number().finite().min(0).nullable()
  })
  .strict()
  .openapi("AgentMonitoringRouteSummary");

const NullableAgentMonitoringRouteSummarySchema = z
  .union([AgentMonitoringRouteSummarySchema, z.null()])
  .openapi("NullableAgentMonitoringRouteSummary");

export const AgentMonitoringActivityResponseSchema = z
  .object({
    externalActivity: AgentMonitoringExternalActivitySchema,
    summaryReadings: z.array(AgentMonitoringSummaryReadingSchema),
    seriesSummaries: z.array(AgentMonitoringSeriesSummarySchema),
    heartRate: NullableAgentMonitoringHeartRateSummarySchema,
    route: NullableAgentMonitoringRouteSummarySchema
  })
  .strict()
  .openapi("AgentMonitoringActivityResponse");

export const AgentReadUnavailableResponseSchema = z
  .object({
    code: z.literal("agent_read_unavailable"),
    message: z.string().min(1)
  })
  .openapi("AgentReadUnavailableResponse");

export const AgentReadExerciseNotFoundResponseSchema = z
  .object({
    code: z.literal("agent_exercise_not_found"),
    message: z.string().min(1)
  })
  .openapi("AgentReadExerciseNotFoundResponse");

export const AgentMonitoringActivityNotFoundResponseSchema = z
  .object({
    code: z.literal("agent_monitoring_activity_not_found"),
    message: z.string().min(1)
  })
  .openapi("AgentMonitoringActivityNotFoundResponse");

export const AgentExerciseAnalyticsParamsSchema = z.object({
  exerciseId: z.string().min(1).openapi({
    param: {
      name: "exerciseId",
      in: "path"
    },
    description: "Resolved Exercise id from the agent catalog."
  })
});

export const AgentMonitoringActivityParamsSchema = z.object({
  externalActivityId: z.string().min(1).openapi({
    param: {
      name: "externalActivityId",
      in: "path"
    },
    description: "External Activity id whose Monitoring Data should be summarized."
  })
});

export const AgentExerciseAnalyticsQuerySchema = z.object({
  from: z.string().trim().min(1).optional().openapi({
    param: {
      name: "from",
      in: "query"
    },
    description: "Optional inclusive ISO-8601 lower bound for performedAt."
  }),
  to: z.string().trim().min(1).optional().openapi({
    param: {
      name: "to",
      in: "query"
    },
    description: "Optional inclusive ISO-8601 upper bound for performedAt."
  }),
  maxPoints: z.coerce
    .number()
    .int()
    .min(1)
    .max(AGENT_ANALYTICS_MAX_POINT_LIMIT)
    .default(AGENT_ANALYTICS_DEFAULT_POINT_LIMIT)
    .openapi({
      param: {
        name: "maxPoints",
        in: "query"
      },
      description:
        "Maximum recent points returned for each derived series. Records and period statistics still compute over the full filtered set."
    })
});

export const AgentHistorySetsQuerySchema = z.object({
  exerciseId: z.string().trim().min(1).optional().openapi({
    param: {
      name: "exerciseId",
      in: "query"
    },
    description: "Optional Exercise id filter."
  }),
  category: z.string().trim().min(1).optional().openapi({
    param: {
      name: "category",
      in: "query"
    },
    description: "Optional Category id or name filter."
  }),
  from: z.string().trim().min(1).optional().openapi({
    param: {
      name: "from",
      in: "query"
    },
    description: "Optional inclusive ISO-8601 lower bound for performedAt."
  }),
  to: z.string().trim().min(1).optional().openapi({
    param: {
      name: "to",
      in: "query"
    },
    description: "Optional inclusive ISO-8601 upper bound for performedAt."
  }),
  minLoadKilograms: z.coerce.number().min(0).optional().openapi({
    param: {
      name: "minLoadKilograms",
      in: "query"
    },
    description: "Optional minimum normalized load threshold."
  }),
  minReps: z.coerce.number().min(0).optional().openapi({
    param: {
      name: "minReps",
      in: "query"
    },
    description: "Optional minimum reps threshold."
  }),
  minDurationSeconds: z.coerce.number().min(0).optional().openapi({
    param: {
      name: "minDurationSeconds",
      in: "query"
    },
    description: "Optional minimum duration threshold."
  }),
  minDistanceKilometers: z.coerce.number().min(0).optional().openapi({
    param: {
      name: "minDistanceKilometers",
      in: "query"
    },
    description: "Optional minimum distance threshold."
  }),
  limit: z.coerce
    .number()
    .int()
    .min(1)
    .max(AGENT_HISTORY_MAX_PAGE_LIMIT)
    .default(AGENT_HISTORY_DEFAULT_PAGE_LIMIT)
    .openapi({
      param: {
        name: "limit",
        in: "query"
      },
      description: "Maximum history rows to return, bounded to 200."
    }),
  cursor: z.string().trim().min(1).optional().openapi({
    param: {
      name: "cursor",
      in: "query"
    },
    description: "Opaque cursor returned by the previous page."
  })
});

export const agentExerciseAnalyticsRoute = createRoute({
  method: "get",
  path: "/agent/analytics/exercises/{exerciseId}",
  operationId: "getAgentExerciseAnalytics",
  tags: ["Agent Reads"],
  summary: "Read computed analytics for one Exercise.",
  description:
    "Computes records, derived series, and period statistics on demand from raw logged sets. Derived analytics are never stored or synced.",
  security: [{ bearerAuth: [] }],
  request: {
    params: AgentExerciseAnalyticsParamsSchema,
    query: AgentExerciseAnalyticsQuerySchema
  },
  responses: {
    200: {
      description:
        "Computed analytics for one resolved Exercise over the requested period.",
      content: {
        "application/json": {
          schema: AgentExerciseAnalyticsResponseSchema
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
    404: {
      description: "The Exercise id is not visible to the authenticated account.",
      content: {
        "application/json": {
          schema: AgentReadExerciseNotFoundResponseSchema
        }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key, catalog, or read storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentCatalogUnavailableResponseSchema,
            AgentReadUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export const agentHistorySetsRoute = createRoute({
  method: "get",
  path: "/agent/history/sets",
  operationId: "listAgentHistorySets",
  tags: ["Agent Reads"],
  summary: "List a filtered page of raw logged sets.",
  description:
    "Returns a server-side filtered, bounded history slice for code-mode agents: data-minimizing and bounded by default (limit, cursor, date range), not a raw dump.",
  security: [{ bearerAuth: [] }],
  request: {
    query: AgentHistorySetsQuerySchema
  },
  responses: {
    200: {
      description: "A bounded page of matching logged sets.",
      content: {
        "application/json": {
          schema: AgentHistorySetsResponseSchema
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
      description: "Agent API key or read storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentReadUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export const agentWorkoutListRoute = createRoute({
  method: "get",
  path: "/agent/workouts",
  operationId: "listAgentWorkouts",
  tags: ["Agent Reads"],
  summary: "List a bounded page of Workout envelopes over a date range.",
  description:
    "Returns bounded Workout envelopes from synchronized Workout rows, enriched with Set counts and resolved Exercise names. Legacy Set-only Workouts remain visible through an inferred fallback. Data-minimizing and bounded by default: date-scoped, limit/cursor-paginated, with a minimal default fields projection, never an unbounded dump.",
  security: [{ bearerAuth: [] }],
  request: {
    query: AgentWorkoutListQuerySchema
  },
  responses: {
    200: {
      description: "A bounded page of Workout envelopes.",
      content: {
        "application/json": {
          schema: AgentWorkoutListResponseSchema
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
      description: "Agent API key or read storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentReadUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export const agentWorkoutDetailRoute = createRoute({
  method: "get",
  path: "/agent/workouts/{workoutId}",
  operationId: "getAgentWorkout",
  tags: ["Agent Reads"],
  summary: "Read one Workout with its logged Sets and available structure.",
  description:
    "Returns the caller's Workout, logged Sets, resolved Exercise catalogue entries, Workout Exercises, Exercise Groups, and Template Link. Coverage fields distinguish authoritative synchronized data from legacy information inferred from Sets or a Template Link snapshot, so an agent never mistakes missing structure for an empty Workout.",
  security: [{ bearerAuth: [] }],
  request: {
    params: AgentWorkoutDetailParamsSchema
  },
  responses: {
    200: {
      description:
        "The Workout, its resolved Exercise identities, and explicit data coverage.",
      content: {
        "application/json": {
          schema: AgentWorkoutDetailResponseSchema
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
    404: {
      description: "The Workout id is not visible to the authenticated account.",
      content: {
        "application/json": {
          schema: AgentWorkoutDetailNotFoundResponseSchema
        }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key or read storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentReadUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export const agentMonitoringActivityRoute = createRoute({
  method: "get",
  path: "/agent/monitoring/activities/{externalActivityId}",
  operationId: "getAgentMonitoringActivity",
  tags: ["Agent Reads"],
  summary: "Read data-minimized Monitoring Data summaries for one External Activity.",
  description:
    "Computes Monitoring Summary readings, heart-rate zones, and route distance/pace on demand for code-mode agents. The response intentionally omits raw Monitoring Series blobs, raw GPS coordinates, blob paths, encodings, hashes, and samples.",
  security: [{ bearerAuth: [] }],
  request: {
    params: AgentMonitoringActivityParamsSchema
  },
  responses: {
    200: {
      description:
        "Computed and aggregated Monitoring Data for one External Activity.",
      content: {
        "application/json": {
          schema: AgentMonitoringActivityResponseSchema
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
    404: {
      description:
        "The External Activity id is not visible to the authenticated account.",
      content: {
        "application/json": {
          schema: AgentMonitoringActivityNotFoundResponseSchema
        }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key or read storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentReadUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export type AgentExerciseAnalyticsQuery = z.infer<
  typeof AgentExerciseAnalyticsQuerySchema
>;
export type AgentHistorySetsQuery = z.infer<typeof AgentHistorySetsQuerySchema>;
export type AgentWorkoutListQuery = z.infer<typeof AgentWorkoutListQuerySchema>;
export type AgentWorkoutListPage = z.infer<typeof AgentWorkoutListResponseSchema>;
export type AgentWorkoutDetailResponse = z.infer<
  typeof AgentWorkoutDetailResponseSchema
>;
export type AgentMonitoringActivityParams = z.infer<
  typeof AgentMonitoringActivityParamsSchema
>;
export type AgentMonitoringActivityResponse = z.infer<
  typeof AgentMonitoringActivityResponseSchema
>;
export type AgentReadableLoggedSet = Omit<
  z.infer<typeof AgentHistorySetSchema>,
  "values"
> & {
  values: LoggedSetValues;
  performedAtDate: Date;
  sequence: number;
  workoutEndedAt: string | null;
  workoutTimezone: string | null;
  workoutLocalDate: string | null;
  workoutComment: string | null;
};
export type AgentHistoryPage = z.infer<typeof AgentHistorySetsResponseSchema>;

export type AgentReadStore = {
  listHistory(input: {
    userId: string;
    query: AgentHistorySetsQuery;
  }): Promise<AgentHistoryPage>;
  listWorkouts(input: {
    userId: string;
    query: AgentWorkoutListQuery;
  }): Promise<AgentWorkoutListPage>;
  getWorkout(input: {
    userId: string;
    workoutId: string;
  }): Promise<AgentWorkoutDetailResponse | null>;
  readMonitoringActivity(input: {
    userId: string;
    agentKeyId: string;
    externalActivityId: string;
  }): Promise<AgentMonitoringActivityResponse | null>;
  readExerciseSets(input: {
    userId: string;
    exerciseId: string;
    from?: string;
    to?: string;
  }): Promise<AgentReadableLoggedSet[]>;
};

type LoggedSetRow = {
  id: string;
  payload: Record<string, unknown>;
  updatedAt: Date;
  receivedAt: Date;
};

type AgentMonitoringExternalActivityRow = {
  id: string;
  source: string;
  externalId: string;
  activityType: string;
  startedAt: Date;
  endedAt: Date;
  timezone: string;
};

type AgentMonitoringSummaryReadingRow = {
  id: string;
  metricId: string;
  metricKey: string;
  unit: string;
  scalarValue: number | null;
  scalarEntered: string | null;
  atTime: Date | null;
  windowStartedAt: Date | null;
  windowEndedAt: Date | null;
  provenance: string;
  source: string;
  externalId: string | null;
  updatedAt: Date;
};

type AgentMonitoringSeriesRow = {
  seriesType: string;
  sampleCount: number;
  blob: Uint8Array;
};

type DecodedAgentMonitoringSeriesRow = {
  row: AgentMonitoringSeriesRow;
  series: CanonicalSeries;
};

const dimensions = ["load", "reps", "duration", "distance"] as const;
const units = new Set<TrainingUnit>([
  "kilogram",
  "pound",
  "repetition",
  "second",
  "kilometer",
  "mile"
]);

export function createDrizzleAgentReadStore(db: ServerDatabase): AgentReadStore {
  return {
    async listHistory({ userId, query }) {
      const allSets = await readLiveLoggedSets(db, userId);
      const matching = applyHistoryFilters(allSets, query).sort(
        compareHistoryDescending
      );
      const offset = cursorOffset(matching, query.cursor);
      const page = matching.slice(offset, offset + query.limit);
      const nextOffset = offset + query.limit;

      return AgentHistorySetsResponseSchema.parse({
        sets: page.map(toHistoryResponseSet),
        limit: query.limit,
        nextCursor:
          nextOffset < matching.length ? page[page.length - 1]?.id ?? null : null,
        totalMatched: matching.length
      });
    },
    async listWorkouts({ userId, query }) {
      const fields = resolveWorkoutFieldSelection(query.fields);
      const allSets = await readLiveLoggedSets(db, userId);
      const grouped = await readWorkoutEnvelopes(db, userId, allSets);
      const from = dateValue(query.from);
      const to = dateValue(query.to);
      const matching = grouped
        .filter((workout) => {
          if (from !== null && workout.startedAtDate < from) {
            return false;
          }
          if (to !== null && workout.startedAtDate > to) {
            return false;
          }

          return true;
        })
        .sort(compareWorkoutDescending);
      const offset = cursorOffset(matching, query.cursor);
      const page = matching.slice(offset, offset + query.limit);
      const nextOffset = offset + query.limit;

      return AgentWorkoutListResponseSchema.parse({
        workouts: page.map((workout) => projectWorkout(workout, fields)),
        fields,
        limit: query.limit,
        nextCursor:
          nextOffset < matching.length ? page[page.length - 1]?.id ?? null : null,
        totalMatched: matching.length
      });
    },
    async getWorkout({ userId, workoutId }) {
      const [sets, workoutSession] = await Promise.all([
        readLiveLoggedSets(db, userId, workoutId),
        readWorkoutSession(db, { userId, workoutId })
      ]);
      sets.sort(compareHistoryAscending);
      if (workoutSession === null && sets.length === 0) {
        return null;
      }
      if (workoutSession !== null) {
        return buildAuthoritativeWorkoutDetail({
          db,
          sets,
          userId,
          workoutId,
          workoutSession
        });
      }

      return buildLegacyWorkoutDetail({
        db,
        sets,
        userId,
        workoutId
      });
    },
    async readMonitoringActivity({ userId, agentKeyId, externalActivityId }) {
      const activity = await readExternalActivity(db, {
        externalActivityId,
        userId
      });
      if (activity === null) {
        return null;
      }

      const [summaryReadings, seriesRows] = await Promise.all([
        readMonitoringSummaryReadings(db, { externalActivityId, userId }),
        readAgentMonitoringSeries(db, { externalActivityId, userId })
      ]);
      const response = buildAgentMonitoringActivityResponse({
        activity,
        seriesRows,
        summaryReadings
      });
      await recordAgentMonitoringRead(db, {
        agentKeyId,
        externalActivityId,
        response,
        userId
      });

      return response;
    },
    async readExerciseSets({ userId, exerciseId, from, to }) {
      const allSets = await readLiveLoggedSets(db, userId);
      return applyHistoryFilters(allSets, {
        exerciseId,
        from,
        to,
        limit: AGENT_HISTORY_MAX_PAGE_LIMIT
      }).sort(compareHistoryAscending);
    }
  };
}

export function buildAgentExerciseAnalyticsResponse({
  exercise,
  maxPoints,
  sets
}: {
  exercise: AgentExercise;
  maxPoints: number;
  sets: readonly AgentReadableLoggedSet[];
}) {
  const analyticsSets = sets.map(toAnalyticsSet);
  const engine = new ExerciseAnalyticsEngine();
  const analytics = engine.compute({
    profile: {
      type: exercise.dimensions as DimensionId[],
      loadMode: exercise.loadMode,
      recordProfile: exercise.recordProfile
    },
    sets: analyticsSets
  });

  return AgentExerciseAnalyticsResponseSchema.parse({
    exercise,
    profile: analytics.profile,
    totalSetCount: analyticsSets.length,
    seriesPointLimit: maxPoints,
    headlineRecord: serializeRecord(analytics.headlineRecord),
    headlineRecords: analytics.headlineRecords.map(serializeRecord),
    recordCatalog: serializeRecordCatalog(analytics),
    estimatedOneRepMax: serializeSeries(analytics.estimatedOneRepMax, maxPoints),
    volume: serializeSeries(analytics.volume, maxPoints),
    maxLoadSeries: serializeMaxLoadSeries(analyticsSets, maxPoints),
    repMaxSeries: analytics.recordCatalog.repMaxRecords.map(serializeRecord),
    periodStats: periodStats(analyticsSets, analytics)
  });
}

function buildAgentMonitoringActivityResponse({
  activity,
  seriesRows,
  summaryReadings
}: {
  activity: AgentMonitoringExternalActivityRow;
  seriesRows: readonly AgentMonitoringSeriesRow[];
  summaryReadings: readonly AgentMonitoringSummaryReadingRow[];
}) {
  const decodedSeries = seriesRows.map((row) => ({
    row,
    series: decodeCanonicalSeriesBlob(row.blob)
  }));

  return AgentMonitoringActivityResponseSchema.parse({
    externalActivity: {
      id: activity.id,
      source: activity.source,
      externalId: activity.externalId,
      activityType: activity.activityType,
      startedAt: activity.startedAt.toISOString(),
      endedAt: activity.endedAt.toISOString(),
      timezone: activity.timezone
    },
    summaryReadings: summaryReadings.map((reading) => ({
      id: reading.id,
      metricId: reading.metricId,
      metricKey: reading.metricKey,
      unit: reading.unit,
      scalarValue: reading.scalarValue,
      scalarEntered: reading.scalarEntered,
      atTime: isoOrNull(reading.atTime),
      windowStartedAt: isoOrNull(reading.windowStartedAt),
      windowEndedAt: isoOrNull(reading.windowEndedAt),
      provenance: reading.provenance,
      source: reading.source,
      externalId: reading.externalId,
      updatedAt: reading.updatedAt.toISOString()
    })),
    seriesSummaries: decodedSeries.map(seriesSummary),
    heartRate: heartRateSummary(decodedSeries, activity),
    route: routeSummary(decodedSeries, activity)
  });
}

async function readExternalActivity(
  db: ServerDatabase,
  {
    externalActivityId,
    userId
  }: {
    externalActivityId: string;
    userId: string;
  }
): Promise<AgentMonitoringExternalActivityRow | null> {
  const rows = await db
    .select({
      id: schema.externalActivities.id,
      source: schema.externalActivities.source,
      externalId: schema.externalActivities.externalId,
      activityType: schema.externalActivities.activityType,
      startedAt: schema.externalActivities.startedAt,
      endedAt: schema.externalActivities.endedAt,
      timezone: schema.externalActivities.timezone
    })
    .from(schema.externalActivities)
    .where(
      and(
        eq(schema.externalActivities.userId, userId),
        eq(schema.externalActivities.id, externalActivityId),
        isNull(schema.externalActivities.deletedAt)
      )
    )
    .limit(1);

  return rows[0] ?? null;
}

async function readMonitoringSummaryReadings(
  db: ServerDatabase,
  {
    externalActivityId,
    userId
  }: {
    externalActivityId: string;
    userId: string;
  }
): Promise<AgentMonitoringSummaryReadingRow[]> {
  return db
    .select({
      id: schema.metricReadings.id,
      metricId: schema.metricReadings.metricId,
      metricKey: schema.metrics.name,
      unit: schema.metrics.unit,
      scalarValue: schema.metricReadings.scalarValue,
      scalarEntered: schema.metricReadings.scalarEntered,
      atTime: schema.metricReadings.atTime,
      windowStartedAt: schema.metricReadings.windowStartedAt,
      windowEndedAt: schema.metricReadings.windowEndedAt,
      provenance: schema.metricReadings.provenance,
      source: schema.metricReadings.source,
      externalId: schema.metricReadings.externalId,
      updatedAt: schema.metricReadings.updatedAt
    })
    .from(schema.metricReadings)
    .innerJoin(schema.metrics, eq(schema.metricReadings.metricId, schema.metrics.id))
    .where(
      and(
        eq(schema.metricReadings.userId, userId),
        eq(schema.metricReadings.externalActivityId, externalActivityId),
        isNull(schema.metricReadings.deletedAt),
        isNull(schema.metrics.deletedAt)
      )
    )
    .orderBy(asc(schema.metricReadings.windowStartedAt), asc(schema.metricReadings.id));
}

async function readAgentMonitoringSeries(
  db: ServerDatabase,
  {
    externalActivityId,
    userId
  }: {
    externalActivityId: string;
    userId: string;
  }
): Promise<AgentMonitoringSeriesRow[]> {
  return db
    .select({
      seriesType: schema.monitoringSeries.seriesType,
      sampleCount: schema.monitoringSeries.sampleCount,
      blob: schema.monitoringSeries.blob
    })
    .from(schema.monitoringSeries)
    .where(
      and(
        eq(schema.monitoringSeries.userId, userId),
        eq(schema.monitoringSeries.externalActivityId, externalActivityId),
        isNull(schema.monitoringSeries.deletedAt)
      )
    )
    .orderBy(asc(schema.monitoringSeries.seriesType), asc(schema.monitoringSeries.id));
}

async function recordAgentMonitoringRead(
  db: ServerDatabase,
  {
    agentKeyId,
    externalActivityId,
    response,
    userId
  }: {
    agentKeyId: string;
    externalActivityId: string;
    response: AgentMonitoringActivityResponse;
    userId: string;
  }
) {
  const occurredAt = new Date();
  await db.insert(schema.activityLog).values({
    id: `agent-monitoring-read:${randomUUID()}`,
    userId,
    actor: "agent",
    batchId: `agent-monitoring-read:${agentKeyId}:${occurredAt.toISOString()}`,
    entityTable: AGENT_MONITORING_READS_ACTIVITY_LOG_ENTITY,
    entityId: externalActivityId,
    beforeImage: null,
    afterImage: {
      externalActivityId,
      keyId: agentKeyId,
      routeSummaryReturned: response.route !== null,
      heartRateSummaryReturned: response.heartRate !== null,
      summaryReadingCount: response.summaryReadings.length,
      seriesTypes: [...new Set(response.seriesSummaries.map((row) => row.seriesType))]
    },
    occurredAt,
    createdAt: occurredAt
  });
}

function seriesSummary({ row, series }: DecodedAgentMonitoringSeriesRow) {
  const first = series.samples[0];
  const last = series.samples[series.samples.length - 1];

  return AgentMonitoringSeriesSummarySchema.parse({
    seriesType: row.seriesType,
    sampleCount: row.sampleCount,
    firstSampleAt: sampleAt(series, first).toISOString(),
    lastSampleAt: sampleAt(series, last).toISOString()
  });
}

function heartRateSummary(
  decodedSeries: readonly DecodedAgentMonitoringSeriesRow[],
  activity: AgentMonitoringExternalActivityRow
) {
  const heartRateSeries = decodedSeries.filter(
    ({ row }) => row.seriesType === "heartRate"
  );
  const samples = heartRateSeries
    .flatMap(({ series }) =>
      series.samples.flatMap((sample) => {
        const value = heartRateValue(sample.value);
        return value === null
          ? []
          : [{ at: sampleAt(series, sample), offsetSeconds: sample.offsetSeconds, value }];
      })
    )
    .sort((left, right) => left.at.getTime() - right.at.getTime());

  if (samples.length === 0) {
    return null;
  }

  const values = samples.map((sample) => sample.value);
  const first = samples[0];
  const last = samples[samples.length - 1];

  return AgentMonitoringHeartRateSummarySchema.parse({
    seriesCount: heartRateSeries.length,
    sampleCount: samples.length,
    minimumBpm: Math.min(...values),
    averageBpm: canonicalNumber(
      values.reduce((total, value) => total + value, 0) / values.length
    ),
    maximumBpm: Math.max(...values),
    zoneSeconds: heartRateZoneSeconds(heartRateSeries, activity),
    trend: {
      firstBpm: first.value,
      lastBpm: last.value,
      deltaBpm: canonicalNumber(last.value - first.value)
    }
  });
}

function heartRateZoneSeconds(
  heartRateSeries: readonly DecodedAgentMonitoringSeriesRow[],
  activity: AgentMonitoringExternalActivityRow
) {
  const zoneSeconds = {
    below120: 0,
    bpm120To139: 0,
    bpm140To159: 0,
    bpm160To179: 0,
    bpm180Plus: 0
  };
  const activityStartMs = activity.startedAt.getTime();
  const activityEndMs = activity.endedAt.getTime();

  for (const { series } of heartRateSeries) {
    const samples = series.samples
      .flatMap((sample) => {
        const value = heartRateValue(sample.value);
        return value === null
          ? []
          : [{ at: sampleAt(series, sample), value }];
      })
      .sort((left, right) => left.at.getTime() - right.at.getTime());

    for (const [index, sample] of samples.entries()) {
      const nextSample = samples[index + 1];
      const intervalStartMs = Math.max(sample.at.getTime(), activityStartMs);
      const intervalEndMs = Math.min(
        nextSample?.at.getTime() ?? activityEndMs,
        activityEndMs
      );
      const durationSeconds = Math.max(
        0,
        (intervalEndMs - intervalStartMs) / 1000
      );
      const bucket = heartRateZoneBucket(sample.value);
      zoneSeconds[bucket] += durationSeconds;
    }
  }

  return AgentMonitoringHeartRateZoneSecondsSchema.parse({
    below120: canonicalNumber(zoneSeconds.below120),
    bpm120To139: canonicalNumber(zoneSeconds.bpm120To139),
    bpm140To159: canonicalNumber(zoneSeconds.bpm140To159),
    bpm160To179: canonicalNumber(zoneSeconds.bpm160To179),
    bpm180Plus: canonicalNumber(zoneSeconds.bpm180Plus)
  });
}

function routeSummary(
  decodedSeries: readonly DecodedAgentMonitoringSeriesRow[],
  activity: AgentMonitoringExternalActivityRow
) {
  const locationSeries = decodedSeries.filter(
    ({ row }) => row.seriesType === "location"
  );
  const locationSamples = locationSeries.flatMap(({ series }) =>
    series.samples.flatMap((sample) => {
      const value = locationValue(sample.value);
      return value === null ? [] : [{ ...value, at: sampleAt(series, sample) }];
    })
  );

  if (locationSamples.length === 0) {
    return null;
  }

  let distanceKilometers = 0;
  for (const { series } of locationSeries) {
    const samples = series.samples
      .flatMap((sample) => {
        const value = locationValue(sample.value);
        return value === null
          ? []
          : [{ ...value, at: sampleAt(series, sample) }];
      })
      .sort((left, right) => left.at.getTime() - right.at.getTime());
    for (let index = 1; index < samples.length; index += 1) {
      distanceKilometers += haversineKilometers(samples[index - 1], samples[index]);
    }
  }

  const durationSeconds = Math.max(
    0,
    (activity.endedAt.getTime() - activity.startedAt.getTime()) / 1000
  );

  return AgentMonitoringRouteSummarySchema.parse({
    seriesCount: locationSeries.length,
    sampleCount: locationSamples.length,
    distanceKilometers: canonicalNumber(distanceKilometers),
    durationSeconds: canonicalNumber(durationSeconds),
    averagePaceSecondsPerKilometer:
      distanceKilometers > 0
        ? canonicalNumber(durationSeconds / distanceKilometers)
        : null
  });
}

async function readLiveLoggedSets(
  db: ServerDatabase,
  userId: string,
  workoutId?: string
): Promise<AgentReadableLoggedSet[]> {
  const filters = [
    eq(schema.loggedSets.userId, userId),
    isNull(schema.loggedSets.deletedAt)
  ];
  if (workoutId !== undefined) {
    filters.push(
      sql`${schema.loggedSets.payload} ->> 'workout_id' = ${workoutId}`
    );
  }
  const rows = await db
    .select({
      id: schema.loggedSets.id,
      payload: schema.loggedSets.payload,
      updatedAt: schema.loggedSets.updatedAt,
      receivedAt: schema.loggedSets.receivedAt
    })
    .from(schema.loggedSets)
    .where(and(...filters))
    .orderBy(asc(schema.loggedSets.receivedAt), asc(schema.loggedSets.id));

  const mappedSets = rows.flatMap((row) => {
    const mapped = mapLoggedSetRow(row);
    return mapped === null ? [] : [mapped];
  });
  const requestedExerciseIds = [
    ...new Set(mappedSets.map((set) => set.exerciseId))
  ];
  const catalog = createDrizzleAgentCatalogStore(db);
  const exercises = await catalog.getExercisesByIds({
    userId,
    exerciseIds: requestedExerciseIds
  });
  const exercisesById = new Map(
    exercises.map((exercise) => [exercise.id, exercise])
  );

  return mappedSets.map((set) => {
    const exercise =
      exercisesById.get(resolvePlatformExerciseId(set.exerciseId)) ?? null;
    return {
      ...set,
      exerciseName: set.exerciseName ?? exercise?.name ?? null,
      category: set.category ?? exercise?.category ?? null
    };
  });
}

function mapLoggedSetRow(row: LoggedSetRow): AgentReadableLoggedSet | null {
  const payload = row.payload;
  const exerciseId = stringValue(payload.exercise_id);
  if (exerciseId === null) {
    return null;
  }

  const performedAt = dateValue(payload.performed_at);
  const effectivePerformedAt =
    performedAt ?? dateValue(payload.workout_started_at) ?? row.updatedAt;
  const categoryId =
    stringValue(payload.exercise_category_id) ?? stringValue(payload.category_id);
  const categoryName =
    stringValue(payload.exercise_category_name) ??
    stringValue(payload.category_name) ??
    categoryId;

  return {
    id: row.id,
    workoutId: stringValue(payload.workout_id),
    performedAt: performedAt?.toISOString() ?? null,
    performedAtDate: effectivePerformedAt,
    updatedAt: row.updatedAt.toISOString(),
    exerciseId,
    exerciseName:
      stringValue(payload.exercise_name) ?? stringValue(payload.exercise_query),
    category:
      categoryId === null || categoryName === null
        ? null
        : { id: categoryId, name: categoryName },
    position: integerValue(payload.position) ?? 0,
    sequence: integerValue(payload.position) ?? 0,
    plannedRestAfter: integerValue(payload.planned_rest_after),
    isCompleted: booleanValue(payload.is_completed) ?? true,
    values: loggedSetValues(payload),
    rpe: rpeValue(payload.rpe),
    side: sideValue(payload.side),
    comment: nullableString(payload.comment),
    workoutEndedAt: stringValue(payload.workout_ended_at),
    workoutTimezone: stringValue(payload.workout_timezone),
    workoutLocalDate: stringValue(payload.workout_local_date),
    workoutComment: nullableString(payload.workout_comment)
  };
}

function loggedSetValues(payload: Record<string, unknown>): LoggedSetValues {
  const nested = payload.values;
  if (isRecord(nested)) {
    const parsed: LoggedSetValues = {};
    for (const dimension of dimensions) {
      const value = parseDimensionValue(nested[dimension]);
      if (value !== undefined) {
        parsed[dimension] = value;
      }
    }

    return parsed;
  }

  const parsed: LoggedSetValues = {};
  for (const dimension of dimensions) {
    const entered = stringValue(payload[`${dimension}_entered`]);
    const unit = unitValue(payload[`${dimension}_unit`]);
    if (entered !== null && unit !== null) {
      parsed[dimension] = { entered, unit };
    }
  }

  return parsed;
}

function parseDimensionValue(value: unknown) {
  if (!isRecord(value)) {
    return undefined;
  }

  const entered = stringValue(value.entered);
  const unit = unitValue(value.unit);
  return entered === null || unit === null ? undefined : { entered, unit };
}

function applyHistoryFilters(
  sets: readonly AgentReadableLoggedSet[],
  query: Partial<AgentHistorySetsQuery>
) {
  const from = dateValue(query.from);
  const to = dateValue(query.to);
  const category = query.category?.trim().toLocaleLowerCase("en-US");

  return sets.filter((set) => {
    if (query.exerciseId !== undefined && set.exerciseId !== query.exerciseId) {
      return false;
    }
    if (category !== undefined) {
      const categoryId = set.category?.id.toLocaleLowerCase("en-US");
      const categoryName = set.category?.name.toLocaleLowerCase("en-US");
      if (categoryId !== category && categoryName !== category) {
        return false;
      }
    }
    if (from !== null && set.performedAtDate < from) {
      return false;
    }
    if (to !== null && set.performedAtDate > to) {
      return false;
    }

    return (
      passesMinimum(set.values.load, "load", "kilogram", query.minLoadKilograms) &&
      passesMinimum(set.values.reps, "reps", "repetition", query.minReps) &&
      passesMinimum(
        set.values.duration,
        "duration",
        "second",
        query.minDurationSeconds
      ) &&
      passesMinimum(
        set.values.distance,
        "distance",
        "kilometer",
        query.minDistanceKilometers
      )
    );
  });
}

function passesMinimum(
  value: LoggedSetValues[DimensionId],
  dimension: DimensionId,
  unit: TrainingUnit,
  minimum: number | undefined
) {
  if (minimum === undefined) {
    return true;
  }

  const normalized = normalizedMetricValue(value, dimension, unit);
  return normalized !== null && normalized >= minimum;
}

function toAnalyticsSet(set: AgentReadableLoggedSet): AnalyticsSet {
  return {
    id: set.id,
    performedAt: set.performedAtDate,
    sequence: set.sequence,
    values: set.values
  };
}

function toHistoryResponseSet(set: AgentReadableLoggedSet) {
  return AgentHistorySetSchema.parse({
    id: set.id,
    workoutId: set.workoutId,
    performedAt: set.performedAt,
    updatedAt: set.updatedAt,
    exerciseId: set.exerciseId,
    exerciseName: set.exerciseName,
    category: set.category,
    position: set.position,
    plannedRestAfter: set.plannedRestAfter,
    isCompleted: set.isCompleted,
    values: set.values,
    rpe: set.rpe,
    side: set.side,
    comment: set.comment
  });
}

type OpaqueWorkoutRow = {
  id: string;
  payload: Record<string, unknown>;
  updatedAt: Date;
  deletedAt: Date | null;
};

async function readWorkoutSession(
  db: ServerDatabase,
  {
    userId,
    workoutId
  }: {
    userId: string;
    workoutId: string;
  }
): Promise<OpaqueWorkoutRow | null> {
  const rows = await db
    .select({
      id: schema.workoutSessions.id,
      payload: schema.workoutSessions.payload,
      updatedAt: schema.workoutSessions.updatedAt,
      deletedAt: schema.workoutSessions.deletedAt
    })
    .from(schema.workoutSessions)
    .where(
      and(
        eq(schema.workoutSessions.userId, userId),
        eq(schema.workoutSessions.id, workoutId)
      )
    )
    .limit(1);

  return rows[0] ?? null;
}

async function buildAuthoritativeWorkoutDetail({
  db,
  sets,
  userId,
  workoutId,
  workoutSession
}: {
  db: ServerDatabase;
  sets: readonly AgentReadableLoggedSet[];
  userId: string;
  workoutId: string;
  workoutSession: OpaqueWorkoutRow;
}): Promise<AgentWorkoutDetailResponse> {
  const [structure, templateLinkRow] = await Promise.all([
    readAuthoritativeWorkoutStructure(db, { userId, workoutId }),
    readWorkoutTemplateLink(db, { userId, workoutId })
  ]);
  const structureIsAuthoritative =
    structure.workoutExercises.length > 0 || sets.length === 0;
  const workoutExercises = structureIsAuthoritative
    ? structure.workoutExercises
    : inferredWorkoutExercises(workoutId, sets);
  const exerciseGroups = structureIsAuthoritative
    ? structure.exerciseGroups
    : [];
  const requestedExerciseIds = [
    ...new Set([
      ...sets.map((set) => set.exerciseId),
      ...workoutExercises.map((exercise) => exercise.exerciseId)
    ])
  ];
  const exerciseCatalog = await workoutExerciseCatalog(db, {
    userId,
    requestedExerciseIds
  });
  const unresolvedExerciseIds = exerciseCatalog
    .filter((entry) => entry.resolution === "unresolved")
    .map((entry) => entry.requestedId);
  const startedAt =
    dateValue(workoutSession.payload.started_at) ??
    sets[0]?.performedAtDate ??
    workoutSession.updatedAt;

  return AgentWorkoutDetailResponseSchema.parse({
    workout: {
      id: workoutId,
      startedAt: startedAt.toISOString(),
      timezone: stringValue(workoutSession.payload.timezone),
      localDate:
        stringValue(workoutSession.payload.local_date) ??
        startedAt.toISOString().slice(0, 10),
      endedAt:
        dateValue(workoutSession.payload.ended_at)?.toISOString() ?? null,
      comment: nullableString(workoutSession.payload.comment),
      updatedAt: workoutSession.updatedAt.toISOString(),
      active:
        workoutSession.deletedAt === null &&
        payloadIsActive(workoutSession.payload)
    },
    sets: sets.map(toHistoryResponseSet),
    workoutExercises,
    exerciseGroups,
    exerciseCatalog,
    templateLink: templateLinkFromPayload(templateLinkRow),
    coverage: {
      workoutMetadata: "authoritative",
      structure: structureIsAuthoritative ? "authoritative" : "unavailable",
      exerciseIdentity:
        requestedExerciseIds.length === 0 ||
        unresolvedExerciseIds.length === 0
          ? "complete"
          : unresolvedExerciseIds.length === requestedExerciseIds.length
            ? "unavailable"
            : "partial",
      unresolvedExerciseIds,
      truncated: false
    }
  });
}

async function readAuthoritativeWorkoutStructure(
  db: ServerDatabase,
  {
    userId,
    workoutId
  }: {
    userId: string;
    workoutId: string;
  }
) {
  const [workoutExerciseRows, exerciseGroupRows] = await Promise.all([
    db
      .select({
        id: schema.workoutExercises.id,
        payload: schema.workoutExercises.payload,
        deletedAt: schema.workoutExercises.deletedAt
      })
      .from(schema.workoutExercises)
      .where(
        and(
          eq(schema.workoutExercises.userId, userId),
          sql`${schema.workoutExercises.payload} ->> 'workout_id' = ${workoutId}`
        )
      ),
    db
      .select({
        id: schema.exerciseGroups.id,
        payload: schema.exerciseGroups.payload,
        deletedAt: schema.exerciseGroups.deletedAt
      })
      .from(schema.exerciseGroups)
      .where(
        and(
          eq(schema.exerciseGroups.userId, userId),
          sql`${schema.exerciseGroups.payload} ->> 'workout_id' = ${workoutId}`
        )
      )
  ]);
  const groupIds = exerciseGroupRows.map((row) => row.id);
  const memberRows =
    groupIds.length === 0
      ? []
      : await db
          .select({
            id: schema.exerciseGroupMembers.id,
            payload: schema.exerciseGroupMembers.payload,
            deletedAt: schema.exerciseGroupMembers.deletedAt
          })
          .from(schema.exerciseGroupMembers)
          .where(
            and(
              eq(schema.exerciseGroupMembers.userId, userId),
              inArray(
                sql<string>`${schema.exerciseGroupMembers.payload} ->> 'group_id'`,
                groupIds
              )
            )
          );
  const workoutExercises = workoutExerciseRows
    .flatMap((row) => {
      const exerciseId = stringValue(row.payload.exercise_id);
      if (exerciseId === null) {
        return [];
      }
      return [
        AgentWorkoutExerciseSchema.parse({
          id: row.id,
          exerciseId,
          position: integerValue(row.payload.position) ?? 0,
          active: row.deletedAt === null && payloadIsActive(row.payload)
        })
      ];
    })
    .sort(
      (left, right) =>
        left.position - right.position || left.id.localeCompare(right.id)
    );
  const exerciseGroups = exerciseGroupRows
    .map((row) =>
      AgentWorkoutExerciseGroupSchema.parse({
        id: row.id,
        name: nullableString(row.payload.name) ?? "",
        colorHex: stringValue(row.payload.color_hex) ?? "#000000",
        position: integerValue(row.payload.position) ?? 0,
        active: row.deletedAt === null && payloadIsActive(row.payload),
        members: memberRows
          .filter((member) => stringValue(member.payload.group_id) === row.id)
          .flatMap((member) => {
            const workoutExerciseId = stringValue(
              member.payload.workout_exercise_id
            );
            if (workoutExerciseId === null) {
              return [];
            }
            return [
              AgentWorkoutExerciseGroupMemberSchema.parse({
                id: member.id,
                workoutExerciseId,
                position: integerValue(member.payload.position) ?? 0,
                active:
                  member.deletedAt === null && payloadIsActive(member.payload)
              })
            ];
          })
          .sort(
            (left, right) =>
              left.position - right.position || left.id.localeCompare(right.id)
          )
      })
    )
    .sort(
      (left, right) =>
        left.position - right.position || left.id.localeCompare(right.id)
    );

  return { workoutExercises, exerciseGroups };
}

function inferredWorkoutExercises(
  workoutId: string,
  sets: readonly AgentReadableLoggedSet[]
) {
  const firstPositionByExerciseId = new Map<string, number>();
  for (const set of sets) {
    const current = firstPositionByExerciseId.get(set.exerciseId);
    if (current === undefined || set.position < current) {
      firstPositionByExerciseId.set(set.exerciseId, set.position);
    }
  }
  return [...firstPositionByExerciseId.entries()]
    .sort(
      ([leftId, leftPosition], [rightId, rightPosition]) =>
        leftPosition - rightPosition || leftId.localeCompare(rightId)
    )
    .map(([exerciseId], position) =>
      AgentWorkoutExerciseSchema.parse({
        id: `inferred:${workoutId}:${exerciseId}`,
        exerciseId,
        position,
        active: true
      })
    );
}

async function buildLegacyWorkoutDetail({
  db,
  sets,
  userId,
  workoutId
}: {
  db: ServerDatabase;
  sets: readonly AgentReadableLoggedSet[];
  userId: string;
  workoutId: string;
}): Promise<AgentWorkoutDetailResponse> {
  const earliestSet = sets.reduce((earliest, set) =>
    set.performedAtDate < earliest.performedAtDate ? set : earliest
  );
  const latestUpdatedAt = sets.reduce(
    (latest, set) =>
      set.updatedAt.localeCompare(latest) > 0 ? set.updatedAt : latest,
    sets[0]!.updatedAt
  );
  const templateLinkRow = await readWorkoutTemplateLink(db, {
    userId,
    workoutId
  });
  const snapshot = templateLinkRow?.payload ?? null;
  const workoutExercises = snapshotWorkoutExercises(snapshot);
  const exerciseGroups = snapshotExerciseGroups(snapshot);
  const requestedExerciseIds = [
    ...new Set([
      ...sets.map((set) => set.exerciseId),
      ...workoutExercises.map((exercise) => exercise.exerciseId)
    ])
  ];
  const exerciseCatalog = await workoutExerciseCatalog(db, {
    userId,
    requestedExerciseIds
  });
  const unresolvedExerciseIds = exerciseCatalog
    .filter((entry) => entry.resolution === "unresolved")
    .map((entry) => entry.requestedId);
  const exerciseIdentity =
    unresolvedExerciseIds.length === 0
      ? "complete"
      : unresolvedExerciseIds.length === requestedExerciseIds.length
        ? "unavailable"
        : "partial";

  return AgentWorkoutDetailResponseSchema.parse({
    workout: {
      id: workoutId,
      startedAt: earliestSet.performedAtDate.toISOString(),
      timezone: earliestSet.workoutTimezone,
      localDate:
        earliestSet.workoutLocalDate ??
        earliestSet.performedAtDate.toISOString().slice(0, 10),
      endedAt: earliestSet.workoutEndedAt,
      comment: earliestSet.workoutComment,
      updatedAt: latestUpdatedAt,
      active: true
    },
    sets: sets.map(toHistoryResponseSet),
    workoutExercises,
    exerciseGroups,
    exerciseCatalog,
    templateLink: templateLinkFromPayload(templateLinkRow),
    coverage: {
      workoutMetadata: "inferred_from_sets",
      structure:
        workoutExercises.length > 0 || exerciseGroups.length > 0
          ? "template_link_snapshot"
          : "unavailable",
      exerciseIdentity,
      unresolvedExerciseIds,
      truncated: false
    }
  });
}

async function readWorkoutTemplateLink(
  db: ServerDatabase,
  {
    userId,
    workoutId
  }: {
    userId: string;
    workoutId: string;
  }
) {
  const rows = await db
    .select({
      id: schema.templateLinks.id,
      payload: schema.templateLinks.payload,
      deletedAt: schema.templateLinks.deletedAt
    })
    .from(schema.templateLinks)
    .where(
      and(
        eq(schema.templateLinks.userId, userId),
        sql`${schema.templateLinks.payload} ->> 'workout_id' = ${workoutId}`,
        isNull(schema.templateLinks.deletedAt)
      )
    )
    .limit(1);

  return rows[0] ?? null;
}

function templateLinkFromPayload(
  row:
    | {
        id: string;
        payload: Record<string, unknown>;
        deletedAt: Date | null;
      }
    | null
) {
  if (row === null) {
    return null;
  }
  const workoutTemplateId = stringValue(row.payload.workout_template_id);
  if (workoutTemplateId === null) {
    return null;
  }
  const slot =
    integerValue(row.payload.slot) ?? stringValue(row.payload.slot) ?? null;

  return AgentWorkoutTemplateLinkSchema.parse({
    id: row.id,
    workoutTemplateId,
    routineId: stringValue(row.payload.routine_id),
    slot,
    active: row.deletedAt === null && payloadIsActive(row.payload)
  });
}

function snapshotWorkoutExercises(payload: Record<string, unknown> | null) {
  const rows = payload?.workout_exercises;
  if (!Array.isArray(rows)) {
    return [];
  }

  return rows.flatMap((value) => {
    if (!isRecord(value)) {
      return [];
    }
    const id = stringValue(value.id);
    const exerciseId = stringValue(value.exercise_id);
    if (id === null || exerciseId === null) {
      return [];
    }

    return [
      AgentWorkoutExerciseSchema.parse({
        id,
        exerciseId,
        position: integerValue(value.position) ?? 0,
        active: payloadIsActive(value)
      })
    ];
  });
}

function snapshotExerciseGroups(payload: Record<string, unknown> | null) {
  const groupRows = payload?.workout_exercise_groups;
  const memberRows = payload?.workout_exercise_group_members;
  if (!Array.isArray(groupRows)) {
    return [];
  }
  const members = Array.isArray(memberRows) ? memberRows : [];

  return groupRows.flatMap((value) => {
    if (!isRecord(value)) {
      return [];
    }
    const id = stringValue(value.id);
    if (id === null) {
      return [];
    }
    const groupMembers = members.flatMap((member) => {
      if (!isRecord(member) || stringValue(member.group_id) !== id) {
        return [];
      }
      const memberId = stringValue(member.id);
      const workoutExerciseId = stringValue(member.workout_exercise_id);
      if (memberId === null || workoutExerciseId === null) {
        return [];
      }

      return [
        AgentWorkoutExerciseGroupMemberSchema.parse({
          id: memberId,
          workoutExerciseId,
          position: integerValue(member.position) ?? 0,
          active: payloadIsActive(member)
        })
      ];
    });

    return [
      AgentWorkoutExerciseGroupSchema.parse({
        id,
        name: nullableString(value.name) ?? "",
        colorHex: stringValue(value.color_hex) ?? "#000000",
        position: integerValue(value.position) ?? 0,
        active: payloadIsActive(value),
        members: groupMembers.sort(
          (left, right) =>
            left.position - right.position || left.id.localeCompare(right.id)
        )
      })
    ];
  });
}

async function workoutExerciseCatalog(
  db: ServerDatabase,
  {
    userId,
    requestedExerciseIds
  }: {
    userId: string;
    requestedExerciseIds: readonly string[];
  }
) {
  const catalog = createDrizzleAgentCatalogStore(db);
  const resolved = await Promise.all(
    requestedExerciseIds.map(async (requestedId) => ({
      requestedId,
      exercise: await catalog.getExerciseById({
        userId,
        exerciseId: requestedId
      })
    }))
  );

  return resolved.map(({ requestedId, exercise }) =>
    AgentWorkoutExerciseCatalogEntrySchema.parse({
      requestedId,
      canonicalId: exercise?.id ?? null,
      resolution:
        exercise === null
          ? "unresolved"
          : exercise.id === requestedId
            ? "matched"
            : "redirected",
      name: exercise?.name ?? null,
      library: exercise?.library ?? null,
      category: exercise?.category ?? null,
      dimensions: exercise?.dimensions ?? [],
      equipment: exercise?.equipment ?? [],
      loadMode: exercise?.loadMode ?? null,
      recordProfile: exercise?.recordProfile ?? null,
      active: exercise?.active ?? null
    })
  );
}

function payloadIsActive(payload: Record<string, unknown>) {
  return payload.deleted_at === null || payload.deleted_at === undefined;
}

type WorkoutEnvelope = {
  id: string;
  startedAt: string;
  startedAtDate: Date;
  endedAt: string | null;
  timezone: string | null;
  comment: string | null;
  setCount: number;
  exerciseNames: string[];
};

async function readWorkoutEnvelopes(
  db: ServerDatabase,
  userId: string,
  sets: readonly AgentReadableLoggedSet[]
): Promise<WorkoutEnvelope[]> {
  const inferred = groupSetsByWorkout(sets);
  const inferredById = new Map(inferred.map((workout) => [workout.id, workout]));
  const sessionRows = await db
    .select({
      id: schema.workoutSessions.id,
      payload: schema.workoutSessions.payload,
      updatedAt: schema.workoutSessions.updatedAt,
      deletedAt: schema.workoutSessions.deletedAt
    })
    .from(schema.workoutSessions)
    .where(eq(schema.workoutSessions.userId, userId));
  const authoritative = sessionRows.flatMap((row): WorkoutEnvelope[] => {
    const grouped = inferredById.get(row.id);
    inferredById.delete(row.id);
    if (row.deletedAt !== null || !payloadIsActive(row.payload)) {
      return [];
    }
    const startedAt =
      dateValue(row.payload.started_at) ??
      grouped?.startedAtDate ??
      row.updatedAt;

    return [{
      id: row.id,
      startedAt: startedAt.toISOString(),
      startedAtDate: startedAt,
      endedAt: dateValue(row.payload.ended_at)?.toISOString() ?? null,
      timezone: stringValue(row.payload.timezone),
      comment: nullableString(row.payload.comment),
      setCount: grouped?.setCount ?? 0,
      exerciseNames: grouped?.exerciseNames ?? []
    }];
  });

  return [...authoritative, ...inferredById.values()];
}

/**
 * Groups legacy live logged sets into inferred Workout envelopes. Newer clients
 * synchronize the Workout itself; this remains the compatibility path for
 * pre-structure-sync history. Sets without a workoutId are not attributable to
 * a Workout and are excluded.
 */
function groupSetsByWorkout(
  sets: readonly AgentReadableLoggedSet[]
): WorkoutEnvelope[] {
  const byWorkoutId = new Map<
    string,
    { earliestSet: AgentReadableLoggedSet; setCount: number; exerciseNames: Set<string> }
  >();

  for (const set of sets) {
    if (set.workoutId === null) {
      continue;
    }
    const existing = byWorkoutId.get(set.workoutId);
    if (existing === undefined) {
      byWorkoutId.set(set.workoutId, {
        earliestSet: set,
        setCount: 1,
        exerciseNames: new Set([set.exerciseName ?? set.exerciseId])
      });
      continue;
    }

    existing.setCount += 1;
    existing.exerciseNames.add(set.exerciseName ?? set.exerciseId);
    if (set.performedAtDate < existing.earliestSet.performedAtDate) {
      existing.earliestSet = set;
    }
  }

  return [...byWorkoutId.entries()].map(([workoutId, group]) => ({
    id: workoutId,
    startedAt: group.earliestSet.performedAtDate.toISOString(),
    startedAtDate: group.earliestSet.performedAtDate,
    endedAt: group.earliestSet.workoutEndedAt,
    timezone: group.earliestSet.workoutTimezone,
    comment: group.earliestSet.workoutComment,
    setCount: group.setCount,
    exerciseNames: [...group.exerciseNames].sort()
  }));
}

function compareWorkoutAscending(left: WorkoutEnvelope, right: WorkoutEnvelope) {
  const timeComparison = left.startedAtDate.getTime() - right.startedAtDate.getTime();
  return timeComparison !== 0 ? timeComparison : left.id.localeCompare(right.id);
}

function compareWorkoutDescending(left: WorkoutEnvelope, right: WorkoutEnvelope) {
  return -compareWorkoutAscending(left, right);
}

function resolveWorkoutFieldSelection(value: string | undefined) {
  if (value === undefined) {
    return ["id", "startedAt"] as (typeof AGENT_WORKOUT_LIST_FIELDS)[number][];
  }

  return [
    ...new Set<(typeof AGENT_WORKOUT_LIST_FIELDS)[number]>([
      "id",
      "startedAt",
      ...(value
        .split(",")
        .map((field) => field.trim())
        .filter((field): field is (typeof AGENT_WORKOUT_LIST_FIELDS)[number] =>
          (AGENT_WORKOUT_LIST_FIELDS as readonly string[]).includes(field)
        ))
    ])
  ];
}

function projectWorkout(
  workout: WorkoutEnvelope,
  fields: readonly (typeof AGENT_WORKOUT_LIST_FIELDS)[number][]
) {
  const full: Record<string, unknown> = {
    id: workout.id,
    startedAt: workout.startedAt,
    endedAt: workout.endedAt,
    timezone: workout.timezone,
    comment: workout.comment,
    setCount: workout.setCount,
    exerciseNames: workout.exerciseNames
  };

  return AgentWorkoutListItemSchema.parse(
    Object.fromEntries(fields.map((field) => [field, full[field]]))
  );
}

function serializeRecord(record: AnalyticsRecord | null) {
  if (record === null) {
    return null;
  }

  return AgentAnalyticsRecordSchema.parse({
    profile: record.profile,
    setId: record.setId,
    achievedAt: record.achievedAt.toISOString(),
    sequence: record.sequence,
    value: record.value,
    unit: record.unit,
    reps: record.reps
  });
}

function serializeRecordCatalog(analytics: ExerciseAnalyticsResult) {
  return AgentRecordCatalogSchema.parse({
    repMaxRecords: analytics.recordCatalog.repMaxRecords.map(serializeRecord),
    minAssistanceRecords:
      analytics.recordCatalog.minAssistanceRecords.map(serializeRecord),
    maxLoad: serializeRecord(analytics.recordCatalog.maxLoad),
    maxReps: serializeRecord(analytics.recordCatalog.maxReps),
    maxDuration: serializeRecord(analytics.recordCatalog.maxDuration),
    minDuration: serializeRecord(analytics.recordCatalog.minDuration),
    maxDistance: serializeRecord(analytics.recordCatalog.maxDistance),
    fastestPace: serializeRecord(analytics.recordCatalog.fastestPace)
  });
}

function serializeSeries(
  series: ExerciseAnalyticsResult["estimatedOneRepMax"],
  maxPoints: number
) {
  return AgentDerivedSeriesSchema.parse({
    isDefined: series.isDefined,
    points: series.points.slice(-maxPoints).map(serializePoint),
    total: series.total
  });
}

function serializeMaxLoadSeries(sets: readonly AnalyticsSet[], maxPoints: number) {
  const points: AnalyticsPoint[] = [];
  for (const set of sets) {
    const value = normalizedMetricValue(set.values.load, "load", "kilogram");
    if (value !== null) {
      points.push({
        setId: set.id,
        achievedAt: set.performedAt,
        value,
        unit: "kilogram"
      });
    }
  }

  return AgentDerivedSeriesSchema.parse({
    isDefined: points.length > 0,
    points: points.slice(-maxPoints).map(serializePoint),
    total: points.length === 0 ? null : Math.max(...points.map((point) => point.value))
  });
}

function serializePoint(point: AnalyticsPoint) {
  return AgentAnalyticsPointSchema.parse({
    setId: point.setId,
    achievedAt: point.achievedAt.toISOString(),
    value: point.value,
    unit: point.unit
  });
}

function periodStats(
  sets: readonly AnalyticsSet[],
  analytics: ExerciseAnalyticsResult
) {
  const performedTimes = sets.map((set) => set.performedAt.getTime());
  const e1rmValues = analytics.estimatedOneRepMax.points.map((point) => point.value);

  return AgentPeriodStatsSchema.parse({
    setCount: sets.length,
    firstPerformedAt:
      performedTimes.length === 0
        ? null
        : new Date(Math.min(...performedTimes)).toISOString(),
    lastPerformedAt:
      performedTimes.length === 0
        ? null
        : new Date(Math.max(...performedTimes)).toISOString(),
    totalVolumeKilograms: analytics.volume.total,
    totalReps: sumDimension(sets, "reps", "repetition"),
    totalDurationSeconds: sumDimension(sets, "duration", "second"),
    totalDistanceKilometers: sumDimension(sets, "distance", "kilometer"),
    maxEstimatedOneRepMaxKilograms:
      e1rmValues.length === 0 ? null : Math.max(...e1rmValues)
  });
}

function sumDimension(
  sets: readonly AnalyticsSet[],
  dimension: DimensionId,
  unit: TrainingUnit
) {
  let total = 0;
  let sawValue = false;
  for (const set of sets) {
    const value = normalizedMetricValue(set.values[dimension], dimension, unit);
    if (value !== null) {
      total += value;
      sawValue = true;
    }
  }

  return sawValue ? total : null;
}

type LocationPoint = {
  latitude: number;
  longitude: number;
};

function sampleAt(
  series: CanonicalSeries,
  sample: CanonicalSeries["samples"][number]
) {
  return new Date(new Date(series.baseTime).getTime() + sample.offsetSeconds * 1000);
}

function heartRateValue(
  value: CanonicalSeries["samples"][number]["value"]
): number | null {
  if (
    isRecord(value) &&
    value.unit === "beatsPerMinute" &&
    typeof value.value === "number" &&
    Number.isFinite(value.value)
  ) {
    return value.value;
  }

  return null;
}

function locationValue(
  value: CanonicalSeries["samples"][number]["value"]
): LocationPoint | null {
  if (!isRecord(value)) {
    return null;
  }

  const record = value as Record<string, unknown>;
  const latitude = structuredScalar(record.latitude, "degree");
  const longitude = structuredScalar(record.longitude, "degree");
  return latitude === null || longitude === null ? null : { latitude, longitude };
}

function structuredScalar(value: unknown, unit: string): number | null {
  if (
    isRecord(value) &&
    value.unit === unit &&
    typeof value.value === "number" &&
    Number.isFinite(value.value)
  ) {
    return value.value;
  }

  return null;
}

function heartRateZoneBucket(
  value: number
): keyof z.infer<typeof AgentMonitoringHeartRateZoneSecondsSchema> {
  if (value < 120) {
    return "below120";
  }
  if (value < 140) {
    return "bpm120To139";
  }
  if (value < 160) {
    return "bpm140To159";
  }
  if (value < 180) {
    return "bpm160To179";
  }

  return "bpm180Plus";
}

function haversineKilometers(left: LocationPoint, right: LocationPoint) {
  const earthRadiusKilometers = 6371;
  const latitudeDelta = toRadians(right.latitude - left.latitude);
  const longitudeDelta = toRadians(right.longitude - left.longitude);
  const leftLatitude = toRadians(left.latitude);
  const rightLatitude = toRadians(right.latitude);
  const halfChordLength =
    Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(leftLatitude) *
      Math.cos(rightLatitude) *
      Math.sin(longitudeDelta / 2) ** 2;

  return (
    earthRadiusKilometers *
    2 *
    Math.atan2(Math.sqrt(halfChordLength), Math.sqrt(1 - halfChordLength))
  );
}

function toRadians(value: number) {
  return (value * Math.PI) / 180;
}

function isoOrNull(value: Date | null) {
  return value === null ? null : value.toISOString();
}

function canonicalNumber(value: number) {
  return Number.parseFloat(value.toFixed(6));
}

function compareHistoryAscending(
  left: AgentReadableLoggedSet,
  right: AgentReadableLoggedSet
) {
  const timeComparison =
    left.performedAtDate.getTime() - right.performedAtDate.getTime();
  if (timeComparison !== 0) {
    return timeComparison;
  }
  if (left.sequence !== right.sequence) {
    return left.sequence - right.sequence;
  }

  return left.id.localeCompare(right.id);
}

function compareHistoryDescending(
  left: AgentReadableLoggedSet,
  right: AgentReadableLoggedSet
) {
  return -compareHistoryAscending(left, right);
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

function dateValue(value: unknown): Date | null {
  if (typeof value !== "string" || value.trim().length === 0) {
    return null;
  }

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function integerValue(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= 0
    ? value
    : null;
}

function booleanValue(value: unknown): boolean | null {
  return typeof value === "boolean" ? value : null;
}

function nullableString(value: unknown) {
  if (value === null || value === undefined) {
    return null;
  }

  return typeof value === "string" ? value : null;
}

function rpeValue(value: unknown) {
  return typeof value === "string" || typeof value === "number" ? value : null;
}

function sideValue(value: unknown) {
  return value === "left" || value === "right" ? value : null;
}

function stringValue(value: unknown): string | null {
  if (typeof value === "string" && value.length > 0) {
    return value;
  }

  return typeof value === "number" && Number.isFinite(value)
    ? value.toString()
    : null;
}

function unitValue(value: unknown): TrainingUnit | null {
  return typeof value === "string" && units.has(value as TrainingUnit)
    ? (value as TrainingUnit)
    : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
