import assert from "node:assert/strict";
import test from "node:test";

import { serve } from "@hono/node-server";
import * as Sentry from "@sentry/node";

import { createApp } from "../src/app.ts";
import { createSentryCrashReporterFromEnv } from "../src/observability.ts";

// The real SDK, with only its transport stubbed, because the fake one in
// observability.test.mjs has no request-data integration. Sentry.init is global,
// so this lives in its own file and process.
//
// The release is pinned as production pins it. With one, the SDK also sends
// session envelopes, and without one it takes a release from the environment
// (GITHUB_SHA on hosted CI), so leaving it out made this test differ by machine.
test("a crash on a User Profile write sends Sentry no request body", async () => {
  // Built at runtime, so source context lines copied into an event can't match.
  const secret = ["HIV", "SECRET"].join("");
  const sessionToken = ["SESSION", "COOKIE", "SECRET"].join("");
  const preScrubRequests = [];
  const sentEnvelopes = [];
  const crashReporter = createSentryCrashReporterFromEnv(
    {
      SERVER_CRASH_REPORTING_ENABLED: "true",
      SERVER_CRASH_REPORTING_DSN: "https://public@example.com/1"
    },
    {
      release: "0.0.0-test",
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
          cookie: `better-auth.session_token=${sessionToken}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          idempotencyKey: "profile-crash",
          sections: { healthLimitations: { text: `${secret} meds` } }
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
  // The SDK did read the session cookie, so its absence below is the scrubber's work.
  assert.match(JSON.stringify(preScrubRequests[0]), new RegExp(sessionToken));

  const eventEnvelopes = sentEnvelopes.filter(([, items]) =>
    items.some(([header]) => header.type === "event")
  );
  assert.equal(eventEnvelopes.length, 1);
  assert.match(JSON.stringify(eventEnvelopes[0]), /forced store failure|\[Filtered\]/);

  // Every envelope, not only the event: a body must not leave by any of them.
  const sent = JSON.stringify(sentEnvelopes);
  assert.ok(!sent.includes(secret));
  assert.ok(!sent.includes(sessionToken));
  assert.doesNotMatch(sent, /healthLimitations/);
});
