/**
 * Meal History (docs/designs/meal-logging.md §5): the distinct meals a user
 * repeats, derived from Meals and Food Entries on each read and never stored
 * or synced. Two Meals are the same meal when they hold the same set of
 * Foods, whatever the Portions; Quick Entries don't count.
 *
 * The app computes the same list in SQL (`NutritionRepository.listMealHistory`)
 * for the Meal screen's Your meals; both run the golden vectors in
 * `packages/golden-vectors/vectors/m38-meal-history.json`, so an agent and the
 * app see the same meals in the same order.
 */

import {
  compareText,
  FOOD_HISTORY_WINDOW_MS,
  isHistoryFoodEntry,
  toSecond
} from "./food-history.js";

export type MealHistoryMeal = {
  id: string;
  /** ISO-8601. */
  startedAt: string;
  /**
   * `instant` or `date`. A Meal payload written before Meals carried a time
   * precision has none, and reads as `instant`, as the app's column default
   * does.
   */
  timePrecision?: string | null;
  deletedAt: string | null;
};

export type MealHistoryEntry = {
  id: string;
  mealId: string;
  kind: string;
  position: number;
  foodSource: string | null;
  foodId: string | null;
  isLiquid: boolean | null;
  /** The snapshot name the entry was logged with. */
  name: string;
  deletedAt: string | null;
};

export type MealHistoryFood = {
  foodSource: string;
  foodId: string;
  /** The snapshot name in the most recent Meal with this identity. */
  name: string;
};

export type MealHistoryRecord = {
  /** The Foods in canonical order. */
  foods: MealHistoryFood[];
  /** Qualifying Meals with this identity in the window. */
  count: number;
  /** The most recent such Meal: latest start, then greatest Meal id. */
  lastMealId: string;
  /** That Meal's start, ISO-8601 UTC in whole seconds. */
  lastStartedAt: string;
};

export type MealHistoryRows = {
  meals: readonly MealHistoryMeal[];
  entries: readonly MealHistoryEntry[];
  archivedUserFoodIds: Iterable<string>;
};

type ConsideredMeal = {
  id: string;
  startedAt: number;
  /** One entry per distinct key: the first by position, then entry id. */
  foods: Map<string, { entry: MealHistoryEntry; key: string }>;
};

/**
 * Meal History, in order: `count` descending, then `lastStartedAt`
 * descending, then the canonical string ascending, at most `limit` items.
 *
 * The rows considered are active `food` entries with a Food Source, a Food id
 * and a liquid flag, leaving out entries of archived User Foods, in active
 * Meals whose time precision is `instant` and that started at or after
 * `now` minus 90 days (the Food History window). A Meal qualifies when those
 * rows hold two or more distinct Foods. Its identity is the canonical string:
 * the distinct `foodSource:foodId` keys in ordinal order, joined with `|`.
 */
export function buildMealHistory(
  { meals, entries, archivedUserFoodIds }: MealHistoryRows,
  { now, limit }: { now: Date; limit: number }
): MealHistoryRecord[] {
  const cutoff = toSecond(now.getTime() - FOOD_HISTORY_WINDOW_MS);
  const archived = new Set(archivedUserFoodIds);
  const considered = new Map<string, ConsideredMeal>();
  for (const meal of meals) {
    const startedAt = toSecond(Date.parse(meal.startedAt));
    if (
      meal.deletedAt === null &&
      (meal.timePrecision ?? "instant") === "instant" &&
      Number.isFinite(startedAt) &&
      startedAt >= cutoff
    ) {
      considered.set(meal.id, { id: meal.id, startedAt, foods: new Map() });
    }
  }

  for (const entry of entries) {
    const meal = considered.get(entry.mealId);
    if (meal === undefined || !isHistoryFoodEntry(entry, archived)) {
      continue;
    }
    const key = `${entry.foodSource}:${entry.foodId}`;
    const current = meal.foods.get(key);
    if (current === undefined || firstInMeal(entry, current.entry) < 0) {
      meal.foods.set(key, { entry, key });
    }
  }

  const groups = new Map<string, { latest: ConsideredMeal; count: number }>();
  for (const meal of considered.values()) {
    if (meal.foods.size < 2) {
      continue;
    }
    const identity = canonicalString(meal);
    const group = groups.get(identity);
    if (group === undefined) {
      groups.set(identity, { latest: meal, count: 1 });
      continue;
    }
    group.count += 1;
    if (
      meal.startedAt > group.latest.startedAt ||
      (meal.startedAt === group.latest.startedAt &&
        compareText(meal.id, group.latest.id) > 0)
    ) {
      group.latest = meal;
    }
  }

  return [...groups.entries()]
    .map(([identity, { latest, count }]) => ({
      identity,
      startedAt: latest.startedAt,
      record: {
        foods: [...latest.foods.values()]
          .sort((left, right) => compareText(left.key, right.key))
          .map(({ entry }) => ({
            foodSource: entry.foodSource as string,
            foodId: entry.foodId as string,
            name: entry.name
          })),
        count,
        lastMealId: latest.id,
        // toISOString() output sorts as text in time order.
        lastStartedAt: new Date(latest.startedAt).toISOString()
      }
    }))
    .sort(
      (left, right) =>
        right.record.count - left.record.count ||
        right.startedAt - left.startedAt ||
        compareText(left.identity, right.identity)
    )
    .slice(0, Math.max(0, limit))
    .map(({ record }) => record);
}

function canonicalString(meal: ConsideredMeal): string {
  return [...meal.foods.keys()].sort(compareText).join("|");
}

/** The entry whose name a Meal shows for a Food: lowest position, then id. */
function firstInMeal(left: MealHistoryEntry, right: MealHistoryEntry): number {
  return left.position - right.position || compareText(left.id, right.id);
}
