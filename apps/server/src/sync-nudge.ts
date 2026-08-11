import { sign as cryptoSign } from "node:crypto";

import type {
  DevicePushPlatform,
  DevicePushTokenStore,
  RegisteredDevicePushToken
} from "./device-push-tokens.js";
import {
  DEVICE_PUSH_PLATFORM_ANDROID,
  DEVICE_PUSH_PLATFORM_IOS
} from "./device-push-tokens.js";
import type {
  JobData,
  JobLogger,
  JobQueue,
  JobWorkHandler
} from "./jobs/index.js";
import { SYNC_PROTOCOL_VERSION } from "./sync.js";

export const SYNC_NUDGE_JOB_NAME = "sync.nudge.dispatch";
export const SYNC_NUDGE_MESSAGE_TYPE = "sync_nudge";
export const SYNC_NUDGE_RETRY_LIMIT = 3;

export type SyncNudgeReason =
  | "sync_push"
  | "manual"
  | "agent_write"
  | "integration_import"
  | "integration_purge";

export type SyncNudgeJobData = JobData & {
  userId?: string;
  sourceDeviceId?: string;
  reason?: SyncNudgeReason;
  targetTokenIds?: string[];
  attempt?: number;
};

export type EnqueueSyncNudgeInput = {
  userId: string;
  sourceDeviceId?: string;
  reason: SyncNudgeReason;
};

export type SyncNudgeEnqueueResult = {
  enqueued: boolean;
  jobId: string | null;
};

export type SyncNudgePublisher = {
  enqueueSyncNudge(input: EnqueueSyncNudgeInput): Promise<SyncNudgeEnqueueResult>;
};

export type SilentSyncNudge = {
  reason: SyncNudgeReason;
  sourceDeviceId?: string;
};

export type PushSendResult = {
  provider: "fcm" | "apns" | "none";
  skipped: boolean;
  statusCode?: number;
};

export type PushSender = {
  sendSilentSyncNudge(
    token: RegisteredDevicePushToken,
    nudge: SilentSyncNudge
  ): Promise<PushSendResult>;
};

export type SyncNudgeWorker = {
  start(): Promise<void>;
};

export type SyncNudgeWorkerOptions = {
  jobs: JobQueue;
  devicePushTokenStore: DevicePushTokenStore;
  pushSender: PushSender;
  logger: JobLogger;
};

type FetchLike = typeof fetch;

type FcmConfig = {
  projectId: string;
  clientEmail: string;
  privateKey: string;
};

type ApnsConfig = {
  keyId: string;
  teamId: string;
  privateKey: string;
  topic: string;
  endpoint: string;
};

export function createJobQueueSyncNudgePublisher(
  jobs: JobQueue
): SyncNudgePublisher {
  return {
    async enqueueSyncNudge(input) {
      const jobId = await jobs.send({
        name: SYNC_NUDGE_JOB_NAME,
        data: {
          userId: input.userId,
          sourceDeviceId: input.sourceDeviceId,
          reason: input.reason
        },
        options: {
          // Retry individual failures explicitly so successful devices are
          // never sent the same nudge again by a whole-job retry.
          retryLimit: 0
        }
      });

      return { enqueued: jobId !== null, jobId };
    }
  };
}

export function createSyncNudgeWorker({
  jobs,
  devicePushTokenStore,
  pushSender,
  logger
}: SyncNudgeWorkerOptions): SyncNudgeWorker {
  return {
    async start() {
      await jobs.ensureQueue({ name: SYNC_NUDGE_JOB_NAME });
      await jobs.work<SyncNudgeJobData>(
        SYNC_NUDGE_JOB_NAME,
        createSyncNudgeHandler({
          jobs,
          devicePushTokenStore,
          pushSender,
          logger
        })
      );
      logger.info({ jobName: SYNC_NUDGE_JOB_NAME }, "sync nudge worker started");
    }
  };
}

