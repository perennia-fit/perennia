import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/controllers/home_controller.dart';
import '../repositories/up_next_feature_repository.dart';

/// The Up-next suggestions for the currently selected Training Day
/// (ROUTINES.md §3.1). Re-derives on every rebuild — nothing here is a
/// cursor, so date navigation and kill-and-reopen both just re-run the pure
/// derivation over current facts.
final upNextSuggestionsProvider =
    StreamProvider<List<UpNextSuggestionView>>((ref) {
  final repository = ref.watch(upNextFeatureRepositoryProvider);
  final selectedDate = ref.watch(selectedTrainingDayProvider);
  return repository.watchSuggestions(selectedDate);
});
