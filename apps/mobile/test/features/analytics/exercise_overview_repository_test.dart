import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/analytics/repositories/exercise_overview_repository.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';

void main() {
  group('exercise overview model', () {
    test('groups history by workout and totals strength volume and reps', () {
      final exercise = _exercise(
        type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
      );
      final workout = _workout('workout-a', DateTime.utc(2026, 6, 16));
      final overview = buildExerciseOverviewModel(
        exercise: exercise,
        workouts: <WorkoutSessionRecord>[workout],
        sets: <LoggedSetRecord>[
          _set(
            'set-a',
            workoutId: workout.id,
            exerciseId: exercise.id,
            position: 0,
            values: _loadReps(load: '100', reps: '5'),
            comment: 'Felt smooth',
          ),
          _set(
            'set-b',
            workoutId: workout.id,
            exerciseId: exercise.id,
            position: 1,
            values: _loadReps(load: '110', reps: '3'),
          ),
        ],
      );

      expect(overview.groups, hasLength(1));
      expect(overview.groups.single.sets.map((set) => set.id), <String>[
        'set-a',
        'set-b',
      ]);
      expect(overview.groups.single.totalReps, 8);
      expect(overview.groups.single.volume, 830);
      expect(overview.groups.single.distance, isNull);
      expect(overview.groups.single.duration, isNull);
    });

    test('groups cardio history by distance and duration', () {
      final exercise = _exercise(
        type: ExerciseType(<DimensionId>[
          DimensionId.distance,
          DimensionId.duration,
        ]),
      );
      final workout = _workout('workout-cardio', DateTime.utc(2026, 6, 17));
      final overview = buildExerciseOverviewModel(
        exercise: exercise,
        workouts: <WorkoutSessionRecord>[workout],
        sets: <LoggedSetRecord>[
          _set(
            'run-a',
            workoutId: workout.id,
            exerciseId: exercise.id,
            position: 0,
            values: _distanceDuration(km: '5', seconds: '1500'),
          ),
          _set(
            'run-b',
            workoutId: workout.id,
            exerciseId: exercise.id,
            position: 1,
            values: _distanceDuration(km: '2.5', seconds: '900'),
          ),
        ],
      );

      expect(overview.groups.single.distance, 7.5);
      expect(overview.groups.single.duration, const Duration(seconds: 2400));
      expect(overview.groups.single.volume, isNull);
      expect(overview.groups.single.totalReps, isNull);
    });

    test('assisted exercises omit volume instead of rendering zero', () {
      final exercise = _exercise(
        type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
        loadMode: ExerciseLoadMode.assisted,
      );
      final workout = _workout('workout-assisted', DateTime.utc(2026, 6, 18));
      final overview = buildExerciseOverviewModel(
        exercise: exercise,
        workouts: <WorkoutSessionRecord>[workout],
        sets: <LoggedSetRecord>[
          _set(
            'assist-a',
            workoutId: workout.id,
            exerciseId: exercise.id,
            position: 0,
            values: _loadReps(load: '20', reps: '5'),
          ),
        ],
      );

      expect(overview.groups.single.volume, isNull);
      expect(overview.groups.single.totalReps, 5);
    });

    test('weekly groups honor the configured week start day', () {
      final exercise = _exercise(
        type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
      );
      final sundayWorkout = _workout('workout-sun', DateTime.utc(2026, 6, 14));
      final mondayWorkout = _workout('workout-mon', DateTime.utc(2026, 6, 15));
      final sets = <LoggedSetRecord>[
        _set(
          'set-sun',
          workoutId: sundayWorkout.id,
          exerciseId: exercise.id,
          position: 0,
          values: _loadReps(load: '100', reps: '5'),
        ),
        _set(
          'set-mon',
          workoutId: mondayWorkout.id,
          exerciseId: exercise.id,
          position: 0,
          values: _loadReps(load: '110', reps: '5'),
        ),
      ];

      final mondayStart = buildExerciseOverviewModel(
        exercise: exercise,
        workouts: <WorkoutSessionRecord>[sundayWorkout, mondayWorkout],
        sets: sets,
      );
      final sundayStart = buildExerciseOverviewModel(
        exercise: exercise,
        workouts: <WorkoutSessionRecord>[sundayWorkout, mondayWorkout],
        sets: sets,
        weekStartDay: WeekStartDay.sunday,
      );

      expect(
        mondayStart.weeklyGroups.map((group) => group.weekStart.storageValue),
        <String>['2026-06-15', '2026-06-08'],
      );
      expect(sundayStart.weeklyGroups, hasLength(1));
      expect(
          sundayStart.weeklyGroups.single.weekStart.storageValue, '2026-06-14');
      expect(sundayStart.weeklyGroups.single.setCount, 2);
      expect(sundayStart.weeklyGroups.single.totalReps, 10);
    });

    test('defensively copies collections and exposes immutable views', () {
      final exercise = _exercise(
        type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
      );
      final workoutA = _workout('workout-a', DateTime.utc(2026, 6, 16));
      final workoutB = _workout('workout-b', DateTime.utc(2026, 6, 17));
      final setA = _set(
        'set-a',
        workoutId: workoutA.id,
        exerciseId: exercise.id,
        position: 0,
        values: _loadReps(load: '100', reps: '5'),
      );
      final setB = _set(
        'set-b',
        workoutId: workoutB.id,
        exerciseId: exercise.id,
        position: 0,
        values: _loadReps(load: '110', reps: '3'),
      );
      final workoutSets = <LoggedSetRecord>[setA];
      final weekWorkouts = <WorkoutSessionRecord>[workoutA];
      final workoutGroup = ExerciseOverviewWorkoutGroup(
        workout: workoutA,
        sets: workoutSets,
        volume: 500,
        totalReps: 5,
        distance: null,
        duration: null,
      );
      final weekGroup = ExerciseOverviewWeekGroup(
        weekStart: TrainingDayDate.fromDateTime(workoutA.startedAt),
        workouts: weekWorkouts,
        setCount: 1,
        volume: 500,
        totalReps: 5,
        distance: null,
        duration: null,
      );
      final groups = <ExerciseOverviewWorkoutGroup>[workoutGroup];
      final weeklyGroups = <ExerciseOverviewWeekGroup>[weekGroup];
      final setsById = <String, LoggedSetRecord>{setA.id: setA};

      final overview = ExerciseOverviewModel(
        exercise: exercise,
        category: null,
        groups: groups,
        weeklyGroups: weeklyGroups,
        setsById: setsById,
      );

      workoutSets.add(setB);
      weekWorkouts.add(workoutB);
      groups.clear();
      weeklyGroups.clear();
      setsById[setB.id] = setB;

      expect(workoutGroup.sets.map((set) => set.id), <String>[setA.id]);
      expect(weekGroup.workouts.map((workout) => workout.id), <String>[
        workoutA.id,
      ]);
      expect(overview.groups, <ExerciseOverviewWorkoutGroup>[workoutGroup]);
      expect(overview.weeklyGroups, <ExerciseOverviewWeekGroup>[weekGroup]);
      expect(overview.setsById.keys, <String>[setA.id]);
      expect(() => workoutGroup.sets.add(setB), throwsUnsupportedError);
      expect(() => weekGroup.workouts.add(workoutB), throwsUnsupportedError);
      expect(() => overview.groups.clear(), throwsUnsupportedError);
      expect(() => overview.weeklyGroups.clear(), throwsUnsupportedError);
      expect(() => overview.setsById.remove(setA.id), throwsUnsupportedError);
    });

    test('50k-set overview aggregation stays under the M4 budget', () {
      final exercise = _exercise(
        type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
      );
      final workout = _workout('workout-big', DateTime.utc(2026, 6, 19));
      final sets = List<LoggedSetRecord>.generate(
        50000,
        (index) => _set(
          'set-$index',
          workoutId: workout.id,
          exerciseId: exercise.id,
          position: index,
          values: _loadReps(
            load: (80 + index % 40).toString(),
            reps: (1 + index % 10).toString(),
          ),
        ),
        growable: false,
      );
      final stopwatch = Stopwatch()..start();

      final overview = buildExerciseOverviewModel(
        exercise: exercise,
        workouts: <WorkoutSessionRecord>[workout],
        sets: sets,
      );
      stopwatch.stop();

      expect(overview.groups.single.sets, hasLength(50000));
      expect(stopwatch.elapsedMilliseconds, lessThan(300));
    });
  });
}

