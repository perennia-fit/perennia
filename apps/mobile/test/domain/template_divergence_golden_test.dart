import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/template_divergence.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/domain/training/workout_capture.dart';

void main() {
  group('Template divergence + Update', () {
    test('matches the shared plan-divergence golden vectors', () async {
      final vector = jsonDecode(
        await _vectorFile('m34-plan-divergence.json').readAsString(),
      ) as Map<String, Object?>;
      expect(vector['domain'], 'plan-divergence');
      expect(vector['schemaVersion'], templateDivergenceGoldenSchemaVersion);
      expect(vector['schema'], 'm34-plan-divergence.schema.json');

      for (final caseObject in vector['cases']! as List<Object?>) {
        final caseData = caseObject! as Map<String, Object?>;
        final reason = caseData['name']! as String;
        final template = _templateFrom(
          caseData['template']! as Map<String, Object?>,
        );
        final workout = _workoutFrom(
          caseData['workout']! as Map<String, Object?>,
        );
        final comparison = compareTemplateToWorkout(
          template: template,
          workout: workout,
        );
        final expected = caseData['expected']! as Map<String, Object?>;

        expect(
          _divergenceToJson(comparison.divergence),
          expected['divergence'],
          reason: reason,
        );
        expect(
          _updatedContentToJson(comparison.updatedContent),
          expected['updatedContent'],
          reason: reason,
        );
      }
    });

    test(
        'a template materialized and performed unchanged is zero divergence '
        'by construction, including copy-previous', () {
      final template = TemplateContentSnapshot(
        exercises: [
          TemplateDivergenceExerciseSnapshot(
            exerciseId: 'exercise-squat',
            exerciseName: 'Squat',
            prescriptions: [
              TemplateDivergencePrescriptionSnapshot(
                mode: TemplateDivergencePrescriptionMode.copyPrevious,
                // Storage never carries values for copy-previous.
                values: LoggedSet.completion(),
                repeat: 2,
                restAfter: const Duration(seconds: 120),
              ),
            ],
          ),
        ],
        groups: const [],
      );
      final resolvedValues = LoggedSet.fromValues(const [
        SetDimensionValue(
          dimension: DimensionId.load,
          entered: '80',
          unit: TrainingUnit.kilogram,
        ),
      ]);
      final workout = WorkoutCaptureSnapshot(
        workoutId: 'workout-x',
        exercises: [
          WorkoutCaptureExerciseSnapshot(
            sourceWorkoutExerciseId: 'we-squat',
            exerciseId: 'exercise-squat',
            exerciseName: 'Squat',
            position: 0,
            sets: [
              WorkoutCaptureSetSnapshot(
                sourceSetId: 'set-1',
                position: 0,
                values: resolvedValues,
                plannedRestAfter: const Duration(seconds: 120),
              ),
              WorkoutCaptureSetSnapshot(
                sourceSetId: 'set-2',
                position: 1,
                values: resolvedValues,
                plannedRestAfter: const Duration(seconds: 120),
              ),
            ],
          ),
        ],
        groups: const [],
      );

      final comparison = compareTemplateToWorkout(
        template: template,
        workout: workout,
      );

      expect(comparison.divergence.hasDivergence, isFalse);
      expect(
        comparison.updatedContent.exercises.single.prescriptions.single.mode,
        TemplateDivergencePrescriptionMode.copyPrevious,
      );
    });
  });
}

TemplateContentSnapshot _templateFrom(Map<String, Object?> raw) {
  return TemplateContentSnapshot(
    exercises: (raw['exercises']! as List<Object?>).map((exerciseObject) {
      final exercise = exerciseObject! as Map<String, Object?>;
      return TemplateDivergenceExerciseSnapshot(
        exerciseId: exercise['exerciseId']! as String,
        exerciseName: exercise['exerciseName']! as String,
        prescriptions:
            (exercise['prescriptions']! as List<Object?>).map((raw) {
          final prescription = raw! as Map<String, Object?>;
          final restSeconds = prescription['restAfterSeconds'] as int?;
          return TemplateDivergencePrescriptionSnapshot(
            mode: _modeFrom(prescription['mode']! as String),
            values: _loggedSetFrom(
              prescription['values']! as Map<String, Object?>,
            ),
            repeat: prescription['repeat']! as int,
            restAfter:
                restSeconds == null ? null : Duration(seconds: restSeconds),
          );
        }),
      );
    }),
    groups: (raw['groups']! as List<Object?>).map((groupObject) {
      final group = groupObject! as Map<String, Object?>;
      return TemplateDivergenceGroupSnapshot(
        memberExerciseIds:
            (group['memberExerciseIds']! as List<Object?>).cast<String>(),
      );
    }),
  );
}

