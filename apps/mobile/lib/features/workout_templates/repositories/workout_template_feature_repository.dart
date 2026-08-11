import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/training/training_dimensions.dart';

final workoutTemplateFeatureRepositoryProvider =
    Provider<WorkoutTemplateFeatureRepository>(
  (ref) => RepositoryWorkoutTemplateFeatureRepository(
    ref.watch(trainingRepositoriesProvider),
  ),
);

/// Presentation-facing boundary for the Workout Template plan tree.
///
/// Widgets never depend on Drift records. Keeping the mapping here makes
/// external/sync writes arrive through the same reactive repository streams.
abstract interface class WorkoutTemplateFeatureRepository {
  Stream<WorkoutTemplateListSnapshot> watchTemplates();

  Stream<WorkoutTemplateDetail?> watchTemplate(String templateId);

  Future<String> createTemplate({
    required String name,
    String? notes,
  });

  Future<void> updateTemplate({
    required String templateId,
    required String name,
    String? notes,
  });

  Future<void> archiveTemplate(String templateId);

  Future<void> restoreTemplate(String templateId);

  Future<String> addExercise({
    required String templateId,
    required String exerciseId,
    String? notes,
  });

  Future<void> updateExerciseNotes({
    required String templateExerciseId,
    String? notes,
  });

  Future<void> removeExercise(String templateExerciseId);

  Future<void> reorderExercises({
    required String templateId,
    required List<String> orderedIds,
  });

  Future<String> addPrescription({
    required String templateExerciseId,
    required PrescriptionInput input,
  });

  Future<void> updatePrescription({
    required String prescriptionId,
    required PrescriptionInput input,
  });

  Future<void> removePrescription(String prescriptionId);

  Future<void> reorderPrescriptions({
    required String templateExerciseId,
    required List<String> orderedIds,
  });

  Future<String> createTemplateGroup({
    required String templateId,
    required TemplateGroupInput input,
  });

  Future<void> updateTemplateGroup({
    required String groupId,
    required TemplateGroupInput input,
  });

  Future<void> reorderTemplateGroups({
    required String templateId,
    required List<String> orderedIds,
  });

  Future<void> dissolveTemplateGroup(String groupId);
}

/// Adapter over the data-layer repository. The concrete mapping is kept in this
/// file so controllers and widgets only use feature models.
class RepositoryWorkoutTemplateFeatureRepository
    implements WorkoutTemplateFeatureRepository {
  const RepositoryWorkoutTemplateFeatureRepository(this._repositories);

  final TrainingRepositories _repositories;

  @override
  Stream<WorkoutTemplateListSnapshot> watchTemplates() {
    return _repositories.workoutTemplates.watchAllSummaries().map(
      (records) {
        final activeRecords = records
            .where((record) => !record.isArchived)
            .toList(growable: false);
        final archivedRecords = records
            .where((record) => record.isArchived)
            .toList(growable: false);
        return WorkoutTemplateListSnapshot(
          active: activeRecords
              .map(_workoutTemplateSummaryFromRecord)
              .toList(growable: false),
          archived: archivedRecords
              .map(_workoutTemplateSummaryFromRecord)
              .toList(growable: false),
        );
      },
    );
  }

  @override
  Stream<WorkoutTemplateDetail?> watchTemplate(String templateId) {
    return _repositories.workoutTemplates.watchById(templateId).map(
          (record) =>
              record == null ? null : _workoutTemplateDetailFromRecord(record),
        );
  }

  @override
  Future<String> createTemplate({
    required String name,
    String? notes,
  }) {
    return _repositories.workoutTemplates.create(
      WorkoutTemplateDraft(name: name, notes: notes),
    );
  }

  @override
  Future<void> updateTemplate({
    required String templateId,
    required String name,
    String? notes,
  }) {
    return _repositories.workoutTemplates.updateTemplate(
      templateId,
      name: name,
      notes: notes,
    );
  }

  @override
  Future<void> archiveTemplate(String templateId) {
    return _repositories.workoutTemplates.archive(templateId);
  }

  @override
  Future<void> restoreTemplate(String templateId) {
    return _repositories.workoutTemplates.restore(templateId);
  }

  @override
  Future<String> addExercise({
    required String templateId,
    required String exerciseId,
    String? notes,
  }) {
    return _repositories.workoutTemplates.addExercise(
      templateId,
      exerciseId,
      note: notes,
    );
  }

  @override
  Future<void> updateExerciseNotes({
    required String templateExerciseId,
    String? notes,
  }) {
    return _repositories.workoutTemplates.updateExerciseNote(
      templateExerciseId,
      note: notes,
    );
  }

  @override
  Future<void> removeExercise(String templateExerciseId) {
    return _repositories.workoutTemplates.removeExercise(templateExerciseId);
  }

  @override
  Future<void> reorderExercises({
    required String templateId,
    required List<String> orderedIds,
  }) {
    return _repositories.workoutTemplates.reorderExercises(
      templateId,
      orderedIds,
    );
  }

  @override
  Future<String> addPrescription({
    required String templateExerciseId,
    required PrescriptionInput input,
  }) {
    return _repositories.workoutTemplates.addPrescription(
      templateExerciseId,
      _prescriptionDraftFromInput(input),
    );
  }

  @override
  Future<void> updatePrescription({
    required String prescriptionId,
    required PrescriptionInput input,
  }) {
    return _repositories.workoutTemplates.updatePrescription(
      prescriptionId,
      _prescriptionDraftFromInput(input),
    );
  }

  @override
  Future<void> removePrescription(String prescriptionId) {
    return _repositories.workoutTemplates.removePrescription(prescriptionId);
  }

  @override
  Future<void> reorderPrescriptions({
    required String templateExerciseId,
    required List<String> orderedIds,
  }) {
    return _repositories.workoutTemplates.reorderPrescriptions(
      templateExerciseId,
      orderedIds,
    );
  }

  @override
  Future<String> createTemplateGroup({
    required String templateId,
    required TemplateGroupInput input,
  }) {
    return _repositories.workoutTemplates.createTemplateGroup(
      templateId,
      TemplateGroupDraft(
        name: input.name,
        colorHex: input.colorHex,
        rounds: input.rounds,
        orderedTemplateExerciseIds: input.orderedTemplateExerciseIds,
      ),
    );
  }

  @override
  Future<void> updateTemplateGroup({
    required String groupId,
    required TemplateGroupInput input,
  }) {
    return _repositories.workoutTemplates.updateTemplateGroup(
      groupId,
      TemplateGroupDraft(
        name: input.name,
        colorHex: input.colorHex,
        rounds: input.rounds,
        orderedTemplateExerciseIds: input.orderedTemplateExerciseIds,
      ),
    );
  }

  @override
  Future<void> reorderTemplateGroups({
    required String templateId,
    required List<String> orderedIds,
  }) {
    return _repositories.workoutTemplates.reorderTemplateGroups(
      templateId,
      orderedIds,
    );
  }

  @override
  Future<void> dissolveTemplateGroup(String groupId) {
    return _repositories.workoutTemplates.dissolveTemplateGroup(groupId);
  }
}

