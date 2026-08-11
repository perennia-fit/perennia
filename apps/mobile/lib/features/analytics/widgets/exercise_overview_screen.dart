import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/analytics/exercise_analytics.dart';
import '../../../domain/training/training_dimensions.dart';
import '../../../theme/theme.dart';
import '../models/exercise_progress_graphs.dart';
import '../repositories/exercise_analytics_repository.dart';
import '../repositories/exercise_overview_repository.dart';

class ExerciseOverviewScreen extends ConsumerWidget {
  const ExerciseOverviewScreen({
    super.key,
    required this.exerciseId,
  });

  final String exerciseId;

  static const historyTabKey = Key('exerciseOverview.historyTab');
  static const recordsTabKey = Key('exerciseOverview.recordsTab');
  static const historyListKey = Key('exerciseOverview.historyList');
  static const weeklySummaryKey = Key('exerciseOverview.weeklySummary');
  static const recordsTableKey = Key('exerciseOverview.recordsTable');

  static Key prBadgeKey(String setId) {
    return Key('exerciseOverview.set.$setId.pr');
  }

  static Key graphKey(String graphId) {
    return Key('exerciseOverview.graph.$graphId');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(exerciseOverviewControllerProvider(exerciseId));
    final analytics =
        ref.watch(exerciseAnalyticsControllerProvider(exerciseId));

    return overview.when(
      data: (model) {
        if (model == null) {
          return const Scaffold(
            appBar: _OverviewAppBar(title: 'Exercise Overview'),
            body: Center(child: Text('Exercise unavailable')),
          );
        }

        final analyticsResult = analytics.maybeWhen(
          data: (result) => result,
          orElse: () => null,
        );
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: _OverviewAppBar(
              title: model.exercise.name,
              bottom: const TabBar(
                tabs: [
                  Tab(key: historyTabKey, text: 'History'),
                  Tab(key: recordsTabKey, text: 'Records'),
                ],
              ),
            ),
            body: SafeArea(
              child: TabBarView(
                children: [
                  _HistoryTab(
                    model: model,
                    analytics: analyticsResult,
                  ),
                  _RecordsTab(
                    model: model,
                    analytics: analyticsResult,
                    isLoading: analytics.isLoading,
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const Scaffold(
        appBar: _OverviewAppBar(title: 'Exercise Overview'),
        body: SizedBox.expand(),
      ),
      error: (error, stackTrace) => const Scaffold(
        appBar: _OverviewAppBar(title: 'Exercise Overview'),
        body: Center(child: Text('Exercise overview unavailable')),
      ),
    );
  }
}

class _OverviewAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _OverviewAppBar({
    required this.title,
    this.bottom,
  });

  final String title;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize {
    final bottomHeight = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight(kToolbarHeight + bottomHeight);
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      bottom: bottom,
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({
    required this.model,
    required this.analytics,
  });

  final ExerciseOverviewModel model;
  final ExerciseAnalyticsResult? analytics;

  @override
  Widget build(BuildContext context) {
    final prBySetId = <String, AnalyticsRecord>{
      for (final record in analytics?.recordCatalog.repMaxRecords ??
          const <AnalyticsRecord>[])
        record.setId: record,
    };

    return ListView(
      key: ExerciseOverviewScreen.historyListKey,
      padding: const EdgeInsets.all(AppDimens.base),
      children: [
        _ExerciseMeta(category: model.category),
        const SizedBox(height: AppDimens.base),
        _WeeklySummarySection(groups: model.weeklyGroups),
        if (model.weeklyGroups.isNotEmpty)
          const SizedBox(height: AppDimens.base),
        if (model.groups.isEmpty)
          Text(
            'No history yet',
            style: context.textStyles.body.copyWith(
              color: context.colors.textSecondary,
            ),
          )
        else
          for (final group in model.groups) ...[
            _WorkoutHistoryGroup(
              exercise: model.exercise,
              group: group,
              prBySetId: prBySetId,
            ),
            const Divider(height: AppDimens.base * 2),
          ],
      ],
    );
  }
}

class _WeeklySummarySection extends StatelessWidget {
  const _WeeklySummarySection({required this.groups});

  final List<ExerciseOverviewWeekGroup> groups;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }

    return Semantics(
      key: ExerciseOverviewScreen.weeklySummaryKey,
      container: true,
      label: 'Weekly history summary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Weekly summary', style: context.textStyles.h2),
          const SizedBox(height: AppDimens.dense),
          for (final group in groups) ...[
            Text(
              'Week of ${group.weekStart.storageValue}',
              style: context.textStyles.body,
            ),
            const SizedBox(height: AppDimens.dense),
            Wrap(
              spacing: AppDimens.dense,
              runSpacing: AppDimens.dense,
              children: [
                _MetricPill(label: _setCountLabel(group.setCount)),
                for (final label in _weeklyMetricLabels(
                  volume: group.volume,
                  totalReps: group.totalReps,
                  distance: group.distance,
                  duration: group.duration,
                ))
                  _MetricPill(label: label),
              ],
            ),
            const SizedBox(height: AppDimens.dense),
          ],
        ],
      ),
    );
  }
}

