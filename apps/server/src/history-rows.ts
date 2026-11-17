/**
 * The rows Food History and Meal History are derived from, read the same way
 * for both: the caller's active Meals, the caller's active Food Entries that
 * can count, and the ids of the caller's archived User Foods. Each history's
 * read store maps these rows to its builder's input; the builders still apply
 * every rule.
 */

import { and, eq, isNotNull, isNull, type SQL, sql } from "drizzle-orm";

import { numberValue, stringValue } from "./agent-nutrition-reads.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";

/** A synced Food Entry payload field a history reads. */
export type HistoryEntryField =
  | "meal_id"
  | "entry_kind"
  | "position"
  | "name"
  | "food_source"
  | "food_id"
  | "is_liquid"
  | "portion_json"
  | "updated_at";

export type HistoryMealRow = {
  id: string;
  /** The payload's `started_at` when it is a JSON string, otherwise null. */
  startedAt: string | null;
  /** The payload's `time_precision`; present only when requested. */
  timePrecision?: string | null;
};

export type HistoryEntryRow = {
  id: string;
  /** Only the requested fields of the synced payload. */
  payload: Record<string, unknown>;
};

export type HistoryRows = {
  meals: HistoryMealRow[];
  entries: HistoryEntryRow[];
  archivedUserFoodIds: string[];
};

export async function loadHistoryRows(
  db: ServerDatabase,
  userId: string,
  {
    includeTimePrecision,
    entryFields
  }: {
    includeTimePrecision: boolean;
    entryFields: readonly HistoryEntryField[];
  }
): Promise<HistoryRows> {
  const meal = schema.meals.payload;
  const entry = schema.foodEntries.payload;
  const mealColumns = {
    id: schema.meals.id,
    startedAt: sql<string | null>`CASE WHEN jsonb_typeof(${meal} -> 'started_at') = 'string' THEN ${meal} ->> 'started_at' END`
  };
  const mealWhere = and(
    eq(schema.meals.userId, userId),
    isNull(schema.meals.deletedAt)
  );
  // The field names come from HistoryEntryField, a fixed set of literals, so
  // writing them into the SQL text is safe.
  const entryPayload = sql.join(
    entryFields.map(
      (field): SQL => {
        const name = sql.raw(`'${field}'`);
        return sql`${name}, ${entry} -> ${name}`;
      }
    ),
    sql`, `
  );

  // Every query is scoped to the caller: another user's Meals, Food Entries
  // and Foods never reach a history builder.
  const [meals, entries, archivedRows] = await Promise.all([
    includeTimePrecision
      ? db
          .select({
            ...mealColumns,
            timePrecision: sql<string | null>`${meal} ->> 'time_precision'`
          })
          .from(schema.meals)
          .where(mealWhere)
      : db.select(mealColumns).from(schema.meals).where(mealWhere),
    // Only the entries that can count, and only the fields the history reads.
    db
      .select({
        id: schema.foodEntries.id,
        payload: sql<Record<string, unknown>>`jsonb_build_object(${entryPayload})`
      })
      .from(schema.foodEntries)
      .where(
        and(
          eq(schema.foodEntries.userId, userId),
          isNull(schema.foodEntries.deletedAt),
          sql`${entry} ->> 'entry_kind' = 'food'`,
          sql`${entry} ->> 'food_source' IS NOT NULL`,
          sql`${entry} ->> 'food_id' IS NOT NULL`
        )
      ),
    db
      .select({ id: schema.foods.id })
      .from(schema.foods)
      .where(
        and(eq(schema.foods.userId, userId), isNotNull(schema.foods.deletedAt))
      )
  ]);

  return {
    meals,
    entries,
    archivedUserFoodIds: archivedRows.map((row) => row.id)
  };
}

/** The Food Entry fields both histories read, parsed the same way. */
export type HistoryEntryBase = {
  id: string;
  mealId: string;
  kind: string;
  position: number;
  foodSource: string | null;
  foodId: string | null;
  isLiquid: boolean | null;
  deletedAt: null;
};

/**
 * The fields both histories read from a synced Food Entry payload, or null
 * without a Meal id. The liquid flag is read as stored: a null flag leaves
 * the entry out, as it does in the app, so this does not use the meal read's
 * mapper, which reads null as false.
 */
export function historyEntryBaseFromPayload(
  id: string,
  payload: Record<string, unknown>
): HistoryEntryBase | null {
  const mealId = stringValue(payload.meal_id);
  if (mealId === null) {
    return null;
  }
  return {
    id,
    mealId,
    kind: stringValue(payload.entry_kind) ?? "quickEntry",
    position: numberValue(payload.position) ?? 0,
    foodSource: stringValue(payload.food_source),
    foodId: stringValue(payload.food_id),
    isLiquid: typeof payload.is_liquid === "boolean" ? payload.is_liquid : null,
    deletedAt: null
  };
}
