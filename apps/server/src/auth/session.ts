import { and, eq, gt, isNull } from "drizzle-orm";

import type { ServerDatabase } from "../db/client.js";
import * as schema from "../db/schema.js";

/**
 * How long a sign-in session lives without use. These are Better Auth's own
 * defaults, stated here because two code paths must agree on them: Better
 * Auth's session endpoints, and {@link verifySessionToken}, which the sync and
 * Agent API routes use instead of those endpoints.
 */
export const SESSION_EXPIRES_IN_SECONDS = 60 * 60 * 24 * 7;

/**
 * How old a session's last renewal must be before a use renews it again, so
 * that a device syncing every few seconds writes the session row at most once
 * a day.
 */
export const SESSION_UPDATE_AGE_SECONDS = 60 * 60 * 24;

export type VerifiedSession = { userId: string };

/**
 * Resolves an app session bearer token to its user and slides the session's
 * expiry forward, as Better Auth's own `getSession` does.
 *
 * The sliding renewal is load-bearing. The app authenticates sync with the
 * session token alone and never calls Better Auth's session endpoints, so
 * without renewing here a session expires a fixed week after sign-in however
 * often the device syncs, and every synced device silently stops syncing
 * ("Sign in required") until its user signs in again.
 *
 * An expired session is never revived, and a user who has requested account
 * deletion resolves to null.
 */
export async function verifySessionToken(
  db: ServerDatabase,
  token: string,
  now: Date = new Date()
): Promise<VerifiedSession | null> {
  const rows = await db
    .select({
      id: schema.session.id,
      userId: schema.session.userId,
      expiresAt: schema.session.expiresAt
    })
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
  const session = rows[0];
  if (session === undefined) {
    return null;
  }

  const lastRenewedAt =
    session.expiresAt.getTime() - SESSION_EXPIRES_IN_SECONDS * 1000;
  if (lastRenewedAt + SESSION_UPDATE_AGE_SECONDS * 1000 <= now.getTime()) {
    await db
      .update(schema.session)
      .set({
        expiresAt: new Date(now.getTime() + SESSION_EXPIRES_IN_SECONDS * 1000),
        updatedAt: now
      })
      .where(
        and(
          eq(schema.session.id, session.id),
          // Never shorten a session another request just renewed further.
          eq(schema.session.expiresAt, session.expiresAt)
        )
      );
  }

  return { userId: session.userId };
}
