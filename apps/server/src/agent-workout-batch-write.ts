import { createRoute, z } from "@hono/zod-openapi";
import { and, asc, eq, inArray, sql } from "drizzle-orm";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import {
  AgentCatalogUnavailableResponseSchema,
  type AgentCatalogStore,
  type AgentExercise
} from "./agent-catalog.js";
import {
  AgentSetValidationIssueSchema,
  AgentSetValidationLimitsSchema,
  AgentSetValidationValuesSchema,
  setValidationLimitsResponse,
  validateAgentSet,
  type AgentSetValidationIssue
} from "./agent-validation.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import { createUuidV7 } from "./agent-plan-materialize.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";
import {
  pushExerciseGroupMembersInTransaction,
  pushExerciseGroupsInTransaction,
  pushWorkoutExercisesInTransaction,
  pushWorkoutSessionsInTransaction,
  pushLoggedSetsInTransaction,
  type SyncPushChange
} from "./sync.js";

export const AGENT_WORKOUT_BATCH_WRITE_MAX_SETS = 100;

const ISO8601StringSchema = z.string().min(1).openapi({
  description: "ISO-8601 timestamp."
});

export const AgentWorkoutBatchWriteWorkoutSchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "Client-supplied UUIDv7 Workout id."
    }),
    startedAt: ISO8601StringSchema.openapi({
      description: "Workout start instant in UTC."
    }),
    endedAt: ISO8601StringSchema.nullable().default(null).openapi({
      description: "Workout end instant in UTC, or null while still open."
    }),
    timezone: z.string().min(1).openapi({
      description: "IANA timezone captured at Workout creation."
    }),
    comment: z.string().nullable().default(null).openapi({
      description: "Optional Workout comment."
    }),
    deletedAt: ISO8601StringSchema.nullable().default(null).openapi({
      description:
        "Nullable Workout archive tombstone. Archiving preserves historical Sets and tombstones active Workout structure."
    })
  })
  .openapi("AgentWorkoutBatchWriteWorkout");

export const AgentWorkoutBatchWriteSetSchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "Client-supplied UUIDv7 Logged Set row id."
    }),
    exerciseName: z.string().trim().min(1).openapi({
      description:
        "Free-text Exercise name resolved through User Library over Platform Library before writing."
    }),
    position: z.number().int().min(0).openapi({
      description: "Zero-based set order inside the Workout."
    }),
    plannedRestAfter: z.number().int().min(0).nullable().default(null).openapi({
      description:
        "Optional planned rest after this Set in seconds. This is authored guidance, not an observed rest duration."
    }),
    performedAt: ISO8601StringSchema.nullable().default(null).openapi({
      description:
        "Optional observed performance instant. Null preserves that no Set-level performance time was supplied."
    }),
    isCompleted: z.boolean().default(true).openapi({
      description:
        "Live-workout completion state. Defaults to true for this performed-fact logging operation; it is not an analytics quality or adherence flag."
    }),
    values: AgentSetValidationValuesSchema,
    rpe: z.union([z.string(), z.number()]).optional().openapi({
      description: "Optional rate of perceived exertion."
    }),
    side: z.string().optional().openapi({
      description: "Optional side annotation.",
      enum: ["left", "right"]
    }),
    comment: z.string().nullable().default(null).openapi({
      description: "Optional per-set comment."
    }),
    updatedAt: ISO8601StringSchema.optional().openapi({
      description:
        "Client-observed row update clock. Defaults to the server receive time when omitted."
    }),
    deletedAt: ISO8601StringSchema.nullable().default(null).openapi({
      description:
        "Nullable archive tombstone. Setting it is an ordinary LWW write of a tombstone, the same archive semantics the app's own delete affordance produces — never a purge."
    })
  })
  .openapi("AgentWorkoutBatchWriteSet");

export const AgentWorkoutBatchWriteRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200).openapi({
      description:
        "Stable key for this agent request. Replays with the same key return the original result without appending another Activity Log batch."
    }),
    workout: AgentWorkoutBatchWriteWorkoutSchema,
    sets: z
      .array(AgentWorkoutBatchWriteSetSchema)
      .min(1)
      .max(AGENT_WORKOUT_BATCH_WRITE_MAX_SETS)
      .openapi({
        description: "Logged Sets to apply atomically as one Activity Log batch."
      })
  })
  .openapi("AgentWorkoutBatchWriteRequest");

