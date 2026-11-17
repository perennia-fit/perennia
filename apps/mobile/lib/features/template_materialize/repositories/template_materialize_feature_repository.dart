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

  /// Ids of every active Workout Template with no active Template
  /// Exercises. Materializing one starts an empty Workout, so every start
  /// surface labels it rather than letting the plan silently vanish.
  Stream<Set<String>> watchEmptyTemplateIds();

  /// The name of [workoutTemplateId] when it has no active Template
  /// Exercises right now, or null when it has some (or is not active).
  /// Read fresh at start time, never from a possibly stale stream value.
  Future<String?> emptyTemplateName(String workoutTemplateId);

  /// The notes of the Template [workoutId] was materialized from, or null
  /// when the Workout has no Template Link or that Template has no notes.
  ///
  /// Materialize never copies notes onto the Workout (ROUTINES.md §1.5);
  /// they stay plan guidance, read live from the Template, so editing the
  /// Template's notes shows up here and nothing is duplicated into history.
  Stream<WorkoutTemplateGuidance?> watchTemplateGuidance(String workoutId);
}

/// A linked Template's plan notes, shown read-only on the Workout.
final class WorkoutTemplateGuidance {
  const WorkoutTemplateGuidance({
    required this.templateName,
    required this.notes,
  });

  final String templateName;
  final String notes;

  @override
  bool operator ==(Object other) =>
      other is WorkoutTemplateGuidance &&
      other.templateName == templateName &&
      other.notes == notes;

  @override
  int get hashCode => Object.hash(templateName, notes);
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

  @override
  Stream<Set<String>> watchEmptyTemplateIds() {
    return _repositories.workoutTemplates.watchActiveSummaries().map(
      (summaries) => {
        for (final summary in summaries)
          if (summary.exerciseCount == 0) summary.id,
      },
    );
  }

  @override
  Future<String?> emptyTemplateName(String workoutTemplateId) async {
    final template = await _repositories.workoutTemplates.getById(
      workoutTemplateId,
      includeArchived: false,
    );
    return template != null && template.exercises.isEmpty
        ? template.name
        : null;
  }

  @override
  Stream<WorkoutTemplateGuidance?> watchTemplateGuidance(
    String workoutId,
  ) async* {
    final link = await _repositories.templateMaterialize.getByWorkoutId(
      workoutId,
    );
    if (link == null) {
      yield null;
      return;
    }
    yield* _repositories.workoutTemplates.watchById(link.workoutTemplateId).map(
      (template) {
        final notes = template?.notes?.trim();
        if (template == null || notes == null || notes.isEmpty) {
          return null;
        }
        return WorkoutTemplateGuidance(
          templateName: template.name,
          notes: notes,
        );
      },
    ).distinct();
  }
}
