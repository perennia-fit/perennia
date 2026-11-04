import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";

import { buildMealHistory } from "../src/meal-history.ts";

// The app runs the same vectors (apps/mobile/test/domain/meal_history_golden_test.dart)
// through NutritionRepository.listMealHistory, so an agent and Your meals see
// the same meals in the same order.
test("Meal History matches the shared golden vectors", async () => {
  const vectorsUrl = new URL("../../../packages/golden-vectors/vectors/", import.meta.url);
  const filenames = (await readdir(vectorsUrl)).filter(
    (name) => name.endsWith(".json") && !name.endsWith(".schema.json")
  );

  let casesRun = 0;
  for (const filename of filenames) {
    const vector = JSON.parse(await readFile(new URL(filename, vectorsUrl), "utf8"));
    if (vector.domain !== "meal-history") {
      continue;
    }
    assert.equal(vector.schemaVersion, 1, filename);
    assert.equal(vector.schema, "m38-meal-history.schema.json", filename);
    for (const { name, input, expected } of vector.cases) {
      const actual = buildMealHistory(
        {
          meals: input.meals,
          entries: input.entries,
          archivedUserFoodIds: input.archivedUserFoodIds
        },
        { now: new Date(input.now), limit: input.limit }
      );
      assert.deepEqual(actual, expected, `${filename}: ${name}`);
      casesRun += 1;
    }
  }
  assert.ok(casesRun > 0, "no meal-history golden vector case ran");
});

test("a Meal without a time precision reads as instant", () => {
  const history = buildMealHistory(
    {
      meals: [{ id: "m-legacy", startedAt: "2026-10-30T08:00:00.000Z", deletedAt: null }],
      entries: [
        {
          id: "e0",
          mealId: "m-legacy",
          kind: "food",
          position: 0,
          foodSource: "usda",
          foodId: "banana",
          isLiquid: false,
          name: "Banana",
          deletedAt: null
        },
        {
          id: "e1",
          mealId: "m-legacy",
          kind: "food",
          position: 1,
          foodSource: "user",
          foodId: "porridge",
          isLiquid: false,
          name: "Porridge",
          deletedAt: null
        }
      ],
      archivedUserFoodIds: []
    },
    { now: new Date("2026-11-01T12:00:00.000Z"), limit: 20 }
  );
  assert.deepEqual(
    history.map((item) => [item.lastMealId, item.count]),
    [["m-legacy", 1]]
  );
});
