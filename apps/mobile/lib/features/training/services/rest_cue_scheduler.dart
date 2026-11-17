import 'dart:async';

import 'package:clock/clock.dart';

import '../../../data/repositories/training_repositories.dart';
import 'rest_cues.dart';

/// Owns the timing of a rest's cues: one-shot `Timer`s armed from the deadline,
/// never detected from the frames the strip happens to draw, so resuming the
/// app never replays a cue.
///
/// Every reading of the time goes through `clock.now()`, so tests run this
/// under `fakeAsync` with no widget and no database.
class RestCueScheduler {
  RestCueScheduler({
    required bool Function() canPlay,
    required void Function(TimerCue cue) onCue,
  })  : _canPlay = canPlay,
        _onCue = onCue;

  final bool Function() _canPlay;
  final void Function(TimerCue cue) _onCue;
  final _armed = <Timer>[];
  String? _armedId;
  DateTime? _armedDeadline;

  /// Arms the cues of [timer] when it is a running timer whose id and deadline
  /// differ from the armed ones (a new timer, or a new deadline after ±15 s).
  /// Anything but a running timer cancels what is armed.
  ///
  /// Only the cues still ahead are armed, so a strip that opens part-way
  /// through a rest plays those and no others.
  void update(RestTimerRecord? timer) {
    if (timer == null || timer.status != RestTimerStatus.running) {
      _cancelArmed();
      _armedId = null;
      _armedDeadline = null;
      return;
    }
    final armedDeadline = _armedDeadline;
    if (timer.id == _armedId &&
        armedDeadline != null &&
        timer.deadlineAt.isAtSameMomentAs(armedDeadline)) {
      return;
    }
    _cancelArmed();
    _armedId = timer.id;
    _armedDeadline = timer.deadlineAt;
    final now = clock.now();
    for (final entry in cueScheduleFor(timer.duration)) {
      final cueAt = timer.deadlineAt.subtract(entry.before);
      final delay = cueAt.difference(now);
      if (delay < -cueArmLimit) {
        continue;
      }
      _armed.add(
        Timer(
          delay.isNegative ? Duration.zero : delay,
          () => _fire(entry.cue, cueAt),
        ),
      );
    }
  }

  void _fire(TimerCue cue, DateTime cueAt) {
    final late = clock.now().difference(cueAt);
    if (late <= cueLateLimit && _canPlay()) {
      _onCue(cue);
    }
  }

  void dispose() {
    _cancelArmed();
  }

  void _cancelArmed() {
    for (final timer in _armed) {
      timer.cancel();
    }
    _armed.clear();
  }
}
