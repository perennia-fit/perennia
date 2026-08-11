import 'package:flutter/material.dart';

import '../../../domain/training/workout_capture.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';

Key workoutCaptureValidationIssueKey({
  required bool warning,
  required String field,
  required String rule,
  required int index,
}) {
  final kind = warning ? 'warning' : 'error';
  return Key('workoutCapture.validation.$kind.$field.$rule.$index');
}

class WorkoutCapturePreviewCounts extends StatelessWidget {
  const WorkoutCapturePreviewCounts({
    required this.exerciseCount,
    required this.setCount,
    required this.groupCount,
    super.key,
  });

  final int exerciseCount;
  final int setCount;
  final int groupCount;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: context.l10n.workoutCaptureCountsSemantics(
        exerciseCount,
        setCount,
        groupCount,
      ),
      child: ExcludeSemantics(
        child: Wrap(
          spacing: AppDimens.dense,
          runSpacing: AppDimens.dense,
          children: [
            _CountBadge(
              icon: Icons.fitness_center,
              label: context.l10n.workoutCaptureExerciseCount(exerciseCount),
            ),
            _CountBadge(
              icon: Icons.format_list_numbered,
              label: context.l10n.workoutCaptureSetCount(setCount),
            ),
            _CountBadge(
              icon: Icons.link,
              label: context.l10n.workoutCaptureGroupCount(groupCount),
            ),
          ],
        ),
      ),
    );
  }
}

class WorkoutCaptureReferenceNote extends StatelessWidget {
  const WorkoutCaptureReferenceNote({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadii.cardMd,
        border: Border.all(color: context.colors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.dense),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              color: context.colors.textSecondary,
            ),
            const SizedBox(width: AppDimens.dense),
            Expanded(
              child: Text(
                context.l10n.workoutCaptureReferenceNote,
                style: context.textStyles.body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WorkoutCaptureValidationPanel extends StatelessWidget {
  const WorkoutCaptureValidationPanel({
    required this.title,
    required this.issues,
    required this.warning,
    super.key,
  });

  final String title;
  final List<WorkoutCaptureValidationIssue> issues;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final borderColor = context.colors.divider;
    final iconColor =
        warning ? context.colors.textSecondary : context.colors.textPrimary;

    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadii.cardMd,
          border: Border.all(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.dense),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    warning ? Icons.warning_amber_rounded : Icons.error_outline,
                    color: iconColor,
                  ),
                  const SizedBox(width: AppDimens.dense),
                  Expanded(child: Text(title, style: context.textStyles.h2)),
                ],
              ),
              const SizedBox(height: AppDimens.dense),
              for (final (index, issue) in issues.indexed)
                Padding(
                  key: workoutCaptureValidationIssueKey(
                    warning: warning,
                    field: issue.fieldPath,
                    rule: issue.rule,
                    index: index,
                  ),
                  padding: EdgeInsets.only(
                    bottom:
                        index == issues.length - 1 ? 0 : AppDimens.dense / 3,
                  ),
                  child: Text(
                    '- ${issue.message}',
                    style: context.textStyles.body,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class WorkoutCaptureInlineFailure extends StatelessWidget {
  const WorkoutCaptureInlineFailure({
    required this.message,
    super.key,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadii.cardMd,
          border: Border.all(color: context.colors.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.dense),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline,
                color: context.colors.textPrimary,
              ),
              const SizedBox(width: AppDimens.dense),
              Expanded(child: Text(message, style: context.textStyles.body)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadii.cardMd,
        border: Border.all(color: context.colors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.dense,
          vertical: AppDimens.dense / 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(width: AppDimens.dense / 2),
            Flexible(child: Text(label)),
          ],
        ),
      ),
    );
  }
}
