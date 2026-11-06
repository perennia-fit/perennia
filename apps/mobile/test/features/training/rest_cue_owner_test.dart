import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/features/training/services/rest_cue_owner.dart';
import 'package:perennia/features/training/services/timer_background_scheduler.dart';

class _FakeScheduler implements TimerBackgroundScheduler {
  final sent = <bool>[];

  @override
  Future<void> setInAppTimerCues(bool active) async {
    sent.add(active);
  }

  @override
  Future<TimerBackgroundPermissionStatus> requestPermissionIfNeeded() async {
    return TimerBackgroundPermissionStatus.granted;
  }

  @override
  Future<TimerBackgroundPermissionStatus> notificationPermissionStatus() async {
    return TimerBackgroundPermissionStatus.granted;
  }

  @override
  Future<TimerBackgroundPermissionStatus> schedule(
    TimerBackgroundSchedule schedule,
  ) async {
    return TimerBackgroundPermissionStatus.granted;
  }

  @override
  Future<void> cancel(String timerId) async {}
}

void main() {
  late _FakeScheduler scheduler;
  late RestCueOwner owner;
  final first = Object();
  final second = Object();

  setUp(() {
    scheduler = _FakeScheduler();
    final container = ProviderContainer(
      overrides: [
        timerBackgroundSchedulerProvider.overrideWithValue(scheduler),
      ],
    );
    addTearDown(container.dispose);
    owner = container.read(restCueOwnerProvider);
  });

  test('true is sent once, and not again while either strip is current', () {
    owner.report(first, current: true);
    expect(scheduler.sent, <bool>[true]);

    owner.report(first, current: true);
    owner.report(second, current: true);
    owner.report(first, current: false);
    owner.report(first, current: true);
    expect(scheduler.sent, <bool>[true]);
  });

  test('false is sent when both strips are not current', () {
    owner.report(first, current: true);
    owner.report(second, current: true);

    owner.report(first, current: false);
    expect(scheduler.sent, <bool>[true]);

    owner.report(second, current: false);
    expect(scheduler.sent, <bool>[true, false]);
  });

  test('false is sent when both strips are removed', () {
    owner.report(first, current: true);
    owner.report(second, current: true);

    owner.remove(first);
    expect(scheduler.sent, <bool>[true]);

    owner.remove(second);
    expect(scheduler.sent, <bool>[true, false]);
  });

  test('the first value is always sent, even false', () {
    owner.report(first, current: false);
    expect(scheduler.sent, <bool>[false]);

    owner.report(second, current: false);
    expect(scheduler.sent, <bool>[false]);
  });
}
