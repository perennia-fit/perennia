import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';

void main() {
  group('NutrientGoalProgress', () {
    test('derives ratio and met status from a complete total and a target', () {
      final progress = NutrientGoalProgress.derive(
        total: _completeTotal(NutrientId.protein, 180),
        target: _target(NutrientId.protein, 180, '180'),
      );

      expect(progress.nutrient, NutrientId.protein);
      expect(progress.hasGoal, isTrue);
      expect(progress.isUnknown, isFalse);
      expect(progress.ratio, closeTo(1.0, 1e-9));
      expect(progress.remaining, closeTo(0.0, 1e-9));
      expect(progress.status, NutrientGoalStatus.met);
    });

    test('reports below-target when the day under-shoots the goal', () {
      final progress = NutrientGoalProgress.derive(
        total: _completeTotal(NutrientId.energy, 1800),
        target: _target(NutrientId.energy, 2400, '2400'),
      );

      expect(progress.ratio, closeTo(0.75, 1e-9));
      expect(progress.remaining, closeTo(600, 1e-9));
      expect(progress.status, NutrientGoalStatus.below);
    });

    test('reports over-target when the day exceeds the goal', () {
      final progress = NutrientGoalProgress.derive(
        total: _completeTotal(NutrientId.carbohydrate, 320),
        target: _target(NutrientId.carbohydrate, 250, '250'),
      );

      expect(progress.ratio, closeTo(1.28, 1e-9));
      expect(progress.remaining, closeTo(-70, 1e-9));
      expect(progress.status, NutrientGoalStatus.over);
    });

    test('a genuinely-zero complete total is distinct from an unknown one', () {
      final zero = NutrientGoalProgress.derive(
        total: _completeTotal(NutrientId.fat, 0),
        target: _target(NutrientId.fat, 70, '70'),
      );

      expect(zero.isUnknown, isFalse);
      expect(zero.ratio, 0.0);
      expect(zero.status, NutrientGoalStatus.below);
    });

    test('an unknown (incomplete) total never produces a ratio', () {
      final progress = NutrientGoalProgress.derive(
        total: _incompleteTotal(NutrientId.fat),
        target: _target(NutrientId.fat, 70, '70'),
      );

      expect(progress.isUnknown, isTrue);
      expect(progress.ratio, isNull);
      expect(progress.remaining, isNull);
      expect(progress.status, NutrientGoalStatus.unknown);
    });

    test('no target leaves the total ungoaled but still readable', () {
      final progress = NutrientGoalProgress.derive(
        total: _completeTotal(NutrientId.protein, 120),
        target: null,
      );

      expect(progress.hasGoal, isFalse);
      expect(progress.ratio, isNull);
      expect(progress.status, NutrientGoalStatus.noGoal);
      expect(progress.total.value, 120);
    });
  });

  group('NutritionTrend', () {
    test('builds one point per requested day, ordered, with daily totals', () {
      final range = NutritionDayRange(
        start: const NutritionDayDate(year: 2026, month: 6, day: 24),
        end: const NutritionDayDate(year: 2026, month: 6, day: 26),
      );

      final trend = NutritionTrend.forNutrient(
        nutrient: NutrientId.energy,
        range: range,
        days: <NutritionDayRecord>[
          _dayWithEnergy(26, 2100),
          _dayWithEnergy(24, 1900),
          // 25th has no logged meals at all.
        ],
        target: _target(NutrientId.energy, 2400, '2400'),
      );

      expect(trend.nutrient, NutrientId.energy);
      expect(trend.target?.value, 2400);
      expect(trend.points, hasLength(3));
      expect(
        trend.points.map((point) => point.localDate.day),
        <int>[24, 25, 26],
      );
      // A day with no meals is genuinely zero — its energy total is complete 0.
      final empty = trend.points[1];
      expect(empty.localDate.day, 25);
      expect(empty.isUnknown, isFalse);
      expect(empty.total.value, 0);
    });

    test('a day with an unreported nutrient is unknown, never zero', () {
      final range = NutritionDayRange(
        start: const NutritionDayDate(year: 2026, month: 6, day: 25),
        end: const NutritionDayDate(year: 2026, month: 6, day: 26),
      );

      final trend = NutritionTrend.forNutrient(
        nutrient: NutrientId.carbohydrate,
        range: range,
        days: <NutritionDayRecord>[
          // 25th: a full meal with known carbs (genuinely some grams).
          _dayWithEnergy(25, 2000, carbohydrate: 220),
          // 26th: a quick entry that only recorded energy → carbs unknown.
          _dayEnergyOnly(26, 1500),
        ],
        target: _target(NutrientId.carbohydrate, 250, '250'),
      );

      final known = trend.points.firstWhere((p) => p.localDate.day == 25);
      final unknown = trend.points.firstWhere((p) => p.localDate.day == 26);

      expect(known.isUnknown, isFalse);
      expect(known.total.value, 220);
      // The unknown carb day must not read as 0 g — it is flagged incomplete.
      expect(unknown.isUnknown, isTrue);
      expect(unknown.total.isComplete, isFalse);
    });

    test('exposes the complete points used for the rendered line', () {
      final range = NutritionDayRange(
        start: const NutritionDayDate(year: 2026, month: 6, day: 25),
        end: const NutritionDayDate(year: 2026, month: 6, day: 26),
      );

      final trend = NutritionTrend.forNutrient(
        nutrient: NutrientId.carbohydrate,
        range: range,
        days: <NutritionDayRecord>[
          _dayWithEnergy(25, 2000, carbohydrate: 220),
          _dayEnergyOnly(26, 1500),
        ],
        target: null,
      );

      // Only the complete carb day contributes a plottable value; the unknown
      // day is held out of the line so it never reads as a 0 g dip.
      expect(trend.completePoints, hasLength(1));
      expect(trend.completePoints.single.localDate.day, 25);
      expect(trend.hasCompletePoints, isTrue);
    });
  });

  group('NutritionDayRange', () {
    test('enumerates each calendar day inclusively', () {
      final range = NutritionDayRange(
        start: const NutritionDayDate(year: 2026, month: 6, day: 28),
        end: const NutritionDayDate(year: 2026, month: 7, day: 1),
      );

      expect(
        range.days.map((day) => day.storageValue),
        <String>['2026-06-28', '2026-06-29', '2026-06-30', '2026-07-01'],
      );
      expect(range.dayCount, 4);
    });

    test('a trailing window ends on the anchor day', () {
      final range = NutritionDayRange.trailing(
        const NutritionDayDate(year: 2026, month: 6, day: 26),
        days: 7,
      );

      expect(range.dayCount, 7);
      expect(range.end.storageValue, '2026-06-26');
      expect(range.start.storageValue, '2026-06-20');
    });

    test('rejects an inverted range', () {
      expect(
        () => NutritionDayRange(
          start: const NutritionDayDate(year: 2026, month: 6, day: 26),
          end: const NutritionDayDate(year: 2026, month: 6, day: 24),
        ),
        throwsArgumentError,
      );
    });
  });
}

