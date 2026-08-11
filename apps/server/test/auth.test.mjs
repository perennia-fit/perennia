import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { genericOAuth } from "better-auth/plugins";

import { createOAuthProvidersFromEnv } from "../src/auth/index.ts";
import { createApp, createMigratedServerApp } from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;
const authSecret = "test-secret-at-least-thirty-two-characters";
const authBaseUrl = "http://localhost";

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

test("oauth provider credentials are sourced from environment configuration", () => {
  const providers = createOAuthProvidersFromEnv({
    GOOGLE_OAUTH_CLIENT_ID: "google-client",
    GOOGLE_OAUTH_CLIENT_SECRET: "google-secret",
    GOOGLE_OAUTH_HOSTED_DOMAIN: "example.com",
    APPLE_OAUTH_CLIENT_ID: "apple-client",
    APPLE_OAUTH_CLIENT_SECRET: "apple-secret",
    APPLE_OAUTH_APP_BUNDLE_IDENTIFIER: "com.openworkoutlogger.app",
    APPLE_OAUTH_AUDIENCE: "web.openworkoutlogger.app,com.openworkoutlogger.app"
  });

  assert.equal(providers.google?.clientId, "google-client");
  assert.equal(providers.google?.clientSecret, "google-secret");
  assert.equal(providers.google?.hd, "example.com");
  assert.equal(providers.apple?.clientId, "apple-client");
  assert.equal(providers.apple?.clientSecret, "apple-secret");
  assert.equal(
    providers.apple?.appBundleIdentifier,
    "com.openworkoutlogger.app"
  );
  assert.deepEqual(providers.apple?.audience, [
    "web.openworkoutlogger.app",
    "com.openworkoutlogger.app"
  ]);
});

test("email verification callback renders success and failure pages", async () => {
  const app = createApp({ logger: { info() {}, error() {} } });

  const successResponse = await app.request("/auth/verified");
  assert.equal(successResponse.status, 200);
  const successHtml = await successResponse.text();
  assert.match(successHtml, /Email Verified/);
  assert.match(successHtml, /return to Perennia and sign in/);

  const failureResponse = await app.request(
    "/auth/verified?error=expired-token"
  );
  assert.equal(failureResponse.status, 400);
  const failureHtml = await failureResponse.text();
  assert.match(failureHtml, /Verification Link Expired/);
  assert.match(failureHtml, /request a new verification email/);
  assert.match(failureHtml, /expired-token/);
});

