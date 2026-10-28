import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../models/consistency_chart_data.dart';

/// The Consistency chart (D6, Phase 4 file 42): each logged Dose's time of
/// day (Y) on its date (X), against the planned times. Rendered with
/// fl_chart like the Effect timeline, from the pure [ConsistencyChartData];
/// it stores nothing and computes nothing beyond re-projecting it.
///
/// fl_chart's `ScatterChart` draws points only, with no line segments and no
/// shaded ranges, so this is a `LineChart` drawn as a scatter: the Doses are
/// a series of dots with no line, each planned time is a two-point segment
/// over the days it applies, the untimed planned doses are segments in a
/// band along the top, and paused and off-cycle days are shaded ranges.
///
/// Strictly descriptive: no verdict, no ratio. Color is never the only
/// signal. A Dose that filled a slot is a filled dot and an extra Dose is a
/// ring; the planned line, the untimed band and both shadings are named in
/// the legend; and each shaded run is labelled under the chart when it is
/// wide enough for its word. Every color is a theme token.
class ConsistencyChart extends StatelessWidget {
  const ConsistencyChart({super.key, required this.range});

  final ConsistencyRange range;

  static const chartKey = Key('consistency.chart');
  static const emptyKey = Key('consistency.chart.empty');
  static const legendKey = Key('consistency.chart.legend');

  static Key shadeLabelKey(int startIndex) =>
      Key('consistency.chart.shade-$startIndex');

  /// The width the Y axis's time labels reserve, so the shade labels under
  /// the chart line up with the plot.
  static const double _leftTitlesWidth = 56;

  /// A shade run narrower than this has no room for its word; the legend
  /// still names its shading.
  static const double _minShadeLabelWidth = 56;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final data = ConsistencyChartData.build(
      from: range.from,
      to: range.to,
      planDays: range.planDays,
      dayStatuses: range.dayStatuses,
      doses: range.doses,
    );
    if (!data.hasAnyData) {
      return Text(
        key: emptyKey,
        l10n.consistencyChartEmpty,
        style: TextStyle(color: colors.textSecondary),
      );
    }

    final dateFormat = DateFormat.yMMMd();
    final fromLabel = dateFormat.format(range.from.toLocalDateTime());
    final toLabel = dateFormat.format(range.to.toLocalDateTime());
    final captionStyle =
        context.textStyles.caption.copyWith(color: colors.textSecondary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          container: true,
          label: l10n.consistencyChartSemantics(fromLabel, toLabel),
          child: ExcludeSemantics(
            child: SizedBox(
              key: chartKey,
              height: 220,
              child: LineChart(_chartData(context, data, colors)),
            ),
          ),
        ),
        _ShadeLabels(data: data, colors: colors),
        Padding(
          padding: const EdgeInsets.only(left: _leftTitlesWidth),
          child: Row(
            children: <Widget>[
              Expanded(child: Text(fromLabel, style: captionStyle)),
              Text(toLabel, style: captionStyle),
            ],
          ),
        ),
        const SizedBox(height: AppDimens.dense / 2),
        _Legend(key: legendKey, data: data, colors: colors),
      ],
    );
  }

  LineChartData _chartData(
    BuildContext context,
    ConsistencyChartData data,
    AppColors colors,
  ) {
    final l10n = context.l10n;
    final timeFormat = DateFormat.j();
    final filled = <FlSpot>[
      for (final point in data.points)
        if (!point.isExtra) FlSpot(point.x, point.y),
    ];
    final extras = <FlSpot>[
      for (final point in data.points)
        if (point.isExtra) FlSpot(point.x, point.y),
    ];

    LineChartBarData dots(List<FlSpot> spots, {required bool ring}) {
      return LineChartBarData(
        spots: spots,
        color: Colors.transparent,
        barWidth: 0,
        dotData: FlDotData(
          getDotPainter: (_, __, ___, ____) => ring
              ? FlDotCirclePainter(
                  radius: 3.5,
                  color: colors.surface,
                  strokeWidth: 1.5,
                  strokeColor: colors.textPrimary,
                )
              : FlDotCirclePainter(
                  radius: 3.5,
                  color: colors.textPrimary,
                  strokeWidth: 0,
                ),
        ),
      );
    }

    return LineChartData(
      minX: data.minX,
      maxX: data.maxX,
      minY: data.minY,
      maxY: data.maxY,
      backgroundColor: Colors.transparent,
      clipData: const FlClipData.all(),
      borderData: FlBorderData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
      gridData: FlGridData(
        drawVerticalLine: false,
        horizontalInterval: 360,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: colors.divider, strokeWidth: 1),
      ),
      rangeAnnotations: RangeAnnotations(
        verticalRangeAnnotations: <VerticalRangeAnnotation>[
          for (final shade in data.shades)
            VerticalRangeAnnotation(
              x1: shade.run.startX,
              x2: shade.run.endX,
              color: _shadeColor(shade.kind, colors),
            ),
        ],
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        bottomTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: _leftTitlesWidth,
            interval: 120,
            getTitlesWidget: (value, meta) {
              final String? label;
              if (value == ConsistencyChartData.untimedBandY) {
                label = data.hasUntimedBand ? l10n.plannedListAnyTime : null;
              } else if (value < ConsistencyChartData.minutesPerDay &&
                  value % 360 == 0) {
                label = timeFormat.format(
                  DateTime(2000, 1, 1, value ~/ 60),
                );
              } else {
                label = null;
              }
              if (label == null) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  label,
                  style: context.textStyles.caption
                      .copyWith(color: colors.textSecondary),
                ),
              );
            },
          ),
        ),
      ),
      lineBarsData: <LineChartBarData>[
        for (final segment in data.plannedSegments)
          LineChartBarData(
            spots: <FlSpot>[
              FlSpot(segment.run.startX, segment.y),
              FlSpot(segment.run.endX, segment.y),
            ],
            color: colors.textSecondary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        for (final run in data.untimedRuns)
          LineChartBarData(
            spots: <FlSpot>[
              FlSpot(run.startX, ConsistencyChartData.untimedBandY),
              FlSpot(run.endX, ConsistencyChartData.untimedBandY),
            ],
            color: colors.textSecondary,
            barWidth: 6,
            dotData: const FlDotData(show: false),
          ),
        if (filled.isNotEmpty) dots(filled, ring: false),
        if (extras.isNotEmpty) dots(extras, ring: true),
      ],
    );
  }
}