NutrientTotal _completeTotal(NutrientId id, double value) {
  return NutrientTotal(
    id: id,
    value: value,
    unit: id.defaultUnit,
    isComplete: true,
  );
}

NutrientTotal _incompleteTotal(NutrientId id) {
  return NutrientTotal(
    id: id,
    value: 0,
    unit: id.defaultUnit,
    isComplete: false,
  );
}

NutritionGoalTarget _target(NutrientId id, double value, String entered) {
  return NutritionGoalTarget(nutrient: id, value: value, entered: entered);
}

NutritionDayRecord _dayWithEnergy(
  int day,
  double energy, {
  double? carbohydrate,
}) {
  final localDate = NutritionDayDate(year: 2026, month: 6, day: day);
  final nutrients = NutrientVector.energyAndMacros(
    energy: NutrientAmount.complete(
      value: energy,
      entered: energy.toString(),
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
            entered: carbohydrate.toString(),
            unit: NutrientUnit.gram,
          ),
    fat: NutrientAmount.complete(
      value: 60,
      entered: '60',
      unit: NutrientUnit.gram,
    ),
  );

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
            nutrients: nutrients,
            updatedAt: DateTime.utc(2026, 6, day, 8),
          ),
        ],
      ),
    ],
  );
}

NutritionDayRecord _dayEnergyOnly(int day, double energy) {
  final localDate = NutritionDayDate(year: 2026, month: 6, day: day);
  return NutritionDayRecord(
    localDate: localDate,
    meals: [
      NutritionDayMealRecord(
        meal: MealRecord(
          id: 'meal-$day',
          mealType: 'Snack',
          startedAt: DateTime.utc(2026, 6, day, 15),
          timezone: 'UTC',
          localDate: localDate,
          updatedAt: DateTime.utc(2026, 6, day, 15),
        ),
        entries: [
          FoodEntryRecord(
            id: 'entry-$day',
            mealId: 'meal-$day',
            kind: FoodEntryKind.quickEntry,
            position: 0,
            name: 'Quick calories',
            nutrients: NutrientVector.full(<NutrientId, NutrientAmount>{
              NutrientId.energy: NutrientAmount.complete(
                value: energy,
                entered: energy.toString(),
                unit: NutrientUnit.kilocalorie,
              ),
            }),
            updatedAt: DateTime.utc(2026, 6, day, 15),
          ),
        ],
      ),
    ],
  );
}
