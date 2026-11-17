import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';

/// One line per change between a Workout and its linked Template, read by
/// the Finish summary's Update row and the Workout menu's Update template
/// dialog.
///
/// Added exercises come first, then removed, then those whose Sets changed,
/// then a note if the exercise groups changed. Within each kind the order is
/// the one `compareTemplateToWorkout` built: Workout order for added and
/// changed, template order for removed, since a removed exercise has no place
/// in the Workout. Display only: the update is all-or-nothing, never a
/// per-item picker (the Template editor covers surgery).
List<String> templateDivergenceLines(
  TemplateDivergenceResult result,
  AppLocalizations l10n,
) {
  return <String>[
    for (final exercise in result.addedExercises)
      l10n.templateChangeAdd(exercise.exerciseName),
    for (final exercise in result.removedExercises)
      l10n.templateChangeRemove(exercise.exerciseName),
    for (final exercise in result.changedExercises)
      l10n.templateChangeSets(exercise.exerciseName),
    if (result.groupsChanged) l10n.templateUpdateGroupsChangedNote,
  ];
}

/// The Update template dialog's body: [templateDivergenceLines], one per
/// line, or the "no changes" note when there are none.
String templateDivergenceDiffText(
  TemplateDivergenceResult divergence,
  AppLocalizations l10n,
) {
  final lines = templateDivergenceLines(divergence, l10n);
  if (lines.isEmpty) {
    return l10n.templateUpdateNoChangesNote;
  }
  return lines.join('\n');
}
