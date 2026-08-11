import { createRoute, z } from "@hono/zod-openapi";
import { and, eq, inArray, or, sql, type SQL } from "drizzle-orm";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema,
} from "./agent-api-keys.js";
import {
  AgentCatalogUnavailableResponseSchema,
  type AgentCatalogStore,
  type AgentExercise,
} from "./agent-catalog.js";
import {
  AgentSetValidationIssueSchema,
  AgentSetValidationValuesSchema,
  PLAN_VALIDATION_LIMITS,
  validateAgentPrescription,
  validateAgentRoutineCadence,
  validateAgentTemplateGroup,
  type AgentSetValidationIssue,
} from "./agent-validation.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";
import {
  PRESCRIPTIONS_SYNC_ENTITY,
  ROUTINES_SYNC_ENTITY,
  ROUTINE_ENTRIES_SYNC_ENTITY,
  TEMPLATE_EXERCISES_SYNC_ENTITY,
  TEMPLATE_GROUP_MEMBERS_SYNC_ENTITY,
  TEMPLATE_GROUPS_SYNC_ENTITY,
  WORKOUT_TEMPLATES_SYNC_ENTITY,
  normalizeIncomingUpdatedAt,
  pushPrescriptionsInTransaction,
  pushRoutineEntriesInTransaction,
  pushRoutinesInTransaction,
  pushTemplateExercisesInTransaction,
  pushTemplateGroupMembersInTransaction,
  pushTemplateGroupsInTransaction,
  pushWorkoutTemplatesInTransaction,
  type SyncPushChange,
  type SyncPushResult,
} from "./sync.js";

export const AGENT_PLAN_TREE_BATCH_WRITE_MAX_ITEMS = 500;
export const AGENT_PLAN_TREE_BATCH_ENTITY = "agent_plan_tree_batches";

const ISO8601StringSchema = z.string().min(1).openapi({
  description: "ISO-8601 timestamp.",
});

export const AgentPlanTreeEntityTypeSchema = z
  .enum([
    "workoutTemplate",
    "templateExercise",
    "prescription",
    "templateGroup",
    "templateGroupMember",
    "routine",
    "routineEntry",
  ])
  .openapi("AgentPlanTreeEntityType");

const AgentPlanTreeSyncFieldsSchema = z.object({
  updatedAt: ISO8601StringSchema.optional().openapi({
    description:
      "Client-observed row update clock. Defaults to the server receive time when omitted.",
  }),
  deletedAt: ISO8601StringSchema.nullable().default(null).openapi({
    description:
      "Set to archive this plan row. Archive is an ordinary reversible LWW write; it never cascades to child plan rows, Workout history, or Logged Sets, and is never a purge.",
  }),
});

export const AgentPlanTreeBatchWriteWorkoutTemplateSchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "Client-supplied UUIDv7 Workout Template id.",
    }),
    name: z.string().openapi({
      description: "Workout Template name.",
    }),
    notes: z.string().nullable().default(null),
  })
  .merge(AgentPlanTreeSyncFieldsSchema)
  .openapi("AgentPlanTreeBatchWriteWorkoutTemplate");

export const AgentPlanTreeBatchWriteTemplateExerciseSchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "Client-supplied UUIDv7 Template Exercise id.",
    }),
    workoutTemplateId: z.string().min(1),
    exerciseId: z.string().min(1).openapi({
      description:
        "Caller-visible User or Platform Library Exercise id. Its Exercise Type drives Prescription validation.",
    }),
    position: z.number().int().min(0),
    note: z.string().nullable().default(null),
  })
  .merge(AgentPlanTreeSyncFieldsSchema)
  .openapi("AgentPlanTreeBatchWriteTemplateExercise");

export const AgentPlanTreeBatchWritePrescriptionSchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "Client-supplied UUIDv7 Prescription id.",
    }),
    templateExerciseId: z.string().min(1),
    mode: z.string().min(1).openapi({
      description: "Prescription mode: fixed or copyPrevious.",
    }),
    position: z.number().int().min(0),
    repeat: z.number(),
    restAfterSeconds: z.number().nullable().default(null),
    values: AgentSetValidationValuesSchema.default({}).openapi({
      description:
        "Self-describing planned values. Fixed values use the shared Set validator; copyPrevious ignores this object.",
    }),
  })
  .merge(AgentPlanTreeSyncFieldsSchema)
  .openapi("AgentPlanTreeBatchWritePrescription");

export const AgentPlanTreeBatchWriteTemplateGroupSchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "Client-supplied UUIDv7 Template Group id.",
    }),
    workoutTemplateId: z.string().min(1),
    name: z.string(),
    colorHex: z.string(),
    rounds: z.number(),
    position: z.number().int().min(0),
  })
  .merge(AgentPlanTreeSyncFieldsSchema)
  .openapi("AgentPlanTreeBatchWriteTemplateGroup");

export const AgentPlanTreeBatchWriteTemplateGroupMemberSchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "Client-supplied UUIDv7 Template Group Member id.",
    }),
    groupId: z.string().min(1),
    templateExerciseId: z.string().min(1),
    position: z.number().int().min(0),
  })
  .merge(AgentPlanTreeSyncFieldsSchema)
  .openapi("AgentPlanTreeBatchWriteTemplateGroupMember");

export const AgentPlanTreeBatchWriteRoutineSchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "Client-supplied UUIDv7 Routine id.",
    }),
    name: z.string(),
    notes: z.string().nullable().default(null),
    cadenceKind: z.string().nullable().default(null).openapi({
      description: "Cadence kind: weekly, rotating, or null for a collection.",
    }),
    cadenceWindow: z.number().nullable().default(null).openapi({
      description:
        "Rotating window length. Must be null for weekly and cadence-less Routines.",
    }),
  })
  .merge(AgentPlanTreeSyncFieldsSchema)
  .openapi("AgentPlanTreeBatchWriteRoutine");

export const AgentPlanTreeBatchWriteRoutineEntrySchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "Client-supplied UUIDv7 Routine Entry id.",
    }),
    routineId: z.string().min(1),
    workoutTemplateId: z.string().min(1),
    position: z.number().int().min(0),
    slot: z.number().nullable().default(null).openapi({
      description:
        "Weekly weekday 1..7, rotating position 1..N, or null for a cadence-less Routine.",
    }),
  })
  .merge(AgentPlanTreeSyncFieldsSchema)
  .openapi("AgentPlanTreeBatchWriteRoutineEntry");

export const AgentPlanTreeBatchWriteCountsSchema = z
  .object({
    workoutTemplates: z.number().int().min(0),
    templateExercises: z.number().int().min(0),
    prescriptions: z.number().int().min(0),
    templateGroups: z.number().int().min(0),
    templateGroupMembers: z.number().int().min(0),
    routines: z.number().int().min(0),
    routineEntries: z.number().int().min(0),
  })
  .strict()
  .openapi("AgentPlanTreeBatchWriteCounts");

export const AgentPlanTreeBatchWriteRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200).openapi({
      description:
        "Stable batch key. Replays with the same key converge without duplicating rows or appending another Activity Log batch.",
    }),
    expectedCounts: AgentPlanTreeBatchWriteCountsSchema.openapi({
      description:
        "Completeness assertion computed from the authorized plan manifest before serialization. Every value must exactly equal the corresponding request-array length; a mismatch rejects the request before validation or storage.",
    }),
    dryRun: z.boolean().default(false).openapi({
      description:
        "Validate and resolve the complete plan tree without writing rows, consuming the idempotency key, appending Activity Log entries, or publishing a sync nudge.",
    }),
    workoutTemplates: z
      .array(AgentPlanTreeBatchWriteWorkoutTemplateSchema)
      .max(AGENT_PLAN_TREE_BATCH_WRITE_MAX_ITEMS)
      .default([]),
    templateExercises: z
      .array(AgentPlanTreeBatchWriteTemplateExerciseSchema)
      .max(AGENT_PLAN_TREE_BATCH_WRITE_MAX_ITEMS)
      .default([]),
    prescriptions: z
      .array(AgentPlanTreeBatchWritePrescriptionSchema)
      .max(AGENT_PLAN_TREE_BATCH_WRITE_MAX_ITEMS)
      .default([]),
    templateGroups: z
      .array(AgentPlanTreeBatchWriteTemplateGroupSchema)
      .max(AGENT_PLAN_TREE_BATCH_WRITE_MAX_ITEMS)
      .default([]),
    templateGroupMembers: z
      .array(AgentPlanTreeBatchWriteTemplateGroupMemberSchema)
      .max(AGENT_PLAN_TREE_BATCH_WRITE_MAX_ITEMS)
      .default([]),
    routines: z
      .array(AgentPlanTreeBatchWriteRoutineSchema)
      .max(AGENT_PLAN_TREE_BATCH_WRITE_MAX_ITEMS)
      .default([]),
    routineEntries: z
      .array(AgentPlanTreeBatchWriteRoutineEntrySchema)
      .max(AGENT_PLAN_TREE_BATCH_WRITE_MAX_ITEMS)
      .default([]),
  })
  .superRefine((request, context) => {
    const actualCounts = planTreeBatchWriteCounts(request);
    for (const key of PLAN_TREE_COUNT_KEYS) {
      if (request.expectedCounts[key] !== actualCounts[key]) {
        context.addIssue({
          code: z.ZodIssueCode.custom,
          path: ["expectedCounts", key],
          message:
            `Expected ${request.expectedCounts[key]} ${key} rows but received ` +
            `${actualCounts[key]}. Rebuild the complete request from the authorized manifest.`,
        });
      }
    }
    const itemCount = requestItemCount(request);
    if (itemCount === 0) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "A plan-tree batch must contain at least one row.",
      });
    }
    if (itemCount > AGENT_PLAN_TREE_BATCH_WRITE_MAX_ITEMS) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: `A plan-tree batch may contain at most ${AGENT_PLAN_TREE_BATCH_WRITE_MAX_ITEMS} rows.`,
      });
    }
  })
  .openapi("AgentPlanTreeBatchWriteRequest");

