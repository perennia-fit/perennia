import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  applyPlatformExerciseCleanup,
  buildRetiredExercises,
} from "../../../tools/platform-exercise-cleanup.mjs";
import {
  focusIdsForRetired,
  platformFocuses,
} from "../../../tools/platform-exercise-focus.mjs";

function readBundledManifest() {
  return JSON.parse(
    readFileSync(
      new URL(
        "../../../tools/data/platform-exercise-review-decisions.json",
        import.meta.url,
      ),
      "utf8",
    ),
  );
}

function readBundledSeed() {
  return JSON.parse(
    readFileSync(
      new URL(
        "../../../apps/mobile/assets/seeds/platform_exercises.json",
        import.meta.url,
      ),
      "utf8",
    ),
  );
}

test("reviewed cleanup collapses duplicate chains and applies English primary names", () => {
  const exercises = [
    { id: "a", name: "Pull Up", updated_at: "2026-01-01T00:00:00Z" },
    { id: "b", name: "Pull-Up", updated_at: "2026-01-01T00:00:00Z" },
    {
      id: "c",
      name: "Pull-ups",
      source_attribution: { source: "fixture" },
      updated_at: "2026-01-01T00:00:00Z",
    },
    { id: "d", name: "Agachamento", updated_at: "2026-01-01T00:00:00Z" },
  ];
  const manifest = {
    reviewedAt: "2026-07-20T00:00:00Z",
    excludedExerciseIds: ["d"],
    merges: [
      { keepExerciseId: "b", removeExerciseId: "a" },
      { keepExerciseId: "c", removeExerciseId: "b" },
      { keepExerciseId: "c", removeExerciseId: "a" },
    ],
    replacements: [{ englishName: "Pull-Ups", exerciseId: "c" }],
  };

  const result = applyPlatformExerciseCleanup(exercises, manifest);

  assert.deepEqual(
    result.exercises.map(({ id, name, updated_at }) => ({ id, name, updated_at })),
    [{ id: "c", name: "Pull-Ups", updated_at: manifest.reviewedAt }],
  );
  assert.equal(result.redirects.get("a"), "c");
  assert.equal(result.redirects.get("b"), "c");
  assert.deepEqual(result.exercises[0].source_attribution, {
    source: "fixture",
    reviewed_name_cleanup: {
      decision: "replace_with_english",
      english_name: "Pull-Ups",
      original_name: "Pull-ups",
      reviewed_at: manifest.reviewedAt,
    },
  });
  assert.deepEqual(result.stats, {
    excludedExercises: 1,
    mergedExercises: 2,
    renamedExercises: 1,
  });
});

test("reviewed cleanup requires a valid review timestamp", () => {
  const exercises = [{ id: "a", name: "Pull Up" }];

  assert.throws(
    () => applyPlatformExerciseCleanup(exercises, {}),
    /valid reviewedAt timestamp/,
  );
  assert.throws(
    () =>
      applyPlatformExerciseCleanup(exercises, {
        reviewedAt: "not-a-timestamp",
      }),
    /valid reviewedAt timestamp/,
  );
});

test("reviewed cleanup normalizes exercise and decision ids once", () => {
  const result = applyPlatformExerciseCleanup(
    [
      { id: 1, name: "Pull Up" },
      { id: 2, name: "Pull-Up" },
      { id: 3, name: "Agachamento" },
    ],
    {
      reviewedAt: "2026-07-20T00:00:00Z",
      excludedExerciseIds: [3],
      merges: [{ keepExerciseId: 2, removeExerciseId: 1 }],
    },
  );

  assert.deepEqual(result.exercises.map((exercise) => exercise.id), ["2"]);
  assert.equal(result.redirects.get("1"), "2");
});

