import { createRoute, z } from "@hono/zod-openapi";
import { and, asc, desc, eq } from "drizzle-orm";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import {
  AgentSettingsValidationIssueSchema,
  SETTINGS_VALIDATION_LIMITS,
  validateAgentSettings,
  type AgentSettingsValidationIssue
} from "./agent-validation.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";
import {
  USER_SETTINGS_SYNC_ENTITY,
  pushUserSettingsInTransaction,
  type SyncPushChange
} from "./sync.js";

export const USER_SETTINGS_AGENT_ENTITY = USER_SETTINGS_SYNC_ENTITY;

/**
 * Deterministic per-user id for the account-level Settings singleton
 * when the agent creates the row before any device has. The device mints its
 * own UUIDv7 for the row on first write; when both a device row and an
 * agent-created row would otherwise race, LWW on the whole row collapses them
 * and the device adopts the winning id on its next write. `id` is the global
 * PK, so it must be unique per user — hence userId in the string.
 */
export function agentUserSettingsRowId(userId: string): string {
  return `user-settings:${userId}`;
}

const ISO8601StringSchema = z.string().min(1).openapi({
  description: "ISO-8601 timestamp."
});

/**
 * The account-level Settings the agent can read and write.
 * Device-level settings (screen-on, crash reporting, auto-backup) are never in
 * this surface — they have no server row to point at.
 */
export const AgentSettingsFieldsSchema = z
  .object({
    themePreference: z.enum(SETTINGS_VALIDATION_LIMITS.themePreferences),
    unitSystem: z.enum(SETTINGS_VALIDATION_LIMITS.unitSystems),
    weekStartDay: z.enum(SETTINGS_VALIDATION_LIMITS.weekStartDays),
    defaultWeightIncrement: z.number(),
    homeScreenDisplay: z.enum(SETTINGS_VALIDATION_LIMITS.homeScreenDisplays),
    prTrackingEnabled: z.boolean(),
    markSetsCompleteByDefault: z.boolean(),
    autoSelectNextSet: z.boolean()
  })
  .openapi("AgentSettingsFields");

export const AgentSettingsReadResponseSchema = z
  .object({
    settings: AgentSettingsFieldsSchema.openapi({
      description:
        "The caller's current account-level Settings. Defaults are returned when the caller has never customized a field."
    }),
    updatedAt: ISO8601StringSchema.nullable().openapi({
      description:
        "Row update clock of the synced Settings singleton, or null when the caller has no stored row yet (defaults returned)."
    })
  })
  .openapi("AgentSettingsReadResponse");

export const AgentSettingsBatchWriteFieldsSchema = z
  .object({
    themePreference: z.string().optional(),
    unitSystem: z.string().optional(),
    weekStartDay: z.string().optional(),
    defaultWeightIncrement: z.number().optional(),
    homeScreenDisplay: z.string().optional(),
    prTrackingEnabled: z.boolean().optional(),
    markSetsCompleteByDefault: z.boolean().optional(),
    autoSelectNextSet: z.boolean().optional()
  })
  .openapi("AgentSettingsBatchWriteFields");

export const AgentSettingsBatchWriteRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200).openapi({
      description:
        "Stable key for this agent request. Replays with the same key return the original result without appending another Activity Log batch."
    }),
    updatedAt: ISO8601StringSchema.optional().openapi({
      description:
        "Client-observed row update clock. Defaults to the server receive time when omitted."
    }),
    fields: AgentSettingsBatchWriteFieldsSchema.openapi({
      description:
        "Partial account-level Settings to change. Only supplied keys are updated; omitted keys keep their current value. At least one field is required."
    })
  })
  .openapi("AgentSettingsBatchWriteRequest");

export const AgentSettingsBatchWriteIssueSchema =
  AgentSettingsValidationIssueSchema.openapi("AgentSettingsBatchWriteIssue");

