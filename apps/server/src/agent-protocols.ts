import { createRoute, z } from "@hono/zod-openapi";
import { and, asc, eq, inArray } from "drizzle-orm";

import {
  agentBatchRequestFingerprint,
  claimAgentBatchReceipt,
  scopedAgentBatchReceiptId
} from "./agent-batch-receipt.js";
import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import {
  AgentDoseValidationIssueSchema,
  AgentDoseValidationLimitsSchema,
  DOSE_ROUTES,
  DOSE_UNITS,
  doseValidationLimitsResponse,
  validateAgentDose,
  type AgentDoseValidationIssue
} from "./agent-validation.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
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
  "localDate",
  "provenance",
  "protocolId",
  "protocolName",
  "updatedAt",
  "deletedAt"
] as const;

const compoundFieldSet = new Set<string>(AGENT_COMPOUND_FIELDS);
const doseFieldSet = new Set<string>(AGENT_DOSE_FIELDS);

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
    timezone: z.string().min(1),
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
    timezone: z.string().min(1).optional(),
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
const AgentProtocolMemberSchema = z
  .object({
    id: z.string().min(1),
    compoundId: z.string().min(1),
    position: z.number().int().min(0),
    updatedAt: ISO8601StringSchema,
    deletedAt: ISO8601StringSchema.nullable()
  })
  .openapi("AgentProtocolMember");

const AgentProtocolScheduleSchema = z
  .object({
    id: z.string().min(1),
    protocolCompoundId: z.string().min(1),
    doseAmountValue: z.number().nullable(),
    doseAmountEntered: z.string().min(1).nullable(),
    doseUnit: DoseUnitSchema.nullable(),
    frequency: z.string().min(1),
    route: DoseRouteSchema.nullable(),
    updatedAt: ISO8601StringSchema,
    deletedAt: ISO8601StringSchema.nullable()
  })
  .openapi("AgentProtocolSchedule");

const AgentProtocolTargetOutcomeSchema = z
  .object({
    id: z.string().min(1),
    metricId: z.string().min(1).nullable(),
    outcomeKind: z.string().min(1),
    updatedAt: ISO8601StringSchema,
    deletedAt: ISO8601StringSchema.nullable()
  })
  .openapi("AgentProtocolTargetOutcome");

export const AgentProtocolSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1),
    startDate: ISO8601StringSchema.nullable(),
    endDate: ISO8601StringSchema.nullable(),
    updatedAt: ISO8601StringSchema,
    deletedAt: ISO8601StringSchema.nullable(),
    members: z.array(AgentProtocolMemberSchema),
    schedules: z.array(AgentProtocolScheduleSchema),
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
      description: "IANA timezone captured at log time."
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

const AgentProtocolBatchWriteMemberSchema = z
  .object({
    id: ClientRowIdSchema.openapi({
      description:
        "UUIDv7 Protocol member id for a new row, or an existing legacy id for an edit/archive."
    }),
    compoundId: AgentProtocolsReferenceIdSchema,
    position: z.number().int().min(0).default(0),
    updatedAt: ISO8601StringSchema.optional(),
    deletedAt: ISO8601StringSchema.nullable().default(null)
  })
  .openapi("AgentProtocolBatchWriteMember");

const AgentProtocolBatchWriteScheduleSchema = z
  .object({
    id: ClientRowIdSchema.openapi({
      description:
        "UUIDv7 Schedule id for a new row, or an existing legacy id for an edit/archive."
    }),
    protocolCompoundId: AgentProtocolsReferenceIdSchema,
    doseAmountValue: z.number().nullable().default(null),
    doseAmountEntered: z.string().trim().min(1).nullable().default(null),
    doseUnit: DoseUnitSchema.nullable().default(null),
    frequency: z.string().trim().min(1),
    route: DoseRouteSchema.nullable().default(null),
    updatedAt: ISO8601StringSchema.optional(),
    deletedAt: ISO8601StringSchema.nullable().default(null)
  })
  .openapi("AgentProtocolBatchWriteSchedule");

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
    outcomeKind: z.string().trim().min(1).default("metric"),
    updatedAt: ISO8601StringSchema.optional(),
    deletedAt: ISO8601StringSchema.nullable().default(null)
  })
  .openapi("AgentProtocolBatchWriteTargetOutcome");

