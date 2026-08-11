import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  DEFAULT_IMPORT_SCOPED_INTEGRATION_CREDENTIAL_SCOPE,
  INTEGRATION_CREDENTIAL_ACTOR,
  INTEGRATION_CREDENTIAL_CONFIG_ID,
  INTEGRATION_CREDENTIAL_PREFIX,
  authenticateIntegrationCredentialOperation,
  createDrizzleIntegrationCredentialStore,
  isIntegrationCredentialOperationAllowed
} from "../src/integration-credentials.ts";
import {
  createApp,
  createDrizzleRateLimitBackend,
  createMigratedServerApp,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error(
    "DATABASE_URL must be set for integration credential tests."
  );
}

test("import-scoped Integration credential scope admits only import operations", () => {
  const scope = DEFAULT_IMPORT_SCOPED_INTEGRATION_CREDENTIAL_SCOPE;

  assert.equal(
    isIntegrationCredentialOperationAllowed(scope, "write_observations"),
    true
  );
  assert.equal(
    isIntegrationCredentialOperationAllowed(
      scope,
      "materialize_and_link_workouts"
    ),
    true
  );
  assert.equal(
    isIntegrationCredentialOperationAllowed(scope, "account_mutation"),
    false
  );
  assert.equal(
    isIntegrationCredentialOperationAllowed(scope, "hard_delete_or_purge"),
    false
  );
});

test("Integration credential auth rejects hard-delete before rate limiting", async () => {
  let rateLimitHits = 0;
  const result = await authenticateIntegrationCredentialOperation({
    secret: "prn_integration_secret",
    operation: "hard_delete_or_purge",
    integrationCredentialStore: {
      async authenticateIntegrationCredential() {
        return {
          actor: INTEGRATION_CREDENTIAL_ACTOR,
          userId: "user-1",
          credentialId: "credential-1",
          credentialName: "Garmin sidecar",
          source: "garmin",
          scope: DEFAULT_IMPORT_SCOPED_INTEGRATION_CREDENTIAL_SCOPE,
          rateLimitEnabled: true,
          rateLimitTimeWindow: 60 * 1000,
          rateLimitMax: 1
        };
      }
    },
    rateLimitBackend: {
      async recordHit() {
        rateLimitHits += 1;
        throw new Error("out-of-scope operations must not reach rate limit");
      }
    },
    logger: { error() {} }
  });

  assert.equal(result.status, "forbidden");
  assert.equal(rateLimitHits, 0);
});

