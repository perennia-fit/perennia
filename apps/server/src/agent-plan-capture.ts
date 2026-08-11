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
import { createUuidV7 } from "./agent-plan-materialize.js";
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
import type { SyncNudgePublisher } from "./sync-nudge.js";
import {
  pushPrescriptionsInTransaction,
  pushRoutineEntriesInTransaction,
  pushTemplateExercisesInTransaction,
  pushTemplateGroupMembersInTransaction,
  pushTemplateGroupsInTransaction,
  pushWorkoutTemplatesInTransaction,
  type SyncPushChange,
  type SyncPushResult,
} from "./sync.js";

export const AGENT_PLAN_CAPTURE_MAX_ROWS = 500;
export const AGENT_PLAN_CAPTURE_BATCH_ENTITY = "agent_plan_captures";
export const AGENT_PLAN_UPDATE_BATCH_ENTITY =
  "agent_plan_updates_from_workout";

const ISO8601StringSchema = z.string().min(1).openapi({
  description: "ISO-8601 timestamp.",
});

const AgentPlanCapturePlacementSchema = z
  .object({
    routineId: z.string().min(1).nullable().default(null).openapi({
      description:
        "Optional active Routine that should reference the captured Workout Template.",
    }),
    slot: z.number().int().min(1).nullable().default(null).openapi({
      description:
        "Cadence slot for the new Routine Entry. Null appends to a cadence-less collection.",
    }),
  })
  .superRefine((placement, context) => {
    if (placement.routineId === null && placement.slot !== null) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["slot"],
        message: "A Cadence slot requires routineId.",
      });
    }
  });

export const AgentPlanCaptureRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200).openapi({
      description:
        "Stable capture key. Replays return the same Workout Template and optional Routine Entry.",
    }),
    workoutId: z.string().min(1).openapi({
      description: "Caller-visible Workout to capture as reusable plan content.",
    }),
    name: z.string().trim().min(1).optional().openapi({
      description:
        "Optional name for the new Workout Template. When omitted, the M33 capture suggestion is used.",
    }),
  })
  .merge(AgentPlanCapturePlacementSchema)
  .openapi("AgentPlanCaptureRequest");

export const AgentPlanUpdateFromWorkoutRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200).openapi({
      description:
        "Stable update key. Replays return the original capture-replace receipt without replacing content twice.",
    }),
    workoutId: z.string().min(1).openapi({
      description:
        "Workout whose active Template Link identifies the Workout Template to update.",
    }),
  })
  .openapi("AgentPlanUpdateFromWorkoutRequest");

export const AgentPlanCaptureIssueSchema = AgentSetValidationIssueSchema.extend(
  {
    sourcePath: z.string().min(1).openapi({
      description:
        "Deterministic location in captured content, placement, or linked Template state.",
    }),
  },
).openapi("AgentPlanCaptureIssue");

export const AgentPlanCaptureLimitsSchema = z
  .object({
    maxRows: z.number().int().positive(),
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
  .openapi("AgentPlanCaptureLimits");

export const AgentPlanCaptureResponseSchema = z
  .object({
    accepted: z.literal(true),
    duplicate: z.boolean(),
    idempotencyKey: z.string().min(1),
    batchId: z.string().min(1).openapi({
      description: "Single Activity Log batch id. Equal to idempotencyKey.",
    }),
    workoutId: z.string().min(1),
    workoutTemplateId: z.string().min(1),
    routineEntryId: z.string().min(1).nullable(),
    exerciseCount: z.number().int().nonnegative(),
    prescriptionCount: z.number().int().nonnegative(),
    groupCount: z.number().int().nonnegative(),
    serverClock: ISO8601StringSchema,
    warnings: z.array(AgentPlanCaptureIssueSchema),
    limits: AgentPlanCaptureLimitsSchema,
  })
  .openapi("AgentPlanCaptureResponse");

export const AgentPlanDivergenceSchema = z
  .object({
    addedExercises: z.array(
      z.object({
        exerciseId: z.string().min(1),
        exerciseName: z.string().min(1),
      }),
    ),
    removedExercises: z.array(
      z.object({
        exerciseId: z.string().min(1),
        exerciseName: z.string().min(1),
      }),
    ),
    changedExercises: z.array(
      z.object({
        exerciseId: z.string().min(1),
        exerciseName: z.string().min(1),
      }),
    ),
    groupsChanged: z.boolean(),
  })
  .openapi("AgentPlanDivergence");

export const AgentPlanUpdateFromWorkoutResponseSchema = z
  .object({
    accepted: z.literal(true),
    duplicate: z.boolean(),
    idempotencyKey: z.string().min(1),
    batchId: z.string().min(1).openapi({
      description: "Single Activity Log batch id. Equal to idempotencyKey.",
    }),
    workoutId: z.string().min(1),
    workoutTemplateId: z.string().min(1),
    exerciseCount: z.number().int().nonnegative(),
    prescriptionCount: z.number().int().nonnegative(),
    groupCount: z.number().int().nonnegative(),
    divergence: AgentPlanDivergenceSchema,
    serverClock: ISO8601StringSchema,
    warnings: z.array(AgentPlanCaptureIssueSchema),
    limits: AgentPlanCaptureLimitsSchema,
  })
  .openapi("AgentPlanUpdateFromWorkoutResponse");

export const AgentPlanCaptureErrorResponseSchema = z
  .object({
    code: z.enum([
      "agent_plan_capture_failed",
      "agent_plan_update_from_workout_failed",
    ]),
    message: z.string().min(1),
    errors: z.array(AgentPlanCaptureIssueSchema),
    warnings: z.array(AgentPlanCaptureIssueSchema),
    limits: AgentPlanCaptureLimitsSchema,
  })
  .openapi("AgentPlanCaptureErrorResponse");

export const AgentPlanCaptureConflictResponseSchema = z
  .object({
    code: z.enum([
      "agent_plan_capture_conflict",
      "agent_plan_update_from_workout_conflict",
    ]),
    message: z.string().min(1),
    retryable: z.literal(true),
    superseded: z.array(
      z.object({
        entityType: z.enum([
          "workoutTemplate",
          "templateExercise",
          "prescription",
          "templateGroup",
          "templateGroupMember",
          "routineEntry",
        ]),
        id: z.string().min(1),
      }),
    ),
  })
  .openapi("AgentPlanCaptureConflictResponse");

export const AgentPlanCaptureNotFoundResponseSchema = z
  .object({
    code: z.enum([
      "agent_workout_not_found",
      "agent_routine_not_found",
      "agent_template_link_not_found",
      "agent_workout_template_not_found",
    ]),
    message: z.string().min(1),
  })
  .openapi("AgentPlanCaptureNotFoundResponse");

export const AgentPlanCaptureUnavailableResponseSchema = z
  .object({
    code: z.literal("agent_plan_capture_unavailable"),
    message: z.string().min(1),
  })
  .openapi("AgentPlanCaptureUnavailableResponse");

export const agentPlanCaptureRoute = createRoute({
  method: "post",
  path: "/agent/workout-templates/capture",
  operationId: "captureAgentWorkoutTemplate",
  tags: ["Agent Writes"],
  summary: "Capture a Workout as a new Workout Template.",
  description:
    "Projects one authoritative Workout into fixed-only reusable plan content: fact annotations are stripped, adjacent identical Sets collapse into repeat, and copyPrevious is never emitted. Exercise order and Groups come from synchronized Workout structure, with a legacy server-materialization envelope fallback; otherwise the response warns that only Set-backed Exercises can be recovered. The server optionally appends the new Template to a cadence-less Routine or places it on a Cadence slot. The validator-checked mutation is one capped, atomic, idempotent, agent-provenanced Activity Log batch followed by a best-effort sync nudge.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: AgentPlanCaptureRequestSchema,
        },
      },
    },
  },
  responses: {
    200: {
      description:
        "The Workout was captured, or the existing idempotent receipt was returned.",
      content: {
        "application/json": {
          schema: AgentPlanCaptureResponseSchema,
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
        "The Workout or optional Routine was not found.",
      content: {
        "application/json": {
          schema: AgentPlanCaptureNotFoundResponseSchema,
        },
      },
    },
    409: {
      description:
        "A newer LWW plan row won while the atomic capture was being committed; no rows were written.",
      content: {
        "application/json": {
          schema: AgentPlanCaptureConflictResponseSchema,
        },
      },
    },
    422: {
      description:
        "Captured content or placement failed hard validation; no rows were written.",
      content: {
        "application/json": {
          schema: AgentPlanCaptureErrorResponseSchema,
        },
      },
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description:
        "Agent API key, Exercise catalog, or capture storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentCatalogUnavailableResponseSchema,
            AgentPlanCaptureUnavailableResponseSchema,
          ]),
        },
      },
    },
  },
});

export const agentPlanUpdateFromWorkoutRoute = createRoute({
  method: "post",
  path: "/agent/workout-templates/update-from-workout",
  operationId: "updateAgentWorkoutTemplateFromWorkout",
  tags: ["Agent Writes"],
  summary: "Explicitly update a linked Workout Template from its Workout.",
  description:
    "Resolves the Workout's active Template Link and capture-replaces that Template's child content while preserving Template identity (id, name, notes), Routine memberships, existing Template Links, and copyPrevious modes that still cover the same performed Set positions and rest. Exercise order and Groups come from synchronized Workout structure, with a legacy server-materialization envelope fallback; otherwise the response warns that only Set-backed Exercises can be recovered. A no-divergence comparison writes no plan rows. No implicit write-back path exists. The validator-checked replacement is one capped, atomic, idempotent, agent-provenanced Activity Log batch followed by a best-effort sync nudge.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: AgentPlanUpdateFromWorkoutRequestSchema,
        },
      },
    },
  },
  responses: {
    200: {
      description:
        "The linked Workout Template was updated, or the existing idempotent receipt was returned.",
      content: {
        "application/json": {
          schema: AgentPlanUpdateFromWorkoutResponseSchema,
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
        "The Workout, active Template Link, or linked Workout Template was not found.",
      content: {
        "application/json": {
          schema: AgentPlanCaptureNotFoundResponseSchema,
        },
      },
    },
    409: {
      description:
        "A newer LWW plan row won while the atomic replacement was being committed; no rows were written.",
      content: {
        "application/json": {
          schema: AgentPlanCaptureConflictResponseSchema,
        },
      },
    },
    422: {
      description:
        "Captured content or linked Template state failed hard validation; no rows were written.",
      content: {
        "application/json": {
          schema: AgentPlanCaptureErrorResponseSchema,
        },
      },
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description:
        "Agent API key, Exercise catalog, or update storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentCatalogUnavailableResponseSchema,
            AgentPlanCaptureUnavailableResponseSchema,
          ]),
        },
      },
    },
  },
});

export type AgentPlanCaptureRequest = z.infer<
  typeof AgentPlanCaptureRequestSchema
>;
export type AgentPlanUpdateFromWorkoutRequest = z.infer<
  typeof AgentPlanUpdateFromWorkoutRequestSchema
