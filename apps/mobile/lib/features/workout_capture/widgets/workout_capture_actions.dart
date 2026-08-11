import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import 'workout_capture_form_style.dart';

class WorkoutCaptureActions extends StatelessWidget {
  const WorkoutCaptureActions({
    required this.isSubmitting,
    required this.canSave,
    required this.onCancel,
    required this.onSave,
    required this.cancelButtonKey,
    required this.saveButtonKey,
    super.key,
  });

  final bool isSubmitting;
  final bool canSave;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final Key cancelButtonKey;
  final Key saveButtonKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: OutlinedButton(
            key: cancelButtonKey,
            style: workoutCaptureOutlinedButtonStyle(context),
            onPressed: isSubmitting ? null : onCancel,
            child: Text(context.l10n.cancelAction),
          ),
        ),
        const SizedBox(width: AppDimens.dense),
        Expanded(
          child: Semantics(
            liveRegion: isSubmitting,
            child: FilledButton.icon(
              key: saveButtonKey,
              style: workoutCaptureSaveButtonStyle(context),
              onPressed: canSave ? onSave : null,
              icon: Icon(
                isSubmitting ? Icons.hourglass_top : Icons.save_outlined,
              ),
              label: Text(
                isSubmitting
                    ? context.l10n.workoutCaptureSaving
                    : context.l10n.workoutCaptureSave,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
