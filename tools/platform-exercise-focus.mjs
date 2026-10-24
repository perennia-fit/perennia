#!/usr/bin/env node
// Assigns every Platform Library exercise to the starter Focuses (Weights,
// Endurance, Functional, Calisthenics, Mobility) and writes them into the
// bundled seed, apps/mobile/assets/seeds/platform_exercises.json.
//
// The assignment is rule-based so it can be re-run whenever the seed is
// regenerated, and reviewable: every rule reads the exercise's name, Category,
// Dimensions, and Equipment, the same facts a person would use. Where a rule
// gets an exercise wrong, add a hand decision to
// tools/data/platform-exercise-focus-overrides.json instead of bending a rule
// around one name. An override replaces the rule result for that exercise.
//
// The seed generator (tools/generate-wger-platform-exercises.mjs) calls
// `applyPlatformExerciseFocuses`. Because regenerating the whole seed needs a
// wger checkout, this file is also a CLI that applies the Focuses to the
// committed seed in place:
//
//   node tools/platform-exercise-focus.mjs          rewrite the seed
//   node tools/platform-exercise-focus.mjs --check  fail if the seed is stale

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

// Seeded on every device with these fixed ids, mirroring the seeded
// Categories, so a Focus means the same thing on every device before sync.
export const platformFocuses = [
  focus("01910000-0000-7000-8000-000000000401", "weights", "Weights", 0),
  focus("01910000-0000-7000-8000-000000000402", "endurance", "Endurance", 1),
  focus("01910000-0000-7000-8000-000000000403", "functional", "Functional", 2),
  focus(
    "01910000-0000-7000-8000-000000000404",
    "calisthenics",
    "Calisthenics",
    3,
  ),
  focus("01910000-0000-7000-8000-000000000405", "mobility", "Mobility", 4),
];

// The staples each starter Focus offers first, before the user has logged
// anything under it, so a first Weights workout opens on the squat and the
// bench press rather than the alphabet's first entry. By exact seed name; a
// missing name fails the run instead of silently shrinking the list. A
// staple always belongs to its Focus.
const starterExerciseNames = {
  weights: [
    "Barbell Squat",
    "Bench Press",
    "Deadlift",
    "Overhead Press",
    "Bent Over Barbell Rows",
    "Romanian Deadlift",
    "Leg Press",
    "Hip Thrust",
  ],
  endurance: [
    "Run",
    "Rowing Machine",
    "Indoor Cycling",
    "SkiErg",
    "Pool Swim",
    "Walking",
    "Stair Master",
    "Jump Rope",
  ],
  functional: [
    "Sled Push",
    "Wall balls",
    "Burpees",
    "Farmer's Walk",
    "Kettlebell Swing",
    "Rowing Machine",
    "SkiErg",
    "Box Jump",
    "Thruster",
    "Walking Lunges",
  ],
  calisthenics: [
    "Pull-Up",
    "Push-Ups",
    "Dips",
    "Chin-ups",
    "Plank",
    "Hanging Leg Raises",
    "Pistol Squat",
    "L-Sit",
  ],
  mobility: [
    "Mobility Flow",
    "Hip Flexor Stretch",
    "Downward Facing Dog Pose",
    "Yoga exercise: Cow-cat",
    "Frog Stretch",
    "Foam Roller Adductors",
  ],
};

const focusUpdatedAt = "2026-10-24T00:00:00Z";
const focusIdByKey = new Map(platformFocuses.map((entry) => [entry.key, entry.id]));

const enduranceCategories = new Set(["Cardio", "Running", "Cycling", "Swimming"]);

const enduranceName =
  /\b(run|running|jog|jogging|walk|walking|hike|ruck|cycl\w*|bike|biking|swim\w*|rowing machine|rower|ski ?erg|ski machine|elliptical\w*|treadmill|stair ?master|climbmill|skipping|jump rope|hand bike|zone 2|sprints?)\b/i;
// Outside the endurance Categories, only names that can only mean a
// sustained machine or rope effort count; "walk" alone also names lunges and
// band drills.
const enduranceMachineName =
  /\b(treadmill|jogging|rowing machine|rower|elliptical|jump rope|skipping|stationary bike|spin bike|air ?bike|assault bike|ski ?erg)\b/i;
const notEnduranceName = /\b(lunges?|crunch\w*|bear|band|lateral|plyometrics?)\b/i;

