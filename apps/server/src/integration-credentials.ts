import {
  randomBytes,
  randomUUID,
  scrypt as scryptCallback,
  timingSafeEqual
} from "node:crypto";
import { promisify } from "node:util";
import { createRoute, z } from "@hono/zod-openapi";
import { and, asc, desc, eq, isNull } from "drizzle-orm";

import {
  DEFAULT_AGENT_API_KEY_RATE_LIMIT_MAX,
  DEFAULT_AGENT_API_KEY_RATE_LIMIT_WINDOW_MS
} from "./agent-api-keys.js";
import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import {
  RateLimitExceededOpenApiResponse,
  type RateLimitBackend,
  type RateLimitDecision
} from "./rate-limit.js";
import { CANONICAL_IMPORT_CONSENT_DATA_CLASSES } from "./canonical-import.js";

const scrypt = promisify(scryptCallback);

export const INTEGRATION_CREDENTIAL_ACTOR = "integration";
export const INTEGRATION_CREDENTIAL_CONFIG_ID = "integration-import";
export const INTEGRATION_CREDENTIAL_PREFIX = "prn_integration_";
export const DEFAULT_INTEGRATION_CREDENTIAL_SOURCE = "garmin";
export const DEFAULT_INTEGRATION_CREDENTIAL_RATE_LIMIT_MAX =
  DEFAULT_AGENT_API_KEY_RATE_LIMIT_MAX;
export const DEFAULT_INTEGRATION_CREDENTIAL_RATE_LIMIT_WINDOW_MS =
  DEFAULT_AGENT_API_KEY_RATE_LIMIT_WINDOW_MS;
export const INTEGRATION_CONSENT_DEFAULT_DEVICE_ID =
  "server:integration-credential";
export const IMPORT_CREDENTIALS_ROUTE_PATH =
  "/integrations/import-credentials";
export const IMPORT_CREDENTIAL_ROUTE_PATH =
  "/integrations/import-credentials/{credentialId}";
export const IMPORT_PROFILE_ROUTE_PATH = "/integrations/import-profile";

export const IntegrationCredentialSourceSchema = z
  .string()
  .trim()
  .min(1)
  .max(80)
  .regex(/^[a-z][a-z0-9_-]*$/)
  .openapi("IntegrationCredentialSource", {
    description:
      "User-operated acquisition source label for this import credential, such as garmin or garmin-garmindb."
  });

export const IntegrationCredentialScopeSchema = z
  .object({
    writeObservations: z.literal(true),
    materializeAndLinkWorkouts: z.literal(true),
    accountMutation: z.literal(false),
    hardDeleteOrPurge: z.literal(false)
  })
  .strict();

export const DEFAULT_IMPORT_SCOPED_INTEGRATION_CREDENTIAL_SCOPE =
  IntegrationCredentialScopeSchema.parse({
    writeObservations: true,
    materializeAndLinkWorkouts: true,
    accountMutation: false,
    hardDeleteOrPurge: false
  });

export const IntegrationCredentialOperationSchema = z.enum([
  "write_observations",
  "materialize_and_link_workouts",
  "account_mutation",
  "hard_delete_or_purge"
]);

export const IntegrationCredentialMetadataSchema = z
  .object({
    id: z.string().min(1),
    source: IntegrationCredentialSourceSchema,
    name: z.string().min(1),
    prefix: z.string().min(1).nullable(),
    start: z.string().min(1).nullable(),
    createdAt: z.string().min(1),
    lastUsedAt: z.string().min(1).nullable(),
    revoked: z.boolean(),
    scope: IntegrationCredentialScopeSchema
  })
  .strict();

export const IntegrationCredentialIssueResponseSchema = z
  .object({
    credential: IntegrationCredentialMetadataSchema,
    secret: z.string().min(1)
  })
  .strict()
  .openapi("IntegrationCredentialIssueResponse");

export const IntegrationCredentialCreateRequestSchema = z
  .object({
    name: z.string().trim().min(1).max(80),
    source: IntegrationCredentialSourceSchema.default(
      DEFAULT_INTEGRATION_CREDENTIAL_SOURCE
    )
  })
  .strict()
  .openapi("IntegrationCredentialCreateRequest");

export const IntegrationCredentialListResponseSchema = z
  .object({
    credentials: z.array(IntegrationCredentialMetadataSchema)
  })
  .strict()
  .openapi("IntegrationCredentialListResponse");

