import assert from "node:assert/strict";
import test from "node:test";

import { createApp } from "../src/app.ts";
import {
  createPrivacyLogger,
  createSentryCrashReporterFromEnv,
  scrubObservabilityData
} from "../src/observability.ts";

test("privacy logger strips training data, comments, and PII beyond user id", () => {
  const logEvents = [];
  const logger = createPrivacyLogger({
    info(payload, message) {
      logEvents.push({ payload, message });
    }
  });

  logger.info(
    {
      user: {
        id: "user-1",
        email: "lifter@example.com",
        name: "Lifter Name"
      },
      userId: "user-1",
      workout: { id: "workout-1", comment: "knee felt weird" },
      sets: [{ exerciseName: "Back Squat", reps: 5 }],
      comment: "private set note",
      authorization: "Bearer secret-token"
    },
    "synthetic log"
  );

  assert.equal(logEvents.length, 1);
  assert.deepEqual(logEvents[0].payload.user, { id: "user-1" });
  assert.equal(logEvents[0].payload.userId, "user-1");

  const serialized = JSON.stringify(logEvents[0].payload);
  assert.doesNotMatch(serialized, /lifter@example\.com/);
  assert.doesNotMatch(serialized, /Lifter Name/);
  assert.doesNotMatch(serialized, /Back Squat/);
  assert.doesNotMatch(serialized, /knee felt weird/);
  assert.doesNotMatch(serialized, /private set note/);
  assert.doesNotMatch(serialized, /secret-token/);
});

test("privacy logger strips Protocols values on the new agent paths (PROTOCOLS.md §8)", () => {
  const logEvents = [];
  const logger = createPrivacyLogger({
    info(payload, message) {
      logEvents.push({ payload, message });
    }
  });

  logger.info(
    {
      userId: "user-1",
      path: "/agent/protocols/doses/batch-write",
      // Every Protocols value a Dose/Compound/Protocol write could surface.
      compoundName: "Testosterone Enanthate",
      amount: "250",
      amountEntered: "250",
      route: "intramuscular",
      strength: { value: 250, massUnit: "milligram", perUnit: "milliliter" },
      protocolName: "Off-season blast",
      dose: { compound_name: "Melatonin", amount_value: 3, route: "oral" },
      compounds: [{ name: "Semaglutide", default_route: "subcutaneous" }],
      schedule: { frequency: "onceWeekly", dose_unit: "milligram" }
    },
    "synthetic protocols log"
  );

  assert.equal(logEvents.length, 1);
  // The userId and (route-templated) path survive for debuggability.
  assert.equal(logEvents[0].payload.userId, "user-1");

  const serialized = JSON.stringify(logEvents[0].payload);
  assert.doesNotMatch(serialized, /Testosterone Enanthate/);
  assert.doesNotMatch(serialized, /Off-season blast/);
  assert.doesNotMatch(serialized, /Melatonin/);
  assert.doesNotMatch(serialized, /Semaglutide/);
  assert.doesNotMatch(serialized, /intramuscular/);
  assert.doesNotMatch(serialized, /subcutaneous/);
  assert.doesNotMatch(serialized, /onceWeekly/);
  // The amount magnitude must not leak either.
  assert.doesNotMatch(serialized, /250/);
});

test("Sentry crash reporting is opt-in and requires a DSN", () => {
  const sdk = createFakeSentrySdk();

  assert.equal(createSentryCrashReporterFromEnv({}, { sdk }), undefined);
  assert.equal(
    createSentryCrashReporterFromEnv(
      {
        SERVER_CRASH_REPORTING_DSN: "https://public@example.com/1"
      },
      { sdk }
    ),
    undefined
  );
  assert.equal(
    createSentryCrashReporterFromEnv(
      {
        SERVER_CRASH_REPORTING_ENABLED: "true"
      },
      { sdk }
    ),
    undefined
  );
  assert.equal(sdk.initCalls.length, 0);

  const reporter = createSentryCrashReporterFromEnv(
    {
      NODE_ENV: "test",
      SERVER_CRASH_REPORTING_ENABLED: "true",
      SERVER_CRASH_REPORTING_DSN: "https://public@example.com/1"
    },
    { release: "0.0.0-test", sdk }
  );

  assert.ok(reporter);
  assert.equal(sdk.initCalls.length, 1);
  assert.equal(sdk.initCalls[0].dsn, "https://public@example.com/1");
  assert.equal(sdk.initCalls[0].enabled, true);
  assert.equal(sdk.initCalls[0].environment, "test");
  assert.equal(sdk.initCalls[0].release, "0.0.0-test");
  assert.equal(sdk.initCalls[0].sendDefaultPii, false);
});

test("Sentry beforeSend scrubs event payloads structurally", () => {
  const sdk = createFakeSentrySdk();
  createSentryCrashReporterFromEnv(
    {
      SERVER_CRASH_REPORTING_ENABLED: "true",
      SERVER_CRASH_REPORTING_DSN: "https://public@example.com/1"
    },
    { sdk }
  );

  const event = sdk.initCalls[0].beforeSend({
    user: {
      id: "user-1",
      email: "lifter@example.com",
      username: "lifter-name"
    },
    extra: {
      payload: {
        sets: [{ exerciseName: "Back Squat", comment: "private note" }]
      },
      bodyMeasurement: {
        weight: "90 kg"
      }
    },
    request: {
      headers: {
        authorization: "Bearer secret-token",
        cookie: "session=secret"
      },
      data: {
        comment: "private request note"
      }
    }
  });

  assert.deepEqual(event.user, { id: "user-1" });
  const serialized = JSON.stringify(event);
  assert.doesNotMatch(serialized, /lifter@example\.com/);
  assert.doesNotMatch(serialized, /lifter-name/);
  assert.doesNotMatch(serialized, /Back Squat/);
  assert.doesNotMatch(serialized, /private note/);
  assert.doesNotMatch(serialized, /90 kg/);
  assert.doesNotMatch(serialized, /secret-token/);
  assert.doesNotMatch(serialized, /private request note/);
});

