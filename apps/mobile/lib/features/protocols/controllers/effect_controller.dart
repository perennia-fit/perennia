import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import 'protocol_controller.dart' show protocolDetailProvider;

/// The Effect repository provider, mirroring `protocolsRepositoryProvider`.
/// Widgets -> this controller -> the repository (the only layer touching
/// Drift/HTTP). Everything downstream of it is derived analytics, computed
/// fresh on every read and never stored (PROTOCOLS.md §4).
final effectRepositoryProvider = Provider<EffectRepository>((ref) {
  return ref.watch(trainingRepositoriesProvider).effect;
});

// `EffectWindowSource` lives in `training_repositories.dart` now:
// `EffectRepository.doseMarkersFor` needs the type too, and a repository can
// never import a controller (Widgets -> Controllers -> Repositories). It is
// re-exported here so every existing import of it through this controller
// file keeps working unchanged.

/// The user's current `Effect` view picks: which source, and which outcomes
/// to correlate. [outcomes] is SEEDED 1:1 from the Protocol's declared target
/// outcomes when a Protocol is chosen, but is always freely
/// adjustable ad hoc afterward (PROTOCOLS.md §4) — nothing here is ever
/// persisted; it lives only in this in-memory selection.
final class EffectSelection {
  EffectSelection({
    this.source,
    List<EffectOutcomeSelection> outcomes = const <EffectOutcomeSelection>[],
  }) : outcomes = List<EffectOutcomeSelection>.unmodifiable(outcomes);

  final EffectWindowSource? source;
  final List<EffectOutcomeSelection> outcomes;

  EffectSelection copyWith({
    EffectWindowSource? source,
    List<EffectOutcomeSelection>? outcomes,
  }) {
    return EffectSelection(
      source: source ?? this.source,
      outcomes: outcomes ?? this.outcomes,
    );
  }
}

final effectSelectionControllerProvider =
    NotifierProvider<EffectSelectionController, EffectSelection>(
  EffectSelectionController.new,
);

/// Holds the in-memory `Effect` view selection. Never touches
/// storage — picking a source/outcome here computes nothing by itself; it
/// only feeds [effectComputationProvider].
class EffectSelectionController extends Notifier<EffectSelection> {
  @override
  EffectSelection build() => EffectSelection();

  /// Picks a `Protocol` as the window source, seeding the outcome list 1:1
  /// from its declared target outcomes — still freely adjustable
  /// ad hoc afterward (§4).
  void selectProtocol(ProtocolEffectOptionRecord protocol) {
    state = EffectSelection(
      source: EffectWindowSource.protocol(protocol.id),
      outcomes: protocol.targetOutcomes
          .map(EffectOutcomeSelection.fromTargetOutcome)
          .toList(growable: false),
    );
  }

  /// Picks a single `Compound` ad hoc (no `Protocol` tag required, §1.4).
  /// There is no Protocol to seed target outcomes from at this level, so the
  /// outcome list starts empty; the user adds outcomes ad hoc.
  void selectCompound(String compoundId) {
    state = EffectSelection(
      source: EffectWindowSource.compound(compoundId),
      outcomes: const <EffectOutcomeSelection>[],
    );
  }

  /// Adds a `Metric` outcome ad hoc (a no-op if already selected).
  void addMetricOutcome(String metricId) {
    _addOutcome(EffectOutcomeSelection.metric(metricId));
  }

  /// Adds the `performance` outcome ad hoc (a no-op if already selected).
  void addPerformanceOutcome() {
    _addOutcome(const EffectOutcomeSelection.performance());
  }

  void _addOutcome(EffectOutcomeSelection outcome) {
    if (state.outcomes.contains(outcome)) {
      return;
    }
    state = state.copyWith(
      outcomes: <EffectOutcomeSelection>[...state.outcomes, outcome],
    );
  }

  /// Removes an outcome from the ad-hoc selection (including a seeded one —
  /// seeding never locks it in, §4).
  void removeOutcome(EffectOutcomeSelection outcome) {
    state = state.copyWith(
      outcomes: state.outcomes
          .where((each) => each != outcome)
          .toList(growable: false),
    );
  }
}

