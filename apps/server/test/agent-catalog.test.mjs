import assert from "node:assert/strict";
import test from "node:test";

import {
  CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS,
  createApp,
  createInMemoryAgentCatalogStore,
} from "../src/index.ts";

test("agent exercise resolution prefers a user exercise over a shadowed platform exercise", async () => {
  const app = createAgentCatalogApp();

  const response = await getAgent(
    app,
    "/agent/exercises/resolve?name=Back%20Squat",
  );

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.resolution, "matched");
  assert.equal(body.matchedExercise.id, "user-back-squat");
  assert.equal(body.matchedExercise.library, "user");
  assert.deepEqual(body.matchedExercise.dimensions, ["load", "reps"]);
  assert.deepEqual(body.matchedExercise.equipment, ["barbell"]);
  assert.equal(body.matchedExercise.recordProfile, "repMax");
  assert.deepEqual(body.candidates, []);
});

test("catalogue ID reads do not leak a shadowed Platform Exercise", async () => {
  const store = createInMemoryAgentCatalogStore(catalogFixtures());

  assert.equal(
    await store.getExerciseById({
      userId: "user-1",
      exerciseId: "platform-back-squat"
    }),
    null
  );
  const visible = await store.getExercisesByIds({
    userId: "user-1",
    exerciseIds: ["platform-back-squat", "user-back-squat"]
  });
  assert.deepEqual(visible.map((entry) => entry.id), ["user-back-squat"]);
});

test("agent exercise resolution shadows mapped Platform cardio exercise ids at read time", async () => {
  const app = createAgentCatalogApp();

  const response = await getAgent(
    app,
    "/agent/exercises/resolve?name=Trail%20Running",
  );

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.resolution, "matched");
  assert.equal(body.matchedExercise.id, "user-trail-running");
  assert.equal(body.matchedExercise.library, "user");
  assert.equal(
    body.matchedExercise.shadowedPlatformExerciseId,
    CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning,
  );

  const listResponse = await getAgent(
    app,
    "/agent/exercises?search=Trail%20Running",
  );
  assert.equal(listResponse.status, 200);
  const list = await listResponse.json();
  assert.equal(
    list.exercises.some(
      (exercise) =>
        exercise.id === CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning,
    ),
    false,
  );
});

test("agent exercise resolution returns a platform exercise when no user exercise shadows it", async () => {
  const app = createAgentCatalogApp();

  const response = await getAgent(
    app,
    "/agent/exercises/resolve?name=Deadlift",
  );

  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.resolution, "matched");
  assert.equal(body.matchedExercise.id, "platform-deadlift");
  assert.equal(body.matchedExercise.library, "platform");
  assert.deepEqual(body.matchedExercise.dimensions, ["load", "reps"]);
  assert.deepEqual(body.matchedExercise.equipment, ["barbell"]);
  assert.equal(body.matchedExercise.recordProfile, "repMax");
});

test("agent exercise resolution returns candidates instead of silently picking ambiguous or partial names", async () => {
  const app = createAgentCatalogApp();

  const ambiguousResponse = await getAgent(
    app,
    "/agent/exercises/resolve?name=squat",
  );
  assert.equal(ambiguousResponse.status, 200);
  const ambiguous = await ambiguousResponse.json();
  assert.equal(ambiguous.resolution, "ambiguous");
  assert.equal(ambiguous.matchedExercise, null);
  assert.deepEqual(
    ambiguous.candidates.map((exercise) => exercise.id),
    ["user-back-squat", "user-front-squat", "user-box-squat"],
  );
  assert.equal(
    ambiguous.candidates.some(
      (exercise) => exercise.id === "platform-back-squat",
    ),
    false,
  );

  const partialResponse = await getAgent(
    app,
    "/agent/exercises/resolve?name=press",
  );
  assert.equal(partialResponse.status, 200);
  const partial = await partialResponse.json();
  assert.equal(partial.resolution, "not_found");
  assert.equal(partial.matchedExercise, null);
  assert.deepEqual(
    partial.candidates.map((exercise) => exercise.id),
    ["platform-bench-press"],
  );
});

