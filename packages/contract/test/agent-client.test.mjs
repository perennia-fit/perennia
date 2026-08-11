import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  AGENT_CLIENT_OPERATION_IDS,
  PerenniaAgentClient
} from "../src/agent-client.ts";
import {
  SET_VALIDATION_LIMITS,
  validateAgentSet
} from "../src/agent-validation.ts";
import {
  SET_VALIDATION_LIMITS as SERVER_SET_VALIDATION_LIMITS,
  validateAgentSet as serverValidateAgentSet
} from "../../../apps/server/src/index.ts";

test("generated agent client tracks the committed OpenAPI agent operations", async () => {
  const document = JSON.parse(
    await readFile(new URL("../openapi.json", import.meta.url), "utf8")
  );
  const expectedOperationIds = Object.entries(document.paths)
    .filter(([path]) => path.startsWith("/agent/"))
    .flatMap(([, methods]) =>
      Object.values(methods).map((operation) => operation.operationId)
    )
    .sort();

  assert.deepEqual(AGENT_CLIENT_OPERATION_IDS, expectedOperationIds);
  assert.equal(
    PerenniaAgentClient.openApiSource,
    "packages/contract/openapi.json"
  );
});

test("Protocols write contract exposes UUIDv7 creation guidance and the shared 422 conflict shape", async () => {
  const document = JSON.parse(
    await readFile(new URL("../openapi.json", import.meta.url), "utf8")
  );
  const idSchema = document.components.schemas.AgentProtocolsClientRowId;
  assert.match(idSchema.anyOf[0].pattern, /^\^\[0-9a-fA-F\]/);
  assert.match(idSchema.anyOf[0].description, /UUIDv7/);
  assert.match(idSchema.anyOf[1].description, /Existing legacy row id/);

  for (const path of [
    "/agent/protocols/doses/batch-write",
    "/agent/protocols/compounds/batch-write",
    "/agent/protocols/batch-write"
  ]) {
    assert.ok(document.paths[path].post.responses["422"]);
    assert.equal(document.paths[path].post.responses["409"], undefined);
  }

  const entityResult =
    document.components.schemas.AgentProtocolsEntityBatchWriteResult;
  assert.equal(entityResult.properties.warnings, undefined);
  assert.ok(entityResult.properties.outcome.enum.includes("refused"));
});

test("generated agent client sends bearer-authenticated JSON requests", async () => {
  const calls = [];
  const client = new PerenniaAgentClient({
    baseUrl: "https://api.example.test/base/",
    bearerToken: "prn_agent_secret",
    fetch: async (url, init) => {
      calls.push({ url: url.toString(), init });
      return Response.json({
        accepted: true,
        warnings: [],
        limits: { numericMin: 0 }
      });
    }
  });

  const response = await client.validateAgentSet({
    exercise: { dimensions: ["load"], loadMode: "added" },
    values: { load: { entered: "0", unit: "kilogram" } }
  });

  assert.equal(response.accepted, true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "https://api.example.test/agent/validate-set");
  assert.equal(calls[0].init.method, "POST");
  assert.equal(calls[0].init.headers.authorization, "Bearer prn_agent_secret");
  assert.equal(calls[0].init.headers["content-type"], "application/json");
  assert.deepEqual(JSON.parse(calls[0].init.body), {
    exercise: { dimensions: ["load"], loadMode: "added" },
    values: { load: { entered: "0", unit: "kilogram" } }
  });

  await client.getAgentMonitoringActivity({
    externalActivityId: "activity/with space"
  });

  assert.equal(calls.length, 2);
  assert.equal(
    calls[1].url,
    "https://api.example.test/agent/monitoring/activities/activity%2Fwith%20space"
  );
  assert.equal(calls[1].init.method, "GET");
  assert.equal(calls[1].init.body, undefined);
  assert.equal(calls[1].init.headers["content-type"], undefined);
});

test("contract validation export is the exact module used by the server", () => {
  assert.equal(validateAgentSet, serverValidateAgentSet);
  assert.equal(SET_VALIDATION_LIMITS, SERVER_SET_VALIDATION_LIMITS);
});
