import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';

/// Renders the Finish prompt's diff summary, e.g. "+ Dips, − Incline Press"
/// (ROUTINES.md §3.4). Exercises added by the performed Workout lead with
/// "+", planned-but-unperformed Exercises with "−", and Exercises whose Sets
/// changed without changing membership with "~". All-or-nothing — this is
/// display only, never a per-item picker (the Template editor covers
/// surgery).
String templateDivergenceDiffText(
  TemplateDivergenceResult divergence,
  AppLocalizations l10n,
) {
  final parts = <String>[
    for (final exercise in divergence.addedExercises)
      '+ ${exercise.exerciseName}',
    for (final exercise in divergence.removedExercises)
      '− ${exercise.exerciseName}',
    for (final exercise in divergence.changedExercises)
      '~ ${exercise.exerciseName}',
  ];
  if (divergence.groupsChanged) {
    parts.add(l10n.templateUpdateGroupsChangedNote);
  }
  if (parts.isEmpty) {
    return l10n.templateUpdateNoChangesNote;
  }
  return parts.join(', ');
}
