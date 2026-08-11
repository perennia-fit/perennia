import { createRoute, z } from "@hono/zod-openapi";
import { and, asc, eq, inArray, isNull, sql } from "drizzle-orm";

import { ActivityLinkKindSchema } from "./activity-links.js";
import type { CanonicalSeries } from "./canonical-import.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import {
  MONITORING_SERIES_BLOB_COMPRESSION,
  MONITORING_SERIES_BLOB_ENCODING,
  MONITORING_SERIES_ROUTE_PATH,
  decodeCanonicalSeriesBlob
} from "./monitoring-series.js";

export const WORKOUT_MONITORING_ROUTE_PATH =
  "/monitoring/workouts/{workoutId}";

const WorkoutMonitoringParamsSchema = z
  .object({
    workoutId: z.string().min(1)
  })
  .strict()
  .openapi("WorkoutMonitoringParams");

const JsonObjectSchema = z.record(z.string(), z.unknown());

export const WorkoutMonitoringSummaryReadingSchema = z
  .object({
    id: z.string().min(1),
    metricId: z.string().min(1),
    metricKey: z.string().min(1),
    unit: z.string().min(1),
    value: JsonObjectSchema,
    scalarValue: z.number().finite().nullable(),
    scalarEntered: z.string().nullable(),
    atTime: z.string().min(1).nullable(),
    windowStartedAt: z.string().min(1).nullable(),
    windowEndedAt: z.string().min(1).nullable(),
    provenance: z.string().min(1),
    source: z.string().min(1),
    externalId: z.string().min(1).nullable(),
    comment: z.string().nullable(),
    updatedAt: z.string().min(1)
  })
  .strict()
  .openapi("WorkoutMonitoringSummaryReading");

export const WorkoutMonitoringSeriesMetadataSchema = z
  .object({
    seriesId: z.string().min(1),
    source: z.string().min(1),
    externalId: z.string().min(1),
    seriesType: z.string().min(1),
    externalActivityId: z.string().min(1),
    sampleCount: z.number().int().min(1),
    encoding: z.literal(MONITORING_SERIES_BLOB_ENCODING),
    compression: z.literal(MONITORING_SERIES_BLOB_COMPRESSION),
    sha256: z.string().min(1),
    uncompressedByteLength: z.number().int().min(1),
    compressedByteLength: z.number().int().min(1),
    blobPath: z.string().min(1),
    updatedAt: z.string().min(1)
  })
  .strict()
  .openapi("WorkoutMonitoringSeriesMetadata");

export const WorkoutLinkedExternalActivitySchema = z
  .object({
    id: z.string().min(1),
    source: z.string().min(1),
    externalId: z.string().min(1),
    activityType: z.string().min(1),
    startedAt: z.string().min(1),
    endedAt: z.string().min(1),
    timezone: z.string().min(1),
    linkId: z.string().min(1),
    linkKind: ActivityLinkKindSchema,
    summaryReadings: z.array(WorkoutMonitoringSummaryReadingSchema),
    series: z.array(WorkoutMonitoringSeriesMetadataSchema)
  })
  .strict()
  .openapi("WorkoutLinkedExternalActivity");

export const WorkoutSetHeartRateSchema = z
  .object({
    setId: z.string().min(1),
    position: z.number().int().min(0),
    seriesId: z.string().min(1),
    sampleCount: z.number().int().min(1),
    windowStartedAt: z.string().min(1),
    windowEndedAt: z.string().min(1),
    average: z
      .object({
        value: z.number().finite(),
        unit: z.literal("beatsPerMinute")
      })
      .strict()
  })
  .strict()
  .openapi("WorkoutSetHeartRate");

export const WorkoutMonitoringResponseSchema = z
  .object({
    workoutId: z.string().min(1),
    linkedExternalActivities: z.array(WorkoutLinkedExternalActivitySchema),
    perSetHeartRate: z.array(WorkoutSetHeartRateSchema)
  })
  .strict()
  .openapi("WorkoutMonitoringResponse");

