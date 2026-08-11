import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import type { RequestHandlerExtra } from "@modelcontextprotocol/sdk/shared/protocol.js";
import type {
  ServerNotification,
  ServerRequest
} from "@modelcontextprotocol/sdk/types.js";
import { z } from "@hono/zod-openapi";

import { authenticateAgentOperation } from "./agent-auth.js";
import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema,
  type AgentApiKeyStore,
  type AuthenticatedAgent
} from "./agent-api-keys.js";
import {
  AgentCatalogUnavailableResponseSchema,
  AgentExerciseListQuerySchema,
  AgentExerciseListResponseSchema,
  AgentExerciseResolveQuerySchema,
  AgentExerciseResolveResponseSchema,
  parseAgentExerciseListQuery,
  type AgentCatalogStore
} from "./agent-catalog.js";
import {
  AgentDoseValidationErrorResponseSchema,
  AgentDoseValidationRequestSchema,
  AgentDoseValidationResponseSchema,
  AgentSetValidationErrorResponseSchema,
  AgentSetValidationRequestSchema,
  AgentSetValidationResponseSchema,
  doseValidationLimitsResponse,
  setValidationLimitsResponse,
  validateAgentDose,
  validateAgentSet
} from "./agent-validation.js";
import {
  AgentExerciseAnalyticsParamsSchema,
  AgentExerciseAnalyticsQuerySchema,
  AgentExerciseAnalyticsResponseSchema,
  AgentHistorySetsQuerySchema,
  AgentHistorySetsResponseSchema,
  AgentMonitoringActivityNotFoundResponseSchema,
  AgentMonitoringActivityParamsSchema,
  AgentMonitoringActivityResponseSchema,
  AgentReadExerciseNotFoundResponseSchema,
  AgentReadUnavailableResponseSchema,
  AgentWorkoutDetailNotFoundResponseSchema,
  AgentWorkoutDetailParamsSchema,
  AgentWorkoutDetailResponseSchema,
  AgentWorkoutListQuerySchema,
  AgentWorkoutListResponseSchema,
  buildAgentExerciseAnalyticsResponse,
  type AgentReadStore
} from "./agent-read-surface.js";
import {
  AgentWorkoutBatchWriteErrorResponseSchema,
  AgentWorkoutBatchWriteRequestSchema,
  AgentWorkoutBatchWriteResponseSchema,
  AgentWorkoutBatchWriteUnavailableResponseSchema,
  prepareAgentWorkoutBatchWrite,
  type AgentWorkoutBatchWriteStore
} from "./agent-workout-batch-write.js";
import {
  AgentExerciseCatalogBatchWriteErrorResponseSchema,
  AgentExerciseCatalogBatchWriteRequestSchema,
  AgentExerciseCatalogBatchWriteResponseSchema,
  AgentExerciseCatalogBatchWriteUnavailableResponseSchema,
  prepareAgentExerciseCatalogBatchWrite,
  type AgentExerciseCatalogBatchWriteStore
} from "./agent-exercise-catalog-batch-write.js";
import {
  AgentMealBatchWriteErrorResponseSchema,
  AgentMealBatchWriteRequestSchema,
  AgentMealBatchWriteResponseSchema,
  AgentMealBatchWriteUnavailableResponseSchema,
  prepareAgentMealBatchWrite,
  type AgentMealBatchWriteStore
} from "./agent-meal-batch-write.js";
import {
  AgentFoodBatchWriteErrorResponseSchema,
  AgentFoodBatchWriteRequestSchema,
  AgentFoodBatchWriteResponseSchema,
  AgentFoodListQuerySchema,
  AgentFoodListResponseSchema,
  AgentFoodPlatformSearchQuerySchema,
  AgentFoodPlatformSearchResponseSchema,
  AgentFoodsUnavailableResponseSchema,
  nutrientValidationLimitsForFoods,
  parseAgentFoodListQuery,
  prepareAgentFoodBatchWrite,
  searchAgentPlatformFoods,
  type AgentFoodBatchWriteStore,
  type AgentFoodCatalogStore
} from "./agent-foods.js";
import {
  AgentMetricBatchWriteErrorResponseSchema,
  AgentMetricBatchWriteRequestSchema,
  AgentMetricBatchWriteResponseSchema,
  AgentMetricListQuerySchema,
  AgentMetricListResponseSchema,
  AgentMetricReadingsQuerySchema,
  AgentMetricReadingsResponseSchema,
  AgentMetricUnavailableResponseSchema,
  type AgentMetricStore
} from "./agent-metrics.js";
import {
  AgentActivityBatchNotFoundResponseSchema,
  AgentActivityListQuerySchema,
  AgentActivityListResponseSchema,
  AgentActivityUnavailableResponseSchema,
  AgentActivityUndoBatchRequestSchema,
  AgentActivityUndoBatchResponseSchema,
  type AgentActivityStore
} from "./agent-activity.js";
import {
  AgentNutritionGoalBatchWriteErrorResponseSchema,
  AgentNutritionGoalBatchWriteRequestSchema,
  AgentNutritionGoalBatchWriteResponseSchema,
  AgentNutritionGoalListResponseSchema,
  AgentNutritionGoalUnavailableResponseSchema,
  type AgentNutritionGoalBatchWriteStore
} from "./agent-nutrition-goals.js";
import {
  AgentSettingsBatchWriteErrorResponseSchema,
  AgentSettingsBatchWriteRequestSchema,
  AgentSettingsBatchWriteResponseSchema,
  AgentSettingsReadResponseSchema,
  AgentSettingsUnavailableResponseSchema,
  type AgentSettingsBatchWriteStore
} from "./agent-settings.js";
import {
  agentPlanInvalidCursorResponse,
  AgentPlanDetailQuerySchema,
  AgentPlanInvalidCursorError,
  AgentPlanNotFoundResponseSchema,
  AgentPlanReadUnavailableResponseSchema,
  AgentRoutineDetailQuerySchema,
  AgentRoutineDetailResponseSchema,
  AgentRoutineListQuerySchema,
  AgentRoutineListResponseSchema,
  AgentRoutineParamsSchema,
  AgentWorkoutTemplateDetailResponseSchema,
  AgentWorkoutTemplateListQuerySchema,
  AgentWorkoutTemplateListResponseSchema,
  AgentWorkoutTemplateParamsSchema,
  type AgentPlanReadStore
} from "./agent-plan-reads.js";
import {
  AgentPlanTreeBatchWriteErrorResponseSchema,
  AgentPlanTreeBatchWriteRequestSchema,
  AgentPlanTreeBatchWriteResponseSchema,
  AgentPlanTreeBatchWriteUnavailableResponseSchema,
  runAgentPlanTreeBatchWrite,
  type AgentPlanTreeBatchWriteStore
} from "./agent-plan-tree-batch-write.js";
import {
  AgentPlanMaterializeRequestSchema,
  AgentPlanMaterializeResponseSchema,
  runAgentPlanMaterializeForAgent,
  type AgentPlanMaterializeStore
} from "./agent-plan-materialize.js";
import {
  AgentPlanCaptureRequestSchema,
  AgentPlanCaptureResponseSchema,
  AgentPlanUpdateFromWorkoutRequestSchema,
  AgentPlanUpdateFromWorkoutResponseSchema,
  runAgentPlanCaptureForAgent,
  runAgentPlanUpdateFromWorkoutForAgent,
  type AgentPlanCaptureStore
} from "./agent-plan-capture.js";
import {
  AgentCompoundBatchWriteRequestSchema,
  AgentCompoundBatchWriteResponseSchema,
  AgentCompoundListQuerySchema,
  AgentCompoundListResponseSchema,
  AgentDoseBatchWriteErrorResponseSchema,
  AgentDoseBatchWriteRequestSchema,
  AgentDoseBatchWriteResponseSchema,
  AgentDoseListQuerySchema,
  AgentDoseListResponseSchema,
  AgentEffectWindowErrorResponseSchema,
  AgentEffectWindowQuerySchema,
  AgentEffectWindowResponseSchema,
  AgentProtocolBatchWriteRequestSchema,
  AgentProtocolBatchWriteResponseSchema,
  AgentProtocolListQuerySchema,
  AgentProtocolListResponseSchema,
  AgentProtocolsBatchWriteErrorResponseSchema,
  AgentProtocolsUnavailableResponseSchema,
  agentProtocolsBatchRequestFingerprint,
  agentProtocolsWriteFailure,
  finalizeAgentDoseBatchWriteResults,
  finalizeAgentProtocolsEntityBatchWriteResults,
  prepareAgentCompoundBatchWrite,
  prepareAgentDoseBatchWrite,
  prepareAgentProtocolBatchWrite,
  type AgentProtocolsStore
} from "./agent-protocols.js";
import { nutrientValidationLimitsResponse } from "./agent-validation.js";
import {
  AgentMealListQuerySchema,
  AgentMealListResponseSchema,
  AgentNutritionReadUnavailableResponseSchema,
  AgentNutritionReadInvalidRangeResponseSchema,
  AgentNutritionTotalsQuerySchema,
  AgentNutritionTotalsResponseSchema,
  AgentNutritionTrendsQuerySchema,
  AgentNutritionTrendsResponseSchema,
  buildAgentNutritionTotalsResponse,
  buildAgentNutritionTrendsResponse,
  goalTargetsFromQuery,
  resolveNutritionGoalTargets,
  validateNutritionRange,
  type AgentNutritionGoalSource,
  type AgentNutritionReadStore
} from "./agent-nutrition-reads.js";
import {
  nutrientDefaultUnit,
  type NutrientId,
  type NutrientUnit
} from "./analytics/nutrition-analytics.js";
import {
  AgentEnergyBalanceQuerySchema,
  AgentEnergyBalanceResponseSchema,
  AgentTrainingDayNutritionQuerySchema,
  AgentTrainingDayNutritionResponseSchema,
  buildAgentEnergyBalanceResponse,
  buildAgentTrainingDayNutritionResponse,
  validateCrossDomainRange,
  type AgentCrossDomainReadStore
} from "./agent-cross-domain-reads.js";
import {
  RateLimitExceededResponseSchema,
  rateLimitRetryAfterSeconds,
  type RateLimitBackend
} from "./rate-limit.js";
import type { RequestLogger } from "./app.js";
import type { SyncNudgePublisher } from "./sync-nudge.js";

export const AGENT_MCP_SERVER_NAME = "perennia-agent";

// Deprecated ('s MCP transport section): the canonical way to
// authenticate a tool call is the `Authorization: Bearer <agent key>` header
// on the transport (populates extra.authInfo.token, read by
// authenticateToolCall below). This field is kept for one deprecation window
// for in-process transports (e.g. InMemoryTransport in tests) that have no
// HTTP request to carry a header on, and is not read by anything reachable
// over the network — the /mcp HTTP mount always carries the key in the
// header, never in tool arguments.
const AgentMcpAuthFieldsSchema = z.object({
  apiKey: z.string().min(1).optional().openapi({
    description:
      "Deprecated: use the Authorization: Bearer <agent key> transport header instead. " +
      "Kept for one deprecation window for in-process transports (e.g. tests) that have " +
      "no HTTP request to carry a header on. When both are present this field takes " +
      "precedence, matching the pre-header behavior; new integrations should rely on the " +
      "header exclusively."
  })
});

export const AgentMcpValidateSetInputSchema = AgentMcpAuthFieldsSchema.extend({
  request: AgentSetValidationRequestSchema
}).openapi("AgentMcpValidateSetInput");

export const AgentMcpValidateDoseInputSchema = AgentMcpAuthFieldsSchema.extend({
  request: AgentDoseValidationRequestSchema
}).openapi("AgentMcpValidateDoseInput");

export const AgentMcpExerciseResolveInputSchema = AgentMcpAuthFieldsSchema.extend({
  query: AgentExerciseResolveQuerySchema
}).openapi("AgentMcpExerciseResolveInput");

