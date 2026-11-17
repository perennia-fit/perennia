import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/training/services/rest_cues.dart';

final _deadline = DateTime.utc(2026, 6, 16, 8, 2);

RestTimerRecord _timer({
  required Duration duration,
  RestTimerStatus status = RestTimerStatus.running,
  String? sourceSetId = 'set-1',
}) {
  return RestTimerRecord(
    id: 'rest-1',
    workoutId: 'workout-1',
    sourceSetId: sourceSetId,
    startedAt: _deadline.subtract(duration),
    deadlineAt: _deadline,
    duration: duration,
    alertVolume: 1,
    status: status,
    updatedAt: _deadline.subtract(duration),
  );
}

/// The phase with [remaining] left on [timer].
RestPhase _phase(RestTimerRecord timer, Duration remaining) {
  return restPhaseAt(timer, null, _deadline.subtract(remaining));
}

const _ms = Duration(milliseconds: 1);

void main() {
  group('restPhaseAt', () {
    test('a 16 s rest passes through every phase at its boundaries', () {
      final timer = _timer(duration: const Duration(seconds: 16));

      const start = Duration(seconds: 16);
      expect(_phase(timer, start), const RestResting(start));
      const justBeforeGetReady = Duration(milliseconds: 10001);
      expect(
        _phase(timer, justBeforeGetReady),
        const RestResting(justBeforeGetReady),
      );
      const getReady = Duration(seconds: 10);
      expect(_phase(timer, getReady), const RestGetReady(getReady));
      const justBeforeCountdown = Duration(milliseconds: 3001);
      expect(
        _phase(timer, justBeforeCountdown),
        const RestGetReady(justBeforeCountdown),
      );
      const countdown = Duration(seconds: 3);
      expect(_phase(timer, countdown), const RestCountdown(countdown));
      expect(_phase(timer, _ms), const RestCountdown(_ms));
      expect(_phase(timer, Duration.zero), const RestOver(Duration.zero));
    });

    test('a 15 s rest has no get ready', () {
      final timer = _timer(duration: const Duration(seconds: 15));

      const start = Duration(seconds: 15);
      expect(_phase(timer, start), const RestResting(start));
      const ten = Duration(seconds: 10);
      expect(_phase(timer, ten), const RestResting(ten));
      const justBeforeCountdown = Duration(milliseconds: 3001);
      expect(
        _phase(timer, justBeforeCountdown),
        const RestResting(justBeforeCountdown),
      );
      const countdown = Duration(seconds: 3);
      expect(_phase(timer, countdown), const RestCountdown(countdown));
      expect(_phase(timer, _ms), const RestCountdown(_ms));
      expect(_phase(timer, Duration.zero), const RestOver(Duration.zero));
    });

    test('a 3 s rest is all countdown', () {
      final timer = _timer(duration: const Duration(seconds: 3));

      const start = Duration(seconds: 3);
      expect(_phase(timer, start), const RestCountdown(start));
      expect(_phase(timer, _ms), const RestCountdown(_ms));
      expect(_phase(timer, Duration.zero), const RestOver(Duration.zero));
    });

    test('expired at the deadline reads as over', () {
      final timer = _timer(
        duration: const Duration(minutes: 2),
        status: RestTimerStatus.expired,
      );

      expect(_phase(timer, Duration.zero), const RestOver(Duration.zero));
    });

    test('expired with its deadline ahead reads as over at zero', () {
      final timer = _timer(
        duration: const Duration(minutes: 2),
        status: RestTimerStatus.expired,
      );

      expect(
        _phase(timer, const Duration(seconds: 5)),
        const RestOver(Duration.zero),
      );
    });

    test('over counts up, and goes idle at 5 min + 1 s', () {
      final timer = _timer(
        duration: const Duration(minutes: 2),
        status: RestTimerStatus.expired,
      );

      const twelve = Duration(seconds: 12);
      expect(_phase(timer, -twelve), const RestOver(twelve));
      expect(_phase(timer, -restOverLimit), const RestOver(restOverLimit));
      expect(
        _phase(timer, -(restOverLimit + const Duration(seconds: 1))),
        const RestIdle(),
      );
    });

    test('over goes idle when a later Set was performed', () {
      final timer = _timer(duration: const Duration(minutes: 2));
      final now = _deadline.add(const Duration(seconds: 12));
      const over = RestOver(Duration(seconds: 12));

      expect(
        restPhaseAt(
          timer,
          (id: 'set-2', performedAt: now.subtract(const Duration(seconds: 1))),
          now,
        ),
        const RestIdle(),
      );
      // The Set that started the rest is not a later Set.
      expect(
        restPhaseAt(timer, (id: 'set-1', performedAt: _deadline), now),
        over,
      );
      // Nor is a Set performed before the rest started.
      expect(
        restPhaseAt(
          timer,
          (
            id: 'set-0',
            performedAt: timer.startedAt.subtract(const Duration(seconds: 1)),
          ),
          now,
        ),
        over,
      );
    });

    test('canceled reads as idle, and so does no timer', () {
      final timer = _timer(
        duration: const Duration(minutes: 2),
        status: RestTimerStatus.canceled,
      );

      expect(_phase(timer, const Duration(seconds: 30)), const RestIdle());
      expect(_phase(timer, Duration.zero), const RestIdle());
      expect(restPhaseAt(null, null, _deadline), const RestIdle());
    });
  });

  group('cueScheduleFor', () {
    test('a rest longer than 15 s starts with get ready', () {
      expect(
        cueScheduleFor(const Duration(seconds: 16)),
        <({Duration before, TimerCue cue})>[
          (before: const Duration(seconds: 10), cue: TimerCue.getReady),
          (before: const Duration(seconds: 3), cue: TimerCue.countdown),
          (before: const Duration(seconds: 2), cue: TimerCue.tick),
          (before: const Duration(seconds: 1), cue: TimerCue.tick),
          (before: Duration.zero, cue: TimerCue.end),
        ],
      );
    });

    test('a 15 s rest has no get ready', () {
      expect(
        cueScheduleFor(const Duration(seconds: 15)),
        <({Duration before, TimerCue cue})>[
          (before: const Duration(seconds: 3), cue: TimerCue.countdown),
          (before: const Duration(seconds: 2), cue: TimerCue.tick),
          (before: const Duration(seconds: 1), cue: TimerCue.tick),
          (before: Duration.zero, cue: TimerCue.end),
        ],
      );
    });
  });

  group('ceilToSeconds', () {
    test('rounds a fraction up and keeps a whole second', () {
      expect(
        ceilToSeconds(const Duration(milliseconds: 2999)),
        const Duration(seconds: 3),
      );
      expect(
        ceilToSeconds(const Duration(seconds: 3)),
        const Duration(seconds: 3),
      );
      expect(
        ceilToSeconds(const Duration(milliseconds: 3001)),
        const Duration(seconds: 4),
      );
    });
  });
}
