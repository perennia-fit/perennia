import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  final previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
  });

  group('WorkoutCaptureRepository', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() => database.close());

    test(
        'previews and saves a lossless new identity without touching source facts',
        () async {
      final source = await _createRichSource(repositories, database);
      final sourceBefore = await _sourceImages(database, source.workoutId);

      final preview = await repositories.workoutCapture.preview(
        source.workoutId,
      );
      expect(preview.workoutId, source.workoutId);
      expect(preview.suggestedName, 'Dumbbell Press + Cable Row');
      expect(preview.exerciseCount, 3);
      expect(preview.setCount, 3);
      expect(preview.groupCount, 1);
      expect(preview.validation.accepted, isTrue);
      expect(preview.validation.warnings, isEmpty);
      expect(
        preview.content.exercises.first.prescriptions.single.repeat,
        2,
      );
      expect(
        preview.content.exercises.first.prescriptions.single.restAfter,
        const Duration(seconds: 90),
      );
      expect(preview.content.exercises.last.prescriptions, isEmpty);
      expect(preview.content.groups.single.memberExerciseIndexes, <int>[1, 0]);
      expect(CapturedTemplateGroupContent.rounds, 1);

      final result = await repositories.workoutCapture.save(
        WorkoutCaptureSaveRequest(
          workoutId: source.workoutId,
          name: '  Captured upper  ',
        ),
        actor: 'test',
        batchId: 'capture-no-placement',
      );
      expect(result.activityBatchId, 'capture-no-placement');
      expect(result.routineEntryId, isNull);
      expect(result.workoutTemplateId, isNot(source.linkedTemplateId));

      final captured = (await repositories.workoutTemplates.getById(
        result.workoutTemplateId,
      ))!;
      expect(captured.name, 'Captured upper');
      expect(captured.notes, isNull);
      expect(
        captured.exercises.map((exercise) => exercise.exerciseId),
        <String>[
          source.pressExerciseId,
          source.rowExerciseId,
          source.zeroExerciseId
        ],
      );
      expect(captured.exercises.every((exercise) => exercise.note == null),
          isTrue);
      expect(captured.exercises.first.exercise.deletedAt, isNotNull);
      final pressPrescription = captured.exercises.first.prescriptions.single;
      expect(pressPrescription.mode, PrescriptionMode.fixed);
      expect(pressPrescription.repeat, 2);
      expect(pressPrescription.values.load?.entered, '32.5');
      expect(pressPrescription.values.load?.unit, TrainingUnit.kilogram);
      expect(pressPrescription.restAfter, const Duration(seconds: 90));
      expect(captured.exercises[1].prescriptions.single.repeat, 1);
      expect(captured.exercises.last.prescriptions, isEmpty);
      expect(captured.groups.single.rounds, 1);
      expect(
        captured.groups.single.members
            .map((member) => member.templateExerciseId),
        <String>[captured.exercises[1].id, captured.exercises[0].id],
      );

      expect(await _sourceImages(database, source.workoutId), sourceBefore);
      final sourceLink = await (database.select(database.templateLinks)
            ..where((row) => row.id.equals(source.templateLinkId)))
          .getSingle();
      expect(sourceLink.workoutTemplateId, source.linkedTemplateId);
      expect(sourceLink.deletedAt, isNull);

      final batchEntries = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == result.activityBatchId)
          .toList(growable: false);
      expect(batchEntries, hasLength(9));
      expect(
        batchEntries.map((entry) => entry.entityTable).toSet(),
        <String>{
          AppDatabase.workoutTemplatesTable,
          AppDatabase.templateExercisesTable,
          AppDatabase.prescriptionsTable,
          AppDatabase.templateGroupsTable,
          AppDatabase.templateGroupMembersTable,
        },
      );
      expect(
        batchEntries.every(
          (entry) => entry.beforeImage == null && entry.afterImage != null,
        ),
        isTrue,
      );
    });

    test(
        'persists lossless expansion for every dimension, exact text, units, and rest',
        () async {
      final source = await _createAllDimensionSource(repositories);
      final sourceSets = await repositories.sets.listActiveForWorkout(
        source.workoutId,
      );
      final sourceProjection = sourceSets
          .map(
            (set) => WorkoutCaptureSetProjection(
              values: set.values,
              plannedRestAfter: set.plannedRestAfter,
            ),
          )
          .toList(growable: false);

      final result = await repositories.workoutCapture.save(
        WorkoutCaptureSaveRequest(
          workoutId: source.workoutId,
          name: 'All dimensions',
        ),
        batchId: 'capture-all-dimensions',
      );
      final captured = (await repositories.workoutTemplates.getById(
        result.workoutTemplateId,
      ))!;
      final prescriptions = captured.exercises.single.prescriptions;
      expect(prescriptions.map((prescription) => prescription.repeat),
          <int>[2, 1, 1]);
      final persistedExpansion = prescriptions
          .expand(
            (prescription) => List<WorkoutCaptureSetProjection>.filled(
              prescription.repeat,
              WorkoutCaptureSetProjection(
                values: prescription.values,
                plannedRestAfter: prescription.restAfter,
              ),
            ),
          )
          .toList(growable: false);
      expect(persistedExpansion, sourceProjection);
      expect(persistedExpansion[0].values.load?.entered, '100');
      expect(persistedExpansion[2].values.load?.entered, '220.46');
      expect(persistedExpansion[2].values.load?.unit, TrainingUnit.pound);
      expect(persistedExpansion[2].values.distance?.entered, '0.62');
      expect(persistedExpansion[2].values.distance?.unit, TrainingUnit.mile);
      expect(persistedExpansion[3].values.load?.entered, '100.0');
      expect(
          persistedExpansion[2].plannedRestAfter, const Duration(seconds: 90));
    });

    test('group validation keeps shared order with deterministic field paths',
        () async {
      final source = await _createRichSource(repositories, database);
      final group = await (database.select(database.exerciseGroups)
            ..where((row) => row.workoutId.equals(source.workoutId)))
          .getSingle();
      await (database.update(database.exerciseGroups)
            ..where((row) => row.id.equals(group.id)))
          .write(
        ExerciseGroupsCompanion(
          name: const Value<String>('   '),
          colorHex: const Value<String>('blue'),
          updatedAt: Value<DateTime>(DateTime.utc(2026, 7, 11, 12)),
        ),
      );

      final preview = await repositories.workoutCapture.preview(
        source.workoutId,
      );
      expect(preview.validation.accepted, isFalse);
      expect(
        preview.validation.errors.map(
          (issue) => '${issue.fieldPath}:${issue.rule}',
        ),
        <String>[
          'groups[0].name:template_group_name_required',
          'groups[0].colorHex:template_group_color_hex',
        ],
      );
    });

    test('historical Set dimensions survive a later Exercise Type change',
        () async {
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Run then changed',
          type: ExerciseType(
            const <DimensionId>[DimensionId.distance, DimensionId.duration],
          ),
        ),
      );
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 7, 1, 8),
          timezone: 'UTC',
        ),
      );
      await repositories.workoutExercises.create(
        WorkoutExerciseDraft(workoutId: workoutId, exerciseId: exerciseId),
      );
      await repositories.sets.create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
          position: 0,
          values: LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.distance,
                entered: '5.00',
                unit: TrainingUnit.kilometer,
              ),
              SetDimensionValue(
                dimension: DimensionId.duration,
                entered: '1500',
                unit: TrainingUnit.second,
              ),
            ],
          ),
        ),
      );
      await repositories.exercises.update(
        exerciseId,
        ExerciseDraft(
          name: 'Run then changed',
          type: ExerciseType(const <DimensionId>[DimensionId.reps]),
        ),
      );

      final preview = await repositories.workoutCapture.preview(workoutId);
      expect(preview.validation.accepted, isTrue);
      expect(preview.validation.warnings, isEmpty);
      final result = await repositories.workoutCapture.save(
        WorkoutCaptureSaveRequest(
          workoutId: workoutId,
          name: 'Historical run',
        ),
      );
      final prescription = (await repositories.workoutTemplates.getById(
        result.workoutTemplateId,
      ))!
          .exercises
          .single
          .prescriptions
          .single;
      expect(
        prescription.values.dimensionIds.toSet(),
        <DimensionId>{DimensionId.distance, DimensionId.duration},
      );
      expect(prescription.values.distance?.entered, '5.00');
      expect(prescription.values.duration?.entered, '1500');
    });

    test('forced mid-tree SQLite failure rolls back every row and Activity log',
        () async {
      final source = await _createAllDimensionSource(repositories);
      final sourceBytes = jsonEncode(
        await _sourceImages(database, source.workoutId),
      );
      final planBytes = jsonEncode(await _captureWriteImages(database));
      await database.customStatement('''
        CREATE TEMP TRIGGER force_capture_prescription_failure
        BEFORE INSERT ON prescriptions
        WHEN NEW.position = 1
        BEGIN
          SELECT RAISE(ABORT, 'forced capture failure');
        END;
      ''');

      await expectLater(
        repositories.workoutCapture.save(
          WorkoutCaptureSaveRequest(
            workoutId: source.workoutId,
            name: 'Must fully roll back',
          ),
          batchId: 'capture-forced-trigger-failure',
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
      expect(
        jsonEncode(await _sourceImages(database, source.workoutId)),
        sourceBytes,
      );
      expect(jsonEncode(await _captureWriteImages(database)), planBytes);
      expect(
        (await repositories.activityLog.listEntries()).where(
          (entry) => entry.batchId == 'capture-forced-trigger-failure',
        ),
        isEmpty,
      );
    });

    test('captured-content warning requires its exact preview fingerprint',
        () async {
      final source = await _createRepeatedWarningSource(repositories);
      final preview = await repositories.workoutCapture.preview(
        source.workoutId,
      );
      expect(preview.validation.accepted, isTrue);
      expect(preview.validation.warnings, hasLength(1));
      final warning = preview.validation.warnings.single;
      expect(warning.sourcePath, 'exercises[0].prescriptions[0]');
      expect(warning.fieldPath, 'exercises[0].prescriptions[0].repeat');
      expect(warning.rule, 'prescription_repeat_improbable');
      expect(
        jsonDecode(warning.acknowledgementToken),
        <String, Object?>{
          'schemaVersion': 1,
          'sourcePath': 'exercises[0].prescriptions[0]',
          'field': 'repeat',
          'dimension': null,
          'rule': 'prescription_repeat_improbable',
          'message': 'Repeat above 100 is improbable.',
          'limit': 100,
        },
      );
      final before = jsonEncode(await _captureWriteImages(database));

      await expectLater(
        repositories.workoutCapture.save(
          WorkoutCaptureSaveRequest(
            workoutId: source.workoutId,
            name: 'Unacknowledged repeat',
          ),
          batchId: 'capture-repeat-unacknowledged',
        ),
        throwsA(isA<WorkoutCaptureWarningsNotAcknowledged>()),
      );
      expect(jsonEncode(await _captureWriteImages(database)), before);

      final result = await repositories.workoutCapture.save(
        WorkoutCaptureSaveRequest(
          workoutId: source.workoutId,
          name: 'Acknowledged repeat',
          acknowledgedWarningTokens:
              preview.validation.warningAcknowledgementTokens,
        ),
        batchId: 'capture-repeat-acknowledged',
      );
      final prescription = (await repositories.workoutTemplates.getById(
        result.workoutTemplateId,
      ))!
          .exercises
          .single
          .prescriptions
          .single;
      expect(prescription.repeat, 101);
      expect(prescription.values.reps?.entered, '10');
    });

    test('unseen Cadence and changed content invalidate warning fingerprints',
        () async {
      final source = await _createRepeatedWarningSource(repositories);
      final preview = await repositories.workoutCapture.preview(
        source.workoutId,
      );
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Warning rotation'),
      );
      await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.rotating(32),
      );

      WorkoutCaptureWarningsNotAcknowledged? unseenPlacement;
      try {
        await repositories.workoutCapture.save(
          WorkoutCaptureSaveRequest(
            workoutId: source.workoutId,
            name: 'Unseen placement',
            placement: WorkoutCapturePlacement.cadenceSlot(routineId, 1),
            acknowledgedWarningTokens:
                preview.validation.warningAcknowledgementTokens,
          ),
          batchId: 'capture-unseen-placement-warning',
        );
      } on WorkoutCaptureWarningsNotAcknowledged catch (error) {
        unseenPlacement = error;
      }
      expect(unseenPlacement, isNotNull);
      final unseenPlacementFailure = unseenPlacement!;
      expect(unseenPlacementFailure.missingWarningTokens, hasLength(1));
      expect(unseenPlacementFailure.unexpectedWarningTokens, isEmpty);
      expect(
        unseenPlacementFailure.validation.warnings
            .map((issue) => issue.fieldPath),
        <String>[
          'exercises[0].prescriptions[0].repeat',
          'placement.cadenceWindow',
        ],
      );

      final staleCombinedTokens =
          unseenPlacementFailure.validation.warningAcknowledgementTokens;
      await repositories.sets.updateValues(
        source.setIds.last,
        values: LoggedSet.fromValues(
          const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '201',
              unit: TrainingUnit.repetition,
            ),
          ],
        ),
      );
      final beforeRetry = jsonEncode(await _captureWriteImages(database));
      WorkoutCaptureWarningsNotAcknowledged? changedContent;
      try {
        await repositories.workoutCapture.save(
          WorkoutCaptureSaveRequest(
            workoutId: source.workoutId,
            name: 'Changed content',
            placement: WorkoutCapturePlacement.cadenceSlot(routineId, 1),
            acknowledgedWarningTokens: staleCombinedTokens,
          ),
          batchId: 'capture-changed-content-warning',
        );
      } on WorkoutCaptureWarningsNotAcknowledged catch (error) {
        changedContent = error;
      }
      expect(changedContent, isNotNull);
      final changedContentFailure = changedContent!;
      expect(changedContentFailure.missingWarningTokens, hasLength(1));
      expect(changedContentFailure.unexpectedWarningTokens, hasLength(1));
      expect(
        changedContentFailure.validation.warnings
            .map((issue) => issue.fieldPath),
        <String>[
          'exercises[0].prescriptions[1].values.reps.entered',
          'placement.cadenceWindow',
        ],
      );
      expect(jsonEncode(await _captureWriteImages(database)), beforeRetry);

      final accepted = await repositories.workoutCapture.save(
        WorkoutCaptureSaveRequest(
          workoutId: source.workoutId,
          name: 'Fresh acknowledgement',
          placement: WorkoutCapturePlacement.cadenceSlot(routineId, 1),
          acknowledgedWarningTokens:
              changedContentFailure.validation.warningAcknowledgementTokens,
        ),
        batchId: 'capture-fresh-warning-acknowledgement',
      );
      final prescriptions = (await repositories.workoutTemplates.getById(
        accepted.workoutTemplateId,
      ))!
          .exercises
          .single
          .prescriptions;
      expect(prescriptions.map((prescription) => prescription.repeat),
          <int>[100, 1]);
      expect(prescriptions.last.values.reps?.entered, '201');
    });

    test('collection placement shares one batch and undo tombstones the graph',
        () async {
      final source = await _createRichSource(repositories, database);
      final existingTemplateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Existing'),
      );
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Collection'),
      );
      final existingEntryId = await repositories.routinePlans
          .addTemplateReference(routineId, existingTemplateId);

      final result = await repositories.workoutCapture.save(
        WorkoutCaptureSaveRequest(
          workoutId: source.workoutId,
          name: 'Captured',
          placement: WorkoutCapturePlacement.collectionAppend(routineId),
        ),
        actor: 'test',
        batchId: 'capture-collection',
      );
      expect(result.routineEntryId, isNotNull);
      var routine = (await repositories.routinePlans.getById(routineId))!;
      expect(routine.entries.map((entry) => entry.id),
          <String>[existingEntryId, result.routineEntryId!]);
      expect(routine.entries.last.position, 1);
      expect(routine.entries.last.slot, isNull);
      expect(routine.entries.last.workoutTemplateId, result.workoutTemplateId);

      final originalBatch = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == result.activityBatchId)
          .toList(growable: false);
      expect(
        originalBatch.map((entry) => entry.entityTable),
        contains(AppDatabase.routineEntriesTable),
      );

      final undo = await repositories.activityLog.undoBatch(
        result.activityBatchId,
        actor: 'test',
      );
      expect(undo.conflicts, isEmpty);
      expect(undo.appliedEntries, hasLength(originalBatch.length));
      final templateRow = await (database.select(database.workoutTemplates)
            ..where((row) => row.id.equals(result.workoutTemplateId)))
          .getSingle();
      expect(templateRow.deletedAt, isNotNull);
      final createdExerciseRows =
          await (database.select(database.templateExercises)
                ..where(
                  (row) =>
                      row.workoutTemplateId.equals(result.workoutTemplateId),
                ))
              .get();
      expect(createdExerciseRows, isNotEmpty);
      expect(createdExerciseRows.every((row) => row.deletedAt != null), isTrue);
      final prescriptionIds = originalBatch
          .where(
            (entry) => entry.entityTable == AppDatabase.prescriptionsTable,
          )
          .map((entry) => entry.entityId)
          .toSet();
      final createdPrescriptions = await (database.select(
        database.prescriptions,
      )..where((row) => row.id.isIn(prescriptionIds)))
          .get();
      expect(createdPrescriptions, isNotEmpty);
      expect(
        createdPrescriptions.every((row) => row.deletedAt != null),
        isTrue,
      );
      final groupIds = originalBatch
          .where(
            (entry) => entry.entityTable == AppDatabase.templateGroupsTable,
          )
          .map((entry) => entry.entityId)
          .toSet();
      final createdGroups = await (database.select(database.templateGroups)
            ..where((row) => row.id.isIn(groupIds)))
          .get();
      expect(createdGroups, hasLength(1));
      expect(createdGroups.single.deletedAt, isNotNull);
      final memberIds = originalBatch
          .where(
            (entry) =>
                entry.entityTable == AppDatabase.templateGroupMembersTable,
          )
          .map((entry) => entry.entityId)
          .toSet();
      final createdMembers = await (database.select(
        database.templateGroupMembers,
      )..where((row) => row.id.isIn(memberIds)))
          .get();
      expect(createdMembers, hasLength(2));
      expect(createdMembers.every((row) => row.deletedAt != null), isTrue);
      final createdEntry = await (database.select(database.routineEntries)
            ..where((row) => row.id.equals(result.routineEntryId!)))
          .getSingle();
      expect(createdEntry.deletedAt, isNotNull);
      routine = (await repositories.routinePlans.getById(routineId))!;
      expect(
          routine.entries.map((entry) => entry.id), <String>[existingEntryId]);
      expect(routine.entries.single.position, 0);
      expect(
        await repositories.workoutSessions.getById(source.workoutId),
        isNotNull,
      );
      expect(
        await repositories.sets.listActiveForWorkout(source.workoutId),
        hasLength(3),
      );
    });

    test('places into weekly and rotating slots and rolls back invalid slots',
        () async {
      final source = await _createMinimalSource(repositories);
      final weeklyId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Week'),
      );
      await repositories.routinePlans.setCadence(
        weeklyId,
        const Cadence.weekly(),
      );
      final weekly = await repositories.workoutCapture.save(
        WorkoutCaptureSaveRequest(
          workoutId: source.workoutId,
          name: 'Weekly capture',
          placement: WorkoutCapturePlacement.cadenceSlot(weeklyId, 7),
        ),
        batchId: 'capture-weekly',
      );
      expect(
        (await repositories.routinePlans.getById(weeklyId))!
            .entries
            .single
            .slot,
        7,
      );

      final rotatingId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Rotation'),
      );
      await repositories.routinePlans.setCadence(
        rotatingId,
        const Cadence.rotating(3),
      );
      final rotating = await repositories.workoutCapture.save(
        WorkoutCaptureSaveRequest(
          workoutId: source.workoutId,
          name: 'Rotating capture',
          placement: WorkoutCapturePlacement.cadenceSlot(rotatingId, 2),
        ),
        batchId: 'capture-rotating',
      );
      expect(weekly.workoutTemplateId, isNot(rotating.workoutTemplateId));
      expect(
        (await repositories.routinePlans.getById(rotatingId))!
            .entries
            .single
            .slot,
        2,
      );

      final templateCount =
          (await database.select(database.workoutTemplates).get()).length;
      await expectLater(
        repositories.workoutCapture.save(
          WorkoutCaptureSaveRequest(
            workoutId: source.workoutId,
            name: 'Must roll back',
            placement: WorkoutCapturePlacement.cadenceSlot(weeklyId, 8),
          ),
          batchId: 'capture-invalid-slot',
        ),
        throwsA(
          isA<WorkoutCaptureValidationException>().having(
            (error) => error.validation.errors.map(
              (issue) => '${issue.fieldPath}:${issue.rule}',
            ),
            'rules',
            contains('placement.slots:routine_entry_slot_range'),
          ),
        ),
      );
      expect(
        (await database.select(database.workoutTemplates).get()).length,
        templateCount,
      );
      expect(
        (await repositories.activityLog.listEntries())
            .where((entry) => entry.batchId == 'capture-invalid-slot'),
        isEmpty,
      );
    });

    test(
        'requires warning acknowledgement and commit-time active Routine state',
        () async {
      final source = await _createMinimalSource(repositories);
      final warningRoutineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Long rotation'),
      );
      await repositories.routinePlans.setCadence(
        warningRoutineId,
        const Cadence.rotating(32),
      );

      WorkoutCaptureWarningsNotAcknowledged? warningFailure;
      try {
        await repositories.workoutCapture.save(
          WorkoutCaptureSaveRequest(
            workoutId: source.workoutId,
            name: 'Needs confirmation',
            placement: WorkoutCapturePlacement.cadenceSlot(warningRoutineId, 1),
          ),
          batchId: 'capture-unaccepted-warning',
        );
      } on WorkoutCaptureWarningsNotAcknowledged catch (error) {
        warningFailure = error;
      }
      expect(warningFailure, isNotNull);
      final acknowledgedWarningFailure = warningFailure!;
      expect(
        acknowledgedWarningFailure.validation.warnings.map(
          (issue) => '${issue.fieldPath}:${issue.rule}',
        ),
        contains('placement.cadenceWindow:cadence_window_improbable'),
      );
      expect(acknowledgedWarningFailure.missingWarningTokens, hasLength(1));
      expect(acknowledgedWarningFailure.unexpectedWarningTokens, isEmpty);
      expect(
        (await repositories.activityLog.listEntries())
            .where((entry) => entry.batchId == 'capture-unaccepted-warning'),
        isEmpty,
      );
      final accepted = await repositories.workoutCapture.save(
        WorkoutCaptureSaveRequest(
          workoutId: source.workoutId,
          name: 'Confirmed',
          placement: WorkoutCapturePlacement.cadenceSlot(warningRoutineId, 1),
          acknowledgedWarningTokens: acknowledgedWarningFailure
              .validation.warningAcknowledgementTokens,
        ),
        batchId: 'capture-accepted-warning',
      );
      expect(accepted.routineEntryId, isNotNull);

      final staleRoutineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Soon archived'),
      );
      await repositories.routinePlans.archive(staleRoutineId);
      final templateCount =
          (await database.select(database.workoutTemplates).get()).length;
      await expectLater(
        repositories.workoutCapture.save(
          WorkoutCaptureSaveRequest(
            workoutId: source.workoutId,
            name: 'Stale placement',
            placement: WorkoutCapturePlacement.collectionAppend(staleRoutineId),
          ),
          batchId: 'capture-stale-routine',
        ),
        throwsStateError,
      );
      expect(
        (await database.select(database.workoutTemplates).get()).length,
        templateCount,
      );
      expect(
        (await repositories.activityLog.listEntries())
            .where((entry) => entry.batchId == 'capture-stale-routine'),
        isEmpty,
      );
    });
  });
}