// The manifest is the provenance record for the bundled Platform Library: it
// names every exercise excluded or merged during catalogue review. Keeping it in
// the repository is what makes the shipped seed auditable — this test fails if
// the seed and the recorded decisions ever disagree.
test("bundled Platform Library reflects every recorded cleanup outcome", () => {
  const manifest = readBundledManifest();
  const seed = readBundledSeed();
  const exercisesById = new Map(
    seed.exercises.map((exercise) => [exercise.id, exercise]),
  );
  const mergeTargetByRemovedId = new Map(
    manifest.merges.map((merge) => [merge.removeExerciseId, merge.keepExerciseId]),
  );
  const redirects = new Map(
    seed.exercise_redirects.map((redirect) => [
      redirect.from_exercise_id,
      redirect.to_exercise_id,
    ]),
  );

  assert.equal(seed.exercises.length, manifest.expectedExerciseCount);
  for (const id of manifest.excludedExerciseIds) {
    assert.equal(exercisesById.has(id), false, `excluded exercise ${id} remains`);
  }
  for (const merge of manifest.merges) {
    assert.equal(
      exercisesById.has(merge.removeExerciseId),
      false,
      `merged exercise ${merge.removeExerciseId} remains`,
    );
    assert.equal(
      exercisesById.has(merge.keepExerciseId),
      true,
      `retained exercise ${merge.keepExerciseId} is missing`,
    );
    assert.equal(
      redirects.get(merge.removeExerciseId),
      merge.keepExerciseId,
      `merged exercise ${merge.removeExerciseId} has no canonical redirect`,
    );
  }
  for (const replacement of manifest.replacements) {
    assert.equal(
      exercisesById.get(replacement.exerciseId)?.name,
      replacement.englishName,
    );
  }
  for (const id of manifest.acceptedEnglishExerciseIds) {
    const retainedId = mergeTargetByRemovedId.get(id) ?? id;
    assert.equal(
      exercisesById.has(retainedId),
      true,
      `accepted English exercise ${id} has no retained record`,
    );
  }
  for (const itemId of manifest.retainedPairs) {
    const [, leftId, rightId] = itemId.split(":");
    const retainedLeftId = mergeTargetByRemovedId.get(leftId) ?? leftId;
    const retainedRightId = mergeTargetByRemovedId.get(rightId) ?? rightId;
    assert.equal(
      exercisesById.has(retainedLeftId),
      true,
      `retained exercise ${leftId} has no retained record`,
    );
    assert.equal(
      exercisesById.has(retainedRightId),
      true,
      `retained exercise ${rightId} has no retained record`,
    );
    assert.notEqual(
      retainedLeftId,
      retainedRightId,
      `kept-distinct pair ${itemId} collapsed to one record`,
    );
  }
});

const retiredCategories = [
  { id: "cat-legs", name: "Legs" },
  { id: "cat-mobility", name: "Mobility" },
];
const retiredReviewedAt = "2026-07-19T23:48:40.614Z";
const retiredStamp = "2026-11-05T00:00:00.000Z";

function exerciseRecord(id, overrides = {}) {
  return {
    id,
    name: `Exercise ${id}`,
    dimension_ids: ["load", "reps"],
    category_id: "cat-legs",
    equipment_ids: ["barbell"],
    focus_ids: ["focus-from-previous-seed"],
    notes: null,
    updated_at: "2026-06-29T00:00:00Z",
    source_attribution: { source: "wger" },
    ...overrides,
  };
}

function retiredExerciseRecord(id, overrides = {}) {
  const { source_attribution: sourceAttribution, ...fields } = exerciseRecord(id);
  return {
    ...fields,
    retired_at: "2026-08-01T00:00:00.000Z",
    source_attribution: sourceAttribution,
    ...overrides,
  };
}

function buildRetired({
  previousSeed = null,
  sourceRecords = [],
  live = [],
  excluded = [],
  merged = [],
  retiredAt = retiredStamp,
  reviewedAt = retiredReviewedAt,
} = {}) {
  return buildRetiredExercises({
    previousSeed,
    sourceRecords,
    cleanup: {
      exercises: live,
      excludedIds: new Set(excluded),
      redirects: new Map(merged.map((id) => [id, "merge-target"])),
    },
    retiredAt,
    reviewedAt,
    categories: retiredCategories,
    focusIdsFor: (record) => [`focus-for-${record.id}`],
  });
}

// The retired list is what lets the app hide ids the live list has dropped, so
// a seed that misses one, or lists one as both, would leave a stale row visible.
test("bundled retired list covers every recorded retirement, and only those", () => {
  const manifest = readBundledManifest();
  const seed = readBundledSeed();
  const retired = seed.retired_exercises;
  const retiredIds = new Set(retired.map((record) => record.id));

  const expectedIds = [
    ...seed.exercise_redirects.map((redirect) => redirect.from_exercise_id),
    ...manifest.excludedExerciseIds,
  ];
  assert.deepEqual(
    expectedIds.filter((id) => !retiredIds.has(id)),
    [],
    "every redirect source and excluded id is retired",
  );

  assert.deepEqual(
    seed.exercises
      .map((exercise) => exercise.id)
      .filter((id) => retiredIds.has(id)),
    [],
    "no id is both live and retired",
  );

  // By instant, not by string: the seed has both ...Z and ....000Z forms.
  assert.deepEqual(
    retired
      .filter(
        (record) =>
          !(Date.parse(record.retired_at) > Date.parse(record.updated_at)),
      )
      .map((record) => record.id),
    [],
    "every retired_at is later than its updated_at",
  );

  const ids = retired.map((record) => record.id);
  assert.deepEqual(
    ids,
    [...ids].sort((left, right) => left.localeCompare(right, "en-US")),
    "the list is sorted by id",
  );

  const categoryIds = new Set(seed.categories.map((category) => category.id));
  assert.deepEqual(
    retired
      .filter((record) => !categoryIds.has(record.category_id))
      .map((record) => record.id),
    [],
    "every category_id is a seed category",
  );
});

