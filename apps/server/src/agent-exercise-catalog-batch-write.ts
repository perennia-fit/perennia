import { createRoute, z } from "@hono/zod-openapi";
import { and, eq } from "drizzle-orm";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema,
} from "./agent-api-keys.js";
import {
  AgentCatalogUnavailableResponseSchema,
  type AgentCatalogStore,
} from "./agent-catalog.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";
import {
  EXERCISES_SYNC_ENTITY,
  EXERCISE_CATEGORIES_SYNC_ENTITY,
  pushExerciseCategoriesInTransaction,
  pushExercisesInTransaction,
  type SyncPushChange,
} from "./sync.js";

export const AGENT_EXERCISE_CATALOG_BATCH_WRITE_MAX_EXERCISES = 50;
export const AGENT_EXERCISE_CATALOG_BATCH_WRITE_MAX_CATEGORIES = 50;

const ISO8601StringSchema = z.string().min(1).openapi({
  description: "ISO-8601 timestamp.",
});

const AgentExerciseCatalogDimensionIdSchema = z
  .enum(["load", "reps", "duration", "distance"])
  .openapi("AgentExerciseCatalogDimensionId");

const AgentExerciseCatalogLoadModeSchema = z
  .enum(["added", "assisted"])
  .openapi("AgentExerciseCatalogLoadMode");

const AgentExerciseCatalogRecordProfileSchema = z
  .enum([
    "repMax",
    "maxLoad",
    "maxReps",
    "maxDuration",
    "minDuration",
    "maxDistance",
    "fastestPace",
    "minAssistancePerRepCount",
    "completionStreak",
  ])
  .openapi("AgentExerciseCatalogRecordProfile");

// A batch-write category item is either a client-supplied new Category (no
// categoryId — resolved by name, creating one if none matches) or a reference
// to an existing Category by id. This is the "create-or-reference" contract
// the acceptance criteria call for.
export const AgentExerciseCatalogBatchWriteCategorySchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "Client-supplied UUIDv7 Category id.",
    }),
    name: z.string().trim().min(1).openapi({
      description: "User-visible Category name.",
    }),
    sortOrder: z.number().int().default(0),
    colorHex: z.string().trim().min(1).default("#607D8B"),
    updatedAt: ISO8601StringSchema.optional().openapi({
      description:
        "Client-observed row update clock. Defaults to the server receive time when omitted.",
    }),
    deletedAt: ISO8601StringSchema.nullable().default(null).openapi({
      description:
        "Set to archive the Category. Archiving keeps referencing Exercise history intact.",
    }),
  })
  .openapi("AgentExerciseCatalogBatchWriteCategory");

export const AgentExerciseCatalogBatchWriteExerciseSchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "Client-supplied UUIDv7 Exercise id.",
    }),
    name: z.string().trim().min(1).openapi({
      description: "User-visible Exercise name.",
    }),
    categoryId: z.string().min(1).nullable().default(null).openapi({
      description:
        "Category id to file this Exercise under. Must reference a Category created earlier in this same batch or an existing caller-visible Category.",
    }),
    dimensions: z
      .array(AgentExerciseCatalogDimensionIdSchema)
      .max(4)
      .default([])
      .openapi({
        description:
          "Exercise Type dimension set, drawn from the curated registry. Any subset is valid, including none (completion-only).",
      }),
    defaultLoadUnit: z.string().trim().min(1).default("kilogram"),
    loadMode: AgentExerciseCatalogLoadModeSchema.default("added"),
    recordProfile: AgentExerciseCatalogRecordProfileSchema.optional().openapi({
      description:
        "Headline Record Profile. Defaults from the dimension set when omitted.",
    }),
    isUnilateral: z.boolean().default(false),
    usesRpe: z.boolean().default(false),
    isFavorite: z.boolean().default(false),
    equipment: z.array(z.string().min(1)).default([]),
    notes: z.string().nullable().default(null),
    customizesExerciseId: z.string().min(1).nullable().default(null).openapi({
      description:
        "Set when this write customizes (shadows) a Platform Library exercise, mirroring the app's customize flow. The platform row is never mutated; this creates/updates the shadowing User Library row.",
    }),
    updatedAt: ISO8601StringSchema.optional().openapi({
      description:
        "Client-observed row update clock. Defaults to the server receive time when omitted.",
    }),
    deletedAt: ISO8601StringSchema.nullable().default(null).openapi({
      description:
        "Set to archive (never purge) the Exercise. Sets that reference it keep their history.",
    }),
  })
  .openapi("AgentExerciseCatalogBatchWriteExercise");

export const AgentExerciseCatalogBatchWriteRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200).openapi({
      description:
        "Stable key for this agent request. Replays with the same key do not append another Activity Log batch.",
    }),
    categories: z
      .array(AgentExerciseCatalogBatchWriteCategorySchema)
      .max(AGENT_EXERCISE_CATALOG_BATCH_WRITE_MAX_CATEGORIES)
      .default([])
      .openapi({
        description:
          "Categories to create, edit, or archive before Exercises in this same batch.",
      }),
    exercises: z
      .array(AgentExerciseCatalogBatchWriteExerciseSchema)
      .max(AGENT_EXERCISE_CATALOG_BATCH_WRITE_MAX_EXERCISES)
      .default([])
      .openapi({
        description:
          "User Library Exercises to create, edit, archive, restore, or favorite.",
      }),
  })
  .refine(
    (request) => request.categories.length + request.exercises.length > 0,
    {
      message:
        "A batch must include at least one Category or Exercise.",
    },
  )
  .openapi("AgentExerciseCatalogBatchWriteRequest");

export const AgentExerciseCatalogBatchWriteIssueSchema = z
  .object({
    field: z.string().min(1),
    rule: z.string().min(1),
    message: z.string().min(1),
    itemIndex: z.number().int().min(0),
    categoryId: z.string().min(1).nullable(),
    exerciseId: z.string().min(1).nullable(),
  })
  .openapi("AgentExerciseCatalogBatchWriteIssue");

const AgentExerciseCatalogBatchWriteCategoryResultSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1),
    applied: z.boolean(),
    outcome: z.enum(["applied", "superseded", "duplicate"]),
  })
  .openapi("AgentExerciseCatalogBatchWriteCategoryResult");

const AgentExerciseCatalogBatchWriteExerciseResultSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1),
    library: z.literal("user"),
    applied: z.boolean(),
    outcome: z.enum(["applied", "superseded", "duplicate"]),
  })
  .openapi("AgentExerciseCatalogBatchWriteExerciseResult");

export const AgentExerciseCatalogBatchWriteResponseSchema = z
  .object({
    accepted: z.literal(true),
    duplicate: z.boolean(),
    idempotencyKey: z.string().min(1),
    batchId: z.string().min(1),
    serverClock: z.string().min(1),
    categories: z.array(AgentExerciseCatalogBatchWriteCategoryResultSchema),
    exercises: z.array(AgentExerciseCatalogBatchWriteExerciseResultSchema),
  })
  .openapi("AgentExerciseCatalogBatchWriteResponse");

export const AgentExerciseCatalogBatchWriteErrorResponseSchema = z
  .object({
    code: z.literal("agent_exercise_catalog_batch_write_failed"),
    message: z.string().min(1),
    errors: z.array(AgentExerciseCatalogBatchWriteIssueSchema),
    warnings: z.array(AgentExerciseCatalogBatchWriteIssueSchema),
  })
  .openapi("AgentExerciseCatalogBatchWriteErrorResponse");

export const AgentExerciseCatalogBatchWriteUnavailableResponseSchema = z
  .object({
    code: z.literal("agent_exercise_catalog_batch_write_unavailable"),
    message: z.string().min(1),
  })
  .openapi("AgentExerciseCatalogBatchWriteUnavailableResponse");

export const agentExerciseCatalogBatchWriteRoute = createRoute({
  method: "post",
  path: "/agent/exercises/batch-write",
  operationId: "batchWriteAgentExerciseCatalog",
  tags: ["Agent Writes"],
  summary:
    "Batch-write User Library Exercises and Categories as one Activity Log batch.",
  description:
    "Authenticated agent write path for the User Library only. Creates, edits, archives, restores, and favorites Exercises, and creates, edits, and archives Categories, in one idempotent batch. Payload shape matches the synced row payloads so devices pull agent writes as ordinary edits. Platform Library rows are never mutable through this op; customizing a Platform exercise creates the shadowing User Library row exactly like the app.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: AgentExerciseCatalogBatchWriteRequestSchema,
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
          schema: AgentExerciseCatalogBatchWriteResponseSchema,
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
        "One or more Categories or Exercises failed hard validation; no rows were written.",
      content: {
        "application/json": {
          schema: AgentExerciseCatalogBatchWriteErrorResponseSchema,
        },
      },
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key or Exercise catalog storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentCatalogUnavailableResponseSchema,
            AgentExerciseCatalogBatchWriteUnavailableResponseSchema,
          ]),
        },
      },
    },
  },
});

