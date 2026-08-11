import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import test from "node:test";

import {
  GARMIN_BACKFILL_JOB_NAME,
  GARMIN_BACKFILL_SINGLETON_SECONDS,
  applyMigrations,
  createApp,
  createDatabaseClient,
  createDrizzleGarminOAuthConnectionStore,
  createDrizzleIntegrationStatusStore,
  createGarminOAuthHttpClient,
  createGarminOAuthTokenCipher,
  GarminOAuthGrantExpiredError,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for Garmin OAuth tests.");
}

test("Garmin OAuth HTTP client classifies invalid refresh grants for reauth", async () => {
  const client = createGarminOAuthHttpClient({
    clientId: "garmin-client-id",
    clientSecret: "garmin-client-secret",
    tokenEndpoint: "https://garmin.example.test/oauth/token",
    fetchImpl: async () =>
      new Response(
        JSON.stringify({
          error: "invalid_grant",
          error_description: "Refresh token expired"
        }),
        {
          status: 400,
          headers: { "content-type": "application/json" }
        }
      )
  });

  await assert.rejects(
    () => client.refreshAccessToken({ refreshToken: "expired-refresh-token" }),
    (error) =>
      error instanceof GarminOAuthGrantExpiredError &&
      error.status === 400 &&
      error.providerError === "invalid_grant"
  );
});

