import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/template_picker/repositories/template_picker_feature_repository.dart';

void main() {
  late AppDatabase database;
  late TrainingRepositories repositories;
  late RepositoryTemplatePickerFeatureRepository adapter;

  setUp(() {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(database);
    adapter = RepositoryTemplatePickerFeatureRepository(repositories);
  });

  tearDown(() => database.close());

  group('watchAllTemplates', () {
    test('emits active Templates only, never archived ones', () async {
      final activeId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Push A'),
      );
      final archivedId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Old Pull'),
      );
      await repositories.workoutTemplates.archive(archivedId);

      final templates = await adapter.watchAllTemplates().first;

      expect(templates.map((t) => t.id), <String>[activeId]);
      expect(templates.single.name, 'Push A');
    });
  });

  group('watchRoutines', () {
    test(
        'groups entries under every Routine that references a Template, '
        'reference semantics made visible (not deduplicated)', () async {
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Push A'),
      );
      final routineOneId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Weekly split'),
      );
      final routineTwoId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Travel favourites'),
      );
      final routineThreeId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Deload block'),
      );
      await repositories.routinePlans.addTemplateReference(
        routineOneId,
        templateId,
      );
      await repositories.routinePlans.addTemplateReference(
        routineTwoId,
        templateId,
      );
      await repositories.routinePlans.addTemplateReference(
        routineThreeId,
        templateId,
      );

      final routines = await adapter.watchRoutines().first;

      expect(routines, hasLength(3));
      for (final routine in routines) {
        expect(routine.entries.single.workoutTemplateId, templateId);
      }
    });

    test('excludes entries referencing an archived Template', () async {
      final activeId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Push A'),
      );
      final archivedId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Old Pull'),
      );
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Weekly split'),
      );
      await repositories.routinePlans.addTemplateReference(
        routineId,
        activeId,
      );
      await repositories.routinePlans.addTemplateReference(
        routineId,
        archivedId,
      );
      await repositories.workoutTemplates.archive(archivedId);

      final routines = await adapter.watchRoutines().first;

      expect(routines.single.entries.single.workoutTemplateId, activeId);
    });

    test('drops a Routine entirely once every entry is archived', () async {
      final archivedId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Old Pull'),
      );
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Weekly split'),
      );
      await repositories.routinePlans.addTemplateReference(
        routineId,
        archivedId,
      );
      await repositories.workoutTemplates.archive(archivedId);

      final routines = await adapter.watchRoutines().first;

      expect(routines, isEmpty);
    });

    test('surfaces the Cadence kind and slot layout for a cadenced Routine',
        () async {
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Push A'),
      );
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Weekly split'),
      );
      await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.weekly(),
      );
      await repositories.routinePlans.addTemplateReference(
        routineId,
        templateId,
        slot: DateTime.monday,
      );

      final routine = (await adapter.watchRoutines().first).single;

      expect(routine.cadenceKind, CadenceKind.weekly);
      expect(routine.entries.single.slot, DateTime.monday);
    });

    test('a cadence-less collection carries a null cadenceKind and no slots',
        () async {
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Push A'),
      );
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Travel favourites'),
      );
      await repositories.routinePlans.addTemplateReference(
        routineId,
        templateId,
      );

      final routine = (await adapter.watchRoutines().first).single;

      expect(routine.cadenceKind, isNull);
      expect(routine.entries.single.slot, isNull);
    });

    test('excludes archived Routines', () async {
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Retired block'),
      );
      await repositories.routinePlans.archive(routineId);

      final routines = await adapter.watchRoutines().first;

      expect(routines, isEmpty);
    });
  });
}
