import assert from "node:assert/strict";
import test from "node:test";

import { DrizzleQueryError } from "drizzle-orm";

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

test("privacy logger strips the Protocol plan values of a logged Agent Protocol write and Schedule write", () => {
  const logEvents = [];
  const logger = createPrivacyLogger({
    info(payload, message) {
      logEvents.push({ payload, message });
    }
  });

  // A logged Agent Protocol batch write, spread as the request body arrives,
  // and a logged Schedule Version write on its own.
  logger.info(
    {
      userId: "user-1",
      path: "/agent/protocols/batch-write",
      idempotencyKey: "plan-1",
      today: "2026-10-27",
      protocols: [
        {
          id: "protocol-1",
          name: "Skin",
          startLocalDate: "2026-09-01",
          endLocalDate: "2026-12-31",
          period: {
            v: 1,
            cycle: { on_days: 60, off_days: 30, anchor: "2026-09-02", anchor_is_default: false },
            pauses: [{ from: "2026-10-10", to: "2026-10-16" }]
          },
          remindersEnabled: true
        }
      ]
    },
    "synthetic Agent Protocol write"
  );
  logger.info(
    {
      userId: "user-1",
      schedule: {
        effective_from: "2026-10-19",
        rule: {
          v: 1,
          kind: "timed",
          days: { kind: "weekdays", weekdays: [1, 3, 5] },
          times: ["07:00"]
        },
        dose_amount_entered: "0.1"
      }
    },
    "synthetic Schedule write"
  );

  assert.equal(logEvents.length, 2);
  for (const event of logEvents) {
    assert.equal(event.payload.userId, "user-1");
    const serialized = JSON.stringify(event.payload);
    // Each key is gone or filtered, never carried with its value.
    for (const key of ["period", "rule", "startLocalDate", "endLocalDate", "today"]) {
      assert.doesNotMatch(serialized, new RegExp(`"${key}":(?!"\\[Filtered\\]")`), key);
    }
    for (const value of [
      "2026-09-01",
      "2026-12-31",
      "2026-09-02",
      "2026-10-10",
      "2026-10-19",
      "2026-10-27",
      "07:00",
      "weekdays",
      "Skin"
    ]) {
      assert.doesNotMatch(serialized, new RegExp(value), value);
    }
  }
});

test("privacy logger strips the plan values of a logged planned-day or Day Status read", () => {
  const logEvents = [];
  const logger = createPrivacyLogger({
    info(payload, message) {
      logEvents.push({ payload, message });
    }
  });

  // A logged Day Status read: its query spread as it arrives, and its response.
  logger.info(
    {
      userId: "user-1",
      path: "/agent/protocols/day-statuses",
      fromLocalDate: "2026-09-01",
      toLocalDate: "2026-10-27",
      today: "2026-10-27",
      compoundId: "compound-ghk",
      protocolId: "protocol-skin",
      detail: "doses",
      dayStatuses: [
        {
          compoundId: "compound-ghk",
          localDate: "2026-10-20",
          status: "partly_logged",
          plannedCount: 2,
          loggedCount: 1,
          extraCount: 0,
          fills: [{ slot: 0, plannedLocalTime: "21:00", amountEntered: "0.1", doseId: "dose-1" }]
        }
      ]
    },
    "synthetic Day Status read"
  );
  // A logged planned-day read's response.
  logger.info(
    {
      userId: "user-1",
      path: "/agent/protocols/planned-days",
      plannedDays: [
        {
          protocolId: "protocol-skin",
          compoundId: "compound-ghk",
          localDate: "2026-11-02",
          state: "off_cycle",
          planned: [{ localTime: "06:45", amountEntered: "0.2", route: "subcutaneous" }]
        }
      ]
    },
    "synthetic planned-day read"
  );

  assert.equal(logEvents.length, 2);
  for (const event of logEvents) {
    assert.equal(event.payload.userId, "user-1");
    const serialized = JSON.stringify(event.payload);
    for (const key of ["fromLocalDate", "toLocalDate", "today", "dayStatuses", "plannedDays"]) {
      assert.doesNotMatch(serialized, new RegExp(`"${key}":(?!"\\[Filtered\\]")`), key);
    }
    for (const value of [
      "2026-09-01",
      "2026-10-27",
      "2026-10-20",
      "2026-11-02",
      "compound-ghk",
      "protocol-skin",
      "partly_logged",
      "off_cycle",
      "21:00",
      "06:45",
      "subcutaneous",
      "dose-1"
    ]) {
      assert.doesNotMatch(serialized, new RegExp(value), value);
    }
  }
});

