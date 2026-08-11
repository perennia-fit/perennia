import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../sync/controllers/sync_status_controller.dart';
import '../repositories/garmin_import_repository.dart';
import '../repositories/imported_data_purge_repository.dart';
import '../repositories/integration_consent_repository.dart';
import 'settings_providers.dart';
import 'settings_shared.dart';

/// Settings → Integrations → Garmin Import: connection status, sync-token and
/// FIT-file actions, per-data-class consents, and the Garmin-scoped danger
/// zone (disconnect and purges).
class GarminIntegrationScreen extends ConsumerWidget {
  const GarminIntegrationScreen({super.key});

  static const adapterTileKey = Key('settings.integrations.garmin.tile');
  static const createTokenButtonKey =
      Key('settings.integrations.garmin.connectConfigure');
  static const tokenTextKey = Key('settings.integrations.garmin.token.text');
  static const copyTokenButtonKey =
      Key('settings.integrations.garmin.copyToken');
  static const fitUploadButtonKey =
      Key('settings.integrations.garmin.fitUpload');
  static const disconnectButtonKey =
      Key('settings.integrations.garmin.disconnect');
  static const purgeGpsButtonKey =
      Key('settings.integrations.garmin.purgeGps');
  static const purgeAllButtonKey =
      Key('settings.integrations.garmin.purgeAll');
  static const confirmPurgeGpsButtonKey =
      Key('settings.integrations.garmin.purgeGps.confirm');
  static const confirmPurgeAllButtonKey =
      Key('settings.integrations.garmin.purgeAll.confirm');

  static Key consentSwitchKey(ImportDataClass dataClass) {
    return Key('settings.integrations.garmin.consent.${dataClass.name}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consentState = ref.watch(garminImportConsentStateProvider).value ??
        GarminImportConsentState.empty;
    final syncStatus = ref.watch(syncStatusControllerProvider).value ??
        SyncStatusState.initial(DateTime.now().toUtc());
    final authState =
        ref.watch(authControllerProvider).value ?? AuthState.defaults;

    return SettingsSubScreen(
      title: 'Garmin Import',
      children: [
        _GarminImportSettingsBody(
          consentState: consentState,
          status: findIntegrationStatus(syncStatus, 'garmin'),
          consentRepository: ref.read(integrationConsentRepositoryProvider),
          garminImportRepository: ref.read(garminImportRepositoryProvider),
          garminFitFilePicker: ref.read(garminFitFilePickerProvider),
          purgeRepository: ref.read(importedDataPurgeRepositoryProvider),
          authSession: authState.session,
        ),
      ],
    );
  }
}

class _GarminImportSettingsBody extends StatelessWidget {
  const _GarminImportSettingsBody({
    required this.consentState,
    required this.status,
    required this.consentRepository,
    required this.garminImportRepository,
    required this.garminFitFilePicker,
    required this.purgeRepository,
    required this.authSession,
  });

  final GarminImportConsentState consentState;
  final IntegrationStatusState? status;
  final IntegrationConsentRepository consentRepository;
  final GarminImportRepository garminImportRepository;
  final GarminFitFilePicker garminFitFilePicker;
  final ImportedDataPurgeRepository purgeRepository;
  final AuthSession? authSession;

