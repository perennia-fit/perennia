import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  createApp,
  createDrizzleDevicePushTokenStore,
  createJobQueueSyncNudgePublisher,
  createMigratedServerApp,
  createPushSenderFromEnv,
  createSyncNudgeWorker,
  DEVICE_PUSH_PLATFORM_ANDROID,
  DEVICE_PUSH_PLATFORM_IOS,
  schema,
  SYNC_NUDGE_JOB_NAME,
  SYNC_NUDGE_MESSAGE_TYPE
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

test("registers a device push token for the signed-in account", async () => {
  const registrations = [];
  const app = createApp({
    logger: { info() {}, error() {} },
    syncStore: {
      async verifyBearerToken(token) {
        return token === "session-token" ? { userId: "user-1" } : null;
      }
    },
    devicePushTokenStore: {
      async registerDevicePushToken(input) {
        registrations.push(input);
      }
    }
  });

  const response = await app.request("/sync/device-push-token", {
    method: "POST",
    headers: {
      authorization: "Bearer session-token",
      "content-type": "application/json"
    },
    body: JSON.stringify({
      deviceId: "device-a",
      platform: "android",
      token: "fcm-token-1"
    })
  });

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { registered: true });
  assert.deepEqual(registrations, [
    {
      userId: "user-1",
      deviceId: "device-a",
      platform: DEVICE_PUSH_PLATFORM_ANDROID,
      token: "fcm-token-1"
    }
  ]);
});

test("sync push enqueues a best-effort nudge after applying writes", async () => {
  const nudges = [];
  const setId = "018f6a90-6d7f-7d63-bfc1-6f1025e0c001";
  const app = createApp({
    logger: { info() {}, error() {} },
    syncStore: {
      async verifyBearerToken(token) {
        return token === "session-token" ? { userId: "user-1" } : null;
      },
      async pushLoggedSets(batch) {
        return {
          accepted: batch.changes.map((change) => change.id),
          serverClock: "2026-06-22T08:00:01.000Z",
          applied: batch.changes.map((change) => ({
            id: change.id,
            updatedAt: "2026-06-22T08:00:00.000Z",
            deviceId: batch.deviceId
          }))
        };
      }
    },
    syncNudgePublisher: {
      async enqueueSyncNudge(input) {
        nudges.push(input);
        return { enqueued: true, jobId: "nudge-job-1" };
      }
    }
  });

  const response = await app.request("/sync/push", {
    method: "POST",
    headers: {
      authorization: "Bearer session-token",
      "content-type": "application/json"
    },
    body: JSON.stringify({
      protocolVersion: 1,
      deviceId: "device-a",
      entity: "logged_sets",
      changes: [
        {
          id: setId,
          payload: {
            id: setId,
            updated_at: "2026-06-22T08:00:00.000Z",
            deleted_at: null
          },
          updatedAt: "2026-06-22T08:00:00.000Z",
          deletedAt: null
        }
      ]
    })
  });

  assert.equal(response.status, 200);
  assert.deepEqual(nudges, [
    {
      userId: "user-1",
      sourceDeviceId: "device-a",
      reason: "sync_push"
    }
  ]);
});

test("sync push does not fail when nudge enqueue fails", async () => {
  const logEvents = [];
  const setId = "018f6a90-6d7f-7d63-bfc1-6f1025e0c001";
  const app = createApp({
    logger: {
      info() {},
      error(payload, message) {
        logEvents.push({ payload, message });
      }
    },
    syncStore: {
      async verifyBearerToken(token) {
        return token === "session-token" ? { userId: "user-1" } : null;
      },
      async pushLoggedSets(batch) {
        return {
          accepted: batch.changes.map((change) => change.id),
          serverClock: "2026-06-22T08:00:01.000Z",
          applied: batch.changes.map((change) => ({
            id: change.id,
            updatedAt: "2026-06-22T08:00:00.000Z",
            deviceId: batch.deviceId
          }))
        };
      }
    },
    syncNudgePublisher: {
      async enqueueSyncNudge() {
        throw new Error("queue unavailable");
      }
    }
  });

  const response = await app.request("/sync/push", {
    method: "POST",
    headers: {
      authorization: "Bearer session-token",
      "content-type": "application/json"
    },
    body: JSON.stringify({
      protocolVersion: 1,
      deviceId: "device-a",
      entity: "logged_sets",
      changes: [
        {
          id: setId,
          payload: {
            id: setId,
            updated_at: "2026-06-22T08:00:00.000Z",
            deleted_at: null
          },
          updatedAt: "2026-06-22T08:00:00.000Z",
          deletedAt: null
        }
      ]
    })
  });

  assert.equal(response.status, 200);
  assert.ok(
    logEvents.some((event) => event.message === "sync nudge enqueue failed")
  );
});

test("job queue nudge publisher sends the dispatch job", async () => {
  const sends = [];
  const publisher = createJobQueueSyncNudgePublisher({
    async start() {},
    async stop() {},
    async ensureQueue() {},
    async schedule() {},
    async send(input) {
      sends.push(input);
      return "queued-nudge-1";
    },
    async work() {}
  });

  const result = await publisher.enqueueSyncNudge({
    userId: "user-1",
    sourceDeviceId: "device-a",
    reason: "sync_push"
  });

  assert.deepEqual(result, { enqueued: true, jobId: "queued-nudge-1" });
  assert.deepEqual(sends, [
    {
      name: SYNC_NUDGE_JOB_NAME,
      data: {
        userId: "user-1",
        sourceDeviceId: "device-a",
        reason: "sync_push"
      },
      options: {
        retryLimit: 0
      }
    }
  ]);
});

