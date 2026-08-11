import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../controllers/metrics_controller.dart';

class MetricsScreen extends ConsumerWidget {
  const MetricsScreen({super.key});

  static const routeName = '/metrics';
  static const emptyStateKey = Key('metrics.empty');

  static Key metricGroupKey(String groupName) =>
      Key('metrics.group.$groupName');

  static Key metricTileKey(String metricId) => Key('metrics.tile.$metricId');

  static const addMetricButtonKey = Key('metrics.addMetric');
  static const metricNameFieldKey = Key('metrics.form.name');
  static const metricUnitFieldKey = Key('metrics.form.unit');
  static const saveMetricButtonKey = Key('metrics.form.save');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(metricsControllerProvider);

    return state.when(
      data: (metrics) => _MetricsContent(state: metrics),
      loading: () => Scaffold(
        appBar: AppBar(title: Text(context.l10n.metricsTitle)),
        body: const SizedBox.expand(),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.metricsTitle)),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Text(
              context.l10n.metricsUnavailable,
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

class _MetricsContent extends StatefulWidget {
  const _MetricsContent({
    required this.state,
  });

  final MetricsState state;

  @override
  State<_MetricsContent> createState() => _MetricsContentState();
}

class _MetricsContentState extends State<_MetricsContent> {
  final Set<String> _expandedSections = <String>{};

  @override
  Widget build(BuildContext context) {
    final sections = _groupMetricSummaries(widget.state.summaries);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.metricsTitle),
        actions: [
          IconButton(
            key: MetricsScreen.addMetricButtonKey,
            tooltip: context.l10n.metricsAddMetricTooltip,
            onPressed: () => _openAddMetric(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: SafeArea(
        child: widget.state.summaries.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(AppDimens.base),
                child: Text(
                  context.l10n.metricsEmpty,
                  key: MetricsScreen.emptyStateKey,
                  style: context.textStyles.body.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.base,
                  AppDimens.base,
                  AppDimens.base,
                  AppDimens.base * 2,
                ),
                children: [
                  for (final section in sections) ...[
                    _MetricSectionHeader(
                      section: section,
                      expanded: _expandedSections.contains(
                        section.taxonomy.section,
                      ),
                      onTap: () {
                        setState(() {
                          final sectionName = section.taxonomy.section;
                          if (_expandedSections.contains(sectionName)) {
                            _expandedSections.remove(sectionName);
                          } else {
                            _expandedSections.add(sectionName);
                          }
                        });
                      },
                    ),
                    if (_expandedSections.contains(section.taxonomy.section))
                      for (final family in section.families) ...[
                        _MetricFamilyHeader(family: family),
                        for (final summary in family.summaries) ...[
                          _MetricTile(summary: summary),
                          const SizedBox(height: AppDimens.dense),
                        ],
                      ],
                    const SizedBox(height: AppDimens.base),
                  ],
                ],
              ),
      ),
    );
  }

  void _openAddMetric(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const _MetricFormScreen(),
      ),
    );
  }
}

/// Creates a manually-authored `Metric` — the general "Custom"
/// counterpart to Body Tracker's bodyComposition-only creation form
/// (`_MeasurementFormScreen`). `unit` is deliberately free text rather than
/// a fixed enum: a biomarker's lab unit (ng/dL, pg/mL, mIU/L…) isn't one of
/// Body Tracker's physical measurement units, and the Metric domain never
/// constrains it ( curates registries for authored Dimensions, not
/// this free-text Metric unit).
class _MetricFormScreen extends ConsumerStatefulWidget {
  const _MetricFormScreen();

  @override
  ConsumerState<_MetricFormScreen> createState() => _MetricFormScreenState();
}

class _MetricFormScreenState extends ConsumerState<_MetricFormScreen> {
  final _nameController = TextEditingController();
  final _unitController = TextEditingController();
  String? _nameError;
  String? _unitError;

  @override
  void dispose() {
    _nameController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.metricsCreateMetricTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDimens.base),
          children: [
            TextField(
              key: MetricsScreen.metricNameFieldKey,
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.metricsNameLabel,
                errorText: _nameError,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppDimens.base),
            TextField(
              key: MetricsScreen.metricUnitFieldKey,
              controller: _unitController,
              decoration: InputDecoration(
                labelText: l10n.metricsUnitLabel,
                hintText: l10n.metricsUnitHint,
                errorText: _unitError,
              ),
            ),
            const SizedBox(height: AppDimens.base),
            FilledButton.icon(
              key: MetricsScreen.saveMetricButtonKey,
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(l10n.metricsCreate),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final name = _nameController.text.trim();
    final unit = _unitController.text.trim();
    setState(() {
      _nameError = name.isEmpty ? l10n.metricsNameRequired : null;
      _unitError = unit.isEmpty ? l10n.metricsUnitRequired : null;
    });
    if (_nameError != null || _unitError != null) {
      return;
    }

    await ref.read(metricsControllerProvider.notifier).createMetric(
          name: name,
          unit: unit,
        );
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.metricsMetricCreated)),
    );
  }
}

class _MetricSectionHeader extends StatelessWidget {
  const _MetricSectionHeader({
    required this.section,
    required this.expanded,
    required this.onTap,
  });

