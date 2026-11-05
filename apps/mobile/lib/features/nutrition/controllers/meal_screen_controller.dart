/// The Meal screen's state and writes (docs/designs/meal-logging.md §6).
///
/// Widgets -> [MealScreenController] -> [NutritionRepository]. Every user
/// action is one repository write, so one transaction and one Batch (§3);
/// the controller holds only what is not written yet (the pending Meal) and
/// which Meal the screen shows once it is.
///
/// Logging screens show nutrition only (§6): nothing here reads Dose,
/// Protocols or Workout data.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/nutrition/meal_type_proposal.dart';
import 'nutrition_day_controller.dart' show nutritionRepositoryProvider;

/// Which Meal screen to open (§6): a new Meal on [day], or the saved Meal
/// [mealId]. The key of [mealScreenControllerProvider].
@immutable
final class MealScreenArgs {
  /// A Meal not written yet, logged on [day]. A screen passes its own
  /// [instance], so it never shares a controller with another new Meal screen
  /// on that day, such as the last one while it is still closing.
  const MealScreenArgs.newMeal(NutritionDayDate this.day, {this.instance})
      : mealId = null;

  /// A saved Meal, opened from its card or the recent-Meal shortcut.
  const MealScreenArgs.existing(String this.mealId)
      : day = null,
        instance = null;

  /// The day a new Meal is logged on; null for [MealScreenArgs.existing].
  final NutritionDayDate? day;

  /// The saved Meal; null for [MealScreenArgs.newMeal].
  final String? mealId;

  /// Compared by identity; see [MealScreenArgs.newMeal].
  final Object? instance;

  bool get isNewMeal => mealId == null;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MealScreenArgs &&
            other.day == day &&
            other.mealId == mealId &&
            identical(other.instance, instance);
  }

  @override
  int get hashCode => Object.hash(day, mealId, identityHashCode(instance));

  @override
  String toString() => isNewMeal
      ? 'MealScreenArgs.newMeal($day)'
      : 'MealScreenArgs.existing($mealId)';
}

/// The clock the Meal screen reads "now" and "today" from: the proposal for
/// an unchosen time, the time-shift buttons, Meal History's window and the
/// recent-Meal shortcut. Overridden in tests, like `protocolsClockProvider`.
///
/// The repository never reads it: a Meal whose time the user didn't choose
/// is stored at the time of the write (§3).
final mealScreenClockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

/// Whether [day] is after the day [now] falls on. A Meal can't start in the
/// future (§8), so a future day offers no `Log meal` on the Nutrition Day
/// view and no Meal in Today's Log sheet. Callers pass "now" from
/// [mealScreenClockProvider].
bool isFutureNutritionDay(NutritionDayDate day, DateTime now) {
  return day.compareTo(NutritionDayDate.fromDateTime(now)) > 0;
}

/// The Meal screen controller, one per [MealScreenArgs] (§6).
final mealScreenControllerProvider = NotifierProvider.autoDispose
    .family<MealScreenController, MealScreenState, MealScreenArgs>(
  MealScreenController.new,
);

/// The saved Meal the screen shows, with its active Food Entries, following
/// it across Nutrition Days when its time moves (§6). Null once the Meal is
/// archived (Delete meal) or while it doesn't exist.
final savedMealProvider = StreamProvider.autoDispose
    .family<NutritionDayMealRecord?, String>((ref, mealId) {
  return ref.watch(nutritionRepositoryProvider).watchMeal(mealId);
});

/// Your meals (§5): read once when the screen opens. It shows only while the
/// Meal has no Food Entries, so it never needs to refresh after a write.
final mealHistoryProvider =
    FutureProvider.autoDispose<List<MealHistoryRecord>>((ref) {
  final clock = ref.read(mealScreenClockProvider);
  return ref
      .read(nutritionRepositoryProvider)
      .listMealHistory(now: clock(), limit: 20);
});

/// How long after a Meal's start the recent-Meal shortcut still offers it
/// (§6, Problem 6), inclusive.
const Duration recentMealShortcutWindow = Duration(minutes: 30);

/// The Meal the recent-Meal shortcut offers (`Add to <time> · <type>`, §6),
/// or null. Read once, and only for a new Meal on today: a saved Meal or
/// another day never offers it.
final recentMealShortcutProvider = FutureProvider.autoDispose
    .family<NutritionDayMealRecord?, MealScreenArgs>((ref, args) async {
  final day = args.day;
  if (day == null) {
    return null;
  }
  final now = ref.read(mealScreenClockProvider)();
  if (day != NutritionDayDate.fromDateTime(now)) {
    return null;
  }
  final nutritionDay =
      await ref.read(nutritionRepositoryProvider).nutritionDay(day);
  return eligibleRecentMeal(nutritionDay.meals, now: now);
});

