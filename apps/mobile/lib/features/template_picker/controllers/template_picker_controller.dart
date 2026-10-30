import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/training/template_picker_search.dart';
import '../repositories/template_picker_feature_repository.dart';

/// Every active Routine with its visible entries, one row each in the
/// Routines sheet.
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

/// Template Exercise count per active Workout Template, so every row in the
/// sheet can say "6 exercises" or "No exercises" from the one stream it
/// already reads.
final templatePickerExerciseCountsProvider =
    Provider.autoDispose<Map<String, int>>((ref) {
  final templates = ref.watch(_templatePickerAllTemplatesRawProvider).value ??
      const <TemplatePickerTemplateView>[];
  return {
    for (final template in templates) template.id: template.exerciseCount,
  };
});

/// Active Workout Templates no shown Routine references: the sheet's
/// "Other saved workouts". A Template inside a Routine is reached through
/// that Routine, so listing it here too would only repeat it. Most recently
/// updated first, by the shared `filterAndSortTemplatesForPicker` order.
final templatePickerOtherTemplatesProvider =
    Provider.autoDispose<AsyncValue<List<TemplatePickerTemplateView>>>((ref) {
  final routines = ref.watch(templatePickerRoutinesProvider);
  final raw = ref.watch(_templatePickerAllTemplatesRawProvider);
  if (!routines.hasValue) {
    return const AsyncLoading<List<TemplatePickerTemplateView>>();
  }
  final inRoutines = {
    for (final routine in routines.requireValue)
      for (final entry in routine.entries) entry.workoutTemplateId,
  };
  return raw.whenData((templates) {
    final byId = <String, TemplatePickerTemplateView>{
      for (final template in templates)
        if (!inRoutines.contains(template.id)) template.id: template,
    };
    final sorted = filterAndSortTemplatesForPicker(
      templates: byId.values.map(
        (template) => TemplatePickerTemplateEntry(
          id: template.id,
          name: template.name,
          updatedAt: template.updatedAt,
        ),
      ),
      query: '',
    );
    return sorted.map((entry) => byId[entry.id]!).toList(growable: false);
  });
});
