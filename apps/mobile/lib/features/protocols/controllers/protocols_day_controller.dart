import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/protocols/protocol_plan_days.dart'
    show DueUnfilledDose, dueUnfilled;

/// The Protocols repository provider, mirroring `nutritionRepositoryProvider`.
/// Widgets -> this controller -> the repository (the only layer touching Drift).
final protocolsRepositoryProvider = Provider<ProtocolsRepository>((ref) {
  return ref.watch(trainingRepositoriesProvider).protocols;
});

/// The Planned list's read path (D6), reached like [protocolsRepositoryProvider].
final protocolPlanRepositoryProvider = Provider<ProtocolPlanRepository>((ref) {
  return ref.watch(trainingRepositoriesProvider).protocolPlan;
});

/// The clock the Protocols logging surfaces read "now" and "today" from: the
/// selected Protocol Day's default, the log sheet's time default, and "Log
/// all planned". Overridden in tests, like `syncNowProvider`.
final protocolsClockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
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

/// Active `Compound` schedule options for Protocol plan editors: identity plus
/// default unit/route for optional Schedule seed values.
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

/// The `Compound`s a Protocol editor's members name, archived ones included
/// with `isArchived` set: a Protocol keeps a member whose Compound was archived,
/// and the editor still names it (D4).
final compoundsByIdsProvider = StreamProvider.autoDispose
    .family<List<CompoundScheduleOptionRecord>, CompoundNameLookupRequest>(
  (ref, request) {
    return ref
        .watch(protocolsRepositoryProvider)
        .watchCompoundsByIds(request.idSet);
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
  ProtocolDayDate build() =>
      ProtocolDayDate.fromDateTime(ref.watch(protocolsClockProvider)());

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

/// The derived `Protocol Day` for the selected date, with its Planned list
/// (D6). Nothing here is stored or synced — the day-view is computed on read.
class ProtocolDayController extends StreamNotifier<ProtocolDayState> {
  /// The local date this build read as today. Day Statuses, row labels and
  /// "Log all planned" all depend on it, so [refreshIfDayChanged] rebuilds
  /// when the clock has moved past it.
  ProtocolDayDate? _today;

  /// The "Log all planned" call in flight, shared by any tap made before it
  /// finishes, so a double tap cannot log the same due doses twice.
  Future<List<LogDoseResult>>? _logAllPlannedInFlight;

  @override
  Stream<ProtocolDayState> build() {
    final planRepository = ref.watch(protocolPlanRepositoryProvider);
    final selectedDate = ref.watch(selectedProtocolDayProvider);
    final today = _today =
        ProtocolDayDate.fromDateTime(ref.read(protocolsClockProvider)());
    // One stream carries the day's Doses and the Planned list matched
    // against them, so the log and the rows always come from one read.
    return planRepository.watchPlannedDay(selectedDate, today: today).map(
          (planned) => ProtocolDayState(day: planned.day, plannedDay: planned),
        );
  }

  /// Rebuilds the day when the local date has moved past the one this build
  /// read as today (local midnight, or a resume on a later day). Without it
  /// the view would keep labelling yesterday as today: "Pending" rows and a
  /// "Log all planned" button on a past day. The selected Protocol Day is
  /// left as it is.
  void refreshIfDayChanged() {
    final today = _today;
    final now =
        ProtocolDayDate.fromDateTime(ref.read(protocolsClockProvider)());
    if (today != null && now != today) {
      ref.invalidateSelf();
    }
  }

  /// "Log all planned" (D6): logs every due unfilled planned dose of today,
  /// timed ones whose time is at or before now and untimed ones, as picked
  /// by the shared core's `dueUnfilled`. Each Dose takes its row's planned
  /// amount, unit and route, is tagged with its row's Protocol, and is timed
  /// now. All of them go through ONE `ProtocolsRepository.logDoses` call: one
  /// transaction and one Batch, so a kill mid-write leaves all or none.
  ///
  /// Reads today's plan afresh rather than the rendered state, so it acts on
  /// what is stored at the moment of the tap, whatever day is selected.
  /// Returns the logged results, empty when nothing was due. A call made
  /// while another is in flight shares it rather than reading the plan
  /// again before the first one's Batch is written.
  Future<List<LogDoseResult>> logAllPlanned() {
    return _logAllPlannedInFlight ??= _logAllPlanned().whenComplete(() {
      _logAllPlannedInFlight = null;
    });
  }

  Future<List<LogDoseResult>> _logAllPlanned() async {
    final now = ref.read(protocolsClockProvider)();
    final today = ProtocolDayDate.fromDateTime(now);
    final plannedDay = await ref
        .read(protocolPlanRepositoryProvider)
        .plannedDay(today, today: today);
    final local = now.toLocal();
    final due = dueUnfilled(
      plannedDay.dayStatuses,
      today,
      planLocalTime(local.hour, local.minute),
    );
    if (due.isEmpty) {
      return const <LogDoseResult>[];
    }
    final drafts = <DoseSnapshotDraft>[
      for (final row in due) _plannedDoseDraft(plannedDay, row, now),
    ];
    return ref.read(protocolsRepositoryProvider).logDoses(drafts);
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

  /// Edits a `Compound` through the repository Activity Log write path.
  /// Returns the Batch id, or null when the draft changes nothing, which
  /// writes nothing.
  Future<String?> editCompound(String compoundId, CompoundDraft draft) {
    return ref
        .read(protocolsRepositoryProvider)
        .editCompound(compoundId, draft);
  }

  /// Archives a `Compound`. It cascades nothing: a Protocol keeps it as a
  /// member, and its logged Doses stay. Returns the Batch id.
  Future<String> archiveCompound(String compoundId) {
    return ref.read(protocolsRepositoryProvider).archiveCompound(compoundId);
  }

  /// How many active Protocols hold [compoundId] as a live member, for the
  /// archive confirmation (D4).
  Future<int> countProtocolsWithCompound(String compoundId) async {
    final summaries =
        await ref.read(protocolsRepositoryProvider).listProtocolSummaries();
    return summaries
        .where((summary) => summary.compoundIds.contains(compoundId))
        .length;
  }

  /// Logs a `Dose` through the repository Activity Log write path. The Dose
  /// snapshots the Compound's name, captures its timezone, and freezes its
  /// local date at log time.
  ///
  /// With [unskipId] (Save from a "Skipped" row, D8 and CUJ 16), the same
  /// transaction and Batch also removes that Skip, so the row reads "Logged"
  /// with no stray Skip behind it.
  Future<LogDoseResult> logDose(DoseSnapshotDraft draft, {String? unskipId}) {
    return ref
        .read(protocolsRepositoryProvider)
        .logDose(draft, unskipId: unskipId);
  }

  /// Skips the planned dose [target] names (D8, CUJ 15 and 17): writes a Skip
  /// for its own Protocol, Compound, date and planned time, never the log
  /// sheet's fields. "Today" is the Protocols clock's, so the repository's
  /// `skip_future` check reads the same day the view labels. Returns the
  /// Batch id.
  Future<String> skipPlannedDose(PlannedDoseTarget target) {
    final today =
        ProtocolDayDate.fromDateTime(ref.read(protocolsClockProvider)());
    return ref.read(protocolsRepositoryProvider).skipPlannedDose(
          ProtocolSkipDraft(
            protocolId: target.protocolId,
            compoundId: target.compoundId,
            localDate: target.localDate,
            plannedLocalTime: target.plannedLocalTime,
          ),
          today: today,
        );
  }

  /// Removes a Skip (D8's Undo skip). A timed Skip's siblings with the same
  /// Protocol, Compound, date and time go in the same Batch, so the row reads
  /// "Pending" or "Not logged" again. Returns the Batch id.
  Future<String> unskipPlannedDose(String skipId) {
    return ref.read(protocolsRepositoryProvider).unskipPlannedDose(skipId);
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

  /// Each of [compoundIds]' most recently logged amount and unit, DERIVED on
  /// read from [lastDoseFor]. An id with no Dose has no entry.
  Future<Map<String, ({double amount, DoseUnit unit})>> latestDoseAmounts(
    Set<String> compoundIds,
  ) async {
    final amounts = <String, ({double amount, DoseUnit unit})>{};
    for (final compoundId in compoundIds) {
      final dose = await lastDoseFor(compoundId);
      if (dose != null) {
        amounts[compoundId] = (amount: dose.amountValue, unit: dose.unit);
      }
    }
    return amounts;
  }
}

/// One "Log all planned" row as a Dose draft. A planned dose's amount, unit
/// and route are all present (D7 `amount_required`), and its Compound is a
/// member row's live reference, so a missing one is a broken invariant: it
/// throws before anything is written rather than logging a partial Batch.
DoseSnapshotDraft _plannedDoseDraft(
  PlannedDay plannedDay,
  DueUnfilledDose row,
  DateTime now,
) {
  final compound = plannedDay.compounds[row.compoundId];
  final amount = row.amount;
  final amountValue = amount.amountValue;
  final amountEntered = amount.amountEntered;
  final unit = amount.unit;
  final route = amount.route;
  if (compound == null ||
      amountValue == null ||
      amountEntered == null ||
      unit == null ||
      route == null) {
    throw StateError(
      'Planned dose ${row.compoundId}#${row.slot} has no Compound or amount.',
    );
  }
  return DoseSnapshotDraft.fromCompound(
    compound: compound,
    amountValue: amountValue,
    amountEntered: amountEntered,
    unit: unit,
    route: route,
    tookAt: now,
    protocol: plannedDay.protocols[row.protocolId] ??
        (throw StateError('Planned dose has no Protocol ${row.protocolId}.')),
  );
}

/// The planned dose a Planned list row names (D8): what the log sheet's Skip
/// writes and Undo skip removes. A Skip names its planned dose by Protocol,
/// Compound, date and planned time, never by slot number, because slot
/// numbers shift when another Protocol's plan for the Compound changes.
/// [skipId] is the Skip marking the row, or null when the row isn't
/// "Skipped".
final class PlannedDoseTarget {
  const PlannedDoseTarget({
    required this.protocolId,
    required this.compoundId,
    required this.localDate,
    required this.plannedLocalTime,
    this.skipId,
  });

  /// The target of [row], on [localDate].
  factory PlannedDoseTarget.fromRow(PlannedRow row, ProtocolDayDate localDate) {
    return PlannedDoseTarget(
      protocolId: row.protocolId,
      compoundId: row.compoundId,
      localDate: localDate,
      plannedLocalTime: row.plannedLocalTime,
      skipId: row.skipId,
    );
  }

  final String protocolId;
  final String compoundId;
  final ProtocolDayDate localDate;

  /// The planned `HH:MM` time, or null for an untimed planned dose.
  final String? plannedLocalTime;
  final String? skipId;
}

class ProtocolDayState {
  const ProtocolDayState({
    required this.day,
    this.plannedDay,
  });

  final ProtocolDayRecord day;

  /// The day's Planned list (D6), or null when no plan has been read.
  final PlannedDay? plannedDay;
}
