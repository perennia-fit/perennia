import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/training/template_picker_search.dart';
import '../repositories/template_picker_feature_repository.dart';

/// The All Templates group's live search text (ROUTINES.md §3.2). Scoped
/// `autoDispose` — the picker sheet is a transient surface, and its search
/// state should not outlive it.
final templatePickerSearchQueryProvider =
    NotifierProvider.autoDispose<TemplatePickerSearchQueryController, String>(
  TemplatePickerSearchQueryController.new,
);

class TemplatePickerSearchQueryController extends Notifier<String> {
  @override
  String build() => '';

  void changed(String value) {
    state = value;
  }
}

/// Every active Routine with its visible entries, for the Routines group.
final templatePickerRoutinesProvider =
    StreamProvider.autoDispose<List<TemplatePickerRoutineView>>((ref) {
  final repository = ref.watch(templatePickerFeatureRepositoryProvider);
  return repository.watchRoutines();
});

final _templatePickerAllTemplatesRawProvider =
    StreamProvider.autoDispose<List<TemplatePickerTemplateView>>((ref) {
  final repository = ref.watch(templatePickerFeatureRepositoryProvider);
  return repository.watchAllTemplates();
});

/// Ids of active Templates with no Template Exercises, unaffected by the
/// search text, so every group in the sheet can label the same Templates
/// "No exercises" from the one stream the sheet already reads.
final templatePickerEmptyTemplateIdsProvider =
    Provider.autoDispose<Set<String>>((ref) {
  final templates = ref.watch(_templatePickerAllTemplatesRawProvider).value ??
      const <TemplatePickerTemplateView>[];
  return {
    for (final template in templates)
      if (template.exerciseCount == 0) template.id,
  };
});

/// The All Templates group's list, filtered by the live search text and
/// ordered by the shared `filterAndSortTemplatesForPicker` derivation
/// (search, recency as the sort fallback — ROUTINES.md §3.2).
final templatePickerFilteredTemplatesProvider =
    Provider.autoDispose<AsyncValue<List<TemplatePickerTemplateView>>>((ref) {
  final query = ref.watch(templatePickerSearchQueryProvider);
  final raw = ref.watch(_templatePickerAllTemplatesRawProvider);
  return raw.whenData((templates) {
    final byId = <String, TemplatePickerTemplateView>{
      for (final template in templates) template.id: template,
    };
    final sorted = filterAndSortTemplatesForPicker(
      templates: templates.map(
        (template) => TemplatePickerTemplateEntry(
          id: template.id,
          name: template.name,
          updatedAt: template.updatedAt,
        ),
      ),
      query: query,
    );
    return sorted.map((entry) => byId[entry.id]!).toList(growable: false);
  });
});
