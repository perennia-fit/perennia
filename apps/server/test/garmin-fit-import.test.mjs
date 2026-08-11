import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";
import { and, eq, inArray } from "drizzle-orm";

import {
  CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS,
  createDrizzleIntegrationCredentialStore,
  createMigratedServerApp,
  parseGarminFitActivityFile,
  schema,
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;
const timezone = "Australia/Brisbane";
const startedAt = "2026-06-23T20:00:00.000Z";
const firstRecordAt = "2026-06-23T20:00:10.000Z";
const secondRecordAt = "2026-06-23T20:00:20.000Z";

test("Garmin FIT activity file maps set messages and record streams to canonical import", () => {
  const canonical = parseGarminFitActivityFile(garminStrengthFitFixture(), {
    timezone,
  });

  assert.equal(canonical.activities.length, 1);
  assert.equal(canonical.metricReadings.length, 0);
  const [activity] = canonical.activities;
  assert.equal(activity.source, "garmin");
  assert.equal(activity.externalId, `fit:123456789:${startedAt}`);
  assert.equal(activity.startedAt, startedAt);
  assert.equal(activity.endedAt, "2026-06-23T20:45:00.000Z");
  assert.equal(activity.timezone, timezone);
  assert.equal(activity.activityType, "strength_training");
  assert.deepEqual(activity.summary, {
    distance: { value: 0, unit: "meter" },
    duration: { value: 2700, unit: "second" },
  });
  assert.deepEqual(
    activity.summaryMetrics.map((metric) => [
      metric.metricKey,
      metric.externalId,
      metric.value,
    ]),
    [
      [
        "averageHeartRate",
        `fit:123456789:${startedAt}:summary:averageHeartRate`,
        { value: 132, unit: "beatsPerMinute" },
      ],
      [
        "maxHeartRate",
        `fit:123456789:${startedAt}:summary:maxHeartRate`,
        { value: 166, unit: "beatsPerMinute" },
      ],
      [
        "activeKilocalories",
        `fit:123456789:${startedAt}:summary:activeKilocalories`,
        { value: 410, unit: "kilocalorie" },
      ],
      [
        "averageCadence",
        `fit:123456789:${startedAt}:summary:averageCadence`,
        { value: 84, unit: "revolutionsPerMinute" },
      ],
      [
        "maxCadence",
        `fit:123456789:${startedAt}:summary:maxCadence`,
        { value: 102, unit: "revolutionsPerMinute" },
      ],
    ],
  );
  assert.deepEqual(activity.sets, [
    {
      source: "garmin",
      externalId: `fit:123456789:${startedAt}:set:1`,
      timezone,
      performedAt: "2026-06-23T20:10:00.000Z",
      dimensions: {
        load: { value: 100, unit: "kilogram" },
        reps: { value: 5, unit: "repetition" },
      },
    },
    {
      source: "garmin",
      externalId: `fit:123456789:${startedAt}:set:2`,
      timezone,
      performedAt: "2026-06-23T20:15:00.000Z",
      dimensions: {
        load: { value: 351, unit: "kilogram" },
        reps: { value: 3, unit: "repetition" },
      },
    },
    {
      source: "garmin",
      externalId: `fit:123456789:${startedAt}:set:3`,
      timezone,
      performedAt: "2026-06-23T20:20:00.000Z",
      dimensions: {
        load: { value: 1001, unit: "kilogram" },
        reps: { value: 1, unit: "repetition" },
      },
    },
  ]);

  assert.deepEqual(
    canonical.series.map((series) => [
      series.type,
      series.externalId,
      series.baseTime,
      series.samples,
    ]),
    [
      [
        "heartRate",
        `fit:123456789:${startedAt}:series:heartRate`,
        firstRecordAt,
        [
          { offsetSeconds: 0, value: { value: 130, unit: "beatsPerMinute" } },
          { offsetSeconds: 10, value: { value: 136, unit: "beatsPerMinute" } },
        ],
      ],
      [
        "location",
        `fit:123456789:${startedAt}:series:location`,
        firstRecordAt,
        [
          {
            offsetSeconds: 0,
            value: {
              latitude: { value: -27.4698, unit: "degree" },
              longitude: { value: 153.0251, unit: "degree" },
            },
          },
          {
            offsetSeconds: 10,
            value: {
              latitude: { value: -27.47, unit: "degree" },
              longitude: { value: 153.0255, unit: "degree" },
            },
          },
        ],
      ],
      [
        "cadence",
        `fit:123456789:${startedAt}:series:cadence`,
        firstRecordAt,
        [
          {
            offsetSeconds: 0,
            value: { value: 82, unit: "revolutionsPerMinute" },
          },
          {
            offsetSeconds: 10,
            value: { value: 86, unit: "revolutionsPerMinute" },
          },
        ],
      ],
    ],
  );
});

test("Garmin FIT activity file parser rejects malformed binary input cleanly", () => {
  assert.throws(
    () => parseGarminFitActivityFile(Buffer.alloc(13)),
    /FIT file is too small to contain a header/,
  );
  assert.throws(
    () => parseGarminFitActivityFile(fitFileWithData(Buffer.alloc(0), "NOPE")),
    /Input is not a FIT file/,
  );
  assert.throws(
    () =>
      parseGarminFitActivityFile(
        fitHeader({ declaredDataSize: 4, actualData: Buffer.alloc(1) }),
      ),
    /FIT data section is truncated/,
  );
  assert.throws(
    () => parseGarminFitActivityFile(fitFileWithData(Buffer.from([0x40]))),
    /FIT file ended while reading a record/,
  );
  assert.throws(
    () =>
      parseGarminFitActivityFile(fitFileWithData(unsupportedBaseTypeData())),
    /Unsupported FIT base type/,
  );
});

test(
  "Garmin FIT upload endpoint preflights consent profile and ingests FIT bytes",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false,
      rateLimit: false,
    });
    const credentialStore = createDrizzleIntegrationCredentialStore(
      serverApp.database.db,
    );
    const userId = await createUser(serverApp);

    try {
      const issued = await credentialStore.issueIntegrationCredential({
        userId,
        name: "GarminDB sync",
        source: "garmin-garmindb",
      });

      const disabledProfile = await serverApp.app.request(
        "/integrations/import-profile",
        {
          headers: { authorization: `Bearer ${issued.secret}` },
        },
      );
      assert.equal(disabledProfile.status, 200);
      const disabledProfileBody = await disabledProfile.json();
      assert.equal(disabledProfileBody.fitImportEnabled, false);
      assert.deepEqual(disabledProfileBody.enabledDataClasses, []);

      await enableIntegrationConsents(serverApp, {
        userId,
        credentialId: issued.credential.id,
        dataClasses: ["activities", "heartRate", "gps"],
      });

      const enabledProfile = await serverApp.app.request(
        "/integrations/import-profile",
        {
          headers: { authorization: `Bearer ${issued.secret}` },
        },
      );
      assert.equal(enabledProfile.status, 200);
      const enabledProfileBody = await enabledProfile.json();
      assert.equal(enabledProfileBody.fitImportEnabled, true);
      assert.deepEqual(enabledProfileBody.enabledDataClasses, [
        "activities",
        "heartRate",
        "gps",
      ]);

      const idempotencyKey = `garmin-fit-upload-${randomUUID()}`;
      const importResponse = await postGarminFitImport(
        serverApp.app,
        issued.secret,
        {
          idempotencyKey,
          timezone,
          file: garminStrengthFitFixture(),
        },
      );
      if (importResponse.status !== 200) {
        assert.fail(
          `expected FIT import to return 200, got ${importResponse.status}: ${await importResponse.text()}`,
        );
      }
      const importBody = await importResponse.json();
      assert.equal(importBody.accepted, true);
      assert.equal(importBody.duplicate, false);
      assert.deepEqual(
        importBody.activities.map((activity) => activity.status),
        ["created"],
      );
      assert.equal(importBody.materializedWorkouts.length, 1);
      assert.equal(importBody.seriesAccepted, 3);

      const duplicateResponse = await postGarminFitImport(
        serverApp.app,
        issued.secret,
        {
          idempotencyKey,
          timezone,
          file: garminStrengthFitFixture(),
        },
      );
      assert.equal(duplicateResponse.status, 200);
      const duplicateBody = await duplicateResponse.json();
      assert.equal(duplicateBody.duplicate, true);

      const activityRows = await serverApp.database.sql`
        select source, external_id
        from external_activities
        where user_id = ${userId}
      `;
      assert.deepEqual(
        activityRows.map((row) => [row.source, row.external_id]),
        [["garmin", `fit:123456789:${startedAt}`]],
      );
    } finally {
      await serverApp.database.close();
    }
  },
);

