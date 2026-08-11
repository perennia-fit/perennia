import {
  createCipheriv,
  createDecipheriv,
  randomBytes,
  randomUUID
} from "node:crypto";
import { createRoute, z } from "@hono/zod-openapi";
import { and, eq, isNotNull, isNull } from "drizzle-orm";

import { GARMIN_OFFICIAL_ACQUISITION_ADAPTER } from "./acquisition-adapters.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";

export const GARMIN_OAUTH_SOURCE =
  GARMIN_OFFICIAL_ACQUISITION_ADAPTER.sourceKey as "garmin";
export const GARMIN_OAUTH_CREDENTIAL_NAME = "Garmin official connector";
export const GARMIN_OAUTH_STATE_TTL_SECONDS = 10 * 60;
export const GARMIN_OAUTH_START_ROUTE_PATH =
  "/integrations/garmin/oauth/start";
export const GARMIN_OAUTH_CALLBACK_ROUTE_PATH =
  "/integrations/garmin/oauth/callback";
export const GARMIN_OAUTH_DISCONNECT_ROUTE_PATH =
  "/integrations/garmin/oauth/disconnect";

const secretFormatVersion = "v1";
const tokenAadPrefix = "garmin-oauth-refresh-token";
const stateAad = Buffer.from("garmin-oauth-state:v1", "utf8");

export const GarminOAuthConnectionSchema = z
  .object({
    id: z.string().min(1),
    source: z.literal(GARMIN_OAUTH_SOURCE),
    credentialName: z.string().min(1),
    providerUserId: z.string().min(1).nullable(),
    scope: z.string().min(1).nullable(),
    connected: z.boolean(),
    connectedAt: z.string().min(1),
    revokedAt: z.string().min(1).nullable(),
    updatedAt: z.string().min(1)
  })
  .strict()
  .openapi("GarminOAuthConnection");

export const GarminOAuthStartResponseSchema = z
  .object({
    authorizationUrl: z.string().url(),
    stateExpiresAt: z.string().min(1)
  })
  .strict()
  .openapi("GarminOAuthStartResponse");

export const GarminOAuthCallbackQuerySchema = z
  .object({
    code: z.string().trim().min(1).openapi({
      param: {
        name: "code",
        in: "query"
      },
      description: "Authorization code returned by Garmin."
    }),
    state: z.string().trim().min(1).openapi({
      param: {
        name: "state",
        in: "query"
      },
      description: "Opaque state minted by the OAuth start route."
    })
  })
  .strict();

export const GarminOAuthCallbackResponseSchema = z
  .object({
    connection: GarminOAuthConnectionSchema
  })
  .strict()
  .openapi("GarminOAuthCallbackResponse");

export const GarminOAuthDisconnectResponseSchema = z
  .object({
    connectionId: z.string().min(1),
    disconnected: z.literal(true),
    revoked: z.boolean()
  })
  .strict()
  .openapi("GarminOAuthDisconnectResponse");

