import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/domain/training/set_validation.dart';
import 'package:perennia/domain/training/training_dimensions.dart';

void main() {
  group('set validation', () {
    test('hard-rejects impossible dimension values', () {
      final result = validateSetValues(
        type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
        loadMode: ExerciseLoadMode.added,
        values: const <SetDimensionValue>[
          SetDimensionValue(
            dimension: DimensionId.load,
            entered: '-1',
            unit: TrainingUnit.kilogram,
          ),
          SetDimensionValue(
            dimension: DimensionId.reps,
            entered: '2.5',
            unit: TrainingUnit.repetition,
          ),
        ],
      );

      expect(result.accepted, isFalse);
      expect(
        result.errors.map((error) => error.rule).toList(growable: false),
        <String>['numeric_non_negative', 'reps_integer'],
      );
      expect(
        result.throwIfRejected,
        throwsA(isA<SetValidationException>()),
      );
    });

    test('soft-warns improbable values while accepting the set', () {
      final result = validateSetValues(
        type: ExerciseType(<DimensionId>[
          DimensionId.duration,
          DimensionId.distance,
        ]),
        loadMode: ExerciseLoadMode.added,
        values: const <SetDimensionValue>[
          SetDimensionValue(
            dimension: DimensionId.duration,
            entered: '300',
            unit: TrainingUnit.second,
          ),
          SetDimensionValue(
            dimension: DimensionId.distance,
            entered: '5',
            unit: TrainingUnit.kilometer,
          ),
        ],
      );

      expect(result.accepted, isTrue);
      expect(result.errors, isEmpty);
      expect(
        result.warnings.map((warning) => warning.rule).toList(growable: false),
        <String>['implied_speed_improbable'],
      );
    });

    test('matches the shared golden vectors', () async {
      final vector = jsonDecode(
        await _vectorFile('m10-set-validation.json').readAsString(),
      ) as Map<String, Object?>;
      final cases = vector['cases']! as List<Object?>;

      for (final caseObject in cases) {
        final caseData = caseObject! as Map<String, Object?>;
        final input = caseData['input']! as Map<String, Object?>;
        final expected = caseData['expected']! as Map<String, Object?>;
        final exercise = input['exercise']! as Map<String, Object?>;
        final result = validateSetValues(
          type: ExerciseType(
            (exercise['dimensions']! as List<Object?>).map(
              (dimension) => DimensionId.values.byName(dimension! as String),
            ),
          ),
          loadMode: ExerciseLoadMode.values.byName(
            exercise['loadMode']! as String,
          ),
          values: _valuesFromVector(
            (input['values'] as Map<String, Object?>?) ?? <String, Object?>{},
          ),
          rpe: input['rpe'],
          side: input['side'] as String?,
        );
        final reason = caseData['name']! as String;

        expect(result.accepted, expected['accepted'], reason: reason);
        expect(
          result.warnings
              .map((warning) => warning.rule)
              .toList(growable: false),
          expected['warningRules'],
          reason: reason,
        );
        expect(
          result.errors.map((error) => error.rule).toList(growable: false),
          expected['errorRules'],
          reason: reason,
        );
      }
    });

    test('matches the shared nutrient golden vectors', () async {
      final vector = jsonDecode(
        await _vectorFile('m18-nutrient-validation.json').readAsString(),
      ) as Map<String, Object?>;
      final cases = vector['cases']! as List<Object?>;

      for (final caseObject in cases) {
        final caseData = caseObject! as Map<String, Object?>;
        final input = caseData['input']! as Map<String, Object?>;
        final expected = caseData['expected']! as Map<String, Object?>;
        final result = validateFoodEntryNutrition(
          nutrients: _nutrientsFromVector(
            input['nutrients']! as Map<String, Object?>,
          ),
          resolvedBaseQuantity: _resolvedBaseQuantityFromVector(
            input['portion'] as Map<String, Object?>?,
          ),
        );
        final reason = caseData['name']! as String;

        expect(result.accepted, expected['accepted'], reason: reason);
        expect(
          result.warnings
              .map((warning) => warning.rule)
              .toList(growable: false),
          expected['warningRules'],
          reason: reason,
        );
        expect(
          result.errors.map((error) => error.rule).toList(growable: false),
          expected['errorRules'],
          reason: reason,
        );
      }
    });

    test('matches the shared nutrition goal golden vectors', () async {
      final vector = jsonDecode(
        await _vectorFile('m33-nutrition-goal-validation.json')
            .readAsString(),
      ) as Map<String, Object?>;
      final cases = vector['cases']! as List<Object?>;

      for (final caseObject in cases) {
        final caseData = caseObject! as Map<String, Object?>;
        final input = caseData['input']! as Map<String, Object?>;
        final expected = caseData['expected']! as Map<String, Object?>;
        final result = validateNutritionGoalTargets(
          _goalTargetsFromVector(input['targets']! as List<Object?>),
        );
        final reason = caseData['name']! as String;

        expect(result.accepted, expected['accepted'], reason: reason);
        expect(
          result.warnings
              .map((warning) => warning.rule)
              .toList(growable: false),
          expected['warningRules'],
          reason: reason,
        );
        expect(
          result.errors.map((error) => error.rule).toList(growable: false),
          expected['errorRules'],
          reason: reason,
        );
      }
    });
  });
}

