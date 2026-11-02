/// The Progress Measure core (docs/designs/progress-overview.md, D0 and D4):
/// one number per Logged Workout for an exercise, taken from its Record
/// Profile, and the New Bests among them. Progress Overview's Key exercises
/// and New bests cards read these functions, and so does the Agent read
/// `listAgentNewBests`.
///
/// Pure: no I/O, no clock. Every value comes from [ExerciseAnalyticsEngine],
/// which is called per Workout and not changed, so its unit normalization and
/// record rules apply. Nothing returned here is stored or synced.
///
/// [progressSeries] and [newBestsBetween] are pinned against the TypeScript
/// twin (`apps/server/src/analytics/progress-measure.ts`) by
/// `packages/golden-vectors/vectors/m37-progress-measure.json`. [periodBest]
/// is Dart only, because only the Key exercises tile compares a period with
/// what came before it.
library;

import '../training/training_day.dart';
import '../training/training_dimensions.dart';
import 'exercise_analytics.dart';

/// D4's measures, one per Record Profile that has a single best number. The
/// names are the wire values.
enum ProgressMeasureKind {
  estimatedOneRepMax(ProgressBetterIs.higher),
  maxLoad(ProgressBetterIs.higher),
  maxReps(ProgressBetterIs.higher),
  maxDuration(ProgressBetterIs.higher),
  minDuration(ProgressBetterIs.lower),
  maxDistance(ProgressBetterIs.higher),
  fastestPace(ProgressBetterIs.lower);

  const ProgressMeasureKind(this.betterIs);

  final ProgressBetterIs betterIs;

  /// D4's table. `minAssistancePerRepCount` is a record per rep count, so no
  /// single number would agree with the engine; `completionStreak` has no
  /// value. Both are null: no series.
  static ProgressMeasureKind? forRecordProfile(RecordProfile profile) {
    return switch (profile) {
      RecordProfile.repMax => estimatedOneRepMax,
      RecordProfile.maxLoad => maxLoad,
      RecordProfile.maxReps => maxReps,
      RecordProfile.maxDuration => maxDuration,
      RecordProfile.minDuration => minDuration,
      RecordProfile.maxDistance => maxDistance,
      RecordProfile.fastestPace => fastestPace,
      RecordProfile.minAssistancePerRepCount => null,
      RecordProfile.completionStreak => null,
    };
  }
}

/// Which way a [ProgressMeasureKind] improves. The names are the wire values.
enum ProgressBetterIs {
  higher,
  lower;

  bool isBetter(double candidate, double current) =>
      this == higher ? candidate > current : candidate < current;
}

/// One Set of a Workout (D0). A Set with [isCompleted] false is not
/// Performed, and [progressSeries] ignores it.
final class ProgressSet {
  const ProgressSet({
    required this.id,
    required this.position,
    required this.isCompleted,
    required this.values,
  });

  final String id;
  final int position;
  final bool isCompleted;
  final LoggedSet values;
}

/// One Workout's Sets of the exercise. The loaders drop deleted Workouts.
final class ProgressWorkoutSets {
  ProgressWorkoutSets({
    required this.workoutId,
    required this.localDate,
    required this.startedAt,
    required Iterable<ProgressSet> sets,
  }) : sets = List<ProgressSet>.unmodifiable(sets);

  final String workoutId;
  final TrainingDayDate localDate;
  final DateTime startedAt;
  final List<ProgressSet> sets;
}

/// One Logged Workout's Progress Measure. [setId] is the Set the engine's
/// value came from; [value] and [unit] are the engine's normalized ones.
final class ProgressPoint {
  const ProgressPoint({
    required this.workoutId,
    required this.localDate,
    required this.startedAt,
    required this.setId,
    required this.value,
    required this.unit,
    required this.isNewBest,
  });

  final String workoutId;
  final TrainingDayDate localDate;
  final DateTime startedAt;
  final String setId;
  final double value;
  final TrainingUnit unit;
  final bool isNewBest;
}

final class ProgressSeries {
  ProgressSeries({
    required this.exerciseId,
    required this.measure,
    required this.betterIs,
    required Iterable<ProgressPoint> points,
  }) : points = List<ProgressPoint>.unmodifiable(points);

  final String exerciseId;
  final ProgressMeasureKind measure;
  final ProgressBetterIs betterIs;

  /// Ordered by (localDate, startedAt, workoutId).
  final List<ProgressPoint> points;
}

/// A New Best point with the exercise it belongs to.
final class NewBest {
  const NewBest({
    required this.exerciseId,
    required this.measure,
    required this.workoutId,
    required this.localDate,
    required this.startedAt,
    required this.setId,
    required this.value,
    required this.unit,
  });

  final String exerciseId;
  final ProgressMeasureKind measure;
  final String workoutId;
  final TrainingDayDate localDate;
  final DateTime startedAt;
  final String setId;
  final double value;
  final TrainingUnit unit;
}

/// What the Key exercises tile shows: [best] is the best point in the
/// period, and [bestBefore] the best value before it. Either can be null.
final class PeriodBest {
  const PeriodBest({required this.best, required this.bestBefore});

  final ProgressPoint? best;
  final double? bestBefore;
}

