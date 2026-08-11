import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/training/training_day.dart';
import '../../../domain/training/training_dimensions.dart';

final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => RepositoryHomeRepository(ref.watch(trainingRepositoriesProvider)),
);

abstract interface class HomeRepository {
  Stream<HomeSummary> watchTrainingDay(TrainingDayDate localDate);

  Stream<HomeWorkoutSummary?> watchWorkout(String workoutId);

  Future<String> startNewWorkout(TrainingDayDate localDate);

  Future<String> addExerciseToWorkout({
    required String workoutId,
    required String exerciseId,
  });

  Future<void> removeExerciseFromWorkout({
    required String workoutExerciseId,
  });

  Future<void> reorderWorkoutExercises({
    required String workoutId,
    required List<String> orderedWorkoutExerciseIds,
  });

  Future<void> linkWorkoutExercisesAsSuperset({
    required String workoutId,
    required String firstWorkoutExerciseId,
    required String secondWorkoutExerciseId,
  });

  Future<void> unlinkWorkoutExercisesFromSuperset({
    required String workoutId,
    required String firstWorkoutExerciseId,
    required String secondWorkoutExerciseId,
  });

  Future<void> updateWorkoutComment({
    required String workoutId,
    String? comment,
  });

  Future<void> updateWorkoutStartedAt({
    required String workoutId,
    required DateTime startedAt,
    required TrainingDayDate localDate,
  });

  Future<void> updateWorkoutEndedAt({
    required String workoutId,
    required DateTime endedAt,
  });

  Future<void> finishWorkout(String workoutId);

  Future<void> resumeWorkout(String workoutId);

  Future<void> deleteWorkout(String workoutId);

  Future<String> copyWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  });

  Future<void> moveWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  });

  Future<String> shareWorkout(String workoutId);

  Future<void> logDefaultWeightRepsSet();
}

class StubHomeRepository implements HomeRepository {
  StubHomeRepository({
    HomeSummary? summary,
  }) : summary = summary ??
            HomeSummary(
              title: 'Training Day',
              selectedDate: const TrainingDayDate(year: 1970, month: 1, day: 1),
              status: 'No workout started',
            );

  final HomeSummary summary;

  @override
  Stream<HomeSummary> watchTrainingDay(TrainingDayDate localDate) {
    return Stream<HomeSummary>.value(summary);
  }

  @override
  Stream<HomeWorkoutSummary?> watchWorkout(String workoutId) {
    return Stream<HomeWorkoutSummary?>.value(null);
  }

  @override
  Future<String> startNewWorkout(TrainingDayDate localDate) async {
    return 'stub-workout';
  }

  @override
  Future<String> addExerciseToWorkout({
    required String workoutId,
    required String exerciseId,
  }) async {
    return 'stub-workout-exercise';
  }

  @override
  Future<void> removeExerciseFromWorkout({
    required String workoutExerciseId,
  }) async {}

  @override
  Future<void> reorderWorkoutExercises({
    required String workoutId,
    required List<String> orderedWorkoutExerciseIds,
  }) async {}

  @override
  Future<void> linkWorkoutExercisesAsSuperset({
    required String workoutId,
    required String firstWorkoutExerciseId,
    required String secondWorkoutExerciseId,
  }) async {}

  @override
  Future<void> unlinkWorkoutExercisesFromSuperset({
    required String workoutId,
    required String firstWorkoutExerciseId,
    required String secondWorkoutExerciseId,
  }) async {}

  @override
  Future<void> updateWorkoutComment({
    required String workoutId,
    String? comment,
  }) async {}

  @override
  Future<void> updateWorkoutStartedAt({
    required String workoutId,
    required DateTime startedAt,
    required TrainingDayDate localDate,
  }) async {}

  @override
  Future<void> updateWorkoutEndedAt({
    required String workoutId,
    required DateTime endedAt,
  }) async {}

  @override
  Future<void> finishWorkout(String workoutId) async {}

  @override
  Future<void> resumeWorkout(String workoutId) async {}

  @override
  Future<void> deleteWorkout(String workoutId) async {}

  @override
  Future<String> copyWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {
    return 'stub-workout-copy';
  }

  @override
  Future<void> moveWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {}

  @override
  Future<String> shareWorkout(String workoutId) async {
    return 'Workout summary';
  }

