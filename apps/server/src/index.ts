import { serve } from "@hono/node-server";
import pino from "pino";
import { pathToFileURL } from "node:url";

import {
  DEFAULT_SERVER_VERSION,
  createApp,
  type RequestLogger
} from "./app.js";
import {
  createPrivacyLogger,
  createSentryCrashReporterFromEnv,
  type CrashReporter
} from "./observability.js";
import { createDrizzleAgentApiKeyStore } from "./agent-api-keys.js";
import { createDrizzleActivityLinkMutationStore } from "./activity-links.js";
import { createAgentMcpServer } from "./agent-mcp.js";
import { createDrizzleAgentCatalogStore } from "./agent-catalog.js";
import { createDrizzleAgentReadStore } from "./agent-read-surface.js";
import { createDrizzleAgentNutritionReadStore } from "./agent-nutrition-reads.js";
import { createDrizzleAgentCrossDomainReadStore } from "./agent-cross-domain-reads.js";
import { createDrizzleAgentWorkoutBatchWriteStore } from "./agent-workout-batch-write.js";
import { createDrizzleAgentExerciseCatalogBatchWriteStore } from "./agent-exercise-catalog-batch-write.js";
import { createDrizzleAgentMealBatchWriteStore } from "./agent-meal-batch-write.js";
import {
  createDrizzleAgentFoodBatchWriteStore,
  createDrizzleAgentFoodCatalogStore
} from "./agent-foods.js";
import { createDrizzleAgentMetricStore } from "./agent-metrics.js";
import { createDrizzleAgentActivityStore } from "./agent-activity.js";
import { createDrizzleAgentProtocolsStore } from "./agent-protocols.js";
import { createDrizzleAgentNutritionGoalStore } from "./agent-nutrition-goals.js";
import { createDrizzleAgentSettingsStore } from "./agent-settings.js";
import { createDrizzleAgentPlanReadStore } from "./agent-plan-reads.js";
import { createDrizzleAgentPlanTreeBatchWriteStore } from "./agent-plan-tree-batch-write.js";
import { createDrizzleAgentPlanMaterializeStore } from "./agent-plan-materialize.js";
import { createDrizzleAgentPlanCaptureStore } from "./agent-plan-capture.js";
import { createDrizzleAccountDeletionStore } from "./account-deletion.js";
import { createDrizzleCanonicalImportStore } from "./canonical-import-endpoint.js";
import { createDrizzleIntegrationCredentialStore } from "./integration-credentials.js";
import { createDrizzleIntegrationStatusStore } from "./integration-status.js";
import { createGarminOAuthRuntimeFromEnv } from "./garmin-oauth.js";
import {
  createDrizzleGarminConnectorConsentStore,
  createGarminBackfillConfigFromEnv,
  createGarminWebhookConfigFromEnv
} from "./garmin-webhook.js";
import { createDrizzleImportedDataPurgeStore } from "./imported-data-purge.js";
import {
  createOAuthProvidersFromEnv,
  createEmailSenderFromEnv,
  createServerAuth,
  type AuthEmailSender
} from "./auth/index.js";
import type { BetterAuthPlugin, SocialProviders } from "better-auth";
import {
  applyMigrations,
  createDatabaseClient,
  createDrizzleReadinessProbe
} from "./db/index.js";
import type { DatabaseClient } from "./db/index.js";
import { createDrizzleDevicePushTokenStore } from "./device-push-tokens.js";
import { createPgBossJobQueue, type JobQueue } from "./jobs/index.js";
import {
  createDrizzleRateLimitBackend,
  type RateLimitBackend,
  type RateLimitPolicyInput
} from "./rate-limit.js";
import { createDrizzleSyncStore } from "./sync.js";
import {
  createJobQueueSyncNudgePublisher,
  SYNC_NUDGE_JOB_NAME,
  type SyncNudgePublisher
} from "./sync-nudge.js";
import { createDrizzleMonitoringSeriesStore } from "./monitoring-series.js";
import { createDrizzleWorkoutMonitoringStore } from "./workout-monitoring.js";

