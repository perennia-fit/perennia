export type DimensionId = "load" | "reps" | "duration" | "distance";

export type TrainingUnit =
  | "kilogram"
  | "pound"
  | "repetition"
  | "second"
  | "kilometer"
  | "mile";

export type ExerciseLoadMode = "added" | "assisted";

export type RecordProfile =
  | "repMax"
  | "maxLoad"
  | "maxReps"
  | "maxDuration"
  | "minDuration"
  | "maxDistance"
  | "fastestPace"
  | "minAssistancePerRepCount"
  | "completionStreak";

export type SetDimensionValue = {
  entered: string;
  unit: TrainingUnit;
};

export type LoggedSetValues = Partial<Record<DimensionId, SetDimensionValue>>;

export type AnalyticsSet = {
  id: string;
  performedAt: Date;
  sequence: number;
  values: LoggedSetValues;
};

export type ExerciseAnalyticsProfile = {
  type: readonly DimensionId[];
  loadMode: ExerciseLoadMode;
  recordProfile: RecordProfile;
};

export type AnalyticsRecord = {
  profile: RecordProfile;
  setId: string;
  achievedAt: Date;
  sequence: number;
  value: number;
  unit: TrainingUnit;
  reps?: number;
};

export type AnalyticsPoint = {
  setId: string;
  achievedAt: Date;
  value: number;
  unit: TrainingUnit;
};

export type DerivedSeries = {
  isDefined: boolean;
  points: readonly AnalyticsPoint[];
  total: number | null;
};

export type RecordCatalog = {
  repMaxRecords: readonly AnalyticsRecord[];
  minAssistanceRecords: readonly AnalyticsRecord[];
  maxLoad: AnalyticsRecord | null;
  maxReps: AnalyticsRecord | null;
  maxDuration: AnalyticsRecord | null;
  minDuration: AnalyticsRecord | null;
  maxDistance: AnalyticsRecord | null;
  fastestPace: AnalyticsRecord | null;
};

export type ExerciseAnalyticsResult = {
  profile: ExerciseAnalyticsProfile;
  recordCatalog: RecordCatalog;
  headlineRecords: readonly AnalyticsRecord[];
  headlineRecord: AnalyticsRecord | null;
  estimatedOneRepMax: DerivedSeries;
  volume: DerivedSeries;
};

export class ExerciseAnalyticsEngine {
  compute({
    profile,
    sets
  }: {
    profile: ExerciseAnalyticsProfile;
    sets: Iterable<AnalyticsSet>;
  }): ExerciseAnalyticsResult {
    const orderedSets = [...sets].sort(compareSets);
    const recordCatalog: RecordCatalog = {
      repMaxRecords: repMaxRecords(profile, orderedSets),
      minAssistanceRecords: minAssistanceRecords(profile, orderedSets),
      maxLoad: bestScalarRecord(
        profile,
        orderedSets,
        "maxLoad",
        "load",
        "kilogram",
        false
      ),
      maxReps: bestScalarRecord(
        profile,
        orderedSets,
        "maxReps",
        "reps",
        "repetition",
        false
      ),
      maxDuration: bestScalarRecord(
        profile,
        orderedSets,
        "maxDuration",
        "duration",
        "second",
        false
      ),
      minDuration: bestScalarRecord(
        profile,
        orderedSets,
        "minDuration",
        "duration",
        "second",
        true
      ),
      maxDistance: bestScalarRecord(
        profile,
        orderedSets,
        "maxDistance",
        "distance",
        "kilometer",
        false
      ),
      fastestPace: fastestPaceRecord(profile, orderedSets)
    };
    const headlineRecords = recordsFor(recordCatalog, profile.recordProfile);
    const e1rm =
      profile.loadMode === "assisted"
        ? undefinedSeries()
        : definedSeries(estimatedOneRepMaxSeries(orderedSets));
    const volume =
      profile.loadMode === "assisted"
        ? undefinedSeries()
        : definedSeries(volumeSeries(profile, orderedSets));

    return {
      profile,
      recordCatalog,
      headlineRecords,
      headlineRecord: headlineRecord(profile, headlineRecords),
      estimatedOneRepMax: e1rm,
      volume
    };
  }
}

function repMaxRecords(
  profile: ExerciseAnalyticsProfile,
  sets: readonly AnalyticsSet[]
): AnalyticsRecord[] {
  if (
    profile.loadMode === "assisted" ||
    !hasDimension(profile, "load") ||
    !hasDimension(profile, "reps")
  ) {
    return [];
  }

  const bestByReps = new Map<number, AnalyticsRecord>();
  for (const set of sets) {
    const load = metricValue(set.values.load, "load", "kilogram");
    const reps = integerReps(set.values.reps);
    if (load === null || reps === null) {
      continue;
    }

    const candidate: AnalyticsRecord = {
      profile: "repMax",
      setId: set.id,
      achievedAt: set.performedAt,
      sequence: set.sequence,
      value: load,
      unit: "kilogram",
      reps
    };
    const current = bestByReps.get(reps);
    if (current === undefined || isBetter(candidate, current)) {
      bestByReps.set(reps, candidate);
    }
  }

  return [...bestByReps.values()]
    .filter((record) => {
      return ![...bestByReps.values()].some((other) => {
        return (
          other.reps !== undefined &&
          record.reps !== undefined &&
          other.reps > record.reps &&
          other.value >= record.value
        );
      });
    })
    .sort((left, right) => (left.reps ?? 0) - (right.reps ?? 0));
}