>;
export type AgentPlanCaptureIssue = z.infer<
  typeof AgentPlanCaptureIssueSchema
>;
export type AgentPlanDivergence = z.infer<
  typeof AgentPlanDivergenceSchema
>;
export type AgentPlanCaptureValues = z.infer<
  typeof AgentSetValidationValuesSchema
>;

export type AgentWorkoutCaptureSetSnapshot = {
  sourceSetId: string;
  position: number;
  values: AgentPlanCaptureValues;
  plannedRestAfterSeconds: number | null;
};

export type AgentWorkoutCaptureExerciseSnapshot = {
  sourceWorkoutExerciseId: string;
  exerciseId: string;
  exerciseName: string;
  position: number;
  sets: AgentWorkoutCaptureSetSnapshot[];
};

export type AgentWorkoutCaptureGroupSnapshot = {
  sourceGroupId: string;
  name: string;
  colorHex: string;
  position: number;
  memberSourceWorkoutExerciseIds: string[];
};

export type AgentWorkoutCaptureSnapshot = {
  workoutId: string;
  exercises: AgentWorkoutCaptureExerciseSnapshot[];
  groups: AgentWorkoutCaptureGroupSnapshot[];
  sourceWarnings?: AgentPlanCaptureIssue[];
};

export type AgentCapturedPrescription = {
  mode: "fixed";
  values: AgentPlanCaptureValues;
  repeat: number;
  restAfterSeconds: number | null;
};

export type AgentCapturedTemplateContent = {
  suggestedName: string;
  exercises: {
    exerciseId: string;
    prescriptions: AgentCapturedPrescription[];
  }[];
  groups: {
    name: string;
    colorHex: string;
    rounds: 1;
    memberExerciseIndexes: number[];
  }[];
};

export type AgentTemplateContentSnapshot = {
  exercises: {
    exerciseId: string;
    exerciseName: string;
    prescriptions: {
      mode: "fixed" | "copyPrevious";
      values: AgentPlanCaptureValues;
      repeat: number;
      restAfterSeconds: number | null;
    }[];
  }[];
  groups: {
    memberExerciseIds: string[];
  }[];
};

export type AgentTemplateDivergenceComparison = {
  divergence: {
    addedExercises: { exerciseId: string; exerciseName: string }[];
    removedExercises: { exerciseId: string; exerciseName: string }[];
    changedExercises: { exerciseId: string; exerciseName: string }[];
    groupsChanged: boolean;
  };
  updatedContent: {
    exercises: {
      exerciseId: string;
      prescriptions: {
        mode: "fixed" | "copyPrevious";
        values: AgentPlanCaptureValues;
        repeat: number;
        restAfterSeconds: number | null;
      }[];
    }[];
    groups: {
      name: string;
      colorHex: string;
      rounds: 1;
      memberExerciseIndexes: number[];
    }[];
  };
};

/**
 * Pure TypeScript twin of Dart's `captureWorkout`.
 *
 * Input and output intentionally match m33-workout-capture.json. Only
 * self-describing values and planned rest survive; adjacent equal projections
 * collapse losslessly into fixed Prescriptions.
 */
export function captureAgentWorkout(
  snapshot: AgentWorkoutCaptureSnapshot,
): AgentCapturedTemplateContent {
  const sourceExerciseIndexes = new Map<string, number>();
  const exerciseIds = new Set<string>();
  const exercises: AgentCapturedTemplateContent["exercises"] = [];

  for (const [index, exercise] of snapshot.exercises.entries()) {
    if (exercise.sourceWorkoutExerciseId.trim().length === 0) {
      throwWorkoutIntegrityError({
        sourcePath: `workout.exercises[${index}]`,
        field: "sourceWorkoutExerciseId",
        rule: "capture_workout_exercise_id_required",
        message: "Workout Exercise id is required.",
        limit: "non-empty-string",
      });
    }
    if (sourceExerciseIndexes.has(exercise.sourceWorkoutExerciseId)) {
      throwWorkoutIntegrityError({
        sourcePath: `workout.exercises[${index}]`,
        field: "sourceWorkoutExerciseId",
        rule: "capture_workout_exercise_id_duplicate",
        message: "Workout Exercise ids must be unique.",
        limit: "unique",
      });
    }
    if (exercise.exerciseId.trim().length === 0) {
      throwWorkoutIntegrityError({
        sourcePath: `workout.exercises[${index}]`,
        field: "exerciseId",
        rule: "capture_exercise_id_required",
        message: "Captured Exercise id is required.",
        limit: "non-empty-string",
      });
    }
    if (exerciseIds.has(exercise.exerciseId)) {
      throwWorkoutIntegrityError({
        sourcePath: `workout.exercises[${index}]`,
        field: "exerciseId",
        rule: "capture_exercise_id_duplicate",
        message: "Captured Exercise ids must be unique.",
        limit: "unique",
      });
    }
    sourceExerciseIndexes.set(exercise.sourceWorkoutExerciseId, index);
    exerciseIds.add(exercise.exerciseId);

    const prescriptions: AgentCapturedPrescription[] = [];
    for (const set of exercise.sets) {
      const previous = prescriptions.at(-1);
      if (
        previous !== undefined &&
        captureValuesEqual(previous.values, set.values) &&
        previous.restAfterSeconds === set.plannedRestAfterSeconds
      ) {
        previous.repeat += 1;
      } else {
        prescriptions.push({
          mode: "fixed",
          values: cloneCaptureValues(set.values),
          repeat: 1,
          restAfterSeconds: set.plannedRestAfterSeconds,
        });
      }
    }
    exercises.push({
      exerciseId: exercise.exerciseId,
      prescriptions,
    });
  }

  const groupedExerciseIndexes = new Set<number>();
  const groups: AgentCapturedTemplateContent["groups"] = [];
  for (const [groupIndex, group] of snapshot.groups.entries()) {
    const memberExerciseIndexes: number[] = [];
    const memberSourceIds = new Set<string>();
    for (const [
      memberIndex,
      sourceId,
    ] of group.memberSourceWorkoutExerciseIds.entries()) {
      const index = sourceExerciseIndexes.get(sourceId);
      if (index === undefined) {
        throwWorkoutIntegrityError({
          sourcePath: `workout.groups[${groupIndex}].members[${memberIndex}]`,
          field: "sourceWorkoutExerciseId",
          rule: "capture_group_member_reference_missing",
          message:
            "Captured group members must reference captured Workout Exercises.",
          limit: "captured-workout-exercise",
        });
      }
      if (memberSourceIds.has(sourceId)) {
        throwWorkoutIntegrityError({
          sourcePath: `workout.groups[${groupIndex}].members[${memberIndex}]`,
          field: "sourceWorkoutExerciseId",
          rule: "capture_group_member_duplicate",
          message: "Captured group members must be unique.",
          limit: "unique",
        });
      }
      if (groupedExerciseIndexes.has(index)) {
        throwWorkoutIntegrityError({
          sourcePath: `workout.groups[${groupIndex}].members[${memberIndex}]`,
          field: "sourceWorkoutExerciseId",
          rule: "capture_exercise_in_multiple_groups",
          message: "A captured Exercise can belong to only one group.",
          limit: "one-group",
        });
      }
      memberSourceIds.add(sourceId);
      groupedExerciseIndexes.add(index);
      memberExerciseIndexes.push(index);
    }
    groups.push({
      name: group.name,
      colorHex: group.colorHex,
      rounds: 1,
      memberExerciseIndexes,
    });
  }

  return {
    suggestedName: suggestAgentCapturedWorkoutTemplateName(snapshot),
    exercises,
    groups,
  };
}

export function suggestAgentCapturedWorkoutTemplateName(
  snapshot: AgentWorkoutCaptureSnapshot,
) {
  const ranked = [...snapshot.exercises].sort((left, right) => {
    const setCount = right.sets.length - left.sets.length;
    if (setCount !== 0) {
      return setCount;
    }
    const position = left.position - right.position;
    if (position !== 0) {
      return position;
    }
    return compareBinaryIds(
      left.sourceWorkoutExerciseId,
      right.sourceWorkoutExerciseId,
    );
  });
  const withSets = ranked.filter((exercise) => exercise.sets.length > 0);
  const dominant = withSets.length > 0 ? withSets : ranked;
  return dominant
    .slice(0, 2)
    .map((exercise) => exercise.exerciseName.trim())
    .join(" + ");
}

/**
 * Pure TypeScript twin of Dart's `compareTemplateToWorkout`.
 *
 * It drives Update-from-Workout so the same comparison that identifies
 * divergence also preserves copyPrevious modes at matching Set positions.
 */
export function compareAgentTemplateToWorkout({
  template,
  workout,
}: {
  template: AgentTemplateContentSnapshot;
  workout: AgentWorkoutCaptureSnapshot;
}): AgentTemplateDivergenceComparison {
  const captured = captureAgentWorkout(workout);
  const capturedExerciseIds = captured.exercises.map(
    (exercise) => exercise.exerciseId,
  );
  const capturedNameByExerciseId = new Map(
    workout.exercises.map((exercise) => [
      exercise.exerciseId,
      exercise.exerciseName,
    ]),
  );
  const templateByExerciseId = new Map(
    template.exercises.map((exercise) => [exercise.exerciseId, exercise]),
  );
  const addedExercises: {
    exerciseId: string;
    exerciseName: string;
  }[] = [];
  const changedExercises: {
    exerciseId: string;
    exerciseName: string;
  }[] = [];
  const updatedExercises: AgentTemplateDivergenceComparison["updatedContent"]["exercises"] =
    [];

  for (const exercise of captured.exercises) {
    const exerciseName =
      capturedNameByExerciseId.get(exercise.exerciseId) ??
      exercise.exerciseId;
    const templateExercise = templateByExerciseId.get(exercise.exerciseId);
    if (templateExercise === undefined) {
      addedExercises.push({
        exerciseId: exercise.exerciseId,
        exerciseName,
      });
      updatedExercises.push({
        exerciseId: exercise.exerciseId,
        prescriptions: exercise.prescriptions.map((prescription) => ({
          ...prescription,
          values: cloneCaptureValues(prescription.values),
        })),
      });
      continue;
    }

    const expectedSlots = expandTemplateExercise(templateExercise);
    const actualSlots = expandCapturedExercise(exercise);
    if (slotsDiverge(expectedSlots, actualSlots)) {
      changedExercises.push({
        exerciseId: exercise.exerciseId,
        exerciseName,
      });
    }
    updatedExercises.push({
      exerciseId: exercise.exerciseId,
      prescriptions: reconcileCapturedPrescriptions(
        exercise.prescriptions,
        expectedSlots,
      ),
    });
  }

  const capturedIds = new Set(capturedExerciseIds);
  const removedExercises = template.exercises
    .filter((exercise) => !capturedIds.has(exercise.exerciseId))
    .map((exercise) => ({
      exerciseId: exercise.exerciseId,
      exerciseName: exercise.exerciseName,
    }));

  return {
    divergence: {
      addedExercises,
      removedExercises,
      changedExercises,
      groupsChanged: groupsDiffer(
        template.groups,
        captured.groups,
        capturedExerciseIds,
      ),
    },
    updatedContent: {
      exercises: updatedExercises,
      groups: captured.groups.map((group) => ({
        ...group,
        memberExerciseIndexes: [...group.memberExerciseIndexes],
      })),
    },
  };
}

