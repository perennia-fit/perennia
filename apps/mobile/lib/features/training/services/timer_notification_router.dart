import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../exercise/widgets/exercise_page.dart';

/// Prefix for the [RouteSettings.name] the timer-tap router pushes with, so a
/// duplicate tap can be recognised and de-duplicated.
String timerExerciseRouteName(String workoutExerciseId) =>
    '/exercise/$workoutExerciseId';

/// Builds the [ExercisePage] route for [workoutExerciseId], named via
/// [timerExerciseRouteName] so every entry point (a manual card tap, landing
/// on a just-added exercise, or a background timer-notification tap) agrees
/// on the route-naming convention [TimerNotificationRouter] relies on to
/// de-duplicate a repeat tap. Shared so the route construction itself isn't
/// hand-copied at each push site.
MaterialPageRoute<void> buildExercisePageRoute(
  String workoutExerciseId, {
  WidgetBuilder? pageBuilder,
}) {
  return MaterialPageRoute<void>(
    settings: RouteSettings(name: timerExerciseRouteName(workoutExerciseId)),
    builder: pageBuilder ??
        (_) => ExercisePage(workoutExerciseId: workoutExerciseId),
  );
}

/// Routes a background timer-notification tap back to the exercise that owns
/// the timer.
///
/// The native side (Android `MainActivity`, iOS `AppDelegate`) forwards a tap
/// over the timer-background method channel as `onTimerNotificationTapped`
/// with the ids captured at scheduling time. A cold-start tap is buffered
/// natively until [signalReady] tells the platform Flutter is up.
class TimerNotificationRouter {
  TimerNotificationRouter({
    required GlobalKey<NavigatorState> navigatorKey,
    required GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey,
    required Future<WorkoutExerciseRecord?> Function(String id)
        resolveWorkoutExercise,
    MethodChannel channel = const MethodChannel(
      'open_workout_logger/timer_background',
    ),
    WidgetBuilder Function(String workoutExerciseId)? pageBuilder,
  })  : _navigatorKey = navigatorKey,
        _scaffoldMessengerKey = scaffoldMessengerKey,
        _resolveWorkoutExercise = resolveWorkoutExercise,
        _channel = channel,
        _pageBuilder = pageBuilder ?? _defaultPageBuilder;

  final GlobalKey<NavigatorState> _navigatorKey;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;
  final Future<WorkoutExerciseRecord?> Function(String id)
      _resolveWorkoutExercise;
  final MethodChannel _channel;
  final WidgetBuilder Function(String workoutExerciseId) _pageBuilder;

  static WidgetBuilder _defaultPageBuilder(String workoutExerciseId) {
    return (_) => ExercisePage(workoutExerciseId: workoutExerciseId);
  }

  static const _missingExerciseMessage =
      'That exercise is no longer in the workout';

  /// Wires the receive handler and tells the platform we are ready to drain any
  /// buffered cold-start tap. Call once after the first frame.
  void start() {
    _channel.setMethodCallHandler(_handleCall);
    unawaited(_signalReady());
  }

  Future<void> _signalReady() async {
    try {
      await _channel.invokeMethod<void>('timerNotificationsReady');
    } on MissingPluginException {
      // No native side (e.g. tests / unsupported platform): nothing to drain.
    }
  }

  Future<Object?> _handleCall(MethodCall call) async {
    if (call.method != 'onTimerNotificationTapped') {
      return null;
    }
    final arguments = call.arguments;
    if (arguments is! Map) {
      return null;
    }
    final workoutExerciseId = arguments['workoutExerciseId'] as String?;
    if (workoutExerciseId == null || workoutExerciseId.isEmpty) {
      return null;
    }
    await handleTap(workoutExerciseId);
    return null;
  }

  /// Visible for the router tests; also the single funnel from [_handleCall].
  @visibleForTesting
  Future<void> handleTap(String workoutExerciseId) async {
    final record = await _resolveWorkoutExercise(workoutExerciseId);
    // Archived / deleted target: getById may still return the row, so also
    // reject a soft-deleted one.
    if (record == null || record.deletedAt != null) {
      _scaffoldMessengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text(_missingExerciseMessage)),
        );
      return;
    }

    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    final routeName = timerExerciseRouteName(workoutExerciseId);
    if (_isTopRoute(navigator, routeName)) {
      // Duplicate tap for the exercise already on top: no-op.
      return;
    }

    unawaited(
      navigator.push(
        buildExercisePageRoute(
          workoutExerciseId,
          pageBuilder: _pageBuilder(workoutExerciseId),
        ),
      ),
    );
  }

  bool _isTopRoute(NavigatorState navigator, String routeName) {
    var isTop = false;
    navigator.popUntil((route) {
      isTop = route.settings.name == routeName;
      return true; // Inspect the top route only; never actually pop.
    });
    return isTop;
  }
}

/// Overridable so tests can inject a fake router.
final timerNotificationRouterProvider = Provider<TimerNotificationRouter?>(
  (ref) => null,
);