function minAssistanceRecords(
  profile: ExerciseAnalyticsProfile,
  sets: readonly AnalyticsSet[]
): AnalyticsRecord[] {
  if (profile.loadMode !== "assisted" || !hasDimension(profile, "load")) {
    return [];
  }

  const bestByReps = new Map<number, AnalyticsRecord>();
  for (const set of sets) {
    const assistance = metricValue(set.values.load, "load", "kilogram");
    const reps = integerReps(set.values.reps);
    if (assistance === null || reps === null) {
      continue;
    }

    const candidate: AnalyticsRecord = {
      profile: "minAssistancePerRepCount",
      setId: set.id,
      achievedAt: set.performedAt,
      sequence: set.sequence,
      value: assistance,
      unit: "kilogram",
      reps
    };
    const current = bestByReps.get(reps);
    if (current === undefined || isBetter(candidate, current, true)) {
      bestByReps.set(reps, candidate);
    }
  }

  return [...bestByReps.values()].sort(
    (left, right) => (left.reps ?? 0) - (right.reps ?? 0)
  );
}

function bestScalarRecord(
  profile: ExerciseAnalyticsProfile,
  sets: readonly AnalyticsSet[],
  recordProfile: RecordProfile,
  dimension: DimensionId,
  unit: TrainingUnit,
  prefersLower: boolean
): AnalyticsRecord | null {
  if (!hasDimension(profile, dimension)) {
    return null;
  }

  let best: AnalyticsRecord | null = null;
  for (const set of sets) {
    const value = metricValue(set.values[dimension], dimension, unit);
    if (value === null) {
      continue;
    }

    const candidate: AnalyticsRecord = {
      profile: recordProfile,
      setId: set.id,
      achievedAt: set.performedAt,
      sequence: set.sequence,
      value,
      unit
    };
    if (best === null || isBetter(candidate, best, prefersLower)) {
      best = candidate;
    }
  }

  return best;
}

function fastestPaceRecord(
  profile: ExerciseAnalyticsProfile,
  sets: readonly AnalyticsSet[]
): AnalyticsRecord | null {
  if (!hasDimension(profile, "distance") || !hasDimension(profile, "duration")) {
    return null;
  }

  let best: AnalyticsRecord | null = null;
  for (const set of sets) {
    const distance = metricValue(set.values.distance, "distance", "kilometer");
    const duration = metricValue(set.values.duration, "duration", "second");
    if (distance === null || duration === null || distance <= 0) {
      continue;
    }

    const candidate: AnalyticsRecord = {
      profile: "fastestPace",
      setId: set.id,
      achievedAt: set.performedAt,
      sequence: set.sequence,
      value: duration / distance,
      unit: "second"
    };
    if (best === null || isBetter(candidate, best, true)) {
      best = candidate;
    }
  }

  return best;
}

function estimatedOneRepMaxSeries(
  sets: readonly AnalyticsSet[]
): AnalyticsPoint[] {
  const points: AnalyticsPoint[] = [];
  for (const set of sets) {
    const load = metricValue(set.values.load, "load", "kilogram");
    const reps = integerReps(set.values.reps);
    if (load === null || reps === null || reps < 1 || reps > 10) {
      continue;
    }

    points.push({
      setId: set.id,
      achievedAt: set.performedAt,
      value: (load * 36) / (37 - reps),
      unit: "kilogram"
    });
  }

  return points;
}

function volumeSeries(
  profile: ExerciseAnalyticsProfile,
  sets: readonly AnalyticsSet[]
): AnalyticsPoint[] {
  const points: AnalyticsPoint[] = [];
  for (const set of sets) {
    const load = metricValue(set.values.load, "load", "kilogram");
    const reps = metricValue(set.values.reps, "reps", "repetition");
    if (hasDimension(profile, "load") && hasDimension(profile, "reps")) {
      if (load === null || reps === null) {
        continue;
      }

      points.push({
        setId: set.id,
        achievedAt: set.performedAt,
        value: load * reps,
        unit: "kilogram"
      });
      continue;
    }

    if (hasDimension(profile, "distance")) {
      const distance = metricValue(set.values.distance, "distance", "kilometer");
      if (distance === null) {
        continue;
      }

      points.push({
        setId: set.id,
        achievedAt: set.performedAt,
        value: distance,
        unit: "kilometer"
      });
      continue;
    }

    if (hasDimension(profile, "duration")) {
      const duration = metricValue(set.values.duration, "duration", "second");
      if (duration === null) {
        continue;
      }

      points.push({
        setId: set.id,
        achievedAt: set.performedAt,
        value: duration,
        unit: "second"
      });
    }
  }

  return points;
}