export const AgentSettingsBatchWriteResponseSchema = z
  .object({
    accepted: z.literal(true),
    duplicate: z.boolean().openapi({
      description:
        "True when the idempotency key had already been applied and no new row or Activity Log entry was written."
    }),
    idempotencyKey: z.string().min(1),
    batchId: z.string().min(1).openapi({
      description: "Activity Log batch id. Equal to the idempotency key."
    }),
    serverClock: z.string().min(1),
    settings: AgentSettingsFieldsSchema.openapi({
      description: "The full account-level Settings after the write applied."
    }),
    updatedAt: ISO8601StringSchema.openapi({
      description: "Row update clock of the Settings singleton after the write."
    })
  })
  .openapi("AgentSettingsBatchWriteResponse");

export const AgentSettingsBatchWriteErrorResponseSchema = z
  .object({
    code: z.literal("agent_settings_batch_write_failed"),
    message: z.string().min(1),
    errors: z.array(AgentSettingsBatchWriteIssueSchema)
  })
  .openapi("AgentSettingsBatchWriteErrorResponse");

export const AgentSettingsUnavailableResponseSchema = z
  .object({
    code: z.literal("agent_settings_unavailable"),
    message: z.string().min(1)
  })
  .openapi("AgentSettingsUnavailableResponse");

