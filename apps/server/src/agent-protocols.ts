import { createRoute, z } from "@hono/zod-openapi";
import { and, asc, eq, inArray, isNull, or, sql, type SQL } from "drizzle-orm";

import {
  agentBatchRequestFingerprint,
  claimAgentBatchReceipt,
  scopedAgentBatchReceiptId
} from "./agent-batch-receipt.js";
import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import { createUuidV7 } from "./agent-plan-materialize.js";
import {
  AgentDoseValidationIssueSchema,
  AgentDoseValidationLimitsSchema,
  DOSE_ROUTES,
  DOSE_UNITS,
  doseValidationLimitsResponse,
  validateAgentDose,
  validateAgentProtocolPeriod,
  validateAgentScheduleRule,
  type AgentDoseValidationIssue,
  type AgentDoseValidationResult
} from "./agent-validation.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import {
  MS_PER_DAY,
  ProtocolPlanCodecError,
  applyingScheduleVersion,
  compareIds,
  compareScheduleVersions,
  dayStatuses,
  decodeProtocolPeriod,
  decodeScheduleRule,
  encodeScheduleRule,
  epochDay,
  isJsonObject,
  isValidLocalDate,
  planDays,
  pushToGroup,
  type DayStatus,
  type DayStatusValue,
  type NotPlannedReason,
  type PlanAmount,
  type PlanDay,
  type PlanDayState,
  type PlanDose,
  type PlanProtocol,
  type ProtocolPeriod,
  type ScheduleRule
} from "./protocol-plan.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";
import {
  COMPOUNDS_SYNC_ENTITY,
  DOSES_SYNC_ENTITY,
  PROTOCOLS_SYNC_ENTITY,
  PROTOCOL_COMPOUNDS_SYNC_ENTITY,
  PROTOCOL_TARGET_OUTCOMES_SYNC_ENTITY,
  SCHEDULES_SYNC_ENTITY,
  pushCompoundsInTransaction,
  pushDosesInTransaction,
  pushProtocolCompoundsInTransaction,
  pushProtocolsInTransaction,
  pushProtocolTargetOutcomesInTransaction,
  pushSchedulesInTransaction,
  type SyncPushChange,
  type SyncPushResult
} from "./sync.js";
import { offsetMinutesInTimezone } from "./timezone.js";

// Bounded-read page sizing (data-minimizing by default).
export const AGENT_PROTOCOLS_DEFAULT_PAGE_LIMIT = 50;
export const AGENT_PROTOCOLS_MAX_PAGE_LIMIT = 200;

// Batch-write item caps (mirror the meal/exercise catalogue caps).
export const AGENT_DOSE_BATCH_WRITE_MAX_DOSES = 200;
export const AGENT_COMPOUND_BATCH_WRITE_MAX_COMPOUNDS = 100;
export const AGENT_PROTOCOL_BATCH_WRITE_MAX_PROTOCOLS = 50;
export const AGENT_PROTOCOL_BATCH_WRITE_MAX_MEMBERS = 100;
export const AGENT_PROTOCOL_BATCH_WRITE_MAX_SCHEDULES = 100;
export const AGENT_PROTOCOL_BATCH_WRITE_MAX_TARGET_OUTCOMES = 50;

// Effect-window bucketing bounds — a descriptive read, never stored.
export const AGENT_EFFECT_WINDOW_MAX_DOSES = 500;

const ISO8601StringSchema = z.string().min(1).openapi({
  description: "ISO-8601 timestamp."
});

const DoseUnitSchema = z.string().min(1).openapi({
  description: "Dose amount unit drawn from the curated registry.",
  enum: [...DOSE_UNITS]
});

const DoseRouteSchema = z.string().min(1).openapi({
  description: "Dose administration route drawn from the curated registry.",
  enum: [...DOSE_ROUTES]
});

const ProvenanceSchema = z
  .enum(["manual", "integration", "agent"])
  .openapi("AgentProtocolsProvenance");

const UUID_V7_PATTERN =
  /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-7[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/;

const ClientUuidV7Schema = z.string().regex(UUID_V7_PATTERN).openapi({
  description: "Client-supplied UUIDv7 row id for a newly authored row."
});

const ClientRowIdSchema = z
  .union([
    ClientUuidV7Schema,
    z.string().trim().min(1).openapi({
      description:
        "Existing legacy row id. Accepted only when editing or archiving a row that already belongs to this account."
    })
  ])
  .openapi("AgentProtocolsClientRowId");

const AgentProtocolsReferenceIdSchema = z.string().trim().min(1).openapi({
  description:
    "Reference to a UUIDv7 row, or to an existing legacy row owned by this account."
});

const AGENT_PROTOCOLS_BATCH_ENTITY = "agent_protocol_batches";

// ---------------------------------------------------------------------------
// Read item shapes (the self-describing synced row projected for an agent).
// Every field is a plain neutral descriptor — no substance type/legality
// categorization exists anywhere in the model, so none appears here.
// ---------------------------------------------------------------------------

const AGENT_COMPOUND_FIELDS = [
  "id",
  "name",
  "defaultUnit",
  "defaultRoute",
  "strength",
  "updatedAt",
  "deletedAt"
] as const;

const AGENT_DOSE_FIELDS = [
  "id",
  "compoundId",
  "compoundName",
  "compoundStrength",
  "amountValue",
  "amountEntered",
  "unit",
  "route",
  "tookAt",
  "timezone",
  "timezoneOffsetMinutes",
  "localDate",
  "provenance",
  "protocolId",
  "protocolName",
  "updatedAt",
  "deletedAt"
] as const;

const compoundFieldSet = new Set<string>(AGENT_COMPOUND_FIELDS);
const doseFieldSet = new Set<string>(AGENT_DOSE_FIELDS);

const DOSE_TIMEZONE_DESCRIPTION =
  "Display label for the timezone the Dose was logged in, as captured at log time: an IANA name such as America/Sao_Paulo, or an abbreviation such as BRT. It is a label only; timezoneOffsetMinutes is what turns tookAt into the Dose's local clock time.";

const DoseTimezoneOffsetReadSchema = z.number().int().nullable().openapi({
  description:
    "UTC offset in minutes east of UTC (UTC-3 is -180), frozen when the Dose was logged. Null for a Dose logged without one; its local time is then read in UTC."
});

/**
 * The UTC offsets a frozen Dose offset, the Effect read and
 * `effectBoundsFromLocalDates` accept (D2): UTC-12:00 to UTC+14:00.
 */
const AGENT_PROTOCOLS_MIN_OFFSET_MINUTES = -720;
const AGENT_PROTOCOLS_MAX_OFFSET_MINUTES = 840;

export const LocalDateSchema = z
  .string()
  .refine(isValidLocalDate, { message: "Must be a real YYYY-MM-DD date." })
  .openapi({
    description: "A local calendar date, YYYY-MM-DD.",
    example: "2026-10-26"
  });

// ---------------------------------------------------------------------------
// Schedule Rule and Protocol Period JSON (docs/designs/protocol-schedules-and-
// reminders.md, "Data shapes"). Agents read and write the stored JSON itself,
// with its snake_case keys, so what an Agent sends is exactly what the shared
// codecs and the two-tier validators (D7) judge in both languages. These
// schemas pin only the JSON types and the version and kinds; every value
// (a time of "9:00", an anchor of "2026-02-30", a count of 2.5) is judged by
// the shared validators and comes back as a 422 issue with its stable rule id.
// ---------------------------------------------------------------------------

const ScheduleRuleDaysSchema = z
  .discriminatedUnion("kind", [
    z.object({ kind: z.literal("daily") }),
    z.object({
      kind: z.literal("weekdays"),
      weekdays: z.array(z.number()).openapi({
        description: "ISO 8601 weekdays, 1 = Monday to 7 = Sunday. Stored sorted."
      })
    }),
    z.object({
      kind: z.literal("every_n_days"),
      n: z.number().openapi({ description: "Due every n days, 2 to 365." }),
      anchor: z.string().openapi({
        description:
          "YYYY-MM-DD date the rhythm is counted from; a date is due when (date - anchor) mod n = 0, before the anchor too."
      }),
      anchor_is_default: z.boolean().openapi({
        description:
          "True when the anchor is left at its default: it is read as the Protocol's startLocalDate, whatever date is stored, so it follows the start without a write."
      })
    })
  ])
  .openapi("AgentScheduleRuleDays");

export const AgentScheduleRuleSchema = z
  .discriminatedUnion("kind", [
    z.object({
      v: z.literal(1),
      kind: z.literal("timed"),
      days: ScheduleRuleDaysSchema,
      times: z.array(z.string()).openapi({
        description: "1 to 12 distinct HH:MM wall-clock times. Stored sorted."
      })
    }),
    z.object({
      v: z.literal(1),
      kind: z.literal("untimed"),
      days: ScheduleRuleDaysSchema,
      count: z.number().openapi({
        description: "1 to 12 planned doses a day with no clock time."
      })
    }),
    z.object({ v: z.literal(1), kind: z.literal("as_needed") }),
    z.object({ v: z.literal(1), kind: z.literal("unscheduled") })
  ])
  .openapi("AgentScheduleRule", {
    description:
      "A Schedule Rule, version 1: when a Protocol Member's Compound is due on a day its Protocol is in effect. timed and untimed rules need a planned amount, unit and route; as_needed plans nothing; unscheduled is a member with no Schedule, and both carry no amount."
  });

export const AgentProtocolPeriodSchema = z
  .object({
    v: z.literal(1),
    cycle: z
      .object({
        on_days: z.number().openapi({ description: "Days on, 1 to 3650." }),
        off_days: z.number().openapi({ description: "Days off, 1 to 3650." }),
        anchor: z.string().openapi({
          description:
            "YYYY-MM-DD date that is cycle day 0; a date is on-cycle when (date - anchor) mod (on + off) < on, before the anchor too."
        }),
        anchor_is_default: z.boolean().openapi({
          description:
            "True when the anchor is left at its default: it is read as the Protocol's startLocalDate, whatever date is stored, so it follows the start without a write."
        })
      })
      .nullable()
      .optional(),
    pauses: z
      .array(
        z.object({
          from: z.string().openapi({ description: "First paused YYYY-MM-DD date." }),
          to: z.string().openapi({ description: "Last paused YYYY-MM-DD date, inclusive." })
        })
      )
      .openapi({
        description: "At most 100 non-overlapping Pauses inside the Protocol's dates."
      })
  })
  .openapi("AgentProtocolPeriod", {
    description:
      "A Protocol Period, version 1: an optional on/off cycle and the Pauses. Null means no cycle and no Pause."
  });

const AgentCompoundStrengthSchema = z
  .object({
    value: z.number().openapi({
      description: "Strength/concentration magnitude (e.g. 5 for 5 mg/capsule)."
    }),
    massUnit: z.string().min(1).openapi({
      description: "Active-mass unit the strength resolves to (e.g. milligram)."
    }),
    perUnit: z.string().min(1).openapi({
      description: "The dose unit the strength is expressed per (e.g. capsule)."
    })
  })
  .openapi("AgentCompoundStrength");

export const AgentCompoundSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1),
    defaultUnit: DoseUnitSchema,
    defaultRoute: DoseRouteSchema,
    strength: AgentCompoundStrengthSchema.nullable(),
    updatedAt: ISO8601StringSchema,
    deletedAt: ISO8601StringSchema.nullable()
  })
  .openapi("AgentCompound");

const AgentCompoundListItemSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1),
    defaultUnit: DoseUnitSchema.optional(),
    defaultRoute: DoseRouteSchema.optional(),
    strength: AgentCompoundStrengthSchema.nullable().optional(),
    updatedAt: ISO8601StringSchema.optional(),
    deletedAt: ISO8601StringSchema.nullable().optional()
  })
  .openapi("AgentCompoundListItem");

const AgentCompoundFieldSchema = z
  .enum(AGENT_COMPOUND_FIELDS)
  .openapi("AgentCompoundField");

export const AgentDoseSchema = z
  .object({
    id: z.string().min(1),
    compoundId: z.string().min(1).nullable(),
    compoundName: z.string().min(1),
    compoundStrength: AgentCompoundStrengthSchema.nullable(),
    amountValue: z.number(),
    amountEntered: z.string().min(1),
    unit: DoseUnitSchema,
    route: DoseRouteSchema,
    tookAt: ISO8601StringSchema,
    timezone: z.string().min(1).openapi({
      description: DOSE_TIMEZONE_DESCRIPTION
    }),
    timezoneOffsetMinutes: DoseTimezoneOffsetReadSchema,
    localDate: z.string().min(1),
    provenance: z.string().min(1),
    protocolId: z.string().min(1).nullable(),
    protocolName: z.string().min(1).nullable(),
    updatedAt: ISO8601StringSchema,
    deletedAt: ISO8601StringSchema.nullable()
  })
  .openapi("AgentDose");

const AgentDoseListItemSchema = z
  .object({
    id: z.string().min(1),
    compoundId: z.string().min(1).nullable().optional(),
    compoundName: z.string().min(1).optional(),
    compoundStrength: AgentCompoundStrengthSchema.nullable().optional(),
    amountValue: z.number().optional(),
    amountEntered: z.string().min(1).optional(),
    unit: DoseUnitSchema.optional(),
    route: DoseRouteSchema.optional(),
    tookAt: ISO8601StringSchema.optional(),
    timezone: z.string().min(1).optional().openapi({
      description: DOSE_TIMEZONE_DESCRIPTION
    }),
    timezoneOffsetMinutes: DoseTimezoneOffsetReadSchema.optional(),
    localDate: z.string().min(1).optional(),
    provenance: z.string().min(1).optional(),
    protocolId: z.string().min(1).nullable().optional(),
    protocolName: z.string().min(1).nullable().optional(),
    updatedAt: ISO8601StringSchema.optional(),
    deletedAt: ISO8601StringSchema.nullable().optional()
  })
  .openapi("AgentDoseListItem");

const AgentDoseFieldSchema = z.enum(AGENT_DOSE_FIELDS).openapi("AgentDoseField");

// A Protocol detail bundles its plan rows (members, schedules, target outcomes)
// — all plan data, never derived analytics.
const AgentProtocolScheduleVersionSchema = z
  .object({
    id: z.string().min(1),
    protocolCompoundId: z.string().min(1),
    effectiveFrom: z.string().min(1).openapi({
      description:
        "Local date (YYYY-MM-DD) this Schedule Version applies from. On any date the version with the latest effectiveFrom on or before it applies, the larger id on a tie."
    }),
    rule: AgentScheduleRuleSchema,
    doseAmountValue: z.number().nullable(),
    doseAmountEntered: z.string().min(1).nullable(),
    doseUnit: DoseUnitSchema.nullable(),
    route: DoseRouteSchema.nullable(),
    updatedAt: ISO8601StringSchema
  })
  .openapi("AgentProtocolScheduleVersion");

const AgentProtocolMemberSchema = z
  .object({
    id: z.string().min(1),
    compoundId: z.string().min(1),
    position: z.number().int().min(0),
    archivedOn: z.string().min(1).nullable().openapi({
      description:
        "Local date (YYYY-MM-DD) the member was removed, frozen when it was archived. The member is still planned that day, and reads removed from the next."
    }),
    versions: z.array(AgentProtocolScheduleVersionSchema).openapi({
      description:
        "Every Schedule Version of this member, sorted by effectiveFrom and then id. Versions are authored plan history, inserted on every changed save and never edited."
    }),
    currentVersion: AgentProtocolScheduleVersionSchema.nullable().openapi({
      description:
        "The version an editor shows: the latest effectiveFrom, the larger id on a tie. Null when the member has no Schedule Version."
    }),
    updatedAt: ISO8601StringSchema,
    deletedAt: ISO8601StringSchema.nullable()
  })
  .openapi("AgentProtocolMember");

const AgentProtocolTargetOutcomeSchema = z
  .object({
    id: z.string().min(1),
    metricId: z.string().min(1).nullable(),
    // Not the write's enum: the write accepted any string until
    // docs/designs/protocol-target-outcome-sync-shape.md (D4), and one old row
    // with another kind must not fail the read for the whole account.
    outcomeKind: z.string().min(1).openapi({
      description:
        "metric (a Metric, named by metricId) or performance (Workout analytics broadly). An outcome an Agent stored before the kind was checked may hold another value; the app ignores it."
    }),
    position: z.number().int().min(0).openapi({
      description:
        "The outcome's place in the Protocol's list, as the app orders it. Outcomes are listed by position, then id."
    }),
    updatedAt: ISO8601StringSchema,
    deletedAt: ISO8601StringSchema.nullable()
  })
  .openapi("AgentProtocolTargetOutcome");

export const AgentProtocolSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1),
    startLocalDate: z.string().min(1).nullable().openapi({
      description: "Local date (YYYY-MM-DD) the Protocol starts."
    }),
    endLocalDate: z.string().min(1).nullable().openapi({
      description: "Inclusive local end date (YYYY-MM-DD); null is ongoing."
    }),
    period: AgentProtocolPeriodSchema.nullable(),
    remindersEnabled: z.boolean().openapi({
      description:
        "Plan data: the user asked to be reminded about this Protocol. Reminders themselves are device-local."
    }),
    archivedOn: z.string().min(1).nullable().openapi({
      description:
        "Local date (YYYY-MM-DD) the Protocol was archived, frozen when it was archived. Past days still count it through this date."
    }),
    updatedAt: ISO8601StringSchema,
    deletedAt: ISO8601StringSchema.nullable(),
    members: z.array(AgentProtocolMemberSchema),
    targetOutcomes: z.array(AgentProtocolTargetOutcomeSchema)
  })
  .openapi("AgentProtocol");

// ---------------------------------------------------------------------------
// Read query schemas
// ---------------------------------------------------------------------------

const limitQuery = z.coerce
  .number()
  .int()
  .min(1)
  .max(AGENT_PROTOCOLS_MAX_PAGE_LIMIT)
  .default(AGENT_PROTOCOLS_DEFAULT_PAGE_LIMIT);

export const AgentCompoundListQuerySchema = z
  .object({
    search: z.string().trim().min(1).optional().openapi({
      param: { name: "search", in: "query" },
      description: "Optional case-insensitive Compound name filter."
    }),
    includeArchived: z.coerce.boolean().default(false).openapi({
      param: { name: "includeArchived", in: "query" },
      description: "When true, archived Compounds are included."
    }),
    limit: limitQuery.openapi({
      param: { name: "limit", in: "query" },
      description: "Maximum Compound rows to return."
    }),
    cursor: z.string().trim().min(1).optional().openapi({
      param: { name: "cursor", in: "query" },
      description: "Opaque cursor returned by the previous page."
    }),
    fields: fieldsQuery(compoundFieldSet, "Compound").openapi({
      param: { name: "fields", in: "query" },
      description:
        "Comma-separated Compound fields to return. id and name are always returned; omit for the full row."
    })
  })
  .openapi("AgentCompoundListQuery");

export const AgentProtocolListQuerySchema = z
  .object({
    search: z.string().trim().min(1).optional().openapi({
      param: { name: "search", in: "query" },
      description: "Optional case-insensitive Protocol name filter."
    }),
    includeArchived: z.coerce.boolean().default(false).openapi({
      param: { name: "includeArchived", in: "query" },
      description: "When true, archived Protocols are included."
    }),
    limit: limitQuery.openapi({
      param: { name: "limit", in: "query" },
      description: "Maximum Protocol rows to return."
    }),
    cursor: z.string().trim().min(1).optional().openapi({
      param: { name: "cursor", in: "query" },
      description: "Opaque cursor returned by the previous page."
    })
  })
  .openapi("AgentProtocolListQuery");

