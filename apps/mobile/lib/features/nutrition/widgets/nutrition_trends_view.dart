import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/analytics/energy_balance.dart';
import '../../../domain/analytics/series_families.dart';
import '../../../domain/nutrition/nutrition.dart';
import '../../../theme/theme.dart';
import '../controllers/nutrition_day_controller.dart';

/// The visible payoff of the nutrition domain: a **read-only** surface that
/// renders derived nutrition totals and trends — energy in, protein, carb, fat
/// — for the anchor `Nutrition Day` and across a trailing window, with progress
/// against the configured `Goal`.
///
/// Everything here is derived analytics computed on demand over `Food Entry`
/// snapshots (NUTRITION.md §1.1, §2); nothing is stored or synced.
/// The surface performs no writes and exposes no recalculate/repair path —
/// caches invalidate mechanically when `Food Entry`s change. Aggregation is
/// unknown-aware: a missing nutrient renders "—", never a misleading "0 g"
/// (NUTRITION.md §4). Goals are configuration, joined at read time, never
/// merged into the analytics store.
class NutritionTrendsView extends ConsumerWidget {
  const NutritionTrendsView({super.key});

  static const String routeName = '/nutrition/trends';

  static const windowToggleKey = Key('nutrition.trends.window');

  static const seriesFamiliesSectionKey =
      Key('nutrition.trends.seriesFamilies');
  static const metricFamilyKey = Key('nutrition.trends.family.metric');
  static const nutritionFamilyKey = Key('nutrition.trends.family.nutrition');

  static const energyBalanceSectionKey = Key('nutrition.trends.energyBalance');
  static const energyBalanceInKey = Key('nutrition.trends.energyBalance.in');
  static const energyBalanceOutKey = Key('nutrition.trends.energyBalance.out');
  static const energyBalanceNetKey = Key('nutrition.trends.energyBalance.net');

  static Key familySeriesKey(SeriesFamily family, String name) {
    return Key('nutrition.trends.series.${family.name}.$name');
  }

  static Key goalProgressKey(NutrientId id) {
    return Key('nutrition.trends.goal-${id.name}');
  }

  static Key goalProgressValueKey(NutrientId id) {
    return Key('nutrition.trends.goalValue-${id.name}');
  }

  static Key trendChartKey(NutrientId id) {
    return Key('nutrition.trends.chart-${id.name}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(nutritionTrendsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nutrition Trends')),
      body: SafeArea(
        child: state.when(
          data: (state) => _NutritionTrendsContent(state: state),
          loading: () => const SizedBox.expand(),
          error: (_, __) => Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Text(
              'Nutrition Trends unavailable',
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NutritionTrendsContent extends ConsumerWidget {
  const _NutritionTrendsContent({required this.state});

  final NutritionTrendsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = ref.watch(nutritionTrendWindowProvider);

    return ListView(
      padding: const EdgeInsets.all(AppDimens.base),
      children: [
        Text(
          'Totals and goal progress are computed from your logged meals — '
          'they are never stored.',
          style: context.textStyles.body.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: AppDimens.base),
        _WindowToggle(
          window: window,
          onChanged: (next) => ref
              .read(nutritionTrendsControllerProvider.notifier)
              .selectWindow(next),
        ),
        const SizedBox(height: AppDimens.base),
        Text("Today's goal progress", style: context.textStyles.h2),
        const SizedBox(height: AppDimens.dense),
        for (final id in goalableNutrientIds) ...[
          _GoalProgressTile(progress: state.anchorProgress(id)),
          const SizedBox(height: AppDimens.dense),
        ],
        const SizedBox(height: AppDimens.dense),
        Text('Trends (${window.label.toLowerCase()})',
            style: context.textStyles.h2),
        const SizedBox(height: AppDimens.dense),
        for (final id in goalableNutrientIds) ...[
          _TrendPanel(trend: state.trendFor(id)),
          const SizedBox(height: AppDimens.dense),
        ],
        const SizedBox(height: AppDimens.dense),
        const _EnergyBalanceSection(),
        const SizedBox(height: AppDimens.dense),
        const _SeriesFamiliesSection(),
        const SizedBox(height: AppDimens.touchTarget),
      ],
    );
  }
}

/// The **headline cross-family read** of the milestone: the anchor day's
/// energy-in vs energy-out balance. Energy-in is the **derived nutrition
/// analytic** (aggregated over `Food Entry`s); energy-out is a measured
/// **`Metric`** (calories burned). The two are read from their own sources and
/// **joined, never merged** — the net is computed on demand and stored nowhere
/// (NUTRITION.md §2, §8).
///
/// It is unknown-aware on both sides: an incomplete in-side or a missing
/// out-side shows an indeterminate "—" net rather than a fabricated number; a
/// "—" is never silently treated as zero in the subtraction (NUTRITION.md §4).
/// Each side is labelled by name + icon (colour is only a secondary cue) so a
/// reader can tell authored-derived intake from a measured Metric.
class _EnergyBalanceSection extends ConsumerWidget {
  const _EnergyBalanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(energyBalanceProvider);

    return balance.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (balance) => _EnergyBalanceCard(balance: balance),
    );
  }
}

class _EnergyBalanceCard extends StatelessWidget {
  const _EnergyBalanceCard({required this.balance});

