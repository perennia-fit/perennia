#!/usr/bin/env node

import { pathToFileURL } from "node:url";

const DEFAULT_BASE_URL = "http://localhost:3000";
const DEFAULT_METRIC_READING_FIELDS =
  "id,metricId,scalarValue,unit,atTime,windowStartedAt,windowEndedAt";

export class OwlAgentApiError extends Error {
  constructor({ body, status }) {
    super(`Agent API request failed with status ${status}.`);
    this.name = "OwlAgentApiError";
    this.body = body;
    this.status = status;
  }
}

export async function createOwlAgentClient(options = {}) {
  const { client } = await createOwlAgentClientWithSource(options);
  return client;
}

export async function createOwlAgentClientWithSource(options = {}) {
  const baseUrl = options.baseUrl ?? process.env.PRN_BASE_URL ?? DEFAULT_BASE_URL;
  const bearerToken = options.bearerToken ?? process.env.PRN_AGENT_API_KEY;
  if (bearerToken === undefined || bearerToken.length === 0) {
    throw new Error("Set PRN_AGENT_API_KEY in the code execution environment.");
  }

  const generatedModule = Object.hasOwn(options, "agentClientModule")
    ? options.agentClientModule
    : await importGeneratedAgentClientModule();
  if (generatedModule?.PerenniaAgentClient !== undefined) {
    return {
      client: new generatedModule.PerenniaAgentClient({
        baseUrl,
        bearerToken,
        fetch: options.fetch
      }),
      source: "generated"
    };
  }

  return {
    client: new PortableOwlAgentClient({
      baseUrl,
      bearerToken,
      fetch: options.fetch
    }),
    source: "portable"
  };
}

export async function metricReadingsSummary(client, input = {}) {
  const response = await client.listAgentMetricReadings({
    fields: DEFAULT_METRIC_READING_FIELDS,
    limit: 100,
    ...input
  });
  return summarizeMetricReadings(response);
}

export function summarizeMetricReadings(input) {
  const readings = Array.isArray(input) ? input : input?.readings ?? [];
  const scalarReadings = readings.filter(
    (reading) => typeof reading.scalarValue === "number"
  );
  const values = scalarReadings.map((reading) => reading.scalarValue);
  const latest = latestReading(readings);
  const unit =
    scalarReadings.find((reading) => reading.unit !== undefined)?.unit ??
    latest?.unit ??
    null;

  return {
    count: readings.length,
    scalarCount: values.length,
    unit,
    min: values.length === 0 ? null : Math.min(...values),
    max: values.length === 0 ? null : Math.max(...values),
    average: values.length === 0 ? null : sum(values) / values.length,
    latest:
      latest === null
        ? null
        : {
            id: latest.id,
            metricId: latest.metricId,
            at:
              latest.atTime ??
              latest.windowEndedAt ??
              latest.windowStartedAt ??
              null,
            scalarValue:
              typeof latest.scalarValue === "number" ? latest.scalarValue : null,
            unit: latest.unit ?? unit
          }
  };
}

export function nutritionPeriodSummary(response) {
  const period = response?.period ?? {};
  return {
    from: period.from ?? response?.from ?? null,
    to: period.to ?? response?.to ?? null,
    dayCount: period.dayCount ?? response?.dayCount ?? 0,
    loggedDayCount: period.loggedDayCount ?? 0,
    mealCount: period.mealCount ?? 0,
    entryCount: period.entryCount ?? 0,
    totals: period.totals ?? [],
    goalProgress: period.goalProgress ?? []
  };
}

export async function effectWindowSummary(client, input = {}) {
  const response = await client.readAgentEffectWindow(input);
  return summarizeEffectWindow(response);
}

/**
 * Reduces a GET /agent/protocols/effect-window response to a compact,
 * strictly descriptive summary: a mean-delta convenience on top of the
 * before/during/after aggregates. Never a causal, efficacy, or medical claim
 * — mirrors `descriptiveOnly: true` through unchanged, and computes
 * nothing that isn't already in the response (nothing is stored).
 */
export function summarizeEffectWindow(response) {
  const segments = response?.segments ?? {};
  const before = segments.before ?? { count: 0, min: null, max: null, mean: null };
  const during = segments.during ?? { count: 0, min: null, max: null, mean: null };
  const after = segments.after ?? { count: 0, min: null, max: null, mean: null };

  return {
    source: response?.source ?? null,
    metric: response?.metric ?? null,
    from: response?.range?.from ?? null,
    to: response?.range?.to ?? null,
    doseCount: Array.isArray(response?.doses) ? response.doses.length : 0,
    before,
    during,
    after,
    meanDelta: {
      duringVsBefore: meanDelta(during.mean, before.mean),
      afterVsBefore: meanDelta(after.mean, before.mean)
    },
    descriptiveOnly: response?.descriptiveOnly ?? true
  };
}