  @override
  Future<void> logDefaultWeightRepsSet() async {}
}

class RepositoryHomeRepository implements HomeRepository {
  RepositoryHomeRepository(
    this._repositories, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final TrainingRepositories _repositories;
  final DateTime Function() _now;

  @override
  Stream<HomeSummary> watchTrainingDay(TrainingDayDate localDate) async* {
    await _repositories.ensureStarterExercises();
    yield* _watchSummary(localDate);
  }

  @override
  Stream<HomeWorkoutSummary?> watchWorkout(String workoutId) async* {
    await _repositories.ensureStarterExercises();
    yield* _watchWorkout(workoutId);
  }

  @override
  Future<String> startNewWorkout(TrainingDayDate localDate) {
    final now = _now().toLocal();
    return _repositories.workoutSessions.create(
      WorkoutSessionDraft(
        startedAt: localDate.atLocalTimeOf(now),
        timezone: now.timeZoneName,
        localDate: localDate,
      ),
    );
  }

  @override
  Future<String> addExerciseToWorkout({
    required String workoutId,
    required String exerciseId,
  }) {
    return _repositories.workoutExercises.create(
      WorkoutExerciseDraft(
        workoutId: workoutId,
        exerciseId: exerciseId,
      ),
    );
  }

  @override
  Future<void> removeExerciseFromWorkout({
    required String workoutExerciseId,
  }) {
    return _repositories.workoutExercises.softDelete(workoutExerciseId);
  }

  @override
  Future<void> reorderWorkoutExercises({
    required String workoutId,
    required List<String> orderedWorkoutExerciseIds,
  }) {
    return _repositories.workoutExercises.reorderForWorkout(
      workoutId: workoutId,
      orderedIds: orderedWorkoutExerciseIds,
    );
  }

  @override
  Future<void> linkWorkoutExercisesAsSuperset({
    required String workoutId,
    required String firstWorkoutExerciseId,
    required String secondWorkoutExerciseId,
  }) {
    return _repositories.exerciseGroups.linkAdjacent(
      workoutId: workoutId,
      firstWorkoutExerciseId: firstWorkoutExerciseId,
      secondWorkoutExerciseId: secondWorkoutExerciseId,
    );
  }

  @override
  Future<void> unlinkWorkoutExercisesFromSuperset({
    required String workoutId,
    required String firstWorkoutExerciseId,
    required String secondWorkoutExerciseId,
  }) {
    return _repositories.exerciseGroups.unlinkAdjacent(
      workoutId: workoutId,
      firstWorkoutExerciseId: firstWorkoutExerciseId,
      secondWorkoutExerciseId: secondWorkoutExerciseId,
    );
  }

  @override
  Future<void> updateWorkoutComment({
    required String workoutId,
    String? comment,
  }) {
    return _repositories.workoutSessions.updateComment(
      workoutId,
      comment: comment,
    );
  }

  @override
  Future<void> updateWorkoutStartedAt({
    required String workoutId,
    required DateTime startedAt,
    required TrainingDayDate localDate,
  }) {
    return _repositories.workoutSessions.updateStartedAt(
      workoutId,
      startedAt: startedAt,
      localDate: localDate,
    );
  }

  @override
  Future<void> updateWorkoutEndedAt({
    required String workoutId,
    required DateTime endedAt,
  }) {
    return _repositories.workoutSessions.updateEndedAt(
      workoutId,
      endedAt: endedAt,
    );
  }

  @override
  Future<void> finishWorkout(String workoutId) {
    return _repositories.workoutSessions.updateEndedAt(
      workoutId,
      endedAt: _now().toUtc(),
    );
  }

  @override
  Future<void> resumeWorkout(String workoutId) {
    return _repositories.workoutSessions.updateEndedAt(
      workoutId,
      endedAt: null,
    );
  }

  @override
  Future<void> deleteWorkout(String workoutId) {
    return _repositories.workoutSessions.softDelete(workoutId);
  }

  @override
  Future<String> copyWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) {
    return _repositories.workoutSessions.copyWorkout(
      workoutId,
      localDate: localDate,
      now: _now(),
    );
  }

