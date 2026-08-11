import assert from "node:assert/strict";
import test from "node:test";

import { createApp, createAgentMcpServer } from "../src/index.ts";

// These tests drive the MCP server over real HTTP (via app.request against the
// Hono app), not the in-process InMemoryTransport used by agent-mcp.test.mjs.
// They exercise the transport-level concerns: the /mcp route existing at all,
// bearer auth populating extra.authInfo.token, and a 401/JSON-RPC error for a
// missing or invalid key ('s MCP transport section).

test("POST /mcp initialize succeeds with a valid bearer key", async () => {
  const app = buildApp();

  const response = await postMcp(app, initializeRequest(), {
    authorization: "Bearer prn_agent_secret"
  });

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.jsonrpc, "2.0");
  assert.equal(body.id, 1);
  assert.equal(body.result.serverInfo.name, "perennia-agent");
});

test("POST /mcp tools/list succeeds with a valid bearer key", async () => {
  const app = buildApp();

  const response = await postMcp(
    app,
    { jsonrpc: "2.0", id: 2, method: "tools/list", params: {} },
    { authorization: "Bearer prn_agent_secret" }
  );

  assert.equal(response.status, 200);
  const body = await response.json();
  const names = body.result.tools.map((tool) => tool.name);
  assert.ok(names.includes("agent_validate_set"));
});

test("POST /mcp tools/call succeeds with a valid bearer key and populates authInfo", async () => {
  const app = buildApp();

  const response = await postMcp(
    app,
    {
      jsonrpc: "2.0",
      id: 3,
      method: "tools/call",
      params: {
        name: "agent_validate_set",
        arguments: {
          request: {
            exercise: { dimensions: ["load", "reps"], loadMode: "added" },
            values: {
              load: { entered: "100", unit: "kilogram" },
              reps: { entered: "5", unit: "repetition" }
            }
          }
        }
      }
    },
    { authorization: "Bearer prn_agent_secret" }
  );

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.result.isError, undefined);
  const structured = body.result.structuredContent;
  assert.equal(structured.accepted, true);
});

test("POST /mcp tools/call rejects a tool call with no Authorization header", async () => {
  const app = buildApp();

  const response = await postMcp(app, {
    jsonrpc: "2.0",
    id: 4,
    method: "tools/call",
    params: {
      name: "agent_validate_set",
      arguments: {
        request: {
          exercise: { dimensions: ["load", "reps"], loadMode: "added" },
          values: {
            load: { entered: "100", unit: "kilogram" }
          }
        }
      }
    }
  });

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.result.isError, true);
  assert.equal(body.result.structuredContent.code, "agent_unauthorized");
});

test("POST /mcp tools/call rejects a tool call with an invalid bearer key", async () => {
  const app = buildApp();

  const response = await postMcp(
    app,
    {
      jsonrpc: "2.0",
      id: 5,
      method: "tools/call",
      params: {
        name: "agent_validate_set",
        arguments: {
          request: {
            exercise: { dimensions: ["load", "reps"], loadMode: "added" },
            values: {
              load: { entered: "100", unit: "kilogram" }
            }
          }
        }
      }
    },
    { authorization: "Bearer not-a-real-key" }
  );

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.result.isError, true);
  assert.equal(body.result.structuredContent.code, "agent_unauthorized");
});

test("POST /mcp returns 503 when the MCP server is not configured", async () => {
  const app = createApp({ logger: { info() {}, error() {} } });

  const response = await postMcp(app, initializeRequest(), {
    authorization: "Bearer prn_agent_secret"
  });

  assert.equal(response.status, 503);
  const body = await response.json();
  assert.equal(body.code, "agent_mcp_unavailable");
});

function buildApp() {
  const agentApiKeyStore = {
    async authenticateAgentApiKey(secret) {
      if (secret !== "prn_agent_secret") {
        return null;
      }
      return { userId: "user-1", keyId: "agent-key-1", keyName: "Garage coach" };
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

  return createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore,
    createMcpServer: () =>
      createAgentMcpServer({
        agentApiKeyStore,
        logger: { info() {}, error() {} }
      })
  });
}

function initializeRequest() {
  return {
    jsonrpc: "2.0",
    id: 1,
    method: "initialize",
    params: {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: { name: "agent-mcp-http-test", version: "0.0.0" }
    }
  };
}

function postMcp(app, body, headers = {}) {
  return app.request("/mcp", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      accept: "application/json, text/event-stream",
      ...headers
    },
    body: JSON.stringify(body)
  });
}
