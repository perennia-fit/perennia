import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../settings/repositories/settings_repository.dart';
import '../services/timer_background_scheduler.dart';

final restTimerAlertProvider = Provider<RestTimerAlert>(
  (ref) => const SystemRestTimerAlert(),
);

abstract interface class RestTimerAlert {
  /// The end cue: rest/interval bout is over.
  Future<void> fire(double volume);

  /// The 3-2-1 prepare cue: rest ends soon (remaining <= 3s). A lighter,
  /// distinct signal from [fire] so the two are never confused.
  Future<void> firePrepare(double volume);
}

class SystemRestTimerAlert implements RestTimerAlert {
  const SystemRestTimerAlert();

  @override
  Future<void> fire(double volume) async {
    await HapticFeedback.vibrate();
    if (volume > 0) {
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  @override
  Future<void> firePrepare(double volume) async {
    // Lighter than the end cue: a selection click + a short click tone, paired
    // so vibration is never the sole signal. Sound honors the volume slider;
    // the platform still respects silent mode / DND.
    await HapticFeedback.selectionClick();
    if (volume > 0) {
      await SystemSound.play(SystemSoundType.click);
    }
  }
}

/// Shows "Background timer alerts are off" when scheduling the background
/// notification was refused; the in-app timer runs either way.
void notifyIfBackgroundAlertsDenied(
  BuildContext context,
  TimerBackgroundPermissionStatus status,
) {
  if (status != TimerBackgroundPermissionStatus.denied || !context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        context.l10n.trainingBackgroundAlertsDenied,
      ),
    ),
  );
}

/// A rest as "m:ss" (minutes not capped at 59), for Rest after and the strip.
String formatRestDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// The rest strip, pinned directly above Log set on the Training Screen.
///
/// Running, it shows "Rest m:ss" with −15 s, +15 s and Stop; idle, it shows
/// Start rest, which starts [rest] (the form's Rest after) and is disabled
/// at Off. Tapping the remaining time opens the alert volume sheet.
///
/// It is the rest timer's **one owner**: the Training Screen keeps it at the
/// same place in its tree while it switches exercises, so this state (the
/// ticker, the 3-2-1 prepare cue, the end alert and the background
/// schedule) is never torn down mid-rest, and no other screen fires a rest
/// alert.
class RestStrip extends ConsumerStatefulWidget {
  const RestStrip({
    super.key,
    required this.workoutId,
    required this.workoutExerciseId,
    required this.rest,
    required this.enableTicker,
    required this.revision,
    required this.onAlertVolumeChanged,
  });

  static const stripKey = Key('training.restStrip');
  static const stopKey = Key('training.restStrip.stop');
  static const startKey = Key('training.restStrip.start');
  static const volumeSliderKey = Key('training.restTimer.volume');

  /// How far one tap on −15 s or +15 s moves a running rest.
  static const adjustStep = Duration(seconds: 15);

  static Key adjustKey(int seconds) {
    return Key('training.restStrip.adjust.$seconds');
  }

  final String workoutId;

  /// The exercise on screen; the background notification returns to it.
  final String workoutExerciseId;

  /// The form's Rest after, which Start rest starts.
  final Duration rest;
  final bool enableTicker;

  /// Bumped by the screen after it writes the timer (Log set, Undo), so a
  /// strip without the ticker reloads it.
  final int revision;

  /// Reports the strip's volume (the slider, or a loaded timer's volume),
  /// which Log set's timer starts with.
  final ValueChanged<double> onAlertVolumeChanged;

  @override
  ConsumerState<RestStrip> createState() => _RestStripState();
}

class _RestStripState extends ConsumerState<RestStrip> {
  Stream<RestTimerRecord?>? _timerStream;
  late Future<RestTimerRecord?> _timerFuture;
  Timer? _ticker;
  DateTime _now = DateTime.now().toUtc();
  String? _renderedTimerId;
  RestTimerRecord? _timer;
  double _alertVolume = RestTimerRepository.defaultAlertVolume;
  final _alertsInFlight = <String>{};
  final _prepareAlertsInFlight = <String>{};