  @override
  Future<void> moveWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) {
    return _repositories.workoutSessions.moveToTrainingDay(
      workoutId,
      localDate: localDate,
    );
  }

  @override
  Future<String> shareWorkout(String workoutId) {
    return _repositories.workoutSessions.shareSummary(workoutId);
  }

  @override
  Future<void> logDefaultWeightRepsSet() {
    return _repositories.logDefaultWeightRepsSet();
  }

  Stream<HomeSummary> _watchSummary(TrainingDayDate localDate) {
    StreamSubscription<List<ExerciseRecord>>? exerciseSubscription;
    late final StreamSubscription<List<WorkoutSessionRecord>>
        workoutSubscription;
    StreamSubscription<List<WorkoutExerciseRecord>>?
        workoutExerciseSubscription;
    StreamSubscription<List<LoggedSetRecord>>? setSubscription;
    StreamSubscription<List<ExerciseGroupRecord>>? exerciseGroupSubscription;

    final controller = StreamController<HomeSummary>();
    List<ExerciseRecord>? latestExercises;
    List<WorkoutSessionRecord>? latestWorkouts;
    List<WorkoutExerciseRecord>? latestWorkoutExercises;
    List<LoggedSetRecord>? latestSets;
    List<ExerciseGroupRecord>? latestExerciseGroups;
    var subscribedWorkoutIds = const <String>{};
    var childSubscriptionVersion = 0;
    Set<String>? subscribedExerciseIds;
    var exerciseSubscriptionVersion = 0;
    HomeSummary? lastEmitted;

    void addIfChanged(HomeSummary summary) {
      if (lastEmitted == summary) {
        return;
      }
      lastEmitted = summary;
      controller.add(summary);
    }

    void emitIfReady() {
      final exercises = latestExercises;
      final workouts = latestWorkouts;
      final workoutExercises = latestWorkoutExercises;
      final sets = latestSets;
      final exerciseGroups = latestExerciseGroups;
      if (exercises == null ||
          workouts == null ||
          workoutExercises == null ||
          sets == null ||
          exerciseGroups == null) {
        return;
      }

      addIfChanged(_homeSummaryFrom(
        exercises: exercises,
        workouts: workouts,
        workoutExercises: workoutExercises,
        sets: sets,
        exerciseGroups: exerciseGroups,
        selectedDate: localDate,
      ));
    }

    void subscribeToExercises(List<WorkoutExerciseRecord> workoutExercises) {
      final nextExerciseIds = workoutExercises
          .map((workoutExercise) => workoutExercise.exerciseId)
          .toSet();
      final currentExerciseIds = subscribedExerciseIds;
      final isSameSubscription = currentExerciseIds != null &&
          _sameStringSet(nextExerciseIds, currentExerciseIds);
      if (isSameSubscription && exerciseSubscription != null) {
        return;
      }

      subscribedExerciseIds = nextExerciseIds;
      latestExercises = null;
      final version = ++exerciseSubscriptionVersion;

      unawaited(exerciseSubscription?.cancel());
      exerciseSubscription =
          _repositories.exercises.watchActiveByIds(nextExerciseIds).listen(
        (exercises) {
          if (version != exerciseSubscriptionVersion) {
            return;
          }
          latestExercises = exercises;
          emitIfReady();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (version == exerciseSubscriptionVersion) {
            controller.addError(error, stackTrace);
          }
        },
      );
    }

    void subscribeToWorkoutRows(List<WorkoutSessionRecord> workouts) {
      final nextWorkoutIds = workouts.map((workout) => workout.id).toSet();
      if (_sameStringSet(nextWorkoutIds, subscribedWorkoutIds) &&
          workoutExerciseSubscription != null &&
          setSubscription != null &&
          exerciseGroupSubscription != null) {
        return;
      }

      subscribedWorkoutIds = nextWorkoutIds;
      latestWorkoutExercises = null;
      latestSets = null;
      latestExerciseGroups = null;
      final version = ++childSubscriptionVersion;

      unawaited(workoutExerciseSubscription?.cancel());
      unawaited(setSubscription?.cancel());
      unawaited(exerciseGroupSubscription?.cancel());
      workoutExerciseSubscription = _repositories.workoutExercises
          .watchActiveForWorkoutIds(nextWorkoutIds)
          .listen(
        (workoutExercises) {
          if (version != childSubscriptionVersion) {
            return;
          }
          latestWorkoutExercises = workoutExercises;
          subscribeToExercises(workoutExercises);
          emitIfReady();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (version == childSubscriptionVersion) {
            controller.addError(error, stackTrace);
          }
        },
      );
      setSubscription =
          _repositories.sets.watchActiveForWorkoutIds(nextWorkoutIds).listen(
        (sets) {
          if (version != childSubscriptionVersion) {
            return;
          }
          latestSets = sets;
          emitIfReady();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (version == childSubscriptionVersion) {
            controller.addError(error, stackTrace);
          }
        },
      );
      exerciseGroupSubscription = _repositories.exerciseGroups
          .watchActiveForWorkoutIds(nextWorkoutIds)
          .listen(
        (groups) {
          if (version != childSubscriptionVersion) {
            return;
          }
          latestExerciseGroups = groups;
          emitIfReady();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (version == childSubscriptionVersion) {
            controller.addError(error, stackTrace);
          }
        },
      );
    }

    controller.onListen = () {
      workoutSubscription = _repositories.workoutSessions
          .watchActiveForLocalDate(localDate)
          .listen(
        (workouts) {
          latestWorkouts = workouts;
          subscribeToWorkoutRows(workouts);
          emitIfReady();
        },
        onError: controller.addError,
      );
    };
    controller.onCancel = () async {
      childSubscriptionVersion++;
      exerciseSubscriptionVersion++;
      await workoutSubscription.cancel();
      await workoutExerciseSubscription?.cancel();
      await setSubscription?.cancel();
      await exerciseGroupSubscription?.cancel();
      await exerciseSubscription?.cancel();
    };

    return controller.stream;
  }

  Stream<HomeWorkoutSummary?> _watchWorkout(String workoutId) {
    StreamSubscription<List<ExerciseRecord>>? exerciseSubscription;
    late final StreamSubscription<List<WorkoutSessionRecord>>
        workoutSubscription;
    late final StreamSubscription<List<WorkoutExerciseRecord>>
        workoutExerciseSubscription;
    late final StreamSubscription<List<LoggedSetRecord>> setSubscription;
    late final StreamSubscription<List<ExerciseGroupRecord>>
        exerciseGroupSubscription;

    final controller = StreamController<HomeWorkoutSummary?>();
    List<ExerciseRecord>? latestExercises;
    List<WorkoutSessionRecord>? latestWorkouts;
    List<WorkoutExerciseRecord>? latestWorkoutExercises;
    List<LoggedSetRecord>? latestSets;
    List<ExerciseGroupRecord>? latestExerciseGroups;
    HomeWorkoutSummary? lastEmitted;
    var emittedNull = false;
    var subscribedExerciseIds = const <String>{};
    var exerciseSubscriptionVersion = 0;

    void addIfChanged(HomeWorkoutSummary? workout) {
      if (workout == null) {
        if (emittedNull && lastEmitted == null) {
          return;
        }
        emittedNull = true;
        lastEmitted = null;
        controller.add(null);
        return;
      }

      if (lastEmitted == workout) {
        return;
      }
      emittedNull = false;
      lastEmitted = workout;
      controller.add(workout);
    }

    void emitIfReady() {
      final exercises = latestExercises;
      final workouts = latestWorkouts;
      final workoutExercises = latestWorkoutExercises;
      final sets = latestSets;
      final exerciseGroups = latestExerciseGroups;
      if (exercises == null ||
          workouts == null ||
          workoutExercises == null ||
          sets == null ||
          exerciseGroups == null) {
        return;
      }

      final workout = workouts.where((row) => row.id == workoutId).firstOrNull;
      if (workout == null) {
        addIfChanged(null);
        return;
      }

      final summary = _homeSummaryFrom(
        exercises: exercises,
        workouts: <WorkoutSessionRecord>[workout],
        workoutExercises: workoutExercises,
        sets: sets,
        exerciseGroups: exerciseGroups,
        selectedDate: workout.localDate,
      );
      addIfChanged(summary.workouts.single);
    }

    void subscribeToExercises(List<WorkoutExerciseRecord> workoutExercises) {
      final nextExerciseIds = workoutExercises
          .map((workoutExercise) => workoutExercise.exerciseId)
          .toSet();
      if (_sameStringSet(nextExerciseIds, subscribedExerciseIds) &&
          exerciseSubscription != null) {
        return;
      }

      subscribedExerciseIds = nextExerciseIds;
      latestExercises = null;
      final version = ++exerciseSubscriptionVersion;

      unawaited(exerciseSubscription?.cancel());
      exerciseSubscription =
          _repositories.exercises.watchActiveByIds(nextExerciseIds).listen(
        (exercises) {
          if (version != exerciseSubscriptionVersion) {
            return;
          }
          latestExercises = exercises;
          emitIfReady();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (version == exerciseSubscriptionVersion) {
            controller.addError(error, stackTrace);
          }
        },
      );
    }

    controller.onListen = () {
      workoutSubscription = _repositories.workoutSessions
          .watchActiveByIds(<String>{workoutId}).listen(
        (workouts) {
          latestWorkouts = workouts;
          emitIfReady();
        },
        onError: controller.addError,
      );
      workoutExerciseSubscription = _repositories.workoutExercises
          .watchActiveForWorkout(workoutId)
          .listen(
        (workoutExercises) {
          latestWorkoutExercises = workoutExercises;
          subscribeToExercises(workoutExercises);
          emitIfReady();
        },
        onError: controller.addError,
      );
      setSubscription =
          _repositories.sets.watchActiveForWorkout(workoutId).listen(
        (sets) {
          latestSets = sets;
          emitIfReady();
        },
        onError: controller.addError,
      );
      exerciseGroupSubscription =
          _repositories.exerciseGroups.watchActiveForWorkout(workoutId).listen(
        (groups) {
          latestExerciseGroups = groups;
          emitIfReady();
        },
        onError: controller.addError,
      );
    };
    controller.onCancel = () async {
      exerciseSubscriptionVersion++;
      await exerciseSubscription?.cancel();
      await workoutSubscription.cancel();
      await workoutExerciseSubscription.cancel();
      await setSubscription.cancel();
      await exerciseGroupSubscription.cancel();
    };

    return controller.stream;
  }
}

