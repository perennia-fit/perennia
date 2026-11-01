import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/training/training_day.dart';
import '../../../domain/training/training_progress.dart';
import '../../focus/repositories/focus_feature_repository.dart';

final progressFeatureRepositoryProvider = Provider<ProgressFeatureRepository>(
  (ref) => RepositoryProgressFeatureRepository(
    ref.watch(trainingRepositoriesProvider),
    ref.watch(focusFeatureRepositoryProvider),
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
  });

  final List<WeeklyPlanFacts> weeklyPlans;
  final bool hasRotatingRoutine;
  final List<ProgressWorkout> workouts;
  final Map<String, FocusRecord> focusesById;
  final List<CompoundConsistencySummary> consistencySummaries;

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
}

class RepositoryProgressFeatureRepository implements ProgressFeatureRepository {
  const RepositoryProgressFeatureRepository(
    this._repositories,
    this._focuses,
  );

  final TrainingRepositories _repositories;
  final FocusFeatureRepository _focuses;

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

  static ProtocolDayDate _protocolDay(TrainingDayDate date) {
    return ProtocolDayDate(year: date.year, month: date.month, day: date.day);
  }
}
