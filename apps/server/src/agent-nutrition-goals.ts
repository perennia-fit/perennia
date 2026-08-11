import { createRoute, z } from "@hono/zod-openapi";
import { and, asc, eq, isNull } from "drizzle-orm";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import {
  AgentNutritionGoalTargetForValidationSchema,
  AgentNutrientValidationIssueSchema,
  validateAgentNutritionGoalTargets,
  type AgentNutrientValidationIssue
} from "./agent-validation.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import { GOALABLE_NUTRIENT_IDS, type NutrientId } from "./analytics/nutrition-analytics.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";
import {
  NUTRITION_GOALS_SYNC_ENTITY,
  pushNutritionGoalsInTransaction,
  type SyncPushChange
} from "./sync.js";

export const AGENT_NUTRITION_GOAL_BATCH_WRITE_MAX_TARGETS =
  GOALABLE_NUTRIENT_IDS.length;

const ISO8601StringSchema = z.string().min(1).openapi({
  description: "ISO-8601 timestamp."
});

const GoalableNutrientIdSchema = z
  .enum(GOALABLE_NUTRIENT_IDS as [NutrientId, ...NutrientId[]])
  .openapi("AgentNutritionGoalableNutrientId");

const NutrientUnitSchema = z
  .enum(["kilocalorie", "gram", "milligram", "microgram", "milliliter"])
  .openapi("AgentNutritionGoalUnit");

export const AgentNutritionGoalSchema = z
  .object({
    id: z.string().min(1),
    nutrient: GoalableNutrientIdSchema,
    value: z.number(),
    unit: NutrientUnitSchema,
    updatedAt: ISO8601StringSchema,
    deletedAt: ISO8601StringSchema.nullable()
  })
  .openapi("AgentNutritionGoal");

export const AgentNutritionGoalListResponseSchema = z
  .object({
    goals: z.array(AgentNutritionGoalSchema).openapi({
      description:
        "Current (live, non-archived) per-nutrient Goal targets, one per goalable Nutrient at most."
    })
  })
  .openapi("AgentNutritionGoalListResponse");

export const AgentNutritionGoalBatchWriteTargetSchema = z
  .object({
    id: z.string().min(1).openapi({
      description:
        "Client-supplied UUIDv7 Nutrition Goal row id. Reuse the existing id to update/clear that Goal; a new id creates one, superseding the prior live target for the same Nutrient."
    }),
    nutrient: GoalableNutrientIdSchema,
    value: z.number().openapi({
      description:
        "Configured target value (never a stored total). Ignored when deletedAt is set."
    }),
    unit: NutrientUnitSchema.optional().openapi({
      description: "Defaults to the Nutrient's canonical unit when omitted."
    }),
    updatedAt: ISO8601StringSchema.optional().openapi({
      description:
        "Client-observed row update clock. Defaults to the server receive time when omitted."
    }),
    deletedAt: ISO8601StringSchema.nullable().default(null).openapi({
      description:
        "Nullable archive tombstone. Setting it clears the Goal target — an ordinary LWW write of a tombstone, never a purge."
    })
  })
  .openapi("AgentNutritionGoalBatchWriteTarget");

export const AgentNutritionGoalBatchWriteRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200).openapi({
      description:
        "Stable key for this agent request. Replays with the same key return the original result without appending another Activity Log batch."
    }),
    targets: z
      .array(AgentNutritionGoalBatchWriteTargetSchema)
      .min(1)
      .max(AGENT_NUTRITION_GOAL_BATCH_WRITE_MAX_TARGETS)
      .openapi({
        description:
          "Goal targets to create/update/clear atomically as one Activity Log batch."
      })
  })
  .openapi("AgentNutritionGoalBatchWriteRequest");

export const AgentNutritionGoalBatchWriteIssueSchema =
  AgentNutrientValidationIssueSchema.extend({
    itemIndex: z.number().int().min(0).openapi({
      description: "Index of the target item that produced the issue."
    }),
    targetId: z.string().min(1).openapi({
      description: "Client-supplied Goal row id for the failed item."
    })
  }).openapi("AgentNutritionGoalBatchWriteIssue");