export const AgentMcpExerciseListInputSchema = AgentMcpAuthFieldsSchema.extend({
  query: AgentExerciseListQuerySchema.optional()
}).openapi("AgentMcpExerciseListInput");

export const AgentMcpWorkoutBatchWriteInputSchema =
  AgentMcpAuthFieldsSchema.extend({
    request: AgentWorkoutBatchWriteRequestSchema
  }).openapi("AgentMcpWorkoutBatchWriteInput");

export const AgentMcpExerciseCatalogBatchWriteInputSchema =
  AgentMcpAuthFieldsSchema.extend({
    request: AgentExerciseCatalogBatchWriteRequestSchema
  }).openapi("AgentMcpExerciseCatalogBatchWriteInput");

export const AgentMcpExerciseAnalyticsInputSchema =
  AgentMcpAuthFieldsSchema.extend({
    params: AgentExerciseAnalyticsParamsSchema,
    query: AgentExerciseAnalyticsQuerySchema.optional()
  }).openapi("AgentMcpExerciseAnalyticsInput");

export const AgentMcpHistorySetsInputSchema = AgentMcpAuthFieldsSchema.extend({
  query: AgentHistorySetsQuerySchema.optional()
}).openapi("AgentMcpHistorySetsInput");

export const AgentMcpWorkoutListInputSchema = AgentMcpAuthFieldsSchema.extend({
  query: AgentWorkoutListQuerySchema.optional()
}).openapi("AgentMcpWorkoutListInput");

export const AgentMcpWorkoutDetailInputSchema = AgentMcpAuthFieldsSchema.extend({
  params: AgentWorkoutDetailParamsSchema
}).openapi("AgentMcpWorkoutDetailInput");

export const AgentMcpMonitoringActivityInputSchema =
  AgentMcpAuthFieldsSchema.extend({
    params: AgentMonitoringActivityParamsSchema
  }).openapi("AgentMcpMonitoringActivityInput");

export const AgentMcpMealBatchWriteInputSchema = AgentMcpAuthFieldsSchema.extend({
  request: AgentMealBatchWriteRequestSchema
}).openapi("AgentMcpMealBatchWriteInput");

export const AgentMcpMealListInputSchema = AgentMcpAuthFieldsSchema.extend({
  query: AgentMealListQuerySchema.optional()
}).openapi("AgentMcpMealListInput");

export const AgentMcpFoodListInputSchema = AgentMcpAuthFieldsSchema.extend({
  query: AgentFoodListQuerySchema.optional()
}).openapi("AgentMcpFoodListInput");

export const AgentMcpFoodPlatformSearchInputSchema =
  AgentMcpAuthFieldsSchema.extend({
    query: AgentFoodPlatformSearchQuerySchema.optional()
  }).openapi("AgentMcpFoodPlatformSearchInput");

export const AgentMcpFoodBatchWriteInputSchema = AgentMcpAuthFieldsSchema.extend(
  {
    request: AgentFoodBatchWriteRequestSchema
  }
).openapi("AgentMcpFoodBatchWriteInput");

export const AgentMcpMetricListInputSchema = AgentMcpAuthFieldsSchema.extend({
  query: AgentMetricListQuerySchema.optional()
}).openapi("AgentMcpMetricListInput");

export const AgentMcpMetricReadingsInputSchema = AgentMcpAuthFieldsSchema.extend({
  query: AgentMetricReadingsQuerySchema.optional()
}).openapi("AgentMcpMetricReadingsInput");

export const AgentMcpMetricBatchWriteInputSchema =
  AgentMcpAuthFieldsSchema.extend({
    request: AgentMetricBatchWriteRequestSchema
  }).openapi("AgentMcpMetricBatchWriteInput");

export const AgentMcpActivityListInputSchema = AgentMcpAuthFieldsSchema.extend({
  query: AgentActivityListQuerySchema.optional()
}).openapi("AgentMcpActivityListInput");

export const AgentMcpActivityUndoBatchInputSchema =
  AgentMcpAuthFieldsSchema.extend({
    request: AgentActivityUndoBatchRequestSchema
  }).openapi("AgentMcpActivityUndoBatchInput");

export const AgentMcpNutritionTotalsInputSchema =
  AgentMcpAuthFieldsSchema.extend({
    query: AgentNutritionTotalsQuerySchema
  }).openapi("AgentMcpNutritionTotalsInput");

export const AgentMcpNutritionTrendsInputSchema =
  AgentMcpAuthFieldsSchema.extend({
    query: AgentNutritionTrendsQuerySchema
  }).openapi("AgentMcpNutritionTrendsInput");

export const AgentMcpEnergyBalanceInputSchema = AgentMcpAuthFieldsSchema.extend({
  query: AgentEnergyBalanceQuerySchema
}).openapi("AgentMcpEnergyBalanceInput");

export const AgentMcpTrainingDayNutritionInputSchema =
  AgentMcpAuthFieldsSchema.extend({
    query: AgentTrainingDayNutritionQuerySchema
  }).openapi("AgentMcpTrainingDayNutritionInput");

export const AgentMcpNutritionGoalListInputSchema =
  AgentMcpAuthFieldsSchema.openapi("AgentMcpNutritionGoalListInput");

export const AgentMcpNutritionGoalBatchWriteInputSchema =
  AgentMcpAuthFieldsSchema.extend({
    request: AgentNutritionGoalBatchWriteRequestSchema
  }).openapi("AgentMcpNutritionGoalBatchWriteInput");

export const AgentMcpSettingsReadInputSchema =
  AgentMcpAuthFieldsSchema.openapi("AgentMcpSettingsReadInput");

export const AgentMcpSettingsBatchWriteInputSchema =
  AgentMcpAuthFieldsSchema.extend({
    request: AgentSettingsBatchWriteRequestSchema
  }).openapi("AgentMcpSettingsBatchWriteInput");

// New tools authenticate only through the transport Authorization header.
// They deliberately do not inherit the deprecated apiKey argument.
export const AgentMcpWorkoutTemplateListInputSchema = z
  .object({
    query: AgentWorkoutTemplateListQuerySchema.optional()
  })
  .openapi("AgentMcpWorkoutTemplateListInput");

export const AgentMcpWorkoutTemplateDetailInputSchema = z
  .object({
    params: AgentWorkoutTemplateParamsSchema,
    query: AgentPlanDetailQuerySchema.optional()
  })
  .openapi("AgentMcpWorkoutTemplateDetailInput");

export const AgentMcpRoutineListInputSchema = z
  .object({
    query: AgentRoutineListQuerySchema.optional()
  })
  .openapi("AgentMcpRoutineListInput");

export const AgentMcpRoutineDetailInputSchema = z
  .object({
    params: AgentRoutineParamsSchema,
    query: AgentRoutineDetailQuerySchema.optional()
  })
  .openapi("AgentMcpRoutineDetailInput");

export const AgentMcpPlanTreeBatchWriteInputSchema = z
  .object({
    request: AgentPlanTreeBatchWriteRequestSchema
  })
  .openapi("AgentMcpPlanTreeBatchWriteInput");

export const AgentMcpPlanMaterializeInputSchema = z
  .object({
    request: AgentPlanMaterializeRequestSchema
  })
  .openapi("AgentMcpPlanMaterializeInput");

export const AgentMcpPlanCaptureInputSchema = z
  .object({
    request: AgentPlanCaptureRequestSchema
  })
  .openapi("AgentMcpPlanCaptureInput");

export const AgentMcpPlanUpdateFromWorkoutInputSchema = z
  .object({
    request: AgentPlanUpdateFromWorkoutRequestSchema
  })
  .openapi("AgentMcpPlanUpdateFromWorkoutInput");

export const AgentMcpCompoundListInputSchema = AgentMcpAuthFieldsSchema.extend({
  query: AgentCompoundListQuerySchema.optional()
}).openapi("AgentMcpCompoundListInput");

export const AgentMcpProtocolListInputSchema = AgentMcpAuthFieldsSchema.extend({
  query: AgentProtocolListQuerySchema.optional()
}).openapi("AgentMcpProtocolListInput");

export const AgentMcpDoseListInputSchema = AgentMcpAuthFieldsSchema.extend({
  query: AgentDoseListQuerySchema.optional()
}).openapi("AgentMcpDoseListInput");

export const AgentMcpEffectWindowInputSchema = AgentMcpAuthFieldsSchema.extend({
  query: AgentEffectWindowQuerySchema
}).openapi("AgentMcpEffectWindowInput");

export const AgentMcpDoseBatchWriteInputSchema = AgentMcpAuthFieldsSchema.extend({
  request: AgentDoseBatchWriteRequestSchema
}).openapi("AgentMcpDoseBatchWriteInput");

export const AgentMcpCompoundBatchWriteInputSchema =
  AgentMcpAuthFieldsSchema.extend({
    request: AgentCompoundBatchWriteRequestSchema
  }).openapi("AgentMcpCompoundBatchWriteInput");

export const AgentMcpProtocolBatchWriteInputSchema =
  AgentMcpAuthFieldsSchema.extend({
    request: AgentProtocolBatchWriteRequestSchema
  }).openapi("AgentMcpProtocolBatchWriteInput");

export type AgentMcpServerOptions = {
  agentApiKeyStore?: AgentApiKeyStore;
  agentCatalogStore?: AgentCatalogStore;
  agentReadStore?: AgentReadStore;
  agentWorkoutBatchWriteStore?: AgentWorkoutBatchWriteStore;
  agentExerciseCatalogBatchWriteStore?: AgentExerciseCatalogBatchWriteStore;
  agentMealBatchWriteStore?: AgentMealBatchWriteStore;
  agentFoodCatalogStore?: AgentFoodCatalogStore;
  agentFoodBatchWriteStore?: AgentFoodBatchWriteStore;
  agentMetricStore?: AgentMetricStore;
  agentActivityStore?: AgentActivityStore;
  agentProtocolsStore?: AgentProtocolsStore;
  agentNutritionReadStore?: AgentNutritionReadStore;
  agentNutritionGoalStore?: AgentNutritionGoalBatchWriteStore;
  agentSettingsStore?: AgentSettingsBatchWriteStore;
  agentPlanReadStore?: AgentPlanReadStore;
  agentPlanTreeBatchWriteStore?: AgentPlanTreeBatchWriteStore;
  agentPlanMaterializeStore?: AgentPlanMaterializeStore;
  agentPlanCaptureStore?: AgentPlanCaptureStore;
  agentCrossDomainReadStore?: AgentCrossDomainReadStore;
  logger?: RequestLogger;
  rateLimitBackend?: RateLimitBackend;
  syncNudgePublisher?: SyncNudgePublisher;
  version?: string;
};

type ToolExtra = RequestHandlerExtra<ServerRequest, ServerNotification>;

