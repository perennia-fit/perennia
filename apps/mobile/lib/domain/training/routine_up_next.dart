/// Pure derivation of "Up next" suggestions for one cadenced Routine
/// (ROUTINES.md §1.2, §3.1;;).
///
/// No stored cursor participates anywhere in this file: the rotation
/// position is derived on demand from the Routine's ordered history of
/// Template Links, which are themselves provenance-only facts, never a
/// cursor. Weekly Cadences are calendar-bound (the selected Training Day's
/// weekday picks the slot, stateless, and resets every calendar day);
/// rotating Cadences are progress-bound (the latest linked Workout's slot is
/// "current", and the next non-empty slot is up next). *Materialized*
/// advances the rotation, not *finished*; skipping days never advances it;
/// picking a slot out of order re-anchors to fact — all three fall out
/// naturally from deriving purely off the single latest fact rather than
/// any remembered expectation.
library;

import 'routine_cadence.dart';
import 'training_day.dart';

/// One active Routine Entry available to suggest.
///
/// The caller is responsible for excluding entries whose referenced
/// Workout Template is archived (materialize already refuses to start one;
/// this pure function has no notion of archival).
final class UpNextRoutineEntry {
  const UpNextRoutineEntry({
    required this.routineEntryId,
    required this.workoutTemplateId,
    required this.templateName,
    required this.slot,
  });

  final String routineEntryId;
  final String workoutTemplateId;
  final String templateName;
  final int slot;
}

/// One historical Template Link fact for the Routine:
/// provenance only, read here purely to derive position.
///
/// [sequence] is a caller-assigned strictly increasing materialize order
/// (e.g. an index over Template Links sorted by their time-sortable id) —
/// kept abstract from wall-clock time so this pure function never parses a
/// `DateTime` or reasons about timezones. [workoutLocalDate] is used only
/// by the weekly derivation's "already done today" check.
final class UpNextTemplateLinkFact {
  const UpNextTemplateLinkFact({
    required this.workoutTemplateId,
    required this.slot,
    required this.sequence,
    this.workoutLocalDate,
  });

  final String workoutTemplateId;
  final int slot;
  final int sequence;
  final TrainingDayDate? workoutLocalDate;
}

/// One suggested (or already-done) session card.
final class UpNextCard {
  const UpNextCard({
    required this.routineEntryId,
    required this.workoutTemplateId,
    required this.templateName,
    required this.slot,
    required this.isDone,
  });

  final String routineEntryId;
  final String workoutTemplateId;
  final String templateName;
  final int slot;
  final bool isDone;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is UpNextCard &&
            other.routineEntryId == routineEntryId &&
            other.workoutTemplateId == workoutTemplateId &&
            other.templateName == templateName &&
            other.slot == slot &&
            other.isDone == isDone;
  }

  @override
  int get hashCode => Object.hash(
        routineEntryId,
        workoutTemplateId,
        templateName,
        slot,
        isDone,
      );
}

/// One Routine's derived Up-next suggestion: the slot in play and its
/// ordered cards — not-yet-done sessions first, done sessions (ticked)
/// after (ROUTINES.md §3.1's "remaining sessions of a half-done slot
/// first, done sessions shown ticked").
final class RoutineUpNextSuggestion {
  RoutineUpNextSuggestion({
    required this.slot,
    required Iterable<UpNextCard> cards,
  }) : cards = List<UpNextCard>.unmodifiable(cards);

  final int slot;
  final List<UpNextCard> cards;
}

/// Derives the Up-next suggestion for one cadenced Routine, or `null` when
/// there is nothing to suggest (a rest day for weekly; every slot empty, or
/// no active Entries at all, for rotating).
RoutineUpNextSuggestion? deriveRoutineUpNext({
  required Cadence cadence,
  required Iterable<UpNextRoutineEntry> entries,
  required Iterable<UpNextTemplateLinkFact> links,
  required TrainingDayDate selectedDate,
}) {
  final entriesBySlot = <int, List<UpNextRoutineEntry>>{};
  for (final entry in entries) {
    entriesBySlot
        .putIfAbsent(entry.slot, () => <UpNextRoutineEntry>[])
        .add(entry);
  }
  if (entriesBySlot.isEmpty) {
    return null;
  }

  return switch (cadence.kind) {
    CadenceKind.weekly => _deriveWeekly(entriesBySlot, links, selectedDate),
    CadenceKind.rotating =>
      _deriveRotating(entriesBySlot, links, cadence.slotCount),
  };
}

