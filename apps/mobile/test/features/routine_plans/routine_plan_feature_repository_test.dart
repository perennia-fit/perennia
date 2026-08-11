import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/routine_plans/repositories/routine_plan_feature_repository.dart';

void main() {
  test('adapter projects live Workout Template references into every Routine',
      () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repositories = TrainingRepositories(database);
    final adapter = RepositoryRoutinePlanFeatureRepository(repositories);
    final templateId = await repositories.workoutTemplates.create(
      const WorkoutTemplateDraft(name: 'Tempo Run'),
    );
    final firstRoutineId = await adapter.createRoutine(name: 'Hybrid week');
    final secondRoutineId = await adapter.createRoutine(name: 'Race build');
    await adapter.addTemplateReference(
      routineId: firstRoutineId,
      workoutTemplateId: templateId,
    );
    await adapter.addTemplateReference(
      routineId: secondRoutineId,
      workoutTemplateId: templateId,
    );

    await repositories.workoutTemplates.updateTemplate(
      templateId,
      name: 'Tempo Run 8k',
      notes: 'Controlled threshold',
    );
    final first = await adapter.watchRoutine(firstRoutineId).firstWhere(
          (routine) => routine?.entries.single.templateName == 'Tempo Run 8k',
        );
    final second = await adapter.watchRoutine(secondRoutineId).firstWhere(
          (routine) => routine?.entries.single.templateName == 'Tempo Run 8k',
        );

    expect(first?.entries.single.templateNotes, 'Controlled threshold');
    expect(second?.entries.single.workoutTemplateId, templateId);
  });

  test('adapter keeps archived templates visible and restores independently',
      () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repositories = TrainingRepositories(database);
    final adapter = RepositoryRoutinePlanFeatureRepository(repositories);
    final templateId = await repositories.workoutTemplates.create(
      const WorkoutTemplateDraft(name: 'Pool intervals'),
    );
    final routineId = await adapter.createRoutine(name: 'Triathlon');
    await adapter.addTemplateReference(
      routineId: routineId,
      workoutTemplateId: templateId,
    );

    await repositories.workoutTemplates.archive(templateId);
    final archived = await adapter.watchRoutine(routineId).firstWhere(
          (routine) => routine?.entries.single.templateIsArchived ?? false,
        );
    expect(archived?.entries.single.templateName, 'Pool intervals');
    expect(await adapter.watchAvailableTemplates().first, isEmpty);

    await adapter.restoreReferencedTemplate(templateId);
    final restored = await adapter.watchRoutine(routineId).firstWhere(
          (routine) =>
              routine != null &&
              routine.entries.isNotEmpty &&
              !routine.entries.single.templateIsArchived,
        );
    expect(restored?.entries.single.workoutTemplateId, templateId);
  });

  test('adapter forwards ordering, removal, and independent Routine lifecycle',
      () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repositories = TrainingRepositories(database);
    final adapter = RepositoryRoutinePlanFeatureRepository(repositories);
    final firstTemplateId = await repositories.workoutTemplates.create(
      const WorkoutTemplateDraft(name: 'Strength'),
    );
    final secondTemplateId = await repositories.workoutTemplates.create(
      const WorkoutTemplateDraft(name: 'Easy Run'),
    );
    final routineId = await adapter.createRoutine(
      name: 'Concurrent plan',
      notes: 'Three sessions',
    );
    final firstEntryId = await adapter.addTemplateReference(
      routineId: routineId,
      workoutTemplateId: firstTemplateId,
    );
    final secondEntryId = await adapter.addTemplateReference(
      routineId: routineId,
      workoutTemplateId: secondTemplateId,
    );

    await adapter.reorderTemplateReferences(
      routineId: routineId,
      orderedEntryIds: <String>[secondEntryId, firstEntryId],
    );
    var detail = await adapter.watchRoutine(routineId).firstWhere(
          (routine) => routine?.entries.first.id == secondEntryId,
        );
    expect(
      detail?.entries.map((entry) => entry.templateName),
      <String>['Easy Run', 'Strength'],
    );

    await adapter.removeTemplateReference(firstEntryId);
    detail = await adapter.watchRoutine(routineId).firstWhere(
          (routine) => routine?.entries.length == 1,
        );
    expect(detail?.entries.single.id, secondEntryId);

    await adapter.archiveRoutine(routineId);
    final archivedSnapshot = await adapter.watchRoutines().firstWhere(
          (snapshot) =>
              snapshot.archived.any((routine) => routine.id == routineId),
        );
    expect(archivedSnapshot.active, isEmpty);
    expect(
      (await repositories.workoutTemplates.getById(firstTemplateId))
          ?.isArchived,
      isFalse,
    );

    await adapter.restoreRoutine(routineId);
    final restoredSnapshot = await adapter.watchRoutines().firstWhere(
          (snapshot) =>
              snapshot.active.any((routine) => routine.id == routineId),
        );
    expect(restoredSnapshot.active.single.entryCount, 1);
  });

  test('adapter preserves Entry identity across Cadence transitions and moves',
      () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repositories = TrainingRepositories(database);
    final adapter = RepositoryRoutinePlanFeatureRepository(repositories);
    final templateIds = <String>[
      await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Strength'),
      ),
      await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Run'),
      ),
      await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Mobility'),
      ),
    ];
    final routineId = await adapter.createRoutine(name: 'Hybrid');
    final entryIds = <String>[
      for (final templateId in templateIds)
        await adapter.addTemplateReference(
          routineId: routineId,
          workoutTemplateId: templateId,
        ),
    ];

    await adapter.setCadence(
      routineId: routineId,
      cadence: const Cadence.weekly(),
    );
    var detail = await adapter.watchRoutine(routineId).firstWhere(
          (routine) => routine?.cadence?.kind == CadenceKind.weekly,
        );
    expect(detail?.entries.map((entry) => entry.id), entryIds);
    expect(detail?.entries.map((entry) => entry.slot), <int?>[1, 2, 3]);

    await adapter.moveTemplateReferenceToSlot(
      routineEntryId: entryIds.last,
      slot: 2,
    );
    detail = await adapter.watchRoutine(routineId).firstWhere(
          (routine) => routine?.entries.last.slot == 2,
        );
    expect(detail?.entries.map((entry) => entry.id), entryIds);

    await adapter.setCadence(
      routineId: routineId,
      cadence: const Cadence.rotating(2),
    );
    detail = await adapter.watchRoutine(routineId).firstWhere(
          (routine) => routine?.cadence?.kind == CadenceKind.rotating,
        );
    expect(detail?.cadence?.window, 2);
    expect(detail?.entries.map((entry) => entry.id), entryIds);
    expect(detail?.entries.map((entry) => entry.slot), <int?>[1, 2, 1]);

    await adapter.setCadence(routineId: routineId, cadence: null);
    detail = await adapter.watchRoutine(routineId).firstWhere(
          (routine) => routine != null && routine.cadence == null,
        );
    expect(detail?.entries.map((entry) => entry.id), entryIds);
    expect(detail?.entries.map((entry) => entry.slot),
        const <int?>[null, null, null]);
  });
}
