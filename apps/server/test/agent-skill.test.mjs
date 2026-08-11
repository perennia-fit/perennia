import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { promisify } from "node:util";
import test from "node:test";

import {
  AGENT_SKILL_SESSION_AUTHENTICATED_OPERATION_IDS,
  buildAgentSkillCommandTable
} from "../../../packages/contract/src/agent-skill-reference.ts";

const execFileAsync = promisify(execFile);

test("Perennia agent skill command map matches the OpenAPI-derived command table (no hand-maintained mapping)", async () => {
  const root = path.resolve(process.cwd(), "..", "..");
  const skillRoot = path.join(root, "agent-skills", "perennia");
  const scriptPath = path.join(skillRoot, "scripts", "prn-agent.mjs");
  const openApiPath = path.join(root, "packages", "contract", "openapi.json");

  const [{ stdout }, openApiRaw] = await Promise.all([
    execFileAsync(process.execPath, [scriptPath, "--commands-json"], {
      cwd: root
    }),
    readFile(openApiPath, "utf8")
  ]);

  const openApiDocument = JSON.parse(openApiRaw);
  const scriptCommands = JSON.parse(stdout).commands;

  // Every agent-key operation (i.e. every /agent/* op except the
  // session-authenticated Agent API Key CRUD trio) must have exactly one
  // prn-agent.mjs command, and the script's declared operationId/method/path
  // must match the committed openapi.json exactly. This is the drift check:
  // a new agent operation with no corresponding command fails here.
  const expectedRows = buildAgentSkillCommandTable(openApiDocument).map((row) => ({
    command: row.command,
    method: row.method,
    operationId: row.operationId,
    path: row.path
  }));

  const scriptRows = Object.entries(scriptCommands)
    .map(([command, definition]) => ({
      command,
      method: definition.method,
      operationId: definition.operationId,
      path: definition.path
    }))
    .sort(compareRows);

  assert.deepEqual(scriptRows, [...expectedRows].sort(compareRows));

  // No orphan commands: every script command's operationId must be a real,
  // non-session-authenticated /agent/* operation in the committed OpenAPI doc.
  const validOperationIds = new Set(expectedRows.map((row) => row.operationId));
  for (const [command, definition] of Object.entries(scriptCommands)) {
    assert.ok(
      validOperationIds.has(definition.operationId),
      `${command} declares operationId ${definition.operationId}, which is not a valid agent-key OpenAPI operation`
    );
  }

  // Sanity: session-authenticated Agent API Key ops are never commands.
  for (const command of Object.values(scriptCommands)) {
    assert.ok(
      !AGENT_SKILL_SESSION_AUTHENTICATED_OPERATION_IDS.has(command.operationId)
    );
  }
});

test("generated api-operations.md Command Map table matches the script's command map", async () => {
  const root = path.resolve(process.cwd(), "..", "..");
  const skillRoot = path.join(root, "agent-skills", "perennia");
  const scriptPath = path.join(skillRoot, "scripts", "prn-agent.mjs");
  const referencePath = path.join(skillRoot, "references", "api-operations.md");

  const [{ stdout }, reference] = await Promise.all([
    execFileAsync(process.execPath, [scriptPath, "--commands-json"], {
      cwd: root
    }),
    readFile(referencePath, "utf8")
  ]);

  const scriptRows = commandRows(JSON.parse(stdout).commands);
  const referenceRows = referenceCommandRows(reference);

  assert.deepEqual(scriptRows, referenceRows);
});

test("Perennia agent skill workflow examples only use registered commands", async () => {
  const root = path.resolve(process.cwd(), "..", "..");
  const skillRoot = path.join(root, "agent-skills", "perennia");
  const scriptPath = path.join(skillRoot, "scripts", "prn-agent.mjs");
  const skillPath = path.join(skillRoot, "SKILL.md");

  const [{ stdout }, skill] = await Promise.all([
    execFileAsync(process.execPath, [scriptPath, "--commands-json"], {
      cwd: root
    }),
    readFile(skillPath, "utf8")
  ]);

  const registeredCommands = new Set(
    Object.keys(JSON.parse(stdout).commands)
  );
  const documentedCommands = Array.from(
    skill.matchAll(/node scripts\/prn-agent\.mjs\s+([a-z0-9-]+)/g),
    (match) => match[1]
  ).filter((command) => !command.startsWith("-"));
  const unknownCommands = documentedCommands.filter(
    (command) => !registeredCommands.has(command)
  );

  assert.deepEqual(
    unknownCommands,
    [],
    `SKILL.md references unregistered command(s): ${unknownCommands.join(", ")}`
  );
});

