import '../../data/repositories/training_repositories.dart';
import '../../l10n/l10n.dart';

/// The message shown when an undo is refused, shared by the Activity feed and
/// the Meal screen (meal-logging.md §7).
///
/// A [ActivityLogUndoConflictReason.dependent] conflict means the undone Batch
/// created a Meal that later gained foods, so it gets its own plain message;
/// every other refusal names the first changed row.
String undoConflictMessage(
  AppLocalizations l10n,
  ActivityLogUndoResult result,
) {
  final count = result.conflicts.length;
  if (result.conflicts.isEmpty) {
    return l10n.activityUndoGenericConflict;
  }
  if (result.conflicts.any(
    (conflict) => conflict.reason == ActivityLogUndoConflictReason.dependent,
  )) {
    return l10n.activityUndoDependentConflict;
  }
  final first = result.conflicts.first;
  return l10n.activityUndoConflict(count, first.entityTable, first.entityId);
}