Future<_RichSource> _createRichSource(
  TrainingRepositories repositories,
  AppDatabase database,
) async {
  final pressExerciseId = await repositories.exercises.create(
    ExerciseDraft(
      name: 'Dumbbell Press',
      type: ExerciseType(
        const <DimensionId>[DimensionId.load, DimensionId.reps],
      ),
      isUnilateral: true,
      usesRpe: true,
    ),
  );
  final rowExerciseId = await repositories.exercises.create(
    ExerciseDraft(
      name: 'Cable Row',
      type: ExerciseType(const <DimensionId>[DimensionId.reps]),
    ),
  );
  final zeroExerciseId = await repositories.exercises.create(
    ExerciseDraft(name: 'Mobility', type: ExerciseType.empty),
  );
  final workoutId = await repositories.workoutSessions.create(
    WorkoutSessionDraft(
      startedAt: DateTime.utc(2026, 7, 11, 8),
      timezone: 'UTC',
      endedAt: DateTime.utc(2026, 7, 11, 9),
      comment: 'Fact-only workout comment',
    ),
  );
  final pressWorkoutExerciseId = await repositories.workoutExercises.create(
    WorkoutExerciseDraft(workoutId: workoutId, exerciseId: pressExerciseId),
  );
  final rowWorkoutExerciseId = await repositories.workoutExercises.create(
    WorkoutExerciseDraft(workoutId: workoutId, exerciseId: rowExerciseId),
  );
  await repositories.workoutExercises.create(
    WorkoutExerciseDraft(workoutId: workoutId, exerciseId: zeroExerciseId),
  );
  final pressValues = LoggedSet.fromValues(
    const <SetDimensionValue>[
      SetDimensionValue(
        dimension: DimensionId.load,
        entered: '32.5',
        unit: TrainingUnit.kilogram,
      ),
      SetDimensionValue(
        dimension: DimensionId.reps,
        entered: '8',
        unit: TrainingUnit.repetition,
      ),
    ],
  );
  await repositories.sets.create(
    LoggedSetDraft(
      workoutId: workoutId,
      exerciseId: pressExerciseId,
      position: 0,
      values: pressValues,
      plannedRestAfter: const Duration(seconds: 90),
      performedAt: DateTime.utc(2026, 7, 11, 8, 10),
      comment: 'Smooth',
      side: SetSide.left,
      rpe: 7.5,
    ),
  );
  await repositories.sets.create(
    LoggedSetDraft(
      workoutId: workoutId,
      exerciseId: pressExerciseId,
      position: 1,
      values: pressValues,
      plannedRestAfter: const Duration(seconds: 90),
      performedAt: DateTime.utc(2026, 7, 11, 8, 15),
      isCompleted: true,
      comment: 'Hard',
      side: SetSide.right,
      rpe: 9,
    ),
  );
  await repositories.sets.create(
    LoggedSetDraft(
      workoutId: workoutId,
      exerciseId: rowExerciseId,
      position: 2,
      values: LoggedSet.fromValues(
        const <SetDimensionValue>[
          SetDimensionValue(
            dimension: DimensionId.reps,
            entered: '12',
            unit: TrainingUnit.repetition,
          ),
        ],
      ),
    ),
  );
  await repositories.exerciseGroups.create(
    ExerciseGroupDraft(
      workoutId: workoutId,
      name: 'Reverse circuit',
      colorHex: '#2F6FED',
      workoutExerciseIds: <String>[
        rowWorkoutExerciseId,
        pressWorkoutExerciseId,
      ],
    ),
  );

  // A historical Workout remains capturable after its Exercise is archived.
  await repositories.exercises.softDelete(pressExerciseId);
  final linkedTemplateId = await repositories.workoutTemplates.create(
    const WorkoutTemplateDraft(name: 'Original link'),
  );
  const templateLinkId = 'source-template-link';
  await database.into(database.templateLinks).insert(
        TemplateLinksCompanion.insert(
          id: templateLinkId,
          workoutId: workoutId,
          workoutTemplateId: linkedTemplateId,
          updatedAt: DateTime.utc(2026, 7, 11, 10),
        ),
      );
  return _RichSource(
    workoutId: workoutId,
    pressExerciseId: pressExerciseId,
    rowExerciseId: rowExerciseId,
    zeroExerciseId: zeroExerciseId,
    linkedTemplateId: linkedTemplateId,
    templateLinkId: templateLinkId,
  );
}