test(
  "email and password auth is disabled clearly when email delivery is unconfigured",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const logEvents = [];
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: {
        info(payload, message) {
          logEvents.push({ payload, message });
        },
        error() {}
      },
      auth: {
        baseUrl: authBaseUrl,
        secret: authSecret
      }
    });

    try {
      assert.ok(
        logEvents.some(
          (event) => event.message === "email/password auth disabled"
        )
      );

      const response = await serverApp.app.request("/api/auth/sign-up/email", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          email: "disabled@example.com",
          password: "correct horse battery staple",
          name: "Disabled User"
        })
      });

      assert.equal(response.status, 503);
      assert.deepEqual(await response.json(), {
        code: "email_password_disabled",
        message: "Email and password auth requires an email provider or SMTP."
      });
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "email and password auth verifies email, signs in, and resets password",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const emails = [];
    const emailSender = {
      async send(message) {
        emails.push(message);
      }
    };
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: {
        baseUrl: authBaseUrl,
        secret: authSecret,
        emailSender
      }
    });
    const email = `user-${Date.now()}@example.com`;
    const verificationCallbackUrl = `${authBaseUrl}/auth/verified`;

    try {
      const signUpResponse = await postJson(
        serverApp.app,
        "/api/auth/sign-up/email",
        {
          email,
          password: "correct horse battery staple",
          name: "Lifecycle User",
          callbackURL: verificationCallbackUrl
        }
      );

      assert.equal(signUpResponse.status, 200);
      assert.equal(emails.length, 1);
      assert.equal(emails[0].to, email);
      assert.equal(emails[0].purpose, "email-verification");
      assertVerificationCallbackUrl(emails[0].url, verificationCallbackUrl);

      const accountRows = await serverApp.database.sql`
        select account.password
        from account
        inner join "user" on "user".id = account."userId"
        where "user".email = ${email}
      `;
      assert.equal(accountRows.length, 1);
      assert.equal(typeof accountRows[0].password, "string");
      assert.notEqual(accountRows[0].password, "");

      const signInBeforeVerify = await postJson(
        serverApp.app,
        "/api/auth/sign-in/email",
        {
          email,
          password: "correct horse battery staple",
          callbackURL: verificationCallbackUrl
        }
      );

      assert.notEqual(signInBeforeVerify.status, 200);

      const resendResponse = await postJson(
        serverApp.app,
        "/api/auth/send-verification-email",
        {
          email,
          callbackURL: verificationCallbackUrl
        }
      );
      assert.equal(resendResponse.status, 200);
      const resendEmail = emails.findLast(
        (message) => message.purpose === "email-verification"
      );
      assert.notEqual(resendEmail, undefined);
      assert.equal(resendEmail.to, email);
      assertVerificationCallbackUrl(resendEmail.url, verificationCallbackUrl);

      const verifyResponse = await serverApp.app.request(
        `/api/auth/verify-email?token=${encodeURIComponent(
          readTokenFromUrl(resendEmail.url)
        )}`
      );

      assert.equal(verifyResponse.status, 200);
      const verifiedUsers = await serverApp.database.sql`
        select "emailVerified"
        from "user"
        where email = ${email}
      `;
      assert.equal(verifiedUsers[0].emailVerified, true);

      const signInResponse = await postJson(
        serverApp.app,
        "/api/auth/sign-in/email",
        {
          email,
          password: "correct horse battery staple"
        }
      );

      assert.equal(signInResponse.status, 200);
      assert.ok(signInResponse.headers.get("set-cookie")?.includes("session"));
      const signInBody = await signInResponse.json();
      assert.equal(typeof signInBody.token, "string");
      assert.notEqual(signInBody.token, "");

      const signOutResponse = await serverApp.app.request("/api/auth/sign-out", {
        method: "POST",
        headers: {
          authorization: `Bearer ${signInBody.token}`
        }
      });
      assert.equal(signOutResponse.status, 200);
      assert.deepEqual(await signOutResponse.json(), { success: true });

      const resetRequestResponse = await postJson(
        serverApp.app,
        "/api/auth/request-password-reset",
        {
          email,
          redirectTo: "http://localhost/reset-password"
        }
      );

      assert.equal(resetRequestResponse.status, 200);
      const resetEmail = emails.findLast(
        (message) => message.purpose === "password-reset"
      );
      assert.notEqual(resetEmail, undefined);
      assert.equal(resetEmail.to, email);

      const resetToken = readTokenFromUrl(resetEmail.url);
      const resetResponse = await postJson(serverApp.app, "/api/auth/reset-password", {
        token: resetToken,
        newPassword: "new correct horse battery staple"
      });

      assert.equal(resetResponse.status, 200);

      const oldPasswordResponse = await postJson(
        serverApp.app,
        "/api/auth/sign-in/email",
        {
          email,
          password: "correct horse battery staple"
        }
      );
      assert.notEqual(oldPasswordResponse.status, 200);

      const newPasswordResponse = await postJson(
        serverApp.app,
        "/api/auth/sign-in/email",
        {
          email,
          password: "new correct horse battery staple"
        }
      );
      assert.equal(newPasswordResponse.status, 200);
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "google and apple social sign-in produce authenticated sessions",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: {
        baseUrl: authBaseUrl,
        secret: authSecret,
        emailSender: null,
        socialProviders: createTestSocialProviders()
      }
    });

    try {
      for (const provider of ["google", "apple"]) {
        const email = uniqueEmail(provider);
        const response = await postJson(serverApp.app, "/api/auth/sign-in/social", {
          provider,
          idToken: {
            token: `${provider}:${email}`,
            accessToken: `${provider}-access-token`
          }
        });

        assert.equal(response.status, 200);
        assert.ok(response.headers.get("set-cookie")?.includes("session"));
        const body = await response.json();
        assert.equal(body.redirect, false);
        assert.equal(body.user.email, email);

        const accountRows = await serverApp.database.sql`
          select account."providerId", account."userId"
          from account
          inner join "user" on "user".id = account."userId"
          where "user".email = ${email}
        `;
        assert.equal(accountRows.length, 1);
        assert.equal(accountRows[0].providerId, provider);
      }
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "trusted oauth sign-in auto-links when the existing email is verified",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const emails = [];
    const oauthProfiles = new Map();
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: {
        baseUrl: authBaseUrl,
        secret: authSecret,
        emailSender: {
          async send(message) {
            emails.push(message);
          }
        },
        plugins: [createTestOAuthPlugin(oauthProfiles)],
        trustedOAuthProviders: ["google"]
      }
    });
    const email = uniqueEmail("verified-oauth");

    try {
      await createEmailUser(serverApp.app, emails, {
        email,
        verified: true
      });

      oauthProfiles.set("verified-code", {
        id: "google-verified-subject",
        email,
        name: "Verified OAuth User",
        emailVerified: true
      });

      const callbackResponse = await completeOAuthSignIn(
        serverApp.app,
        "verified-code"
      );

      assert.equal(callbackResponse.status, 302);
      assert.equal(
        callbackResponse.headers.get("location"),
        "http://localhost/signed-in"
      );
      assert.ok(callbackResponse.headers.get("set-cookie")?.includes("session"));

      const accountRows = await serverApp.database.sql`
        select account."providerId", account."accountId", account."userId"
        from account
        inner join "user" on "user".id = account."userId"
        where "user".email = ${email}
        order by account."providerId"
      `;

      assert.deepEqual(
        accountRows.map((row) => row.providerId),
        ["credential", "google"]
      );
      assert.equal(accountRows[0].userId, accountRows[1].userId);
      assert.equal(accountRows[1].accountId, "google-verified-subject");
    } finally {
      await serverApp.database.close();
    }
  }
);

