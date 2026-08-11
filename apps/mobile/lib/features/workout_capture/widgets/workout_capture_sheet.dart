import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/training/workout_capture.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../controllers/workout_capture_controller.dart';
import '../repositories/workout_capture_feature_repository.dart';
import 'workout_capture_actions.dart';
import 'workout_capture_feedback.dart';
import 'workout_capture_form_style.dart';
import 'workout_capture_placement_fields.dart';

Future<WorkoutCaptureSaveResult?> showWorkoutCaptureSheet(
  BuildContext context, {
  required String workoutId,
}) {
  return showModalBottomSheet<WorkoutCaptureSaveResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => WorkoutCaptureSheet(workoutId: workoutId),
  );
}

class WorkoutCaptureSheet extends ConsumerStatefulWidget {
  const WorkoutCaptureSheet({
    required this.workoutId,
    super.key,
  });

  final String workoutId;

  static const sheetKey = Key('workoutCapture.sheet');
  static const nameFieldKey = Key('workoutCapture.name');
  static const routineFieldKey = Key('workoutCapture.routine');
  static const slotFieldKey = Key('workoutCapture.slot');
  static const warningsAcceptanceKey = Key('workoutCapture.acceptWarnings');
  static const saveButtonKey = Key('workoutCapture.save');
  static const cancelButtonKey = Key('workoutCapture.cancel');
  static const closeButtonKey = Key('workoutCapture.close');
  static const retryButtonKey = Key('workoutCapture.retry');
  static const saveFailureKey = Key('workoutCapture.saveFailure');

  static const routinePickerKey =
      WorkoutCapturePlacementFields.routinePickerKey;
  static const slotPickerKey = WorkoutCapturePlacementFields.slotPickerKey;
  static const slotPickerListKey =
      WorkoutCapturePlacementFields.slotPickerListKey;
  static const slotNumberFieldKey =
      WorkoutCapturePlacementFields.slotNumberFieldKey;
  static const slotApplyButtonKey =
      WorkoutCapturePlacementFields.slotApplyButtonKey;

  static Key routineOptionKey(String id) =>
      WorkoutCapturePlacementFields.routineOptionKey(id);
  static Key slotOptionKey(int slot) =>
      WorkoutCapturePlacementFields.slotOptionKey(slot);

  static Key validationIssueKey({
    required bool warning,
    required String field,
    required String rule,
    required int index,
  }) {
    return workoutCaptureValidationIssueKey(
      warning: warning,
      field: field,
      rule: rule,
      index: index,
    );
  }

  @override
  ConsumerState<WorkoutCaptureSheet> createState() =>
      _WorkoutCaptureSheetState();
}