export type AgentExerciseCatalogBatchWriteRequest = z.infer<
  typeof AgentExerciseCatalogBatchWriteRequestSchema
>;
export type AgentExerciseCatalogBatchWriteIssue = z.infer<
  typeof AgentExerciseCatalogBatchWriteIssueSchema
>;
export type AgentExerciseCatalogBatchWriteResponse = z.infer<
  typeof AgentExerciseCatalogBatchWriteResponseSchema
>;

type PreparedCategory = {
  id: string;
  updatedAt: string;
  deletedAt: string | null;
  payload: Record<string, unknown>;
  result: z.infer<typeof AgentExerciseCatalogBatchWriteCategoryResultSchema>;
};

type PreparedExercise = {
  id: string;
  updatedAt: string;
  deletedAt: string | null;
  payload: Record<string, unknown>;
  result: z.infer<typeof AgentExerciseCatalogBatchWriteExerciseResultSchema>;
};

export type AgentExerciseCatalogBatchPreparation =
  | {
      accepted: true;
      categories: PreparedCategory[];
      exercises: PreparedExercise[];
      responseCategories: z.infer<
        typeof AgentExerciseCatalogBatchWriteCategoryResultSchema
      >[];
      responseExercises: z.infer<
        typeof AgentExerciseCatalogBatchWriteExerciseResultSchema
      >[];
    }
  | {
      accepted: false;
      errors: AgentExerciseCatalogBatchWriteIssue[];
      warnings: AgentExerciseCatalogBatchWriteIssue[];
    };

export type AgentExerciseCatalogBatchWriteStore = {
  writeExerciseCatalogBatch(input: {
    userId: string;
    batchId: string;
    correlationId?: string;
    deviceId: string;
    categories: PreparedCategory[];
    exercises: PreparedExercise[];
  }): Promise<{
    duplicate: boolean;
    serverClock: string;
    applied: { id: string; updatedAt: string; deviceId: string }[];
  }>;
};

// Mirrors the app's defaultRecordProfileFor(training_dimensions.dart) /
// agent-catalog.ts's defaultRecordProfileForDimensions so an agent-created
// Exercise gets the same default headline record the app would assign.
function defaultRecordProfileForDimensions(
  dimensions: readonly string[],
): z.infer<typeof AgentExerciseCatalogRecordProfileSchema> {
  const has = (dimension: string) => dimensions.includes(dimension);
  if (dimensions.length === 0) {
    return "completionStreak";
  }
  if (has("load") && has("reps")) {
    return "repMax";
  }
  if (has("reps")) {
    return "maxReps";
  }
  if (has("distance") && has("duration")) {
    return "fastestPace";
  }
  if (has("duration")) {
    return "maxDuration";
  }
  if (has("distance")) {
    return "maxDistance";
  }
  if (has("load")) {
    return "maxLoad";
  }
  return "completionStreak";
}

