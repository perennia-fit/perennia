import { randomBytes } from "node:crypto";

import { createRoute, z } from "@hono/zod-openapi";
import { and, desc, eq, inArray, isNull, sql } from "drizzle-orm";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema,
  type AuthenticatedAgent,
} from "./agent-api-keys.js";
import {
  AgentCatalogUnavailableResponseSchema,
  type AgentCatalogStore,
  type AgentExercise,
} from "./agent-catalog.js";
import {
  AgentSetValidationIssueSchema,
  AgentSetValidationValuesSchema,
  validateAgentPrescription,
  validateAgentRoutineCadence,
  type AgentSetValidationIssue,
} from "./agent-validation.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";
import type { SyncNudgePublisher } from "./sync-nudge.js";
import {
  pushExerciseGroupMembersInTransaction,
  pushExerciseGroupsInTransaction,
  pushLoggedSetsInTransaction,
  pushTemplateLinksInTransaction,
  pushWorkoutExercisesInTransaction,
  pushWorkoutSessionsInTransaction,
  type SyncPushChange,
} from "./sync.js";

export const AGENT_PLAN_MATERIALIZE_MAX_SETS = 100;
export const AGENT_PLAN_MATERIALIZE_MAX_FUTURE_SKEW_MS = 5 * 60 * 1000;
export const AGENT_PLAN_MATERIALIZE_BATCH_ENTITY =
  "agent_plan_materializations";

const ISO8601StringSchema = z.string().min(1).openapi({
  description: "ISO-8601 timestamp.",
});

export const AgentPlanMaterializeRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200).openapi({
      description:
        "Stable materialize key. Replays converge on the same Workout and Template Link without advancing a Routine rotation twice.",
    }),
    workoutTemplateId: z.string().min(1).openapi({
      description: "Active caller-visible Workout Template to materialize.",
    }),
    routineId: z.string().min(1).nullable().default(null).openapi({
      description:
        "Optional active Routine through which the Template is being materialized.",
    }),
    slot: z.number().int().min(1).nullable().default(null).openapi({
      description:
        "Cadence slot fulfilled by this materialization. Null for a bare Template or a cadence-less Routine.",
    }),
    startedAt: ISO8601StringSchema.optional().openapi({
      description:
        "Workout start instant. Defaults to the server receive time when omitted.",
    }),
    timezone: z.string().min(1).openapi({
      description:
        "IANA timezone captured on the new Workout. Its local Training Day is frozen at materialization time.",
    }),
  })
  .superRefine((request, context) => {
    if (request.routineId === null && request.slot !== null) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["slot"],
        message: "A Cadence slot requires routineId.",
      });
    }
  })
  .openapi("AgentPlanMaterializeRequest");

export const AgentPlanMaterializeIssueSchema =
  AgentSetValidationIssueSchema.extend({
    exerciseId: z.string().min(1).nullable(),
    prescriptionId: z.string().min(1).nullable(),
  }).openapi("AgentPlanMaterializeIssue");

export const AgentPlanMaterializeLimitsSchema = z
  .object({
    maxSets: z.number().int().positive(),
  })
  .openapi("AgentPlanMaterializeLimits");

export const AgentPlanMaterializeResponseSchema = z
  .object({
    accepted: z.literal(true),
    duplicate: z.boolean().openapi({
      description:
        "True when this idempotency key had already produced the returned Workout.",
    }),
    idempotencyKey: z.string().min(1),
    batchId: z.string().min(1).openapi({
      description: "The single Activity Log batch id. Equal to idempotencyKey.",
    }),
    workoutId: z.string().min(1),
    templateLinkId: z.string().min(1),
    setIds: z.array(z.string().min(1)).max(AGENT_PLAN_MATERIALIZE_MAX_SETS),
    setCount: z.number().int().min(0).max(AGENT_PLAN_MATERIALIZE_MAX_SETS),
    startedAt: ISO8601StringSchema,
    timezone: z.string().min(1),
    localDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    workoutTemplateId: z.string().min(1),
    routineId: z.string().min(1).nullable(),
    slot: z.number().int().min(1).nullable(),
    serverClock: ISO8601StringSchema,
    warnings: z.array(AgentPlanMaterializeIssueSchema),
    limits: AgentPlanMaterializeLimitsSchema,
  })
  .openapi("AgentPlanMaterializeResponse");

export const AgentPlanMaterializeErrorResponseSchema = z
  .object({
    code: z.literal("agent_plan_materialize_failed"),
    message: z.string().min(1),
    errors: z.array(AgentPlanMaterializeIssueSchema),
    warnings: z.array(AgentPlanMaterializeIssueSchema),
    limits: AgentPlanMaterializeLimitsSchema,
  })
  .openapi("AgentPlanMaterializeErrorResponse");

export const AgentPlanMaterializeNotFoundResponseSchema = z
  .object({
    code: z.enum([
      "agent_workout_template_not_found",
      "agent_routine_not_found",
    ]),
    message: z.string().min(1),
  })
  .openapi("AgentPlanMaterializeNotFoundResponse");

export const AgentPlanMaterializeUnavailableResponseSchema = z
  .object({
    code: z.literal("agent_plan_materialize_unavailable"),
    message: z.string().min(1),
  })
  .openapi("AgentPlanMaterializeUnavailableResponse");

export const agentPlanMaterializeRoute = createRoute({
  method: "post",
  path: "/agent/workout-templates/materialize",
  operationId: "materializeAgentWorkoutTemplate",
  tags: ["Agent Writes"],
  summary: "Materialize a Workout Template into a new Workout.",
  description:
    "Creates one new Workout, unrolls its Prescriptions into capped Logged Sets, resolves copyPrevious from completed exercise history (zero-values when never performed), and records exactly one Template Link. Optional Routine/slot provenance advances a derived rotating Cadence through the Link, never through stored cursor state. The whole mutation is one atomic Activity Log batch, idempotent by key, agent-provenanced, and followed by a best-effort sync nudge.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: AgentPlanMaterializeRequestSchema,
        },
      },
    },
  },
  responses: {
    200: {
      description:
        "The Template was materialized, or the existing idempotent result was returned.",
      content: {
        "application/json": {
          schema: AgentPlanMaterializeResponseSchema,
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
    404: {
      description:
        "The caller-visible active Workout Template or requested Routine was not found.",
      content: {
        "application/json": {
          schema: AgentPlanMaterializeNotFoundResponseSchema,
        },
      },
    },
    422: {
      description:
        "The stored plan is invalid, the Routine/slot provenance does not match, the timezone is invalid, or expansion exceeds the set cap.",
      content: {
        "application/json": {
          schema: AgentPlanMaterializeErrorResponseSchema,
        },
      },
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description:
        "Agent API key, Exercise catalog, or materialize storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentCatalogUnavailableResponseSchema,
            AgentPlanMaterializeUnavailableResponseSchema,
          ]),
        },
      },
    },
  },
});

