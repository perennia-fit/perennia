import assert from "node:assert/strict";
import test from "node:test";

import {
  listFoodsFromRows,
  prepareAgentFoodBatchWrite,
  searchAgentPlatformFoods,
  toAgentFood
} from "../src/index.ts";

test("prepareAgentFoodBatchWrite snapshots a plain User Food, storing the full nutrient vector with unknowns explicit", () => {
  const result = prepareAgentFoodBatchWrite({
    request: {
      idempotencyKey: "food-batch-1",
      foods: [
        {
          id: "food-1",
          name: "Banana",
          nutrientsPer100: {
            energy: {
              status: "complete",
              value: 89,
              entered: "89",
              unit: "kilocalorie"
            },
            protein: {
              status: "complete",
              value: 1.1,
              entered: "1.1",
              unit: "gram"
            }
          },
          isLiquid: false,
          servingLabel: "medium",
          servingSize: 118,
          packageSize: null,
          recipeIngredients: null,
          recipeServingCount: null,
          deletedAt: null
        }
      ]
    },
    now: new Date("2026-07-04T00:00:00.000Z")
  });

  assert.equal(result.accepted, true);
  assert.equal(result.foods.length, 1);
  const payload = result.foods[0].payload;
  assert.equal(payload.name, "Banana");
  assert.equal(payload.food_source, "user");
  assert.equal(payload.is_liquid, false);
  assert.equal(payload.serving_size, 118);
  assert.equal(payload.recipe_ingredients_json, null);
  assert.equal(payload.recipe_serving_count, null);

  const nutrients = JSON.parse(payload.nutrient_values_json);
  assert.equal(nutrients.energy.status, "complete");
  assert.equal(nutrients.energy.value, 89);
  // Fiber was never supplied: stays an explicit unknown, never coerced to 0.
  assert.equal(nutrients.fiber.status, "unknown");
  assert.equal(nutrients.fiber.value, null);

  assert.equal(result.responseFoods[0].isRecipe, false);
  assert.equal(result.responseFoods[0].name, "Banana");
});

test("prepareAgentFoodBatchWrite snapshots a Recipe with its flat ingredient list, deriving nutrientsPer100/servingSize from the ingredients rather than trusting caller-supplied top-level values", () => {
  const result = prepareAgentFoodBatchWrite({
    request: {
      idempotencyKey: "food-batch-recipe",
      foods: [
        {
          id: "recipe-1",
          name: "Protein Oats",
          // Deliberately fabricated/implausible top-level facts: a correct
          // implementation must ignore these for a Recipe and derive from
          // recipeIngredients/recipeServingCount instead (CONTEXT.md: Recipe
          // nutrition "is derived from its ingredients").
          nutrientsPer100: {
            energy: {
              status: "complete",
              value: 999999,
              entered: "999999",
              unit: "kilocalorie"
            }
          },
          isLiquid: true,
          servingLabel: "bowl",
          servingSize: 250,
          packageSize: 500,
          recipeIngredients: [
            {
              foodId: "food-oats",
              name: "Oats",
              foodSource: "usda",
              nutrientsPer100: {
                energy: {
                  status: "complete",
                  value: 389,
                  entered: "389",
                  unit: "kilocalorie"
                }
              },
              isLiquid: false,
              portion: { value: 50, entered: "50", unit: "gram" },
              servingLabel: null,
              servingSize: null,
              packageSize: null
            }
          ],
          recipeServingCount: 2,
          deletedAt: null
        }
      ]
    },
    now: new Date("2026-07-04T00:00:00.000Z")
  });

  assert.equal(result.accepted, true);
  const payload = result.foods[0].payload;
  assert.equal(payload.recipe_serving_count, 2);
  const ingredients = JSON.parse(payload.recipe_ingredients_json);
  assert.equal(ingredients.length, 1);
  assert.equal(ingredients[0].food_id, "food-oats");
  assert.equal(ingredients[0].portion.value, 50);
  assert.equal(ingredients[0].nutrient_values.energy.value, 389);
  assert.equal(result.responseFoods[0].isRecipe, true);

  // Derived, not caller-supplied: single 50 g ingredient at 389 kcal/100g
  // means per-100 stays 389 kcal, and servingSize = totalBaseQuantity (50) /
  // servingCount (2) = 25 g/serving — mirrors deriveRecipeNutrition() in
  // apps/mobile/lib/domain/nutrition/nutrition.dart.
  const nutrients = JSON.parse(payload.nutrient_values_json);
  assert.equal(nutrients.energy.value, 389);
  assert.equal(payload.serving_size, 25);
  // Recipe shape is normalized like the app: not liquid, generic "serving"
  // label, no package size — a Recipe is never a liquid/package Food.
  assert.equal(payload.is_liquid, false);
  assert.equal(payload.serving_label, "serving");
  assert.equal(payload.package_size, null);
});

