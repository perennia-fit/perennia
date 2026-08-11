import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/training/training_day.dart';
import '../../../domain/training/training_dimensions.dart';
import '../../settings/repositories/settings_repository.dart';

final exerciseOverviewRepositoryProvider =
    Provider<ExerciseOverviewRepository>((ref) {
  final settings =
      ref.watch(settingsControllerProvider).value ?? AppSettings.defaults;
  return ExerciseOverviewRepository(
    ref.watch(trainingRepositoriesProvider),
    settings: settings,
  );
});

final exerciseOverviewControllerProvider =
    FutureProvider.family<ExerciseOverviewModel?, String>((ref, exerciseId) {
  return ref
      .watch(exerciseOverviewRepositoryProvider)
      .getForExercise(exerciseId);
});

class ExerciseOverviewRepository {
  const ExerciseOverviewRepository(
    this._repositories, {
    this.settings = AppSettings.defaults,
  });

  final TrainingRepositories _repositories;
  final AppSettings settings;

  Future<ExerciseOverviewModel?> getForExercise(String exerciseId) async {
    final exercise = await _repositories.exercises.getById(exerciseId);
    if (exercise == null || exercise.deletedAt != null) {
      return null;
    }

    final category = await _categoryForExercise(exercise);
    final sets = await _repositories.sets.listActiveForExercise(exercise.id);
    final workouts = await _repositories.workoutSessions.listActiveByIds(
      sets.map((set) => set.workoutId).toSet(),
    );
    return buildExerciseOverviewModel(
      exercise: exercise,
      category: category,
      workouts: workouts,
      sets: sets,
      weekStartDay: settings.weekStartDay,
    );
  }

  Future<ExerciseCategoryRecord?> _categoryForExercise(
    ExerciseRecord exercise,
  ) async {
    final categoryId = exercise.categoryId;
    if (categoryId == null) {
      return null;
    }

    final categories = await _repositories.catalog.listCategories();
    for (final category in categories) {
      if (category.id == categoryId) {
        return category;
      }
    }
    return null;
  }
}

ExerciseOverviewModel buildExerciseOverviewModel({
  required ExerciseRecord exercise,
  required List<WorkoutSessionRecord> workouts,
  required List<LoggedSetRecord> sets,
  ExerciseCategoryRecord? category,
  WeekStartDay weekStartDay = WeekStartDay.monday,
}) {
  final activeWorkoutsById = <String, WorkoutSessionRecord>{
    for (final workout in workouts)
      if (workout.deletedAt == null) workout.id: workout,
  };
  final exerciseSets = sets
      .where(
        (set) =>
            set.exerciseId == exercise.id &&
            set.deletedAt == null &&
            activeWorkoutsById.containsKey(set.workoutId),
      )
      .toList(growable: false)
    ..sort((left, right) {
      final leftWorkout = activeWorkoutsById[left.workoutId]!;
      final rightWorkout = activeWorkoutsById[right.workoutId]!;
      final workoutComparison =
          rightWorkout.startedAt.compareTo(leftWorkout.startedAt);
      if (workoutComparison != 0) {
        return workoutComparison;
      }
      final positionComparison = left.position.compareTo(right.position);
      if (positionComparison != 0) {
        return positionComparison;
      }
      return left.id.compareTo(right.id);
    });

  final groups = <ExerciseOverviewWorkoutGroup>[];
  var index = 0;
  while (index < exerciseSets.length) {
    final workoutId = exerciseSets[index].workoutId;
    final groupSets = <LoggedSetRecord>[];
    while (index < exerciseSets.length &&
        exerciseSets[index].workoutId == workoutId) {
      groupSets.add(exerciseSets[index]);
      index += 1;
    }

    groups.add(
      ExerciseOverviewWorkoutGroup(
        workout: activeWorkoutsById[workoutId]!,
        sets: groupSets,
        volume: _strengthVolume(exercise, groupSets),
        totalReps: _totalReps(exercise, groupSets),
        distance: _totalDistance(exercise, groupSets),
        duration: _totalDuration(exercise, groupSets),
      ),
    );
  }

  return ExerciseOverviewModel(
    exercise: exercise,
    category: category,
    groups: groups,
    weeklyGroups: _buildWeeklyGroups(groups, weekStartDay),
    setsById: <String, LoggedSetRecord>{
      for (final set in exerciseSets) set.id: set,
    },
  );
}

class ExerciseOverviewModel {
  ExerciseOverviewModel({
    required this.exercise,
    required this.category,
    required Iterable<ExerciseOverviewWorkoutGroup> groups,
    required Iterable<ExerciseOverviewWeekGroup> weeklyGroups,
    required Map<String, LoggedSetRecord> setsById,
  })  : groups = List<ExerciseOverviewWorkoutGroup>.unmodifiable(groups),
        weeklyGroups = List<ExerciseOverviewWeekGroup>.unmodifiable(
          weeklyGroups,
        ),
        setsById = Map<String, LoggedSetRecord>.unmodifiable(setsById);

  final ExerciseRecord exercise;
  final ExerciseCategoryRecord? category;
  final List<ExerciseOverviewWorkoutGroup> groups;
  final List<ExerciseOverviewWeekGroup> weeklyGroups;
  final Map<String, LoggedSetRecord> setsById;
}

