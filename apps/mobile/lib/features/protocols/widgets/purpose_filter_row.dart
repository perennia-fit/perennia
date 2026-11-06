import 'package:flutter/material.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../focus/widgets/focus_visuals.dart';

/// Whether a Compound shows under the Compound list's and the Compound picker's
/// search and Purpose filter. [lowerQuery] and [lowerName] are already
/// lowercased, and [lowerPurposeNames] maps each active Purpose's id to its
/// lowercased name.
///
/// Search matches the name or any active Purpose's name, and [filterId] picks
/// one Purpose. An id that isn't an active Purpose names nothing: it stays on the
/// Compound, so it still satisfies a filter on that id, but it isn't searched.
/// This never matches a substance type or legality field, which the model never
/// carries.
bool compoundMatchesFilter({
  required String lowerName,
  required Iterable<String> purposeIds,
  required Map<String, String> lowerPurposeNames,
  required String lowerQuery,
  required String? filterId,
}) {
  if (filterId != null && !purposeIds.contains(filterId)) {
    return false;
  }
  return lowerQuery.isEmpty ||
      lowerName.contains(lowerQuery) ||
      purposeIds
          .any((id) => lowerPurposeNames[id]?.contains(lowerQuery) ?? false);
}

/// What the Compound list and the Compound picker say when
/// [compoundMatchesFilter] leaves nothing to show. A search says so first, then
/// a filter, and with neither the library itself is empty.
String compoundFilterEmptyMessage(
  AppLocalizations l10n, {
  required bool hasQuery,
  required bool hasFilter,
}) {
  if (hasQuery) {
    return l10n.compoundListNoMatches;
  }
  return hasFilter ? l10n.purposeFilterEmpty : l10n.compoundListEmpty;
}

/// The Compound list's and the Compound picker's Purpose filter: **All**, then
/// each active Purpose in [purposes]' order, one active at a time, scrolling
/// sideways. Callers omit the row when there are no active Purposes, because
/// they also drop its spacing.
///
/// A chip's label is the Purpose's name and nothing else. Reading "Sleep" next
/// to a Compound says the user tagged it; a verb beside the name would read as
/// a claim that the Compound does something (docs/designs/compound-purposes.md,
/// the neutral-instrument rule).
class PurposeFilterRow extends StatelessWidget {
  const PurposeFilterRow({
    super.key,
    required this.purposes,
    required this.selectedId,
    required this.onSelected,
  });

  final List<PurposeRecord> purposes;

  /// The active filter, or null for All.
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  static const rowKey = Key('protocols.purposeFilter');

  /// The chip for the Purpose [id], or All when [id] is null.
  static Key optionKey(String? id) =>
      Key('protocols.purposeFilter.option.${id ?? 'all'}');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      key: rowKey,
      label: l10n.purposeFilterLabel,
      container: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FocusChip(
              key: optionKey(null),
              label: l10n.purposeFilterAll,
              icon: null,
              selected: selectedId == null,
              onSelected: (_) => onSelected(null),
            ),
            for (final purpose in purposes) ...[
              const SizedBox(width: AppDimens.dense / 2),
              FocusChip(
                key: optionKey(purpose.id),
                label: purpose.name,
                icon: null,
                selected: selectedId == purpose.id,
                onSelected: (_) => onSelected(purpose.id),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