type ExpectedTemplateSlot = {
  mode: "fixed" | "copyPrevious";
  values: AgentPlanCaptureValues | null;
  restAfterSeconds: number | null;
};

function expandTemplateExercise(
  exercise: AgentTemplateContentSnapshot["exercises"][number],
) {
  const slots: ExpectedTemplateSlot[] = [];
  for (const prescription of exercise.prescriptions) {
    const slot: ExpectedTemplateSlot = {
      mode: prescription.mode,
      values:
        prescription.mode === "fixed"
          ? cloneCaptureValues(prescription.values)
          : null,
      restAfterSeconds: prescription.restAfterSeconds,
    };
    slots.push(
      ...Array.from({ length: prescription.repeat }, () => ({
        ...slot,
        values:
          slot.values === null
            ? null
            : cloneCaptureValues(slot.values),
      })),
    );
  }
  return slots;
}

function expandCapturedExercise(
  exercise: AgentCapturedTemplateContent["exercises"][number],
) {
  return exercise.prescriptions.flatMap((prescription) =>
    Array.from({ length: prescription.repeat }, () => ({
      values: prescription.values,
      plannedRestAfterSeconds: prescription.restAfterSeconds,
    })),
  );
}

function slotsDiverge(
  expected: ExpectedTemplateSlot[],
  actual: {
    values: AgentPlanCaptureValues;
    plannedRestAfterSeconds: number | null;
  }[],
) {
  if (expected.length !== actual.length) {
    return true;
  }
  return expected.some((expectedSlot, index) => {
    const actualSlot = actual[index]!;
    return (
      expectedSlot.restAfterSeconds !==
        actualSlot.plannedRestAfterSeconds ||
      (expectedSlot.mode === "fixed" &&
        !captureValuesEqual(expectedSlot.values ?? {}, actualSlot.values))
    );
  });
}

function reconcileCapturedPrescriptions(
  captured: AgentCapturedPrescription[],
  expectedSlots: ExpectedTemplateSlot[],
) {
  let cursor = 0;
  return captured.map((prescription) => {
    const start = cursor;
    const end = cursor + prescription.repeat;
    cursor = end;
    const allCopyPreviousMatch =
      end <= expectedSlots.length &&
      Array.from(
        { length: prescription.repeat },
        (_, offset) => expectedSlots[start + offset]!,
      ).every(
        (slot) =>
          slot.mode === "copyPrevious" &&
          slot.restAfterSeconds === prescription.restAfterSeconds,
      );
    return {
      mode: allCopyPreviousMatch
        ? ("copyPrevious" as const)
        : ("fixed" as const),
      values: allCopyPreviousMatch
        ? {}
        : cloneCaptureValues(prescription.values),
      repeat: prescription.repeat,
      restAfterSeconds: prescription.restAfterSeconds,
    };
  });
}

function groupsDiffer(
  templateGroups: AgentTemplateContentSnapshot["groups"],
  capturedGroups: AgentCapturedTemplateContent["groups"],
  capturedExerciseIds: string[],
) {
  const templateKeys = new Set(
    templateGroups.map((group) => groupKey(group.memberExerciseIds)),
  );
  const capturedKeys = new Set(
    capturedGroups.map((group) =>
      groupKey(
        group.memberExerciseIndexes.map(
          (index) => capturedExerciseIds[index]!,
        ),
      ),
    ),
  );
  return (
    templateKeys.size !== capturedKeys.size ||
    [...capturedKeys].some((key) => !templateKeys.has(key))
  );
}

function groupKey(memberIds: string[]) {
  return [...memberIds].sort(compareBinaryIds).join("\0");
}

const captureDimensions = [
  "load",
  "reps",
  "duration",
  "distance",
] as const;

function captureValuesEqual(
  left: AgentPlanCaptureValues,
  right: AgentPlanCaptureValues,
) {
  return captureDimensions.every((dimension) => {
    const leftValue = left[dimension];
    const rightValue = right[dimension];
    return (
      (leftValue === undefined && rightValue === undefined) ||
      (leftValue !== undefined &&
        rightValue !== undefined &&
        leftValue.entered === rightValue.entered &&
        leftValue.unit === rightValue.unit)
    );
  });
}

function cloneCaptureValues(values: AgentPlanCaptureValues) {
  return Object.fromEntries(
    captureDimensions.flatMap((dimension) => {
      const value = values[dimension];
      return value === undefined
        ? []
        : [[dimension, { entered: value.entered, unit: value.unit }]];
    }),
  ) as AgentPlanCaptureValues;
}

export type AgentPlanCaptureOpaqueRow = {
  id: string;
  userId: string;
  payload: Record<string, unknown>;
  updatedAt: Date;
  deletedAt: Date | null;
};

export type AgentPlanCaptureRoutineState = {
  routine: AgentPlanCaptureOpaqueRow;
  entries: AgentPlanCaptureOpaqueRow[];
};

export type AgentPlanCaptureLinkedTemplateState = {
  templateLink: AgentPlanCaptureOpaqueRow;
  workoutTemplate: AgentPlanCaptureOpaqueRow | null;
  templateExercises: AgentPlanCaptureOpaqueRow[];
  prescriptions: AgentPlanCaptureOpaqueRow[];
  templateGroups: AgentPlanCaptureOpaqueRow[];
  templateGroupMembers: AgentPlanCaptureOpaqueRow[];
};

export type AgentPlanMutationRow = {
  id: string;
  payload: Record<string, unknown>;
  updatedAt: string;
  deletedAt: string | null;
};

export type AgentPlanMutationRows = {
  workoutTemplates: AgentPlanMutationRow[];
  templateExercises: AgentPlanMutationRow[];
  prescriptions: AgentPlanMutationRow[];
  templateGroups: AgentPlanMutationRow[];
  templateGroupMembers: AgentPlanMutationRow[];
  routineEntries: AgentPlanMutationRow[];
};

type AgentPlanCaptureReceipt = {
  kind: "capture";
  workoutId: string;
  workoutTemplateId: string;
  routineEntryId: string | null;
  exerciseCount: number;
  prescriptionCount: number;
  groupCount: number;
  warnings: AgentPlanCaptureIssue[];
  serverClock: string;
};

type AgentPlanUpdateReceipt = {
  kind: "update";
  workoutId: string;
  workoutTemplateId: string;
  exerciseCount: number;
  prescriptionCount: number;
  groupCount: number;
  divergence: AgentPlanDivergence;
  warnings: AgentPlanCaptureIssue[];
  serverClock: string;
};

type AgentPlanVerbReceipt =
  | AgentPlanCaptureReceipt
  | AgentPlanUpdateReceipt;
type AgentPlanVerbReceiptInput =
  | Omit<AgentPlanCaptureReceipt, "serverClock">
  | Omit<AgentPlanUpdateReceipt, "serverClock">;

export type AgentPlanMutationEntityType =
  | "workoutTemplate"
  | "templateExercise"
  | "prescription"
  | "templateGroup"
  | "templateGroupMember"
  | "routineEntry";

export type AgentPlanSupersededRow = {
  entityType: AgentPlanMutationEntityType;
  id: string;
};

export class AgentPlanCaptureConflictError extends Error {
  constructor(readonly superseded: AgentPlanSupersededRow[]) {
    super("Atomic capture/update was superseded by newer plan rows.");
  }
}

export type AgentPlanCaptureStore = {
  readPlanVerbReceipt(input: {
    userId: string;
    batchId: string;
    kind: "capture" | "update";
  }): Promise<AgentPlanVerbReceipt | null>;
  loadWorkoutCaptureSource(input: {
    userId: string;
    workoutId: string;
  }): Promise<AgentWorkoutCaptureSnapshot | null>;
  loadCaptureRoutine(input: {
    userId: string;
    routineId: string;
  }): Promise<AgentPlanCaptureRoutineState | null>;
  loadLinkedTemplate(input: {
    userId: string;
    workoutId: string;
  }): Promise<AgentPlanCaptureLinkedTemplateState | null>;
  writePlanVerb(input: {
    userId: string;
    batchId: string;
    deviceId: string;
    kind: "capture" | "update";
    receipt: AgentPlanVerbReceiptInput;
    rows: AgentPlanMutationRows;
  }): Promise<{
    duplicate: boolean;
    applied: number;
    receipt: AgentPlanVerbReceipt;
  }>;
};

export type AgentPlanCaptureRunResult =
  | {
      status: "accepted";
      body:
        | z.infer<typeof AgentPlanCaptureResponseSchema>
        | z.infer<typeof AgentPlanUpdateFromWorkoutResponseSchema>;
    }
  | {
      status: "not_found";
      body: z.infer<typeof AgentPlanCaptureNotFoundResponseSchema>;
    }
  | {
      status: "validation_failed";
      body: z.infer<typeof AgentPlanCaptureErrorResponseSchema>;
    }
  | {
      status: "conflict";
      body: z.infer<typeof AgentPlanCaptureConflictResponseSchema>;
    }
  | {
      status: "catalog_unavailable";
      body: z.infer<typeof AgentCatalogUnavailableResponseSchema>;
    }
  | {
      status: "unavailable";
      body: z.infer<typeof AgentPlanCaptureUnavailableResponseSchema>;
    };

type AgentPlanCaptureLogger = {
  error?: (input: Record<string, unknown>, message: string) => void;
};

export function agentPlanCaptureLimitsResponse() {
  return AgentPlanCaptureLimitsSchema.parse({
    maxRows: AGENT_PLAN_CAPTURE_MAX_ROWS,
    ...PLAN_VALIDATION_LIMITS,
  });
}

export async function runAgentPlanCaptureForAgent({
  agent,
  catalogStore,
  logger,
  request,
  store,
  syncNudgePublisher,
}: {
  agent: AuthenticatedAgent;
  catalogStore?: AgentCatalogStore;
  logger: AgentPlanCaptureLogger;
  request: AgentPlanCaptureRequest;
  store?: AgentPlanCaptureStore;
  syncNudgePublisher?: SyncNudgePublisher;
}): Promise<AgentPlanCaptureRunResult> {
  return runAgentPlanVerbForAgent({
    agent,
    catalogStore,
    logger,
    store,
    syncNudgePublisher,
    batchId: request.idempotencyKey,
    run: () =>
      runAgentPlanCapture({
        catalogStore,
        deviceId: `agent:${agent.keyId}`,
        request,
        store: store!,
        userId: agent.userId,
      }),
  });
}

