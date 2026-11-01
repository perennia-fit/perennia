// The Agent's Progress reads (docs/designs/progress-overview.md, D9): the same
// This week, Trained days and Time by Focus answers Progress Overview shows,
// computed on read by the shared training progress core and never stored.

import { createRoute, z } from "@hono/zod-openapi";
import { and, eq, gte, inArray, isNull, lte, sql } from "drizzle-orm";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import { payloadFocusId, type AgentCatalogStore } from "./agent-catalog.js";
import { isoWeekday, routineEntryFromRow } from "./agent-plan-reads.js";
import {
  AGENT_PROTOCOL_DAYS_MAX_RANGE_DAYS,
  LocalDateSchema,
  unionValues
} from "./agent-protocols.js";
import type { AgentSettingsReadStore } from "./agent-settings.js";
import {
  NO_FOCUS_KEY,
  summarizeTrainingWeek,
  trainingDays,
  trainingWeek,
  type ProgressWorkout,
  type TrainingDayStatus,
  type WeeklyPlan
} from "./analytics/training-progress.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import { epochDay, localDateFromEpochDay } from "./protocol-plan.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";

const TRAINING_DAY_STATUSES = unionValues<TrainingDayStatus>()([
  "done",
  "partly_done",
  "done_differently",
  "not_done",
  "pending",
  "planned",
  "trained",
  "rest",
  "no_plan"
]);

export const AgentTrainingDaysQuerySchema = z
  .object({
    fromLocalDate: LocalDateSchema.openapi({
      param: { name: "fromLocalDate", in: "query" },
      description: `Inclusive first local date (YYYY-MM-DD) of the range. The range holds at most ${AGENT_PROTOCOL_DAYS_MAX_RANGE_DAYS} days, both ends included.`
    }),
    toLocalDate: LocalDateSchema.openapi({
      param: { name: "toLocalDate", in: "query" },
      description:
        "Inclusive last local date (YYYY-MM-DD) of the range; not before fromLocalDate and not after today."
    }),
    today: LocalDateSchema.openapi({
      param: { name: "today", in: "query" },
      description:
        "The user's local date (YYYY-MM-DD), within one day of the server's UTC date. It picks the week the response's week describes, and which of that week's days are past, today or still to come."
    })
  })
  .openapi("AgentTrainingDaysQuery");

const AgentTrainingDayStatusSchema = z
  .enum(TRAINING_DAY_STATUSES)
  .openapi("AgentTrainingDayStatus", {
    description:
      "A day's Training Day Status against the weekly Routines: done (every planned workout done), partly_done, done_differently (only other Workouts), not_done, pending (today, not yet done), planned (a later day), trained (a Workout on a day nothing was planned), rest (nothing planned and nothing logged), or no_plan (no weekly Routine plans anything). Never a score."
  });

const AgentTrainingDaySchema = z
  .object({
    localDate: LocalDateSchema,
    workoutCount: z.number().int().min(0).openapi({
      description:
        "Logged Workouts on this date: Workouts with at least one completed Set, Open Workouts included. A date with one or more is a Trained Day."
    }),
    secondsByFocus: z.record(z.string(), z.number().int().min(0)).openapi({
      description: `Seconds of ended Logged Workouts on this date by Focus id (see GET /agent/focuses), with "${NO_FOCUS_KEY}" for Workouts without a Focus. An Open Workout adds no time and no key.`
    })
  })
  .openapi("AgentTrainingDay");

const AgentTrainingWeekDaySchema = z
  .object({
    localDate: LocalDateSchema,
    status: AgentTrainingDayStatusSchema,
    plannedCount: z.number().int().min(0).openapi({
      description: "Workouts the weekly Routines plan on this date."
    }),
    matchedCount: z.number().int().min(0).openapi({
      description:
        "Planned workouts done: each takes one Logged Workout of this date started from its Workout Template."
    }),
    workoutCount: z.number().int().min(0).openapi({
      description: "Logged Workouts on this date."
    })
  })
  .openapi("AgentTrainingWeekDay");

