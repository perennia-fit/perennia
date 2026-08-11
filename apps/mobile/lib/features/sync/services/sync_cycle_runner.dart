import '../../auth/repositories/auth_repository.dart';
import '../repositories/sync_repository.dart';
import 'sync_coordinator.dart';

const _syncPullWindowLimit = 100;
const _maxPendingDrainPasses = 8;
const _maxConsecutiveNoProgressPasses = 2;

final class RepositorySyncCycleRunner {
  RepositorySyncCycleRunner({
    required SyncCycleRepository repository,
    required SyncStatusRepository statusRepository,
    void Function()? onUserSettingsApplied,
  })  : _repository = repository,
        _statusRepository = statusRepository,
        _onUserSettingsApplied = onUserSettingsApplied;

  final SyncCycleRepository _repository;
  final SyncStatusRepository _statusRepository;
  final void Function()? _onUserSettingsApplied;

  Future<SyncCycleResult> run({
    required AuthSession session,
    required String deviceId,
  }) async {
    await _statusRepository.recordSyncing();
    var aggregate = SyncCycleResult.skipped;
    var drainPasses = 0;
    var consecutiveNoProgressPasses = 0;
    try {
      while (true) {
        drainPasses += 1;
        if (drainPasses > _maxPendingDrainPasses) {
          throw StateError(
            'Sync could not drain pending changes after '
            '$_maxPendingDrainPasses passes.',
          );
        }
        var passProgress = 0;
        final authoredPush = await _repository.pushPendingLoggedSets(
          session: session,
          deviceId: deviceId,
          manageStatus: false,
        );
        final consentPush =
            await _repository.pushPendingIntegrationDataClassConsents(
          session: session,
          deviceId: deviceId,
          manageStatus: false,
        );
        aggregate += SyncCycleResult(
          appliedCount: 0,
          pushedCount: authoredPush.pushedCount + consentPush.pushedCount,
          serverClock: consentPush.serverClock ?? authoredPush.serverClock,
        );
        passProgress += authoredPush.pushedCount + consentPush.pushedCount;

        String? previousCursor;
        while (true) {
          final pull = await _repository.pullLoggedSetChanges(
            session: session,
            deviceId: deviceId,
            limit: _syncPullWindowLimit,
            manageStatus: false,
          );
          aggregate += SyncCycleResult(
            appliedCount: pull.appliedCount,
            userSettingsApplied: pull.userSettingsApplied,
            serverClock: pull.serverClock,
          );
          passProgress += pull.appliedCount;
          if (!pull.hasMore || pull.fullResyncRequired) {
            break;
          }
          if (pull.nextCursor == previousCursor) {
            throw const FormatException(
              'Sync pull cursor did not advance while more changes remained.',
            );
          }
          previousCursor = pull.nextCursor;
        }

        final hasPendingChanges = await _repository.hasPendingChanges();
        if (!hasPendingChanges) {
          break;
        }
        if (passProgress == 0) {
          consecutiveNoProgressPasses += 1;
          if (consecutiveNoProgressPasses >= _maxConsecutiveNoProgressPasses) {
            throw StateError(
              'Sync made no progress while pending changes remained.',
            );
          }
        } else {
          consecutiveNoProgressPasses = 0;
        }
      }

      if (aggregate.userSettingsApplied) {
        _onUserSettingsApplied?.call();
      }
      await _statusRepository.recordSuccess(
        serverClock: aggregate.serverClock,
      );
      return aggregate;
    } on Object catch (error) {
      await _statusRepository.recordFailure(error);
      rethrow;
    }
  }
}