export type AgentPlanMaterializeRequest = z.infer<
  typeof AgentPlanMaterializeRequestSchema
>;
export type AgentPlanMaterializeIssue = z.infer<
  typeof AgentPlanMaterializeIssueSchema
>;
export type AgentPlanMaterializeValues = z.infer<
  typeof AgentSetValidationValuesSchema
>;

export type AgentPlanMaterializePrescriptionInput = {
  mode: "fixed" | "copyPrevious";
  fixedValues: AgentPlanMaterializeValues | null;
  lastPerformedValues: AgentPlanMaterializeValues | null;
  repeat: number;
  restAfterSeconds: number | null;
};

export type AgentPlanMaterializeExerciseInput = {
  exerciseId: string;
  dimensions: AgentExercise["dimensions"];
  defaultLoadUnit: "kilogram" | "pound";
  prescriptions: AgentPlanMaterializePrescriptionInput[];
};

export type AgentPlanMaterializeGroupInput = {
  name: string;
  colorHex: string;
  memberExerciseIndexes: number[];
};

export type AgentPlanMaterializedSet = {
  values: AgentPlanMaterializeValues;
  plannedRestAfterSeconds: number | null;
};

export type AgentPlanMaterializedContent = {
  exercises: {
    exerciseId: string;
    sets: AgentPlanMaterializedSet[];
  }[];
  groups: AgentPlanMaterializeGroupInput[];
};

/**
 * Pure TypeScript twin of the app's `materializeTemplateContent`.
 * Its input/output intentionally matches m34-plan-materialize.json.
 */
export function materializeAgentTemplateContent(input: {
  exercises: AgentPlanMaterializeExerciseInput[];
  groups: AgentPlanMaterializeGroupInput[];
}): AgentPlanMaterializedContent {
  return {
    exercises: input.exercises.map((exercise) => {
      const sets: AgentPlanMaterializedSet[] = [];
      for (const prescription of exercise.prescriptions) {
        const values =
          prescription.mode === "fixed"
            ? requireFixedValues(prescription.fixedValues)
            : (prescription.lastPerformedValues ??
              zeroValuesForExercise(exercise));
        for (
          let repeatIndex = 0;
          repeatIndex < prescription.repeat;
          repeatIndex += 1
        ) {
          sets.push({
            values,
            plannedRestAfterSeconds: prescription.restAfterSeconds,
          });
        }
      }
      return { exerciseId: exercise.exerciseId, sets };
    }),
    groups: input.groups.map((group) => ({
      name: group.name,
      colorHex: group.colorHex,
      memberExerciseIndexes: [...group.memberExerciseIndexes],
    })),
  };
}

export type AgentPlanMaterializeOpaqueRow = {
  id: string;
  userId: string;
  payload: Record<string, unknown>;
  updatedAt: Date;
  deletedAt: Date | null;
};

export type AgentPlanMaterializeSource = {
  workoutTemplate: AgentPlanMaterializeOpaqueRow | null;
  templateExercises: AgentPlanMaterializeOpaqueRow[];
  prescriptions: AgentPlanMaterializeOpaqueRow[];
  templateGroups: AgentPlanMaterializeOpaqueRow[];
  templateGroupMembers: AgentPlanMaterializeOpaqueRow[];
  routine: AgentPlanMaterializeOpaqueRow | null;
  routineEntries: AgentPlanMaterializeOpaqueRow[];
};

export type AgentPlanMaterializeHistory = {
  lastPerformedValuesByExerciseId: Record<string, AgentPlanMaterializeValues>;
  defaultLoadUnitsByExerciseId: Record<string, "kilogram" | "pound">;
};

export type AgentPlanMaterializeReceipt = {
  workoutId: string;
  templateLinkId: string;
  setIds: string[];
  startedAt: string;
  timezone: string;
  localDate: string;
  workoutTemplateId: string;
  routineId: string | null;
  slot: number | null;
  warnings: AgentPlanMaterializeIssue[];
  serverClock: string;
};

export type AgentPlanMaterializePreparedRow = {
  id: string;
  payload: Record<string, unknown>;
  updatedAt: string;
};

export type AgentPlanMaterializeStore = {
  readMaterializeReceipt(input: {
    userId: string;
    batchId: string;
  }): Promise<AgentPlanMaterializeReceipt | null>;
  loadMaterializeSource(input: {
    userId: string;
    workoutTemplateId: string;
    routineId: string | null;
  }): Promise<AgentPlanMaterializeSource>;
  loadMaterializeHistory(input: {
    userId: string;
    exerciseIds: string[];
  }): Promise<AgentPlanMaterializeHistory>;
  writeMaterialization(input: {
    userId: string;
    batchId: string;
    deviceId: string;
    receipt: Omit<AgentPlanMaterializeReceipt, "serverClock">;
    workoutSession?: AgentPlanMaterializePreparedRow;
    workoutExercises?: AgentPlanMaterializePreparedRow[];
    exerciseGroups?: AgentPlanMaterializePreparedRow[];
    exerciseGroupMembers?: AgentPlanMaterializePreparedRow[];
    sets: AgentPlanMaterializePreparedRow[];
    templateLink: AgentPlanMaterializePreparedRow;
  }): Promise<{
    duplicate: boolean;
    applied: number;
    receipt: AgentPlanMaterializeReceipt;
  }>;
};