  final _MetricSectionGroup section;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      hint: expanded ? 'Collapse' : 'Expand',
      child: InkWell(
        key: MetricsScreen.metricGroupKey(section.taxonomy.section),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppDimens.dense,
          ),
          child: Row(
            children: [
              Icon(section.taxonomy.icon, size: 20),
              const SizedBox(width: AppDimens.dense),
              Expanded(
                child: Text(
                  section.taxonomy.section,
                  style: context.textStyles.h2,
                ),
              ),
              Text(
                section.metricCount.toString(),
                style: context.textStyles.caption.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(width: AppDimens.dense),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                color: context.colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricFamilyHeader extends StatelessWidget {
  const _MetricFamilyHeader({
    required this.family,
  });

  final _MetricFamilyGroup family;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppDimens.dense / 2,
        bottom: AppDimens.dense,
      ),
      child: Text(
        family.taxonomy.family,
        style: context.textStyles.caption.copyWith(
          color: context.colors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.summary,
  });

  final MetricSummary summary;

  @override
  Widget build(BuildContext context) {
    final latestReading = summary.latestReading;
    final trendLabel = _trendLabel(
      summary.trendDelta,
      summary.metric.unit,
    );

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        key: MetricsScreen.metricTileKey(summary.metric.id),
        minVerticalPadding: AppDimens.dense,
        leading: Icon(_metricIcon(summary.metric)),
        title: Text(summary.metric.name),
        subtitle: latestReading == null
            ? Text(
                'No readings yet',
                style: context.textStyles.caption.copyWith(
                  color: context.colors.textSecondary,
                ),
              )
            : _MetricSubtitle(reading: latestReading),
        trailing: latestReading == null
            ? const Icon(Icons.chevron_right)
            : _MetricTrailing(
                valueLabel: _readingValueLabel(
                  context,
                  summary.metric,
                  latestReading,
                ),
                trendLabel: trendLabel,
                trendDelta: summary.trendDelta,
              ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => MetricDetailScreen(metricId: summary.metric.id),
            ),
          );
        },
      ),
    );
  }
}

class _MetricSubtitle extends StatelessWidget {
  const _MetricSubtitle({
    required this.reading,
  });