  @override
  Widget build(BuildContext context) {
    final effectiveStatus = status;
    final statusLabel = consentState.isConnected
        ? effectiveStatus == null
            ? 'Connected'
            : integrationStatusLabel(effectiveStatus.condition)
        : 'Not connected';
    final statusColor = consentState.isConnected && effectiveStatus != null
        ? integrationStatusColor(context, effectiveStatus.condition)
        : Theme.of(context).colorScheme.primary;
    final statusIcon = consentState.isConnected && effectiveStatus != null
        ? integrationStatusIcon(effectiveStatus.condition)
        : consentState.isConnected
            ? Icons.cloud_done_outlined
            : Icons.cloud_off_outlined;

    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            key: GarminIntegrationScreen.adapterTileKey,
            contentPadding: EdgeInsets.zero,
            leading: Icon(statusIcon, color: statusColor),
            title: const Text('Garmin Import adapter'),
            subtitle: Text(statusLabel),
            trailing: effectiveStatus == null
                ? null
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Last successful',
                        style: context.textStyles.caption,
                      ),
                      Text(
                        formatLastSuccessfulSync(
                          effectiveStatus.lastSuccessfulAt,
                        ),
                        style: context.textStyles.body,
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: AppDimens.dense),
          Wrap(
            spacing: AppDimens.dense,
            runSpacing: AppDimens.dense,
            children: [
              SizedBox(
                height: AppDimens.touchTarget,
                child: FilledButton.icon(
                  key: GarminIntegrationScreen.createTokenButtonKey,
                  onPressed: authSession == null
                      ? null
                      : () {
                          unawaited(
                            _createGarminDbCredential(
                              context,
                              session: authSession!,
                            ),
                          );
                        },
                  icon: const Icon(Icons.settings_ethernet_outlined),
                  label: const Text('Create sync token'),
                ),
              ),
              SizedBox(
                height: AppDimens.touchTarget,
                child: OutlinedButton.icon(
                  key: GarminIntegrationScreen.fitUploadButtonKey,
                  onPressed: authSession == null ||
                          consentState.credentialId == null ||
                          !consentState.consentFor(ImportDataClass.activities)
                      ? null
                      : () {
                          unawaited(
                            _importGarminFitFiles(
                              context,
                              session: authSession!,
                              credentialId: consentState.credentialId!,
                            ),
                          );
                        },
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Import FIT files'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.base),
          SettingsSection(
            title: 'Imported feeds',
            children: [
              for (final dataClass in ImportDataClass.values)
                SwitchListTile(
                  key: GarminIntegrationScreen.consentSwitchKey(dataClass),
                  contentPadding: EdgeInsets.zero,
                  title: Text(dataClass.label),
                  subtitle: dataClass == ImportDataClass.gps
                      ? const Text('Separate opt-in')
                      : null,
                  value: consentState.consentFor(dataClass),
                  onChanged: consentState.canEdit(dataClass)
                      ? (enabled) {
                          unawaited(
                            consentRepository.setGarminConsentEnabled(
                              dataClass,
                              enabled: enabled,
                            ),
                          );
                        }
                      : null,
                ),
            ],
          ),
          const SizedBox(height: AppDimens.base),
          Text('Connection & imported data', style: context.textStyles.h2),
          const SizedBox(height: AppDimens.dense),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.error),
              borderRadius: AppRadii.cardMd,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppDimens.dense),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (consentState.isConnected) ...[
                    SizedBox(
                      height: AppDimens.touchTarget,
                      child: OutlinedButton.icon(
                        key: GarminIntegrationScreen.disconnectButtonKey,
                        onPressed: () {
                          unawaited(
                            consentRepository.disconnectGarminImport(),
                          );
                        },
                        icon: const Icon(Icons.link_off_outlined),
                        label: const Text('Disconnect'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDimens.dense),
                  ],
                  SizedBox(
                    height: AppDimens.touchTarget,
                    child: OutlinedButton.icon(
                      key: GarminIntegrationScreen.purgeGpsButtonKey,
                      onPressed: authSession == null
                          ? null
                          : () {
                              unawaited(
                                _confirmGarminPurge(
                                  context,
                                  session: authSession!,
                                  scope: ImportedDataPurgeScope.gpsOnly,
                                ),
                              );
                            },
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Purge GPS'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: destructiveButtonForeground(context),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimens.dense),
                  SizedBox(
                    height: AppDimens.touchTarget,
                    child: OutlinedButton.icon(
                      key: GarminIntegrationScreen.purgeAllButtonKey,
                      onPressed: authSession == null
                          ? null
                          : () {
                              unawaited(
                                _confirmGarminPurge(
                                  context,
                                  session: authSession!,
                                  scope: ImportedDataPurgeScope.all,
                                ),
                              );
                            },
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('Purge imported data'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: destructiveButtonForeground(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createGarminDbCredential(
    BuildContext context, {
    required AuthSession session,
  }) async {
    try {
      final issued = await garminImportRepository.createGarminDbCredential(
        session: session,
      );

      if (!context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('GarminDB sync token'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(
                  issued.secret,
                  key: GarminIntegrationScreen.tokenTextKey,
                  style: context.textStyles.body.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: AppDimens.base),
                const Text(
                  'Copy this one-time token now. Then tap Sync now, enable '
                  'Activities, Heart rate, and Sleep/wellness, and run the '
                  'GarminDB script.',
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                key: GarminIntegrationScreen.copyTokenButtonKey,
                onPressed: () {
                  unawaited(Clipboard.setData(
                    ClipboardData(text: issued.secret),
                  ));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sync token copied')),
                  );
                },
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy token'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } on Object catch (error) {
      if (!context.mounted) {
        return;
      }
      _showGarminImportError(context, error);
    }
  }

  Future<void> _importGarminFitFiles(
    BuildContext context, {
    required AuthSession session,
    required String credentialId,
  }) async {
    try {
      final files = await garminFitFilePicker();
      if (files.isEmpty) {
        return;
      }

      var imported = 0;
      var duplicates = 0;
      for (final file in files) {
        final response = await garminImportRepository.uploadGarminFitFile(
          session: session,
          credentialId: credentialId,
          bytes: await file.readAsBytes(),
          filename: file.name,
        );
        if (response.duplicate) {
          duplicates += 1;
        } else {
          imported += 1;
        }
      }

      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'FIT import complete: $imported imported, $duplicates skipped.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) {
        return;
      }
      _showGarminImportError(context, error);
    }
  }

  void _showGarminImportError(BuildContext context, Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Garmin import failed: $error')),
    );
  }

  Future<void> _confirmGarminPurge(
    BuildContext context, {
    required AuthSession session,
    required ImportedDataPurgeScope scope,
  }) async {
    final gpsOnly = scope == ImportedDataPurgeScope.gpsOnly;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(gpsOnly ? 'Purge GPS data?' : 'Purge imported data?'),
          content: Text(
            gpsOnly
                ? 'This removes imported Garmin location tracks only. '
                    'Activities, summaries, workouts, and heart rate stay.'
                : 'This removes imported Garmin activities, summaries, '
                    'GPS, and materialized workouts. Disconnect stays separate.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              key: gpsOnly
                  ? GarminIntegrationScreen.confirmPurgeGpsButtonKey
                  : GarminIntegrationScreen.confirmPurgeAllButtonKey,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.delete_forever_outlined),
              label: Text(gpsOnly ? 'Purge GPS' : 'Purge'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await purgeRepository.purgeGarminImportedData(
        session: session,
        scope: scope,
      );
    } on Object {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purge failed')),
      );
      return;
    }

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          gpsOnly ? 'Garmin GPS purged' : 'Garmin imported data purged',
        ),
      ),
    );
  }
}
