// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated from packages/contract/openapi.json by packages/contract/scripts/generate-agent-client.ts.

export type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };

export type AgentClientFetch = (
  url: string,
  init: {
    method: string;
    headers: Record<string, string>;
    body?: string;
    signal?: unknown;
  }
) => Promise<{
  ok: boolean;
  status: number;
  text(): Promise<string>;
}>;

export type AgentClientOptions = {
  baseUrl: string | URL;
  bearerToken: string;
  fetch?: AgentClientFetch;
};

export type AgentClientRequestOptions = {
  signal?: unknown;
};

export type AgentActivityBatch = {
  "batchId": string;
  "actor": string;
  "occurredAt": string;
  "entries": Array<AgentActivityEntry>;
};

export type AgentActivityEntry = {
  "id": string;
  "entityTable": string;
  "entityId": string;
  "beforeImage": AgentActivityImage;
  "afterImage": AgentActivityImage;
  "occurredAt": string;
};

export type AgentActivityImage = Record<string, unknown> | null;

export type AgentActivityListResponse = {
  "batches": Array<AgentActivityBatch>;
  "limit": number;
  "nextCursor": string | null;
  "totalMatched": number;
};

export type AgentActivityUndoBatchRequest = {
  "batchId": string;
  "idempotencyKey": string;
};

export type AgentActivityUndoBatchResponse = {
  "accepted": true;
  "applied": boolean;
  "duplicate": boolean;
  "originalBatchId": string;
  "undoBatchId": string | null;
  "serverClock": string;
  "entries": Array<AgentActivityUndoEntryResult>;
};

export type AgentActivityUndoEntryResult = {
  "entryId": string;
  "entityTable": string;
  "entityId": string;
  "outcome": AgentActivityUndoOutcome;
};

export type AgentActivityUndoOutcome = "reverted" | "skipped_stale" | "skipped_missing" | "skipped_unsupported";

export type AgentAnalyticsPoint = {
  "setId": string;
  "achievedAt": string;
  "value": number;
  "unit": AgentReadTrainingUnit;
};

export type AgentAnalyticsRecord = {
  "profile": AgentReadRecordProfile;
  "setId": string;
  "achievedAt": string;
  "sequence": number;
  "value": number;
  "unit": AgentReadTrainingUnit;
  "reps"?: number;
};

export type AgentApiKeyCreateRequest = {
  "name": string;
};

export type AgentApiKeyCreateResponse = {
  "key": AgentApiKeyMetadata;
  "secret": string;
};

export type AgentApiKeyListResponse = {
  "keys": Array<AgentApiKeyMetadata>;
};

export type AgentApiKeyMetadata = {
  "id": string;
  "name": string;
  "prefix": string | null;
  "start": string | null;
  "createdAt": string;
  "lastUsedAt": string | null;
  "revoked": boolean;
};

export type AgentApiKeyProtectedProbeResponse = {
  "authenticated": true;
  "userId": string;
  "keyId": string;
  "keyName": string | null;
};

export type AgentApiKeyRevokeResponse = {
  "revoked": true;
};

