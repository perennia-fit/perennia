import { createRoute, z } from "@hono/zod-openapi";
import { and, eq, isNull } from "drizzle-orm";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema,
} from "./agent-api-keys.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";
import type {
  DimensionId,
  ExerciseLoadMode,
  RecordProfile,
} from "./analytics/exercise-analytics.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import {
  PLATFORM_EXERCISE_SEED_CATEGORIES,
  PLATFORM_EXERCISE_SEED_EXERCISES,
  PLATFORM_EXERCISE_SEED_FOCUSES,
  PLATFORM_EXERCISE_SEED_REDIRECTS,
} from "./data/platform-exercise-seed.generated.js";

export const AGENT_EXERCISE_DEFAULT_PAGE_LIMIT = 50;
export const AGENT_EXERCISE_MAX_PAGE_LIMIT = 100;
export const AGENT_EXERCISE_DEFAULT_CANDIDATE_LIMIT = 8;
export const AGENT_EXERCISE_MAX_CANDIDATE_LIMIT = 20;

const AGENT_EXERCISE_LIST_FIELDS = [
  "id",
  "name",
  "library",
  "category",
  "dimensions",
  "equipment",
  "focusIds",
  "loadMode",
  "recordProfile",
  "favorite",
  "active",
  "shadowedPlatformExerciseId",
] as const;

const AGENT_EXERCISE_DEFAULT_LIST_FIELDS = [
  "id",
  "name",
  "library",
  "category",
  "dimensions",
  "equipment",
  "focusIds",
  "loadMode",
  "recordProfile",
  "favorite",
  "active",
] as const;

const AgentExerciseLibrarySchema = z
  .enum(["user", "platform"])
  .openapi("AgentExerciseLibrary");

const AgentExerciseDimensionIdSchema = z
  .enum(["load", "reps", "duration", "distance"])
  .openapi("AgentExerciseDimensionId");

const AgentExerciseLoadModeSchema = z
  .enum(["added", "assisted"])
  .openapi("AgentExerciseLoadMode");

const AgentExerciseRecordProfileSchema = z
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
  .openapi("AgentExerciseRecordProfile");

export const AgentExerciseCategorySchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "Stable Category id.",
    }),
    name: z.string().min(1).openapi({
      description: "User-visible Category name.",
    }),
  })
  .openapi("AgentExerciseCategory");

// Category is optional on an Exercise: the app's `Exercises.categoryId` is
// nullable and agent batch-write accepts `categoryId: null`, so the catalog
// projects "no Category" as null rather than rejecting the row (which used to
// fail the whole listing with a 500).
const NullableAgentExerciseCategorySchema = z
  .union([AgentExerciseCategorySchema, z.null()])
  .openapi("NullableAgentExerciseCategory");

export const AgentFocusSchema = z
  .object({
    id: z.string().min(1).openapi({
      description:
        "Stable Focus id. Starter Focus ids are fixed and identical on every device.",
    }),
    name: z.string().min(1).openapi({
      description: "User-visible Focus name, after any rename by the user.",
    }),
    sortOrder: z.number().int().openapi({
      description: "User-defined display order; lower sorts first.",
    }),
    starter: z.boolean().openapi({
      description:
        "True for one of Perennia's starter Focuses (possibly renamed or reordered by the user); false for a Focus the user created.",
    }),
  })
  .openapi("AgentFocus");

export const AgentFocusListResponseSchema = z
  .object({
    focuses: z.array(AgentFocusSchema).openapi({
      description:
        "The caller's active Focuses in display order: the starter set merged with the user's own rows. Archived Focuses are omitted.",
    }),
  })
  .openapi("AgentFocusListResponse");

export const AgentExerciseSchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "Stable Exercise id to use in agent writes.",
    }),
    library: AgentExerciseLibrarySchema.openapi({
      description:
        "Library origin after User Library over Platform Library shadowing.",
    }),
    name: z.string().min(1).openapi({
      description: "User-visible Exercise name.",
    }),
    category: NullableAgentExerciseCategorySchema.openapi({
      description: "Exercise Category label, or null when the exercise has no Category.",
    }),
    dimensions: z.array(AgentExerciseDimensionIdSchema).max(4).openapi({
      description: "Exercise Type dimension set used for set entry.",
    }),
    equipment: z.array(z.string().min(1)).openapi({
      description:
        "Structured Equipment ids associated with the exercise. Empty when none is known.",
    }),
    // Defaulted so an Exercise projection built before Focus existed (or by
    // a store that does not know it) still parses as "belongs to none".
    focusIds: z.array(z.string().min(1)).default([]).openapi({
      description:
        "Ids of the Focuses this Exercise belongs to (see GET /agent/focuses). Empty when it belongs to none. Ids may name an archived Focus; history is never rewritten.",
    }),
    loadMode: AgentExerciseLoadModeSchema.openapi({
      description: "Per-exercise load semantics.",
    }),
    recordProfile: AgentExerciseRecordProfileSchema.openapi({
      description: "Headline Record Profile for this exercise.",
    }),
    favorite: z.boolean().openapi({
      description: "True when the user has marked the exercise as a favorite.",
    }),
    active: z.boolean().openapi({
      description: "True when the exercise is not archived.",
    }),
    shadowedPlatformExerciseId: z.string().min(1).nullable().openapi({
      description:
        "Platform Exercise id hidden by this User Library exercise, when known.",
    }),
  })
  .openapi("AgentExercise");

export const AgentExerciseListFieldSchema = z
  .enum(AGENT_EXERCISE_LIST_FIELDS)
  .openapi("AgentExerciseListField");

