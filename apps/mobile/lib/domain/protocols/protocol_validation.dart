/// Structural validation for authoring a Protocol: name, Compound
/// membership, and target outcomes. Its bounds and Period are judged by the
/// shared plan validator, `validateProtocolPeriod` in
/// `protocol_plan_validation.dart`.
///
/// Every check hard-rejects with an [ArgumentError]. This is separate from the
/// shared two-tier Dose validator, which guards logged amounts.
library;

import 'protocols.dart';

/// Hard-rejects an empty/blank name (structural validation — not the shared
/// Dose two-tier validator, which guards logging amounts).
String validateProtocolName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(name, 'name', 'Protocol name is empty.');
  }
  return trimmed;
}

/// Hard-rejects an empty or duplicated membership list. A Protocol
/// associates ONE OR MORE Compounds; a repeated
/// Compound id is never a meaningful stack member.
List<String> validateProtocolMembership(List<String> compoundIds) {
  if (compoundIds.isEmpty) {
    throw ArgumentError.value(
      compoundIds,
      'compoundIds',
      'A Protocol requires at least one Compound.',
    );
  }
  final uniqueIds = compoundIds.toSet();
  if (uniqueIds.length != compoundIds.length) {
    throw ArgumentError.value(
      compoundIds,
      'compoundIds',
      'A Protocol cannot list the same Compound twice.',
    );
  }
  return compoundIds;
}

/// Hard-rejects a malformed or duplicated target-outcome list: a
/// `metric` outcome requires a non-blank [ProtocolTargetOutcomeDraft.metricId],
/// and no two outcomes may declare the SAME thing twice (the same Metric
/// twice, or `performance` twice). An EMPTY list is always valid — a
/// Protocol MAY declare target outcomes, never must.
List<ProtocolTargetOutcomeDraft> validateProtocolTargetOutcomes(
  List<ProtocolTargetOutcomeDraft> outcomes,
) {
  final seenKeys = <String>{};
  for (final outcome in outcomes) {
    if (outcome.kind == ProtocolOutcomeKind.metric) {
      final metricId = outcome.metricId?.trim() ?? '';
      if (metricId.isEmpty) {
        throw ArgumentError.value(
          outcome.metricId,
          'metricId',
          'A metric target outcome requires a Metric id.',
        );
      }
    }
    final key = protocolTargetOutcomeKey(outcome.kind.name, outcome.metricId);
    if (!seenKeys.add(key)) {
      throw ArgumentError.value(
        outcomes,
        'targetOutcomes',
        'A Protocol cannot declare the same target outcome twice.',
      );
    }
  }
  return outcomes;
}

/// The identity key for ONE target outcome (kind + Metric id):
/// what the repository diffs existing rows against when it replaces a
/// Protocol's target outcomes, and what [validateProtocolTargetOutcomes]
/// uses to reject a duplicate.
String protocolTargetOutcomeKey(String kindName, String? metricId) {
  return '$kindName|${metricId ?? ''}';
}
