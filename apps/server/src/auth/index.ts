import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { memoryAdapter } from "better-auth/adapters/memory";
import { apiKey } from "@better-auth/api-key";
import {
  betterAuth,
  type Auth,
  type BetterAuthPlugin,
  type SocialProviders
} from "better-auth";
import { openAPI } from "better-auth/plugins";

import {
  AGENT_API_KEY_CONFIG_ID,
  AGENT_API_KEY_PREFIX,
  type AgentApiKeyAuthApi
} from "../agent-api-keys.js";
import type { RequestLogger } from "../app.js";
import type { ServerDatabase } from "../db/client.js";
import * as schema from "../db/schema.js";
import {
  buildAuthEmailMessage,
  type AuthEmailSender
} from "./email.js";

export { createEmailSenderFromEnv } from "./email.js";
export type {
  AuthEmailMessage,
  AuthEmailPurpose,
  AuthEmailSender,
  EmailDeliveryResolution
} from "./email.js";

export const AUTH_BASE_PATH = "/api/auth";
export const AUTH_DISABLED_MESSAGE =
  "Email and password auth requires an email provider or SMTP.";
export const TRUSTED_OAUTH_PROVIDERS = ["google", "apple"] as const;

export type ServerAuth = {
  apiKeyApi: AgentApiKeyAuthApi;
  basePath: string;
  emailPasswordEnabled: boolean;
  handler: Auth["handler"];
};

export type CreateServerAuthOptions = {
  db: ServerDatabase;
  baseUrl: string;
  secret: string;
  emailSender?: AuthEmailSender | null;
  emailDisabledReason?: string;
  logger?: RequestLogger;
  plugins?: BetterAuthPlugin[];
  socialProviders?: SocialProviders;
  trustedOrigins?: string[];
  trustedOAuthProviders?: string[];
};

export function createServerAuth({
  db,
  baseUrl,
  secret,
  emailSender,
  emailDisabledReason = "email_provider_unconfigured",
  logger,
  plugins,
  socialProviders,
  trustedOrigins,
  trustedOAuthProviders
}: CreateServerAuthOptions): ServerAuth {
  const emailPasswordEnabled = emailSender !== undefined && emailSender !== null;

  if (!emailPasswordEnabled) {
    logger?.info(
      { reason: emailDisabledReason },
      "email/password auth disabled"
    );
  }

  const auth = betterAuth({
    ...baseAuthOptions({
      baseUrl,
      secret,
      emailSender,
      plugins,
      socialProviders,
      trustedOrigins,
      trustedOAuthProviders
    }),
    database: drizzleAdapter(db, {
      provider: "pg",
      schema,
      camelCase: true
    })
  });

  return {
    apiKeyApi: auth.api as unknown as AgentApiKeyAuthApi,
    basePath: AUTH_BASE_PATH,
    emailPasswordEnabled,
    handler: auth.handler
  };
}

export async function createAuthOpenApiDocument() {
  const auth = betterAuth({
    ...baseAuthOptions({
      baseUrl: "http://localhost",
      secret: "contract-openapi-only-secret-at-least-thirty-two",
      emailSender: {
        async send() {}
      },
      socialProviders: {
        google: {
          clientId: "contract-google-client",
          clientSecret: "contract-google-secret"
        },
        apple: {
          clientId: "contract-apple-client",
          clientSecret: "contract-apple-secret"
        }
      },
      trustedOrigins: ["http://localhost"]
    }),
    database: memoryAdapter({})
  });
  const response = await auth.handler(
    new Request("http://localhost/api/auth/open-api/generate-schema")
  );

  if (!response.ok) {
    throw new Error(
      `Failed to generate Better Auth OpenAPI document: ${response.status}`
    );
  }

  return response.json() as Promise<Record<string, unknown>>;
}