export const AgentExerciseListItemSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1),
    library: AgentExerciseLibrarySchema.optional(),
    category: NullableAgentExerciseCategorySchema.optional(),
    dimensions: z.array(AgentExerciseDimensionIdSchema).max(4).optional(),
    equipment: z.array(z.string().min(1)).optional(),
    focusIds: z.array(z.string().min(1)).optional(),
    loadMode: AgentExerciseLoadModeSchema.optional(),
    recordProfile: AgentExerciseRecordProfileSchema.optional(),
    favorite: z.boolean().optional(),
    active: z.boolean().optional(),
    shadowedPlatformExerciseId: z.string().min(1).nullable().optional(),
  })
  .openapi("AgentExerciseListItem");

const NullableAgentExerciseSchema = z
  .union([AgentExerciseSchema, z.null()])
  .openapi("NullableAgentExercise");

export const AgentExerciseListResponseSchema = z
  .object({
    exercises: z.array(AgentExerciseListItemSchema),
    limit: z.number().int().min(1).max(AGENT_EXERCISE_MAX_PAGE_LIMIT),
    nextCursor: z.string().min(1).nullable(),
    fields: z.array(AgentExerciseListFieldSchema),
  })
  .openapi("AgentExerciseListResponse");

const AgentExerciseResolutionSchema = z
  .enum(["matched", "ambiguous", "not_found"])
  .openapi("AgentExerciseResolution");

export const AgentExerciseResolveGuidanceSchema = z
  .object({
    op: z.literal("POST /agent/exercises/batch-write").openapi({
      description:
        "The batch-write operation a code-mode script should call next.",
    }),
    message: z.string().min(1).openapi({
      description:
        "Human/agent-readable next step: create the Exercise (not_found) or disambiguate by id (ambiguous), then retry the original write.",
    }),
  })
  .openapi("AgentExerciseResolveGuidance");

const NullableAgentExerciseResolveGuidanceSchema = z
  .union([AgentExerciseResolveGuidanceSchema, z.null()])
  .openapi("NullableAgentExerciseResolveGuidance");

export const AgentExerciseResolveResponseSchema = z
  .object({
    query: z.string().min(1),
    resolution: AgentExerciseResolutionSchema,
    matchedExercise: NullableAgentExerciseSchema,
    candidates: z.array(AgentExerciseSchema).openapi({
      description:
        "Suggested resolvable exercises when the query is ambiguous or not an exact match.",
    }),
    guidance: NullableAgentExerciseResolveGuidanceSchema.openapi({
      description:
        "Machine-actionable next step for not_found/ambiguous resolutions, pointing at POST /agent/exercises/batch-write so a code-mode script can create-then-log in one program. Null when resolution is matched.",
    }),
  })
  .openapi("AgentExerciseResolveResponse");

export const AgentCatalogUnavailableResponseSchema = z
  .object({
    code: z.literal("agent_catalog_unavailable").openapi({
      description:
        "Returned by app instances that have no AgentCatalogStore configured.",
    }),
    message: z.string().min(1).openapi({
      description:
        "Human-readable explanation that the agent Exercise catalog data source is unavailable.",
    }),
  })
  .openapi("AgentCatalogUnavailableResponse");

const fieldSet = new Set<string>(AGENT_EXERCISE_LIST_FIELDS);

export const AgentExerciseListQuerySchema = z.object({
  search: z
    .string()
    .trim()
    .min(1)
    .optional()
    .openapi({
      param: {
        name: "search",
        in: "query",
      },
      description: "Optional case-insensitive search term for Exercise names.",
    }),
  category: z
    .string()
    .trim()
    .min(1)
    .optional()
    .openapi({
      param: {
        name: "category",
        in: "query",
      },
      description:
        "Optional Category id or name filter. Category colors are presentation-only and not part of this response.",
    }),
  focus: z
    .string()
    .trim()
    .min(1)
    .optional()
    .openapi({
      param: {
        name: "focus",
        in: "query",
      },
      description:
        "Optional Focus id or name filter (see GET /agent/focuses). Keeps exercises that belong to that Focus.",
    }),
  favorite: z
    .enum(["true", "false"])
    .optional()
    .openapi({
      param: {
        name: "favorite",
        in: "query",
      },
      description: "Optional favorite filter.",
    }),
  activeOnly: z
    .enum(["true", "false"])
    .default("true")
    .openapi({
      param: {
        name: "activeOnly",
        in: "query",
      },
      description:
        "When true, archived exercises are excluded. Defaults to true for picker-like agent reads.",
    }),
  limit: z.coerce
    .number()
    .int()
    .min(1)
    .max(AGENT_EXERCISE_MAX_PAGE_LIMIT)
    .default(AGENT_EXERCISE_DEFAULT_PAGE_LIMIT)
    .openapi({
      param: {
        name: "limit",
        in: "query",
      },
      description: "Maximum number of exercises to return, bounded to 100.",
    }),
  cursor: z
    .string()
    .trim()
    .min(1)
    .optional()
    .openapi({
      param: {
        name: "cursor",
        in: "query",
      },
      description: "Opaque pagination cursor returned by the previous page.",
    }),
  fields: z
    .string()
    .trim()
    .min(1)
    .optional()
    .refine(
      (value) =>
        value === undefined ||
        value
          .split(",")
          .map((field) => field.trim())
          .every((field) => fieldSet.has(field)),
      "fields must be a comma-separated list of known exercise fields",
    )
    .openapi({
      param: {
        name: "fields",
        in: "query",
      },
      description:
        "Comma-separated list of additional fields. id and name are always returned.",
    }),
});

