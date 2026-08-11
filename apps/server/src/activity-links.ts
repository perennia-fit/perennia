import { createHash } from "node:crypto";
import { createRoute, z } from "@hono/zod-openapi";
import { and, eq, isNull } from "drizzle-orm";

import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";

export const ACTIVITY_LINK_USER_ACTION_ACTOR = "app";
export const ACTIVITY_LINK_KIND_MATERIALIZED_SOURCE = "materialized_source";
export const ACTIVITY_LINK_KIND_TIME_OVERLAP = "time_overlap";
export const ACTIVITY_LINK_KIND_SUGGESTED_TIME_OVERLAP =
  "suggested_time_overlap";

export const ActivityLinkKindSchema = z.enum([
  ACTIVITY_LINK_KIND_MATERIALIZED_SOURCE,
  ACTIVITY_LINK_KIND_TIME_OVERLAP,
  ACTIVITY_LINK_KIND_SUGGESTED_TIME_OVERLAP
]);

export const ActivityLinkSchema = z
  .object({
    id: z.string().min(1),
    workoutId: z.string().min(1),
    externalActivityId: z.string().min(1),
    linkKind: ActivityLinkKindSchema,
    status: z.enum(["created", "existing", "refreshed", "tombstoned"])
  })
  .strict()
  .openapi("ActivityLink");

export const ActivityLinkCreateRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200),
    externalActivityId: z.string().min(1),
    workoutId: z.string().min(1)
  })
  .strict()
  .openapi("ActivityLinkCreateRequest");

export const ActivityLinkDeleteRequestSchema = z
  .object({
    idempotencyKey: z.string().min(1).max(200)
  })
  .strict()
  .openapi("ActivityLinkDeleteRequest");

export const ActivityLinkMutationResponseSchema = z
  .object({
    accepted: z.literal(true),
    duplicate: z.boolean(),
    batchId: z.string().min(1),
    serverClock: z.string().min(1),
    activityLink: ActivityLinkSchema
  })
  .strict()
  .openapi("ActivityLinkMutationResponse");