Color _shadeColor(ConsistencyShadeKind kind, AppColors colors) =>
    switch (kind) {
      ConsistencyShadeKind.paused => colors.divider,
      ConsistencyShadeKind.offCycle => colors.divider.withValues(alpha: 0.5),
    };

String _shadeLabel(ConsistencyShadeKind kind, AppLocalizations l10n) =>
    switch (kind) {
      ConsistencyShadeKind.paused => l10n.dayStatusPaused,
      ConsistencyShadeKind.offCycle => l10n.dayStatusOffCycle,
    };

/// Each shaded run's word under the chart, aligned with the run, when the
/// run is wide enough to hold it.
class _ShadeLabels extends StatelessWidget {
  const _ShadeLabels({required this.data, required this.colors});

  final ConsistencyChartData data;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    if (data.shades.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    return SizedBox(
      height: 20,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final plotWidth =
              constraints.maxWidth - ConsistencyChart._leftTitlesWidth;
          if (plotWidth <= 0) {
            return const SizedBox.shrink();
          }
          final dayWidth = plotWidth / data.dayCount;
          return Stack(
            children: <Widget>[
              for (final shade in data.shades)
                if (shade.run.dayCount * dayWidth >=
                    ConsistencyChart._minShadeLabelWidth)
                  Positioned(
                    key: ConsistencyChart.shadeLabelKey(shade.run.startIndex),
                    left: ConsistencyChart._leftTitlesWidth +
                        shade.run.startX * dayWidth,
                    width: shade.run.dayCount * dayWidth,
                    top: 0,
                    bottom: 0,
                    child: Text(
                      _shadeLabel(shade.kind, l10n),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: context.textStyles.caption
                          .copyWith(color: colors.textSecondary),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({super.key, required this.data, required this.colors});

  final ConsistencyChartData data;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final captionStyle =
        context.textStyles.caption.copyWith(color: colors.textSecondary);
    final shadeKinds = data.shades.map((shade) => shade.kind).toSet();

    Widget item(Widget swatch, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ExcludeSemantics(child: swatch),
            const SizedBox(width: AppDimens.dense / 2),
            Text(label, style: captionStyle),
          ],
        );

    Widget dot({required bool ring}) => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ring ? colors.surface : colors.textPrimary,
            border: Border.all(color: colors.textPrimary, width: 1.5),
          ),
        );

    Widget block(Color color, {double height = 12}) =>
        Container(width: 12, height: height, color: color);

    return Wrap(
      spacing: AppDimens.base,
      runSpacing: AppDimens.dense / 2,
      children: <Widget>[
        if (data.points.any((point) => !point.isExtra))
          item(dot(ring: false), l10n.consistencyChartLoggedLegend),
        if (data.points.any((point) => point.isExtra))
          item(dot(ring: true), l10n.consistencyChartExtraLegend),
        if (data.plannedSegments.isNotEmpty)
          item(
            block(colors.textSecondary, height: 2),
            l10n.consistencyChartPlannedLegend,
          ),
        if (data.untimedRuns.isNotEmpty)
          item(
            block(colors.textSecondary, height: 6),
            l10n.plannedListAnyTime,
          ),
        for (final kind in ConsistencyShadeKind.values)
          if (shadeKinds.contains(kind))
            item(block(_shadeColor(kind, colors)), _shadeLabel(kind, l10n)),
      ],
    );
  }
}