export const AgentProtocolBatchWriteProtocolSchema = z
  .object({
    id: ClientRowIdSchema.openapi({
      description:
        "UUIDv7 Protocol id for a new row, or an existing legacy id for an edit/archive."
    }),
    name: z.string().trim().min(1),
    startDate: ISO8601StringSchema.nullable().default(null),
    endDate: ISO8601StringSchema.nullable().default(null),
    updatedAt: ISO8601StringSchema.optional(),
    deletedAt: ISO8601StringSchema.nullable().default(null).openapi({
      description:
        "Set to archive the Protocol. Archiving is a plan edit — it never cascades to a logged Dose (PROTOCOLS.md §7)."
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
  .openapi("AgentProtocolBatchWriteProtocol");

export const AgentProtocolBatchWriteRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200).openapi({
      description:
        "Stable key for this agent request. Replays with the same key do not append another Activity Log batch."
    }),
    protocols: z
      .array(AgentProtocolBatchWriteProtocolSchema)
      .min(1)
      .max(AGENT_PROTOCOL_BATCH_WRITE_MAX_PROTOCOLS)
      .openapi({
        description:
          "Protocols (plus their members, schedules, and target outcomes) to create, edit, or archive. Plan writes never touch logged Doses."
      })
  })
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
    protocols: z.array(AgentEntityBatchWriteResultSchema)
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
        "The Compound whose logged Doses drive the timeline. Provide exactly one of compoundId or protocolId."
    }),
    protocolId: z.string().trim().min(1).optional().openapi({
      param: { name: "protocolId", in: "query" },
      description:
        "The Protocol whose tagged Doses drive the timeline. Provide exactly one of compoundId or protocolId."
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
      description: "Inclusive ISO-8601 lower bound of the analysis range."
    }),
    to: z.string().trim().min(1).openapi({
      param: { name: "to", in: "query" },
      description: "Exclusive ISO-8601 upper bound of the analysis range."
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
    "Returns a bounded page of Protocols, each with its member Compounds, Schedules, and declared target outcomes (all plan data — never derived analytics).",
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
  summary: "Batch-write Protocols (plan + schedules + target outcomes).",
  description:
    "Authenticated agent write path for Protocol plans. Creates, edits, and archives Protocols with their member Compounds, Schedules, and target outcomes in one idempotent batch. Plan writes never touch logged Doses — archiving a Protocol never cascades (PROTOCOLS.md §7).",
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
    "Computes a descriptive before/during/after summary of one outcome Metric around the logged Dose timeline of a Compound or Protocol over a range. Aggregates (count/min/max/mean) are computed on demand and never stored. Strictly descriptive — never a causal, efficacy, or medical claim.",
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

// ---------------------------------------------------------------------------
// Inferred types
// ---------------------------------------------------------------------------

export type AgentCompoundListQuery = z.infer<typeof AgentCompoundListQuerySchema>;
export type AgentProtocolListQuery = z.infer<typeof AgentProtocolListQuerySchema>;
export type AgentDoseListQuery = z.infer<typeof AgentDoseListQuerySchema>;
export type AgentEffectWindowQuery = z.infer<typeof AgentEffectWindowQuerySchema>;
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
};

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

export function prepareAgentProtocolBatchWrite({
  request,
  now = new Date()
}: {
  request: AgentProtocolBatchWriteRequest;
  now?: Date;
}):
  | {
      accepted: true;
      protocols: PreparedRow[];
      members: PreparedRow[];
      schedules: PreparedRow[];
      targetOutcomes: PreparedRow[];
      responseProtocols: PreparedEntityResult[];
    }
  | {
      accepted: false;
      errors: z.infer<typeof AgentProtocolsBatchWriteIssueSchema>[];
    } {
  const errors: z.infer<typeof AgentProtocolsBatchWriteIssueSchema>[] = [];
  const protocols: PreparedRow[] = [];
  const members: PreparedRow[] = [];
  const schedules: PreparedRow[] = [];
  const targetOutcomes: PreparedRow[] = [];
  const responseProtocols: PreparedEntityResult[] = [];
  const nowIso = now.toISOString();
  const seenProtocol = new Set<string>();
  const seenRow = new Set<string>();

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

    const updatedAt = protocol.updatedAt ?? nowIso;
    const deletedAt = protocol.deletedAt ?? null;
    protocols.push({
      id: protocol.id,
      itemIndex,
      field: `protocols[${itemIndex}].id`,
      updatedAt,
      deletedAt,
      payload: {
        id: protocol.id,
        name: protocol.name,
        start_date: protocol.startDate,
        end_date: protocol.endDate,
        updated_at: updatedAt,
        deleted_at: deletedAt
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
        deletedAt: member.deletedAt ?? null,
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
          updated_at: memberUpdatedAt,
          deleted_at: member.deletedAt ?? null
        }
      });
    }

    for (const scheduleRow of protocol.schedules) {
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
      const scheduleUpdatedAt = scheduleRow.updatedAt ?? nowIso;
      schedules.push({
        id: scheduleRow.id,
        itemIndex,
        field: `protocols[${itemIndex}].schedules`,
        updatedAt: scheduleUpdatedAt,
        deletedAt: scheduleRow.deletedAt ?? null,
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
          dose_amount_value: scheduleRow.doseAmountValue,
          dose_amount_entered: scheduleRow.doseAmountEntered,
          dose_unit: scheduleRow.doseUnit,
          frequency: scheduleRow.frequency,
          route: scheduleRow.route,
          updated_at: scheduleUpdatedAt,
          deleted_at: scheduleRow.deletedAt ?? null
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
      const outcomeUpdatedAt = outcome.updatedAt ?? nowIso;
      targetOutcomes.push({
        id: outcome.id,
        itemIndex,
        field: `protocols[${itemIndex}].targetOutcomes`,
        updatedAt: outcomeUpdatedAt,
        deletedAt: outcome.deletedAt ?? null,
        payload: {
          id: outcome.id,
          protocol_id: protocol.id,
          metric_id: outcome.metricId,
          outcome_kind: outcome.outcomeKind,
          updated_at: outcomeUpdatedAt,
          deleted_at: outcome.deletedAt ?? null
        }
      });
    }

    responseProtocols.push({ id: protocol.id, name: protocol.name });
  }

  if (errors.length > 0) {
    return { accepted: false, errors };
  }
  return {
    accepted: true,
    protocols,
    members,
    schedules,
    targetOutcomes,
    responseProtocols
  };
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

export function agentProtocolsWriteFailure(
  result: AgentProtocolsStoreWriteResult
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
      warnings: []
    })
  };
}

