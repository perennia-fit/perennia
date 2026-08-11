import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/template_materialize.dart';
import 'package:perennia/domain/training/training_dimensions.dart';

void main() {
  group('Template materialize', () {
    test('matches the shared plan-materialize golden vectors', () async {
      final vector = jsonDecode(
        await _vectorFile('m34-plan-materialize.json').readAsString(),
      ) as Map<String, Object?>;
      expect(vector['domain'], 'template-materialize');
      expect(vector['schemaVersion'], 1);
      expect(vector['schema'], 'm34-plan-materialize.schema.json');

      for (final caseObject in vector['cases']! as List<Object?>) {
        final caseData = caseObject! as Map<String, Object?>;
        final input = caseData['input']! as Map<String, Object?>;
        final exercises = (input['exercises']! as List<Object?>)
            .map((raw) => _exerciseFrom(raw! as Map<String, Object?>));
        final groups = (input['groups']! as List<Object?>)
            .map((raw) => _groupFrom(raw! as Map<String, Object?>));

        final plan = materializeTemplateContent(
          exercises: exercises,
          groups: groups,
        );
        final actual = _planToJson(plan);
        final reason = caseData['name']! as String;

        expect(actual, caseData['expected'], reason: reason);
      }
    });

    test('a fixed Prescription without values is rejected', () {
      final exercise = MaterializeExerciseInput(
        exerciseId: 'exercise-1',
        dimensions: const <DimensionId>[DimensionId.reps],
        defaultLoadUnit: TrainingUnit.kilogram,
        prescriptions: const <MaterializePrescriptionInput>[
          MaterializePrescriptionInput(
            mode: MaterializePrescriptionMode.fixed,
            repeat: 1,
            restAfter: null,
          ),
        ],
      );

      expect(
        () => materializeTemplateContent(
          exercises: <MaterializeExerciseInput>[exercise],
          groups: const <MaterializeGroupInput>[],
        ),
        throwsArgumentError,
      );
    });

    test('zeroLoggedSetFor never fabricates a value for a completion-only '
        'Exercise', () {
      expect(
        zeroLoggedSetFor(
          dimensions: const <DimensionId>[],
          defaultLoadUnit: TrainingUnit.kilogram,
        ),
        LoggedSet.completion(),
      );
    });
  });
}

MaterializeExerciseInput _exerciseFrom(Map<String, Object?> raw) {
  return MaterializeExerciseInput(
    exerciseId: raw['exerciseId']! as String,
    dimensions: (raw['dimensions']! as List<Object?>)
        .map((value) => DimensionId.values.byName(value! as String)),
    defaultLoadUnit: TrainingUnit.values.byName(
      raw['defaultLoadUnit']! as String,
    ),
    prescriptions: (raw['prescriptions']! as List<Object?>).map((prescObject) {
      final prescription = prescObject! as Map<String, Object?>;
      final restSeconds = prescription['restAfterSeconds'] as int?;
      final fixedValuesRaw =
          prescription['fixedValues'] as Map<String, Object?>?;
      final lastPerformedRaw =
          prescription['lastPerformedValues'] as Map<String, Object?>?;
      return MaterializePrescriptionInput(
        mode: MaterializePrescriptionMode.values.byName(
          prescription['mode']! as String,
        ),
        fixedValues:
            fixedValuesRaw == null ? null : _loggedSetFrom(fixedValuesRaw),
        lastPerformedValues: lastPerformedRaw == null
            ? null
            : _loggedSetFrom(lastPerformedRaw),
        repeat: prescription['repeat']! as int,
        restAfter: restSeconds == null ? null : Duration(seconds: restSeconds),
      );
    }),
  );
}

MaterializeGroupInput _groupFrom(Map<String, Object?> raw) {
  return MaterializeGroupInput(
    name: raw['name']! as String,
    colorHex: raw['colorHex']! as String,
    memberExerciseIndexes:
        (raw['memberExerciseIndexes']! as List<Object?>).cast<int>(),
  );
}

LoggedSet _loggedSetFrom(Map<String, Object?> raw) {
  if (raw.isEmpty) {
    return LoggedSet.completion();
  }
  return LoggedSet.fromValues(
    raw.entries.map((entry) {
      final value = entry.value! as Map<String, Object?>;
      return SetDimensionValue(
        dimension: DimensionId.values.byName(entry.key),
        entered: value['entered']! as String,
        unit: TrainingUnit.values.byName(value['unit']! as String),
      );
    }),
  );
}

Map<String, Object?> _planToJson(MaterializedWorkoutPlan plan) {
  return <String, Object?>{
    'exercises': plan.exercises.map((exercise) {
      return <String, Object?>{
        'exerciseId': exercise.exerciseId,
        'sets': exercise.sets.map((set) {
          return <String, Object?>{
            'values': _loggedSetToJson(set.values),
            'plannedRestAfterSeconds': set.plannedRestAfter?.inSeconds,
          };
        }).toList(growable: false),
      };
    }).toList(growable: false),
    'groups': plan.groups.map((group) {
      return <String, Object?>{
        'name': group.name,
        'colorHex': group.colorHex,
        'memberExerciseIndexes': group.memberExerciseIndexes,
      };
    }).toList(growable: false),
  };
}

Map<String, Object?> _loggedSetToJson(LoggedSet values) {
  return <String, Object?>{
    for (final dimension in DimensionId.values)
      if (values.valueFor(dimension) case final value?)
        dimension.name: <String, Object?>{
          'entered': value.entered,
          'unit': value.unit.name,
        },
  };
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
