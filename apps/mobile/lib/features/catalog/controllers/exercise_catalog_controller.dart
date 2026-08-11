import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../repositories/exercise_catalog_repository.dart';

final exerciseCatalogControllerProvider =
    StreamNotifierProvider<ExerciseCatalogController, ExerciseCatalogState>(
  ExerciseCatalogController.new,
);

class ExerciseCatalogController extends StreamNotifier<ExerciseCatalogState> {
  @override
  Stream<ExerciseCatalogState> build() {
    final repository = ref.watch(exerciseCatalogRepositoryProvider);
    return repository.watchCatalog().map(
          (sections) => ExerciseCatalogState(sections: sections),
        );
  }
}

final class ExerciseCatalogState {
  ExerciseCatalogState({
    required List<ExerciseCatalogSectionRecord> sections,
  }) : sections = List<ExerciseCatalogSectionRecord>.unmodifiable(sections);

  final List<ExerciseCatalogSectionRecord> sections;

  int get totalExercises => sections
      .where((section) => !section.isVirtual)
      .fold<int>(0, (total, section) => total + section.exercises.length);
}
