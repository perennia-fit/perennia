import { createRoute, z } from "@hono/zod-openapi";
import { randomUUID } from "node:crypto";
import { isDeepStrictEqual } from "node:util";
import { and, asc, eq, isNull } from "drizzle-orm";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import {
  USER_PROFILE_SECTION_NAMES,
  isProfileRecord,
  validateUserProfileSection,
  type UserProfileSectionName,
  type UserProfileValidationIssue
} from "./agent-validation.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";
import {
  USER_PROFILE_SECTIONS_SYNC_ENTITY,
  normalizeIncomingUpdatedAt,
  pushUserProfileSectionsInTransaction,
  type SyncPushChange
} from "./sync.js";

// The agent surface of the User Profile (docs/designs/user-profile.md). Sections
// and fields are camelCase here and snake_case in the stored row and the shared
// validator; everything that crosses between the two goes through the maps below.

const ISO8601StringSchema = z.string().min(1).openapi({
  description: "ISO-8601 timestamp."
});

const NullableStringSchema = z.string().nullable();

const AgentProfileHeightSchema = z
  .object({
    value: z.number(),
    unit: z.string().openapi({
      description:
        '"cm" or "in", as entered. An unknown unit written by another client is returned as stored.'
    })
  })
  .openapi("AgentProfileHeight");

const AgentProfileExperienceEntrySchema = z
  .object({
    focusId: z.string().openapi({
      description:
        "See GET /agent/focuses; an id not listed there names an archived Focus."
    }),
    level: z.string().openapi({
      description: "beginner, intermediate or advanced."
    })
  })
  .openapi("AgentProfileExperienceEntry");

function profileSectionSchema<T extends z.ZodType>(name: string, values: T) {
  return z
    .object({
      values,
      updatedAt: ISO8601StringSchema.openapi({
        description: "Row update clock of this section."
      })
    })
    .nullable()
    .openapi(name, {
      description:
        "Null when the section has no row, or every field in its row is unset. In the values, null means unset."
    });
}

export const AgentProfileSchema = z
  .object({
    sections: z.object({
      aboutYou: profileSectionSchema(
        "AgentProfileAboutYouSection",
        z.object({
          sex: NullableStringSchema.openapi({
            description: "female or male, or null when not set."
          }),
          birthYear: z.number().int().nullable(),
          height: AgentProfileHeightSchema.nullable()
        })
      ),
      trainingGoals: profileSectionSchema(
        "AgentProfileTrainingGoalsSection",
        z.object({
          goals: z.array(z.string()).nullable().openapi({
            description:
              "Training Goal ids. An empty list means the user chose none; null means unset."
          })
        })
      ),
      experience: profileSectionSchema(
        "AgentProfileExperienceSection",
        z.object({
          levels: z.array(AgentProfileExperienceEntrySchema).nullable().openapi({
            description:
              "One entry per Focus. An empty list means the user chose none; null means unset."
          })
        })
      ),
      trainingSetup: profileSectionSchema(
        "AgentProfileTrainingSetupSection",
        z.object({
          equipment: z.array(z.string()).nullable().openapi({
            description:
              "Equipment ids. An empty list means bodyweight only; null means unset."
          }),
          daysPerWeek: z.number().int().nullable(),
          sessionMinutes: z.number().int().nullable()
        })
      ),
      healthLimitations: profileSectionSchema(
        "AgentProfileHealthLimitationsSection",
        z.object({
          text: NullableStringSchema,
          none: z.boolean().openapi({
            description: "True when the user said they have none."
          })
        })
      ),
      generalNotes: profileSectionSchema(
        "AgentProfileGeneralNotesSection",
        z.object({
          text: NullableStringSchema
        })
      )
    })
  })
  .openapi("AgentProfile");

// The request types fields at JSON level only. An unknown sex, goal, level or
// unit must reach the shared validator and come back as a 422 with its rule,
// which is the same verdict the app's editors give; only unknown keys, wrong JSON
// types and non-integers stop here, as the route's 400.
const AgentProfileWriteStringSchema = z.string().nullable().optional();
const AgentProfileWriteIntegerSchema = z.number().int().nullable().optional();

