import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  AGENT_MCP_EXCLUDED_OPERATION_IDS,
  AGENT_MCP_TOOL_NAMES,
  AGENT_SKILL_SESSION_AUTHENTICATED_OPERATION_IDS,
  buildAgentMcpToolTable,
  buildAgentSkillCommandTable,
  deriveAgentKeyOperations
} from "../src/agent-skill-reference.ts";

async function loadOpenApiDocument() {
  const raw = await readFile(new URL("../openapi.json", import.meta.url), "utf8");
  return JSON.parse(raw);
}

test("deriveAgentKeyOperations excludes session-authenticated Agent API Key management routes", async () => {
  const document = await loadOpenApiDocument();
  const operations = deriveAgentKeyOperations(document);

  const operationIds = operations.map((operation) => operation.operationId);
  for (const excludedId of AGENT_SKILL_SESSION_AUTHENTICATED_OPERATION_IDS) {
    assert.ok(
      !operationIds.includes(excludedId),
      `${excludedId} is session-authenticated and must not be a code-mode skill command`
    );
  }

  // Sanity: the excluded set is exactly the three Agent API Key CRUD ops.
  assert.deepEqual(
    [...AGENT_SKILL_SESSION_AUTHENTICATED_OPERATION_IDS].sort(),
    ["createAgentApiKey", "listAgentApiKeys", "revokeAgentApiKey"]
  );

  // Every remaining /agent/* path is present, keyed by operationId.
  const allAgentOperationIds = Object.entries(document.paths)
    .filter(([path]) => path.startsWith("/agent/"))
    .flatMap(([, methods]) => Object.values(methods).map((op) => op.operationId));
  const expected = allAgentOperationIds
    .filter((id) => !AGENT_SKILL_SESSION_AUTHENTICATED_OPERATION_IDS.has(id))
    .sort();

  assert.deepEqual(operationIds.sort(), expected);
});

test("buildAgentSkillCommandTable maps every agent-key operation to exactly one command name", async () => {
  const document = await loadOpenApiDocument();
  const table = buildAgentSkillCommandTable(document);

  const operations = deriveAgentKeyOperations(document);
  assert.equal(table.length, operations.length);

  const commandNames = table.map((row) => row.command);
  assert.equal(new Set(commandNames).size, commandNames.length, "command names must be unique");

  for (const row of table) {
    assert.equal(typeof row.command, "string");
    assert.match(row.command, /^[a-z][a-z0-9-]*$/);
    assert.match(row.method, /^(GET|POST|DELETE)$/);
    assert.ok(row.path.startsWith("/agent/"));
  }
});

test("buildAgentSkillCommandTable throws when an agent-key operation has no registered command name", () => {
  const fakeDocument = {
    paths: {
      "/agent/new-thing": {
        get: { operationId: "listAgentNewThing", tags: ["Agent Reads"] }
      }
    }
  };

  assert.throws(
    () => buildAgentSkillCommandTable(fakeDocument),
    /listAgentNewThing/
  );
});

test("buildAgentMcpToolTable maps every MCP-eligible agent operation exactly once", async () => {
  const document = await loadOpenApiDocument();
  const commandTable = buildAgentSkillCommandTable(document);
  const mcpTable = buildAgentMcpToolTable(document);
  const expectedOperationIds = commandTable
    .map((row) => row.operationId)
    .filter((operationId) => !AGENT_MCP_EXCLUDED_OPERATION_IDS.has(operationId))
    .sort();

  assert.deepEqual(
    mcpTable.map((row) => row.operationId).sort(),
    expectedOperationIds
  );
  assert.equal(
    new Set(mcpTable.map((row) => row.tool)).size,
    mcpTable.length,
    "MCP tool names must be unique"
  );
  for (const row of mcpTable) {
    assert.match(row.tool, /^agent_[a-z0-9_]+$/);
    assert.equal(row.tool, AGENT_MCP_TOOL_NAMES[row.operationId]);
  }
});

test("buildAgentMcpToolTable rejects stale MCP names", () => {
  const fakeDocument = {
    paths: {
      "/agent/validate-set": {
        post: { operationId: "validateAgentSet", tags: ["Agent Validation"] }
      }
    }
  };

  assert.throws(
    () => buildAgentMcpToolTable(fakeDocument),
    /Agent MCP tool-name registry drift \(stale:/
  );
});

test("Routine selectedDate does not freeze the contract generation date", async () => {
  const document = await loadOpenApiDocument();
  const parameters = document.paths["/agent/routines/{routineId}"].get.parameters;
  const selectedDate = parameters.find(
    (parameter) => parameter.in === "query" && parameter.name === "selectedDate"
  );

  assert.ok(selectedDate, "expected the optional selectedDate query parameter");
  assert.equal(
    "default" in selectedDate.schema,
    false,
    "the server resolves today's date at read time; OpenAPI must not commit a calendar date"
  );
});