class HomeSummary {
  HomeSummary({
    required this.title,
    required this.selectedDate,
    required this.status,
    Iterable<HomeWorkoutSummary> workouts = const <HomeWorkoutSummary>[],
    Iterable<HomeWorkoutExerciseSummary> workoutExercises =
        const <HomeWorkoutExerciseSummary>[],
    Iterable<HomeExerciseSummary> exercises = const <HomeExerciseSummary>[],
    Iterable<HomeSetSummary> sets = const <HomeSetSummary>[],
  })  : workouts = List<HomeWorkoutSummary>.unmodifiable(workouts),
        workoutExercises = List<HomeWorkoutExerciseSummary>.unmodifiable(
          workoutExercises,
        ),
        exercises = List<HomeExerciseSummary>.unmodifiable(exercises),
        sets = List<HomeSetSummary>.unmodifiable(sets);

  final String title;
  final TrainingDayDate selectedDate;
  final String status;
  final List<HomeWorkoutSummary> workouts;
  final List<HomeWorkoutExerciseSummary> workoutExercises;
  final List<HomeExerciseSummary> exercises;
  final List<HomeSetSummary> sets;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is HomeSummary &&
            runtimeType == other.runtimeType &&
            title == other.title &&
            selectedDate == other.selectedDate &&
            status == other.status &&
            _listEquals(other.workouts, workouts) &&
            _listEquals(other.workoutExercises, workoutExercises) &&
            _listEquals(other.exercises, exercises) &&
            _listEquals(other.sets, sets);
  }

  @override
  int get hashCode => Object.hash(
        title,
        selectedDate,
        status,
        Object.hashAll(workouts),
        Object.hashAll(workoutExercises),
        Object.hashAll(exercises),
        Object.hashAll(sets),
      );
}

