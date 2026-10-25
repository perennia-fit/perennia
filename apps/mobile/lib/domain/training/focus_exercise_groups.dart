/// How the exercises of one Focus are offered when a Workout starts under it.
library;

import 'training_records.dart';

/// The exercises of a Focus in the order they are offered: what the user has
/// logged under it (most recent first), then the Focus's staples in their
/// curated order, then the rest of the Focus, favorites first and then by
/// name. Each exercise appears once, in the first group it qualifies for.
final class FocusExerciseGroups {
  const FocusExerciseGroups({
    required this.recent,
    required this.staples,
    required this.rest,
  });

  final List<(ExerciseRecord, FocusExerciseUse)> recent;
  final List<ExerciseRecord> staples;
  final List<ExerciseRecord> rest;

  bool get isEmpty => recent.isEmpty && staples.isEmpty && rest.isEmpty;
}

/// Groups [exercises] for [focusId]. Uses or staples naming an exercise not
/// in [exercises] (archived, shadowed, filtered out) are dropped.
FocusExerciseGroups focusExerciseGroups({
  required Iterable<ExerciseRecord> exercises,
  required String focusId,
  required List<FocusExerciseUse> uses,
  required List<String> starterIds,
}) {
  final byId = <String, ExerciseRecord>{
    for (final exercise in exercises) exercise.id: exercise,
  };
  final recent = <(ExerciseRecord, FocusExerciseUse)>[
    for (final use in uses)
      if (byId[use.exerciseId] case final exercise?) (exercise, use),
  ];
  final placed = <String>{for (final (exercise, _) in recent) exercise.id};
  final staples = <ExerciseRecord>[
    for (final id in starterIds)
      if (!placed.contains(id))
        if (byId[id] case final exercise?) exercise,
  ];
  placed.addAll(staples.map((exercise) => exercise.id));
  final rest = [
    for (final exercise in byId.values)
      if (!placed.contains(exercise.id) &&
          exercise.focusIds.contains(focusId))
        (exercise, exercise.name.toLowerCase()),
  ]..sort((left, right) {
      if (left.$1.isFavorite != right.$1.isFavorite) {
        return left.$1.isFavorite ? -1 : 1;
      }
      return left.$2.compareTo(right.$2);
    });
  return FocusExerciseGroups(
    recent: List.unmodifiable(recent),
    staples: List.unmodifiable(staples),
    rest: List.unmodifiable(rest.map((entry) => entry.$1)),
  );
}
