import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../theme/theme.dart';
import '../controllers/effect_controller.dart';
import '../controllers/protocol_controller.dart';
import '../controllers/protocols_day_controller.dart';
import 'effect_timeline_chart.dart';

/// The `Effect` view (PROTOCOLS.md §4, §5) — the Protocols payoff
/// screen: choose a `Protocol`/`Compound` window, then see before/during/
/// after deltas on selected outcomes. Everything rendered here is DERIVED
/// analytics computed fresh on every open — nothing is stored, and nothing
/// is ever written back as a `Metric` Reading ("join, never merge", §2).
///
/// This slice lands the window picker, the outcome picker (seeded from a
/// Protocol's declared target outcomes, but freely adjustable ad
/// hoc), a minimal before/during/after render, the dose-overlay timeline,
/// the dose-response table — grouped by the ACTUAL
/// logged `Dose` level, never the Schedule/plan (§1.4) — and the strictly-
/// descriptive framing copy: a one-time neutral
/// disclaimer, and a confounder note so the deltas read as "what changed",
/// never a verdict.
///
/// Strictly descriptive, never causal: a delta is shown as a
/// plain number with a direction icon, never colored red/green as
/// good/bad — this is a neutral logbook, not an advisor. Copy anywhere on
/// this screen must never state or imply causation or efficacy ("works",
/// "caused", "improves because of") — that is HITL-reviewed, load-bearing
/// product copy; do not edit the disclaimer/confounder strings
/// without a fresh human sign-off.
class EffectScreen extends ConsumerWidget {
  const EffectScreen({super.key});

  static const noSourcesKey = Key('effect.noSources');
  static const noSourcePickedKey = Key('effect.noSourcePicked');
  static const noWindowKey = Key('effect.noWindow');
  static const windowSummaryKey = Key('effect.windowSummary');
  static const noOutcomesKey = Key('effect.noOutcomes');
  static const disclaimerKey = Key('effect.disclaimer');
  static const confounderNoteKey = Key('effect.confounderNote');

  /// A one-time neutral disclaimer (PROTOCOLS.md §3): present,
  /// factual, and never moralizing — no "warning", no "consult a doctor"
  /// nagging. HITL-reviewed copy; changing it needs a fresh human
  /// sign-off.
  static const disclaimerText = 'For personal tracking; not medical advice.';

  /// Surfaces the confounders that make a causal read of the deltas below
  /// unsupportable (PROTOCOLS.md §4) — descriptive framing, not a
  /// verdict. Shown once per rendered window, not repeated per outcome
  /// card. HITL-reviewed copy; changing it needs a fresh human
  /// sign-off.
  static const confounderNoteText =
      'What changed during this window — not a verdict. Diet, training, '
      'sleep, day-to-day variation (regression to the mean), and placebo '
      'can all move these numbers too, regardless of dosing.';