export const AgentDoseListQuerySchema = z
  .object({
    compoundId: z.string().trim().min(1).optional().openapi({
      param: { name: "compoundId", in: "query" },
      description: "Optional Compound id filter."
    }),
    protocolId: z.string().trim().min(1).optional().openapi({
      param: { name: "protocolId", in: "query" },
      description: "Optional Protocol tag filter."
    }),
    from: z.string().trim().min(1).optional().openapi({
      param: { name: "from", in: "query" },
      description: "Optional inclusive ISO-8601 lower bound on the Dose time."
    }),
    to: z.string().trim().min(1).optional().openapi({
      param: { name: "to", in: "query" },
      description: "Optional inclusive ISO-8601 upper bound on the Dose time."
    }),
    provenance: z.string().trim().min(1).optional().openapi({
      param: { name: "provenance", in: "query" },
      description: "Optional Provenance filter."
    }),
    includeArchived: z.coerce.boolean().default(false).openapi({
      param: { name: "includeArchived", in: "query" },
      description: "When true, archived (tombstoned) Doses are included."
    }),
    limit: limitQuery.openapi({
      param: { name: "limit", in: "query" },
      description: "Maximum Dose rows to return."
    }),
    cursor: z.string().trim().min(1).optional().openapi({
      param: { name: "cursor", in: "query" },
      description: "Opaque cursor returned by the previous page."
    }),
    fields: fieldsQuery(doseFieldSet, "Dose").openapi({
      param: { name: "fields", in: "query" },
      description:
        "Comma-separated Dose fields to return. id is always returned; omit for the full row."
    })
  })
  .openapi("AgentDoseListQuery");

export const AgentCompoundListResponseSchema = z
  .object({
    compounds: z.array(AgentCompoundListItemSchema),
    fields: z.array(AgentCompoundFieldSchema),
    limit: z.number().int().min(1).max(AGENT_PROTOCOLS_MAX_PAGE_LIMIT),
    nextCursor: z.string().min(1).nullable(),
    totalMatched: z.number().int().min(0)
  })
  .openapi("AgentCompoundListResponse");

export const AgentProtocolListResponseSchema = z
  .object({
    protocols: z.array(AgentProtocolSchema),
    limit: z.number().int().min(1).max(AGENT_PROTOCOLS_MAX_PAGE_LIMIT),
    nextCursor: z.string().min(1).nullable(),
    totalMatched: z.number().int().min(0)
  })
  .openapi("AgentProtocolListResponse");

export const AgentDoseListResponseSchema = z
  .object({
    doses: z.array(AgentDoseListItemSchema),
    fields: z.array(AgentDoseFieldSchema),
    limit: z.number().int().min(1).max(AGENT_PROTOCOLS_MAX_PAGE_LIMIT),
    nextCursor: z.string().min(1).nullable(),
    totalMatched: z.number().int().min(0)
  })
  .openapi("AgentDoseListResponse");

// ---------------------------------------------------------------------------
// Write request shapes — payloads are exactly the synced row shapes so devices
// pull agent writes as ordinary edits (mirrors the meal/exercise batch writes).
// ---------------------------------------------------------------------------

const CompoundStrengthInputSchema = z
  .object({
    value: z.number(),
    massUnit: z.string().trim().min(1),
    perUnit: z.string().trim().min(1)
  })
  .openapi("AgentCompoundStrengthInput");

export const AgentCompoundBatchWriteCompoundSchema = z
  .object({
    id: ClientRowIdSchema.openapi({
      description:
        "UUIDv7 Compound id for a new row, or an existing legacy id for an edit/archive."
    }),
    name: z.string().trim().min(1),
    defaultUnit: DoseUnitSchema,
    defaultRoute: DoseRouteSchema,
    strength: CompoundStrengthInputSchema.nullable().default(null),
    updatedAt: ISO8601StringSchema.optional(),
    deletedAt: ISO8601StringSchema.nullable().default(null).openapi({
      description:
        "Set to archive the Compound (a tombstone). Logged Doses keep their self-describing snapshot; archiving never cascades."
    })
  })
  .openapi("AgentCompoundBatchWriteCompound");

export const AgentCompoundBatchWriteRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200).openapi({
      description:
        "Stable key for this agent request. Replays with the same key do not append another Activity Log batch."
    }),
    compounds: z
      .array(AgentCompoundBatchWriteCompoundSchema)
      .min(1)
      .max(AGENT_COMPOUND_BATCH_WRITE_MAX_COMPOUNDS)
      .openapi({
        description: "Compounds to create, edit, or archive in one batch."
      })
  })
  .openapi("AgentCompoundBatchWriteRequest");

export const AgentDoseBatchWriteDoseSchema = z
  .object({
    id: ClientRowIdSchema.openapi({
      description:
        "UUIDv7 Dose id for a new row, or an existing legacy id for an edit/archive."
    }),
    compoundId: AgentProtocolsReferenceIdSchema.nullable().default(null).openapi({
      description:
        "Optional Compound id the Dose was logged from. New references use UUIDv7; an existing account-owned legacy Compound id remains valid. The Dose is self-describing regardless (compoundName/compoundStrength snapshot)."
    }),
    compoundName: z.string().trim().min(1).openapi({
      description: "Compound name snapshotted at log time (self-describing)."
    }),
    compoundStrength: CompoundStrengthInputSchema.nullable().default(null),
    amount: z.union([z.string(), z.number()]).openapi({
      description: "Dose amount as entered. Validated by the shared dose validator."
    }),
    unit: DoseUnitSchema,
    route: DoseRouteSchema,
    tookAt: ISO8601StringSchema.openapi({
      description: "Instant the Dose was taken (its timezone is captured separately)."
    }),
    timezone: z.string().trim().min(1).openapi({
      description:
        "Display label for the timezone at log time: an IANA name such as America/Sao_Paulo, or an abbreviation such as BRT. When it is an IANA name and timezoneOffsetMinutes is absent, the server derives the offset from it and tookAt; an abbreviation cannot be converted, so the offset then stays null."
    }),
    timezoneOffsetMinutes: z
      .number()
      .int()
      .min(AGENT_PROTOCOLS_MIN_OFFSET_MINUTES)
      .max(AGENT_PROTOCOLS_MAX_OFFSET_MINUTES)
      .optional()
      .openapi({
        description:
          "Optional UTC offset at log time, in minutes east of UTC (UTC-3 is -180), -720 to +840. Frozen on the Dose with tookAt so its local clock time never moves. Wins over the offset derived from timezone."
      }),
    localDate: z.string().trim().min(1).openapi({
      description:
        "Protocol Day date (YYYY-MM-DD) the Dose falls on in its local timezone, frozen at log time."
    }),
    protocolId: AgentProtocolsReferenceIdSchema.nullable().default(null).openapi({
      description:
        "Optional Protocol tag. New references use UUIDv7; an existing account-owned legacy Protocol id remains valid. Never required (ad-hoc Doses are allowed)."
    }),
    protocolName: z.string().trim().min(1).nullable().default(null).openapi({
      description: "Protocol name snapshotted at log time when tagged."
    }),
    updatedAt: ISO8601StringSchema.optional(),
    deletedAt: ISO8601StringSchema.nullable().default(null).openapi({
      description:
        "Nullable tombstone. A Dose is user log — hard-deletes to a tombstone, recoverable via the Activity Log; never a purge."
    })
  })
  .openapi("AgentDoseBatchWriteDose");

export const AgentDoseBatchWriteRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200).openapi({
      description:
        "Stable key for this agent request. Replays with the same key do not append another Activity Log batch."
    }),
    doses: z
      .array(AgentDoseBatchWriteDoseSchema)
      .min(1)
      .max(AGENT_DOSE_BATCH_WRITE_MAX_DOSES)
      .openapi({
        description:
          "Doses to log, edit, or tombstone atomically as one Activity Log batch. Each is validated by the shared two-tier dose validator."
      })
  })
  .openapi("AgentDoseBatchWriteRequest");

const ArchivedFlagSchema = z.boolean().default(false);

const AgentProtocolBatchWriteMemberSchema = z
  .object({
    id: ClientRowIdSchema.openapi({
      description:
        "UUIDv7 Protocol Member id for a new row, or an existing id for an edit or archive."
    }),
    compoundId: AgentProtocolsReferenceIdSchema,
    position: z.number().int().min(0).default(0),
    updatedAt: ISO8601StringSchema.optional(),
    archived: ArchivedFlagSchema.openapi({
      description:
        "Set to true to remove the member from the Protocol. The server stamps the archive with the current time and freezes archivedOn as the request's today; the member is still planned that day. Its Schedule Versions are kept. A removed member is never restored: adding the Compound again is a new member row."
    })
  })
  .strict()
  .openapi("AgentProtocolBatchWriteMember");

const AgentProtocolBatchWriteScheduleSchema = z
  .object({
    id: ClientRowIdSchema.openapi({
      description:
        "UUIDv7 id of a new Schedule Version. Versions are insert-only: an id that already exists is rejected."
    }),
    protocolCompoundId: AgentProtocolsReferenceIdSchema.openapi({
      description:
        "The Protocol Member this Schedule Version belongs to: one in this request, or an existing member of the same Protocol."
    }),
    rule: AgentScheduleRuleSchema,
    doseAmountValue: z.number().nullable().default(null),
    doseAmountEntered: z.string().nullable().default(null),
    doseUnit: DoseUnitSchema.nullable().default(null),
    route: DoseRouteSchema.nullable().default(null),
    updatedAt: ISO8601StringSchema.optional()
  })
  .strict()
  .openapi("AgentProtocolBatchWriteSchedule", {
    description:
      "A new Schedule Version for one Protocol Member. The server dates it (effectiveFrom) exactly as the app does: a member's first version applies from the Protocol's start when the member is created with its Protocol or the start is still ahead, and from today otherwise; a later version applies from the later of today and the member's latest effectiveFrom. times and weekdays are stored sorted. Every edit is a new version; none is edited or archived."
  });

const AgentProtocolBatchWriteTargetOutcomeSchema = z
  .object({
    id: ClientRowIdSchema.openapi({
      description:
        "UUIDv7 target-outcome id for a new row, or an existing legacy id for an edit/archive."
    }),
    metricId: z.string().trim().min(1).nullable().default(null).openapi({
      description:
        "Optional Metric id. Metric ids are opaque and may be canonical catalogue ids rather than Protocol-row UUIDv7 values."
    }),
    outcomeKind: z.enum(["metric", "performance"]).default("metric").openapi({
      description:
        "metric (a Metric, named by metricId) or performance (Workout analytics broadly; metricId null). A metric outcome without a metricId, or a performance outcome with one, is refused with target_outcome_metric_id."
    }),
    position: z.number().int().min(0).optional().openapi({
      description:
        "The outcome's place in the Protocol's list. Left out, an existing outcome keeps its position and a new one goes after the Protocol's other outcomes, in the order sent."
    }),
    updatedAt: ISO8601StringSchema.optional(),
    deletedAt: ISO8601StringSchema.nullable().default(null)
  })
  .openapi("AgentProtocolBatchWriteTargetOutcome");

export const AgentProtocolBatchWriteProtocolSchema = z
  .object({
    id: ClientRowIdSchema.openapi({
      description:
        "UUIDv7 Protocol id for a new row, or an existing id for an edit or archive."
    }),
    name: z.string().trim().min(1),
    startLocalDate: LocalDateSchema.openapi({
      description:
        "Local date (YYYY-MM-DD) the Protocol starts. Moving it earlier inserts, for each member planned from the old start (archived ones included), a copy of its earliest Schedule Version dated from the new start; a member added after the old start keeps its own first date. Moving it later inserts nothing. Every-N and cycle anchors left at their default (anchor_is_default: true) are read as this date, so they follow the start without a write."
    }),
    endLocalDate: LocalDateSchema.nullable().default(null).openapi({
      description: "Inclusive local end date (YYYY-MM-DD); null is ongoing."
    }),
    period: AgentProtocolPeriodSchema.nullable().default(null),
    remindersEnabled: z.boolean().default(false).openapi({
      description:
        "Plan data: remind me about this Protocol. Each device schedules its own reminders. Left out, it is written as false."
    }),
    updatedAt: ISO8601StringSchema.optional(),
    archived: ArchivedFlagSchema.openapi({
      description:
        "Set to true to archive the Protocol. The server stamps the archive with the current time and freezes archivedOn as the request's today; past days still count the Protocol through that date. Archiving is a plan edit: it never cascades to a logged Dose, and an archived Protocol is never restored."
    }),
    members: z
      .array(AgentProtocolBatchWriteMemberSchema)
      .max(AGENT_PROTOCOL_BATCH_WRITE_MAX_MEMBERS)
      .default([]),
    schedules: z
      .array(AgentProtocolBatchWriteScheduleSchema)
      .max(AGENT_PROTOCOL_BATCH_WRITE_MAX_SCHEDULES)
      .default([]),
    targetOutcomes: z
      .array(AgentProtocolBatchWriteTargetOutcomeSchema)
      .max(AGENT_PROTOCOL_BATCH_WRITE_MAX_TARGET_OUTCOMES)
      .default([])
  })
  .strict()
  .openapi("AgentProtocolBatchWriteProtocol", {
    description:
      "One Protocol as it should be stored. The write replaces the whole Protocol row, so a field left out takes its default: endLocalDate and period become null (no end, no cycle, no Pauses) and remindersEnabled becomes false. To edit one field, send every field as read."
  });

export const AgentProtocolBatchWriteRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200).openapi({
      description:
        "Stable key for this agent request. Replays with the same key do not append another Activity Log batch."
    }),
    today: LocalDateSchema.openapi({
      description:
        "The user's local date (YYYY-MM-DD). It dates Schedule Versions and archives exactly as the app does, and must be within one day of the server's UTC date."
    }),
    protocols: z
      .array(AgentProtocolBatchWriteProtocolSchema)
      .min(1)
      .max(AGENT_PROTOCOL_BATCH_WRITE_MAX_PROTOCOLS)
      .openapi({
        description:
          "Protocols (plus their members, Schedule Versions, and target outcomes) to create, edit, or archive. Plan writes never touch logged Doses."
      })
  })
  .strict()
  .openapi("AgentProtocolBatchWriteRequest");

// ---------------------------------------------------------------------------
// Write issue + response shapes
// ---------------------------------------------------------------------------

export const AgentDoseBatchWriteIssueSchema = AgentDoseValidationIssueSchema.extend(
  {
    itemIndex: z.number().int().min(0),
    doseId: z.string().min(1)
  }
).openapi("AgentDoseBatchWriteIssue");

export const AgentProtocolsBatchWriteIssueSchema = z
  .object({
    field: z.string().min(1),
    rule: z.string().min(1),
    message: z.string().min(1),
    itemIndex: z.number().int().min(0),
    entityId: z.string().min(1).nullable()
  })
  .openapi("AgentProtocolsBatchWriteIssue");

const AgentDoseBatchWriteResultSchema = z
  .object({
    id: z.string().min(1),
    compoundName: z.string().min(1),
    outcome: z.enum(["applied", "superseded", "duplicate", "refused"]),
    warnings: z.array(AgentDoseValidationIssueSchema)
  })
  .openapi("AgentDoseBatchWriteResult");

const AgentEntityBatchWriteResultSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1).nullable(),
    outcome: z.enum(["applied", "superseded", "duplicate", "refused"])
  })
  .openapi("AgentProtocolsEntityBatchWriteResult");

export const AgentDoseBatchWriteResponseSchema = z
  .object({
    accepted: z.literal(true),
    duplicate: z.boolean(),
    idempotencyKey: z.string().min(1),
    batchId: z.string().min(1),
    serverClock: z.string().min(1),
    doses: z.array(AgentDoseBatchWriteResultSchema)
  })
  .openapi("AgentDoseBatchWriteResponse");

export const AgentCompoundBatchWriteResponseSchema = z
  .object({
    accepted: z.literal(true),
    duplicate: z.boolean(),
    idempotencyKey: z.string().min(1),
    batchId: z.string().min(1),
    serverClock: z.string().min(1),
    compounds: z.array(AgentEntityBatchWriteResultSchema)
  })
  .openapi("AgentCompoundBatchWriteResponse");

export const AgentProtocolBatchWriteResponseSchema = z
  .object({
    accepted: z.literal(true),
    duplicate: z.boolean(),
    idempotencyKey: z.string().min(1),
    batchId: z.string().min(1),
    serverClock: z.string().min(1),
    protocols: z.array(AgentEntityBatchWriteResultSchema),
    warnings: z.array(AgentProtocolsBatchWriteIssueSchema).openapi({
      description:
        "Soft warnings from the shared plan validators (an improbable plan, such as more than 6 times a day). The batch was still written."
    })
  })
  .openapi("AgentProtocolBatchWriteResponse");

export const AgentDoseBatchWriteErrorResponseSchema = z
  .object({
    code: z.literal("agent_dose_batch_write_failed"),
    message: z.string().min(1),
    errors: z.array(AgentDoseBatchWriteIssueSchema),
    warnings: z.array(AgentDoseBatchWriteIssueSchema),
    limits: AgentDoseValidationLimitsSchema
  })
  .openapi("AgentDoseBatchWriteErrorResponse");

export const AgentProtocolsBatchWriteErrorResponseSchema = z
  .object({
    code: z.literal("agent_protocols_batch_write_failed"),
    message: z.string().min(1),
    errors: z.array(AgentProtocolsBatchWriteIssueSchema),
    warnings: z.array(AgentProtocolsBatchWriteIssueSchema)
  })
  .openapi("AgentProtocolsBatchWriteErrorResponse");

export const AgentProtocolsUnavailableResponseSchema = z
  .object({
    code: z.literal("agent_protocols_unavailable"),
    message: z.string().min(1)
  })
  .openapi("AgentProtocolsUnavailableResponse");

// ---------------------------------------------------------------------------
// Effect-window read shapes (descriptive only, never stored — /0034)
// ---------------------------------------------------------------------------

export const AgentEffectWindowQuerySchema = z
  .object({
    compoundId: z.string().trim().min(1).optional().openapi({
      param: { name: "compoundId", in: "query" },
      description:
        "The Compound whose logged Doses (earliest to latest) are the DURING span. Provide exactly one of compoundId or protocolId."
    }),
    protocolId: z.string().trim().min(1).optional().openapi({
      param: { name: "protocolId", in: "query" },
      description:
        "The Protocol whose local start and end dates (read at timezoneOffsetMinutes) are the DURING span; its tagged Doses are returned as markers. Provide exactly one of compoundId or protocolId."
    }),
    metricId: z.string().trim().min(1).optional().openapi({
      param: { name: "metricId", in: "query" },
      description:
        "The outcome Metric to summarize. Provide exactly one of metricId or metricKey."
    }),
    metricKey: z.string().trim().min(1).optional().openapi({
      param: { name: "metricKey", in: "query" },
      description:
        "The outcome Metric by name/key. Provide exactly one of metricId or metricKey."
    }),
    from: z.string().trim().min(1).openapi({
      param: { name: "from", in: "query" },
      description:
        "Inclusive ISO-8601 lower bound of the Dose markers returned. Does not move the window."
    }),
    to: z.string().trim().min(1).openapi({
      param: { name: "to", in: "query" },
      description:
        "Exclusive ISO-8601 upper bound of the Dose markers returned. Does not move the window."
    }),
    timezoneOffsetMinutes: z.coerce
      .number()
      .int()
      .min(AGENT_PROTOCOLS_MIN_OFFSET_MINUTES)
      .max(AGENT_PROTOCOLS_MAX_OFFSET_MINUTES)
      .default(0)
      .openapi({
        param: { name: "timezoneOffsetMinutes", in: "query" },
        description:
          "UTC offset, in minutes east of UTC (UTC-3 is -180), from -720 to +840, that turns a Protocol's local-date bounds into instants: DURING runs from local midnight of its start date to local midnight after its inclusive end date. Defaults to 0 (UTC). Ignored for a Compound source."
      })
  })
  .openapi("AgentEffectWindowQuery");

