import { createHash } from "node:crypto";
import { gzipSync, gunzipSync } from "node:zlib";
import { createRoute, z } from "@hono/zod-openapi";
import { and, eq, isNull } from "drizzle-orm";

import {
  CanonicalMetricValueSchema,
  CanonicalSeriesAnchorSchema,
  CanonicalSeriesSchema,
  type CanonicalSeries
} from "./canonical-import.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";

export const MONITORING_SERIES_ROUTE_PATH =
  "/monitoring/series/{seriesId}/blob";
export const MONITORING_SERIES_BLOB_ENCODING =
  "canonical-series-delta-json-v1";
export const MONITORING_SERIES_BLOB_COMPRESSION = "gzip";

const MonitoringSeriesBlobParamsSchema = z
  .object({
    seriesId: z.string().min(1)
  })
  .strict()
  .openapi("MonitoringSeriesBlobParams");

export const MonitoringSeriesBlobResponseSchema = z
  .object({
    seriesId: z.string().min(1),
    source: z.string().min(1),
    externalId: z.string().min(1),
    seriesType: z.string().min(1),
    externalActivityId: z.string().min(1).nullable(),
    sampleCount: z.number().int().min(1),
    encoding: z.literal(MONITORING_SERIES_BLOB_ENCODING),
    compression: z.literal(MONITORING_SERIES_BLOB_COMPRESSION),
    sha256: z.string().min(1),
    uncompressedByteLength: z.number().int().min(1),
    compressedByteLength: z.number().int().min(1),
    blobBase64: z.string().min(1),
    updatedAt: z.string().min(1)
  })
  .strict()
  .openapi("MonitoringSeriesBlobResponse");

