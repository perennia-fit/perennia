import type { z } from "@hono/zod-openapi";

import {
  CanonicalActivitySchema,
  CanonicalMetricReadingSchema,
  CanonicalSeriesSchema,
  type CanonicalActivity,
  type CanonicalImportDataClass,
  type CanonicalMetricReading,
  type CanonicalSeries
} from "./canonical-import.js";
import {
  CANONICAL_ACTIVITY_PLATFORM_EXERCISES,
  normalizeCanonicalActivityExerciseMapping,
  type NormalizedCanonicalActivity
} from "./canonical-activity-mapping.js";
import {
  validateAgentSet,
  type AgentSetValidationInput,
  type AgentSetValidationIssue
} from "./agent-validation.js";
import type {
  ExternalActivityStore,
  StoredExternalActivity
} from "./external-activities.js";
import { owlMetricSchemaForImportKey } from "./metric-catalog.js";

export type CanonicalIngestionReviewFlag = {
  itemType: "activity" | "series" | "metricReading";
  itemIndex: number;
  severity: "warning" | "error";
  field: string;
  rule: string;
  message: string;
};

export type CanonicalActivityIngestionStatus =
  | "created"
  | "refreshed"
  | "tombstoned"
  | "notStored";

export type CanonicalActivityIngestionResult = {
  itemIndex: number;
  source: string | null;
  externalId: string | null;
  status: CanonicalActivityIngestionStatus;
  stored: StoredExternalActivity | null;
  reviewFlags: CanonicalIngestionReviewFlag[];
};

export type CanonicalMaterializedWorkoutStatus =
  | "created"
  | "existing"
  | "refreshed"
  | "tombstoned";

export type CanonicalMaterializedWorkout = {
  workoutId: string;
  setIds: string[];
  externalActivityId: string;
  source: string;
  externalId: string;
  exerciseId: string;
  status: CanonicalMaterializedWorkoutStatus;
};

export type CanonicalActivityLink = {
  id: string;
  workoutId: string;
  externalActivityId: string;
  linkKind: string;
  status: CanonicalMaterializedWorkoutStatus;
};

export type CanonicalActivityLinkSuggestion = {
  externalActivityId: string;
  source: string;
  externalId: string;
  candidateWorkoutIds: string[];
  reason: "ambiguous_time_overlap";
};

export type CanonicalActivityMaterializationResult = {
  workout: CanonicalMaterializedWorkout;
  activityLink: CanonicalActivityLink;
};

export type CanonicalActivityLinkingResult =
  | {
      kind: "linked";
      activityLink: CanonicalActivityLink;
    }
  | {
      kind: "suggested";
      suggestion: CanonicalActivityLinkSuggestion;
    }
  | {
      kind: "none";
    };

export type CanonicalMaterializationSet = {
  source: string;
  externalId: string;
  timezone: string;
  performedAt?: string;
  values: AgentSetValidationInput["values"];
  warnings: AgentSetValidationIssue[];
};

export type CanonicalActivityMaterializationStore = {
  linkActivityByTimeOverlap(input: {
    userId: string;
    deviceId: string;
    activity: NormalizedCanonicalActivity;
    externalActivity: StoredExternalActivity;
    importedAt?: Date;
  }): Promise<CanonicalActivityLinkingResult>;
  materializeCardioActivity(input: {
    userId: string;
    deviceId: string;
    activity: NormalizedCanonicalActivity;
    externalActivity: StoredExternalActivity;
    set: CanonicalMaterializationSet;
    importedAt?: Date;
  }): Promise<CanonicalActivityMaterializationResult | null>;
  materializeStrengthActivity(input: {
    userId: string;
    deviceId: string;
    activity: NormalizedCanonicalActivity;
    externalActivity: StoredExternalActivity;
    sets: CanonicalMaterializationSet[];
    importedAt?: Date;
  }): Promise<CanonicalActivityMaterializationResult | null>;
};