test(
  "Garmin OAuth callback stores encrypted refresh-token custody and healthy status",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `garmin-oauth-user-${randomUUID()}`;
    const sessionToken = `session-${randomUUID()}`;
    const refreshToken = `garmin-refresh-${randomUUID()}`;
    const logs = [];
    const exchanges = [];
    const revocations = [];
    const queuedJobs = [];
    const store = createDrizzleGarminOAuthConnectionStore({
      cipher: createGarminOAuthTokenCipher(randomBytes(32)),
      db: database.db
    });
    const app = createApp({
      garminOAuthClient: {
        async exchangeCode(input) {
          exchanges.push(input);
          return {
            accessToken: `garmin-access-${randomUUID()}`,
            expiresInSeconds: 3600,
            providerUserId: "garmin-user-1",
            refreshToken,
            scope: "activity heartrate"
          };
        },
        async refreshAccessToken() {
          throw new Error("OAuth callback tests should not refresh access tokens");
        },
        async revokeRefreshToken(token) {
          revocations.push(token);
          return { revoked: true };
        }
      },
      garminOAuthConfig: {
        authorizationEndpoint: "https://garmin.example.test/oauth/authorize",
        clientId: "garmin-client-id",
        redirectUri: "https://api.example.test/integrations/garmin/oauth/callback",
        scopes: ["activity", "heartrate"],
        stateTtlSeconds: 600
      },
      garminOAuthStore: store,
      garminBackfillConfig: {
        chunkDays: 30,
        historyStart: "2026-01-01T00:00:00.000Z",
        historyEnd: "2026-03-02T00:00:00.000Z"
      },
      garminWebhookJobQueue: {
        async start() {},
        async stop() {},
        async ensureQueue() {},
        async schedule() {},
        async send(input) {
          queuedJobs.push(input);
          return `backfill-job-${queuedJobs.length}`;
        },
        async work() {}
      },
      integrationStatusStore: createDrizzleIntegrationStatusStore(database.db),
      logger: captureLogger(logs),
      syncStore: {
        async verifyBearerToken(token) {
          return token === sessionToken ? { userId } : null;
        },
        async explainUnauthorizedBearerToken() {
          return "The session bearer token is invalid or expired.";
        }
      }
    });

    try {
      await seedUser(database, userId);
      await seedSession(database, { userId, token: sessionToken });

      const startResponse = await app.request("/integrations/garmin/oauth/start", {
        method: "POST",
        headers: { authorization: `Bearer ${sessionToken}` }
      });
      assert.equal(startResponse.status, 200);
      const startBody = await startResponse.json();
      const authorizationUrl = new URL(startBody.authorizationUrl);
      assert.equal(
        `${authorizationUrl.origin}${authorizationUrl.pathname}`,
        "https://garmin.example.test/oauth/authorize"
      );
      assert.equal(authorizationUrl.searchParams.get("client_id"), "garmin-client-id");
      assert.equal(authorizationUrl.searchParams.get("response_type"), "code");
      assert.equal(
        authorizationUrl.searchParams.get("redirect_uri"),
        "https://api.example.test/integrations/garmin/oauth/callback"
      );
      assert.equal(authorizationUrl.searchParams.get("scope"), "activity heartrate");
      const state = authorizationUrl.searchParams.get("state");
      assert.equal(typeof state, "string");
      assert.notEqual(state, "");
      assert.equal(state.includes(userId), false);

      const callbackResponse = await app.request(
        `/integrations/garmin/oauth/callback?code=${encodeURIComponent(
          "garmin-auth-code"
        )}&state=${encodeURIComponent(state)}`
      );
      assert.equal(callbackResponse.status, 200);
      const callbackBody = await callbackResponse.json();
      assert.equal(callbackBody.connection.source, "garmin");
      assert.equal(callbackBody.connection.connected, true);
      assert.equal(callbackBody.connection.providerUserId, "garmin-user-1");
      assert.equal(Object.hasOwn(callbackBody.connection, "refreshToken"), false);
      assert.equal(JSON.stringify(callbackBody).includes(refreshToken), false);
      assert.deepEqual(exchanges, [
        {
          code: "garmin-auth-code",
          redirectUri: "https://api.example.test/integrations/garmin/oauth/callback"
        }
      ]);
      assert.deepEqual(
        queuedJobs.map((job) => ({
          name: job.name,
          windowStart: job.data.windowStart,
          windowEnd: job.data.windowEnd,
          idempotencyKey: job.data.idempotencyKey,
          singletonKey: job.options.singletonKey,
          singletonSeconds: job.options.singletonSeconds,
          retryLimit: job.options.retryLimit
        })),
        [
          {
            name: GARMIN_BACKFILL_JOB_NAME,
            windowStart: "2026-01-01T00:00:00.000Z",
            windowEnd: "2026-01-31T00:00:00.000Z",
            idempotencyKey: `garmin-backfill:${callbackBody.connection.id}:2026-01-01T00-00-00-000Z:2026-01-31T00-00-00-000Z`,
            singletonKey: `garmin-backfill:${callbackBody.connection.id}:2026-01-01T00-00-00-000Z:2026-01-31T00-00-00-000Z`,
            singletonSeconds: GARMIN_BACKFILL_SINGLETON_SECONDS,
            retryLimit: 3
          },
          {
            name: GARMIN_BACKFILL_JOB_NAME,
            windowStart: "2026-01-31T00:00:00.000Z",
            windowEnd: "2026-03-02T00:00:00.000Z",
            idempotencyKey: `garmin-backfill:${callbackBody.connection.id}:2026-01-31T00-00-00-000Z:2026-03-02T00-00-00-000Z`,
            singletonKey: `garmin-backfill:${callbackBody.connection.id}:2026-01-31T00-00-00-000Z:2026-03-02T00-00-00-000Z`,
            singletonSeconds: GARMIN_BACKFILL_SINGLETON_SECONDS,
            retryLimit: 3
          }
        ]
      );

      const connectionRows = await database.sql`
        select id, user_id, source, credential_name, provider_user_id,
               encrypted_refresh_token, scope, revoked_at
        from garmin_oauth_connections
        where user_id = ${userId}
      `;
      assert.equal(connectionRows.length, 1);
      assert.equal(connectionRows[0].source, "garmin");
      assert.equal(connectionRows[0].credential_name, "Garmin official connector");
      assert.equal(connectionRows[0].provider_user_id, "garmin-user-1");
      assert.equal(connectionRows[0].scope, "activity heartrate");
      assert.equal(connectionRows[0].revoked_at, null);
      assert.notEqual(connectionRows[0].encrypted_refresh_token, refreshToken);
      assert.equal(
        connectionRows[0].encrypted_refresh_token.includes(refreshToken),
        false
      );

      const decrypted = await store.decryptRefreshTokenForConnectorJob({
        connectionId: connectionRows[0].id,
        userId
      });
      assert.equal(decrypted, refreshToken);
      const otherUserDecryption = await store.decryptRefreshTokenForConnectorJob({
        connectionId: connectionRows[0].id,
        userId: `other-${userId}`
      });
      assert.equal(otherUserDecryption, null);

      const statusRows = await database.sql`
        select source, credential_id, credential_name, condition, recovery_action
        from integration_statuses
        where user_id = ${userId}
      `;
      assert.deepEqual(Array.from(statusRows), [
        {
          source: "garmin",
          credential_id: connectionRows[0].id,
          credential_name: "Garmin official connector",
          condition: "ok",
          recovery_action: "none"
        }
      ]);

      const disconnectResponse = await app.request(
        "/integrations/garmin/oauth/disconnect",
        {
          method: "POST",
          headers: { authorization: `Bearer ${sessionToken}` }
        }
      );
      assert.equal(disconnectResponse.status, 200);
      const disconnectBody = await disconnectResponse.json();
      assert.equal(disconnectBody.disconnected, true);
      assert.equal(disconnectBody.revoked, true);
      assert.equal(disconnectBody.connectionId, connectionRows[0].id);
      assert.deepEqual(revocations, [refreshToken]);

      const disconnectedRows = await database.sql`
        select encrypted_refresh_token, revoked_at
        from garmin_oauth_connections
        where id = ${connectionRows[0].id}
      `;
      assert.equal(disconnectedRows.length, 1);
      assert.equal(disconnectedRows[0].encrypted_refresh_token, null);
      assert.notEqual(disconnectedRows[0].revoked_at, null);
      assert.equal(
        await store.decryptRefreshTokenForConnectorJob({
          connectionId: connectionRows[0].id,
          userId
        }),
        null
      );

      assert.equal(JSON.stringify(logs).includes(refreshToken), false);
    } finally {
      await database.close();
    }
  }
);

