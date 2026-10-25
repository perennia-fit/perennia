import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/training/focus_exercise_groups.dart';
import '../../catalog/controllers/exercise_catalog_controller.dart';
import '../repositories/focus_feature_repository.dart';

/// Active Focuses in the user's order, for pickers and the start sheet.
final activeFocusesProvider = StreamProvider<List<FocusRecord>>((ref) {
  return ref.watch(focusFeatureRepositoryProvider).watchActive();
});

/// Every Focus by id, archived ones included, so a Workout's label survives
/// its Focus being archived.
final focusesByIdProvider = StreamProvider<Map<String, FocusRecord>>((ref) {
  return ref.watch(focusFeatureRepositoryProvider).watchAllById();
});

/// One Focus by id, archived or not; null for no Focus or an unknown id.
final focusRecordProvider =
    Provider.autoDispose.family<FocusRecord?, String?>((ref, focusId) {
  return focusId == null
      ? null
      : ref.watch(focusesByIdProvider).value?[focusId];
});

/// The exercises one Focus offers, grouped and ordered, or null until the
/// catalog and the Focus's history have loaded. Recomputed only when one of
/// them changes, never on a mere rebuild.
final focusExerciseGroupsProvider =
    Provider.autoDispose.family<FocusExerciseGroups?, String>((ref, focusId) {
  final catalog = ref.watch(exerciseCatalogControllerProvider).value;
  final uses = ref.watch(focusExerciseUsesProvider(focusId)).value;
  if (catalog == null || uses == null) {
    return null;
  }
  return focusExerciseGroups(
    exercises: [
      for (final section in catalog.sections)
        if (!section.isVirtual) ...section.exercises,
    ],
    focusId: focusId,
    uses: uses,
    starterIds:
        ref.watch(focusStarterExerciseIdsProvider).value?[focusId] ??
            const <String>[],
  );
});

/// Each starter Focus's staple exercises, from the bundled seed.
final focusStarterExerciseIdsProvider =
    FutureProvider<Map<String, List<String>>>((ref) {
  return ref.watch(focusFeatureRepositoryProvider).starterExerciseIds();
});

/// The exercises logged under one Focus, most recent first.
final focusExerciseUsesProvider =
    StreamProvider.autoDispose.family<List<FocusExerciseUse>, String>(
  (ref, focusId) {
    return ref
        .watch(focusFeatureRepositoryProvider)
        .watchRecentExerciseUses(focusId);
  },
);
