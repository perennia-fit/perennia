import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_dimensions.dart';

void main() {
  final previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
  });

  group('WorkoutTemplateRepository Template Groups', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() => database.close());

    test('creates, updates, watches, and dissolves an offline group tree',
        () async {
      final fixture = await _createTemplateFixture(repositories, count: 3);
      final firstGroupEmission = repositories.workoutTemplates
          .watchById(fixture.templateId)
          .firstWhere((record) => record?.groups.isNotEmpty ?? false);

      final groupId = await repositories.workoutTemplates.createTemplateGroup(
        fixture.templateId,
        TemplateGroupDraft(
          name: '  Hyrox pair  ',
          colorHex: ' #0891b2 ',
          rounds: 3,
          orderedTemplateExerciseIds: fixture.entryIds.take(2),
        ),
        actor: 'tester',
        batchId: 'create-template-group',
      );
      final created = (await firstGroupEmission)!.groups.single;
      expect(created.id, groupId);
      expect(created.name, 'Hyrox pair');
      expect(created.colorHex, '#0891B2');
      expect(created.rounds, 3);
      expect(created.position, 0);
      expect(
        created.members.map((member) => member.templateExerciseId),
        fixture.entryIds.take(2),
      );
      final createLogs = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == 'create-template-group')
          .toList(growable: false);
      expect(createLogs, hasLength(3));
      expect(
        createLogs.map((entry) => entry.entityTable),
        containsAll(<String>[
          AppDatabase.templateGroupsTable,
          AppDatabase.templateGroupMembersTable,
        ]),
      );

      await repositories.workoutTemplates.updateTemplateGroup(
        groupId,
        TemplateGroupDraft(
          name: 'Run + sled',
          colorHex: '#E06C5A',
          rounds: 4,
          orderedTemplateExerciseIds: <String>[
            fixture.entryIds[2],
            fixture.entryIds[1],
          ],
        ),
        batchId: 'update-template-group',
      );
      final updated =
          (await repositories.workoutTemplates.getById(fixture.templateId))!
              .groups
              .single;
      expect(updated.name, 'Run + sled');
      expect(updated.rounds, 4);
      expect(
        updated.members.map((member) => member.templateExerciseId),
        <String>[fixture.entryIds[2], fixture.entryIds[1]],
      );

      await expectLater(
        repositories.workoutTemplates.removeExercise(fixture.entryIds[1]),
        throwsA(isA<TemplateExerciseGroupedException>()),
      );

      final groupBeforeArchive =
          await database.select(database.templateGroups).getSingle();
      final membersBeforeArchive =
          await database.select(database.templateGroupMembers).get();
      await repositories.workoutTemplates.archive(fixture.templateId);
      expect(
        await database.select(database.templateGroups).getSingle(),
        groupBeforeArchive,
      );
      expect(
        await database.select(database.templateGroupMembers).get(),
        membersBeforeArchive,
      );
      await repositories.workoutTemplates.restore(fixture.templateId);

      await repositories.workoutTemplates.dissolveTemplateGroup(
        groupId,
        batchId: 'dissolve-template-group',
      );
      expect(
        (await database.select(database.templateGroups).getSingle()).deletedAt,
        isNotNull,
      );
      final activeMembers =
          await (database.select(database.templateGroupMembers)
                ..where((row) => row.deletedAt.isNull()))
              .get();
      expect(activeMembers, isEmpty);
      final detail =
          await repositories.workoutTemplates.getById(fixture.templateId);
      expect(detail?.groups, isEmpty);
      expect(detail?.exercises, hasLength(3));

      final undo = await repositories.activityLog.undoBatch(
        'dissolve-template-group',
      );
      expect(undo.hasConflicts, isFalse);
      expect(
        (await repositories.workoutTemplates.getById(fixture.templateId))!
            .groups
            .single
            .members,
        hasLength(2),
      );
    });

    test('enforces graph invariants, reorders, and preflights undo uniqueness',
        () async {
      final fixture = await _createTemplateFixture(repositories, count: 4);
      final firstGroupId =
          await repositories.workoutTemplates.createTemplateGroup(
        fixture.templateId,
        TemplateGroupDraft(
          name: 'A',
          colorHex: '#4A8FE0',
          rounds: 1,
          orderedTemplateExerciseIds: fixture.entryIds.take(2),
        ),
      );
      final secondGroupId =
          await repositories.workoutTemplates.createTemplateGroup(
        fixture.templateId,
        TemplateGroupDraft(
          name: 'B',
          colorHex: '#5FB05C',
          rounds: 2,
          orderedTemplateExerciseIds: fixture.entryIds.skip(2),
        ),
      );

      await repositories.workoutTemplates.reorderTemplateGroups(
        fixture.templateId,
        <String>[secondGroupId, firstGroupId],
      );
      expect(
        (await repositories.workoutTemplates.getById(fixture.templateId))!
            .groups
            .map((group) => group.id),
        <String>[secondGroupId, firstGroupId],
      );

      final logCount = (await repositories.activityLog.listEntries()).length;
      await expectLater(
        repositories.workoutTemplates.createTemplateGroup(
          fixture.templateId,
          TemplateGroupDraft(
            name: 'Invalid overlap',
            colorHex: '#E0A23F',
            rounds: 1,
            orderedTemplateExerciseIds: <String>[
              fixture.entryIds[1],
              fixture.entryIds[2],
            ],
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repositories.workoutTemplates.createTemplateGroup(
          fixture.templateId,
          TemplateGroupDraft(
            name: '',
            colorHex: 'blue',
            rounds: 0,
            orderedTemplateExerciseIds: const <String>['', ''],
          ),
        ),
        throwsA(isA<SetValidationException>()),
      );
      expect((await repositories.activityLog.listEntries()).length, logCount);

      await repositories.workoutTemplates.dissolveTemplateGroup(
        firstGroupId,
        batchId: 'dissolve-for-regroup',
      );
      expect(
        (await repositories.workoutTemplates.getById(fixture.templateId))!
            .groups
            .single
            .position,
        0,
      );
      await repositories.workoutTemplates.createTemplateGroup(
        fixture.templateId,
        TemplateGroupDraft(
          name: 'Replacement',
          colorHex: '#A06CD5',
          rounds: 5,
          orderedTemplateExerciseIds: fixture.entryIds.take(2),
        ),
      );
      final undo = await repositories.activityLog.undoBatch(
        'dissolve-for-regroup',
      );
      expect(undo.hasConflicts, isTrue);
      expect(
        undo.conflicts.map((conflict) => conflict.entityTable),
        contains(AppDatabase.templateGroupMembersTable),
      );
    });
  });
}

Future<({String templateId, List<String> entryIds})> _createTemplateFixture(
  TrainingRepositories repositories, {
  required int count,
}) async {
  final templateId = await repositories.workoutTemplates.create(
    const WorkoutTemplateDraft(name: 'Hybrid day'),
  );
  final entryIds = <String>[];
  for (var index = 0; index < count; index += 1) {
    final exerciseId = await repositories.exercises.create(
      ExerciseDraft(
        name: 'Station ${index + 1}',
        type: ExerciseType(
          const <DimensionId>[DimensionId.duration],
        ),
      ),
    );
    entryIds.add(
      await repositories.workoutTemplates.addExercise(
        templateId,
        exerciseId,
      ),
    );
  }
  return (templateId: templateId, entryIds: entryIds);
}
