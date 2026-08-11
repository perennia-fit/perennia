import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme.dart';
import '../../activity/widgets/activity_feed_screen.dart';
import '../../protocols/widgets/compound_list_screen.dart';
import '../../protocols/widgets/protocols_lock_screen.dart';
import '../../sync/controllers/sync_status_controller.dart';
import '../repositories/integration_consent_repository.dart';
import '../repositories/settings_repository.dart';
import 'about_screen.dart';
import 'agent_api_screen.dart';
import 'backup_settings_screen.dart';
import 'data_management_screen.dart';
import 'garmin_integration_screen.dart';
import 'general_settings_screen.dart';
import 'integrations_screen.dart';
import 'logging_settings_screen.dart';
import 'privacy_settings_screen.dart';
import 'settings_shared.dart';
import 'sync_settings_screen.dart';

export 'about_screen.dart';
export 'agent_api_screen.dart';
export 'backup_settings_screen.dart';
export 'data_management_screen.dart';
export 'garmin_integration_screen.dart';
export 'general_settings_screen.dart';
export 'integrations_screen.dart';
export 'logging_settings_screen.dart';
export 'privacy_settings_screen.dart';
export 'settings_providers.dart';
export 'settings_shared.dart';
export 'sync_settings_screen.dart';

/// The Settings hub: a single viewport of navigation rows, each showing its
/// current value, each opening one focused sub-screen. All rows navigate —
/// no inline controls live here.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({
    super.key,
    this.onEraseAllData,
  });

  final Future<void> Function()? onEraseAllData;

  static const routeName = '/settings';

  // Hub navigation rows.
  static const generalTileKey = Key('settings.hub.general');
  static const loggingTileKey = Key('settings.hub.logging');
  static const syncTileKey = Key('settings.hub.sync');
  static const integrationsTileKey = Key('settings.hub.integrations');
  static const agentApiTileKey = Key('settings.hub.agentApi');
  static const backupTileKey = Key('settings.hub.backup');
  static const dataManagementTileKey = Key('settings.hub.dataManagement');
  static const privacyTileKey = Key('settings.hub.privacy');
  static const activityLogTileKey = Key('settings.hub.activityLog');
  static const aboutTileKey = Key('settings.hub.about');

  /// Deliberately a quiet root row, not a sub-screen setting: same neutral
  /// copy and lock gate as before the hub split (/0035).
  static const supplementsTileKey = Key('settings.tracking.supplements.tile');

  // Compatibility aliases: these controls moved to focused sub-screens; the
  // key constants stay addressable here so tests and tooling keep one stable
  // entry point.
  static const themePreferenceKey = GeneralSettingsScreen.themePreferenceKey;
  static const unitSystemKey = GeneralSettingsScreen.unitSystemKey;
  static const weekStartDayKey = GeneralSettingsScreen.weekStartDayKey;
  static const homeScreenDisplayKey =
      GeneralSettingsScreen.homeScreenDisplayKey;
  static const defaultWeightIncrementFieldKey =
      LoggingSettingsScreen.defaultWeightIncrementFieldKey;
  static const prTrackingSwitchKey = LoggingSettingsScreen.prTrackingSwitchKey;
  static const autoSelectNextSetSwitchKey =
      LoggingSettingsScreen.autoSelectNextSetSwitchKey;
  static const keepScreenOnSwitchKey =
      LoggingSettingsScreen.keepScreenOnSwitchKey;
  static const exerciseCreditsKey = AboutScreen.exerciseCreditsKey;
  static const nutritionCreditsKey = AboutScreen.nutritionCreditsKey;
  static const crashReportingSwitchKey =
      PrivacySettingsScreen.crashReportingSwitchKey;
  static const debugCrashReportButtonKey =
      PrivacySettingsScreen.debugCrashReportButtonKey;
  static const syncStatusRowKey = SyncSettingsScreen.syncStatusRowKey;
  static const syncNowButtonKey = SyncSettingsScreen.syncNowButtonKey;
  static const syncFailureBannerKey = SyncSettingsScreen.syncFailureBannerKey;
  static const integrationStatusRowKey =
      SyncSettingsScreen.integrationStatusRowKey;
  static const integrationFailureBannerKey =
      SyncSettingsScreen.integrationFailureBannerKey;
  static const garminImportAdapterTileKey =
      GarminIntegrationScreen.adapterTileKey;
  static const garminImportAdapterButtonKey =
      GarminIntegrationScreen.createTokenButtonKey;
  static const garminImportTokenTextKey = GarminIntegrationScreen.tokenTextKey;
  static const garminImportCopyTokenButtonKey =
      GarminIntegrationScreen.copyTokenButtonKey;
  static const garminImportFitUploadButtonKey =
      GarminIntegrationScreen.fitUploadButtonKey;
  static const garminImportDisconnectButtonKey =
      GarminIntegrationScreen.disconnectButtonKey;
  static const garminImportPurgeGpsButtonKey =
      GarminIntegrationScreen.purgeGpsButtonKey;
  static const garminImportPurgeAllButtonKey =
      GarminIntegrationScreen.purgeAllButtonKey;
  static const confirmGarminImportPurgeGpsButtonKey =
      GarminIntegrationScreen.confirmPurgeGpsButtonKey;
  static const confirmGarminImportPurgeAllButtonKey =
      GarminIntegrationScreen.confirmPurgeAllButtonKey;

  static Key garminImportConsentSwitchKey(ImportDataClass dataClass) {
    return GarminIntegrationScreen.consentSwitchKey(dataClass);
  }

  static const nutritionImportTileKey =
      IntegrationsScreen.nutritionImportTileKey;
  static const autoBackupSwitchKey = BackupSettingsScreen.autoBackupSwitchKey;
  static const autoBackupFolderButtonKey =
      BackupSettingsScreen.autoBackupFolderButtonKey;
  static const autoBackupGrantPromptKey =
      BackupSettingsScreen.autoBackupGrantPromptKey;
  static const autoBackupPassphraseFieldKey =
      BackupSettingsScreen.autoBackupPassphraseFieldKey;
  static const eraseAllDataButtonKey =
      DataManagementScreen.eraseAllDataButtonKey;
  static const confirmEraseAllDataButtonKey =
      DataManagementScreen.confirmEraseAllDataButtonKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings.defaults;
    final syncStatus = ref.watch(syncStatusControllerProvider).value ??
        SyncStatusState.initial(DateTime.now().toUtc());
    final garminConsentState =
        ref.watch(garminImportConsentStateProvider).value ??
            GarminImportConsentState.empty;

    final syncSubtitle = syncStatus.lastSuccessfulSyncAt == null
        ? syncStatusLabel(syncStatus.kind)
        : '${syncStatusLabel(syncStatus.kind)} · '
            '${formatLastSuccessfulSync(syncStatus.lastSuccessfulSyncAt)}';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDimens.base),
          children: [
            _HubGroup(
              title: 'Preferences',
              children: [
                SettingsNavTile(
                  key: generalTileKey,
                  icon: Icons.tune,
                  title: 'General',
                  subtitle: '${settings.themePreference.label} theme · '
                      '${settings.unitSystem.label} · '
                      'Week starts ${settings.weekStartDay.label}',
                  onTap: () => _push(context, const GeneralSettingsScreen()),
                ),
                SettingsNavTile(
                  key: loggingTileKey,
                  icon: Icons.playlist_add_check,
                  title: 'Logging',
                  subtitle: 'Increment '
                      '${formatWeightIncrement(settings.defaultWeightIncrement)}'
                      ' · PR tracking '
                      '${settings.prTrackingEnabled ? 'on' : 'off'}',
                  onTap: () => _push(context, const LoggingSettingsScreen()),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.base),
            _HubGroup(
              title: 'Sync & connections',
              children: [
                SettingsNavTile(
                  key: syncTileKey,
                  icon: syncStatusIcon(syncStatus.kind),
                  iconColor: syncStatusColor(context, syncStatus.kind),
                  title: 'Sync',
                  subtitle: syncSubtitle,
                  onTap: () => _push(context, const SyncSettingsScreen()),
                ),
                SettingsNavTile(
                  key: integrationsTileKey,
                  icon: Icons.extension_outlined,
                  title: 'Integrations',
                  subtitle: garminConsentState.isConnected
                      ? 'Garmin connected · Nutrition import'
                      : 'Garmin · Nutrition import',
                  onTap: () => _push(context, const IntegrationsScreen()),
                ),
                SettingsNavTile(
                  key: agentApiTileKey,
                  icon: Icons.smart_toy_outlined,
                  title: 'Agent API',
                  subtitle: 'Keys for AI agents',
                  onTap: () => _push(context, const AgentApiScreen()),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.base),
            _HubGroup(
              title: 'Data & privacy',
              children: [
                SettingsNavTile(
                  key: backupTileKey,
                  icon: Icons.backup_outlined,
                  title: 'Backup & restore',
                  subtitle: settings.autoBackupEnabled
                      ? 'Auto-backup on · '
                          '${settings.autoBackupLastStatus.label}'
                      : 'Auto-backup off',
                  onTap: () => _push(context, const BackupSettingsScreen()),
                ),
                SettingsNavTile(
                  key: dataManagementTileKey,
                  icon: Icons.delete_sweep_outlined,
                  title: 'Data management',
                  subtitle: "Erase this device's data",
                  onTap: () => _push(
                    context,
                    DataManagementScreen(onEraseAllData: onEraseAllData),
                  ),
                ),
                SettingsNavTile(
                  key: privacyTileKey,
                  icon: Icons.shield_outlined,
                  title: 'Privacy & security',
                  // The Supplements lock state is deliberately not surfaced
                  // here: hide-at-a-glance extends to the hub.
                  subtitle: 'Crash reporting '
                      '${settings.crashReportingEnabled ? 'on' : 'off'}',
                  onTap: () => _push(context, const PrivacySettingsScreen()),
                ),
                SettingsNavTile(
                  key: activityLogTileKey,
                  icon: Icons.history_outlined,
                  title: 'Activity Log',
                  subtitle: 'Review changes and undo recoverable actions',
                  onTap: () => _push(context, const ActivityFeedScreen()),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.base),
            _HubGroup(
              children: [
                SettingsNavTile(
                  key: supplementsTileKey,
                  icon: Icons.medication_outlined,
                  title: 'Supplements',
                  subtitle: 'Log what you take and review it by day',
                  onTap: () => _push(
                    context,
                    const ProtocolsLockGate(child: CompoundListScreen()),
                  ),
                ),
                SettingsNavTile(
                  key: aboutTileKey,
                  icon: Icons.info_outline,
                  title: 'About',
                  subtitle: 'Data credits and licenses',
                  onTap: () => _push(context, const AboutScreen()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }
}

class _HubGroup extends StatelessWidget {
  const _HubGroup({
    this.title,
    required this.children,
  });

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    return Semantics(
      container: true,
      label: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(
                left: AppDimens.dense,
                bottom: AppDimens.dense,
              ),
              child: Text(
                title.toUpperCase(),
                style: context.textStyles.label.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          Material(
            color: context.colors.surface,
            borderRadius: AppRadii.cardMd,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < children.length; index += 1) ...[
                  children[index],
                  if (index != children.length - 1)
                    Divider(height: 1, color: context.colors.divider),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
