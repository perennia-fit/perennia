import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../body_tracker/widgets/body_tracker_screen.dart';
import '../../metrics/widgets/metrics_screen.dart';
import '../../settings/widgets/settings_shared.dart';
import '../controllers/progress_controller.dart';
import 'focus_time_card.dart';
import 'protocols_progress_card.dart';
import 'this_week_card.dart';
import 'trained_days_card.dart';

/// The Progress root (docs/designs/progress-overview.md, D8): one period
/// control over a scroll of summary cards, each derived on read from data
/// the app already records and each opening a detail screen that already
/// exists, then the links to Body Tracker and Health metrics.
///
/// Home builds this only while Progress is selected, so its `autoDispose`
/// providers compute nothing on Today or Library; the list's
/// [PageStorageKey] brings its scroll position back on return.
class ProgressOverview extends ConsumerWidget {
  const ProgressOverview({super.key});

  static const listKey = PageStorageKey<String>('progress.overview');
  static const periodControlKey = Key('progress.period');
  static const bodyTrackerTileKey = Key('progress.more.bodyTracker');
  static const healthMetricsTileKey = Key('progress.more.healthMetrics');

  static Key periodKey(ProgressPeriod period) =>
      Key('progress.period.${period.name}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final period = ref.watch(progressPeriodProvider);
    const gap = SizedBox(height: AppDimens.dense);
    return SafeArea(
      child: ListView(
        key: listKey,
        padding: const EdgeInsets.all(AppDimens.base),
        children: [
          SegmentedButton<ProgressPeriod>(
            key: periodControlKey,
            showSelectedIcon: false,
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(
                Size.fromHeight(AppDimens.touchTarget),
              ),
            ),
            segments: <ButtonSegment<ProgressPeriod>>[
              for (final value in ProgressPeriod.values)
                ButtonSegment<ProgressPeriod>(
                  value: value,
                  label: Text(
                    switch (value) {
                      ProgressPeriod.weeks4 => l10n.progressPeriodWeeks4,
                      ProgressPeriod.weeks12 => l10n.progressPeriodWeeks12,
                      ProgressPeriod.year => l10n.progressPeriodYear,
                    },
                    key: periodKey(value),
                  ),
                ),
            ],
            selected: <ProgressPeriod>{period},
            onSelectionChanged: (selection) {
              ref
                  .read(progressPeriodProvider.notifier)
                  .select(selection.single);
            },
          ),
          gap,
          const ThisWeekCard(),
          gap,
          const TrainedDaysCard(),
          gap,
          const FocusTimeCard(),
          gap,
          // Absent, or nothing while loading, without leaving a gap.
          const _ProtocolsSlot(gap: gap),
          Card(
            margin: EdgeInsets.zero,
            child: SettingsNavTile(
              key: bodyTrackerTileKey,
              icon: Icons.monitor_weight_outlined,
              title: l10n.homeBodyTitle,
              subtitle: l10n.navBodyTracker,
              onTap: () {
                Navigator.of(context).pushNamed(BodyTrackerScreen.routeName);
              },
            ),
          ),
          gap,
          Card(
            margin: EdgeInsets.zero,
            child: SettingsNavTile(
              key: healthMetricsTileKey,
              icon: Icons.monitor_heart_outlined,
              title: l10n.homeHealthMetricsTitle,
              subtitle: l10n.metricsTitle,
              onTap: () {
                Navigator.of(context).pushNamed(MetricsScreen.routeName);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProtocolsSlot extends ConsumerWidget {
  const _ProtocolsSlot({required this.gap});

  final Widget gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(progressProtocolsProvider).value == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [const ProtocolsProgressCard(), gap],
    );
  }
}
