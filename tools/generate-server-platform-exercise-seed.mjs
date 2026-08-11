#!/usr/bin/env node
// Generates the server-side Platform Exercise Library seed module from the
// SAME bundled wger seed artifact the app uses:
//   apps/mobile/assets/seeds/platform_exercises.json
//
// The production server image only copies apps/server (see Dockerfile), so the
// mobile asset never ships alongside the server. To keep the Platform Library
// available server-side without a runtime cross-package file read, we emit a
// committed TypeScript module that compiles into dist/ as part of the module
// graph. The generator keeps ONLY the fields the agent catalog needs (id, name,
// dimension_ids, category_id, equipment_ids) plus categories — the heavy
// per-record source_attribution/license metadata is dropped. Re-run and commit
// the output whenever the mobile seed changes; a drift check guards it in CI.
//
// Usage: node tools/generate-server-platform-exercise-seed.mjs [--check]

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const repoRoot = new URL("../", import.meta.url);
const seedUrl = new URL(
  "apps/mobile/assets/seeds/platform_exercises.json",
  repoRoot
);
const outputUrl = new URL(
  "apps/server/src/data/platform-exercise-seed.generated.ts",
  repoRoot
);

function build() {
  const seed = JSON.parse(readFileSync(seedUrl, "utf8"));

  const categories = (seed.categories ?? []).map((category) => ({
    id: String(category.id),
    name: String(category.name)
  }));

  const exercises = (seed.exercises ?? []).map((exercise) => ({
    id: String(exercise.id),
    name: String(exercise.name),
    dimensionIds: (exercise.dimension_ids ?? []).map(String),
    categoryId:
      exercise.category_id === null || exercise.category_id === undefined
        ? null
        : String(exercise.category_id),
    equipmentIds: (exercise.equipment_ids ?? []).map(String)
  }));
  const redirects = (seed.exercise_redirects ?? []).map((redirect) => ({
    fromExerciseId: String(redirect.from_exercise_id),
    toExerciseId: String(redirect.to_exercise_id)
  }));

  const header = `// GENERATED FILE — do not edit by hand.
// Regenerate with: node tools/generate-server-platform-exercise-seed.mjs
//
// Source: apps/mobile/assets/seeds/platform_exercises.json (wger).
// Only the fields the agent Exercise catalog needs are retained; the Platform
// Library is derived identically to the app (loadMode "added", recordProfile via
// defaultRecordProfileFor). Keep this in sync with the mobile seed — the
// server contract-drift gate re-runs the generator and diffs the result.

import type { DimensionId } from "../analytics/exercise-analytics.js";

export type PlatformSeedCategory = {
  id: string;
  name: string;
};

export type PlatformSeedExercise = {
  id: string;
  name: string;
  dimensionIds: DimensionId[];
  categoryId: string | null;
  equipmentIds: string[];
};

export type PlatformSeedExerciseRedirect = {
  fromExerciseId: string;
  toExerciseId: string;
};

export const PLATFORM_EXERCISE_SEED_CATEGORIES: readonly PlatformSeedCategory[] =
`;

  const body =
    header +
    JSON.stringify(categories, null, 2) +
    ";\n\nexport const PLATFORM_EXERCISE_SEED_EXERCISES: readonly PlatformSeedExercise[] =\n" +
    JSON.stringify(exercises, null, 2) +
    ";\n\nexport const PLATFORM_EXERCISE_SEED_REDIRECTS: readonly PlatformSeedExerciseRedirect[] =\n" +
    JSON.stringify(redirects, null, 2) +
    ";\n";

  return body;
}

function main() {
  const check = process.argv.includes("--check");
  const generated = build();

  if (check) {
    const existing = readFileSync(outputUrl, "utf8");
    if (existing !== generated) {
      console.error(
        `Server Platform Exercise seed is stale. Run:\n  node ${fileURLToPath(new URL("generate-server-platform-exercise-seed.mjs", import.meta.url))}`
      );
      process.exit(1);
    }
    console.log("Server Platform Exercise seed is up to date.");
    return;
  }

  writeFileSync(outputUrl, generated);
  console.log(`Wrote ${fileURLToPath(outputUrl)}`);
}

main();