export function createAgentMcpServer({
  agentApiKeyStore,
  agentCatalogStore,
  agentReadStore,
  agentWorkoutBatchWriteStore,
  agentExerciseCatalogBatchWriteStore,
  agentMealBatchWriteStore,
  agentFoodCatalogStore,
  agentFoodBatchWriteStore,
  agentMetricStore,
  agentActivityStore,
  agentProtocolsStore,
  agentNutritionReadStore,
  agentNutritionGoalStore,
  agentSettingsStore,
  agentPlanReadStore,
  agentPlanTreeBatchWriteStore,
  agentPlanMaterializeStore,
  agentPlanCaptureStore,
  agentCrossDomainReadStore,
  logger = { info() {}, error() {} },
  rateLimitBackend,
  syncNudgePublisher,
  version = "0.0.0"
}: AgentMcpServerOptions = {}) {
  const server = new McpServer(
    {
      name: AGENT_MCP_SERVER_NAME,
      version
    },
    {
      capabilities: {
        tools: {
          listChanged: true
        }
      }
    }
  );

  const resolveAgentPlanReadTool = async (extra: ToolExtra) => {
    const auth = await authenticateToolCall({
      apiKey: undefined,
      extra,
      agentApiKeyStore,
      logger,
      rateLimitBackend
    });
    if (auth.status !== "authenticated") {
      return auth;
    }
    if (agentPlanReadStore === undefined) {
      return {
        status: "error" as const,
        result: errorResult(
          AgentPlanReadUnavailableResponseSchema.parse({
            code: "agent_plan_read_unavailable",
            message: "Agent plan read storage is not configured."
          })
        )
      };
    }
    return {
      status: "authenticated" as const,
      agent: auth.agent,
      store: agentPlanReadStore
    };
  };

  server.registerTool(
    "agent_validate_set",
    {
      title: "Validate Agent Set",
      description:
        "Validate one candidate logged set with the same two-tier module used by REST.",
      inputSchema: AgentMcpValidateSetInputSchema,
      outputSchema: AgentSetValidationResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }

      const result = validateAgentSet(input.request);
      const limits = setValidationLimitsResponse();
      if (result.errors.length > 0) {
        return errorResult(
          AgentSetValidationErrorResponseSchema.parse({
            code: "agent_set_validation_failed",
            message: "Set failed hard validation.",
            errors: result.errors,
            warnings: result.warnings,
            limits
          })
        );
      }

      return successResult(
        AgentSetValidationResponseSchema.parse({
          accepted: true,
          warnings: result.warnings,
          limits
        })
      );
    }
  );

  server.registerTool(
    "agent_validate_dose",
    {
      title: "Validate Agent Dose",
      description:
        "Validate one candidate logged Dose with the same neutral, two-tier module used by REST (PROTOCOLS.md, no substance type/legality categorization).",
      inputSchema: AgentMcpValidateDoseInputSchema,
      outputSchema: AgentDoseValidationResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }

      const result = validateAgentDose(input.request);
      const limits = doseValidationLimitsResponse();
      if (result.errors.length > 0) {
        return errorResult(
          AgentDoseValidationErrorResponseSchema.parse({
            code: "agent_dose_validation_failed",
            message: "Dose failed hard validation.",
            errors: result.errors,
            warnings: result.warnings,
            limits
          })
        );
      }

      return successResult(
        AgentDoseValidationResponseSchema.parse({
          accepted: true,
          warnings: result.warnings,
          limits
        })
      );
    }
  );

  server.registerTool(
    "agent_resolve_exercise",
    {
      title: "Resolve Agent Exercise",
      description:
        "Resolve an Exercise name through the same User Library over Platform Library catalog path as REST.",
      inputSchema: AgentMcpExerciseResolveInputSchema,
      outputSchema: AgentExerciseResolveResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentCatalogStore === undefined) {
        return errorResult(
          AgentCatalogUnavailableResponseSchema.parse({
            code: "agent_catalog_unavailable",
            message: "Agent Exercise catalog storage is not configured."
          })
        );
      }

      return successResult(
        AgentExerciseResolveResponseSchema.parse(
          await agentCatalogStore.resolveExerciseName({
            userId: auth.agent.userId,
            name: input.query.name,
            candidateLimit: input.query.candidateLimit
          })
        )
      );
    }
  );

  server.registerTool(
    "agent_list_exercises",
    {
      title: "List Agent Exercises",
      description:
        "List the caller's resolvable Exercise catalog with the same query contract as REST.",
      inputSchema: AgentMcpExerciseListInputSchema,
      outputSchema: AgentExerciseListResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentCatalogStore === undefined) {
        return errorResult(
          AgentCatalogUnavailableResponseSchema.parse({
            code: "agent_catalog_unavailable",
            message: "Agent Exercise catalog storage is not configured."
          })
        );
      }

      const query = parseAgentExerciseListQuery(
        AgentExerciseListQuerySchema.parse(input.query ?? {})
      );
      return successResult(
        AgentExerciseListResponseSchema.parse(
          await agentCatalogStore.listExercises({
            userId: auth.agent.userId,
            ...query
          })
        )
      );
    }
  );

  server.registerTool(
    "agent_batch_write_workout",
    {
      title: "Batch Write Agent Workout",
      description:
        "Apply an agent Workout batch through the same validation, Activity Log, and sync-nudge path as REST.",
      inputSchema: AgentMcpWorkoutBatchWriteInputSchema,
      outputSchema: AgentWorkoutBatchWriteResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentCatalogStore === undefined) {
        return errorResult(
          AgentCatalogUnavailableResponseSchema.parse({
            code: "agent_catalog_unavailable",
            message: "Agent Exercise catalog storage is not configured."
          })
        );
      }
      if (agentWorkoutBatchWriteStore === undefined) {
        return errorResult(
          AgentWorkoutBatchWriteUnavailableResponseSchema.parse({
            code: "agent_batch_write_unavailable",
            message: "Agent workout batch write storage is not configured."
          })
        );
      }

      return writeWorkoutBatchToolResult({
        agent: auth.agent,
        agentCatalogStore,
        agentWorkoutBatchWriteStore,
        logger,
        request: input.request,
        syncNudgePublisher
      });
    }
  );

  server.registerTool(
    "agent_batch_write_exercise_catalog",
    {
      title: "Batch Write Agent Exercise Catalog",
      description:
        "Create, edit, archive, restore, and favorite User Library Exercises and Categories through the same validation, reference resolution, Activity Log, and sync-nudge path as REST. Platform Library rows are never mutable through this op.",
      inputSchema: AgentMcpExerciseCatalogBatchWriteInputSchema,
      outputSchema: AgentExerciseCatalogBatchWriteResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentCatalogStore === undefined) {
        return errorResult(
          AgentCatalogUnavailableResponseSchema.parse({
            code: "agent_catalog_unavailable",
            message: "Agent Exercise catalog storage is not configured."
          })
        );
      }
      if (agentExerciseCatalogBatchWriteStore === undefined) {
        return errorResult(
          AgentExerciseCatalogBatchWriteUnavailableResponseSchema.parse({
            code: "agent_exercise_catalog_batch_write_unavailable",
            message:
              "Agent Exercise catalog batch write storage is not configured."
          })
        );
      }

      return writeExerciseCatalogBatchToolResult({
        agent: auth.agent,
        agentCatalogStore,
        agentExerciseCatalogBatchWriteStore,
        logger,
        request: input.request,
        syncNudgePublisher
      });
    }
  );

  server.registerTool(
    "agent_get_exercise_analytics",
    {
      title: "Get Agent Exercise Analytics",
      description:
        "Read computed analytics for one Exercise through the same on-demand path as REST.",
      inputSchema: AgentMcpExerciseAnalyticsInputSchema,
      outputSchema: AgentExerciseAnalyticsResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentCatalogStore === undefined) {
        return errorResult(
          AgentCatalogUnavailableResponseSchema.parse({
            code: "agent_catalog_unavailable",
            message: "Agent Exercise catalog storage is not configured."
          })
        );
      }
      if (agentReadStore === undefined) {
        return errorResult(
          AgentReadUnavailableResponseSchema.parse({
            code: "agent_read_unavailable",
            message: "Agent read storage is not configured."
          })
        );
      }

      const query = AgentExerciseAnalyticsQuerySchema.parse(input.query ?? {});
      const exercise = await agentCatalogStore.getExerciseById({
        userId: auth.agent.userId,
        exerciseId: input.params.exerciseId
      });
      if (exercise === null) {
        return errorResult(
          AgentReadExerciseNotFoundResponseSchema.parse({
            code: "agent_exercise_not_found",
            message: "Exercise is not visible to the authenticated account."
          })
        );
      }

      const sets = await agentReadStore.readExerciseSets({
        userId: auth.agent.userId,
        exerciseId: input.params.exerciseId,
        from: query.from,
        to: query.to
      });

      return successResult(
        AgentExerciseAnalyticsResponseSchema.parse(
          buildAgentExerciseAnalyticsResponse({
            exercise,
            maxPoints: query.maxPoints,
            sets
          })
        )
      );
    }
  );

  server.registerTool(
    "agent_list_history_sets",
    {
      title: "List Agent History Sets",
      description:
        "List a bounded page of raw logged sets through the same filtered read path as REST.",
      inputSchema: AgentMcpHistorySetsInputSchema,
      outputSchema: AgentHistorySetsResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentReadStore === undefined) {
        return errorResult(
          AgentReadUnavailableResponseSchema.parse({
            code: "agent_read_unavailable",
            message: "Agent read storage is not configured."
          })
        );
      }

      return successResult(
        AgentHistorySetsResponseSchema.parse(
          await agentReadStore.listHistory({
            userId: auth.agent.userId,
            query: AgentHistorySetsQuerySchema.parse(input.query ?? {})
          })
        )
      );
    }
  );

  server.registerTool(
    "agent_list_workouts",
    {
      title: "List Agent Workouts",
      description:
        "List a bounded page of synchronized Workout envelopes over a date range, with a legacy Set-only fallback, through the same path as REST. Data-minimizing and bounded by default.",
      inputSchema: AgentMcpWorkoutListInputSchema,
      outputSchema: AgentWorkoutListResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentReadStore === undefined) {
        return errorResult(
          AgentReadUnavailableResponseSchema.parse({
            code: "agent_read_unavailable",
            message: "Agent read storage is not configured."
          })
        );
      }

      return successResult(
        AgentWorkoutListResponseSchema.parse(
          await agentReadStore.listWorkouts({
            userId: auth.agent.userId,
            query: AgentWorkoutListQuerySchema.parse(input.query ?? {})
          })
        )
      );
    }
  );

  server.registerTool(
    "agent_get_workout",
    {
      title: "Get Agent Workout",
      description:
        "Read one Workout with its raw logged Sets, resolved Exercise identities, ordered Workout Exercises, Exercise Groups, Template Link, and explicit authoritative/inferred coverage. Use this before describing a Workout so missing structure is never mistaken for empty structure.",
      inputSchema: AgentMcpWorkoutDetailInputSchema,
      outputSchema: AgentWorkoutDetailResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentReadStore === undefined) {
        return errorResult(
          AgentReadUnavailableResponseSchema.parse({
            code: "agent_read_unavailable",
            message: "Agent read storage is not configured."
          })
        );
      }

      const workout = await agentReadStore.getWorkout({
        userId: auth.agent.userId,
        workoutId: input.params.workoutId
      });
      if (workout === null) {
        return errorResult(
          AgentWorkoutDetailNotFoundResponseSchema.parse({
            code: "agent_workout_not_found",
            message: "Workout is not visible to the authenticated account."
          })
        );
      }

      return successResult(AgentWorkoutDetailResponseSchema.parse(workout));
    }
  );

  server.registerTool(
    "agent_list_workout_templates",
    {
      title: "List Agent Workout Templates",
      description:
        "List a cursor-paginated, projected Workout Template page for finding reusable sessions in a training program or plan, through the same bounded read store as REST.",
      inputSchema: AgentMcpWorkoutTemplateListInputSchema,
      outputSchema: AgentWorkoutTemplateListResponseSchema
    },
    async (input, extra) => {
      const auth = await resolveAgentPlanReadTool(extra);
      if (auth.status !== "authenticated") {
        return auth.result;
      }

      try {
        return successResult(
          await auth.store.listWorkoutTemplates({
            userId: auth.agent.userId,
            query: AgentWorkoutTemplateListQuerySchema.parse(input.query ?? {})
          })
        );
      } catch (error) {
        if (error instanceof AgentPlanInvalidCursorError) {
          return errorResult(agentPlanInvalidCursorResponse());
        }
        throw error;
      }
    }
  );

  server.registerTool(
    "agent_get_workout_template",
    {
      title: "Get Agent Workout Template",
      description:
        "Get one reusable-session Workout Template from a training program or plan, with explicitly capped exercises, Prescriptions, Template Groups, and members through the same read store as REST.",
      inputSchema: AgentMcpWorkoutTemplateDetailInputSchema,
      outputSchema: AgentWorkoutTemplateDetailResponseSchema
    },
    async (input, extra) => {
      const auth = await resolveAgentPlanReadTool(extra);
      if (auth.status !== "authenticated") {
        return auth.result;
      }

      const result = await auth.store.getWorkoutTemplate({
        userId: auth.agent.userId,
        workoutTemplateId: input.params.workoutTemplateId,
        query: AgentPlanDetailQuerySchema.parse(input.query ?? {})
      });
      if (result === null) {
        return errorResult(
          AgentPlanNotFoundResponseSchema.parse({
            code: "agent_workout_template_not_found",
            message: "Workout Template was not found."
          })
        );
      }
      return successResult(result);
    }
  );

  server.registerTool(
    "agent_list_routines",
    {
      title: "List Agent Routines",
      description:
        "List cursor-paginated Routines that organize Workout Templates into a training program or plan, through the same projected bounded read store as REST.",
      inputSchema: AgentMcpRoutineListInputSchema,
      outputSchema: AgentRoutineListResponseSchema
    },
    async (input, extra) => {
      const auth = await resolveAgentPlanReadTool(extra);
      if (auth.status !== "authenticated") {
        return auth.result;
      }

      try {
        return successResult(
          await auth.store.listRoutines({
            userId: auth.agent.userId,
            query: AgentRoutineListQuerySchema.parse(input.query ?? {})
          })
        );
      } catch (error) {
        if (error instanceof AgentPlanInvalidCursorError) {
          return errorResult(agentPlanInvalidCursorResponse());
        }
        throw error;
      }
    }
  );

  server.registerTool(
    "agent_get_routine",
    {
      title: "Get Agent Routine",
      description:
        "Get one training program or plan Routine's bounded Entries, full Cadence slot layout, and Up next derived from Template Links through the same read store as REST. No rotation cursor is stored.",
      inputSchema: AgentMcpRoutineDetailInputSchema,
      outputSchema: AgentRoutineDetailResponseSchema
    },
    async (input, extra) => {
      const auth = await resolveAgentPlanReadTool(extra);
      if (auth.status !== "authenticated") {
        return auth.result;
      }

      const result = await auth.store.getRoutine({
        userId: auth.agent.userId,
        routineId: input.params.routineId,
        query: AgentRoutineDetailQuerySchema.parse(input.query ?? {})
      });
      if (result === null) {
        return errorResult(
          AgentPlanNotFoundResponseSchema.parse({
            code: "agent_routine_not_found",
            message: "Routine was not found."
          })
        );
      }
      return successResult(result);
    }
  );

  server.registerTool(
    "agent_batch_write_plan_tree",
    {
      title: "Batch Write Agent Plan Tree",
      description:
        "Validate, create, edit, restore, or archive an authored training program or plan tree of Workout Templates, Prescriptions, Groups, Routines, and Cadences as one capped atomic Activity Log batch through the same shared validators and sync rails as REST. expectedCounts rejects incomplete serialization before storage; dryRun performs the complete validation and reference-resolution pass without writing or consuming the idempotency key. Hard errors abort the request; soft warnings return per item; replay is idempotent and archive never cascades.",
      inputSchema: AgentMcpPlanTreeBatchWriteInputSchema,
      outputSchema: AgentPlanTreeBatchWriteResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: undefined,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentPlanTreeBatchWriteStore === undefined) {
        return errorResult(
          AgentPlanTreeBatchWriteUnavailableResponseSchema.parse({
            code: "agent_plan_tree_batch_write_unavailable",
            message: "Agent plan-tree batch write storage is not configured."
          })
        );
      }
      const result = await runAgentPlanTreeBatchWrite({
        afterWrite: async ({ applied }) =>
          maybeNudgeAgentWrite({
            syncNudgePublisher,
            logger,
            agent: auth.agent,
            batchId: input.request.idempotencyKey,
            applied
          }),
        catalogStore: agentCatalogStore,
        deviceId: `agent:${auth.agent.keyId}`,
        request: input.request,
        store: agentPlanTreeBatchWriteStore,
        userId: auth.agent.userId
      });
      return result.status === "accepted"
        ? successResult(result.body)
        : errorResult(result.body);
    }
  );

  server.registerTool(
    "agent_materialize_workout_template",
    {
      title: "Materialize Agent Workout Template",
      description:
        "Start one planned training-program session by materializing its Workout Template into a new Workout, capped resolved Sets, and exactly one Template Link through the same idempotent Activity Log and sync-nudge path as REST. copyPrevious resolves from completed history, or zero-values when never performed; Routine/slot provenance advances derived rotation exactly once.",
      inputSchema: AgentMcpPlanMaterializeInputSchema,
      outputSchema: AgentPlanMaterializeResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: undefined,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      const result = await runAgentPlanMaterializeForAgent({
        agent: auth.agent,
        catalogStore: agentCatalogStore,
        logger,
        request: input.request,
        store: agentPlanMaterializeStore,
        syncNudgePublisher
      });
      return result.status === "accepted"
        ? successResult(result.body)
        : errorResult(result.body);
    }
  );

  server.registerTool(
    "agent_capture_workout_template",
    {
      title: "Capture Agent Workout Template",
      description:
        "Save one performed Workout as a new fixed-only reusable Workout Template for a training program or plan, optionally placing it into a Routine collection or Cadence slot. Adjacent identical Sets collapse into repeat, fact annotations are stripped, copyPrevious is never emitted, and the validator-checked mutation uses the same atomic idempotent Activity Log and sync-nudge path as REST.",
      inputSchema: AgentMcpPlanCaptureInputSchema,
      outputSchema: AgentPlanCaptureResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: undefined,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      const result = await runAgentPlanCaptureForAgent({
        agent: auth.agent,
        catalogStore: agentCatalogStore,
        logger,
        request: input.request,
        store: agentPlanCaptureStore,
        syncNudgePublisher
      });
      return result.status === "accepted"
        ? successResult(result.body)
        : errorResult(result.body);
    }
  );

  server.registerTool(
    "agent_update_workout_template_from_workout",
    {
      title: "Update Agent Workout Template From Workout",
      description:
        "Explicitly update a training program or plan by capture-replacing a Workout's linked Template content while preserving Template identity, Routine memberships, Template Links, and matching copyPrevious modes. This is never implicit; the validator-checked replacement uses the same atomic idempotent Activity Log and sync-nudge path as REST.",
      inputSchema: AgentMcpPlanUpdateFromWorkoutInputSchema,
      outputSchema: AgentPlanUpdateFromWorkoutResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: undefined,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      const result = await runAgentPlanUpdateFromWorkoutForAgent({
        agent: auth.agent,
        catalogStore: agentCatalogStore,
        logger,
        request: input.request,
        store: agentPlanCaptureStore,
        syncNudgePublisher
      });
      return result.status === "accepted"
        ? successResult(result.body)
        : errorResult(result.body);
    }
  );

  server.registerTool(
    "agent_get_monitoring_activity",
    {
      title: "Get Agent Monitoring Activity",
      description:
        "Read data-minimized Monitoring Data summaries for one External Activity through the same on-demand, computed path as REST. Omits raw Monitoring Series blobs, raw GPS coordinates, blob paths, encodings, hashes, and samples.",
      inputSchema: AgentMcpMonitoringActivityInputSchema,
      outputSchema: AgentMonitoringActivityResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentReadStore === undefined) {
        return errorResult(
          AgentReadUnavailableResponseSchema.parse({
            code: "agent_read_unavailable",
            message: "Agent read storage is not configured."
          })
        );
      }

      const monitoring = await agentReadStore.readMonitoringActivity({
        userId: auth.agent.userId,
        agentKeyId: auth.agent.keyId,
        externalActivityId: input.params.externalActivityId
      });
      if (monitoring === null) {
        return errorResult(
          AgentMonitoringActivityNotFoundResponseSchema.parse({
            code: "agent_monitoring_activity_not_found",
            message: "External Activity is not visible to the authenticated account."
          })
        );
      }

      return successResult(AgentMonitoringActivityResponseSchema.parse(monitoring));
    }
  );

  server.registerTool(
    "agent_batch_write_meal",
    {
      title: "Batch Write Agent Meal",
      description:
        "Apply an agent Meal / Food Entry / Quick Entry batch through the same validation, Activity Log, and sync-nudge path as REST. Idempotent by idempotency key; no logic fork.",
      inputSchema: AgentMcpMealBatchWriteInputSchema,
      outputSchema: AgentMealBatchWriteResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentMealBatchWriteStore === undefined) {
        return errorResult(
          AgentMealBatchWriteUnavailableResponseSchema.parse({
            code: "agent_meal_batch_write_unavailable",
            message: "Agent meal batch write storage is not configured."
          })
        );
      }

      return writeMealBatchToolResult({
        agent: auth.agent,
        agentMealBatchWriteStore,
        agentFoodCatalogStore,
        logger,
        request: input.request,
        syncNudgePublisher
      });
    }
  );

  server.registerTool(
    "agent_list_meals",
    {
      title: "List Agent Meals",
      description:
        "List a bounded raw Meal (+ Food Entry, when requested) page over a date range through the same read path as REST. Data-minimizing and bounded by default.",
      inputSchema: AgentMcpMealListInputSchema,
      outputSchema: AgentMealListResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentNutritionReadStore === undefined) {
        return errorResult(
          AgentNutritionReadUnavailableResponseSchema.parse({
            code: "agent_nutrition_read_unavailable",
            message: "Agent nutrition read storage is not configured."
          })
        );
      }

      return successResult(
        AgentMealListResponseSchema.parse(
          await agentNutritionReadStore.listMeals({
            userId: auth.agent.userId,
            query: AgentMealListQuerySchema.parse(input.query ?? {})
          })
        )
      );
    }
  );

  server.registerTool(
    "agent_list_foods",
    {
      title: "List Agent Foods",
      description:
        "Search or list the caller's Food library (User Foods and Recipes) through the same bounded, data-minimizing read path as REST. Platform reference data is never in this list — use agent_search_platform_foods for that.",
      inputSchema: AgentMcpFoodListInputSchema,
      outputSchema: AgentFoodListResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentFoodCatalogStore === undefined) {
        return errorResult(
          AgentFoodsUnavailableResponseSchema.parse({
            code: "agent_foods_unavailable",
            message: "Agent Food catalog storage is not configured."
          })
        );
      }

      const query = parseAgentFoodListQuery(
        AgentFoodListQuerySchema.parse(input.query ?? {})
      );
      return successResult(
        AgentFoodListResponseSchema.parse(
          await agentFoodCatalogStore.listFoods({
            userId: auth.agent.userId,
            ...query
          })
        )
      );
    }
  );

  server.registerTool(
    "agent_search_platform_foods",
    {
      title: "Search Agent Platform Foods",
      description:
        "Search the bundled USDA Platform Food reference dataset through the same path as REST — the SAME offline CC0 catalog the app ships, so an agent and the app resolve identical generic-food nutrient facts. Open Food Facts (branded/barcode) is not available through this tool in this slice.",
      inputSchema: AgentMcpFoodPlatformSearchInputSchema,
      outputSchema: AgentFoodPlatformSearchResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }

      const query = AgentFoodPlatformSearchQuerySchema.parse(input.query ?? {});
      return successResult(
        AgentFoodPlatformSearchResponseSchema.parse(
          searchAgentPlatformFoods({ search: query.search, limit: query.limit })
        )
      );
    }
  );

  server.registerTool(
    "agent_batch_write_foods",
    {
      title: "Batch Write Agent Foods",
      description:
        "Create, edit, or archive User Foods and Recipes through the same validation, Activity Log, and sync-nudge path as REST. Idempotent by idempotency key; no logic fork.",
      inputSchema: AgentMcpFoodBatchWriteInputSchema,
      outputSchema: AgentFoodBatchWriteResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentFoodBatchWriteStore === undefined) {
        return errorResult(
          AgentFoodsUnavailableResponseSchema.parse({
            code: "agent_foods_unavailable",
            message: "Agent Food batch write storage is not configured."
          })
        );
      }

      return writeFoodBatchToolResult({
        agent: auth.agent,
        agentFoodBatchWriteStore,
        logger,
        request: input.request,
        syncNudgePublisher
      });
    }
  );

  server.registerTool(
    "agent_list_metrics",
    {
      title: "List Agent Metrics",
      description:
        "List bounded Metric definitions through the same REST contract used by code-mode clients.",
      inputSchema: AgentMcpMetricListInputSchema,
      outputSchema: AgentMetricListResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentMetricStore === undefined) {
        return errorResult(
          AgentMetricUnavailableResponseSchema.parse({
            code: "agent_metric_unavailable",
            message: "Agent Metric storage is not configured."
          })
        );
      }

      return successResult(
        AgentMetricListResponseSchema.parse(
          await agentMetricStore.listMetrics({
            userId: auth.agent.userId,
            query: AgentMetricListQuerySchema.parse(input.query ?? {})
          })
        )
      );
    }
  );

  server.registerTool(
    "agent_list_metric_readings",
    {
      title: "List Agent Metric Readings",
      description:
        "List bounded normalized Metric Readings through the same REST contract used by code-mode clients.",
      inputSchema: AgentMcpMetricReadingsInputSchema,
      outputSchema: AgentMetricReadingsResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentMetricStore === undefined) {
        return errorResult(
          AgentMetricUnavailableResponseSchema.parse({
            code: "agent_metric_unavailable",
            message: "Agent Metric storage is not configured."
          })
        );
      }

      return successResult(
        AgentMetricReadingsResponseSchema.parse(
          await agentMetricStore.listMetricReadings({
            userId: auth.agent.userId,
            query: AgentMetricReadingsQuerySchema.parse(input.query ?? {})
          })
        )
      );
    }
  );

  server.registerTool(
    "agent_batch_write_metrics",
    {
      title: "Batch Write Agent Metrics",
      description:
        "Apply Metric definitions and Metric Readings through the same normalization, Activity Log, and sync-nudge path as REST. Idempotent by idempotency key.",
      inputSchema: AgentMcpMetricBatchWriteInputSchema,
      outputSchema: AgentMetricBatchWriteResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentMetricStore === undefined) {
        return errorResult(
          AgentMetricUnavailableResponseSchema.parse({
            code: "agent_metric_unavailable",
            message: "Agent Metric storage is not configured."
          })
        );
      }

      return writeMetricBatchToolResult({
        agent: auth.agent,
        agentMetricStore,
        logger,
        request: input.request,
        syncNudgePublisher
      });
    }
  );

  server.registerTool(
    "agent_list_activity",
    {
      title: "List Agent Activity Log",
      description:
        "List bounded, cursor-paginated Activity Log batches so the agent can see exactly what changed (accountability), through the same REST contract used by code-mode clients.",
      inputSchema: AgentMcpActivityListInputSchema,
      outputSchema: AgentActivityListResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentActivityStore === undefined) {
        return errorResult(
          AgentActivityUnavailableResponseSchema.parse({
            code: "agent_activity_unavailable",
            message: "Agent Activity Log storage is not configured."
          })
        );
      }

      return successResult(
        AgentActivityListResponseSchema.parse(
          await agentActivityStore.listActivity({
            userId: auth.agent.userId,
            query: AgentActivityListQuerySchema.parse(input.query ?? {})
          })
        )
      );
    }
  );

  server.registerTool(
    "agent_undo_activity_batch",
    {
      title: "Undo Agent Activity Batch",
      description:
        "Revert a prior Activity Log batch by applying its inverse images as a NEW ordinary write batch, through the same Activity Log and sync-nudge path as REST. Rows changed since are skipped and surfaced per row; idempotent by idempotency key; nothing is hard-deleted.",
      inputSchema: AgentMcpActivityUndoBatchInputSchema,
      outputSchema: AgentActivityUndoBatchResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentActivityStore === undefined) {
        return errorResult(
          AgentActivityUnavailableResponseSchema.parse({
            code: "agent_activity_unavailable",
            message: "Agent Activity Log storage is not configured."
          })
        );
      }

      return undoActivityBatchToolResult({
        agent: auth.agent,
        agentActivityStore,
        logger,
        request: input.request,
        syncNudgePublisher
      });
    }
  );

  server.registerTool(
    "agent_get_nutrition_totals",
    {
      title: "Get Agent Nutrition Totals",
      description:
        "Read computed per-Nutrition-Day and period nutrition totals through the same on-demand, data-minimizing path as REST. Never a raw meal-by-meal dump.",
      inputSchema: AgentMcpNutritionTotalsInputSchema,
      outputSchema: AgentNutritionTotalsResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentNutritionReadStore === undefined) {
        return errorResult(
          AgentNutritionReadUnavailableResponseSchema.parse({
            code: "agent_nutrition_read_unavailable",
            message: "Agent nutrition read storage is not configured."
          })
        );
      }

      const query = AgentNutritionTotalsQuerySchema.parse(input.query);
      const range = validateNutritionRange(query.from, query.to);
      if (!range.ok) {
        return errorResult(
          AgentNutritionReadInvalidRangeResponseSchema.parse({
            code: "agent_nutrition_read_invalid_range",
            message: range.message
          })
        );
      }

      const days = await agentNutritionReadStore.readNutritionDays({
        userId: auth.agent.userId,
        from: query.from,
        to: query.to
      });
      const { goals, goalSource } = await resolvedNutritionGoalsForMcp({
        userId: auth.agent.userId,
        query,
        agentNutritionGoalStore
      });

      return successResult(
        AgentNutritionTotalsResponseSchema.parse(
          buildAgentNutritionTotalsResponse({
            from: query.from,
            to: query.to,
            days,
            goals,
            goalSource
          })
        )
      );
    }
  );

  server.registerTool(
    "agent_get_nutrition_trends",
    {
      title: "Get Agent Nutrition Trends",
      description:
        "Read computed per-day nutrition trends and period goal progress through the same on-demand, data-minimizing path as REST. Never a raw meal-by-meal dump.",
      inputSchema: AgentMcpNutritionTrendsInputSchema,
      outputSchema: AgentNutritionTrendsResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentNutritionReadStore === undefined) {
        return errorResult(
          AgentNutritionReadUnavailableResponseSchema.parse({
            code: "agent_nutrition_read_unavailable",
            message: "Agent nutrition read storage is not configured."
          })
        );
      }

      const query = AgentNutritionTrendsQuerySchema.parse(input.query);
      const range = validateNutritionRange(query.from, query.to);
      if (!range.ok) {
        return errorResult(
          AgentNutritionReadInvalidRangeResponseSchema.parse({
            code: "agent_nutrition_read_invalid_range",
            message: range.message
          })
        );
      }

      const days = await agentNutritionReadStore.readNutritionDays({
        userId: auth.agent.userId,
        from: query.from,
        to: query.to
      });
      const { goals, goalSource } = await resolvedNutritionGoalsForMcp({
        userId: auth.agent.userId,
        query,
        agentNutritionGoalStore
      });

      return successResult(
        AgentNutritionTrendsResponseSchema.parse(
          buildAgentNutritionTrendsResponse({
            from: query.from,
            to: query.to,
            days,
            goals,
            goalSource
          })
        )
      );
    }
  );

  server.registerTool(
    "agent_list_nutrition_goals",
    {
      title: "List Agent Nutrition Goals",
      description:
        "List the caller's current per-nutrient Nutrition Goal targets through the same REST contract used by code-mode clients. Goal targets are configuration, never a stored derived total.",
      inputSchema: AgentMcpNutritionGoalListInputSchema,
      outputSchema: AgentNutritionGoalListResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentNutritionGoalStore === undefined) {
        return errorResult(
          AgentNutritionGoalUnavailableResponseSchema.parse({
            code: "agent_nutrition_goal_unavailable",
            message: "Agent Nutrition Goal storage is not configured."
          })
        );
      }

      const goals = await agentNutritionGoalStore.listNutritionGoals({
        userId: auth.agent.userId
      });

      return successResult(
        AgentNutritionGoalListResponseSchema.parse({ goals })
      );
    }
  );

  server.registerTool(
    "agent_batch_write_nutrition_goals",
    {
      title: "Batch Write Agent Nutrition Goals",
      description:
        "Create/update/clear per-nutrient Nutrition Goal targets through the same shared validator, Activity Log, and sync-nudge path as REST. Idempotent by idempotency key.",
      inputSchema: AgentMcpNutritionGoalBatchWriteInputSchema,
      outputSchema: AgentNutritionGoalBatchWriteResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentNutritionGoalStore === undefined) {
        return errorResult(
          AgentNutritionGoalUnavailableResponseSchema.parse({
            code: "agent_nutrition_goal_unavailable",
            message: "Agent Nutrition Goal storage is not configured."
          })
        );
      }

      return writeNutritionGoalBatchToolResult({
        agent: auth.agent,
        agentNutritionGoalStore,
        logger,
        request: input.request,
        syncNudgePublisher
      });
    }
  );

  server.registerTool(
    "agent_read_settings",
    {
      title: "Read Agent Settings",
      description:
        "Read the caller's account-level Settings (theme, unit system, week start, default weight increment, home-screen display, logging-workflow toggles) through the same REST contract used by code-mode clients. Device-level settings (screen-on, crash reporting, auto-backup) are deliberately absent — they have no synced row.",
      inputSchema: AgentMcpSettingsReadInputSchema,
      outputSchema: AgentSettingsReadResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentSettingsStore === undefined) {
        return errorResult(
          AgentSettingsUnavailableResponseSchema.parse({
            code: "agent_settings_unavailable",
            message: "Agent Settings storage is not configured."
          })
        );
      }

      const read = await agentSettingsStore.readSettings({
        userId: auth.agent.userId
      });

      return successResult(
        AgentSettingsReadResponseSchema.parse({
          settings: read.settings,
          updatedAt: read.updatedAt
        })
      );
    }
  );

  server.registerTool(
    "agent_batch_write_settings",
    {
      title: "Batch Write Agent Settings",
      description:
        "Change any subset of the caller's account-level Settings through the same shared two-tier validator, Activity Log, and sync-nudge path as REST. Idempotent by idempotency key. Device-level settings cannot be written — they have no server row.",
      inputSchema: AgentMcpSettingsBatchWriteInputSchema,
      outputSchema: AgentSettingsBatchWriteResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentSettingsStore === undefined) {
        return errorResult(
          AgentSettingsUnavailableResponseSchema.parse({
            code: "agent_settings_unavailable",
            message: "Agent Settings storage is not configured."
          })
        );
      }

      return writeSettingsBatchToolResult({
        agent: auth.agent,
        agentSettingsStore,
        logger,
        request: input.request,
        syncNudgePublisher
      });
    }
  );

  server.registerTool(
    "agent_get_energy_balance",
    {
      title: "Get Agent Energy Balance",
      description:
        "Read computed energy-in vs energy-out balance through the same cross-domain join path as REST. Join-never-merge: no balance value or meal<->workout link is ever written. Never a raw Meal/Reading dump.",
      inputSchema: AgentMcpEnergyBalanceInputSchema,
      outputSchema: AgentEnergyBalanceResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (
        agentNutritionReadStore === undefined ||
        agentCrossDomainReadStore === undefined
      ) {
        return errorResult(
          AgentNutritionReadUnavailableResponseSchema.parse({
            code: "agent_nutrition_read_unavailable",
            message: "Agent cross-domain read storage is not configured."
          })
        );
      }

      const query = AgentEnergyBalanceQuerySchema.parse(input.query);
      const range = validateCrossDomainRange(query.from, query.to);
      if (!range.ok) {
        return errorResult(
          AgentNutritionReadInvalidRangeResponseSchema.parse({
            code: "agent_nutrition_read_invalid_range",
            message: range.message
          })
        );
      }

      const [nutritionDays, caloriesBurned] = await Promise.all([
        agentNutritionReadStore.readNutritionDays({
          userId: auth.agent.userId,
          from: query.from,
          to: query.to
        }),
        agentCrossDomainReadStore.readCaloriesBurnedReadings({
          userId: auth.agent.userId,
          from: query.from,
          to: query.to
        })
      ]);

      return successResult(
        AgentEnergyBalanceResponseSchema.parse(
          buildAgentEnergyBalanceResponse({
            from: query.from,
            to: query.to,
            nutritionDays,
            caloriesBurned
          })
        )
      );
    }
  );

  server.registerTool(
    "agent_get_training_day_nutrition",
    {
      title: "Get Agent Training-Day Nutrition",
      description:
        "Read computed protein-on-training-days cohorts and pre/post-workout fuelling through the same cross-domain join path as REST. Join-never-merge: meal<->workout proximity is computed, never stored. Never a raw Meal/Workout dump.",
      inputSchema: AgentMcpTrainingDayNutritionInputSchema,
      outputSchema: AgentTrainingDayNutritionResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (
        agentNutritionReadStore === undefined ||
        agentCrossDomainReadStore === undefined
      ) {
        return errorResult(
          AgentNutritionReadUnavailableResponseSchema.parse({
            code: "agent_nutrition_read_unavailable",
            message: "Agent cross-domain read storage is not configured."
          })
        );
      }

      const query = AgentTrainingDayNutritionQuerySchema.parse(input.query);
      const range = validateCrossDomainRange(query.from, query.to);
      if (!range.ok) {
        return errorResult(
          AgentNutritionReadInvalidRangeResponseSchema.parse({
            code: "agent_nutrition_read_invalid_range",
            message: range.message
          })
        );
      }

      const [nutritionDays, workouts] = await Promise.all([
        agentNutritionReadStore.readNutritionDays({
          userId: auth.agent.userId,
          from: query.from,
          to: query.to
        }),
        agentCrossDomainReadStore.readWorkoutTimings({
          userId: auth.agent.userId,
          from: query.from,
          to: query.to
        })
      ]);

      return successResult(
        AgentTrainingDayNutritionResponseSchema.parse(
          buildAgentTrainingDayNutritionResponse({
            from: query.from,
            to: query.to,
            nutritionDays,
            workouts,
            preWindowMinutes: query.preWindowMinutes,
            postWindowMinutes: query.postWindowMinutes
          })
        )
      );
    }
  );

  // ----- Protocols agent surface -----

  server.registerTool(
    "agent_list_compounds",
    {
      title: "List Agent Compounds",
      description:
        "List a bounded, data-minimizing page of the caller's Compound library through the same REST read path. A Compound is a neutral tracking template — never categorized by type or legality.",
      inputSchema: AgentMcpCompoundListInputSchema,
      outputSchema: AgentCompoundListResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentProtocolsStore === undefined) {
        return errorResult(
          AgentProtocolsUnavailableResponseSchema.parse({
            code: "agent_protocols_unavailable",
            message: "Agent Protocols storage is not configured."
          })
        );
      }
      return successResult(
        AgentCompoundListResponseSchema.parse(
          await agentProtocolsStore.listCompounds({
            userId: auth.agent.userId,
            query: AgentCompoundListQuerySchema.parse(input.query ?? {})
          })
        )
      );
    }
  );

  server.registerTool(
    "agent_list_protocols",
    {
      title: "List Agent Protocols",
      description:
        "List a bounded page of the caller's Protocols with their member Compounds, Schedules, and target outcomes through the same REST read path. All plan data — never derived analytics.",
      inputSchema: AgentMcpProtocolListInputSchema,
      outputSchema: AgentProtocolListResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentProtocolsStore === undefined) {
        return errorResult(
          AgentProtocolsUnavailableResponseSchema.parse({
            code: "agent_protocols_unavailable",
            message: "Agent Protocols storage is not configured."
          })
        );
      }
      return successResult(
        AgentProtocolListResponseSchema.parse(
          await agentProtocolsStore.listProtocols({
            userId: auth.agent.userId,
            query: AgentProtocolListQuerySchema.parse(input.query ?? {})
          })
        )
      );
    }
  );

  server.registerTool(
    "agent_list_doses",
    {
      title: "List Agent Doses",
      description:
        "List a bounded, date-scoped page of the caller's logged Doses through the same REST read path, filterable by Compound, Protocol tag, and Provenance. Each Dose is a self-describing snapshot.",
      inputSchema: AgentMcpDoseListInputSchema,
      outputSchema: AgentDoseListResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentProtocolsStore === undefined) {
        return errorResult(
          AgentProtocolsUnavailableResponseSchema.parse({
            code: "agent_protocols_unavailable",
            message: "Agent Protocols storage is not configured."
          })
        );
      }
      return successResult(
        AgentDoseListResponseSchema.parse(
          await agentProtocolsStore.listDoses({
            userId: auth.agent.userId,
            query: AgentDoseListQuerySchema.parse(input.query ?? {})
          })
        )
      );
    }
  );

  server.registerTool(
    "agent_read_effect_window",
    {
      title: "Read Agent Effect Window",
      description:
        "Read a descriptive before/during/after summary of one outcome Metric around a Compound's or Protocol's logged Dose timeline over a range, through the same REST path. Aggregates are computed on demand and never stored. Strictly descriptive — never a causal, efficacy, or medical claim.",
      inputSchema: AgentMcpEffectWindowInputSchema,
      outputSchema: AgentEffectWindowResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentProtocolsStore === undefined) {
        return errorResult(
          AgentProtocolsUnavailableResponseSchema.parse({
            code: "agent_protocols_unavailable",
            message: "Agent Protocols storage is not configured."
          })
        );
      }
      const result = await agentProtocolsStore.readEffectWindow({
        userId: auth.agent.userId,
        query: AgentEffectWindowQuerySchema.parse(input.query)
      });
      if (!result.ok) {
        return errorResult(
          AgentEffectWindowErrorResponseSchema.parse({
            code: "agent_effect_window_invalid_request",
            message: result.message
          })
        );
      }
      return successResult(
        AgentEffectWindowResponseSchema.parse(result.value)
      );
    }
  );

  server.registerTool(
    "agent_batch_write_doses",
    {
      title: "Batch Write Agent Doses",
      description:
        "Apply an agent Dose batch through the same shared dose validator, Activity Log, and sync-nudge path as REST. Provenance agent, optional Protocol tag, tombstone supported. Idempotent by idempotency key; no logic fork.",
      inputSchema: AgentMcpDoseBatchWriteInputSchema,
      outputSchema: AgentDoseBatchWriteResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentProtocolsStore === undefined) {
        return errorResult(
          AgentProtocolsUnavailableResponseSchema.parse({
            code: "agent_protocols_unavailable",
            message: "Agent Protocols storage is not configured."
          })
        );
      }
      return writeDoseBatchToolResult({
        agent: auth.agent,
        agentProtocolsStore,
        logger,
        request: input.request,
        syncNudgePublisher
      });
    }
  );

  server.registerTool(
    "agent_batch_write_compounds",
    {
      title: "Batch Write Agent Compounds",
      description:
        "Apply an agent Compound batch through the same Activity Log and sync-nudge path as REST. Create, edit, or archive Compounds. A Compound is a neutral template. Idempotent by idempotency key.",
      inputSchema: AgentMcpCompoundBatchWriteInputSchema,
      outputSchema: AgentCompoundBatchWriteResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentProtocolsStore === undefined) {
        return errorResult(
          AgentProtocolsUnavailableResponseSchema.parse({
            code: "agent_protocols_unavailable",
            message: "Agent Protocols storage is not configured."
          })
        );
      }
      return writeCompoundBatchToolResult({
        agent: auth.agent,
        agentProtocolsStore,
        logger,
        request: input.request,
        syncNudgePublisher
      });
    }
  );

  server.registerTool(
    "agent_batch_write_protocols",
    {
      title: "Batch Write Agent Protocols",
      description:
        "Apply an agent Protocol plan batch (protocols + members + schedules + target outcomes) through the same Activity Log and sync-nudge path as REST. Archive supported. Plan writes never touch logged Doses (no cascade). Idempotent by idempotency key.",
      inputSchema: AgentMcpProtocolBatchWriteInputSchema,
      outputSchema: AgentProtocolBatchWriteResponseSchema
    },
    async (input, extra) => {
      const auth = await authenticateToolCall({
        apiKey: input.apiKey,
        extra,
        agentApiKeyStore,
        logger,
        rateLimitBackend
      });
      if (auth.status !== "authenticated") {
        return auth.result;
      }
      if (agentProtocolsStore === undefined) {
        return errorResult(
          AgentProtocolsUnavailableResponseSchema.parse({
            code: "agent_protocols_unavailable",
            message: "Agent Protocols storage is not configured."
          })
        );
      }
      return writeProtocolBatchToolResult({
        agent: auth.agent,
        agentProtocolsStore,
        logger,
        request: input.request,
        syncNudgePublisher
      });
    }
  );

  return server;
}