test(
  "Garmin OAuth callback rejects tampered state before token exchange",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `garmin-oauth-tamper-user-${randomUUID()}`;
    const sessionToken = `session-${randomUUID()}`;
    let exchangeCount = 0;
    const app = createApp({
      garminOAuthClient: {
        async exchangeCode() {
          exchangeCount += 1;
          throw new Error("tampered state must not reach token exchange");
        },
        async refreshAccessToken() {
          throw new Error("tampered state must not refresh access tokens");
        },
        async revokeRefreshToken() {
          return { revoked: false };
        }
      },
      garminOAuthConfig: {
        authorizationEndpoint: "https://garmin.example.test/oauth/authorize",
        clientId: "garmin-client-id",
        redirectUri: "https://api.example.test/integrations/garmin/oauth/callback",
        scopes: ["activity"],
        stateTtlSeconds: 600
      },
      garminOAuthStore: createDrizzleGarminOAuthConnectionStore({
        cipher: createGarminOAuthTokenCipher(randomBytes(32)),
        db: database.db
      }),
      integrationStatusStore: createDrizzleIntegrationStatusStore(database.db),
      logger: { info() {}, error() {} },
      syncStore: {
        async verifyBearerToken(token) {
          return token === sessionToken ? { userId } : null;
        }
      }
    });

    try {
      await seedUser(database, userId);
      await seedSession(database, { userId, token: sessionToken });

      const startResponse = await app.request("/integrations/garmin/oauth/start", {
        method: "POST",
        headers: { authorization: `Bearer ${sessionToken}` }
      });
      assert.equal(startResponse.status, 200);
      const startBody = await startResponse.json();
      const state = new URL(startBody.authorizationUrl).searchParams.get("state");
      assert.equal(typeof state, "string");
      // Flip the FIRST character of the state (the leading base64url char of the
      // IV segment). Unlike the trailing char — whose low bits can be base64
      // padding that decodes to identical bytes, occasionally letting AES-GCM
      // still verify — the leading char always carries significant bits, so the
      // tamper deterministically corrupts the decoded IV and the callback must
      // reject it every run.
      const firstStateChar = state.at(0);
      const tamperedState = `${
        firstStateChar === "A" ? "B" : "A"
      }${state.slice(1)}`;
      assert.notEqual(tamperedState, state);

      const callbackResponse = await app.request(
        `/integrations/garmin/oauth/callback?code=garmin-auth-code&state=${encodeURIComponent(
          tamperedState
        )}`
      );

      assert.equal(callbackResponse.status, 400);
      assert.equal(exchangeCount, 0);
      const rows = await database.sql`
        select count(*)::int as count
        from garmin_oauth_connections
        where user_id = ${userId}
      `;
      assert.equal(rows[0].count, 0);
    } finally {
      await database.close();
    }
  }
);

async function seedUser(database, userId) {
  await database.db.insert(schema.user).values({
    id: userId,
    name: "Garmin OAuth Test User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
}

async function seedSession(database, { userId, token }) {
  await database.db.insert(schema.session).values({
    id: `session-${randomUUID()}`,
    userId,
    token,
    expiresAt: new Date("2026-07-25T10:00:00.000Z")
  });
}

function captureLogger(logs) {
  return {
    info(payload, message) {
      logs.push({ level: "info", message, payload });
    },
    error(payload, message) {
      logs.push({ level: "error", message, payload });
    }
  };
}