test("Perennia code-mode portable client reaches method parity with every agent-key operation", async () => {
  const root = path.resolve(process.cwd(), "..", "..");
  const codeScriptPath = path.join(
    root,
    "agent-skills",
    "perennia",
    "scripts",
    "prn-code.mjs"
  );
  const openApiPath = path.join(root, "packages", "contract", "openapi.json");
  const [codeMode, openApiRaw] = await Promise.all([
    import(pathToFileURL(codeScriptPath).href),
    readFile(openApiPath, "utf8")
  ]);

  const expectedOperationIds = buildAgentSkillCommandTable(
    JSON.parse(openApiRaw)
  ).map((row) => row.operationId);

  const portablePrototype = codeMode.PortableOwlAgentClient.prototype;
  const missing = expectedOperationIds.filter(
    (operationId) => typeof portablePrototype[operationId] !== "function"
  );

  assert.deepEqual(
    missing,
    [],
    `PortableOwlAgentClient is missing methods for: ${missing.join(", ")}`
  );
});

test("Perennia code-mode helper prefers generated client and reduces metric readings", async () => {
  const root = path.resolve(process.cwd(), "..", "..");
  const codeScriptPath = path.join(
    root,
    "agent-skills",
    "perennia",
    "scripts",
    "prn-code.mjs"
  );
  const codeMode = await import(pathToFileURL(codeScriptPath).href);

  class FakeGeneratedClient {
    constructor(options) {
      this.options = options;
    }
  }

  const generated = await codeMode.createOwlAgentClientWithSource({
    agentClientModule: {
      PerenniaAgentClient: FakeGeneratedClient
    },
    baseUrl: "https://perennia.example.test",
    bearerToken: "prn_agent_secret"
  });
  assert.equal(generated.source, "generated");
  assert.equal(generated.client.options.bearerToken, "prn_agent_secret");

  const requests = [];
  const portable = await codeMode.createOwlAgentClientWithSource({
    agentClientModule: null,
    baseUrl: "https://perennia.example.test",
    bearerToken: "prn_agent_secret",
    fetch: async (url, init) => {
      requests.push({ url, init });
      return {
        status: 200,
        async text() {
          return JSON.stringify({
            readings: [
              {
                id: "reading-1",
                metricId: "metric-1",
                scalarValue: 90,
                unit: "kilogram",
                atTime: "2026-06-01T07:00:00.000Z"
              },
              {
                id: "reading-2",
                metricId: "metric-1",
                scalarValue: 88,
                unit: "kilogram",
                atTime: "2026-06-02T07:00:00.000Z"
              }
            ],
            fields: ["id", "metricId", "scalarValue", "unit", "atTime"],
            limit: 100,
            nextCursor: null,
            totalMatched: 2
          });
        }
      };
    }
  });

  assert.equal(portable.source, "portable");
  const summary = await codeMode.metricReadingsSummary(portable.client, {
    metricId: "metric-1",
    from: "2026-06-01",
    to: "2026-06-30"
  });

  assert.equal(requests.length, 1);
  const requestUrl = new URL(requests[0].url);
  assert.equal(requestUrl.pathname, "/agent/metrics/readings");
  assert.equal(requestUrl.searchParams.get("metricId"), "metric-1");
  assert.equal(
    requestUrl.searchParams.get("fields"),
    "id,metricId,scalarValue,unit,atTime,windowStartedAt,windowEndedAt"
  );
  assert.equal(requests[0].init.headers.authorization, "Bearer prn_agent_secret");
  assert.deepEqual(summary, {
    count: 2,
    scalarCount: 2,
    unit: "kilogram",
    min: 88,
    max: 90,
    average: 89,
    latest: {
      id: "reading-2",
      metricId: "metric-1",
      at: "2026-06-02T07:00:00.000Z",
      scalarValue: 88,
      unit: "kilogram"
    }
  });
});