export {
  ACCOUNT_DELETION_GRACE_DAYS,
  ACCOUNT_DELETION_GRACE_MS,
  ACCOUNT_DELETION_PURGE_DEFAULT_BATCH_SIZE,
  ACCOUNT_DELETION_PURGE_JOB_NAME,
  ACCOUNT_DELETION_PURGE_SCHEDULE_CRON,
  ACCOUNT_DELETION_PURGE_SCHEDULE_KEY,
  createAccountDeletionPurgeWorker,
  createDrizzleAccountDeletionPurgeStore,
  type AccountDeletionPurgeInput,
  type AccountDeletionPurgeResult,
  type AccountDeletionPurgeStore,
  type AccountDeletionPurgeWorker
} from "./account-deletion-purge.js";
export {
  ACCOUNT_DELETION_LOCAL_ONLY_MESSAGE,
  AccountDeletionResponseSchema,
  AccountDeletionUnauthorizedResponseSchema,
  AccountDeletionUnavailableResponseSchema,
  accountDeletionRoute,
  createDrizzleAccountDeletionStore,
  type AccountDeletionResult,
  type AccountDeletionStore
} from "./account-deletion.js";
export {
  authenticateAgentOperation,
  type AgentAuthLogger,
  type AgentOperationAuthResult
} from "./agent-auth.js";
export {
  ACTIVITY_LINK_KIND_MATERIALIZED_SOURCE,
  ACTIVITY_LINK_KIND_SUGGESTED_TIME_OVERLAP,
  ACTIVITY_LINK_KIND_TIME_OVERLAP,
  ACTIVITY_LINK_USER_ACTION_ACTOR,
  ActivityLinkConflictResponseSchema,
  ActivityLinkCreateRequestSchema,
  ActivityLinkDeleteRequestSchema,
  ActivityLinkKindSchema,
  ActivityLinkMutationResponseSchema,
  ActivityLinkNotFoundResponseSchema,
  ActivityLinkSchema,
  ActivityLinkUnauthorizedResponseSchema,
  ActivityLinkUnavailableResponseSchema,
  activityLinkCreateRoute,
  activityLinkDeleteRoute,
  createDrizzleActivityLinkMutationStore,
  type ActivityLink,
  type ActivityLinkCreateRequest,
  type ActivityLinkDeleteRequest,
  type ActivityLinkMutationResponse,
  type ActivityLinkMutationResult,
  type ActivityLinkMutationStore
} from "./activity-links.js";
export {
  AGENT_MCP_SERVER_NAME,
  AgentMcpEnergyBalanceInputSchema,
  AgentMcpExerciseAnalyticsInputSchema,
  AgentMcpExerciseListInputSchema,
  AgentMcpExerciseResolveInputSchema,
  AgentMcpHistorySetsInputSchema,
  AgentMcpMealBatchWriteInputSchema,
  AgentMcpMetricBatchWriteInputSchema,
  AgentMcpMetricListInputSchema,
  AgentMcpMetricReadingsInputSchema,
  AgentMcpNutritionTotalsInputSchema,
  AgentMcpNutritionTrendsInputSchema,
  AgentMcpPlanCaptureInputSchema,
  AgentMcpPlanMaterializeInputSchema,
  AgentMcpPlanUpdateFromWorkoutInputSchema,
  AgentMcpRoutineDetailInputSchema,
  AgentMcpRoutineListInputSchema,
  AgentMcpTrainingDayNutritionInputSchema,
  AgentMcpValidateSetInputSchema,
  AgentMcpWorkoutTemplateDetailInputSchema,
  AgentMcpWorkoutTemplateListInputSchema,
  AgentMcpWorkoutBatchWriteInputSchema,
  AgentMcpWorkoutDetailInputSchema,
  AgentMcpWorkoutListInputSchema,
  createAgentMcpServer,
  type AgentMcpServerOptions
} from "./agent-mcp.js";
export {
  AGENT_API_KEY_CONFIG_ID,
  AGENT_API_KEY_PREFIX,
  AgentApiKeyCreateRequestSchema,
  AgentApiKeyCreateResponseSchema,
  AgentApiKeyListResponseSchema,
  AgentApiKeyMetadataSchema,
  AgentApiKeyNotFoundResponseSchema,
  AgentApiKeyProtectedProbeResponseSchema,
  AgentApiKeyRevokeResponseSchema,
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema,
  agentApiKeyCreateRoute,
  agentApiKeyListRoute,
  agentApiKeyRevokeRoute,
  agentProtectedProbeRoute,
  createDrizzleAgentApiKeyStore,
  type AgentApiKeyStore,
  type AgentSession,
  type AuthenticatedAgent
} from "./agent-api-keys.js";
export {
  DEFAULT_IMPORT_SCOPED_INTEGRATION_CREDENTIAL_SCOPE,
  DEFAULT_INTEGRATION_CREDENTIAL_SOURCE,
  DEFAULT_INTEGRATION_CREDENTIAL_RATE_LIMIT_MAX,
  DEFAULT_INTEGRATION_CREDENTIAL_RATE_LIMIT_WINDOW_MS,
  INTEGRATION_CREDENTIAL_ACTOR,
  INTEGRATION_CREDENTIAL_CONFIG_ID,
  INTEGRATION_CREDENTIAL_PREFIX,
  IMPORT_CREDENTIALS_ROUTE_PATH,
  IMPORT_CREDENTIAL_ROUTE_PATH,
  IMPORT_PROFILE_ROUTE_PATH,
  IntegrationCredentialCreateRequestSchema,
  IntegrationCredentialForbiddenResponseSchema,
  IntegrationCredentialIssueResponseSchema,
  IntegrationCredentialListResponseSchema,
  IntegrationCredentialMetadataSchema,
  IntegrationCredentialNotFoundResponseSchema,
  IntegrationCredentialOperationSchema,
  IntegrationCredentialRevokeResponseSchema,
  IntegrationCredentialScopeSchema,
  IntegrationCredentialSourceSchema,
  IntegrationCredentialUnauthorizedResponseSchema,
  IntegrationCredentialUnavailableResponseSchema,
  IntegrationImportDataClassAccessSchema,
  IntegrationImportProfileResponseSchema,
  authenticateIntegrationCredentialOperation,
  createDrizzleIntegrationCredentialStore,
  integrationCredentialCreateRoute,
  integrationCredentialListRoute,
  integrationCredentialRevokeRoute,
  integrationImportProfileRoute,
  isIntegrationCredentialOperationAllowed,
  type AuthenticatedIntegrationCredential,
  type IntegrationCredentialAuthLogger,
  type IntegrationCredentialIssueResponse,
  type IntegrationCredentialMetadata,
  type IntegrationCredentialOperation,
  type IntegrationCredentialOperationAuthResult,
  type IntegrationCredentialScope,
  type IntegrationCredentialStore,
  type IntegrationImportDataClassAccess,
  type IntegrationImportProfileResponse
} from "./integration-credentials.js";
export {
  INTEGRATION_STATUS_MANUAL_FIT_IMPORT_FALLBACK,
  INTEGRATION_STATUS_ROUTE_PATH,
  IntegrationStatusConditionSchema,
  IntegrationStatusFailureKindSchema,
  IntegrationStatusListResponseSchema,
  IntegrationStatusRecordSchema,
  IntegrationStatusRecoveryActionSchema,
  IntegrationStatusReportRequestSchema,
  IntegrationStatusReportResponseSchema,
  IntegrationStatusSourceSchema,
  IntegrationStatusTriggerSchema,
  IntegrationStatusUnauthorizedResponseSchema,
  IntegrationStatusUnavailableResponseSchema,
  createDrizzleIntegrationStatusStore,
  integrationStatusListRoute,
  integrationStatusReportRoute,
  type IntegrationStatusRecord,
  type IntegrationStatusReportRequest,
  type IntegrationStatusStore
} from "./integration-status.js";
export {
  AcquisitionAdapterExerciseMappingSchema,
  AcquisitionAdapterKindSchema,
  AcquisitionAdapterRegistrationSchema,
  GARMIN_OFFICIAL_ACQUISITION_ADAPTER,
  createAcquisitionAdapterRegistry,
  createDefaultAcquisitionAdapterRegistry,
  type AcquisitionAdapterExerciseMapping,
  type AcquisitionAdapterKind,
  type AcquisitionAdapterRegistration,
  type AcquisitionAdapterRegistry
} from "./acquisition-adapters.js";
export {
  GARMIN_OAUTH_CALLBACK_ROUTE_PATH,
  GARMIN_OAUTH_CREDENTIAL_NAME,
  GARMIN_OAUTH_DISCONNECT_ROUTE_PATH,
  GARMIN_OAUTH_SOURCE,
  GARMIN_OAUTH_START_ROUTE_PATH,
  GARMIN_OAUTH_STATE_TTL_SECONDS,
  GarminOAuthCallbackQuerySchema,
  GarminOAuthCallbackResponseSchema,
  GarminOAuthConnectionSchema,
  GarminOAuthDisconnectResponseSchema,
  GarminOAuthGrantExpiredError,
  GarminOAuthInvalidCallbackResponseSchema,
  GarminOAuthNotFoundResponseSchema,
  GarminOAuthStartResponseSchema,
  GarminOAuthUnauthorizedResponseSchema,
  GarminOAuthUnavailableResponseSchema,
  createDrizzleGarminOAuthConnectionStore,
  createGarminAuthorizationUrl,
  createGarminOAuthHttpClient,
  createGarminOAuthRuntimeFromEnv,
  createGarminOAuthTokenCipher,
  garminAccessTokenExpiresAt,
  garminOAuthCallbackRoute,
  garminOAuthDisconnectRoute,
  garminOAuthStartRoute,
  type GarminOAuthAccessTokenResult,
  type GarminOAuthCallbackResponse,
  type GarminOAuthClient,
  type GarminOAuthConfig,
  type GarminOAuthConnection,
  type GarminOAuthConnectionStore,
  type GarminOAuthConnectorConnection,
  type GarminOAuthDisconnectResponse,
  type GarminOAuthStartResponse,
  type GarminOAuthTokenCipher,
  type GarminOAuthTokenResult
} from "./garmin-oauth.js";
export {
  GARMIN_BACKFILL_DEFAULT_CHUNK_DAYS,
  GARMIN_BACKFILL_FULL_HISTORY_START,
  GARMIN_BACKFILL_JOB_NAME,
  GARMIN_BACKFILL_SINGLETON_SECONDS,
  GARMIN_CONSENT_DATA_CLASSES_ROUTE_PATH,
  GARMIN_HOSTED_DATA_CLASSES,
  GARMIN_PREMIUM_DATA_CLASSES,
  GARMIN_RECONCILIATION_DISPATCH_JOB_NAME,
  GARMIN_RECONCILIATION_JOB_NAME,
  GARMIN_RECONCILIATION_LOOKBACK_SECONDS,
  GARMIN_RECONCILIATION_SCHEDULE_CRON,
  GARMIN_RECONCILIATION_SCHEDULE_KEY,
  GARMIN_WEBHOOK_DEFAULT_TIMEZONE,
  GARMIN_WEBHOOK_JOB_NAME,
  GARMIN_WEBHOOK_RETRY_LIMIT,
  GARMIN_WEBHOOK_ROUTE_PATH,
  GARMIN_WEBHOOK_SECRET_HEADER,
  GARMIN_WEBHOOK_SINGLETON_SECONDS,
  GarminConsentDataClassAccessSchema,
  GarminConsentDataClassesResponseSchema,
  GarminConsentUnauthorizedResponseSchema,
  GarminConsentUnavailableResponseSchema,
  GarminWebhookAcceptedResponseSchema,
  GarminWebhookPingSchema,
  GarminWebhookUnauthorizedResponseSchema,
  GarminWebhookUnavailableResponseSchema,
  GarminRateLimitError,
  createDrizzleGarminConnectorConsentStore,
  createGarminBackfillConfigFromEnv,
  createGarminBackfillChunks,
  createGarminBackfillJobHandler,
  createGarminOfficialApiClientFromEnv,
  createGarminOfficialHttpClient,
  createGarminReconciliationDispatchHandler,
  createGarminReconciliationJobHandler,
  createGarminWebhookConfigFromEnv,
  createGarminWebhookJobHandler,
  createGarminWebhookWorker,
  enqueueGarminBackfill,
  enqueueGarminReconciliation,
  enqueueGarminWebhookPing,
  garminConsentDataClassesRoute,
  garminWebhookIdempotencyKey,
  garminWebhookRoute,
  listGarminConnectorConsentDataClassAccess,
  mapGarminOfficialActivityPayloadsToCanonicalImport,
  verifyGarminWebhookSecret,
  type GarminBackfillConfig,
  type GarminBackfillJobData,
  type GarminConnectorConsentDataClassAccess,
  type GarminConnectorConsentStore,
  type GarminConnectorImportJobHandler,
  type GarminEntitlementStore,
  type GarminConsentDataClassesResponse,
  type GarminImportWindowJobData,
  type GarminOfficialActivityClient,
  type GarminOfficialActivityPayload,
  type GarminReconciliationDispatchJobData,
  type GarminReconciliationJobData,
  type GarminWebhookAcceptedResponse,
  type GarminWebhookConfig,
  type GarminWebhookJobData,
  type GarminWebhookJobHandler,
  type GarminWebhookPing,
  type GarminWebhookWorker
} from "./garmin-webhook.js";
export {
  AGENT_EXERCISE_DEFAULT_CANDIDATE_LIMIT,
  AGENT_EXERCISE_DEFAULT_PAGE_LIMIT,
  AGENT_EXERCISE_MAX_CANDIDATE_LIMIT,
  AGENT_EXERCISE_MAX_PAGE_LIMIT,
  AgentCatalogUnavailableResponseSchema,
  AgentExerciseCategorySchema,
  AgentExerciseListFieldSchema,
  AgentExerciseListItemSchema,
  AgentExerciseListResponseSchema,
  AgentExerciseResolveGuidanceSchema,
  AgentExerciseResolveResponseSchema,
  AgentExerciseSchema,
  AgentExerciseListQuerySchema,
  AgentExerciseResolveQuerySchema,
  agentExerciseListRoute,
  agentExerciseResolveRoute,
  buildPlatformCatalogExercises,
  createDrizzleAgentCatalogStore,
  createInMemoryAgentCatalogStore,
  parseAgentExerciseListQuery,
  resolvePlatformExerciseId,
  toAgentCatalogExerciseFromPayload,
  type AgentCatalogExercise,
  type AgentCatalogStore,
  type AgentExercise,
  type AgentExerciseGetInput,
  type AgentExercisesGetInput,
  type AgentExerciseListField,
  type AgentExerciseListInput,
  type AgentExerciseListResponse,
  type AgentExerciseResolveInput,
  type AgentExerciseResolveResponse
} from "./agent-catalog.js";
export {
  AGENT_ANALYTICS_DEFAULT_POINT_LIMIT,
  AGENT_ANALYTICS_MAX_POINT_LIMIT,
  AGENT_HISTORY_DEFAULT_PAGE_LIMIT,
  AGENT_HISTORY_MAX_PAGE_LIMIT,
  AgentAnalyticsPointSchema,
  AgentAnalyticsRecordSchema,
  AgentDerivedSeriesSchema,
  AgentExerciseAnalyticsParamsSchema,
  AgentExerciseAnalyticsQuerySchema,
  AgentExerciseAnalyticsResponseSchema,
  AgentHistorySetCategorySchema,
  AgentHistorySetSchema,
  AgentHistorySetsQuerySchema,
  AgentHistorySetsResponseSchema,
  AgentMonitoringActivityNotFoundResponseSchema,
  AgentMonitoringActivityParamsSchema,
  AgentMonitoringActivityResponseSchema,
  AgentMonitoringExternalActivitySchema,
  AgentMonitoringHeartRateSummarySchema,
  AgentMonitoringHeartRateTrendSchema,
  AgentMonitoringHeartRateZoneSecondsSchema,
  AgentMonitoringRouteSummarySchema,
  AgentMonitoringSeriesSummarySchema,
  AgentMonitoringSummaryReadingSchema,
  AgentPeriodStatsSchema,
  AgentReadExerciseNotFoundResponseSchema,
  AgentReadUnavailableResponseSchema,
  AgentWorkoutDetailCoverageSchema,
  AgentWorkoutDetailNotFoundResponseSchema,
  AgentWorkoutDetailParamsSchema,
  AgentWorkoutDetailResponseSchema,
  AgentWorkoutDetailWorkoutSchema,
  AgentWorkoutExerciseCatalogEntrySchema,
  AgentWorkoutExerciseGroupMemberSchema,
  AgentWorkoutExerciseGroupSchema,
  AgentWorkoutExerciseSchema,
  AgentWorkoutTemplateLinkSchema,
  AgentRecordCatalogSchema,
  agentExerciseAnalyticsRoute,
  agentHistorySetsRoute,
  agentMonitoringActivityRoute,
  agentWorkoutDetailRoute,
  buildAgentExerciseAnalyticsResponse,
  createDrizzleAgentReadStore,
  type AgentExerciseAnalyticsQuery,
  type AgentHistoryPage,
  type AgentHistorySetsQuery,
  type AgentMonitoringActivityParams,
  type AgentMonitoringActivityResponse,
  type AgentReadStore,
  type AgentReadableLoggedSet,
  type AgentWorkoutDetailResponse
} from "./agent-read-surface.js";
export {
  AGENT_NUTRITION_MAX_RANGE_DAYS,
  AgentNutrientGoalProgressSchema,
  AgentNutrientTotalSchema,
  AgentNutritionDayTotalsSchema,
  AgentNutritionPeriodTotalsSchema,
  AgentNutritionReadInvalidRangeResponseSchema,
  AgentNutritionReadUnavailableResponseSchema,
  AgentNutritionTotalsQuerySchema,
  AgentNutritionTotalsResponseSchema,
  AgentNutritionTrendSchema,
  AgentNutritionTrendsQuerySchema,
  AgentNutritionTrendsResponseSchema,
  agentNutritionTotalsRoute,
  agentNutritionTrendsRoute,
  buildAgentNutritionTotalsResponse,
  buildAgentNutritionTrendsResponse,
  createDrizzleAgentNutritionReadStore,
  goalTargetsFromQuery,
  resolveNutritionGoalTargets,
  validateNutritionRange,
  type AgentNutritionGoalSource,
  type AgentNutritionReadStore,
  type AgentNutritionTotalsQuery,
  type AgentNutritionTotalsResponse,
  type AgentNutritionTrendsQuery,
  type AgentNutritionTrendsResponse
} from "./agent-nutrition-reads.js";
export {
  AGENT_CROSS_DOMAIN_MAX_RANGE_DAYS,
  AGENT_CROSS_DOMAIN_MAX_WORKOUT_POINTS,
  CALORIES_BURNED_METRIC_NAME,
  DEFAULT_FUELLING_WINDOW_MINUTES,
  MAX_FUELLING_WINDOW_MINUTES,
  AgentEnergyBalanceResponseSchema,
  AgentTrainingDayNutritionResponseSchema,
  agentEnergyBalanceRoute,
  agentTrainingDayNutritionRoute,
  buildAgentEnergyBalanceResponse,
  buildAgentTrainingDayNutritionResponse,
  createDrizzleAgentCrossDomainReadStore,
  mealTimingsFromNutritionDays,
  validateCrossDomainRange,
  type AgentCrossDomainReadStore,
  type AgentEnergyBalanceQuery,
  type AgentEnergyBalanceResponse,
  type AgentTrainingDayNutritionQuery,
  type AgentTrainingDayNutritionResponse
} from "./agent-cross-domain-reads.js";
export {
  computeEnergyBalance,
  computeProteinOnTrainingDays,
  computeWorkoutFuelling,
  deriveDailyEnergyBalance,
  summarizeEnergyBalance,
  utcDayKey,
  type CaloriesBurnedReading,
  type DailyEnergyBalance,
  type MealTiming,
  type WorkoutTiming
} from "./analytics/cross-domain-analytics.js";
export {
  buildNutritionTrend,
  dayTotals,
  deriveGoalProgress,
  enumerateNutritionDays,
  resolveEntryNutrient,
  totalsFromEntries,
  type AnalyticsFoodEntry,
  type AnalyticsMeal,
  type AnalyticsNutritionDay,
  type NutrientAmount,
  type NutrientGoalProgress,
  type NutrientGoalTarget,
  type NutrientId,
  type NutrientTotal
} from "./analytics/nutrition-analytics.js";
export {
  AGENT_WORKOUT_BATCH_WRITE_MAX_SETS,
  AgentWorkoutBatchWriteErrorResponseSchema,
  AgentWorkoutBatchWriteIssueSchema,
  AgentWorkoutBatchWriteRequestSchema,
  AgentWorkoutBatchWriteResponseSchema,
  AgentWorkoutBatchWriteSetResultSchema,
  AgentWorkoutBatchWriteSetSchema,
  AgentWorkoutBatchWriteUnavailableResponseSchema,
  AgentWorkoutBatchWriteWorkoutSchema,
  agentWorkoutBatchWriteRoute,
  createDrizzleAgentWorkoutBatchWriteStore,
  prepareAgentWorkoutBatchWrite,
  type AgentWorkoutBatchPreparation,
  type AgentWorkoutBatchPreparedSet,
  type AgentWorkoutBatchWriteIssue,
  type AgentWorkoutBatchWriteRequest,
  type AgentWorkoutBatchWriteStore
} from "./agent-workout-batch-write.js";
export {
  AGENT_EXERCISE_CATALOG_BATCH_WRITE_MAX_CATEGORIES,
  AGENT_EXERCISE_CATALOG_BATCH_WRITE_MAX_EXERCISES,
  AgentExerciseCatalogBatchWriteCategorySchema,
  AgentExerciseCatalogBatchWriteErrorResponseSchema,
  AgentExerciseCatalogBatchWriteExerciseSchema,
  AgentExerciseCatalogBatchWriteIssueSchema,
  AgentExerciseCatalogBatchWriteRequestSchema,
  AgentExerciseCatalogBatchWriteResponseSchema,
  AgentExerciseCatalogBatchWriteUnavailableResponseSchema,
  agentExerciseCatalogBatchWriteRoute,
  createDrizzleAgentExerciseCatalogBatchWriteStore,
  prepareAgentExerciseCatalogBatchWrite,
  type AgentExerciseCatalogBatchPreparation,
  type AgentExerciseCatalogBatchWriteIssue,
  type AgentExerciseCatalogBatchWriteRequest,
  type AgentExerciseCatalogBatchWriteResponse,
  type AgentExerciseCatalogBatchWriteStore
} from "./agent-exercise-catalog-batch-write.js";
export {
  AGENT_MEAL_BATCH_WRITE_MAX_ENTRIES,
  AgentMealBatchWriteEntryResultSchema,
  AgentMealBatchWriteEntrySchema,
  AgentMealBatchWriteErrorResponseSchema,
  AgentMealBatchWriteIssueSchema,
  AgentMealBatchWriteMealSchema,
  AgentMealBatchWriteRequestSchema,
  AgentMealBatchWriteResponseSchema,
  AgentMealBatchWriteUnavailableResponseSchema,
  agentMealBatchWriteRoute,
  createDrizzleAgentMealBatchWriteStore,
  prepareAgentMealBatchWrite,
  type AgentMealBatchPreparation,
  type AgentMealBatchPreparedRow,
  type AgentMealBatchWriteEntry,
  type AgentMealBatchWriteEntryResult,
  type AgentMealBatchWriteIssue,
  type AgentMealBatchWriteRequest,
  type AgentMealBatchWriteStore
} from "./agent-meal-batch-write.js";
export {
  AGENT_FOOD_BATCH_WRITE_MAX_FOODS,
  AGENT_FOOD_BATCH_WRITE_MAX_RECIPE_INGREDIENTS,
  AGENT_FOODS_DEFAULT_PAGE_LIMIT,
  AGENT_FOODS_DEFAULT_PLATFORM_SEARCH_LIMIT,
  AGENT_FOODS_ENTITY,
  AGENT_FOODS_MAX_PAGE_LIMIT,
  AGENT_FOODS_MAX_PLATFORM_SEARCH_LIMIT,
  AgentFoodBatchWriteErrorResponseSchema,
  AgentFoodBatchWriteFoodSchema,
  AgentFoodBatchWriteIssueSchema,
  AgentFoodBatchWriteRequestSchema,
  AgentFoodBatchWriteResponseSchema,
  AgentFoodBatchWriteResultSchema,
  AgentFoodListQuerySchema,
  AgentFoodListResponseSchema,
  AgentFoodNutrientVectorSchema,
  AgentFoodPlatformSearchQuerySchema,
  AgentFoodPlatformSearchResponseSchema,
  AgentFoodSchema,
  AgentFoodsUnavailableResponseSchema,
  AgentPlatformFoodAttributionSchema,
  AgentPlatformFoodSchema,
  agentFoodBatchWriteRoute,
  agentFoodListRoute,
  agentFoodPlatformSearchRoute,
  createDrizzleAgentFoodBatchWriteStore,
  createDrizzleAgentFoodCatalogStore,
  listFoodsFromRows,
  nutrientValidationLimitsForFoods,
  parseAgentFoodListQuery,
  prepareAgentFoodBatchWrite,
  searchAgentPlatformFoods,
  toAgentFood,
  type AgentFoodBatchPreparation,
  type AgentFoodBatchPreparedRow,
  type AgentFoodBatchWriteFood,
  type AgentFoodBatchWriteIssue,
  type AgentFoodBatchWriteRequest,
  type AgentFoodBatchWriteResult,
  type AgentFoodBatchWriteStore,
  type AgentFoodCatalogRow,
  type AgentFoodCatalogStore,
  type AgentFoodListField,
  type AgentFoodListQuery,
  type AgentFoodListResponse,
  type AgentFoodPlatformSearchQuery,
  type AgentFoodPlatformSearchResponse
} from "./agent-foods.js";
export {
  AGENT_NUTRITION_GOAL_BATCH_WRITE_MAX_TARGETS,
  AgentNutritionGoalBatchWriteErrorResponseSchema,
  AgentNutritionGoalBatchWriteIssueSchema,
  AgentNutritionGoalBatchWriteRequestSchema,
  AgentNutritionGoalBatchWriteResponseSchema,
  AgentNutritionGoalBatchWriteTargetResultSchema,
  AgentNutritionGoalBatchWriteTargetSchema,
  AgentNutritionGoalListResponseSchema,
  AgentNutritionGoalSchema,
  AgentNutritionGoalUnavailableResponseSchema,
  agentNutritionGoalBatchWriteRoute,
  agentNutritionGoalListRoute,
  createDrizzleAgentNutritionGoalStore,
  type AgentNutritionGoal,
  type AgentNutritionGoalBatchWriteIssue,
  type AgentNutritionGoalBatchWriteRequest,
  type AgentNutritionGoalBatchWriteResponse,
  type AgentNutritionGoalBatchWriteStore,
  type AgentNutritionGoalBatchWriteTarget,
  type AgentNutritionGoalListResponse,
  type AgentNutritionGoalReadStore
} from "./agent-nutrition-goals.js";
export {
  AGENT_SETTINGS_DEFAULTS,
  AgentSettingsBatchWriteErrorResponseSchema,
  AgentSettingsBatchWriteIssueSchema,
  AgentSettingsBatchWriteRequestSchema,
  AgentSettingsBatchWriteResponseSchema,
  AgentSettingsFieldsSchema,
  AgentSettingsReadResponseSchema,
  AgentSettingsUnavailableResponseSchema,
  agentSettingsBatchWriteRoute,
  agentSettingsReadRoute,
  agentUserSettingsRowId,
  buildSettingsPayload,
  createDrizzleAgentSettingsStore,
  USER_SETTINGS_AGENT_ENTITY,
  type AgentSettingsBatchWriteRequest,
  type AgentSettingsBatchWriteResponse,
  type AgentSettingsBatchWriteStore,
  type AgentSettingsFields,
  type AgentSettingsReadResponse,
  type AgentSettingsReadStore
} from "./agent-settings.js";
export {
  AGENT_PLAN_DEFAULT_COMPONENT_LIMIT,
  AGENT_PLAN_DEFAULT_PAGE_LIMIT,
  AGENT_PLAN_MAX_COMPONENT_LIMIT,
  AGENT_PLAN_MAX_PAGE_LIMIT,
  agentPlanInvalidCursorResponse,
  AgentPlanDetailQuerySchema,
  AgentPlanInvalidCursorError,
  AgentPlanInvalidCursorResponseSchema,
  AgentPlanNotFoundResponseSchema,
  AgentPlanPrescriptionSchema,
  AgentPlanReadUnavailableResponseSchema,
  AgentPlanRoutineEntrySchema,
  AgentPlanTemplateExerciseSchema,
  AgentPlanTemplateGroupMemberSchema,
  AgentPlanTemplateGroupSchema,
  AgentPlanUpNextCardSchema,
  AgentPlanUpNextSchema,
  AgentRoutineDetailQuerySchema,
  AgentRoutineDetailResponseSchema,
  AgentRoutineDetailSchema,
  AgentRoutineListQuerySchema,
  AgentRoutineListResponseSchema,
  AgentRoutineParamsSchema,
  AgentWorkoutTemplateDetailResponseSchema,
  AgentWorkoutTemplateDetailSchema,
  AgentWorkoutTemplateListQuerySchema,
  AgentWorkoutTemplateListResponseSchema,
  AgentWorkoutTemplateParamsSchema,
  agentRoutineDetailRoute,
  agentRoutineListRoute,
  agentWorkoutTemplateDetailRoute,
  agentWorkoutTemplateListRoute,
  createDrizzleAgentPlanReadStore,
  deriveAgentRoutineUpNext,
  type AgentPlanDetailQuery,
  type AgentPlanReadStore,
  type AgentPlanUpNext,
  type AgentRoutineDetailQuery,
  type AgentRoutineListQuery,
  type AgentUpNextRoutineEntry,
  type AgentUpNextTemplateLinkFact,
  type AgentWorkoutTemplateListQuery
} from "./agent-plan-reads.js";
export {
  AGENT_PLAN_TREE_BATCH_ENTITY,
  AGENT_PLAN_TREE_BATCH_WRITE_MAX_ITEMS,
  AGENT_PLAN_TREE_PRESCRIPTIONS_ENTITY,
  AGENT_PLAN_TREE_ROUTINE_ENTRIES_ENTITY,
  AGENT_PLAN_TREE_ROUTINES_ENTITY,
  AGENT_PLAN_TREE_TEMPLATE_EXERCISES_ENTITY,
  AGENT_PLAN_TREE_TEMPLATE_GROUP_MEMBERS_ENTITY,
  AGENT_PLAN_TREE_TEMPLATE_GROUPS_ENTITY,
  AGENT_PLAN_TREE_WORKOUT_TEMPLATES_ENTITY,
  AgentPlanTreeBatchWriteErrorResponseSchema,
  AgentPlanTreeBatchWriteIssueSchema,
  AgentPlanTreeBatchWriteItemResultSchema,
  AgentPlanTreeBatchWriteLimitsSchema,
  AgentPlanTreeBatchWritePrescriptionSchema,
  AgentPlanTreeBatchWriteRequestSchema,
  AgentPlanTreeBatchWriteResponseSchema,
  AgentPlanTreeBatchWriteRoutineEntrySchema,
  AgentPlanTreeBatchWriteRoutineSchema,
  AgentPlanTreeBatchWriteTemplateExerciseSchema,
  AgentPlanTreeBatchWriteTemplateGroupMemberSchema,
  AgentPlanTreeBatchWriteTemplateGroupSchema,
  AgentPlanTreeBatchWriteUnavailableResponseSchema,
  AgentPlanTreeBatchWriteWorkoutTemplateSchema,
  AgentPlanTreeEntityTypeSchema,
  agentPlanTreeBatchWriteRoute,
  createDrizzleAgentPlanTreeBatchWriteStore,
  planTreeBatchWriteLimitsResponse,
  planTreeBatchWriteDuplicateItems,
  planTreeBatchWriteResponseItems,
  prepareAgentPlanTreeBatchWrite,
  runAgentPlanTreeBatchWrite,
  type AgentPlanTreeBatchPreparation,
  type AgentPlanTreeBatchReferenceState,
  type AgentPlanTreeBatchWriteRunResult,
  type AgentPlanTreeBatchWriteIssue,
  type AgentPlanTreeBatchWriteRequest,
  type AgentPlanTreeBatchWriteResponse,
  type AgentPlanTreeBatchWriteStore,
  type AgentPlanTreeEntityType,
  type AgentPlanTreePreparedRow,
  type AgentPlanTreeReferenceRow
} from "./agent-plan-tree-batch-write.js";
export {
  AGENT_PLAN_MATERIALIZE_BATCH_ENTITY,
  AGENT_PLAN_MATERIALIZE_MAX_FUTURE_SKEW_MS,
  AGENT_PLAN_MATERIALIZE_MAX_SETS,
  AgentPlanMaterializeErrorResponseSchema,
  AgentPlanMaterializeIssueSchema,
  AgentPlanMaterializeLimitsSchema,
  AgentPlanMaterializeNotFoundResponseSchema,
  AgentPlanMaterializeRequestSchema,
  AgentPlanMaterializeResponseSchema,
  AgentPlanMaterializeUnavailableResponseSchema,
  agentPlanMaterializeLimitsResponse,
  agentPlanMaterializeRoute,
  createDrizzleAgentPlanMaterializeStore,
  createUuidV7,
  materializeAgentTemplateContent,
  prepareAgentPlanMaterialize,
  runAgentPlanMaterialize,
  runAgentPlanMaterializeForAgent,
  type AgentPlanMaterializeExerciseInput,
  type AgentPlanMaterializeGroupInput,
  type AgentPlanMaterializeHistory,
  type AgentPlanMaterializeIssue,
  type AgentPlanMaterializeOpaqueRow,
  type AgentPlanMaterializePreparedRow,
  type AgentPlanMaterializePrescriptionInput,
  type AgentPlanMaterializeReceipt,
  type AgentPlanMaterializeRequest,
  type AgentPlanMaterializeRunResult,
  type AgentPlanMaterializeSource,
  type AgentPlanMaterializeStore,
  type AgentPlanMaterializeValues,
  type AgentPlanMaterializedContent,
  type AgentPlanMaterializedSet
} from "./agent-plan-materialize.js";
export {
  AGENT_PLAN_CAPTURE_BATCH_ENTITY,
  AGENT_PLAN_CAPTURE_MAX_ROWS,
  AGENT_PLAN_UPDATE_BATCH_ENTITY,
  AgentPlanCaptureConflictError,
  AgentPlanCaptureConflictResponseSchema,
  AgentPlanCaptureErrorResponseSchema,
  AgentPlanCaptureIssueSchema,
  AgentPlanCaptureLimitsSchema,
  AgentPlanCaptureNotFoundResponseSchema,
  AgentPlanCaptureRequestSchema,
  AgentPlanCaptureResponseSchema,
  AgentPlanCaptureUnavailableResponseSchema,
  AgentPlanDivergenceSchema,
  AgentPlanUpdateFromWorkoutRequestSchema,
  AgentPlanUpdateFromWorkoutResponseSchema,
  agentPlanCaptureLimitsResponse,
  agentPlanCaptureRoute,
  agentPlanUpdateFromWorkoutRoute,
  captureAgentWorkout,
  compareAgentTemplateToWorkout,
  createDrizzleAgentPlanCaptureStore,
  runAgentPlanCapture,
  runAgentPlanCaptureForAgent,
  runAgentPlanUpdateFromWorkout,
  runAgentPlanUpdateFromWorkoutForAgent,
  suggestAgentCapturedWorkoutTemplateName,
  type AgentCapturedPrescription,
  type AgentCapturedTemplateContent,
  type AgentPlanCaptureIssue,
  type AgentPlanCaptureLinkedTemplateState,
  type AgentPlanCaptureOpaqueRow,
  type AgentPlanCaptureRequest,
  type AgentPlanCaptureRoutineState,
  type AgentPlanCaptureRunResult,
  type AgentPlanCaptureStore,
  type AgentPlanCaptureValues,
  type AgentPlanDivergence,
  type AgentPlanMutationEntityType,
  type AgentPlanMutationRow,
  type AgentPlanMutationRows,
  type AgentPlanSupersededRow,
  type AgentPlanUpdateFromWorkoutRequest,
  type AgentTemplateContentSnapshot,
  type AgentTemplateDivergenceComparison,
  type AgentWorkoutCaptureExerciseSnapshot,
  type AgentWorkoutCaptureGroupSnapshot,
  type AgentWorkoutCaptureSetSnapshot,
  type AgentWorkoutCaptureSnapshot
} from "./agent-plan-capture.js";
export {
  AGENT_METRIC_BATCH_WRITE_MAX_METRICS,
  AGENT_METRIC_BATCH_WRITE_MAX_READINGS,
  AGENT_METRIC_DEFAULT_PAGE_LIMIT,
  AGENT_METRIC_MAX_PAGE_LIMIT,
  AgentMetricBatchWriteErrorResponseSchema,
  AgentMetricBatchWriteIssueSchema,
  AgentMetricBatchWriteRequestSchema,
  AgentMetricBatchWriteResponseSchema,
  AgentMetricListQuerySchema,
  AgentMetricListResponseSchema,
  AgentMetricReadingsQuerySchema,
  AgentMetricReadingsResponseSchema,
  AgentMetricReadingSchema,
  AgentMetricSchema,
  AgentMetricUnavailableResponseSchema,
  METRICS_AGENT_ENTITY,
  agentMetricBatchWriteRoute,
  agentMetricListRoute,
  agentMetricReadingsRoute,
  createDrizzleAgentMetricStore,
  type AgentMetricBatchWriteIssue,
  type AgentMetricBatchWriteRequest,
  type AgentMetricBatchWriteResponse,
  type AgentMetricListQuery,
  type AgentMetricReadingsQuery,
  type AgentMetricStore
} from "./agent-metrics.js";
export {
  AGENT_ACTIVITY_DEFAULT_PAGE_LIMIT,
  AGENT_ACTIVITY_MAX_PAGE_LIMIT,
  AgentActivityBatchNotFoundResponseSchema,
  AgentActivityBatchSchema,
  AgentActivityEntrySchema,
  AgentActivityListQuerySchema,
  AgentActivityListResponseSchema,
  AgentActivityUnavailableResponseSchema,
  AgentActivityUndoBatchRequestSchema,
  AgentActivityUndoBatchResponseSchema,
  agentActivityListRoute,
  agentActivityUndoBatchRoute,
  createDrizzleAgentActivityStore,
  type AgentActivityListQuery,
  type AgentActivityListResponse,
  type AgentActivityStore,
  type AgentActivityUndoBatchResponse
} from "./agent-activity.js";
export {
  AgentCompoundBatchWriteResponseSchema,
  AgentCompoundListResponseSchema,
  AgentDoseBatchWriteErrorResponseSchema,
  AgentDoseBatchWriteResponseSchema,
  AgentDoseListResponseSchema,
  AgentEffectWindowResponseSchema,
  AgentProtocolBatchWriteResponseSchema,
  AgentProtocolListResponseSchema,
  AgentProtocolsBatchWriteErrorResponseSchema,
  agentCompoundBatchWriteRoute,
  agentCompoundListRoute,
  agentDoseBatchWriteRoute,
  agentDoseListRoute,
  agentEffectWindowRoute,
  agentProtocolBatchWriteRoute,
  agentProtocolListRoute,
  agentProtocolsBatchMarkerId,
  agentProtocolsWriteFailure,
  computeEffectWindowSegments,
  createDrizzleAgentProtocolsStore,
  prepareAgentCompoundBatchWrite,
  prepareAgentDoseBatchWrite,
  prepareAgentProtocolBatchWrite,
  type AgentProtocolsStore,
  type AgentProtocolsStoreWriteResult
} from "./agent-protocols.js";
export {
  AgentDoseValidationErrorResponseSchema,
  AgentDoseValidationIssueSchema,
  AgentDoseValidationLimitsSchema,
  AgentDoseValidationRequestSchema,
  AgentDoseValidationResponseSchema,
  AgentFoodEntryNutrientValidationRequestSchema,
  AgentNutrientAmountSchema,
  AgentNutrientValidationIssueSchema,
  AgentNutrientValidationLimitsSchema,
  AgentNutritionGoalTargetForValidationSchema,
  AgentNutritionGoalValidationRequestSchema,
  AgentRoutineCadenceValidationRequestSchema,
  AgentSettingsValidationIssueSchema,
  AgentSettingsValidationRequestSchema,
  AgentSetDimensionValueSchema,
  AgentSetValidationValuesSchema,
  AgentSetValidationErrorResponseSchema,
  AgentSetValidationIssueSchema,
  AgentSetValidationLimitsSchema,
  AgentSetValidationRequestSchema,
  AgentSetValidationResponseSchema,
  DOSE_ROUTES,
  DOSE_UNITS,
  DOSE_VALIDATION_LIMITS,
  NUTRIENT_VALIDATION_LIMITS,
  PLAN_VALIDATION_LIMITS,
  PRESCRIPTION_VALIDATION_LIMITS,
  PREDEFINED_SET_VALIDATION_LIMITS,
  SET_VALIDATION_LIMITS,
  SETTINGS_VALIDATION_LIMITS,
  ROUTINE_CADENCE_VALIDATION_LIMITS,
  TEMPLATE_GROUP_VALIDATION_LIMITS,
  agentDoseValidationRoute,
  agentSetValidationRoute,
  doseValidationLimitsResponse,
  nutrientValidationLimitsResponse,
  predefinedSetValidationLimitsResponse,
  setValidationLimitsResponse,
  validateAgentDose,
  validateAgentFoodEntry,
  validateAgentNutritionGoalTargets,
  validateAgentPrescription,
  validateAgentRoutineCadence,
  validateAgentPredefinedSet,
  validateAgentSet,
  validateAgentSettings,
  validateAgentTemplateGroup,
  type AgentDoseValidationInput,
  type AgentDoseValidationIssue,
  type AgentDoseValidationResult,
  type AgentFoodEntryNutrientValidationInput,
  type AgentNutrientValidationIssue,
  type AgentNutrientValidationResult,
  type AgentNutritionGoalValidationInput,
  type AgentPrescriptionValidationInput,
  type AgentPrescriptionValidationResult,
  type AgentRoutineCadenceValidationInput,
  type AgentRoutineCadenceValidationResult,
  type AgentSettingsValidationInput,
  type AgentSettingsValidationIssue,
  type AgentSettingsValidationResult,
  type AgentTemplateGroupValidationInput,
  type AgentTemplateGroupValidationResult,
  type AgentPredefinedSetValidationInput,
  type AgentPredefinedSetValidationResult,
  type AgentSetValidationInput,
  type AgentSetValidationIssue,
  type AgentSetValidationResult,
  type DoseRoute,
  type DoseUnit
} from "./agent-validation.js";
export {
  createApp,
  DEFAULT_SERVER_VERSION,
  AuthDisabledResponseSchema,
  HealthResponseSchema,
  ReadinessResponseSchema,
  ReadinessUnavailableResponseSchema
} from "./app.js";
export {
  CORRELATION_ID_HEADER,
  FILTERED_OBSERVABILITY_VALUE,
  createPrivacyLogger,
  createSentryCrashReporterFromEnv,
  resolveCorrelationId,
  safeRequestPath,
  scrubObservabilityData,
  type CrashReportContext,
  type CrashReporter,
  type StructuredLogger
} from "./observability.js";
export {
  ACTIVITY_LOG_RETENTION_DAYS,
  ACTIVITY_LOG_RETENTION_DEFAULT_BATCH_SIZE,
  ACTIVITY_LOG_RETENTION_JOB_NAME,
  ACTIVITY_LOG_RETENTION_MS,
  ACTIVITY_LOG_RETENTION_SCHEDULE_CRON,
  ACTIVITY_LOG_RETENTION_SCHEDULE_KEY,
  createActivityLogRetentionWorker,
  createDrizzleActivityLogRetentionStore,
  type ActivityLogRetentionResult,
  type ActivityLogRetentionStore,
  type ActivityLogRetentionWorker
} from "./activity-log-retention.js";
export {
  AUTH_BASE_PATH,
  AUTH_DISABLED_MESSAGE,
  createEmailSenderFromEnv,
  createOAuthProvidersFromEnv,
  createServerAuth,
  type AuthEmailMessage,
  type AuthEmailPurpose,
  type AuthEmailSender,
  type EmailDeliveryResolution,
  type ServerAuth
} from "./auth/index.js";
export {
  CanonicalActivitySchema,
  CanonicalActivitySummarySchema,
  CanonicalExternalIdSchema,
  CANONICAL_IMPORT_CONSENT_DATA_CLASSES,
  CanonicalImportConsentDataClassSchema,
  CanonicalImportDataClassSchema,
  CanonicalMetricReadingSchema,
  CanonicalMetricValueSchema,
  CanonicalScalarValueSchema,
  CanonicalSeriesAnchorSchema,
  CanonicalSeriesSampleSchema,
  CanonicalSeriesSchema,
  CanonicalSeriesTypeSchema,
  CanonicalSetSchema,
  CanonicalSourceSchema,
  CanonicalStructuredValueSchema,
  CanonicalSummaryMetricSchema,
  CanonicalTimeAnchorSchema,
  CanonicalTimezoneSchema,
  CanonicalTrainingDimensionsSchema,
  CanonicalUtcInstantSchema,
  registerCanonicalImportOpenApiSchemas,
  type CanonicalActivity,
  type CanonicalImportConsentDataClass,
  type CanonicalImportDataClass,
  type CanonicalMetricReading,
  type CanonicalSeries,
  type CanonicalSet
} from "./canonical-import.js";
export {
  CANONICAL_ACTIVITY_PLATFORM_CATEGORY_IDS,
  CANONICAL_ACTIVITY_PLATFORM_EXERCISES,
  CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS,
  normalizeCanonicalActivityExerciseMapping,
  parseNormalizedCanonicalActivity,
  resolveCanonicalActivityExerciseMapping,
  type CanonicalActivityExerciseMapping,
  type CanonicalActivityPlatformExercise,
  type CanonicalActivityPlatformExerciseId,
  type NormalizedCanonicalActivity
} from "./canonical-activity-mapping.js";
export {
  createCanonicalIngestionPipeline,
  type CanonicalActivityLink,
  type CanonicalActivityLinkSuggestion,
  type CanonicalActivityLinkingResult,
  type CanonicalActivityMaterializationResult,
  type CanonicalActivityMaterializationStore,
  type CanonicalActivityIngestionResult,
  type CanonicalActivityIngestionStatus,
  type CanonicalIngestionBatchInput,
  type CanonicalIngestionBatchResult,
  type CanonicalIngestionPipeline,
  type CanonicalIngestionReviewFlag,
  type CanonicalMaterializedWorkout,
  type CanonicalMaterializedWorkoutStatus
} from "./canonical-ingestion.js";
export {
  CANONICAL_IMPORT_ACTIVITY_LOG_ACTOR,
  CANONICAL_IMPORT_MAX_ACTIVITIES,
  CANONICAL_IMPORT_MAX_METRIC_READINGS,
  CANONICAL_IMPORT_MAX_SERIES,
  CANONICAL_IMPORT_ROUTE_PATH,
  ACTIVITY_LINK_CLOCK_SKEW_TOLERANCE_MS,
  ACTIVITY_LINK_OPEN_SESSION_WINDOW_MS,
  ACTIVITY_LINK_STRONG_OVERLAP_MIN_COVERAGE,
  ACTIVITY_LINKS_IMPORT_ENTITY,
  CANONICAL_IMPORT_BATCHES_ENTITY,
  LOGGED_SETS_IMPORT_ENTITY,
  CanonicalImportActivityLinkSchema,
  CanonicalImportActivityLinkSuggestionSchema,
  CanonicalImportActivityResultSchema,
  CanonicalImportForbiddenResponseSchema,
  CanonicalImportMaterializedWorkoutSchema,
  CanonicalImportMetricReadingResultSchema,
  CanonicalImportRequestSchema,
  CanonicalImportResponseSchema,
  CanonicalImportReviewFlagSchema,
  CanonicalImportUnauthorizedResponseSchema,
  CanonicalImportUnavailableResponseSchema,
  EXTERNAL_ACTIVITIES_IMPORT_ENTITY,
  METRIC_READINGS_IMPORT_ENTITY,
  MONITORING_SERIES_IMPORT_ENTITY,
  canonicalImportRoute,
  createDrizzleCanonicalImportStore,
  type CanonicalImportMetricReadingResult,
  type CanonicalImportRequest,
  type CanonicalImportResponse,
  type CanonicalImportStore,
  type CanonicalImportStoreResult
} from "./canonical-import-endpoint.js";
export {
  applyMigrations,
  createDatabaseClient,
  createDrizzleReadinessProbe,
  schema
} from "./db/index.js";
export {
  createDrizzleDevicePushTokenStore,
  devicePushTokenRegistrationRoute,
  DEVICE_PUSH_PLATFORM_ANDROID,
  DEVICE_PUSH_PLATFORM_IOS,
  DevicePushPlatformSchema,
  DevicePushTokenRegistrationRequestSchema,
  DevicePushTokenRegistrationResponseSchema,
  type DevicePushPlatform,
  type DevicePushTokenStore,
  type RegisteredDevicePushToken
} from "./device-push-tokens.js";
export {
  createDrizzleJobHeartbeatStore,
  createJobSpine,
  createPgBossJobQueue,
  createPgBossOptions,
  JOB_SPINE_CRON_HEARTBEAT,
  JOB_SPINE_CRON_SCHEDULE_KEY,
  JOB_SPINE_ENQUEUED_HEARTBEAT,
  JOB_SPINE_ENQUEUED_MARKER,
  JOB_SPINE_SCHEDULE_CRON,
  type JobHeartbeatStore,
  type JobQueue,
  type JobSpine
} from "./jobs/index.js";
export {
  createDrizzleSyncStore,
  EXERCISE_GROUP_MEMBERS_SYNC_ENTITY,
  EXERCISE_GROUPS_SYNC_ENTITY,
  FOOD_ENTRIES_SYNC_ENTITY,
  INTEGRATION_DATA_CLASS_CONSENTS_SYNC_ENTITY,
  LOGGED_SETS_SYNC_ENTITY,
  MEALS_SYNC_ENTITY,
  SYNC_PROTOCOL_VERSION,
  SyncPulledChangeSchema,
  SyncPullRequestSchema,
  SyncPullResponseSchema,
  SyncPushChangeSchema,
  SyncPushRequestSchema,
  SyncPushResponseSchema,
  SyncUnauthorizedResponseSchema,
  SyncUnavailableResponseSchema,
  syncPullRoute,
  WORKOUT_EXERCISES_SYNC_ENTITY,
  WORKOUT_SESSIONS_SYNC_ENTITY,
  type SyncPullWindow,
  type SyncStore
} from "./sync.js";
export {
  createJobQueueSyncNudgePublisher,
  createPushSenderFromEnv,
  createSyncNudgeWorker,
  SYNC_NUDGE_JOB_NAME,
  SYNC_NUDGE_MESSAGE_TYPE,
  SYNC_NUDGE_RETRY_LIMIT,
  type PushSender,
  type PushSendResult,
  type SyncNudgePublisher,
  type SyncNudgeWorker
} from "./sync-nudge.js";
export {
  createDrizzleSyncTombstoneGcStore,
  createSyncTombstoneGcWorker,
  SYNC_TOMBSTONE_GC_JOB_NAME,
  SYNC_TOMBSTONE_GC_SCHEDULE_CRON,
  SYNC_TOMBSTONE_GC_SCHEDULE_KEY,
  SYNC_TOMBSTONE_RETENTION_DAYS,
  SYNC_TOMBSTONE_RETENTION_MS,
  type SyncTombstoneGcResult,
  type SyncTombstoneGcStore,
  type SyncTombstoneGcWorker
} from "./sync-tombstone-gc.js";
export {
  ExerciseAnalyticsEngine,
  normalizedMetricValue,
  type AnalyticsPoint,
  type AnalyticsRecord,
  type AnalyticsSet,
  type DerivedSeries,
  type DimensionId,
  type ExerciseAnalyticsProfile,
  type ExerciseAnalyticsResult,
  type ExerciseLoadMode,
  type LoggedSetValues,
  type RecordCatalog,
  type RecordProfile,
  type SetDimensionValue,
  type TrainingUnit
} from "./analytics/exercise-analytics.js";
export {
  createDrizzleExternalActivityStore,
  type ExternalActivityStore,
  type StoredExternalActivity
} from "./external-activities.js";
export {
  IMPORTED_DATA_PURGE_ACTIVITY_LOG_ACTOR,
  IMPORTED_DATA_PURGE_DEVICE_ID,
  IMPORTED_DATA_PURGES_ENTITY,
  ImportedDataPurgeCountsSchema,
  ImportedDataPurgeRequestSchema,
  ImportedDataPurgeResponseSchema,
  ImportedDataPurgeScopeSchema,
  ImportedDataPurgeSourceSchema,
  ImportedDataPurgeUnauthorizedResponseSchema,
  ImportedDataPurgeUnavailableResponseSchema,
  createDrizzleImportedDataPurgeStore,
  importedDataPurgeRoute,
  type ImportedDataPurgeCounts,
  type ImportedDataPurgeScope,
  type ImportedDataPurgeSource,
  type ImportedDataPurgeStore
} from "./imported-data-purge.js";
export {
  GARMIN_FIT_IMPORT_DEFAULT_TIMEZONE,
  GARMIN_FIT_IMPORT_MAX_BYTES,
  GARMIN_FIT_IMPORT_ROUTE_PATH,
  GarminFitImportForbiddenResponseSchema,
  GarminFitImportInvalidResponseSchema,
  GarminFitImportJsonRequestSchema,
  GarminFitImportQuerySchema,
  GarminFitImportUnauthorizedResponseSchema,
  GarminFitImportUnavailableResponseSchema,
  garminFitImportIdempotencyKey,
  garminFitImportRoute,
  type GarminFitImportPayload
} from "./garmin-fit-import-endpoint.js";
export {
  parseGarminFitActivityFile,
  type GarminFitCanonicalImport
} from "./garmin-fit-import.js";
export {
  normalizeMetricReading,
  type MetricReadingNormalizationInput,
  type NormalizedMetricReading
} from "./metric-reading-normalization.js";
export { createOpenApiDocument } from "./openapi.js";
export {
  DEFAULT_RATE_LIMIT_ENFORCE,
  DEFAULT_RATE_LIMIT_LIMIT,
  DEFAULT_RATE_LIMIT_WINDOW_MS,
  createDrizzleRateLimitBackend,
  createRateLimitMiddleware,
  defaultRateLimitKey,
  type RateLimitBackend,
  type RateLimitDecision,
  type RateLimitPolicy,
  type RateLimitPolicyInput,
  type RateLimitRecordInput
} from "./rate-limit.js";
export {
  MONITORING_SERIES_BLOB_COMPRESSION,
  MONITORING_SERIES_BLOB_ENCODING,
  MONITORING_SERIES_ROUTE_PATH,
  MonitoringSeriesBlobResponseSchema,
  MonitoringSeriesNotFoundResponseSchema,
  MonitoringSeriesUnauthorizedResponseSchema,
  MonitoringSeriesUnavailableResponseSchema,
  createDrizzleMonitoringSeriesStore,
  decodeCanonicalSeriesBlob,
  encodeCanonicalSeriesBlob,
  monitoringSeriesBlobRoute,
  type EncodedMonitoringSeriesBlob,
  type MonitoringSeriesBlobResponse,
  type MonitoringSeriesStore
} from "./monitoring-series.js";
export {
  WORKOUT_MONITORING_ROUTE_PATH,
  WorkoutLinkedExternalActivitySchema,
  WorkoutMonitoringNotFoundResponseSchema,
  WorkoutMonitoringResponseSchema,
  WorkoutMonitoringSeriesMetadataSchema,
  WorkoutMonitoringSummaryReadingSchema,
  WorkoutMonitoringUnauthorizedResponseSchema,
  WorkoutMonitoringUnavailableResponseSchema,
  WorkoutSetHeartRateSchema,
  createDrizzleWorkoutMonitoringStore,
  workoutMonitoringRoute,
  type WorkoutMonitoringResponse,
  type WorkoutMonitoringStore
} from "./workout-monitoring.js";

