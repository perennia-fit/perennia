# Performance budgets

These tests lock the app's performance budgets into CI. The budgets exist because
the gym floor is the context: logging must stay instant on a mid-range phone with
years of history, so a regression here is a product bug, not a benchmark curio.
Each budget constant is defined next to the test that enforces it.

| Surface | CI guard | Budget |
| --- | --- | --- |
| Exercise Overview large history | `performance_budgets_test.dart` builds and seeds a 50k-set fixture, then asserts the overview aggregate completes below `exerciseOverviewAggregateBudget`. | < 300 ms |
| Set save feedback | A widget test taps Save set and expects `TrainingScreen.saveSetConfirmationKey` after one `setSaveConfirmationFrameBudget` pump. The confirmation is shown before the save path awaits local persistence or timer work; no network client is on this path. | 1 frame / 16 ms |
| Cold start Home data path | The harness starts the stopwatch, asks real `RepositoryHomeRepository` to load the first training-day summary from an in-memory Drift database, real `TrainingRepositories`, platform starter seed, and first Home query, then asserts that the summary contains the data Home needs to render an interactive empty state. The recorded host baseline is `recordedColdStartHomeInteractiveBaseline` (`420 ms`, recorded 2026-06-21) against the Android target. True widget-root and mid-range Android process-spawn timing remain tracked by [#40](https://github.com/lspinheiro/Perennia/issues/40). | < 2 s |

CI runs this file explicitly through the `Performance budgets` step in
`.github/workflows/ci.yml`, so a regression past these thresholds fails the
required mobile job.