test("privacy logger strips the Protocol ids of a logged Protocol delete", () => {
  const logEvents = [];
  const logger = createPrivacyLogger({
    info(payload, message) {
      logEvents.push({ payload, message });
    }
  });

  // A logged delete request, its body spread as it arrives (D8).
  logger.info(
    {
      userId: "user-1",
      path: "/agent/protocols/delete",
      idempotencyKey: "delete-1",
      protocolIds: ["protocol-skin", "protocol-sleep"]
    },
    "synthetic Protocol delete"
  );

  assert.equal(logEvents.length, 1);
  const serialized = JSON.stringify(logEvents[0].payload);
  assert.equal(logEvents[0].payload.userId, "user-1");
  assert.doesNotMatch(serialized, /"protocolIds":(?!"\[Filtered\]")/);
  for (const value of ["protocol-skin", "protocol-sleep"]) {
    assert.doesNotMatch(serialized, new RegExp(value), value);
  }
});

test("privacy logger strips the Skips of a logged Skip write", () => {
  const logEvents = [];
  const logger = createPrivacyLogger({
    info(payload, message) {
      logEvents.push({ payload, message });
    }
  });

  // A logged Skip write request, its body spread as it arrives (D8). The
  // items' `localDate` and `plannedLocalTime` are not denied keys on their
  // own, so only the `skips` parent key keeps them out of the log.
  logger.info(
    {
      userId: "user-1",
      path: "/agent/protocols/skips/batch-write",
      idempotencyKey: "skip-1",
      skips: [
        {
          id: "skip-a",
          protocolId: "protocol-skin",
          compoundId: "compound-ghk",
          localDate: "2026-10-31",
          plannedLocalTime: "21:17"
        }
      ]
    },
    "synthetic Skip write"
  );

  assert.equal(logEvents.length, 1);
  const serialized = JSON.stringify(logEvents[0].payload);
  assert.equal(logEvents[0].payload.userId, "user-1");
  assert.doesNotMatch(serialized, /"skips":(?!"\[Filtered\]")/);
  for (const value of [
    "skip-a",
    "protocol-skin",
    "compound-ghk",
    "2026-10-31",
    "21:17"
  ]) {
    assert.doesNotMatch(serialized, new RegExp(value), value);
  }
});

test("privacy logger strips the User Profile values of a logged agent write and read", () => {
  const logEvents = [];
  const logger = createPrivacyLogger({
    info(payload, message) {
      logEvents.push({ payload, message });
    }
  });

  // A logged write body spread as it arrives, then a read section: none of these
  // field names is denied on its own, so `sections` and `values` keep them out.
  logger.info(
    {
      userId: "user-1",
      path: "/agent/profile/batch-write",
      idempotencyKey: "profile-1",
      sections: {
        aboutYou: { birthYear: 1984 },
        healthLimitations: { text: "Left knee surgery", none: false },
        generalNotes: { text: "Private note" }
      }
    },
    "synthetic User Profile write"
  );
  logger.info(
    {
      userId: "user-1",
      path: "/agent/profile",
      healthLimitations: { values: { text: "Right wrist" } }
    },
    "synthetic User Profile read"
  );

  assert.equal(logEvents.length, 2);
  const serialized = JSON.stringify(logEvents.map((event) => event.payload));
  assert.equal(logEvents[0].payload.userId, "user-1");
  assert.equal(logEvents[0].payload.path, "/agent/profile/batch-write");
  assert.doesNotMatch(serialized, /"sections":(?!"\[Filtered\]")/);
  assert.doesNotMatch(serialized, /"values":(?!"\[Filtered\]")/);
  for (const value of ["1984", "Left knee", "Private note", "Right wrist"]) {
    assert.doesNotMatch(serialized, new RegExp(value), value);
  }
});

