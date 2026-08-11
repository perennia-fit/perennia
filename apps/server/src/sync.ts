import { isDeepStrictEqual } from "node:util";
import { createRoute, z } from "@hono/zod-openapi";
import { and, asc, eq, gt, gte, inArray, isNull, or } from "drizzle-orm";

import { ACCOUNT_DELETION_LOCAL_ONLY_MESSAGE } from "./account-deletion.js";
import { CanonicalImportConsentDataClassSchema } from "./canonical-import.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import { SYNC_TOMBSTONE_RETENTION_MS } from "./sync-tombstone-gc.js";

export const SYNC_PROTOCOL_VERSION = 1;
export const LOGGED_SETS_SYNC_ENTITY = "logged_sets";
export const FOODS_SYNC_ENTITY = "foods";
export const MEAL_TYPES_SYNC_ENTITY = "meal_types";
export const MEALS_SYNC_ENTITY = "meals";
export const FOOD_ENTRIES_SYNC_ENTITY = "food_entries";
export const METRICS_SYNC_ENTITY = "metrics";
export const METRIC_READINGS_SYNC_ENTITY = "metric_readings";
export const NUTRITION_GOALS_SYNC_ENTITY = "nutrition_goals";
export const USER_SETTINGS_SYNC_ENTITY = "user_settings";
export const EXERCISE_CATEGORIES_SYNC_ENTITY = "exercise_categories";
export const EXERCISES_SYNC_ENTITY = "exercises";
export const WORKOUT_SESSIONS_SYNC_ENTITY = "workout_sessions";
export const WORKOUT_EXERCISES_SYNC_ENTITY = "workout_exercises";
export const EXERCISE_GROUPS_SYNC_ENTITY = "exercise_groups";
export const EXERCISE_GROUP_MEMBERS_SYNC_ENTITY = "exercise_group_members";
export const COMPOUNDS_SYNC_ENTITY = "compounds";
export const DOSES_SYNC_ENTITY = "doses";
export const PROTOCOLS_SYNC_ENTITY = "protocols";
export const PROTOCOL_COMPOUNDS_SYNC_ENTITY = "protocol_compounds";
export const SCHEDULES_SYNC_ENTITY = "schedules";
export const PROTOCOL_TARGET_OUTCOMES_SYNC_ENTITY = "protocol_target_outcomes";
export const INTEGRATION_DATA_CLASS_CONSENTS_SYNC_ENTITY =
  "integration_data_class_consents";
export const ROUTINES_SYNC_ENTITY = "routines";
export const WORKOUT_TEMPLATES_SYNC_ENTITY = "workout_templates";
export const TEMPLATE_EXERCISES_SYNC_ENTITY = "template_exercises";
export const PRESCRIPTIONS_SYNC_ENTITY = "prescriptions";
export const TEMPLATE_GROUPS_SYNC_ENTITY = "template_groups";
export const TEMPLATE_GROUP_MEMBERS_SYNC_ENTITY =
  "template_group_members";
export const ROUTINE_ENTRIES_SYNC_ENTITY = "routine_entries";
export const TEMPLATE_LINKS_SYNC_ENTITY = "template_links";
const SYNC_PULL_ENTITIES = [
  EXERCISE_CATEGORIES_SYNC_ENTITY,
  EXERCISES_SYNC_ENTITY,
  WORKOUT_SESSIONS_SYNC_ENTITY,
  WORKOUT_EXERCISES_SYNC_ENTITY,
  EXERCISE_GROUPS_SYNC_ENTITY,
  EXERCISE_GROUP_MEMBERS_SYNC_ENTITY,
  COMPOUNDS_SYNC_ENTITY,
  DOSES_SYNC_ENTITY,
  FOODS_SYNC_ENTITY,
  MEAL_TYPES_SYNC_ENTITY,
  FOOD_ENTRIES_SYNC_ENTITY,
  LOGGED_SETS_SYNC_ENTITY,
  METRICS_SYNC_ENTITY,
  MEALS_SYNC_ENTITY,
  METRIC_READINGS_SYNC_ENTITY,
  INTEGRATION_DATA_CLASS_CONSENTS_SYNC_ENTITY,
  PROTOCOLS_SYNC_ENTITY,
  PROTOCOL_COMPOUNDS_SYNC_ENTITY,
  SCHEDULES_SYNC_ENTITY,
  PROTOCOL_TARGET_OUTCOMES_SYNC_ENTITY,
  NUTRITION_GOALS_SYNC_ENTITY,
  USER_SETTINGS_SYNC_ENTITY,
  ROUTINES_SYNC_ENTITY,
  WORKOUT_TEMPLATES_SYNC_ENTITY,
  TEMPLATE_EXERCISES_SYNC_ENTITY,
  PRESCRIPTIONS_SYNC_ENTITY,
  TEMPLATE_GROUPS_SYNC_ENTITY,
  TEMPLATE_GROUP_MEMBERS_SYNC_ENTITY,
  ROUTINE_ENTRIES_SYNC_ENTITY,
  TEMPLATE_LINKS_SYNC_ENTITY
] as const;
const SYNC_PUSH_ENTITIES = [
  EXERCISE_CATEGORIES_SYNC_ENTITY,
  EXERCISES_SYNC_ENTITY,
  WORKOUT_SESSIONS_SYNC_ENTITY,
  WORKOUT_EXERCISES_SYNC_ENTITY,
  EXERCISE_GROUPS_SYNC_ENTITY,
  EXERCISE_GROUP_MEMBERS_SYNC_ENTITY,
  COMPOUNDS_SYNC_ENTITY,
  DOSES_SYNC_ENTITY,
  FOODS_SYNC_ENTITY,
  MEAL_TYPES_SYNC_ENTITY,
  FOOD_ENTRIES_SYNC_ENTITY,
  LOGGED_SETS_SYNC_ENTITY,
  MEALS_SYNC_ENTITY,
  INTEGRATION_DATA_CLASS_CONSENTS_SYNC_ENTITY,
  PROTOCOLS_SYNC_ENTITY,
  PROTOCOL_COMPOUNDS_SYNC_ENTITY,
  SCHEDULES_SYNC_ENTITY,
  PROTOCOL_TARGET_OUTCOMES_SYNC_ENTITY,
  NUTRITION_GOALS_SYNC_ENTITY,
  USER_SETTINGS_SYNC_ENTITY,
  ROUTINES_SYNC_ENTITY,
  WORKOUT_TEMPLATES_SYNC_ENTITY,
  TEMPLATE_EXERCISES_SYNC_ENTITY,
  PRESCRIPTIONS_SYNC_ENTITY,
  TEMPLATE_GROUPS_SYNC_ENTITY,
  TEMPLATE_GROUP_MEMBERS_SYNC_ENTITY,
  ROUTINE_ENTRIES_SYNC_ENTITY,
  TEMPLATE_LINKS_SYNC_ENTITY
] as const;
export const SYNC_PULL_MODE_DELTA = "delta";
export const SYNC_PULL_MODE_SNAPSHOT = "snapshot";

const ACTIVITY_LOG_ENVELOPE_FIELDS = [
  "activityLogId",
  "actor",
  "batchId",
  "beforeImage",
  "afterImage",
  "occurredAt"
] as const;

export const SyncPushChangeSchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "UUIDv7 primary key for the changed row."
    }),
    payload: z.record(z.string(), z.unknown()).openapi({
      description: "Canonical row payload from the device replica."
    }),
    updatedAt: z.string().min(1).openapi({
      description: "HLC-style updated_at value for LWW ordering."
    }),
    deletedAt: z.string().min(1).nullable().openapi({
      description: "Tombstone timestamp, or null for live rows."
    }),
    activityLogId: z.string().min(1).optional().openapi({
      description:
        "Stable id of the client activity-log entry that produced this change."
    }),
    actor: z.string().min(1).optional().openapi({
      description: "Actor recorded by the client activity log."
    }),
    batchId: z.string().min(1).optional().openapi({
      description: "Client activity-log batch id for undo/recovery grouping."
    }),
    beforeImage: z
      .record(z.string(), z.unknown())
      .nullable()
      .optional()
      .openapi({
        description: "Client activity-log before image for this mutation."
      }),
    afterImage: z
      .record(z.string(), z.unknown())
      .nullable()
      .optional()
      .openapi({
        description: "Client activity-log after image for this mutation."
      }),
    occurredAt: z.string().min(1).optional().openapi({
      description: "Client activity-log occurrence timestamp."
    })
  })
  .superRefine((change, ctx) => {
    const providedEnvelopeFields = ACTIVITY_LOG_ENVELOPE_FIELDS.filter(
      (field) => change[field] !== undefined
    );
    if (
      providedEnvelopeFields.length > 0 &&
      providedEnvelopeFields.length < ACTIVITY_LOG_ENVELOPE_FIELDS.length
    ) {
      ctx.addIssue({
        code: "custom",
        message:
          "activity-log sync metadata must be provided as a complete envelope"
      });
    }
  })
  .openapi("SyncPushChange");

export const SyncPushRequestSchema = z
  .object({
    protocolVersion: z.literal(SYNC_PROTOCOL_VERSION).openapi({
      description: "Version of the delta-sync protocol spoken by the client."
    }),
    deviceId: z.string().min(1).openapi({
      description: "Stable id for the signed-in device replica."
    }),
    entity: z.enum(SYNC_PUSH_ENTITIES).openapi({
      description: "Synced entity type carried by this push batch."
    }),
    changes: z.array(SyncPushChangeSchema).min(1).max(100).openapi({
      description: "Locally changed rows from the device journal."
    })
  })
  .openapi("SyncPushRequest");

export const SyncPushResponseSchema = z
  .object({
    protocolVersion: z.literal(SYNC_PROTOCOL_VERSION),
    accepted: z.array(z.string().min(1)),
    serverClock: z.string().min(1).openapi({
      description:
        "Server-side sync clock observed while processing the push batch."
    }),
    applied: z.array(
      z.object({
        id: z.string().min(1),
        updatedAt: z.string().min(1),
        deviceId: z.string().min(1)
      })
    )
  })
  .openapi("SyncPushResponse");

export const SyncPullRequestSchema = z
  .object({
    protocolVersion: z.literal(SYNC_PROTOCOL_VERSION).openapi({
      description: "Version of the delta-sync protocol spoken by the client."
    }),
    cursor: z.string().min(1).nullable().openapi({
      description: "Opaque server-issued cursor from the previous pull."
    }),
    limit: z.number().int().min(1).max(100).default(100).openapi({
      description: "Maximum number of changes to return in this window."
    }),
    mode: z
      .enum([SYNC_PULL_MODE_DELTA, SYNC_PULL_MODE_SNAPSHOT])
      .default(SYNC_PULL_MODE_DELTA)
      .openapi({
        description:
          "Delta returns changes since the cursor; snapshot returns live rows for forced full re-sync."
      })
  })
  .openapi("SyncPullRequest");

export const SyncPulledChangeSchema = z
  .object({
    entity: z.enum(SYNC_PULL_ENTITIES),
    id: z.string().min(1),
    deviceId: z.string().min(1),
    payload: z.record(z.string(), z.unknown()),
    updatedAt: z.string().min(1),
    deletedAt: z.string().min(1).nullable(),
    activityLogId: z.string().min(1).optional().openapi({
      description:
        "Stable id of the Activity Log entry that produced this change."
    }),
    actor: z.string().min(1).optional().openapi({
      description: "Actor recorded by the Activity Log entry."
    }),
    batchId: z.string().min(1).optional().openapi({
      description: "Activity Log batch id for undo/recovery grouping."
    }),
    beforeImage: z
      .record(z.string(), z.unknown())
      .nullable()
      .optional()
      .openapi({
        description: "Activity Log before image for this mutation."
      }),
    afterImage: z
      .record(z.string(), z.unknown())
      .nullable()
      .optional()
      .openapi({
        description: "Activity Log after image for this mutation."
      }),
    occurredAt: z.string().min(1).optional().openapi({
      description: "Activity Log occurrence timestamp."
    })
  })
  .superRefine((change, ctx) => {
    const providedEnvelopeFields = ACTIVITY_LOG_ENVELOPE_FIELDS.filter(
      (field) => change[field] !== undefined
    );
    if (
      providedEnvelopeFields.length > 0 &&
      providedEnvelopeFields.length < ACTIVITY_LOG_ENVELOPE_FIELDS.length
    ) {
      ctx.addIssue({
        code: "custom",
        message:
          "activity-log sync metadata must be provided as a complete envelope"
      });
    }
  })
  .openapi("SyncPulledChange");

export const SyncPullResponseSchema = z
  .object({
    protocolVersion: z.literal(SYNC_PROTOCOL_VERSION),
    fullResyncRequired: z.boolean().default(false).openapi({
      description:
        "True when the presented cursor is older than the tombstone GC horizon and the client must perform a full re-sync."
    }),
    changes: z.array(SyncPulledChangeSchema),
    nextCursor: z.string().min(1).nullable(),
    serverClock: z.string().min(1).openapi({
      description:
        "Server-side sync clock observed while processing the pull request."
    })
  })
  .openapi("SyncPullResponse");

