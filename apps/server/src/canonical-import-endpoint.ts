import { createHash, randomBytes } from "node:crypto";
import { createRoute, z } from "@hono/zod-openapi";
import { and, asc, eq, isNull } from "drizzle-orm";

import {
  type CanonicalActivity,
  CanonicalImportDataClassSchema,
  type CanonicalImportDataClass,
  type CanonicalMetricReading,
  type CanonicalSeries
} from "./canonical-import.js";
import {
  CANONICAL_ACTIVITY_PLATFORM_EXERCISES,
  parseNormalizedCanonicalActivity
} from "./canonical-activity-mapping.js";
import {
  createCanonicalIngestionPipeline,
  type CanonicalActivityLink,
  type CanonicalActivityLinkingResult,
  type CanonicalActivityMaterializationResult,
  type CanonicalActivityMaterializationStore,
  type CanonicalMaterializationSet,
  type CanonicalMaterializedWorkout
} from "./canonical-ingestion.js";
import type {
  ExternalActivityStore,
  StoredExternalActivity
} from "./external-activities.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import {
  normalizeMetricReading,
  type MetricReadingNormalizationInput
} from "./metric-reading-normalization.js";
import {
  normalizeMetricLookupKey,
  owlMetricSchemaForImportKey,
  type PerenniaMetricSchema
} from "./metric-catalog.js";
import { encodeCanonicalSeriesBlob } from "./monitoring-series.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";
import {
  ACTIVITY_LINK_KIND_MATERIALIZED_SOURCE,
  ACTIVITY_LINK_KIND_TIME_OVERLAP
} from "./activity-links.js";

export const CANONICAL_IMPORT_ROUTE_PATH = "/integrations/canonical-import";
export const CANONICAL_IMPORT_ACTIVITY_LOG_ACTOR = "integration";
export const EXTERNAL_ACTIVITIES_IMPORT_ENTITY = "external_activities";
export const LOGGED_SETS_IMPORT_ENTITY = "logged_sets";
export const ACTIVITY_LINKS_IMPORT_ENTITY = "activity_links";
export const METRIC_READINGS_IMPORT_ENTITY = "metric_readings";
export const MONITORING_SERIES_IMPORT_ENTITY = "monitoring_series";
export const CANONICAL_IMPORT_BATCHES_ENTITY = "canonical_import_batches";
export const CANONICAL_IMPORT_MAX_ACTIVITIES = 500;
export const CANONICAL_IMPORT_MAX_METRIC_READINGS = 2_000;
export const CANONICAL_IMPORT_MAX_SERIES = 200;
export const ACTIVITY_LINK_CLOCK_SKEW_TOLERANCE_MS = 5 * 60 * 1000;
export const ACTIVITY_LINK_OPEN_SESSION_WINDOW_MS = 4 * 60 * 60 * 1000;
export const ACTIVITY_LINK_STRONG_OVERLAP_MIN_COVERAGE = 0.6;

const CanonicalImportUnknownItemSchema = z.unknown().openapi({
  description:
    "Candidate canonical item. Item-level shape problems are returned as review flags instead of rejecting the whole import."
});

export const CanonicalImportRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200).openapi({
      description:
        "Stable import batch key. Replays with the same key do not append another Activity Log batch."
    }),
    activities: z
      .array(CanonicalImportUnknownItemSchema)
      .max(CANONICAL_IMPORT_MAX_ACTIVITIES)
      .default([])
      .openapi({
        description:
          "Canonical Activity candidates emitted by an acquisition adapter."
      }),
    metricReadings: z
      .array(CanonicalImportUnknownItemSchema)
      .max(CANONICAL_IMPORT_MAX_METRIC_READINGS)
      .default([])
      .openapi({
        description:
          "Time-anchored Metric Reading candidates emitted by an acquisition adapter."
      }),
    series: z
      .array(CanonicalImportUnknownItemSchema)
      .max(CANONICAL_IMPORT_MAX_SERIES)
      .default([])
      .openapi({
        description:
          "Dense Monitoring Series candidates. Consented series are stored as compressed out-of-band blobs."
      }),
    consentedDataClasses: z
      .array(CanonicalImportDataClassSchema)
      .default([])
      .openapi({
        description:
          "Legacy adapter echo of requested data classes. Persisted per-Integration consent is authoritative for every import class; this field cannot enable Monitoring Data import."
      })
  })
  .strict()
  .openapi("CanonicalImportRequest");

export const CanonicalImportReviewFlagSchema = z
  .object({
    itemType: z.enum(["activity", "series", "metricReading"]),
    itemIndex: z.number().int().min(0),
    severity: z.enum(["warning", "error"]),
    field: z.string().min(1),
    rule: z.string().min(1),
    message: z.string().min(1)
  })
  .strict()
  .openapi("CanonicalImportReviewFlag");

export const CanonicalImportActivityResultSchema = z
  .object({
    itemIndex: z.number().int().min(0),
    source: z.string().min(1).nullable(),
    externalId: z.string().min(1).nullable(),
    status: z.enum(["created", "refreshed", "tombstoned", "notStored"]),
    externalActivityId: z.string().min(1).nullable(),
    reviewFlags: z.array(CanonicalImportReviewFlagSchema)
  })
  .strict()
  .openapi("CanonicalImportActivityResult");

export const CanonicalImportMetricReadingResultSchema = z
  .object({
    source: z.string().min(1),
    externalId: z.string().min(1),
    metricKey: z.string().min(1),
    status: z.enum(["created", "refreshed", "tombstoned"]),
    metricReadingId: z.string().min(1)
  })
  .strict()
  .openapi("CanonicalImportMetricReadingResult");

export const CanonicalImportMaterializedWorkoutSchema = z
  .object({
    workoutId: z.string().min(1),
    setIds: z.array(z.string().min(1)),
    externalActivityId: z.string().min(1),
    source: z.string().min(1),
    externalId: z.string().min(1),
    exerciseId: z.string().min(1),
    status: z.enum(["created", "existing", "refreshed", "tombstoned"])
  })
  .strict()
  .openapi("CanonicalImportMaterializedWorkout");

export const CanonicalImportActivityLinkSchema = z
  .object({
    id: z.string().min(1),
    workoutId: z.string().min(1),
    externalActivityId: z.string().min(1),
    linkKind: z.string().min(1),
    status: z.enum(["created", "existing", "refreshed", "tombstoned"])
  })
  .strict()
  .openapi("CanonicalImportActivityLink");

export const CanonicalImportActivityLinkSuggestionSchema = z
  .object({
    externalActivityId: z.string().min(1),
    source: z.string().min(1),
    externalId: z.string().min(1),
    candidateWorkoutIds: z.array(z.string().min(1)).min(2),
    reason: z.literal("ambiguous_time_overlap")
  })
  .strict()
  .openapi("CanonicalImportActivityLinkSuggestion");

export const CanonicalImportResponseSchema = z
  .object({
    accepted: z.literal(true),
    duplicate: z.boolean().openapi({
      description:
        "True when this idempotency key had already been applied and no rows were written."
    }),
    idempotencyKey: z.string().min(1),
    batchId: z.string().min(1).openapi({
      description: "Activity Log batch id. Equal to the idempotency key."
    }),
    serverClock: z.string().min(1),
    activities: z.array(CanonicalImportActivityResultSchema),
    metricReadings: z.array(CanonicalImportMetricReadingResultSchema),
    seriesAccepted: z.number().int().min(0),
    reviewFlags: z.array(CanonicalImportReviewFlagSchema),
    materializedWorkouts: z.array(CanonicalImportMaterializedWorkoutSchema),
    activityLinks: z.array(CanonicalImportActivityLinkSchema),
    activityLinkSuggestions: z
      .array(CanonicalImportActivityLinkSuggestionSchema)
      .default([])
  })
  .strict()
  .openapi("CanonicalImportResponse");