test("prepareAgentFoodBatchWrite derives a Recipe's nutrientsPer100 as the ingredient-weighted average across multiple ingredients", () => {
  const result = prepareAgentFoodBatchWrite({
    request: {
      idempotencyKey: "food-batch-recipe-multi",
      foods: [
        {
          id: "recipe-multi",
          name: "Oats and Banana",
          nutrientsPer100: {},
          isLiquid: false,
          servingLabel: null,
          servingSize: null,
          packageSize: null,
          recipeIngredients: [
            {
              foodId: "food-oats",
              name: "Oats",
              foodSource: "usda",
              nutrientsPer100: {
                energy: {
                  status: "complete",
                  value: 400,
                  entered: "400",
                  unit: "kilocalorie"
                }
              },
              isLiquid: false,
              portion: { value: 100, entered: "100", unit: "gram" },
              servingLabel: null,
              servingSize: null,
              packageSize: null
            },
            {
              foodId: "food-banana",
              name: "Banana",
              foodSource: "usda",
              nutrientsPer100: {
                energy: {
                  status: "complete",
                  value: 100,
                  entered: "100",
                  unit: "kilocalorie"
                }
              },
              isLiquid: false,
              portion: { value: 100, entered: "100", unit: "gram" },
              servingLabel: null,
              servingSize: null,
              packageSize: null
            }
          ],
          recipeServingCount: 1,
          deletedAt: null
        }
      ]
    },
    now: new Date("2026-07-04T00:00:00.000Z")
  });

  assert.equal(result.accepted, true);
  const payload = result.foods[0].payload;
  const nutrients = JSON.parse(payload.nutrient_values_json);
  // (400*100 + 100*100) / 200 total grams * 100 = 250 kcal/100g.
  assert.equal(nutrients.energy.value, 250);
  assert.equal(payload.serving_size, 200);
});

test("prepareAgentFoodBatchWrite marks a Recipe nutrient unknown (never zero-filled) when any ingredient is missing it", () => {
  const result = prepareAgentFoodBatchWrite({
    request: {
      idempotencyKey: "food-batch-recipe-missing-nutrient",
      foods: [
        {
          id: "recipe-missing",
          name: "Mixed Bowl",
          nutrientsPer100: {},
          isLiquid: false,
          servingLabel: null,
          servingSize: null,
          packageSize: null,
          recipeIngredients: [
            {
              foodId: "food-known",
              name: "Known Food",
              foodSource: "usda",
              nutrientsPer100: {
                fiber: {
                  status: "complete",
                  value: 5,
                  entered: "5",
                  unit: "gram"
                }
              },
              isLiquid: false,
              portion: { value: 100, entered: "100", unit: "gram" },
              servingLabel: null,
              servingSize: null,
              packageSize: null
            },
            {
              foodId: "food-unknown-fiber",
              name: "Unknown Fiber Food",
              foodSource: "usda",
              nutrientsPer100: {},
              isLiquid: false,
              portion: { value: 100, entered: "100", unit: "gram" },
              servingLabel: null,
              servingSize: null,
              packageSize: null
            }
          ],
          recipeServingCount: 1,
          deletedAt: null
        }
      ]
    },
    now: new Date("2026-07-04T00:00:00.000Z")
  });

  assert.equal(result.accepted, true);
  const payload = result.foods[0].payload;
  const nutrients = JSON.parse(payload.nutrient_values_json);
  assert.equal(nutrients.fiber.status, "unknown");
  assert.equal(nutrients.fiber.value, null);
});

test("prepareAgentFoodBatchWrite hard-rejects a Recipe ingredient whose portion resolves to a non-positive base quantity", () => {
  const result = prepareAgentFoodBatchWrite({
    request: {
      idempotencyKey: "food-batch-recipe-bad-portion",
      foods: [
        {
          id: "recipe-bad-portion",
          name: "Bad Portion Recipe",
          nutrientsPer100: {},
          isLiquid: false,
          servingLabel: null,
          servingSize: null,
          packageSize: null,
          recipeIngredients: [
            {
              foodId: "food-serving-based",
              name: "Serving Based",
              foodSource: "usda",
              nutrientsPer100: {},
              isLiquid: false,
              // "serving" unit but no servingSize snapshot on the ingredient
              // means the base quantity can't be resolved server-side.
              portion: { value: 1, entered: "1", unit: "serving" },
              servingLabel: null,
              servingSize: null,
              packageSize: null
            }
          ],
          recipeServingCount: 1,
          deletedAt: null
        }
      ]
    },
    now: new Date("2026-07-04T00:00:00.000Z")
  });

  assert.equal(result.accepted, false);
  assert.equal(result.errors[0].rule, "recipe_ingredient_portion_unavailable");
});

