import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/training_repositories.dart'
    show ProtocolDayDate;
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../settings/repositories/settings_repository.dart';
import '../../settings/widgets/settings_shared.dart';
import '../../training/services/timer_background_scheduler.dart';
import '../services/protocol_reminder_scheduler.dart';

/// "Reminders scheduled through `<date>`" (CUJ 11). The Protocol screen and
/// the reminder status screen both show it, so both format the date here.
String protocolRemindersScheduledThroughLabel(
  AppLocalizations l10n,
  ProtocolDayDate horizonEnd,
) {
  return l10n.protocolRemindersScheduledThrough(
    DateFormat.yMMMd().format(horizonEnd.toLocalDateTime()),
  );
}

/// The style of every reminder action button (Allow, Open settings): the
/// primary text colour, and at least a 48 dp touch target.
ButtonStyle protocolReminderActionStyle(AppColors colors) {
  return TextButton.styleFrom(
    foregroundColor: colors.textPrimary,
    minimumSize: const Size(0, AppDimens.touchTarget),
  );
}

/// One reminder notice: a notifications-off icon, the [message] that says
/// what is wrong in words (the icon only echoes it), and its action. The
/// Protocol Day view's banner (CUJ 12) and the Protocol screen's denied
/// state (CUJ 10) both use it.
class ProtocolReminderNotice extends StatelessWidget {
  const ProtocolReminderNotice({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.actionKey,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        ExcludeSemantics(
          child: Icon(
            Icons.notifications_off_outlined,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(width: AppDimens.dense),
        Expanded(
          child: Text(message, style: TextStyle(color: colors.textPrimary)),
        ),
        TextButton(
          key: actionKey,
          style: protocolReminderActionStyle(colors),
          onPressed: onAction,
          child: Text(actionLabel),
        ),
      ],
    );
  }
}

/// The Settings "Supplement reminders" row (file 58), under
/// `ProtocolsLockSettingsTile` and following its pattern: it opens the
/// reminder status screen.
///
/// Like the lock, this controls device-level behaviour only. It never
/// changes what syncs, and nothing it shows is stored.
class ProtocolRemindersSettingsTile extends StatelessWidget {
  const ProtocolRemindersSettingsTile({super.key});

  static const tileKey = Key('settings.protocolReminders');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListTile(
      key: tileKey,
      contentPadding: EdgeInsets.zero,
      minTileHeight: AppDimens.touchTarget,
      title: Text(l10n.protocolRemindersSettingsTile),
      subtitle: Text(l10n.protocolRemindersSettingsTileSubtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const ProtocolRemindersSettingsScreen(),
          ),
        ),
      ),
    );
  }
}

/// The reminder status screen (D5, CUJs 9, 11 and 12): the device switch,
/// the notification permission, and how far ahead reminders are scheduled.
/// Opening it runs the reconciler, which reads the plugin's pending list
/// live, so what it shows is current; it stores nothing. It names no
/// Compound, so it sits outside the Supplements lock like the rest of
/// Settings.
class ProtocolRemindersSettingsScreen extends ConsumerStatefulWidget {
  const ProtocolRemindersSettingsScreen({super.key});

  static const deviceSwitchKey = Key('settings.protocolReminders.device');
  static const permissionKey = Key('settings.protocolReminders.permission');
  static const allowButtonKey = Key('settings.protocolReminders.allow');
  static const openSettingsButtonKey =
      Key('settings.protocolReminders.openSettings');
  static const horizonKey = Key('settings.protocolReminders.horizon');

  @override
  ConsumerState<ProtocolRemindersSettingsScreen> createState() =>
      _ProtocolRemindersSettingsScreenState();
}

class _ProtocolRemindersSettingsScreenState
    extends ConsumerState<ProtocolRemindersSettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(protocolReminderSchedulerProvider).reconcile());
      }
    });
  }

  Future<void> _setDeviceSwitch(bool enabled) async {
    final scheduler = ref.read(protocolReminderSchedulerProvider);
    await ref
        .read(settingsControllerProvider.notifier)
        .setProtocolRemindersOnThisDevice(enabled);
    await scheduler.reconcile();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings.defaults;
    final status = ref.watch(protocolReminderStatusProvider).value ??
        ProtocolReminderStatus.unknown;
    final scheduler = ref.read(protocolReminderSchedulerProvider);
    final permission = status.permission;
    final horizonEnd = status.horizonEnd;

    final String? permissionLabel = switch (permission) {
      TimerBackgroundPermissionStatus.granted =>
        l10n.protocolRemindersPermissionGranted,
      TimerBackgroundPermissionStatus.denied =>
        l10n.protocolRemindersPermissionDenied,
      TimerBackgroundPermissionStatus.notDetermined =>
        l10n.protocolRemindersPermissionNotDetermined,
      TimerBackgroundPermissionStatus.unsupported =>
        l10n.protocolRemindersPermissionUnsupported,
      null => null,
    };
    final Widget? permissionAction = switch (permission) {
      TimerBackgroundPermissionStatus.notDetermined => TextButton(
          key: ProtocolRemindersSettingsScreen.allowButtonKey,
          style: protocolReminderActionStyle(colors),
          onPressed: () => unawaited(scheduler.requestPermission()),
          child: Text(l10n.protocolRemindersAllow),
        ),
      TimerBackgroundPermissionStatus.denied => TextButton(
          key: ProtocolRemindersSettingsScreen.openSettingsButtonKey,
          style: protocolReminderActionStyle(colors),
          onPressed: () => unawaited(scheduler.openNotificationSettings()),
          child: Text(l10n.protocolRemindersOpenSettings),
        ),
      _ => null,
    };

    return SettingsSubScreen(
      title: l10n.protocolRemindersSettingsTitle,
      children: [
        SettingsSection(
          children: [
            SwitchListTile(
              key: ProtocolRemindersSettingsScreen.deviceSwitchKey,
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.protocolRemindersDeviceSwitch),
              subtitle: Text(l10n.protocolRemindersDeviceSwitchSubtitle),
              value: settings.protocolRemindersOnThisDevice,
              onChanged: (enabled) => unawaited(_setDeviceSwitch(enabled)),
            ),
            ListTile(
              key: ProtocolRemindersSettingsScreen.permissionKey,
              contentPadding: EdgeInsets.zero,
              minTileHeight: AppDimens.touchTarget,
              title: Text(l10n.protocolRemindersPermissionLabel),
              subtitle: permissionLabel == null ? null : Text(permissionLabel),
              trailing: permissionAction,
            ),
            if (horizonEnd != null)
              Padding(
                key: ProtocolRemindersSettingsScreen.horizonKey,
                padding:
                    const EdgeInsets.symmetric(vertical: AppDimens.dense),
                child: Text(
                  protocolRemindersScheduledThroughLabel(l10n, horizonEnd),
                  style: context.textStyles.body
                      .copyWith(color: colors.textSecondary),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