test(
  "Garmin FIT upload endpoint drops activities when Activities consent is off",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false,
      rateLimit: false,
    });
    const credentialStore = createDrizzleIntegrationCredentialStore(
      serverApp.database.db,
    );
    const userId = await createUser(serverApp);

    try {
      const issued = await credentialStore.issueIntegrationCredential({
        userId,
        name: "GarminDB sync",
        source: "garmin-garmindb",
      });

      const response = await postGarminFitImport(serverApp.app, issued.secret, {
        idempotencyKey: `garmin-fit-no-activity-consent-${randomUUID()}`,
        timezone,
        file: garminStrengthFitFixture(),
      });
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.accepted, true);
      assert.equal(body.duplicate, false);
      assert.equal(body.activities.length, 0);
      assert.equal(body.materializedWorkouts.length, 0);
      assert.ok(
        body.reviewFlags.some(
          (flag) =>
            flag.rule === "activity_data_not_consented" &&
            flag.field === "activities[0]",
        ),
      );

      const activityRows = await serverApp.database.sql`
        select id
        from external_activities
        where user_id = ${userId}
      `;
      assert.equal(activityRows.length, 0);
      const setRows = await serverApp.database.sql`
        select id
        from logged_sets
        where user_id = ${userId}
      `;
      assert.equal(setRows.length, 0);
    } finally {
      await serverApp.database.close();
    }
  },
);