export async function workoutsSummary(client, input = {}) {
  const response = await client.listAgentWorkouts(input);
  return summarizeWorkouts(response);
}

/**
 * Reduces a GET /agent/workouts response to a compact summary: total sets
 * across the returned page, the unique exercise names touched, and the
 * earliest/latest startedAt in the page. Computed from the bounded page only
 * — never a new unbounded read.
 */
export function summarizeWorkouts(response) {
  const workouts = Array.isArray(response) ? response : response?.workouts ?? [];
  const startedAtValues = workouts
    .map((workout) => workout.startedAt)
    .filter((value) => typeof value === "string")
    .sort();
  const uniqueExerciseNames = [
    ...new Set(workouts.flatMap((workout) => workout.exerciseNames ?? []))
  ].sort();

  return {
    workoutCount: workouts.length,
    totalMatched: response?.totalMatched ?? workouts.length,
    totalSets: sum(workouts.map((workout) => workout.setCount ?? 0)),
    uniqueExerciseNames,
    earliestStartedAt: startedAtValues.at(0) ?? null,
    latestStartedAt: startedAtValues.at(-1) ?? null
  };
}

function meanDelta(candidate, baseline) {
  if (typeof candidate !== "number" || typeof baseline !== "number") {
    return null;
  }
  return Math.round((candidate - baseline) * 1000) / 1000;
}

export class PortableOwlAgentClient {
  constructor({ baseUrl, bearerToken, fetch }) {
    this.baseUrl = new URL(baseUrl);
    this.bearerToken = bearerToken;
    this.fetchImplementation = fetch ?? globalThis.fetch;
    if (this.fetchImplementation === undefined) {
      throw new Error("PortableOwlAgentClient requires a fetch implementation.");
    }
  }

  async batchWriteAgentCompounds(body, options = {}) {
    return this.request({
      method: "POST",
      path: "/agent/protocols/compounds/batch-write",
      expectedStatus: 200,
      body,
      signal: options.signal
    });
  }

  async batchWriteAgentDoses(body, options = {}) {
    return this.request({
      method: "POST",
      path: "/agent/protocols/doses/batch-write",
      expectedStatus: 200,
      body,
      signal: options.signal
    });
  }

  async batchWriteAgentExerciseCatalog(body, options = {}) {
    return this.request({
      method: "POST",
      path: "/agent/exercises/batch-write",
      expectedStatus: 200,
      body,
      signal: options.signal
    });
  }

  async batchWriteAgentFoods(body, options = {}) {
    return this.request({
      method: "POST",
      path: "/agent/foods/batch-write",
      expectedStatus: 200,
      body,
      signal: options.signal
    });
  }

  async batchWriteAgentMeal(body, options = {}) {
    return this.request({
      method: "POST",
      path: "/agent/meals/batch-write",
      expectedStatus: 200,
      body,
      signal: options.signal
    });
  }

  async batchWriteAgentNutritionGoals(body, options = {}) {
    return this.request({
      method: "POST",
      path: "/agent/nutrition/goals/batch-write",
      expectedStatus: 200,
      body,
      signal: options.signal
    });
  }

  async batchWriteAgentPlanTree(body, options = {}) {
    return this.request({
      method: "POST",
      path: "/agent/plan-tree/batch-write",
      expectedStatus: 200,
      body,
      signal: options.signal
    });
  }

  async batchWriteAgentProtocols(body, options = {}) {
    return this.request({
      method: "POST",
      path: "/agent/protocols/batch-write",
      expectedStatus: 200,
      body,
      signal: options.signal
    });
  }

  async batchWriteAgentSettings(body, options = {}) {
    return this.request({
      method: "POST",
      path: "/agent/settings/batch-write",
      expectedStatus: 200,
      body,
      signal: options.signal
    });
  }

  async batchWriteAgentMetrics(body, options = {}) {
    return this.request({
      method: "POST",
      path: "/agent/metrics/batch-write",
      expectedStatus: 200,
      body,
      signal: options.signal
    });
  }

  async batchWriteAgentWorkout(body, options = {}) {
    return this.request({
      method: "POST",
      path: "/agent/workouts/batch-write",
      expectedStatus: 200,
      body,
      signal: options.signal
    });
  }

