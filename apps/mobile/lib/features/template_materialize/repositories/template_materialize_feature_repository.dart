import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';

final templateMaterializeFeatureRepositoryProvider =
    Provider<TemplateMaterializeFeatureRepository>(
  (ref) => RepositoryTemplateMaterializeFeatureRepository(
    ref.watch(trainingRepositoriesProvider),
  ),
);

/// Presentation-facing boundary for the app-side materialize verb
/// (ROUTINES.md §1.4, §3.2). Starting a Template always begins a new
/// Workout; pass [routineId] and [slot] only when the start was reached
/// through a Routine's Cadence slot.
abstract interface class TemplateMaterializeFeatureRepository {
  Future<String> materializeTemplate({
    required String workoutTemplateId,
    String? routineId,
    int? slot,
  });
}

class RepositoryTemplateMaterializeFeatureRepository
    implements TemplateMaterializeFeatureRepository {
  const RepositoryTemplateMaterializeFeatureRepository(this._repositories);

  final TrainingRepositories _repositories;

  @override
  Future<String> materializeTemplate({
    required String workoutTemplateId,
    String? routineId,
    int? slot,
  }) async {
    final result = await _repositories.templateMaterialize.materialize(
      TemplateMaterializeRequest(
        workoutTemplateId: workoutTemplateId,
        routineId: routineId,
        slot: slot,
      ),
    );
    return result.workoutId;
  }
}
