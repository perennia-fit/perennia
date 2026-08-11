import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';

final templatePickerFeatureRepositoryProvider =
    Provider<TemplatePickerFeatureRepository>(
  (ref) => RepositoryTemplatePickerFeatureRepository(
    ref.watch(trainingRepositoriesProvider),
  ),
);

/// Presentation-facing boundary for the picker sheet's Routines and All
/// Templates groups (ROUTINES.md §3.2). The Today/Up next group deliberately
/// has no member here — it reuses `UpNextFeatureRepository`'s existing
/// derived-suggestions stream unchanged (one derivation, never
/// forked). Both streams here already exclude archived Workout Templates;
/// "Archived templates never appear" holds for every group in the sheet.
abstract interface class TemplatePickerFeatureRepository {
  /// Every active Routine with at least one visible (non-archived-template)
  /// entry. A Template referenced by several Routines appears once per
  /// Routine — reference semantics made visible, never deduplicated.
  Stream<List<TemplatePickerRoutineView>> watchRoutines();

  /// Every active Workout Template, for the All Templates group's
  /// search + recency-fallback ordering (applied by the caller).
  Stream<List<TemplatePickerTemplateView>> watchAllTemplates();
}

/// Always-empty [TemplatePickerFeatureRepository], for composing the app
/// root in contexts that stub Home away from a real database (widget
/// tests, the app-shell harness) — mirrors `StubUpNextFeatureRepository`.
class StubTemplatePickerFeatureRepository
    implements TemplatePickerFeatureRepository {
  const StubTemplatePickerFeatureRepository();

  @override
  Stream<List<TemplatePickerRoutineView>> watchRoutines() {
    return Stream<List<TemplatePickerRoutineView>>.value(
      const <TemplatePickerRoutineView>[],
    );
  }

  @override
  Stream<List<TemplatePickerTemplateView>> watchAllTemplates() {
    return Stream<List<TemplatePickerTemplateView>>.value(
      const <TemplatePickerTemplateView>[],
    );
  }
}

class RepositoryTemplatePickerFeatureRepository
    implements TemplatePickerFeatureRepository {
  const RepositoryTemplatePickerFeatureRepository(this._repositories);

  final TrainingRepositories _repositories;

  @override
  Stream<List<TemplatePickerRoutineView>> watchRoutines() {
    return _repositories.routinePlans.watchActiveDetails().map((records) {
      return records
          .map(_routineViewFromRecord)
          .where((routine) => routine.entries.isNotEmpty)
          .toList(growable: false);
    });
  }

  @override
  Stream<List<TemplatePickerTemplateView>> watchAllTemplates() {
    return _repositories.workoutTemplates.watchActiveSummaries().map(
          (records) =>
              records.map(_templateViewFromRecord).toList(growable: false),
        );
  }
}

TemplatePickerRoutineView _routineViewFromRecord(RoutinePlanRecord record) {
  return TemplatePickerRoutineView(
    routineId: record.id,
    routineName: record.name,
    cadenceKind: record.cadence?.kind,
    entries: record.entries
        .where((entry) => !entry.templateIsArchived)
        .map(
          (entry) => TemplatePickerRoutineEntryView(
            routineEntryId: entry.id,
            workoutTemplateId: entry.workoutTemplateId,
            templateName: entry.templateName,
            slot: entry.slot,
          ),
        )
        .toList(growable: false),
  );
}

TemplatePickerTemplateView _templateViewFromRecord(
  WorkoutTemplateSummaryRecord record,
) {
  return TemplatePickerTemplateView(
    id: record.id,
    name: record.name,
    exerciseCount: record.exerciseCount,
    updatedAt: record.updatedAt,
  );
}

/// One active Routine and its visible ordered entries, presentation-ready.
final class TemplatePickerRoutineView {
  TemplatePickerRoutineView({
    required this.routineId,
    required this.routineName,
    required this.cadenceKind,
    required Iterable<TemplatePickerRoutineEntryView> entries,
  }) : entries = List<TemplatePickerRoutineEntryView>.unmodifiable(entries);

  final String routineId;
  final String routineName;

  /// `null` for a cadence-less collection; entries then carry no slot.
  final CadenceKind? cadenceKind;
  final List<TemplatePickerRoutineEntryView> entries;
}

/// One Routine Entry's picker-relevant identity.
final class TemplatePickerRoutineEntryView {
  const TemplatePickerRoutineEntryView({
    required this.routineEntryId,
    required this.workoutTemplateId,
    required this.templateName,
    required this.slot,
  });

  final String routineEntryId;
  final String workoutTemplateId;
  final String templateName;
  final int? slot;
}

/// One active Workout Template, presentation-ready.
final class TemplatePickerTemplateView {
  const TemplatePickerTemplateView({
    required this.id,
    required this.name,
    required this.exerciseCount,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final int exerciseCount;
  final DateTime updatedAt;
}
