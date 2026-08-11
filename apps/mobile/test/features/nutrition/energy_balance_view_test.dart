import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/analytics/energy_balance.dart';
import 'package:perennia/domain/analytics/series_families.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/features/nutrition/controllers/nutrition_day_controller.dart';
import 'package:perennia/features/nutrition/widgets/nutrition_trends_view.dart';
import 'package:perennia/theme/theme.dart';

const _anchor = NutritionDayDate(year: 2026, month: 6, day: 26);

NutrientTotal _energyIn(double value, {bool isComplete = true}) {
  return NutrientTotal(
    id: NutrientId.energy,
    value: value,
    unit: NutrientUnit.kilocalorie,
    isComplete: isComplete,
  );
}

EnergyBalance _balance({
  required NutrientTotal energyIn,
  required double? energyOut,
}) {
  return EnergyBalance.derive(
    localDate: _anchor,
    energyIn: energyIn,
    energyOut: energyOut,
  );
}

void main() {
  testWidgets('shows energy-in, energy-out, and the net for the day',
      (tester) async {
    await _pumpTrends(
      tester,
      balance: _balance(energyIn: _energyIn(2100), energyOut: 2600),
    );

    final section = await _scrollToBalance(tester);
    expect(section, findsOneWidget);

    // Both inputs are legible…
    expect(
      find.descendant(of: section, matching: find.text('2100 kcal')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: section, matching: find.text('2600 kcal')),
      findsOneWidget,
    );
    // …and the net (in − out) is shown.
    final netValue = find.byKey(NutritionTrendsView.energyBalanceNetKey);
    expect(netValue, findsOneWidget);
    expect(tester.widget<Text>(netValue).data, contains('500'));
  });

  testWidgets('labels which side is derived intake and which is a measured '
      'Metric (more than colour)', (tester) async {
    await _pumpTrends(
      tester,
      balance: _balance(energyIn: _energyIn(2100), energyOut: 2600),
    );

    await _scrollToBalance(tester);

    // The in-side is named as a derived nutrition analytic.
    final inRow = find.byKey(NutritionTrendsView.energyBalanceInKey);
    expect(
      find.descendant(of: inRow, matching: find.textContaining('Energy in')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: inRow,
        matching: find.textContaining(SeriesFamily.nutritionAnalytic.label),
      ),
      findsOneWidget,
    );
    // The out-side is named as a measured Metric.
    final outRow = find.byKey(NutritionTrendsView.energyBalanceOutKey);
    expect(
      find.descendant(of: outRow, matching: find.textContaining('Energy out')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: outRow,
        matching: find.textContaining(SeriesFamily.metric.label),
      ),
      findsOneWidget,
    );
    // Each side is iconographically distinct (a non-colour signal).
    expect(
      find.descendant(
        of: inRow,
        matching: find.byIcon(Icons.restaurant_outlined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: outRow,
        matching: find.byIcon(Icons.monitor_heart_outlined),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows an indeterminate net when the out-side is missing, never '
      'a fabricated 0', (tester) async {
    await _pumpTrends(
      tester,
      balance: _balance(energyIn: _energyIn(2100), energyOut: null),
    );

    final section = await _scrollToBalance(tester);

    final netValue = find.byKey(NutritionTrendsView.energyBalanceNetKey);
    // The net is a dash, not a number — no implicit zero out-side.
    expect(tester.widget<Text>(netValue).data, '—');
    // The known in-side is still surfaced; the out-side reads as a dash.
    expect(
      find.descendant(of: section, matching: find.text('2100 kcal')),
      findsOneWidget,
    );
    final outRow = find.byKey(NutritionTrendsView.energyBalanceOutKey);
    expect(
      find.descendant(of: outRow, matching: find.text('—')),
      findsOneWidget,
    );
    // An explanation of why the net is indeterminate is present.
    expect(
      find.descendant(
        of: section,
        matching: find.textContaining('indeterminate'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows an indeterminate net when the in-side is incomplete',
      (tester) async {
    await _pumpTrends(
      tester,
      balance: _balance(
        energyIn: _energyIn(1800, isComplete: false),
        energyOut: 2600,
      ),
    );

    await _scrollToBalance(tester);

    final netValue = find.byKey(NutritionTrendsView.energyBalanceNetKey);
    expect(tester.widget<Text>(netValue).data, '—');
    // The incomplete in-side reads as a dash, never the underlying 1800.
    final inRow = find.byKey(NutritionTrendsView.energyBalanceInKey);
    expect(
      find.descendant(of: inRow, matching: find.text('—')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: inRow, matching: find.textContaining('1800')),
      findsNothing,
    );
  });

  testWidgets('energy balance section meets accessibility in both themes',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();

      await _pumpTrends(
        tester,
        balance: _balance(energyIn: _energyIn(2100), energyOut: 2600),
        theme: theme,
      );
      await _scrollToBalance(tester);

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

Future<Finder> _scrollToBalance(WidgetTester tester) async {
  final section = find.byKey(NutritionTrendsView.energyBalanceSectionKey);
  await tester.scrollUntilVisible(
    section,
    400,
    scrollable: find.byType(Scrollable).first,
  );
  return section;
}

Future<void> _pumpTrends(
  WidgetTester tester, {
  required EnergyBalance balance,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        nutritionTrendsControllerProvider.overrideWith(
          () => _FakeTrendsController(_trendsState()),
        ),
        seriesFamiliesProvider.overrideWithValue(
          AsyncData<TwoSeriesFamilies>(
            TwoSeriesFamilies(
              metricSeries: const <TrendSeries>[],
              nutritionSeries: const <TrendSeries>[],
            ),
          ),
        ),
        energyBalanceProvider.overrideWithValue(
          AsyncData<EnergyBalance>(balance),
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

NutritionTrendsState _trendsState() {
  return NutritionTrendsState(
    range: NutritionDayRange.trailing(_anchor, days: 7),
    days: const <NutritionDayRecord>[],
    goalsByNutrient: const <NutrientId, NutritionGoalRecord>{},
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