test("prepareAgentFoodBatchWrite hard-rejects a Recipe with zero ingredients", () => {
  const result = prepareAgentFoodBatchWrite({
    request: {
      idempotencyKey: "food-batch-bad-recipe",
      foods: [
        {
          id: "recipe-bad",
          name: "Empty Recipe",
          nutrientsPer100: {},
          isLiquid: false,
          servingLabel: null,
          servingSize: null,
          packageSize: null,
          recipeIngredients: [],
          recipeServingCount: 1,
          deletedAt: null
        }
      ]
    }
  });

  assert.equal(result.accepted, false);
  assert.equal(result.errors.length, 1);
  assert.equal(result.errors[0].rule, "recipe_requires_ingredients");
});

test("prepareAgentFoodBatchWrite hard-rejects a plain Food that carries a recipeServingCount", () => {
  const result = prepareAgentFoodBatchWrite({
    request: {
      idempotencyKey: "food-batch-bad-plain",
      foods: [
        {
          id: "food-bad",
          name: "Weird Food",
          nutrientsPer100: {},
          isLiquid: false,
          servingLabel: null,
          servingSize: null,
          packageSize: null,
          recipeIngredients: null,
          recipeServingCount: 3,
          deletedAt: null
        }
      ]
    }
  });

  assert.equal(result.accepted, false);
  assert.equal(result.errors[0].rule, "plain_food_forbids_serving_count");
});

test("prepareAgentFoodBatchWrite hard-rejects a negative nutrient value via the shared validator", () => {
  const result = prepareAgentFoodBatchWrite({
    request: {
      idempotencyKey: "food-batch-invalid-nutrient",
      foods: [
        {
          id: "food-invalid",
          name: "Bad Food",
          nutrientsPer100: {
            energy: {
              status: "complete",
              value: -5,
              entered: "-5",
              unit: "kilocalorie"
            }
          },
          isLiquid: false,
          servingLabel: null,
          servingSize: null,
          packageSize: null,
          recipeIngredients: null,
          recipeServingCount: null,
          deletedAt: null
        }
      ]
    }
  });

  assert.equal(result.accepted, false);
  assert.equal(result.errors[0].rule, "nutrient_non_negative");
  assert.equal(result.errors[0].foodId, "food-invalid");
});

test("prepareAgentFoodBatchWrite hard-rejects a duplicate Food id within one batch", () => {
  const food = {
    id: "food-dup",
    name: "Dup",
    nutrientsPer100: {},
    isLiquid: false,
    servingLabel: null,
    servingSize: null,
    packageSize: null,
    recipeIngredients: null,
    recipeServingCount: null,
    deletedAt: null
  };
  const result = prepareAgentFoodBatchWrite({
    request: { idempotencyKey: "food-batch-dup", foods: [food, food] }
  });

  assert.equal(result.accepted, false);
  assert.equal(result.errors[0].rule, "duplicate_food_id");
});

test("prepareAgentFoodBatchWrite passes a nullable deletedAt through as an LWW tombstone, never a purge", () => {
  const archivedAt = "2026-07-04T06:00:00.000Z";
  const result = prepareAgentFoodBatchWrite({
    request: {
      idempotencyKey: "food-batch-archive",
      foods: [
        {
          id: "food-archive",
          name: "Archived Food",
          nutrientsPer100: {},
          isLiquid: false,
          servingLabel: null,
          servingSize: null,
          packageSize: null,
          recipeIngredients: null,
          recipeServingCount: null,
          updatedAt: archivedAt,
          deletedAt: archivedAt
        }
      ]
    }
  });

  assert.equal(result.accepted, true);
  assert.equal(result.foods[0].deletedAt, archivedAt);
  assert.equal(result.foods[0].payload.deleted_at, archivedAt);
});

