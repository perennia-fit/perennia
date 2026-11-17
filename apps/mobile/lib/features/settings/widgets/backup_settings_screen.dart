import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../repositories/settings_repository.dart';
import '../services/auto_backup_service.dart';
import 'backup_now_section.dart';
import 'backup_restore_section.dart';
import 'settings_shared.dart';

/// Settings → Backup & restore: Back up now through the platform save
/// dialog, scheduled backups to a user-granted folder where the platform
/// supports them, and merge-only restore from a backup file.
class BackupSettingsScreen extends ConsumerWidget {
  const BackupSettingsScreen({super.key});

  static const autoBackupSwitchKey = Key('settings.autoBackup.enabled');
  static const autoBackupFolderButtonKey = Key('settings.autoBackup.folder');
  static const autoBackupGrantPromptKey =
      Key('settings.autoBackup.grantPrompt');
  static const backupPassphraseFieldKey = BackupNowSection.passphraseFieldKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings.defaults;
    final controller = ref.read(settingsControllerProvider.notifier);
    final autoBackupAvailable =
        ref.watch(autoBackupAvailableProvider).value ?? false;

    return SettingsSubScreen(
      title: context.l10n.backupSettingsTitle,
      children: [
        const BackupNowSection(),
        if (autoBackupAvailable) ...[
          const SizedBox(height: AppDimens.base),
          _AutoBackupSettings(
            settings: settings,
            controller: controller,
            chooseFolder: () =>
                ref.read(autoBackupServiceProvider).chooseFolder(),
            applySchedule: (nextSettings) =>
                ref.read(autoBackupServiceProvider).applySchedule(nextSettings),
          ),
        ],
        const SizedBox(height: AppDimens.base),
        const BackupRestoreSection(),
      ],
    );
  }
}

class _AutoBackupSettings extends StatelessWidget {
  const _AutoBackupSettings({
    required this.settings,
    required this.controller,
    required this.chooseFolder,
    required this.applySchedule,
  });

  final AppSettings settings;
  final SettingsController controller;
  final Future<AutoBackupFolderGrant?> Function() chooseFolder;
  final Future<AutoBackupScheduleStatus> Function(AppSettings settings)
      applySchedule;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.dense),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: BackupSettingsScreen.autoBackupSwitchKey,
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.autoBackupSwitchTitle),
            subtitle: Text(settings.autoBackupLastStatus.label),
            value: settings.autoBackupEnabled,
            onChanged: (enabled) {
              final nextSettings =
                  settings.copyWith(autoBackupEnabled: enabled);
              unawaited(
                controller
                    .setAutoBackupEnabled(enabled)
                    .then((_) => applySchedule(nextSettings)),
              );
            },
          ),
          if (settings.autoBackupNeedsFolderGrant) ...[
            const SizedBox(height: AppDimens.dense),
            const _AutoBackupGrantPrompt(),
          ],
          const SizedBox(height: AppDimens.dense),
          OutlinedButton.icon(
            key: BackupSettingsScreen.autoBackupFolderButtonKey,
            onPressed: () {
              unawaited(_chooseBackupFolder());
            },
            icon: const Icon(Icons.folder_open_outlined),
            label: Text(
              settings.autoBackupFolderLabel ??
                  context.l10n.autoBackupChooseFolderButton,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseBackupFolder() async {
    final grant = await chooseFolder();
    if (grant == null) {
      return;
    }
    await controller.setAutoBackupFolder(
      uri: grant.uri,
      label: grant.label,
    );
    await applySchedule(
      settings.copyWith(
        autoBackupEnabled: true,
        autoBackupFolderUri: grant.uri,
        autoBackupFolderLabel: grant.label,
        autoBackupLastStatus: AutoBackupStatus.idle,
      ),
    );
  }
}

class _AutoBackupGrantPrompt extends StatelessWidget {
  const _AutoBackupGrantPrompt();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: context.l10n.autoBackupFolderWarningLabel,
      child: DecoratedBox(
        key: BackupSettingsScreen.autoBackupGrantPromptKey,
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
                Icons.folder_off_outlined,
                color: colorScheme.onErrorContainer,
              ),
              const SizedBox(width: AppDimens.dense),
              Expanded(
                child: Text(
                  context.l10n.autoBackupGrantPrompt,
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
