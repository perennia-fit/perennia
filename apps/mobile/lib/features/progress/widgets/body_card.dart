import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../body_tracker/widgets/body_tracker_screen.dart';
import '../controllers/progress_controller.dart';
import 'progress_card.dart';
import 'progress_sparkline.dart';

/// The curated Body Tracker measurements over the period (D5, D8 card 6):
/// one row per measurement with a Reading in the period, each with its
/// latest Trend, the Trend's change over the period and a chart of the
/// period's Readings as dots under the Trend line.
///
/// Values keep the Reading's own unit, as Body Tracker shows them; nothing
/// is converted to the unit system. The change has an arrow and a number,
/// never a color, because a fall is good for one measurement and bad for
/// another.
class BodyCard extends ConsumerWidget {
  const BodyCard({super.key});

  static const bodyTrackerButtonKey = Key('progress.body.bodyTracker');

  static Key rowKey(String measurementId) =>
      Key('progress.body.row.$measurementId');
  static Key trendKey(String measurementId) =>
      Key('progress.body.trend.$measurementId');
  static Key changeKey(String measurementId) =>
      Key('progress.body.change.$measurementId');
  static Key chartKey(String measurementId) =>
      Key('progress.body.chart.$measurementId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final title = l10n.progressBodyTitle;
    final state = ref.watch(progressBodyProvider);
    final rows = state.value;
    if (state.hasError || rows == null) {
      return ProgressCard.pending(title: title, failed: state.hasError);
    }
    final bodyTracker = ProgressCardAction(
      key: bodyTrackerButtonKey,
      label: l10n.progressBodyTrackerAction,
      onPressed: () {
        Navigator.of(context).pushNamed(BodyTrackerScreen.routeName);
      },
    );
    if (rows.isEmpty) {
      return ProgressCard.empty(
        title: title,
        message: l10n.progressBodyEmpty,
        emptyAction: bodyTracker,
      );
    }
    const gap = SizedBox(height: AppDimens.dense);
    return ProgressCard(
      title: title,
      action: bodyTracker,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.progressBodyTrendHint,
            style: context.textStyles.caption.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          for (final row in rows) ...[gap, _Row(row: row)],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row});

  final ProgressBodyRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final unit = measurementUnitLabel(l10n, row.unit);
    final change = row.change;
    const numerals = [FontFeature.tabularFigures()];
    return Column(
      key: BodyCard.rowKey(row.measurementId),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A name has no length limit: two lines, then an ellipsis, so a
            // long one never pushes the values off the card.
            Expanded(
              child: Text(
                row.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.body.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: AppDimens.dense),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  l10n.bodyTrackerValueWithUnit(
                    _oneDecimal(row.latestTrend),
                    unit,
                  ),
                  key: BodyCard.trendKey(row.measurementId),
                  style: context.textStyles.body.copyWith(
                    color: colors.textPrimary,
                    fontFeatures: numerals,
                  ),
                ),
                if (change != null)
                  Text(
                    _changeLabel(l10n, change, unit),
                    key: BodyCard.changeKey(row.measurementId),
                    style: context.textStyles.caption.copyWith(
                      color: colors.textSecondary,
                      fontFeatures: numerals,
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppDimens.dense / 3),
        Semantics(
          container: true,
          label: l10n.progressBodyChartSemantics(row.readings.length, row.name),
          child: ExcludeSemantics(
            child: SizedBox(
              key: BodyCard.chartKey(row.measurementId),
              height: AppDimens.progressBodyChartHeight,
              child: ProgressSparkline(
                points: <ProgressSparklinePoint>[
                  for (final reading in row.readings)
                    ProgressSparklinePoint(x: reading.at, y: reading.value),
                ],
                overlay: <ProgressSparklinePoint>[
                  for (final reading in row.readings)
                    ProgressSparklinePoint(x: reading.at, y: reading.trend),
                ],
                pointColor: colors.textSecondary,
                overlayColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// D8's change label: "↓ 1.6 kg", or "No change" when the change rounds
  /// to 0.0. The arrow follows the rounded number, so it never points at a
  /// change the label shows as nothing.
  static String _changeLabel(
    AppLocalizations l10n,
    double change,
    String unit,
  ) {
    final magnitude = _oneDecimal(change.abs());
    if (magnitude == '0.0') {
      return l10n.progressBodyNoChange;
    }
    final value = l10n.bodyTrackerValueWithUnit(magnitude, unit);
    return change > 0
        ? l10n.progressBodyChangeUp(value)
        : l10n.progressBodyChangeDown(value);
  }
}

/// [value] to one decimal, rounded half up in magnitude (D8). Unlike Key
/// exercises' loads, a trailing ".0" stays: every Body value has one decimal.
String _oneDecimal(double value) {
  final tenths = (value.abs() * 10).round();
  final text = (tenths / 10).toStringAsFixed(1);
  return value < 0 && tenths != 0 ? '-$text' : text;
}
