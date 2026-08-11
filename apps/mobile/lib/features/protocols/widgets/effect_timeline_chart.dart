import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../theme/theme.dart';
import '../models/effect_timeline_chart_data.dart';

/// The dose-overlay timeline (PROTOCOLS.md §4): plots the chosen
/// outcome's actual samples over the `Effect` window with the ACTUAL logged
/// `Dose`s overlaid as time-aligned vertical markers on the SAME time axis —
/// "join, never merge" (§2). Rendered with fl_chart; DERIVED on demand, this
/// widget stores nothing and computes nothing beyond re-projecting the data
/// it is handed. Dose markers plot the real (tz-frozen)
/// `Dose.tookAt` instants, never the plan/Schedule (§1.4). Strictly
/// descriptive: a plain line + plain markers, no causal framing,
/// no color-coded good/bad — every stroke uses a neutral theme token.
class EffectTimelineChart extends StatelessWidget {
  const EffectTimelineChart({
    super.key,
    required this.window,
    required this.samples,
    required this.doses,
  });

  final EffectWindow window;
  final List<EffectSample> samples;
  final List<DoseRecord> doses;

  static const noDataKey = Key('effect.timeline.noData');
  static const chartKey = Key('effect.timeline.chart');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final data = EffectTimelineChartData.build(
      window: window,
      samples: samples,
      doses: doses,
    );

    if (!data.hasAnyData || !data.hasRenderableSpan) {
      return Text(
        key: noDataKey,
        'No outcome data or logged Doses in this window yet.',
        style: TextStyle(color: colors.textSecondary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          key: chartKey,
          height: 140,
          child: LineChart(_chartData(data, colors)),
        ),
        const SizedBox(height: AppDimens.dense / 2),
        _Legend(colors: colors, doseCount: doses.length),
      ],
    );
  }

  LineChartData _chartData(EffectTimelineChartData data, AppColors colors) {
    return LineChartData(
      minX: data.minX,
      maxX: data.maxX,
      backgroundColor: Colors.transparent,
      gridData: FlGridData(
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: colors.divider, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: const FlTitlesData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
      extraLinesData: ExtraLinesData(
        verticalLines: <VerticalLine>[
          for (final marker in data.markers)
            VerticalLine(
              x: marker.daysSinceOrigin,
              color: colors.record,
              strokeWidth: 2,
              dashArray: const <int>[4, 3],
            ),
        ],
      ),
      lineBarsData: <LineChartBarData>[
        if (data.hasSeries)
          LineChartBarData(
            spots: <FlSpot>[
              for (final point in data.points)
                FlSpot(point.daysSinceOrigin, point.value),
            ],
            isCurved: false,
            color: colors.save,
            barWidth: 2,
            dotData: const FlDotData(show: true),
          ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.colors, required this.doseCount});

  final AppColors colors;
  final int doseCount;

  @override
  Widget build(BuildContext context) {
    final captionStyle =
        context.textStyles.caption.copyWith(color: colors.textSecondary);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(width: 12, height: 2, color: colors.save),
        const SizedBox(width: AppDimens.dense / 2),
        Text('Outcome', style: captionStyle),
        const SizedBox(width: AppDimens.base),
        Container(width: 2, height: 12, color: colors.record),
        const SizedBox(width: AppDimens.dense / 2),
        Text(
          '$doseCount logged ${doseCount == 1 ? 'Dose' : 'Doses'}',
          style: captionStyle,
        ),
      ],
    );
  }
}