/// The `Effect` window plus its per-outcome before/during/after results for
/// the current selection — a snapshot of a computation, never a stored
/// entity (PROTOCOLS.md §4).
///
/// [samples] carries each selected outcome's raw (unaggregated) time series —
/// the input [results] was aggregated from — so the dose-overlay timeline
/// can plot the actual points, not just the before/during/after
/// means. [doses] is the ACTUAL logged `Dose` timeline for the window's
/// source (real tz-frozen `Dose.tookAt`, never the Schedule/plan), shared by
/// every outcome's chart since the intake events are the same regardless of
/// which outcome is being read alongside them. [doseResponseTables]
/// is each selected outcome's behavior grouped by the ACTUAL logged Dose
/// level over the window — the same "join, never merge" discipline, derived
/// from [doses] + [samples] and never the Schedule/plan.
final class EffectComputation {
  EffectComputation({
    required this.window,
    required Map<EffectOutcomeSelection, OutcomeEffectResult> results,
    Map<EffectOutcomeSelection, List<EffectSample>> samples =
        const <EffectOutcomeSelection, List<EffectSample>>{},
    List<DoseRecord> doses = const <DoseRecord>[],
    Map<EffectOutcomeSelection, List<DoseResponseRow>> doseResponseTables =
        const <EffectOutcomeSelection, List<DoseResponseRow>>{},
  })  : results = Map<EffectOutcomeSelection, OutcomeEffectResult>.unmodifiable(
          results,
        ),
        samples = _unmodifiableListMap(samples),
        doses = List<DoseRecord>.unmodifiable(doses),
        doseResponseTables = _unmodifiableListMap(doseResponseTables);

  final EffectWindow window;
  final Map<EffectOutcomeSelection, OutcomeEffectResult> results;
  final Map<EffectOutcomeSelection, List<EffectSample>> samples;
  final List<DoseRecord> doses;
  final Map<EffectOutcomeSelection, List<DoseResponseRow>> doseResponseTables;
}

Map<K, List<V>> _unmodifiableListMap<K, V>(Map<K, List<V>> source) {
  return Map<K, List<V>>.unmodifiable({
    for (final entry in source.entries)
      entry.key: List<V>.unmodifiable(entry.value),
  });
}

/// Computes the `Effect` window + every selected outcome's delta ON DEMAND
/// — re-runs from scratch whenever the selection (or the
/// underlying Protocol/Dose/Metric/Workout data) changes. `null` means
/// nothing is picked yet, or a `Compound` window has no logged Dose to derive
/// a window from (PROTOCOLS.md §1.4) — never a fabricated/empty window.
final effectComputationProvider =
    FutureProvider.autoDispose<EffectComputation?>((ref) async {
  final selection = ref.watch(effectSelectionControllerProvider);
  final source = selection.source;
  if (source == null) {
    return null;
  }

  final repository = ref.watch(effectRepositoryProvider);
  final now = DateTime.now();

  EffectWindow? window;
  if (source.isProtocol) {
    final protocol =
        await ref.watch(protocolDetailProvider(source.protocolId!).future);
    if (protocol == null) {
      return null;
    }
    window = repository.windowForProtocol(protocol, now: now);
  } else {
    window = await repository.windowForCompound(source.compoundId!, now: now);
  }
  if (window == null) {
    return null;
  }

  final doses = await repository.doseMarkersFor(source, window);

  final results = <EffectOutcomeSelection, OutcomeEffectResult>{};
  final samples = <EffectOutcomeSelection, List<EffectSample>>{};
  final doseResponseTables = <EffectOutcomeSelection, List<DoseResponseRow>>{};
  for (final outcome in selection.outcomes) {
    final outcomeSamples = await repository.samplesFor(outcome, window);
    samples[outcome] = outcomeSamples;
    results[outcome] = computeOutcomeEffect(
      window: window,
      samples: outcomeSamples,
    );
    // Derived from the SAME `doses`/`outcomeSamples` this loop already read
    // — no extra repository round trip (mirrors `computeOutcome`'s
    // pure-function-fed-by-a-single-read shape).
    doseResponseTables[outcome] = computeDoseResponseTable(
      doses: doses,
      samples: outcomeSamples,
    );
  }
  return EffectComputation(
    window: window,
    results: results,
    samples: samples,
    doses: doses,
    doseResponseTables: doseResponseTables,
  );
});