class _ExerciseMeta extends StatelessWidget {
  const _ExerciseMeta({required this.category});

  final ExerciseCategoryRecord? category;

  @override
  Widget build(BuildContext context) {
    final categoryText = category?.name ?? 'Uncategorized';
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Exercise overview metadata, $categoryText',
      child: Row(
        children: [
          Container(
            width: AppDimens.base,
            height: AppDimens.base,
            decoration: BoxDecoration(
              color: _categoryColor(context, category),
              borderRadius: AppRadii.chipFull,
            ),
          ),
          const SizedBox(width: AppDimens.dense),
          Text(categoryText, style: context.textStyles.caption),
        ],
      ),
    );
  }
}

class _WorkoutHistoryGroup extends StatelessWidget {
  const _WorkoutHistoryGroup({
    required this.exercise,
    required this.group,
    required this.prBySetId,
  });

  final ExerciseRecord exercise;
  final ExerciseOverviewWorkoutGroup group;
  final Map<String, AnalyticsRecord> prBySetId;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Workout history from ${_formatDate(group.workout.startedAt)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatDate(group.workout.startedAt),
            style: context.textStyles.h2,
          ),
          const SizedBox(height: AppDimens.dense),
          Wrap(
            spacing: AppDimens.dense,
            runSpacing: AppDimens.dense,
            children: _aggregateLabels(group)
                .map((label) => _MetricPill(label: label))
                .toList(growable: false),
          ),
          const SizedBox(height: AppDimens.dense),
          for (final set in group.sets)
            _HistorySetRow(
              exercise: exercise,
              set: set,
              pr: prBySetId[set.id],
            ),
        ],
      ),
    );
  }
}

class _HistorySetRow extends StatelessWidget {
  const _HistorySetRow({
    required this.exercise,
    required this.set,
    required this.pr,
  });

  final ExerciseRecord exercise;
  final LoggedSetRecord set;
  final AnalyticsRecord? pr;

  @override
  Widget build(BuildContext context) {
    final pr = this.pr;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.dense),
      child: Semantics(
        label: pr == null
            ? 'Logged set ${_formatSet(set, exercise)}'
            : 'Personal record set ${_formatSet(set, exercise)}',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_formatSet(set, exercise),
                      style: context.textStyles.body),
                  if (set.comment != null && set.comment!.isNotEmpty)
                    Text(
                      set.comment!,
                      style: context.textStyles.caption.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (pr != null)
              _PrBadge(
                key: ExerciseOverviewScreen.prBadgeKey(set.id),
                label: '${pr.reps} rep PR',
              ),
          ],
        ),
      ),
    );
  }
}

class _PrBadge extends StatelessWidget {
  const _PrBadge({
    super.key,
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Personal record, $label',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.emoji_events_outlined,
            color: context.colors.record,
            size: 20,
          ),
          const SizedBox(width: AppDimens.dense),
          Text(label, style: context.textStyles.caption),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: context.colors.divider),
          borderRadius: AppRadii.chipFull,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.base,
            vertical: AppDimens.dense,
          ),
          child: Text(label, style: context.textStyles.caption),
        ),
      ),
    );
  }
}

class _RecordsTab extends StatelessWidget {
  const _RecordsTab({
    required this.model,
    required this.analytics,
    required this.isLoading,
  });

  final ExerciseOverviewModel model;
  final ExerciseAnalyticsResult? analytics;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final analytics = this.analytics;
    if (analytics == null) {
      return isLoading
          ? const SizedBox.expand()
          : const Center(child: Text('Records unavailable'));
    }

    return ListView(
      key: ExerciseOverviewScreen.recordsTableKey,
      padding: const EdgeInsets.all(AppDimens.base),
      children: [
        _ProgressGraphsSection(
          graphs: ExerciseProgressGraphs.fromAnalytics(analytics),
        ),
        const SizedBox(height: AppDimens.base),
        Text('Actual rep maxes', style: context.textStyles.h2),
        const SizedBox(height: AppDimens.dense),
        _ActualRecordsTable(records: analytics.recordCatalog.repMaxRecords),
        const SizedBox(height: AppDimens.base),
        Text('Estimated rep maxes', style: context.textStyles.h2),
        const SizedBox(height: AppDimens.dense),
        if (!analytics.estimatedOneRepMax.isDefined)
          Text(
            'Estimated rep maxes undefined',
            style: context.textStyles.body.copyWith(
              color: context.colors.textSecondary,
            ),
          )
        else
          _EstimatedRecordsTable(
            points: analytics.estimatedOneRepMax.points,
            setsById: model.setsById,
          ),
      ],
    );
  }
}