export const SyncUnauthorizedResponseSchema = z
  .object({
    code: z.literal("sync_unauthorized"),
    message: z.string().min(1)
  })
  .openapi("SyncUnauthorizedResponse");

export const SyncUnavailableResponseSchema = z
  .object({
    code: z.literal("sync_unavailable"),
    message: z.string().min(1)
  })
  .openapi("SyncUnavailableResponse");

export const syncPushRoute = createRoute({
  method: "post",
  path: "/sync/push",
  operationId: "pushSync",
  tags: ["Sync"],
  summary: "Push local replica changes to the server.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: SyncPushRequestSchema
        }
      }
    }
  },
  responses: {
    200: {
      description: "The server accepted the pushed changes.",
      content: {
        "application/json": {
          schema: SyncPushResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid session bearer token.",
      content: {
        "application/json": {
          schema: SyncUnauthorizedResponseSchema
        }
      }
    },
    503: {
      description: "Sync storage is not configured for this app instance.",
      content: {
        "application/json": {
          schema: SyncUnavailableResponseSchema
        }
      }
    }
  }
});

export const syncPullRoute = createRoute({
  method: "post",
  path: "/sync/pull",
  operationId: "pullSync",
  tags: ["Sync"],
  summary: "Pull replica changes from the server.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: SyncPullRequestSchema
        }
      }
    }
  },
  responses: {
    200: {
      description: "The server returned the next window of replica changes.",
      content: {
        "application/json": {
          schema: SyncPullResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid session bearer token.",
      content: {
        "application/json": {
          schema: SyncUnauthorizedResponseSchema
        }
      }
    },
    503: {
      description: "Sync storage is not configured for this app instance.",
      content: {
        "application/json": {
          schema: SyncUnavailableResponseSchema
        }
      }
    }
  }
});

export type SyncPushChange = z.infer<typeof SyncPushChangeSchema>;
export type SyncPulledChange = z.infer<typeof SyncPulledChangeSchema>;
type SyncPushEntity = (typeof SYNC_PUSH_ENTITIES)[number];
type SyncPullEntity = (typeof SYNC_PULL_ENTITIES)[number];
export type SyncAppliedChange = {
  id: string;
  updatedAt: string;
  deviceId: string;
};

export type SyncPushResult = {
  accepted: string[];
  serverClock: string;
  applied: SyncAppliedChange[];
};

export type SyncPullWindow = {
  fullResyncRequired?: boolean;
  changes: SyncPulledChange[];
  nextCursor: string | null;
  serverClock: string;
};

export type AuthenticatedSyncSession = {
  userId: string;
};