test("sync nudge worker retries only failed device tokens", async () => {
  const workers = new Map();
  const sentNudges = [];
  const queuedRetries = [];
  const warnings = [];
  const jobs = {
    async start() {},
    async stop() {},
    async ensureQueue(input) {
      assert.equal(input.name, SYNC_NUDGE_JOB_NAME);
    },
    async schedule() {},
    async send(input) {
      queuedRetries.push(input);
      return `retry-${queuedRetries.length}`;
    },
    async work(name, handler) {
      workers.set(name, handler);
    }
  };
  const worker = createSyncNudgeWorker({
    jobs,
    devicePushTokenStore: {
      async listDevicePushTokensForUser(input) {
        assert.deepEqual(input, {
          userId: "user-1",
          excludeDeviceId: "device-a"
        });
        return [
          {
            id: "token-1",
            userId: "user-1",
            deviceId: "device-b",
            platform: DEVICE_PUSH_PLATFORM_ANDROID,
            token: "fcm-token-1"
          },
          {
            id: "token-2",
            userId: "user-1",
            deviceId: "device-c",
            platform: DEVICE_PUSH_PLATFORM_IOS,
            token: "apns-token-1"
          }
        ];
      }
    },
    pushSender: {
      async sendSilentSyncNudge(token, nudge) {
        sentNudges.push({ token: token.token, nudge });
        if (token.token === "apns-token-1") {
          throw new Error("apns unavailable");
        }
        return { provider: "fcm", skipped: false };
      }
    },
    logger: {
      info() {},
      warn(payload, message) {
        warnings.push({ payload, message });
      }
    }
  });

  await worker.start();
  await workers.get(SYNC_NUDGE_JOB_NAME)({
    id: "nudge-job-1",
    name: SYNC_NUDGE_JOB_NAME,
    data: {
      userId: "user-1",
      sourceDeviceId: "device-a",
      reason: "agent_write"
    }
  });

  assert.deepEqual(sentNudges, [
    {
      token: "fcm-token-1",
      nudge: { reason: "agent_write", sourceDeviceId: "device-a" }
    },
    {
      token: "apns-token-1",
      nudge: { reason: "agent_write", sourceDeviceId: "device-a" }
    }
  ]);
  assert.ok(
    warnings.some((event) => event.message === "sync nudge push send failed")
  );
  assert.deepEqual(queuedRetries, [
    {
      name: SYNC_NUDGE_JOB_NAME,
      data: {
        userId: "user-1",
        sourceDeviceId: "device-a",
        reason: "agent_write",
        targetTokenIds: ["token-2"],
        attempt: 1
      },
      options: { retryLimit: 0 }
    }
  ]);

  await workers.get(SYNC_NUDGE_JOB_NAME)({
    id: "nudge-job-2",
    name: SYNC_NUDGE_JOB_NAME,
    data: queuedRetries[0].data
  });
  assert.deepEqual(
    sentNudges.map((entry) => entry.token),
    ["fcm-token-1", "apns-token-1", "apns-token-1"]
  );
});

test("unconfigured push providers skip nudges without throwing", async () => {
  const logs = [];
  const sender = createPushSenderFromEnv(
    {},
    {
      info(payload, message) {
        logs.push({ payload, message });
      }
    }
  );

  const result = await sender.sendSilentSyncNudge(
    {
      id: "token-1",
      userId: "user-1",
      deviceId: "device-a",
      platform: DEVICE_PUSH_PLATFORM_ANDROID,
      token: "fcm-token"
    },
    { reason: "sync_push" }
  );

  assert.deepEqual(result, { provider: "none", skipped: true });
  assert.ok(
    logs.some((event) => event.message === "sync nudge skipped; push providers unconfigured")
  );
});

test(
  "device push token store upserts the latest token per user device platform",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const store = createDrizzleDevicePushTokenStore(serverApp.database.db);
    const userId = `user-${randomUUID()}`;

    try {
      await serverApp.database.db.insert(schema.user).values({
        id: userId,
        name: "Push User",
        email: `${userId}@example.com`,
        emailVerified: true
      });
      await store.registerDevicePushToken({
        userId,
        deviceId: "device-a",
        platform: DEVICE_PUSH_PLATFORM_ANDROID,
        token: "old-token"
      });
      await store.registerDevicePushToken({
        userId,
        deviceId: "device-a",
        platform: DEVICE_PUSH_PLATFORM_ANDROID,
        token: "new-token"
      });

      const tokens = await store.listDevicePushTokensForUser({ userId });

      assert.equal(tokens.length, 1);
      assert.equal(tokens[0].token, "new-token");
      assert.equal(tokens[0].deviceId, "device-a");
      assert.equal(tokens[0].platform, DEVICE_PUSH_PLATFORM_ANDROID);
    } finally {
      await serverApp.database.close();
    }
  }
);

test("silent nudge messages use the stable sync payload marker", () => {
  assert.equal(SYNC_NUDGE_MESSAGE_TYPE, "sync_nudge");
});
