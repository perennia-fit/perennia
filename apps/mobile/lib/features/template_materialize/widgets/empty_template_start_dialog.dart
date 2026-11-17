import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../controllers/template_materialize_controller.dart';

/// Asks before starting a Workout Template that has no Template Exercises.
///
/// Materialize copies only Template Exercises and their Prescriptions, never
/// the Template's notes (ROUTINES.md §1.5), so an empty Template starts an
/// empty Workout. That is valid — the user may want an empty session under
/// the Template's Focus — but it should never happen by surprise, which is
/// how a notes-only placeholder Template written by an agent looked like a
/// broken Routine. A Template with exercises starts with no prompt, so the
/// ≤ 2-taps covenant holds for every real plan.
class EmptyTemplateStartDialog extends StatelessWidget {
  const EmptyTemplateStartDialog({super.key, required this.templateName});

  final String templateName;

  static const cancelButtonKey = Key('emptyTemplateStart.cancel');
  static const confirmButtonKey = Key('emptyTemplateStart.confirm');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.templateStartEmptyTitle(templateName)),
      content: Text(l10n.templateStartEmptyMessage),
      actions: [
        TextButton(
          key: cancelButtonKey,
          style: TextButton.styleFrom(
            foregroundColor: context.colors.textPrimary,
          ),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          key: confirmButtonKey,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.templateStartEmptyConfirmAction),
        ),
      ],
    );
  }
}

/// Resolves `true` when starting [workoutTemplateId] should go ahead: the
/// Template has exercises, or the user confirmed an empty start.
///
/// A failed emptiness read lets the start proceed — the materialize call
/// that follows reports its own failure — so this check can never be the
/// reason a real plan doesn't start.
Future<bool> confirmTemplateStart(
  BuildContext context,
  WidgetRef ref, {
  required String workoutTemplateId,
}) async {
  final String? emptyName;
  try {
    emptyName = await ref
        .read(templateMaterializeControllerProvider)
        .emptyTemplateName(workoutTemplateId);
  } on Object {
    return true;
  }
  if (emptyName == null) {
    return true;
  }
  if (!context.mounted) {
    return false;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => EmptyTemplateStartDialog(templateName: emptyName!),
  );
  return confirmed ?? false;
}