Future<_MinimalSource> _createMinimalSource(
  TrainingRepositories repositories,
) async {
  final exerciseId = await repositories.exercises.create(
    ExerciseDraft(
      name: 'Push-up',
      type: ExerciseType(const <DimensionId>[DimensionId.reps]),
    ),
  );
  final workoutId = await repositories.workoutSessions.create(
    WorkoutSessionDraft(
      startedAt: DateTime.utc(2026, 7, 11, 8),
      timezone: 'UTC',
    ),
  );
  await repositories.workoutExercises.create(
    WorkoutExerciseDraft(workoutId: workoutId, exerciseId: exerciseId),
  );
  await repositories.sets.create(
    LoggedSetDraft(
      workoutId: workoutId,
      exerciseId: exerciseId,
      position: 0,
      values: LoggedSet.fromValues(
        const <SetDimensionValue>[
          SetDimensionValue(
            dimension: DimensionId.reps,
            entered: '10',
            unit: TrainingUnit.repetition,
          ),
        ],
      ),
    ),
  );
  return _MinimalSource(workoutId: workoutId);
}

Future<_MinimalSource> _createAllDimensionSource(
  TrainingRepositories repositories,
) async {
  final exerciseId = await repositories.exercises.create(
    ExerciseDraft(
      name: 'Mixed event',
      type: ExerciseType(const <DimensionId>[
        DimensionId.load,
        DimensionId.reps,
        DimensionId.duration,
        DimensionId.distance,
      ]),
    ),
  );
  final workoutId = await repositories.workoutSessions.create(
    WorkoutSessionDraft(
      startedAt: DateTime.utc(2026, 7, 11, 8),
      timezone: 'UTC',
    ),
  );
  await repositories.workoutExercises.create(
    WorkoutExerciseDraft(workoutId: workoutId, exerciseId: exerciseId),
  );
  final first = LoggedSet.fromValues(
    const <SetDimensionValue>[
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
      SetDimensionValue(
        dimension: DimensionId.duration,
        entered: '120',
        unit: TrainingUnit.second,
      ),
      SetDimensionValue(
        dimension: DimensionId.distance,
        entered: '1',
        unit: TrainingUnit.kilometer,
      ),
    ],
  );
  final alternateUnits = LoggedSet.fromValues(
    const <SetDimensionValue>[
      SetDimensionValue(
        dimension: DimensionId.load,
        entered: '220.46',
        unit: TrainingUnit.pound,
      ),
      SetDimensionValue(
        dimension: DimensionId.reps,
        entered: '5',
        unit: TrainingUnit.repetition,
      ),
      SetDimensionValue(
        dimension: DimensionId.duration,
        entered: '120.0',
        unit: TrainingUnit.second,
      ),
      SetDimensionValue(
        dimension: DimensionId.distance,
        entered: '0.62',
        unit: TrainingUnit.mile,
      ),
    ],
  );
  final alternateEnteredText = LoggedSet.fromValues(
    const <SetDimensionValue>[
      SetDimensionValue(
        dimension: DimensionId.load,
        entered: '100.0',
        unit: TrainingUnit.kilogram,
      ),
      SetDimensionValue(
        dimension: DimensionId.reps,
        entered: '5',
        unit: TrainingUnit.repetition,
      ),
      SetDimensionValue(
        dimension: DimensionId.duration,
        entered: '120',
        unit: TrainingUnit.second,
      ),
      SetDimensionValue(
        dimension: DimensionId.distance,
        entered: '1',
        unit: TrainingUnit.kilometer,
      ),
    ],
  );
  final drafts = <({LoggedSet values, Duration rest})>[
    (values: first, rest: const Duration(seconds: 60)),
    (values: first, rest: const Duration(seconds: 60)),
    (values: alternateUnits, rest: const Duration(seconds: 90)),
    (values: alternateEnteredText, rest: const Duration(seconds: 60)),
  ];
  for (var position = 0; position < drafts.length; position += 1) {
    final draft = drafts[position];
    await repositories.sets.create(
      LoggedSetDraft(
        workoutId: workoutId,
        exerciseId: exerciseId,
        position: position,
        values: draft.values,
        plannedRestAfter: draft.rest,
      ),
    );
  }
  return _MinimalSource(workoutId: workoutId);
}

