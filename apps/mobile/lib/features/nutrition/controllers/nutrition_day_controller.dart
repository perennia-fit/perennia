import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/analytics/energy_balance.dart';
import '../../../domain/analytics/series_families.dart';
import '../../metrics/controllers/metrics_controller.dart'
    show metricRepositoryProvider;

final nutritionRepositoryProvider = Provider<NutritionRepository>((ref) {
  return ref.watch(trainingRepositoriesProvider).nutrition;
});

final mealTypeListProvider = StreamProvider<List<MealTypeRecord>>((ref) {
  return ref.watch(nutritionRepositoryProvider).watchMealTypes();
});

final nutritionGoalListProvider =
    StreamProvider<List<NutritionGoalRecord>>((ref) {
  return ref.watch(nutritionRepositoryProvider).watchNutritionGoals();
});

/// Active nutrition `Goal` targets keyed by goalable `Nutrient` for read-time
/// display. Goals are configuration, never derived analytics (NUTRITION.md §2).
final nutritionGoalsByNutrientProvider =
    Provider<Map<NutrientId, NutritionGoalRecord>>((ref) {
  final goals = ref.watch(nutritionGoalListProvider).value ??
      const <NutritionGoalRecord>[];
  return <NutrientId, NutritionGoalRecord>{
    for (final goal in goals) goal.nutrient: goal,
  };
});

final selectedNutritionDayProvider =
    NotifierProvider<SelectedNutritionDayController, NutritionDayDate>(
  SelectedNutritionDayController.new,
);

/// The length of the trailing window the trends surface aggregates over. Kept
/// deliberately small — distribution/per-weekday windows are deferred (§12).
enum NutritionTrendWindow {
  week(7, 'Last 7 days'),
  month(30, 'Last 30 days');

  const NutritionTrendWindow(this.days, this.label);

  final int days;
  final String label;
}

final nutritionTrendWindowProvider =
    NotifierProvider<NutritionTrendWindowController, NutritionTrendWindow>(
  NutritionTrendWindowController.new,
);

class NutritionTrendWindowController extends Notifier<NutritionTrendWindow> {
  @override
  NutritionTrendWindow build() => NutritionTrendWindow.week;

  void select(NutritionTrendWindow window) {
    state = window;
  }
}

/// The derived trends/goals surface state: the per-day records over the trailing
/// window plus the active `Goal` configuration. Totals, trends, and goal
/// progress are all **derived on read** here — nothing in this state
/// is persisted or synced. Goals are configuration, joined at read time, never
/// merged into the analytics store (NUTRITION.md §2).
class NutritionTrendsState {
  NutritionTrendsState({
    required this.range,
    required List<NutritionDayRecord> days,
    required Map<NutrientId, NutritionGoalRecord> goalsByNutrient,
  })  : days = List<NutritionDayRecord>.unmodifiable(days),
        goalsByNutrient = Map<NutrientId, NutritionGoalRecord>.unmodifiable(
          goalsByNutrient,
        );

  final NutritionDayRange range;
  final List<NutritionDayRecord> days;
  final Map<NutrientId, NutritionGoalRecord> goalsByNutrient;

  NutritionDayDate get anchorDate => range.end;

  /// The derived totals for the most recent (anchor) day in the window.
  NutrientTotals get anchorTotals {
    for (final day in days) {
      if (day.localDate == range.end) {
        return day.totals;
      }
    }
    return NutrientTotals.fromEntries(const <FoodEntryRecord>[]);
  }

  NutritionGoalTarget? targetFor(NutrientId nutrient) {
    return goalsByNutrient[nutrient]?.target;
  }

  /// Goal progress for the anchor day for one goalable nutrient (derived total
  /// vs configured target, unknown-aware).
  NutrientGoalProgress anchorProgress(NutrientId nutrient) {
    return NutrientGoalProgress.derive(
      total: anchorTotals[nutrient],
      target: targetFor(nutrient),
    );
  }

  /// The per-day trend for one nutrient across the window, with the configured
  /// target carried as a reference line.
  NutritionTrend trendFor(NutrientId nutrient) {
    return NutritionTrend.forNutrient(
      nutrient: nutrient,
      range: range,
      days: days,
      target: targetFor(nutrient),
    );
  }
}

final nutritionTrendsControllerProvider =
    StreamNotifierProvider<NutritionTrendsController, NutritionTrendsState>(
  NutritionTrendsController.new,
);

