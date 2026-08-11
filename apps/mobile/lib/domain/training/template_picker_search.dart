/// Pure filter + sort for the picker sheet's All Templates group
/// (ROUTINES.md §3.2: "search, recency as the sort fallback").
///
/// There is no ranking algorithm here on purpose: a case-insensitive
/// substring match on the name is the only filter, and the display order —
/// filtered or not — always falls back to recency (most recently updated
/// first). FitNotes' "most recent routine auto-selected" default is
/// superseded by the Cadence-derived Up-next suggestions; this function is
/// the only place recency survives, as a browsing sort order.
library;

/// One Workout Template's picker-relevant identity: what the search filters
/// on, and what the recency fallback sorts by.
final class TemplatePickerTemplateEntry {
  const TemplatePickerTemplateEntry({
    required this.id,
    required this.name,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final DateTime updatedAt;
}

/// Filters [templates] by a case-insensitive substring match of [query]
/// against the name (an empty/blank query matches everything), then sorts
/// by recency descending. Ties break by name, then by id, so the order is
/// fully deterministic for golden-style assertions.
List<TemplatePickerTemplateEntry> filterAndSortTemplatesForPicker({
  required Iterable<TemplatePickerTemplateEntry> templates,
  required String query,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final filtered = normalizedQuery.isEmpty
      ? templates.toList(growable: false)
      : templates
          .where(
            (template) => template.name.toLowerCase().contains(normalizedQuery),
          )
          .toList(growable: false);
  filtered.sort((left, right) {
    final byRecency = right.updatedAt.compareTo(left.updatedAt);
    if (byRecency != 0) {
      return byRecency;
    }
    final byName = left.name.compareTo(right.name);
    if (byName != 0) {
      return byName;
    }
    return left.id.compareTo(right.id);
  });
  return List<TemplatePickerTemplateEntry>.unmodifiable(filtered);
}