Future<_RepeatedWarningSource> _createRepeatedWarningSource(
  TrainingRepositories repositories,
) async {
  final exerciseId = await repositories.exercises.create(
    ExerciseDraft(
      name: 'High repeat exercise',
      type: ExerciseType(const <DimensionId>[DimensionId.reps]),
    ),
  );
  final workoutId = await repositories.workoutSessions.create(
    WorkoutSessionDraft(
      startedAt: DateTime.utc(2026, 7, 11, 8),
      timezone: 'UTC',
    ),
  );
  await repositories.workoutExercises.create(
    WorkoutExerciseDraft(workoutId: workoutId, exerciseId: exerciseId),
  );
  final values = LoggedSet.fromValues(
    const <SetDimensionValue>[
      SetDimensionValue(
        dimension: DimensionId.reps,
        entered: '10',
        unit: TrainingUnit.repetition,
      ),
    ],
  );
  final setIds = <String>[];
  for (var position = 0; position < 101; position += 1) {
    setIds.add(
      await repositories.sets.create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
          position: position,
          values: values,
        ),
      ),
    );
  }
  return _RepeatedWarningSource(
    workoutId: workoutId,
    setIds: setIds,
  );
}

Future<Map<String, Object?>> _sourceImages(
  AppDatabase database,
  String workoutId,
) async {
  final workout = await (database.select(database.workoutSessions)
        ..where((row) => row.id.equals(workoutId)))
      .getSingle();
  final workoutExercises = await (database.select(database.workoutExercises)
        ..where((row) => row.workoutId.equals(workoutId)))
      .get();
  final sets = await (database.select(database.loggedSets)
        ..where((row) => row.workoutId.equals(workoutId)))
      .get();
  final groups = await (database.select(database.exerciseGroups)
        ..where((row) => row.workoutId.equals(workoutId)))
      .get();
  final groupIds = groups.map((group) => group.id).toSet();
  final members = await (database.select(database.exerciseGroupMembers)
        ..where((row) => row.groupId.isIn(groupIds)))
      .get();
  final links = await (database.select(database.templateLinks)
        ..where((row) => row.workoutId.equals(workoutId)))
      .get();
  return <String, Object?>{
    'workout': workout.toJson(),
    'workoutExercises': workoutExercises.map((row) => row.toJson()).toList(),
    'sets': sets.map((row) => row.toJson()).toList(),
    'groups': groups.map((row) => row.toJson()).toList(),
    'members': members.map((row) => row.toJson()).toList(),
    'links': links.map((row) => row.toJson()).toList(),
  };
}

