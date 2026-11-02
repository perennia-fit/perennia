import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../theme/theme.dart';

/// One point of a [ProgressSparkline], placed by its time [x].
final class ProgressSparklinePoint {
  const ProgressSparklinePoint({required this.x, required this.y});

  final DateTime x;
  final double y;
}

/// A small chart of values over time (D8 Charts), drawn with fl_chart's
/// `LineChart`: [points] as dots in [pointColor], the ones at
/// [markedIndexes] as hollow rings instead, and [overlay], when given, as a
/// line in [overlayColor] under them.
///
/// Points sit on the x axis by time, not by index, so uneven gaps between
/// sessions show as gaps. The y range is the drawn values' minimum and
/// maximum with 10% padding, not a zero baseline, so a small change in a
/// large value is visible. It fills its parent's size and has no axes,
/// labels or touch; wrap it in a labelled [Semantics] as the cards do.
class ProgressSparkline extends StatelessWidget {
  const ProgressSparkline({
    super.key,
    required this.points,
    this.overlay = const <ProgressSparklinePoint>[],
    this.markedIndexes = const <int>{},
    required this.pointColor,
    this.overlayColor,
  });

  final List<ProgressSparklinePoint> points;
  final List<ProgressSparklinePoint> overlay;

  /// Indexes into [points] drawn as hollow rings (New Bests).
  final Set<int> markedIndexes;
  final Color pointColor;

  /// The [overlay] line's color; [pointColor] when null.
  final Color? overlayColor;

  /// The share of the y span added above and below the drawn values.
  static const double yPadding = 0.1;

  @override
  Widget build(BuildContext context) {
    final drawn = <ProgressSparklinePoint>[...points, ...overlay];
    if (drawn.isEmpty) {
      return const SizedBox.expand();
    }
    final colors = context.colors;

    double xOf(ProgressSparklinePoint point) =>
        point.x.millisecondsSinceEpoch.toDouble();
    FlSpot spot(ProgressSparklinePoint point) => FlSpot(xOf(point), point.y);

    var minX = drawn.map(xOf).reduce(math.min);
    var maxX = drawn.map(xOf).reduce(math.max);
    if (minX == maxX) {
      // One instant: centre it.
      minX -= 1;
      maxX += 1;
    }
    final minValue = drawn.map((point) => point.y).reduce(math.min);
    final maxValue = drawn.map((point) => point.y).reduce(math.max);
    final span = maxValue - minValue;
    // Equal values have no span; pad by a share of the value itself, or by
    // one when that is zero, so the points sit mid-height.
    final padding = span > 0
        ? span * yPadding
        : (minValue.abs() > 0 ? minValue.abs() * yPadding : 1.0);

    final plain = <FlSpot>[
      for (final (index, point) in points.indexed)
        if (!markedIndexes.contains(index)) spot(point),
    ];
    final rings = <FlSpot>[
      for (final (index, point) in points.indexed)
        if (markedIndexes.contains(index)) spot(point),
    ];

    LineChartBarData dots(
      List<FlSpot> spots, {
      required bool ring,
    }) {
      return LineChartBarData(
        spots: spots,
        color: Colors.transparent,
        barWidth: 0,
        dotData: FlDotData(
          getDotPainter: (_, __, ___, ____) => ring
              ? FlDotCirclePainter(
                  radius: AppDimens.progressSparklinePoint,
                  color: colors.surface,
                  strokeWidth: AppDimens.progressSparklineRing,
                  strokeColor: pointColor,
                )
              : FlDotCirclePainter(
                  radius: AppDimens.progressSparklinePoint,
                  color: pointColor,
                  strokeWidth: 0,
                ),
        ),
      );
    }

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minValue - padding,
        maxY: maxValue + padding,
        backgroundColor: Colors.transparent,
        clipData: const FlClipData.none(),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        titlesData: const FlTitlesData(show: false),
        lineBarsData: <LineChartBarData>[
          if (overlay.isNotEmpty)
            LineChartBarData(
              spots: overlay.map(spot).toList(growable: false),
              color: overlayColor ?? pointColor,
              barWidth: AppDimens.progressSparklineLine,
              isCurved: false,
              dotData: const FlDotData(show: false),
            ),
          if (plain.isNotEmpty) dots(plain, ring: false),
          if (rings.isNotEmpty) dots(rings, ring: true),
        ],
      ),
      duration: Duration.zero,
    );
  }
}
