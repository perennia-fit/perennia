import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/analytics/progress_measure.dart';
import '../../../domain/training/training_day.dart';
import '../../../domain/training/training_progress.dart';
import '../../analytics/repositories/exercise_analytics_repository.dart';
import '../../focus/repositories/focus_feature_repository.dart';

final progressFeatureRepositoryProvider = Provider<ProgressFeatureRepository>(
  (ref) => RepositoryProgressFeatureRepository(
    ref.watch(trainingRepositoriesProvider),
    ref.watch(focusFeatureRepositoryProvider),
    ref.watch(exerciseAnalyticsRepositoryProvider),
  ),
);

/// Presentation-facing boundary for Progress Overview
/// (docs/designs/progress-overview.md, D8): every card reads its inputs
/// through here, so card and app-shell tests can run on fixed data without a
/// database. Read-only; Progress writes nothing.
abstract interface class ProgressFeatureRepository {
  /// Active weekly Routines with their planning entries.
  Stream<List<WeeklyPlanFacts>> watchWeeklyPlans();

  /// Whether any active Routine has a rotating Cadence.
  Stream<bool> watchHasRotatingRoutine();

  /// Every live Workout dated in [from]..[to], Open Workouts included.
  Stream<List<ProgressWorkout>> watchProgressWorkoutsBetween(
    TrainingDayDate from,
    TrainingDayDate to,
  );

  /// Every Focus by id, archived ones included.
  Stream<Map<String, FocusRecord>> watchFocusesById();

  /// Each Compound's counted Day Statuses in [from]..[to].
  Stream<List<CompoundConsistencySummary>> watchConsistencySummary(
    TrainingDayDate from,
    TrainingDayDate to, {
    required TrainingDayDate today,
  });

  /// Active Favorite exercises, ordered by name (case-insensitive), then id
  /// (D8): a Favorite is a flag, with no order of its own.
  Stream<List<ExerciseRecord>> watchFavorites();

  /// Active exercises' names by id.
  Stream<Map<String, String>> watchExerciseNames();

  /// Each of [exerciseIds]' Progress Measure over its whole history, in the
  /// order given; an archived exercise, or one with no series, is left out.
  Stream<List<ProgressSeries>> watchProgressSeries(
    Iterable<String> exerciseIds,
  );

  /// Every active exercise's New Bests dated in [from]..[to], newest first.
  Stream<List<NewBest>> watchNewBests(TrainingDayDate from, TrainingDayDate to);
}

/// Fixed-data [ProgressFeatureRepository] for app roots composed without a
/// real database (widget tests, the app-shell harness). Every stream emits
/// its data once, so tests settle.
class StubProgressFeatureRepository implements ProgressFeatureRepository {
  const StubProgressFeatureRepository({
    this.weeklyPlans = const <WeeklyPlanFacts>[],
    this.hasRotatingRoutine = false,
    this.workouts = const <ProgressWorkout>[],
    this.focusesById = const <String, FocusRecord>{},
    this.consistencySummaries = const <CompoundConsistencySummary>[],
    this.favorites = const <ExerciseRecord>[],
    this.exerciseNames = const <String, String>{},
    this.progressSeries = const <ProgressSeries>[],
    this.newBests = const <NewBest>[],
  });

  final List<WeeklyPlanFacts> weeklyPlans;
  final bool hasRotatingRoutine;
  final List<ProgressWorkout> workouts;
  final Map<String, FocusRecord> focusesById;
  final List<CompoundConsistencySummary> consistencySummaries;
  final List<ExerciseRecord> favorites;
  final Map<String, String> exerciseNames;

  /// Every series the stub knows; [watchProgressSeries] returns those asked
  /// for, in the order asked.
  final List<ProgressSeries> progressSeries;
  final List<NewBest> newBests;

  @override
  Stream<List<WeeklyPlanFacts>> watchWeeklyPlans() {
    return Stream<List<WeeklyPlanFacts>>.value(weeklyPlans);
  }

  @override
  Stream<bool> watchHasRotatingRoutine() {
    return Stream<bool>.value(hasRotatingRoutine);
  }

  @override
  Stream<List<ProgressWorkout>> watchProgressWorkoutsBetween(
    TrainingDayDate from,
    TrainingDayDate to,
  ) {
    return Stream<List<ProgressWorkout>>.value(workouts);
  }