test(
  "trusted oauth sign-in prompts to link when the existing email is unverified",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const emails = [];
    const oauthProfiles = new Map();
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: {
        baseUrl: authBaseUrl,
        secret: authSecret,
        emailSender: {
          async send(message) {
            emails.push(message);
          }
        },
        plugins: [createTestOAuthPlugin(oauthProfiles)],
        trustedOAuthProviders: ["google"]
      }
    });
    const email = uniqueEmail("unverified-oauth");

    try {
      await createEmailUser(serverApp.app, emails, {
        email,
        verified: false
      });

      oauthProfiles.set("unverified-code", {
        id: "google-unverified-subject",
        email,
        name: "Unverified OAuth User",
        emailVerified: true
      });

      const callbackResponse = await completeOAuthSignIn(
        serverApp.app,
        "unverified-code"
      );

      assert.equal(callbackResponse.status, 302);
      assert.match(
        callbackResponse.headers.get("location") ?? "",
        /^http:\/\/localhost\/auth-error\?error=account_not_linked$/
      );

      const accountRows = await serverApp.database.sql`
        select account."providerId"
        from account
        inner join "user" on "user".id = account."userId"
        where "user".email = ${email}
        order by account."providerId"
      `;

      assert.deepEqual(
        accountRows.map((row) => row.providerId),
        ["credential"]
      );
    } finally {
      await serverApp.database.close();
    }
  }
);

async function postJson(app, path, body) {
  return app.request(path, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body)
  });
}