class HomeWorkoutSummary {
  HomeWorkoutSummary({
    required this.id,
    required this.startedAt,
    this.localDate,
    this.endedAt,
    this.comment,
    Iterable<HomeWorkoutExerciseSummary> workoutExercises =
        const <HomeWorkoutExerciseSummary>[],
    Iterable<HomeExerciseGroupSummary> exerciseGroups =
        const <HomeExerciseGroupSummary>[],
  })  : workoutExercises = List<HomeWorkoutExerciseSummary>.unmodifiable(
          workoutExercises,
        ),
        exerciseGroups = List<HomeExerciseGroupSummary>.unmodifiable(
          exerciseGroups,
        );

  final String id;
  final DateTime startedAt;
  final TrainingDayDate? localDate;
  final DateTime? endedAt;
  final String? comment;
  final List<HomeWorkoutExerciseSummary> workoutExercises;
  final List<HomeExerciseGroupSummary> exerciseGroups;

  Duration? get duration => endedAt?.difference(startedAt);
  bool get isOpen => endedAt == null;
  int get setCount {
    var count = 0;
    for (final exercise in workoutExercises) {
      count += exercise.sets.length;
    }
    return count;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is HomeWorkoutSummary &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            startedAt == other.startedAt &&
            localDate == other.localDate &&
            endedAt == other.endedAt &&
            comment == other.comment &&
            _listEquals(other.workoutExercises, workoutExercises) &&
            _listEquals(other.exerciseGroups, exerciseGroups);
  }