class _ProgressGraphsSection extends StatelessWidget {
  const _ProgressGraphsSection({required this.graphs});

  final ExerciseProgressGraphs graphs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Progress graphs', style: context.textStyles.h2),
        const SizedBox(height: AppDimens.dense),
        for (final series in graphs.series) ...[
          _GraphPanel(series: series),
          const SizedBox(height: AppDimens.dense),
        ],
      ],
    );
  }
}

class _GraphPanel extends StatefulWidget {
  const _GraphPanel({required this.series});

  final ExerciseGraphSeries series;

  @override
  State<_GraphPanel> createState() => _GraphPanelState();
}

class _GraphPanelState extends State<_GraphPanel> {
  ExerciseGraphPoint? _selectedPoint;

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final selectedPoint = _selectedPoint;
    final hasPoints = series.renderPoints.isNotEmpty;

    return Semantics(
      container: true,
      label: 'Progress graph, ${series.kind.title}, '
          '${series.rawPoints.length} raw points',
      button: hasPoints,
      hint: hasPoints ? 'Tap to inspect a raw graph value' : null,
      child: GestureDetector(
        key: ExerciseOverviewScreen.graphKey(series.kind.id),
        behavior: HitTestBehavior.opaque,
        onTapDown: hasPoints ? _selectNearestPoint : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: context.colors.divider),
            borderRadius: AppRadii.cardMd,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(series.kind.title, style: context.textStyles.body),
                const SizedBox(height: AppDimens.dense),
                SizedBox(
                  height: 128,
                  width: double.infinity,
                  child: hasPoints
                      ? CustomPaint(
                          painter: _GraphPainter(
                            points: series.renderPoints,
                            lineColor: _graphColor(context, series.kind),
                            gridColor: context.colors.divider,
                          ),
                        )
                      : Center(
                          child: Text(
                            series.kind.emptyLabel,
                            style: context.textStyles.caption.copyWith(
                              color: context.colors.textSecondary,
                            ),
                          ),
                        ),
                ),
                if (series.isDownsampled)
                  Text(
                    'Rendering ${series.renderPoints.length} of '
                    '${series.rawPoints.length} raw points',
                    style: context.textStyles.caption.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                if (selectedPoint != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'Selected ${series.kind.title}: '
                      '${_formatValue(selectedPoint.value, selectedPoint.unit)} '
                      'on ${_formatDate(selectedPoint.achievedAt)}',
                      style: context.textStyles.caption,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _selectNearestPoint(TapDownDetails details) {
    final series = widget.series;
    if (series.renderPoints.isEmpty) {
      return;
    }

    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 1;
    final scaledIndex =
        (details.localPosition.dx / width) * (series.renderPoints.length - 1);
    final renderIndex = scaledIndex.round().clamp(
          0,
          series.renderPoints.length - 1,
        );
    setState(() {
      _selectedPoint = series.inspectRawPoint(renderIndex);
    });
  }
}

class _GraphPainter extends CustomPainter {
  const _GraphPainter({
    required this.points,
    required this.lineColor,
    required this.gridColor,
  });

  final List<ExerciseGraphPoint> points;
  final Color lineColor;
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

    if (points.isEmpty) {
      return;
    }

    final values = points.map((point) => point.value);
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = maxValue == minValue ? 1 : maxValue - minValue;
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    Offset pointOffset(int index) {
      final point = points[index];
      final x = points.length == 1
          ? size.width / 2
          : size.width * index / (points.length - 1);
      final normalized = (point.value - minValue) / range;
      final y = size.height - (normalized * (size.height - AppDimens.base));
      return Offset(x, y.clamp(0, size.height).toDouble());
    }

    if (points.length == 1) {
      canvas.drawCircle(pointOffset(0), 4, dotPaint);
      return;
    }

    final path = Path()..moveTo(pointOffset(0).dx, pointOffset(0).dy);
    for (var index = 1; index < points.length; index += 1) {
      final offset = pointOffset(index);
      path.lineTo(offset.dx, offset.dy);
    }
    canvas.drawPath(path, linePaint);

    canvas.drawCircle(pointOffset(0), 3, dotPaint);
    canvas.drawCircle(pointOffset(points.length - 1), 3, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor;
  }
}

class _ActualRecordsTable extends StatelessWidget {
  const _ActualRecordsTable({required this.records});

  final List<AnalyticsRecord> records;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Text(
        'No actual rep maxes yet',
        style: context.textStyles.body.copyWith(
          color: context.colors.textSecondary,
        ),
      );
    }

    return DataTable(
      columns: const [
        DataColumn(label: Text('Reps')),
        DataColumn(label: Text('Load')),
      ],
      rows: [
        for (final record in records)
          DataRow(
            cells: [
              DataCell(Text('${record.reps} reps')),
              DataCell(Text(_formatValue(record.value, record.unit))),
            ],
          ),
      ],
    );
  }
}

class _EstimatedRecordsTable extends StatelessWidget {
  const _EstimatedRecordsTable({
    required this.points,
    required this.setsById,
  });