function baseAuthOptions({
  baseUrl,
  secret,
  emailSender,
  plugins,
  socialProviders,
  trustedOrigins,
  trustedOAuthProviders
}: {
  baseUrl: string;
  secret: string;
  emailSender?: AuthEmailSender | null;
  plugins?: BetterAuthPlugin[];
  socialProviders?: SocialProviders;
  trustedOrigins?: string[];
  trustedOAuthProviders?: string[];
}) {
  const emailPasswordEnabled = emailSender !== undefined && emailSender !== null;

  return {
    appName: "Perennia",
    baseURL: baseUrl,
    basePath: AUTH_BASE_PATH,
    secret,
    socialProviders,
    trustedOrigins: trustedOrigins ?? [baseUrl],
    account: {
      accountLinking: {
        enabled: true,
        requireLocalEmailVerified: true,
        trustedProviders: trustedOAuthProviders ?? [...TRUSTED_OAUTH_PROVIDERS]
      }
    },
    emailAndPassword: {
      enabled: emailPasswordEnabled,
      requireEmailVerification: true,
      autoSignIn: false,
      sendResetPassword: emailPasswordEnabled
        ? async ({
            user,
            url,
            token
          }: {
            user: { email: string };
            url: string;
            token: string;
          }) => {
            await emailSender.send(
              buildAuthEmailMessage({
                purpose: "password-reset",
                to: user.email,
                url,
                token
              })
            );
          }
        : undefined
    },
    emailVerification: {
      sendOnSignUp: emailPasswordEnabled,
      sendOnSignIn: emailPasswordEnabled,
      autoSignInAfterVerification: false,
      sendVerificationEmail: emailPasswordEnabled
        ? async ({
            user,
            url,
            token
          }: {
            user: { email: string };
            url: string;
            token: string;
          }) => {
            await emailSender.send(
              buildAuthEmailMessage({
                purpose: "email-verification",
                to: user.email,
                url,
                token
              })
            );
          }
        : undefined
    },
    plugins: [
      openAPI(),
      apiKey({
        configId: AGENT_API_KEY_CONFIG_ID,
        defaultPrefix: AGENT_API_KEY_PREFIX,
        keyExpiration: {
          defaultExpiresIn: null,
          disableCustomExpiresTime: true
        },
        rateLimit: {
          enabled: false
        },
        requireName: true
      }),
      ...(plugins ?? [])
    ]
  };
}

export function createOAuthProvidersFromEnv(
  env: NodeJS.ProcessEnv,
  logger?: RequestLogger
): SocialProviders {
  const providers: SocialProviders = {};
  const google = readOAuthClient(env, {
    provider: "google",
    clientIdNames: ["GOOGLE_OAUTH_CLIENT_ID", "GOOGLE_CLIENT_ID"],
    clientSecretNames: [
      "GOOGLE_OAUTH_CLIENT_SECRET",
      "GOOGLE_CLIENT_SECRET"
    ],
    logger
  });
  const apple = readOAuthClient(env, {
    provider: "apple",
    clientIdNames: ["APPLE_OAUTH_CLIENT_ID", "APPLE_CLIENT_ID"],
    clientSecretNames: [
      "APPLE_OAUTH_CLIENT_SECRET",
      "APPLE_CLIENT_SECRET"
    ],
    logger
  });

  if (google !== undefined) {
    providers.google = {
      ...google,
      hd: readFirstEnv(env, [
        "GOOGLE_OAUTH_HOSTED_DOMAIN",
        "GOOGLE_HOSTED_DOMAIN",
        "GOOGLE_WORKSPACE_DOMAIN"
      ])
    };
  }

  if (apple !== undefined) {
    const audience = readCommaSeparatedEnv(env, [
      "APPLE_OAUTH_AUDIENCE",
      "APPLE_AUDIENCE"
    ]);
    providers.apple = {
      ...apple,
      appBundleIdentifier: readFirstEnv(env, [
        "APPLE_OAUTH_APP_BUNDLE_IDENTIFIER",
        "APPLE_APP_BUNDLE_IDENTIFIER",
        "IOS_BUNDLE_IDENTIFIER"
      ]),
      audience: audience.length > 0 ? audience : undefined
    };
  }

  return providers;
}

function readOAuthClient(
  env: NodeJS.ProcessEnv,
  {
    provider,
    clientIdNames,
    clientSecretNames,
    logger
  }: {
    provider: string;
    clientIdNames: string[];
    clientSecretNames: string[];
    logger?: RequestLogger;
  }
) {
  const clientId = readFirstEnv(env, clientIdNames);
  const clientSecret = readFirstEnv(env, clientSecretNames);

  if (clientId !== undefined && clientSecret !== undefined) {
    return { clientId, clientSecret };
  }

  if (clientId !== undefined || clientSecret !== undefined) {
    logger?.info(
      {
        provider,
        reason:
          clientId === undefined ? "missing_client_id" : "missing_client_secret"
      },
      "oauth provider disabled"
    );
  }

  return undefined;
}

function readFirstEnv(env: NodeJS.ProcessEnv, names: string[]) {
  for (const name of names) {
    const value = env[name];
    if (value !== undefined && value.trim().length > 0) {
      return value.trim();
    }
  }

  return undefined;
}

function readCommaSeparatedEnv(env: NodeJS.ProcessEnv, names: string[]) {
  const value = readFirstEnv(env, names);
  if (value === undefined) {
    return [];
  }

  return value
    .split(",")
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);
}