/// The most recent Meal in [meals] that the recent-Meal shortcut may offer
/// at [now] (§6): an active `instant` Meal, with or without Food Entries,
/// whose start is between 0 and [recentMealShortcutWindow] before [now],
/// inclusive. A `date` Meal has no clock time and never qualifies; neither
/// does a start in the future. Ties on the start break by the larger id.
NutritionDayMealRecord? eligibleRecentMeal(
  Iterable<NutritionDayMealRecord> meals, {
  required DateTime now,
}) {
  NutritionDayMealRecord? best;
  for (final candidate in meals) {
    final meal = candidate.meal;
    if (meal.deletedAt != null ||
        meal.timePrecision != MealTimePrecision.instant) {
      continue;
    }
    final age = now.difference(meal.startedAt);
    if (age.isNegative || age > recentMealShortcutWindow) {
      continue;
    }
    final current = best?.meal;
    if (current == null ||
        meal.startedAt.isAfter(current.startedAt) ||
        (meal.startedAt.isAtSameMomentAs(current.startedAt) &&
            meal.id.compareTo(current.id) > 0)) {
      best = candidate;
    }
  }
  return best;
}

/// The Meal screen's state (§6). Immutable; the controller replaces it.
@immutable
final class MealScreenState {
  const MealScreenState({
    required this.day,
    required this.pendingMealId,
    required this.pendingStart,
    required this.pendingMealType,
    required this.timeChosen,
    required this.savedMealId,
    required this.firstBatchId,
    required this.writing,
  });

  /// The day a new Meal screen opened for; null for a screen opened on a
  /// saved Meal, which reads its day from the Meal itself.
  final NutritionDayDate? day;

  /// The id the first write creates the Meal with, minted by
  /// `NutritionRepository.newMealId` when the screen opens, so a repeated
  /// write of it is a double tap (§3). Null on a screen opened on a saved
  /// Meal.
  final String? pendingMealId;

  /// The chosen local clock time of the pending Meal; null means now, which
  /// the repository resolves at the write (§3).
  final DateTime? pendingStart;

  /// The hand-picked Meal Type of the pending Meal; null means proposed from
  /// its time, which the repository resolves at the write (§4).
  final String? pendingMealType;

  /// Whether the pending Meal has a time: true on today (`now` is a
  /// proposal), false on another day until the user chooses one (CUJ 5).
  final bool timeChosen;

  /// The Meal every write lands in once it is written; null while the screen
  /// holds a pending Meal, which the first write creates (§6).
  final String? savedMealId;

  /// The Batch that created the Meal on a new screen. Undoing it returns the
  /// screen to a new Meal (§6). Null otherwise.
  final String? firstBatchId;

  /// A write is in flight; further writes are ignored until it settles (a
  /// double tap, §3).
  final bool writing;

  /// Whether the screen's Meal is written yet (§6).
  bool get isSaved => savedMealId != null;

  /// Whether a pick (a food, Your meals, `Add foods later`) may write: false
  /// on a new Meal on another day until a time is chosen (§6, CUJ 5).
  bool get canPick => isSaved || timeChosen;

  /// The Meal the next write lands in (§3): the pending Meal while new, the
  /// saved one after. Null fields of the pending Meal stay null, so the
  /// repository resolves now and the proposal at the write.
  MealTarget get target {
    if (savedMealId case final mealId?) {
      return ExistingMealTarget(mealId);
    }
    return NewMealTarget(
      PendingMeal(
        id: pendingMealId!,
        startedAt: pendingStart,
        mealTypeName: pendingMealType,
      ),
    );
  }

  MealScreenState copyWith({
    DateTime? Function()? pendingStart,
    String? Function()? pendingMealType,
    bool? timeChosen,
    bool? writing,
  }) {
    return MealScreenState(
      day: day,
      pendingMealId: pendingMealId,
      pendingStart: pendingStart == null ? this.pendingStart : pendingStart(),
      pendingMealType:
          pendingMealType == null ? this.pendingMealType : pendingMealType(),
      timeChosen: timeChosen ?? this.timeChosen,
      savedMealId: savedMealId,
      firstBatchId: firstBatchId,
      writing: writing ?? this.writing,
    );
  }

  /// This state once [mealId] is written. [firstBatchId] is kept from a
  /// screen already saved, and taken from [batchId] by the write that saves
  /// a new one.
  MealScreenState saved(String mealId, {String? batchId}) {
    return MealScreenState(
      day: day,
      pendingMealId: pendingMealId,
      pendingStart: pendingStart,
      pendingMealType: pendingMealType,
      timeChosen: timeChosen,
      savedMealId: mealId,
      firstBatchId: isSaved ? firstBatchId : batchId,
      writing: writing,
    );
  }