async function writeDoseBatchToolResult({
  agent,
  agentProtocolsStore,
  logger,
  request,
  syncNudgePublisher
}: {
  agent: AuthenticatedAgent;
  agentProtocolsStore: AgentProtocolsStore;
  logger: RequestLogger;
  request: z.infer<typeof AgentDoseBatchWriteRequestSchema>;
  syncNudgePublisher?: SyncNudgePublisher;
}): Promise<CallToolResult> {
  const prepared = prepareAgentDoseBatchWrite({ request });
  if (!prepared.accepted) {
    return errorResult(
      AgentDoseBatchWriteErrorResponseSchema.parse({
        code: "agent_dose_batch_write_failed",
        message: "Batch contains one or more hard dose validation failures.",
        errors: prepared.errors,
        warnings: prepared.warnings,
        limits: doseValidationLimitsResponse()
      })
    );
  }
  const sourceDeviceId = `agent:${agent.keyId}`;
  const writeResult = await agentProtocolsStore.writeDoseBatch({
    userId: agent.userId,
    batchId: request.idempotencyKey,
    requestFingerprint: agentProtocolsBatchRequestFingerprint(request),
    deviceId: sourceDeviceId,
    doses: prepared.doses
  });
  const writeFailure = agentProtocolsWriteFailure(writeResult);
  if (writeFailure !== null) {
    return errorResult(writeFailure.body);
  }
  await maybeNudgeAgentWrite({
    syncNudgePublisher,
    logger,
    agent,
    batchId: request.idempotencyKey,
    applied: writeResult.applied.length
  });
  return successResult(
    AgentDoseBatchWriteResponseSchema.parse({
      accepted: true,
      duplicate: writeResult.duplicate,
      idempotencyKey: request.idempotencyKey,
      batchId: request.idempotencyKey,
      serverClock: writeResult.serverClock,
      doses: finalizeAgentDoseBatchWriteResults({
        applied: writeResult.applied,
        accepted: writeResult.accepted,
        duplicate: writeResult.duplicate,
        results: prepared.responseDoses
      })
    })
  );
}