  @override
  void initState() {
    super.initState();
    _timerFuture = _loadTimer(widget.workoutId);
    if (widget.enableTicker) {
      _timerStream = _watchTimer(widget.workoutId);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _now = DateTime.now().toUtc());
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant RestStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workoutId != widget.workoutId ||
        oldWidget.revision != widget.revision) {
      _timerStream = widget.enableTicker ? _watchTimer(widget.workoutId) : null;
      _timerFuture = _loadTimer(widget.workoutId);
      _renderedTimerId = null;
      _now = DateTime.now().toUtc();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.enableTicker) {
      return StreamBuilder<RestTimerRecord?>(
        stream: _timerStream!,
        builder: (context, snapshot) => _buildStrip(context, snapshot.data),
      );
    }

    return FutureBuilder<RestTimerRecord?>(
      future: _timerFuture,
      builder: (context, snapshot) => _buildStrip(context, snapshot.data),
    );
  }

  Stream<RestTimerRecord?> _watchTimer(String workoutId) {
    return ref
        .read(trainingRepositoriesProvider)
        .restTimers
        .watchCurrentForWorkout(workoutId);
  }

  Future<RestTimerRecord?> _loadTimer(String workoutId) {
    return ref
        .read(trainingRepositoriesProvider)
        .restTimers
        .getCurrentForWorkout(workoutId);
  }

  Widget _buildStrip(BuildContext context, RestTimerRecord? timer) {
    _timer = timer;
    _syncVolume(timer);
    if (timer != null &&
        timer.status == RestTimerStatus.running &&
        timer.alertFiredAt == null &&
        timer.isExpiredAt(_now)) {
      _queueAlert(timer);
    } else if (timer != null &&
        timer.status == RestTimerStatus.running &&
        timer.alertFiredAt == null &&
        timer.prepareAlertFiredAt == null &&
        _isWithinPrepareWindow(timer)) {
      _queuePrepareAlert(timer);
    }

    final remaining = timer?.remainingAt(_now) ?? Duration.zero;
    final running = timer != null &&
        timer.status == RestTimerStatus.running &&
        remaining > Duration.zero;

    return DecoratedBox(
      key: RestStrip.stripKey,
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.divider),
        borderRadius: AppRadii.cardMd,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.dense),
        child: running
            ? _buildRunning(context, timer, remaining)
            : _buildIdle(context),
      ),
    );
  }

  Widget _buildRunning(
    BuildContext context,
    RestTimerRecord timer,
    Duration remaining,
  ) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: TextButton(
            style: TextButton.styleFrom(
              alignment: AlignmentDirectional.centerStart,
              minimumSize: const Size(0, AppDimens.touchTarget),
            ),
            onPressed: _showVolumeSheet,
            child: Semantics(
              label: l10n.trainingRestStripRemainingLabel(
                remaining.inMinutes,
                remaining.inSeconds.remainder(60),
              ),
              child: ExcludeSemantics(
                child: Text(
                  l10n.trainingRestCountdown(formatRestDuration(remaining)),
                  style: context.textStyles.numeralRow.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
        _AdjustButton(
          seconds: -RestStrip.adjustStep.inSeconds,
          text: l10n.trainingRestStripShorten,
          label: l10n.trainingRestStripShortenLabel,
          onPressed: () => unawaited(_adjust(timer, -RestStrip.adjustStep)),
        ),
        _AdjustButton(
          seconds: RestStrip.adjustStep.inSeconds,
          text: l10n.trainingRestStripLengthen,
          label: l10n.trainingRestStripLengthenLabel,
          onPressed: () => unawaited(_adjust(timer, RestStrip.adjustStep)),
        ),
        IconButton(
          key: RestStrip.stopKey,
          tooltip: l10n.trainingStopRestTooltip,
          onPressed: () => unawaited(_stop(timer.id)),
          icon: const Icon(Icons.stop),
        ),
      ],
    );
  }

  Widget _buildIdle(BuildContext context) {
    final rest = widget.rest;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        key: RestStrip.startKey,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, AppDimens.touchTarget),
        ),
        onPressed: rest > Duration.zero ? () => unawaited(_start(rest)) : null,
        icon: const Icon(Icons.timer_outlined),
        label: Text(context.l10n.trainingStartRest),
      ),
    );
  }

  /// A newly shown timer brings its own volume, which Log set then reuses.
  void _syncVolume(RestTimerRecord? timer) {
    if (timer?.id == _renderedTimerId) {
      return;
    }
    _renderedTimerId = timer?.id;
    if (timer != null) {
      _alertVolume = timer.alertVolume;
      widget.onAlertVolumeChanged(timer.alertVolume);
    }
  }

  Future<void> _showVolumeSheet() {
    return showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return _RestVolumeSheet(
          initialVolume: _alertVolume,
          onChanged: _setVolume,
        );
      },
    );
  }

  void _setVolume(double volume) {
    if (!mounted) {
      return;
    }
    setState(() => _alertVolume = volume);
    widget.onAlertVolumeChanged(volume);
    final timer = _timer;
    if (timer != null && timer.status == RestTimerStatus.running) {
      unawaited(
        ref
            .read(trainingRepositoriesProvider)
            .restTimers
            .updateAlertVolume(timer.id, alertVolume: volume)
            .then((_) => _refreshTimer()),
      );
    }
  }

  Future<void> _start(Duration rest) async {
    final repository = ref.read(trainingRepositoriesProvider).restTimers;
    final timerId = await repository.start(
      RestTimerDraft(
        workoutId: widget.workoutId,
        duration: rest,
        alertVolume: _alertVolume,
      ),
    );
    final timer = await repository.getById(timerId);
    if (timer != null) {
      final status = await _scheduleBackground(timer);
      if (mounted) {
        notifyIfBackgroundAlertsDenied(context, status);
      }
    }
    _refreshTimer();
  }

  /// −15 s / +15 s. The background notification is cancelled and scheduled
  /// again at the new deadline; when the adjust left no time, it is not
  /// rescheduled, because the strip fires the end alert on its next tick
  /// (and a notification at "now" would ring on top of it). A refused
  /// permission was already reported when the rest started, so it is not
  /// reported again on every tap.
  Future<void> _adjust(RestTimerRecord timer, Duration delta) async {
    final repository = ref.read(trainingRepositoriesProvider).restTimers;
    final scheduler = ref.read(timerBackgroundSchedulerProvider);
    await repository.adjust(timer.id, delta);
    await scheduler.cancel(timer.id);
    final adjusted = await repository.getById(timer.id);
    if (adjusted != null &&
        adjusted.status == RestTimerStatus.running &&
        adjusted.remainingAt(DateTime.now().toUtc()) > Duration.zero) {
      await _scheduleBackground(adjusted);
    }
    _refreshTimer();
  }

  Future<void> _stop(String timerId) async {
    await ref.read(trainingRepositoriesProvider).restTimers.cancel(timerId);
    await ref.read(timerBackgroundSchedulerProvider).cancel(timerId);
    _refreshTimer();
  }

  Future<TimerBackgroundPermissionStatus> _scheduleBackground(
    RestTimerRecord timer,
  ) {
    return ref.read(timerBackgroundSchedulerProvider).schedule(
          TimerBackgroundSchedule.rest(
            timer,
            workoutExerciseId: widget.workoutExerciseId,
            soundEnabled: _restTimerSoundsEnabled(),
          ),
        );
  }

  void _refreshTimer() {
    if (!mounted || widget.enableTicker) {
      return;
    }
    setState(() {
      _timerFuture = _loadTimer(widget.workoutId);
      _renderedTimerId = null;
      _now = DateTime.now().toUtc();
    });
  }

  void _queueAlert(RestTimerRecord timer) {
    if (!_alertsInFlight.add(timer.id)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_fireAlert(timer));
    });
  }

  Future<void> _fireAlert(RestTimerRecord timer) async {
    try {
      if (_restTimerSoundsEnabled()) {
        await ref.read(restTimerAlertProvider).fire(timer.alertVolume);
      }
    } finally {
      if (mounted) {
        await ref.read(trainingRepositoriesProvider).restTimers.markAlertFired(
              timer.id,
            );
        await ref.read(timerBackgroundSchedulerProvider).cancel(timer.id);
      }
      _alertsInFlight.remove(timer.id);
    }
  }

  bool _isWithinPrepareWindow(RestTimerRecord timer) {
    final remaining = timer.remainingAt(_now);
    return remaining > Duration.zero &&
        remaining <= RestTimerRepository.prepareCueLead;
  }

  void _queuePrepareAlert(RestTimerRecord timer) {
    if (!_prepareAlertsInFlight.add(timer.id)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_firePrepareAlert(timer));
    });
  }

  Future<void> _firePrepareAlert(RestTimerRecord timer) async {
    try {
      final restTimers = ref.read(trainingRepositoriesProvider).restTimers;
      final current = await restTimers.getById(timer.id);
      // Re-check under the current row: don't prepare-cue a timer that already
      // expired/fired its end cue, or already prepare-cued.
      if (current == null ||
          current.status != RestTimerStatus.running ||
          current.alertFiredAt != null ||
          current.prepareAlertFiredAt != null) {
        return;
      }
      if (_restTimerSoundsEnabled()) {
        await ref.read(restTimerAlertProvider).firePrepare(current.alertVolume);
      }
      await restTimers.markPrepareAlertFired(timer.id);
    } finally {
      _prepareAlertsInFlight.remove(timer.id);
    }
  }

  bool _restTimerSoundsEnabled() {
    return ref.read(settingsControllerProvider).value?.restTimerSoundsEnabled ??
        AppSettings.defaults.restTimerSoundsEnabled;
  }
}

