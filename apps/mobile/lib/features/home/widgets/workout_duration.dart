import '../../../domain/training/training_day.dart';
import '../../../l10n/l10n.dart';
import '../repositories/home_repository.dart';

/// A Workout's duration as Today's cards and the Workout screen show it: the
/// largest units that apply, or "in progress" when [duration] is null or
/// negative (the Workout has not finished, or its times were edited across
/// each other).
String formatWorkoutDuration(AppLocalizations l10n, Duration? duration) {
  if (duration == null || duration.isNegative) {
    return l10n.workoutDurationInProgress;
  }

  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return minutes == 0
        ? l10n.workoutDurationHours(hours)
        : l10n.workoutDurationHoursMinutes(hours, minutes);
  }
  if (minutes > 0) {
    return l10n.workoutDurationMinutes(minutes);
  }
  return l10n.workoutDurationSeconds(seconds);
}

/// The Training Day [workout] belongs to: its stored `localDate`, or its
/// `startedAt` in local time when that is null.
TrainingDayDate workoutLocalDate(HomeWorkoutSummary workout) {
  return workout.localDate ??
      TrainingDayDate.fromDateTime(workout.startedAt.toLocal());
}
