import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { applyPlatformExerciseCleanup } from "../../../tools/platform-exercise-cleanup.mjs";

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
  const manifest = JSON.parse(
    readFileSync(
      new URL(
        "../../../tools/data/platform-exercise-review-decisions.json",
        import.meta.url,
      ),
      "utf8",
    ),
  );
  const seed = JSON.parse(
    readFileSync(
      new URL(
        "../../../apps/mobile/assets/seeds/platform_exercises.json",
        import.meta.url,
      ),
      "utf8",
    ),
  );
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