test(
  "Garmin FIT session upload requires an own credential id and stays tenant-scoped",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false,
      rateLimit: false,
    });
    const credentialStore = createDrizzleIntegrationCredentialStore(
      serverApp.database.db,
    );

    try {
      const userA = await createSignedInUser(serverApp);
      const userB = await createSignedInUser(serverApp);
      const userACredential = await credentialStore.issueIntegrationCredential({
        userId: userA.userId,
        name: "User A GarminDB sync",
        source: "garmin-garmindb",
      });
      const userBCredential = await credentialStore.issueIntegrationCredential({
        userId: userB.userId,
        name: "User B GarminDB sync",
        source: "garmin-garmindb",
      });

      await enableIntegrationConsents(serverApp, {
        userId: userB.userId,
        credentialId: userBCredential.credential.id,
        dataClasses: ["activities"],
      });

      const missingCredentialResponse = await postGarminFitImport(
        serverApp.app,
        userA.sessionToken,
        {
          idempotencyKey: `garmin-fit-missing-credential-${randomUUID()}`,
          timezone,
          file: garminStrengthFitFixture(),
        },
      );
      assert.equal(missingCredentialResponse.status, 400);
      assert.match(
        (await missingCredentialResponse.json()).message,
        /requires a credentialId/,
      );

      const crossTenantResponse = await postGarminFitImport(
        serverApp.app,
        userA.sessionToken,
        {
          idempotencyKey: `garmin-fit-cross-tenant-${randomUUID()}`,
          timezone,
          credentialId: userBCredential.credential.id,
          file: garminStrengthFitFixture(),
        },
      );
      assert.equal(crossTenantResponse.status, 200);
      const crossTenantBody = await crossTenantResponse.json();
      assert.equal(crossTenantBody.activities.length, 0);
      assert.equal(crossTenantBody.materializedWorkouts.length, 0);
      assert.ok(
        crossTenantBody.reviewFlags.some(
          (flag) => flag.rule === "activity_data_not_consented",
        ),
      );
      assert.deepEqual(
        await countImportedRowsByUser(serverApp, [userA.userId, userB.userId]),
        {
          [userA.userId]: { externalActivities: 0, loggedSets: 0 },
          [userB.userId]: { externalActivities: 0, loggedSets: 0 },
        },
      );

      await enableIntegrationConsents(serverApp, {
        userId: userA.userId,
        credentialId: userACredential.credential.id,
        dataClasses: ["activities"],
      });

      const ownCredentialResponse = await postGarminFitImport(
        serverApp.app,
        userA.sessionToken,
        {
          idempotencyKey: `garmin-fit-session-happy-${randomUUID()}`,
          timezone,
          credentialId: userACredential.credential.id,
          file: garminStrengthFitFixture(),
        },
      );
      assert.equal(ownCredentialResponse.status, 200);
      const ownCredentialBody = await ownCredentialResponse.json();
      assert.deepEqual(
        ownCredentialBody.activities.map((activity) => activity.status),
        ["created"],
      );
      assert.equal(ownCredentialBody.materializedWorkouts.length, 1);
      assert.deepEqual(
        await countImportedRowsByUser(serverApp, [userA.userId, userB.userId]),
        {
          [userA.userId]: { externalActivities: 1, loggedSets: 2 },
          [userB.userId]: { externalActivities: 0, loggedSets: 0 },
        },
      );
    } finally {
      await serverApp.database.close();
    }
  },
);