export const AgentPlanTreeBatchWriteIssueSchema =
  AgentSetValidationIssueSchema.extend({
    entityType: AgentPlanTreeEntityTypeSchema,
    itemIndex: z.number().int().min(0),
    entityId: z.string().min(1),
  }).openapi("AgentPlanTreeBatchWriteIssue");

export const AgentPlanTreeBatchWriteItemResultSchema = z
  .object({
    entityType: AgentPlanTreeEntityTypeSchema,
    itemIndex: z.number().int().min(0),
    id: z.string().min(1),
    outcome: z.enum(["validated", "applied", "superseded", "duplicate"]),
    warnings: z.array(AgentSetValidationIssueSchema),
  })
  .openapi("AgentPlanTreeBatchWriteItemResult");

export const AgentPlanTreeBatchWriteLimitsSchema = z
  .object({
    maxItems: z.number().int().positive(),
    repeatMin: z.number().int(),
    repeatWarnAbove: z.number().int(),
    restAfterSecondsMin: z.number(),
    templateGroupRoundsMin: z.number().int(),
    templateGroupMembersMin: z.number().int(),
    templateGroupColorHexFormat: z.string(),
    cadenceKinds: z.array(z.string()),
    rotatingWindowMin: z.number().int(),
    rotatingWindowWarnAbove: z.number().int(),
    weeklySlotMin: z.number().int(),
    weeklySlotMax: z.number().int(),
    routineEntrySlotMin: z.number().int(),
  })
  .openapi("AgentPlanTreeBatchWriteLimits");

export const AgentPlanTreeBatchWriteResponseSchema = z
  .object({
    accepted: z.literal(true),
    dryRun: z.boolean(),
    duplicate: z.boolean(),
    idempotencyKey: z.string().min(1),
    batchId: z.string().min(1).nullable().openapi({
      description:
        "The single Activity Log batch id for an applied or duplicate request. Equal to idempotencyKey; null for a dry run.",
    }),
    serverClock: z.string().min(1),
    expectedCounts: AgentPlanTreeBatchWriteCountsSchema,
    actualCounts: AgentPlanTreeBatchWriteCountsSchema,
    items: z.array(AgentPlanTreeBatchWriteItemResultSchema),
  })
  .openapi("AgentPlanTreeBatchWriteResponse");

export const AgentPlanTreeBatchWriteErrorResponseSchema = z
  .object({
    code: z.literal("agent_plan_tree_batch_write_failed"),
    message: z.string().min(1),
    errors: z.array(AgentPlanTreeBatchWriteIssueSchema),
    warnings: z.array(AgentPlanTreeBatchWriteIssueSchema),
    limits: AgentPlanTreeBatchWriteLimitsSchema,
  })
  .openapi("AgentPlanTreeBatchWriteErrorResponse");

export const AgentPlanTreeBatchWriteUnavailableResponseSchema = z
  .object({
    code: z.literal("agent_plan_tree_batch_write_unavailable"),
    message: z.string().min(1),
  })
  .openapi("AgentPlanTreeBatchWriteUnavailableResponse");

export const agentPlanTreeBatchWriteRoute = createRoute({
  method: "post",
  path: "/agent/plan-tree/batch-write",
  operationId: "batchWriteAgentPlanTree",
  tags: ["Agent Writes"],
  summary: "Batch-write the authored plan tree as one Activity Log batch.",
  description:
    "Validates, creates, edits, restores, or archives Workout Templates, Template Exercises, Prescriptions, Template Groups and members, Routines, Cadences, and Routine Entries in one capped atomic request. The caller must declare expected row counts so truncated or incomplete serialization is rejected before storage, and may first submit the same request as a non-writing dry run. Client UUIDv7 ids are upserted through the ordinary sync rails; hard validation aborts the whole request, soft validation is returned per item, replay is idempotent by batch key, and archive never cascades. Template Links are intentionally created by the separate materialize operation, not by plan authoring.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: AgentPlanTreeBatchWriteRequestSchema,
        },
      },
    },
  },
  responses: {
    200: {
      description:
        "The batch was accepted, or recognized as an idempotent replay.",
      content: {
        "application/json": {
          schema: AgentPlanTreeBatchWriteResponseSchema,
        },
      },
    },
    401: {
      description: "The request is missing a valid agent API key.",
      content: {
        "application/json": {
          schema: AgentUnauthorizedResponseSchema,
        },
      },
    },
    422: {
      description:
        "One or more plan rows failed hard validation or reference resolution; no rows were written.",
      content: {
        "application/json": {
          schema: AgentPlanTreeBatchWriteErrorResponseSchema,
        },
      },
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description:
        "Agent API key, Exercise catalog, or plan-tree write storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentCatalogUnavailableResponseSchema,
            AgentPlanTreeBatchWriteUnavailableResponseSchema,
          ]),
        },
      },
    },
  },
});

export type AgentPlanTreeEntityType = z.infer<
  typeof AgentPlanTreeEntityTypeSchema
>;
export type AgentPlanTreeBatchWriteRequest = z.infer<
  typeof AgentPlanTreeBatchWriteRequestSchema
>;
export type AgentPlanTreeBatchWriteIssue = z.infer<
  typeof AgentPlanTreeBatchWriteIssueSchema
>;
export type AgentPlanTreeBatchWriteResponse = z.infer<
  typeof AgentPlanTreeBatchWriteResponseSchema
>;

export type AgentPlanTreeReferenceRow = {
  id: string;
  userId: string;
  payload: Record<string, unknown>;
  deletedAt: Date | null;
};

export type AgentPlanTreeBatchReferenceState = {
  workoutTemplates: AgentPlanTreeReferenceRow[];
  templateExercises: AgentPlanTreeReferenceRow[];
  prescriptions: AgentPlanTreeReferenceRow[];
  templateGroups: AgentPlanTreeReferenceRow[];
  templateGroupMembers: AgentPlanTreeReferenceRow[];
  routines: AgentPlanTreeReferenceRow[];
  routineEntries: AgentPlanTreeReferenceRow[];
};

export type AgentPlanTreePreparedRow = {
  entityType: AgentPlanTreeEntityType;
  itemIndex: number;
  id: string;
  updatedAt: string;
  deletedAt: string | null;
  payload: Record<string, unknown>;
  warnings: AgentSetValidationIssue[];
};

type PreparedRowsByEntity = {
  workoutTemplates: AgentPlanTreePreparedRow[];
  templateExercises: AgentPlanTreePreparedRow[];
  prescriptions: AgentPlanTreePreparedRow[];
  templateGroups: AgentPlanTreePreparedRow[];
  templateGroupMembers: AgentPlanTreePreparedRow[];
  routines: AgentPlanTreePreparedRow[];
  routineEntries: AgentPlanTreePreparedRow[];
};

export type AgentPlanTreeBatchPreparation =
  | ({
      accepted: true;
      responseItems: AgentPlanTreePreparedRow[];
    } & PreparedRowsByEntity)
  | {
      accepted: false;
      errors: AgentPlanTreeBatchWriteIssue[];
      warnings: AgentPlanTreeBatchWriteIssue[];
    };

export type AgentPlanTreeBatchWriteStore = {
  readPlanTreeBatchReceipt(input: {
    userId: string;
    batchId: string;
  }): Promise<{ serverClock: string } | null>;
  loadPlanTreeBatchReferences(input: {
    userId: string;
    request: AgentPlanTreeBatchWriteRequest;
  }): Promise<AgentPlanTreeBatchReferenceState>;
  writePlanTreeBatch(input: {
    userId: string;
    batchId: string;
    deviceId: string;
    rows: PreparedRowsByEntity;
  }): Promise<{
    duplicate: boolean;
    serverClock: string;
    appliedKeys: string[];
  }>;
};

export type AgentPlanTreeBatchWriteRunResult =
  | {
      status: "accepted";
      body: AgentPlanTreeBatchWriteResponse;
    }
  | {
      status: "validation_failed";
      body: z.infer<typeof AgentPlanTreeBatchWriteErrorResponseSchema>;
    }
  | {
      status: "catalog_unavailable";
      body: z.infer<typeof AgentCatalogUnavailableResponseSchema>;
    };

export function planTreeBatchWriteLimitsResponse() {
  return AgentPlanTreeBatchWriteLimitsSchema.parse({
    maxItems: AGENT_PLAN_TREE_BATCH_WRITE_MAX_ITEMS,
    ...PLAN_VALIDATION_LIMITS,
  });
}