test("agent exercise resolution attaches machine-actionable batch-write guidance for not_found and ambiguous, but not matched", async () => {
  const app = createAgentCatalogApp();

  const matchedResponse = await getAgent(
    app,
    "/agent/exercises/resolve?name=Back%20Squat",
  );
  const matched = await matchedResponse.json();
  assert.equal(matched.resolution, "matched");
  assert.equal(matched.guidance, null);

  const ambiguousResponse = await getAgent(
    app,
    "/agent/exercises/resolve?name=squat",
  );
  const ambiguous = await ambiguousResponse.json();
  assert.equal(ambiguous.resolution, "ambiguous");
  assert.ok(ambiguous.guidance);
  assert.equal(ambiguous.guidance.op, "POST /agent/exercises/batch-write");
  assert.match(ambiguous.guidance.message, /disambiguate/i);

  const notFoundResponse = await getAgent(
    app,
    "/agent/exercises/resolve?name=Totally%20Unknown%20Exercise",
  );
  const notFound = await notFoundResponse.json();
  assert.equal(notFound.resolution, "not_found");
  assert.ok(notFound.guidance);
  assert.equal(notFound.guidance.op, "POST /agent/exercises/batch-write");
  assert.match(notFound.guidance.message, /create/i);
});

test("agent exercise catalog list returns a filtered bounded page with selected fields", async () => {
  const app = createAgentCatalogApp();

  const firstPageResponse = await getAgent(
    app,
    "/agent/exercises?search=squat&category=cat-strength&favorite=true&activeOnly=true&limit=1&fields=library,dimensions,equipment,recordProfile",
  );
  assert.equal(firstPageResponse.status, 200);
  const firstPage = await firstPageResponse.json();
  assert.equal(firstPage.limit, 1);
  assert.deepEqual(firstPage.fields, [
    "id",
    "name",
    "library",
    "dimensions",
    "equipment",
    "recordProfile",
  ]);
  assert.deepEqual(
    firstPage.exercises.map((exercise) => exercise.id),
    ["user-back-squat"],
  );
  assert.equal(firstPage.exercises[0].library, "user");
  assert.deepEqual(firstPage.exercises[0].dimensions, ["load", "reps"]);
  assert.deepEqual(firstPage.exercises[0].equipment, ["barbell"]);
  assert.equal(firstPage.exercises[0].recordProfile, "repMax");
  assert.equal(Object.hasOwn(firstPage.exercises[0], "category"), false);
  assert.equal(typeof firstPage.nextCursor, "string");

  const secondPageResponse = await getAgent(
    app,
    `/agent/exercises?search=squat&category=cat-strength&favorite=true&activeOnly=true&limit=1&fields=library,dimensions,equipment,recordProfile&cursor=${encodeURIComponent(firstPage.nextCursor)}`,
  );
  assert.equal(secondPageResponse.status, 200);
  const secondPage = await secondPageResponse.json();
  assert.deepEqual(
    secondPage.exercises.map((exercise) => exercise.id),
    ["user-front-squat"],
  );
  assert.equal(secondPage.nextCursor, null);

  const allResponse = await getAgent(app, "/agent/exercises?limit=100");
  assert.equal(allResponse.status, 200);
  const all = await allResponse.json();
  assert.equal(
    all.exercises.some((exercise) => exercise.id === "platform-back-squat"),
    false,
  );
  assert.equal(
    all.exercises.some((exercise) => exercise.id === "other-user-row"),
    false,
  );

  const activeOnlyResponse = await getAgent(
    app,
    "/agent/exercises?search=curl&activeOnly=false",
  );
  assert.equal(activeOnlyResponse.status, 200);
  const activeOnly = await activeOnlyResponse.json();
  assert.deepEqual(
    activeOnly.exercises.map((exercise) => exercise.id),
    ["user-archived-curl"],
  );
});