export const AgentExerciseResolveQuerySchema = z.object({
  name: z
    .string()
    .trim()
    .min(1)
    .openapi({
      param: {
        name: "name",
        in: "query",
      },
      description: "Free-text Exercise name to resolve.",
    }),
  candidateLimit: z.coerce
    .number()
    .int()
    .min(0)
    .max(AGENT_EXERCISE_MAX_CANDIDATE_LIMIT)
    .default(AGENT_EXERCISE_DEFAULT_CANDIDATE_LIMIT)
    .openapi({
      param: {
        name: "candidateLimit",
        in: "query",
      },
      description: "Maximum number of candidate suggestions to return.",
    }),
});

export const agentExerciseListRoute = createRoute({
  method: "get",
  path: "/agent/exercises",
  operationId: "listAgentExercises",
  tags: ["Agent Catalog"],
  summary: "List the caller's resolvable Exercise catalog.",
  description:
    "Store-gated slice of the agent catalog read surface. App instances without a configured AgentCatalogStore return 503 agent_catalog_unavailable; the production server wires a DB-backed AgentCatalogStore over the synced Exercise rows and the bundled Platform Library.",
  security: [{ bearerAuth: [] }],
  request: {
    query: AgentExerciseListQuerySchema,
  },
  responses: {
    200: {
      description:
        "A bounded page of exercises after User Library over Platform Library shadowing.",
      content: {
        "application/json": {
          schema: AgentExerciseListResponseSchema,
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
    429: RateLimitExceededOpenApiResponse,
    503: {
      description:
        "Agent catalog storage or API key storage is not configured. Instances without a wired AgentCatalogStore return agent_catalog_unavailable.",
      content: {
        "application/json": {
          schema: z.union([
            AgentCatalogUnavailableResponseSchema,
            AgentApiKeyUnavailableResponseSchema,
          ]),
        },
      },
    },
  },
});

export const agentExerciseResolveRoute = createRoute({
  method: "get",
  path: "/agent/exercises/resolve",
  operationId: "resolveAgentExerciseName",
  tags: ["Agent Catalog"],
  summary: "Resolve a free-text Exercise name for the caller.",
  description:
    "Store-gated slice of the agent catalog read surface. App instances without a configured AgentCatalogStore return 503 agent_catalog_unavailable; the production server wires a DB-backed AgentCatalogStore over the synced Exercise rows and the bundled Platform Library.",
  security: [{ bearerAuth: [] }],
  request: {
    query: AgentExerciseResolveQuerySchema,
  },
  responses: {
    200: {
      description:
        "The exact match, or candidates when the name is ambiguous or not an exact match.",
      content: {
        "application/json": {
          schema: AgentExerciseResolveResponseSchema,
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
    429: RateLimitExceededOpenApiResponse,
    503: {
      description:
        "Agent catalog storage or API key storage is not configured. Instances without a wired AgentCatalogStore return agent_catalog_unavailable.",
      content: {
        "application/json": {
          schema: z.union([
            AgentCatalogUnavailableResponseSchema,
            AgentApiKeyUnavailableResponseSchema,
          ]),
        },
      },
    },
  },
});

export const agentFocusListRoute = createRoute({
  method: "get",
  path: "/agent/focuses",
  operationId: "listAgentFocuses",
  tags: ["Agent Catalog"],
  summary: "List the caller's Focuses.",
  description:
    "A Focus is the training discipline a Workout is performed under (Weights, Endurance, Functional, Calisthenics, Mobility, plus any the user created). Returns the starter set merged with the user's synced Focus rows: a user row sharing a starter id carries the user's rename/reorder, and archived Focuses are omitted. Use these ids for `focusId` on Workout and Workout Template writes, `focusIds` on Exercise writes, and the `focus` filter on GET /agent/exercises.",
  security: [{ bearerAuth: [] }],
  responses: {
    200: {
      description: "The caller's active Focuses in display order.",
      content: {
        "application/json": {
          schema: AgentFocusListResponseSchema,
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
    429: RateLimitExceededOpenApiResponse,
    503: {
      description:
        "Agent catalog storage or API key storage is not configured. Instances without a wired AgentCatalogStore return agent_catalog_unavailable.",
      content: {
        "application/json": {
          schema: z.union([
            AgentCatalogUnavailableResponseSchema,
            AgentApiKeyUnavailableResponseSchema,
          ]),
        },
      },
    },
  },
});

export type AgentExerciseListField = z.infer<
  typeof AgentExerciseListFieldSchema
>;
export type AgentExercise = z.infer<typeof AgentExerciseSchema>;
export type AgentCatalogExercise = AgentExercise & {
  ownerUserId: string | null;
};
export type AgentExerciseListInput = {
  userId: string;
  search?: string;
  category?: string;
  focus?: string;
  favorite?: boolean;
  activeOnly: boolean;
  limit: number;
  cursor?: string;
  fields: AgentExerciseListField[];
};
export type AgentExerciseListResponse = z.infer<
  typeof AgentExerciseListResponseSchema
>;
export type AgentExerciseResolveInput = {
  userId: string;
  name: string;
  candidateLimit: number;
};
export type AgentExerciseResolveResponse = z.infer<
  typeof AgentExerciseResolveResponseSchema
>;
export type AgentExerciseGetInput = {
  userId: string;
  exerciseId: string;
};
export type AgentExercisesGetInput = {
  userId: string;
  exerciseIds: string[];
  /**
   * Also return a Platform exercise that a same-named active User Library
   * exercise hides. The Progress reads set it: the app still counts such an
   * exercise as active, since its row there is not deleted.
   */
  includeShadowed?: boolean;
};
export type AgentCatalogCategory = {
  id: string;
  name: string;
};
export type AgentCategoryGetInput = {
  userId: string;
  categoryId: string;
};
export type AgentFocus = z.infer<typeof AgentFocusSchema>;
export type AgentFocusListInput = {
  userId: string;
};
export type AgentCatalogStore = {
  getExerciseById(input: AgentExerciseGetInput): Promise<AgentExercise | null>;
  getExercisesByIds(input: AgentExercisesGetInput): Promise<AgentExercise[]>;
  listExercises(
    input: AgentExerciseListInput,
  ): Promise<AgentExerciseListResponse>;
  resolveExerciseName(
    input: AgentExerciseResolveInput,
  ): Promise<AgentExerciseResolveResponse>;
  // Direct Category lookup by id, independent of whether any Exercise
  // currently references it (a brand-new or otherwise-empty Category is
  // still a valid, caller-visible reference target).
  getCategoryById(
    input: AgentCategoryGetInput,
  ): Promise<AgentCatalogCategory | null>;
  // The caller's active Focuses (starter set merged with their synced rows).
  listFocuses(input: AgentFocusListInput): Promise<AgentFocus[]>;
};

export const FOCUS_NOT_FOUND_RULE = "focus_not_found";

export function focusNotFoundMessage(field: "focusId" | "focusIds"): string {
  return field === "focusId"
    ? "focusId must reference an active Focus visible to the authenticated account (see GET /agent/focuses)."
    : "focusIds must reference active Focuses visible to the authenticated account (see GET /agent/focuses).";
}

// The reference check behind `focus_not_found`, shared by every agent write
// that names a Focus: the id must be one of the caller's active Focuses. A
// starter id resolves without any synced row; a starter or user Focus the
// caller archived does not. The Focus list is loaded at most once per check
// (i.e. per request), and only when a write actually names a Focus.
export function createActiveFocusCheck({
  catalogStore,
  userId,
}: {
  catalogStore: Pick<AgentCatalogStore, "listFocuses">;
  userId: string;
}): (focusId: string) => Promise<boolean> {
  let activeIds: Promise<ReadonlySet<string>> | undefined;
  return async (focusId) => {
    activeIds ??= catalogStore
      .listFocuses({ userId })
      .then((focuses) => new Set(focuses.map((focus) => focus.id)));
    return (await activeIds).has(focusId);
  };
}

// `focus_id` is a soft reference set on a device or by an agent write; rows
// that predate Focus lack it, and anything but a non-empty string reads as
// "no Focus".
export function payloadFocusId(
  payload: Record<string, unknown> | null | undefined,
): string | null {
  const value = payload?.focus_id;
  return typeof value === "string" && value.length > 0 ? value : null;
}

export function parseAgentExerciseListQuery(
  query: z.infer<typeof AgentExerciseListQuerySchema>,
): Omit<AgentExerciseListInput, "userId"> {
  return {
    search: query.search,
    category: query.category,
    focus: query.focus,
    favorite:
      query.favorite === undefined ? undefined : query.favorite === "true",
    activeOnly: query.activeOnly === "true",
    limit: query.limit,
    cursor: query.cursor,
    fields: resolveFieldSelection(query.fields),
  };
}

export type AgentCatalogCategoryFixture = AgentCatalogCategory & {
  ownerUserId: string;
};

// A user's synced Focus row as the catalog sees it: either a Focus they
// created or their rename/reorder/archive of a starter Focus (same id).
export type AgentCatalogFocusRow = {
  id: string;
  name: string;
  sortOrder: number;
  deleted: boolean;
};

export type AgentCatalogFocusFixture = AgentCatalogFocusRow & {
  ownerUserId: string;
};

const STARTER_FOCUS_IDS = new Set(
  PLATFORM_EXERCISE_SEED_FOCUSES.map((focus) => focus.id),
);

export function isStarterFocusId(focusId: string): boolean {
  return STARTER_FOCUS_IDS.has(focusId);
}

// Merges the starter Focuses with a user's own rows exactly as the app's
// seeded table behaves: a user row with a starter id is that starter after the
// user's edits (so it overrides name and order, and a tombstone archives it),
// any other row is a user-created Focus. Archived Focuses are dropped.
export function mergeAgentFocuses(
  userRows: readonly AgentCatalogFocusRow[],
): AgentFocus[] {
  const merged = new Map<string, AgentFocus & { deleted: boolean }>();
  for (const starter of PLATFORM_EXERCISE_SEED_FOCUSES) {
    merged.set(starter.id, {
      id: starter.id,
      name: starter.name,
      sortOrder: starter.sortOrder,
      starter: true,
      deleted: false,
    });
  }
  for (const row of userRows) {
    const starter = merged.get(row.id);
    merged.set(row.id, {
      id: row.id,
      name: row.name.trim().length > 0 ? row.name : (starter?.name ?? row.id),
      sortOrder: row.sortOrder,
      starter: isStarterFocusId(row.id),
      deleted: row.deleted,
    });
  }

  return [...merged.values()]
    .filter((focus) => !focus.deleted)
    .sort(
      (left, right) =>
        left.sortOrder - right.sortOrder ||
        left.name.localeCompare(right.name) ||
        left.id.localeCompare(right.id),
    )
    .map(({ deleted: _deleted, ...focus }) => AgentFocusSchema.parse(focus));
}

export function createInMemoryAgentCatalogStore(
  exercises: readonly AgentCatalogExercise[],
  categories: readonly AgentCatalogCategoryFixture[] = [],
  focuses: readonly AgentCatalogFocusFixture[] = [],
): AgentCatalogStore {
  const focusesForUser = (userId: string) =>
    mergeAgentFocuses(focuses.filter((focus) => focus.ownerUserId === userId));

  return {
    async getExerciseById(input) {
      const resolvedExerciseId = resolvePlatformExerciseId(input.exerciseId);
      const exercise = filterVisibleExercises(exercises, input.userId).find(
        (candidate) => candidate.id === resolvedExerciseId,
      );

      return exercise === undefined ? null : stripOwner(exercise);
    },
    async getExercisesByIds(input) {
      const exerciseIds = new Set(
        input.exerciseIds.map(resolvePlatformExerciseId),
      );
      const candidates =
        input.includeShadowed === true
          ? callerCatalogExercises(exercises, input.userId)
          : filterVisibleExercises(exercises, input.userId);
      return candidates
        .filter((exercise) => exerciseIds.has(exercise.id))
        .map(stripOwner);
    },
    async listExercises(input) {
      const fields = normalizeFieldSelection(input.fields);
      const focusIdKeys =
        input.focus === undefined
          ? undefined
          : resolveFocusFilter(input.focus, focusesForUser(input.userId));
      const visible = filterVisibleExercises(exercises, input.userId)
        .filter((exercise) => (input.activeOnly ? exercise.active : true))
        .filter((exercise) => matchesSearch(exercise, input.search))
        .filter((exercise) => matchesCategory(exercise, input.category))
        .filter((exercise) => matchesFocus(exercise, focusIdKeys))
        .filter((exercise) =>
          input.favorite === undefined
            ? true
            : exercise.favorite === input.favorite,
        );
      const offset = parseCursor(input.cursor);
      const page = visible.slice(offset, offset + input.limit);
      const nextOffset = offset + input.limit;

      return AgentExerciseListResponseSchema.parse({
        exercises: page.map((exercise) => projectExercise(exercise, fields)),
        limit: input.limit,
        nextCursor: nextOffset < visible.length ? String(nextOffset) : null,
        fields,
      });
    },
    async resolveExerciseName(input) {
      const query = input.name.trim();
      const queryKey = normalizeName(query);
      const visible = filterVisibleExercises(exercises, input.userId).filter(
        (exercise) => exercise.active,
      );
      const exactUserMatches = visible.filter(
        (exercise) =>
          exercise.library === "user" &&
          normalizeName(exercise.name) === queryKey,
      );
      if (exactUserMatches.length === 1) {
        return resolveMatched(query, exactUserMatches[0]);
      }
      if (exactUserMatches.length > 1) {
        return resolveAmbiguous(query, exactUserMatches, input.candidateLimit);
      }

      const exactPlatformMatches = visible.filter(
        (exercise) =>
          exercise.library === "platform" &&
          normalizeName(exercise.name) === queryKey,
      );
      if (exactPlatformMatches.length === 1) {
        return resolveMatched(query, exactPlatformMatches[0]);
      }
      if (exactPlatformMatches.length > 1) {
        return resolveAmbiguous(
          query,
          exactPlatformMatches,
          input.candidateLimit,
        );
      }

      const candidates = visible
        .filter((exercise) => isCandidate(exercise, queryKey))
        .slice(0, input.candidateLimit);
      const resolution = candidates.length > 1 ? "ambiguous" : "not_found";

      return AgentExerciseResolveResponseSchema.parse({
        query,
        resolution,
        matchedExercise: null,
        candidates: candidates.map(stripOwner),
        guidance: resolutionGuidance(resolution),
      });
    },
    async getCategoryById(input) {
      const ownedCategory = categories.find(
        (category) =>
          category.id === input.categoryId &&
          category.ownerUserId === input.userId,
      );
      if (ownedCategory !== undefined) {
        return { id: ownedCategory.id, name: ownedCategory.name };
      }

      // Back-compat for fixtures/tests that only ever describe a Category via
      // an Exercise's embedded category field (no standalone Category list) —
      // a Category referenced by at least one of the caller's own exercises
      // is a valid match too.
      const embedded = filterVisibleExercises(exercises, input.userId).find(
        (exercise) => exercise.category?.id === input.categoryId,
      );
      return embedded?.category == null
        ? null
        : { id: embedded.category.id, name: embedded.category.name };
    },
    async listFocuses(input) {
      return focusesForUser(input.userId);
    },
  };
}

function resolutionGuidance(
  resolution: "matched" | "ambiguous" | "not_found",
): z.infer<typeof AgentExerciseResolveGuidanceSchema> | null {
  if (resolution === "matched") {
    return null;
  }

  return AgentExerciseResolveGuidanceSchema.parse({
    op: "POST /agent/exercises/batch-write",
    message:
      resolution === "not_found"
        ? "No Exercise matched this name. Create it with POST /agent/exercises/batch-write, then retry the original write using the new Exercise id."
        : "Multiple Exercises matched this name. Disambiguate using one of the candidate ids (create a new Exercise with POST /agent/exercises/batch-write if none of them is right), then retry the original write.",
  });
}

function resolveMatched(
  query: string,
  exercise: AgentCatalogExercise,
): AgentExerciseResolveResponse {
  return AgentExerciseResolveResponseSchema.parse({
    query,
    resolution: "matched",
    matchedExercise: stripOwner(exercise),
    candidates: [],
    guidance: null,
  });
}

function resolveAmbiguous(
  query: string,
  exercises: readonly AgentCatalogExercise[],
  candidateLimit: number,
): AgentExerciseResolveResponse {
  return AgentExerciseResolveResponseSchema.parse({
    query,
    resolution: "ambiguous",
    matchedExercise: null,
    candidates: exercises.slice(0, candidateLimit).map(stripOwner),
    guidance: resolutionGuidance("ambiguous"),
  });
}

function callerCatalogExercises(
  exercises: readonly AgentCatalogExercise[],
  userId: string,
) {
  return exercises.filter(
    (exercise) =>
      exercise.library === "platform" ||
      (exercise.library === "user" && exercise.ownerUserId === userId),
  );
}

function filterVisibleExercises(
  exercises: readonly AgentCatalogExercise[],
  userId: string,
) {
  const callerExercises = callerCatalogExercises(exercises, userId);
  const activeUserExerciseNames = new Set(
    callerExercises
      .filter((exercise) => exercise.library === "user" && exercise.active)
      .map((exercise) => normalizeName(exercise.name)),
  );

  return callerExercises.filter((exercise) => {
    if (exercise.library === "user") {
      return true;
    }

    return !activeUserExerciseNames.has(normalizeName(exercise.name));
  });
}

function matchesSearch(
  exercise: AgentCatalogExercise,
  search: string | undefined,
) {
  if (search === undefined) {
    return true;
  }

  return isCandidate(exercise, normalizeName(search));
}

function matchesCategory(
  exercise: AgentCatalogExercise,
  category: string | undefined,
) {
  if (category === undefined) {
    return true;
  }

  if (exercise.category === null) {
    return false;
  }

  const categoryKey = normalizeName(category);
  return (
    normalizeName(exercise.category.id) === categoryKey ||
    normalizeName(exercise.category.name) === categoryKey
  );
}

// A focus filter names a Focus by id or by (case-insensitive) name. The id
// form matches without consulting the Focus list, so an exercise filed under a
// since-archived Focus is still reachable by that Focus's id. Resolved once
// per listing into the normalized ids an exercise may carry to match.
function resolveFocusFilter(
  focus: string,
  focuses: readonly AgentFocus[],
): ReadonlySet<string> {
  const focusKey = normalizeName(focus);
  const ids = new Set([focusKey]);
  for (const candidate of focuses) {
    if (normalizeName(candidate.name) === focusKey) {
      ids.add(normalizeName(candidate.id));
    }
  }
  return ids;
}

function matchesFocus(
  exercise: AgentCatalogExercise,
  focusIdKeys: ReadonlySet<string> | undefined,
) {
  if (focusIdKeys === undefined) {
    return true;
  }

  return (exercise.focusIds ?? []).some((id) =>
    focusIdKeys.has(normalizeName(id)),
  );
}

function isCandidate(exercise: AgentCatalogExercise, queryKey: string) {
  const exerciseKey = normalizeName(exercise.name);
  if (exerciseKey.includes(queryKey) || queryKey.includes(exerciseKey)) {
    return true;
  }

  const queryTokens = queryKey.split(" ").filter((token) => token.length > 0);
  return queryTokens.every((token) => exerciseKey.includes(token));
}

function projectExercise(
  exercise: AgentCatalogExercise,
  fields: readonly AgentExerciseListField[],
) {
  const fullExercise = stripOwner(exercise);
  const selected: Partial<Record<AgentExerciseListField, unknown>> = {
    id: fullExercise.id,
    name: fullExercise.name,
  };

  for (const field of fields) {
    selected[field] = fullExercise[field];
  }

  return selected;
}

function resolveFieldSelection(rawFields: string | undefined) {
  if (rawFields === undefined) {
    return [...AGENT_EXERCISE_DEFAULT_LIST_FIELDS];
  }

  return normalizeFieldSelection(
    rawFields
      .split(",")
      .map((field) => field.trim())
      .filter((field): field is AgentExerciseListField =>
        (AGENT_EXERCISE_LIST_FIELDS as readonly string[]).includes(field),
      ),
  );
}

function normalizeFieldSelection(
  fields: readonly AgentExerciseListField[],
): AgentExerciseListField[] {
  return [...new Set<AgentExerciseListField>(["id", "name", ...fields])];
}

function stripOwner(exercise: AgentCatalogExercise): AgentExercise {
  return AgentExerciseSchema.parse({
    id: exercise.id,
    library: exercise.library,
    name: exercise.name,
    category: exercise.category,
    dimensions: exercise.dimensions as readonly DimensionId[],
    equipment: exercise.equipment,
    // In-memory fixtures predating Focus may omit it; an absent list is none.
    focusIds: exercise.focusIds ?? [],
    loadMode: exercise.loadMode as ExerciseLoadMode,
    recordProfile: exercise.recordProfile as RecordProfile,
    favorite: exercise.favorite,
    active: exercise.active,
    shadowedPlatformExerciseId: exercise.shadowedPlatformExerciseId,
  });
}

function parseCursor(cursor: string | undefined) {
  if (cursor === undefined) {
    return 0;
  }

  const parsed = Number.parseInt(cursor, 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
}

function normalizeName(value: string) {
  return value.trim().toLocaleLowerCase("en-US").replace(/\s+/g, " ");
}

// ---------------------------------------------------------------------------
// DB-backed AgentCatalogStore
//
// The agent Exercise catalog is the merge of two libraries, exactly as the app
// composes it (CatalogRepository.listMergedCatalog):
//   - the User Library: rows synced into `exercises`/`exercise_categories`,
// read here from the opaque `payload` JSON the app wrote;
// - the Platform Library: a deterministic bundled seed that never
//     syncs, loaded server-side from the SAME wger artifact the app ships.
//
// Resolution and shadowing semantics are NOT re-implemented — we materialize a
// per-caller `AgentCatalogExercise[]` and delegate to
// `createInMemoryAgentCatalogStore`, so User-over-Platform ordering, name-based
// shadowing, and matched|ambiguous|not_found behavior are shared with the
// in-memory path and cannot fork.
// ---------------------------------------------------------------------------

// Mirrors the app's `defaultRecordProfileFor` (training_dimensions.dart) for
// Platform Library rows, which the app materializes with loadMode "added".
function defaultRecordProfileForDimensions(
  dimensions: readonly DimensionId[],
): RecordProfile {
  const has = (dimension: DimensionId) => dimensions.includes(dimension);
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

let cachedPlatformCatalog: readonly AgentCatalogExercise[] | undefined;
const platformCategoryNamesById = new Map(
  PLATFORM_EXERCISE_SEED_CATEGORIES.map((category) => [
    category.id,
    category.name,
  ]),
);

// Projects a Category reference to its label, or null when it cannot be named.
// The name comes from the caller's synced Category row when it has one; failing
// that, from the Platform seed, whose Categories every device seeds under the
// same fixed ids (so a seeded row the server never received still has its
// seed name). A reference neither source can name is a dangling id: the app's
// Exercise List shows such an exercise as Uncategorized, so it projects as no
// Category rather than as an unnamed one the schema would reject.
function resolveCategoryLabel(
  categoryId: string | null,
  syncedName: string | null | undefined,
): AgentCatalogExercise["category"] {
  if (categoryId === null) {
    return null;
  }
  const name =
    syncedName !== null && syncedName !== undefined && syncedName.length > 0
      ? syncedName
      : platformCategoryNamesById.get(categoryId);
  return name === undefined ? null : { id: categoryId, name };
}
const platformExerciseRedirects = new Map(
  PLATFORM_EXERCISE_SEED_REDIRECTS.map((redirect) => [
    redirect.fromExerciseId,
    redirect.toExerciseId,
  ]),
);

export function resolvePlatformExerciseId(exerciseId: string): string {
  return platformExerciseRedirects.get(exerciseId) ?? exerciseId;
}

/**
 * Every stored exercise id that `resolvePlatformExerciseId` maps to
 * `exerciseId`: the id itself and each seed redirect's source, so a SQL
 * filter on a Set's `exercise_id` misses none of the exercise's Sets.
 */
export function exerciseIdsResolvingTo(exerciseId: string): string[] {
  return [
    exerciseId,
    ...PLATFORM_EXERCISE_SEED_REDIRECTS.filter(
      (redirect) => redirect.toExerciseId === exerciseId,
    ).map((redirect) => redirect.fromExerciseId),
  ];
}

// Builds the Platform Library slice of the catalog from the bundled wger seed,
// deriving loadMode/recordProfile identically to the app's platform seed loader.
export function buildPlatformCatalogExercises(): readonly AgentCatalogExercise[] {
  if (cachedPlatformCatalog !== undefined) {
    return cachedPlatformCatalog;
  }

  cachedPlatformCatalog = PLATFORM_EXERCISE_SEED_EXERCISES.map((exercise) => {
    const dimensions = exercise.dimensionIds;
    return {
      id: exercise.id,
      library: "platform" as const,
      ownerUserId: null,
      name: exercise.name,
      category: resolveCategoryLabel(exercise.categoryId, null),
      dimensions,
      equipment: exercise.equipmentIds,
      focusIds: exercise.focusIds,
      loadMode: "added" as ExerciseLoadMode,
      recordProfile: defaultRecordProfileForDimensions(dimensions),
      favorite: false,
      active: true,
      shadowedPlatformExerciseId: null,
    };
  });

  return cachedPlatformCatalog;
}

export function parseJsonStringArray(value: unknown): string[] {
  if (Array.isArray(value)) {
    return value.map((entry) => String(entry));
  }
  if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value) as unknown;
      return Array.isArray(parsed) ? parsed.map((entry) => String(entry)) : [];
    } catch {
      return [];
    }
  }
  return [];
}

// Maps a synced Exercise row (opaque `payload` written by the app's
// `_exerciseImage`) plus the name on the caller's synced Category row for its
// `category_id` (null or empty when there is no such row) to an
// AgentCatalogExercise.
export function toAgentCatalogExerciseFromPayload({
  ownerUserId,
  deletedAt,
  payload,
  categoryName,
}: {
  ownerUserId: string;
  deletedAt: Date | null;
  payload: Record<string, unknown>;
  categoryName: string | null;
}): AgentCatalogExercise {
  const library =
    payload.library_origin === "platform" ? "platform" : ("user" as const);
  const dimensions = parseJsonStringArray(
    payload.dimension_ids,
  ) as DimensionId[];
  const loadMode: ExerciseLoadMode =
    payload.load_mode === "assisted" ? "assisted" : "added";
  const recordProfile =
    typeof payload.record_profile === "string"
      ? (payload.record_profile as RecordProfile)
      : defaultRecordProfileForDimensions(dimensions);
  // The app writes `category_id: null` for an uncategorized exercise; rows
  // from older or foreign writers may omit the key entirely. Both mean none.
  const categoryId =
    typeof payload.category_id === "string" && payload.category_id.length > 0
      ? payload.category_id
      : null;

  return {
    id: String(payload.id),
    library,
    ownerUserId,
    name: String(payload.name ?? ""),
    category: resolveCategoryLabel(categoryId, categoryName),
    dimensions,
    equipment: parseJsonStringArray(payload.equipment_ids),
    // `focus_ids` rides the payload JSON-encoded exactly like
    // `equipment_ids`; rows written before Focus existed simply lack it.
    focusIds: parseJsonStringArray(payload.focus_ids),
    loadMode,
    recordProfile,
    favorite: payload.is_favorite === true,
    active: deletedAt === null,
    shadowedPlatformExerciseId: null,
  };
}

export function createDrizzleAgentCatalogStore(
  db: ServerDatabase,
): AgentCatalogStore {
  async function loadUserCatalogExercises(
    userId: string,
  ): Promise<AgentCatalogExercise[]> {
    const [exerciseRows, categoryRows] = await Promise.all([
      db
        .select()
        .from(schema.exercises)
        .where(eq(schema.exercises.userId, userId)),
      db
        .select()
        .from(schema.exerciseCategories)
        .where(eq(schema.exerciseCategories.userId, userId)),
    ]);

    const categoryNamesById = new Map<string, string>();
    for (const row of categoryRows) {
      const payload = row.payload ?? {};
      categoryNamesById.set(
        row.id,
        typeof payload.name === "string" ? payload.name : "",
      );
    }

    return exerciseRows.map((row) =>
      toAgentCatalogExerciseFromPayload({
        ownerUserId: row.userId,
        deletedAt: row.deletedAt,
        payload: row.payload ?? {},
        categoryName:
          typeof row.payload?.category_id === "string"
            ? categoryNamesById.get(row.payload.category_id) ?? null
            : null,
      }),
    );
  }

  async function loadUserFocusRows(
    userId: string,
  ): Promise<AgentCatalogFocusFixture[]> {
    const rows = await db
      .select({
        id: schema.focuses.id,
        payload: schema.focuses.payload,
        deletedAt: schema.focuses.deletedAt,
      })
      .from(schema.focuses)
      .where(eq(schema.focuses.userId, userId));
    return rows.map((row) => toAgentCatalogFocusRow(userId, row));
  }

  async function loadCatalogForUser(
    userId: string,
  ): Promise<AgentCatalogExercise[]> {
    const platform = buildPlatformCatalogExercises();
    const userExercises = await loadUserCatalogExercises(userId);

    // Link each active User Library exercise to the Platform exercise it
    // shadows by normalized name (mirrors the app's
    // `_shadowsActivePlatformExercise`). The shadowed platform row is then
    // hidden at read time by the in-memory store's name-based visibility rule.
    const platformIdByName = new Map<string, string>();
    for (const exercise of platform) {
      const key = normalizeName(exercise.name);
      if (!platformIdByName.has(key)) {
        platformIdByName.set(key, exercise.id);
      }
    }
    const linkedUserExercises = userExercises.map((exercise) => {
      if (exercise.library !== "user" || !exercise.active) {
        return exercise;
      }
      const shadowedId = platformIdByName.get(normalizeName(exercise.name));
      return shadowedId === undefined
        ? exercise
        : { ...exercise, shadowedPlatformExerciseId: shadowedId };
    });

    return [...platform, ...linkedUserExercises];
  }

  return {
    async getExerciseById(input) {
      const store = createInMemoryAgentCatalogStore(
        await loadCatalogForUser(input.userId),
      );
      return store.getExerciseById({
        ...input,
        exerciseId: resolvePlatformExerciseId(input.exerciseId),
      });
    },
    async getExercisesByIds(input) {
      const store = createInMemoryAgentCatalogStore(
        await loadCatalogForUser(input.userId),
      );
      return store.getExercisesByIds(input);
    },
    async listExercises(input) {
      const [catalog, focusRows] = await Promise.all([
        loadCatalogForUser(input.userId),
        input.focus === undefined
          ? Promise.resolve([])
          : loadUserFocusRows(input.userId),
      ]);
      const store = createInMemoryAgentCatalogStore(catalog, [], focusRows);
      return store.listExercises(input);
    },
    async resolveExerciseName(input) {
      const store = createInMemoryAgentCatalogStore(
        await loadCatalogForUser(input.userId),
      );
      return store.resolveExerciseName(input);
    },
    async getCategoryById(input) {
      // Direct lookup against exercise_categories, independent of whether any
      // Exercise currently references it — a Category with zero exercises
      // filed under it (brand-new, or about to receive its first Exercise in
      // this same batch) is still a valid, caller-visible reference target.
      const rows = await db
        .select({
          id: schema.exerciseCategories.id,
          payload: schema.exerciseCategories.payload,
        })
        .from(schema.exerciseCategories)
        .where(
          and(
            eq(schema.exerciseCategories.id, input.categoryId),
            eq(schema.exerciseCategories.userId, input.userId),
            isNull(schema.exerciseCategories.deletedAt),
          ),
        )
        .limit(1);

      const row = rows[0];
      if (row === undefined) {
        return null;
      }

      const payload = row.payload ?? {};
      return {
        id: row.id,
        name: typeof payload.name === "string" ? payload.name : "",
      };
    },
    async listFocuses(input) {
      return mergeAgentFocuses(await loadUserFocusRows(input.userId));
    },
  };
}

// Maps a synced Focus row (opaque payload written by the app) to the
// catalog's row shape. The row's own deleted_at column is the tombstone.
export function toAgentCatalogFocusRow(
  ownerUserId: string,
  row: {
    id: string;
    payload: Record<string, unknown> | null;
    deletedAt: Date | null;
  },
): AgentCatalogFocusFixture {
  const payload = row.payload ?? {};
  const sortOrder = payload.sort_order;
  return {
    ownerUserId,
    id: row.id,
    name: typeof payload.name === "string" ? payload.name : "",
    sortOrder:
      typeof sortOrder === "number" && Number.isInteger(sortOrder)
        ? sortOrder
        : 0,
    deleted: row.deletedAt !== null,
  };
}
