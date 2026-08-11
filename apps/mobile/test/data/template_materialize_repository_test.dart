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

  group('TemplateMaterializeRepository', () {
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

    test(
        'materializing a bare Template creates one Workout whose Sets exactly '
        'reflect fixed Prescriptions (repeat unrolled) and exactly one '
        'Template Link with no Routine', () async {
      final exerciseId = await createExercise(name: 'Bench Press');
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Push A', notes: 'Barbell day'),
      );
      final templateExerciseId = await repositories.workoutTemplates
          .addExercise(templateId, exerciseId);
      await repositories.workoutTemplates.addPrescription(
        templateExerciseId,
        PrescriptionDraft(
          mode: PrescriptionMode.fixed,
          values: LoggedSet.fromValues(const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.load,
              entered: '100',
              unit: TrainingUnit.kilogram,
            ),
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '5',
              unit: TrainingUnit.repetition,
            ),
          ]),
          repeat: 3,
          restAfter: const Duration(seconds: 120),
        ),
      );

      final result = await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(workoutTemplateId: templateId),
        now: DateTime(2026, 7, 12, 8),
        batchId: 'materialize-1',
      );

      final workoutExercises = await repositories.workoutExercises
          .listActiveForWorkout(result.workoutId);
      expect(workoutExercises, hasLength(1));
      expect(workoutExercises.single.exerciseId, exerciseId);

      final sets = await repositories.sets.listActiveForWorkout(
        result.workoutId,
      );
      expect(sets, hasLength(3));
      for (final set in sets) {
        expect(set.values.load?.entered, '100');
        expect(set.values.reps?.entered, '5');
        expect(set.plannedRestAfter, const Duration(seconds: 120));
      }

      final link = await repositories.templateMaterialize.getByWorkoutId(
        result.workoutId,
      );
      expect(link, isNotNull);
      expect(link!.id, result.templateLinkId);
      expect(link.workoutTemplateId, templateId);
      expect(link.routineId, isNull);
      expect(link.slot, isNull);

      // Notes are plan guidance and are never copied into the Workout.
      final workout = await repositories.workoutSessions.getById(
        result.workoutId,
      );
      expect(workout?.comment, isNull);

      // One Activity Log batch for the whole materialize.
      final batchEntries = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == 'materialize-1')
          .toList(growable: false);
      expect(batchEntries, isNotEmpty);
      expect(
        batchEntries.every((entry) => entry.batchId == 'materialize-1'),
        isTrue,
      );
    });

    test(
        'copy-previous Prescriptions resolve from the exercise\'s last '
        'performed values at materialize time', () async {
      final exerciseId = await createExercise(name: 'Back Squat');
      final earlierWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime(2026, 7, 1, 9),
          timezone: 'UTC',
        ),
      );
      await repositories.sets.create(
        LoggedSetDraft(
          workoutId: earlierWorkoutId,
          exerciseId: exerciseId,
          position: 0,
          values: LoggedSet.fromValues(const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.load,
              entered: '140',
              unit: TrainingUnit.kilogram,
            ),
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '3',
              unit: TrainingUnit.repetition,
            ),
          ]),
          performedAt: DateTime(2026, 7, 1, 9, 10),
          isCompleted: true,
        ),
      );
      final laterWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime(2026, 7, 8, 9),
          timezone: 'UTC',
        ),
      );
      await repositories.sets.create(
        LoggedSetDraft(
          workoutId: laterWorkoutId,
          exerciseId: exerciseId,
          position: 0,
          values: LoggedSet.fromValues(const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.load,
              entered: '150',
              unit: TrainingUnit.kilogram,
            ),
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '2',
              unit: TrainingUnit.repetition,
            ),
          ]),
          performedAt: DateTime(2026, 7, 8, 9, 10),
          isCompleted: true,
        ),
      );

      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Strength'),
      );
      final templateExerciseId = await repositories.workoutTemplates
          .addExercise(templateId, exerciseId);
      await repositories.workoutTemplates.addPrescription(
        templateExerciseId,
        PrescriptionDraft(
          mode: PrescriptionMode.copyPrevious,
          values: LoggedSet.completion(),
          repeat: 2,
          restAfter: const Duration(seconds: 180),
        ),
      );

      final result = await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(workoutTemplateId: templateId),
        now: DateTime(2026, 7, 15, 8),
      );

      final sets = await repositories.sets.listActiveForWorkout(
        result.workoutId,
      );
      expect(sets, hasLength(2));
      for (final set in sets) {
        expect(set.values.load?.entered, '150');
        expect(set.values.reps?.entered, '2');
        expect(set.plannedRestAfter, const Duration(seconds: 180));
      }
    });

    test(
        'copy-previous Prescriptions resolve to zero-values when the '
        'exercise was never performed', () async {
      final exerciseId = await createExercise(
        name: 'Cable Row',
        defaultLoadUnit: TrainingUnit.pound,
      );
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Pull'),
      );
      final templateExerciseId = await repositories.workoutTemplates
          .addExercise(templateId, exerciseId);
      await repositories.workoutTemplates.addPrescription(
        templateExerciseId,
        PrescriptionDraft(
          mode: PrescriptionMode.copyPrevious,
          values: LoggedSet.completion(),
          repeat: 1,
        ),
      );

      final result = await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(workoutTemplateId: templateId),
        now: DateTime(2026, 7, 12, 8),
      );

      final sets = await repositories.sets.listActiveForWorkout(
        result.workoutId,
      );
      expect(sets, hasLength(1));
      expect(sets.single.values.load?.entered, '0');
      expect(sets.single.values.load?.unit, TrainingUnit.pound);
      expect(sets.single.values.reps?.entered, '0');
    });

    test(
        'copy-previous Prescriptions never resolve from a not-yet-performed '
        'placeholder Set (e.g. left behind by an abandoned materialize) — '
        'only a genuinely completed Set counts as "last performed"',
        () async {
      final exerciseId = await createExercise(name: 'Front Squat');

      final completedWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime(2026, 7, 1, 9),
          timezone: 'UTC',
        ),
      );
      await repositories.sets.create(
        LoggedSetDraft(
          workoutId: completedWorkoutId,
          exerciseId: exerciseId,
          position: 0,
          values: LoggedSet.fromValues(const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.load,
              entered: '100',
              unit: TrainingUnit.kilogram,
            ),
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '5',
              unit: TrainingUnit.repetition,
            ),
          ]),
          performedAt: DateTime(2026, 7, 1, 9, 10),
          isCompleted: true,
        ),
      );

      // A later, but never-completed, placeholder Set for the same
      // exercise — e.g. left behind by an abandoned/unfinished materialize.
      // It must never be treated as "last performed".
      final abandonedWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime(2026, 7, 8, 9),
          timezone: 'UTC',
        ),
      );
      await repositories.sets.create(
        LoggedSetDraft(
          workoutId: abandonedWorkoutId,
          exerciseId: exerciseId,
          position: 0,
          values: LoggedSet.fromValues(const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.load,
              entered: '999',
              unit: TrainingUnit.kilogram,
            ),
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '99',
              unit: TrainingUnit.repetition,
            ),
          ]),
          performedAt: DateTime(2026, 7, 8, 9, 10),
          isCompleted: false,
        ),
      );

      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Legs'),
      );
      final templateExerciseId = await repositories.workoutTemplates
          .addExercise(templateId, exerciseId);
      await repositories.workoutTemplates.addPrescription(
        templateExerciseId,
        PrescriptionDraft(
          mode: PrescriptionMode.copyPrevious,
          values: LoggedSet.completion(),
          repeat: 1,
        ),
      );

      final result = await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(workoutTemplateId: templateId),
        now: DateTime(2026, 7, 15, 8),
      );

      final sets = await repositories.sets.listActiveForWorkout(
        result.workoutId,
      );
      expect(sets, hasLength(1));
      expect(sets.single.values.load?.entered, '100');
      expect(sets.single.values.reps?.entered, '5');
    });

    test(
        'Template Groups and rounds materialize into the Workout\'s Exercise '
        'Groups', () async {
      final pullUpId = await createExercise(
        name: 'Pull-up',
        dimensions: const <DimensionId>[DimensionId.reps],
      );
      final pushUpId = await createExercise(
        name: 'Push-up',
        dimensions: const <DimensionId>[DimensionId.reps],
      );
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Superset'),
      );
      final pullUpEntryId = await repositories.workoutTemplates.addExercise(
        templateId,
        pullUpId,
      );
      final pushUpEntryId = await repositories.workoutTemplates.addExercise(
        templateId,
        pushUpId,
      );
      await repositories.workoutTemplates.addPrescription(
        pullUpEntryId,
        PrescriptionDraft(
          mode: PrescriptionMode.fixed,
          values: LoggedSet.fromValues(const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '8',
              unit: TrainingUnit.repetition,
            ),
          ]),
        ),
      );
      await repositories.workoutTemplates.addPrescription(
        pushUpEntryId,
        PrescriptionDraft(
          mode: PrescriptionMode.fixed,
          values: LoggedSet.fromValues(const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '15',
              unit: TrainingUnit.repetition,
            ),
          ]),
        ),
      );
      await repositories.workoutTemplates.createTemplateGroup(
        templateId,
        TemplateGroupDraft(
          name: 'Push superset',
          colorHex: '#2F6FED',
          rounds: 3,
          orderedTemplateExerciseIds: <String>[pullUpEntryId, pushUpEntryId],
        ),
      );

      final result = await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(workoutTemplateId: templateId),
        now: DateTime(2026, 7, 12, 8),
      );

      final groups = await repositories.exerciseGroups.listActiveForWorkout(
        result.workoutId,
      );
      expect(groups, hasLength(1));
      expect(groups.single.name, 'Push superset');
      expect(groups.single.colorHex, '#2F6FED');
      final workoutExercises = await repositories.workoutExercises
          .listActiveForWorkout(result.workoutId);
      final exerciseIdByWorkoutExerciseId = <String, String>{
        for (final exercise in workoutExercises)
          exercise.id: exercise.exerciseId,
      };
      expect(
        groups.single.workoutExerciseIds
            .map((id) => exerciseIdByWorkoutExerciseId[id]),
        <String>[pullUpId, pushUpId],
      );
    });

    test(
        'materializing via a Routine slot records the Routine and slot on '
        'the Template Link; renaming the Routine name later never touches '
        'the Workout', () async {
      final exerciseId = await createExercise(name: 'Overhead Press');
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Push A'),
      );
      final entryId = await repositories.workoutTemplates.addExercise(
        templateId,
        exerciseId,
      );
      await repositories.workoutTemplates.addPrescription(
        entryId,
        PrescriptionDraft(
          mode: PrescriptionMode.fixed,
          values: LoggedSet.fromValues(const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.load,
              entered: '60',
              unit: TrainingUnit.kilogram,
            ),
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '5',
              unit: TrainingUnit.repetition,
            ),
          ]),
        ),
      );
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Hybrid week'),
      );
      await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.rotating(3),
      );

      final result = await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(
          workoutTemplateId: templateId,
          routineId: routineId,
          slot: 2,
        ),
        now: DateTime(2026, 7, 12, 8),
      );

      final link = await repositories.templateMaterialize.getByWorkoutId(
        result.workoutId,
      );
      expect(link?.routineId, routineId);
      expect(link?.slot, 2);

      await repositories.routinePlans.updateRoutine(
        routineId,
        name: 'Renamed week',
      );
      final unchangedLink = await repositories.templateMaterialize
          .getByWorkoutId(result.workoutId);
      expect(unchangedLink?.id, link?.id);
      expect(unchangedLink?.routineId, routineId);
      expect(unchangedLink?.slot, 2);
    });

    test(
        'renaming or archiving the Template afterwards never alters the '
        'Workout or breaks the Template Link', () async {
      final exerciseId = await createExercise(name: 'Deadlift');
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Pull A'),
      );
      final entryId = await repositories.workoutTemplates.addExercise(
        templateId,
        exerciseId,
      );
      await repositories.workoutTemplates.addPrescription(
        entryId,
        PrescriptionDraft(
          mode: PrescriptionMode.fixed,
          values: LoggedSet.fromValues(const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.load,
              entered: '100',
              unit: TrainingUnit.kilogram,
            ),
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '5',
              unit: TrainingUnit.repetition,
            ),
          ]),
        ),
      );

      final result = await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(workoutTemplateId: templateId),
        now: DateTime(2026, 7, 12, 8),
      );
      final setsBefore = await repositories.sets.listActiveForWorkout(
        result.workoutId,
      );

      await repositories.workoutTemplates.updateTemplate(
        templateId,
        name: 'Pull A renamed',
      );
      await repositories.workoutTemplates.archive(templateId);

      final link = await repositories.templateMaterialize.getByWorkoutId(
        result.workoutId,
      );
      expect(link, isNotNull);
      expect(link!.deletedAt, isNull);
      final setsAfter = await repositories.sets.listActiveForWorkout(
        result.workoutId,
      );
      expect(
        setsAfter.map((set) => set.values.load?.entered),
        setsBefore.map((set) => set.values.load?.entered),
      );
    });

    test('archived Templates cannot be materialized', () async {
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Retired'),
      );
      await repositories.workoutTemplates.archive(templateId);

      expect(
        () => repositories.templateMaterialize.materialize(
          TemplateMaterializeRequest(workoutTemplateId: templateId),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test(
        'a manually assembled Workout (not materialized) has no Template '
        'Link', () async {
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(startedAt: DateTime(2026, 7, 12, 8), timezone: 'UTC'),
      );

      final link = await repositories.templateMaterialize.getByWorkoutId(
        workoutId,
      );
      expect(link, isNull);
    });

    test(
        'starting the same Template twice always begins a brand-new Workout '
        '(a Template is a plan for one session)', () async {
      final exerciseId = await createExercise(name: 'Kettlebell Swing');
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Conditioning'),
      );
      final entryId = await repositories.workoutTemplates.addExercise(
        templateId,
        exerciseId,
      );
      await repositories.workoutTemplates.addPrescription(
        entryId,
        PrescriptionDraft(
          mode: PrescriptionMode.fixed,
          values: LoggedSet.fromValues(const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.load,
              entered: '24',
              unit: TrainingUnit.kilogram,
            ),
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '20',
              unit: TrainingUnit.repetition,
            ),
          ]),
        ),
      );

      final first = await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(workoutTemplateId: templateId),
        now: DateTime(2026, 7, 12, 8),
      );
      final second = await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(workoutTemplateId: templateId),
        now: DateTime(2026, 7, 12, 18),
      );

      expect(first.workoutId, isNot(second.workoutId));
      expect(first.templateLinkId, isNot(second.templateLinkId));
    });
  });
}
