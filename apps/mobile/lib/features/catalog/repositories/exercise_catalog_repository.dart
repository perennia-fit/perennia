import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';

final exerciseCatalogRepositoryProvider = Provider<ExerciseCatalogRepository>(
  (ref) => RepositoryExerciseCatalogRepository(
    ref.watch(trainingRepositoriesProvider),
  ),
);

abstract interface class ExerciseCatalogRepository {
  Stream<List<ExerciseCatalogSectionRecord>> watchCatalog();
}

class RepositoryExerciseCatalogRepository implements ExerciseCatalogRepository {
  RepositoryExerciseCatalogRepository(this._repositories);

  final TrainingRepositories _repositories;
  Future<void>? _seedFuture;

  @override
  Stream<List<ExerciseCatalogSectionRecord>> watchCatalog() async* {
    await _ensurePlatformLibrarySeeded();
    yield* _repositories.catalog.watchMergedCatalog();
  }

  Future<void> _ensurePlatformLibrarySeeded() {
    final existingSeedFuture = _seedFuture;
    if (existingSeedFuture != null) {
      return existingSeedFuture;
    }

    late final Future<void> nextSeedFuture;
    nextSeedFuture =
        _repositories.catalog.ensurePlatformLibrarySeeded().catchError(
      (Object error, StackTrace stackTrace) {
        if (identical(_seedFuture, nextSeedFuture)) {
          _seedFuture = null;
        }
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _seedFuture = nextSeedFuture;
    return nextSeedFuture;
  }
}

class StubExerciseCatalogRepository implements ExerciseCatalogRepository {
  const StubExerciseCatalogRepository({
    this.sections = const <ExerciseCatalogSectionRecord>[],
  });

  final List<ExerciseCatalogSectionRecord> sections;

  @override
  Stream<List<ExerciseCatalogSectionRecord>> watchCatalog() {
    return Stream<List<ExerciseCatalogSectionRecord>>.value(sections);
  }
}
