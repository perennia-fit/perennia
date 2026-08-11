/**
 * Server-side nutrition analytics — the derived totals/trends/goal-progress
 * machinery the agent read surface exposes. It is a faithful TS mirror
 * of the device-canonical Dart aggregation in
 * apps/mobile/lib/domain/nutrition/nutrition.dart so an agent and the phone see
 * identical numbers for the same range.
 *
 * Everything here is computed on demand from self-describing `Food Entry`
 * snapshots + `Portion`s. No nutrition total is ever stored or synced,
 * and an *unknown* `Nutrient` propagates an incompleteness flag — it
 * is never coerced to zero (NUTRITION.md §4; `0 ≠ unknown`).
 */

export type NutrientUnit =
  | "kilocalorie"
  | "gram"
  | "milligram"
  | "microgram"
  | "milliliter";

/** The fixed nutrient registry, storage key + default unit (nutrition.dart). */
export const NUTRIENT_REGISTRY = [
  { id: "energy", unit: "kilocalorie" },
  { id: "protein", unit: "gram" },
  { id: "carbohydrate", unit: "gram" },
  { id: "sugar", unit: "gram" },
  { id: "fat", unit: "gram" },
  { id: "saturated_fat", unit: "gram" },
  { id: "monounsaturated_fat", unit: "gram" },
  { id: "polyunsaturated_fat", unit: "gram" },
  { id: "fiber", unit: "gram" },
  { id: "sodium", unit: "milligram" },
  { id: "cholesterol", unit: "milligram" },
  { id: "vitamin_a", unit: "microgram" },
  { id: "vitamin_c", unit: "milligram" },
  { id: "vitamin_d", unit: "microgram" },
  { id: "vitamin_e", unit: "milligram" },
  { id: "vitamin_k", unit: "microgram" },
  { id: "thiamin", unit: "milligram" },
  { id: "riboflavin", unit: "milligram" },
  { id: "niacin", unit: "milligram" },
  { id: "vitamin_b6", unit: "milligram" },
  { id: "folate", unit: "microgram" },
  { id: "vitamin_b12", unit: "microgram" },
  { id: "calcium", unit: "milligram" },
  { id: "iron", unit: "milligram" },
  { id: "magnesium", unit: "milligram" },
  { id: "phosphorus", unit: "milligram" },
  { id: "potassium", unit: "milligram" },
  { id: "zinc", unit: "milligram" },
  { id: "copper", unit: "milligram" },
  { id: "manganese", unit: "milligram" },
  { id: "selenium", unit: "microgram" },
  { id: "caffeine", unit: "milligram" },
  { id: "water", unit: "milliliter" }
] as const;

export type NutrientId = (typeof NUTRIENT_REGISTRY)[number]["id"];

export const NUTRIENT_IDS: readonly NutrientId[] = NUTRIENT_REGISTRY.map(
  (nutrient) => nutrient.id
);

const NUTRIENT_UNIT_BY_ID = new Map<NutrientId, NutrientUnit>(
  NUTRIENT_REGISTRY.map((nutrient) => [nutrient.id, nutrient.unit])
);

/** The goalable `Nutrient`s in v1: energy + the three macros (NUTRITION.md §4). */
export const GOALABLE_NUTRIENT_IDS: readonly NutrientId[] = [
  "energy",
  "protein",
  "carbohydrate",
  "fat"
];

/** The "core" tier — energy + macros — always present in a totals summary. */
export const CORE_NUTRIENT_IDS: readonly NutrientId[] = [
  "energy",
  "protein",
  "carbohydrate",
  "fat"
];

/** The "common" micro/macro tier surfaced alongside the core totals. */
export const COMMON_NUTRIENT_IDS: readonly NutrientId[] = [
  "saturated_fat",
  "sugar",
  "fiber",
  "sodium"
];

export function nutrientDefaultUnit(id: NutrientId): NutrientUnit {
  const unit = NUTRIENT_UNIT_BY_ID.get(id);
  if (unit === undefined) {
    throw new Error(`Unknown nutrient id: ${id}`);
  }

  return unit;
}

