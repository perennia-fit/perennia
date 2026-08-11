import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../nutrition/widgets/nutrition_import_screen.dart';
import '../../sync/controllers/sync_status_controller.dart';
import '../repositories/integration_consent_repository.dart';
import 'garmin_integration_screen.dart';
import 'settings_shared.dart';

/// Settings → Integrations: one row per integration, each leading to its own
/// focused screen. Unconnected integrations show a single quiet row instead
/// of their full control panel.
class IntegrationsScreen extends ConsumerWidget {
  const IntegrationsScreen({super.key});

  static const garminTileKey = Key('settings.integrations.garmin.open');
  static const nutritionImportTileKey =
      Key('settings.integrations.nutritionImport.tile');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consentState = ref.watch(garminImportConsentStateProvider).value ??
        GarminImportConsentState.empty;
    final syncStatus = ref.watch(syncStatusControllerProvider).value ??
        SyncStatusState.initial(DateTime.now().toUtc());
    final garminStatus = findIntegrationStatus(syncStatus, 'garmin');

    final garminSubtitle = consentState.isConnected
        ? garminStatus == null
            ? 'Connected'
            : integrationStatusLabel(garminStatus.condition)
        : 'Not connected';
    final garminColor = consentState.isConnected && garminStatus != null
        ? integrationStatusColor(context, garminStatus.condition)
        : Theme.of(context).colorScheme.primary;
    final garminIcon = consentState.isConnected && garminStatus != null
        ? integrationStatusIcon(garminStatus.condition)
        : consentState.isConnected
            ? Icons.cloud_done_outlined
            : Icons.cloud_off_outlined;

    return SettingsSubScreen(
      title: 'Integrations',
      children: [
        SettingsSection(
          children: [
            SettingsNavTile(
              key: garminTileKey,
              icon: garminIcon,
              iconColor: garminColor,
              title: 'Garmin Import',
              subtitle: garminSubtitle,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const GarminIntegrationScreen(),
                ),
              ),
            ),
            SettingsNavTile(
              key: nutritionImportTileKey,
              icon: Icons.file_download_outlined,
              title: 'Nutrition import',
              subtitle: 'Import a Cronometer, MyFitnessPal, Yazio, or '
                  'Lifesum export on this device',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const NutritionImportScreen(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
