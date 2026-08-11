// GENERATED FILE — do not edit by hand.
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
{
  "datasetVersion": "fdc-foundation-sr-legacy-2026-04",
  "sourceName": "USDA FoodData Central",
  "sourceUrl": "https://fdc.nal.usda.gov/",
  "licenseName": "Public domain (CC0-equivalent U.S. government work)",
  "attributionText": "Food reference data derived from USDA FoodData Central."
};

export const USDA_FOOD_SEED_FOODS: readonly UsdaFoodSeedFood[] =
[
  {
    "id": "usda-fdc-171077",
    "name": "Chicken breast",
    "isLiquid": false,
    "servingLabel": "piece",
    "servingSize": 86,
    "packageSize": null,
    "nutrientsPer100": {
      "energy": {
        "status": "complete",
        "value": 165,
        "entered": "165",
        "unit": "kilocalorie"
      },
      "protein": {
        "status": "complete",
        "value": 31.02,
        "entered": "31.02",
        "unit": "gram"
      },
      "carbohydrate": {
        "status": "complete",
        "value": 0,
        "entered": "0",
        "unit": "gram"
      },
      "sugar": {
        "status": "complete",
        "value": 0,
        "entered": "0",
        "unit": "gram"
      },
      "fat": {
        "status": "complete",
        "value": 3.57,
        "entered": "3.57",
        "unit": "gram"
      },
      "saturated_fat": {
        "status": "complete",
        "value": 1.01,
        "entered": "1.01",
        "unit": "gram"
      },
      "monounsaturated_fat": {
        "status": "complete",
        "value": 1.24,
        "entered": "1.24",
        "unit": "gram"
      },
      "polyunsaturated_fat": {
        "status": "complete",
        "value": 0.77,
        "entered": "0.77",
        "unit": "gram"
      },
      "fiber": {
        "status": "complete",
        "value": 0,
        "entered": "0",
        "unit": "gram"
      },
      "sodium": {
        "status": "complete",
        "value": 74,
        "entered": "74",
        "unit": "milligram"
      },
      "cholesterol": {
        "status": "complete",
        "value": 85,
        "entered": "85",
        "unit": "milligram"
      },
      "niacin": {
        "status": "complete",
        "value": 13.7,
        "entered": "13.7",
        "unit": "milligram"
      },
      "vitamin_b6": {
        "status": "complete",
        "value": 0.6,
        "entered": "0.6",
        "unit": "milligram"
      },
      "phosphorus": {
        "status": "complete",
        "value": 228,
        "entered": "228",
        "unit": "milligram"
      },
      "potassium": {
        "status": "complete",
        "value": 256,
        "entered": "256",
        "unit": "milligram"
      },
      "selenium": {
        "status": "complete",
        "value": 27.6,
        "entered": "27.6",
        "unit": "microgram"
      },
      "water": {
        "status": "complete",
        "value": 65.26,
        "entered": "65.26",
        "unit": "milliliter"
      }
    }
  },
  {
    "id": "usda-fdc-171284",
    "name": "Milk, whole",
    "isLiquid": true,
    "servingLabel": "cup",
    "servingSize": 244,
    "packageSize": 3785.41,
    "nutrientsPer100": {
      "energy": {
        "status": "complete",
        "value": 61,
        "entered": "61",
        "unit": "kilocalorie"
      },
      "protein": {
        "status": "complete",
        "value": 3.15,
        "entered": "3.15",
        "unit": "gram"
      },
      "carbohydrate": {
        "status": "complete",
        "value": 4.8,
        "entered": "4.8",
        "unit": "gram"
      },
      "sugar": {
        "status": "complete",
        "value": 5.05,
        "entered": "5.05",
        "unit": "gram"
      },
      "fat": {
        "status": "complete",
        "value": 3.25,
        "entered": "3.25",
        "unit": "gram"
      },
      "saturated_fat": {
        "status": "complete",
        "value": 1.865,
        "entered": "1.865",
        "unit": "gram"
      },
      "sodium": {
        "status": "complete",
        "value": 43,
        "entered": "43",
        "unit": "milligram"
      },
      "cholesterol": {
        "status": "complete",
        "value": 10,
        "entered": "10",
        "unit": "milligram"
      },
      "vitamin_a": {
        "status": "complete",
        "value": 46,
        "entered": "46",
        "unit": "microgram"
      },
      "vitamin_d": {
        "status": "complete",
        "value": 1.3,
        "entered": "1.3",
        "unit": "microgram"
      },
      "calcium": {
        "status": "complete",
        "value": 113,
        "entered": "113",
        "unit": "milligram"
      },
      "potassium": {
        "status": "complete",
        "value": 132,
        "entered": "132",
        "unit": "milligram"
      },
      "water": {
        "status": "complete",
        "value": 88.13,
        "entered": "88.13",
        "unit": "milliliter"
      }
    }
  },
  {
    "id": "usda-fdc-173757",
    "name": "Chickpeas, boiled",
    "isLiquid": false,
    "servingLabel": "cup",
    "servingSize": 164,
    "packageSize": null,
    "nutrientsPer100": {
      "energy": {
        "status": "complete",
        "value": 164,
        "entered": "164",
        "unit": "kilocalorie"
      },
      "protein": {
        "status": "complete",
        "value": 8.86,
        "entered": "8.86",
        "unit": "gram"
      },
      "carbohydrate": {
        "status": "complete",
        "value": 27.42,
        "entered": "27.42",
        "unit": "gram"
      },
      "sugar": {
        "status": "complete",
        "value": 4.8,
        "entered": "4.8",
        "unit": "gram"
      },
      "fat": {
        "status": "complete",
        "value": 2.59,
        "entered": "2.59",
        "unit": "gram"
      },
      "saturated_fat": {
        "status": "complete",
        "value": 0.269,
        "entered": "0.269",
        "unit": "gram"
      },
      "fiber": {
        "status": "complete",
        "value": 7.6,
        "entered": "7.6",
        "unit": "gram"
      },
      "sodium": {
        "status": "complete",
        "value": 7,
        "entered": "7",
        "unit": "milligram"
      },
      "folate": {
        "status": "complete",
        "value": 172,
        "entered": "172",
        "unit": "microgram"
      },
      "iron": {
        "status": "complete",
        "value": 2.89,
        "entered": "2.89",
        "unit": "milligram"
      },
      "magnesium": {
        "status": "complete",
        "value": 48,
        "entered": "48",
        "unit": "milligram"
      },
      "phosphorus": {
        "status": "complete",
        "value": 168,
        "entered": "168",
        "unit": "milligram"
      },
      "potassium": {
        "status": "complete",
        "value": 291,
        "entered": "291",
        "unit": "milligram"
      },
      "zinc": {
        "status": "complete",
        "value": 1.53,
        "entered": "1.53",
        "unit": "milligram"
      },
      "water": {
        "status": "complete",
        "value": 60.21,
        "entered": "60.21",
        "unit": "milliliter"
      }
    }
  }
];
