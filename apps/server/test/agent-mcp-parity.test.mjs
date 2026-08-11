import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import test from "node:test";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";

import {
  AGENT_MCP_EXCLUDED_OPERATION_IDS,
  AGENT_SKILL_SESSION_AUTHENTICATED_OPERATION_IDS,
  buildAgentMcpToolTable
} from "../../../packages/contract/src/agent-skill-reference.ts";
import { createAgentMcpServer } from "../src/index.ts";

// Guards MCP/REST tool-parity drift: every agent REST operation in
// the committed OpenAPI contract, except the probe and key-management
// operations (which have no MCP analog — an agent authenticates the MCP
// transport itself, it doesn't manage its own keys or ping a probe through
// it), must have a corresponding registered MCP tool. Adding a new
// agent-surface REST route without updating the shared MCP name registry fails
// this test, preserving the parity ledger's "close the gap together" rule.

const openApiPath = fileURLToPath(
  new URL("../../../packages/contract/openapi.json", import.meta.url)
);
const openApiDocument = JSON.parse(readFileSync(openApiPath, "utf8"));

test("every non-excluded agent REST operation has a mapped MCP tool name", () => {
  const mappedOperationIds = buildAgentMcpToolTable(openApiDocument).map(
    (row) => row.operationId
  );
  const excludedOperationIds = new Set([
    ...AGENT_SKILL_SESSION_AUTHENTICATED_OPERATION_IDS,
    ...AGENT_MCP_EXCLUDED_OPERATION_IDS
  ]);
  const expectedOperationIds = Object.entries(openApiDocument.paths)
    .filter(([path]) => path.startsWith("/agent/"))
    .flatMap(([, methods]) =>
      Object.values(methods).map((operation) => operation.operationId)
    )
    .filter((operationId) => !excludedOperationIds.has(operationId))
    .sort();

  assert.deepEqual(mappedOperationIds.sort(), expectedOperationIds);
});

test("the MCP toolset registers a tool for every mapped agent REST operation", async () => {
  const { client, close } = await createMcpClient(fullyWiredMcpServer());

  try {
    const { tools } = await client.listTools();
    const toolNames = new Set(tools.map((tool) => tool.name));

    const missingTools = buildAgentMcpToolTable(openApiDocument)
      .filter((row) => !toolNames.has(row.tool))
      .map((row) => `${row.operationId} -> ${row.tool}`);

    assert.deepEqual(
      missingTools,
      [],
      "every mapped agent REST operation must have a registered MCP tool"
    );
  } finally {
    await close();
  }
});

function fullyWiredMcpServer() {
  return createAgentMcpServer({
    agentApiKeyStore: {
      async authenticateAgentApiKey() {
        return null;
      },
      async createAgentApiKey() {
        throw new Error("not used");
      },
      async listAgentApiKeys() {
        throw new Error("not used");
      },
      async revokeAgentApiKey() {
        throw new Error("not used");
      },
      async verifySessionBearerToken() {
        throw new Error("not used");
      }
    },
    agentCatalogStore: {
      async resolveExerciseName() {
        throw new Error("not used");
      },
      async listExercises() {
        throw new Error("not used");
      },
      async getExerciseById() {
        throw new Error("not used");
      }
    },
    agentReadStore: {
      async listHistory() {
        throw new Error("not used");
      },
      async readMonitoringActivity() {
        throw new Error("not used");
      },
      async readExerciseSets() {
        throw new Error("not used");
      }
    },
    agentWorkoutBatchWriteStore: {
      async writeWorkoutBatch() {
        throw new Error("not used");
      }
    },
    agentMealBatchWriteStore: {
      async writeMealBatch() {
        throw new Error("not used");
      }
    },
    agentFoodCatalogStore: {
      async listFoods() {
        throw new Error("not used");
      },
      async getFoodById() {
        throw new Error("not used");
      }
    },
    agentFoodBatchWriteStore: {
      async writeFoodBatch() {
        throw new Error("not used");
      }
    },
    agentMetricStore: {
      async listMetrics() {
        throw new Error("not used");
      },
      async listMetricReadings() {
        throw new Error("not used");
      },
      async writeMetricBatch() {
        throw new Error("not used");
      }
    },
    agentNutritionReadStore: {
      async readNutritionDays() {
        throw new Error("not used");
      }
    },
    agentCrossDomainReadStore: {
      async readWorkoutTimings() {
        throw new Error("not used");
      },
      async readCaloriesBurnedReadings() {
        throw new Error("not used");
      }
    },
    agentProtocolsStore: {
      async listCompounds() {
        throw new Error("not used");
      },
      async listProtocols() {
        throw new Error("not used");
      },
      async listDoses() {
        throw new Error("not used");
      },
      async readEffectWindow() {
        throw new Error("not used");
      },
      async writeDoseBatch() {
        throw new Error("not used");
      },
      async writeCompoundBatch() {
        throw new Error("not used");
      },
      async writeProtocolBatch() {
        throw new Error("not used");
      }
    },
    logger: { info() {}, error() {} }
  });
}

async function createMcpClient(server) {
  const client = new Client(
    { name: "agent-mcp-parity-test-client", version: "0.0.0" },
    { capabilities: {} }
  );
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();

  await Promise.all([
    server.connect(serverTransport),
    client.connect(clientTransport)
  ]);

  return {
    client,
    async close() {
      await Promise.all([client.close(), server.close()]);
    }
  };
}