async function writeCompoundBatchToolResult({
  agent,
  agentProtocolsStore,
  logger,
  request,
  syncNudgePublisher
}: {
  agent: AuthenticatedAgent;
  agentProtocolsStore: AgentProtocolsStore;
  logger: RequestLogger;
  request: z.infer<typeof AgentCompoundBatchWriteRequestSchema>;
  syncNudgePublisher?: SyncNudgePublisher;
}): Promise<CallToolResult> {
  const prepared = prepareAgentCompoundBatchWrite({ request });
  if (!prepared.accepted) {
    return errorResult(
      AgentProtocolsBatchWriteErrorResponseSchema.parse({
        code: "agent_protocols_batch_write_failed",
        message: "Batch contains one or more hard validation failures.",
        errors: prepared.errors,
        warnings: []
      })
    );
  }
  const sourceDeviceId = `agent:${agent.keyId}`;
  const writeResult = await agentProtocolsStore.writeCompoundBatch({
    userId: agent.userId,
    batchId: request.idempotencyKey,
    requestFingerprint: agentProtocolsBatchRequestFingerprint(request),
    deviceId: sourceDeviceId,
    compounds: prepared.compounds
  });
  const writeFailure = agentProtocolsWriteFailure(writeResult);
  if (writeFailure !== null) {
    return errorResult(writeFailure.body);
  }
  await maybeNudgeAgentWrite({
    syncNudgePublisher,
    logger,
    agent,
    batchId: request.idempotencyKey,
    applied: writeResult.applied.length
  });
  return successResult(
    AgentCompoundBatchWriteResponseSchema.parse({
      accepted: true,
      duplicate: writeResult.duplicate,
      idempotencyKey: request.idempotencyKey,
      batchId: request.idempotencyKey,
      serverClock: writeResult.serverClock,
      compounds: finalizeAgentProtocolsEntityBatchWriteResults({
        applied: writeResult.applied,
        accepted: writeResult.accepted,
        duplicate: writeResult.duplicate,
        results: prepared.responseCompounds
      })
    })
  );
}

