import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../theme/theme.dart';
import '../../sync/controllers/sync_status_controller.dart';

/// Scaffold shared by every Settings sub-screen: an app bar with the screen
/// title over a padded scrolling body.
class SettingsSubScreen extends StatelessWidget {
  const SettingsSubScreen({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDimens.base),
          children: children,
        ),
      ),
    );
  }
}

/// A group of settings rows separated by hairline dividers, with an optional
/// section title.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    this.title,
    required this.children,
  });

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    return Semantics(
      container: true,
      label: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(title, style: context.textStyles.h2),
            const SizedBox(height: AppDimens.dense),
          ],
          for (var index = 0; index < children.length; index += 1) ...[
            children[index],
            if (index != children.length - 1)
              Divider(color: context.colors.divider),
          ],
        ],
      ),
    );
  }
}

/// A navigation row: leading icon, title, current-value subtitle, trailing
/// chevron. The hub and list-style sub-screens are built from these.
class SettingsNavTile extends StatelessWidget {
  const SettingsNavTile({
    super.key,
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return ListTile(
      leading: Icon(icon, color: iconColor ?? context.colors.textSecondary),
      title: Text(title),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Icon(Icons.chevron_right, color: context.colors.textSecondary),
      onTap: onTap,
    );
  }
}

String formatWeightIncrement(double value) {
  final formatted = value.toStringAsFixed(3);
  return formatted
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String formatLastSuccessfulSync(DateTime? value) {
  if (value == null) {
    return 'Never';
  }
  return DateFormat.yMMMd().add_Hm().format(value.toLocal());
}

String syncStatusLabel(SyncStatusKind kind) {
  return switch (kind) {
    SyncStatusKind.idle => 'Not synced yet',
    SyncStatusKind.syncing => 'Syncing',
    SyncStatusKind.synced => 'Synced',
    SyncStatusKind.failed => 'Sync failed',
    SyncStatusKind.authExpired => 'Sign in required',
  };
}

IconData syncStatusIcon(SyncStatusKind kind) {
  return switch (kind) {
    SyncStatusKind.idle => Icons.sync_outlined,
    SyncStatusKind.syncing => Icons.sync_outlined,
    SyncStatusKind.synced => Icons.cloud_done_outlined,
    SyncStatusKind.failed => Icons.sync_problem_outlined,
    SyncStatusKind.authExpired => Icons.person_off_outlined,
  };
}

Color syncStatusColor(BuildContext context, SyncStatusKind kind) {
  final colorScheme = Theme.of(context).colorScheme;
  return switch (kind) {
    SyncStatusKind.synced => context.colors.save,
    SyncStatusKind.failed || SyncStatusKind.authExpired => colorScheme.error,
    SyncStatusKind.idle || SyncStatusKind.syncing => colorScheme.primary,
  };
}

String integrationSourceLabel(String source) {
  return switch (source) {
    'garmin' => 'Garmin',
    _ => source,
  };
}

String integrationStatusLabel(IntegrationStatusCondition condition) {
  return switch (condition) {
    IntegrationStatusCondition.ok => 'Connected',
    IntegrationStatusCondition.temporaryFailure => 'Feed failing',
    IntegrationStatusCondition.rateLimited => 'Backoff active',
    IntegrationStatusCondition.reauthRequired => 'Re-auth required',
  };
}

IconData integrationStatusIcon(IntegrationStatusCondition condition) {
  return switch (condition) {
    IntegrationStatusCondition.ok => Icons.cloud_done_outlined,
    IntegrationStatusCondition.temporaryFailure ||
    IntegrationStatusCondition.rateLimited =>
      Icons.sync_problem_outlined,
    IntegrationStatusCondition.reauthRequired => Icons.person_off_outlined,
  };
}

Color integrationStatusColor(
  BuildContext context,
  IntegrationStatusCondition condition,
) {
  final colorScheme = Theme.of(context).colorScheme;
  return switch (condition) {
    IntegrationStatusCondition.ok => context.colors.save,
    IntegrationStatusCondition.temporaryFailure ||
    IntegrationStatusCondition.rateLimited ||
    IntegrationStatusCondition.reauthRequired =>
      colorScheme.error,
  };
}

IntegrationStatusState? findIntegrationStatus(
  SyncStatusState status,
  String source,
) {
  for (final integration in status.integrationStatuses) {
    if (integration.source == source) {
      return integration;
    }
  }
  return null;
}

Color destructiveButtonForeground(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark
      ? context.colors.textPrimary
      : theme.colorScheme.error;
}