export const AgentTrainingDaysResponseSchema = z
  .object({
    days: z.array(AgentTrainingDaySchema).openapi({
      description: "One per date from fromLocalDate through toLocalDate, ascending."
    }),
    trainedDayCount: z.number().int().min(0).openapi({
      description: "The number of days with at least one Logged Workout."
    }),
    week: z
      .object({
        weekStart: LocalDateSchema.openapi({
          description:
            "First date of the week containing today, from the account's weekStartDay setting (Monday when unset)."
        }),
        days: z.array(AgentTrainingWeekDaySchema).length(7),
        counts: z
          .object({
            done: z.number().int().min(0),
            partlyDone: z.number().int().min(0),
            doneDifferently: z.number().int().min(0),
            notDone: z.number().int().min(0),
            trained: z.number().int().min(0)
          })
          .openapi({
            description:
              "Days of the week with each counted status. pending, planned, rest and no_plan are not counted, so an unfinished today never is."
          }),
        comparedRoutineIds: z.array(z.string().min(1)).openapi({
          description:
            "Ids of the weekly Routines that plan something, ascending. Rotating Routines are never compared; empty when no weekly Routine plans anything."
        })
      })
      .openapi({
        description:
          "This week against the weekly Routines as they are now, whatever the range."
      })
  })
  .openapi("AgentTrainingDaysResponse");

export const AgentProgressReadInvalidRangeResponseSchema = z
  .object({
    code: z.literal("agent_progress_read_invalid_range"),
    message: z.string().min(1)
  })
  .openapi("AgentProgressReadInvalidRangeResponse");

export const AgentProgressReadUnavailableResponseSchema = z
  .object({
    code: z.literal("agent_progress_read_unavailable"),
    message: z.string().min(1)
  })
  .openapi("AgentProgressReadUnavailableResponse");

