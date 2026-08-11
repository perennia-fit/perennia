import { and, asc, inArray, isNotNull, lt } from "drizzle-orm";

import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import type {
  JobData,
  JobLogger,
  JobQueue,
  JobWorkHandler
} from "./jobs/index.js";

export const ACCOUNT_DELETION_GRACE_DAYS = 30;
export const ACCOUNT_DELETION_GRACE_MS =
  ACCOUNT_DELETION_GRACE_DAYS * 24 * 60 * 60 * 1000;
export const ACCOUNT_DELETION_PURGE_JOB_NAME = "account-deletion.purge";
export const ACCOUNT_DELETION_PURGE_SCHEDULE_KEY =
  "account-deletion-purge-daily";
export const ACCOUNT_DELETION_PURGE_SCHEDULE_CRON = "0 4 * * *";
export const ACCOUNT_DELETION_PURGE_DEFAULT_BATCH_SIZE = 100;

export type AccountDeletionPurgeInput = {
  now?: Date;
};

export type AccountDeletionPurgeResult = {
  purgedCount: number;
  purgedUserIds: string[];
  cutoff: string;
  batchSize: number;
};

export type AccountDeletionPurgeStore = {
  purgeExpiredDeletedAccounts(
    input?: AccountDeletionPurgeInput
  ): Promise<AccountDeletionPurgeResult>;
};

export type AccountDeletionPurgeWorker = {
  start(): Promise<void>;
};

export type AccountDeletionPurgeWorkerOptions = {
  jobs: JobQueue;
  accountDeletionPurgeStore: AccountDeletionPurgeStore;
  logger: JobLogger;
  clock?: () => Date;
};

type AccountDeletionPurgeJobData = JobData & {
  source?: string;
};

export function createDrizzleAccountDeletionPurgeStore(
  db: ServerDatabase,
  options: { batchSize?: number } = {}
): AccountDeletionPurgeStore {
  const batchSize =
    options.batchSize ?? ACCOUNT_DELETION_PURGE_DEFAULT_BATCH_SIZE;

  if (!Number.isInteger(batchSize) || batchSize < 1) {
    throw new Error(
      "Account deletion purge batchSize must be a positive integer."
    );
  }

  return {
    async purgeExpiredDeletedAccounts(input = {}) {
      const now = input.now ?? new Date();
      const cutoff = new Date(now.getTime() - ACCOUNT_DELETION_GRACE_MS);
      const purgedUserIds: string[] = [];

      while (true) {
        const purgedBatchUserIds = await db.transaction(async (transaction) => {
          const expiredUsers = await transaction
            .select({ id: schema.user.id })
            .from(schema.user)
            .where(
              and(
                isNotNull(schema.user.deletionRequestedAt),
                lt(schema.user.deletionRequestedAt, cutoff)
              )
            )
            .orderBy(
              asc(schema.user.deletionRequestedAt),
              asc(schema.user.id)
            )
            .limit(batchSize);

          if (expiredUsers.length === 0) {
            return [];
          }

          const deletedUsers = await transaction
            .delete(schema.user)
            .where(
              inArray(
                schema.user.id,
                expiredUsers.map((user) => user.id)
              )
            )
            .returning({ id: schema.user.id });

          return deletedUsers.map((user) => user.id);
        });

        purgedUserIds.push(...purgedBatchUserIds);

        if (purgedBatchUserIds.length < batchSize) {
          break;
        }
      }

      return {
        purgedCount: purgedUserIds.length,
        purgedUserIds,
        cutoff: cutoff.toISOString(),
        batchSize
      };
    }
  };
}

export function createAccountDeletionPurgeWorker({
  jobs,
  accountDeletionPurgeStore,
  logger,
  clock = () => new Date()
}: AccountDeletionPurgeWorkerOptions): AccountDeletionPurgeWorker {
  return {
    async start() {
      await jobs.ensureQueue({ name: ACCOUNT_DELETION_PURGE_JOB_NAME });
      await jobs.work<AccountDeletionPurgeJobData>(
        ACCOUNT_DELETION_PURGE_JOB_NAME,
        createAccountDeletionPurgeHandler({
          accountDeletionPurgeStore,
          logger,
          clock
        })
      );
      await jobs.schedule({
        name: ACCOUNT_DELETION_PURGE_JOB_NAME,
        cron: ACCOUNT_DELETION_PURGE_SCHEDULE_CRON,
        key: ACCOUNT_DELETION_PURGE_SCHEDULE_KEY,
        data: { source: "account-deletion-purge" }
      });
      logger.info(
        {
          jobName: ACCOUNT_DELETION_PURGE_JOB_NAME,
          schedule: ACCOUNT_DELETION_PURGE_SCHEDULE_CRON
        },
        "account deletion purge worker started"
      );
    }
  };
}

function createAccountDeletionPurgeHandler({
  accountDeletionPurgeStore,
  logger,
  clock
}: {
  accountDeletionPurgeStore: AccountDeletionPurgeStore;
  logger: JobLogger;
  clock: () => Date;
}): JobWorkHandler<AccountDeletionPurgeJobData> {
  return async (job) => {
    const result = await accountDeletionPurgeStore.purgeExpiredDeletedAccounts({
      now: clock()
    });

    logger.info(
      {
        jobId: job.id,
        purgedCount: result.purgedCount,
        purgedUserIds: result.purgedUserIds,
        cutoff: result.cutoff,
        batchSize: result.batchSize
      },
      "account deletion purge completed"
    );
  };
}
