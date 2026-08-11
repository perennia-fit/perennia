import { createHash } from "node:crypto";
import { createRoute, z } from "@hono/zod-openapi";
import { and, eq, inArray, isNull, sql } from "drizzle-orm";

import { ACTIVITY_LINK_KIND_MATERIALIZED_SOURCE } from "./activity-links.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";

export const IMPORTED_DATA_PURGE_ACTIVITY_LOG_ACTOR = "app";
export const IMPORTED_DATA_PURGE_DEVICE_ID = "app:imported-data-purge";
export const IMPORTED_DATA_PURGES_ENTITY = "imported_data_purges";

export const ImportedDataPurgeSourceSchema = z
  .enum(["garmin"])
  .openapi("ImportedDataPurgeSource");

export const ImportedDataPurgeScopeSchema = z
  .enum(["all", "gpsOnly"])
  .openapi("ImportedDataPurgeScope");

export const ImportedDataPurgeRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200),
    source: ImportedDataPurgeSourceSchema,
    scope: ImportedDataPurgeScopeSchema
  })
  .strict()
  .openapi("ImportedDataPurgeRequest");

export const ImportedDataPurgeCountsSchema = z
  .object({
    externalActivities: z.number().int().nonnegative(),
    metricReadings: z.number().int().nonnegative(),
    monitoringSeries: z.number().int().nonnegative(),
    materializedSets: z.number().int().nonnegative(),
    activityLinks: z.number().int().nonnegative()
  })
  .strict()
  .openapi("ImportedDataPurgeCounts");

export const ImportedDataPurgeResponseSchema = z
  .object({
    accepted: z.literal(true),
    duplicate: z.boolean(),
    batchId: z.string().min(1),
    serverClock: z.string().min(1),
    source: ImportedDataPurgeSourceSchema,
    scope: ImportedDataPurgeScopeSchema,
    tombstonedCounts: ImportedDataPurgeCountsSchema
  })
  .strict()
  .openapi("ImportedDataPurgeResponse");

