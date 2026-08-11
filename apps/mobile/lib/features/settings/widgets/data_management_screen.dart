import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../theme/theme.dart';
import 'settings_shared.dart';

/// Settings → Data management: destructive local-data operations, isolated
/// from routine settings. Erase remains confirmation-gated (soft-delete +
/// tombstones underneath; restore stays merge-only and separate).
class DataManagementScreen extends ConsumerWidget {
  const DataManagementScreen({
    super.key,
    this.onEraseAllData,
  });

  final Future<void> Function()? onEraseAllData;

  static const eraseAllDataButtonKey = Key('settings.eraseAllData');
  static const confirmEraseAllDataButtonKey =
      Key('settings.eraseAllData.confirm');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsSubScreen(
      title: 'Data management',
      children: [
        Text('Danger zone', style: context.textStyles.h2),
        const SizedBox(height: AppDimens.dense),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.error),
            borderRadius: AppRadii.cardMd,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Erase local workouts, exercises, routines, timers, and '
                  'analytics source data from this device.',
                  style: context.textStyles.body,
                ),
                const SizedBox(height: AppDimens.dense),
                Semantics(
                  label: 'Erase all data, confirmation required',
                  button: true,
                  child: SizedBox(
                    height: AppDimens.touchTarget,
                    child: OutlinedButton.icon(
                      key: eraseAllDataButtonKey,
                      onPressed: () {
                        unawaited(
                          _confirmEraseAllData(
                            context,
                            onEraseAllData ??
                                () => ref
                                    .read(trainingRepositoriesProvider)
                                    .eraseAllData(),
                          ),
                        );
                      },
                      icon: Icon(
                        Icons.delete_forever_outlined,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      label: const Text('Erase all data'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.colors.textPrimary,
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppDimens.base),
        Text(
          'Imported integration data is purged from its integration screen '
          '(Settings → Integrations).',
          style: context.textStyles.body.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmEraseAllData(
    BuildContext context,
    Future<void> Function() eraseAllData,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Erase all data?'),
          content: const Text(
            'This clears local workouts, exercises, routines, timers, and '
            'analytics source data on this device. Backup restore is separate.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              key: confirmEraseAllDataButtonKey,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Erase'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await eraseAllData();
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Local data erased')),
    );
  }
}
