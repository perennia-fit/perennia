import { createRoute, z } from "@hono/zod-openapi";
import type { ApiKey } from "@better-auth/api-key";
import { and, desc, eq, gt, isNull } from "drizzle-orm";

import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";

export const AGENT_API_KEY_CONFIG_ID = "agent";
export const AGENT_API_KEY_PREFIX = "prn_agent_";
export const DEFAULT_AGENT_API_KEY_RATE_LIMIT_MAX = 10;
export const DEFAULT_AGENT_API_KEY_RATE_LIMIT_WINDOW_MS = 24 * 60 * 60 * 1000;

export const AgentApiKeyCreateRequestSchema = z
  .object({
    name: z.string().trim().min(1).max(80).openapi({
      description: "User-visible name for the agent API key."
    })
  })
  .openapi("AgentApiKeyCreateRequest");

export const AgentApiKeyMetadataSchema = z
  .object({
    id: z.string().min(1).openapi({
      description: "Stable API key id."
    }),
    name: z.string().min(1).openapi({
      description: "User-visible API key name."
    }),
    prefix: z.string().min(1).nullable().openapi({
      description: "Public API key prefix, if present."
    }),
    start: z.string().min(1).nullable().openapi({
      description: "Starting characters used to identify the secret."
    }),
    createdAt: z.string().min(1).openapi({
      description: "ISO-8601 timestamp when the key was created."
    }),
    lastUsedAt: z.string().min(1).nullable().openapi({
      description: "ISO-8601 timestamp when this key was last authenticated."
    }),
    revoked: z.boolean().openapi({
      description: "True when the key can no longer authenticate."
    })
  })
  .openapi("AgentApiKeyMetadata");

export const AgentApiKeyCreateResponseSchema = z
  .object({
    key: AgentApiKeyMetadataSchema,
    secret: z.string().min(1).openapi({
      description: "One-time API key secret. It is never returned by list calls."
    })
  })
  .openapi("AgentApiKeyCreateResponse");

export const AgentApiKeyListResponseSchema = z
  .object({
    keys: z.array(AgentApiKeyMetadataSchema)
  })
  .openapi("AgentApiKeyListResponse");

export const AgentApiKeyRevokeResponseSchema = z
  .object({
    revoked: z.literal(true)
  })
  .openapi("AgentApiKeyRevokeResponse");

export const AgentApiKeyProtectedProbeResponseSchema = z
  .object({
    authenticated: z.literal(true),
    userId: z.string().min(1),
    keyId: z.string().min(1),
    keyName: z.string().min(1).nullable()
  })
  .openapi("AgentApiKeyProtectedProbeResponse");

export const AgentUnauthorizedResponseSchema = z
  .object({
    code: z.literal("agent_unauthorized"),
    message: z.string().min(1)
  })
  .openapi("AgentUnauthorizedResponse");

export const AgentApiKeyUnavailableResponseSchema = z
  .object({
    code: z.literal("agent_api_keys_unavailable"),
    message: z.string().min(1)
  })
  .openapi("AgentApiKeyUnavailableResponse");

export const AgentApiKeyNotFoundResponseSchema = z
  .object({
    code: z.literal("agent_api_key_not_found"),
    message: z.string().min(1)
  })
  .openapi("AgentApiKeyNotFoundResponse");

const AgentApiKeyPathParamsSchema = z.object({
  keyId: z.string().min(1).openapi({
    param: {
      name: "keyId",
      in: "path"
    },
    description: "API key id to revoke."
  })
});

export const agentApiKeyCreateRoute = createRoute({
  method: "post",
  path: "/agent/api-keys",
  operationId: "createAgentApiKey",
  tags: ["Agent API Keys"],
  summary: "Create a named agent API key.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: AgentApiKeyCreateRequestSchema
        }
      }
    }
  },
  responses: {
    201: {
      description:
        "The key was created. The secret is returned exactly once in this response.",
      content: {
        "application/json": {
          schema: AgentApiKeyCreateResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid session bearer token.",
      content: {
        "application/json": {
          schema: AgentUnauthorizedResponseSchema
        }
      }
    },
    503: {
      description: "Agent API key storage is not configured.",
      content: {
        "application/json": {
          schema: AgentApiKeyUnavailableResponseSchema
        }
      }
    }
  }
});