class NutritionTrendsController extends StreamNotifier<NutritionTrendsState> {
  @override
  Stream<NutritionTrendsState> build() {
    final repository = ref.watch(nutritionRepositoryProvider);
    final goalsByNutrient = ref.watch(nutritionGoalsByNutrientProvider);
    final range = ref.watch(nutritionTrendRangeProvider);

    return repository.watchNutritionDaysInRange(range).map(
          (days) => NutritionTrendsState(
            range: range,
            days: days,
            goalsByNutrient: goalsByNutrient,
          ),
        );
  }

  void selectWindow(NutritionTrendWindow window) {
    ref.read(nutritionTrendWindowProvider.notifier).select(window);
  }
}

/// The trailing `Nutrition Day` window the trends surface aggregates over,
/// derived from the selected anchor day and window length. Shared by both the
/// nutrition analytics and the `Metric` family reads so they cover the same
/// span — joined only by sharing the window, never by sharing a store.
final nutritionTrendRangeProvider = Provider<NutritionDayRange>((ref) {
  final anchor = ref.watch(selectedNutritionDayProvider);
  final window = ref.watch(nutritionTrendWindowProvider);
  return NutritionDayRange.trailing(anchor, days: window.days);
});

/// The **`Metric` family** for the trends surface: every enabled monitoring
/// `Metric` as a labelled series, read straight from the Metric store's stored,
/// provenance-stamped `Reading`s. Computed nowhere from nutrition —
/// this never touches `Food Entry`s.
final metricSeriesFamilyProvider = StreamProvider<List<TrendSeries>>((ref) {
  final metrics = ref.watch(metricRepositoryProvider);
  final range = ref.watch(nutritionTrendRangeProvider);
  // The window covers the inclusive local-day range. `Reading` instants near a
  // local-day boundary can land on the adjacent UTC day, so the SQL bounds are
  // padded a day on each side; the display layer re-buckets each Reading onto
  // its local `Nutrition Day`.
  final from = range.start.addDays(-1).toLocalDateTime();
  final to = range.end.addDays(2).toLocalDateTime();

  return metrics.watchEnabledMetricSeries(from: from, to: to).map(
        (seriesData) => <TrendSeries>[
          for (final data in seriesData)
            TrendSeries.fromMetricReadings(
              metricName: data.metric.name,
              unitLabel: data.metric.unit,
              readings: <MetricReadingPoint>[
                for (final reading in data.readings)
                  MetricReadingPoint(
                    at: reading.atTime ??
                        reading.windowEndedAt ??
                        reading.updatedAt,
                    value: reading.scalarValue,
                  ),
              ],
            ),
        ],
      );
});

/// The **nutrition-analytics family** for the trends surface: derived per-day
/// totals over `Food Entry`s for the goalable nutrients (energy in, protein,
/// carbs, fat), computed on demand and stored nowhere. Unknown days
/// stay unknown gaps.
final nutritionSeriesFamilyProvider = Provider<List<TrendSeries>>((ref) {
  final state = ref.watch(nutritionTrendsControllerProvider).value;
  if (state == null) {
    return const <TrendSeries>[];
  }
  return <TrendSeries>[
    for (final id in goalableNutrientIds)
      TrendSeries.fromNutritionTrend(state.trendFor(id)),
  ];
});

/// The two series families presented together on one screen, **joined at read
/// time, never merged** (NUTRITION.md §2): the `Metric` family is read from the
/// Metric repository and the nutrition family is computed over `Food Entry`s;
/// neither writes into a shared series table.
final seriesFamiliesProvider = Provider<AsyncValue<TwoSeriesFamilies>>((ref) {
  final metricFamily = ref.watch(metricSeriesFamilyProvider);
  final nutritionState = ref.watch(nutritionTrendsControllerProvider);

  return metricFamily.when(
    data: (metricSeries) => nutritionState.when(
      data: (_) => AsyncData<TwoSeriesFamilies>(
        TwoSeriesFamilies(
          metricSeries: metricSeries,
          nutritionSeries: ref.watch(nutritionSeriesFamilyProvider),
        ),
      ),
      loading: () => const AsyncLoading<TwoSeriesFamilies>(),
      error: AsyncError<TwoSeriesFamilies>.new,
    ),
    loading: () => const AsyncLoading<TwoSeriesFamilies>(),
    error: AsyncError<TwoSeriesFamilies>.new,
  );
});