const AgentEffectAggregateSchema = z
  .object({
    count: z.number().int().min(0),
    min: z.number().nullable(),
    max: z.number().nullable(),
    mean: z.number().nullable()
  })
  .openapi("AgentEffectAggregate");

const AgentEffectDoseMarkerSchema = z
  .object({
    doseId: z.string().min(1),
    compoundName: z.string().min(1),
    amountValue: z.number(),
    unit: DoseUnitSchema,
    route: DoseRouteSchema,
    tookAt: ISO8601StringSchema
  })
  .openapi("AgentEffectDoseMarker");

export const AgentEffectWindowResponseSchema = z
  .object({
    source: z
      .object({
        kind: z.enum(["compound", "protocol"]),
        id: z.string().min(1)
      })
      .openapi("AgentEffectWindowSource"),
    metric: z
      .object({
        id: z.string().min(1),
        name: z.string().min(1),
        unit: z.string().min(1)
      })
      .openapi("AgentEffectWindowMetric"),
    range: z.object({ from: ISO8601StringSchema, to: ISO8601StringSchema }),
    window: z
      .object({
        duringStart: ISO8601StringSchema.nullable(),
        duringEnd: ISO8601StringSchema.nullable()
      })
      .openapi("AgentEffectWindowSpan"),
    doses: z.array(AgentEffectDoseMarkerSchema),
    segments: z
      .object({
        before: AgentEffectAggregateSchema,
        during: AgentEffectAggregateSchema,
        after: AgentEffectAggregateSchema
      })
      .openapi("AgentEffectWindowSegments"),
    descriptiveOnly: z.literal(true).openapi({
      description:
        "Always true: this is a descriptive before/during/after summary, never a causal, efficacy, or medical claim, and nothing here is stored."
    })
  })
  .openapi("AgentEffectWindowResponse");

export const AgentEffectWindowErrorResponseSchema = z
  .object({
    code: z.literal("agent_effect_window_invalid_request"),
    message: z.string().min(1)
  })
  .openapi("AgentEffectWindowErrorResponse");

// ---------------------------------------------------------------------------
// Planned-day and Day Status reads (docs/designs/protocol-schedules-and-
// reminders.md, D6 "Later stage"). Both are computed on read by the shared
// plan core (protocol-plan.ts, the twin of the app's Dart core, pinned by the
// m36 vectors), so an Agent and the app give the same answer for a day.
// Nothing here is stored, and the responses carry statuses and counts only:
// no ratio, streak or percentage.
// ---------------------------------------------------------------------------

/**
 * The longest range either read accepts, in days, both ends included: the
 * same 366 the app's Consistency view reads at most
 * (`maxConsistencyRangeDays`).
 */
export const AGENT_PROTOCOL_DAYS_MAX_RANGE_DAYS = 366;

/**
 * Every value of the string union `T`, as a tuple `z.enum` takes. It is
 * checked both ways at compile time: a value the union lacks fails the
 * element type, and a union value the tuple leaves out fails the `missing`
 * check. So when the shared core gains a state or status, this module stops
 * compiling instead of the response schema refusing the core's output with a
 * 500 at run time.
 */
export function unionValues<T extends string>() {
  return <const V extends readonly [T, ...T[]]>(
    values: V & ([Exclude<T, V[number]>] extends [never] ? unknown : { missing: Exclude<T, V[number]> })
  ): V => values;
}

const PLAN_DAY_STATES = unionValues<PlanDayState>()([
  "planned",
  "not_scheduled_today",
  "as_needed",
  "no_schedule",
  "removed",
  "outside",
  "paused",
  "off_cycle"
]);

const DAY_STATUS_VALUES = unionValues<DayStatusValue>()([
  "not_planned",
  "paused",
  "off_cycle",
  "pending",
  "logged",
  "partly_logged",
  "not_logged"
]);

const NOT_PLANNED_REASONS = unionValues<NotPlannedReason>()([
  "not_scheduled_today",
  "as_needed",
  "no_schedule",
  "removed",
  "outside"
]);

const AgentProtocolDaysRangeQuerySchema = z.object({
  fromLocalDate: LocalDateSchema.openapi({
    param: { name: "fromLocalDate", in: "query" },
    description: `Inclusive first local date (YYYY-MM-DD) of the range. The range holds at most ${AGENT_PROTOCOL_DAYS_MAX_RANGE_DAYS} days, both ends included.`
  }),
  toLocalDate: LocalDateSchema.openapi({
    param: { name: "toLocalDate", in: "query" },
    description: "Inclusive last local date (YYYY-MM-DD) of the range; not before fromLocalDate."
  }),
  compoundId: z.string().trim().min(1).optional().openapi({
    param: { name: "compoundId", in: "query" },
    description:
      "Optional Compound id: only this Compound's days. An unknown id returns an empty list."
  }),
  protocolId: z.string().trim().min(1).optional().openapi({
    param: { name: "protocolId", in: "query" },
    description:
      "Optional Protocol id: only this Protocol's plan is read. An unknown id returns an empty list."
  })
});

export const AgentProtocolPlannedDaysQuerySchema = AgentProtocolDaysRangeQuerySchema.openapi(
  "AgentProtocolPlannedDaysQuery"
);

export const AgentProtocolDayStatusesQuerySchema = AgentProtocolDaysRangeQuerySchema.extend({
  today: LocalDateSchema.openapi({
    param: { name: "today", in: "query" },
    description:
      "The user's local date (YYYY-MM-DD), within one day of the server's UTC date. It decides Pending against Not logged, and toLocalDate must not be after it: a day still to come has no Day Status."
  }),
  detail: z
    .enum(["summary", "doses"])
    .default("summary")
    .openapi({
      param: { name: "detail", in: "query" },
      description:
        "summary (the default) returns each Day Status's status and counts; doses also returns its fills, the planned dose each logged Dose filled."
    })
}).openapi("AgentProtocolDayStatusesQuery");

const PlanLocalTimeReadSchema = z.string().min(1).openapi({
  description: "A wall-clock time, HH:MM."
});

const PlanAmountReadFields = {
  amountValue: z.number().nullable(),
  amountEntered: z.string().nullable(),
  unit: DoseUnitSchema.nullable(),
  route: DoseRouteSchema.nullable()
};

const AgentProtocolPlannedDoseSchema = z
  .object({
    localTime: PlanLocalTimeReadSchema.nullable().openapi({
      description: "The planned wall-clock time, HH:MM; null for an untimed planned dose (any time that day)."
    }),
    ...PlanAmountReadFields
  })
  .openapi("AgentProtocolPlannedDose");

const AgentProtocolPlannedDaySchema = z
  .object({
    protocolId: z.string().min(1),
    compoundId: z.string().min(1),
    localDate: z.string().min(1),
    state: z
      .enum(PLAN_DAY_STATES)
      .openapi({
        description:
          "What the Protocol planned for the Compound that day: planned, or why nothing was (not scheduled that day, as needed, no Schedule, member removed, outside the Protocol's dates, paused, or off cycle)."
      }),
    planned: z.array(AgentProtocolPlannedDoseSchema).openapi({
      description: "The planned doses, non-empty exactly when state is planned, in the rule's stored order."
    })
  })
  .openapi("AgentProtocolPlannedDay");

export const AgentProtocolPlannedDaysResponseSchema = z
  .object({
    fromLocalDate: z.string().min(1),
    toLocalDate: z.string().min(1),
    plannedDays: z.array(AgentProtocolPlannedDaySchema).openapi({
      description:
        "One entry per Protocol, Compound and date of the range, for every Compound with a member row in that Protocol, ordered by date, then Protocol id, then Compound id."
    })
  })
  .openapi("AgentProtocolPlannedDaysResponse");

const AgentProtocolDayStatusFillSchema = z
  .object({
    slot: z.number().int().min(0),
    protocolId: z.string().min(1),
    plannedLocalTime: PlanLocalTimeReadSchema.nullable().openapi({
      description: "The slot's planned time, HH:MM; null for an untimed slot."
    }),
    ...PlanAmountReadFields,
    doseId: z.string().min(1).nullable().openapi({
      description: "The logged Dose that filled this slot; null when it is unfilled."
    })
  })
  .openapi("AgentProtocolDayStatusFill");

const AgentProtocolDayStatusSchema = z
  .object({
    compoundId: z.string().min(1),
    localDate: z.string().min(1),
    status: z
      .enum(DAY_STATUS_VALUES)
      .openapi({
        description:
          "One per Compound and date, summed across the Protocols read: every Protocol in effect, or with protocolId only that Protocol, whose planned doses alone are then matched against the Compound's Doses (so for a Compound also in another Protocol it can differ from the app's Day Status, which sums them all). pending is today with planned doses still unfilled."
      }),
    notPlannedReason: z
      .enum(NOT_PLANNED_REASONS)
      .optional()
      .openapi({ description: "Present exactly when status is not_planned." }),
    plannedCount: z.number().int().min(0),
    loggedCount: z.number().int().min(0).openapi({
      description: "Filled planned doses; never more than plannedCount."
    }),
    extraCount: z.number().int().min(0).openapi({
      description: "Logged Doses that filled no planned dose. Extras never change the status."
    }),
    fills: z.array(AgentProtocolDayStatusFillSchema).optional().openapi({
      description: "Only with detail=doses: every planned dose (slot), in slot order, with the Dose that filled it."
    })
  })
  .openapi("AgentProtocolDayStatus");

export const AgentProtocolDayStatusesResponseSchema = z
  .object({
    fromLocalDate: z.string().min(1),
    toLocalDate: z.string().min(1),
    today: z.string().min(1),
    detail: z.enum(["summary", "doses"]),
    dayStatuses: z.array(AgentProtocolDayStatusSchema).openapi({
      description:
        "One per Compound and date that has at least one planned day in the plan read, ordered by date, then Compound id. A Compound in no Protocol read has none."
    })
  })
  .openapi("AgentProtocolDayStatusesResponse");

export const AgentProtocolDaysInvalidRequestResponseSchema = z
  .object({
    code: z.literal("agent_protocol_days_invalid_request"),
    message: z.string().min(1)
  })
  .openapi("AgentProtocolDaysInvalidRequestResponse");

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

function readResponses401_503() {
  return {
    401: {
      description: "The request is missing a valid agent API key.",
      content: {
        "application/json": { schema: AgentUnauthorizedResponseSchema }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key or Protocols storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentProtocolsUnavailableResponseSchema
          ])
        }
      }
    }
  };
}

export const agentCompoundListRoute = createRoute({
  method: "get",
  path: "/agent/protocols/compounds",
  operationId: "listAgentCompounds",
  tags: ["Agent Reads"],
  summary: "List the caller's Compounds.",
  description:
    "Returns a bounded, data-minimizing page of the caller's Compound library. A Compound is a neutral tracking template — the model never categorizes it by type or legality.",
  security: [{ bearerAuth: [] }],
  request: { query: AgentCompoundListQuerySchema },
  responses: {
    200: {
      description: "A bounded page of Compounds.",
      content: {
        "application/json": { schema: AgentCompoundListResponseSchema }
      }
    },
    ...readResponses401_503()
  }
});

export const agentProtocolListRoute = createRoute({
  method: "get",
  path: "/agent/protocols",
  operationId: "listAgentProtocols",
  tags: ["Agent Reads"],
  summary: "List the caller's Protocols with their plan detail.",
  description:
    "Returns a bounded page of Protocols, each with its local-date bounds, Protocol Period, Protocol Members (with every Schedule Version and the current one), and declared target outcomes (all plan data — never derived analytics).",
  security: [{ bearerAuth: [] }],
  request: { query: AgentProtocolListQuerySchema },
  responses: {
    200: {
      description: "A bounded page of Protocols with detail.",
      content: {
        "application/json": { schema: AgentProtocolListResponseSchema }
      }
    },
    ...readResponses401_503()
  }
});

export const agentDoseListRoute = createRoute({
  method: "get",
  path: "/agent/protocols/doses",
  operationId: "listAgentDoses",
  tags: ["Agent Reads"],
  summary: "List the caller's logged Doses over a date range.",
  description:
    "Returns a bounded, date-scoped page of logged Doses, filterable by Compound, Protocol tag, and Provenance. Each Dose is a self-describing snapshot.",
  security: [{ bearerAuth: [] }],
  request: { query: AgentDoseListQuerySchema },
  responses: {
    200: {
      description: "A bounded page of Doses.",
      content: {
        "application/json": { schema: AgentDoseListResponseSchema }
      }
    },
    ...readResponses401_503()
  }
});

function writeResponses401_429_503() {
  return {
    401: {
      description: "The request is missing a valid agent API key.",
      content: {
        "application/json": { schema: AgentUnauthorizedResponseSchema }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key or Protocols write storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentProtocolsUnavailableResponseSchema
          ])
        }
      }
    }
  };
}

export const agentDoseBatchWriteRoute = createRoute({
  method: "post",
  path: "/agent/protocols/doses/batch-write",
  operationId: "batchWriteAgentDoses",
  tags: ["Agent Writes"],
  summary: "Batch-write logged Doses as one Activity Log batch.",
  description:
    "Authenticated agent write path for logged Doses. Each Dose is validated by the shared two-tier dose validator, snapshotted self-describingly, stamped Provenance agent, optionally tagged to a Protocol, and applied atomically as one idempotent Activity Log batch. Tombstoning is supported; purge is intentionally absent.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": { schema: AgentDoseBatchWriteRequestSchema }
      }
    }
  },
  responses: {
    200: {
      description: "The batch was accepted, or recognized as an idempotent replay.",
      content: {
        "application/json": { schema: AgentDoseBatchWriteResponseSchema }
      }
    },
    422: {
      description:
        "One or more Doses failed hard validation, or the idempotency key conflicts with an earlier request; no rows were written.",
      content: {
        "application/json": {
          schema: z.union([
            AgentDoseBatchWriteErrorResponseSchema,
            AgentProtocolsBatchWriteErrorResponseSchema
          ])
        }
      }
    },
    ...writeResponses401_429_503()
  }
});

export const agentCompoundBatchWriteRoute = createRoute({
  method: "post",
  path: "/agent/protocols/compounds/batch-write",
  operationId: "batchWriteAgentCompounds",
  tags: ["Agent Writes"],
  summary: "Batch-write Compounds as one Activity Log batch.",
  description:
    "Authenticated agent write path for the Compound library. Creates, edits, and archives Compounds in one idempotent batch. A Compound is a neutral template; the model never categorizes it by type or legality.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": { schema: AgentCompoundBatchWriteRequestSchema }
      }
    }
  },
  responses: {
    200: {
      description: "The batch was accepted, or recognized as an idempotent replay.",
      content: {
        "application/json": { schema: AgentCompoundBatchWriteResponseSchema }
      }
    },
    422: {
      description:
        "One or more Compounds failed hard validation, or the idempotency key conflicts with an earlier request; no rows were written.",
      content: {
        "application/json": { schema: AgentProtocolsBatchWriteErrorResponseSchema }
      }
    },
    ...writeResponses401_429_503()
  }
});

export const agentProtocolBatchWriteRoute = createRoute({
  method: "post",
  path: "/agent/protocols/batch-write",
  operationId: "batchWriteAgentProtocols",
  tags: ["Agent Writes"],
  summary: "Batch-write Protocols (plan + Schedule Versions + target outcomes).",
  description:
    "Authenticated agent write path for Protocol plans. Creates, edits, and archives Protocols with their Protocol Members, Schedule Versions, and target outcomes in one idempotent batch, validated by the shared two-tier plan validators. The request carries the user's local date as today, which dates every new Schedule Version and archive exactly as the app does; versions are insert-only. Plan writes never touch logged Doses: archiving a Protocol never cascades.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": { schema: AgentProtocolBatchWriteRequestSchema }
      }
    }
  },
  responses: {
    200: {
      description: "The batch was accepted, or recognized as an idempotent replay.",
      content: {
        "application/json": { schema: AgentProtocolBatchWriteResponseSchema }
      }
    },
    422: {
      description:
        "One or more Protocols failed hard validation, or the idempotency key conflicts with an earlier request; no rows were written.",
      content: {
        "application/json": { schema: AgentProtocolsBatchWriteErrorResponseSchema }
      }
    },
    ...writeResponses401_429_503()
  }
});

export const agentEffectWindowRoute = createRoute({
  method: "get",
  path: "/agent/protocols/effect-window",
  operationId: "readAgentEffectWindow",
  tags: ["Agent Reads"],
  summary: "Read a descriptive Effect window for a Compound/Protocol × Metric.",
  description:
    "Computes a descriptive before/during/after summary of one outcome Metric around a Protocol's declared course (local midnight of its start date to local midnight after its inclusive end date, at timezoneOffsetMinutes, default UTC; no end date = ongoing until now) or a Compound's logged Dose timeline (earliest to latest Dose; a single Dose = ongoing until now), with BEFORE and AFTER mirroring DURING's length. The window is the same one the app's Effect view shows; off-cycle and paused days count as during. The range only scopes the Dose markers returned. Aggregates (count/min/max/mean) are computed on demand and never stored. Strictly descriptive — never a causal, efficacy, or medical claim.",
  security: [{ bearerAuth: [] }],
  request: { query: AgentEffectWindowQuerySchema },
  responses: {
    200: {
      description: "The descriptive Effect window summary.",
      content: {
        "application/json": { schema: AgentEffectWindowResponseSchema }
      }
    },
    422: {
      description:
        "The request is malformed (e.g. not exactly one source, not exactly one Metric, or the Metric/source was not found).",
      content: {
        "application/json": { schema: AgentEffectWindowErrorResponseSchema }
      }
    },
    ...readResponses401_503()
  }
});

// The app sets no validation hook, so a query the request schema refuses
// never reaches the route or its checks, as for every route here.
const PROTOCOL_DAYS_SCHEMA_400_NOTE =
  "A query the request schema refuses, such as a date that is not a real YYYY-MM-DD date or a missing required parameter, is also answered 400, before authentication, in the request validator's own error body rather than this one.";

function protocolDaysInvalidResponse(description: string) {
  return {
    400: {
      description,
      content: {
        "application/json": { schema: AgentProtocolDaysInvalidRequestResponseSchema }
      }
    }
  };
}

export const agentProtocolPlannedDaysRoute = createRoute({
  method: "get",
  path: "/agent/protocols/planned-days",
  operationId: "listAgentProtocolPlannedDays",
  tags: ["Agent Reads"],
  summary: "List what the caller's Protocols planned on each day of a range.",
  description: `Returns one planned day per Protocol, Compound and local date from fromLocalDate through toLocalDate (both included, at most ${AGENT_PROTOCOL_DAYS_MAX_RANGE_DAYS} days; future dates allowed): the planned doses with their times and amounts, or why nothing was planned. Archived Protocols and removed members still plan the days before their archive. Computed on read by the same plan core the app uses, never stored.`,
  security: [{ bearerAuth: [] }],
  request: { query: AgentProtocolPlannedDaysQuerySchema },
  responses: {
    200: {
      description: "The planned days of the range.",
      content: {
        "application/json": { schema: AgentProtocolPlannedDaysResponseSchema }
      }
    },
    ...protocolDaysInvalidResponse(
      `The range is refused, with this body: fromLocalDate after toLocalDate, or a range of more than ${AGENT_PROTOCOL_DAYS_MAX_RANGE_DAYS} days. ${PROTOCOL_DAYS_SCHEMA_400_NOTE}`
    ),
    ...readResponses401_503()
  }
});