ExerciseRecord _exercise({
  required ExerciseType type,
  ExerciseLoadMode loadMode = ExerciseLoadMode.added,
}) {
  return ExerciseRecord(
    id: 'exercise',
    origin: ExerciseLibraryOrigin.user,
    name: 'Bench Press',
    type: type,
    defaultLoadUnit: TrainingUnit.kilogram,
    loadMode: loadMode,
    recordProfile: defaultRecordProfileFor(type: type, loadMode: loadMode),
    categoryId: 'strength',
    notes: null,
    isFavorite: false,
    updatedAt: DateTime.utc(2026, 6, 1),
  );
}

WorkoutSessionRecord _workout(String id, DateTime startedAt) {
  return WorkoutSessionRecord(
    id: id,
    startedAt: startedAt,
    timezone: 'UTC',
    localDate: TrainingDayDate.fromDateTime(startedAt),
    endedAt: null,
    comment: null,
    updatedAt: startedAt,
    deletedAt: null,
  );
}

LoggedSetRecord _set(
  String id, {
  required String workoutId,
  required String exerciseId,
  required int position,
  required LoggedSet values,
  String? comment,
}) {
  return LoggedSetRecord(
    id: id,
    workoutId: workoutId,
    exerciseId: exerciseId,
    position: position,
    values: values,
    plannedRestAfter: null,
    isCompleted: false,
    updatedAt: DateTime.utc(2026, 6, 16).add(Duration(seconds: position)),
    comment: comment,
  );
}

LoggedSet _loadReps({required String load, required String reps}) {
  return LoggedSet.fromValues(<SetDimensionValue>[
    SetDimensionValue(
      dimension: DimensionId.load,
      entered: load,
      unit: TrainingUnit.kilogram,
    ),
    SetDimensionValue(
      dimension: DimensionId.reps,
      entered: reps,
      unit: TrainingUnit.repetition,
    ),
  ]);
}

LoggedSet _distanceDuration({required String km, required String seconds}) {
  return LoggedSet.fromValues(<SetDimensionValue>[
    SetDimensionValue(
      dimension: DimensionId.distance,
      entered: km,
      unit: TrainingUnit.kilometer,
    ),
    SetDimensionValue(
      dimension: DimensionId.duration,
      entered: seconds,
      unit: TrainingUnit.second,
    ),
  ]);
}
