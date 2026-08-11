import { createRoute, z } from "@hono/zod-openapi";
import { and, eq, inArray, sql } from "drizzle-orm";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";

export const AGENT_PLAN_DEFAULT_PAGE_LIMIT = 20;
export const AGENT_PLAN_MAX_PAGE_LIMIT = 100;
export const AGENT_PLAN_DEFAULT_COMPONENT_LIMIT = 100;
export const AGENT_PLAN_MAX_COMPONENT_LIMIT = 500;

const AGENT_WORKOUT_TEMPLATE_LIST_FIELDS = [
  "id",
  "name",
  "notes",
  "exerciseCount",
  "groupCount",
  "updatedAt",
  "deletedAt"
] as const;
const AGENT_WORKOUT_TEMPLATE_DEFAULT_LIST_FIELDS = ["id", "name", "exerciseCount"] as const;
const AGENT_ROUTINE_LIST_FIELDS = [
  "id",
  "name",
  "notes",
  "cadenceKind",
  "cadenceWindow",
  "entryCount",
  "updatedAt",
  "deletedAt"
] as const;
const AGENT_ROUTINE_DEFAULT_LIST_FIELDS = ["id", "name", "cadenceKind", "entryCount"] as const;

const ISO8601StringSchema = z.string().min(1).openapi({
  description: "ISO-8601 timestamp."
});
const LocalDateSchema = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/)
  .openapi({
    description: "Calendar date in YYYY-MM-DD form."
  });
const AgentPlanCadenceKindSchema = z.enum(["weekly", "rotating"]).openapi("AgentPlanCadenceKind");

const AgentPlanDimensionValueSchema = z
  .object({
    value: z.number().nullable(),
    unit: z.string().min(1).nullable(),
    entered: z.string().nullable()
  })
  .openapi("AgentPlanDimensionValue");

export const AgentPlanPrescriptionSchema = z
  .object({
    id: z.string().min(1),
    templateExerciseId: z.string().min(1),
    mode: z.enum(["fixed", "copyPrevious"]),
    position: z.number().int(),
    repeat: z.number().int().min(1),
    restAfterSeconds: z.number().nullable(),
    load: AgentPlanDimensionValueSchema.nullable(),
    reps: AgentPlanDimensionValueSchema.nullable(),
    duration: AgentPlanDimensionValueSchema.nullable(),
    distance: AgentPlanDimensionValueSchema.nullable(),
    updatedAt: ISO8601StringSchema,
    deletedAt: ISO8601StringSchema.nullable()
  })
  .openapi("AgentPlanPrescription");

export const AgentPlanTemplateExerciseSchema = z
  .object({
    id: z.string().min(1),
    workoutTemplateId: z.string().min(1),
    exerciseId: z.string().min(1),
    position: z.number().int(),
    note: z.string().nullable(),
    prescriptions: z.array(AgentPlanPrescriptionSchema),
    prescriptionCount: z.number().int().min(0),
    prescriptionsTruncated: z.boolean(),
    updatedAt: ISO8601StringSchema,
    deletedAt: ISO8601StringSchema.nullable()
  })
  .openapi("AgentPlanTemplateExercise");

export const AgentPlanTemplateGroupMemberSchema = z
  .object({
    id: z.string().min(1),
    groupId: z.string().min(1),
    templateExerciseId: z.string().min(1),
    position: z.number().int(),
    updatedAt: ISO8601StringSchema,
    deletedAt: ISO8601StringSchema.nullable()
  })
  .openapi("AgentPlanTemplateGroupMember");

export const AgentPlanTemplateGroupSchema = z
  .object({
    id: z.string().min(1),
    workoutTemplateId: z.string().min(1),
    name: z.string().min(1),
    colorHex: z.string().min(1),
    rounds: z.number().int().min(1),
    position: z.number().int(),
    members: z.array(AgentPlanTemplateGroupMemberSchema),
    memberCount: z.number().int().min(0),
    membersTruncated: z.boolean(),
    updatedAt: ISO8601StringSchema,
    deletedAt: ISO8601StringSchema.nullable()
  })
  .openapi("AgentPlanTemplateGroup");

export const AgentWorkoutTemplateDetailSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1),
    notes: z.string().nullable(),
    exercises: z.array(AgentPlanTemplateExerciseSchema),
    groups: z.array(AgentPlanTemplateGroupSchema),
    exerciseCount: z.number().int().min(0),
    groupCount: z.number().int().min(0),
    componentLimit: z.number().int().min(1).max(AGENT_PLAN_MAX_COMPONENT_LIMIT),
    componentCount: z.number().int().min(0),
    componentsReturned: z.number().int().min(0),
    componentsTruncated: z.boolean(),
    updatedAt: ISO8601StringSchema,
    deletedAt: ISO8601StringSchema.nullable()
  })
  .openapi("AgentWorkoutTemplateDetail");

const AgentWorkoutTemplateListFieldSchema = z
  .enum(AGENT_WORKOUT_TEMPLATE_LIST_FIELDS)
  .openapi("AgentWorkoutTemplateListField");
const AgentWorkoutTemplateListItemSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1),
    notes: z.string().nullable().optional(),
    exerciseCount: z.number().int().min(0).optional(),
    groupCount: z.number().int().min(0).optional(),
    updatedAt: ISO8601StringSchema.optional(),
    deletedAt: ISO8601StringSchema.nullable().optional()
  })
  .openapi("AgentWorkoutTemplateListItem");

export const AgentWorkoutTemplateListResponseSchema = z
  .object({
    workoutTemplates: z.array(AgentWorkoutTemplateListItemSchema),
    fields: z.array(AgentWorkoutTemplateListFieldSchema),
    limit: z.number().int().min(1).max(AGENT_PLAN_MAX_PAGE_LIMIT),
    nextCursor: z.string().min(1).nullable(),
    totalMatched: z.number().int().min(0)
  })
  .openapi("AgentWorkoutTemplateListResponse");