export function planTreeBatchWriteResponseItems({
  duplicate,
  appliedKeys,
  rows,
}: {
  duplicate: boolean;
  appliedKeys: readonly string[];
  rows: readonly AgentPlanTreePreparedRow[];
}) {
  const applied = new Set(appliedKeys);
  return rows.map((row) =>
    AgentPlanTreeBatchWriteItemResultSchema.parse({
      entityType: row.entityType,
      itemIndex: row.itemIndex,
      id: row.id,
      outcome: duplicate
        ? "duplicate"
        : applied.has(entityKey(row.entityType, row.id))
          ? "applied"
          : "superseded",
      warnings: row.warnings,
    }),
  );
}

export function planTreeBatchWriteValidationItems(
  rows: readonly AgentPlanTreePreparedRow[],
) {
  return rows.map((row) =>
    AgentPlanTreeBatchWriteItemResultSchema.parse({
      entityType: row.entityType,
      itemIndex: row.itemIndex,
      id: row.id,
      outcome: "validated",
      warnings: row.warnings,
    }),
  );
}

export function planTreeBatchWriteDuplicateItems(
  request: AgentPlanTreeBatchWriteRequest,
) {
  const collections: {
    entityType: AgentPlanTreeEntityType;
    rows: { id: string }[];
  }[] = [
    { entityType: "workoutTemplate", rows: request.workoutTemplates },
    { entityType: "templateExercise", rows: request.templateExercises },
    { entityType: "prescription", rows: request.prescriptions },
    { entityType: "templateGroup", rows: request.templateGroups },
    { entityType: "templateGroupMember", rows: request.templateGroupMembers },
    { entityType: "routine", rows: request.routines },
    { entityType: "routineEntry", rows: request.routineEntries },
  ];
  return collections.flatMap((collection) =>
    collection.rows.map((row, itemIndex) =>
      AgentPlanTreeBatchWriteItemResultSchema.parse({
        entityType: collection.entityType,
        itemIndex,
        id: row.id,
        outcome: "duplicate",
        warnings: [],
      }),
    ),
  );
}

export async function runAgentPlanTreeBatchWrite({
  afterWrite,
  catalogStore,
  deviceId,
  request,
  store,
  userId,
}: {
  afterWrite?: (input: { applied: number }) => Promise<void>;
  catalogStore?: AgentCatalogStore;
  deviceId: string;
  request: AgentPlanTreeBatchWriteRequest;
  store: AgentPlanTreeBatchWriteStore;
  userId: string;
}): Promise<AgentPlanTreeBatchWriteRunResult> {
  const counts = planTreeBatchWriteCounts(request);
  if (!request.dryRun) {
    const receipt = await store.readPlanTreeBatchReceipt({
      userId,
      batchId: request.idempotencyKey,
    });
    if (receipt !== null) {
      return {
        status: "accepted",
        body: AgentPlanTreeBatchWriteResponseSchema.parse({
          accepted: true,
          dryRun: false,
          duplicate: true,
          idempotencyKey: request.idempotencyKey,
          batchId: request.idempotencyKey,
          serverClock: receipt.serverClock,
          expectedCounts: request.expectedCounts,
          actualCounts: counts,
          items: planTreeBatchWriteDuplicateItems(request),
        }),
      };
    }
  }
  if (catalogStore === undefined) {
    return {
      status: "catalog_unavailable",
      body: AgentCatalogUnavailableResponseSchema.parse({
        code: "agent_catalog_unavailable",
        message: "Agent Exercise catalog storage is not configured.",
      }),
    };
  }

  const prepared = await prepareAgentPlanTreeBatchWrite({
    catalogStore,
    request,
    referenceStore: store,
    userId,
  });
  if (!prepared.accepted) {
    return {
      status: "validation_failed",
      body: AgentPlanTreeBatchWriteErrorResponseSchema.parse({
        code: "agent_plan_tree_batch_write_failed",
        message:
          "Batch contains one or more hard validation or plan reference failures.",
        errors: prepared.errors,
        warnings: prepared.warnings,
        limits: planTreeBatchWriteLimitsResponse(),
      }),
    };
  }

  if (request.dryRun) {
    return {
      status: "accepted",
      body: AgentPlanTreeBatchWriteResponseSchema.parse({
        accepted: true,
        dryRun: true,
        duplicate: false,
        idempotencyKey: request.idempotencyKey,
        batchId: null,
        serverClock: new Date().toISOString(),
        expectedCounts: request.expectedCounts,
        actualCounts: counts,
        items: planTreeBatchWriteValidationItems(prepared.responseItems),
      }),
    };
  }

  const writeResult = await store.writePlanTreeBatch({
    userId,
    batchId: request.idempotencyKey,
    deviceId,
    rows: prepared,
  });
  await afterWrite?.({ applied: writeResult.appliedKeys.length });

  return {
    status: "accepted",
    body: AgentPlanTreeBatchWriteResponseSchema.parse({
      accepted: true,
      dryRun: false,
      duplicate: writeResult.duplicate,
      idempotencyKey: request.idempotencyKey,
      batchId: request.idempotencyKey,
      serverClock: writeResult.serverClock,
      expectedCounts: request.expectedCounts,
      actualCounts: counts,
      items: planTreeBatchWriteResponseItems({
        duplicate: writeResult.duplicate,
        appliedKeys: writeResult.appliedKeys,
        rows: prepared.responseItems,
      }),
    }),
  };
}

export async function prepareAgentPlanTreeBatchWrite({
  catalogStore,
  request,
  referenceStore,
  userId,
  now = new Date(),
}: {
  catalogStore: AgentCatalogStore;
  request: AgentPlanTreeBatchWriteRequest;
  referenceStore: Pick<
    AgentPlanTreeBatchWriteStore,
    "loadPlanTreeBatchReferences"
  >;
  userId: string;
  now?: Date;
}): Promise<AgentPlanTreeBatchPreparation> {
  const references = await referenceStore.loadPlanTreeBatchReferences({
    userId,
    request,
  });
  const nowIso = now.toISOString();
  const errors: AgentPlanTreeBatchWriteIssue[] = [];
  const warnings: AgentPlanTreeBatchWriteIssue[] = [];
  const rows = prepareRows(request, nowIso);
  const responseItems = flattenPreparedRows(rows);
  const preparedByKey = new Map(
    responseItems.map((row) => [entityKey(row.entityType, row.id), row]),
  );

  rejectDuplicateAndUnavailableIds({
    request,
    references,
    userId,
    errors,
  });

  const finalTemplates = overlayRows(
    references.workoutTemplates,
    rows.workoutTemplates,
    userId,
  );
  const finalTemplateExercises = overlayRows(
    references.templateExercises,
    rows.templateExercises,
    userId,
  );
  const finalPrescriptions = overlayRows(
    references.prescriptions,
    rows.prescriptions,
    userId,
  );
  const finalGroups = overlayRows(
    references.templateGroups,
    rows.templateGroups,
    userId,
  );
  const finalMembers = overlayRows(
    references.templateGroupMembers,
    rows.templateGroupMembers,
    userId,
  );
  const finalRoutines = overlayRows(references.routines, rows.routines, userId);
  const finalEntries = overlayRows(
    references.routineEntries,
    rows.routineEntries,
    userId,
  );

  validateRequiredNames(rows.workoutTemplates, rows.routines, errors);
  validateDirectPlanReferences({
    rows,
    finalTemplates,
    finalTemplateExercises,
    finalGroups,
    finalRoutines,
    errors,
  });
  validateTemplateExerciseUniqueness({
    request,
    references,
    finalTemplateExercises,
    preparedByKey,
    userId,
    errors,
  });
  validateGroupRelationships({
    request,
    references,
    rows,
    finalGroups,
    finalMembers,
    finalTemplateExercises,
    preparedByKey,
    userId,
    errors,
    warnings,
  });
  validateRoutineFinalStates({
    request,
    references,
    rows,
    finalRoutines,
    finalEntries,
    preparedByKey,
    userId,
    errors,
    warnings,
  });

  const touchedTemplateExerciseIds = touchedTemplateExerciseIdsForValidation({
    request,
    references,
    userId,
  });
  const exerciseIds = new Set<string>();
  for (const templateExerciseId of touchedTemplateExerciseIds) {
    const row = finalTemplateExercises.get(templateExerciseId);
    if (row !== undefined && row.deletedAt === null) {
      exerciseIds.add(payloadRequiredString(row.payload, "exercise_id"));
    }
  }

  const exerciseById = new Map<string, AgentExercise | null>(
    await Promise.all(
      [...exerciseIds].map(
        async (exerciseId) =>
          [
            exerciseId,
            await catalogStore.getExerciseById({ userId, exerciseId }),
          ] as const,
      ),
    ),
  );

  validateTemplateExerciseCatalogReferences({
    rows: rows.templateExercises,
    exerciseById,
    errors,
  });
  validatePrescriptions({
    finalPrescriptions,
    finalTemplateExercises,
    preparedByKey,
    touchedTemplateExerciseIds,
    exerciseById,
    errors,
    warnings,
  });

  if (errors.length > 0) {
    return { accepted: false, errors, warnings };
  }
  return {
    accepted: true,
    ...rows,
    responseItems,
  };
}

