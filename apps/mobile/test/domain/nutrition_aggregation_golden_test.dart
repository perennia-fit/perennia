import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';

/// Device-side half of the m23 nutrition aggregation golden-vector parity proof.
///
/// The same `packages/golden-vectors/vectors/m23-nutrition-aggregation.json`
/// cases are consumed by the server analytics test
/// (apps/server/test/nutrition-analytics.golden.test.mjs). Both must reproduce
/// the identical canonical totals/goal-progress so an agent and the phone never
/// disagree for the same range (NUTRITION.md §2, §8).
void main() {
  final vectorFile = File(
    '../../packages/golden-vectors/vectors/m23-nutrition-aggregation.json',
  );

  test('device nutrition aggregation matches the shared golden vectors', () {
    expect(vectorFile.existsSync(), isTrue,
        reason: 'golden vector file must exist at ${vectorFile.path}');
    final vector =
        jsonDecode(vectorFile.readAsStringSync()) as Map<String, Object?>;
    expect(vector['domain'], 'nutrition-analytics');

    final cases = vector['cases']! as List<Object?>;
    var casesChecked = 0;
    for (final rawCase in cases) {
      final vectorCase = rawCase! as Map<String, Object?>;
      final reason = vectorCase['name']! as String;
      casesChecked += 1;

      final days = (vectorCase['days']! as List<Object?>)
          .map((day) => _dayFromJson(day! as Map<String, Object?>))
          .toList(growable: false);

      final totalsByDate = <String, NutrientTotals>{
        for (final day in days) day.localDate.storageValue: day.totals,
      };
      final periodTotals = NutrientTotals.fromEntries(
        days.expand((day) => day.meals).expand((meal) => meal.entries),
      );

      final expected = vectorCase['expected']! as Map<String, Object?>;

      // Per-day totals.
      final dayTotals = expected['dayTotals']! as Map<String, Object?>;
      dayTotals.forEach((localDate, rawTotals) {
        final totals = totalsByDate[localDate];
        expect(totals, isNotNull,
            reason: '$reason: missing computed totals for $localDate');
        _assertTotals(totals!, rawTotals! as Map<String, Object?>,
            '$reason day $localDate');
      });

      // Period totals.
      _assertTotals(periodTotals,
          expected['periodTotals']! as Map<String, Object?>, '$reason period');

      // Goal progress over the period totals.
      final goals = (vectorCase['goals'] as Map<String, Object?>?) ??
          const <String, Object?>{};
      final goalProgress =
          (expected['goalProgress'] as Map<String, Object?>?) ??
              const <String, Object?>{};
      goalProgress.forEach((nutrientKey, rawExpected) {
        final nutrient = NutrientId.byStorageKey(nutrientKey);
        final expectedProgress = rawExpected! as Map<String, Object?>;
        final goalValue = goals[nutrientKey];
        final target = goalValue == null
            ? null
            : NutritionGoalTarget(
                nutrient: nutrient,
                value: (goalValue as num).toDouble(),
                entered: goalValue.toString(),
              );
        final progress = NutrientGoalProgress.derive(
          total: periodTotals[nutrient],
          target: target,
        );

        expect(progress.status.name, expectedProgress['status'],
            reason: '$reason $nutrientKey status');
        _expectNullableClose(progress.ratio, expectedProgress['ratio'],
            '$reason $nutrientKey ratio');
        _expectNullableClose(progress.remaining, expectedProgress['remaining'],
            '$reason $nutrientKey remaining');
      });
    }

    expect(casesChecked, greaterThan(0));
  });
}

NutritionDayRecord _dayFromJson(Map<String, Object?> json) {
  final localDate = NutritionDayDate.parse(json['localDate']! as String);
  final entries = (json['entries']! as List<Object?>)
      .asMap()
      .entries
      .map((entry) => _entryFromJson(entry.key, entry.value! as Map<String, Object?>))
      .toList(growable: false);

  // A single synthetic Meal carries the day's entries; aggregation is over the
  // entries, so the Meal shape is irrelevant beyond grouping.
  final meal = MealRecord(
    id: 'meal-${localDate.storageValue}',
    mealType: 'Vector',
    startedAt: DateTime.utc(localDate.year, localDate.month, localDate.day),
    timezone: 'UTC',
    localDate: localDate,
    updatedAt: DateTime.utc(localDate.year, localDate.month, localDate.day),
  );

  return NutritionDayRecord(
    localDate: localDate,
    meals: <NutritionDayMealRecord>[
      NutritionDayMealRecord(meal: meal, entries: entries),
    ],
  );
}

FoodEntryRecord _entryFromJson(int position, Map<String, Object?> json) {
  final kind = json['kind']! as String;
  final nutrients = _nutrientVectorFromJson(
    json['nutrients']! as Map<String, Object?>,
  );

  if (kind == 'quickEntry') {
    return FoodEntryRecord(
      id: 'entry-$position',
      mealId: 'meal',
      kind: FoodEntryKind.quickEntry,
      position: position,
      name: 'Quick',
      nutrients: nutrients,
      updatedAt: DateTime.utc(2026, 6, 24),
    );
  }

  // A reference Food snapshots its per-100 vector; the resolved base quantity is
  // expressed as a gram Portion so resolvedBaseQuantity passes it through
  // unchanged, exercising the same per-100 scaling path the UI uses.
  final baseQuantity = (json['resolvedBaseQuantity']! as num).toDouble();
  return FoodEntryRecord(
    id: 'entry-$position',
    mealId: 'meal',
    kind: FoodEntryKind.food,
    position: position,
    name: 'Food',
    nutrients: nutrients,
    foodId: 'food-$position',
    foodSource: FoodSource.usda,
    isLiquid: false,
    portion: Portion(
      value: baseQuantity,
      entered: baseQuantity.toString(),
      unit: PortionUnit.gram,
    ),
    updatedAt: DateTime.utc(2026, 6, 24),
  );
}

NutrientVector _nutrientVectorFromJson(Map<String, Object?> json) {
  final amounts = <NutrientId, NutrientAmount>{};
  json.forEach((key, rawAmount) {
    final id = NutrientId.byStorageKey(key);
    final amount = rawAmount! as Map<String, Object?>;
    if (amount['status'] == 'complete') {
      final value = (amount['value']! as num).toDouble();
      amounts[id] = NutrientAmount.complete(
        value: value,
        entered: value.toString(),
        unit: id.defaultUnit,
      );
    } else {
      amounts[id] = NutrientAmount.unknown(id.defaultUnit);
    }
  });

  return NutrientVector.full(amounts);
}

void _assertTotals(
  NutrientTotals totals,
  Map<String, Object?> expected,
  String reason,
) {
  expected.forEach((nutrientKey, rawExpected) {
    final nutrient = NutrientId.byStorageKey(nutrientKey);
    final total = totals[nutrient];
    final expectedTotal = rawExpected! as Map<String, Object?>;
    expect(total.isComplete, expectedTotal['complete'],
        reason: '$reason $nutrientKey complete');
    if (expectedTotal.containsKey('value')) {
      expect(total.value,
          closeTo((expectedTotal['value']! as num).toDouble(), 0.000001),
          reason: '$reason $nutrientKey value');
    }
  });
}

void _expectNullableClose(double? actual, Object? expected, String reason) {
  if (expected == null) {
    expect(actual, isNull, reason: reason);
    return;
  }
  expect(actual, isNotNull, reason: reason);
  expect(actual!, closeTo((expected as num).toDouble(), 0.000001),
      reason: reason);
}
