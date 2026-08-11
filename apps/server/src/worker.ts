import pino from "pino";
import { pathToFileURL } from "node:url";

import {
  createAccountDeletionPurgeWorker,
  createDrizzleAccountDeletionPurgeStore,
  type AccountDeletionPurgeWorker
} from "./account-deletion-purge.js";
import { createDrizzleCanonicalImportStore } from "./canonical-import-endpoint.js";
import {
  createActivityLogRetentionWorker,
  createDrizzleActivityLogRetentionStore,
  type ActivityLogRetentionWorker
} from "./activity-log-retention.js";
import {
  applyMigrations,
  createDatabaseClient,
  type DatabaseClient
} from "./db/index.js";
import { createDrizzleDevicePushTokenStore } from "./device-push-tokens.js";
import { createGarminOAuthRuntimeFromEnv } from "./garmin-oauth.js";
import {
  createGarminBackfillConfigFromEnv,
  createDrizzleGarminConnectorConsentStore,
  createGarminOfficialApiClientFromEnv,
  createGarminWebhookWorker,
  type GarminWebhookWorker
} from "./garmin-webhook.js";
import { createDrizzleIntegrationStatusStore } from "./integration-status.js";
import {
  createDrizzleJobHeartbeatStore,
  createJobSpine,
  createPgBossJobQueue,
  type JobSpine
} from "./jobs/index.js";
import {
  createJobQueueSyncNudgePublisher,
  createPushSenderFromEnv,
  createSyncNudgeWorker,
  type SyncNudgeWorker
} from "./sync-nudge.js";
import {
  createDrizzleSyncTombstoneGcStore,
  createSyncTombstoneGcWorker,
  type SyncTombstoneGcWorker
} from "./sync-tombstone-gc.js";
import {
  createPrivacyLogger,
  createSentryCrashReporterFromEnv
} from "./observability.js";

export type StartedWorker = {
  database: DatabaseClient;
  spine: JobSpine;
  accountDeletionPurgeWorker: AccountDeletionPurgeWorker;
  activityLogRetentionWorker: ActivityLogRetentionWorker;
  garminWebhookWorker: GarminWebhookWorker | null;
  syncNudgeWorker: SyncNudgeWorker;
  tombstoneGcWorker: SyncTombstoneGcWorker;
  close(): Promise<void>;
};

export async function startWorker(): Promise<StartedWorker> {
  const logger = createPrivacyLogger(pino());
  const databaseUrl = readRequiredEnv("DATABASE_URL");

  await applyMigrations(databaseUrl);
  const database = createDatabaseClient(databaseUrl);
  const jobs = createPgBossJobQueue({ databaseUrl, logger });
  const garminOAuthRuntime = createGarminOAuthRuntimeFromEnv({
    db: database.db
  });
  const garminOfficialClient = createGarminOfficialApiClientFromEnv();
  const garminBackfillConfig = createGarminBackfillConfigFromEnv(process.env);
  const spine = createJobSpine({
    jobs,
    heartbeatStore: createDrizzleJobHeartbeatStore(database.db),
    logger
  });
  const syncNudgeWorker = createSyncNudgeWorker({
    jobs,
    devicePushTokenStore: createDrizzleDevicePushTokenStore(database.db),
    pushSender: createPushSenderFromEnv(process.env, logger),
    logger
  });
  const garminWebhookWorker =
    garminOAuthRuntime === null || garminOfficialClient === null
      ? null
      : createGarminWebhookWorker({
          jobs,
          canonicalImportStore: createDrizzleCanonicalImportStore(database.db),
          garminOAuthClient: garminOAuthRuntime.client,
          garminOAuthStore: garminOAuthRuntime.store,
          garminConsentStore: createDrizzleGarminConnectorConsentStore(
            database.db
          ),
          garminOfficialClient,
          integrationStatusStore: createDrizzleIntegrationStatusStore(
            database.db
          ),
          logger,
          backfillConfig: garminBackfillConfig,
          syncNudgePublisher: createJobQueueSyncNudgePublisher(jobs)
        });
  const activityLogRetentionWorker = createActivityLogRetentionWorker({
    jobs,
    activityLogRetentionStore: createDrizzleActivityLogRetentionStore(
      database.db
    ),
    logger
  });
  const accountDeletionPurgeWorker = createAccountDeletionPurgeWorker({
    jobs,
    accountDeletionPurgeStore: createDrizzleAccountDeletionPurgeStore(
      database.db
    ),
    logger
  });
  const tombstoneGcWorker = createSyncTombstoneGcWorker({
    jobs,
    tombstoneGcStore: createDrizzleSyncTombstoneGcStore(database.db),
    logger
  });

  let spineStarted = false;
  try {
    await spine.start();
    spineStarted = true;
    await syncNudgeWorker.start();
    await garminWebhookWorker?.start();
    await tombstoneGcWorker.start();
    await activityLogRetentionWorker.start();
    await accountDeletionPurgeWorker.start();
  } catch (error) {
    if (spineStarted) {
      await spine.stop();
    }
    await database.close();
    throw error;
  }

  const close = async () => {
    await spine.stop();
    await database.close();
  };

  process.once("SIGINT", () => {
    void close().finally(() => process.exit(0));
  });
  process.once("SIGTERM", () => {
    void close().finally(() => process.exit(0));
  });

  logger.info({}, "worker listening for jobs");

  return {
    database,
    spine,
    accountDeletionPurgeWorker,
    activityLogRetentionWorker,
    garminWebhookWorker,
    syncNudgeWorker,
    tombstoneGcWorker,
    close
  };
}

function readRequiredEnv(name: string) {
  const value = process.env[name];
  if (value === undefined || value.length === 0) {
    throw new Error(`${name} is required.`);
  }

  return value;
}

const isMainModule =
  process.argv[1] !== undefined &&
  import.meta.url === pathToFileURL(process.argv[1]).href;

if (isMainModule) {
  startWorker().catch((error) => {
    const startupLogger = createPrivacyLogger(pino());
    const startupCrashReporter = createSentryCrashReporterFromEnv(process.env, {
      release: process.env.npm_package_version ?? "0.0.0"
    });
    startupCrashReporter?.captureException(error, {
      correlationId: "worker-startup",
      method: "STARTUP",
      path: "worker-startup"
    });
    startupLogger.fatal?.({ error }, "worker failed to start");
    process.exit(1);
  });
}
