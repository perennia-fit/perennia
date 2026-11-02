import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/training/training_progress.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../focus/widgets/focus_manager_screen.dart';
import '../../focus/widgets/focus_visuals.dart';
import '../controllers/progress_controller.dart';
import 'progress_card.dart';
import 'progress_format.dart';

/// Weekly time per Focus over the period (D3, D8 card 3): one stacked bar
/// per week, every bar on the same scale, and a legend that names each Focus
/// with this week's time, so a Focus is never told by its color alone.
class FocusTimeCard extends ConsumerWidget {
  const FocusTimeCard({super.key});

  static const chartKey = Key('progress.focusTime.chart');
  static const focusesButtonKey = Key('progress.focusTime.focuses');

  /// A legend entry, keyed by Focus id or [noFocusKey].
  static Key legendKey(String focusKey) =>
      Key('progress.focusTime.legend.$focusKey');

  static const double chartHeight = 120;

  /// The gridline steps, in hours, from which the smallest that keeps at
  /// most five gridlines above zero is taken. A week has 168 hours, so 48
  /// always fits.
  static const List<int> gridStepsHours = <int>[1, 2, 4, 6, 12, 24, 48];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final title = l10n.progressFocusTimeTitle;
    final state = ref.watch(progressFocusTimeProvider);
    final data = state.value;
    if (state.hasError || data == null) {
      return ProgressCard.pending(title: title, failed: state.hasError);
    }
    final focuses = ProgressCardAction(
      key: focusesButtonKey,
      label: l10n.progressFocusesAction,
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const FocusManagerScreen()),
        );
      },
    );
    if (data.isEmpty) {
      return ProgressCard.empty(
        title: title,
        message: l10n.progressFocusTimeEmpty,
        action: focuses,
      );
    }

    final colors = context.colors;
    final entries = <_FocusEntry>[
      for (final key in data.keys)
        _FocusEntry(
          key: key,
          name: _focusName(context, data, key),
          color: _focusColor(colors, data, key),
          seconds: data.currentWeek.secondsByFocus[key] ?? 0,
        ),
    ];
    final caption = context.textStyles.caption.copyWith(
      color: colors.textSecondary,
    );
    return ProgressCard(
      title: title,
      action: focuses,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            key: chartKey,
            container: true,
            label: l10n.progressFocusTimeSemantics(
              entries
                  .map(
                    (entry) => l10n.progressFocusTimeEntry(
                      entry.name,
                      speakFocusDuration(entry.seconds, l10n),
                    ),
                  )
                  .join(', '),
            ),
            child: ExcludeSemantics(
              child: SizedBox(
                height: chartHeight,
                child: _Bars(data: data, entries: entries),
              ),
            ),
          ),
          const SizedBox(height: AppDimens.dense),
          ExcludeSemantics(
            child: Wrap(
              spacing: AppDimens.dense,
              runSpacing: AppDimens.dense / 2,
              children: [
                for (final entry in entries)
                  Row(
                    key: legendKey(entry.key),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Dot(color: entry.color),
                      const SizedBox(width: AppDimens.dense / 3),
                      // Flexible: a Focus name has no length limit, so a
                      // long one wraps within the card instead of
                      // overflowing it.
                      Flexible(
                        child: Text(
                          l10n.progressFocusTimeEntry(
                            entry.name,
                            formatFocusDuration(entry.seconds, l10n),
                          ),
                          style: caption.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _focusName(
    BuildContext context,
    ProgressFocusTime data,
    String key,
  ) {
    final l10n = context.l10n;
    if (key == noFocusKey) {
      return l10n.progressFocusTimeNoFocus;
    }
    final focus = data.focusesById[key];
    return focus == null
        ? l10n.progressFocusTimeUnknownFocus
        : focusDisplayName(context, focus);
  }

  /// "No Focus", and a Focus not on this device yet, use the `other` token,
  /// which is never a Focus's default.
  static Color _focusColor(
      AppColors colors, ProgressFocusTime data, String key) {
    final focus = data.focusesById[key];
    return focus == null
        ? colors.categoryColor('other')
        : resolvedFocusColor(focus, colors);
  }
}

class _FocusEntry {
  const _FocusEntry({
    required this.key,
    required this.name,
    required this.color,
    required this.seconds,
  });

  final String key;
  final String name;
  final Color color;
  final int seconds;
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: AppDimens.dense,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.data, required this.entries});

  final ProgressFocusTime data;
  final List<_FocusEntry> entries;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final caption = context.textStyles.caption.copyWith(
      color: colors.textSecondary,
    );

    // Each (week, Focus) amount is rounded to whole minutes once (D3); the
    // bars are drawn from those minutes.
    final hoursByWeek = <List<double>>[
      for (final week in data.weeks)
        <double>[
          for (final entry in entries)
            roundedFocusMinutes(week.secondsByFocus[entry.key] ?? 0) / 60,
        ],
    ];
    final tallest = hoursByWeek
        .map((hours) => hours.fold<double>(0, (sum, value) => sum + value))
        .fold<double>(0, math.max);
    final step = FocusTimeCard.gridStepsHours.firstWhere(
      (step) => (tallest / step).ceil() <= 5,
      orElse: () => FocusTimeCard.gridStepsHours.last,
    );
    final maxY = math.max(1, (tallest / step).ceil()) * step.toDouble();

    String axisLabel(double value) {
      final hours = value.round();
      return hours == 0 ? '0' : l10n.progressFocusTimeAxisHours(hours);
    }

    final painter = TextPainter(
      text: TextSpan(text: axisLabel(maxY), style: caption),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final axisWidth = painter.width + AppDimens.dense / 2;
    painter.dispose();

    return LayoutBuilder(
      builder: (context, constraints) {
        final slot = (constraints.maxWidth - axisWidth) / data.weeks.length;
        final barWidth = math.max(1.0, math.min(slot * 0.6, AppDimens.base));
        return BarChart(
          BarChartData(
            minY: 0,
            maxY: maxY,
            alignment: BarChartAlignment.spaceAround,
            backgroundColor: Colors.transparent,
            barTouchData: BarTouchData(enabled: false),
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: step.toDouble(),
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: colors.divider, strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              bottomTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: step.toDouble(),
                  reservedSize: axisWidth,
                  getTitlesWidget: (value, meta) => Text(
                    axisLabel(value),
                    style: caption.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
            barGroups: <BarChartGroupData>[
              for (final (index, hours) in hoursByWeek.indexed)
                BarChartGroupData(
                  x: index,
                  barRods: <BarChartRodData>[
                    _rod(hours, barWidth, colors),
                  ],
                ),
            ],
          ),
          duration: Duration.zero,
        );
      },
    );
  }

  /// One week's stacked bar: segments bottom to top in legend order, each
  /// outlined in the card surface color, so adjacent segments sit 1 dp apart.
  BarChartRodData _rod(List<double> hours, double width, AppColors colors) {
    final items = <BarChartRodStackItem>[];
    var top = 0.0;
    for (final (index, value) in hours.indexed) {
      if (value <= 0) {
        continue;
      }
      items.add(
        BarChartRodStackItem(
          top,
          top + value,
          entries[index].color,
          BorderSide(color: colors.surface),
        ),
      );
      top += value;
    }
    return BarChartRodData(
      toY: top,
      width: width,
      color: Colors.transparent,
      borderRadius: BorderRadius.zero,
      rodStackItems: items,
    );
  }
}
