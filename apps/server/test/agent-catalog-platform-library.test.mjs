import assert from "node:assert/strict";
import test from "node:test";

import {
  CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS,
  buildPlatformCatalogExercises,
  resolvePlatformExerciseId,
  toAgentCatalogExerciseFromPayload,
} from "../src/index.ts";

test("the server Platform Library is derived from the bundled wger seed with app-parity loadMode/recordProfile", () => {
  const platform = buildPlatformCatalogExercises();

  assert.ok(platform.length > 500, "expected the full wger seed to load");

  // Every platform row is added-load with a derived recordProfile and no owner.
  for (const exercise of platform) {
    assert.equal(exercise.library, "platform");
    assert.equal(exercise.ownerUserId, null);
    assert.equal(exercise.loadMode, "added");
    assert.equal(exercise.active, true);
    assert.equal(exercise.favorite, false);
    assert.equal(exercise.shadowedPlatformExerciseId, null);
    assert.ok(exercise.category.id.length > 0);
    assert.ok(exercise.category.name.length > 0);
  }

  // A canonical cardio activity resolves to distance+duration -> fastestPace,
  // exactly as the app materializes it.
  const trailRunning = platform.find(
    (exercise) =>
      exercise.id === CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.trailRunning,
  );
  assert.ok(trailRunning, "Trail Running should be in the seed");
  assert.deepEqual(trailRunning.dimensions, ["distance", "duration"]);
  assert.equal(trailRunning.recordProfile, "fastestPace");

  // A load+reps strength exercise derives repMax.
  const strength = platform.find(
    (exercise) =>
      exercise.dimensions.includes("load") &&
      exercise.dimensions.includes("reps"),
  );
  assert.ok(strength, "expected at least one load+reps exercise");
  assert.equal(strength.recordProfile, "repMax");
});

test("reviewed Platform exercise ids resolve to their canonical records", () => {
  const removedId = "01910000-0000-7000-8000-000000200184";
  const canonicalId = "01910000-0000-7000-8000-000000000103";

  assert.equal(resolvePlatformExerciseId(removedId), canonicalId);
  assert.equal(resolvePlatformExerciseId(canonicalId), canonicalId);
  assert.ok(
    buildPlatformCatalogExercises().some(
      (exercise) => exercise.id === resolvePlatformExerciseId(removedId),
    ),
  );
});

test("a synced exercise payload maps to an AgentCatalogExercise mirroring the app snapshot", () => {
  const exercise = toAgentCatalogExerciseFromPayload({
    ownerUserId: "user-1",
    deletedAt: null,
    payload: {
      id: "user-back-squat",
      library_origin: "user",
      name: "Back Squat",
      dimension_ids: JSON.stringify(["load", "reps"]),
      default_load_unit: "kilogram",
      load_mode: "added",
      record_profile: "repMax",
      is_favorite: true,
      is_unilateral: false,
      uses_rpe: false,
      category_id: "cat-1",
      equipment_ids: JSON.stringify(["barbell"]),
      notes: null,
      updated_at: "2025-06-30T08:00:00.000Z",
      deleted_at: null,
    },
    categoryName: "Strength",
  });

  assert.equal(exercise.id, "user-back-squat");
  assert.equal(exercise.library, "user");
  assert.equal(exercise.ownerUserId, "user-1");
  assert.equal(exercise.name, "Back Squat");
  assert.deepEqual(exercise.dimensions, ["load", "reps"]);
  assert.deepEqual(exercise.equipment, ["barbell"]);
  assert.equal(exercise.loadMode, "added");
  assert.equal(exercise.recordProfile, "repMax");
  assert.equal(exercise.favorite, true);
  assert.equal(exercise.active, true);
  assert.equal(exercise.category.id, "cat-1");
  assert.equal(exercise.category.name, "Strength");
});

test("an archived (deletedAt) exercise payload maps to active: false", () => {
  const exercise = toAgentCatalogExerciseFromPayload({
    ownerUserId: "user-1",
    deletedAt: new Date("2025-06-30T13:00:00.000Z"),
    payload: {
      id: "user-archived-curl",
      library_origin: "user",
      name: "Curl",
      dimension_ids: JSON.stringify(["load", "reps"]),
      load_mode: "added",
      record_profile: "repMax",
      is_favorite: true,
      category_id: "cat-arms",
      equipment_ids: JSON.stringify([]),
      updated_at: "2025-06-30T13:00:00.000Z",
      deleted_at: "2025-06-30T13:00:00.000Z",
    },
    categoryName: "Arms",
  });

  assert.equal(exercise.active, false);
  assert.equal(exercise.favorite, true);
  assert.deepEqual(exercise.equipment, []);
});
