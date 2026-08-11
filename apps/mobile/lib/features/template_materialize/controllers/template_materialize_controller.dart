import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/template_materialize_feature_repository.dart';

final templateMaterializeControllerProvider =
    Provider<TemplateMaterializeController>((ref) {
  return TemplateMaterializeController(
    ref.watch(templateMaterializeFeatureRepositoryProvider),
  );
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
}
