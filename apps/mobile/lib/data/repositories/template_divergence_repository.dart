part of 'training_repositories.dart';

/// One human-readable divergence result for the Finish prompt and the
/// overflow's "Update template" verb (ROUTINES.md §3.4): "+ Dips,
/// − Incline Press".
final class TemplateDivergenceSummary {
  const TemplateDivergenceSummary({
    required this.workoutId,
    required this.workoutTemplateId,
    required this.templateName,
    required this.divergence,
  });

  final String workoutId;
  final String workoutTemplateId;
  final String templateName;
  final TemplateDivergenceResult divergence;

  bool get hasDivergence => divergence.hasDivergence;
}

/// Identities touched by one atomic Update-template-from-workout batch.
final class TemplateUpdateFromWorkoutResult {
  const TemplateUpdateFromWorkoutResult({
    required this.workoutTemplateId,
    required this.activityBatchId,
  });

  final String workoutTemplateId;
  final String activityBatchId;
}

/// Divergence (read) and Update (write) for the plan-learns-from-fact loop
/// closed at Finish (ROUTINES.md §2, §3.4;).
///
/// Both operations require an existing [TemplateLinkRecord] for the Workout
/// — there is deliberately no implicit or automatic path; the app and the
/// (future) agent surface alike must ask for this explicitly. Neither
/// method throws when the Workout simply isn't linked or the linked
/// Template has since been archived: they resolve to `null` so callers
/// (the Finish flow, the overflow menu) can treat "not applicable" as a
/// normal, silent outcome rather than an error.
final class TemplateDivergenceRepository {
  TemplateDivergenceRepository._(this._repositories)
      : _snapshotLoader = _WorkoutCaptureSnapshotLoader(
          _repositories.database,
        );

  final TrainingRepositories _repositories;
  final _WorkoutCaptureSnapshotLoader _snapshotLoader;

  AppDatabase get _database => _repositories.database;

  /// Compares the Workout's performed facts against its linked Template's
  /// currently-stored content. `null` when the Workout has no active
  /// Template Link, or the linked Template no longer exists.
  Future<TemplateDivergenceSummary?> summaryForWorkout(
    String workoutId,
  ) async {
    final resolved = await _resolveLinkedTemplate(workoutId);
    if (resolved == null) {
      return null;
    }
    final loaded = await _snapshotLoader.load(workoutId);
    final comparison = compareTemplateToWorkout(
      template: _templateContentSnapshotFromRecord(resolved.template),
      workout: loaded.snapshot,
    );
    return TemplateDivergenceSummary(
      workoutId: workoutId,
      workoutTemplateId: resolved.template.id,
      templateName: resolved.template.name,
      divergence: comparison.divergence,
    );
  }

  /// Capture-replaces the linked Template's content with what this Workout
  /// actually performed, preserving identity and `copyPrevious` modes
  /// (ROUTINES.md §2 "Update"). All-or-nothing, one Activity Log batch.
  /// `null` when the Workout has no active Template Link, or the linked
  /// Template no longer exists.
  Future<TemplateUpdateFromWorkoutResult?> updateTemplateFromWorkout(
    String workoutId, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final resolved = await _resolveLinkedTemplate(workoutId);
      if (resolved == null) {
        return null;
      }
      final loaded = await _snapshotLoader.load(workoutId);
      final comparison = compareTemplateToWorkout(
        template: _templateContentSnapshotFromRecord(resolved.template),
        workout: loaded.snapshot,
      );
      await _repositories.workoutTemplates._replaceContent(
        resolved.template.id,
        _workoutTemplateContentDraftFromUpdate(comparison.updatedContent),
        context,
        exercisePolicy: _WorkoutTemplateContentExercisePolicy.historicalFact,
      );
      return TemplateUpdateFromWorkoutResult(
        workoutTemplateId: resolved.template.id,
        activityBatchId: context.batchId,
      );
    });
  }

  Future<_ResolvedTemplateLink?> _resolveLinkedTemplate(
    String workoutId,
  ) async {
    final link = await _repositories.templateMaterialize.getByWorkoutId(
      workoutId,
    );
    if (link == null) {
      return null;
    }
    final template = await _repositories.workoutTemplates.getById(
      link.workoutTemplateId,
      includeArchived: false,
    );
    if (template == null) {
      return null;
    }
    return _ResolvedTemplateLink(link: link, template: template);
  }
}

final class _ResolvedTemplateLink {
  const _ResolvedTemplateLink({required this.link, required this.template});

  final TemplateLinkRecord link;
  final WorkoutTemplateRecord template;
}

TemplateContentSnapshot _templateContentSnapshotFromRecord(
  WorkoutTemplateRecord record,
) {
  final exerciseIdByTemplateExerciseId = <String, String>{
    for (final exercise in record.exercises) exercise.id: exercise.exerciseId,
  };
  return TemplateContentSnapshot(
    exercises: record.exercises.map((exercise) {
      return TemplateDivergenceExerciseSnapshot(
        exerciseId: exercise.exerciseId,
        exerciseName: exercise.exercise.name,
        prescriptions: exercise.prescriptions.map((prescription) {
          return TemplateDivergencePrescriptionSnapshot(
            mode: prescription.mode == PrescriptionMode.fixed
                ? TemplateDivergencePrescriptionMode.fixed
                : TemplateDivergencePrescriptionMode.copyPrevious,
            values: prescription.values,
            repeat: prescription.repeat,
            restAfter: prescription.restAfter,
          );
        }),
      );
    }),
    groups: record.groups.map((group) {
      return TemplateDivergenceGroupSnapshot(
        memberExerciseIds: group.members.map(
          (member) => exerciseIdByTemplateExerciseId[member.templateExerciseId]!,
        ),
      );
    }),
  );
}

WorkoutTemplateContentDraft _workoutTemplateContentDraftFromUpdate(
  TemplateUpdateContent content,
) {
  return WorkoutTemplateContentDraft(
    exercises: content.exercises.map((exercise) {
      return WorkoutTemplateExerciseContentDraft(
        exerciseId: exercise.exerciseId,
        prescriptions: exercise.prescriptions.map((prescription) {
          return PrescriptionDraft(
            mode: prescription.mode == TemplateDivergencePrescriptionMode.fixed
                ? PrescriptionMode.fixed
                : PrescriptionMode.copyPrevious,
            values: prescription.values,
            repeat: prescription.repeat,
            restAfter: prescription.restAfter,
          );
        }),
      );
    }),
    groups: content.groups.map((group) {
      return WorkoutTemplateGroupContentDraft(
        name: group.name,
        colorHex: group.colorHex,
        rounds: TemplateUpdateGroupContent.rounds,
        memberExerciseIndexes: group.memberExerciseIndexes,
      );
    }),
  );
}
