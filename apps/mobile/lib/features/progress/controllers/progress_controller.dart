import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/analytics/progress_measure.dart';
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

  /// Whether [date] is in [from]..[to], both included.
  bool contains(TrainingDayDate date) =>
      date.compareTo(from) >= 0 && date.compareTo(to) <= 0;

  // Value equality: a settings change that leaves the dates alone rebuilds
  // this range without notifying the cards that watch it.
  @override
  bool operator ==(Object other) =>
      other is ProgressRange &&
      other.period == period &&
      other.today == today &&
      other.weekStart == weekStart &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(period, today, weekStart, from, to);
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

final progressFavoritesProvider =
    StreamProvider.autoDispose<List<ExerciseRecord>>((ref) {
  return ref.watch(progressFeatureRepositoryProvider).watchFavorites();
});

final progressExerciseNamesProvider =
    StreamProvider.autoDispose<Map<String, String>>((ref) {
  return ref.watch(progressFeatureRepositoryProvider).watchExerciseNames();
});

/// Keyed by the charted Favorites' ids as a set, so renaming one, even when
/// that reorders the tiles, keeps its series stream rather than restarting
/// it. The tiles take their order from the Favorites, not from the series.
final progressSeriesProvider = StreamProvider.autoDispose
    .family<List<ProgressSeries>, ProgressExerciseIds>((ref, ids) {
  return ref
      .watch(progressFeatureRepositoryProvider)
      .watchProgressSeries(ids.ids);
});

final progressNewBestsBetweenProvider = StreamProvider.autoDispose
    .family<List<NewBest>, (TrainingDayDate, TrainingDayDate)>((ref, range) {
  return ref
      .watch(progressFeatureRepositoryProvider)
      .watchNewBests(range.$1, range.$2);
});

/// Exercise ids compared by value, as a family key. The ids are kept in
/// code-unit order, so the key does not depend on the order they are given in.
@immutable
final class ProgressExerciseIds {
  ProgressExerciseIds(Iterable<String> ids)
      : ids = List<String>.unmodifiable(ids.toSet().toList()..sort());

  final List<String> ids;

  @override
  bool operator ==(Object other) =>
      other is ProgressExerciseIds && listEquals(other.ids, ids);

  @override
  int get hashCode => Object.hashAll(ids);
}

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

/// The Key exercises card (D8 card 4): a tile per charted Favorite.
final class ProgressKeyExercises {
  const ProgressKeyExercises({
    required this.hasFavorites,
    required this.tiles,
    required this.unitSystem,
    required this.today,
  });

  /// Whether any active exercise is a Favorite, charted or not: with none,
  /// the card asks for one; with some but no tile, it says none is charted.
  final bool hasFavorites;
  final List<ProgressKeyExercise> tiles;
  final UnitSystem unitSystem;
  final TrainingDayDate today;
}

/// One Favorite's tile: its series' points in the period and [periodBest].
final class ProgressKeyExercise {
  const ProgressKeyExercise({
    required this.exerciseId,
    required this.name,
    required this.measure,
    required this.points,
    required this.periodBest,
  });

  final String exerciseId;
  final String name;
  final ProgressMeasureKind measure;

  /// The series' points dated in the period, in series order.
  final List<ProgressPoint> points;
  final PeriodBest periodBest;
}

/// The New bests card (D8 card 5).
final class ProgressNewBests {
  const ProgressNewBests({
    required this.count,
    required this.rows,
    required this.unitSystem,
    required this.today,
  });

  /// Every New Best in the period, of which [rows] are the most recent.
  final int count;
  final List<ProgressNewBestRow> rows;
  final UnitSystem unitSystem;
  final TrainingDayDate today;
}

final class ProgressNewBestRow {
  const ProgressNewBestRow({required this.best, required this.exerciseName});

  final NewBest best;
  final String exerciseName;
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

/// The unlocked card's rows. With a lock set and no rows the card still
/// shows, empty, so unlocking never reveals whether Protocols exist.
final class ProgressProtocolsRows extends ProgressProtocols {
  const ProgressProtocolsRows({required this.rows});