export const agentTrainingDaysRoute = createRoute({
  method: "get",
  path: "/agent/progress/training-days",
  operationId: "listAgentTrainingDays",
  tags: ["Agent Reads"],
  summary: "List Trained Days and time per Focus over a range, and this week's Training Day Statuses.",
  description: `Returns one entry per local date from fromLocalDate through toLocalDate (both included, at most ${AGENT_PROTOCOL_DAYS_MAX_RANGE_DAYS} days, ending no later than today) with its Logged Workout count and seconds per Focus, the number of Trained Days, and the Training Day Status of each day of the week containing today against the weekly Routines. Only Workouts with at least one completed Set count. Computed on read by the same core the app's Progress Overview uses, never stored.`,
  security: [{ bearerAuth: [] }],
  request: { query: AgentTrainingDaysQuerySchema },
  responses: {
    200: {
      description: "The range's Trained Days and this week's statuses.",
      content: {
        "application/json": { schema: AgentTrainingDaysResponseSchema }
      }
    },
    400: {
      description:
        "The range is refused, with this body: fromLocalDate after toLocalDate, a range of more than " +
        `${AGENT_PROTOCOL_DAYS_MAX_RANGE_DAYS} days, toLocalDate after today, or a today more than one day from the server's UTC date. ` +
        "A query the request schema refuses, such as a date that is not a real YYYY-MM-DD date or a missing required parameter, is also answered 400, before authentication, in the request validator's own error body rather than this one.",
      content: {
        "application/json": { schema: AgentProgressReadInvalidRangeResponseSchema }
      }
    },
    401: {
      description: "The request is missing a valid agent API key.",
      content: {
        "application/json": { schema: AgentUnauthorizedResponseSchema }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key or progress read storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentProgressReadUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export type AgentTrainingDaysQuery = z.infer<typeof AgentTrainingDaysQuerySchema>;
export type AgentTrainingDaysResponse = z.infer<typeof AgentTrainingDaysResponseSchema>;

export type AgentProgressReadStore = {
  /**
   * The `listAgentTrainingDays` response. The route and the MCP tool run
   * `checkAgentProtocolDaysQuery` first; the store does not check the range.
   */
  readTrainingDays(input: {
    userId: string;
    from: string;
    to: string;
    today: string;
  }): Promise<AgentTrainingDaysResponse>;
};

export function createDrizzleAgentProgressReadStore({
  db,
  settingsStore
}: {
  db: ServerDatabase;
  settingsStore: AgentSettingsReadStore;
  /**
   * Not read by `readTrainingDays`. The store takes it at construction so the
   * exercise progress reads D9 adds resolve Set exercises through it.
   */
  catalogStore: AgentCatalogStore;
}): AgentProgressReadStore {
  return {
    async readTrainingDays({ userId, from, to, today }) {
      const { settings } = await settingsStore.readSettings({ userId });
      const weekStart = weekStartFor(today, settings.weekStartDay);
      const weekEnd = addDays(weekStart, 6);
      const [plans, workouts] = await Promise.all([
        loadWeeklyPlans(db, userId),
        loadProgressWorkouts(
          db,
          userId,
          from < weekStart ? from : weekStart,
          to > weekEnd ? to : weekEnd
        )
      ]);

      const days = trainingDays({ workouts, from, to });
      const week = trainingWeek({ plans, workouts, weekStart, today });
      return AgentTrainingDaysResponseSchema.parse({
        days,
        trainedDayCount: days.filter((day) => day.workoutCount > 0).length,
        week: { ...week, counts: summarizeTrainingWeek(week.days) }
      });
    }
  };
}

/**
 * One plan per live weekly Routine, from its live entries that have a slot and
 * a live Workout Template: the rule Up next and the app's loader apply (D1).
 * A weekly slot is the ISO weekday it plans.
 */
async function loadWeeklyPlans(db: ServerDatabase, userId: string): Promise<WeeklyPlan[]> {
  const routines = await db
    .select()
    .from(schema.routines)
    .where(
      and(
        eq(schema.routines.userId, userId),
        isNull(schema.routines.deletedAt),
        sql`${schema.routines.payload} ->> 'cadence_kind' = 'weekly'`
      )
    );
  if (routines.length === 0) {
    return [];
  }
  const entryRows = await db
    .select()
    .from(schema.routineEntries)
    .where(
      and(
        eq(schema.routineEntries.userId, userId),
        isNull(schema.routineEntries.deletedAt),
        inArray(
          sql`${schema.routineEntries.payload} ->> 'routine_id'`,
          routines.map((routine) => routine.id)
        )
      )
    );
  const templateIds = [
    ...new Set(
      entryRows
        .map((entry) => entry.payload.workout_template_id)
        .filter((id): id is string => typeof id === "string")
    )
  ];
  const templates =
    templateIds.length === 0
      ? []
      : await db
          .select()
          .from(schema.workoutTemplates)
          .where(
            and(
              eq(schema.workoutTemplates.userId, userId),
              isNull(schema.workoutTemplates.deletedAt),
              inArray(schema.workoutTemplates.id, templateIds)
            )
          );
  const templatesById = new Map(templates.map((template) => [template.id, template]));

  const entriesByRoutine = new Map<string, WeeklyPlan["entries"][number][]>();
  for (const row of entryRows) {
    const entry = routineEntryFromRow(row, templatesById);
    if (entry.workoutTemplateArchived || entry.slot === null) {
      continue;
    }
    const entries = entriesByRoutine.get(entry.routineId) ?? [];
    entries.push({ workoutTemplateId: entry.workoutTemplateId, weekday: entry.slot });
    entriesByRoutine.set(entry.routineId, entries);
  }
  return routines.map((routine) => ({
    routineId: routine.id,
    entries: entriesByRoutine.get(routine.id) ?? []
  }));
}

/**
 * The live Workouts dated `from` through `to` as `ProgressWorkout` facts (D0,
 * D1). `performedSetCount` counts live Sets whose payload `is_completed` is
 * true; a missing key is false, unlike the exercise analytics read's
 * `is_completed ?? true`.
 */
async function loadProgressWorkouts(
  db: ServerDatabase,
  userId: string,
  from: string,
  to: string
): Promise<ProgressWorkout[]> {
  const localDate = sql<string>`${schema.workoutSessions.payload} ->> 'local_date'`;
  const sessions = await db
    .select()
    .from(schema.workoutSessions)
    .where(
      and(
        eq(schema.workoutSessions.userId, userId),
        isNull(schema.workoutSessions.deletedAt),
        gte(localDate, from),
        lte(localDate, to)
      )
    );
  if (sessions.length === 0) {
    return [];
  }
  const workoutIds = sessions.map((session) => session.id);
  const setWorkoutId = sql<string>`${schema.loggedSets.payload} ->> 'workout_id'`;
  const [setCounts, links] = await Promise.all([
    db
      .select({ workoutId: setWorkoutId, count: sql<number>`count(*)::int` })
      .from(schema.loggedSets)
      .where(
        and(
          eq(schema.loggedSets.userId, userId),
          isNull(schema.loggedSets.deletedAt),
          sql`${schema.loggedSets.payload} -> 'is_completed' = 'true'::jsonb`,
          inArray(setWorkoutId, workoutIds)
        )
      )
      .groupBy(setWorkoutId),
    db
      .select()
      .from(schema.templateLinks)
      .where(
        and(
          eq(schema.templateLinks.userId, userId),
          isNull(schema.templateLinks.deletedAt),
          inArray(sql`${schema.templateLinks.payload} ->> 'workout_id'`, workoutIds)
        )
      )
  ]);

  const performedSetCounts = new Map(setCounts.map((row) => [row.workoutId, row.count]));
  // More than one live link per Workout is not enforced by the schema or
  // sync, so take the latest `updatedAt`, then the highest id, as the app does.
  const linkByWorkout = new Map<string, (typeof links)[number]>();
  for (const link of links) {
    const workoutId = link.payload.workout_id as string;
    const current = linkByWorkout.get(workoutId);
    if (
      current === undefined ||
      link.updatedAt.getTime() > current.updatedAt.getTime() ||
      (link.updatedAt.getTime() === current.updatedAt.getTime() && link.id > current.id)
    ) {
      linkByWorkout.set(workoutId, link);
    }
  }

  return sessions.map((session) => {
    const linkedTemplateId = linkByWorkout.get(session.id)?.payload.workout_template_id;
    return {
      workoutId: session.id,
      localDate: session.payload.local_date as string,
      startedAt: (dateValue(session.payload.started_at) ?? session.updatedAt).toISOString(),
      endedAt: dateValue(session.payload.ended_at)?.toISOString() ?? null,
      focusId: payloadFocusId(session.payload),
      linkedTemplateId:
        typeof linkedTemplateId === "string" && linkedTemplateId.length > 0
          ? linkedTemplateId
          : null,
      performedSetCount: performedSetCounts.get(session.id) ?? 0
    };
  });
}

/** The first date of the week holding `today`, as `AppSettings.weekStartFor` computes it. */
function weekStartFor(today: string, weekStartDay: "monday" | "sunday"): string {
  const startWeekday = weekStartDay === "sunday" ? 7 : 1;
  return addDays(today, -((isoWeekday(today) - startWeekday + 7) % 7));
}

function addDays(localDate: string, days: number): string {
  return localDateFromEpochDay(epochDay(localDate) + days);
}

function dateValue(value: unknown): Date | null {
  if (typeof value !== "string" || value.length === 0) {
    return null;
  }
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}
