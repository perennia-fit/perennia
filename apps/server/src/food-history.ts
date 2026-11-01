/**
 * Food History (docs/designs/unified-food-search.md § Food History): the
 * distinct Foods a user logged, one per Food Source and Food id, derived from
 * Food Entries and Meals on each read and never stored. It orders Foods; a
 * Food's facts come from the Food itself.
 *
 * The app computes the same list in SQL (`NutritionRepository.listFoodHistory`)
 * to order its add-food picker; both run the golden vectors in
 * `packages/golden-vectors/vectors/m37-food-history.json`, so an agent and the
 * picker see the user's Foods in the same order.
 */

/** Food Entries whose Meal started this long before `now`, or later, count. */
export const FOOD_HISTORY_WINDOW_MS = 90 * 24 * 60 * 60 * 1000;

export type FoodHistoryPortion = {
  value: number;
  entered: string;
  unit: string;
};

export type FoodHistoryMeal = {
  id: string;
  /** ISO-8601. */
  startedAt: string;
  deletedAt: string | null;
};

export type FoodHistoryEntry = {
  id: string;
  mealId: string;
  kind: string;
  position: number;
  foodSource: string | null;
  foodId: string | null;
  isLiquid: boolean | null;
  portion: FoodHistoryPortion | null;
  /** ISO-8601. */
  updatedAt: string;
  deletedAt: string | null;
};

export type FoodHistoryRecord = {
  foodSource: string;
  foodId: string;
  /** Entries whose Meal started in the 90 days before `now`. */
  recentCount: number;
  /** The latest Meal start, ISO-8601 UTC. */
  lastLoggedAt: string;
  /** The latest entry's position within its Meal. */
  latestPosition: number;
  /** The latest entry: Meal start, then entry updatedAt, then entry id. */
  latestEntryId: string;
  /** The Portion of the latest entry that has one. */
  lastPortion: FoodHistoryPortion | null;
};

type CountedEntry = {
  id: string;
  foodSource: string;
  foodId: string;
  position: number;
  portion: FoodHistoryPortion | null;
  startedAt: number;
  updatedAt: number;
};

/**
 * The full Food History, in order: entries in the last 90 days descending,
 * then the latest Meal start descending, then the latest entry's position,
 * then Food Source name, then Food id.
 *
 * Only active `food` entries with a Food id, a Food Source and a liquid flag,
 * in active Meals, count. Entries of an archived User Food are left out:
 * archiving is the user-facing delete, so neither the picker nor an agent is
 * offered the Food again. Its entries stay.
 */
export function buildFoodHistory({
  entries,
  meals,
  archivedUserFoodIds,
  now
}: {
  entries: readonly FoodHistoryEntry[];
  meals: readonly FoodHistoryMeal[];
  archivedUserFoodIds: Iterable<string>;
  now: Date;
}): FoodHistoryRecord[] {
  const cutoff = now.getTime() - FOOD_HISTORY_WINDOW_MS;
  const archived = new Set(archivedUserFoodIds);
  const mealStarts = new Map<string, number>();
  for (const meal of meals) {
    const startedAt = Date.parse(meal.startedAt);
    if (meal.deletedAt === null && Number.isFinite(startedAt)) {
      mealStarts.set(meal.id, startedAt);
    }
  }

  const groups = new Map<string, CountedEntry[]>();
  for (const entry of entries) {
    const startedAt = mealStarts.get(entry.mealId);
    const updatedAt = Date.parse(entry.updatedAt);
    const { foodSource, foodId } = entry;
    if (
      entry.deletedAt !== null ||
      startedAt === undefined ||
      !Number.isFinite(updatedAt) ||
      entry.kind !== "food" ||
      foodSource === null ||
      foodId === null ||
      entry.isLiquid === null ||
      (foodSource === "user" && archived.has(foodId))
    ) {
      continue;
    }
    const key = JSON.stringify([foodSource, foodId]);
    const group = groups.get(key) ?? [];
    group.push({
      id: entry.id,
      foodSource,
      foodId,
      position: entry.position,
      portion: entry.portion,
      startedAt,
      updatedAt
    });
    groups.set(key, group);
  }

  const records: (FoodHistoryRecord & { lastLoggedMs: number })[] = [];
  for (const group of groups.values()) {
    const byLatest = [...group].sort(latestFirst);
    const latest = byLatest[0];
    records.push({
      foodSource: latest.foodSource,
      foodId: latest.foodId,
      recentCount: group.filter((entry) => entry.startedAt >= cutoff).length,
      lastLoggedAt: new Date(latest.startedAt).toISOString(),
      lastLoggedMs: latest.startedAt,
      latestPosition: latest.position,
      latestEntryId: latest.id,
      lastPortion: byLatest.find((entry) => entry.portion !== null)?.portion ?? null
    });
  }

  return records
    .sort(
      (left, right) =>
        right.recentCount - left.recentCount ||
        right.lastLoggedMs - left.lastLoggedMs ||
        left.latestPosition - right.latestPosition ||
        compareText(left.foodSource, right.foodSource) ||
        compareText(left.foodId, right.foodId)
    )
    .map(({ lastLoggedMs: _lastLoggedMs, ...record }) => record);
}

function latestFirst(left: CountedEntry, right: CountedEntry): number {
  return (
    right.startedAt - left.startedAt ||
    right.updatedAt - left.updatedAt ||
    compareText(right.id, left.id)
  );
}

/** Code-unit order, as SQLite's default BINARY collation orders ASCII text. */
function compareText(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}
