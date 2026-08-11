import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  group('WorkoutTemplateRepository', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('active and archived summaries react to lifecycle writes', () async {
      expect(
        await repositories.workoutTemplates.watchActiveSummaries().first,
        isEmpty,
      );
      final createdSummary = repositories.workoutTemplates
          .watchActiveSummaries()
          .firstWhere((summaries) => summaries.isNotEmpty);
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(
          name: '  Push A  ',
          notes: '  Main gym  ',
        ),
        batchId: 'create-template',
      );

      final summaries = await createdSummary;
      expect(summaries.single.name, 'Push A');
      expect(summaries.single.notes, 'Main gym');
      expect(summaries.single.exerciseCount, 0);

      await repositories.workoutTemplates.updateTemplate(
        templateId,
        name: 'Push B',
        notes: '  ',
        batchId: 'update-template',
      );
      expect(
        await repositories.workoutTemplates.getById(templateId),
        isA<WorkoutTemplateRecord>()
            .having((record) => record.name, 'name', 'Push B')
            .having((record) => record.notes, 'notes', isNull),
      );

      await repositories.workoutTemplates.archive(
        templateId,
        batchId: 'archive-template',
      );
      expect(
          await repositories.workoutTemplates.listActiveSummaries(), isEmpty);
      final archived =
          await repositories.workoutTemplates.listArchivedSummaries();
      expect(archived.single.id, templateId);
      expect(archived.single.isArchived, isTrue);

      final archiveLogs = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == 'archive-template')
          .toList(growable: false);
      expect(archiveLogs, hasLength(1));
      expect(archiveLogs.single.entityTable, AppDatabase.workoutTemplatesTable);
      expect(archiveLogs.single.beforeImage?['deleted_at'], isNull);
      expect(archiveLogs.single.afterImage?['deleted_at'], isNotNull);

      await repositories.workoutTemplates.restore(templateId);
      expect(
        (await repositories.workoutTemplates.listActiveSummaries()).single.id,
        templateId,
      );
    });

    test('builds, updates, and reorders the complete plan tree', () async {
      final squatId = await _createExercise(
        repositories,
        name: 'Back Squat',
        dimensions: const <DimensionId>[DimensionId.load, DimensionId.reps],
      );
      final plankId = await _createExercise(
        repositories,
        name: 'Plank',
        dimensions: const <DimensionId>[DimensionId.duration],
      );
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Strength'),
      );
      final squatEntryId = await repositories.workoutTemplates.addExercise(
        templateId,
        squatId,
        note: ' Rack 2 ',
      );
      final plankEntryId = await repositories.workoutTemplates.addExercise(
        templateId,
        plankId,
      );
      final workingSetId = await repositories.workoutTemplates.addPrescription(
        squatEntryId,
        PrescriptionDraft(
          mode: PrescriptionMode.fixed,
          values: _loadReps(load: '100', reps: '5'),
          repeat: 3,
          restAfter: const Duration(seconds: 180),
        ),
      );
      final previousSetId = await repositories.workoutTemplates.addPrescription(
        squatEntryId,
        PrescriptionDraft(
          mode: PrescriptionMode.copyPrevious,
          values: LoggedSet.completion(),
          repeat: 1,
        ),
      );

      await repositories.workoutTemplates.updateExerciseNote(
        squatEntryId,
        note: 'Rack 4',
        batchId: 'update-entry-note',
      );
      await repositories.workoutTemplates.updatePrescription(
        workingSetId,
        PrescriptionDraft(
          mode: PrescriptionMode.fixed,
          values: _loadReps(load: '102.5', reps: '5'),
          repeat: 4,
          restAfter: const Duration(seconds: 210),
        ),
        batchId: 'update-prescription',
      );
      await repositories.workoutTemplates.reorderExercises(
        templateId,
        <String>[plankEntryId, squatEntryId],
        batchId: 'reorder-exercises',
      );
      await repositories.workoutTemplates.reorderPrescriptions(
        squatEntryId,
        <String>[previousSetId, workingSetId],
        batchId: 'reorder-prescriptions',
      );

      final detail = await repositories.workoutTemplates.getById(templateId);
      expect(detail, isNotNull);
      expect(
        detail!.exercises.map((entry) => entry.id),
        <String>[plankEntryId, squatEntryId],
      );
      final squat = detail.exercises.last;
      expect(squat.exercise.name, 'Back Squat');
      expect(squat.note, 'Rack 4');
      expect(
        squat.prescriptions.map((prescription) => prescription.id),
        <String>[previousSetId, workingSetId],
      );
      expect(squat.prescriptions.first.mode, PrescriptionMode.copyPrevious);
      expect(squat.prescriptions.first.values.dimensionIds, isEmpty);
      expect(squat.prescriptions.last.values.load?.entered, '102.5');
      expect(squat.prescriptions.last.repeat, 4);
      expect(squat.prescriptions.last.restAfter, const Duration(seconds: 210));

      final logs = await repositories.activityLog.listEntries();
      expect(
        logs
            .where((entry) => entry.batchId == 'reorder-exercises')
            .map((entry) => entry.entityTable)
            .toSet(),
        <String>{AppDatabase.templateExercisesTable},
      );
      expect(
        logs
            .where((entry) => entry.batchId == 'reorder-prescriptions')
            .map((entry) => entry.entityTable)
            .toSet(),
        <String>{AppDatabase.prescriptionsTable},
      );
    });

    test('removing an entry preserves Prescriptions and re-add restores it',
        () async {
      final exerciseId = await _createExercise(
        repositories,
        name: 'Bench Press',
        dimensions: const <DimensionId>[DimensionId.load, DimensionId.reps],
      );
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Push'),
      );
      final entryId = await repositories.workoutTemplates.addExercise(
        templateId,
        exerciseId,
      );
      await expectLater(
        database.into(database.templateExercises).insert(
              TemplateExercisesCompanion.insert(
                id: 'duplicate-active-template-exercise',
                workoutTemplateId: templateId,
                exerciseId: exerciseId,
                position: 1,
                updatedAt: DateTime.utc(2026, 7, 11),
              ),
            ),
        throwsA(isA<sqlite.SqliteException>()),
      );
      final prescriptionId =
          await repositories.workoutTemplates.addPrescription(
        entryId,
        PrescriptionDraft(
          mode: PrescriptionMode.fixed,
          values: _loadReps(load: '80', reps: '8'),
        ),
      );

      await repositories.workoutTemplates.removeExercise(
        entryId,
        batchId: 'remove-entry',
      );
      expect(
        (await repositories.workoutTemplates.getById(templateId))!.exercises,
        isEmpty,
      );
      final prescription = await (database.select(database.prescriptions)
            ..where((row) => row.id.equals(prescriptionId)))
          .getSingle();
      expect(prescription.deletedAt, isNull);
      final removeLogs = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == 'remove-entry')
          .toList(growable: false);
      expect(removeLogs, hasLength(1));
      expect(removeLogs.single.entityTable, AppDatabase.templateExercisesTable);

      final restoredEntryId = await repositories.workoutTemplates.addExercise(
        templateId,
        exerciseId,
      );
      expect(restoredEntryId, entryId);
      expect(
        (await repositories.workoutTemplates.getById(templateId))!
            .exercises
            .single
            .prescriptions
            .single
            .id,
        prescriptionId,
      );

      await repositories.workoutTemplates.removeExercise(
        entryId,
        batchId: 'remove-entry-for-undo',
      );
      final undo = await repositories.activityLog.undoBatch(
        'remove-entry-for-undo',
      );
      expect(undo.conflicts, isEmpty);
      expect(
        (await repositories.workoutTemplates.getById(templateId))!
            .exercises
            .single
            .prescriptions
            .single
            .id,
        prescriptionId,
      );
    });

    test('validates dimensions, values, repeat warnings, and atomic reorder',
        () async {
      final exerciseId = await _createExercise(
        repositories,
        name: 'Deadlift',
        dimensions: const <DimensionId>[DimensionId.load, DimensionId.reps],
      );
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Pull'),
      );
      final entryId = await repositories.workoutTemplates.addExercise(
        templateId,
        exerciseId,
      );

      final warning =
          await repositories.workoutTemplates.validatePrescriptionDraft(
        entryId,
        PrescriptionDraft(
          mode: PrescriptionMode.fixed,
          values: _loadReps(load: '60', reps: '5'),
          repeat: 101,
        ),
      );
      expect(warning.accepted, isTrue);
      expect(
        warning.warnings.map((issue) => issue.rule),
        contains('prescription_repeat_improbable'),
      );

      await expectLater(
        repositories.workoutTemplates.addPrescription(
          entryId,
          PrescriptionDraft(
            mode: PrescriptionMode.fixed,
            values: _loadReps(load: '-1', reps: '5'),
          ),
          batchId: 'invalid-prescription',
        ),
        throwsA(isA<SetValidationException>()),
      );
      expect(
        (await repositories.activityLog.listEntries())
            .where((entry) => entry.batchId == 'invalid-prescription'),
        isEmpty,
      );
      await expectLater(
        repositories.workoutTemplates.addPrescription(
          entryId,
          PrescriptionDraft(
            mode: PrescriptionMode.fixed,
            values: LoggedSet.completion(),
          ),
        ),
        throwsArgumentError,
      );

      await expectLater(
        repositories.workoutTemplates.reorderExercises(
          templateId,
          const <String>['unknown'],
          batchId: 'invalid-reorder',
        ),
        throwsArgumentError,
      );
      expect(
        (await repositories.workoutTemplates.getById(templateId))!
            .exercises
            .single
            .position,
        0,
      );
      expect(
        (await repositories.activityLog.listEntries())
            .where((entry) => entry.batchId == 'invalid-reorder'),
        isEmpty,
      );
    });

    test('detail retains metadata for an archived referenced Exercise',
        () async {
      final exerciseId = await _createExercise(
        repositories,
        name: 'Retired Press',
        dimensions: const <DimensionId>[DimensionId.reps],
      );
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Archive reference'),
      );
      await repositories.workoutTemplates.addExercise(templateId, exerciseId);
      await repositories.exercises.softDelete(exerciseId);

      final exercise =
          (await repositories.workoutTemplates.getById(templateId))!
              .exercises
              .single
              .exercise;
      expect(exercise.name, 'Retired Press');
      expect(exercise.deletedAt, isNotNull);
    });

    test('Activity Log undo can restore a Template Link image', () async {
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Linked'),
      );
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 7, 11, 8),
          timezone: 'UTC',
        ),
      );
      final beforeTime = DateTime.utc(2026, 7, 11, 8, 1);
      final afterTime = DateTime.utc(2026, 7, 11, 8, 2);
      const linkId = 'template-link-for-undo';
      await database.into(database.templateLinks).insert(
            TemplateLinksCompanion.insert(
              id: linkId,
              workoutId: workoutId,
              workoutTemplateId: templateId,
              slot: const Value<int?>(2),
              updatedAt: afterTime,
            ),
          );
      final beforeImage = <String, Object?>{
        'id': linkId,
        'workout_id': workoutId,
        'workout_template_id': templateId,
        'routine_id': null,
        'slot': 1,
        'updated_at': beforeTime.toIso8601String(),
        'deleted_at': null,
      };
      final afterImage = <String, Object?>{
        ...beforeImage,
        'slot': 2,
        'updated_at': afterTime.toIso8601String(),
      };
      await database.into(database.activityLog).insert(
            ActivityLogCompanion.insert(
              id: 'template-link-activity',
              actor: 'test',
              batchId: 'template-link-update',
              entityTable: AppDatabase.templateLinksTable,
              entityId: linkId,
              beforeImage: Value<String?>(jsonEncode(beforeImage)),
              afterImage: Value<String?>(jsonEncode(afterImage)),
              occurredAt: afterTime,
              updatedAt: afterTime,
            ),
          );

      final result =
          await repositories.activityLog.undoBatch('template-link-update');
      expect(result.conflicts, isEmpty);
      final restored = await (database.select(database.templateLinks)
            ..where((row) => row.id.equals(linkId)))
          .getSingle();
      expect(restored.slot, 1);
      expect(restored.updatedAt, isNot(afterTime));
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
