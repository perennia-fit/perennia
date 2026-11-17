import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/training/services/rest_cue_scheduler.dart';
import 'package:perennia/features/training/services/rest_cues.dart';

/// A running rest of [duration] that ends [remaining] from `clock.now()`.
RestTimerRecord _timer({
  String id = 'rest-1',
  required Duration duration,
  Duration? remaining,
}) {
  final now = clock.now().toUtc();
  final deadlineAt = now.add(remaining ?? duration);
  return RestTimerRecord(
    id: id,
    workoutId: 'workout-1',
    sourceSetId: null,
    startedAt: deadlineAt.subtract(duration),
    deadlineAt: deadlineAt,
    duration: duration,
    alertVolume: 1,
    status: RestTimerStatus.running,
    updatedAt: now,
  );
}

void main() {
  late List<TimerCue> played;
  late bool canPlay;

  RestCueScheduler newScheduler() {
    return RestCueScheduler(canPlay: () => canPlay, onCue: played.add);
  }

  setUp(() {
    played = <TimerCue>[];
    canPlay = true;
  });

  const second = Duration(seconds: 1);

  test('a 20 s rest plays each cue at its offset, in order', () {
    fakeAsync((async) {
      final scheduler = newScheduler();
      scheduler.update(_timer(duration: const Duration(seconds: 20)));

      async.elapse(
          const Duration(seconds: 10) - const Duration(milliseconds: 1));
      expect(played, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(played, <TimerCue>[TimerCue.getReady]);

      async.elapse(const Duration(seconds: 7));
      expect(played, <TimerCue>[TimerCue.getReady, TimerCue.countdown]);

      async.elapse(second);
      expect(played.last, TimerCue.tick);
      expect(played, hasLength(3));

      async.elapse(second);
      expect(played.last, TimerCue.tick);
      expect(played, hasLength(4));

      async.elapse(second);
      expect(played, <TimerCue>[
        TimerCue.getReady,
        TimerCue.countdown,
        TimerCue.tick,
        TimerCue.tick,
        TimerCue.end,
      ]);

      scheduler.dispose();
    });
  });

  test('a 15 s rest has no get ready', () {
    fakeAsync((async) {
      final scheduler = newScheduler();
      scheduler.update(_timer(duration: const Duration(seconds: 15)));

      async.elapse(const Duration(seconds: 15));

      expect(played, <TimerCue>[
        TimerCue.countdown,
        TimerCue.tick,
        TimerCue.tick,
        TimerCue.end,
      ]);

      scheduler.dispose();
    });
  });

  test('with canPlay false no cue reaches onCue', () {
    fakeAsync((async) {
      canPlay = false;
      final scheduler = newScheduler();
      scheduler.update(_timer(duration: const Duration(seconds: 20)));

      async.elapse(const Duration(seconds: 20));

      expect(played, isEmpty);

      scheduler.dispose();
    });
  });

  test('a deadline moved to now still plays the end cue', () {
    fakeAsync((async) {
      final scheduler = newScheduler();
      final timer = _timer(duration: const Duration(seconds: 20));
      scheduler.update(timer);
      async.elapse(const Duration(seconds: 5));

      // −15 s with 15 s left: `adjust` sets the deadline to exactly now, and
      // the row reaches `update` a moment later. That moment puts the −1 s
      // tick past `cueArmLimit`, so the end is the only cue left.
      scheduler.update(
        _timer(
          duration: const Duration(seconds: 5),
          remaining: const Duration(milliseconds: -5),
        ),
      );
      async.elapse(Duration.zero);

      expect(played, <TimerCue>[TimerCue.end]);

      scheduler.dispose();
    });
  });

  test('with 0:05 left it plays the countdown, ticks and end, no get ready',
      () {
    fakeAsync((async) {
      final scheduler = newScheduler();
      scheduler.update(
        _timer(
          duration: const Duration(minutes: 2),
          remaining: const Duration(seconds: 5),
        ),
      );

      async.elapse(const Duration(seconds: 5));

      expect(played, <TimerCue>[
        TimerCue.countdown,
        TimerCue.tick,
        TimerCue.tick,
        TimerCue.end,
      ]);

      scheduler.dispose();
    });
  });

  test('a cue that fires 1.5 s late does not play', () {
    fakeAsync((async) {
      final scheduler = newScheduler();
      scheduler.update(
        _timer(
          duration: const Duration(seconds: 15),
          remaining: const Duration(seconds: 4),
        ),
      );

      // The clock jumps with no Timer running: 1.5 s past the countdown's time
      // (0:03), and 0.5 s past the first tick's (0:02).
      async.elapseBlocking(const Duration(milliseconds: 2500));
      async.elapse(Duration.zero);
      expect(played, <TimerCue>[TimerCue.tick]);

      async.elapse(const Duration(milliseconds: 1500));
      expect(played, <TimerCue>[TimerCue.tick, TimerCue.tick, TimerCue.end]);

      scheduler.dispose();
    });
  });

  test('a new deadline cancels the old cues', () {
    fakeAsync((async) {
      final scheduler = newScheduler();
      final timer = _timer(duration: const Duration(seconds: 20));
      scheduler.update(timer);
      async.elapse(const Duration(seconds: 5));

      // +15 s with 15 s left: 30 s from now.
      scheduler.update(
        _timer(
          duration: const Duration(seconds: 35),
          remaining: const Duration(seconds: 30),
        ),
      );

      // The old get ready was due 5 s from now.
      async.elapse(const Duration(seconds: 19));
      expect(played, isEmpty);

      async.elapse(second);
      expect(played, <TimerCue>[TimerCue.getReady]);

      scheduler.dispose();
    });
  });

  test('the same id and deadline arms nothing twice', () {
    fakeAsync((async) {
      final scheduler = newScheduler();
      final timer = _timer(duration: const Duration(seconds: 15));
      scheduler.update(timer);
      async.elapse(second);
      scheduler.update(timer);

      async.elapse(const Duration(seconds: 14));

      expect(played, <TimerCue>[
        TimerCue.countdown,
        TimerCue.tick,
        TimerCue.tick,
        TimerCue.end,
      ]);

      scheduler.dispose();
    });
  });

  test('update(null) cancels all', () {
    fakeAsync((async) {
      final scheduler = newScheduler();
      scheduler.update(_timer(duration: const Duration(seconds: 20)));

      scheduler.update(null);
      async.elapse(const Duration(seconds: 20));

      expect(played, isEmpty);
      expect(async.pendingTimers, isEmpty);

      scheduler.dispose();
    });
  });

  test('dispose cancels all', () {
    fakeAsync((async) {
      final scheduler = newScheduler();
      scheduler.update(_timer(duration: const Duration(seconds: 20)));

      scheduler.dispose();
      async.elapse(const Duration(seconds: 20));

      expect(played, isEmpty);
      expect(async.pendingTimers, isEmpty);
    });
  });
}
