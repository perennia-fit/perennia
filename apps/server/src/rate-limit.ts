import type { Context, MiddlewareHandler } from "hono";
import { randomUUID } from "node:crypto";
import { z } from "@hono/zod-openapi";
import { and, eq, gte, lt, lte, sql } from "drizzle-orm";

import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";

export const DEFAULT_RATE_LIMIT_LIMIT = 1_000_000;
export const DEFAULT_RATE_LIMIT_WINDOW_MS = 60 * 1000;
export const DEFAULT_RATE_LIMIT_ENFORCE = false;

export const RateLimitExceededResponseSchema = z
  .object({
    code: z.literal("rate_limited").openapi({
      description: "Stable machine-readable rate-limit error code."
    }),
    message: z.string().min(1).openapi({
      description: "Human-readable explanation of the rejected request."
    }),
    limit: z.number().int().min(1).openapi({
      description: "Maximum requests allowed in the current window."
    }),
    retryAfterSeconds: z.number().int().min(1).openapi({
      description: "Whole seconds until the caller should retry."
    })
  })
  .openapi("RateLimitExceededResponse");

export const RateLimitExceededHeadersSchema = z
  .object({
    "x-rate-limit-limit": z.string().openapi({
      description: "Maximum requests allowed in the current window."
    }),
    "x-rate-limit-remaining": z.string().openapi({
      description: "Remaining requests in the current window."
    }),
    "x-rate-limit-reset": z.string().openapi({
      description: "ISO-8601 timestamp when the current window resets."
    }),
    "retry-after": z.string().openapi({
      description: "Whole seconds until the caller should retry."
    })
  })
  .openapi("RateLimitExceededHeaders");

export const RateLimitExceededOpenApiResponse = {
  description: "The authenticated key exceeded its rate limit.",
  headers: RateLimitExceededHeadersSchema,
  content: {
    "application/json": {
      schema: RateLimitExceededResponseSchema
    }
  }
};

export type RateLimitRecordInput = {
  key: string;
  limit: number;
  windowMs: number;
  cost?: number;
  now?: Date;
};

export type RateLimitDecision = {
  allowed: boolean;
  key: string;
  limit: number;
  remaining: number;
  resetAt: string;
  retryAfterMs: number;
  totalHits?: number;
};

export type RateLimitBackend = {
  recordHit(input: RateLimitRecordInput): Promise<RateLimitDecision>;
};

export type RateLimitPolicy = {
  limit: number;
  windowMs: number;
  enforce: boolean;
  keyGenerator: (context: Context) => string;
};

export type RateLimitPolicyInput = Partial<
  Omit<RateLimitPolicy, "keyGenerator">
> & {
  keyGenerator?: (context: Context) => string;
};

export type RateLimitMiddlewareOptions = {
  backend: RateLimitBackend;
  policy?: RateLimitPolicyInput;
  logger?: {
    error?(payload: Record<string, unknown>, message: string): void;
  };
};

export function createDrizzleRateLimitBackend(
  db: ServerDatabase
): RateLimitBackend {
  return {
    async recordHit(input) {
      validateRateLimitInput(input);

      const now = input.now ?? new Date();
      const cost = input.cost ?? 1;
      const cutoff = new Date(now.getTime() - input.windowMs);
      const expiresAt = new Date(now.getTime() + input.windowMs);

      const totalHits = await db.transaction(async (transaction) => {
        await transaction
          .delete(schema.rateLimitWindows)
          .where(lt(schema.rateLimitWindows.expiresAt, now));

        await transaction
          .insert(schema.rateLimitWindows)
          .values({
            id: randomUUID(),
            key: input.key,
            windowStartedAt: now,
            count: cost,
            expiresAt,
            updatedAt: now
          })
          .onConflictDoUpdate({
            target: [
              schema.rateLimitWindows.key,
              schema.rateLimitWindows.windowStartedAt
            ],
            set: {
              count: sql`${schema.rateLimitWindows.count} + ${cost}`,
              expiresAt,
              updatedAt: now
            }
          });

        const rows = await transaction
          .select({
            totalHits:
              sql<number>`coalesce(sum(${schema.rateLimitWindows.count}), 0)::int`
          })
          .from(schema.rateLimitWindows)
          .where(
            and(
              eq(schema.rateLimitWindows.key, input.key),
              gte(schema.rateLimitWindows.windowStartedAt, cutoff),
              lte(schema.rateLimitWindows.windowStartedAt, now)
            )
          );

        return Number(rows[0]?.totalHits ?? 0);
      });

      const allowed = totalHits <= input.limit;
      return {
        allowed,
        key: input.key,
        limit: input.limit,
        remaining: Math.max(0, input.limit - totalHits),
        resetAt: expiresAt.toISOString(),
        retryAfterMs: allowed ? 0 : input.windowMs,
        totalHits
      };
    }
  };
}