  async captureAgentWorkoutTemplate(body, options = {}) {
    return this.request({
      method: "POST",
      path: "/agent/workout-templates/capture",
      expectedStatus: 200,
      body,
      signal: options.signal
    });
  }

  async getAgentEnergyBalance(input, options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/cross-domain/energy-balance",
      expectedStatus: 200,
      query: pick(input, ["from", "to"]),
      signal: options.signal
    });
  }

  async getAgentExerciseAnalytics(input, options = {}) {
    return this.request({
      method: "GET",
      path: `/agent/analytics/exercises/${encodeURIComponent(
        String(input.exerciseId)
      )}`,
      expectedStatus: 200,
      query: pick(input, ["from", "to", "maxPoints"]),
      signal: options.signal
    });
  }

  async getAgentMonitoringActivity(input, options = {}) {
    return this.request({
      method: "GET",
      path: `/agent/monitoring/activities/${encodeURIComponent(
        String(input.externalActivityId)
      )}`,
      expectedStatus: 200,
      signal: options.signal
    });
  }

  async getAgentRoutine(input, options = {}) {
    return this.request({
      method: "GET",
      path: `/agent/routines/${encodeURIComponent(String(input.routineId))}`,
      expectedStatus: 200,
      query: pick(input, ["includeArchived", "componentLimit", "selectedDate"]),
      signal: options.signal
    });
  }

  async getAgentWorkout(input, options = {}) {
    return this.request({
      method: "GET",
      path: `/agent/workouts/${encodeURIComponent(String(input.workoutId))}`,
      expectedStatus: 200,
      signal: options.signal
    });
  }

  async getAgentWorkoutTemplate(input, options = {}) {
    return this.request({
      method: "GET",
      path: `/agent/workout-templates/${encodeURIComponent(
        String(input.workoutTemplateId)
      )}`,
      expectedStatus: 200,
      query: pick(input, ["includeArchived", "componentLimit"]),
      signal: options.signal
    });
  }

  async getAgentNutritionTotals(input, options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/nutrition/totals",
      expectedStatus: 200,
      query: pick(input, [
        "from",
        "to",
        "energyGoal",
        "proteinGoal",
        "carbohydrateGoal",
        "fatGoal"
      ]),
      signal: options.signal
    });
  }

  async getAgentNutritionTrends(input, options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/nutrition/trends",
      expectedStatus: 200,
      query: pick(input, [
        "from",
        "to",
        "energyGoal",
        "proteinGoal",
        "carbohydrateGoal",
        "fatGoal"
      ]),
      signal: options.signal
    });
  }

  async getAgentProtectedProbe(options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/probe",
      expectedStatus: 200,
      signal: options.signal
    });
  }

  async getAgentTrainingDayNutrition(input, options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/cross-domain/training-day-nutrition",
      expectedStatus: 200,
      query: pick(input, [
        "from",
        "to",
        "preWindowMinutes",
        "postWindowMinutes"
      ]),
      signal: options.signal
    });
  }

  async materializeAgentWorkoutTemplate(body, options = {}) {
    return this.request({
      method: "POST",
      path: "/agent/workout-templates/materialize",
      expectedStatus: 200,
      body,
      signal: options.signal
    });
  }

  async listAgentActivity(input = {}, options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/activity",
      expectedStatus: 200,
      query: pick(input, [
        "actor",
        "entityTable",
        "batchId",
        "from",
        "to",
        "limit",
        "cursor"
      ]),
      signal: options.signal
    });
  }

  async listAgentCompounds(input = {}, options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/protocols/compounds",
      expectedStatus: 200,
      query: pick(input, ["search", "includeArchived", "limit", "cursor", "fields"]),
      signal: options.signal
    });
  }

  async listAgentDoses(input = {}, options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/protocols/doses",
      expectedStatus: 200,
      query: pick(input, [
        "compoundId",
        "protocolId",
        "from",
        "to",
        "provenance",
        "includeArchived",
        "limit",
        "cursor",
        "fields"
      ]),
      signal: options.signal
    });
  }

  async listAgentExercises(input = {}, options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/exercises",
      expectedStatus: 200,
      query: pick(input, [
        "search",
        "category",
        "favorite",
        "activeOnly",
        "limit",
        "cursor",
        "fields"
      ]),
      signal: options.signal
    });
  }

  async listAgentFoods(input = {}, options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/foods",
      expectedStatus: 200,
      query: pick(input, ["search", "includeArchived", "limit", "cursor", "fields"]),
      signal: options.signal
    });
  }

  async listAgentHistorySets(input = {}, options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/history/sets",
      expectedStatus: 200,
      query: pick(input, [
        "exerciseId",
        "category",
        "from",
        "to",
        "minLoadKilograms",
        "minReps",
        "minDurationSeconds",
        "minDistanceKilometers",
        "limit",
        "cursor"
      ]),
      signal: options.signal
    });
  }

  async listAgentMeals(input = {}, options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/meals",
      expectedStatus: 200,
      query: pick(input, ["from", "to", "limit", "cursor", "fields"]),
      signal: options.signal
    });
  }

  async listAgentMetricReadings(input = {}, options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/metrics/readings",
      expectedStatus: 200,
      query: pick(input, [
        "metricId",
        "metricKey",
        "from",
        "to",
        "provenance",
        "source",
        "includeArchived",
        "limit",
        "cursor",
        "fields"
      ]),
      signal: options.signal
    });
  }

  async listAgentMetrics(input = {}, options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/metrics",
      expectedStatus: 200,
      query: pick(input, [
        "search",
        "metricKey",
        "metricGroup",
        "enabledOnly",
        "includeArchived",
        "limit",
        "cursor",
        "fields"
      ]),
      signal: options.signal
    });
  }

  async listAgentNutritionGoals(options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/nutrition/goals",
      expectedStatus: 200,
      signal: options.signal
    });
  }

  async listAgentProtocols(input = {}, options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/protocols",
      expectedStatus: 200,
      query: pick(input, ["search", "includeArchived", "limit", "cursor"]),
      signal: options.signal
    });
  }

  async listAgentRoutines(input = {}, options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/routines",
      expectedStatus: 200,
      query: pick(input, [
        "search",
        "includeArchived",
        "limit",
        "cursor",
        "fields"
      ]),
      signal: options.signal
    });
  }

  async listAgentWorkoutTemplates(input = {}, options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/workout-templates",
      expectedStatus: 200,
      query: pick(input, [
        "search",
        "includeArchived",
        "limit",
        "cursor",
        "fields"
      ]),
      signal: options.signal
    });
  }

  async listAgentWorkouts(input = {}, options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/workouts",
      expectedStatus: 200,
      query: pick(input, ["from", "to", "limit", "cursor", "fields"]),
      signal: options.signal
    });
  }

  async readAgentEffectWindow(input, options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/protocols/effect-window",
      expectedStatus: 200,
      query: pick(input, [
        "compoundId",
        "protocolId",
        "metricId",
        "metricKey",
        "from",
        "to"
      ]),
      signal: options.signal
    });
  }

  async readAgentSettings(options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/settings",
      expectedStatus: 200,
      signal: options.signal
    });
  }

  async resolveAgentExerciseName(input, options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/exercises/resolve",
      expectedStatus: 200,
      query: pick(input, ["name", "candidateLimit"]),
      signal: options.signal
    });
  }

  async searchAgentPlatformFoods(input = {}, options = {}) {
    return this.request({
      method: "GET",
      path: "/agent/foods/platform-search",
      expectedStatus: 200,
      query: pick(input, ["search", "source", "limit"]),
      signal: options.signal
    });
  }

  async undoAgentActivityBatch(body, options = {}) {
    return this.request({
      method: "POST",
      path: "/agent/activity/undo-batch",
      expectedStatus: 200,
      body,
      signal: options.signal
    });
  }

  async updateAgentWorkoutTemplateFromWorkout(body, options = {}) {
    return this.request({
      method: "POST",
      path: "/agent/workout-templates/update-from-workout",
      expectedStatus: 200,
      body,
      signal: options.signal
    });
  }

  async validateAgentDose(body, options = {}) {
    return this.request({
      method: "POST",
      path: "/agent/validate-dose",
      expectedStatus: 200,
      body,
      signal: options.signal
    });
  }

  async validateAgentSet(body, options = {}) {
    return this.request({
      method: "POST",
      path: "/agent/validate-set",
      expectedStatus: 200,
      body,
      signal: options.signal
    });
  }

  async request({ body, expectedStatus, method, path, query, signal }) {
    const url = new URL(path, this.baseUrl);
    for (const [key, value] of Object.entries(query ?? {})) {
      if (value !== undefined && value !== null) {
        url.searchParams.set(key, String(value));
      }
    }

    const headers = {
      accept: "application/json",
      authorization: `Bearer ${this.bearerToken}`
    };
    const init = { method, headers, signal };
    if (body !== undefined) {
      headers["content-type"] = "application/json";
      init.body = JSON.stringify(body);
    }

    const response = await this.fetchImplementation(url.toString(), init);
    const responseBody = await response.text();
    if (response.status !== expectedStatus) {
      throw new OwlAgentApiError({ body: responseBody, status: response.status });
    }

    return responseBody.length === 0 ? undefined : JSON.parse(responseBody);
  }
}

