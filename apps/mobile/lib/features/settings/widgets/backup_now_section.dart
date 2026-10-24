import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../repositories/settings_repository.dart';
import '../services/backup_export_service.dart';
import 'settings_shared.dart';

/// Settings → Backup & restore → Back up: saves a backup file through the
/// platform save dialog, and holds the passphrase every backup is encrypted
/// with. See [BackupExportService] for why this is a foreground save.
class BackupNowSection extends ConsumerStatefulWidget {
  const BackupNowSection({super.key});

  static const backUpNowButtonKey = Key('settings.backup.now');
  static const passphraseFieldKey = Key('settings.backup.passphrase');
  static const failureDoneButtonKey = Key('settings.backup.failureDone');

  @override
  ConsumerState<BackupNowSection> createState() => _BackupNowSectionState();
}

class _BackupNowSectionState extends ConsumerState<BackupNowSection> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings.defaults;
    final controller = ref.read(settingsControllerProvider.notifier);

    return SettingsSection(
      title: l10n.backupNowSectionTitle,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.backupNowDescription,
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppDimens.dense),
            SizedBox(
              height: AppDimens.touchTarget,
              child: OutlinedButton.icon(
                key: BackupNowSection.backUpNowButtonKey,
                onPressed: _saving ? null : () => unawaited(_backUpNow()),
                icon: const Icon(Icons.save_alt_outlined),
                label: Text(
                  _saving ? l10n.backupNowProgress : l10n.backupNowButton,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.textPrimary,
                ),
              ),
            ),
            if (_saving) ...[
              const SizedBox(height: AppDimens.dense),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: AppDimens.base),
            _BackupPassphraseField(
              value: settings.autoBackupEncryptionPassphrase,
              onChanged: controller.setAutoBackupEncryptionPassphrase,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _backUpNow() async {
    setState(() => _saving = true);
    final result = await ref.read(backupExportServiceProvider).backUpNow();
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);

    final l10n = context.l10n;
    switch (result.outcome) {
      case BackupSaveOutcome.saved:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.backupNowSavedMessage)),
        );
      case BackupSaveOutcome.cancelled:
        return;
      case BackupSaveOutcome.unsupported:
        await _showFailure(l10n.backupNowUnsupportedMessage);
      case BackupSaveOutcome.failed:
        await _showFailure(l10n.backupNowFailedMessage);
    }
  }

  Future<void> _showFailure(String message) {
    final l10n = context.l10n;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.backupNowFailedTitle),
          content: Text(message, style: dialogContext.textStyles.body),
          actions: [
            FilledButton(
              key: BackupNowSection.failureDoneButtonKey,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.backupRestoreDoneAction),
            ),
          ],
        );
      },
    );
  }
}

/// The passphrase both Back up now and auto-backup encrypt with. It is
/// stored as `autoBackupEncryptionPassphrase` because auto-backup came
/// first; the persisted name stays so existing settings keep loading.
class _BackupPassphraseField extends StatefulWidget {
  const _BackupPassphraseField({
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final Future<void> Function(String? value) onChanged;

  @override
  State<_BackupPassphraseField> createState() => _BackupPassphraseFieldState();
}

class _BackupPassphraseFieldState extends State<_BackupPassphraseField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(covariant _BackupPassphraseField oldWidget) {
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
    final l10n = context.l10n;
    return TextField(
      key: BackupNowSection.passphraseFieldKey,
      controller: _controller,
      obscureText: true,
      decoration: InputDecoration(
        labelText: l10n.backupPassphraseLabel,
        helperText: l10n.backupPassphraseHelper,
        helperMaxLines: 3,
      ),
      onChanged: (value) {
        unawaited(widget.onChanged(value));
      },
    );
  }
}
