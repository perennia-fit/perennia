import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme.dart';
import '../repositories/settings_repository.dart';
import '../services/auto_backup_service.dart';
import 'settings_shared.dart';

/// Settings → Backup & restore: scheduled encrypted backups to a
/// user-granted folder.
class BackupSettingsScreen extends ConsumerWidget {
  const BackupSettingsScreen({super.key});

  static const autoBackupSwitchKey = Key('settings.autoBackup.enabled');
  static const autoBackupFolderButtonKey = Key('settings.autoBackup.folder');
  static const autoBackupGrantPromptKey =
      Key('settings.autoBackup.grantPrompt');
  static const autoBackupPassphraseFieldKey =
      Key('settings.autoBackup.passphrase');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings.defaults;
    final controller = ref.read(settingsControllerProvider.notifier);

    return SettingsSubScreen(
      title: 'Backup & restore',
      children: [
        _AutoBackupSettings(
          settings: settings,
          controller: controller,
          chooseFolder: () => ref.read(autoBackupServiceProvider).chooseFolder(),
          applySchedule: (nextSettings) =>
              ref.read(autoBackupServiceProvider).applySchedule(nextSettings),
        ),
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
            title: const Text('Auto-backup'),
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
            label:
                Text(settings.autoBackupFolderLabel ?? 'Choose backup folder'),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimens.dense),
          _AutoBackupPassphraseField(
            value: settings.autoBackupEncryptionPassphrase,
            onChanged: controller.setAutoBackupEncryptionPassphrase,
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
      label: 'Auto-backup folder warning',
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
                  'Choose a backup folder again to resume auto-backup.',
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

class _AutoBackupPassphraseField extends StatefulWidget {
  const _AutoBackupPassphraseField({
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final Future<void> Function(String? value) onChanged;

  @override
  State<_AutoBackupPassphraseField> createState() =>
      _AutoBackupPassphraseFieldState();
}

class _AutoBackupPassphraseFieldState
    extends State<_AutoBackupPassphraseField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(covariant _AutoBackupPassphraseField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextText = widget.value ?? '';
    if (_controller.text != nextText) {
      _controller.text = nextText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: BackupSettingsScreen.autoBackupPassphraseFieldKey,
      controller: _controller,
      obscureText: true,
      decoration: const InputDecoration(
        labelText: 'Backup passphrase',
      ),
      onChanged: (value) {
        unawaited(widget.onChanged(value));
      },
    );
  }
}
