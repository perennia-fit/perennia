import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/features/nutrition/controllers/nutrition_day_controller.dart';
import 'package:perennia/features/nutrition/widgets/nutrition_trends_view.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  testWidgets('renders goal progress per goalable nutrient for the anchor day',
      (tester) async {
    await _pumpTrends(tester, state: _stateWithGoals());

    for (final id in goalableNutrientIds) {
      expect(
        find.byKey(NutritionTrendsView.goalProgressKey(id)),
        findsOneWidget,
        reason: 'expected a goal progress tile for ${id.name}',
      );
    }

    // Energy: 2100 / 2400 → below, both values readable as text (not colour-only).
    final energyTile = find.byKey(
      NutritionTrendsView.goalProgressValueKey(NutrientId.energy),
    );
    expect(tester.widget<Text>(energyTile).data, contains('2100'));
    expect(tester.widget<Text>(energyTile).data, contains('2400'));
    expect(
      find.descendant(
        of: find.byKey(NutritionTrendsView.goalProgressKey(NutrientId.energy)),
        matching: find.textContaining('Under'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows a dash instead of 0 g for an unknown anchor total',
      (tester) async {
    await _pumpTrends(tester, state: _stateWithUnknownCarbs());

    final carbValue = find.byKey(
      NutritionTrendsView.goalProgressValueKey(NutrientId.carbohydrate),
    );
    // The logged total renders as a dash, never a coerced "0 g".
    expect(tester.widget<Text>(carbValue).data, startsWith('—'));
    expect(
      tester.widget<Text>(carbValue).data,
      isNot(contains('0 g of')),
    );
    // The unknown state is labelled, not implied by colour alone.
    expect(
      find.descendant(
        of: find.byKey(
          NutritionTrendsView.goalProgressKey(NutrientId.carbohydrate),
        ),
        matching: find.textContaining('Unknown'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('distinguishes a genuinely-zero total from an unknown one',
      (tester) async {
    await _pumpTrends(tester, state: _stateWithZeroFat());

    final fatValue = find.byKey(
      NutritionTrendsView.goalProgressValueKey(NutrientId.fat),
    );
    // A real zero shows "0 g", never a dash.
    expect(tester.widget<Text>(fatValue).data, contains('0 g'));
    expect(tester.widget<Text>(fatValue).data, isNot(contains('—')));
  });

  testWidgets('renders the trend chart with a goal reference line', (
    tester,
  ) async {
    await _pumpTrends(tester, state: _stateWithGoals());

    final chart = find.byKey(
      NutritionTrendsView.trendChartKey(NutrientId.energy),
    );
    await tester.scrollUntilVisible(
      chart,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(chart, findsOneWidget);
    // The configured target is surfaced as a reference, with its value labelled.
    expect(
      find.descendant(
        of: chart,
        matching: find.textContaining('Goal'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('is a read-only surface — no save/clear/recalculate controls',
      (tester) async {
    await _pumpTrends(tester, state: _stateWithGoals());

    // No write affordances: the surface only reads derived analytics.
    expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
    expect(find.text('Recalculate'), findsNothing);
    expect(find.textContaining('Repair'), findsNothing);
    // The only interactive control is the window toggle (a read selector).
    expect(find.byKey(NutritionTrendsView.windowToggleKey), findsOneWidget);
  });

  testWidgets('window toggle re-selects the trend window without writing',
      (tester) async {
    final controller = _FakeTrendsController(_stateWithGoals());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionTrendsControllerProvider.overrideWith(() => controller),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NutritionTrendsView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(NutritionTrendWindow.month.label));
    await tester.pumpAndSettle();

    expect(controller.selectedWindows, contains(NutritionTrendWindow.month));
  });

  testWidgets('Nutrition trends surface meets accessibility in both themes',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();

      await _pumpTrends(tester, state: _stateWithGoals(), theme: theme);

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
  required NutritionTrendsState state,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        nutritionTrendsControllerProvider.overrideWith(
          () => _FakeTrendsController(state),
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

class _FakeTrendsController extends NutritionTrendsController {
  _FakeTrendsController(this._state);

  final NutritionTrendsState _state;
  final selectedWindows = <NutritionTrendWindow>[];

  @override
  Stream<NutritionTrendsState> build() {
    return Stream<NutritionTrendsState>.value(_state);
  }

  @override
  void selectWindow(NutritionTrendWindow window) {
    selectedWindows.add(window);
  }
}

const _anchor = NutritionDayDate(year: 2026, month: 6, day: 26);

NutritionDayRange _weekRange() {
  return NutritionDayRange.trailing(_anchor, days: 7);
}

Map<NutrientId, NutritionGoalRecord> _allGoals() {
  return <NutrientId, NutritionGoalRecord>{
    NutrientId.energy: _goal(NutrientId.energy, 2400, '2400'),
    NutrientId.protein: _goal(NutrientId.protein, 180, '180'),
    NutrientId.carbohydrate: _goal(NutrientId.carbohydrate, 250, '250'),
    NutrientId.fat: _goal(NutrientId.fat, 70, '70'),
  };
}

NutritionTrendsState _stateWithGoals() {
  return NutritionTrendsState(
    range: _weekRange(),
    days: <NutritionDayRecord>[
      _day(24, energy: 1900, protein: 150, carbohydrate: 210, fat: 55),
      _day(26, energy: 2100, protein: 170, carbohydrate: 230, fat: 60),
    ],
    goalsByNutrient: _allGoals(),
  );
}

NutritionTrendsState _stateWithUnknownCarbs() {
  return NutritionTrendsState(
    range: _weekRange(),
    days: <NutritionDayRecord>[
      _day(26, energy: 2100, protein: 170, carbohydrate: null, fat: 60),
    ],
    goalsByNutrient: _allGoals(),
  );
}

NutritionTrendsState _stateWithZeroFat() {
  return NutritionTrendsState(
    range: _weekRange(),
    days: <NutritionDayRecord>[
      _day(26, energy: 2100, protein: 170, carbohydrate: 230, fat: 0),
    ],
    goalsByNutrient: _allGoals(),
  );
}

NutritionGoalRecord _goal(NutrientId nutrient, double value, String entered) {
  return NutritionGoalRecord(
    id: 'goal-${nutrient.name}',
    target: NutritionGoalTarget(
      nutrient: nutrient,
      value: value,
      entered: entered,
    ),
    updatedAt: DateTime.utc(2026, 6, 26),
  );
}

NutritionDayRecord _day(
  int day, {
  required double energy,
  required double protein,
  required double? carbohydrate,
  required double fat,
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
                value: protein,
                entered: protein.toStringAsFixed(0),
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
                value: fat,
                entered: fat.toStringAsFixed(0),
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
