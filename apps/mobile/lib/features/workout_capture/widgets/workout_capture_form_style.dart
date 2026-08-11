import 'package:flutter/material.dart';

import '../../../theme/theme.dart';

class WorkoutCaptureFieldLabel extends StatelessWidget {
  const WorkoutCaptureFieldLabel({
    required this.label,
    super.key,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.dense / 2),
      child: Text(label, style: context.textStyles.label),
    );
  }
}

InputDecoration workoutCaptureInputDecoration(
  BuildContext context, {
  String? hintText,
  String? helperText,
  String? errorText,
  Widget? suffixIcon,
}) {
  final divider = context.colors.divider;
  final primary = Theme.of(context).colorScheme.primary;
  const radius = AppRadii.cardMd;

  OutlineInputBorder border(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return InputDecoration(
    hintText: hintText,
    helperText: helperText,
    errorText: errorText,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: context.colors.surface,
    floatingLabelBehavior: FloatingLabelBehavior.never,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppDimens.base,
      vertical: AppDimens.dense,
    ),
    enabledBorder: border(divider),
    disabledBorder: border(divider),
    focusedBorder: border(primary, width: 2),
    errorBorder: border(divider, width: 2),
    focusedErrorBorder: border(primary, width: 2),
    errorStyle: context.textStyles.label.copyWith(
      color: context.colors.textPrimary,
    ),
  );
}

ButtonStyle workoutCaptureOutlinedButtonStyle(BuildContext context) {
  return OutlinedButton.styleFrom(
    foregroundColor: context.colors.textPrimary,
    disabledForegroundColor: context.colors.textSecondary,
    side: BorderSide(color: context.colors.divider),
    minimumSize: const Size.fromHeight(AppDimens.rowHeight),
    shape: const RoundedRectangleBorder(borderRadius: AppRadii.cardMd),
  );
}

ButtonStyle workoutCaptureSaveButtonStyle(BuildContext context) {
  return FilledButton.styleFrom(
    backgroundColor: context.colors.save,
    foregroundColor: Theme.of(context).colorScheme.onSecondary,
    minimumSize: const Size.fromHeight(AppDimens.rowHeight),
    shape: const RoundedRectangleBorder(borderRadius: AppRadii.cardMd),
  );
}
