/// The read-side records of the training domain: Exercises, their
/// categories, Workouts, Workout Exercises, and Logged Sets.
///
/// They live in domain, not next to the repositories that build them, so
/// pure training logic (catalog merge, share text) can take them as input
/// without importing the data layer. The repositories re-export this file,
/// so callers that import `training_repositories.dart` see no change.
library;

import 'training_day.dart';
import 'training_dimensions.dart';

class ExerciseRecord {
  ExerciseRecord({
    required this.id,
    required this.origin,
    required this.name,
    required this.type,
    required this.defaultLoadUnit,
    required this.loadMode,
    required this.recordProfile,
    this.isUnilateral = false,
    this.usesRpe = false,
    required this.categoryId,
    List<ExerciseEquipment> equipment = const <ExerciseEquipment>[],
    required this.notes,
    required this.isFavorite,
    required this.updatedAt,
    this.shadowsPlatformExercise = false,
    this.deletedAt,
  }) : equipment = List<ExerciseEquipment>.unmodifiable(equipment);

  final String id;
  final ExerciseLibraryOrigin origin;
  final String name;
  final ExerciseType type;
  final TrainingUnit defaultLoadUnit;
  final ExerciseLoadMode loadMode;
  final RecordProfile recordProfile;
  final bool isUnilateral;
  final bool usesRpe;
  final String? categoryId;
  final List<ExerciseEquipment> equipment;
  final String? notes;
  final bool isFavorite;
  final DateTime updatedAt;
  final bool shadowsPlatformExercise;
  final DateTime? deletedAt;

  bool get isReadOnly => origin == ExerciseLibraryOrigin.platform;

  ExerciseRecord copyWith({
    bool? shadowsPlatformExercise,
  }) {
    return ExerciseRecord(
      id: id,
      origin: origin,
      name: name,
      type: type,
      defaultLoadUnit: defaultLoadUnit,
      loadMode: loadMode,
      recordProfile: recordProfile,
      isUnilateral: isUnilateral,
      usesRpe: usesRpe,
      categoryId: categoryId,
      equipment: equipment,
      notes: notes,
      isFavorite: isFavorite,
      updatedAt: updatedAt,
      shadowsPlatformExercise:
          shadowsPlatformExercise ?? this.shadowsPlatformExercise,
      deletedAt: deletedAt,
    );
  }
}

class WorkoutSessionRecord {
  const WorkoutSessionRecord({
    required this.id,
    required this.startedAt,
    required this.timezone,
    required this.localDate,
    required this.updatedAt,
    this.endedAt,
    this.comment,
    this.deletedAt,
  });

  final String id;
  final DateTime startedAt;
  final String timezone;
  final TrainingDayDate localDate;
  final DateTime? endedAt;
  final String? comment;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class WorkoutExerciseRecord {
  const WorkoutExerciseRecord({
    required this.id,
    required this.workoutId,
    required this.exerciseId,
    required this.position,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String workoutId;
  final String exerciseId;
  final int position;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class LoggedSetRecord {
  const LoggedSetRecord({
    required this.id,
    required this.workoutId,
    required this.exerciseId,
    required this.position,
    required this.values,
    required this.plannedRestAfter,
    this.performedAt,
    required this.isCompleted,
    required this.updatedAt,
    this.comment,
    this.side,
    this.rpe,
    this.deletedAt,
  });

  final String id;
  final String workoutId;
  final String exerciseId;
  final int position;
  final LoggedSet values;
  final Duration? plannedRestAfter;
  final DateTime? performedAt;
  final bool isCompleted;
  final DateTime updatedAt;
  final String? comment;
  final SetSide? side;
  final double? rpe;
  final DateTime? deletedAt;
}

enum ExerciseLibraryOrigin {
  platform,
  user,
}

enum SetSide {
  left,
  right,
}

class ExerciseCategoryRecord {
  const ExerciseCategoryRecord({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.colorHex,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String name;
  final int sortOrder;
  final String colorHex;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

final class ExerciseCatalogSectionRecord {
  ExerciseCatalogSectionRecord({
    required this.category,
    required List<ExerciseRecord> exercises,
    this.virtualId,
    this.virtualTitle,
  }) : exercises = List<ExerciseRecord>.unmodifiable(exercises);

  ExerciseCatalogSectionRecord.virtualFavorites({
    required List<ExerciseRecord> exercises,
  })  : category = null,
        exercises = List<ExerciseRecord>.unmodifiable(exercises),
        virtualId = favoritesId,
        virtualTitle = 'Favorites';

  static const favoritesId = 'favorites';

  final ExerciseCategoryRecord? category;
  final List<ExerciseRecord> exercises;
  final String? virtualId;
  final String? virtualTitle;

  String get id => virtualId ?? category?.id ?? 'uncategorized';

  String get title => virtualTitle ?? category?.name ?? 'Uncategorized';

  bool get isVirtual => virtualId != null;
}