  /// A new Meal again, with the fresh [mealId] (after its first Batch was
  /// undone, §6). The user's pending choices stay.
  MealScreenState pending(String mealId) {
    return MealScreenState(
      day: day,
      pendingMealId: mealId,
      pendingStart: pendingStart,
      pendingMealType: pendingMealType,
      timeChosen: timeChosen,
      savedMealId: null,
      firstBatchId: null,
      writing: writing,
    );
  }
}

/// Drives one Meal screen (§6): holds the pending Meal until the first
/// write, then follows the saved Meal, and turns each user action into one
/// repository write (§3).
///
/// - Every write uses the current [MealScreenState.target], and switches the
///   state to saved with the Meal it landed in.
/// - A write while another is in flight is ignored and returns null (a double
///   tap, §3). A [MealAlreadyExistsException] means the pending Meal is
///   already written, so the state switches to saved with that id instead.
/// - What the user didn't choose is sent as null, so the repository resolves
///   now and the proposed Meal Type at the write (§3, §4). Once the Meal is
///   saved the proposal is never recomputed: its type is a stored label.
class MealScreenController extends Notifier<MealScreenState> {
  MealScreenController(this.args);

  final MealScreenArgs args;

  NutritionRepository get _repository => ref.read(nutritionRepositoryProvider);

  DateTime Function() get _clock => ref.read(mealScreenClockProvider);

  @override
  MealScreenState build() {
    final mealId = args.mealId;
    if (mealId != null) {
      return MealScreenState(
        day: null,
        pendingMealId: null,
        pendingStart: null,
        pendingMealType: null,
        timeChosen: true,
        savedMealId: mealId,
        firstBatchId: null,
        writing: false,
      );
    }
    final day = args.day!;
    return MealScreenState(
      day: day,
      pendingMealId: _repository.newMealId(),
      pendingStart: null,
      pendingMealType: null,
      timeChosen: day == NutritionDayDate.fromDateTime(_clock()),
      savedMealId: null,
      firstBatchId: null,
      writing: false,
    );
  }

  /// Whether a new Meal screen opened for today, where the time-shift
  /// buttons and the recent-Meal shortcut show (§6). False on a screen
  /// opened on a saved Meal, which reads its day from the Meal.
  bool get isToday {
    final day = state.day;
    return day != null && day == NutritionDayDate.fromDateTime(_clock());
  }

  /// The Meal Type the header proposes for the pending Meal (§4): at its
  /// chosen clock time, or now. Display only: the write sends null and the
  /// repository proposes again at the stored time, so what is stored matches
  /// what the header showed for a chosen time.
  String proposedMealType(List<MealTypeRecord> mealTypes) {
    return proposeMealType(state.pendingStart ?? _clock(), mealTypes);
  }

  /// Sets the pending Meal's local clock time (the time sheet on a new Meal:
  /// a picked time, or a time-shift button's now minus its amount, §6).
  void setPendingTime(DateTime localClock) {
    _requireNew('setPendingTime');
    state = state.copyWith(
      pendingStart: () => localClock,
      timeChosen: true,
    );
  }

  /// Hand-picks the pending Meal's Meal Type; the proposal no longer applies.
  void setPendingMealType(String mealTypeName) {
    _requireNew('setPendingMealType');
    state = state.copyWith(pendingMealType: () => mealTypeName);
  }

  /// Moves the saved Meal to [instant]: one `updateMealTime` (§1). Its Meal
  /// Type stays as stored. Returns the Batch id, or null if ignored.
  Future<String?> changeTime(DateTime instant) {
    final mealId = _requireSavedMealId('changeTime');
    return _write(
      () => _repository.updateMealTime(mealId, instant),
      mealIdOf: (_) => mealId,
      batchIdOf: (batchId) => batchId,
    );
  }

  /// Stores [mealTypeName] on the saved Meal: one `updateMealType`. Returns
  /// the Batch id, or null if ignored.
  Future<String?> changeType(String mealTypeName) {
    final mealId = _requireSavedMealId('changeType');
    return _write(
      () => _repository.updateMealType(mealId, mealTypeName),
      mealIdOf: (_) => mealId,
      batchIdOf: (batchId) => batchId,
    );
  }

  /// A Your meals row (Log again, §5): copies [record]'s most recent Meal
  /// into this one, in one Batch.
  Future<LogMealAgainResult?> logAgain(MealHistoryRecord record) {
    final target = state.target;
    return _write(
      () => _repository.logMealAgain(record.lastMealId, target),
      mealIdOf: (result) => result.mealId,
      batchIdOf: (result) => result.batchId,
    );
  }

  /// `Add foods later` (§2): writes the pending Meal with no Food Entries.
  /// Returns the Meal id, or null if ignored.
  Future<String?> addFoodsLater() {
    _requireNew('addFoodsLater');
    final target = state.target as NewMealTarget;
    return _write(
      () => _repository.createMeal(target.meal),
      mealIdOf: (mealId) => mealId,
      batchIdOf: (_) => null,
    );
  }

