import { createHash } from "node:crypto";
import { and, eq } from "drizzle-orm";

import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";

type ReceiptDatabase = Pick<ServerDatabase, "select" | "insert">;

export type AgentBatchReceiptClaim =
  | {
      status: "inserted" | "duplicate" | "conflict";
      serverClock: string;
    }
  | {
      status: "unavailable";
      serverClock: string;
    };

export function agentBatchRequestFingerprint(value: unknown) {
  return createHash("sha256").update(canonicalJson(value)).digest("hex");
}

export function scopedAgentBatchReceiptId({
  scope,
  userId,
  batchId
}: {
  scope: string;
  userId: string;
  batchId: string;
}) {
  return `agent-batch:${encodeURIComponent(scope)}:${encodeURIComponent(userId)}:${encodeURIComponent(batchId)}`;
}

export async function claimAgentBatchReceipt(
  transaction: ReceiptDatabase,
  {
    markerId,
    userId,
    batchId,
    entityTable,
    kind,
    requestFingerprint,
    occurredAt,
    metadata = {}
  }: {
    markerId: string;
    userId: string;
    batchId: string;
    entityTable: string;
    kind: string;
    requestFingerprint: string;
    occurredAt: Date;
    metadata?: Record<string, unknown>;
  }
): Promise<AgentBatchReceiptClaim> {
  const inserted = await transaction
    .insert(schema.activityLog)
    .values({
      id: markerId,
      userId,
      actor: "agent",
      batchId,
      entityTable,
      entityId: batchId,
      beforeImage: null,
      afterImage: {
        idempotencyKey: batchId,
        kind,
        requestFingerprint,
        ...metadata
      },
      occurredAt
    })
    .onConflictDoNothing({ target: schema.activityLog.id })
    .returning({ id: schema.activityLog.id });

  if (inserted.length > 0) {
    return {
      status: "inserted",
      serverClock: occurredAt.toISOString()
    };
  }

  // Each SELECT gets a fresh READ COMMITTED snapshot. A bounded re-read covers
  // the narrow case where ON CONFLICT observed an in-flight receipt but its
  // committed row was not visible to the first statement snapshot.
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const rows = await transaction
      .select({
        occurredAt: schema.activityLog.occurredAt,
        afterImage: schema.activityLog.afterImage
      })
      .from(schema.activityLog)
      .where(
        and(
          eq(schema.activityLog.id, markerId),
          eq(schema.activityLog.userId, userId),
          eq(schema.activityLog.actor, "agent"),
          eq(schema.activityLog.batchId, batchId),
          eq(schema.activityLog.entityTable, entityTable),
          eq(schema.activityLog.entityId, batchId)
        )
      )
      .limit(1);
    const receipt = rows[0];
    if (receipt === undefined) {
      continue;
    }

    return {
      status:
        receipt.afterImage?.kind === kind &&
        receipt.afterImage.requestFingerprint === requestFingerprint
          ? "duplicate"
          : "conflict",
      serverClock: receipt.occurredAt.toISOString()
    };
  }

  return {
    status: "unavailable",
    serverClock: occurredAt.toISOString()
  };
}

function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJson(item)).join(",")}]`;
  }
  if (value !== null && typeof value === "object") {
    return `{${Object.entries(value)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, item]) => `${JSON.stringify(key)}:${canonicalJson(item)}`)
      .join(",")}}`;
  }

  return JSON.stringify(value) ?? "null";
}