export const AgentProfileBatchWriteSectionsSchema = z
  .object({
    aboutYou: z
      .object({
        sex: AgentProfileWriteStringSchema,
        birthYear: AgentProfileWriteIntegerSchema,
        height: z
          .object({ value: z.number(), unit: z.string() })
          .strict()
          .nullable()
          .optional()
      })
      .strict()
      .optional(),
    trainingGoals: z
      .object({ goals: z.array(z.string()).nullable().optional() })
      .strict()
      .optional(),
    experience: z
      .object({
        levels: z
          .array(
            z.object({ focusId: z.string(), level: z.string() }).strict()
          )
          .nullable()
          .optional()
      })
      .strict()
      .optional(),
    trainingSetup: z
      .object({
        equipment: z.array(z.string()).nullable().optional(),
        daysPerWeek: AgentProfileWriteIntegerSchema,
        sessionMinutes: AgentProfileWriteIntegerSchema
      })
      .strict()
      .optional(),
    healthLimitations: z
      .object({
        text: AgentProfileWriteStringSchema,
        none: z.boolean().nullable().optional()
      })
      .strict()
      .optional(),
    generalNotes: z
      .object({ text: AgentProfileWriteStringSchema })
      .strict()
      .optional()
  })
  .strict()
  .openapi("AgentProfileBatchWriteSections");

export const AgentProfileBatchWriteRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200).openapi({
      description:
        "Stable key for this agent request. A replay with the same key appends no Batch and returns the current User Profile, with warnings recomputed from what the Batch wrote. A write that changed nothing reserves no key."
    }),
    updatedAt: ISO8601StringSchema.refine(
      (value) => !Number.isNaN(Date.parse(value)),
      "updatedAt must be an ISO-8601 timestamp"
    )
      .optional()
      .openapi({
        description:
          "Client-observed row update clock. Defaults to the server receive time when omitted."
      }),
    sections: AgentProfileBatchWriteSectionsSchema.openapi({
      description:
        "The fields to change, by section. A field left out is unchanged, null clears it, and a list replaces the whole list. At least one field is required."
    })
  })
  .strict()
  .refine(
    (request) =>
      Object.values(request.sections).some(
        (section) => section !== undefined && Object.keys(section).length > 0
      ),
    { message: "At least one field is required.", path: ["sections"] }
  )
  .openapi("AgentProfileBatchWriteRequest");

export const AgentProfileValidationIssueSchema = z
  .object({
    section: z.string().min(1).openapi({
      description: "Section that triggered the rule, for example aboutYou."
    }),
    field: z.string().min(1).openapi({
      description: "Field that triggered the rule, for example birthYear."
    }),
    rule: z.string().min(1).openapi({
      description: "Stable machine-readable validation rule id."
    }),
    message: z.string().min(1).openapi({
      description: "Human-readable explanation of the rule."
    })
  })
  .openapi("AgentProfileValidationIssue");

export const AgentProfileBatchWriteResponseSchema = z
  .object({
    accepted: z.literal(true),
    duplicate: z.boolean().openapi({
      description:
        "True when the idempotency key had already been applied and no new row or Activity Log entry was written."
    }),
    idempotencyKey: z.string().min(1),
    batchId: z.string().min(1).openapi({
      description:
        "Activity Log batch id. Equal to the idempotency key. A write that changed nothing appends no Batch, so this id then names none and can't be undone."
    }),
    serverClock: z.string().min(1),
    profile: AgentProfileSchema.openapi({
      description: "The User Profile as it reads after the write."
    }),
    warnings: z.array(AgentProfileValidationIssueSchema).openapi({
      description:
        "Improbable values that were saved anyway, to confirm with the user."
    })
  })
  .openapi("AgentProfileBatchWriteResponse");

export const AgentProfileBatchWriteErrorResponseSchema = z
  .object({
    code: z.literal("agent_profile_batch_write_failed"),
    message: z.string().min(1),
    errors: z.array(AgentProfileValidationIssueSchema)
  })
  .openapi("AgentProfileBatchWriteErrorResponse");

export const AgentProfileUnavailableResponseSchema = z
  .object({
    code: z.literal("agent_profile_unavailable"),
    message: z.string().min(1)
  })
  .openapi("AgentProfileUnavailableResponse");