export function createRateLimitMiddleware({
  backend,
  policy: policyInput,
  logger
}: RateLimitMiddlewareOptions): MiddlewareHandler {
  const policy = resolveRateLimitPolicy(policyInput);

  return async (context, next) => {
    let decision: RateLimitDecision;

    try {
      decision = await backend.recordHit({
        key: policy.keyGenerator(context),
        limit: policy.limit,
        windowMs: policy.windowMs
      });
    } catch (error) {
      logger?.error?.({ error }, "rate-limit backend failed open");
      await next();
      return;
    }

    if (!decision.allowed && policy.enforce) {
      return rateLimitExceededResponse(context, decision);
    }

    applyRateLimitHeaders(context, decision);
    await next();
  };
}

export function applyRateLimitHeaders(
  context: Context,
  decision: RateLimitDecision
) {
  context.header("x-rate-limit-limit", decision.limit.toString());
  context.header("x-rate-limit-remaining", decision.remaining.toString());
  context.header("x-rate-limit-reset", decision.resetAt);
}

export function rateLimitRetryAfterSeconds(decision: RateLimitDecision) {
  return Math.max(1, Math.ceil(decision.retryAfterMs / 1000));
}

export function rateLimitExceededResponse(
  context: Context,
  decision: RateLimitDecision
) {
  applyRateLimitHeaders(context, decision);
  const retryAfterSeconds = rateLimitRetryAfterSeconds(decision);
  context.header("retry-after", retryAfterSeconds.toString());
  return context.json(
    RateLimitExceededResponseSchema.parse({
      code: "rate_limited",
      message: "Too many requests.",
      limit: decision.limit,
      retryAfterSeconds
    }),
    429
  );
}

export function defaultRateLimitKey(context: Context) {
  const forwardedFor = context.req.header("x-forwarded-for");
  const clientIp =
    forwardedFor?.split(",")[0]?.trim() ??
    context.req.header("x-real-ip") ??
    "unknown";
  const path = new URL(context.req.url).pathname;

  return `ip:${clientIp}:${context.req.method}:${path}`;
}

function resolveRateLimitPolicy(
  input: RateLimitPolicyInput = {}
): RateLimitPolicy {
  const policy = {
    limit: input.limit ?? DEFAULT_RATE_LIMIT_LIMIT,
    windowMs: input.windowMs ?? DEFAULT_RATE_LIMIT_WINDOW_MS,
    enforce: input.enforce ?? DEFAULT_RATE_LIMIT_ENFORCE,
    keyGenerator: input.keyGenerator ?? defaultRateLimitKey
  };

  validateRateLimitInput({
    key: "policy-validation",
    limit: policy.limit,
    windowMs: policy.windowMs
  });

  return policy;
}

function validateRateLimitInput(input: RateLimitRecordInput) {
  const cost = input.cost ?? 1;

  if (input.key.length === 0) {
    throw new Error("Rate-limit key must not be empty.");
  }
  if (!Number.isInteger(input.limit) || input.limit < 1) {
    throw new Error("Rate-limit limit must be a positive integer.");
  }
  if (!Number.isInteger(input.windowMs) || input.windowMs < 1) {
    throw new Error("Rate-limit windowMs must be a positive integer.");
  }
  if (!Number.isInteger(cost) || cost < 1) {
    throw new Error("Rate-limit cost must be a positive integer.");
  }
}
