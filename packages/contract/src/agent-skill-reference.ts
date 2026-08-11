// Shared derivation for agent skill command maps. The generator script
// (scripts/generate-agent-skill-reference.ts) and the CI drift tests import
// this module so the code-mode REST skill, the Hermes MCP reference and
// allowlist, the registered MCP tools, and the committed OpenAPI contract
// cannot silently drift apart.

type JsonObject = Record<string, unknown>;

type OpenApiParameter = {
  in?: string;
  name: string;
  required?: boolean;
  schema?: JsonObject;
};

type OpenApiOperation = {
  operationId?: string;
  parameters?: OpenApiParameter[];
  requestBody?: unknown;
  tags?: string[];
};

export type OpenApiDocument = {
  paths?: Record<string, Record<string, OpenApiOperation>>;
};

export type AgentKeyOperation = {
  hasBody: boolean;
  method: string;
  operationId: string;
  path: string;
  pathParameters: string[];
};

export type AgentSkillCommandRow = {
  command: string;
  hasBody: boolean;
  method: string;
  operationId: string;
  path: string;
  pathParameters: string[];
};

export type AgentMcpToolRow = AgentSkillCommandRow & {
  tool: string;
};

/**
 * The three Agent API Key management operations authenticate with a human
 * SESSION bearer token (`verifySessionBearer` in apps/server/src/app.ts), not
 * an agent API key — a different actor than every other /agent/* route. They
 * are intentionally not registered as MCP tools (apps/server/src/agent-mcp.ts)
 * and are excluded from the code-mode skill's command surface for the same
 * reason: `prn-agent.mjs`/`prn-code.mjs` assume `PRN_AGENT_API_KEY` is already
 * the acting credential.
 */
export const AGENT_SKILL_SESSION_AUTHENTICATED_OPERATION_IDS: ReadonlySet<string> =
  new Set(["createAgentApiKey", "listAgentApiKeys", "revokeAgentApiKey"]);

/**
 * Command name registry — the single source of truth mapping an OpenAPI
 * operationId to the `prn-agent.mjs` command name. Deliberately hand-authored
 * (not derived from the operationId string) so existing command names stay
 * stable as the API surface grows; adding a new agent-key operation without a
 * registry entry fails `buildAgentSkillCommandTable` loudly instead of
 * silently leaving the skill without a command.
 */
export const AGENT_SKILL_COMMAND_NAMES: Readonly<Record<string, string>> = {
  batchWriteAgentCompounds: "manage-compounds",
  batchWriteAgentDoses: "log-doses",
  batchWriteAgentExerciseCatalog: "manage-exercise-catalog",
  batchWriteAgentFoods: "manage-foods",
  batchWriteAgentMeal: "log-meal",
  batchWriteAgentMetrics: "log-metrics",
  batchWriteAgentNutritionGoals: "log-nutrition-goals",
  batchWriteAgentPlanTree: "manage-plan-tree",
  batchWriteAgentProtocols: "manage-protocols",
  batchWriteAgentSettings: "update-settings",
  batchWriteAgentWorkout: "log-workout",
  captureAgentWorkoutTemplate: "capture-workout-template",
  getAgentEnergyBalance: "energy-balance",
  getAgentExerciseAnalytics: "exercise-analytics",
  getAgentMonitoringActivity: "monitoring-activity",
  getAgentNutritionTotals: "nutrition-totals",
  getAgentNutritionTrends: "nutrition-trends",
  getAgentProtectedProbe: "probe",
  getAgentRoutine: "get-routine",
  getAgentTrainingDayNutrition: "training-day-nutrition",
  getAgentWorkout: "get-workout",
  getAgentWorkoutTemplate: "get-workout-template",
  listAgentActivity: "list-activity",
  listAgentCompounds: "list-compounds",
  listAgentDoses: "list-doses",
  listAgentExercises: "list-exercises",
  listAgentFoods: "list-foods",
  listAgentHistorySets: "list-history-sets",
  listAgentMeals: "list-meals",
  listAgentMetricReadings: "list-metric-readings",
  listAgentMetrics: "list-metrics",
  listAgentNutritionGoals: "list-nutrition-goals",
  listAgentProtocols: "list-protocols",
  listAgentRoutines: "list-routines",
  listAgentWorkoutTemplates: "list-workout-templates",
  listAgentWorkouts: "list-workouts",
  materializeAgentWorkoutTemplate: "materialize-workout-template",
  readAgentEffectWindow: "effect-window",
  readAgentSettings: "read-settings",
  resolveAgentExerciseName: "resolve-exercise",
  searchAgentPlatformFoods: "search-platform-foods",
  undoAgentActivityBatch: "undo-activity-batch",
  updateAgentWorkoutTemplateFromWorkout:
    "update-workout-template-from-workout",
  validateAgentDose: "validate-dose",
  validateAgentSet: "validate-set"
};

