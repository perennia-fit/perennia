import { createHash } from "node:crypto";
import { and, asc, eq, isNull } from "drizzle-orm";

import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import { normalizeMetricLookupKey } from "./metric-catalog.js";

type MetricIdentityDatabase = Pick<ServerDatabase, "select">;

/**
 * The names the app seeds into Body Tracker on every install, each under a
 * fresh random id. Mirrors `MeasurementRepository.defaultMeasurementNames`
 * in the app.
 */
export const DEFAULT_MEASUREMENT_NAMES: ReadonlySet<string> = new Set([
  "Body Weight",
  "Body Fat"
]);

/**
 * The user's body-composition Metric that a body-composition value named
 * [name] in [unit] belongs to: active, scalar, same name (case and spacing
 * ignored), same unit, first by sort order then id. Null when there is none.
 *
 * This is the one identity rule for a body-composition measurement on the
 * server. Canonical import attaches an imported weigh-in to this row rather
 * than creating its own, and sync push folds a device's seeded default into
 * it (`pushMetricsInTransaction` in sync.ts). Units must agree because a
 * reading's value is stored in its Metric's unit: a pound Body Weight and a
 * kilogram one are different rows. The app's backup restore and pull-side
 * merge use the same rule (`PortableArchiveRepository
 * ._adoptLocalDefaultMeasurementIds`, `MeasurementRepository
 * .adoptSyncedDefaultMeasurement`).
 */
export async function findActiveBodyCompositionMetric(
  database: MetricIdentityDatabase,
  { name, unit, userId }: { name: string; unit: string; userId: string }
) {
  const rows = await database
    .select()
    .from(schema.metrics)
    .where(
      and(
        eq(schema.metrics.userId, userId),
        eq(schema.metrics.metricGroup, "bodyComposition"),
        eq(schema.metrics.valueShape, "scalar"),
        isNull(schema.metrics.deletedAt)
      )
    )
    .orderBy(asc(schema.metrics.sortOrder), asc(schema.metrics.id));

  const normalizedName = normalizeMetricLookupKey(name);
  return (
    rows.find(
      (row) =>
        row.unit === unit &&
        normalizeMetricLookupKey(row.name) === normalizedName
    ) ?? null
  );
}

/**
 * Serializes, per user, the writes that look a body-composition Metric up
 * by name and unit and create one when there is none: sync push of a
 * default measurement and canonical import of a weigh-in. Without it two
 * of them running at once could each find nothing and each insert a Body
 * Weight. Locks the user's row for the rest of the transaction.
 */
export async function lockMetricIdentity(
  database: MetricIdentityDatabase,
  userId: string
) {
  await database
    .select({ id: schema.user.id })
    .from(schema.user)
    .where(eq(schema.user.id, userId))
    .for("update");
}

/**
 * The deterministic id of the user's Metric for [metricKey]: a catalog
 * Metric's canonical key, or `"lab:" + labTestKey` for the Lab Metric the
 * Agent write creates (docs/designs/lab-results.md, "Finding the Lab Metric
 * for a Lab Test").
 *
 * The id is scoped by user on purpose. Metric ids are one global key space,
 * and sync push skips a row whose id another account already owns (TENANT
 * ISOLATION in sync.ts): an unscoped id such as `metric:hrv` would belong to
 * the first account that wrote it, and every other account's write of it
 * would be dropped. Hashing the user id in keeps each account's row its own,
 * and keeps it stable so two concurrent writes of one key meet on one row.
 *
 * The value is pinned by tests and by stored rows: never change the prefix,
 * the NUL separator or the 32-hex-character length.
 */
export function stableMetricId(userId: string, metricKey: string) {
  return stableScopedId("metric", userId, metricKey);
}

function stableScopedId(prefix: string, ...parts: string[]) {
  return `${prefix}:${hashParts(parts)}`;
}

function hashParts(parts: string[]) {
  const hash = createHash("sha256");
  for (const part of parts) {
    hash.update(part);
    hash.update("\0");
  }

  return hash.digest("hex").slice(0, 32);
}

/**
 * The user's live Lab Metric for [labTestKey]: `deletedAt` null, lowest
 * `sortOrder`, then lowest id. Null when there is none. The same rule as the
 * app's `LabResultsRepository` (docs/designs/lab-results.md, "Finding the
 * Lab Metric for a Lab Test"), so a write from either side lands on the same
 * row when one exists.
 *
 * This picks where a new Lab Result is written, never what a reader shows:
 * two Lab Metrics for one Lab Test can exist (two devices offline, or an
 * older server), and they are not merged. Readers join Lab Results by key
 * through [labMetricIds], so a result on either row is seen.
 */
export async function findLabMetric(
  database: MetricIdentityDatabase,
  { userId, labTestKey }: { userId: string; labTestKey: string }
) {
  const rows = await database
    .select()
    .from(schema.metrics)
    .where(
      and(
        eq(schema.metrics.userId, userId),
        eq(schema.metrics.labTestKey, labTestKey),
        isNull(schema.metrics.deletedAt)
      )
    )
    .orderBy(asc(schema.metrics.sortOrder), asc(schema.metrics.id))
    .limit(1);
  return rows[0] ?? null;
}

/**
 * The ids of every Metric of the user with [labTestKey], archived ones
 * included. Readers of Lab Results join by key, not by row: identity is per
 * user and per Lab Test (docs/designs/lab-results.md, "Result identity and
 * the collapse"), a Lab Metric's own archive state has no effect on its
 * readings, and a second Lab Metric for one key must not hide or split its
 * results.
 */
export async function labMetricIds(
  database: MetricIdentityDatabase,
  { userId, labTestKey }: { userId: string; labTestKey: string }
) {
  const rows = await database
    .select({ id: schema.metrics.id })
    .from(schema.metrics)
    .where(
      and(
        eq(schema.metrics.userId, userId),
        eq(schema.metrics.labTestKey, labTestKey)
      )
    )
    .orderBy(asc(schema.metrics.id));
  return rows.map((row) => row.id);
}
