#!/usr/bin/env node
// Generates the server-side USDA Food seed module from the SAME bundled USDA
// FoodData Central seed artifact the app uses:
//   apps/mobile/assets/seeds/usda_foods.json
//
// The production server image only copies apps/server (see Dockerfile), so the
// mobile asset never ships alongside the server. To keep the USDA reference
// data available server-side without a runtime cross-package file read, we
// emit a committed TypeScript module that compiles into dist/ as part of the
// module graph — mirrors tools/generate-server-platform-exercise-seed.mjs
// exactly, one seed file per bundled reference dataset. Re-run and
// commit the output whenever the mobile seed changes; a drift check guards it
// in CI.
//
// Usage: node tools/generate-server-usda-food-seed.mjs [--check]

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const repoRoot = new URL("../", import.meta.url);
const seedUrl = new URL(
  "apps/mobile/assets/seeds/usda_foods.json",
  repoRoot
);
const outputUrl = new URL(
  "apps/server/src/data/usda-food-seed.generated.ts",
  repoRoot
);

function build() {
  const seed = JSON.parse(readFileSync(seedUrl, "utf8"));

  const metadata = {
    datasetVersion: String(seed.metadata.dataset_version),
    sourceName: String(seed.metadata.source_name),
    sourceUrl: String(seed.metadata.source_url),
    licenseName: String(seed.metadata.license_name),
    attributionText: String(seed.metadata.attribution_text)
  };

  const foods = (seed.foods ?? []).map((food) => ({
    id: String(food.id),
    name: String(food.name),
    isLiquid: Boolean(food.is_liquid),
    servingLabel: food.serving_label === null ? null : String(food.serving_label),
    servingSize:
      food.serving_size === null || food.serving_size === undefined
        ? null
        : Number(food.serving_size),
    packageSize:
      food.package_size === null || food.package_size === undefined
        ? null
        : Number(food.package_size),
    nutrientsPer100: food.nutrients_per_100
  }));

  const header = `// GENERATED FILE — do not edit by hand.
// Regenerate with: node tools/generate-server-usda-food-seed.mjs
//
// Source: apps/mobile/assets/seeds/usda_foods.json (USDA
// FoodData Central, CC0/public domain). The agent Platform Food search
// (GET /agent/foods/platform-search) serves the SAME bundled dataset the app
// ships, so an agent and the app see identical USDA results. Keep this in sync
// with the mobile seed — the server contract-drift gate re-runs the generator
// and diffs the result.

export type UsdaFoodSeedMetadata = {
  datasetVersion: string;
  sourceName: string;
  sourceUrl: string;
  licenseName: string;
  attributionText: string;
};

export type UsdaFoodSeedNutrientAmount = {
  status: "complete" | "unknown";
  value: number | null;
  entered: string | null;
  unit: string;
};

export type UsdaFoodSeedFood = {
  id: string;
  name: string;
  isLiquid: boolean;
  servingLabel: string | null;
  servingSize: number | null;
  packageSize: number | null;
  nutrientsPer100: Record<string, UsdaFoodSeedNutrientAmount>;
};

export const USDA_FOOD_SEED_METADATA: UsdaFoodSeedMetadata =
`;

  const body =
    header +
    JSON.stringify(metadata, null, 2) +
    ";\n\nexport const USDA_FOOD_SEED_FOODS: readonly UsdaFoodSeedFood[] =\n" +
    JSON.stringify(foods, null, 2) +
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
        `Server USDA Food seed is stale. Run:\n  node ${fileURLToPath(new URL("generate-server-usda-food-seed.mjs", import.meta.url))}`
      );
      process.exit(1);
    }
    console.log("Server USDA Food seed is up to date.");
    return;
  }

  writeFileSync(outputUrl, generated);
  console.log(`Wrote ${fileURLToPath(outputUrl)}`);
}

main();
