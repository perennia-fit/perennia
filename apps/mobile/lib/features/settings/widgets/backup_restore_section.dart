import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/local/app_database.dart';
import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../repositories/settings_repository.dart';
import 'settings_providers.dart';
import 'settings_shared.dart';

/// Settings → Backup & restore → Restore: brings a backup file's rows in
/// through the portable-archive merge.
///
/// Restore is merge-only by invariant, so this flow has exactly one outcome
/// and no "replace" choice: pick a file, unlock it if it is encrypted, review
/// what it holds, then merge. Every failure happens before the merge
/// transaction commits, which is why the error copy can promise nothing
/// changed.
class BackupRestoreSection extends ConsumerStatefulWidget {
  const BackupRestoreSection({super.key});

  static const restoreButtonKey = Key('settings.restore.button');
  static const passphraseFieldKey = Key('settings.restore.passphrase');
  static const unlockButtonKey = Key('settings.restore.unlock');
  static const confirmButtonKey = Key('settings.restore.confirm');
  static const doneButtonKey = Key('settings.restore.done');

  @override
  ConsumerState<BackupRestoreSection> createState() =>
      _BackupRestoreSectionState();
}

enum _RestoreProgress { idle, reading, restoring }

class _BackupRestoreSectionState extends ConsumerState<BackupRestoreSection> {
  _RestoreProgress _progress = _RestoreProgress.idle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final busy = _progress != _RestoreProgress.idle;
    final label = switch (_progress) {
      _RestoreProgress.idle => l10n.backupRestoreButton,
      _RestoreProgress.reading => l10n.backupRestoreReadingProgress,
      _RestoreProgress.restoring => l10n.backupRestoreRestoringProgress,
    };