Future<Map<String, Object?>> _captureWriteImages(AppDatabase database) async {
  return <String, Object?>{
    'workoutTemplates': (await database.select(database.workoutTemplates).get())
        .map((row) => row.toJson())
        .toList(),
    'templateExercises':
        (await database.select(database.templateExercises).get())
            .map((row) => row.toJson())
            .toList(),
    'prescriptions': (await database.select(database.prescriptions).get())
        .map((row) => row.toJson())
        .toList(),
    'templateGroups': (await database.select(database.templateGroups).get())
        .map((row) => row.toJson())
        .toList(),
    'templateGroupMembers':
        (await database.select(database.templateGroupMembers).get())
            .map((row) => row.toJson())
            .toList(),
    'routineEntries': (await database.select(database.routineEntries).get())
        .map((row) => row.toJson())
        .toList(),
    'activityLog': (await database.select(database.activityLog).get())
        .map((row) => row.toJson())
        .toList(),
  };
}

final class _RichSource {
  const _RichSource({
    required this.workoutId,
    required this.pressExerciseId,
    required this.rowExerciseId,
    required this.zeroExerciseId,
    required this.linkedTemplateId,
    required this.templateLinkId,
  });

  final String workoutId;
  final String pressExerciseId;
  final String rowExerciseId;
  final String zeroExerciseId;
  final String linkedTemplateId;
  final String templateLinkId;
}

final class _MinimalSource {
  const _MinimalSource({required this.workoutId});

  final String workoutId;
}

final class _RepeatedWarningSource {
  _RepeatedWarningSource({
    required this.workoutId,
    required Iterable<String> setIds,
  }) : setIds = List<String>.unmodifiable(setIds);

  final String workoutId;
  final List<String> setIds;
}