/**
 * `getAgentProtectedProbe` is an authenticated REST transport smoke test, not
 * a domain operation, so it deliberately has no MCP tool. Session-authenticated
 * Agent API Key management operations are already excluded from the agent-key
 * command table above.
 */
export const AGENT_MCP_EXCLUDED_OPERATION_IDS: ReadonlySet<string> = new Set([
  "getAgentProtectedProbe"
]);

/**
 * Stable mapping from OpenAPI operationId to registered MCP tool name.
 * The build helper below fails on missing or stale mappings so a new Agent API
 * operation cannot ship without updating both the server and Hermes surface.
 */
export const AGENT_MCP_TOOL_NAMES: Readonly<Record<string, string>> = {
  batchWriteAgentCompounds: "agent_batch_write_compounds",
  batchWriteAgentDoses: "agent_batch_write_doses",
  batchWriteAgentExerciseCatalog: "agent_batch_write_exercise_catalog",
  batchWriteAgentFoods: "agent_batch_write_foods",
  batchWriteAgentMeal: "agent_batch_write_meal",
  batchWriteAgentMetrics: "agent_batch_write_metrics",
  batchWriteAgentNutritionGoals: "agent_batch_write_nutrition_goals",
  batchWriteAgentPlanTree: "agent_batch_write_plan_tree",
  batchWriteAgentProtocols: "agent_batch_write_protocols",
  batchWriteAgentSettings: "agent_batch_write_settings",
  batchWriteAgentWorkout: "agent_batch_write_workout",
  captureAgentWorkoutTemplate: "agent_capture_workout_template",
  getAgentEnergyBalance: "agent_get_energy_balance",
  getAgentExerciseAnalytics: "agent_get_exercise_analytics",
  getAgentMonitoringActivity: "agent_get_monitoring_activity",
  getAgentNutritionTotals: "agent_get_nutrition_totals",
  getAgentNutritionTrends: "agent_get_nutrition_trends",
  getAgentRoutine: "agent_get_routine",
  getAgentTrainingDayNutrition: "agent_get_training_day_nutrition",
  getAgentWorkout: "agent_get_workout",
  getAgentWorkoutTemplate: "agent_get_workout_template",
  listAgentActivity: "agent_list_activity",
  listAgentCompounds: "agent_list_compounds",
  listAgentDoses: "agent_list_doses",
  listAgentExercises: "agent_list_exercises",
  listAgentFoods: "agent_list_foods",
  listAgentHistorySets: "agent_list_history_sets",
  listAgentMeals: "agent_list_meals",
  listAgentMetricReadings: "agent_list_metric_readings",
  listAgentMetrics: "agent_list_metrics",
  listAgentNutritionGoals: "agent_list_nutrition_goals",
  listAgentProtocols: "agent_list_protocols",
  listAgentRoutines: "agent_list_routines",
  listAgentWorkoutTemplates: "agent_list_workout_templates",
  listAgentWorkouts: "agent_list_workouts",
  materializeAgentWorkoutTemplate: "agent_materialize_workout_template",
  readAgentEffectWindow: "agent_read_effect_window",
  readAgentSettings: "agent_read_settings",
  resolveAgentExerciseName: "agent_resolve_exercise",
  searchAgentPlatformFoods: "agent_search_platform_foods",
  undoAgentActivityBatch: "agent_undo_activity_batch",
  updateAgentWorkoutTemplateFromWorkout:
    "agent_update_workout_template_from_workout",
  validateAgentDose: "agent_validate_dose",
  validateAgentSet: "agent_validate_set"
};

