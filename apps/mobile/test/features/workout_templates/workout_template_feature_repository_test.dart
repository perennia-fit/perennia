import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/workout_templates/repositories/workout_template_feature_repository.dart';

void main() {
  test('lifecycle stream always emits an atomic active/archived partition',
      () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repositories = TrainingRepositories(database);
    final adapter = RepositoryWorkoutTemplateFeatureRepository(repositories);
    final templateId = await adapter.createTemplate(name: 'Atomic lifecycle');
    final observed = <WorkoutTemplateListSnapshot>[];
    final initial = Completer<void>();
    final archived = Completer<void>();
    final restored = Completer<void>();
    var waitingForArchive = false;
    var waitingForRestore = false;
    final subscription = adapter.watchTemplates().listen((snapshot) {
      observed.add(snapshot);
      if (!initial.isCompleted &&
          snapshot.active.any((item) => item.id == templateId)) {
        initial.complete();
      }
      if (waitingForArchive &&
          !archived.isCompleted &&
          snapshot.archived.any((item) => item.id == templateId)) {
        archived.complete();
      }
      if (waitingForRestore &&
          !restored.isCompleted &&
          snapshot.active.any((item) => item.id == templateId)) {
        restored.complete();
      }
    });
    addTearDown(subscription.cancel);

    await initial.future;
    final transitionStart = observed.length;
    waitingForArchive = true;
    await adapter.archiveTemplate(templateId);
    await archived.future;
    waitingForRestore = true;
    await adapter.restoreTemplate(templateId);
    await restored.future;

    for (final snapshot in observed.skip(transitionStart)) {
      final appearances =
          snapshot.active.where((item) => item.id == templateId).length +
              snapshot.archived.where((item) => item.id == templateId).length;
      expect(appearances, 1);
    }
  });

  test('adapter maps the reactive plan tree and archived lifecycle', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repositories = TrainingRepositories(database);
    final adapter = RepositoryWorkoutTemplateFeatureRepository(repositories);
    final exerciseId = await repositories.exercises.create(
      ExerciseDraft(
        name: 'Assisted Pull-up',
        type: ExerciseType(
          const <DimensionId>[DimensionId.load, DimensionId.reps],
        ),
        defaultLoadUnit: TrainingUnit.kilogram,
        loadMode: ExerciseLoadMode.assisted,
      ),
    );

    final templateId = await adapter.createTemplate(
      name: 'Pull A',
      notes: 'Wide neutral handles',
    );
    final entryId = await adapter.addExercise(
      templateId: templateId,
      exerciseId: exerciseId,
      notes: 'Control the eccentric',
    );
    final prescriptionId = await adapter.addPrescription(
      templateExerciseId: entryId,
      input: PrescriptionInput(
        mode: TemplatePrescriptionMode.fixed,
        repeat: 3,
        restAfter: const Duration(seconds: 90),
        values: LoggedSet.fromValues(
          const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.load,
              entered: '20',
              unit: TrainingUnit.kilogram,
            ),
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '8',
              unit: TrainingUnit.repetition,
            ),
          ],
        ),
      ),
    );

    final activeSnapshot = await adapter.watchTemplates().firstWhere(
          (snapshot) => snapshot.active.any(
            (template) =>
                template.id == templateId && template.exerciseCount == 1,
          ),
        );
    expect(activeSnapshot.archived, isEmpty);
    expect(activeSnapshot.active.single.name, 'Pull A');

    final detail = await adapter.watchTemplate(templateId).firstWhere(
          (template) =>
              template != null &&
              template.exercises.single.prescriptions.isNotEmpty,
        );
    expect(detail?.notes, 'Wide neutral handles');
    expect(detail?.exercises.single.name, 'Assisted Pull-up');
    expect(detail?.exercises.single.loadMode, ExerciseLoadMode.assisted);
    expect(detail?.exercises.single.notes, 'Control the eccentric');
    expect(detail?.exercises.single.prescriptions.single.id, prescriptionId);
    expect(
      detail?.exercises.single.prescriptions.single.values.load?.entered,
      '20',
    );

    await repositories.exercises.softDelete(exerciseId);
    final detailWithArchivedExercise =
        await adapter.watchTemplate(templateId).firstWhere(
              (template) =>
                  template?.exercises.single.name == 'Assisted Pull-up',
            );
    expect(
        detailWithArchivedExercise?.exercises.single.name, 'Assisted Pull-up');

    await adapter.archiveTemplate(templateId);
    final archivedSnapshot = await adapter.watchTemplates().firstWhere(
          (snapshot) => snapshot.archived.any(
            (template) => template.id == templateId,
          ),
        );
    expect(
      archivedSnapshot.active.any((template) => template.id == templateId),
      isFalse,
    );
    expect(archivedSnapshot.archived.single.isArchived, isTrue);

    await adapter.restoreTemplate(templateId);
    final restoredSnapshot = await adapter.watchTemplates().firstWhere(
          (snapshot) => snapshot.active.any(
            (template) => template.id == templateId,
          ),
        );
    expect(restoredSnapshot.active.single.isArchived, isFalse);
  });

  test('adapter forwards notes, ordering, modes, and Prescription edits',
      () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repositories = TrainingRepositories(database);
    final adapter = RepositoryWorkoutTemplateFeatureRepository(repositories);
    final type = ExerciseType(const <DimensionId>[DimensionId.reps]);
    final firstExerciseId = await repositories.exercises.create(
      ExerciseDraft(name: 'Push-up', type: type),
    );
    final secondExerciseId = await repositories.exercises.create(
      ExerciseDraft(name: 'Dip', type: type),
    );
    final templateId = await adapter.createTemplate(name: 'Bodyweight Push');
    final firstEntryId = await adapter.addExercise(
      templateId: templateId,
      exerciseId: firstExerciseId,
    );
    final secondEntryId = await adapter.addExercise(
      templateId: templateId,
      exerciseId: secondExerciseId,
    );

    await adapter.reorderExercises(
      templateId: templateId,
      orderedIds: <String>[secondEntryId, firstEntryId],
    );
    await adapter.updateExerciseNotes(
      templateExerciseId: secondEntryId,
      notes: 'Rings if available',
    );
    final copyPreviousId = await adapter.addPrescription(
      templateExerciseId: secondEntryId,
      input: PrescriptionInput(
        mode: TemplatePrescriptionMode.copyPrevious,
        repeat: 4,
        values: LoggedSet.completion(),
      ),
    );
    final fixedId = await adapter.addPrescription(
      templateExerciseId: secondEntryId,
      input: PrescriptionInput(
        mode: TemplatePrescriptionMode.fixed,
        repeat: 2,
        values: LoggedSet.fromValues(
          const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '10',
              unit: TrainingUnit.repetition,
            ),
          ],
        ),
      ),
    );
    await adapter.reorderPrescriptions(
      templateExerciseId: secondEntryId,
      orderedIds: <String>[fixedId, copyPreviousId],
    );
    await adapter.updatePrescription(
      prescriptionId: fixedId,
      input: PrescriptionInput(
        mode: TemplatePrescriptionMode.fixed,
        repeat: 3,
        restAfter: const Duration(seconds: 60),
        values: LoggedSet.fromValues(
          const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '12',
              unit: TrainingUnit.repetition,
            ),
          ],
        ),
      ),
    );

    final detail = await adapter.watchTemplate(templateId).firstWhere(
          (template) =>
              template?.exercises.first.prescriptions.first.repeat == 3,
        );
    expect(
      detail?.exercises.map((exercise) => exercise.name),
      <String>['Dip', 'Push-up'],
    );
    expect(detail?.exercises.first.notes, 'Rings if available');
    expect(
      detail?.exercises.first.prescriptions
          .map((prescription) => prescription.id),
      <String>[fixedId, copyPreviousId],
    );
    expect(
        detail?.exercises.first.prescriptions.first.values.reps?.entered, '12');
    expect(detail?.exercises.first.prescriptions.first.restAfter,
        const Duration(seconds: 60));
    expect(detail?.exercises.first.prescriptions.last.mode,
        TemplatePrescriptionMode.copyPrevious);

    final groupId = await adapter.createTemplateGroup(
      templateId: templateId,
      input: TemplateGroupInput(
        name: 'A1 Pair',
        colorHex: '#2F6FED',
        rounds: 3,
        orderedTemplateExerciseIds: <String>[secondEntryId, firstEntryId],
      ),
    );
    final grouped = await adapter.watchTemplate(templateId).firstWhere(
          (template) => template?.groups.isNotEmpty ?? false,
        );
    expect(grouped?.groups.single.id, groupId);
    expect(grouped?.groups.single.rounds, 3);
    expect(
      grouped?.groups.single.members.map((member) => member.templateExerciseId),
      <String>[secondEntryId, firstEntryId],
    );

    await adapter.updateTemplateGroup(
      groupId: groupId,
      input: TemplateGroupInput(
        name: 'A1 Circuit',
        colorHex: '#5FB05C',
        rounds: 4,
        orderedTemplateExerciseIds: <String>[firstEntryId, secondEntryId],
      ),
    );
    final updatedGroup = await adapter.watchTemplate(templateId).firstWhere(
          (template) => template?.groups.single.rounds == 4,
        );
    expect(updatedGroup?.groups.single.name, 'A1 Circuit');
    await adapter.dissolveTemplateGroup(groupId);
    await adapter.watchTemplate(templateId).firstWhere(
          (template) => template?.groups.isEmpty ?? false,
        );

    await adapter.removePrescription(copyPreviousId);
    await adapter.removeExercise(firstEntryId);
    final trimmed = await adapter.watchTemplate(templateId).firstWhere(
          (template) =>
              template?.exercises.length == 1 &&
              template!.exercises.single.prescriptions.length == 1,
        );
    expect(trimmed?.exercises.single.name, 'Dip');
  });
}