test("Integration credential routes issue metadata and expose import profile preflight", async () => {
  const issuedAt = "2026-06-30T08:00:00.000Z";
  const credential = {
    id: "credential-1",
    source: "garmin-garmindb",
    name: "GarminDB sync",
    prefix: INTEGRATION_CREDENTIAL_PREFIX,
    start: `${INTEGRATION_CREDENTIAL_PREFIX}lookup`,
    createdAt: issuedAt,
    lastUsedAt: null,
    revoked: false,
    scope: DEFAULT_IMPORT_SCOPED_INTEGRATION_CREDENTIAL_SCOPE
  };
  const issueCalls = [];
  const revokeCalls = [];
  const app = createApp({
    logger: { info() {}, error() {} },
    syncStore: {
      async verifyBearerToken(token) {
        return token === "session-token" ? { userId: "user-1" } : null;
      }
    },
    integrationCredentialStore: {
      async issueIntegrationCredential(input) {
        issueCalls.push(input);
        return {
          credential: {
            ...credential,
            name: input.name,
            source: input.source
          },
          secret: "prn_integration_secret"
        };
      },
      async authenticateIntegrationCredential(secret) {
        if (secret !== "prn_integration_secret") {
          return null;
        }

        return {
          actor: INTEGRATION_CREDENTIAL_ACTOR,
          userId: "user-1",
          credentialId: credential.id,
          credentialName: credential.name,
          source: credential.source,
          scope: DEFAULT_IMPORT_SCOPED_INTEGRATION_CREDENTIAL_SCOPE,
          rateLimitEnabled: false,
          rateLimitTimeWindow: 60 * 1000,
          rateLimitMax: 100
        };
      },
      async listIntegrationCredentials(userId) {
        return userId === "user-1" ? [credential] : [];
      },
      async revokeIntegrationCredential(input) {
        revokeCalls.push(input);
        return input.userId === "user-1" && input.credentialId === credential.id;
      },
      async listIntegrationCredentialConsentDataClasses(input) {
        assert.deepEqual(input, {
          userId: "user-1",
          credentialId: credential.id
        });
        return [
          { dataClass: "activities", enabled: true },
          { dataClass: "heartRate", enabled: false },
          { dataClass: "gps", enabled: false },
          { dataClass: "sleepWellness", enabled: false },
          { dataClass: "bodyComposition", enabled: false }
        ];
      }
    }
  });

  const unauthorized = await app.request("/integrations/import-credentials", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      name: "GarminDB sync",
      source: "garmin-garmindb"
    })
  });
  assert.equal(unauthorized.status, 401);

  const createResponse = await app.request(
    "/integrations/import-credentials",
    {
      method: "POST",
      headers: {
        authorization: "Bearer session-token",
        "content-type": "application/json"
      },
      body: JSON.stringify({
        name: "GarminDB sync",
        source: "garmin-garmindb"
      })
    }
  );
  assert.equal(createResponse.status, 201);
  const createBody = await createResponse.json();
  assert.equal(createBody.credential.source, "garmin-garmindb");
  assert.equal(createBody.secret, "prn_integration_secret");
  assert.deepEqual(issueCalls, [
    {
      userId: "user-1",
      name: "GarminDB sync",
      source: "garmin-garmindb"
    }
  ]);

  const listResponse = await app.request("/integrations/import-credentials", {
    headers: { authorization: "Bearer session-token" }
  });
  assert.equal(listResponse.status, 200);
  const listBody = await listResponse.json();
  assert.deepEqual(listBody.credentials, [credential]);

  const profileResponse = await app.request("/integrations/import-profile", {
    headers: { authorization: "Bearer prn_integration_secret" }
  });
  assert.equal(profileResponse.status, 200);
  const profileBody = await profileResponse.json();
  assert.deepEqual(profileBody.credential, {
    id: credential.id,
    name: "GarminDB sync",
    source: "garmin-garmindb"
  });
  assert.deepEqual(profileBody.enabledDataClasses, ["activities"]);
  assert.equal(profileBody.fitImportEnabled, true);
  assert.equal(
    profileBody.manualFitImport.uploadPath,
    "/integrations/garmin/fit-import"
  );

  const revokeResponse = await app.request(
    "/integrations/import-credentials/credential-1",
    {
      method: "DELETE",
      headers: { authorization: "Bearer session-token" }
    }
  );
  assert.equal(revokeResponse.status, 200);
  assert.deepEqual(await revokeResponse.json(), { revoked: true });
  assert.deepEqual(revokeCalls, [
    {
      userId: "user-1",
      credentialId: "credential-1"
    }
  ]);
});