export const MonitoringSeriesUnauthorizedResponseSchema = z
  .object({
    code: z.literal("sync_unauthorized"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("MonitoringSeriesUnauthorizedResponse");

export const MonitoringSeriesNotFoundResponseSchema = z
  .object({
    code: z.literal("monitoring_series_not_found"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("MonitoringSeriesNotFoundResponse");

export const MonitoringSeriesUnavailableResponseSchema = z
  .object({
    code: z.literal("monitoring_series_unavailable"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("MonitoringSeriesUnavailableResponse");

export const monitoringSeriesBlobRoute = createRoute({
  method: "get",
  path: MONITORING_SERIES_ROUTE_PATH,
  operationId: "getMonitoringSeriesBlob",
  tags: ["Monitoring"],
  summary: "Fetch a compressed Monitoring Series blob.",
  description:
    "Returns an immutable, compressed, delta-encoded Monitoring Series blob on demand. Series blobs are not part of ordinary row-sync delta windows and are intended for deep analysis paths.",
  security: [{ bearerAuth: [] }],
  request: {
    params: MonitoringSeriesBlobParamsSchema
  },
  responses: {
    200: {
      description: "The compressed Monitoring Series blob and safe metadata.",
      content: {
        "application/json": {
          schema: MonitoringSeriesBlobResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid session bearer token.",
      content: {
        "application/json": {
          schema: MonitoringSeriesUnauthorizedResponseSchema
        }
      }
    },
    404: {
      description: "No Monitoring Series blob exists for this account and id.",
      content: {
        "application/json": {
          schema: MonitoringSeriesNotFoundResponseSchema
        }
      }
    },
    503: {
      description: "Monitoring Series storage or session auth is unavailable.",
      content: {
        "application/json": {
          schema: MonitoringSeriesUnavailableResponseSchema
        }
      }
    }
  }
});

export type MonitoringSeriesBlobResponse = z.infer<
  typeof MonitoringSeriesBlobResponseSchema
>;

export type MonitoringSeriesStore = {
  fetchMonitoringSeriesBlob(input: {
    seriesId: string;
    userId: string;
  }): Promise<MonitoringSeriesBlobResponse | null>;
};

export type EncodedMonitoringSeriesBlob = {
  blob: Buffer;
  compressedByteLength: number;
  encoding: typeof MONITORING_SERIES_BLOB_ENCODING;
  compression: typeof MONITORING_SERIES_BLOB_COMPRESSION;
  sha256: string;
  uncompressedByteLength: number;
};

const DeltaEncodedMonitoringSeriesBlobSchema = z
  .object({
    version: z.literal(1),
    source: z.string().min(1),
    externalId: z.string().min(1),
    seriesType: z.string().min(1),
    anchor: CanonicalSeriesAnchorSchema,
    baseTime: z.string().min(1),
    timezone: z.string().min(1),
    samples: z
      .array(
        z
          .object({
            deltaSeconds: z.number().finite(),
            value: CanonicalMetricValueSchema
          })
          .strict()
      )
      .min(1)
  })
  .strict();

export function encodeCanonicalSeriesBlob(
  series: CanonicalSeries
): EncodedMonitoringSeriesBlob {
  let previousOffsetSeconds = 0;
  const payload = DeltaEncodedMonitoringSeriesBlobSchema.parse({
    version: 1,
    source: series.source,
    externalId: series.externalId,
    seriesType: series.type,
    anchor: series.anchor,
    baseTime: series.baseTime,
    timezone: series.timezone,
    samples: series.samples.map((sample) => {
      const deltaSeconds = sample.offsetSeconds - previousOffsetSeconds;
      previousOffsetSeconds = sample.offsetSeconds;

      return {
        deltaSeconds,
        value: sample.value
      };
    })
  });
  const uncompressed = Buffer.from(JSON.stringify(payload), "utf8");
  const blob = gzipSync(uncompressed);

  return {
    blob,
    compressedByteLength: blob.byteLength,
    encoding: MONITORING_SERIES_BLOB_ENCODING,
    compression: MONITORING_SERIES_BLOB_COMPRESSION,
    sha256: createHash("sha256").update(blob).digest("hex"),
    uncompressedByteLength: uncompressed.byteLength
  };
}

export function decodeCanonicalSeriesBlob(blob: Uint8Array): CanonicalSeries {
  const payload = DeltaEncodedMonitoringSeriesBlobSchema.parse(
    JSON.parse(gunzipSync(blob).toString("utf8"))
  );
  let offsetSeconds = 0;

  return CanonicalSeriesSchema.parse({
    source: payload.source,
    externalId: payload.externalId,
    type: payload.seriesType,
    anchor: payload.anchor,
    baseTime: payload.baseTime,
    timezone: payload.timezone,
    samples: payload.samples.map((sample) => {
      offsetSeconds += sample.deltaSeconds;

      return {
        offsetSeconds,
        value: sample.value
      };
    })
  });
}

export function createDrizzleMonitoringSeriesStore(
  db: ServerDatabase
): MonitoringSeriesStore {
  return {
    async fetchMonitoringSeriesBlob({ seriesId, userId }) {
      const rows = await db
        .select({
          id: schema.monitoringSeries.id,
          source: schema.monitoringSeries.source,
          externalId: schema.monitoringSeries.externalId,
          seriesType: schema.monitoringSeries.seriesType,
          externalActivityId: schema.monitoringSeries.externalActivityId,
          sampleCount: schema.monitoringSeries.sampleCount,
          encoding: schema.monitoringSeries.encoding,
          compression: schema.monitoringSeries.compression,
          sha256: schema.monitoringSeries.sha256,
          uncompressedByteLength:
            schema.monitoringSeries.uncompressedByteLength,
          compressedByteLength: schema.monitoringSeries.compressedByteLength,
          blob: schema.monitoringSeries.blob,
          updatedAt: schema.monitoringSeries.updatedAt
        })
        .from(schema.monitoringSeries)
        .where(
          and(
            eq(schema.monitoringSeries.userId, userId),
            eq(schema.monitoringSeries.id, seriesId),
            isNull(schema.monitoringSeries.deletedAt)
          )
        )
        .limit(1);
      const row = rows[0];
      if (row === undefined) {
        return null;
      }

      const blob = Buffer.from(row.blob);
      return MonitoringSeriesBlobResponseSchema.parse({
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
        blobBase64: blob.toString("base64"),
        updatedAt: row.updatedAt.toISOString()
      });
    }
  };
}