export const agentSettingsReadRoute = createRoute({
  method: "get",
  path: "/agent/settings",
  operationId: "readAgentSettings",
  tags: ["Agent Reads"],
  summary: "Read the caller's account-level Settings.",
  description:
    "Returns the caller's account-level Settings: theme, unit system, week start, default weight increment, home-screen display, and the logging-workflow toggles. Device-level settings (screen-on, crash reporting, auto-backup) are deliberately absent — they have no synced row and no agent surface. Defaults are returned for any field the caller has never customized.",
  security: [{ bearerAuth: [] }],
  responses: {
    200: {
      description: "The caller's current account-level Settings.",
      content: {
        "application/json": {
          schema: AgentSettingsReadResponseSchema
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
      description: "Agent API key or Settings storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentSettingsUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export const agentSettingsBatchWriteRoute = createRoute({
  method: "post",
  path: "/agent/settings/batch-write",
  operationId: "batchWriteAgentSettings",
  tags: ["Agent Writes"],
  summary: "Change account-level Settings as one Activity Log batch.",
  description:
    "Authenticated agent write path for account-level Settings: change any subset of theme, unit system, week start, default weight increment, home-screen display, or the logging-workflow toggles, validated with the same shared two-tier Settings validator the UI uses (enum membership, increment bounds), applied to the synced Settings singleton as one Activity Log batch with a best-effort sync nudge. Device-level settings cannot be written here — they have no server row.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: AgentSettingsBatchWriteRequestSchema
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
          schema: AgentSettingsBatchWriteResponseSchema
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
        "One or more fields failed hard validation; no row was written.",
      content: {
        "application/json": {
          schema: AgentSettingsBatchWriteErrorResponseSchema
        }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key or Settings storage is not configured.",
      content: {
        "application/json": {
          schema: z.union([
            AgentApiKeyUnavailableResponseSchema,
            AgentSettingsUnavailableResponseSchema
          ])
        }
      }
    }
  }
});

export type AgentSettingsFields = z.infer<typeof AgentSettingsFieldsSchema>;
export type AgentSettingsReadResponse = z.infer<
  typeof AgentSettingsReadResponseSchema
>;
export type AgentSettingsBatchWriteRequest = z.infer<
  typeof AgentSettingsBatchWriteRequestSchema
>;
export type AgentSettingsBatchWriteResponse = z.infer<
  typeof AgentSettingsBatchWriteResponseSchema
>;

/** Canonical defaults, identical to the Dart `AppSettings.defaults` account half. */
export const AGENT_SETTINGS_DEFAULTS: AgentSettingsFields = {
  themePreference: "system",
  unitSystem: "metric",
  weekStartDay: "monday",
  defaultWeightIncrement: 2.5,
  homeScreenDisplay: "comfortable",
  prTrackingEnabled: true,
  markSetsCompleteByDefault: false,
  autoSelectNextSet: true
};

export type AgentSettingsReadStore = {
  /** Current account-level Settings + row clock, or defaults when absent. */
  readSettings(input: {
    userId: string;
  }): Promise<{ settings: AgentSettingsFields; updatedAt: string | null }>;
};

export type AgentSettingsBatchWriteStore = AgentSettingsReadStore & {
  writeSettingsBatch(input: {
    userId: string;
    batchId: string;
    correlationId?: string;
    deviceId: string;
    request: AgentSettingsBatchWriteRequest;
  }): Promise<
    | {
        accepted: true;
        duplicate: boolean;
        serverClock: string;
        settings: AgentSettingsFields;
        updatedAt: string;
      }
    | {
        accepted: false;
        errors: AgentSettingsValidationIssue[];
      }
  >;
};

type MutationDatabase = Pick<ServerDatabase, "select" | "insert" | "update">;

export function createDrizzleAgentSettingsStore(
  db: ServerDatabase
): AgentSettingsBatchWriteStore {
  return {
    async readSettings({ userId }) {
      const current = await readCurrentSettingsRow(db, userId);
      if (current === null) {
        return { settings: { ...AGENT_SETTINGS_DEFAULTS }, updatedAt: null };
      }
      return {
        settings: mergeSettings(AGENT_SETTINGS_DEFAULTS, current.payload),
        updatedAt: current.updatedAt.toISOString()
      };
    },
    async writeSettingsBatch({ userId, batchId, deviceId, request }) {
      const serverClock = new Date();

      // Validate the supplied fields through the SAME shared two-tier validator
      // the UI uses — no agent-only parallel check.
      const validation = validateAgentSettings({ fields: request.fields });
      if (validation.errors.length > 0) {
        return { accepted: false, errors: validation.errors };
      }

      return db.transaction(async (transaction) => {
        const existingBatchRows = await transaction
          .select({ id: schema.activityLog.id })
          .from(schema.activityLog)
          .where(
            and(
              eq(schema.activityLog.userId, userId),
              eq(schema.activityLog.actor, "agent"),
              eq(schema.activityLog.batchId, batchId)
            )
          )
          .orderBy(asc(schema.activityLog.createdAt), asc(schema.activityLog.id))
          .limit(1);

        if (existingBatchRows.length > 0) {
          const current = await readCurrentSettingsRow(transaction, userId);
          const settings =
            current === null
              ? { ...AGENT_SETTINGS_DEFAULTS }
              : mergeSettings(AGENT_SETTINGS_DEFAULTS, current.payload);
          return {
            accepted: true,
            duplicate: true,
            serverClock: serverClock.toISOString(),
            settings,
            updatedAt:
              current?.updatedAt.toISOString() ?? serverClock.toISOString()
          };
        }

        const existing = await readCurrentSettingsRow(transaction, userId);
        const rowId = existing?.id ?? agentUserSettingsRowId(userId);
        const beforeImage = existing?.payload ?? null;
        const beforeSettings =
          existing === null
            ? { ...AGENT_SETTINGS_DEFAULTS }
            : mergeSettings(AGENT_SETTINGS_DEFAULTS, existing.payload);
        const nextSettings = applyFields(beforeSettings, request.fields);

        const updatedAt = request.updatedAt ?? serverClock.toISOString();
        const payload = buildSettingsPayload({
          id: rowId,
          settings: nextSettings,
          updatedAt
        });

        const change: SyncPushChange = {
          id: rowId,
          payload,
          updatedAt,
          deletedAt: null,
          activityLogId: `agent:${batchId}:${rowId}`,
          actor: "agent",
          batchId,
          beforeImage,
          afterImage: payload,
          occurredAt: updatedAt
        };

        const result = await pushUserSettingsInTransaction(transaction, {
          userId,
          deviceId,
          changes: [change],
          serverClock
        });

        const applied = result.applied.find((row) => row.id === rowId);
        return {
          accepted: true,
          duplicate: false,
          serverClock: result.serverClock,
          settings: nextSettings,
          updatedAt: applied?.updatedAt ?? updatedAt
        };
      });
    }
  };
}

async function readCurrentSettingsRow(
  db: Pick<ServerDatabase, "select">,
  userId: string
): Promise<{
  id: string;
  payload: Record<string, unknown>;
  updatedAt: Date;
} | null> {
  const rows = await db
    .select({
      id: schema.userSettings.id,
      payload: schema.userSettings.payload,
      updatedAt: schema.userSettings.updatedAt,
      deletedAt: schema.userSettings.deletedAt
    })
    .from(schema.userSettings)
    .where(eq(schema.userSettings.userId, userId))
    .orderBy(desc(schema.userSettings.updatedAt), desc(schema.userSettings.id))
    .limit(1);
  const row = rows[0];
  if (row === undefined || row.deletedAt !== null) {
    return null;
  }
  return { id: row.id, payload: row.payload, updatedAt: row.updatedAt };
}

/** Overlays the stored payload onto the canonical defaults, ignoring unknowns. */
function mergeSettings(
  defaults: AgentSettingsFields,
  payload: Record<string, unknown>
): AgentSettingsFields {
  return AgentSettingsFieldsSchema.parse({
    themePreference: enumOrDefault(
      payload.theme_preference,
      SETTINGS_VALIDATION_LIMITS.themePreferences,
      defaults.themePreference
    ),
    unitSystem: enumOrDefault(
      payload.unit_system,
      SETTINGS_VALIDATION_LIMITS.unitSystems,
      defaults.unitSystem
    ),
    weekStartDay: enumOrDefault(
      payload.week_start_day,
      SETTINGS_VALIDATION_LIMITS.weekStartDays,
      defaults.weekStartDay
    ),
    defaultWeightIncrement: numberOrDefault(
      payload.default_weight_increment,
      defaults.defaultWeightIncrement
    ),
    homeScreenDisplay: enumOrDefault(
      payload.home_screen_display,
      SETTINGS_VALIDATION_LIMITS.homeScreenDisplays,
      defaults.homeScreenDisplay
    ),
    prTrackingEnabled: boolOrDefault(
      payload.pr_tracking_enabled,
      defaults.prTrackingEnabled
    ),
    markSetsCompleteByDefault: boolOrDefault(
      payload.mark_sets_complete_by_default,
      defaults.markSetsCompleteByDefault
    ),
    autoSelectNextSet: boolOrDefault(
      payload.auto_select_next_set,
      defaults.autoSelectNextSet
    )
  });
}

/** Applies a partial write's supplied keys onto the current settings. */
function applyFields(
  current: AgentSettingsFields,
  fields: AgentSettingsBatchWriteRequest["fields"]
): AgentSettingsFields {
  return AgentSettingsFieldsSchema.parse({
    themePreference: fields.themePreference ?? current.themePreference,
    unitSystem: fields.unitSystem ?? current.unitSystem,
    weekStartDay: fields.weekStartDay ?? current.weekStartDay,
    defaultWeightIncrement:
      fields.defaultWeightIncrement ?? current.defaultWeightIncrement,
    homeScreenDisplay: fields.homeScreenDisplay ?? current.homeScreenDisplay,
    prTrackingEnabled: fields.prTrackingEnabled ?? current.prTrackingEnabled,
    markSetsCompleteByDefault:
      fields.markSetsCompleteByDefault ?? current.markSetsCompleteByDefault,
    autoSelectNextSet: fields.autoSelectNextSet ?? current.autoSelectNextSet
  });
}

/** The canonical snake_case payload the device replica also produces. */
export function buildSettingsPayload({
  id,
  settings,
  updatedAt
}: {
  id: string;
  settings: AgentSettingsFields;
  updatedAt: string;
}): Record<string, unknown> {
  return {
    id,
    theme_preference: settings.themePreference,
    unit_system: settings.unitSystem,
    week_start_day: settings.weekStartDay,
    default_weight_increment: settings.defaultWeightIncrement,
    home_screen_display: settings.homeScreenDisplay,
    pr_tracking_enabled: settings.prTrackingEnabled,
    mark_sets_complete_by_default: settings.markSetsCompleteByDefault,
    auto_select_next_set: settings.autoSelectNextSet,
    updated_at: updatedAt,
    deleted_at: null
  };
}

function enumOrDefault<T extends string>(
  value: unknown,
  allowed: readonly T[],
  fallback: T
): T {
  return typeof value === "string" && (allowed as readonly string[]).includes(value)
    ? (value as T)
    : fallback;
}

function numberOrDefault(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? value
    : fallback;
}

function boolOrDefault(value: unknown, fallback: boolean): boolean {
  return typeof value === "boolean" ? value : fallback;
}
