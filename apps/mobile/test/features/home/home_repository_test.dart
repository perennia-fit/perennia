import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/home/repositories/home_repository.dart';

void main() {
  group('Home summary models', () {
    test('defensively copy collections and expose immutable views', () {
      final setA = const HomeSetSummary(
        id: 'set-a',
        description: 'Bench Press - 100 kg x 5',
      );
      final setB = const HomeSetSummary(
        id: 'set-b',
        description: 'Bench Press - 110 kg x 3',
      );
      final exerciseA = HomeWorkoutExerciseSummary(
        id: 'workout-exercise-a',
        workoutId: 'workout-a',
        exerciseId: 'exercise-a',
        name: 'Bench Press',
        type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
        sets: <HomeSetSummary>[setA],
      );
      final exerciseB = HomeWorkoutExerciseSummary(
        id: 'workout-exercise-b',
        workoutId: 'workout-b',
        exerciseId: 'exercise-b',
        name: 'Squat',
        type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
        sets: <HomeSetSummary>[setB],
      );
      final nestedExercises = <HomeWorkoutExerciseSummary>[exerciseA];
      final group = HomeExerciseGroupSummary(
        id: 'group-a',
        name: 'Superset 1',
        colorHex: '#2F6FED',
        workoutExerciseIds: <String>[
          'workout-exercise-a',
          'workout-exercise-b',
        ],
      );
      final exerciseGroups = <HomeExerciseGroupSummary>[group];
      final workoutA = HomeWorkoutSummary(
        id: 'workout-a',
        startedAt: DateTime.utc(2026, 6, 16, 8),
        localDate: const TrainingDayDate(year: 2026, month: 6, day: 16),
        workoutExercises: nestedExercises,
        exerciseGroups: exerciseGroups,
      );
      final workoutB = HomeWorkoutSummary(
        id: 'workout-b',
        startedAt: DateTime.utc(2026, 6, 17, 8),
        localDate: const TrainingDayDate(year: 2026, month: 6, day: 17),
        workoutExercises: <HomeWorkoutExerciseSummary>[exerciseB],
      );
      final workouts = <HomeWorkoutSummary>[workoutA];
      final workoutExercises = <HomeWorkoutExerciseSummary>[exerciseA];
      final exercises = <HomeExerciseSummary>[
        const HomeExerciseSummary(id: 'exercise-a', name: 'Bench Press'),
      ];
      final sets = <HomeSetSummary>[setA];

      final summary = HomeSummary(
        title: 'Training Day',
        selectedDate: const TrainingDayDate(year: 2026, month: 6, day: 16),
        status: '1 workout, 1 set',
        workouts: workouts,
        workoutExercises: workoutExercises,
        exercises: exercises,
        sets: sets,
      );

      nestedExercises.add(exerciseB);
      exerciseGroups.clear();
      workouts.add(workoutB);
      workoutExercises.add(exerciseB);
      exercises.add(const HomeExerciseSummary(id: 'exercise-b', name: 'Squat'));
      sets.add(setB);

      expect(workoutA.workoutExercises, <HomeWorkoutExerciseSummary>[
        exerciseA,
      ]);
      expect(workoutA.exerciseGroups, <HomeExerciseGroupSummary>[group]);
      expect(summary.workouts, <HomeWorkoutSummary>[workoutA]);
      expect(
        summary.workoutExercises,
        <HomeWorkoutExerciseSummary>[exerciseA],
      );
      expect(summary.exercises.map((exercise) => exercise.id), <String>[
        'exercise-a',
      ]);
      expect(summary.sets, <HomeSetSummary>[setA]);
      expect(
        () => workoutA.workoutExercises.add(exerciseB),
        throwsUnsupportedError,
      );
      expect(
        () => workoutA.exerciseGroups.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => group.workoutExerciseIds.add('workout-exercise-c'),
        throwsUnsupportedError,
      );
      expect(() => exerciseA.sets.add(setB), throwsUnsupportedError);
      expect(() => summary.workouts.add(workoutB), throwsUnsupportedError);
      expect(
        () => summary.workoutExercises.clear(),
        throwsUnsupportedError,
      );
      expect(() => summary.exercises.clear(), throwsUnsupportedError);
      expect(() => summary.sets.add(setB), throwsUnsupportedError);
    });
  });
}
