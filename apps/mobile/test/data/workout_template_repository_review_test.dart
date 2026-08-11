import 'package:drift/drift.dart' show OrderingTerm, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  final previousMultipleDatabaseWarning =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        previousMultipleDatabaseWarning;
  });

  group('Workout Template repository review regressions', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('archiving a populated template changes only the template row',
        () async {
      final benchId = await _createExercise(
        repositories,
        name: 'Bench Press',
        dimensions: const <DimensionId>[
          DimensionId.load,
          DimensionId.reps,
        ],
      );
      final plankId = await _createExercise(
        repositories,
        name: 'Plank',
        dimensions: const <DimensionId>[DimensionId.duration],
      );
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Populated Push'),
      );
      final benchEntryId = await repositories.workoutTemplates.addExercise(
        templateId,
        benchId,
      );
      final plankEntryId = await repositories.workoutTemplates.addExercise(
        templateId,
        plankId,
      );
      final benchPrescriptionId =
          await repositories.workoutTemplates.addPrescription(
        benchEntryId,
        PrescriptionDraft(
          mode: PrescriptionMode.fixed,
          values: _loadReps(load: '90', reps: '5'),
          repeat: 3,
        ),
      );
      final plankPrescriptionId =
          await repositories.workoutTemplates.addPrescription(
        plankEntryId,
        PrescriptionDraft(
          mode: PrescriptionMode.fixed,
          values: LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.duration,
                entered: '60',
                unit: TrainingUnit.second,
              ),
            ],
          ),
          repeat: 2,
        ),
      );
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 7, 11, 8),
          timezone: 'UTC',
        ),
      );
      await database.into(database.templateLinks).insert(
            TemplateLinksCompanion.insert(
              id: 'archive-no-cascade-link',
              workoutId: workoutId,
              workoutTemplateId: templateId,
              updatedAt: DateTime.utc(2026, 7, 11, 8, 1),
            ),
          );

      await repositories.workoutTemplates.archive(
        templateId,
        actor: 'review-test',
        batchId: 'archive-populated-template',
      );

      final template = await (database.select(database.workoutTemplates)
            ..where((row) => row.id.equals(templateId)))
          .getSingle();
      final entries = await (database.select(database.templateExercises)
            ..where((row) => row.workoutTemplateId.equals(templateId)))
          .get();
      final prescriptions = await (database.select(database.prescriptions)
            ..where(
              (row) => row.id.isIn(
                <String>{benchPrescriptionId, plankPrescriptionId},
              ),
            ))
          .get();
      final link = await (database.select(database.templateLinks)
            ..where((row) => row.id.equals('archive-no-cascade-link')))
          .getSingle();

      expect(template.deletedAt, isNotNull);
      expect(entries.map((entry) => entry.id).toSet(), <String>{
        benchEntryId,
        plankEntryId,
      });
      expect(entries.every((entry) => entry.deletedAt == null), isTrue);
      expect(prescriptions, hasLength(2));
      expect(
        prescriptions.every((prescription) => prescription.deletedAt == null),
        isTrue,
      );
      expect(link.deletedAt, isNull);
      expect(
        await repositories.workoutTemplates.getById(
          templateId,
          includeArchived: false,
        ),
        isNull,
      );
      final archivedDetail =
          await repositories.workoutTemplates.getById(templateId);
      expect(
        archivedDetail!.exercises.map((entry) => entry.id).toSet(),
        <String>{benchEntryId, plankEntryId},
      );
      expect(
        archivedDetail.exercises
            .expand((entry) => entry.prescriptions)
            .map((prescription) => prescription.id)
            .toSet(),
        <String>{benchPrescriptionId, plankPrescriptionId},
      );

      final archiveEntries = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == 'archive-populated-template')
          .toList(growable: false);
      expect(archiveEntries, hasLength(1));
      expect(archiveEntries.single.actor, 'review-test');
      expect(
        archiveEntries.single.entityTable,
        AppDatabase.workoutTemplatesTable,
      );
      expect(archiveEntries.single.beforeImage, containsPair('id', templateId));
      expect(archiveEntries.single.beforeImage?['deleted_at'], isNull);
      expect(archiveEntries.single.afterImage?['deleted_at'], isNotNull);

      await repositories.workoutTemplates.restore(templateId);
      final restored = await repositories.workoutTemplates.getById(templateId);
      expect(
        restored!.exercises.map((entry) => entry.id).toSet(),
        <String>{benchEntryId, plankEntryId},
      );
      expect(
        restored.exercises
            .expand((entry) => entry.prescriptions)
            .map((prescription) => prescription.id)
            .toSet(),
        <String>{benchPrescriptionId, plankPrescriptionId},
      );
    });

    test('a mid-reorder database failure rolls back rows and Activity Log',
        () async {
      final exerciseIds = <String>[
        await _createExercise(
          repositories,
          name: 'Exercise A',
          dimensions: const <DimensionId>[DimensionId.reps],
        ),
        await _createExercise(
          repositories,
          name: 'Exercise B',
          dimensions: const <DimensionId>[DimensionId.reps],
        ),
        await _createExercise(
          repositories,
          name: 'Exercise C',
          dimensions: const <DimensionId>[DimensionId.reps],
        ),
      ];
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Atomic reorder'),
      );
      final entryIds = <String>[];
      for (final exerciseId in exerciseIds) {
        entryIds.add(
          await repositories.workoutTemplates.addExercise(
            templateId,
            exerciseId,
          ),
        );
      }
      final beforeRows = await _templateExerciseImages(database, templateId);
      final blockedId = entryIds.first;
      await database.customStatement('''
        CREATE TRIGGER fail_second_template_exercise_reorder
        BEFORE UPDATE OF position ON template_exercises
        WHEN NEW.id = '$blockedId'
        BEGIN
          SELECT RAISE(ABORT, 'forced reorder failure');
        END;
      ''');

      await expectLater(
        repositories.workoutTemplates.reorderExercises(
          templateId,
          <String>[entryIds[2], entryIds[1], entryIds[0]],
          actor: 'review-test',
          batchId: 'rolled-back-reorder',
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );

      expect(await _templateExerciseImages(database, templateId), beforeRows);
      expect(
        (await repositories.activityLog.listEntries())
            .where((entry) => entry.batchId == 'rolled-back-reorder'),
        isEmpty,
      );

      await database.customStatement(
        'DROP TRIGGER fail_second_template_exercise_reorder',
      );
      await repositories.workoutTemplates.reorderExercises(
        templateId,
        <String>[entryIds[2], entryIds[1], entryIds[0]],
        actor: 'review-test',
        batchId: 'successful-reorder',
      );
      final afterRows = await _templateExerciseImages(database, templateId);
      expect(afterRows[entryIds[2]]?['position'], 0);
      expect(afterRows[entryIds[1]]?['position'], 1);
      expect(afterRows[entryIds[0]]?['position'], 2);

      final activityEntries = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == 'successful-reorder')
          .toList(growable: false);
      expect(activityEntries, hasLength(2));
      expect(activityEntries.map((entry) => entry.actor).toSet(), {
        'review-test',
      });
      expect(activityEntries.map((entry) => entry.entityTable).toSet(), {
        AppDatabase.templateExercisesTable,
      });
      expect(activityEntries.map((entry) => entry.occurredAt).toSet(),
          hasLength(1));
      for (final entry in activityEntries) {
        expect(entry.beforeImage, containsPair('id', entry.entityId));
        expect(entry.afterImage, containsPair('id', entry.entityId));
        expect(
          entry.beforeImage?['position'],
          isNot(entry.afterImage?['position']),
        );
      }
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

Future<Map<String, Map<String, Object?>>> _templateExerciseImages(
  AppDatabase database,
  String templateId,
) async {
  final rows = await (database.select(database.templateExercises)
        ..where((row) => row.workoutTemplateId.equals(templateId))
        ..orderBy([(row) => OrderingTerm.asc(row.id)]))
      .get();
  return <String, Map<String, Object?>>{
    for (final row in rows)
      row.id: <String, Object?>{
        'position': row.position,
        'updated_at': row.updatedAt.toUtc(),
        'deleted_at': row.deletedAt?.toUtc(),
      },
  };
}
