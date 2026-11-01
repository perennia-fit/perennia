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

/// The Consistency view's worst case (Phase 4 of
/// docs/designs/protocol-schedules-and-reminders.md): `planDays` plus
/// `dayStatuses` over its longest range, for one Compound in 3 Protocols
/// with 5 Schedule Versions each and 800 logged Doses.
const protocolConsistencyRangeDays = 366;
const protocolConsistencyProtocolCount = 3;
const protocolConsistencyVersionsPerProtocol = 5;
const protocolConsistencyDoseCount = 800;
const protocolConsistencyBudget = Duration(milliseconds: 50);

/// Food History over about five years of logging (eleven Foods a day): read
/// once per add-food picker opening (docs/designs/unified-food-search.md §
/// Performance).
const foodHistoryEntryCount = 20000;
const foodHistoryFoodCount = 1500;
const foodHistoryBudget = Duration(milliseconds: 150);