export const IntegrationCredentialRevokeResponseSchema = z
  .object({
    revoked: z.literal(true)
  })
  .strict()
  .openapi("IntegrationCredentialRevokeResponse");

export const IntegrationCredentialUnavailableResponseSchema = z
  .object({
    code: z.literal("integration_credentials_unavailable"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("IntegrationCredentialUnavailableResponse");

export const IntegrationCredentialUnauthorizedResponseSchema = z
  .object({
    code: z.literal("integration_credentials_unauthorized"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("IntegrationCredentialUnauthorizedResponse");

export const IntegrationCredentialForbiddenResponseSchema = z
  .object({
    code: z.literal("integration_credentials_forbidden"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("IntegrationCredentialForbiddenResponse");

export const IntegrationCredentialNotFoundResponseSchema = z
  .object({
    code: z.literal("integration_credential_not_found"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("IntegrationCredentialNotFoundResponse");

export const IntegrationImportDataClassAccessSchema = z
  .object({
    dataClass: z.enum(CANONICAL_IMPORT_CONSENT_DATA_CLASSES),
    enabled: z.boolean()
  })
  .strict()
  .openapi("IntegrationImportDataClassAccess");

export const IntegrationImportProfileResponseSchema = z
  .object({
    credential: z
      .object({
        id: z.string().min(1),
        name: z.string().min(1),
        source: IntegrationCredentialSourceSchema
      })
      .strict(),
    dataClasses: z.array(IntegrationImportDataClassAccessSchema),
    enabledDataClasses: z.array(z.enum(CANONICAL_IMPORT_CONSENT_DATA_CLASSES)),
    fitImportEnabled: z.boolean(),
    manualFitImport: z
      .object({
        enabled: z.literal(true),
        uploadPath: z.literal("/integrations/garmin/fit-import")
      })
      .strict()
  })
  .strict()
  .openapi("IntegrationImportProfileResponse");

export type IntegrationCredentialScope = z.infer<
  typeof IntegrationCredentialScopeSchema
>;
export type IntegrationCredentialOperation = z.infer<
  typeof IntegrationCredentialOperationSchema
>;
export type IntegrationCredentialMetadata = z.infer<
  typeof IntegrationCredentialMetadataSchema
>;
export type IntegrationCredentialIssueResponse = z.infer<
  typeof IntegrationCredentialIssueResponseSchema
>;
export type IntegrationImportDataClassAccess = z.infer<
  typeof IntegrationImportDataClassAccessSchema
>;
export type IntegrationImportProfileResponse = z.infer<
  typeof IntegrationImportProfileResponseSchema
>;

export type AuthenticatedIntegrationCredential = {
  actor: typeof INTEGRATION_CREDENTIAL_ACTOR;
  userId: string;
  credentialId: string;
  credentialName: string | null;
  source: string;
  scope: IntegrationCredentialScope;
  rateLimitEnabled?: boolean;
  rateLimitTimeWindow?: number | null;
  rateLimitMax?: number | null;
};

export type IntegrationCredentialStore = {
  issueIntegrationCredential(input: {
    name: string;
    source?: string;
    userId: string;
    rateLimitEnabled?: boolean;
    rateLimitTimeWindow?: number | null;
    rateLimitMax?: number | null;
  }): Promise<IntegrationCredentialIssueResponse>;
  authenticateIntegrationCredential(
    secret: string
  ): Promise<AuthenticatedIntegrationCredential | null>;
  listIntegrationCredentials(
    userId: string
  ): Promise<IntegrationCredentialMetadata[]>;
  revokeIntegrationCredential(input: {
    credentialId: string;
    userId: string;
  }): Promise<boolean>;
  listIntegrationCredentialConsentDataClasses(input: {
    credentialId: string;
    userId: string;
  }): Promise<IntegrationImportDataClassAccess[]>;
};

export const integrationCredentialCreateRoute = createRoute({
  method: "post",
  path: IMPORT_CREDENTIALS_ROUTE_PATH,
  operationId: "createIntegrationImportCredential",
  tags: ["Integrations"],
  summary: "Create an import-scoped Integration credential.",
  description:
    "Issues a one-time secret for user-operated import tooling such as the GarminDB sync example. Creating the credential also creates default-off Garmin import consent rows.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: IntegrationCredentialCreateRequestSchema
        }
      }
    }
  },
  responses: {
    201: {
      description: "The credential was created. The secret is shown once.",
      content: {
        "application/json": {
          schema: IntegrationCredentialIssueResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid session bearer token.",
      content: {
        "application/json": {
          schema: IntegrationCredentialUnauthorizedResponseSchema
        }
      }
    },
    503: {
      description: "Credential storage or session auth is not configured.",
      content: {
        "application/json": {
          schema: IntegrationCredentialUnavailableResponseSchema
        }
      }
    }
  }
});

export const integrationCredentialListRoute = createRoute({
  method: "get",
  path: IMPORT_CREDENTIALS_ROUTE_PATH,
  operationId: "listIntegrationImportCredentials",
  tags: ["Integrations"],
  summary: "List import-scoped Integration credentials.",
  security: [{ bearerAuth: [] }],
  responses: {
    200: {
      description: "Metadata for the user's import-scoped credentials.",
      content: {
        "application/json": {
          schema: IntegrationCredentialListResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid session bearer token.",
      content: {
        "application/json": {
          schema: IntegrationCredentialUnauthorizedResponseSchema
        }
      }
    },
    503: {
      description: "Credential storage or session auth is not configured.",
      content: {
        "application/json": {
          schema: IntegrationCredentialUnavailableResponseSchema
        }
      }
    }
  }
});

export const integrationCredentialRevokeRoute = createRoute({
  method: "delete",
  path: IMPORT_CREDENTIAL_ROUTE_PATH,
  operationId: "revokeIntegrationImportCredential",
  tags: ["Integrations"],
  summary: "Revoke an import-scoped Integration credential.",
  security: [{ bearerAuth: [] }],
  request: {
    params: z
      .object({
        credentialId: z.string().min(1)
      })
      .strict()
  },
  responses: {
    200: {
      description: "The credential was revoked.",
      content: {
        "application/json": {
          schema: IntegrationCredentialRevokeResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid session bearer token.",
      content: {
        "application/json": {
          schema: IntegrationCredentialUnauthorizedResponseSchema
        }
      }
    },
    404: {
      description: "No credential exists for this account with that id.",
      content: {
        "application/json": {
          schema: IntegrationCredentialNotFoundResponseSchema
        }
      }
    },
    503: {
      description: "Credential storage or session auth is not configured.",
      content: {
        "application/json": {
          schema: IntegrationCredentialUnavailableResponseSchema
        }
      }
    }
  }
});

export const integrationImportProfileRoute = createRoute({
  method: "get",
  path: IMPORT_PROFILE_ROUTE_PATH,
  operationId: "getIntegrationImportProfile",
  tags: ["Integrations"],
  summary: "Read enabled import profile for an import credential.",
  description:
    "Used by edge automation before acquisition. The script must refuse to run when Garmin FIT activities are not enabled.",
  security: [{ bearerAuth: [] }],
  responses: {
    200: {
      description:
        "The authenticated credential's source and enabled import data classes.",
      content: {
        "application/json": {
          schema: IntegrationImportProfileResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid Integration credential.",
      content: {
        "application/json": {
          schema: IntegrationCredentialUnauthorizedResponseSchema
        }
      }
    },
    403: {
      description: "The Integration credential is not scoped for import.",
      content: {
        "application/json": {
          schema: IntegrationCredentialForbiddenResponseSchema
        }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Credential storage is not configured.",
      content: {
        "application/json": {
          schema: IntegrationCredentialUnavailableResponseSchema
        }
      }
    }
  }
});

export type IntegrationCredentialAuthLogger = {
  error?(payload: Record<string, unknown>, message: string): void;
};

export type IntegrationCredentialOperationAuthResult =
  | {
      status: "authenticated";
      credential: AuthenticatedIntegrationCredential;
      rateLimitDecision?: RateLimitDecision;
    }
  | {
      status: "forbidden";
      credential: AuthenticatedIntegrationCredential;
    }
  | {
      status: "rate_limited";
      decision: RateLimitDecision;
    }
  | {
      status: "unauthorized";
    };

export function isIntegrationCredentialOperationAllowed(
  scope: IntegrationCredentialScope,
  operation: IntegrationCredentialOperation
) {
  switch (operation) {
    case "write_observations":
      return scope.writeObservations;
    case "materialize_and_link_workouts":
      return scope.materializeAndLinkWorkouts;
    case "account_mutation":
      return scope.accountMutation;
    case "hard_delete_or_purge":
      return scope.hardDeleteOrPurge;
  }
}

export async function authenticateIntegrationCredentialOperation({
  secret,
  operation,
  integrationCredentialStore,
  rateLimitBackend,
  logger
}: {
  secret: string;
  operation: IntegrationCredentialOperation;
  integrationCredentialStore: IntegrationCredentialStore;
  rateLimitBackend: RateLimitBackend | undefined;
  logger: IntegrationCredentialAuthLogger;
}): Promise<IntegrationCredentialOperationAuthResult> {
  const parsedOperation = IntegrationCredentialOperationSchema.parse(operation);
  const credential =
    await integrationCredentialStore.authenticateIntegrationCredential(secret);
  if (credential === null) {
    return { status: "unauthorized" };
  }

  if (
    !isIntegrationCredentialOperationAllowed(
      credential.scope,
      parsedOperation
    )
  ) {
    return { status: "forbidden", credential };
  }

  if (rateLimitBackend === undefined || credential.rateLimitEnabled === false) {
    return { status: "authenticated", credential };
  }

  try {
    const decision = await rateLimitBackend.recordHit({
      key: `integration-credential:${credential.credentialId}`,
      limit: positiveIntegerOrDefault(
        credential.rateLimitMax,
        DEFAULT_INTEGRATION_CREDENTIAL_RATE_LIMIT_MAX
      ),
      windowMs: positiveIntegerOrDefault(
        credential.rateLimitTimeWindow,
        DEFAULT_INTEGRATION_CREDENTIAL_RATE_LIMIT_WINDOW_MS
      )
    });

    if (!decision.allowed) {
      return { status: "rate_limited", decision };
    }

    return { status: "authenticated", credential, rateLimitDecision: decision };
  } catch (error) {
    logger.error?.(
      { error, credentialId: credential.credentialId },
      "integration credential rate-limit failed open"
    );
    return { status: "authenticated", credential };
  }
}

export function createDrizzleIntegrationCredentialStore(
  db: ServerDatabase
): IntegrationCredentialStore {
  return {
    async issueIntegrationCredential(input) {
      const name = z.string().trim().min(1).max(80).parse(input.name);
      const source = IntegrationCredentialSourceSchema.parse(
        input.source ?? DEFAULT_INTEGRATION_CREDENTIAL_SOURCE
      );
      const users = await db
        .select({ id: schema.user.id })
        .from(schema.user)
        .where(
          and(
            eq(schema.user.id, input.userId),
            isNull(schema.user.deletionRequestedAt)
          )
        )
        .limit(1);

      if (users.length === 0) {
        throw new Error("Integration credential user does not exist.");
      }

      const secret = createIntegrationCredentialSecret();
      const key = await hashSecret(secret.secret);
      const now = new Date();
      const row = await db.transaction(async (transaction) => {
        const created = await transaction
          .insert(schema.apikey)
          .values({
            id: randomUUID(),
            configId: INTEGRATION_CREDENTIAL_CONFIG_ID,
            name,
            start: secret.start,
            prefix: INTEGRATION_CREDENTIAL_PREFIX,
            key,
            referenceId: input.userId,
            enabled: true,
            rateLimitEnabled: input.rateLimitEnabled ?? true,
            rateLimitTimeWindow: positiveIntegerOrDefault(
              input.rateLimitTimeWindow,
              DEFAULT_INTEGRATION_CREDENTIAL_RATE_LIMIT_WINDOW_MS
            ),
            rateLimitMax: positiveIntegerOrDefault(
              input.rateLimitMax,
              DEFAULT_INTEGRATION_CREDENTIAL_RATE_LIMIT_MAX
            ),
            permissions: JSON.stringify({
              scope: DEFAULT_IMPORT_SCOPED_INTEGRATION_CREDENTIAL_SCOPE
            }),
            metadata: JSON.stringify({
              actor: INTEGRATION_CREDENTIAL_ACTOR,
              credentialType: "import_scoped",
              source,
              version: 1
            })
          })
          .returning();

        const credential = created[0];
        if (credential === undefined) {
          throw new Error("Integration credential was not created.");
        }

        await transaction.insert(schema.integrationDataClassConsents).values(
          CANONICAL_IMPORT_CONSENT_DATA_CLASSES.map((dataClass) => ({
            id: generateUuidV7(now),
            userId: input.userId,
            deviceId: INTEGRATION_CONSENT_DEFAULT_DEVICE_ID,
            credentialId: credential.id,
            dataClass,
            enabled: false,
            updatedAt: now,
            deletedAt: null,
            receivedAt: now
          }))
        );

        return credential;
      });

      return IntegrationCredentialIssueResponseSchema.parse({
        credential: mapIntegrationCredentialMetadata(row),
        secret: secret.secret
      });
    },
    async authenticateIntegrationCredential(secret) {
      const parsedSecret = parseIntegrationCredentialSecret(secret);
      if (parsedSecret === null) {
        return null;
      }

      const rows = await db
        .select({
          id: schema.apikey.id,
          name: schema.apikey.name,
          key: schema.apikey.key,
          referenceId: schema.apikey.referenceId,
          permissions: schema.apikey.permissions,
          metadata: schema.apikey.metadata,
          rateLimitEnabled: schema.apikey.rateLimitEnabled,
          rateLimitTimeWindow: schema.apikey.rateLimitTimeWindow,
          rateLimitMax: schema.apikey.rateLimitMax
        })
        .from(schema.apikey)
        .innerJoin(schema.user, eq(schema.user.id, schema.apikey.referenceId))
        .where(
          and(
            eq(schema.apikey.configId, INTEGRATION_CREDENTIAL_CONFIG_ID),
            eq(schema.apikey.start, parsedSecret.start),
            eq(schema.apikey.enabled, true),
            isNull(schema.user.deletionRequestedAt)
          )
        )
        .limit(1);
      const row = rows[0];

      if (row === undefined) {
        return null;
      }

      if (!(await verifySecret(secret, row.key))) {
        return null;
      }

      await db
        .update(schema.apikey)
        .set({
          lastRequest: new Date(),
          updatedAt: new Date()
        })
        .where(
          and(
            eq(schema.apikey.id, row.id),
            eq(schema.apikey.configId, INTEGRATION_CREDENTIAL_CONFIG_ID),
            eq(schema.apikey.enabled, true)
          )
        );

      return {
        actor: INTEGRATION_CREDENTIAL_ACTOR,
        userId: row.referenceId,
        credentialId: row.id,
        credentialName: row.name,
        source: parseStoredSource(row.metadata),
        scope: parseStoredScope(row.permissions),
        rateLimitEnabled: row.rateLimitEnabled,
        rateLimitTimeWindow: row.rateLimitTimeWindow,
        rateLimitMax: row.rateLimitMax
      };
    },
    async listIntegrationCredentials(userId) {
      const rows = await db
        .select()
        .from(schema.apikey)
        .where(
          and(
            eq(schema.apikey.configId, INTEGRATION_CREDENTIAL_CONFIG_ID),
            eq(schema.apikey.referenceId, userId)
          )
        )
        .orderBy(desc(schema.apikey.createdAt));

      return rows.map(mapIntegrationCredentialMetadata);
    },
    async revokeIntegrationCredential({ credentialId, userId }) {
      const revoked = await db
        .update(schema.apikey)
        .set({
          enabled: false,
          updatedAt: new Date()
        })
        .where(
          and(
            eq(schema.apikey.id, credentialId),
            eq(schema.apikey.configId, INTEGRATION_CREDENTIAL_CONFIG_ID),
            eq(schema.apikey.referenceId, userId)
          )
        )
        .returning({ id: schema.apikey.id });

      return revoked.length > 0;
    },
    async listIntegrationCredentialConsentDataClasses({ credentialId, userId }) {
      const rows = await db
        .select({
          dataClass: schema.integrationDataClassConsents.dataClass,
          enabled: schema.integrationDataClassConsents.enabled,
          deletedAt: schema.integrationDataClassConsents.deletedAt
        })
        .from(schema.integrationDataClassConsents)
        .where(
          and(
            eq(schema.integrationDataClassConsents.userId, userId),
            eq(schema.integrationDataClassConsents.credentialId, credentialId)
          )
        )
        .orderBy(asc(schema.integrationDataClassConsents.dataClass));

      const rowsByDataClass = new Map(
        rows.map((row) => [
          row.dataClass,
          row.deletedAt === null && row.enabled
        ])
      );

      return CANONICAL_IMPORT_CONSENT_DATA_CLASSES.map((dataClass) =>
        IntegrationImportDataClassAccessSchema.parse({
          dataClass,
          enabled: rowsByDataClass.get(dataClass) ?? false
        })
      );
    }
  };
}

function generateUuidV7(now = new Date()) {
  const bytes = randomBytes(16);
  const timestampMs = BigInt(now.getTime());

  bytes[0] = Number((timestampMs >> 40n) & 0xffn);
  bytes[1] = Number((timestampMs >> 32n) & 0xffn);
  bytes[2] = Number((timestampMs >> 24n) & 0xffn);
  bytes[3] = Number((timestampMs >> 16n) & 0xffn);
  bytes[4] = Number((timestampMs >> 8n) & 0xffn);
  bytes[5] = Number(timestampMs & 0xffn);
  bytes[6] = (bytes[6] & 0x0f) | 0x70;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  return [
    bytes.subarray(0, 4).toString("hex"),
    bytes.subarray(4, 6).toString("hex"),
    bytes.subarray(6, 8).toString("hex"),
    bytes.subarray(8, 10).toString("hex"),
    bytes.subarray(10, 16).toString("hex")
  ].join("-");
}

function createIntegrationCredentialSecret() {
  const lookupId = randomBytes(12).toString("base64url");
  const secret = `${INTEGRATION_CREDENTIAL_PREFIX}${lookupId}.${randomBytes(32).toString("base64url")}`;

  return {
    secret,
    start: `${INTEGRATION_CREDENTIAL_PREFIX}${lookupId}`
  };
}

function parseIntegrationCredentialSecret(secret: string) {
  if (!secret.startsWith(INTEGRATION_CREDENTIAL_PREFIX)) {
    return null;
  }

  const [lookupId, token] = secret
    .slice(INTEGRATION_CREDENTIAL_PREFIX.length)
    .split(".", 2);
  if (lookupId === undefined || lookupId.length === 0) {
    return null;
  }
  if (token === undefined || token.length === 0) {
    return null;
  }

  return {
    start: `${INTEGRATION_CREDENTIAL_PREFIX}${lookupId}`
  };
}

async function hashSecret(secret: string) {
  const salt = randomBytes(16).toString("base64url");
  const derived = (await scrypt(secret, salt, 64)) as Buffer;

  return `scrypt:v1:${salt}:${derived.toString("base64url")}`;
}

async function verifySecret(secret: string, storedHash: string) {
  const [algorithm, version, salt, hash] = storedHash.split(":", 4);
  if (algorithm !== "scrypt" || version !== "v1" || !salt || !hash) {
    return false;
  }

  const expected = Buffer.from(hash, "base64url");
  const actual = (await scrypt(secret, salt, expected.length)) as Buffer;

  return (
    actual.length === expected.length && timingSafeEqual(actual, expected)
  );
}

function parseStoredScope(permissions: string | null) {
  if (permissions === null) {
    return DEFAULT_IMPORT_SCOPED_INTEGRATION_CREDENTIAL_SCOPE;
  }

  let storedPermissions: unknown;
  try {
    storedPermissions = JSON.parse(permissions);
  } catch {
    return DEFAULT_IMPORT_SCOPED_INTEGRATION_CREDENTIAL_SCOPE;
  }

  const parsed = z
    .object({ scope: IntegrationCredentialScopeSchema })
    .strict()
    .safeParse(storedPermissions);

  return parsed.success
    ? parsed.data.scope
    : DEFAULT_IMPORT_SCOPED_INTEGRATION_CREDENTIAL_SCOPE;
}

function parseStoredSource(metadata: string | null) {
  if (metadata === null) {
    return DEFAULT_INTEGRATION_CREDENTIAL_SOURCE;
  }

  let storedMetadata: unknown;
  try {
    storedMetadata = JSON.parse(metadata);
  } catch {
    return DEFAULT_INTEGRATION_CREDENTIAL_SOURCE;
  }

  const parsed = z
    .object({ source: IntegrationCredentialSourceSchema })
    .passthrough()
    .safeParse(storedMetadata);

  return parsed.success
    ? parsed.data.source
    : DEFAULT_INTEGRATION_CREDENTIAL_SOURCE;
}

function mapIntegrationCredentialMetadata(
  row: Pick<
    typeof schema.apikey.$inferSelect,
    | "createdAt"
    | "enabled"
    | "id"
    | "lastRequest"
    | "name"
    | "permissions"
    | "metadata"
    | "prefix"
    | "start"
  >
): IntegrationCredentialMetadata {
  return IntegrationCredentialMetadataSchema.parse({
    id: row.id,
    source: parseStoredSource(row.metadata),
    name: row.name,
    prefix: row.prefix,
    start: row.start,
    createdAt: row.createdAt.toISOString(),
    lastUsedAt: row.lastRequest?.toISOString() ?? null,
    revoked: !row.enabled,
    scope: parseStoredScope(row.permissions)
  });
}

function positiveIntegerOrDefault(
  value: number | null | undefined,
  fallback: number
): number {
  return value !== null &&
    value !== undefined &&
    Number.isInteger(value) &&
    value > 0
    ? value
    : fallback;
}
