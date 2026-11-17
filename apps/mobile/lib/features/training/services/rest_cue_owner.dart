import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'timer_background_scheduler.dart';

/// Kept alive for the app's life (not autoDispose), so the last value sent
/// outlives any one strip.
final restCueOwnerProvider = Provider<RestCueOwner>(
  (ref) => RestCueOwner(ref.read(timerBackgroundSchedulerProvider)),
);

/// Tells native whether a rest strip on the current route is showing a running
/// rest, which is what keeps a cue's notification from posting while the app
/// plays that cue.
///
/// It keeps one entry per mounted strip because the router can push a second
/// Training Screen over the first, and only the top one is current. An entry is
/// false for a strip with no running rest: a rest running in another Workout
/// has no strip to play its cues, so its notifications must still post.
class RestCueOwner {
  RestCueOwner(this._scheduler);

  final TimerBackgroundScheduler _scheduler;
  final _strips = <Object, bool>{};

  /// Null until the first send: native starts each engine at false, but the
  /// first value after the app starts is always sent, whatever it is.
  bool? _lastSent;

  void report(Object strip, {required bool current}) {
    _strips[strip] = current;
    _sendIfChanged();
  }

  void remove(Object strip) {
    _strips.remove(strip);
    _sendIfChanged();
  }

  void _sendIfChanged() {
    final active = _strips.values.any((current) => current);
    if (active == _lastSent) {
      return;
    }
    _lastSent = active;
    unawaited(_scheduler.setInAppTimerCues(active));
  }
}