/// The well-known monitoring `Metric` name that supplies the **energy-out**
/// side of the balance: calories burned, a tracker signal in the M12 Metric
/// domain (CONTEXT.md reserves `Metric` for the body's response). The out-side
/// is read from this `Metric`'s `Reading`s, never reconstructed from authored
/// intake (NUTRITION.md §2, §8;).
const caloriesBurnedMetricName = 'Calories Burned';

final caloriesBurnedMetricSeriesProvider =
    StreamProvider<MetricSeriesData?>((ref) {
  final metrics = ref.watch(metricRepositoryProvider);
  final anchor = ref.watch(selectedNutritionDayProvider);
  // Keep the same local-day boundary padding the full Metric family uses, but
  // scope the subscription to the one energy-out Metric.
  final from = anchor.addDays(-1).toLocalDateTime();
  final to = anchor.addDays(2).toLocalDateTime();

  return metrics.watchMonitoringMetricSeriesByName(
    caloriesBurnedMetricName,
    from: from,
    to: to,
  );
});

/// The **energy-out** value for the anchor `Nutrition Day`: the sum of the
/// calories-burned `Metric`'s `Reading`s that fall on that local day, or `null`
/// when there is no such `Reading` (an unknown out-side, never an implicit
/// zero).
///
/// This is a pure read off the Metric store — the stored, provenance-stamped
/// signal — bucketed onto the local day. It never touches `Food Entry`s; the
/// balance joins it with the derived energy-in only at read time (
/// "join, never merge").
final energyOutForAnchorDayProvider = Provider<AsyncValue<double?>>((ref) {
  final anchor = ref.watch(selectedNutritionDayProvider);
  final caloriesBurnedSeries = ref.watch(caloriesBurnedMetricSeriesProvider);
  return caloriesBurnedSeries.whenData(
    (series) => _energyOutForAnchorDay(anchor: anchor, series: series),
  );
});

double? _energyOutForAnchorDay({
  required NutritionDayDate anchor,
  required MetricSeriesData? series,
}) {
  if (series == null) {
    return null;
  }

  final caloriesBurned = TrendSeries.fromMetricReadings(
    metricName: series.metric.name,
    unitLabel: series.metric.unit,
    readings: <MetricReadingPoint>[
      for (final reading in series.readings)
        MetricReadingPoint(
          at: reading.atTime ?? reading.windowEndedAt ?? reading.updatedAt,
          value: reading.scalarValue,
        ),
    ],
  );

  // Sum the known Readings on the anchor local day. A day with no Reading stays
  // unknown (`null`), never an implicit 0 in the subtraction (NUTRITION.md §4).
  double? total;
  for (final datum in caloriesBurned.data) {
    if (datum.localDate != anchor || datum.isUnknown) {
      continue;
    }
    total = (total ?? 0) + datum.value!;
  }
  return total;
}

/// The headline cross-family read of M22: the anchor day's **energy-in vs
/// energy-out** balance, **joined at read time, never merged** (NUTRITION.md §2,
/// §8). Energy-in is the derived nutrition analytic (computed over `Food Entry`s,
/// stored nowhere —); energy-out is a calories-burned `Metric` read
/// from its own store. The net is computed on demand and nothing is persisted —
/// no balance value, no in/out association.
final energyBalanceProvider = Provider<AsyncValue<EnergyBalance>>((ref) {
  final energyOut = ref.watch(energyOutForAnchorDayProvider);
  final nutritionState = ref.watch(nutritionTrendsControllerProvider);

  return energyOut.when(
    data: (energyOutValue) => nutritionState.when(
      data: (state) => AsyncData<EnergyBalance>(
        EnergyBalance.derive(
          localDate: state.anchorDate,
          energyIn: state.anchorTotals[NutrientId.energy],
          energyOut: energyOutValue,
        ),
      ),
      loading: () => const AsyncLoading<EnergyBalance>(),
      error: AsyncError<EnergyBalance>.new,
    ),
    loading: () => const AsyncLoading<EnergyBalance>(),
    error: AsyncError<EnergyBalance>.new,
  );
});

class SelectedNutritionDayController extends Notifier<NutritionDayDate> {
  @override
  NutritionDayDate build() => NutritionDayDate.fromDateTime(DateTime.now());

  void select(NutritionDayDate localDate) {
    state = localDate;
  }

  void addDays(int days) {
    state = state.addDays(days);
  }
}

final nutritionDayControllerProvider =
    StreamNotifierProvider<NutritionDayController, NutritionDayState>(
  NutritionDayController.new,
);