export const AgentWorkoutTemplateDetailResponseSchema = z
  .object({
    workoutTemplate: AgentWorkoutTemplateDetailSchema
  })
  .openapi("AgentWorkoutTemplateDetailResponse");

const AgentPlanCadenceSchema = z
  .discriminatedUnion("kind", [
    z.object({
      kind: z.literal("weekly"),
      window: z.null()
    }),
    z.object({
      kind: z.literal("rotating"),
      window: z.number().int().min(1)
    })
  ])
  .openapi("AgentPlanCadence");

export const AgentPlanRoutineEntrySchema = z
  .object({
    id: z.string().min(1),
    routineId: z.string().min(1),
    workoutTemplateId: z.string().min(1),
    workoutTemplateName: z.string().min(1),
    workoutTemplateArchived: z.boolean(),
    position: z.number().int(),
    slot: z.number().int().min(1).nullable(),
    updatedAt: ISO8601StringSchema,
    deletedAt: ISO8601StringSchema.nullable()
  })
  .openapi("AgentPlanRoutineEntry");

const AgentPlanCadenceSlotSchema = z
  .object({
    slot: z.number().int().min(1),
    entries: z.array(AgentPlanRoutineEntrySchema)
  })
  .openapi("AgentPlanCadenceSlot");

export const AgentPlanUpNextCardSchema = z
  .object({
    routineEntryId: z.string().min(1),
    workoutTemplateId: z.string().min(1),
    workoutTemplateName: z.string().min(1),
    slot: z.number().int().min(1),
    isDone: z.boolean()
  })
  .openapi("AgentPlanUpNextCard");

export const AgentPlanUpNextSchema = z
  .object({
    selectedDate: LocalDateSchema,
    slot: z.number().int().min(1),
    cards: z.array(AgentPlanUpNextCardSchema)
  })
  .openapi("AgentPlanUpNext");

export const AgentRoutineDetailSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1),
    notes: z.string().nullable(),
    cadence: AgentPlanCadenceSchema.nullable(),
    entries: z.array(AgentPlanRoutineEntrySchema),
    slotLayout: z.array(AgentPlanCadenceSlotSchema).nullable(),
    upNext: AgentPlanUpNextSchema.nullable(),
    entryLimit: z.number().int().min(1).max(AGENT_PLAN_MAX_COMPONENT_LIMIT),
    entryCount: z.number().int().min(0),
    entriesReturned: z.number().int().min(0),
    entriesTruncated: z.boolean(),
    updatedAt: ISO8601StringSchema,
    deletedAt: ISO8601StringSchema.nullable()
  })
  .openapi("AgentRoutineDetail");

const AgentRoutineListFieldSchema = z
  .enum(AGENT_ROUTINE_LIST_FIELDS)
  .openapi("AgentRoutineListField");
const AgentRoutineListItemSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1),
    notes: z.string().nullable().optional(),
    cadenceKind: AgentPlanCadenceKindSchema.nullable().optional(),
    cadenceWindow: z.number().int().min(1).nullable().optional(),
    entryCount: z.number().int().min(0).optional(),
    updatedAt: ISO8601StringSchema.optional(),
    deletedAt: ISO8601StringSchema.nullable().optional()
  })
  .openapi("AgentRoutineListItem");

export const AgentRoutineListResponseSchema = z
  .object({
    routines: z.array(AgentRoutineListItemSchema),
    fields: z.array(AgentRoutineListFieldSchema),
    limit: z.number().int().min(1).max(AGENT_PLAN_MAX_PAGE_LIMIT),
    nextCursor: z.string().min(1).nullable(),
    totalMatched: z.number().int().min(0)
  })
  .openapi("AgentRoutineListResponse");

export const AgentRoutineDetailResponseSchema = z
  .object({
    routine: AgentRoutineDetailSchema
  })
  .openapi("AgentRoutineDetailResponse");

export const AgentPlanNotFoundResponseSchema = z
  .object({
    code: z.enum(["agent_workout_template_not_found", "agent_routine_not_found"]),
    message: z.string().min(1)
  })
  .openapi("AgentPlanNotFoundResponse");

export const AgentPlanReadUnavailableResponseSchema = z
  .object({
    code: z.literal("agent_plan_read_unavailable"),
    message: z.string().min(1)
  })
  .openapi("AgentPlanReadUnavailableResponse");

export const AgentPlanInvalidCursorResponseSchema = z
  .object({
    code: z.literal("agent_plan_invalid_cursor"),
    message: z.string().min(1)
  })
  .openapi("AgentPlanInvalidCursorResponse");

export class AgentPlanInvalidCursorError extends Error {
  constructor(readonly cursor: string) {
    super("The plan-read cursor is no longer valid.");
    this.name = "AgentPlanInvalidCursorError";
  }
}

export function agentPlanInvalidCursorResponse() {
  return AgentPlanInvalidCursorResponseSchema.parse({
    code: "agent_plan_invalid_cursor",
    message: "The cursor is invalid or no longer resolves in the requested result set."
  });
}

const workoutTemplateFieldSet = new Set<string>(AGENT_WORKOUT_TEMPLATE_LIST_FIELDS);
const routineFieldSet = new Set<string>(AGENT_ROUTINE_LIST_FIELDS);

const AgentPlanBaseListQueryShape = {
  search: z
    .string()
    .trim()
    .min(1)
    .optional()
    .openapi({
      param: { name: "search", in: "query" },
      description: "Optional case-insensitive name search."
    }),
  includeArchived: z.coerce
    .boolean()
    .default(false)
    .openapi({
      param: { name: "includeArchived", in: "query" },
      description: "When true, archived rows are included."
    }),
  limit: z.coerce
    .number()
    .int()
    .min(1)
    .max(AGENT_PLAN_MAX_PAGE_LIMIT)
    .default(AGENT_PLAN_DEFAULT_PAGE_LIMIT)
    .openapi({
      param: { name: "limit", in: "query" },
      description: "Maximum rows to return, bounded to 100."
    }),
  cursor: z
    .string()
    .trim()
    .min(1)
    .optional()
    .openapi({
      param: { name: "cursor", in: "query" },
      description: "Opaque cursor returned by the previous page."
    })
};