export const agentProtocolDayStatusesRoute = createRoute({
  method: "get",
  path: "/agent/protocols/day-statuses",
  operationId: "listAgentProtocolDayStatuses",
  tags: ["Agent Reads"],
  summary: "List the Day Status of each Compound on each day of a range.",
  description: `Returns one Day Status per Compound and local date from fromLocalDate through toLocalDate (both included, at most ${AGENT_PROTOCOL_DAYS_MAX_RANGE_DAYS} days, ending no later than today), matching the logged Doses against the planned doses exactly as the app's Planned list and Consistency view do. A Dose's Protocol tag never decides what it fills. With detail=doses each Day Status also lists its fills. Statuses and counts only, computed on read and never stored.`,
  security: [{ bearerAuth: [] }],
  request: { query: AgentProtocolDayStatusesQuerySchema },
  responses: {
    200: {
      description: "The Day Statuses of the range.",
      content: {
        "application/json": { schema: AgentProtocolDayStatusesResponseSchema }
      }
    },
    ...protocolDaysInvalidResponse(
      `The range is refused, with this body: fromLocalDate after toLocalDate, a range of more than ${AGENT_PROTOCOL_DAYS_MAX_RANGE_DAYS} days, toLocalDate after today, or a today more than one day from the server's UTC date. ${PROTOCOL_DAYS_SCHEMA_400_NOTE}`
    ),
    ...readResponses401_503()
  }
});

// ---------------------------------------------------------------------------
// Inferred types
// ---------------------------------------------------------------------------

export type AgentCompoundListQuery = z.infer<typeof AgentCompoundListQuerySchema>;
export type AgentProtocolListQuery = z.infer<typeof AgentProtocolListQuerySchema>;
export type AgentDoseListQuery = z.infer<typeof AgentDoseListQuerySchema>;
export type AgentEffectWindowQuery = z.infer<typeof AgentEffectWindowQuerySchema>;
export type AgentProtocolPlannedDaysQuery = z.infer<typeof AgentProtocolPlannedDaysQuerySchema>;
export type AgentProtocolDayStatusesQuery = z.infer<typeof AgentProtocolDayStatusesQuerySchema>;
export type AgentProtocolPlannedDaysResponse = z.infer<
  typeof AgentProtocolPlannedDaysResponseSchema
>;
export type AgentProtocolDayStatusesResponse = z.infer<
  typeof AgentProtocolDayStatusesResponseSchema
>;
export type AgentCompoundBatchWriteRequest = z.infer<
  typeof AgentCompoundBatchWriteRequestSchema
>;
export type AgentDoseBatchWriteRequest = z.infer<
  typeof AgentDoseBatchWriteRequestSchema
>;
export type AgentProtocolBatchWriteRequest = z.infer<
  typeof AgentProtocolBatchWriteRequestSchema
>;
export type AgentDoseBatchWriteIssue = z.infer<typeof AgentDoseBatchWriteIssueSchema>;

type PreparedReference = {
  field: string;
  id: string;
  table: "compounds" | "protocols" | "protocolCompounds";
};

type PreparedRow = {
  id: string;
  itemIndex: number;
  field: string;
  updatedAt: string;
  deletedAt: string | null;
  payload: Record<string, unknown>;
  references?: PreparedReference[];
  /**
   * Protocols and Protocol Members only: the request's `archived`. The store
   * turns it into `deleted_at` and `archived_on`, because only the store can
   * see whether the row is already archived.
   */
  archive?: boolean;
};

type AgentProtocolsBatchWriteIssue = z.infer<typeof AgentProtocolsBatchWriteIssueSchema>;

type PreparedDoseResult = Omit<
  z.infer<typeof AgentDoseBatchWriteResultSchema>,
  "outcome"
>;

type PreparedEntityResult = Omit<
  z.infer<typeof AgentEntityBatchWriteResultSchema>,
  "outcome"
>;

export type AgentDoseBatchPreparation =
  | {
      accepted: true;
      doses: PreparedRow[];
      responseDoses: PreparedDoseResult[];
    }
  | {
      accepted: false;
      errors: AgentDoseBatchWriteIssue[];
      warnings: AgentDoseBatchWriteIssue[];
    };

export type AgentProtocolsStoreWriteResult = {
  duplicate: boolean;
  idempotencyConflict: boolean;
  receiptUnavailable: boolean;
  serverClock: string;
  accepted: string[];
  applied: { id: string; updatedAt: string; deviceId: string }[];
  validationErrors: z.infer<typeof AgentProtocolsBatchWriteIssueSchema>[];
};

export type AgentProtocolsStore = {
  listCompounds(input: {
    userId: string;
    query: AgentCompoundListQuery;
  }): Promise<z.infer<typeof AgentCompoundListResponseSchema>>;
  listProtocols(input: {
    userId: string;
    query: AgentProtocolListQuery;
  }): Promise<z.infer<typeof AgentProtocolListResponseSchema>>;
  listDoses(input: {
    userId: string;
    query: AgentDoseListQuery;
  }): Promise<z.infer<typeof AgentDoseListResponseSchema>>;
  readEffectWindow(input: {
    userId: string;
    query: AgentEffectWindowQuery;
  }): Promise<
    | { ok: true; value: z.infer<typeof AgentEffectWindowResponseSchema> }
    | { ok: false; message: string }
  >;
  /**
   * The range's planned days. The query is already checked by
   * `checkAgentProtocolDaysQuery`, so the store never sees a bad range. The
   * store parses its own response against the response schema, and REST and
   * MCP return it as is, so a large range is schema-checked once.
   */
  listProtocolPlannedDays(input: {
    userId: string;
    query: AgentProtocolPlannedDaysQuery;
  }): Promise<AgentProtocolPlannedDaysResponse>;
  /** The range's Day Statuses, the query checked and the response parsed as above. */
  listProtocolDayStatuses(input: {
    userId: string;
    query: AgentProtocolDayStatusesQuery;
  }): Promise<AgentProtocolDayStatusesResponse>;
  writeDoseBatch(input: {
    userId: string;
    batchId: string;
    requestFingerprint: string;
    deviceId: string;
    doses: PreparedRow[];
  }): Promise<AgentProtocolsStoreWriteResult>;
  writeCompoundBatch(input: {
    userId: string;
    batchId: string;
    requestFingerprint: string;
    deviceId: string;
    compounds: PreparedRow[];
  }): Promise<AgentProtocolsStoreWriteResult>;
  writeProtocolBatch(input: {
    userId: string;
    batchId: string;
    requestFingerprint: string;
    deviceId: string;
    /** The request's `today`: the user's local date, already bounds-checked. */
    today: string;
    protocols: PreparedRow[];
    members: PreparedRow[];
    schedules: PreparedRow[];
    targetOutcomes: PreparedRow[];
  }): Promise<AgentProtocolsStoreWriteResult>;
};

// ---------------------------------------------------------------------------
// Pure prepare functions (validation + payload building), unit-testable
// ---------------------------------------------------------------------------

export function prepareAgentDoseBatchWrite({
  request,
  now = new Date()
}: {
  request: AgentDoseBatchWriteRequest;
  now?: Date;
}): AgentDoseBatchPreparation {
  const errors: AgentDoseBatchWriteIssue[] = [];
  const warnings: AgentDoseBatchWriteIssue[] = [];
  const prepared: PreparedRow[] = [];
  const responseDoses: PreparedDoseResult[] = [];
  const nowIso = now.toISOString();
  const seen = new Set<string>();

  for (const [itemIndex, dose] of request.doses.entries()) {
    if (seen.has(dose.id)) {
      errors.push(
        doseIssue(itemIndex, dose.id, {
          field: "id",
          rule: "duplicate_dose_id",
          message: "A Dose id may appear only once per batch.",
          limit: null
        })
      );
      continue;
    }
    seen.add(dose.id);

    const validation = validateAgentDose({
      amount: dose.amount,
      unit: dose.unit,
      route: dose.route
    });
    for (const warning of validation.warnings) {
      warnings.push(doseIssue(itemIndex, dose.id, warning));
    }
    for (const error of validation.errors) {
      errors.push(doseIssue(itemIndex, dose.id, error));
    }
    if (validation.errors.length > 0) {
      continue;
    }

    const amountValue = parseAmountValue(dose.amount);
    const updatedAt = dose.updatedAt ?? nowIso;
    const deletedAt = dose.deletedAt ?? null;
    prepared.push({
      id: dose.id,
      itemIndex,
      field: `doses[${itemIndex}].id`,
      updatedAt,
      deletedAt,
      references: [
        ...(dose.compoundId === null
          ? []
          : [
              {
                field: `doses[${itemIndex}].compoundId`,
                id: dose.compoundId,
                table: "compounds" as const
              }
            ]),
        ...(dose.protocolId === null
          ? []
          : [
              {
                field: `doses[${itemIndex}].protocolId`,
                id: dose.protocolId,
                table: "protocols" as const
              }
            ])
      ],
      payload: {
        id: dose.id,
        compound_id: dose.compoundId,
        compound_name: dose.compoundName,
        compound_strength: strengthPayload(dose.compoundStrength),
        amount_value: amountValue,
        amount_entered:
          typeof dose.amount === "string" ? dose.amount : String(dose.amount),
        unit: dose.unit,
        route: dose.route,
        took_at: dose.tookAt,
        timezone: dose.timezone,
        timezone_offset_minutes: doseTimezoneOffsetMinutes(dose),
        local_date: dose.localDate,
        provenance: "agent",
        protocol_id: dose.protocolId,
        protocol_name: dose.protocolName,
        updated_at: updatedAt,
        deleted_at: deletedAt
      }
    });
    responseDoses.push({
      id: dose.id,
      compoundName: dose.compoundName,
      warnings: validation.warnings
    });
  }

  if (errors.length > 0) {
    return { accepted: false, errors, warnings };
  }

  return { accepted: true, doses: prepared, responseDoses };
}

export function prepareAgentCompoundBatchWrite({
  request,
  now = new Date()
}: {
  request: AgentCompoundBatchWriteRequest;
  now?: Date;
}):
  | {
      accepted: true;
      compounds: PreparedRow[];
      responseCompounds: PreparedEntityResult[];
    }
  | {
      accepted: false;
      errors: z.infer<typeof AgentProtocolsBatchWriteIssueSchema>[];
    } {
  const errors: z.infer<typeof AgentProtocolsBatchWriteIssueSchema>[] = [];
  const compounds: PreparedRow[] = [];
  const responseCompounds: PreparedEntityResult[] = [];
  const nowIso = now.toISOString();
  const seen = new Set<string>();

  for (const [itemIndex, compound] of request.compounds.entries()) {
    if (seen.has(compound.id)) {
      errors.push(
        entityIssue(itemIndex, compound.id, {
          field: `compounds[${itemIndex}].id`,
          rule: "duplicate_compound_id",
          message: "A Compound id may appear only once per batch."
        })
      );
      continue;
    }
    seen.add(compound.id);

    const updatedAt = compound.updatedAt ?? nowIso;
    const deletedAt = compound.deletedAt ?? null;
    compounds.push({
      id: compound.id,
      itemIndex,
      field: `compounds[${itemIndex}].id`,
      updatedAt,
      deletedAt,
      payload: {
        id: compound.id,
        name: compound.name,
        default_unit: compound.defaultUnit,
        default_route: compound.defaultRoute,
        strength: strengthPayload(compound.strength),
        updated_at: updatedAt,
        deleted_at: deletedAt
      }
    });
    responseCompounds.push({ id: compound.id, name: compound.name });
  }

  if (errors.length > 0) {
    return { accepted: false, errors };
  }
  return { accepted: true, compounds, responseCompounds };
}

/**
 * The Agent Protocol write's pure half (docs/designs/protocol-schedules-and-
 * reminders.md, D6 and D7): it checks the request's `today` against the
 * server clock, runs every Protocol Period and Schedule Rule through the shared
 * two-tier validators, and builds the synced row payloads, with each `rule`
 * (its times and weekdays sorted, D7) and `period` stored as JSON text in the
 * codec's encoding (Data shapes). Everything that needs stored data (dating
 * Schedule Versions, refusing a reused version id or an archived Protocol,
 * re-dated copies on a start move, archive stamps) is the store's
 * `writeProtocolBatch`, inside its transaction, so REST and MCP share it.
 */
export function prepareAgentProtocolBatchWrite({
  request,
  now = new Date()
}: {
  request: AgentProtocolBatchWriteRequest;
  now?: Date;
}):
  | {
      accepted: true;
      today: string;
      protocols: PreparedRow[];
      members: PreparedRow[];
      schedules: PreparedRow[];
      targetOutcomes: PreparedRow[];
      responseProtocols: PreparedEntityResult[];
      warnings: AgentProtocolsBatchWriteIssue[];
    }
  | {
      accepted: false;
      errors: AgentProtocolsBatchWriteIssue[];
      warnings: AgentProtocolsBatchWriteIssue[];
    } {
  const errors: AgentProtocolsBatchWriteIssue[] = [];
  const warnings: AgentProtocolsBatchWriteIssue[] = [];
  const protocols: PreparedRow[] = [];
  const members: PreparedRow[] = [];
  const schedules: PreparedRow[] = [];
  const targetOutcomes: PreparedRow[] = [];
  const responseProtocols: PreparedEntityResult[] = [];
  const nowIso = now.toISOString();
  const seenProtocol = new Set<string>();
  const seenRow = new Set<string>();

  // `today` dates versions and archives, so it must be a date a person using
  // the app could have: every real zone is within a day of UTC.
  const todayMessage = todayOutOfRangeMessage(request.today, now);
  if (todayMessage !== null) {
    errors.push(
      entityIssue(0, null, {
        field: "today",
        rule: "today_out_of_range",
        message: todayMessage
      })
    );
  }

  for (const [itemIndex, protocol] of request.protocols.entries()) {
    if (seenProtocol.has(protocol.id)) {
      errors.push(
        entityIssue(itemIndex, protocol.id, {
          field: `protocols[${itemIndex}].id`,
          rule: "duplicate_protocol_id",
          message: "A Protocol id may appear only once per batch."
        })
      );
      continue;
    }
    seenProtocol.add(protocol.id);

    const periodValidation = validateAgentProtocolPeriod({
      startLocalDate: protocol.startLocalDate,
      endLocalDate: protocol.endLocalDate,
      period: protocol.period
    });
    collectPlanIssues(periodValidation, {
      itemIndex,
      entityId: protocol.id,
      fieldPrefix: `protocols[${itemIndex}]`,
      errors,
      warnings
    });
    const period =
      periodValidation.errors.length > 0
        ? null
        : encodePlanJson(() => storedPeriodText(protocol.period), {
            itemIndex,
            entityId: protocol.id,
            field: `protocols[${itemIndex}].period`,
            rule: "period_format",
            errors
          });

    const updatedAt = protocol.updatedAt ?? nowIso;
    protocols.push({
      id: protocol.id,
      itemIndex,
      field: `protocols[${itemIndex}].id`,
      updatedAt,
      deletedAt: null,
      archive: protocol.archived,
      payload: {
        id: protocol.id,
        name: protocol.name,
        start_local_date: protocol.startLocalDate,
        end_local_date: protocol.endLocalDate,
        period: period ?? null,
        reminders_enabled: protocol.remindersEnabled,
        archived_on: null,
        updated_at: updatedAt,
        deleted_at: null
      }
    });

    for (const member of protocol.members) {
      if (seenRow.has(member.id)) {
        errors.push(
          entityIssue(itemIndex, member.id, {
            field: `protocols[${itemIndex}].members`,
            rule: "duplicate_plan_row_id",
            message: "A plan row id may appear only once per batch."
          })
        );
        continue;
      }
      seenRow.add(member.id);
      const memberUpdatedAt = member.updatedAt ?? nowIso;
      members.push({
        id: member.id,
        itemIndex,
        field: `protocols[${itemIndex}].members`,
        updatedAt: memberUpdatedAt,
        deletedAt: null,
        archive: member.archived,
        references: [
          {
            field: `protocols[${itemIndex}].members.compoundId`,
            id: member.compoundId,
            table: "compounds"
          }
        ],
        payload: {
          id: member.id,
          protocol_id: protocol.id,
          compound_id: member.compoundId,
          position: member.position,
          archived_on: null,
          updated_at: memberUpdatedAt,
          deleted_at: null
        }
      });
    }

    for (const [scheduleIndex, scheduleRow] of protocol.schedules.entries()) {
      if (seenRow.has(scheduleRow.id)) {
        errors.push(
          entityIssue(itemIndex, scheduleRow.id, {
            field: `protocols[${itemIndex}].schedules`,
            rule: "duplicate_plan_row_id",
            message: "A plan row id may appear only once per batch."
          })
        );
        continue;
      }
      seenRow.add(scheduleRow.id);
      const field = `protocols[${itemIndex}].schedules[${scheduleIndex}]`;
      const ruleValidation = validateAgentScheduleRule(scheduleRow.rule, {
        amountValue: scheduleRow.doseAmountValue,
        amountEntered: scheduleRow.doseAmountEntered,
        unit: scheduleRow.doseUnit,
        route: scheduleRow.route
      });
      collectPlanIssues(ruleValidation, {
        itemIndex,
        entityId: scheduleRow.id,
        fieldPrefix: field,
        errors,
        warnings
      });
      const rule =
        ruleValidation.errors.length > 0
          ? null
          : encodePlanJson(
              // Stored as JSON text in the codec's encoding (Data shapes),
              // with its times and weekdays sorted, as writers store them (D7).
              () =>
                JSON.stringify(encodeScheduleRule(sortedRule(scheduleRow.rule) as ScheduleRule)),
              {
                itemIndex,
                entityId: scheduleRow.id,
                field: `${field}.rule`,
                rule: "rule_format",
                errors
              }
            );
      const scheduleUpdatedAt = scheduleRow.updatedAt ?? nowIso;
      schedules.push({
        id: scheduleRow.id,
        itemIndex,
        field: `protocols[${itemIndex}].schedules`,
        updatedAt: scheduleUpdatedAt,
        deletedAt: null,
        references: [
          {
            field: `protocols[${itemIndex}].schedules.protocolCompoundId`,
            id: scheduleRow.protocolCompoundId,
            table: "protocolCompounds"
          }
        ],
        payload: {
          id: scheduleRow.id,
          protocol_compound_id: scheduleRow.protocolCompoundId,
          // Assigned by the store from stored versions (D1).
          effective_from: null,
          rule,
          dose_amount_value: scheduleRow.doseAmountValue,
          dose_amount_entered: scheduleRow.doseAmountEntered,
          dose_unit: scheduleRow.doseUnit,
          route: scheduleRow.route,
          updated_at: scheduleUpdatedAt,
          deleted_at: null
        }
      });
    }

    for (const outcome of protocol.targetOutcomes) {
      if (seenRow.has(outcome.id)) {
        errors.push(
          entityIssue(itemIndex, outcome.id, {
            field: `protocols[${itemIndex}].targetOutcomes`,
            rule: "duplicate_plan_row_id",
            message: "A plan row id may appear only once per batch."
          })
        );
        continue;
      }
      seenRow.add(outcome.id);
      // Mirrors the app's validateProtocolTargetOutcomes: a structural
      // refusal, not a validation tier.
      if ((outcome.outcomeKind === "metric") !== (outcome.metricId !== null)) {
        errors.push(
          entityIssue(itemIndex, outcome.id, {
            field: `protocols[${itemIndex}].targetOutcomes`,
            rule: "target_outcome_metric_id",
            message:
              outcome.outcomeKind === "metric"
                ? "A metric target outcome needs a metricId."
                : "A performance target outcome has no metricId; send null."
          })
        );
        continue;
      }
      const outcomeUpdatedAt = outcome.updatedAt ?? nowIso;
      targetOutcomes.push({
        id: outcome.id,
        itemIndex,
        field: `protocols[${itemIndex}].targetOutcomes`,
        updatedAt: outcomeUpdatedAt,
        deletedAt: outcome.deletedAt ?? null,
        // Exactly the app's image (_protocolTargetOutcomeImage): a pull hands
        // this payload to the app's decoder unchanged. The app can't read
        // another shape (docs/designs/protocol-target-outcome-sync-shape.md).
        payload: {
          id: outcome.id,
          protocol_id: protocol.id,
          kind: outcome.outcomeKind,
          metric_id: outcome.metricId,
          // Assigned by the store from stored outcomes when left out (D3).
          position: outcome.position ?? null,
          updated_at: outcomeUpdatedAt,
          deleted_at: outcome.deletedAt ?? null
        }
      });
    }

    responseProtocols.push({ id: protocol.id, name: protocol.name });
  }

  if (errors.length > 0) {
    return { accepted: false, errors, warnings };
  }
  return {
    accepted: true,
    today: request.today,
    protocols,
    members,
    schedules,
    targetOutcomes,
    responseProtocols,
    warnings
  };
}