export function createDrizzleAgentPlanTreeBatchWriteStore(
  db: ServerDatabase,
): AgentPlanTreeBatchWriteStore {
  return {
    async readPlanTreeBatchReceipt({ userId, batchId }) {
      const rows = await db
        .select({ occurredAt: schema.activityLog.occurredAt })
        .from(schema.activityLog)
        .where(
          and(
            eq(schema.activityLog.userId, userId),
            eq(schema.activityLog.actor, "agent"),
            eq(schema.activityLog.batchId, batchId),
            eq(schema.activityLog.entityTable, AGENT_PLAN_TREE_BATCH_ENTITY),
          ),
        )
        .limit(1);
      return rows[0] === undefined
        ? null
        : { serverClock: rows[0].occurredAt.toISOString() };
    },

    async loadPlanTreeBatchReferences({ userId, request }) {
      return loadDrizzlePlanTreeBatchReferences(db, userId, request);
    },

    async writePlanTreeBatch({ userId, batchId, deviceId, rows }) {
      const serverClock = new Date();
      return db.transaction(async (transaction) => {
        const insertedBatchRows = await transaction
          .insert(schema.activityLog)
          .values({
            id: `agent:${userId}:${batchId}:plan-tree-batch`,
            userId,
            actor: "agent",
            batchId,
            entityTable: AGENT_PLAN_TREE_BATCH_ENTITY,
            entityId: batchId,
            beforeImage: null,
            afterImage: {
              idempotencyKey: batchId,
              kind: "agent_plan_tree_batch",
            },
            occurredAt: serverClock,
          })
          .onConflictDoNothing({ target: schema.activityLog.id })
          .returning({ occurredAt: schema.activityLog.occurredAt });
        if (insertedBatchRows.length === 0) {
          const receiptRows = await transaction
            .select({ occurredAt: schema.activityLog.occurredAt })
            .from(schema.activityLog)
            .where(
              and(
                eq(schema.activityLog.userId, userId),
                eq(schema.activityLog.actor, "agent"),
                eq(schema.activityLog.batchId, batchId),
                eq(
                  schema.activityLog.entityTable,
                  AGENT_PLAN_TREE_BATCH_ENTITY,
                ),
              ),
            )
            .limit(1);
          const receipt = receiptRows[0];
          if (receipt === undefined) {
            throw new Error(
              "Plan-tree batch marker id collided outside the caller's receipt scope.",
            );
          }
          return {
            duplicate: true,
            serverClock: receipt.occurredAt.toISOString(),
            appliedKeys: [],
          };
        }

        const groups: PlanWriteGroup[] = [
          {
            entityType: "workoutTemplate",
            keyPrefix: "workout-template",
            rows: rows.workoutTemplates,
            table: schema.workoutTemplates,
            push: pushWorkoutTemplatesInTransaction,
          },
          {
            entityType: "templateExercise",
            keyPrefix: "template-exercise",
            rows: rows.templateExercises,
            table: schema.templateExercises,
            push: pushTemplateExercisesInTransaction,
          },
          {
            entityType: "prescription",
            keyPrefix: "prescription",
            rows: rows.prescriptions,
            table: schema.prescriptions,
            push: pushPrescriptionsInTransaction,
          },
          {
            entityType: "templateGroup",
            keyPrefix: "template-group",
            rows: rows.templateGroups,
            table: schema.templateGroups,
            push: pushTemplateGroupsInTransaction,
          },
          {
            entityType: "templateGroupMember",
            keyPrefix: "template-group-member",
            rows: rows.templateGroupMembers,
            table: schema.templateGroupMembers,
            push: pushTemplateGroupMembersInTransaction,
          },
          {
            entityType: "routine",
            keyPrefix: "routine",
            rows: rows.routines,
            table: schema.routines,
            push: pushRoutinesInTransaction,
          },
          {
            entityType: "routineEntry",
            keyPrefix: "routine-entry",
            rows: rows.routineEntries,
            table: schema.routineEntries,
            push: pushRoutineEntriesInTransaction,
          },
        ];
        const appliedKeys: string[] = [];
        for (const group of groups) {
          if (group.rows.length === 0) {
            continue;
          }
          const changes: SyncPushChange[] = [];
          for (const row of group.rows) {
            const beforeImage = await readBeforeImage(
              transaction,
              group.table,
              userId,
              row.id,
            );
            const normalizedUpdatedAt = normalizeIncomingUpdatedAt(
              new Date(row.updatedAt),
              serverClock,
            );
            const normalizedAfterImage = {
              ...row.payload,
              updated_at: normalizedUpdatedAt.toISOString(),
              deleted_at:
                row.deletedAt === null
                  ? null
                  : new Date(row.deletedAt).toISOString(),
            };
            changes.push({
              id: row.id,
              payload: row.payload,
              updatedAt: row.updatedAt,
              deletedAt: row.deletedAt,
              activityLogId: `agent:${batchId}:${group.keyPrefix}:${row.id}`,
              actor: "agent",
              batchId,
              beforeImage,
              afterImage: normalizedAfterImage,
              occurredAt: normalizedUpdatedAt.toISOString(),
            });
          }
          const result = await group.push(transaction, {
            userId,
            deviceId,
            changes,
            serverClock,
          });
          appliedKeys.push(
            ...result.applied.map((row) => entityKey(group.entityType, row.id)),
          );
        }

        return {
          duplicate: false,
          serverClock: serverClock.toISOString(),
          appliedKeys,
        };
      });
    },
  };
}

function prepareRows(
  request: AgentPlanTreeBatchWriteRequest,
  nowIso: string,
): PreparedRowsByEntity {
  const workoutTemplates = request.workoutTemplates.map((item, itemIndex) =>
    preparedRow({
      entityType: "workoutTemplate",
      itemIndex,
      item,
      nowIso,
      payload: {
        id: item.id,
        name: item.name.trim(),
        notes: item.notes,
      },
    }),
  );
  const templateExercises = request.templateExercises.map((item, itemIndex) =>
    preparedRow({
      entityType: "templateExercise",
      itemIndex,
      item,
      nowIso,
      payload: {
        id: item.id,
        workout_template_id: item.workoutTemplateId,
        exercise_id: item.exerciseId,
        position: item.position,
        note: item.note,
      },
    }),
  );
  const prescriptions = request.prescriptions.map((item, itemIndex) =>
    preparedRow({
      entityType: "prescription",
      itemIndex,
      item,
      nowIso,
      payload: {
        id: item.id,
        template_exercise_id: item.templateExerciseId,
        mode: item.mode === "copyPrevious" ? "copy-previous" : item.mode,
        position: item.position,
        repeat: item.repeat,
        rest_after: item.restAfterSeconds,
        ...prescriptionDimensionPayload(
          item.mode === "fixed" ? item.values : {},
        ),
      },
    }),
  );
  const templateGroups = request.templateGroups.map((item, itemIndex) =>
    preparedRow({
      entityType: "templateGroup",
      itemIndex,
      item,
      nowIso,
      payload: {
        id: item.id,
        workout_template_id: item.workoutTemplateId,
        name: item.name.trim(),
        color_hex: item.colorHex.trim(),
        rounds: item.rounds,
        position: item.position,
      },
    }),
  );
  const templateGroupMembers = request.templateGroupMembers.map(
    (item, itemIndex) =>
      preparedRow({
        entityType: "templateGroupMember",
        itemIndex,
        item,
        nowIso,
        payload: {
          id: item.id,
          group_id: item.groupId,
          template_exercise_id: item.templateExerciseId,
          position: item.position,
        },
      }),
  );
  const routines = request.routines.map((item, itemIndex) =>
    preparedRow({
      entityType: "routine",
      itemIndex,
      item,
      nowIso,
      payload: {
        id: item.id,
        name: item.name.trim(),
        notes: item.notes,
        cadence_kind: item.cadenceKind,
        cadence_window: item.cadenceWindow,
      },
    }),
  );
  const routineEntries = request.routineEntries.map((item, itemIndex) =>
    preparedRow({
      entityType: "routineEntry",
      itemIndex,
      item,
      nowIso,
      payload: {
        id: item.id,
        routine_id: item.routineId,
        workout_template_id: item.workoutTemplateId,
        position: item.position,
        slot: item.slot,
      },
    }),
  );

  return {
    workoutTemplates,
    templateExercises,
    prescriptions,
    templateGroups,
    templateGroupMembers,
    routines,
    routineEntries,
  };
}

function preparedRow({
  entityType,
  itemIndex,
  item,
  nowIso,
  payload,
}: {
  entityType: AgentPlanTreeEntityType;
  itemIndex: number;
  item: { id: string; updatedAt?: string; deletedAt: string | null };
  nowIso: string;
  payload: Record<string, unknown>;
}): AgentPlanTreePreparedRow {
  const updatedAt = item.updatedAt ?? nowIso;
  return {
    entityType,
    itemIndex,
    id: item.id,
    updatedAt,
    deletedAt: item.deletedAt,
    payload: {
      ...payload,
      updated_at: updatedAt,
      deleted_at: item.deletedAt,
    },
    warnings: [],
  };
}

function prescriptionDimensionPayload(
  values: z.infer<typeof AgentSetValidationValuesSchema>,
) {
  const payload: Record<string, unknown> = {};
  for (const dimension of ["load", "reps", "duration", "distance"] as const) {
    const value = values[dimension];
    payload[`${dimension}_value`] =
      value === undefined ? null : Number(value.entered);
    payload[`${dimension}_unit`] = value?.unit ?? null;
    payload[`${dimension}_entered`] = value?.entered ?? null;
  }
  return payload;
}