function recordsFor(
  catalog: RecordCatalog,
  profile: RecordProfile
): readonly AnalyticsRecord[] {
  switch (profile) {
    case "repMax":
      return catalog.repMaxRecords;
    case "minAssistancePerRepCount":
      return catalog.minAssistanceRecords;
    case "maxLoad":
      return nullableRecord(catalog.maxLoad);
    case "maxReps":
      return nullableRecord(catalog.maxReps);
    case "maxDuration":
      return nullableRecord(catalog.maxDuration);
    case "minDuration":
      return nullableRecord(catalog.minDuration);
    case "maxDistance":
      return nullableRecord(catalog.maxDistance);
    case "fastestPace":
      return nullableRecord(catalog.fastestPace);
    case "completionStreak":
      return [];
  }
}

function headlineRecord(
  profile: ExerciseAnalyticsProfile,
  records: readonly AnalyticsRecord[]
): AnalyticsRecord | null {
  if (records.length === 0) {
    return null;
  }

  const prefersLower =
    profile.recordProfile === "minAssistancePerRepCount" ||
    profile.recordProfile === "minDuration" ||
    profile.recordProfile === "fastestPace";

  return records.reduce((best, candidate) =>
    isBetter(candidate, best, prefersLower) ? candidate : best
  );
}

function nullableRecord(record: AnalyticsRecord | null): readonly AnalyticsRecord[] {
  return record === null ? [] : [record];
}

function definedSeries(points: readonly AnalyticsPoint[]): DerivedSeries {
  return {
    isDefined: true,
    points,
    total: points.reduce((sum, point) => sum + point.value, 0)
  };
}

function undefinedSeries(): DerivedSeries {
  return {
    isDefined: false,
    points: [],
    total: null
  };
}

function hasDimension(profile: ExerciseAnalyticsProfile, dimension: DimensionId) {
  return profile.type.includes(dimension);
}

function compareSets(left: AnalyticsSet, right: AnalyticsSet) {
  const timeComparison = left.performedAt.getTime() - right.performedAt.getTime();
  if (timeComparison !== 0) {
    return timeComparison;
  }

  const sequenceComparison = left.sequence - right.sequence;
  if (sequenceComparison !== 0) {
    return sequenceComparison;
  }

  return left.id.localeCompare(right.id);
}

function isBetter(
  candidate: AnalyticsRecord,
  current: AnalyticsRecord,
  prefersLower = false
) {
  if (candidate.value !== current.value) {
    return prefersLower
      ? candidate.value < current.value
      : candidate.value > current.value;
  }

  const timeComparison =
    candidate.achievedAt.getTime() - current.achievedAt.getTime();
  if (timeComparison !== 0) {
    return timeComparison < 0;
  }

  if (candidate.sequence !== current.sequence) {
    return candidate.sequence < current.sequence;
  }

  return candidate.setId.localeCompare(current.setId) < 0;
}

function metricValue(
  value: SetDimensionValue | undefined,
  dimension: DimensionId,
  targetUnit: TrainingUnit
): number | null {
  if (value === undefined) {
    return null;
  }

  const numericValue = Number.parseFloat(value.entered);
  if (!Number.isFinite(numericValue)) {
    return null;
  }

  switch (dimension) {
    case "load":
      return convertLoad(numericValue, value.unit, targetUnit);
    case "reps":
      return value.unit === "repetition" && targetUnit === "repetition"
        ? numericValue
        : null;
    case "duration":
      return value.unit === "second" && targetUnit === "second"
        ? numericValue
        : null;
    case "distance":
      return convertDistance(numericValue, value.unit, targetUnit);
  }
}

export function normalizedMetricValue(
  value: SetDimensionValue | undefined,
  dimension: DimensionId,
  targetUnit: TrainingUnit
): number | null {
  return metricValue(value, dimension, targetUnit);
}

function convertLoad(
  value: number,
  from: TrainingUnit,
  to: TrainingUnit
): number | null {
  const kilograms =
    from === "kilogram" ? value : from === "pound" ? value * 0.45359237 : null;
  if (kilograms === null) {
    return null;
  }

  return to === "kilogram"
    ? kilograms
    : to === "pound"
      ? kilograms / 0.45359237
      : null;
}

function convertDistance(
  value: number,
  from: TrainingUnit,
  to: TrainingUnit
): number | null {
  const kilometers =
    from === "kilometer" ? value : from === "mile" ? value * 1.609344 : null;
  if (kilometers === null) {
    return null;
  }

  return to === "kilometer"
    ? kilometers
    : to === "mile"
      ? kilometers / 1.609344
      : null;
}

function integerReps(value: SetDimensionValue | undefined): number | null {
  const reps = metricValue(value, "reps", "repetition");
  if (reps === null || reps <= 0 || Math.round(reps) !== reps) {
    return null;
  }

  return reps;
}