  /// Save on the Portion screen. [entry] lands in the Meal the screen holds
  /// now: Log Portion built it for the target when it opened, and undoing the
  /// first Batch since then gave the screen a new Meal.
  Future<LogFoodEntryResult?> logFoodSnapshot(FoodEntrySnapshotDraft entry) {
    final target = state.target;
    return _write(
      () => _repository.logFoodEntrySnapshot(
        target: target,
        entry: entry.forMeal(target.mealId),
      ),
      mealIdOf: (result) => result.mealId,
      batchIdOf: (result) => result.batchId,
    );
  }

  /// A Quick Entry into this Meal.
  Future<LogQuickEntryResult?> logQuickEntry(QuickFoodEntryDraft entry) {
    final target = state.target;
    return _write(
      () => _repository.logQuickEntry(target: target, entry: entry),
      mealIdOf: (result) => result.mealId,
      batchIdOf: (result) => result.batchId,
    );
  }

  /// Removes one Food Entry. Removing the last one keeps the Meal (§2).
  /// Returns the Batch id, or null if ignored: the in-flight guard clears
  /// before [savedMealProvider] drops the row, so a double tap can ask to
  /// remove an entry that is already gone.
  Future<String?> removeEntry(String foodEntryId) {
    final mealId = _requireSavedMealId('removeEntry');
    return _write<String?>(
      () async {
        final entry = await _repository.getFoodEntryById(foodEntryId);
        if (entry == null || entry.deletedAt != null) {
          return null;
        }
        return _repository.deleteFoodEntry(foodEntryId);
      },
      mealIdOf: (_) => mealId,
      batchIdOf: (batchId) => batchId,
    );
  }

  /// Changes one Food-backed entry's Portion.
  Future<LogFoodEntryResult?> updatePortion(
    String foodEntryId,
    Portion portion,
  ) {
    _requireSavedMealId('updatePortion');
    return _write(
      () => _repository.updateFoodEntryPortion(
        id: foodEntryId,
        portion: portion,
      ),
      mealIdOf: (result) => result.mealId,
      batchIdOf: (result) => result.batchId,
    );
  }

  /// Delete meal: archives the Meal and its Food Entries in one Batch, so
  /// one undo restores all of it. Returns the Batch id, or null if ignored.
  Future<String?> deleteMeal() {
    final mealId = _requireSavedMealId('deleteMeal');
    return _write(
      () => _repository.deleteMeal(mealId),
      mealIdOf: (_) => mealId,
      batchIdOf: (batchId) => batchId,
    );
  }

  /// Undoes [batchId] from the Undo bar. Undoing the Batch that created this
  /// screen's Meal returns the screen to a new Meal with a fresh pending id:
  /// the old id now exists, archived, so reusing it would be a double tap
  /// (§6). A refused undo (§7) changes nothing; the caller shows
  /// `undoConflictMessage`. Returns null if ignored.
  Future<ActivityLogUndoResult?> undo(String batchId) async {
    if (state.writing) {
      return null;
    }
    state = state.copyWith(writing: true);
    try {
      final result = await ref
          .read(trainingRepositoriesProvider)
          .activityLog
          .undoBatch(batchId);
      if (!ref.mounted) {
        return result;
      }
      if (!result.hasConflicts &&
          state.firstBatchId != null &&
          state.firstBatchId == batchId) {
        state = state.pending(_repository.newMealId());
      }
      return result;
    } finally {
      if (ref.mounted) {
        state = state.copyWith(writing: false);
      }
    }
  }

  /// Runs one write under the in-flight guard and switches to saved with the
  /// Meal it landed in.
  Future<T?> _write<T>(
    Future<T> Function() write, {
    required String Function(T result) mealIdOf,
    required String? Function(T result) batchIdOf,
  }) async {
    if (state.writing) {
      return null;
    }
    state = state.copyWith(writing: true);
    try {
      final result = await write();
      if (ref.mounted) {
        state = state.saved(mealIdOf(result), batchId: batchIdOf(result));
      }
      return result;
    } on MealAlreadyExistsException catch (error) {
      // The pending Meal is already written (a double tap that got past the
      // guard, or a write that committed before the screen saw it): show it.
      if (ref.mounted) {
        state = state.saved(error.mealId);
      }
      return null;
    } finally {
      if (ref.mounted) {
        state = state.copyWith(writing: false);
      }
    }
  }

  void _requireNew(String action) {
    if (state.isSaved) {
      throw StateError('$action applies to a Meal not written yet.');
    }
  }

  String _requireSavedMealId(String action) {
    if (state.savedMealId case final mealId?) {
      return mealId;
    }
    throw StateError('$action applies to a saved Meal.');
  }
}
