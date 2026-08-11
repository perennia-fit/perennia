import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/features/nutrition/controllers/nutrition_day_controller.dart';

void main() {
  group('NutritionTrendsState', () {
    test('defensively copies collection inputs and exposes immutable views',
        () {
      final sourceDays = <NutritionDayRecord>[_emptyDay(26)];
      final sourceGoals = <NutrientId, NutritionGoalRecord>{
        NutrientId.energy: _goal(NutrientId.energy, 2400, '2400'),
      };

      final state = NutritionTrendsState(
        range: NutritionDayRange(
          start: const NutritionDayDate(year: 2026, month: 6, day: 20),
          end: const NutritionDayDate(year: 2026, month: 6, day: 26),
        ),
        days: sourceDays,
        goalsByNutrient: sourceGoals,
      );

      sourceDays.add(_emptyDay(27));
      sourceGoals[NutrientId.protein] = _goal(
        NutrientId.protein,
        180,
        '180',
      );

      expect(state.days.map((day) => day.localDate.day), <int>[26]);
      expect(state.goalsByNutrient.keys, <NutrientId>[NutrientId.energy]);
      expect(
        () => state.days.add(_emptyDay(28)),
        throwsUnsupportedError,
      );
      expect(
        () => state.goalsByNutrient.clear(),
        throwsUnsupportedError,
      );
    });
  });
}

NutritionDayRecord _emptyDay(int day) {
  return NutritionDayRecord(
    localDate: NutritionDayDate(year: 2026, month: 6, day: day),
    meals: const <NutritionDayMealRecord>[],
  );
}

NutritionGoalRecord _goal(
  NutrientId nutrient,
  double value,
  String entered,
) {
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
