import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/set_validation.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/domain/training/workout_capture.dart';

void main() {
  group('Workout capture', () {
    test('matches the shared capture golden vectors losslessly', () async {
      final vector = jsonDecode(
        await _vectorFile('m33-workout-capture.json').readAsString(),
      ) as Map<String, Object?>;
      expect(vector['domain'], 'workout-capture');
      expect(
        vector['schemaVersion'],
        workoutCaptureGoldenSchemaVersion,
      );
      expect(vector['schema'], 'm33-workout-capture.schema.json');

      for (final caseObject in vector['cases']! as List<Object?>) {
        final caseData = caseObject! as Map<String, Object?>;
        final snapshot = _snapshotFrom(
          caseData['input']! as Map<String, Object?>,
        );
        final content = captureWorkout(snapshot);
        final actual = <String, Object?>{
          'suggestedName': suggestCapturedWorkoutTemplateName(snapshot),
          ..._contentToJson(content),
        };
        final reason = caseData['name']! as String;

        expect(actual, caseData['expected'], reason: reason);
        expect(
          jsonEncode(actual),
          isNot(anyOf(contains('copyPrevious'), contains('copy-previous'))),
          reason: reason,
        );

        for (var index = 0; index < snapshot.exercises.length; index += 1) {
          expect(
            content.exercises[index].expandPrescriptions(),
            snapshot.exercises[index].sets
                .map((set) => set.projection)
                .toList(growable: false),
            reason: '$reason must expand to the projected source Sets',
          );
        }
      }
    });

    test('rejects group references that cannot form a Template tree', () {
      final exercise = WorkoutCaptureExerciseSnapshot(
        sourceWorkoutExerciseId: 'workout-exercise-1',
        exerciseId: 'exercise-1',
        exerciseName: 'Squat',
        position: 0,
        sets: const <WorkoutCaptureSetSnapshot>[],
      );

      expect(
        () => captureWorkout(
          WorkoutCaptureSnapshot(
            workoutId: 'workout-1',
            exercises: <WorkoutCaptureExerciseSnapshot>[exercise],
            groups: <WorkoutCaptureGroupSnapshot>[
              WorkoutCaptureGroupSnapshot(
                sourceGroupId: 'group-1',
                name: 'Circuit',
                colorHex: '#2F6FED',
                position: 0,
                memberSourceWorkoutExerciseIds: const <String>[
                  'missing-workout-exercise',
                ],
              ),
            ],
          ),
        ),
        throwsArgumentError,
      );
    });

    test('warning fingerprints preserve source paths and canonical map limits',
        () {
      const shared = SetValidationIssue(
        field: 'repeat',
        dimension: null,
        rule: 'same_rule',
        message: 'Same shared warning.',
        limit: <Object?, Object?>{2: 'two', 1: 'one'},
      );
      const first = WorkoutCaptureValidationIssue(
        sourcePath: 'exercises[0].prescriptions[0]',
        issue: shared,
      );
      const second = WorkoutCaptureValidationIssue(
        sourcePath: 'exercises[1].prescriptions[0]',
        issue: shared,
      );

      expect(first.acknowledgementToken, isNot(second.acknowledgementToken));
      expect(
        (jsonDecode(first.acknowledgementToken)
            as Map<String, Object?>)['limit'],
        <String, Object?>{'1': 'one', '2': 'two'},
      );
      final result = WorkoutCaptureValidationResult(
        warnings: const <WorkoutCaptureValidationIssue>[first, second],
      );
      expect(result.warningAcknowledgementTokens, hasLength(2));
    });
  });
}

WorkoutCaptureSnapshot _snapshotFrom(Map<String, Object?> raw) {
  return WorkoutCaptureSnapshot(
    workoutId: raw['workoutId']! as String,
    comment: raw['comment'] as String?,
    startedAt: _dateTimeFrom(raw['startedAt']),
    endedAt: _dateTimeFrom(raw['endedAt']),
    exercises: (raw['exercises']! as List<Object?>).map((exerciseObject) {
      final exercise = exerciseObject! as Map<String, Object?>;
      return WorkoutCaptureExerciseSnapshot(
        sourceWorkoutExerciseId: exercise['sourceWorkoutExerciseId']! as String,
        exerciseId: exercise['exerciseId']! as String,
        exerciseName: exercise['exerciseName']! as String,
        position: exercise['position']! as int,
        sets: (exercise['sets']! as List<Object?>).map((setObject) {
          final set = setObject! as Map<String, Object?>;
          final restSeconds = set['plannedRestAfterSeconds'] as int?;
          return WorkoutCaptureSetSnapshot(
            sourceSetId: set['sourceSetId']! as String,
            position: set['position']! as int,
            values: _loggedSetFrom(
              set['values']! as Map<String, Object?>,
            ),
            plannedRestAfter:
                restSeconds == null ? null : Duration(seconds: restSeconds),
            comment: set['comment'] as String?,
            side: set['side'] as String?,
            rpe: (set['rpe'] as num?)?.toDouble(),
            isCompleted: set['isCompleted']! as bool,
            performedAt: _dateTimeFrom(set['performedAt']),
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

DateTime? _dateTimeFrom(Object? raw) {
  return raw == null ? null : DateTime.parse(raw as String);
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

Map<String, Object?> _contentToJson(CapturedWorkoutTemplateContent content) {
  return <String, Object?>{
    'exercises': content.exercises.map((exercise) {
      return <String, Object?>{
        'exerciseId': exercise.exerciseId,
        'prescriptions': exercise.prescriptions.map((prescription) {
          return <String, Object?>{
            'mode': CapturedPrescriptionContent.mode,
            'values': _loggedSetToJson(prescription.values),
            'repeat': prescription.repeat,
            'restAfterSeconds': prescription.restAfter?.inSeconds,
          };
        }).toList(growable: false),
      };
    }).toList(growable: false),
    'groups': content.groups.map((group) {
      return <String, Object?>{
        'name': group.name,
        'colorHex': group.colorHex,
        'rounds': CapturedTemplateGroupContent.rounds,
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
