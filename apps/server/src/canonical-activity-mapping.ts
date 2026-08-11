import {
  CanonicalActivitySchema,
  type CanonicalActivity
} from "./canonical-import.js";
import type {
  DimensionId,
  ExerciseLoadMode,
  RecordProfile
} from "./analytics/exercise-analytics.js";

export const CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS = {
  strengthTraining: "01910000-0000-7000-8000-000000000120",
  running: "01910000-0000-7000-8000-000000000109",
  roadRunning: "01910000-0000-7000-8000-000000000110",
  trailRunning: "01910000-0000-7000-8000-000000000111",
  treadmillRunning: "01910000-0000-7000-8000-000000000112",
  trackRunning: "01910000-0000-7000-8000-000000000113",
  cycling: "01910000-0000-7000-8000-000000000114",
  indoorCycling: "01910000-0000-7000-8000-000000000115",
  outdoorCycling: "01910000-0000-7000-8000-000000000116",
  swimming: "01910000-0000-7000-8000-000000000117",
  poolSwim: "01910000-0000-7000-8000-000000000118",
  openWaterSwim: "01910000-0000-7000-8000-000000000119"
} as const;

export const CANONICAL_ACTIVITY_PLATFORM_CATEGORY_IDS = {
  strength: "01910000-0000-7000-8000-000000000001",
  running: "01910000-0000-7000-8000-000000000004",
  cycling: "01910000-0000-7000-8000-000000000005",
  swimming: "01910000-0000-7000-8000-000000000006"
} as const;

export type CanonicalActivityPlatformExerciseId =
  (typeof CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS)[keyof typeof CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS];

export type NormalizedCanonicalActivity = CanonicalActivity & {
  mappedExerciseId: CanonicalActivityPlatformExerciseId | null;
};

export type CanonicalActivityExerciseMapping = {
  platformExerciseId: CanonicalActivityPlatformExerciseId;
  family: "strength" | "running" | "cycling" | "swimming";
  fallback: boolean;
};

export type CanonicalActivityPlatformExercise = {
  id: CanonicalActivityPlatformExerciseId;
  name: string;
  categoryId: string;
  categoryName: string;
  dimensions: readonly DimensionId[];
  loadMode: ExerciseLoadMode;
  recordProfile: RecordProfile;
};

export const CANONICAL_ACTIVITY_PLATFORM_EXERCISES: Record<
  CanonicalActivityPlatformExerciseId,
  CanonicalActivityPlatformExercise