function rejectDuplicateAndUnavailableIds({
  request,
  references,
  userId,
  errors,
}: {
  request: AgentPlanTreeBatchWriteRequest;
  references: AgentPlanTreeBatchReferenceState;
  userId: string;
  errors: AgentPlanTreeBatchWriteIssue[];
}) {
  const collections: {
    entityType: AgentPlanTreeEntityType;
    rows: { id: string }[];
    existing: AgentPlanTreeReferenceRow[];
  }[] = [
    {
      entityType: "workoutTemplate",
      rows: request.workoutTemplates,
      existing: references.workoutTemplates,
    },
    {
      entityType: "templateExercise",
      rows: request.templateExercises,
      existing: references.templateExercises,
    },
    {
      entityType: "prescription",
      rows: request.prescriptions,
      existing: references.prescriptions,
    },
    {
      entityType: "templateGroup",
      rows: request.templateGroups,
      existing: references.templateGroups,
    },
    {
      entityType: "templateGroupMember",
      rows: request.templateGroupMembers,
      existing: references.templateGroupMembers,
    },
    {
      entityType: "routine",
      rows: request.routines,
      existing: references.routines,
    },
    {
      entityType: "routineEntry",
      rows: request.routineEntries,
      existing: references.routineEntries,
    },
  ];

  for (const collection of collections) {
    const seen = new Set<string>();
    const existingById = new Map(
      collection.existing.map((row) => [row.id, row]),
    );
    for (const [itemIndex, row] of collection.rows.entries()) {
      if (seen.has(row.id)) {
        errors.push(
          structuralIssue({
            entityType: collection.entityType,
            itemIndex,
            entityId: row.id,
            field: "id",
            rule: "duplicate_plan_row_id",
            message: "A plan row id may appear only once per entity list.",
            limit: "unique",
          }),
        );
      }
      seen.add(row.id);
      const existing = existingById.get(row.id);
      if (existing !== undefined && existing.userId !== userId) {
        errors.push(
          structuralIssue({
            entityType: collection.entityType,
            itemIndex,
            entityId: row.id,
            field: "id",
            rule: "plan_row_id_unavailable",
            message:
              "This client id is unavailable. Generate a new UUIDv7 for this plan row.",
            limit: "caller-owned-or-new",
          }),
        );
      }
    }
  }
}

function validateRequiredNames(
  workoutTemplates: AgentPlanTreePreparedRow[],
  routines: AgentPlanTreePreparedRow[],
  errors: AgentPlanTreeBatchWriteIssue[],
) {
  for (const row of [...workoutTemplates, ...routines]) {
    if (
      row.deletedAt === null &&
      payloadRequiredString(row.payload, "name").length === 0
    ) {
      errors.push(
        structuralIssueForRow(row, {
          field: "name",
          rule: "plan_name_required",
          message: `${entityLabel(row.entityType)} name is required.`,
          limit: "non-empty",
        }),
      );
    }
  }
}

function validateDirectPlanReferences({
  rows,
  finalTemplates,
  finalTemplateExercises,
  finalGroups,
  finalRoutines,
  errors,
}: {
  rows: PreparedRowsByEntity;
  finalTemplates: Map<string, AgentPlanTreeReferenceRow>;
  finalTemplateExercises: Map<string, AgentPlanTreeReferenceRow>;
  finalGroups: Map<string, AgentPlanTreeReferenceRow>;
  finalRoutines: Map<string, AgentPlanTreeReferenceRow>;
  errors: AgentPlanTreeBatchWriteIssue[];
}) {
  for (const row of rows.templateExercises) {
    if (row.deletedAt !== null) {
      continue;
    }
    requireActiveReference({
      row,
      field: "workoutTemplateId",
      referenceId: payloadRequiredString(row.payload, "workout_template_id"),
      references: finalTemplates,
      label: "Workout Template",
      errors,
    });
  }
  for (const row of rows.prescriptions) {
    if (row.deletedAt !== null) {
      continue;
    }
    requireActiveReference({
      row,
      field: "templateExerciseId",
      referenceId: payloadRequiredString(row.payload, "template_exercise_id"),
      references: finalTemplateExercises,
      label: "Template Exercise",
      errors,
    });
  }
  for (const row of rows.templateGroups) {
    if (row.deletedAt !== null) {
      continue;
    }
    requireActiveReference({
      row,
      field: "workoutTemplateId",
      referenceId: payloadRequiredString(row.payload, "workout_template_id"),
      references: finalTemplates,
      label: "Workout Template",
      errors,
    });
  }
  for (const row of rows.templateGroupMembers) {
    if (row.deletedAt !== null) {
      continue;
    }
    requireActiveReference({
      row,
      field: "groupId",
      referenceId: payloadRequiredString(row.payload, "group_id"),
      references: finalGroups,
      label: "Template Group",
      errors,
    });
    requireActiveReference({
      row,
      field: "templateExerciseId",
      referenceId: payloadRequiredString(row.payload, "template_exercise_id"),
      references: finalTemplateExercises,
      label: "Template Exercise",
      errors,
    });
  }
  for (const row of rows.routineEntries) {
    if (row.deletedAt !== null) {
      continue;
    }
    requireActiveReference({
      row,
      field: "routineId",
      referenceId: payloadRequiredString(row.payload, "routine_id"),
      references: finalRoutines,
      label: "Routine",
      errors,
    });
    requireActiveReference({
      row,
      field: "workoutTemplateId",
      referenceId: payloadRequiredString(row.payload, "workout_template_id"),
      references: finalTemplates,
      label: "Workout Template",
      errors,
    });
  }
}

function validateTemplateExerciseUniqueness({
  request,
  references,
  finalTemplateExercises,
  preparedByKey,
  userId,
  errors,
}: {
  request: AgentPlanTreeBatchWriteRequest;
  references: AgentPlanTreeBatchReferenceState;
  finalTemplateExercises: Map<string, AgentPlanTreeReferenceRow>;
  preparedByKey: Map<string, AgentPlanTreePreparedRow>;
  userId: string;
  errors: AgentPlanTreeBatchWriteIssue[];
}) {
  const requestedIds = new Set(request.templateExercises.map((row) => row.id));
  const touchedTemplateIds = new Set([
    ...request.templateExercises.map((row) => row.workoutTemplateId),
    ...references.templateExercises
      .filter((row) => row.userId === userId && requestedIds.has(row.id))
      .map((row) => payloadRequiredString(row.payload, "workout_template_id")),
  ]);
  const seen = new Map<string, string>();
  for (const row of finalTemplateExercises.values()) {
    if (row.deletedAt !== null) {
      continue;
    }
    const templateId = payloadRequiredString(
      row.payload,
      "workout_template_id",
    );
    if (!touchedTemplateIds.has(templateId)) {
      continue;
    }
    const exerciseId = payloadRequiredString(row.payload, "exercise_id");
    const key = `${templateId}\u0000${exerciseId}`;
    const previousId = seen.get(key);
    if (previousId === undefined) {
      seen.set(key, row.id);
      continue;
    }
    const target = latestPreparedRowForIds(preparedByKey, "templateExercise", [
      previousId,
      row.id,
    ]);
    if (target !== undefined) {
      errors.push(
        structuralIssueForRow(target, {
          field: "exerciseId",
          rule: "template_exercise_active_unique",
          message:
            "An active Exercise may appear only once in a Workout Template.",
          limit: "unique-per-workout-template",
        }),
      );
    }
  }
}

