import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';

final routinePlanFeatureRepositoryProvider =
    Provider<RoutinePlanFeatureRepository>(
  (ref) => RepositoryRoutinePlanFeatureRepository(
    ref.watch(trainingRepositoriesProvider),
  ),
);

/// Presentation-facing boundary for authored Routines and their ordered
/// Workout Template references.
abstract interface class RoutinePlanFeatureRepository {
  Stream<RoutinePlanListSnapshot> watchRoutines();

  Stream<RoutinePlanDetail?> watchRoutine(String routineId);

  Stream<List<RoutineWorkoutTemplateOption>> watchAvailableTemplates();

  Future<String> createRoutine({required String name, String? notes});

  Future<void> updateRoutine({
    required String routineId,
    required String name,
    String? notes,
  });

  Future<void> archiveRoutine(String routineId);

  Future<void> restoreRoutine(String routineId);

  Future<String> addTemplateReference({
    required String routineId,
    required String workoutTemplateId,
    int? slot,
  });

  Future<void> removeTemplateReference(String routineEntryId);

  Future<void> reorderTemplateReferences({
    required String routineId,
    required List<String> orderedEntryIds,
  });

  Future<void> setCadence({
    required String routineId,
    required Cadence? cadence,
  });

  Future<void> moveTemplateReferenceToSlot({
    required String routineEntryId,
    required int slot,
  });

  Future<void> replaceCadenceLayout({
    required String routineId,
    required List<RoutineEntryPlacement> placements,
  });

  Future<void> restoreReferencedTemplate(String workoutTemplateId);
}