function profileQueryError() {
  const cause = Object.assign(new Error("Key (text)=(Left knee) is invalid"), {
    code: "23514",
    constraint_name: "user_profile_sections_check",
    detail: "Failing row contains (Left knee)",
    where: "JSON data, line 1: Left knee"
  });
  return new DrizzleQueryError(
    'insert into "user_profile_sections" values ($1)',
    [
      JSON.stringify({
        section: "health_limitations",
        values: { text: "Left knee" }
      })
    ],
    cause
  );
}

function assertNoQueryData(serialized) {
  for (const value of ["Left knee", "Failed query", "health_limitations", "insert into"]) {
    assert.doesNotMatch(serialized, new RegExp(value), value);
  }
}

test("privacy logger keeps only codes of a failed query, never its params", () => {
  const logEvents = [];
  const logger = createPrivacyLogger({
    info() {},
    error(payload, message) {
      logEvents.push({ payload, message });
    }
  });

  logger.error({ userId: "user-1", error: profileQueryError() }, "request failed");

  assert.deepEqual(logEvents[0].payload.error, {
    type: "DrizzleQueryError",
    message: "Database query failed.",
    cause: {
      type: "Error",
      code: "23514",
      constraint: "user_profile_sections_check"
    }
  });
  assertNoQueryData(JSON.stringify(logEvents[0].payload));
});

test("a postgres.js error is treated as a failed query, with its hidden query", () => {
  const error = Object.assign(new Error("Failing row contains (Left knee)"), {
    code: "23514",
    constraint_name: "user_profile_sections_check"
  });
  Object.defineProperty(error, "query", { value: "insert into x", enumerable: false });

  const serialized = scrubObservabilityData({ error }).error;
  assert.equal(serialized.message, "Database query failed.");
  assert.equal(serialized.code, "23514");
  assert.equal(serialized.constraint, "user_profile_sections_check");
  assertNoQueryData(JSON.stringify(serialized));
});

test("a crash report of a failed query carries no query data", () => {
  const sdk = createFakeSentrySdk();
  const reporter = createSentryCrashReporterFromEnv(
    {
      SERVER_CRASH_REPORTING_ENABLED: "true",
      SERVER_CRASH_REPORTING_DSN: "https://public@example.com/1"
    },
    { sdk }
  );

  reporter.captureException(profileQueryError(), {
    correlationId: "corr-1",
    method: "POST",
    path: "/agent/profile/batch-write"
  });

  const { error } = sdk.capturedEvents[0].extra;
  assert.equal(error.type, "DrizzleQueryError");
  assert.equal(error.cause.code, "23514");
  assertNoQueryData(JSON.stringify(error));
});

test("Sentry beforeSend keeps an event's exceptions, without their messages", () => {
  const sdk = createFakeSentrySdk();
  createSentryCrashReporterFromEnv(
    {
      SERVER_CRASH_REPORTING_ENABLED: "true",
      SERVER_CRASH_REPORTING_DSN: "https://public@example.com/1"
    },
    { sdk }
  );

  const frames = [{ filename: "app.js", lineno: 3 }];
  const event = sdk.initCalls[0].beforeSend({
    exception: {
      values: [
        {
          type: "DrizzleQueryError",
          value: "Failed query: params: Left knee",
          stacktrace: { frames }
        }
      ]
    },
    extra: { values: { text: "Right wrist" } }
  });

  assert.deepEqual(event.exception.values, [
    {
      type: "DrizzleQueryError",
      value: "[Filtered]",
      stacktrace: { frames }
    }
  ]);
  assert.equal(event.extra.values, "[Filtered]");

  // The exemption is the event's own path: `values` stays filtered elsewhere.
  assert.equal(
    scrubObservabilityData({ exception: { values: ["Left knee"] } }).exception.values,
    "[Filtered]"
  );
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
  assert.deepEqual(
    sdk.initCalls[0].integrations.map((integration) => integration.name),
    ["Http"]
  );
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
      // The SDK parses the Cookie header into this field as well.
      cookies: { "better-auth.session_token": "session-cookie-secret" },
      // The SDK sends the raw body as a string, which filtering by key can't reach.
      data: JSON.stringify({
        sections: { healthLimitations: { text: "HIVSECRET meds" } },
        note: "private request note"
      })
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
  assert.doesNotMatch(serialized, /session-cookie-secret/);
  assert.doesNotMatch(serialized, /private request note/);
  assert.doesNotMatch(serialized, /HIVSECRET/);
  assert.equal("data" in event.request, false);
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
