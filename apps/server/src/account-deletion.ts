import { createRoute, z } from "@hono/zod-openapi";
import { and, eq, gt, isNull } from "drizzle-orm";

import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";

export const ACCOUNT_DELETION_LOCAL_ONLY_MESSAGE =
  "Account deletion was requested. This device is now in Local-only Mode and its local data remains on the device.";

export const AccountDeletionResponseSchema = z
  .object({
    deletionRequestedAt: z.string().min(1).openapi({
      description: "ISO-8601 timestamp when account deletion was requested."
    }),
    localReplicaPreserved: z.literal(true).openapi({
      description:
        "Always true: devices keep their local replica and degrade to Local-only Mode."
    })
  })
  .openapi("AccountDeletionResponse");

export const AccountDeletionUnavailableResponseSchema = z
  .object({
    code: z.literal("account_deletion_unavailable"),
    message: z.string().min(1)
  })
  .openapi("AccountDeletionUnavailableResponse");

export const AccountDeletionUnauthorizedResponseSchema = z
  .object({
    code: z.literal("sync_unauthorized"),
    message: z.string().min(1)
  })
  .openapi("AccountDeletionUnauthorizedResponse");

export const accountDeletionRoute = createRoute({
  method: "post",
  path: "/account/deletion",
  operationId: "requestAccountDeletion",
  tags: ["Account"],
  summary: "Request account deletion and drop devices to Local-only Mode.",
  security: [{ bearerAuth: [] }],
  responses: {
    200: {
      description:
        "The account has been marked for deletion; devices keep their local data.",
      content: {
        "application/json": {
          schema: AccountDeletionResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid session bearer token.",
      content: {
        "application/json": {
          schema: AccountDeletionUnauthorizedResponseSchema
        }
      }
    },
    503: {
      description: "Account deletion storage is not configured.",
      content: {
        "application/json": {
          schema: AccountDeletionUnavailableResponseSchema
        }
      }
    }
  }
});

export type AccountDeletionResult = {
  userId: string;
  deletionRequestedAt: string;
};

export type AccountDeletionStore = {
  requestAccountDeletion(token: string): Promise<AccountDeletionResult | null>;
};

export function createDrizzleAccountDeletionStore(
  db: ServerDatabase
): AccountDeletionStore {
  return {
    async requestAccountDeletion(token) {
      const now = new Date();
      const sessionRows = await db
        .select({ userId: schema.session.userId })
        .from(schema.session)
        .innerJoin(schema.user, eq(schema.user.id, schema.session.userId))
        .where(
          and(
            eq(schema.session.token, token),
            gt(schema.session.expiresAt, now),
            isNull(schema.user.deletionRequestedAt)
          )
        )
        .limit(1);
      const session = sessionRows[0];
      if (session === undefined) {
        return null;
      }

      return db.transaction(async (transaction) => {
        const updatedRows = await transaction
          .update(schema.user)
          .set({
            deletionRequestedAt: now,
            updatedAt: now
          })
          .where(
            and(
              eq(schema.user.id, session.userId),
              isNull(schema.user.deletionRequestedAt)
            )
          )
          .returning({
            deletionRequestedAt: schema.user.deletionRequestedAt
          });
        const updated = updatedRows[0];
        if (updated === undefined || updated.deletionRequestedAt === null) {
          return null;
        }

        return {
          userId: session.userId,
          deletionRequestedAt: updated.deletionRequestedAt.toISOString()
        };
      });
    }
  };
}