export async function prepareAgentExerciseCatalogBatchWrite({
  catalogStore,
  request,
  userId,
  now = new Date(),
}: {
  catalogStore: AgentCatalogStore;
  request: AgentExerciseCatalogBatchWriteRequest;
  userId: string;
  now?: Date;
}): Promise<AgentExerciseCatalogBatchPreparation> {
  const errors: AgentExerciseCatalogBatchWriteIssue[] = [];
  const warnings: AgentExerciseCatalogBatchWriteIssue[] = [];
  const seenCategoryIds = new Set<string>();
  const seenExerciseIds = new Set<string>();
  const preparedCategories: PreparedCategory[] = [];
  const preparedExercises: PreparedExercise[] = [];

  // Category ids created earlier in this same batch are valid exercise
  // category references even though they are not yet persisted.
  const batchCategoryIds = new Set(
    request.categories.map((category) => category.id),
  );

  for (const [itemIndex, category] of request.categories.entries()) {
    if (seenCategoryIds.has(category.id)) {
      errors.push(
        categoryIssue({
          field: `categories[${itemIndex}].id`,
          itemIndex,
          categoryId: category.id,
          rule: "duplicate_category_id",
          message: "A Category id may appear only once per batch.",
        }),
      );
      continue;
    }
    seenCategoryIds.add(category.id);

    const updatedAt = category.updatedAt ?? now.toISOString();
    const payload: Record<string, unknown> = {
      id: category.id,
      name: category.name,
      sort_order: category.sortOrder,
      color_hex: category.colorHex,
      updated_at: updatedAt,
      deleted_at: category.deletedAt,
    };

    preparedCategories.push({
      id: category.id,
      updatedAt,
      deletedAt: category.deletedAt,
      payload,
      result: AgentExerciseCatalogBatchWriteCategoryResultSchema.parse({
        id: category.id,
        name: category.name,
        applied: true,
        outcome: "applied",
      }),
    });
  }

  for (const [itemIndex, item] of request.exercises.entries()) {
    if (seenExerciseIds.has(item.id)) {
      errors.push(
        exerciseIssue({
          field: `exercises[${itemIndex}].id`,
          itemIndex,
          exerciseId: item.id,
          rule: "duplicate_exercise_id",
          message: "An Exercise id may appear only once per batch.",
        }),
      );
      continue;
    }
    seenExerciseIds.add(item.id);

    let categoryName = "";
    if (item.categoryId !== null) {
      if (batchCategoryIds.has(item.categoryId)) {
        const batchCategory = request.categories.find(
          (category) => category.id === item.categoryId,
        );
        categoryName = batchCategory?.name ?? "";
      } else {
        const existingCategory = await catalogStore.getCategoryById({
          userId,
          categoryId: item.categoryId,
        });
        if (existingCategory === null) {
          errors.push(
            exerciseIssue({
              field: `exercises[${itemIndex}].categoryId`,
              itemIndex,
              exerciseId: item.id,
              rule: "category_not_found",
              message:
                "categoryId must reference a Category created earlier in this batch or visible to the authenticated account.",
            }),
          );
          continue;
        }
        categoryName = existingCategory.name;
      }
    }

    let customizedPlatformExercise: Awaited<
      ReturnType<AgentCatalogStore["getExerciseById"]>
    > = null;
    if (item.customizesExerciseId !== null) {
      customizedPlatformExercise = await catalogStore.getExerciseById({
        userId,
        exerciseId: item.customizesExerciseId,
      });
      if (
        customizedPlatformExercise === null ||
        customizedPlatformExercise.library !== "platform"
      ) {
        errors.push(
          exerciseIssue({
            field: `exercises[${itemIndex}].customizesExerciseId`,
            itemIndex,
            exerciseId: item.id,
            rule: "customized_exercise_not_platform",
            message:
              "customizesExerciseId must reference an active Platform Library exercise.",
          }),
        );
        continue;
      }
    }

    const recordProfile =
      item.recordProfile ?? defaultRecordProfileForDimensions(item.dimensions);
    const updatedAt = item.updatedAt ?? now.toISOString();
    const payload: Record<string, unknown> = {
      id: item.id,
      library_origin: "user",
      name: item.name,
      dimension_ids: JSON.stringify(item.dimensions),
      default_load_unit: item.defaultLoadUnit,
      load_mode: item.loadMode,
      record_profile: recordProfile,
      is_favorite: item.isFavorite,
      is_unilateral: item.isUnilateral,
      uses_rpe: item.usesRpe,
      category_id: item.categoryId,
      equipment_ids: JSON.stringify(item.equipment),
      notes: item.notes,
      updated_at: updatedAt,
      deleted_at: item.deletedAt,
    };

    preparedExercises.push({
      id: item.id,
      updatedAt,
      deletedAt: item.deletedAt,
      payload,
      result: AgentExerciseCatalogBatchWriteExerciseResultSchema.parse({
        id: item.id,
        name: item.name,
        library: "user",
        applied: true,
        outcome: "applied",
      }),
    });
    // categoryName is read above purely to hard-validate the reference;
    // the payload does not carry a denormalized category name (the app's
    // own exercise row payload doesn't either — category name resolution
    // happens at read time via the category_id join, exactly as
    // agent-catalog.ts's createDrizzleAgentCatalogStore does).
    void categoryName;
  }

  if (errors.length > 0) {
    return { accepted: false, errors, warnings };
  }

  return {
    accepted: true,
    categories: preparedCategories,
    exercises: preparedExercises,
    responseCategories: preparedCategories.map((category) => category.result),
    responseExercises: preparedExercises.map((exercise) => exercise.result),
  };
}