  @override
  Stream<Map<String, FocusRecord>> watchFocusesById() {
    return Stream<Map<String, FocusRecord>>.value(focusesById);
  }

  @override
  Stream<List<CompoundConsistencySummary>> watchConsistencySummary(
    TrainingDayDate from,
    TrainingDayDate to, {
    required TrainingDayDate today,
  }) {
    return Stream<List<CompoundConsistencySummary>>.value(
      consistencySummaries,
    );
  }

  @override
  Stream<List<ExerciseRecord>> watchFavorites() {
    return Stream<List<ExerciseRecord>>.value(favorites);
  }

  @override
  Stream<Map<String, String>> watchExerciseNames() {
    return Stream<Map<String, String>>.value(exerciseNames);
  }

  @override
  Stream<List<ProgressSeries>> watchProgressSeries(
    Iterable<String> exerciseIds,
  ) {
    final byId = <String, ProgressSeries>{
      for (final series in progressSeries) series.exerciseId: series,
    };
    return Stream<List<ProgressSeries>>.value(<ProgressSeries>[
      for (final id in exerciseIds)
        if (byId[id] case final series?) series,
    ]);
  }

  @override
  Stream<List<NewBest>> watchNewBests(
    TrainingDayDate from,
    TrainingDayDate to,
  ) {
    return Stream<List<NewBest>>.value(newBests);
  }
}

class RepositoryProgressFeatureRepository implements ProgressFeatureRepository {
  const RepositoryProgressFeatureRepository(
    this._repositories,
    this._focuses,
    this._analytics,
  );

  final TrainingRepositories _repositories;
  final FocusFeatureRepository _focuses;
  final ExerciseAnalyticsRepository _analytics;

  @override
  Stream<List<WeeklyPlanFacts>> watchWeeklyPlans() {
    return _repositories.routineUpNext.watchWeeklyPlans();
  }

  @override
  Stream<bool> watchHasRotatingRoutine() {
    return _repositories.routineUpNext.watchHasRotatingRoutine();
  }

  @override
  Stream<List<ProgressWorkout>> watchProgressWorkoutsBetween(
    TrainingDayDate from,
    TrainingDayDate to,
  ) {
    return _repositories.workoutSessions.watchProgressWorkoutsBetween(
      from,
      to,
    );
  }

  /// Waits for the starter Focus seed, as [FocusFeatureRepository.watchAllById]
  /// does, so a first read never labels a starter Focus as unknown.
  @override
  Stream<Map<String, FocusRecord>> watchFocusesById() {
    return _focuses.watchAllById();
  }

  @override
  Stream<List<CompoundConsistencySummary>> watchConsistencySummary(
    TrainingDayDate from,
    TrainingDayDate to, {
    required TrainingDayDate today,
  }) {
    return _repositories.protocolPlan.watchConsistencySummary(
      _protocolDay(from),
      _protocolDay(to),
      today: _protocolDay(today),
    );
  }

  @override
  Stream<List<ExerciseRecord>> watchFavorites() {
    return _repositories.exercises.watchActive().map(
          (exercises) => exercises
              .where((exercise) => exercise.isFavorite)
              .toList(growable: false)
            ..sort((a, b) {
              final byName = a.name.toLowerCase().compareTo(
                    b.name.toLowerCase(),
                  );
              return byName != 0 ? byName : a.id.compareTo(b.id);
            }),
        );
  }

  @override
  Stream<Map<String, String>> watchExerciseNames() {
    return _repositories.exercises.watchActive().map(
          (exercises) => <String, String>{
            for (final exercise in exercises) exercise.id: exercise.name,
          },
        );
  }

  @override
  Stream<List<ProgressSeries>> watchProgressSeries(
    Iterable<String> exerciseIds,
  ) {
    return _analytics.watchProgressSeries(exerciseIds);
  }

  @override
  Stream<List<NewBest>> watchNewBests(
    TrainingDayDate from,
    TrainingDayDate to,
  ) {
    return _analytics.watchNewBests(from, to);
  }

  static ProtocolDayDate _protocolDay(TrainingDayDate date) {
    return ProtocolDayDate(year: date.year, month: date.month, day: date.day);
  }
}