export const agentApiKeyListRoute = createRoute({
  method: "get",
  path: "/agent/api-keys",
  operationId: "listAgentApiKeys",
  tags: ["Agent API Keys"],
  summary: "List the caller's agent API key metadata.",
  security: [{ bearerAuth: [] }],
  responses: {
    200: {
      description: "Agent API key metadata. Secrets are never returned.",
      content: {
        "application/json": {
          schema: AgentApiKeyListResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid session bearer token.",
      content: {
        "application/json": {
          schema: AgentUnauthorizedResponseSchema
        }
      }
    },
    503: {
      description: "Agent API key storage is not configured.",
      content: {
        "application/json": {
          schema: AgentApiKeyUnavailableResponseSchema
        }
      }
    }
  }
});

export const agentApiKeyRevokeRoute = createRoute({
  method: "delete",
  path: "/agent/api-keys/{keyId}",
  operationId: "revokeAgentApiKey",
  tags: ["Agent API Keys"],
  summary: "Revoke one of the caller's agent API keys.",
  security: [{ bearerAuth: [] }],
  request: {
    params: AgentApiKeyPathParamsSchema
  },
  responses: {
    200: {
      description: "The key was revoked.",
      content: {
        "application/json": {
          schema: AgentApiKeyRevokeResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid session bearer token.",
      content: {
        "application/json": {
          schema: AgentUnauthorizedResponseSchema
        }
      }
    },
    404: {
      description: "The key does not exist for this account.",
      content: {
        "application/json": {
          schema: AgentApiKeyNotFoundResponseSchema
        }
      }
    },
    503: {
      description: "Agent API key storage is not configured.",
      content: {
        "application/json": {
          schema: AgentApiKeyUnavailableResponseSchema
        }
      }
    }
  }
});

export const agentProtectedProbeRoute = createRoute({
  method: "get",
  path: "/agent/probe",
  operationId: "getAgentProtectedProbe",
  tags: ["Agent API Keys"],
  summary: "Protected probe that proves an agent API key can authenticate.",
  security: [{ bearerAuth: [] }],
  responses: {
    200: {
      description: "The agent API key authenticated.",
      content: {
        "application/json": {
          schema: AgentApiKeyProtectedProbeResponseSchema
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
      description: "Agent API key storage is not configured.",
      content: {
        "application/json": {
          schema: AgentApiKeyUnavailableResponseSchema
        }
      }
    }
  }
});

export type AgentApiKeyMetadata = z.infer<typeof AgentApiKeyMetadataSchema>;
export type AgentSession = {
  userId: string;
};
export type AuthenticatedAgent = {
  userId: string;
  keyId: string;
  keyName: string | null;
  rateLimitEnabled?: boolean;
  rateLimitTimeWindow?: number | null;
  rateLimitMax?: number | null;
};
export type AgentApiKeyStore = {
  authenticateAgentApiKey(secret: string): Promise<AuthenticatedAgent | null>;
  createAgentApiKey(input: {
    name: string;
    userId: string;
  }): Promise<z.infer<typeof AgentApiKeyCreateResponseSchema>>;
  listAgentApiKeys(userId: string): Promise<AgentApiKeyMetadata[]>;
  revokeAgentApiKey(input: {
    keyId: string;
    userId: string;
  }): Promise<boolean>;
  verifySessionBearerToken(token: string): Promise<AgentSession | null>;
};

export type AgentApiKeyAuthApi = {
  createApiKey(input: {
    body: {
      configId: typeof AGENT_API_KEY_CONFIG_ID;
      name: string;
      prefix: typeof AGENT_API_KEY_PREFIX;
      userId: string;
    };
  }): Promise<ApiKey>;
  verifyApiKey(input: {
    body: {
      configId: typeof AGENT_API_KEY_CONFIG_ID;
      key: string;
    };
  }): Promise<
    | {
        valid: true;
        error: null;
        key: Omit<ApiKey, "key"> | null;
      }
    | {
        valid: boolean;
        error: unknown;
        key: null;
      }
  >;
};

type ApiKeyMetadataRow = Pick<
  ApiKey,
  | "createdAt"
  | "enabled"
  | "id"
  | "lastRequest"
  | "name"
  | "prefix"
  | "start"
>;

export function createDrizzleAgentApiKeyStore(
  db: ServerDatabase,
  apiKeyApi: AgentApiKeyAuthApi
): AgentApiKeyStore {
  return {
    async authenticateAgentApiKey(secret) {
      const result = await apiKeyApi.verifyApiKey({
        body: {
          configId: AGENT_API_KEY_CONFIG_ID,
          key: secret
        }
      });

      if (!result.valid || result.key === null || !result.key.enabled) {
        return null;
      }

      const users = await db
        .select({ id: schema.user.id })
        .from(schema.user)
        .where(
          and(
            eq(schema.user.id, result.key.referenceId),
            isNull(schema.user.deletionRequestedAt)
          )
        )
        .limit(1);

      if (users.length === 0) {
        return null;
      }

      return {
        userId: result.key.referenceId,
        keyId: result.key.id,
        keyName: result.key.name,
        rateLimitEnabled: result.key.rateLimitEnabled,
        rateLimitTimeWindow: result.key.rateLimitTimeWindow,
        rateLimitMax: result.key.rateLimitMax
      };
    },
    async createAgentApiKey({ name, userId }) {
      const key = await apiKeyApi.createApiKey({
        body: {
          configId: AGENT_API_KEY_CONFIG_ID,
          name,
          prefix: AGENT_API_KEY_PREFIX,
          // agent keys have full account capability, so we leave
          // Better Auth permissions/metadata unused instead of modeling scopes.
          userId
        }
      });

      return AgentApiKeyCreateResponseSchema.parse({
        key: mapApiKeyMetadata(key),
        secret: key.key
      });
    },
    async listAgentApiKeys(userId) {
      const keys = await db
        .select({
          id: schema.apikey.id,
          name: schema.apikey.name,
          prefix: schema.apikey.prefix,
          start: schema.apikey.start,
          createdAt: schema.apikey.createdAt,
          lastRequest: schema.apikey.lastRequest,
          enabled: schema.apikey.enabled
        })
        .from(schema.apikey)
        .where(
          and(
            eq(schema.apikey.configId, AGENT_API_KEY_CONFIG_ID),
            eq(schema.apikey.referenceId, userId)
          )
        )
        .orderBy(desc(schema.apikey.createdAt));

      return keys.map(mapApiKeyMetadata);
    },
    async revokeAgentApiKey({ keyId, userId }) {
      const revoked = await db
        .update(schema.apikey)
        .set({
          enabled: false,
          updatedAt: new Date()
        })
        .where(
          and(
            eq(schema.apikey.id, keyId),
            eq(schema.apikey.configId, AGENT_API_KEY_CONFIG_ID),
            eq(schema.apikey.referenceId, userId)
          )
        )
        .returning({ id: schema.apikey.id });

      return revoked.length > 0;
    },
    async verifySessionBearerToken(token) {
      const rows = await db
        .select({ userId: schema.session.userId })
        .from(schema.session)
        .innerJoin(schema.user, eq(schema.user.id, schema.session.userId))
        .where(
          and(
            eq(schema.session.token, token),
            gt(schema.session.expiresAt, new Date()),
            isNull(schema.user.deletionRequestedAt)
          )
        )
        .limit(1);

      return rows[0] ?? null;
    }
  };
}

function mapApiKeyMetadata(key: ApiKeyMetadataRow): AgentApiKeyMetadata {
  return AgentApiKeyMetadataSchema.parse({
    id: key.id,
    name: key.name,
    prefix: key.prefix,
    start: key.start,
    createdAt: key.createdAt.toISOString(),
    lastUsedAt: key.lastRequest?.toISOString() ?? null,
    revoked: !key.enabled
  });
}
