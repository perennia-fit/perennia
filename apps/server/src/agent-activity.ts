import { isDeepStrictEqual } from "node:util";
import { createRoute, z } from "@hono/zod-openapi";
import { and, asc, desc, eq, gte, lte } from "drizzle-orm";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";
import {
  COMPOUNDS_SYNC_ENTITY,
  DOSES_SYNC_ENTITY,
  EXERCISE_CATEGORIES_SYNC_ENTITY,
  EXERCISE_GROUP_MEMBERS_SYNC_ENTITY,
  EXERCISE_GROUPS_SYNC_ENTITY,
  EXERCISES_SYNC_ENTITY,
  FOOD_ENTRIES_SYNC_ENTITY,
  FOODS_SYNC_ENTITY,
  LOGGED_SETS_SYNC_ENTITY,
  MEAL_TYPES_SYNC_ENTITY,
  MEALS_SYNC_ENTITY,
  NUTRITION_GOALS_SYNC_ENTITY,
  PRESCRIPTIONS_SYNC_ENTITY,
  PROTOCOL_COMPOUNDS_SYNC_ENTITY,
  PROTOCOL_TARGET_OUTCOMES_SYNC_ENTITY,
  PROTOCOLS_SYNC_ENTITY,
  WORKOUT_EXERCISES_SYNC_ENTITY,
  WORKOUT_SESSIONS_SYNC_ENTITY,
  WORKOUT_TEMPLATES_SYNC_ENTITY,
  TEMPLATE_GROUP_MEMBERS_SYNC_ENTITY,
  TEMPLATE_GROUPS_SYNC_ENTITY,
  TEMPLATE_EXERCISES_SYNC_ENTITY,
  ROUTINES_SYNC_ENTITY,
  ROUTINE_ENTRIES_SYNC_ENTITY,
  SCHEDULES_SYNC_ENTITY,
  TEMPLATE_LINKS_SYNC_ENTITY,
  pushCompoundsInTransaction,
  pushDosesInTransaction,
  pushExerciseCategoriesInTransaction,
  pushExerciseGroupMembersInTransaction,
  pushExerciseGroupsInTransaction,
  pushExercisesInTransaction,
  pushFoodEntriesInTransaction,
  pushFoodsInTransaction,
  pushLoggedSetsInTransaction,
  pushMealsInTransaction,
  pushMealTypesInTransaction,
  pushNutritionGoalsInTransaction,
  pushPrescriptionsInTransaction,
  pushProtocolCompoundsInTransaction,
  pushProtocolsInTransaction,
  pushProtocolTargetOutcomesInTransaction,
  pushWorkoutTemplatesInTransaction,
  pushTemplateGroupMembersInTransaction,
  pushTemplateGroupsInTransaction,
  pushTemplateExercisesInTransaction,
  pushRoutineEntriesInTransaction,
  pushRoutinesInTransaction,
  pushSchedulesInTransaction,
  pushTemplateLinksInTransaction,
  pushWorkoutExercisesInTransaction,
  pushWorkoutSessionsInTransaction,
  type SyncPushChange,
  type SyncPushResult
} from "./sync.js";

export const AGENT_ACTIVITY_DEFAULT_PAGE_LIMIT = 50;
export const AGENT_ACTIVITY_MAX_PAGE_LIMIT = 200;

// Bookkeeping rows written into activity_log that are NOT user-facing entity
// mutations: agent batch-write fingerprints and plan-operation receipts,
// canonical-import batch receipts (canonical-import-endpoint.ts), monitoring-read
// audit rows (agent-read-surface.ts), and imported-data purge receipts. Their
// after-images are internal projections (idempotencyKey/status/read-audit
// metadata), not raw row payloads, so they must never surface as "batches" in the
// Activity Log read nor be grouped/undone. The monitoring-read rows in particular
// use actor 'agent', so they would leak under the natural ?actor=agent filter if
// not excluded here. Kept as literal strings (not imports) to avoid pulling the
// import/monitoring endpoint modules into this read/undo surface.
const AGENT_BATCH_MARKER_ENTITIES = new Set<string>([
  "agent_metric_batches",
  "agent_protocol_batches",
  "agent_plan_tree_batches",
  "agent_plan_materializations",
  "agent_plan_captures",
  "agent_plan_updates_from_workout",
  "canonical_import_batches",
  "agent_monitoring_reads",
  "imported_data_purges"
]);