/** How far the request's `today` may be from the server's UTC date (D6). */
const AGENT_TODAY_MAX_SKEW_DAYS = 1;

/**
 * Why `today` is refused, or null when it is within
 * {@link AGENT_TODAY_MAX_SKEW_DAYS} of the server's UTC date. The Protocol
 * batch write and the Day Status read share it, so one `today` is accepted or
 * refused, with one message, by both.
 */
function todayOutOfRangeMessage(today: string, now: Date): string | null {
  const serverUtcDate = now.toISOString().slice(0, 10);
  return Math.abs(epochDay(today) - epochDay(serverUtcDate)) > AGENT_TODAY_MAX_SKEW_DAYS
    ? `today must be within ${AGENT_TODAY_MAX_SKEW_DAYS} day of the server's UTC date (${serverUtcDate}).`
    : null;
}

/**
 * The checks the planned-day and Day Status reads make before any storage
 * read, shared by REST and MCP so both refuse the same queries with the same
 * message (D6): `fromLocalDate` after `toLocalDate`, a range of more than
 * {@link AGENT_PROTOCOL_DAYS_MAX_RANGE_DAYS} days (both ends included, as the
 * app's Consistency view counts), and, for Day Statuses only, `toLocalDate`
 * after `today`. Planned days may lie in the future; a Day Status may not,
 * because a day still to come has no status.
 *
 * `today` is also held within one day of the server's UTC date, the bound the
 * Protocol batch write puts on its own `today`, because every real UTC offset
 * (-12:00 to +14:00, D2) puts the user's date there. Without it a `today` of
 * a later year would read every planned day up to it as Not logged, a status
 * no person using the app could see.
 */
export function checkAgentProtocolDaysQuery(
  query: { fromLocalDate: string; toLocalDate: string; today?: string },
  now: Date = new Date(),
  // Why a range may not end after today, in the caller's domain's terms.
  futureDayReason = "a day still to come has no Day Status"
): { ok: true } | { ok: false; message: string } {
  const from = epochDay(query.fromLocalDate);
  const to = epochDay(query.toLocalDate);
  if (from > to) {
    return { ok: false, message: "fromLocalDate must not be after toLocalDate." };
  }
  const dayCount = to - from + 1;
  if (dayCount > AGENT_PROTOCOL_DAYS_MAX_RANGE_DAYS) {
    return {
      ok: false,
      message: `The range spans ${dayCount} days, more than the ${AGENT_PROTOCOL_DAYS_MAX_RANGE_DAYS}-day maximum.`
    };
  }
  if (query.today !== undefined) {
    const todayMessage = todayOutOfRangeMessage(query.today, now);
    if (todayMessage !== null) {
      return { ok: false, message: todayMessage };
    }
    if (to > epochDay(query.today)) {
      return {
        ok: false,
        message: `toLocalDate must not be after today: ${futureDayReason}.`
      };
    }
  }
  return { ok: true };
}

/**
 * The stored period, as JSON text in the codec's encoding (Data shapes), the
 * form every writer stores: null when there is no cycle and no Pause, as the
 * app writes it (readers accept both forms, and a decoded object too). The
 * decoded period is already the encoding: decoding builds a fresh object of
 * only the known keys, in stored order.
 */
function storedPeriodText(
  period: z.infer<typeof AgentProtocolPeriodSchema> | null
): string | null {
  const decoded = decodeProtocolPeriod(period);
  return decoded === null || (decoded.cycle === null && decoded.pauses.length === 0)
    ? null
    : JSON.stringify(decoded);
}

/**
 * Runs a codec encode after the shared validators accepted the JSON. A value
 * both accepted can't fail the codec today, but if the two ever drift the
 * write is refused with an issue rather than a 500 or an unplannable row.
 */
function encodePlanJson<T>(
  encode: () => T,
  {
    itemIndex,
    entityId,
    field,
    rule,
    errors
  }: {
    itemIndex: number;
    entityId: string;
    field: string;
    rule: string;
    errors: AgentProtocolsBatchWriteIssue[];
  }
): T | null {
  try {
    return encode();
  } catch (error) {
    if (!(error instanceof ProtocolPlanCodecError)) {
      throw error;
    }
    errors.push(entityIssue(itemIndex, entityId, { field, rule, message: error.message }));
    return null;
  }
}

/** Shared-validator issues, re-addressed to their place in the batch. */
function collectPlanIssues(
  result: AgentDoseValidationResult,
  {
    itemIndex,
    entityId,
    fieldPrefix,
    errors,
    warnings
  }: {
    itemIndex: number;
    entityId: string;
    fieldPrefix: string;
    errors: AgentProtocolsBatchWriteIssue[];
    warnings: AgentProtocolsBatchWriteIssue[];
  }
) {
  for (const [issues, target] of [
    [result.errors, errors],
    [result.warnings, warnings]
  ] as const) {
    for (const issue of issues) {
      target.push(
        entityIssue(itemIndex, entityId, {
          field: `${fieldPrefix}.${issue.field}`,
          rule: issue.rule,
          message: issue.message
        })
      );
    }
  }
}

/**
 * A Dose's frozen UTC offset (D2): the Agent's own value wins; otherwise it is
 * derived from an IANA `timezone` at `tookAt`; an abbreviation such as "BRT"
 * can't be converted, so it stays null.
 */
function doseTimezoneOffsetMinutes(dose: AgentDoseBatchWriteRequest["doses"][number]) {
  if (dose.timezoneOffsetMinutes !== undefined) {
    return dose.timezoneOffsetMinutes;
  }
  return offsetMinutesInTimezone(new Date(dose.tookAt), dose.timezone);
}

export function finalizeAgentDoseBatchWriteResults({
  applied,
  accepted,
  duplicate,
  results
}: {
  applied: readonly { id: string }[];
  accepted: readonly string[];
  duplicate: boolean;
  results: PreparedDoseResult[];
}) {
  const appliedIds = new Set(applied.map((row) => row.id));
  const acceptedIds = new Set(accepted);
  return results.map((result) => ({
    ...result,
    outcome: duplicate
      ? ("duplicate" as const)
      : appliedIds.has(result.id)
        ? ("applied" as const)
        : acceptedIds.has(result.id)
          ? ("superseded" as const)
          : ("refused" as const)
  }));
}

export function finalizeAgentProtocolsEntityBatchWriteResults({
  applied,
  accepted,
  duplicate,
  results
}: {
  applied: readonly { id: string }[];
  accepted: readonly string[];
  duplicate: boolean;
  results: PreparedEntityResult[];
}) {
  const appliedIds = new Set(applied.map((row) => row.id));
  const acceptedIds = new Set(accepted);
  return results.map((result) => ({
    ...result,
    outcome: duplicate
      ? ("duplicate" as const)
      : appliedIds.has(result.id)
        ? ("applied" as const)
        : acceptedIds.has(result.id)
          ? ("superseded" as const)
          : ("refused" as const)
  }));
}

export function agentProtocolsBatchRequestFingerprint(request: unknown) {
  return agentBatchRequestFingerprint(request);
}

/**
 * The response for a write the store refused, or `null` when it was accepted.
 * A refusal still returns the soft warnings the pure step judged (spec D6:
 * a refused write returns its `warnings` beside its `errors`), so pass them
 * through. Compound and Dose writes pass `[]`: a Dose carries its warnings in
 * its own result, in a shape this response doesn't hold.
 */
export function agentProtocolsWriteFailure(
  result: AgentProtocolsStoreWriteResult,
  warnings: z.infer<typeof AgentProtocolsBatchWriteErrorResponseSchema>["warnings"]
):
  | {
      status: 422;
      body: z.infer<typeof AgentProtocolsBatchWriteErrorResponseSchema>;
    }
  | {
      status: 503;
      body: z.infer<typeof AgentProtocolsUnavailableResponseSchema>;
    }
  | null {
  if (result.receiptUnavailable) {
    return {
      status: 503,
      body: AgentProtocolsUnavailableResponseSchema.parse({
        code: "agent_protocols_unavailable",
        message:
          "The idempotency receipt is temporarily unavailable; retry the same request."
      })
    };
  }
  const errors = result.idempotencyConflict
    ? [
        entityIssue(0, null, {
          field: "idempotencyKey",
          rule: "idempotency_key_conflict",
          message:
            "Idempotency key has already been used with a different request body."
        })
      ]
    : (result.validationErrors ?? []);
  if (errors.length === 0) {
    return null;
  }
  return {
    status: 422,
    body: AgentProtocolsBatchWriteErrorResponseSchema.parse({
      code: "agent_protocols_batch_write_failed",
      message: "Batch contains one or more hard validation failures.",
      errors,
      warnings
    })
  };
}

// ---------------------------------------------------------------------------
// Pure effect-window computation (deterministic, golden-vectorable, no I/O)
// ---------------------------------------------------------------------------

export type EffectWindowSample = { at: Date; value: number };

/**
 * What an Effect window is anchored to. A Protocol is a time-bounded course, so
 * its declared start/end are DURING whatever Doses were logged against it (the
 * tagged Doses are markers on top, never the bounds). Its bounds are local
 * dates; `effectBoundsFromLocalDates` turns them into these instants, and the
 * window math stays on instants, pinned by m29-effect-window.json. An ad-hoc
 * Compound has no declared course, so its logged Doses are.
 */
export type EffectWindowSource =
  | { kind: "protocol"; startDate: Date; endDate: Date | null }
  | { kind: "compound"; doseTimes: readonly Date[] };

/**
 * DURING plus the mirrored BEFORE/AFTER spans of the same length on either
 * side. `duringEnd === null` is a course still running: `duringEndOrNow` (the
 * clock at derivation) ends DURING and starts AFTER.
 */
export type EffectWindow = {
  duringStart: Date;
  duringEnd: Date | null;
  duringEndOrNow: Date;
  beforeStart: Date;
  afterEnd: Date;
};

export type EffectAggregate = {
  count: number;
  min: number | null;
  max: number | null;
  mean: number | null;
};

export type EffectWindowSegments = {
  before: EffectAggregate;
  during: EffectAggregate;
  after: EffectAggregate;
};

/**
 * Derives the Effect window exactly as the app does (`effectWindowForProtocol`
 * / `effectWindowForDoseTimes` in apps/mobile/lib/domain/effect/effect.dart);
 * `packages/golden-vectors/vectors/m29-effect-window.json` pins both. A
 * Protocol with no end date is ongoing until `now`. A Compound spans its
 * earliest to latest Dose; exactly one Dose has no latest to end on, so it is
 * ongoing until `now` too rather than a zero-length window that buckets
 * nothing. No Dose, no window.
 */
export function deriveEffectWindow(
  source: EffectWindowSource,
  now: Date
): EffectWindow | null {
  let duringStart: Date;
  let duringEnd: Date | null;
  if (source.kind === "protocol") {
    duringStart = source.startDate;
    duringEnd = source.endDate;
  } else {
    const times = source.doseTimes
      .map((tookAt) => tookAt.getTime())
      .sort((left, right) => left - right);
    if (times.length === 0) {
      return null;
    }
    duringStart = new Date(times[0]!);
    duringEnd = times.length === 1 ? null : new Date(times[times.length - 1]!);
  }
  const duringEndOrNow = duringEnd ?? now;
  const duringLengthMs = duringEndOrNow.getTime() - duringStart.getTime();
  return {
    duringStart,
    duringEnd,
    duringEndOrNow,
    beforeStart: new Date(duringStart.getTime() - duringLengthMs),
    afterEnd: new Date(duringEndOrNow.getTime() + duringLengthMs)
  };
}

/**
 * Turns a Protocol's inclusive local-date bounds into the instants
 * `deriveEffectWindow` takes (docs/designs/protocol-schedules-and-reminders.md,
 * D2). Start is local midnight of the start date; end is local midnight of the
 * day after the inclusive end date, because Effect's windows are half-open. A
 * null end is an ongoing Protocol, which Effect runs until now. Local midnight
 * is the UTC midnight of that date minus `timezoneOffsetMinutes` (UTC-3 is
 * -180), the same conversion as the local-time anchors in
 * metric-reading-normalization.ts. The offset is the caller's: the app passes
 * the device's current one, and the Agent Effect read defaults to 0 (UTC).
 * It must be a whole number of minutes from -720 to +840 (UTC-12:00 to
 * UTC+14:00, the span of real zones); anything else throws a RangeError.
 * `packages/golden-vectors/vectors/m36-protocol-plan.json` pins it against the
 * app's twin in apps/mobile/lib/domain/effect/effect.dart.
 */
export function effectBoundsFromLocalDates(
  startLocalDate: string,
  endLocalDate: string | null | undefined,
  timezoneOffsetMinutes: number
): { startDate: Date; endDate: Date | null } {
  // The Dart twin takes an int, so a fractional or non-finite offset is a
  // caller bug here too.
  if (!Number.isInteger(timezoneOffsetMinutes)) {
    throw new RangeError(`Not a whole-minute UTC offset: ${timezoneOffsetMinutes}.`);
  }
  if (
    timezoneOffsetMinutes < AGENT_PROTOCOLS_MIN_OFFSET_MINUTES ||
    timezoneOffsetMinutes > AGENT_PROTOCOLS_MAX_OFFSET_MINUTES
  ) {
    throw new RangeError(
      `UTC offset ${timezoneOffsetMinutes} is outside ${AGENT_PROTOCOLS_MIN_OFFSET_MINUTES} to ${AGENT_PROTOCOLS_MAX_OFFSET_MINUTES} minutes.`
    );
  }
  const localMidnight = (localDate: string, addDays: number) =>
    new Date((epochDay(localDate) + addDays) * MS_PER_DAY - timezoneOffsetMinutes * 60_000);
  return {
    startDate: localMidnight(startLocalDate, 0),
    endDate:
      endLocalDate === null || endLocalDate === undefined
        ? null
        : localMidnight(endLocalDate, 1)
  };
}

/**
 * The descriptive Effect computation (PROTOCOLS.md §4): each segment of
 * `window` aggregates whatever outcome samples fall in it (count/min/max/mean).
 * Half-open segments `[start, end)`, so a boundary sample lands in exactly one,
 * and a sample outside all three is dropped, never moved to the nearest. No
 * window means every segment is empty. Pure — no I/O, nothing stored — which
 * is what makes it golden-vectorable.
 */
export function computeEffectWindowSegments({
  window,
  samples
}: {
  window: EffectWindow | null;
  samples: readonly EffectWindowSample[];
}): EffectWindowSegments {
  if (window === null) {
    return {
      before: emptyAggregate(),
      during: emptyAggregate(),
      after: emptyAggregate()
    };
  }

  const beforeStart = window.beforeStart.getTime();
  const duringStart = window.duringStart.getTime();
  const duringEnd = window.duringEndOrNow.getTime();
  const afterEnd = window.afterEnd.getTime();
  const before: number[] = [];
  const during: number[] = [];
  const after: number[] = [];
  for (const sample of samples) {
    const at = sample.at.getTime();
    if (at >= beforeStart && at < duringStart) {
      before.push(sample.value);
    } else if (at >= duringStart && at < duringEnd) {
      during.push(sample.value);
    } else if (at >= duringEnd && at < afterEnd) {
      after.push(sample.value);
    }
  }

  return {
    before: aggregate(before),
    during: aggregate(during),
    after: aggregate(after)
  };
}

function aggregate(values: number[]): EffectAggregate {
  if (values.length === 0) {
    return emptyAggregate();
  }
  let min = values[0]!;
  let max = values[0]!;
  let sum = 0;
  for (const value of values) {
    if (value < min) {
      min = value;
    }
    if (value > max) {
      max = value;
    }
    sum += value;
  }
  return { count: values.length, min, max, mean: sum / values.length };
}

function emptyAggregate(): EffectAggregate {
  return { count: 0, min: null, max: null, mean: null };
}

// ---------------------------------------------------------------------------
// Drizzle store
// ---------------------------------------------------------------------------

type OpaqueRow = {
  id: string;
  payload: Record<string, unknown>;
  updatedAt: Date;
  deletedAt: Date | null;
};