/// −15 s or +15 s: a text button, since no icon reads as fifteen seconds;
/// the screen reader hears [label] ("Rest 15 seconds less").
class _AdjustButton extends StatelessWidget {
  const _AdjustButton({
    required this.seconds,
    required this.text,
    required this.label,
    required this.onPressed,
  });

  final int seconds;
  final String text;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      key: RestStrip.adjustKey(seconds),
      style: TextButton.styleFrom(
        minimumSize: const Size(AppDimens.touchTarget, AppDimens.touchTarget),
      ),
      onPressed: onPressed,
      child: Semantics(
        label: label,
        child: ExcludeSemantics(child: Text(text)),
      ),
    );
  }
}

/// The alert volume slider, opened from the strip's remaining time. It
/// keeps its own value so the slider moves while the strip writes.
class _RestVolumeSheet extends StatefulWidget {
  const _RestVolumeSheet({
    required this.initialVolume,
    required this.onChanged,
  });

  final double initialVolume;
  final ValueChanged<double> onChanged;

  @override
  State<_RestVolumeSheet> createState() => _RestVolumeSheetState();
}

class _RestVolumeSheetState extends State<_RestVolumeSheet> {
  late double _volume = widget.initialVolume;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.trainingRestVolumeTitle, style: context.textStyles.h2),
            const SizedBox(height: AppDimens.dense),
            Row(
              children: [
                const Icon(Icons.volume_up_outlined),
                Expanded(
                  child: Semantics(
                    label: l10n.trainingRestVolumeTitle,
                    child: Slider(
                      key: RestStrip.volumeSliderKey,
                      value: _volume,
                      onChanged: (value) {
                        setState(() => _volume = value);
                        widget.onChanged(value);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
