import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../settings/repositories/settings_repository.dart';
import '../services/rest_cue_owner.dart';
import '../services/rest_cue_scheduler.dart';
import '../services/rest_cues.dart';
import '../services/timer_background_scheduler.dart';
import '../services/timer_cue_player.dart';
import 'training_confirmation.dart';

/// Shows [message] ("Background timer alerts are off") through [show] when
/// scheduling the background notification was refused; the in-app timer runs
/// either way.
///
/// It shows once per app run and never over a confirmation with Undo: while
/// [undoShowing] is true, the show step goes to [whenUndoEnds]. Without these
/// two rules, a lifter who denied notifications would lose Undo on every Log
/// set. The flag is set when the message shows, not when it is requested, so
/// a screen closed during the wait does not use up the one showing.
void notifyIfBackgroundAlertsDenied(
  TimerBackgroundPermissionStatus status, {
  required String message,
  required ShowTrainingConfirmation show,
  required bool Function() undoShowing,
  required ValueChanged<VoidCallback> whenUndoEnds,
}) {
  if (status != TimerBackgroundPermissionStatus.denied ||
      RestStrip._backgroundAlertsNoticeShown) {
    return;
  }
  void showNotice() {
    if (RestStrip._backgroundAlertsNoticeShown) {
      return;
    }
    RestStrip._backgroundAlertsNoticeShown = true;
    show(TrainingConfirmation(message: message));
  }

  if (undoShowing()) {
    whenUndoEnds(showNotice);
  } else {
    showNotice();
  }
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
/// It draws the phase [restPhaseAt] gives: resting with an elapsed bar, Get
/// ready for the last seconds, Rest over counting up, and Start rest when idle
/// (disabled at Off). Tapping the remaining time opens the alert volume sheet.
///
/// It is the rest timer's **one owner**: the Training Screen keeps it at the
/// same place in its tree while it switches exercises, so this state (the
/// ticker, the cues and the background schedule) is never torn down mid-rest.
/// A [RestCueOwner] entry keeps two strips on two routes from both cueing.
///
/// It is also the screen's status row: while [confirmation] is set, it draws
/// that message in place of the phase, with a crossfade. Only the drawing
/// changes: the ticker and the cues keep running under the message, and the
/// phase shows again when it ends.
///
/// With [enableTicker] false (tests only) it just draws the phase: it has no
/// scheduler, no [RestCueOwner] entry, and writes no end.
///
/// For a moment after a message with Undo ends, what replaced it ignores taps:
/// see [_RestStripState._ignoreTapsAfterUndoEnded].
class RestStrip extends ConsumerStatefulWidget {
  const RestStrip({
    super.key,
    required this.workoutId,
    required this.workoutExerciseId,
    required this.rest,
    required this.enableTicker,
    required this.revision,
    required this.onAlertVolumeChanged,
    required this.onConfirmation,
    required this.undoShowing,
    required this.whenUndoEnds,
    required this.notificationTexts,
    this.newestPerformed,
    this.confirmation,
  });

  static const stripKey = Key('training.restStrip');
  static const stopKey = Key('training.restStrip.stop');
  static const startKey = Key('training.restStrip.start');
  static const volumeSliderKey = Key('training.restTimer.volume');
  static const elapsedBarKey = Key('training.restStrip.elapsedBar');

  /// How far one tap on −15 s or +15 s moves a running rest.
  static const adjustStep = Duration(seconds: 15);

  static Key adjustKey(int seconds) {
    return Key('training.restStrip.adjust.$seconds');
  }

  /// Whether "Background timer alerts are off" has shown in this app run.
  static bool _backgroundAlertsNoticeShown = false;

  /// The flag above lives for the whole test isolate.
  @visibleForTesting
  static void resetBackgroundAlertsNoticeForTesting() {
    _backgroundAlertsNoticeShown = false;
  }

  /// Whether this app run has asked to load the cue tones.
  static bool _cuesPrepared = false;

  /// The flag above lives for the whole test isolate, too.
  @visibleForTesting
  static void resetCuesPreparedForTesting() {
    _cuesPrepared = false;
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

  /// Shows a message on this strip's row, through the screen that owns it.
  final ShowTrainingConfirmation onConfirmation;

  /// Whether a message must not be replaced yet; see
  /// [notifyIfBackgroundAlertsDenied].
  final bool Function() undoShowing;

  /// Holds a message until the confirmation with Undo ends.
  final ValueChanged<VoidCallback> whenUndoEnds;

  /// What the notifications say for a rest this strip schedules, built by the
  /// screen for the exercise on screen.
  final RestNotificationTexts notificationTexts;

  /// The Workout's Performed Set with the latest `performedAt`, which can end
  /// Rest over: see [restPhaseAt].
  final ({String id, DateTime performedAt})? newestPerformed;

  /// The message to show, if any. Its `sequence` keys the crossfade: a new
  /// number swaps with a transition, the same number updates in place.
  final ({TrainingConfirmation confirmation, int sequence})? confirmation;

  @override
  ConsumerState<RestStrip> createState() => _RestStripState();
}

/// The width of the strip's phase accents: the elapsed bar and Get ready's
/// border.
const double _accentWidth = 2;

/// From this text scale, the time takes its own line above the buttons: side
/// by side, the buttons leave it no width on a narrow phone.
const double _stackAtTextScale = 1.5;

class _RestStripState extends ConsumerState<RestStrip> {
  Stream<RestTimerRecord?>? _timerStream;
  late Future<RestTimerRecord?> _timerFuture;
  Timer? _ticker;
  DateTime _now = clock.now().toUtc();
  String? _renderedTimerId;
  RestTimerRecord? _timer;
  double _alertVolume = RestTimerRepository.defaultAlertVolume;

  /// Whether the switcher's current child ignores taps; a tap inside the
  /// crossfade then reaches the outgoing child under it.
  bool _ignoringTaps = false;
  Timer? _ignoringTapsTimer;

  RestCueScheduler? _cueScheduler;

  /// Kept from [initState], because `ref` throws once the element is unmounted
  /// and [dispose] must still remove this strip's entry.
  RestCueOwner? _cueOwner;
  AppLifecycleListener? _lifecycleListener;
  ModalRoute<Object?>? _route;

  /// Whether the lifter can see the app; see [_isVisible].
  bool _visible = true;

  /// The row's identity at the last sync, so a build that changes nothing
  /// schedules nothing.
  (String, DateTime, RestTimerStatus)? _syncedRow;

  /// The rows whose end this strip has written.
  final _markedEnds = <String>{};

  /// The phase last announced to a screen reader. Null until the first row,
  /// which sets it and announces nothing.
  Type? _announcedPhase;

  bool get _routeIsCurrent => _route?.isCurrent ?? false;

  @override
  void initState() {
    super.initState();
    _timerFuture = _loadTimer(widget.workoutId);
    if (widget.enableTicker) {
      _timerStream = _watchTimer(widget.workoutId);
      if (!RestStrip._cuesPrepared) {
        RestStrip._cuesPrepared = true;
        unawaited(ref.read(timerCuePlayerProvider).prepare());
      }
      _visible = _isVisible(WidgetsBinding.instance.lifecycleState);
      _lifecycleListener = AppLifecycleListener(
        onStateChange: _onLifecycleStateChanged,
      );
      _cueOwner = ref.read(restCueOwnerProvider);
      _cueScheduler = RestCueScheduler(
        canPlay: () => _visible && _routeIsCurrent && _restTimerSoundsEnabled(),
        onCue: _playCue,
      );
      _armTicker();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  /// Visible means the lifter can see the app, so `inactive` (the notification
  /// shade, Control Center, split screen) still counts. Native uses the same
  /// meaning when it decides whether to post a cue's notification.
  static bool _isVisible(AppLifecycleState? state) {
    return state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden;
  }

  void _onLifecycleStateChanged(AppLifecycleState state) {
    final wasVisible = _visible;
    _visible = _isVisible(state);
    if (_visible && !wasVisible && mounted) {
      setState(() => _now = clock.now().toUtc());
      _syncCues();
    }
  }

  void _playCue(TimerCue cue) {
    unawaited(
      ref
          .read(timerCuePlayerProvider)
          .play(cue, volume: _timer?.alertVolume ?? _alertVolume),
    );
  }

  /// A one-shot that lands on the next whole second of the row's `remaining`,
  /// so the digits change in step with the cues, and re-arms itself from there.
  void _armTicker() {
    _ticker?.cancel();
    _ticker = Timer(_untilNextWholeSecond(), _syncToNow);
  }

  Duration _untilNextWholeSecond() {
    final timer = _timer;
    if (timer == null) {
      return const Duration(seconds: 1);
    }
    final remaining = timer.deadlineAt.difference(clock.now());
    final past = remaining.inMicroseconds % Duration.microsecondsPerSecond;
    return past == 0
        ? const Duration(seconds: 1)
        : Duration(microseconds: past);
  }

  /// Syncs directly, not from build, because no frames are drawn in the
  /// background and a covered or backgrounded strip must keep reporting.
  void _syncToNow() {
    if (!mounted) {
      return;
    }
    setState(() => _now = clock.now().toUtc());
    _syncCues();
    _armTicker();
  }

  /// In this order: `update` comes first so that a −15 s to zero arms its end
  /// cue before the mark's write can emit an expired row, which would cancel
  /// that cue.
  ///
  /// The strip reports current only while it holds a running row. A current
  /// strip with no rest of its own has no cues armed, and native must still cue
  /// a rest running in another Workout, so it cannot claim those cues.
  void _syncCues() {
    final scheduler = _cueScheduler;
    final owner = _cueOwner;
    if (scheduler == null || owner == null) {
      return;
    }
    final timer = _timer;
    scheduler.update(timer);
    owner.report(
      this,
      current: _routeIsCurrent && timer?.status == RestTimerStatus.running,
    );
    _markEndIfDue(timer);
  }

  /// Writes the end of a running row at or past its deadline and cancels its
  /// background schedule, once per row. This one rule covers an end reached in
  /// the app, an end that passed in the background, and a reopen after 0:00.
  /// It plays nothing; only the end cue does.
  ///
  /// The cancel reaches native before the row's write can turn the in-app claim
  /// off, because a notification that has already fired can no longer be
  /// removed: on iOS the cancel is what keeps it silent from then on.
  ///
  /// It runs only while the app is visible AND this strip's route is current,
  /// not whenever the app is visible. The aligned Dart tick lands at the
  /// deadline, normally before the native service's unaligned tick. A covered
  /// strip (under a second Training Screen, Exercise Overview or the volume
  /// sheet) would then cancel the schedule before native posts, so that end
  /// would have no cue at all: the covered strip cannot play it either.
  void _markEndIfDue(RestTimerRecord? timer) {
    if (timer == null ||
        !_visible ||
        !_routeIsCurrent ||
        timer.status != RestTimerStatus.running) {
      return;
    }
    final now = clock.now();
    if (timer.deadlineAt.isAfter(now) || !_markedEnds.add(timer.id)) {
      return;
    }
    final restTimers = ref.read(trainingRepositoriesProvider).restTimers;
    final scheduler = ref.read(timerBackgroundSchedulerProvider);
    unawaited(() async {
      await restTimers.markAlertFired(timer.id, now: now);
      await scheduler.cancel(timer.id);
    }());
  }

  @override
  void didUpdateWidget(covariant RestStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workoutId != widget.workoutId ||
        oldWidget.revision != widget.revision) {
      _timerStream = widget.enableTicker ? _watchTimer(widget.workoutId) : null;
      _timerFuture = _loadTimer(widget.workoutId);
      _renderedTimerId = null;
      _now = clock.now().toUtc();
    }
    final previous = oldWidget.confirmation;
    if (previous != null &&
        previous.confirmation.onUndo != null &&
        previous.sequence != widget.confirmation?.sequence) {
      _ignoreTapsAfterUndoEnded();
    }
  }

  /// Undo draws at the row's trailing edge, the same place as Stop, and a
  /// finger is often on its way there when the message ends: Undo's own
  /// second tap of a double tap, or a tap a moment too late. Reaching Stop
  /// would cancel the rest and its background schedule with no way back, so
  /// what replaced the message takes no taps for one double tap's length.
  ///
  /// This is a timer, not the crossfade's status, because the crossfade has
  /// no length under Reduce Motion, and a double tap outlasts 150 ms.
  void _ignoreTapsAfterUndoEnded() {
    _ignoringTaps = true;
    _ignoringTapsTimer?.cancel();
    _ignoringTapsTimer = Timer(kDoubleTapTimeout, () {
      if (mounted) {
        setState(() => _ignoringTaps = false);
      }
    });
  }

  @override
  void dispose() {
    _ignoringTapsTimer?.cancel();
    _ticker?.cancel();
    _cueScheduler?.dispose();
    _cueOwner?.remove(this);
    _lifecycleListener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.enableTicker) {
      return StreamBuilder<RestTimerRecord?>(
        stream: _timerStream!,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.waiting) {
            _afterRowLoaded(context, snapshot.data);
          }
          return _buildStrip(context, snapshot.data);
        },
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

  /// Build has no side effects: what a new row or phase sets off runs after
  /// the frame, and only when the row or phase actually changed.
  void _afterRowLoaded(BuildContext context, RestTimerRecord? timer) {
    final row =
        timer == null ? null : (timer.id, timer.deadlineAt, timer.status);
    if (row != _syncedRow) {
      _syncedRow = row;
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncToNow());
    }

    final phase = restPhaseAt(timer, widget.newestPerformed, _now).runtimeType;
    final previous = _announcedPhase;
    _announcedPhase = phase;
    if (previous != null &&
        previous != phase &&
        (phase == RestGetReady || phase == RestOver)) {
      final text = phase == RestOver
          ? context.l10n.trainingRestOver
          : _splitGetReady(context.l10n, '').label;
      final view = View.of(context);
      final direction = Directionality.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(SemanticsService.sendAnnouncement(view, text, direction));
      });
    }
  }

  Widget _buildStrip(BuildContext context, RestTimerRecord? timer) {
    _timer = timer;
    _syncVolume(timer);

    final shown = widget.confirmation;
    final phase = restPhaseAt(timer, widget.newestPerformed, _now);
    final colors = context.colors;
    // While a message shows, the strip keeps its default look.
    final drawn = shown == null ? phase : const RestIdle();
    final highlighted = drawn is RestGetReady || drawn is RestCountdown;

    return DecoratedBox(
      key: RestStrip.stripKey,
      decoration: BoxDecoration(
        color: drawn is RestOver ? colors.surface : null,
        border: highlighted
            ? Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: _accentWidth)
            : Border.all(color: colors.divider),
        borderRadius: AppRadii.cardMd,
      ),
      child: ClipRRect(
        borderRadius: AppRadii.cardMd,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppDimens.dense),
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 150),
                // The default centres its children; the strip's content starts
                // at the leading edge.
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: AlignmentDirectional.centerStart,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                child: KeyedSubtree(
                  // One key for every phase: they swap with no transition.
                  key: shown != null
                      ? ValueKey<int>(shown.sequence)
                      : const ValueKey('phase'),
                  child: IgnorePointer(
                    ignoring: _ignoringTaps,
                    child: shown != null
                        ? _ConfirmationContent(shown.confirmation)
                        : _buildPhase(context, timer, phase),
                  ),
                ),
              ),
            ),
            if (timer != null && drawn is RestResting)
              PositionedDirectional(
                start: 0,
                end: 0,
                bottom: 0,
                child: _ElapsedBar(
                  key: RestStrip.elapsedBarKey,
                  elapsed: 1 -
                      drawn.remaining.inMicroseconds /
                          timer.duration.inMicroseconds,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhase(
    BuildContext context,
    RestTimerRecord? timer,
    RestPhase phase,
  ) {
    if (timer != null) {
      switch (phase) {
        case RestResting(:final remaining):
          return _buildRunning(context, timer, remaining, getReady: false);
        case RestGetReady(:final remaining) || RestCountdown(:final remaining):
          return _buildRunning(context, timer, remaining, getReady: true);
        case RestOver(:final elapsed):
          return _buildOver(context, timer, elapsed);
        case RestIdle():
          break;
      }
    }
    return _buildIdle(context);
  }

  /// "Get ready · 0:10" split at the time, for its emphasis and for the
  /// announcement that must not read the digits. One ARB key holds the string,
  /// so nothing else has to agree with its separator.
  ({String label, String rest}) _splitGetReady(
    AppLocalizations l10n,
    String time,
  ) {
    final full = l10n.trainingRestGetReady(time);
    final beforeTime = full.substring(0, full.lastIndexOf(time));
    final label = beforeTime.replaceFirst(RegExp(r'[\s·]+$'), '');
    return (label: label, rest: full.substring(label.length));
  }

  Widget _buildRunning(
    BuildContext context,
    RestTimerRecord timer,
    Duration remaining, {
    required bool getReady,
  }) {
    final l10n = context.l10n;
    final digits = ceilToSeconds(remaining);
    final time = formatRestDuration(digits);
    final style = context.textStyles.numeralRow.copyWith(
      color: context.colors.textPrimary,
    );
    final Widget text;
    if (getReady) {
      final parts = _splitGetReady(l10n, time);
      text = Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: parts.label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: parts.rest),
          ],
        ),
        style: style,
      );
    } else {
      text = Text(l10n.trainingRestCountdown(time), style: style);
    }
    final timeButton = TextButton(
      style: TextButton.styleFrom(
        alignment: AlignmentDirectional.centerStart,
        minimumSize: const Size(0, AppDimens.touchTarget),
      ),
      onPressed: _showVolumeSheet,
      child: Semantics(
        label: l10n.trainingRestStripRemainingLabel(
          digits.inMinutes,
          digits.inSeconds.remainder(60),
        ),
        child: ExcludeSemantics(child: text),
      ),
    );
    final shorten = _AdjustButton(
      seconds: -RestStrip.adjustStep.inSeconds,
      text: l10n.trainingRestStripShorten,
      label: l10n.trainingRestStripShortenLabel,
      onPressed: () => unawaited(_adjust(timer, -RestStrip.adjustStep)),
    );
    final lengthen = _AdjustButton(
      seconds: RestStrip.adjustStep.inSeconds,
      text: l10n.trainingRestStripLengthen,
      label: l10n.trainingRestStripLengthenLabel,
      onPressed: () => unawaited(_adjust(timer, RestStrip.adjustStep)),
    );
    final stop = _stopButton(timer);
    if (MediaQuery.textScalerOf(context).scale(1) >= _stackAtTextScale) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          timeButton,
          Row(
            children: [
              Expanded(child: shorten),
              Expanded(child: lengthen),
              stop,
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: timeButton),
        shorten,
        lengthen,
        stop,
      ],
    );
  }

  /// "Rest over · +0:12". It wraps rather than overflows at large text.
  Widget _buildOver(
    BuildContext context,
    RestTimerRecord timer,
    Duration elapsed,
  ) {
    final l10n = context.l10n;
    final numerals = context.textStyles.numeralRow;
    final primary = numerals.copyWith(color: context.colors.textPrimary);
    final secondary = numerals.copyWith(color: context.colors.textSecondary);
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: AppDimens.dense),
            child: MergeSemantics(
              child: Wrap(
                spacing: AppDimens.dense / 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(l10n.trainingRestOver, style: primary),
                  ExcludeSemantics(child: Text('·', style: secondary)),
                  Text(
                    l10n.trainingRestOverElapsed(
                      formatRestDuration(elapsed),
                    ),
                    style: secondary,
                  ),
                ],
              ),
            ),
          ),
        ),
        _stopButton(timer),
      ],
    );
  }

  Widget _stopButton(RestTimerRecord timer) {
    return IconButton(
      key: RestStrip.stopKey,
      tooltip: context.l10n.trainingStopRestTooltip,
      onPressed: () => unawaited(_stop(timer.id)),
      icon: const Icon(Icons.stop),
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
    final previous = await repository.getCurrentForWorkout(widget.workoutId);
    final timerId = await repository.start(
      RestTimerDraft(
        workoutId: widget.workoutId,
        duration: rest,
        alertVolume: _alertVolume,
      ),
      now: clock.now(),
    );
    await cancelReplacedRestSchedule(
      ref.read(timerBackgroundSchedulerProvider),
      previous: previous,
      startedTimerId: timerId,
    );
    final timer = await repository.getById(timerId);
    if (timer != null) {
      final status = await _scheduleBackground(timer);
      if (mounted) {
        notifyIfBackgroundAlertsDenied(
          status,
          message: context.l10n.trainingBackgroundAlertsDenied,
          show: widget.onConfirmation,
          undoShowing: widget.undoShowing,
          whenUndoEnds: widget.whenUndoEnds,
        );
      }
    }
    _refreshTimer();
  }

  /// −15 s / +15 s. The background notification is cancelled and scheduled
  /// again at the new deadline; when the adjust left no time, it is not
  /// rescheduled, because the strip plays and marks the end right away. A
  /// deadline rounded up to the next second still schedules: native posts
  /// nothing while the strip plays the cues, a cancel that lands while the
  /// schedule waits on the permission answer stops it being sent, and native
  /// adds nothing for a deadline that has passed by the time the schedule
  /// arrives. A refused permission was already reported when the rest started,
  /// so it is not reported again on every tap.
  Future<void> _adjust(RestTimerRecord timer, Duration delta) async {
    final repository = ref.read(trainingRepositoriesProvider).restTimers;
    final scheduler = ref.read(timerBackgroundSchedulerProvider);
    await repository.adjust(timer.id, delta, now: clock.now());
    await scheduler.cancel(timer.id);
    final adjusted = await repository.getById(timer.id);
    if (adjusted != null &&
        adjusted.status == RestTimerStatus.running &&
        adjusted.remainingAt(clock.now().toUtc()) > Duration.zero) {
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
            texts: widget.notificationTexts,
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
      _now = clock.now().toUtc();
    });
  }

  bool _restTimerSoundsEnabled() {
    return ref.read(settingsControllerProvider).value?.restTimerSoundsEnabled ??
        AppSettings.defaults.restTimerSoundsEnabled;
  }
}

