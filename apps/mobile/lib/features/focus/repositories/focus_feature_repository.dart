import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';

final focusFeatureRepositoryProvider = Provider<FocusFeatureRepository>(
  (ref) => RepositoryFocusFeatureRepository(
    ref.watch(trainingRepositoriesProvider),
  ),
);

/// Presentation-facing boundary for Focuses: the list a Workout can be
/// started under, the exercises the user has logged under each, and the
/// writes that record or manage them.
abstract interface class FocusFeatureRepository {
  /// Active Focuses in the user's order.
  Stream<List<FocusRecord>> watchActive();

  /// Every Focus, archived ones included, for labelling Workouts recorded
  /// under a Focus that has since been archived.
  Stream<Map<String, FocusRecord>> watchAllById();

  /// The exercises logged in Workouts under [focusId], most recent first.
  Stream<List<FocusExerciseUse>> watchRecentExerciseUses(String focusId);

  /// Each starter Focus's staple exercises, offered before any history.
  Future<Map<String, List<String>>> starterExerciseIds();

  Future<String> create(String name);

  Future<void> rename(String id, String name);

  Future<void> reorder(List<String> orderedIds);

  Future<void> archive(String id);

  Future<void> setWorkoutFocus(String workoutId, String? focusId);

  Future<void> setTemplateFocus(String workoutTemplateId, String? focusId);
}

/// Focus-less [FocusFeatureRepository] for app roots composed without a
/// real database (widget tests, the app-shell harness).
class StubFocusFeatureRepository implements FocusFeatureRepository {
  const StubFocusFeatureRepository({
    this.focuses = const <FocusRecord>[],
  });

  final List<FocusRecord> focuses;

  @override
  Stream<List<FocusRecord>> watchActive() {
    return Stream<List<FocusRecord>>.value(focuses);
  }

  @override
  Stream<Map<String, FocusRecord>> watchAllById() {
    return Stream<Map<String, FocusRecord>>.value(<String, FocusRecord>{
      for (final focus in focuses) focus.id: focus,
    });
  }

  @override
  Stream<List<FocusExerciseUse>> watchRecentExerciseUses(String focusId) {
    return Stream<List<FocusExerciseUse>>.value(const <FocusExerciseUse>[]);
  }

  @override
  Future<Map<String, List<String>>> starterExerciseIds() async =>
      const <String, List<String>>{};

  @override
  Future<String> create(String name) async => 'stub-focus';

  @override
  Future<void> rename(String id, String name) async {}

  @override
  Future<void> reorder(List<String> orderedIds) async {}

  @override
  Future<void> archive(String id) async {}

  @override
  Future<void> setWorkoutFocus(String workoutId, String? focusId) async {}

  @override
  Future<void> setTemplateFocus(
    String workoutTemplateId,
    String? focusId,
  ) async {}
}

class RepositoryFocusFeatureRepository implements FocusFeatureRepository {
  const RepositoryFocusFeatureRepository(this._repositories);

  final TrainingRepositories _repositories;

  // The starter Focuses are seeded with the Platform Library; a first read
  // waits for that seed (memoized, so later reads do not).
  Stream<T> _afterSeed<T>(Stream<T> Function() watch) async* {
    await _repositories.catalog.ensurePlatformLibrarySeeded();
    yield* watch();
  }

  @override
  Stream<List<FocusRecord>> watchActive() {
    return _afterSeed(_repositories.focuses.watchActive);
  }

  @override
  Stream<Map<String, FocusRecord>> watchAllById() {
    return _afterSeed(_repositories.focuses.watchAllById);
  }

  @override
  Stream<List<FocusExerciseUse>> watchRecentExerciseUses(String focusId) {
    return _repositories.focuses.watchRecentExerciseUses(focusId);
  }

  @override
  Future<Map<String, List<String>>> starterExerciseIds() {
    return _repositories.focuses.starterExerciseIds();
  }

  @override
  Future<String> create(String name) => _repositories.focuses.create(name);

  @override
  Future<void> rename(String id, String name) {
    return _repositories.focuses.rename(id, name: name);
  }

  @override
  Future<void> reorder(List<String> orderedIds) {
    return _repositories.focuses.reorder(orderedIds);
  }

  @override
  Future<void> archive(String id) => _repositories.focuses.archive(id);

  @override
  Future<void> setWorkoutFocus(String workoutId, String? focusId) {
    return _repositories.workoutSessions.setFocus(workoutId, focusId: focusId);
  }

  @override
  Future<void> setTemplateFocus(String workoutTemplateId, String? focusId) {
    return _repositories.workoutTemplates.setFocus(
      workoutTemplateId,
      focusId: focusId,
    );
  }
}
