import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/settings_repository.dart';
import 'settings_shared.dart';

/// Settings → Food data: whether the add-food picker may look foods up on
/// Open Food Facts. The offline food list works either way.
class FoodDataSettingsScreen extends ConsumerWidget {
  const FoodDataSettingsScreen({super.key});

  static const onlineFoodLookupsSwitchKey =
      Key('settings.foodData.onlineLookups');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings.defaults;
    final controller = ref.read(settingsControllerProvider.notifier);

    return SettingsSubScreen(
      title: 'Food data',
      children: [
        SettingsSection(
          children: [
            SwitchListTile(
              key: onlineFoodLookupsSwitchKey,
              title: const Text('Look up foods online'),
              subtitle: const Text(
                'Sends your search text or barcode to Open Food Facts. The '
                'offline food list works without it.',
              ),
              value: settings.onlineFoodLookups,
              onChanged: controller.setOnlineFoodLookups,
            ),
          ],
        ),
      ],
    );
  }
}
