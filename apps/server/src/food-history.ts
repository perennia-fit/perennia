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

/**
 * Times compare in whole seconds, rounded down: the app stores them as Unix
 * seconds, so it cannot see milliseconds, and the two must agree on the
 * latest entry, its Portion and the 90-day window.
 */
export function toSecond(ms: number): number {
  return Math.floor(ms / 1000) * 1000;
}

/** The fields of a Food Entry that decide whether Food or Meal History reads it. */
export type HistoryFoodEntryFields = {
  kind: string;
  foodSource: string | null;
  foodId: string | null;
  isLiquid: boolean | null;
  deletedAt: string | null;
};

/**
 * Whether a Food Entry can count towards Food History or Meal History: an
 * active `food` entry with a Food Source, a Food id and a liquid flag, and not
 * an entry of an archived User Food. Archiving is the user-facing delete, so
 * neither history offers the Food again; its entries stay. Each builder adds
 * its own rules about the entry's Meal.
 */
export function isHistoryFoodEntry<E extends HistoryFoodEntryFields>(
  entry: E,
  archivedUserFoodIds: ReadonlySet<string>
): entry is E & { foodSource: string; foodId: string; isLiquid: boolean } {
  return (
    entry.deletedAt === null &&
    entry.kind === "food" &&
    entry.foodSource !== null &&
    entry.foodId !== null &&
    entry.isLiquid !== null &&
    !(entry.foodSource === "user" && archivedUserFoodIds.has(entry.foodId))
  );
}

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
  /** The latest Meal start, ISO-8601 UTC in whole seconds. */
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
  const cutoff = toSecond(now.getTime() - FOOD_HISTORY_WINDOW_MS);
  const archived = new Set(archivedUserFoodIds);
  const mealStarts = new Map<string, number>();
  for (const meal of meals) {
    const startedAt = toSecond(Date.parse(meal.startedAt));
    if (meal.deletedAt === null && Number.isFinite(startedAt)) {
      mealStarts.set(meal.id, startedAt);
    }
  }

  // One pass: each group keeps its latest entry, its latest entry with a
  // Portion, and its count in the window.
  const groups = new Map<
    string,
    {
      latest: CountedEntry;
      latestWithPortion: CountedEntry | null;
      recentCount: number;
    }
  >();
  for (const entry of entries) {
    const startedAt = mealStarts.get(entry.mealId);
    const updatedAt = toSecond(Date.parse(entry.updatedAt));
    if (
      startedAt === undefined ||
      !Number.isFinite(updatedAt) ||
      !isHistoryFoodEntry(entry, archived)
    ) {
      continue;
    }
    const { foodSource, foodId } = entry;
    const counted: CountedEntry = {
      id: entry.id,
      foodSource,
      foodId,
      position: entry.position,
      portion: entry.portion,
      startedAt,
      updatedAt
    };
    const withPortion = counted.portion === null ? null : counted;
    const recent = startedAt >= cutoff ? 1 : 0;
    // Food Source names hold no NUL, so the key is unambiguous.
    const key = `${foodSource}\u0000${foodId}`;
    const group = groups.get(key);
    if (group === undefined) {
      groups.set(key, {
        latest: counted,
        latestWithPortion: withPortion,
        recentCount: recent
      });
      continue;
    }
    group.recentCount += recent;
    if (latestFirst(counted, group.latest) < 0) {
      group.latest = counted;
    }
    if (
      withPortion !== null &&
      (group.latestWithPortion === null ||
        latestFirst(withPortion, group.latestWithPortion) < 0)
    ) {
      group.latestWithPortion = withPortion;
    }
  }

  return [...groups.values()]
    .map(
      ({ latest, latestWithPortion, recentCount }): FoodHistoryRecord => ({
        foodSource: latest.foodSource,
        foodId: latest.foodId,
        recentCount,
        // toISOString() output sorts as text in time order.
        lastLoggedAt: new Date(latest.startedAt).toISOString(),
        latestPosition: latest.position,
        latestEntryId: latest.id,
        lastPortion: latestWithPortion?.portion ?? null
      })
    )
    .sort(
      (left, right) =>
        right.recentCount - left.recentCount ||
        compareText(right.lastLoggedAt, left.lastLoggedAt) ||
        left.latestPosition - right.latestPosition ||
        compareText(left.foodSource, right.foodSource) ||
        compareText(left.foodId, right.foodId)
    );
}

function latestFirst(left: CountedEntry, right: CountedEntry): number {
  return (
    right.startedAt - left.startedAt ||
    right.updatedAt - left.updatedAt ||
    compareText(right.id, left.id)
  );
}

/** Code-unit order, as SQLite's default BINARY collation orders ASCII text. */
export function compareText(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}
