import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';

void main() {
  final previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
  });

  group('RoutinePlanRepository', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() => database.close());

    test('creates, edits, archives, and restores an empty Routine', () async {
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(
          name: '  Hybrid week  ',
          notes: '  Fits around shifts  ',
        ),
        actor: 'test',
        batchId: 'create-routine',
      );
      var routine = await repositories.routinePlans.getById(routineId);
      expect(routine?.name, 'Hybrid week');
      expect(routine?.notes, 'Fits around shifts');
      expect(routine?.entries, isEmpty);

      await repositories.routinePlans.updateRoutine(
        routineId,
        name: '  Hybrid fortnight ',
        notes: '   ',
        actor: 'test',
        batchId: 'update-routine',
      );
      routine = await repositories.routinePlans.getById(routineId);
      expect(routine?.name, 'Hybrid fortnight');
      expect(routine?.notes, isNull);

      await repositories.routinePlans.archive(
        routineId,
        actor: 'test',
        batchId: 'archive-routine',
      );
      expect(
        await repositories.routinePlans.listActiveSummaries(),
        isEmpty,
      );
      expect(
        (await repositories.routinePlans.listArchivedSummaries()).single.id,
        routineId,
      );
      expect(
        await repositories.routinePlans.getById(
          routineId,
          includeArchived: false,
        ),
        isNull,
      );

      await repositories.routinePlans.restore(
        routineId,
        actor: 'test',
        batchId: 'restore-routine',
      );
      expect(
        (await repositories.routinePlans.listActiveSummaries()).single.id,
        routineId,
      );

      final logs = await repositories.activityLog.listEntries();
      for (final batchId in <String>{
        'create-routine',
        'update-routine',
        'archive-routine',
        'restore-routine',
      }) {
        final batch = logs.where((entry) => entry.batchId == batchId).toList();
        expect(batch, hasLength(1), reason: batchId);
        expect(batch.single.entityTable, AppDatabase.planRoutinesTable);
      }
      final createLog = logs.singleWhere(
        (entry) => entry.batchId == 'create-routine',
      );
      expect(createLog.beforeImage, isNull);
      expect(createLog.afterImage?['name'], 'Hybrid week');
    });

    test('references one live Template without copying or cascading', () async {
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(
          name: 'Tempo Run',
          notes: 'Eight kilometres',
        ),
      );
      final firstRoutineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Race build'),
      );
      final secondRoutineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Travel favourites'),
      );
      final firstEntryId = await repositories.routinePlans.addTemplateReference(
        firstRoutineId,
        templateId,
      );
      // Duplicate references in one Routine are valid and retain distinct
      // identity for the future Cadence slot layout.
      final duplicateEntryId =
          await repositories.routinePlans.addTemplateReference(
        firstRoutineId,
        templateId,
      );
      await repositories.routinePlans.addTemplateReference(
        secondRoutineId,
        templateId,
      );

      final firstRename =
          repositories.routinePlans.watchById(firstRoutineId).firstWhere(
                (routine) =>
                    routine?.entries.every(
                      (entry) => entry.templateName == 'Threshold Run',
                    ) ??
                    false,
              );
      final secondRename =
          repositories.routinePlans.watchById(secondRoutineId).firstWhere(
                (routine) =>
                    routine?.entries.single.templateName == 'Threshold Run',
              );
      await repositories.workoutTemplates.updateTemplate(
        templateId,
        name: 'Threshold Run',
        notes: 'Ten kilometres',
      );
      expect((await firstRename)?.entries, hasLength(2));
      expect(
          (await secondRename)?.entries.single.templateNotes, 'Ten kilometres');
      expect(
        await database.select(database.workoutTemplates).get(),
        hasLength(1),
      );

      await repositories.workoutTemplates.archive(templateId);
      var firstRoutine =
          (await repositories.routinePlans.getById(firstRoutineId))!;
      expect(
        firstRoutine.entries.every((entry) => entry.templateIsArchived),
        isTrue,
      );
      expect(
        (await repositories.routinePlans.listActiveSummaries())
            .singleWhere((routine) => routine.id == firstRoutineId)
            .archivedTemplateCount,
        2,
      );

      final entriesBeforeRoutineArchive =
          await database.select(database.routineEntries).get();
      await repositories.routinePlans.archive(firstRoutineId);
      expect(
        await database.select(database.routineEntries).get(),
        entriesBeforeRoutineArchive,
      );
      expect(
        (await repositories.workoutTemplates.getById(templateId))?.isArchived,
        isTrue,
      );

      await repositories.routinePlans.restore(firstRoutineId);
      await repositories.workoutTemplates.restore(templateId);
      await repositories.routinePlans.removeTemplateReference(firstEntryId);
      firstRoutine = (await repositories.routinePlans.getById(firstRoutineId))!;
      expect(firstRoutine.entries, hasLength(1));
      expect(firstRoutine.entries.single.id, duplicateEntryId);
      expect(firstRoutine.entries.single.position, 0);
      expect(firstRoutine.entries.single.templateIsArchived, isFalse);
      final removed = await (database.select(database.routineEntries)
            ..where((row) => row.id.equals(firstEntryId)))
          .getSingle();
      expect(removed.deletedAt, isNotNull);
      expect(
        (await repositories.workoutTemplates.getById(templateId))?.isArchived,
        isFalse,
      );
    });

    test('reorders exact entry IDs atomically and undo restores removal',
        () async {
      final templateIds = <String>[];
      for (final name in <String>['Strength', 'Intervals', 'Mobility']) {
        templateIds.add(
          await repositories.workoutTemplates.create(
            WorkoutTemplateDraft(name: name),
          ),
        );
      }
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Mixed week'),
      );
      final entryIds = <String>[];
      for (final templateId in templateIds) {
        entryIds.add(
          await repositories.routinePlans.addTemplateReference(
            routineId,
            templateId,
          ),
        );
      }

      final reversed = entryIds.reversed.toList(growable: false);
      await repositories.routinePlans.reorderTemplateReferences(
        routineId,
        reversed,
        actor: 'test',
        batchId: 'reorder-entries',
      );
      expect(
        (await repositories.routinePlans.getById(routineId))
            ?.entries
            .map((entry) => entry.id),
        reversed,
      );
      final reorderLogs = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == 'reorder-entries')
          .toList(growable: false);
      expect(reorderLogs, hasLength(2));
      expect(
        reorderLogs.map((entry) => entry.entityTable).toSet(),
        <String>{AppDatabase.routineEntriesTable},
      );

      final rowsBeforeInvalid =
          await database.select(database.routineEntries).get();
      final logIdsBeforeInvalid = (await repositories.activityLog.listEntries())
          .map((entry) => entry.id)
          .toList(growable: false);
      await expectLater(
        repositories.routinePlans.reorderTemplateReferences(
          routineId,
          <String>[reversed.first, reversed.first, reversed.last],
          batchId: 'invalid-reorder',
        ),
        throwsArgumentError,
      );
      expect(
        await database.select(database.routineEntries).get(),
        rowsBeforeInvalid,
      );
      expect(
        (await repositories.activityLog.listEntries()).map((entry) => entry.id),
        logIdsBeforeInvalid,
      );

      await repositories.routinePlans.removeTemplateReference(
        reversed[1],
        actor: 'test',
        batchId: 'remove-entry',
      );
      expect(
        (await repositories.routinePlans.getById(routineId))
            ?.entries
            .map((entry) => entry.id),
        <String>[reversed.first, reversed.last],
      );
      final removeLogs = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == 'remove-entry')
          .toList(growable: false);
      expect(removeLogs, hasLength(2));
      expect(removeLogs.map((entry) => entry.batchId).toSet(), hasLength(1));

      final undo = await repositories.activityLog.undoBatch(
        'remove-entry',
        actor: 'test-undo',
      );
      expect(undo.conflicts, isEmpty);
      expect(undo.appliedEntries, hasLength(2));
      expect(
        (await repositories.routinePlans.getById(routineId))
            ?.entries
            .map((entry) => entry.id),
        reversed,
      );
    });

    test('undoing an add after a later add leaves contiguous positions',
        () async {
      final firstTemplateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'First'),
      );
      final secondTemplateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Second'),
      );
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Undo add collection'),
      );
      final firstEntryId = await repositories.routinePlans.addTemplateReference(
        routineId,
        firstTemplateId,
        actor: 'test',
        batchId: 'add-first-entry',
      );
      final secondEntryId =
          await repositories.routinePlans.addTemplateReference(
        routineId,
        secondTemplateId,
        actor: 'test',
        batchId: 'add-later-entry',
      );

      final undo = await repositories.activityLog.undoBatch(
        'add-first-entry',
        actor: 'test-undo',
      );

      expect(undo.conflicts, isEmpty);
      final routine = await repositories.routinePlans.getById(routineId);
      expect(
          routine?.entries.map((entry) => entry.id), <String>[secondEntryId]);
      expect(routine?.entries.single.position, 0);
      final firstRow = await (database.select(database.routineEntries)
            ..where((row) => row.id.equals(firstEntryId)))
          .getSingle();
      expect(firstRow.deletedAt, isNotNull);
      final undoLogs = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == undo.undoBatchId)
          .toList(growable: false);
      expect(undoLogs.map((entry) => entry.entityId).toSet(), <String>{
        firstEntryId,
        secondEntryId,
      });
      expect(
        undoLogs
            .singleWhere((entry) => entry.entityId == secondEntryId)
            .afterImage?['position'],
        0,
      );
    });

    test('undoing a removal after a later add reconciles duplicate positions',
        () async {
      final templateIds = <String>[];
      for (final name in <String>['First', 'Second', 'Later']) {
        templateIds.add(
          await repositories.workoutTemplates.create(
            WorkoutTemplateDraft(name: name),
          ),
        );
      }
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Undo removal collection'),
      );
      final firstEntryId = await repositories.routinePlans.addTemplateReference(
        routineId,
        templateIds[0],
      );
      final secondEntryId =
          await repositories.routinePlans.addTemplateReference(
        routineId,
        templateIds[1],
      );
      await repositories.routinePlans.removeTemplateReference(
        firstEntryId,
        actor: 'test',
        batchId: 'remove-before-later-add',
      );
      final laterEntryId = await repositories.routinePlans.addTemplateReference(
        routineId,
        templateIds[2],
      );

      final undo = await repositories.activityLog.undoBatch(
        'remove-before-later-add',
        actor: 'test-undo',
      );

      expect(undo.conflicts, isEmpty);
      final tiedIds = <String>[secondEntryId, laterEntryId]..sort();
      final expectedIds = <String>[firstEntryId, ...tiedIds];
      final entries =
          (await repositories.routinePlans.getById(routineId))!.entries;
      expect(entries.map((entry) => entry.id), expectedIds);
      expect(entries.map((entry) => entry.position), <int>[0, 1, 2]);
      final undoLogs = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == undo.undoBatchId)
          .toList(growable: false);
      expect(
        undoLogs.any((entry) => entry.afterImage?['position'] == 2),
        isTrue,
      );
      expect(undoLogs.map((entry) => entry.batchId).toSet(), hasLength(1));
    });

    test('undo covers create and reorder and rejects a stale current image',
        () async {
      final createdRoutineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Undo created collection'),
        actor: 'test',
        batchId: 'create-for-undo',
      );
      final createUndo = await repositories.activityLog.undoBatch(
        'create-for-undo',
        actor: 'test-undo',
      );
      expect(createUndo.conflicts, isEmpty);
      expect(
        (await repositories.routinePlans.getById(createdRoutineId))?.isArchived,
        isTrue,
      );

      final templateIds = <String>[];
      for (final name in <String>['A', 'B', 'C']) {
        templateIds.add(
          await repositories.workoutTemplates.create(
            WorkoutTemplateDraft(name: name),
          ),
        );
      }
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Undo reorder collection'),
      );
      final entryIds = <String>[];
      for (final templateId in templateIds) {
        entryIds.add(
          await repositories.routinePlans.addTemplateReference(
            routineId,
            templateId,
          ),
        );
      }
      await repositories.routinePlans.reorderTemplateReferences(
        routineId,
        entryIds.reversed.toList(growable: false),
        actor: 'test',
        batchId: 'reorder-for-undo',
      );
      final reorderUndo = await repositories.activityLog.undoBatch(
        'reorder-for-undo',
        actor: 'test-undo',
      );
      expect(reorderUndo.conflicts, isEmpty);
      expect(
        (await repositories.routinePlans.getById(routineId))
            ?.entries
            .map((entry) => entry.id),
        entryIds,
      );

      await repositories.routinePlans.updateRoutine(
        routineId,
        name: 'First rename',
        notes: null,
        actor: 'test',
        batchId: 'stale-rename',
      );
      await repositories.routinePlans.updateRoutine(
        routineId,
        name: 'Later rename',
        notes: null,
        actor: 'test',
        batchId: 'later-rename',
      );
      final logCount = (await repositories.activityLog.listEntries()).length;
      final staleUndo = await repositories.activityLog.undoBatch(
        'stale-rename',
        actor: 'test-undo',
      );
      expect(staleUndo.appliedEntries, isEmpty);
      expect(staleUndo.conflicts, hasLength(1));
      expect(
        (await repositories.routinePlans.getById(routineId))?.name,
        'Later rename',
      );
      expect(
        (await repositories.activityLog.listEntries()).length,
        logCount,
      );
    });

    test('Cadence transitions preserve entry identity and default slots',
        () async {
      final templateIds = <String>[];
      for (var index = 0; index < 5; index += 1) {
        templateIds.add(
          await repositories.workoutTemplates.create(
            WorkoutTemplateDraft(name: 'Template ${index + 1}'),
          ),
        );
      }
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Cadence collection'),
      );
      final entryIds = <String>[];
      for (final templateId in templateIds) {
        entryIds.add(
          await repositories.routinePlans.addTemplateReference(
            routineId,
            templateId,
          ),
        );
      }

      final weeklyResult = await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.weekly(),
        actor: 'test',
        batchId: 'set-weekly',
      );
      expect(weeklyResult.warnings, isEmpty);
      var routine = (await repositories.routinePlans.getById(routineId))!;
      expect(routine.cadence?.kind, CadenceKind.weekly);
      expect(routine.cadence?.window, isNull);
      expect(routine.entries.map((entry) => entry.id), entryIds);
      expect(
          routine.entries.map((entry) => entry.position), <int>[0, 1, 2, 3, 4]);
      expect(routine.entries.map((entry) => entry.slot), <int?>[1, 2, 3, 4, 5]);

      await repositories.routinePlans.replaceCadenceLayout(
        routineId,
        <RoutineEntrySlotPlacement>[
          RoutineEntrySlotPlacement(entryId: entryIds[1], slot: 2),
          RoutineEntrySlotPlacement(entryId: entryIds[0], slot: 2),
          RoutineEntrySlotPlacement(entryId: entryIds[2], slot: 4),
          RoutineEntrySlotPlacement(entryId: entryIds[3], slot: 6),
          RoutineEntrySlotPlacement(entryId: entryIds[4], slot: 7),
        ],
      );
      routine = (await repositories.routinePlans.getById(routineId))!;
      final layoutEntryIds = <String>[
        entryIds[1],
        entryIds[0],
        entryIds[2],
        entryIds[3],
        entryIds[4],
      ];
      expect(routine.entries.map((entry) => entry.id), layoutEntryIds);
      expect(
        routine.entries.map((entry) => entry.position),
        <int>[0, 1, 2, 3, 4],
      );
      expect(routine.entries.map((entry) => entry.slot), <int?>[2, 2, 4, 6, 7]);

      await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.rotating(3),
      );
      routine = (await repositories.routinePlans.getById(routineId))!;
      expect(routine.cadence?.kind, CadenceKind.rotating);
      expect(routine.cadence?.window, 3);
      expect(routine.entries.map((entry) => entry.id), layoutEntryIds);
      expect(
          routine.entries.map((entry) => entry.position), <int>[0, 1, 2, 3, 4]);
      expect(routine.entries.map((entry) => entry.slot), <int?>[1, 2, 3, 1, 2]);

      final warning = await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.rotating(32),
      );
      expect(
        warning.warnings.map((issue) => issue.rule),
        contains('cadence_window_improbable'),
      );
      expect(
        (await repositories.routinePlans.getById(routineId))?.cadence?.window,
        32,
      );

      await repositories.routinePlans.setCadence(routineId, null);
      routine = (await repositories.routinePlans.getById(routineId))!;
      expect(routine.cadence, isNull);
      expect(routine.entries.map((entry) => entry.slot), everyElement(isNull));
      expect(routine.entries.map((entry) => entry.id), layoutEntryIds);

      final rowsBeforeInvalid =
          await database.select(database.routineEntries).get();
      final logCountBeforeInvalid =
          (await repositories.activityLog.listEntries()).length;
      await expectLater(
        repositories.routinePlans.setCadence(
          routineId,
          const Cadence.rotating(0),
        ),
        throwsA(isA<SetValidationException>()),
      );
      expect(await database.select(database.routineEntries).get(),
          rowsBeforeInvalid);
      expect(
        (await repositories.activityLog.listEntries()).length,
        logCountBeforeInvalid,
      );

      final weeklyLogs = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == 'set-weekly')
          .toList(growable: false);
      expect(weeklyLogs, hasLength(6));
      expect(weeklyLogs.map((entry) => entry.batchId).toSet(), hasLength(1));
    });

    test('Cadence-aware add and undo reconcile later entries atomically',
        () async {
      final templateIds = <String>[];
      for (final name in <String>['First', 'Second', 'Later']) {
        templateIds.add(
          await repositories.workoutTemplates.create(
            WorkoutTemplateDraft(name: name),
          ),
        );
      }
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Undo Cadence collection'),
      );
      for (var index = 0; index < 2; index += 1) {
        await repositories.routinePlans.addTemplateReference(
          routineId,
          templateIds[index],
        );
      }
      await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.weekly(),
        actor: 'test',
        batchId: 'cadence-before-later-add',
      );
      final laterEntryId = await repositories.routinePlans.addTemplateReference(
        routineId,
        templateIds[2],
      );
      expect(
        (await repositories.routinePlans.getById(routineId))?.entries.last.slot,
        3,
      );
      await expectLater(
        repositories.routinePlans.moveTemplateReferenceToSlot(
          laterEntryId,
          8,
        ),
        throwsA(isA<SetValidationException>()),
      );

      final undo = await repositories.activityLog.undoBatch(
        'cadence-before-later-add',
        actor: 'test-undo',
      );
      expect(undo.conflicts, isEmpty);
      final routine = (await repositories.routinePlans.getById(routineId))!;
      expect(routine.cadence, isNull);
      expect(routine.entries, hasLength(3));
      expect(routine.entries.map((entry) => entry.slot), everyElement(isNull));
      final undoLogs = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == undo.undoBatchId)
          .toList(growable: false);
      expect(
        undoLogs.any((entry) => entry.entityId == laterEntryId),
        isTrue,
      );
      expect(undoLogs.map((entry) => entry.batchId).toSet(), hasLength(1));
    });

    test('Cadence values have canonical shapes and reject invalid storage',
        () async {
      const weekly = Cadence.weekly();
      const rotating = Cadence.rotating(4);
      expect(weekly.kind, CadenceKind.weekly);
      expect(weekly.window, isNull);
      expect(weekly.slotCount, 7);
      expect(rotating.kind, CadenceKind.rotating);
      expect(rotating.window, 4);
      expect(rotating.slotCount, 4);

      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Storage boundary'),
      );
      await (database.update(database.planRoutines)
            ..where((row) => row.id.equals(routineId)))
          .write(
        const PlanRoutinesCompanion(
          cadenceKind: Value<String?>('weekly'),
          cadenceWindow: Value<int?>(7),
        ),
      );
      await expectLater(
        repositories.routinePlans.getById(routineId),
        throwsA(isA<StateError>()),
      );

      await (database.update(database.planRoutines)
            ..where((row) => row.id.equals(routineId)))
          .write(
        const PlanRoutinesCompanion(
          cadenceKind: Value<String?>('monthly'),
          cadenceWindow: Value<int?>(null),
        ),
      );
      await expectLater(
        repositories.routinePlans.getById(routineId),
        throwsA(isA<StateError>()),
      );
    });

    test('semantic Cadence undo preserves authored coincident slots and stales',
        () async {
      final templateIds = <String>[];
      for (var index = 0; index < 5; index += 1) {
        templateIds.add(
          await repositories.workoutTemplates.create(
            WorkoutTemplateDraft(name: 'Undo semantic ${index + 1}'),
          ),
        );
      }
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Semantic undo'),
      );
      final entryIds = <String>[];
      for (final templateId in templateIds) {
        entryIds.add(
          await repositories.routinePlans.addTemplateReference(
            routineId,
            templateId,
          ),
        );
      }
      await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.weekly(),
      );
      await repositories.routinePlans.replaceCadenceLayout(
        routineId,
        <RoutineEntrySlotPlacement>[
          RoutineEntrySlotPlacement(entryId: entryIds[0], slot: 1),
          RoutineEntrySlotPlacement(entryId: entryIds[1], slot: 2),
          RoutineEntrySlotPlacement(entryId: entryIds[2], slot: 3),
          RoutineEntrySlotPlacement(entryId: entryIds[3], slot: 4),
          RoutineEntrySlotPlacement(entryId: entryIds[4], slot: 2),
        ],
      );

      await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.rotating(3),
        actor: 'test',
        batchId: 'semantic-cadence',
      );
      final transitionLogs = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == 'semantic-cadence')
          .toList(growable: false);
      expect(transitionLogs, hasLength(6));
      final coincidentLog = transitionLogs.singleWhere(
        (entry) => entry.entityId == entryIds[4],
      );
      expect(coincidentLog.beforeImage?['slot'], 2);
      expect(coincidentLog.afterImage?['slot'], 2);

      final undo = await repositories.activityLog.undoBatch(
        'semantic-cadence',
        actor: 'test-undo',
      );
      expect(undo.conflicts, isEmpty);
      var routine = (await repositories.routinePlans.getById(routineId))!;
      expect(routine.cadence?.kind, CadenceKind.weekly);
      expect(routine.entries.last.slot, 2);

      await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.rotating(3),
        actor: 'test',
        batchId: 'semantic-cadence-stale',
      );
      await repositories.routinePlans.moveTemplateReferenceToSlot(
        entryIds[4],
        3,
      );
      final staleUndo = await repositories.activityLog.undoBatch(
        'semantic-cadence-stale',
        actor: 'test-undo',
      );
      expect(staleUndo.conflicts, isNotEmpty);
      expect(staleUndo.undoBatchId, isNull);
      routine = (await repositories.routinePlans.getById(routineId))!;
      expect(routine.cadence?.kind, CadenceKind.rotating);
      expect(routine.entries.last.slot, 3);
    });

    test(
        'watchActiveDetails streams every active Routine with its entries, '
        'excluding archived Routines but keeping archived-template entries '
        'visible for the caller to filter (picker sheet source)', () async {
      final activeTemplateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Push A'),
      );
      final archivedTemplateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Old Pull'),
      );
      final cadencedRoutineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Weekly split'),
      );
      await repositories.routinePlans.setCadence(
        cadencedRoutineId,
        const Cadence.weekly(),
      );
      await repositories.routinePlans.addTemplateReference(
        cadencedRoutineId,
        activeTemplateId,
      );
      await repositories.routinePlans.addTemplateReference(
        cadencedRoutineId,
        archivedTemplateId,
      );
      await repositories.workoutTemplates.archive(archivedTemplateId);

      final collectionRoutineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Travel favourites'),
      );
      await repositories.routinePlans.addTemplateReference(
        collectionRoutineId,
        activeTemplateId,
      );

      final archivedRoutineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Retired block'),
      );
      await repositories.routinePlans.archive(archivedRoutineId);

      final details =
          await repositories.routinePlans.watchActiveDetails().first;
      final byId = {for (final routine in details) routine.id: routine};

      expect(byId.containsKey(archivedRoutineId), isFalse);

      final cadenced = byId[cadencedRoutineId]!;
      expect(cadenced.cadence?.kind, CadenceKind.weekly);
      expect(cadenced.entries, hasLength(2));
      expect(
        cadenced.entries.map((entry) => entry.workoutTemplateId).toSet(),
        <String>{activeTemplateId, archivedTemplateId},
      );
      expect(
        cadenced.entries
            .singleWhere(
                (entry) => entry.workoutTemplateId == archivedTemplateId)
            .templateIsArchived,
        isTrue,
      );

      final collection = byId[collectionRoutineId]!;
      expect(collection.cadence, isNull);
      expect(collection.entries.single.workoutTemplateId, activeTemplateId);
    });
  });
}
