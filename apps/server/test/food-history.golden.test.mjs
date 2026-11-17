import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";

import { buildFoodHistory } from "../src/food-history.ts";

// The app runs the same vectors (apps/mobile/test/domain/food_history_golden_test.dart),
// so an agent and the add-food picker see the user's Foods in the same order.
test("Food History matches the shared golden vectors", async () => {
  const vectorsUrl = new URL("../../../packages/golden-vectors/vectors/", import.meta.url);
  const filenames = (await readdir(vectorsUrl)).filter(
    (name) => name.endsWith(".json") && !name.endsWith(".schema.json")
  );

  let casesRun = 0;
  for (const filename of filenames) {
    const vector = JSON.parse(await readFile(new URL(filename, vectorsUrl), "utf8"));
    if (vector.domain !== "food-history") {
      continue;
    }
    for (const { name, input, expected } of vector.cases) {
      const actual = buildFoodHistory({
        entries: input.entries,
        meals: input.meals,
        archivedUserFoodIds: input.archivedUserFoodIds,
        now: new Date(input.now)
      }).map(({ foodSource, foodId, recentCount, lastLoggedAt, lastPortion }) => ({
        foodSource,
        foodId,
        recentCount,
        lastLoggedAt,
        lastPortion
      }));
      assert.deepEqual(actual, expected, `${filename}: ${name}`);
      casesRun += 1;
    }
  }
  assert.ok(casesRun > 0, "no food-history golden vector case ran");
});
