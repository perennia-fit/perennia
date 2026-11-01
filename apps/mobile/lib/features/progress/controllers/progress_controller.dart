import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/training/training_day.dart';
import '../../../domain/training/training_progress.dart';
import '../../protocols/controllers/protocols_lock_controller.dart';
import '../../settings/repositories/settings_repository.dart';
import '../repositories/progress_feature_repository.dart';

/// The instant Progress reads "now" from. Tests override it with a fixed
/// instant.
final progressClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Today's local date for Progress Overview (D8). No other provider tracks
/// the current date (Today's selected day is set once), so this one moves on
/// by itself: when the app resumes, and at the next local midnight, so a
/// screen left open overnight shows the new day.
final progressTodayProvider =
    NotifierProvider.autoDispose<ProgressTodayController, TrainingDayDate>(
  ProgressTodayController.new,
);

class ProgressTodayController extends Notifier<TrainingDayDate> {
  Timer? _midnight;

  @override
  TrainingDayDate build() {
    final clock = ref.watch(progressClockProvider);
    final lifecycle = AppLifecycleListener(onResume: () => _refresh(clock));
    ref.onDispose(() {
      lifecycle.dispose();
      _midnight?.cancel();
    });
    return _read(clock);
  }

  TrainingDayDate _read(DateTime Function() clock) {
    final now = clock();
    _midnight?.cancel();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(nextMidnight.difference(now), () => _refresh(clock));
    return TrainingDayDate.fromDateTime(now);
  }

  void _refresh(DateTime Function() clock) {
    final today = _read(clock);
    if (today != state) {
      state = today;
    }
  }
}

/// The period every card except This week covers. Not persisted (D8).
enum ProgressPeriod {
  weeks4(4),
  weeks12(12),
  year(52);

  const ProgressPeriod(this.weeks);

  final int weeks;
}

/// The chosen period. Not `autoDispose`, so the choice survives switching
/// away from Progress until the app restarts.
final progressPeriodProvider =
    NotifierProvider<ProgressPeriodController, ProgressPeriod>(
  ProgressPeriodController.new,
);

class ProgressPeriodController extends Notifier<ProgressPeriod> {
  @override
  ProgressPeriod build() => ProgressPeriod.weeks12;

  void select(ProgressPeriod period) {
    state = period;
  }
}

/// The dates the cards cover: [from] is the start of the week `weeks - 1`
/// weeks before the current one, and [to] the end of the current week, so
/// future dates of this week are part of the period and shown empty.
final class ProgressRange {
  const ProgressRange({
    required this.period,
    required this.today,
    required this.weekStart,
    required this.firstWeekStart,
    required this.from,
    required this.to,
  });

  final ProgressPeriod period;
  final TrainingDayDate today;

  /// The first date of the current week, by `weekStartDay`.
  final TrainingDayDate weekStart;

  /// The first date of the period's first week; the same date as [from].
  final TrainingDayDate firstWeekStart;
  final TrainingDayDate from;
  final TrainingDayDate to;
}

/// The settings Progress reads, or null while they load. A failed load
/// reads as the defaults, as Home's does.
final _progressSettingsProvider = Provider.autoDispose<AppSettings?>((ref) {
  final settings = ref.watch(settingsControllerProvider);
  return settings.value ?? (settings.hasError ? AppSettings.defaults : null);
});

/// The period's dates, or null until the settings have loaded: the week
/// start comes from them, and the Protocols card must not guess
/// `showProtocolsOnToday`.
final progressRangeProvider = Provider.autoDispose<ProgressRange?>((ref) {
  final settings = ref.watch(_progressSettingsProvider);
  if (settings == null) {
    return null;
  }
  final today = ref.watch(progressTodayProvider);
  final period = ref.watch(progressPeriodProvider);
  final weekStart = settings.weekStartFor(today);
  final firstWeekStart = weekStart.addDays(-7 * (period.weeks - 1));
  return ProgressRange(
    period: period,
    today: today,
    weekStart: weekStart,
    firstWeekStart: firstWeekStart,
    from: firstWeekStart,
    to: weekStart.addDays(6),
  );
});

// One stream provider per repository stream. The ranged ones are families
// keyed by their dates, so a new period starts loading instead of showing the
// previous period's rows for a frame.

final progressWeeklyPlansProvider =
    StreamProvider.autoDispose<List<WeeklyPlanFacts>>((ref) {
  return ref.watch(progressFeatureRepositoryProvider).watchWeeklyPlans();
});

final progressHasRotatingRoutineProvider =
    StreamProvider.autoDispose<bool>((ref) {
  return ref.watch(progressFeatureRepositoryProvider).watchHasRotatingRoutine();
});

final progressWorkoutsProvider = StreamProvider.autoDispose
    .family<List<ProgressWorkout>, (TrainingDayDate, TrainingDayDate)>(
  (ref, range) {
    return ref
        .watch(progressFeatureRepositoryProvider)
        .watchProgressWorkoutsBetween(range.$1, range.$2);
  },
);