WorkoutTemplateSummary _workoutTemplateSummaryFromRecord(
  WorkoutTemplateSummaryRecord record,
) {
  return WorkoutTemplateSummary(
    id: record.id,
    name: record.name,
    notes: record.notes,
    exerciseCount: record.exerciseCount,
    isArchived: record.isArchived,
  );
}

PrescriptionDraft _prescriptionDraftFromInput(PrescriptionInput input) {
  return PrescriptionDraft(
    mode: input.mode == TemplatePrescriptionMode.fixed
        ? PrescriptionMode.fixed
        : PrescriptionMode.copyPrevious,
    values: input.values,
    repeat: input.repeat,
    restAfter: input.restAfter,
  );
}

WorkoutTemplateDetail _workoutTemplateDetailFromRecord(
  WorkoutTemplateRecord record,
) {
  return WorkoutTemplateDetail(
    id: record.id,
    name: record.name,
    notes: record.notes,
    groups: record.groups
        .map(
          (group) => TemplateGroupDetail(
            id: group.id,
            name: group.name,
            colorHex: group.colorHex,
            rounds: group.rounds,
            members: group.members
                .map(
                  (member) => TemplateGroupMemberDetail(
                    templateExerciseId: member.templateExerciseId,
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false),
    exercises: record.exercises
        .map(
          (entry) => TemplateExerciseDetail(
            id: entry.id,
            exerciseId: entry.exerciseId,
            name: entry.exercise.name,
            type: entry.exercise.type,
            defaultLoadUnit: entry.exercise.defaultLoadUnit,
            loadMode: entry.exercise.loadMode,
            notes: entry.note,
            prescriptions: entry.prescriptions
                .map(
                  (prescription) => PrescriptionDetail(
                    id: prescription.id,
                    mode: prescription.mode == PrescriptionMode.fixed
                        ? TemplatePrescriptionMode.fixed
                        : TemplatePrescriptionMode.copyPrevious,
                    values: prescription.values,
                    repeat: prescription.repeat,
                    restAfter: prescription.restAfter,
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false),
  );
}

final class WorkoutTemplateListSnapshot {
  WorkoutTemplateListSnapshot({
    required List<WorkoutTemplateSummary> active,
    required List<WorkoutTemplateSummary> archived,
  })  : active = List<WorkoutTemplateSummary>.unmodifiable(active),
        archived = List<WorkoutTemplateSummary>.unmodifiable(archived);

  static final empty = WorkoutTemplateListSnapshot(
    active: const <WorkoutTemplateSummary>[],
    archived: const <WorkoutTemplateSummary>[],
  );

  final List<WorkoutTemplateSummary> active;
  final List<WorkoutTemplateSummary> archived;

  WorkoutTemplateListSnapshot mapSummary(
    String templateId,
    WorkoutTemplateSummary Function(WorkoutTemplateSummary) update,
  ) {
    return WorkoutTemplateListSnapshot(
      active: active
          .map((item) => item.id == templateId ? update(item) : item)
          .toList(growable: false),
      archived: archived
          .map((item) => item.id == templateId ? update(item) : item)
          .toList(growable: false),
    );
  }
}

final class WorkoutTemplateSummary {
  const WorkoutTemplateSummary({
    required this.id,
    required this.name,
    required this.exerciseCount,
    required this.isArchived,
    this.notes,
  });

  final String id;
  final String name;
  final String? notes;
  final int exerciseCount;
  final bool isArchived;

  WorkoutTemplateSummary copyWith({
    String? name,
    String? Function()? notes,
    bool? isArchived,
    int? exerciseCount,
  }) {
    return WorkoutTemplateSummary(
      id: id,
      name: name ?? this.name,
      notes: notes == null ? this.notes : notes(),
      exerciseCount: exerciseCount ?? this.exerciseCount,
      isArchived: isArchived ?? this.isArchived,
    );
  }
}

final class WorkoutTemplateDetail {
  WorkoutTemplateDetail({
    required this.id,
    required this.name,
    required List<TemplateExerciseDetail> exercises,
    List<TemplateGroupDetail> groups = const <TemplateGroupDetail>[],
    this.notes,
  })  : exercises = List<TemplateExerciseDetail>.unmodifiable(exercises),
        groups = List<TemplateGroupDetail>.unmodifiable(groups);

  final String id;
  final String name;
  final String? notes;
  final List<TemplateExerciseDetail> exercises;
  final List<TemplateGroupDetail> groups;

  WorkoutTemplateDetail copyWith({
    String? name,
    String? Function()? notes,
    List<TemplateExerciseDetail>? exercises,
    List<TemplateGroupDetail>? groups,
  }) {
    return WorkoutTemplateDetail(
      id: id,
      name: name ?? this.name,
      notes: notes == null ? this.notes : notes(),
      exercises: exercises ?? this.exercises,
      groups: groups ?? this.groups,
    );
  }
}

final class TemplateGroupDetail {
  TemplateGroupDetail({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.rounds,
    required List<TemplateGroupMemberDetail> members,
  }) : members = List<TemplateGroupMemberDetail>.unmodifiable(members);

  final String id;
  final String name;
  final String colorHex;
  final int rounds;
  final List<TemplateGroupMemberDetail> members;

  TemplateGroupDetail copyWith({
    String? name,
    String? colorHex,
    int? rounds,
    List<TemplateGroupMemberDetail>? members,
  }) {
    return TemplateGroupDetail(
      id: id,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      rounds: rounds ?? this.rounds,
      members: members ?? this.members,
    );
  }
}

final class TemplateGroupMemberDetail {
  const TemplateGroupMemberDetail({required this.templateExerciseId});

  final String templateExerciseId;
}

final class TemplateGroupInput {
  TemplateGroupInput({
    required this.name,
    required this.colorHex,
    required this.rounds,
    required List<String> orderedTemplateExerciseIds,
  }) : orderedTemplateExerciseIds =
            List<String>.unmodifiable(orderedTemplateExerciseIds);

  final String name;
  final String colorHex;
  final int rounds;
  final List<String> orderedTemplateExerciseIds;
}

final class TemplateExerciseDetail {
  TemplateExerciseDetail({
    required this.id,
    required this.exerciseId,
    required this.name,
    required this.type,
    required this.defaultLoadUnit,
    required this.loadMode,
    required List<PrescriptionDetail> prescriptions,
    this.notes,
  }) : prescriptions = List<PrescriptionDetail>.unmodifiable(prescriptions);

  final String id;
  final String exerciseId;
  final String name;
  final ExerciseType type;
  final TrainingUnit defaultLoadUnit;
  final ExerciseLoadMode loadMode;
  final String? notes;
  final List<PrescriptionDetail> prescriptions;

  TemplateExerciseDetail copyWith({
    String? Function()? notes,
    List<PrescriptionDetail>? prescriptions,
  }) {
    return TemplateExerciseDetail(
      id: id,
      exerciseId: exerciseId,
      name: name,
      type: type,
      defaultLoadUnit: defaultLoadUnit,
      loadMode: loadMode,
      notes: notes == null ? this.notes : notes(),
      prescriptions: prescriptions ?? this.prescriptions,
    );
  }
}

enum TemplatePrescriptionMode { fixed, copyPrevious }

final class PrescriptionInput {
  const PrescriptionInput({
    required this.mode,
    required this.repeat,
    required this.values,
    this.restAfter,
  });

  final TemplatePrescriptionMode mode;
  final LoggedSet values;
  final int repeat;
  final Duration? restAfter;
}

final class PrescriptionDetail {
  const PrescriptionDetail({
    required this.id,
    required this.mode,
    required this.values,
    required this.repeat,
    required this.restAfter,
  });

  factory PrescriptionDetail.fromInput({
    required String id,
    required PrescriptionInput input,
  }) {
    return PrescriptionDetail(
      id: id,
      mode: input.mode,
      values: input.values,
      repeat: input.repeat,
      restAfter: input.restAfter,
    );
  }

  final String id;
  final TemplatePrescriptionMode mode;
  final LoggedSet values;
  final int repeat;
  final Duration? restAfter;
}
