import assert from "node:assert/strict";
import test from "node:test";

import { createApp } from "../src/index.ts";
import { LAB_TEST_CATALOGUE } from "../src/data/lab-test-catalogue.generated.ts";

test("agent Lab Tests returns every catalogue entry in order, with every listed field", async () => {
  const app = createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore("user-1")
  });

  const response = await app.request("/agent/lab-tests", {
    headers: { authorization: "Bearer prn_agent_secret" }
  });
  assert.equal(response.status, 200);
  const body = await response.json();

  assert.deepEqual(Object.keys(body), ["labTests"]);
  assert.ok(LAB_TEST_CATALOGUE.length > 0);
  // The generated entry minus `foldedUnits`, in catalogue order.
  const expected = LAB_TEST_CATALOGUE.map((entry) => {
    const { foldedUnits: _foldedUnits, ...listed } = entry;
    return listed;
  });
  assert.deepEqual(body.labTests, JSON.parse(JSON.stringify(expected)));

  for (const labTest of body.labTests) {
    assert.deepEqual(Object.keys(labTest).sort(), [
      "defaultRanges",
      "hardBounds",
      "key",
      "name",
      "panel",
      "plausibleBounds",
      "printedRangeKind",
      "unit",
      "unitAliases",
      "variants"
    ]);
    assert.equal("foldedUnits" in labTest, false);
  }
});

test("agent Lab Tests answers 401 without a valid agent key", async () => {
  const app = createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore("user-1")
  });

  const missing = await app.request("/agent/lab-tests");
  assert.equal(missing.status, 401);
  assert.equal((await missing.json()).code, "agent_unauthorized");

  const wrong = await app.request("/agent/lab-tests", {
    headers: { authorization: "Bearer prn_agent_wrong" }
  });
  assert.equal(wrong.status, 401);
  assert.equal((await wrong.json()).code, "agent_unauthorized");
});

test("agent Lab Tests without an agent key store answers 503", async () => {
  const app = createApp({ logger: { info() {}, error() {} } });

  const response = await app.request("/agent/lab-tests", {
    headers: { authorization: "Bearer prn_agent_secret" }
  });
  assert.equal(response.status, 503);
  assert.equal((await response.json()).code, "agent_api_keys_unavailable");
});

function createAgentKeyStore(userId) {
  return {
    async authenticateAgentApiKey(secret) {
      if (secret !== "prn_agent_secret") {
        return null;
      }
      return { userId, keyId: "agent-lab-tests-key-1", keyName: "Lab coach" };
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
  };
}
