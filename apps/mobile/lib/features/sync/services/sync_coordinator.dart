import 'dart:async';

import '../../auth/repositories/auth_repository.dart';

enum SyncTrigger {
  appLaunch,
  appResume,
  authChanged,
  localWrite,
  networkRestored,
  periodic,
  serverNudge,
  manual,
}

typedef LoadSyncSession = Future<AuthSession?> Function();
typedef LoadSyncDeviceId = Future<String> Function();
typedef RunSyncCycle = Future<SyncCycleResult> Function({
  required AuthSession session,
  required String deviceId,
});
typedef RecordSyncCredentialFailure = Future<void> Function(Object error);

final class SyncCycleResult {
  const SyncCycleResult({
    required this.appliedCount,
    this.pushedCount = 0,
    this.userSettingsApplied = false,
    this.serverClock,
  });

  static const skipped = SyncCycleResult(appliedCount: 0);

  final int appliedCount;
  final int pushedCount;
  final bool userSettingsApplied;
  final String? serverClock;

  SyncCycleResult operator +(SyncCycleResult other) {
    return SyncCycleResult(
      appliedCount: appliedCount + other.appliedCount,
      pushedCount: pushedCount + other.pushedCount,
      userSettingsApplied: userSettingsApplied || other.userSettingsApplied,
      serverClock: other.serverClock ?? serverClock,
    );
  }
}

/// The single owner of a device replica's Sync Runs.
///
/// Every source of sync work is a hint to this coordinator. Runs are serialized,
/// and a trigger observed while a run is in flight produces exactly one
/// follow-up run before the active future completes. That prevents a late
/// response from regressing the shared pull cursor.
final class SyncCoordinator {
  SyncCoordinator({
    required LoadSyncSession loadSession,
    required LoadSyncDeviceId loadDeviceId,
    required RunSyncCycle runCycle,
    RecordSyncCredentialFailure? recordCredentialFailure,
  })  : _loadSession = loadSession,
        _loadDeviceId = loadDeviceId,
        _runCycle = runCycle,
        _recordCredentialFailure = recordCredentialFailure;

  final LoadSyncSession _loadSession;
  final LoadSyncDeviceId _loadDeviceId;
  final RunSyncCycle _runCycle;
  final RecordSyncCredentialFailure? _recordCredentialFailure;

  Future<SyncCycleResult>? _activeRun;
  var _requestedGeneration = 0;
  var _disposed = false;
  Timer? _localWriteDebounce;
  Timer? _periodicTimer;
  Timer? _retryTimer;
  Duration? _periodicInterval;
  var _consecutiveFailures = 0;

  Future<SyncCycleResult> synchronizeNow(SyncTrigger trigger) {
    _requestedGeneration += 1;
    final activeRun = _activeRun;
    if (activeRun != null) {
      return activeRun;
    }
    return _startRun();
  }

  Future<SyncCycleResult> synchronizeNowWith({
    required SyncTrigger trigger,
    required AuthSession session,
    required String deviceId,
  }) {
    _requestedGeneration += 1;
    final activeRun = _activeRun;
    if (activeRun != null) {
      return activeRun;
    }
    return _startRun(
      credentials: _SyncCredentials(session: session, deviceId: deviceId),
    );
  }

  void requestSync(SyncTrigger trigger) {
    if (_disposed) {
      return;
    }
    if (trigger == SyncTrigger.localWrite) {
      _localWriteDebounce?.cancel();
      _localWriteDebounce = Timer(const Duration(seconds: 2), () {
        _localWriteDebounce = null;
        _requestImmediate(trigger);
      });
      return;
    }
    _requestImmediate(trigger);
  }

  void startPeriodic({
    Duration interval = const Duration(minutes: 15),
  }) {
    _periodicInterval = interval;
    if (_periodicTimer != null) {
      return;
    }
    _periodicTimer = Timer.periodic(
      interval,
      (_) => requestSync(SyncTrigger.periodic),
    );
  }

  void stopPeriodic() {
    _periodicInterval = null;
    pausePeriodic();
  }

  void pausePeriodic() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  void resumePeriodic() {
    final interval = _periodicInterval;
    if (interval != null) {
      startPeriodic(interval: interval);
    }
  }

  void _requestImmediate(SyncTrigger trigger) {
    if (_disposed) {
      return;
    }
    _requestedGeneration += 1;
    if (_retryTimer != null &&
        (trigger == SyncTrigger.localWrite ||
            trigger == SyncTrigger.periodic)) {
      return;
    }
    if (trigger == SyncTrigger.networkRestored ||
        trigger == SyncTrigger.appResume ||
        trigger == SyncTrigger.serverNudge) {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
    if (_activeRun == null) {
      unawaited(
        _startRun().then<void>(
          (_) {
            _consecutiveFailures = 0;
            _retryTimer?.cancel();
            _retryTimer = null;
          },
          onError: (Object _, StackTrace __) => _scheduleRetry(),
        ),
      );
    }
  }

  void _scheduleRetry() {
    if (_disposed || _retryTimer != null) {
      return;
    }
    _consecutiveFailures += 1;
    final exponent = (_consecutiveFailures - 1).clamp(0, 8).toInt();
    final seconds = (1 << exponent).clamp(2, 300).toInt();
    _retryTimer = Timer(Duration(seconds: seconds), () {
      _retryTimer = null;
      _requestImmediate(SyncTrigger.networkRestored);
    });
  }

  Future<SyncCycleResult> _startRun({_SyncCredentials? credentials}) {
    final activeRun = _activeRun;
    if (activeRun != null) {
      return activeRun;
    }

    final run = _runUntilSettled(credentials: credentials);
    _activeRun = run;
    unawaited(
      run.then<void>(
        (_) => _clearActiveRun(run),
        onError: (Object _, StackTrace __) => _clearActiveRun(run),
      ),
    );
    return run;
  }

  void _clearActiveRun(Future<SyncCycleResult> run) {
    if (identical(_activeRun, run)) {
      _activeRun = null;
    }
  }

  Future<SyncCycleResult> _runUntilSettled({
    _SyncCredentials? credentials,
  }) async {
    var aggregate = SyncCycleResult.skipped;
    while (!_disposed) {
      final observedGeneration = _requestedGeneration;
      final AuthSession? session;
      final String deviceId;
      try {
        session = credentials?.session ?? await _loadSession();
        if (session == null) {
          return aggregate;
        }
        deviceId = credentials?.deviceId ?? await _loadDeviceId();
      } on Object catch (error) {
        await _recordCredentialFailure?.call(error);
        rethrow;
      }
      aggregate += await _runCycle(session: session, deviceId: deviceId);
      if (_requestedGeneration == observedGeneration) {
        return aggregate;
      }
    }
    return aggregate;
  }

  void dispose() {
    _disposed = true;
    _localWriteDebounce?.cancel();
    _retryTimer?.cancel();
    stopPeriodic();
  }
}

final class _SyncCredentials {
  const _SyncCredentials({
    required this.session,
    required this.deviceId,
  });

  final AuthSession session;
  final String deviceId;
}