const ISO8601StringSchema = z.string().min(1).openapi({
  description: "ISO-8601 timestamp."
});

const AgentActivityImageSchema = z
  .record(z.string(), z.unknown())
  .nullable()
  .openapi("AgentActivityImage");

export const AgentActivityEntrySchema = z
  .object({
    id: z.string().min(1),
    entityTable: z.string().min(1),
    entityId: z.string().min(1),
    beforeImage: AgentActivityImageSchema,
    afterImage: AgentActivityImageSchema,
    occurredAt: ISO8601StringSchema
  })
  .openapi("AgentActivityEntry");

export const AgentActivityBatchSchema = z
  .object({
    batchId: z.string().min(1),
    actor: z.string().min(1),
    occurredAt: ISO8601StringSchema,
    entries: z.array(AgentActivityEntrySchema)
  })
  .openapi("AgentActivityBatch");

export const AgentActivityListQuerySchema = z
  .object({
    actor: z.string().trim().min(1).optional().openapi({
      param: { name: "actor", in: "query" },
      description:
        "Optional actor filter, for example agent, app, or sync."
    }),
    entityTable: z.string().trim().min(1).optional().openapi({
      param: { name: "entityTable", in: "query" },
      description:
        "Optional entity table filter, for example logged_sets or meals."
    }),
    batchId: z.string().trim().min(1).optional().openapi({
      param: { name: "batchId", in: "query" },
      description: "Optional exact Activity Log batch id filter."
    }),
    from: z.string().trim().min(1).optional().openapi({
      param: { name: "from", in: "query" },
      description: "Optional inclusive ISO-8601 lower bound on occurredAt."
    }),
    to: z.string().trim().min(1).optional().openapi({
      param: { name: "to", in: "query" },
      description: "Optional inclusive ISO-8601 upper bound on occurredAt."
    }),
    limit: z.coerce
      .number()
      .int()
      .min(1)
      .max(AGENT_ACTIVITY_MAX_PAGE_LIMIT)
      .default(AGENT_ACTIVITY_DEFAULT_PAGE_LIMIT)
      .openapi({
        param: { name: "limit", in: "query" },
        description: "Maximum Activity Log batches to return."
      }),
    cursor: z.string().trim().min(1).optional().openapi({
      param: { name: "cursor", in: "query" },
      description: "Opaque cursor returned by the previous page."
    })
  })
  .openapi("AgentActivityListQuery");

export const AgentActivityListResponseSchema = z
  .object({
    batches: z.array(AgentActivityBatchSchema),
    limit: z.number().int().min(1).max(AGENT_ACTIVITY_MAX_PAGE_LIMIT),
    nextCursor: z.string().min(1).nullable(),
    totalMatched: z.number().int().min(0)
  })
  .openapi("AgentActivityListResponse");

export const AgentActivityUndoBatchRequestSchema = z
  .object({
    batchId: z.string().trim().min(1).openapi({
      description: "The Activity Log batch id to revert."
    }),
    idempotencyKey: z.string().min(1).max(200).openapi({
      description:
        "Stable key for this undo request. Replays with the same key do not append another Activity Log batch; they return the original result."
    })
  })
  .openapi("AgentActivityUndoBatchRequest");

const AgentActivityUndoOutcomeSchema = z
  .enum(["reverted", "skipped_stale", "skipped_missing", "skipped_unsupported"])
  .openapi("AgentActivityUndoOutcome");

const AgentActivityUndoEntryResultSchema = z
  .object({
    entryId: z.string().min(1),
    entityTable: z.string().min(1),
    entityId: z.string().min(1),
    outcome: AgentActivityUndoOutcomeSchema
  })
  .openapi("AgentActivityUndoEntryResult");