export type NutrientAmount =
  | { status: "complete"; value: number; unit: NutrientUnit }
  | { status: "unknown"; unit: NutrientUnit };

/** A self-describing Food Entry as the analytics layer consumes it. */
export type AnalyticsFoodEntry = {
  /** "food" scales the per-100 vector by the resolved Portion; "quickEntry" is whole. */
  kind: "food" | "quickEntry";
  nutrients: Partial<Record<NutrientId, NutrientAmount>>;
  /** Resolved logged amount in g/ml for a reference Food; undefined for a Quick Entry. */
  resolvedBaseQuantity?: number;
};

export type AnalyticsMeal = {
  id: string;
  mealType: string;
  startedAt: Date;
  entries: readonly AnalyticsFoodEntry[];
};

export type AnalyticsNutritionDay = {
  localDate: string;
  meals: readonly AnalyticsMeal[];
};

export type NutrientTotal = {
  id: NutrientId;
  value: number;
  unit: NutrientUnit;
  isComplete: boolean;
};

/**
 * Resolve a Food Entry's nutrient vector to its contribution to a total. A Quick
 * Entry's vector already describes the whole entry; a reference Food's per-100
 * vector is scaled by `resolvedBaseQuantity / 100` (same as the device). An
 * unknown component stays unknown after scaling — never coerced to zero.
 */
export function resolveEntryNutrient(
  entry: AnalyticsFoodEntry,
  id: NutrientId
): NutrientAmount {
  const unit = nutrientDefaultUnit(id);
  const amount = entry.nutrients[id];
  if (amount === undefined || amount.status === "unknown") {
    return { status: "unknown", unit };
  }

  if (entry.kind === "quickEntry") {
    return { status: "complete", value: amount.value, unit };
  }

  if (
    entry.resolvedBaseQuantity === undefined ||
    !Number.isFinite(entry.resolvedBaseQuantity)
  ) {
    throw new Error("Reference Food entry is missing a resolvable Portion.");
  }

  return {
    status: "complete",
    value: (amount.value * entry.resolvedBaseQuantity) / 100,
    unit
  };
}

/**
 * Sum a set of Food Entries into per-nutrient totals. A nutrient total is flagged
 * incomplete the moment any contributing entry lacked that nutrient — the
 * incompleteness propagates rather than being silently summed as "0 g".
 */
export function totalsFromEntries(
  entries: Iterable<AnalyticsFoodEntry>
): Map<NutrientId, NutrientTotal> {
  const values = new Map<NutrientId, number>();
  const complete = new Map<NutrientId, boolean>();
  for (const id of NUTRIENT_IDS) {
    values.set(id, 0);
    complete.set(id, true);
  }

  for (const entry of entries) {
    for (const id of NUTRIENT_IDS) {
      const amount = resolveEntryNutrient(entry, id);
      if (amount.status === "complete") {
        values.set(id, (values.get(id) ?? 0) + amount.value);
      } else {
        complete.set(id, false);
      }
    }
  }

  const totals = new Map<NutrientId, NutrientTotal>();
  for (const id of NUTRIENT_IDS) {
    totals.set(id, {
      id,
      value: values.get(id) ?? 0,
      unit: nutrientDefaultUnit(id),
      isComplete: complete.get(id) ?? true
    });
  }

  return totals;
}

function dayEntries(day: AnalyticsNutritionDay): AnalyticsFoodEntry[] {
  return day.meals.flatMap((meal) => [...meal.entries]);
}

export function dayTotals(
  day: AnalyticsNutritionDay
): Map<NutrientId, NutrientTotal> {
  return totalsFromEntries(dayEntries(day));
}

export type NutrientGoalTarget = {
  nutrient: NutrientId;
  value: number;
  unit: NutrientUnit;
};

export type NutrientGoalStatus = "noGoal" | "unknown" | "below" | "met" | "over";

/**
 * Derived goal progress for one nutrient: the period/day computed total measured
 * against a configured target. Unknown-aware — an incomplete total yields an
 * `unknown` status with no ratio/remaining, never a misleadingly precise compare
 * (NUTRITION.md §4). Mirrors NutrientGoalProgress.derive in nutrition.dart.
 */