> = {
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.strengthTraining]: {
    id: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.strengthTraining,
    name: "Strength Training",
    categoryId: CANONICAL_ACTIVITY_PLATFORM_CATEGORY_IDS.strength,
    categoryName: "Strength",
    dimensions: ["load", "reps"],
    loadMode: "added",
    recordProfile: "repMax"
  },
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.running]: {
    id: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.running,
    name: "Running",
    categoryId: CANONICAL_ACTIVITY_PLATFORM_CATEGORY_IDS.running,
    categoryName: "Running",
    dimensions: ["distance", "duration"],
    loadMode: "added",
    recordProfile: "fastestPace"
  },
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.roadRunning]: {
    id: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.roadRunning,
    name: "Road Running",
    categoryId: CANONICAL_ACTIVITY_PLATFORM_CATEGORY_IDS.running,
    categoryName: "Running",
    dimensions: ["distance", "duration"],
    loadMode: "added",
    recordProfile: "fastestPace"
  },
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning]: {
    id: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning,
    name: "Trail Running",
    categoryId: CANONICAL_ACTIVITY_PLATFORM_CATEGORY_IDS.running,
    categoryName: "Running",
    dimensions: ["distance", "duration"],
    loadMode: "added",
    recordProfile: "fastestPace"
  },
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.treadmillRunning]: {
    id: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.treadmillRunning,
    name: "Treadmill Running",
    categoryId: CANONICAL_ACTIVITY_PLATFORM_CATEGORY_IDS.running,
    categoryName: "Running",
    dimensions: ["distance", "duration"],
    loadMode: "added",
    recordProfile: "fastestPace"
  },
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trackRunning]: {
    id: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trackRunning,
    name: "Track Running",
    categoryId: CANONICAL_ACTIVITY_PLATFORM_CATEGORY_IDS.running,
    categoryName: "Running",
    dimensions: ["distance", "duration"],
    loadMode: "added",
    recordProfile: "fastestPace"
  },
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.cycling]: {
    id: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.cycling,
    name: "Cycling",
    categoryId: CANONICAL_ACTIVITY_PLATFORM_CATEGORY_IDS.cycling,
    categoryName: "Cycling",
    dimensions: ["distance", "duration"],
    loadMode: "added",
    recordProfile: "fastestPace"
  },
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.indoorCycling]: {
    id: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.indoorCycling,
    name: "Indoor Cycling",
    categoryId: CANONICAL_ACTIVITY_PLATFORM_CATEGORY_IDS.cycling,
    categoryName: "Cycling",
    dimensions: ["distance", "duration"],
    loadMode: "added",
    recordProfile: "fastestPace"
  },
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.outdoorCycling]: {
    id: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.outdoorCycling,
    name: "Outdoor Cycling",
    categoryId: CANONICAL_ACTIVITY_PLATFORM_CATEGORY_IDS.cycling,
    categoryName: "Cycling",
    dimensions: ["distance", "duration"],
    loadMode: "added",
    recordProfile: "fastestPace"
  },
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.swimming]: {
    id: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.swimming,
    name: "Swimming",
    categoryId: CANONICAL_ACTIVITY_PLATFORM_CATEGORY_IDS.swimming,
    categoryName: "Swimming",
    dimensions: ["distance", "duration"],
    loadMode: "added",
    recordProfile: "fastestPace"
  },
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.poolSwim]: {
    id: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.poolSwim,
    name: "Pool Swim",
    categoryId: CANONICAL_ACTIVITY_PLATFORM_CATEGORY_IDS.swimming,
    categoryName: "Swimming",
    dimensions: ["distance", "duration"],
    loadMode: "added",
    recordProfile: "fastestPace"
  },
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.openWaterSwim]: {
    id: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.openWaterSwim,
    name: "Open-Water Swim",
    categoryId: CANONICAL_ACTIVITY_PLATFORM_CATEGORY_IDS.swimming,
    categoryName: "Swimming",
    dimensions: ["distance", "duration"],
    loadMode: "added",
    recordProfile: "fastestPace"
  }
};

const FAMILY_GENERIC_EXERCISE_IDS = {
  strength: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.strengthTraining,
  running: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.running,
  cycling: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.cycling,
  swimming: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.swimming
} as const;

const EXERCISE_ID_FAMILIES: Record<
  CanonicalActivityPlatformExerciseId,
  CanonicalActivityExerciseMapping["family"]
> = {
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.strengthTraining]: "strength",
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.running]: "running",
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.roadRunning]: "running",
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning]: "running",
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.treadmillRunning]: "running",
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trackRunning]: "running",
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.cycling]: "cycling",
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.indoorCycling]: "cycling",
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.outdoorCycling]: "cycling",
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.swimming]: "swimming",
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.poolSwim]: "swimming",
  [CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.openWaterSwim]: "swimming"
};

const KNOWN_VENDOR_ACTIVITY_TYPE_MAPPINGS = createVendorActivityTypeMappings([
  ["garmin", "strength_training", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.strengthTraining],
  ["garmin", "strength", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.strengthTraining],
  ["garmin", "running", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.running],
  ["garmin", "run", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.running],
  ["garmin", "road_running", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.roadRunning],
  ["garmin", "street_running", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.roadRunning],
  ["garmin", "trail_running", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning],
  ["garmin", "treadmill_running", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.treadmillRunning],
  ["garmin", "track_running", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trackRunning],
  ["garmin", "cycling", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.cycling],
  ["garmin", "road_biking", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.outdoorCycling],
  ["garmin", "indoor_cycling", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.indoorCycling],
  ["garmin", "lap_swimming", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.poolSwim],
  ["garmin", "pool_swimming", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.poolSwim],
  ["garmin", "open_water_swimming", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.openWaterSwim],
  ["coros", "run", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.running],
  ["coros", "road run", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.roadRunning],
  ["coros", "trail run", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning],
  ["coros", "treadmill", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.treadmillRunning],
  ["coros", "track run", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trackRunning],
  ["coros", "bike", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.cycling],
  ["coros", "indoor bike", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.indoorCycling],
  ["coros", "outdoor bike", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.outdoorCycling],
  ["coros", "pool swim", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.poolSwim],
  ["coros", "open water", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.openWaterSwim],
  ["strava", "Run", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.running],
  ["strava", "TrailRun", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning],
  ["strava", "VirtualRun", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.treadmillRunning],
  ["strava", "Ride", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.cycling],
  ["strava", "VirtualRide", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.indoorCycling],
  ["strava", "Swim", CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.swimming]
]);