async function writeProtocolBatchToolResult({
  agent,
  agentProtocolsStore,
  logger,
  request,
  syncNudgePublisher
}: {
  agent: AuthenticatedAgent;
  agentProtocolsStore: AgentProtocolsStore;
  logger: RequestLogger;
  request: z.infer<typeof AgentProtocolBatchWriteRequestSchema>;
  syncNudgePublisher?: SyncNudgePublisher;
}): Promise<CallToolResult> {
  const prepared = prepareAgentProtocolBatchWrite({ request });
  if (!prepared.accepted) {
    return errorResult(
      AgentProtocolsBatchWriteErrorResponseSchema.parse({
        code: "agent_protocols_batch_write_failed",
        message: "Batch contains one or more hard validation failures.",
        errors: prepared.errors,
        warnings: []
      })
    );
  }
  const sourceDeviceId = `agent:${agent.keyId}`;
  const writeResult = await agentProtocolsStore.writeProtocolBatch({
    userId: agent.userId,
    batchId: request.idempotencyKey,
    requestFingerprint: agentProtocolsBatchRequestFingerprint(request),
    deviceId: sourceDeviceId,
    protocols: prepared.protocols,
    members: prepared.members,
    schedules: prepared.schedules,
    targetOutcomes: prepared.targetOutcomes
  });
  const writeFailure = agentProtocolsWriteFailure(writeResult);
  if (writeFailure !== null) {
    return errorResult(writeFailure.body);
  }
  await maybeNudgeAgentWrite({
    syncNudgePublisher,
    logger,
    agent,
    batchId: request.idempotencyKey,
    applied: writeResult.applied.length
  });
  return successResult(
    AgentProtocolBatchWriteResponseSchema.parse({
      accepted: true,
      duplicate: writeResult.duplicate,
      idempotencyKey: request.idempotencyKey,
      batchId: request.idempotencyKey,
      serverClock: writeResult.serverClock,
      protocols: finalizeAgentProtocolsEntityBatchWriteResults({
        applied: writeResult.applied,
        accepted: writeResult.accepted,
        duplicate: writeResult.duplicate,
        results: prepared.responseProtocols
      })
    })
  );
}

