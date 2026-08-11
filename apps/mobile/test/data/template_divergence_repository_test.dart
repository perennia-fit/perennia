import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_dimensions.dart';

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

  group('TemplateDivergenceRepository', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    Future<String> createExercise({
      required String name,
      Iterable<DimensionId> dimensions = const <DimensionId>[
        DimensionId.load,
        DimensionId.reps,
      ],
      TrainingUnit defaultLoadUnit = TrainingUnit.kilogram,
    }) {
      return repositories.exercises.create(
        ExerciseDraft(
          name: name,
          type: ExerciseType(dimensions),
          defaultLoadUnit: defaultLoadUnit,
        ),
      );
    }

    LoggedSet weightReps(String load, String reps) {
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

    Future<({String templateId, String benchId, String rowId})>
        createMixedTemplate({String name = 'Push A', String? notes}) async {
      final benchId = await createExercise(name: 'Bench Press');
      final rowId = await createExercise(name: 'Barbell Row');
      final templateId = await repositories.workoutTemplates.create(
        WorkoutTemplateDraft(name: name, notes: notes),
      );
      final benchEntryId =
          await repositories.workoutTemplates.addExercise(templateId, benchId);
      await repositories.workoutTemplates.addPrescription(
        benchEntryId,
        PrescriptionDraft(
          mode: PrescriptionMode.fixed,
          values: weightReps('100', '5'),
          repeat: 2,
          restAfter: const Duration(seconds: 90),
        ),
      );
      final rowEntryId =
          await repositories.workoutTemplates.addExercise(templateId, rowId);
      await repositories.workoutTemplates.addPrescription(
        rowEntryId,
        PrescriptionDraft(
          mode: PrescriptionMode.copyPrevious,
          values: LoggedSet.completion(),
          repeat: 3,
          restAfter: const Duration(seconds: 45),
        ),
      );
      return (templateId: templateId, benchId: benchId, rowId: rowId);
    }

    test(
        'a Template materialized and performed unchanged is zero divergence '
        'by construction, including copy-previous', () async {
      final built = await createMixedTemplate();
      final result = await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(workoutTemplateId: built.templateId),
        now: DateTime(2026, 7, 12, 8),
      );

      final summary = await repositories.templateDivergence.summaryForWorkout(
        result.workoutId,
      );

      expect(summary, isNotNull);
      expect(summary!.workoutTemplateId, built.templateId);
      expect(summary.hasDivergence, isFalse);
      expect(summary.divergence.addedExercises, isEmpty);
      expect(summary.divergence.removedExercises, isEmpty);
      expect(summary.divergence.changedExercises, isEmpty);
      expect(summary.divergence.groupsChanged, isFalse);
    });

    test('logging an extra exercise mid-workout diverges as added', () async {
      final built = await createMixedTemplate();
      final result = await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(workoutTemplateId: built.templateId),
        now: DateTime(2026, 7, 12, 8),
      );

      final dipsId = await createExercise(
        name: 'Dips',
        dimensions: const <DimensionId>[DimensionId.reps],
      );
      await repositories.workoutExercises.create(
        WorkoutExerciseDraft(workoutId: result.workoutId, exerciseId: dipsId),
      );
      final nextPosition =
          await repositories.sets.nextPositionForWorkout(result.workoutId);
      await repositories.sets.create(
        LoggedSetDraft(
          workoutId: result.workoutId,
          exerciseId: dipsId,
          position: nextPosition,
          values: LoggedSet.fromValues(const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '12',
              unit: TrainingUnit.repetition,
            ),
          ]),
        ),
      );

      final summary = await repositories.templateDivergence.summaryForWorkout(
        result.workoutId,
      );

      expect(summary!.hasDivergence, isTrue);
      expect(summary.divergence.addedExercises, hasLength(1));
      expect(summary.divergence.addedExercises.single.exerciseName, 'Dips');
      expect(summary.divergence.removedExercises, isEmpty);
      expect(summary.divergence.changedExercises, isEmpty);
    });

    test('editing a fixed Set\'s performed value diverges as changed',
        () async {
      final built = await createMixedTemplate();
      final result = await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(workoutTemplateId: built.templateId),
        now: DateTime(2026, 7, 12, 8),
      );

      final sets = await repositories.sets.listActiveForWorkout(
        result.workoutId,
      );
      final benchSet =
          sets.firstWhere((set) => set.exerciseId == built.benchId);
      await repositories.sets.updateValues(
        benchSet.id,
        values: weightReps('105', '5'),
      );

      final summary = await repositories.templateDivergence.summaryForWorkout(
        result.workoutId,
      );

      expect(summary!.hasDivergence, isTrue);
      expect(summary.divergence.changedExercises, hasLength(1));
      expect(
        summary.divergence.changedExercises.single.exerciseId,
        built.benchId,
      );
      expect(summary.divergence.addedExercises, isEmpty);
      expect(summary.divergence.removedExercises, isEmpty);
    });

    test(
        'a Workout with no Template Link has no divergence summary, and '
        'Update is a silent no-op', () async {
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime(2026, 7, 12, 8),
          timezone: 'UTC',
        ),
      );

      expect(
        await repositories.templateDivergence.summaryForWorkout(workoutId),
        isNull,
      );
      expect(
        await repositories.templateDivergence
            .updateTemplateFromWorkout(workoutId),
        isNull,
      );
    });

    test(
        'Update replaces the Template\'s content atomically while preserving '
        'id, name, notes, Routine membership, the Template Link, and '
        'copy-previous modes', () async {
      final built = await createMixedTemplate(
        name: 'Push A',
        notes: 'Barbell day',
      );
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Hybrid week'),
      );
      await repositories.routinePlans.addTemplateReference(
        routineId,
        built.templateId,
      );

      final result = await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(workoutTemplateId: built.templateId),
        now: DateTime(2026, 7, 12, 8),
      );

      // Diverge: heavier bench load on every bench Set (so it still
      // collapses to one Prescription, isolating the load change from a
      // repeat-count change), plus an unplanned extra exercise.
      final sets = await repositories.sets.listActiveForWorkout(
        result.workoutId,
      );
      for (final set in sets.where((set) => set.exerciseId == built.benchId)) {
        await repositories.sets.updateValues(
          set.id,
          values: weightReps('105', '5'),
        );
      }
      final dipsId = await createExercise(
        name: 'Dips',
        dimensions: const <DimensionId>[DimensionId.reps],
      );
      await repositories.workoutExercises.create(
        WorkoutExerciseDraft(workoutId: result.workoutId, exerciseId: dipsId),
      );
      final nextPosition =
          await repositories.sets.nextPositionForWorkout(result.workoutId);
      await repositories.sets.create(
        LoggedSetDraft(
          workoutId: result.workoutId,
          exerciseId: dipsId,
          position: nextPosition,
          values: LoggedSet.fromValues(const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '12',
              unit: TrainingUnit.repetition,
            ),
          ]),
        ),
      );

      final updateResult = await repositories.templateDivergence
          .updateTemplateFromWorkout(result.workoutId, batchId: 'update-1');

      expect(updateResult, isNotNull);
      expect(updateResult!.workoutTemplateId, built.templateId);
      expect(updateResult.activityBatchId, 'update-1');

      final after = await repositories.workoutTemplates.getById(
        built.templateId,
      );
      expect(after, isNotNull);
      expect(after!.id, built.templateId, reason: 'identity preserved');
      expect(after.name, 'Push A', reason: 'name preserved');
      expect(after.notes, 'Barbell day', reason: 'notes preserved');
      expect(
        after.exercises.map((exercise) => exercise.exerciseId).toSet(),
        <String>{built.benchId, built.rowId, dipsId},
      );

      final benchExercise = after.exercises.firstWhere(
        (exercise) => exercise.exerciseId == built.benchId,
      );
      expect(benchExercise.prescriptions, hasLength(1));
      expect(benchExercise.prescriptions.single.mode, PrescriptionMode.fixed);
      expect(benchExercise.prescriptions.single.values.load?.entered, '105');

      final rowExercise = after.exercises.firstWhere(
        (exercise) => exercise.exerciseId == built.rowId,
      );
      expect(rowExercise.prescriptions, hasLength(1));
      expect(
        rowExercise.prescriptions.single.mode,
        PrescriptionMode.copyPrevious,
        reason: 'unchanged copy-previous survives the write-back',
      );

      // Routine membership preserved.
      final routine = await repositories.routinePlans.getById(routineId);
      expect(
        routine!.entries.map((entry) => entry.workoutTemplateId),
        contains(built.templateId),
      );

      // The Template Link still points at the same Template.
      final link = await repositories.templateMaterialize.getByWorkoutId(
        result.workoutId,
      );
      expect(link!.workoutTemplateId, built.templateId);

      // One Activity Log batch for the whole write-back.
      final batchEntries = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == 'update-1')
          .toList(growable: false);
      expect(batchEntries, isNotEmpty);
      expect(
        batchEntries.every((entry) => entry.batchId == 'update-1'),
        isTrue,
      );
    });

    test(
        'the overflow verb can Update a linked Workout at any later time, '
        'even with zero divergence', () async {
      final built = await createMixedTemplate();
      final result = await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(workoutTemplateId: built.templateId),
        now: DateTime(2026, 7, 12, 8),
      );

      final summaryBefore = await repositories.templateDivergence
          .summaryForWorkout(result.workoutId);
      expect(summaryBefore!.hasDivergence, isFalse);

      final updateResult = await repositories.templateDivergence
          .updateTemplateFromWorkout(result.workoutId);

      expect(updateResult, isNotNull);
      final after = await repositories.workoutTemplates.getById(
        built.templateId,
      );
      expect(after!.exercises, hasLength(2));
      final rowExercise = after.exercises.firstWhere(
        (exercise) => exercise.exerciseId == built.rowId,
      );
      expect(rowExercise.prescriptions.single.mode, PrescriptionMode.copyPrevious);
    });

    test(
        'reading the divergence summary never writes anything — dismissing '
        'is a silent no with no state recorded', () async {
      final built = await createMixedTemplate();
      final result = await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(workoutTemplateId: built.templateId),
        now: DateTime(2026, 7, 12, 8),
      );
      final sets = await repositories.sets.listActiveForWorkout(
        result.workoutId,
      );
      final benchSet =
          sets.firstWhere((set) => set.exerciseId == built.benchId);
      await repositories.sets.updateValues(
        benchSet.id,
        values: weightReps('105', '5'),
      );

      final before = await repositories.workoutTemplates.getById(
        built.templateId,
      );
      final summary = await repositories.templateDivergence.summaryForWorkout(
        result.workoutId,
      );
      expect(summary!.hasDivergence, isTrue);

      final after = await repositories.workoutTemplates.getById(
        built.templateId,
      );
      expect(after!.updatedAt, before!.updatedAt);
      expect(
        after.exercises
            .firstWhere((exercise) => exercise.exerciseId == built.benchId)
            .prescriptions
            .single
            .values
            .load
            ?.entered,
        '100',
        reason: 'the Template itself is untouched until Update is invoked',
      );
    });
  });
}