export function createPushSenderFromEnv(
  env: Record<string, string | undefined>,
  logger: JobLogger,
  fetchImpl: FetchLike = fetch
): PushSender {
  const fcmConfig = readFcmConfig(env);
  const apnsConfig = readApnsConfig(env);

  if (fcmConfig === null && apnsConfig === null) {
    return createNoopPushSender(logger);
  }

  const fcmSender =
    fcmConfig === null ? null : createFcmV1Sender(fcmConfig, fetchImpl);
  const apnsSender =
    apnsConfig === null ? null : createApnsSender(apnsConfig, fetchImpl);

  return {
    async sendSilentSyncNudge(token, nudge) {
      const provider = providerForPlatform(token.platform, fcmSender, apnsSender);

      if (provider === null) {
        logger.info(
          {
            platform: token.platform,
            deviceId: token.deviceId
          },
          "sync nudge skipped; push provider unconfigured for platform"
        );
        return { provider: "none", skipped: true };
      }

      return provider.send(token, nudge);
    }
  };
}

function createNoopPushSender(logger: JobLogger): PushSender {
  return {
    async sendSilentSyncNudge() {
      logger.info(
        {},
        "sync nudge skipped; push providers unconfigured"
      );
      return { provider: "none", skipped: true };
    }
  };
}

function createSyncNudgeHandler({
  jobs,
  devicePushTokenStore,
  pushSender,
  logger
}: {
  jobs: JobQueue;
  devicePushTokenStore: DevicePushTokenStore;
  pushSender: PushSender;
  logger: JobLogger;
}): JobWorkHandler<SyncNudgeJobData> {
  return async (job) => {
    const userId = readString(job.data.userId);
    if (userId === null) {
      logger.warn?.({ jobId: job.id }, "sync nudge job missing user id");
      return;
    }

    const sourceDeviceId = readOptionalString(job.data.sourceDeviceId);
    const reason = readSyncNudgeReason(job.data.reason);
    const targetTokenIds = readStringArray(job.data.targetTokenIds);
    const allTokens = await devicePushTokenStore.listDevicePushTokensForUser({
      userId,
      excludeDeviceId: sourceDeviceId
    });
    const tokens =
      targetTokenIds === null
        ? allTokens
        : allTokens.filter((token) => targetTokenIds.includes(token.id));
    const attempt = readAttempt(job.data.attempt);
    let dispatchedCount = 0;
    let skippedCount = 0;
    let failedCount = 0;
    let prunedCount = 0;
    const retryTokenIds: string[] = [];

    for (const token of tokens) {
      try {
        const result = await pushSender.sendSilentSyncNudge(token, {
          reason,
          sourceDeviceId
        });
        if (result.skipped) {
          skippedCount += 1;
        } else {
          dispatchedCount += 1;
        }
      } catch (error) {
        if (error instanceof PushDeliveryError && !error.retryable) {
          prunedCount += 1;
          await devicePushTokenStore.removeDevicePushToken?.({
            userId,
            tokenId: token.id
          });
          logger.warn?.(
            {
              error,
              jobId: job.id,
              tokenId: token.id,
              platform: token.platform,
              deviceId: token.deviceId
            },
            "sync nudge removed terminal push token"
          );
          continue;
        }
        failedCount += 1;
        retryTokenIds.push(token.id);
        logger.warn?.(
          {
            error,
            jobId: job.id,
            tokenId: token.id,
            platform: token.platform,
            deviceId: token.deviceId
          },
          "sync nudge push send failed"
        );
      }
    }

    logger.info(
      {
        jobId: job.id,
        userId,
        tokenCount: tokens.length,
        dispatchedCount,
        skippedCount,
        failedCount,
        prunedCount,
        attempt
      },
      "sync nudge dispatch completed"
    );

    if (retryTokenIds.length > 0 && attempt < SYNC_NUDGE_RETRY_LIMIT) {
      await jobs.send({
        name: SYNC_NUDGE_JOB_NAME,
        data: {
          userId,
          sourceDeviceId,
          reason,
          targetTokenIds: retryTokenIds,
          attempt: attempt + 1
        },
        options: {
          retryLimit: 0
        }
      });
    }
  };
}

class PushDeliveryError extends Error {
  constructor(
    message: string,
    readonly retryable: boolean,
    readonly statusCode: number
  ) {
    super(message);
  }
}

type PlatformSender = {
  send(
    token: RegisteredDevicePushToken,
    nudge: SilentSyncNudge
  ): Promise<PushSendResult>;
};

function providerForPlatform(
  platform: DevicePushPlatform,
  fcmSender: PlatformSender | null,
  apnsSender: PlatformSender | null
) {
  if (platform === DEVICE_PUSH_PLATFORM_ANDROID) {
    return fcmSender;
  }
  if (platform === DEVICE_PUSH_PLATFORM_IOS) {
    return apnsSender;
  }
  return null;
}