export async function runAgentPlanUpdateFromWorkoutForAgent({
  agent,
  catalogStore,
  logger,
  request,
  store,
  syncNudgePublisher,
}: {
  agent: AuthenticatedAgent;
  catalogStore?: AgentCatalogStore;
  logger: AgentPlanCaptureLogger;
  request: AgentPlanUpdateFromWorkoutRequest;
  store?: AgentPlanCaptureStore;
  syncNudgePublisher?: SyncNudgePublisher;
}): Promise<AgentPlanCaptureRunResult> {
  return runAgentPlanVerbForAgent({
    agent,
    catalogStore,
    logger,
    store,
    syncNudgePublisher,
    batchId: request.idempotencyKey,
    run: () =>
      runAgentPlanUpdateFromWorkout({
        catalogStore,
        deviceId: `agent:${agent.keyId}`,
        request,
        store: store!,
        userId: agent.userId,
      }),
  });
}

async function runAgentPlanVerbForAgent({
  agent,
  batchId,
  catalogStore,
  logger,
  run,
  store,
  syncNudgePublisher,
}: {
  agent: AuthenticatedAgent;
  batchId: string;
  catalogStore?: AgentCatalogStore;
  logger: AgentPlanCaptureLogger;
  run: () => Promise<AgentPlanCaptureRunResult & { applied?: number }>;
  store?: AgentPlanCaptureStore;
  syncNudgePublisher?: SyncNudgePublisher;
}) {
  if (store === undefined) {
    return {
      status: "unavailable" as const,
      body: AgentPlanCaptureUnavailableResponseSchema.parse({
        code: "agent_plan_capture_unavailable",
        message: "Agent plan capture/update storage is not configured.",
      }),
    };
  }
  if (catalogStore === undefined) {
    return {
      status: "catalog_unavailable" as const,
      body: AgentCatalogUnavailableResponseSchema.parse({
        code: "agent_catalog_unavailable",
        message: "Agent Exercise catalog storage is not configured.",
      }),
    };
  }

  const result = await run();
  if (
    result.status === "accepted" &&
    (result.applied ?? 0) > 0 &&
    syncNudgePublisher !== undefined
  ) {
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
          batchId,
        },
        "agent sync nudge enqueue failed",
      );
    }
  }
  return result;
}

export async function runAgentPlanCapture({
  catalogStore,
  createId = createUuidV7,
  deviceId,
  request,
  store,
  userId,
}: {
  catalogStore?: AgentCatalogStore;
  createId?: (timestamp?: Date) => string;
  deviceId: string;
  request: AgentPlanCaptureRequest;
  store: AgentPlanCaptureStore;
  userId: string;
}): Promise<AgentPlanCaptureRunResult & { applied?: number }> {
  const existing = await store.readPlanVerbReceipt({
    userId,
    batchId: request.idempotencyKey,
    kind: "capture",
  });
  if (existing?.kind === "capture") {
    return acceptedCaptureResult(
      request.idempotencyKey,
      existing,
      true,
      0,
    );
  }
  if (catalogStore === undefined) {
    return catalogUnavailable();
  }

  let workout: AgentWorkoutCaptureSnapshot | null;
  try {
    workout = await store.loadWorkoutCaptureSource({
      userId,
      workoutId: request.workoutId,
    });
  } catch (error) {
    return sourceValidationFailure("capture", error);
  }
  if (workout === null) {
    return notFound("agent_workout_not_found", "Workout was not found.");
  }
  const sourceWarnings = workout.sourceWarnings ?? [];

  const normalized = await normalizeWorkoutExercises({
    catalogStore,
    userId,
    workout,
  });
  if (!normalized.accepted) {
    return validationFailed("capture", normalized.errors, sourceWarnings);
  }
  let content: AgentCapturedTemplateContent;
  try {
    content = captureAgentWorkout(normalized.workout);
  } catch (error) {
    return sourceValidationFailure("capture", error, sourceWarnings);
  }
  if (content.exercises.length === 0) {
    return validationFailed(
      "capture",
      [workoutExercisesRequiredIssue()],
      sourceWarnings,
    );
  }

  let routine: AgentPlanCaptureRoutineState | null = null;
  if (request.routineId !== null) {
    routine = await store.loadCaptureRoutine({
      userId,
      routineId: request.routineId,
    });
    if (routine === null) {
      return notFound("agent_routine_not_found", "Routine was not found.");
    }
  }

  const validation = validateCapturedContent({
    content,
    exercises: normalized.exercises,
  });
  validation.warnings.unshift(...sourceWarnings);
  if (routine !== null) {
    const placementValidation = validateCapturePlacement(
      routine,
      request.slot,
    );
    validation.errors.push(...placementValidation.errors);
    validation.warnings.push(...placementValidation.warnings);
  }
  if (validation.errors.length > 0) {
    return validationFailed(
      "capture",
      validation.errors,
      validation.warnings,
    );
  }

  const now = new Date();
  const nowIso = now.toISOString();
  const workoutTemplateId = createId(now);
  const rows = emptyMutationRows();
  rows.workoutTemplates.push(
    mutationRow(
      workoutTemplateId,
      {
        id: workoutTemplateId,
        name: request.name ?? content.suggestedName,
        notes: null,
      },
      nowIso,
    ),
  );
  const ids = appendContentRows({
    content,
    createId,
    now,
    nowIso,
    rows,
    workoutTemplateId,
  });

  let routineEntryId: string | null = null;
  if (routine !== null) {
    routineEntryId = createId(now);
    rows.routineEntries.push(
      mutationRow(
        routineEntryId,
        {
          id: routineEntryId,
          routine_id: routine.routine.id,
          workout_template_id: workoutTemplateId,
          position: activePositionedRows(routine.entries).length,
          slot: request.slot,
        },
        nowIso,
      ),
    );
  }

  const rowCount = mutationRowCount(rows);
  if (rowCount > AGENT_PLAN_CAPTURE_MAX_ROWS) {
    return validationFailed(
      "capture",
      [
        captureIssue({
          sourcePath: "capture",
          field: "rows",
          rule: "capture_row_cap_exceeded",
          message: `Capture would write ${rowCount} plan rows; the maximum is ${AGENT_PLAN_CAPTURE_MAX_ROWS}.`,
          limit: AGENT_PLAN_CAPTURE_MAX_ROWS,
        }),
      ],
      validation.warnings,
    );
  }

  let writeResult: Awaited<
    ReturnType<AgentPlanCaptureStore["writePlanVerb"]>
  >;
  try {
    writeResult = await store.writePlanVerb({
      userId,
      batchId: request.idempotencyKey,
      deviceId,
      kind: "capture",
      receipt: {
        kind: "capture",
        workoutId: request.workoutId,
        workoutTemplateId,
        routineEntryId,
        exerciseCount: content.exercises.length,
        prescriptionCount: ids.prescriptionCount,
        groupCount: content.groups.length,
        warnings: validation.warnings,
      },
      rows,
    });
  } catch (error) {
    return planVerbConflict("capture", error);
  }
  if (writeResult.receipt.kind !== "capture") {
    throw new Error("Capture receipt kind mismatch.");
  }
  return acceptedCaptureResult(
    request.idempotencyKey,
    writeResult.receipt,
    writeResult.duplicate,
    writeResult.applied,
  );
}

export async function runAgentPlanUpdateFromWorkout({
  catalogStore,
  createId = createUuidV7,
  deviceId,
  request,
  store,
  userId,
}: {
  catalogStore?: AgentCatalogStore;
  createId?: (timestamp?: Date) => string;
  deviceId: string;
  request: AgentPlanUpdateFromWorkoutRequest;
  store: AgentPlanCaptureStore;
  userId: string;
}): Promise<AgentPlanCaptureRunResult & { applied?: number }> {
  const existing = await store.readPlanVerbReceipt({
    userId,
    batchId: request.idempotencyKey,
    kind: "update",
  });
  if (existing?.kind === "update") {
    return acceptedUpdateResult(
      request.idempotencyKey,
      existing,
      true,
      0,
    );
  }
  if (catalogStore === undefined) {
    return catalogUnavailable();
  }

  let workout: AgentWorkoutCaptureSnapshot | null;
  try {
    workout = await store.loadWorkoutCaptureSource({
      userId,
      workoutId: request.workoutId,
    });
  } catch (error) {
    return sourceValidationFailure("update", error);
  }
  if (workout === null) {
    return notFound("agent_workout_not_found", "Workout was not found.");
  }
  const sourceWarnings = workout.sourceWarnings ?? [];
  const linked = await store.loadLinkedTemplate({
    userId,
    workoutId: request.workoutId,
  });
  if (linked === null) {
    return notFound(
      "agent_template_link_not_found",
      "Workout has no active Template Link.",
    );
  }
  if (linked.workoutTemplate === null) {
    return notFound(
      "agent_workout_template_not_found",
      "Linked Workout Template was not found.",
    );
  }

  const normalized = await normalizeWorkoutExercises({
    catalogStore,
    userId,
    workout,
  });
  if (!normalized.accepted) {
    return validationFailed("update", normalized.errors, sourceWarnings);
  }
  if (normalized.workout.exercises.length === 0) {
    return validationFailed(
      "update",
      [workoutExercisesRequiredIssue()],
      sourceWarnings,
    );
  }
  let comparison: AgentTemplateDivergenceComparison;
  try {
    const template = templateSnapshotFromState(
      linked,
      normalized.exercises,
    );
    comparison = compareAgentTemplateToWorkout({
      template,
      workout: normalized.workout,
    });
  } catch (error) {
    return sourceValidationFailure("update", error, sourceWarnings);
  }
  const validation = validateUpdatedContent({
    content: comparison.updatedContent,
    exercises: normalized.exercises,
  });
  validation.warnings.unshift(...sourceWarnings);
  if (validation.errors.length > 0) {
    return validationFailed(
      "update",
      validation.errors,
      validation.warnings,
    );
  }

  const now = new Date();
  const nowIso = now.toISOString();
  const rows = emptyMutationRows();
  const hasDivergence = agentPlanDivergenceExists(
    comparison.divergence,
  );
  const prescriptionCount = comparison.updatedContent.exercises.reduce(
    (count, exercise) => count + exercise.prescriptions.length,
    0,
  );
  if (hasDivergence) {
    appendContentTombstones(rows, linked, nowIso);
    appendContentRows({
      content: comparison.updatedContent,
      createId,
      now,
      nowIso,
      rows,
      workoutTemplateId: linked.workoutTemplate.id,
    });
  }
  const rowCount = mutationRowCount(rows);
  if (rowCount > AGENT_PLAN_CAPTURE_MAX_ROWS) {
    return validationFailed(
      "update",
      [
        captureIssue({
          sourcePath: "update",
          field: "rows",
          rule: "update_row_cap_exceeded",
          message: `Update would write ${rowCount} plan rows; the maximum is ${AGENT_PLAN_CAPTURE_MAX_ROWS}.`,
          limit: AGENT_PLAN_CAPTURE_MAX_ROWS,
        }),
      ],
      validation.warnings,
    );
  }

  let writeResult: Awaited<
    ReturnType<AgentPlanCaptureStore["writePlanVerb"]>
  >;
  try {
    writeResult = await store.writePlanVerb({
      userId,
      batchId: request.idempotencyKey,
      deviceId,
      kind: "update",
      receipt: {
        kind: "update",
        workoutId: request.workoutId,
        workoutTemplateId: linked.workoutTemplate.id,
        exerciseCount: comparison.updatedContent.exercises.length,
        prescriptionCount,
        groupCount: comparison.updatedContent.groups.length,
        divergence: comparison.divergence,
        warnings: validation.warnings,
      },
      rows,
    });
  } catch (error) {
    return planVerbConflict("update", error);
  }
  if (writeResult.receipt.kind !== "update") {
    throw new Error("Update receipt kind mismatch.");
  }
  return acceptedUpdateResult(
    request.idempotencyKey,
    writeResult.receipt,
    writeResult.duplicate,
    writeResult.applied,
  );
}

