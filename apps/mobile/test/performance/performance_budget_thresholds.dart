const exerciseOverviewLargeHistorySetCount = 50000;
const exerciseOverviewAggregateBudget = Duration(milliseconds: 300);

const setSaveConfirmationFrameBudget = Duration(milliseconds: 16);

const coldStartHomeInteractiveBudget = Duration(seconds: 2);
const recordedColdStartHomeInteractiveBaseline = Duration(milliseconds: 420);
const recordedColdStartHomeInteractiveBaselineDate = '2026-06-21';
const recordedColdStartHomeInteractiveBaselineHarness =
    'Flutter widget-test harness on a local Windows host with real Drift '
    'in-memory database, real repositories, starter seed, and first Home query';

/// The Open Food Facts list on the device holds about 41,000 products; a
/// typed search must return within this after the 300 ms typing pause.
const openFoodFactsLocalSearchRowCount = 41000;
const openFoodFactsLocalSearchBudget = Duration(milliseconds: 100);
