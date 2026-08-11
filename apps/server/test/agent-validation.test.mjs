import assert from "node:assert/strict";
import test from "node:test";

import { createApp } from "../src/index.ts";

test("agent set validation accepts clean values for authenticated agents", async () => {
  const app = createAgentValidationApp();

  const response = await postValidateSet(app, {
    exercise: {"dimensions": ["load"], "loadMode": "added"},
    values: {"load": {"entered": "0", "unit": "kilogram"}},
    rpe: "0",
    side: "right"
  });

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.accepted, true);
  assert.deepEqual(body.warnings, []);
  assert.equal(body.limits.loadMaxKilograms, 1000);
  assert.equal(body.limits.repsMax, 10000);
});

test("agent set validation returns soft warnings while accepting the set", async () => {
  const app = createAgentValidationApp();

  const response = await postValidateSet(app, {
    exercise: {"dimensions": ["duration", "distance"], "loadMode": "added"},
    values: {
      "duration": {"entered": "300", "unit": "second"},
      "distance": {"entered": "5", "unit": "kilometer"}
    }
  });

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.accepted, true);
  assert.deepEqual(
    body.warnings.map((warning) => warning.rule),
    ["implied_speed_improbable"]
  );
  assert.equal(body.warnings[0].field, "values.distance");
});

test("agent set validation hard rejects with field-level errors", async () => {
  const app = createAgentValidationApp();

  const response = await postValidateSet(app, {
    exercise: {"dimensions": ["reps"], "loadMode": "added"},
    values: {"reps": {"entered": "2.5", "unit": "repetition"}},
    side: "center"
  });

  assert.equal(response.status, 422);
  const body = await response.json();
  assert.equal(body.code, "agent_set_validation_failed");
  assert.deepEqual(
    body.errors.map((error) => error.rule),
    ["reps_integer", "side_allowed"]
  );
  assert.deepEqual(body.errors.map((error) => error.field), [
    "values.reps.entered",
    "side"
  ]);
  assert.deepEqual(body.warnings, []);
  assert.equal(body.limits.rpeStep, 0.5);
});

test("agent set validation requires an agent API key store and bearer token", async () => {
  const appWithoutStore = createApp({logger: {info() {}, error() {}}});
  const unavailableResponse = await postValidateSet(appWithoutStore, {
    exercise: {"dimensions": ["load"], "loadMode": "added"},
    values: {"load": {"entered": "0", "unit": "kilogram"}}
  });
  assert.equal(unavailableResponse.status, 503);

  const app = createAgentValidationApp();
  const missingBearerResponse = await app.request("/agent/validate-set", {
    method: "POST",
    headers: {"content-type": "application/json"},
    body: JSON.stringify({
      exercise: {"dimensions": ["load"], "loadMode": "added"},
      values: {"load": {"entered": "0", "unit": "kilogram"}}
    })
  });
  assert.equal(missingBearerResponse.status, 401);

  const invalidBearerResponse = await app.request("/agent/validate-set", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_agent_unknown",
      "content-type": "application/json"
    },
    body: JSON.stringify({
      exercise: {"dimensions": ["load"], "loadMode": "added"},
      values: {"load": {"entered": "0", "unit": "kilogram"}}
    })
  });
  assert.equal(invalidBearerResponse.status, 401);
});

function createAgentValidationApp() {
  return createApp({
    logger: {info() {}, error() {}},
    agentApiKeyStore: {
      async authenticateAgentApiKey(secret) {
        if (secret !== "prn_agent_secret") {
          return null;
        }

        return {
          userId: "user-1",
          keyId: "agent-key-1",
          keyName: "Garage coach"
        };
      },
      async createAgentApiKey() {
        throw new Error("createAgentApiKey should not be called.");
      },
      async listAgentApiKeys() {
        throw new Error("listAgentApiKeys should not be called.");
      },
      async revokeAgentApiKey() {
        throw new Error("revokeAgentApiKey should not be called.");
      },
      async verifySessionBearerToken() {
        throw new Error("verifySessionBearerToken should not be called.");
      }
    }
  });
}

function postValidateSet(app, body) {
  return app.request("/agent/validate-set", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_agent_secret",
      "content-type": "application/json"
    },
    body: JSON.stringify(body)
  });
}
