import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/workout_template_feature_repository.dart';

final workoutTemplateListControllerProvider = StreamNotifierProvider<
    WorkoutTemplateListController, WorkoutTemplateListSnapshot>(
  WorkoutTemplateListController.new,
);

final workoutTemplateDetailControllerProvider =
    StreamProvider.family<WorkoutTemplateDetail?, String>((ref, templateId) {
  return ref
      .watch(workoutTemplateFeatureRepositoryProvider)
      .watchTemplate(templateId);
});

class WorkoutTemplateListController
    extends StreamNotifier<WorkoutTemplateListSnapshot> {
  @override
  Stream<WorkoutTemplateListSnapshot> build() {
    return ref.watch(workoutTemplateFeatureRepositoryProvider).watchTemplates();
  }

  Future<String> createTemplate({
    required String name,
    String? notes,
  }) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw const WorkoutTemplateInputException('Enter a template name.');
    }
    return ref.read(workoutTemplateFeatureRepositoryProvider).createTemplate(
          name: normalizedName,
          notes: _normalizedOptionalText(notes),
        );
  }

  Future<void> updateTemplate({
    required String templateId,
    required String name,
    String? notes,
  }) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw const WorkoutTemplateInputException('Enter a template name.');
    }
    return ref.read(workoutTemplateFeatureRepositoryProvider).updateTemplate(
          templateId: templateId,
          name: normalizedName,
          notes: _normalizedOptionalText(notes),
        );
  }

  Future<void> archiveTemplate(String templateId) {
    return ref
        .read(workoutTemplateFeatureRepositoryProvider)
        .archiveTemplate(templateId);
  }

  Future<void> restoreTemplate(String templateId) {
    return ref
        .read(workoutTemplateFeatureRepositoryProvider)
        .restoreTemplate(templateId);
  }

  Future<String> addExercise({
    required String templateId,
    required String exerciseId,
    String? notes,
  }) {
    return ref.read(workoutTemplateFeatureRepositoryProvider).addExercise(
          templateId: templateId,
          exerciseId: exerciseId,
          notes: _normalizedOptionalText(notes),
        );
  }

  Future<void> updateExerciseNotes({
    required String templateExerciseId,
    String? notes,
  }) {
    return ref
        .read(workoutTemplateFeatureRepositoryProvider)
        .updateExerciseNotes(
          templateExerciseId: templateExerciseId,
          notes: _normalizedOptionalText(notes),
        );
  }

  Future<void> removeExercise(String templateExerciseId) {
    return ref
        .read(workoutTemplateFeatureRepositoryProvider)
        .removeExercise(templateExerciseId);
  }

  Future<void> reorderExercises({
    required String templateId,
    required List<String> orderedIds,
  }) {
    return ref.read(workoutTemplateFeatureRepositoryProvider).reorderExercises(
          templateId: templateId,
          orderedIds: List<String>.unmodifiable(orderedIds),
        );
  }

  Future<String> addPrescription({
    required String templateExerciseId,
    required PrescriptionInput input,
  }) {
    _validatePrescription(input);
    return ref.read(workoutTemplateFeatureRepositoryProvider).addPrescription(
          templateExerciseId: templateExerciseId,
          input: input,
        );
  }

  Future<void> updatePrescription({
    required String prescriptionId,
    required PrescriptionInput input,
  }) {
    _validatePrescription(input);
    return ref
        .read(workoutTemplateFeatureRepositoryProvider)
        .updatePrescription(
          prescriptionId: prescriptionId,
          input: input,
        );
  }

  Future<void> removePrescription(String prescriptionId) {
    return ref
        .read(workoutTemplateFeatureRepositoryProvider)
        .removePrescription(prescriptionId);
  }

  Future<void> reorderPrescriptions({
    required String templateExerciseId,
    required List<String> orderedIds,
  }) {
    return ref
        .read(workoutTemplateFeatureRepositoryProvider)
        .reorderPrescriptions(
          templateExerciseId: templateExerciseId,
          orderedIds: List<String>.unmodifiable(orderedIds),
        );
  }

  Future<String> createTemplateGroup({
    required String templateId,
    required TemplateGroupInput input,
  }) {
    return ref
        .read(workoutTemplateFeatureRepositoryProvider)
        .createTemplateGroup(
          templateId: templateId,
          input: _normalizedTemplateGroupInput(input),
        );
  }

  Future<void> updateTemplateGroup({
    required String groupId,
    required TemplateGroupInput input,
  }) {
    return ref
        .read(workoutTemplateFeatureRepositoryProvider)
        .updateTemplateGroup(
          groupId: groupId,
          input: _normalizedTemplateGroupInput(input),
        );
  }

  Future<void> reorderTemplateGroups({
    required String templateId,
    required List<String> orderedIds,
  }) {
    return ref
        .read(workoutTemplateFeatureRepositoryProvider)
        .reorderTemplateGroups(
          templateId: templateId,
          orderedIds: List<String>.unmodifiable(orderedIds),
        );
  }

  Future<void> dissolveTemplateGroup(String groupId) {
    return ref
        .read(workoutTemplateFeatureRepositoryProvider)
        .dissolveTemplateGroup(groupId);
  }

  void _validatePrescription(PrescriptionInput input) {
    if (input.repeat < 1) {
      throw const WorkoutTemplateInputException(
        'Prescription repeat must be at least 1.',
      );
    }
    if (input.restAfter?.isNegative ?? false) {
      throw const WorkoutTemplateInputException(
        'Prescription rest cannot be negative.',
      );
    }
  }
}

TemplateGroupInput _normalizedTemplateGroupInput(TemplateGroupInput input) {
  return TemplateGroupInput(
    name: input.name.trim(),
    colorHex: input.colorHex.trim().toUpperCase(),
    rounds: input.rounds,
    orderedTemplateExerciseIds: input.orderedTemplateExerciseIds,
  );
}

final class WorkoutTemplateInputException implements Exception {
  const WorkoutTemplateInputException(this.message);

  final String message;

  @override
  String toString() => message;
}

String? _normalizedOptionalText(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