export type CanonicalIngestionBatchInput = {
  userId: string;
  deviceId: string;
  importedAt?: Date;
  activities: unknown[];
  series?: unknown[];
  metricReadings?: unknown[];
  consentedDataClasses?: readonly CanonicalImportDataClass[];
};

export type CanonicalIngestionBatchResult = {
  accepted: true;
  activities: CanonicalActivityIngestionResult[];
  storedExternalActivities: StoredExternalActivity[];
  series: CanonicalSeries[];
  metricReadings: CanonicalMetricReading[];
  reviewFlags: CanonicalIngestionReviewFlag[];
  materializedWorkouts: CanonicalMaterializedWorkout[];
  activityLinks: CanonicalActivityLink[];
  activityLinkSuggestions: CanonicalActivityLinkSuggestion[];
};

export type CanonicalIngestionPipeline = {
  ingestCanonicalBatch(
    input: CanonicalIngestionBatchInput
  ): Promise<CanonicalIngestionBatchResult>;
};

export function createCanonicalIngestionPipeline({
  externalActivityStore,
  activityMaterializationStore
}: {
  externalActivityStore: ExternalActivityStore;
  activityMaterializationStore?: CanonicalActivityMaterializationStore;
}): CanonicalIngestionPipeline {
  return {
    async ingestCanonicalBatch({
      userId,
      deviceId,
      importedAt,
      activities,
      series = [],
      metricReadings = [],
      consentedDataClasses = []
    }) {
      const reviewFlags: CanonicalIngestionReviewFlag[] = [];
      const activityResults: CanonicalActivityIngestionResult[] = [];
      const storedExternalActivities: StoredExternalActivity[] = [];
      const materializedWorkouts: CanonicalMaterializedWorkout[] = [];
      const activityLinks: CanonicalActivityLink[] = [];
      const activityLinkSuggestions: CanonicalActivityLinkSuggestion[] = [];
      const consentFilter = filterCanonicalItemsByConsent({
        activities,
        metricReadings,
        series,
        consentedDataClasses
      });
      reviewFlags.push(...consentFilter.reviewFlags);

      const normalizedSeries = normalizeItems({
        itemType: "series",
        rawItems: consentFilter.series,
        schema: CanonicalSeriesSchema,
        reviewFlags
      });
      const normalizedMetricReadings = normalizeItems({
        itemType: "metricReading",
        rawItems: consentFilter.metricReadings,
        schema: CanonicalMetricReadingSchema,
        reviewFlags
      });

      for (const [itemIndex, rawActivity] of consentFilter.activities.entries()) {
        const normalized = normalizeCanonicalActivity(rawActivity, itemIndex);
        reviewFlags.push(...normalized.reviewFlags);
        const activityConsentFlags =
          consentFilter.activityReviewFlagsByIndex.get(itemIndex) ?? [];

        if (normalized.activity === null) {
          activityResults.push({
            itemIndex,
            source: normalized.source,
            externalId: normalized.externalId,
            status: "notStored",
            stored: null,
            reviewFlags: [...normalized.reviewFlags, ...activityConsentFlags]
          });
          continue;
        }

        const existing = await externalActivityStore.findExternalActivity({
          userId,
          source: normalized.activity.source,
          externalId: normalized.activity.externalId
        });
        const stored = await externalActivityStore.storeCanonicalActivity({
          userId,
          deviceId,
          activity: normalized.activity,
          importedAt
        });
        const status =
          stored === null
            ? "tombstoned"
            : existing === null
              ? "created"
              : "refreshed";

        if (stored !== null) {
          storedExternalActivities.push(stored);
          if (activityMaterializationStore !== undefined) {
            const materialized = await materializeActivity({
              activity: normalized.activity,
              activityMaterializationStore,
              deviceId,
              externalActivity: stored,
              importedAt,
              itemIndex,
              reviewFlags,
              userId
            });
            if (materialized !== null) {
              if (materialized.workout !== null) {
                materializedWorkouts.push(materialized.workout);
              }
              if (materialized.activityLink !== null) {
                activityLinks.push(materialized.activityLink);
              }
              if (materialized.activityLinkSuggestion !== null) {
                activityLinkSuggestions.push(materialized.activityLinkSuggestion);
              }
            }
          }
        }

        activityResults.push({
          itemIndex,
          source: normalized.activity.source,
          externalId: normalized.activity.externalId,
          status,
          stored,
          reviewFlags: [...normalized.reviewFlags, ...activityConsentFlags]
        });
      }

      return {
        accepted: true,
        activities: activityResults,
        storedExternalActivities,
        series: normalizedSeries,
        metricReadings: normalizedMetricReadings,
        reviewFlags,
        materializedWorkouts,
        activityLinks,
        activityLinkSuggestions
      };
    }
  };
}