export const AgentWorkoutTemplateListQuerySchema = z
  .object({
    ...AgentPlanBaseListQueryShape,
    fields: projectedFieldsQuery(workoutTemplateFieldSet, "Workout Template")
  })
  .openapi("AgentWorkoutTemplateListQuery");

export const AgentRoutineListQuerySchema = z
  .object({
    ...AgentPlanBaseListQueryShape,
    fields: projectedFieldsQuery(routineFieldSet, "Routine")
  })
  .openapi("AgentRoutineListQuery");

export const AgentPlanDetailQuerySchema = z
  .object({
    includeArchived: z.coerce
      .boolean()
      .default(false)
      .openapi({
        param: { name: "includeArchived", in: "query" },
        description: "When true, archived child rows are included in the bounded detail."
      }),
    componentLimit: z.coerce
      .number()
      .int()
      .min(1)
      .max(AGENT_PLAN_MAX_COMPONENT_LIMIT)
      .default(AGENT_PLAN_DEFAULT_COMPONENT_LIMIT)
      .openapi({
        param: { name: "componentLimit", in: "query" },
        description:
          "Maximum nested plan rows returned. Counts and truncation flags describe omitted rows."
      })
  })
  .openapi("AgentPlanDetailQuery");

export const AgentRoutineDetailQuerySchema = AgentPlanDetailQuerySchema.extend({
  // Resolve the default in routineDetail(), not in Zod: OpenAPI generation
  // evaluates functional defaults and would otherwise commit today's date.
  selectedDate: LocalDateSchema.optional().openapi({
    param: { name: "selectedDate", in: "query" },
    description:
      "Training Day used for weekly Up-next derivation. Rotating Cadences ignore this date."
  })
}).openapi("AgentRoutineDetailQuery");

export const AgentWorkoutTemplateParamsSchema = z
  .object({
    workoutTemplateId: z
      .string()
      .min(1)
      .openapi({
        param: { name: "workoutTemplateId", in: "path" }
      })
  })
  .openapi("AgentWorkoutTemplateParams");

export const AgentRoutineParamsSchema = z
  .object({
    routineId: z
      .string()
      .min(1)
      .openapi({
        param: { name: "routineId", in: "path" }
      })
  })
  .openapi("AgentRoutineParams");

export const agentWorkoutTemplateListRoute = createRoute({
  method: "get",
  path: "/agent/workout-templates",
  operationId: "listAgentWorkoutTemplates",
  tags: ["Agent Reads"],
  summary: "List the caller's Workout Templates.",
  description:
    "Returns a cursor-paginated, projected Workout Template page with a small default field set. Use the detail operation for bounded exercises, Prescriptions, and Template Groups.",
  security: [{ bearerAuth: [] }],
  request: { query: AgentWorkoutTemplateListQuerySchema },
  responses: planListResponses(
    "A bounded page of Workout Templates.",
    AgentWorkoutTemplateListResponseSchema
  )
});

export const agentWorkoutTemplateDetailRoute = createRoute({
  method: "get",
  path: "/agent/workout-templates/{workoutTemplateId}",
  operationId: "getAgentWorkoutTemplate",
  tags: ["Agent Reads"],
  summary: "Get one Workout Template and its plan content.",
  description:
    "Returns one Workout Template with ordered Template Exercises, Prescriptions, Template Groups, and members. Nested rows are explicitly capped; counts and truncation flags make the bound visible.",
  security: [{ bearerAuth: [] }],
  request: {
    params: AgentWorkoutTemplateParamsSchema,
    query: AgentPlanDetailQuerySchema
  },
  responses: planDetailResponses(
    "The bounded Workout Template detail.",
    AgentWorkoutTemplateDetailResponseSchema
  )
});

export const agentRoutineListRoute = createRoute({
  method: "get",
  path: "/agent/routines",
  operationId: "listAgentRoutines",
  tags: ["Agent Reads"],
  summary: "List the caller's Routines.",
  description:
    "Returns a cursor-paginated, projected Routine page with a small default field set. Use the detail operation for the Cadence slot layout and derived Up next.",
  security: [{ bearerAuth: [] }],
  request: { query: AgentRoutineListQuerySchema },
  responses: planListResponses("A bounded page of Routines.", AgentRoutineListResponseSchema)
});

export const agentRoutineDetailRoute = createRoute({
  method: "get",
  path: "/agent/routines/{routineId}",
  operationId: "getAgentRoutine",
  tags: ["Agent Reads"],
  summary: "Get one Routine with its Cadence layout and derived Up next.",
  description:
    "Returns ordered Routine Entries, the complete Cadence slot layout including empty rest slots, and Up next derived on demand from Template Links exactly as the app derives it. No rotation cursor is stored.",
  security: [{ bearerAuth: [] }],
  request: {
    params: AgentRoutineParamsSchema,
    query: AgentRoutineDetailQuerySchema
  },
  responses: planDetailResponses("The bounded Routine detail.", AgentRoutineDetailResponseSchema)
});

export type AgentWorkoutTemplateListQuery = z.infer<typeof AgentWorkoutTemplateListQuerySchema>;
export type AgentRoutineListQuery = z.infer<typeof AgentRoutineListQuerySchema>;
export type AgentPlanDetailQuery = z.infer<typeof AgentPlanDetailQuerySchema>;
export type AgentRoutineDetailQuery = z.infer<typeof AgentRoutineDetailQuerySchema>;
export type AgentPlanUpNext = z.infer<typeof AgentPlanUpNextSchema>;
export type AgentPlanReadStore = {
  listWorkoutTemplates(input: {
    userId: string;
    query: AgentWorkoutTemplateListQuery;
  }): Promise<z.infer<typeof AgentWorkoutTemplateListResponseSchema>>;
  getWorkoutTemplate(input: {
    userId: string;
    workoutTemplateId: string;
    query: AgentPlanDetailQuery;
  }): Promise<z.infer<typeof AgentWorkoutTemplateDetailResponseSchema> | null>;
  listRoutines(input: {
    userId: string;
    query: AgentRoutineListQuery;
  }): Promise<z.infer<typeof AgentRoutineListResponseSchema>>;
  getRoutine(input: {
    userId: string;
    routineId: string;
    query: AgentRoutineDetailQuery;
  }): Promise<z.infer<typeof AgentRoutineDetailResponseSchema> | null>;
};

