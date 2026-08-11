import { createHash, timingSafeEqual } from "node:crypto";
import { createRoute, z } from "@hono/zod-openapi";
import { and, eq, isNull } from "drizzle-orm";

import { GARMIN_OFFICIAL_ACQUISITION_ADAPTER } from "./acquisition-adapters.js";
import {
  CanonicalImportConsentDataClassSchema,
  type CanonicalImportConsentDataClass
} from "./canonical-import.js";
import {
  CANONICAL_IMPORT_ACTIVITY_LOG_ACTOR,
  CANONICAL_IMPORT_BATCHES_ENTITY,
  CanonicalImportRequestSchema,
  type CanonicalImportStore,
  type CanonicalImportStoreResult
} from "./canonical-import-endpoint.js";
import {
  GARMIN_OAUTH_CREDENTIAL_NAME,
  GARMIN_OAUTH_SOURCE,
  GarminOAuthGrantExpiredError
} from "./garmin-oauth.js";
import type {
  GarminOAuthClient,
  GarminOAuthConnectorConnection,
  GarminOAuthConnectionStore
} from "./garmin-oauth.js";
import {
  parseGarminFitActivityFile,
  type GarminFitCanonicalImport
} from "./garmin-fit-import.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import type { IntegrationStatusStore } from "./integration-status.js";
import type {
  JobData,
  JobEnvelope,
  JobLogger,
  JobQueue
} from "./jobs/index.js";
import type { SyncNudgePublisher } from "./sync-nudge.js";

export const GARMIN_WEBHOOK_ROUTE_PATH = "/integrations/garmin/webhook";
export const GARMIN_CONSENT_DATA_CLASSES_ROUTE_PATH =
  "/integrations/garmin/consent-data-classes";
export const GARMIN_WEBHOOK_JOB_NAME = "integrations.garmin.webhook.ingest";
export const GARMIN_WEBHOOK_SECRET_HEADER = "x-garmin-webhook-secret";
export const GARMIN_WEBHOOK_RETRY_LIMIT = 3;
export const GARMIN_WEBHOOK_SINGLETON_SECONDS = 30 * 24 * 60 * 60;
export const GARMIN_WEBHOOK_DEFAULT_TIMEZONE = "UTC";
export const GARMIN_BACKFILL_JOB_NAME = "integrations.garmin.backfill";
export const GARMIN_RECONCILIATION_DISPATCH_JOB_NAME =
  "integrations.garmin.reconciliation.dispatch";
export const GARMIN_RECONCILIATION_JOB_NAME =
  "integrations.garmin.reconciliation";
export const GARMIN_RECONCILIATION_SCHEDULE_KEY =
  "integrations.garmin.reconciliation";
export const GARMIN_RECONCILIATION_SCHEDULE_CRON = "*/30 * * * *";
export const GARMIN_BACKFILL_FULL_HISTORY_START =
  "1970-01-01T00:00:00.000Z";
export const GARMIN_BACKFILL_DEFAULT_CHUNK_DAYS = 365;
export const GARMIN_BACKFILL_SINGLETON_SECONDS =
  GARMIN_WEBHOOK_SINGLETON_SECONDS;
export const GARMIN_RECONCILIATION_LOOKBACK_SECONDS = 25 * 60 * 60;
export const GARMIN_PREMIUM_DATA_CLASSES = [
  "sleepWellness",
  "bodyComposition"
] as const satisfies readonly CanonicalImportConsentDataClass[];
export const GARMIN_HOSTED_DATA_CLASSES =
  GARMIN_OFFICIAL_ACQUISITION_ADAPTER.consentDataClasses;

export const GarminWebhookPingSchema = z
  .object({
    providerUserId: z.string().trim().min(1).openapi({
      description:
        "Garmin-side account identifier from the webhook ping; used to find the server-custodied OAuth connection."
    }),
    eventId: z.string().trim().min(1).optional().openapi({
      description:
        "Garmin webhook event id. When present it becomes part of the idempotent batch key."
    }),
    activityIds: z.array(z.string().trim().min(1)).default([]).openapi({
      description:
        "Garmin activity ids referenced by the ping. The worker fetches each id server-side."
    })
  })
  .strict()
  .openapi("GarminWebhookPing");

export const GarminWebhookAcceptedResponseSchema = z
  .object({
    accepted: z.literal(true),
    idempotencyKey: z.string().min(1),
    jobId: z.string().min(1).nullable()
  })
  .strict()
  .openapi("GarminWebhookAcceptedResponse");