type StoredMetricReadingInput =
  | CanonicalMetricReading
  | CanonicalActivity["summaryMetrics"][number];

function filterCanonicalItemsByConsent({
  activities,
  metricReadings,
  series,
  consentedDataClasses
}: {
  activities: unknown[];
  metricReadings: unknown[];
  series: unknown[];
  consentedDataClasses: readonly CanonicalImportDataClass[];
}) {
  const consented = new Set(consentedDataClasses);
  const reviewFlags: CanonicalIngestionReviewFlag[] = [];
  const activityReviewFlagsByIndex = new Map<
    number,
    CanonicalIngestionReviewFlag[]
  >();
  const addActivityFlag = (itemIndex: number, flag: CanonicalIngestionReviewFlag) => {
    reviewFlags.push(flag);
    activityReviewFlagsByIndex.set(itemIndex, [
      ...(activityReviewFlagsByIndex.get(itemIndex) ?? []),
      flag
    ]);
  };

  const filteredActivities = consented.has("activities")
    ? activities.map((activity, itemIndex) =>
        filterActivitySummaryMetricsByConsent({
          activity,
          consentedDataClasses: consented,
          itemIndex,
          addActivityFlag
        })
      )
    : [];

  if (!consented.has("activities")) {
    for (const itemIndex of activities.keys()) {
      reviewFlags.push(
        notConsentedReviewFlag({
          itemType: "activity",
          itemIndex,
          field: `activities[${itemIndex}]`,
          rule: "activity_data_not_consented",
          dataClass: "activities"
        })
      );
    }
  }

  return {
    activities: filteredActivities,
    metricReadings: filterMetricReadingsByConsent({
      rawReadings: metricReadings,
      consentedDataClasses: consented,
      reviewFlags
    }),
    series: filterSeriesByConsent({
      rawSeries: series,
      consentedDataClasses: consented,
      reviewFlags
    }),
    reviewFlags,
    activityReviewFlagsByIndex
  };
}

function filterActivitySummaryMetricsByConsent({
  activity,
  consentedDataClasses,
  itemIndex,
  addActivityFlag
}: {
  activity: unknown;
  consentedDataClasses: Set<CanonicalImportDataClass>;
  itemIndex: number;
  addActivityFlag: (itemIndex: number, flag: CanonicalIngestionReviewFlag) => void;
}) {
  const parsed = parseActivityForConsent(activity);
  if (parsed === null) {
    return activity;
  }

  const summaryMetrics = parsed.summaryMetrics.filter(
    (reading, summaryMetricIndex) => {
      const dataClass = metricReadingDataClass(reading);
      if (dataClass === "gps") {
        addActivityFlag(
          itemIndex,
          gpsSummaryNotSupportedReviewFlag({
            itemType: "activity",
            itemIndex,
            field: `activities[${itemIndex}].summaryMetrics[${summaryMetricIndex}]`
          })
        );
        return false;
      }

      if (consentedDataClasses.has(dataClass)) {
        return true;
      }

      addActivityFlag(
        itemIndex,
        notConsentedReviewFlag({
          itemType: "activity",
          itemIndex,
          field: `activities[${itemIndex}].summaryMetrics[${summaryMetricIndex}]`,
          rule: "monitoring_data_not_consented",
          dataClass
        })
      );
      return false;
    }
  );

  return isRecord(activity)
    ? { ...activity, summaryMetrics }
    : { ...parsed, summaryMetrics };
}

