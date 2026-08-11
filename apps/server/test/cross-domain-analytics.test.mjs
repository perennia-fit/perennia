import assert from "node:assert/strict";
import test from "node:test";

import {
  computeEnergyBalance,
  computeProteinOnTrainingDays,
  computeWorkoutFuelling,
  deriveDailyEnergyBalance,
  summarizeEnergyBalance,
  utcDayKey
} from "../src/analytics/cross-domain-analytics.ts";

// A self-describing nutrition day with one quick-entry meal whose energy nutrient
// is the supplied amount, so the analytics math is exercised without the storage
// mapping layer.
function energyNutritionDay(localDate, energyAmount) {
  return {
    localDate,
    meals: [
      {
        id: `${localDate}-meal`,
        mealType: "Lunch",
        startedAt: new Date(`${localDate}T12:00:00.000Z`),
        entries: [{ kind: "quickEntry", nutrients: { energy: energyAmount } }]
      }
    ]
  };
}

function complete(value, unit) {
  return { status: "complete", value, unit };
}

function unknown(unit) {
  return { status: "unknown", unit };
}

test("deriveDailyEnergyBalance: net only when both sides known; unknowns held out", () => {
  const both = deriveDailyEnergyBalance({
    localDate: "2026-06-24",
    energyIn: 2000,
    energyInComplete: true,
    energyOut: 500
  });
  assert.equal(both.status, "computed");
  assert.equal(both.net, 1500);

  // Incomplete in-side -> indeterminate, no net fabricated.
  const inUnknown = deriveDailyEnergyBalance({
    localDate: "2026-06-24",
    energyIn: 2000,
    energyInComplete: false,
    energyOut: 500
  });
  assert.equal(inUnknown.status, "indeterminate");
  assert.equal(inUnknown.energyIn, null);
  assert.equal(inUnknown.net, null);

  // Missing out-side -> indeterminate (a missing Reading is unknown, not 0).
  const outMissing = deriveDailyEnergyBalance({
    localDate: "2026-06-24",
    energyIn: 2000,
    energyInComplete: true,
    energyOut: null
  });
  assert.equal(outMissing.status, "indeterminate");
  assert.equal(outMissing.net, null);

  // A genuine complete zero out-side is NOT unknown: net is computed.
  const zeroOut = deriveDailyEnergyBalance({
    localDate: "2026-06-24",
    energyIn: 2000,
    energyInComplete: true,
    energyOut: 0
  });
  assert.equal(zeroOut.status, "computed");
  assert.equal(zeroOut.net, 2000);
});

test("computeEnergyBalance: joins nutrition energy with calories-burned per day", () => {
  const days = ["2026-06-24", "2026-06-25", "2026-06-26"];
  const nutritionDays = [
    energyNutritionDay("2026-06-24", complete(2000, "kilocalorie")),
    // Day 25: energy unknown -> indeterminate even with a Reading.
    energyNutritionDay("2026-06-25", unknown("kilocalorie"))
    // Day 26: no meals at all -> complete zero in, but no Reading -> indeterminate.
  ];
  const caloriesBurned = [
    { localDate: "2026-06-24", value: 300 },
    { localDate: "2026-06-24", value: 200 },
    { localDate: "2026-06-25", value: 400 }
  ];

  const daily = computeEnergyBalance({ days, nutritionDays, caloriesBurned });
  assert.equal(daily.length, 3);

  const d24 = daily[0];
  assert.equal(d24.status, "computed");
  assert.equal(d24.energyIn, 2000);
  assert.equal(d24.energyOut, 500); // 300 + 200 summed onto the day
  assert.equal(d24.net, 1500);

  const d25 = daily[1];
  assert.equal(d25.status, "indeterminate");
  assert.equal(d25.energyIn, null); // unknown energy-in held out
  assert.equal(d25.net, null);

  const d26 = daily[2];
  assert.equal(d26.status, "indeterminate"); // no Reading -> unknown out-side
  assert.equal(d26.energyOut, null);

  const summary = summarizeEnergyBalance(daily);
  assert.equal(summary.computedDayCount, 1);
  assert.equal(summary.indeterminateDayCount, 2);
  assert.equal(summary.averageNet, 1500);
  assert.equal(summary.cumulativeNet, 1500);
});

