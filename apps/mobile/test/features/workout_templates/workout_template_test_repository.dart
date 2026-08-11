import 'dart:async';

import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/workout_templates/repositories/workout_template_feature_repository.dart';

/// Mutable in-memory repository used by Workout Template widget tests.
///
/// Keeping this fake in test code prevents test-only stream controllers and
/// mutation shortcuts from becoming part of the production feature API.
class StubWorkoutTemplateFeatureRepository
    implements WorkoutTemplateFeatureRepository {
  StubWorkoutTemplateFeatureRepository({
    WorkoutTemplateListSnapshot? snapshot,
    Map<String, WorkoutTemplateDetail> details =
        const <String, WorkoutTemplateDetail>{},
  })  : _snapshot = snapshot ?? WorkoutTemplateListSnapshot.empty,
        _details = Map<String, WorkoutTemplateDetail>.of(details);

  WorkoutTemplateListSnapshot _snapshot;
  final Map<String, WorkoutTemplateDetail> _details;
  final StreamController<WorkoutTemplateListSnapshot> _listController =
      StreamController<WorkoutTemplateListSnapshot>.broadcast();
  final Map<String, StreamController<WorkoutTemplateDetail?>>
      _detailControllers = <String, StreamController<WorkoutTemplateDetail?>>{};

  Future<void> close() async {
    await _listController.close();
    await Future.wait(
      _detailControllers.values.map((controller) => controller.close()),
    );
  }

  @override
  Stream<WorkoutTemplateListSnapshot> watchTemplates() async* {
    yield _snapshot;
    yield* _listController.stream;
  }

  @override
  Stream<WorkoutTemplateDetail?> watchTemplate(String templateId) async* {
    yield _details[templateId];
    yield* (_detailControllers[templateId] ??=
            StreamController<WorkoutTemplateDetail?>.broadcast())
        .stream;
  }

  @override
  Future<String> createTemplate({
    required String name,
    String? notes,
  }) async {
    final id = 'template-${_details.length + 1}';
    final detail = WorkoutTemplateDetail(
      id: id,
      name: name,
      notes: notes,
      exercises: const <TemplateExerciseDetail>[],
    );
    _details[id] = detail;
    _snapshot = WorkoutTemplateListSnapshot(
      active: <WorkoutTemplateSummary>[
        ..._snapshot.active,
        WorkoutTemplateSummary(
          id: id,
          name: name,
          notes: notes,
          exerciseCount: 0,
          isArchived: false,
        ),
      ],
      archived: _snapshot.archived,
    );
    _emitList();
    _emitDetail(id);
    return id;
  }

  @override
  Future<void> updateTemplate({
    required String templateId,
    required String name,
    String? notes,
  }) async {
    final current = _details[templateId];
    if (current == null) {
      return;
    }
    _details[templateId] = current.copyWith(name: name, notes: () => notes);
    _snapshot = _snapshot.mapSummary(
      templateId,
      (summary) => summary.copyWith(name: name, notes: () => notes),
    );
    _emitList();
    _emitDetail(templateId);
  }

  @override
  Future<void> archiveTemplate(String templateId) async {
    final summary = _snapshot.active
        .where((candidate) => candidate.id == templateId)
        .firstOrNull;
    if (summary == null) {
      return;
    }
    _snapshot = WorkoutTemplateListSnapshot(
      active: _snapshot.active
          .where((candidate) => candidate.id != templateId)
          .toList(growable: false),
      archived: <WorkoutTemplateSummary>[
        ..._snapshot.archived,
        summary.copyWith(isArchived: true),
      ],
    );
    _emitList();
  }

  @override
  Future<void> restoreTemplate(String templateId) async {
    final summary = _snapshot.archived
        .where((candidate) => candidate.id == templateId)
        .firstOrNull;
    if (summary == null) {
      return;
    }
    _snapshot = WorkoutTemplateListSnapshot(
      active: <WorkoutTemplateSummary>[
        ..._snapshot.active,
        summary.copyWith(isArchived: false),
      ],
      archived: _snapshot.archived
          .where((candidate) => candidate.id != templateId)
          .toList(growable: false),
    );
    _emitList();
  }

  @override
  Future<String> addExercise({
    required String templateId,
    required String exerciseId,
    String? notes,
  }) async {
    final current = _details[templateId];
    if (current == null) {
      throw StateError('Unknown Workout Template: $templateId');
    }
    final id = 'template-exercise-${current.exercises.length + 1}';
    _details[templateId] = current.copyWith(
      exercises: <TemplateExerciseDetail>[
        ...current.exercises,
        TemplateExerciseDetail(
          id: id,
          exerciseId: exerciseId,
          name: exerciseId,
          type: ExerciseType.empty,
          defaultLoadUnit: TrainingUnit.kilogram,
          loadMode: ExerciseLoadMode.added,
          notes: notes,
          prescriptions: const <PrescriptionDetail>[],
        ),
      ],
    );
    _snapshot = _snapshot.mapSummary(
      templateId,
      (summary) => summary.copyWith(
        exerciseCount: current.exercises.length + 1,
      ),
    );
    _emitList();
    _emitDetail(templateId);
    return id;
  }

  @override
  Future<void> updateExerciseNotes({
    required String templateExerciseId,
    String? notes,
  }) async {
    _updateExercise(
      templateExerciseId,
      (exercise) => exercise.copyWith(notes: () => notes),
    );
  }

  @override
  Future<void> removeExercise(String templateExerciseId) async {
    for (final entry in _details.entries.toList(growable: false)) {
      if (!entry.value.exercises
          .any((exercise) => exercise.id == templateExerciseId)) {
        continue;
      }
      _details[entry.key] = entry.value.copyWith(
        exercises: entry.value.exercises
            .where((exercise) => exercise.id != templateExerciseId)
            .toList(growable: false),
      );
      _snapshot = _snapshot.mapSummary(
        entry.key,
        (summary) => summary.copyWith(
          exerciseCount: _details[entry.key]!.exercises.length,
        ),
      );
      _emitList();
      _emitDetail(entry.key);
      return;
    }
  }

  @override
  Future<void> reorderExercises({
    required String templateId,
    required List<String> orderedIds,
  }) async {
    final current = _details[templateId];
    if (current == null) {
      return;
    }
    final byId = <String, TemplateExerciseDetail>{
      for (final exercise in current.exercises) exercise.id: exercise,
    };
    _details[templateId] = current.copyWith(
      exercises: <TemplateExerciseDetail>[
        for (final id in orderedIds)
          if (byId[id] != null) byId[id]!,
      ],
    );
    _emitDetail(templateId);
  }

  @override
  Future<String> addPrescription({
    required String templateExerciseId,
    required PrescriptionInput input,
  }) async {
    final id = 'prescription-${DateTime.now().microsecondsSinceEpoch}';
    _updateExercise(
      templateExerciseId,
      (exercise) => exercise.copyWith(
        prescriptions: <PrescriptionDetail>[
          ...exercise.prescriptions,
          PrescriptionDetail.fromInput(id: id, input: input),
        ],
      ),
    );
    return id;
  }

  @override
  Future<void> updatePrescription({
    required String prescriptionId,
    required PrescriptionInput input,
  }) async {
    _updatePrescription(
      prescriptionId,
      (_) => PrescriptionDetail.fromInput(id: prescriptionId, input: input),
    );
  }

  @override
  Future<void> removePrescription(String prescriptionId) async {
    for (final template in _details.entries.toList(growable: false)) {
      for (final exercise in template.value.exercises) {
        if (!exercise.prescriptions
            .any((prescription) => prescription.id == prescriptionId)) {
          continue;
        }
        _updateExercise(
          exercise.id,
          (value) => value.copyWith(
            prescriptions: value.prescriptions
                .where((prescription) => prescription.id != prescriptionId)
                .toList(growable: false),
          ),
        );
        return;
      }
    }
  }

  @override
  Future<void> reorderPrescriptions({
    required String templateExerciseId,
    required List<String> orderedIds,
  }) async {
    _updateExercise(
      templateExerciseId,
      (exercise) {
        final byId = <String, PrescriptionDetail>{
          for (final prescription in exercise.prescriptions)
            prescription.id: prescription,
        };
        return exercise.copyWith(
          prescriptions: <PrescriptionDetail>[
            for (final id in orderedIds)
              if (byId[id] != null) byId[id]!,
          ],
        );
      },
    );
  }

  @override
  Future<String> createTemplateGroup({
    required String templateId,
    required TemplateGroupInput input,
  }) async {
    final current = _details[templateId];
    if (current == null) {
      throw StateError('Unknown Workout Template: $templateId');
    }
    final groupId = 'template-group-${current.groups.length + 1}';
    _details[templateId] = current.copyWith(
      groups: <TemplateGroupDetail>[
        ...current.groups,
        _groupFromInput(groupId, input),
      ],
    );
    _emitDetail(templateId);
    return groupId;
  }

  @override
  Future<void> updateTemplateGroup({
    required String groupId,
    required TemplateGroupInput input,
  }) async {
    _updateTemplateGroup(
      groupId,
      (group) => _groupFromInput(group.id, input),
    );
  }

  @override
  Future<void> reorderTemplateGroups({
    required String templateId,
    required List<String> orderedIds,
  }) async {
    final current = _details[templateId];
    if (current == null) {
      return;
    }
    final byId = <String, TemplateGroupDetail>{
      for (final group in current.groups) group.id: group,
    };
    _details[templateId] = current.copyWith(
      groups: <TemplateGroupDetail>[
        for (final id in orderedIds)
          if (byId[id] != null) byId[id]!,
      ],
    );
    _emitDetail(templateId);
  }

  @override
  Future<void> dissolveTemplateGroup(String groupId) async {
    for (final entry in _details.entries.toList(growable: false)) {
      if (!entry.value.groups.any((group) => group.id == groupId)) {
        continue;
      }
      _details[entry.key] = entry.value.copyWith(
        groups: entry.value.groups
            .where((group) => group.id != groupId)
            .toList(growable: false),
      );
      _emitDetail(entry.key);
      return;
    }
  }

  void _updateExercise(
    String templateExerciseId,
    TemplateExerciseDetail Function(TemplateExerciseDetail) update,
  ) {
    for (final entry in _details.entries.toList(growable: false)) {
      final index = entry.value.exercises
          .indexWhere((exercise) => exercise.id == templateExerciseId);
      if (index < 0) {
        continue;
      }
      final exercises = List<TemplateExerciseDetail>.of(entry.value.exercises);
      exercises[index] = update(exercises[index]);
      _details[entry.key] = entry.value.copyWith(exercises: exercises);
      _emitDetail(entry.key);
      return;
    }
  }

  void _updatePrescription(
    String prescriptionId,
    PrescriptionDetail Function(PrescriptionDetail) update,
  ) {
    for (final template in _details.entries.toList(growable: false)) {
      for (final exercise in template.value.exercises) {
        final index = exercise.prescriptions.indexWhere(
          (prescription) => prescription.id == prescriptionId,
        );
        if (index < 0) {
          continue;
        }
        _updateExercise(exercise.id, (value) {
          final prescriptions = List<PrescriptionDetail>.of(
            value.prescriptions,
          );
          prescriptions[index] = update(prescriptions[index]);
          return value.copyWith(prescriptions: prescriptions);
        });
        return;
      }
    }
  }

  void _updateTemplateGroup(
    String groupId,
    TemplateGroupDetail Function(TemplateGroupDetail) update,
  ) {
    for (final entry in _details.entries.toList(growable: false)) {
      final index =
          entry.value.groups.indexWhere((group) => group.id == groupId);
      if (index < 0) {
        continue;
      }
      final groups = List<TemplateGroupDetail>.of(entry.value.groups);
      groups[index] = update(groups[index]);
      _details[entry.key] = entry.value.copyWith(groups: groups);
      _emitDetail(entry.key);
      return;
    }
  }

  void _emitList() => _listController.add(_snapshot);

  void _emitDetail(String templateId) {
    _detailControllers[templateId]?.add(_details[templateId]);
  }
}

TemplateGroupDetail _groupFromInput(String id, TemplateGroupInput input) {
  return TemplateGroupDetail(
    id: id,
    name: input.name,
    colorHex: input.colorHex,
    rounds: input.rounds,
    members: input.orderedTemplateExerciseIds
        .map(
          (templateExerciseId) => TemplateGroupMemberDetail(
            templateExerciseId: templateExerciseId,
          ),
        )
        .toList(growable: false),
  );
}