// ---------------------------------------------------------------------------
// Pure effect-window computation (deterministic, golden-vectorable, no I/O)
// ---------------------------------------------------------------------------

export type EffectWindowSample = { at: Date; value: number };
export type EffectWindowDose = { tookAt: Date };

export type EffectAggregate = {
  count: number;
  min: number | null;
  max: number | null;
  mean: number | null;
};

export type EffectWindowSegments = {
  duringStart: Date | null;
  duringEnd: Date | null;
  before: EffectAggregate;
  during: EffectAggregate;
  after: EffectAggregate;
};

/**
 * The descriptive Effect computation (PROTOCOLS.md §4): the window's DURING span
 * is the actual logged Dose timeline's bounds (earliest → latest Dose), with the
 * mirrored BEFORE/AFTER spans of equal length immediately surrounding it. Each
 * segment aggregates whatever outcome samples fall in it (count/min/max/mean).
 * Half-open segments `[start, end)`, so a boundary sample lands in exactly one.
 * Pure — no I/O, nothing stored — which is what makes it golden-vectorable.
 */
export function computeEffectWindowSegments({
  doses,
  samples
}: {
  doses: readonly EffectWindowDose[];
  samples: readonly EffectWindowSample[];
}): EffectWindowSegments {
  if (doses.length === 0) {
    return {
      duringStart: null,
      duringEnd: null,
      before: emptyAggregate(),
      during: emptyAggregate(),
      after: emptyAggregate()
    };
  }

  const times = doses
    .map((dose) => dose.tookAt.getTime())
    .sort((left, right) => left - right);
  const duringStart = new Date(times[0]!);
  const duringEnd = new Date(times[times.length - 1]!);
  const duringLengthMs = duringEnd.getTime() - duringStart.getTime();
  const beforeStart = new Date(duringStart.getTime() - duringLengthMs);
  const afterEnd = new Date(duringEnd.getTime() + duringLengthMs);

  const before: number[] = [];
  const during: number[] = [];
  const after: number[] = [];
  for (const sample of samples) {
    const at = sample.at.getTime();
    if (at >= beforeStart.getTime() && at < duringStart.getTime()) {
      before.push(sample.value);
    } else if (at >= duringStart.getTime() && at < duringEnd.getTime()) {
      during.push(sample.value);
    } else if (at >= duringEnd.getTime() && at < afterEnd.getTime()) {
      after.push(sample.value);
    }
  }

  return {
    duringStart,
    duringEnd,
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
      const membersByProtocol = groupBy(memberRows, (row) =>
        String(row.payload.protocol_id ?? "")
      );
      const outcomesByProtocol = groupBy(outcomeRows, (row) =>
        String(row.payload.protocol_id ?? "")
      );
      const memberIdsByProtocol = new Map<string, Set<string>>();
      for (const [protocolId, rows] of membersByProtocol) {
        memberIdsByProtocol.set(protocolId, new Set(rows.map((row) => row.id)));
      }
      const schedulesByMember = groupBy(scheduleRows, (row) =>
        String(row.payload.protocol_compound_id ?? "")
      );

      const start = cursorOffset(filteredProtocols, query.cursor);
      const page = filteredProtocols.slice(start, start + query.limit);
      const protocols = page.map((protocol) => {
        const members = (membersByProtocol.get(protocol.id) ?? [])
          .slice()
          .sort((left, right) => memberPosition(left) - memberPosition(right));
        const memberIds = memberIdsByProtocol.get(protocol.id) ?? new Set();
        const schedules: OpaqueRow[] = [];
        for (const memberId of memberIds) {
          schedules.push(...(schedulesByMember.get(memberId) ?? []));
        }
        const outcomes = outcomesByProtocol.get(protocol.id) ?? [];
        return AgentProtocolSchema.parse({
          ...serializeProtocol(protocol),
          members: members.map((row) => serializeMember(row)),
          schedules: schedules
            .sort((left, right) => left.id.localeCompare(right.id))
            .map((row) => serializeSchedule(row)),
          targetOutcomes: outcomes
            .slice()
            .sort((left, right) => left.id.localeCompare(right.id))
            .map((row) => serializeTargetOutcome(row))
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

      const doseRows = await selectOpaque(db, schema.doses, userId);
      const doses = doseRows.filter((row) => {
        if (row.deletedAt !== null) {
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
        const tookAt = parseOptionalDate(String(row.payload.took_at ?? ""));
        return tookAt !== null && tookAt >= from && tookAt < to;
      });

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

      const segments = computeEffectWindowSegments({
        doses: doses.map((row) => ({
          tookAt: parseOptionalDate(String(row.payload.took_at ?? "")) ?? new Date(0)
        })),
        samples
      });

      const doseMarkers = doses
        .slice()
        .sort((left, right) =>
          String(left.payload.took_at) < String(right.payload.took_at) ? -1 : 1
        )
        .slice(0, AGENT_EFFECT_WINDOW_MAX_DOSES)
        .map((row) => ({
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
            duringStart: segments.duringStart?.toISOString() ?? null,
            duringEnd: segments.duringEnd?.toISOString() ?? null
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

async function writeOpaqueBatch(
  db: ServerDatabase,
  {
    userId,
    batchId,
    requestFingerprint,
    deviceId,
    operationKind,
    groups
  }: {
    userId: string;
    batchId: string;
    requestFingerprint: string;
    deviceId: string;
    operationKind: "doses" | "compounds" | "protocols";
    groups: OpaqueBatchGroup[];
  }
): Promise<AgentProtocolsStoreWriteResult> {
  const serverClock = new Date();
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

async function readOpaqueOwners(
  transaction: Pick<ServerDatabase, "select">,
  table: OpaqueTable,
  ids: string[]
) {
  if (ids.length === 0) {
    return new Map<string, string>();
  }
  const rows = await transaction
    .select({ id: table.id, userId: table.userId })
    .from(table)
    .where(inArray(table.id, ids));
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
    .where(eq(table.id, id))
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
  userId: string
): Promise<OpaqueRow[]> {
  return db
    .select({
      id: table.id,
      payload: table.payload,
      updatedAt: table.updatedAt,
      deletedAt: table.deletedAt
    })
    .from(table)
    .where(eq(table.userId, userId))
    .orderBy(asc(table.id));
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
    startDate: nullableString(row.payload.start_date),
    endDate: nullableString(row.payload.end_date),
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  };
}

function serializeMember(row: OpaqueRow) {
  return {
    id: row.id,
    compoundId: String(row.payload.compound_id ?? ""),
    position: Number(row.payload.position ?? 0),
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  };
}

function serializeSchedule(row: OpaqueRow) {
  return {
    id: row.id,
    protocolCompoundId: String(row.payload.protocol_compound_id ?? ""),
    doseAmountValue:
      row.payload.dose_amount_value === null ||
      row.payload.dose_amount_value === undefined
        ? null
        : Number(row.payload.dose_amount_value),
    doseAmountEntered: nullableString(row.payload.dose_amount_entered),
    doseUnit: nullableString(row.payload.dose_unit),
    frequency: String(row.payload.frequency ?? ""),
    route: nullableString(row.payload.route),
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null
  };
}

function serializeTargetOutcome(row: OpaqueRow) {
  return {
    id: row.id,
    metricId: nullableString(row.payload.metric_id),
    outcomeKind: String(row.payload.outcome_kind ?? "metric"),
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
    const groupKey = key(row);
    const existing = map.get(groupKey);
    if (existing === undefined) {
      map.set(groupKey, [row]);
    } else {
      existing.push(row);
    }
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