export const WorkoutMonitoringUnauthorizedResponseSchema = z
  .object({
    code: z.literal("sync_unauthorized"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("WorkoutMonitoringUnauthorizedResponse");

export const WorkoutMonitoringNotFoundResponseSchema = z
  .object({
    code: z.literal("workout_monitoring_not_found"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("WorkoutMonitoringNotFoundResponse");

export const WorkoutMonitoringUnavailableResponseSchema = z
  .object({
    code: z.literal("workout_monitoring_unavailable"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("WorkoutMonitoringUnavailableResponse");

export const workoutMonitoringRoute = createRoute({
  method: "get",
  path: WORKOUT_MONITORING_ROUTE_PATH,
  operationId: "getWorkoutMonitoring",
  tags: ["Monitoring"],
  summary: "Read linked Monitoring Data for a Workout.",
  description:
    "Returns read-only Monitoring Summary readings and Monitoring Series metadata for External Activities linked to a Workout. Dense series blobs are fetched separately through the Monitoring Series blob endpoint. Per-set heart rate is derived on demand from observed set timing and never stored.",
  security: [{ bearerAuth: [] }],
  request: {
    params: WorkoutMonitoringParamsSchema
  },
  responses: {
    200: {
      description: "Read-only linked Monitoring Data for the Workout.",
      content: {
        "application/json": {
          schema: WorkoutMonitoringResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid session bearer token.",
      content: {
        "application/json": {
          schema: WorkoutMonitoringUnauthorizedResponseSchema
        }
      }
    },
    404: {
      description: "No live Workout or Activity Link exists for this account.",
      content: {
        "application/json": {
          schema: WorkoutMonitoringNotFoundResponseSchema
        }
      }
    },
    503: {
      description: "Workout Monitoring storage or session auth is unavailable.",
      content: {
        "application/json": {
          schema: WorkoutMonitoringUnavailableResponseSchema
        }
      }
    }
  }
});

export type WorkoutMonitoringResponse = z.infer<
  typeof WorkoutMonitoringResponseSchema
>;

export type WorkoutMonitoringStore = {
  readWorkoutMonitoring(input: {
    userId: string;
    workoutId: string;
  }): Promise<WorkoutMonitoringResponse | null>;
};

type LoggedSetTimingWindow = {
  endedAt: Date;
  setId: string;
  position: number;
  startedAt: Date;
};

type MonitoringSeriesRow = {
  id: string;
  externalActivityId: string | null;
  source: string;
  externalId: string;
  seriesType: string;
  sampleCount: number;
  encoding: string;
  compression: string;
  sha256: string;
  uncompressedByteLength: number;
  compressedByteLength: number;
  blob: Uint8Array;
  updatedAt: Date;
};

export function createDrizzleWorkoutMonitoringStore(
  db: ServerDatabase
): WorkoutMonitoringStore {
  return {
    async readWorkoutMonitoring({ userId, workoutId }) {
      const linkedRows = await db
        .select({
          linkId: schema.activityLinks.id,
          linkKind: schema.activityLinks.linkKind,
          externalActivityId: schema.externalActivities.id,
          source: schema.externalActivities.source,
          externalId: schema.externalActivities.externalId,
          activityType: schema.externalActivities.activityType,
          startedAt: schema.externalActivities.startedAt,
          endedAt: schema.externalActivities.endedAt,
          timezone: schema.externalActivities.timezone
        })
        .from(schema.activityLinks)
        .innerJoin(
          schema.externalActivities,
          eq(schema.activityLinks.externalActivityId, schema.externalActivities.id)
        )
        .where(
          and(
            eq(schema.activityLinks.userId, userId),
            eq(schema.activityLinks.workoutId, workoutId),
            isNull(schema.activityLinks.deletedAt),
            isNull(schema.externalActivities.deletedAt)
          )
        )
        .orderBy(asc(schema.externalActivities.startedAt), asc(schema.activityLinks.id));

      const setRows = await db
        .select({
          id: schema.loggedSets.id,
          payload: schema.loggedSets.payload
        })
        .from(schema.loggedSets)
        .where(
          and(
            eq(schema.loggedSets.userId, userId),
            isNull(schema.loggedSets.deletedAt),
            sql`${schema.loggedSets.payload}->>'workout_id' = ${workoutId}`
          )
        )
        .orderBy(
          sql`(${schema.loggedSets.payload}->>'position')::int`,
          asc(schema.loggedSets.id)
        );

      if (linkedRows.length === 0 && setRows.length === 0) {
        return null;
      }

      const externalActivityIds = linkedRows.map(
        (row) => row.externalActivityId
      );
      const [readingRows, seriesRows] =
        externalActivityIds.length === 0
          ? [[], []]
          : await Promise.all([
              readSummaryReadings(db, { userId, externalActivityIds }),
              readMonitoringSeries(db, { userId, externalActivityIds })
            ]);
      const readingsByActivity = groupBy(readingRows, (row) => row.externalActivityId);
      const seriesByActivity = groupBy(
        seriesRows.filter((row) => row.externalActivityId !== null),
        (row) => row.externalActivityId ?? ""
      );

      return WorkoutMonitoringResponseSchema.parse({
        workoutId,
        linkedExternalActivities: linkedRows.map((row) => ({
          id: row.externalActivityId,
          source: row.source,
          externalId: row.externalId,
          activityType: row.activityType,
          startedAt: row.startedAt.toISOString(),
          endedAt: row.endedAt.toISOString(),
          timezone: row.timezone,
          linkId: row.linkId,
          linkKind: row.linkKind,
          summaryReadings: (readingsByActivity.get(row.externalActivityId) ?? [])
            .map((reading) => ({
              id: reading.id,
              metricId: reading.metricId,
              metricKey: reading.metricKey,
              unit: reading.unit,
              value: reading.value,
              scalarValue: reading.scalarValue,
              scalarEntered: reading.scalarEntered,
              atTime: isoOrNull(reading.atTime),
              windowStartedAt: isoOrNull(reading.windowStartedAt),
              windowEndedAt: isoOrNull(reading.windowEndedAt),
              provenance: reading.provenance,
              source: reading.source,
              externalId: reading.externalId,
              comment: reading.comment,
              updatedAt: reading.updatedAt.toISOString()
            })),
          series: (seriesByActivity.get(row.externalActivityId) ?? []).map(
            seriesMetadata
          )
        })),
        perSetHeartRate: derivePerSetHeartRate({
          seriesRows,
          setRows: setRows.map((row) => ({
            id: row.id,
            payload: row.payload
          }))
        })
      });
    }
  };
}

async function readSummaryReadings(
  db: ServerDatabase,
  {
    externalActivityIds,
    userId
  }: {
    externalActivityIds: string[];
    userId: string;
  }
) {
  return db
    .select({
      id: schema.metricReadings.id,
      externalActivityId: schema.metricReadings.externalActivityId,
      metricId: schema.metricReadings.metricId,
      metricKey: schema.metrics.name,
      unit: schema.metrics.unit,
      value: schema.metricReadings.valueJson,
      scalarValue: schema.metricReadings.scalarValue,
      scalarEntered: schema.metricReadings.scalarEntered,
      atTime: schema.metricReadings.atTime,
      windowStartedAt: schema.metricReadings.windowStartedAt,
      windowEndedAt: schema.metricReadings.windowEndedAt,
      provenance: schema.metricReadings.provenance,
      source: schema.metricReadings.source,
      externalId: schema.metricReadings.externalId,
      comment: schema.metricReadings.comment,
      updatedAt: schema.metricReadings.updatedAt
    })
    .from(schema.metricReadings)
    .innerJoin(schema.metrics, eq(schema.metricReadings.metricId, schema.metrics.id))
    .where(
      and(
        eq(schema.metricReadings.userId, userId),
        inArray(schema.metricReadings.externalActivityId, externalActivityIds),
        isNull(schema.metricReadings.deletedAt),
        isNull(schema.metrics.deletedAt)
      )
    )
    .orderBy(asc(schema.metricReadings.windowStartedAt), asc(schema.metricReadings.id));
}

async function readMonitoringSeries(
  db: ServerDatabase,
  {
    externalActivityIds,
    userId
  }: {
    externalActivityIds: string[];
    userId: string;
  }
): Promise<MonitoringSeriesRow[]> {
  return db
    .select({
      id: schema.monitoringSeries.id,
      externalActivityId: schema.monitoringSeries.externalActivityId,
      source: schema.monitoringSeries.source,
      externalId: schema.monitoringSeries.externalId,
      seriesType: schema.monitoringSeries.seriesType,
      sampleCount: schema.monitoringSeries.sampleCount,
      encoding: schema.monitoringSeries.encoding,
      compression: schema.monitoringSeries.compression,
      sha256: schema.monitoringSeries.sha256,
      uncompressedByteLength: schema.monitoringSeries.uncompressedByteLength,
      compressedByteLength: schema.monitoringSeries.compressedByteLength,
      blob: schema.monitoringSeries.blob,
      updatedAt: schema.monitoringSeries.updatedAt
    })
    .from(schema.monitoringSeries)
    .where(
      and(
        eq(schema.monitoringSeries.userId, userId),
        inArray(schema.monitoringSeries.externalActivityId, externalActivityIds),
        isNull(schema.monitoringSeries.deletedAt)
      )
    )
    .orderBy(asc(schema.monitoringSeries.seriesType), asc(schema.monitoringSeries.id));
}

function seriesMetadata(row: MonitoringSeriesRow) {
  return {
    seriesId: row.id,
    source: row.source,
    externalId: row.externalId,
    seriesType: row.seriesType,
    externalActivityId: row.externalActivityId,
    sampleCount: row.sampleCount,
    encoding: row.encoding,
    compression: row.compression,
    sha256: row.sha256,
    uncompressedByteLength: row.uncompressedByteLength,
    compressedByteLength: row.compressedByteLength,
    blobPath: MONITORING_SERIES_ROUTE_PATH.replace("{seriesId}", row.id),
    updatedAt: row.updatedAt.toISOString()
  };
}

function derivePerSetHeartRate({
  seriesRows,
  setRows
}: {
  seriesRows: MonitoringSeriesRow[];
  setRows: Array<{ id: string; payload: Record<string, unknown> }>;
}) {
  const windows = setRows.flatMap((row) => {
    const window = timingWindowForSet(row);
    return window === null ? [] : [window];
  });
  if (windows.length === 0) {
    return [];
  }

  const heartRateSeries = seriesRows
    .filter((row) => row.seriesType === "heartRate")
    .map((row) => ({ row, series: decodeCanonicalSeriesBlob(row.blob) }));

  return windows.flatMap((window) =>
    heartRateSeries.flatMap(({ row, series }) => {
      const samples = heartRateSamplesInWindow(series, window);
      if (samples.length === 0) {
        return [];
      }

      return [
        {
          setId: window.setId,
          position: window.position,
          seriesId: row.id,
          sampleCount: samples.length,
          windowStartedAt: window.startedAt.toISOString(),
          windowEndedAt: window.endedAt.toISOString(),
          average: {
            value: canonicalNumber(
              samples.reduce((total, sample) => total + sample, 0) /
                samples.length
            ),
            unit: "beatsPerMinute" as const
          }
        }
      ];
    })
  );
}

function timingWindowForSet({
  id,
  payload
}: {
  id: string;
  payload: Record<string, unknown>;
}): LoggedSetTimingWindow | null {
  const performedAt = dateValue(payload.performed_at);
  const startedAt =
    dateValue(payload.performed_started_at) ??
    dateValue(payload.performed_start_at);
  const endedAt =
    dateValue(payload.performed_ended_at) ?? dateValue(payload.performed_end_at);

  if (startedAt !== null && endedAt !== null && endedAt >= startedAt) {
    return {
      setId: id,
      position: integerValue(payload.position) ?? 0,
      startedAt,
      endedAt
    };
  }

  if (performedAt === null) {
    return null;
  }

  const durationSeconds = durationSecondsValue(payload);
  return {
    setId: id,
    position: integerValue(payload.position) ?? 0,
    startedAt: performedAt,
    endedAt:
      durationSeconds === null
        ? performedAt
        : new Date(performedAt.getTime() + durationSeconds * 1000)
  };
}

function heartRateSamplesInWindow(
  series: CanonicalSeries,
  window: LoggedSetTimingWindow
) {
  const baseTime = new Date(series.baseTime).getTime();
  return series.samples.flatMap((sample) => {
    const at = new Date(baseTime + sample.offsetSeconds * 1000);
    if (at < window.startedAt || at > window.endedAt) {
      return [];
    }

    const value = heartRateValue(sample.value);
    return value === null ? [] : [value];
  });
}

function heartRateValue(
  value: CanonicalSeries["samples"][number]["value"]
): number | null {
  if (
    typeof value === "object" &&
    value !== null &&
    "value" in value &&
    "unit" in value &&
    value.unit === "beatsPerMinute" &&
    typeof value.value === "number"
  ) {
    return value.value;
  }

  return null;
}

function durationSecondsValue(payload: Record<string, unknown>) {
  const values = recordValue(payload.values);
  const duration = values === null ? null : recordValue(values.duration);
  if (duration === null || stringValue(duration.unit) !== "second") {
    return null;
  }

  const value =
    numberValue(duration.value) ?? numberValue(duration.entered) ?? null;
  return value === null || value <= 0 ? null : value;
}

function groupBy<T>(
  rows: T[],
  keyFor: (row: T) => string | null
): Map<string, T[]> {
  const grouped = new Map<string, T[]>();
  for (const row of rows) {
    const key = keyFor(row);
    if (key === null) {
      continue;
    }
    const existing = grouped.get(key) ?? [];
    existing.push(row);
    grouped.set(key, existing);
  }

  return grouped;
}

function isoOrNull(value: Date | null) {
  return value === null ? null : value.toISOString();
}

function dateValue(value: unknown): Date | null {
  if (typeof value !== "string" || value.length === 0) {
    return null;
  }

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function integerValue(value: unknown): number | null {
  if (typeof value === "number" && Number.isInteger(value)) {
    return value;
  }
  if (typeof value !== "string" || value.length === 0) {
    return null;
  }

  const parsed = Number.parseInt(value, 10);
  return Number.isInteger(parsed) ? parsed : null;
}

function numberValue(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value !== "string" || value.length === 0) {
    return null;
  }

  const parsed = Number.parseFloat(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function recordValue(value: unknown): Record<string, unknown> | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }

  return value as Record<string, unknown>;
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function canonicalNumber(value: number) {
  return Number.parseFloat(value.toFixed(6));
}