WorkoutCaptureSnapshot _workoutFrom(Map<String, Object?> raw) {
  return WorkoutCaptureSnapshot(
    workoutId: raw['workoutId']! as String,
    exercises: (raw['exercises']! as List<Object?>).map((exerciseObject) {
      final exercise = exerciseObject! as Map<String, Object?>;
      return WorkoutCaptureExerciseSnapshot(
        sourceWorkoutExerciseId:
            exercise['sourceWorkoutExerciseId']! as String,
        exerciseId: exercise['exerciseId']! as String,
        exerciseName: exercise['exerciseName']! as String,
        position: exercise['position']! as int,
        sets: (exercise['sets']! as List<Object?>).map((setObject) {
          final set = setObject! as Map<String, Object?>;
          final restSeconds = set['plannedRestAfterSeconds'] as int?;
          return WorkoutCaptureSetSnapshot(
            sourceSetId: set['sourceSetId']! as String,
            position: set['position']! as int,
            values: _loggedSetFrom(set['values']! as Map<String, Object?>),
            plannedRestAfter:
                restSeconds == null ? null : Duration(seconds: restSeconds),
          );
        }),
      );
    }),
    groups: (raw['groups']! as List<Object?>).map((groupObject) {
      final group = groupObject! as Map<String, Object?>;
      return WorkoutCaptureGroupSnapshot(
        sourceGroupId: group['sourceGroupId']! as String,
        name: group['name']! as String,
        colorHex: group['colorHex']! as String,
        position: group['position']! as int,
        memberSourceWorkoutExerciseIds:
            (group['memberSourceWorkoutExerciseIds']! as List<Object?>)
                .cast<String>(),
      );
    }),
  );
}

TemplateDivergencePrescriptionMode _modeFrom(String raw) {
  return switch (raw) {
    'fixed' => TemplateDivergencePrescriptionMode.fixed,
    'copyPrevious' => TemplateDivergencePrescriptionMode.copyPrevious,
    _ => throw StateError('Unsupported Prescription mode: $raw.'),
  };
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

Map<String, Object?> _divergenceToJson(TemplateDivergenceResult result) {
  return <String, Object?>{
    'addedExercises': result.addedExercises.map(_exerciseRefToJson).toList(),
    'removedExercises':
        result.removedExercises.map(_exerciseRefToJson).toList(),
    'changedExercises':
        result.changedExercises.map(_exerciseRefToJson).toList(),
    'groupsChanged': result.groupsChanged,
  };
}

Map<String, Object?> _exerciseRefToJson(TemplateDivergenceExerciseRef ref) {
  return <String, Object?>{
    'exerciseId': ref.exerciseId,
    'exerciseName': ref.exerciseName,
  };
}

Map<String, Object?> _updatedContentToJson(TemplateUpdateContent content) {
  return <String, Object?>{
    'exercises': content.exercises.map((exercise) {
      return <String, Object?>{
        'exerciseId': exercise.exerciseId,
        'prescriptions': exercise.prescriptions.map((prescription) {
          return <String, Object?>{
            'mode': prescription.mode.name,
            'values': _loggedSetToJson(prescription.values),
            'repeat': prescription.repeat,
            'restAfterSeconds': prescription.restAfter?.inSeconds,
          };
        }).toList(),
      };
    }).toList(),
    'groups': content.groups.map((group) {
      return <String, Object?>{
        'name': group.name,
        'colorHex': group.colorHex,
        'rounds': TemplateUpdateGroupContent.rounds,
        'memberExerciseIndexes': group.memberExerciseIndexes,
      };
    }).toList(),
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
