import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme.dart';
import '../repositories/settings_repository.dart';
import 'settings_shared.dart';

/// Settings → General: display and calendar preferences.
class GeneralSettingsScreen extends ConsumerWidget {
  const GeneralSettingsScreen({super.key});

  static const themePreferenceKey = Key('settings.themePreference');
  static const unitSystemKey = Key('settings.unitSystem');
  static const weekStartDayKey = Key('settings.weekStartDay');
  static const homeScreenDisplayKey = Key('settings.homeScreenDisplay');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings.defaults;
    final controller = ref.read(settingsControllerProvider.notifier);

    return SettingsSubScreen(
      title: 'General',
      children: [
        SettingsSection(
          children: [
            _SegmentedPreference<AppThemePreference>(
              key: themePreferenceKey,
              label: 'Theme',
              selected: settings.themePreference,
              values: AppThemePreference.values,
              labelFor: (value) => value.label,
              onChanged: controller.setThemePreference,
            ),
            _SegmentedPreference<UnitSystem>(
              key: unitSystemKey,
              label: 'Units',
              selected: settings.unitSystem,
              values: UnitSystem.values,
              labelFor: (value) => value.label,
              onChanged: controller.setUnitSystem,
            ),
            _SegmentedPreference<WeekStartDay>(
              key: weekStartDayKey,
              label: 'Week starts',
              selected: settings.weekStartDay,
              values: WeekStartDay.values,
              labelFor: (value) => value.label,
              onChanged: controller.setWeekStartDay,
            ),
            _SegmentedPreference<HomeScreenDisplay>(
              key: homeScreenDisplayKey,
              label: 'Home display',
              selected: settings.homeScreenDisplay,
              values: HomeScreenDisplay.values,
              labelFor: (value) => value.label,
              onChanged: controller.setHomeScreenDisplay,
            ),
          ],
        ),
      ],
    );
  }
}

class _SegmentedPreference<T> extends StatelessWidget {
  const _SegmentedPreference({
    super.key,
    required this.label,
    required this.selected,
    required this.values,
    required this.labelFor,
    required this.onChanged,
  });

  final String label;
  final T selected;
  final List<T> values;
  final String Function(T value) labelFor;
  final Future<void> Function(T value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.dense),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.textStyles.caption),
          const SizedBox(height: AppDimens.dense),
          Semantics(
            label: label,
            child: SegmentedButton<T>(
              selected: <T>{selected},
              segments: [
                for (final value in values)
                  ButtonSegment<T>(
                    value: value,
                    label: Text(labelFor(value)),
                  ),
              ],
              onSelectionChanged: (selection) {
                unawaited(onChanged(selection.single));
              },
            ),
          ),
        ],
      ),
    );
  }
}