export type NutrientGoalProgress = {
  nutrient: NutrientId;
  status: NutrientGoalStatus;
  total: NutrientTotal;
  target: NutrientGoalTarget | null;
  ratio: number | null;
  remaining: number | null;
};

export function deriveGoalProgress(
  total: NutrientTotal,
  target: NutrientGoalTarget | null
): NutrientGoalProgress {
  if (target === null) {
    return {
      nutrient: total.id,
      status: "noGoal",
      total,
      target: null,
      ratio: null,
      remaining: null
    };
  }
  if (!total.isComplete) {
    return {
      nutrient: total.id,
      status: "unknown",
      total,
      target,
      ratio: null,
      remaining: null
    };
  }

  const ratio = target.value === 0 ? null : total.value / target.value;
  const remaining = target.value - total.value;
  let status: NutrientGoalStatus;
  if (total.value > target.value) {
    status = "over";
  } else if (total.value === target.value) {
    status = "met";
  } else {
    status = "below";
  }

  return {
    nutrient: total.id,
    status,
    total,
    target,
    ratio,
    remaining
  };
}

export type NutritionTrendPoint = {
  localDate: string;
  value: number;
  isComplete: boolean;
};

export type NutritionTrend = {
  nutrient: NutrientId;
  unit: NutrientUnit;
  target: NutrientGoalTarget | null;
  points: readonly NutritionTrendPoint[];
};

/**
 * One per-day trend line for a single nutrient across an inclusive date range.
 * Every requested day yields a point: a day with no logged meals is a genuine
 * complete zero; a day whose entries omitted the nutrient is flagged incomplete
 * so the line never reads as a false zero (NUTRITION.md §4).
 */
export function buildNutritionTrend({
  nutrient,
  days,
  totalsByDate,
  target
}: {
  nutrient: NutrientId;
  days: readonly string[];
  totalsByDate: Map<string, Map<NutrientId, NutrientTotal>>;
  target: NutrientGoalTarget | null;
}): NutritionTrend {
  const unit = nutrientDefaultUnit(nutrient);
  const points: NutritionTrendPoint[] = days.map((localDate) => {
    const dayTotalsMap = totalsByDate.get(localDate);
    const total = dayTotalsMap?.get(nutrient);
    if (total === undefined) {
      return { localDate, value: 0, isComplete: true };
    }

    return {
      localDate,
      value: total.value,
      isComplete: total.isComplete
    };
  });

  return { nutrient, unit, target, points };
}

/**
 * Enumerate the inclusive calendar days between two `YYYY-MM-DD` Nutrition Day
 * dates. Pure value computation; stores nothing.
 */
export function enumerateNutritionDays(from: string, to: string): string[] {
  const start = parseNutritionDay(from);
  const end = parseNutritionDay(to);
  if (start.getTime() > end.getTime()) {
    throw new Error("Nutrition day range end must not precede its start.");
  }

  const days: string[] = [];
  const cursor = new Date(start.getTime());
  while (cursor.getTime() <= end.getTime()) {
    days.push(formatNutritionDay(cursor));
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }

  return days;
}

const NUTRITION_DAY_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;

export function parseNutritionDay(value: string): Date {
  const match = NUTRITION_DAY_PATTERN.exec(value);
  if (match === null) {
    throw new Error(`Expected a YYYY-MM-DD nutrition day: ${value}`);
  }

  const year = Number.parseInt(match[1], 10);
  const month = Number.parseInt(match[2], 10);
  const day = Number.parseInt(match[3], 10);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    throw new Error(`Invalid nutrition day date: ${value}`);
  }

  return date;
}

function formatNutritionDay(date: Date): string {
  const year = date.getUTCFullYear().toString().padStart(4, "0");
  const month = (date.getUTCMonth() + 1).toString().padStart(2, "0");
  const day = date.getUTCDate().toString().padStart(2, "0");
  return `${year}-${month}-${day}`;
}
