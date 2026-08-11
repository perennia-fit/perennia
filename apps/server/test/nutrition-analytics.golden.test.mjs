import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";

import {
  deriveGoalProgress,
  totalsFromEntries
} from "../src/analytics/nutrition-analytics.ts";

const GOAL_UNIT = {
  energy: "kilocalorie",
  protein: "gram",
  carbohydrate: "gram",
  fat: "gram"
};

test("server nutrition analytics matches the shared golden vectors", async () => {
  const vectorsUrl = new URL(
    "../../../packages/golden-vectors/vectors/",
    import.meta.url
  );
  const filenames = (await readdir(vectorsUrl)).filter((name) =>
    name.endsWith(".json")
  );

  let casesChecked = 0;
  for (const filename of filenames) {
    const vector = JSON.parse(await readFile(new URL(filename, vectorsUrl), "utf8"));
    if (vector.domain !== "nutrition-analytics") {
      continue;
    }

    for (const vectorCase of vector.cases) {
      casesChecked += 1;
      const reason = `${filename} ${vectorCase.name}`;
      const allEntries = [];
      const totalsByDate = new Map();

      for (const day of vectorCase.days) {
        const entries = day.entries.map(toAnalyticsEntry);
        allEntries.push(...entries);
        totalsByDate.set(day.localDate, totalsFromEntries(entries));
      }
      const periodTotals = totalsFromEntries(allEntries);

      // Per-day totals.
      for (const [localDate, expectedTotals] of Object.entries(
        vectorCase.expected.dayTotals
      )) {
        const totals = totalsByDate.get(localDate);
        assert.ok(totals, `${reason}: missing computed totals for ${localDate}`);
        assertTotals(totals, expectedTotals, `${reason} day ${localDate}`);
      }

      // Period totals.
      assertTotals(
        periodTotals,
        vectorCase.expected.periodTotals,
        `${reason} period`
      );

      // Goal progress over the period totals.
      for (const [nutrient, expected] of Object.entries(
        vectorCase.expected.goalProgress ?? {}
      )) {
        const target =
          vectorCase.goals[nutrient] === undefined
            ? null
            : {
                nutrient,
                value: vectorCase.goals[nutrient],
                unit: GOAL_UNIT[nutrient]
              };
        const progress = deriveGoalProgress(periodTotals.get(nutrient), target);
        assert.equal(progress.status, expected.status, `${reason} ${nutrient} status`);
        assertNullableAlmostEqual(
          progress.ratio,
          expected.ratio,
          `${reason} ${nutrient} ratio`
        );
        assertNullableAlmostEqual(
          progress.remaining,
          expected.remaining,
          `${reason} ${nutrient} remaining`
        );
      }
    }
  }

  assert.ok(casesChecked > 0, "expected at least one nutrition-analytics vector case");
});

function toAnalyticsEntry(entry) {
  return {
    kind: entry.kind,
    resolvedBaseQuantity: entry.resolvedBaseQuantity,
    nutrients: Object.fromEntries(
      Object.entries(entry.nutrients).map(([id, amount]) => [
        id,
        amount.status === "complete"
          ? { status: "complete", value: amount.value, unit: GOAL_UNIT[id] ?? "gram" }
          : { status: "unknown", unit: GOAL_UNIT[id] ?? "gram" }
      ])
    )
  };
}

function assertTotals(totals, expectedTotals, reason) {
  for (const [nutrient, expected] of Object.entries(expectedTotals)) {
    const total = totals.get(nutrient);
    assert.ok(total, `${reason}: missing computed total for ${nutrient}`);
    assert.equal(
      total.isComplete,
      expected.complete,
      `${reason} ${nutrient} complete`
    );
    if (expected.value !== undefined) {
      assertAlmostEqual(total.value, expected.value, `${reason} ${nutrient} value`);
    }
  }
}

function assertNullableAlmostEqual(actual, expected, reason) {
  if (expected === null || expected === undefined) {
    assert.equal(actual, expected ?? null, reason);
    return;
  }
  assertAlmostEqual(actual, expected, reason);
}

function assertAlmostEqual(actual, expected, reason) {
  assert.ok(
    typeof actual === "number" && Math.abs(actual - expected) <= 0.000001,
    `${reason}: expected ${actual} to be within 0.000001 of ${expected}`
  );
}