function filterMetricReadingsByConsent({
  rawReadings,
  consentedDataClasses,
  reviewFlags
}: {
  rawReadings: unknown[];
  consentedDataClasses: Set<CanonicalImportDataClass>;
  reviewFlags: CanonicalIngestionReviewFlag[];
}) {
  const filtered: unknown[] = [];
  for (const [itemIndex, rawReading] of rawReadings.entries()) {
    const parsed = CanonicalMetricReadingSchema.safeParse(rawReading);
    if (!parsed.success) {
      filtered.push(rawReading);
      continue;
    }

    const dataClass = metricReadingDataClass(parsed.data);
    if (dataClass === "gps") {
      reviewFlags.push(
        gpsSummaryNotSupportedReviewFlag({
          itemType: "metricReading",
          itemIndex,
          field: `metricReadings[${itemIndex}]`
        })
      );
      continue;
    }

    if (consentedDataClasses.has(dataClass)) {
      filtered.push(rawReading);
      continue;
    }

    reviewFlags.push(
      notConsentedReviewFlag({
        itemType: "metricReading",
        itemIndex,
        field: `metricReadings[${itemIndex}]`,
        rule: "monitoring_data_not_consented",
        dataClass
      })
    );
  }

  return filtered;
}

function filterSeriesByConsent({
  rawSeries,
  consentedDataClasses,
  reviewFlags
}: {
  rawSeries: unknown[];
  consentedDataClasses: Set<CanonicalImportDataClass>;
  reviewFlags: CanonicalIngestionReviewFlag[];
}) {
  const filtered: unknown[] = [];
  for (const [itemIndex, rawSeriesItem] of rawSeries.entries()) {
    const parsed = CanonicalSeriesSchema.safeParse(rawSeriesItem);
    if (!parsed.success) {
      filtered.push(rawSeriesItem);
      continue;
    }

    const dataClass = seriesDataClass(parsed.data.type);
    if (consentedDataClasses.has(dataClass)) {
      filtered.push(rawSeriesItem);
      continue;
    }

    reviewFlags.push(
      notConsentedReviewFlag({
        itemType: "series",
        itemIndex,
        field: `series[${itemIndex}]`,
        rule: "monitoring_data_not_consented",
        dataClass
      })
    );
  }

  return filtered;
}

function parseActivityForConsent(activity: unknown): CanonicalActivity | null {
  const parsed = CanonicalActivitySchema.safeParse(activity);
  if (parsed.success) {
    return parsed.data;
  }

  const stripped = CanonicalActivitySchema.safeParse(
    stripUnknownActivityFields(activity)
  );
  return stripped.success ? stripped.data : null;
}

function metricReadingDataClass(
  reading: StoredMetricReadingInput
): CanonicalImportDataClass {
  const catalogSchema = owlMetricSchemaForImportKey(reading.metricKey);
  if (catalogSchema !== null) {
    return catalogSchema.dataClass;
  }

  const key = reading.metricKey.toLowerCase();
  const units = canonicalMetricValueUnits(reading.value);

  if (
    key.includes("heart") ||
    key === "hrv" ||
    units.includes("beatsperminute")
  ) {
    return "heartRate";
  }
  if (
    key.includes("gps") ||
    key.includes("location") ||
    key.includes("latitude") ||
    key.includes("longitude")
  ) {
    return "gps";
  }
  if (
    key.includes("body") ||
    key.includes("weight") ||
    key.includes("mass") ||
    key.includes("fat")
  ) {
    return "bodyComposition";
  }
  if (
    key.includes("sleep") ||
    key.includes("stress") ||
    key.includes("wellness") ||
    key.includes("recovery") ||
    key.includes("battery")
  ) {
    return "sleepWellness";
  }

  return "activities";
}