test(
  "Garmin FIT canonical output materializes through the shared import pipeline and dedups on re-import",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} },
      auth: false,
    });
    const credentialStore = createDrizzleIntegrationCredentialStore(
      serverApp.database.db,
    );
    const userId = await createUser(serverApp);

    try {
      const issued = await credentialStore.issueIntegrationCredential({
        userId,
        name: "Manual FIT import",
      });
      await enableIntegrationConsents(serverApp, {
        userId,
        credentialId: issued.credential.id,
        dataClasses: ["activities", "heartRate", "gps"],
      });
      const canonical = parseGarminFitActivityFile(garminStrengthFitFixture(), {
        timezone,
      });
      const firstIdempotencyKey = `fit-import-${randomUUID()}`;
      const firstResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        {
          idempotencyKey: firstIdempotencyKey,
          consentedDataClasses: ["activities", "heartRate", "gps"],
          ...canonical,
        },
      );

      assert.equal(firstResponse.status, 200);
      const firstBody = await firstResponse.json();
      assert.equal(firstBody.accepted, true);
      assert.equal(firstBody.duplicate, false);
      assert.deepEqual(
        firstBody.activities.map((activity) => activity.status),
        ["created"],
      );
      assert.equal(firstBody.materializedWorkouts.length, 1);
      assert.equal(
        firstBody.materializedWorkouts[0].exerciseId,
        CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.strengthTraining,
      );
      assert.equal(firstBody.materializedWorkouts[0].setIds.length, 2);
      assert.equal(firstBody.seriesAccepted, 3);
      assert.equal(
        firstBody.reviewFlags.some(
          (flag) =>
            flag.severity === "error" &&
            flag.rule === "load_max_kilograms" &&
            flag.field === "activities[0].sets[2].dimensions.load.value",
        ),
        true,
      );

      const activityRows = await serverApp.database.sql`
        select id, source, external_id, activity_type, mapped_exercise_id, sets_json
        from external_activities
        where user_id = ${userId}
      `;
      assert.equal(activityRows.length, 1);
      assert.equal(activityRows[0].source, "garmin");
      assert.equal(activityRows[0].external_id, `fit:123456789:${startedAt}`);
      assert.equal(activityRows[0].activity_type, "strength_training");
      assert.equal(
        activityRows[0].mapped_exercise_id,
        CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.strengthTraining,
      );
      assert.equal(activityRows[0].sets_json.length, 3);

      const setRows = await serverApp.database.sql`
        select id, payload
        from logged_sets
        where user_id = ${userId}
        order by payload->>'position'
      `;
      assert.equal(setRows.length, 2);
      assert.equal(setRows[0].payload.provenance, "integration");
      assert.equal(setRows[0].payload.source, "garmin");
      assert.equal(
        setRows[0].payload.external_set_external_id,
        `fit:123456789:${startedAt}:set:1`,
      );
      assert.equal(setRows[0].payload.values.load.entered, "100");
      assert.equal(setRows[0].payload.values.reps.entered, "5");
      assert.equal(
        setRows[1].payload.external_set_external_id,
        `fit:123456789:${startedAt}:set:2`,
      );
      assert.deepEqual(
        setRows[1].payload.review_flags.map((flag) => flag.rule),
        ["added_load_improbable"],
      );

      const seriesRows = await serverApp.database.sql`
        select series_type, sample_count, external_activity_id
        from monitoring_series
        where user_id = ${userId}
        order by series_type
      `;
      assert.deepEqual(
        seriesRows.map((row) => [
          row.series_type,
          row.sample_count,
          row.external_activity_id,
        ]),
        [
          ["cadence", 2, activityRows[0].id],
          ["heartRate", 2, activityRows[0].id],
          ["location", 2, activityRows[0].id],
        ],
      );

      const logRows = await serverApp.database.sql`
        select batch_id, entity_table
        from activity_log
        where user_id = ${userId} and batch_id = ${firstIdempotencyKey}
        order by entity_table, entity_id
      `;
      assert.equal(new Set(logRows.map((row) => row.batch_id)).size, 1);
      assert.deepEqual(logRows.map((row) => row.entity_table).sort(), [
        "activity_links",
        "external_activities",
        "logged_sets",
        "logged_sets",
        "metric_readings",
        "metric_readings",
        "metric_readings",
        "metric_readings",
        "metric_readings",
        "monitoring_series",
        "monitoring_series",
        "monitoring_series",
      ]);

      const secondResponse = await postCanonicalImport(
        serverApp.app,
        issued.secret,
        {
          idempotencyKey: `fit-import-refresh-${randomUUID()}`,
          consentedDataClasses: ["activities", "heartRate", "gps"],
          ...canonical,
        },
      );
      assert.equal(secondResponse.status, 200);
      const secondBody = await secondResponse.json();
      assert.deepEqual(
        secondBody.activities.map((activity) => activity.status),
        ["refreshed"],
      );
      assert.deepEqual(
        secondBody.materializedWorkouts.map((workout) => workout.status),
        ["existing"],
      );

      const reimportedSetRows = await serverApp.database.sql`
        select id
        from logged_sets
        where user_id = ${userId}
      `;
      assert.equal(reimportedSetRows.length, 2);
    } finally {
      await serverApp.database.close();
    }
  },
);