export const GarminWebhookUnauthorizedResponseSchema = z
  .object({
    code: z.literal("garmin_webhook_unauthorized"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("GarminWebhookUnauthorizedResponse");

export const GarminWebhookUnavailableResponseSchema = z
  .object({
    code: z.literal("garmin_webhook_unavailable"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("GarminWebhookUnavailableResponse");

export const GarminConsentDataClassAccessSchema = z
  .object({
    dataClass: CanonicalImportConsentDataClassSchema,
    enabled: z.boolean(),
    locked: z.boolean(),
    lockReason: z.literal("paid_tier_required").nullable()
  })
  .strict()
  .openapi("GarminConsentDataClassAccess");

export const GarminConsentDataClassesResponseSchema = z
  .object({
    connectionId: z.string().min(1).nullable(),
    dataClasses: z.array(GarminConsentDataClassAccessSchema)
  })
  .strict()
  .openapi("GarminConsentDataClassesResponse");

export const GarminConsentUnauthorizedResponseSchema = z
  .object({
    code: z.literal("garmin_consent_unauthorized"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("GarminConsentUnauthorizedResponse");

export const GarminConsentUnavailableResponseSchema = z
  .object({
    code: z.literal("garmin_consent_unavailable"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("GarminConsentUnavailableResponse");

export const garminWebhookRoute = createRoute({
  method: "post",
  path: GARMIN_WEBHOOK_ROUTE_PATH,
  operationId: "receiveGarminWebhook",
  tags: ["Integrations"],
  summary: "Receive an official Garmin webhook ping.",
  description:
    "Acknowledges Garmin's official connector ping quickly and defers token minting, provider fetch, and canonical ingestion to a pg-boss job.",
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: GarminWebhookPingSchema
        }
      }
    }
  },
  responses: {
    202: {
      description: "The Garmin webhook ping was accepted for background import.",
      content: {
        "application/json": {
          schema: GarminWebhookAcceptedResponseSchema
        }
      }
    },
    401: {
      description: "The webhook shared secret is missing or invalid.",
      content: {
        "application/json": {
          schema: GarminWebhookUnauthorizedResponseSchema
        }
      }
    },
    503: {
      description: "Garmin webhook configuration or job queue is unavailable.",
      content: {
        "application/json": {
          schema: GarminWebhookUnavailableResponseSchema
        }
      }
    }
  }
});

export const garminConsentDataClassesRoute = createRoute({
  method: "get",
  path: GARMIN_CONSENT_DATA_CLASSES_ROUTE_PATH,
  operationId: "listGarminConsentDataClasses",
  tags: ["Integrations"],
  summary: "List Garmin hosted connector data-class consent access.",
  description:
    "Lists every hosted Garmin import data class, including premium classes that are offered but locked until the account has an active paid tier.",
  security: [{ bearerAuth: [] }],
  responses: {
    200: {
      description: "The Garmin consent surface for the signed-in account.",
      content: {
        "application/json": {
          schema: GarminConsentDataClassesResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid session bearer token.",
      content: {
        "application/json": {
          schema: GarminConsentUnauthorizedResponseSchema
        }
      }
    },
    503: {
      description: "Garmin consent storage or sync auth is unavailable.",
      content: {
        "application/json": {
          schema: GarminConsentUnavailableResponseSchema
        }
      }
    }
  }
});

export type GarminWebhookPing = z.infer<typeof GarminWebhookPingSchema>;
export type GarminWebhookAcceptedResponse = z.infer<
  typeof GarminWebhookAcceptedResponseSchema
>;
export type GarminConsentDataClassesResponse = z.infer<
  typeof GarminConsentDataClassesResponseSchema
>;

export type GarminWebhookConfig = {
  sharedSecret: string;
};

export type GarminBackfillConfig = {
  chunkDays?: number;
  historyStart?: string | null;
  historyEnd?: string | null;
  reconciliationCron?: string;
  reconciliationLookbackSeconds?: number;
};

export type GarminConnectorConsentStore = {
  listEnabledDataClasses(input: {
    credentialId: string;
    userId: string;
  }): Promise<CanonicalImportConsentDataClass[]>;
};

export type GarminEntitlementStore = {
  hasActivePaidTier(userId: string): Promise<boolean>;
};

export type GarminConnectorConsentDataClassAccess = {
  dataClass: CanonicalImportConsentDataClass;
  enabled: boolean;
  locked: boolean;
  lockReason: "paid_tier_required" | null;
};

export type GarminWebhookJobData = JobData & {
  providerUserId?: string;
  eventId?: string;
  activityIds?: unknown;
  idempotencyKey?: string;
};

export type GarminImportWindowJobData = JobData & {
  connectionId?: string;
  providerUserId?: string | null;
  userId?: string;
  windowStart?: string;
  windowEnd?: string;
  idempotencyKey?: string;
};

export type GarminBackfillJobData = GarminImportWindowJobData;
export type GarminReconciliationJobData = GarminImportWindowJobData;

export type GarminReconciliationDispatchJobData = JobData & {
  source?: string;
};

export type GarminOfficialActivityPayload =
  | {
      kind: "fit";
      fitFileBase64: string;
      timezone?: string;
    }
  | {
      kind: "canonical";
      activities?: GarminFitCanonicalImport["activities"];
      metricReadings?: GarminFitCanonicalImport["metricReadings"];
      series?: GarminFitCanonicalImport["series"];
    };

export type GarminOfficialActivityClient = {
  listActivityIds(input: {
    accessToken: string;
    dataClasses: CanonicalImportConsentDataClass[];
    providerUserId: string | null;
    windowStart: string;
    windowEnd: string;
  }): Promise<{ activityIds: string[] }>;
  fetchActivityPayloads(input: {
    accessToken: string;
    activityIds: string[];
    dataClasses: CanonicalImportConsentDataClass[];
    providerUserId: string | null;
  }): Promise<GarminOfficialActivityPayload[]>;
};

export type GarminWebhookJobHandler = (
  job: JobEnvelope<GarminWebhookJobData>
) => Promise<CanonicalImportStoreResult | null>;

export type GarminConnectorImportJobHandler = (
  job: JobEnvelope<GarminImportWindowJobData>
) => Promise<CanonicalImportStoreResult | null>;

export type GarminWebhookWorker = {
  start(): Promise<void>;
};

export type GarminWebhookJobHandlerOptions = {
  canonicalImportStore: CanonicalImportStore;
  garminOAuthClient: GarminOAuthClient;
  garminOAuthStore: GarminOAuthConnectionStore;
  garminConsentStore?: GarminConnectorConsentStore;
  garminEntitlementStore?: GarminEntitlementStore;
  garminOfficialClient: GarminOfficialActivityClient;
  integrationStatusStore?: IntegrationStatusStore;
  jobs?: JobQueue;
  logger: JobLogger;
  syncNudgePublisher?: SyncNudgePublisher;
  backfillConfig?: GarminBackfillConfig;
  defaultTimezone?: string;
};

export class GarminRateLimitError extends Error {
  readonly retryAfterSeconds: number;

  constructor({ retryAfterSeconds }: { retryAfterSeconds: number }) {
    super("Garmin provider rate limit exceeded.");
    this.name = "GarminRateLimitError";
    this.retryAfterSeconds = retryAfterSeconds;
  }
}

export function createDrizzleGarminConnectorConsentStore(
  db: ServerDatabase
): GarminConnectorConsentStore {
  return {
    async listEnabledDataClasses({ credentialId, userId }) {
      const rows = await db
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

      return rows
        .map((row) => CanonicalImportConsentDataClassSchema.safeParse(row.dataClass))
        .filter((parsed) => parsed.success)
        .map((parsed) => parsed.data);
    }
  };
}

export async function listGarminConnectorConsentDataClassAccess({
  credentialId,
  consentStore,
  entitlementStore,
  userId
}: {
  credentialId: string;
  consentStore?: GarminConnectorConsentStore;
  entitlementStore?: GarminEntitlementStore;
  userId: string;
}): Promise<GarminConnectorConsentDataClassAccess[]> {
  const enabledDataClasses = new Set(
    await readGarminEnabledConsentDataClasses({
      consentStore,
      credentialId,
      userId
    })
  );
  const hasPaidTier =
    entitlementStore === undefined
      ? false
      : await entitlementStore.hasActivePaidTier(userId);

  return GARMIN_HOSTED_DATA_CLASSES.map((dataClass) => {
    const locked =
      isGarminPremiumDataClass(dataClass) && hasPaidTier === false;
    return {
      dataClass,
      enabled: locked ? false : enabledDataClasses.has(dataClass),
      locked,
      lockReason: locked ? "paid_tier_required" : null
    };
  });
}

export function verifyGarminWebhookSecret({
  config,
  providedSecret
}: {
  config: GarminWebhookConfig;
  providedSecret: string | undefined;
}) {
  if (providedSecret === undefined) {
    return false;
  }
  const expected = Buffer.from(config.sharedSecret, "utf8");
  const provided = Buffer.from(providedSecret, "utf8");
  return (
    expected.byteLength === provided.byteLength &&
    timingSafeEqual(expected, provided)
  );
}

export async function enqueueGarminWebhookPing({
  jobs,
  ping
}: {
  jobs: JobQueue;
  ping: GarminWebhookPing;
}) {
  const idempotencyKey = garminWebhookIdempotencyKey(ping);
  const jobId = await jobs.send({
    name: GARMIN_WEBHOOK_JOB_NAME,
    data: {
      providerUserId: ping.providerUserId,
      eventId: ping.eventId,
      activityIds: ping.activityIds,
      idempotencyKey
    },
    options: {
      singletonKey: idempotencyKey,
      singletonSeconds: GARMIN_WEBHOOK_SINGLETON_SECONDS,
      retryLimit: GARMIN_WEBHOOK_RETRY_LIMIT
    }
  });

  return { idempotencyKey, jobId };
}

export function garminWebhookIdempotencyKey(ping: GarminWebhookPing) {
  const providerDigest = digestText(ping.providerUserId).slice(0, 16);
  const eventKey =
    ping.eventId ??
    digestText(
      JSON.stringify({
        providerUserId: ping.providerUserId,
        activityIds: ping.activityIds
      })
    );
  return `garmin-webhook:${providerDigest}:${safeKeySegment(eventKey)}`;
}

export async function enqueueGarminBackfill({
  config,
  connection,
  jobs,
  now = new Date()
}: {
  config?: GarminBackfillConfig;
  connection: GarminOAuthConnectorConnection;
  jobs: JobQueue;
  now?: Date;
}) {
  const chunks = createGarminBackfillChunks({ config, connection, now });
  const jobIds = [];

  for (const chunk of chunks) {
    jobIds.push(
      await jobs.send({
        name: GARMIN_BACKFILL_JOB_NAME,
        data: chunk,
        options: {
          singletonKey: chunk.idempotencyKey,
          singletonSeconds: GARMIN_BACKFILL_SINGLETON_SECONDS,
          retryLimit: GARMIN_WEBHOOK_RETRY_LIMIT
        }
      })
    );
  }

  return { chunks, jobIds };
}

export function createGarminBackfillChunks({
  config,
  connection,
  now = new Date()
}: {
  config?: GarminBackfillConfig;
  connection: GarminOAuthConnectorConnection;
  now?: Date;
}): Array<Required<GarminImportWindowJobData>> {
  const chunkDays = normalizeChunkDays(config?.chunkDays);
  const historyStart = parseInstant(
    config?.historyStart ?? GARMIN_BACKFILL_FULL_HISTORY_START
  );
  const historyEnd = parseInstant(config?.historyEnd ?? now.toISOString());
  const chunks: Array<Required<GarminImportWindowJobData>> = [];

  for (
    let cursor = historyStart;
    cursor < historyEnd;
    cursor = addDaysUtc(cursor, chunkDays)
  ) {
    const windowEnd = minDate(addDaysUtc(cursor, chunkDays), historyEnd);
    const windowStartText = cursor.toISOString();
    const windowEndText = windowEnd.toISOString();
    const idempotencyKey = garminWindowIdempotencyKey({
      connectionId: connection.id,
      prefix: "garmin-backfill",
      windowEnd: windowEndText,
      windowStart: windowStartText
    });
    chunks.push({
      connectionId: connection.id,
      idempotencyKey,
      providerUserId: connection.providerUserId,
      userId: connection.userId,
      windowStart: windowStartText,
      windowEnd: windowEndText
    });
  }

  return chunks;
}

export async function enqueueGarminReconciliation({
  connection,
  jobs,
  windowEnd,
  windowStart
}: {
  connection: GarminOAuthConnectorConnection;
  jobs: JobQueue;
  windowEnd: Date;
  windowStart: Date;
}) {
  const windowStartText = windowStart.toISOString();
  const windowEndText = windowEnd.toISOString();
  const idempotencyKey = garminWindowIdempotencyKey({
    connectionId: connection.id,
    prefix: "garmin-reconciliation",
    windowEnd: windowEndText,
    windowStart: windowStartText
  });
  const data: Required<GarminImportWindowJobData> = {
    connectionId: connection.id,
    idempotencyKey,
    providerUserId: connection.providerUserId,
    userId: connection.userId,
    windowStart: windowStartText,
    windowEnd: windowEndText
  };
  const jobId = await jobs.send({
    name: GARMIN_RECONCILIATION_JOB_NAME,
    data,
    options: {
      singletonKey: idempotencyKey,
      singletonSeconds: GARMIN_BACKFILL_SINGLETON_SECONDS,
      retryLimit: GARMIN_WEBHOOK_RETRY_LIMIT
    }
  });

  return { data, jobId };
}

export function mapGarminOfficialActivityPayloadsToCanonicalImport(
  payloads: GarminOfficialActivityPayload[],
  {
    defaultTimezone = GARMIN_WEBHOOK_DEFAULT_TIMEZONE
  }: { defaultTimezone?: string } = {}
): GarminFitCanonicalImport {
  const canonical: GarminFitCanonicalImport = {
    activities: [],
    metricReadings: [],
    series: []
  };

  for (const payload of payloads) {
    const mapped =
      payload.kind === "fit"
        ? parseGarminFitActivityFile(
            Buffer.from(payload.fitFileBase64, "base64"),
            {
              source: "garmin",
              timezone: payload.timezone ?? defaultTimezone
            }
          )
        : {
            activities: payload.activities ?? [],
            metricReadings: payload.metricReadings ?? [],
            series: payload.series ?? []
          };
    canonical.activities.push(...mapped.activities);
    canonical.metricReadings.push(...mapped.metricReadings);
    canonical.series.push(...mapped.series);
  }

  return canonical;
}

export function createGarminWebhookJobHandler({
  canonicalImportStore,
  defaultTimezone = GARMIN_WEBHOOK_DEFAULT_TIMEZONE,
  garminConsentStore,
  garminEntitlementStore,
  garminOAuthClient,
  garminOAuthStore,
  garminOfficialClient,
  integrationStatusStore,
  logger,
  syncNudgePublisher
}: GarminWebhookJobHandlerOptions): GarminWebhookJobHandler {
  return async (job) => {
    const parsed = GarminWebhookJobDataSchema.safeParse(job.data);
    if (!parsed.success) {
      logger.warn?.({ jobId: job.id }, "Garmin webhook job payload invalid");
      return null;
    }
    const jobData = parsed.data;
    const connection =
      await garminOAuthStore.findActiveConnectionByProviderUserId({
        providerUserId: jobData.providerUserId
      });
    if (connection === null) {
      logger.warn?.(
        { jobId: job.id },
        "Garmin webhook job skipped; no active connection"
      );
      return null;
    }

    const refreshToken =
      await garminOAuthStore.decryptRefreshTokenForConnectorJob({
        connectionId: connection.id,
        userId: connection.userId
      });
    if (refreshToken === null) {
      logger.warn?.(
        { jobId: job.id, connectionId: connection.id },
        "Garmin webhook job skipped; refresh token unavailable"
      );
      return null;
    }

    const accessToken = await refreshGarminAccessTokenForConnectorJob({
      connectionId: connection.id,
      garminOAuthClient,
      integrationStatusStore,
      jobId: job.id,
      logger,
      refreshToken,
      trigger: "incremental",
      userId: connection.userId
    });
    if (accessToken === null) {
      return null;
    }
    const dataClasses = await resolveGarminEffectiveDataClasses({
      credentialId: connection.id,
      consentStore: garminConsentStore,
      entitlementStore: garminEntitlementStore,
      userId: connection.userId
    });
    const payloads = await garminOfficialClient.fetchActivityPayloads({
      accessToken: accessToken.accessToken,
      activityIds: jobData.activityIds,
      dataClasses,
      providerUserId: jobData.providerUserId
    });
    const canonical = filterGarminCanonicalImportByDataClasses(
      mapGarminOfficialActivityPayloadsToCanonicalImport(payloads, {
        defaultTimezone
      }),
      dataClasses
    );
    const request = CanonicalImportRequestSchema.parse({
      idempotencyKey: jobData.idempotencyKey,
      consentedDataClasses: inferConsentEcho(canonical),
      ...canonical
    });
    const result = await canonicalImportStore.importCanonicalBatch({
      actor: CANONICAL_IMPORT_ACTIVITY_LOG_ACTOR,
      batchId: jobData.idempotencyKey,
      credentialId: connection.id,
      deviceId: garminWebhookDeviceId(connection.id),
      idempotencyKey: jobData.idempotencyKey,
      request,
      userId: connection.userId
    });

    await enqueueImportNudge({
      connectionId: connection.id,
      result,
      syncNudgePublisher,
      userId: connection.userId
    });
    logger.info(
      {
        jobId: job.id,
        batchId: jobData.idempotencyKey,
        connectionId: connection.id,
        duplicate: result.duplicate
      },
      "Garmin webhook import completed"
    );
    return result;
  };
}

export function createGarminBackfillJobHandler(
  options: GarminWebhookJobHandlerOptions
): GarminConnectorImportJobHandler {
  return createGarminImportWindowJobHandler({
    ...options,
    jobName: GARMIN_BACKFILL_JOB_NAME,
    trigger: "backfill"
  });
}

export function createGarminReconciliationJobHandler(
  options: GarminWebhookJobHandlerOptions
): GarminConnectorImportJobHandler {
  return createGarminImportWindowJobHandler({
    ...options,
    jobName: GARMIN_RECONCILIATION_JOB_NAME,
    trigger: "scheduled"
  });
}

export function createGarminReconciliationDispatchHandler({
  backfillConfig,
  garminOAuthStore,
  integrationStatusStore,
  jobs,
  logger,
  now = () => new Date()
}: {
  backfillConfig?: GarminBackfillConfig;
  garminOAuthStore: GarminOAuthConnectionStore;
  integrationStatusStore?: IntegrationStatusStore;
  jobs: JobQueue;
  logger: JobLogger;
  now?: () => Date;
}) {
  return async (job: JobEnvelope<GarminReconciliationDispatchJobData>) => {
    const windowEnd = now();
    const lookbackSeconds = normalizePositiveInteger(
      backfillConfig?.reconciliationLookbackSeconds,
      GARMIN_RECONCILIATION_LOOKBACK_SECONDS
    );
    const windowStart = new Date(
      windowEnd.getTime() - lookbackSeconds * 1000
    );
    const connections = await garminOAuthStore.listActiveConnectorConnections();

    for (const connection of connections) {
      const connectionWindowStart = await reconciliationWindowStart({
        connection,
        fallback: windowStart,
        integrationStatusStore
      });
      await enqueueGarminReconciliation({
        connection,
        jobs,
        windowEnd,
        windowStart: connectionWindowStart
      });
    }

    logger.info(
      {
        jobId: job.id,
        connectionCount: connections.length
      },
      "Garmin reconciliation jobs dispatched"
    );
  };
}

function createGarminImportWindowJobHandler({
  canonicalImportStore,
  defaultTimezone = GARMIN_WEBHOOK_DEFAULT_TIMEZONE,
  garminConsentStore,
  garminEntitlementStore,
  garminOAuthClient,
  garminOAuthStore,
  garminOfficialClient,
  integrationStatusStore,
  jobs,
  jobName,
  logger,
  syncNudgePublisher,
  trigger
}: GarminWebhookJobHandlerOptions & {
  jobName: string;
  trigger: "backfill" | "scheduled";
}): GarminConnectorImportJobHandler {
  return async (job) => {
    const parsed = GarminImportWindowJobDataSchema.safeParse(job.data);
    if (!parsed.success) {
      logger.warn?.({ jobId: job.id }, "Garmin connector job payload invalid");
      return null;
    }
    const jobData = parsed.data;
    const connection = {
      id: jobData.connectionId,
      providerUserId: jobData.providerUserId,
      userId: jobData.userId
    };

    try {
      const refreshToken =
        await garminOAuthStore.decryptRefreshTokenForConnectorJob({
          connectionId: connection.id,
          userId: connection.userId
        });
      if (refreshToken === null) {
        logger.warn?.(
          { jobId: job.id, connectionId: connection.id },
          "Garmin connector job skipped; refresh token unavailable"
        );
        return null;
      }

      const accessToken = await refreshGarminAccessTokenForConnectorJob({
        connectionId: connection.id,
        garminOAuthClient,
        integrationStatusStore,
        jobId: job.id,
        logger,
        refreshToken,
        trigger,
        userId: connection.userId
      });
      if (accessToken === null) {
        return null;
      }
      const dataClasses = await resolveGarminEffectiveDataClasses({
        credentialId: connection.id,
        consentStore: garminConsentStore,
        entitlementStore: garminEntitlementStore,
        userId: connection.userId
      });
      const listed = await garminOfficialClient.listActivityIds({
        accessToken: accessToken.accessToken,
        dataClasses,
        providerUserId: connection.providerUserId,
        windowEnd: jobData.windowEnd,
        windowStart: jobData.windowStart
      });
      const payloads = await garminOfficialClient.fetchActivityPayloads({
        accessToken: accessToken.accessToken,
        activityIds: listed.activityIds,
        dataClasses,
        providerUserId: connection.providerUserId
      });
      const canonical = filterGarminCanonicalImportByDataClasses(
        mapGarminOfficialActivityPayloadsToCanonicalImport(payloads, {
          defaultTimezone
        }),
        dataClasses
      );
      const result = await importCanonicalGarminBatch({
        canonical,
        canonicalImportStore,
        connectionId: connection.id,
        idempotencyKey: jobData.idempotencyKey,
        userId: connection.userId
      });

      await recordConnectorStatus({
        condition: "ok",
        connectionId: connection.id,
        integrationStatusStore,
        trigger,
        userId: connection.userId
      });
      await enqueueImportNudge({
        connectionId: connection.id,
        result,
        syncNudgePublisher,
        userId: connection.userId
      });
      logger.info(
        {
          jobId: job.id,
          batchId: jobData.idempotencyKey,
          connectionId: connection.id,
          duplicate: result.duplicate,
          jobName
        },
        "Garmin connector import completed"
      );
      return result;
    } catch (error) {
      if (error instanceof GarminRateLimitError) {
        await recordConnectorStatus({
          condition: "rate_limited",
          connectionId: connection.id,
          failureKind: "rate_limit",
          integrationStatusStore,
          retryAfterSeconds: error.retryAfterSeconds,
          trigger,
          userId: connection.userId
        });
        await enqueueRateLimitedRetry({
          jobs,
          job,
          retryAfterSeconds: error.retryAfterSeconds
        });
        logger.warn?.(
          {
            jobId: job.id,
            connectionId: connection.id,
            retryAfterSeconds: error.retryAfterSeconds
          },
          "Garmin connector job rate-limited"
        );
        return null;
      }

      await recordConnectorStatus({
        condition: "temporary_failure",
        connectionId: connection.id,
        failureKind: "unknown",
        integrationStatusStore,
        trigger,
        userId: connection.userId
      });
      logger.warn?.(
        { jobId: job.id, connectionId: connection.id },
        "Garmin connector job failed"
      );
      throw error;
    }
  };
}

export function createGarminWebhookWorker({
  jobs,
  ...handlerOptions
}: GarminWebhookJobHandlerOptions & {
  jobs: JobQueue;
}): GarminWebhookWorker {
  return {
    async start() {
      await jobs.ensureQueue({ name: GARMIN_WEBHOOK_JOB_NAME });
      await jobs.ensureQueue({ name: GARMIN_BACKFILL_JOB_NAME });
      await jobs.ensureQueue({ name: GARMIN_RECONCILIATION_JOB_NAME });
      await jobs.ensureQueue({ name: GARMIN_RECONCILIATION_DISPATCH_JOB_NAME });
      const handler = createGarminWebhookJobHandler(handlerOptions);
      const backfillHandler = createGarminBackfillJobHandler({
        ...handlerOptions,
        jobs
      });
      const reconciliationHandler = createGarminReconciliationJobHandler({
        ...handlerOptions,
        jobs
      });
      const reconciliationDispatchHandler =
        createGarminReconciliationDispatchHandler({
          backfillConfig: handlerOptions.backfillConfig,
          garminOAuthStore: handlerOptions.garminOAuthStore,
          integrationStatusStore: handlerOptions.integrationStatusStore,
          jobs,
          logger: handlerOptions.logger
        });
      await jobs.work<GarminWebhookJobData>(GARMIN_WEBHOOK_JOB_NAME, async (job) => {
        await handler(job);
      });
      await jobs.work<GarminBackfillJobData>(GARMIN_BACKFILL_JOB_NAME, async (job) => {
        await backfillHandler(job);
      });
      await jobs.work<GarminReconciliationJobData>(
        GARMIN_RECONCILIATION_JOB_NAME,
        async (job) => {
          await reconciliationHandler(job);
        }
      );
      await jobs.work<GarminReconciliationDispatchJobData>(
        GARMIN_RECONCILIATION_DISPATCH_JOB_NAME,
        reconciliationDispatchHandler
      );
      await jobs.schedule({
        name: GARMIN_RECONCILIATION_DISPATCH_JOB_NAME,
        cron:
          handlerOptions.backfillConfig?.reconciliationCron ??
          GARMIN_RECONCILIATION_SCHEDULE_CRON,
        key: GARMIN_RECONCILIATION_SCHEDULE_KEY,
        data: { source: GARMIN_OAUTH_SOURCE }
      });
      handlerOptions.logger.info(
        {
          jobName: GARMIN_WEBHOOK_JOB_NAME,
          backfillJobName: GARMIN_BACKFILL_JOB_NAME,
          reconciliationJobName: GARMIN_RECONCILIATION_JOB_NAME
        },
        "Garmin webhook worker started"
      );
    }
  };
}

export function createGarminWebhookConfigFromEnv(
  env: Record<string, string | undefined> = process.env
): GarminWebhookConfig | null {
  const sharedSecret = nonEmpty(env.GARMIN_WEBHOOK_SHARED_SECRET);
  return sharedSecret === null ? null : { sharedSecret };
}

export function createGarminBackfillConfigFromEnv(
  env: Record<string, string | undefined> = process.env
): GarminBackfillConfig {
  return {
    chunkDays: optionalPositiveInteger(env.GARMIN_BACKFILL_CHUNK_DAYS),
    historyStart: nonEmpty(env.GARMIN_BACKFILL_HISTORY_START),
    historyEnd: nonEmpty(env.GARMIN_BACKFILL_HISTORY_END),
    reconciliationCron: nonEmpty(env.GARMIN_RECONCILIATION_CRON) ?? undefined,
    reconciliationLookbackSeconds: optionalPositiveInteger(
      env.GARMIN_RECONCILIATION_LOOKBACK_SECONDS
    )
  };
}

export function createGarminOfficialApiClientFromEnv({
  env = process.env,
  fetchImpl = fetch
}: {
  env?: Record<string, string | undefined>;
  fetchImpl?: typeof fetch;
} = {}): GarminOfficialActivityClient | null {
  const activityUrlTemplate = nonEmpty(env.GARMIN_WEBHOOK_ACTIVITY_URL_TEMPLATE);
  if (activityUrlTemplate === null) {
    return null;
  }
  const activityListUrlTemplate = nonEmpty(
    env.GARMIN_WEBHOOK_ACTIVITY_LIST_URL_TEMPLATE
  );

  return createGarminOfficialHttpClient({
    activityListUrlTemplate: activityListUrlTemplate ?? undefined,
    activityUrlTemplate,
    defaultTimezone:
      nonEmpty(env.GARMIN_WEBHOOK_DEFAULT_TIMEZONE) ??
      GARMIN_WEBHOOK_DEFAULT_TIMEZONE,
    fetchImpl
  });
}

export function createGarminOfficialHttpClient({
  activityListUrlTemplate,
  activityUrlTemplate,
  defaultTimezone = GARMIN_WEBHOOK_DEFAULT_TIMEZONE,
  fetchImpl = fetch
}: {
  activityListUrlTemplate?: string;
  activityUrlTemplate: string;
  defaultTimezone?: string;
  fetchImpl?: typeof fetch;
}): GarminOfficialActivityClient {
  return {
    async listActivityIds({
      accessToken,
      dataClasses,
      providerUserId,
      windowEnd,
      windowStart
    }) {
      if (activityListUrlTemplate === undefined) {
        throw new Error("Garmin activity list URL template is not configured.");
      }
      const response = await fetchImpl(
        renderActivityListUrl(activityListUrlTemplate, {
          dataClasses,
          providerUserId,
          windowEnd,
          windowStart
        }),
        {
          headers: {
            authorization: `Bearer ${accessToken}`,
            accept: "application/json",
            "x-prn-data-classes": dataClasses.join(",")
          }
        }
      );
      if (response.status === 429) {
        throw new GarminRateLimitError({
          retryAfterSeconds: retryAfterSecondsFromResponse(response)
        });
      }
      if (!response.ok) {
        throw new Error(
          `Garmin activity list fetch failed with ${response.status}.`
        );
      }

      return normalizeActivityListResponse(await response.json());
    },
    async fetchActivityPayloads({ accessToken, activityIds, dataClasses }) {
      const payloads: GarminOfficialActivityPayload[] = [];
      for (const activityId of activityIds) {
        const response = await fetchImpl(
          renderActivityUrl(activityUrlTemplate, {
            activityId,
            dataClasses
          }),
          {
            headers: {
              authorization: `Bearer ${accessToken}`,
              accept: "application/octet-stream,application/json",
              "x-prn-data-classes": dataClasses.join(",")
            }
          }
        );
        if (response.status === 429) {
          throw new GarminRateLimitError({
            retryAfterSeconds: retryAfterSecondsFromResponse(response)
          });
        }
        if (!response.ok) {
          throw new Error(
            `Garmin activity fetch failed with ${response.status}.`
          );
        }

        const contentType = response.headers.get("content-type") ?? "";
        if (contentType.includes("json")) {
          payloads.push(
            normalizeJsonPayload((await response.json()) as unknown, {
              defaultTimezone
            })
          );
        } else {
          payloads.push({
            kind: "fit",
            fitFileBase64: Buffer.from(await response.arrayBuffer()).toString(
              "base64"
            ),
            timezone: defaultTimezone
          });
        }
      }

      return payloads;
    }
  };
}

const GarminWebhookJobDataSchema = z
  .object({
    providerUserId: z.string().min(1),
    eventId: z.string().min(1).optional(),
    activityIds: z.array(z.string().min(1)).default([]),
    idempotencyKey: z.string().min(1).max(200)
  })
  .strict();

const GarminImportWindowJobDataSchema = z
  .object({
    connectionId: z.string().min(1),
    providerUserId: z.string().min(1).nullable(),
    userId: z.string().min(1),
    windowStart: z
      .string()
      .min(1)
      .refine((value) => !Number.isNaN(Date.parse(value))),
    windowEnd: z
      .string()
      .min(1)
      .refine((value) => !Number.isNaN(Date.parse(value))),
    idempotencyKey: z.string().min(1).max(200)
  })
  .strict();

async function importCanonicalGarminBatch({
  canonical,
  canonicalImportStore,
  connectionId,
  idempotencyKey,
  userId
}: {
  canonical: GarminFitCanonicalImport;
  canonicalImportStore: CanonicalImportStore;
  connectionId: string;
  idempotencyKey: string;
  userId: string;
}) {
  const request = CanonicalImportRequestSchema.parse({
    idempotencyKey,
    consentedDataClasses: inferConsentEcho(canonical),
    ...canonical
  });

  return canonicalImportStore.importCanonicalBatch({
    actor: CANONICAL_IMPORT_ACTIVITY_LOG_ACTOR,
    batchId: idempotencyKey,
    credentialId: connectionId,
    deviceId: garminWebhookDeviceId(connectionId),
    idempotencyKey,
    request,
    userId
  });
}

async function resolveGarminEffectiveDataClasses({
  credentialId,
  consentStore,
  entitlementStore,
  userId
}: {
  credentialId: string;
  consentStore: GarminConnectorConsentStore | undefined;
  entitlementStore: GarminEntitlementStore | undefined;
  userId: string;
}) {
  const access = await listGarminConnectorConsentDataClassAccess({
    credentialId,
    consentStore,
    entitlementStore,
    userId
  });
  return access
    .filter((item) => item.enabled && item.locked === false)
    .map((item) => item.dataClass);
}

async function readGarminEnabledConsentDataClasses({
  consentStore,
  credentialId,
  userId
}: {
  consentStore: GarminConnectorConsentStore | undefined;
  credentialId: string;
  userId: string;
}) {
  if (consentStore === undefined) {
    return [];
  }

  return consentStore.listEnabledDataClasses({ credentialId, userId });
}

function filterGarminCanonicalImportByDataClasses(
  canonical: GarminFitCanonicalImport,
  dataClasses: readonly CanonicalImportConsentDataClass[]
): GarminFitCanonicalImport {
  const allowed = new Set(dataClasses);
  return {
    activities: allowed.has("activities")
      ? canonical.activities.map((activity) => ({
          ...activity,
          summaryMetrics: (activity.summaryMetrics ?? []).filter((metric) =>
            allowed.has(garminMetricDataClass(metric))
          )
        }))
      : [],
    metricReadings: canonical.metricReadings.filter((reading) =>
      allowed.has(garminMetricDataClass(reading))
    ),
    series: canonical.series.filter((series) =>
      allowed.has(garminSeriesDataClass(series))
    )
  };
}

function garminMetricDataClass(
  metric: GarminFitCanonicalImport["metricReadings"][number]
): CanonicalImportConsentDataClass {
  const key = metric.metricKey.toLowerCase();
  const units = garminMetricValueUnits(metric.value);
  if (
    key.includes("heart") ||
    key === "hrv" ||
    units.includes("beatsperminute")
  ) {
    return "heartRate";
  }
  if (
    key.includes("gps") ||
    key.includes("location") ||
    key.includes("latitude") ||
    key.includes("longitude")
  ) {
    return "gps";
  }
  if (
    key.includes("body") ||
    key.includes("weight") ||
    key.includes("mass") ||
    key.includes("fat")
  ) {
    return "bodyComposition";
  }
  if (
    key.includes("sleep") ||
    key.includes("stress") ||
    key.includes("wellness") ||
    key.includes("recovery") ||
    key.includes("battery")
  ) {
    return "sleepWellness";
  }

  return "activities";
}

function garminSeriesDataClass(
  series: GarminFitCanonicalImport["series"][number]
): CanonicalImportConsentDataClass {
  if (series.type === "heartRate") {
    return "heartRate";
  }
  if (series.type === "location") {
    return "gps";
  }

  return "activities";
}

function garminMetricValueUnits(
  value: GarminFitCanonicalImport["metricReadings"][number]["value"]
) {
  const scalarUnit = (value as { unit?: unknown }).unit;
  if (typeof scalarUnit === "string") {
    return [scalarUnit.toLowerCase()];
  }

  return Object.values(value).map((fieldValue) =>
    fieldValue.unit.toLowerCase()
  );
}

function isGarminPremiumDataClass(
  dataClass: CanonicalImportConsentDataClass
) {
  return GARMIN_PREMIUM_DATA_CLASSES.includes(
    dataClass as (typeof GARMIN_PREMIUM_DATA_CLASSES)[number]
  );
}

async function refreshGarminAccessTokenForConnectorJob({
  connectionId,
  garminOAuthClient,
  integrationStatusStore,
  jobId,
  logger,
  refreshToken,
  trigger,
  userId
}: {
  connectionId: string;
  garminOAuthClient: GarminOAuthClient;
  integrationStatusStore: IntegrationStatusStore | undefined;
  jobId: string;
  logger: JobLogger;
  refreshToken: string;
  trigger: "backfill" | "incremental" | "scheduled";
  userId: string;
}) {
  try {
    return await garminOAuthClient.refreshAccessToken({ refreshToken });
  } catch (error) {
    if (!(error instanceof GarminOAuthGrantExpiredError)) {
      throw error;
    }

    await recordConnectorStatus({
      condition: "reauth_required",
      connectionId,
      failureKind: "token_expired",
      integrationStatusStore,
      trigger,
      userId
    });
    logger.warn?.(
      { jobId, connectionId },
      "Garmin connector job requires reauthorization"
    );
    return null;
  }
}

async function recordConnectorStatus({
  condition,
  connectionId,
  failureKind,
  integrationStatusStore,
  retryAfterSeconds,
  trigger,
  userId
}: {
  condition: "ok" | "temporary_failure" | "rate_limited" | "reauth_required";
  connectionId: string;
  failureKind?: "rate_limit" | "token_expired" | "unknown";
  integrationStatusStore: IntegrationStatusStore | undefined;
  retryAfterSeconds?: number;
  trigger: "backfill" | "incremental" | "scheduled";
  userId: string;
}) {
  if (integrationStatusStore === undefined) {
    return;
  }

  await integrationStatusStore.recordIntegrationStatus({
    credentialId: connectionId,
    credentialName: GARMIN_OAUTH_CREDENTIAL_NAME,
    userId,
    report: {
      source: GARMIN_OAUTH_SOURCE,
      condition,
      trigger,
      ...(failureKind === undefined ? {} : { failureKind }),
      ...(retryAfterSeconds === undefined ? {} : { retryAfterSeconds })
    }
  });
}

async function reconciliationWindowStart({
  connection,
  fallback,
  integrationStatusStore
}: {
  connection: GarminOAuthConnectorConnection;
  fallback: Date;
  integrationStatusStore: IntegrationStatusStore | undefined;
}) {
  if (integrationStatusStore === undefined) {
    return fallback;
  }

  const statuses = await integrationStatusStore.listIntegrationStatuses(
    connection.userId
  );
  const lastSuccessfulAt = statuses.find(
    (status) =>
      status.source === GARMIN_OAUTH_SOURCE &&
      status.credentialId === connection.id &&
      status.lastSuccessfulAt !== null
  )?.lastSuccessfulAt;
  if (lastSuccessfulAt === undefined || lastSuccessfulAt === null) {
    return fallback;
  }

  const parsed = new Date(lastSuccessfulAt);
  return Number.isNaN(parsed.getTime()) ? fallback : parsed;
}

async function enqueueRateLimitedRetry({
  jobs,
  job,
  retryAfterSeconds
}: {
  jobs: JobQueue | undefined;
  job: JobEnvelope<GarminImportWindowJobData>;
  retryAfterSeconds: number;
}) {
  const idempotencyKey =
    typeof job.data.idempotencyKey === "string"
      ? job.data.idempotencyKey
      : job.id;
  await jobs?.send({
    name: job.name,
    data: job.data,
    options: {
      singletonKey: `${idempotencyKey}:retry`,
      singletonSeconds: retryAfterSeconds,
      retryLimit: GARMIN_WEBHOOK_RETRY_LIMIT
    }
  });
}

async function enqueueImportNudge({
  connectionId,
  result,
  syncNudgePublisher,
  userId
}: {
  connectionId: string;
  result: CanonicalImportStoreResult;
  syncNudgePublisher: SyncNudgePublisher | undefined;
  userId: string;
}) {
  if (
    syncNudgePublisher === undefined ||
    result.applied.every(
      (applied) => applied.entityTable === CANONICAL_IMPORT_BATCHES_ENTITY
    )
  ) {
    return;
  }

  await syncNudgePublisher.enqueueSyncNudge({
    userId,
    sourceDeviceId: garminWebhookDeviceId(connectionId),
    reason: "integration_import"
  });
}

function inferConsentEcho(canonical: GarminFitCanonicalImport) {
  const dataClasses = new Set<CanonicalImportConsentDataClass>();
  if (canonical.activities.length > 0) {
    dataClasses.add("activities");
  }
  for (const activity of canonical.activities) {
    for (const metric of activity.summaryMetrics ?? []) {
      dataClasses.add(garminMetricDataClass(metric));
    }
  }
  for (const reading of canonical.metricReadings) {
    dataClasses.add(garminMetricDataClass(reading));
  }
  for (const series of canonical.series) {
    dataClasses.add(garminSeriesDataClass(series));
  }

  return Array.from(dataClasses);
}

function normalizeJsonPayload(
  value: unknown,
  { defaultTimezone }: { defaultTimezone: string }
): GarminOfficialActivityPayload {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("Garmin JSON activity response must be an object.");
  }
  const body = value as Record<string, unknown>;
  if (typeof body.fitFileBase64 === "string") {
    return {
      kind: "fit",
      fitFileBase64: body.fitFileBase64,
      timezone:
        typeof body.timezone === "string" && body.timezone.length > 0
          ? body.timezone
          : defaultTimezone
    };
  }

  return {
    kind: "canonical",
    activities: Array.isArray(body.activities)
      ? (body.activities as GarminFitCanonicalImport["activities"])
      : [],
    metricReadings: Array.isArray(body.metricReadings)
      ? (body.metricReadings as GarminFitCanonicalImport["metricReadings"])
      : [],
    series: Array.isArray(body.series)
      ? (body.series as GarminFitCanonicalImport["series"])
      : []
  };
}

function normalizeActivityListResponse(value: unknown) {
  const activityIds = new Set<string>();
  const addId = (candidate: unknown) => {
    if (typeof candidate === "string" && candidate.trim().length > 0) {
      activityIds.add(candidate.trim());
    }
  };
  const addFromItem = (item: unknown) => {
    if (typeof item === "string") {
      addId(item);
      return;
    }
    if (typeof item !== "object" || item === null || Array.isArray(item)) {
      return;
    }
    const body = item as Record<string, unknown>;
    addId(body.activityId);
    addId(body.activity_id);
    addId(body.id);
  };

  if (Array.isArray(value)) {
    for (const item of value) {
      addFromItem(item);
    }
  } else if (typeof value === "object" && value !== null) {
    const body = value as Record<string, unknown>;
    const list = Array.isArray(body.activityIds)
      ? body.activityIds
      : Array.isArray(body.activities)
        ? body.activities
        : [];
    for (const item of list) {
      addFromItem(item);
    }
  }

  return { activityIds: Array.from(activityIds) };
}

function renderActivityUrl(
  template: string,
  {
    activityId,
    dataClasses
  }: {
    activityId: string;
    dataClasses: readonly CanonicalImportConsentDataClass[];
  }
) {
  return template
    .replaceAll("{activityId}", encodeURIComponent(activityId))
    .replaceAll("{dataClasses}", encodeURIComponent(dataClasses.join(",")));
}

function renderActivityListUrl(
  template: string,
  {
    dataClasses,
    providerUserId,
    windowEnd,
    windowStart
  }: {
    dataClasses: readonly CanonicalImportConsentDataClass[];
    providerUserId: string | null;
    windowEnd: string;
    windowStart: string;
  }
) {
  return template
    .replaceAll("{providerUserId}", encodeURIComponent(providerUserId ?? ""))
    .replaceAll("{windowStart}", encodeURIComponent(windowStart))
    .replaceAll("{windowEnd}", encodeURIComponent(windowEnd))
    .replaceAll("{dataClasses}", encodeURIComponent(dataClasses.join(",")));
}

function garminWebhookDeviceId(connectionId: string) {
  return `integration:${connectionId}`;
}

function garminWindowIdempotencyKey({
  connectionId,
  prefix,
  windowEnd,
  windowStart
}: {
  connectionId: string;
  prefix: "garmin-backfill" | "garmin-reconciliation";
  windowEnd: string;
  windowStart: string;
}) {
  return `${prefix}:${safeKeySegment(connectionId)}:${timestampKeySegment(
    windowStart
  )}:${timestampKeySegment(windowEnd)}`;
}

function timestampKeySegment(value: string) {
  return value.replace(/[:.]/g, "-");
}

function addDaysUtc(value: Date, days: number) {
  return new Date(value.getTime() + days * 24 * 60 * 60 * 1000);
}

function minDate(left: Date, right: Date) {
  return left < right ? left : right;
}

function parseInstant(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`Invalid Garmin backfill timestamp: ${value}`);
  }
  return date;
}

function normalizeChunkDays(value: number | undefined) {
  return normalizePositiveInteger(value, GARMIN_BACKFILL_DEFAULT_CHUNK_DAYS);
}

function normalizePositiveInteger(
  value: number | undefined,
  fallback: number
) {
  return Number.isInteger(value) && value !== undefined && value > 0
    ? value
    : fallback;
}

function optionalPositiveInteger(value: string | undefined) {
  const trimmed = nonEmpty(value);
  if (trimmed === null) {
    return undefined;
  }
  const parsed = Number.parseInt(trimmed, 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : undefined;
}

function retryAfterSecondsFromResponse(response: Response) {
  const retryAfter = response.headers.get("retry-after");
  if (retryAfter !== null) {
    const parsed = Number.parseInt(retryAfter, 10);
    if (Number.isInteger(parsed) && parsed > 0) {
      return parsed;
    }
  }

  return 60;
}

function digestText(value: string) {
  return createHash("sha256").update(value).digest("hex");
}

function safeKeySegment(value: string) {
  return value.replace(/[^A-Za-z0-9_.:-]/g, "_").slice(0, 120);
}

function nonEmpty(value: string | undefined) {
  return value === undefined || value.trim().length === 0 ? null : value.trim();
}
