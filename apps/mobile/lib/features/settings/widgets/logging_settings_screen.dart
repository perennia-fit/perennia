import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme.dart';
import '../repositories/settings_repository.dart';
import 'settings_shared.dart';

/// Settings → Logging: set-entry behavior on the Training Screen.
class LoggingSettingsScreen extends ConsumerWidget {
  const LoggingSettingsScreen({super.key});

  static const defaultWeightIncrementFieldKey =
      Key('settings.defaultWeightIncrement');
  static const prTrackingSwitchKey = Key('settings.prTracking');
  static const autoSelectNextSetSwitchKey = Key('settings.autoSelectNextSet');
  static const restTimerSoundsSwitchKey = Key('settings.restTimerSounds');
  static const keepScreenOnSwitchKey = Key('settings.keepScreenOn');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings.defaults;
    final controller = ref.read(settingsControllerProvider.notifier);

    return SettingsSubScreen(
      title: 'Logging',
      children: [
        SettingsSection(
          children: [
            _DefaultWeightIncrementField(
              value: settings.defaultWeightIncrement,
              onChanged: controller.setDefaultWeightIncrement,
            ),
            SwitchListTile(
              key: prTrackingSwitchKey,
              title: const Text('PR tracking'),
              value: settings.prTrackingEnabled,
              onChanged: controller.setPrTrackingEnabled,
            ),
            SwitchListTile(
              key: autoSelectNextSetSwitchKey,
              title: const Text('Auto-select next set'),
              value: settings.autoSelectNextSet,
              onChanged: controller.setAutoSelectNextSet,
            ),
            SwitchListTile(
              key: restTimerSoundsSwitchKey,
              title: const Text('Timer sounds & vibration'),
              subtitle: const Text(
                "Beep before rest ends, alert when it's done",
              ),
              value: settings.restTimerSoundsEnabled,
              onChanged: controller.setRestTimerSoundsEnabled,
            ),
            SwitchListTile(
              key: keepScreenOnSwitchKey,
              title: const Text('Keep screen on'),
              value: settings.keepScreenOn,
              onChanged: controller.setKeepScreenOn,
            ),
          ],
        ),
      ],
    );
  }
}

class _DefaultWeightIncrementField extends StatefulWidget {
  const _DefaultWeightIncrementField({
    required this.value,
    required this.onChanged,
  });

  final double value;
  final Future<void> Function(double value) onChanged;

  @override
  State<_DefaultWeightIncrementField> createState() =>
      _DefaultWeightIncrementFieldState();
}

class _DefaultWeightIncrementFieldState
    extends State<_DefaultWeightIncrementField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: formatWeightIncrement(widget.value));
  }

  @override
  void didUpdateWidget(covariant _DefaultWeightIncrementField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value ||
        _controller.text == formatWeightIncrement(widget.value)) {
      return;
    }
    _controller.text = formatWeightIncrement(widget.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.dense),
      child: TextField(
        key: LoggingSettingsScreen.defaultWeightIncrementFieldKey,
        controller: _controller,
        decoration: const InputDecoration(
          labelText: 'Default weight increment',
          suffixText: 'kg/lb',
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (value) {
          final parsed = double.tryParse(value);
          if (parsed == null || parsed <= 0) {
            return;
          }
          unawaited(widget.onChanged(parsed));
        },
      ),
    );
  }
}