async function normalizeWorkoutExercises({
  catalogStore,
  userId,
  workout,
}: {
  catalogStore: AgentCatalogStore;
  userId: string;
  workout: AgentWorkoutCaptureSnapshot;
}): Promise<
  | {
      accepted: true;
      workout: AgentWorkoutCaptureSnapshot;
      exercises: Map<string, AgentExercise>;
    }
  | { accepted: false; errors: AgentPlanCaptureIssue[] }
> {
  const exerciseIds = unique(
    workout.exercises.map((exercise) => exercise.exerciseId),
  );
  const catalogExercises = await catalogStore.getExercisesByIds({
    userId,
    exerciseIds,
  });
  const exercises = new Map(
    catalogExercises.map((exercise) => [exercise.id, exercise]),
  );
  const missing = exerciseIds.filter((exerciseId) => !exercises.has(exerciseId));
  if (missing.length > 0) {
    return {
      accepted: false,
      errors: missing.map((exerciseId) =>
        captureIssue({
          sourcePath: "workout.exercises",
          field: "exerciseId",
          rule: "capture_exercise_not_found",
          message: `Exercise is not caller-visible: ${exerciseId}.`,
          limit: "caller-visible",
        }),
      ),
    };
  }
  return {
    accepted: true,
    exercises,
    workout: {
      ...workout,
      exercises: workout.exercises.map((exercise) => ({
        ...exercise,
        exerciseName: exercises.get(exercise.exerciseId)!.name,
      })),
    },
  };
}

function validateCapturedContent({
  content,
  exercises,
}: {
  content: AgentCapturedTemplateContent;
  exercises: ReadonlyMap<string, AgentExercise>;
}) {
  return validatePlanContent({
    exercises: content.exercises,
    groups: content.groups,
    catalogExercises: exercises,
    sourceRoot: "capturedContent",
  });
}

function validateUpdatedContent({
  content,
  exercises,
}: {
  content: AgentTemplateDivergenceComparison["updatedContent"];
  exercises: ReadonlyMap<string, AgentExercise>;
}) {
  return validatePlanContent({
    exercises: content.exercises,
    groups: content.groups,
    catalogExercises: exercises,
    sourceRoot: "updatedContent",
  });
}

function validatePlanContent({
  catalogExercises,
  exercises,
  groups,
  sourceRoot,
}: {
  catalogExercises: ReadonlyMap<string, AgentExercise>;
  exercises: {
    exerciseId: string;
    prescriptions: {
      mode: "fixed" | "copyPrevious";
      values: AgentPlanCaptureValues;
      repeat: number;
      restAfterSeconds: number | null;
    }[];
  }[];
  groups: {
    name: string;
    colorHex: string;
    rounds: number;
    memberExerciseIndexes: number[];
  }[];
  sourceRoot: string;
}) {
  const errors: AgentPlanCaptureIssue[] = [];
  const warnings: AgentPlanCaptureIssue[] = [];
  for (const [exerciseIndex, exercise] of exercises.entries()) {
    const catalogExercise = catalogExercises.get(exercise.exerciseId);
    if (catalogExercise === undefined) {
      errors.push(
        captureIssue({
          sourcePath: `${sourceRoot}.exercises[${exerciseIndex}]`,
          field: "exerciseId",
          rule: "capture_exercise_not_found",
          message: `Exercise is not caller-visible: ${exercise.exerciseId}.`,
          limit: "caller-visible",
        }),
      );
      continue;
    }
    for (const [
      prescriptionIndex,
      prescription,
    ] of exercise.prescriptions.entries()) {
      const sourcePath = `${sourceRoot}.exercises[${exerciseIndex}].prescriptions[${prescriptionIndex}]`;
      const result = validateAgentPrescription({
        mode: prescription.mode,
        // Capture is historical fact. Match Dart by validating the
        // self-describing dimensions that survived projection, not today's
        // Exercise Type input template.
        dimensions: captureDimensions.filter(
          (dimension) => prescription.values[dimension] !== undefined,
        ),
        loadMode: catalogExercise.loadMode,
        repeat: prescription.repeat,
        restAfterSeconds: prescription.restAfterSeconds,
        values: prescription.values,
      });
      errors.push(...contextualIssues(result.errors, sourcePath));
      warnings.push(...contextualIssues(result.warnings, sourcePath));
    }
  }
  for (const [groupIndex, group] of groups.entries()) {
    const sourcePath = `${sourceRoot}.groups[${groupIndex}]`;
    const result = validateAgentTemplateGroup({
      name: group.name,
      colorHex: group.colorHex,
      rounds: group.rounds,
      memberIds: group.memberExerciseIndexes.map(
        (index) => exercises[index]?.exerciseId ?? `missing:${index}`,
      ),
    });
    errors.push(...contextualIssues(result.errors, sourcePath));
    warnings.push(...contextualIssues(result.warnings, sourcePath));
  }
  return { errors, warnings };
}

function validateCapturePlacement(
  routine: AgentPlanCaptureRoutineState,
  requestedSlot: number | null,
) {
  const activeEntries = activePositionedRows(routine.entries);
  const errors: AgentPlanCaptureIssue[] = [];
  const positions = activeEntries.map((entry) =>
    payloadRequiredInteger(entry.payload, "position"),
  );
  if (positions.some((position, index) => position !== index)) {
    errors.push(
      captureIssue({
        sourcePath: "placement",
        field: "position",
        rule: "routine_entry_positions_not_normalized",
        message:
          "Routine Entry positions must be contiguous from zero before capture can append.",
        limit: "0..n-1",
      }),
    );
  }
  const result = validateAgentRoutineCadence({
    cadenceKind: payloadNullableString(
      routine.routine.payload,
      "cadence_kind",
    ),
    cadenceWindow: payloadNullableNumber(
      routine.routine.payload,
      "cadence_window",
    ),
    slots: [
      ...activeEntries.map((entry) =>
        payloadNullableNumber(entry.payload, "slot"),
      ),
      requestedSlot,
    ],
  });
  return {
    errors: [...errors, ...contextualIssues(result.errors, "placement")],
    warnings: contextualIssues(result.warnings, "placement"),
  };
}

function contextualIssues(
  issues: readonly AgentSetValidationIssue[],
  sourcePath: string,
) {
  return issues.map((issue) =>
    AgentPlanCaptureIssueSchema.parse({
      ...issue,
      sourcePath,
    }),
  );
}

function captureIssue({
  dimension = null,
  field,
  limit,
  message,
  rule,
  sourcePath,
}: {
  sourcePath: string;
  field: string;
  dimension?: "load" | "reps" | "duration" | "distance" | null;
  rule: string;
  message: string;
  limit: unknown;
}) {
  return AgentPlanCaptureIssueSchema.parse({
    sourcePath,
    field,
    dimension,
    rule,
    message,
    limit,
  });
}

function emptyMutationRows(): AgentPlanMutationRows {
  return {
    workoutTemplates: [],
    templateExercises: [],
    prescriptions: [],
    templateGroups: [],
    templateGroupMembers: [],
    routineEntries: [],
  };
}

function mutationRow(
  id: string,
  payload: Record<string, unknown>,
  updatedAt: string,
  deletedAt: string | null = null,
): AgentPlanMutationRow {
  return {
    id,
    payload: {
      ...payload,
      updated_at: updatedAt,
      deleted_at: deletedAt,
    },
    updatedAt,
    deletedAt,
  };
}

function appendContentRows({
  content,
  createId,
  now,
  nowIso,
  rows,
  workoutTemplateId,
}: {
  content:
    | AgentCapturedTemplateContent
    | AgentTemplateDivergenceComparison["updatedContent"];
  createId: (timestamp?: Date) => string;
  now: Date;
  nowIso: string;
  rows: AgentPlanMutationRows;
  workoutTemplateId: string;
}) {
  const templateExerciseIds: string[] = [];
  let prescriptionCount = 0;
  for (const [exerciseIndex, exercise] of content.exercises.entries()) {
    const templateExerciseId = createId(now);
    templateExerciseIds.push(templateExerciseId);
    rows.templateExercises.push(
      mutationRow(
        templateExerciseId,
        {
          id: templateExerciseId,
          workout_template_id: workoutTemplateId,
          exercise_id: exercise.exerciseId,
          position: exerciseIndex,
          note: null,
        },
        nowIso,
      ),
    );
    for (const [
      prescriptionIndex,
      prescription,
    ] of exercise.prescriptions.entries()) {
      const prescriptionId = createId(now);
      prescriptionCount += 1;
      rows.prescriptions.push(
        mutationRow(
          prescriptionId,
          {
            id: prescriptionId,
            template_exercise_id: templateExerciseId,
            mode:
              prescription.mode === "copyPrevious"
                ? "copy-previous"
                : "fixed",
            position: prescriptionIndex,
            repeat: prescription.repeat,
            rest_after: prescription.restAfterSeconds,
            ...prescriptionDimensionPayload(prescription.values),
          },
          nowIso,
        ),
      );
    }
  }
  for (const [groupIndex, group] of content.groups.entries()) {
    const groupId = createId(now);
    rows.templateGroups.push(
      mutationRow(
        groupId,
        {
          id: groupId,
          workout_template_id: workoutTemplateId,
          name: group.name,
          color_hex: group.colorHex,
          rounds: 1,
          position: groupIndex,
        },
        nowIso,
      ),
    );
    for (const [memberIndex, exerciseIndex] of group.memberExerciseIndexes.entries()) {
      const memberId = createId(now);
      rows.templateGroupMembers.push(
        mutationRow(
          memberId,
          {
            id: memberId,
            group_id: groupId,
            template_exercise_id: templateExerciseIds[exerciseIndex],
            position: memberIndex,
          },
          nowIso,
        ),
      );
    }
  }
  return { prescriptionCount };
}

function prescriptionDimensionPayload(values: AgentPlanCaptureValues) {
  const payload: Record<string, unknown> = {};
  for (const dimension of captureDimensions) {
    const value = values[dimension];
    payload[`${dimension}_value`] =
      value === undefined ? null : Number(value.entered);
    payload[`${dimension}_unit`] =
      value === undefined ? null : value.unit;
    payload[`${dimension}_entered`] =
      value === undefined ? null : value.entered;
  }
  return payload;
}