export function createDrizzleAgentProtocolsStore(
  db: ServerDatabase
): AgentProtocolsStore {
  return {
    async listCompounds({ userId, query }) {
      const fields = resolveFieldSelection(query.fields, AGENT_COMPOUND_FIELDS, [
        "id",
        "name"
      ]);
      const rows = await db
        .select({
          id: schema.compounds.id,
          payload: schema.compounds.payload,
          updatedAt: schema.compounds.updatedAt,
          deletedAt: schema.compounds.deletedAt
        })
        .from(schema.compounds)
        .where(eq(schema.compounds.userId, userId))
        .orderBy(asc(schema.compounds.id));

      const search = query.search?.toLowerCase();
      const filtered = rows.filter((row) => {
        if (!query.includeArchived && row.deletedAt !== null) {
          return false;
        }
        if (search !== undefined) {
          const name = String(row.payload.name ?? "").toLowerCase();
          if (!name.includes(search)) {
            return false;
          }
        }
        return true;
      });
      const start = cursorOffset(filtered, query.cursor);
      const page = filtered.slice(start, start + query.limit);
      return AgentCompoundListResponseSchema.parse({
        compounds: page.map((row) =>
          AgentCompoundListItemSchema.parse(
            projectFields(serializeCompound(row), fields)
          )
        ),
        fields,
        limit: query.limit,
        nextCursor: nextCursorFor(filtered, start, page),
        totalMatched: filtered.length
      });
    },

    async listProtocols({ userId, query }) {
      const [protocolRows, memberRows, scheduleRows, outcomeRows] =
        await Promise.all([
          selectOpaque(db, schema.protocols, userId),
          selectOpaque(db, schema.protocolCompounds, userId),
          selectOpaque(db, schema.schedules, userId),
          selectOpaque(db, schema.protocolTargetOutcomes, userId)
        ]);

      const search = query.search?.toLowerCase();
      const filteredProtocols = protocolRows
        .filter((row) => {
          // A row tombstoned by undo never existed (D1), archived or not.
          if (isUndoTombstone(row)) {
            return false;
          }
          if (!query.includeArchived && row.deletedAt !== null) {
            return false;
          }
          if (search !== undefined) {
            const name = String(row.payload.name ?? "").toLowerCase();
            if (!name.includes(search)) {
              return false;
            }
          }
          return true;
        })
        .sort((left, right) => left.id.localeCompare(right.id));

      // Group plan rows by their owning protocol/protocol_compound.
      const membersByProtocol = groupBy(
        memberRows.filter((row) => !isUndoTombstone(row)),
        (row) => String(row.payload.protocol_id ?? "")
      );
      const outcomesByProtocol = groupBy(outcomeRows, (row) =>
        String(row.payload.protocol_id ?? "")
      );
      const schedulesByMember = groupBy(scheduleRows, (row) =>
        String(row.payload.protocol_compound_id ?? "")
      );

      const start = cursorOffset(filteredProtocols, query.cursor);
      const page = filteredProtocols.slice(start, start + query.limit);
      const protocols = page.map((protocol) => {
        const members = (membersByProtocol.get(protocol.id) ?? [])
          .slice()
          .sort((left, right) => memberPosition(left) - memberPosition(right));
        const outcomes = outcomesByProtocol.get(protocol.id) ?? [];
        return AgentProtocolSchema.parse({
          ...serializeProtocol(protocol),
          members: members.map((row) =>
            serializeMember(row, schedulesByMember.get(row.id) ?? [])
          ),
          targetOutcomes: outcomes
            .map((row) => serializeTargetOutcome(row))
            .sort(
              (left, right) =>
                left.position - right.position || compareIds(left.id, right.id)
            )
        });
      });

      return AgentProtocolListResponseSchema.parse({
        protocols,
        limit: query.limit,
        nextCursor: nextCursorFor(filteredProtocols, start, page),
        totalMatched: filteredProtocols.length
      });
    },

    async listDoses({ userId, query }) {
      const fields = resolveFieldSelection(query.fields, AGENT_DOSE_FIELDS, ["id"]);
      const rows = await selectOpaque(db, schema.doses, userId);
      const from = parseOptionalDate(query.from);
      const to = parseOptionalDate(query.to);
      const filtered = rows
        .filter((row) => {
          if (!query.includeArchived && row.deletedAt !== null) {
            return false;
          }
          if (
            query.compoundId !== undefined &&
            row.payload.compound_id !== query.compoundId
          ) {
            return false;
          }
          if (
            query.protocolId !== undefined &&
            row.payload.protocol_id !== query.protocolId
          ) {
            return false;
          }
          if (
            query.provenance !== undefined &&
            row.payload.provenance !== query.provenance
          ) {
            return false;
          }
          const tookAt = parseOptionalDate(String(row.payload.took_at ?? ""));
          if (from !== null && (tookAt === null || tookAt < from)) {
            return false;
          }
          if (to !== null && (tookAt === null || tookAt > to)) {
            return false;
          }
          return true;
        })
        .sort((left, right) => {
          const leftAt = String(left.payload.took_at ?? "");
          const rightAt = String(right.payload.took_at ?? "");
          if (leftAt !== rightAt) {
            return leftAt < rightAt ? -1 : 1;
          }
          return left.id.localeCompare(right.id);
        });
      const start = cursorOffset(filtered, query.cursor);
      const page = filtered.slice(start, start + query.limit);
      return AgentDoseListResponseSchema.parse({
        doses: page.map((row) =>
          AgentDoseListItemSchema.parse(projectFields(serializeDose(row), fields))
        ),
        fields,
        limit: query.limit,
        nextCursor: nextCursorFor(filtered, start, page),
        totalMatched: filtered.length
      });
    },

    async readEffectWindow({ userId, query }) {
      const sourceCount =
        (query.compoundId !== undefined ? 1 : 0) +
        (query.protocolId !== undefined ? 1 : 0);
      if (sourceCount !== 1) {
        return {
          ok: false,
          message: "Provide exactly one of compoundId or protocolId."
        };
      }
      const metricCount =
        (query.metricId !== undefined ? 1 : 0) +
        (query.metricKey !== undefined ? 1 : 0);
      if (metricCount !== 1) {
        return {
          ok: false,
          message: "Provide exactly one of metricId or metricKey."
        };
      }
      const from = parseOptionalDate(query.from);
      const to = parseOptionalDate(query.to);
      if (from === null || to === null || from >= to) {
        return {
          ok: false,
          message: "from and to must be valid ISO-8601 timestamps with from < to."
        };
      }

      const metricRow = await resolveMetric(db, userId, query);
      if (metricRow === null) {
        return { ok: false, message: "The requested Metric was not found." };
      }

      // The window comes from every logged Dose of the Compound (or tagged to
      // the Protocol), whatever the range: the app derives its window from
      // the same Doses, and a range that clipped them would move DURING. The
      // range only scopes the Dose markers listed back.
      const doseRows = await selectOpaque(db, schema.doses, userId);
      const sourceDoses: { row: OpaqueRow; tookAt: Date }[] = [];
      for (const row of doseRows) {
        if (row.deletedAt !== null) {
          continue;
        }
        if (
          query.compoundId !== undefined &&
          row.payload.compound_id !== query.compoundId
        ) {
          continue;
        }
        if (
          query.protocolId !== undefined &&
          row.payload.protocol_id !== query.protocolId
        ) {
          continue;
        }
        const tookAt = parseOptionalDate(String(row.payload.took_at ?? ""));
        if (tookAt !== null) {
          sourceDoses.push({ row, tookAt });
        }
      }

      let windowSource: EffectWindowSource | null;
      if (query.protocolId !== undefined) {
        // An archived Protocol keeps its Effect (archive is not delete), so
        // only a Protocol that was never written is an error.
        const [protocolRow] = await db
          .select({ payload: schema.protocols.payload })
          .from(schema.protocols)
          .where(
            and(
              eq(schema.protocols.userId, userId),
              eq(schema.protocols.id, query.protocolId)
            )
          );
        if (protocolRow === undefined) {
          return { ok: false, message: "The requested Protocol was not found." };
        }
        // The bounds are local dates (D2), read at the caller's offset
        // (default UTC). Every Protocol has a start date; a row without a
        // real one declares no course, so it derives no window.
        const startLocalDate = protocolRow.payload.start_local_date;
        const endLocalDate = protocolRow.payload.end_local_date;
        windowSource =
          typeof startLocalDate !== "string" || !isValidLocalDate(startLocalDate)
            ? null
            : {
                kind: "protocol",
                ...effectBoundsFromLocalDates(
                  startLocalDate,
                  typeof endLocalDate === "string" && isValidLocalDate(endLocalDate)
                    ? endLocalDate
                    : null,
                  query.timezoneOffsetMinutes
                )
              };
      } else {
        windowSource = {
          kind: "compound",
          doseTimes: sourceDoses.map((dose) => dose.tookAt)
        };
      }
      const window =
        windowSource === null
          ? null
          : deriveEffectWindow(windowSource, new Date());

      const readingRows = await db
        .select({
          scalarValue: schema.metricReadings.scalarValue,
          atTime: schema.metricReadings.atTime,
          windowStartedAt: schema.metricReadings.windowStartedAt,
          windowEndedAt: schema.metricReadings.windowEndedAt,
          updatedAt: schema.metricReadings.updatedAt,
          deletedAt: schema.metricReadings.deletedAt
        })
        .from(schema.metricReadings)
        .where(
          and(
            eq(schema.metricReadings.userId, userId),
            eq(schema.metricReadings.metricId, metricRow.id)
          )
        );

      const samples: EffectWindowSample[] = [];
      for (const reading of readingRows) {
        if (reading.deletedAt !== null || reading.scalarValue === null) {
          continue;
        }
        const at =
          reading.atTime ?? reading.windowStartedAt ?? reading.windowEndedAt;
        if (at === null) {
          continue;
        }
        samples.push({ at, value: reading.scalarValue });
      }

      const segments = computeEffectWindowSegments({ window, samples });

      const doseMarkers = sourceDoses
        .filter((dose) => dose.tookAt >= from && dose.tookAt < to)
        .sort((left, right) => left.tookAt.getTime() - right.tookAt.getTime())
        .slice(0, AGENT_EFFECT_WINDOW_MAX_DOSES)
        .map(({ row }) => ({
          doseId: row.id,
          compoundName: String(row.payload.compound_name ?? ""),
          amountValue: Number(row.payload.amount_value ?? 0),
          unit: String(row.payload.unit ?? ""),
          route: String(row.payload.route ?? ""),
          tookAt: String(row.payload.took_at ?? "")
        }));

      return {
        ok: true,
        value: AgentEffectWindowResponseSchema.parse({
          source: {
            kind: query.compoundId !== undefined ? "compound" : "protocol",
            id: query.compoundId ?? query.protocolId!
          },
          metric: {
            id: metricRow.id,
            name: metricRow.name,
            unit: metricRow.unit
          },
          range: { from: from.toISOString(), to: to.toISOString() },
          window: {
            duringStart: window?.duringStart.toISOString() ?? null,
            duringEnd: window?.duringEnd?.toISOString() ?? null
          },
          doses: doseMarkers,
          segments: {
            before: segments.before,
            during: segments.during,
            after: segments.after
          },
          descriptiveOnly: true
        })
      };
    },

    async listProtocolPlannedDays({ userId, query }) {
      const protocols = await readPlanProtocols(db, userId, query);
      return AgentProtocolPlannedDaysResponseSchema.parse({
        fromLocalDate: query.fromLocalDate,
        toLocalDate: query.toLocalDate,
        plannedDays: planDays(protocols, query.fromLocalDate, query.toLocalDate).map(
          serializePlanDay
        )
      });
    },

    async listProtocolDayStatuses({ userId, query }) {
      const [protocols, doses] = await Promise.all([
        readPlanProtocols(db, userId, query),
        readPlanDoses(db, userId, query)
      ]);
      const statuses = dayStatuses(
        planDays(protocols, query.fromLocalDate, query.toLocalDate),
        doses,
        query.today
      );
      return AgentProtocolDayStatusesResponseSchema.parse({
        fromLocalDate: query.fromLocalDate,
        toLocalDate: query.toLocalDate,
        today: query.today,
        detail: query.detail,
        dayStatuses: statuses.map((status) => serializeDayStatus(status, query.detail))
      });
    },

    async writeDoseBatch({
      userId,
      batchId,
      requestFingerprint,
      deviceId,
      doses
    }) {
      return writeOpaqueBatch(db, {
        userId,
        batchId,
        requestFingerprint,
        deviceId,
        operationKind: "doses",
        groups: [
          {
            keyPrefix: "dose",
            rows: doses,
            tableKey: "doses",
            table: schema.doses,
            push: pushDosesInTransaction
          }
        ]
      });
    },

    async writeCompoundBatch({
      userId,
      batchId,
      requestFingerprint,
      deviceId,
      compounds
    }) {
      return writeOpaqueBatch(db, {
        userId,
        batchId,
        requestFingerprint,
        deviceId,
        operationKind: "compounds",
        groups: [
          {
            keyPrefix: "compound",
            rows: compounds,
            tableKey: "compounds",
            table: schema.compounds,
            push: pushCompoundsInTransaction
          }
        ]
      });
    },

    async writeProtocolBatch({
      userId,
      batchId,
      requestFingerprint,
      deviceId,
      today,
      protocols,
      members,
      schedules,
      targetOutcomes
    }) {
      return writeOpaqueBatch(db, {
        userId,
        batchId,
        requestFingerprint,
        deviceId,
        operationKind: "protocols",
        finalize: (transaction, serverClock) =>
          finalizeProtocolPlanRows(transaction, {
            userId,
            today,
            serverClock,
            protocols,
            members,
            schedules,
            targetOutcomes
          }),
        groups: [
          {
            keyPrefix: "protocol",
            rows: protocols,
            tableKey: "protocols",
            table: schema.protocols,
            push: pushProtocolsInTransaction
          },
          {
            keyPrefix: "member",
            rows: members,
            tableKey: "protocolCompounds",
            table: schema.protocolCompounds,
            push: pushProtocolCompoundsInTransaction
          },
          {
            keyPrefix: "schedule",
            rows: schedules,
            tableKey: "schedules",
            table: schema.schedules,
            push: pushSchedulesInTransaction
          },
          {
            keyPrefix: "outcome",
            rows: targetOutcomes,
            tableKey: "protocolTargetOutcomes",
            table: schema.protocolTargetOutcomes,
            push: pushProtocolTargetOutcomesInTransaction
          }
        ]
      });
    }
  };
}

// ---------------------------------------------------------------------------
// Store helpers
// ---------------------------------------------------------------------------

type PushInTransaction = (
  transaction: Parameters<typeof pushDosesInTransaction>[0],
  input: {
    userId: string;
    deviceId: string;
    changes: SyncPushChange[];
    serverClock: Date;
  }
) => Promise<SyncPushResult>;

type OpaqueTable =
  | typeof schema.doses
  | typeof schema.compounds
  | typeof schema.protocols
  | typeof schema.protocolCompounds
  | typeof schema.schedules
  | typeof schema.protocolTargetOutcomes;

type OpaqueTableKey =
  | "doses"
  | "compounds"
  | "protocols"
  | "protocolCompounds"
  | "schedules"
  | "protocolTargetOutcomes";

type OpaqueBatchGroup = {
  keyPrefix: string;
  rows: PreparedRow[];
  tableKey: OpaqueTableKey;
  table: OpaqueTable;
  push: PushInTransaction;
};

const OPAQUE_TABLES: Record<OpaqueTableKey, OpaqueTable> = {
  doses: schema.doses,
  compounds: schema.compounds,
  protocols: schema.protocols,
  protocolCompounds: schema.protocolCompounds,
  schedules: schema.schedules,
  protocolTargetOutcomes: schema.protocolTargetOutcomes
};

const LEGACY_PROTOCOLS_ACTIVITY_ENTITIES = [
  DOSES_SYNC_ENTITY,
  COMPOUNDS_SYNC_ENTITY,
  PROTOCOLS_SYNC_ENTITY,
  PROTOCOL_COMPOUNDS_SYNC_ENTITY,
  SCHEDULES_SYNC_ENTITY,
  PROTOCOL_TARGET_OUTCOMES_SYNC_ENTITY
] as const;

type OpaqueBatchOptions = {
  userId: string;
  batchId: string;
  requestFingerprint: string;
  deviceId: string;
  operationKind: "doses" | "compounds" | "protocols";
  groups: OpaqueBatchGroup[];
  /**
   * Work that needs stored data and must not run on a replay: it runs once
   * the receipt is claimed, may rewrite and add rows in `groups`, and
   * returns issues that refuse the whole batch, receipt included.
   */
  finalize?: (
    transaction: OpaqueTransaction,
    serverClock: Date
  ) => Promise<AgentProtocolsBatchWriteIssue[]>;
};

async function writeOpaqueBatch(
  db: ServerDatabase,
  options: OpaqueBatchOptions
): Promise<AgentProtocolsStoreWriteResult> {
  const serverClock = new Date();
  try {
    return await writeOpaqueBatchInTransaction(db, { ...options, serverClock });
  } catch (error) {
    if (error instanceof OpaqueBatchRefused) {
      return emptyAgentProtocolsWriteResult(serverClock.toISOString(), {
        validationErrors: error.issues
      });
    }
    throw error;
  }
}

/** Thrown inside the transaction so a refused batch rolls back its receipt. */
class OpaqueBatchRefused extends Error {
  constructor(readonly issues: AgentProtocolsBatchWriteIssue[]) {
    super("The Protocols batch was refused.");
  }
}

type OpaqueTransaction = Parameters<Parameters<ServerDatabase["transaction"]>[0]>[0];

async function writeOpaqueBatchInTransaction(
  db: ServerDatabase,
  {
    userId,
    batchId,
    requestFingerprint,
    deviceId,
    operationKind,
    groups,
    finalize,
    serverClock
  }: OpaqueBatchOptions & { serverClock: Date }
): Promise<AgentProtocolsStoreWriteResult> {
  return db.transaction(async (transaction) => {
    const validationErrors = await validateOpaqueBatchRows(transaction, {
      userId,
      groups
    });
    if (validationErrors.length > 0) {
      return emptyAgentProtocolsWriteResult(serverClock.toISOString(), {
        validationErrors
      });
    }

    const markerId = agentProtocolsBatchMarkerId(userId, batchId);
    const legacyBatch = await hasLegacyProtocolsBatch(transaction, {
      userId,
      batchId
    });
    const receipt = await claimAgentBatchReceipt(transaction, {
      markerId,
      userId,
      batchId,
      entityTable: AGENT_PROTOCOLS_BATCH_ENTITY,
      kind: operationKind,
      requestFingerprint,
      occurredAt: serverClock
    });
    if (receipt.status === "unavailable") {
      return emptyAgentProtocolsWriteResult(receipt.serverClock, {
        receiptUnavailable: true
      });
    }
    if (receipt.status === "conflict") {
      return emptyAgentProtocolsWriteResult(receipt.serverClock, {
        idempotencyConflict: true
      });
    }
    if (receipt.status === "duplicate" || legacyBatch) {
      return emptyAgentProtocolsWriteResult(receipt.serverClock, {
        duplicate: true
      });
    }
    if (finalize !== undefined) {
      const refused = await finalize(transaction, serverClock);
      if (refused.length > 0) {
        throw new OpaqueBatchRefused(refused);
      }
    }

    const applied: { id: string; updatedAt: string; deviceId: string }[] = [];
    const accepted: string[] = [];
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
          row.id
        );
        changes.push({
          id: row.id,
          payload: row.payload,
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          activityLogId: `agent:${batchId}:${group.keyPrefix}:${row.id}`,
          actor: "agent",
          batchId,
          beforeImage,
          afterImage: row.payload,
          occurredAt: row.updatedAt
        });
      }
      const result = await group.push(transaction, {
        userId,
        deviceId,
        changes,
        serverClock
      });
      accepted.push(...result.accepted);
      applied.push(...result.applied);
    }

    return {
      duplicate: false,
      idempotencyConflict: false,
      receiptUnavailable: false,
      serverClock: serverClock.toISOString(),
      accepted,
      applied,
      validationErrors: []
    };
  });
}

// ---------------------------------------------------------------------------
// Protocol plan finalization: the half of an Agent Protocol write that needs
// stored data (docs/designs/protocol-schedules-and-reminders.md, D1 and D6).
// It runs inside the write's transaction, after the idempotency receipt, so a
// replay never re-dates anything and a refusal rolls the receipt back.
// ---------------------------------------------------------------------------

type StoredPlanRow = {
  id: string;
  payload: Record<string, unknown>;
  deletedAt: Date | null;
};

/** A Schedule Version as D1 dates and copies it. */
type PlanVersionRow = {
  id: string;
  effectiveFrom: string;
  payload: Record<string, unknown>;
};