  final MetricReadingRecord reading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.dense / 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.metricsLatestReading(
              _formatReadingTime(context, reading),
            ),
          ),
          const SizedBox(height: AppDimens.dense / 3),
          Text(
            context.l10n.metricsSource(reading.source),
            style: context.textStyles.caption.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTrailing extends StatelessWidget {
  const _MetricTrailing({
    required this.valueLabel,
    required this.trendLabel,
    required this.trendDelta,
  });

  final String valueLabel;
  final String? trendLabel;
  final double? trendDelta;

  @override
  Widget build(BuildContext context) {
    final trendLabel = this.trendLabel;
    final trendDelta = this.trendDelta;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 128),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            valueLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.numeralRow,
          ),
          if (trendLabel != null && trendDelta != null) ...[
            const SizedBox(height: AppDimens.dense / 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  trendDelta < 0 ? Icons.trending_down : Icons.trending_up,
                  size: 16,
                  color: context.colors.textSecondary,
                ),
                const SizedBox(width: AppDimens.dense / 3),
                Flexible(
                  child: Text(
                    trendLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.caption.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class MetricDetailScreen extends ConsumerWidget {
  const MetricDetailScreen({
    required this.metricId,
    super.key,
  });

  static const chartKey = Key('metrics.detail.chart');
  static const logReadingButtonKey = Key('metrics.detail.logReading');
  static const readingValueFieldKey = Key('metrics.detail.reading.value');
  static const readingMeasuredAtFieldKey =
      Key('metrics.detail.reading.measuredAt');
  static const readingCommentFieldKey =
      Key('metrics.detail.reading.comment');
  static const saveReadingButtonKey = Key('metrics.detail.reading.save');

  static Key historyReadingKey(String readingId) {
    return Key('metrics.detail.history.$readingId');
  }

  final String metricId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(metricSeriesControllerProvider(metricId));

    return state.when(
      data: (series) {
        if (series == null) {
          return Scaffold(
            appBar: AppBar(title: Text(context.l10n.metricsTitle)),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppDimens.base),
                child: Text(
                  context.l10n.metricsUnavailable,
                  style: context.textStyles.body.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }
        return _MetricDetailContent(series: series);
      },
      loading: () => Scaffold(
        appBar: AppBar(title: Text(context.l10n.metricsTitle)),
        body: const SizedBox.expand(),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.metricsTitle)),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Text(
              context.l10n.metricsUnavailable,
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

class _MetricDetailContent extends StatefulWidget {
  const _MetricDetailContent({
    required this.series,
  });

  final MetricSeriesData series;

  @override
  State<_MetricDetailContent> createState() => _MetricDetailContentState();
}

class _MetricDetailContentState extends State<_MetricDetailContent> {
  final ScrollController _historyController = ScrollController();
  final Map<String, GlobalKey> _historyKeys = <String, GlobalKey>{};

  _MetricChartMode _chartMode = _MetricChartMode.readings;
  String? _selectedPointKey;
  String? _selectedReadingId;

  @override
  void didUpdateWidget(covariant _MetricDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final activeReadingIds =
        widget.series.readings.map((reading) => reading.id).toSet();
    _historyKeys.removeWhere((readingId, _) {
      return !activeReadingIds.contains(readingId);
    });
    final selectedReadingId = _selectedReadingId;
    if (selectedReadingId != null &&
        !activeReadingIds.contains(selectedReadingId)) {
      _selectedPointKey = null;
      _selectedReadingId = null;
    }
  }

  @override
  void dispose() {
    _historyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readings = widget.series.readings.reversed.toList(growable: false);
    final latestReading = readings.isEmpty ? null : readings.first;
    final chartPoints = _chartPoints(
      widget.series.metric,
      widget.series.readings,
      _chartMode,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.series.metric.name),
        actions: [
          // Manual logging only makes sense for a scalar Metric — a
          // structured/series shape (e.g. sleep stages) isn't something
          // this simple value+time form can author ( stays scoped
          // to the scalar case the Effect view's deltas already read).
          if (widget.series.metric.valueShape == MetricValueShape.scalar)
            IconButton(
              key: MetricDetailScreen.logReadingButtonKey,
              tooltip: context.l10n.metricsLogReadingTooltip,
              onPressed: () => _openLogReading(context, widget.series.metric),
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      latestReading == null
                          ? 'No readings yet'
                          : _readingValueLabel(
                              context,
                              widget.series.metric,
                              latestReading,
                            ),
                      style: context.textStyles.numeralHero,
                    ),
                  ),
                  Text(
                    _taxonomyFor(widget.series.metric).section,
                    style: context.textStyles.caption.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.base),
              _MetricChartPanel(
                metric: widget.series.metric,
                mode: _chartMode,
                points: chartPoints,
                selectedPointKey: _selectedPointKey,
                onModeChanged: (mode) {
                  setState(() {
                    _chartMode = mode;
                    _selectedPointKey = null;
                    _selectedReadingId = null;
                  });
                },
                onPointSelected: _handlePointSelected,
              ),
              const SizedBox(height: AppDimens.base),
              Text('History', style: context.textStyles.h2),
              const SizedBox(height: AppDimens.dense),
              Expanded(
                child: readings.isEmpty
                    ? Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          'No readings yet',
                          style: context.textStyles.body.copyWith(
                            color: context.colors.textSecondary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _historyController,
                        itemCount: readings.length,
                        itemBuilder: (context, index) {
                          final reading = readings[index];
                          return _MetricReadingRow(
                            key: _historyKeyFor(reading.id),
                            metric: widget.series.metric,
                            reading: reading,
                            selected: reading.id == _selectedReadingId,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  GlobalKey _historyKeyFor(String readingId) {
    return _historyKeys.putIfAbsent(readingId, () => GlobalKey());
  }

  void _openLogReading(BuildContext context, MetricRecord metric) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _LogReadingScreen(metric: metric),
      ),
    );
  }

  void _handlePointSelected(_SeriesPoint point) {
    setState(() {
      _selectedPointKey = point.key;
      _selectedReadingId = point.scrollReadingId;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rowContext = _historyKeys[point.scrollReadingId]?.currentContext;
      if (rowContext == null) {
        return;
      }
      Scrollable.ensureVisible(
        rowContext,
        alignment: 0.18,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }
}

/// Logs a manually-entered scalar `Reading` against an existing `Metric`
/// — mirrors Body Tracker's `_MeasurementEntryScreen` (value +
/// measured-at + optional comment), generalized to any scalar Metric so a
/// biomarker gets the same ≤-a-few-taps manual entry a body measurement
/// already had, with no separate Protocols-only path.
class _LogReadingScreen extends ConsumerStatefulWidget {
  const _LogReadingScreen({required this.metric});

  final MetricRecord metric;

  @override
  ConsumerState<_LogReadingScreen> createState() => _LogReadingScreenState();
}

class _LogReadingScreenState extends ConsumerState<_LogReadingScreen> {
  late final TextEditingController _valueController;
  late final TextEditingController _measuredAtController;
  late final TextEditingController _commentController;
  String? _valueError;
  String? _measuredAtError;

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController();
    _measuredAtController = TextEditingController(
      text: _formatEditableDateTime(DateTime.now()),
    );
    _commentController = TextEditingController();
  }

  @override
  void dispose() {
    _valueController.dispose();
    _measuredAtController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.metricsLogReadingTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDimens.base),
          children: [
            TextField(
              key: MetricDetailScreen.readingValueFieldKey,
              controller: _valueController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.metricsValueLabel,
                suffixText: widget.metric.unit,
                errorText: _valueError,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: AppDimens.base),
            TextField(
              key: MetricDetailScreen.readingMeasuredAtFieldKey,
              controller: _measuredAtController,
              decoration: InputDecoration(
                labelText: l10n.metricsMeasuredAtLabel,
                errorText: _measuredAtError,
              ),
              keyboardType: TextInputType.datetime,
            ),
            const SizedBox(height: AppDimens.base),
            TextField(
              key: MetricDetailScreen.readingCommentFieldKey,
              controller: _commentController,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.metricsCommentLabel,
              ),
            ),
            const SizedBox(height: AppDimens.base),
            FilledButton.icon(
              key: MetricDetailScreen.saveReadingButtonKey,
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(l10n.metricsSaveReading),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final measuredAt = _parseEditableDateTime(_measuredAtController.text);
    setState(() {
      _valueError = null;
      _measuredAtError =
          measuredAt == null ? l10n.metricsInvalidDateTime : null;
    });
    if (measuredAt == null) {
      return;
    }

    try {
      await ref.read(metricsControllerProvider.notifier).logReading(
            metricId: widget.metric.id,
            valueEntered: _valueController.text,
            measuredAt: measuredAt,
            comment: _commentController.text,
          );
    } on ArgumentError {
      setState(() {
        _valueError = l10n.metricsInvalidValue;
      });
      return;
    }

    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.metricsReadingSaved)),
    );
  }
}

class _MetricChartPanel extends StatelessWidget {
  const _MetricChartPanel({
    required this.metric,
    required this.mode,
    required this.points,
    required this.selectedPointKey,
    required this.onModeChanged,
    required this.onPointSelected,
  });

  final MetricRecord metric;
  final _MetricChartMode mode;
  final List<_SeriesPoint> points;
  final String? selectedPointKey;
  final ValueChanged<_MetricChartMode> onModeChanged;
  final ValueChanged<_SeriesPoint> onPointSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: MetricDetailScreen.chartKey,
      height: 282,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Chart', style: context.textStyles.h2),
                  const Spacer(),
                  _MetricChartModeSelector(
                    mode: mode,
                    onChanged: onModeChanged,
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.dense),
              Expanded(
                child: points.isEmpty
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'No time series yet',
                          style: context.textStyles.body.copyWith(
                            color: context.colors.textSecondary,
                          ),
                        ),
                      )
                    : _MetricChartCanvas(
                        metric: metric,
                        mode: mode,
                        points: points,
                        selectedPointKey: selectedPointKey,
                        onPointSelected: onPointSelected,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricChartModeSelector extends StatelessWidget {
  const _MetricChartModeSelector({
    required this.mode,
    required this.onChanged,
  });

  final _MetricChartMode mode;
  final ValueChanged<_MetricChartMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_MetricChartMode>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment<_MetricChartMode>(
          value: _MetricChartMode.readings,
          icon: Icon(Icons.timeline_outlined),
          label: Text('Raw'),
        ),
        ButtonSegment<_MetricChartMode>(
          value: _MetricChartMode.daily,
          icon: Icon(Icons.calendar_view_day_outlined),
          label: Text('Day'),
        ),
        ButtonSegment<_MetricChartMode>(
          value: _MetricChartMode.weekly,
          icon: Icon(Icons.calendar_view_week_outlined),
          label: Text('Week'),
        ),
      ],
      selected: <_MetricChartMode>{mode},
      onSelectionChanged: (selection) {
        onChanged(selection.single);
      },
    );
  }
}

class _MetricChartCanvas extends StatelessWidget {
  const _MetricChartCanvas({
    required this.metric,
    required this.mode,
    required this.points,
    required this.selectedPointKey,
    required this.onPointSelected,
  });

  final MetricRecord metric;
  final _MetricChartMode mode;
  final List<_SeriesPoint> points;
  final String? selectedPointKey;
  final ValueChanged<_SeriesPoint> onPointSelected;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final point = _nearestChartPoint(
              points,
              details.localPosition,
              size,
            );
            if (point != null) {
              onPointSelected(point);
            }
          },
          child: CustomPaint(
            painter: _MetricChartPainter(
              points: points,
              mode: mode,
              unit: metric.unit,
              locale: locale,
              selectedPointKey: selectedPointKey,
              lineColor: context.colors.record,
              axisColor: context.colors.textSecondary,
              gridColor: context.colors.divider,
              textColor: context.colors.textSecondary,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

class _MetricReadingRow extends StatelessWidget {
  const _MetricReadingRow({
    required this.metric,
    required this.reading,
    required this.selected,
    super.key,
  });

  final MetricRecord metric;
  final MetricReadingRecord reading;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: AppDimens.dense),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.dense,
        vertical: AppDimens.dense,
      ),
      decoration: selected
          ? BoxDecoration(
              color: context.colors.record.withValues(alpha: 0.12),
              border: Border(
                left: BorderSide(
                  color: context.colors.record,
                  width: 4,
                ),
              ),
            )
          : null,
      child: Row(
        key: MetricDetailScreen.historyReadingKey(reading.id),
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_formatReadingTime(context, reading)),
                const SizedBox(height: AppDimens.dense / 3),
                Text(
                  context.l10n.metricsSource(reading.source),
                  style: context.textStyles.caption.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppDimens.base),
          Text(
            _readingValueLabel(context, metric, reading),
            style: context.textStyles.numeralRow,
          ),
        ],
      ),
    );
  }
}

class _MetricChartPainter extends CustomPainter {
  const _MetricChartPainter({
    required this.points,
    required this.mode,
    required this.unit,
    required this.locale,
    required this.selectedPointKey,
    required this.lineColor,
    required this.axisColor,
    required this.gridColor,
    required this.textColor,
  });

  final List<_SeriesPoint> points;
  final _MetricChartMode mode;
  final String unit;
  final String locale;
  final String? selectedPointKey;
  final Color lineColor;
  final Color axisColor;
  final Color gridColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) {
      return;
    }

    final bounds = _chartPlotBounds(size);
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1;

    final yTicks = _chartValueTicks(points);
    for (final value in yTicks) {
      final y = _chartOffsetForValue(points, value, bounds).dy;
      canvas.drawLine(
        Offset(bounds.left, y),
        Offset(bounds.right, y),
        gridPaint,
      );
      _paintLabel(
        canvas,
        _formatAxisValue(value, unit),
        Offset(0, y - 8),
        TextStyle(color: textColor, fontSize: 11),
        maxWidth: bounds.left - 6,
        textAlign: TextAlign.right,
      );
    }

    canvas.drawLine(bounds.bottomLeft, bounds.bottomRight, axisPaint);
    canvas.drawLine(bounds.topLeft, bounds.bottomLeft, axisPaint);

    if (points.length > 1) {
      final path = Path()
        ..moveTo(
          _chartOffsetFor(points.first, points, bounds).dx,
          _chartOffsetFor(points.first, points, bounds).dy,
        );
      for (final point in points.skip(1)) {
        final offset = _chartOffsetFor(point, points, bounds);
        path.lineTo(offset.dx, offset.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 3,
      );
    }

    final dotPaint = Paint()..color = lineColor;
    final selectedPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final dotRadius = points.length > 60 ? 2.0 : 3.0;
    for (final point in points) {
      final offset = _chartOffsetFor(point, points, bounds);
      canvas.drawCircle(offset, dotRadius, dotPaint);
      if (point.key == selectedPointKey) {
        canvas.drawCircle(offset, dotRadius + 5, selectedPaint);
      }
    }

    final xTicks = _chartTimeTicks(points);
    for (final point in xTicks) {
      final offset = _chartOffsetFor(point, points, bounds);
      final label = _formatAxisTimestamp(locale, point.timestamp, mode);
      _paintCenteredLabel(
        canvas,
        label,
        Offset(offset.dx, bounds.bottom + 6),
        TextStyle(color: textColor, fontSize: 11),
        size.width,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MetricChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.mode != mode ||
        oldDelegate.unit != unit ||
        oldDelegate.locale != locale ||
        oldDelegate.selectedPointKey != selectedPointKey ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.axisColor != axisColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.textColor != textColor;
  }
}

enum _MetricChartMode {
  readings,
  daily,
  weekly;
}

enum _MetricAggregation {
  average,
  sum,
  min,
  max,
  latest;
}

class _MetricTaxonomy {
  const _MetricTaxonomy({
    required this.section,
    required this.family,
    required this.sectionOrder,
    required this.familyOrder,
    required this.icon,
  });

  final String section;
  final String family;
  final int sectionOrder;
  final int familyOrder;
  final IconData icon;
}

class _MetricSectionGroup {
  _MetricSectionGroup({
    required this.taxonomy,
  });

  final _MetricTaxonomy taxonomy;
  final List<_MetricFamilyGroup> families = <_MetricFamilyGroup>[];

  int get metricCount {
    return families.fold<int>(
      0,
      (total, family) => total + family.summaries.length,
    );
  }
}

class _MetricFamilyGroup {
  _MetricFamilyGroup({
    required this.taxonomy,
  });

  final _MetricTaxonomy taxonomy;
  final List<MetricSummary> summaries = <MetricSummary>[];
}

class _SeriesPoint {
  const _SeriesPoint({
    required this.key,
    required this.timestamp,
    required this.value,
    required this.scrollReadingId,
  });

  final String key;
  final DateTime timestamp;
  final double value;
  final String scrollReadingId;
}

List<_MetricSectionGroup> _groupMetricSummaries(
  List<MetricSummary> summaries,
) {
  final sorted = summaries.toList(growable: false)
    ..sort((a, b) {
      final taxonomyA = _taxonomyFor(a.metric);
      final taxonomyB = _taxonomyFor(b.metric);
      final section = taxonomyA.sectionOrder.compareTo(taxonomyB.sectionOrder);
      if (section != 0) {
        return section;
      }
      final family = taxonomyA.familyOrder.compareTo(taxonomyB.familyOrder);
      if (family != 0) {
        return family;
      }
      final pinned = b.metric.pinned.toString().compareTo(
            a.metric.pinned.toString(),
          );
      if (pinned != 0) {
        return pinned;
      }
      final sortOrder = a.metric.sortOrder.compareTo(b.metric.sortOrder);
      if (sortOrder != 0) {
        return sortOrder;
      }
      final name = a.metric.name.compareTo(b.metric.name);
      if (name != 0) {
        return name;
      }
      return a.metric.id.compareTo(b.metric.id);
    });

  final sections = <_MetricSectionGroup>[];
  for (final summary in sorted) {
    final taxonomy = _taxonomyFor(summary.metric);
    var section = sections.cast<_MetricSectionGroup?>().firstWhere(
          (candidate) => candidate?.taxonomy.section == taxonomy.section,
          orElse: () => null,
        );
    if (section == null) {
      section = _MetricSectionGroup(taxonomy: taxonomy);
      sections.add(section);
    }

    var family = section.families.cast<_MetricFamilyGroup?>().firstWhere(
          (candidate) => candidate?.taxonomy.family == taxonomy.family,
          orElse: () => null,
        );
    if (family == null) {
      family = _MetricFamilyGroup(taxonomy: taxonomy);
      section.families.add(family);
    }
    family.summaries.add(summary);
  }
  return sections;
}

_MetricTaxonomy _taxonomyFor(MetricRecord metric) {
  final name = metric.name.toLowerCase();

  if (metric.group == MetricGroup.bodyComposition ||
      name.contains('weight') ||
      name.contains('body fat')) {
    return const _MetricTaxonomy(
      section: 'Body',
      family: 'Composition',
      sectionOrder: 10,
      familyOrder: 10,
      icon: Icons.straighten_outlined,
    );
  }

  if (name.contains('sleep') ||
      name.contains('rem') ||
      name.contains('awake') ||
      name.contains('deep') ||
      name.contains('light')) {
    return _MetricTaxonomy(
      section: 'Sleep',
      family: name.contains('score') ? 'Quality' : 'Duration & Stages',
      sectionOrder: 20,
      familyOrder: name.contains('score') ? 20 : 10,
      icon: Icons.bedtime_outlined,
    );
  }

  if (name.contains('heart') || metric.unit == 'beatsPerMinute') {
    return const _MetricTaxonomy(
      section: 'Cardiovascular',
      family: 'Heart Rate',
      sectionOrder: 30,
      familyOrder: 10,
      icon: Icons.monitor_heart_outlined,
    );
  }

  if (name.contains('hrv')) {
    return const _MetricTaxonomy(
      section: 'Cardiovascular',
      family: 'Heart Rate Variability',
      sectionOrder: 30,
      familyOrder: 20,
      icon: Icons.monitor_heart_outlined,
    );
  }

  if (name.contains('stress')) {
    return const _MetricTaxonomy(
      section: 'Recovery',
      family: 'Stress',
      sectionOrder: 40,
      familyOrder: 10,
      icon: Icons.spa_outlined,
    );
  }

  if (name.contains('body battery') || name.contains('battery')) {
    return const _MetricTaxonomy(
      section: 'Recovery',
      family: 'Body Battery',
      sectionOrder: 40,
      familyOrder: 20,
      icon: Icons.battery_charging_full_outlined,
    );
  }

  if (name.contains('step') ||
      name.contains('cadence') ||
      name.contains('distance')) {
    return const _MetricTaxonomy(
      section: 'Activity & Energy',
      family: 'Movement',
      sectionOrder: 50,
      familyOrder: 10,
      icon: Icons.directions_walk_outlined,
    );
  }

  if (name.contains('calorie') ||
      name.contains('energy') ||
      metric.unit == 'kilocalorie') {
    return const _MetricTaxonomy(
      section: 'Activity & Energy',
      family: 'Energy',
      sectionOrder: 50,
      familyOrder: 20,
      icon: Icons.local_fire_department_outlined,
    );
  }

  if (name.contains('power') || metric.unit == 'watt') {
    return const _MetricTaxonomy(
      section: 'Training',
      family: 'Output',
      sectionOrder: 60,
      familyOrder: 10,
      icon: Icons.bolt_outlined,
    );
  }

  if (metric.group == MetricGroup.custom) {
    return const _MetricTaxonomy(
      section: 'Custom',
      family: 'User Metrics',
      sectionOrder: 90,
      familyOrder: 10,
      icon: Icons.tune_outlined,
    );
  }

  return const _MetricTaxonomy(
    section: 'Wellness',
    family: 'Other',
    sectionOrder: 80,
    familyOrder: 10,
    icon: Icons.timeline_outlined,
  );
}

List<_SeriesPoint> _chartPoints(
  MetricRecord metric,
  List<MetricReadingRecord> readings,
  _MetricChartMode mode,
) {
  final scalarReadings = readings
      .where((reading) => reading.scalarValue != null)
      .toList(growable: false)
    ..sort((a, b) => _readingObservedAt(a).compareTo(_readingObservedAt(b)));

  if (mode == _MetricChartMode.readings) {
    return scalarReadings
        .map(
          (reading) => _SeriesPoint(
            key: '${mode.name}:${reading.id}',
            timestamp: _readingObservedAt(reading),
            value: reading.scalarValue!,
            scrollReadingId: reading.id,
          ),
        )
        .toList(growable: false);
  }

  final buckets = <DateTime, List<MetricReadingRecord>>{};
  for (final reading in scalarReadings) {
    final bucket = switch (mode) {
      _MetricChartMode.readings => _readingObservedAt(reading),
      _MetricChartMode.daily => _dayBucket(_readingObservedAt(reading)),
      _MetricChartMode.weekly => _weekBucket(_readingObservedAt(reading)),
    };
    buckets.putIfAbsent(bucket, () => <MetricReadingRecord>[]).add(reading);
  }

  final entries = buckets.entries.toList(growable: false)
    ..sort((a, b) => a.key.compareTo(b.key));
  return entries
      .map(
        (entry) => _SeriesPoint(
          key: '${mode.name}:${entry.key.toIso8601String()}',
          timestamp: entry.key,
          value: _aggregateMetricValue(metric, entry.value),
          scrollReadingId: _latestReadingIn(entry.value).id,
        ),
      )
      .toList(growable: false);
}

double _aggregateMetricValue(
  MetricRecord metric,
  List<MetricReadingRecord> readings,
) {
  final values = readings
      .map((reading) => reading.scalarValue)
      .whereType<double>()
      .toList(growable: false);
  if (values.isEmpty) {
    return 0;
  }

  return switch (_aggregationFor(metric)) {
    _MetricAggregation.sum => values.reduce((a, b) => a + b),
    _MetricAggregation.min => values.reduce(math.min),
    _MetricAggregation.max => values.reduce(math.max),
    _MetricAggregation.latest => _latestReadingIn(readings).scalarValue ?? 0,
    _MetricAggregation.average =>
      values.reduce((a, b) => a + b) / values.length,
  };
}

_MetricAggregation _aggregationFor(MetricRecord metric) {
  final name = metric.name.toLowerCase();
  if (name.startsWith('min ') || name.contains(' minimum')) {
    return _MetricAggregation.min;
  }
  if (name.startsWith('max ') || name.contains(' maximum')) {
    return _MetricAggregation.max;
  }
  if (name.contains('step') ||
      name.contains('calorie') ||
      name.contains('duration') ||
      name.contains('sleep') ||
      name.contains('awake') ||
      name.contains('deep') ||
      name.contains('light') ||
      name.contains('rem')) {
    return _MetricAggregation.sum;
  }
  if (metric.group == MetricGroup.bodyComposition) {
    return _MetricAggregation.latest;
  }
  return _MetricAggregation.average;
}

MetricReadingRecord _latestReadingIn(List<MetricReadingRecord> readings) {
  return readings.reduce((a, b) {
    return _readingObservedAt(a).isAfter(_readingObservedAt(b)) ? a : b;
  });
}

DateTime _readingObservedAt(MetricReadingRecord reading) {
  return reading.atTime ??
      reading.windowEndedAt ??
      reading.windowStartedAt ??
      reading.updatedAt;
}

DateTime _dayBucket(DateTime timestamp) {
  final local = timestamp.toLocal();
  return DateTime(local.year, local.month, local.day);
}

DateTime _weekBucket(DateTime timestamp) {
  final day = _dayBucket(timestamp);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

_SeriesPoint? _nearestChartPoint(
  List<_SeriesPoint> points,
  Offset position,
  Size size,
) {
  if (points.isEmpty || size.width <= 0 || size.height <= 0) {
    return null;
  }
  final bounds = _chartPlotBounds(size);
  _SeriesPoint? nearest;
  var nearestDistance = double.infinity;
  for (final point in points) {
    final offset = _chartOffsetFor(point, points, bounds);
    final distance = (offset - position).distanceSquared;
    if (distance < nearestDistance) {
      nearest = point;
      nearestDistance = distance;
    }
  }
  return nearest;
}

Rect _chartPlotBounds(Size size) {
  final left = math.min(56.0, size.width * 0.28);
  final right = math.max(left + 1, size.width - 10);
  final top = 8.0;
  final bottom = math.max(top + 1, size.height - 42);
  return Rect.fromLTRB(left, top, right, bottom);
}

Offset _chartOffsetFor(
  _SeriesPoint point,
  List<_SeriesPoint> points,
  Rect bounds,
) {
  final minTime = points.first.timestamp.millisecondsSinceEpoch.toDouble();
  final maxTime = points.last.timestamp.millisecondsSinceEpoch.toDouble();
  final minValue = points.map((point) => point.value).reduce(math.min);
  final maxValue = points.map((point) => point.value).reduce(math.max);
  final timestamp = point.timestamp.millisecondsSinceEpoch.toDouble();
  final x = minTime == maxTime
      ? bounds.center.dx
      : bounds.left +
          ((timestamp - minTime) / (maxTime - minTime)) * bounds.width;
  final y = minValue == maxValue
      ? bounds.center.dy
      : bounds.bottom -
          ((point.value - minValue) / (maxValue - minValue)) * bounds.height;
  return Offset(x, y);
}

Offset _chartOffsetForValue(
  List<_SeriesPoint> points,
  double value,
  Rect bounds,
) {
  final minValue = points.map((point) => point.value).reduce(math.min);
  final maxValue = points.map((point) => point.value).reduce(math.max);
  final y = minValue == maxValue
      ? bounds.center.dy
      : bounds.bottom -
          ((value - minValue) / (maxValue - minValue)) * bounds.height;
  return Offset(bounds.left, y);
}

List<double> _chartValueTicks(List<_SeriesPoint> points) {
  final minValue = points.map((point) => point.value).reduce(math.min);
  final maxValue = points.map((point) => point.value).reduce(math.max);
  if (minValue == maxValue) {
    return <double>[minValue];
  }
  return <double>[
    minValue,
    minValue + ((maxValue - minValue) / 2),
    maxValue,
  ];
}

List<_SeriesPoint> _chartTimeTicks(List<_SeriesPoint> points) {
  if (points.length <= 2) {
    return points;
  }
  return <_SeriesPoint>[
    points.first,
    points[points.length ~/ 2],
    points.last,
  ];
}

void _paintLabel(
  Canvas canvas,
  String label,
  Offset offset,
  TextStyle style, {
  required double maxWidth,
  TextAlign textAlign = TextAlign.left,
}) {
  final painter = TextPainter(
    text: TextSpan(text: label, style: style),
    textAlign: textAlign,
    textDirection: ui.TextDirection.ltr,
    maxLines: 2,
  )..layout(maxWidth: maxWidth);
  painter.paint(canvas, offset);
}

void _paintCenteredLabel(
  Canvas canvas,
  String label,
  Offset centerTop,
  TextStyle style,
  double canvasWidth,
) {
  final painter = TextPainter(
    text: TextSpan(text: label, style: style),
    textAlign: TextAlign.center,
    textDirection: ui.TextDirection.ltr,
    maxLines: 2,
  )..layout(maxWidth: 72);
  final x = (centerTop.dx - painter.width / 2)
      .clamp(
        0.0,
        math.max(0, canvasWidth - painter.width),
      )
      .toDouble();
  painter.paint(canvas, Offset(x, centerTop.dy));
}

IconData _metricIcon(MetricRecord metric) {
  return _taxonomyFor(metric).icon;
}

String _formatReadingTime(
  BuildContext context,
  MetricReadingRecord reading,
) {
  final observedAt = _readingObservedAt(reading);
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.yMMMd(locale).add_jm().format(observedAt.toLocal());
}

String _formatAxisTimestamp(
  String locale,
  DateTime timestamp,
  _MetricChartMode mode,
) {
  final local = timestamp.toLocal();
  return switch (mode) {
    _MetricChartMode.readings =>
      '${DateFormat.MMMd(locale).format(local)}\n${DateFormat.jm(locale).format(local)}',
    _MetricChartMode.daily => DateFormat.MMMd(locale).format(local),
    _MetricChartMode.weekly => DateFormat.MMMd(locale).format(local),
  };
}

String _formatAxisValue(double value, String unit) {
  if (unit == 'second') {
    return '${_formatCompactDouble(value / 3600)} h';
  }
  if (unit == 'count') {
    return _formatCompactDouble(value);
  }
  return '${_formatCompactDouble(value)} ${_unitLabel(unit)}';
}

String _readingValueLabel(
  BuildContext context,
  MetricRecord metric,
  MetricReadingRecord reading,
) {
  final scalarValue = reading.scalarValue;
  final entered = reading.scalarEntered;
  if (metric.unit == 'second' && scalarValue != null) {
    return context.l10n.bodyTrackerValueWithUnit(
      _formatCompactDouble(scalarValue / 3600),
      'h',
    );
  }
  if (metric.unit == 'count') {
    return entered ?? _formatCompactDouble(scalarValue ?? 0);
  }
  return context.l10n.bodyTrackerValueWithUnit(
    entered ?? _formatCompactDouble(scalarValue ?? 0),
    _unitLabel(metric.unit),
  );
}

String _unitLabel(String unit) {
  return switch (unit) {
    'beatsPerMinute' => 'bpm',
    'kilocalorie' => 'kcal',
    'kilogram' => 'kg',
    'pound' => 'lb',
    'centimeter' => 'cm',
    'inch' => 'in',
    'millisecond' => 'ms',
    'percent' => '%',
    'score' => 'score',
    'stepsPerMinute' => 'spm',
    'watt' => 'W',
    _ => unit,
  };
}

String? _trendLabel(double? trendDelta, String unit) {
  if (trendDelta == null) {
    return null;
  }
  final displayValue = unit == 'second' ? trendDelta / 3600 : trendDelta;
  final unitLabel = unit == 'second' ? 'h' : _unitLabel(unit);
  final value = _formatCompactDouble(displayValue);
  final sign = displayValue > 0 ? '+' : '';
  if (unit == 'count') {
    return '$sign$value';
  }
  return '$sign$value $unitLabel';
}

String _formatCompactDouble(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  var result = value.toStringAsFixed(2);
  while (result.contains('.') && result.endsWith('0')) {
    result = result.substring(0, result.length - 1);
  }
  if (result.endsWith('.')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

// Mirrors `body_tracker_screen.dart`'s private editable-date-time helpers of
// the same name — small enough (and file-local, per that file's own
// convention) that a shared util would cost more than it saves.
String _formatEditableDateTime(DateTime value) {
  return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
}

DateTime? _parseEditableDateTime(String value) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})$',
  ).firstMatch(value.trim());
  if (match == null) {
    return null;
  }

  final parts = <int>[];
  for (var index = 1; index <= 5; index += 1) {
    final parsed = int.tryParse(match.group(index)!);
    if (parsed == null) {
      return null;
    }
    parts.add(parsed);
  }

  final parsed = DateTime(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
  );
  if (parsed.year != parts[0] ||
      parsed.month != parts[1] ||
      parsed.day != parts[2] ||
      parsed.hour != parts[3] ||
      parsed.minute != parts[4]) {
    return null;
  }
  return parsed;
}
