import { asc, inArray, lt } from "drizzle-orm";

import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import type {
  JobData,
  JobLogger,
  JobQueue,
  JobWorkHandler
} from "./jobs/index.js";

export const ACTIVITY_LOG_RETENTION_DAYS = 180;
export const ACTIVITY_LOG_RETENTION_MS =
  ACTIVITY_LOG_RETENTION_DAYS * 24 * 60 * 60 * 1000;
export const ACTIVITY_LOG_RETENTION_JOB_NAME = "activity-log.retention.prune";
export const ACTIVITY_LOG_RETENTION_SCHEDULE_KEY =
  "activity-log-retention-daily";
export const ACTIVITY_LOG_RETENTION_SCHEDULE_CRON = "30 3 * * *";
export const ACTIVITY_LOG_RETENTION_DEFAULT_BATCH_SIZE = 500;

export type ActivityLogRetentionInput = {
  now?: Date;
};

export type ActivityLogRetentionResult = {
  prunedCount: number;
  cutoff: string;
  batchSize: number;
};

export type ActivityLogRetentionStore = {
  pruneExpiredActivityLogEntries(
    input?: ActivityLogRetentionInput
  ): Promise<ActivityLogRetentionResult>;
};

export type ActivityLogRetentionWorker = {
  start(): Promise<void>;
};

export type ActivityLogRetentionWorkerOptions = {
  jobs: JobQueue;
  activityLogRetentionStore: ActivityLogRetentionStore;
  logger: JobLogger;
  clock?: () => Date;
};

type ActivityLogRetentionJobData = JobData & {
  source?: string;
};

export function createDrizzleActivityLogRetentionStore(
  db: ServerDatabase,
  options: { batchSize?: number } = {}
): ActivityLogRetentionStore {
  const batchSize =
    options.batchSize ?? ACTIVITY_LOG_RETENTION_DEFAULT_BATCH_SIZE;

  if (!Number.isInteger(batchSize) || batchSize < 1) {
    throw new Error("Activity Log retention batchSize must be a positive integer.");
  }

  return {
    async pruneExpiredActivityLogEntries(input = {}) {
      const now = input.now ?? new Date();
      const cutoff = new Date(now.getTime() - ACTIVITY_LOG_RETENTION_MS);
      let prunedCount = 0;

      while (true) {
        const prunedBatchCount = await db.transaction(async (transaction) => {
          const expiredRows = await transaction
            .select({ id: schema.activityLog.id })
            .from(schema.activityLog)
            .where(lt(schema.activityLog.occurredAt, cutoff))
            .orderBy(asc(schema.activityLog.occurredAt), asc(schema.activityLog.id))
            .limit(batchSize);

          if (expiredRows.length === 0) {
            return 0;
          }

          const deletedRows = await transaction
            .delete(schema.activityLog)
            .where(
              inArray(
                schema.activityLog.id,
                expiredRows.map((row) => row.id)
              )
            )
            .returning({ id: schema.activityLog.id });

          return deletedRows.length;
        });

        prunedCount += prunedBatchCount;

        if (prunedBatchCount < batchSize) {
          break;
        }
      }

      return {
        prunedCount,
        cutoff: cutoff.toISOString(),
        batchSize
      };
    }
  };
}

export function createActivityLogRetentionWorker({
  jobs,
  activityLogRetentionStore,
  logger,
  clock = () => new Date()
}: ActivityLogRetentionWorkerOptions): ActivityLogRetentionWorker {
  return {
    async start() {
      await jobs.ensureQueue({ name: ACTIVITY_LOG_RETENTION_JOB_NAME });
      await jobs.work<ActivityLogRetentionJobData>(
        ACTIVITY_LOG_RETENTION_JOB_NAME,
        createActivityLogRetentionHandler({
          activityLogRetentionStore,
          logger,
          clock
        })
      );
      await jobs.schedule({
        name: ACTIVITY_LOG_RETENTION_JOB_NAME,
        cron: ACTIVITY_LOG_RETENTION_SCHEDULE_CRON,
        key: ACTIVITY_LOG_RETENTION_SCHEDULE_KEY,
        data: { source: "activity-log-retention" }
      });
      logger.info(
        {
          jobName: ACTIVITY_LOG_RETENTION_JOB_NAME,
          schedule: ACTIVITY_LOG_RETENTION_SCHEDULE_CRON
        },
        "activity log retention worker started"
      );
    }
  };
}

function createActivityLogRetentionHandler({
  activityLogRetentionStore,
  logger,
  clock
}: {
  activityLogRetentionStore: ActivityLogRetentionStore;
  logger: JobLogger;
  clock: () => Date;
}): JobWorkHandler<ActivityLogRetentionJobData> {
  return async (job) => {
    const result =
      await activityLogRetentionStore.pruneExpiredActivityLogEntries({
        now: clock()
      });

    logger.info(
      {
        jobId: job.id,
        prunedCount: result.prunedCount,
        cutoff: result.cutoff,
        batchSize: result.batchSize
      },
      "activity log retention prune completed"
    );
  };
}