test("Sentry beforeSend removes automatic request query strings", () => {
  const sdk = createFakeSentrySdk();
  createSentryCrashReporterFromEnv(
    {
      SERVER_CRASH_REPORTING_ENABLED: "true",
      SERVER_CRASH_REPORTING_DSN: "https://public@example.com/1"
    },
    { sdk }
  );

  const event = sdk.initCalls[0].beforeSend({
    request: {
      url: "/agent/analytics/exercises/abc?exerciseQuery=Back+Squat",
      query_string: "exerciseQuery=Back Squat"
    }
  });

  assert.equal(event.request.url, "/agent/analytics/exercises/:exerciseId");
  assert.equal(event.request.query_string, "[Filtered]");
  const serialized = JSON.stringify(event);
  assert.doesNotMatch(serialized, /exerciseQuery/);
  assert.doesNotMatch(serialized, /Back Squat/);
});

test("unhandled request errors produce scrubbed crash events with correlation id", async () => {
  const sdk = createFakeSentrySdk();
  const reporter = createSentryCrashReporterFromEnv(
    {
      SERVER_CRASH_REPORTING_ENABLED: "true",
      SERVER_CRASH_REPORTING_DSN: "https://public@example.com/1"
    },
    { sdk }
  );
  const logEvents = [];
  const app = createApp({
    crashReporter: reporter,
    logger: {
      info(payload, message) {
        logEvents.push({ payload, message });
      },
      error(payload, message) {
        logEvents.push({ payload, message });
      }
    }
  });
  app.get("/forced-error", () => {
    const error = new Error("forced test crash");
    Object.assign(error, {
      payload: {
        workout: { id: "workout-1", comment: "private workout note" },
        sets: [{ exerciseName: "Back Squat", reps: 5 }],
        email: "lifter@example.com"
      }
    });
    throw error;
  });

  const response = await app.request("/forced-error", {
    headers: {
      "x-correlation-id": "corr-forced-error"
    }
  });

  assert.equal(response.status, 500);
  assert.equal(response.headers.get("x-correlation-id"), "corr-forced-error");
  assert.equal(sdk.capturedEvents.length, 1);
  assert.equal(sdk.capturedEvents[0].tags.correlation_id, "corr-forced-error");
  assert.equal(sdk.capturedEvents[0].contexts.request.path, "/forced-error");

  const serializedEvent = JSON.stringify(sdk.capturedEvents[0]);
  assert.doesNotMatch(serializedEvent, /Back Squat/);
  assert.doesNotMatch(serializedEvent, /private workout note/);
  assert.doesNotMatch(serializedEvent, /lifter@example\.com/);

  const requestLog = logEvents.find((event) => event.message === "request completed");
  assert.equal(requestLog.payload.correlationId, "corr-forced-error");
  assert.equal(requestLog.payload.path, "/forced-error");
});

test("scrubObservabilityData redacts known sensitive shapes without dropping user id", () => {
  assert.deepEqual(
    scrubObservabilityData({
      user: {
        id: "user-1",
        email: "lifter@example.com"
      },
      request: {
        path: "/agent/analytics/exercises/user-back-squat",
        url: "/agent/analytics/exercises/user-back-squat?exerciseQuery=Back+Squat",
        query_string: "exerciseQuery=Back Squat",
        headers: {
          authorization: "Bearer secret"
        }
      },
      reps: 5,
      load: "100 kg",
      afterImage: {
        exercise_name: "Back Squat"
      }
    }),
    {
      user: { id: "user-1" },
      request: {
        path: "/agent/analytics/exercises/:exerciseId",
        url: "/agent/analytics/exercises/:exerciseId",
        query_string: "[Filtered]",
        headers: {
          authorization: "[Filtered]"
        }
      },
      reps: "[Filtered]",
      load: "[Filtered]",
      afterImage: "[Filtered]"
    }
  );
});

function createFakeSentrySdk() {
  let initOptions;
  let activeScope;
  const sdk = {
    initCalls: [],
    capturedEvents: [],
    init(options) {
      initOptions = options;
      sdk.initCalls.push(options);
    },
    withScope(callback) {
      const scope = {
        tags: {},
        user: undefined,
        contexts: {},
        extra: {},
        setTag(key, value) {
          scope.tags[key] = value;
        },
        setUser(user) {
          scope.user = user;
        },
        setContext(key, value) {
          scope.contexts[key] = value;
        },
        setExtra(key, value) {
          scope.extra[key] = value;
        }
      };
      activeScope = scope;
      callback(scope);
      activeScope = undefined;
    },
    captureException(error) {
      const event = {
        tags: activeScope?.tags ?? {},
        user: activeScope?.user,
        contexts: activeScope?.contexts ?? {},
        extra: {
          ...(activeScope?.extra ?? {}),
          thrown: serializeError(error)
        }
      };
      sdk.capturedEvents.push(initOptions?.beforeSend?.(event) ?? event);
      return "captured-event-id";
    }
  };

  return sdk;
}

function serializeError(error) {
  if (!(error instanceof Error)) {
    return error;
  }

  return {
    name: error.name,
    message: error.message,
    stack: error.stack,
    ...Object.fromEntries(
      Object.entries(error).map(([key, value]) => [key, value])
    )
  };
}