function validateGroupRelationships({
  request,
  references,
  rows,
  finalGroups,
  finalMembers,
  finalTemplateExercises,
  preparedByKey,
  userId,
  errors,
  warnings,
}: {
  request: AgentPlanTreeBatchWriteRequest;
  references: AgentPlanTreeBatchReferenceState;
  rows: PreparedRowsByEntity;
  finalGroups: Map<string, AgentPlanTreeReferenceRow>;
  finalMembers: Map<string, AgentPlanTreeReferenceRow>;
  finalTemplateExercises: Map<string, AgentPlanTreeReferenceRow>;
  preparedByKey: Map<string, AgentPlanTreePreparedRow>;
  userId: string;
  errors: AgentPlanTreeBatchWriteIssue[];
  warnings: AgentPlanTreeBatchWriteIssue[];
}) {
  const requestedMemberIds = new Set(
    request.templateGroupMembers.map((row) => row.id),
  );
  const currentMembersById = new Map(
    references.templateGroupMembers
      .filter((row) => row.userId === userId && requestedMemberIds.has(row.id))
      .map((row) => [row.id, row]),
  );
  const touchedExerciseIds = new Set([
    ...request.templateExercises.map((row) => row.id),
    ...request.templateGroupMembers.map((row) => row.templateExerciseId),
    ...[...currentMembersById.values()].map((row) =>
      payloadRequiredString(row.payload, "template_exercise_id"),
    ),
  ]);
  const touchedGroupIds = new Set([
    ...request.templateGroups.map((row) => row.id),
    ...request.templateGroupMembers.map((row) => row.groupId),
    ...[...currentMembersById.values()].map((row) =>
      payloadRequiredString(row.payload, "group_id"),
    ),
    ...[...finalMembers.values()]
      .filter((member) =>
        touchedExerciseIds.has(
          payloadRequiredString(member.payload, "template_exercise_id"),
        ),
      )
      .map((member) => payloadRequiredString(member.payload, "group_id")),
  ]);

  for (const member of finalMembers.values()) {
    if (member.deletedAt !== null) {
      continue;
    }
    const groupId = payloadRequiredString(member.payload, "group_id");
    const templateExerciseId = payloadRequiredString(
      member.payload,
      "template_exercise_id",
    );
    if (
      !touchedGroupIds.has(groupId) &&
      !touchedExerciseIds.has(templateExerciseId)
    ) {
      continue;
    }
    const group = finalGroups.get(groupId);
    const exercise = finalTemplateExercises.get(templateExerciseId);
    if (
      group !== undefined &&
      group.deletedAt === null &&
      exercise !== undefined &&
      exercise.deletedAt === null &&
      payloadRequiredString(group.payload, "workout_template_id") !==
        payloadRequiredString(exercise.payload, "workout_template_id")
    ) {
      const target =
        preparedByKey.get(entityKey("templateGroupMember", member.id)) ??
        preparedByKey.get(entityKey("templateGroup", groupId)) ??
        preparedByKey.get(entityKey("templateExercise", templateExerciseId)) ??
        batchValidationFallback(rows);
      errors.push(
        structuralIssueForRow(target, {
          field: "templateExerciseId",
          rule: "template_group_member_template_mismatch",
          message:
            "A Template Group member must belong to the same Workout Template as its group.",
          limit: "same-workout-template",
        }),
      );
    }
  }

  const membershipChangedExerciseIds = new Set([
    ...request.templateGroupMembers.map((row) => row.templateExerciseId),
    ...[...currentMembersById.values()].map((row) =>
      payloadRequiredString(row.payload, "template_exercise_id"),
    ),
  ]);
  const membershipByExercise = new Map<string, AgentPlanTreeReferenceRow>();
  for (const member of finalMembers.values()) {
    if (member.deletedAt !== null) {
      continue;
    }
    const templateExerciseId = payloadRequiredString(
      member.payload,
      "template_exercise_id",
    );
    if (!membershipChangedExerciseIds.has(templateExerciseId)) {
      continue;
    }
    const previous = membershipByExercise.get(templateExerciseId);
    if (previous === undefined) {
      membershipByExercise.set(templateExerciseId, member);
      continue;
    }
    const target = latestPreparedRowForIds(
      preparedByKey,
      "templateGroupMember",
      [previous.id, member.id],
    );
    if (target !== undefined) {
      errors.push(
        structuralIssueForRow(target, {
          field: "templateExerciseId",
          rule: "template_group_membership_active_unique",
          message:
            "An active Template Exercise may belong to only one Template Group.",
          limit: "one-active-group",
        }),
      );
    }
  }

  for (const groupId of touchedGroupIds) {
    const group = finalGroups.get(groupId);
    if (group === undefined || group.deletedAt !== null) {
      continue;
    }
    const memberIds = [...finalMembers.values()]
      .filter(
        (member) =>
          member.deletedAt === null &&
          payloadRequiredString(member.payload, "group_id") === groupId,
      )
      .map((member) =>
        payloadRequiredString(member.payload, "template_exercise_id"),
      );
    const result = validateAgentTemplateGroup({
      name: payloadRequiredString(group.payload, "name"),
      colorHex: payloadRequiredString(group.payload, "color_hex"),
      rounds: payloadRequiredNumber(group.payload, "rounds"),
      memberIds,
    });
    const target = groupAggregateValidationTarget({
      currentMembersById,
      finalMembers,
      groupId,
      preparedByKey,
      rows,
    });
    addValidationResult(target, result, errors, warnings);
  }
}

function validateRoutineFinalStates({
  request,
  references,
  rows,
  finalRoutines,
  finalEntries,
  preparedByKey,
  userId,
  errors,
  warnings,
}: {
  request: AgentPlanTreeBatchWriteRequest;
  references: AgentPlanTreeBatchReferenceState;
  rows: PreparedRowsByEntity;
  finalRoutines: Map<string, AgentPlanTreeReferenceRow>;
  finalEntries: Map<string, AgentPlanTreeReferenceRow>;
  preparedByKey: Map<string, AgentPlanTreePreparedRow>;
  userId: string;
  errors: AgentPlanTreeBatchWriteIssue[];
  warnings: AgentPlanTreeBatchWriteIssue[];
}) {
  const requestedEntryIds = new Set(
    request.routineEntries.map((row) => row.id),
  );
  const currentEntriesById = new Map(
    references.routineEntries
      .filter((row) => row.userId === userId && requestedEntryIds.has(row.id))
      .map((row) => [row.id, row]),
  );
  const touchedRoutineIds = new Set([
    ...request.routines.map((row) => row.id),
    ...request.routineEntries.map((row) => row.routineId),
    ...[...currentEntriesById.values()].map((row) =>
      payloadRequiredString(row.payload, "routine_id"),
    ),
  ]);
  for (const routineId of touchedRoutineIds) {
    const routine = finalRoutines.get(routineId);
    if (routine === undefined || routine.deletedAt !== null) {
      continue;
    }
    const target = routineAggregateValidationTarget({
      currentEntriesById,
      preparedByKey,
      routineId,
      rows,
    });
    const slots = [...finalEntries.values()]
      .filter(
        (entry) =>
          entry.deletedAt === null &&
          payloadRequiredString(entry.payload, "routine_id") === routineId,
      )
      .map((entry) => payloadNullableNumber(entry.payload, "slot"));
    const result = validateAgentRoutineCadence({
      cadenceKind: payloadNullableString(routine.payload, "cadence_kind"),
      cadenceWindow: payloadNullableNumber(routine.payload, "cadence_window"),
      slots,
    });
    addValidationResult(target, result, errors, warnings);
  }
}

function latestPreparedRowForIds(
  preparedByKey: Map<string, AgentPlanTreePreparedRow>,
  entityType: AgentPlanTreeEntityType,
  ids: readonly string[],
) {
  return ids
    .map((id) => preparedByKey.get(entityKey(entityType, id)))
    .filter((row): row is AgentPlanTreePreparedRow => row !== undefined)
    .reduce<AgentPlanTreePreparedRow | undefined>(
      (latest, row) =>
        latest === undefined || row.itemIndex > latest.itemIndex ? row : latest,
      undefined,
    );
}

function groupAggregateValidationTarget({
  currentMembersById,
  finalMembers,
  groupId,
  preparedByKey,
  rows,
}: {
  currentMembersById: Map<string, AgentPlanTreeReferenceRow>;
  finalMembers: Map<string, AgentPlanTreeReferenceRow>;
  groupId: string;
  preparedByKey: Map<string, AgentPlanTreePreparedRow>;
  rows: PreparedRowsByEntity;
}) {
  const groupRow = preparedByKey.get(entityKey("templateGroup", groupId));
  if (groupRow !== undefined) {
    return groupRow;
  }

  const memberRow = latestAffectedRow(rows.templateGroupMembers, (row) => {
    const currentGroupId = payloadRequiredString(
      currentMembersById.get(row.id)?.payload ?? {},
      "group_id",
    );
    const nextGroupId = payloadRequiredString(row.payload, "group_id");
    return currentGroupId === groupId || nextGroupId === groupId;
  });
  if (memberRow !== undefined) {
    return memberRow;
  }

  const affectedExerciseIds = new Set(
    [...finalMembers.values()]
      .filter(
        (member) =>
          payloadRequiredString(member.payload, "group_id") === groupId,
      )
      .map((member) =>
        payloadRequiredString(member.payload, "template_exercise_id"),
      ),
  );
  return (
    latestAffectedRow(rows.templateExercises, (row) =>
      affectedExerciseIds.has(row.id),
    ) ?? batchValidationFallback(rows)
  );
}

function routineAggregateValidationTarget({
  currentEntriesById,
  preparedByKey,
  routineId,
  rows,
}: {
  currentEntriesById: Map<string, AgentPlanTreeReferenceRow>;
  preparedByKey: Map<string, AgentPlanTreePreparedRow>;
  routineId: string;
  rows: PreparedRowsByEntity;
}) {
  const routineRow = preparedByKey.get(entityKey("routine", routineId));
  if (routineRow !== undefined) {
    return routineRow;
  }

  return (
    latestAffectedRow(rows.routineEntries, (row) => {
      const currentRoutineId = payloadRequiredString(
        currentEntriesById.get(row.id)?.payload ?? {},
        "routine_id",
      );
      const nextRoutineId = payloadRequiredString(row.payload, "routine_id");
      return currentRoutineId === routineId || nextRoutineId === routineId;
    }) ?? batchValidationFallback(rows)
  );
}

function latestAffectedRow(
  rows: AgentPlanTreePreparedRow[],
  affectsAggregate: (row: AgentPlanTreePreparedRow) => boolean,
) {
  return rows.reduce<AgentPlanTreePreparedRow | undefined>(
    (latest, row) =>
      affectsAggregate(row) &&
      (latest === undefined || row.itemIndex > latest.itemIndex)
        ? row
        : latest,
    undefined,
  );
}

function batchValidationFallback(rows: PreparedRowsByEntity) {
  const fallback = flattenPreparedRows(rows)[0];
  if (fallback === undefined) {
    throw new Error(
      "A plan-tree aggregate validation result has no request item anchor.",
    );
  }
  return fallback;
}

function validateTemplateExerciseCatalogReferences({
  rows,
  exerciseById,
  errors,
}: {
  rows: AgentPlanTreePreparedRow[];
  exerciseById: Map<string, AgentExercise | null>;
  errors: AgentPlanTreeBatchWriteIssue[];
}) {
  for (const row of rows) {
    if (row.deletedAt !== null) {
      continue;
    }
    const exerciseId = payloadRequiredString(row.payload, "exercise_id");
    const exercise = exerciseById.get(exerciseId);
    if (exercise === null || exercise === undefined || !exercise.active) {
      errors.push(
        structuralIssueForRow(row, {
          field: "exerciseId",
          rule: "exercise_not_found",
          message:
            "exerciseId must reference an active caller-visible Exercise.",
          limit: "active-caller-visible",
        }),
      );
    }
  }
}