  static Key protocolChipKey(String id) => Key('effect.source.protocol-$id');
  static Key compoundChipKey(String id) => Key('effect.source.compound-$id');
  static Key metricOutcomeChipKey(String id) =>
      Key('effect.outcome.metric-$id');
  static const performanceOutcomeChipKey = Key('effect.outcome.performance');
  static Key resultCardKey(String outcomeKey) =>
      Key('effect.result.$outcomeKey');
  static Key doseResponseRowKey(String outcomeKey, int index) =>
      Key('effect.doseResponse.$outcomeKey.$index');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final protocols = ref.watch(protocolEffectOptionListProvider).value ??
        const <ProtocolEffectOptionRecord>[];
    final compounds = ref.watch(compoundOptionListProvider).value ??
        const <CompoundOptionRecord>[];
    final metrics = ref.watch(metricOptionListProvider).value ??
        const <MetricOptionRecord>[];
    final selection = ref.watch(effectSelectionControllerProvider);
    final computationAsync = ref.watch(effectComputationProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.chrome,
        title: const Text('Effect'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppDimens.base),
        children: <Widget>[
          Text(
            key: EffectScreen.disclaimerKey,
            EffectScreen.disclaimerText,
            style: context.textStyles.caption
                .copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppDimens.base),
          Text(
            'Window',
            style: TextStyle(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppDimens.dense),
          if (protocols.isEmpty && compounds.isEmpty)
            Text(
              key: EffectScreen.noSourcesKey,
              'No Protocols or Compounds yet.',
              style: TextStyle(color: colors.textSecondary),
            )
          else
            _SourcePicker(
              protocols: protocols,
              compounds: compounds,
              selectedSource: selection.source,
            ),
          const SizedBox(height: AppDimens.base),
          if (selection.source == null)
            Text(
              key: EffectScreen.noSourcePickedKey,
              'Choose a Protocol or Compound above to see its Effect window.',
              style: TextStyle(color: colors.textSecondary),
            )
          else ...<Widget>[
            Text(
              'Outcomes',
              style: TextStyle(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppDimens.dense),
            _OutcomePicker(metrics: metrics, selectedOutcomes: selection.outcomes),
            const SizedBox(height: AppDimens.base),
            computationAsync.when(
              data: (computation) {
                if (computation == null) {
                  return Text(
                    key: EffectScreen.noWindowKey,
                    'No logged Doses yet to derive a window from.',
                    style: TextStyle(color: colors.textSecondary),
                  );
                }
                return _EffectResultsBody(
                  computation: computation,
                  outcomes: selection.outcomes,
                  metrics: metrics,
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) => Text(
                'Could not compute the Effect view.',
                style: TextStyle(color: colors.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SourcePicker extends ConsumerWidget {
  const _SourcePicker({
    required this.protocols,
    required this.compounds,
    required this.selectedSource,
  });

  final List<ProtocolEffectOptionRecord> protocols;
  final List<CompoundOptionRecord> compounds;
  final EffectWindowSource? selectedSource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(effectSelectionControllerProvider.notifier);

    // No `labelStyle` override here (mirrors `protocol_screen.dart`'s
    // Compound/target-outcome chips): the default Material chip theme already
    // picks a contrast-safe label color for both the selected and unselected
    // states, and pinning it to `colors.textPrimary` broke that contrast
    // against a selected chip's own background in both themes.
    return Wrap(
      spacing: AppDimens.dense,
      runSpacing: AppDimens.dense,
      children: <Widget>[
        for (final protocol in protocols)
          ChoiceChip(
            key: EffectScreen.protocolChipKey(protocol.id),
            label: Text('Protocol: ${protocol.name}'),
            selected: selectedSource?.protocolId == protocol.id,
            onSelected: (_) => controller.selectProtocol(protocol),
          ),
        for (final compound in compounds)
          ChoiceChip(
            key: EffectScreen.compoundChipKey(compound.id),
            label: Text('Compound: ${compound.name}'),
            selected: selectedSource?.compoundId == compound.id,
            onSelected: (_) => controller.selectCompound(compound.id),
          ),
      ],
    );
  }
}

class _OutcomePicker extends ConsumerWidget {
  const _OutcomePicker({
    required this.metrics,
    required this.selectedOutcomes,
  });

  final List<MetricOptionRecord> metrics;
  final List<EffectOutcomeSelection> selectedOutcomes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(effectSelectionControllerProvider.notifier);

    if (metrics.isEmpty) {
      return const SizedBox.shrink();
    }

    // No `labelStyle` override here either — see `_SourcePicker` above.
    return Wrap(
      spacing: AppDimens.dense,
      runSpacing: AppDimens.dense,
      children: <Widget>[
        for (final metric in metrics)
          FilterChip(
            key: EffectScreen.metricOutcomeChipKey(metric.id),
            label: Text(metric.name),
            selected: selectedOutcomes.contains(
              EffectOutcomeSelection.metric(metric.id),
            ),
            onSelected: (selected) {
              if (selected) {
                controller.addMetricOutcome(metric.id);
              } else {
                controller.removeOutcome(
                  EffectOutcomeSelection.metric(metric.id),
                );
              }
            },
          ),
        FilterChip(
          key: EffectScreen.performanceOutcomeChipKey,
          label: const Text('Performance'),
          selected: selectedOutcomes.contains(
            const EffectOutcomeSelection.performance(),
          ),
          onSelected: (selected) {
            if (selected) {
              controller.addPerformanceOutcome();
            } else {
              controller.removeOutcome(
                const EffectOutcomeSelection.performance(),
              );
            }
          },
        ),
      ],
    );
  }
}

class _EffectResultsBody extends StatelessWidget {
  const _EffectResultsBody({
    required this.computation,
    required this.outcomes,
    required this.metrics,
  });

  final EffectComputation computation;
  final List<EffectOutcomeSelection> outcomes;
  final List<MetricOptionRecord> metrics;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dateFormat = DateFormat.yMMMd();
    final window = computation.window;
    final windowLabel = window.isOngoing
        ? '${dateFormat.format(window.duringStart.toLocal())} – ongoing'
        : '${dateFormat.format(window.duringStart.toLocal())} – '
            '${dateFormat.format(window.duringEnd!.toLocal())}';

    // The confounder note is rendered ONCE per window —
    // never repeated per outcome card — so it reads as framing for the
    // whole result set, not a nag attached to every number.
    final confounderNote = Text(
      key: EffectScreen.confounderNoteKey,
      EffectScreen.confounderNoteText,
      style:
          context.textStyles.caption.copyWith(color: colors.textSecondary),
    );

    if (outcomes.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            key: EffectScreen.windowSummaryKey,
            'During: $windowLabel',
            style: TextStyle(color: colors.textSecondary),
          ),
          const SizedBox(height: AppDimens.dense),
          confounderNote,
          const SizedBox(height: AppDimens.dense),
          Text(
            key: EffectScreen.noOutcomesKey,
            'Pick an outcome above to see its before/during/after values.',
            style: TextStyle(color: colors.textSecondary),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          key: EffectScreen.windowSummaryKey,
          'During: $windowLabel',
          style: TextStyle(color: colors.textSecondary),
        ),
        const SizedBox(height: AppDimens.dense),
        confounderNote,
        const SizedBox(height: AppDimens.base),
        for (final outcome in outcomes)
          Padding(
            padding: const EdgeInsets.only(bottom: AppDimens.base),
            child: _OutcomeResultCard(
              outcome: outcome,
              result: computation.results[outcome],
              samples: computation.samples[outcome] ?? const <EffectSample>[],
              doses: computation.doses,
              doseResponseTable: computation.doseResponseTables[outcome] ??
                  const <DoseResponseRow>[],
              window: window,
              label: _outcomeLabel(outcome, metrics),
            ),
          ),
      ],
    );
  }

  String _outcomeLabel(
    EffectOutcomeSelection outcome,
    List<MetricOptionRecord> metrics,
  ) {
    if (outcome.kind == ProtocolOutcomeKind.performance) {
      return 'Performance (training volume)';
    }
    for (final metric in metrics) {
      if (metric.id == outcome.metricId) {
        return metric.name;
      }
    }
    return 'Metric';
  }
}

class _OutcomeResultCard extends StatelessWidget {
  const _OutcomeResultCard({
    required this.outcome,
    required this.result,
    required this.samples,
    required this.doses,
    required this.doseResponseTable,
    required this.window,
    required this.label,
  });

  final EffectOutcomeSelection outcome;
  final OutcomeEffectResult? result;
  final List<EffectSample> samples;
  final List<DoseRecord> doses;
  final List<DoseResponseRow> doseResponseTable;
  final EffectWindow window;
  final String label;

  String get _outcomeKey =>
      outcome.kind == ProtocolOutcomeKind.performance
          ? 'performance'
          : 'metric-${outcome.metricId}';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final result = this.result;

    return Card(
      key: EffectScreen.resultCardKey(_outcomeKey),
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppDimens.dense),
            if (result == null)
              Text(
                'No data.',
                style: TextStyle(color: colors.textSecondary),
              )
            else ...<Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  _SegmentValue(
                    label: 'Before',
                    stats: result.before,
                    colors: colors,
                  ),
                  _SegmentValue(
                    label: 'During',
                    stats: result.during,
                    colors: colors,
                  ),
                  _SegmentValue(
                    label: 'After',
                    stats: result.after,
                    colors: colors,
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.dense),
              _DeltaRow(label: 'During Δ', delta: result.duringDelta, colors: colors),
              _DeltaRow(label: 'After Δ', delta: result.afterDelta, colors: colors),
              const SizedBox(height: AppDimens.base),
              EffectTimelineChart(
                window: window,
                samples: samples,
                doses: doses,
              ),
              if (doseResponseTable.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppDimens.base),
                _DoseResponseTable(
                  outcomeKey: _outcomeKey,
                  rows: doseResponseTable,
                  colors: colors,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// The dose-response table (PROTOCOLS.md §4): one row per distinct
/// ACTUAL logged `Dose` level — grouped from [DoseResponseRow]s the
/// controller already derived via `computeDoseResponseTable` (NEVER the
/// Schedule/plan, §1.4, load-bearing) — pairing it with the outcome
/// behavior observed at that level over the window. Strictly descriptive:
/// a plain mean + sample/dose count, never colored or framed as
/// good/bad/effective. A level with no attributed samples still lists its
/// dose count with a `—` mean (never fabricated).
class _DoseResponseTable extends StatelessWidget {
  const _DoseResponseTable({
    required this.outcomeKey,
    required this.rows,
    required this.colors,
  });

  final String outcomeKey;
  final List<DoseResponseRow> rows;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Dose response',
          style: TextStyle(
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppDimens.dense),
        for (var index = 0; index < rows.length; index += 1)
          Padding(
            key: EffectScreen.doseResponseRowKey(outcomeKey, index),
            padding: const EdgeInsets.only(bottom: AppDimens.dense / 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${rows[index].compoundName} · '
                    '${rows[index].levelLabel} '
                    '(${rows[index].doseCount} '
                    '${rows[index].doseCount == 1 ? 'dose' : 'doses'})',
                    style: TextStyle(color: colors.textPrimary),
                  ),
                ),
                const SizedBox(width: AppDimens.dense),
                Text(
                  rows[index].stats.mean == null
                      ? '—'
                      : _formatNumber(rows[index].stats.mean!),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: AppDimens.dense / 2),
                Text(
                  '(${rows[index].stats.sampleCount})',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SegmentValue extends StatelessWidget {
  const _SegmentValue({
    required this.label,
    required this.stats,
    required this.colors,
  });

  final String label;
  final EffectSegmentStats stats;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(label, style: TextStyle(color: colors.textSecondary)),
        const SizedBox(height: AppDimens.dense / 3),
        Text(
          stats.mean == null ? '—' : _formatNumber(stats.mean!),
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          '(${stats.sampleCount})',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

class _DeltaRow extends StatelessWidget {
  const _DeltaRow({
    required this.label,
    required this.delta,
    required this.colors,
  });

  final String label;
  final double? delta;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    if (delta == null) {
      return Padding(
        padding: const EdgeInsets.only(top: AppDimens.dense / 3),
        child: Text(
          '$label: —',
          style: TextStyle(color: colors.textSecondary),
        ),
      );
    }
    final icon = delta! < 0 ? Icons.trending_down : Icons.trending_up;
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.dense / 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: colors.textSecondary),
          const SizedBox(width: AppDimens.dense / 3),
          Text(
            '$label: ${_formatNumber(delta!)}',
            style: TextStyle(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

String _formatNumber(double value) {
  final fixed = value.toStringAsFixed(2);
  return fixed
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
