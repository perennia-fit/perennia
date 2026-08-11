import { randomBytes } from "node:crypto";
import { and, eq, isNull } from "drizzle-orm";

import { type CanonicalActivity } from "./canonical-import.js";
import {
  parseNormalizedCanonicalActivity,
  type NormalizedCanonicalActivity
} from "./canonical-activity-mapping.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";

export type StoredExternalActivity = {
  id: string;
  userId: string;
  deviceId: string;
  source: string;
  externalId: string;
  startedAt: string;
  endedAt: string;
  timezone: string;
  activityType: string;
  mappedExerciseId: string | null;
  summary: CanonicalActivity["summary"];
  summaryMetrics: CanonicalActivity["summaryMetrics"];
  sets: CanonicalActivity["sets"];
  updatedAt: string;
  deletedAt: string | null;
};

export type ExternalActivityStore = {
  storeCanonicalActivity(input: {
    userId: string;
    deviceId: string;
    activity: CanonicalActivity | NormalizedCanonicalActivity;
    importedAt?: Date;
  }): Promise<StoredExternalActivity | null>;
  findExternalActivity(input: {
    userId: string;
    source: string;
    externalId: string;
  }): Promise<StoredExternalActivity | null>;
};

export function createDrizzleExternalActivityStore(
  db: ServerDatabase
): ExternalActivityStore {
  return {
    async storeCanonicalActivity({ userId, deviceId, activity, importedAt }) {
      const parsed = parseNormalizedCanonicalActivity(activity);
      const updatedAt = importedAt ?? new Date();

      return db.transaction(async (transaction) => {
        const existingRows = await transaction
          .select()
          .from(schema.externalActivities)
          .where(
            and(
              eq(schema.externalActivities.userId, userId),
              eq(schema.externalActivities.source, parsed.source),
              eq(schema.externalActivities.externalId, parsed.externalId)
            )
          )
          .limit(1);
        const existing = existingRows[0];
        if (existing?.deletedAt !== null && existing?.deletedAt !== undefined) {
          return null;
        }

        if (existing === undefined) {
          const id = generateUuidV7(updatedAt);
          await transaction.insert(schema.externalActivities).values({
            id,
            userId,
            deviceId,
            source: parsed.source,
            externalId: parsed.externalId,
            startedAt: parseCanonicalInstant(parsed.startedAt),
            endedAt: parseCanonicalInstant(parsed.endedAt),
            timezone: parsed.timezone,
            activityType: parsed.activityType,
            mappedExerciseId: parsed.mappedExerciseId,
            summaryJson: parsed.summary,
            summaryMetricsJson: parsed.summaryMetrics,
            setsJson: parsed.sets ?? null,
            updatedAt,
            deletedAt: null,
            receivedAt: updatedAt
          });

          return {
            id,
            userId,
            deviceId,
            source: parsed.source,
            externalId: parsed.externalId,
            startedAt: parsed.startedAt,
            endedAt: parsed.endedAt,
            timezone: parsed.timezone,
            activityType: parsed.activityType,
            mappedExerciseId: parsed.mappedExerciseId,
            summary: parsed.summary,
            summaryMetrics: parsed.summaryMetrics,
            sets: parsed.sets,
            updatedAt: updatedAt.toISOString(),
            deletedAt: null
          };
        }

        await transaction
          .update(schema.externalActivities)
          .set({
            userId,
            deviceId,
            startedAt: parseCanonicalInstant(parsed.startedAt),
            endedAt: parseCanonicalInstant(parsed.endedAt),
            timezone: parsed.timezone,
            activityType: parsed.activityType,
            mappedExerciseId: parsed.mappedExerciseId,
            summaryJson: parsed.summary,
            summaryMetricsJson: parsed.summaryMetrics,
            setsJson: parsed.sets ?? null,
            updatedAt,
            deletedAt: null,
            receivedAt: updatedAt
          })
          .where(eq(schema.externalActivities.id, existing.id));

        return {
          id: existing.id,
          userId,
          deviceId,
          source: parsed.source,
          externalId: parsed.externalId,
          startedAt: parsed.startedAt,
          endedAt: parsed.endedAt,
          timezone: parsed.timezone,
          activityType: parsed.activityType,
          mappedExerciseId: parsed.mappedExerciseId,
          summary: parsed.summary,
          summaryMetrics: parsed.summaryMetrics,
          sets: parsed.sets,
          updatedAt: updatedAt.toISOString(),
          deletedAt: null
        };
      });
    },
    async findExternalActivity({ userId, source, externalId }) {
      const rows = await db
        .select()
        .from(schema.externalActivities)
        .where(
          and(
            eq(schema.externalActivities.userId, userId),
            eq(schema.externalActivities.source, source),
            eq(schema.externalActivities.externalId, externalId),
            isNull(schema.externalActivities.deletedAt)
          )
        )
        .limit(1);

      return rows[0] === undefined ? null : rowToStoredExternalActivity(rows[0]);
    }
  };
}

function rowToStoredExternalActivity(
  row: typeof schema.externalActivities.$inferSelect
): StoredExternalActivity {
  return {
    id: row.id,
    userId: row.userId,
    deviceId: row.deviceId,
    source: row.source,
    externalId: row.externalId,
    startedAt: row.startedAt.toISOString(),
    endedAt: row.endedAt.toISOString(),
    timezone: row.timezone,
    activityType: row.activityType,
    mappedExerciseId: row.mappedExerciseId,
    summary: row.summaryJson as CanonicalActivity["summary"],
    summaryMetrics:
      row.summaryMetricsJson as CanonicalActivity["summaryMetrics"],
    sets: (row.setsJson ?? undefined) as CanonicalActivity["sets"],
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  };
}

function parseCanonicalInstant(value: string) {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.valueOf())) {
    throw new Error("Canonical Activity timestamp must be an ISO-8601 instant.");
  }

  return parsed;
}

function generateUuidV7(now = new Date()) {
  const bytes = randomBytes(16);
  const timestampMs = BigInt(now.getTime());

  bytes[0] = Number((timestampMs >> 40n) & 0xffn);
  bytes[1] = Number((timestampMs >> 32n) & 0xffn);
  bytes[2] = Number((timestampMs >> 24n) & 0xffn);
  bytes[3] = Number((timestampMs >> 16n) & 0xffn);
  bytes[4] = Number((timestampMs >> 8n) & 0xffn);
  bytes[5] = Number(timestampMs & 0xffn);
  bytes[6] = (bytes[6] & 0x0f) | 0x70;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  return [
    bytes.subarray(0, 4).toString("hex"),
    bytes.subarray(4, 6).toString("hex"),
    bytes.subarray(6, 8).toString("hex"),
    bytes.subarray(8, 10).toString("hex"),
    bytes.subarray(10, 16).toString("hex")
  ].join("-");
}