function seriesDataClass(type: string): CanonicalImportDataClass {
  switch (type) {
    case "heartRate":
      return "heartRate";
    case "location":
      return "gps";
    default:
      return "activities";
  }
}

function canonicalMetricValueUnits(value: StoredMetricReadingInput["value"]) {
  if (isCanonicalScalarValue(value)) {
    return [value.unit.toLowerCase()];
  }

  return Object.values(value).map((fieldValue) =>
    fieldValue.unit.toLowerCase()
  );
}

function notConsentedReviewFlag({
  itemType,
  itemIndex,
  field,
  rule,
  dataClass
}: {
  itemType: CanonicalIngestionReviewFlag["itemType"];
  itemIndex: number;
  field: string;
  rule: string;
  dataClass: CanonicalImportDataClass;
}): CanonicalIngestionReviewFlag {
  return {
    itemType,
    itemIndex,
    severity: "warning",
    field,
    rule,
    message: `Data class ${dataClass} is not enabled for this Integration import.`
  };
}

function gpsSummaryNotSupportedReviewFlag({
  itemType,
  itemIndex,
  field
}: {
  itemType: "activity" | "metricReading";
  itemIndex: number;
  field: string;
}): CanonicalIngestionReviewFlag {
  return {
    itemType,
    itemIndex,
    severity: "warning",
    field,
    rule: "gps_summary_not_supported",
    message: "GPS Monitoring Data imports as series, not Metric Readings."
  };
}

async function materializeActivity({
  activity,
  activityMaterializationStore,
  deviceId,
  externalActivity,
  importedAt,
  itemIndex,
  reviewFlags,
  userId
}: {
  activity: NormalizedCanonicalActivity;
  activityMaterializationStore: CanonicalActivityMaterializationStore;
  deviceId: string;
  externalActivity: StoredExternalActivity;
  importedAt?: Date;
  itemIndex: number;
  reviewFlags: CanonicalIngestionReviewFlag[];
  userId: string;
}): Promise<{
  workout: CanonicalMaterializedWorkout | null;
  activityLink: CanonicalActivityLink | null;
  activityLinkSuggestion: CanonicalActivityLinkSuggestion | null;
} | null> {
  const linking = await activityMaterializationStore.linkActivityByTimeOverlap({
    userId,
    deviceId,
    activity,
    externalActivity,
    importedAt
  });
  if (linking.kind === "linked") {
    return {
      workout: null,
      activityLink: linking.activityLink,
      activityLinkSuggestion: null
    };
  }
  if (linking.kind === "suggested") {
    return {
      workout: null,
      activityLink: null,
      activityLinkSuggestion: linking.suggestion
    };
  }

  if (isMaterializableStrengthActivity(activity)) {
    const prepared = prepareStrengthMaterializationSets(activity, itemIndex);
    reviewFlags.push(...prepared.reviewFlags);
    if (prepared.sets.length === 0) {
      return null;
    }

    const materialized = await activityMaterializationStore.materializeStrengthActivity({
      userId,
      deviceId,
      activity,
      externalActivity,
      sets: prepared.sets,
      importedAt
    });
    return materialized === null
      ? null
      : {
          workout: materialized.workout,
          activityLink: materialized.activityLink,
          activityLinkSuggestion: null
        };
  }

  if (isMaterializableCardioActivity(activity)) {
    const prepared = prepareCardioMaterializationSet(activity, itemIndex);
    reviewFlags.push(...prepared.reviewFlags);
    if (prepared.set === null) {
      return null;
    }

    const materialized = await activityMaterializationStore.materializeCardioActivity({
      userId,
      deviceId,
      activity,
      externalActivity,
      set: prepared.set,
      importedAt
    });
    return materialized === null
      ? null
      : {
          workout: materialized.workout,
          activityLink: materialized.activityLink,
          activityLinkSuggestion: null
        };
  }

  return null;
}

function isMaterializableStrengthActivity(activity: NormalizedCanonicalActivity) {
  const platformExercise = platformExerciseFor(activity);
  return (
    platformExercise !== null &&
    platformExercise.dimensions.includes("load") &&
    platformExercise.dimensions.includes("reps") &&
    activity.sets !== undefined &&
    activity.sets.length > 0
  );
}