async function maybeNudgeAgentWrite({
  syncNudgePublisher,
  logger,
  agent,
  batchId,
  applied
}: {
  syncNudgePublisher?: SyncNudgePublisher;
  logger: RequestLogger;
  agent: AuthenticatedAgent;
  batchId: string;
  applied: number;
}) {
  if (syncNudgePublisher === undefined || applied <= 0) {
    return;
  }
  try {
    await syncNudgePublisher.enqueueSyncNudge({
      userId: agent.userId,
      sourceDeviceId: `agent:${agent.keyId}`,
      reason: "agent_write"
    });
  } catch (error) {
    logger.error?.(
      { error, userId: agent.userId, keyId: agent.keyId, batchId },
      "agent sync nudge enqueue failed"
    );
  }
}

async function writeMealBatchToolResult({
  agent,
  agentMealBatchWriteStore,
  agentFoodCatalogStore,
  logger,
  request,
  syncNudgePublisher
}: {
  agent: AuthenticatedAgent;
  agentMealBatchWriteStore: AgentMealBatchWriteStore;
  agentFoodCatalogStore?: AgentFoodCatalogStore;
  logger: RequestLogger;
  request: z.infer<typeof AgentMealBatchWriteRequestSchema>;
  syncNudgePublisher?: SyncNudgePublisher;
}): Promise<CallToolResult> {
  const prepared = await prepareAgentMealBatchWrite({
    request,
    userId: agent.userId,
    foodCatalogStore: agentFoodCatalogStore
  });
  if (!prepared.accepted) {
    return errorResult(
      AgentMealBatchWriteErrorResponseSchema.parse({
        code: "agent_meal_batch_write_failed",
        message: "Batch contains one or more hard validation failures.",
        errors: prepared.errors,
        warnings: prepared.warnings,
        limits: nutrientValidationLimitsResponse()
      })
    );
  }

  const sourceDeviceId = `agent:${agent.keyId}`;
  const writeResult = await agentMealBatchWriteStore.writeMealBatch({
    userId: agent.userId,
    batchId: request.idempotencyKey,
    deviceId: sourceDeviceId,
    meal: prepared.meal,
    entries: prepared.entries
  });

  if (syncNudgePublisher !== undefined && writeResult.applied.length > 0) {
    try {
      await syncNudgePublisher.enqueueSyncNudge({
        userId: agent.userId,
        sourceDeviceId,
        reason: "agent_write"
      });
    } catch (error) {
      logger.error?.(
        {
          error,
          userId: agent.userId,
          keyId: agent.keyId,
          batchId: request.idempotencyKey
        },
        "agent sync nudge enqueue failed"
      );
    }
  }

  return successResult(
    AgentMealBatchWriteResponseSchema.parse({
      accepted: true,
      duplicate: writeResult.duplicate,
      idempotencyKey: request.idempotencyKey,
      batchId: request.idempotencyKey,
      mealId: request.meal.id,
      serverClock: writeResult.serverClock,
      entries: prepared.responseEntries
    })
  );
}

async function writeFoodBatchToolResult({
  agent,
  agentFoodBatchWriteStore,
  logger,
  request,
  syncNudgePublisher
}: {
  agent: AuthenticatedAgent;
  agentFoodBatchWriteStore: AgentFoodBatchWriteStore;
  logger: RequestLogger;
  request: z.infer<typeof AgentFoodBatchWriteRequestSchema>;
  syncNudgePublisher?: SyncNudgePublisher;
}): Promise<CallToolResult> {
  const prepared = prepareAgentFoodBatchWrite({ request });
  if (!prepared.accepted) {
    return errorResult(
      AgentFoodBatchWriteErrorResponseSchema.parse({
        code: "agent_food_batch_write_failed",
        message: "Batch contains one or more hard validation failures.",
        errors: prepared.errors,
        warnings: prepared.warnings,
        limits: nutrientValidationLimitsForFoods()
      })
    );
  }

  const sourceDeviceId = `agent:${agent.keyId}`;
  const writeResult = await agentFoodBatchWriteStore.writeFoodBatch({
    userId: agent.userId,
    batchId: request.idempotencyKey,
    deviceId: sourceDeviceId,
    foods: prepared.foods
  });

  if (syncNudgePublisher !== undefined && writeResult.applied.length > 0) {
    try {
      await syncNudgePublisher.enqueueSyncNudge({
        userId: agent.userId,
        sourceDeviceId,
        reason: "agent_write"
      });
    } catch (error) {
      logger.error?.(
        {
          error,
          userId: agent.userId,
          keyId: agent.keyId,
          batchId: request.idempotencyKey
        },
        "agent sync nudge enqueue failed"
      );
    }
  }

  return successResult(
    AgentFoodBatchWriteResponseSchema.parse({
      accepted: true,
      duplicate: writeResult.duplicate,
      idempotencyKey: request.idempotencyKey,
      batchId: request.idempotencyKey,
      serverClock: writeResult.serverClock,
      foods: prepared.responseFoods
    })
  );
}

async function writeMetricBatchToolResult({
  agent,
  agentMetricStore,
  logger,
  request,
  syncNudgePublisher
}: {
  agent: AuthenticatedAgent;
  agentMetricStore: AgentMetricStore;
  logger: RequestLogger;
  request: z.infer<typeof AgentMetricBatchWriteRequestSchema>;
  syncNudgePublisher?: SyncNudgePublisher;
}): Promise<CallToolResult> {
  const sourceDeviceId = `agent:${agent.keyId}`;
  const writeResult = await agentMetricStore.writeMetricBatch({
    userId: agent.userId,
    batchId: request.idempotencyKey,
    deviceId: sourceDeviceId,
    request
  });

  if (!writeResult.accepted) {
    return errorResult(
      AgentMetricBatchWriteErrorResponseSchema.parse({
        code: "agent_metric_batch_write_failed",
        message: "Batch contains one or more hard Metric validation failures.",
        errors: writeResult.errors,
        warnings: writeResult.warnings
      })
    );
  }

  if (
    syncNudgePublisher !== undefined &&
    writeResult.activityLogEntries > 0
  ) {
    try {
      await syncNudgePublisher.enqueueSyncNudge({
        userId: agent.userId,
        sourceDeviceId,
        reason: "agent_write"
      });
    } catch (error) {
      logger.error?.(
        {
          error,
          userId: agent.userId,
          keyId: agent.keyId,
          batchId: request.idempotencyKey
        },
        "agent sync nudge enqueue failed"
      );
    }
  }

  return successResult(
    AgentMetricBatchWriteResponseSchema.parse({
      accepted: true,
      duplicate: writeResult.duplicate,
      idempotencyKey: request.idempotencyKey,
      batchId: request.idempotencyKey,
      serverClock: writeResult.serverClock,
      metrics: writeResult.metrics,
      readings: writeResult.readings
    })
  );
}

async function undoActivityBatchToolResult({
  agent,
  agentActivityStore,
  logger,
  request,
  syncNudgePublisher
}: {
  agent: AuthenticatedAgent;
  agentActivityStore: AgentActivityStore;
  logger: RequestLogger;
  request: z.infer<typeof AgentActivityUndoBatchRequestSchema>;
  syncNudgePublisher?: SyncNudgePublisher;
}): Promise<CallToolResult> {
  const sourceDeviceId = `agent:${agent.keyId}`;
  const undoResult = await agentActivityStore.undoBatch({
    userId: agent.userId,
    batchId: request.batchId,
    idempotencyKey: request.idempotencyKey,
    deviceId: sourceDeviceId
  });

  if (!undoResult.accepted) {
    return errorResult(
      AgentActivityBatchNotFoundResponseSchema.parse({
        code: "activity_batch_not_found",
        message: "No Activity Log batch with that id is visible to the caller."
      })
    );
  }

  if (syncNudgePublisher !== undefined && undoResult.activityLogEntries > 0) {
    try {
      await syncNudgePublisher.enqueueSyncNudge({
        userId: agent.userId,
        sourceDeviceId,
        reason: "agent_write"
      });
    } catch (error) {
      logger.error?.(
        {
          error,
          userId: agent.userId,
          keyId: agent.keyId,
          batchId: request.idempotencyKey
        },
        "agent sync nudge enqueue failed"
      );
    }
  }

  return successResult(
    AgentActivityUndoBatchResponseSchema.parse({
      accepted: true,
      applied: undoResult.applied,
      duplicate: undoResult.duplicate,
      originalBatchId: request.batchId,
      undoBatchId: undoResult.undoBatchId,
      serverClock: undoResult.serverClock,
      entries: undoResult.entries.map((entry) => ({
        entryId: entry.entryId,
        entityTable: entry.entityTable,
        entityId: entry.entityId,
        outcome: entry.outcome
      }))
    })
  );
}

/**
 * Resolve the goal targets a totals/trends tool call should score against —
 * mirrors app.ts's `resolvedNutritionGoals` REST helper: explicit query-param
 * targets win per-nutrient; any goalable Nutrient the query left unset falls
 * back to the caller's stored Nutrition Goal.
 */