export function normalizeCanonicalActivityExerciseMapping(
  activity: CanonicalActivity
): NormalizedCanonicalActivity {
  const mapping = resolveCanonicalActivityExerciseMapping({
    source: activity.source,
    activityType: activity.activityType
  });

  return {
    ...activity,
    mappedExerciseId: mapping?.platformExerciseId ?? null
  };
}

export function parseNormalizedCanonicalActivity(
  activity: CanonicalActivity | NormalizedCanonicalActivity
): NormalizedCanonicalActivity {
  const { mappedExerciseId, ...canonicalActivity } = activity as CanonicalActivity &
    Partial<NormalizedCanonicalActivity>;
  const parsed = CanonicalActivitySchema.parse(canonicalActivity);

  return {
    ...parsed,
    mappedExerciseId: parseMappedExerciseId(mappedExerciseId)
  };
}

export function resolveCanonicalActivityExerciseMapping({
  source,
  activityType
}: {
  source: string;
  activityType: string;
}): CanonicalActivityExerciseMapping | null {
  const sourceKey = normalizeLookupKey(source);
  const activityTypeKey = normalizeLookupKey(activityType);
  const knownExerciseId = KNOWN_VENDOR_ACTIVITY_TYPE_MAPPINGS.get(
    `${sourceKey}:${activityTypeKey}`
  );

  if (knownExerciseId !== undefined) {
    return {
      platformExerciseId: knownExerciseId,
      family: EXERCISE_ID_FAMILIES[knownExerciseId],
      fallback: false
    };
  }

  const family = inferActivityTypeFamily(activityType);
  if (family === null) {
    return null;
  }

  return {
    platformExerciseId: FAMILY_GENERIC_EXERCISE_IDS[family],
    family,
    fallback: true
  };
}

function createVendorActivityTypeMappings(
  entries: readonly (readonly [
    source: string,
    activityType: string,
    platformExerciseId: CanonicalActivityPlatformExerciseId
  ])[]
) {
  return new Map(
    entries.map(([source, activityType, platformExerciseId]) => [
      `${normalizeLookupKey(source)}:${normalizeLookupKey(activityType)}`,
      platformExerciseId
    ])
  );
}

function parseMappedExerciseId(value: unknown) {
  if (typeof value !== "string") {
    return null;
  }

  return isCanonicalActivityPlatformExerciseId(value) ? value : null;
}

function isCanonicalActivityPlatformExerciseId(
  value: string
): value is CanonicalActivityPlatformExerciseId {
  return (
    Object.values(CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS) as string[]
  ).includes(value);
}

function inferActivityTypeFamily(
  activityType: string
): CanonicalActivityExerciseMapping["family"] | null {
  const key = normalizeLookupKey(activityType);

  if (key.includes("run") || key.includes("jog")) {
    return "running";
  }
  if (
    key.includes("cycl") ||
    key.includes("bike") ||
    key.includes("biking") ||
    key.includes("ride")
  ) {
    return "cycling";
  }
  if (key.includes("swim")) {
    return "swimming";
  }
  if (
    key.includes("strength") ||
    key.includes("weighttraining") ||
    key.includes("resistance")
  ) {
    return "strength";
  }

  return null;
}

function normalizeLookupKey(value: string) {
  return value
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "");
}