function appendContentTombstones(
  rows: AgentPlanMutationRows,
  state: AgentPlanCaptureLinkedTemplateState,
  nowIso: string,
) {
  const append = (
    target: AgentPlanMutationRow[],
    source: AgentPlanCaptureOpaqueRow[],
  ) => {
    for (const row of source) {
      target.push(mutationRow(row.id, row.payload, nowIso, nowIso));
    }
  };
  append(rows.templateGroupMembers, state.templateGroupMembers);
  append(rows.prescriptions, state.prescriptions);
  append(rows.templateGroups, state.templateGroups);
  append(rows.templateExercises, state.templateExercises);
}

function mutationRowCount(rows: AgentPlanMutationRows) {
  return Object.values(rows).reduce(
    (count, collection) => count + collection.length,
    0,
  );
}

function templateSnapshotFromState(
  state: AgentPlanCaptureLinkedTemplateState,
  catalogExercises: ReadonlyMap<string, AgentExercise>,
): AgentTemplateContentSnapshot {
  const templateExercises = activePositionedRows(state.templateExercises);
  const prescriptionsByExerciseId = groupByPayloadParent(
    activePositionedRows(state.prescriptions),
    "template_exercise_id",
  );
  const groups = activePositionedRows(state.templateGroups);
  const membersByGroupId = groupByPayloadParent(
    activePositionedRows(state.templateGroupMembers),
    "group_id",
  );
  const exerciseIdByTemplateExerciseId = new Map(
    templateExercises.map((row) => [
      row.id,
      payloadRequiredString(row.payload, "exercise_id"),
    ]),
  );
  return {
    exercises: templateExercises.map((row) => {
      const exerciseId = payloadRequiredString(row.payload, "exercise_id");
      return {
        exerciseId,
        exerciseName:
          catalogExercises.get(exerciseId)?.name ?? exerciseId,
        prescriptions: (
          prescriptionsByExerciseId.get(row.id) ?? []
        ).map((prescription) => {
          const storedMode = payloadRequiredString(
            prescription.payload,
            "mode",
          );
          if (
            storedMode !== "fixed" &&
            storedMode !== "copy-previous" &&
            storedMode !== "copyPrevious"
          ) {
            throwWorkoutIntegrityError({
              sourcePath: "linkedTemplate.prescriptions",
              field: "mode",
              rule: "prescription_mode_invalid",
              message:
                "Stored Prescription mode must be fixed or copy-previous.",
              limit: "fixed|copy-previous",
            });
          }
          const mode =
            storedMode === "copy-previous" ||
            storedMode === "copyPrevious"
              ? ("copyPrevious" as const)
              : ("fixed" as const);
          return {
            mode,
            values:
              mode === "copyPrevious"
                ? {}
                : dimensionValuesFromPayload(prescription.payload),
            repeat: payloadRequiredInteger(
              prescription.payload,
              "repeat",
            ),
            restAfterSeconds: payloadNullableNumber(
              prescription.payload,
              "rest_after",
            ),
          };
        }),
      };
    }),
    groups: groups.map((group) => ({
      memberExerciseIds: (
        membersByGroupId.get(group.id) ?? []
      ).map((member) => {
        const templateExerciseId = payloadRequiredString(
          member.payload,
          "template_exercise_id",
        );
        const exerciseId =
          exerciseIdByTemplateExerciseId.get(templateExerciseId);
        if (exerciseId === undefined) {
          throw new AgentPlanCaptureSourceError([
            captureIssue({
              sourcePath: "linkedTemplate.groups",
              field: "templateExerciseId",
              rule: "template_group_member_reference_missing",
              message:
                "Template Group Member references a missing active Template Exercise.",
              limit: "active-template-exercise",
            }),
          ]);
        }
        return exerciseId;
      }),
    })),
  };
}

class AgentPlanCaptureSourceError extends Error {
  constructor(readonly issues: AgentPlanCaptureIssue[]) {
    super("Stored Workout or Template content cannot be captured.");
  }
}

function throwWorkoutIntegrityError({
  field,
  limit,
  message,
  rule,
  sourcePath,
}: {
  sourcePath: string;
  field: string;
  rule: string;
  message: string;
  limit: unknown;
}): never {
  throw new AgentPlanCaptureSourceError([
    captureIssue({
      sourcePath,
      field,
      rule,
      message,
      limit,
    }),
  ]);
}

function sourceValidationFailure(
  kind: "capture" | "update",
  error: unknown,
  warnings: AgentPlanCaptureIssue[] = [],
): AgentPlanCaptureRunResult {
  if (error instanceof AgentPlanCaptureSourceError) {
    return validationFailed(kind, error.issues, warnings);
  }
  throw error;
}

function workoutExercisesRequiredIssue() {
  return captureIssue({
    sourcePath: "workout.exercises",
    field: "exercises",
    rule: "capture_workout_exercises_required",
    message:
      "Capture and update-from-Workout require at least one active Workout Exercise.",
    limit: 1,
  });
}

function agentPlanDivergenceExists(
  divergence: AgentPlanDivergence,
) {
  return (
    divergence.addedExercises.length > 0 ||
    divergence.removedExercises.length > 0 ||
    divergence.changedExercises.length > 0 ||
    divergence.groupsChanged
  );
}

function planVerbConflict(
  kind: "capture" | "update",
  error: unknown,
): AgentPlanCaptureRunResult {
  if (!(error instanceof AgentPlanCaptureConflictError)) {
    throw error;
  }
  return {
    status: "conflict",
    body: AgentPlanCaptureConflictResponseSchema.parse({
      code:
        kind === "capture"
          ? "agent_plan_capture_conflict"
          : "agent_plan_update_from_workout_conflict",
      message:
        "A newer plan row won the LWW race. Nothing from this atomic operation was committed; reload the plan tree before retrying.",
      retryable: true,
      superseded: error.superseded,
    }),
  };
}

function validationFailed(
  kind: "capture" | "update",
  errors: AgentPlanCaptureIssue[],
  warnings: AgentPlanCaptureIssue[],
): AgentPlanCaptureRunResult {
  return {
    status: "validation_failed",
    body: AgentPlanCaptureErrorResponseSchema.parse({
      code:
        kind === "capture"
          ? "agent_plan_capture_failed"
          : "agent_plan_update_from_workout_failed",
      message:
        kind === "capture"
          ? "Workout could not be captured as a Workout Template."
          : "Workout Template could not be updated from the Workout.",
      errors,
      warnings,
      limits: agentPlanCaptureLimitsResponse(),
    }),
  };
}

function notFound(
  code: z.infer<typeof AgentPlanCaptureNotFoundResponseSchema>["code"],
  message: string,
): AgentPlanCaptureRunResult {
  return {
    status: "not_found",
    body: AgentPlanCaptureNotFoundResponseSchema.parse({ code, message }),
  };
}

function catalogUnavailable(): AgentPlanCaptureRunResult {
  return {
    status: "catalog_unavailable",
    body: AgentCatalogUnavailableResponseSchema.parse({
      code: "agent_catalog_unavailable",
      message: "Agent Exercise catalog storage is not configured.",
    }),
  };
}

function acceptedCaptureResult(
  idempotencyKey: string,
  receipt: AgentPlanCaptureReceipt,
  duplicate: boolean,
  applied: number,
): AgentPlanCaptureRunResult & { applied: number } {
  const { kind: _kind, ...responseReceipt } = receipt;
  return {
    status: "accepted",
    applied,
    body: AgentPlanCaptureResponseSchema.parse({
      accepted: true,
      duplicate,
      idempotencyKey,
      batchId: idempotencyKey,
      ...responseReceipt,
      limits: agentPlanCaptureLimitsResponse(),
    }),
  };
}

function acceptedUpdateResult(
  idempotencyKey: string,
  receipt: AgentPlanUpdateReceipt,
  duplicate: boolean,
  applied: number,
): AgentPlanCaptureRunResult & { applied: number } {
  const { kind: _kind, ...responseReceipt } = receipt;
  return {
    status: "accepted",
    applied,
    body: AgentPlanUpdateFromWorkoutResponseSchema.parse({
      accepted: true,
      duplicate,
      idempotencyKey,
      batchId: idempotencyKey,
      ...responseReceipt,
      limits: agentPlanCaptureLimitsResponse(),
    }),
  };
}

export function createDrizzleAgentPlanCaptureStore(
  db: ServerDatabase,
): AgentPlanCaptureStore {
  return {
    async readPlanVerbReceipt({ userId, batchId, kind }) {
      return readDrizzlePlanVerbReceipt(db, userId, batchId, kind);
    },

    async loadWorkoutCaptureSource({ userId, workoutId }) {
      return loadDrizzleWorkoutCaptureSource(db, userId, workoutId);
    },

    async loadCaptureRoutine({ userId, routineId }) {
      const [routineRows, entryRows] = await Promise.all([
        db
          .select()
          .from(schema.routines)
          .where(
            and(
              eq(schema.routines.userId, userId),
              eq(schema.routines.id, routineId),
              isNull(schema.routines.deletedAt),
            ),
          )
          .limit(1),
        db
          .select()
          .from(schema.routineEntries)
          .where(
            and(
              eq(schema.routineEntries.userId, userId),
              isNull(schema.routineEntries.deletedAt),
              sql`${schema.routineEntries.payload} ->> 'routine_id' = ${routineId}`,
            ),
          ),
      ]);
      const routine = routineRows[0];
      return routine === undefined
        ? null
        : {
            routine,
            entries: entryRows,
          };
    },

    async loadLinkedTemplate({ userId, workoutId }) {
      return loadDrizzleLinkedTemplate(db, userId, workoutId);
    },

    async writePlanVerb({
      userId,
      batchId,
      deviceId,
      kind,
      receipt,
      rows,
    }) {
      const serverClock = new Date();
      return db.transaction(async (transaction) => {
        const storedReceipt = {
          ...receipt,
          serverClock: serverClock.toISOString(),
        } as AgentPlanVerbReceipt;
        const entityTable =
          kind === "capture"
            ? AGENT_PLAN_CAPTURE_BATCH_ENTITY
            : AGENT_PLAN_UPDATE_BATCH_ENTITY;
        const inserted = await transaction
          .insert(schema.activityLog)
          .values({
            id: `agent:${userId}:${batchId}:plan-${kind}`,
            userId,
            actor: "agent",
            batchId,
            entityTable,
            entityId: batchId,
            beforeImage: null,
            afterImage: {
              idempotencyKey: batchId,
              ...storedReceipt,
            },
            occurredAt: serverClock,
          })
          .onConflictDoNothing({ target: schema.activityLog.id })
          .returning({ id: schema.activityLog.id });
        if (inserted.length === 0) {
          const winner = await readDrizzlePlanVerbReceipt(
            transaction,
            userId,
            batchId,
            kind,
          );
          if (winner === null) {
            throw new Error(
              "Plan capture/update batch marker collided outside the caller's receipt scope.",
            );
          }
          return {
            duplicate: true,
            applied: 0,
            receipt: winner,
          };
        }

        const groups: {
          entityType: AgentPlanMutationEntityType;
          keyPrefix: string;
          rows: AgentPlanMutationRow[];
          table:
            | typeof schema.workoutTemplates
            | typeof schema.templateExercises
            | typeof schema.prescriptions
            | typeof schema.templateGroups
            | typeof schema.templateGroupMembers
            | typeof schema.routineEntries;
          push: (
            transaction: Parameters<
              typeof pushWorkoutTemplatesInTransaction
            >[0],
            input: {
              userId: string;
              deviceId: string;
              changes: SyncPushChange[];
              serverClock: Date;
            },
          ) => Promise<SyncPushResult>;
        }[] = [
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
            entityType: "routineEntry",
            keyPrefix: "routine-entry",
            rows: rows.routineEntries,
            table: schema.routineEntries,
            push: pushRoutineEntriesInTransaction,
          },
        ];
        let applied = 0;
        const superseded: AgentPlanSupersededRow[] = [];
        for (const group of groups) {
          if (group.rows.length === 0) {
            continue;
          }
          const changes: SyncPushChange[] = [];
          for (const row of group.rows) {
            const beforeImage = await readPlanBeforeImage(
              transaction,
              group.table,
              userId,
              row.id,
            );
            changes.push({
              id: row.id,
              payload: row.payload,
              updatedAt: row.updatedAt,
              deletedAt: row.deletedAt,
              activityLogId: `agent:${batchId}:${kind}:${group.keyPrefix}:${row.id}`,
              actor: "agent",
              batchId,
              beforeImage,
              afterImage: {
                ...row.payload,
                updated_at: row.updatedAt,
                deleted_at: row.deletedAt,
              },
              occurredAt: row.updatedAt,
            });
          }
          const result = await group.push(transaction, {
            userId,
            deviceId,
            changes,
            serverClock,
          });
          applied += result.applied.length;
          const appliedIds = new Set(result.applied.map((row) => row.id));
          for (const row of group.rows) {
            if (!appliedIds.has(row.id)) {
              superseded.push({
                entityType: group.entityType,
                id: row.id,
              });
            }
          }
        }
        if (superseded.length > 0) {
          throw new AgentPlanCaptureConflictError(superseded);
        }
        return {
          duplicate: false,
          applied,
          receipt: storedReceipt,
        };
      });
    },
  };
}

