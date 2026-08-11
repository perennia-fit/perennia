enum SyncStatusKind {
  idle,
  syncing,
  synced,
  failed,
  authExpired,
}

enum IntegrationStatusCondition {
  ok,
  temporaryFailure,
  rateLimited,
  reauthRequired,
}

enum IntegrationStatusRecoveryAction {
  none,
  retry,
  backoff,
  reauth,
}

final class SyncStatusState {
  SyncStatusState({
    required this.kind,
    required this.observedAt,
    this.lastSuccessfulSyncAt,
    this.firstFailureAt,
    this.lastFailureAt,
    this.lastFailureMessage,
    List<IntegrationStatusState> integrationStatuses =
        const <IntegrationStatusState>[],
  }) : integrationStatuses = List<IntegrationStatusState>.unmodifiable(
          integrationStatuses,
        );

  factory SyncStatusState.initial(DateTime observedAt) {
    return SyncStatusState(
      kind: SyncStatusKind.idle,
      observedAt: observedAt.toUtc(),
    );
  }

  static const sustainedFailureThreshold = Duration(hours: 24);

  final SyncStatusKind kind;
  final DateTime? lastSuccessfulSyncAt;
  final DateTime? firstFailureAt;
  final DateTime? lastFailureAt;
  final String? lastFailureMessage;
  final DateTime observedAt;
  final List<IntegrationStatusState> integrationStatuses;

  bool get showsFailureBanner {
    if (kind == SyncStatusKind.authExpired) {
      return true;
    }
    if (kind != SyncStatusKind.failed) {
      return false;
    }

    final lastSuccess = lastSuccessfulSyncAt;
    final failureAnchor = lastSuccess ?? firstFailureAt;
    if (failureAnchor == null) {
      return false;
    }

    return observedAt.difference(failureAnchor) > sustainedFailureThreshold;
  }
}

final class IntegrationStatusState {
  const IntegrationStatusState({
    required this.source,
    required this.condition,
    required this.recoveryAction,
    required this.observedAt,
    this.credentialName,
    this.lastSuccessfulAt,
    this.firstFailureAt,
    this.lastFailureAt,
    this.failureKind,
    this.retryAfterSeconds,
    this.nextAttemptAt,
    this.manualFitImportFallback = true,
  });

  final String source;
  final String? credentialName;
  final IntegrationStatusCondition condition;
  final IntegrationStatusRecoveryAction recoveryAction;
  final DateTime? lastSuccessfulAt;
  final DateTime? firstFailureAt;
  final DateTime? lastFailureAt;
  final String? failureKind;
  final int? retryAfterSeconds;
  final DateTime? nextAttemptAt;
  final bool manualFitImportFallback;
  final DateTime observedAt;

  bool get showsFailureBanner {
    if (condition == IntegrationStatusCondition.reauthRequired ||
        condition == IntegrationStatusCondition.rateLimited) {
      return true;
    }
    if (condition != IntegrationStatusCondition.temporaryFailure) {
      return false;
    }

    final failureAnchor = lastSuccessfulAt ?? firstFailureAt;
    if (failureAnchor == null) {
      return false;
    }
    return observedAt.difference(failureAnchor) >
        SyncStatusState.sustainedFailureThreshold;
  }
}