export const AgentWorkoutBatchWriteIssueSchema = AgentSetValidationIssueSchema
  .extend({
    itemIndex: z.number().int().min(0).openapi({
      description: "Index of the set item that produced the issue."
    }),
    setId: z.string().min(1).openapi({
      description: "Client-supplied set id for the failed item."
    }),
    exerciseName: z.string().min(1).openapi({
      description: "Exercise name from the failed request item."
    })
  })
  .openapi("AgentWorkoutBatchWriteIssue");

export const AgentWorkoutBatchWriteSetResultSchema = z
  .object({
    id: z.string().min(1),
    exerciseId: z.string().min(1),
    exerciseName: z.string().min(1),
    requestedExerciseName: z.string().min(1),
    warnings: z.array(AgentSetValidationIssueSchema)
  })
  .openapi("AgentWorkoutBatchWriteSetResult");

export const AgentWorkoutBatchWriteResponseSchema = z
  .object({
    accepted: z.literal(true),
    duplicate: z.boolean().openapi({
      description:
        "True when the idempotency key had already been applied and no new rows or Activity Log entries were written."
    }),
    idempotencyKey: z.string().min(1),
    batchId: z.string().min(1).openapi({
      description: "Activity Log batch id. Equal to the idempotency key."
    }),
    workoutId: z.string().min(1),
    serverClock: z.string().min(1),
    sets: z.array(AgentWorkoutBatchWriteSetResultSchema)
  })
  .openapi("AgentWorkoutBatchWriteResponse");

export const AgentWorkoutBatchWriteErrorResponseSchema = z
  .object({
    code: z.literal("agent_batch_write_failed"),
    message: z.string().min(1),
    errors: z.array(AgentWorkoutBatchWriteIssueSchema),
    warnings: z.array(AgentWorkoutBatchWriteIssueSchema),
    limits: AgentSetValidationLimitsSchema
  })
  .openapi("AgentWorkoutBatchWriteErrorResponse");

export const AgentWorkoutBatchWriteUnavailableResponseSchema = z
  .object({
    code: z.literal("agent_batch_write_unavailable"),
    message: z.string().min(1)
  })
  .openapi("AgentWorkoutBatchWriteUnavailableResponse");

