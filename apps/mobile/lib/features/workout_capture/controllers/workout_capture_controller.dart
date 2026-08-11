import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/training/workout_capture.dart';
import '../repositories/workout_capture_feature_repository.dart';

final workoutCapturePreviewProvider =
    FutureProvider.autoDispose.family<WorkoutCapturePreview, String>(
  (ref, workoutId) =>
      ref.watch(workoutCaptureFeatureRepositoryProvider).preview(workoutId),
);

final workoutCaptureRoutineOptionsProvider =
    StreamProvider.autoDispose<List<WorkoutCaptureRoutineOption>>(
  (ref) => ref.watch(workoutCaptureFeatureRepositoryProvider).watchRoutines(),
);

final workoutCaptureControllerProvider = NotifierProvider.autoDispose
    .family<WorkoutCaptureController, WorkoutCaptureFormState, String>(
  WorkoutCaptureController.new,
);

class WorkoutCaptureController extends Notifier<WorkoutCaptureFormState> {
  WorkoutCaptureController(this.workoutId);

  final String workoutId;

  @override
  WorkoutCaptureFormState build() => const WorkoutCaptureFormState();

  void nameChanged() {
    state = state.forEditedInput(showNameError: false);
  }

  void selectRoutine(WorkoutCaptureRoutineOption? routine) {
    state = state.forEditedInput(
      selectedRoutine: routine,
      selectedSlot: null,
      showSlotError: false,
      placementNotice: null,
    );
  }

  void selectSlot(int slot) {
    final routine = state.selectedRoutine;
    if (routine == null ||
        !routine.requiresSlot ||
        slot < 1 ||
        slot > routine.slotCount) {
      state = state.forEditedInput(
        selectedSlot: null,
        showSlotError: true,
        placementNotice: WorkoutCapturePlacementNotice.cadenceChanged,
      );
      return;
    }
    state = state.forEditedInput(
      selectedSlot: slot,
      showSlotError: false,
      placementNotice: null,
    );
  }

  void setWarningsAccepted(
    bool accepted,
    WorkoutCaptureValidationResult validation,
  ) {
    state = state.copyWith(
      acknowledgedWarningTokens: accepted
          ? validation.warningAcknowledgementTokenSet
          : const <String>{},
      saveFailure: null,
    );
  }

  /// Reconciles a reactive Routine snapshot without ever converting an
  /// explicit selection into the no-placement choice.
  void reconcileRoutines(List<WorkoutCaptureRoutineOption> routines) {
    final selected = state.selectedRoutine;
    if (selected == null) {
      return;
    }

    WorkoutCaptureRoutineOption? refreshed;
    for (final routine in routines) {
      if (routine.id == selected.id) {
        refreshed = routine;
        break;
      }
    }
    if (refreshed == null) {
      if (state.placementNotice ==
              WorkoutCapturePlacementNotice.routineUnavailable &&
          state.selectedSlot == null) {
        return;
      }
      state = state.forEditedInput(
        selectedRoutine: selected,
        selectedSlot: null,
        showSlotError: false,
        placementNotice: WorkoutCapturePlacementNotice.routineUnavailable,
      );
      return;
    }

    final detailsChanged = refreshed.name != selected.name ||
        refreshed.cadenceKind != selected.cadenceKind ||
        refreshed.slotCount != selected.slotCount;
    final selectedSlot = state.selectedSlot;
    final cadenceKindChanged = refreshed.cadenceKind != selected.cadenceKind;
    final wasUnavailable = state.placementNotice ==
        WorkoutCapturePlacementNotice.routineUnavailable;
    final wasCadenceChanged =
        state.placementNotice == WorkoutCapturePlacementNotice.cadenceChanged;
    if (!detailsChanged && !wasUnavailable) {
      return;
    }

    final slotOutOfRange = refreshed.requiresSlot &&
        selectedSlot != null &&
        (selectedSlot < 1 || selectedSlot > refreshed.slotCount);
    final replacementSlotRequired = refreshed.requiresSlot &&
        (cadenceKindChanged ||
            slotOutOfRange ||
            (selectedSlot == null &&
                (wasUnavailable ||
                    wasCadenceChanged ||
                    !selected.requiresSlot)));
    final placementReviewRequired =
        cadenceKindChanged || replacementSlotRequired;

    state = state.forEditedInput(
      selectedRoutine: refreshed,
      selectedSlot:
          refreshed.requiresSlot && !cadenceKindChanged && !slotOutOfRange
              ? selectedSlot
              : null,
      showSlotError: replacementSlotRequired,
      placementNotice: placementReviewRequired
          ? WorkoutCapturePlacementNotice.cadenceChanged
          : null,
    );
  }

  WorkoutCaptureValidationResult validationFor(WorkoutCapturePreview preview) {
    return state.runtimeValidation ?? preview.validation;
  }

  bool warningsAcceptedFor(WorkoutCaptureValidationResult validation) {
    final expected = validation.warningAcknowledgementTokenSet;
    return state.acknowledgedWarningTokens.length == expected.length &&
        state.acknowledgedWarningTokens.containsAll(expected);
  }

  bool canSubmit(WorkoutCapturePreview preview) {
    final validation = validationFor(preview);
    final routine = state.selectedRoutine;
    final slot = state.selectedSlot;
    final placementReady = routine?.requiresSlot != true ||
        (slot != null && slot >= 1 && slot <= routine!.slotCount);
    return !state.isSubmitting &&
        state.placementNotice == null &&
        placementReady &&
        validation.accepted &&
        (validation.warnings.isEmpty || warningsAcceptedFor(validation));
  }

