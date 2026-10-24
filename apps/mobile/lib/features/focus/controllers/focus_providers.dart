import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
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
