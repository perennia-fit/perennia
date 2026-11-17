import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/domain/training/training_records.dart';
import 'package:perennia/domain/training/workout_share_summary.dart';

void main() {
  final startedAt = DateTime.utc(2026, 6, 16, 7);
  final day = TrainingDayDate.fromDateTime(DateTime(2026, 6, 16));

  WorkoutSessionRecord workout({DateTime? endedAt, String? comment}) {
    return WorkoutSessionRecord(
      id: 'w1',
      startedAt: startedAt,
      timezone: 'UTC',
      localDate: day,
      updatedAt: startedAt,
      endedAt: endedAt,
      comment: comment,
    );
  }

  ExerciseRecord exercise(String id, String name) {
    return ExerciseRecord(
      id: id,
      origin: ExerciseLibraryOrigin.user,
      name: name,
      type:
          ExerciseType(const <DimensionId>[DimensionId.load, DimensionId.reps]),
      defaultLoadUnit: TrainingUnit.kilogram,
      loadMode: ExerciseLoadMode.added,
      recordProfile: RecordProfile.repMax,
      categoryId: null,
      notes: null,
      isFavorite: false,
      updatedAt: startedAt,
    );
  }

  WorkoutExerciseRecord workoutExercise(String exerciseId, int position) {
    return WorkoutExerciseRecord(
      id: 'we-$exerciseId',
      workoutId: 'w1',
      exerciseId: exerciseId,
      position: position,
      updatedAt: startedAt,
    );
  }

  LoggedSetRecord set(
    String exerciseId,
    int position,
    List<SetDimensionValue> values, {
    bool isCompleted = false,
    SetSide? side,
    double? rpe,
    String? comment,
  }) {
    return LoggedSetRecord(
      id: 's-$exerciseId-$position',
      workoutId: 'w1',
      exerciseId: exerciseId,
      position: position,
      values: LoggedSet.fromValues(values),
      plannedRestAfter: null,
      isCompleted: isCompleted,
      updatedAt: startedAt,
      side: side,
      rpe: rpe,
      comment: comment,
    );
  }

  SetDimensionValue value(
      DimensionId dimension, String entered, TrainingUnit unit) {
    return SetDimensionValue(
        dimension: dimension, entered: entered, unit: unit);
  }

  test('an empty Workout says no exercises were logged', () {
    expect(
      workoutShareSummary(
        workout: workout(),
        workoutExercises: const <WorkoutExerciseRecord>[],
        sets: const <LoggedSetRecord>[],
        exercisesById: const <String, ExerciseRecord>{},
      ),
      'Workout on 2026-06-16\n'
      '\n'
      'No exercises logged.',
    );
  });

  test('pins the full summary layout', () {
    final summary = workoutShareSummary(
      workout: workout(
        endedAt: startedAt.add(const Duration(hours: 1, minutes: 30)),
        comment: '  Felt great  ',
      ),
      workoutExercises: <WorkoutExerciseRecord>[
        workoutExercise('squat', 0),
        workoutExercise('plank', 1),
      ],
      sets: <LoggedSetRecord>[
        set(
          'squat',
          0,
          <SetDimensionValue>[
            value(DimensionId.load, '100', TrainingUnit.kilogram),
            value(DimensionId.reps, '5', TrainingUnit.repetition),
          ],
          isCompleted: true,
          rpe: 8,
          comment: ' Smooth ',
        ),
        set(
          'squat',
          1,
          <SetDimensionValue>[
            value(DimensionId.load, '225', TrainingUnit.pound),
            value(DimensionId.reps, '3', TrainingUnit.repetition),
          ],
          side: SetSide.left,
          rpe: 8.5,
          comment: '   ',
        ),
        set('run', 2, <SetDimensionValue>[
          value(DimensionId.distance, '5', TrainingUnit.kilometer),
          value(DimensionId.duration, '1500', TrainingUnit.second),
        ]),
        set('carry', 3, <SetDimensionValue>[
          value(DimensionId.distance, '1.5', TrainingUnit.mile),
        ]),
        set('carry', 4, const <SetDimensionValue>[]),
      ],
      exercisesById: <String, ExerciseRecord>{
        'squat': exercise('squat', 'Back Squat'),
        'plank': exercise('plank', 'Plank'),
        'run': exercise('run', 'Run'),
      },
    );

    expect(
      summary,
      'Workout on 2026-06-16\n'
      'Duration: 1h 30m\n'
      'Comment: Felt great\n'
      '\n'
      'Back Squat\n'
      '- Set 1: 100 kg x 5 reps | completed | RPE 8\n'
      '  Note: Smooth\n'
      '- Set 2: 225 lb x 3 reps | left | RPE 8.5\n'
      '\n'
      'Plank\n'
      '- No sets logged\n'
      '\n'
      'Run\n'
      '- Set 1: 5 km in 1500 sec\n'
      '\n'
      'Unknown exercise\n'
      '- Set 1: 1.5 mi\n'
      '- Set 2: Completed',
    );
  });

  test('formats duration in whole hours, minutes, or seconds', () {
    String durationLine(Duration? elapsed) {
      final summary = workoutShareSummary(
        workout: workout(
          endedAt: elapsed == null ? null : startedAt.add(elapsed),
        ),
        workoutExercises: const <WorkoutExerciseRecord>[],
        sets: const <LoggedSetRecord>[],
        exercisesById: const <String, ExerciseRecord>{},
      );
      return summary.split('\n')[1];
    }

    expect(durationLine(const Duration(hours: 2)), 'Duration: 2h');
    expect(
      durationLine(const Duration(hours: 1, minutes: 5, seconds: 30)),
      'Duration: 1h 5m',
    );
    expect(
      durationLine(const Duration(minutes: 45, seconds: 10)),
      'Duration: 45m',
    );
    expect(durationLine(const Duration(seconds: 42)), 'Duration: 42s');
    expect(durationLine(Duration.zero), 'Duration: 0s');
    // An end before the start and an open Workout both omit the line.
    expect(durationLine(const Duration(minutes: -1)), '');
    expect(durationLine(null), '');
  });
}