export type SyncStore = {
  verifyBearerToken(token: string): Promise<AuthenticatedSyncSession | null>;
  explainUnauthorizedBearerToken?(token: string): Promise<string | null>;
  pushExerciseCategories(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushExercises(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushLoggedSets(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushFoods(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushMealTypes(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushMeals(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushFoodEntries(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushCompounds(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushDoses(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushProtocols(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushProtocolCompounds(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushSchedules(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushProtocolTargetOutcomes(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushNutritionGoals(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushUserSettings(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushIntegrationDataClassConsents(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushRoutines(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushWorkoutSessions(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushWorkoutExercises(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushExerciseGroups(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushExerciseGroupMembers(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushWorkoutTemplates(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushTemplateExercises(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushPrescriptions(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushTemplateGroups(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushTemplateGroupMembers(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushRoutineEntries(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pushTemplateLinks(input: {
    userId: string;
    correlationId?: string;
    deviceId: string;
    changes: SyncPushChange[];
  }): Promise<SyncPushResult>;
  pullChanges(input: {
    userId: string;
    correlationId?: string;
    cursor: string | null;
    limit: number;
    mode: typeof SYNC_PULL_MODE_DELTA | typeof SYNC_PULL_MODE_SNAPSHOT;
  }): Promise<SyncPullWindow>;
};

type LoggedSetMutationDatabase = Pick<ServerDatabase, "select" | "insert" | "update">;

export async function pushExerciseCategoriesInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: EXERCISE_CATEGORIES_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.exerciseCategories.userId,
        updatedAt: schema.exerciseCategories.updatedAt,
        deviceId: schema.exerciseCategories.deviceId
      })
      .from(schema.exerciseCategories)
      .where(eq(schema.exerciseCategories.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    // TENANT ISOLATION: a second user's push can never overwrite the
    // first user's row keyed by the same client PK.
    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.exerciseCategories).values(rowValues);
    } else {
      await transaction
        .update(schema.exerciseCategories)
        .set(rowValues)
        .where(eq(schema.exerciseCategories.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushNutritionGoalsInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: NUTRITION_GOALS_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.nutritionGoals.userId,
        updatedAt: schema.nutritionGoals.updatedAt,
        deviceId: schema.nutritionGoals.deviceId
      })
      .from(schema.nutritionGoals)
      .where(eq(schema.nutritionGoals.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    // TENANT ISOLATION: a second user's push can never overwrite the
    // first user's row keyed by the same client PK.
    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.nutritionGoals).values(rowValues);
    } else {
      await transaction
        .update(schema.nutritionGoals)
        .set(rowValues)
        .where(eq(schema.nutritionGoals.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

// The account-level Settings singleton. Structurally identical to
// nutrition goals — an opaque-payload LWW upsert keyed by the client id, with
// tenant isolation on write — the only difference being the well-known
// singleton id rather than a UUIDv7 list. `deleted_at` stays null (a settings
// row is overwritten, never archived), but the tombstone path is kept for
// rail uniformity.
export async function pushUserSettingsInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: USER_SETTINGS_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.userSettings.userId,
        updatedAt: schema.userSettings.updatedAt,
        deviceId: schema.userSettings.deviceId
      })
      .from(schema.userSettings)
      .where(eq(schema.userSettings.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    // TENANT ISOLATION: a second user's push can never overwrite the
    // first user's singleton keyed by the same well-known client id.
    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.userSettings).values(rowValues);
    } else {
      await transaction
        .update(schema.userSettings)
        .set(rowValues)
        .where(eq(schema.userSettings.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushExercisesInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: EXERCISES_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.exercises.userId,
        updatedAt: schema.exercises.updatedAt,
        deviceId: schema.exercises.deviceId
      })
      .from(schema.exercises)
      .where(eq(schema.exercises.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    // TENANT ISOLATION: a second user's push can never overwrite the
    // first user's row keyed by the same client PK.
    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.exercises).values(rowValues);
    } else {
      await transaction
        .update(schema.exercises)
        .set(rowValues)
        .where(eq(schema.exercises.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushLoggedSetsInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: LOGGED_SETS_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.loggedSets.userId,
        updatedAt: schema.loggedSets.updatedAt,
        deviceId: schema.loggedSets.deviceId
      })
      .from(schema.loggedSets)
      .where(eq(schema.loggedSets.id, change.id))
      .limit(1);
    const existing = existingRows[0];
    const gcMarker =
      existing === undefined
        ? (
            await transaction
              .select({
                tombstoneUpdatedAt:
                  schema.loggedSetTombstoneGcMarkers.tombstoneUpdatedAt,
                deviceId: schema.loggedSetTombstoneGcMarkers.deviceId
              })
              .from(schema.loggedSetTombstoneGcMarkers)
              .where(
                and(
                  eq(schema.loggedSetTombstoneGcMarkers.userId, userId),
                  eq(schema.loggedSetTombstoneGcMarkers.loggedSetId, change.id)
                )
              )
              .limit(1)
          )[0]
        : undefined;

    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      gcMarker !== undefined &&
      !lwwWins(
        updatedAt,
        deviceId,
        gcMarker.tombstoneUpdatedAt,
        gcMarker.deviceId
      )
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    if (existing === undefined) {
      await transaction.insert(schema.loggedSets).values({
        id: change.id,
        userId,
        deviceId,
        payload,
        updatedAt,
        deletedAt,
        receivedAt: serverClock
      });
    } else {
      await transaction
        .update(schema.loggedSets)
        .set({
          deviceId,
          payload,
          updatedAt,
          deletedAt,
          receivedAt: serverClock
        })
        .where(eq(schema.loggedSets.id, change.id));
    }

    await maybeRecordActivityLog(change);
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushFoodsInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: FOODS_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.foods.userId,
        updatedAt: schema.foods.updatedAt,
        deviceId: schema.foods.deviceId
      })
      .from(schema.foods)
      .where(eq(schema.foods.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    // TENANT ISOLATION: a second user's push can never overwrite the
    // first user's row keyed by the same client PK.
    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.foods).values(rowValues);
    } else {
      await transaction
        .update(schema.foods)
        .set(rowValues)
        .where(eq(schema.foods.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushMealTypesInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: MEAL_TYPES_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.mealTypes.userId,
        updatedAt: schema.mealTypes.updatedAt,
        deviceId: schema.mealTypes.deviceId
      })
      .from(schema.mealTypes)
      .where(eq(schema.mealTypes.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    // TENANT ISOLATION: a second user's push can never overwrite the
    // first user's row keyed by the same client PK.
    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.mealTypes).values(rowValues);
    } else {
      await transaction
        .update(schema.mealTypes)
        .set(rowValues)
        .where(eq(schema.mealTypes.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushMealsInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: MEALS_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.meals.userId,
        updatedAt: schema.meals.updatedAt,
        deviceId: schema.meals.deviceId
      })
      .from(schema.meals)
      .where(eq(schema.meals.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.meals).values(rowValues);
    } else {
      await transaction
        .update(schema.meals)
        .set(rowValues)
        .where(eq(schema.meals.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushFoodEntriesInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: FOOD_ENTRIES_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.foodEntries.userId,
        updatedAt: schema.foodEntries.updatedAt,
        deviceId: schema.foodEntries.deviceId
      })
      .from(schema.foodEntries)
      .where(eq(schema.foodEntries.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.foodEntries).values(rowValues);
    } else {
      await transaction
        .update(schema.foodEntries)
        .set(rowValues)
        .where(eq(schema.foodEntries.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushCompoundsInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: COMPOUNDS_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.compounds.userId,
        updatedAt: schema.compounds.updatedAt,
        deviceId: schema.compounds.deviceId
      })
      .from(schema.compounds)
      .where(eq(schema.compounds.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    // TENANT ISOLATION: a second user's push can never overwrite the
    // first user's row keyed by the same client PK.
    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.compounds).values(rowValues);
    } else {
      await transaction
        .update(schema.compounds)
        .set(rowValues)
        .where(eq(schema.compounds.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushDosesInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: DOSES_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.doses.userId,
        updatedAt: schema.doses.updatedAt,
        deviceId: schema.doses.deviceId
      })
      .from(schema.doses)
      .where(eq(schema.doses.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    // TENANT ISOLATION: never let a cross-user push overwrite an
    // existing Dose row keyed by the same client PK.
    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.doses).values(rowValues);
    } else {
      await transaction
        .update(schema.doses)
        .set(rowValues)
        .where(eq(schema.doses.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushProtocolsInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: PROTOCOLS_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.protocols.userId,
        updatedAt: schema.protocols.updatedAt,
        deviceId: schema.protocols.deviceId
      })
      .from(schema.protocols)
      .where(eq(schema.protocols.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    // TENANT ISOLATION: a second user's push can never overwrite the
    // first user's row keyed by the same client PK.
    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.protocols).values(rowValues);
    } else {
      await transaction
        .update(schema.protocols)
        .set(rowValues)
        .where(eq(schema.protocols.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushProtocolCompoundsInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: PROTOCOL_COMPOUNDS_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.protocolCompounds.userId,
        updatedAt: schema.protocolCompounds.updatedAt,
        deviceId: schema.protocolCompounds.deviceId
      })
      .from(schema.protocolCompounds)
      .where(eq(schema.protocolCompounds.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.protocolCompounds).values(rowValues);
    } else {
      await transaction
        .update(schema.protocolCompounds)
        .set(rowValues)
        .where(eq(schema.protocolCompounds.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushSchedulesInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: SCHEDULES_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.schedules.userId,
        updatedAt: schema.schedules.updatedAt,
        deviceId: schema.schedules.deviceId
      })
      .from(schema.schedules)
      .where(eq(schema.schedules.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.schedules).values(rowValues);
    } else {
      await transaction
        .update(schema.schedules)
        .set(rowValues)
        .where(eq(schema.schedules.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushProtocolTargetOutcomesInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: PROTOCOL_TARGET_OUTCOMES_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.protocolTargetOutcomes.userId,
        updatedAt: schema.protocolTargetOutcomes.updatedAt,
        deviceId: schema.protocolTargetOutcomes.deviceId
      })
      .from(schema.protocolTargetOutcomes)
      .where(eq(schema.protocolTargetOutcomes.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.protocolTargetOutcomes).values(rowValues);
    } else {
      await transaction
        .update(schema.protocolTargetOutcomes)
        .set(rowValues)
        .where(eq(schema.protocolTargetOutcomes.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushRoutinesInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: ROUTINES_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.routines.userId,
        updatedAt: schema.routines.updatedAt,
        deviceId: schema.routines.deviceId
      })
      .from(schema.routines)
      .where(eq(schema.routines.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    // TENANT ISOLATION: a second user's push can never overwrite the
    // first user's row keyed by the same client PK.
    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.routines).values(rowValues);
    } else {
      await transaction
        .update(schema.routines)
        .set(rowValues)
        .where(eq(schema.routines.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

type OpaqueSyncExistingRow = {
  userId: string;
  updatedAt: Date;
  deviceId: string;
};

type OpaqueSyncRowValues = {
  id: string;
  userId: string;
  deviceId: string;
  payload: Record<string, unknown>;
  updatedAt: Date;
  deletedAt: Date | null;
  receivedAt: Date;
};

async function pushOpaqueSyncRowsInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock,
    entityTable,
    readExisting,
    writeRow
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
    entityTable: SyncPullEntity;
    readExisting(id: string): Promise<OpaqueSyncExistingRow | undefined>;
    writeRow(
      existing: OpaqueSyncExistingRow | undefined,
      row: OpaqueSyncRowValues
    ): Promise<void>;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existing = await readExisting(change.id);

    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    await writeRow(existing, {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    });
    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushWorkoutSessionsInTransaction(
  transaction: LoggedSetMutationDatabase,
  input: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
) {
  return pushOpaqueSyncRowsInTransaction(transaction, {
    ...input,
    entityTable: WORKOUT_SESSIONS_SYNC_ENTITY,
    async readExisting(id) {
      const rows = await transaction
        .select({
          userId: schema.workoutSessions.userId,
          updatedAt: schema.workoutSessions.updatedAt,
          deviceId: schema.workoutSessions.deviceId
        })
        .from(schema.workoutSessions)
        .where(eq(schema.workoutSessions.id, id))
        .limit(1);
      return rows[0];
    },
    async writeRow(existing, row) {
      if (existing === undefined) {
        await transaction.insert(schema.workoutSessions).values(row);
      } else {
        await transaction
          .update(schema.workoutSessions)
          .set(row)
          .where(eq(schema.workoutSessions.id, row.id));
      }
    }
  });
}

export async function pushWorkoutExercisesInTransaction(
  transaction: LoggedSetMutationDatabase,
  input: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
) {
  return pushOpaqueSyncRowsInTransaction(transaction, {
    ...input,
    entityTable: WORKOUT_EXERCISES_SYNC_ENTITY,
    async readExisting(id) {
      const rows = await transaction
        .select({
          userId: schema.workoutExercises.userId,
          updatedAt: schema.workoutExercises.updatedAt,
          deviceId: schema.workoutExercises.deviceId
        })
        .from(schema.workoutExercises)
        .where(eq(schema.workoutExercises.id, id))
        .limit(1);
      return rows[0];
    },
    async writeRow(existing, row) {
      if (existing === undefined) {
        await transaction.insert(schema.workoutExercises).values(row);
      } else {
        await transaction
          .update(schema.workoutExercises)
          .set(row)
          .where(eq(schema.workoutExercises.id, row.id));
      }
    }
  });
}

export async function pushExerciseGroupsInTransaction(
  transaction: LoggedSetMutationDatabase,
  input: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
) {
  return pushOpaqueSyncRowsInTransaction(transaction, {
    ...input,
    entityTable: EXERCISE_GROUPS_SYNC_ENTITY,
    async readExisting(id) {
      const rows = await transaction
        .select({
          userId: schema.exerciseGroups.userId,
          updatedAt: schema.exerciseGroups.updatedAt,
          deviceId: schema.exerciseGroups.deviceId
        })
        .from(schema.exerciseGroups)
        .where(eq(schema.exerciseGroups.id, id))
        .limit(1);
      return rows[0];
    },
    async writeRow(existing, row) {
      if (existing === undefined) {
        await transaction.insert(schema.exerciseGroups).values(row);
      } else {
        await transaction
          .update(schema.exerciseGroups)
          .set(row)
          .where(eq(schema.exerciseGroups.id, row.id));
      }
    }
  });
}

export async function pushExerciseGroupMembersInTransaction(
  transaction: LoggedSetMutationDatabase,
  input: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
) {
  return pushOpaqueSyncRowsInTransaction(transaction, {
    ...input,
    entityTable: EXERCISE_GROUP_MEMBERS_SYNC_ENTITY,
    async readExisting(id) {
      const rows = await transaction
        .select({
          userId: schema.exerciseGroupMembers.userId,
          updatedAt: schema.exerciseGroupMembers.updatedAt,
          deviceId: schema.exerciseGroupMembers.deviceId
        })
        .from(schema.exerciseGroupMembers)
        .where(eq(schema.exerciseGroupMembers.id, id))
        .limit(1);
      return rows[0];
    },
    async writeRow(existing, row) {
      if (existing === undefined) {
        await transaction.insert(schema.exerciseGroupMembers).values(row);
      } else {
        await transaction
          .update(schema.exerciseGroupMembers)
          .set(row)
          .where(eq(schema.exerciseGroupMembers.id, row.id));
      }
    }
  });
}

export async function pushWorkoutTemplatesInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: WORKOUT_TEMPLATES_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.workoutTemplates.userId,
        updatedAt: schema.workoutTemplates.updatedAt,
        deviceId: schema.workoutTemplates.deviceId
      })
      .from(schema.workoutTemplates)
      .where(eq(schema.workoutTemplates.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    // TENANT ISOLATION: a second user's push can never overwrite the
    // first user's row keyed by the same client PK.
    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.workoutTemplates).values(rowValues);
    } else {
      await transaction
        .update(schema.workoutTemplates)
        .set(rowValues)
        .where(eq(schema.workoutTemplates.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushTemplateExercisesInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: TEMPLATE_EXERCISES_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.templateExercises.userId,
        updatedAt: schema.templateExercises.updatedAt,
        deviceId: schema.templateExercises.deviceId
      })
      .from(schema.templateExercises)
      .where(eq(schema.templateExercises.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    // TENANT ISOLATION: a second user's push can never overwrite the
    // first user's row keyed by the same client PK.
    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.templateExercises).values(rowValues);
    } else {
      await transaction
        .update(schema.templateExercises)
        .set(rowValues)
        .where(eq(schema.templateExercises.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushPrescriptionsInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: PRESCRIPTIONS_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.prescriptions.userId,
        updatedAt: schema.prescriptions.updatedAt,
        deviceId: schema.prescriptions.deviceId
      })
      .from(schema.prescriptions)
      .where(eq(schema.prescriptions.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    // TENANT ISOLATION: a second user's push can never overwrite the
    // first user's row keyed by the same client PK.
    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.prescriptions).values(rowValues);
    } else {
      await transaction
        .update(schema.prescriptions)
        .set(rowValues)
        .where(eq(schema.prescriptions.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushTemplateGroupsInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: TEMPLATE_GROUPS_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.templateGroups.userId,
        updatedAt: schema.templateGroups.updatedAt,
        deviceId: schema.templateGroups.deviceId
      })
      .from(schema.templateGroups)
      .where(eq(schema.templateGroups.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    // TENANT ISOLATION: a second user's push can never overwrite the
    // first user's row keyed by the same client PK.
    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.templateGroups).values(rowValues);
    } else {
      await transaction
        .update(schema.templateGroups)
        .set(rowValues)
        .where(eq(schema.templateGroups.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushTemplateGroupMembersInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: TEMPLATE_GROUP_MEMBERS_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.templateGroupMembers.userId,
        updatedAt: schema.templateGroupMembers.updatedAt,
        deviceId: schema.templateGroupMembers.deviceId
      })
      .from(schema.templateGroupMembers)
      .where(eq(schema.templateGroupMembers.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    // TENANT ISOLATION: a second user's push can never overwrite the
    // first user's row keyed by the same client PK.
    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.templateGroupMembers).values(rowValues);
    } else {
      await transaction
        .update(schema.templateGroupMembers)
        .set(rowValues)
        .where(eq(schema.templateGroupMembers.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushRoutineEntriesInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: ROUTINE_ENTRIES_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.routineEntries.userId,
        updatedAt: schema.routineEntries.updatedAt,
        deviceId: schema.routineEntries.deviceId
      })
      .from(schema.routineEntries)
      .where(eq(schema.routineEntries.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    // TENANT ISOLATION: a second user's push can never overwrite the
    // first user's row keyed by the same client PK.
    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.routineEntries).values(rowValues);
    } else {
      await transaction
        .update(schema.routineEntries)
        .set(rowValues)
        .where(eq(schema.routineEntries.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushTemplateLinksInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: TEMPLATE_LINKS_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.templateLinks.userId,
        updatedAt: schema.templateLinks.updatedAt,
        deviceId: schema.templateLinks.deviceId
      })
      .from(schema.templateLinks)
      .where(eq(schema.templateLinks.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    // TENANT ISOLATION: a second user's push can never overwrite the
    // first user's row keyed by the same client PK.
    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      payload,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.templateLinks).values(rowValues);
    } else {
      await transaction
        .update(schema.templateLinks)
        .set(rowValues)
        .where(eq(schema.templateLinks.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export async function pushIntegrationDataClassConsentsInTransaction(
  transaction: LoggedSetMutationDatabase,
  {
    userId,
    deviceId,
    changes,
    serverClock
  }: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
): Promise<SyncPushResult> {
  const acceptedIds: string[] = [];
  const applied: SyncAppliedChange[] = [];
  const maybeRecordActivityLog = async (change: SyncPushChange) => {
    if (!hasActivityLogEnvelope(change)) {
      return;
    }

    await transaction
      .insert(schema.activityLog)
      .values({
        id: change.activityLogId,
        userId,
        actor: change.actor,
        batchId: change.batchId,
        entityTable: INTEGRATION_DATA_CLASS_CONSENTS_SYNC_ENTITY,
        entityId: change.id,
        beforeImage: change.beforeImage,
        afterImage: change.afterImage,
        occurredAt: parseIsoDate(change.occurredAt, "occurredAt")
      })
      .onConflictDoNothing({ target: schema.activityLog.id });
  };

  for (const change of changes) {
    const parsedPayload = parseIntegrationConsentPayload(change.payload);
    const updatedAt = normalizeIncomingUpdatedAt(
      parseIsoDate(change.updatedAt, "updatedAt"),
      serverClock
    );
    const deletedAt =
      change.deletedAt === null
        ? null
        : parseIsoDate(change.deletedAt, "deletedAt");
    const payload = syncPayloadClock(change.payload, updatedAt, deletedAt);
    const existingRows = await transaction
      .select({
        userId: schema.integrationDataClassConsents.userId,
        updatedAt: schema.integrationDataClassConsents.updatedAt,
        deviceId: schema.integrationDataClassConsents.deviceId
      })
      .from(schema.integrationDataClassConsents)
      .where(eq(schema.integrationDataClassConsents.id, change.id))
      .limit(1);
    const existing = existingRows[0];

    if (existing !== undefined && existing.userId !== userId) {
      continue;
    }
    if (
      existing !== undefined &&
      !lwwWins(updatedAt, deviceId, existing.updatedAt, existing.deviceId)
    ) {
      await maybeRecordActivityLog(change);
      acceptedIds.push(change.id);
      continue;
    }

    const rowValues = {
      id: change.id,
      userId,
      deviceId,
      credentialId: parsedPayload.credentialId,
      dataClass: parsedPayload.dataClass,
      enabled: parsedPayload.enabled,
      updatedAt,
      deletedAt,
      receivedAt: serverClock
    };
    if (existing === undefined) {
      await transaction.insert(schema.integrationDataClassConsents).values(rowValues);
    } else {
      await transaction
        .update(schema.integrationDataClassConsents)
        .set(rowValues)
        .where(eq(schema.integrationDataClassConsents.id, change.id));
    }

    await maybeRecordActivityLog({ ...change, payload });
    acceptedIds.push(change.id);
    applied.push({
      id: change.id,
      updatedAt: updatedAt.toISOString(),
      deviceId
    });
  }

  return {
    accepted: acceptedIds,
    serverClock: serverClock.toISOString(),
    applied
  };
}

export function createDrizzleSyncStore(db: ServerDatabase): SyncStore {
  return {
    async verifyBearerToken(token) {
      const rows = await db
        .select({ userId: schema.session.userId })
        .from(schema.session)
        .innerJoin(schema.user, eq(schema.user.id, schema.session.userId))
        .where(
          and(
            eq(schema.session.token, token),
            gt(schema.session.expiresAt, new Date()),
            isNull(schema.user.deletionRequestedAt)
          )
        )
        .limit(1);

      return rows[0] ?? null;
    },
    async explainUnauthorizedBearerToken(token) {
      const rows = await db
        .select({ deletionRequestedAt: schema.user.deletionRequestedAt })
        .from(schema.session)
        .innerJoin(schema.user, eq(schema.user.id, schema.session.userId))
        .where(
          and(
            eq(schema.session.token, token),
            gt(schema.session.expiresAt, new Date())
          )
        )
        .limit(1);
      const row = rows[0];
      if (
        row?.deletionRequestedAt !== null &&
        row?.deletionRequestedAt !== undefined
      ) {
        return ACCOUNT_DELETION_LOCAL_ONLY_MESSAGE;
      }

      return null;
    },
    async pushExerciseCategories({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushExerciseCategoriesInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushExercises({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushExercisesInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushLoggedSets({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushLoggedSetsInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushFoods({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushFoodsInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushMealTypes({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushMealTypesInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushMeals({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushMealsInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushFoodEntries({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushFoodEntriesInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushCompounds({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushCompoundsInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushDoses({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushDosesInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushProtocols({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushProtocolsInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushProtocolCompounds({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushProtocolCompoundsInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushSchedules({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushSchedulesInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushProtocolTargetOutcomes({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushProtocolTargetOutcomesInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushNutritionGoals({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushNutritionGoalsInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushUserSettings({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushUserSettingsInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushIntegrationDataClassConsents({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushIntegrationDataClassConsentsInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushRoutines({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushRoutinesInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushWorkoutSessions({ userId, deviceId, changes }) {
      const serverClock = new Date();
      return db.transaction((transaction) =>
        pushWorkoutSessionsInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );
    },
    async pushWorkoutExercises({ userId, deviceId, changes }) {
      const serverClock = new Date();
      return db.transaction((transaction) =>
        pushWorkoutExercisesInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );
    },
    async pushExerciseGroups({ userId, deviceId, changes }) {
      const serverClock = new Date();
      return db.transaction((transaction) =>
        pushExerciseGroupsInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );
    },
    async pushExerciseGroupMembers({ userId, deviceId, changes }) {
      const serverClock = new Date();
      return db.transaction((transaction) =>
        pushExerciseGroupMembersInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );
    },
    async pushWorkoutTemplates({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushWorkoutTemplatesInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushTemplateExercises({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushTemplateExercisesInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushPrescriptions({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushPrescriptionsInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushTemplateGroups({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushTemplateGroupsInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushTemplateGroupMembers({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushTemplateGroupMembersInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushRoutineEntries({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushRoutineEntriesInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pushTemplateLinks({ userId, deviceId, changes }) {
      const serverClock = new Date();
      const result = await db.transaction((transaction) =>
        pushTemplateLinksInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        })
      );

      return result;
    },
    async pullChanges({ userId, cursor, limit, mode }) {
      const serverClock = new Date();
      const cursorPosition =
        cursor === null ? null : decodeSyncCursor(cursor);
      if (
        mode === SYNC_PULL_MODE_DELTA &&
        cursorPosition !== null &&
        cursorPosition.receivedAt.getTime() <
          serverClock.getTime() - SYNC_TOMBSTONE_RETENTION_MS
      ) {
        return {
          fullResyncRequired: true,
          changes: [],
          nextCursor: cursor,
          serverClock: serverClock.toISOString()
        };
      }

      const exerciseCategoryCursorFilter = pullCursorFilter(
        EXERCISE_CATEGORIES_SYNC_ENTITY,
        schema.exerciseCategories.receivedAt,
        schema.exerciseCategories.id,
        cursorPosition
      );
      const exerciseCursorFilter = pullCursorFilter(
        EXERCISES_SYNC_ENTITY,
        schema.exercises.receivedAt,
        schema.exercises.id,
        cursorPosition
      );
      const workoutSessionCursorFilter = pullCursorFilter(
        WORKOUT_SESSIONS_SYNC_ENTITY,
        schema.workoutSessions.receivedAt,
        schema.workoutSessions.id,
        cursorPosition
      );
      const workoutExerciseCursorFilter = pullCursorFilter(
        WORKOUT_EXERCISES_SYNC_ENTITY,
        schema.workoutExercises.receivedAt,
        schema.workoutExercises.id,
        cursorPosition
      );
      const exerciseGroupCursorFilter = pullCursorFilter(
        EXERCISE_GROUPS_SYNC_ENTITY,
        schema.exerciseGroups.receivedAt,
        schema.exerciseGroups.id,
        cursorPosition
      );
      const exerciseGroupMemberCursorFilter = pullCursorFilter(
        EXERCISE_GROUP_MEMBERS_SYNC_ENTITY,
        schema.exerciseGroupMembers.receivedAt,
        schema.exerciseGroupMembers.id,
        cursorPosition
      );
      const loggedSetCursorFilter = pullCursorFilter(
        LOGGED_SETS_SYNC_ENTITY,
        schema.loggedSets.receivedAt,
        schema.loggedSets.id,
        cursorPosition
      );
      const foodCursorFilter = pullCursorFilter(
        FOODS_SYNC_ENTITY,
        schema.foods.receivedAt,
        schema.foods.id,
        cursorPosition
      );
      const mealTypeCursorFilter = pullCursorFilter(
        MEAL_TYPES_SYNC_ENTITY,
        schema.mealTypes.receivedAt,
        schema.mealTypes.id,
        cursorPosition
      );
      const mealCursorFilter = pullCursorFilter(
        MEALS_SYNC_ENTITY,
        schema.meals.receivedAt,
        schema.meals.id,
        cursorPosition
      );
      const foodEntryCursorFilter = pullCursorFilter(
        FOOD_ENTRIES_SYNC_ENTITY,
        schema.foodEntries.receivedAt,
        schema.foodEntries.id,
        cursorPosition
      );
      const metricCursorFilter = pullCursorFilter(
        METRICS_SYNC_ENTITY,
        schema.metrics.receivedAt,
        schema.metrics.id,
        cursorPosition
      );
      const metricReadingCursorFilter = pullCursorFilter(
        METRIC_READINGS_SYNC_ENTITY,
        schema.metricReadings.receivedAt,
        schema.metricReadings.id,
        cursorPosition
      );
      const consentCursorFilter = pullCursorFilter(
        INTEGRATION_DATA_CLASS_CONSENTS_SYNC_ENTITY,
        schema.integrationDataClassConsents.receivedAt,
        schema.integrationDataClassConsents.id,
        cursorPosition
      );
      const compoundCursorFilter = pullCursorFilter(
        COMPOUNDS_SYNC_ENTITY,
        schema.compounds.receivedAt,
        schema.compounds.id,
        cursorPosition
      );
      const doseCursorFilter = pullCursorFilter(
        DOSES_SYNC_ENTITY,
        schema.doses.receivedAt,
        schema.doses.id,
        cursorPosition
      );
      const protocolCursorFilter = pullCursorFilter(
        PROTOCOLS_SYNC_ENTITY,
        schema.protocols.receivedAt,
        schema.protocols.id,
        cursorPosition
      );
      const protocolCompoundCursorFilter = pullCursorFilter(
        PROTOCOL_COMPOUNDS_SYNC_ENTITY,
        schema.protocolCompounds.receivedAt,
        schema.protocolCompounds.id,
        cursorPosition
      );
      const protocolTargetOutcomeCursorFilter = pullCursorFilter(
        PROTOCOL_TARGET_OUTCOMES_SYNC_ENTITY,
        schema.protocolTargetOutcomes.receivedAt,
        schema.protocolTargetOutcomes.id,
        cursorPosition
      );
      const scheduleCursorFilter = pullCursorFilter(
        SCHEDULES_SYNC_ENTITY,
        schema.schedules.receivedAt,
        schema.schedules.id,
        cursorPosition
      );
      const nutritionGoalCursorFilter = pullCursorFilter(
        NUTRITION_GOALS_SYNC_ENTITY,
        schema.nutritionGoals.receivedAt,
        schema.nutritionGoals.id,
        cursorPosition
      );
      const userSettingsCursorFilter = pullCursorFilter(
        USER_SETTINGS_SYNC_ENTITY,
        schema.userSettings.receivedAt,
        schema.userSettings.id,
        cursorPosition
      );
      const routineCursorFilter = pullCursorFilter(
        ROUTINES_SYNC_ENTITY,
        schema.routines.receivedAt,
        schema.routines.id,
        cursorPosition
      );
      const workoutTemplateCursorFilter = pullCursorFilter(
        WORKOUT_TEMPLATES_SYNC_ENTITY,
        schema.workoutTemplates.receivedAt,
        schema.workoutTemplates.id,
        cursorPosition
      );
      const templateExerciseCursorFilter = pullCursorFilter(
        TEMPLATE_EXERCISES_SYNC_ENTITY,
        schema.templateExercises.receivedAt,
        schema.templateExercises.id,
        cursorPosition
      );
      const prescriptionCursorFilter = pullCursorFilter(
        PRESCRIPTIONS_SYNC_ENTITY,
        schema.prescriptions.receivedAt,
        schema.prescriptions.id,
        cursorPosition
      );
      const templateGroupCursorFilter = pullCursorFilter(
        TEMPLATE_GROUPS_SYNC_ENTITY,
        schema.templateGroups.receivedAt,
        schema.templateGroups.id,
        cursorPosition
      );
      const templateGroupMemberCursorFilter = pullCursorFilter(
        TEMPLATE_GROUP_MEMBERS_SYNC_ENTITY,
        schema.templateGroupMembers.receivedAt,
        schema.templateGroupMembers.id,
        cursorPosition
      );
      const routineEntryCursorFilter = pullCursorFilter(
        ROUTINE_ENTRIES_SYNC_ENTITY,
        schema.routineEntries.receivedAt,
        schema.routineEntries.id,
        cursorPosition
      );
      const templateLinkCursorFilter = pullCursorFilter(
        TEMPLATE_LINKS_SYNC_ENTITY,
        schema.templateLinks.receivedAt,
        schema.templateLinks.id,
        cursorPosition
      );
      const liveExerciseCategorySnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.exerciseCategories.deletedAt)
          : undefined;
      const liveExerciseSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.exercises.deletedAt)
          : undefined;
      const liveWorkoutSessionSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.workoutSessions.deletedAt)
          : undefined;
      const liveWorkoutExerciseSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.workoutExercises.deletedAt)
          : undefined;
      const liveExerciseGroupSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.exerciseGroups.deletedAt)
          : undefined;
      const liveExerciseGroupMemberSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.exerciseGroupMembers.deletedAt)
          : undefined;
      const liveLoggedSetSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.loggedSets.deletedAt)
          : undefined;
      const liveFoodSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT ? isNull(schema.foods.deletedAt) : undefined;
      const liveMealTypeSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.mealTypes.deletedAt)
          : undefined;
      const liveMealSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT ? isNull(schema.meals.deletedAt) : undefined;
      const liveFoodEntrySnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.foodEntries.deletedAt)
          : undefined;
      const liveMetricSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.metrics.deletedAt)
          : undefined;
      const liveMetricReadingSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.metricReadings.deletedAt)
          : undefined;
      const liveConsentSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.integrationDataClassConsents.deletedAt)
          : undefined;
      const liveCompoundSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.compounds.deletedAt)
          : undefined;
      const liveDoseSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT ? isNull(schema.doses.deletedAt) : undefined;
      const liveProtocolSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.protocols.deletedAt)
          : undefined;
      const liveProtocolCompoundSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.protocolCompounds.deletedAt)
          : undefined;
      const liveProtocolTargetOutcomeSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.protocolTargetOutcomes.deletedAt)
          : undefined;
      const liveScheduleSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.schedules.deletedAt)
          : undefined;
      const liveNutritionGoalSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.nutritionGoals.deletedAt)
          : undefined;
      const liveUserSettingsSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.userSettings.deletedAt)
          : undefined;
      const liveRoutineSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.routines.deletedAt)
          : undefined;
      const liveWorkoutTemplateSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.workoutTemplates.deletedAt)
          : undefined;
      const liveTemplateExerciseSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.templateExercises.deletedAt)
          : undefined;
      const livePrescriptionSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.prescriptions.deletedAt)
          : undefined;
      const liveTemplateGroupSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.templateGroups.deletedAt)
          : undefined;
      const liveTemplateGroupMemberSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.templateGroupMembers.deletedAt)
          : undefined;
      const liveRoutineEntrySnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.routineEntries.deletedAt)
          : undefined;
      const liveTemplateLinkSnapshotFilter =
        mode === SYNC_PULL_MODE_SNAPSHOT
          ? isNull(schema.templateLinks.deletedAt)
          : undefined;
      const exerciseCategoryRows = await db
        .select({
          id: schema.exerciseCategories.id,
          deviceId: schema.exerciseCategories.deviceId,
          payload: schema.exerciseCategories.payload,
          updatedAt: schema.exerciseCategories.updatedAt,
          deletedAt: schema.exerciseCategories.deletedAt,
          receivedAt: schema.exerciseCategories.receivedAt
        })
        .from(schema.exerciseCategories)
        .where(
          and(
            eq(schema.exerciseCategories.userId, userId),
            liveExerciseCategorySnapshotFilter,
            exerciseCategoryCursorFilter
          )
        )
        .orderBy(
          asc(schema.exerciseCategories.receivedAt),
          asc(schema.exerciseCategories.id)
        )
        .limit(limit);
      const exerciseRows = await db
        .select({
          id: schema.exercises.id,
          deviceId: schema.exercises.deviceId,
          payload: schema.exercises.payload,
          updatedAt: schema.exercises.updatedAt,
          deletedAt: schema.exercises.deletedAt,
          receivedAt: schema.exercises.receivedAt
        })
        .from(schema.exercises)
        .where(
          and(
            eq(schema.exercises.userId, userId),
            liveExerciseSnapshotFilter,
            exerciseCursorFilter
          )
        )
        .orderBy(asc(schema.exercises.receivedAt), asc(schema.exercises.id))
        .limit(limit);
      const workoutSessionRows = await db
        .select({
          id: schema.workoutSessions.id,
          deviceId: schema.workoutSessions.deviceId,
          payload: schema.workoutSessions.payload,
          updatedAt: schema.workoutSessions.updatedAt,
          deletedAt: schema.workoutSessions.deletedAt,
          receivedAt: schema.workoutSessions.receivedAt
        })
        .from(schema.workoutSessions)
        .where(
          and(
            eq(schema.workoutSessions.userId, userId),
            liveWorkoutSessionSnapshotFilter,
            workoutSessionCursorFilter
          )
        )
        .orderBy(
          asc(schema.workoutSessions.receivedAt),
          asc(schema.workoutSessions.id)
        )
        .limit(limit);
      const workoutExerciseRows = await db
        .select({
          id: schema.workoutExercises.id,
          deviceId: schema.workoutExercises.deviceId,
          payload: schema.workoutExercises.payload,
          updatedAt: schema.workoutExercises.updatedAt,
          deletedAt: schema.workoutExercises.deletedAt,
          receivedAt: schema.workoutExercises.receivedAt
        })
        .from(schema.workoutExercises)
        .where(
          and(
            eq(schema.workoutExercises.userId, userId),
            liveWorkoutExerciseSnapshotFilter,
            workoutExerciseCursorFilter
          )
        )
        .orderBy(
          asc(schema.workoutExercises.receivedAt),
          asc(schema.workoutExercises.id)
        )
        .limit(limit);
      const exerciseGroupRows = await db
        .select({
          id: schema.exerciseGroups.id,
          deviceId: schema.exerciseGroups.deviceId,
          payload: schema.exerciseGroups.payload,
          updatedAt: schema.exerciseGroups.updatedAt,
          deletedAt: schema.exerciseGroups.deletedAt,
          receivedAt: schema.exerciseGroups.receivedAt
        })
        .from(schema.exerciseGroups)
        .where(
          and(
            eq(schema.exerciseGroups.userId, userId),
            liveExerciseGroupSnapshotFilter,
            exerciseGroupCursorFilter
          )
        )
        .orderBy(
          asc(schema.exerciseGroups.receivedAt),
          asc(schema.exerciseGroups.id)
        )
        .limit(limit);
      const exerciseGroupMemberRows = await db
        .select({
          id: schema.exerciseGroupMembers.id,
          deviceId: schema.exerciseGroupMembers.deviceId,
          payload: schema.exerciseGroupMembers.payload,
          updatedAt: schema.exerciseGroupMembers.updatedAt,
          deletedAt: schema.exerciseGroupMembers.deletedAt,
          receivedAt: schema.exerciseGroupMembers.receivedAt
        })
        .from(schema.exerciseGroupMembers)
        .where(
          and(
            eq(schema.exerciseGroupMembers.userId, userId),
            liveExerciseGroupMemberSnapshotFilter,
            exerciseGroupMemberCursorFilter
          )
        )
        .orderBy(
          asc(schema.exerciseGroupMembers.receivedAt),
          asc(schema.exerciseGroupMembers.id)
        )
        .limit(limit);
      const loggedSetRows = await db
        .select({
          id: schema.loggedSets.id,
          deviceId: schema.loggedSets.deviceId,
          payload: schema.loggedSets.payload,
          updatedAt: schema.loggedSets.updatedAt,
          deletedAt: schema.loggedSets.deletedAt,
          receivedAt: schema.loggedSets.receivedAt
        })
        .from(schema.loggedSets)
        .where(
          and(
            eq(schema.loggedSets.userId, userId),
            liveLoggedSetSnapshotFilter,
            loggedSetCursorFilter
          )
        )
        .orderBy(asc(schema.loggedSets.receivedAt), asc(schema.loggedSets.id))
        .limit(limit);
      const foodRows = await db
        .select({
          id: schema.foods.id,
          deviceId: schema.foods.deviceId,
          payload: schema.foods.payload,
          updatedAt: schema.foods.updatedAt,
          deletedAt: schema.foods.deletedAt,
          receivedAt: schema.foods.receivedAt
        })
        .from(schema.foods)
        .where(
          and(
            eq(schema.foods.userId, userId),
            liveFoodSnapshotFilter,
            foodCursorFilter
          )
        )
        .orderBy(asc(schema.foods.receivedAt), asc(schema.foods.id))
        .limit(limit);
      const mealTypeRows = await db
        .select({
          id: schema.mealTypes.id,
          deviceId: schema.mealTypes.deviceId,
          payload: schema.mealTypes.payload,
          updatedAt: schema.mealTypes.updatedAt,
          deletedAt: schema.mealTypes.deletedAt,
          receivedAt: schema.mealTypes.receivedAt
        })
        .from(schema.mealTypes)
        .where(
          and(
            eq(schema.mealTypes.userId, userId),
            liveMealTypeSnapshotFilter,
            mealTypeCursorFilter
          )
        )
        .orderBy(asc(schema.mealTypes.receivedAt), asc(schema.mealTypes.id))
        .limit(limit);
      const mealRows = await db
        .select({
          id: schema.meals.id,
          deviceId: schema.meals.deviceId,
          payload: schema.meals.payload,
          updatedAt: schema.meals.updatedAt,
          deletedAt: schema.meals.deletedAt,
          receivedAt: schema.meals.receivedAt
        })
        .from(schema.meals)
        .where(
          and(
            eq(schema.meals.userId, userId),
            liveMealSnapshotFilter,
            mealCursorFilter
          )
        )
        .orderBy(asc(schema.meals.receivedAt), asc(schema.meals.id))
        .limit(limit);
      const foodEntryRows = await db
        .select({
          id: schema.foodEntries.id,
          deviceId: schema.foodEntries.deviceId,
          payload: schema.foodEntries.payload,
          updatedAt: schema.foodEntries.updatedAt,
          deletedAt: schema.foodEntries.deletedAt,
          receivedAt: schema.foodEntries.receivedAt
        })
        .from(schema.foodEntries)
        .where(
          and(
            eq(schema.foodEntries.userId, userId),
            liveFoodEntrySnapshotFilter,
            foodEntryCursorFilter
          )
        )
        .orderBy(asc(schema.foodEntries.receivedAt), asc(schema.foodEntries.id))
        .limit(limit);
      const metricRows = await db
        .select({
          id: schema.metrics.id,
          deviceId: schema.metrics.deviceId,
          name: schema.metrics.name,
          unit: schema.metrics.unit,
          valueShape: schema.metrics.valueShape,
          metricGroup: schema.metrics.metricGroup,
          goalType: schema.metrics.goalType,
          goalTargetValue: schema.metrics.goalTargetValue,
          enabled: schema.metrics.enabled,
          pinned: schema.metrics.pinned,
          sortOrder: schema.metrics.sortOrder,
          updatedAt: schema.metrics.updatedAt,
          deletedAt: schema.metrics.deletedAt,
          receivedAt: schema.metrics.receivedAt
        })
        .from(schema.metrics)
        .where(
          and(
            eq(schema.metrics.userId, userId),
            liveMetricSnapshotFilter,
            metricCursorFilter
          )
        )
        .orderBy(asc(schema.metrics.receivedAt), asc(schema.metrics.id))
        .limit(limit);
      const metricReadingRows = await db
        .select({
          id: schema.metricReadings.id,
          deviceId: schema.metricReadings.deviceId,
          metricId: schema.metricReadings.metricId,
          externalActivityId: schema.metricReadings.externalActivityId,
          valueJson: schema.metricReadings.valueJson,
          scalarValue: schema.metricReadings.scalarValue,
          scalarEntered: schema.metricReadings.scalarEntered,
          atTime: schema.metricReadings.atTime,
          windowStartedAt: schema.metricReadings.windowStartedAt,
          windowEndedAt: schema.metricReadings.windowEndedAt,
          provenance: schema.metricReadings.provenance,
          source: schema.metricReadings.source,
          externalId: schema.metricReadings.externalId,
          comment: schema.metricReadings.comment,
          updatedAt: schema.metricReadings.updatedAt,
          deletedAt: schema.metricReadings.deletedAt,
          receivedAt: schema.metricReadings.receivedAt
        })
        .from(schema.metricReadings)
        .where(
          and(
            eq(schema.metricReadings.userId, userId),
            liveMetricReadingSnapshotFilter,
            metricReadingCursorFilter
          )
        )
        .orderBy(
          asc(schema.metricReadings.receivedAt),
          asc(schema.metricReadings.id)
        )
        .limit(limit);
      const consentRows = await db
        .select({
          id: schema.integrationDataClassConsents.id,
          deviceId: schema.integrationDataClassConsents.deviceId,
          credentialId: schema.integrationDataClassConsents.credentialId,
          dataClass: schema.integrationDataClassConsents.dataClass,
          enabled: schema.integrationDataClassConsents.enabled,
          updatedAt: schema.integrationDataClassConsents.updatedAt,
          deletedAt: schema.integrationDataClassConsents.deletedAt,
          receivedAt: schema.integrationDataClassConsents.receivedAt
        })
        .from(schema.integrationDataClassConsents)
        .where(
          and(
            eq(schema.integrationDataClassConsents.userId, userId),
            liveConsentSnapshotFilter,
            consentCursorFilter
          )
        )
        .orderBy(
          asc(schema.integrationDataClassConsents.receivedAt),
          asc(schema.integrationDataClassConsents.id)
        )
        .limit(limit);
      const compoundRows = await db
        .select({
          id: schema.compounds.id,
          deviceId: schema.compounds.deviceId,
          payload: schema.compounds.payload,
          updatedAt: schema.compounds.updatedAt,
          deletedAt: schema.compounds.deletedAt,
          receivedAt: schema.compounds.receivedAt
        })
        .from(schema.compounds)
        .where(
          and(
            eq(schema.compounds.userId, userId),
            liveCompoundSnapshotFilter,
            compoundCursorFilter
          )
        )
        .orderBy(asc(schema.compounds.receivedAt), asc(schema.compounds.id))
        .limit(limit);
      const doseRows = await db
        .select({
          id: schema.doses.id,
          deviceId: schema.doses.deviceId,
          payload: schema.doses.payload,
          updatedAt: schema.doses.updatedAt,
          deletedAt: schema.doses.deletedAt,
          receivedAt: schema.doses.receivedAt
        })
        .from(schema.doses)
        .where(
          and(
            eq(schema.doses.userId, userId),
            liveDoseSnapshotFilter,
            doseCursorFilter
          )
        )
        .orderBy(asc(schema.doses.receivedAt), asc(schema.doses.id))
        .limit(limit);
      const protocolRows = await db
        .select({
          id: schema.protocols.id,
          deviceId: schema.protocols.deviceId,
          payload: schema.protocols.payload,
          updatedAt: schema.protocols.updatedAt,
          deletedAt: schema.protocols.deletedAt,
          receivedAt: schema.protocols.receivedAt
        })
        .from(schema.protocols)
        .where(
          and(
            eq(schema.protocols.userId, userId),
            liveProtocolSnapshotFilter,
            protocolCursorFilter
          )
        )
        .orderBy(asc(schema.protocols.receivedAt), asc(schema.protocols.id))
        .limit(limit);
      const protocolCompoundRows = await db
        .select({
          id: schema.protocolCompounds.id,
          deviceId: schema.protocolCompounds.deviceId,
          payload: schema.protocolCompounds.payload,
          updatedAt: schema.protocolCompounds.updatedAt,
          deletedAt: schema.protocolCompounds.deletedAt,
          receivedAt: schema.protocolCompounds.receivedAt
        })
        .from(schema.protocolCompounds)
        .where(
          and(
            eq(schema.protocolCompounds.userId, userId),
            liveProtocolCompoundSnapshotFilter,
            protocolCompoundCursorFilter
          )
        )
        .orderBy(
          asc(schema.protocolCompounds.receivedAt),
          asc(schema.protocolCompounds.id)
        )
        .limit(limit);
      const protocolTargetOutcomeRows = await db
        .select({
          id: schema.protocolTargetOutcomes.id,
          deviceId: schema.protocolTargetOutcomes.deviceId,
          payload: schema.protocolTargetOutcomes.payload,
          updatedAt: schema.protocolTargetOutcomes.updatedAt,
          deletedAt: schema.protocolTargetOutcomes.deletedAt,
          receivedAt: schema.protocolTargetOutcomes.receivedAt
        })
        .from(schema.protocolTargetOutcomes)
        .where(
          and(
            eq(schema.protocolTargetOutcomes.userId, userId),
            liveProtocolTargetOutcomeSnapshotFilter,
            protocolTargetOutcomeCursorFilter
          )
        )
        .orderBy(
          asc(schema.protocolTargetOutcomes.receivedAt),
          asc(schema.protocolTargetOutcomes.id)
        )
        .limit(limit);
      const scheduleRows = await db
        .select({
          id: schema.schedules.id,
          deviceId: schema.schedules.deviceId,
          payload: schema.schedules.payload,
          updatedAt: schema.schedules.updatedAt,
          deletedAt: schema.schedules.deletedAt,
          receivedAt: schema.schedules.receivedAt
        })
        .from(schema.schedules)
        .where(
          and(
            eq(schema.schedules.userId, userId),
            liveScheduleSnapshotFilter,
            scheduleCursorFilter
          )
        )
        .orderBy(asc(schema.schedules.receivedAt), asc(schema.schedules.id))
        .limit(limit);
      const nutritionGoalRows = await db
        .select({
          id: schema.nutritionGoals.id,
          deviceId: schema.nutritionGoals.deviceId,
          payload: schema.nutritionGoals.payload,
          updatedAt: schema.nutritionGoals.updatedAt,
          deletedAt: schema.nutritionGoals.deletedAt,
          receivedAt: schema.nutritionGoals.receivedAt
        })
        .from(schema.nutritionGoals)
        .where(
          and(
            eq(schema.nutritionGoals.userId, userId),
            liveNutritionGoalSnapshotFilter,
            nutritionGoalCursorFilter
          )
        )
        .orderBy(
          asc(schema.nutritionGoals.receivedAt),
          asc(schema.nutritionGoals.id)
        )
        .limit(limit);
      const userSettingsRows = await db
        .select({
          id: schema.userSettings.id,
          deviceId: schema.userSettings.deviceId,
          payload: schema.userSettings.payload,
          updatedAt: schema.userSettings.updatedAt,
          deletedAt: schema.userSettings.deletedAt,
          receivedAt: schema.userSettings.receivedAt
        })
        .from(schema.userSettings)
        .where(
          and(
            eq(schema.userSettings.userId, userId),
            liveUserSettingsSnapshotFilter,
            userSettingsCursorFilter
          )
        )
        .orderBy(
          asc(schema.userSettings.receivedAt),
          asc(schema.userSettings.id)
        )
        .limit(limit);
      const routineRows = await db
        .select({
          id: schema.routines.id,
          deviceId: schema.routines.deviceId,
          payload: schema.routines.payload,
          updatedAt: schema.routines.updatedAt,
          deletedAt: schema.routines.deletedAt,
          receivedAt: schema.routines.receivedAt
        })
        .from(schema.routines)
        .where(
          and(
            eq(schema.routines.userId, userId),
            liveRoutineSnapshotFilter,
            routineCursorFilter
          )
        )
        .orderBy(asc(schema.routines.receivedAt), asc(schema.routines.id))
        .limit(limit);
      const workoutTemplateRows = await db
        .select({
          id: schema.workoutTemplates.id,
          deviceId: schema.workoutTemplates.deviceId,
          payload: schema.workoutTemplates.payload,
          updatedAt: schema.workoutTemplates.updatedAt,
          deletedAt: schema.workoutTemplates.deletedAt,
          receivedAt: schema.workoutTemplates.receivedAt
        })
        .from(schema.workoutTemplates)
        .where(
          and(
            eq(schema.workoutTemplates.userId, userId),
            liveWorkoutTemplateSnapshotFilter,
            workoutTemplateCursorFilter
          )
        )
        .orderBy(asc(schema.workoutTemplates.receivedAt), asc(schema.workoutTemplates.id))
        .limit(limit);
      const templateExerciseRows = await db
        .select({
          id: schema.templateExercises.id,
          deviceId: schema.templateExercises.deviceId,
          payload: schema.templateExercises.payload,
          updatedAt: schema.templateExercises.updatedAt,
          deletedAt: schema.templateExercises.deletedAt,
          receivedAt: schema.templateExercises.receivedAt
        })
        .from(schema.templateExercises)
        .where(
          and(
            eq(schema.templateExercises.userId, userId),
            liveTemplateExerciseSnapshotFilter,
            templateExerciseCursorFilter
          )
        )
        .orderBy(asc(schema.templateExercises.receivedAt), asc(schema.templateExercises.id))
        .limit(limit);
      const prescriptionRows = await db
        .select({
          id: schema.prescriptions.id,
          deviceId: schema.prescriptions.deviceId,
          payload: schema.prescriptions.payload,
          updatedAt: schema.prescriptions.updatedAt,
          deletedAt: schema.prescriptions.deletedAt,
          receivedAt: schema.prescriptions.receivedAt
        })
        .from(schema.prescriptions)
        .where(
          and(
            eq(schema.prescriptions.userId, userId),
            livePrescriptionSnapshotFilter,
            prescriptionCursorFilter
          )
        )
        .orderBy(asc(schema.prescriptions.receivedAt), asc(schema.prescriptions.id))
        .limit(limit);
      const templateGroupRows = await db
        .select({
          id: schema.templateGroups.id,
          deviceId: schema.templateGroups.deviceId,
          payload: schema.templateGroups.payload,
          updatedAt: schema.templateGroups.updatedAt,
          deletedAt: schema.templateGroups.deletedAt,
          receivedAt: schema.templateGroups.receivedAt
        })
        .from(schema.templateGroups)
        .where(
          and(
            eq(schema.templateGroups.userId, userId),
            liveTemplateGroupSnapshotFilter,
            templateGroupCursorFilter
          )
        )
        .orderBy(asc(schema.templateGroups.receivedAt), asc(schema.templateGroups.id))
        .limit(limit);
      const templateGroupMemberRows = await db
        .select({
          id: schema.templateGroupMembers.id,
          deviceId: schema.templateGroupMembers.deviceId,
          payload: schema.templateGroupMembers.payload,
          updatedAt: schema.templateGroupMembers.updatedAt,
          deletedAt: schema.templateGroupMembers.deletedAt,
          receivedAt: schema.templateGroupMembers.receivedAt
        })
        .from(schema.templateGroupMembers)
        .where(
          and(
            eq(schema.templateGroupMembers.userId, userId),
            liveTemplateGroupMemberSnapshotFilter,
            templateGroupMemberCursorFilter
          )
        )
        .orderBy(asc(schema.templateGroupMembers.receivedAt), asc(schema.templateGroupMembers.id))
        .limit(limit);
      const routineEntryRows = await db
        .select({
          id: schema.routineEntries.id,
          deviceId: schema.routineEntries.deviceId,
          payload: schema.routineEntries.payload,
          updatedAt: schema.routineEntries.updatedAt,
          deletedAt: schema.routineEntries.deletedAt,
          receivedAt: schema.routineEntries.receivedAt
        })
        .from(schema.routineEntries)
        .where(
          and(
            eq(schema.routineEntries.userId, userId),
            liveRoutineEntrySnapshotFilter,
            routineEntryCursorFilter
          )
        )
        .orderBy(
          asc(schema.routineEntries.receivedAt),
          asc(schema.routineEntries.id)
        )
        .limit(limit);
      const templateLinkRows = await db
        .select({
          id: schema.templateLinks.id,
          deviceId: schema.templateLinks.deviceId,
          payload: schema.templateLinks.payload,
          updatedAt: schema.templateLinks.updatedAt,
          deletedAt: schema.templateLinks.deletedAt,
          receivedAt: schema.templateLinks.receivedAt
        })
        .from(schema.templateLinks)
        .where(
          and(
            eq(schema.templateLinks.userId, userId),
            liveTemplateLinkSnapshotFilter,
            templateLinkCursorFilter
          )
        )
        .orderBy(
          asc(schema.templateLinks.receivedAt),
          asc(schema.templateLinks.id)
        )
        .limit(limit);
      const baseRows: PullRow[] = [
        ...exerciseCategoryRows.map((row): PullRow => ({
          entity: EXERCISE_CATEGORIES_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...exerciseRows.map((row): PullRow => ({
          entity: EXERCISES_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...workoutSessionRows.map((row): PullRow => ({
          entity: WORKOUT_SESSIONS_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...workoutExerciseRows.map((row): PullRow => ({
          entity: WORKOUT_EXERCISES_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...exerciseGroupRows.map((row): PullRow => ({
          entity: EXERCISE_GROUPS_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...exerciseGroupMemberRows.map((row): PullRow => ({
          entity: EXERCISE_GROUP_MEMBERS_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...loggedSetRows.map((row): PullRow => ({
          entity: LOGGED_SETS_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...foodRows.map((row): PullRow => ({
          entity: FOODS_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...mealTypeRows.map((row): PullRow => ({
          entity: MEAL_TYPES_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...mealRows.map((row): PullRow => ({
          entity: MEALS_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...foodEntryRows.map((row): PullRow => ({
          entity: FOOD_ENTRIES_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...metricRows.map((row): PullRow => ({
          entity: METRICS_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: metricSyncPayload(row),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...metricReadingRows.map((row): PullRow => ({
          entity: METRIC_READINGS_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: metricReadingSyncPayload(row),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...consentRows.map((row): PullRow => ({
          entity: INTEGRATION_DATA_CLASS_CONSENTS_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: integrationConsentSyncPayload(row),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...compoundRows.map((row): PullRow => ({
          entity: COMPOUNDS_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...doseRows.map((row): PullRow => ({
          entity: DOSES_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...protocolRows.map((row): PullRow => ({
          entity: PROTOCOLS_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...protocolCompoundRows.map((row): PullRow => ({
          entity: PROTOCOL_COMPOUNDS_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...protocolTargetOutcomeRows.map((row): PullRow => ({
          entity: PROTOCOL_TARGET_OUTCOMES_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...scheduleRows.map((row): PullRow => ({
          entity: SCHEDULES_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...nutritionGoalRows.map((row): PullRow => ({
          entity: NUTRITION_GOALS_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...userSettingsRows.map((row): PullRow => ({
          entity: USER_SETTINGS_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...routineRows.map((row): PullRow => ({
          entity: ROUTINES_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...workoutTemplateRows.map((row): PullRow => ({
          entity: WORKOUT_TEMPLATES_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...templateExerciseRows.map((row): PullRow => ({
          entity: TEMPLATE_EXERCISES_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...prescriptionRows.map((row): PullRow => ({
          entity: PRESCRIPTIONS_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...templateGroupRows.map((row): PullRow => ({
          entity: TEMPLATE_GROUPS_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...templateGroupMemberRows.map((row): PullRow => ({
          entity: TEMPLATE_GROUP_MEMBERS_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...routineEntryRows.map((row): PullRow => ({
          entity: ROUTINE_ENTRIES_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        })),
        ...templateLinkRows.map((row): PullRow => ({
          entity: TEMPLATE_LINKS_SYNC_ENTITY,
          id: row.id,
          deviceId: row.deviceId,
          payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          receivedAt: row.receivedAt
        }))
      ]
        .sort(comparePullRows)
        .filter(
          (row) =>
            cursorPosition === null ||
            comparePullRowToCursor(row, cursorPosition) > 0
        )
        .slice(0, limit);
      const lastRow = baseRows.at(-1);
      const rows = await withWorkoutStructurePullDependencies(
        db,
        userId,
        baseRows
      );
      const payloadsById = new Map(
        rows.map((row) => [
          pullEnvelopeKey(row.entity, row.id),
          row.payload
        ])
      );
      const envelopesById = await matchingActivityLogEnvelopesForPull(db, {
        userId,
        payloadsById
      });

      return {
        fullResyncRequired: false,
        changes: rows.map((row) => {
          const key = pullEnvelopeKey(row.entity, row.id);
          const payload = payloadsById.get(key)!;
          const envelope = envelopesById.get(key);
          return {
            entity: row.entity,
            id: row.id,
            deviceId: row.deviceId,
            payload,
            updatedAt: row.updatedAt.toISOString(),
            deletedAt: row.deletedAt?.toISOString() ?? null,
            ...(envelope === undefined
              ? {}
              : {
                  activityLogId: envelope.id,
                  actor: envelope.actor,
                  batchId: envelope.batchId,
                  beforeImage: envelope.beforeImage,
                  afterImage: envelope.afterImage,
                  occurredAt: envelope.occurredAt.toISOString()
                })
          };
        }),
        nextCursor:
          lastRow === undefined
            ? cursor
            : encodeSyncCursor(
                lastRow.receivedAt,
                lastRow.entity,
                lastRow.id
              ),
        serverClock: serverClock.toISOString()
      };
    }
  };
}

const MAX_FUTURE_CLOCK_SKEW_MS = 5 * 60 * 1000;

export function normalizeIncomingUpdatedAt(
  updatedAt: Date,
  serverClock: Date
) {
  const maxAcceptedTime =
    serverClock.getTime() + MAX_FUTURE_CLOCK_SKEW_MS;
  if (updatedAt.getTime() > maxAcceptedTime) {
    return serverClock;
  }

  return updatedAt;
}

function lwwWins(
  incomingUpdatedAt: Date,
  incomingDeviceId: string,
  existingUpdatedAt: Date,
  existingDeviceId: string
) {
  const timestampComparison =
    incomingUpdatedAt.getTime() - existingUpdatedAt.getTime();
  if (timestampComparison !== 0) {
    return timestampComparison > 0;
  }

  return incomingDeviceId > existingDeviceId;
}

function syncPayloadClock(
  payload: Record<string, unknown>,
  updatedAt: Date,
  deletedAt: Date | null
): Record<string, unknown> {
  return {
    ...payload,
    updated_at: updatedAt.toISOString(),
    deleted_at: deletedAt?.toISOString() ?? null
  };
}

type PullRow = {
  entity: SyncPullEntity;
  id: string;
  deviceId: string;
  payload: Record<string, unknown>;
  updatedAt: Date;
  deletedAt: Date | null;
  receivedAt: Date;
};

type OpaquePullRow = {
  id: string;
  deviceId: string;
  payload: Record<string, unknown>;
  updatedAt: Date;
  deletedAt: Date | null;
  receivedAt: Date;
};

const WORKOUT_STRUCTURE_PULL_ENTITIES = new Set<SyncPullEntity>([
  WORKOUT_EXERCISES_SYNC_ENTITY,
  EXERCISE_GROUPS_SYNC_ENTITY,
  EXERCISE_GROUP_MEMBERS_SYNC_ENTITY
]);

/**
 * Pull cursors order by receive time, not foreign-key topology. Include the
 * exact ancestors needed by structure rows in this bounded base page so a
 * fresh replica can apply the response transactionally even when a child was
 * received before its parent. The cursor still advances from the base page;
 * dependency rows are idempotent LWW context.
 */
async function withWorkoutStructurePullDependencies(
  db: ServerDatabase,
  userId: string,
  baseRows: PullRow[]
): Promise<PullRow[]> {
  if (
    !baseRows.some((row) => WORKOUT_STRUCTURE_PULL_ENTITIES.has(row.entity))
  ) {
    return baseRows;
  }

  const payloadString = (
    payload: Record<string, unknown>,
    key: string
  ): string | null => {
    const value = payload[key];
    return typeof value === "string" && value.length > 0 ? value : null;
  };
  const idsFrom = (entity: SyncPullEntity, key: string) =>
    new Set(
      baseRows
        .filter((row) => row.entity === entity)
        .flatMap((row) => {
          const id = payloadString(row.payload, key);
          return id === null ? [] : [id];
        })
    );
  const groupIds = idsFrom(EXERCISE_GROUP_MEMBERS_SYNC_ENTITY, "group_id");
  const workoutExerciseIds = idsFrom(
    EXERCISE_GROUP_MEMBERS_SYNC_ENTITY,
    "workout_exercise_id"
  );
  const groupRows =
    groupIds.size === 0
      ? []
      : await db
          .select({
            id: schema.exerciseGroups.id,
            deviceId: schema.exerciseGroups.deviceId,
            payload: schema.exerciseGroups.payload,
            updatedAt: schema.exerciseGroups.updatedAt,
            deletedAt: schema.exerciseGroups.deletedAt,
            receivedAt: schema.exerciseGroups.receivedAt
          })
          .from(schema.exerciseGroups)
          .where(
            and(
              eq(schema.exerciseGroups.userId, userId),
              inArray(schema.exerciseGroups.id, [...groupIds])
            )
          );
  const workoutExerciseRows =
    workoutExerciseIds.size === 0
      ? []
      : await db
          .select({
            id: schema.workoutExercises.id,
            deviceId: schema.workoutExercises.deviceId,
            payload: schema.workoutExercises.payload,
            updatedAt: schema.workoutExercises.updatedAt,
            deletedAt: schema.workoutExercises.deletedAt,
            receivedAt: schema.workoutExercises.receivedAt
          })
          .from(schema.workoutExercises)
          .where(
            and(
              eq(schema.workoutExercises.userId, userId),
              inArray(schema.workoutExercises.id, [...workoutExerciseIds])
            )
          );
  const contextualRows: PullRow[] = [
    ...groupRows.map((row) =>
      opaquePullRow(EXERCISE_GROUPS_SYNC_ENTITY, row)
    ),
    ...workoutExerciseRows.map((row) =>
      opaquePullRow(WORKOUT_EXERCISES_SYNC_ENTITY, row)
    ),
    ...baseRows
  ];
  const workoutIds = new Set<string>();
  const exerciseIds = new Set<string>();
  for (const row of contextualRows) {
    if (
      row.entity === WORKOUT_EXERCISES_SYNC_ENTITY ||
      row.entity === EXERCISE_GROUPS_SYNC_ENTITY
    ) {
      const workoutId = payloadString(row.payload, "workout_id");
      if (workoutId !== null) {
        workoutIds.add(workoutId);
      }
    }
    if (row.entity === WORKOUT_EXERCISES_SYNC_ENTITY) {
      const exerciseId = payloadString(row.payload, "exercise_id");
      if (exerciseId !== null) {
        exerciseIds.add(exerciseId);
      }
    }
  }
  const [workoutRows, exerciseRows] = await Promise.all([
    workoutIds.size === 0
      ? Promise.resolve([])
      : db
          .select({
            id: schema.workoutSessions.id,
            deviceId: schema.workoutSessions.deviceId,
            payload: schema.workoutSessions.payload,
            updatedAt: schema.workoutSessions.updatedAt,
            deletedAt: schema.workoutSessions.deletedAt,
            receivedAt: schema.workoutSessions.receivedAt
          })
          .from(schema.workoutSessions)
          .where(
            and(
              eq(schema.workoutSessions.userId, userId),
              inArray(schema.workoutSessions.id, [...workoutIds])
            )
          ),
    exerciseIds.size === 0
      ? Promise.resolve([])
      : db
          .select({
            id: schema.exercises.id,
            deviceId: schema.exercises.deviceId,
            payload: schema.exercises.payload,
            updatedAt: schema.exercises.updatedAt,
            deletedAt: schema.exercises.deletedAt,
            receivedAt: schema.exercises.receivedAt
          })
          .from(schema.exercises)
          .where(
            and(
              eq(schema.exercises.userId, userId),
              inArray(schema.exercises.id, [...exerciseIds])
            )
          )
  ]);
  const categoryIds = new Set(
    exerciseRows.flatMap((row) => {
      const categoryId = payloadString(row.payload, "category_id");
      return categoryId === null ? [] : [categoryId];
    })
  );
  const categoryRows =
    categoryIds.size === 0
      ? []
      : await db
          .select({
            id: schema.exerciseCategories.id,
            deviceId: schema.exerciseCategories.deviceId,
            payload: schema.exerciseCategories.payload,
            updatedAt: schema.exerciseCategories.updatedAt,
            deletedAt: schema.exerciseCategories.deletedAt,
            receivedAt: schema.exerciseCategories.receivedAt
          })
          .from(schema.exerciseCategories)
          .where(
            and(
              eq(schema.exerciseCategories.userId, userId),
              inArray(schema.exerciseCategories.id, [...categoryIds])
            )
          );
  const dependencies = [
    ...categoryRows.map((row) =>
      opaquePullRow(EXERCISE_CATEGORIES_SYNC_ENTITY, row)
    ),
    ...exerciseRows.map((row) => opaquePullRow(EXERCISES_SYNC_ENTITY, row)),
    ...workoutRows.map((row) =>
      opaquePullRow(WORKOUT_SESSIONS_SYNC_ENTITY, row)
    ),
    ...workoutExerciseRows.map((row) =>
      opaquePullRow(WORKOUT_EXERCISES_SYNC_ENTITY, row)
    ),
    ...groupRows.map((row) =>
      opaquePullRow(EXERCISE_GROUPS_SYNC_ENTITY, row)
    )
  ];
  const baseKeys = new Set(
    baseRows.map((row) => pullEnvelopeKey(row.entity, row.id))
  );
  const dependencyByKey = new Map<string, PullRow>();
  for (const row of dependencies) {
    const key = pullEnvelopeKey(row.entity, row.id);
    if (!baseKeys.has(key)) {
      dependencyByKey.set(key, row);
    }
  }
  const orderedDependencies = [...dependencyByKey.values()].sort(
    (left, right) =>
      syncEntitySortRank(left.entity) - syncEntitySortRank(right.entity) ||
      left.id.localeCompare(right.id)
  );
  return [...orderedDependencies, ...baseRows];
}

function opaquePullRow(
  entity: SyncPullEntity,
  row: OpaquePullRow
): PullRow {
  return {
    entity,
    id: row.id,
    deviceId: row.deviceId,
    payload: syncPayloadClock(row.payload, row.updatedAt, row.deletedAt),
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
    receivedAt: row.receivedAt
  };
}

type SyncCursorPosition = {
  receivedAt: Date;
  entity: SyncPullEntity;
  id: string;
};

function pullCursorFilter(
  entity: SyncPullEntity,
  receivedAtColumn:
    | typeof schema.exerciseCategories.receivedAt
    | typeof schema.exercises.receivedAt
    | typeof schema.workoutSessions.receivedAt
    | typeof schema.workoutExercises.receivedAt
    | typeof schema.exerciseGroups.receivedAt
    | typeof schema.exerciseGroupMembers.receivedAt
    | typeof schema.loggedSets.receivedAt
    | typeof schema.foods.receivedAt
    | typeof schema.mealTypes.receivedAt
    | typeof schema.meals.receivedAt
    | typeof schema.foodEntries.receivedAt
    | typeof schema.metrics.receivedAt
    | typeof schema.metricReadings.receivedAt
    | typeof schema.integrationDataClassConsents.receivedAt
    | typeof schema.compounds.receivedAt
    | typeof schema.doses.receivedAt
    | typeof schema.protocols.receivedAt
    | typeof schema.protocolCompounds.receivedAt
    | typeof schema.protocolTargetOutcomes.receivedAt
    | typeof schema.schedules.receivedAt
    | typeof schema.nutritionGoals.receivedAt
    | typeof schema.userSettings.receivedAt
    | typeof schema.routines.receivedAt
    | typeof schema.workoutTemplates.receivedAt
    | typeof schema.templateExercises.receivedAt
    | typeof schema.prescriptions.receivedAt
    | typeof schema.templateGroups.receivedAt
    | typeof schema.templateGroupMembers.receivedAt
    | typeof schema.routineEntries.receivedAt
    | typeof schema.templateLinks.receivedAt,
  idColumn:
    | typeof schema.exerciseCategories.id
    | typeof schema.exercises.id
    | typeof schema.workoutSessions.id
    | typeof schema.workoutExercises.id
    | typeof schema.exerciseGroups.id
    | typeof schema.exerciseGroupMembers.id
    | typeof schema.loggedSets.id
    | typeof schema.foods.id
    | typeof schema.mealTypes.id
    | typeof schema.meals.id
    | typeof schema.foodEntries.id
    | typeof schema.metrics.id
    | typeof schema.metricReadings.id
    | typeof schema.integrationDataClassConsents.id
    | typeof schema.compounds.id
    | typeof schema.doses.id
    | typeof schema.protocols.id
    | typeof schema.protocolCompounds.id
    | typeof schema.protocolTargetOutcomes.id
    | typeof schema.schedules.id
    | typeof schema.nutritionGoals.id
    | typeof schema.userSettings.id
    | typeof schema.routines.id
    | typeof schema.workoutTemplates.id
    | typeof schema.templateExercises.id
    | typeof schema.prescriptions.id
    | typeof schema.templateGroups.id
    | typeof schema.templateGroupMembers.id
    | typeof schema.routineEntries.id
    | typeof schema.templateLinks.id,
  cursorPosition: SyncCursorPosition | null
) {
  if (cursorPosition === null) {
    return undefined;
  }

  const entityComparison =
    syncEntitySortRank(entity) - syncEntitySortRank(cursorPosition.entity);
  if (entityComparison < 0) {
    return gt(receivedAtColumn, cursorPosition.receivedAt);
  }
  if (entityComparison > 0) {
    return gte(receivedAtColumn, cursorPosition.receivedAt);
  }

  return or(
    gt(receivedAtColumn, cursorPosition.receivedAt),
    and(
      eq(receivedAtColumn, cursorPosition.receivedAt),
      gt(idColumn, cursorPosition.id)
    )
  );
}

function comparePullRows(left: PullRow, right: PullRow) {
  return (
    left.receivedAt.getTime() - right.receivedAt.getTime() ||
    syncEntitySortRank(left.entity) - syncEntitySortRank(right.entity) ||
    left.id.localeCompare(right.id)
  );
}

function comparePullRowToCursor(row: PullRow, cursor: SyncCursorPosition) {
  return (
    row.receivedAt.getTime() - cursor.receivedAt.getTime() ||
    syncEntitySortRank(row.entity) - syncEntitySortRank(cursor.entity) ||
    row.id.localeCompare(cursor.id)
  );
}

function syncEntitySortRank(entity: SyncPullEntity) {
  switch (entity) {
    case EXERCISE_CATEGORIES_SYNC_ENTITY:
      return 0;
    case EXERCISES_SYNC_ENTITY:
      return 1;
    // Preserve established entity ranks while ordering the Workout parent and
    // structure before Logged Sets when rows share a receive timestamp.
    case WORKOUT_SESSIONS_SYNC_ENTITY:
      return 1.1;
    case WORKOUT_EXERCISES_SYNC_ENTITY:
      return 1.2;
    case EXERCISE_GROUPS_SYNC_ENTITY:
      return 1.3;
    case EXERCISE_GROUP_MEMBERS_SYNC_ENTITY:
      return 1.4;
    case COMPOUNDS_SYNC_ENTITY:
      return 2;
    case DOSES_SYNC_ENTITY:
      return 3;
    // A Food before its Food Entries — a Food Entry's `food_id` is a soft
    // reference (never a Drift FK), so this is cosmetic ordering only,
    // mirroring Compound-before-Dose above.
    case FOODS_SYNC_ENTITY:
      return 4;
    case MEAL_TYPES_SYNC_ENTITY:
      return 5;
    case FOOD_ENTRIES_SYNC_ENTITY:
      return 6;
    case LOGGED_SETS_SYNC_ENTITY:
      return 7;
    case METRICS_SYNC_ENTITY:
      return 8;
    case MEALS_SYNC_ENTITY:
      return 9;
    case METRIC_READINGS_SYNC_ENTITY:
      return 10;
    case INTEGRATION_DATA_CLASS_CONSENTS_SYNC_ENTITY:
      return 11;
    case PROTOCOLS_SYNC_ENTITY:
      return 12;
    case PROTOCOL_COMPOUNDS_SYNC_ENTITY:
      return 13;
    case PROTOCOL_TARGET_OUTCOMES_SYNC_ENTITY:
      return 14;
    case SCHEDULES_SYNC_ENTITY:
      return 15;
    case NUTRITION_GOALS_SYNC_ENTITY:
      return 16;
    // WorkoutTemplates precede TemplateExercises and their child rows;
    // Routines precede RoutineEntries. TemplateGroupMembers follow both the
    // TemplateGroup and TemplateExercise parents they reference.
    case WORKOUT_TEMPLATES_SYNC_ENTITY:
      return 17;
    case TEMPLATE_EXERCISES_SYNC_ENTITY:
      return 18;
    case PRESCRIPTIONS_SYNC_ENTITY:
      return 19;
    case TEMPLATE_GROUPS_SYNC_ENTITY:
      return 20;
    case TEMPLATE_GROUP_MEMBERS_SYNC_ENTITY:
      return 21;
    case ROUTINES_SYNC_ENTITY:
      return 22;
    case ROUTINE_ENTRIES_SYNC_ENTITY:
      return 23;
    case TEMPLATE_LINKS_SYNC_ENTITY:
      return 24;
    // The account-level Settings singleton has no FK relationship to any other
    // entity, so its rank is purely for cursor-pagination stability; appended
    // last to avoid renumbering the routine FK chain above.
    case USER_SETTINGS_SYNC_ENTITY:
      return 25;
  }
}

function metricSyncPayload(row: {
  id: string;
  name: string;
  unit: string;
  valueShape: string;
  metricGroup: string;
  goalType: string | null;
  goalTargetValue: number | null;
  enabled: boolean;
  pinned: boolean;
  sortOrder: number;
  updatedAt: Date;
  deletedAt: Date | null;
}) {
  return {
    id: row.id,
    name: row.name,
    unit: row.unit,
    value_shape: row.valueShape,
    metric_group: row.metricGroup,
    goal_type: row.goalType,
    goal_target_value: row.goalTargetValue,
    enabled: row.enabled,
    pinned: row.pinned,
    sort_order: row.sortOrder,
    updated_at: row.updatedAt.toISOString(),
    deleted_at: row.deletedAt?.toISOString() ?? null
  };
}

function metricReadingSyncPayload(row: {
  id: string;
  metricId: string;
  externalActivityId: string | null;
  valueJson: Record<string, unknown>;
  scalarValue: number | null;
  scalarEntered: string | null;
  atTime: Date | null;
  windowStartedAt: Date | null;
  windowEndedAt: Date | null;
  provenance: string;
  source: string;
  externalId: string | null;
  comment: string | null;
  updatedAt: Date;
  deletedAt: Date | null;
}) {
  return {
    id: row.id,
    metric_id: row.metricId,
    external_activity_id: row.externalActivityId,
    value_json: row.valueJson,
    scalar_value: row.scalarValue,
    scalar_entered: row.scalarEntered,
    at_time: row.atTime?.toISOString() ?? null,
    window_started_at: row.windowStartedAt?.toISOString() ?? null,
    window_ended_at: row.windowEndedAt?.toISOString() ?? null,
    provenance: row.provenance,
    source: row.source,
    external_id: row.externalId,
    comment: row.comment,
    updated_at: row.updatedAt.toISOString(),
    deleted_at: row.deletedAt?.toISOString() ?? null
  };
}

function parseIntegrationConsentPayload(payload: Record<string, unknown>) {
  const credentialId = stringPayloadValue(payload, "credential_id");
  const dataClass = CanonicalImportConsentDataClassSchema.parse(
    stringPayloadValue(payload, "data_class")
  );
  const enabled = booleanPayloadValue(payload, "enabled");

  return { credentialId, dataClass, enabled };
}

function integrationConsentSyncPayload(row: {
  id: string;
  credentialId: string;
  dataClass: string;
  enabled: boolean;
  updatedAt: Date;
  deletedAt: Date | null;
}) {
  return {
    id: row.id,
    credential_id: row.credentialId,
    data_class: row.dataClass,
    enabled: row.enabled,
    updated_at: row.updatedAt.toISOString(),
    deleted_at: row.deletedAt?.toISOString() ?? null
  };
}

function stringPayloadValue(payload: Record<string, unknown>, field: string) {
  const value = payload[field];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${field} must be a non-empty string.`);
  }

  return value;
}

function booleanPayloadValue(payload: Record<string, unknown>, field: string) {
  const value = payload[field];
  if (typeof value !== "boolean") {
    throw new Error(`${field} must be a boolean.`);
  }

  return value;
}

function pullEnvelopeKey(entity: SyncPullEntity, id: string) {
  return `${entity}\0${id}`;
}

type PullActivityLogEnvelope = {
  id: string;
  actor: string;
  batchId: string;
  entityTable: SyncPullEntity;
  entityId: string;
  beforeImage: Record<string, unknown> | null;
  afterImage: Record<string, unknown> | null;
  occurredAt: Date;
};

async function matchingActivityLogEnvelopesForPull(
  db: ServerDatabase,
  {
    userId,
    payloadsById
  }: {
    userId: string;
    payloadsById: Map<string, Record<string, unknown>>;
  }
) {
  if (payloadsById.size === 0) {
    return new Map<string, PullActivityLogEnvelope>();
  }

  const entityIdsByTable = new Map<SyncPullEntity, string[]>();
  for (const key of payloadsById.keys()) {
    const parsed = parsePullEnvelopeKey(key);
    entityIdsByTable.set(parsed.entity, [
      ...(entityIdsByTable.get(parsed.entity) ?? []),
      parsed.id
    ]);
  }
  const entityTables = [...entityIdsByTable.keys()];
  const entityIds = [...new Set([...entityIdsByTable.values()].flat())];
  const rows = await db
    .select({
      id: schema.activityLog.id,
      actor: schema.activityLog.actor,
      batchId: schema.activityLog.batchId,
      entityTable: schema.activityLog.entityTable,
      entityId: schema.activityLog.entityId,
      beforeImage: schema.activityLog.beforeImage,
      afterImage: schema.activityLog.afterImage,
      occurredAt: schema.activityLog.occurredAt
    })
    .from(schema.activityLog)
    .where(
      and(
        eq(schema.activityLog.userId, userId),
        inArray(schema.activityLog.entityTable, entityTables),
        inArray(schema.activityLog.entityId, entityIds)
      )
    );

  const envelopesById = new Map<string, PullActivityLogEnvelope>();
  for (const row of rows) {
    if (!isSyncPullEntity(row.entityTable)) {
      continue;
    }

    const key = pullEnvelopeKey(row.entityTable, row.entityId);
    const payload = payloadsById.get(key);
    if (payload === undefined || !isDeepStrictEqual(row.afterImage, payload)) {
      continue;
    }

    const existing = envelopesById.get(key);
    if (
      existing === undefined ||
      row.occurredAt.getTime() > existing.occurredAt.getTime() ||
      (row.occurredAt.getTime() === existing.occurredAt.getTime() &&
        row.id > existing.id)
    ) {
      envelopesById.set(key, {
        id: row.id,
        actor: row.actor,
        batchId: row.batchId,
        entityTable: row.entityTable,
        entityId: row.entityId,
        beforeImage: row.beforeImage,
        afterImage: row.afterImage,
        occurredAt: row.occurredAt
      });
    }
  }

  return envelopesById;
}

function parsePullEnvelopeKey(key: string): { entity: SyncPullEntity; id: string } {
  const [entity, id] = key.split("\0");
  if (!isSyncPullEntity(entity) || id === undefined) {
    throw new Error("invalid pull envelope key");
  }

  return { entity, id };
}

function isSyncPullEntity(value: string): value is SyncPullEntity {
  return (SYNC_PULL_ENTITIES as readonly string[]).includes(value);
}

type SyncPushChangeWithActivityLogEnvelope = SyncPushChange & {
  activityLogId: string;
  actor: string;
  batchId: string;
  beforeImage: Record<string, unknown> | null;
  afterImage: Record<string, unknown> | null;
  occurredAt: string;
};

function hasActivityLogEnvelope(
  change: SyncPushChange
): change is SyncPushChangeWithActivityLogEnvelope {
  return ACTIVITY_LOG_ENVELOPE_FIELDS.every(
    (field) => change[field] !== undefined
  );
}

export function readBearerToken(authorization: string | undefined) {
  if (authorization === undefined) {
    return null;
  }

  const match = /^Bearer\s+(.+)$/i.exec(authorization.trim());
  return match?.[1] ?? null;
}

function parseIsoDate(value: string, field: string) {
  const date = new Date(value);
  if (Number.isNaN(date.valueOf())) {
    throw new Error(`${field} must be an ISO-8601 timestamp.`);
  }

  return date;
}

function encodeSyncCursor(
  receivedAt: Date,
  entity: SyncPullEntity,
  id: string
) {
  return `${receivedAt.toISOString()}|${entity}|${id}`;
}

function decodeSyncCursor(cursor: string): SyncCursorPosition {
  const parts = cursor.split("|");
  if (parts.length === 2) {
    return {
      receivedAt: parseIsoDate(parts[0], "cursor"),
      entity: LOGGED_SETS_SYNC_ENTITY,
      id: parts[1]
    };
  }
  if (parts.length !== 3 || !isSyncPullEntity(parts[1])) {
    throw new Error("cursor must be a server-issued sync cursor.");
  }

  return {
    receivedAt: parseIsoDate(parts[0], "cursor"),
    entity: parts[1],
    id: parts[2]
  };
}