  final List<CompoundConsistencySummary> rows;
}

final progressThisWeekProvider =
    Provider.autoDispose<AsyncValue<ProgressThisWeek>>((ref) {
  // The week alone, not the period: switching the period neither recomputes
  // This week nor makes it wait on a year of Workouts it does not read
  // (Goal 2, D8).
  final dates = ref.watch(
    progressRangeProvider.select(
      (range) => range == null ? null : (range.weekStart, range.today),
    ),
  );
  if (dates == null) {
    return const AsyncLoading<ProgressThisWeek>();
  }
  final (weekStart, today) = dates;
  final plans = ref.watch(progressWeeklyPlansProvider);
  final rotating = ref.watch(progressHasRotatingRoutineProvider);
  final workouts = ref.watch(
    progressWorkoutsProvider((weekStart, weekStart.addDays(6))),
  );
  return _whenAll(
    <AsyncValue<Object?>>[plans, rotating, workouts],
    'progress.thisWeek',
    () {
      final facts = plans.requireValue;
      final week = trainingWeek(
        plans: facts.map((plan) => plan.toWeeklyPlan()),
        workouts: workouts.requireValue,
        weekStart: weekStart,
        today: today,
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
        today: today,
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

/// Key exercises' tiles: the first [maxTiles] Favorites, in the order
/// [ProgressFeatureRepository.watchFavorites] gives, whose Record Profile has
/// a series (D4, D8). Only those few series are computed, on this isolate.
final progressKeyExercisesProvider =
    Provider.autoDispose<AsyncValue<ProgressKeyExercises>>((ref) {
  final range = ref.watch(progressRangeProvider);
  final unitSystem = ref.watch(
    _progressSettingsProvider.select((settings) => settings?.unitSystem),
  );
  if (range == null || unitSystem == null) {
    return const AsyncLoading<ProgressKeyExercises>();
  }
  final favorites = ref.watch(progressFavoritesProvider);
  final charted = favorites.value
      ?.where(
        (exercise) =>
            ProgressMeasureKind.forRecordProfile(exercise.recordProfile) !=
            null,
      )
      .take(progressKeyExercisesMaxTiles)
      .toList(growable: false);
  final series = charted == null
      ? const AsyncLoading<List<ProgressSeries>>()
      : ref.watch(
          progressSeriesProvider(
            ProgressExerciseIds(<String>[
              for (final exercise in charted) exercise.id,
            ]),
          ),
        );
  return _whenAll(
    <AsyncValue<Object?>>[favorites, series],
    'progress.keyExercises',
    () {
      final byId = <String, ProgressSeries>{
        for (final one in series.requireValue) one.exerciseId: one,
      };
      return ProgressKeyExercises(
        hasFavorites: favorites.requireValue.isNotEmpty,
        tiles: <ProgressKeyExercise>[
          for (final exercise in charted!)
            if (byId[exercise.id] case final one?)
              ProgressKeyExercise(
                exerciseId: exercise.id,
                name: exercise.name,
                measure: one.measure,
                points: <ProgressPoint>[
                  for (final point in one.points)
                    if (range.contains(point.localDate)) point,
                ],
                periodBest: periodBest(one, range.from, range.to),
              ),
        ],
        unitSystem: unitSystem,
        today: range.today,
      );
    },
  );
});

/// The most Key exercises tiles shown (D8).
const int progressKeyExercisesMaxTiles = 6;

/// The most New Bests listed (D8); the title counts all of them.
const int progressNewBestsMaxRows = 5;

/// The period's New Bests with their exercises' names. A New Best whose
/// exercise has no active name yet (its archive is still reaching this
/// stream) is left out of the rows and the count alike.
final progressNewBestsProvider =
    Provider.autoDispose<AsyncValue<ProgressNewBests>>((ref) {
  final range = ref.watch(progressRangeProvider);
  final unitSystem = ref.watch(
    _progressSettingsProvider.select((settings) => settings?.unitSystem),
  );
  if (range == null || unitSystem == null) {
    return const AsyncLoading<ProgressNewBests>();
  }
  final bests = ref.watch(
    progressNewBestsBetweenProvider((range.from, range.to)),
  );
  final names = ref.watch(progressExerciseNamesProvider);
  return _whenAll(
    <AsyncValue<Object?>>[bests, names],
    'progress.newBests',
    () {
      final nameById = names.requireValue;
      final rows = <ProgressNewBestRow>[
        for (final best in bests.requireValue)
          if (nameById[best.exerciseId] case final name?)
            ProgressNewBestRow(best: best, exerciseName: name),
      ];
      return ProgressNewBests(
        count: rows.length,
        rows: rows.take(progressNewBestsMaxRows).toList(growable: false),
        unitSystem: unitSystem,
        today: range.today,
      );
    },
  );
});

/// The Protocols card's state (D7): data null means the card is absent, and
/// loading renders nothing, because the card may turn out absent. The lock
/// is read on every build and before any summary, so no Compound is loaded
/// for the card while Protocols are locked. Every error fails closed as
/// [ProgressProtocolsUnavailable], so this provider is never an error.
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
  final protocols = _whenAll<ProgressProtocols?>(
    <AsyncValue<Object?>>[summaries],
    'progress.protocols',
    () {
      final rows = summaries.requireValue;
      if (rows.isEmpty && !lockState.isEnabled) {
        return null;
      }
      return ProgressProtocolsRows(rows: rows);
    },
  );
  return protocols.hasError
      ? const AsyncData<ProgressProtocols?>(ProgressProtocolsUnavailable())
      : protocols;
});

/// Loading until every input has data, the first error otherwise; then
/// [compute] inside a Timeline span named [span], so a profile build shows
/// each card's work in DevTools. An error is also logged under [span]: the
/// card shows only that it is unavailable.
AsyncValue<T> _whenAll<T>(
  List<AsyncValue<Object?>> inputs,
  String span,
  T Function() compute,
) {
  AsyncValue<T> failed(Object error, StackTrace stackTrace) {
    developer.log(
      'failed',
      name: span,
      error: error,
      stackTrace: stackTrace,
    );
    return AsyncError<T>(error, stackTrace);
  }

  for (final input in inputs) {
    if (input.hasError) {
      return failed(input.error!, input.stackTrace ?? StackTrace.empty);
    }
  }
  if (inputs.any((input) => !input.hasValue)) {
    return AsyncLoading<T>();
  }
  try {
    return AsyncData<T>(developer.Timeline.timeSync(span, compute));
  } catch (error, stackTrace) {
    return failed(error, stackTrace);
  }
}