class RepositoryRoutinePlanFeatureRepository
    implements RoutinePlanFeatureRepository {
  const RepositoryRoutinePlanFeatureRepository(this._repositories);

  final TrainingRepositories _repositories;

  @override
  Stream<RoutinePlanListSnapshot> watchRoutines() {
    return _repositories.routinePlans.watchAllSummaries().map((records) {
      return RoutinePlanListSnapshot(
        active: records
            .where((record) => !record.isArchived)
            .map(_routinePlanSummaryFromRecord)
            .toList(growable: false),
        archived: records
            .where((record) => record.isArchived)
            .map(_routinePlanSummaryFromRecord)
            .toList(growable: false),
      );
    });
  }

  @override
  Stream<RoutinePlanDetail?> watchRoutine(String routineId) {
    return _repositories.routinePlans.watchById(routineId).map(
          (record) =>
              record == null ? null : _routinePlanDetailFromRecord(record),
        );
  }

  @override
  Stream<List<RoutineWorkoutTemplateOption>> watchAvailableTemplates() {
    return _repositories.workoutTemplates.watchActiveSummaries().map(
          (records) => records
              .map(
                (record) => RoutineWorkoutTemplateOption(
                  id: record.id,
                  name: record.name,
                  notes: record.notes,
                  exerciseCount: record.exerciseCount,
                ),
              )
              .toList(growable: false),
        );
  }

  @override
  Future<String> createRoutine({required String name, String? notes}) {
    return _repositories.routinePlans.create(
      RoutinePlanDraft(name: name, notes: notes),
    );
  }

  @override
  Future<void> updateRoutine({
    required String routineId,
    required String name,
    String? notes,
  }) {
    return _repositories.routinePlans.updateRoutine(
      routineId,
      name: name,
      notes: notes,
    );
  }

  @override
  Future<void> archiveRoutine(String routineId) {
    return _repositories.routinePlans.archive(routineId);
  }

  @override
  Future<void> restoreRoutine(String routineId) {
    return _repositories.routinePlans.restore(routineId);
  }

  @override
  Future<String> addTemplateReference({
    required String routineId,
    required String workoutTemplateId,
    int? slot,
  }) {
    return _repositories.routinePlans.addTemplateReference(
      routineId,
      workoutTemplateId,
      slot: slot,
    );
  }

  @override
  Future<void> removeTemplateReference(String routineEntryId) {
    return _repositories.routinePlans.removeTemplateReference(routineEntryId);
  }

  @override
  Future<void> reorderTemplateReferences({
    required String routineId,
    required List<String> orderedEntryIds,
  }) {
    return _repositories.routinePlans.reorderTemplateReferences(
      routineId,
      orderedEntryIds,
    );
  }

  @override
  Future<void> setCadence({
    required String routineId,
    required Cadence? cadence,
  }) async {
    await _repositories.routinePlans.setCadence(
      routineId,
      cadence,
    );
  }

  @override
  Future<void> moveTemplateReferenceToSlot({
    required String routineEntryId,
    required int slot,
  }) {
    return _repositories.routinePlans.moveTemplateReferenceToSlot(
      routineEntryId,
      slot,
    );
  }

  @override
  Future<void> replaceCadenceLayout({
    required String routineId,
    required List<RoutineEntryPlacement> placements,
  }) {
    return _repositories.routinePlans.replaceCadenceLayout(
      routineId,
      placements
          .map(
            (placement) => RoutineEntrySlotPlacement(
              entryId: placement.entryId,
              slot: placement.slot,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<void> restoreReferencedTemplate(String workoutTemplateId) {
    return _repositories.workoutTemplates.restore(workoutTemplateId);
  }
}

final class RoutinePlanListSnapshot {
  RoutinePlanListSnapshot({
    required List<RoutinePlanSummary> active,
    required List<RoutinePlanSummary> archived,
  })  : active = List<RoutinePlanSummary>.unmodifiable(active),
        archived = List<RoutinePlanSummary>.unmodifiable(archived);

  static final empty = RoutinePlanListSnapshot(
    active: const <RoutinePlanSummary>[],
    archived: const <RoutinePlanSummary>[],
  );

  final List<RoutinePlanSummary> active;
  final List<RoutinePlanSummary> archived;
}

final class RoutinePlanSummary {
  const RoutinePlanSummary({
    required this.id,
    required this.name,
    required this.entryCount,
    required this.archivedTemplateCount,
    required this.isArchived,
    this.cadence,
    this.notes,
  });

  final String id;
  final String name;
  final String? notes;
  final int entryCount;
  final int archivedTemplateCount;
  final bool isArchived;
  final Cadence? cadence;
}

final class RoutinePlanDetail {
  RoutinePlanDetail({
    required this.id,
    required this.name,
    required this.isArchived,
    required List<RoutineEntryDetail> entries,
    this.cadence,
    this.notes,
  }) : entries = List<RoutineEntryDetail>.unmodifiable(entries);

  final String id;
  final String name;
  final String? notes;
  final bool isArchived;
  final Cadence? cadence;
  final List<RoutineEntryDetail> entries;
}

final class RoutineEntryDetail {
  const RoutineEntryDetail({
    required this.id,
    required this.routineId,
    required this.workoutTemplateId,
    required this.position,
    required this.templateName,
    required this.templateIsArchived,
    this.slot,
    this.templateNotes,
  });

  final String id;
  final String routineId;
  final String workoutTemplateId;
  final int position;
  final int? slot;
  final String templateName;
  final String? templateNotes;
  final bool templateIsArchived;
}

final class RoutineEntryPlacement {
  const RoutineEntryPlacement({required this.entryId, required this.slot});

  final String entryId;
  final int slot;
}

final class RoutineWorkoutTemplateOption {
  const RoutineWorkoutTemplateOption({
    required this.id,
    required this.name,
    required this.exerciseCount,
    this.notes,
  });

  final String id;
  final String name;
  final String? notes;
  final int exerciseCount;
}

RoutinePlanSummary _routinePlanSummaryFromRecord(
  RoutinePlanSummaryRecord record,
) {
  return RoutinePlanSummary(
    id: record.id,
    name: record.name,
    notes: record.notes,
    entryCount: record.entryCount,
    archivedTemplateCount: record.archivedTemplateCount,
    isArchived: record.isArchived,
    cadence: record.cadence,
  );
}

RoutinePlanDetail _routinePlanDetailFromRecord(RoutinePlanRecord record) {
  return RoutinePlanDetail(
    id: record.id,
    name: record.name,
    notes: record.notes,
    isArchived: record.isArchived,
    cadence: record.cadence,
    entries: record.entries
        .map(
          (entry) => RoutineEntryDetail(
            id: entry.id,
            routineId: entry.routineId,
            workoutTemplateId: entry.workoutTemplateId,
            position: entry.position,
            slot: entry.slot,
            templateName: entry.templateName,
            templateNotes: entry.templateNotes,
            templateIsArchived: entry.templateIsArchived,
          ),
        )
        .toList(growable: false),
  );
}
