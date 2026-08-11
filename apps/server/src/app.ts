import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";
import type { Context } from "hono";
import { HTTPException } from "hono/http-exception";
import { StreamableHTTPTransport } from "@hono/mcp";
import type { AuthInfo } from "@modelcontextprotocol/sdk/server/auth/types.js";
import pino from "pino";

import {
  AUTH_DISABLED_MESSAGE,
  type ServerAuth
} from "./auth/index.js";
import { registerCanonicalImportOpenApiSchemas } from "./canonical-import.js";
import {
  agentApiKeyCreateRoute,
  AgentApiKeyCreateResponseSchema,
  agentApiKeyListRoute,
  AgentApiKeyListResponseSchema,
  AgentApiKeyNotFoundResponseSchema,
  agentApiKeyRevokeRoute,
  AgentApiKeyRevokeResponseSchema,
  AgentApiKeyProtectedProbeResponseSchema,
  agentProtectedProbeRoute,
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema,
  type AuthenticatedAgent,
  type AgentApiKeyStore
} from "./agent-api-keys.js";
import { authenticateAgentOperation } from "./agent-auth.js";
import type { createAgentMcpServer } from "./agent-mcp.js";
import {
  AgentCatalogUnavailableResponseSchema,
  agentExerciseListRoute,
  AgentExerciseListResponseSchema,
  agentExerciseResolveRoute,
  AgentExerciseResolveResponseSchema,
  parseAgentExerciseListQuery,
  type AgentCatalogStore
} from "./agent-catalog.js";
import {
  agentDoseValidationRoute,
  AgentDoseValidationErrorResponseSchema,
  AgentDoseValidationResponseSchema,
  agentSetValidationRoute,
  AgentSetValidationErrorResponseSchema,
  AgentSetValidationResponseSchema,
  doseValidationLimitsResponse,
  nutrientValidationLimitsResponse,
  setValidationLimitsResponse,
  validateAgentDose,
  validateAgentSet
} from "./agent-validation.js";
import {
  agentWorkoutBatchWriteRoute,
  AgentWorkoutBatchWriteErrorResponseSchema,
  AgentWorkoutBatchWriteResponseSchema,
  AgentWorkoutBatchWriteUnavailableResponseSchema,
  prepareAgentWorkoutBatchWrite,
  type AgentWorkoutBatchWriteStore
} from "./agent-workout-batch-write.js";
import {
  agentExerciseCatalogBatchWriteRoute,
  AgentExerciseCatalogBatchWriteErrorResponseSchema,
  AgentExerciseCatalogBatchWriteResponseSchema,
  AgentExerciseCatalogBatchWriteUnavailableResponseSchema,
  prepareAgentExerciseCatalogBatchWrite,
  type AgentExerciseCatalogBatchWriteStore
} from "./agent-exercise-catalog-batch-write.js";
import {
  agentMealBatchWriteRoute,
  AgentMealBatchWriteErrorResponseSchema,
  AgentMealBatchWriteResponseSchema,
  AgentMealBatchWriteUnavailableResponseSchema,
  prepareAgentMealBatchWrite,
  type AgentMealBatchWriteStore
} from "./agent-meal-batch-write.js";
import {
  agentFoodBatchWriteRoute,
  agentFoodListRoute,
  agentFoodPlatformSearchRoute,
  AgentFoodBatchWriteErrorResponseSchema,
  AgentFoodBatchWriteResponseSchema,
  AgentFoodListResponseSchema,
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
  agentCompoundBatchWriteRoute,
  agentCompoundListRoute,
  AgentCompoundBatchWriteResponseSchema,
  AgentCompoundListResponseSchema,
  agentDoseBatchWriteRoute,
  agentDoseListRoute,
  AgentDoseBatchWriteErrorResponseSchema,
  AgentDoseBatchWriteResponseSchema,
  AgentDoseListResponseSchema,
  agentEffectWindowRoute,
  AgentEffectWindowErrorResponseSchema,
  AgentEffectWindowResponseSchema,
  agentProtocolBatchWriteRoute,
  agentProtocolListRoute,
  AgentProtocolBatchWriteResponseSchema,
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
import {
  agentMetricBatchWriteRoute,
  AgentMetricBatchWriteErrorResponseSchema,
  AgentMetricBatchWriteResponseSchema,
  agentMetricListRoute,
  AgentMetricListResponseSchema,
  agentMetricReadingsRoute,
  AgentMetricReadingsResponseSchema,
  AgentMetricUnavailableResponseSchema,
  type AgentMetricStore
} from "./agent-metrics.js";
import {
  agentActivityListRoute,
  agentActivityUndoBatchRoute,
  AgentActivityBatchNotFoundResponseSchema,
  AgentActivityListResponseSchema,
  AgentActivityUnavailableResponseSchema,
  AgentActivityUndoBatchResponseSchema,
  type AgentActivityStore
} from "./agent-activity.js";
import {
  agentNutritionGoalBatchWriteRoute,
  agentNutritionGoalListRoute,
  AgentNutritionGoalBatchWriteErrorResponseSchema,
  AgentNutritionGoalBatchWriteResponseSchema,
  AgentNutritionGoalListResponseSchema,
  AgentNutritionGoalUnavailableResponseSchema,
  type AgentNutritionGoalBatchWriteStore
} from "./agent-nutrition-goals.js";
import {
  agentSettingsReadRoute,
  agentSettingsBatchWriteRoute,
  AgentSettingsReadResponseSchema,
  AgentSettingsBatchWriteErrorResponseSchema,
  AgentSettingsBatchWriteResponseSchema,
  AgentSettingsUnavailableResponseSchema,
  type AgentSettingsBatchWriteStore
} from "./agent-settings.js";
import {
  agentRoutineDetailRoute,
  agentRoutineListRoute,
  agentWorkoutTemplateDetailRoute,
  agentWorkoutTemplateListRoute,
  agentPlanInvalidCursorResponse,
  AgentPlanInvalidCursorError,
  AgentPlanNotFoundResponseSchema,
  AgentPlanReadUnavailableResponseSchema,
  type AgentPlanReadStore
} from "./agent-plan-reads.js";
import {
  agentPlanTreeBatchWriteRoute,
  AgentPlanTreeBatchWriteUnavailableResponseSchema,
  runAgentPlanTreeBatchWrite,
  type AgentPlanTreeBatchWriteStore
} from "./agent-plan-tree-batch-write.js";
import {
  agentPlanMaterializeRoute,
  runAgentPlanMaterializeForAgent,
  type AgentPlanMaterializeStore
} from "./agent-plan-materialize.js";
import {
  agentPlanCaptureRoute,
  agentPlanUpdateFromWorkoutRoute,
  AgentPlanCaptureResponseSchema,
  AgentPlanUpdateFromWorkoutResponseSchema,
  runAgentPlanCaptureForAgent,
  runAgentPlanUpdateFromWorkoutForAgent,
  type AgentPlanCaptureRunResult,
  type AgentPlanCaptureStore
} from "./agent-plan-capture.js";
import {
  CANONICAL_IMPORT_ACTIVITY_LOG_ACTOR,
  CANONICAL_IMPORT_BATCHES_ENTITY,
  CanonicalImportForbiddenResponseSchema,
  CanonicalImportResponseSchema,
  CanonicalImportRequestSchema,
  CanonicalImportUnauthorizedResponseSchema,
  CanonicalImportUnavailableResponseSchema,
  canonicalImportRoute,
  canonicalImportObservabilityContext,
  type CanonicalImportObservabilityContext,
  type CanonicalImportStore
} from "./canonical-import-endpoint.js";
import {
  ActivityLinkConflictResponseSchema,
  ActivityLinkMutationResponseSchema,
  ActivityLinkNotFoundResponseSchema,
  ActivityLinkUnauthorizedResponseSchema,
  ActivityLinkUnavailableResponseSchema,
  activityLinkCreateRoute,
  activityLinkDeleteRoute,
  type ActivityLinkMutationStore
} from "./activity-links.js";
import {
  authenticateIntegrationCredentialOperation,
  IntegrationCredentialForbiddenResponseSchema,
  IntegrationCredentialIssueResponseSchema,
  IntegrationCredentialListResponseSchema,
  IntegrationCredentialNotFoundResponseSchema,
  IntegrationCredentialRevokeResponseSchema,
  IntegrationCredentialUnauthorizedResponseSchema,
  IntegrationCredentialUnavailableResponseSchema,
  IntegrationImportProfileResponseSchema,
  integrationCredentialCreateRoute,
  integrationCredentialListRoute,
  integrationCredentialRevokeRoute,
  integrationImportProfileRoute,
  type AuthenticatedIntegrationCredential,
  type IntegrationCredentialStore
} from "./integration-credentials.js";
import {
  IntegrationStatusListResponseSchema,
  IntegrationStatusReportResponseSchema,
  IntegrationStatusUnauthorizedResponseSchema,
  IntegrationStatusUnavailableResponseSchema,
  integrationStatusListRoute,
  integrationStatusReportRoute,
  type IntegrationStatusStore
} from "./integration-status.js";
import {
  GARMIN_OAUTH_SOURCE,
  GARMIN_OAUTH_STATE_TTL_SECONDS,
  GarminOAuthCallbackResponseSchema,
  GarminOAuthDisconnectResponseSchema,
  GarminOAuthInvalidCallbackResponseSchema,
  GarminOAuthNotFoundResponseSchema,
  GarminOAuthStartResponseSchema,
  GarminOAuthUnauthorizedResponseSchema,
  GarminOAuthUnavailableResponseSchema,
  createGarminAuthorizationUrl,
  garminAccessTokenExpiresAt,
  garminOAuthCallbackRoute,
  garminOAuthDisconnectRoute,
  garminOAuthStartRoute,
  type GarminOAuthClient,
  type GarminOAuthConfig,
  type GarminOAuthConnectionStore
} from "./garmin-oauth.js";
import {
  GARMIN_WEBHOOK_SECRET_HEADER,
  GarminConsentDataClassesResponseSchema,
  GarminConsentUnauthorizedResponseSchema,
  GarminConsentUnavailableResponseSchema,
  GarminWebhookAcceptedResponseSchema,
  GarminWebhookUnauthorizedResponseSchema,
  GarminWebhookUnavailableResponseSchema,
  enqueueGarminBackfill,
  enqueueGarminWebhookPing,
  garminConsentDataClassesRoute,
  garminWebhookRoute,
  listGarminConnectorConsentDataClassAccess,
  verifyGarminWebhookSecret,
  type GarminBackfillConfig,
  type GarminConnectorConsentStore,
  type GarminEntitlementStore,
  type GarminWebhookConfig
} from "./garmin-webhook.js";
import {
  GARMIN_FIT_IMPORT_DEFAULT_TIMEZONE,
  GARMIN_FIT_IMPORT_MAX_BYTES,
  GarminFitImportInvalidResponseSchema,
  GarminFitImportForbiddenResponseSchema,
  GarminFitImportUnauthorizedResponseSchema,
  GarminFitImportUnavailableResponseSchema,
  GarminFitImportJsonRequestSchema,
  GarminFitImportQuerySchema,
  garminFitImportIdempotencyKey,
  garminFitImportRoute,
  type GarminFitImportPayload
} from "./garmin-fit-import-endpoint.js";
import { parseGarminFitActivityFile } from "./garmin-fit-import.js";
import {
  IMPORTED_DATA_PURGE_ACTIVITY_LOG_ACTOR,
  IMPORTED_DATA_PURGE_DEVICE_ID,
  IMPORTED_DATA_PURGES_ENTITY,
  ImportedDataPurgeResponseSchema,
  ImportedDataPurgeUnauthorizedResponseSchema,
  ImportedDataPurgeUnavailableResponseSchema,
  importedDataPurgeRoute,
  type ImportedDataPurgeStore
} from "./imported-data-purge.js";
import {
  agentExerciseAnalyticsRoute,
  agentHistorySetsRoute,
  agentMonitoringActivityRoute,
  agentWorkoutDetailRoute,
  agentWorkoutListRoute,
  AgentExerciseAnalyticsResponseSchema,
  AgentHistorySetsResponseSchema,
  AgentMonitoringActivityNotFoundResponseSchema,
  AgentMonitoringActivityResponseSchema,
  AgentReadExerciseNotFoundResponseSchema,
  AgentReadUnavailableResponseSchema,
  AgentWorkoutDetailNotFoundResponseSchema,
  AgentWorkoutDetailResponseSchema,
  AgentWorkoutListResponseSchema,
  buildAgentExerciseAnalyticsResponse,
  type AgentReadStore
} from "./agent-read-surface.js";
import {
  agentMealListRoute,
  agentNutritionTotalsRoute,
  agentNutritionTrendsRoute,
  AgentMealListResponseSchema,
  AgentNutritionReadInvalidRangeResponseSchema,
  AgentNutritionReadUnavailableResponseSchema,
  AgentNutritionTotalsResponseSchema,
  AgentNutritionTrendsResponseSchema,
  buildAgentNutritionTotalsResponse,
  buildAgentNutritionTrendsResponse,
  goalTargetsFromQuery,
  resolveNutritionGoalTargets,
  validateNutritionRange,
  type AgentNutritionGoalSource,
  type AgentNutritionTotalsQuery,
  type AgentNutritionReadStore
} from "./agent-nutrition-reads.js";
import {
  nutrientDefaultUnit,
  type NutrientId,
  type NutrientUnit
} from "./analytics/nutrition-analytics.js";
import {
  agentEnergyBalanceRoute,
  agentTrainingDayNutritionRoute,
  AgentEnergyBalanceResponseSchema,
  AgentTrainingDayNutritionResponseSchema,
  buildAgentEnergyBalanceResponse,
  buildAgentTrainingDayNutritionResponse,
  validateCrossDomainRange,
  type AgentCrossDomainReadStore
} from "./agent-cross-domain-reads.js";
import {
  accountDeletionRoute,
  AccountDeletionResponseSchema,
  AccountDeletionUnavailableResponseSchema,
  type AccountDeletionStore
} from "./account-deletion.js";
import {
  devicePushTokenRegistrationRoute,
  DevicePushTokenRegistrationResponseSchema,
  type DevicePushTokenStore
} from "./device-push-tokens.js";
import {
  applyRateLimitHeaders,
  createRateLimitMiddleware,
  rateLimitExceededResponse,
  type RateLimitBackend,
  type RateLimitPolicyInput
} from "./rate-limit.js";
import {
  COMPOUNDS_SYNC_ENTITY,
  DOSES_SYNC_ENTITY,
  EXERCISE_CATEGORIES_SYNC_ENTITY,
  EXERCISE_GROUP_MEMBERS_SYNC_ENTITY,
  EXERCISE_GROUPS_SYNC_ENTITY,
  EXERCISES_SYNC_ENTITY,
  FOOD_ENTRIES_SYNC_ENTITY,
  FOODS_SYNC_ENTITY,
  LOGGED_SETS_SYNC_ENTITY,
  MEALS_SYNC_ENTITY,
  MEAL_TYPES_SYNC_ENTITY,
  NUTRITION_GOALS_SYNC_ENTITY,
  USER_SETTINGS_SYNC_ENTITY,
  PRESCRIPTIONS_SYNC_ENTITY,
  PROTOCOLS_SYNC_ENTITY,
  PROTOCOL_COMPOUNDS_SYNC_ENTITY,
  PROTOCOL_TARGET_OUTCOMES_SYNC_ENTITY,
  ROUTINES_SYNC_ENTITY,
  ROUTINE_ENTRIES_SYNC_ENTITY,
  WORKOUT_EXERCISES_SYNC_ENTITY,
  WORKOUT_SESSIONS_SYNC_ENTITY,
  WORKOUT_TEMPLATES_SYNC_ENTITY,
  TEMPLATE_EXERCISES_SYNC_ENTITY,
  TEMPLATE_GROUPS_SYNC_ENTITY,
  TEMPLATE_GROUP_MEMBERS_SYNC_ENTITY,
  TEMPLATE_LINKS_SYNC_ENTITY,
  SCHEDULES_SYNC_ENTITY,
  readBearerToken,
  SyncPullResponseSchema,
  syncPullRoute,
  SyncPushResponseSchema,
  SyncUnauthorizedResponseSchema,
  syncPushRoute,
  SyncUnavailableResponseSchema,
  type SyncStore
} from "./sync.js";
import {
  MonitoringSeriesBlobResponseSchema,
  MonitoringSeriesNotFoundResponseSchema,
  MonitoringSeriesUnauthorizedResponseSchema,
  MonitoringSeriesUnavailableResponseSchema,
  monitoringSeriesBlobRoute,
  type MonitoringSeriesStore
} from "./monitoring-series.js";
import {
  WorkoutMonitoringNotFoundResponseSchema,
  WorkoutMonitoringResponseSchema,
  WorkoutMonitoringUnauthorizedResponseSchema,
  WorkoutMonitoringUnavailableResponseSchema,
  workoutMonitoringRoute,
  type WorkoutMonitoringStore
} from "./workout-monitoring.js";
import type { SyncNudgePublisher } from "./sync-nudge.js";
import type { JobQueue } from "./jobs/index.js";
import {
  CORRELATION_ID_HEADER,
  createPrivacyLogger,
  resolveCorrelationId,
  safeRequestPath,
  type CrashReporter
} from "./observability.js";

export const DEFAULT_SERVER_VERSION = "0.0.0";

export type RequestLogger = {
  info(payload: Record<string, unknown>, message: string): void;
  error?(payload: Record<string, unknown>, message: string): void;
};

export type ReadinessProbe = {
  check(): Promise<void>;
};

export type CreateAppOptions = {
  accountDeletionStore?: AccountDeletionStore;
  agentApiKeyStore?: AgentApiKeyStore;
  agentActivityStore?: AgentActivityStore;
  agentCatalogStore?: AgentCatalogStore;
  agentReadStore?: AgentReadStore;
  agentNutritionReadStore?: AgentNutritionReadStore;
  agentCrossDomainReadStore?: AgentCrossDomainReadStore;
  agentWorkoutBatchWriteStore?: AgentWorkoutBatchWriteStore;
  agentExerciseCatalogBatchWriteStore?: AgentExerciseCatalogBatchWriteStore;
  agentMealBatchWriteStore?: AgentMealBatchWriteStore;
  agentFoodCatalogStore?: AgentFoodCatalogStore;
  agentFoodBatchWriteStore?: AgentFoodBatchWriteStore;
  agentMetricStore?: AgentMetricStore;
  agentProtocolsStore?: AgentProtocolsStore;
  agentNutritionGoalStore?: AgentNutritionGoalBatchWriteStore;
  agentSettingsStore?: AgentSettingsBatchWriteStore;
  agentPlanReadStore?: AgentPlanReadStore;
  agentPlanTreeBatchWriteStore?: AgentPlanTreeBatchWriteStore;
  agentPlanMaterializeStore?: AgentPlanMaterializeStore;
  agentPlanCaptureStore?: AgentPlanCaptureStore;
  activityLinkMutationStore?: ActivityLinkMutationStore;
  canonicalImportStore?: CanonicalImportStore;
  auth?: ServerAuth;
  crashReporter?: CrashReporter;
  garminOAuthClient?: GarminOAuthClient;
  garminOAuthConfig?: GarminOAuthConfig;
  garminOAuthStore?: GarminOAuthConnectionStore;
  garminBackfillConfig?: GarminBackfillConfig;
  garminConsentStore?: GarminConnectorConsentStore;
  garminEntitlementStore?: GarminEntitlementStore;
  garminWebhookConfig?: GarminWebhookConfig;
  garminWebhookJobQueue?: JobQueue;
  integrationCredentialStore?: IntegrationCredentialStore;
  importedDataPurgeStore?: ImportedDataPurgeStore;
  integrationStatusStore?: IntegrationStatusStore;
  logger?: RequestLogger;
  monitoringSeriesStore?: MonitoringSeriesStore;
  workoutMonitoringStore?: WorkoutMonitoringStore;
  readinessProbe?: ReadinessProbe;
  // A factory, not a shared instance: /mcp is stateless, so each
  // request gets its own McpServer connected to its own transport. The SDK's
  // Protocol throws if `connect()` is called twice on one instance, so a
  // single long-lived McpServer can't be reused across requests.
  createMcpServer?: () => ReturnType<typeof createAgentMcpServer>;
  rateLimitBackend?: RateLimitBackend;
  rateLimitPolicy?: RateLimitPolicyInput;
  devicePushTokenStore?: DevicePushTokenStore;
  syncStore?: SyncStore;
  syncNudgePublisher?: SyncNudgePublisher;
  version?: string;
};

type AppEnv = {
  Variables: {
    correlationId: string;
    canonicalImportObservability?: CanonicalImportObservabilityContext;
    userId?: string;
    // Read by @hono/mcp's StreamableHTTPTransport and threaded into every MCP
    // tool call as `extra.authInfo` ('s MCP transport section).
    auth?: AuthInfo;
  };
};

class CanonicalImportProcessingError extends Error {
  constructor() {
    super("Canonical import failed.");
    this.name = "CanonicalImportProcessingError";
  }
}

export const HealthResponseSchema = z
  .object({
    status: z.literal("ok").openapi({
      description: "Server health status."
    }),
    version: z.string().min(1).openapi({
      description: "Server package version."
    })
  })
  .openapi("HealthResponse");

export const ReadinessResponseSchema = z
  .object({
    status: z.literal("ready").openapi({
      description: "Server readiness status."
    }),
    database: z.literal("ok").openapi({
      description: "Postgres connectivity status."
    })
  })
  .openapi("ReadinessResponse");

export const ReadinessUnavailableResponseSchema = z
  .object({
    status: z.literal("not_ready").openapi({
      description: "Server readiness status."
    }),
    database: z.enum(["error", "unconfigured"]).openapi({
      description: "Postgres connectivity failure reason."
    })
  })
  .openapi("ReadinessUnavailableResponse");

export const AuthDisabledResponseSchema = z
  .object({
    code: z.literal("email_password_disabled").openapi({
      description: "Stable machine-readable disabled auth code."
    }),
    message: z.string().min(1).openapi({
      description: "Human-readable disabled auth reason."
    })
  })
  .openapi("AuthDisabledResponse");

const healthRoute = createRoute({
  method: "get",
  path: "/healthz",
  operationId: "getHealthz",
  tags: ["Health"],
  summary: "Report server health.",
  responses: {
    200: {
      description: "The server is ready to accept requests.",
      content: {
        "application/json": {
          schema: HealthResponseSchema
        }
      }
    }
  }
});

const readyRoute = createRoute({
  method: "get",
  path: "/readyz",
  operationId: "getReadyz",
  tags: ["Health"],
  summary: "Report server readiness.",
  responses: {
    200: {
      description: "The server can reach Postgres.",
      content: {
        "application/json": {
          schema: ReadinessResponseSchema
        }
      }
    },
    503: {
      description: "The server cannot confirm Postgres readiness.",
      content: {
        "application/json": {
          schema: ReadinessUnavailableResponseSchema
        }
      }
    }
  }
});

export function createApp(options: CreateAppOptions = {}) {
  const logger = createPrivacyLogger(options.logger ?? pino());
  const accountDeletionStore = options.accountDeletionStore;
  const agentApiKeyStore = options.agentApiKeyStore;
  const agentActivityStore = options.agentActivityStore;
  const agentCatalogStore = options.agentCatalogStore;
  const agentReadStore = options.agentReadStore;
  const agentNutritionReadStore = options.agentNutritionReadStore;
  const agentCrossDomainReadStore = options.agentCrossDomainReadStore;
  const agentWorkoutBatchWriteStore = options.agentWorkoutBatchWriteStore;
  const agentExerciseCatalogBatchWriteStore =
    options.agentExerciseCatalogBatchWriteStore;
  const agentMealBatchWriteStore = options.agentMealBatchWriteStore;
  const agentFoodCatalogStore = options.agentFoodCatalogStore;
  const agentFoodBatchWriteStore = options.agentFoodBatchWriteStore;
  const agentMetricStore = options.agentMetricStore;
  const agentProtocolsStore = options.agentProtocolsStore;
  const agentNutritionGoalStore = options.agentNutritionGoalStore;
  const agentSettingsStore = options.agentSettingsStore;
  const agentPlanReadStore = options.agentPlanReadStore;
  const agentPlanTreeBatchWriteStore = options.agentPlanTreeBatchWriteStore;
  const agentPlanMaterializeStore = options.agentPlanMaterializeStore;
  const agentPlanCaptureStore = options.agentPlanCaptureStore;
  const activityLinkMutationStore = options.activityLinkMutationStore;
  const canonicalImportStore = options.canonicalImportStore;
  const auth = options.auth;
  const crashReporter = options.crashReporter;
  const garminOAuthClient = options.garminOAuthClient;
  const garminOAuthConfig = options.garminOAuthConfig;
  const garminOAuthStore = options.garminOAuthStore;
  const garminBackfillConfig = options.garminBackfillConfig;
  const garminConsentStore = options.garminConsentStore;
  const garminEntitlementStore = options.garminEntitlementStore;
  const garminWebhookConfig = options.garminWebhookConfig;
  const garminWebhookJobQueue = options.garminWebhookJobQueue;
  const integrationCredentialStore = options.integrationCredentialStore;
  const importedDataPurgeStore = options.importedDataPurgeStore;
  const integrationStatusStore = options.integrationStatusStore;
  const monitoringSeriesStore = options.monitoringSeriesStore;
  const workoutMonitoringStore = options.workoutMonitoringStore;
  const readinessProbe = options.readinessProbe;
  const createMcpServer = options.createMcpServer;
  const rateLimitBackend = options.rateLimitBackend;
  const devicePushTokenStore = options.devicePushTokenStore;
  const syncStore = options.syncStore;
  const syncNudgePublisher = options.syncNudgePublisher;
  const version = options.version ?? DEFAULT_SERVER_VERSION;
  const app = new OpenAPIHono<AppEnv>();
  registerCanonicalImportOpenApiSchemas(app.openAPIRegistry);

  app.use("*", async (context, next) => {
    const correlationId = resolveCorrelationId(
      context.req.header(CORRELATION_ID_HEADER)
    );
    const startedAt = Date.now();
    context.set("correlationId", correlationId);
    context.header(CORRELATION_ID_HEADER, correlationId);

    try {
      await next();
    } finally {
      logger.info(
        {
          correlationId,
          method: context.req.method,
          path: safeRequestPath(new URL(context.req.url).pathname),
          status: context.res.status,
          durationMs: Date.now() - startedAt,
          userId: context.get("userId")
        },
        "request completed"
      );
    }
  });

  app.onError((error, context) => {
    if (error instanceof HTTPException) {
      return error.getResponse();
    }

    const canonicalImport = context.get("canonicalImportObservability");
    const crashContext = {
      correlationId: requestCorrelationId(context),
      method: context.req.method,
      path: safeRequestPath(new URL(context.req.url).pathname),
      ...(canonicalImport === undefined ? {} : { canonicalImport }),
      userId: context.get("userId")
    };
    crashReporter?.captureException(error, crashContext);
    logger.error?.(
      {
        ...crashContext,
        error
      },
      "request failed"
    );

    return context.json(
      {
        code: "internal_error",
        message: "Internal server error."
      },
      500
    );
  });

  if (rateLimitBackend !== undefined) {
    app.use(
      "*",
      createRateLimitMiddleware({
        backend: rateLimitBackend,
        policy: options.rateLimitPolicy,
        logger
      })
    );
  }

  if (auth !== undefined) {
    app.all(`${auth.basePath}/*`, async (context) => {
      const path = new URL(context.req.url).pathname;

      if (
        !auth.emailPasswordEnabled &&
        isEmailPasswordAuthPath(path, auth.basePath)
      ) {
        return context.json(
          AuthDisabledResponseSchema.parse({
            code: "email_password_disabled",
            message: AUTH_DISABLED_MESSAGE
          }),
          503
        );
      }

      return auth.handler(context.req.raw);
    });
  }

  app.get("/auth/verified", (context) => {
    const requestUrl = new URL(context.req.url);
    const error =
      requestUrl.searchParams.get("error") ??
      requestUrl.searchParams.get("code");
    const isSuccess = error === null || error.length === 0;

    return context.html(
      renderAuthVerifiedPage({
        status: isSuccess ? "verified" : "failed",
        detail: error ?? undefined
      }),
      isSuccess ? 200 : 400
    );
  });

  app.openapi(healthRoute, (context) => {
    const responseBody = HealthResponseSchema.parse({
      status: "ok",
      version
    });

    return context.json(responseBody, 200);
  });

  app.openapi(readyRoute, async (context) => {
    if (readinessProbe === undefined) {
      return context.json(
        ReadinessUnavailableResponseSchema.parse({
          status: "not_ready",
          database: "unconfigured"
        }),
        503
      );
    }

    try {
      await readinessProbe.check();
    } catch (error) {
      logger.error?.({ error }, "readiness probe failed");
      return context.json(
        ReadinessUnavailableResponseSchema.parse({
          status: "not_ready",
          database: "error"
        }),
        503
      );
    }

    return context.json(
      ReadinessResponseSchema.parse({
        status: "ready",
        database: "ok"
      }),
      200
    );
  });

  app.openapi(canonicalImportRoute, async (context) => {
    if (
      integrationCredentialStore === undefined ||
      canonicalImportStore === undefined
    ) {
      return context.json(
        CanonicalImportUnavailableResponseSchema.parse({
          code: "canonical_import_unavailable",
          message: "Canonical import storage is not configured."
        }),
        503
      );
    }

    const integrationAuth = await authenticateIntegrationCredentialBearer({
      context,
      integrationCredentialStore,
      rateLimitBackend,
      logger
    });
    if (integrationAuth.status === "unauthorized") {
      return context.json(
        CanonicalImportUnauthorizedResponseSchema.parse({
          code: "integration_unauthorized",
          message: "A valid Integration credential is required."
        }),
        401
      );
    }
    if (integrationAuth.status === "forbidden") {
      return context.json(
        CanonicalImportForbiddenResponseSchema.parse({
          code: "integration_forbidden",
          message: "The Integration credential is not scoped for imports."
        }),
        403
      );
    }
    if (integrationAuth.status === "rate_limited") {
      return integrationAuth.response;
    }
    const integration = integrationAuth.credential;
    const requestBody = context.req.valid("json");
    const correlationId = requestCorrelationId(context);
    const importObservability = canonicalImportObservabilityContext({
      credentialId: integration.credentialId,
      request: requestBody,
      userId: integration.userId
    });
    context.set("canonicalImportObservability", importObservability);
    logger.info(
      {
        correlationId,
        canonicalImport: importObservability
      },
      "canonical import received"
    );

    let importResult: Awaited<
      ReturnType<CanonicalImportStore["importCanonicalBatch"]>
    >;
    try {
      importResult = await canonicalImportStore.importCanonicalBatch({
        actor: CANONICAL_IMPORT_ACTIVITY_LOG_ACTOR,
        batchId: requestBody.idempotencyKey,
        correlationId,
        credentialId: integration.credentialId,
        deviceId: `integration:${integration.credentialId}`,
        idempotencyKey: requestBody.idempotencyKey,
        request: requestBody,
        userId: integration.userId
      });
    } catch {
      logger.error?.(
        {
          correlationId,
          canonicalImport: importObservability,
          failureKind: "canonical_import_processing_error"
        },
        "canonical import failed"
      );
      throw new CanonicalImportProcessingError();
    }

    const appliedDataRows = importResult.applied.filter(
      (applied) => applied.entityTable !== CANONICAL_IMPORT_BATCHES_ENTITY
    );
    logger.info(
      {
        correlationId,
        canonicalImport: {
          ...importObservability,
          resultCounts: {
            activityResults: importResult.activities.length,
            metricReadingResults: importResult.metricReadings.length,
            seriesAccepted: importResult.seriesAccepted,
            reviewFlags: importResult.reviewFlags.length,
            materializedWorkouts: importResult.materializedWorkouts.length,
            activityLinks: importResult.activityLinks.length,
            activityLinkSuggestions: importResult.activityLinkSuggestions.length,
            appliedRows: appliedDataRows.length
          }
        }
      },
      "canonical import completed"
    );
    if (syncNudgePublisher !== undefined && appliedDataRows.length > 0) {
      try {
        await syncNudgePublisher.enqueueSyncNudge({
          userId: integration.userId,
          sourceDeviceId: `integration:${integration.credentialId}`,
          reason: "integration_import"
        });
      } catch (error) {
        logger.error?.(
          {
            error,
            userId: integration.userId,
            credentialId: integration.credentialId,
            batchId: requestBody.idempotencyKey
          },
          "integration import sync nudge enqueue failed"
        );
      }
    }

    const { applied, ...responseBody } = importResult;
    return context.json(CanonicalImportResponseSchema.parse(responseBody), 200);
  });

  app.openapi(integrationCredentialCreateRoute, async (context) => {
    if (integrationCredentialStore === undefined || syncStore === undefined) {
      return context.json(
        IntegrationCredentialUnavailableResponseSchema.parse({
          code: "integration_credentials_unavailable",
          message:
            "Integration credential storage or session auth is not configured."
        }),
        503
      );
    }

    const session = await verifySyncSessionBearer(context, syncStore);
    if (session === null) {
      return context.json(
        IntegrationCredentialUnauthorizedResponseSchema.parse({
          code: "integration_credentials_unauthorized",
          message: "A session bearer token is required."
        }),
        401
      );
    }

    const requestBody = context.req.valid("json");
    const issued =
      await integrationCredentialStore.issueIntegrationCredential({
        userId: session.userId,
        name: requestBody.name,
        source: requestBody.source
      });

    return context.json(
      IntegrationCredentialIssueResponseSchema.parse(issued),
      201
    );
  });

  app.openapi(integrationCredentialListRoute, async (context) => {
    if (integrationCredentialStore === undefined || syncStore === undefined) {
      return context.json(
        IntegrationCredentialUnavailableResponseSchema.parse({
          code: "integration_credentials_unavailable",
          message:
            "Integration credential storage or session auth is not configured."
        }),
        503
      );
    }

    const session = await verifySyncSessionBearer(context, syncStore);
    if (session === null) {
      return context.json(
        IntegrationCredentialUnauthorizedResponseSchema.parse({
          code: "integration_credentials_unauthorized",
          message: "A session bearer token is required."
        }),
        401
      );
    }

    return context.json(
      IntegrationCredentialListResponseSchema.parse({
        credentials:
          await integrationCredentialStore.listIntegrationCredentials(
            session.userId
          )
      }),
      200
    );
  });

  app.openapi(integrationCredentialRevokeRoute, async (context) => {
    if (integrationCredentialStore === undefined || syncStore === undefined) {
      return context.json(
        IntegrationCredentialUnavailableResponseSchema.parse({
          code: "integration_credentials_unavailable",
          message:
            "Integration credential storage or session auth is not configured."
        }),
        503
      );
    }

    const session = await verifySyncSessionBearer(context, syncStore);
    if (session === null) {
      return context.json(
        IntegrationCredentialUnauthorizedResponseSchema.parse({
          code: "integration_credentials_unauthorized",
          message: "A session bearer token is required."
        }),
        401
      );
    }

    const params = context.req.valid("param");
    const revoked =
      await integrationCredentialStore.revokeIntegrationCredential({
        credentialId: params.credentialId,
        userId: session.userId
      });
    if (!revoked) {
      return context.json(
        IntegrationCredentialNotFoundResponseSchema.parse({
          code: "integration_credential_not_found",
          message:
            "No import-scoped Integration credential exists for this account with that id."
        }),
        404
      );
    }

    return context.json(
      IntegrationCredentialRevokeResponseSchema.parse({ revoked: true }),
      200
    );
  });

  app.openapi(integrationImportProfileRoute, async (context) => {
    if (integrationCredentialStore === undefined) {
      return context.json(
        IntegrationCredentialUnavailableResponseSchema.parse({
          code: "integration_credentials_unavailable",
          message: "Integration credential storage is not configured."
        }),
        503
      );
    }

    const integrationAuth = await authenticateIntegrationCredentialBearer({
      context,
      integrationCredentialStore,
      rateLimitBackend,
      logger
    });
    if (integrationAuth.status === "unauthorized") {
      return context.json(
        IntegrationCredentialUnauthorizedResponseSchema.parse({
          code: "integration_credentials_unauthorized",
          message: "A valid Integration credential is required."
        }),
        401
      );
    }
    if (integrationAuth.status === "forbidden") {
      return context.json(
        IntegrationCredentialForbiddenResponseSchema.parse({
          code: "integration_credentials_forbidden",
          message: "The Integration credential is not scoped for imports."
        }),
        403
      );
    }
    if (integrationAuth.status === "rate_limited") {
      return integrationAuth.response;
    }

    const integration = integrationAuth.credential;
    const dataClasses =
      await integrationCredentialStore.listIntegrationCredentialConsentDataClasses({
        credentialId: integration.credentialId,
        userId: integration.userId
      });
    const enabledDataClasses = dataClasses
      .filter((dataClass) => dataClass.enabled)
      .map((dataClass) => dataClass.dataClass);

    return context.json(
      IntegrationImportProfileResponseSchema.parse({
        credential: {
          id: integration.credentialId,
          name: integration.credentialName ?? "Integration import",
          source: integration.source
        },
        dataClasses,
        enabledDataClasses,
        fitImportEnabled: enabledDataClasses.includes("activities"),
        manualFitImport: {
          enabled: true,
          uploadPath: "/integrations/garmin/fit-import"
        }
      }),
      200
    );
  });

  app.openapi(garminFitImportRoute, async (context) => {
    if (canonicalImportStore === undefined) {
      return context.json(
        GarminFitImportUnavailableResponseSchema.parse({
          code: "garmin_fit_import_unavailable",
          message: "Canonical import storage is not configured."
        }),
        503
      );
    }
    if (
      integrationCredentialStore === undefined &&
      syncStore === undefined
    ) {
      return context.json(
        GarminFitImportUnavailableResponseSchema.parse({
          code: "garmin_fit_import_unavailable",
          message: "FIT import auth is not configured."
        }),
        503
      );
    }

    const authResult = await authenticateGarminFitImportBearer({
      context,
      integrationCredentialStore,
      syncStore,
      rateLimitBackend,
      logger
    });
    if (authResult.status === "unauthorized") {
      return context.json(
        GarminFitImportUnauthorizedResponseSchema.parse({
          code: "garmin_fit_import_unauthorized",
          message:
            "A valid Integration credential or session bearer token is required."
        }),
        401
      );
    }
    if (authResult.status === "forbidden") {
      return context.json(
        GarminFitImportForbiddenResponseSchema.parse({
          code: "garmin_fit_import_forbidden",
          message: "The Integration credential is not scoped for imports."
        }),
        403
      );
    }
    if (authResult.status === "rate_limited") {
      return authResult.response;
    }

    const parsedPayload = await readGarminFitImportPayload(context);
    if (parsedPayload.status === "invalid") {
      return context.json(
        GarminFitImportInvalidResponseSchema.parse({
          code: "garmin_fit_import_invalid",
          message: parsedPayload.message
        }),
        400
      );
    }
    const payload = parsedPayload.payload;
    const credentialId =
      authResult.kind === "integration"
        ? authResult.credential.credentialId
        : payload.credentialId;
    if (credentialId === undefined) {
      return context.json(
        GarminFitImportInvalidResponseSchema.parse({
          code: "garmin_fit_import_invalid",
          message:
            "Manual FIT upload with a session bearer requires a credentialId whose Garmin import consent rows are enabled in the app."
        }),
        400
      );
    }

    const idempotencyKey =
      payload.idempotencyKey ??
      garminFitImportIdempotencyKey(payload.bytes);
    let canonical;
    try {
      canonical = parseGarminFitActivityFile(payload.bytes, {
        source: "garmin",
        timezone: payload.timezone
      });
    } catch {
      return context.json(
        GarminFitImportInvalidResponseSchema.parse({
          code: "garmin_fit_import_invalid",
          message: "The uploaded file could not be parsed as a Garmin FIT activity."
        }),
        400
      );
    }

    const requestBody = CanonicalImportRequestSchema.parse({
      idempotencyKey,
      consentedDataClasses: [],
      ...canonical
    });
    const correlationId = requestCorrelationId(context);
    const importObservability = canonicalImportObservabilityContext({
      credentialId,
      request: requestBody,
      userId: authResult.userId
    });
    context.set("canonicalImportObservability", importObservability);
    logger.info(
      {
        correlationId,
        canonicalImport: importObservability
      },
      "garmin fit import received"
    );

    let importResult: Awaited<
      ReturnType<CanonicalImportStore["importCanonicalBatch"]>
    >;
    try {
      importResult = await canonicalImportStore.importCanonicalBatch({
        actor: CANONICAL_IMPORT_ACTIVITY_LOG_ACTOR,
        batchId: idempotencyKey,
        correlationId,
        credentialId,
        deviceId:
          authResult.kind === "integration"
            ? `integration:${credentialId}`
            : "app:garmin-fit-import",
        idempotencyKey,
        request: requestBody,
        userId: authResult.userId
      });
    } catch {
      logger.error?.(
        {
          correlationId,
          canonicalImport: importObservability,
          failureKind: "garmin_fit_import_processing_error"
        },
        "garmin fit import failed"
      );
      throw new CanonicalImportProcessingError();
    }

    const appliedDataRows = importResult.applied.filter(
      (applied) => applied.entityTable !== CANONICAL_IMPORT_BATCHES_ENTITY
    );
    if (syncNudgePublisher !== undefined && appliedDataRows.length > 0) {
      try {
        await syncNudgePublisher.enqueueSyncNudge({
          userId: authResult.userId,
          sourceDeviceId:
            authResult.kind === "integration"
              ? `integration:${credentialId}`
              : "app:garmin-fit-import",
          reason: "integration_import"
        });
      } catch (error) {
        logger.error?.(
          {
            error,
            userId: authResult.userId,
            credentialId,
            batchId: idempotencyKey
          },
          "garmin fit import sync nudge enqueue failed"
        );
      }
    }

    const { applied, ...responseBody } = importResult;
    return context.json(CanonicalImportResponseSchema.parse(responseBody), 200);
  });

  app.openapi(integrationStatusReportRoute, async (context) => {
    if (
      integrationCredentialStore === undefined ||
      integrationStatusStore === undefined
    ) {
      return context.json(
        IntegrationStatusUnavailableResponseSchema.parse({
          code: "integration_status_unavailable",
          message: "Integration status storage is not configured."
        }),
        503
      );
    }

    const integration = await authenticateIntegrationStatusBearer({
      context,
      integrationCredentialStore
    });
    if (integration === null) {
      return context.json(
        IntegrationStatusUnauthorizedResponseSchema.parse({
          code: "integration_status_unauthorized",
          message: "A valid Integration credential is required."
        }),
        401
      );
    }

    setRequestUserId(context, integration.userId);
    const status = await integrationStatusStore.recordIntegrationStatus({
      credentialId: integration.credentialId,
      credentialName: integration.credentialName,
      userId: integration.userId,
      report: context.req.valid("json")
    });

    return context.json(
      IntegrationStatusReportResponseSchema.parse({ status }),
      200
    );
  });

  app.openapi(integrationStatusListRoute, async (context) => {
    if (syncStore === undefined || integrationStatusStore === undefined) {
      return context.json(
        IntegrationStatusUnavailableResponseSchema.parse({
          code: "integration_status_unavailable",
          message: "Integration status storage is not configured."
        }),
        503
      );
    }

    const token = readBearerToken(context.req.header("authorization"));
    if (token === null) {
      return context.json(
        IntegrationStatusUnauthorizedResponseSchema.parse({
          code: "integration_status_unauthorized",
          message: "A session bearer token is required."
        }),
        401
      );
    }

    const session = await syncStore.verifyBearerToken(token);
    if (session === null) {
      return context.json(
        IntegrationStatusUnauthorizedResponseSchema.parse({
          code: "integration_status_unauthorized",
          message: await syncUnauthorizedMessage(syncStore, token)
        }),
        401
      );
    }

    setRequestUserId(context, session.userId);
    return context.json(
      IntegrationStatusListResponseSchema.parse({
        statuses: await integrationStatusStore.listIntegrationStatuses(
          session.userId
        )
      }),
      200
    );
  });

  app.openapi(garminOAuthStartRoute, async (context) => {
    if (
      garminOAuthConfig === undefined ||
      garminOAuthStore === undefined ||
      syncStore === undefined
    ) {
      return context.json(
        GarminOAuthUnavailableResponseSchema.parse({
          code: "garmin_oauth_unavailable",
          message: "Garmin OAuth storage or configuration is not configured."
        }),
        503
      );
    }

    const session = await verifySyncSessionBearer(context, syncStore);
    if (session === null) {
      return context.json(
        GarminOAuthUnauthorizedResponseSchema.parse({
          code: "garmin_oauth_unauthorized",
          message: "A session bearer token is required."
        }),
        401
      );
    }

    const stateExpiresAt = new Date(
      Date.now() +
        (garminOAuthConfig.stateTtlSeconds ?? GARMIN_OAUTH_STATE_TTL_SECONDS) *
          1000
    );
    const state = garminOAuthStore.createOAuthState({
      expiresAt: stateExpiresAt,
      userId: session.userId
    });

    return context.json(
      GarminOAuthStartResponseSchema.parse({
        authorizationUrl: createGarminAuthorizationUrl({
          config: garminOAuthConfig,
          state
        }),
        stateExpiresAt: stateExpiresAt.toISOString()
      }),
      200
    );
  });

  app.openapi(garminOAuthCallbackRoute, async (context) => {
    if (
      garminOAuthClient === undefined ||
      garminOAuthConfig === undefined ||
      garminOAuthStore === undefined ||
      integrationStatusStore === undefined
    ) {
      return context.json(
        GarminOAuthUnavailableResponseSchema.parse({
          code: "garmin_oauth_unavailable",
          message: "Garmin OAuth storage or configuration is not configured."
        }),
        503
      );
    }

    const query = context.req.valid("query");
    const oauthState = garminOAuthStore.readOAuthState({
      state: query.state
    });
    if (oauthState === null) {
      return context.json(
        GarminOAuthInvalidCallbackResponseSchema.parse({
          code: "garmin_oauth_invalid_callback",
          message: "Garmin OAuth state is invalid or expired."
        }),
        400
      );
    }

    setRequestUserId(context, oauthState.userId);
    const token = await garminOAuthClient.exchangeCode({
      code: query.code,
      redirectUri: garminOAuthConfig.redirectUri
    });
    const connection = await garminOAuthStore.upsertConnection({
      accessTokenExpiresAt: garminAccessTokenExpiresAt(token.expiresInSeconds),
      providerUserId: token.providerUserId,
      refreshToken: token.refreshToken,
      scope: token.scope,
      userId: oauthState.userId
    });
    await integrationStatusStore.recordIntegrationStatus({
      credentialId: connection.id,
      credentialName: connection.credentialName,
      userId: oauthState.userId,
      report: {
        source: GARMIN_OAUTH_SOURCE,
        condition: "ok",
        trigger: "manual"
      }
    });
    if (garminWebhookJobQueue !== undefined) {
      await enqueueGarminBackfill({
        config: garminBackfillConfig,
        connection: {
          ...connection,
          userId: oauthState.userId
        },
        jobs: garminWebhookJobQueue
      });
    }

    return context.json(
      GarminOAuthCallbackResponseSchema.parse({ connection }),
      200
    );
  });

  app.openapi(garminOAuthDisconnectRoute, async (context) => {
    if (
      garminOAuthClient === undefined ||
      garminOAuthStore === undefined ||
      syncStore === undefined
    ) {
      return context.json(
        GarminOAuthUnavailableResponseSchema.parse({
          code: "garmin_oauth_unavailable",
          message: "Garmin OAuth storage or configuration is not configured."
        }),
        503
      );
    }

    const session = await verifySyncSessionBearer(context, syncStore);
    if (session === null) {
      return context.json(
        GarminOAuthUnauthorizedResponseSchema.parse({
          code: "garmin_oauth_unauthorized",
          message: "A session bearer token is required."
        }),
        401
      );
    }

    const connection = await garminOAuthStore.findActiveConnectionForUser({
      userId: session.userId
    });
    if (connection === null) {
      return context.json(
        GarminOAuthNotFoundResponseSchema.parse({
          code: "garmin_oauth_connection_not_found",
          message: "No active Garmin OAuth connection exists for this account."
        }),
        404
      );
    }

    const refreshToken =
      await garminOAuthStore.decryptRefreshTokenForConnectorJob({
        connectionId: connection.id,
        userId: session.userId
      });
    if (refreshToken === null) {
      return context.json(
        GarminOAuthNotFoundResponseSchema.parse({
          code: "garmin_oauth_connection_not_found",
          message: "No active Garmin OAuth connection exists for this account."
        }),
        404
      );
    }

    let revoked = false;
    try {
      revoked = (await garminOAuthClient.revokeRefreshToken(refreshToken))
        .revoked;
    } catch {
      revoked = false;
    }
    await garminOAuthStore.forgetRefreshToken({
      connectionId: connection.id,
      userId: session.userId
    });

    return context.json(
      GarminOAuthDisconnectResponseSchema.parse({
        connectionId: connection.id,
        disconnected: true,
        revoked
      }),
      200
    );
  });

  app.openapi(garminConsentDataClassesRoute, async (context) => {
    if (syncStore === undefined || garminOAuthStore === undefined) {
      return context.json(
        GarminConsentUnavailableResponseSchema.parse({
          code: "garmin_consent_unavailable",
          message: "Garmin consent storage or session auth is not configured."
        }),
        503
      );
    }

    const session = await verifySyncSessionBearer(context, syncStore);
    if (session === null) {
      return context.json(
        GarminConsentUnauthorizedResponseSchema.parse({
          code: "garmin_consent_unauthorized",
          message: "A session bearer token is required."
        }),
        401
      );
    }

    const connection = await garminOAuthStore.findActiveConnectionForUser({
      userId: session.userId
    });
    const credentialId = connection?.id ?? "garmin-oauth-unconnected";
    const dataClasses = await listGarminConnectorConsentDataClassAccess({
      credentialId,
      consentStore: garminConsentStore,
      entitlementStore: garminEntitlementStore,
      userId: session.userId
    });

    return context.json(
      GarminConsentDataClassesResponseSchema.parse({
        connectionId: connection?.id ?? null,
        dataClasses
      }),
      200
    );
  });

  app.openapi(garminWebhookRoute, async (context) => {
    if (
      garminWebhookConfig === undefined ||
      garminWebhookJobQueue === undefined
    ) {
      return context.json(
        GarminWebhookUnavailableResponseSchema.parse({
          code: "garmin_webhook_unavailable",
          message: "Garmin webhook configuration or job queue is not configured."
        }),
        503
      );
    }

    if (
      !verifyGarminWebhookSecret({
        config: garminWebhookConfig,
        providedSecret: context.req.header(GARMIN_WEBHOOK_SECRET_HEADER)
      })
    ) {
      return context.json(
        GarminWebhookUnauthorizedResponseSchema.parse({
          code: "garmin_webhook_unauthorized",
          message: "A valid Garmin webhook secret is required."
        }),
        401
      );
    }

    const queued = await enqueueGarminWebhookPing({
      jobs: garminWebhookJobQueue,
      ping: context.req.valid("json")
    });

    return context.json(
      GarminWebhookAcceptedResponseSchema.parse({
        accepted: true,
        idempotencyKey: queued.idempotencyKey,
        jobId: queued.jobId
      }),
      202
    );
  });

  app.openapi(importedDataPurgeRoute, async (context) => {
    if (
      importedDataPurgeStore === undefined ||
      syncStore === undefined
    ) {
      return context.json(
        ImportedDataPurgeUnavailableResponseSchema.parse({
          code: "imported_data_purge_unavailable",
          message: "Imported data purge storage is not configured."
        }),
        503
      );
    }

    const session = await verifySyncSessionBearer(context, syncStore);
    if (session === null) {
      return context.json(
        ImportedDataPurgeUnauthorizedResponseSchema.parse({
          code: "imported_data_purge_unauthorized",
          message: "A session bearer token is required."
        }),
        401
      );
    }

    const requestBody = context.req.valid("json");
    const result = await importedDataPurgeStore.purgeImportedData({
      userId: session.userId,
      actor: IMPORTED_DATA_PURGE_ACTIVITY_LOG_ACTOR,
      batchId: requestBody.idempotencyKey,
      deviceId: IMPORTED_DATA_PURGE_DEVICE_ID,
      source: requestBody.source,
      scope: requestBody.scope
    });

    const appliedDataRows = result.applied.filter(
      (applied) => applied.entityTable !== IMPORTED_DATA_PURGES_ENTITY
    );
    if (syncNudgePublisher !== undefined && appliedDataRows.length > 0) {
      try {
        await syncNudgePublisher.enqueueSyncNudge({
          userId: session.userId,
          sourceDeviceId: IMPORTED_DATA_PURGE_DEVICE_ID,
          reason: "integration_purge"
        });
      } catch (error) {
        logger.error?.(
          {
            error,
            userId: session.userId,
            batchId: requestBody.idempotencyKey,
            source: requestBody.source,
            scope: requestBody.scope
          },
          "imported data purge sync nudge enqueue failed"
        );
      }
    }

    const { applied, ...responseBody } = result;
    return context.json(
      ImportedDataPurgeResponseSchema.parse(responseBody),
      200
    );
  });

  app.openapi(activityLinkCreateRoute, async (context) => {
    if (
      activityLinkMutationStore === undefined ||
      syncStore === undefined
    ) {
      return context.json(
        ActivityLinkUnavailableResponseSchema.parse({
          code: "activity_link_unavailable",
          message: "Activity Link storage is not configured."
        }),
        503
      );
    }

    const session = await verifySyncSessionBearer(context, syncStore);
    if (session === null) {
      return context.json(
        ActivityLinkUnauthorizedResponseSchema.parse({
          code: "activity_link_unauthorized",
          message: "A session bearer token is required."
        }),
        401
      );
    }

    const requestBody = context.req.valid("json");
    const result = await activityLinkMutationStore.createActivityLink({
      userId: session.userId,
      batchId: requestBody.idempotencyKey,
      deviceId: "app:activity-link",
      externalActivityId: requestBody.externalActivityId,
      workoutId: requestBody.workoutId
    });
    if (result.status === "not_found") {
      return context.json(
        ActivityLinkNotFoundResponseSchema.parse({
          code: "activity_link_not_found",
          message:
            "No live External Activity and Workout exist for this account with those ids."
        }),
        404
      );
    }
    if (result.status === "conflict") {
      return context.json(
        ActivityLinkConflictResponseSchema.parse({
          code: "activity_link_conflict",
          message: "The External Activity is already linked to another Workout."
        }),
        409
      );
    }

    return context.json(
      ActivityLinkMutationResponseSchema.parse(result.response),
      200
    );
  });

  app.openapi(activityLinkDeleteRoute, async (context) => {
    if (
      activityLinkMutationStore === undefined ||
      syncStore === undefined
    ) {
      return context.json(
        ActivityLinkUnavailableResponseSchema.parse({
          code: "activity_link_unavailable",
          message: "Activity Link storage is not configured."
        }),
        503
      );
    }

    const session = await verifySyncSessionBearer(context, syncStore);
    if (session === null) {
      return context.json(
        ActivityLinkUnauthorizedResponseSchema.parse({
          code: "activity_link_unauthorized",
          message: "A session bearer token is required."
        }),
        401
      );
    }

    const params = context.req.valid("param");
    const requestBody = context.req.valid("json");
    const result = await activityLinkMutationStore.unlinkActivityLink({
      userId: session.userId,
      batchId: requestBody.idempotencyKey,
      deviceId: "app:activity-link",
      linkId: params.linkId
    });
    if (result.status === "not_found") {
      return context.json(
        ActivityLinkNotFoundResponseSchema.parse({
          code: "activity_link_not_found",
          message: "No Activity Link exists for this account with that id."
        }),
        404
      );
    }
    if (result.status === "conflict") {
      return context.json(
        ActivityLinkConflictResponseSchema.parse({
          code: "activity_link_conflict",
          message: "The Activity Link could not be unlinked."
        }),
        409
      );
    }

    return context.json(
      ActivityLinkMutationResponseSchema.parse(result.response),
      200
    );
  });

  app.openapi(accountDeletionRoute, async (context) => {
    if (accountDeletionStore === undefined) {
      return context.json(
        AccountDeletionUnavailableResponseSchema.parse({
          code: "account_deletion_unavailable",
          message: "Account deletion storage is not configured."
        }),
        503
      );
    }

    const token = readBearerToken(context.req.header("authorization"));
    if (token === null) {
      return context.json(
        SyncUnauthorizedResponseSchema.parse({
          code: "sync_unauthorized",
          message: "A session bearer token is required."
        }),
        401
      );
    }

    const result = await accountDeletionStore.requestAccountDeletion(token);
    if (result === null) {
      return context.json(
        SyncUnauthorizedResponseSchema.parse({
          code: "sync_unauthorized",
          message:
            "The session bearer token is invalid or the account is already local-only."
        }),
        401
      );
    }
    setRequestUserId(context, result.userId);

    return context.json(
      AccountDeletionResponseSchema.parse({
        deletionRequestedAt: result.deletionRequestedAt,
        localReplicaPreserved: true
      }),
      200
    );
  });

  app.openapi(agentApiKeyCreateRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }

    const session = await verifySessionBearer(context, agentApiKeyStore);
    if (session === null) {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A session bearer token is required."
        }),
        401
      );
    }

    const requestBody = context.req.valid("json");
    const created = await agentApiKeyStore.createAgentApiKey({
      userId: session.userId,
      name: requestBody.name
    });

    return context.json(AgentApiKeyCreateResponseSchema.parse(created), 201);
  });

  app.openapi(agentApiKeyListRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }

    const session = await verifySessionBearer(context, agentApiKeyStore);
    if (session === null) {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A session bearer token is required."
        }),
        401
      );
    }

    return context.json(
      AgentApiKeyListResponseSchema.parse({
        keys: await agentApiKeyStore.listAgentApiKeys(session.userId)
      }),
      200
    );
  });

  app.openapi(agentApiKeyRevokeRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }

    const session = await verifySessionBearer(context, agentApiKeyStore);
    if (session === null) {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A session bearer token is required."
        }),
        401
      );
    }

    const params = context.req.valid("param");
    const revoked = await agentApiKeyStore.revokeAgentApiKey({
      userId: session.userId,
      keyId: params.keyId
    });
    if (!revoked) {
      return context.json(
        AgentApiKeyNotFoundResponseSchema.parse({
          code: "agent_api_key_not_found",
          message: "No agent API key exists for this account with that id."
        }),
        404
      );
    }

    return context.json(
      AgentApiKeyRevokeResponseSchema.parse({ revoked: true }),
      200
    );
  });

  app.openapi(agentProtectedProbeRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;

    return context.json(
      AgentApiKeyProtectedProbeResponseSchema.parse({
        authenticated: true,
        userId: agent.userId,
        keyId: agent.keyId,
        keyName: agent.keyName
      }),
      200
    );
  });

  app.openapi(agentSetValidationRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }

    const requestBody = context.req.valid("json");
    const result = validateAgentSet(requestBody);
    const limits = setValidationLimitsResponse();
    if (result.errors.length > 0) {
      return context.json(
        AgentSetValidationErrorResponseSchema.parse({
          code: "agent_set_validation_failed",
          message: "Set failed hard validation.",
          errors: result.errors,
          warnings: result.warnings,
          limits
        }),
        422
      );
    }

    return context.json(
      AgentSetValidationResponseSchema.parse({
        accepted: true,
        warnings: result.warnings,
        limits
      }),
      200
    );
  });

  app.openapi(agentDoseValidationRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }

    const requestBody = context.req.valid("json");
    const result = validateAgentDose(requestBody);
    const limits = doseValidationLimitsResponse();
    if (result.errors.length > 0) {
      return context.json(
        AgentDoseValidationErrorResponseSchema.parse({
          code: "agent_dose_validation_failed",
          message: "Dose failed hard validation.",
          errors: result.errors,
          warnings: result.warnings,
          limits
        }),
        422
      );
    }

    return context.json(
      AgentDoseValidationResponseSchema.parse({
        accepted: true,
        warnings: result.warnings,
        limits
      }),
      200
    );
  });

  app.openapi(agentExerciseResolveRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentCatalogStore === undefined) {
      return context.json(
        AgentCatalogUnavailableResponseSchema.parse({
          code: "agent_catalog_unavailable",
          message: "Agent Exercise catalog storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;

    const query = context.req.valid("query");
    const result = await agentCatalogStore.resolveExerciseName({
      userId: agent.userId,
      name: query.name,
      candidateLimit: query.candidateLimit
    });

    return context.json(AgentExerciseResolveResponseSchema.parse(result), 200);
  });

  app.openapi(agentExerciseListRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentCatalogStore === undefined) {
      return context.json(
        AgentCatalogUnavailableResponseSchema.parse({
          code: "agent_catalog_unavailable",
          message: "Agent Exercise catalog storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;

    const query = parseAgentExerciseListQuery(context.req.valid("query"));
    const result = await agentCatalogStore.listExercises({
      userId: agent.userId,
      ...query
    });

    return context.json(AgentExerciseListResponseSchema.parse(result), 200);
  });

  app.openapi(agentWorkoutBatchWriteRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentCatalogStore === undefined) {
      return context.json(
        AgentCatalogUnavailableResponseSchema.parse({
          code: "agent_catalog_unavailable",
          message: "Agent Exercise catalog storage is not configured."
        }),
        503
      );
    }
    if (agentWorkoutBatchWriteStore === undefined) {
      return context.json(
        AgentWorkoutBatchWriteUnavailableResponseSchema.parse({
          code: "agent_batch_write_unavailable",
          message: "Agent workout batch write storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;

    const requestBody = context.req.valid("json");
    const prepared = await prepareAgentWorkoutBatchWrite({
      catalogStore: agentCatalogStore,
      request: requestBody,
      userId: agent.userId
    });
    if (!prepared.accepted) {
      return context.json(
        AgentWorkoutBatchWriteErrorResponseSchema.parse({
          code: "agent_batch_write_failed",
          message:
            "Batch contains one or more hard validation or Exercise resolution failures.",
          errors: prepared.errors,
          warnings: prepared.warnings,
          limits: setValidationLimitsResponse()
        }),
        422
      );
    }

    const writeResult = await agentWorkoutBatchWriteStore.writeWorkoutBatch({
      userId: agent.userId,
      batchId: requestBody.idempotencyKey,
      correlationId: requestCorrelationId(context),
      deviceId: `agent:${agent.keyId}`,
      workout: requestBody.workout,
      sets: prepared.sets
    });
    if (syncNudgePublisher !== undefined && writeResult.applied.length > 0) {
      try {
        await syncNudgePublisher.enqueueSyncNudge({
          userId: agent.userId,
          sourceDeviceId: `agent:${agent.keyId}`,
          reason: "agent_write"
        });
      } catch (error) {
        logger.error?.(
          {
            error,
            userId: agent.userId,
            keyId: agent.keyId,
            batchId: requestBody.idempotencyKey
          },
          "agent sync nudge enqueue failed"
        );
      }
    }

    return context.json(
      AgentWorkoutBatchWriteResponseSchema.parse({
        accepted: true,
        duplicate: writeResult.duplicate,
        idempotencyKey: requestBody.idempotencyKey,
        batchId: requestBody.idempotencyKey,
        workoutId: requestBody.workout.id,
        serverClock: writeResult.serverClock,
        sets: prepared.responseSets
      }),
      200
    );
  });

  app.openapi(agentExerciseCatalogBatchWriteRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentCatalogStore === undefined) {
      return context.json(
        AgentCatalogUnavailableResponseSchema.parse({
          code: "agent_catalog_unavailable",
          message: "Agent Exercise catalog storage is not configured."
        }),
        503
      );
    }
    if (agentExerciseCatalogBatchWriteStore === undefined) {
      return context.json(
        AgentExerciseCatalogBatchWriteUnavailableResponseSchema.parse({
          code: "agent_exercise_catalog_batch_write_unavailable",
          message:
            "Agent Exercise catalog batch write storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;

    const requestBody = context.req.valid("json");
    const prepared = await prepareAgentExerciseCatalogBatchWrite({
      catalogStore: agentCatalogStore,
      request: requestBody,
      userId: agent.userId
    });
    if (!prepared.accepted) {
      return context.json(
        AgentExerciseCatalogBatchWriteErrorResponseSchema.parse({
          code: "agent_exercise_catalog_batch_write_failed",
          message:
            "Batch contains one or more hard validation or reference resolution failures.",
          errors: prepared.errors,
          warnings: prepared.warnings
        }),
        422
      );
    }

    const writeResult =
      await agentExerciseCatalogBatchWriteStore.writeExerciseCatalogBatch({
        userId: agent.userId,
        batchId: requestBody.idempotencyKey,
        correlationId: requestCorrelationId(context),
        deviceId: `agent:${agent.keyId}`,
        categories: prepared.categories,
        exercises: prepared.exercises
      });
    if (syncNudgePublisher !== undefined && writeResult.applied.length > 0) {
      try {
        await syncNudgePublisher.enqueueSyncNudge({
          userId: agent.userId,
          sourceDeviceId: `agent:${agent.keyId}`,
          reason: "agent_write"
        });
      } catch (error) {
        logger.error?.(
          {
            error,
            userId: agent.userId,
            keyId: agent.keyId,
            batchId: requestBody.idempotencyKey
          },
          "agent sync nudge enqueue failed"
        );
      }
    }

    return context.json(
      AgentExerciseCatalogBatchWriteResponseSchema.parse({
        accepted: true,
        duplicate: writeResult.duplicate,
        idempotencyKey: requestBody.idempotencyKey,
        batchId: requestBody.idempotencyKey,
        serverClock: writeResult.serverClock,
        categories: prepared.responseCategories,
        exercises: prepared.responseExercises
      }),
      200
    );
  });

  app.openapi(agentMealBatchWriteRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentMealBatchWriteStore === undefined) {
      return context.json(
        AgentMealBatchWriteUnavailableResponseSchema.parse({
          code: "agent_meal_batch_write_unavailable",
          message: "Agent meal batch write storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;

    const requestBody = context.req.valid("json");
    const prepared = await prepareAgentMealBatchWrite({
      request: requestBody,
      userId: agent.userId,
      foodCatalogStore: agentFoodCatalogStore
    });
    if (!prepared.accepted) {
      return context.json(
        AgentMealBatchWriteErrorResponseSchema.parse({
          code: "agent_meal_batch_write_failed",
          message:
            "Batch contains one or more hard validation failures.",
          errors: prepared.errors,
          warnings: prepared.warnings,
          limits: nutrientValidationLimitsResponse()
        }),
        422
      );
    }

    const writeResult = await agentMealBatchWriteStore.writeMealBatch({
      userId: agent.userId,
      batchId: requestBody.idempotencyKey,
      correlationId: requestCorrelationId(context),
      deviceId: `agent:${agent.keyId}`,
      meal: prepared.meal,
      entries: prepared.entries
    });
    if (syncNudgePublisher !== undefined && writeResult.applied.length > 0) {
      try {
        await syncNudgePublisher.enqueueSyncNudge({
          userId: agent.userId,
          sourceDeviceId: `agent:${agent.keyId}`,
          reason: "agent_write"
        });
      } catch (error) {
        logger.error?.(
          {
            error,
            userId: agent.userId,
            keyId: agent.keyId,
            batchId: requestBody.idempotencyKey
          },
          "agent sync nudge enqueue failed"
        );
      }
    }

    return context.json(
      AgentMealBatchWriteResponseSchema.parse({
        accepted: true,
        duplicate: writeResult.duplicate,
        idempotencyKey: requestBody.idempotencyKey,
        batchId: requestBody.idempotencyKey,
        mealId: requestBody.meal.id,
        serverClock: writeResult.serverClock,
        entries: prepared.responseEntries
      }),
      200
    );
  });

  // ----- Agent food library surface -----

  app.openapi(agentFoodListRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentFoodCatalogStore === undefined) {
      return context.json(
        AgentFoodsUnavailableResponseSchema.parse({
          code: "agent_foods_unavailable",
          message: "Agent Food catalog storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }

    const result = await agentFoodCatalogStore.listFoods({
      userId: agentAuth.agent.userId,
      ...parseAgentFoodListQuery(context.req.valid("query"))
    });

    return context.json(AgentFoodListResponseSchema.parse(result), 200);
  });

  app.openapi(agentFoodPlatformSearchRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }

    const query = context.req.valid("query");
    const result = searchAgentPlatformFoods({
      search: query.search,
      limit: query.limit
    });

    return context.json(
      AgentFoodPlatformSearchResponseSchema.parse(result),
      200
    );
  });

  app.openapi(agentFoodBatchWriteRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentFoodBatchWriteStore === undefined) {
      return context.json(
        AgentFoodsUnavailableResponseSchema.parse({
          code: "agent_foods_unavailable",
          message: "Agent Food batch write storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;

    const requestBody = context.req.valid("json");
    const prepared = prepareAgentFoodBatchWrite({ request: requestBody });
    if (!prepared.accepted) {
      return context.json(
        AgentFoodBatchWriteErrorResponseSchema.parse({
          code: "agent_food_batch_write_failed",
          message: "Batch contains one or more hard validation failures.",
          errors: prepared.errors,
          warnings: prepared.warnings,
          limits: nutrientValidationLimitsForFoods()
        }),
        422
      );
    }

    const writeResult = await agentFoodBatchWriteStore.writeFoodBatch({
      userId: agent.userId,
      batchId: requestBody.idempotencyKey,
      correlationId: requestCorrelationId(context),
      deviceId: `agent:${agent.keyId}`,
      foods: prepared.foods
    });
    if (syncNudgePublisher !== undefined && writeResult.applied.length > 0) {
      try {
        await syncNudgePublisher.enqueueSyncNudge({
          userId: agent.userId,
          sourceDeviceId: `agent:${agent.keyId}`,
          reason: "agent_write"
        });
      } catch (error) {
        logger.error?.(
          {
            error,
            userId: agent.userId,
            keyId: agent.keyId,
            batchId: requestBody.idempotencyKey
          },
          "agent sync nudge enqueue failed"
        );
      }
    }

    return context.json(
      AgentFoodBatchWriteResponseSchema.parse({
        accepted: true,
        duplicate: writeResult.duplicate,
        idempotencyKey: requestBody.idempotencyKey,
        batchId: requestBody.idempotencyKey,
        serverClock: writeResult.serverClock,
        foods: prepared.responseFoods
      }),
      200
    );
  });

  app.openapi(agentMetricListRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentMetricStore === undefined) {
      return context.json(
        AgentMetricUnavailableResponseSchema.parse({
          code: "agent_metric_unavailable",
          message: "Agent Metric storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }

    const result = await agentMetricStore.listMetrics({
      userId: agentAuth.agent.userId,
      query: context.req.valid("query")
    });

    return context.json(AgentMetricListResponseSchema.parse(result), 200);
  });

  app.openapi(agentMetricReadingsRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentMetricStore === undefined) {
      return context.json(
        AgentMetricUnavailableResponseSchema.parse({
          code: "agent_metric_unavailable",
          message: "Agent Metric storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }

    const result = await agentMetricStore.listMetricReadings({
      userId: agentAuth.agent.userId,
      query: context.req.valid("query")
    });

    return context.json(AgentMetricReadingsResponseSchema.parse(result), 200);
  });

  app.openapi(agentMetricBatchWriteRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentMetricStore === undefined) {
      return context.json(
        AgentMetricUnavailableResponseSchema.parse({
          code: "agent_metric_unavailable",
          message: "Agent Metric storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;

    const requestBody = context.req.valid("json");
    const writeResult = await agentMetricStore.writeMetricBatch({
      userId: agent.userId,
      batchId: requestBody.idempotencyKey,
      correlationId: requestCorrelationId(context),
      deviceId: `agent:${agent.keyId}`,
      request: requestBody
    });
    if (!writeResult.accepted) {
      return context.json(
        AgentMetricBatchWriteErrorResponseSchema.parse({
          code: "agent_metric_batch_write_failed",
          message:
            "Batch contains one or more hard Metric validation failures.",
          errors: writeResult.errors,
          warnings: writeResult.warnings
        }),
        422
      );
    }
    if (
      syncNudgePublisher !== undefined &&
      writeResult.activityLogEntries > 0
    ) {
      try {
        await syncNudgePublisher.enqueueSyncNudge({
          userId: agent.userId,
          sourceDeviceId: `agent:${agent.keyId}`,
          reason: "agent_write"
        });
      } catch (error) {
        logger.error?.(
          {
            error,
            userId: agent.userId,
            keyId: agent.keyId,
            batchId: requestBody.idempotencyKey
          },
          "agent sync nudge enqueue failed"
        );
      }
    }

    return context.json(
      AgentMetricBatchWriteResponseSchema.parse({
        accepted: true,
        duplicate: writeResult.duplicate,
        idempotencyKey: requestBody.idempotencyKey,
        batchId: requestBody.idempotencyKey,
        serverClock: writeResult.serverClock,
        metrics: writeResult.metrics,
        readings: writeResult.readings
      }),
      200
    );
  });

  // ----- Agent Activity Log read + batch undo -----

  app.openapi(agentActivityListRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentActivityStore === undefined) {
      return context.json(
        AgentActivityUnavailableResponseSchema.parse({
          code: "agent_activity_unavailable",
          message: "Agent Activity Log storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }

    const result = await agentActivityStore.listActivity({
      userId: agentAuth.agent.userId,
      query: context.req.valid("query")
    });

    return context.json(AgentActivityListResponseSchema.parse(result), 200);
  });

  app.openapi(agentActivityUndoBatchRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentActivityStore === undefined) {
      return context.json(
        AgentActivityUnavailableResponseSchema.parse({
          code: "agent_activity_unavailable",
          message: "Agent Activity Log storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;

    const requestBody = context.req.valid("json");
    const sourceDeviceId = `agent:${agent.keyId}`;
    const undoResult = await agentActivityStore.undoBatch({
      userId: agent.userId,
      batchId: requestBody.batchId,
      idempotencyKey: requestBody.idempotencyKey,
      deviceId: sourceDeviceId
    });
    if (!undoResult.accepted) {
      return context.json(
        AgentActivityBatchNotFoundResponseSchema.parse({
          code: "activity_batch_not_found",
          message: "No Activity Log batch with that id is visible to the caller."
        }),
        404
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
            batchId: requestBody.idempotencyKey
          },
          "agent sync nudge enqueue failed"
        );
      }
    }

    return context.json(
      AgentActivityUndoBatchResponseSchema.parse({
        accepted: true,
        applied: undoResult.applied,
        duplicate: undoResult.duplicate,
        originalBatchId: requestBody.batchId,
        undoBatchId: undoResult.undoBatchId,
        serverClock: undoResult.serverClock,
        entries: undoResult.entries.map((entry) => ({
          entryId: entry.entryId,
          entityTable: entry.entityTable,
          entityId: entry.entityId,
          outcome: entry.outcome
        }))
      }),
      200
    );
  });

  // ----- Protocols agent surface -----

  app.openapi(agentCompoundListRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentProtocolsStore === undefined) {
      return context.json(
        AgentProtocolsUnavailableResponseSchema.parse({
          code: "agent_protocols_unavailable",
          message: "Agent Protocols storage is not configured."
        }),
        503
      );
    }
    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const result = await agentProtocolsStore.listCompounds({
      userId: agentAuth.agent.userId,
      query: context.req.valid("query")
    });
    return context.json(AgentCompoundListResponseSchema.parse(result), 200);
  });

  app.openapi(agentProtocolListRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentProtocolsStore === undefined) {
      return context.json(
        AgentProtocolsUnavailableResponseSchema.parse({
          code: "agent_protocols_unavailable",
          message: "Agent Protocols storage is not configured."
        }),
        503
      );
    }
    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const result = await agentProtocolsStore.listProtocols({
      userId: agentAuth.agent.userId,
      query: context.req.valid("query")
    });
    return context.json(AgentProtocolListResponseSchema.parse(result), 200);
  });

  app.openapi(agentDoseListRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentProtocolsStore === undefined) {
      return context.json(
        AgentProtocolsUnavailableResponseSchema.parse({
          code: "agent_protocols_unavailable",
          message: "Agent Protocols storage is not configured."
        }),
        503
      );
    }
    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const result = await agentProtocolsStore.listDoses({
      userId: agentAuth.agent.userId,
      query: context.req.valid("query")
    });
    return context.json(AgentDoseListResponseSchema.parse(result), 200);
  });

  app.openapi(agentEffectWindowRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentProtocolsStore === undefined) {
      return context.json(
        AgentProtocolsUnavailableResponseSchema.parse({
          code: "agent_protocols_unavailable",
          message: "Agent Protocols storage is not configured."
        }),
        503
      );
    }
    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const result = await agentProtocolsStore.readEffectWindow({
      userId: agentAuth.agent.userId,
      query: context.req.valid("query")
    });
    if (!result.ok) {
      return context.json(
        AgentEffectWindowErrorResponseSchema.parse({
          code: "agent_effect_window_invalid_request",
          message: result.message
        }),
        422
      );
    }
    return context.json(
      AgentEffectWindowResponseSchema.parse(result.value),
      200
    );
  });

  app.openapi(agentDoseBatchWriteRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentProtocolsStore === undefined) {
      return context.json(
        AgentProtocolsUnavailableResponseSchema.parse({
          code: "agent_protocols_unavailable",
          message: "Agent Protocols storage is not configured."
        }),
        503
      );
    }
    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;
    const requestBody = context.req.valid("json");
    const prepared = prepareAgentDoseBatchWrite({ request: requestBody });
    if (!prepared.accepted) {
      return context.json(
        AgentDoseBatchWriteErrorResponseSchema.parse({
          code: "agent_dose_batch_write_failed",
          message: "Batch contains one or more hard dose validation failures.",
          errors: prepared.errors,
          warnings: prepared.warnings,
          limits: doseValidationLimitsResponse()
        }),
        422
      );
    }
    const writeResult = await agentProtocolsStore.writeDoseBatch({
      userId: agent.userId,
      batchId: requestBody.idempotencyKey,
      requestFingerprint: agentProtocolsBatchRequestFingerprint(requestBody),
      deviceId: `agent:${agent.keyId}`,
      doses: prepared.doses
    });
    const writeFailure = agentProtocolsWriteFailure(writeResult);
    if (writeFailure !== null) {
      return writeFailure.status === 422
        ? context.json(writeFailure.body, 422)
        : context.json(writeFailure.body, 503);
    }
    await maybeNudgeAgentWrite({
      syncNudgePublisher,
      logger,
      agent,
      batchId: requestBody.idempotencyKey,
      applied: writeResult.applied.length
    });
    return context.json(
      AgentDoseBatchWriteResponseSchema.parse({
        accepted: true,
        duplicate: writeResult.duplicate,
        idempotencyKey: requestBody.idempotencyKey,
        batchId: requestBody.idempotencyKey,
        serverClock: writeResult.serverClock,
        doses: finalizeAgentDoseBatchWriteResults({
          applied: writeResult.applied,
          accepted: writeResult.accepted,
          duplicate: writeResult.duplicate,
          results: prepared.responseDoses
        })
      }),
      200
    );
  });

  app.openapi(agentCompoundBatchWriteRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentProtocolsStore === undefined) {
      return context.json(
        AgentProtocolsUnavailableResponseSchema.parse({
          code: "agent_protocols_unavailable",
          message: "Agent Protocols storage is not configured."
        }),
        503
      );
    }
    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;
    const requestBody = context.req.valid("json");
    const prepared = prepareAgentCompoundBatchWrite({ request: requestBody });
    if (!prepared.accepted) {
      return context.json(
        AgentProtocolsBatchWriteErrorResponseSchema.parse({
          code: "agent_protocols_batch_write_failed",
          message: "Batch contains one or more hard validation failures.",
          errors: prepared.errors,
          warnings: []
        }),
        422
      );
    }
    const writeResult = await agentProtocolsStore.writeCompoundBatch({
      userId: agent.userId,
      batchId: requestBody.idempotencyKey,
      requestFingerprint: agentProtocolsBatchRequestFingerprint(requestBody),
      deviceId: `agent:${agent.keyId}`,
      compounds: prepared.compounds
    });
    const writeFailure = agentProtocolsWriteFailure(writeResult);
    if (writeFailure !== null) {
      return writeFailure.status === 422
        ? context.json(writeFailure.body, 422)
        : context.json(writeFailure.body, 503);
    }
    await maybeNudgeAgentWrite({
      syncNudgePublisher,
      logger,
      agent,
      batchId: requestBody.idempotencyKey,
      applied: writeResult.applied.length
    });
    return context.json(
      AgentCompoundBatchWriteResponseSchema.parse({
        accepted: true,
        duplicate: writeResult.duplicate,
        idempotencyKey: requestBody.idempotencyKey,
        batchId: requestBody.idempotencyKey,
        serverClock: writeResult.serverClock,
        compounds: finalizeAgentProtocolsEntityBatchWriteResults({
          applied: writeResult.applied,
          accepted: writeResult.accepted,
          duplicate: writeResult.duplicate,
          results: prepared.responseCompounds
        })
      }),
      200
    );
  });

  app.openapi(agentProtocolBatchWriteRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentProtocolsStore === undefined) {
      return context.json(
        AgentProtocolsUnavailableResponseSchema.parse({
          code: "agent_protocols_unavailable",
          message: "Agent Protocols storage is not configured."
        }),
        503
      );
    }
    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;
    const requestBody = context.req.valid("json");
    const prepared = prepareAgentProtocolBatchWrite({ request: requestBody });
    if (!prepared.accepted) {
      return context.json(
        AgentProtocolsBatchWriteErrorResponseSchema.parse({
          code: "agent_protocols_batch_write_failed",
          message: "Batch contains one or more hard validation failures.",
          errors: prepared.errors,
          warnings: []
        }),
        422
      );
    }
    const writeResult = await agentProtocolsStore.writeProtocolBatch({
      userId: agent.userId,
      batchId: requestBody.idempotencyKey,
      requestFingerprint: agentProtocolsBatchRequestFingerprint(requestBody),
      deviceId: `agent:${agent.keyId}`,
      protocols: prepared.protocols,
      members: prepared.members,
      schedules: prepared.schedules,
      targetOutcomes: prepared.targetOutcomes
    });
    const writeFailure = agentProtocolsWriteFailure(writeResult);
    if (writeFailure !== null) {
      return writeFailure.status === 422
        ? context.json(writeFailure.body, 422)
        : context.json(writeFailure.body, 503);
    }
    await maybeNudgeAgentWrite({
      syncNudgePublisher,
      logger,
      agent,
      batchId: requestBody.idempotencyKey,
      applied: writeResult.applied.length
    });
    return context.json(
      AgentProtocolBatchWriteResponseSchema.parse({
        accepted: true,
        duplicate: writeResult.duplicate,
        idempotencyKey: requestBody.idempotencyKey,
        batchId: requestBody.idempotencyKey,
        serverClock: writeResult.serverClock,
        protocols: finalizeAgentProtocolsEntityBatchWriteResults({
          applied: writeResult.applied,
          accepted: writeResult.accepted,
          duplicate: writeResult.duplicate,
          results: prepared.responseProtocols
        })
      }),
      200
    );
  });

  app.openapi(agentExerciseAnalyticsRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentCatalogStore === undefined) {
      return context.json(
        AgentCatalogUnavailableResponseSchema.parse({
          code: "agent_catalog_unavailable",
          message: "Agent Exercise catalog storage is not configured."
        }),
        503
      );
    }
    if (agentReadStore === undefined) {
      return context.json(
        AgentReadUnavailableResponseSchema.parse({
          code: "agent_read_unavailable",
          message: "Agent read storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;

    const params = context.req.valid("param");
    const query = context.req.valid("query");
    const exercise = await agentCatalogStore.getExerciseById({
      userId: agent.userId,
      exerciseId: params.exerciseId
    });
    if (exercise === null) {
      return context.json(
        AgentReadExerciseNotFoundResponseSchema.parse({
          code: "agent_exercise_not_found",
          message: "Exercise is not visible to the authenticated account."
        }),
        404
      );
    }

    const sets = await agentReadStore.readExerciseSets({
      userId: agent.userId,
      exerciseId: params.exerciseId,
      from: query.from,
      to: query.to
    });

    return context.json(
      AgentExerciseAnalyticsResponseSchema.parse(
        buildAgentExerciseAnalyticsResponse({
          exercise,
          maxPoints: query.maxPoints,
          sets
        })
      ),
      200
    );
  });

  app.openapi(agentHistorySetsRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentReadStore === undefined) {
      return context.json(
        AgentReadUnavailableResponseSchema.parse({
          code: "agent_read_unavailable",
          message: "Agent read storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;

    return context.json(
      AgentHistorySetsResponseSchema.parse(
        await agentReadStore.listHistory({
          userId: agent.userId,
          query: context.req.valid("query")
        })
      ),
      200
    );
  });

  app.openapi(agentWorkoutListRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentReadStore === undefined) {
      return context.json(
        AgentReadUnavailableResponseSchema.parse({
          code: "agent_read_unavailable",
          message: "Agent read storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;

    return context.json(
      AgentWorkoutListResponseSchema.parse(
        await agentReadStore.listWorkouts({
          userId: agent.userId,
          query: context.req.valid("query")
        })
      ),
      200
    );
  });

  app.openapi(agentWorkoutDetailRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentReadStore === undefined) {
      return context.json(
        AgentReadUnavailableResponseSchema.parse({
          code: "agent_read_unavailable",
          message: "Agent read storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }

    const params = context.req.valid("param");
    const workout = await agentReadStore.getWorkout({
      userId: agentAuth.agent.userId,
      workoutId: params.workoutId
    });
    if (workout === null) {
      return context.json(
        AgentWorkoutDetailNotFoundResponseSchema.parse({
          code: "agent_workout_not_found",
          message: "The Workout was not found for this account."
        }),
        404
      );
    }

    return context.json(AgentWorkoutDetailResponseSchema.parse(workout), 200);
  });

  app.openapi(agentMonitoringActivityRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentReadStore === undefined) {
      return context.json(
        AgentReadUnavailableResponseSchema.parse({
          code: "agent_read_unavailable",
          message: "Agent read storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;
    const params = context.req.valid("param");
    const monitoring = await agentReadStore.readMonitoringActivity({
      userId: agent.userId,
      agentKeyId: agent.keyId,
      externalActivityId: params.externalActivityId
    });
    if (monitoring === null) {
      return context.json(
        AgentMonitoringActivityNotFoundResponseSchema.parse({
          code: "agent_monitoring_activity_not_found",
          message: "External Activity is not visible to the authenticated account."
        }),
        404
      );
    }

    return context.json(
      AgentMonitoringActivityResponseSchema.parse(monitoring),
      200
    );
  });

  app.openapi(agentNutritionTotalsRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentNutritionReadStore === undefined) {
      return context.json(
        AgentNutritionReadUnavailableResponseSchema.parse({
          code: "agent_nutrition_read_unavailable",
          message: "Agent nutrition read storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;

    const query = context.req.valid("query");
    const range = validateNutritionRange(query.from, query.to);
    if (!range.ok) {
      return context.json(
        AgentNutritionReadInvalidRangeResponseSchema.parse({
          code: "agent_nutrition_read_invalid_range",
          message: range.message
        }),
        422
      );
    }

    const days = await agentNutritionReadStore.readNutritionDays({
      userId: agent.userId,
      from: query.from,
      to: query.to
    });
    const { goals, goalSource } = await resolvedNutritionGoals({
      userId: agent.userId,
      query,
      agentNutritionGoalStore
    });

    return context.json(
      AgentNutritionTotalsResponseSchema.parse(
        buildAgentNutritionTotalsResponse({
          from: query.from,
          to: query.to,
          days,
          goals,
          goalSource
        })
      ),
      200
    );
  });

  app.openapi(agentNutritionTrendsRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentNutritionReadStore === undefined) {
      return context.json(
        AgentNutritionReadUnavailableResponseSchema.parse({
          code: "agent_nutrition_read_unavailable",
          message: "Agent nutrition read storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;

    const query = context.req.valid("query");
    const range = validateNutritionRange(query.from, query.to);
    if (!range.ok) {
      return context.json(
        AgentNutritionReadInvalidRangeResponseSchema.parse({
          code: "agent_nutrition_read_invalid_range",
          message: range.message
        }),
        422
      );
    }

    const days = await agentNutritionReadStore.readNutritionDays({
      userId: agent.userId,
      from: query.from,
      to: query.to
    });
    const { goals, goalSource } = await resolvedNutritionGoals({
      userId: agent.userId,
      query,
      agentNutritionGoalStore
    });

    return context.json(
      AgentNutritionTrendsResponseSchema.parse(
        buildAgentNutritionTrendsResponse({
          from: query.from,
          to: query.to,
          days,
          goals,
          goalSource
        })
      ),
      200
    );
  });

  app.openapi(agentMealListRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentNutritionReadStore === undefined) {
      return context.json(
        AgentNutritionReadUnavailableResponseSchema.parse({
          code: "agent_nutrition_read_unavailable",
          message: "Agent nutrition read storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;

    return context.json(
      AgentMealListResponseSchema.parse(
        await agentNutritionReadStore.listMeals({
          userId: agent.userId,
          query: context.req.valid("query")
        })
      ),
      200
    );
  });

  app.openapi(agentNutritionGoalListRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentNutritionGoalStore === undefined) {
      return context.json(
        AgentNutritionGoalUnavailableResponseSchema.parse({
          code: "agent_nutrition_goal_unavailable",
          message: "Agent Nutrition Goal storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }

    const goals = await agentNutritionGoalStore.listNutritionGoals({
      userId: agentAuth.agent.userId
    });

    return context.json(
      AgentNutritionGoalListResponseSchema.parse({ goals }),
      200
    );
  });

  app.openapi(agentNutritionGoalBatchWriteRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentNutritionGoalStore === undefined) {
      return context.json(
        AgentNutritionGoalUnavailableResponseSchema.parse({
          code: "agent_nutrition_goal_unavailable",
          message: "Agent Nutrition Goal storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;

    const requestBody = context.req.valid("json");
    const writeResult = await agentNutritionGoalStore.writeNutritionGoalBatch({
      userId: agent.userId,
      batchId: requestBody.idempotencyKey,
      correlationId: requestCorrelationId(context),
      deviceId: `agent:${agent.keyId}`,
      request: requestBody
    });
    if (!writeResult.accepted) {
      return context.json(
        AgentNutritionGoalBatchWriteErrorResponseSchema.parse({
          code: "agent_nutrition_goal_batch_write_failed",
          message:
            "Batch contains one or more hard Nutrition Goal validation failures.",
          errors: writeResult.errors
        }),
        422
      );
    }
    if (syncNudgePublisher !== undefined && writeResult.applied.length > 0) {
      try {
        await syncNudgePublisher.enqueueSyncNudge({
          userId: agent.userId,
          sourceDeviceId: `agent:${agent.keyId}`,
          reason: "agent_write"
        });
      } catch (error) {
        logger.error?.(
          {
            error,
            userId: agent.userId,
            keyId: agent.keyId,
            batchId: requestBody.idempotencyKey
          },
          "agent sync nudge enqueue failed"
        );
      }
    }

    return context.json(
      AgentNutritionGoalBatchWriteResponseSchema.parse({
        accepted: true,
        duplicate: writeResult.duplicate,
        idempotencyKey: requestBody.idempotencyKey,
        batchId: requestBody.idempotencyKey,
        serverClock: writeResult.serverClock,
        targets: writeResult.targets
      }),
      200
    );
  });

  const resolveAgentPlanReadContext = async (context: Context<AppEnv>) => {
    if (agentApiKeyStore === undefined) {
      return {
        status: "error" as const,
        response: context.json(
          AgentApiKeyUnavailableResponseSchema.parse({
            code: "agent_api_keys_unavailable",
            message: "Agent API key storage is not configured."
          }),
          503
        )
      };
    }
    if (agentPlanReadStore === undefined) {
      return {
        status: "error" as const,
        response: context.json(
          AgentPlanReadUnavailableResponseSchema.parse({
            code: "agent_plan_read_unavailable",
            message: "Agent plan read storage is not configured."
          }),
          503
        )
      };
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return {
        status: "error" as const,
        response: context.json(
          AgentUnauthorizedResponseSchema.parse({
            code: "agent_unauthorized",
            message: "A valid agent API key is required."
          }),
          401
        )
      };
    }
    if (agentAuth.status === "rate_limited") {
      return { status: "error" as const, response: agentAuth.response };
    }
    return {
      status: "ready" as const,
      userId: agentAuth.agent.userId,
      store: agentPlanReadStore
    };
  };

  app.openapi(agentWorkoutTemplateListRoute, async (context) => {
    const planRead = await resolveAgentPlanReadContext(context);
    if (planRead.status === "error") {
      return planRead.response;
    }

    try {
      const result = await planRead.store.listWorkoutTemplates({
        userId: planRead.userId,
        query: context.req.valid("query")
      });
      return context.json(result, 200);
    } catch (error) {
      if (error instanceof AgentPlanInvalidCursorError) {
        return context.json(agentPlanInvalidCursorResponse(), 400);
      }
      throw error;
    }
  });

  app.openapi(agentWorkoutTemplateDetailRoute, async (context) => {
    const planRead = await resolveAgentPlanReadContext(context);
    if (planRead.status === "error") {
      return planRead.response;
    }

    const params = context.req.valid("param");
    const result = await planRead.store.getWorkoutTemplate({
      userId: planRead.userId,
      workoutTemplateId: params.workoutTemplateId,
      query: context.req.valid("query")
    });
    if (result === null) {
      return context.json(
        AgentPlanNotFoundResponseSchema.parse({
          code: "agent_workout_template_not_found",
          message: "Workout Template was not found."
        }),
        404
      );
    }
    return context.json(result, 200);
  });

  app.openapi(agentRoutineListRoute, async (context) => {
    const planRead = await resolveAgentPlanReadContext(context);
    if (planRead.status === "error") {
      return planRead.response;
    }

    try {
      const result = await planRead.store.listRoutines({
        userId: planRead.userId,
        query: context.req.valid("query")
      });
      return context.json(result, 200);
    } catch (error) {
      if (error instanceof AgentPlanInvalidCursorError) {
        return context.json(agentPlanInvalidCursorResponse(), 400);
      }
      throw error;
    }
  });

  app.openapi(agentRoutineDetailRoute, async (context) => {
    const planRead = await resolveAgentPlanReadContext(context);
    if (planRead.status === "error") {
      return planRead.response;
    }

    const params = context.req.valid("param");
    const result = await planRead.store.getRoutine({
      userId: planRead.userId,
      routineId: params.routineId,
      query: context.req.valid("query")
    });
    if (result === null) {
      return context.json(
        AgentPlanNotFoundResponseSchema.parse({
          code: "agent_routine_not_found",
          message: "Routine was not found."
        }),
        404
      );
    }
    return context.json(result, 200);
  });

  app.openapi(agentPlanTreeBatchWriteRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentPlanTreeBatchWriteStore === undefined) {
      return context.json(
        AgentPlanTreeBatchWriteUnavailableResponseSchema.parse({
          code: "agent_plan_tree_batch_write_unavailable",
          message: "Agent plan-tree batch write storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;
    const requestBody = context.req.valid("json");
    const result = await runAgentPlanTreeBatchWrite({
      afterWrite: async ({ applied }) =>
        maybeNudgeAgentWrite({
          syncNudgePublisher,
          logger,
          agent,
          batchId: requestBody.idempotencyKey,
          applied
        }),
      catalogStore: agentCatalogStore,
      deviceId: `agent:${agent.keyId}`,
      request: requestBody,
      store: agentPlanTreeBatchWriteStore,
      userId: agent.userId
    });
    if (result.status === "catalog_unavailable") {
      return context.json(result.body, 503);
    }
    if (result.status === "validation_failed") {
      return context.json(result.body, 422);
    }
    return context.json(result.body, 200);
  });

  app.openapi(agentPlanMaterializeRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }

    const agent = agentAuth.agent;
    const requestBody = context.req.valid("json");
    const result = await runAgentPlanMaterializeForAgent({
      agent,
      catalogStore: agentCatalogStore,
      logger,
      request: requestBody,
      store: agentPlanMaterializeStore,
      syncNudgePublisher
    });
    if (
      result.status === "catalog_unavailable" ||
      result.status === "unavailable"
    ) {
      return context.json(result.body, 503);
    }
    if (result.status === "not_found") {
      return context.json(result.body, 404);
    }
    if (result.status === "validation_failed") {
      return context.json(result.body, 422);
    }
    return context.json(result.body, 200);
  });

  app.openapi(agentPlanCaptureRoute, async (context) => {
    return handleAgentPlanVerbRequest({
      context,
      agentApiKeyStore,
      acceptedSchema: AgentPlanCaptureResponseSchema,
      rateLimitBackend,
      logger,
      run: (agent) =>
        runAgentPlanCaptureForAgent({
          agent,
          catalogStore: agentCatalogStore,
          logger,
          request: context.req.valid("json"),
          store: agentPlanCaptureStore,
          syncNudgePublisher
        })
    });
  });

  app.openapi(agentPlanUpdateFromWorkoutRoute, async (context) => {
    return handleAgentPlanVerbRequest({
      context,
      agentApiKeyStore,
      acceptedSchema: AgentPlanUpdateFromWorkoutResponseSchema,
      rateLimitBackend,
      logger,
      run: (agent) =>
        runAgentPlanUpdateFromWorkoutForAgent({
          agent,
          catalogStore: agentCatalogStore,
          logger,
          request: context.req.valid("json"),
          store: agentPlanCaptureStore,
          syncNudgePublisher
        })
    });
  });

  app.openapi(agentSettingsReadRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentSettingsStore === undefined) {
      return context.json(
        AgentSettingsUnavailableResponseSchema.parse({
          code: "agent_settings_unavailable",
          message: "Agent Settings storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }

    const read = await agentSettingsStore.readSettings({
      userId: agentAuth.agent.userId
    });

    return context.json(
      AgentSettingsReadResponseSchema.parse({
        settings: read.settings,
        updatedAt: read.updatedAt
      }),
      200
    );
  });

  app.openapi(agentSettingsBatchWriteRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (agentSettingsStore === undefined) {
      return context.json(
        AgentSettingsUnavailableResponseSchema.parse({
          code: "agent_settings_unavailable",
          message: "Agent Settings storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;

    const requestBody = context.req.valid("json");
    const writeResult = await agentSettingsStore.writeSettingsBatch({
      userId: agent.userId,
      batchId: requestBody.idempotencyKey,
      correlationId: requestCorrelationId(context),
      deviceId: `agent:${agent.keyId}`,
      request: requestBody
    });
    if (!writeResult.accepted) {
      return context.json(
        AgentSettingsBatchWriteErrorResponseSchema.parse({
          code: "agent_settings_batch_write_failed",
          message:
            "Settings write contains one or more hard validation failures.",
          errors: writeResult.errors
        }),
        422
      );
    }
    if (syncNudgePublisher !== undefined && !writeResult.duplicate) {
      try {
        await syncNudgePublisher.enqueueSyncNudge({
          userId: agent.userId,
          sourceDeviceId: `agent:${agent.keyId}`,
          reason: "agent_write"
        });
      } catch (error) {
        logger.error?.(
          {
            error,
            userId: agent.userId,
            keyId: agent.keyId,
            batchId: requestBody.idempotencyKey
          },
          "agent settings sync nudge enqueue failed"
        );
      }
    }

    return context.json(
      AgentSettingsBatchWriteResponseSchema.parse({
        accepted: true,
        duplicate: writeResult.duplicate,
        idempotencyKey: requestBody.idempotencyKey,
        batchId: requestBody.idempotencyKey,
        serverClock: writeResult.serverClock,
        settings: writeResult.settings,
        updatedAt: writeResult.updatedAt
      }),
      200
    );
  });

  app.openapi(agentEnergyBalanceRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (
      agentNutritionReadStore === undefined ||
      agentCrossDomainReadStore === undefined
    ) {
      return context.json(
        AgentNutritionReadUnavailableResponseSchema.parse({
          code: "agent_nutrition_read_unavailable",
          message: "Agent cross-domain read storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;

    const query = context.req.valid("query");
    const range = validateCrossDomainRange(query.from, query.to);
    if (!range.ok) {
      return context.json(
        AgentNutritionReadInvalidRangeResponseSchema.parse({
          code: "agent_nutrition_read_invalid_range",
          message: range.message
        }),
        422
      );
    }

    const [nutritionDays, caloriesBurned] = await Promise.all([
      agentNutritionReadStore.readNutritionDays({
        userId: agent.userId,
        from: query.from,
        to: query.to
      }),
      agentCrossDomainReadStore.readCaloriesBurnedReadings({
        userId: agent.userId,
        from: query.from,
        to: query.to
      })
    ]);

    return context.json(
      AgentEnergyBalanceResponseSchema.parse(
        buildAgentEnergyBalanceResponse({
          from: query.from,
          to: query.to,
          nutritionDays,
          caloriesBurned
        })
      ),
      200
    );
  });

  app.openapi(agentTrainingDayNutritionRoute, async (context) => {
    if (agentApiKeyStore === undefined) {
      return context.json(
        AgentApiKeyUnavailableResponseSchema.parse({
          code: "agent_api_keys_unavailable",
          message: "Agent API key storage is not configured."
        }),
        503
      );
    }
    if (
      agentNutritionReadStore === undefined ||
      agentCrossDomainReadStore === undefined
    ) {
      return context.json(
        AgentNutritionReadUnavailableResponseSchema.parse({
          code: "agent_nutrition_read_unavailable",
          message: "Agent cross-domain read storage is not configured."
        }),
        503
      );
    }

    const agentAuth = await authenticateAgentBearer({
      context,
      agentApiKeyStore,
      rateLimitBackend,
      logger
    });
    if (agentAuth.status === "unauthorized") {
      return context.json(
        AgentUnauthorizedResponseSchema.parse({
          code: "agent_unauthorized",
          message: "A valid agent API key is required."
        }),
        401
      );
    }
    if (agentAuth.status === "rate_limited") {
      return agentAuth.response;
    }
    const agent = agentAuth.agent;

    const query = context.req.valid("query");
    const range = validateCrossDomainRange(query.from, query.to);
    if (!range.ok) {
      return context.json(
        AgentNutritionReadInvalidRangeResponseSchema.parse({
          code: "agent_nutrition_read_invalid_range",
          message: range.message
        }),
        422
      );
    }

    const [nutritionDays, workouts] = await Promise.all([
      agentNutritionReadStore.readNutritionDays({
        userId: agent.userId,
        from: query.from,
        to: query.to
      }),
      agentCrossDomainReadStore.readWorkoutTimings({
        userId: agent.userId,
        from: query.from,
        to: query.to
      })
    ]);

    return context.json(
      AgentTrainingDayNutritionResponseSchema.parse(
        buildAgentTrainingDayNutritionResponse({
          from: query.from,
          to: query.to,
          nutritionDays,
          workouts,
          preWindowMinutes: query.preWindowMinutes,
          postWindowMinutes: query.postWindowMinutes
        })
      ),
      200
    );
  });

  app.openapi(syncPushRoute, async (context) => {
    if (syncStore === undefined) {
      return context.json(
        SyncUnavailableResponseSchema.parse({
          code: "sync_unavailable",
          message: "Sync storage is not configured."
        }),
        503
      );
    }

    const token = readBearerToken(context.req.header("authorization"));
    if (token === null) {
      return context.json(
        SyncUnauthorizedResponseSchema.parse({
          code: "sync_unauthorized",
          message: "A session bearer token is required."
        }),
        401
      );
    }

    const session = await syncStore.verifyBearerToken(token);
    if (session === null) {
      return context.json(
        SyncUnauthorizedResponseSchema.parse({
          code: "sync_unauthorized",
          message: await syncUnauthorizedMessage(syncStore, token)
        }),
        401
      );
    }
    setRequestUserId(context, session.userId);

    const requestBody = context.req.valid("json");
    let result: Awaited<ReturnType<SyncStore["pushLoggedSets"]>>;
    switch (requestBody.entity) {
      case EXERCISE_CATEGORIES_SYNC_ENTITY:
        result = await syncStore.pushExerciseCategories({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case EXERCISES_SYNC_ENTITY:
        result = await syncStore.pushExercises({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case LOGGED_SETS_SYNC_ENTITY:
        result = await syncStore.pushLoggedSets({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case FOODS_SYNC_ENTITY:
        result = await syncStore.pushFoods({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case MEAL_TYPES_SYNC_ENTITY:
        result = await syncStore.pushMealTypes({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case MEALS_SYNC_ENTITY:
        result = await syncStore.pushMeals({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case FOOD_ENTRIES_SYNC_ENTITY:
        result = await syncStore.pushFoodEntries({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case COMPOUNDS_SYNC_ENTITY:
        result = await syncStore.pushCompounds({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case DOSES_SYNC_ENTITY:
        result = await syncStore.pushDoses({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case PROTOCOLS_SYNC_ENTITY:
        result = await syncStore.pushProtocols({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case PROTOCOL_COMPOUNDS_SYNC_ENTITY:
        result = await syncStore.pushProtocolCompounds({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case SCHEDULES_SYNC_ENTITY:
        result = await syncStore.pushSchedules({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case PROTOCOL_TARGET_OUTCOMES_SYNC_ENTITY:
        result = await syncStore.pushProtocolTargetOutcomes({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case NUTRITION_GOALS_SYNC_ENTITY:
        result = await syncStore.pushNutritionGoals({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case USER_SETTINGS_SYNC_ENTITY:
        result = await syncStore.pushUserSettings({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case ROUTINES_SYNC_ENTITY:
        result = await syncStore.pushRoutines({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case WORKOUT_SESSIONS_SYNC_ENTITY:
        result = await syncStore.pushWorkoutSessions({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case WORKOUT_EXERCISES_SYNC_ENTITY:
        result = await syncStore.pushWorkoutExercises({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case EXERCISE_GROUPS_SYNC_ENTITY:
        result = await syncStore.pushExerciseGroups({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case EXERCISE_GROUP_MEMBERS_SYNC_ENTITY:
        result = await syncStore.pushExerciseGroupMembers({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case WORKOUT_TEMPLATES_SYNC_ENTITY:
        result = await syncStore.pushWorkoutTemplates({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case TEMPLATE_EXERCISES_SYNC_ENTITY:
        result = await syncStore.pushTemplateExercises({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case PRESCRIPTIONS_SYNC_ENTITY:
        result = await syncStore.pushPrescriptions({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case TEMPLATE_GROUPS_SYNC_ENTITY:
        result = await syncStore.pushTemplateGroups({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case TEMPLATE_GROUP_MEMBERS_SYNC_ENTITY:
        result = await syncStore.pushTemplateGroupMembers({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case ROUTINE_ENTRIES_SYNC_ENTITY:
        result = await syncStore.pushRoutineEntries({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      case TEMPLATE_LINKS_SYNC_ENTITY:
        result = await syncStore.pushTemplateLinks({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
      default:
        result = await syncStore.pushIntegrationDataClassConsents({
          userId: session.userId,
          correlationId: requestCorrelationId(context),
          deviceId: requestBody.deviceId,
          changes: requestBody.changes
        });
        break;
    }
    if (syncNudgePublisher !== undefined && result.applied.length > 0) {
      try {
        await syncNudgePublisher.enqueueSyncNudge({
          userId: session.userId,
          sourceDeviceId: requestBody.deviceId,
          reason: "sync_push"
        });
      } catch (error) {
        logger.error?.(
          {
            error,
            userId: session.userId,
            deviceId: requestBody.deviceId
          },
          "sync nudge enqueue failed"
        );
      }
    }

    return context.json(
      SyncPushResponseSchema.parse({
        protocolVersion: requestBody.protocolVersion,
        accepted: result.accepted,
        serverClock: result.serverClock,
        applied: result.applied
      }),
      200
    );
  });

  app.openapi(devicePushTokenRegistrationRoute, async (context) => {
    if (syncStore === undefined || devicePushTokenStore === undefined) {
      return context.json(
        SyncUnavailableResponseSchema.parse({
          code: "sync_unavailable",
          message: "Push-token storage is not configured."
        }),
        503
      );
    }

    const token = readBearerToken(context.req.header("authorization"));
    if (token === null) {
      return context.json(
        SyncUnauthorizedResponseSchema.parse({
          code: "sync_unauthorized",
          message: "A session bearer token is required."
        }),
        401
      );
    }

    const session = await syncStore.verifyBearerToken(token);
    if (session === null) {
      return context.json(
        SyncUnauthorizedResponseSchema.parse({
          code: "sync_unauthorized",
          message: await syncUnauthorizedMessage(syncStore, token)
        }),
        401
      );
    }
    setRequestUserId(context, session.userId);

    const requestBody = context.req.valid("json");
    await devicePushTokenStore.registerDevicePushToken({
      userId: session.userId,
      deviceId: requestBody.deviceId,
      platform: requestBody.platform,
      token: requestBody.token
    });

    return context.json(
      DevicePushTokenRegistrationResponseSchema.parse({
        registered: true
      }),
      200
    );
  });

  app.openapi(monitoringSeriesBlobRoute, async (context) => {
    if (syncStore === undefined || monitoringSeriesStore === undefined) {
      return context.json(
        MonitoringSeriesUnavailableResponseSchema.parse({
          code: "monitoring_series_unavailable",
          message: "Monitoring Series storage or session auth is not configured."
        }),
        503
      );
    }

    const token = readBearerToken(context.req.header("authorization"));
    if (token === null) {
      return context.json(
        MonitoringSeriesUnauthorizedResponseSchema.parse({
          code: "sync_unauthorized",
          message: "A session bearer token is required."
        }),
        401
      );
    }

    const session = await syncStore.verifyBearerToken(token);
    if (session === null) {
      return context.json(
        MonitoringSeriesUnauthorizedResponseSchema.parse({
          code: "sync_unauthorized",
          message: await syncUnauthorizedMessage(syncStore, token)
        }),
        401
      );
    }
    setRequestUserId(context, session.userId);

    const params = context.req.valid("param");
    const series = await monitoringSeriesStore.fetchMonitoringSeriesBlob({
      seriesId: params.seriesId,
      userId: session.userId
    });
    if (series === null) {
      return context.json(
        MonitoringSeriesNotFoundResponseSchema.parse({
          code: "monitoring_series_not_found",
          message: "No Monitoring Series blob exists for this account and id."
        }),
        404
      );
    }

    return context.json(MonitoringSeriesBlobResponseSchema.parse(series), 200);
  });

  app.openapi(workoutMonitoringRoute, async (context) => {
    if (syncStore === undefined || workoutMonitoringStore === undefined) {
      return context.json(
        WorkoutMonitoringUnavailableResponseSchema.parse({
          code: "workout_monitoring_unavailable",
          message: "Workout Monitoring storage or session auth is not configured."
        }),
        503
      );
    }

    const token = readBearerToken(context.req.header("authorization"));
    if (token === null) {
      return context.json(
        WorkoutMonitoringUnauthorizedResponseSchema.parse({
          code: "sync_unauthorized",
          message: "A session bearer token is required."
        }),
        401
      );
    }

    const session = await syncStore.verifyBearerToken(token);
    if (session === null) {
      return context.json(
        WorkoutMonitoringUnauthorizedResponseSchema.parse({
          code: "sync_unauthorized",
          message: await syncUnauthorizedMessage(syncStore, token)
        }),
        401
      );
    }
    setRequestUserId(context, session.userId);

    const params = context.req.valid("param");
    const monitoring = await workoutMonitoringStore.readWorkoutMonitoring({
      userId: session.userId,
      workoutId: params.workoutId
    });
    if (monitoring === null) {
      return context.json(
        WorkoutMonitoringNotFoundResponseSchema.parse({
          code: "workout_monitoring_not_found",
          message: "No live Workout or Activity Link exists for this account."
        }),
        404
      );
    }

    return context.json(
      WorkoutMonitoringResponseSchema.parse(monitoring),
      200
    );
  });

  app.openapi(syncPullRoute, async (context) => {
    if (syncStore === undefined) {
      return context.json(
        SyncUnavailableResponseSchema.parse({
          code: "sync_unavailable",
          message: "Sync storage is not configured."
        }),
        503
      );
    }

    const token = readBearerToken(context.req.header("authorization"));
    if (token === null) {
      return context.json(
        SyncUnauthorizedResponseSchema.parse({
          code: "sync_unauthorized",
          message: "A session bearer token is required."
        }),
        401
      );
    }

    const session = await syncStore.verifyBearerToken(token);
    if (session === null) {
      return context.json(
        SyncUnauthorizedResponseSchema.parse({
          code: "sync_unauthorized",
          message: await syncUnauthorizedMessage(syncStore, token)
        }),
        401
      );
    }
    setRequestUserId(context, session.userId);

    const requestBody = context.req.valid("json");
    const window = await syncStore.pullChanges({
      userId: session.userId,
      correlationId: requestCorrelationId(context),
      cursor: requestBody.cursor,
      limit: requestBody.limit,
      mode: requestBody.mode
    });

    return context.json(
      SyncPullResponseSchema.parse({
        protocolVersion: requestBody.protocolVersion,
        fullResyncRequired: window.fullResyncRequired,
        changes: window.changes,
        nextCursor: window.nextCursor,
        serverClock: window.serverClock
      }),
      200
    );
  });

  // The MCP server is served over Streamable HTTP at /mcp ('s MCP
  // transport section): stateless (a fresh transport per request, no session
  // id generator) with JSON responses enabled so plain JSON-RPC clients (curl,
  // code-mode agents) work without an SSE stream. Auth is transport-level, not
  // a tool argument: the same `Authorization: Bearer <agent key>` header REST
  // uses is read here and handed to the SDK as `authInfo`, which the MCP SDK
  // threads into every tool call's `extra.authInfo` — the exact field
  // `authenticateToolCall` already reads. This is intentionally not registered
  // as a Zod-OpenAPI route: MCP is JSON-RPC, not a REST resource, and has no
  // place in the OpenAPI contract or the agent operation list derived from it.
  app.all("/mcp", async (context) => {
    if (createMcpServer === undefined) {
      return context.json(
        {
          code: "agent_mcp_unavailable",
          message: "The agent MCP server is not configured."
        },
        503
      );
    }

    const token = readBearerToken(context.req.header("authorization"));
    context.set(
      "auth",
      token === null
        ? undefined
        : {
            token,
            clientId: "agent-bearer",
            scopes: []
          }
    );

    // A fresh McpServer + transport per request (stateless): the SDK
    // Protocol instance cannot be reconnected once closed, and a shared,
    // long-lived instance would leak request-scoped auth across callers.
    const server = createMcpServer();
    const transport = new StreamableHTTPTransport({
      sessionIdGenerator: undefined,
      enableJsonResponse: true
    });
    await server.connect(transport);
    try {
      return await transport.handleRequest(context);
    } finally {
      await server.close();
    }
  });

  return app;
}

function isEmailPasswordAuthPath(path: string, basePath: string) {
  const relativePath = path.slice(basePath.length);

  return [
    "/sign-up/email",
    "/sign-in/email",
    "/request-password-reset",
    "/reset-password",
    "/send-verification-email",
    "/verify-email"
  ].some(
    (emailPasswordPath) =>
      relativePath === emailPasswordPath ||
      relativePath.startsWith(`${emailPasswordPath}/`)
  );
}

function renderAuthVerifiedPage({
  status,
  detail
}: {
  status: "verified" | "failed";
  detail?: string;
}) {
  const isVerified = status === "verified";
  const title = isVerified ? "Email Verified" : "Verification Link Expired";
  const message = isVerified
    ? "You can return to Perennia and sign in."
    : "Perennia could not verify this email link. Return to the app and request a new verification email.";

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${escapeHtml(title)} - Perennia</title>
    <style>
      :root {
        color-scheme: dark light;
        --color-background-dark: #14181b;
        --color-surface-dark: #1e2428;
        --color-text-primary-dark: #ecf1f4;
        --color-text-secondary-dark: #9aa7ae;
        --color-primary: #1fb6cc;
        --color-destructive: #e5484d;
      }

      * {
        box-sizing: border-box;
      }

      body {
        margin: 0;
        min-width: 320px;
        min-height: 100svh;
        display: grid;
        place-items: center;
        padding: 24px;
        background: var(--color-background-dark);
        color: var(--color-text-primary-dark);
        font-family: Roboto, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }

      main {
        width: min(520px, 100%);
        padding: 24px;
        border: 1px solid rgba(154, 167, 174, 0.24);
        border-radius: 8px;
        background: var(--color-surface-dark);
      }

      .eyebrow {
        margin: 0 0 12px;
        color: ${isVerified ? "var(--color-primary)" : "var(--color-destructive)"};
        font-size: 13px;
        font-weight: 700;
        letter-spacing: 0.04em;
        text-transform: uppercase;
      }

      h1 {
        margin: 0;
        font-size: 22px;
        line-height: 1.25;
      }

      p {
        margin: 16px 0 0;
        color: var(--color-text-secondary-dark);
        font-size: 15px;
        line-height: 1.45;
      }

      code {
        font-family: ui-monospace, "SFMono-Regular", Consolas, monospace;
      }
    </style>
  </head>
  <body>
    <main>
      <p class="eyebrow">Perennia</p>
      <h1>${escapeHtml(title)}</h1>
      <p>${escapeHtml(message)}</p>
      ${detail === undefined ? "" : `<p><code>${escapeHtml(detail)}</code></p>`}
    </main>
  </body>
</html>`;
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

async function syncUnauthorizedMessage(syncStore: SyncStore, token: string) {
  return (
    (await syncStore.explainUnauthorizedBearerToken?.(token)) ??
    "The session bearer token is invalid or expired."
  );
}

async function verifySessionBearer(
  context: Context<AppEnv>,
  agentApiKeyStore: AgentApiKeyStore
) {
  const token = readBearerToken(context.req.header("authorization"));
  if (token === null) {
    return null;
  }

  const session = await agentApiKeyStore.verifySessionBearerToken(token);
  if (session !== null) {
    setRequestUserId(context, session.userId);
  }

  return session;
}

async function verifySyncSessionBearer(
  context: Context<AppEnv>,
  syncStore: SyncStore
) {
  const token = readBearerToken(context.req.header("authorization"));
  if (token === null) {
    return null;
  }

  const session = await syncStore.verifyBearerToken(token);
  if (session !== null) {
    setRequestUserId(context, session.userId);
  }

  return session;
}

async function verifyAgentBearer(
  context: Context<AppEnv>,
  agentApiKeyStore: AgentApiKeyStore,
  rateLimitBackend: RateLimitBackend | undefined,
  logger: RequestLogger
) {
  const token = readBearerToken(context.req.header("authorization"));
  if (token === null) {
    return { status: "unauthorized" as const };
  }

  return authenticateAgentOperation({
    secret: token,
    agentApiKeyStore,
    rateLimitBackend,
    logger
  });
}

type AgentBearerAuthResult =
  | {
      status: "authenticated";
      agent: AuthenticatedAgent;
    }
  | {
      status: "rate_limited";
      response: ReturnType<typeof rateLimitExceededResponse>;
    }
  | {
      status: "unauthorized";
    };

type IntegrationBearerAuthResult =
  | {
      status: "authenticated";
      credential: AuthenticatedIntegrationCredential;
    }
  | {
      status: "forbidden";
    }
  | {
      status: "rate_limited";
      response: ReturnType<typeof rateLimitExceededResponse>;
    }
  | {
      status: "unauthorized";
    };

async function handleAgentPlanVerbRequest<TAccepted>({
  acceptedSchema,
  context,
  agentApiKeyStore,
  rateLimitBackend,
  logger,
  run
}: {
  acceptedSchema: z.ZodType<TAccepted>;
  context: Context;
  agentApiKeyStore: AgentApiKeyStore | undefined;
  rateLimitBackend: RateLimitBackend | undefined;
  logger: RequestLogger;
  run: (agent: AuthenticatedAgent) => Promise<AgentPlanCaptureRunResult>;
}) {
  if (agentApiKeyStore === undefined) {
    return context.json(
      AgentApiKeyUnavailableResponseSchema.parse({
        code: "agent_api_keys_unavailable",
        message: "Agent API key storage is not configured."
      }),
      503
    );
  }
  const agentAuth = await authenticateAgentBearer({
    context,
    agentApiKeyStore,
    rateLimitBackend,
    logger
  });
  if (agentAuth.status === "unauthorized") {
    return context.json(
      AgentUnauthorizedResponseSchema.parse({
        code: "agent_unauthorized",
        message: "A valid agent API key is required."
      }),
      401
    );
  }
  if (agentAuth.status === "rate_limited") {
    return agentAuth.response;
  }

  const result = await run(agentAuth.agent);
  if (
    result.status === "catalog_unavailable" ||
    result.status === "unavailable"
  ) {
    return context.json(result.body, 503);
  }
  if (result.status === "not_found") {
    return context.json(result.body, 404);
  }
  if (result.status === "validation_failed") {
    return context.json(result.body, 422);
  }
  if (result.status === "conflict") {
    return context.json(result.body, 409);
  }
  return context.json(acceptedSchema.parse(result.body), 200);
}

async function authenticateAgentBearer({
  context,
  agentApiKeyStore,
  rateLimitBackend,
  logger
}: {
  context: Context;
  agentApiKeyStore: AgentApiKeyStore;
  rateLimitBackend: RateLimitBackend | undefined;
  logger: RequestLogger;
}): Promise<AgentBearerAuthResult> {
  const auth = await verifyAgentBearer(
    context,
    agentApiKeyStore,
    rateLimitBackend,
    logger
  );
  if (auth.status === "unauthorized") {
    return { status: "unauthorized" };
  }
  if (auth.status === "rate_limited") {
    return {
      status: "rate_limited",
      response: rateLimitExceededResponse(context, auth.decision)
    };
  }

  if (auth.rateLimitDecision !== undefined) {
    applyRateLimitHeaders(context, auth.rateLimitDecision);
  }

  setRequestUserId(context, auth.agent.userId);

  return { status: "authenticated", agent: auth.agent };
}

async function authenticateIntegrationCredentialBearer({
  context,
  integrationCredentialStore,
  rateLimitBackend,
  logger
}: {
  context: Context;
  integrationCredentialStore: IntegrationCredentialStore;
  rateLimitBackend: RateLimitBackend | undefined;
  logger: RequestLogger;
}): Promise<IntegrationBearerAuthResult> {
  const token = readBearerToken(context.req.header("authorization"));
  if (token === null) {
    return { status: "unauthorized" };
  }

  const auth = await authenticateIntegrationCredentialOperation({
    secret: token,
    operation: "write_observations",
    integrationCredentialStore,
    rateLimitBackend,
    logger
  });
  if (auth.status === "unauthorized") {
    return { status: "unauthorized" };
  }
  if (auth.status === "forbidden") {
    return { status: "forbidden" };
  }
  if (auth.status === "rate_limited") {
    return {
      status: "rate_limited",
      response: rateLimitExceededResponse(context, auth.decision)
    };
  }

  if (auth.rateLimitDecision !== undefined) {
    applyRateLimitHeaders(context, auth.rateLimitDecision);
  }

  setRequestUserId(context, auth.credential.userId);

  return { status: "authenticated", credential: auth.credential };
}

async function authenticateIntegrationStatusBearer({
  context,
  integrationCredentialStore
}: {
  context: Context;
  integrationCredentialStore: IntegrationCredentialStore;
}) {
  const token = readBearerToken(context.req.header("authorization"));
  if (token === null) {
    return null;
  }

  return integrationCredentialStore.authenticateIntegrationCredential(token);
}

type GarminFitImportBearerAuthResult =
  | {
      status: "authenticated";
      kind: "integration";
      credential: AuthenticatedIntegrationCredential;
      userId: string;
    }
  | {
      status: "authenticated";
      kind: "session";
      userId: string;
    }
  | {
      status: "forbidden";
    }
  | {
      status: "rate_limited";
      response: ReturnType<typeof rateLimitExceededResponse>;
    }
  | {
      status: "unauthorized";
    };

async function authenticateGarminFitImportBearer({
  context,
  integrationCredentialStore,
  syncStore,
  rateLimitBackend,
  logger
}: {
  context: Context<AppEnv>;
  integrationCredentialStore: IntegrationCredentialStore | undefined;
  syncStore: SyncStore | undefined;
  rateLimitBackend: RateLimitBackend | undefined;
  logger: RequestLogger;
}): Promise<GarminFitImportBearerAuthResult> {
  if (integrationCredentialStore !== undefined) {
    const integrationAuth = await authenticateIntegrationCredentialBearer({
      context,
      integrationCredentialStore,
      rateLimitBackend,
      logger
    });
    if (integrationAuth.status === "authenticated") {
      return {
        status: "authenticated",
        kind: "integration",
        credential: integrationAuth.credential,
        userId: integrationAuth.credential.userId
      };
    }
    if (integrationAuth.status === "forbidden") {
      return { status: "forbidden" };
    }
    if (integrationAuth.status === "rate_limited") {
      return integrationAuth;
    }
  }

  if (syncStore !== undefined) {
    const session = await verifySyncSessionBearer(context, syncStore);
    if (session !== null) {
      return {
        status: "authenticated",
        kind: "session",
        userId: session.userId
      };
    }
  }

  return { status: "unauthorized" };
}

type GarminFitPayloadParseResult =
  | {
      status: "ok";
      payload: GarminFitImportPayload;
    }
  | {
      status: "invalid";
      message: string;
    };

async function readGarminFitImportPayload(
  context: Context<AppEnv>
): Promise<GarminFitPayloadParseResult> {
  const query = readGarminFitImportQuery(context);
  if (query.status === "invalid") {
    return query;
  }

  const contentType = (
    context.req.header("content-type") ?? ""
  ).toLowerCase();
  if (contentType.startsWith("multipart/form-data")) {
    let formData: FormData;
    try {
      formData = await context.req.raw.formData();
    } catch {
      return {
        status: "invalid",
        message: "Multipart request body could not be parsed."
      };
    }

    const file = formData.get("file");
    if (!isFileLike(file)) {
      return {
        status: "invalid",
        message: "Multipart FIT import requires a file field named file."
      };
    }

    const bytes = new Uint8Array(await file.arrayBuffer());
    return validateGarminFitPayloadBytes({
      bytes,
      credentialId: formStringValue(formData.get("credentialId")) ??
        query.query.credentialId,
      idempotencyKey: formStringValue(formData.get("idempotencyKey")) ??
        query.query.idempotencyKey,
      timezone:
        formStringValue(formData.get("timezone")) ??
        query.query.timezone ??
        GARMIN_FIT_IMPORT_DEFAULT_TIMEZONE
    });
  }

  if (contentType.startsWith("application/json")) {
    let body: unknown;
    try {
      body = await context.req.json();
    } catch {
      return {
        status: "invalid",
        message: "JSON FIT import request body could not be parsed."
      };
    }

    const parsed = GarminFitImportJsonRequestSchema.safeParse(body);
    if (!parsed.success) {
      return {
        status: "invalid",
        message:
          "JSON FIT import requires fileBase64 and optional timezone/idempotencyKey."
      };
    }

    const bytes = decodeBase64Bytes(parsed.data.fileBase64);
    if (bytes === null) {
      return {
        status: "invalid",
        message: "fileBase64 must contain non-empty base64 FIT bytes."
      };
    }

    return validateGarminFitPayloadBytes({
      bytes,
      credentialId: parsed.data.credentialId ?? query.query.credentialId,
      idempotencyKey:
        parsed.data.idempotencyKey ?? query.query.idempotencyKey,
      timezone:
        parsed.data.timezone ??
        query.query.timezone ??
        GARMIN_FIT_IMPORT_DEFAULT_TIMEZONE
    });
  }

  if (
    contentType.startsWith("application/octet-stream") ||
    contentType === ""
  ) {
    const bytes = new Uint8Array(await context.req.arrayBuffer());
    return validateGarminFitPayloadBytes({
      bytes,
      credentialId: query.query.credentialId,
      idempotencyKey: query.query.idempotencyKey,
      timezone: query.query.timezone ?? GARMIN_FIT_IMPORT_DEFAULT_TIMEZONE
    });
  }

  return {
    status: "invalid",
    message:
      "FIT import requires multipart/form-data, application/json, or application/octet-stream."
  };
}

function readGarminFitImportQuery(
  context: Context<AppEnv>
):
  | { status: "ok"; query: z.infer<typeof GarminFitImportQuerySchema> }
  | { status: "invalid"; message: string } {
  const searchParams = new URL(context.req.url).searchParams;
  const candidate: Record<string, string> = {};
  for (const key of ["timezone", "idempotencyKey", "credentialId"]) {
    const value = searchParams.get(key);
    if (value !== null) {
      candidate[key] = value;
    }
  }

  const parsed = GarminFitImportQuerySchema.safeParse(candidate);
  if (!parsed.success) {
    return {
      status: "invalid",
      message:
        "FIT import query may include only valid timezone, idempotencyKey, and credentialId values."
    };
  }

  return { status: "ok", query: parsed.data };
}

function validateGarminFitPayloadBytes({
  bytes,
  credentialId,
  idempotencyKey,
  timezone
}: GarminFitImportPayload): GarminFitPayloadParseResult {
  if (bytes.byteLength === 0) {
    return {
      status: "invalid",
      message: "FIT import file is empty."
    };
  }
  if (bytes.byteLength > GARMIN_FIT_IMPORT_MAX_BYTES) {
    return {
      status: "invalid",
      message: "FIT import file is too large."
    };
  }

  return {
    status: "ok",
    payload: {
      bytes,
      credentialId,
      idempotencyKey,
      timezone
    }
  };
}

function isFileLike(value: unknown): value is { arrayBuffer(): Promise<ArrayBuffer> } {
  return (
    typeof value === "object" &&
    value !== null &&
    "arrayBuffer" in value &&
    typeof value.arrayBuffer === "function"
  );
}

function formStringValue(value: FormDataEntryValue | null) {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function decodeBase64Bytes(value: string) {
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return null;
  }

  const buffer = Buffer.from(trimmed, "base64");
  return buffer.byteLength === 0 ? null : new Uint8Array(buffer);
}

function requestCorrelationId(context: Context<AppEnv>) {
  return context.get("correlationId");
}

/**
 * Fire the post-write sync nudge for an agent batch, best-effort — a nudge
 * failure never fails the applied write (mirrors the meal/metric write paths).
 * Only nudges when at least one row was applied.
 */
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

/**
 * Resolve the goal targets a totals/trends read should score against:
 * explicit query-param targets always win per-nutrient; any goalable
 * Nutrient the query left unset falls back to the caller's stored Nutrition
 * Goal (fixes the root cause of every agent nutrition read needing
 * goal targets re-supplied on each call). Absent a configured
 * `agentNutritionGoalStore`, behaves exactly as before (query-only).
 */
async function resolvedNutritionGoals({
  userId,
  query,
  agentNutritionGoalStore
}: {
  userId: string;
  query: AgentNutritionTotalsQuery;
  agentNutritionGoalStore: AgentNutritionGoalBatchWriteStore | undefined;
}) {
  const queryGoals = goalTargetsFromQuery(query);
  if (agentNutritionGoalStore === undefined) {
    return {
      goals: queryGoals,
      goalSource: (queryGoals.size > 0 ? "query" : "none") as AgentNutritionGoalSource
    };
  }

  const storedGoalRows = await agentNutritionGoalStore.listNutritionGoals({
    userId
  });
  const storedGoals = new Map<NutrientId, { nutrient: NutrientId; value: number; unit: NutrientUnit }>();
  for (const goal of storedGoalRows) {
    storedGoals.set(goal.nutrient, {
      nutrient: goal.nutrient,
      value: goal.value,
      unit: nutrientUnitOrDefault(goal.unit, goal.nutrient)
    });
  }

  return resolveNutritionGoalTargets({ queryGoals, storedGoals });
}

function nutrientUnitOrDefault(
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

function setRequestUserId(context: Context<AppEnv>, userId: string) {
  context.set("userId", userId);
}