export const agentProfileReadRoute = createRoute({
  method: "get",
  path: "/agent/profile",
  operationId: "readAgentProfile",
  tags: ["Agent Reads"],
  summary: "Read the caller's User Profile.",
  description:
    "Returns the six sections of the caller's User Profile: About you, Training Goals, Experience, Training setup, Health & limitations and General Notes. A section is null when it has no row or every field in its row is unset. Values are what the user entered, not medical advice.",
  security: [{ bearerAuth: [] }],
  responses: {
    200: {
      description: "The caller's User Profile.",
      content: {
        "application/json": {
          schema: AgentProfileSchema
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
      description: "Agent API key or User Profile storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentProfileUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export const agentProfileBatchWriteRoute = createRoute({
  method: "post",
  path: "/agent/profile/batch-write",
  operationId: "batchWriteAgentProfile",
  tags: ["Agent Writes"],
  summary: "Change User Profile fields as one Activity Log batch.",
  description:
    "Merges the given fields into each named section of the caller's User Profile, following the same Save semantics as the app: a field left out is unchanged, null clears a field, and a list replaces the whole list. Each merged section goes through the same shared two-tier validator the app uses. A hard reject writes nothing; improbable values are saved and returned as warnings. The write is one Activity Log batch, with a best-effort sync nudge; a write that changes nothing appends none.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: AgentProfileBatchWriteRequestSchema
        }
      }
    }
  },
  responses: {
    200: {
      description:
        "The write was accepted, or recognized as an idempotent replay.",
      content: {
        "application/json": {
          schema: AgentProfileBatchWriteResponseSchema
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
        "One or more merged sections failed hard validation; nothing was written.",
      content: {
        "application/json": {
          schema: AgentProfileBatchWriteErrorResponseSchema
        }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key or User Profile storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentProfileUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export type AgentProfile = z.infer<typeof AgentProfileSchema>;
export type AgentProfileBatchWriteRequest = z.infer<
  typeof AgentProfileBatchWriteRequestSchema
>;
export type AgentProfileBatchWriteResponse = z.infer<
  typeof AgentProfileBatchWriteResponseSchema
>;
export type AgentProfileValidationIssue = z.infer<
  typeof AgentProfileValidationIssueSchema
>;

export type AgentProfileStore = {
  read(input: { userId: string }): Promise<AgentProfile>;
  batchWrite(input: {
    userId: string;
    deviceId: string;
    request: AgentProfileBatchWriteRequest;
  }): Promise<
    | {
        accepted: true;
        duplicate: boolean;
        /** Whether a row changed, which is what a Sync Nudge is for. */
        applied: boolean;
        serverClock: string;
        profile: AgentProfile;
        warnings: AgentProfileValidationIssue[];
      }
    | {
        accepted: false;
        errors: AgentProfileValidationIssue[];
      }
  >;
};

type AgentSectionName = keyof AgentProfile["sections"];
type SectionValues = Record<string, unknown>;

/**
 * Keyed by section, so a section with no entry is a compile error. `fields` are
 * wire names in output order, and the read shape is serialised in that order.
 */
const PROFILE_SECTION_CONFIG: Readonly<
  Record<
    UserProfileSectionName,
    { agent: AgentSectionName; fields: readonly string[] }
  >
> = {
  about_you: { agent: "aboutYou", fields: ["sex", "birth_year", "height"] },
  training_goals: { agent: "trainingGoals", fields: ["goals"] },
  experience: { agent: "experience", fields: ["levels"] },
  training_setup: {
    agent: "trainingSetup",
    fields: ["equipment", "days_per_week", "session_minutes"]
  },
  health_limitations: { agent: "healthLimitations", fields: ["text", "none"] },
  general_notes: { agent: "generalNotes", fields: ["text"] }
};

/** In read order, which is also the order issues are reported in. */
const PROFILE_SECTIONS: readonly {
  wire: UserProfileSectionName;
  agent: AgentSectionName;
}[] = USER_PROFILE_SECTION_NAMES.map((wire) => ({
  wire,
  agent: PROFILE_SECTION_CONFIG[wire].agent
}));

const AGENT_FIELD_BY_WIRE_FIELD: Readonly<Record<string, string>> = {
  birth_year: "birthYear",
  days_per_week: "daysPerWeek",
  session_minutes: "sessionMinutes"
};

const WIRE_FIELD_BY_AGENT_FIELD: Readonly<Record<string, string>> =
  Object.fromEntries(
    Object.entries(AGENT_FIELD_BY_WIRE_FIELD).map(([wire, agent]) => [
      agent,
      wire
    ])
  );

type SectionRow = {
  id: string;
  payload: Record<string, unknown>;
  values: SectionValues;
  updatedAt: Date;
};

type QueryDatabase = Pick<ServerDatabase, "select">;

export function createDrizzleAgentProfileStore(
  db: ServerDatabase
): AgentProfileStore {
  return {
    read({ userId }) {
      return readProfile(db, userId);
    },
    async batchWrite({ userId, deviceId, request }) {
      const serverClock = new Date();
      const batchId = request.idempotencyKey;
      const referenceYear = serverClock.getUTCFullYear();

      return db.transaction(async (transaction) => {
        const existingBatchRows = await transaction
          .select({
            entityTable: schema.activityLog.entityTable,
            afterImage: schema.activityLog.afterImage
          })
          .from(schema.activityLog)
          .where(
            and(
              eq(schema.activityLog.userId, userId),
              eq(schema.activityLog.actor, "agent"),
              eq(schema.activityLog.batchId, batchId)
            )
          )
          .orderBy(
            asc(schema.activityLog.createdAt),
            asc(schema.activityLog.id)
          );

        if (existingBatchRows.length > 0) {
          return {
            accepted: true as const,
            duplicate: true,
            applied: false,
            serverClock: serverClock.toISOString(),
            profile: await readProfile(transaction, userId),
            warnings: warningsFromAfterImages(
              existingBatchRows,
              referenceYear
            )
          };
        }

        const newestRows = await readNewestSectionRows(transaction, userId);
        const updatedAt = normalizeIncomingUpdatedAt(
          new Date(request.updatedAt ?? serverClock.toISOString()),
          serverClock
        ).toISOString();

        const errors: AgentProfileValidationIssue[] = [];
        const warnings: AgentProfileValidationIssue[] = [];
        const changes: SyncPushChange[] = [];

        for (const { wire, agent } of PROFILE_SECTIONS) {
          const fields = request.sections[agent];
          // An empty section names no field, so it changes nothing.
          if (fields === undefined || Object.keys(fields).length === 0) {
            continue;
          }

          const existing = newestRows.get(wire);
          const merged = mergeSectionValues(
            wire,
            existing?.values ?? readSectionValues(wire, {}),
            toWireFields(fields)
          );
          const validation = validateUserProfileSection(wire, merged, {
            referenceYear
          });
          errors.push(...toAgentIssues(agent, validation.errors));
          warnings.push(...toAgentIssues(agent, validation.warnings));

          // A write that says nothing new stays off the record, as a device Save
          // does: a new Batch would make undo of the earlier one read as "changed
          // since" although no value changed. It is still validated above, so a
          // stored value the rules reject is reported and warnings are returned.
          if (
            existing === undefined
              ? isSectionUnset(wire, merged)
              : isDeepStrictEqual(merged, existing.values)
          ) {
            continue;
          }

          const rowId = existing?.id ?? randomUUID();
          const payload = {
            id: rowId,
            section: wire,
            values: merged,
            updated_at: updatedAt,
            deleted_at: null
          };
          changes.push({
            id: rowId,
            payload,
            updatedAt,
            deletedAt: null,
            activityLogId: `agent:${batchId}:${rowId}`,
            actor: "agent",
            batchId,
            beforeImage: existing?.payload ?? null,
            // `updatedAt` above is already the clock the push stores, so this
            // deep-equals the stored row. Undo compares the two, and reports a
            // difference as a later change.
            afterImage: payload,
            occurredAt: updatedAt
          });
        }

        if (errors.length > 0) {
          return { accepted: false as const, errors };
        }

        let applied = false;
        if (changes.length > 0) {
          const result = await pushUserProfileSectionsInTransaction(
            transaction,
            { userId, deviceId, changes, serverClock }
          );
          applied = result.applied.length > 0;
        }

        return {
          accepted: true as const,
          duplicate: false,
          applied,
          serverClock: serverClock.toISOString(),
          profile: await readProfile(transaction, userId),
          warnings
        };
      });
    }
  };
}

async function readProfile(
  db: QueryDatabase,
  userId: string
): Promise<AgentProfile> {
  const newestRows = await readNewestSectionRows(db, userId);
  const sections: Record<string, unknown> = {};
  for (const { wire, agent } of PROFILE_SECTIONS) {
    const row = newestRows.get(wire);
    sections[agent] =
      row === undefined || isSectionUnset(wire, row.values)
        ? null
        : {
            values: toAgentValues(wire, row.values),
            updatedAt: row.updatedAt.toISOString()
          };
  }
  return AgentProfileSchema.parse({ sections });
}

/**
 * The newest live row per section: the greatest `updated_at`, then the greatest
 * `id`, matching agent-nutrition-goals.ts. Older rows stay in the table, unread.
 */
async function readNewestSectionRows(
  db: QueryDatabase,
  userId: string
): Promise<Map<UserProfileSectionName, SectionRow>> {
  const rows = await db
    .select({
      id: schema.userProfileSections.id,
      payload: schema.userProfileSections.payload,
      updatedAt: schema.userProfileSections.updatedAt
    })
    .from(schema.userProfileSections)
    .where(
      and(
        eq(schema.userProfileSections.userId, userId),
        isNull(schema.userProfileSections.deletedAt)
      )
    )
    .orderBy(
      asc(schema.userProfileSections.updatedAt),
      asc(schema.userProfileSections.id)
    );

  const newest = new Map<UserProfileSectionName, SectionRow>();
  for (const row of rows) {
    const section = readSectionName(row.payload);
    if (section !== null) {
      newest.set(section, {
        ...row,
        values: readSectionValues(section, row.payload.values)
      });
    }
  }
  return newest;
}

function readSectionName(
  image: Record<string, unknown> | null
): UserProfileSectionName | null {
  const section = image?.section;
  return (
    PROFILE_SECTIONS.find(({ wire }) => wire === section)?.wire ?? null
  );
}

/**
 * Reads a stored section tolerantly. Push does no domain validation, so a row can
 * hold anything: a field of the wrong JSON type reads as null, and unknown string
 * ids are kept for the agent to see. Keys this version doesn't know are kept, so
 * a later whole-row write can't erase what a newer client wrote.
 */
function readSectionValues(
  section: UserProfileSectionName,
  values: unknown
): SectionValues {
  const raw: SectionValues = isProfileRecord(values) ? values : {};
  switch (section) {
    case "about_you":
      return {
        ...raw,
        sex: readString(raw.sex),
        birth_year: readInteger(raw.birth_year),
        height: readHeight(raw.height)
      };
    case "training_goals":
      return { ...raw, goals: readStringList(raw.goals) };
    case "experience":
      return { ...raw, levels: readLevels(raw.levels) };
    case "training_setup":
      return {
        ...raw,
        equipment: readStringList(raw.equipment),
        days_per_week: readInteger(raw.days_per_week),
        session_minutes: readInteger(raw.session_minutes)
      };
    case "health_limitations": {
      // A stored `none: true` wins over any text in the same row, as it does in
      // a save, so no reader sees both.
      const none = raw.none === true;
      return { ...raw, text: none ? null : readString(raw.text), none };
    }
    case "general_notes":
      return { ...raw, text: readString(raw.text) };
  }
}

function readString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function readInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isSafeInteger(value)
    ? value
    : null;
}

function readHeight(value: unknown): { value: number; unit: string } | null {
  if (!isProfileRecord(value)) {
    return null;
  }
  const { value: amount, unit } = value;
  return typeof amount === "number" &&
    Number.isFinite(amount) &&
    typeof unit === "string"
    ? { value: amount, unit }
    : null;
}

function readStringList(value: unknown): string[] | null {
  return Array.isArray(value)
    ? value.filter((entry): entry is string => typeof entry === "string")
    : null;
}

function readLevels(
  value: unknown
): { focus_id: string; level: string }[] | null {
  if (!Array.isArray(value)) {
    return null;
  }
  const levels: { focus_id: string; level: string }[] = [];
  for (const entry of value) {
    if (
      isProfileRecord(entry) &&
      typeof entry.focus_id === "string" &&
      typeof entry.level === "string"
    ) {
      levels.push({ focus_id: entry.focus_id, level: entry.level });
    }
  }
  return levels;
}

function toWireFields(fields: Record<string, unknown>): SectionValues {
  const changes: SectionValues = {};
  for (const [field, value] of Object.entries(fields)) {
    if (value === undefined) {
      continue;
    }
    changes[WIRE_FIELD_BY_AGENT_FIELD[field] ?? field] =
      field === "levels" && Array.isArray(value)
        ? value.map(({ focusId, level }: { focusId: string; level: string }) => ({
            focus_id: focusId,
            level
          }))
        : value;
  }
  return changes;
}

/**
 * Merges a write into a section's tolerantly read values, following Save
 * semantics: a field left out is unchanged, null clears it, and a list replaces
 * the whole list. Twins the Dart `mergeUserProfileSectionValues`, including the
 * Health & limitations normalisation: `none: true` wins over text in one write,
 * new text clears `none`, and an explicit `none: null` means false.
 *
 * A stored value the rules would reject stays in the merge, so the validator
 * reports it and the whole write gets a 422 naming that field. Only pushes can
 * store one. Dropping it here would erase a value the write never named, so the
 * agent clears or corrects it itself (docs/designs/user-profile.md, Agent surface).
 */
function mergeSectionValues(
  section: UserProfileSectionName,
  current: SectionValues,
  changes: SectionValues
): SectionValues {
  const merged: SectionValues = { ...current, ...changes };
  if (section === "health_limitations") {
    if (changes.none === true) {
      merged.text = null;
    } else if (changes.text !== undefined && changes.text !== null) {
      merged.none = false;
    }
    if (changes.none === null) {
      merged.none = false;
    }
  }
  return merged;
}

/** Whether no field says anything. An empty list is a choice, so it says something. */
function isSectionUnset(
  section: UserProfileSectionName,
  values: SectionValues
): boolean {
  return PROFILE_SECTION_CONFIG[section].fields.every((field) =>
    field === "none" ? values.none !== true : values[field] === null
  );
}

function toAgentValues(
  section: UserProfileSectionName,
  values: SectionValues
): SectionValues {
  const agentValues: SectionValues = {};
  for (const field of PROFILE_SECTION_CONFIG[section].fields) {
    agentValues[AGENT_FIELD_BY_WIRE_FIELD[field] ?? field] =
      field === "levels"
        ? ((values.levels as { focus_id: string; level: string }[] | null)?.map(
            ({ focus_id: focusId, level }) => ({ focusId, level })
          ) ?? null)
        : values[field];
  }
  return agentValues;
}

function toAgentIssues(
  section: AgentSectionName,
  issues: readonly UserProfileValidationIssue[]
): AgentProfileValidationIssue[] {
  return issues.map(({ field, rule, message }) => ({
    section,
    field: AGENT_FIELD_BY_WIRE_FIELD[field] ?? field,
    rule,
    message
  }));
}

/**
 * The warnings of a replayed Batch. Nothing stores the original response, so they
 * are recomputed from what the Batch wrote, section by section in read order.
 */
function warningsFromAfterImages(
  entries: readonly {
    entityTable: string;
    afterImage: Record<string, unknown> | null;
  }[],
  referenceYear: number
): AgentProfileValidationIssue[] {
  return PROFILE_SECTIONS.flatMap(({ wire, agent }) =>
    entries
      .filter(
        (entry) =>
          entry.entityTable === USER_PROFILE_SECTIONS_SYNC_ENTITY &&
          readSectionName(entry.afterImage) === wire
      )
      .flatMap((entry) =>
        toAgentIssues(
          agent,
          validateUserProfileSection(
            wire,
            readSectionValues(wire, entry.afterImage?.values),
            { referenceYear }
          ).warnings
        )
      )
  );
}
