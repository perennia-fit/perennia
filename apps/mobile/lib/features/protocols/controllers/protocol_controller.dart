import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import 'protocols_day_controller.dart' show protocolsRepositoryProvider;

/// Lightweight active `Metric` options for read paths that only need an id and
/// label, such as Protocol target-outcome and Effect outcome pickers.
final metricOptionListProvider =
    StreamProvider<List<MetricOptionRecord>>((ref) {
  return ref.watch(trainingRepositoriesProvider).metrics.watchMetricOptions();
});

/// The active (non-archived) `Protocol` list (PROTOCOLS.md §1.4): the
/// Routine analog — a named, time-bounded plan grouping one or more Compounds
/// (a stack). Widgets -> this controller -> the repository (the only layer
/// touching Drift).
final protocolListControllerProvider =
    StreamNotifierProvider<ProtocolListController, List<ProtocolSummaryRecord>>(
  ProtocolListController.new,
);

/// The lightweight active `Protocol` options used by Dose logging. This keeps
/// the gym-floor Dose sheet off full Protocol plan-detail streams.
final protocolOptionListProvider =
    StreamProvider<List<ProtocolOptionRecord>>((ref) {
  return ref.watch(protocolsRepositoryProvider).watchProtocolOptions();
});

/// Active `Protocol` options for the Effect source picker: identity plus
/// declared target outcomes, without member/Schedule detail streams.
final protocolEffectOptionListProvider =
    StreamProvider<List<ProtocolEffectOptionRecord>>((ref) {
  return ref.watch(protocolsRepositoryProvider).watchProtocolEffectOptions();
});

/// A scoped `Protocol` detail stream for read paths that already know the
/// selected Protocol id and should not rebuild on unrelated plan changes.
final protocolDetailProvider =
    StreamProvider.autoDispose.family<ProtocolRecord?, String>((ref, id) {
  return ref.watch(protocolsRepositoryProvider).watchProtocol(id);
});

/// A `Protocol` is a MUTABLE PLAN: every write here touches only the
/// Protocol/its membership, never a logged `Dose` (§1.4).
class ProtocolListController
    extends StreamNotifier<List<ProtocolSummaryRecord>> {
  @override
  Stream<List<ProtocolSummaryRecord>> build() {
    return ref.watch(protocolsRepositoryProvider).watchProtocolSummaries();
  }

  /// Creates a named, time-bounded `Protocol` grouping one or more Compounds
  /// (a stack). One reversible Activity Log batch.
  Future<CreateProtocolResult> createProtocol(ProtocolDraft draft) {
    return ref.read(protocolsRepositoryProvider).createProtocol(draft);
  }

  /// Edits a `Protocol`'s name/window and reconciles its membership. Never
  /// reads or writes a logged `Dose` (§1.4).
  Future<String> editProtocol(String protocolId, ProtocolDraft draft) {
    return ref.read(protocolsRepositoryProvider).editProtocol(
          protocolId,
          draft,
        );
  }

  /// Archives a `Protocol` (soft-delete via `deletedAt`): drops from the
  /// active list, history survives, never cascades to a logged `Dose`.
  Future<String> archiveProtocol(String protocolId) {
    return ref.read(protocolsRepositoryProvider).archiveProtocol(protocolId);
  }

  /// Loads one active `Protocol` detail for edit navigation from the summary
  /// list. The list itself stays on summaries; detail is hydrated on demand.
  Future<ProtocolRecord?> loadProtocolDetail(String protocolId) {
    return ref
        .read(protocolsRepositoryProvider)
        .watchProtocol(protocolId)
        .first;
  }
}
