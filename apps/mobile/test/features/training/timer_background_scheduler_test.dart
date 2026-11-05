import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/training/services/timer_background_scheduler.dart';

const RestNotificationTexts _texts = (
  title: 'Rest timer',
  countdownLabel: 'Rest',
  body: 'Rest over',
  getReadyText: 'Get ready · Deadlift · Set 4',
  prepareText: 'Deadlift · Set 4 in 0:03',
);

RestTimerRecord _restTimer({Duration duration = const Duration(minutes: 2)}) {
  return RestTimerRecord(
    id: 'rest-1',
    workoutId: 'workout-1',
    sourceSetId: 'set-1',
    startedAt: DateTime.utc(2026, 6, 16, 8),
    deadlineAt: DateTime.utc(2026, 6, 16, 8, 2),
    duration: duration,
    alertVolume: 0.75,
    status: RestTimerStatus.running,
    updatedAt: DateTime.utc(2026, 6, 16, 8),
  );
}

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
        _restTimer(),
        texts: _texts,
        workoutExerciseId: 'we-1',
      );

      expect(schedule.toPlatformMap(), <String, Object?>{
        'kind': 'rest',
        'timerId': 'rest-1',
        'deadlineAtMillis':
            DateTime.utc(2026, 6, 16, 8, 2).millisecondsSinceEpoch,
        'title': 'Rest timer',
        'body': 'Rest over',
        'countdownLabel': 'Rest',
        'getReadyText': 'Get ready · Deadlift · Set 4',
        'prepareText': 'Deadlift · Set 4 in 0:03',
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
        texts: _texts,
        workoutExerciseId: 'we-9',
        soundEnabled: false,
      );

      final map = schedule.toPlatformMap();
      expect(map['workoutId'], 'workout-9');
      expect(map['workoutExerciseId'], 'we-9');
      expect(map['soundEnabled'], false);
    });

    test('leaves getReadyText out of the map when it is null', () {
      final schedule = TimerBackgroundSchedule.rest(
        _restTimer(),
        texts: (
          title: _texts.title,
          countdownLabel: _texts.countdownLabel,
          body: _texts.body,
          getReadyText: null,
          prepareText: _texts.prepareText,
        ),
      );

      final map = schedule.toPlatformMap();
      expect(map.containsKey('getReadyText'), isFalse);
      expect(map['prepareText'], 'Deadlift · Set 4 in 0:03');
    });

    test('a 15 s timer has no getReadyText even when the text is supplied', () {
      final map = TimerBackgroundSchedule.rest(
        _restTimer(duration: const Duration(seconds: 15)),
        texts: _texts,
      ).toPlatformMap();

      expect(map.containsKey('getReadyText'), isFalse);
    });

    test('a 16 s timer keeps its getReadyText', () {
      final map = TimerBackgroundSchedule.rest(
        _restTimer(duration: const Duration(seconds: 16)),
        texts: _texts,
      ).toPlatformMap();

      expect(map['getReadyText'], 'Get ready · Deadlift · Set 4');
    });

    test('setInAppTimerCues invokes the method with the value', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });

      final scheduler = MethodChannelTimerBackgroundScheduler(channel: channel);
      await scheduler.setInAppTimerCues(true);

      expect(calls.single.method, 'setInAppTimerCues');
      expect(calls.single.arguments, <String, Object?>{'active': true});
    });

    test('setInAppTimerCues swallows a missing native side', () async {
      final scheduler = MethodChannelTimerBackgroundScheduler(
        channel: const MethodChannel('test_timer_background_missing'),
      );

      await expectLater(scheduler.setInAppTimerCues(false), completes);
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
          body: 'Rest over',
          countdownLabel: 'Rest',
          prepareText: 'Deadlift · Set 4 in 0:03',
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
          prepareText: 'Interval 2/8 in 0:03',
        ),
      );

      expect(status, TimerBackgroundPermissionStatus.denied);
      expect(
        calls.map((call) => call.method),
        <String>['requestNotificationPermissionIfNeeded'],
      );
    });

    group('a cancel during the permission wait', () {
      TimerBackgroundSchedule scheduleAt(DateTime deadlineAt) {
        return TimerBackgroundSchedule(
          kind: TimerBackgroundKind.rest,
          timerId: 'rest-1',
          deadlineAt: deadlineAt,
          title: 'Rest timer',
          body: 'Rest over',
          countdownLabel: 'Rest',
          prepareText: 'Deadlift · Set 4 in 0:03',
        );
      }

      /// Holds each permission answer until its completer is completed, the
      /// way the system prompt does on the first-ever rest.
      (List<MethodCall>, List<Completer<String>>) holdPermission() {
        final calls = <MethodCall>[];
        final answers = <Completer<String>>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          if (call.method == 'requestNotificationPermissionIfNeeded') {
            final answer = Completer<String>();
            answers.add(answer);
            return answer.future;
          }
          return Future<Object?>.value('granted');
        });
        return (calls, answers);
      }

      test('the schedule is never sent, so the end stays silent', () async {
        final (calls, answers) = holdPermission();
        final scheduler =
            MethodChannelTimerBackgroundScheduler(channel: channel);

        final status = scheduler.schedule(
          scheduleAt(DateTime.utc(2026, 6, 16, 8, 2)),
        );
        await pumpEventQueue();
        await scheduler.cancel('rest-1');
        answers.single.complete('granted');

        expect(await status, TimerBackgroundPermissionStatus.granted);
        expect(
          calls.map((call) => call.method),
          <String>['requestNotificationPermissionIfNeeded', 'cancelTimer'],
        );
      });

      test('only the latest schedule of the rest is sent', () async {
        final (calls, answers) = holdPermission();
        final scheduler =
            MethodChannelTimerBackgroundScheduler(channel: channel);
        final adjustedDeadline = DateTime.utc(2026, 6, 16, 8, 3);

        final first = scheduler.schedule(
          scheduleAt(DateTime.utc(2026, 6, 16, 8, 2)),
        );
        await pumpEventQueue();
        await scheduler.cancel('rest-1');
        final second = scheduler.schedule(scheduleAt(adjustedDeadline));
        await pumpEventQueue();
        answers[0].complete('granted');
        answers[1].complete('granted');
        await Future.wait([first, second]);

        final sent = calls.where((call) => call.method == 'scheduleTimer');
        expect(sent, hasLength(1));
        expect(
          (sent.single.arguments as Map)['deadlineAtMillis'],
          adjustedDeadline.millisecondsSinceEpoch,
        );
      });

      test('another rest\'s cancel does not stop the schedule', () async {
        final (calls, answers) = holdPermission();
        final scheduler =
            MethodChannelTimerBackgroundScheduler(channel: channel);

        final status = scheduler.schedule(
          scheduleAt(DateTime.utc(2026, 6, 16, 8, 2)),
        );
        await pumpEventQueue();
        await scheduler.cancel('rest-2');
        answers.single.complete('granted');
        await status;

        expect(calls.last.method, 'scheduleTimer');
      });
    });

    group('notificationPermissionStatus (read-only, D5)', () {
      Future<(TimerBackgroundPermissionStatus, List<MethodCall>)> statusFor(
        Future<Object?> Function(MethodCall call) handler,
      ) async {
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return handler(call);
        });
        final scheduler =
            MethodChannelTimerBackgroundScheduler(channel: channel);
        return (await scheduler.notificationPermissionStatus(), calls);
      }

      test('maps every channel value, and never asks', () async {
        final cases = <Object?, TimerBackgroundPermissionStatus>{
          'granted': TimerBackgroundPermissionStatus.granted,
          'denied': TimerBackgroundPermissionStatus.denied,
          'notDetermined': TimerBackgroundPermissionStatus.notDetermined,
          'unsupported': TimerBackgroundPermissionStatus.unsupported,
          'something-new': TimerBackgroundPermissionStatus.unsupported,
          null: TimerBackgroundPermissionStatus.unsupported,
        };
        for (final entry in cases.entries) {
          final (status, calls) = await statusFor((_) async => entry.key);
          expect(status, entry.value, reason: 'channel value ${entry.key}');
          expect(
            calls.map((call) => call.method),
            <String>['notificationPermissionStatus'],
            reason: 'a status read is one read-only call',
          );
        }
      });

      test('reads a denial error as denied', () async {
        final (status, _) = await statusFor((_) async {
          throw PlatformException(code: 'notification_permission_denied');
        });
        expect(status, TimerBackgroundPermissionStatus.denied);
      });

      test('reads a missing native side as unsupported', () async {
        final scheduler = MethodChannelTimerBackgroundScheduler(
          channel: const MethodChannel('test_timer_background_missing'),
        );
        expect(
          await scheduler.notificationPermissionStatus(),
          TimerBackgroundPermissionStatus.unsupported,
        );
      });
    });
  });
}