function isMaterializableCardioActivity(activity: NormalizedCanonicalActivity) {
  return (
    activity.mappedExerciseId !== null &&
    activity.summary.distance !== undefined &&
    activity.summary.duration !== undefined &&
    (activity.sets === undefined || activity.sets.length === 0)
  );
}

function prepareStrengthMaterializationSets(
  activity: NormalizedCanonicalActivity,
  itemIndex: number
): {
  sets: CanonicalMaterializationSet[];
  reviewFlags: CanonicalIngestionReviewFlag[];
} {
  const platformExercise = platformExerciseFor(activity);
  if (platformExercise === null || activity.sets === undefined) {
    return { sets: [], reviewFlags: [] };
  }

  const sets: CanonicalMaterializationSet[] = [];
  const reviewFlags: CanonicalIngestionReviewFlag[] = [];
  for (const [setIndex, set] of activity.sets.entries()) {
    const values = strengthSetValues(set);
    if (values === null) {
      reviewFlags.push({
        itemType: "activity",
        itemIndex,
        severity: "error",
        field: `activities[${itemIndex}].sets[${setIndex}].dimensions`,
        rule: "fit_strength_set_missing_load_or_reps",
        message:
          "FIT strength sets require both load and reps dimensions to materialize."
      });
      continue;
    }

    const validation = validateAgentSet({
      exercise: {
        dimensions: [...platformExercise.dimensions],
        loadMode: platformExercise.loadMode
      },
      values
    });
    reviewFlags.push(
      ...validation.warnings.map((warning) =>
        validationIssueToReviewFlag({ issue: warning, itemIndex, setIndex, severity: "warning" })
      ),
      ...validation.errors.map((error) =>
        validationIssueToReviewFlag({ issue: error, itemIndex, setIndex, severity: "error" })
      )
    );
    if (validation.errors.length > 0) {
      continue;
    }

    sets.push({
      source: set.source,
      externalId: set.externalId,
      timezone: set.timezone,
      performedAt: set.performedAt,
      values,
      warnings: validation.warnings
    });
  }

  return { sets, reviewFlags };
}

function prepareCardioMaterializationSet(
  activity: NormalizedCanonicalActivity,
  itemIndex: number
): {
  set: CanonicalMaterializationSet | null;
  reviewFlags: CanonicalIngestionReviewFlag[];
} {
  const platformExercise = platformExerciseFor(activity);
  const values = cardioSetValues(activity);
  if (platformExercise === null || values === null) {
    return { set: null, reviewFlags: [] };
  }

  const validation = validateAgentSet({
    exercise: {
      dimensions: [...platformExercise.dimensions],
      loadMode: platformExercise.loadMode
    },
    values
  });
  const reviewFlags = [
    ...validation.warnings.map((warning) =>
      validationIssueToReviewFlag({ issue: warning, itemIndex, setIndex: 0, severity: "warning" })
    ),
    ...validation.errors.map((error) =>
      validationIssueToReviewFlag({ issue: error, itemIndex, setIndex: 0, severity: "error" })
    )
  ];
  if (validation.errors.length > 0) {
    return { set: null, reviewFlags };
  }

  return {
    set: {
      source: activity.source,
      externalId: activity.externalId,
      timezone: activity.timezone,
      values,
      warnings: validation.warnings
    },
    reviewFlags
  };
}

function strengthSetValues(
  set: NonNullable<CanonicalActivity["sets"]>[number]
): AgentSetValidationInput["values"] | null {
  const { load, reps } = set.dimensions;
  if (load === undefined || reps === undefined) {
    return null;
  }

  return {
    load: {
      entered: load.value.toString(),
      unit: load.unit
    },
    reps: {
      entered: reps.value.toString(),
      unit: "repetition"
    }
  };
}