test("agent exercise catalog routes require a configured store and valid agent bearer", async () => {
  const appWithoutStore = createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore(),
  });
  const unavailableResponse = await getAgent(
    appWithoutStore,
    "/agent/exercises/resolve?name=Back%20Squat",
  );
  assert.equal(unavailableResponse.status, 503);
  assert.deepEqual(await unavailableResponse.json(), {
    code: "agent_catalog_unavailable",
    message: "Agent Exercise catalog storage is not configured.",
  });

  const app = createAgentCatalogApp();
  const missingBearerResponse = await app.request(
    "/agent/exercises/resolve?name=Back%20Squat",
  );
  assert.equal(missingBearerResponse.status, 401);

  const invalidBearerResponse = await app.request(
    "/agent/exercises/resolve?name=Back%20Squat",
    {
      headers: { authorization: "Bearer prn_agent_unknown" },
    },
  );
  assert.equal(invalidBearerResponse.status, 401);
});

function createAgentCatalogApp() {
  return createApp({
    logger: { info() {}, error() {} },
    agentApiKeyStore: createAgentKeyStore(),
    agentCatalogStore: createInMemoryAgentCatalogStore(catalogFixtures()),
  });
}

function createAgentKeyStore() {
  return {
    async authenticateAgentApiKey(secret) {
      if (secret !== "prn_agent_secret") {
        return null;
      }

      return {
        userId: "user-1",
        keyId: "agent-key-1",
        keyName: "Garage coach",
      };
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
    },
  };
}

function getAgent(app, path) {
  return app.request(path, {
    headers: { authorization: "Bearer prn_agent_secret" },
  });
}

function catalogFixtures() {
  return [
    exercise({
      id: "platform-back-squat",
      library: "platform",
      name: "Back Squat",
      categoryId: "cat-strength",
    }),
    exercise({
      id: "platform-deadlift",
      library: "platform",
      name: "Deadlift",
      categoryId: "cat-strength",
    }),
    exercise({
      id: "platform-bench-press",
      library: "platform",
      name: "Bench Press",
      categoryId: "cat-strength",
    }),
    exercise({
      id: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning,
      library: "platform",
      name: "Trail Running",
      categoryId: "cat-running",
      dimensions: ["distance", "duration"],
      equipment: [],
      recordProfile: "fastestPace",
    }),
    exercise({
      id: "user-back-squat",
      library: "user",
      ownerUserId: "user-1",
      name: "Back Squat",
      categoryId: "cat-strength",
      favorite: true,
      shadowedPlatformExerciseId: "platform-back-squat",
    }),
    exercise({
      id: "user-trail-running",
      library: "user",
      ownerUserId: "user-1",
      name: "Trail Running",
      categoryId: "cat-running",
      dimensions: ["distance", "duration"],
      equipment: [],
      recordProfile: "fastestPace",
      shadowedPlatformExerciseId:
        CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning,
    }),
    exercise({
      id: "user-front-squat",
      library: "user",
      ownerUserId: "user-1",
      name: "Front Squat",
      categoryId: "cat-strength",
      favorite: true,
    }),
    exercise({
      id: "user-box-squat",
      library: "user",
      ownerUserId: "user-1",
      name: "Box Squat",
      categoryId: "cat-strength",
    }),
    exercise({
      id: "user-archived-curl",
      library: "user",
      ownerUserId: "user-1",
      name: "Curl",
      categoryId: "cat-arms",
      active: false,
      favorite: true,
    }),
    exercise({
      id: "other-user-row",
      library: "user",
      ownerUserId: "user-2",
      name: "Cable Row",
      categoryId: "cat-back",
      favorite: true,
    }),
  ];
}

function exercise(overrides) {
  return {
    id: overrides.id,
    library: overrides.library,
    ownerUserId: overrides.ownerUserId ?? null,
    name: overrides.name,
    category: {
      id: overrides.categoryId,
      name: categoryName(overrides.categoryId),
    },
    dimensions: overrides.dimensions ?? ["load", "reps"],
    equipment: overrides.equipment ?? ["barbell"],
    loadMode: overrides.loadMode ?? "added",
    recordProfile: overrides.recordProfile ?? "repMax",
    favorite: overrides.favorite ?? false,
    active: overrides.active ?? true,
    shadowedPlatformExerciseId: overrides.shadowedPlatformExerciseId ?? null,
  };
}

function categoryName(id) {
  switch (id) {
    case "cat-arms":
      return "Arms";
    case "cat-back":
      return "Back";
    case "cat-strength":
      return "Strength";
    case "cat-running":
      return "Running";
    default:
      return "Other";
  }
}