export const AgentActivityUndoBatchResponseSchema = z
  .object({
    accepted: z.literal(true),
    applied: z.boolean().openapi({
      description:
        "True when the undo was applied as a new write batch (or recognized as an idempotent replay). False when the undo was aborted because at least one entry conflicted — mirroring the app's batch-atomic undoBatch, nothing is applied and no new batch is recorded."
    }),
    duplicate: z.boolean(),
    originalBatchId: z.string().min(1),
    undoBatchId: z.string().min(1).nullable().openapi({
      description:
        "The idempotencyKey of the new undo batch, or null when the undo was aborted (no batch recorded)."
    }),
    serverClock: z.string().min(1),
    entries: z.array(AgentActivityUndoEntryResultSchema)
  })
  .openapi("AgentActivityUndoBatchResponse");

export const AgentActivityBatchNotFoundResponseSchema = z
  .object({
    code: z.literal("activity_batch_not_found"),
    message: z.string().min(1)
  })
  .openapi("AgentActivityBatchNotFoundResponse");

export const AgentActivityUnavailableResponseSchema = z
  .object({
    code: z.literal("agent_activity_unavailable"),
    message: z.string().min(1)
  })
  .openapi("AgentActivityUnavailableResponse");

export const agentActivityListRoute = createRoute({
  method: "get",
  path: "/agent/activity",
  operationId: "listAgentActivity",
  tags: ["Agent Reads"],
  summary: "List the caller's Activity Log batches.",
  description:
    "Returns a bounded, cursor-paginated page of Activity Log batches for code-mode agents so they can see exactly what changed (accountability). Entries carry the before/after images that make an undo an ordinary, recoverable write.",
  security: [{ bearerAuth: [] }],
  request: {
    query: AgentActivityListQuerySchema
  },
  responses: {
    200: {
      description: "A bounded page of Activity Log batches.",
      content: {
        "application/json": {
          schema: AgentActivityListResponseSchema
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
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key or Activity Log storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentActivityUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export const agentActivityUndoBatchRoute = createRoute({
  method: "post",
  path: "/agent/activity/undo-batch",
  operationId: "undoAgentActivityBatch",
  tags: ["Agent Writes"],
  summary: "Revert an Activity Log batch as a new ordinary write.",
  description:
    "Applies the inverse images of a prior Activity Log batch as a NEW ordinary write batch (mirroring the app's undoBatch), propagating via a sync nudge. Rows whose current state no longer matches the recorded after-image are skipped and surfaced per row (silent LWW). Idempotent by idempotencyKey; nothing is hard-deleted.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: AgentActivityUndoBatchRequestSchema
        }
      }
    }
  },
  responses: {
    200: {
      description:
        "The undo batch was applied, or recognized as an idempotent replay.",
      content: {
        "application/json": {
          schema: AgentActivityUndoBatchResponseSchema
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
    404: {
      description:
        "No Activity Log batch with that id is visible to the caller.",
      content: {
        "application/json": {
          schema: AgentActivityBatchNotFoundResponseSchema
        }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key or Activity Log storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentActivityUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export type AgentActivityListQuery = z.infer<typeof AgentActivityListQuerySchema>;
export type AgentActivityListResponse = z.infer<
  typeof AgentActivityListResponseSchema
>;
export type AgentActivityUndoBatchResponse = z.infer<
  typeof AgentActivityUndoBatchResponseSchema
>;
type AgentActivityUndoOutcome = z.infer<typeof AgentActivityUndoOutcomeSchema>;

export type AgentActivityStore = {
  listActivity(input: {
    userId: string;
    query: AgentActivityListQuery;
  }): Promise<AgentActivityListResponse>;
  undoBatch(input: {
    userId: string;
    batchId: string;
    idempotencyKey: string;
    deviceId: string;
  }): Promise<
    | {
        accepted: true;
        applied: boolean;
        duplicate: boolean;
        serverClock: string;
        undoBatchId: string | null;
        activityLogEntries: number;
        appliedRows: { id: string; updatedAt: string; deviceId: string }[];
        entries: {
          entryId: string;
          entityTable: string;
          entityId: string;
          outcome: AgentActivityUndoOutcome;
        }[];
      }
    | { accepted: false; code: "activity_batch_not_found" }
  >;
};

type OpaqueTable =
  | typeof schema.exerciseCategories
  | typeof schema.exercises
  | typeof schema.workoutSessions
  | typeof schema.workoutExercises
  | typeof schema.exerciseGroups
  | typeof schema.exerciseGroupMembers
  | typeof schema.loggedSets
  | typeof schema.foods
  | typeof schema.mealTypes
  | typeof schema.meals
  | typeof schema.foodEntries
  | typeof schema.nutritionGoals
  | typeof schema.compounds
  | typeof schema.doses
  | typeof schema.protocols
  | typeof schema.protocolCompounds
  | typeof schema.schedules
  | typeof schema.protocolTargetOutcomes
  | typeof schema.routines
  | typeof schema.workoutTemplates
  | typeof schema.templateExercises
  | typeof schema.prescriptions
  | typeof schema.templateGroups
  | typeof schema.templateGroupMembers
  | typeof schema.routineEntries
  | typeof schema.templateLinks;

type PushInTransaction = (
  transaction: MutationDatabase,
  input: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
) => Promise<SyncPushResult>;

type MutationDatabase = Pick<ServerDatabase, "select" | "insert" | "update">;

// Registry of opaque-payload sync entities the agent can undo. Each maps the
// Activity Log `entity_table` string to the physical row table and that
// entity's own sync push path — so an undo runs through the identical LWW,
// tenant-isolation, and Activity Log wiring as any other write. Typed agent
// entities (metrics/readings) and batch markers are intentionally absent: their
// Activity Log images are serialized projections, not raw row payloads, so they
// are surfaced as `skipped_unsupported` rather than reverted through this path.
const UNDOABLE_ENTITY_REGISTRY: Record<
  string,
  { table: OpaqueTable; push: PushInTransaction }
> = {
  [EXERCISE_CATEGORIES_SYNC_ENTITY]: {
    table: schema.exerciseCategories,
    push: pushExerciseCategoriesInTransaction
  },
  [EXERCISES_SYNC_ENTITY]: {
    table: schema.exercises,
    push: pushExercisesInTransaction
  },
  [WORKOUT_SESSIONS_SYNC_ENTITY]: {
    table: schema.workoutSessions,
    push: pushWorkoutSessionsInTransaction
  },
  [WORKOUT_EXERCISES_SYNC_ENTITY]: {
    table: schema.workoutExercises,
    push: pushWorkoutExercisesInTransaction
  },
  [EXERCISE_GROUPS_SYNC_ENTITY]: {
    table: schema.exerciseGroups,
    push: pushExerciseGroupsInTransaction
  },
  [EXERCISE_GROUP_MEMBERS_SYNC_ENTITY]: {
    table: schema.exerciseGroupMembers,
    push: pushExerciseGroupMembersInTransaction
  },
  [LOGGED_SETS_SYNC_ENTITY]: {
    table: schema.loggedSets,
    push: pushLoggedSetsInTransaction
  },
  [FOODS_SYNC_ENTITY]: {
    table: schema.foods,
    push: pushFoodsInTransaction
  },
  [MEAL_TYPES_SYNC_ENTITY]: {
    table: schema.mealTypes,
    push: pushMealTypesInTransaction
  },
  [MEALS_SYNC_ENTITY]: {
    table: schema.meals,
    push: pushMealsInTransaction
  },
  [FOOD_ENTRIES_SYNC_ENTITY]: {
    table: schema.foodEntries,
    push: pushFoodEntriesInTransaction
  },
  [NUTRITION_GOALS_SYNC_ENTITY]: {
    table: schema.nutritionGoals,
    push: pushNutritionGoalsInTransaction
  },
  [COMPOUNDS_SYNC_ENTITY]: {
    table: schema.compounds,
    push: pushCompoundsInTransaction
  },
  [DOSES_SYNC_ENTITY]: {
    table: schema.doses,
    push: pushDosesInTransaction
  },
  [PROTOCOLS_SYNC_ENTITY]: {
    table: schema.protocols,
    push: pushProtocolsInTransaction
  },
  [PROTOCOL_COMPOUNDS_SYNC_ENTITY]: {
    table: schema.protocolCompounds,
    push: pushProtocolCompoundsInTransaction
  },
  [SCHEDULES_SYNC_ENTITY]: {
    table: schema.schedules,
    push: pushSchedulesInTransaction
  },
  [PROTOCOL_TARGET_OUTCOMES_SYNC_ENTITY]: {
    table: schema.protocolTargetOutcomes,
    push: pushProtocolTargetOutcomesInTransaction
  },
  [ROUTINES_SYNC_ENTITY]: {
    table: schema.routines,
    push: pushRoutinesInTransaction
  },
  [WORKOUT_TEMPLATES_SYNC_ENTITY]: {
    table: schema.workoutTemplates,
    push: pushWorkoutTemplatesInTransaction
  },
  [TEMPLATE_EXERCISES_SYNC_ENTITY]: {
    table: schema.templateExercises,
    push: pushTemplateExercisesInTransaction
  },
  [PRESCRIPTIONS_SYNC_ENTITY]: {
    table: schema.prescriptions,
    push: pushPrescriptionsInTransaction
  },
  [TEMPLATE_GROUPS_SYNC_ENTITY]: {
    table: schema.templateGroups,
    push: pushTemplateGroupsInTransaction
  },
  [TEMPLATE_GROUP_MEMBERS_SYNC_ENTITY]: {
    table: schema.templateGroupMembers,
    push: pushTemplateGroupMembersInTransaction
  },
  [ROUTINE_ENTRIES_SYNC_ENTITY]: {
    table: schema.routineEntries,
    push: pushRoutineEntriesInTransaction
  },
  [TEMPLATE_LINKS_SYNC_ENTITY]: {
    table: schema.templateLinks,
    push: pushTemplateLinksInTransaction
  }
};

type ActivityLogRow = typeof schema.activityLog.$inferSelect;

export function createDrizzleAgentActivityStore(
  db: ServerDatabase
): AgentActivityStore {
  return {
    async listActivity({ userId, query }) {
      const conditions = [eq(schema.activityLog.userId, userId)];
      if (query.actor !== undefined) {
        conditions.push(eq(schema.activityLog.actor, query.actor));
      }
      if (query.entityTable !== undefined) {
        conditions.push(eq(schema.activityLog.entityTable, query.entityTable));
      }
      if (query.batchId !== undefined) {
        conditions.push(eq(schema.activityLog.batchId, query.batchId));
      }
      const from = parseOptionalDate(query.from);
      const to = parseOptionalDate(query.to);
      if (from !== null) {
        conditions.push(gte(schema.activityLog.occurredAt, from));
      }
      if (to !== null) {
        conditions.push(lte(schema.activityLog.occurredAt, to));
      }

      const rows = await db
        .select()
        .from(schema.activityLog)
        .where(and(...conditions))
        .orderBy(
          desc(schema.activityLog.occurredAt),
          asc(schema.activityLog.id)
        );

      const batches = groupIntoBatches(rows);
      const start = cursorOffset(batches, query.cursor);
      const page = batches.slice(start, start + query.limit);

      return AgentActivityListResponseSchema.parse({
        batches: page,
        limit: query.limit,
        nextCursor:
          start + page.length >= batches.length
            ? null
            : page[page.length - 1]?.batchId ?? null,
        totalMatched: batches.length
      });
    },
    async undoBatch({ userId, batchId, idempotencyKey, deviceId }) {
      const serverClock = new Date();

      return db.transaction(async (transaction) => {
        // Idempotency: a prior undo under this key returns the original result
        // without appending a second batch.
        const existingUndoRows = await transaction
          .select({ id: schema.activityLog.id })
          .from(schema.activityLog)
          .where(
            and(
              eq(schema.activityLog.userId, userId),
              eq(schema.activityLog.batchId, idempotencyKey)
            )
          )
          .limit(1);
        if (existingUndoRows.length > 0) {
          return {
            accepted: true as const,
            applied: true,
            duplicate: true,
            serverClock: serverClock.toISOString(),
            undoBatchId: idempotencyKey,
            activityLogEntries: 0,
            appliedRows: [],
            entries: []
          };
        }

        const entries = await transaction
          .select()
          .from(schema.activityLog)
          .where(
            and(
              eq(schema.activityLog.userId, userId),
              eq(schema.activityLog.batchId, batchId)
            )
          )
          .orderBy(
            asc(schema.activityLog.occurredAt),
            asc(schema.activityLog.id)
          );

        const undoableEntries = entries.filter(
          (entry) => !AGENT_BATCH_MARKER_ENTITIES.has(entry.entityTable)
        );
        if (undoableEntries.length === 0) {
          return { accepted: false as const, code: "activity_batch_not_found" };
        }

        // The app's ActivityLogRepository.undoBatch is batch-ATOMIC: it
        // pre-checks EVERY entry against its recorded after-image and, if any
        // single entry conflicts, aborts the whole undo (nothing applied,
        // undoBatchId null, only the conflicting entries surfaced, no new
        // Activity Log batch). We mirror that here — never a straddled,
        // half-reverted state. Undo of semantically-coupled writes is
        // all-or-nothing.

        // Reverse order so a create-then-edit batch unwinds edits before the
        // create, mirroring the app's undoBatch (entries applied in reverse).
        const orderedEntries = [...undoableEntries].reverse();

        // Pass 1: pre-check. Collect conflicts; if any, abort without mutating.
        const conflicts: {
          entryId: string;
          entityTable: string;
          entityId: string;
          outcome: AgentActivityUndoOutcome;
        }[] = [];
        const applicable: {
          entry: ActivityLogRow;
          registryEntry: { table: OpaqueTable; push: PushInTransaction };
          afterImage: Record<string, unknown>;
        }[] = [];
        for (const entry of orderedEntries) {
          const registryEntry = UNDOABLE_ENTITY_REGISTRY[entry.entityTable];
          if (registryEntry === undefined) {
            conflicts.push({
              entryId: entry.id,
              entityTable: entry.entityTable,
              entityId: entry.entityId,
              outcome: "skipped_unsupported"
            });
            continue;
          }

          const currentPayload = await readCurrentPayload(
            transaction,
            registryEntry.table,
            userId,
            entry.entityId
          );
          const afterImage = entry.afterImage;

          // The row must currently match the recorded after-image, else a later
          // write has changed it and undo cannot safely revert (LWW conflict).
          if (currentPayload === null || afterImage === null) {
            conflicts.push({
              entryId: entry.id,
              entityTable: entry.entityTable,
              entityId: entry.entityId,
              outcome: "skipped_missing"
            });
            continue;
          }
          if (!isDeepStrictEqual(currentPayload, afterImage)) {
            conflicts.push({
              entryId: entry.id,
              entityTable: entry.entityTable,
              entityId: entry.entityId,
              outcome: "skipped_stale"
            });
            continue;
          }

          applicable.push({ entry, registryEntry, afterImage });
        }

        if (conflicts.length > 0) {
          // Abort: apply nothing, record no undo batch, surface only the
          // conflicting entries (mirroring the app's per-row conflict list).
          return {
            accepted: true as const,
            applied: false,
            duplicate: false,
            serverClock: serverClock.toISOString(),
            undoBatchId: null,
            activityLogEntries: 0,
            appliedRows: [],
            entries: conflicts
          };
        }

        // Pass 2: apply. Every entry pre-checked clean, so each reverts.
        const results: {
          entryId: string;
          entityTable: string;
          entityId: string;
          outcome: AgentActivityUndoOutcome;
        }[] = [];
        const appliedRows: {
          id: string;
          updatedAt: string;
          deviceId: string;
        }[] = [];
        let activityLogEntries = 0;

        for (const { entry, registryEntry, afterImage } of applicable) {
          const inverse = inversePayload(entry, serverClock);
          const change: SyncPushChange = {
            id: entry.entityId,
            payload: inverse.payload,
            updatedAt: inverse.updatedAt,
            deletedAt: inverse.deletedAt,
            activityLogId: `agent:${idempotencyKey}:${entry.entityTable}:${entry.entityId}`,
            actor: "agent",
            batchId: idempotencyKey,
            beforeImage: afterImage,
            afterImage: inverse.payload,
            occurredAt: inverse.updatedAt
          };
          const pushResult = await registryEntry.push(transaction, {
            userId,
            deviceId,
            changes: [change],
            serverClock
          });
          activityLogEntries += 1;
          for (const appliedChange of pushResult.applied) {
            appliedRows.push(appliedChange);
          }
          results.push({
            entryId: entry.id,
            entityTable: entry.entityTable,
            entityId: entry.entityId,
            outcome: "reverted"
          });
        }

        return {
          accepted: true as const,
          applied: true,
          duplicate: false,
          serverClock: serverClock.toISOString(),
          undoBatchId: idempotencyKey,
          activityLogEntries,
          appliedRows,
          entries: results
        };
      });
    }
  };
}

async function readCurrentPayload(
  transaction: MutationDatabase,
  table: OpaqueTable,
  userId: string,
  id: string
): Promise<Record<string, unknown> | null> {
  const rows = await transaction
    .select({ userId: table.userId, payload: table.payload })
    .from(table)
    .where(eq(table.id, id))
    .limit(1);
  const existing = rows[0];
  if (existing === undefined || existing.userId !== userId) {
    return null;
  }

  return existing.payload as Record<string, unknown>;
}

/**
 * The inverse of an Activity Log entry, mirroring the app's
 * `_inverseImageForUndo`: restore the before-image (restamped now); a create
 * (no before-image) inverts to its after-image with a fresh tombstone, so undo
 * of a create is an archive — never a hard delete.
 */
function inversePayload(
  entry: ActivityLogRow,
  serverClock: Date
): { payload: Record<string, unknown>; updatedAt: string; deletedAt: string | null } {
  const source = entry.beforeImage ?? entry.afterImage;
  if (source === null || source === undefined) {
    // An entry with neither image is not invertible; the caller filters these
    // out earlier, but be defensive.
    const nowIso = serverClock.toISOString();
    return { payload: { updated_at: nowIso, deleted_at: nowIso }, updatedAt: nowIso, deletedAt: nowIso };
  }

  const nowIso = serverClock.toISOString();
  const payload: Record<string, unknown> = { ...source, updated_at: nowIso };
  const deletedAt =
    entry.beforeImage === null || entry.beforeImage === undefined
      ? nowIso
      : normalizeDeletedAt(source.deleted_at);
  payload.deleted_at = deletedAt;

  return { payload, updatedAt: nowIso, deletedAt };
}

function normalizeDeletedAt(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function groupIntoBatches(rows: ActivityLogRow[]) {
  const order: string[] = [];
  const byBatch = new Map<
    string,
    {
      batchId: string;
      actor: string;
      occurredAt: Date;
      entries: {
        id: string;
        entityTable: string;
        entityId: string;
        beforeImage: Record<string, unknown> | null;
        afterImage: Record<string, unknown> | null;
        occurredAt: string;
      }[];
    }
  >();

  for (const row of rows) {
    if (AGENT_BATCH_MARKER_ENTITIES.has(row.entityTable)) {
      continue;
    }
    let batch = byBatch.get(row.batchId);
    if (batch === undefined) {
      batch = {
        batchId: row.batchId,
        actor: row.actor,
        occurredAt: row.occurredAt,
        entries: []
      };
      byBatch.set(row.batchId, batch);
      order.push(row.batchId);
    }
    if (row.occurredAt > batch.occurredAt) {
      batch.occurredAt = row.occurredAt;
    }
    batch.entries.push({
      id: row.id,
      entityTable: row.entityTable,
      entityId: row.entityId,
      beforeImage: row.beforeImage ?? null,
      afterImage: row.afterImage ?? null,
      occurredAt: row.occurredAt.toISOString()
    });
  }

  return order.map((batchId) => {
    const batch = byBatch.get(batchId)!;
    batch.entries.sort((left, right) => {
      const byTime = left.occurredAt.localeCompare(right.occurredAt);
      return byTime !== 0 ? byTime : left.id.localeCompare(right.id);
    });
    return {
      batchId: batch.batchId,
      actor: batch.actor,
      occurredAt: batch.occurredAt.toISOString(),
      entries: batch.entries
    };
  });
}

function cursorOffset(
  batches: { batchId: string }[],
  cursor: string | undefined
): number {
  if (cursor === undefined) {
    return 0;
  }
  const index = batches.findIndex((batch) => batch.batchId === cursor);
  return index === -1 ? batches.length : index + 1;
}

function parseOptionalDate(value: string | undefined): Date | null {
  if (value === undefined) {
    return null;
  }
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? null : date;
}