/// A [TrainingConfirmation] in the strip's row. Only the message is a live
/// region, so a screen reader reads each one once and never the countdown.
class _ConfirmationContent extends StatelessWidget {
  const _ConfirmationContent(this.confirmation);

  final TrainingConfirmation confirmation;

  @override
  Widget build(BuildContext context) {
    final onUndo = confirmation.onUndo;
    final undoLabel = confirmation.undoLabel;
    // The minimum height is the Undo button's: without it, the strip's height
    // jumps between Log set's first message and its Undo version, moving the
    // form.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                confirmation.message,
                key: confirmation.textKey,
                style: context.textStyles.label.copyWith(
                  color: context.colors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (onUndo != null && undoLabel != null)
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(
                  AppDimens.touchTarget,
                  AppDimens.touchTarget,
                ),
              ),
              onPressed: onUndo,
              child: Text(undoLabel),
            ),
        ],
      ),
    );
  }
}

/// The 2 dp bar along the strip's bottom edge while resting. [elapsed] is 0 to
/// 1. It is decoration: the digits say the same to a screen reader.
class _ElapsedBar extends StatelessWidget {
  const _ElapsedBar({super.key, required this.elapsed});

  final double elapsed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: _accentWidth,
      child: ColoredBox(
        color: colors.divider,
        child: FractionallySizedBox(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: elapsed.clamp(0.0, 1.0),
          child: ColoredBox(color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
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
        child: ExcludeSemantics(
          child: FittedBox(fit: BoxFit.scaleDown, child: Text(text)),
        ),
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
