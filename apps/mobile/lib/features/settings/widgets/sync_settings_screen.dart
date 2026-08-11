import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../sync/controllers/sync_status_controller.dart';
import '../../sync/repositories/sync_device_id_repository.dart';
import 'settings_providers.dart';
import 'settings_shared.dart';

/// Settings → Sync: sync health, manual sync, and per-integration feed
/// status. Failure banners stay non-modal (>24 h or auth expiry only).
class SyncSettingsScreen extends ConsumerWidget {
  const SyncSettingsScreen({super.key});

  static const syncStatusRowKey = Key('settings.syncStatus.row');
  static const syncNowButtonKey = Key('settings.syncStatus.syncNow');
  static const syncFailureBannerKey = Key('settings.syncStatus.failureBanner');
  static const integrationStatusRowKey = Key('settings.integrationStatus.row');
  static const integrationFailureBannerKey =
      Key('settings.integrationStatus.failureBanner');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatus = ref.watch(syncStatusControllerProvider).value ??
        SyncStatusState.initial(DateTime.now().toUtc());
    final authState =
        ref.watch(authControllerProvider).value ?? AuthState.defaults;
    final syncDeviceId = ref.watch(syncDeviceIdProvider).value;
    final syncNow = ref.read(settingsSyncNowProvider);

    return SettingsSubScreen(
      title: 'Sync',
      children: [
        _SyncStatusTile(
          status: syncStatus,
          onSyncNow: authState.session == null ||
                  syncDeviceId == null ||
                  syncStatus.kind == SyncStatusKind.syncing
              ? null
              : () {
                  unawaited(
                    _syncNow(
                      context,
                      session: authState.session!,
                      deviceId: syncDeviceId,
                      syncNow: syncNow,
                    ),
                  );
                },
        ),
      ],
    );
  }
}

class _SyncStatusTile extends StatelessWidget {
  const _SyncStatusTile({
    required this.status,
    required this.onSyncNow,
  });

  final SyncStatusState status;
  final VoidCallback? onSyncNow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.dense),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (status.showsFailureBanner) ...[
            _SyncFailureBanner(status: status),
            const SizedBox(height: AppDimens.dense),
          ],
          for (final integration in status.integrationStatuses)
            if (integration.showsFailureBanner) ...[
              _IntegrationFailureBanner(status: integration),
              const SizedBox(height: AppDimens.dense),
            ],
          ListTile(
            key: SyncSettingsScreen.syncStatusRowKey,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              syncStatusIcon(status.kind),
              color: syncStatusColor(context, status.kind),
            ),
            title: const Text('Sync'),
            subtitle: Text(syncStatusLabel(status.kind)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Last successful',
                  style: context.textStyles.caption,
                ),
                const SizedBox(height: 2),
                Text(
                  formatLastSuccessfulSync(status.lastSuccessfulSyncAt),
                  style: context.textStyles.body,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.dense),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              height: AppDimens.touchTarget,
              child: OutlinedButton.icon(
                key: SyncSettingsScreen.syncNowButtonKey,
                onPressed: onSyncNow,
                icon: const Icon(Icons.sync_outlined),
                label: const Text('Sync now'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.textPrimary,
                ),
              ),
            ),
          ),
          for (final integration in status.integrationStatuses) ...[
            Divider(color: context.colors.divider),
            _IntegrationStatusRow(status: integration),
          ],
        ],
      ),
    );
  }
}

Future<void> _syncNow(
  BuildContext context, {
  required AuthSession session,
  required String deviceId,
  required SettingsSyncNow syncNow,
}) async {
  try {
    final result = await syncNow(session: session, deviceId: deviceId);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Sync complete: ${result.appliedCount} changes applied.',
        ),
      ),
    );
  } on Object catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sync failed: $error')),
    );
  }
}

class _SyncFailureBanner extends StatelessWidget {
  const _SyncFailureBanner({required this.status});

  final SyncStatusState status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: 'Sync warning',
      child: DecoratedBox(
        key: SyncSettingsScreen.syncFailureBannerKey,
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.error),
          borderRadius: AppRadii.cardMd,
          color: colorScheme.errorContainer,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.dense),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.sync_problem_outlined,
                color: colorScheme.onErrorContainer,
              ),
              const SizedBox(width: AppDimens.dense),
              Expanded(
                child: Text(
                  _syncFailureMessage(status),
                  style: context.textStyles.body.copyWith(
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntegrationFailureBanner extends StatelessWidget {
  const _IntegrationFailureBanner({required this.status});

  final IntegrationStatusState status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: '${integrationSourceLabel(status.source)} integration warning',
      child: DecoratedBox(
        key: SyncSettingsScreen.integrationFailureBannerKey,
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.error),
          borderRadius: AppRadii.cardMd,
          color: colorScheme.errorContainer,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.dense),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                integrationStatusIcon(status.condition),
                color: colorScheme.onErrorContainer,
              ),
              const SizedBox(width: AppDimens.dense),
              Expanded(
                child: Text(
                  _integrationFailureMessage(status),
                  style: context.textStyles.body.copyWith(
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntegrationStatusRow extends StatelessWidget {
  const _IntegrationStatusRow({required this.status});

  final IntegrationStatusState status;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: SyncSettingsScreen.integrationStatusRowKey,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        integrationStatusIcon(status.condition),
        color: integrationStatusColor(context, status.condition),
      ),
      title: Text(integrationSourceLabel(status.source)),
      subtitle: Text(integrationStatusLabel(status.condition)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'Last successful',
            style: context.textStyles.caption,
          ),
          const SizedBox(height: 2),
          Text(
            formatLastSuccessfulSync(status.lastSuccessfulAt),
            style: context.textStyles.body,
          ),
        ],
      ),
    );
  }
}

String _syncFailureMessage(SyncStatusState status) {
  if (status.kind == SyncStatusKind.authExpired) {
    return status.lastFailureMessage ??
        'Sign in again to resume sync. Local logging stays available.';
  }
  return 'Sync has been failing for more than 24 hours. '
      'Local logging stays available.';
}

String _integrationFailureMessage(IntegrationStatusState status) {
  final source = integrationSourceLabel(status.source);
  final fallback = status.manualFitImportFallback
      ? ' Manual FIT import still works as the guaranteed fallback.'
      : '';
  return switch (status.condition) {
    IntegrationStatusCondition.reauthRequired =>
      '$source sidecar needs new credentials in the self-host config.$fallback',
    IntegrationStatusCondition.rateLimited =>
      '$source sidecar is backing off after a rate limit.$fallback',
    IntegrationStatusCondition.temporaryFailure =>
      '$source sidecar has been failing for more than 24 hours.$fallback',
    IntegrationStatusCondition.ok => '$source sidecar is connected.',
  };
}
