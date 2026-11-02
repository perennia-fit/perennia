import 'package:intl/intl.dart';

import '../../../domain/analytics/progress_measure.dart';
import '../../../domain/training/training_day.dart';
import '../../../l10n/l10n.dart';
import '../../settings/repositories/settings_repository.dart';

/// The separator between the parts of a Progress summary line.
const String progressSeparator = ' · ';

/// [seconds] as "2h 40m" or "35m", after rounding half up to whole minutes
/// once (D3), so the display agrees with an Agent summing the per-date
/// seconds itself.
String formatFocusDuration(int seconds, AppLocalizations l10n) {
  final minutes = roundedFocusMinutes(seconds);
  final hours = minutes ~/ 60;
  return hours > 0
      ? l10n.workoutDurationHoursMinutes(hours, minutes % 60)
      : l10n.workoutDurationMinutes(minutes);
}

/// [seconds] as "2 hours 40 minutes", for screen readers, from the same
/// rounded minutes as [formatFocusDuration].
String speakFocusDuration(int seconds, AppLocalizations l10n) {
  final minutes = roundedFocusMinutes(seconds);
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) {
    return l10n.progressMinutesSpoken(rest);
  }
  if (rest == 0) {
    return l10n.progressHoursSpoken(hours);
  }
  return l10n.progressHoursMinutesSpoken(
    l10n.progressHoursSpoken(hours),
    l10n.progressMinutesSpoken(rest),
  );
}

/// Whole minutes in [seconds], rounded half up: 30 seconds is one minute.
int roundedFocusMinutes(int seconds) => (seconds + 30) ~/ 60;

/// [measure]'s label (Data shapes): "e1RM", "heaviest", "most reps"...
String progressMeasureLabel(
  ProgressMeasureKind measure,
  AppLocalizations l10n,
) {
  return switch (measure) {
    ProgressMeasureKind.estimatedOneRepMax =>
      l10n.progressMeasureEstimatedOneRepMax,
    ProgressMeasureKind.maxLoad => l10n.progressMeasureMaxLoad,
    ProgressMeasureKind.maxReps => l10n.progressMeasureMaxReps,
    ProgressMeasureKind.maxDuration => l10n.progressMeasureMaxDuration,
    ProgressMeasureKind.minDuration => l10n.progressMeasureMinDuration,
    ProgressMeasureKind.maxDistance => l10n.progressMeasureMaxDistance,
    ProgressMeasureKind.fastestPace => l10n.progressMeasureFastestPace,
  };
}

/// Pounds per kilogram and kilometres per mile, for imperial display (D8).
const double _poundsPerKilogram = 2.20462;
const double _kilometersPerMile = 1.609344;

/// [value], the engine's normalized value for [measure] (kilograms,
/// repetitions, seconds, kilometres, seconds per kilometre), as Key exercises
/// and New bests show it in [unitSystem] (D8): loads to one decimal with a
/// trailing ".0" dropped, distances to two decimals, durations and paces as
/// `m:ss` (`h:mm:ss` from an hour), after rounding seconds half up.
///
/// With [isDifference], [value] is the gap between two values, as the
/// comparison line shows it: a duration or pace gap under a minute reads
/// "18 s" and a longer one "1:05", with no "/km" after it; other measures
/// read as their values do.
String formatProgressValue(
  ProgressMeasureKind measure,
  double value,
  UnitSystem unitSystem,
  AppLocalizations l10n, {
  bool isDifference = false,
}) {
  final imperial = unitSystem == UnitSystem.imperial;
  switch (measure) {
    case ProgressMeasureKind.estimatedOneRepMax:
    case ProgressMeasureKind.maxLoad:
      final load = _oneDecimal(imperial ? value * _poundsPerKilogram : value);
      return imperial
          ? l10n.progressValuePounds(load)
          : l10n.progressValueKilograms(load);
    case ProgressMeasureKind.maxReps:
      return l10n.progressValueReps(value.round());
    case ProgressMeasureKind.maxDistance:
      final distance =
          (imperial ? value / _kilometersPerMile : value).toStringAsFixed(2);
      return imperial
          ? l10n.progressValueMiles(distance)
          : l10n.progressValueKilometers(distance);
    case ProgressMeasureKind.maxDuration:
    case ProgressMeasureKind.minDuration:
      final seconds = _wholeSeconds(value);
      return isDifference && seconds < 60
          ? l10n.progressValueSeconds(seconds)
          : _clock(seconds);
    case ProgressMeasureKind.fastestPace:
      final seconds = _wholeSeconds(
        imperial ? value * _kilometersPerMile : value,
      );
      if (isDifference) {
        return seconds < 60
            ? l10n.progressValueSeconds(seconds)
            : _clock(seconds);
      }
      final pace = _clock(seconds);
      return imperial
          ? l10n.progressValuePacePerMile(pace)
          : l10n.progressValuePacePerKilometer(pace);
  }
}

/// [date] as a Progress row dates it (D8): the weekday ("Sat") from six days
/// before [today] through today, "12 Oct" for another date in [today]'s year,
/// and "12 Oct 2025" otherwise.
String formatProgressDate(
  TrainingDayDate date,
  TrainingDayDate today,
  String locale,
) {
  final local = date.toLocalDateTime();
  if (date.compareTo(today.addDays(-6)) >= 0 && date.compareTo(today) <= 0) {
    return DateFormat('EEE', locale).format(local);
  }
  return date.year == today.year
      ? DateFormat('d MMM', locale).format(local)
      : DateFormat('d MMM y', locale).format(local);
}

/// [value] rounded half up to one decimal, without a trailing ".0".
String _oneDecimal(double value) {
  final text = ((value * 10).round() / 10).toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// Seconds rounded half up to whole seconds.
int _wholeSeconds(double seconds) => (seconds + 0.5).floor();

/// [seconds] as `m:ss`, or `h:mm:ss` from an hour.
String _clock(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$rest'
      : '$minutes:$rest';
}