/** Every non-session-authenticated /agent/* operation, sorted by operationId. */
export function deriveAgentKeyOperations(
  document: OpenApiDocument
): AgentKeyOperation[] {
  const operations: AgentKeyOperation[] = [];

  for (const [path, methods] of Object.entries(document.paths ?? {})) {
    if (!path.startsWith("/agent/")) {
      continue;
    }

    for (const [method, operation] of Object.entries(methods)) {
      const operationId = operation.operationId;
      if (operationId === undefined) {
        throw new Error(`${method.toUpperCase()} ${path} is missing operationId.`);
      }
      if (AGENT_SKILL_SESSION_AUTHENTICATED_OPERATION_IDS.has(operationId)) {
        continue;
      }

      operations.push({
        hasBody: operation.requestBody !== undefined,
        method: method.toUpperCase(),
        operationId,
        path,
        pathParameters: (operation.parameters ?? [])
          .filter((parameter) => parameter.in === "path")
          .map((parameter) => parameter.name)
      });
    }
  }

  return operations.sort((left, right) =>
    left.operationId.localeCompare(right.operationId)
  );
}

/**
 * Joins the derived agent-key operations with the command name registry.
 * Throws if any operation has no registered command name — the mechanism
 * that keeps a newly added agent operation from shipping without a skill
 * command.
 */
export function buildAgentSkillCommandTable(
  document: OpenApiDocument
): AgentSkillCommandRow[] {
  const operations = deriveAgentKeyOperations(document);
  const missing = operations
    .map((operation) => operation.operationId)
    .filter((operationId) => AGENT_SKILL_COMMAND_NAMES[operationId] === undefined);

  if (missing.length > 0) {
    throw new Error(
      `No prn-agent.mjs command name is registered for: ${missing.join(", ")}. ` +
        "Add an entry to AGENT_SKILL_COMMAND_NAMES in packages/contract/src/agent-skill-reference.ts."
    );
  }

  return operations
    .map((operation) => ({
      ...operation,
      command: AGENT_SKILL_COMMAND_NAMES[operation.operationId]
    }))
    .sort((left, right) => left.command.localeCompare(right.command));
}

/**
 * Joins the agent-key command table to the MCP tool-name registry and rejects
 * either direction of drift.
 */
export function buildAgentMcpToolTable(
  document: OpenApiDocument
): AgentMcpToolRow[] {
  const commandRows = buildAgentSkillCommandTable(document);
  const expectedRows = commandRows.filter(
    (row) => !AGENT_MCP_EXCLUDED_OPERATION_IDS.has(row.operationId)
  );
  const expectedOperationIds = new Set(
    expectedRows.map((row) => row.operationId)
  );
  const missing = expectedRows
    .map((row) => row.operationId)
    .filter((operationId) => AGENT_MCP_TOOL_NAMES[operationId] === undefined);
  const stale = Object.keys(AGENT_MCP_TOOL_NAMES).filter(
    (operationId) => !expectedOperationIds.has(operationId)
  );

  if (missing.length > 0 || stale.length > 0) {
    const details = [
      missing.length > 0 ? `missing: ${missing.join(", ")}` : null,
      stale.length > 0 ? `stale: ${stale.join(", ")}` : null
    ]
      .filter((value): value is string => value !== null)
      .join("; ");
    throw new Error(`Agent MCP tool-name registry drift (${details}).`);
  }

  return expectedRows.map((row) => ({
    ...row,
    tool: AGENT_MCP_TOOL_NAMES[row.operationId]
  }));
}