export const AgentNutritionGoalBatchWriteTargetResultSchema = z
  .object({
    id: z.string().min(1),
    nutrient: GoalableNutrientIdSchema,
    outcome: z.enum(["applied", "superseded", "duplicate"])
  })
  .openapi("AgentNutritionGoalBatchWriteTargetResult");

export const AgentNutritionGoalBatchWriteResponseSchema = z
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
    serverClock: z.string().min(1),
    targets: z.array(AgentNutritionGoalBatchWriteTargetResultSchema)
  })
  .openapi("AgentNutritionGoalBatchWriteResponse");

export const AgentNutritionGoalBatchWriteErrorResponseSchema = z
  .object({
    code: z.literal("agent_nutrition_goal_batch_write_failed"),
    message: z.string().min(1),
    errors: z.array(AgentNutritionGoalBatchWriteIssueSchema)
  })
  .openapi("AgentNutritionGoalBatchWriteErrorResponse");

export const AgentNutritionGoalUnavailableResponseSchema = z
  .object({
    code: z.literal("agent_nutrition_goal_unavailable"),
    message: z.string().min(1)
  })
  .openapi("AgentNutritionGoalUnavailableResponse");

export const agentNutritionGoalListRoute = createRoute({
  method: "get",
  path: "/agent/nutrition/goals",
  operationId: "listAgentNutritionGoals",
  tags: ["Agent Reads"],
  summary: "List the caller's current per-nutrient Nutrition Goal targets.",
  description:
    "Returns the live (non-archived) Nutrition Goal target for each goalable Nutrient (v1: energy + protein/carbohydrate/fat, NUTRITION.md §4) the caller has configured. Goal targets are configuration, never a stored derived total. Fixes the root cause of totals/trends needing goal query params on every call — stored Goals are now readable directly and used by default.",
  security: [{ bearerAuth: [] }],
  responses: {
    200: {
      description: "The caller's current Nutrition Goal targets.",
      content: {
        "application/json": {
          schema: AgentNutritionGoalListResponseSchema
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
      description: "Agent API key or Nutrition Goal storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentNutritionGoalUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export const agentNutritionGoalBatchWriteRoute = createRoute({
  method: "post",
  path: "/agent/nutrition/goals/batch-write",
  operationId: "batchWriteAgentNutritionGoals",
  tags: ["Agent Writes"],
  summary:
    "Batch-write per-nutrient Nutrition Goal targets as one Activity Log batch.",
  description:
    "Authenticated agent write path for Nutrition Goals: create, update, or clear (via deletedAt) per-nutrient targets, validated with the same shared two-tier nutrient validator used by Food Entries (NUTRITION.md §6), applied atomically with one Activity Log batch and a best-effort sync nudge. Nutrient keys are restricted to the fixed goalable registry: energy, protein, carbohydrate, fat.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: AgentNutritionGoalBatchWriteRequestSchema
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
          schema: AgentNutritionGoalBatchWriteResponseSchema
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
        "One or more targets failed hard validation; no rows were written.",
      content: {
        "application/json": {
          schema: AgentNutritionGoalBatchWriteErrorResponseSchema
        }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key or Nutrition Goal storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentNutritionGoalUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export type AgentNutritionGoal = z.infer<typeof AgentNutritionGoalSchema>;
export type AgentNutritionGoalListResponse = z.infer<
  typeof AgentNutritionGoalListResponseSchema
>;
export type AgentNutritionGoalBatchWriteRequest = z.infer<
  typeof AgentNutritionGoalBatchWriteRequestSchema
>;
export type AgentNutritionGoalBatchWriteTarget = z.infer<
  typeof AgentNutritionGoalBatchWriteTargetSchema
>;
export type AgentNutritionGoalBatchWriteIssue = z.infer<
  typeof AgentNutritionGoalBatchWriteIssueSchema
>;
export type AgentNutritionGoalBatchWriteResponse = z.infer<
  typeof AgentNutritionGoalBatchWriteResponseSchema
>;

export type AgentNutritionGoalReadStore = {
  /** Live (non-tombstoned) current Goal target per goalable Nutrient. */
  listNutritionGoals(input: { userId: string }): Promise<AgentNutritionGoal[]>;
};

export type AgentNutritionGoalBatchWriteStore = AgentNutritionGoalReadStore & {
  writeNutritionGoalBatch(input: {
    userId: string;
    batchId: string;
    correlationId?: string;
    deviceId: string;
    request: AgentNutritionGoalBatchWriteRequest;
  }): Promise<
    | {
        accepted: true;
        duplicate: boolean;
        serverClock: string;
        applied: { id: string; updatedAt: string; deviceId: string }[];
        targets: z.infer<typeof AgentNutritionGoalBatchWriteTargetResultSchema>[];
      }
    | {
        accepted: false;
        errors: AgentNutritionGoalBatchWriteIssue[];
      }
  >;
};

type MutationDatabase = Pick<ServerDatabase, "select" | "insert" | "update">;
type NutritionGoalRow = typeof schema.nutritionGoals.$inferSelect;

export function createDrizzleAgentNutritionGoalStore(
  db: ServerDatabase
): AgentNutritionGoalBatchWriteStore {
  return {
    async listNutritionGoals({ userId }) {
      const rowsByNutrient = await readCurrentGoalRowsByNutrient(db, userId);

      return GOALABLE_NUTRIENT_IDS.flatMap((nutrient) => {
        const row = rowsByNutrient.get(nutrient);
        return row === undefined ? [] : [row];
      });
    },
    async writeNutritionGoalBatch({
      userId,
      batchId,
      correlationId,
      deviceId,
      request
    }) {
      const serverClock = new Date();
      const errors: AgentNutritionGoalBatchWriteIssue[] = [];
      const seenIds = new Set<string>();

      for (const [itemIndex, target] of request.targets.entries()) {
        if (seenIds.has(target.id)) {
          errors.push(
            AgentNutritionGoalBatchWriteIssueSchema.parse({
              field: `targets[${itemIndex}].id`,
              nutrient: target.nutrient,
              rule: "duplicate_target_id",
              message: "A Nutrition Goal target id may appear only once per batch.",
              limit: null,
              itemIndex,
              targetId: target.id
            })
          );
          continue;
        }
        seenIds.add(target.id);

        // A cleared target (deletedAt set) carries no meaningful value to
        // validate — only a live target's value goes through the shared
        // per-nutrient hard-reject rules (NUTRITION.md §6).
        if (target.deletedAt !== null) {
          continue;
        }

        const validation = validateAgentNutritionGoalTargets({
          targets: [
            AgentNutritionGoalTargetForValidationSchema.parse({
              nutrient: target.nutrient,
              value: target.value
            })
          ]
        });
        for (const error of validation.errors) {
          errors.push(issueForError(error, { itemIndex, targetId: target.id }));
        }
      }

      if (errors.length > 0) {
        return { accepted: false, errors };
      }

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
            accepted: true,
            duplicate: true,
            serverClock: serverClock.toISOString(),
            applied: [],
            targets: request.targets.map((target) =>
              AgentNutritionGoalBatchWriteTargetResultSchema.parse({
                id: target.id,
                nutrient: target.nutrient,
                outcome: "duplicate"
              })
            )
          };
        }

        const nowIso = serverClock.toISOString();
        const changes: SyncPushChange[] = request.targets.map((target) => {
          const updatedAt = target.updatedAt ?? nowIso;
          const deletedAt = target.deletedAt ?? null;
          const payload = buildNutritionGoalPayload({
            target,
            updatedAt,
            deletedAt
          });
          return {
            id: target.id,
            payload,
            updatedAt,
            deletedAt,
            activityLogId: `agent:${batchId}:${target.id}`,
            actor: "agent",
            batchId,
            beforeImage: null,
            afterImage: payload,
            occurredAt: updatedAt
          };
        });

        const beforeImagesById = new Map<string, Record<string, unknown> | null>();
        for (const change of changes) {
          beforeImagesById.set(
            change.id,
            await readBeforeImage(transaction, { userId, rowId: change.id })
          );
        }
        const changesWithBeforeImages = changes.map((change) => ({
          ...change,
          beforeImage: beforeImagesById.get(change.id) ?? null
        }));

        const result = await pushNutritionGoalsInTransaction(transaction, {
          userId,
          deviceId,
          changes: changesWithBeforeImages,
          serverClock
        });

        const appliedIds = new Set(result.accepted);
        const targets = request.targets.map((target) =>
          AgentNutritionGoalBatchWriteTargetResultSchema.parse({
            id: target.id,
            nutrient: target.nutrient,
            outcome: appliedIds.has(target.id) ? "applied" : "superseded"
          })
        );

        return {
          accepted: true,
          duplicate: false,
          serverClock: result.serverClock,
          applied: result.applied,
          targets
        };
      });
    }
  };
}

async function readCurrentGoalRowsByNutrient(
  db: Pick<ServerDatabase, "select">,
  userId: string
): Promise<Map<NutrientId, AgentNutritionGoal>> {
  const rows = await db
    .select()
    .from(schema.nutritionGoals)
    .where(
      and(
        eq(schema.nutritionGoals.userId, userId),
        isNull(schema.nutritionGoals.deletedAt)
      )
    )
    .orderBy(asc(schema.nutritionGoals.updatedAt), asc(schema.nutritionGoals.id));

  const byNutrient = new Map<NutrientId, AgentNutritionGoal>();
  for (const row of rows) {
    const nutrient = nutrientIdFromPayload(row.payload);
    const value = numberValue(row.payload.target_value);
    const unit = stringValue(row.payload.unit);
    if (nutrient === null || value === null || unit === null) {
      continue;
    }
    // Rows are ordered oldest -> newest by updatedAt, so the last write for a
    // nutrient wins — matching the device's "one active row per Nutrient"
    // invariant (training_repositories.dart `_activeNutritionGoalRowFor`).
    byNutrient.set(
      nutrient,
      AgentNutritionGoalSchema.parse({
        id: row.id,
        nutrient,
        value,
        unit,
        updatedAt: row.updatedAt.toISOString(),
        deletedAt: row.deletedAt?.toISOString() ?? null
      })
    );
  }

  return byNutrient;
}

function nutrientIdFromPayload(
  payload: Record<string, unknown>
): NutrientId | null {
  const raw = payload.nutrient_id;
  return typeof raw === "string" &&
    (GOALABLE_NUTRIENT_IDS as readonly string[]).includes(raw)
    ? (raw as NutrientId)
    : null;
}

function buildNutritionGoalPayload({
  target,
  updatedAt,
  deletedAt
}: {
  target: AgentNutritionGoalBatchWriteTarget;
  updatedAt: string;
  deletedAt: string | null;
}): Record<string, unknown> {
  return {
    id: target.id,
    nutrient_id: target.nutrient,
    target_value: target.value,
    target_entered: String(target.value),
    unit: target.unit ?? nutrientDefaultUnitFallback(target.nutrient),
    updated_at: updatedAt,
    deleted_at: deletedAt
  };
}

function nutrientDefaultUnitFallback(nutrient: NutrientId): string {
  return nutrient === "energy" ? "kilocalorie" : "gram";
}

async function readBeforeImage(
  transaction: Pick<ServerDatabase, "select">,
  { userId, rowId }: { userId: string; rowId: string }
) {
  const existingRows = await transaction
    .select({
      userId: schema.nutritionGoals.userId,
      payload: schema.nutritionGoals.payload
    })
    .from(schema.nutritionGoals)
    .where(eq(schema.nutritionGoals.id, rowId))
    .limit(1);
  const existing = existingRows[0];
  if (existing === undefined || existing.userId !== userId) {
    return null;
  }

  return existing.payload;
}

function issueForError(
  issue: AgentNutrientValidationIssue,
  match: { itemIndex: number; targetId: string }
): AgentNutritionGoalBatchWriteIssue {
  return AgentNutritionGoalBatchWriteIssueSchema.parse({
    ...issue,
    field: `targets[${match.itemIndex}].value`,
    itemIndex: match.itemIndex,
    targetId: match.targetId
  });
}

function numberValue(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}