function touchedTemplateExerciseIdsForValidation({
  request,
  references,
  userId,
}: {
  request: AgentPlanTreeBatchWriteRequest;
  references: AgentPlanTreeBatchReferenceState;
  userId: string;
}) {
  const requestedPrescriptionIds = new Set(
    request.prescriptions.map((row) => row.id),
  );
  return new Set([
    ...request.templateExercises.map((row) => row.id),
    ...request.prescriptions.map((row) => row.templateExerciseId),
    ...references.prescriptions
      .filter(
        (row) => row.userId === userId && requestedPrescriptionIds.has(row.id),
      )
      .map((row) => payloadRequiredString(row.payload, "template_exercise_id")),
  ]);
}

function validatePrescriptions({
  finalPrescriptions,
  finalTemplateExercises,
  preparedByKey,
  touchedTemplateExerciseIds,
  exerciseById,
  errors,
  warnings,
}: {
  finalPrescriptions: Map<string, AgentPlanTreeReferenceRow>;
  finalTemplateExercises: Map<string, AgentPlanTreeReferenceRow>;
  preparedByKey: Map<string, AgentPlanTreePreparedRow>;
  touchedTemplateExerciseIds: Set<string>;
  exerciseById: Map<string, AgentExercise | null>;
  errors: AgentPlanTreeBatchWriteIssue[];
  warnings: AgentPlanTreeBatchWriteIssue[];
}) {
  for (const prescription of finalPrescriptions.values()) {
    if (prescription.deletedAt !== null) {
      continue;
    }
    const templateExerciseId = payloadRequiredString(
      prescription.payload,
      "template_exercise_id",
    );
    if (!touchedTemplateExerciseIds.has(templateExerciseId)) {
      continue;
    }
    const parent = finalTemplateExercises.get(templateExerciseId);
    if (parent === undefined || parent.deletedAt !== null) {
      continue;
    }
    const target =
      preparedByKey.get(entityKey("prescription", prescription.id)) ??
      preparedByKey.get(entityKey("templateExercise", templateExerciseId));
    if (target === undefined) {
      continue;
    }
    const exercise = exerciseById.get(
      payloadRequiredString(parent.payload, "exercise_id"),
    );
    if (exercise === null || exercise === undefined || !exercise.active) {
      errors.push(
        structuralIssueForRow(target, {
          field: "templateExerciseId",
          rule: "prescription_exercise_not_found",
          message:
            "The Prescription's Template Exercise must reference an active caller-visible Exercise.",
          limit: "active-caller-visible",
        }),
      );
      continue;
    }
    const storedMode = payloadRequiredString(prescription.payload, "mode");
    if (storedMode !== "fixed" && storedMode !== "copy-previous") {
      errors.push(
        structuralIssueForRow(target, {
          field: "mode",
          rule: "prescription_mode_invalid",
          message: "Mode must be fixed or copyPrevious.",
          limit: "fixed|copyPrevious",
        }),
      );
      continue;
    }
    const itemValues = dimensionValuesFromPayload(prescription.payload);
    const result = validateAgentPrescription({
      mode: storedMode === "copy-previous" ? "copyPrevious" : "fixed",
      dimensions: exercise.dimensions,
      loadMode: exercise.loadMode,
      repeat: payloadRequiredNumber(prescription.payload, "repeat"),
      restAfterSeconds: payloadNullableNumber(
        prescription.payload,
        "rest_after",
      ),
      values: itemValues,
    });
    addValidationResult(target, result, errors, warnings);
  }
}

function addValidationResult(
  row: AgentPlanTreePreparedRow,
  result: {
    errors: AgentSetValidationIssue[];
    warnings: AgentSetValidationIssue[];
  },
  errors: AgentPlanTreeBatchWriteIssue[],
  warnings: AgentPlanTreeBatchWriteIssue[],
) {
  for (const issue of result.errors) {
    errors.push(contextualIssue(row, issue));
  }
  for (const issue of result.warnings) {
    row.warnings.push(issue);
    warnings.push(contextualIssue(row, issue));
  }
}

function requireActiveReference({
  row,
  field,
  referenceId,
  references,
  label,
  errors,
}: {
  row: AgentPlanTreePreparedRow;
  field: string;
  referenceId: string;
  references: Map<string, AgentPlanTreeReferenceRow>;
  label: string;
  errors: AgentPlanTreeBatchWriteIssue[];
}) {
  const reference = references.get(referenceId);
  if (reference !== undefined && reference.deletedAt === null) {
    return;
  }
  errors.push(
    structuralIssueForRow(row, {
      field,
      rule: "plan_reference_not_found",
      message: `${field} must reference an active caller-owned ${label} created in this batch or already stored.`,
      limit: "active-caller-owned",
    }),
  );
}

function overlayRows(
  existing: AgentPlanTreeReferenceRow[],
  prepared: AgentPlanTreePreparedRow[],
  userId: string,
) {
  const rows = new Map<string, AgentPlanTreeReferenceRow>();
  for (const row of existing) {
    if (row.userId === userId) {
      rows.set(row.id, row);
    }
  }
  for (const row of prepared) {
    rows.set(row.id, {
      id: row.id,
      userId,
      payload: row.payload,
      deletedAt: row.deletedAt === null ? null : new Date(row.deletedAt),
    });
  }
  return rows;
}

function contextualIssue(
  row: AgentPlanTreePreparedRow,
  issue: AgentSetValidationIssue,
) {
  return AgentPlanTreeBatchWriteIssueSchema.parse({
    ...issue,
    entityType: row.entityType,
    itemIndex: row.itemIndex,
    entityId: row.id,
  });
}

function structuralIssueForRow(
  row: AgentPlanTreePreparedRow,
  issue: {
    field: string;
    rule: string;
    message: string;
    limit: string | number | null;
  },
) {
  return structuralIssue({
    entityType: row.entityType,
    itemIndex: row.itemIndex,
    entityId: row.id,
    ...issue,
  });
}

function structuralIssue(input: {
  entityType: AgentPlanTreeEntityType;
  itemIndex: number;
  entityId: string;
  field: string;
  rule: string;
  message: string;
  limit: string | number | null;
}) {
  return AgentPlanTreeBatchWriteIssueSchema.parse({
    ...input,
    dimension: null,
  });
}

function dimensionValuesFromPayload(payload: Record<string, unknown>) {
  const values: Record<string, { entered: string; unit: string }> = {};
  for (const dimension of ["load", "reps", "duration", "distance"] as const) {
    const entered = payload[`${dimension}_entered`];
    const unit = payload[`${dimension}_unit`];
    if (typeof entered === "string" && typeof unit === "string") {
      values[dimension] = { entered, unit };
    }
  }
  return AgentSetValidationValuesSchema.parse(values);
}

function flattenPreparedRows(rows: PreparedRowsByEntity) {
  return [
    ...rows.workoutTemplates,
    ...rows.templateExercises,
    ...rows.prescriptions,
    ...rows.templateGroups,
    ...rows.templateGroupMembers,
    ...rows.routines,
    ...rows.routineEntries,
  ];
}

const PLAN_TREE_COUNT_KEYS = [
  "workoutTemplates",
  "templateExercises",
  "prescriptions",
  "templateGroups",
  "templateGroupMembers",
  "routines",
  "routineEntries",
] as const;

function planTreeBatchWriteCounts(
  request: Pick<AgentPlanTreeBatchWriteRequest, (typeof PLAN_TREE_COUNT_KEYS)[number]>,
) {
  return AgentPlanTreeBatchWriteCountsSchema.parse(
    Object.fromEntries(
      PLAN_TREE_COUNT_KEYS.map((key) => [key, request[key].length]),
    ),
  );
}

function requestItemCount(request: AgentPlanTreeBatchWriteRequest) {
  return Object.values(planTreeBatchWriteCounts(request)).reduce(
    (total, count) => total + count,
    0,
  );
}

function entityKey(entityType: AgentPlanTreeEntityType, id: string) {
  return `${entityType}:${id}`;
}

function entityLabel(entityType: AgentPlanTreeEntityType) {
  return entityType === "workoutTemplate" ? "Workout Template" : "Routine";
}

function payloadRequiredString(payload: Record<string, unknown>, key: string) {
  const value = payload[key];
  return typeof value === "string" ? value : "";
}

function payloadNullableString(payload: Record<string, unknown>, key: string) {
  const value = payload[key];
  return typeof value === "string" ? value : null;
}

function payloadRequiredNumber(payload: Record<string, unknown>, key: string) {
  const value = payload[key];
  return typeof value === "number" ? value : Number(value);
}

function payloadNullableNumber(payload: Record<string, unknown>, key: string) {
  const value = payload[key];
  return value === null || value === undefined ? null : Number(value);
}

type OpaquePlanTable =
  | typeof schema.workoutTemplates
  | typeof schema.templateExercises
  | typeof schema.prescriptions
  | typeof schema.templateGroups
  | typeof schema.templateGroupMembers
  | typeof schema.routines
  | typeof schema.routineEntries;