test("computeProteinOnTrainingDays: cohorts by training day, incomplete days held out", () => {
  const days = ["2026-06-24", "2026-06-25", "2026-06-26", "2026-06-27"];
  const proteinDays = [
    { localDate: "2026-06-24", protein: complete(150, "gram") },
    { localDate: "2026-06-25", protein: complete(90, "gram") },
    { localDate: "2026-06-26", protein: unknown("gram") },
    { localDate: "2026-06-27", protein: complete(110, "gram") }
  ].map(({ localDate, protein }) => ({
    localDate,
    meals: [
      {
        id: `${localDate}-m`,
        mealType: "Dinner",
        startedAt: new Date(`${localDate}T18:00:00.000Z`),
        entries: [{ kind: "quickEntry", nutrients: { protein } }]
      }
    ]
  }));

  const trainingDayDates = new Set(["2026-06-24", "2026-06-26"]);
  const result = computeProteinOnTrainingDays({
    days,
    nutritionDays: proteinDays,
    trainingDayDates
  });

  // Training cohort: 24 (150, complete) + 26 (unknown, held out).
  assert.equal(result.trainingDays.dayCount, 2);
  assert.equal(result.trainingDays.completeDayCount, 1);
  assert.equal(result.trainingDays.incompleteDayCount, 1);
  assert.equal(result.trainingDays.averageProtein, 150);
  assert.equal(result.trainingDays.totalProtein, 150);

  // Rest cohort: 25 (90) + 27 (110) -> avg 100.
  assert.equal(result.restDays.dayCount, 2);
  assert.equal(result.restDays.completeDayCount, 2);
  assert.equal(result.restDays.averageProtein, 100);
});

test("computeWorkoutFuelling: windows meals around workout start", () => {
  const workouts = [
    {
      workoutId: "w1",
      startedAt: new Date("2026-06-24T17:00:00.000Z"),
      localDate: "2026-06-24"
    }
  ];
  const meals = [
    // 90 min before -> pre (within 120)
    {
      mealId: "m-pre",
      mealType: "Snack",
      startedAt: new Date("2026-06-24T15:30:00.000Z"),
      localDate: "2026-06-24"
    },
    // 30 min after -> post (within 120)
    {
      mealId: "m-post",
      mealType: "Dinner",
      startedAt: new Date("2026-06-24T17:30:00.000Z"),
      localDate: "2026-06-24"
    },
    // 5 hours after -> outside both windows
    {
      mealId: "m-far",
      mealType: "Supper",
      startedAt: new Date("2026-06-24T22:00:00.000Z"),
      localDate: "2026-06-24"
    }
  ];

  const { perWorkout, summary } = computeWorkoutFuelling({
    workouts,
    meals,
    preWindowMinutes: 120,
    postWindowMinutes: 120
  });

  assert.equal(perWorkout.length, 1);
  assert.equal(perWorkout[0].preWorkoutMealCount, 1);
  assert.equal(perWorkout[0].postWorkoutMealCount, 1);
  assert.equal(perWorkout[0].minutesSincePreWorkoutMeal, 90);
  assert.equal(perWorkout[0].minutesUntilPostWorkoutMeal, 30);

  assert.equal(summary.workoutCount, 1);
  assert.equal(summary.workoutsWithPreMeal, 1);
  assert.equal(summary.workoutsWithPostMeal, 1);
});

test("utcDayKey: buckets an instant onto its UTC calendar day", () => {
  assert.equal(utcDayKey(new Date("2026-06-24T23:59:59.000Z")), "2026-06-24");
  assert.equal(utcDayKey(new Date("2026-06-25T00:00:00.000Z")), "2026-06-25");
});