async function finalizeProtocolPlanRows(
  transaction: OpaqueTransaction,
  {
    userId,
    today,
    serverClock,
    protocols,
    members,
    schedules,
    targetOutcomes
  }: {
    userId: string;
    today: string;
    serverClock: Date;
    protocols: PreparedRow[];
    members: PreparedRow[];
    schedules: PreparedRow[];
    targetOutcomes: PreparedRow[];
  }
): Promise<AgentProtocolsBatchWriteIssue[]> {
  const issues: AgentProtocolsBatchWriteIssue[] = [];
  const nowIso = serverClock.toISOString();
  const protocolIds = protocols.map((row) => row.id);
  const referencedMemberIds = [
    ...new Set([
      ...members.map((row) => row.id),
      ...schedules.map((row) => String(row.payload.protocol_compound_id))
    ])
  ];

  const storedProtocols = byId(
    await selectStoredPlanRows(transaction, schema.protocols, userId, [
      inArray(schema.protocols.id, protocolIds)
    ])
  );
  const storedMembers = byId(
    await selectStoredPlanRows(transaction, schema.protocolCompounds, userId, [
      inArray(schema.protocolCompounds.id, referencedMemberIds),
      inArray(sql`${schema.protocolCompounds.payload}->>'protocol_id'`, protocolIds)
    ])
  );
  const memberIds = [...new Set([...storedMembers.keys(), ...members.map((row) => row.id)])];
  const storedVersionRows = await selectStoredPlanRows(transaction, schema.schedules, userId, [
    inArray(
      schema.schedules.id,
      schedules.map((row) => row.id)
    ),
    inArray(sql`${schema.schedules.payload}->>'protocol_compound_id'`, memberIds)
  ]);

  // Versions are insert-only: an id that exists already (for this account; the
  // ownership check refused anyone else's) can't be rewritten.
  const storedVersionIds = new Set(storedVersionRows.map((row) => row.id));
  for (const row of schedules) {
    if (storedVersionIds.has(row.id)) {
      issues.push(
        entityIssue(row.itemIndex, row.id, {
          field: row.field,
          rule: "schedule_version_exists",
          message:
            "Schedule Versions are insert-only: send a new id for every edit. This id already exists."
        })
      );
    }
  }

  // Undo tombstones a version, and a tombstoned version never existed (D1).
  // Each member's list is kept in D1's version order, so the version that
  // applies on a date, the earliest and the latest are read off it.
  const versionsByMember = new Map<string, PlanVersionRow[]>();
  for (const row of storedVersionRows) {
    const effectiveFrom = row.payload.effective_from;
    if (
      row.deletedAt !== null ||
      typeof effectiveFrom !== "string" ||
      !isValidLocalDate(effectiveFrom)
    ) {
      continue;
    }
    pushToGroup(versionsByMember, String(row.payload.protocol_compound_id), {
      id: row.id,
      effectiveFrom,
      payload: row.payload
    });
  }
  for (const versions of versionsByMember.values()) {
    versions.sort(compareScheduleVersions);
  }

  // An archived Protocol is read-only, as it is in the app's editor (D1,
  // D6): a write that names one is refused whatever it sends, a re-sent
  // `archived: true` included. A row tombstoned by undo never existed, so it
  // isn't "archived" here, but the app can't edit it either: a write that
  // names one is refused with the restore refusal, also whatever it sends,
  // so a re-sent `archived: true` can't edit it or move its start.
  const refusedProtocolIds = new Set<string>();
  for (const row of protocols) {
    const stored = storedProtocols.get(row.id);
    if (stored === undefined || stored.deletedAt === null) {
      continue;
    }
    refusedProtocolIds.add(row.id);
    issues.push(
      isUndoTombstone(stored)
        ? entityIssue(row.itemIndex, row.id, {
            field: row.field,
            rule: "archived_row_not_restorable",
            message:
              "This Protocol was removed by undo and can't be restored or edited. Create a new Protocol instead."
          })
        : entityIssue(row.itemIndex, row.id, {
            field: row.field,
            rule: "protocol_archived",
            message:
              "This Protocol is archived, and an archived Protocol is read-only. Create a new Protocol instead."
          })
    );
  }

  for (const [rows, stored] of [
    [protocols.filter((row) => !refusedProtocolIds.has(row.id)), storedProtocols],
    [members, storedMembers]
  ] as const) {
    for (const row of rows) {
      const refused = stampArchive(row, stored.get(row.id), { today, nowIso });
      if (refused !== null) {
        issues.push(refused);
      }
    }
  }

  // D1: moving the start earlier inserts re-dated copies (never an edit);
  // moving it later inserts nothing, because the version that applies on the
  // new start is already the latest one dated on or before it. On an earlier
  // move, every member row of the Protocol whose earliest version is dated on
  // or before the old start and after the new one gets a copy of that version
  // (the one in effect on its first date), dated from the new start: archived
  // members too, which still cover those days up to their archived_on, and so
  // a member this request archives. Rows tombstoned by undo never existed,
  // members with no versions already cover every date, and a member added
  // after the old start keeps its own first date. A member removed before it
  // planned anything (its stored archived_on is before its earliest version)
  // gets no copy either: it was never planned from the old start, and a copy
  // would turn days that were never in its plan into "Not logged". Its
  // archived_on is read as stored before this request, so a member this
  // request archives still gets its copy. The app's
  // _redateVersionsForStartMove skips exactly the same members. As in the
  // app, the copies come only from what was stored before this request, and
  // this request's edits are dated after them: a copy is dated before every
  // version its member has and an edit on or after the latest, so the two
  // never share a date ("No ties"). Default anchors are read as the start
  // (D4), so they need no rewriting; a copy and the period still store the
  // new start there, as the app's writes do.
  const startMoveCopies: PreparedRow[] = [];
  for (const protocol of protocols) {
    const stored = storedProtocols.get(protocol.id);
    const oldStart = stored?.payload.start_local_date;
    const newStart = String(protocol.payload.start_local_date);
    if (
      refusedProtocolIds.has(protocol.id) ||
      typeof oldStart !== "string" ||
      !isValidLocalDate(oldStart) ||
      oldStart === newStart
    ) {
      continue;
    }
    protocol.payload.period = withPeriodDefaultAnchorMoved(protocol.payload.period, newStart);
    if (newStart > oldStart) {
      continue;
    }

    const protocolMembers = [...storedMembers.values()]
      .filter((member) => member.payload.protocol_id === protocol.id && !isUndoTombstone(member))
      .sort((a, b) => compareIds(a.id, b.id));
    for (const member of protocolMembers) {
      const versions = versionsByMember.get(member.id) ?? [];
      const earliest = versions[0];
      if (
        earliest === undefined ||
        earliest.effectiveFrom > oldStart ||
        earliest.effectiveFrom <= newStart ||
        removedBeforePlanning(member, earliest.effectiveFrom)
      ) {
        continue;
      }
      const source = applyingScheduleVersion(versions, earliest.effectiveFrom)!;
      const id = createUuidV7(serverClock);
      const payload = {
        ...source.payload,
        id,
        effective_from: newStart,
        rule: withRuleDefaultAnchorMoved(source.payload.rule, newStart),
        updated_at: nowIso,
        deleted_at: null
      };
      startMoveCopies.push({
        id,
        itemIndex: protocol.itemIndex,
        field: `protocols[${protocol.itemIndex}].schedules`,
        updatedAt: nowIso,
        deletedAt: null,
        payload
      });
      insertVersion(versions, { id, effectiveFrom: newStart, payload });
      versionsByMember.set(member.id, versions);
    }
  }

  const protocolByItemIndex = new Map(protocols.map((row) => [row.itemIndex, row]));
  const batchMembers = byId(members);
  for (const row of schedules) {
    const protocol = protocolByItemIndex.get(row.itemIndex)!;
    const memberId = String(row.payload.protocol_compound_id);
    const batchMember = batchMembers.get(memberId);
    const storedMember = storedMembers.get(memberId);
    const member =
      batchMember ??
      (storedMember === undefined || isUndoTombstone(storedMember) ? undefined : storedMember);
    if (member === undefined || member.payload.protocol_id !== protocol.id) {
      issues.push(
        entityIssue(row.itemIndex, row.id, {
          field: `${row.field}.protocolCompoundId`,
          rule: "schedule_member_not_found",
          message:
            "A Schedule Version belongs to a Protocol Member of the Protocol it is listed under, in this request or already stored."
        })
      );
      continue;
    }

    // D1: a member's first version applies from the Protocol's start when the
    // member is created with its Protocol, or while the start is still ahead,
    // and from today otherwise; a later one from max(today, the latest
    // effectiveFrom), so it can never land behind, and be hidden by, another.
    const start = String(protocol.payload.start_local_date);
    const versions = versionsByMember.get(memberId) ?? [];
    const latest = versions.at(-1);
    let effectiveFrom: string;
    if (latest === undefined) {
      const createdWithProtocol =
        storedMember === undefined && !storedProtocols.has(protocol.id);
      effectiveFrom = createdWithProtocol || start > today ? start : today;
    } else {
      effectiveFrom = latest.effectiveFrom > today ? latest.effectiveFrom : today;
    }
    row.payload.effective_from = effectiveFrom;
    insertVersion(versions, { id: row.id, effectiveFrom, payload: row.payload });
    versionsByMember.set(memberId, versions);
  }
  schedules.push(...startMoveCopies);

  await assignTargetOutcomePositions(transaction, { userId, targetOutcomes });

  return issues;
}

/**
 * Fills each target outcome's `position` left null by
 * prepareAgentProtocolBatchWrite, in batch order, so an Agent outcome sorts
 * where the app would put it rather than first
 * (docs/designs/protocol-target-outcome-sync-shape.md, D3). An outcome stored
 * already under the same Protocol keeps its position, so archiving one by
 * sending deletedAt doesn't move it. A new one goes one past the largest
 * position among the Protocol's live stored outcomes (other than this batch's)
 * and this batch's earlier live outcomes. Later batch rows don't count, so the
 * result depends on batch order; positions needn't be unique.
 */
async function assignTargetOutcomePositions(
  transaction: OpaqueTransaction,
  { userId, targetOutcomes }: { userId: string; targetOutcomes: PreparedRow[] }
) {
  if (targetOutcomes.every((row) => row.payload.position !== null)) {
    return;
  }
  const protocolIds = [
    ...new Set(targetOutcomes.map((row) => String(row.payload.protocol_id)))
  ];
  const stored = await selectStoredPlanRows(
    transaction,
    schema.protocolTargetOutcomes,
    userId,
    [
      inArray(
        schema.protocolTargetOutcomes.id,
        targetOutcomes.map((row) => row.id)
      ),
      inArray(sql`${schema.protocolTargetOutcomes.payload}->>'protocol_id'`, protocolIds)
    ]
  );
  const storedById = byId(stored);
  const batchIds = new Set(targetOutcomes.map((row) => row.id));
  const largestByProtocol = new Map<string, number>();
  const noteLargest = (protocolId: string, position: number) => {
    largestByProtocol.set(
      protocolId,
      Math.max(largestByProtocol.get(protocolId) ?? -1, position)
    );
  };
  for (const row of stored) {
    if (row.deletedAt === null && !batchIds.has(row.id)) {
      noteLargest(String(row.payload.protocol_id), payloadPosition(row.payload) ?? 0);
    }
  }
  for (const row of targetOutcomes) {
    const protocolId = String(row.payload.protocol_id);
    if (row.payload.position === null) {
      const existing = storedById.get(row.id);
      const kept =
        existing !== undefined && existing.payload.protocol_id === protocolId
          ? payloadPosition(existing.payload)
          : null;
      row.payload.position = kept ?? (largestByProtocol.get(protocolId) ?? -1) + 1;
    }
    if (row.deletedAt === null) {
      noteLargest(protocolId, row.payload.position as number);
    }
  }
}

/** A plan row payload's `position` when it is a non-negative integer. */
function payloadPosition(payload: Record<string, unknown>): number | null {
  const position = payload.position;
  return typeof position === "number" && Number.isInteger(position) && position >= 0
    ? position
    : null;
}

/**
 * Turns the request's `archived` into the row's archive stamp. A new archive
 * is stamped with the current time and freezes `archived_on` as the request's
 * `today`, so an Agent can't backdate a removal; a row archived already keeps
 * its stamp. An archived row is never restored: a removed member comes back as
 * a new member row (D1), so restoring one would erase its removed days.
 */
function stampArchive(
  row: PreparedRow,
  stored: StoredPlanRow | undefined,
  { today, nowIso }: { today: string; nowIso: string }
): AgentProtocolsBatchWriteIssue | null {
  const storedArchived = stored !== undefined && stored.deletedAt !== null;
  if (row.archive === true) {
    const deletedAt = storedArchived
      ? typeof stored.payload.deleted_at === "string"
        ? stored.payload.deleted_at
        : stored.deletedAt!.toISOString()
      : nowIso;
    row.deletedAt = deletedAt;
    row.payload.deleted_at = deletedAt;
    row.payload.archived_on = storedArchived ? nullableString(stored.payload.archived_on) : today;
    return null;
  }
  if (storedArchived) {
    return entityIssue(row.itemIndex, row.id, {
      field: row.field,
      rule: "archived_row_not_restorable",
      message:
        "An archived Protocol or Protocol Member can't be restored. Send archived: true to edit it, or add the Compound again as a new member."
    });
  }
  return null;
}

/**
 * A member removed before it planned anything (D1): its stored `archived_on`
 * is before `earliestEffectiveFrom`, its earliest version's date. Such a
 * member planned no day, so a start move gives it no copy.
 */
function removedBeforePlanning(member: StoredPlanRow, earliestEffectiveFrom: string) {
  const archivedOn = nullableString(member.payload.archived_on);
  return archivedOn !== null && isValidLocalDate(archivedOn) && archivedOn < earliestEffectiveFrom;
}

/**
 * A Protocol or member row tombstoned by undo: `deleted_at` with no frozen
 * `archived_on`.
 */
function isUndoTombstone(row: StoredPlanRow) {
  return row.deletedAt !== null && nullableString(row.payload.archived_on) === null;
}

/** Inserts `version` into a list kept in D1's version order. */
function insertVersion(versions: PlanVersionRow[], version: PlanVersionRow) {
  versions.push(version);
  versions.sort(compareScheduleVersions);
}

/**
 * Writers store `times` and `weekdays` sorted (D7); the codecs accept any
 * order. Runs on the request's rule object, before it is encoded.
 */
function sortedRule(rule: unknown): unknown {
  if (!isJsonObject(rule)) {
    return rule;
  }
  const sorted: Record<string, unknown> = { ...rule };
  if (Array.isArray(rule.times)) {
    sorted.times = [...(rule.times as string[])].sort(compareIds);
  }
  if (isJsonObject(rule.days) && Array.isArray(rule.days.weekdays)) {
    sorted.days = {
      ...rule.days,
      weekdays: [...(rule.days.weekdays as number[])].sort((left, right) => left - right)
    };
  }
  return sorted;
}

/** A copied rule whose every-N anchor was left at its default moves with the start. */
function withRuleDefaultAnchorMoved(stored: unknown, newStart: string): unknown {
  return mapStoredJson(stored, (rule) => {
    const days = rule.days;
    if (
      !isJsonObject(days) ||
      days.kind !== "every_n_days" ||
      days.anchor_is_default !== true
    ) {
      return rule;
    }
    return { ...rule, days: { ...days, anchor: newStart } };
  });
}

/** A cycle anchor left at its default moves with the start. */
function withPeriodDefaultAnchorMoved(stored: unknown, newStart: string): unknown {
  return mapStoredJson(stored, (period) => {
    const cycle = period.cycle;
    if (!isJsonObject(cycle) || cycle.anchor_is_default !== true) {
      return period;
    }
    return { ...period, cycle: { ...cycle, anchor: newStart } };
  });
}

/**
 * Applies `map` to a stored JSON object and returns it as JSON text, the form
 * every writer stores (Data shapes). Agent writes made before that rule
 * stored the object itself; a copy of such a row is written as text too. A
 * value that holds no JSON object is returned as stored.
 */
function mapStoredJson(
  stored: unknown,
  map: (object: Record<string, unknown>) => Record<string, unknown>
): unknown {
  const object = readJsonObject(stored);
  if (object === null) {
    return stored;
  }
  return JSON.stringify(map(object));
}

