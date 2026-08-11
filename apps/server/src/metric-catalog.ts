import type { CanonicalImportDataClass } from "./canonical-import.js";

export type PerenniaMetricGroup = "monitoring" | "bodyComposition";
export type PerenniaMetricGoalType = "decrease" | "increase" | "target";

export type PerenniaMetricSchema = {
  canonicalKey: string;
  displayName: string;
  defaultUnit: string;
  valueShape: "scalar";
  metricGroup: PerenniaMetricGroup;
  dataClass: CanonicalImportDataClass;
  goalType: PerenniaMetricGoalType | null;
  enabledByDefault: boolean;
  pinnedByDefault: boolean;
  sortOrder: number;
  aliases?: readonly string[];
};

export const PRN_METRIC_SCHEMAS = [
  metricSchema({
    canonicalKey: "restingHeartRate",
    displayName: "Resting Heart Rate",
    defaultUnit: "beatsPerMinute",
    dataClass: "heartRate",
    sortOrder: 100,
    aliases: ["resting_hr", "rhr", "restingHeartRate"]
  }),
  metricSchema({
    canonicalKey: "averageHeartRate",
    displayName: "Average Heart Rate",
    defaultUnit: "beatsPerMinute",
    dataClass: "heartRate",
    sortOrder: 110,
    aliases: ["avg_hr", "average_hr", "heartRateAverage"]
  }),
  metricSchema({
    canonicalKey: "maxHeartRate",
    displayName: "Max Heart Rate",
    defaultUnit: "beatsPerMinute",
    dataClass: "heartRate",
    sortOrder: 120,
    aliases: ["max_hr", "maximumHeartRate"]
  }),
  metricSchema({
    canonicalKey: "hrv",
    displayName: "Heart Rate Variability",
    defaultUnit: "millisecond",
    dataClass: "heartRate",
    sortOrder: 130,
    aliases: ["lastNightHrv", "lastNightAverageHrv", "hrvLastNightAverage"]
  }),
  metricSchema({
    canonicalKey: "steps",
    displayName: "Steps",
    defaultUnit: "count",
    dataClass: "activities",
    sortOrder: 200,
    aliases: ["stepCount", "dailySteps"]
  }),
  metricSchema({
    canonicalKey: "activeKilocalories",
    displayName: "Active Calories",
    defaultUnit: "kilocalorie",
    dataClass: "activities",
    sortOrder: 210,
    aliases: ["activeCalories", "calories_active", "activityCalories"]
  }),
  metricSchema({
    canonicalKey: "totalKilocalories",
    displayName: "Total Calories",
    defaultUnit: "kilocalorie",
    dataClass: "activities",
    sortOrder: 220,
    aliases: ["totalCalories", "calories_total"]
  }),
  metricSchema({
    canonicalKey: "basalKilocalories",
    displayName: "Basal Calories",
    defaultUnit: "kilocalorie",
    dataClass: "activities",
    sortOrder: 230,
    aliases: ["bmrCalories", "calories_bmr", "basalCalories"]
  }),
  metricSchema({
    canonicalKey: "sleepDuration",
    displayName: "Sleep Duration",
    defaultUnit: "second",
    dataClass: "sleepWellness",
    sortOrder: 300,
    aliases: ["totalSleep", "sleep_total", "sleep_avg"]
  }),
  metricSchema({
    canonicalKey: "deepSleepDuration",
    displayName: "Deep Sleep",
    defaultUnit: "second",
    dataClass: "sleepWellness",
    sortOrder: 310,
    aliases: ["deepSleep", "deep_sleep"]
  }),
  metricSchema({
    canonicalKey: "lightSleepDuration",
    displayName: "Light Sleep",
    defaultUnit: "second",
    dataClass: "sleepWellness",
    sortOrder: 320,
    aliases: ["lightSleep", "light_sleep"]
  }),
  metricSchema({
    canonicalKey: "remSleepDuration",
    displayName: "REM Sleep",
    defaultUnit: "second",
    dataClass: "sleepWellness",
    sortOrder: 330,
    aliases: ["remSleep", "rem_sleep"]
  }),
  metricSchema({
    canonicalKey: "awakeDuration",
    displayName: "Awake Time",
    defaultUnit: "second",
    dataClass: "sleepWellness",
    sortOrder: 340,
    aliases: ["awake", "awake_sleep"]
  }),
  metricSchema({
    canonicalKey: "sleepScore",
    displayName: "Sleep Score",
    defaultUnit: "score",
    dataClass: "sleepWellness",
    sortOrder: 350,
    aliases: ["sleep_score", "sleepQualityScore"]
  }),
  metricSchema({
    canonicalKey: "stressAverage",
    displayName: "Average Stress",
    defaultUnit: "score",
    dataClass: "sleepWellness",
    sortOrder: 360,
    aliases: ["stress_avg", "avgStress"]
  }),
  metricSchema({
    canonicalKey: "bodyBatteryMinimum",
    displayName: "Body Battery Min",
    defaultUnit: "score",
    dataClass: "sleepWellness",
    sortOrder: 370,
    aliases: ["bb_min"]
  }),
  metricSchema({
    canonicalKey: "bodyBatteryMaximum",
    displayName: "Body Battery Max",
    defaultUnit: "score",
    dataClass: "sleepWellness",
    sortOrder: 380,
    aliases: ["bb_max"]
  }),
  metricSchema({
    canonicalKey: "averageCadence",
    displayName: "Average Cadence",
    defaultUnit: "stepsPerMinute",
    dataClass: "activities",
    sortOrder: 400,
    aliases: ["avg_cadence", "averageStepCadence"]
  }),
  metricSchema({
    canonicalKey: "maxCadence",
    displayName: "Max Cadence",
    defaultUnit: "stepsPerMinute",
    dataClass: "activities",
    sortOrder: 410,
    aliases: ["max_cadence"]
  }),
  metricSchema({
    canonicalKey: "averagePower",
    displayName: "Average Power",
    defaultUnit: "watt",
    dataClass: "activities",
    sortOrder: 420,
    aliases: ["avg_power"]
  }),
  {
    ...metricSchema({
      canonicalKey: "bodyWeight",
      displayName: "Body Weight",
      defaultUnit: "kilogram",
      dataClass: "bodyComposition",
      sortOrder: 500,
      aliases: ["bodyMass", "weight"]
    }),
    metricGroup: "bodyComposition",
    goalType: "decrease",
    enabledByDefault: false,
    pinnedByDefault: false
  },
  {
    ...metricSchema({
      canonicalKey: "bodyFat",
      displayName: "Body Fat",
      defaultUnit: "percent",
      dataClass: "bodyComposition",
      sortOrder: 510,
      aliases: ["bodyFatPercentage", "bodyFatPercent"]
    }),
    metricGroup: "bodyComposition",
    goalType: "decrease",
    enabledByDefault: false,
    pinnedByDefault: false
  }
] as const satisfies readonly PerenniaMetricSchema[];

