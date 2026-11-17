import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../protocols/widgets/protocol_reminders_settings.dart';
import '../../protocols/widgets/protocols_lock_settings.dart';
import '../repositories/settings_repository.dart';
import '../services/client_crash_reporting.dart';
import 'settings_shared.dart';

/// Settings → Privacy & security: crash-reporting opt-in, whether Today
/// shows Protocols on this device, the Protocols lock, and Protocol
/// reminders on this device.
class PrivacySettingsScreen extends ConsumerWidget {
  const PrivacySettingsScreen({super.key});

  static const crashReportingSwitchKey = Key('settings.crashReporting');
  static const debugCrashReportButtonKey =
      Key('settings.crashReporting.debugCrash');
  static const showProtocolsOnTodaySwitchKey =
      Key('settings.showProtocolsOnToday');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings.defaults;
    final controller = ref.read(settingsControllerProvider.notifier);

    return SettingsSubScreen(
      title: 'Privacy & security',
      children: [
        SettingsSection(
          children: [
            SwitchListTile(
              key: crashReportingSwitchKey,
              title: const Text('Crash reporting'),
              value: settings.crashReportingEnabled,
              onChanged: controller.setCrashReportingEnabled,
            ),
            SwitchListTile(
              key: showProtocolsOnTodaySwitchKey,
              title: Text(context.l10n.privacyShowProtocolsOnToday),
              subtitle: Text(context.l10n.privacyShowProtocolsOnTodaySubtitle),
              value: settings.showProtocolsOnToday,
              onChanged: controller.setShowProtocolsOnToday,
            ),
            const ProtocolsLockSettingsTile(),
            const ProtocolRemindersSettingsTile(),
            if (kDebugMode)
              _DebugCrashReportButton(
                enabled: settings.crashReportingEnabled,
                crashReporter: ref.read(clientCrashReporterProvider),
              ),
          ],
        ),
      ],
    );
  }
}

class _DebugCrashReportButton extends StatelessWidget {
  const _DebugCrashReportButton({
    required this.enabled,
    required this.crashReporter,
  });

  final bool enabled;
  final ClientCrashReporter crashReporter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.dense),
      child: SizedBox(
        height: AppDimens.touchTarget,
        child: OutlinedButton.icon(
          key: PrivacySettingsScreen.debugCrashReportButtonKey,
          onPressed: enabled
              ? () {
                  unawaited(
                    crashReporter.captureException(
                      StateError('Perennia debug crash'),
                      StackTrace.current,
                    ),
                  );
                }
              : null,
          icon: const Icon(Icons.report_problem_outlined),
          label: const Text('Send test crash'),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.colors.textPrimary,
          ),
        ),
      ),
    );
  }
}