export const CanonicalImportUnauthorizedResponseSchema = z
  .object({
    code: z.literal("integration_unauthorized"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("CanonicalImportUnauthorizedResponse");

export const CanonicalImportForbiddenResponseSchema = z
  .object({
    code: z.literal("integration_forbidden"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("CanonicalImportForbiddenResponse");

export const CanonicalImportUnavailableResponseSchema = z
  .object({
    code: z.literal("canonical_import_unavailable"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("CanonicalImportUnavailableResponse");

export const canonicalImportRoute = createRoute({
  method: "post",
  path: CANONICAL_IMPORT_ROUTE_PATH,
  operationId: "importCanonicalBatch",
  tags: ["Integrations"],
  summary: "Ingest a canonical Integration batch.",
  description:
    "Dedicated import surface for acquisition adapters. Authenticates an import-scoped Integration credential, feeds the shared canonical ingestion pipeline, stores observations atomically, and records one actor=integration Activity Log batch.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: CanonicalImportRequestSchema
        }
      }
    }
  },
  responses: {
    200: {
      description:
        "The canonical batch was accepted, or recognized as an idempotent replay.",
      content: {
        "application/json": {
          schema: CanonicalImportResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid Integration credential.",
      content: {
        "application/json": {
          schema: CanonicalImportUnauthorizedResponseSchema
        }
      }
    },
    403: {
      description: "The Integration credential is not scoped for imports.",
      content: {
        "application/json": {
          schema: CanonicalImportForbiddenResponseSchema
        }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Canonical import storage or credentials are not configured.",
      content: {
        "application/json": {
          schema: CanonicalImportUnavailableResponseSchema
        }
      }
    }
  }
});

export type CanonicalImportRequest = z.infer<
  typeof CanonicalImportRequestSchema
>;
export type CanonicalImportResponse = z.infer<
  typeof CanonicalImportResponseSchema
>;
export type CanonicalImportMetricReadingResult = z.infer<
  typeof CanonicalImportMetricReadingResultSchema
>;
export type CanonicalImportStoreResult = CanonicalImportResponse & {
  applied: Array<{
    entityTable:
      | typeof EXTERNAL_ACTIVITIES_IMPORT_ENTITY
      | typeof LOGGED_SETS_IMPORT_ENTITY
      | typeof ACTIVITY_LINKS_IMPORT_ENTITY
      | typeof METRIC_READINGS_IMPORT_ENTITY
      | typeof MONITORING_SERIES_IMPORT_ENTITY
      | typeof CANONICAL_IMPORT_BATCHES_ENTITY;
    entityId: string;
  }>;
};

export type CanonicalImportStore = {
  importCanonicalBatch(input: {
    actor: typeof CANONICAL_IMPORT_ACTIVITY_LOG_ACTOR;
    batchId: string;
    correlationId?: string;
    credentialId: string;
    deviceId: string;
    idempotencyKey: string;
    request: CanonicalImportRequest;
    userId: string;
  }): Promise<CanonicalImportStoreResult>;
};

export type CanonicalImportObservabilityContext = {
  batchId: string;
  credentialId: string;
  userId: string;
  counts: {
    activityCount: number;
    metricReadingCount: number;
    seriesCount: number;
    consentedDataClassCount: number;
  };
  references: {
    activities: CanonicalImportReferenceSummary;
    metricReadings: CanonicalImportReferenceSummary;
    series: CanonicalImportReferenceSummary;
  };
};

type CanonicalImportReferenceSummary = {
  total: number;
  omitted: number;
  items: CanonicalImportReference[];
};

type CanonicalImportReference = {
  source: string | null;
  externalId: string | null;
};

export const CANONICAL_IMPORT_OBSERVABILITY_REFERENCE_LIMIT = 25;

export function canonicalImportObservabilityContext({
  credentialId,
  request,
  userId
}: {
  credentialId: string;
  request: CanonicalImportRequest;
  userId: string;
}): CanonicalImportObservabilityContext {
  return {
    batchId: request.idempotencyKey,
    credentialId,
    userId,
    counts: {
      activityCount: request.activities.length,
      metricReadingCount: request.metricReadings.length,
      seriesCount: request.series.length,
      consentedDataClassCount: request.consentedDataClasses.length
    },
    references: {
      activities: canonicalImportReferenceSummary(request.activities),
      metricReadings: canonicalImportReferenceSummary(request.metricReadings),
      series: canonicalImportReferenceSummary(request.series)
    }
  };
}

type CanonicalImportMutationDatabase = Pick<
  ServerDatabase,
  "insert" | "select" | "update"
>;

type ActivityLogWrite = {
  id: string;
  entityTable:
    | typeof EXTERNAL_ACTIVITIES_IMPORT_ENTITY
    | typeof LOGGED_SETS_IMPORT_ENTITY
    | typeof ACTIVITY_LINKS_IMPORT_ENTITY
    | typeof METRIC_READINGS_IMPORT_ENTITY
    | typeof MONITORING_SERIES_IMPORT_ENTITY
    | typeof CANONICAL_IMPORT_BATCHES_ENTITY;
  entityId: string;
  beforeImage: Record<string, unknown> | null;
  afterImage: Record<string, unknown>;
  occurredAt: Date;
};

type StoredMetricReadingInput =
  | CanonicalMetricReading
  | CanonicalActivity["summaryMetrics"][number];

type StoredMetricReadingCandidate = {
  reading: StoredMetricReadingInput;
  externalActivityId: string | null;
};

export function createDrizzleCanonicalImportStore(
  db: ServerDatabase
): CanonicalImportStore {
  return {
    async importCanonicalBatch({
      batchId,
      credentialId,
      deviceId,
      idempotencyKey,
      request,
      userId
    }) {
      const serverClock = new Date();

      return db.transaction(async (transaction) => {
        const existingBatchRows = await transaction
          .select({
            id: schema.activityLog.id,
            entityTable: schema.activityLog.entityTable,
            entityId: schema.activityLog.entityId
          })
          .from(schema.activityLog)
          .where(
            and(
              eq(schema.activityLog.userId, userId),
              eq(schema.activityLog.actor, CANONICAL_IMPORT_ACTIVITY_LOG_ACTOR),
              eq(schema.activityLog.batchId, batchId)
            )
          )
          .orderBy(asc(schema.activityLog.createdAt), asc(schema.activityLog.id));

        if (existingBatchRows.length > 0) {
          return {
            ...emptyCanonicalImportResponse({
              duplicate: true,
              idempotencyKey,
              batchId,
              serverClock
            }),
            applied: []
          };
        }

        const activityLogWrites: ActivityLogWrite[] = [];
        const externalActivityStore = createTransactionExternalActivityStore(
          transaction,
          {
            activityLogWrites,
            batchId,
            deviceId,
            userId
          }
        );
        const activityMaterializationStore =
          createTransactionActivityMaterializationStore(transaction, {
            activityLogWrites,
            batchId,
            deviceId,
            userId
          });
        const consentedDataClasses = await readEnabledImportConsentDataClasses(
          transaction,
          {
            credentialId,
            userId
          }
        );
        const ingestion = await createCanonicalIngestionPipeline({
          externalActivityStore,
          activityMaterializationStore
        }).ingestCanonicalBatch({
          userId,
          deviceId,
          importedAt: serverClock,
          activities: request.activities,
          metricReadings: request.metricReadings,
          series: request.series,
          consentedDataClasses
        });

        const metricReadingResults: CanonicalImportMetricReadingResult[] = [];
        const metricReadingsToStore: StoredMetricReadingCandidate[] = [
          ...ingestion.storedExternalActivities.flatMap(
            (activity) =>
              activity.summaryMetrics.map((reading) => ({
                reading,
                externalActivityId: activity.id
              }))
          ),
          ...ingestion.metricReadings.map((reading) => ({
            reading,
            externalActivityId: null
          }))
        ];
        for (const candidate of metricReadingsToStore) {
          metricReadingResults.push(
            await storeMetricReadingInTransaction(transaction, {
              activityLogWrites,
              batchId,
              deviceId,
              externalActivityId: candidate.externalActivityId,
              reading: candidate.reading,
              updatedAt: serverClock,
              userId
            })
          );
        }
        let seriesAccepted = 0;
        for (const series of ingestion.series) {
          const result = await storeMonitoringSeriesInTransaction(transaction, {
            activityLogWrites,
            batchId,
            deviceId,
            series,
            updatedAt: serverClock,
            userId
          });
          if (result.status === "created" || result.status === "refreshed") {
            seriesAccepted += 1;
          }
        }
        if (activityLogWrites.length === 0) {
          activityLogWrites.push(
            canonicalImportNoopBatchWrite({
              batchId,
              idempotencyKey,
              occurredAt: serverClock,
              request,
              resultCounts: {
                activities: ingestion.activities.length,
                metricReadings: metricReadingResults.length,
                reviewFlags: ingestion.reviewFlags.length,
                seriesAccepted
              }
            })
          );
        }

        for (const write of activityLogWrites) {
          await transaction
            .insert(schema.activityLog)
            .values({
              id: write.id,
              userId,
              actor: CANONICAL_IMPORT_ACTIVITY_LOG_ACTOR,
              batchId,
              entityTable: write.entityTable,
              entityId: write.entityId,
              beforeImage: write.beforeImage,
              afterImage: write.afterImage,
              occurredAt: write.occurredAt
            })
            .onConflictDoNothing({ target: schema.activityLog.id });
        }

        const response = CanonicalImportResponseSchema.parse({
          accepted: true,
          duplicate: false,
          idempotencyKey,
          batchId,
          serverClock: serverClock.toISOString(),
          activities: ingestion.activities.map((activity) => ({
            itemIndex: activity.itemIndex,
            source: activity.source,
            externalId: activity.externalId,
            status: activity.status,
            externalActivityId: activity.stored?.id ?? null,
            reviewFlags: [
              ...activity.reviewFlags
            ]
          })),
          metricReadings: metricReadingResults,
          seriesAccepted,
          reviewFlags: ingestion.reviewFlags,
          materializedWorkouts: ingestion.materializedWorkouts,
          activityLinks: ingestion.activityLinks,
          activityLinkSuggestions: ingestion.activityLinkSuggestions
        });

        return {
          ...response,
          applied: activityLogWrites.map((write) => ({
            entityTable: write.entityTable,
            entityId: write.entityId
          }))
        };
      });
    }
  };
}

async function readEnabledImportConsentDataClasses(
  transaction: CanonicalImportMutationDatabase,
  {
    credentialId,
    userId
  }: {
    credentialId: string;
    userId: string;
  }
): Promise<CanonicalImportDataClass[]> {
  const rows = await transaction
    .select({ dataClass: schema.integrationDataClassConsents.dataClass })
    .from(schema.integrationDataClassConsents)
    .where(
      and(
        eq(schema.integrationDataClassConsents.userId, userId),
        eq(schema.integrationDataClassConsents.credentialId, credentialId),
        eq(schema.integrationDataClassConsents.enabled, true),
        isNull(schema.integrationDataClassConsents.deletedAt)
      )
    );
  const consented = rows
    .map((row) => CanonicalImportDataClassSchema.safeParse(row.dataClass))
    .filter((parsed) => parsed.success)
    .map((parsed) => parsed.data);

  return consented;
}

function createTransactionExternalActivityStore(
  transaction: CanonicalImportMutationDatabase,
  {
    activityLogWrites,
    batchId,
    deviceId,
    userId
  }: {
    activityLogWrites: ActivityLogWrite[];
    batchId: string;
    deviceId: string;
    userId: string;
  }
): ExternalActivityStore {
  return {
    async findExternalActivity({ userId, source, externalId }) {
      const rows = await transaction
        .select()
        .from(schema.externalActivities)
        .where(
          and(
            eq(schema.externalActivities.userId, userId),
            eq(schema.externalActivities.source, source),
            eq(schema.externalActivities.externalId, externalId),
            isNull(schema.externalActivities.deletedAt)
          )
        )
        .limit(1);

      return rows[0] === undefined ? null : mapStoredExternalActivity(rows[0]);
    },
    async storeCanonicalActivity(input) {
      const parsed = parseNormalizedCanonicalActivity(input.activity);
      const updatedAt = input.importedAt ?? new Date();
      const existingRows = await transaction
        .select()
        .from(schema.externalActivities)
        .where(
          and(
            eq(schema.externalActivities.userId, userId),
            eq(schema.externalActivities.source, parsed.source),
            eq(schema.externalActivities.externalId, parsed.externalId)
          )
        )
        .limit(1);
      const existing = existingRows[0];
      if (existing?.deletedAt !== null && existing?.deletedAt !== undefined) {
        return null;
      }

      const id = existing?.id ?? generateUuidV7(updatedAt);
      const rowValues = {
        id,
        userId,
        deviceId,
        source: parsed.source,
        externalId: parsed.externalId,
        startedAt: parseCanonicalInstant(parsed.startedAt),
        endedAt: parseCanonicalInstant(parsed.endedAt),
        timezone: parsed.timezone,
        activityType: parsed.activityType,
        mappedExerciseId: parsed.mappedExerciseId,
        summaryJson: parsed.summary,
        summaryMetricsJson: parsed.summaryMetrics,
        setsJson: parsed.sets ?? null,
        updatedAt,
        deletedAt: null,
        receivedAt: updatedAt
      };

      if (existing === undefined) {
        await transaction.insert(schema.externalActivities).values(rowValues);
      } else {
        await transaction
          .update(schema.externalActivities)
          .set(rowValues)
          .where(eq(schema.externalActivities.id, id));
      }

      const stored: StoredExternalActivity = {
        id,
        userId,
        deviceId,
        source: parsed.source,
        externalId: parsed.externalId,
        startedAt: parsed.startedAt,
        endedAt: parsed.endedAt,
        timezone: parsed.timezone,
        activityType: parsed.activityType,
        mappedExerciseId: parsed.mappedExerciseId,
        summary: parsed.summary,
        summaryMetrics: parsed.summaryMetrics,
        sets: parsed.sets,
        updatedAt: updatedAt.toISOString(),
        deletedAt: null
      };
      activityLogWrites.push({
        id: stableActivityLogId(batchId, EXTERNAL_ACTIVITIES_IMPORT_ENTITY, id),
        entityTable: EXTERNAL_ACTIVITIES_IMPORT_ENTITY,
        entityId: id,
        beforeImage:
          existing === undefined ? null : externalActivityRowImage(existing),
        afterImage: externalActivityStoredImage(stored),
        occurredAt: updatedAt
      });

      return stored;
    }
  };
}

function createTransactionActivityMaterializationStore(
  transaction: CanonicalImportMutationDatabase,
  {
    activityLogWrites,
    batchId,
    deviceId,
    userId
  }: {
    activityLogWrites: ActivityLogWrite[];
    batchId: string;
    deviceId: string;
    userId: string;
  }
): CanonicalActivityMaterializationStore {
  return {
    async linkActivityByTimeOverlap({
      activity,
      externalActivity,
      importedAt
    }) {
      return linkActivityByTimeOverlap(transaction, {
        activity,
        activityLogWrites,
        batchId,
        deviceId,
        externalActivity,
        importedAt,
        userId
      });
    },
    async materializeCardioActivity({
      activity,
      externalActivity,
      set,
      importedAt
    }) {
      return materializeActivitySets(transaction, {
        activity,
        activityLogWrites,
        batchId,
        deviceId,
        externalActivity,
        importedAt,
        setIdFor: () =>
          stableScopedId(
            "materialized-set",
            userId,
            activity.source,
            activity.externalId
          ),
        sets: [set],
        userId
      });
    },
    async materializeStrengthActivity({
      activity,
      externalActivity,
      sets,
      importedAt
    }) {
      return materializeActivitySets(transaction, {
        activity,
        activityLogWrites,
        batchId,
        deviceId,
        externalActivity,
        importedAt,
        setIdFor: (set) =>
          stableScopedId(
            "materialized-set",
            userId,
            activity.source,
            activity.externalId,
            set.externalId
          ),
        sets,
        userId
      });
    }
  };
}

async function linkActivityByTimeOverlap(
  transaction: CanonicalImportMutationDatabase,
  {
    activity,
    activityLogWrites,
    batchId,
    deviceId,
    externalActivity,
    importedAt,
    userId
  }: {
    activity: Parameters<
      CanonicalActivityMaterializationStore["materializeCardioActivity"]
    >[0]["activity"];
    activityLogWrites: ActivityLogWrite[];
    batchId: string;
    deviceId: string;
    externalActivity: StoredExternalActivity;
    importedAt?: Date;
    userId: string;
  }
): Promise<CanonicalActivityLinkingResult> {
  const existingRows = await transaction
    .select()
    .from(schema.activityLinks)
    .where(
      and(
        eq(schema.activityLinks.userId, userId),
        eq(schema.activityLinks.externalActivityId, externalActivity.id)
      )
    )
    .limit(1);
  const existing = existingRows[0];
  if (existing !== undefined) {
    if (
      existing.deletedAt === null &&
      existing.linkKind !== ACTIVITY_LINK_KIND_MATERIALIZED_SOURCE
    ) {
      return {
        kind: "linked",
        activityLink: activityLinkFromRow(existing, "existing")
      };
    }

    return { kind: "none" };
  }

  const candidates = await readHandLoggedWorkoutCandidates(transaction, {
    userId
  });
  const ranked = rankWorkoutCandidatesForActivity({
    activityStartedAt: parseCanonicalInstant(activity.startedAt),
    activityEndedAt: parseCanonicalInstant(activity.endedAt),
    candidates
  });
  const strongCandidates = ranked.filter(
    (candidate) =>
      candidate.coverage >= ACTIVITY_LINK_STRONG_OVERLAP_MIN_COVERAGE
  );
  const best = strongCandidates[0];
  if (best === undefined) {
    return { kind: "none" };
  }

  const tiedBestCandidates = strongCandidates.filter((candidate) =>
    overlapScoresTie(candidate, best)
  );
  if (tiedBestCandidates.length > 1) {
    return {
      kind: "suggested",
      suggestion: {
        externalActivityId: externalActivity.id,
        source: activity.source,
        externalId: activity.externalId,
        candidateWorkoutIds: tiedBestCandidates.map(
          (candidate) => candidate.workoutId
        ),
        reason: "ambiguous_time_overlap"
      }
    };
  }

  const updatedAt = importedAt ?? new Date();
  const linkId = stableScopedId(
    "activity-link",
    userId,
    externalActivity.id,
    best.workoutId
  );
  const linkIdRows = await transaction
    .select({ userId: schema.activityLinks.userId })
    .from(schema.activityLinks)
    .where(eq(schema.activityLinks.id, linkId))
    .limit(1);
  if (linkIdRows[0] !== undefined && linkIdRows[0].userId !== userId) {
    return { kind: "none" };
  }

  const linkValues = {
    id: linkId,
    userId,
    deviceId,
    workoutId: best.workoutId,
    externalActivityId: externalActivity.id,
    linkKind: ACTIVITY_LINK_KIND_TIME_OVERLAP,
    updatedAt,
    deletedAt: null,
    receivedAt: updatedAt
  };
  await transaction.insert(schema.activityLinks).values(linkValues);
  activityLogWrites.push({
    id: stableActivityLogId(batchId, ACTIVITY_LINKS_IMPORT_ENTITY, linkId),
    entityTable: ACTIVITY_LINKS_IMPORT_ENTITY,
    entityId: linkId,
    beforeImage: null,
    afterImage: activityLinkRowImage(linkValues),
    occurredAt: updatedAt
  });

  return {
    kind: "linked",
    activityLink: activityLinkFromRow(linkValues, "created")
  };
}

type HandLoggedWorkoutCandidate = {
  workoutId: string;
  startedAt: Date;
  endedAt: Date | null;
};

type RankedWorkoutCandidate = HandLoggedWorkoutCandidate & {
  overlapMs: number;
  coverage: number;
};

async function readHandLoggedWorkoutCandidates(
  transaction: CanonicalImportMutationDatabase,
  { userId }: { userId: string }
): Promise<HandLoggedWorkoutCandidate[]> {
  const rows = await transaction
    .select({ payload: schema.loggedSets.payload })
    .from(schema.loggedSets)
    .where(and(eq(schema.loggedSets.userId, userId), isNull(schema.loggedSets.deletedAt)));
  const workouts = new Map<string, HandLoggedWorkoutCandidate>();

  for (const row of rows) {
    const payload = row.payload;
    if (
      payload.external_activity_id !== undefined ||
      payload.provenance === CANONICAL_IMPORT_ACTIVITY_LOG_ACTOR
    ) {
      continue;
    }

    const workoutId = stringValue(payload.workout_id);
    const startedAt = dateValue(payload.workout_started_at);
    const endedAt = nullableDateValue(payload.workout_ended_at);
    if (workoutId === null || startedAt === null) {
      continue;
    }

    const existing = workouts.get(workoutId);
    if (existing === undefined) {
      workouts.set(workoutId, { workoutId, startedAt, endedAt });
      continue;
    }

    if (startedAt < existing.startedAt) {
      existing.startedAt = startedAt;
    }
    if (
      endedAt !== null &&
      (existing.endedAt === null || endedAt > existing.endedAt)
    ) {
      existing.endedAt = endedAt;
    }
  }

  return [...workouts.values()];
}

function rankWorkoutCandidatesForActivity({
  activityStartedAt,
  activityEndedAt,
  candidates
}: {
  activityStartedAt: Date;
  activityEndedAt: Date;
  candidates: HandLoggedWorkoutCandidate[];
}): RankedWorkoutCandidate[] {
  const activityDurationMs =
    activityEndedAt.getTime() - activityStartedAt.getTime();
  if (activityDurationMs <= 0) {
    return [];
  }

  return candidates
    .map((candidate) => {
      const candidateEndedAt = effectiveWorkoutCandidateEndedAt(
        candidate,
        candidates
      );
      const overlapMs = intervalOverlapMs({
        leftStartedAt: new Date(
          candidate.startedAt.getTime() - ACTIVITY_LINK_CLOCK_SKEW_TOLERANCE_MS
        ),
        leftEndedAt: new Date(
          candidateEndedAt.getTime() + ACTIVITY_LINK_CLOCK_SKEW_TOLERANCE_MS
        ),
        rightStartedAt: activityStartedAt,
        rightEndedAt: activityEndedAt
      });

      return {
        ...candidate,
        overlapMs,
        coverage: overlapMs / activityDurationMs
      };
    })
    .filter((candidate) => candidate.overlapMs > 0)
    .sort((left, right) => {
      const coverageDiff = right.coverage - left.coverage;
      if (Math.abs(coverageDiff) > 0.000001) {
        return coverageDiff;
      }

      return right.overlapMs - left.overlapMs;
    });
}

function effectiveWorkoutCandidateEndedAt(
  candidate: HandLoggedWorkoutCandidate,
  candidates: HandLoggedWorkoutCandidate[]
) {
  if (candidate.endedAt !== null) {
    return candidate.endedAt;
  }

  const boundedOpenEnd = new Date(
    candidate.startedAt.getTime() + ACTIVITY_LINK_OPEN_SESSION_WINDOW_MS
  );
  const nextWorkout = candidates
    .filter((next) => next.startedAt > candidate.startedAt)
    .sort((left, right) => left.startedAt.getTime() - right.startedAt.getTime())[0];

  return nextWorkout !== undefined && nextWorkout.startedAt < boundedOpenEnd
    ? nextWorkout.startedAt
    : boundedOpenEnd;
}

function intervalOverlapMs({
  leftStartedAt,
  leftEndedAt,
  rightStartedAt,
  rightEndedAt
}: {
  leftStartedAt: Date;
  leftEndedAt: Date;
  rightStartedAt: Date;
  rightEndedAt: Date;
}) {
  return Math.max(
    0,
    Math.min(leftEndedAt.getTime(), rightEndedAt.getTime()) -
      Math.max(leftStartedAt.getTime(), rightStartedAt.getTime())
  );
}

function overlapScoresTie(
  left: RankedWorkoutCandidate,
  right: RankedWorkoutCandidate
) {
  return (
    Math.abs(left.coverage - right.coverage) <= 0.000001 &&
    left.overlapMs === right.overlapMs
  );
}

async function materializeActivitySets(
  transaction: CanonicalImportMutationDatabase,
  {
    activity,
    activityLogWrites,
    batchId,
    deviceId,
    externalActivity,
    importedAt,
    setIdFor,
    sets,
    userId
  }: {
    activity: Parameters<
      CanonicalActivityMaterializationStore["materializeCardioActivity"]
    >[0]["activity"];
    activityLogWrites: ActivityLogWrite[];
    batchId: string;
    deviceId: string;
    externalActivity: StoredExternalActivity;
    importedAt?: Date;
    setIdFor: (set: CanonicalMaterializationSet, index: number) => string;
    sets: CanonicalMaterializationSet[];
    userId: string;
  }
): Promise<CanonicalActivityMaterializationResult | null> {
  if (activity.mappedExerciseId === null || sets.length === 0) {
    return null;
  }

  const platformExercise =
    CANONICAL_ACTIVITY_PLATFORM_EXERCISES[activity.mappedExerciseId];
  const updatedAt = importedAt ?? new Date();
  const workoutId = stableScopedId(
    "materialized-workout",
    userId,
    activity.source,
    activity.externalId
  );
  const linkId = stableScopedId(
    "activity-link",
    userId,
    externalActivity.id,
    workoutId
  );
  const existingLinkRows = await transaction
    .select()
    .from(schema.activityLinks)
    .where(eq(schema.activityLinks.id, linkId))
    .limit(1);
  const existingLink = existingLinkRows[0];
  if (existingLink !== undefined && existingLink.userId !== userId) {
    return null;
  }

  const setPlans = [];
  for (const [index, set] of sets.entries()) {
    const setId = setIdFor(set, index);
    const existingSetRows = await transaction
      .select({
        userId: schema.loggedSets.userId,
        deletedAt: schema.loggedSets.deletedAt,
        payload: schema.loggedSets.payload
      })
      .from(schema.loggedSets)
      .where(eq(schema.loggedSets.id, setId))
      .limit(1);
    const existingSet = existingSetRows[0];
    if (existingSet !== undefined && existingSet.userId !== userId) {
      return null;
    }

    setPlans.push({
      existingSet,
      payload: materializedSetPayload({
        activity,
        externalActivity,
        platformExercise,
        position: index,
        set,
        setId,
        updatedAt,
        workoutId
      }),
      set,
      setId
    });
  }

  let sawCreatedSet = false;
  let sawLiveExistingSet = false;
  for (const plan of setPlans) {
    if (plan.existingSet === undefined) {
      await transaction.insert(schema.loggedSets).values({
        id: plan.setId,
        userId,
        deviceId,
        payload: plan.payload,
        updatedAt,
        deletedAt: null,
        receivedAt: updatedAt
      });
      activityLogWrites.push({
        id: stableActivityLogId(batchId, LOGGED_SETS_IMPORT_ENTITY, plan.setId),
        entityTable: LOGGED_SETS_IMPORT_ENTITY,
        entityId: plan.setId,
        beforeImage: null,
        afterImage: plan.payload,
        occurredAt: updatedAt
      });
      sawCreatedSet = true;
    } else if (plan.existingSet.deletedAt === null) {
      sawLiveExistingSet = true;
    }
  }

  const linkValues = {
    id: linkId,
    userId,
    deviceId,
    workoutId,
    externalActivityId: externalActivity.id,
    linkKind: ACTIVITY_LINK_KIND_MATERIALIZED_SOURCE,
    updatedAt,
    deletedAt: null,
    receivedAt: updatedAt
  };
  if (existingLink === undefined) {
    await transaction.insert(schema.activityLinks).values(linkValues);
    activityLogWrites.push({
      id: stableActivityLogId(batchId, ACTIVITY_LINKS_IMPORT_ENTITY, linkId),
      entityTable: ACTIVITY_LINKS_IMPORT_ENTITY,
      entityId: linkId,
      beforeImage: null,
      afterImage: activityLinkRowImage(linkValues),
      occurredAt: updatedAt
    });
  }

  const workoutStatus =
    sawCreatedSet || existingLink === undefined
      ? ("created" as const)
      : sawLiveExistingSet
        ? ("existing" as const)
        : ("tombstoned" as const);
  const activityLink = {
    id: linkId,
    workoutId,
    externalActivityId: externalActivity.id,
    linkKind:
      existingLink?.linkKind ?? ACTIVITY_LINK_KIND_MATERIALIZED_SOURCE,
    status:
      existingLink === undefined
        ? ("created" as const)
        : existingLink.deletedAt === null
          ? ("existing" as const)
          : ("tombstoned" as const)
  };

  return {
    workout: {
      workoutId,
      setIds: setPlans.map((plan) => plan.setId),
      externalActivityId: externalActivity.id,
      source: activity.source,
      externalId: activity.externalId,
      exerciseId: platformExercise.id,
      status: workoutStatus
    },
    activityLink
  };
}

function materializedSetPayload({
  activity,
  externalActivity,
  platformExercise,
  position,
  set,
  setId,
  updatedAt,
  workoutId
}: {
  activity: Parameters<
    CanonicalActivityMaterializationStore["materializeCardioActivity"]
  >[0]["activity"];
  externalActivity: StoredExternalActivity;
  platformExercise: (typeof CANONICAL_ACTIVITY_PLATFORM_EXERCISES)[keyof typeof CANONICAL_ACTIVITY_PLATFORM_EXERCISES];
  position: number;
  set: CanonicalMaterializationSet;
  setId: string;
  updatedAt: Date;
  workoutId: string;
}) {
  const payload: Record<string, unknown> = {
    id: setId,
    workout_id: workoutId,
    workout_started_at: activity.startedAt,
    workout_ended_at: activity.endedAt,
    workout_timezone: activity.timezone,
    workout_comment: null,
    source: activity.source,
    provenance: CANONICAL_IMPORT_ACTIVITY_LOG_ACTOR,
    external_activity_id: externalActivity.id,
    external_activity_source: activity.source,
    external_activity_external_id: activity.externalId,
    external_set_source: set.source,
    external_set_external_id: set.externalId,
    external_set_timezone: set.timezone,
    performed_at: set.performedAt ?? null,
    exercise_id: platformExercise.id,
    exercise_name: platformExercise.name,
    exercise_category_id: platformExercise.categoryId,
    exercise_category_name: platformExercise.categoryName,
    exercise_library: "platform",
    exercise_query: platformExercise.name,
    position,
    values: set.values,
    review_flags: set.warnings.map(materializedSetReviewFlag),
    rpe: null,
    side: null,
    comment: null,
    updated_at: updatedAt.toISOString(),
    deleted_at: null
  };

  for (const [dimension, value] of Object.entries(set.values)) {
    if (value !== undefined) {
      payload[`${dimension}_entered`] = value.entered;
      payload[`${dimension}_unit`] = value.unit;
    }
  }

  return payload;
}

function materializedSetReviewFlag(
  warning: CanonicalMaterializationSet["warnings"][number]
) {
  return {
    severity: "warning",
    field: warning.field,
    dimension: warning.dimension,
    rule: warning.rule,
    message: warning.message,
    limit: warning.limit
  };
}

async function storeMetricReadingInTransaction(
  transaction: CanonicalImportMutationDatabase,
  {
    activityLogWrites,
    batchId,
    deviceId,
    externalActivityId,
    reading,
    updatedAt,
    userId
  }: {
    activityLogWrites: ActivityLogWrite[];
    batchId: string;
    deviceId: string;
    externalActivityId: string | null;
    reading: StoredMetricReadingInput;
    updatedAt: Date;
    userId: string;
  }
): Promise<CanonicalImportMetricReadingResult> {
  const existingRows = await transaction
    .select()
    .from(schema.metricReadings)
    .where(
      and(
        eq(schema.metricReadings.userId, userId),
        eq(schema.metricReadings.source, reading.source),
        eq(schema.metricReadings.externalId, reading.externalId)
      )
    )
    .limit(1);
  const existing = existingRows[0];
  if (existing?.deletedAt !== null && existing?.deletedAt !== undefined) {
    return CanonicalImportMetricReadingResultSchema.parse({
      source: reading.source,
      externalId: reading.externalId,
      metricKey: reading.metricKey,
      status: "tombstoned",
      metricReadingId: existing.id
    });
  }

  const normalizedInput = metricReadingNormalizationInput(reading);
  const normalized = normalizeMetricReading(normalizedInput);
  const metricId = await resolveImportedMetricId(transaction, {
    deviceId,
    reading,
    normalized,
    updatedAt,
    userId
  });
  const readingId = existing?.id ?? generateUuidV7(updatedAt);
  const valueJson = JSON.parse(normalized.valueJson) as Record<string, unknown>;

  const atTime = nullableDate(normalized.atTime);
  const windowStartedAt = nullableDate(normalized.windowStartedAt);
  const windowEndedAt = nullableDate(normalized.windowEndedAt);
  const scalarEntered = scalarEnteredValue(reading);
  const rowValues = {
    id: readingId,
    userId,
    deviceId,
    metricId,
    externalActivityId,
    valueJson,
    scalarValue: normalized.scalarValue,
    scalarEntered,
    atTime,
    windowStartedAt,
    windowEndedAt,
    provenance: CANONICAL_IMPORT_ACTIVITY_LOG_ACTOR,
    source: reading.source,
    externalId: reading.externalId,
    comment: null,
    updatedAt,
    deletedAt: null,
    receivedAt: updatedAt
  };

  await transaction
    .insert(schema.metricReadings)
    .values(rowValues)
    .onConflictDoUpdate({
      target: schema.metricReadings.id,
      set: rowValues
    });

  const afterImage = metricReadingImage({
    ...rowValues,
    updatedAt,
    deletedAt: null,
    receivedAt: updatedAt
  });
  activityLogWrites.push({
    id: stableActivityLogId(batchId, METRIC_READINGS_IMPORT_ENTITY, readingId),
    entityTable: METRIC_READINGS_IMPORT_ENTITY,
    entityId: readingId,
    beforeImage:
      existing === undefined ? null : metricReadingImage(existing),
    afterImage,
    occurredAt: updatedAt
  });

  return CanonicalImportMetricReadingResultSchema.parse({
    source: reading.source,
    externalId: reading.externalId,
    metricKey: reading.metricKey,
    status: existing === undefined ? "created" : "refreshed",
    metricReadingId: readingId
  });
}

async function resolveImportedMetricId(
  transaction: CanonicalImportMutationDatabase,
  {
    deviceId,
    normalized,
    reading,
    updatedAt,
    userId
  }: {
    deviceId: string;
    normalized: ReturnType<typeof normalizeMetricReading>;
    reading: StoredMetricReadingInput;
    updatedAt: Date;
    userId: string;
  }
) {
  const catalogSchema = owlMetricSchemaForImportKey(reading.metricKey);
  if (catalogSchema?.metricGroup === "bodyComposition") {
    const existing = await findExistingBodyCompositionMetric(transaction, {
      metricSchema: catalogSchema,
      unit: normalized.unit,
      userId
    });
    if (existing !== null) {
      return existing.id;
    }

    const metricId = stableScopedId(
      "metric",
      userId,
      catalogSchema.canonicalKey
    );
    await transaction
      .insert(schema.metrics)
      .values({
        id: metricId,
        userId,
        deviceId,
        name: catalogSchema.displayName,
        unit: normalized.unit,
        valueShape: normalized.valueShape,
        metricGroup: catalogSchema.metricGroup,
        goalType: catalogSchema.goalType,
        goalTargetValue: null,
        enabled: catalogSchema.enabledByDefault,
        pinned: catalogSchema.pinnedByDefault,
        sortOrder: await nextMetricSortOrder(transaction, userId),
        updatedAt,
        deletedAt: null,
        receivedAt: updatedAt
      })
      .onConflictDoNothing({ target: schema.metrics.id });
    return metricId;
  }

  const canonicalKey = catalogSchema?.canonicalKey ?? reading.metricKey;
  const metricId = stableScopedId("metric", userId, canonicalKey);
  const metricName = catalogSchema?.displayName ?? reading.metricKey;
  const metricGroup = catalogSchema?.metricGroup ?? "monitoring";
  const goalType = catalogSchema?.goalType ?? null;
  const existing = await transaction
    .select({
      id: schema.metrics.id,
      deviceId: schema.metrics.deviceId,
      name: schema.metrics.name,
      unit: schema.metrics.unit,
      valueShape: schema.metrics.valueShape,
      metricGroup: schema.metrics.metricGroup,
      goalType: schema.metrics.goalType,
      deletedAt: schema.metrics.deletedAt
    })
    .from(schema.metrics)
    .where(and(eq(schema.metrics.userId, userId), eq(schema.metrics.id, metricId)))
    .limit(1);
  if (existing[0] === undefined) {
    await transaction.insert(schema.metrics).values({
      id: metricId,
      userId,
      deviceId,
      name: metricName,
      unit: normalized.unit,
      valueShape: normalized.valueShape,
      metricGroup,
      goalType,
      goalTargetValue: null,
      enabled: catalogSchema?.enabledByDefault ?? true,
      pinned: catalogSchema?.pinnedByDefault ?? false,
      sortOrder:
        catalogSchema?.sortOrder ??
        (await nextMetricSortOrder(transaction, userId)),
      updatedAt,
      deletedAt: null,
      receivedAt: updatedAt
    });
    return metricId;
  }

  if (
    existing[0].deviceId !== deviceId ||
    existing[0].name !== metricName ||
    existing[0].unit !== normalized.unit ||
    existing[0].valueShape !== normalized.valueShape ||
    existing[0].metricGroup !== metricGroup ||
    existing[0].goalType !== goalType ||
    existing[0].deletedAt !== null
  ) {
    await transaction
      .update(schema.metrics)
      .set({
        deviceId,
        name: metricName,
        unit: normalized.unit,
        valueShape: normalized.valueShape,
        metricGroup,
        goalType,
        updatedAt,
        deletedAt: null,
        receivedAt: updatedAt
      })
      .where(and(eq(schema.metrics.userId, userId), eq(schema.metrics.id, metricId)));
  }
  return metricId;
}

async function findExistingBodyCompositionMetric(
  transaction: CanonicalImportMutationDatabase,
  {
    metricSchema,
    unit,
    userId
  }: {
    metricSchema: PerenniaMetricSchema;
    unit: string;
    userId: string;
  }
) {
  const rows = await transaction
    .select()
    .from(schema.metrics)
    .where(
      and(
        eq(schema.metrics.userId, userId),
        eq(schema.metrics.metricGroup, "bodyComposition"),
        eq(schema.metrics.valueShape, "scalar"),
        isNull(schema.metrics.deletedAt)
      )
    )
    .orderBy(asc(schema.metrics.sortOrder), asc(schema.metrics.id));

  const normalizedName = normalizeMetricLookupKey(metricSchema.displayName);
  return (
    rows.find(
      (row) =>
        row.unit === unit &&
        normalizeMetricLookupKey(row.name) === normalizedName
    ) ?? null
  );
}

async function nextMetricSortOrder(
  transaction: CanonicalImportMutationDatabase,
  userId: string
) {
  const rows = await transaction
    .select({ sortOrder: schema.metrics.sortOrder })
    .from(schema.metrics)
    .where(
      and(eq(schema.metrics.userId, userId), isNull(schema.metrics.deletedAt))
    );
  return rows.reduce((next, row) => Math.max(next, row.sortOrder + 1), 0);
}

type MonitoringSeriesImportStatus =
  | "created"
  | "refreshed"
  | "tombstoned"
  | "notStored";

async function storeMonitoringSeriesInTransaction(
  transaction: CanonicalImportMutationDatabase,
  {
    activityLogWrites,
    batchId,
    deviceId,
    series,
    updatedAt,
    userId
  }: {
    activityLogWrites: ActivityLogWrite[];
    batchId: string;
    deviceId: string;
    series: CanonicalSeries;
    updatedAt: Date;
    userId: string;
  }
): Promise<{ id: string | null; status: MonitoringSeriesImportStatus }> {
  const externalActivityId = await resolveMonitoringSeriesExternalActivityId(
    transaction,
    { series, userId }
  );
  if (externalActivityId === "notStored") {
    return { id: null, status: "notStored" };
  }

  const existingRows = await transaction
    .select()
    .from(schema.monitoringSeries)
    .where(
      and(
        eq(schema.monitoringSeries.userId, userId),
        eq(schema.monitoringSeries.source, series.source),
        eq(schema.monitoringSeries.externalId, series.externalId)
      )
    )
    .limit(1);
  const existing = existingRows[0];
  if (existing?.deletedAt !== null && existing?.deletedAt !== undefined) {
    return { id: existing.id, status: "tombstoned" };
  }

  const encoded = encodeCanonicalSeriesBlob(series);
  const seriesId = existing?.id ?? generateUuidV7(updatedAt);
  const rowValues = {
    id: seriesId,
    userId,
    deviceId,
    externalActivityId,
    source: series.source,
    externalId: series.externalId,
    seriesType: series.type,
    anchorJson: series.anchor,
    baseTime: parseCanonicalInstant(series.baseTime),
    timezone: series.timezone,
    sampleCount: series.samples.length,
    encoding: encoded.encoding,
    compression: encoded.compression,
    blob: encoded.blob,
    uncompressedByteLength: encoded.uncompressedByteLength,
    compressedByteLength: encoded.compressedByteLength,
    sha256: encoded.sha256,
    provenance: CANONICAL_IMPORT_ACTIVITY_LOG_ACTOR,
    updatedAt,
    deletedAt: null,
    receivedAt: updatedAt
  };

  if (existing === undefined) {
    await transaction.insert(schema.monitoringSeries).values(rowValues);
  } else {
    await transaction
      .update(schema.monitoringSeries)
      .set(rowValues)
      .where(eq(schema.monitoringSeries.id, seriesId));
  }

  activityLogWrites.push({
    id: stableActivityLogId(batchId, MONITORING_SERIES_IMPORT_ENTITY, seriesId),
    entityTable: MONITORING_SERIES_IMPORT_ENTITY,
    entityId: seriesId,
    beforeImage:
      existing === undefined ? null : monitoringSeriesImage(existing),
    afterImage: monitoringSeriesImage(rowValues),
    occurredAt: updatedAt
  });

  return {
    id: seriesId,
    status: existing === undefined ? "created" : "refreshed"
  };
}

async function resolveMonitoringSeriesExternalActivityId(
  transaction: CanonicalImportMutationDatabase,
  {
    series,
    userId
  }: {
    series: CanonicalSeries;
    userId: string;
  }
): Promise<string | null | "notStored"> {
  if (series.anchor.kind !== "activity") {
    return null;
  }

  const rows = await transaction
    .select({
      id: schema.externalActivities.id,
      deletedAt: schema.externalActivities.deletedAt
    })
    .from(schema.externalActivities)
    .where(
      and(
        eq(schema.externalActivities.userId, userId),
        eq(schema.externalActivities.source, series.anchor.source),
        eq(schema.externalActivities.externalId, series.anchor.externalId)
      )
    )
    .limit(1);
  const row = rows[0];
  if (row === undefined || row.deletedAt !== null) {
    return "notStored";
  }

  return row.id;
}

function canonicalImportNoopBatchWrite({
  batchId,
  idempotencyKey,
  occurredAt,
  request,
  resultCounts
}: {
  batchId: string;
  idempotencyKey: string;
  occurredAt: Date;
  request: CanonicalImportRequest;
  resultCounts: {
    activities: number;
    metricReadings: number;
    reviewFlags: number;
    seriesAccepted: number;
  };
}): ActivityLogWrite {
  return {
    id: stableActivityLogId(
      batchId,
      CANONICAL_IMPORT_BATCHES_ENTITY,
      batchId
    ),
    entityTable: CANONICAL_IMPORT_BATCHES_ENTITY,
    entityId: batchId,
    beforeImage: null,
    afterImage: {
      idempotencyKey,
      batchId,
      status: "accepted_noop",
      requested: {
        activities: request.activities.length,
        metricReadings: request.metricReadings.length,
        series: request.series.length
      },
      resultCounts,
      occurredAt: occurredAt.toISOString()
    },
    occurredAt
  };
}

function emptyCanonicalImportResponse({
  duplicate,
  idempotencyKey,
  batchId,
  serverClock
}: {
  duplicate: boolean;
  idempotencyKey: string;
  batchId: string;
  serverClock: Date;
}): CanonicalImportResponse {
  return CanonicalImportResponseSchema.parse({
    accepted: true,
    duplicate,
    idempotencyKey,
    batchId,
    serverClock: serverClock.toISOString(),
    activities: [],
    metricReadings: [],
    seriesAccepted: 0,
    reviewFlags: [],
    materializedWorkouts: [],
    activityLinks: [],
    activityLinkSuggestions: []
  });
}

function metricReadingNormalizationInput(
  reading: StoredMetricReadingInput
): MetricReadingNormalizationInput {
  return {
    metric: {
      valueShape: canonicalValueShape(reading.value),
      unit: canonicalValueUnit(reading.value)
    },
    value: canonicalValueToMetricInput(reading.value),
    timeAnchor: canonicalTimeAnchorToMetricInput(reading.at)
  };
}

function canonicalValueShape(
  value: StoredMetricReadingInput["value"]
): "scalar" | "structured" {
  return isCanonicalScalarValue(value) ? "scalar" : "structured";
}

function canonicalValueUnit(value: StoredMetricReadingInput["value"]) {
  return isCanonicalScalarValue(value) ? value.unit : "structured";
}

function canonicalValueToMetricInput(
  value: StoredMetricReadingInput["value"]
): MetricReadingNormalizationInput["value"] {
  if (isCanonicalScalarValue(value)) {
    return {
      shape: "scalar",
      entered: value.value.toString(),
      unit: value.unit
    };
  }

  return {
    shape: "structured",
    fields: Object.fromEntries(
      Object.entries(value).map(([fieldName, fieldValue]) => [
        fieldName,
        {
          entered: fieldValue.value.toString(),
          unit: fieldValue.unit
        }
      ])
    )
  };
}

function canonicalTimeAnchorToMetricInput(
  at: StoredMetricReadingInput["at"]
): MetricReadingNormalizationInput["timeAnchor"] {
  if (at.kind === "instant") {
    return { atTime: at.at };
  }

  return {
    windowStartedAt: at.startedAt,
    windowEndedAt: at.endedAt
  };
}

function isCanonicalScalarValue(
  value: StoredMetricReadingInput["value"]
): value is { value: number; unit: string } {
  return (
    typeof value === "object" &&
    value !== null &&
    "value" in value &&
    "unit" in value &&
    typeof value.value === "number" &&
    typeof value.unit === "string"
  );
}

function scalarEnteredValue(reading: StoredMetricReadingInput) {
  return isCanonicalScalarValue(reading.value)
    ? reading.value.value.toString()
    : null;
}

function mapStoredExternalActivity(
  row: typeof schema.externalActivities.$inferSelect
): StoredExternalActivity {
  return {
    id: row.id,
    userId: row.userId,
    deviceId: row.deviceId,
    source: row.source,
    externalId: row.externalId,
    startedAt: row.startedAt.toISOString(),
    endedAt: row.endedAt.toISOString(),
    timezone: row.timezone,
    activityType: row.activityType,
    mappedExerciseId: row.mappedExerciseId,
    summary: row.summaryJson as CanonicalActivity["summary"],
    summaryMetrics:
      row.summaryMetricsJson as CanonicalActivity["summaryMetrics"],
    sets: (row.setsJson ?? undefined) as CanonicalActivity["sets"],
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  };
}

function externalActivityRowImage(
  row: typeof schema.externalActivities.$inferSelect
) {
  return {
    id: row.id,
    userId: row.userId,
    deviceId: row.deviceId,
    source: row.source,
    externalId: row.externalId,
    startedAt: row.startedAt.toISOString(),
    endedAt: row.endedAt.toISOString(),
    timezone: row.timezone,
    activityType: row.activityType,
    mappedExerciseId: row.mappedExerciseId,
    summary: row.summaryJson,
    summaryMetrics: row.summaryMetricsJson,
    sets: row.setsJson,
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  };
}

function externalActivityStoredImage(activity: StoredExternalActivity) {
  return {
    id: activity.id,
    userId: activity.userId,
    deviceId: activity.deviceId,
    source: activity.source,
    externalId: activity.externalId,
    startedAt: activity.startedAt,
    endedAt: activity.endedAt,
    timezone: activity.timezone,
    activityType: activity.activityType,
    mappedExerciseId: activity.mappedExerciseId,
    summary: activity.summary,
    summaryMetrics: activity.summaryMetrics,
    sets: activity.sets ?? null,
    updatedAt: activity.updatedAt,
    deletedAt: activity.deletedAt
  };
}

function activityLinkFromRow(
  row:
    | typeof schema.activityLinks.$inferSelect
    | typeof schema.activityLinks.$inferInsert,
  status: CanonicalActivityLink["status"]
): CanonicalActivityLink {
  return {
    id: row.id,
    workoutId: row.workoutId,
    externalActivityId: row.externalActivityId,
    linkKind: row.linkKind,
    status
  };
}

function activityLinkRowImage(
  row: Pick<
    typeof schema.activityLinks.$inferSelect,
    | "deletedAt"
    | "deviceId"
    | "externalActivityId"
    | "id"
    | "linkKind"
    | "receivedAt"
    | "updatedAt"
    | "userId"
    | "workoutId"
  >
) {
  return {
    id: row.id,
    userId: row.userId,
    deviceId: row.deviceId,
    workoutId: row.workoutId,
    externalActivityId: row.externalActivityId,
    linkKind: row.linkKind,
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null,
    receivedAt: row.receivedAt.toISOString()
  };
}

function metricReadingImage(
  row: Pick<
    typeof schema.metricReadings.$inferSelect,
    | "atTime"
    | "comment"
    | "deletedAt"
    | "deviceId"
    | "externalId"
    | "externalActivityId"
    | "id"
    | "metricId"
    | "provenance"
    | "receivedAt"
    | "scalarEntered"
    | "scalarValue"
    | "source"
    | "updatedAt"
    | "userId"
    | "valueJson"
    | "windowEndedAt"
    | "windowStartedAt"
  >
) {
  return {
    id: row.id,
    userId: row.userId,
    deviceId: row.deviceId,
    metricId: row.metricId,
    externalActivityId: row.externalActivityId,
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
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null,
    receivedAt: row.receivedAt.toISOString()
  };
}

function monitoringSeriesImage(
  row: Pick<
    typeof schema.monitoringSeries.$inferSelect,
    | "anchorJson"
    | "baseTime"
    | "compressedByteLength"
    | "compression"
    | "deletedAt"
    | "deviceId"
    | "encoding"
    | "externalActivityId"
    | "externalId"
    | "id"
    | "provenance"
    | "receivedAt"
    | "sampleCount"
    | "seriesType"
    | "sha256"
    | "source"
    | "timezone"
    | "uncompressedByteLength"
    | "updatedAt"
    | "userId"
  >
) {
  return {
    id: row.id,
    userId: row.userId,
    deviceId: row.deviceId,
    externalActivityId: row.externalActivityId,
    source: row.source,
    externalId: row.externalId,
    seriesType: row.seriesType,
    anchor: row.anchorJson,
    baseTime: row.baseTime.toISOString(),
    timezone: row.timezone,
    sampleCount: row.sampleCount,
    encoding: row.encoding,
    compression: row.compression,
    uncompressedByteLength: row.uncompressedByteLength,
    compressedByteLength: row.compressedByteLength,
    sha256: row.sha256,
    provenance: row.provenance,
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null,
    receivedAt: row.receivedAt.toISOString()
  };
}

function canonicalImportReferenceSummary(
  items: readonly unknown[]
): CanonicalImportReferenceSummary {
  const references = items
    .slice(0, CANONICAL_IMPORT_OBSERVABILITY_REFERENCE_LIMIT)
    .map(canonicalImportReference);
  return {
    total: items.length,
    omitted: Math.max(
      0,
      items.length - CANONICAL_IMPORT_OBSERVABILITY_REFERENCE_LIMIT
    ),
    items: references
  };
}

function canonicalImportReference(item: unknown): CanonicalImportReference {
  if (!isRecord(item)) {
    return { source: null, externalId: null };
  }

  return {
    source: stringValue(item.source),
    externalId: stringValue(item.externalId)
  };
}

function nullableDate(value: string | null) {
  return value === null ? null : parseCanonicalInstant(value);
}

function dateValue(value: unknown) {
  if (typeof value !== "string") {
    return null;
  }

  const parsed = new Date(value);
  return Number.isNaN(parsed.valueOf()) ? null : parsed;
}

function nullableDateValue(value: unknown) {
  return value === null ? null : dateValue(value);
}

function stringValue(value: unknown) {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function parseCanonicalInstant(value: string) {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.valueOf())) {
    throw new Error("Canonical timestamp must be an ISO-8601 instant.");
  }

  return parsed;
}

function stableScopedId(prefix: string, ...parts: string[]) {
  return `${prefix}:${hashParts(parts)}`;
}

function stableActivityLogId(batchId: string, entityTable: string, entityId: string) {
  return `integration:${hashParts([batchId, entityTable, entityId])}`;
}

function hashParts(parts: string[]) {
  const hash = createHash("sha256");
  for (const part of parts) {
    hash.update(part);
    hash.update("\0");
  }

  return hash.digest("hex").slice(0, 32);
}

function generateUuidV7(now = new Date()) {
  const bytes = randomBytes(16);
  const timestampMs = BigInt(now.getTime());

  bytes[0] = Number((timestampMs >> 40n) & 0xffn);
  bytes[1] = Number((timestampMs >> 32n) & 0xffn);
  bytes[2] = Number((timestampMs >> 24n) & 0xffn);
  bytes[3] = Number((timestampMs >> 16n) & 0xffn);
  bytes[4] = Number((timestampMs >> 8n) & 0xffn);
  bytes[5] = Number(timestampMs & 0xffn);
  bytes[6] = (bytes[6] & 0x0f) | 0x70;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  return [
    bytes.subarray(0, 4).toString("hex"),
    bytes.subarray(4, 6).toString("hex"),
    bytes.subarray(6, 8).toString("hex"),
    bytes.subarray(8, 10).toString("hex"),
    bytes.subarray(10, 16).toString("hex")
  ].join("-");
}