async function importGeneratedAgentClientModule() {
  const specifiers = [
    process.env.PRN_AGENT_CLIENT_MODULE,
    "@perennia/contract/agent-client"
  ].filter(Boolean);

  for (const specifier of specifiers) {
    try {
      return await import(specifier);
    } catch {
      // A distributed skill may not have the workspace package or a TS loader.
    }
  }

  return null;
}

function latestReading(readings) {
  const ordered = readings
    .filter((reading) => readingAnchor(reading) !== null)
    .sort((left, right) => {
      const byAnchor = readingAnchor(left).localeCompare(readingAnchor(right));
      return byAnchor || String(left.id ?? "").localeCompare(String(right.id ?? ""));
    });
  return ordered.at(-1) ?? null;
}

function readingAnchor(reading) {
  return (
    reading.atTime ?? reading.windowEndedAt ?? reading.windowStartedAt ?? null
  );
}

function sum(values) {
  return values.reduce((total, value) => total + value, 0);
}

function pick(input = {}, keys) {
  return Object.fromEntries(
    keys
      .filter((key) => input[key] !== undefined && input[key] !== null)
      .map((key) => [key, input[key]])
  );
}

function parseCliOptions(argv) {
  const options = {
    baseUrl: undefined,
    pretty: false,
    query: []
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    switch (token) {
      case "--base-url":
        options.baseUrl = requireValue(argv, ++index, token);
        break;
      case "--pretty":
        options.pretty = true;
        break;
      case "--query":
        options.query.push(parseKeyValue(requireValue(argv, ++index, token)));
        break;
      default:
        if (token.startsWith("--")) {
          throw new Error(`Unknown option: ${token}`);
        }
        throw new Error(`Unexpected positional argument: ${token}`);
    }
  }

  return options;
}