    return SettingsSection(
      title: l10n.backupRestoreSectionTitle,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.backupRestoreDescription,
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppDimens.dense),
            SizedBox(
              height: AppDimens.touchTarget,
              child: OutlinedButton.icon(
                key: BackupRestoreSection.restoreButtonKey,
                onPressed: busy ? null : () => unawaited(_restore()),
                icon: const Icon(Icons.settings_backup_restore_outlined),
                label: Text(label),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.textPrimary,
                ),
              ),
            ),
            if (busy) ...[
              const SizedBox(height: AppDimens.dense),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _restore() async {
    final file = await ref.read(backupArchiveFilePickerProvider)();
    if (file == null || !mounted) {
      return;
    }
    final archives = ref.read(trainingRepositoriesProvider).portableArchives;
    // Held so the settings reload below still happens if the screen is
    // closed while the merge runs.
    final container = ProviderScope.containerOf(context, listen: false);

    try {
      _setProgress(_RestoreProgress.reading);
      final bytes = await file.readAsBytes();
      final plaintext = archives.isEncryptedPortableArchive(bytes)
          ? await _unlock(archives, bytes)
          : bytes;
      if (plaintext == null) {
        return;
      }
      final manifest = await archives.inspectPortableArchive(plaintext);
      _setProgress(_RestoreProgress.idle);

      if (!mounted || !await _confirm(manifest)) {
        return;
      }

      _setProgress(_RestoreProgress.restoring);
      final result = await archives.importPortableArchive(plaintext);
      // A backup carries the synced account settings row; reload them the way
      // sync does after applying one.
      container.invalidate(settingsControllerProvider);
      _setProgress(_RestoreProgress.idle);
      if (mounted) {
        await _showResult(result);
      }
    } on PortableArchiveNewerVersionException {
      await _showFailure((l10n) => l10n.backupRestoreNewerVersionMessage);
    } on PortableArchiveException {
      await _showFailure((l10n) => l10n.backupRestoreUnreadableMessage);
    } on IOException {
      await _showFailure((l10n) => l10n.backupRestoreUnreadableMessage);
    } finally {
      _setProgress(_RestoreProgress.idle);
    }
  }

  /// Asks for the passphrase until it decrypts the archive or the user
  /// cancels (null). Decrypting once here and passing the plaintext on keeps
  /// the deliberately slow key derivation to a single run.
  Future<List<int>?> _unlock(
    PortableArchiveRepository archives,
    List<int> bytes,
  ) async {
    var rejected = false;
    while (mounted) {
      _setProgress(_RestoreProgress.idle);
      final passphrase = await showDialog<String>(
        context: context,
        builder: (_) => _PassphraseDialog(rejected: rejected),
      );
      if (passphrase == null) {
        return null;
      }
      _setProgress(_RestoreProgress.reading);
      try {
        return await archives.decryptPortableArchive(
          bytes,
          passphrase: passphrase,
        );
      } on PortableArchivePassphraseException {
        rejected = true;
      }
    }
    return null;
  }

  Future<bool> _confirm(PortableArchiveManifest manifest) async {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final rowCounts = <String, int>{
      for (final entity in manifest.entities) entity.tableName: entity.rowCount,
    };
    int count(String tableName) => rowCounts[tableName] ?? 0;
    final contents = <String>[
      l10n.backupRestoreWorkoutCount(count(AppDatabase.workoutSessionsTable)),
      l10n.backupRestoreSetCount(count(AppDatabase.loggedSetsTable)),
      l10n.backupRestoreFoodEntryCount(count(AppDatabase.foodEntriesTable)),
      l10n.backupRestoreMetricReadingCount(
        count(AppDatabase.metricReadingsTable),
      ),
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.backupRestoreConfirmTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.backupRestoreCreatedAt(
                    DateFormat.yMMMd(locale)
                        .add_jm()
                        .format(manifest.createdAt.toLocal()),
                  ),
                  style: dialogContext.textStyles.body,
                ),
                const SizedBox(height: AppDimens.dense),
                for (final line in contents)
                  Text(line, style: dialogContext.textStyles.body),
                const SizedBox(height: AppDimens.dense),
                Text(
                  l10n.backupRestoreMergeExplanation,
                  style: dialogContext.textStyles.body.copyWith(
                    color: dialogContext.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.backupRestoreCancelAction),
            ),
            FilledButton(
              key: BackupRestoreSection.confirmButtonKey,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.backupRestoreConfirmAction),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<void> _showResult(PortableArchiveImportResult result) {
    final l10n = context.l10n;
    // Activity Log rows are history, not items the user would count.
    int total(Map<String, int> rowsByTable) => rowsByTable.entries
        .where((entry) => entry.key != AppDatabase.activityLogTable)
        .fold(0, (sum, entry) => sum + entry.value);
    final changed = total(result.changedRowsByTable);
    final unchanged = total(result.skippedRowsByTable);

    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.backupRestoreDoneTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.backupRestoreChangedCount(changed),
                style: dialogContext.textStyles.body,
              ),
              if (changed > 0 && unchanged > 0)
                Text(
                  l10n.backupRestoreUnchangedCount(unchanged),
                  style: dialogContext.textStyles.body.copyWith(
                    color: dialogContext.colors.textSecondary,
                  ),
                ),
            ],
          ),
          actions: [
            FilledButton(
              key: BackupRestoreSection.doneButtonKey,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.backupRestoreDoneAction),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showFailure(
    String Function(AppLocalizations l10n) messageOf,
  ) async {
    if (!mounted) {
      return;
    }
    _setProgress(_RestoreProgress.idle);
    final l10n = context.l10n;
    final message = messageOf(l10n);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.backupRestoreFailedTitle),
          content: Text(message, style: dialogContext.textStyles.body),
          actions: [
            FilledButton(
              key: BackupRestoreSection.doneButtonKey,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.backupRestoreDoneAction),
            ),
          ],
        );
      },
    );
  }

  void _setProgress(_RestoreProgress progress) {
    if (mounted && _progress != progress) {
      setState(() => _progress = progress);
    }
  }
}

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({required this.rejected});

  final bool rejected;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.isNotEmpty) {
      Navigator.of(context).pop(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.backupRestorePassphraseTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.backupRestorePassphraseMessage,
            style: context.textStyles.body,
          ),
          const SizedBox(height: AppDimens.dense),
          TextField(
            key: BackupRestoreSection.passphraseFieldKey,
            controller: _controller,
            autofocus: true,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.backupRestorePassphraseLabel,
              errorText:
                  widget.rejected ? l10n.backupRestorePassphraseRejected : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.backupRestoreCancelAction),
        ),
        FilledButton(
          key: BackupRestoreSection.unlockButtonKey,
          onPressed: _controller.text.isEmpty ? null : _submit,
          child: Text(l10n.backupRestoreUnlockAction),
        ),
      ],
    );
  }
}