RoutineUpNextSuggestion? _deriveWeekly(
  Map<int, List<UpNextRoutineEntry>> entriesBySlot,
  Iterable<UpNextTemplateLinkFact> links,
  TrainingDayDate selectedDate,
) {
  final slot = selectedDate.toLocalDateTime().weekday;
  final slotEntries = entriesBySlot[slot];
  if (slotEntries == null || slotEntries.isEmpty) {
    return null;
  }
  final doneTemplateIds = <String>{
    for (final link in links)
      if (link.slot == slot && link.workoutLocalDate == selectedDate)
        link.workoutTemplateId,
  };
  return RoutineUpNextSuggestion(
    slot: slot,
    cards: _cardsFor(slotEntries, doneTemplateIds),
  );
}

RoutineUpNextSuggestion? _deriveRotating(
  Map<int, List<UpNextRoutineEntry>> entriesBySlot,
  Iterable<UpNextTemplateLinkFact> links,
  int slotCount,
) {
  final sortedLinks = List<UpNextTemplateLinkFact>.of(links)
    ..sort((a, b) => b.sequence.compareTo(a.sequence));

  int? currentSlot;
  final doneTemplateIds = <String>{};
  if (sortedLinks.isNotEmpty) {
    currentSlot = sortedLinks.first.slot;
    for (final link in sortedLinks) {
      if (link.slot != currentSlot) {
        break;
      }
      doneTemplateIds.add(link.workoutTemplateId);
    }
  }

  if (currentSlot != null) {
    final currentEntries =
        entriesBySlot[currentSlot] ?? const <UpNextRoutineEntry>[];
    final hasRemaining = currentEntries.any(
      (entry) => !doneTemplateIds.contains(entry.workoutTemplateId),
    );
    if (hasRemaining) {
      return RoutineUpNextSuggestion(
        slot: currentSlot,
        cards: _cardsFor(currentEntries, doneTemplateIds),
      );
    }
  }

  // The current slot (if any) is fully done, or nothing has ever
  // materialized: scan forward for the next non-empty slot, wrapping the
  // window. `base = 0` stands for "before slot 1" in the never-started
  // case, so the scan naturally starts at slot 1.
  final base = currentSlot ?? 0;
  for (var step = 1; step <= slotCount; step += 1) {
    final candidate = ((base - 1 + step) % slotCount) + 1;
    final candidateEntries = entriesBySlot[candidate];
    if (candidateEntries != null && candidateEntries.isNotEmpty) {
      return RoutineUpNextSuggestion(
        slot: candidate,
        cards: _cardsFor(candidateEntries, const <String>{}),
      );
    }
  }
  return null;
}

List<UpNextCard> _cardsFor(
  List<UpNextRoutineEntry> entries,
  Set<String> doneTemplateIds,
) {
  final notDone = entries.where(
    (entry) => !doneTemplateIds.contains(entry.workoutTemplateId),
  );
  final done = entries.where(
    (entry) => doneTemplateIds.contains(entry.workoutTemplateId),
  );
  return <UpNextCard>[
    for (final entry in notDone) _cardFrom(entry, isDone: false),
    for (final entry in done) _cardFrom(entry, isDone: true),
  ];
}

UpNextCard _cardFrom(UpNextRoutineEntry entry, {required bool isDone}) {
  return UpNextCard(
    routineEntryId: entry.routineEntryId,
    workoutTemplateId: entry.workoutTemplateId,
    templateName: entry.templateName,
    slot: entry.slot,
    isDone: isDone,
  );
}