export type AgentUpNextRoutineEntry = {
  routineEntryId: string;
  workoutTemplateId: string;
  workoutTemplateName: string;
  slot: number;
};
export type AgentUpNextTemplateLinkFact = {
  workoutTemplateId: string;
  slot: number;
  sequence: number;
  workoutLocalDate: string | null;
};

/**
 * TypeScript twin of mobile's `deriveRoutineUpNext`, deliberately consumed by
 * the same m34 golden vector. It has no database or clock dependency.
 */
export function deriveAgentRoutineUpNext(input: {
  cadence:
    | { kind: "weekly"; window: null }
    | {
        kind: "rotating";
        window: number;
      };
  entries: readonly AgentUpNextRoutineEntry[];
  links: readonly AgentUpNextTemplateLinkFact[];
  selectedDate: string;
}): AgentPlanUpNext | null {
  const entriesBySlot = new Map<number, AgentUpNextRoutineEntry[]>();
  for (const entry of input.entries) {
    const slotEntries = entriesBySlot.get(entry.slot) ?? [];
    slotEntries.push(entry);
    entriesBySlot.set(entry.slot, slotEntries);
  }
  if (entriesBySlot.size === 0) {
    return null;
  }

  if (input.cadence.kind === "weekly") {
    const slot = isoWeekday(input.selectedDate);
    const entries = entriesBySlot.get(slot);
    if (entries === undefined || entries.length === 0) {
      return null;
    }
    const doneTemplateIds = new Set(
      input.links
        .filter((link) => link.slot === slot && link.workoutLocalDate === input.selectedDate)
        .map((link) => link.workoutTemplateId)
    );
    return {
      selectedDate: input.selectedDate,
      slot,
      cards: upNextCards(entries, doneTemplateIds)
    };
  }

  const sortedLinks = [...input.links].sort((left, right) => right.sequence - left.sequence);
  const currentSlot = sortedLinks[0]?.slot;
  const doneTemplateIds = new Set<string>();
  if (currentSlot !== undefined) {
    for (const link of sortedLinks) {
      if (link.slot !== currentSlot) {
        break;
      }
      doneTemplateIds.add(link.workoutTemplateId);
    }
    const currentEntries = entriesBySlot.get(currentSlot) ?? [];
    if (currentEntries.some((entry) => !doneTemplateIds.has(entry.workoutTemplateId))) {
      return {
        selectedDate: input.selectedDate,
        slot: currentSlot,
        cards: upNextCards(currentEntries, doneTemplateIds)
      };
    }
  }

  const base = currentSlot ?? 0;
  for (let step = 1; step <= input.cadence.window; step += 1) {
    const candidate = ((base - 1 + step) % input.cadence.window) + 1;
    const entries = entriesBySlot.get(candidate);
    if (entries !== undefined && entries.length > 0) {
      return {
        selectedDate: input.selectedDate,
        slot: candidate,
        cards: upNextCards(entries, new Set())
      };
    }
  }
  return null;
}

type OpaquePlanRow = {
  id: string;
  payload: Record<string, unknown>;
  updatedAt: Date;
  deletedAt: Date | null;
};
type WorkoutTemplateListRows = {
  workoutTemplates: OpaquePlanRow[];
  templateExercises: OpaquePlanRow[];
  templateGroups: OpaquePlanRow[];
};
type WorkoutTemplateDetailRows = WorkoutTemplateListRows & {
  prescriptions: OpaquePlanRow[];
  templateGroupMembers: OpaquePlanRow[];
};
type RoutineListRows = {
  routines: OpaquePlanRow[];
  routineEntries: OpaquePlanRow[];
};
type RoutineDetailRows = RoutineListRows & {
  workoutTemplates: OpaquePlanRow[];
  templateLinks: OpaquePlanRow[];
};

