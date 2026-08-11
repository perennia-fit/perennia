import { randomUUID } from "node:crypto";
import { createRoute, z } from "@hono/zod-openapi";
import { and, desc, eq } from "drizzle-orm";

import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";

export const INTEGRATION_STATUS_ROUTE_PATH = "/integrations/status";
export const INTEGRATION_STATUS_MANUAL_FIT_IMPORT_FALLBACK = true;

export const IntegrationStatusSourceSchema = z.enum(["garmin"]);
export const IntegrationStatusConditionSchema = z.enum([
  "ok",
  "temporary_failure",
  "rate_limited",
  "reauth_required"
]);
export const IntegrationStatusFailureKindSchema = z.enum([
  "login",
  "network",
  "server",
  "rate_limit",
  "token_expired",
  "unknown"
]);
export const IntegrationStatusTriggerSchema = z.enum([
  "manual",
  "scheduled",
  "backfill",
  "incremental"
]);
export const IntegrationStatusRecoveryActionSchema = z.enum([
  "none",
  "retry",
  "backoff",
  "reauth"
]);

const IntegrationStatusOccurredAtSchema = z
  .string()
  .min(1)
  .refine((value) => !Number.isNaN(new Date(value).getTime()), {
    message: "occurredAt must be a valid timestamp"
  })
  .openapi({
    description:
      "UTC instant when the sidecar observed this health condition. Defaults to server receipt time."
  });

export const IntegrationStatusReportRequestSchema = z
  .object({
    source: IntegrationStatusSourceSchema,
    condition: IntegrationStatusConditionSchema,
    failureKind: IntegrationStatusFailureKindSchema.optional(),
    trigger: IntegrationStatusTriggerSchema.optional(),
    occurredAt: IntegrationStatusOccurredAtSchema.optional(),
    retryAfterSeconds: z.number().int().min(1).optional().openapi({
      description:
        "Backoff seconds from a rate-limit response. Only health metadata; never payload data."
    })
  })
  .strict()
  .superRefine((report, context) => {
    if (
      report.condition === "rate_limited" &&
      report.retryAfterSeconds === undefined
    ) {
      context.addIssue({
        code: "custom",
        path: ["retryAfterSeconds"],
        message: "rate_limited status reports require retryAfterSeconds"
      });
    }
    if (report.condition === "ok" && report.failureKind !== undefined) {
      context.addIssue({
        code: "custom",
        path: ["failureKind"],
        message: "ok status reports cannot include a failureKind"
      });
    }
  })
  .openapi("IntegrationStatusReportRequest");

export const IntegrationStatusRecordSchema = z
  .object({
    id: z.string().min(1),
    source: IntegrationStatusSourceSchema,
    credentialId: z.string().min(1),
    credentialName: z.string().min(1).nullable(),
    condition: IntegrationStatusConditionSchema,
    recoveryAction: IntegrationStatusRecoveryActionSchema,
    lastSuccessfulAt: z.string().min(1).nullable(),
    firstFailureAt: z.string().min(1).nullable(),
    lastFailureAt: z.string().min(1).nullable(),
    failureKind: IntegrationStatusFailureKindSchema.nullable(),
    retryAfterSeconds: z.number().int().min(1).nullable(),
    nextAttemptAt: z.string().min(1).nullable(),
    updatedAt: z.string().min(1),
    manualFitImportFallback: z.literal(true)
  })
  .strict()
  .openapi("IntegrationStatusRecord");

export const IntegrationStatusReportResponseSchema = z
  .object({
    status: IntegrationStatusRecordSchema
  })
  .strict()
  .openapi("IntegrationStatusReportResponse");

export const IntegrationStatusListResponseSchema = z
  .object({
    statuses: z.array(IntegrationStatusRecordSchema)
  })
  .strict()
  .openapi("IntegrationStatusListResponse");