test("Perennia code-mode helper reduces an effect-window response to a compact descriptive summary", async () => {
  const root = path.resolve(process.cwd(), "..", "..");
  const codeScriptPath = path.join(
    root,
    "agent-skills",
    "perennia",
    "scripts",
    "prn-code.mjs"
  );
  const codeMode = await import(pathToFileURL(codeScriptPath).href);

  const response = {
    source: { kind: "compound", id: "compound-1", name: "Creatine Monohydrate" },
    metric: { id: "metric-1", key: "hrv", name: "HRV" },
    range: { from: "2026-06-01T00:00:00.000Z", to: "2026-06-30T00:00:00.000Z" },
    window: { beforeHours: 24, afterHours: 24 },
    doses: [
      {
        doseId: "dose-1",
        compoundName: "Creatine Monohydrate",
        amountValue: 5,
        unit: "gram",
        route: "oral",
        tookAt: "2026-06-15T07:00:00.000Z"
      }
    ],
    segments: {
      before: { count: 10, min: 60, max: 70, mean: 65 },
      during: { count: 5, min: 62, max: 68, mean: 64 },
      after: { count: 10, min: 63, max: 72, mean: 67 }
    },
    descriptiveOnly: true
  };

  const summary = codeMode.summarizeEffectWindow(response);

  assert.deepEqual(summary, {
    source: { kind: "compound", id: "compound-1", name: "Creatine Monohydrate" },
    metric: { id: "metric-1", key: "hrv", name: "HRV" },
    from: "2026-06-01T00:00:00.000Z",
    to: "2026-06-30T00:00:00.000Z",
    doseCount: 1,
    before: { count: 10, min: 60, max: 70, mean: 65 },
    during: { count: 5, min: 62, max: 68, mean: 64 },
    after: { count: 10, min: 63, max: 72, mean: 67 },
    meanDelta: { duringVsBefore: -1, afterVsBefore: 2 },
    descriptiveOnly: true
  });
});

test("Perennia code-mode helper reduces a workouts list response to a compact summary", async () => {
  const root = path.resolve(process.cwd(), "..", "..");
  const codeScriptPath = path.join(
    root,
    "agent-skills",
    "perennia",
    "scripts",
    "prn-code.mjs"
  );
  const codeMode = await import(pathToFileURL(codeScriptPath).href);

  const response = {
    workouts: [
      {
        id: "workout-1",
        startedAt: "2026-06-24T05:00:00.000Z",
        endedAt: "2026-06-24T06:00:00.000Z",
        timezone: "Australia/Brisbane",
        comment: null,
        setCount: 12,
        exerciseNames: ["Back Squat", "Bench Press"]
      },
      {
        id: "workout-2",
        startedAt: "2026-06-26T05:00:00.000Z",
        endedAt: null,
        timezone: "Australia/Brisbane",
        comment: "felt strong",
        setCount: 8,
        exerciseNames: ["Deadlift"]
      }
    ],
    fields: ["id", "startedAt", "endedAt", "timezone", "comment", "setCount", "exerciseNames"],
    limit: 50,
    nextCursor: null,
    totalMatched: 2
  };

  const summary = codeMode.summarizeWorkouts(response);

  assert.deepEqual(summary, {
    workoutCount: 2,
    totalMatched: 2,
    totalSets: 20,
    uniqueExerciseNames: ["Back Squat", "Bench Press", "Deadlift"],
    earliestStartedAt: "2026-06-24T05:00:00.000Z",
    latestStartedAt: "2026-06-26T05:00:00.000Z"
  });
});

function commandRows(commands) {
  return Object.entries(commands)
    .map(([command, definition]) => ({
      command,
      method: definition.method,
      path: definition.path
    }))
    .sort(compareRows);
}

function referenceCommandRows(markdown) {
  return markdown
    .split(/\r?\n/)
    .map((line) =>
      /^\| `([^`]+)` \| (GET|POST) \| `([^`]+)` \|$/.exec(line.trim())
    )
    .filter(Boolean)
    .map((match) => ({
      command: match[1],
      method: match[2],
      path: match[3]
    }))
    .sort(compareRows);
}

function compareRows(left, right) {
  return (
    left.command.localeCompare(right.command) ||
    left.method.localeCompare(right.method) ||
    left.path.localeCompare(right.path)
  );
}