class _WorkoutCaptureSheetState extends ConsumerState<WorkoutCaptureSheet> {
  final _nameController = TextEditingController();
  bool _didSeedName = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      workoutCaptureRoutineOptionsProvider,
      (_, next) => next.whenData(
        (routines) => ref
            .read(workoutCaptureControllerProvider(widget.workoutId).notifier)
            .reconcileRoutines(routines),
      ),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controllerProvider =
        workoutCaptureControllerProvider(widget.workoutId);
    final formState = ref.watch(controllerProvider);
    final preview = ref.watch(workoutCapturePreviewProvider(widget.workoutId));
    final routines = ref.watch(workoutCaptureRoutineOptionsProvider);
    final routineValues =
        routines.value ?? const <WorkoutCaptureRoutineOption>[];

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope<WorkoutCaptureSaveResult>(
      canPop: !formState.isSubmitting,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: bottomInset),
        child: FractionallySizedBox(
          key: WorkoutCaptureSheet.sheetKey,
          heightFactor: 0.92,
          child: Material(
            color: context.colors.background,
            child: preview.when(
              data: (value) => _buildForm(
                context,
                preview: value,
                routines: routineValues,
                routinesLoading: routines.isLoading,
                formState: formState,
              ),
              loading: () => _buildLoading(context),
              error: (_, __) => _buildPreviewError(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetHeader(
              submitting: false,
              onClose: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Semantics(
                label: context.l10n.workoutCaptureLoading,
                liveRegion: true,
                child: Center(
                  child: CircularProgressIndicator(
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewError(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimens.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetHeader(
              submitting: false,
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AppDimens.base),
            Icon(
              Icons.error_outline,
              size: AppDimens.touchTarget,
              color: context.colors.textPrimary,
            ),
            const SizedBox(height: AppDimens.dense),
            Text(
              context.l10n.workoutCapturePreviewUnavailable,
              textAlign: TextAlign.center,
              style: context.textStyles.body,
            ),
            const SizedBox(height: AppDimens.base),
            OutlinedButton.icon(
              key: WorkoutCaptureSheet.retryButtonKey,
              style: workoutCaptureOutlinedButtonStyle(context),
              onPressed: () => ref.invalidate(
                workoutCapturePreviewProvider(widget.workoutId),
              ),
              icon: const Icon(Icons.refresh),
              label: Text(context.l10n.workoutCaptureRetry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(
    BuildContext context, {
    required WorkoutCapturePreview preview,
    required List<WorkoutCaptureRoutineOption> routines,
    required bool routinesLoading,
    required WorkoutCaptureFormState formState,
  }) {
    _seedName(preview.suggestedName);
    final controllerProvider =
        workoutCaptureControllerProvider(widget.workoutId);
    final controller = ref.read(controllerProvider.notifier);
    final validation = controller.validationFor(preview);
    final hasWarnings = validation.warnings.isNotEmpty;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(AppDimens.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetHeader(
              submitting: formState.isSubmitting,
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AppDimens.dense),
            WorkoutCapturePreviewCounts(
              exerciseCount: preview.exerciseCount,
              setCount: preview.setCount,
              groupCount: preview.groupCount,
            ),
            const SizedBox(height: AppDimens.base),
            WorkoutCaptureFieldLabel(
              label: context.l10n.workoutCaptureNameLabel,
            ),
            Semantics(
              label: context.l10n.workoutCaptureNameLabel,
              textField: true,
              child: TextField(
                key: WorkoutCaptureSheet.nameFieldKey,
                controller: _nameController,
                enabled: !formState.isSubmitting,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onChanged: (_) => controller.nameChanged(),
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                decoration: workoutCaptureInputDecoration(
                  context,
                  errorText: formState.showNameError
                      ? context.l10n.workoutCaptureNameRequired
                      : null,
                ),
              ),
            ),
            WorkoutCapturePlacementFields(
              routines: routines,
              routinesLoading: routinesLoading,
              state: formState,
              enabled: !formState.isSubmitting,
              routineFieldKey: WorkoutCaptureSheet.routineFieldKey,
              slotFieldKey: WorkoutCaptureSheet.slotFieldKey,
              onRoutineSelected: controller.selectRoutine,
              onSlotSelected: controller.selectSlot,
            ),
            const SizedBox(height: AppDimens.base),
            const WorkoutCaptureReferenceNote(),
            if (validation.errors.isNotEmpty) ...[
              const SizedBox(height: AppDimens.base),
              WorkoutCaptureValidationPanel(
                title: context.l10n.workoutCaptureErrorsTitle,
                issues: validation.errors,
                warning: false,
              ),
            ],
            if (hasWarnings) ...[
              const SizedBox(height: AppDimens.base),
              WorkoutCaptureValidationPanel(
                title: context.l10n.workoutCaptureWarningsTitle,
                issues: validation.warnings,
                warning: true,
              ),
              const SizedBox(height: AppDimens.dense),
              CheckboxListTile(
                key: WorkoutCaptureSheet.warningsAcceptanceKey,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: controller.warningsAcceptedFor(validation),
                onChanged: formState.isSubmitting
                    ? null
                    : (value) => controller.setWarningsAccepted(
                          value ?? false,
                          validation,
                        ),
                title: Text(context.l10n.workoutCaptureAcceptWarnings),
              ),
            ],
            if (formState.saveFailure != null) ...[
              const SizedBox(height: AppDimens.base),
              WorkoutCaptureInlineFailure(
                key: WorkoutCaptureSheet.saveFailureKey,
                message: context.l10n.workoutCaptureSaveFailed,
              ),
            ],
            const SizedBox(height: AppDimens.base),
            WorkoutCaptureActions(
              isSubmitting: formState.isSubmitting,
              canSave: controller.canSubmit(preview),
              cancelButtonKey: WorkoutCaptureSheet.cancelButtonKey,
              saveButtonKey: WorkoutCaptureSheet.saveButtonKey,
              onCancel: () => Navigator.of(context).pop(),
              onSave: () => _submit(preview),
            ),
          ],
        ),
      ),
    );
  }

  void _seedName(String suggestedName) {
    if (_didSeedName) {
      return;
    }
    _nameController
      ..text = suggestedName
      ..selection = TextSelection.collapsed(offset: suggestedName.length);
    _didSeedName = true;
  }

  Future<void> _submit(WorkoutCapturePreview preview) async {
    final result = await ref
        .read(workoutCaptureControllerProvider(widget.workoutId).notifier)
        .submit(preview: preview, name: _nameController.text);
    if (result != null && mounted) {
      Navigator.of(context).pop(result);
    }
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.submitting,
    required this.onClose,
  });

  final bool submitting;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            context.l10n.workoutCaptureTitle,
            style: context.textStyles.h1,
          ),
        ),
        IconButton(
          key: WorkoutCaptureSheet.closeButtonKey,
          tooltip: context.l10n.workoutCaptureClose,
          onPressed: submitting ? null : onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}