/** A stored JSON object, whether synced as an object or as JSON text; else null. */
function readJsonObject(value: unknown): Record<string, unknown> | null {
  if (isJsonObject(value)) {
    return value;
  }
  if (typeof value !== "string") {
    return null;
  }
  try {
    const parsed: unknown = JSON.parse(value);
    return isJsonObject(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

function byId<T extends { id: string }>(rows: readonly T[]) {
  return new Map(rows.map((row) => [row.id, row]));
}

async function selectStoredPlanRows(
  transaction: Pick<ServerDatabase, "select">,
  table:
    | typeof schema.protocols
    | typeof schema.protocolCompounds
    | typeof schema.schedules
    | typeof schema.protocolTargetOutcomes,
  userId: string,
  anyOf: ReturnType<typeof inArray>[]
): Promise<StoredPlanRow[]> {
  return transaction
    .select({ id: table.id, payload: table.payload, deletedAt: table.deletedAt })
    .from(table)
    .where(and(eq(table.userId, userId), or(...anyOf)));
}

export function agentProtocolsBatchMarkerId(userId: string, batchId: string) {
  return scopedAgentBatchReceiptId({
    scope: "protocols",
    userId,
    batchId
  });
}

function emptyAgentProtocolsWriteResult(
  serverClock: string,
  overrides: Partial<AgentProtocolsStoreWriteResult> = {}
): AgentProtocolsStoreWriteResult {
  return {
    duplicate: false,
    idempotencyConflict: false,
    receiptUnavailable: false,
    serverClock,
    accepted: [],
    applied: [],
    validationErrors: [],
    ...overrides
  };
}

async function hasLegacyProtocolsBatch(
  transaction: Pick<ServerDatabase, "select">,
  { userId, batchId }: { userId: string; batchId: string }
) {
  const rows = await transaction
    .select({ id: schema.activityLog.id })
    .from(schema.activityLog)
    .where(
      and(
        eq(schema.activityLog.userId, userId),
        eq(schema.activityLog.actor, "agent"),
        eq(schema.activityLog.batchId, batchId),
        inArray(
          schema.activityLog.entityTable,
          LEGACY_PROTOCOLS_ACTIVITY_ENTITIES
        )
      )
    )
    .limit(1);
  return rows.length > 0;
}

async function validateOpaqueBatchRows(
  transaction: Pick<ServerDatabase, "select">,
  { userId, groups }: { userId: string; groups: OpaqueBatchGroup[] }
) {
  const errors: z.infer<typeof AgentProtocolsBatchWriteIssueSchema>[] = [];
  const requestedIds = new Map<OpaqueTableKey, Set<string>>();
  const owners = new Map<OpaqueTableKey, Map<string, string>>();

  for (const group of groups) {
    requestedIds.set(group.tableKey, new Set(group.rows.map((row) => row.id)));
    owners.set(
      group.tableKey,
      await readOpaqueOwners(
        transaction,
        group.table,
        userId,
        group.rows.map((row) => row.id)
      )
    );
    const groupOwners = owners.get(group.tableKey)!;
    for (const row of group.rows) {
      const owner = groupOwners.get(row.id);
      if (owner !== undefined && owner !== userId) {
        errors.push(
          entityIssue(row.itemIndex, row.id, {
            field: row.field,
            rule: "row_owned_by_another_user",
            message: "This row id already belongs to another account."
          })
        );
      } else if (owner === undefined && !UUID_V7_PATTERN.test(row.id)) {
        errors.push(
          entityIssue(row.itemIndex, row.id, {
            field: row.field,
            rule: "new_row_id_must_be_uuidv7",
            message:
              "New Protocols rows require a client-supplied UUIDv7. Existing legacy ids may only be edited or archived."
          })
        );
      }
    }
  }

  const references = groups.flatMap((group) =>
    group.rows.flatMap((row) =>
      (row.references ?? []).map((reference) => ({ row, reference }))
    )
  );
  for (const tableKey of [
    "compounds",
    "protocols",
    "protocolCompounds"
  ] as const) {
    const tableReferences = references.filter(
      ({ reference }) => reference.table === tableKey
    );
    const ids = [...new Set(tableReferences.map(({ reference }) => reference.id))];
    if (ids.length === 0) {
      continue;
    }
    const tableOwners = new Map(owners.get(tableKey) ?? []);
    const referencedOwners = await readOpaqueOwners(
      transaction,
      OPAQUE_TABLES[tableKey],
      userId,
      ids
    );
    for (const [id, owner] of referencedOwners) {
      tableOwners.set(id, owner);
    }
    owners.set(tableKey, tableOwners);
    const sameBatchIds = requestedIds.get(tableKey) ?? new Set<string>();

    for (const { row, reference } of tableReferences) {
      if (sameBatchIds.has(reference.id)) {
        continue;
      }
      const owner = tableOwners.get(reference.id);
      if (owner !== undefined && owner !== userId) {
        errors.push(
          entityIssue(row.itemIndex, row.id, {
            field: reference.field,
            rule: "reference_owned_by_another_user",
            message: "The referenced row belongs to another account."
          })
        );
      } else if (owner === undefined && !UUID_V7_PATTERN.test(reference.id)) {
        errors.push(
          entityIssue(row.itemIndex, row.id, {
            field: reference.field,
            rule: "legacy_reference_not_found",
            message:
              "A non-UUIDv7 reference is valid only when it resolves to an existing row owned by this account."
          })
        );
      }
    }
  }
  return errors;
}

// `compounds` is keyed (user_id, id) because OTC seed Compound ids are shared
// by every account: another account's row under the same id is that account's
// own Compound, not an owner of this one, so only the caller's rows count.
const ACCOUNT_KEYED_OPAQUE_TABLES: ReadonlySet<OpaqueTable> = new Set([
  schema.compounds
]);

async function readOpaqueOwners(
  transaction: Pick<ServerDatabase, "select">,
  table: OpaqueTable,
  userId: string,
  ids: string[]
) {
  if (ids.length === 0) {
    return new Map<string, string>();
  }
  const rows = await transaction
    .select({ id: table.id, userId: table.userId })
    .from(table)
    .where(
      ACCOUNT_KEYED_OPAQUE_TABLES.has(table)
        ? and(eq(table.userId, userId), inArray(table.id, ids))
        : inArray(table.id, ids)
    );
  return new Map(rows.map((row) => [row.id, row.userId]));
}

async function readBeforeImage(
  transaction: Pick<ServerDatabase, "select">,
  table: OpaqueTable,
  userId: string,
  id: string
) {
  const existingRows = await transaction
    .select({ userId: table.userId, payload: table.payload })
    .from(table)
    // Scoped by owner as well as id: `compounds` is keyed (user_id, id)
    // because OTC seed Compound ids are shared by every account.
    .where(and(eq(table.userId, userId), eq(table.id, id)))
    .limit(1);
  const existing = existingRows[0];
  if (existing === undefined || existing.userId !== userId) {
    return null;
  }
  return existing.payload;
}

async function selectOpaque(
  db: ServerDatabase,
  table: OpaqueTable,
  userId: string,
  condition?: SQL
): Promise<OpaqueRow[]> {
  return db
    .select({
      id: table.id,
      payload: table.payload,
      updatedAt: table.updatedAt,
      deletedAt: table.deletedAt
    })
    .from(table)
    .where(and(eq(table.userId, userId), condition))
    .orderBy(asc(table.id));
}

/**
 * The plan rows `planDays` reads, as the app's plan query reads them
 * (`ProtocolPlanRepository._planQuery`): every Protocol and Protocol Member
 * except rows tombstoned by undo (archived ones are kept with their frozen
 * dates, so past days still count them, D1), and every Schedule Version not
 * tombstoned. As there, a member counts only while the user holds a row for
 * its Compound (archived or not): the app's query inner-joins `compounds`, so
 * a member synced before its Compound plans nothing in either. Each query is
 * scoped to the user; with a `protocolId` only that Protocol, its members and
 * their versions are read. A `compoundId` keeps only that Compound's member
 * rows (and their versions), which leaves its PlanDays exactly as a read of
 * the whole plan gives them, because `planDays` decides each Protocol,
 * Compound and date on its own.
 *
 * A row the codecs can't read is left out rather than failing the read, as
 * the Protocol list read leaves it out: a Protocol with no real start date
 * (synced before local dates, D3) plans nothing, a version whose
 * `effectiveFrom` or rule the codec can't read is skipped, and a period it
 * can't read reads as none.
 */
async function readPlanProtocols(
  db: ServerDatabase,
  userId: string,
  query: { protocolId?: string; compoundId?: string }
): Promise<PlanProtocol[]> {
  const { protocolId, compoundId } = query;
  const memberPayload = schema.protocolCompounds.payload;
  const memberFilter = and(
    protocolId === undefined ? undefined : sql`${memberPayload}->>'protocol_id' = ${protocolId}`,
    compoundId === undefined ? undefined : sql`${memberPayload}->>'compound_id' = ${compoundId}`
  );
  const [protocolRows, memberRows, scheduleRows] = await Promise.all([
    selectOpaque(
      db,
      schema.protocols,
      userId,
      protocolId === undefined ? undefined : eq(schema.protocols.id, protocolId)
    ),
    selectOpaque(
      db,
      schema.protocolCompounds,
      userId,
      and(
        memberFilter,
        inArray(
          sql`${memberPayload}->>'compound_id'`,
          db
            .select({ id: schema.compounds.id })
            .from(schema.compounds)
            .where(eq(schema.compounds.userId, userId))
        )
      )
    ),
    // A Schedule Version names its member, not its Protocol or Compound, so
    // a filtered read's versions are the ones naming its filtered members.
    selectOpaque(
      db,
      schema.schedules,
      userId,
      memberFilter === undefined
        ? undefined
        : inArray(
            sql`${schema.schedules.payload}->>'protocol_compound_id'`,
            db
              .select({ id: schema.protocolCompounds.id })
              .from(schema.protocolCompounds)
              .where(and(eq(schema.protocolCompounds.userId, userId), memberFilter))
          )
    )
  ]);
  const members = memberRows.filter(
    (row) => !isUndoTombstone(row) && typeof row.payload.compound_id === "string"
  );

  const membersByProtocol = groupBy(members, (row) => String(row.payload.protocol_id ?? ""));
  const versionsByMember = groupBy(
    scheduleRows.filter((row) => row.deletedAt === null),
    (row) => String(row.payload.protocol_compound_id ?? "")
  );
  const protocols: PlanProtocol[] = [];
  for (const row of protocolRows) {
    const startLocalDate = localDateOrNull(row.payload.start_local_date);
    const protocolMembers = membersByProtocol.get(row.id) ?? [];
    if (isUndoTombstone(row) || startLocalDate === null || protocolMembers.length === 0) {
      continue;
    }
    protocols.push({
      protocolId: row.id,
      startLocalDate,
      endLocalDate: localDateOrNull(row.payload.end_local_date),
      period: readStoredPeriod(row.payload.period),
      archivedOn: localDateOrNull(row.payload.archived_on),
      remindersEnabled: row.payload.reminders_enabled === true,
      members: protocolMembers.map((member) => ({
        memberId: member.id,
        compoundId: String(member.payload.compound_id),
        archivedOn: localDateOrNull(member.payload.archived_on),
        versions: (versionsByMember.get(member.id) ?? []).flatMap((version) => {
          const serialized = serializeScheduleVersion(version);
          return serialized === null
            ? []
            : [
                {
                  id: serialized.id,
                  effectiveFrom: serialized.effectiveFrom,
                  rule: serialized.rule,
                  amountValue: serialized.doseAmountValue,
                  amountEntered: serialized.doseAmountEntered,
                  unit: serialized.doseUnit,
                  route: serialized.route
                }
              ];
        })
      }))
    });
  }
  return protocols;
}

/**
 * The range's logged Doses as matching reads them (D6 step 2), the same set
 * the app numbers (`ProtocolPlanRepository._planDoses`): every Dose not
 * archived, tagged or not, of a Compound, on its frozen local date. Its local
 * time is its instant at its frozen UTC offset; a Dose logged before offsets
 * were frozen has none and is read in UTC (D2). `sequence` numbers a
 * Compound's Doses on a date by local time, then id. The Protocol filter does
 * not apply: a Dose's tag never decides what it fills, and Doses of a
 * Compound the plan read doesn't plan are ignored by `dayStatuses`.
 */
async function readPlanDoses(
  db: ServerDatabase,
  userId: string,
  query: { fromLocalDate: string; toLocalDate: string; compoundId?: string }
): Promise<PlanDose[]> {
  // Byte order ("C"), so the range compares YYYY-MM-DD dates whatever the
  // database's default collation.
  const localDate = sql`(${schema.doses.payload}->>'local_date') collate "C"`;
  const rows = await selectOpaque(
    db,
    schema.doses,
    userId,
    and(
      isNull(schema.doses.deletedAt),
      sql`${localDate} between ${query.fromLocalDate} and ${query.toLocalDate}`,
      query.compoundId === undefined
        ? undefined
        : sql`${schema.doses.payload}->>'compound_id' = ${query.compoundId}`
    )
  );

  const doses: Omit<PlanDose, "sequence">[] = [];
  for (const row of rows) {
    const compoundId = nullableString(row.payload.compound_id);
    const doseLocalDate = localDateOrNull(row.payload.local_date);
    const localTime = doseLocalTime(row.payload);
    if (compoundId === null || doseLocalDate === null || localTime === null) {
      continue;
    }
    doses.push({ doseId: row.id, compoundId, localDate: doseLocalDate, localTime });
  }
  doses.sort(
    (left, right) =>
      compareIds(left.localTime, right.localTime) || compareIds(left.doseId, right.doseId)
  );
  const sequenceByGroup = new Map<string, number>();
  return doses.map((dose) => {
    const key = `${dose.compoundId}\u0000${dose.localDate}`;
    const sequence = sequenceByGroup.get(key) ?? 0;
    sequenceByGroup.set(key, sequence + 1);
    return { ...dose, sequence };
  });
}

/**
 * A Dose's local clock time, `HH:MM`: its `took_at` at its frozen
 * `timezone_offset_minutes`, or in UTC when it has none (D2). Null when
 * `took_at` is not a timestamp.
 */
function doseLocalTime(payload: Record<string, unknown>): string | null {
  const tookAt = parseOptionalDate(
    typeof payload.took_at === "string" ? payload.took_at : undefined
  );
  if (tookAt === null) {
    return null;
  }
  const offset = payload.timezone_offset_minutes;
  const offsetMinutes = typeof offset === "number" && Number.isInteger(offset) ? offset : 0;
  const clock = new Date(tookAt.getTime() + offsetMinutes * 60_000);
  return `${String(clock.getUTCHours()).padStart(2, "0")}:${String(clock.getUTCMinutes()).padStart(2, "0")}`;
}

function localDateOrNull(value: unknown): string | null {
  return typeof value === "string" && isValidLocalDate(value) ? value : null;
}

async function resolveMetric(
  db: ServerDatabase,
  userId: string,
  query: AgentEffectWindowQuery
): Promise<{ id: string; name: string; unit: string } | null> {
  const rows = await db
    .select({
      id: schema.metrics.id,
      name: schema.metrics.name,
      unit: schema.metrics.unit
    })
    .from(schema.metrics)
    .where(eq(schema.metrics.userId, userId));
  if (query.metricId !== undefined) {
    return rows.find((row) => row.id === query.metricId) ?? null;
  }
  const key = query.metricKey!.toLowerCase();
  return rows.find((row) => row.name.toLowerCase() === key) ?? null;
}

// ---------------------------------------------------------------------------
// Serialization (opaque payload → agent read shape)
// ---------------------------------------------------------------------------

function serializeCompound(row: OpaqueRow) {
  return {
    id: row.id,
    name: String(row.payload.name ?? ""),
    defaultUnit: String(row.payload.default_unit ?? ""),
    defaultRoute: String(row.payload.default_route ?? ""),
    strength: readStrength(row.payload.strength),
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  };
}

function serializeDose(row: OpaqueRow) {
  return {
    id: row.id,
    compoundId: nullableString(row.payload.compound_id),
    compoundName: String(row.payload.compound_name ?? ""),
    compoundStrength: readStrength(row.payload.compound_strength),
    amountValue: Number(row.payload.amount_value ?? 0),
    amountEntered: String(row.payload.amount_entered ?? ""),
    unit: String(row.payload.unit ?? ""),
    route: String(row.payload.route ?? ""),
    tookAt: String(row.payload.took_at ?? row.updatedAt.toISOString()),
    timezone: String(row.payload.timezone ?? "UTC"),
    // A Dose logged before offsets were frozen has none, and reads null.
    timezoneOffsetMinutes:
      typeof row.payload.timezone_offset_minutes === "number"
        ? row.payload.timezone_offset_minutes
        : null,
    localDate: String(row.payload.local_date ?? ""),
    provenance: String(row.payload.provenance ?? "manual"),
    protocolId: nullableString(row.payload.protocol_id),
    protocolName: nullableString(row.payload.protocol_name),
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  };
}

function serializeProtocol(row: OpaqueRow) {
  return {
    id: row.id,
    name: String(row.payload.name ?? ""),
    startLocalDate: nullableString(row.payload.start_local_date),
    endLocalDate: nullableString(row.payload.end_local_date),
    period: readStoredPeriod(row.payload.period),
    remindersEnabled: row.payload.reminders_enabled === true,
    archivedOn: nullableString(row.payload.archived_on),
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  };
}

function serializeMember(row: OpaqueRow, versionRows: readonly OpaqueRow[]) {
  // Versions tombstoned by undo never existed (D1), so they are left out.
  // A version whose stored JSON the codec can't read can't be planned on
  // either, and is left out rather than failing the whole read.
  const versions = versionRows
    .filter((version) => version.deletedAt === null)
    .flatMap((version) => {
      const serialized = serializeScheduleVersion(version);
      return serialized === null ? [] : [serialized];
    })
    .sort(compareScheduleVersions);
  return {
    id: row.id,
    compoundId: String(row.payload.compound_id ?? ""),
    position: Number(row.payload.position ?? 0),
    archivedOn: nullableString(row.payload.archived_on),
    versions,
    // The latest effectiveFrom, the larger id on a tie: the last in this order.
    currentVersion: versions.at(-1) ?? null,
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  };
}

function serializeScheduleVersion(row: OpaqueRow) {
  const effectiveFrom = row.payload.effective_from;
  if (typeof effectiveFrom !== "string" || !isValidLocalDate(effectiveFrom)) {
    return null;
  }
  let rule: ScheduleRule;
  try {
    rule = decodeScheduleRule(readJsonObject(row.payload.rule));
  } catch (error) {
    if (error instanceof ProtocolPlanCodecError) {
      return null;
    }
    throw error;
  }
  return {
    id: row.id,
    protocolCompoundId: String(row.payload.protocol_compound_id ?? ""),
    effectiveFrom,
    rule,
    doseAmountValue:
      row.payload.dose_amount_value === null ||
      row.payload.dose_amount_value === undefined
        ? null
        : Number(row.payload.dose_amount_value),
    doseAmountEntered: nullableString(row.payload.dose_amount_entered),
    doseUnit: nullableString(row.payload.dose_unit),
    route: nullableString(row.payload.route),
    updatedAt: row.updatedAt.toISOString()
  };
}

/** A stored period through the codec; one it can't read reads as no period. */
function readStoredPeriod(value: unknown): ProtocolPeriod | null {
  try {
    return decodeProtocolPeriod(value === null || value === undefined ? null : readJsonObject(value));
  } catch (error) {
    if (error instanceof ProtocolPlanCodecError) {
      return null;
    }
    throw error;
  }
}

function serializePlanDay(day: PlanDay) {
  return {
    protocolId: day.protocolId,
    compoundId: day.compoundId,
    localDate: day.localDate,
    state: day.state,
    planned: day.planned.map((planned) => ({
      localTime: planned.localTime,
      ...readPlanAmount(planned)
    }))
  };
}

function serializeDayStatus(status: DayStatus, detail: "summary" | "doses") {
  return {
    compoundId: status.compoundId,
    localDate: status.localDate,
    status: status.status,
    ...(status.notPlannedReason === undefined
      ? {}
      : { notPlannedReason: status.notPlannedReason }),
    plannedCount: status.plannedCount,
    loggedCount: status.loggedCount,
    extraCount: status.extraCount,
    ...(detail === "doses"
      ? {
          fills: status.fills.map((fill) => ({
            slot: fill.slot,
            protocolId: fill.protocolId,
            plannedLocalTime: fill.plannedLocalTime,
            ...readPlanAmount(fill),
            doseId: fill.doseId
          }))
        }
      : {})
  };
}

function readPlanAmount(amount: PlanAmount) {
  return {
    amountValue: amount.amountValue ?? null,
    amountEntered: amount.amountEntered ?? null,
    unit: amount.unit ?? null,
    route: amount.route ?? null
  };
}

/**
 * Reads `kind`, the key the app writes. An Agent write stored `outcome_kind`
 * and no `position` before docs/designs/protocol-target-outcome-sync-shape.md
 * (D4, D5), and an Agent undo can restore such a payload, so both fall back.
 */
function serializeTargetOutcome(row: OpaqueRow) {
  const kind = row.payload.kind;
  const legacyKind = row.payload.outcome_kind;
  return {
    id: row.id,
    metricId: nullableString(row.payload.metric_id),
    outcomeKind:
      typeof kind === "string" && kind.length > 0
        ? kind
        : typeof legacyKind === "string" && legacyKind.length > 0
          ? legacyKind
          : "metric",
    position: payloadPosition(row.payload) ?? 0,
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  };
}

function readStrength(value: unknown) {
  if (value === null || value === undefined || typeof value !== "object") {
    return null;
  }
  const record = value as Record<string, unknown>;
  if (
    typeof record.value !== "number" ||
    typeof record.massUnit !== "string" ||
    typeof record.perUnit !== "string"
  ) {
    return null;
  }
  return {
    value: record.value,
    massUnit: record.massUnit,
    perUnit: record.perUnit
  };
}

function strengthPayload(
  strength: { value: number; massUnit: string; perUnit: string } | null | undefined
) {
  return strength === null || strength === undefined
    ? null
    : { value: strength.value, massUnit: strength.massUnit, perUnit: strength.perUnit };
}

// ---------------------------------------------------------------------------
// Shared small helpers (mirror agent-metrics)
// ---------------------------------------------------------------------------

function fieldsQuery(fieldSet: Set<string>, label: string) {
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
      `fields must be a comma-separated list of known ${label} fields`
    );
}

function resolveFieldSelection<const T extends readonly string[]>(
  value: string | undefined,
  allFields: T,
  requiredFields: readonly T[number][]
): T[number][] {
  if (value === undefined) {
    return [...allFields];
  }
  return [
    ...new Set<T[number]>([
      ...requiredFields,
      ...(value
        .split(",")
        .map((field) => field.trim())
        .filter((field): field is T[number] =>
          (allFields as readonly string[]).includes(field)
        ) as T[number][])
    ])
  ];
}

function projectFields<T extends Record<string, unknown>>(
  value: T,
  fields: readonly string[]
) {
  return Object.fromEntries(
    fields.filter((field) => field in value).map((field) => [field, value[field]])
  );
}

function cursorOffset<T extends { id: string }>(
  rows: readonly T[],
  cursor: string | undefined
) {
  if (cursor === undefined) {
    return 0;
  }
  const index = rows.findIndex((row) => row.id === cursor);
  return index < 0 ? 0 : index + 1;
}

function nextCursorFor<T extends { id: string }>(
  filtered: readonly T[],
  start: number,
  page: readonly T[]
) {
  return start + page.length >= filtered.length
    ? null
    : page[page.length - 1]?.id ?? null;
}

function groupBy<T>(rows: readonly T[], key: (row: T) => string) {
  const map = new Map<string, T[]>();
  for (const row of rows) {
    pushToGroup(map, key(row), row);
  }
  return map;
}

function memberPosition(row: OpaqueRow) {
  return Number(row.payload.position ?? 0);
}

function parseOptionalDate(value: string | undefined) {
  if (value === undefined || value.length === 0) {
    return null;
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function parseAmountValue(amount: string | number): number {
  if (typeof amount === "number") {
    return amount;
  }
  const parsed = Number(amount.trim());
  return Number.isNaN(parsed) ? 0 : parsed;
}

function nullableString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function doseIssue(
  itemIndex: number,
  doseId: string,
  issue: AgentDoseValidationIssue
): AgentDoseBatchWriteIssue {
  return AgentDoseBatchWriteIssueSchema.parse({
    ...issue,
    field: issue.field.startsWith("doses[")
      ? issue.field
      : `doses[${itemIndex}].${issue.field}`,
    itemIndex,
    doseId
  });
}

function entityIssue(
  itemIndex: number,
  entityId: string | null,
  issue: { field: string; rule: string; message: string }
): z.infer<typeof AgentProtocolsBatchWriteIssueSchema> {
  return AgentProtocolsBatchWriteIssueSchema.parse({
    ...issue,
    itemIndex,
    entityId
  });
}
