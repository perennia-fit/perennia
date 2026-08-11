import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme.dart';
import '../../protocols/widgets/protocols_lock_settings.dart';
import '../repositories/settings_repository.dart';
import '../services/client_crash_reporting.dart';
import 'settings_shared.dart';

/// Settings → Privacy & security: crash-reporting opt-in and the
/// Supplements lock.
class PrivacySettingsScreen extends ConsumerWidget {
  const PrivacySettingsScreen({super.key});

  static const crashReportingSwitchKey = Key('settings.crashReporting');
  static const debugCrashReportButtonKey =
      Key('settings.crashReporting.debugCrash');

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
            const ProtocolsLockSettingsTile(),
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