export const GarminOAuthUnauthorizedResponseSchema = z
  .object({
    code: z.literal("garmin_oauth_unauthorized"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("GarminOAuthUnauthorizedResponse");

export const GarminOAuthInvalidCallbackResponseSchema = z
  .object({
    code: z.literal("garmin_oauth_invalid_callback"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("GarminOAuthInvalidCallbackResponse");

export const GarminOAuthNotFoundResponseSchema = z
  .object({
    code: z.literal("garmin_oauth_connection_not_found"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("GarminOAuthNotFoundResponse");

export const GarminOAuthUnavailableResponseSchema = z
  .object({
    code: z.literal("garmin_oauth_unavailable"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("GarminOAuthUnavailableResponse");

export const garminOAuthStartRoute = createRoute({
  method: "post",
  path: GARMIN_OAUTH_START_ROUTE_PATH,
  operationId: "startGarminOAuth",
  tags: ["Integrations"],
  summary: "Start the official Garmin OAuth flow.",
  description:
    "Mints an opaque server state and returns Garmin's authorization URL for the hosted, business-gated official connector. No Garmin credential is exposed to the client.",
  security: [{ bearerAuth: [] }],
  responses: {
    200: {
      description: "Garmin authorization URL with opaque state.",
      content: {
        "application/json": {
          schema: GarminOAuthStartResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid session bearer token.",
      content: {
        "application/json": {
          schema: GarminOAuthUnauthorizedResponseSchema
        }
      }
    },
    503: {
      description: "Garmin OAuth storage or configuration is unavailable.",
      content: {
        "application/json": {
          schema: GarminOAuthUnavailableResponseSchema
        }
      }
    }
  }
});

export const garminOAuthCallbackRoute = createRoute({
  method: "get",
  path: GARMIN_OAUTH_CALLBACK_ROUTE_PATH,
  operationId: "completeGarminOAuth",
  tags: ["Integrations"],
  summary: "Complete the official Garmin OAuth flow.",
  description:
    "Exchanges Garmin's authorization code server-side, stores the refresh token encrypted at rest, and returns only connection metadata.",
  request: {
    query: GarminOAuthCallbackQuerySchema
  },
  responses: {
    200: {
      description: "Garmin connection metadata after successful authorization.",
      content: {
        "application/json": {
          schema: GarminOAuthCallbackResponseSchema
        }
      }
    },
    400: {
      description: "The callback state is invalid or expired.",
      content: {
        "application/json": {
          schema: GarminOAuthInvalidCallbackResponseSchema
        }
      }
    },
    503: {
      description: "Garmin OAuth storage, status storage, or configuration is unavailable.",
      content: {
        "application/json": {
          schema: GarminOAuthUnavailableResponseSchema
        }
      }
    }
  }
});

export const garminOAuthDisconnectRoute = createRoute({
  method: "post",
  path: GARMIN_OAUTH_DISCONNECT_ROUTE_PATH,
  operationId: "disconnectGarminOAuth",
  tags: ["Integrations"],
  summary: "Disconnect the official Garmin OAuth connector.",
  description:
    "Revokes the Garmin refresh token where the provider allows it and removes the encrypted custodied secret from storage.",
  security: [{ bearerAuth: [] }],
  responses: {
    200: {
      description: "The Garmin refresh token was revoked or forgotten.",
      content: {
        "application/json": {
          schema: GarminOAuthDisconnectResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid session bearer token.",
      content: {
        "application/json": {
          schema: GarminOAuthUnauthorizedResponseSchema
        }
      }
    },
    404: {
      description: "No active Garmin OAuth connection exists for this account.",
      content: {
        "application/json": {
          schema: GarminOAuthNotFoundResponseSchema
        }
      }
    },
    503: {
      description: "Garmin OAuth storage or configuration is unavailable.",
      content: {
        "application/json": {
          schema: GarminOAuthUnavailableResponseSchema
        }
      }
    }
  }
});

export type GarminOAuthConnection = z.infer<
  typeof GarminOAuthConnectionSchema
>;
export type GarminOAuthStartResponse = z.infer<
  typeof GarminOAuthStartResponseSchema
>;
export type GarminOAuthCallbackResponse = z.infer<
  typeof GarminOAuthCallbackResponseSchema
>;
export type GarminOAuthDisconnectResponse = z.infer<
  typeof GarminOAuthDisconnectResponseSchema
>;

export type GarminOAuthConfig = {
  authorizationEndpoint: string;
  clientId: string;
  redirectUri: string;
  scopes: readonly string[];
  stateTtlSeconds?: number;
};

export type GarminOAuthTokenResult = {
  accessToken: string;
  expiresInSeconds: number | null;
  providerUserId: string | null;
  refreshToken: string;
  scope: string | null;
};

export type GarminOAuthAccessTokenResult = {
  accessToken: string;
  expiresInSeconds: number | null;
};

export type GarminOAuthClient = {
  exchangeCode(input: {
    code: string;
    redirectUri: string;
  }): Promise<GarminOAuthTokenResult>;
  refreshAccessToken(input: {
    refreshToken: string;
  }): Promise<GarminOAuthAccessTokenResult>;
  revokeRefreshToken(refreshToken: string): Promise<{ revoked: boolean }>;
};

export type GarminOAuthConnectorConnection = GarminOAuthConnection & {
  userId: string;
};

export type GarminOAuthConnectionStore = {
  createOAuthState(input: {
    expiresAt: Date;
    userId: string;
  }): string;
  readOAuthState(input: {
    now?: Date;
    state: string;
  }): { userId: string } | null;
  upsertConnection(input: {
    accessTokenExpiresAt: Date | null;
    providerUserId: string | null;
    refreshToken: string;
    scope: string | null;
    userId: string;
  }): Promise<GarminOAuthConnection>;
  findActiveConnectionForUser(input: {
    userId: string;
  }): Promise<GarminOAuthConnection | null>;
  findActiveConnectionByProviderUserId(input: {
    providerUserId: string;
  }): Promise<GarminOAuthConnectorConnection | null>;
  listActiveConnectorConnections(): Promise<GarminOAuthConnectorConnection[]>;
  decryptRefreshTokenForConnectorJob(input: {
    connectionId: string;
    userId: string;
  }): Promise<string | null>;
  forgetRefreshToken(input: {
    connectionId: string;
    userId: string;
  }): Promise<boolean>;
};

export class GarminOAuthGrantExpiredError extends Error {
  readonly providerError: string | null;
  readonly providerErrorDescription: string | null;
  readonly status: number;

  constructor({
    providerError = null,
    providerErrorDescription = null,
    status
  }: {
    providerError?: string | null;
    providerErrorDescription?: string | null;
    status: number;
  }) {
    super("Garmin OAuth grant expired or was revoked.");
    this.name = "GarminOAuthGrantExpiredError";
    this.providerError = providerError;
    this.providerErrorDescription = providerErrorDescription;
    this.status = status;
  }
}

export type GarminOAuthTokenCipher = {
  decrypt(input: { aad: Buffer; encrypted: string }): string;
  encrypt(input: { aad: Buffer; plaintext: string }): string;
};

export function createGarminOAuthTokenCipher(
  keyInput: string | Uint8Array
): GarminOAuthTokenCipher {
  const key =
    typeof keyInput === "string" ? decodeCipherKey(keyInput) : Buffer.from(keyInput);
  if (key.byteLength !== 32) {
    throw new Error("Garmin OAuth token encryption key must be 32 bytes.");
  }

  return {
    encrypt({ aad, plaintext }) {
      const iv = randomBytes(12);
      const cipher = createCipheriv("aes-256-gcm", key, iv);
      cipher.setAAD(aad);
      const encrypted = Buffer.concat([
        cipher.update(plaintext, "utf8"),
        cipher.final()
      ]);
      const tag = cipher.getAuthTag();

      return [
        secretFormatVersion,
        iv.toString("base64url"),
        tag.toString("base64url"),
        encrypted.toString("base64url")
      ].join(".");
    },
    decrypt({ aad, encrypted }) {
      const [version, ivText, tagText, payloadText] = encrypted.split(".", 4);
      if (
        version !== secretFormatVersion ||
        ivText === undefined ||
        tagText === undefined ||
        payloadText === undefined
      ) {
        throw new Error("Invalid Garmin OAuth encrypted value.");
      }

      const decipher = createDecipheriv(
        "aes-256-gcm",
        key,
        Buffer.from(ivText, "base64url")
      );
      decipher.setAAD(aad);
      decipher.setAuthTag(Buffer.from(tagText, "base64url"));
      return Buffer.concat([
        decipher.update(Buffer.from(payloadText, "base64url")),
        decipher.final()
      ]).toString("utf8");
    }
  };
}

export function createDrizzleGarminOAuthConnectionStore({
  cipher,
  db
}: {
  cipher: GarminOAuthTokenCipher;
  db: ServerDatabase;
}): GarminOAuthConnectionStore {
  return {
    createOAuthState({ expiresAt, userId }) {
      return cipher.encrypt({
        aad: stateAad,
        plaintext: JSON.stringify({
          version: 1,
          userId,
          expiresAt: expiresAt.toISOString(),
          nonce: randomBytes(16).toString("base64url")
        })
      });
    },
    readOAuthState({ now = new Date(), state }) {
      let parsed: unknown;
      try {
        parsed = JSON.parse(cipher.decrypt({ aad: stateAad, encrypted: state }));
      } catch {
        return null;
      }

      const result = z
        .object({
          version: z.literal(1),
          userId: z.string().min(1),
          expiresAt: z.string().min(1),
          nonce: z.string().min(1)
        })
        .strict()
        .safeParse(parsed);
      if (!result.success) {
        return null;
      }

      const expiresAt = new Date(result.data.expiresAt);
      if (Number.isNaN(expiresAt.getTime()) || expiresAt < now) {
        return null;
      }

      return { userId: result.data.userId };
    },
    async upsertConnection({
      accessTokenExpiresAt,
      providerUserId,
      refreshToken,
      scope,
      userId
    }) {
      const now = new Date();
      const existing = await findConnectionRow(db, userId);
      const connectionId = existing?.id ?? randomUUID();
      const encryptedRefreshToken = cipher.encrypt({
        aad: tokenAad({ connectionId, userId }),
        plaintext: refreshToken
      });
      const values = {
        source: GARMIN_OAUTH_SOURCE,
        credentialName: GARMIN_OAUTH_CREDENTIAL_NAME,
        providerUserId,
        scope,
        encryptedRefreshToken,
        accessTokenExpiresAt,
        connectedAt: existing?.connectedAt ?? now,
        revokedAt: null,
        updatedAt: now
      };

      const row =
        existing === null
          ? (
              await db
                .insert(schema.garminOAuthConnections)
                .values({
                  id: connectionId,
                  userId,
                  ...values
                })
                .returning()
            )[0]
          : (
              await db
                .update(schema.garminOAuthConnections)
                .set(values)
                .where(eq(schema.garminOAuthConnections.id, connectionId))
                .returning()
            )[0];

      if (row === undefined) {
        throw new Error("Garmin OAuth connection was not stored.");
      }

      return mapConnection(row);
    },
    async findActiveConnectionForUser({ userId }) {
      const row = await findConnectionRow(db, userId);
      if (row === null || row.encryptedRefreshToken === null || row.revokedAt !== null) {
        return null;
      }

      return mapConnection(row);
    },
    async findActiveConnectionByProviderUserId({ providerUserId }) {
      const rows = await db
        .select()
        .from(schema.garminOAuthConnections)
        .where(
          and(
            eq(schema.garminOAuthConnections.providerUserId, providerUserId),
            eq(schema.garminOAuthConnections.source, GARMIN_OAUTH_SOURCE),
            isNull(schema.garminOAuthConnections.revokedAt)
          )
        )
        .limit(1);
      const row = rows[0] ?? null;
      if (row === null || row.encryptedRefreshToken === null) {
        return null;
      }

      return mapConnectorConnection(row);
    },
    async listActiveConnectorConnections() {
      const rows = await db
        .select()
        .from(schema.garminOAuthConnections)
        .where(
          and(
            eq(schema.garminOAuthConnections.source, GARMIN_OAUTH_SOURCE),
            isNull(schema.garminOAuthConnections.revokedAt),
            isNotNull(schema.garminOAuthConnections.encryptedRefreshToken)
          )
        );

      return rows
        .filter((row) => row.encryptedRefreshToken !== null)
        .map(mapConnectorConnection);
    },
    async decryptRefreshTokenForConnectorJob({ connectionId, userId }) {
      const rows = await db
        .select({
          encryptedRefreshToken:
            schema.garminOAuthConnections.encryptedRefreshToken
        })
        .from(schema.garminOAuthConnections)
        .where(
          and(
            eq(schema.garminOAuthConnections.id, connectionId),
            eq(schema.garminOAuthConnections.userId, userId),
            eq(schema.garminOAuthConnections.source, GARMIN_OAUTH_SOURCE),
            isNull(schema.garminOAuthConnections.revokedAt)
          )
        )
        .limit(1);
      const encrypted = rows[0]?.encryptedRefreshToken ?? null;
      if (encrypted === null) {
        return null;
      }

      return cipher.decrypt({
        aad: tokenAad({ connectionId, userId }),
        encrypted
      });
    },
    async forgetRefreshToken({ connectionId, userId }) {
      const now = new Date();
      const rows = await db
        .update(schema.garminOAuthConnections)
        .set({
          encryptedRefreshToken: null,
          accessTokenExpiresAt: null,
          revokedAt: now,
          updatedAt: now
        })
        .where(
          and(
            eq(schema.garminOAuthConnections.id, connectionId),
            eq(schema.garminOAuthConnections.userId, userId),
            eq(schema.garminOAuthConnections.source, GARMIN_OAUTH_SOURCE)
          )
        )
        .returning({ id: schema.garminOAuthConnections.id });

      return rows.length > 0;
    }
  };
}

export function createGarminAuthorizationUrl({
  config,
  state
}: {
  config: GarminOAuthConfig;
  state: string;
}) {
  const url = new URL(config.authorizationEndpoint);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("client_id", config.clientId);
  url.searchParams.set("redirect_uri", config.redirectUri);
  url.searchParams.set("scope", config.scopes.join(" "));
  url.searchParams.set("state", state);
  return url.toString();
}

export function createGarminOAuthHttpClient({
  clientId,
  clientSecret,
  fetchImpl = globalThis.fetch,
  revokeEndpoint,
  tokenEndpoint
}: {
  clientId: string;
  clientSecret: string;
  fetchImpl?: typeof fetch;
  revokeEndpoint?: string;
  tokenEndpoint: string;
}): GarminOAuthClient {
  return {
    async exchangeCode({ code, redirectUri }) {
      const response = await fetchImpl(tokenEndpoint, {
        method: "POST",
        headers: {
          authorization: basicAuth(clientId, clientSecret),
          "content-type": "application/x-www-form-urlencoded",
          accept: "application/json"
        },
        body: new URLSearchParams({
          grant_type: "authorization_code",
          code,
          redirect_uri: redirectUri
        })
      });
      if (!response.ok) {
        throw new Error(`Garmin OAuth token exchange failed with ${response.status}.`);
      }
      const body = await response.json();

      return {
        accessToken: requiredString(body, "access_token"),
        expiresInSeconds: optionalNumber(body, "expires_in"),
        providerUserId:
          optionalString(body, "user_id") ??
          optionalString(body, "athlete_id") ??
          optionalString(body, "sub"),
        refreshToken: requiredString(body, "refresh_token"),
        scope: optionalString(body, "scope")
      };
    },
    async refreshAccessToken({ refreshToken }) {
      const response = await fetchImpl(tokenEndpoint, {
        method: "POST",
        headers: {
          authorization: basicAuth(clientId, clientSecret),
          "content-type": "application/x-www-form-urlencoded",
          accept: "application/json"
        },
        body: new URLSearchParams({
          grant_type: "refresh_token",
          refresh_token: refreshToken
        })
      });
      if (!response.ok) {
        const body = await readJsonResponseBody(response);
        if (isGarminOAuthGrantExpiredResponse(response, body)) {
          throw new GarminOAuthGrantExpiredError({
            providerError: optionalString(body, "error"),
            providerErrorDescription: optionalString(body, "error_description"),
            status: response.status
          });
        }
        throw new Error(`Garmin OAuth token refresh failed with ${response.status}.`);
      }
      const body = await response.json();

      return {
        accessToken: requiredString(body, "access_token"),
        expiresInSeconds: optionalNumber(body, "expires_in")
      };
    },
    async revokeRefreshToken(refreshToken) {
      if (revokeEndpoint === undefined || revokeEndpoint.length === 0) {
        return { revoked: false };
      }
      const response = await fetchImpl(revokeEndpoint, {
        method: "POST",
        headers: {
          authorization: basicAuth(clientId, clientSecret),
          "content-type": "application/x-www-form-urlencoded",
          accept: "application/json"
        },
        body: new URLSearchParams({
          token: refreshToken,
          token_type_hint: "refresh_token"
        })
      });

      return { revoked: response.ok || response.status === 400 };
    }
  };
}

async function readJsonResponseBody(response: Response) {
  try {
    return await response.json();
  } catch {
    return null;
  }
}

function isGarminOAuthGrantExpiredResponse(response: Response, body: unknown) {
  const providerError = optionalString(body, "error");
  return (
    providerError === "invalid_grant" ||
    providerError === "invalid_token" ||
    (response.status === 401 && providerError !== "invalid_client")
  );
}

export function garminAccessTokenExpiresAt(
  expiresInSeconds: number | null,
  now = new Date()
) {
  return expiresInSeconds === null
    ? null
    : new Date(now.getTime() + expiresInSeconds * 1000);
}

export function createGarminOAuthRuntimeFromEnv({
  db,
  env = process.env,
  fetchImpl
}: {
  db: ServerDatabase;
  env?: NodeJS.ProcessEnv;
  fetchImpl?: typeof fetch;
}) {
  const clientId = nonEmpty(env.GARMIN_OAUTH_CLIENT_ID);
  const clientSecret = nonEmpty(env.GARMIN_OAUTH_CLIENT_SECRET);
  const redirectUri = nonEmpty(env.GARMIN_OAUTH_REDIRECT_URI);
  const encryptionKey = nonEmpty(env.GARMIN_OAUTH_TOKEN_ENCRYPTION_KEY);
  const authorizationEndpoint =
    nonEmpty(env.GARMIN_OAUTH_AUTHORIZATION_URL) ??
    "https://apis.garmin.com/oauth-service/oauth/authorize";
  const tokenEndpoint =
    nonEmpty(env.GARMIN_OAUTH_TOKEN_URL) ??
    "https://apis.garmin.com/oauth-service/oauth/token";
  if (
    clientId === null ||
    clientSecret === null ||
    redirectUri === null ||
    encryptionKey === null
  ) {
    return null;
  }

  const config: GarminOAuthConfig = {
    authorizationEndpoint,
    clientId,
    redirectUri,
    scopes: (nonEmpty(env.GARMIN_OAUTH_SCOPES) ?? "activity heartrate")
      .split(/[,\s]+/)
      .map((scope) => scope.trim())
      .filter((scope) => scope.length > 0),
    stateTtlSeconds: positiveInteger(env.GARMIN_OAUTH_STATE_TTL_SECONDS)
  };
  const client = createGarminOAuthHttpClient({
    clientId,
    clientSecret,
    fetchImpl,
    revokeEndpoint: nonEmpty(env.GARMIN_OAUTH_REVOKE_URL) ?? undefined,
    tokenEndpoint
  });
  const store = createDrizzleGarminOAuthConnectionStore({
    cipher: createGarminOAuthTokenCipher(encryptionKey),
    db
  });

  return { config, client, store };
}

async function findConnectionRow(db: ServerDatabase, userId: string) {
  return (
    (
      await db
        .select()
        .from(schema.garminOAuthConnections)
        .where(
          and(
            eq(schema.garminOAuthConnections.userId, userId),
            eq(schema.garminOAuthConnections.source, GARMIN_OAUTH_SOURCE)
          )
        )
        .limit(1)
    )[0] ?? null
  );
}

function mapConnection(
  row: typeof schema.garminOAuthConnections.$inferSelect
): GarminOAuthConnection {
  return GarminOAuthConnectionSchema.parse({
    id: row.id,
    source: row.source,
    credentialName: row.credentialName,
    providerUserId: row.providerUserId,
    scope: row.scope,
    connected: row.encryptedRefreshToken !== null && row.revokedAt === null,
    connectedAt: row.connectedAt.toISOString(),
    revokedAt: row.revokedAt?.toISOString() ?? null,
    updatedAt: row.updatedAt.toISOString()
  });
}

function mapConnectorConnection(
  row: typeof schema.garminOAuthConnections.$inferSelect
): GarminOAuthConnectorConnection {
  return {
    ...mapConnection(row),
    userId: row.userId
  };
}

function tokenAad({
  connectionId,
  userId
}: {
  connectionId: string;
  userId: string;
}) {
  return Buffer.from(`${tokenAadPrefix}:${userId}:${connectionId}`, "utf8");
}

function decodeCipherKey(value: string) {
  const trimmed = value.trim();
  if (/^[0-9a-f]{64}$/i.test(trimmed)) {
    return Buffer.from(trimmed, "hex");
  }

  return Buffer.from(trimmed, "base64url");
}

function basicAuth(clientId: string, clientSecret: string) {
  return `Basic ${Buffer.from(`${clientId}:${clientSecret}`, "utf8").toString(
    "base64"
  )}`;
}

function requiredString(body: unknown, key: string) {
  const value = optionalString(body, key);
  if (value === null) {
    throw new Error(`Garmin OAuth response is missing ${key}.`);
  }
  return value;
}

function optionalString(body: unknown, key: string) {
  if (typeof body !== "object" || body === null || !(key in body)) {
    return null;
  }
  const value = (body as Record<string, unknown>)[key];
  return typeof value === "string" && value.length > 0 ? value : null;
}

function optionalNumber(body: unknown, key: string) {
  if (typeof body !== "object" || body === null || !(key in body)) {
    return null;
  }
  const value = (body as Record<string, unknown>)[key];
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function nonEmpty(value: string | undefined) {
  return value === undefined || value.trim().length === 0 ? null : value.trim();
}

function positiveInteger(value: string | undefined) {
  if (value === undefined || value.trim().length === 0) {
    return undefined;
  }
  const parsed = Number.parseInt(value, 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : undefined;
}
