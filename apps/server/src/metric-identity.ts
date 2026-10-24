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