test("reviewed cleanup returns the excluded ids", () => {
  const result = applyPlatformExerciseCleanup(
    [
      { id: "a", name: "Pull Up" },
      { id: " b ", name: "Agachamento" },
    ],
    { reviewedAt: "2026-07-20T00:00:00Z", excludedExerciseIds: ["b"] },
  );

  assert.deepEqual([...result.excludedIds], ["b"]);
});

test("retired list carries a previous record forward unchanged", () => {
  const carried = retiredExerciseRecord("old", { focus_ids: ["frozen"] });
  const before = JSON.stringify(carried);

  const [record] = buildRetired({
    previousSeed: { exercises: [], retired_exercises: [carried] },
    // The source and the cleanup no longer agree with the frozen record.
    sourceRecords: [exerciseRecord("old", { name: "Renamed upstream" })],
    excluded: ["old"],
    merged: ["old"],
    retiredAt: "2026-12-01T00:00:00.000Z",
  });

  assert.equal(record, carried);
  assert.equal(JSON.stringify(record), before);
});

test("newly retired id prefers the previous seed's record", () => {
  const [record] = buildRetired({
    previousSeed: {
      exercises: [exerciseRecord("a", { name: "Corrected name" })],
    },
    sourceRecords: [
      exerciseRecord("a", {
        name: "Uncorrected source name",
        focus_ids: ["source"],
      }),
    ],
    merged: ["a"],
  });

  assert.equal(record.name, "Corrected name");
  assert.deepEqual(record.focus_ids, ["focus-from-previous-seed"]);
  assert.equal(record.retired_at, retiredStamp);
});

test("source-only retired id takes source fields and focusIdsFor", () => {
  const { focus_ids: _focusIds, ...source } = exerciseRecord(200, {
    name: "Only in source",
    internal_source_key: "not copied",
  });

  const retired = buildRetired({ sourceRecords: [source], excluded: ["200"] });

  assert.deepEqual(retired, [
    {
      id: "200",
      name: "Only in source",
      dimension_ids: ["load", "reps"],
      category_id: "cat-legs",
      equipment_ids: ["barbell"],
      focus_ids: ["focus-for-200"],
      notes: null,
      updated_at: "2026-06-29T00:00:00Z",
      retired_at: retiredStamp,
      source_attribution: { source: "wger" },
    },
  ]);
  assert.deepEqual(Object.keys(retired[0]), [
    "id",
    "name",
    "dimension_ids",
    "category_id",
    "equipment_ids",
    "focus_ids",
    "notes",
    "updated_at",
    "retired_at",
    "source_attribution",
  ]);
});

test("retired record omits source_attribution where the source has none", () => {
  const { source_attribution: _attribution, ...source } = exerciseRecord("a");

  const [record] = buildRetired({ sourceRecords: [source], excluded: ["a"] });

  assert.equal("source_attribution" in record, false);
});

test("retired list is sorted by id across carried and new records", () => {
  const retired = buildRetired({
    previousSeed: {
      exercises: [],
      retired_exercises: [
        retiredExerciseRecord("b"),
        retiredExerciseRecord("d"),
      ],
    },
    sourceRecords: [exerciseRecord("c"), exerciseRecord("a")],
    excluded: ["c"],
    merged: ["a"],
  });

  assert.deepEqual(
    retired.map((record) => record.id),
    ["a", "b", "c", "d"],
  );
});

test("retired list treats a null previous seed and a missing key as empty", () => {
  const source = exerciseRecord("a");
  const fromNull = buildRetired({
    previousSeed: null,
    sourceRecords: [source],
    excluded: ["a"],
  });
  const fromSeedWithoutKey = buildRetired({
    previousSeed: { exercises: [exerciseRecord("a")] },
    sourceRecords: [source],
    excluded: ["a"],
  });

  assert.deepEqual(
    fromNull.map((record) => record.id),
    ["a"],
  );
  assert.deepEqual(
    fromSeedWithoutKey.map((record) => record.id),
    ["a"],
  );
});

test("retired list fails for a previous id in neither new list", () => {
  assert.throws(
    () =>
      buildRetired({
        previousSeed: { exercises: [exerciseRecord("gone")] },
      }),
    /Exercise gone from the previous seed is neither live nor retired/,
  );
});

test("retired list fails for an id in both new lists", () => {
  assert.throws(
    () =>
      buildRetired({
        previousSeed: {
          exercises: [],
          retired_exercises: [retiredExerciseRecord("back")],
        },
        live: [exerciseRecord("back")],
      }),
    /Exercise back is both live and retired/,
  );
  assert.throws(
    () =>
      buildRetired({
        sourceRecords: [exerciseRecord("both")],
        live: [exerciseRecord("both")],
        merged: ["both"],
      }),
    /Exercise both is both live and retired/,
  );
});