async function loadDrizzleWorkoutCaptureSource(
  db: ServerDatabase,
  userId: string,
  workoutId: string,
): Promise<AgentWorkoutCaptureSnapshot | null> {
  const [
    setRows,
    linkRows,
    workoutSessionRows,
    workoutExerciseRows,
    workoutGroupRows,
  ] = await Promise.all([
    db
      .select()
      .from(schema.loggedSets)
      .where(
        and(
          eq(schema.loggedSets.userId, userId),
          isNull(schema.loggedSets.deletedAt),
          sql`${schema.loggedSets.payload} ->> 'workout_id' = ${workoutId}`,
        ),
      ),
    db
      .select()
      .from(schema.templateLinks)
      .where(
        and(
          eq(schema.templateLinks.userId, userId),
          isNull(schema.templateLinks.deletedAt),
          sql`${schema.templateLinks.payload} ->> 'workout_id' = ${workoutId}`,
        ),
      )
      .orderBy(desc(schema.templateLinks.updatedAt), desc(schema.templateLinks.id)),
    db
      .select()
      .from(schema.workoutSessions)
      .where(
        and(
          eq(schema.workoutSessions.userId, userId),
          eq(schema.workoutSessions.id, workoutId),
        ),
      )
      .limit(1),
    db
      .select()
      .from(schema.workoutExercises)
      .where(
        and(
          eq(schema.workoutExercises.userId, userId),
          isNull(schema.workoutExercises.deletedAt),
          sql`${schema.workoutExercises.payload} ->> 'workout_id' = ${workoutId}`,
        ),
      ),
    db
      .select()
      .from(schema.exerciseGroups)
      .where(
        and(
          eq(schema.exerciseGroups.userId, userId),
          isNull(schema.exerciseGroups.deletedAt),
          sql`${schema.exerciseGroups.payload} ->> 'workout_id' = ${workoutId}`,
        ),
      ),
  ]);
  const link = linkRows[0];
  const workoutSession = workoutSessionRows[0];
  if (workoutSession !== undefined && workoutSession.deletedAt !== null) {
    return null;
  }
  if (
    setRows.length === 0 &&
    link === undefined &&
    workoutSession === undefined
  ) {
    return null;
  }
  const hasAuthoritativeStructure = workoutExerciseRows.length > 0;
  const hasLegacyStructureEnvelope =
    link !== undefined &&
    Object.hasOwn(link.payload, "workout_deleted_at") &&
    Array.isArray(link.payload.workout_exercises) &&
    Array.isArray(link.payload.workout_exercise_groups) &&
    Array.isArray(link.payload.workout_exercise_group_members);
  if (
    !hasAuthoritativeStructure &&
    hasLegacyStructureEnvelope &&
    payloadNullableString(link.payload, "workout_deleted_at") !== null
  ) {
    return null;
  }
  const workoutGroupIds = workoutGroupRows.map((row) => row.id);
  const workoutGroupMemberRows =
    workoutGroupIds.length === 0
      ? []
      : await db
          .select()
          .from(schema.exerciseGroupMembers)
          .where(
            and(
              eq(schema.exerciseGroupMembers.userId, userId),
              isNull(schema.exerciseGroupMembers.deletedAt),
              inArray(
                sql<string>`${schema.exerciseGroupMembers.payload} ->> 'group_id'`,
                workoutGroupIds,
              ),
            ),
          );

  const sortedSets = [...setRows].sort((left, right) => {
    const position =
      payloadRequiredInteger(left.payload, "position") -
      payloadRequiredInteger(right.payload, "position");
    return position !== 0 ? position : compareBinaryIds(left.id, right.id);
  });
  const setsByExerciseId = new Map<string, AgentWorkoutCaptureSetSnapshot[]>();
  const exerciseNameById = new Map<string, string>();
  for (const row of sortedSets) {
    const exerciseId = payloadRequiredString(row.payload, "exercise_id");
    const exerciseName = payloadNullableString(
      row.payload,
      "exercise_name",
    );
    if (exerciseName !== null) {
      exerciseNameById.set(exerciseId, exerciseName);
    }
    const sets = setsByExerciseId.get(exerciseId) ?? [];
    sets.push({
      sourceSetId: row.id,
      position: payloadRequiredInteger(row.payload, "position"),
      values: dimensionValuesFromPayload(row.payload),
      plannedRestAfterSeconds: payloadNullableNumber(
        row.payload,
        "planned_rest_after",
      ),
    });
    setsByExerciseId.set(exerciseId, sets);
  }

  const structuredExercises = hasAuthoritativeStructure
    ? workoutExerciseRows
        .map((row) => ({ id: row.id, payload: row.payload }))
        .sort((left, right) =>
          comparePayloadPositionedRows(left.payload, right.payload),
        )
    : hasLegacyStructureEnvelope
      ? payloadObjectArray(link!.payload, "workout_exercises")
          .filter((row) => payloadNullableString(row, "deleted_at") === null)
          .sort(comparePayloadPositionedRows)
          .map((payload) => ({
            id: payloadRequiredString(payload, "id"),
            payload,
          }))
      : [];
  const exercises: AgentWorkoutCaptureExerciseSnapshot[] =
    hasAuthoritativeStructure || hasLegacyStructureEnvelope
      ? structuredExercises.map((row) => {
          const exerciseId = payloadRequiredString(
            row.payload,
            "exercise_id",
          );
          return {
            sourceWorkoutExerciseId: row.id,
            exerciseId,
            exerciseName:
              exerciseNameById.get(exerciseId) ?? exerciseId,
            position: payloadRequiredInteger(row.payload, "position"),
            sets: setsByExerciseId.get(exerciseId) ?? [],
          };
        })
      : [...setsByExerciseId.entries()]
          .sort(([leftId, leftSets], [rightId, rightSets]) => {
            const position =
              (leftSets[0]?.position ?? 0) -
              (rightSets[0]?.position ?? 0);
            return position !== 0
              ? position
              : compareBinaryIds(leftId, rightId);
          })
          .map(([exerciseId, sets], index) => ({
            sourceWorkoutExerciseId: `${workoutId}:exercise:${exerciseId}`,
            exerciseId,
            exerciseName:
              exerciseNameById.get(exerciseId) ?? exerciseId,
            position: index,
            sets,
          }));
  const activeExerciseIds = new Set(
    exercises.map((exercise) => exercise.exerciseId),
  );
  const orphanExerciseId = [...setsByExerciseId.keys()].find(
    (exerciseId) => !activeExerciseIds.has(exerciseId),
  );
  if (orphanExerciseId !== undefined) {
    throw new AgentPlanCaptureSourceError([
      captureIssue({
        sourcePath: "workout.sets",
        field: "exerciseId",
        rule: "capture_set_without_workout_exercise",
        message:
          "Workout has an active Set without an active Workout Exercise.",
        limit: "active-workout-exercise",
      }),
    ]);
  }

  const groups = hasAuthoritativeStructure
    ? workoutGroupsFromRows(
        workoutGroupRows.map((row) => row.payload),
        workoutGroupMemberRows.map((row) => row.payload),
        exercises,
      )
    : hasLegacyStructureEnvelope
      ? workoutGroupsFromEnvelope(link!.payload, exercises)
      : [];
  const sourceWarnings =
    hasAuthoritativeStructure || hasLegacyStructureEnvelope
    ? []
    : [
        captureIssue({
          sourcePath: "workout.structure",
          field: "workoutId",
          rule: "capture_workout_structure_unavailable",
          message:
            "This Workout has no synchronized structure or legacy materialization envelope. Capture recovered Set-backed Exercises, but exact Workout Exercise order, Groups, and archive state are unavailable.",
          limit: "synchronized-workout-structure",
        }),
      ];
  return {
    workoutId,
    exercises,
    groups,
    sourceWarnings,
  };
}

function workoutGroupsFromEnvelope(
  payload: Record<string, unknown>,
  exercises: AgentWorkoutCaptureExerciseSnapshot[],
) {
  return workoutGroupsFromRows(
    payloadObjectArray(payload, "workout_exercise_groups"),
    payloadObjectArray(payload, "workout_exercise_group_members"),
    exercises,
  );
}