function createFcmV1Sender(
  config: FcmConfig,
  fetchImpl: FetchLike
): PlatformSender {
  let cachedAccessToken: { token: string; expiresAtMs: number } | null = null;

  async function getAccessToken() {
    const now = Date.now();
    if (
      cachedAccessToken !== null &&
      cachedAccessToken.expiresAtMs - 60_000 > now
    ) {
      return cachedAccessToken.token;
    }

    const issuedAt = Math.floor(now / 1000);
    const assertion = signJwt({
      algorithm: "RS256",
      header: { alg: "RS256", typ: "JWT" },
      claims: {
        iss: config.clientEmail,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token",
        iat: issuedAt,
        exp: issuedAt + 3600
      },
      privateKey: config.privateKey
    });
    const response = await fetchImpl("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: {
        "content-type": "application/x-www-form-urlencoded"
      },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion
      }).toString()
    });
    const body = await readJsonObject(response);

    if (!response.ok) {
      throw new Error(`FCM OAuth token request failed with ${response.status}.`);
    }

    const token = readRequiredJsonString(body, "access_token");
    const expiresIn = readOptionalJsonNumber(body, "expires_in") ?? 3600;
    cachedAccessToken = {
      token,
      expiresAtMs: now + expiresIn * 1000
    };
    return token;
  }

  return {
    async send(token, nudge) {
      const accessToken = await getAccessToken();
      const response = await fetchImpl(
        `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(
          config.projectId
        )}/messages:send`,
        {
          method: "POST",
          headers: {
            authorization: `Bearer ${accessToken}`,
            "content-type": "application/json"
          },
          body: JSON.stringify({
            message: {
              token: token.token,
              data: createStringNudgePayload(nudge),
              android: {
                priority: "high"
              }
            }
          })
        }
      );
      if (!response.ok) {
        const body = await response.text();
        throw new PushDeliveryError(
          `FCM send failed with ${response.status}: ${body}`,
          !isTerminalFcmFailure(response.status, body),
          response.status
        );
      }

      return { provider: "fcm", skipped: false, statusCode: response.status };
    }
  };
}

function createApnsSender(
  config: ApnsConfig,
  fetchImpl: FetchLike
): PlatformSender {
  return {
    async send(token, nudge) {
      const issuedAt = Math.floor(Date.now() / 1000);
      const authorization = signJwt({
        algorithm: "ES256",
        header: { alg: "ES256", kid: config.keyId },
        claims: {
          iss: config.teamId,
          iat: issuedAt
        },
        privateKey: config.privateKey
      });
      const response = await fetchImpl(
        `${config.endpoint}/3/device/${encodeURIComponent(token.token)}`,
        {
          method: "POST",
          headers: {
            authorization: `bearer ${authorization}`,
            "apns-push-type": "background",
            "apns-priority": "5",
            "apns-topic": config.topic,
            "content-type": "application/json"
          },
          body: JSON.stringify({
            aps: {
              "content-available": 1
            },
            ...createStringNudgePayload(nudge)
          })
        }
      );
      if (!response.ok) {
        const body = await response.text();
        throw new PushDeliveryError(
          `APNs send failed with ${response.status}: ${body}`,
          !isTerminalApnsFailure(response.status, body),
          response.status
        );
      }

      return { provider: "apns", skipped: false, statusCode: response.status };
    }
  };
}

function createStringNudgePayload(nudge: SilentSyncNudge) {
  return {
    type: SYNC_NUDGE_MESSAGE_TYPE,
    protocolVersion: String(SYNC_PROTOCOL_VERSION),
    reason: nudge.reason,
    ...(nudge.sourceDeviceId === undefined
      ? {}
      : { sourceDeviceId: nudge.sourceDeviceId })
  };
}

function readFcmConfig(env: Record<string, string | undefined>): FcmConfig | null {
  const serviceAccount = readServiceAccountJson(env.FCM_SERVICE_ACCOUNT_JSON);
  const projectId = env.FCM_PROJECT_ID ?? readStringField(serviceAccount, "project_id");
  const clientEmail =
    env.FCM_CLIENT_EMAIL ?? readStringField(serviceAccount, "client_email");
  const privateKey =
    env.FCM_PRIVATE_KEY ?? readStringField(serviceAccount, "private_key");

  if (projectId === null || clientEmail === null || privateKey === null) {
    return null;
  }

  return {
    projectId,
    clientEmail,
    privateKey: normalizePrivateKey(privateKey)
  };
}