export function createDrizzleAgentPlanReadStore(db: ServerDatabase): AgentPlanReadStore {
  return {
    async listWorkoutTemplates({ userId, query }) {
      const fields = resolveWorkoutTemplateFields(query.fields);
      const rows = await loadWorkoutTemplateListRows(db, userId, fields);
      const exerciseCounts = countActiveByParent(
        rows.templateExercises,
        "workout_template_id"
      );
      const groupCounts = countActiveByParent(rows.templateGroups, "workout_template_id");
      const templates = rows.workoutTemplates
        .filter((row) => query.includeArchived || row.deletedAt === null)
        .map((row) => workoutTemplateSummary(row, exerciseCounts, groupCounts))
        .filter((row) => matchesSearch(row.name, query.search))
        .sort(compareNamedRows);
      const start = cursorOffset(templates, query.cursor);
      const page = templates.slice(start, start + query.limit);

      return AgentWorkoutTemplateListResponseSchema.parse({
        workoutTemplates: page.map((template) => projectFields(template, fields)),
        fields,
        limit: query.limit,
        nextCursor: nextCursor(templates, start, page),
        totalMatched: templates.length
      });
    },

    async getWorkoutTemplate({ userId, workoutTemplateId, query }) {
      const [template] = await db
        .select()
        .from(schema.workoutTemplates)
        .where(
          and(
            eq(schema.workoutTemplates.userId, userId),
            eq(schema.workoutTemplates.id, workoutTemplateId)
          )
        );
      if (
        template === undefined ||
        (!query.includeArchived && template.deletedAt !== null)
      ) {
        return null;
      }
      const rows = await loadWorkoutTemplateDetailRows(
        db,
        userId,
        workoutTemplateId,
        template
      );
      const detail = workoutTemplateDetail(template, rows, query);
      return AgentWorkoutTemplateDetailResponseSchema.parse({
        workoutTemplate: detail
      });
    },

    async listRoutines({ userId, query }) {
      const fields = resolveRoutineFields(query.fields);
      const rows = await loadRoutineListRows(db, userId, fields);
      const entryCounts = countActiveByParent(rows.routineEntries, "routine_id");
      const routines = rows.routines
        .filter((row) => query.includeArchived || row.deletedAt === null)
        .map((row) => routineSummary(row, entryCounts))
        .filter((row) => matchesSearch(row.name, query.search))
        .sort(compareNamedRows);
      const start = cursorOffset(routines, query.cursor);
      const page = routines.slice(start, start + query.limit);

      return AgentRoutineListResponseSchema.parse({
        routines: page.map((routine) => projectFields(routine, fields)),
        fields,
        limit: query.limit,
        nextCursor: nextCursor(routines, start, page),
        totalMatched: routines.length
      });
    },

    async getRoutine({ userId, routineId, query }) {
      const [routine] = await db
        .select()
        .from(schema.routines)
        .where(and(eq(schema.routines.userId, userId), eq(schema.routines.id, routineId)));
      if (
        routine === undefined ||
        (!query.includeArchived && routine.deletedAt !== null)
      ) {
        return null;
      }
      const rows = await loadRoutineDetailRows(db, userId, routineId, routine);
      return AgentRoutineDetailResponseSchema.parse({
        routine: routineDetail(routine, rows, query)
      });
    }
  };
}

async function loadWorkoutTemplateListRows(
  db: ServerDatabase,
  userId: string,
  fields: readonly string[]
): Promise<WorkoutTemplateListRows> {
  const includeExerciseCounts = fields.includes("exerciseCount");
  const includeGroupCounts = fields.includes("groupCount");
  const [workoutTemplates, templateExercises, templateGroups] = await Promise.all([
    db.select().from(schema.workoutTemplates).where(eq(schema.workoutTemplates.userId, userId)),
    includeExerciseCounts
      ? db
          .select()
          .from(schema.templateExercises)
          .where(eq(schema.templateExercises.userId, userId))
      : Promise.resolve([]),
    includeGroupCounts
      ? db.select().from(schema.templateGroups).where(eq(schema.templateGroups.userId, userId))
      : Promise.resolve([])
  ]);
  return { workoutTemplates, templateExercises, templateGroups };
}

async function loadWorkoutTemplateDetailRows(
  db: ServerDatabase,
  userId: string,
  workoutTemplateId: string,
  workoutTemplate: OpaquePlanRow
): Promise<WorkoutTemplateDetailRows> {
  const [templateExercises, templateGroups] = await Promise.all([
    db
      .select()
      .from(schema.templateExercises)
      .where(
        and(
          eq(schema.templateExercises.userId, userId),
          sql`${schema.templateExercises.payload} ->> 'workout_template_id' = ${workoutTemplateId}`
        )
      ),
    db
      .select()
      .from(schema.templateGroups)
      .where(
        and(
          eq(schema.templateGroups.userId, userId),
          sql`${schema.templateGroups.payload} ->> 'workout_template_id' = ${workoutTemplateId}`
        )
      )
  ]);
  const exerciseIds = templateExercises.map((row) => row.id);
  const groupIds = templateGroups.map((row) => row.id);
  const [prescriptions, templateGroupMembers] = await Promise.all([
    exerciseIds.length === 0
      ? Promise.resolve([])
      : db
          .select()
          .from(schema.prescriptions)
          .where(
            and(
              eq(schema.prescriptions.userId, userId),
              inArray(
                sql<string>`${schema.prescriptions.payload} ->> 'template_exercise_id'`,
                exerciseIds
              )
            )
          ),
    groupIds.length === 0
      ? Promise.resolve([])
      : db
          .select()
          .from(schema.templateGroupMembers)
          .where(
            and(
              eq(schema.templateGroupMembers.userId, userId),
              inArray(
                sql<string>`${schema.templateGroupMembers.payload} ->> 'group_id'`,
                groupIds
              )
            )
          )
  ]);
  return {
    workoutTemplates: [workoutTemplate],
    templateExercises,
    prescriptions,
    templateGroups,
    templateGroupMembers
  };
}

async function loadRoutineListRows(
  db: ServerDatabase,
  userId: string,
  fields: readonly string[]
): Promise<RoutineListRows> {
  const [routines, routineEntries] = await Promise.all([
    db.select().from(schema.routines).where(eq(schema.routines.userId, userId)),
    fields.includes("entryCount")
      ? db.select().from(schema.routineEntries).where(eq(schema.routineEntries.userId, userId))
      : Promise.resolve([])
  ]);
  return { routines, routineEntries };
}

async function loadRoutineDetailRows(
  db: ServerDatabase,
  userId: string,
  routineId: string,
  routine: OpaquePlanRow
): Promise<RoutineDetailRows> {
  const [routineEntries, templateLinks] = await Promise.all([
    db
      .select()
      .from(schema.routineEntries)
      .where(
        and(
          eq(schema.routineEntries.userId, userId),
          sql`${schema.routineEntries.payload} ->> 'routine_id' = ${routineId}`
        )
      ),
    db
      .select()
      .from(schema.templateLinks)
      .where(
        and(
          eq(schema.templateLinks.userId, userId),
          sql`${schema.templateLinks.payload} ->> 'routine_id' = ${routineId}`
        )
      )
  ]);
  const workoutTemplateIds = [
    ...new Set(
      routineEntries
        .map((entry) => payloadString(entry, "workout_template_id"))
        .filter((id): id is string => id !== null)
    )
  ];
  const workoutTemplates =
    workoutTemplateIds.length === 0
      ? []
      : await db
          .select()
          .from(schema.workoutTemplates)
          .where(
            and(
              eq(schema.workoutTemplates.userId, userId),
              inArray(schema.workoutTemplates.id, workoutTemplateIds)
            )
          );
  return {
    workoutTemplates,
    routines: [routine],
    routineEntries,
    templateLinks
  };
}

