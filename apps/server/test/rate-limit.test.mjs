import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  createApp,
  createDrizzleRateLimitBackend,
  createMigratedServerApp
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;
const WINDOW_MS = 60 * 1000;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for rate-limit tests.");
}

test("rate-limit middleware observes denied decisions without gating by default", async () => {
  const decisions = [];
  const app = createApp({
    rateLimitBackend: {
      async recordHit(input) {
        decisions.push(input);
        return {
          allowed: false,
          key: input.key,
          limit: input.limit,
          remaining: 0,
          resetAt: "2026-06-22T18:01:00.000Z",
          retryAfterMs: 1000
        };
      }
    },
    rateLimitPolicy: {
      enforce: false,
      limit: 1,
      windowMs: WINDOW_MS
    },
    logger: { info() {}, error() {} }
  });

  const response = await app.request("/healthz", {
    headers: { "x-forwarded-for": "203.0.113.10" }
  });

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("x-rate-limit-limit"), "1");
  assert.equal(response.headers.get("x-rate-limit-remaining"), "0");
  assert.equal(decisions.length, 1);
  assert.match(decisions[0].key, /^ip:203\.0\.113\.10:GET:\/healthz$/);
});

test("rate-limit middleware can enforce a 429 when configured", async () => {
  const app = createApp({
    rateLimitBackend: {
      async recordHit(input) {
        return {
          allowed: false,
          key: input.key,
          limit: input.limit,
          remaining: 0,
          resetAt: "2026-06-22T18:01:00.000Z",
          retryAfterMs: 1500
        };
      }
    },
    rateLimitPolicy: {
      enforce: true,
      limit: 1,
      windowMs: WINDOW_MS
    },
    logger: { info() {}, error() {} }
  });

  const response = await app.request("/healthz");

  assert.equal(response.status, 429);
  assert.equal(response.headers.get("retry-after"), "2");
  assert.deepEqual(await response.json(), {
    code: "rate_limited",
    message: "Too many requests.",
    limit: 1,
    retryAfterSeconds: 2
  });
});

test(
  "migrated server app records rate-limit windows in observe-only mode",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });

    try {
      const response = await serverApp.app.request("/healthz", {
        headers: { "x-forwarded-for": "198.51.100.20" }
      });
      const rows = await serverApp.database.sql`
        select key, count
        from rate_limit_windows
        where key = 'ip:198.51.100.20:GET:/healthz'
      `;

      assert.equal(response.status, 200);
      assert.equal(rows.length, 1);
      assert.equal(rows[0].count, 1);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "Postgres rate-limit backend counts the sliding-window boundary",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false
    });
    const backend = createDrizzleRateLimitBackend(serverApp.database.db);
    const inclusiveKey = `boundary-inclusive-${randomUUID()}`;
    const expiredKey = `boundary-expired-${randomUUID()}`;
    const base = new Date("2026-06-22T18:00:00.000Z");

    try {
      await backend.recordHit({
        key: inclusiveKey,
        limit: 2,
        windowMs: WINDOW_MS,
        now: base
      });
      await backend.recordHit({
        key: inclusiveKey,
        limit: 2,
        windowMs: WINDOW_MS,
        now: new Date(base.getTime() + 30 * 1000)
      });
      const inclusiveDecision = await backend.recordHit({
        key: inclusiveKey,
        limit: 2,
        windowMs: WINDOW_MS,
        now: new Date(base.getTime() + WINDOW_MS)
      });

      await backend.recordHit({
        key: expiredKey,
        limit: 2,
        windowMs: WINDOW_MS,
        now: base
      });
      await backend.recordHit({
        key: expiredKey,
        limit: 2,
        windowMs: WINDOW_MS,
        now: new Date(base.getTime() + 30 * 1000)
      });
      const expiredDecision = await backend.recordHit({
        key: expiredKey,
        limit: 2,
        windowMs: WINDOW_MS,
        now: new Date(base.getTime() + WINDOW_MS + 1)
      });

      assert.equal(inclusiveDecision.allowed, false);
      assert.equal(inclusiveDecision.remaining, 0);
      assert.equal(inclusiveDecision.totalHits, 3);
      assert.equal(expiredDecision.allowed, true);
      assert.equal(expiredDecision.remaining, 0);
      assert.equal(expiredDecision.totalHits, 2);
    } finally {
      await serverApp.database.close();
    }
  }
);