  final EnergyBalance balance;

  @override
  Widget build(BuildContext context) {
    final unit = nutrientUnitLabel(balance.unit);

    return Column(
      key: NutritionTrendsView.energyBalanceSectionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Energy balance', style: context.textStyles.h2),
        const SizedBox(height: 2),
        Text(
          'Energy in (derived from your meals) and energy out (a measured '
          'Metric) are read separately and netted only for viewing — never '
          'merged or stored.',
          style: context.textStyles.caption.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: AppDimens.dense),
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.surface,
            border: Border.all(color: context.colors.divider),
            borderRadius: AppRadii.cardMd,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EnergySideRow(
                  rowKey: NutritionTrendsView.energyBalanceInKey,
                  family: SeriesFamily.nutritionAnalytic,
                  label: 'Energy in',
                  provenance: 'Derived intake',
                  value: balance.energyInValue,
                  unit: unit,
                ),
                const SizedBox(height: AppDimens.dense),
                _EnergySideRow(
                  rowKey: NutritionTrendsView.energyBalanceOutKey,
                  family: SeriesFamily.metric,
                  label: 'Energy out',
                  provenance: 'Measured Metric',
                  value: balance.energyOutValue,
                  unit: unit,
                ),
                const SizedBox(height: AppDimens.dense),
                Divider(height: 1, color: context.colors.divider),
                const SizedBox(height: AppDimens.dense),
                _NetRow(balance: balance, unit: unit),
                if (balance.isIndeterminate) ...[
                  const SizedBox(height: AppDimens.dense),
                  Text(
                    _indeterminateReason(balance),
                    style: context.textStyles.caption.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One side of the balance: its name + provenance (so the family is conveyed by
/// more than colour), and its known value or a "—" for an unknown side.
class _EnergySideRow extends StatelessWidget {
  const _EnergySideRow({
    required this.rowKey,
    required this.family,
    required this.label,
    required this.provenance,
    required this.value,
    required this.unit,
  });

  final Key rowKey;
  final SeriesFamily family;
  final String label;
  final String provenance;
  final double? value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final accent = _familyColor(context, family);
    final valueText =
        value == null ? '—' : '${formatNutritionNumber(value!)} $unit';

    return Row(
      key: rowKey,
      children: [
        Icon(_familyIcon(family), size: 18, color: accent),
        const SizedBox(width: AppDimens.dense),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: context.textStyles.body),
              Text(
                // Pair the side with its family + provenance words so the
                // authored-vs-measured distinction never rests on colour.
                '${family.label} · $provenance',
                style: context.textStyles.caption.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppDimens.dense),
        Text(
          valueText,
          style: context.textStyles.label.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// The net (energy-in − energy-out) when both sides are known, else an
/// indeterminate "—" paired with a status word so colour is never the sole
/// signal.
class _NetRow extends StatelessWidget {
  const _NetRow({required this.balance, required this.unit});

  final EnergyBalance balance;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final net = balance.net;
    final netText = net == null
        ? '—'
        : '${net > 0 ? '+' : ''}${formatNutritionNumber(net)} $unit';
    final statusColor = _netColor(context, balance);

    return Row(
      children: [
        Expanded(
          child: Text(
            'Net (in − out)',
            style: context.textStyles.body,
          ),
        ),
        const SizedBox(width: AppDimens.dense),
        _StatusChip(label: _netLabel(balance), color: statusColor),
        const SizedBox(width: AppDimens.dense),
        Text(
          netText,
          key: NutritionTrendsView.energyBalanceNetKey,
          style: context.textStyles.label.copyWith(color: statusColor),
        ),
      ],
    );
  }
}

/// The **two series families** shown together on one screen: stored `Metric`
/// signals and derived nutrition analytics. They are presented side by side but
/// **never merged** into a common series store (NUTRITION.md §2) — each family
/// keeps its own provenance, read from its own source, and is labelled so a
/// reader can tell a measured body signal from a derived intake analytic
/// (the family is conveyed by an icon + text, never colour alone).
class _SeriesFamiliesSection extends ConsumerWidget {
  const _SeriesFamiliesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final families = ref.watch(seriesFamiliesProvider);

    return families.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (families) {
        return Column(
          key: NutritionTrendsView.seriesFamiliesSectionKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Series families', style: context.textStyles.h2),
            const SizedBox(height: 2),
            Text(
              'Measured Metrics and derived nutrition analytics are shown '
              'together but kept separate — joined for viewing, never merged.',
              style: context.textStyles.caption.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppDimens.dense),
            _FamilyGroup(
              key: NutritionTrendsView.metricFamilyKey,
              family: SeriesFamily.metric,
              series: families.metricSeries,
              emptyLabel: 'No measured Metrics yet',
            ),
            const SizedBox(height: AppDimens.dense),
            _FamilyGroup(
              key: NutritionTrendsView.nutritionFamilyKey,
              family: SeriesFamily.nutritionAnalytic,
              series: families.nutritionSeries,
              emptyLabel: 'No logged nutrition yet',
            ),
          ],
        );
      },
    );
  }
}

/// One labelled family and the series that belong to it. The family header
/// pairs an icon with its name and provenance text so the distinction never
/// rests on colour alone.
class _FamilyGroup extends StatelessWidget {
  const _FamilyGroup({
    required this.family,
    required this.series,
    required this.emptyLabel,
    super.key,
  });

  final SeriesFamily family;
  final List<TrendSeries> series;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: context.colors.divider),
        borderRadius: AppRadii.cardMd,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FamilyHeader(family: family),
            const SizedBox(height: AppDimens.dense),
            if (series.isEmpty)
              Text(
                emptyLabel,
                style: context.textStyles.caption.copyWith(
                  color: context.colors.textSecondary,
                ),
              )
            else
              for (final entry in series) ...[
                _FamilySeriesRow(family: family, series: entry),
                if (entry != series.last)
                  const SizedBox(height: AppDimens.dense),
              ],
          ],
        ),
      ),
    );
  }
}