  @override
  int get hashCode => Object.hash(
        id,
        startedAt,
        localDate,
        endedAt,
        comment,
        Object.hashAll(workoutExercises),
        Object.hashAll(exerciseGroups),
      );
}

class HomeExerciseGroupSummary {
  HomeExerciseGroupSummary({
    required this.id,
    required this.name,
    required this.colorHex,
    required Iterable<String> workoutExerciseIds,
  }) : workoutExerciseIds = List<String>.unmodifiable(workoutExerciseIds);

  final String id;
  final String name;
  final String colorHex;
  final List<String> workoutExerciseIds;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is HomeExerciseGroupSummary &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            name == other.name &&
            colorHex == other.colorHex &&
            _listEquals(other.workoutExerciseIds, workoutExerciseIds);
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        colorHex,
        Object.hashAll(workoutExerciseIds),
      );
}

class HomeWorkoutExerciseSummary {
  HomeWorkoutExerciseSummary({
    required this.id,
    required this.workoutId,
    required this.exerciseId,
    required this.name,
    required this.type,
    Iterable<HomeSetSummary> sets = const <HomeSetSummary>[],
  }) : sets = List<HomeSetSummary>.unmodifiable(sets);

  final String id;
  final String workoutId;
  final String exerciseId;
  final String name;
  final ExerciseType type;
  final List<HomeSetSummary> sets;
  int get setCount => sets.length;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is HomeWorkoutExerciseSummary &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            workoutId == other.workoutId &&
            exerciseId == other.exerciseId &&
            name == other.name &&
            type == other.type &&
            _listEquals(other.sets, sets);
  }

  @override
  int get hashCode => Object.hash(
        id,
        workoutId,
        exerciseId,
        name,
        type,
        Object.hashAll(sets),
      );
}

class HomeExerciseSummary {
  const HomeExerciseSummary({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is HomeExerciseSummary &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            name == other.name;
  }

  @override
  int get hashCode => Object.hash(id, name);
}

class HomeSetSummary {
  const HomeSetSummary({
    required this.id,
    required this.description,
    this.isCompleted = false,
  });

  final String id;
  final String description;
  final bool isCompleted;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is HomeSetSummary &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            description == other.description &&
            isCompleted == other.isCompleted;
  }

  @override
  int get hashCode => Object.hash(id, description, isCompleted);
}

