import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';

/// The Protocols repository provider, mirroring `nutritionRepositoryProvider`.
/// Widgets -> this controller -> the repository (the only layer touching Drift).
final protocolsRepositoryProvider = Provider<ProtocolsRepository>((ref) {
  return ref.watch(trainingRepositoriesProvider).protocols;
});

/// The active (non-archived) `Compound` library, for the bare logging surface's
/// picker. Archived Compounds drop out (PROTOCOLS.md §7).
final compoundListProvider = StreamProvider<List<CompoundRecord>>((ref) {
  return ref.watch(protocolsRepositoryProvider).watchCompounds();
});

/// Lightweight active `Compound` options for read paths that only need an id
/// and label. Dose logging still consumes [compoundListProvider] because it
/// snapshots default/strength details.
final compoundOptionListProvider =
    StreamProvider<List<CompoundOptionRecord>>((ref) {
  return ref.watch(protocolsRepositoryProvider).watchCompoundOptions();
});

/// Active `Compound` schedule options for Protocol plan editors: identity for
/// member chips plus default unit/route for optional Schedule seed values.
final compoundScheduleOptionListProvider =
    StreamProvider<List<CompoundScheduleOptionRecord>>((ref) {
  return ref.watch(protocolsRepositoryProvider).watchCompoundScheduleOptions();
});

final protocolMemberCompoundNamesProvider =
    StreamProvider.family<Map<String, String>, CompoundNameLookupRequest>(
  (ref, request) {
    return ref
        .watch(protocolsRepositoryProvider)
        .watchCompoundNamesByIds(request.idSet);
  },
);

/// The small "recently logged" Compound id shortlist for the Compound list
/// screen: DERIVED on read from each Compound's most recent Dose,
/// never stored. The screen maps these ids onto the already-watched
/// full Compound library it needs for Dose logging defaults.
final recentCompoundIdsProvider = StreamProvider<List<String>>((ref) {
  return ref.watch(protocolsRepositoryProvider).watchRecentCompoundIds();
});

class CompoundNameLookupRequest {
  CompoundNameLookupRequest(Iterable<String> ids)
      : ids = List<String>.unmodifiable(
          ids.toSet().toList(growable: false)..sort(),
        );

  final List<String> ids;

  Set<String> get idSet => ids.toSet();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! CompoundNameLookupRequest || other.ids.length != ids.length) {
      return false;
    }
    for (var index = 0; index < ids.length; index += 1) {
      if (other.ids[index] != ids[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(ids);
}

/// The selected `Protocol Day` (defaults to today's local date). Doses are
/// grouped by their frozen local date.
final selectedProtocolDayProvider =
    NotifierProvider<SelectedProtocolDayController, ProtocolDayDate>(
  SelectedProtocolDayController.new,
);

class SelectedProtocolDayController extends Notifier<ProtocolDayDate> {
  @override
  ProtocolDayDate build() => ProtocolDayDate.fromDateTime(DateTime.now());

  void select(ProtocolDayDate localDate) {
    state = localDate;
  }

  void addDays(int days) {
    state = state.addDays(days);
  }
}

final protocolDayControllerProvider =
    StreamNotifierProvider<ProtocolDayController, ProtocolDayState>(
  ProtocolDayController.new,
);

/// The derived `Protocol Day` for the selected date. Nothing here is stored or
/// synced — the day-view is computed on read.
class ProtocolDayController extends StreamNotifier<ProtocolDayState> {
  @override
  Stream<ProtocolDayState> build() {
    final repository = ref.watch(protocolsRepositoryProvider);
    final selectedDate = ref.watch(selectedProtocolDayProvider);
    return repository.watchProtocolDay(selectedDate).map(
          (day) => ProtocolDayState(day: day),
        );
  }

  void selectProtocolDay(ProtocolDayDate localDate) {
    ref.read(selectedProtocolDayProvider.notifier).select(localDate);
  }

  /// Moves the selected `Protocol Day` back one day (date-header arrow/swipe
  /// navigation — mirrors `NutritionDayController.showPreviousDay`).
  void showPreviousDay() {
    ref.read(selectedProtocolDayProvider.notifier).addDays(-1);
  }

  /// Moves the selected `Protocol Day` forward one day.
  void showNextDay() {
    ref.read(selectedProtocolDayProvider.notifier).addDays(1);
  }

  /// Creates a `Compound` through the repository Activity Log write path.
  Future<CreateCompoundResult> createCompound(CompoundDraft draft) {
    return ref.read(protocolsRepositoryProvider).createCompound(draft);
  }

  /// Logs a `Dose` through the repository Activity Log write path. The Dose
  /// snapshots the Compound's name, captures its timezone, and freezes its
  /// local date at log time.
  Future<LogDoseResult> logDose(DoseSnapshotDraft draft) {
    return ref.read(protocolsRepositoryProvider).logDose(draft);
  }

  /// Idempotently loads the tiny OTC seed `Compound` library (PROTOCOLS.md §3),
  /// so the picker has neutral starter rows on a first run. Safe to call
  /// repeatedly — the seed skips Compounds already present (stable ids).
  Future<void> ensureOtcLibrarySeeded() {
    return ref.read(protocolsRepositoryProvider).ensureOtcLibrarySeeded();
  }

  /// Sets a Compound's favourites UI-affordance flag, hoisting it
  /// into the Compound list's virtual "Favorites" section.
  Future<void> setFavorite(String compoundId, {required bool isFavorite}) {
    return ref.read(protocolsRepositoryProvider).setFavorite(
          compoundId,
          isFavorite: isFavorite,
        );
  }

  /// Edits a logged `Dose` in place through the repository Activity Log write
  /// path ('s tap-to-edit). The Dose's already-frozen local date
  /// carries over untouched unless the caller explicitly overrides it
  /// (never re-derived from the device's current timezone).
  Future<String> editDose(String doseId, DoseSnapshotDraft draft) {
    return ref.read(protocolsRepositoryProvider).editDose(doseId, draft);
  }

  /// Deletes a logged `Dose` through the repository's tombstone + undo-
  /// recoverable Activity Log write path ('s tap-to-delete). Never
  /// cascades to the Compound.
  Future<String> deleteDose(String doseId) {
    return ref.read(protocolsRepositoryProvider).deleteDose(doseId);
  }

  /// The Compound's most recently logged Dose, DERIVED on read —
  /// seeds the ≤2-tap "prefill-from-last" Dose entry sheet (PROTOCOLS.md §5,
  ///). Null when the Compound has never been logged, so the caller
  /// falls back to its default unit/route.
  Future<DoseRecord?> lastDoseFor(String compoundId) {
    return ref.read(protocolsRepositoryProvider).lastDoseFor(compoundId);
  }
}

class ProtocolDayState {
  const ProtocolDayState({
    required this.day,
  });

  final ProtocolDayRecord day;
}