async function main(argv = process.argv.slice(2)) {
  if (argv.length === 0 || argv[0] === "--help" || argv[0] === "-h") {
    printHelp();
    return;
  }

  const command = argv.shift();
  const options = parseCliOptions(argv);
  const { client, source } = await createOwlAgentClientWithSource({
    baseUrl: options.baseUrl
  });
  const query = Object.fromEntries(options.query);
  const data =
    command === "probe"
      ? await client.getAgentProtectedProbe()
      : command === "metric-readings-summary"
        ? await metricReadingsSummary(client, query)
        : command === "nutrition-period-summary"
          ? nutritionPeriodSummary(await client.getAgentNutritionTotals(query))
          : command === "effect-window-summary"
            ? await effectWindowSummary(client, query)
            : command === "workouts-summary"
              ? await workoutsSummary(client, query)
              : null;

  if (data === null) {
    throw new Error(`Unknown command: ${command}`);
  }

  writeJson({ ok: true, command, clientSource: source, data }, options.pretty);
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

function writeJson(value, pretty) {
  process.stdout.write(`${JSON.stringify(value, null, pretty ? 2 : 0)}\n`);
}

function printHelp() {
  process.stdout.write(`Perennia code-mode helper

Usage:
  node scripts/prn-code.mjs <command> [options]

Environment:
  PRN_BASE_URL               API base URL, default ${DEFAULT_BASE_URL}
  PRN_AGENT_API_KEY          Agent API key used as the bearer token
  PRN_AGENT_CLIENT_MODULE    Optional generated client module specifier

Commands:
  probe
  metric-readings-summary
  nutrition-period-summary
  effect-window-summary
  workouts-summary

Options:
  --base-url <url>       Override PRN_BASE_URL
  --query key=value      Add an operation input/query value, repeatable
  --pretty               Pretty-print stdout JSON
  --help                 Show help

Examples:
  node scripts/prn-code.mjs probe --pretty
  node scripts/prn-code.mjs metric-readings-summary --query metricKey=hrv --query from=2026-06-01 --query to=2026-06-30
  node scripts/prn-code.mjs effect-window-summary --query compoundId=compound-1 --query metricKey=hrv --query from=2026-06-01 --query to=2026-06-30
  node scripts/prn-code.mjs workouts-summary --query from=2026-06-01T00:00:00.000Z --query to=2026-06-30T00:00:00.000Z
`);
}

if (process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href) {
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
}