List<NutritionGoalTarget> _goalTargetsFromVector(List<Object?> targets) {
  return targets.map((targetObject) {
    final target = targetObject! as Map<String, Object?>;
    final value = (target['value']! as num).toDouble();
    return NutritionGoalTarget(
      nutrient: NutrientId.byStorageKey(target['nutrient']! as String),
      value: value,
      entered: value.toString(),
    );
  }).toList(growable: false);
}

List<SetDimensionValue> _valuesFromVector(Map<String, Object?> values) {
  return values.entries.map((entry) {
    final value = entry.value! as Map<String, Object?>;
    return SetDimensionValue(
      dimension: DimensionId.values.byName(entry.key),
      entered: value['entered']! as String,
      unit: TrainingUnit.values.byName(value['unit']! as String),
    );
  }).toList(growable: false);
}

NutrientVector _nutrientsFromVector(Map<String, Object?> nutrients) {
  return NutrientVector.full(
    <NutrientId, NutrientAmount>{
      for (final entry in nutrients.entries)
        NutrientId.byStorageKey(entry.key): _nutrientAmountFromVector(
          entry.value! as Map<String, Object?>,
        ),
    },
  );
}

NutrientAmount _nutrientAmountFromVector(Map<String, Object?> amount) {
  final unit = NutrientUnit.values.byName(amount['unit']! as String);
  final status = NutrientValueStatus.values.byName(
    amount['status']! as String,
  );
  return switch (status) {
    NutrientValueStatus.complete => NutrientAmount.complete(
        value: (amount['value']! as num).toDouble(),
        entered: amount['entered']! as String,
        unit: unit,
      ),
    NutrientValueStatus.unknown => NutrientAmount.unknown(unit),
  };
}

double? _resolvedBaseQuantityFromVector(Map<String, Object?>? portion) {
  if (portion == null) {
    return null;
  }
  return (portion['resolvedBaseQuantity']! as num).toDouble();
}

File _vectorFile(String name) {
  var directory = Directory.current;
  for (var depth = 0; depth < 6; depth += 1) {
    final candidate = File(
      '${directory.path}${Platform.pathSeparator}packages'
      '${Platform.pathSeparator}golden-vectors'
      '${Platform.pathSeparator}vectors'
      '${Platform.pathSeparator}$name',
    );
    if (candidate.existsSync()) {
      return candidate;
    }
    directory = directory.parent;
  }
  throw StateError('Golden vector not found: $name.');
}
