import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/plan_validation.dart';
import 'package:perennia/domain/training/set_validation.dart';
import 'package:perennia/domain/training/training_dimensions.dart';

void main() {
  group('plan validation', () {
    test('Prescription hard-rejects unknown modes and non-finite rest', () {
      final invalidMode = validatePrescription(
        mode: 'inherit',
        dimensions: const <DimensionId>[DimensionId.reps],
        loadMode: ExerciseLoadMode.added,
        repeat: 1,
        restAfterSeconds: null,
        values: const <SetDimensionValue>[],
      );
      expect(
        invalidMode.errors.map((issue) => issue.rule),
        contains('prescription_mode_invalid'),
      );

      final nonFiniteRest = validatePrescription(
        mode: 'copyPrevious',
        dimensions: const <DimensionId>[DimensionId.duration],
        loadMode: ExerciseLoadMode.added,
        repeat: 1,
        restAfterSeconds: double.infinity,
        values: const <SetDimensionValue>[],
      );
      expect(
        nonFiniteRest.errors.map((issue) => issue.rule),
        contains('prescription_rest_after_finite'),
      );
    });

    test('Template Group hard-rejects fractional and non-finite rounds', () {
      final cases = <({num rounds, String rule})>[
        (rounds: 1.5, rule: 'template_group_rounds_integer'),
        (rounds: double.infinity, rule: 'template_group_rounds_finite'),
        (rounds: double.nan, rule: 'template_group_rounds_finite'),
      ];

      for (final caseData in cases) {
        final result = validateTemplateGroup(
          name: 'Circuit',
          colorHex: '#2F6FED',
          rounds: caseData.rounds,
          memberIds: const <String>[
            'template-exercise-1',
            'template-exercise-2',
          ],
        );

        expect(
          result.errors.map((issue) => issue.rule),
          <String>[caseData.rule],
          reason: 'rounds=${caseData.rounds}',
        );
        expect(result.warnings, isEmpty);
      }
    });

    test('Routine Cadence hard-rejects non-finite window and slots', () {
      final window = validateRoutineCadence(
        cadenceKind: 'rotating',
        cadenceWindow: double.infinity,
        slots: const <num?>[1],
      );
      expect(
        window.errors.map((issue) => issue.rule),
        contains('cadence_window_finite'),
      );

      final slot = validateRoutineCadence(
        cadenceKind: 'weekly',
        cadenceWindow: null,
        slots: <num?>[double.nan],
      );
      expect(
        slot.errors.map((issue) => issue.rule),
        contains('routine_entry_slot_finite'),
      );
    });

    test('matches the shared plan-validation golden vectors', () async {
      final vector = jsonDecode(
        await _vectorFile('m33-plan-validation.json').readAsString(),
      ) as Map<String, Object?>;
      final limits = vector['limits']! as Map<String, Object?>;
      expect(
        limits,
        <String, Object?>{
          'repeatMin': PrescriptionValidationLimits.repeatMin,
          'repeatWarnAbove': PrescriptionValidationLimits.repeatWarnAbove,
          'restAfterSecondsMin':
              PrescriptionValidationLimits.restAfterSecondsMin,
          'templateGroupRoundsMin': TemplateGroupValidationLimits.roundsMin,
          'templateGroupMembersMin': TemplateGroupValidationLimits.membersMin,
          'templateGroupColorHexFormat':
              TemplateGroupValidationLimits.colorHexFormat,
          'cadenceKinds': RoutineCadenceValidationLimits.cadenceKinds,
          'rotatingWindowMin': RoutineCadenceValidationLimits.rotatingWindowMin,
          'rotatingWindowWarnAbove':
              RoutineCadenceValidationLimits.rotatingWindowWarnAbove,
          'weeklySlotMin': RoutineCadenceValidationLimits.weeklySlotMin,
          'weeklySlotMax': RoutineCadenceValidationLimits.weeklySlotMax,
          'routineEntrySlotMin':
              RoutineCadenceValidationLimits.routineEntrySlotMin,
        },
      );

      for (final caseObject in vector['cases']! as List<Object?>) {
        final caseData = caseObject! as Map<String, Object?>;
        final input = caseData['input']! as Map<String, Object?>;
        final expected = caseData['expected']! as Map<String, Object?>;
        final reason = caseData['name']! as String;
        final validator = caseData['validator']! as String;
        final SetValidationResult result = switch (validator) {
          'prescription' => validatePrescription(
              mode: input['mode']! as String,
              dimensions: _dimensionsFrom(
                input['dimensions']! as List<Object?>,
              ),
              loadMode: ExerciseLoadMode.values.byName(
                input['loadMode']! as String,
              ),
              repeat: input['repeat']! as num,
              restAfterSeconds: input['restAfterSeconds'] as num?,
              values: _valuesFrom(input['values']! as Map<String, Object?>),
            ),
          'templateGroup' => validateTemplateGroup(
              name: input['name']! as String,
              colorHex: input['colorHex']! as String,
              rounds: input['rounds']! as num,
              memberIds: (input['memberIds']! as List<Object?>).cast<String>(),
            ),
          'routineCadence' => validateRoutineCadence(
              cadenceKind: input['cadenceKind'] as String?,
              cadenceWindow: input['cadenceWindow'] as num?,
              slots: (input['slots']! as List<Object?>).cast<num?>(),
            ),
          _ => throw StateError('Unknown plan validator: $validator.'),
        };

        expect(result.accepted, expected['accepted'], reason: reason);
        expect(
          result.warnings.map((issue) => issue.rule).toList(growable: false),
          expected['warningRules'],
          reason: reason,
        );
        expect(
          result.errors.map((issue) => issue.rule).toList(growable: false),
          expected['errorRules'],
          reason: reason,
        );
      }
    });
  });
}

List<DimensionId> _dimensionsFrom(List<Object?> raw) {
  return raw
      .map((name) => DimensionId.values.byName(name! as String))
      .toList(growable: false);
}

List<SetDimensionValue> _valuesFrom(Map<String, Object?> raw) {
  return raw.entries.map((entry) {
    final value = entry.value! as Map<String, Object?>;
    return SetDimensionValue(
      dimension: DimensionId.values.byName(entry.key),
      entered: value['entered']! as String,
      unit: TrainingUnit.values.byName(value['unit']! as String),
    );
  }).toList(growable: false);
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