function garminStrengthFitFixture() {
  const builder = new FitBuilder();
  builder.define(0, 0, [
    [3, 4, BASE.uint32],
    [4, 4, BASE.uint32],
  ]);
  builder.message(0, [uint32(123456789), dateTime("2026-06-23T19:59:00.000Z")]);
  builder.define(1, 18, [
    [2, 4, BASE.uint32],
    [5, 1, BASE.enum],
    [6, 1, BASE.enum],
    [7, 4, BASE.uint32],
    [8, 4, BASE.uint32],
    [9, 4, BASE.uint32],
    [11, 2, BASE.uint16],
    [16, 1, BASE.uint8],
    [17, 1, BASE.uint8],
    [18, 1, BASE.uint8],
    [19, 1, BASE.uint8],
  ]);
  builder.message(1, [
    dateTime(startedAt),
    uint8(10),
    uint8(20),
    uint32(2700_000),
    uint32(2700_000),
    uint32(0),
    uint16(410),
    uint8(132),
    uint8(166),
    uint8(84),
    uint8(102),
  ]);
  builder.define(2, 20, [
    [253, 4, BASE.uint32],
    [0, 4, BASE.sint32],
    [1, 4, BASE.sint32],
    [3, 1, BASE.uint8],
    [4, 1, BASE.uint8],
  ]);
  builder.message(2, [
    dateTime(firstRecordAt),
    semicircles(-27.4698),
    semicircles(153.0251),
    uint8(130),
    uint8(82),
  ]);
  builder.message(2, [
    dateTime(secondRecordAt),
    semicircles(-27.47),
    semicircles(153.0255),
    uint8(136),
    uint8(86),
  ]);
  builder.define(3, 225, [
    [0, 4, BASE.uint32],
    [2, 4, BASE.uint32],
    [3, 2, BASE.uint16],
    [4, 2, BASE.uint16],
  ]);
  builder.message(3, [
    uint32(60_000),
    dateTime("2026-06-23T20:10:00.000Z"),
    uint16(5),
    uint16(1600),
  ]);
  builder.message(3, [
    uint32(60_000),
    dateTime("2026-06-23T20:15:00.000Z"),
    uint16(3),
    uint16(5616),
  ]);
  builder.message(3, [
    uint32(60_000),
    dateTime("2026-06-23T20:20:00.000Z"),
    uint16(1),
    uint16(16016),
  ]);

  return builder.build();
}

function fitFileWithData(data, magic = ".FIT") {
  return fitHeader({ declaredDataSize: data.length, actualData: data, magic });
}

function fitHeader({ declaredDataSize, actualData, magic = ".FIT" }) {
  const header = Buffer.alloc(14);
  header.writeUInt8(14, 0);
  header.writeUInt8(0x10, 1);
  header.writeUInt16LE(0, 2);
  header.writeUInt32LE(declaredDataSize, 4);
  header.write(magic, 8, "ascii");
  return Buffer.concat([header, actualData, Buffer.alloc(2)]);
}