function cardioSetValues(
  activity: NormalizedCanonicalActivity
): AgentSetValidationInput["values"] | null {
  const distance = cardioDistanceValue(activity.summary.distance);
  const duration = activity.summary.duration;
  if (distance === null || duration === undefined) {
    return null;
  }

  return {
    distance,
    duration: {
      entered: duration.value.toString(),
      unit: "second"
    }
  };
}

function cardioDistanceValue(
  distance: CanonicalActivity["summary"]["distance"]
) {
  if (distance === undefined) {
    return null;
  }
  if (distance.unit === "meter") {
    return {
      entered: (distance.value / 1000).toString(),
      unit: "kilometer" as const
    };
  }

  return {
    entered: distance.value.toString(),
    unit: distance.unit
  };
}

function platformExerciseFor(activity: NormalizedCanonicalActivity) {
  return activity.mappedExerciseId === null
    ? null
    : CANONICAL_ACTIVITY_PLATFORM_EXERCISES[activity.mappedExerciseId];
}

function validationIssueToReviewFlag({
  issue,
  itemIndex,
  setIndex,
  severity
}: {
  issue: AgentSetValidationIssue;
  itemIndex: number;
  setIndex: number;
  severity: CanonicalIngestionReviewFlag["severity"];
}): CanonicalIngestionReviewFlag {
  return {
    itemType: "activity",
    itemIndex,
    severity,
    field: validationIssueFieldToCanonicalField(issue.field, itemIndex, setIndex),
    rule: issue.rule,
    message: issue.message
  };
}

function validationIssueFieldToCanonicalField(
  field: string,
  itemIndex: number,
  setIndex: number
) {
  const dimensionField = /^values\.(load|reps|duration|distance)\.(entered|unit)$/.exec(
    field
  );
  if (dimensionField !== null) {
    const [, dimension, leaf] = dimensionField;
    return `activities[${itemIndex}].sets[${setIndex}].dimensions.${dimension}.${
      leaf === "entered" ? "value" : "unit"
    }`;
  }

  if (field === "values" || field.startsWith("values.")) {
    return `activities[${itemIndex}].sets[${setIndex}].dimensions`;
  }

  return `activities[${itemIndex}].sets[${setIndex}].${field}`;
}

function normalizeCanonicalActivity(rawActivity: unknown, itemIndex: number) {
  const strictParse = CanonicalActivitySchema.safeParse(rawActivity);
  if (strictParse.success) {
    const reviewFlags = validateCanonicalActivity(
      strictParse.data,
      itemIndex
    );
    const activity = normalizeCanonicalActivityExerciseMapping(strictParse.data);

    return {
      activity,
      source: activity.source,
      externalId: activity.externalId,
      reviewFlags
    };
  }

  const shapeFlags = zodIssuesToReviewFlags({
    itemType: "activity",
    itemIndex,
    rule: "canonical_activity_shape",
    severity: "warning",
    issues: strictParse.error.issues
  });
  const strippedParse = CanonicalActivitySchema.safeParse(
    stripUnknownActivityFields(rawActivity)
  );

  if (strippedParse.success) {
    const reviewFlags = [
      ...shapeFlags,
      ...validateCanonicalActivity(strippedParse.data, itemIndex)
    ];
    const activity = normalizeCanonicalActivityExerciseMapping(
      strippedParse.data
    );

    return {
      activity,
      source: activity.source,
      externalId: activity.externalId,
      reviewFlags
    };
  }

  const reviewFlags = [
    ...shapeFlags,
    ...zodIssuesToReviewFlags({
      itemType: "activity",
      itemIndex,
      rule: "canonical_activity_unstored",
      severity: "error",
      issues: strippedParse.error.issues
    })
  ];

  return {
    activity: null,
    source: readStringField(rawActivity, "source"),
    externalId: readStringField(rawActivity, "externalId"),
    reviewFlags
  };
}

