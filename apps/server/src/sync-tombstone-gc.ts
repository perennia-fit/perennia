import { randomUUID } from "node:crypto";

import { and, eq, inArray, isNotNull, lt } from "drizzle-orm";

import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import type {
  JobData,
  JobLogger,
  JobQueue,
  JobWorkHandler
} from "./jobs/index.js";

export const SYNC_TOMBSTONE_RETENTION_DAYS = 180;
export const SYNC_TOMBSTONE_RETENTION_MS =
  SYNC_TOMBSTONE_RETENTION_DAYS * 24 * 60 * 60 * 1000;
export const SYNC_TOMBSTONE_GC_JOB_NAME = "sync.tombstones.gc";
export const SYNC_TOMBSTONE_GC_SCHEDULE_KEY = "sync-tombstones-gc-daily";
export const SYNC_TOMBSTONE_GC_SCHEDULE_CRON = "0 3 * * *";

export type CollectExpiredLoggedSetTombstonesInput = {
  now?: Date;
};

export type SyncTombstoneGcResult = {
  deletedCount: number;
  markerCount: number;
  cutoff: string;
};

export type SyncTombstoneGcStore = {
  collectExpiredLoggedSetTombstones(
    input?: CollectExpiredLoggedSetTombstonesInput
  ): Promise<SyncTombstoneGcResult>;
};

export type SyncTombstoneGcWorker = {
  start(): Promise<void>;
};

export type SyncTombstoneGcWorkerOptions = {
  jobs: JobQueue;
  tombstoneGcStore: SyncTombstoneGcStore;
  logger: JobLogger;
  clock?: () => Date;
};

type TombstoneGcJobData = JobData & {
  source?: string;
};

export function createDrizzleSyncTombstoneGcStore(
  db: ServerDatabase
): SyncTombstoneGcStore {
  return {
    async collectExpiredLoggedSetTombstones(input = {}) {
      const now = input.now ?? new Date();
      const cutoff = new Date(now.getTime() - SYNC_TOMBSTONE_RETENTION_MS);

      return db.transaction(async (transaction) => {
        const expiredRows = await transaction
          .select({
            id: schema.loggedSets.id,
            userId: schema.loggedSets.userId,
            deviceId: schema.loggedSets.deviceId,
            updatedAt: schema.loggedSets.updatedAt,
            deletedAt: schema.loggedSets.deletedAt
          })
          .from(schema.loggedSets)
          .where(
            and(
              isNotNull(schema.loggedSets.deletedAt),
              lt(schema.loggedSets.deletedAt, cutoff)
            )
          );

        if (expiredRows.length === 0) {
          return {
            deletedCount: 0,
            markerCount: 0,
            cutoff: cutoff.toISOString()
          };
        }

        const markerValues = expiredRows.map((row) => {
          if (row.deletedAt === null) {
            throw new Error("expired tombstone query returned a live row.");
          }

          return {
            id: randomUUID(),
            userId: row.userId,
            loggedSetId: row.id,
            deviceId: row.deviceId,
            tombstoneUpdatedAt: row.updatedAt,
            deletedAt: row.deletedAt,
            gcAt: now
          };
        });
        const markerRows = await transaction
          .insert(schema.loggedSetTombstoneGcMarkers)
          .values(markerValues)
          .onConflictDoNothing({
            target: [
              schema.loggedSetTombstoneGcMarkers.userId,
              schema.loggedSetTombstoneGcMarkers.loggedSetId
            ]
          })
          .returning({ id: schema.loggedSetTombstoneGcMarkers.id });

        const deletedRows = await transaction
          .delete(schema.loggedSets)
          .where(
            inArray(
              schema.loggedSets.id,
              expiredRows.map((row) => row.id)
            )
          )
          .returning({ id: schema.loggedSets.id });

        return {
          deletedCount: deletedRows.length,
          markerCount: markerRows.length,
          cutoff: cutoff.toISOString()
        };
      });
    }
  };
}

export function createSyncTombstoneGcWorker({
  jobs,
  tombstoneGcStore,
  logger,
  clock = () => new Date()
}: SyncTombstoneGcWorkerOptions): SyncTombstoneGcWorker {
  return {
    async start() {
      await jobs.ensureQueue({ name: SYNC_TOMBSTONE_GC_JOB_NAME });
      await jobs.work<TombstoneGcJobData>(
        SYNC_TOMBSTONE_GC_JOB_NAME,
        createTombstoneGcHandler({ tombstoneGcStore, logger, clock })
      );
      await jobs.schedule({
        name: SYNC_TOMBSTONE_GC_JOB_NAME,
        cron: SYNC_TOMBSTONE_GC_SCHEDULE_CRON,
        key: SYNC_TOMBSTONE_GC_SCHEDULE_KEY,
        data: { source: "sync-tombstone-gc" }
      });
      logger.info(
        {
          jobName: SYNC_TOMBSTONE_GC_JOB_NAME,
          schedule: SYNC_TOMBSTONE_GC_SCHEDULE_CRON
        },
        "sync tombstone GC worker started"
      );
    }
  };
}

function createTombstoneGcHandler({
  tombstoneGcStore,
  logger,
  clock
}: {
  tombstoneGcStore: SyncTombstoneGcStore;
  logger: JobLogger;
  clock: () => Date;
}): JobWorkHandler<TombstoneGcJobData> {
  return async (job) => {
    const result = await tombstoneGcStore.collectExpiredLoggedSetTombstones({
      now: clock()
    });

    logger.info(
      {
        jobId: job.id,
        deletedCount: result.deletedCount,
        markerCount: result.markerCount,
        cutoff: result.cutoff
      },
      "sync tombstone GC completed"
    );
  };
}