export const ActivityLinkUnauthorizedResponseSchema = z
  .object({
    code: z.literal("activity_link_unauthorized"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("ActivityLinkUnauthorizedResponse");

export const ActivityLinkUnavailableResponseSchema = z
  .object({
    code: z.literal("activity_link_unavailable"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("ActivityLinkUnavailableResponse");

export const ActivityLinkNotFoundResponseSchema = z
  .object({
    code: z.literal("activity_link_not_found"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("ActivityLinkNotFoundResponse");

export const ActivityLinkConflictResponseSchema = z
  .object({
    code: z.literal("activity_link_conflict"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("ActivityLinkConflictResponse");

export const activityLinkCreateRoute = createRoute({
  method: "post",
  path: "/integrations/activity-links",
  operationId: "createActivityLink",
  tags: ["Integrations"],
  summary: "Accept an Activity Link suggestion.",
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: ActivityLinkCreateRequestSchema
        }
      }
    }
  },
  responses: {
    200: {
      description: "The Activity Link exists for the requested Workout.",
      content: {
        "application/json": {
          schema: ActivityLinkMutationResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid session bearer token.",
      content: {
        "application/json": {
          schema: ActivityLinkUnauthorizedResponseSchema
        }
      }
    },
    404: {
      description: "The External Activity or Workout could not be linked.",
      content: {
        "application/json": {
          schema: ActivityLinkNotFoundResponseSchema
        }
      }
    },
    409: {
      description: "The External Activity is already linked elsewhere.",
      content: {
        "application/json": {
          schema: ActivityLinkConflictResponseSchema
        }
      }
    },
    503: {
      description: "Activity Link storage is not configured.",
      content: {
        "application/json": {
          schema: ActivityLinkUnavailableResponseSchema
        }
      }
    }
  }
});

export const activityLinkDeleteRoute = createRoute({
  method: "delete",
  path: "/integrations/activity-links/{linkId}",
  operationId: "deleteActivityLink",
  tags: ["Integrations"],
  summary: "Unlink a Workout from an External Activity.",
  request: {
    params: z
      .object({
        linkId: z.string().min(1)
      })
      .openapi("ActivityLinkDeleteParams"),
    body: {
      required: true,
      content: {
        "application/json": {
          schema: ActivityLinkDeleteRequestSchema
        }
      }
    }
  },
  responses: {
    200: {
      description: "The Activity Link was tombstoned without deleting either side.",
      content: {
        "application/json": {
          schema: ActivityLinkMutationResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid session bearer token.",
      content: {
        "application/json": {
          schema: ActivityLinkUnauthorizedResponseSchema
        }
      }
    },
    404: {
      description: "No Activity Link exists for this account with that id.",
      content: {
        "application/json": {
          schema: ActivityLinkNotFoundResponseSchema
        }
      }
    },
    409: {
      description: "The Activity Link could not be unlinked.",
      content: {
        "application/json": {
          schema: ActivityLinkConflictResponseSchema
        }
      }
    },
    503: {
      description: "Activity Link storage is not configured.",
      content: {
        "application/json": {
          schema: ActivityLinkUnavailableResponseSchema
        }
      }
    }
  }
});

export type ActivityLink = z.infer<typeof ActivityLinkSchema>;
export type ActivityLinkCreateRequest = z.infer<
  typeof ActivityLinkCreateRequestSchema
>;
export type ActivityLinkDeleteRequest = z.infer<
  typeof ActivityLinkDeleteRequestSchema
>;
export type ActivityLinkMutationResponse = z.infer<
  typeof ActivityLinkMutationResponseSchema
>;

export type ActivityLinkMutationResult =
  | {
      status: "linked";
      response: ActivityLinkMutationResponse;
    }
  | {
      status: "not_found";
    }
  | {
      status: "conflict";
    };

export type ActivityLinkMutationStore = {
  createActivityLink(input: {
    userId: string;
    batchId: string;
    deviceId: string;
    externalActivityId: string;
    workoutId: string;
  }): Promise<ActivityLinkMutationResult>;
  unlinkActivityLink(input: {
    userId: string;
    batchId: string;
    deviceId: string;
    linkId: string;
  }): Promise<ActivityLinkMutationResult>;
};

export function createDrizzleActivityLinkMutationStore(
  db: ServerDatabase
): ActivityLinkMutationStore {
  return {
    async createActivityLink(input) {
      const serverClock = new Date();
      return db.transaction(async (transaction) => {
        const duplicate = await readDuplicateLinkMutation({
          transaction,
          userId: input.userId,
          batchId: input.batchId
        });
        if (duplicate !== null) {
          return duplicate;
        }

        const externalActivity = await readLiveExternalActivity({
          transaction,
          userId: input.userId,
          externalActivityId: input.externalActivityId
        });
        if (externalActivity === null) {
          return { status: "not_found" as const };
        }
        const workoutExists = await hasLiveWorkout({
          transaction,
          userId: input.userId,
          workoutId: input.workoutId
        });
        if (!workoutExists) {
          return { status: "not_found" as const };
        }

        const existingRows = await transaction
          .select()
          .from(schema.activityLinks)
          .where(
            and(
              eq(schema.activityLinks.userId, input.userId),
              eq(schema.activityLinks.externalActivityId, input.externalActivityId)
            )
          )
          .limit(1);
        const existing = existingRows[0];
        if (existing !== undefined && existing.deletedAt === null) {
          if (existing.workoutId !== input.workoutId) {
            return { status: "conflict" as const };
          }

          return {
            status: "linked" as const,
            response: mutationResponse({
              activityLink: activityLinkFromRow(existing, "existing"),
              batchId: input.batchId,
              duplicate: false,
              serverClock
            })
          };
        }

        const linkId =
          existing?.id ??
          stableScopedId(
            "activity-link",
            input.userId,
            input.externalActivityId,
            input.workoutId
          );
        const rowValues = {
          id: linkId,
          userId: input.userId,
          deviceId: input.deviceId,
          workoutId: input.workoutId,
          externalActivityId: input.externalActivityId,
          linkKind: ACTIVITY_LINK_KIND_TIME_OVERLAP,
          updatedAt: serverClock,
          deletedAt: null,
          receivedAt: serverClock
        };

        if (existing === undefined) {
          await transaction.insert(schema.activityLinks).values(rowValues);
        } else {
          await transaction
            .update(schema.activityLinks)
            .set(rowValues)
            .where(eq(schema.activityLinks.id, existing.id));
        }

        await insertActivityLinkLog(transaction, {
          userId: input.userId,
          batchId: input.batchId,
          linkId,
          beforeImage: existing === undefined ? null : activityLinkRowImage(existing),
          afterImage: activityLinkRowImage(rowValues),
          occurredAt: serverClock
        });

        return {
          status: "linked" as const,
          response: mutationResponse({
            activityLink: activityLinkFromRow(rowValues, "created"),
            batchId: input.batchId,
            duplicate: false,
            serverClock
          })
        };
      });
    },
    async unlinkActivityLink(input) {
      const serverClock = new Date();
      return db.transaction(async (transaction) => {
        const duplicate = await readDuplicateLinkMutation({
          transaction,
          userId: input.userId,
          batchId: input.batchId
        });
        if (duplicate !== null) {
          return duplicate;
        }

        const existingRows = await transaction
          .select()
          .from(schema.activityLinks)
          .where(
            and(
              eq(schema.activityLinks.userId, input.userId),
              eq(schema.activityLinks.id, input.linkId)
            )
          )
          .limit(1);
        const existing = existingRows[0];
        if (existing === undefined) {
          return { status: "not_found" as const };
        }
        if (existing.deletedAt !== null) {
          return {
            status: "linked" as const,
            response: mutationResponse({
              activityLink: activityLinkFromRow(existing, "tombstoned"),
              batchId: input.batchId,
              duplicate: false,
              serverClock
            })
          };
        }

        const rowValues = {
          ...existing,
          deviceId: input.deviceId,
          updatedAt: serverClock,
          deletedAt: serverClock,
          receivedAt: serverClock
        };
        await transaction
          .update(schema.activityLinks)
          .set(rowValues)
          .where(eq(schema.activityLinks.id, existing.id));
        await insertActivityLinkLog(transaction, {
          userId: input.userId,
          batchId: input.batchId,
          linkId: existing.id,
          beforeImage: activityLinkRowImage(existing),
          afterImage: activityLinkRowImage(rowValues),
          occurredAt: serverClock
        });

        return {
          status: "linked" as const,
          response: mutationResponse({
            activityLink: activityLinkFromRow(rowValues, "tombstoned"),
            batchId: input.batchId,
            duplicate: false,
            serverClock
          })
        };
      });
    }
  };
}

type ActivityLinkMutationDatabase = Pick<
  ServerDatabase,
  "insert" | "select" | "update"
>;

async function readDuplicateLinkMutation({
  transaction,
  userId,
  batchId
}: {
  transaction: ActivityLinkMutationDatabase;
  userId: string;
  batchId: string;
}): Promise<ActivityLinkMutationResult | null> {
  const duplicateRows = await transaction
    .select({
      entityId: schema.activityLog.entityId
    })
    .from(schema.activityLog)
    .where(
      and(
        eq(schema.activityLog.userId, userId),
        eq(schema.activityLog.actor, ACTIVITY_LINK_USER_ACTION_ACTOR),
        eq(schema.activityLog.batchId, batchId),
        eq(schema.activityLog.entityTable, "activity_links")
      )
    )
    .limit(1);
  const duplicate = duplicateRows[0];
  if (duplicate === undefined) {
    return null;
  }

  const linkRows = await transaction
    .select()
    .from(schema.activityLinks)
    .where(
      and(
        eq(schema.activityLinks.userId, userId),
        eq(schema.activityLinks.id, duplicate.entityId)
      )
    )
    .limit(1);
  const link = linkRows[0];
  if (link === undefined) {
    return { status: "not_found" };
  }

  return {
    status: "linked",
    response: mutationResponse({
      activityLink: activityLinkFromRow(
        link,
        link.deletedAt === null ? "existing" : "tombstoned"
      ),
      batchId,
      duplicate: true,
      serverClock: new Date()
    })
  };
}

async function readLiveExternalActivity({
  transaction,
  userId,
  externalActivityId
}: {
  transaction: ActivityLinkMutationDatabase;
  userId: string;
  externalActivityId: string;
}) {
  const rows = await transaction
    .select({ id: schema.externalActivities.id })
    .from(schema.externalActivities)
    .where(
      and(
        eq(schema.externalActivities.userId, userId),
        eq(schema.externalActivities.id, externalActivityId),
        isNull(schema.externalActivities.deletedAt)
      )
    )
    .limit(1);

  return rows[0] ?? null;
}

async function hasLiveWorkout({
  transaction,
  userId,
  workoutId
}: {
  transaction: ActivityLinkMutationDatabase;
  userId: string;
  workoutId: string;
}) {
  const rows = await transaction
    .select({ payload: schema.loggedSets.payload })
    .from(schema.loggedSets)
    .where(and(eq(schema.loggedSets.userId, userId), isNull(schema.loggedSets.deletedAt)));

  return rows.some((row) => row.payload.workout_id === workoutId);
}

async function insertActivityLinkLog(
  transaction: ActivityLinkMutationDatabase,
  {
    userId,
    batchId,
    linkId,
    beforeImage,
    afterImage,
    occurredAt
  }: {
    userId: string;
    batchId: string;
    linkId: string;
    beforeImage: Record<string, unknown> | null;
    afterImage: Record<string, unknown>;
    occurredAt: Date;
  }
) {
  await transaction
    .insert(schema.activityLog)
    .values({
      id: stableActivityLogId(batchId, linkId),
      userId,
      actor: ACTIVITY_LINK_USER_ACTION_ACTOR,
      batchId,
      entityTable: "activity_links",
      entityId: linkId,
      beforeImage,
      afterImage,
      occurredAt
    })
    .onConflictDoNothing({ target: schema.activityLog.id });
}

function mutationResponse({
  activityLink,
  batchId,
  duplicate,
  serverClock
}: {
  activityLink: ActivityLink;
  batchId: string;
  duplicate: boolean;
  serverClock: Date;
}): ActivityLinkMutationResponse {
  return ActivityLinkMutationResponseSchema.parse({
    accepted: true,
    duplicate,
    batchId,
    serverClock: serverClock.toISOString(),
    activityLink
  });
}

function activityLinkFromRow(
  row: ActivityLinkImageRow,
  status: ActivityLink["status"]
): ActivityLink {
  return ActivityLinkSchema.parse({
    id: row.id,
    workoutId: row.workoutId,
    externalActivityId: row.externalActivityId,
    linkKind: row.linkKind,
    status
  });
}

function activityLinkRowImage(
  row: ActivityLinkImageRow
) {
  return {
    id: row.id,
    userId: row.userId,
    deviceId: row.deviceId,
    workoutId: row.workoutId,
    externalActivityId: row.externalActivityId,
    linkKind: row.linkKind,
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null,
    receivedAt: row.receivedAt.toISOString()
  };
}

type ActivityLinkImageRow = {
  id: string;
  userId: string;
  deviceId: string;
  workoutId: string;
  externalActivityId: string;
  linkKind: string;
  updatedAt: Date;
  deletedAt: Date | null;
  receivedAt: Date;
};

function stableScopedId(prefix: string, ...parts: string[]) {
  return `${prefix}:${hashParts(parts)}`;
}

function stableActivityLogId(batchId: string, linkId: string) {
  return `${ACTIVITY_LINK_USER_ACTION_ACTOR}:${hashParts([
    batchId,
    "activity_links",
    linkId
  ])}`;
}

function hashParts(parts: string[]) {
  const hash = createHash("sha256");
  for (const part of parts) {
    hash.update(part);
    hash.update("\0");
  }

  return hash.digest("hex").slice(0, 32);
}
