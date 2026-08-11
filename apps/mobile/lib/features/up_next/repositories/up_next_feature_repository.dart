import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/training/training_day.dart';

final upNextFeatureRepositoryProvider = Provider<UpNextFeatureRepository>(
  (ref) => RepositoryUpNextFeatureRepository(
    ref.watch(trainingRepositoriesProvider),
  ),
);

/// Presentation-facing boundary over the derived Up-next read path
/// (ROUTINES.md §3.1;;).
///
/// Read-only: the rotation/weekday position is derived fresh on every
/// watch, never cached or cursor-held. Materializing a suggested card goes
/// through `TemplateMaterializeFeatureRepository` — this boundary never
/// writes.
abstract interface class UpNextFeatureRepository {
  Stream<List<UpNextSuggestionView>> watchSuggestions(
    TrainingDayDate selectedDate,
  );
}

/// Always-empty [UpNextFeatureRepository], for composing the app root in
/// contexts that stub Home away from a real database (widget tests, the
/// app-shell harness) without needing per-call-site provider overrides.
class StubUpNextFeatureRepository implements UpNextFeatureRepository {
  const StubUpNextFeatureRepository();

  @override
  Stream<List<UpNextSuggestionView>> watchSuggestions(
    TrainingDayDate selectedDate,
  ) {
    return Stream<List<UpNextSuggestionView>>.value(
      const <UpNextSuggestionView>[],
    );
  }
}

class RepositoryUpNextFeatureRepository implements UpNextFeatureRepository {
  const RepositoryUpNextFeatureRepository(this._repositories);

  final TrainingRepositories _repositories;

  @override
  Stream<List<UpNextSuggestionView>> watchSuggestions(
    TrainingDayDate selectedDate,
  ) {
    return _repositories.routineUpNext.watchSuggestions(selectedDate).map(
          (summaries) => summaries
              .map(
                (summary) => UpNextSuggestionView(
                  routineId: summary.routineId,
                  routineName: summary.routineName,
                  cadenceKind: summary.cadenceKind,
                  slot: summary.slot,
                  cards: summary.cards.map(
                    (card) => UpNextCardView(
                      routineEntryId: card.routineEntryId,
                      workoutTemplateId: card.workoutTemplateId,
                      templateName: card.templateName,
                      isDone: card.isDone,
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
  }
}

/// One cadenced Routine's derived Up-next suggestion, presentation-ready.
class UpNextSuggestionView {
  UpNextSuggestionView({
    required this.routineId,
    required this.routineName,
    required this.cadenceKind,
    required this.slot,
    required Iterable<UpNextCardView> cards,
  }) : cards = List<UpNextCardView>.unmodifiable(cards);

  final String routineId;
  final String routineName;
  final CadenceKind cadenceKind;
  final int slot;
  final List<UpNextCardView> cards;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is UpNextSuggestionView &&
            runtimeType == other.runtimeType &&
            routineId == other.routineId &&
            routineName == other.routineName &&
            cadenceKind == other.cadenceKind &&
            slot == other.slot &&
            _cardsEqual(other.cards, cards);
  }

  @override
  int get hashCode => Object.hash(
        routineId,
        routineName,
        cadenceKind,
        slot,
        Object.hashAll(cards),
      );
}

/// One suggested (or already-done) session card, presentation-ready.
class UpNextCardView {
  const UpNextCardView({
    required this.routineEntryId,
    required this.workoutTemplateId,
    required this.templateName,
    required this.isDone,
  });

  final String routineEntryId;
  final String workoutTemplateId;
  final String templateName;
  final bool isDone;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is UpNextCardView &&
            runtimeType == other.runtimeType &&
            routineEntryId == other.routineEntryId &&
            workoutTemplateId == other.workoutTemplateId &&
            templateName == other.templateName &&
            isDone == other.isDone;
  }

  @override
  int get hashCode =>
      Object.hash(routineEntryId, workoutTemplateId, templateName, isDone);
}

bool _cardsEqual(List<UpNextCardView> left, List<UpNextCardView> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
