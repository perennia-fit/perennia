import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  createApp,
  createDrizzleIntegrationCredentialStore,
  createMigratedServerApp,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error(
    "DATABASE_URL must be set for integration status tests."
  );
}

test("integration status reports reject imported data payloads and malformed timestamps", async () => {
  const app = createApp({
    logger: { info() {}, error() {} },
    integrationCredentialStore: {
      async authenticateIntegrationCredential(secret) {
        return secret === "prn_integration_secret"
          ? {
              actor: "integration",
              userId: "user-1",
              credentialId: "credential-1",
              credentialName: "Garmin sidecar",
              scope: {
                writeObservations: true,
                materializeAndLinkWorkouts: true,
                accountMutation: false,
                hardDeleteOrPurge: false
              }
            }
          : null;
      }
    },
    integrationStatusStore: {
      async recordIntegrationStatus() {
        throw new Error("payload-shaped status reports must be rejected first");
      },
      async listIntegrationStatuses() {
        return [];
      }
    },
    syncStore: {
      async verifyBearerToken() {
        return null;
      }
    }
  });

  const response = await app.request("/integrations/status", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_integration_secret",
      "content-type": "application/json"
    },
    body: JSON.stringify({
      source: "garmin",
      condition: "temporary_failure",
      failureKind: "network",
      occurredAt: "2026-06-25T10:00:00.000Z",
      activities: [{ externalId: "must-not-be-status-data" }]
    })
  });

  assert.equal(response.status, 400);

  const invalidTimestampResponse = await app.request("/integrations/status", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_integration_secret",
      "content-type": "application/json"
    },
    body: JSON.stringify({
      source: "garmin",
      condition: "temporary_failure",
      failureKind: "network",
      occurredAt: "not-a-timestamp"
    })
  });

  assert.equal(invalidTimestampResponse.status, 400);
});

test(
  "integration status failure writes no core rows and stores only health metadata",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false,
      rateLimit: false
    });
    const credentialStore = createDrizzleIntegrationCredentialStore(
      serverApp.database.db
    );
    const userId = await createUser(serverApp, "integration-status-failure");

    try {
      const issued = await credentialStore.issueIntegrationCredential({
        userId,
        name: "Garmin sidecar"
      });

      const response = await postIntegrationStatus(serverApp, issued.secret, {
        source: "garmin",
        condition: "reauth_required",
        failureKind: "token_expired",
        trigger: "scheduled",
        occurredAt: "2026-06-25T10:00:00.000Z"
      });

      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.status.source, "garmin");
      assert.equal(body.status.condition, "reauth_required");
      assert.equal(body.status.recoveryAction, "reauth");
      assert.equal(body.status.manualFitImportFallback, true);
      assert.equal(body.status.lastSuccessfulAt, null);
      assert.equal(body.status.firstFailureAt, "2026-06-25T10:00:00.000Z");
      assert.equal(body.status.lastFailureAt, "2026-06-25T10:00:00.000Z");
      assert.equal(body.status.failureKind, "token_expired");
      assert.equal(JSON.stringify(body).includes("must-not-be-status-data"), false);

      const statusRows = await serverApp.database.sql`
        select source, condition, failure_kind, recovery_action, retry_after_seconds
        from integration_statuses
        where user_id = ${userId}
      `;
      assert.equal(statusRows.length, 1);
      assert.deepEqual(statusRows[0], {
        source: "garmin",
        condition: "reauth_required",
        failure_kind: "token_expired",
        recovery_action: "reauth",
        retry_after_seconds: null
      });

      assert.equal(await countRows(serverApp, "logged_sets", userId), 0);
      assert.equal(await countRows(serverApp, "external_activities", userId), 0);
      assert.equal(await countRows(serverApp, "metric_readings", userId), 0);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "integration status rate-limit reports expose backoff metadata",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false,
      rateLimit: false
    });
    const credentialStore = createDrizzleIntegrationCredentialStore(
      serverApp.database.db
    );
    const userId = await createUser(serverApp, "integration-status-backoff");

    try {
      const issued = await credentialStore.issueIntegrationCredential({
        userId,
        name: "Garmin sidecar"
      });

      const response = await postIntegrationStatus(serverApp, issued.secret, {
        source: "garmin",
        condition: "rate_limited",
        failureKind: "rate_limit",
        trigger: "scheduled",
        occurredAt: "2026-06-25T10:00:00.000Z",
        retryAfterSeconds: 120
      });

      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.status.condition, "rate_limited");
      assert.equal(body.status.recoveryAction, "backoff");
      assert.equal(body.status.retryAfterSeconds, 120);
      assert.equal(body.status.nextAttemptAt, "2026-06-25T10:02:00.000Z");
      assert.equal(body.status.manualFitImportFallback, true);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "integration status list is account-scoped for the Settings status surface",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false,
      rateLimit: false
    });
    const credentialStore = createDrizzleIntegrationCredentialStore(
      serverApp.database.db
    );
    const userA = await createUser(serverApp, "integration-status-list-a");
    const userB = await createUser(serverApp, "integration-status-list-b");
    const sessionToken = `session-${randomUUID()}`;

    try {
      const issuedA = await credentialStore.issueIntegrationCredential({
        userId: userA,
        name: "Garmin sidecar"
      });
      const issuedB = await credentialStore.issueIntegrationCredential({
        userId: userB,
        name: "Other sidecar"
      });
      await createSession(serverApp, userA, sessionToken);

      await postIntegrationStatus(serverApp, issuedA.secret, {
        source: "garmin",
        condition: "temporary_failure",
        failureKind: "network",
        occurredAt: "2026-06-25T10:00:00.000Z"
      });
      await postIntegrationStatus(serverApp, issuedB.secret, {
        source: "garmin",
        condition: "reauth_required",
        failureKind: "token_expired",
        occurredAt: "2026-06-25T10:00:00.000Z"
      });

      const response = await serverApp.app.request("/integrations/status", {
        headers: { authorization: `Bearer ${sessionToken}` }
      });

      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.statuses.length, 1);
      assert.equal(body.statuses[0].condition, "temporary_failure");
      assert.equal(body.statuses[0].credentialName, "Garmin sidecar");
    } finally {
      await serverApp.database.close();
    }
  }
);

async function postIntegrationStatus(serverApp, secret, body) {
  return serverApp.app.request("/integrations/status", {
    method: "POST",
    headers: {
      authorization: `Bearer ${secret}`,
      "content-type": "application/json"
    },
    body: JSON.stringify(body)
  });
}

async function createUser(serverApp, label) {
  const userId = `user-${label}-${randomUUID()}`;
  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: `Integration Status Test ${label}`,
    email: `${userId}@example.com`,
    emailVerified: true
  });
  return userId;
}

async function createSession(serverApp, userId, token) {
  await serverApp.database.db.insert(schema.session).values({
    id: `session-${randomUUID()}`,
    userId,
    token,
    expiresAt: new Date(Date.now() + 60 * 60 * 1000)
  });
}

async function countRows(serverApp, tableName, userId) {
  const rows = await serverApp.database.sql`
    select count(*)::int as count
    from ${serverApp.database.sql(tableName)}
    where user_id = ${userId}
  `;
  return rows[0].count;
}