final progressFocusesByIdProvider =
    StreamProvider.autoDispose<Map<String, FocusRecord>>((ref) {
  return ref.watch(progressFeatureRepositoryProvider).watchFocusesById();
});

final progressConsistencySummaryProvider = StreamProvider.autoDispose.family<
    List<CompoundConsistencySummary>,
    (TrainingDayDate, TrainingDayDate, TrainingDayDate)>(
  (ref, range) {
    return ref.watch(progressFeatureRepositoryProvider).watchConsistencySummary(
          range.$1,
          range.$2,
          today: range.$3,
        );
  },
);

/// This week against the weekly Routines (D1), with what the card says
/// around it.
final class ProgressThisWeek {
  const ProgressThisWeek({
    required this.week,
    required this.counts,
    required this.comparedRoutineNames,
    required this.hasRotatingRoutine,
    required this.today,
  });

  final TrainingWeek week;
  final TrainingWeekCounts counts;

  /// The compared Routines' names, ordered by name, case-insensitive.
  final List<String> comparedRoutineNames;
  final bool hasRotatingRoutine;
  final TrainingDayDate today;

  /// Nothing to compare and nothing logged: the card's empty state.
  bool get isEmpty =>
      comparedRoutineNames.isEmpty &&
      !hasRotatingRoutine &&
      week.days.every((day) => day.workoutCount == 0);
}

/// The period's Trained Days (D2).
final class ProgressTrainedDays {
  const ProgressTrainedDays({
    required this.range,
    required this.days,
    required this.trainedDayCount,
  });

  final ProgressRange range;

  /// One entry per date of the period, ascending.
  final List<TrainingDay> days;

  /// Dates up to today with at least one Logged Workout.
  final int trainedDayCount;

  bool isTrained(TrainingDay day) => _isTrainedDay(day, range.today);
}

/// A Trained Day of the period: a date up to [today] with a Logged Workout.
bool _isTrainedDay(TrainingDay day, TrainingDayDate today) =>
    day.workoutCount > 0 && day.localDate.compareTo(today) <= 0;

/// Weekly time per Focus over the period (D3).
final class ProgressFocusTime {
  const ProgressFocusTime({
    required this.weeks,
    required this.keys,
    required this.focusesById,
  });

  /// One bucket per week of the period, the current week last.
  final List<WeeklyFocusSeconds> weeks;

  /// Every Focus id (or [noFocusKey]) with time in the period, in Focus sort
  /// order, ids with no Focus row after them, and [noFocusKey] last.
  final List<String> keys;
  final Map<String, FocusRecord> focusesById;

  /// No finished Logged Workout in the period: the card's empty state.
  bool get isEmpty => keys.isEmpty;

  WeeklyFocusSeconds get currentWeek => weeks.last;
}

/// One Compound's counted Day Statuses in the period (D7).
sealed class ProgressProtocols {
  const ProgressProtocols();
}

/// A lock is set and locked: only the lock row shows.
final class ProgressProtocolsLocked extends ProgressProtocols {
  const ProgressProtocolsLocked();
}

/// The lock state cannot be read: the card fails closed.
final class ProgressProtocolsUnavailable extends ProgressProtocols {
  const ProgressProtocolsUnavailable();
}

final class ProgressProtocolsRows extends ProgressProtocols {
  const ProgressProtocolsRows({required this.rows, required this.lockSet});

  final List<CompoundConsistencySummary> rows;

  /// Whether a lock is set (and unlocked). With no rows the card then stays,
  /// so unlocking never reveals whether Protocols exist.
  final bool lockSet;
}

