import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import 'rest_cues.dart';

/// The finished, localized strings a rest's notifications show. Native code
/// cannot read the ARB file, so the schedule carries them. They are computed
/// once, when the rest is scheduled: sending the schedule again for a new
/// label would start a new schedule, which could post a threshold the lifter
/// already heard.
///
/// [getReadyText] is the cue's text whatever the rest's length;
/// [TimerBackgroundSchedule.rest] decides whether the cue is sent.
typedef RestNotificationTexts = ({
  String title,
  String countdownLabel,
  String body,
  String? getReadyText,
  String prepareText,
});

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

  /// Tells native whether a rest strip on the current route is playing the
  /// cues in the app. While the app is visible and this is true, native posts
  /// no cue notification, so each moment has one cue.
  Future<void> setInAppTimerCues(bool active);
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
    required this.prepareText,
    this.getReadyText,
    this.workoutId,
    this.workoutExerciseId,
    this.soundEnabled = true,
  });

  /// The one place that decides get-ready: a rest not longer than
  /// [getReadyAfterRest] gets no cue on either platform. It reads
  /// `timer.duration`, not the form's Rest after, because −15 s and +15 s move
  /// the running timer's duration and a Set's planned rest can start it, so
  /// the form's value can differ from the rest that runs.
  factory TimerBackgroundSchedule.rest(
    RestTimerRecord timer, {
    required RestNotificationTexts texts,
    String? workoutExerciseId,
    bool soundEnabled = true,
  }) {
    return TimerBackgroundSchedule(
      kind: TimerBackgroundKind.rest,
      timerId: timer.id,
      deadlineAt: timer.deadlineAt.toUtc(),
      title: texts.title,
      body: texts.body,
      countdownLabel: texts.countdownLabel,
      prepareText: texts.prepareText,
      getReadyText:
          timer.duration > getReadyAfterRest ? texts.getReadyText : null,
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

  /// The text of the notification 10 seconds before the deadline; null means
  /// no get-ready cue.
  final String? getReadyText;

  /// The text of the notification 3 seconds before the deadline.
  final String prepareText;

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
      if (getReadyText != null) 'getReadyText': getReadyText,
      'prepareText': prepareText,
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

  @override
  Future<void> setInAppTimerCues(bool active) async {
    try {
      await _channel.invokeMethod<void>('setInAppTimerCues', <String, Object?>{
        'active': active,
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