/// The exercise's Progress Measure per Logged Workout (D4), or null for a
/// Record Profile with no single best number.
///
/// Each Workout's Performed Sets run through [ExerciseAnalyticsEngine] on
/// their own, with `performedAt` the Workout's start and the sequence the
/// Set's position; a Workout with no Performed Set, or no value for the
/// measure, has no point. Points are ordered by (localDate, startedAt,
/// workoutId), and a point is a New Best when it is strictly better than
/// every earlier one, so the first point and equal values never are.
ProgressSeries? progressSeries({
  required String exerciseId,
  required ExerciseAnalyticsProfile profile,
  required Iterable<ProgressWorkoutSets> workouts,
}) {
  final measure = ProgressMeasureKind.forRecordProfile(profile.recordProfile);
  if (measure == null) {
    return null;
  }

  final ordered = workouts.toList()
    ..sort((a, b) {
      final byDate = a.localDate.compareTo(b.localDate);
      if (byDate != 0) return byDate;
      final byStart = a.startedAt.compareTo(b.startedAt);
      return byStart != 0 ? byStart : a.workoutId.compareTo(b.workoutId);
    });

  const engine = ExerciseAnalyticsEngine();
  final points = <ProgressPoint>[];
  double? best;
  for (final workout in ordered) {
    final performed =
        workout.sets.where((set) => set.isCompleted).toList(growable: false);
    if (performed.isEmpty) {
      continue;
    }
    final result = engine.compute(
      profile: profile,
      sets: <AnalyticsSet>[
        for (final set in performed)
          AnalyticsSet(
            id: set.id,
            performedAt: workout.startedAt,
            sequence: set.position,
            values: set.values,
          ),
      ],
    );
    final taken = _measureValue(measure, result, performed);
    if (taken == null) {
      continue;
    }

    final isNewBest =
        best != null && measure.betterIs.isBetter(taken.value, best);
    if (best == null || isNewBest) {
      best = taken.value;
    }
    points.add(
      ProgressPoint(
        workoutId: workout.workoutId,
        localDate: workout.localDate,
        startedAt: workout.startedAt,
        setId: taken.setId,
        value: taken.value,
        unit: taken.unit,
        isNewBest: isNewBest,
      ),
    );
  }

  return ProgressSeries(
    exerciseId: exerciseId,
    measure: measure,
    betterIs: measure.betterIs,
    points: points,
  );
}

/// The value D4 takes from one Workout's engine result. For e1RM, the highest
/// point; on a tie, the Set with the lower (position, id), compared here
/// rather than left to the engine's own Set order.
({String setId, double value, TrainingUnit unit})? _measureValue(
  ProgressMeasureKind measure,
  ExerciseAnalyticsResult result,
  List<ProgressSet> sets,
) {
  if (measure != ProgressMeasureKind.estimatedOneRepMax) {
    final record = result.headlineRecord;
    return record == null
        ? null
        : (setId: record.setId, value: record.value, unit: record.unit);
  }

  final positionById = <String, int>{
    for (final set in sets) set.id: set.position,
  };
  int compareSets(String left, String right) {
    final byPosition = positionById[left]!.compareTo(positionById[right]!);
    return byPosition != 0 ? byPosition : left.compareTo(right);
  }

  ({String setId, double value, TrainingUnit unit})? best;
  for (final point in result.estimatedOneRepMax.points) {
    if (best == null ||
        point.value > best.value ||
        (point.value == best.value &&
            compareSets(point.setId, best.setId) < 0)) {
      best = (setId: point.setId, value: point.value, unit: point.unit);
    }
  }
  return best;
}

/// Every New Best point of [series] whose local date is in [from, to] (D4),
/// newest first: by localDate, startedAt and workoutId descending, then
/// exerciseId ascending. The series carry each exercise's whole history, so
/// a best in the period is judged against everything before it.
List<NewBest> newBestsBetween(
  Iterable<ProgressSeries> series,
  TrainingDayDate from,
  TrainingDayDate to,
) {
  final bests = <NewBest>[
    for (final one in series)
      for (final point in one.points)
        if (point.isNewBest && _inPeriod(point.localDate, from, to))
          NewBest(
            exerciseId: one.exerciseId,
            measure: one.measure,
            workoutId: point.workoutId,
            localDate: point.localDate,
            startedAt: point.startedAt,
            setId: point.setId,
            value: point.value,
            unit: point.unit,
          ),
  ]..sort((a, b) {
      final byDate = b.localDate.compareTo(a.localDate);
      if (byDate != 0) return byDate;
      final byStart = b.startedAt.compareTo(a.startedAt);
      if (byStart != 0) return byStart;
      final byWorkout = b.workoutId.compareTo(a.workoutId);
      return byWorkout != 0 ? byWorkout : a.exerciseId.compareTo(b.exerciseId);
    });
  return List<NewBest>.unmodifiable(bests);
}

/// The best point of [series] whose local date is in [from, to], and the
/// best value among its points before [from] (D4). On equal values the
/// earlier point is the best.
PeriodBest periodBest(
  ProgressSeries series,
  TrainingDayDate from,
  TrainingDayDate to,
) {
  ProgressPoint? best;
  double? bestBefore;
  for (final point in series.points) {
    if (point.localDate.compareTo(from) < 0) {
      if (bestBefore == null ||
          series.betterIs.isBetter(point.value, bestBefore)) {
        bestBefore = point.value;
      }
    } else if (point.localDate.compareTo(to) <= 0) {
      if (best == null || series.betterIs.isBetter(point.value, best.value)) {
        best = point;
      }
    }
  }
  return PeriodBest(best: best, bestBefore: bestBefore);
}

bool _inPeriod(
  TrainingDayDate date,
  TrainingDayDate from,
  TrainingDayDate to,
) =>
    date.compareTo(from) >= 0 && date.compareTo(to) <= 0;