function readTokenFromUrl(url) {
  const parsedUrl = new URL(url);
  const token =
    parsedUrl.searchParams.get("token") ??
    parsedUrl.pathname.split("/").filter(Boolean).at(-1);
  assert.equal(typeof token, "string");
  assert.notEqual(token, "");
  return token;
}

function assertVerificationCallbackUrl(url, expectedCallbackUrl) {
  const parsedUrl = new URL(url);
  assert.equal(parsedUrl.searchParams.get("callbackURL"), expectedCallbackUrl);
}

async function createEmailUser(app, emails, { email, verified }) {
  const signUpResponse = await postJson(app, "/api/auth/sign-up/email", {
    email,
    password: "correct horse battery staple",
    name: "OAuth Link User"
  });

  assert.equal(signUpResponse.status, 200);
  const verificationEmail = emails.findLast(
    (message) => message.to === email && message.purpose === "email-verification"
  );
  assert.notEqual(verificationEmail, undefined);

  if (!verified) {
    return;
  }

  const verificationToken = readTokenFromUrl(verificationEmail.url);
  const verifyResponse = await app.request(
    `/api/auth/verify-email?token=${encodeURIComponent(verificationToken)}`
  );
  assert.equal(verifyResponse.status, 200);
}

function createTestOAuthPlugin(oauthProfiles) {
  return genericOAuth({
    config: [
      {
        providerId: "google",
        clientId: "test-google-client",
        clientSecret: "test-google-secret",
        authorizationUrl: "https://oauth.test/authorize",
        tokenUrl: "https://oauth.test/token",
        scopes: ["email", "profile"],
        async getToken({ code }) {
          return {
            accessToken: code,
            scopes: ["email", "profile"]
          };
        },
        async getUserInfo(tokens) {
          return oauthProfiles.get(tokens.accessToken) ?? null;
        }
      }
    ]
  });
}

function createTestSocialProviders() {
  return {
    google: {
      clientId: "test-google-client",
      clientSecret: "test-google-secret",
      async verifyIdToken(token) {
        return token.startsWith("google:");
      },
      async getUserInfo(tokens) {
        const email = tokens.idToken.slice("google:".length);
        return {
          user: {
            id: `google-${email}`,
            email,
            name: "Google User",
            emailVerified: true
          },
          data: {}
        };
      }
    },
    apple: {
      clientId: "test-apple-client",
      clientSecret: "test-apple-secret",
      async verifyIdToken(token) {
        return token.startsWith("apple:");
      },
      async getUserInfo(tokens) {
        const email = tokens.idToken.slice("apple:".length);
        return {
          user: {
            id: `apple-${email}`,
            email,
            name: "Apple User",
            emailVerified: true
          },
          data: {}
        };
      }
    }
  };
}

async function completeOAuthSignIn(app, code) {
  const signInResponse = await postJson(app, "/api/auth/sign-in/oauth2", {
    providerId: "google",
    callbackURL: "http://localhost/signed-in",
    errorCallbackURL: "http://localhost/auth-error",
    disableRedirect: true
  });

  assert.equal(signInResponse.status, 200);
  const signInBody = await signInResponse.json();
  const authorizationUrl = new URL(signInBody.url);
  const state = authorizationUrl.searchParams.get("state");
  assert.equal(typeof state, "string");
  assert.notEqual(state, "");

  return app.request(
    `/api/auth/oauth2/callback/google?code=${encodeURIComponent(
      code
    )}&state=${encodeURIComponent(state)}`,
    {
      headers: {
        cookie: readCookieHeader(signInResponse)
      }
    }
  );
}

function readCookieHeader(response) {
  const setCookie = response.headers.get("set-cookie");
  assert.equal(typeof setCookie, "string");

  return setCookie
    .split(/,(?=\s*[^;,=]+=[^;,]+)/)
    .map((cookie) => cookie.split(";")[0])
    .join("; ");
}

function uniqueEmail(prefix) {
  return `${prefix}-${randomUUID()}@example.com`;
}