HomeSummary _homeSummaryFrom({
  required List<ExerciseRecord> exercises,
  required List<WorkoutSessionRecord> workouts,
  required List<WorkoutExerciseRecord> workoutExercises,
  required List<LoggedSetRecord> sets,
  required TrainingDayDate selectedDate,
  List<ExerciseGroupRecord> exerciseGroups = const <ExerciseGroupRecord>[],
}) {
  final workoutIds = workouts.map((workout) => workout.id).toSet();
  final exerciseById = <String, ExerciseRecord>{
    for (final exercise in exercises) exercise.id: exercise,
  };
  final trainingDaySets = sets
      .where((set) => workoutIds.contains(set.workoutId))
      .toList(growable: false);
  final trainingDayWorkoutExercises = workoutExercises
      .where(
          (workoutExercise) => workoutIds.contains(workoutExercise.workoutId))
      .toList(growable: false);
  final setsByWorkoutExerciseKey = <String, List<HomeSetSummary>>{};
  for (final set in trainingDaySets) {
    final key = _workoutExerciseKey(set.workoutId, set.exerciseId);
    setsByWorkoutExerciseKey.putIfAbsent(key, () => <HomeSetSummary>[]).add(
          HomeSetSummary(
            id: set.id,
            description: _formatSet(set, exerciseById[set.exerciseId]),
            isCompleted: set.isCompleted,
          ),
        );
  }

  final status = _formatTrainingDayStatus(
    workoutCount: workouts.length,
    setCount: trainingDaySets.length,
  );

  final homeWorkoutExercises = trainingDayWorkoutExercises.map(
    (workoutExercise) {
      final exercise = exerciseById[workoutExercise.exerciseId];
      final key = _workoutExerciseKey(
        workoutExercise.workoutId,
        workoutExercise.exerciseId,
      );
      final sets = setsByWorkoutExerciseKey[key] ?? const <HomeSetSummary>[];
      return HomeWorkoutExerciseSummary(
        id: workoutExercise.id,
        workoutId: workoutExercise.workoutId,
        exerciseId: workoutExercise.exerciseId,
        name: exercise?.name ?? 'Unknown exercise',
        type: exercise?.type ?? ExerciseType.empty,
        sets: List<HomeSetSummary>.unmodifiable(sets),
      );
    },
  ).toList(growable: false);
  final workoutExercisesByWorkoutId =
      <String, List<HomeWorkoutExerciseSummary>>{};
  for (final workoutExercise in homeWorkoutExercises) {
    workoutExercisesByWorkoutId
        .putIfAbsent(
          workoutExercise.workoutId,
          () => <HomeWorkoutExerciseSummary>[],
        )
        .add(workoutExercise);
  }

  return HomeSummary(
    title: 'Training Day',
    selectedDate: selectedDate,
    status: status,
    workouts: workouts
        .map(
          (workout) => HomeWorkoutSummary(
            id: workout.id,
            startedAt: workout.startedAt,
            localDate: workout.localDate,
            endedAt: workout.endedAt,
            comment: workout.comment,
            workoutExercises: List<HomeWorkoutExerciseSummary>.unmodifiable(
              workoutExercisesByWorkoutId[workout.id] ??
                  const <HomeWorkoutExerciseSummary>[],
            ),
            exerciseGroups: exerciseGroups
                .where((group) => group.workoutId == workout.id)
                .map(
                  (group) => HomeExerciseGroupSummary(
                    id: group.id,
                    name: group.name,
                    colorHex: group.colorHex,
                    workoutExerciseIds: group.workoutExerciseIds,
                  ),
                ),
          ),
        )
        .toList(growable: false),
    workoutExercises: homeWorkoutExercises,
    exercises: exercises
        .map(
          (exercise) => HomeExerciseSummary(
            id: exercise.id,
            name: exercise.name,
          ),
        )
        .toList(growable: false),
    sets: trainingDaySets
        .map(
          (set) => HomeSetSummary(
            id: set.id,
            description: _formatSet(set, exerciseById[set.exerciseId]),
            isCompleted: set.isCompleted,
          ),
        )
        .toList(growable: false),
  );
}

String _formatSet(LoggedSetRecord set, ExerciseRecord? exercise) {
  final load = set.values.load;
  final reps = set.values.reps;
  final exerciseName = exercise?.name ?? 'Unknown exercise';
  if (load != null && reps != null) {
    return '$exerciseName - ${load.entered} ${_unitLabel(load.unit)} x '
        '${reps.entered}';
  }

  return exerciseName;
}

String _workoutExerciseKey(String workoutId, String exerciseId) {
  return '$workoutId::$exerciseId';
}

String _formatTrainingDayStatus({
  required int workoutCount,
  required int setCount,
}) {
  if (workoutCount == 0) {
    return 'No workout started';
  }

  final workoutLabel =
      workoutCount == 1 ? '1 workout' : '$workoutCount workouts';
  final setLabel = switch (setCount) {
    0 => 'No sets',
    1 => '1 set',
    _ => '$setCount sets',
  };
  return '$workoutLabel - $setLabel';
}

String _unitLabel(TrainingUnit unit) {
  return switch (unit) {
    TrainingUnit.kilogram => 'kg',
    TrainingUnit.pound => 'lb',
    TrainingUnit.repetition => 'reps',
    TrainingUnit.second => 'sec',
    TrainingUnit.kilometer => 'km',
    TrainingUnit.mile => 'mi',
  };
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) {
    return false;
  }

  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }

  return true;
}

bool _sameStringSet(Set<String> left, Set<String> right) {
  return left.length == right.length && left.containsAll(right);
}