const functionalName =
  /\b(sled|wall ?balls?|burpees?|farmer'?s?|carry|carries|yoke|sandbag|thrusters?|box jumps?|battle ropes?|ball slams?|slams?|devil press|turkish get[- ]?up|atlas|keg|tire|ski ?erg|ski machine|rowing machine|bear crawl|mountain climbers?|clean|cleans|snatch\w*|jerk|walking lunges?|broad jumps?|(kettlebell|dumbbell|russian|american) swings?)\b/i;
const medicineBallFunctionalName = /\b(throw|slam|pass|chop|toss|wall ?ball)\b/i;
const functionalEquipment = new Set(["sled", "sandbag"]);

const weightsEquipment = new Set([
  "barbell",
  "dumbbell",
  "kettlebell",
  "cable",
  "machine",
  "smithMachine",
  "ezBar",
  "plate",
  "inclineBench",
  "band",
  "bosu",
]);
const weightsName =
  /\b(machine|cable|weighted|plate|dumbbells?|barbell|kettlebell|smith|ez[- ]?bar)\b/i;

const calisthenicsEquipment = new Set([
  "bodyweight",
  "pullUpBar",
  "wall",
  "gymMat",
  "trx",
  "step",
  "bench",
  "box",
  "medicineBall",
  "swissBall",
  "rope",
]);
const calisthenicsName =
  /\b(push[- ]?ups?|press[- ]?ups?|pull[- ]?ups?|chin[- ]?ups?|dips?|muscle[- ]?ups?|planks?|l[- ]?sit|handstand|pistol|planche|lever|hollow|sit[- ]?ups?|crunch\w*|leg raises?|v[- ]?ups?|burpees?|bodyweight|air squats?|rope climbs?|skin the cat|inverted rows?|australian)\b/i;

const mobilityName =
  /\b(stretch\w*|yoga|pose|flow|mobility|foam roll\w*|warm[- ]?up|cool[- ]?down|circles|rotations?|asana|cat[- ]cow|cow[- ]cat|child'?s pose|pigeon|virabhadrasana|leg swings?|arm swings?)\b/i;

/**
 * Returns the Focus keys for one exercise from its own facts.
 *
 * Mobility and Endurance end the decision early: a stretch is not also a
 * Weights exercise because it uses a band, and a treadmill is not also
 * Calisthenics because it needs no weight.
 */
export function focusKeysFor(exercise, categoryName) {
  const name = String(exercise.name ?? "");
  const dimensions = new Set(exercise.dimension_ids ?? []);
  const equipment = new Set(exercise.equipment_ids ?? []);
  const keys = new Set();

  // A band that assists a bodyweight movement (band-assisted pull-ups and
  // push-ups) does not make it a Weights exercise.
  const isBandAssistedBodyweight =
    calisthenicsName.test(name) &&
    !dimensions.has("load") &&
    [...equipment].every((id) => id === "band" || calisthenicsEquipment.has(id));
  const isLoaded =
    !isBandAssistedBodyweight &&
    (dimensions.has("load") ||
      [...equipment].some((id) => weightsEquipment.has(id)) ||
      weightsName.test(name));

  if (
    categoryName === "Mobility" ||
    equipment.has("foamRoll") ||
    (mobilityName.test(name) && !dimensions.has("load") && !weightsName.test(name))
  ) {
    keys.add("mobility");
    return keys;
  }

  const inEnduranceCategory = enduranceCategories.has(categoryName);
  if (
    (inEnduranceCategory && enduranceName.test(name)) ||
    (enduranceMachineName.test(name) && !notEnduranceName.test(name))
  ) {
    keys.add("endurance");
  }

  if (
    functionalName.test(name) ||
    [...equipment].some((id) => functionalEquipment.has(id)) ||
    (equipment.has("medicineBall") && medicineBallFunctionalName.test(name))
  ) {
    keys.add("functional");
  }
  // Conditioning work filed under Cardio that is not a sustained effort
  // (high knees, bag work, broncos) is a Functional station.
  if (inEnduranceCategory && !keys.has("endurance")) {
    keys.add("functional");
  }
  if (keys.has("endurance")) {
    return keys;
  }

  if (isLoaded && !inEnduranceCategory) {
    keys.add("weights");
  }
  const usesOnlyBodyweightEquipment = [...equipment].every((id) =>
    calisthenicsEquipment.has(id),
  );
  const measuresWork =
    dimensions.has("reps") || dimensions.has("duration") || dimensions.has("distance");
  if (
    !isLoaded &&
    !inEnduranceCategory &&
    measuresWork &&
    usesOnlyBodyweightEquipment
  ) {
    keys.add("calisthenics");
  }
  if (calisthenicsName.test(name) && !isLoaded) {
    keys.add("calisthenics");
  }
  return keys;
}

/**
 * Adds `focus_ids` to every exercise, in starter-Focus order, and returns the
 * Focus list to write beside the Categories.
 */
export function applyPlatformExerciseFocuses(exercises, categories, overrides = {}) {
  const categoryNameById = new Map(
    categories.map((category) => [category.id, category.name]),
  );
  const overrideKeysById = new Map(
    Object.entries(overrides.exercises ?? {}).map(([id, keys]) => {
      for (const key of keys) {
        if (!focusIdByKey.has(key)) {
          throw new Error(`Focus override for ${id} names unknown Focus "${key}".`);
        }
      }
      return [id, new Set(keys)];
    }),
  );
  const exerciseIds = new Set(exercises.map((exercise) => exercise.id));
  for (const id of overrideKeysById.keys()) {
    if (!exerciseIds.has(id)) {
      throw new Error(`Focus override names missing exercise ${id}.`);
    }
  }

  const exerciseIdByName = new Map();
  for (const exercise of exercises) {
    const key = String(exercise.name).toLowerCase();
    if (!exerciseIdByName.has(key)) exerciseIdByName.set(key, exercise.id);
  }
  const starterIdsByFocusKey = new Map();
  const starterFocusKeysByExerciseId = new Map();
  for (const [focusKey, names] of Object.entries(starterExerciseNames)) {
    const ids = names.map((name) => {
      const id = exerciseIdByName.get(name.toLowerCase());
      if (!id) {
        throw new Error(`Starter exercise "${name}" for ${focusKey} is not in the seed.`);
      }
      const keys = starterFocusKeysByExerciseId.get(id) ?? new Set();
      keys.add(focusKey);
      starterFocusKeysByExerciseId.set(id, keys);
      return id;
    });
    starterIdsByFocusKey.set(focusKey, ids);
  }

  const withFocuses = exercises.map((exercise) => {
    const keys = new Set(
      overrideKeysById.get(exercise.id) ??
        focusKeysFor(exercise, categoryNameById.get(exercise.category_id)),
    );
    for (const key of starterFocusKeysByExerciseId.get(exercise.id) ?? []) {
      keys.add(key);
    }
    const focusIds = platformFocuses
      .filter((entry) => keys.has(entry.key))
      .map((entry) => entry.id);
    return withFocusIdsAfterEquipment(exercise, focusIds);
  });

  return {
    exercises: withFocuses,
    focuses: platformFocuses.map(({ id, key, name, sort_order }) => ({
      id,
      name,
      sort_order,
      starter_exercise_ids: starterIdsByFocusKey.get(key) ?? [],
      updated_at: focusUpdatedAt,
    })),
  };
}

// Keeps `focus_ids` beside `equipment_ids` so a seed diff reads per exercise.
function withFocusIdsAfterEquipment(exercise, focusIds) {
  const next = {};
  let placed = false;
  for (const [key, value] of Object.entries(exercise)) {
    if (key === "focus_ids") continue;
    next[key] = value;
    if (key === "equipment_ids") {
      next.focus_ids = focusIds;
      placed = true;
    }
  }
  if (!placed) next.focus_ids = focusIds;
  return next;
}

// Places `focuses` right after `categories` in the seed object.
export function withSeedFocuses(seed, overrides) {
  const applied = applyPlatformExerciseFocuses(
    seed.exercises ?? [],
    seed.categories ?? [],
    overrides,
  );
  const next = {};
  for (const [key, value] of Object.entries(seed)) {
    if (key === "focuses") continue;
    next[key] = key === "exercises" ? applied.exercises : value;
    if (key === "categories") next.focuses = applied.focuses;
  }
  if (!("focuses" in next)) next.focuses = applied.focuses;
  return next;
}

export function readPlatformExerciseFocusOverrides() {
  return JSON.parse(readFileSync(overridesUrl, "utf8"));
}

function focus(id, key, name, sortOrder) {
  return { id, key, name, sort_order: sortOrder };
}

const repoRoot = new URL("../", import.meta.url);
const seedUrl = new URL("apps/mobile/assets/seeds/platform_exercises.json", repoRoot);
const overridesUrl = new URL(
  "tools/data/platform-exercise-focus-overrides.json",
  repoRoot,
);

function main() {
  const check = process.argv.includes("--check");
  const current = readFileSync(seedUrl, "utf8");
  const next = `${JSON.stringify(
    withSeedFocuses(JSON.parse(current), readPlatformExerciseFocusOverrides()),
    null,
    2,
  )}\n`;
  if (check) {
    if (next !== current) {
      console.error(
        "platform_exercises.json Focuses are stale. Run: node tools/platform-exercise-focus.mjs",
      );
      process.exit(1);
    }
    console.log("platform_exercises.json Focuses are current.");
    return;
  }
  writeFileSync(seedUrl, next);
  const counts = new Map();
  for (const exercise of JSON.parse(next).exercises) {
    for (const id of exercise.focus_ids) counts.set(id, (counts.get(id) ?? 0) + 1);
  }
  console.log(
    platformFocuses
      .map((entry) => `${entry.name} ${counts.get(entry.id) ?? 0}`)
      .join(", "),
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
