import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';

final templateDivergenceFeatureRepositoryProvider =
    Provider<TemplateDivergenceFeatureRepository>(
  (ref) => RepositoryTemplateDivergenceFeatureRepository(
    ref.watch(trainingRepositoriesProvider),
  ),
);

/// UI-shaped access to the plan-learns-from-fact loop (ROUTINES.md §2,
/// §3.4): the Finish prompt reads [summaryForWorkout] to decide whether to
/// ask, and the overflow's "Update template" verb calls
/// [updateTemplateFromWorkout] directly, any time, on any linked Workout.
abstract interface class TemplateDivergenceFeatureRepository {
  Future<TemplateDivergenceSummary?> summaryForWorkout(String workoutId);

  Future<TemplateUpdateFromWorkoutResult?> updateTemplateFromWorkout(
    String workoutId,
  );
}

class RepositoryTemplateDivergenceFeatureRepository
    implements TemplateDivergenceFeatureRepository {
  const RepositoryTemplateDivergenceFeatureRepository(this._repositories);

  final TrainingRepositories _repositories;

  @override
  Future<TemplateDivergenceSummary?> summaryForWorkout(String workoutId) {
    return _repositories.templateDivergence.summaryForWorkout(workoutId);
  }

  @override
  Future<TemplateUpdateFromWorkoutResult?> updateTemplateFromWorkout(
    String workoutId,
  ) {
    return _repositories.templateDivergence.updateTemplateFromWorkout(
      workoutId,
    );
  }
}
