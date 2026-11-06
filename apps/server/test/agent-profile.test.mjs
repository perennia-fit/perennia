import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import {
  applyMigrations,
  createApp,
  createDatabaseClient,
  createDrizzleAgentActivityStore,
  createDrizzleAgentProfileStore,
  createDrizzleSyncStore,
  schema,
  SYNC_PROTOCOL_VERSION
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error(
    "DATABASE_URL must be set for server Postgres integration tests."
  );
}

const skip = databaseUrl ? false : "DATABASE_URL is not set.";
const year = new Date().getUTCFullYear();
const EMPTY_SECTIONS = {
  aboutYou: null,
  trainingGoals: null,
  experience: null,
  trainingSetup: null,
  healthLimitations: null,
  generalNotes: null
};

function profileTest(name, body) {
  test(name, { skip }, async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-profile-user-${randomUUID()}`;
    const nudges = [];
    const errorLogs = [];
    const sessionToken = `session-${randomUUID()}`;
    const app = createApp({
      logger: {
        info() {},
        error(payload, message) {
          errorLogs.push({ payload, message });
        }
      },
      agentApiKeyStore: createAgentKeyStore(userId),
      agentProfileStore: createDrizzleAgentProfileStore(database.db),
      agentActivityStore: createDrizzleAgentActivityStore(database.db),
      syncStore: createDrizzleSyncStore(database.db),
      syncNudgePublisher: {
        async enqueueSyncNudge(input) {
          nudges.push(input);
          return { enqueued: true, jobId: `nudge-${nudges.length}` };
        }
      }
    });
    try {
      await database.db.insert(schema.user).values({
        id: userId,
        name: "Agent Profile User",
        email: `${userId}@example.com`,
        emailVerified: true
      });
      await database.db.insert(schema.session).values({
        id: `session-row-${randomUUID()}`,
        token: sessionToken,
        userId,
        expiresAt: new Date("2099-01-01T00:00:00.000Z")
      });
      await body({ app, database, userId, nudges, sessionToken, errorLogs });
    } finally {
      await database.close();
    }
  });
}

profileTest("read when empty returns every section as null", async ({ app }) => {
  assert.deepEqual(await readSections(app), EMPTY_SECTIONS);
});

profileTest(
  "a partial write keeps absent fields, null clears a field, and a list replaces the whole list",
  async ({ app, nudges, database, userId }) => {
    const first = await write(app, {
      aboutYou: {
        sex: "female",
        birthYear: 1990,
        height: { value: 66, unit: "in" }
      },
      trainingGoals: { goals: ["strength", "longevity"] },
      experience: { levels: [{ focusId: "focus-a", level: "beginner" }] }
    });
    assert.equal(first.status, 200);
    const firstBody = await first.json();
    assert.equal(firstBody.accepted, true);
    assert.equal(firstBody.duplicate, false);
    assert.equal(firstBody.batchId, firstBody.idempotencyKey);
    assert.deepEqual(firstBody.warnings, []);
    assert.deepEqual(firstBody.profile.sections.aboutYou.values, {
      sex: "female",
      birthYear: 1990,
      height: { value: 66, unit: "in" }
    });
    assert.deepEqual(firstBody.profile.sections.experience.values.levels, [
      { focusId: "focus-a", level: "beginner" }
    ]);
    assert.equal(nudges.length, 1, "an applied write nudges");

    // The rows hold snake_case section values.
    const rows = await database.sql`
      select payload from user_profile_sections where user_id = ${userId}
    `;
    const experience = rows
      .map((row) => storedJson(row.payload))
      .find((payload) => payload.section === "experience");
    assert.deepEqual(experience.values.levels, [
      { focus_id: "focus-a", level: "beginner" }
    ]);

    await assertOk(write(app, { aboutYou: { birthYear: 1991 } }));
    await assertOk(write(app, { aboutYou: { sex: null } }));
    await assertOk(write(app, { trainingGoals: { goals: ["mobility"] } }));

    const sections = await readSections(app);
    assert.deepEqual(sections.aboutYou.values, {
      sex: null,
      birthYear: 1991,
      height: { value: 66, unit: "in" }
    });
    assert.deepEqual(sections.trainingGoals.values.goals, ["mobility"]);
    assert.equal(
      (await sectionRows(database, userId, "about_you")).length,
      1,
      "writes update the section's row in place"
    );
  }
);

profileTest(
  "an all-unset row reads as null, and an empty list is a choice rather than unset",
  async ({ app, database, userId }) => {
    await assertOk(write(app, { generalNotes: { text: "Prefers mornings" } }));
    await assertOk(write(app, { generalNotes: { text: null } }));
    await assertOk(write(app, { trainingGoals: { goals: [] } }));

    const sections = await readSections(app);
    assert.equal(sections.generalNotes, null);
    assert.deepEqual(sections.trainingGoals.values.goals, []);
    assert.equal(
      (await sectionRows(database, userId, "general_notes")).length,
      1,
      "clearing every field keeps the row"
    );
  }
);

profileTest(
  "Health & limitations normalises in both directions before validating",
  async ({ app }) => {
    await assertOk(write(app, { healthLimitations: { text: "Left knee" } }));
    assert.deepEqual((await readSections(app)).healthLimitations.values, {
      text: "Left knee",
      none: false
    });

    await assertOk(write(app, { healthLimitations: { none: true } }));
    assert.deepEqual((await readSections(app)).healthLimitations.values, {
      text: null,
      none: true
    });

    await assertOk(write(app, { healthLimitations: { text: "Right wrist" } }));
    assert.deepEqual((await readSections(app)).healthLimitations.values, {
      text: "Right wrist",
      none: false
    });

    // One write that sets both: none wins, so both can never be stored.
    await assertOk(
      write(app, { healthLimitations: { text: "Ignored", none: true } })
    );
    assert.deepEqual((await readSections(app)).healthLimitations.values, {
      text: null,
      none: true
    });

    // An explicit null means false, which leaves nothing set here.
    await assertOk(write(app, { healthLimitations: { none: null } }));
    assert.equal((await readSections(app)).healthLimitations, null);

    // Text over the limit is judged on the merged section even with none: true
    // given, because none wins before validation.
    const overLimit = "x".repeat(1001);
    const accepted = await write(app, {
      healthLimitations: { text: overLimit, none: true }
    });
    assert.equal(accepted.status, 200);
    const rejected = await write(app, {
      healthLimitations: { text: overLimit }
    });
    assert.equal(rejected.status, 422);
    assert.equal((await rejected.json()).errors[0].rule, "text.too_long");
  }
);

profileTest(
  "the strict schema answers 400 for unknown keys, wrong JSON types, non-integers and an empty write",
  async ({ app, database, userId, nudges }) => {
    const invalidBodies = [
      { sections: { aboutYou: { nickname: "Sam" } } },
      { sections: { favourites: { colour: "red" } } },
      { sections: { aboutYou: { birthYear: "1990" } } },
      { sections: { aboutYou: { birthYear: 1990.5 } } },
      { sections: { aboutYou: { height: { value: 170, unit: "cm", extra: 1 } } } },
      { sections: { aboutYou: { sex: 1 } } },
      { sections: { trainingSetup: { daysPerWeek: 3.5 } } },
      { sections: { trainingGoals: { goals: "strength" } } },
      { sections: { experience: { levels: [{ focusId: "a", level: "beginner", x: 1 }] } } },
      { sections: { healthLimitations: { none: "yes" } } },
      { sections: { generalNotes: { text: 5 } } },
      { sections: {} },
      { sections: { aboutYou: {} } },
      { sections: { aboutYou: { sex: "male" } }, extra: true },
      { sections: { aboutYou: { sex: "male" } }, updatedAt: "not a date" }
    ];
    for (const body of invalidBodies) {
      const response = await post(app, {
        idempotencyKey: `profile-${randomUUID()}`,
        ...body
      });
      assert.equal(response.status, 400, JSON.stringify(body));
    }
    assert.equal(await countRows(database, userId), 0);
    assert.equal(nudges.length, 0);
  }
);

profileTest(
  "a hard reject answers 422, writes nothing, and names the section and field in camelCase",
  async ({ app, database, userId, nudges }) => {
    const cases = [
      [{ aboutYou: { birthYear: year + 1 } }, "aboutYou", "birthYear", "birth_year.future"],
      [{ aboutYou: { sex: "other" } }, "aboutYou", "sex", "sex.unknown"],
      [{ aboutYou: { height: { value: 170, unit: "ft" } } }, "aboutYou", "height", "height.unit"],
      [{ trainingGoals: { goals: ["flying"] } }, "trainingGoals", "goals", "goals.unknown"],
      [
        { experience: { levels: [{ focusId: "a", level: "expert" }] } },
        "experience",
        "levels",
        "levels.unknown_level"
      ],
      [{ trainingSetup: { daysPerWeek: 0 } }, "trainingSetup", "daysPerWeek", "days_per_week.range"]
    ];
    for (const [sections, section, field, rule] of cases) {
      const response = await write(app, sections);
      assert.equal(response.status, 422, rule);
      const body = await response.json();
      assert.equal(body.code, "agent_profile_batch_write_failed");
      assert.equal(body.errors.length, 1);
      assert.equal(body.errors[0].section, section);
      assert.equal(body.errors[0].field, field);
      assert.equal(body.errors[0].rule, rule);
      assert.ok(body.errors[0].message.length > 0);
    }

    // One bad section stops the whole write, including the good one.
    const mixed = await write(app, {
      generalNotes: { text: "Kept out" },
      trainingSetup: { daysPerWeek: 8 }
    });
    assert.equal(mixed.status, 422);

    assert.equal(await countRows(database, userId), 0);
    assert.equal(await countBatches(database, userId), 0);
    assert.equal(nudges.length, 0);
  }
);

profileTest(
  "a stored value the rules reject blocks a write of its section until the write replaces it",
  async ({ app, sessionToken, database, userId }) => {
    // Only a push can store one: it does no domain validation.
    const id = randomUUID();
    await pushSection(app, sessionToken, id, "about_you", {
      sex: "other",
      birth_year: 1990,
      height: null
    });
    assert.equal((await readSections(app)).aboutYou.values.sex, "other");

    const blocked = await write(app, { aboutYou: { birthYear: 1991 } });
    assert.equal(blocked.status, 422);
    const body = await blocked.json();
    assert.deepEqual(
      body.errors.map(({ section, field, rule }) => [section, field, rule]),
      [["aboutYou", "sex", "sex.unknown"]]
    );
    assert.equal(await countBatches(database, userId), 0);

    await assertOk(write(app, { aboutYou: { sex: null, birthYear: 1991 } }));
    assert.deepEqual((await readSections(app)).aboutYou.values, {
      sex: null,
      birthYear: 1991,
      height: null
    });
  }
);

profileTest(
  "a stored Equipment id the rules reject blocks a write of its section, and the merge keeps it",
  async ({ app, sessionToken, database, userId }) => {
    const equipment = ["barbell", "barbell", "x".repeat(65), "future_gear"];
    await pushSection(app, sessionToken, randomUUID(), "training_setup", {
      equipment,
      days_per_week: 3,
      session_minutes: null
    });
    assert.deepEqual(
      (await readSections(app)).trainingSetup.values.equipment,
      equipment
    );

    const blocked = await write(app, { trainingSetup: { daysPerWeek: 4 } });
    assert.equal(blocked.status, 422);
    assert.deepEqual(
      (await blocked.json()).errors.map(({ section, field, rule }) => [
        section,
        field,
        rule
      ]),
      [
        ["trainingSetup", "equipment", "equipment.invalid"],
        ["trainingSetup", "equipment", "equipment.duplicate"]
      ]
    );
    assert.equal(await countBatches(database, userId), 0);
    const [row] = await sectionRows(database, userId, "training_setup");
    assert.deepEqual(storedJson(row.payload).values.equipment, equipment);

    await assertOk(
      write(app, {
        trainingSetup: { equipment: ["future_gear"], daysPerWeek: 4 }
      })
    );
    assert.deepEqual((await readSections(app)).trainingSetup.values, {
      equipment: ["future_gear"],
      daysPerWeek: 4,
      sessionMinutes: null
    });
  }
);

profileTest(
  "a soft warning applies, and is returned in camelCase with the message",
  async ({ app }) => {
    const birthYear = year - 111;
    const response = await write(app, { aboutYou: { birthYear } });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.deepEqual(body.warnings, [
      {
        section: "aboutYou",
        field: "birthYear",
        rule: "birth_year.improbable_age",
        message: "That makes you 111. Check the birth year."
      }
    ]);
    assert.equal(body.profile.sections.aboutYou.values.birthYear, birthYear);
  }
);

profileTest(
  "an idempotent replay answers duplicate: true, appends no Batch, and returns the warning again",
  async ({ app, database, userId, nudges }) => {
    const idempotencyKey = `profile-${randomUUID()}`;
    const request = {
      idempotencyKey,
      sections: {
        aboutYou: { birthYear: year - 111 },
        trainingSetup: { sessionMinutes: 300, daysPerWeek: 4 }
      }
    };
    const first = await post(app, request);
    assert.equal(first.status, 200);
    const firstBody = await first.json();
    assert.equal(firstBody.duplicate, false);
    assert.equal(firstBody.warnings.length, 2);
    assert.equal(nudges.length, 1);
    const batchesAfterFirst = await countBatches(database, userId);
    const rowsAfterFirst = await countRows(database, userId);

    // A later change is what `profile` shows on the replay.
    await assertOk(write(app, { trainingSetup: { daysPerWeek: 5 } }));
    const nudgesBeforeReplay = nudges.length;
    const batchesBeforeReplay = await countBatches(database, userId);

    const replay = await post(app, request);
    assert.equal(replay.status, 200);
    const replayBody = await replay.json();
    assert.equal(replayBody.duplicate, true);
    assert.equal(replayBody.batchId, idempotencyKey);
    assert.deepEqual(replayBody.warnings, firstBody.warnings);
    assert.equal(replayBody.profile.sections.trainingSetup.values.daysPerWeek, 5);
    assert.equal(await countBatches(database, userId), batchesBeforeReplay);
    assert.equal(nudges.length, nudgesBeforeReplay, "a replay does not nudge");
    assert.equal(batchesBeforeReplay, batchesAfterFirst + 1);
    assert.equal(await countRows(database, userId), rowsAfterFirst);
  }
);

profileTest(
  "a section with no row and only null fields writes no row and no Batch, and does not nudge",
  async ({ app, database, userId, nudges }) => {
    const response = await write(app, {
      aboutYou: { sex: null, birthYear: null, height: null },
      trainingSetup: { equipment: null },
      healthLimitations: { text: null, none: false },
      generalNotes: { text: null }
    });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.duplicate, false);
    assert.deepEqual(body.profile.sections, EMPTY_SECTIONS);
    assert.equal(await countRows(database, userId), 0);
    assert.equal(await countBatches(database, userId), 0);
    assert.equal(nudges.length, 0);
  }
);

profileTest(
  "re-sending the same fields adds no Batch and no nudge, and undo of the first Batch still applies",
  async ({ app, database, userId, nudges }) => {
    const first = await assertOk(
      write(app, {
        trainingGoals: { goals: ["strength"] },
        aboutYou: { birthYear: year - 111 }
      })
    );
    const before = await sectionRows(database, userId, "training_goals");
    assert.equal(nudges.length, 1);

    const again = await assertOk(
      write(app, {
        trainingGoals: { goals: ["strength"] },
        aboutYou: { birthYear: year - 111 }
      })
    );
    assert.equal(again.duplicate, false);
    assert.equal(again.warnings.length, 1, "warnings are still returned");
    assert.deepEqual(again.profile, first.profile);
    assert.equal(await countBatches(database, userId), 1);
    assert.equal(nudges.length, 1, "nothing changed, so nothing to nudge");
    assert.deepEqual(
      await sectionRows(database, userId, "training_goals"),
      before,
      "the row and its clock did not move"
    );

    // One changed section beside an unchanged one writes only the changed one.
    const mixed = await assertOk(
      write(app, {
        trainingGoals: { goals: ["strength"] },
        generalNotes: { text: "Prefers mornings" }
      })
    );
    assert.deepEqual(
      (await listProfileActivity(app))
        .find((batch) => batch.batchId === mixed.batchId)
        .entries.map((entry) => entry.afterImage.section),
      ["general_notes"]
    );
    assert.equal(await countBatches(database, userId), 2);

    const undo = await postUndo(app, first.batchId);
    assert.equal(undo.status, 200);
    assert.equal((await undo.json()).applied, true);
    assert.equal((await readSections(app)).trainingGoals, null);
  }
);

profileTest(
  "clearing an already all-unset row adds no Batch",
  async ({ app, database, userId, nudges }) => {
    await assertOk(write(app, { aboutYou: { sex: "female" } }));
    await assertOk(write(app, { aboutYou: { sex: null } }));
    assert.equal(await countBatches(database, userId), 2);
    assert.equal(nudges.length, 2);

    await assertOk(write(app, { aboutYou: { sex: null } }));
    assert.equal(await countBatches(database, userId), 2);
    assert.equal(nudges.length, 2);
  }
);

profileTest(
  "a write the database refuses logs no value",
  async ({ app, errorLogs }) => {
    // Postgres refuses NUL in jsonb, after the schema and the validator accept it.
    const response = await write(app, {
      healthLimitations: { text: "HIVSECRET meds\u0000" }
    });
    assert.equal(response.status, 500);

    const failure = errorLogs.find((log) => log.message === "request failed");
    assert.ok(failure, "the failure is logged");
    assert.equal(failure.payload.error.message, "Database query failed.");
    assert.equal(failure.payload.error.type, "DrizzleQueryError");
    assert.equal(failure.payload.error.cause.type, "PostgresError");
    const serialized = JSON.stringify(failure.payload);
    assert.doesNotMatch(serialized, /HIVSECRET/);
    assert.doesNotMatch(serialized, /Failed query/);
    assert.doesNotMatch(serialized, /health_limitations/);
  }
);

profileTest(
  "an empty section beside a real one changes nothing",
  async ({ app, database, userId }) => {
    const response = await write(app, {
      trainingGoals: {},
      generalNotes: { text: "Prefers mornings" }
    });
    assert.equal(response.status, 200);
    assert.equal(await countRows(database, userId), 1);
    assert.equal((await readSections(app)).trainingGoals, null);
  }
);

profileTest(
  "the newest row per section is read and written, by updated_at and then id",
  async ({ app, sessionToken, database, userId }) => {
    const older = randomUUID();
    const newer = randomUUID();
    await pushSection(
      app,
      sessionToken,
      older,
      "general_notes",
      { text: "older" },
      "2025-06-01T08:00:00.000Z"
    );
    await pushSection(
      app,
      sessionToken,
      newer,
      "general_notes",
      { text: "newer" },
      "2025-06-02T08:00:00.000Z"
    );
    const sections = await readSections(app);
    assert.equal(sections.generalNotes.values.text, "newer");
    assert.equal(sections.generalNotes.updatedAt, "2025-06-02T08:00:00.000Z");

    // A tie on updated_at goes to the greater id.
    const [low, high] = [randomUUID(), randomUUID()].sort();
    const tiedAt = "2025-06-03T08:00:00.000Z";
    await pushSection(app, sessionToken, high, "experience", { levels: [{ focus_id: "high", level: "advanced" }] }, tiedAt);
    await pushSection(app, sessionToken, low, "experience", { levels: [{ focus_id: "low", level: "advanced" }] }, tiedAt);
    assert.equal(
      (await readSections(app)).experience.values.levels[0].focusId,
      "high"
    );

    await assertOk(write(app, { generalNotes: { text: "from the agent" } }));
    const rows = await sectionRows(database, userId, "general_notes");
    assert.equal(rows.length, 2, "no third row");
    const byId = new Map(rows.map((row) => [row.id, storedJson(row.payload)]));
    assert.equal(byId.get(newer).values.text, "from the agent");
    assert.equal(byId.get(older).values.text, "older");
  }
);

profileTest(
  "a poisoned row reads tolerantly and never fails the read or a later write",
  async ({ app, sessionToken }) => {
    await pushSection(app, sessionToken, randomUUID(), "about_you", {
      sex: 5,
      birth_year: "x",
      height: { value: "tall", unit: "cm" },
      from_a_newer_app: "kept"
    });
    await pushSection(app, sessionToken, randomUUID(), "training_goals", {
      goals: ["strength", 7, "made_up_goal"]
    });
    await pushSection(app, sessionToken, randomUUID(), "experience", {
      levels: [
        { focus_id: "a", level: "beginner" },
        { focus_id: 3, level: "beginner" },
        "nonsense"
      ]
    });
    await pushSection(app, sessionToken, randomUUID(), "training_setup", {
      equipment: ["barbell", "barbell", "", "x".repeat(65), 9, "future_gear"],
      days_per_week: 1.5,
      session_minutes: 1e300
    });
    await pushSection(app, sessionToken, randomUUID(), "health_limitations", {
      text: "Left knee",
      none: true
    });
    await pushSection(app, sessionToken, randomUUID(), "general_notes", {
      text: ["not", "text"]
    });

    const sections = await readSections(app);
    assert.equal(sections.aboutYou, null, "every field read as unset");
    assert.deepEqual(sections.trainingGoals.values.goals, [
      "strength",
      "made_up_goal"
    ]);
    assert.deepEqual(sections.experience.values.levels, [
      { focusId: "a", level: "beginner" }
    ]);
    assert.deepEqual(sections.trainingSetup.values, {
      equipment: [
        "barbell",
        "barbell",
        "",
        "x".repeat(65),
        "future_gear"
      ],
      daysPerWeek: null,
      sessionMinutes: null
    });
    assert.deepEqual(sections.healthLimitations.values, {
      text: null,
      none: true
    });
    assert.equal(sections.generalNotes, null);

    // A later write merges over those reads, without tripping on them.
    await assertOk(write(app, { aboutYou: { birthYear: 1990 } }));
    assert.equal((await readSections(app)).aboutYou.values.birthYear, 1990);
  }
);

profileTest(
  "undo of a two-section Batch restores both sections, and undo of a first write reads null",
  async ({ app }) => {
    await assertOk(write(app, { trainingGoals: { goals: ["mobility"] } }));

    const write2 = await assertOk(
      write(app, {
        trainingGoals: { goals: ["strength", "longevity"] },
        trainingSetup: { daysPerWeek: 4 }
      })
    );
    const undo = await postUndo(app, write2.batchId);
    assert.equal(undo.status, 200);
    const undoBody = await undo.json();
    assert.equal(undoBody.applied, true);
    assert.equal(undoBody.entries.length, 2);

    const sections = await readSections(app);
    assert.deepEqual(sections.trainingGoals.values.goals, ["mobility"]);
    assert.equal(
      sections.trainingSetup,
      null,
      "the section this Batch created reads as if it never existed"
    );

    // A write after undoing a first write starts a new row and reads back.
    await assertOk(write(app, { trainingSetup: { daysPerWeek: 3 } }));
    assert.equal((await readSections(app)).trainingSetup.values.daysPerWeek, 3);
  }
);

profileTest(
  "undo works with a client updatedAt in another format, or too far in the future",
  async ({ app }) => {
    const respelled = await post(app, {
      idempotencyKey: `profile-${randomUUID()}`,
      updatedAt: "2025-06-01T08:00:00Z",
      sections: { generalNotes: { text: "Respelled clock" } }
    });
    assert.equal(respelled.status, 200);
    const respelledUndo = await postUndo(app, (await respelled.json()).batchId);
    assert.equal((await respelledUndo.json()).applied, true);

    const future = await post(app, {
      idempotencyKey: `profile-${randomUUID()}`,
      updatedAt: "2099-01-01T00:00:00.000Z",
      sections: { experience: { levels: [] } }
    });
    assert.equal(future.status, 200);
    const futureUndo = await postUndo(app, (await future.json()).batchId);
    assert.equal((await futureUndo.json()).applied, true);
  }
);

profileTest(
  "undo of a whole Batch is refused after a change to either section",
  async ({ app }) => {
    const batch = await assertOk(
      write(app, {
        trainingGoals: { goals: ["strength"] },
        trainingSetup: { daysPerWeek: 4 }
      })
    );
    await assertOk(write(app, { trainingSetup: { daysPerWeek: 5 } }));

    const undo = await postUndo(app, batch.batchId);
    assert.equal(undo.status, 200);
    const undoBody = await undo.json();
    assert.equal(undoBody.applied, false);
    assert.equal(undoBody.undoBatchId, null);
    assert.deepEqual(
      undoBody.entries.map((entry) => entry.outcome),
      ["skipped_stale"]
    );

    const sections = await readSections(app);
    assert.deepEqual(sections.trainingGoals.values.goals, ["strength"]);
    assert.equal(sections.trainingSetup.values.daysPerWeek, 5);
  }
);

profileTest(
  "Activity redacts the two free-text sections and shows the others, and undo still works from the real images",
  async ({ app, database, userId }) => {
    const health = await assertOk(
      write(app, { healthLimitations: { text: "Left knee surgery" } })
    );
    const notes = await assertOk(
      write(app, { generalNotes: { text: "Private note" } })
    );
    const shown = await assertOk(
      write(app, { aboutYou: { birthYear: 1990 } })
    );
    await assertOk(write(app, { healthLimitations: { text: "Right knee" } }));

    const batches = await listProfileActivity(app);
    const serialized = JSON.stringify(batches);
    for (const secret of ["Left knee surgery", "Private note", "Right knee"]) {
      assert.doesNotMatch(serialized, new RegExp(secret), secret);
    }

    const entry = (batchId) =>
      batches.find((batch) => batch.batchId === batchId).entries[0];
    const healthEntry = entry(health.batchId);
    assert.equal(healthEntry.beforeImage, null, "a null image stays null");
    assert.deepEqual(healthEntry.afterImage.values, { redacted: true });
    assert.equal(healthEntry.afterImage.section, "health_limitations");
    assert.equal(healthEntry.entityTable, "user_profile_sections");

    assert.deepEqual(entry(notes.batchId).afterImage.values, { redacted: true });
    assert.equal(entry(shown.batchId).afterImage.values.birth_year, 1990);

    const edit = batches.find((batch) =>
      batch.entries.some((candidate) => candidate.beforeImage !== null)
    ).entries[0];
    assert.deepEqual(edit.beforeImage.values, { redacted: true });
    assert.deepEqual(edit.afterImage.values, { redacted: true });

    // The stored image is untouched.
    const stored = await database.sql`
      select after_image from activity_log
      where user_id = ${userId} and batch_id = ${health.batchId}
    `;
    assert.equal(
      storedJson(stored[0].after_image).values.text,
      "Left knee surgery"
    );

    // The Batch an undo appends carries the same text, so it is redacted too.
    const notesUndo = await postUndo(app, notes.batchId);
    const notesUndoBody = await notesUndo.json();
    assert.equal(notesUndoBody.applied, true);
    assert.equal((await readSections(app)).generalNotes, null);
    const afterUndo = await listProfileActivity(app);
    const undoEntry = afterUndo.find(
      (batch) => batch.batchId === notesUndoBody.undoBatchId
    ).entries[0];
    assert.deepEqual(undoEntry.beforeImage.values, { redacted: true });
    assert.deepEqual(undoEntry.afterImage.values, { redacted: true });
    assert.doesNotMatch(JSON.stringify(afterUndo), /Private note/);
  }
);

profileTest(
  "Activity fails closed on an entry with no readable section, and either image can trigger redaction",
  async ({ app, database, userId }) => {
    const logEntry = (batchId, beforeImage, afterImage) =>
      database.db.insert(schema.activityLog).values({
        id: `activity-${randomUUID()}`,
        userId,
        actor: "app",
        batchId,
        entityTable: "user_profile_sections",
        entityId: randomUUID(),
        beforeImage,
        afterImage,
        occurredAt: new Date("2026-06-01T08:00:00.000Z")
      });
    await logEntry("unreadable", null, {
      section: 7,
      values: { text: "Unreadable secret" }
    });
    await logEntry("unknown", null, {
      section: "made_up",
      values: { text: "Unknown secret" }
    });
    await logEntry(
      "either",
      { section: "health_limitations", values: { text: "Before secret" } },
      { section: "about_you", values: { birth_year: 1990 } }
    );

    const batches = await listProfileActivity(app);
    assert.doesNotMatch(JSON.stringify(batches), /secret/);
    const entry = (batchId) =>
      batches.find((batch) => batch.batchId === batchId).entries[0];
    assert.deepEqual(entry("unreadable").afterImage.values, { redacted: true });
    assert.deepEqual(entry("unknown").afterImage.values, { redacted: true });
    assert.deepEqual(entry("either").beforeImage.values, { redacted: true });
    assert.deepEqual(entry("either").afterImage.values, { redacted: true });
  }
);

test("the agent routes answer 503 when the store isn't configured, and 401 without a key", async () => {
  const unconfigured = createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore("user-1")
  });
  const read = await unconfigured.request("/agent/profile", {
    headers: { authorization: "Bearer prn_agent_secret" }
  });
  assert.equal(read.status, 503);
  assert.equal((await read.json()).code, "agent_profile_unavailable");
  const written = await post(unconfigured, {
    idempotencyKey: "profile-1",
    sections: { generalNotes: { text: "x" } }
  });
  assert.equal(written.status, 503);
  assert.equal((await written.json()).code, "agent_profile_unavailable");

  const configured = createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore("user-1"),
    agentProfileStore: {
      async read() {
        throw new Error("read should not be called.");
      },
      async batchWrite() {
        throw new Error("batchWrite should not be called.");
      }
    }
  });
  const noKey = await configured.request("/agent/profile");
  assert.equal(noKey.status, 401);
});

function createAgentKeyStore(userId) {
  return {
    async authenticateAgentApiKey(secret) {
      if (secret !== "prn_agent_secret") {
        return null;
      }
      return { userId, keyId: "agent-key-1", keyName: "Garage coach" };
    },
    async createAgentApiKey() {
      throw new Error("createAgentApiKey should not be called.");
    },
    async listAgentApiKeys() {
      throw new Error("listAgentApiKeys should not be called.");
    },
    async revokeAgentApiKey() {
      throw new Error("revokeAgentApiKey should not be called.");
    },
    async verifySessionBearerToken() {
      throw new Error("verifySessionBearerToken should not be called.");
    }
  };
}

function post(app, body) {
  return app.request("/agent/profile/batch-write", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_agent_secret",
      "content-type": "application/json"
    },
    body: JSON.stringify(body)
  });
}

function write(app, sections) {
  return post(app, { idempotencyKey: `profile-${randomUUID()}`, sections });
}

async function assertOk(responsePromise) {
  const response = await responsePromise;
  const body = await response.json();
  assert.equal(response.status, 200, JSON.stringify(body));
  return body;
}

async function readSections(app) {
  const response = await app.request("/agent/profile", {
    headers: { authorization: "Bearer prn_agent_secret" }
  });
  assert.equal(response.status, 200);
  return (await response.json()).sections;
}

function postUndo(app, batchId) {
  return app.request("/agent/activity/undo-batch", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_agent_secret",
      "content-type": "application/json"
    },
    body: JSON.stringify({ batchId, idempotencyKey: `undo-${randomUUID()}` })
  });
}

async function listProfileActivity(app) {
  const response = await app.request(
    "/agent/activity?entityTable=user_profile_sections&limit=100",
    { headers: { authorization: "Bearer prn_agent_secret" } }
  );
  assert.equal(response.status, 200);
  return (await response.json()).batches;
}

async function pushSection(
  app,
  sessionToken,
  id,
  section,
  values,
  updatedAt = "2025-06-01T08:00:00.000Z"
) {
  const response = await app.request("/sync/push", {
    method: "POST",
    headers: {
      authorization: `Bearer ${sessionToken}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({
      protocolVersion: SYNC_PROTOCOL_VERSION,
      deviceId: "device-a",
      entity: "user_profile_sections",
      changes: [
        {
          id,
          payload: {
            id,
            section,
            values,
            updated_at: updatedAt,
            deleted_at: null
          },
          updatedAt,
          deletedAt: null
        }
      ]
    })
  });
  assert.equal(response.status, 200);
}

function storedJson(value) {
  return typeof value === "string" ? JSON.parse(value) : value;
}

async function sectionRows(database, userId, section) {
  const rows = await database.sql`
    select id, payload from user_profile_sections where user_id = ${userId}
  `;
  return rows.filter((row) => storedJson(row.payload).section === section);
}

async function countRows(database, userId) {
  const rows = await database.sql`
    select count(*)::int as count from user_profile_sections
    where user_id = ${userId}
  `;
  return rows[0].count;
}

async function countBatches(database, userId) {
  const rows = await database.sql`
    select count(distinct batch_id)::int as count from activity_log
    where user_id = ${userId}
  `;
  return rows[0].count;
}
