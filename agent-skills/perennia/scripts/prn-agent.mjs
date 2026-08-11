#!/usr/bin/env node

// Command map — keep in lockstep with
// packages/contract/src/agent-skill-reference.ts's AGENT_SKILL_COMMAND_NAMES.
// apps/server/test/agent-skill.test.mjs fails CI if this table's
// (operationId, method, path) triples ever drift from the committed
// packages/contract/openapi.json. The Agent API Keys operations
// (createAgentApiKey/listAgentApiKeys/revokeAgentApiKey) are intentionally
// absent: they authenticate with a human session bearer token, not an agent
// API key, so they are not a code-mode skill command.
const COMMANDS = {
  probe: { method: "GET", path: "/agent/probe", operationId: "getAgentProtectedProbe" },
  "validate-set": {
    method: "POST",
    path: "/agent/validate-set",
    body: true,
    operationId: "validateAgentSet"
  },
  "validate-dose": {
    method: "POST",
    path: "/agent/validate-dose",
    body: true,
    operationId: "validateAgentDose"
  },
  "list-exercises": {
    method: "GET",
    path: "/agent/exercises",
    operationId: "listAgentExercises"
  },
  "resolve-exercise": {
    method: "GET",
    path: "/agent/exercises/resolve",
    operationId: "resolveAgentExerciseName"
  },
  "log-workout": {
    method: "POST",
    path: "/agent/workouts/batch-write",
    body: true,
    operationId: "batchWriteAgentWorkout"
  },
  "manage-exercise-catalog": {
    method: "POST",
    path: "/agent/exercises/batch-write",
    body: true,
    operationId: "batchWriteAgentExerciseCatalog"
  },
  "list-history-sets": {
    method: "GET",
    path: "/agent/history/sets",
    operationId: "listAgentHistorySets"
  },
  "list-workouts": {
    method: "GET",
    path: "/agent/workouts",
    operationId: "listAgentWorkouts"
  },
  "get-workout": {
    method: "GET",
    path: "/agent/workouts/{workoutId}",
    params: ["workoutId"],
    operationId: "getAgentWorkout"
  },
  "list-workout-templates": {
    method: "GET",
    path: "/agent/workout-templates",
    operationId: "listAgentWorkoutTemplates"
  },
  "get-workout-template": {
    method: "GET",
    path: "/agent/workout-templates/{workoutTemplateId}",
    params: ["workoutTemplateId"],
    operationId: "getAgentWorkoutTemplate"
  },
  "list-routines": {
    method: "GET",
    path: "/agent/routines",
    operationId: "listAgentRoutines"
  },
  "get-routine": {
    method: "GET",
    path: "/agent/routines/{routineId}",
    params: ["routineId"],
    operationId: "getAgentRoutine"
  },
  "manage-plan-tree": {
    method: "POST",
    path: "/agent/plan-tree/batch-write",
    body: true,
    operationId: "batchWriteAgentPlanTree"
  },
  "materialize-workout-template": {
    method: "POST",
    path: "/agent/workout-templates/materialize",
    body: true,
    operationId: "materializeAgentWorkoutTemplate"
  },
  "capture-workout-template": {
    method: "POST",
    path: "/agent/workout-templates/capture",
    body: true,
    operationId: "captureAgentWorkoutTemplate"
  },
  "update-workout-template-from-workout": {
    method: "POST",
    path: "/agent/workout-templates/update-from-workout",
    body: true,
    operationId: "updateAgentWorkoutTemplateFromWorkout"
  },
  "exercise-analytics": {
    method: "GET",
    path: "/agent/analytics/exercises/{exerciseId}",
    params: ["exerciseId"],
    operationId: "getAgentExerciseAnalytics"
  },
  "monitoring-activity": {
    method: "GET",
    path: "/agent/monitoring/activities/{externalActivityId}",
    params: ["externalActivityId"],
    operationId: "getAgentMonitoringActivity"
  },
  "log-meal": {
    method: "POST",
    path: "/agent/meals/batch-write",
    body: true,
    operationId: "batchWriteAgentMeal"
  },
  "list-meals": { method: "GET", path: "/agent/meals", operationId: "listAgentMeals" },
  "list-foods": { method: "GET", path: "/agent/foods", operationId: "listAgentFoods" },
  "search-platform-foods": {
    method: "GET",
    path: "/agent/foods/platform-search",
    operationId: "searchAgentPlatformFoods"
  },
  "manage-foods": {
    method: "POST",
    path: "/agent/foods/batch-write",
    body: true,
    operationId: "batchWriteAgentFoods"
  },
  "nutrition-totals": {
    method: "GET",
    path: "/agent/nutrition/totals",
    operationId: "getAgentNutritionTotals"
  },
  "nutrition-trends": {
    method: "GET",
    path: "/agent/nutrition/trends",
    operationId: "getAgentNutritionTrends"
  },
  "list-nutrition-goals": {
    method: "GET",
    path: "/agent/nutrition/goals",
    operationId: "listAgentNutritionGoals"
  },
  "log-nutrition-goals": {
    method: "POST",
    path: "/agent/nutrition/goals/batch-write",
    body: true,
    operationId: "batchWriteAgentNutritionGoals"
  },
  "energy-balance": {
    method: "GET",
    path: "/agent/cross-domain/energy-balance",
    operationId: "getAgentEnergyBalance"
  },
  "training-day-nutrition": {
    method: "GET",
    path: "/agent/cross-domain/training-day-nutrition",
    operationId: "getAgentTrainingDayNutrition"
  },
  "list-metrics": { method: "GET", path: "/agent/metrics", operationId: "listAgentMetrics" },
  "list-metric-readings": {
    method: "GET",
    path: "/agent/metrics/readings",
    operationId: "listAgentMetricReadings"
  },
  "log-metrics": {
    method: "POST",
    path: "/agent/metrics/batch-write",
    body: true,
    operationId: "batchWriteAgentMetrics"
  },
  "list-compounds": {
    method: "GET",
    path: "/agent/protocols/compounds",
    operationId: "listAgentCompounds"
  },
  "list-protocols": {
    method: "GET",
    path: "/agent/protocols",
    operationId: "listAgentProtocols"
  },
  "list-doses": {
    method: "GET",
    path: "/agent/protocols/doses",
    operationId: "listAgentDoses"
  },
  "effect-window": {
    method: "GET",
    path: "/agent/protocols/effect-window",
    operationId: "readAgentEffectWindow"
  },
  "log-doses": {
    method: "POST",
    path: "/agent/protocols/doses/batch-write",
    body: true,
    operationId: "batchWriteAgentDoses"
  },
  "manage-compounds": {
    method: "POST",
    path: "/agent/protocols/compounds/batch-write",
    body: true,
    operationId: "batchWriteAgentCompounds"
  },
  "manage-protocols": {
    method: "POST",
    path: "/agent/protocols/batch-write",
    body: true,
    operationId: "batchWriteAgentProtocols"
  },
  "read-settings": {
    method: "GET",
    path: "/agent/settings",
    operationId: "readAgentSettings"
  },
  "update-settings": {
    method: "POST",
    path: "/agent/settings/batch-write",
    body: true,
    operationId: "batchWriteAgentSettings"
  },
  "list-activity": {
    method: "GET",
    path: "/agent/activity",
    operationId: "listAgentActivity"
  },
  "undo-activity-batch": {
    method: "POST",
    path: "/agent/activity/undo-batch",
    body: true,
    operationId: "undoAgentActivityBatch"
  }
};
const PATH_PARAM_FLAGS = new Map([
  ["--exercise-id", "exerciseId"],
  ["--external-activity-id", "externalActivityId"],
  ["--routine-id", "routineId"],
  ["--workout-id", "workoutId"],
  ["--workout-template-id", "workoutTemplateId"]
]);

