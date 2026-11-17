import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { eq } from "drizzle-orm";

import {
  SESSION_EXPIRES_IN_SECONDS,
  SESSION_UPDATE_AGE_SECONDS,
  verifySessionToken
} from "../src/auth/session.ts";
import {
  createMigratedServerApp,
  schema,
  SYNC_PROTOCOL_VERSION
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;
const DAY_MS = 24 * 60 * 60 * 1000;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for session renewal tests.");
}

test("session lifetime matches Better Auth's defaults", () => {
  assert.equal(SESSION_EXPIRES_IN_SECONDS, 7 * 24 * 60 * 60);
  assert.equal(SESSION_UPDATE_AGE_SECONDS, 24 * 60 * 60);
});

test(
  "a sync pull renews a session last renewed more than a day ago",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createServer();
    try {
      // Signed in six days ago and never renewed: one day from expiry.
      const { sessionToken, sessionId } = await createSession(serverApp, {
        expiresAt: new Date(Date.now() + DAY_MS)
      });
      const before = Date.now();

      const response = await pull(serverApp, sessionToken);

      assert.equal(response.status, 200);
      const expiresAt = await readExpiresAt(serverApp, sessionId);
      assert.ok(
        expiresAt.getTime() >= before + SESSION_EXPIRES_IN_SECONDS * 1000,
        `expected the session to be renewed for a full week, got ${expiresAt.toISOString()}`
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "a session used daily for longer than a week keeps syncing",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createServer();
    try {
      const signedInAt = new Date("2026-11-01T09:00:00.000Z");
      const { sessionToken } = await createSession(serverApp, {
        expiresAt: new Date(
          signedInAt.getTime() + SESSION_EXPIRES_IN_SECONDS * 1000
        )
      });

      for (let day = 1; day <= 14; day += 1) {
        const now = new Date(signedInAt.getTime() + day * DAY_MS);
        assert.notEqual(
          await verifySessionToken(serverApp.database.db, sessionToken, now),
          null,
          `day ${day}`
        );
      }
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "a session renewed within the last day is not written again",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createServer();
    try {
      const expiresAt = new Date(
        Date.now() + SESSION_EXPIRES_IN_SECONDS * 1000 - 60 * 60 * 1000
      );
      const { sessionToken, sessionId } = await createSession(serverApp, {
        expiresAt
      });

      assert.notEqual(
        await verifySessionToken(serverApp.database.db, sessionToken),
        null
      );

      assert.equal(
        (await readExpiresAt(serverApp, sessionId)).getTime(),
        expiresAt.getTime()
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "an expired session is rejected and not revived",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createServer();
    try {
      const expiresAt = new Date(Date.now() - 60 * 1000);
      const { sessionToken, sessionId } = await createSession(serverApp, {
        expiresAt
      });

      const response = await pull(serverApp, sessionToken);

      assert.equal(response.status, 401);
      assert.equal(
        (await readExpiresAt(serverApp, sessionId)).getTime(),
        expiresAt.getTime()
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "an Agent API key request renews the session too",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createServer();
    try {
      const { sessionToken, sessionId } = await createSession(serverApp, {
        expiresAt: new Date(Date.now() + DAY_MS)
      });
      const before = Date.now();

      const response = await serverApp.app.request("/agent/api-keys", {
        headers: { authorization: `Bearer ${sessionToken}` }
      });

      assert.equal(response.status, 200);
      const expiresAt = await readExpiresAt(serverApp, sessionId);
      assert.ok(
        expiresAt.getTime() >= before + SESSION_EXPIRES_IN_SECONDS * 1000
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

function createServer() {
  return createMigratedServerApp({
    databaseUrl,
    logger: { info() {}, error() {} },
    // Auth on, so the Agent API key routes exist alongside sync.
    auth: {
      baseUrl: "http://localhost",
      secret: "test-secret-at-least-thirty-two-characters"
    }
  });
}

async function createSession(serverApp, { expiresAt }) {
  const userId = `user-${randomUUID()}`;
  const sessionId = `session-row-${randomUUID()}`;
  const sessionToken = `session-${randomUUID()}`;

  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: "Session Renewal User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
  await serverApp.database.db.insert(schema.session).values({
    id: sessionId,
    token: sessionToken,
    userId,
    expiresAt
  });

  return { sessionId, sessionToken };
}

function pull(serverApp, sessionToken) {
  return serverApp.app.request("/sync/pull", {
    method: "POST",
    headers: {
      authorization: `Bearer ${sessionToken}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({
      protocolVersion: SYNC_PROTOCOL_VERSION,
      cursor: null,
      limit: 1
    })
  });
}

async function readExpiresAt(serverApp, sessionId) {
  const rows = await serverApp.database.db
    .select({ expiresAt: schema.session.expiresAt })
    .from(schema.session)
    .where(eq(schema.session.id, sessionId));
  return rows[0].expiresAt;
}