export type AgentPlanMaterializeRunResult =
  | {
      status: "accepted";
      body: z.infer<typeof AgentPlanMaterializeResponseSchema>;
    }
  | {
      status: "not_found";
      body: z.infer<typeof AgentPlanMaterializeNotFoundResponseSchema>;
    }
  | {
      status: "validation_failed";
      body: z.infer<typeof AgentPlanMaterializeErrorResponseSchema>;
    }
  | {
      status: "catalog_unavailable";
      body: z.infer<typeof AgentCatalogUnavailableResponseSchema>;
    }
  | {
      status: "unavailable";
      body: z.infer<typeof AgentPlanMaterializeUnavailableResponseSchema>;
    };

type AgentPlanMaterializeLogger = {
  error?: (input: Record<string, unknown>, message: string) => void;
};

type AgentPlanMaterializePreparation =
  | {
      status: "accepted";
      content: AgentPlanMaterializedContent;
      warnings: AgentPlanMaterializeIssue[];
    }
  | {
      status: "not_found";
      kind: "workoutTemplate" | "routine";
    }
  | {
      status: "validation_failed";
      errors: AgentPlanMaterializeIssue[];
      warnings: AgentPlanMaterializeIssue[];
    };

export function agentPlanMaterializeLimitsResponse() {
  return AgentPlanMaterializeLimitsSchema.parse({
    maxSets: AGENT_PLAN_MATERIALIZE_MAX_SETS,
  });
}

export async function runAgentPlanMaterializeForAgent({
  agent,
  catalogStore,
  logger,
  request,
  store,
  syncNudgePublisher,
}: {
  agent: AuthenticatedAgent;
  catalogStore?: AgentCatalogStore;
  logger: AgentPlanMaterializeLogger;
  request: AgentPlanMaterializeRequest;
  store?: AgentPlanMaterializeStore;
  syncNudgePublisher?: SyncNudgePublisher;
}): Promise<AgentPlanMaterializeRunResult> {
  if (store === undefined) {
    return {
      status: "unavailable",
      body: AgentPlanMaterializeUnavailableResponseSchema.parse({
        code: "agent_plan_materialize_unavailable",
        message: "Agent plan materialize storage is not configured.",
      }),
    };
  }

  return runAgentPlanMaterialize({
    afterWrite: async ({ applied }) => {
      if (syncNudgePublisher === undefined || applied <= 0) {
        return;
      }
      try {
        await syncNudgePublisher.enqueueSyncNudge({
          userId: agent.userId,
          sourceDeviceId: `agent:${agent.keyId}`,
          reason: "agent_write",
        });
      } catch (error) {
        logger.error?.(
          {
            error,
            userId: agent.userId,
            keyId: agent.keyId,
            batchId: request.idempotencyKey,
          },
          "agent sync nudge enqueue failed",
        );
      }
    },
    catalogStore,
    deviceId: `agent:${agent.keyId}`,
    request,
    store,
    userId: agent.userId,
  });
}