function workoutTemplateSummary(
  row: OpaquePlanRow,
  exerciseCounts: ReadonlyMap<string, number>,
  groupCounts: ReadonlyMap<string, number>
) {
  return {
    id: row.id,
    name: payloadRequiredString(row, "name"),
    notes: payloadNullableString(row, "notes"),
    exerciseCount: exerciseCounts.get(row.id) ?? 0,
    groupCount: groupCounts.get(row.id) ?? 0,
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  };
}

function workoutTemplateDetail(
  row: OpaquePlanRow,
  rows: WorkoutTemplateDetailRows,
  query: AgentPlanDetailQuery
) {
  const visible = (candidate: OpaquePlanRow) =>
    query.includeArchived || candidate.deletedAt === null;
  const exerciseRows = rows.templateExercises
    .filter(
      (candidate) =>
        visible(candidate) && payloadString(candidate, "workout_template_id") === row.id
    )
    .sort(comparePositionedRows);
  const groupRows = rows.templateGroups
    .filter(
      (candidate) =>
        visible(candidate) && payloadString(candidate, "workout_template_id") === row.id
    )
    .sort(comparePositionedRows);
  const prescriptionRowsByExercise = groupByParent(
    rows.prescriptions.filter(visible),
    "template_exercise_id"
  );
  const memberRowsByGroup = groupByParent(rows.templateGroupMembers.filter(visible), "group_id");
  const componentCount =
    exerciseRows.length +
    groupRows.length +
    exerciseRows.reduce(
      (sum, exercise) => sum + (prescriptionRowsByExercise.get(exercise.id)?.length ?? 0),
      0
    ) +
    groupRows.reduce((sum, group) => sum + (memberRowsByGroup.get(group.id)?.length ?? 0), 0);

  let remaining = query.componentLimit;
  let componentsReturned = 0;
  const exercises = [];
  for (const exerciseRow of exerciseRows) {
    if (remaining === 0) {
      break;
    }
    remaining -= 1;
    componentsReturned += 1;
    const allPrescriptions = (prescriptionRowsByExercise.get(exerciseRow.id) ?? []).sort(
      comparePositionedRows
    );
    const selectedPrescriptions = allPrescriptions.slice(0, remaining);
    remaining -= selectedPrescriptions.length;
    componentsReturned += selectedPrescriptions.length;
    exercises.push(
      templateExerciseFromRow(exerciseRow, selectedPrescriptions, allPrescriptions.length)
    );
  }

  const groups = [];
  for (const groupRow of groupRows) {
    if (remaining === 0) {
      break;
    }
    remaining -= 1;
    componentsReturned += 1;
    const allMembers = (memberRowsByGroup.get(groupRow.id) ?? []).sort(comparePositionedRows);
    const selectedMembers = allMembers.slice(0, remaining);
    remaining -= selectedMembers.length;
    componentsReturned += selectedMembers.length;
    groups.push(templateGroupFromRow(groupRow, selectedMembers, allMembers.length));
  }

  return {
    id: row.id,
    name: payloadRequiredString(row, "name"),
    notes: payloadNullableString(row, "notes"),
    exercises,
    groups,
    exerciseCount: exerciseRows.length,
    groupCount: groupRows.length,
    componentLimit: query.componentLimit,
    componentCount,
    componentsReturned,
    componentsTruncated: componentsReturned < componentCount,
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  };
}

function templateExerciseFromRow(
  row: OpaquePlanRow,
  prescriptionRows: OpaquePlanRow[],
  prescriptionCount: number
) {
  return {
    id: row.id,
    workoutTemplateId: payloadRequiredString(row, "workout_template_id"),
    exerciseId: payloadRequiredString(row, "exercise_id"),
    position: payloadRequiredInteger(row, "position"),
    note: payloadNullableString(row, "note"),
    prescriptions: prescriptionRows.map(prescriptionFromRow),
    prescriptionCount,
    prescriptionsTruncated: prescriptionRows.length < prescriptionCount,
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  };
}

function prescriptionFromRow(row: OpaquePlanRow) {
  const mode = payloadRequiredString(row, "mode");
  return {
    id: row.id,
    templateExerciseId: payloadRequiredString(row, "template_exercise_id"),
    mode: mode === "copy-previous" ? "copyPrevious" : mode,
    position: payloadRequiredInteger(row, "position"),
    repeat: payloadRequiredInteger(row, "repeat"),
    restAfterSeconds: payloadNullableNumber(row, "rest_after"),
    load: dimensionValue(row, "load"),
    reps: dimensionValue(row, "reps"),
    duration: dimensionValue(row, "duration"),
    distance: dimensionValue(row, "distance"),
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  };
}

function templateGroupFromRow(
  row: OpaquePlanRow,
  memberRows: OpaquePlanRow[],
  memberCount: number
) {
  return {
    id: row.id,
    workoutTemplateId: payloadRequiredString(row, "workout_template_id"),
    name: payloadRequiredString(row, "name"),
    colorHex: payloadRequiredString(row, "color_hex"),
    rounds: payloadRequiredInteger(row, "rounds"),
    position: payloadRequiredInteger(row, "position"),
    members: memberRows.map((member) => ({
      id: member.id,
      groupId: payloadRequiredString(member, "group_id"),
      templateExerciseId: payloadRequiredString(member, "template_exercise_id"),
      position: payloadRequiredInteger(member, "position"),
      updatedAt: member.updatedAt.toISOString(),
      deletedAt: member.deletedAt?.toISOString() ?? null
    })),
    memberCount,
    membersTruncated: memberRows.length < memberCount,
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  };
}

