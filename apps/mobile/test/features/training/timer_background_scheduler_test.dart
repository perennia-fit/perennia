import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/training/services/timer_background_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('timer background scheduler', () {
    const channel = MethodChannel('test_timer_background');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('maps rest timers to native schedule payloads', () {
      final schedule = TimerBackgroundSchedule.rest(
        RestTimerRecord(
          id: 'rest-1',
          workoutId: 'workout-1',
          sourceSetId: 'set-1',
          startedAt: DateTime.utc(2026, 6, 16, 8),
          deadlineAt: DateTime.utc(2026, 6, 16, 8, 2),
          duration: const Duration(minutes: 2),
          alertVolume: 0.75,
          status: RestTimerStatus.running,
          updatedAt: DateTime.utc(2026, 6, 16, 8),
        ),
        workoutExerciseId: 'we-1',
      );

      expect(schedule.toPlatformMap(), <String, Object?>{
        'kind': 'rest',
        'timerId': 'rest-1',
        'deadlineAtMillis':
            DateTime.utc(2026, 6, 16, 8, 2).millisecondsSinceEpoch,
        'title': 'Rest timer',
        'body': 'Rest timer complete',
        'countdownLabel': 'Rest',
        // tap-to-return ids + the device-level sound flag.
        'workoutId': 'workout-1',
        'workoutExerciseId': 'we-1',
        'soundEnabled': true,
      });
    });

    test('carries the workoutExerciseId and soundEnabled flag through', () {
      final schedule = TimerBackgroundSchedule.rest(
        RestTimerRecord(
          id: 'rest-2',
          workoutId: 'workout-9',
          sourceSetId: null,
          startedAt: DateTime.utc(2026, 6, 16, 8),
          deadlineAt: DateTime.utc(2026, 6, 16, 8, 2),
          duration: const Duration(minutes: 2),
          alertVolume: 1,
          status: RestTimerStatus.running,
          updatedAt: DateTime.utc(2026, 6, 16, 8),
        ),
        workoutExerciseId: 'we-9',
        soundEnabled: false,
      );

      final map = schedule.toPlatformMap();
      expect(map['workoutId'], 'workout-9');
      expect(map['workoutExerciseId'], 'we-9');
      expect(map['soundEnabled'], false);
    });

    test('requests notification permission before scheduling', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return 'granted';
      });

      final scheduler = MethodChannelTimerBackgroundScheduler(channel: channel);
      final status = await scheduler.schedule(
        TimerBackgroundSchedule(
          kind: TimerBackgroundKind.rest,
          timerId: 'rest-1',
          deadlineAt: DateTime.utc(2026, 6, 16, 8, 2),
          title: 'Rest timer',
          body: 'Rest timer complete',
          countdownLabel: 'Rest',
        ),
      );

      expect(status, TimerBackgroundPermissionStatus.granted);
      expect(
        calls.map((call) => call.method),
        <String>['requestNotificationPermissionIfNeeded', 'scheduleTimer'],
      );
    });

    test('does not schedule when notification permission is denied', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return 'denied';
      });

      final scheduler = MethodChannelTimerBackgroundScheduler(channel: channel);
      final status = await scheduler.schedule(
        TimerBackgroundSchedule(
          kind: TimerBackgroundKind.interval,
          timerId: 'interval-1',
          deadlineAt: DateTime.utc(2026, 6, 16, 8, 20),
          title: 'Work interval',
          body: 'Interval 1/8 complete',
          countdownLabel: 'Work',
        ),
      );

      expect(status, TimerBackgroundPermissionStatus.denied);
      expect(
        calls.map((call) => call.method),
        <String>['requestNotificationPermissionIfNeeded'],
      );
    });
  });
}
