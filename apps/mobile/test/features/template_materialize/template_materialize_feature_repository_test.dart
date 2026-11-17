import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/template_materialize/repositories/template_materialize_feature_repository.dart';

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

  late AppDatabase database;
  late TrainingRepositories repositories;
  late RepositoryTemplateMaterializeFeatureRepository repository;

  setUp(() {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(database);
    repository = RepositoryTemplateMaterializeFeatureRepository(repositories);
  });

  tearDown(() async {
    await database.close();
  });

  Future<String> createExercise() {
    return repositories.exercises.create(
      ExerciseDraft(
        name: 'Goblet Squat',
        type: ExerciseType(const [DimensionId.load, DimensionId.reps]),
        defaultLoadUnit: TrainingUnit.kilogram,
      ),
    );
  }

  group('empty Workout Templates', () {
    test('only active Templates with no active Template Exercises are empty',
        () async {
      final exerciseId = await createExercise();
      final emptyId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(
          name: 'Friday — Functional Strength',
          notes: 'Skill: single-leg box squat. Power: kettlebell swings.',
        ),
      );
      final plannedId = await repositories.workoutTemplates
          .create(const WorkoutTemplateDraft(name: 'Lifting A'));
      await repositories.workoutTemplates.addExercise(plannedId, exerciseId);
      final archivedEmptyId = await repositories.workoutTemplates
          .create(const WorkoutTemplateDraft(name: 'Old placeholder'));
      await repositories.workoutTemplates.archive(archivedEmptyId);

      expect(await repository.watchEmptyTemplateIds().first, {emptyId});
      expect(
        await repository.emptyTemplateName(emptyId),
        'Friday — Functional Strength',
      );
      expect(await repository.emptyTemplateName(plannedId), isNull);
      expect(await repository.emptyTemplateName(archivedEmptyId), isNull);
    });

    test('a Template whose only Template Exercise was removed is empty again',
        () async {
      final exerciseId = await createExercise();
      final templateId = await repositories.workoutTemplates
          .create(const WorkoutTemplateDraft(name: 'Lifting B'));
      final templateExerciseId = await repositories.workoutTemplates
          .addExercise(templateId, exerciseId);
      expect(await repository.emptyTemplateName(templateId), isNull);

      await repositories.workoutTemplates.removeExercise(templateExerciseId);

      expect(await repository.emptyTemplateName(templateId), 'Lifting B');
      expect(await repository.watchEmptyTemplateIds().first, {templateId});
    });
  });

  group('linked Template guidance', () {
    test(
        "shows the linked Template's notes live, without copying them onto "
        'the Workout', () async {
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(
          name: 'Friday — Functional Strength',
          notes: '  Keep skill work before conditioning.  ',
        ),
      );
      final workoutId = await repository.materializeTemplate(
        workoutTemplateId: templateId,
      );

      expect(
        await repository.watchTemplateGuidance(workoutId).first,
        const WorkoutTemplateGuidance(
          templateName: 'Friday — Functional Strength',
          notes: 'Keep skill work before conditioning.',
        ),
      );
      final workout = await repositories.workoutSessions.getById(workoutId);
      expect(workout?.comment, isNull);

      await repositories.workoutTemplates.updateTemplate(
        templateId,
        name: 'Friday — Functional Strength',
        notes: 'Swings first.',
      );
      expect(
        (await repository.watchTemplateGuidance(workoutId).first)?.notes,
        'Swings first.',
      );
    });

    test('is null for an unlinked Workout or a Template without notes',
        () async {
      final templateId = await repositories.workoutTemplates
          .create(const WorkoutTemplateDraft(name: 'No notes'));
      final linkedWorkoutId = await repository.materializeTemplate(
        workoutTemplateId: templateId,
      );
      final now = DateTime(2026, 10, 30, 18);
      final unlinkedWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: now,
          timezone: 'UTC',
          localDate: TrainingDayDate.fromDateTime(now),
        ),
      );

      expect(
        await repository.watchTemplateGuidance(linkedWorkoutId).first,
        isNull,
      );
      expect(
        await repository.watchTemplateGuidance(unlinkedWorkoutId).first,
        isNull,
      );
    });
  });
}