function parsePort(value: string | undefined) {
  if (value === undefined) {
    return 3000;
  }

  const parsed = Number.parseInt(value, 10);
  if (Number.isNaN(parsed) || parsed < 1 || parsed > 65535) {
    throw new Error(`Invalid PORT: ${value}`);
  }

  return parsed;
}

function readRequiredEnv(name: string) {
  const value = process.env[name];
  if (value === undefined || value.length === 0) {
    throw new Error(`${name} is required.`);
  }

  return value;
}

export type MigratedServerAppOptions = {
  auth?:
    | false
    | {
        baseUrl?: string;
        emailDisabledReason?: string;
        emailSender?: AuthEmailSender | null;
        plugins?: BetterAuthPlugin[];
        secret?: string;
        socialProviders?: SocialProviders;
        trustedOrigins?: string[];
        trustedOAuthProviders?: string[];
      };
  crashReporter?: CrashReporter;
  databaseUrl: string;
  jobs?: JobQueue;
  logger: RequestLogger;
  rateLimit?:
    | false
    | {
        backend?: RateLimitBackend;
        policy?: RateLimitPolicyInput;
      };
  syncNudgePublisher?: SyncNudgePublisher;
  version?: string;
};

export type MigratedServerApp = {
  app: ReturnType<typeof createApp>;
  database: DatabaseClient;
  mcpServer: ReturnType<typeof createAgentMcpServer>;
};