function workoutGroupsFromRows(
  groupRows: Record<string, unknown>[],
  memberRows: Record<string, unknown>[],
  exercises: AgentWorkoutCaptureExerciseSnapshot[],
) {
  const groups = groupRows
    .filter((row) => payloadNullableString(row, "deleted_at") === null)
    .sort(comparePayloadPositionedRows);
  const activeSourceIds = new Set(
    exercises.map((exercise) => exercise.sourceWorkoutExerciseId),
  );
  const membersByGroupId = new Map<string, Record<string, unknown>[]>();
  for (const member of memberRows
    .filter((row) => payloadNullableString(row, "deleted_at") === null)
    .sort(comparePayloadPositionedRows)) {
    const groupId = payloadRequiredString(member, "group_id");
    const existing = membersByGroupId.get(groupId) ?? [];
    existing.push(member);
    membersByGroupId.set(groupId, existing);
  }
  return groups.map((group) => {
    const sourceGroupId = payloadRequiredString(group, "id");
    const memberSourceWorkoutExerciseIds = (
      membersByGroupId.get(sourceGroupId) ?? []
    ).map((member) =>
      payloadRequiredString(member, "workout_exercise_id"),
    );
    if (
      memberSourceWorkoutExerciseIds.some(
        (sourceId) => !activeSourceIds.has(sourceId),
      )
    ) {
      throw new AgentPlanCaptureSourceError([
        captureIssue({
          sourcePath: "workout.groups",
          field: "workoutExerciseId",
          rule: "capture_group_member_reference_missing",
          message:
            "Workout Exercise Group Member references a missing active Workout Exercise.",
          limit: "active-workout-exercise",
        }),
      ]);
    }
    return {
      sourceGroupId,
      name: payloadRequiredString(group, "name"),
      colorHex: payloadRequiredString(group, "color_hex"),
      position: payloadRequiredInteger(group, "position"),
      memberSourceWorkoutExerciseIds,
    };
  });
}

async function loadDrizzleLinkedTemplate(
  db: ServerDatabase,
  userId: string,
  workoutId: string,
): Promise<AgentPlanCaptureLinkedTemplateState | null> {
  const linkRows = await db
    .select()
    .from(schema.templateLinks)
    .where(
      and(
        eq(schema.templateLinks.userId, userId),
        isNull(schema.templateLinks.deletedAt),
        sql`${schema.templateLinks.payload} ->> 'workout_id' = ${workoutId}`,
      ),
    )
    .orderBy(desc(schema.templateLinks.updatedAt), desc(schema.templateLinks.id))
    .limit(1);
  const templateLink = linkRows[0];
  if (templateLink === undefined) {
    return null;
  }
  const workoutTemplateId = payloadRequiredString(
    templateLink.payload,
    "workout_template_id",
  );
  const [templateRows, templateExercises, templateGroups] =
    await Promise.all([
      db
        .select()
        .from(schema.workoutTemplates)
        .where(
          and(
            eq(schema.workoutTemplates.userId, userId),
            eq(schema.workoutTemplates.id, workoutTemplateId),
            isNull(schema.workoutTemplates.deletedAt),
          ),
        )
        .limit(1),
      db
        .select()
        .from(schema.templateExercises)
        .where(
          and(
            eq(schema.templateExercises.userId, userId),
            isNull(schema.templateExercises.deletedAt),
            sql`${schema.templateExercises.payload} ->> 'workout_template_id' = ${workoutTemplateId}`,
          ),
        ),
      db
        .select()
        .from(schema.templateGroups)
        .where(
          and(
            eq(schema.templateGroups.userId, userId),
            isNull(schema.templateGroups.deletedAt),
            sql`${schema.templateGroups.payload} ->> 'workout_template_id' = ${workoutTemplateId}`,
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
              isNull(schema.prescriptions.deletedAt),
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
              isNull(schema.templateGroupMembers.deletedAt),
              inArray(
                sql<string>`${schema.templateGroupMembers.payload} ->> 'group_id'`,
                templateGroupIds,
              ),
            ),
          ),
  ]);
  return {
    templateLink,
    workoutTemplate: templateRows[0] ?? null,
    templateExercises,
    prescriptions,
    templateGroups,
    templateGroupMembers,
  };
}

async function readDrizzlePlanVerbReceipt(
  db: Pick<ServerDatabase, "select">,
  userId: string,
  batchId: string,
  kind: "capture" | "update",
): Promise<AgentPlanVerbReceipt | null> {
  const entityTable =
    kind === "capture"
      ? AGENT_PLAN_CAPTURE_BATCH_ENTITY
      : AGENT_PLAN_UPDATE_BATCH_ENTITY;
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
        eq(schema.activityLog.entityTable, entityTable),
      ),
    )
    .limit(1);
  const row = rows[0];
  if (row?.afterImage === null || row?.afterImage === undefined) {
    return null;
  }
  const image = row.afterImage;
  const warnings = Array.isArray(image.warnings)
    ? image.warnings.map((warning) =>
        AgentPlanCaptureIssueSchema.parse(warning),
      )
    : [];
  if (kind === "capture") {
    return {
      kind,
      workoutId: requiredImageString(image, "workoutId"),
      workoutTemplateId: requiredImageString(
        image,
        "workoutTemplateId",
      ),
      routineEntryId: nullableImageString(image, "routineEntryId"),
      exerciseCount: requiredImageNumber(image, "exerciseCount"),
      prescriptionCount: requiredImageNumber(
        image,
        "prescriptionCount",
      ),
      groupCount: requiredImageNumber(image, "groupCount"),
      warnings,
      serverClock: row.occurredAt.toISOString(),
    };
  }
  return {
    kind,
    workoutId: requiredImageString(image, "workoutId"),
    workoutTemplateId: requiredImageString(
      image,
      "workoutTemplateId",
    ),
    exerciseCount: requiredImageNumber(image, "exerciseCount"),
    prescriptionCount: requiredImageNumber(
      image,
      "prescriptionCount",
    ),
    groupCount: requiredImageNumber(image, "groupCount"),
    divergence: AgentPlanDivergenceSchema.parse(image.divergence),
    warnings,
    serverClock: row.occurredAt.toISOString(),
  };
}

type PlanMutationTable =
  | typeof schema.workoutTemplates
  | typeof schema.templateExercises
  | typeof schema.prescriptions
  | typeof schema.templateGroups
  | typeof schema.templateGroupMembers
  | typeof schema.routineEntries;

async function readPlanBeforeImage(
  transaction: Pick<ServerDatabase, "select">,
  table: PlanMutationTable,
  userId: string,
  id: string,
) {
  const rows = await transaction
    .select({ userId: table.userId, payload: table.payload })
    .from(table)
    .where(eq(table.id, id))
    .limit(1);
  const row = rows[0];
  return row === undefined || row.userId !== userId ? null : row.payload;
}

function activePositionedRows(rows: AgentPlanCaptureOpaqueRow[]) {
  return rows
    .filter((row) => row.deletedAt === null)
    .sort((left, right) => {
      const position =
        payloadRequiredInteger(left.payload, "position") -
        payloadRequiredInteger(right.payload, "position");
      return position !== 0
        ? position
        : compareBinaryIds(left.id, right.id);
    });
}

function groupByPayloadParent(
  rows: AgentPlanCaptureOpaqueRow[],
  field: string,
) {
  const grouped = new Map<string, AgentPlanCaptureOpaqueRow[]>();
  for (const row of rows) {
    const parentId = payloadRequiredString(row.payload, field);
    const existing = grouped.get(parentId) ?? [];
    existing.push(row);
    grouped.set(parentId, existing);
  }
  return grouped;
}

function dimensionValuesFromPayload(
  payload: Record<string, unknown>,
): AgentPlanCaptureValues {
  const nested =
    typeof payload.values === "object" &&
    payload.values !== null &&
    !Array.isArray(payload.values)
      ? (payload.values as Record<string, unknown>)
      : {};
  return Object.fromEntries(
    captureDimensions.flatMap((dimension) => {
      const entered =
        payloadNullableString(payload, `${dimension}_entered`) ??
        nestedDimensionString(nested, dimension, "entered");
      const unit =
        payloadNullableString(payload, `${dimension}_unit`) ??
        nestedDimensionString(nested, dimension, "unit");
      if (entered === null && unit === null) {
        return [];
      }
      if (entered === null || unit === null) {
        throw new AgentPlanCaptureSourceError([
          captureIssue({
            sourcePath: "workout.sets",
            field: dimension,
            dimension,
            rule: "capture_dimension_value_incomplete",
            message: `Captured ${dimension} requires both entered text and unit.`,
            limit: "entered+unit",
          }),
        ]);
      }
      return [[dimension, { entered, unit }]];
    }),
  ) as AgentPlanCaptureValues;
}

function nestedDimensionString(
  values: Record<string, unknown>,
  dimension: string,
  field: string,
) {
  const raw = values[dimension];
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    return null;
  }
  const value = (raw as Record<string, unknown>)[field];
  return typeof value === "string" ? value : null;
}

function payloadObjectArray(
  payload: Record<string, unknown>,
  key: string,
) {
  const raw = payload[key];
  if (!Array.isArray(raw)) {
    return [];
  }
  return raw.filter(
    (value): value is Record<string, unknown> =>
      typeof value === "object" && value !== null && !Array.isArray(value),
  );
}

function comparePayloadPositionedRows(
  left: Record<string, unknown>,
  right: Record<string, unknown>,
) {
  const position =
    payloadRequiredInteger(left, "position") -
    payloadRequiredInteger(right, "position");
  return position !== 0
    ? position
    : compareBinaryIds(
        payloadRequiredString(left, "id"),
        payloadRequiredString(right, "id"),
      );
}

function compareBinaryIds(left: string, right: string) {
  return Buffer.from(left).compare(Buffer.from(right));
}

function payloadRequiredString(
  payload: Record<string, unknown>,
  key: string,
) {
  const value = payload[key];
  if (typeof value !== "string" || value.length === 0) {
    throw new AgentPlanCaptureSourceError([
      captureIssue({
        sourcePath: "storedContent",
        field: key,
        rule: "capture_source_field_required",
        message: `Stored capture source requires ${key}.`,
        limit: "non-empty-string",
      }),
    ]);
  }
  return value;
}

function payloadNullableString(
  payload: Record<string, unknown>,
  key: string,
) {
  const value = payload[key];
  return typeof value === "string" ? value : null;
}

function payloadRequiredInteger(
  payload: Record<string, unknown>,
  key: string,
) {
  const value = Number(payload[key]);
  if (!Number.isInteger(value)) {
    throw new AgentPlanCaptureSourceError([
      captureIssue({
        sourcePath: "storedContent",
        field: key,
        rule: "capture_source_integer_required",
        message: `Stored capture source requires integer ${key}.`,
        limit: "integer",
      }),
    ]);
  }
  return value;
}

function payloadNullableNumber(
  payload: Record<string, unknown>,
  key: string,
) {
  const value = payload[key];
  return value === null || value === undefined ? null : Number(value);
}

function requiredImageString(
  image: Record<string, unknown>,
  key: string,
) {
  const value = image[key];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`Stored plan verb receipt requires ${key}.`);
  }
  return value;
}

function nullableImageString(
  image: Record<string, unknown>,
  key: string,
) {
  const value = image[key];
  return typeof value === "string" ? value : null;
}

function requiredImageNumber(
  image: Record<string, unknown>,
  key: string,
) {
  const value = Number(image[key]);
  if (!Number.isInteger(value) || value < 0) {
    throw new Error(`Stored plan verb receipt requires non-negative ${key}.`);
  }
  return value;
}

function unique(values: string[]) {
  return [...new Set(values)];
}