class NutritionDayController extends StreamNotifier<NutritionDayState> {
  @override
  Stream<NutritionDayState> build() {
    final repository = ref.watch(nutritionRepositoryProvider);
    final selectedDate = ref.watch(selectedNutritionDayProvider);
    return repository.watchNutritionDay(selectedDate).map(
          (day) => NutritionDayState(day: day),
        );
  }

  void selectNutritionDay(NutritionDayDate localDate) {
    ref.read(selectedNutritionDayProvider.notifier).select(localDate);
  }

  void showPreviousDay() {
    ref.read(selectedNutritionDayProvider.notifier).addDays(-1);
  }

  void showNextDay() {
    ref.read(selectedNutritionDayProvider.notifier).addDays(1);
  }

  Future<String> startMeal({
    required MealTypeRecord mealType,
    DateTime? startedAt,
    NutritionDayDate? localDate,
  }) {
    final selectedDate = localDate ?? ref.read(selectedNutritionDayProvider);
    final effectiveStartedAt = startedAt ?? DateTime.now();
    return ref.read(nutritionRepositoryProvider).createMeal(
          MealDraft(
            mealType: mealType.name,
            startedAt: effectiveStartedAt,
            localDate: selectedDate,
            timezone: effectiveStartedAt.toLocal().timeZoneName,
          ),
        );
  }

  Future<String> createMealType({
    required String name,
  }) async {
    final mealTypes = await _activeMealTypes();
    final nextSortOrder = mealTypes.isEmpty
        ? 0
        : mealTypes
                .map((type) => type.sortOrder)
                .reduce((left, right) => left > right ? left : right) +
            1;
    return ref.read(nutritionRepositoryProvider).createMealType(
          MealTypeDraft(name: name, sortOrder: nextSortOrder),
        );
  }

  Future<void> renameMealType({
    required MealTypeRecord mealType,
    required String name,
  }) {
    return ref.read(nutritionRepositoryProvider).updateMealType(
          mealType.id,
          MealTypeDraft(name: name, sortOrder: mealType.sortOrder),
        );
  }

  Future<void> reorderMealTypes(List<String> orderedIds) {
    return ref.read(nutritionRepositoryProvider).reorderMealTypes(orderedIds);
  }

  Future<void> archiveMealType(String id) {
    return ref.read(nutritionRepositoryProvider).archiveMealType(id);
  }

  /// Saves one nutrition `Goal` target. The target is hard-rejected by the
  /// shared validator before any write (NUTRITION.md §6); the write confirms
  /// locally without blocking on the network.
  Future<String> saveNutritionGoal(NutritionGoalTarget target) {
    return ref.read(nutritionRepositoryProvider).saveNutritionGoal(target);
  }

  /// Clears the active nutrition `Goal` for [nutrient] with a normal LWW
  /// soft-delete.
  Future<void> clearNutritionGoal(NutrientId nutrient) {
    return ref.read(nutritionRepositoryProvider).clearNutritionGoal(nutrient);
  }

  Future<LogQuickEntryResult> logQuickEntry({
    required MealDraft meal,
    required QuickFoodEntryDraft entry,
  }) {
    return ref.read(nutritionRepositoryProvider).logQuickEntry(
          meal: meal,
          entry: entry,
        );
  }

  Future<LogQuickEntryResult> logQuickEntryForMeal({
    required String mealId,
    required QuickFoodEntryDraft entry,
  }) {
    return ref.read(nutritionRepositoryProvider).logQuickEntryForMeal(
          mealId: mealId,
          entry: entry,
        );
  }

  Future<LogFoodEntryResult> logFoodEntry({
    required FoodEntryDraft entry,
  }) {
    return ref.read(nutritionRepositoryProvider).logFoodEntry(entry: entry);
  }

  Future<LogFoodEntryResult> logFoodEntrySnapshot({
    required FoodEntrySnapshotDraft entry,
  }) {
    return ref.read(nutritionRepositoryProvider).logFoodEntrySnapshot(
          entry: entry,
        );
  }

  Future<List<MealTypeRecord>> _activeMealTypes() async {
    final current = ref.read(mealTypeListProvider).value;
    if (current != null) {
      return current;
    }
    return ref.read(nutritionRepositoryProvider).listMealTypes();
  }
}

class NutritionDayState {
  const NutritionDayState({
    required this.day,
  });

  final NutritionDayRecord day;
}
