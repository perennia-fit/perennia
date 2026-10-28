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
import { createAgentMcpServer, createApp } from "../src/index.ts";
import { dayStatuses, planDays } from "../src/protocol-plan.ts";

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

test("the planned-day and Day Status tools answer exactly as their REST reads do", async () => {
  const store = planReadStore();
  const app = createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: authenticatingKeyStore(),
    agentProtocolsStore: store
  });
  const { client, close } = await createMcpClient(
    createAgentMcpServer({
      agentApiKeyStore: authenticatingKeyStore(),
      agentProtocolsStore: store,
      logger: { info() {}, error() {} }
    })
  );
  const today = new Date().toISOString().slice(0, 10);
  const day = (offset) => addDays(today, offset);
  const rest = (path, query) =>
    app.request(`${path}?${new URLSearchParams(query).toString()}`, {
      headers: { authorization: "Bearer prn_agent_secret" }
    });
  const mcp = (name, query) =>
    client.callTool({ name, arguments: { apiKey: "prn_agent_secret", query } });

  try {
    const reads = [
      ["/agent/protocols/planned-days", "agent_list_protocol_planned_days", { fromLocalDate: day(-3), toLocalDate: day(3) }],
      ["/agent/protocols/planned-days", "agent_list_protocol_planned_days", { fromLocalDate: day(-3), toLocalDate: day(0), compoundId: "compound-a", protocolId: "protocol-1" }],
      ["/agent/protocols/day-statuses", "agent_list_protocol_day_statuses", { fromLocalDate: day(-3), toLocalDate: day(0), today }],
      ["/agent/protocols/day-statuses", "agent_list_protocol_day_statuses", { fromLocalDate: day(-3), toLocalDate: day(-1), today, detail: "doses", compoundId: "compound-a" }]
    ];
    for (const [path, tool, query] of reads) {
      const restResponse = await rest(path, query);
      assert.equal(restResponse.status, 200, `${path} ${JSON.stringify(query)}`);
      const mcpResponse = await mcp(tool, query);
      assert.equal(mcpResponse.isError, undefined, JSON.stringify(mcpResponse.content));
      assert.deepEqual(mcpResponse.structuredContent, await restResponse.json());
    }

    // Each refusal is the same refusal on both surfaces.
    const refused = [
      ["/agent/protocols/planned-days", "agent_list_protocol_planned_days", { fromLocalDate: day(1), toLocalDate: day(0) }],
      ["/agent/protocols/planned-days", "agent_list_protocol_planned_days", { fromLocalDate: day(-366), toLocalDate: day(0) }],
      ["/agent/protocols/day-statuses", "agent_list_protocol_day_statuses", { fromLocalDate: day(-3), toLocalDate: day(1), today }],
      ["/agent/protocols/day-statuses", "agent_list_protocol_day_statuses", { fromLocalDate: day(-3), toLocalDate: day(3), today: day(3) }]
    ];
    for (const [path, tool, query] of refused) {
      const restResponse = await rest(path, query);
      assert.equal(restResponse.status, 400, `${path} ${JSON.stringify(query)}`);
      const mcpResponse = await mcp(tool, query);
      assert.equal(mcpResponse.isError, true);
      assert.deepEqual(mcpResponse.structuredContent, await restResponse.json());
      assert.equal(mcpResponse.structuredContent.code, "agent_protocol_days_invalid_request");
    }

    // A Day Status read without today is malformed on both.
    const noToday = { fromLocalDate: day(-3), toLocalDate: day(-1) };
    assert.equal((await rest("/agent/protocols/day-statuses", noToday)).status, 400);
    assert.equal((await mcp("agent_list_protocol_day_statuses", noToday)).isError, true);
    assert.equal(store.calls, reads.length * 2);
  } finally {
    await close();
  }
});

/**
 * A Protocols store whose two plan reads answer through the shared core over
 * one fixed plan, honoring the filters, so both surfaces have a real answer to
 * agree on.
 */
function planReadStore() {
  const today = new Date().toISOString().slice(0, 10);
  const protocols = [
    {
      protocolId: "protocol-1",
      startLocalDate: addDays(today, -10),
      remindersEnabled: false,
      members: [
        {
          memberId: "member-1",
          compoundId: "compound-a",
          versions: [
            {
              id: "version-1",
              effectiveFrom: addDays(today, -10),
              rule: { v: 1, kind: "timed", days: { kind: "daily" }, times: ["09:00", "21:00"] },
              amountValue: 5,
              amountEntered: "5",
              unit: "milligram",
              route: "oral"
            }
          ]
        },
        {
          memberId: "member-2",
          compoundId: "compound-b",
          versions: [
            {
              id: "version-2",
              effectiveFrom: addDays(today, -10),
              rule: { v: 1, kind: "as_needed" }
            }
          ]
        }
      ]
    }
  ];
  const doses = [
    { doseId: "dose-1", compoundId: "compound-a", localDate: addDays(today, -1), localTime: "08:55", sequence: 0 }
  ];
  const plan = (query) =>
    planDays(
      protocols.filter((protocol) => query.protocolId === undefined || protocol.protocolId === query.protocolId),
      query.fromLocalDate,
      query.toLocalDate
    ).filter((planDay) => query.compoundId === undefined || planDay.compoundId === query.compoundId);
  const amounts = (amount) => ({
    amountValue: amount.amountValue ?? null,
    amountEntered: amount.amountEntered ?? null,
    unit: amount.unit ?? null,
    route: amount.route ?? null
  });
  const store = {
    calls: 0,
    async listProtocolPlannedDays({ query }) {
      store.calls += 1;
      return {
        fromLocalDate: query.fromLocalDate,
        toLocalDate: query.toLocalDate,
        plannedDays: plan(query).map((planDay) => ({
          ...planDay,
          planned: planDay.planned.map((planned) => ({ localTime: planned.localTime, ...amounts(planned) }))
        }))
      };
    },
    async listProtocolDayStatuses({ query }) {
      store.calls += 1;
      return {
        fromLocalDate: query.fromLocalDate,
        toLocalDate: query.toLocalDate,
        today: query.today,
        detail: query.detail,
        dayStatuses: dayStatuses(plan(query), doses, query.today).map(({ fills, ...summary }) =>
          query.detail === "doses"
            ? {
                ...summary,
                fills: fills.map((fill) => ({
                  slot: fill.slot,
                  protocolId: fill.protocolId,
                  plannedLocalTime: fill.plannedLocalTime,
                  ...amounts(fill),
                  doseId: fill.doseId
                }))
              }
            : summary
        )
      };
    }
  };
  return store;
}

function authenticatingKeyStore() {
  return {
    async authenticateAgentApiKey(secret) {
      return secret === "prn_agent_secret"
        ? { userId: "user-1", keyId: "agent-key-1", keyName: "Parity" }
        : null;
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
  };
}

function addDays(localDate, days) {
  const date = new Date(`${localDate}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

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
      async listProtocolPlannedDays() {
        throw new Error("not used");
      },
      async listProtocolDayStatuses() {
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
