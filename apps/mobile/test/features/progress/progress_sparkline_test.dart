import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/features/progress/widgets/progress_sparkline.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  final start = DateTime(2026, 10, 1, 7);
  ProgressSparklinePoint point(int day, double y) =>
      ProgressSparklinePoint(x: start.add(Duration(days: day)), y: y);

  Future<LineChartData> pump(
    WidgetTester tester,
    List<ProgressSparklinePoint> points, {
    Set<int> markedIndexes = const <int>{},
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: AppDimens.progressSparklineHeight,
            child: ProgressSparkline(
              points: points,
              markedIndexes: markedIndexes,
              pointColor: AppColors.light.textPrimary,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    return tester.widget<LineChart>(find.byType(LineChart)).data;
  }

  testWidgets('the y range pads the drawn values by 10%, not from zero', (
    tester,
  ) async {
    final data = await pump(tester, <ProgressSparklinePoint>[
      point(0, 100),
      point(3, 110),
      point(6, 105),
    ]);

    expect(data.minY, closeTo(99, 1e-9));
    expect(data.maxY, closeTo(111, 1e-9));
  });

  testWidgets('equal values sit mid-height', (tester) async {
    final data = await pump(tester, <ProgressSparklinePoint>[
      point(0, 50),
      point(2, 50),
    ]);

    expect(data.minY, lessThan(50));
    expect(data.maxY, greaterThan(50));
    expect(data.maxY - 50, closeTo(50 - data.minY, 1e-9));
  });

  testWidgets('uneven times are placed by time, not by index', (tester) async {
    final points = <ProgressSparklinePoint>[
      point(0, 1),
      point(1, 2),
      point(10, 3),
    ];
    final data = await pump(tester, points);

    final xs = <double>[
      for (final bar in data.lineBarsData)
        for (final spot in bar.spots) spot.x,
    ]..sort();
    expect(xs, <double>[
      for (final point in points) point.x.millisecondsSinceEpoch.toDouble(),
    ]);
    expect((xs[2] - xs[1]) / (xs[1] - xs[0]), closeTo(9, 1e-9));
    expect(data.minX, xs.first);
    expect(data.maxX, xs.last);
  });

  testWidgets('marked points render as hollow rings', (tester) async {
    final points = <ProgressSparklinePoint>[
      point(0, 10),
      point(2, 12),
      point(4, 11),
    ];
    final data = await pump(tester, points, markedIndexes: const <int>{1});

    FlDotCirclePainter painterOf(LineChartBarData bar) =>
        bar.dotData.getDotPainter(bar.spots.first, 0, bar, 0)
            as FlDotCirclePainter;

    final rings = data.lineBarsData
        .where((bar) => painterOf(bar).strokeWidth > 0)
        .toList();
    expect(rings, hasLength(1));
    expect(rings.single.spots.map((spot) => spot.y), <double>[12]);
    final ring = painterOf(rings.single);
    expect(ring.color, AppColors.light.surface);
    expect(ring.strokeColor, AppColors.light.textPrimary);

    final dots = data.lineBarsData
        .where((bar) => painterOf(bar).strokeWidth == 0)
        .single;
    expect(dots.spots.map((spot) => spot.y), <double>[10, 11]);
    expect(painterOf(dots).color, AppColors.light.textPrimary);
  });
}