export async function createMigratedServerApp({
  auth: authOptions,
  crashReporter,
  databaseUrl,
  jobs,
  logger,
  rateLimit,
  syncNudgePublisher,
  version = DEFAULT_SERVER_VERSION
}: MigratedServerAppOptions): Promise<MigratedServerApp> {
  const safeLogger = createPrivacyLogger(logger);
  await applyMigrations(databaseUrl);
  const database = createDatabaseClient(databaseUrl);
  const rateLimitBackend =
    rateLimit === false
      ? undefined
      : rateLimit?.backend ?? createDrizzleRateLimitBackend(database.db);
  const emailDelivery = createEmailSenderFromEnv(process.env);
  const auth =
    authOptions === false
      ? undefined
      : createServerAuth({
          db: database.db,
          logger: safeLogger,
          baseUrl: authOptions?.baseUrl ?? "http://localhost:3000",
          secret: authOptions?.secret ?? readAuthSecret(process.env),
          emailSender: authOptions?.emailSender ?? emailDelivery.sender,
          emailDisabledReason:
            authOptions?.emailDisabledReason ?? emailDelivery.reason,
          plugins: authOptions?.plugins,
          socialProviders:
            authOptions?.socialProviders ??
            createOAuthProvidersFromEnv(process.env, safeLogger),
          trustedOrigins: authOptions?.trustedOrigins,
          trustedOAuthProviders: authOptions?.trustedOAuthProviders
        });
  const agentApiKeyStore =
    auth === undefined
      ? undefined
      : createDrizzleAgentApiKeyStore(database.db, auth.apiKeyApi);
  const agentCatalogStore = createDrizzleAgentCatalogStore(database.db);
  const agentReadStore = createDrizzleAgentReadStore(database.db);
  const agentNutritionReadStore = createDrizzleAgentNutritionReadStore(
    database.db
  );
  const agentCrossDomainReadStore = createDrizzleAgentCrossDomainReadStore(
    database.db
  );
  const agentWorkoutBatchWriteStore = createDrizzleAgentWorkoutBatchWriteStore(
    database.db
  );
  const agentExerciseCatalogBatchWriteStore =
    createDrizzleAgentExerciseCatalogBatchWriteStore(database.db);
  const agentMealBatchWriteStore = createDrizzleAgentMealBatchWriteStore(
    database.db
  );
  const agentFoodCatalogStore = createDrizzleAgentFoodCatalogStore(database.db);
  const agentFoodBatchWriteStore = createDrizzleAgentFoodBatchWriteStore(
    database.db
  );
  const agentMetricStore = createDrizzleAgentMetricStore(database.db);
  const agentActivityStore = createDrizzleAgentActivityStore(database.db);
  const agentProtocolsStore = createDrizzleAgentProtocolsStore(database.db);
  const agentNutritionGoalStore = createDrizzleAgentNutritionGoalStore(
    database.db
  );
  const agentSettingsStore = createDrizzleAgentSettingsStore(database.db);
  const agentPlanReadStore = createDrizzleAgentPlanReadStore(database.db);
  const agentPlanTreeBatchWriteStore =
    createDrizzleAgentPlanTreeBatchWriteStore(database.db);
  const agentPlanMaterializeStore =
    createDrizzleAgentPlanMaterializeStore(database.db);
  const agentPlanCaptureStore =
    createDrizzleAgentPlanCaptureStore(database.db);
  const activityLinkMutationStore = createDrizzleActivityLinkMutationStore(
    database.db
  );
  const canonicalImportStore = createDrizzleCanonicalImportStore(database.db);
  const monitoringSeriesStore = createDrizzleMonitoringSeriesStore(database.db);
  const workoutMonitoringStore = createDrizzleWorkoutMonitoringStore(database.db);
  const integrationCredentialStore =
    createDrizzleIntegrationCredentialStore(database.db);
  const integrationStatusStore = createDrizzleIntegrationStatusStore(
    database.db
  );
  const garminOAuthRuntime = createGarminOAuthRuntimeFromEnv({
    db: database.db
  });
  const garminWebhookConfig = createGarminWebhookConfigFromEnv(process.env);
  const garminBackfillConfig = createGarminBackfillConfigFromEnv(process.env);
  const importedDataPurgeStore = createDrizzleImportedDataPurgeStore(
    database.db
  );
  // Shared construction args for every McpServer instance this process makes:
  // the long-lived one returned below (in-process transports, tests) and the
  // per-request ones /mcp's stateless HTTP mount builds via createMcpServer.
  // One args object keeps both from drifting apart.
  const agentMcpServerOptions = {
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
    logger: safeLogger,
    rateLimitBackend,
    syncNudgePublisher,
    version
  };
  const mcpServer = createAgentMcpServer(agentMcpServerOptions);
  const app = createApp({
    accountDeletionStore: createDrizzleAccountDeletionStore(database.db),
    agentApiKeyStore,
    agentActivityStore,
    agentCatalogStore,
    agentReadStore,
    agentNutritionReadStore,
    agentCrossDomainReadStore,
    agentWorkoutBatchWriteStore,
    agentExerciseCatalogBatchWriteStore,
    agentMealBatchWriteStore,
    agentFoodCatalogStore,
    agentFoodBatchWriteStore,
    agentMetricStore,
    agentProtocolsStore,
    agentNutritionGoalStore,
    agentSettingsStore,
    agentPlanReadStore,
    agentPlanTreeBatchWriteStore,
    agentPlanMaterializeStore,
    agentPlanCaptureStore,
    activityLinkMutationStore,
    auth,
    canonicalImportStore,
    createMcpServer: () => createAgentMcpServer(agentMcpServerOptions),
    crashReporter,
    garminOAuthClient: garminOAuthRuntime?.client,
    garminOAuthConfig: garminOAuthRuntime?.config,
    garminOAuthStore: garminOAuthRuntime?.store,
    garminBackfillConfig,
    garminConsentStore: createDrizzleGarminConnectorConsentStore(database.db),
    garminWebhookConfig: garminWebhookConfig ?? undefined,
    garminWebhookJobQueue: jobs,
    integrationCredentialStore,
    importedDataPurgeStore,
    integrationStatusStore,
    logger: safeLogger,
    monitoringSeriesStore,
    workoutMonitoringStore,
    readinessProbe: createDrizzleReadinessProbe(database.db),
    rateLimitBackend,
    rateLimitPolicy: rateLimit === false ? undefined : rateLimit?.policy,
    devicePushTokenStore: createDrizzleDevicePushTokenStore(database.db),
    syncStore: createDrizzleSyncStore(database.db),
    syncNudgePublisher,
    version
  });

  return { app, database, mcpServer };
}