test("listFoodsFromRows searches by name, excludes archived by default, and paginates", () => {
  const rows = [
    {
      id: "food-a",
      updatedAt: new Date("2026-07-01T00:00:00.000Z"),
      deletedAt: null,
      payload: { name: "Apple", food_source: "user" }
    },
    {
      id: "food-b",
      updatedAt: new Date("2026-07-02T00:00:00.000Z"),
      deletedAt: new Date("2026-07-03T00:00:00.000Z"),
      payload: { name: "Archived Bread", food_source: "user" }
    },
    {
      id: "food-c",
      updatedAt: new Date("2026-07-03T00:00:00.000Z"),
      deletedAt: null,
      payload: { name: "Avocado Toast Recipe", food_source: "user" }
    }
  ];

  const defaultPage = listFoodsFromRows(rows, {
    includeArchived: false,
    limit: 50,
    fields: []
  });
  assert.equal(defaultPage.foods.length, 2);
  assert.ok(!defaultPage.foods.some((food) => food.id === "food-b"));

  const archivedIncluded = listFoodsFromRows(rows, {
    includeArchived: true,
    limit: 50,
    fields: []
  });
  assert.equal(archivedIncluded.foods.length, 3);

  const searched = listFoodsFromRows(rows, {
    search: "avocado",
    includeArchived: false,
    limit: 50,
    fields: []
  });
  assert.equal(searched.foods.length, 1);
  assert.equal(searched.foods[0].id, "food-c");

  const paged = listFoodsFromRows(rows, {
    includeArchived: false,
    limit: 1,
    fields: []
  });
  assert.equal(paged.foods.length, 1);
  assert.ok(paged.nextCursor !== null);
  const secondPage = listFoodsFromRows(rows, {
    includeArchived: false,
    limit: 1,
    cursor: paged.nextCursor,
    fields: []
  });
  assert.equal(secondPage.foods.length, 1);
  assert.notEqual(secondPage.foods[0].id, paged.foods[0].id);
  assert.equal(secondPage.nextCursor, null);
});

test("listFoodsFromRows always returns id and name even with an empty fields selection", () => {
  const rows = [
    {
      id: "food-a",
      updatedAt: new Date("2026-07-01T00:00:00.000Z"),
      deletedAt: null,
      payload: { name: "Apple", food_source: "user" }
    }
  ];

  const result = listFoodsFromRows(rows, {
    includeArchived: false,
    limit: 50,
    fields: []
  });
  assert.deepEqual(Object.keys(result.foods[0]).sort(), ["id", "name"]);
  assert.deepEqual(result.fields, ["id", "name"]);
});

test("listFoodsFromRows projects requested fields, including isRecipe derived from the payload", () => {
  const rows = [
    {
      id: "recipe-a",
      updatedAt: new Date("2026-07-01T00:00:00.000Z"),
      deletedAt: null,
      payload: {
        name: "Chili",
        food_source: "user",
        recipe_ingredients_json: JSON.stringify([{ food_id: "x" }]),
        recipe_serving_count: 4
      }
    }
  ];

  const result = listFoodsFromRows(rows, {
    includeArchived: false,
    limit: 50,
    fields: ["isRecipe", "recipeServingCount", "foodSource"]
  });
  assert.equal(result.foods[0].isRecipe, true);
  assert.equal(result.foods[0].recipeServingCount, 4);
  assert.equal(result.foods[0].foodSource, "user");
});

test("toAgentFood maps a synced foods row payload to the agent shape, including an archived row", () => {
  const food = toAgentFood({
    id: "food-1",
    updatedAt: new Date("2026-07-01T00:00:00.000Z"),
    deletedAt: new Date("2026-07-02T00:00:00.000Z"),
    payload: {
      name: "Chicken",
      food_source: "usda",
      nutrient_values_json: JSON.stringify({
        energy: { status: "complete", value: 165, entered: "165", unit: "kilocalorie" }
      }),
      is_liquid: false,
      serving_label: "piece",
      serving_size: 86,
      package_size: null,
      recipe_ingredients_json: null,
      recipe_serving_count: null
    }
  });

  assert.equal(food.id, "food-1");
  assert.equal(food.name, "Chicken");
  assert.equal(food.foodSource, "usda");
  assert.equal(food.isRecipe, false);
  assert.equal(food.nutrientsPer100.energy.value, 165);
  assert.equal(food.deletedAt, "2026-07-02T00:00:00.000Z");
});

test("searchAgentPlatformFoods returns bundled USDA foods with ODbL-adjacent attribution metadata", () => {
  const result = searchAgentPlatformFoods({ limit: 20 });

  assert.ok(result.foods.length > 0, "expected the bundled USDA seed to load");
  assert.ok(result.foods.every((food) => food.foodSource === "usda"));
  assert.equal(result.attribution.source, "usda");
  assert.ok(result.attribution.sourceName.includes("USDA"));
  assert.ok(result.attribution.attributionText.length > 0);
  assert.ok(result.attribution.licenseName.length > 0);
});

test("searchAgentPlatformFoods filters by case-insensitive name and honors the limit", () => {
  const all = searchAgentPlatformFoods({ limit: 50 });
  const target = all.foods[0];

  const result = searchAgentPlatformFoods({
    search: target.name.toUpperCase(),
    limit: 50
  });
  assert.ok(result.foods.some((food) => food.id === target.id));

  const bounded = searchAgentPlatformFoods({ limit: 1 });
  assert.equal(bounded.foods.length, 1);
});

test("searchAgentPlatformFoods returns an empty page for an unmatched query, never an error", () => {
  const result = searchAgentPlatformFoods({
    search: "definitely-not-a-real-food-xyz",
    limit: 20
  });
  assert.deepEqual(result.foods, []);
});