function routineSummary(row: OpaquePlanRow, entryCounts: ReadonlyMap<string, number>) {
  const cadence = cadenceFromRow(row);
  return {
    id: row.id,
    name: payloadRequiredString(row, "name"),
    notes: payloadNullableString(row, "notes"),
    cadenceKind: cadence?.kind ?? null,
    cadenceWindow: cadence?.window ?? null,
    entryCount: entryCounts.get(row.id) ?? 0,
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  };
}

function routineDetail(row: OpaquePlanRow, rows: RoutineDetailRows, query: AgentRoutineDetailQuery) {
  const selectedDate = query.selectedDate ?? currentUtcLocalDate();
  const templatesById = new Map(rows.workoutTemplates.map((template) => [template.id, template]));
  const allEntryRows = rows.routineEntries
    .filter(
      (candidate) =>
        (query.includeArchived || candidate.deletedAt === null) &&
        payloadString(candidate, "routine_id") === row.id
    )
    .sort(comparePositionedRows);
  const allEntries = allEntryRows.map((entry) => routineEntryFromRow(entry, templatesById));
  const entries = allEntries.slice(0, query.componentLimit);
  const cadence = cadenceFromRow(row);
  const activeUpNextEntries = rows.routineEntries
    .filter(
      (candidate) =>
        candidate.deletedAt === null && payloadString(candidate, "routine_id") === row.id
    )
    .map((entry) => routineEntryFromRow(entry, templatesById))
    .filter((entry) => !entry.workoutTemplateArchived && entry.slot !== null)
    .sort((left, right) => left.position - right.position || left.id.localeCompare(right.id));
  const activeLinkRows = rows.templateLinks
    .filter(
      (link) =>
        link.deletedAt === null &&
        payloadString(link, "routine_id") === row.id &&
        payloadNullableString(link, "workout_deleted_at") === null
    )
    .sort((left, right) => compareBinaryIds(left.id, right.id));
  const upNext =
    cadence === null
      ? null
      : deriveAgentRoutineUpNext({
          cadence,
          entries: activeUpNextEntries.map((entry) => ({
            routineEntryId: entry.id,
            workoutTemplateId: entry.workoutTemplateId,
            workoutTemplateName: entry.workoutTemplateName,
            slot: entry.slot!
          })),
          links: activeLinkRows
            .map((link, sequence) => templateLinkFact(link, sequence))
            .filter((link): link is AgentUpNextTemplateLinkFact => link !== null),
          selectedDate
        });

  return {
    id: row.id,
    name: payloadRequiredString(row, "name"),
    notes: payloadNullableString(row, "notes"),
    cadence,
    entries,
    slotLayout: cadence === null ? null : cadenceSlotLayout(cadence, activeUpNextEntries),
    upNext,
    entryLimit: query.componentLimit,
    entryCount: allEntries.length,
    entriesReturned: entries.length,
    entriesTruncated: entries.length < allEntries.length,
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  };
}

function routineEntryFromRow(row: OpaquePlanRow, templatesById: Map<string, OpaquePlanRow>) {
  const workoutTemplateId = payloadRequiredString(row, "workout_template_id");
  const template = templatesById.get(workoutTemplateId);
  return {
    id: row.id,
    routineId: payloadRequiredString(row, "routine_id"),
    workoutTemplateId,
    workoutTemplateName:
      template === undefined ? "Unknown Workout Template" : payloadRequiredString(template, "name"),
    workoutTemplateArchived: template === undefined || template.deletedAt !== null,
    position: payloadRequiredInteger(row, "position"),
    slot: payloadNullableInteger(row, "slot"),
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  };
}

function cadenceFromRow(
  row: OpaquePlanRow
): { kind: "weekly"; window: null } | { kind: "rotating"; window: number } | null {
  const kind = payloadNullableString(row, "cadence_kind");
  if (kind === null) {
    return null;
  }
  if (kind === "weekly") {
    return { kind, window: null };
  }
  return {
    kind: "rotating",
    window: payloadRequiredInteger(row, "cadence_window")
  };
}

function cadenceSlotLayout(
  cadence: { kind: "weekly"; window: null } | { kind: "rotating"; window: number },
  entries: ReturnType<typeof routineEntryFromRow>[]
) {
  const slotCount = cadence.kind === "weekly" ? 7 : cadence.window;
  return Array.from({ length: slotCount }, (_, index) => ({
    slot: index + 1,
    entries: entries.filter((entry) => entry.slot === index + 1)
  }));
}

function templateLinkFact(
  row: OpaquePlanRow,
  sequence: number
): AgentUpNextTemplateLinkFact | null {
  const slot = payloadNullableInteger(row, "slot");
  const workoutTemplateId = payloadString(row, "workout_template_id");
  if (slot === null || workoutTemplateId === null) {
    return null;
  }
  return {
    workoutTemplateId,
    slot,
    sequence,
    workoutLocalDate: payloadNullableString(row, "workout_local_date")
  };
}

function upNextCards(entries: readonly AgentUpNextRoutineEntry[], doneTemplateIds: Set<string>) {
  return [
    ...entries.filter((entry) => !doneTemplateIds.has(entry.workoutTemplateId)),
    ...entries.filter((entry) => doneTemplateIds.has(entry.workoutTemplateId))
  ].map((entry) => ({
    routineEntryId: entry.routineEntryId,
    workoutTemplateId: entry.workoutTemplateId,
    workoutTemplateName: entry.workoutTemplateName,
    slot: entry.slot,
    isDone: doneTemplateIds.has(entry.workoutTemplateId)
  }));
}

function isoWeekday(localDate: string) {
  const date = new Date(`${localDate}T00:00:00.000Z`);
  const weekday = date.getUTCDay();
  return weekday === 0 ? 7 : weekday;
}