export async function runAgentPlanMaterialize({
  afterWrite,
  catalogStore,
  createId = createUuidV7,
  deviceId,
  now = new Date(),
  request,
  store,
  userId,
}: {
  afterWrite?: (input: { applied: number }) => Promise<void>;
  catalogStore?: AgentCatalogStore;
  createId?: (timestamp: Date) => string;
  deviceId: string;
  now?: Date;
  request: AgentPlanMaterializeRequest;
  store: AgentPlanMaterializeStore;
  userId: string;
}): Promise<AgentPlanMaterializeRunResult> {
  const existingReceipt = await store.readMaterializeReceipt({
    userId,
    batchId: request.idempotencyKey,
  });
  if (existingReceipt !== null) {
    return acceptedMaterializeResult(
      request.idempotencyKey,
      existingReceipt,
      true,
    );
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

  const startedAt = new Date(request.startedAt ?? now);
  const localDate = localDateInTimezone(startedAt, request.timezone);
  if (Number.isNaN(startedAt.getTime()) || localDate === null) {
    return validationFailed([
      materializeIssue({
        field: Number.isNaN(startedAt.getTime()) ? "startedAt" : "timezone",
        rule: Number.isNaN(startedAt.getTime())
          ? "materialize_started_at_invalid"
          : "materialize_timezone_invalid",
        message: Number.isNaN(startedAt.getTime())
          ? "startedAt must be a valid ISO-8601 timestamp."
          : "timezone must be a valid IANA timezone.",
        limit: Number.isNaN(startedAt.getTime()) ? "ISO-8601" : "IANA",
      }),
    ]);
  }
  if (
    startedAt.getTime() >
    now.getTime() + AGENT_PLAN_MATERIALIZE_MAX_FUTURE_SKEW_MS
  ) {
    return validationFailed([
      materializeIssue({
        field: "startedAt",
        rule: "materialize_started_at_in_future",
        message:
          "startedAt cannot be more than five minutes ahead of the server clock.",
        limit: AGENT_PLAN_MATERIALIZE_MAX_FUTURE_SKEW_MS / 1000,
      }),
    ]);
  }

  const source = await store.loadMaterializeSource({
    userId,
    workoutTemplateId: request.workoutTemplateId,
    routineId: request.routineId,
  });
  const prepared = await prepareAgentPlanMaterialize({
    catalogStore,
    request,
    source,
    store,
    userId,
  });
  if (prepared.status === "not_found") {
    const template = prepared.kind === "workoutTemplate";
    return {
      status: "not_found",
      body: AgentPlanMaterializeNotFoundResponseSchema.parse({
        code: template
          ? "agent_workout_template_not_found"
          : "agent_routine_not_found",
        message: template
          ? "Workout Template was not found."
          : "Routine was not found.",
      }),
    };
  }
  if (prepared.status === "validation_failed") {
    return validationFailed(prepared.errors, prepared.warnings);
  }

  const workoutId = createId(now);
  const templateLinkId = createId(now);
  const nowIso = now.toISOString();
  const workoutExercises = prepared.content.exercises.map(
    (exercise, position): AgentPlanMaterializePreparedRow => {
      const id = createId(now);
      return {
        id,
        updatedAt: nowIso,
        payload: {
          id,
          workout_id: workoutId,
          exercise_id: exercise.exerciseId,
          position,
          updated_at: nowIso,
          deleted_at: null,
        },
      };
    },
  );
  const exerciseGroups: AgentPlanMaterializePreparedRow[] = [];
  const exerciseGroupMembers: AgentPlanMaterializePreparedRow[] = [];
  for (const [position, group] of prepared.content.groups.entries()) {
    const groupId = createId(now);
    exerciseGroups.push({
      id: groupId,
      updatedAt: nowIso,
      payload: {
        id: groupId,
        workout_id: workoutId,
        name: group.name,
        color_hex: group.colorHex,
        position,
        updated_at: nowIso,
        deleted_at: null,
      },
    });
    for (const [
      memberPosition,
      exerciseIndex,
    ] of group.memberExerciseIndexes.entries()) {
      const memberId = createId(now);
      exerciseGroupMembers.push({
        id: memberId,
        updatedAt: nowIso,
        payload: {
          id: memberId,
          group_id: groupId,
          workout_exercise_id: workoutExercises[exerciseIndex]!.id,
          position: memberPosition,
          updated_at: nowIso,
          deleted_at: null,
        },
      });
    }
  }
  const setIds: string[] = [];
  const sets: AgentPlanMaterializePreparedRow[] = [];
  for (const exercise of prepared.content.exercises) {
    for (const [setIndex, set] of exercise.sets.entries()) {
      const setId = createId(now);
      setIds.push(setId);
      sets.push({
        id: setId,
        updatedAt: nowIso,
        payload: {
          id: setId,
          workout_id: workoutId,
          workout_started_at: startedAt.toISOString(),
          workout_timezone: request.timezone,
          workout_local_date: localDate,
          workout_ended_at: null,
          workout_comment: null,
          exercise_id: exercise.exerciseId,
          position: setIndex,
          planned_rest_after: set.plannedRestAfterSeconds,
          performed_at: null,
          is_completed: false,
          ...dimensionPayload(set.values),
          comment: null,
          side: null,
          rpe: null,
          updated_at: nowIso,
          deleted_at: null,
        },
      });
    }
  }

  const templateLink: AgentPlanMaterializePreparedRow = {
    id: templateLinkId,
    updatedAt: nowIso,
    payload: {
      id: templateLinkId,
      workout_id: workoutId,
      workout_template_id: request.workoutTemplateId,
      routine_id: request.routineId,
      slot: request.slot,
      workout_started_at: startedAt.toISOString(),
      workout_timezone: request.timezone,
      workout_local_date: localDate,
      workout_ended_at: null,
      workout_comment: null,
      workout_updated_at: nowIso,
      workout_deleted_at: null,
      workout_exercises: workoutExercises.map((row) => row.payload),
      workout_exercise_groups: exerciseGroups.map((row) => row.payload),
      workout_exercise_group_members: exerciseGroupMembers.map(
        (row) => row.payload,
      ),
      updated_at: nowIso,
      deleted_at: null,
    },
  };
  const workoutSession: AgentPlanMaterializePreparedRow = {
    id: workoutId,
    updatedAt: nowIso,
    payload: {
      id: workoutId,
      started_at: startedAt.toISOString(),
      timezone: request.timezone,
      local_date: localDate,
      ended_at: null,
      comment: null,
      updated_at: nowIso,
      deleted_at: null,
    },
  };

  const writeResult = await store.writeMaterialization({
    userId,
    batchId: request.idempotencyKey,
    deviceId,
    receipt: {
      workoutId,
      templateLinkId,
      setIds,
      startedAt: startedAt.toISOString(),
      timezone: request.timezone,
      localDate,
      workoutTemplateId: request.workoutTemplateId,
      routineId: request.routineId,
      slot: request.slot,
      warnings: prepared.warnings,
    },
    workoutSession,
    workoutExercises,
    exerciseGroups,
    exerciseGroupMembers,
    sets,
    templateLink,
  });
  await afterWrite?.({ applied: writeResult.applied });
  return acceptedMaterializeResult(
    request.idempotencyKey,
    writeResult.receipt,
    writeResult.duplicate,
  );
}

export async function prepareAgentPlanMaterialize({
  catalogStore,
  request,
  source,
  store,
  userId,
}: {
  catalogStore: AgentCatalogStore;
  request: AgentPlanMaterializeRequest;
  source: AgentPlanMaterializeSource;
  store: Pick<AgentPlanMaterializeStore, "loadMaterializeHistory">;
  userId: string;
}): Promise<AgentPlanMaterializePreparation> {
  if (
    source.workoutTemplate === null ||
    source.workoutTemplate.deletedAt !== null
  ) {
    return { status: "not_found", kind: "workoutTemplate" };
  }
  if (
    request.routineId !== null &&
    (source.routine === null || source.routine.deletedAt !== null)
  ) {
    return { status: "not_found", kind: "routine" };
  }

  const errors: AgentPlanMaterializeIssue[] = [];
  const warnings: AgentPlanMaterializeIssue[] = [];
  validateRoutineProvenance(request, source, errors, warnings);

  const templateExercises = source.templateExercises
    .filter(
      (row) =>
        row.deletedAt === null &&
        payloadString(row.payload, "workout_template_id") ===
          request.workoutTemplateId,
    )
    .sort(comparePositionedRows);
  const exerciseIds = [
    ...new Set(
      templateExercises.map((row) =>
        payloadRequiredString(row.payload, "exercise_id"),
      ),
    ),
  ];
  const prescriptionsByExercise = groupByParent(
    source.prescriptions.filter((row) => row.deletedAt === null),
    "template_exercise_id",
  );
  const copyPreviousTemplateExerciseIds = new Set(
    source.prescriptions
      .filter((row) => {
        if (row.deletedAt !== null) {
          return false;
        }
        const mode = payloadString(row.payload, "mode");
        return mode === "copy-previous" || mode === "copyPrevious";
      })
      .map((row) => payloadRequiredString(row.payload, "template_exercise_id")),
  );
  const historyExerciseIds = [
    ...new Set(
      templateExercises
        .filter((row) => copyPreviousTemplateExerciseIds.has(row.id))
        .map((row) => payloadRequiredString(row.payload, "exercise_id")),
    ),
  ];
  const [exercises, history] = await Promise.all([
    catalogStore.getExercisesByIds({ userId, exerciseIds }),
    store.loadMaterializeHistory({
      userId,
      exerciseIds: historyExerciseIds,
    }),
  ]);
  const exerciseById = new Map(
    exercises.map((exercise) => [exercise.id, exercise]),
  );

  const inputs: AgentPlanMaterializeExerciseInput[] = [];
  for (const templateExercise of templateExercises) {
    const exerciseId = payloadRequiredString(
      templateExercise.payload,
      "exercise_id",
    );
    const exercise = exerciseById.get(exerciseId) ?? null;
    if (exercise === null) {
      errors.push(
        materializeIssue({
          field: "exerciseId",
          rule: "plan_reference_not_found",
          message:
            "Template Exercise must reference a caller-visible Exercise.",
          limit: "caller-visible",
          exerciseId,
        }),
      );
      continue;
    }

    const prescriptionInputs: AgentPlanMaterializePrescriptionInput[] = [];
    for (const prescription of (
      prescriptionsByExercise.get(templateExercise.id) ?? []
    ).sort(comparePositionedRows)) {
      const storedMode = payloadRequiredString(prescription.payload, "mode");
      const mode =
        storedMode === "copy-previous" || storedMode === "copyPrevious"
          ? "copyPrevious"
          : storedMode === "fixed"
            ? "fixed"
            : null;
      if (mode === null) {
        errors.push(
          materializeIssue({
            field: "mode",
            rule: "prescription_mode_invalid",
            message: "Prescription mode must be fixed or copyPrevious.",
            limit: "fixed|copyPrevious",
            exerciseId,
            prescriptionId: prescription.id,
          }),
        );
        continue;
      }

      const repeat = payloadNumber(prescription.payload, "repeat");
      const restAfterSeconds = payloadNullableNumber(
        prescription.payload,
        "rest_after",
      );
      const values = dimensionValuesFromPayload(prescription.payload);
      const validation = validateAgentPrescription({
        mode,
        dimensions: exercise.dimensions,
        loadMode: exercise.loadMode,
        repeat,
        restAfterSeconds,
        values,
      });
      errors.push(
        ...validation.errors.map((issue) =>
          contextualMaterializeIssue(issue, exerciseId, prescription.id),
        ),
      );
      warnings.push(
        ...validation.warnings.map((issue) =>
          contextualMaterializeIssue(issue, exerciseId, prescription.id),
        ),
      );
      if (validation.errors.length > 0) {
        continue;
      }
      prescriptionInputs.push({
        mode,
        fixedValues: mode === "fixed" ? values : null,
        lastPerformedValues:
          mode === "copyPrevious"
            ? (history.lastPerformedValuesByExerciseId[exerciseId] ?? null)
            : null,
        repeat,
        restAfterSeconds,
      });
    }

    inputs.push({
      exerciseId,
      dimensions: exercise.dimensions,
      defaultLoadUnit:
        history.defaultLoadUnitsByExerciseId[exerciseId] ?? "kilogram",
      prescriptions: prescriptionInputs,
    });
  }

  if (errors.length > 0) {
    return { status: "validation_failed", errors, warnings };
  }

  const exerciseIndexByTemplateExerciseId = new Map(
    templateExercises.map((row, index) => [row.id, index]),
  );
  const membersByGroup = groupByParent(
    source.templateGroupMembers.filter((row) => row.deletedAt === null),
    "group_id",
  );
  const groups = source.templateGroups
    .filter(
      (row) =>
        row.deletedAt === null &&
        payloadString(row.payload, "workout_template_id") ===
          request.workoutTemplateId,
    )
    .sort(comparePositionedRows)
    .map((group) => ({
      name: payloadRequiredString(group.payload, "name"),
      colorHex: payloadRequiredString(group.payload, "color_hex"),
      memberExerciseIndexes: (membersByGroup.get(group.id) ?? [])
        .sort(comparePositionedRows)
        .map((member) =>
          exerciseIndexByTemplateExerciseId.get(
            payloadRequiredString(member.payload, "template_exercise_id"),
          ),
        )
        .filter((index): index is number => index !== undefined),
    }));
  const content = materializeAgentTemplateContent({
    exercises: inputs,
    groups,
  });
  const setCount = content.exercises.reduce(
    (count, exercise) => count + exercise.sets.length,
    0,
  );
  if (setCount > AGENT_PLAN_MATERIALIZE_MAX_SETS) {
    return {
      status: "validation_failed",
      errors: [
        materializeIssue({
          field: "sets",
          rule: "materialize_set_cap_exceeded",
          message: `Materialize would create ${setCount} Sets, above the ${AGENT_PLAN_MATERIALIZE_MAX_SETS}-Set cap.`,
          limit: AGENT_PLAN_MATERIALIZE_MAX_SETS,
        }),
      ],
      warnings,
    };
  }
  return { status: "accepted", content, warnings };
}

export function createDrizzleAgentPlanMaterializeStore(
  db: ServerDatabase,
): AgentPlanMaterializeStore {
  return {
    async readMaterializeReceipt({ userId, batchId }) {
      return readDrizzleMaterializeReceipt(db, userId, batchId);
    },

    async loadMaterializeSource({ userId, workoutTemplateId, routineId }) {
      return loadDrizzleMaterializeSource(
        db,
        userId,
        workoutTemplateId,
        routineId,
      );
    },

    async loadMaterializeHistory({ userId, exerciseIds }) {
      return loadDrizzleMaterializeHistory(db, userId, exerciseIds);
    },

    async writeMaterialization({
      userId,
      batchId,
      deviceId,
      receipt,
      workoutSession,
      workoutExercises,
      exerciseGroups,
      exerciseGroupMembers,
      sets,
      templateLink,
    }) {
      const serverClock = new Date();
      return db.transaction(async (transaction) => {
        const storedReceipt: AgentPlanMaterializeReceipt = {
          ...receipt,
          serverClock: serverClock.toISOString(),
        };
        const inserted = await transaction
          .insert(schema.activityLog)
          .values({
            id: `agent:${userId}:${batchId}:plan-materialize`,
            userId,
            actor: "agent",
            batchId,
            entityTable: AGENT_PLAN_MATERIALIZE_BATCH_ENTITY,
            entityId: batchId,
            beforeImage: null,
            afterImage: {
              kind: "agent_plan_materialize",
              idempotencyKey: batchId,
              ...storedReceipt,
            },
            occurredAt: serverClock,
          })
          .onConflictDoNothing({ target: schema.activityLog.id })
          .returning({ id: schema.activityLog.id });
        if (inserted.length === 0) {
          const winnerReceipt = await readDrizzleMaterializeReceipt(
            transaction,
            userId,
            batchId,
          );
          if (winnerReceipt === null) {
            throw new Error(
              "Materialize batch marker collided outside the caller's receipt scope.",
            );
          }
          return {
            duplicate: true,
            applied: 0,
            receipt: winnerReceipt,
          };
        }

        const changesFor = (
          rows: AgentPlanMaterializePreparedRow[],
          kind: string,
        ): SyncPushChange[] =>
          rows.map((row) => ({
            id: row.id,
            payload: row.payload,
            updatedAt: row.updatedAt,
            deletedAt: null,
            activityLogId: `agent:${batchId}:${kind}:${row.id}`,
            actor: "agent",
            batchId,
            beforeImage: null,
            afterImage: row.payload,
            occurredAt: row.updatedAt,
          }));
        const resolvedWorkoutSession = workoutSession ?? {
          id: receipt.workoutId,
          updatedAt: receipt.startedAt,
          payload: {
            id: receipt.workoutId,
            started_at: receipt.startedAt,
            timezone: receipt.timezone,
            local_date: receipt.localDate,
            ended_at: null,
            comment: null,
            updated_at: receipt.startedAt,
            deleted_at: null,
          },
        };
        const workoutSessionResult =
          await pushWorkoutSessionsInTransaction(transaction, {
            userId,
            deviceId,
            changes: changesFor([resolvedWorkoutSession], "workout-session"),
            serverClock,
          });
        const workoutExerciseResult =
          await pushWorkoutExercisesInTransaction(transaction, {
            userId,
            deviceId,
            changes: changesFor(workoutExercises ?? [], "workout-exercise"),
            serverClock,
          });
        const exerciseGroupResult =
          await pushExerciseGroupsInTransaction(transaction, {
            userId,
            deviceId,
            changes: changesFor(exerciseGroups ?? [], "exercise-group"),
            serverClock,
          });
        const exerciseGroupMemberResult =
          await pushExerciseGroupMembersInTransaction(transaction, {
            userId,
            deviceId,
            changes: changesFor(
              exerciseGroupMembers ?? [],
              "exercise-group-member",
            ),
            serverClock,
          });
        const setChanges: SyncPushChange[] = sets.map((set) => ({
          id: set.id,
          payload: set.payload,
          updatedAt: set.updatedAt,
          deletedAt: null,
          activityLogId: `agent:${batchId}:materialized-set:${set.id}`,
          actor: "agent",
          batchId,
          beforeImage: null,
          afterImage: set.payload,
          occurredAt: set.updatedAt,
        }));
        const setResult =
          setChanges.length === 0
            ? { applied: [] }
            : await pushLoggedSetsInTransaction(transaction, {
                userId,
                deviceId,
                changes: setChanges,
                serverClock,
              });
        const linkResult = await pushTemplateLinksInTransaction(transaction, {
          userId,
          deviceId,
          changes: [
            {
              id: templateLink.id,
              payload: templateLink.payload,
              updatedAt: templateLink.updatedAt,
              deletedAt: null,
              activityLogId: `agent:${batchId}:template-link:${templateLink.id}`,
              actor: "agent",
              batchId,
              beforeImage: null,
              afterImage: templateLink.payload,
              occurredAt: templateLink.updatedAt,
            },
          ],
          serverClock,
        });

        return {
          duplicate: false,
          applied:
            workoutSessionResult.applied.length +
            workoutExerciseResult.applied.length +
            exerciseGroupResult.applied.length +
            exerciseGroupMemberResult.applied.length +
            setResult.applied.length +
            linkResult.applied.length,
          receipt: storedReceipt,
        };
      });
    },
  };
}

async function loadDrizzleMaterializeSource(
  db: ServerDatabase,
  userId: string,
  workoutTemplateId: string,
  routineId: string | null,
): Promise<AgentPlanMaterializeSource> {
  const [
    templateRows,
    templateExercises,
    templateGroups,
    routineRows,
    routineEntries,
  ] = await Promise.all([
    db
      .select()
      .from(schema.workoutTemplates)
      .where(
        and(
          eq(schema.workoutTemplates.userId, userId),
          eq(schema.workoutTemplates.id, workoutTemplateId),
        ),
      )
      .limit(1),
    db
      .select()
      .from(schema.templateExercises)
      .where(
        and(
          eq(schema.templateExercises.userId, userId),
          sql`${schema.templateExercises.payload} ->> 'workout_template_id' = ${workoutTemplateId}`,
        ),
      ),
    db
      .select()
      .from(schema.templateGroups)
      .where(
        and(
          eq(schema.templateGroups.userId, userId),
          sql`${schema.templateGroups.payload} ->> 'workout_template_id' = ${workoutTemplateId}`,
        ),
      ),
    routineId === null
      ? Promise.resolve([])
      : db
          .select()
          .from(schema.routines)
          .where(
            and(
              eq(schema.routines.userId, userId),
              eq(schema.routines.id, routineId),
            ),
          )
          .limit(1),
    routineId === null
      ? Promise.resolve([])
      : db
          .select()
          .from(schema.routineEntries)
          .where(
            and(
              eq(schema.routineEntries.userId, userId),
              sql`${schema.routineEntries.payload} ->> 'routine_id' = ${routineId}`,
            ),
          ),
  ]);
  const templateExerciseIds = templateExercises.map((row) => row.id);
  const templateGroupIds = templateGroups.map((row) => row.id);
  const [prescriptions, templateGroupMembers] = await Promise.all([
    templateExerciseIds.length === 0
      ? Promise.resolve([])
      : db
          .select()
          .from(schema.prescriptions)
          .where(
            and(
              eq(schema.prescriptions.userId, userId),
              inArray(
                sql<string>`${schema.prescriptions.payload} ->> 'template_exercise_id'`,
                templateExerciseIds,
              ),
            ),
          ),
    templateGroupIds.length === 0
      ? Promise.resolve([])
      : db
          .select()
          .from(schema.templateGroupMembers)
          .where(
            and(
              eq(schema.templateGroupMembers.userId, userId),
              inArray(
                sql<string>`${schema.templateGroupMembers.payload} ->> 'group_id'`,
                templateGroupIds,
              ),
            ),
          ),
  ]);
  return {
    workoutTemplate: templateRows[0] ?? null,
    templateExercises,
    prescriptions,
    templateGroups,
    templateGroupMembers,
    routine: routineRows[0] ?? null,
    routineEntries,
  };
}

async function loadDrizzleMaterializeHistory(
  db: ServerDatabase,
  userId: string,
  exerciseIds: string[],
): Promise<AgentPlanMaterializeHistory> {
  if (exerciseIds.length === 0) {
    return {
      lastPerformedValuesByExerciseId: {},
      defaultLoadUnitsByExerciseId: {},
    };
  }
  const loggedSetExerciseId = sql<string>`${schema.loggedSets.payload} ->> 'exercise_id'`;
  const [setRows, exerciseRows] = await Promise.all([
    db
      .selectDistinctOn([loggedSetExerciseId], {
        id: schema.loggedSets.id,
        payload: schema.loggedSets.payload,
      })
      .from(schema.loggedSets)
      .where(
        and(
          eq(schema.loggedSets.userId, userId),
          isNull(schema.loggedSets.deletedAt),
          inArray(loggedSetExerciseId, exerciseIds),
          sql`coalesce(${schema.loggedSets.payload} ->> 'is_completed', 'false') = 'true'`,
        ),
      )
      .orderBy(
        loggedSetExerciseId,
        sql`${schema.loggedSets.payload} ->> 'performed_at' desc nulls last`,
        desc(schema.loggedSets.id),
      ),
    db
      .select({
        id: schema.exercises.id,
        payload: schema.exercises.payload,
      })
      .from(schema.exercises)
      .where(
        and(
          eq(schema.exercises.userId, userId),
          inArray(schema.exercises.id, exerciseIds),
        ),
      ),
  ]);

  const lastPerformedValuesByExerciseId: Record<
    string,
    AgentPlanMaterializeValues
  > = {};
  for (const row of setRows) {
    const exerciseId = payloadRequiredString(row.payload, "exercise_id");
    lastPerformedValuesByExerciseId[exerciseId] = dimensionValuesFromPayload(
      row.payload,
    );
  }
  const defaultLoadUnitsByExerciseId: Record<string, "kilogram" | "pound"> = {};
  for (const row of exerciseRows) {
    defaultLoadUnitsByExerciseId[row.id] =
      row.payload.default_load_unit === "pound" ? "pound" : "kilogram";
  }
  return {
    lastPerformedValuesByExerciseId,
    defaultLoadUnitsByExerciseId,
  };
}

async function readDrizzleMaterializeReceipt(
  db: Pick<ServerDatabase, "select">,
  userId: string,
  batchId: string,
) {
  const rows = await db
    .select({
      afterImage: schema.activityLog.afterImage,
      occurredAt: schema.activityLog.occurredAt,
    })
    .from(schema.activityLog)
    .where(
      and(
        eq(schema.activityLog.userId, userId),
        eq(schema.activityLog.actor, "agent"),
        eq(schema.activityLog.batchId, batchId),
        eq(schema.activityLog.entityTable, AGENT_PLAN_MATERIALIZE_BATCH_ENTITY),
      ),
    )
    .limit(1);
  const row = rows[0];
  if (row === undefined || row.afterImage === null) {
    return null;
  }
  const image = row.afterImage;
  return {
    workoutId: requiredImageString(image, "workoutId"),
    templateLinkId: requiredImageString(image, "templateLinkId"),
    setIds: imageStringArray(image, "setIds"),
    startedAt: requiredImageString(image, "startedAt"),
    timezone: requiredImageString(image, "timezone"),
    localDate: requiredImageString(image, "localDate"),
    workoutTemplateId: requiredImageString(image, "workoutTemplateId"),
    routineId: nullableImageString(image, "routineId"),
    slot: nullableImageNumber(image, "slot"),
    warnings: z
      .array(AgentPlanMaterializeIssueSchema)
      .parse(image.warnings ?? []),
    serverClock: row.occurredAt.toISOString(),
  } satisfies AgentPlanMaterializeReceipt;
}

function validateRoutineProvenance(
  request: AgentPlanMaterializeRequest,
  source: AgentPlanMaterializeSource,
  errors: AgentPlanMaterializeIssue[],
  warnings: AgentPlanMaterializeIssue[],
) {
  if (request.routineId === null || source.routine === null) {
    return;
  }
  const cadenceKind = payloadNullableString(
    source.routine.payload,
    "cadence_kind",
  );
  const cadenceWindow = payloadNullableNumber(
    source.routine.payload,
    "cadence_window",
  );
  const cadenceValidation = validateAgentRoutineCadence({
    cadenceKind,
    cadenceWindow,
    slots: [request.slot],
  });
  errors.push(
    ...cadenceValidation.errors.map((issue) =>
      contextualMaterializeIssue(issue, null, null),
    ),
  );
  warnings.push(
    ...cadenceValidation.warnings.map((issue) =>
      contextualMaterializeIssue(issue, null, null),
    ),
  );

  const matchingEntry = source.routineEntries.some(
    (entry) =>
      entry.deletedAt === null &&
      payloadString(entry.payload, "routine_id") === request.routineId &&
      payloadString(entry.payload, "workout_template_id") ===
        request.workoutTemplateId &&
      payloadNullableNumber(entry.payload, "slot") === request.slot,
  );
  if (!matchingEntry) {
    errors.push(
      materializeIssue({
        field: "routineId",
        rule: "materialize_routine_entry_not_found",
        message:
          "The requested Routine/slot must contain an active reference to this Workout Template.",
        limit: "active-routine-entry",
      }),
    );
  }
}

function acceptedMaterializeResult(
  idempotencyKey: string,
  receipt: AgentPlanMaterializeReceipt,
  duplicate: boolean,
): AgentPlanMaterializeRunResult {
  return {
    status: "accepted",
    body: AgentPlanMaterializeResponseSchema.parse({
      accepted: true,
      duplicate,
      idempotencyKey,
      batchId: idempotencyKey,
      ...receipt,
      setCount: receipt.setIds.length,
      limits: agentPlanMaterializeLimitsResponse(),
    }),
  };
}

function validationFailed(
  errors: AgentPlanMaterializeIssue[],
  warnings: AgentPlanMaterializeIssue[] = [],
): AgentPlanMaterializeRunResult {
  return {
    status: "validation_failed",
    body: AgentPlanMaterializeErrorResponseSchema.parse({
      code: "agent_plan_materialize_failed",
      message: "Workout Template could not be materialized.",
      errors,
      warnings,
      limits: agentPlanMaterializeLimitsResponse(),
    }),
  };
}

function contextualMaterializeIssue(
  issue: AgentSetValidationIssue,
  exerciseId: string | null,
  prescriptionId: string | null,
) {
  return AgentPlanMaterializeIssueSchema.parse({
    ...issue,
    exerciseId,
    prescriptionId,
  });
}

function materializeIssue({
  exerciseId = null,
  prescriptionId = null,
  ...issue
}: {
  field: string;
  rule: string;
  message: string;
  limit: string | number | null;
  exerciseId?: string | null;
  prescriptionId?: string | null;
}) {
  return AgentPlanMaterializeIssueSchema.parse({
    ...issue,
    dimension: null,
    exerciseId,
    prescriptionId,
  });
}

function requireFixedValues(
  values: AgentPlanMaterializeValues | null,
): AgentPlanMaterializeValues {
  if (values === null) {
    throw new Error("A fixed Prescription requires values.");
  }
  return values;
}

function zeroValuesForExercise(
  exercise: AgentPlanMaterializeExerciseInput,
): AgentPlanMaterializeValues {
  const values: Record<string, { entered: string; unit: string }> = {};
  for (const dimension of exercise.dimensions) {
    values[dimension] = {
      entered: "0",
      unit:
        dimension === "load"
          ? exercise.defaultLoadUnit
          : dimension === "reps"
            ? "repetition"
            : dimension === "duration"
              ? "second"
              : "kilometer",
    };
  }
  return AgentSetValidationValuesSchema.parse(values);
}

function dimensionValuesFromPayload(
  payload: Record<string, unknown>,
): AgentPlanMaterializeValues {
  if (
    typeof payload.values === "object" &&
    payload.values !== null &&
    !Array.isArray(payload.values)
  ) {
    const nested = AgentSetValidationValuesSchema.safeParse(payload.values);
    if (nested.success) {
      return nested.data;
    }
  }
  const values: Record<string, { entered: string; unit: string }> = {};
  for (const dimension of ["load", "reps", "duration", "distance"] as const) {
    const rawEntered = payload[`${dimension}_entered`];
    const rawValue = payload[`${dimension}_value`];
    const unit = payload[`${dimension}_unit`];
    const entered =
      typeof rawEntered === "string"
        ? rawEntered
        : typeof rawValue === "number"
          ? String(rawValue)
          : null;
    if (entered !== null && typeof unit === "string") {
      values[dimension] = { entered, unit };
    }
  }
  return AgentSetValidationValuesSchema.parse(values);
}

function dimensionPayload(values: AgentPlanMaterializeValues) {
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

function groupByParent(rows: AgentPlanMaterializeOpaqueRow[], key: string) {
  const result = new Map<string, AgentPlanMaterializeOpaqueRow[]>();
  for (const row of rows) {
    const parentId = payloadString(row.payload, key);
    if (parentId === null) {
      continue;
    }
    const entries = result.get(parentId) ?? [];
    entries.push(row);
    result.set(parentId, entries);
  }
  return result;
}

function comparePositionedRows(
  left: AgentPlanMaterializeOpaqueRow,
  right: AgentPlanMaterializeOpaqueRow,
) {
  return (
    payloadNumber(left.payload, "position") -
      payloadNumber(right.payload, "position") ||
    left.id.localeCompare(right.id)
  );
}

function payloadString(payload: Record<string, unknown>, key: string) {
  const value = payload[key];
  return typeof value === "string" ? value : null;
}

function payloadRequiredString(payload: Record<string, unknown>, key: string) {
  return payloadString(payload, key) ?? "";
}

function payloadNullableString(payload: Record<string, unknown>, key: string) {
  return payloadString(payload, key);
}

function payloadNumber(payload: Record<string, unknown>, key: string) {
  return Number(payload[key]);
}

function payloadNullableNumber(payload: Record<string, unknown>, key: string) {
  const value = payload[key];
  return value === null || value === undefined ? null : Number(value);
}

function localDateInTimezone(date: Date, timeZone: string) {
  if (Number.isNaN(date.getTime())) {
    return null;
  }
  try {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(date);
    const part = (type: Intl.DateTimeFormatPartTypes) =>
      parts.find((candidate) => candidate.type === type)?.value;
    const year = part("year");
    const month = part("month");
    const day = part("day");
    return year === undefined || month === undefined || day === undefined
      ? null
      : `${year}-${month}-${day}`;
  } catch {
    return null;
  }
}

export function createUuidV7(timestamp = new Date()) {
  const bytes = randomBytes(16);
  let milliseconds = BigInt(timestamp.getTime());
  for (let index = 5; index >= 0; index -= 1) {
    bytes[index] = Number(milliseconds & 0xffn);
    milliseconds >>= 8n;
  }
  bytes[6] = (bytes[6]! & 0x0f) | 0x70;
  bytes[8] = (bytes[8]! & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function requiredImageString(image: Record<string, unknown>, key: string) {
  const value = image[key];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`Materialize receipt is missing ${key}.`);
  }
  return value;
}

function nullableImageString(image: Record<string, unknown>, key: string) {
  const value = image[key];
  return typeof value === "string" ? value : null;
}

function nullableImageNumber(image: Record<string, unknown>, key: string) {
  const value = image[key];
  return typeof value === "number" ? value : null;
}

function imageStringArray(image: Record<string, unknown>, key: string) {
  const value = image[key];
  if (
    !Array.isArray(value) ||
    value.some((entry) => typeof entry !== "string")
  ) {
    throw new Error(`Materialize receipt is missing ${key}.`);
  }
  return value as string[];
}