  Future<WorkoutCaptureSaveResult?> submit({
    required WorkoutCapturePreview preview,
    required String name,
  }) async {
    if (state.isSubmitting) {
      return null;
    }
    final normalizedName = name.trim();
    final routine = state.selectedRoutine;
    final nameMissing = normalizedName.isEmpty;
    final slotMissing = routine?.requiresSlot == true &&
        (state.selectedSlot == null ||
            state.selectedSlot! < 1 ||
            state.selectedSlot! > routine!.slotCount);
    if (nameMissing || slotMissing || state.placementNotice != null) {
      state = state.copyWith(
        showNameError: nameMissing,
        showSlotError: slotMissing,
      );
      return null;
    }

    final placement = switch (routine) {
      null => const WorkoutCapturePlacement.none(),
      WorkoutCaptureRoutineOption(requiresSlot: false) =>
        WorkoutCapturePlacement.collectionAppend(routine.id),
      WorkoutCaptureRoutineOption(requiresSlot: true) =>
        WorkoutCapturePlacement.cadenceSlot(routine.id, state.selectedSlot!),
    };
    state = state.copyWith(isSubmitting: true, saveFailure: null);
    try {
      final result =
          await ref.read(workoutCaptureFeatureRepositoryProvider).save(
                WorkoutCaptureSaveRequest(
                  workoutId: workoutId,
                  name: normalizedName,
                  placement: placement,
                  acknowledgedWarningTokens: state.acknowledgedWarningTokens,
                ),
              );
      state = state.copyWith(isSubmitting: false);
      return result;
    } on WorkoutCaptureValidationException catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        runtimeValidation: error.validation,
        acknowledgedWarningTokens: const <String>{},
      );
    } on WorkoutCaptureWarningsNotAcknowledged catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        runtimeValidation: error.validation,
        acknowledgedWarningTokens: const <String>{},
      );
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        saveFailure: WorkoutCaptureSaveFailure.unexpected,
      );
    }
    return null;
  }
}

enum WorkoutCapturePlacementNotice { routineUnavailable, cadenceChanged }

enum WorkoutCaptureSaveFailure { unexpected }

final class WorkoutCaptureFormState {
  const WorkoutCaptureFormState({
    this.selectedRoutine,
    this.selectedSlot,
    this.acknowledgedWarningTokens = const <String>{},
    this.isSubmitting = false,
    this.showNameError = false,
    this.showSlotError = false,
    this.placementNotice,
    this.runtimeValidation,
    this.saveFailure,
  });

  final WorkoutCaptureRoutineOption? selectedRoutine;
  final int? selectedSlot;
  final Set<String> acknowledgedWarningTokens;
  final bool isSubmitting;
  final bool showNameError;
  final bool showSlotError;
  final WorkoutCapturePlacementNotice? placementNotice;
  final WorkoutCaptureValidationResult? runtimeValidation;
  final WorkoutCaptureSaveFailure? saveFailure;

  WorkoutCaptureFormState forEditedInput({
    Object? selectedRoutine = _notProvided,
    Object? selectedSlot = _notProvided,
    bool? showNameError,
    bool? showSlotError,
    Object? placementNotice = _notProvided,
  }) {
    return WorkoutCaptureFormState(
      selectedRoutine: identical(selectedRoutine, _notProvided)
          ? this.selectedRoutine
          : selectedRoutine as WorkoutCaptureRoutineOption?,
      selectedSlot: identical(selectedSlot, _notProvided)
          ? this.selectedSlot
          : selectedSlot as int?,
      isSubmitting: isSubmitting,
      showNameError: showNameError ?? this.showNameError,
      showSlotError: showSlotError ?? this.showSlotError,
      placementNotice: identical(placementNotice, _notProvided)
          ? this.placementNotice
          : placementNotice as WorkoutCapturePlacementNotice?,
    );
  }

  WorkoutCaptureFormState copyWith({
    Object? selectedRoutine = _notProvided,
    Object? selectedSlot = _notProvided,
    Set<String>? acknowledgedWarningTokens,
    bool? isSubmitting,
    bool? showNameError,
    bool? showSlotError,
    Object? placementNotice = _notProvided,
    Object? runtimeValidation = _notProvided,
    Object? saveFailure = _notProvided,
  }) {
    return WorkoutCaptureFormState(
      selectedRoutine: identical(selectedRoutine, _notProvided)
          ? this.selectedRoutine
          : selectedRoutine as WorkoutCaptureRoutineOption?,
      selectedSlot: identical(selectedSlot, _notProvided)
          ? this.selectedSlot
          : selectedSlot as int?,
      acknowledgedWarningTokens: Set<String>.unmodifiable(
        acknowledgedWarningTokens ?? this.acknowledgedWarningTokens,
      ),
      isSubmitting: isSubmitting ?? this.isSubmitting,
      showNameError: showNameError ?? this.showNameError,
      showSlotError: showSlotError ?? this.showSlotError,
      placementNotice: identical(placementNotice, _notProvided)
          ? this.placementNotice
          : placementNotice as WorkoutCapturePlacementNotice?,
      runtimeValidation: identical(runtimeValidation, _notProvided)
          ? this.runtimeValidation
          : runtimeValidation as WorkoutCaptureValidationResult?,
      saveFailure: identical(saveFailure, _notProvided)
          ? this.saveFailure
          : saveFailure as WorkoutCaptureSaveFailure?,
    );
  }
}

const _notProvided = Object();
