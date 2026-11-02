import '../../../l10n/l10n.dart';

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
