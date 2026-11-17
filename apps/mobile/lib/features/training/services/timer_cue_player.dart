import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'rest_cues.dart';

final timerCuePlayerProvider = Provider<TimerCuePlayer>(
  (ref) => const MethodChannelTimerCuePlayer(),
);

/// Plays a rest's cues in the app.
abstract interface class TimerCuePlayer {
  /// Loads the tones, so the first cue is never lost to a load.
  Future<void> prepare();

  /// Plays [cue]'s tone and vibration. [volume] is 0 to 1.
  Future<void> play(TimerCue cue, {required double volume});
}

class MethodChannelTimerCuePlayer implements TimerCuePlayer {
  const MethodChannelTimerCuePlayer({
    MethodChannel channel = _defaultChannel,
  }) : _channel = channel;

  static const _defaultChannel = MethodChannel('perennia/timer_background');

  final MethodChannel _channel;

  @override
  Future<void> prepare() async {
    try {
      await _channel.invokeMethod<void>('prepareCues');
    } on MissingPluginException {
      return;
    }
  }

  @override
  Future<void> play(TimerCue cue, {required double volume}) async {
    try {
      await _channel.invokeMethod<void>('playCue', <String, Object?>{
        'cue': cue.name,
        'volume': volume,
      });
    } on MissingPluginException {
      return;
    }
  }
}
