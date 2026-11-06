import assert from "node:assert/strict";
import test from "node:test";

import { serve } from "@hono/node-server";
import * as Sentry from "@sentry/node";

import { createApp } from "../src/app.ts";
import { createSentryCrashReporterFromEnv } from "../src/observability.ts";

// The real SDK, with only its transport stubbed, because the fake one in
// observability.test.mjs has no request-data integration. Sentry.init is global,
// so this lives in its own file and process.
test("a crash on a User Profile write sends Sentry no request body", async () => {
  const preScrubRequests = [];
  const sentEnvelopes = [];
  const crashReporter = createSentryCrashReporterFromEnv(
    {
      SERVER_CRASH_REPORTING_ENABLED: "true",
      SERVER_CRASH_REPORTING_DSN: "https://public@example.com/1"
    },
    {
      sdk: {
        init(options) {
          return Sentry.init({
            ...options,
            beforeSend(event, hint) {
              preScrubRequests.push(event.request);
              return options.beforeSend(event, hint);
            },
            transport: () => ({
              async send(envelope) {
                sentEnvelopes.push(envelope);
                return { statusCode: 200 };
              },
              flush: async () => true
            })
          });
        },
        withScope: Sentry.withScope,
        captureException: Sentry.captureException
      }
    }
  );

  const app = createApp({
    crashReporter,
    logger: { info() {}, error() {} },
    agentApiKeyStore: {
      async authenticateAgentApiKey() {
        return { userId: "user-1", keyId: "key-1", keyName: "Garage coach" };
      }
    },
    agentProfileStore: {
      async batchWrite() {
        throw new Error("forced store failure");
      }
    }
  });

  const server = await new Promise((resolve) => {
    const started = serve({ fetch: app.fetch, port: 0 }, () => resolve(started));
  });
  try {
    const response = await fetch(
      `http://127.0.0.1:${server.address().port}/agent/profile/batch-write`,
      {
        method: "POST",
        headers: {
          authorization: "Bearer prn_agent_secret",
          "content-type": "application/json"
        },
        body: JSON.stringify({
          idempotencyKey: "profile-crash",
          sections: { healthLimitations: { text: "HIVSECRET meds" } }
        })
      }
    );
    assert.equal(response.status, 500);
    await Sentry.flush(2000);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await Sentry.close();
  }

  // The SDK did attach this request to the event, so its missing body means
  // something: the integration never captured it.
  assert.equal(preScrubRequests.length, 1);
  assert.match(preScrubRequests[0].url, /\/agent\/profile\/batch-write$/);
  assert.equal(preScrubRequests[0].data, undefined);

  assert.equal(sentEnvelopes.length, 1);
  const sent = JSON.stringify(sentEnvelopes[0]);
  assert.match(sent, /forced store failure|\[Filtered\]/);
  assert.doesNotMatch(sent, /HIVSECRET/);
  assert.doesNotMatch(sent, /healthLimitations/);
});
