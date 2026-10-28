import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';

final timerBackgroundSchedulerProvider = Provider<TimerBackgroundScheduler>(
  (ref) => const MethodChannelTimerBackgroundScheduler(),
);

abstract interface class TimerBackgroundScheduler {
  /// Asks for the system notification permission when it can still be
  /// asked, and answers [TimerBackgroundPermissionStatus.granted] or
  /// [TimerBackgroundPermissionStatus.denied] (or unsupported). The one
  /// permission path: Supplement reminders reuse it (D5).
  Future<TimerBackgroundPermissionStatus> requestPermissionIfNeeded();

  /// Reads the system notification permission without prompting (D5,
  /// file 51), including [TimerBackgroundPermissionStatus.notDetermined]
  /// when the user has never been asked.
  Future<TimerBackgroundPermissionStatus> notificationPermissionStatus();

  Future<TimerBackgroundPermissionStatus> schedule(
    TimerBackgroundSchedule schedule,
  );

  Future<void> cancel(String timerId);
}

enum TimerBackgroundPermissionStatus {
  granted,
  denied,

  /// Not granted, and never asked for: requesting it would show the system
  /// prompt. Only [TimerBackgroundScheduler.notificationPermissionStatus]
  /// reports it.
  notDetermined,
  unsupported,
}

enum TimerBackgroundKind {
  rest,
  interval,
}

class TimerBackgroundSchedule {
  const TimerBackgroundSchedule({
    required this.kind,
    required this.timerId,
    required this.deadlineAt,
    required this.title,
    required this.body,
    required this.countdownLabel,
    this.workoutId,
    this.workoutExerciseId,
    this.soundEnabled = true,
  });

  factory TimerBackgroundSchedule.rest(
    RestTimerRecord timer, {
    String? workoutExerciseId,
    bool soundEnabled = true,
  }) {
    return TimerBackgroundSchedule(
      kind: TimerBackgroundKind.rest,
      timerId: timer.id,
      deadlineAt: timer.deadlineAt.toUtc(),
      title: 'Rest timer',
      body: 'Rest timer complete',
      countdownLabel: 'Rest',
      workoutId: timer.workoutId,
      workoutExerciseId: workoutExerciseId,
      soundEnabled: soundEnabled,
    );
  }

  final TimerBackgroundKind kind;
  final String timerId;
  final DateTime deadlineAt;
  final String title;
  final String body;
  final String countdownLabel;

  /// Ids the notification carries so a tap can return to the exercise.
  /// `workoutExerciseId` is the active exercise at scheduling time;
  /// both are null when unknown (e.g. an ad-hoc rest timer with no workout).
  final String? workoutId;
  final String? workoutExerciseId;

  /// When false, native prepare/completion notifications post WITHOUT their
  /// custom sound (silent/default-importance), keeping the visual notification.
  /// Mirrors the device-level `restTimerSoundsEnabled` setting.
  final bool soundEnabled;

  Map<String, Object?> toPlatformMap() {
    return <String, Object?>{
      'kind': kind.name,
      'timerId': timerId,
      'deadlineAtMillis': deadlineAt.millisecondsSinceEpoch,
      'title': title,
      'body': body,
      'countdownLabel': countdownLabel,
      'workoutId': workoutId,
      'workoutExerciseId': workoutExerciseId,
      'soundEnabled': soundEnabled,
    };
  }
}

class MethodChannelTimerBackgroundScheduler
    implements TimerBackgroundScheduler {
  const MethodChannelTimerBackgroundScheduler({
    MethodChannel channel = _defaultChannel,
  }) : _channel = channel;

  static const _defaultChannel = MethodChannel(
    'perennia/timer_background',
  );

  final MethodChannel _channel;

  @override
  Future<TimerBackgroundPermissionStatus> requestPermissionIfNeeded() {
    return _invokeStatus('requestNotificationPermissionIfNeeded');
  }

  @override
  Future<TimerBackgroundPermissionStatus> notificationPermissionStatus() {
    return _invokeStatus('notificationPermissionStatus');
  }

  @override
  Future<TimerBackgroundPermissionStatus> schedule(
    TimerBackgroundSchedule schedule,
  ) async {
    final permission = await requestPermissionIfNeeded();
    if (permission != TimerBackgroundPermissionStatus.granted) {
      return permission;
    }

    return _invokeStatus('scheduleTimer', schedule.toPlatformMap());
  }

  @override
  Future<void> cancel(String timerId) async {
    try {
      await _channel.invokeMethod<void>('cancelTimer', <String, Object?>{
        'timerId': timerId,
      });
    } on MissingPluginException {
      return;
    }
  }

  Future<TimerBackgroundPermissionStatus> _invokeStatus(
    String method, [
    Object? arguments,
  ]) async {
    try {
      final result = await _channel.invokeMethod<String>(method, arguments);
      return _statusFromPlatform(result);
    } on MissingPluginException {
      return TimerBackgroundPermissionStatus.unsupported;
    } on PlatformException catch (error) {
      if (error.code == 'notification_permission_denied') {
        return TimerBackgroundPermissionStatus.denied;
      }
      rethrow;
    }
  }
}

TimerBackgroundPermissionStatus _statusFromPlatform(String? value) {
  return switch (value) {
    'granted' => TimerBackgroundPermissionStatus.granted,
    'denied' => TimerBackgroundPermissionStatus.denied,
    'notDetermined' => TimerBackgroundPermissionStatus.notDetermined,
    _ => TimerBackgroundPermissionStatus.unsupported,
  };
}
