import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_dimensions.dart';

void main() {
  group('plan-tree kill and reopen', () {
    test('persists each committed step of a mid-Template edit', () async {
      final directory = await Directory.systemTemp.createTemp(
        'prn_plan_template_reopen_',
      );
      final file = File('${directory.path}/plan.sqlite');
      var database = AppDatabase.openFile(file);
      addTearDown(() async {
        await database.close();
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      var repositories = TrainingRepositories(database);

      final pressId = await _createExercise(
        repositories,
        name: 'Bench Press',
        dimensions: const <DimensionId>[
          DimensionId.load,
          DimensionId.reps,
        ],
      );
      final rowId = await _createExercise(
        repositories,
        name: 'Barbell Row',
        dimensions: const <DimensionId>[
          DimensionId.load,
          DimensionId.reps,
        ],
      );
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Push and pull draft'),
      );
      final pressEntryId = await repositories.workoutTemplates.addExercise(
        templateId,
        pressId,
        note: 'Pause on the chest',
      );
      final rowEntryId = await repositories.workoutTemplates.addExercise(
        templateId,
        rowId,
      );
      final prescriptionId =
          await repositories.workoutTemplates.addPrescription(
        pressEntryId,
        PrescriptionDraft(
          mode: PrescriptionMode.fixed,
          values: _loadReps(load: '80', reps: '6'),
          repeat: 3,
          restAfter: const Duration(seconds: 120),
        ),
      );

      // Simulate the process being killed between individually committed edit
      // actions: no screen-level "done" action is needed to make them durable.
      await database.close();
      database = AppDatabase.openFile(file);
      repositories = TrainingRepositories(database);

      var detail = await repositories.workoutTemplates.getById(templateId);
      expect(detail?.name, 'Push and pull draft');
      expect(
        detail?.exercises.map((entry) => entry.id),
        <String>[pressEntryId, rowEntryId],
      );
      expect(
        detail?.exercises.first.prescriptions.single.id,
        prescriptionId,
      );
      expect(
        detail?.exercises.first.prescriptions.single.values.load?.entered,
        '80',
      );

      final groupId = await repositories.workoutTemplates.createTemplateGroup(
        templateId,
        TemplateGroupDraft(
          name: 'Alternating pair',
          colorHex: '#4A8FE0',
          rounds: 4,
          orderedTemplateExerciseIds: <String>[pressEntryId, rowEntryId],
        ),
      );
      await repositories.workoutTemplates.updateTemplate(
        templateId,
        name: 'Push and pull',
        notes: 'Four rounds',
      );

      await database.close();
      database = AppDatabase.openFile(file);
      repositories = TrainingRepositories(database);

      detail = await repositories.workoutTemplates.getById(templateId);
      expect(detail?.name, 'Push and pull');
      expect(detail?.notes, 'Four rounds');
      expect(detail?.exercises, hasLength(2));
      expect(detail?.groups.single.id, groupId);
      expect(detail?.groups.single.rounds, 4);
      expect(
        detail?.groups.single.members
            .map((member) => member.templateExerciseId),
        <String>[pressEntryId, rowEntryId],
      );
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    });

    test('persists each committed step of a mid-Routine edit', () async {
      final directory = await Directory.systemTemp.createTemp(
        'prn_plan_routine_reopen_',
      );
      final file = File('${directory.path}/plan.sqlite');
      var database = AppDatabase.openFile(file);
      addTearDown(() async {
        await database.close();
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      var repositories = TrainingRepositories(database);

      final strengthTemplateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Strength'),
      );
      final intervalsTemplateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Intervals'),
      );
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Hybrid week draft'),
      );
      final strengthEntryId =
          await repositories.routinePlans.addTemplateReference(
        routineId,
        strengthTemplateId,
      );

      await database.close();
      database = AppDatabase.openFile(file);
      repositories = TrainingRepositories(database);

      var routine = await repositories.routinePlans.getById(routineId);
      expect(routine?.name, 'Hybrid week draft');
      expect(routine?.entries.single.id, strengthEntryId);
      expect(
        routine?.entries.single.workoutTemplateId,
        strengthTemplateId,
      );

      final intervalsEntryId =
          await repositories.routinePlans.addTemplateReference(
        routineId,
        intervalsTemplateId,
      );
      await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.weekly(),
      );
      await repositories.routinePlans.replaceCadenceLayout(
        routineId,
        <RoutineEntrySlotPlacement>[
          RoutineEntrySlotPlacement(entryId: strengthEntryId, slot: 1),
          RoutineEntrySlotPlacement(entryId: intervalsEntryId, slot: 3),
        ],
      );
      await repositories.routinePlans.updateRoutine(
        routineId,
        name: 'Hybrid week',
        notes: 'Lift then run',
      );

      await database.close();
      database = AppDatabase.openFile(file);
      repositories = TrainingRepositories(database);

      routine = await repositories.routinePlans.getById(routineId);
      expect(routine?.name, 'Hybrid week');
      expect(routine?.notes, 'Lift then run');
      expect(routine?.cadence?.kind, CadenceKind.weekly);
      expect(
        routine?.entries.map((entry) => entry.id),
        <String>[strengthEntryId, intervalsEntryId],
      );
      expect(routine?.entries.map((entry) => entry.slot), <int?>[1, 3]);
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    });
  });
}

Future<String> _createExercise(
  TrainingRepositories repositories, {
  required String name,
  required List<DimensionId> dimensions,
}) {
  return repositories.exercises.create(
    ExerciseDraft(name: name, type: ExerciseType(dimensions)),
  );
}

LoggedSet _loadReps({required String load, required String reps}) {
  return LoggedSet.fromValues(<SetDimensionValue>[
    SetDimensionValue(
      dimension: DimensionId.load,
      entered: load,
      unit: TrainingUnit.kilogram,
    ),
    SetDimensionValue(
      dimension: DimensionId.reps,
      entered: reps,
      unit: TrainingUnit.repetition,
    ),
  ]);
}