const metricSchemasByLookupKey = new Map<string, PerenniaMetricSchema>(
  PRN_METRIC_SCHEMAS.flatMap((schema) =>
    [schema.canonicalKey, ...(schema.aliases ?? [])].map((key) => [
      normalizeMetricLookupKey(key),
      schema
    ])
  )
);

export function owlMetricSchemaForImportKey(
  metricKey: string
): PerenniaMetricSchema | null {
  return metricSchemasByLookupKey.get(normalizeMetricLookupKey(metricKey)) ?? null;
}

export function normalizeMetricLookupKey(value: string) {
  return value.replace(/[^a-z0-9]/gi, "").toLowerCase();
}

function metricSchema({
  canonicalKey,
  displayName,
  defaultUnit,
  dataClass,
  sortOrder,
  aliases = []
}: {
  canonicalKey: string;
  displayName: string;
  defaultUnit: string;
  dataClass: CanonicalImportDataClass;
  sortOrder: number;
  aliases?: readonly string[];
}): PerenniaMetricSchema {
  return {
    canonicalKey,
    displayName,
    defaultUnit,
    valueShape: "scalar",
    metricGroup: "monitoring",
    dataClass,
    goalType: null,
    enabledByDefault: true,
    pinnedByDefault: false,
    sortOrder,
    aliases
  };
}