test(
  "Integration credentials issue once, authenticate to user scope, rate-limit, and revoke",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false,
      rateLimit: false
    });
    const store = createDrizzleIntegrationCredentialStore(
      serverApp.database.db
    );
    const userA = await createUser(serverApp, "integration-owner");
    const userB = await createUser(serverApp, "other-user");

    try {
      const issued = await store.issueIntegrationCredential({
        userId: userA.userId,
        name: "Garmin sidecar",
        rateLimitMax: 1,
        rateLimitTimeWindow: 60 * 1000
      });

      assert.equal(issued.credential.name, "Garmin sidecar");
      assert.equal(issued.credential.source, "garmin");
      assert.equal(issued.credential.revoked, false);
      assert.equal(issued.credential.scope.writeObservations, true);
      assert.match(issued.secret, /^prn_integration_/);
      assert.equal(Object.hasOwn(issued.credential, "secret"), false);

      const keyRows = await serverApp.database.sql`
        select
          "configId" as config_id,
          "referenceId" as reference_id,
          key,
          prefix,
          start,
          permissions,
          metadata,
          "rateLimitEnabled" as rate_limit_enabled,
          "rateLimitTimeWindow" as rate_limit_time_window,
          "rateLimitMax" as rate_limit_max
        from apikey
        where id = ${issued.credential.id}
      `;

      assert.equal(keyRows.length, 1);
      assert.equal(keyRows[0].config_id, INTEGRATION_CREDENTIAL_CONFIG_ID);
      assert.equal(keyRows[0].reference_id, userA.userId);
      assert.equal(keyRows[0].prefix, INTEGRATION_CREDENTIAL_PREFIX);
      assert.equal(keyRows[0].start, issued.credential.start);
      assert.notEqual(keyRows[0].key, issued.secret);
      assert.match(keyRows[0].key, /^scrypt:v1:/);
      assert.deepEqual(JSON.parse(keyRows[0].permissions), {
        scope: DEFAULT_IMPORT_SCOPED_INTEGRATION_CREDENTIAL_SCOPE
      });
      assert.deepEqual(JSON.parse(keyRows[0].metadata), {
        actor: INTEGRATION_CREDENTIAL_ACTOR,
        credentialType: "import_scoped",
        source: "garmin",
        version: 1
      });
      assert.equal(keyRows[0].rate_limit_enabled, true);
      assert.equal(keyRows[0].rate_limit_time_window, 60 * 1000);
      assert.equal(keyRows[0].rate_limit_max, 1);

      const consentRows = await serverApp.database.sql`
        select credential_id, data_class, enabled, deleted_at
        from integration_data_class_consents
        where user_id = ${userA.userId}
          and credential_id = ${issued.credential.id}
        order by data_class
      `;
      assert.deepEqual(
        consentRows.map((row) => [
          row.credential_id,
          row.data_class,
          row.enabled,
          row.deleted_at
        ]),
        [
          [issued.credential.id, "activities", false, null],
          [issued.credential.id, "bodyComposition", false, null],
          [issued.credential.id, "gps", false, null],
          [issued.credential.id, "heartRate", false, null],
          [issued.credential.id, "sleepWellness", false, null]
        ]
      );

      const listed = await store.listIntegrationCredentials(userA.userId);
      assert.equal(listed.length, 1);
      assert.equal(listed[0].id, issued.credential.id);
      assert.equal(Object.hasOwn(listed[0], "secret"), false);
      assert.deepEqual(
        await store.listIntegrationCredentials(userB.userId),
        []
      );

      const authenticated =
        await store.authenticateIntegrationCredential(issued.secret);
      assert.deepEqual(authenticated, {
        actor: INTEGRATION_CREDENTIAL_ACTOR,
        userId: userA.userId,
        credentialId: issued.credential.id,
        credentialName: "Garmin sidecar",
        source: "garmin",
        scope: DEFAULT_IMPORT_SCOPED_INTEGRATION_CREDENTIAL_SCOPE,
        rateLimitEnabled: true,
        rateLimitTimeWindow: 60 * 1000,
        rateLimitMax: 1
      });

      const forbidden = await authenticateIntegrationCredentialOperation({
        secret: issued.secret,
        operation: "account_mutation",
        integrationCredentialStore: store,
        rateLimitBackend: createDrizzleRateLimitBackend(serverApp.database.db),
        logger: { error() {} }
      });
      assert.equal(forbidden.status, "forbidden");
      assert.equal(forbidden.credential.userId, userA.userId);

      const rateLimitBackend = createDrizzleRateLimitBackend(
        serverApp.database.db
      );
      const firstImportAuth = await authenticateIntegrationCredentialOperation({
        secret: issued.secret,
        operation: "write_observations",
        integrationCredentialStore: store,
        rateLimitBackend,
        logger: { error() {} }
      });
      assert.equal(firstImportAuth.status, "authenticated");
      assert.equal(firstImportAuth.credential.userId, userA.userId);

      const secondImportAuth = await authenticateIntegrationCredentialOperation({
        secret: issued.secret,
        operation: "write_observations",
        integrationCredentialStore: store,
        rateLimitBackend,
        logger: { error() {} }
      });
      assert.equal(secondImportAuth.status, "rate_limited");

      const revokedByOtherUser = await store.revokeIntegrationCredential({
        userId: userB.userId,
        credentialId: issued.credential.id
      });
      assert.equal(revokedByOtherUser, false);
      assert.notEqual(
        await store.authenticateIntegrationCredential(issued.secret),
        null
      );

      const revoked = await store.revokeIntegrationCredential({
        userId: userA.userId,
        credentialId: issued.credential.id
      });
      assert.equal(revoked, true);
      assert.equal(
        await store.authenticateIntegrationCredential(issued.secret),
        null
      );

      const revokedAuth = await authenticateIntegrationCredentialOperation({
        secret: issued.secret,
        operation: "write_observations",
        integrationCredentialStore: store,
        rateLimitBackend,
        logger: { error() {} }
      });
      assert.equal(revokedAuth.status, "unauthorized");
    } finally {
      await serverApp.database.close();
    }
  }
);

async function createUser(serverApp, label) {
  const userId = `user-${label}-${randomUUID()}`;
  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: `Integration Test ${label}`,
    email: `${userId}@example.com`,
    emailVerified: true
  });

  return { userId };
}
