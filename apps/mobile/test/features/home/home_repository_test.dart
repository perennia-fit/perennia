import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/platform_exercise_seed.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/home/repositories/home_repository.dart';

void main() {
  group('Home summary models', () {
    test('defensively copy collections and expose immutable views', () {
      final setA = const HomeSetSummary(
        id: 'set-a',
        description: 'Bench Press - 100 kg x 5',
      );
      final setB = const HomeSetSummary(
        id: 'set-b',
        description: 'Bench Press - 110 kg x 3',
      );
      final exerciseA = HomeWorkoutExerciseSummary(
        id: 'workout-exercise-a',
        workoutId: 'workout-a',
        exerciseId: 'exercise-a',
        name: 'Bench Press',
        type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
        sets: <HomeSetSummary>[setA],
      );
      final exerciseB = HomeWorkoutExerciseSummary(
        id: 'workout-exercise-b',
        workoutId: 'workout-b',
        exerciseId: 'exercise-b',
        name: 'Squat',
        type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
        sets: <HomeSetSummary>[setB],
      );
      final nestedExercises = <HomeWorkoutExerciseSummary>[exerciseA];
      final group = HomeExerciseGroupSummary(
        id: 'group-a',
        name: 'Superset 1',
        colorHex: '#2F6FED',
        workoutExerciseIds: <String>[
          'workout-exercise-a',
          'workout-exercise-b',
        ],
      );
      final exerciseGroups = <HomeExerciseGroupSummary>[group];
      final workoutA = HomeWorkoutSummary(
        id: 'workout-a',
        startedAt: DateTime.utc(2026, 6, 16, 8),
        localDate: const TrainingDayDate(year: 2026, month: 6, day: 16),
        workoutExercises: nestedExercises,
        exerciseGroups: exerciseGroups,
      );
      final workoutB = HomeWorkoutSummary(
        id: 'workout-b',
        startedAt: DateTime.utc(2026, 6, 17, 8),
        localDate: const TrainingDayDate(year: 2026, month: 6, day: 17),
        workoutExercises: <HomeWorkoutExerciseSummary>[exerciseB],
      );
      final workouts = <HomeWorkoutSummary>[workoutA];
      final workoutExercises = <HomeWorkoutExerciseSummary>[exerciseA];
      final exercises = <HomeExerciseSummary>[
        const HomeExerciseSummary(id: 'exercise-a', name: 'Bench Press'),
      ];
      final sets = <HomeSetSummary>[setA];

      final summary = HomeSummary(
        title: 'Training Day',
        selectedDate: const TrainingDayDate(year: 2026, month: 6, day: 16),
        status: '1 workout, 1 set',
        workouts: workouts,
        workoutExercises: workoutExercises,
        exercises: exercises,
        sets: sets,
      );

      nestedExercises.add(exerciseB);
      exerciseGroups.clear();
      workouts.add(workoutB);
      workoutExercises.add(exerciseB);
      exercises.add(const HomeExerciseSummary(id: 'exercise-b', name: 'Squat'));
      sets.add(setB);

      expect(workoutA.workoutExercises, <HomeWorkoutExerciseSummary>[
        exerciseA,
      ]);
      expect(workoutA.exerciseGroups, <HomeExerciseGroupSummary>[group]);
      expect(summary.workouts, <HomeWorkoutSummary>[workoutA]);
      expect(
        summary.workoutExercises,
        <HomeWorkoutExerciseSummary>[exerciseA],
      );
      expect(summary.exercises.map((exercise) => exercise.id), <String>[
        'exercise-a',
      ]);
      expect(summary.sets, <HomeSetSummary>[setA]);
      expect(
        () => workoutA.workoutExercises.add(exerciseB),
        throwsUnsupportedError,
      );
      expect(
        () => workoutA.exerciseGroups.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => group.workoutExerciseIds.add('workout-exercise-c'),
        throwsUnsupportedError,
      );
      expect(() => exerciseA.sets.add(setB), throwsUnsupportedError);
      expect(() => summary.workouts.add(workoutB), throwsUnsupportedError);
      expect(
        () => summary.workoutExercises.clear(),
        throwsUnsupportedError,
      );
      expect(() => summary.exercises.clear(), throwsUnsupportedError);
      expect(() => summary.sets.add(setB), throwsUnsupportedError);
    });
  });

  group('RepositoryHomeRepository progress', () {
    final warnAboutMultipleDatabases =
        driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    const trainingDay = TrainingDayDate(year: 2026, month: 7, day: 12);

    late AppDatabase database;
    late TrainingRepositories repositories;
    late RepositoryHomeRepository homeRepository;

    setUpAll(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    });

    tearDownAll(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases =
          warnAboutMultipleDatabases;
    });

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(
        database,
        platformSeedSource: const _EmptySeedSource(),
      );
      homeRepository = RepositoryHomeRepository(repositories);
    });

    tearDown(() async {
      await database.close();
    });

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

    /// Starts a Template named [name] with one exercise planned for
    /// [plannedSets] Sets on [trainingDay]; returns the Workout's id.
    Future<({String workoutId, String templateId})> startTemplate(
      String name, {
      int plannedSets = 3,
    }) async {
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: '$name Press',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
          defaultLoadUnit: TrainingUnit.kilogram,
        ),
      );
      final templateId = await repositories.workoutTemplates.create(
        WorkoutTemplateDraft(name: name),
      );
      final templateExerciseId = await repositories.workoutTemplates
          .addExercise(templateId, exerciseId);
      await repositories.workoutTemplates.addPrescription(
        templateExerciseId,
        PrescriptionDraft(
          mode: PrescriptionMode.fixed,
          values: weightReps('60', '8'),
          repeat: plannedSets,
        ),
      );
      final result = await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(workoutTemplateId: templateId),
        now: DateTime(2026, 7, 12, 8),
      );
      return (workoutId: result.workoutId, templateId: templateId);
    }

    Future<HomeWorkoutSummary> firstWorkoutWhere(
      Stream<HomeWorkoutSummary?> stream,
      bool Function(HomeWorkoutSummary workout) condition,
    ) {
      return stream
          .where((workout) => workout != null && condition(workout))
          .cast<HomeWorkoutSummary>()
          .first
          .timeout(const Duration(seconds: 5));
    }

    Future<HomeSummary> firstDayWhere(
      Stream<HomeSummary> stream,
      bool Function(HomeSummary summary) condition,
    ) {
      return stream.where(condition).first.timeout(const Duration(seconds: 5));
    }

    test(
        'templateName follows the Template Link, re-emits on a rename and '
        'survives archiving the Template', () async {
      final started = await startTemplate('Upper B');
      final emissions =
          homeRepository.watchWorkout(started.workoutId).asBroadcastStream();
      final subscription = emissions.listen((_) {});
      addTearDown(subscription.cancel);

      final first = await firstWorkoutWhere(
        emissions,
        (workout) => workout.workoutExercises.isNotEmpty,
      );
      expect(first.templateName, 'Upper B');

      await repositories.workoutTemplates.updateTemplate(
        started.templateId,
        name: 'Upper Body B',
      );
      final renamed = await firstWorkoutWhere(
        emissions,
        (workout) => workout.templateName == 'Upper Body B',
      );
      expect(renamed.id, started.workoutId);

      await repositories.workoutTemplates.archive(started.templateId);
      final afterArchive = await firstWorkoutWhere(
        homeRepository.watchWorkout(started.workoutId),
        (workout) => workout.workoutExercises.isNotEmpty,
      );
      expect(afterArchive.templateName, 'Upper Body B');
    });

    test('templateName is null for a Workout with no Template Link', () async {
      final started = await startTemplate('Upper B');
      final emptyWorkoutId = await homeRepository.startNewWorkout(trainingDay);

      final day = await firstDayWhere(
        homeRepository.watchTrainingDay(trainingDay),
        (summary) => summary.workouts.length == 2,
      );
      final byId = <String, HomeWorkoutSummary>{
        for (final workout in day.workouts) workout.id: workout,
      };
      expect(byId[started.workoutId]!.templateName, 'Upper B');
      expect(byId[emptyWorkoutId]!.templateName, isNull);
    });

    test('performed counts split Performed from Planned Sets', () async {
      final started = await startTemplate('Upper B');
      final exerciseId = (await repositories.workoutExercises
              .listActiveForWorkout(started.workoutId))
          .single
          .exerciseId;
      final sets = await repositories.sets.listActiveForWorkout(
        started.workoutId,
      );
      await repositories.sets.setCompleted(sets[0].id, isCompleted: true);
      // Later than the stamp the first Set got when it was written, so it is
      // the latest Performed Set.
      final performedAt = DateTime.utc(2099, 1, 1, 8, 30);
      final extraSetId = await repositories.sets.create(
        LoggedSetDraft(
          workoutId: started.workoutId,
          exerciseId: exerciseId,
          position: 3,
          values: weightReps('60', '6'),
          performedAt: performedAt,
          isCompleted: true,
        ),
      );

      final workout = await firstWorkoutWhere(
        homeRepository.watchWorkout(started.workoutId),
        (workout) => workout.setCount == 4,
      );
      final exercise = workout.workoutExercises.single;
      expect(exercise.setCount, 4);
      expect(exercise.performedCount, 2);
      expect(exercise.plannedCount, 2);
      expect(workout.performedSetCount, 2);
      expect(
        exercise.sets.singleWhere((set) => set.id == extraSetId).performedAt,
        performedAt,
      );
      expect(exercise.latestPerformedAt, performedAt);
    });

    test(
        'the day line counts only Workouts with a Performed Set, and their '
        'Performed Sets', () async {
      final started = await startTemplate('Upper B');
      final emissions =
          homeRepository.watchTrainingDay(trainingDay).asBroadcastStream();
      final subscription = emissions.listen((_) {});
      addTearDown(subscription.cancel);

      final planned = await firstDayWhere(
        emissions,
        (summary) => summary.sets.length == 3,
      );
      expect(planned.status, 'No workout started');

      final sets = await repositories.sets.listActiveForWorkout(
        started.workoutId,
      );
      await repositories.sets.setCompleted(sets[0].id, isCompleted: true);
      final one = await firstDayWhere(
        emissions,
        (summary) => summary.status != 'No workout started',
      );
      expect(one.status, '1 workout - 1 set');

      await homeRepository.startNewWorkout(trainingDay);
      await repositories.sets.setCompleted(sets[1].id, isCompleted: true);
      final two = await firstDayWhere(
        emissions,
        (summary) =>
            summary.workouts.length == 2 &&
            summary.status != '1 workout - 1 set',
      );
      expect(two.status, '1 workout - 2 sets');
    });
  });
}

class _EmptySeedSource implements PlatformExerciseSeedSource {
  const _EmptySeedSource();

  @override
  Future<PlatformExerciseSeed> load() async {
    return const PlatformExerciseSeed(
      categories: <SeedExerciseCategory>[],
      exercises: <SeedExercise>[],
    );
  }
}
