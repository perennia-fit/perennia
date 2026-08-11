import 'package:flutter/material.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import 'template_divergence_diff_text.dart';

/// The Finish-time "update the template?" prompt (ROUTINES.md §3.4) and the
/// overflow's "Update template" confirmation — the same dialog either way,
/// since Update means the same thing regardless of when it's invoked.
/// Dismissing (the back button, tapping outside, or "Not now") pops `false`
/// (or `null`) and is a silent no: no state is recorded anywhere.
class TemplateUpdatePromptDialog extends StatelessWidget {
  const TemplateUpdatePromptDialog({super.key, required this.summary});

  final TemplateDivergenceSummary summary;

  static Key dismissButtonKey(String workoutId) =>
      Key('templateUpdatePrompt.$workoutId.dismiss');

  static Key confirmButtonKey(String workoutId) =>
      Key('templateUpdatePrompt.$workoutId.confirm');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.templateUpdatePromptTitle(summary.templateName)),
      content: Text(
        templateDivergenceDiffText(summary.divergence, l10n),
      ),
      actions: [
        TextButton(
          key: dismissButtonKey(summary.workoutId),
          style: TextButton.styleFrom(
            foregroundColor: context.colors.textPrimary,
          ),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.templateUpdateDismissAction),
        ),
        FilledButton(
          key: confirmButtonKey(summary.workoutId),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.templateUpdateConfirmAction),
        ),
      ],
    );
  }
}

/// Shows [TemplateUpdatePromptDialog] and resolves `true` only when the user
/// explicitly confirms Update.
Future<bool> showTemplateUpdatePromptDialog(
  BuildContext context, {
  required TemplateDivergenceSummary summary,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => TemplateUpdatePromptDialog(summary: summary),
  );
  return result ?? false;
}
