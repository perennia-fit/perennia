import '../../../data/repositories/training_repositories.dart';

/// How long before the deadline the get-ready cue plays.
const getReadyLead = Duration(seconds: 10);

/// Rests longer than this get the get-ready cue. A rest this short has barely
/// started when the cue would play.
const getReadyAfterRest = Duration(seconds: 15);

/// How long before the deadline the 3-2-1 cue plays.
const countdownLead = RestTimerRepository.prepareCueLead;

/// How long after the deadline the strip keeps showing Rest over, so a strip
/// left alone does not read "+58:12".
const restOverLimit = Duration(minutes: 5);

/// A cue at most this far in the past is still armed, so a −15 s that brings
/// the deadline to now still plays the end cue.
const cueArmLimit = Duration(seconds: 1);

/// A cue that fires at most this late still plays. Later than that, the system
/// notification has covered the moment.
const cueLateLimit = Duration(seconds: 1);

/// One moment in a rest that has a sound, a vibration or both.
enum TimerCue { getReady, countdown, tick, end }

/// What the rest strip shows, derived from the timer row and the clock.
sealed class RestPhase {
  const RestPhase();
}

/// No rest to show: "Start rest".
final class RestIdle extends RestPhase {
  const RestIdle();

  @override
  bool operator ==(Object other) => other is RestIdle;

  @override
  int get hashCode => (RestIdle).hashCode;
}

/// A rest with more than the cues' lead left.
final class RestResting extends RestPhase {
  const RestResting(this.remaining);

  final Duration remaining;

  @override
  bool operator ==(Object other) =>
      other is RestResting && other.remaining == remaining;

  @override
  int get hashCode => Object.hash(RestResting, remaining);

  @override
  String toString() => 'RestResting($remaining)';
}

/// The last [getReadyLead] of a rest longer than [getReadyAfterRest], before
/// the countdown.
final class RestGetReady extends RestPhase {
  const RestGetReady(this.remaining);

  final Duration remaining;

  @override
  bool operator ==(Object other) =>
      other is RestGetReady && other.remaining == remaining;

  @override
  int get hashCode => Object.hash(RestGetReady, remaining);

  @override
  String toString() => 'RestGetReady($remaining)';
}

/// The last [countdownLead] of a rest.
final class RestCountdown extends RestPhase {
  const RestCountdown(this.remaining);

  final Duration remaining;

  @override
  bool operator ==(Object other) =>
      other is RestCountdown && other.remaining == remaining;

  @override
  int get hashCode => Object.hash(RestCountdown, remaining);

  @override
  String toString() => 'RestCountdown($remaining)';
}

/// The rest ended [elapsed] ago, and the lifter has not moved on.
final class RestOver extends RestPhase {
  const RestOver(this.elapsed);

  final Duration elapsed;

  @override
  bool operator ==(Object other) =>
      other is RestOver && other.elapsed == elapsed;

  @override
  int get hashCode => Object.hash(RestOver, elapsed);

  @override
  String toString() => 'RestOver($elapsed)';
}

/// The strip's phase for [timer] at [now]. [newestPerformed] is the Workout's
/// Performed Set with the latest `performedAt`.
///
/// `expired` counts as over: `RestTimerRepository.markAlertFired` sets that
/// status along with `alertFiredAt`, and without this the strip would drop to
/// idle the moment it marks the end.
///
/// A later Set ends Rest over: with Rest after Off, Log set starts no timer and
/// leaves the previous one, and a Set logged after the timer started, other
/// than the one that started it, means the lifter has moved on.
RestPhase restPhaseAt(
  RestTimerRecord? timer,
  ({String id, DateTime performedAt})? newestPerformed,
  DateTime now,
) {
  if (timer == null || timer.status == RestTimerStatus.canceled) {
    return const RestIdle();
  }
  final remaining = timer.deadlineAt.difference(now);
  if (remaining > Duration.zero && timer.status == RestTimerStatus.running) {
    if (remaining <= countdownLead) {
      return RestCountdown(remaining);
    }
    if (timer.duration > getReadyAfterRest && remaining <= getReadyLead) {
      return RestGetReady(remaining);
    }
    return RestResting(remaining);
  }
  // At or past the deadline, or `expired` with its deadline moved ahead: an
  // elapsed time is never negative.
  final elapsed = remaining.isNegative ? -remaining : Duration.zero;
  if (elapsed > restOverLimit) {
    return const RestIdle();
  }
  if (newestPerformed != null &&
      newestPerformed.id != timer.sourceSetId &&
      newestPerformed.performedAt.isAfter(timer.startedAt)) {
    return const RestIdle();
  }
  return RestOver(elapsed);
}

/// The cues of a rest of [duration], as offsets before its deadline, in the
/// order they play.
List<({Duration before, TimerCue cue})> cueScheduleFor(Duration duration) {
  return <({Duration before, TimerCue cue})>[
    if (duration > getReadyAfterRest)
      (before: getReadyLead, cue: TimerCue.getReady),
    (before: countdownLead, cue: TimerCue.countdown),
    (before: const Duration(seconds: 2), cue: TimerCue.tick),
    (before: const Duration(seconds: 1), cue: TimerCue.tick),
    (before: Duration.zero, cue: TimerCue.end),
  ];
}

/// [d] rounded up to whole seconds, for the strip's digits. A `Timer` never
/// fires early, so rounding down would show "0:02" as the 0:03 beep plays.
Duration ceilToSeconds(Duration d) {
  final micros = d.inMicroseconds;
  final seconds = micros ~/ Duration.microsecondsPerSecond;
  final hasFraction = micros.remainder(Duration.microsecondsPerSecond) > 0;
  return Duration(seconds: hasFraction ? seconds + 1 : seconds);
}
