import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/training/plan_validation.dart' as plan_validation;
import '../../../domain/training/routine_cadence.dart';
import '../repositories/routine_plan_feature_repository.dart';

final routinePlanListControllerProvider =
    StreamNotifierProvider<RoutinePlanListController, RoutinePlanListSnapshot>(
  RoutinePlanListController.new,
);

final routinePlanCommandsProvider = Provider<RoutinePlanCommands>((ref) {
  return RoutinePlanCommands(
    ref.watch(routinePlanFeatureRepositoryProvider),
  );
});

final routinePlanDetailControllerProvider =
    StreamProvider.family<RoutinePlanDetail?, String>((ref, routineId) {
  return ref
      .watch(routinePlanFeatureRepositoryProvider)
      .watchRoutine(routineId);
});

final routinePlanTemplateOptionsProvider =
    StreamProvider<List<RoutineWorkoutTemplateOption>>((ref) {
  return ref
      .watch(routinePlanFeatureRepositoryProvider)
      .watchAvailableTemplates();
});

class RoutinePlanListController
    extends StreamNotifier<RoutinePlanListSnapshot> {
  @override
  Stream<RoutinePlanListSnapshot> build() {
    return ref.watch(routinePlanFeatureRepositoryProvider).watchRoutines();
  }
}

final class RoutinePlanCommands {
  const RoutinePlanCommands(this._repository);

  final RoutinePlanFeatureRepository _repository;

  Future<String> createRoutine({required String name, String? notes}) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw const RoutinePlanInputException('Enter a Routine name.');
    }
    return _repository.createRoutine(
      name: normalizedName,
      notes: _normalizedOptionalText(notes),
    );
  }

  Future<void> updateRoutine({
    required String routineId,
    required String name,
    String? notes,
  }) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw const RoutinePlanInputException('Enter a Routine name.');
    }
    return _repository.updateRoutine(
      routineId: routineId,
      name: normalizedName,
      notes: _normalizedOptionalText(notes),
    );
  }

  Future<void> archiveRoutine(String routineId) {
    return _repository.archiveRoutine(routineId);
  }

  Future<void> restoreRoutine(String routineId) {
    return _repository.restoreRoutine(routineId);
  }

  Future<String> addTemplateReference({
    required String routineId,
    required String workoutTemplateId,
    int? slot,
  }) {
    return _repository.addTemplateReference(
      routineId: routineId,
      workoutTemplateId: workoutTemplateId,
      slot: slot,
    );
  }

  Future<void> removeTemplateReference(String routineEntryId) {
    return _repository.removeTemplateReference(routineEntryId);
  }

  Future<void> reorderTemplateReferences({
    required String routineId,
    required List<String> orderedEntryIds,
  }) {
    return _repository.reorderTemplateReferences(
      routineId: routineId,
      orderedEntryIds: List<String>.unmodifiable(orderedEntryIds),
    );
  }

  RoutineCadenceInputValidation validateCadence(
    Cadence? cadence,
  ) {
    final result = plan_validation.validateRoutineCadence(
      cadenceKind: switch (cadence?.kind) {
        null => null,
        CadenceKind.weekly => 'weekly',
        CadenceKind.rotating => 'rotating',
      },
      cadenceWindow: cadence?.window,
      slots: const <num?>[],
    );
    return RoutineCadenceInputValidation(
      accepted: result.accepted,
      hasWarning: result.warnings.isNotEmpty,
    );
  }

  Future<void> setCadence({
    required String routineId,
    required Cadence? cadence,
  }) {
    return _repository.setCadence(
      routineId: routineId,
      cadence: cadence,
    );
  }

  Future<void> moveTemplateReferenceToSlot({
    required String routineEntryId,
    required int slot,
  }) {
    return _repository.moveTemplateReferenceToSlot(
      routineEntryId: routineEntryId,
      slot: slot,
    );
  }

  Future<void> replaceCadenceLayout({
    required String routineId,
    required List<RoutineEntryPlacement> placements,
  }) {
    return _repository.replaceCadenceLayout(
      routineId: routineId,
      placements: List<RoutineEntryPlacement>.unmodifiable(placements),
    );
  }

  Future<void> restoreReferencedTemplate(String workoutTemplateId) {
    return _repository.restoreReferencedTemplate(workoutTemplateId);
  }
}

final class RoutineCadenceInputValidation {
  const RoutineCadenceInputValidation({
    required this.accepted,
    required this.hasWarning,
  });

  final bool accepted;
  final bool hasWarning;
}

final class RoutinePlanInputException implements Exception {
  const RoutinePlanInputException(this.message);

  final String message;

  @override
  String toString() => message;
}

String? _normalizedOptionalText(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
