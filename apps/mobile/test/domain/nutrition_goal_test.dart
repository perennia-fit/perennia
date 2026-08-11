import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/domain/training/set_validation.dart';

void main() {
  group('goalable nutrient registry', () {
    test('v1 goals target only energy + the three macros', () {
      expect(
        goalableNutrientIds,
        <NutrientId>[
          NutrientId.energy,
          NutrientId.protein,
          NutrientId.carbohydrate,
          NutrientId.fat,
        ],
      );
      expect(isGoalableNutrient(NutrientId.energy), isTrue);
      expect(isGoalableNutrient(NutrientId.fiber), isFalse);
      expect(isGoalableNutrient(NutrientId.sodium), isFalse);
    });
  });

  group('NutritionGoalTarget', () {
    test('defaults the unit to the nutrient registry unit', () {
      final energy = NutritionGoalTarget(
        nutrient: NutrientId.energy,
        value: 2400,
        entered: '2400',
      );
      final protein = NutritionGoalTarget(
        nutrient: NutrientId.protein,
        value: 180,
        entered: '180',
      );

      expect(energy.unit, NutrientUnit.kilocalorie);
      expect(protein.unit, NutrientUnit.gram);
    });

    test('rejects a non-goalable nutrient', () {
      expect(
        () => NutritionGoalTarget(
          nutrient: NutrientId.sodium,
          value: 1500,
          entered: '1500',
        ),
        throwsArgumentError,
      );
    });

    test('rejects an empty entered value', () {
      expect(
        () => NutritionGoalTarget(
          nutrient: NutrientId.fat,
          value: 70,
          entered: '   ',
        ),
        throwsArgumentError,
      );
    });
  });

  group('NutritionGoalDraft', () {
    test('rejects two targets for the same nutrient', () {
      expect(
        () => NutritionGoalDraft(
          targets: <NutritionGoalTarget>[
            NutritionGoalTarget(
              nutrient: NutrientId.protein,
              value: 180,
              entered: '180',
            ),
            NutritionGoalTarget(
              nutrient: NutrientId.protein,
              value: 200,
              entered: '200',
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('indexes targets by nutrient', () {
      final draft = NutritionGoalDraft(
        targets: <NutritionGoalTarget>[
          NutritionGoalTarget(
            nutrient: NutrientId.energy,
            value: 2400,
            entered: '2400',
          ),
          NutritionGoalTarget(
            nutrient: NutrientId.carbohydrate,
            value: 250,
            entered: '250',
          ),
        ],
      );

      expect(draft.targetFor(NutrientId.energy)?.value, 2400);
      expect(draft.targetFor(NutrientId.carbohydrate)?.value, 250);
      expect(draft.targetFor(NutrientId.fat), isNull);
    });
  });

  group('validateNutritionGoalTargets reuses the shared two-tier validator', () {
    test('accepts energy + macro targets within the caps', () {
      final result = validateNutritionGoalTargets(<NutritionGoalTarget>[
        NutritionGoalTarget(
          nutrient: NutrientId.energy,
          value: 2400,
          entered: '2400',
        ),
        NutritionGoalTarget(
          nutrient: NutrientId.protein,
          value: 180,
          entered: '180',
        ),
        NutritionGoalTarget(
          nutrient: NutrientId.carbohydrate,
          value: 250,
          entered: '250',
        ),
        NutritionGoalTarget(
          nutrient: NutrientId.fat,
          value: 70,
          entered: '70',
        ),
      ]);

      expect(result.accepted, isTrue);
      expect(result.warnings, isEmpty);
    });

    test('hard-rejects a negative target with the shared non-negative rule', () {
      final result = validateNutritionGoalTargets(<NutritionGoalTarget>[
        NutritionGoalTarget(
          nutrient: NutrientId.protein,
          value: -1,
          entered: '-1',
        ),
      ]);

      expect(result.accepted, isFalse);
      expect(
        result.errors.single.rule,
        'nutrient_non_negative',
      );
      expect(result.errors.single.nutrient, NutrientId.protein);
    });

    test('hard-rejects an energy target past the absurd kcal cap', () {
      final result = validateNutritionGoalTargets(<NutritionGoalTarget>[
        NutritionGoalTarget(
          nutrient: NutrientId.energy,
          value: 10001,
          entered: '10001',
        ),
      ]);

      expect(result.accepted, isFalse);
      expect(
        result.errors.single.rule,
        'nutrient_energy_max_kilocalories',
      );
    });

    test('hard-rejects a macro target past the absurd gram cap', () {
      final result = validateNutritionGoalTargets(<NutritionGoalTarget>[
        NutritionGoalTarget(
          nutrient: NutrientId.carbohydrate,
          value: 2001,
          entered: '2001',
        ),
      ]);

      expect(result.accepted, isFalse);
      expect(result.errors.single.rule, 'nutrient_macro_max_grams');
    });

    test('throwIfRejected throws on an impossible target', () {
      final result = validateNutritionGoalTargets(<NutritionGoalTarget>[
        NutritionGoalTarget(
          nutrient: NutrientId.fat,
          value: 5000,
          entered: '5000',
        ),
      ]);

      expect(result.throwIfRejected, throwsA(isA<NutrientValidationException>()));
    });
  });
}