export async function startServer() {
  const release = process.env.npm_package_version ?? DEFAULT_SERVER_VERSION;
  const logger = createPrivacyLogger(pino());
  const crashReporter = createSentryCrashReporterFromEnv(process.env, {
    release
  });
  const databaseUrl = readRequiredEnv("DATABASE_URL");
  const port = parsePort(process.env.PORT);
  const emailDelivery = createEmailSenderFromEnv(process.env);
  const jobs = createPgBossJobQueue({ databaseUrl, logger });
  const syncNudgePublisher = createJobQueueSyncNudgePublisher(jobs);
  const { app, database, mcpServer } = await createMigratedServerApp({
    auth: {
      baseUrl: readAuthBaseUrl(process.env, port),
      secret: readAuthSecret(process.env),
      emailSender: emailDelivery.sender,
      emailDisabledReason: emailDelivery.reason,
      trustedOrigins: readTrustedOrigins(process.env)
    },
    databaseUrl,
    jobs,
    logger,
    crashReporter,
    syncNudgePublisher,
    version: release
  });

  try {
    await jobs.start();
    await jobs.ensureQueue({ name: SYNC_NUDGE_JOB_NAME });
  } catch (error) {
    try {
      await jobs.stop();
    } catch (stopError) {
      logger.error?.({ error: stopError }, "job queue stop failed");
    }
    await database.close();
    throw error;
  }

  const server = serve(
    {
      fetch: app.fetch,
      port
    },
    () => {
      logger.info({ port }, "server listening");
    }
  );

  const close = async () => {
    server.close();
    await jobs.stop();
    await database.close();
  };

  process.once("SIGINT", () => {
    void close().finally(() => process.exit(0));
  });
  process.once("SIGTERM", () => {
    void close().finally(() => process.exit(0));
  });

  return { app, database, mcpServer, server };
}