export const IntegrationStatusUnauthorizedResponseSchema = z
  .object({
    code: z.literal("integration_status_unauthorized"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("IntegrationStatusUnauthorizedResponse");

export const IntegrationStatusUnavailableResponseSchema = z
  .object({
    code: z.literal("integration_status_unavailable"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("IntegrationStatusUnavailableResponse");

export const integrationStatusReportRoute = createRoute({
  method: "post",
  path: INTEGRATION_STATUS_ROUTE_PATH,
  operationId: "reportIntegrationStatus",
  tags: ["Integrations"],
  summary: "Report sanitized Integration health.",
  description:
    "Records per-integration health metadata from an acquisition adapter. This surface never accepts imported activities, Monitoring Data, or exception messages.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: IntegrationStatusReportRequestSchema
        }
      }
    }
  },
  responses: {
    200: {
      description:
        "The Integration health record was stored outside the core domain.",
      content: {
        "application/json": {
          schema: IntegrationStatusReportResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid Integration credential.",
      content: {
        "application/json": {
          schema: IntegrationStatusUnauthorizedResponseSchema
        }
      }
    },
    503: {
      description: "Integration status storage or credentials are unavailable.",
      content: {
        "application/json": {
          schema: IntegrationStatusUnavailableResponseSchema
        }
      }
    }
  }
});

export const integrationStatusListRoute = createRoute({
  method: "get",
  path: INTEGRATION_STATUS_ROUTE_PATH,
  operationId: "listIntegrationStatuses",
  tags: ["Integrations"],
  summary: "List Integration health for the signed-in account.",
  security: [{ bearerAuth: [] }],
  responses: {
    200: {
      description:
        "Per-integration health records for the same status surface that displays sync health.",
      content: {
        "application/json": {
          schema: IntegrationStatusListResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid session bearer token.",
      content: {
        "application/json": {
          schema: IntegrationStatusUnauthorizedResponseSchema
        }
      }
    },
    503: {
      description: "Integration status storage or sync auth is unavailable.",
      content: {
        "application/json": {
          schema: IntegrationStatusUnavailableResponseSchema
        }
      }
    }
  }
});

export type IntegrationStatusReportRequest = z.infer<
  typeof IntegrationStatusReportRequestSchema
>;
export type IntegrationStatusRecord = z.infer<
  typeof IntegrationStatusRecordSchema
>;

export type IntegrationStatusStore = {
  recordIntegrationStatus(input: {
    credentialId: string;
    credentialName: string | null;
    userId: string;
    report: IntegrationStatusReportRequest;
  }): Promise<IntegrationStatusRecord>;
  listIntegrationStatuses(userId: string): Promise<IntegrationStatusRecord[]>;
};

export function createDrizzleIntegrationStatusStore(
  db: ServerDatabase
): IntegrationStatusStore {
  return {
    async recordIntegrationStatus({ credentialId, credentialName, userId, report }) {
      const occurredAt = parseOptionalInstant(report.occurredAt) ?? new Date();
      const existing = (
        await db
          .select()
          .from(schema.integrationStatuses)
          .where(
            and(
              eq(schema.integrationStatuses.userId, userId),
              eq(schema.integrationStatuses.credentialId, credentialId),
              eq(schema.integrationStatuses.source, report.source)
            )
          )
          .limit(1)
      )[0];
      const failure = report.condition === "ok" ? null : report.failureKind ?? "unknown";
      const retryAfterSeconds =
        report.condition === "rate_limited"
          ? report.retryAfterSeconds ?? null
          : report.retryAfterSeconds ?? null;
      const nextAttemptAt =
        retryAfterSeconds === null
          ? null
          : new Date(occurredAt.getTime() + retryAfterSeconds * 1000);
      const values = {
        credentialName,
        condition: report.condition,
        recoveryAction: recoveryActionFor(report.condition),
        lastSuccessfulAt:
          report.condition === "ok"
            ? occurredAt
            : existing?.lastSuccessfulAt ?? null,
        firstFailureAt:
          report.condition === "ok"
            ? null
            : existing?.firstFailureAt ?? occurredAt,
        lastFailureAt: report.condition === "ok" ? null : occurredAt,
        failureKind: failure,
        trigger: report.trigger ?? null,
        retryAfterSeconds,
        nextAttemptAt,
        updatedAt: occurredAt
      };

      const row =
        existing === undefined
          ? (
              await db
                .insert(schema.integrationStatuses)
                .values({
                  id: randomUUID(),
                  userId,
                  credentialId,
                  source: report.source,
                  ...values
                })
                .returning()
            )[0]
          : (
              await db
                .update(schema.integrationStatuses)
                .set(values)
                .where(eq(schema.integrationStatuses.id, existing.id))
                .returning()
            )[0];

      if (row === undefined) {
        throw new Error("Integration status was not stored.");
      }

      return mapIntegrationStatusRecord(row);
    },
    async listIntegrationStatuses(userId) {
      const rows = await db
        .select()
        .from(schema.integrationStatuses)
        .where(eq(schema.integrationStatuses.userId, userId))
        .orderBy(desc(schema.integrationStatuses.updatedAt));

      return rows.map(mapIntegrationStatusRecord);
    }
  };
}

function mapIntegrationStatusRecord(
  row: typeof schema.integrationStatuses.$inferSelect
): IntegrationStatusRecord {
  return IntegrationStatusRecordSchema.parse({
    id: row.id,
    source: row.source,
    credentialId: row.credentialId,
    credentialName: row.credentialName,
    condition: row.condition,
    recoveryAction: row.recoveryAction,
    lastSuccessfulAt: row.lastSuccessfulAt?.toISOString() ?? null,
    firstFailureAt: row.firstFailureAt?.toISOString() ?? null,
    lastFailureAt: row.lastFailureAt?.toISOString() ?? null,
    failureKind: row.failureKind,
    retryAfterSeconds: row.retryAfterSeconds,
    nextAttemptAt: row.nextAttemptAt?.toISOString() ?? null,
    updatedAt: row.updatedAt.toISOString(),
    manualFitImportFallback: INTEGRATION_STATUS_MANUAL_FIT_IMPORT_FALLBACK
  });
}

function recoveryActionFor(
  condition: z.infer<typeof IntegrationStatusConditionSchema>
) {
  switch (condition) {
    case "ok":
      return "none";
    case "temporary_failure":
      return "retry";
    case "rate_limited":
      return "backoff";
    case "reauth_required":
      return "reauth";
  }
}

function parseOptionalInstant(value: string | undefined) {
  if (value === undefined) {
    return null;
  }
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw new Error("Invalid integration status occurredAt timestamp.");
  }
  return parsed;
}