export function createDrizzleAgentExerciseCatalogBatchWriteStore(
  db: ServerDatabase,
): AgentExerciseCatalogBatchWriteStore {
  return {
    async writeExerciseCatalogBatch({
      userId,
      batchId,
      deviceId,
      categories,
      exercises,
    }) {
      const serverClock = new Date();

      return db.transaction(async (transaction) => {
        const existingBatchRows = await transaction
          .select({ id: schema.activityLog.id })
          .from(schema.activityLog)
          .where(
            and(
              eq(schema.activityLog.userId, userId),
              eq(schema.activityLog.actor, "agent"),
              eq(schema.activityLog.batchId, batchId),
            ),
          )
          .limit(1);

        if (existingBatchRows.length > 0) {
          return {
            duplicate: true,
            serverClock: serverClock.toISOString(),
            applied: [],
          };
        }

        const categoryChanges: SyncPushChange[] = [];
        for (const category of categories) {
          const beforeImage = await readBeforeImage({
            transaction,
            userId,
            table: schema.exerciseCategories,
            id: category.id,
          });
          categoryChanges.push({
            id: category.id,
            payload: category.payload,
            updatedAt: category.updatedAt,
            deletedAt: category.deletedAt,
            activityLogId: `agent:${batchId}:category:${category.id}`,
            actor: "agent",
            batchId,
            beforeImage,
            afterImage: category.payload,
            occurredAt: category.updatedAt,
          });
        }

        const exerciseChanges: SyncPushChange[] = [];
        for (const exercise of exercises) {
          const beforeImage = await readBeforeImage({
            transaction,
            userId,
            table: schema.exercises,
            id: exercise.id,
          });
          exerciseChanges.push({
            id: exercise.id,
            payload: exercise.payload,
            updatedAt: exercise.updatedAt,
            deletedAt: exercise.deletedAt,
            activityLogId: `agent:${batchId}:exercise:${exercise.id}`,
            actor: "agent",
            batchId,
            beforeImage,
            afterImage: exercise.payload,
            occurredAt: exercise.updatedAt,
          });
        }

        const categoryResult = await pushExerciseCategoriesInTransaction(
          transaction,
          {
            userId,
            deviceId,
            changes: categoryChanges,
            serverClock,
          },
        );
        const exerciseResult = await pushExercisesInTransaction(transaction, {
          userId,
          deviceId,
          changes: exerciseChanges,
          serverClock,
        });

        return {
          duplicate: false,
          serverClock: serverClock.toISOString(),
          applied: [...categoryResult.applied, ...exerciseResult.applied],
        };
      });
    },
  };
}

async function readBeforeImage({
  transaction,
  userId,
  table,
  id,
}: {
  transaction: Pick<ServerDatabase, "select">;
  userId: string;
  table: typeof schema.exercises | typeof schema.exerciseCategories;
  id: string;
}) {
  const existingRows = await transaction
    .select({
      userId: table.userId,
      payload: table.payload,
    })
    .from(table)
    .where(eq(table.id, id))
    .limit(1);
  const existing = existingRows[0];
  if (existing === undefined || existing.userId !== userId) {
    return null;
  }

  return existing.payload;
}

function categoryIssue({
  field,
  itemIndex,
  categoryId,
  rule,
  message,
}: {
  field: string;
  itemIndex: number;
  categoryId: string;
  rule: string;
  message: string;
}): AgentExerciseCatalogBatchWriteIssue {
  return AgentExerciseCatalogBatchWriteIssueSchema.parse({
    field,
    rule,
    message,
    itemIndex,
    categoryId,
    exerciseId: null,
  });
}

function exerciseIssue({
  field,
  itemIndex,
  exerciseId,
  rule,
  message,
}: {
  field: string;
  itemIndex: number;
  exerciseId: string;
  rule: string;
  message: string;
}): AgentExerciseCatalogBatchWriteIssue {
  return AgentExerciseCatalogBatchWriteIssueSchema.parse({
    field,
    rule,
    message,
    itemIndex,
    categoryId: null,
    exerciseId,
  });
}

export {
  EXERCISES_SYNC_ENTITY as AGENT_EXERCISE_CATALOG_EXERCISES_ENTITY,
  EXERCISE_CATEGORIES_SYNC_ENTITY as AGENT_EXERCISE_CATALOG_CATEGORIES_ENTITY,
};
