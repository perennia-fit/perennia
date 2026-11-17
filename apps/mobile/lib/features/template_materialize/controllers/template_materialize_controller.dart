import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/template_materialize_feature_repository.dart';

final templateMaterializeControllerProvider =
    Provider<TemplateMaterializeController>((ref) {
  return TemplateMaterializeController(
    ref.watch(templateMaterializeFeatureRepositoryProvider),
  );
});

/// Active Workout Templates that would start an empty Workout. Start
/// surfaces read `.value` and treat "not loaded" as "none empty", so a
/// missing value never blocks or mislabels a start.
final emptyWorkoutTemplateIdsProvider = StreamProvider<Set<String>>((ref) {
  return ref
      .watch(templateMaterializeFeatureRepositoryProvider)
      .watchEmptyTemplateIds();
});

/// The linked Template's plan notes for one Workout, or null.
final workoutTemplateGuidanceProvider = StreamProvider.autoDispose
    .family<WorkoutTemplateGuidance?, String>((ref, workoutId) {
      return ref
          .watch(templateMaterializeFeatureRepositoryProvider)
          .watchTemplateGuidance(workoutId);
    });

/// Thin command boundary over [TemplateMaterializeFeatureRepository]. Kept
/// as a controller (rather than calling the feature repository directly
/// from widgets) so screens depend on one stable, presentation-facing verb.
class TemplateMaterializeController {
  const TemplateMaterializeController(this._repository);

  final TemplateMaterializeFeatureRepository _repository;

  /// Starts [workoutTemplateId] as a new Workout, returning its id.
  ///
  /// Pass [routineId] (and [slot] when the Routine has a Cadence) only when
  /// starting through a Routine slot; a bare Template start leaves both
  /// null.
  Future<String> start({
    required String workoutTemplateId,
    String? routineId,
    int? slot,
  }) {
    return _repository.materializeTemplate(
      workoutTemplateId: workoutTemplateId,
      routineId: routineId,
      slot: slot,
    );
  }

  /// The Template's name when starting [workoutTemplateId] would give an
  /// empty Workout; null when it would not.
  Future<String?> emptyTemplateName(String workoutTemplateId) {
    return _repository.emptyTemplateName(workoutTemplateId);
  }
}
