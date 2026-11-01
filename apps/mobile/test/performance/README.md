# Performance budgets

These tests lock the app's performance budgets into CI. The budgets exist because
the gym floor is the context: logging must stay instant on a mid-range phone with
years of history, so a regression here is a product bug, not a benchmark curio.
Each budget constant is defined next to the test that enforces it.

| Surface | CI guard | Budget |
| --- | --- | --- |
| Exercise Overview large history | `performance_budgets_test.dart` builds and seeds a 50k-set fixture, then asserts the overview aggregate completes below `exerciseOverviewAggregateBudget`. | < 300 ms |
| Set save feedback | A widget test taps Save set and expects `TrainingScreen.saveSetConfirmationKey` after one `setSaveConfirmationFrameBudget` pump. The confirmation is shown before the save path awaits local persistence or timer work; no network client is on this path. | 1 frame / 16 ms |
| Open Food Facts device search | `performance_budgets_test.dart` installs a 41,000-product synthetic bundle into an in-memory `FoodReferenceDatabase`, then asserts that a two-word prefix search (`greek yo`, 50 results) through the FTS5 index completes below `openFoodFactsLocalSearchBudget` on the host. | < 100 ms |
| Food History | `performance_budgets_test.dart` inserts 20,000 Food Entries for 1,500 Foods in 3,400 Meals over five years into an in-memory `AppDatabase`, then asserts that `NutritionRepository.listFoodHistory`, read once per add-food picker opening, returns every Food below `foodHistoryBudget` on the host. It times the fastest of three reads, because the full test run shares the host with other test files and the margin is under 2×. | < 150 ms |
| Typed All search | `performance_budgets_test.dart` installs the 41,000-product synthetic bundle, builds a loaded `YourFoods` of 1,500 items, then asserts that a typed All search (`greek yo`: Your foods, USDA and Open Food Facts merged, 50 rows) completes below `openFoodFactsLocalSearchBudget` on the host. | < 100 ms |
| Consistency view range | `performance_budgets_test.dart` builds one Compound in 3 Protocols (5 Schedule Versions each, one with a cycle and Pauses) and 800 Doses, then asserts that the shared core's `planDays` plus `dayStatuses` over 366 days completes below `protocolConsistencyBudget`, after checking that every PlanDay, Day Status and Dose was produced and matched. | < 50 ms |
| Cold start Home data path | The harness starts the stopwatch, asks real `RepositoryHomeRepository` to load the first training-day summary from an in-memory Drift database, real `TrainingRepositories`, platform starter seed, and first Home query, then asserts that the summary contains the data Home needs to render an interactive empty state. The recorded host baseline is `recordedColdStartHomeInteractiveBaseline` (`420 ms`, recorded 2026-06-21) against the Android target. True widget-root and mid-range Android process-spawn timing are not yet measured here. | < 2 s |

CI runs this file explicitly through the `Performance budgets` step in
`.github/workflows/ci.yml`, so a regression past these thresholds fails the
required mobile job.