class _FamilyHeader extends StatelessWidget {
  const _FamilyHeader({required this.family});

  final SeriesFamily family;

  @override
  Widget build(BuildContext context) {
    final accent = _familyColor(context, family);
    return Row(
      children: [
        Icon(_familyIcon(family), size: 18, color: accent),
        const SizedBox(width: AppDimens.dense),
        Text(family.label, style: context.textStyles.body),
        const SizedBox(width: AppDimens.dense),
        Expanded(
          child: Text(
            family.provenanceLabel,
            style: context.textStyles.caption.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// One series within a family: its name, latest value (or "—" for an unknown
/// gap), and a small sparkline. Unknown gaps are never plotted as zero and are
/// never blended into a neighbouring point.
class _FamilySeriesRow extends StatelessWidget {
  const _FamilySeriesRow({
    required this.family,
    required this.series,
  });

  final SeriesFamily family;
  final TrendSeries series;

  @override
  Widget build(BuildContext context) {
    final accent = _familyColor(context, family);
    final latest = series.comparablePoints.isEmpty
        ? null
        : series.comparablePoints.last;
    final latestText = latest == null
        ? '—'
        : '${formatNutritionNumber(latest.value!)} ${series.unitLabel}';

    return Padding(
      key: NutritionTrendsView.familySeriesKey(family, series.name),
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(series.name, style: context.textStyles.body),
                Text(
                  // The family label travels with each series so it stays
                  // legible even out of its group's context.
                  family.label,
                  style: context.textStyles.caption.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppDimens.dense),
          SizedBox(
            width: 88,
            height: 28,
            child: series.hasComparablePoints
                ? CustomPaint(
                    painter: _SparklinePainter(
                      series: series,
                      lineColor: accent,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: AppDimens.dense),
          Text(
            latestText,
            style: context.textStyles.label.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.series,
    required this.lineColor,
  });

  final TrendSeries series;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final data = series.data;
    if (data.isEmpty) {
      return;
    }

    final values = <double>[
      for (final datum in data)
        if (datum.value != null) datum.value!,
    ];
    if (values.isEmpty) {
      return;
    }
    final maxValue = values.reduce(math.max);
    final minValue = math.min(0, values.reduce(math.min));
    final range = maxValue == minValue ? 1 : maxValue - minValue;

    double yFor(double value) {
      final normalized = (value - minValue) / range;
      return size.height - normalized * size.height;
    }

    double xFor(int index) {
      if (data.length == 1) {
        return size.width / 2;
      }
      return size.width * index / (data.length - 1);
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    Path? path;
    for (var index = 0; index < data.length; index += 1) {
      final value = data[index].value;
      if (value == null) {
        // Break the line across an unknown gap — never bridge a fake 0.
        path = null;
        continue;
      }
      final offset = Offset(xFor(index), yFor(value));
      canvas.drawCircle(offset, 2, dotPaint);
      if (path == null) {
        path = Path()..moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
        canvas.drawPath(path, linePaint);
        path = Path()..moveTo(offset.dx, offset.dy);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.series != series || oldDelegate.lineColor != lineColor;
  }
}

IconData _familyIcon(SeriesFamily family) {
  return switch (family) {
    SeriesFamily.metric => Icons.monitor_heart_outlined,
    SeriesFamily.nutritionAnalytic => Icons.restaurant_outlined,
  };
}

Color _familyColor(BuildContext context, SeriesFamily family) {
  // Colour is a secondary cue only — every family is also named in text.
  return switch (family) {
    SeriesFamily.metric => context.colors.record,
    SeriesFamily.nutritionAnalytic => context.colors.save,
  };
}

class _WindowToggle extends StatelessWidget {
  const _WindowToggle({
    required this.window,
    required this.onChanged,
  });

  final NutritionTrendWindow window;
  final ValueChanged<NutritionTrendWindow> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<NutritionTrendWindow>(
      key: NutritionTrendsView.windowToggleKey,
      segments: <ButtonSegment<NutritionTrendWindow>>[
        for (final value in NutritionTrendWindow.values)
          ButtonSegment<NutritionTrendWindow>(
            value: value,
            label: Text(value.label),
          ),
      ],
      selected: <NutritionTrendWindow>{window},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

/// One goalable nutrient's anchor-day progress: a ring fill paired with the
/// derived total / configured target as plain text, and a labelled status word
/// so colour is never the sole signal (DESIGN.md / WCAG AA).
class _GoalProgressTile extends StatelessWidget {
  const _GoalProgressTile({required this.progress});

  final NutrientGoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(context, progress.status);
    final id = progress.nutrient;

    return DecoratedBox(
      key: NutritionTrendsView.goalProgressKey(id),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: context.colors.divider),
        borderRadius: AppRadii.cardMd,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.base),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CustomPaint(
                painter: _ProgressRingPainter(
                  fraction: progress.fillFraction,
                  trackColor: context.colors.divider,
                  fillColor: statusColor,
                ),
                child: Center(
                  child: Text(
                    _ringLabel(progress),
                    style: context.textStyles.label.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppDimens.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nutrientDisplayLabel(id),
                    style: context.textStyles.body,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _progressValueText(progress),
                    key: NutritionTrendsView.goalProgressValueKey(id),
                    style: context.textStyles.label.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppDimens.dense),
            _StatusChip(
              label: _statusLabel(progress),
              color: statusColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.dense,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: AppRadii.chipFull,
      ),
      child: Text(
        label,
        style: context.textStyles.label.copyWith(color: color),
      ),
    );
  }
}

/// A trend panel for one nutrient: the per-day derived totals across the window
/// drawn as a line, with the configured target as a dashed reference. Unknown
/// days are held out of the line so it never dips to a false zero.
class _TrendPanel extends StatelessWidget {
  const _TrendPanel({required this.trend});

  final NutritionTrend trend;

  @override
  Widget build(BuildContext context) {
    final target = trend.target;
    final unit = nutrientUnitLabel(trend.nutrient.defaultUnit);
    final hasPoints = trend.hasCompletePoints;
    final unknownDays = trend.points.where((point) => point.isUnknown).length;

    return Semantics(
      container: true,
      label: '${nutrientDisplayLabel(trend.nutrient)} trend',
      child: DecoratedBox(
        key: NutritionTrendsView.trendChartKey(trend.nutrient),
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border.all(color: context.colors.divider),
          borderRadius: AppRadii.cardMd,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nutrientDisplayLabel(trend.nutrient),
                style: context.textStyles.body,
              ),
              const SizedBox(height: AppDimens.dense),
              SizedBox(
                height: 120,
                width: double.infinity,
                child: hasPoints
                    ? CustomPaint(
                        painter: _TrendPainter(
                          points: trend.points,
                          target: target?.value,
                          lineColor: context.colors.save,
                          targetColor: context.colors.record,
                          gridColor: context.colors.divider,
                        ),
                      )
                    : Center(
                        child: Text(
                          'No logged totals yet',
                          style: context.textStyles.caption.copyWith(
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: AppDimens.dense),
              if (target != null)
                Text(
                  'Goal: ${formatNutritionNumber(target.value)} $unit',
                  style: context.textStyles.caption.copyWith(
                    color: context.colors.record,
                  ),
                )
              else
                Text(
                  'No goal set',
                  style: context.textStyles.caption.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              if (unknownDays > 0)
                Text(
                  '$unknownDays ${unknownDays == 1 ? 'day' : 'days'} '
                  'with an unreported value (shown as —, not plotted)',
                  style: context.textStyles.caption.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({
    required this.fraction,
    required this.trackColor,
    required this.fillColor,
  });

  /// The clamped `[0, 1]` fill, or `null` when there is no comparable progress
  /// (no goal, or an unknown total).
  final double? fraction;
  final Color trackColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 3;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, trackPaint);

    final value = fraction;
    if (value == null || value <= 0) {
      return;
    }

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * value,
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) {
    return oldDelegate.fraction != fraction ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.fillColor != fillColor;
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.points,
    required this.target,
    required this.lineColor,
    required this.targetColor,
    required this.gridColor,
  });

  final List<NutritionTrendPoint> points;
  final double? target;
  final Color lineColor;
  final Color targetColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      gridPaint,
    );

    // Only complete days are plottable — unknown days never read as zero.
    final plottable = <double?>[
      for (final point in points) point.plottableValue,
    ];
    final values = plottable.whereType<double>().toList(growable: false);
    if (values.isEmpty) {
      return;
    }

    final candidates = <double>[
      ...values,
      0,
      if (target != null) target!,
    ];
    final maxValue = candidates.reduce(math.max);
    final minValue = math.min(0, candidates.reduce(math.min));
    final range = maxValue == minValue ? 1 : maxValue - minValue;

    double yFor(double value) {
      final normalized = (value - minValue) / range;
      final y = size.height - normalized * (size.height - AppDimens.base);
      return y.clamp(0, size.height).toDouble();
    }

    double xFor(int index) {
      if (points.length == 1) {
        return size.width / 2;
      }
      return size.width * index / (points.length - 1);
    }

    if (target != null) {
      final targetPaint = Paint()
        ..color = targetColor
        ..strokeWidth = 1.5;
      _drawDashedLine(
        canvas,
        Offset(0, yFor(target!)),
        Offset(size.width, yFor(target!)),
        targetPaint,
      );
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    Path? path;
    for (var index = 0; index < plottable.length; index += 1) {
      final value = plottable[index];
      if (value == null) {
        // Break the line across an unknown gap rather than bridging a fake 0.
        path = null;
        continue;
      }
      final offset = Offset(xFor(index), yFor(value));
      canvas.drawCircle(offset, 3, dotPaint);
      if (path == null) {
        path = Path()..moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
        canvas.drawPath(path, linePaint);
        path = Path()..moveTo(offset.dx, offset.dy);
      }
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashWidth = 5.0;
    const dashGap = 4.0;
    final totalLength = (end - start).distance;
    final direction = (end - start) / totalLength;
    var drawn = 0.0;
    while (drawn < totalLength) {
      final segmentEnd = math.min(drawn + dashWidth, totalLength);
      canvas.drawLine(
        start + direction * drawn,
        start + direction * segmentEnd,
        paint,
      );
      drawn += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.target != target ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.targetColor != targetColor ||
        oldDelegate.gridColor != gridColor;
  }
}

Color _netColor(BuildContext context, EnergyBalance balance) {
  if (balance.isIndeterminate) {
    return Theme.of(context).colorScheme.error;
  }
  // A deficit (more burned than eaten) and a surplus are both neutral facts —
  // colour is a secondary cue paired with the status word, never a judgement.
  if (balance.isSurplus) {
    return context.colors.record;
  }
  if (balance.isDeficit) {
    return context.colors.save;
  }
  return context.colors.textSecondary;
}

String _netLabel(EnergyBalance balance) {
  if (balance.isIndeterminate) {
    return 'Indeterminate';
  }
  if (balance.isSurplus) {
    return 'Surplus';
  }
  if (balance.isDeficit) {
    return 'Deficit';
  }
  return 'Balanced';
}

String _indeterminateReason(EnergyBalance balance) {
  if (!balance.energyInKnown && !balance.energyOutKnown) {
    return 'Net is indeterminate — energy in is incomplete and no calories-'
        'burned Metric was recorded. A missing value is never treated as 0.';
  }
  if (!balance.energyInKnown) {
    return 'Net is indeterminate — a logged item is missing its energy value, '
        'so energy in is incomplete. A missing value is never treated as 0.';
  }
  return 'Net is indeterminate — no calories-burned Metric was recorded for '
      'this day. A missing value is never treated as 0.';
}

Color _statusColor(BuildContext context, NutrientGoalStatus status) {
  return switch (status) {
    NutrientGoalStatus.met ||
    NutrientGoalStatus.below =>
      context.colors.save,
    NutrientGoalStatus.over => context.colors.record,
    NutrientGoalStatus.unknown => Theme.of(context).colorScheme.error,
    NutrientGoalStatus.noGoal => context.colors.textSecondary,
  };
}

String _statusLabel(NutrientGoalProgress progress) {
  return switch (progress.status) {
    NutrientGoalStatus.met => 'On target',
    NutrientGoalStatus.below => 'Under',
    NutrientGoalStatus.over => 'Over',
    NutrientGoalStatus.unknown => 'Unknown',
    NutrientGoalStatus.noGoal => 'No goal',
  };
}

String _ringLabel(NutrientGoalProgress progress) {
  final ratio = progress.ratio;
  if (ratio == null) {
    return progress.isUnknown ? '—' : '·';
  }
  return '${(ratio * 100).round()}%';
}

String _progressValueText(NutrientGoalProgress progress) {
  final unit = nutrientUnitLabel(progress.total.unit);
  final totalText = progress.isUnknown
      ? '—'
      : '${formatNutritionNumber(progress.total.value)} $unit';
  final target = progress.target;
  if (target == null) {
    return '$totalText logged · no goal';
  }
  final targetText = '${formatNutritionNumber(target.value)} $unit';
  return '$totalText of $targetText';
}
