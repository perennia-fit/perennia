import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';

final templateDivergenceFeatureRepositoryProvider =
    Provider<TemplateDivergenceFeatureRepository>(
  (ref) => RepositoryTemplateDivergenceFeatureRepository(
    ref.watch(trainingRepositoriesProvider),
  ),
);

/// UI-shaped access to the plan-learns-from-fact loop (ROUTINES.md §2,
/// §3.4): the Finish flow reads [summaryForWorkout] to decide whether the
/// Finish summary shows its Update row, and that row calls
/// [updateTemplateFromWorkout] directly on tap. The Workout menu's "Update
/// template" calls it after its dialog, any time, on any linked Workout.
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