class ExerciseOverviewWorkoutGroup {
  ExerciseOverviewWorkoutGroup({
    required this.workout,
    required Iterable<LoggedSetRecord> sets,
    required this.volume,
    required this.totalReps,
    required this.distance,
    required this.duration,
  }) : sets = List<LoggedSetRecord>.unmodifiable(sets);

  final WorkoutSessionRecord workout;
  final List<LoggedSetRecord> sets;
  final double? volume;
  final double? totalReps;
  final double? distance;
  final Duration? duration;
}

class ExerciseOverviewWeekGroup {
  ExerciseOverviewWeekGroup({
    required this.weekStart,
    required Iterable<WorkoutSessionRecord> workouts,
    required this.setCount,
    required this.volume,
    required this.totalReps,
    required this.distance,
    required this.duration,
  }) : workouts = List<WorkoutSessionRecord>.unmodifiable(workouts);

  final TrainingDayDate weekStart;
  final List<WorkoutSessionRecord> workouts;
  final int setCount;
  final double? volume;
  final double? totalReps;
  final double? distance;
  final Duration? duration;
}

List<ExerciseOverviewWeekGroup> _buildWeeklyGroups(
  List<ExerciseOverviewWorkoutGroup> groups,
  WeekStartDay weekStartDay,
) {
  final settings = AppSettings(weekStartDay: weekStartDay);
  final groupsByWeekStart =
      <TrainingDayDate, List<ExerciseOverviewWorkoutGroup>>{};
  for (final group in groups) {
    final weekStart = settings.weekStartFor(group.workout.localDate);
    groupsByWeekStart.putIfAbsent(weekStart, () => []).add(group);
  }

  final weeklyGroups = <ExerciseOverviewWeekGroup>[];
  for (final entry in groupsByWeekStart.entries) {
    final workoutGroups = entry.value;
    weeklyGroups.add(
      ExerciseOverviewWeekGroup(
        weekStart: entry.key,
        workouts: workoutGroups.map((group) => group.workout),
        setCount: workoutGroups.fold<int>(
          0,
          (total, group) => total + group.sets.length,
        ),
        volume: _sumDoubles(workoutGroups.map((group) => group.volume)),
        totalReps: _sumDoubles(workoutGroups.map((group) => group.totalReps)),
        distance: _sumDoubles(workoutGroups.map((group) => group.distance)),
        duration: _sumDurations(workoutGroups.map((group) => group.duration)),
      ),
    );
  }

  weeklyGroups.sort((left, right) => right.weekStart.compareTo(left.weekStart));
  return weeklyGroups;
}

double? _sumDoubles(Iterable<double?> values) {
  var hasValue = false;
  var total = 0.0;
  for (final value in values) {
    if (value == null) {
      continue;
    }
    hasValue = true;
    total += value;
  }
  return hasValue ? total : null;
}

Duration? _sumDurations(Iterable<Duration?> values) {
  var hasValue = false;
  var total = Duration.zero;
  for (final value in values) {
    if (value == null) {
      continue;
    }
    hasValue = true;
    total += value;
  }
  return hasValue ? total : null;
}

double? _strengthVolume(
  ExerciseRecord exercise,
  List<LoggedSetRecord> sets,
) {
  if (exercise.loadMode == ExerciseLoadMode.assisted ||
      !exercise.type.hasDimension(DimensionId.load) ||
      !exercise.type.hasDimension(DimensionId.reps)) {
    return null;
  }

  var total = 0.0;
  for (final set in sets) {
    final load = set.values.load?.convertedTo(TrainingUnit.kilogram);
    final reps = set.values.reps?.convertedTo(TrainingUnit.repetition);
    if (load != null && reps != null) {
      total += load * reps;
    }
  }
  return total;
}

double? _totalReps(
  ExerciseRecord exercise,
  List<LoggedSetRecord> sets,
) {
  if (!exercise.type.hasDimension(DimensionId.reps)) {
    return null;
  }

  var total = 0.0;
  for (final set in sets) {
    final reps = set.values.reps?.convertedTo(TrainingUnit.repetition);
    if (reps != null) {
      total += reps;
    }
  }
  return total;
}

double? _totalDistance(
  ExerciseRecord exercise,
  List<LoggedSetRecord> sets,
) {
  if (!exercise.type.hasDimension(DimensionId.distance)) {
    return null;
  }

  var total = 0.0;
  for (final set in sets) {
    final distance = set.values.distance?.convertedTo(TrainingUnit.kilometer);
    if (distance != null) {
      total += distance;
    }
  }
  return total;
}

Duration? _totalDuration(
  ExerciseRecord exercise,
  List<LoggedSetRecord> sets,
) {
  if (!exercise.type.hasDimension(DimensionId.duration)) {
    return null;
  }

  var totalSeconds = 0.0;
  for (final set in sets) {
    final duration = set.values.duration?.convertedTo(TrainingUnit.second);
    if (duration != null) {
      totalSeconds += duration;
    }
  }
  return Duration(seconds: totalSeconds.round());
}