test("retired list fails for a new id with no previous seed or source record", () => {
  assert.throws(
    () => buildRetired({ excluded: ["missing"] }),
    /Newly retired exercise missing has no previous seed or source record/,
  );
});

test("retired list fails for an invalid or missing retiredAt, even with nothing to retire", () => {
  for (const retiredAt of ["not-a-timestamp", "", null]) {
    assert.throws(
      () => buildRetired({ retiredAt }),
      /valid retiredAt timestamp/,
    );
  }
  assert.throws(
    () =>
      buildRetiredExercises({
        previousSeed: null,
        sourceRecords: [],
        cleanup: { exercises: [], excludedIds: new Set(), redirects: new Map() },
        reviewedAt: retiredReviewedAt,
        categories: retiredCategories,
        focusIdsFor: () => [],
      }),
    /valid retiredAt timestamp/,
  );
});

test("retired list fails when a new retirement's retiredAt is not later than reviewedAt", () => {
  for (const retiredAt of [retiredReviewedAt, "2026-07-01T00:00:00.000Z"]) {
    assert.throws(
      () =>
        buildRetired({
          sourceRecords: [
            exerciseRecord("a", { updated_at: "2026-01-01T00:00:00Z" }),
          ],
          excluded: ["a"],
          retiredAt,
        }),
      /retiredAt .* must be later than reviewedAt .* to retire a/,
    );
  }
});

test("rename-only run accepts a retiredAt older than reviewedAt", () => {
  const carried = retiredExerciseRecord("old");

  const retired = buildRetired({
    previousSeed: {
      exercises: [exerciseRecord("live")],
      retired_exercises: [carried],
    },
    live: [exerciseRecord("live", { name: "Renamed by review" })],
    excluded: ["old"],
    retiredAt: "2026-01-01T00:00:00.000Z",
  });

  assert.deepEqual(retired, [carried]);
});

test("retired list fails when a live id's dimensions changed", () => {
  assert.throws(
    () =>
      buildRetired({
        previousSeed: { exercises: [exerciseRecord("a")] },
        live: [exerciseRecord("a", { dimension_ids: ["reps"] })],
      }),
    /Live exercise a changed dimension_ids/,
  );
});

test("retired list fails for an unknown category, carried or new", () => {
  assert.throws(
    () =>
      buildRetired({
        sourceRecords: [exerciseRecord("a", { category_id: "cat-gone" })],
        excluded: ["a"],
      }),
    /Retired exercise a names unknown category cat-gone/,
  );
  assert.throws(
    () =>
      buildRetired({
        previousSeed: {
          exercises: [],
          retired_exercises: [
            retiredExerciseRecord("b", { category_id: "cat-gone" }),
          ],
        },
      }),
    /Retired exercise b names unknown category cat-gone/,
  );
});

test("retired list fails when retired_at is not later than updated_at", () => {
  // The same instant in the two forms the seed uses: a string comparison would
  // call retired_at the later one, because "Z" sorts after ".".
  assert.throws(
    () =>
      buildRetired({
        sourceRecords: [
          exerciseRecord("a", { updated_at: "2026-11-05T00:00:00.000Z" }),
        ],
        excluded: ["a"],
        retiredAt: "2026-11-05T00:00:00Z",
      }),
    /Retired exercise a has retired_at .* not later than updated_at/,
  );
  assert.throws(
    () =>
      buildRetired({
        previousSeed: {
          exercises: [],
          retired_exercises: [
            retiredExerciseRecord("b", {
              updated_at: "2026-09-01T00:00:00Z",
            }),
          ],
        },
      }),
    /Retired exercise b has retired_at .* not later than updated_at/,
  );
});

test("focusIdsForRetired returns rule Focuses in starter-Focus order", () => {
  const focusId = (key) => platformFocuses.find((entry) => entry.key === key).id;

  // A sled push reaches Functional before Weights in the rule, but Weights comes
  // first in starter-Focus order.
  assert.deepEqual(
    focusIdsForRetired(
      {
        name: "Barbell Sled Push",
        dimension_ids: ["load", "distance"],
        equipment_ids: ["sled"],
      },
      "Legs",
    ),
    [focusId("weights"), focusId("functional")],
  );
  // "Deadlift" is a Weights starter by name; no starter lookup means a retired
  // record with no load or weights equipment does not pick it up.
  assert.deepEqual(
    focusIdsForRetired(
      { name: "Deadlift", dimension_ids: ["reps"], equipment_ids: [] },
      "Legs",
    ),
    [focusId("calisthenics")],
  );
});