final progressThisWeekProvider =
    Provider.autoDispose<AsyncValue<ProgressThisWeek>>((ref) {
  final range = ref.watch(progressRangeProvider);
  if (range == null) {
    return const AsyncLoading<ProgressThisWeek>();
  }
  final plans = ref.watch(progressWeeklyPlansProvider);
  final rotating = ref.watch(progressHasRotatingRoutineProvider);
  final workouts = ref.watch(progressWorkoutsProvider((range.from, range.to)));
  return _whenAll(
    <AsyncValue<Object?>>[plans, rotating, workouts],
    'progress.thisWeek',
    () {
      final facts = plans.requireValue;
      final week = trainingWeek(
        plans: facts.map((plan) => plan.toWeeklyPlan()),
        workouts: workouts.requireValue,
        weekStart: range.weekStart,
        today: range.today,
      );
      final compared = week.comparedRoutineIds.toSet();
      final names = <String>[
        for (final plan in facts)
          if (compared.contains(plan.routineId)) plan.routineName,
      ]..sort(
          (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
        );
      return ProgressThisWeek(
        week: week,
        counts: summarizeTrainingWeek(week.days),
        comparedRoutineNames: names,
        hasRotatingRoutine: rotating.requireValue,
        today: range.today,
      );
    },
  );
});

final progressTrainedDaysProvider =
    Provider.autoDispose<AsyncValue<ProgressTrainedDays>>((ref) {
  final range = ref.watch(progressRangeProvider);
  if (range == null) {
    return const AsyncLoading<ProgressTrainedDays>();
  }
  final workouts = ref.watch(progressWorkoutsProvider((range.from, range.to)));
  return _whenAll(
    <AsyncValue<Object?>>[workouts],
    'progress.trainedDays',
    () {
      final days = trainingDays(
        workouts: workouts.requireValue,
        from: range.from,
        to: range.to,
      );
      return ProgressTrainedDays(
        range: range,
        days: days,
        trainedDayCount:
            days.where((day) => _isTrainedDay(day, range.today)).length,
      );
    },
  );
});

/// Reads the period's [TrainingDay]s from [progressTrainedDaysProvider], so
/// `trainingDays` runs once per Workouts change for both cards.
final progressFocusTimeProvider =
    Provider.autoDispose<AsyncValue<ProgressFocusTime>>((ref) {
  final trained = ref.watch(progressTrainedDaysProvider);
  final focuses = ref.watch(progressFocusesByIdProvider);
  return _whenAll(
    <AsyncValue<Object?>>[trained, focuses],
    'progress.focusTime',
    () {
      final ProgressTrainedDays(:days, :range) = trained.requireValue;
      final focusesById = focuses.requireValue;
      final keys = <String>{
        for (final day in days) ...day.secondsByFocus.keys,
      }.toList()
        ..sort((a, b) => _compareFocusKeys(a, b, focusesById));
      return ProgressFocusTime(
        weeks: weeklyFocusSeconds(days, range.firstWeekStart),
        keys: keys,
        focusesById: focusesById,
      );
    },
  );
});

/// Focus sort order, then id; ids with no Focus row on this device yet (not
/// pulled) after every known Focus; "No Focus" last.
int _compareFocusKeys(
  String a,
  String b,
  Map<String, FocusRecord> focusesById,
) {
  int rank(String key) {
    if (key == noFocusKey) return 2;
    return focusesById.containsKey(key) ? 0 : 1;
  }

  final byRank = rank(a).compareTo(rank(b));
  if (byRank != 0) {
    return byRank;
  }
  final focusA = focusesById[a];
  final focusB = focusesById[b];
  if (focusA != null && focusB != null) {
    final byOrder = focusA.sortOrder.compareTo(focusB.sortOrder);
    if (byOrder != 0) {
      return byOrder;
    }
  }
  return a.compareTo(b);
}

/// The Protocols card's state (D7): data null means the card is absent, and
/// loading renders nothing, because the card may turn out absent. The lock
/// is read on every build and before any summary, so no Compound is loaded
/// for the card while Protocols are locked, and an error fails closed.
final progressProtocolsProvider =
    Provider.autoDispose<AsyncValue<ProgressProtocols?>>((ref) {
  final range = ref.watch(progressRangeProvider);
  final settings = ref.watch(_progressSettingsProvider);
  if (range == null || settings == null) {
    return const AsyncLoading<ProgressProtocols?>();
  }
  if (!settings.showProtocolsOnToday) {
    return const AsyncData<ProgressProtocols?>(null);
  }
  final lock = ref.watch(protocolsLockControllerProvider);
  if (lock.hasError) {
    return const AsyncData<ProgressProtocols?>(
      ProgressProtocolsUnavailable(),
    );
  }
  final lockState = lock.value;
  if (lockState == null) {
    return const AsyncLoading<ProgressProtocols?>();
  }
  if (lockState.isUnavailable) {
    return const AsyncData<ProgressProtocols?>(
      ProgressProtocolsUnavailable(),
    );
  }
  if (lockState.isLocked) {
    return const AsyncData<ProgressProtocols?>(ProgressProtocolsLocked());
  }
  final summaries = ref.watch(
    progressConsistencySummaryProvider((range.from, range.to, range.today)),
  );
  return _whenAll<ProgressProtocols?>(
    <AsyncValue<Object?>>[summaries],
    'progress.protocols',
    () {
      final rows = summaries.requireValue;
      if (rows.isEmpty && !lockState.isEnabled) {
        return null;
      }
      return ProgressProtocolsRows(rows: rows, lockSet: lockState.isEnabled);
    },
  );
});

/// Loading until every input has data, the first error otherwise; then
/// [compute] inside a Timeline span named [span], so a profile build shows
/// each card's work in DevTools.
AsyncValue<T> _whenAll<T>(
  List<AsyncValue<Object?>> inputs,
  String span,
  T Function() compute,
) {
  for (final input in inputs) {
    if (input.hasError) {
      return AsyncError<T>(input.error!, input.stackTrace ?? StackTrace.empty);
    }
  }
  if (inputs.any((input) => !input.hasValue)) {
    return AsyncLoading<T>();
  }
  try {
    return AsyncData<T>(developer.Timeline.timeSync(span, compute));
  } catch (error, stackTrace) {
    return AsyncError<T>(error, stackTrace);
  }
}