export const ImportedDataPurgeUnauthorizedResponseSchema = z
  .object({
    code: z.literal("imported_data_purge_unauthorized"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("ImportedDataPurgeUnauthorizedResponse");

export const ImportedDataPurgeUnavailableResponseSchema = z
  .object({
    code: z.literal("imported_data_purge_unavailable"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("ImportedDataPurgeUnavailableResponse");

export const importedDataPurgeRoute = createRoute({
  method: "post",
  path: "/integrations/imported-data/purge",
  operationId: "purgeImportedData",
  tags: ["Integrations"],
  summary: "Purge imported Integration data from Settings.",
  description:
    "Session-authenticated Settings action. Purge is explicit and separate from disconnect; it writes tombstones and one Activity Log batch without storing Monitoring Data values in the log.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: ImportedDataPurgeRequestSchema
        }
      }
    }
  },
  responses: {
    200: {
      description: "The requested imported data has been tombstoned.",
      content: {
        "application/json": {
          schema: ImportedDataPurgeResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid session bearer token.",
      content: {
        "application/json": {
          schema: ImportedDataPurgeUnauthorizedResponseSchema
        }
      }
    },
    503: {
      description: "Imported data purge storage is not configured.",
      content: {
        "application/json": {
          schema: ImportedDataPurgeUnavailableResponseSchema
        }
      }
    }
  }
});

export type ImportedDataPurgeSource = z.infer<
  typeof ImportedDataPurgeSourceSchema
>;
export type ImportedDataPurgeScope = z.infer<typeof ImportedDataPurgeScopeSchema>;
export type ImportedDataPurgeCounts = z.infer<
  typeof ImportedDataPurgeCountsSchema
>;
export type ImportedDataPurgeResponse = z.infer<
  typeof ImportedDataPurgeResponseSchema
>;

export type ImportedDataPurgeAppliedRow = {
  entityTable: string;
  entityId: string;
};

export type ImportedDataPurgeStoreResult = ImportedDataPurgeResponse & {
  applied: ImportedDataPurgeAppliedRow[];
};

export type ImportedDataPurgeStore = {
  purgeImportedData(input: {
    userId: string;
    actor: string;
    batchId: string;
    deviceId: string;
    source: ImportedDataPurgeSource;
    scope: ImportedDataPurgeScope;
  }): Promise<ImportedDataPurgeStoreResult>;
};

type PurgedIds = {
  externalActivityIds: string[];
  metricReadingIds: string[];
  monitoringSeriesIds: string[];
  materializedSetIds: string[];
  activityLinkIds: string[];
};

type ImportedDataPurgeMutationDatabase = Pick<
  ServerDatabase,
  "insert" | "select" | "update"
>;

export function createDrizzleImportedDataPurgeStore(
  db: ServerDatabase
): ImportedDataPurgeStore {
  return {
    async purgeImportedData(input) {
      const serverClock = new Date();
      return db.transaction(async (transaction) => {
        const duplicate = await readDuplicatePurge(transaction, {
          batchId: input.batchId,
          scope: input.scope,
          serverClock,
          source: input.source,
          userId: input.userId
        });
        if (duplicate !== null) {
          return duplicate;
        }

        const ids =
          input.scope === "gpsOnly"
            ? await tombstoneGpsOnly(transaction, { ...input, serverClock })
            : await tombstoneAllImportedData(transaction, {
                ...input,
                serverClock
              });
        const counts = countsFromIds(ids);
        const beforeImage = purgeBeforeImage(input, ids);
        const afterImage = purgeAfterImage(input, ids, counts, serverClock);

        await transaction
          .insert(schema.activityLog)
          .values({
            id: stableActivityLogId(input.batchId),
            userId: input.userId,
            actor: input.actor,
            batchId: input.batchId,
            entityTable: IMPORTED_DATA_PURGES_ENTITY,
            entityId: input.batchId,
            beforeImage,
            afterImage,
            occurredAt: serverClock
          })
          .onConflictDoNothing({ target: schema.activityLog.id });

        return {
          ...ImportedDataPurgeResponseSchema.parse({
          accepted: true,
          duplicate: false,
          batchId: input.batchId,
          serverClock: serverClock.toISOString(),
          source: input.source,
          scope: input.scope,
          tombstonedCounts: counts
          }),
          applied: appliedRowsFromIds(ids)
        };
      });
    }
  };
}

async function readDuplicatePurge(
  transaction: ImportedDataPurgeMutationDatabase,
  {
    batchId,
    scope,
    serverClock,
    source,
    userId
  }: {
    batchId: string;
    scope: ImportedDataPurgeScope;
    serverClock: Date;
    source: ImportedDataPurgeSource;
    userId: string;
  }
): Promise<ImportedDataPurgeStoreResult | null> {
  const rows = await transaction
    .select({
      afterImage: schema.activityLog.afterImage
    })
    .from(schema.activityLog)
    .where(
      and(
        eq(schema.activityLog.userId, userId),
        eq(schema.activityLog.actor, IMPORTED_DATA_PURGE_ACTIVITY_LOG_ACTOR),
        eq(schema.activityLog.batchId, batchId),
        eq(schema.activityLog.entityTable, IMPORTED_DATA_PURGES_ENTITY)
      )
    )
    .limit(1);
  const row = rows[0];
  if (row === undefined) {
    return null;
  }

  const counts = countsFromAfterImage(row.afterImage);
  return {
    accepted: true,
    duplicate: true,
    batchId,
    serverClock: serverClock.toISOString(),
    source,
    scope,
    tombstonedCounts: counts,
    applied: []
  };
}

async function tombstoneAllImportedData(
  transaction: ImportedDataPurgeMutationDatabase,
  input: {
    userId: string;
    deviceId: string;
    source: ImportedDataPurgeSource;
    serverClock: Date;
  }
): Promise<PurgedIds> {
  const externalActivityRows = await transaction
    .select({ id: schema.externalActivities.id })
    .from(schema.externalActivities)
    .where(
      and(
        eq(schema.externalActivities.userId, input.userId),
        eq(schema.externalActivities.source, input.source)
      )
    );
  const externalActivityIds = externalActivityRows.map((row) => row.id);

  const activityLinkRows =
    externalActivityIds.length === 0
      ? []
      : await transaction
          .update(schema.activityLinks)
          .set(tombstoneValues(input))
          .where(
            and(
              eq(schema.activityLinks.userId, input.userId),
              inArray(schema.activityLinks.externalActivityId, externalActivityIds),
              eq(
                schema.activityLinks.linkKind,
                ACTIVITY_LINK_KIND_MATERIALIZED_SOURCE
              ),
              isNull(schema.activityLinks.deletedAt)
            )
          )
          .returning({ id: schema.activityLinks.id });

  const materializedSetRows = await transaction
    .update(schema.loggedSets)
    .set(tombstoneValues(input))
    .where(
      and(
        eq(schema.loggedSets.userId, input.userId),
        sql`${schema.loggedSets.payload}->>'provenance' = 'integration'`,
        sql`${schema.loggedSets.payload}->>'source' = ${input.source}`,
        isNull(schema.loggedSets.deletedAt)
      )
    )
    .returning({ id: schema.loggedSets.id });

  const metricReadingRows = await transaction
    .update(schema.metricReadings)
    .set(tombstoneValues(input))
    .where(
      and(
        eq(schema.metricReadings.userId, input.userId),
        eq(schema.metricReadings.source, input.source),
        eq(schema.metricReadings.provenance, "integration"),
        isNull(schema.metricReadings.deletedAt)
      )
    )
    .returning({ id: schema.metricReadings.id });

  const monitoringSeriesRows = await transaction
    .update(schema.monitoringSeries)
    .set(tombstoneValues(input))
    .where(
      and(
        eq(schema.monitoringSeries.userId, input.userId),
        eq(schema.monitoringSeries.source, input.source),
        eq(schema.monitoringSeries.provenance, "integration"),
        isNull(schema.monitoringSeries.deletedAt)
      )
    )
    .returning({ id: schema.monitoringSeries.id });

  const liveExternalActivityRows = await transaction
    .update(schema.externalActivities)
    .set(tombstoneValues(input))
    .where(
      and(
        eq(schema.externalActivities.userId, input.userId),
        eq(schema.externalActivities.source, input.source),
        isNull(schema.externalActivities.deletedAt)
      )
    )
    .returning({ id: schema.externalActivities.id });

  return {
    externalActivityIds: liveExternalActivityRows.map((row) => row.id),
    metricReadingIds: metricReadingRows.map((row) => row.id),
    monitoringSeriesIds: monitoringSeriesRows.map((row) => row.id),
    materializedSetIds: materializedSetRows.map((row) => row.id),
    activityLinkIds: activityLinkRows.map((row) => row.id)
  };
}

async function tombstoneGpsOnly(
  transaction: ImportedDataPurgeMutationDatabase,
  input: {
    userId: string;
    deviceId: string;
    source: ImportedDataPurgeSource;
    serverClock: Date;
  }
): Promise<PurgedIds> {
  const monitoringSeriesRows = await transaction
    .update(schema.monitoringSeries)
    .set(tombstoneValues(input))
    .where(
      and(
        eq(schema.monitoringSeries.userId, input.userId),
        eq(schema.monitoringSeries.source, input.source),
        eq(schema.monitoringSeries.provenance, "integration"),
        eq(schema.monitoringSeries.seriesType, "location"),
        isNull(schema.monitoringSeries.deletedAt)
      )
    )
    .returning({ id: schema.monitoringSeries.id });

  return {
    externalActivityIds: [],
    metricReadingIds: [],
    monitoringSeriesIds: monitoringSeriesRows.map((row) => row.id),
    materializedSetIds: [],
    activityLinkIds: []
  };
}

function tombstoneValues(input: { deviceId: string; serverClock: Date }) {
  return {
    deviceId: input.deviceId,
    updatedAt: input.serverClock,
    deletedAt: input.serverClock,
    receivedAt: input.serverClock
  };
}

function purgeBeforeImage(
  input: {
    batchId: string;
    source: ImportedDataPurgeSource;
    scope: ImportedDataPurgeScope;
  },
  ids: PurgedIds
) {
  return {
    batchId: input.batchId,
    source: input.source,
    scope: input.scope,
    liveIds: ids
  };
}

function purgeAfterImage(
  input: {
    batchId: string;
    source: ImportedDataPurgeSource;
    scope: ImportedDataPurgeScope;
  },
  ids: PurgedIds,
  tombstonedCounts: ImportedDataPurgeCounts,
  deletedAt: Date
) {
  return {
    batchId: input.batchId,
    source: input.source,
    scope: input.scope,
    deletedAt: deletedAt.toISOString(),
    tombstonedCounts,
    tombstonedIds: ids
  };
}

function countsFromIds(ids: PurgedIds): ImportedDataPurgeCounts {
  return {
    externalActivities: ids.externalActivityIds.length,
    metricReadings: ids.metricReadingIds.length,
    monitoringSeries: ids.monitoringSeriesIds.length,
    materializedSets: ids.materializedSetIds.length,
    activityLinks: ids.activityLinkIds.length
  };
}

function countsFromAfterImage(
  afterImage: Record<string, unknown> | null
): ImportedDataPurgeCounts {
  if (
    afterImage !== null &&
    typeof afterImage.tombstonedCounts === "object" &&
    afterImage.tombstonedCounts !== null
  ) {
    return ImportedDataPurgeCountsSchema.parse(afterImage.tombstonedCounts);
  }

  return {
    externalActivities: 0,
    metricReadings: 0,
    monitoringSeries: 0,
    materializedSets: 0,
    activityLinks: 0
  };
}

function appliedRowsFromIds(ids: PurgedIds): ImportedDataPurgeAppliedRow[] {
  return [
    ...ids.externalActivityIds.map((entityId) => ({
      entityTable: "external_activities",
      entityId
    })),
    ...ids.metricReadingIds.map((entityId) => ({
      entityTable: "metric_readings",
      entityId
    })),
    ...ids.monitoringSeriesIds.map((entityId) => ({
      entityTable: "monitoring_series",
      entityId
    })),
    ...ids.materializedSetIds.map((entityId) => ({
      entityTable: "logged_sets",
      entityId
    })),
    ...ids.activityLinkIds.map((entityId) => ({
      entityTable: "activity_links",
      entityId
    }))
  ];
}

function stableActivityLogId(batchId: string) {
  return `app:imported-data-purge:${createHash("sha256")
    .update(batchId)
    .digest("hex")
    .slice(0, 32)}`;
}