const commandPathParameters = new Set(
  Object.values(COMMANDS).flatMap((command) => command.params ?? [])
);
for (const [flag, pathParameter] of PATH_PARAM_FLAGS) {
  if (!commandPathParameters.has(pathParameter)) {
    throw new Error(
      `${flag} targets ${pathParameter}, which no registered command uses.`
    );
  }
}

async function main() {
  const argv = process.argv.slice(2);
  if (argv.includes("--commands-json")) {
    writeJson(commandManifest(), argv.includes("--pretty"));
    return;
  }
  if (argv.length === 0 || argv[0] === "--help" || argv[0] === "-h") {
    printHelp();
    return;
  }

  const commandName = argv.shift();
  const command = COMMANDS[commandName];
  if (command === undefined) {
    writeJson(
      {
        ok: false,
        error: "unknown_command",
        message: `Unknown command: ${commandName}`
      },
      true
    );
    process.exitCode = 2;
    return;
  }

  const options = parseOptions(argv);
  if (options.help) {
    printHelp(commandName);
    return;
  }
  if (!command.body && (options.file !== undefined || options.json !== undefined)) {
    throw new Error("--file and --json are only valid for commands with request bodies.");
  }

  const body = command.body ? await readRequestBody(options) : undefined;
  const baseUrl = stripTrailingSlash(
    options.baseUrl ?? process.env.PRN_BASE_URL ?? "http://localhost:3000"
  );
  const apiKey = process.env.PRN_AGENT_API_KEY;
  if (apiKey === undefined || apiKey.length === 0) {
    writeJson(
      {
        ok: false,
        error: "missing_api_key",
        message: "Set PRN_AGENT_API_KEY in the code execution environment."
      },
      true
    );
    process.exitCode = 2;
    return;
  }

  const path = fillPathParams(command.path, command.params ?? [], options.params);
  if (path.missing.length > 0) {
    writeJson(
      {
        ok: false,
        error: "missing_path_param",
        message: `Missing required path parameter(s): ${path.missing.join(", ")}`
      },
      true
    );
    process.exitCode = 2;
    return;
  }

  const url = new URL(`${baseUrl}${path.value}`);
  for (const [key, value] of options.query) {
    url.searchParams.append(key, value);
  }

  if (options.dryRun) {
    writeJson(
      {
        ok: true,
        status: null,
        dryRun: true,
        command: commandName,
        data: {
          method: command.method,
          url: url.toString(),
          body
        }
      },
      options.pretty
    );
    return;
  }

  const response = await fetch(url, {
    method: command.method,
    headers: {
      authorization: `Bearer ${apiKey}`,
      ...(body === undefined ? {} : { "content-type": "application/json" })
    },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const responseBody = await readResponseBody(response);
  const envelope = {
    ok: response.ok,
    status: response.status,
    command: commandName,
    data: responseBody,
    ...(options.select.length === 0
      ? {}
      : { selected: selectPaths(responseBody, options.select) })
  };

  writeJson(envelope, options.pretty);
  if (!response.ok) {
    process.exitCode = 1;
  }
}

function parseOptions(argv) {
  const options = {
    baseUrl: undefined,
    dryRun: false,
    file: undefined,
    help: false,
    json: undefined,
    params: new Map(),
    pretty: false,
    query: [],
    select: []
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    switch (token) {
      case "--base-url":
        options.baseUrl = requireValue(argv, ++index, token);
        break;
      case "--dry-run":
        options.dryRun = true;
        break;
      case "--file":
        options.file = requireValue(argv, ++index, token);
        break;
      case "--help":
      case "-h":
        options.help = true;
        break;
      case "--json":
        options.json = requireValue(argv, ++index, token);
        break;
      case "--param": {
        const [key, value] = parseKeyValue(requireValue(argv, ++index, token));
        options.params.set(camelCase(key), value);
        break;
      }
      case "--pretty":
        options.pretty = true;
        break;
      case "--query": {
        const pair = parseKeyValue(requireValue(argv, ++index, token));
        options.query.push(pair);
        break;
      }
      case "--select":
        options.select.push(requireValue(argv, ++index, token));
        break;
      default:
        if (PATH_PARAM_FLAGS.has(token)) {
          const key = PATH_PARAM_FLAGS.get(token);
          const value = requireValue(argv, ++index, token);
          options.params.set(key, value);
          break;
        }
        if (token.startsWith("--")) {
          throw new Error(`Unknown option: ${token}`);
        }
        throw new Error(`Unexpected positional argument: ${token}`);
    }
  }

  return options;
}

async function readRequestBody(options) {
  if (options.file !== undefined && options.json !== undefined) {
    throw new Error("Pass only one of --file or --json.");
  }
  if (options.json !== undefined) {
    return parseJson(options.json, "--json");
  }
  if (options.file !== undefined) {
    const text = await import("node:fs/promises").then(({ readFile }) =>
      readFile(options.file, "utf8")
    );
    return parseJson(text, options.file);
  }

  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(Buffer.from(chunk));
  }
  const stdin = Buffer.concat(chunks).toString("utf8").trim();
  if (stdin.length === 0) {
    throw new Error("Write commands require --file, --json, or JSON on stdin.");
  }

  return parseJson(stdin, "stdin");
}

function fillPathParams(template, params, provided) {
  const missing = [];
  let value = template;
  for (const param of params) {
    const raw = provided.get(param);
    if (raw === undefined) {
      missing.push(param);
      continue;
    }
    value = value.replace(`{${param}}`, encodeURIComponent(raw));
  }

  return { value, missing };
}

async function readResponseBody(response) {
  const text = await response.text();
  if (text.length === 0) {
    return null;
  }
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

function parseKeyValue(value) {
  const separator = value.indexOf("=");
  if (separator <= 0) {
    throw new Error(`Expected key=value, received: ${value}`);
  }

  return [value.slice(0, separator), value.slice(separator + 1)];
}

function requireValue(argv, index, flag) {
  const value = argv[index];
  if (value === undefined || value.startsWith("--")) {
    throw new Error(`${flag} requires a value.`);
  }
  return value;
}

function parseJson(text, source) {
  try {
    return JSON.parse(text);
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(`Invalid JSON in ${source}: ${detail}`);
  }
}

function stripTrailingSlash(value) {
  return value.replace(/\/+$/, "");
}

function camelCase(value) {
  return value.replace(/-([a-z])/g, (_match, letter) => letter.toUpperCase());
}

function selectPaths(value, paths) {
  return Object.fromEntries(paths.map((path) => [path, selectPath(value, path)]));
}

function selectPath(value, path) {
  const parts = path.split(".").filter(Boolean);
  return selectPathParts(value, parts);
}

function selectPathParts(value, parts) {
  let current = value;
  for (let index = 0; index < parts.length; index += 1) {
    const part = parts[index];
    if (part.endsWith("[]")) {
      const key = part.slice(0, -2);
      const items = key.length === 0 ? current : current?.[key];
      if (!Array.isArray(items)) {
        return null;
      }
      const rest = parts.slice(index + 1);
      return rest.length === 0
        ? items
        : items.map((item) => selectPathParts(item, rest));
    }
    current = current?.[part];
    if (current === undefined) {
      return null;
    }
  }

  return current;
}

function commandManifest() {
  return {
    commands: Object.fromEntries(
      Object.entries(COMMANDS)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([name, command]) => [
          name,
          {
            method: command.method,
            path: command.path,
            body: command.body === true,
            params: command.params ?? [],
            operationId: command.operationId
          }
        ])
    )
  };
}

function writeJson(value, pretty) {
  process.stdout.write(`${JSON.stringify(value, null, pretty ? 2 : 0)}\n`);
}

function printHelp(commandName) {
  const commands = Object.keys(COMMANDS).sort();
  const details =
    commandName === undefined
      ? ""
      : `\nSelected command:\n  ${commandName} ${JSON.stringify(COMMANDS[commandName])}\n`;

  process.stdout.write(`Perennia agent API helper

Usage:
  node scripts/prn-agent.mjs <command> [options]

Environment:
  PRN_BASE_URL        API base URL, default http://localhost:3000
  PRN_AGENT_API_KEY   Agent API key used as the bearer token

Options:
  --base-url <url>         Override PRN_BASE_URL
  --file <path>            JSON request body for write/validation commands
  --json <json>            Inline JSON request body
  --query key=value        Add a query parameter, repeatable
  --param key=value        Add a path parameter, repeatable
  --select <path>          Copy data at a dot path into selected, repeatable
  --exercise-id <id>       Shorthand path parameter
  --external-activity-id <id>
  --workout-id <id>
  --dry-run                Print the planned request without sending it
  --pretty                 Pretty-print stdout JSON
  --commands-json          Print the command map for drift checks
  --help                   Show help

Commands:
  ${commands.join("\n  ")}
${details}
Examples:
  node scripts/prn-agent.mjs probe --pretty
  node scripts/prn-agent.mjs resolve-exercise --query name="Back Squat"
  node scripts/prn-agent.mjs list-metrics --query metricKey=bodyWeight --query fields=id,name,canonicalKey,unit --select metrics[].id
  node scripts/prn-agent.mjs exercise-analytics --exercise-id ex-1 --query from=2026-06-01
  node scripts/prn-agent.mjs log-metrics --file metrics.json --dry-run
  node scripts/prn-agent.mjs list-activity --query actor=agent --query limit=20
  node scripts/prn-agent.mjs undo-activity-batch --json '{"batchId":"batch-id","idempotencyKey":"undo-key"}'
`);
}

main().catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  writeJson(
    {
      ok: false,
      error: "script_failed",
      message: error instanceof Error ? error.message : String(error)
    },
    false
  );
  process.exitCode = 1;
});