function readAuthBaseUrl(env: NodeJS.ProcessEnv, port: number) {
  return (
    env.BETTER_AUTH_URL ??
    env.AUTH_BASE_URL ??
    env.PUBLIC_SERVER_URL ??
    `http://localhost:${port}`
  );
}

function readAuthSecret(env: NodeJS.ProcessEnv) {
  const secret = env.BETTER_AUTH_SECRET ?? env.AUTH_SECRET;
  if (secret !== undefined && secret.length > 0) {
    return secret;
  }

  if (env.NODE_ENV === "production") {
    throw new Error("BETTER_AUTH_SECRET or AUTH_SECRET is required.");
  }

  return "development-only-perennia-auth-secret";
}

function readTrustedOrigins(env: NodeJS.ProcessEnv) {
  const rawValue = env.BETTER_AUTH_TRUSTED_ORIGINS ?? env.AUTH_TRUSTED_ORIGINS;
  if (rawValue === undefined || rawValue.length === 0) {
    return undefined;
  }

  return rawValue
    .split(",")
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);
}

const isMainModule =
  process.argv[1] !== undefined &&
  import.meta.url === pathToFileURL(process.argv[1]).href;

if (isMainModule) {
  startServer().catch((error) => {
    const startupLogger = createPrivacyLogger(pino());
    const startupCrashReporter = createSentryCrashReporterFromEnv(process.env, {
      release: process.env.npm_package_version ?? DEFAULT_SERVER_VERSION
    });
    startupCrashReporter?.captureException(error, {
      correlationId: "server-startup",
      method: "STARTUP",
      path: "server-startup"
    });
    startupLogger.fatal?.({ error }, "server failed to start");
    process.exit(1);
  });
}