  final List<AnalyticsPoint> points;
  final Map<String, LoggedSetRecord> setsById;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Text(
        'No estimated rep maxes yet',
        style: context.textStyles.body.copyWith(
          color: context.colors.textSecondary,
        ),
      );
    }

    return DataTable(
      columns: const [
        DataColumn(label: Text('Reps')),
        DataColumn(label: Text('e1RM')),
      ],
      rows: [
        for (final point in points)
          DataRow(
            cells: [
              DataCell(Text(_repLabel(setsById[point.setId]))),
              DataCell(Text(_formatValue(point.value, point.unit))),
            ],
          ),
      ],
    );
  }
}

List<String> _aggregateLabels(ExerciseOverviewWorkoutGroup group) {
  return _metricLabels(
    volume: group.volume,
    totalReps: group.totalReps,
    distance: group.distance,
    duration: group.duration,
  );
}

List<String> _metricLabels({
  required double? volume,
  required double? totalReps,
  required double? distance,
  required Duration? duration,
}) {
  final labels = <String>[];
  if (volume != null) {
    labels.add('Volume ${_formatNumber(volume)} kg');
  }
  if (totalReps != null) {
    labels.add('Reps ${_formatNumber(totalReps)}');
  }
  if (distance != null) {
    labels.add('Distance ${_formatNumber(distance)} km');
  }
  if (duration != null) {
    labels.add('Duration ${_formatDuration(duration)}');
  }
  return labels;
}

List<String> _weeklyMetricLabels({
  required double? volume,
  required double? totalReps,
  required double? distance,
  required Duration? duration,
}) {
  final labels = <String>[];
  if (volume != null) {
    labels.add('Weekly volume ${_formatNumber(volume)} kg');
  }
  if (totalReps != null) {
    labels.add('Weekly reps ${_formatNumber(totalReps)}');
  }
  if (distance != null) {
    labels.add('Weekly distance ${_formatNumber(distance)} km');
  }
  if (duration != null) {
    labels.add('Weekly duration ${_formatDuration(duration)}');
  }
  return labels;
}

String _setCountLabel(int count) {
  return count == 1 ? '1 set' : '$count sets';
}

String _formatSet(LoggedSetRecord set, ExerciseRecord exercise) {
  final load = set.values.load;
  final reps = set.values.reps;
  if (load != null && reps != null) {
    return '${load.entered} ${_unitShortLabel(load.unit)} x ${reps.entered}';
  }

  final segments = <String>[];
  for (final dimension in exercise.type.dimensions) {
    final value = set.values.valueFor(dimension);
    if (value != null) {
      segments.add('${value.entered} ${_unitShortLabel(value.unit)}');
    }
  }
  return segments.isEmpty ? 'Completed set' : segments.join(' - ');
}

String _repLabel(LoggedSetRecord? set) {
  final reps = set?.values.reps?.convertedTo(TrainingUnit.repetition);
  return reps == null ? 'Set' : '${_formatNumber(reps)} reps';
}

String _formatValue(double value, TrainingUnit unit) {
  return '${_formatNumber(value)} ${_unitShortLabel(unit)}';
}

String _formatNumber(num value) {
  if (value.roundToDouble() == value) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}

String _formatDate(DateTime value) {
  final utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _unitShortLabel(TrainingUnit unit) {
  return switch (unit) {
    TrainingUnit.kilogram => 'kg',
    TrainingUnit.pound => 'lb',
    TrainingUnit.repetition => 'reps',
    TrainingUnit.second => 'sec',
    TrainingUnit.kilometer => 'km',
    TrainingUnit.mile => 'mi',
  };
}

Color _categoryColor(
  BuildContext context,
  ExerciseCategoryRecord? category,
) {
  final colorHex = category?.colorHex;
  if (colorHex == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(colorHex)) {
    return context.colors.categoryColor('other');
  }

  return Color(int.parse(colorHex.substring(1), radix: 16) | 0xFF000000);
}

Color _graphColor(BuildContext context, ExerciseGraphKind kind) {
  return switch (kind) {
    ExerciseGraphKind.headlineRecordTrend => context.colors.record,
    ExerciseGraphKind.volume => context.colors.save,
    ExerciseGraphKind.estimatedOneRepMax =>
      Theme.of(context).colorScheme.primary,
  };
}