async function resolvedNutritionGoalsForMcp({
  userId,
  query,
  agentNutritionGoalStore
}: {
  userId: string;
  query: {
    energyGoal?: number;
    proteinGoal?: number;
    carbohydrateGoal?: number;
    fatGoal?: number;
  };
  agentNutritionGoalStore: AgentNutritionGoalBatchWriteStore | undefined;
}) {
  const queryGoals = goalTargetsFromQuery(query as Parameters<typeof goalTargetsFromQuery>[0]);
  if (agentNutritionGoalStore === undefined) {
    return {
      goals: queryGoals,
      goalSource: (queryGoals.size > 0 ? "query" : "none") as AgentNutritionGoalSource
    };
  }

  const storedGoalRows = await agentNutritionGoalStore.listNutritionGoals({
    userId
  });
  const storedGoals = new Map<
    NutrientId,
    { nutrient: NutrientId; value: number; unit: NutrientUnit }
  >();
  for (const goal of storedGoalRows) {
    storedGoals.set(goal.nutrient, {
      nutrient: goal.nutrient,
      value: goal.value,
      unit: nutrientUnitOrDefaultForMcp(goal.unit, goal.nutrient)
    });
  }

  return resolveNutritionGoalTargets({ queryGoals, storedGoals });
}

function nutrientUnitOrDefaultForMcp(
  unit: string,
  nutrient: NutrientId
): NutrientUnit {
  return unit === "kilocalorie" ||
    unit === "gram" ||
    unit === "milligram" ||
    unit === "microgram" ||
    unit === "milliliter"
    ? unit
    : nutrientDefaultUnit(nutrient);
}

async function writeNutritionGoalBatchToolResult({
  agent,
  agentNutritionGoalStore,
  logger,
  request,
  syncNudgePublisher
}: {
  agent: AuthenticatedAgent;
  agentNutritionGoalStore: AgentNutritionGoalBatchWriteStore;
  logger: RequestLogger;
  request: z.infer<typeof AgentNutritionGoalBatchWriteRequestSchema>;
  syncNudgePublisher?: SyncNudgePublisher;
}): Promise<CallToolResult> {
  const sourceDeviceId = `agent:${agent.keyId}`;
  const writeResult = await agentNutritionGoalStore.writeNutritionGoalBatch({
    userId: agent.userId,
    batchId: request.idempotencyKey,
    deviceId: sourceDeviceId,
    request
  });

  if (!writeResult.accepted) {
    return errorResult(
      AgentNutritionGoalBatchWriteErrorResponseSchema.parse({
        code: "agent_nutrition_goal_batch_write_failed",
        message:
          "Batch contains one or more hard Nutrition Goal validation failures.",
        errors: writeResult.errors
      })
    );
  }

  if (syncNudgePublisher !== undefined && writeResult.applied.length > 0) {
    try {
      await syncNudgePublisher.enqueueSyncNudge({
        userId: agent.userId,
        sourceDeviceId,
        reason: "agent_write"
      });
    } catch (error) {
      logger.error?.(
        {
          error,
          userId: agent.userId,
          keyId: agent.keyId,
          batchId: request.idempotencyKey
        },
        "agent sync nudge enqueue failed"
      );
    }
  }

  return successResult(
    AgentNutritionGoalBatchWriteResponseSchema.parse({
      accepted: true,
      duplicate: writeResult.duplicate,
      idempotencyKey: request.idempotencyKey,
      batchId: request.idempotencyKey,
      serverClock: writeResult.serverClock,
      targets: writeResult.targets
    })
  );
}

async function writeSettingsBatchToolResult({
  agent,
  agentSettingsStore,
  logger,
  request,
  syncNudgePublisher
}: {
  agent: AuthenticatedAgent;
  agentSettingsStore: AgentSettingsBatchWriteStore;
  logger: RequestLogger;
  request: z.infer<typeof AgentSettingsBatchWriteRequestSchema>;
  syncNudgePublisher?: SyncNudgePublisher;
}): Promise<CallToolResult> {
  const sourceDeviceId = `agent:${agent.keyId}`;
  const writeResult = await agentSettingsStore.writeSettingsBatch({
    userId: agent.userId,
    batchId: request.idempotencyKey,
    deviceId: sourceDeviceId,
    request
  });

  if (!writeResult.accepted) {
    return errorResult(
      AgentSettingsBatchWriteErrorResponseSchema.parse({
        code: "agent_settings_batch_write_failed",
        message:
          "Settings write contains one or more hard validation failures.",
        errors: writeResult.errors
      })
    );
  }

  if (syncNudgePublisher !== undefined && !writeResult.duplicate) {
    try {
      await syncNudgePublisher.enqueueSyncNudge({
        userId: agent.userId,
        sourceDeviceId,
        reason: "agent_write"
      });
    } catch (error) {
      logger.error?.(
        {
          error,
          userId: agent.userId,
          keyId: agent.keyId,
          batchId: request.idempotencyKey
        },
        "agent settings sync nudge enqueue failed"
      );
    }
  }

  return successResult(
    AgentSettingsBatchWriteResponseSchema.parse({
      accepted: true,
      duplicate: writeResult.duplicate,
      idempotencyKey: request.idempotencyKey,
      batchId: request.idempotencyKey,
      serverClock: writeResult.serverClock,
      settings: writeResult.settings,
      updatedAt: writeResult.updatedAt
    })
  );
}

async function writeWorkoutBatchToolResult({
  agent,
  agentCatalogStore,
  agentWorkoutBatchWriteStore,
  logger,
  request,
  syncNudgePublisher
}: {
  agent: AuthenticatedAgent;
  agentCatalogStore: AgentCatalogStore;
  agentWorkoutBatchWriteStore: AgentWorkoutBatchWriteStore;
  logger: RequestLogger;
  request: z.infer<typeof AgentWorkoutBatchWriteRequestSchema>;
  syncNudgePublisher?: SyncNudgePublisher;
}): Promise<CallToolResult> {
  const prepared = await prepareAgentWorkoutBatchWrite({
    catalogStore: agentCatalogStore,
    request,
    userId: agent.userId
  });
  if (!prepared.accepted) {
    return errorResult(
      AgentWorkoutBatchWriteErrorResponseSchema.parse({
        code: "agent_batch_write_failed",
        message:
          "Batch contains one or more hard validation or Exercise resolution failures.",
        errors: prepared.errors,
        warnings: prepared.warnings,
        limits: setValidationLimitsResponse()
      })
    );
  }

  const sourceDeviceId = `agent:${agent.keyId}`;
  const writeResult = await agentWorkoutBatchWriteStore.writeWorkoutBatch({
    userId: agent.userId,
    batchId: request.idempotencyKey,
    deviceId: sourceDeviceId,
    workout: request.workout,
    sets: prepared.sets
  });

  if (syncNudgePublisher !== undefined && writeResult.applied.length > 0) {
    try {
      await syncNudgePublisher.enqueueSyncNudge({
        userId: agent.userId,
        sourceDeviceId,
        reason: "agent_write"
      });
    } catch (error) {
      logger.error?.(
        {
          error,
          userId: agent.userId,
          keyId: agent.keyId,
          batchId: request.idempotencyKey
        },
        "agent sync nudge enqueue failed"
      );
    }
  }

  return successResult(
    AgentWorkoutBatchWriteResponseSchema.parse({
      accepted: true,
      duplicate: writeResult.duplicate,
      idempotencyKey: request.idempotencyKey,
      batchId: request.idempotencyKey,
      workoutId: request.workout.id,
      serverClock: writeResult.serverClock,
      sets: prepared.responseSets
    })
  );
}

async function writeExerciseCatalogBatchToolResult({
  agent,
  agentCatalogStore,
  agentExerciseCatalogBatchWriteStore,
  logger,
  request,
  syncNudgePublisher
}: {
  agent: AuthenticatedAgent;
  agentCatalogStore: AgentCatalogStore;
  agentExerciseCatalogBatchWriteStore: AgentExerciseCatalogBatchWriteStore;
  logger: RequestLogger;
  request: z.infer<typeof AgentExerciseCatalogBatchWriteRequestSchema>;
  syncNudgePublisher?: SyncNudgePublisher;
}): Promise<CallToolResult> {
  const prepared = await prepareAgentExerciseCatalogBatchWrite({
    catalogStore: agentCatalogStore,
    request,
    userId: agent.userId
  });
  if (!prepared.accepted) {
    return errorResult(
      AgentExerciseCatalogBatchWriteErrorResponseSchema.parse({
        code: "agent_exercise_catalog_batch_write_failed",
        message:
          "Batch contains one or more hard validation or reference resolution failures.",
        errors: prepared.errors,
        warnings: prepared.warnings
      })
    );
  }

  const sourceDeviceId = `agent:${agent.keyId}`;
  const writeResult =
    await agentExerciseCatalogBatchWriteStore.writeExerciseCatalogBatch({
      userId: agent.userId,
      batchId: request.idempotencyKey,
      deviceId: sourceDeviceId,
      categories: prepared.categories,
      exercises: prepared.exercises
    });

  if (syncNudgePublisher !== undefined && writeResult.applied.length > 0) {
    try {
      await syncNudgePublisher.enqueueSyncNudge({
        userId: agent.userId,
        sourceDeviceId,
        reason: "agent_write"
      });
    } catch (error) {
      logger.error?.(
        {
          error,
          userId: agent.userId,
          keyId: agent.keyId,
          batchId: request.idempotencyKey
        },
        "agent sync nudge enqueue failed"
      );
    }
  }

  return successResult(
    AgentExerciseCatalogBatchWriteResponseSchema.parse({
      accepted: true,
      duplicate: writeResult.duplicate,
      idempotencyKey: request.idempotencyKey,
      batchId: request.idempotencyKey,
      serverClock: writeResult.serverClock,
      categories: prepared.responseCategories,
      exercises: prepared.responseExercises
    })
  );
}

async function authenticateToolCall({
  apiKey,
  extra,
  agentApiKeyStore,
  logger,
  rateLimitBackend
}: {
  apiKey: string | undefined;
  extra: ToolExtra;
  agentApiKeyStore: AgentApiKeyStore | undefined;
  logger: RequestLogger;
  rateLimitBackend: RateLimitBackend | undefined;
}): Promise<
  | {
      status: "authenticated";
      agent: AuthenticatedAgent;
    }
  | {
      status: "error";
      result: CallToolResult;
    }
> {
  if (agentApiKeyStore === undefined) {
    return {
      status: "error",
      result: errorResult(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        })
      )
    };
  }

  const secret = apiKey ?? extra.authInfo?.token;
  if (secret === undefined || secret.length === 0) {
    return unauthorizedResult();
  }

  const auth = await authenticateAgentOperation({
    secret,
    agentApiKeyStore,
    rateLimitBackend,
    logger
  });
  if (auth.status === "unauthorized") {
    return unauthorizedResult();
  }
  if (auth.status === "rate_limited") {
    return {
      status: "error",
      result: errorResult(
        RateLimitExceededResponseSchema.parse({
          code: "rate_limited",
          message: "Too many requests.",
          limit: auth.decision.limit,
          retryAfterSeconds: rateLimitRetryAfterSeconds(auth.decision)
        })
      )
    };
  }

  return {
    status: "authenticated",
    agent: auth.agent
  };
}

function unauthorizedResult() {
  return {
    status: "error" as const,
    result: errorResult(
      AgentUnauthorizedResponseSchema.parse({
        code: "agent_unauthorized",
        message: "A valid agent API key is required."
      })
    )
  };
}

function successResult(body: Record<string, unknown>): CallToolResult {
  const structuredContent = jsonStructuredContent(body);

  return {
    structuredContent,
    content: [{ type: "text", text: JSON.stringify(structuredContent) }]
  };
}

function errorResult(body: Record<string, unknown>): CallToolResult {
  return {
    ...successResult(body),
    isError: true
  };
}

function jsonStructuredContent(body: Record<string, unknown>): Record<string, unknown> {
  return JSON.parse(JSON.stringify(body)) as Record<string, unknown>;
}
