/// How the Exercise List merges the Platform Library with user Exercises:
/// Shadowing, ordering, and grouping into catalog sections.
library;

import 'training_records.dart';

/// Groups the merged catalog into Exercise List sections.
///
/// A virtual Favorites section comes first when any Exercise is a favorite.
/// Category sections follow in [categories] order, skipping empty ones. Any
/// Exercise whose category is not in [categories] lands in a trailing
/// section per category id, sorted by id, with uncategorized Exercises last.
List<ExerciseCatalogSectionRecord> exerciseCatalogSections(
  List<ExerciseCategoryRecord> categories,
  List<ExerciseRecord> exercises,
) {
  final categoryById = <String, ExerciseCategoryRecord>{
    for (final category in categories) category.id: category,
  };
  final shadowAwareExercises = markShadowingUserExercises(exercises);
  final selectedExercises = mergedExercises(shadowAwareExercises);
  final exercisesByCategoryId = <String?, List<ExerciseRecord>>{};
  for (final exercise in selectedExercises) {
    exercisesByCategoryId
        .putIfAbsent(exercise.categoryId, () => <ExerciseRecord>[])
        .add(exercise);
  }

  final sections = <ExerciseCatalogSectionRecord>[];
  final favoriteExercises = selectedExercises
      .where((exercise) => exercise.isFavorite)
      .toList(growable: false);
  if (favoriteExercises.isNotEmpty) {
    sections.add(
      ExerciseCatalogSectionRecord.virtualFavorites(
        exercises: List<ExerciseRecord>.unmodifiable(favoriteExercises),
      ),
    );
  }

  for (final category in categories) {
    final exerciseList = exercisesByCategoryId.remove(category.id);
    if (exerciseList == null || exerciseList.isEmpty) {
      continue;
    }

    sections.add(
      ExerciseCatalogSectionRecord(
        category: category,
        exercises: List<ExerciseRecord>.unmodifiable(exerciseList),
      ),
    );
  }

  final remainingCategoryIds = exercisesByCategoryId.keys.toList()
    ..sort((left, right) {
      if (left == null && right == null) {
        return 0;
      }
      if (left == null) {
        return 1;
      }
      if (right == null) {
        return -1;
      }
      return left.compareTo(right);
    });
  for (final categoryId in remainingCategoryIds) {
    final exerciseList = exercisesByCategoryId[categoryId]!;
    sections.add(
      ExerciseCatalogSectionRecord(
        category: categoryId == null ? null : categoryById[categoryId],
        exercises: List<ExerciseRecord>.unmodifiable(exerciseList),
      ),
    );
  }

  return List<ExerciseCatalogSectionRecord>.unmodifiable(sections);
}

/// The Exercises the catalog shows: every user Exercise, plus each Platform
/// Library Exercise no user Exercise shares a name with, sorted by
/// [compareExerciseRecords]. A user Exercise with a Platform Library name
/// hides that Platform Exercise rather than appearing next to it.
List<ExerciseRecord> mergedExercises(List<ExerciseRecord> exercises) {
  final userNames = exercises
      .where((exercise) => exercise.origin == ExerciseLibraryOrigin.user)
      .map((exercise) => normalizeExerciseName(exercise.name))
      .toSet();
  final selected = exercises
      .where(
        (exercise) =>
            exercise.origin == ExerciseLibraryOrigin.user ||
            !userNames.contains(normalizeExerciseName(exercise.name)),
      )
      .toList(growable: false);

  selected.sort(compareExerciseRecords);
  return selected;
}

/// Sets [ExerciseRecord.shadowsPlatformExercise] on each user Exercise whose
/// name matches a Platform Library Exercise, and clears it on every other
/// record.
List<ExerciseRecord> markShadowingUserExercises(
  List<ExerciseRecord> exercises,
) {
  final platformNames = exercises
      .where((exercise) => exercise.origin == ExerciseLibraryOrigin.platform)
      .map((exercise) => normalizeExerciseName(exercise.name))
      .toSet();

  return exercises.map((exercise) {
    final shadowsPlatform = exercise.origin == ExerciseLibraryOrigin.user &&
        platformNames.contains(normalizeExerciseName(exercise.name));
    return exercise.copyWith(shadowsPlatformExercise: shadowsPlatform);
  }).toList(growable: false);
}

/// Orders Exercises by normalized name, user before Platform on a tie.
int compareExerciseRecords(ExerciseRecord left, ExerciseRecord right) {
  final leftName = normalizeExerciseName(left.name);
  final rightName = normalizeExerciseName(right.name);
  final nameComparison = leftName.compareTo(rightName);
  if (nameComparison != 0) {
    return nameComparison;
  }

  return _originRank(left.origin).compareTo(_originRank(right.origin));
}

int _originRank(ExerciseLibraryOrigin origin) {
  return switch (origin) {
    ExerciseLibraryOrigin.user => 0,
    ExerciseLibraryOrigin.platform => 1,
  };
}

/// The key two Exercise names are compared by: trimmed and lower-cased.
///
/// Shadowing and the repository's unique-active-name check use this same
/// key, so they agree on which names belong to the same Exercise.
String normalizeExerciseName(String name) {
  return name.trim().toLowerCase();
}