function validateCanonicalActivity(
  activity: CanonicalActivity,
  itemIndex: number
): CanonicalIngestionReviewFlag[] {
  const reviewFlags: CanonicalIngestionReviewFlag[] = [];
  const startedAt = Date.parse(activity.startedAt);
  const endedAt = Date.parse(activity.endedAt);

  if (
    Number.isFinite(startedAt) &&
    Number.isFinite(endedAt) &&
    endedAt < startedAt
  ) {
    reviewFlags.push({
      itemType: "activity",
      itemIndex,
      severity: "warning",
      field: `activities[${itemIndex}].endedAt`,
      rule: "activity_window_reversed",
      message:
        "External Activity end time is before its start time; raw observation was kept for review."
    });
  }

  return reviewFlags;
}

function normalizeItems<T extends z.ZodType>({
  itemType,
  rawItems,
  schema,
  reviewFlags
}: {
  itemType: CanonicalIngestionReviewFlag["itemType"];
  rawItems: unknown[];
  schema: T;
  reviewFlags: CanonicalIngestionReviewFlag[];
}): z.infer<T>[] {
  const normalized: z.infer<T>[] = [];

  for (const [itemIndex, rawItem] of rawItems.entries()) {
    const parsed = schema.safeParse(rawItem);
    if (parsed.success) {
      normalized.push(parsed.data);
      continue;
    }

    reviewFlags.push(
      ...zodIssuesToReviewFlags({
        itemType,
        itemIndex,
        rule: `canonical_${itemTypeRuleName(itemType)}_shape`,
        severity: "warning",
        issues: parsed.error.issues
      })
    );
  }

  return normalized;
}

function zodIssuesToReviewFlags({
  itemType,
  itemIndex,
  rule,
  severity,
  issues
}: {
  itemType: CanonicalIngestionReviewFlag["itemType"];
  itemIndex: number;
  rule: string;
  severity: CanonicalIngestionReviewFlag["severity"];
  issues: z.core.$ZodIssue[];
}): CanonicalIngestionReviewFlag[] {
  return issues.map((issue) => ({
    itemType,
    itemIndex,
    severity,
    field: formatIssuePath(
      `${itemTypeBasePath(itemType)}[${itemIndex}]`,
      issue.path
    ),
    rule,
    message: issue.message
  }));
}

function stripUnknownActivityFields(rawActivity: unknown) {
  if (!isRecord(rawActivity)) {
    return rawActivity;
  }

  const allowedKeys = [
    "source",
    "externalId",
    "startedAt",
    "endedAt",
    "timezone",
    "activityType",
    "summary",
    "summaryMetrics",
    "sets"
  ];
  const stripped: Record<string, unknown> = {};

  for (const key of allowedKeys) {
    if (Object.hasOwn(rawActivity, key)) {
      stripped[key] = rawActivity[key];
    }
  }

  return stripped;
}

function readStringField(rawValue: unknown, field: string) {
  if (!isRecord(rawValue)) {
    return null;
  }

  const value = rawValue[field];
  return typeof value === "string" ? value : null;
}

function formatIssuePath(
  basePath: string,
  path: ReadonlyArray<string | number | symbol>
): string {
  let field = basePath;

  for (const segment of path) {
    if (typeof segment === "number") {
      field = `${field}[${segment}]`;
      continue;
    }

    field = `${field}.${String(segment)}`;
  }

  return field;
}

function itemTypeBasePath(itemType: CanonicalIngestionReviewFlag["itemType"]) {
  switch (itemType) {
    case "activity":
      return "activities";
    case "series":
      return "series";
    case "metricReading":
      return "metricReadings";
  }
}

function itemTypeRuleName(itemType: CanonicalIngestionReviewFlag["itemType"]) {
  switch (itemType) {
    case "activity":
      return "activity";
    case "series":
      return "series";
    case "metricReading":
      return "metric_reading";
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isCanonicalScalarValue(
  value: StoredMetricReadingInput["value"]
): value is { value: number; unit: string } {
  return (
    typeof value === "object" &&
    value !== null &&
    "value" in value &&
    "unit" in value &&
    typeof value.value === "number" &&
    typeof value.unit === "string"
  );
}