type PlanPushInTransaction = (
  transaction: Parameters<typeof pushWorkoutTemplatesInTransaction>[0],
  input: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  },
) => Promise<SyncPushResult>;

type PlanWriteGroup = {
  entityType: AgentPlanTreeEntityType;
  keyPrefix: string;
  rows: AgentPlanTreePreparedRow[];
  table: OpaquePlanTable;
  push: PlanPushInTransaction;
};

async function readBeforeImage(
  transaction: Pick<ServerDatabase, "select">,
  table: OpaquePlanTable,
  userId: string,
  id: string,
) {
  const existingRows = await transaction
    .select({ userId: table.userId, payload: table.payload })
    .from(table)
    .where(eq(table.id, id))
    .limit(1);
  const existing = existingRows[0];
  if (existing === undefined || existing.userId !== userId) {
    return null;
  }
  return existing.payload;
}

async function loadDrizzlePlanTreeBatchReferences(
  db: ServerDatabase,
  userId: string,
  request: AgentPlanTreeBatchWriteRequest,
): Promise<AgentPlanTreeBatchReferenceState> {
  const directTemplateIds = unique([
    ...request.workoutTemplates.map((row) => row.id),
    ...request.templateExercises.map((row) => row.workoutTemplateId),
    ...request.templateGroups.map((row) => row.workoutTemplateId),
    ...request.routineEntries.map((row) => row.workoutTemplateId),
  ]);
  const directTemplateExerciseIds = unique([
    ...request.templateExercises.map((row) => row.id),
    ...request.prescriptions.map((row) => row.templateExerciseId),
    ...request.templateGroupMembers.map((row) => row.templateExerciseId),
  ]);
  const directGroupIds = unique([
    ...request.templateGroups.map((row) => row.id),
    ...request.templateGroupMembers.map((row) => row.groupId),
  ]);
  const directRoutineIds = unique([
    ...request.routines.map((row) => row.id),
    ...request.routineEntries.map((row) => row.routineId),
  ]);

  const matchesTemplateReference = (target: SQL<string>) =>
    or(
      valuesCondition(target, directTemplateIds),
      previousPayloadReferenceCondition({
        sourceIds: request.templateExercises.map((row) => row.id),
        sourceTable: schema.templateExercises,
        sourceUserId: userId,
        payloadKey: "workout_template_id",
        target,
      }),
      previousPayloadReferenceCondition({
        sourceIds: request.templateGroups.map((row) => row.id),
        sourceTable: schema.templateGroups,
        sourceUserId: userId,
        payloadKey: "workout_template_id",
        target,
      }),
      previousPayloadReferenceCondition({
        sourceIds: request.routineEntries.map((row) => row.id),
        sourceTable: schema.routineEntries,
        sourceUserId: userId,
        payloadKey: "workout_template_id",
        target,
      }),
    );
  const matchesTemplateExerciseReference = (target: SQL<string>) =>
    or(
      valuesCondition(target, directTemplateExerciseIds),
      previousPayloadReferenceCondition({
        sourceIds: request.prescriptions.map((row) => row.id),
        sourceTable: schema.prescriptions,
        sourceUserId: userId,
        payloadKey: "template_exercise_id",
        target,
      }),
      previousPayloadReferenceCondition({
        sourceIds: request.templateGroupMembers.map((row) => row.id),
        sourceTable: schema.templateGroupMembers,
        sourceUserId: userId,
        payloadKey: "template_exercise_id",
        target,
      }),
    );
  const matchesGroupReference = (target: SQL<string>) =>
    or(
      valuesCondition(target, directGroupIds),
      previousPayloadReferenceCondition({
        sourceIds: request.templateGroupMembers.map((row) => row.id),
        sourceTable: schema.templateGroupMembers,
        sourceUserId: userId,
        payloadKey: "group_id",
        target,
      }),
    );
  const matchesRoutineReference = (target: SQL<string>) =>
    or(
      valuesCondition(target, directRoutineIds),
      previousPayloadReferenceCondition({
        sourceIds: request.routineEntries.map((row) => row.id),
        sourceTable: schema.routineEntries,
        sourceUserId: userId,
        payloadKey: "routine_id",
        target,
      }),
    );

  const [
    workoutTemplates,
    templateExercises,
    prescriptions,
    templateGroups,
    templateGroupMembers,
    routines,
    routineEntries,
  ] = await Promise.all([
    selectRowsWhere(
      db,
      schema.workoutTemplates,
      matchesTemplateReference(sql<string>`${schema.workoutTemplates.id}`),
    ),
    selectRowsWhere(
      db,
      schema.templateExercises,
      or(
        matchesTemplateExerciseReference(
          sql<string>`${schema.templateExercises.id}`,
        ),
        and(
          eq(schema.templateExercises.userId, userId),
          matchesTemplateReference(
            sql<string>`${schema.templateExercises.payload} ->> 'workout_template_id'`,
          ),
        ),
      ),
    ),
    selectRowsWhere(
      db,
      schema.prescriptions,
      or(
        valuesCondition(
          sql<string>`${schema.prescriptions.id}`,
          request.prescriptions.map((row) => row.id),
        ),
        and(
          eq(schema.prescriptions.userId, userId),
          matchesTemplateExerciseReference(
            sql<string>`${schema.prescriptions.payload} ->> 'template_exercise_id'`,
          ),
        ),
      ),
    ),
    selectRowsWhere(
      db,
      schema.templateGroups,
      or(
        matchesGroupReference(sql<string>`${schema.templateGroups.id}`),
        and(
          eq(schema.templateGroups.userId, userId),
          matchesTemplateReference(
            sql<string>`${schema.templateGroups.payload} ->> 'workout_template_id'`,
          ),
        ),
      ),
    ),
    selectRowsWhere(
      db,
      schema.templateGroupMembers,
      or(
        valuesCondition(
          sql<string>`${schema.templateGroupMembers.id}`,
          request.templateGroupMembers.map((row) => row.id),
        ),
        and(
          eq(schema.templateGroupMembers.userId, userId),
          or(
            matchesGroupReference(
              sql<string>`${schema.templateGroupMembers.payload} ->> 'group_id'`,
            ),
            matchesTemplateExerciseReference(
              sql<string>`${schema.templateGroupMembers.payload} ->> 'template_exercise_id'`,
            ),
          ),
        ),
      ),
    ),
    selectRowsWhere(
      db,
      schema.routines,
      matchesRoutineReference(sql<string>`${schema.routines.id}`),
    ),
    selectRowsWhere(
      db,
      schema.routineEntries,
      or(
        valuesCondition(
          sql<string>`${schema.routineEntries.id}`,
          request.routineEntries.map((row) => row.id),
        ),
        and(
          eq(schema.routineEntries.userId, userId),
          matchesRoutineReference(
            sql<string>`${schema.routineEntries.payload} ->> 'routine_id'`,
          ),
        ),
      ),
    ),
  ]);

  return {
    workoutTemplates,
    templateExercises,
    prescriptions,
    templateGroups,
    templateGroupMembers,
    routines,
    routineEntries,
  };
}

function valuesCondition(target: SQL<string>, values: string[]) {
  return values.length === 0 ? undefined : inArray(target, unique(values));
}

function previousPayloadReferenceCondition({
  payloadKey,
  sourceIds,
  sourceTable,
  sourceUserId,
  target,
}: {
  payloadKey: string;
  sourceIds: string[];
  sourceTable: OpaquePlanTable;
  sourceUserId: string;
  target: SQL<string>;
}) {
  if (sourceIds.length === 0) {
    return undefined;
  }
  return sql`${target} in (
    select ${sourceTable.payload} ->> ${payloadKey}
    from ${sourceTable}
    where ${sourceTable.userId} = ${sourceUserId}
      and ${inArray(sourceTable.id, unique(sourceIds))}
  )`;
}

async function selectRowsWhere(
  db: ServerDatabase,
  table: OpaquePlanTable,
  condition: SQL | undefined,
): Promise<AgentPlanTreeReferenceRow[]> {
  if (condition === undefined) {
    return [];
  }
  return db
    .select({
      id: table.id,
      userId: table.userId,
      payload: table.payload,
      deletedAt: table.deletedAt,
    })
    .from(table)
    .where(condition);
}

function unique(values: string[]) {
  return [...new Set(values)];
}

export const AGENT_PLAN_TREE_WORKOUT_TEMPLATES_ENTITY =
  WORKOUT_TEMPLATES_SYNC_ENTITY;
export const AGENT_PLAN_TREE_TEMPLATE_EXERCISES_ENTITY =
  TEMPLATE_EXERCISES_SYNC_ENTITY;
export const AGENT_PLAN_TREE_PRESCRIPTIONS_ENTITY = PRESCRIPTIONS_SYNC_ENTITY;
export const AGENT_PLAN_TREE_TEMPLATE_GROUPS_ENTITY =
  TEMPLATE_GROUPS_SYNC_ENTITY;
export const AGENT_PLAN_TREE_TEMPLATE_GROUP_MEMBERS_ENTITY =
  TEMPLATE_GROUP_MEMBERS_SYNC_ENTITY;
export const AGENT_PLAN_TREE_ROUTINES_ENTITY = ROUTINES_SYNC_ENTITY;
export const AGENT_PLAN_TREE_ROUTINE_ENTRIES_ENTITY =
  ROUTINE_ENTRIES_SYNC_ENTITY;