export type AgentCompoundBatchWriteCompound = {
  "id": AgentProtocolsClientRowId & unknown;
  "name": string;
  "defaultUnit": "milligram" | "microgram" | "gram" | "internationalUnit" | "milliliter" | "tablet" | "capsule" | "drop" | "spray" | "puff" | "patch" | "unit";
  "defaultRoute": "oral" | "sublingual" | "subcutaneous" | "intramuscular" | "transdermal" | "intranasal" | "inhaled" | "topical" | "other";
  "strength"?: AgentCompoundStrengthInput;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentCompoundBatchWriteRequest = {
  "idempotencyKey": string;
  "compounds": Array<AgentCompoundBatchWriteCompound>;
};

export type AgentCompoundBatchWriteResponse = {
  "accepted": true;
  "duplicate": boolean;
  "idempotencyKey": string;
  "batchId": string;
  "serverClock": string;
  "compounds": Array<AgentProtocolsEntityBatchWriteResult>;
};

export type AgentCompoundField = "id" | "name" | "defaultUnit" | "defaultRoute" | "strength" | "updatedAt" | "deletedAt";

export type AgentCompoundListItem = {
  "id": string;
  "name": string;
  "defaultUnit"?: "milligram" | "microgram" | "gram" | "internationalUnit" | "milliliter" | "tablet" | "capsule" | "drop" | "spray" | "puff" | "patch" | "unit";
  "defaultRoute"?: "oral" | "sublingual" | "subcutaneous" | "intramuscular" | "transdermal" | "intranasal" | "inhaled" | "topical" | "other";
  "strength"?: AgentCompoundStrength;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentCompoundListResponse = {
  "compounds": Array<AgentCompoundListItem>;
  "fields": Array<AgentCompoundField>;
  "limit": number;
  "nextCursor": string | null;
  "totalMatched": number;
};

export type AgentCompoundStrength = {
  "value": number;
  "massUnit": string;
  "perUnit": string;
} | null;

export type AgentCompoundStrengthInput = {
  "value": number;
  "massUnit": string;
  "perUnit": string;
} | null;

export type AgentDailyEnergyBalance = {
  "localDate": string;
  "status": "computed" | "indeterminate";
  "energyIn": number | null;
  "energyOut": number | null;
  "net": number | null;
};

export type AgentDerivedSeries = {
  "isDefined": boolean;
  "points": Array<AgentAnalyticsPoint>;
  "total": number | null;
};

export type AgentDoseBatchWriteDose = {
  "id": AgentProtocolsClientRowId;
  "compoundId"?: string | null;
  "compoundName": string;
  "compoundStrength"?: AgentCompoundStrengthInput;
  "amount": string | number;
  "unit": "milligram" | "microgram" | "gram" | "internationalUnit" | "milliliter" | "tablet" | "capsule" | "drop" | "spray" | "puff" | "patch" | "unit";
  "route": "oral" | "sublingual" | "subcutaneous" | "intramuscular" | "transdermal" | "intranasal" | "inhaled" | "topical" | "other";
  "tookAt": string;
  "timezone": string;
  "localDate": string;
  "protocolId"?: string | null;
  "protocolName"?: string | null;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentDoseBatchWriteRequest = {
  "idempotencyKey": string;
  "doses": Array<AgentDoseBatchWriteDose>;
};

export type AgentDoseBatchWriteResponse = {
  "accepted": true;
  "duplicate": boolean;
  "idempotencyKey": string;
  "batchId": string;
  "serverClock": string;
  "doses": Array<AgentDoseBatchWriteResult>;
};

export type AgentDoseBatchWriteResult = {
  "id": string;
  "compoundName": string;
  "outcome": "applied" | "superseded" | "duplicate" | "refused";
  "warnings": Array<AgentDoseValidationIssue>;
};

export type AgentDoseField = "id" | "compoundId" | "compoundName" | "compoundStrength" | "amountValue" | "amountEntered" | "unit" | "route" | "tookAt" | "timezone" | "localDate" | "provenance" | "protocolId" | "protocolName" | "updatedAt" | "deletedAt";

export type AgentDoseListItem = {
  "id": string;
  "compoundId"?: string | null;
  "compoundName"?: string;
  "compoundStrength"?: AgentCompoundStrength;
  "amountValue"?: number;
  "amountEntered"?: string;
  "unit"?: "milligram" | "microgram" | "gram" | "internationalUnit" | "milliliter" | "tablet" | "capsule" | "drop" | "spray" | "puff" | "patch" | "unit";
  "route"?: "oral" | "sublingual" | "subcutaneous" | "intramuscular" | "transdermal" | "intranasal" | "inhaled" | "topical" | "other";
  "tookAt"?: string;
  "timezone"?: string;
  "localDate"?: string;
  "provenance"?: string;
  "protocolId"?: string | null;
  "protocolName"?: string | null;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentDoseListResponse = {
  "doses": Array<AgentDoseListItem>;
  "fields": Array<AgentDoseField>;
  "limit": number;
  "nextCursor": string | null;
  "totalMatched": number;
};

export type AgentDoseValidationIssue = {
  "field": string;
  "rule": string;
  "message": string;
  "limit": number | string | unknown | null;
};

export type AgentDoseValidationLimits = {
  "amountMin": 0;
  "units": {
  "milligram": {
  "warnAbove": number;
  "maxPerDose": number;
};
  "microgram": {
  "warnAbove": number;
  "maxPerDose": number;
};
  "gram": {
  "warnAbove": number;
  "maxPerDose": number;
};
  "internationalUnit": {
  "warnAbove": number;
  "maxPerDose": number;
};
  "milliliter": {
  "warnAbove": number;
  "maxPerDose": number;
};
  "tablet": {
  "warnAbove": number;
  "maxPerDose": number;
};
  "capsule": {
  "warnAbove": number;
  "maxPerDose": number;
};
  "drop": {
  "warnAbove": number;
  "maxPerDose": number;
};
  "spray": {
  "warnAbove": number;
  "maxPerDose": number;
};
  "puff": {
  "warnAbove": number;
  "maxPerDose": number;
};
  "patch": {
  "warnAbove": number;
  "maxPerDose": number;
};
  "unit": {
  "warnAbove": number;
  "maxPerDose": number;
};
};
};

export type AgentDoseValidationRequest = {
  "amount": string | number;
  "unit": "milligram" | "microgram" | "gram" | "internationalUnit" | "milliliter" | "tablet" | "capsule" | "drop" | "spray" | "puff" | "patch" | "unit";
  "route": "oral" | "sublingual" | "subcutaneous" | "intramuscular" | "transdermal" | "intranasal" | "inhaled" | "topical" | "other";
};

export type AgentDoseValidationResponse = {
  "accepted": true;
  "warnings": Array<AgentDoseValidationIssue>;
  "limits": AgentDoseValidationLimits;
};

export type AgentEffectAggregate = {
  "count": number;
  "min": number | null;
  "max": number | null;
  "mean": number | null;
};

export type AgentEffectDoseMarker = {
  "doseId": string;
  "compoundName": string;
  "amountValue": number;
  "unit": "milligram" | "microgram" | "gram" | "internationalUnit" | "milliliter" | "tablet" | "capsule" | "drop" | "spray" | "puff" | "patch" | "unit";
  "route": "oral" | "sublingual" | "subcutaneous" | "intramuscular" | "transdermal" | "intranasal" | "inhaled" | "topical" | "other";
  "tookAt": string;
};

export type AgentEffectWindowMetric = {
  "id": string;
  "name": string;
  "unit": string;
};

export type AgentEffectWindowResponse = {
  "source": AgentEffectWindowSource;
  "metric": AgentEffectWindowMetric;
  "range": {
  "from": string;
  "to": string;
};
  "window": AgentEffectWindowSpan;
  "doses": Array<AgentEffectDoseMarker>;
  "segments": AgentEffectWindowSegments;
  "descriptiveOnly": true;
};

export type AgentEffectWindowSegments = {
  "before": AgentEffectAggregate;
  "during": AgentEffectAggregate;
  "after": AgentEffectAggregate;
};

export type AgentEffectWindowSource = {
  "kind": "compound" | "protocol";
  "id": string;
};

export type AgentEffectWindowSpan = {
  "duringStart": string | null;
  "duringEnd": string | null;
};

export type AgentEnergyBalanceResponse = {
  "from": string;
  "to": string;
  "dayCount": number;
  "unit": "kilocalorie";
  "caloriesBurnedMetricName": string;
  "summary": AgentEnergyBalanceSummary;
  "days": Array<AgentDailyEnergyBalance>;
};

export type AgentEnergyBalanceSummary = {
  "computedDayCount": number;
  "indeterminateDayCount": number;
  "averageEnergyIn": number | null;
  "averageEnergyOut": number | null;
  "averageNet": number | null;
  "cumulativeNet": number | null;
};

export type AgentExercise = {
  "id": string;
  "library": AgentExerciseLibrary;
  "name": string;
  "category": AgentExerciseCategory;
  "dimensions": Array<AgentExerciseDimensionId>;
  "equipment": Array<string>;
  "loadMode": AgentExerciseLoadMode;
  "recordProfile": AgentExerciseRecordProfile;
  "favorite": boolean;
  "active": boolean;
  "shadowedPlatformExerciseId": string | null;
};

export type AgentExerciseAnalyticsResponse = {
  "exercise": AgentExercise;
  "profile": AgentReadExerciseAnalyticsProfile;
  "totalSetCount": number;
  "seriesPointLimit": number;
  "headlineRecord": NullableAgentAnalyticsRecord;
  "headlineRecords": Array<AgentAnalyticsRecord>;
  "recordCatalog": AgentRecordCatalog;
  "estimatedOneRepMax": AgentDerivedSeries;
  "volume": AgentDerivedSeries;
  "maxLoadSeries": AgentDerivedSeries;
  "repMaxSeries": Array<AgentAnalyticsRecord>;
  "periodStats": AgentPeriodStats;
};

export type AgentExerciseCatalogBatchWriteCategory = {
  "id": string;
  "name": string;
  "sortOrder"?: number;
  "colorHex"?: string;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentExerciseCatalogBatchWriteCategoryResult = {
  "id": string;
  "name": string;
  "applied": boolean;
  "outcome": "applied" | "superseded" | "duplicate";
};

export type AgentExerciseCatalogBatchWriteExercise = {
  "id": string;
  "name": string;
  "categoryId"?: string | null;
  "dimensions"?: Array<AgentExerciseCatalogDimensionId>;
  "defaultLoadUnit"?: string;
  "loadMode"?: AgentExerciseCatalogLoadMode;
  "recordProfile"?: AgentExerciseCatalogRecordProfile;
  "isUnilateral"?: boolean;
  "usesRpe"?: boolean;
  "isFavorite"?: boolean;
  "equipment"?: Array<string>;
  "notes"?: string | null;
  "customizesExerciseId"?: string | null;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentExerciseCatalogBatchWriteExerciseResult = {
  "id": string;
  "name": string;
  "library": "user";
  "applied": boolean;
  "outcome": "applied" | "superseded" | "duplicate";
};

export type AgentExerciseCatalogBatchWriteRequest = {
  "idempotencyKey": string;
  "categories"?: Array<AgentExerciseCatalogBatchWriteCategory>;
  "exercises"?: Array<AgentExerciseCatalogBatchWriteExercise>;
};

export type AgentExerciseCatalogBatchWriteResponse = {
  "accepted": true;
  "duplicate": boolean;
  "idempotencyKey": string;
  "batchId": string;
  "serverClock": string;
  "categories": Array<AgentExerciseCatalogBatchWriteCategoryResult>;
  "exercises": Array<AgentExerciseCatalogBatchWriteExerciseResult>;
};

export type AgentExerciseCatalogDimensionId = "load" | "reps" | "duration" | "distance";

export type AgentExerciseCatalogLoadMode = "added" | "assisted";

export type AgentExerciseCatalogRecordProfile = "repMax" | "maxLoad" | "maxReps" | "maxDuration" | "minDuration" | "maxDistance" | "fastestPace" | "minAssistancePerRepCount" | "completionStreak";

export type AgentExerciseCategory = {
  "id": string;
  "name": string;
};

export type AgentExerciseDimensionId = "load" | "reps" | "duration" | "distance";

export type AgentExerciseLibrary = "user" | "platform";

export type AgentExerciseListField = "id" | "name" | "library" | "category" | "dimensions" | "equipment" | "loadMode" | "recordProfile" | "favorite" | "active" | "shadowedPlatformExerciseId";

export type AgentExerciseListItem = {
  "id": string;
  "name": string;
  "library"?: AgentExerciseLibrary;
  "category"?: AgentExerciseCategory;
  "dimensions"?: Array<AgentExerciseDimensionId>;
  "equipment"?: Array<string>;
  "loadMode"?: AgentExerciseLoadMode;
  "recordProfile"?: AgentExerciseRecordProfile;
  "favorite"?: boolean;
  "active"?: boolean;
  "shadowedPlatformExerciseId"?: string | null;
};

export type AgentExerciseListResponse = {
  "exercises": Array<AgentExerciseListItem>;
  "limit": number;
  "nextCursor": string | null;
  "fields": Array<AgentExerciseListField>;
};

export type AgentExerciseLoadMode = "added" | "assisted";

export type AgentExerciseRecordProfile = "repMax" | "maxLoad" | "maxReps" | "maxDuration" | "minDuration" | "maxDistance" | "fastestPace" | "minAssistancePerRepCount" | "completionStreak";

export type AgentExerciseResolution = "matched" | "ambiguous" | "not_found";

export type AgentExerciseResolveGuidance = {
  "op": "POST /agent/exercises/batch-write";
  "message": string;
};

export type AgentExerciseResolveResponse = {
  "query": string;
  "resolution": AgentExerciseResolution;
  "matchedExercise": NullableAgentExercise;
  "candidates": Array<AgentExercise>;
  "guidance": NullableAgentExerciseResolveGuidance;
};

export type AgentFoodBatchWriteFood = {
  "id": string;
  "name": string;
  "nutrientsPer100": Record<string, unknown>;
  "isLiquid"?: boolean;
  "servingLabel"?: string | null;
  "servingSize"?: number | null;
  "packageSize"?: number | null;
  "recipeIngredients"?: Array<AgentFoodBatchWriteRecipeIngredient> | null;
  "recipeServingCount"?: number | null;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentFoodBatchWriteRecipeIngredient = {
  "foodId": string;
  "name": string;
  "foodSource": AgentFoodSource;
  "nutrientsPer100": Record<string, unknown>;
  "isLiquid": boolean;
  "portion": AgentFoodBatchWriteRecipeIngredientPortion;
  "servingLabel"?: string | null;
  "servingSize"?: number | null;
  "packageSize"?: number | null;
};

export type AgentFoodBatchWriteRecipeIngredientPortion = {
  "value": number;
  "entered": string;
  "unit": AgentFoodPortionUnit;
};

export type AgentFoodBatchWriteRequest = {
  "idempotencyKey": string;
  "foods": Array<AgentFoodBatchWriteFood>;
};

export type AgentFoodBatchWriteResponse = {
  "accepted": true;
  "duplicate": boolean;
  "idempotencyKey": string;
  "batchId": string;
  "serverClock": string;
  "foods": Array<AgentFoodBatchWriteResult>;
};

export type AgentFoodBatchWriteResult = {
  "id": string;
  "name": string;
  "isRecipe": boolean;
  "warnings": Array<AgentNutrientValidationIssue>;
};

export type AgentFoodField = "id" | "name" | "foodSource" | "nutrientsPer100" | "isLiquid" | "servingLabel" | "servingSize" | "packageSize" | "isRecipe" | "recipeServingCount" | "updatedAt" | "deletedAt";

export type AgentFoodListItem = {
  "id": string;
  "name": string;
  "foodSource"?: AgentFoodSource;
  "nutrientsPer100"?: Record<string, unknown>;
  "isLiquid"?: boolean;
  "servingLabel"?: string | null;
  "servingSize"?: number | null;
  "packageSize"?: number | null;
  "isRecipe"?: boolean;
  "recipeServingCount"?: number | null;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentFoodListResponse = {
  "foods": Array<AgentFoodListItem>;
  "limit": number;
  "nextCursor": string | null;
  "fields": Array<AgentFoodField>;
};

export type AgentFoodPlatformSearchResponse = {
  "foods": Array<AgentPlatformFood>;
  "limit": number;
  "attribution": AgentPlatformFoodAttribution;
};

export type AgentFoodPortionUnit = "gram" | "milliliter" | "ounce" | "fluidOunce" | "serving" | "package";

export type AgentFoodSource = "usda" | "openFoodFacts" | "user";

export type AgentFuellingSummary = {
  "workoutCount": number;
  "workoutsWithPreMeal": number;
  "workoutsWithPostMeal": number;
};

export type AgentHistorySet = {
  "id": string;
  "workoutId": string | null;
  "performedAt": string | null;
  "updatedAt": string;
  "exerciseId": string;
  "exerciseName": string | null;
  "category": NullableAgentHistorySetCategory;
  "position": number;
  "plannedRestAfter": number | null;
  "isCompleted": boolean;
  "values"?: AgentSetValidationValues;
  "rpe": string | number | unknown | null;
  "side": "left" | "right" | null;
  "comment": string | null;
};

export type AgentHistorySetCategory = {
  "id": string;
  "name": string;
};

export type AgentHistorySetsResponse = {
  "sets": Array<AgentHistorySet>;
  "limit": number;
  "nextCursor": string | null;
  "totalMatched": number;
};

export type AgentMealBatchWriteEntry = {
  "id": string;
  "position": number;
  "name"?: string;
  "nutrients"?: Record<string, unknown>;
  "isLiquid"?: boolean;
  "foodId"?: string | null;
  "foodSource"?: "usda" | "openFoodFacts" | "user" | null;
  "portion"?: {
  "value": number;
  "entered": string;
  "unit": AgentMealPortionUnit;
} | null;
  "servingLabel"?: string | null;
  "servingSize"?: number | null;
  "packageSize"?: number | null;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentMealBatchWriteEntryResult = {
  "id": string;
  "name": string;
  "kind": "food" | "quickEntry";
  "warnings": Array<AgentNutrientValidationIssue>;
};

export type AgentMealBatchWriteMeal = {
  "id": string;
  "mealType": string;
  "startedAt": string;
  "endedAt"?: string | null;
  "timezone": string;
  "localDate": string;
  "deletedAt"?: string | null;
};

export type AgentMealBatchWriteRequest = {
  "idempotencyKey": string;
  "meal": AgentMealBatchWriteMeal;
  "entries": Array<AgentMealBatchWriteEntry>;
};

export type AgentMealBatchWriteResponse = {
  "accepted": true;
  "duplicate": boolean;
  "idempotencyKey": string;
  "batchId": string;
  "mealId": string;
  "serverClock": string;
  "entries": Array<AgentMealBatchWriteEntryResult>;
};

export type AgentMealEntry = {
  "id": string;
  "position": number;
  "name": string;
  "kind": "food" | "quickEntry";
  "nutrients": Record<string, unknown>;
  "isLiquid": boolean;
  "foodId": string | null;
  "foodSource": string | null;
  "portion": {
  "value": number;
  "entered": string;
  "unit": string;
} | null;
  "servingLabel": string | null;
  "servingSize": number | null;
  "packageSize": number | null;
  "updatedAt": string;
};

export type AgentMealListField = "id" | "mealType" | "startedAt" | "endedAt" | "timezone" | "localDate" | "entries";

export type AgentMealListItem = {
  "id": string;
  "mealType"?: string;
  "startedAt"?: string;
  "endedAt"?: string | null;
  "timezone"?: string;
  "localDate"?: string;
  "entries"?: Array<AgentMealEntry>;
};

export type AgentMealListResponse = {
  "meals": Array<AgentMealListItem>;
  "fields": Array<AgentMealListField>;
  "limit": number;
  "nextCursor": string | null;
  "totalMatched": number;
};

export type AgentMealPortionUnit = "gram" | "milliliter" | "ounce" | "fluidOunce" | "serving" | "package";

export type AgentMetricBatchWriteMetric = {
  "id": string;
  "name": string;
  "unit": string;
  "valueShape": AgentMetricValueShape;
  "metricGroup": string;
  "goalType"?: string | null;
  "goalTargetValue"?: number | null;
  "enabled"?: boolean;
  "pinned"?: boolean;
  "sortOrder"?: number;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentMetricBatchWriteMetricResult = {
  "id": string;
  "name": string;
  "valueShape": AgentMetricValueShape;
  "unit": string;
  "metricGroup": string;
  "applied": boolean;
  "outcome": "applied" | "superseded" | "duplicate";
};

export type AgentMetricBatchWriteReading = {
  "id": string;
  "metricId": string;
  "value": AgentMetricReadingValue;
  "timeAnchor": AgentMetricReadingTimeAnchor;
  "provenance"?: string;
  "source"?: string;
  "externalId"?: string | null;
  "externalActivityId"?: string | null;
  "comment"?: string | null;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentMetricBatchWriteReadingResult = {
  "id": string;
  "metricId": string;
  "valueShape": AgentMetricValueShape;
  "unit": string;
  "warnings": Array<string>;
  "applied": boolean;
  "outcome": "applied" | "superseded" | "duplicate";
};

export type AgentMetricBatchWriteRequest = {
  "idempotencyKey": string;
  "metrics"?: Array<AgentMetricBatchWriteMetric>;
  "readings"?: Array<AgentMetricBatchWriteReading>;
};

export type AgentMetricBatchWriteResponse = {
  "accepted": true;
  "duplicate": boolean;
  "idempotencyKey": string;
  "batchId": string;
  "serverClock": string;
  "metrics": Array<AgentMetricBatchWriteMetricResult>;
  "readings": Array<AgentMetricBatchWriteReadingResult>;
};

export type AgentMetricListField = "id" | "name" | "canonicalKey" | "aliases" | "dataClass" | "unit" | "valueShape" | "metricGroup" | "goalType" | "goalTargetValue" | "enabled" | "pinned" | "sortOrder" | "updatedAt" | "deletedAt";

export type AgentMetricListItem = {
  "id": string;
  "name": string;
  "canonicalKey"?: string | null;
  "aliases"?: Array<string>;
  "dataClass"?: string | null;
  "unit"?: string;
  "valueShape"?: AgentMetricValueShape;
  "metricGroup"?: string;
  "goalType"?: string | null;
  "goalTargetValue"?: number | null;
  "enabled"?: boolean;
  "pinned"?: boolean;
  "sortOrder"?: number;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentMetricListResponse = {
  "metrics": Array<AgentMetricListItem>;
  "fields": Array<AgentMetricListField>;
  "limit": number;
  "nextCursor": string | null;
  "totalMatched": number;
};

export type AgentMetricReadingField = "id" | "metricId" | "externalActivityId" | "valueShape" | "unit" | "valueJson" | "scalarValue" | "scalarEntered" | "atTime" | "windowStartedAt" | "windowEndedAt" | "provenance" | "source" | "externalId" | "comment" | "warnings" | "updatedAt" | "deletedAt";

export type AgentMetricReadingListItem = {
  "id": string;
  "metricId": string;
  "externalActivityId"?: string | null;
  "valueShape"?: AgentMetricValueShape;
  "unit"?: string;
  "valueJson"?: Record<string, unknown>;
  "scalarValue"?: number | null;
  "scalarEntered"?: string | null;
  "atTime"?: string | null;
  "windowStartedAt"?: string | null;
  "windowEndedAt"?: string | null;
  "provenance"?: string;
  "source"?: string;
  "externalId"?: string | null;
  "comment"?: string | null;
  "warnings"?: Array<string>;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentMetricReadingTimeAnchor = {
  "atTime"?: string;
  "windowStartedAt"?: string;
  "windowEndedAt"?: string;
  "localDateTime"?: string;
  "timezoneOffsetMinutes"?: number;
};

export type AgentMetricReadingValue = unknown;

export type AgentMetricReadingsResponse = {
  "readings": Array<AgentMetricReadingListItem>;
  "fields": Array<AgentMetricReadingField>;
  "limit": number;
  "nextCursor": string | null;
  "totalMatched": number;
};

export type AgentMetricValueShape = "scalar" | "structured" | "series";

export type AgentMonitoringActivityResponse = {
  "externalActivity": AgentMonitoringExternalActivity;
  "summaryReadings": Array<AgentMonitoringSummaryReading>;
  "seriesSummaries": Array<AgentMonitoringSeriesSummary>;
  "heartRate": NullableAgentMonitoringHeartRateSummary;
  "route": NullableAgentMonitoringRouteSummary;
};

export type AgentMonitoringExternalActivity = {
  "id": string;
  "source": string;
  "externalId": string;
  "activityType": string;
  "startedAt": string;
  "endedAt": string;
  "timezone": string;
};

export type AgentMonitoringHeartRateSummary = {
  "seriesCount": number;
  "sampleCount": number;
  "minimumBpm": number;
  "averageBpm": number;
  "maximumBpm": number;
  "zoneSeconds": AgentMonitoringHeartRateZoneSeconds;
  "trend": AgentMonitoringHeartRateTrend;
};

export type AgentMonitoringHeartRateTrend = {
  "firstBpm": number;
  "lastBpm": number;
  "deltaBpm": number;
};

export type AgentMonitoringHeartRateZoneSeconds = {
  "below120": number;
  "bpm120To139": number;
  "bpm140To159": number;
  "bpm160To179": number;
  "bpm180Plus": number;
};

export type AgentMonitoringRouteSummary = {
  "seriesCount": number;
  "sampleCount": number;
  "distanceKilometers": number;
  "durationSeconds": number;
  "averagePaceSecondsPerKilometer": number | null;
};

export type AgentMonitoringSeriesSummary = {
  "seriesType": string;
  "sampleCount": number;
  "firstSampleAt": string;
  "lastSampleAt": string;
};

export type AgentMonitoringSummaryReading = {
  "id": string;
  "metricId": string;
  "metricKey": string;
  "unit": string;
  "scalarValue": number | null;
  "scalarEntered": string | null;
  "atTime": string | null;
  "windowStartedAt": string | null;
  "windowEndedAt": string | null;
  "provenance": string;
  "source": string;
  "externalId": string | null;
  "updatedAt": string;
};

export type AgentNutrientGoalProgress = {
  "nutrient": AgentNutritionGoalableNutrientId;
  "status": AgentNutrientGoalStatus;
  "total": AgentNutrientTotal;
  "target": AgentNutrientGoalTarget | unknown | null;
  "ratio": number | null;
  "remaining": number | null;
};

export type AgentNutrientGoalStatus = "noGoal" | "unknown" | "below" | "met" | "over";

export type AgentNutrientGoalTarget = {
  "nutrient": AgentNutritionGoalableNutrientId;
  "unit": AgentNutritionNutrientUnit;
  "value": number;
};

export type AgentNutrientId = "energy" | "protein" | "carbohydrate" | "sugar" | "fat" | "saturated_fat" | "monounsaturated_fat" | "polyunsaturated_fat" | "fiber" | "sodium" | "cholesterol" | "vitamin_a" | "vitamin_c" | "vitamin_d" | "vitamin_e" | "vitamin_k" | "thiamin" | "riboflavin" | "niacin" | "vitamin_b6" | "folate" | "vitamin_b12" | "calcium" | "iron" | "magnesium" | "phosphorus" | "potassium" | "zinc" | "copper" | "manganese" | "selenium" | "caffeine" | "water" | null;

export type AgentNutrientTotal = {
  "nutrient": AgentNutritionNutrientId;
  "unit": AgentNutritionNutrientUnit;
  "value": number;
  "complete": boolean;
};

export type AgentNutrientValidationIssue = {
  "field": string;
  "nutrient": AgentNutrientId;
  "rule": string;
  "message": string;
  "limit": number | string | unknown | null;
};

export type AgentNutritionDayTotals = {
  "localDate": string;
  "mealCount": number;
  "entryCount": number;
  "totals": Array<AgentNutrientTotal>;
  "goalProgress": Array<AgentNutrientGoalProgress>;
};

export type AgentNutritionGoal = {
  "id": string;
  "nutrient": AgentNutritionGoalableNutrientId;
  "value": number;
  "unit": AgentNutritionGoalUnit;
  "updatedAt": string;
  "deletedAt": string | null;
};

export type AgentNutritionGoalBatchWriteRequest = {
  "idempotencyKey": string;
  "targets": Array<AgentNutritionGoalBatchWriteTarget>;
};

export type AgentNutritionGoalBatchWriteResponse = {
  "accepted": true;
  "duplicate": boolean;
  "idempotencyKey": string;
  "batchId": string;
  "serverClock": string;
  "targets": Array<AgentNutritionGoalBatchWriteTargetResult>;
};

export type AgentNutritionGoalBatchWriteTarget = {
  "id": string;
  "nutrient": AgentNutritionGoalableNutrientId;
  "value": number;
  "unit"?: AgentNutritionGoalUnit & unknown;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentNutritionGoalBatchWriteTargetResult = {
  "id": string;
  "nutrient": AgentNutritionGoalableNutrientId;
  "outcome": "applied" | "superseded" | "duplicate";
};

export type AgentNutritionGoalListResponse = {
  "goals": Array<AgentNutritionGoal>;
};

export type AgentNutritionGoalUnit = "kilocalorie" | "gram" | "milligram" | "microgram" | "milliliter";

export type AgentNutritionGoalableNutrientId = "energy" | "protein" | "carbohydrate" | "fat";

export type AgentNutritionNutrientId = "energy" | "protein" | "carbohydrate" | "sugar" | "fat" | "saturated_fat" | "monounsaturated_fat" | "polyunsaturated_fat" | "fiber" | "sodium" | "cholesterol" | "vitamin_a" | "vitamin_c" | "vitamin_d" | "vitamin_e" | "vitamin_k" | "thiamin" | "riboflavin" | "niacin" | "vitamin_b6" | "folate" | "vitamin_b12" | "calcium" | "iron" | "magnesium" | "phosphorus" | "potassium" | "zinc" | "copper" | "manganese" | "selenium" | "caffeine" | "water";

export type AgentNutritionNutrientUnit = "kilocalorie" | "gram" | "milligram" | "microgram" | "milliliter";

export type AgentNutritionPeriodTotals = {
  "from": string;
  "to": string;
  "dayCount": number;
  "loggedDayCount": number;
  "mealCount": number;
  "entryCount": number;
  "totals": Array<AgentNutrientTotal>;
  "goalProgress": Array<AgentNutrientGoalProgress>;
};

export type AgentNutritionTotalsResponse = {
  "from": string;
  "to": string;
  "dayCount": number;
  "goalSource": "query" | "stored" | "none";
  "period": AgentNutritionPeriodTotals;
  "days": Array<AgentNutritionDayTotals>;
};

export type AgentNutritionTrend = {
  "nutrient": AgentNutritionNutrientId;
  "unit": AgentNutritionNutrientUnit;
  "target": AgentNutrientGoalTarget | unknown | null;
  "points": Array<AgentNutritionTrendPoint>;
};

export type AgentNutritionTrendPoint = {
  "localDate": string;
  "value": number | null;
  "complete": boolean;
};

export type AgentNutritionTrendsResponse = {
  "from": string;
  "to": string;
  "dayCount": number;
  "goalSource": "query" | "stored" | "none";
  "trends": Array<AgentNutritionTrend>;
  "goalProgress": Array<AgentNutrientGoalProgress>;
};

export type AgentPeriodStats = {
  "setCount": number;
  "firstPerformedAt": string | null;
  "lastPerformedAt": string | null;
  "totalVolumeKilograms": number | null;
  "totalReps": number | null;
  "totalDurationSeconds": number | null;
  "totalDistanceKilometers": number | null;
  "maxEstimatedOneRepMaxKilograms": number | null;
};

export type AgentPlanCadence = unknown;

export type AgentPlanCadenceKind = "weekly" | "rotating" | null;

export type AgentPlanCadenceSlot = {
  "slot": number;
  "entries": Array<AgentPlanRoutineEntry>;
};

export type AgentPlanCaptureIssue = AgentSetValidationIssue & {
  "sourcePath": string;
};

export type AgentPlanCaptureLimits = {
  "maxRows": number;
  "repeatMin": number;
  "repeatWarnAbove": number;
  "restAfterSecondsMin": number;
  "templateGroupRoundsMin": number;
  "templateGroupMembersMin": number;
  "templateGroupColorHexFormat": string;
  "cadenceKinds": Array<string>;
  "rotatingWindowMin": number;
  "rotatingWindowWarnAbove": number;
  "weeklySlotMin": number;
  "weeklySlotMax": number;
  "routineEntrySlotMin": number;
};

export type AgentPlanCaptureRequest = {
  "idempotencyKey": string;
  "workoutId": string;
  "name"?: string;
  "routineId"?: string | null;
  "slot"?: number | null;
};

export type AgentPlanCaptureResponse = {
  "accepted": true;
  "duplicate": boolean;
  "idempotencyKey": string;
  "batchId": string;
  "workoutId": string;
  "workoutTemplateId": string;
  "routineEntryId": string | null;
  "exerciseCount": number;
  "prescriptionCount": number;
  "groupCount": number;
  "serverClock": string;
  "warnings": Array<AgentPlanCaptureIssue>;
  "limits": AgentPlanCaptureLimits;
};

export type AgentPlanDimensionValue = {
  "value": number | null;
  "unit": string | null;
  "entered": string | null;
} | null;

export type AgentPlanDivergence = {
  "addedExercises": Array<{
  "exerciseId": string;
  "exerciseName": string;
}>;
  "removedExercises": Array<{
  "exerciseId": string;
  "exerciseName": string;
}>;
  "changedExercises": Array<{
  "exerciseId": string;
  "exerciseName": string;
}>;
  "groupsChanged": boolean;
};

export type AgentPlanMaterializeIssue = AgentSetValidationIssue & {
  "exerciseId": string | null;
  "prescriptionId": string | null;
};

export type AgentPlanMaterializeLimits = {
  "maxSets": number;
};

export type AgentPlanMaterializeRequest = {
  "idempotencyKey": string;
  "workoutTemplateId": string;
  "routineId"?: string | null;
  "slot"?: number | null;
  "startedAt"?: string;
  "timezone": string;
};

export type AgentPlanMaterializeResponse = {
  "accepted": true;
  "duplicate": boolean;
  "idempotencyKey": string;
  "batchId": string;
  "workoutId": string;
  "templateLinkId": string;
  "setIds": Array<string>;
  "setCount": number;
  "startedAt": string;
  "timezone": string;
  "localDate": string;
  "workoutTemplateId": string;
  "routineId": string | null;
  "slot": number | null;
  "serverClock": string;
  "warnings": Array<AgentPlanMaterializeIssue>;
  "limits": AgentPlanMaterializeLimits;
};

export type AgentPlanPrescription = {
  "id": string;
  "templateExerciseId": string;
  "mode": "fixed" | "copyPrevious";
  "position": number;
  "repeat": number;
  "restAfterSeconds": number | null;
  "load": AgentPlanDimensionValue;
  "reps": AgentPlanDimensionValue;
  "duration": AgentPlanDimensionValue;
  "distance": AgentPlanDimensionValue;
  "updatedAt": string;
  "deletedAt": string | null;
};

export type AgentPlanRoutineEntry = {
  "id": string;
  "routineId": string;
  "workoutTemplateId": string;
  "workoutTemplateName": string;
  "workoutTemplateArchived": boolean;
  "position": number;
  "slot": number | null;
  "updatedAt": string;
  "deletedAt": string | null;
};

export type AgentPlanTemplateExercise = {
  "id": string;
  "workoutTemplateId": string;
  "exerciseId": string;
  "position": number;
  "note": string | null;
  "prescriptions": Array<AgentPlanPrescription>;
  "prescriptionCount": number;
  "prescriptionsTruncated": boolean;
  "updatedAt": string;
  "deletedAt": string | null;
};

export type AgentPlanTemplateGroup = {
  "id": string;
  "workoutTemplateId": string;
  "name": string;
  "colorHex": string;
  "rounds": number;
  "position": number;
  "members": Array<AgentPlanTemplateGroupMember>;
  "memberCount": number;
  "membersTruncated": boolean;
  "updatedAt": string;
  "deletedAt": string | null;
};

export type AgentPlanTemplateGroupMember = {
  "id": string;
  "groupId": string;
  "templateExerciseId": string;
  "position": number;
  "updatedAt": string;
  "deletedAt": string | null;
};

export type AgentPlanTreeBatchWriteCounts = {
  "workoutTemplates": number;
  "templateExercises": number;
  "prescriptions": number;
  "templateGroups": number;
  "templateGroupMembers": number;
  "routines": number;
  "routineEntries": number;
};

export type AgentPlanTreeBatchWriteItemResult = {
  "entityType": AgentPlanTreeEntityType;
  "itemIndex": number;
  "id": string;
  "outcome": "validated" | "applied" | "superseded" | "duplicate";
  "warnings": Array<AgentSetValidationIssue>;
};

export type AgentPlanTreeBatchWritePrescription = {
  "id": string;
  "templateExerciseId": string;
  "mode": string;
  "position": number;
  "repeat": number;
  "restAfterSeconds"?: number | null;
  "values"?: AgentSetValidationValues & unknown;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentPlanTreeBatchWriteRequest = {
  "idempotencyKey": string;
  "expectedCounts": AgentPlanTreeBatchWriteCounts & unknown;
  "dryRun"?: boolean;
  "workoutTemplates"?: Array<AgentPlanTreeBatchWriteWorkoutTemplate>;
  "templateExercises"?: Array<AgentPlanTreeBatchWriteTemplateExercise>;
  "prescriptions"?: Array<AgentPlanTreeBatchWritePrescription>;
  "templateGroups"?: Array<AgentPlanTreeBatchWriteTemplateGroup>;
  "templateGroupMembers"?: Array<AgentPlanTreeBatchWriteTemplateGroupMember>;
  "routines"?: Array<AgentPlanTreeBatchWriteRoutine>;
  "routineEntries"?: Array<AgentPlanTreeBatchWriteRoutineEntry>;
};

export type AgentPlanTreeBatchWriteResponse = {
  "accepted": true;
  "dryRun": boolean;
  "duplicate": boolean;
  "idempotencyKey": string;
  "batchId": string | null;
  "serverClock": string;
  "expectedCounts": AgentPlanTreeBatchWriteCounts;
  "actualCounts": AgentPlanTreeBatchWriteCounts;
  "items": Array<AgentPlanTreeBatchWriteItemResult>;
};

export type AgentPlanTreeBatchWriteRoutine = {
  "id": string;
  "name": string;
  "notes"?: string | null;
  "cadenceKind"?: string | null;
  "cadenceWindow"?: number | null;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentPlanTreeBatchWriteRoutineEntry = {
  "id": string;
  "routineId": string;
  "workoutTemplateId": string;
  "position": number;
  "slot"?: number | null;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentPlanTreeBatchWriteTemplateExercise = {
  "id": string;
  "workoutTemplateId": string;
  "exerciseId": string;
  "position": number;
  "note"?: string | null;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentPlanTreeBatchWriteTemplateGroup = {
  "id": string;
  "workoutTemplateId": string;
  "name": string;
  "colorHex": string;
  "rounds": number;
  "position": number;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentPlanTreeBatchWriteTemplateGroupMember = {
  "id": string;
  "groupId": string;
  "templateExerciseId": string;
  "position": number;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentPlanTreeBatchWriteWorkoutTemplate = {
  "id": string;
  "name": string;
  "notes"?: string | null;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentPlanTreeEntityType = "workoutTemplate" | "templateExercise" | "prescription" | "templateGroup" | "templateGroupMember" | "routine" | "routineEntry";

export type AgentPlanUpNext = {
  "selectedDate": string;
  "slot": number;
  "cards": Array<AgentPlanUpNextCard>;
} | null;

export type AgentPlanUpNextCard = {
  "routineEntryId": string;
  "workoutTemplateId": string;
  "workoutTemplateName": string;
  "slot": number;
  "isDone": boolean;
};

export type AgentPlanUpdateFromWorkoutRequest = {
  "idempotencyKey": string;
  "workoutId": string;
};

export type AgentPlanUpdateFromWorkoutResponse = {
  "accepted": true;
  "duplicate": boolean;
  "idempotencyKey": string;
  "batchId": string;
  "workoutId": string;
  "workoutTemplateId": string;
  "exerciseCount": number;
  "prescriptionCount": number;
  "groupCount": number;
  "divergence": AgentPlanDivergence;
  "serverClock": string;
  "warnings": Array<AgentPlanCaptureIssue>;
  "limits": AgentPlanCaptureLimits;
};

export type AgentPlatformFood = {
  "id": string;
  "name": string;
  "foodSource": AgentPlatformFoodSource;
  "nutrientsPer100": Record<string, unknown>;
  "isLiquid": boolean;
  "servingLabel": string | null;
  "servingSize": number | null;
  "packageSize": number | null;
};

export type AgentPlatformFoodAttribution = {
  "source": AgentPlatformFoodSource;
  "datasetVersion": string;
  "sourceName": string;
  "sourceUrl": string;
  "licenseName": string;
  "attributionText": string;
};

export type AgentPlatformFoodSource = "usda";

export type AgentProteinCohort = {
  "dayCount": number;
  "completeDayCount": number;
  "incompleteDayCount": number;
  "averageProtein": number | null;
  "totalProtein": number | null;
};

export type AgentProtocol = {
  "id": string;
  "name": string;
  "startDate": string | null;
  "endDate": string | null;
  "updatedAt": string;
  "deletedAt": string | null;
  "members": Array<AgentProtocolMember>;
  "schedules": Array<AgentProtocolSchedule>;
  "targetOutcomes": Array<AgentProtocolTargetOutcome>;
};

export type AgentProtocolBatchWriteMember = {
  "id": AgentProtocolsClientRowId & unknown;
  "compoundId": string;
  "position"?: number;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentProtocolBatchWriteProtocol = {
  "id": AgentProtocolsClientRowId & unknown;
  "name": string;
  "startDate"?: string | null;
  "endDate"?: string | null;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
  "members"?: Array<AgentProtocolBatchWriteMember>;
  "schedules"?: Array<AgentProtocolBatchWriteSchedule>;
  "targetOutcomes"?: Array<AgentProtocolBatchWriteTargetOutcome>;
};

export type AgentProtocolBatchWriteRequest = {
  "idempotencyKey": string;
  "protocols": Array<AgentProtocolBatchWriteProtocol>;
};

export type AgentProtocolBatchWriteResponse = {
  "accepted": true;
  "duplicate": boolean;
  "idempotencyKey": string;
  "batchId": string;
  "serverClock": string;
  "protocols": Array<AgentProtocolsEntityBatchWriteResult>;
};

export type AgentProtocolBatchWriteSchedule = {
  "id": AgentProtocolsClientRowId & unknown;
  "protocolCompoundId": string;
  "doseAmountValue"?: number | null;
  "doseAmountEntered"?: string | null;
  "doseUnit"?: "milligram" | "microgram" | "gram" | "internationalUnit" | "milliliter" | "tablet" | "capsule" | "drop" | "spray" | "puff" | "patch" | "unit";
  "frequency": string;
  "route"?: "oral" | "sublingual" | "subcutaneous" | "intramuscular" | "transdermal" | "intranasal" | "inhaled" | "topical" | "other";
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentProtocolBatchWriteTargetOutcome = {
  "id": AgentProtocolsClientRowId & unknown;
  "metricId"?: string | null;
  "outcomeKind"?: string;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentProtocolListResponse = {
  "protocols": Array<AgentProtocol>;
  "limit": number;
  "nextCursor": string | null;
  "totalMatched": number;
};

export type AgentProtocolMember = {
  "id": string;
  "compoundId": string;
  "position": number;
  "updatedAt": string;
  "deletedAt": string | null;
};

export type AgentProtocolSchedule = {
  "id": string;
  "protocolCompoundId": string;
  "doseAmountValue": number | null;
  "doseAmountEntered": string | null;
  "doseUnit": "milligram" | "microgram" | "gram" | "internationalUnit" | "milliliter" | "tablet" | "capsule" | "drop" | "spray" | "puff" | "patch" | "unit";
  "frequency": string;
  "route": "oral" | "sublingual" | "subcutaneous" | "intramuscular" | "transdermal" | "intranasal" | "inhaled" | "topical" | "other";
  "updatedAt": string;
  "deletedAt": string | null;
};

export type AgentProtocolTargetOutcome = {
  "id": string;
  "metricId": string | null;
  "outcomeKind": string;
  "updatedAt": string;
  "deletedAt": string | null;
};

export type AgentProtocolsClientRowId = string | string;

export type AgentProtocolsEntityBatchWriteResult = {
  "id": string;
  "name": string | null;
  "outcome": "applied" | "superseded" | "duplicate" | "refused";
};

export type AgentReadDimensionId = "load" | "reps" | "duration" | "distance";

export type AgentReadExerciseAnalyticsProfile = {
  "type": Array<AgentReadDimensionId>;
  "loadMode": "added" | "assisted";
  "recordProfile": AgentReadRecordProfile;
};

export type AgentReadRecordProfile = "repMax" | "maxLoad" | "maxReps" | "maxDuration" | "minDuration" | "maxDistance" | "fastestPace" | "minAssistancePerRepCount" | "completionStreak";

export type AgentReadTrainingUnit = "kilogram" | "pound" | "repetition" | "second" | "kilometer" | "mile";

export type AgentRecordCatalog = {
  "repMaxRecords": Array<AgentAnalyticsRecord>;
  "minAssistanceRecords": Array<AgentAnalyticsRecord>;
  "maxLoad": NullableAgentAnalyticsRecord;
  "maxReps": NullableAgentAnalyticsRecord;
  "maxDuration": NullableAgentAnalyticsRecord;
  "minDuration": NullableAgentAnalyticsRecord;
  "maxDistance": NullableAgentAnalyticsRecord;
  "fastestPace": NullableAgentAnalyticsRecord;
};

export type AgentRoutineDetail = {
  "id": string;
  "name": string;
  "notes": string | null;
  "cadence": AgentPlanCadence;
  "entries": Array<AgentPlanRoutineEntry>;
  "slotLayout": Array<AgentPlanCadenceSlot> | null;
  "upNext": AgentPlanUpNext;
  "entryLimit": number;
  "entryCount": number;
  "entriesReturned": number;
  "entriesTruncated": boolean;
  "updatedAt": string;
  "deletedAt": string | null;
};

export type AgentRoutineDetailResponse = {
  "routine": AgentRoutineDetail;
};

export type AgentRoutineListField = "id" | "name" | "notes" | "cadenceKind" | "cadenceWindow" | "entryCount" | "updatedAt" | "deletedAt";

export type AgentRoutineListItem = {
  "id": string;
  "name": string;
  "notes"?: string | null;
  "cadenceKind"?: AgentPlanCadenceKind;
  "cadenceWindow"?: number | null;
  "entryCount"?: number;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentRoutineListResponse = {
  "routines": Array<AgentRoutineListItem>;
  "fields": Array<AgentRoutineListField>;
  "limit": number;
  "nextCursor": string | null;
  "totalMatched": number;
};

export type AgentSetDimensionId = "load" | "reps" | "duration" | "distance";

export type AgentSetDimensionValue = {
  "entered": string;
  "unit": "kilogram" | "pound" | "repetition" | "second" | "kilometer" | "mile";
};

export type AgentSetExerciseLoadMode = "added" | "assisted";

export type AgentSetIssueDimensionId = "load" | "reps" | "duration" | "distance" | null;

export type AgentSetValidationExercise = {
  "dimensions": Array<AgentSetDimensionId>;
  "loadMode"?: AgentSetExerciseLoadMode;
};

export type AgentSetValidationIssue = {
  "field": string;
  "dimension": AgentSetIssueDimensionId;
  "rule": string;
  "message": string;
  "limit": number | string | unknown | null;
};

export type AgentSetValidationLimits = {
  "numericMin": 0;
  "maxDecimalPlaces": 5;
  "loadMaxKilograms": 1000;
  "loadMaxDecimalPlaces": 2;
  "addedLoadWarnKilograms": 350;
  "assistedLoadWarnKilograms": 150;
  "repsMax": 10000;
  "repsWarnAbove": 200;
  "durationMaxSeconds": 86400;
  "durationWarnAboveSeconds": 14400;
  "distanceMaxKilometers": 1000;
  "distanceWarnAboveKilometers": 250;
  "rpeMin": 0;
  "rpeMax": 10;
  "rpeStep": 0.5;
  "speedWarnAboveKilometersPerHour": 50;
  "allowedSides": Array<"left" | "right">;
};

export type AgentSetValidationRequest = {
  "exercise": AgentSetValidationExercise;
  "values"?: AgentSetValidationValues;
  "rpe"?: string | number;
  "side"?: "left" | "right";
};

export type AgentSetValidationResponse = {
  "accepted": true;
  "warnings": Array<AgentSetValidationIssue>;
  "limits": AgentSetValidationLimits;
};

export type AgentSetValidationValues = {
  "load"?: AgentSetDimensionValue;
  "reps"?: AgentSetDimensionValue & unknown;
  "duration"?: AgentSetDimensionValue & unknown;
  "distance"?: AgentSetDimensionValue & unknown;
};

export type AgentSettingsBatchWriteFields = {
  "themePreference"?: string;
  "unitSystem"?: string;
  "weekStartDay"?: string;
  "defaultWeightIncrement"?: number;
  "homeScreenDisplay"?: string;
  "prTrackingEnabled"?: boolean;
  "markSetsCompleteByDefault"?: boolean;
  "autoSelectNextSet"?: boolean;
};

export type AgentSettingsBatchWriteRequest = {
  "idempotencyKey": string;
  "updatedAt"?: string;
  "fields": AgentSettingsBatchWriteFields;
};

export type AgentSettingsBatchWriteResponse = {
  "accepted": true;
  "duplicate": boolean;
  "idempotencyKey": string;
  "batchId": string;
  "serverClock": string;
  "settings": AgentSettingsFields & unknown;
  "updatedAt": string;
};

export type AgentSettingsFields = {
  "themePreference": "system" | "light" | "dark";
  "unitSystem": "metric" | "imperial";
  "weekStartDay": "monday" | "sunday";
  "defaultWeightIncrement": number;
  "homeScreenDisplay": "comfortable" | "compact";
  "prTrackingEnabled": boolean;
  "markSetsCompleteByDefault": boolean;
  "autoSelectNextSet": boolean;
};

export type AgentSettingsReadResponse = {
  "settings": AgentSettingsFields;
  "updatedAt": string | null;
};

export type AgentTrainingDayNutritionResponse = {
  "from": string;
  "to": string;
  "dayCount": number;
  "trainingDayCount": number;
  "proteinUnit": "gram";
  "protein": {
  "trainingDays": AgentProteinCohort;
  "restDays": AgentProteinCohort;
};
  "fuelling": {
  "preWindowMinutes": number;
  "postWindowMinutes": number;
  "summary": AgentFuellingSummary;
  "perWorkout": Array<AgentWorkoutFuelling>;
  "workoutPointLimit": number;
  "truncated": boolean;
};
};

export type AgentWorkoutBatchWriteRequest = {
  "idempotencyKey": string;
  "workout": AgentWorkoutBatchWriteWorkout;
  "sets": Array<AgentWorkoutBatchWriteSet>;
};

export type AgentWorkoutBatchWriteResponse = {
  "accepted": true;
  "duplicate": boolean;
  "idempotencyKey": string;
  "batchId": string;
  "workoutId": string;
  "serverClock": string;
  "sets": Array<AgentWorkoutBatchWriteSetResult>;
};

export type AgentWorkoutBatchWriteSet = {
  "id": string;
  "exerciseName": string;
  "position": number;
  "plannedRestAfter"?: number | null;
  "performedAt"?: string | null;
  "isCompleted"?: boolean;
  "values"?: AgentSetValidationValues;
  "rpe"?: string | number;
  "side"?: "left" | "right";
  "comment"?: string | null;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentWorkoutBatchWriteSetResult = {
  "id": string;
  "exerciseId": string;
  "exerciseName": string;
  "requestedExerciseName": string;
  "warnings": Array<AgentSetValidationIssue>;
};

export type AgentWorkoutBatchWriteWorkout = {
  "id": string;
  "startedAt": string;
  "endedAt"?: string | null;
  "timezone": string;
  "comment"?: string | null;
  "deletedAt"?: string | null;
};

export type AgentWorkoutDetailCoverage = {
  "workoutMetadata": "authoritative" | "inferred_from_sets";
  "structure": "authoritative" | "template_link_snapshot" | "unavailable";
  "exerciseIdentity": "complete" | "partial" | "unavailable";
  "unresolvedExerciseIds": Array<string>;
  "truncated": boolean;
};

export type AgentWorkoutDetailResponse = {
  "workout": AgentWorkoutDetailWorkout;
  "sets": Array<AgentHistorySet>;
  "workoutExercises": Array<AgentWorkoutExercise>;
  "exerciseGroups": Array<AgentWorkoutExerciseGroup>;
  "exerciseCatalog": Array<AgentWorkoutExerciseCatalogEntry>;
  "templateLink": AgentWorkoutTemplateLink | unknown | null;
  "coverage": AgentWorkoutDetailCoverage;
};

export type AgentWorkoutDetailWorkout = {
  "id": string;
  "startedAt": string;
  "timezone": string | null;
  "localDate": string | null;
  "endedAt": string | null;
  "comment": string | null;
  "updatedAt": string;
  "active": boolean;
};

export type AgentWorkoutExercise = {
  "id": string;
  "exerciseId": string;
  "position": number;
  "active": boolean;
};

export type AgentWorkoutExerciseCatalogEntry = {
  "requestedId": string;
  "canonicalId": string | null;
  "resolution": "matched" | "redirected" | "unresolved";
  "name": string | null;
  "library": "user" | "platform" | null;
  "category": NullableAgentHistorySetCategory;
  "dimensions": Array<AgentReadDimensionId>;
  "equipment": Array<string>;
  "loadMode": "added" | "assisted" | null;
  "recordProfile": "repMax" | "maxLoad" | "maxReps" | "maxDuration" | "minDuration" | "maxDistance" | "fastestPace" | "minAssistancePerRepCount" | "completionStreak" | null;
  "active": boolean | null;
};

export type AgentWorkoutExerciseGroup = {
  "id": string;
  "name": string;
  "colorHex": string;
  "position": number;
  "active": boolean;
  "members": Array<AgentWorkoutExerciseGroupMember>;
};

export type AgentWorkoutExerciseGroupMember = {
  "id": string;
  "workoutExerciseId": string;
  "position": number;
  "active": boolean;
};

export type AgentWorkoutFuelling = {
  "workoutId": string;
  "workoutStartedAt": string;
  "preWorkoutMealCount": number;
  "postWorkoutMealCount": number;
  "minutesSincePreWorkoutMeal": number | null;
  "minutesUntilPostWorkoutMeal": number | null;
};

export type AgentWorkoutListField = "id" | "startedAt" | "endedAt" | "timezone" | "comment" | "setCount" | "exerciseNames";

export type AgentWorkoutListItem = {
  "id": string;
  "startedAt"?: string;
  "endedAt"?: string | null;
  "timezone"?: string | null;
  "comment"?: string | null;
  "setCount"?: number;
  "exerciseNames"?: Array<string>;
};

export type AgentWorkoutListResponse = {
  "workouts": Array<AgentWorkoutListItem>;
  "fields": Array<AgentWorkoutListField>;
  "limit": number;
  "nextCursor": string | null;
  "totalMatched": number;
};

export type AgentWorkoutTemplateDetail = {
  "id": string;
  "name": string;
  "notes": string | null;
  "exercises": Array<AgentPlanTemplateExercise>;
  "groups": Array<AgentPlanTemplateGroup>;
  "exerciseCount": number;
  "groupCount": number;
  "componentLimit": number;
  "componentCount": number;
  "componentsReturned": number;
  "componentsTruncated": boolean;
  "updatedAt": string;
  "deletedAt": string | null;
};

export type AgentWorkoutTemplateDetailResponse = {
  "workoutTemplate": AgentWorkoutTemplateDetail;
};

export type AgentWorkoutTemplateLink = {
  "id": string;
  "workoutTemplateId": string;
  "routineId": string | null;
  "slot": string | number | unknown | null;
  "active": boolean;
};

export type AgentWorkoutTemplateListField = "id" | "name" | "notes" | "exerciseCount" | "groupCount" | "updatedAt" | "deletedAt";

export type AgentWorkoutTemplateListItem = {
  "id": string;
  "name": string;
  "notes"?: string | null;
  "exerciseCount"?: number;
  "groupCount"?: number;
  "updatedAt"?: string;
  "deletedAt"?: string | null;
};

export type AgentWorkoutTemplateListResponse = {
  "workoutTemplates": Array<AgentWorkoutTemplateListItem>;
  "fields": Array<AgentWorkoutTemplateListField>;
  "limit": number;
  "nextCursor": string | null;
  "totalMatched": number;
};

export type NullableAgentAnalyticsRecord = AgentAnalyticsRecord | unknown | null;

export type NullableAgentExercise = AgentExercise | unknown | null;

export type NullableAgentExerciseResolveGuidance = AgentExerciseResolveGuidance | unknown | null;

export type NullableAgentHistorySetCategory = AgentHistorySetCategory | unknown | null;

export type NullableAgentMonitoringHeartRateSummary = AgentMonitoringHeartRateSummary | unknown | null;

export type NullableAgentMonitoringRouteSummary = AgentMonitoringRouteSummary | unknown | null;

export type GetAgentEnergyBalanceInput = {
  "from": string;
  "to": string;
};

export type GetAgentExerciseAnalyticsInput = {
  "exerciseId": string;
  "from"?: string;
  "to"?: string;
  "maxPoints"?: number;
};

export type GetAgentMonitoringActivityInput = {
  "externalActivityId": string;
};

export type GetAgentNutritionTotalsInput = {
  "from": string;
  "to": string;
  "energyGoal"?: number | null;
  "proteinGoal"?: number | null;
  "carbohydrateGoal"?: number | null;
  "fatGoal"?: number | null;
};

export type GetAgentNutritionTrendsInput = {
  "from": string;
  "to": string;
  "energyGoal"?: number | null;
  "proteinGoal"?: number | null;
  "carbohydrateGoal"?: number | null;
  "fatGoal"?: number | null;
};

export type GetAgentRoutineInput = {
  "routineId": string;
  "includeArchived"?: boolean | null;
  "componentLimit"?: number;
  "selectedDate"?: string;
};

export type GetAgentTrainingDayNutritionInput = {
  "from": string;
  "to": string;
  "preWindowMinutes"?: number;
  "postWindowMinutes"?: number;
};

export type GetAgentWorkoutInput = {
  "workoutId": string;
};

export type GetAgentWorkoutTemplateInput = {
  "workoutTemplateId": string;
  "includeArchived"?: boolean | null;
  "componentLimit"?: number;
};

export type ListAgentActivityInput = {
  "actor"?: string;
  "entityTable"?: string;
  "batchId"?: string;
  "from"?: string;
  "to"?: string;
  "limit"?: number;
  "cursor"?: string;
};

export type ListAgentCompoundsInput = {
  "search"?: string;
  "includeArchived"?: boolean | null;
  "limit"?: number;
  "cursor"?: string;
  "fields"?: string;
};

export type ListAgentDosesInput = {
  "compoundId"?: string;
  "protocolId"?: string;
  "from"?: string;
  "to"?: string;
  "provenance"?: string;
  "includeArchived"?: boolean | null;
  "limit"?: number;
  "cursor"?: string;
  "fields"?: string;
};

export type ListAgentExercisesInput = {
  "search"?: string;
  "category"?: string;
  "favorite"?: "true" | "false";
  "activeOnly"?: "true" | "false";
  "limit"?: number;
  "cursor"?: string;
  "fields"?: string;
};

export type ListAgentFoodsInput = {
  "search"?: string;
  "includeArchived"?: boolean | null;
  "limit"?: number;
  "cursor"?: string;
  "fields"?: string;
};

export type ListAgentHistorySetsInput = {
  "exerciseId"?: string;
  "category"?: string;
  "from"?: string;
  "to"?: string;
  "minLoadKilograms"?: number | null;
  "minReps"?: number | null;
  "minDurationSeconds"?: number | null;
  "minDistanceKilometers"?: number | null;
  "limit"?: number;
  "cursor"?: string;
};

export type ListAgentMealsInput = {
  "from"?: string;
  "to"?: string;
  "limit"?: number;
  "cursor"?: string;
  "fields"?: string;
};

export type ListAgentMetricReadingsInput = {
  "metricId"?: string;
  "metricKey"?: string;
  "from"?: string;
  "to"?: string;
  "provenance"?: string;
  "source"?: string;
  "includeArchived"?: boolean | null;
  "limit"?: number;
  "cursor"?: string;
  "fields"?: string;
};

export type ListAgentMetricsInput = {
  "search"?: string;
  "metricKey"?: string;
  "metricGroup"?: string;
  "enabledOnly"?: boolean | null;
  "includeArchived"?: boolean | null;
  "limit"?: number;
  "cursor"?: string;
  "fields"?: string;
};

export type ListAgentProtocolsInput = {
  "search"?: string;
  "includeArchived"?: boolean | null;
  "limit"?: number;
  "cursor"?: string;
};

export type ListAgentRoutinesInput = {
  "search"?: string;
  "includeArchived"?: boolean | null;
  "limit"?: number;
  "cursor"?: string;
  "fields"?: string;
};

export type ListAgentWorkoutsInput = {
  "from"?: string;
  "to"?: string;
  "limit"?: number;
  "cursor"?: string;
  "fields"?: string;
};

export type ListAgentWorkoutTemplatesInput = {
  "search"?: string;
  "includeArchived"?: boolean | null;
  "limit"?: number;
  "cursor"?: string;
  "fields"?: string;
};

export type ReadAgentEffectWindowInput = {
  "compoundId"?: string;
  "protocolId"?: string;
  "metricId"?: string;
  "metricKey"?: string;
  "from": string;
  "to": string;
};

export type ResolveAgentExerciseNameInput = {
  "name": string;
  "candidateLimit"?: number | null;
};

export type RevokeAgentApiKeyInput = {
  "keyId": string;
};

export type SearchAgentPlatformFoodsInput = {
  "search"?: string;
  "source"?: AgentPlatformFoodSource & unknown;
  "limit"?: number;
};

export const AGENT_CLIENT_OPERATION_IDS = [
  "batchWriteAgentCompounds",
  "batchWriteAgentDoses",
  "batchWriteAgentExerciseCatalog",
  "batchWriteAgentFoods",
  "batchWriteAgentMeal",
  "batchWriteAgentMetrics",
  "batchWriteAgentNutritionGoals",
  "batchWriteAgentPlanTree",
  "batchWriteAgentProtocols",
  "batchWriteAgentSettings",
  "batchWriteAgentWorkout",
  "captureAgentWorkoutTemplate",
  "createAgentApiKey",
  "getAgentEnergyBalance",
  "getAgentExerciseAnalytics",
  "getAgentMonitoringActivity",
  "getAgentNutritionTotals",
  "getAgentNutritionTrends",
  "getAgentProtectedProbe",
  "getAgentRoutine",
  "getAgentTrainingDayNutrition",
  "getAgentWorkout",
  "getAgentWorkoutTemplate",
  "listAgentActivity",
  "listAgentApiKeys",
  "listAgentCompounds",
  "listAgentDoses",
  "listAgentExercises",
  "listAgentFoods",
  "listAgentHistorySets",
  "listAgentMeals",
  "listAgentMetricReadings",
  "listAgentMetrics",
  "listAgentNutritionGoals",
  "listAgentProtocols",
  "listAgentRoutines",
  "listAgentWorkoutTemplates",
  "listAgentWorkouts",
  "materializeAgentWorkoutTemplate",
  "readAgentEffectWindow",
  "readAgentSettings",
  "resolveAgentExerciseName",
  "revokeAgentApiKey",
  "searchAgentPlatformFoods",
  "undoAgentActivityBatch",
  "updateAgentWorkoutTemplateFromWorkout",
  "validateAgentDose",
  "validateAgentSet"
] as const;

export class AgentApiError extends Error {
  constructor({
    body,
    status
  }: {
    body: string;
    status: number;
  }) {
    super(`Agent API request failed with status ${status}.`);
    this.name = "AgentApiError";
    this.body = body;
    this.status = status;
  }

  readonly body: string;
  readonly status: number;
}

export class PerenniaAgentClient {
  static readonly openApiSource = "packages/contract/openapi.json";

  constructor(options: AgentClientOptions) {
    this.baseUrl = new URL(options.baseUrl);
    this.bearerToken = options.bearerToken;
    const fetchImplementation =
      options.fetch ??
      (globalThis.fetch as unknown as AgentClientFetch | undefined);

    if (fetchImplementation === undefined) {
      throw new Error("PerenniaAgentClient requires a fetch implementation.");
    }
    this.fetchImplementation = fetchImplementation;
  }

  private readonly baseUrl: URL;
  private readonly bearerToken: string;
  private readonly fetchImplementation: AgentClientFetch;

  async batchWriteAgentCompounds(body: AgentCompoundBatchWriteRequest, options: AgentClientRequestOptions = {}): Promise<AgentCompoundBatchWriteResponse> {
    return this.request<AgentCompoundBatchWriteResponse>({
      method: "POST",
      path: "/agent/protocols/compounds/batch-write",
      expectedStatus: 200,
      body: body,
      signal: options.signal
    });
  }

  async batchWriteAgentDoses(body: AgentDoseBatchWriteRequest, options: AgentClientRequestOptions = {}): Promise<AgentDoseBatchWriteResponse> {
    return this.request<AgentDoseBatchWriteResponse>({
      method: "POST",
      path: "/agent/protocols/doses/batch-write",
      expectedStatus: 200,
      body: body,
      signal: options.signal
    });
  }

  async batchWriteAgentExerciseCatalog(body: AgentExerciseCatalogBatchWriteRequest, options: AgentClientRequestOptions = {}): Promise<AgentExerciseCatalogBatchWriteResponse> {
    return this.request<AgentExerciseCatalogBatchWriteResponse>({
      method: "POST",
      path: "/agent/exercises/batch-write",
      expectedStatus: 200,
      body: body,
      signal: options.signal
    });
  }

  async batchWriteAgentFoods(body: AgentFoodBatchWriteRequest, options: AgentClientRequestOptions = {}): Promise<AgentFoodBatchWriteResponse> {
    return this.request<AgentFoodBatchWriteResponse>({
      method: "POST",
      path: "/agent/foods/batch-write",
      expectedStatus: 200,
      body: body,
      signal: options.signal
    });
  }

  async batchWriteAgentMeal(body: AgentMealBatchWriteRequest, options: AgentClientRequestOptions = {}): Promise<AgentMealBatchWriteResponse> {
    return this.request<AgentMealBatchWriteResponse>({
      method: "POST",
      path: "/agent/meals/batch-write",
      expectedStatus: 200,
      body: body,
      signal: options.signal
    });
  }

  async batchWriteAgentMetrics(body: AgentMetricBatchWriteRequest, options: AgentClientRequestOptions = {}): Promise<AgentMetricBatchWriteResponse> {
    return this.request<AgentMetricBatchWriteResponse>({
      method: "POST",
      path: "/agent/metrics/batch-write",
      expectedStatus: 200,
      body: body,
      signal: options.signal
    });
  }

  async batchWriteAgentNutritionGoals(body: AgentNutritionGoalBatchWriteRequest, options: AgentClientRequestOptions = {}): Promise<AgentNutritionGoalBatchWriteResponse> {
    return this.request<AgentNutritionGoalBatchWriteResponse>({
      method: "POST",
      path: "/agent/nutrition/goals/batch-write",
      expectedStatus: 200,
      body: body,
      signal: options.signal
    });
  }

  async batchWriteAgentPlanTree(body: AgentPlanTreeBatchWriteRequest, options: AgentClientRequestOptions = {}): Promise<AgentPlanTreeBatchWriteResponse> {
    return this.request<AgentPlanTreeBatchWriteResponse>({
      method: "POST",
      path: "/agent/plan-tree/batch-write",
      expectedStatus: 200,
      body: body,
      signal: options.signal
    });
  }

  async batchWriteAgentProtocols(body: AgentProtocolBatchWriteRequest, options: AgentClientRequestOptions = {}): Promise<AgentProtocolBatchWriteResponse> {
    return this.request<AgentProtocolBatchWriteResponse>({
      method: "POST",
      path: "/agent/protocols/batch-write",
      expectedStatus: 200,
      body: body,
      signal: options.signal
    });
  }

  async batchWriteAgentSettings(body: AgentSettingsBatchWriteRequest, options: AgentClientRequestOptions = {}): Promise<AgentSettingsBatchWriteResponse> {
    return this.request<AgentSettingsBatchWriteResponse>({
      method: "POST",
      path: "/agent/settings/batch-write",
      expectedStatus: 200,
      body: body,
      signal: options.signal
    });
  }

  async batchWriteAgentWorkout(body: AgentWorkoutBatchWriteRequest, options: AgentClientRequestOptions = {}): Promise<AgentWorkoutBatchWriteResponse> {
    return this.request<AgentWorkoutBatchWriteResponse>({
      method: "POST",
      path: "/agent/workouts/batch-write",
      expectedStatus: 200,
      body: body,
      signal: options.signal
    });
  }

  async captureAgentWorkoutTemplate(body: AgentPlanCaptureRequest, options: AgentClientRequestOptions = {}): Promise<AgentPlanCaptureResponse> {
    return this.request<AgentPlanCaptureResponse>({
      method: "POST",
      path: "/agent/workout-templates/capture",
      expectedStatus: 200,
      body: body,
      signal: options.signal
    });
  }

  async createAgentApiKey(body: AgentApiKeyCreateRequest, options: AgentClientRequestOptions = {}): Promise<AgentApiKeyCreateResponse> {
    return this.request<AgentApiKeyCreateResponse>({
      method: "POST",
      path: "/agent/api-keys",
      expectedStatus: 201,
      body: body,
      signal: options.signal
    });
  }

  async getAgentEnergyBalance(input: GetAgentEnergyBalanceInput, options: AgentClientRequestOptions = {}): Promise<AgentEnergyBalanceResponse> {
    return this.request<AgentEnergyBalanceResponse>({
      method: "GET",
      path: "/agent/cross-domain/energy-balance",
      expectedStatus: 200,
      query: { "from": input.from, "to": input.to },
      signal: options.signal
    });
  }

  async getAgentExerciseAnalytics(input: GetAgentExerciseAnalyticsInput, options: AgentClientRequestOptions = {}): Promise<AgentExerciseAnalyticsResponse> {
    return this.request<AgentExerciseAnalyticsResponse>({
      method: "GET",
      path: `/agent/analytics/exercises/${encodeURIComponent(String(input["exerciseId"]))}`,
      expectedStatus: 200,
      query: { "from": input.from, "to": input.to, "maxPoints": input.maxPoints },
      signal: options.signal
    });
  }

  async getAgentMonitoringActivity(input: GetAgentMonitoringActivityInput, options: AgentClientRequestOptions = {}): Promise<AgentMonitoringActivityResponse> {
    return this.request<AgentMonitoringActivityResponse>({
      method: "GET",
      path: `/agent/monitoring/activities/${encodeURIComponent(String(input["externalActivityId"]))}`,
      expectedStatus: 200,
      signal: options.signal
    });
  }

  async getAgentNutritionTotals(input: GetAgentNutritionTotalsInput, options: AgentClientRequestOptions = {}): Promise<AgentNutritionTotalsResponse> {
    return this.request<AgentNutritionTotalsResponse>({
      method: "GET",
      path: "/agent/nutrition/totals",
      expectedStatus: 200,
      query: { "from": input.from, "to": input.to, "energyGoal": input.energyGoal, "proteinGoal": input.proteinGoal, "carbohydrateGoal": input.carbohydrateGoal, "fatGoal": input.fatGoal },
      signal: options.signal
    });
  }

  async getAgentNutritionTrends(input: GetAgentNutritionTrendsInput, options: AgentClientRequestOptions = {}): Promise<AgentNutritionTrendsResponse> {
    return this.request<AgentNutritionTrendsResponse>({
      method: "GET",
      path: "/agent/nutrition/trends",
      expectedStatus: 200,
      query: { "from": input.from, "to": input.to, "energyGoal": input.energyGoal, "proteinGoal": input.proteinGoal, "carbohydrateGoal": input.carbohydrateGoal, "fatGoal": input.fatGoal },
      signal: options.signal
    });
  }

  async getAgentProtectedProbe(options: AgentClientRequestOptions = {}): Promise<AgentApiKeyProtectedProbeResponse> {
    return this.request<AgentApiKeyProtectedProbeResponse>({
      method: "GET",
      path: "/agent/probe",
      expectedStatus: 200,
      signal: options.signal
    });
  }

  async getAgentRoutine(input: GetAgentRoutineInput, options: AgentClientRequestOptions = {}): Promise<AgentRoutineDetailResponse> {
    return this.request<AgentRoutineDetailResponse>({
      method: "GET",
      path: `/agent/routines/${encodeURIComponent(String(input["routineId"]))}`,
      expectedStatus: 200,
      query: { "includeArchived": input.includeArchived, "componentLimit": input.componentLimit, "selectedDate": input.selectedDate },
      signal: options.signal
    });
  }

  async getAgentTrainingDayNutrition(input: GetAgentTrainingDayNutritionInput, options: AgentClientRequestOptions = {}): Promise<AgentTrainingDayNutritionResponse> {
    return this.request<AgentTrainingDayNutritionResponse>({
      method: "GET",
      path: "/agent/cross-domain/training-day-nutrition",
      expectedStatus: 200,
      query: { "from": input.from, "to": input.to, "preWindowMinutes": input.preWindowMinutes, "postWindowMinutes": input.postWindowMinutes },
      signal: options.signal
    });
  }

  async getAgentWorkout(input: GetAgentWorkoutInput, options: AgentClientRequestOptions = {}): Promise<AgentWorkoutDetailResponse> {
    return this.request<AgentWorkoutDetailResponse>({
      method: "GET",
      path: `/agent/workouts/${encodeURIComponent(String(input["workoutId"]))}`,
      expectedStatus: 200,
      signal: options.signal
    });
  }

  async getAgentWorkoutTemplate(input: GetAgentWorkoutTemplateInput, options: AgentClientRequestOptions = {}): Promise<AgentWorkoutTemplateDetailResponse> {
    return this.request<AgentWorkoutTemplateDetailResponse>({
      method: "GET",
      path: `/agent/workout-templates/${encodeURIComponent(String(input["workoutTemplateId"]))}`,
      expectedStatus: 200,
      query: { "includeArchived": input.includeArchived, "componentLimit": input.componentLimit },
      signal: options.signal
    });
  }

  async listAgentActivity(input: ListAgentActivityInput = {}, options: AgentClientRequestOptions = {}): Promise<AgentActivityListResponse> {
    return this.request<AgentActivityListResponse>({
      method: "GET",
      path: "/agent/activity",
      expectedStatus: 200,
      query: { "actor": input.actor, "entityTable": input.entityTable, "batchId": input.batchId, "from": input.from, "to": input.to, "limit": input.limit, "cursor": input.cursor },
      signal: options.signal
    });
  }

  async listAgentApiKeys(options: AgentClientRequestOptions = {}): Promise<AgentApiKeyListResponse> {
    return this.request<AgentApiKeyListResponse>({
      method: "GET",
      path: "/agent/api-keys",
      expectedStatus: 200,
      signal: options.signal
    });
  }

  async listAgentCompounds(input: ListAgentCompoundsInput = {}, options: AgentClientRequestOptions = {}): Promise<AgentCompoundListResponse> {
    return this.request<AgentCompoundListResponse>({
      method: "GET",
      path: "/agent/protocols/compounds",
      expectedStatus: 200,
      query: { "search": input.search, "includeArchived": input.includeArchived, "limit": input.limit, "cursor": input.cursor, "fields": input.fields },
      signal: options.signal
    });
  }

  async listAgentDoses(input: ListAgentDosesInput = {}, options: AgentClientRequestOptions = {}): Promise<AgentDoseListResponse> {
    return this.request<AgentDoseListResponse>({
      method: "GET",
      path: "/agent/protocols/doses",
      expectedStatus: 200,
      query: { "compoundId": input.compoundId, "protocolId": input.protocolId, "from": input.from, "to": input.to, "provenance": input.provenance, "includeArchived": input.includeArchived, "limit": input.limit, "cursor": input.cursor, "fields": input.fields },
      signal: options.signal
    });
  }

  async listAgentExercises(input: ListAgentExercisesInput = {}, options: AgentClientRequestOptions = {}): Promise<AgentExerciseListResponse> {
    return this.request<AgentExerciseListResponse>({
      method: "GET",
      path: "/agent/exercises",
      expectedStatus: 200,
      query: { "search": input.search, "category": input.category, "favorite": input.favorite, "activeOnly": input.activeOnly, "limit": input.limit, "cursor": input.cursor, "fields": input.fields },
      signal: options.signal
    });
  }

  async listAgentFoods(input: ListAgentFoodsInput = {}, options: AgentClientRequestOptions = {}): Promise<AgentFoodListResponse> {
    return this.request<AgentFoodListResponse>({
      method: "GET",
      path: "/agent/foods",
      expectedStatus: 200,
      query: { "search": input.search, "includeArchived": input.includeArchived, "limit": input.limit, "cursor": input.cursor, "fields": input.fields },
      signal: options.signal
    });
  }

  async listAgentHistorySets(input: ListAgentHistorySetsInput = {}, options: AgentClientRequestOptions = {}): Promise<AgentHistorySetsResponse> {
    return this.request<AgentHistorySetsResponse>({
      method: "GET",
      path: "/agent/history/sets",
      expectedStatus: 200,
      query: { "exerciseId": input.exerciseId, "category": input.category, "from": input.from, "to": input.to, "minLoadKilograms": input.minLoadKilograms, "minReps": input.minReps, "minDurationSeconds": input.minDurationSeconds, "minDistanceKilometers": input.minDistanceKilometers, "limit": input.limit, "cursor": input.cursor },
      signal: options.signal
    });
  }

  async listAgentMeals(input: ListAgentMealsInput = {}, options: AgentClientRequestOptions = {}): Promise<AgentMealListResponse> {
    return this.request<AgentMealListResponse>({
      method: "GET",
      path: "/agent/meals",
      expectedStatus: 200,
      query: { "from": input.from, "to": input.to, "limit": input.limit, "cursor": input.cursor, "fields": input.fields },
      signal: options.signal
    });
  }

  async listAgentMetricReadings(input: ListAgentMetricReadingsInput = {}, options: AgentClientRequestOptions = {}): Promise<AgentMetricReadingsResponse> {
    return this.request<AgentMetricReadingsResponse>({
      method: "GET",
      path: "/agent/metrics/readings",
      expectedStatus: 200,
      query: { "metricId": input.metricId, "metricKey": input.metricKey, "from": input.from, "to": input.to, "provenance": input.provenance, "source": input.source, "includeArchived": input.includeArchived, "limit": input.limit, "cursor": input.cursor, "fields": input.fields },
      signal: options.signal
    });
  }

  async listAgentMetrics(input: ListAgentMetricsInput = {}, options: AgentClientRequestOptions = {}): Promise<AgentMetricListResponse> {
    return this.request<AgentMetricListResponse>({
      method: "GET",
      path: "/agent/metrics",
      expectedStatus: 200,
      query: { "search": input.search, "metricKey": input.metricKey, "metricGroup": input.metricGroup, "enabledOnly": input.enabledOnly, "includeArchived": input.includeArchived, "limit": input.limit, "cursor": input.cursor, "fields": input.fields },
      signal: options.signal
    });
  }

  async listAgentNutritionGoals(options: AgentClientRequestOptions = {}): Promise<AgentNutritionGoalListResponse> {
    return this.request<AgentNutritionGoalListResponse>({
      method: "GET",
      path: "/agent/nutrition/goals",
      expectedStatus: 200,
      signal: options.signal
    });
  }

  async listAgentProtocols(input: ListAgentProtocolsInput = {}, options: AgentClientRequestOptions = {}): Promise<AgentProtocolListResponse> {
    return this.request<AgentProtocolListResponse>({
      method: "GET",
      path: "/agent/protocols",
      expectedStatus: 200,
      query: { "search": input.search, "includeArchived": input.includeArchived, "limit": input.limit, "cursor": input.cursor },
      signal: options.signal
    });
  }

  async listAgentRoutines(input: ListAgentRoutinesInput = {}, options: AgentClientRequestOptions = {}): Promise<AgentRoutineListResponse> {
    return this.request<AgentRoutineListResponse>({
      method: "GET",
      path: "/agent/routines",
      expectedStatus: 200,
      query: { "search": input.search, "includeArchived": input.includeArchived, "limit": input.limit, "cursor": input.cursor, "fields": input.fields },
      signal: options.signal
    });
  }

  async listAgentWorkouts(input: ListAgentWorkoutsInput = {}, options: AgentClientRequestOptions = {}): Promise<AgentWorkoutListResponse> {
    return this.request<AgentWorkoutListResponse>({
      method: "GET",
      path: "/agent/workouts",
      expectedStatus: 200,
      query: { "from": input.from, "to": input.to, "limit": input.limit, "cursor": input.cursor, "fields": input.fields },
      signal: options.signal
    });
  }

  async listAgentWorkoutTemplates(input: ListAgentWorkoutTemplatesInput = {}, options: AgentClientRequestOptions = {}): Promise<AgentWorkoutTemplateListResponse> {
    return this.request<AgentWorkoutTemplateListResponse>({
      method: "GET",
      path: "/agent/workout-templates",
      expectedStatus: 200,
      query: { "search": input.search, "includeArchived": input.includeArchived, "limit": input.limit, "cursor": input.cursor, "fields": input.fields },
      signal: options.signal
    });
  }

  async materializeAgentWorkoutTemplate(body: AgentPlanMaterializeRequest, options: AgentClientRequestOptions = {}): Promise<AgentPlanMaterializeResponse> {
    return this.request<AgentPlanMaterializeResponse>({
      method: "POST",
      path: "/agent/workout-templates/materialize",
      expectedStatus: 200,
      body: body,
      signal: options.signal
    });
  }

  async readAgentEffectWindow(input: ReadAgentEffectWindowInput, options: AgentClientRequestOptions = {}): Promise<AgentEffectWindowResponse> {
    return this.request<AgentEffectWindowResponse>({
      method: "GET",
      path: "/agent/protocols/effect-window",
      expectedStatus: 200,
      query: { "compoundId": input.compoundId, "protocolId": input.protocolId, "metricId": input.metricId, "metricKey": input.metricKey, "from": input.from, "to": input.to },
      signal: options.signal
    });
  }

  async readAgentSettings(options: AgentClientRequestOptions = {}): Promise<AgentSettingsReadResponse> {
    return this.request<AgentSettingsReadResponse>({
      method: "GET",
      path: "/agent/settings",
      expectedStatus: 200,
      signal: options.signal
    });
  }

  async resolveAgentExerciseName(input: ResolveAgentExerciseNameInput, options: AgentClientRequestOptions = {}): Promise<AgentExerciseResolveResponse> {
    return this.request<AgentExerciseResolveResponse>({
      method: "GET",
      path: "/agent/exercises/resolve",
      expectedStatus: 200,
      query: { "name": input.name, "candidateLimit": input.candidateLimit },
      signal: options.signal
    });
  }

  async revokeAgentApiKey(input: RevokeAgentApiKeyInput, options: AgentClientRequestOptions = {}): Promise<AgentApiKeyRevokeResponse> {
    return this.request<AgentApiKeyRevokeResponse>({
      method: "DELETE",
      path: `/agent/api-keys/${encodeURIComponent(String(input["keyId"]))}`,
      expectedStatus: 200,
      signal: options.signal
    });
  }

  async searchAgentPlatformFoods(input: SearchAgentPlatformFoodsInput = {}, options: AgentClientRequestOptions = {}): Promise<AgentFoodPlatformSearchResponse> {
    return this.request<AgentFoodPlatformSearchResponse>({
      method: "GET",
      path: "/agent/foods/platform-search",
      expectedStatus: 200,
      query: { "search": input.search, "source": input.source, "limit": input.limit },
      signal: options.signal
    });
  }

  async undoAgentActivityBatch(body: AgentActivityUndoBatchRequest, options: AgentClientRequestOptions = {}): Promise<AgentActivityUndoBatchResponse> {
    return this.request<AgentActivityUndoBatchResponse>({
      method: "POST",
      path: "/agent/activity/undo-batch",
      expectedStatus: 200,
      body: body,
      signal: options.signal
    });
  }

  async updateAgentWorkoutTemplateFromWorkout(body: AgentPlanUpdateFromWorkoutRequest, options: AgentClientRequestOptions = {}): Promise<AgentPlanUpdateFromWorkoutResponse> {
    return this.request<AgentPlanUpdateFromWorkoutResponse>({
      method: "POST",
      path: "/agent/workout-templates/update-from-workout",
      expectedStatus: 200,
      body: body,
      signal: options.signal
    });
  }

  async validateAgentDose(body: AgentDoseValidationRequest, options: AgentClientRequestOptions = {}): Promise<AgentDoseValidationResponse> {
    return this.request<AgentDoseValidationResponse>({
      method: "POST",
      path: "/agent/validate-dose",
      expectedStatus: 200,
      body: body,
      signal: options.signal
    });
  }

  async validateAgentSet(body: AgentSetValidationRequest, options: AgentClientRequestOptions = {}): Promise<AgentSetValidationResponse> {
    return this.request<AgentSetValidationResponse>({
      method: "POST",
      path: "/agent/validate-set",
      expectedStatus: 200,
      body: body,
      signal: options.signal
    });
  }

  private async request<TResponse>({
    body,
    expectedStatus,
    method,
    path,
    query,
    signal
  }: {
    body?: unknown;
    expectedStatus: number;
    method: string;
    path: string;
    query?: Record<string, unknown>;
    signal?: unknown;
  }): Promise<TResponse> {
    const url = new URL(path, this.baseUrl);
    for (const [key, value] of Object.entries(query ?? {})) {
      if (value === undefined || value === null) {
        continue;
      }
      url.searchParams.set(key, String(value));
    }

    const headers: Record<string, string> = {
      accept: "application/json",
      authorization: `Bearer ${this.bearerToken}`
    };
    let encodedBody: string | undefined;
    if (body !== undefined) {
      headers["content-type"] = "application/json";
      encodedBody = JSON.stringify(body);
    }

    const response = await this.fetchImplementation(url.toString(), {
      method,
      headers,
      body: encodedBody,
      signal
    });
    const responseBody = await response.text();

    if (response.status !== expectedStatus) {
      throw new AgentApiError({ body: responseBody, status: response.status });
    }

    return (responseBody.length === 0
      ? undefined
      : JSON.parse(responseBody)) as TResponse;
  }
}