function readApnsConfig(env: Record<string, string | undefined>): ApnsConfig | null {
  const keyId = env.APNS_KEY_ID;
  const teamId = env.APNS_TEAM_ID;
  const privateKey = env.APNS_PRIVATE_KEY;
  const topic = env.APNS_TOPIC ?? env.APNS_BUNDLE_ID;

  if (
    keyId === undefined ||
    teamId === undefined ||
    privateKey === undefined ||
    topic === undefined
  ) {
    return null;
  }

  return {
    keyId,
    teamId,
    privateKey: normalizePrivateKey(privateKey),
    topic,
    endpoint:
      env.APNS_ENDPOINT ??
      (env.APNS_ENVIRONMENT === "production"
        ? "https://api.push.apple.com"
        : "https://api.sandbox.push.apple.com")
  };
}

function readServiceAccountJson(rawValue: string | undefined) {
  if (rawValue === undefined || rawValue.length === 0) {
    return null;
  }

  const parsed = JSON.parse(rawValue) as unknown;
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error("FCM_SERVICE_ACCOUNT_JSON must be a JSON object.");
  }

  return parsed as Record<string, unknown>;
}

function readStringField(
  object: Record<string, unknown> | null,
  field: string
) {
  const value = object?.[field];
  return typeof value === "string" && value.length > 0 ? value : null;
}

function normalizePrivateKey(value: string) {
  return value.replace(/\\n/g, "\n");
}

function signJwt({
  algorithm,
  header,
  claims,
  privateKey
}: {
  algorithm: "RS256" | "ES256";
  header: Record<string, unknown>;
  claims: Record<string, unknown>;
  privateKey: string;
}) {
  const encodedHeader = base64Url(JSON.stringify(header));
  const encodedClaims = base64Url(JSON.stringify(claims));
  const signingInput = `${encodedHeader}.${encodedClaims}`;
  const signature =
    algorithm === "ES256"
      ? cryptoSign("SHA256", Buffer.from(signingInput), {
          key: privateKey,
          dsaEncoding: "ieee-p1363"
        })
      : cryptoSign("RSA-SHA256", Buffer.from(signingInput), privateKey);

  return `${signingInput}.${base64Url(signature)}`;
}

function base64Url(value: string | Buffer) {
  return Buffer.from(value).toString("base64url");
}

async function readJsonObject(response: Response) {
  const decoded = (await response.json()) as unknown;
  if (typeof decoded !== "object" || decoded === null || Array.isArray(decoded)) {
    throw new Error("Expected a JSON object response.");
  }

  return decoded as Record<string, unknown>;
}

function readRequiredJsonString(
  object: Record<string, unknown>,
  field: string
) {
  const value = object[field];
  if (typeof value === "string" && value.length > 0) {
    return value;
  }

  throw new Error(`Expected ${field} to be a non-empty string.`);
}

function readOptionalJsonNumber(
  object: Record<string, unknown>,
  field: string
) {
  const value = object[field];
  return typeof value === "number" ? value : null;
}

function readString(value: unknown) {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function readOptionalString(value: unknown) {
  return value === undefined ? undefined : readString(value) ?? undefined;
}

function readStringArray(value: unknown): string[] | null {
  if (!Array.isArray(value)) {
    return null;
  }
  return value.filter(
    (entry): entry is string =>
      typeof entry === "string" && entry.length > 0
  );
}

function readAttempt(value: unknown) {
  return typeof value === "number" && Number.isInteger(value) && value >= 0
    ? value
    : 0;
}

function isTerminalFcmFailure(statusCode: number, body: string) {
  return (
    statusCode === 404 ||
    (statusCode === 400 &&
      (body.includes("UNREGISTERED") ||
        body.includes("INVALID_ARGUMENT")))
  );
}

function isTerminalApnsFailure(statusCode: number, body: string) {
  return (
    statusCode === 410 ||
    (statusCode === 400 &&
      (body.includes("BadDeviceToken") ||
        body.includes("DeviceTokenNotForTopic")))
  );
}

function readSyncNudgeReason(value: unknown): SyncNudgeReason {
  if (
    value === "manual" ||
    value === "agent_write" ||
    value === "integration_import" ||
    value === "integration_purge"
  ) {
    return value;
  }

  return "sync_push";
}