function unsupportedBaseTypeData() {
  return Buffer.from([
    0x40, 0x00, 0x00, 0x14, 0x00, 0x01, 0x03, 0x01, 0x1f, 0x00, 0x01,
  ]);
}

async function createUser(serverApp) {
  const userId = `fit-import-user-${randomUUID()}`;
  await serverApp.database.db.insert(schema.user).values({
    id: userId,
    name: "FIT Import User",
    email: `${userId}@example.com`,
    emailVerified: true,
  });

  return userId;
}

async function createSignedInUser(serverApp) {
  const userId = await createUser(serverApp);
  const sessionToken = `session-${randomUUID()}`;
  await serverApp.database.db.insert(schema.session).values({
    id: `session-row-${randomUUID()}`,
    token: sessionToken,
    userId,
    expiresAt: new Date("2099-01-01T00:00:00.000Z"),
  });

  return { userId, sessionToken };
}

async function countImportedRowsByUser(serverApp, userIds) {
  const counts = {};
  for (const userId of userIds) {
    const externalActivities = await serverApp.database.sql`
      select id
      from external_activities
      where user_id = ${userId}
    `;
    const loggedSets = await serverApp.database.sql`
      select id
      from logged_sets
      where user_id = ${userId}
    `;
    counts[userId] = {
      externalActivities: externalActivities.length,
      loggedSets: loggedSets.length,
    };
  }

  return counts;
}

async function enableIntegrationConsents(
  serverApp,
  { userId, credentialId, dataClasses },
) {
  const updatedAt = new Date("2026-06-25T08:00:00.000Z");
  await serverApp.database.db
    .update(schema.integrationDataClassConsents)
    .set({
      enabled: true,
      updatedAt,
      deletedAt: null,
      receivedAt: updatedAt,
    })
    .where(
      and(
        eq(schema.integrationDataClassConsents.userId, userId),
        eq(schema.integrationDataClassConsents.credentialId, credentialId),
        inArray(schema.integrationDataClassConsents.dataClass, dataClasses),
      ),
    );
}

async function postCanonicalImport(app, secret, body) {
  return app.request("/integrations/canonical-import", {
    method: "POST",
    headers: {
      authorization: `Bearer ${secret}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

async function postGarminFitImport(
  app,
  token,
  { credentialId, file, idempotencyKey, timezone },
) {
  return app.request("/integrations/garmin/fit-import", {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      fileBase64: Buffer.from(file).toString("base64"),
      ...(credentialId === undefined ? {} : { credentialId }),
      idempotencyKey,
      timezone,
    }),
  });
}

const BASE = {
  enum: 0x00,
  uint8: 0x02,
  sint32: 0x85,
  uint16: 0x84,
  uint32: 0x86,
};

class FitBuilder {
  #records = [];

  define(localMessageType, globalMessageNumber, fields) {
    const bytes = [
      0x40 | localMessageType,
      0,
      0,
      globalMessageNumber & 0xff,
      (globalMessageNumber >> 8) & 0xff,
      fields.length,
    ];
    for (const [number, size, baseType] of fields) {
      bytes.push(number, size, baseType);
    }
    this.#records.push(Buffer.from(bytes));
  }

  message(localMessageType, fieldValues) {
    this.#records.push(
      Buffer.concat([Buffer.from([localMessageType]), ...fieldValues]),
    );
  }

  build() {
    const data = Buffer.concat(this.#records);
    const header = Buffer.alloc(14);
    header.writeUInt8(14, 0);
    header.writeUInt8(0x10, 1);
    header.writeUInt16LE(0, 2);
    header.writeUInt32LE(data.length, 4);
    header.write(".FIT", 8, "ascii");
    return Buffer.concat([header, data, Buffer.alloc(2)]);
  }
}

function uint8(value) {
  return Buffer.from([value]);
}

function uint16(value) {
  const buffer = Buffer.alloc(2);
  buffer.writeUInt16LE(value);
  return buffer;
}

function uint32(value) {
  const buffer = Buffer.alloc(4);
  buffer.writeUInt32LE(value);
  return buffer;
}

function int32(value) {
  const buffer = Buffer.alloc(4);
  buffer.writeInt32LE(value);
  return buffer;
}

function dateTime(value) {
  return uint32(
    Math.round((Date.parse(value) - Date.UTC(1989, 11, 31)) / 1000),
  );
}

function semicircles(degrees) {
  return int32(Math.round((degrees * 2 ** 31) / 180));
}