export const agentWorkoutBatchWriteRoute = createRoute({
  method: "post",
  path: "/agent/workouts/batch-write",
  operationId: "batchWriteAgentWorkout",
  tags: ["Agent Writes"],
  summary: "Batch-write a Workout as one Activity Log batch.",
  description:
    "Authenticated agent write path. Resolves Exercise names through User Library over Platform Library, persists the authoritative Workout and ordered Workout Exercises alongside the logged Sets, validates every Set with the shared two-tier validation module, applies the request atomically, and records one Activity Log batch. Purge and hard-delete are intentionally absent.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: AgentWorkoutBatchWriteRequestSchema
        }
      }
    }
  },
  responses: {
    200: {
      description:
        "The batch was accepted, or recognized as an idempotent replay.",
      content: {
        "application/json": {
          schema: AgentWorkoutBatchWriteResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid agent API key.",
      content: {
        "application/json": {
          schema: AgentUnauthorizedResponseSchema
        }
      }
    },
    422: {
      description:
        "One or more items failed hard validation or Exercise name resolution; no rows were written.",
      content: {
        "application/json": {
          schema: AgentWorkoutBatchWriteErrorResponseSchema
        }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key, catalog, or write storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentCatalogUnavailableResponseSchema,
            AgentWorkoutBatchWriteUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export type AgentWorkoutBatchWriteRequest = z.infer<
  typeof AgentWorkoutBatchWriteRequestSchema
>;
export type AgentWorkoutBatchWriteIssue = z.infer<
  typeof AgentWorkoutBatchWriteIssueSchema
>;
export type AgentWorkoutBatchPreparedSet = {
  id: string;
  updatedAt: string;
  deletedAt: string | null;
  payload: Record<string, unknown>;
  result: z.infer<typeof AgentWorkoutBatchWriteSetResultSchema>;
};
export type AgentWorkoutBatchPreparation =
  | {
      accepted: true;
      sets: AgentWorkoutBatchPreparedSet[];
      responseSets: z.infer<typeof AgentWorkoutBatchWriteSetResultSchema>[];
    }
  | {
      accepted: false;
      errors: AgentWorkoutBatchWriteIssue[];
      warnings: AgentWorkoutBatchWriteIssue[];
    };
export type AgentWorkoutBatchWriteStore = {
  writeWorkoutBatch(input: {
    userId: string;
    batchId: string;
    correlationId?: string;
    deviceId: string;
    workout?: z.infer<typeof AgentWorkoutBatchWriteWorkoutSchema>;
    sets: AgentWorkoutBatchPreparedSet[];
  }): Promise<{
    duplicate: boolean;
    serverClock: string;
    applied: { id: string; updatedAt: string; deviceId: string }[];
  }>;
};

export async function prepareAgentWorkoutBatchWrite({
  catalogStore,
  request,
  userId,
  now = new Date()
}: {
  catalogStore: AgentCatalogStore;
  request: AgentWorkoutBatchWriteRequest;
  userId: string;
  now?: Date;
}): Promise<AgentWorkoutBatchPreparation> {
  const errors: AgentWorkoutBatchWriteIssue[] = [];
  const warnings: AgentWorkoutBatchWriteIssue[] = [];
  const preparedSets: AgentWorkoutBatchPreparedSet[] = [];

  for (const [itemIndex, item] of request.sets.entries()) {
    const resolution = await catalogStore.resolveExerciseName({
      userId,
      name: item.exerciseName,
      candidateLimit: 0
    });
    const exercise = resolution.matchedExercise;
    if (resolution.resolution !== "matched" || exercise === null) {
      errors.push(
        issueForItem(itemIndex, item, {
          field: `sets[${itemIndex}].exerciseName`,
          dimension: null,
          rule:
            resolution.resolution === "ambiguous"
              ? "exercise_resolution_ambiguous"
              : "exercise_not_found",
          message:
            resolution.resolution === "ambiguous"
              ? "Exercise name is ambiguous."
              : "Exercise name could not be resolved.",
          limit: null
        })
      );
      continue;
    }

    const validation = validateAgentSet({
      exercise: {
        dimensions: exercise.dimensions,
        loadMode: exercise.loadMode
      },
      values: item.values,
      rpe: item.rpe,
      side: item.side
    });
    for (const warning of validation.warnings) {
      warnings.push(issueForItem(itemIndex, item, warning));
    }
    for (const error of validation.errors) {
      errors.push(issueForItem(itemIndex, item, error));
    }
    if (validation.errors.length > 0) {
      continue;
    }

    const updatedAt = item.updatedAt ?? now.toISOString();
    const deletedAt = item.deletedAt ?? null;
    const payload = buildLoggedSetPayload({
      exercise,
      item,
      request,
      updatedAt,
      deletedAt
    });
    const result = AgentWorkoutBatchWriteSetResultSchema.parse({
      id: item.id,
      exerciseId: exercise.id,
      exerciseName: exercise.name,
      requestedExerciseName: item.exerciseName,
      warnings: validation.warnings
    });

    preparedSets.push({
      id: item.id,
      updatedAt,
      deletedAt,
      payload,
      result
    });
  }

  if (errors.length > 0) {
    return { accepted: false, errors, warnings };
  }

  return {
    accepted: true,
    sets: preparedSets,
    responseSets: preparedSets.map((set) => set.result)
  };
}

export function createDrizzleAgentWorkoutBatchWriteStore(
  db: ServerDatabase
): AgentWorkoutBatchWriteStore {
  return {
    async writeWorkoutBatch({ userId, batchId, deviceId, workout, sets }) {
      const serverClock = new Date();

      return db.transaction(async (transaction) => {
        const existingBatchRows = await transaction
          .select({ id: schema.activityLog.id })
          .from(schema.activityLog)
          .where(
            and(
              eq(schema.activityLog.userId, userId),
              eq(schema.activityLog.actor, "agent"),
              eq(schema.activityLog.batchId, batchId)
            )
          )
          .orderBy(asc(schema.activityLog.createdAt), asc(schema.activityLog.id))
          .limit(1);

        if (existingBatchRows.length > 0) {
          return {
            duplicate: true,
            serverClock: serverClock.toISOString(),
            applied: []
          };
        }

        const resolvedWorkout = workout ?? workoutFromPreparedSets(sets);
        const workoutUpdatedAt = serverClock.toISOString();
        const workoutPayload = {
          id: resolvedWorkout.id,
          started_at: resolvedWorkout.startedAt,
          timezone: resolvedWorkout.timezone,
          local_date: localDateInTimezone(
            resolvedWorkout.startedAt,
            resolvedWorkout.timezone
          ),
          ended_at: resolvedWorkout.endedAt,
          comment: resolvedWorkout.comment,
          updated_at: workoutUpdatedAt,
          deleted_at: resolvedWorkout.deletedAt
        };
        const existingWorkoutRows = await transaction
          .select({
            userId: schema.workoutSessions.userId,
            payload: schema.workoutSessions.payload
          })
          .from(schema.workoutSessions)
          .where(eq(schema.workoutSessions.id, resolvedWorkout.id))
          .limit(1);
        const existingWorkout = existingWorkoutRows[0];
        const workoutBeforeImage =
          existingWorkout?.userId === userId ? existingWorkout.payload : null;
        const workoutResult = await pushWorkoutSessionsInTransaction(
          transaction,
          {
            userId,
            deviceId,
            changes: [
              {
                id: resolvedWorkout.id,
                payload: workoutPayload,
                updatedAt: workoutUpdatedAt,
                deletedAt: resolvedWorkout.deletedAt,
                activityLogId: `agent:${batchId}:workout:${resolvedWorkout.id}`,
                actor: "agent",
                batchId,
                beforeImage: workoutBeforeImage,
                afterImage: workoutPayload,
                occurredAt: workoutUpdatedAt
              }
            ],
            serverClock
          }
        );
        const workoutExerciseResult = await writeWorkoutExercises({
          transaction,
          userId,
          batchId,
          deviceId,
          workoutId: resolvedWorkout.id,
          sets,
          serverClock,
          archiveAt: resolvedWorkout.deletedAt
        });
        const archivedGroupResult =
          resolvedWorkout.deletedAt === null
            ? { applied: [] }
            : await archiveWorkoutGroups({
                transaction,
                userId,
                batchId,
                deviceId,
                workoutId: resolvedWorkout.id,
                archivedAt: resolvedWorkout.deletedAt,
                serverClock
              });
        const changes: SyncPushChange[] = [];
        for (const set of sets) {
          const beforeImage = await readBeforeImage({
            transaction,
            userId,
            setId: set.id
          });
          changes.push({
            id: set.id,
            payload: set.payload,
            updatedAt: set.updatedAt,
            deletedAt: set.deletedAt,
            activityLogId: `agent:${batchId}:${set.id}`,
            actor: "agent",
            batchId,
            beforeImage,
            afterImage: set.payload,
            occurredAt: set.updatedAt
          });
        }

        const result = await pushLoggedSetsInTransaction(transaction, {
          userId,
          deviceId,
          changes,
          serverClock
        });

        return {
          duplicate: false,
          serverClock: result.serverClock,
          applied: [
            ...workoutResult.applied,
            ...workoutExerciseResult.applied,
            ...archivedGroupResult.applied,
            ...result.applied
          ]
        };
      });
    }
  };
}

function buildLoggedSetPayload({
  exercise,
  item,
  request,
  updatedAt,
  deletedAt
}: {
  exercise: AgentExercise;
  item: z.infer<typeof AgentWorkoutBatchWriteSetSchema>;
  request: AgentWorkoutBatchWriteRequest;
  updatedAt: string;
  deletedAt: string | null;
}) {
  const payload: Record<string, unknown> = {
    id: item.id,
    workout_id: request.workout.id,
    workout_started_at: request.workout.startedAt,
    workout_ended_at: request.workout.endedAt,
    workout_timezone: request.workout.timezone,
    workout_comment: request.workout.comment,
    workout_deleted_at: request.workout.deletedAt,
    exercise_id: exercise.id,
    exercise_name: exercise.name,
    exercise_category_id: exercise.category.id,
    exercise_category_name: exercise.category.name,
    exercise_equipment: exercise.equipment,
    exercise_library: exercise.library,
    exercise_query: item.exerciseName,
    position: item.position,
    planned_rest_after: item.plannedRestAfter,
    performed_at: item.performedAt,
    is_completed: item.isCompleted,
    values: item.values,
    rpe: item.rpe ?? null,
    side: item.side ?? null,
    comment: item.comment,
    updated_at: updatedAt,
    deleted_at: deletedAt
  };

  for (const [dimension, value] of Object.entries(item.values)) {
    if (value !== undefined) {
      payload[`${dimension}_entered`] = value.entered;
      payload[`${dimension}_unit`] = value.unit;
    }
  }

  return payload;
}

function workoutFromPreparedSets(
  sets: readonly AgentWorkoutBatchPreparedSet[]
): z.infer<typeof AgentWorkoutBatchWriteWorkoutSchema> {
  const payload = sets[0]?.payload;
  if (payload === undefined) {
    throw new Error("A Workout batch requires at least one Set.");
  }

  return AgentWorkoutBatchWriteWorkoutSchema.parse({
    id: payload.workout_id,
    startedAt: payload.workout_started_at,
    endedAt: payload.workout_ended_at ?? null,
    timezone: payload.workout_timezone,
    comment: payload.workout_comment ?? null,
    deletedAt: payload.workout_deleted_at ?? null
  });
}

function localDateInTimezone(startedAt: string, timezone: string) {
  const date = new Date(startedAt);
  try {
    return new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit"
    }).format(date);
  } catch {
    return date.toISOString().slice(0, 10);
  }
}

async function writeWorkoutExercises({
  transaction,
  userId,
  batchId,
  deviceId,
  workoutId,
  sets,
  serverClock,
  archiveAt
}: {
  transaction: Parameters<typeof pushWorkoutExercisesInTransaction>[0];
  userId: string;
  batchId: string;
  deviceId: string;
  workoutId: string;
  sets: readonly AgentWorkoutBatchPreparedSet[];
  serverClock: Date;
  archiveAt: string | null;
}) {
  const existingRows = await transaction
    .select({
      id: schema.workoutExercises.id,
      userId: schema.workoutExercises.userId,
      payload: schema.workoutExercises.payload,
      deletedAt: schema.workoutExercises.deletedAt
    })
    .from(schema.workoutExercises)
    .where(
      and(
        eq(schema.workoutExercises.userId, userId),
        sql`${schema.workoutExercises.payload} ->> 'workout_id' = ${workoutId}`
      )
    );
  const existingByExerciseId = new Map(
    existingRows
      .filter((row) => row.deletedAt === null)
      .flatMap((row) => {
        const exerciseId = row.payload.exercise_id;
        return typeof exerciseId === "string" ? [[exerciseId, row] as const] : [];
      })
  );
  const positionsByExerciseId = new Map<string, number>();
  for (const set of sets) {
    const exerciseId = set.result.exerciseId;
    const position =
      typeof set.payload.position === "number" ? set.payload.position : 0;
    const current = positionsByExerciseId.get(exerciseId);
    if (current === undefined || position < current) {
      positionsByExerciseId.set(exerciseId, position);
    }
  }
  const orderedExerciseIds = [...positionsByExerciseId.entries()]
    .sort(
      ([leftId, leftPosition], [rightId, rightPosition]) =>
        leftPosition - rightPosition || leftId.localeCompare(rightId)
    )
    .map(([exerciseId]) => exerciseId);
  const updatedAt = serverClock.toISOString();
  const changes =
    archiveAt === null
      ? orderedExerciseIds.map((exerciseId, position) => {
          const existing = existingByExerciseId.get(exerciseId);
          const id = existing?.id ?? createUuidV7(serverClock);
          const payload = {
            id,
            workout_id: workoutId,
            exercise_id: exerciseId,
            position,
            updated_at: updatedAt,
            deleted_at: null
          };
          return {
            id,
            payload,
            updatedAt,
            deletedAt: null,
            activityLogId: `agent:${batchId}:workout-exercise:${id}`,
            actor: "agent",
            batchId,
            beforeImage: existing?.payload ?? null,
            afterImage: payload,
            occurredAt: updatedAt
          } satisfies SyncPushChange;
        })
      : existingRows
          .filter((row) => row.deletedAt === null)
          .map((row) => {
            const payload = {
              ...row.payload,
              id: row.id,
              updated_at: updatedAt,
              deleted_at: archiveAt
            };
            return {
              id: row.id,
              payload,
              updatedAt,
              deletedAt: archiveAt,
              activityLogId: `agent:${batchId}:workout-exercise:${row.id}`,
              actor: "agent",
              batchId,
              beforeImage: row.payload,
              afterImage: payload,
              occurredAt: updatedAt
            } satisfies SyncPushChange;
          });

  return changes.length === 0
    ? { applied: [] }
    : pushWorkoutExercisesInTransaction(transaction, {
        userId,
        deviceId,
        changes,
        serverClock
      });
}

async function archiveWorkoutGroups({
  transaction,
  userId,
  batchId,
  deviceId,
  workoutId,
  archivedAt,
  serverClock
}: {
  transaction: Parameters<typeof pushExerciseGroupsInTransaction>[0];
  userId: string;
  batchId: string;
  deviceId: string;
  workoutId: string;
  archivedAt: string;
  serverClock: Date;
}) {
  const groupRows = await transaction
    .select({
      id: schema.exerciseGroups.id,
      payload: schema.exerciseGroups.payload,
      deletedAt: schema.exerciseGroups.deletedAt
    })
    .from(schema.exerciseGroups)
    .where(
      and(
        eq(schema.exerciseGroups.userId, userId),
        sql`${schema.exerciseGroups.payload} ->> 'workout_id' = ${workoutId}`
      )
    );
  const activeGroups = groupRows.filter((row) => row.deletedAt === null);
  const groupIds = activeGroups.map((row) => row.id);
  const memberRows =
    groupIds.length === 0
      ? []
      : await transaction
          .select({
            id: schema.exerciseGroupMembers.id,
            payload: schema.exerciseGroupMembers.payload,
            deletedAt: schema.exerciseGroupMembers.deletedAt
          })
          .from(schema.exerciseGroupMembers)
          .where(
            and(
              eq(schema.exerciseGroupMembers.userId, userId),
              inArray(
                sql<string>`${schema.exerciseGroupMembers.payload} ->> 'group_id'`,
                groupIds
              )
            )
          );
  const updatedAt = serverClock.toISOString();
  const tombstone = (
    entity: "exercise-group" | "exercise-group-member",
    row: { id: string; payload: Record<string, unknown> }
  ) => {
    const payload = {
      ...row.payload,
      id: row.id,
      updated_at: updatedAt,
      deleted_at: archivedAt
    };
    return {
      id: row.id,
      payload,
      updatedAt,
      deletedAt: archivedAt,
      activityLogId: `agent:${batchId}:${entity}:${row.id}`,
      actor: "agent",
      batchId,
      beforeImage: row.payload,
      afterImage: payload,
      occurredAt: updatedAt
    } satisfies SyncPushChange;
  };
  const memberChanges = memberRows
    .filter((row) => row.deletedAt === null)
    .map((row) => tombstone("exercise-group-member", row));
  const groupChanges = activeGroups.map((row) =>
    tombstone("exercise-group", row)
  );
  const memberResult =
    memberChanges.length === 0
      ? { applied: [] }
      : await pushExerciseGroupMembersInTransaction(transaction, {
          userId,
          deviceId,
          changes: memberChanges,
          serverClock
        });
  const groupResult =
    groupChanges.length === 0
      ? { applied: [] }
      : await pushExerciseGroupsInTransaction(transaction, {
          userId,
          deviceId,
          changes: groupChanges,
          serverClock
        });
  return { applied: [...memberResult.applied, ...groupResult.applied] };
}

async function readBeforeImage({
  transaction,
  userId,
  setId
}: {
  transaction: Pick<ServerDatabase, "select">;
  userId: string;
  setId: string;
}) {
  const existingRows = await transaction
    .select({
      userId: schema.loggedSets.userId,
      payload: schema.loggedSets.payload
    })
    .from(schema.loggedSets)
    .where(eq(schema.loggedSets.id, setId))
    .limit(1);
  const existing = existingRows[0];
  if (existing === undefined || existing.userId !== userId) {
    return null;
  }

  return existing.payload;
}

function issueForItem(
  itemIndex: number,
  item: z.infer<typeof AgentWorkoutBatchWriteSetSchema>,
  issue: AgentSetValidationIssue
): AgentWorkoutBatchWriteIssue {
  return AgentWorkoutBatchWriteIssueSchema.parse({
    ...issue,
    field: issue.field.startsWith("sets[")
      ? issue.field
      : `sets[${itemIndex}].${issue.field}`,
    itemIndex,
    setId: item.id,
    exerciseName: item.exerciseName
  });
}
