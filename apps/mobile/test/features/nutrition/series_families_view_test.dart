import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/analytics/energy_balance.dart';
import 'package:perennia/domain/analytics/series_families.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/features/nutrition/controllers/nutrition_day_controller.dart';
import 'package:perennia/features/nutrition/widgets/nutrition_trends_view.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  testWidgets('renders a Metric series and a nutrition series as two '
      'separately-labelled families on one screen', (tester) async {
    await _pumpTrends(tester, families: _bothFamilies());

    final section = find.byKey(NutritionTrendsView.seriesFamiliesSectionKey);
    await tester.scrollUntilVisible(
      section,
      400,
      scrollable: find.byType(Scrollable).first,
    );

    expect(section, findsOneWidget);
    expect(find.byKey(NutritionTrendsView.metricFamilyKey), findsOneWidget);
    expect(find.byKey(NutritionTrendsView.nutritionFamilyKey), findsOneWidget);

    // The Metric family carries a stored signal...
    final metricGroup = find.byKey(NutritionTrendsView.metricFamilyKey);
    expect(
      find.descendant(of: metricGroup, matching: find.text('Calories Burned')),
      findsOneWidget,
    );
    // ...the nutrition family carries a derived analytic.
    final nutritionGroup = find.byKey(NutritionTrendsView.nutritionFamilyKey);
    expect(
      find.descendant(of: nutritionGroup, matching: find.text('Calories')),
      findsOneWidget,
    );
  });

  testWidgets('labels each family by name (more than colour)', (tester) async {
    await _pumpTrends(tester, families: _bothFamilies());

    final section = find.byKey(NutritionTrendsView.seriesFamiliesSectionKey);
    await tester.scrollUntilVisible(
      section,
      400,
      scrollable: find.byType(Scrollable).first,
    );

    final metricGroup = find.byKey(NutritionTrendsView.metricFamilyKey);
    final nutritionGroup = find.byKey(NutritionTrendsView.nutritionFamilyKey);

    // The family name appears as text in each group — not implied by colour.
    expect(
      find.descendant(
        of: metricGroup,
        matching: find.text(SeriesFamily.metric.label),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: metricGroup,
        matching: find.text(SeriesFamily.metric.provenanceLabel),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: nutritionGroup,
        matching: find.text(SeriesFamily.nutritionAnalytic.label),
      ),
      findsWidgets,
    );
    // Each family is also iconographically distinct (a non-colour signal).
    expect(
      find.descendant(
        of: metricGroup,
        matching: find.byIcon(Icons.monitor_heart_outlined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: nutritionGroup,
        matching: find.byIcon(Icons.restaurant_outlined),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a nutrition unknown gap renders as a dash, never 0',
      (tester) async {
    await _pumpTrends(tester, families: _nutritionUnknownCarbs());

    final section = find.byKey(NutritionTrendsView.seriesFamiliesSectionKey);
    await tester.scrollUntilVisible(
      section,
      400,
      scrollable: find.byType(Scrollable).first,
    );

    final carbRow = find.byKey(
      NutritionTrendsView.familySeriesKey(
        SeriesFamily.nutritionAnalytic,
        'Carbs',
      ),
    );
    expect(carbRow, findsOneWidget);
    // The all-unknown carb series shows a dash for its latest value, not 0 g.
    expect(
      find.descendant(of: carbRow, matching: find.text('—')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: carbRow, matching: find.text('0 g')),
      findsNothing,
    );
  });

  testWidgets('shows an empty Metric family rather than fabricating a signal',
      (tester) async {
    await _pumpTrends(tester, families: _nutritionOnly());

    final section = find.byKey(NutritionTrendsView.seriesFamiliesSectionKey);
    await tester.scrollUntilVisible(
      section,
      400,
      scrollable: find.byType(Scrollable).first,
    );

    final metricGroup = find.byKey(NutritionTrendsView.metricFamilyKey);
    expect(metricGroup, findsOneWidget);
    expect(
      find.descendant(
        of: metricGroup,
        matching: find.textContaining('No measured Metrics'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('series families section meets accessibility in both themes',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();

      await _pumpTrends(tester, families: _bothFamilies(), theme: theme);
      final section = find.byKey(NutritionTrendsView.seriesFamiliesSectionKey);
      await tester.scrollUntilVisible(
        section,
        400,
        scrollable: find.byType(Scrollable).first,
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

Future<void> _pumpTrends(
  WidgetTester tester, {
  required TwoSeriesFamilies families,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        nutritionTrendsControllerProvider.overrideWith(
          () => _FakeTrendsController(_trendsState()),
        ),
        seriesFamiliesProvider.overrideWithValue(
          AsyncData<TwoSeriesFamilies>(families),
        ),
        // The trends screen now also renders the energy-balance section; this
        // suite focuses on the series families, so stub a computed balance.
        energyBalanceProvider.overrideWithValue(
          AsyncData<EnergyBalance>(
            EnergyBalance.derive(
              localDate: const NutritionDayDate(year: 2026, month: 6, day: 26),
              energyIn: const NutrientTotal(
                id: NutrientId.energy,
                value: 2100,
                unit: NutrientUnit.kilocalorie,
                isComplete: true,
              ),
              energyOut: 2600,
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: const NutritionTrendsView(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TwoSeriesFamilies _bothFamilies() {
  return TwoSeriesFamilies(
    metricSeries: <TrendSeries>[
      TrendSeries.fromMetricReadings(
        metricName: 'Calories Burned',
        unitLabel: 'kcal',
        readings: <MetricReadingPoint>[
          _reading(25, 2400),
          _reading(26, 2600),
        ],
      ),
    ],
    nutritionSeries: <TrendSeries>[
      TrendSeries.fromNutritionTrend(_energyTrend()),
    ],
  );
}

TwoSeriesFamilies _nutritionUnknownCarbs() {
  return TwoSeriesFamilies(
    metricSeries: <TrendSeries>[
      TrendSeries.fromMetricReadings(
        metricName: 'Calories Burned',
        unitLabel: 'kcal',
        readings: <MetricReadingPoint>[_reading(26, 2600)],
      ),
    ],
    nutritionSeries: <TrendSeries>[
      TrendSeries.fromNutritionTrend(_carbTrend(carbohydrate: null)),
    ],
  );
}

TwoSeriesFamilies _nutritionOnly() {
  return TwoSeriesFamilies(
    metricSeries: const <TrendSeries>[],
    nutritionSeries: <TrendSeries>[
      TrendSeries.fromNutritionTrend(_energyTrend()),
    ],
  );
}

NutritionTrend _energyTrend() {
  final range = NutritionDayRange(
    start: const NutritionDayDate(year: 2026, month: 6, day: 25),
    end: const NutritionDayDate(year: 2026, month: 6, day: 26),
  );
  return NutritionTrend.forNutrient(
    nutrient: NutrientId.energy,
    range: range,
    days: <NutritionDayRecord>[
      _day(25, energy: 1900, carbohydrate: 210),
      _day(26, energy: 2100, carbohydrate: 230),
    ],
    target: null,
  );
}

NutritionTrend _carbTrend({required double? carbohydrate}) {
  final range = NutritionDayRange(
    start: const NutritionDayDate(year: 2026, month: 6, day: 26),
    end: const NutritionDayDate(year: 2026, month: 6, day: 26),
  );
  return NutritionTrend.forNutrient(
    nutrient: NutrientId.carbohydrate,
    range: range,
    days: <NutritionDayRecord>[
      _day(26, energy: 2100, carbohydrate: carbohydrate),
    ],
    target: null,
  );
}

NutritionTrendsState _trendsState() {
  return NutritionTrendsState(
    range: NutritionDayRange.trailing(
      const NutritionDayDate(year: 2026, month: 6, day: 26),
      days: 7,
    ),
    days: <NutritionDayRecord>[
      _day(26, energy: 2100, carbohydrate: 230),
    ],
    goalsByNutrient: const <NutrientId, NutritionGoalRecord>{},
  );
}

MetricReadingPoint _reading(int day, double value) {
  return MetricReadingPoint(
    at: DateTime.utc(2026, 6, day, 12),
    value: value,
  );
}

NutritionDayRecord _day(
  int day, {
  required double energy,
  required double? carbohydrate,
}) {
  final localDate = NutritionDayDate(year: 2026, month: 6, day: day);
  return NutritionDayRecord(
    localDate: localDate,
    meals: [
      NutritionDayMealRecord(
        meal: MealRecord(
          id: 'meal-$day',
          mealType: 'Breakfast',
          startedAt: DateTime.utc(2026, 6, day, 8),
          timezone: 'UTC',
          localDate: localDate,
          updatedAt: DateTime.utc(2026, 6, day, 8),
        ),
        entries: [
          FoodEntryRecord(
            id: 'entry-$day',
            mealId: 'meal-$day',
            kind: FoodEntryKind.quickEntry,
            position: 0,
            name: 'Logged food',
            nutrients: NutrientVector.energyAndMacros(
              energy: NutrientAmount.complete(
                value: energy,
                entered: energy.toStringAsFixed(0),
                unit: NutrientUnit.kilocalorie,
              ),
              protein: NutrientAmount.complete(
                value: 100,
                entered: '100',
                unit: NutrientUnit.gram,
              ),
              carbohydrate: carbohydrate == null
                  ? NutrientAmount.unknown(NutrientUnit.gram)
                  : NutrientAmount.complete(
                      value: carbohydrate,
                      entered: carbohydrate.toStringAsFixed(0),
                      unit: NutrientUnit.gram,
                    ),
              fat: NutrientAmount.complete(
                value: 60,
                entered: '60',
                unit: NutrientUnit.gram,
              ),
            ),
            updatedAt: DateTime.utc(2026, 6, day, 8),
          ),
        ],
      ),
    ],
  );
}

class _FakeTrendsController extends NutritionTrendsController {
  _FakeTrendsController(this._state);

  final NutritionTrendsState _state;

  @override
  Stream<NutritionTrendsState> build() {
    return Stream<NutritionTrendsState>.value(_state);
  }
}