function dimensionValue(row: OpaquePlanRow, prefix: string) {
  const value = payloadNullableNumber(row, `${prefix}_value`);
  const unit = payloadNullableString(row, `${prefix}_unit`);
  const entered = payloadNullableString(row, `${prefix}_entered`);
  return value === null && unit === null && entered === null ? null : { value, unit, entered };
}

function groupByParent(rows: OpaquePlanRow[], parentField: string): Map<string, OpaquePlanRow[]> {
  const grouped = new Map<string, OpaquePlanRow[]>();
  for (const row of rows) {
    const parentId = payloadString(row, parentField);
    if (parentId === null) {
      continue;
    }
    const children = grouped.get(parentId) ?? [];
    children.push(row);
    grouped.set(parentId, children);
  }
  return grouped;
}

function countActiveByParent(rows: OpaquePlanRow[], parentField: string): Map<string, number> {
  const counts = new Map<string, number>();
  for (const row of rows) {
    if (row.deletedAt !== null) {
      continue;
    }
    const parentId = payloadString(row, parentField);
    if (parentId !== null) {
      counts.set(parentId, (counts.get(parentId) ?? 0) + 1);
    }
  }
  return counts;
}

function payloadString(row: OpaquePlanRow, field: string): string | null {
  const value = row.payload[field];
  return typeof value === "string" && value.length > 0 ? value : null;
}

function payloadRequiredString(row: OpaquePlanRow, field: string): string {
  const value = payloadString(row, field);
  if (value === null) {
    throw new Error(`Plan row ${row.id} is missing ${field}.`);
  }
  return value;
}

function payloadNullableString(row: OpaquePlanRow, field: string): string | null {
  const value = row.payload[field];
  return typeof value === "string" ? value : null;
}

function payloadRequiredInteger(row: OpaquePlanRow, field: string): number {
  const value = row.payload[field];
  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw new Error(`Plan row ${row.id} has an invalid ${field}.`);
  }
  return value;
}

function payloadNullableInteger(row: OpaquePlanRow, field: string): number | null {
  const value = row.payload[field];
  return typeof value === "number" && Number.isInteger(value) ? value : null;
}

function payloadNullableNumber(row: OpaquePlanRow, field: string): number | null {
  const value = row.payload[field];
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function comparePositionedRows(left: OpaquePlanRow, right: OpaquePlanRow) {
  return (
    payloadRequiredInteger(left, "position") - payloadRequiredInteger(right, "position") ||
    left.id.localeCompare(right.id)
  );
}

function compareNamedRows(left: { id: string; name: string }, right: { id: string; name: string }) {
  return left.name.localeCompare(right.name) || left.id.localeCompare(right.id);
}

function compareBinaryIds(left: string, right: string) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function matchesSearch(name: string, search: string | undefined) {
  return (
    search === undefined ||
    name.toLocaleLowerCase("en-US").includes(search.toLocaleLowerCase("en-US"))
  );
}

function cursorOffset(rows: readonly { id: string }[], cursor: string | undefined) {
  if (cursor === undefined) {
    return 0;
  }
  const index = rows.findIndex((row) => row.id === cursor);
  if (index < 0) {
    throw new AgentPlanInvalidCursorError(cursor);
  }
  return index + 1;
}

function nextCursor(
  rows: readonly { id: string }[],
  start: number,
  page: readonly { id: string }[]
) {
  return start + page.length >= rows.length ? null : (page[page.length - 1]?.id ?? null);
}

function resolveWorkoutTemplateFields(raw: string | undefined) {
  return resolveFields(
    raw,
    AGENT_WORKOUT_TEMPLATE_LIST_FIELDS,
    AGENT_WORKOUT_TEMPLATE_DEFAULT_LIST_FIELDS
  );
}

function resolveRoutineFields(raw: string | undefined) {
  return resolveFields(raw, AGENT_ROUTINE_LIST_FIELDS, AGENT_ROUTINE_DEFAULT_LIST_FIELDS);
}

function resolveFields<T extends string>(
  raw: string | undefined,
  allowed: readonly T[],
  defaults: readonly T[]
): T[] {
  const requested =
    raw === undefined
      ? defaults
      : raw
          .split(",")
          .map((field) => field.trim())
          .filter((field): field is T => allowed.includes(field as T));
  return [...new Set<T>(["id", "name", ...requested] as T[])];
}

function projectFields<T extends Record<string, unknown>>(value: T, fields: readonly string[]) {
  return Object.fromEntries(fields.map((field) => [field, value[field]]));
}

function projectedFieldsQuery(fieldSet: Set<string>, entityName: string) {
  return z
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
      `fields must be a comma-separated list of known ${entityName} fields`
    )
    .openapi({
      param: { name: "fields", in: "query" },
      description:
        `Comma-separated ${entityName} fields. id and name are always returned; ` +
        "omitting fields uses the minimal default projection."
    });
}

function currentUtcLocalDate() {
  return new Date().toISOString().slice(0, 10);
}

function planListResponses(description: string, responseSchema: z.ZodType) {
  return {
    200: {
      description,
      content: { "application/json": { schema: responseSchema } }
    },
    400: {
      description: "The cursor is invalid or no longer resolves in the requested result set.",
      content: {
        "application/json": { schema: AgentPlanInvalidCursorResponseSchema }
      }
    },
    ...planReadCommonResponses()
  };
}

function planReadCommonResponses() {
  return {
    401: {
      description: "The request is missing a valid agent API key.",
      content: {
        "application/json": { schema: AgentUnauthorizedResponseSchema }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key or plan read storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentPlanReadUnavailableResponseSchema
          ])
        }
      }
    }
  };
}

function planDetailResponses(description: string, responseSchema: z.ZodType) {
  return {
    200: {
      description,
      content: { "application/json": { schema: responseSchema } }
    },
    ...planReadCommonResponses(),
    404: {
      description: "The requested plan entity is not visible to the caller.",
      content: {
        "application/json": { schema: AgentPlanNotFoundResponseSchema }
      }
    }
  };
}
