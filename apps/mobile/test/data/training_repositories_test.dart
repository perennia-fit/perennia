import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/local/uuid_v7.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/platform_exercise_seed.dart';
import 'package:perennia/domain/training/plan_logging.dart';
import 'package:perennia/domain/training/template_materialize.dart'
    show zeroLoggedSetFor;
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/domain/training/training_progress.dart';
import 'package:perennia/features/home/controllers/home_controller.dart';
import 'package:perennia/features/home/repositories/home_repository.dart';

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

  test('UUIDv7 generator produces unique time-ordered identifiers', () {
    final generator = UuidV7Generator();
    final first = generator.generate(
      timestamp: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );
    final second = generator.generate(
      timestamp: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );
    final third = generator.generate(
      timestamp: DateTime.fromMillisecondsSinceEpoch(1001, isUtc: true),
    );

    expect({first, second, third}, hasLength(3));
    expect(first.compareTo(second), lessThan(0));
    expect(second.compareTo(third), lessThan(0));
    expect(first.split('-')[2].startsWith('7'), isTrue);
  });

  group('training repositories', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(
        database,
        platformSeedSource: const _StarterSeedSource(),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('opens current schema with sync-ready columns on every table',
        () async {
      final columnsByTable = await database.describeSchema();

      expect(
        columnsByTable.keys,
        containsAll(<String>[
          'exercise_categories',
          'exercises',
          'workout_sessions',
          'workout_exercises',
          'exercise_groups',
          'exercise_group_members',
          AppDatabase.workoutTemplatesTable,
          AppDatabase.templateExercisesTable,
          AppDatabase.templateGroupsTable,
          AppDatabase.templateGroupMembersTable,
          AppDatabase.prescriptionsTable,
          AppDatabase.planRoutinesTable,
          AppDatabase.routineEntriesTable,
          'logged_sets',
          'rest_timers',
          'interval_timers',
          'metrics',
          'metric_readings',
          'activity_log',
          AppDatabase.integrationDataClassConsentsTable,
          AppDatabase.syncStatesTable,
        ]),
      );
      expect(
        columnsByTable.keys,
        isNot(
          contains(
            anyOf(
              'routines',
              'routine_days',
              'routine_exercises',
              'predefined_sets',
              'routine_exercise_groups',
              'routine_exercise_group_members',
            ),
          ),
        ),
      );

      for (final tableName in AppDatabase.tableNames) {
        expect(columnsByTable[tableName], contains('id'), reason: tableName);
        expect(
          columnsByTable[tableName],
          contains('updated_at'),
          reason: tableName,
        );
        expect(
          columnsByTable[tableName],
          contains('deleted_at'),
          reason: tableName,
        );
      }

      expect(
        columnsByTable[AppDatabase.syncStatesTable],
        containsAll(<String>[
          'id',
          'pull_cursor',
          'sync_status',
          'last_successful_sync_at',
          'first_failure_at',
          'last_failure_at',
          'last_failure_message',
          'updated_at',
        ]),
      );

      expect(
        columnsByTable['exercise_categories'],
        containsAll(<String>['name', 'sort_order', 'color_hex']),
      );
      expect(
        columnsByTable[AppDatabase.activityLogTable],
        contains('sync_acknowledged_at'),
      );
      expect(
        columnsByTable[AppDatabase.loggedSetsTable],
        containsAll(<String>[
          'performed_at',
          'sync_device_id',
          'sync_previously_synced',
        ]),
      );
      expect(
        await _indexNames(database, AppDatabase.loggedSetsTable),
        containsAll(<String>[
          'logged_sets_workout_id_index',
          'logged_sets_exercise_id_index',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.integrationDataClassConsentsTable],
        containsAll(<String>[
          'id',
          'credential_id',
          'data_class',
          'enabled',
          'sync_device_id',
          'sync_previously_synced',
          'updated_at',
          'deleted_at',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.metricsTable],
        containsAll(<String>[
          'name',
          'unit',
          'value_shape',
          'metric_group',
          'goal_type',
          'goal_target_value',
          'enabled',
          'pinned',
          'sort_order',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.metricReadingsTable],
        containsAll(<String>[
          'metric_id',
          'value_json',
          'scalar_value',
          'scalar_entered',
          'at_time',
          'window_started_at',
          'window_ended_at',
          'provenance',
          'source',
          'external_id',
        ]),
      );
      expect(
        columnsByTable['workout_sessions'],
        containsAll(<String>[
          'started_at',
          'timezone',
          'local_date',
          'ended_at',
          'comment',
        ]),
      );
      expect(
        columnsByTable['workout_exercises'],
        containsAll(<String>['workout_id', 'exercise_id', 'position']),
      );
      expect(
        columnsByTable['exercise_groups'],
        containsAll(<String>['workout_id', 'name', 'color_hex', 'position']),
      );
      expect(
        columnsByTable['exercise_group_members'],
        containsAll(<String>['group_id', 'workout_exercise_id', 'position']),
      );
      expect(
        columnsByTable['logged_sets'],
        containsAll(<String>[
          'position',
          'planned_rest_after',
          'is_completed',
          'comment',
          'side',
          'rpe',
          'sync_device_id',
          'load_value',
          'load_unit',
          'load_entered',
          'reps_value',
          'reps_unit',
          'reps_entered',
          'duration_value',
          'duration_unit',
          'duration_entered',
          'distance_value',
          'distance_unit',
          'distance_entered',
        ]),
      );
      expect(
        columnsByTable['rest_timers'],
        containsAll(<String>[
          'workout_id',
          'source_set_id',
          'started_at',
          'deadline_at',
          'duration_seconds',
          'alert_volume',
          'status',
          'alert_fired_at',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.intervalTimersTable],
        containsAll(<String>[
          'workout_id',
          'started_at',
          'phase_started_at',
          'deadline_at',
          'current_step_index',
          'completed_set_count',
          'alert_volume',
          'phase',
          'status',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.intervalTimersTable],
        isNot(contains('routine_day_id')),
      );
    });

    test('scoped active history queries omit unrelated and archived rows',
        () async {
      final targetExerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Bench Press',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
      );
      final otherExerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Back Squat',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
      );
      final activeWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 7, 9, 8),
          timezone: 'UTC',
        ),
      );
      final archivedWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 7, 8, 8),
          timezone: 'UTC',
        ),
      );

      final targetSetId = await repositories.sets.create(
        LoggedSetDraft(
          workoutId: activeWorkoutId,
          exerciseId: targetExerciseId,
          position: 0,
          values: _loadRepsValues(load: '100', reps: '5'),
        ),
      );
      await repositories.sets.create(
        LoggedSetDraft(
          workoutId: activeWorkoutId,
          exerciseId: otherExerciseId,
          position: 1,
          values: _loadRepsValues(load: '120', reps: '3'),
        ),
      );
      final deletedTargetSetId = await repositories.sets.create(
        LoggedSetDraft(
          workoutId: activeWorkoutId,
          exerciseId: targetExerciseId,
          position: 2,
          values: _loadRepsValues(load: '90', reps: '8'),
        ),
      );
      await repositories.sets.softDelete(deletedTargetSetId);
      await repositories.workoutSessions.softDelete(archivedWorkoutId);

      final targetSets =
          await repositories.sets.listActiveForExercise(targetExerciseId);
      final activeWorkouts = await repositories.workoutSessions.listActiveByIds(
        <String>{activeWorkoutId, archivedWorkoutId, 'missing-workout'},
      );

      expect(targetSets.map((set) => set.id), <String>[
        targetSetId,
      ]);
      expect(
        targetSets.map((set) => set.id),
        isNot(contains(deletedTargetSetId)),
      );
      expect(
        targetSets.where((set) => set.exerciseId == otherExerciseId),
        isEmpty,
      );
      expect(activeWorkouts.map((workout) => workout.id), <String>[
        activeWorkoutId,
      ]);
    });

    test('scoped workout child watches omit unrelated and archived rows',
        () async {
      final benchId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Bench Press',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
      );
      final rowId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Barbell Row',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
      );
      final targetWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 7, 9, 8),
          timezone: 'UTC',
        ),
      );
      final secondTargetWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 7, 9, 18),
          timezone: 'UTC',
        ),
      );
      final unrelatedWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 7, 10, 8),
          timezone: 'UTC',
        ),
      );

      final targetWorkoutExerciseId =
          await repositories.workoutExercises.create(
        WorkoutExerciseDraft(workoutId: targetWorkoutId, exerciseId: benchId),
      );
      final deletedWorkoutExerciseId =
          await repositories.workoutExercises.create(
        WorkoutExerciseDraft(workoutId: targetWorkoutId, exerciseId: rowId),
      );
      final secondTargetWorkoutExerciseId =
          await repositories.workoutExercises.create(
        WorkoutExerciseDraft(
          workoutId: secondTargetWorkoutId,
          exerciseId: rowId,
        ),
      );
      final unrelatedWorkoutExerciseId =
          await repositories.workoutExercises.create(
        WorkoutExerciseDraft(
          workoutId: unrelatedWorkoutId,
          exerciseId: benchId,
        ),
      );
      await repositories.workoutExercises.softDelete(deletedWorkoutExerciseId);

      final targetSetId = await _createLoadRepsSet(
        repositories,
        workoutId: targetWorkoutId,
        exerciseId: benchId,
        position: 0,
        load: '100',
        reps: '5',
      );
      final deletedSetId = await _createLoadRepsSet(
        repositories,
        workoutId: targetWorkoutId,
        exerciseId: rowId,
        position: 1,
        load: '90',
        reps: '8',
      );
      final unrelatedSetId = await _createLoadRepsSet(
        repositories,
        workoutId: unrelatedWorkoutId,
        exerciseId: benchId,
        position: 0,
        load: '80',
        reps: '10',
      );
      await repositories.sets.softDelete(deletedSetId);

      expect(
        await repositories.workoutExercises
            .watchActiveForWorkoutIds(<String>{}).first,
        isEmpty,
      );
      expect(
        await repositories.sets.watchActiveForWorkoutIds(<String>{}).first,
        isEmpty,
      );

      final workoutExerciseEmissions = <List<WorkoutExerciseRecord>>[];
      final setEmissions = <List<LoggedSetRecord>>[];
      final workoutExerciseSubscription =
          repositories.workoutExercises.watchActiveForWorkoutIds(<String>{
        targetWorkoutId,
        secondTargetWorkoutId,
      }).listen(workoutExerciseEmissions.add);
      final setSubscription = repositories.sets.watchActiveForWorkoutIds(
        <String>{targetWorkoutId, secondTargetWorkoutId},
      ).listen(setEmissions.add);
      addTearDown(workoutExerciseSubscription.cancel);
      addTearDown(setSubscription.cancel);

      await _waitFor(
        () => workoutExerciseEmissions.isNotEmpty && setEmissions.isNotEmpty,
      );

      expect(
        workoutExerciseEmissions.last.map((row) => row.id).toSet(),
        <String>{targetWorkoutExerciseId, secondTargetWorkoutExerciseId},
      );
      expect(
        workoutExerciseEmissions.last.map((row) => row.id),
        isNot(contains(unrelatedWorkoutExerciseId)),
      );
      expect(setEmissions.last.map((set) => set.id).toSet(), <String>{
        targetSetId,
      });
      expect(
          setEmissions.last.map((set) => set.id),
          isNot(contains(
            unrelatedSetId,
          )));

      final secondTargetSetId = await _createLoadRepsSet(
        repositories,
        workoutId: secondTargetWorkoutId,
        exerciseId: rowId,
        position: 0,
        load: '70',
        reps: '12',
      );

      await _waitFor(
        () => setEmissions.last.any((set) => set.id == secondTargetSetId),
      );
      expect(setEmissions.last.map((set) => set.id).toSet(), <String>{
        targetSetId,
        secondTargetSetId,
      });
    });

    test('exercise groups persist, round-robin, and activity log changes',
        () async {
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 6),
          timezone: 'Australia/Brisbane',
        ),
        actor: 'tester',
      );
      final benchId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Bench Press',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
        actor: 'tester',
      );
      final rowId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Barbell Row',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
        actor: 'tester',
      );
      final curlId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Curl',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
        actor: 'tester',
      );
      final benchWorkoutExerciseId = await repositories.workoutExercises.create(
        WorkoutExerciseDraft(workoutId: workoutId, exerciseId: benchId),
        actor: 'tester',
      );
      final rowWorkoutExerciseId = await repositories.workoutExercises.create(
        WorkoutExerciseDraft(workoutId: workoutId, exerciseId: rowId),
        actor: 'tester',
      );
      final curlWorkoutExerciseId = await repositories.workoutExercises.create(
        WorkoutExerciseDraft(workoutId: workoutId, exerciseId: curlId),
        actor: 'tester',
      );

      final groupId = await repositories.exerciseGroups.create(
        ExerciseGroupDraft(
          workoutId: workoutId,
          name: 'A1 superset',
          colorHex: '#ab12cd',
          workoutExerciseIds: <String>[
            benchWorkoutExerciseId,
            rowWorkoutExerciseId,
          ],
        ),
        actor: 'tester',
      );

      var groups = await repositories.exerciseGroups.listActiveForWorkout(
        workoutId,
      );
      expect(groups.single.id, groupId);
      expect(groups.single.name, 'A1 superset');
      expect(groups.single.colorHex, '#AB12CD');
      expect(
        groups.single.members.map((member) => member.workoutExerciseId),
        <String>[benchWorkoutExerciseId, rowWorkoutExerciseId],
      );

      await repositories.exerciseGroups.update(
        groupId,
        name: 'Upper pair',
        colorHex: '#0891b2',
        workoutExerciseIds: <String>[
          rowWorkoutExerciseId,
          curlWorkoutExerciseId,
        ],
        actor: 'tester',
      );

      groups = await repositories.exerciseGroups.listActiveForWorkout(
        workoutId,
      );
      final logs = await repositories.activityLog.listEntries();
      final groupUpdateLog = logs.singleWhere(
        (entry) =>
            entry.entityTable == AppDatabase.exerciseGroupsTable &&
            entry.entityId == groupId &&
            entry.beforeImage?['name'] == 'A1 superset' &&
            entry.afterImage?['name'] == 'Upper pair',
      );
      final removedMemberLog = logs.singleWhere(
        (entry) =>
            entry.entityTable == AppDatabase.exerciseGroupMembersTable &&
            entry.beforeImage?['workout_exercise_id'] ==
                benchWorkoutExerciseId &&
            entry.beforeImage?['deleted_at'] == null &&
            entry.afterImage?['deleted_at'] != null,
      );
      final addedMemberLog = logs.singleWhere(
        (entry) =>
            entry.entityTable == AppDatabase.exerciseGroupMembersTable &&
            entry.beforeImage == null &&
            entry.afterImage?['workout_exercise_id'] == curlWorkoutExerciseId,
      );

      expect(groupUpdateLog.actor, 'tester');
      expect(removedMemberLog.actor, 'tester');
      expect(addedMemberLog.actor, 'tester');
      expect(groups.single.colorHex, '#0891B2');
      expect(
        groups.single.members.map((member) => member.workoutExerciseId),
        <String>[rowWorkoutExerciseId, curlWorkoutExerciseId],
      );
    });

    test('adjacent links merge and unlink across an unlimited circuit',
        () async {
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 6),
          timezone: 'Australia/Brisbane',
        ),
        actor: 'tester',
      );
      final workoutExerciseIds = <String>[];
      for (final name in <String>['Squat', 'Row', 'Press', 'Carry']) {
        final exerciseId = await repositories.exercises.create(
          ExerciseDraft(
            name: name,
            type: ExerciseType(<DimensionId>[
              DimensionId.load,
              DimensionId.reps,
            ]),
          ),
          actor: 'tester',
        );
        workoutExerciseIds.add(
          await repositories.workoutExercises.create(
            WorkoutExerciseDraft(
              workoutId: workoutId,
              exerciseId: exerciseId,
            ),
            actor: 'tester',
          ),
        );
      }

      await repositories.exerciseGroups.linkAdjacent(
        workoutId: workoutId,
        firstWorkoutExerciseId: workoutExerciseIds[0],
        secondWorkoutExerciseId: workoutExerciseIds[1],
        actor: 'tester',
      );
      await repositories.exerciseGroups.linkAdjacent(
        workoutId: workoutId,
        firstWorkoutExerciseId: workoutExerciseIds[2],
        secondWorkoutExerciseId: workoutExerciseIds[3],
        actor: 'tester',
      );
      await repositories.exerciseGroups.linkAdjacent(
        workoutId: workoutId,
        firstWorkoutExerciseId: workoutExerciseIds[1],
        secondWorkoutExerciseId: workoutExerciseIds[2],
        actor: 'tester',
      );

      final groups = await repositories.exerciseGroups.listActiveForWorkout(
        workoutId,
      );
      expect(groups, hasLength(1));
      expect(groups.single.workoutExerciseIds, workoutExerciseIds);

      await repositories.exerciseGroups.unlinkAdjacent(
        workoutId: workoutId,
        firstWorkoutExerciseId: workoutExerciseIds[1],
        secondWorkoutExerciseId: workoutExerciseIds[2],
        actor: 'tester',
      );

      final splitGroups =
          await repositories.exerciseGroups.listActiveForWorkout(workoutId);
      expect(splitGroups, hasLength(2));
      expect(
        splitGroups.map((group) => group.workoutExerciseIds),
        <List<String>>[
          workoutExerciseIds.sublist(0, 2),
          workoutExerciseIds.sublist(2, 4),
        ],
      );
      expect(
        splitGroups.map((group) => group.colorHex).toSet(),
        hasLength(2),
        reason: 'separate adjacent groups need distinct edge-bar colors',
      );

      await repositories.exerciseGroups.unlinkAdjacent(
        workoutId: workoutId,
        firstWorkoutExerciseId: workoutExerciseIds[0],
        secondWorkoutExerciseId: workoutExerciseIds[1],
        actor: 'tester',
      );

      final remainingGroups =
          await repositories.exerciseGroups.listActiveForWorkout(workoutId);
      expect(remainingGroups, hasLength(1));
      expect(
        remainingGroups.single.workoutExerciseIds,
        workoutExerciseIds.sublist(2, 4),
      );
    });

    test('new adjacent links keep active Exercise Group names unique',
        () async {
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 6),
          timezone: 'Australia/Brisbane',
        ),
        actor: 'tester',
      );
      final workoutExerciseIds = <String>[];
      for (final name in <String>[
        'Squat',
        'Row',
        'Press',
        'Carry',
        'Lunge',
        'Pull-up',
      ]) {
        final exerciseId = await repositories.exercises.create(
          ExerciseDraft(
            name: name,
            type: ExerciseType(<DimensionId>[DimensionId.reps]),
          ),
          actor: 'tester',
        );
        workoutExerciseIds.add(
          await repositories.workoutExercises.create(
            WorkoutExerciseDraft(
              workoutId: workoutId,
              exerciseId: exerciseId,
            ),
            actor: 'tester',
          ),
        );
      }

      for (final pair in <(int, int)>[(0, 1), (2, 3)]) {
        await repositories.exerciseGroups.linkAdjacent(
          workoutId: workoutId,
          firstWorkoutExerciseId: workoutExerciseIds[pair.$1],
          secondWorkoutExerciseId: workoutExerciseIds[pair.$2],
          actor: 'tester',
        );
      }
      await repositories.exerciseGroups.unlinkAdjacent(
        workoutId: workoutId,
        firstWorkoutExerciseId: workoutExerciseIds[0],
        secondWorkoutExerciseId: workoutExerciseIds[1],
        actor: 'tester',
      );
      await repositories.exerciseGroups.linkAdjacent(
        workoutId: workoutId,
        firstWorkoutExerciseId: workoutExerciseIds[4],
        secondWorkoutExerciseId: workoutExerciseIds[5],
        actor: 'tester',
      );

      final groups = await repositories.exerciseGroups.listActiveForWorkout(
        workoutId,
      );
      expect(groups, hasLength(2));
      expect(groups.map((group) => group.name).toSet(), hasLength(2));
    });

    test('reorder splits Exercise Groups into contiguous runs', () async {
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 6),
          timezone: 'Australia/Brisbane',
        ),
        actor: 'tester',
      );
      final workoutExerciseIds = <String>[];
      for (final name in <String>['Squat', 'Row', 'Press', 'Carry', 'Lunge']) {
        final exerciseId = await repositories.exercises.create(
          ExerciseDraft(
            name: name,
            type: ExerciseType(<DimensionId>[DimensionId.reps]),
          ),
          actor: 'tester',
        );
        workoutExerciseIds.add(
          await repositories.workoutExercises.create(
            WorkoutExerciseDraft(
              workoutId: workoutId,
              exerciseId: exerciseId,
            ),
            actor: 'tester',
          ),
        );
      }
      for (var index = 0; index < 3; index += 1) {
        await repositories.exerciseGroups.linkAdjacent(
          workoutId: workoutId,
          firstWorkoutExerciseId: workoutExerciseIds[index],
          secondWorkoutExerciseId: workoutExerciseIds[index + 1],
          actor: 'tester',
        );
      }

      await repositories.workoutExercises.reorderForWorkout(
        workoutId: workoutId,
        orderedIds: <String>[
          workoutExerciseIds[0],
          workoutExerciseIds[1],
          workoutExerciseIds[4],
          workoutExerciseIds[2],
          workoutExerciseIds[3],
        ],
        actor: 'tester',
      );

      final groups = await repositories.exerciseGroups.listActiveForWorkout(
        workoutId,
      );
      expect(
        groups.map((group) => group.workoutExerciseIds),
        <List<String>>[
          workoutExerciseIds.sublist(0, 2),
          workoutExerciseIds.sublist(2, 4),
        ],
      );
      expect(groups.map((group) => group.colorHex).toSet(), hasLength(2));
    });

    test('Workout and Training Day summaries react to a new Exercise Group',
        () async {
      const trainingDay = TrainingDayDate(year: 2026, month: 6, day: 14);
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 6),
          timezone: 'Australia/Brisbane',
          localDate: trainingDay,
        ),
        actor: 'tester',
      );
      final workoutExerciseIds = <String>[];
      for (final name in <String>['Split Squat', 'Pull-up', 'Push-up']) {
        final exerciseId = await repositories.exercises.create(
          ExerciseDraft(
            name: name,
            type: ExerciseType(<DimensionId>[DimensionId.reps]),
          ),
          actor: 'tester',
        );
        workoutExerciseIds.add(
          await repositories.workoutExercises.create(
            WorkoutExerciseDraft(
              workoutId: workoutId,
              exerciseId: exerciseId,
            ),
            actor: 'tester',
          ),
        );
      }

      final homeRepository = RepositoryHomeRepository(repositories);
      final emissions = <HomeWorkoutSummary?>[];
      final subscription =
          homeRepository.watchWorkout(workoutId).listen(emissions.add);
      addTearDown(subscription.cancel);
      final dayEmissions = <HomeSummary>[];
      final daySubscription =
          homeRepository.watchTrainingDay(trainingDay).listen(dayEmissions.add);
      addTearDown(daySubscription.cancel);
      await _waitFor(() => emissions.any((summary) => summary != null));

      await homeRepository.linkWorkoutExercisesAsSuperset(
        workoutId: workoutId,
        firstWorkoutExerciseId: workoutExerciseIds[0],
        secondWorkoutExerciseId: workoutExerciseIds[1],
      );
      await homeRepository.linkWorkoutExercisesAsSuperset(
        workoutId: workoutId,
        firstWorkoutExerciseId: workoutExerciseIds[1],
        secondWorkoutExerciseId: workoutExerciseIds[2],
      );

      await _waitFor(
        () => emissions.any(
          (summary) =>
              summary?.exerciseGroups.singleOrNull?.workoutExerciseIds.length ==
              3,
        ),
      );
      expect(
        emissions.last!.exerciseGroups.single.workoutExerciseIds,
        workoutExerciseIds,
      );
      await _waitFor(
        () => dayEmissions.any(
          (summary) =>
              summary.workouts.singleOrNull?.exerciseGroups.singleOrNull
                  ?.workoutExerciseIds.length ==
              3,
        ),
      );
      expect(
        dayEmissions
            .last.workouts.single.exerciseGroups.single.workoutExerciseIds,
        workoutExerciseIds,
      );
    });

    test('exercise group watcher ignores unrelated group member changes',
        () async {
      final targetWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 6),
          timezone: 'Australia/Brisbane',
        ),
      );
      final unrelatedWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 15, 6),
          timezone: 'Australia/Brisbane',
        ),
      );
      final benchId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Bench Press',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
      );
      final rowId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Barbell Row',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
      );
      final curlId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Curl',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
      );

      final targetBenchWorkoutExerciseId =
          await repositories.workoutExercises.create(
        WorkoutExerciseDraft(workoutId: targetWorkoutId, exerciseId: benchId),
      );
      final targetRowWorkoutExerciseId =
          await repositories.workoutExercises.create(
        WorkoutExerciseDraft(workoutId: targetWorkoutId, exerciseId: rowId),
      );
      final unrelatedBenchWorkoutExerciseId =
          await repositories.workoutExercises.create(
        WorkoutExerciseDraft(
          workoutId: unrelatedWorkoutId,
          exerciseId: benchId,
        ),
      );
      final unrelatedRowWorkoutExerciseId =
          await repositories.workoutExercises.create(
        WorkoutExerciseDraft(workoutId: unrelatedWorkoutId, exerciseId: rowId),
      );
      final unrelatedCurlWorkoutExerciseId =
          await repositories.workoutExercises.create(
        WorkoutExerciseDraft(workoutId: unrelatedWorkoutId, exerciseId: curlId),
      );

      final targetGroupId = await repositories.exerciseGroups.create(
        ExerciseGroupDraft(
          workoutId: targetWorkoutId,
          name: 'A1 superset',
          colorHex: '#ab12cd',
          workoutExerciseIds: <String>[
            targetBenchWorkoutExerciseId,
            targetRowWorkoutExerciseId,
          ],
        ),
      );
      final unrelatedGroupId = await repositories.exerciseGroups.create(
        ExerciseGroupDraft(
          workoutId: unrelatedWorkoutId,
          name: 'Other day pair',
          colorHex: '#0891b2',
          workoutExerciseIds: <String>[
            unrelatedBenchWorkoutExerciseId,
            unrelatedRowWorkoutExerciseId,
          ],
        ),
      );

      final emissions = <List<ExerciseGroupRecord>>[];
      final subscription = repositories.exerciseGroups
          .watchActiveForWorkout(targetWorkoutId)
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      await _waitFor(() => emissions.isNotEmpty);
      expect(emissions.last.map((group) => group.id), <String>[
        targetGroupId,
      ]);
      final initialEmissionCount = emissions.length;

      await repositories.exerciseGroups.update(
        unrelatedGroupId,
        name: 'Other day pair',
        colorHex: '#0891b2',
        workoutExerciseIds: <String>[
          unrelatedRowWorkoutExerciseId,
          unrelatedCurlWorkoutExerciseId,
        ],
      );
      for (var index = 0; index < 5; index += 1) {
        await pumpEventQueue();
      }

      expect(emissions, hasLength(initialEmissionCount));
      expect(
        emissions.last.single.members.map((member) => member.workoutExerciseId),
        <String>[targetBenchWorkoutExerciseId, targetRowWorkoutExerciseId],
      );
    });

    test('exercise groups survive reopening the database', () async {
      final directory = await Directory.systemTemp.createTemp('perennia_test_');
      addTearDown(() => directory.delete(recursive: true));

      final databaseFile = File('${directory.path}/exercise_groups.sqlite');
      final firstDatabase = AppDatabase.openFile(databaseFile);
      final firstRepositories = TrainingRepositories(firstDatabase);
      final workoutId = await firstRepositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 6),
          timezone: 'Australia/Brisbane',
        ),
      );
      final squatId = await firstRepositories.exercises.create(
        ExerciseDraft(
          name: 'Front Squat',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
      );
      final lungeId = await firstRepositories.exercises.create(
        ExerciseDraft(
          name: 'Reverse Lunge',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
      );
      final squatWorkoutExerciseId =
          await firstRepositories.workoutExercises.create(
        WorkoutExerciseDraft(workoutId: workoutId, exerciseId: squatId),
      );
      final lungeWorkoutExerciseId =
          await firstRepositories.workoutExercises.create(
        WorkoutExerciseDraft(workoutId: workoutId, exerciseId: lungeId),
      );
      final groupId = await firstRepositories.exerciseGroups.create(
        ExerciseGroupDraft(
          workoutId: workoutId,
          name: 'Leg circuit',
          colorHex: '#E11D48',
          workoutExerciseIds: <String>[
            squatWorkoutExerciseId,
            lungeWorkoutExerciseId,
          ],
        ),
      );
      await firstDatabase.close();

      final reopenedDatabase = AppDatabase.openFile(databaseFile);
      addTearDown(reopenedDatabase.close);
      final reopenedRepositories = TrainingRepositories(reopenedDatabase);

      final groups = await reopenedRepositories.exerciseGroups
          .listActiveForWorkout(workoutId);

      expect(groups.single.id, groupId);
      expect(groups.single.name, 'Leg circuit');
      expect(groups.single.colorHex, '#E11D48');
      expect(
        groups.single.members.map((member) => member.workoutExerciseId),
        <String>[squatWorkoutExerciseId, lungeWorkoutExerciseId],
      );
    });

    test('set annotations are optional, persisted, and activity logged',
        () async {
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Split Squat',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
          isUnilateral: true,
          usesRpe: true,
        ),
        actor: 'tester',
      );
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 6),
          timezone: 'Australia/Brisbane',
        ),
        actor: 'tester',
      );
      final annotatedSetId = await repositories.sets.create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
          position: 0,
          values: LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.load,
                entered: '24',
                unit: TrainingUnit.kilogram,
              ),
              SetDimensionValue(
                dimension: DimensionId.reps,
                entered: '8',
                unit: TrainingUnit.repetition,
              ),
            ],
          ),
          comment: 'Steady tempo',
          side: SetSide.left,
          rpe: 7.5,
        ),
        actor: 'tester',
      );
      final bareSetId = await repositories.sets.create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
          position: 1,
          values: LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.load,
                entered: '24',
                unit: TrainingUnit.kilogram,
              ),
              SetDimensionValue(
                dimension: DimensionId.reps,
                entered: '8',
                unit: TrainingUnit.repetition,
              ),
            ],
          ),
        ),
        actor: 'tester',
      );

      await repositories.sets.updateAnnotations(
        annotatedSetId,
        comment: 'Hard finish',
        side: SetSide.right,
        rpe: 8,
        actor: 'tester',
      );

      final annotatedSet = await repositories.sets.getById(annotatedSetId);
      final bareSet = await repositories.sets.getById(bareSetId);
      final logs = await repositories.activityLog.listEntries();
      final annotationLog = logs.singleWhere(
        (entry) =>
            entry.entityTable == AppDatabase.loggedSetsTable &&
            entry.entityId == annotatedSetId &&
            entry.beforeImage?['comment'] == 'Steady tempo' &&
            entry.beforeImage?['side'] == 'left' &&
            entry.beforeImage?['rpe'] == 7.5 &&
            entry.afterImage?['comment'] == 'Hard finish' &&
            entry.afterImage?['side'] == 'right' &&
            entry.afterImage?['rpe'] == 8,
      );

      expect(annotatedSet?.comment, 'Hard finish');
      expect(annotatedSet?.side, SetSide.right);
      expect(annotatedSet?.rpe, 8);
      expect(bareSet?.comment, isNull);
      expect(bareSet?.side, isNull);
      expect(bareSet?.rpe, isNull);
      expect(annotationLog.actor, 'tester');
    });

    test('set performed timestamps default locally and sync explicitly',
        () async {
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Stair Master',
          type: ExerciseType(<DimensionId>[
            DimensionId.duration,
            DimensionId.distance,
          ]),
        ),
        actor: 'tester',
      );
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 6),
          timezone: 'Australia/Brisbane',
        ),
        actor: 'tester',
      );

      final defaultedSetId = await repositories.sets.create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
          position: 0,
          values: LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.duration,
                entered: '600',
                unit: TrainingUnit.second,
              ),
            ],
          ),
        ),
        actor: 'tester',
      );
      final explicitPerformedAt = DateTime.utc(2026, 6, 14, 6, 15);
      final explicitSetId = await repositories.sets.create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
          position: 1,
          performedAt: explicitPerformedAt,
          values: LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.duration,
                entered: '1200',
                unit: TrainingUnit.second,
              ),
              SetDimensionValue(
                dimension: DimensionId.distance,
                entered: '0.5',
                unit: TrainingUnit.kilometer,
              ),
            ],
          ),
        ),
        actor: 'tester',
      );
      final syncedPerformedAt = DateTime.utc(2026, 6, 14, 6, 45);
      await repositories.sets.applySyncImage(
        image: <String, Object?>{
          'id': '01910000-0000-7000-8000-000000099999',
          'workout_id': workoutId,
          'exercise_id': exerciseId,
          'position': 2,
          'planned_rest_after': null,
          'performed_at': syncedPerformedAt.toIso8601String(),
          'is_completed': true,
          'load_value': null,
          'load_unit': null,
          'load_entered': null,
          'reps_value': null,
          'reps_unit': null,
          'reps_entered': null,
          'duration_value': 300.0,
          'duration_unit': TrainingUnit.second.name,
          'duration_entered': '300',
          'distance_value': null,
          'distance_unit': null,
          'distance_entered': null,
          'comment': null,
          'side': null,
          'rpe': null,
          'updated_at': DateTime.utc(2026, 6, 14, 7).toIso8601String(),
          'deleted_at': null,
        },
        deviceId: 'device-b',
        batchId: 'sync-batch',
        actor: 'sync',
      );

      final defaultedSet = await repositories.sets.getById(defaultedSetId);
      final explicitSet = await repositories.sets.getById(explicitSetId);
      final syncedSet = await repositories.sets.getById(
        '01910000-0000-7000-8000-000000099999',
      );
      final logs = await repositories.activityLog.listEntries();
      final explicitCreateLog = logs.singleWhere(
        (entry) =>
            entry.entityTable == AppDatabase.loggedSetsTable &&
            entry.entityId == explicitSetId &&
            entry.beforeImage == null,
      );
      final syncLog = logs.singleWhere(
        (entry) =>
            entry.entityTable == AppDatabase.loggedSetsTable &&
            entry.entityId == '01910000-0000-7000-8000-000000099999',
      );

      expect(defaultedSet?.performedAt, isNotNull);
      expect(defaultedSet!.performedAt, defaultedSet.updatedAt);
      expect(explicitSet?.performedAt, explicitPerformedAt);
      expect(syncedSet?.performedAt, syncedPerformedAt);
      expect(
        explicitCreateLog.afterImage?['performed_at'],
        explicitPerformedAt.toIso8601String(),
      );
      expect(
        syncLog.afterImage?['performed_at'],
        syncedPerformedAt.toIso8601String(),
      );
    });

    test('set performed timestamp survives value and annotation edits',
        () async {
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Bench Press',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
          isUnilateral: true,
          usesRpe: true,
        ),
        actor: 'tester',
      );
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 6),
          timezone: 'Australia/Brisbane',
        ),
        actor: 'tester',
      );
      final performedAt = DateTime.utc(2026, 6, 14, 6, 12);
      final setId = await repositories.sets.create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
          position: 0,
          performedAt: performedAt,
          values: LoggedSet.fromValues(
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
            ],
          ),
          comment: 'Paused',
          side: SetSide.left,
          rpe: 7.5,
        ),
        actor: 'tester',
      );

      await (database.update(database.loggedSets)
            ..where((row) => row.id.equals(setId)))
          .write(
        LoggedSetsCompanion(
          updatedAt: Value<DateTime>(DateTime.utc(2020)),
        ),
      );
      final beforeValueEdit = await repositories.sets.getById(setId);

      await repositories.sets.updateValues(
        setId,
        values: LoggedSet.fromValues(
          const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.load,
              entered: '102.5',
              unit: TrainingUnit.kilogram,
            ),
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '5',
              unit: TrainingUnit.repetition,
            ),
          ],
        ),
        actor: 'tester',
      );
      final afterValueEdit = await repositories.sets.getById(setId);

      expect(beforeValueEdit?.performedAt, performedAt);
      expect(afterValueEdit?.performedAt, performedAt);
      expect(
        afterValueEdit!.updatedAt.isAfter(beforeValueEdit!.updatedAt),
        isTrue,
      );
      expect(afterValueEdit.values.load?.entered, '102.5');

      await (database.update(database.loggedSets)
            ..where((row) => row.id.equals(setId)))
          .write(
        LoggedSetsCompanion(
          updatedAt: Value<DateTime>(DateTime.utc(2020, 1, 2)),
        ),
      );
      final beforeAnnotationEdit = await repositories.sets.getById(setId);

      await repositories.sets.updateAnnotations(
        setId,
        comment: 'Fast finish',
        side: SetSide.right,
        rpe: 8,
        actor: 'tester',
      );
      final afterAnnotationEdit = await repositories.sets.getById(setId);

      expect(beforeAnnotationEdit?.performedAt, performedAt);
      expect(afterAnnotationEdit?.performedAt, performedAt);
      expect(
        afterAnnotationEdit!.updatedAt.isAfter(beforeAnnotationEdit!.updatedAt),
        isTrue,
      );
      expect(afterAnnotationEdit.comment, 'Fast finish');
      expect(afterAnnotationEdit.side, SetSide.right);
      expect(afterAnnotationEdit.rpe, 8);
    });

    test('pulled Logged Set fallback never overwrites an authoritative Workout',
        () async {
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Front Squat',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
        actor: 'tester',
      );
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 7, 20, 6),
          timezone: 'Australia/Brisbane',
          comment: 'Authoritative comment',
        ),
        actor: 'tester',
      );
      final authoritative = await repositories.workoutSessions.getById(
        workoutId,
      );

      await repositories.sets.applySyncImage(
        image: <String, Object?>{
          'id': '01910000-0000-7000-8000-000000099998',
          'workout_id': workoutId,
          'exercise_id': exerciseId,
          'position': 0,
          'planned_rest_after': null,
          'performed_at': '2026-07-20T06:05:00.000Z',
          'is_completed': true,
          'load_value': 60.0,
          'load_unit': TrainingUnit.kilogram.name,
          'load_entered': '60',
          'reps_value': 5.0,
          'reps_unit': TrainingUnit.repetition.name,
          'reps_entered': '5',
          'duration_value': null,
          'duration_unit': null,
          'duration_entered': null,
          'distance_value': null,
          'distance_unit': null,
          'distance_entered': null,
          'comment': null,
          'side': null,
          'rpe': null,
          'updated_at': '2026-07-20T06:05:00.000Z',
          'deleted_at': null,
          'workout_started_at': '2026-07-19T01:00:00.000Z',
          'workout_ended_at': null,
          'workout_timezone': 'UTC',
          'workout_local_date': '2026-07-19',
          'workout_comment': 'Stale denormalized comment',
        },
        deviceId: 'device-b',
        batchId: 'sync-batch',
      );

      final after = await repositories.workoutSessions.getById(workoutId);
      expect(after?.startedAt, authoritative?.startedAt);
      expect(after?.timezone, 'Australia/Brisbane');
      expect(after?.localDate, authoritative?.localDate);
      expect(after?.comment, 'Authoritative comment');
      expect(after?.updatedAt, authoritative?.updatedAt);
    });

    test('set validation hard-rejects impossible local saves', () async {
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Back Squat',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
        actor: 'tester',
      );
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 6),
          timezone: 'Australia/Brisbane',
        ),
        actor: 'tester',
      );
      final warningDraft = LoggedSetDraft(
        workoutId: workoutId,
        exerciseId: exerciseId,
        position: 0,
        values: LoggedSet.fromValues(
          const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.load,
              entered: '351',
              unit: TrainingUnit.kilogram,
            ),
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '5',
              unit: TrainingUnit.repetition,
            ),
          ],
        ),
      );

      final validation = await repositories.sets.validateEntry(warningDraft);
      expect(validation.accepted, isTrue);
      expect(
        validation.warnings
            .map((warning) => warning.rule)
            .toList(growable: false),
        <String>['added_load_improbable'],
      );

      await expectLater(
        repositories.sets.create(
          LoggedSetDraft(
            workoutId: workoutId,
            exerciseId: exerciseId,
            position: 0,
            values: LoggedSet.fromValues(
              const <SetDimensionValue>[
                SetDimensionValue(
                  dimension: DimensionId.load,
                  entered: '-1',
                  unit: TrainingUnit.kilogram,
                ),
                SetDimensionValue(
                  dimension: DimensionId.reps,
                  entered: '5',
                  unit: TrainingUnit.repetition,
                ),
              ],
            ),
          ),
          actor: 'tester',
        ),
        throwsA(
          isA<SetValidationException>().having(
            (error) => error.errors.map((issue) => issue.rule),
            'rules',
            contains('numeric_non_negative'),
          ),
        ),
      );

      final setId =
          await repositories.sets.create(warningDraft, actor: 'tester');
      await expectLater(
        repositories.sets.updateValues(
          setId,
          values: LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.load,
                entered: '100',
                unit: TrainingUnit.kilogram,
              ),
              SetDimensionValue(
                dimension: DimensionId.reps,
                entered: '2.5',
                unit: TrainingUnit.repetition,
              ),
            ],
          ),
          actor: 'tester',
        ),
        throwsA(
          isA<SetValidationException>().having(
            (error) => error.errors.map((issue) => issue.rule),
            'rules',
            contains('reps_integer'),
          ),
        ),
      );

      final unchanged = await repositories.sets.getById(setId);
      expect(unchanged?.values.reps?.entered, '5');
    });

    test('create, update, and soft-delete append before and after images',
        () async {
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Back Squat',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
        actor: 'tester',
      );

      await repositories.exercises.rename(
        exerciseId,
        name: 'High-Bar Back Squat',
        actor: 'tester',
      );
      await repositories.exercises.softDelete(exerciseId, actor: 'tester');

      final logs = await repositories.activityLog.listEntries();

      expect(logs, hasLength(3));
      expect(logs.map((entry) => entry.actor), everyElement('tester'));

      final updateLog = logs[1];
      expect(updateLog.entityTable, 'exercises');
      expect(updateLog.entityId, exerciseId);
      expect(updateLog.beforeImage?['name'], 'Back Squat');
      expect(updateLog.afterImage?['name'], 'High-Bar Back Squat');

      final deleteLog = logs[2];
      expect(deleteLog.beforeImage?['deleted_at'], isNull);
      expect(deleteLog.afterImage?['deleted_at'], isNotNull);

      final activeExercises = await repositories.exercises.listActive();
      expect(activeExercises, isEmpty);
    });

    test('workout session and set repositories update and soft-delete',
        () async {
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Pull-Up',
          type: ExerciseType(<DimensionId>[DimensionId.reps]),
        ),
        actor: 'tester',
      );
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 6),
          timezone: 'Australia/Brisbane',
        ),
        actor: 'tester',
      );
      final setId = await repositories.sets.create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
          position: 0,
          values: LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.reps,
                entered: '5',
                unit: TrainingUnit.repetition,
              ),
            ],
          ),
        ),
        actor: 'tester',
      );

      await repositories.workoutSessions.updateEndedAt(
        workoutId,
        endedAt: DateTime.utc(2026, 6, 14, 7),
        actor: 'tester',
      );
      await repositories.sets.updateValues(
        setId,
        values: LoggedSet.fromValues(
          const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '6',
              unit: TrainingUnit.repetition,
            ),
          ],
        ),
        actor: 'tester',
      );
      await repositories.sets.softDelete(setId, actor: 'tester');
      await repositories.workoutSessions.softDelete(workoutId, actor: 'tester');

      final logs = await repositories.activityLog.listEntries();
      final workoutUpdate = logs.singleWhere(
        (entry) =>
            entry.entityTable == 'workout_sessions' &&
            entry.beforeImage?['ended_at'] == null &&
            entry.afterImage?['ended_at'] != null,
      );
      final setUpdate = logs.singleWhere(
        (entry) =>
            entry.entityTable == 'logged_sets' &&
            entry.beforeImage?['reps_entered'] == '5' &&
            entry.afterImage?['reps_entered'] == '6',
      );

      expect(workoutUpdate.actor, 'tester');
      expect(setUpdate.actor, 'tester');
      expect(await repositories.workoutSessions.listActive(), isEmpty);
      expect(await repositories.sets.listActiveForWorkout(workoutId), isEmpty);
    });

    test('soft-deleting a workout archives its exercise entries and sets',
        () async {
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Deadlift',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
        actor: 'tester',
      );
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 6),
          timezone: 'Australia/Brisbane',
        ),
        actor: 'tester',
      );
      await repositories.workoutExercises.create(
        WorkoutExerciseDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
        ),
        actor: 'tester',
      );
      await repositories.sets.create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
          position: 0,
          values: LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.load,
                entered: '140',
                unit: TrainingUnit.kilogram,
              ),
              SetDimensionValue(
                dimension: DimensionId.reps,
                entered: '5',
                unit: TrainingUnit.repetition,
              ),
            ],
          ),
        ),
        actor: 'tester',
      );

      await repositories.workoutSessions.softDelete(
        workoutId,
        actor: 'tester',
      );

      expect(await repositories.workoutSessions.listActive(), isEmpty);
      expect(
        await repositories.workoutExercises.listActiveForWorkout(workoutId),
        isEmpty,
      );
      expect(await repositories.sets.listActiveForWorkout(workoutId), isEmpty);

      final logs = await repositories.activityLog.listEntries();
      final deleteLogs = logs
          .where(
            (entry) =>
                entry.afterImage?['deleted_at'] != null &&
                (entry.entityTable == AppDatabase.workoutSessionsTable ||
                    entry.entityTable == AppDatabase.workoutExercisesTable ||
                    entry.entityTable == AppDatabase.loggedSetsTable),
          )
          .toList(growable: false);

      expect(deleteLogs.map((entry) => entry.actor), everyElement('tester'));
      expect(deleteLogs.map((entry) => entry.batchId).toSet(), hasLength(1));
      expect(
        deleteLogs.map((entry) => entry.entityTable),
        containsAll(<String>[
          AppDatabase.workoutSessionsTable,
          AppDatabase.workoutExercisesTable,
          AppDatabase.loggedSetsTable,
        ]),
      );
    });

    test('adds catalog exercise to workout log with activity log', () async {
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Back Squat',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
        actor: 'tester',
      );
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 6),
          timezone: 'Australia/Brisbane',
        ),
        actor: 'tester',
      );

      final workoutExerciseId = await repositories.workoutExercises.create(
        WorkoutExerciseDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
        ),
        actor: 'tester',
      );
      await repositories.workoutExercises.create(
        WorkoutExerciseDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
        ),
        actor: 'tester',
      );

      final workoutExercises =
          await repositories.workoutExercises.listActiveForWorkout(workoutId);
      final logs = await repositories.activityLog.listEntries();
      final addLog = logs.singleWhere(
        (entry) =>
            entry.entityTable == AppDatabase.workoutExercisesTable &&
            entry.entityId == workoutExerciseId,
      );

      expect(workoutExercises, hasLength(1));
      expect(workoutExercises.single.id, workoutExerciseId);
      expect(workoutExercises.single.workoutId, workoutId);
      expect(workoutExercises.single.exerciseId, exerciseId);
      expect(workoutExercises.single.position, 0);
      expect(addLog.beforeImage, isNull);
      expect(addLog.afterImage?['workout_id'], workoutId);
      expect(addLog.afterImage?['exercise_id'], exerciseId);
    });

    test(
        'workout exercises can be reordered and removed with related workout data',
        () async {
      final squatId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Back Squat',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
        actor: 'tester',
      );
      final rowId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Row',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
        actor: 'tester',
      );
      final curlId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Curl',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
        actor: 'tester',
      );
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 6),
          timezone: 'Australia/Brisbane',
        ),
        actor: 'tester',
      );
      final squatWorkoutExerciseId = await repositories.workoutExercises.create(
        WorkoutExerciseDraft(workoutId: workoutId, exerciseId: squatId),
        actor: 'tester',
      );
      final rowWorkoutExerciseId = await repositories.workoutExercises.create(
        WorkoutExerciseDraft(workoutId: workoutId, exerciseId: rowId),
        actor: 'tester',
      );
      final curlWorkoutExerciseId = await repositories.workoutExercises.create(
        WorkoutExerciseDraft(workoutId: workoutId, exerciseId: curlId),
        actor: 'tester',
      );
      await _createLoadRepsSet(
        repositories,
        workoutId: workoutId,
        exerciseId: rowId,
        position: 0,
        load: '60',
        reps: '8',
      );
      final groupId = await repositories.exerciseGroups.create(
        ExerciseGroupDraft(
          workoutId: workoutId,
          name: 'Circuit',
          colorHex: '#2F6FED',
          workoutExerciseIds: <String>[
            squatWorkoutExerciseId,
            rowWorkoutExerciseId,
            curlWorkoutExerciseId,
          ],
        ),
        actor: 'tester',
      );

      await repositories.workoutExercises.reorderForWorkout(
        workoutId: workoutId,
        orderedIds: <String>[
          curlWorkoutExerciseId,
          squatWorkoutExerciseId,
          rowWorkoutExerciseId,
        ],
        actor: 'tester',
      );
      await repositories.workoutExercises.softDelete(
        rowWorkoutExerciseId,
        actor: 'tester',
      );

      final workoutExercises =
          await repositories.workoutExercises.listActiveForWorkout(workoutId);
      final sets = await repositories.sets.listActiveForWorkout(workoutId);
      final group = await repositories.exerciseGroups.getById(groupId);
      final logs = await repositories.activityLog.listEntries();
      final exerciseDeleteLog = logs.singleWhere(
        (entry) =>
            entry.entityTable == AppDatabase.workoutExercisesTable &&
            entry.entityId == rowWorkoutExerciseId &&
            entry.afterImage?['deleted_at'] != null,
      );
      final setDeleteLogs = logs.where(
        (entry) =>
            entry.entityTable == AppDatabase.loggedSetsTable &&
            entry.afterImage?['deleted_at'] != null,
      );
      final memberDeleteLog = logs.singleWhere(
        (entry) =>
            entry.entityTable == AppDatabase.exerciseGroupMembersTable &&
            entry.beforeImage?['workout_exercise_id'] == rowWorkoutExerciseId &&
            entry.afterImage?['deleted_at'] != null,
      );
      final reorderLogs = logs.where(
        (entry) =>
            entry.entityTable == AppDatabase.workoutExercisesTable &&
            entry.beforeImage != null &&
            entry.afterImage?['deleted_at'] == null &&
            entry.beforeImage?['position'] != entry.afterImage?['position'],
      );

      expect(workoutExercises.map((exercise) => exercise.id), <String>[
        curlWorkoutExerciseId,
        squatWorkoutExerciseId,
      ]);
      expect(sets, isEmpty);
      expect(group?.workoutExerciseIds, <String>[
        curlWorkoutExerciseId,
        squatWorkoutExerciseId,
      ]);
      expect(group?.members.map((member) => member.position), <int>[0, 1]);
      expect(exerciseDeleteLog.actor, 'tester');
      expect(setDeleteLogs.map((entry) => entry.actor), everyElement('tester'));
      expect(memberDeleteLog.actor, 'tester');
      expect(
        reorderLogs.map((entry) => entry.entityId),
        unorderedEquals(<String>[
          curlWorkoutExerciseId,
          squatWorkoutExerciseId,
          rowWorkoutExerciseId,
        ]),
      );
      expect(reorderLogs.map((entry) => entry.actor), everyElement('tester'));
    });

    test('logs a dimension-adaptive set for an exercise in a workout',
        () async {
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Bench Press',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
        actor: 'tester',
      );
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 6),
          timezone: 'Australia/Brisbane',
        ),
        actor: 'tester',
      );
      await repositories.workoutExercises.create(
        WorkoutExerciseDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
        ),
        actor: 'tester',
      );

      final setId = await repositories.sets.create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
          position: 0,
          values: LoggedSet.fromValues(
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
            ],
          ),
        ),
        actor: 'tester',
      );

      final set = await repositories.sets.getById(setId);
      final logs = await repositories.activityLog.listEntries();
      final setLog = logs.singleWhere(
        (entry) =>
            entry.entityTable == AppDatabase.loggedSetsTable &&
            entry.entityId == setId,
      );

      expect(set?.workoutId, workoutId);
      expect(set?.exerciseId, exerciseId);
      expect(set?.values.dimensionIds, <DimensionId>[
        DimensionId.load,
        DimensionId.reps,
      ]);
      expect(set?.values.load?.entered, '100');
      expect(set?.values.load?.unit, TrainingUnit.kilogram);
      expect(set?.values.reps?.entered, '5');
      expect(set?.values.reps?.unit, TrainingUnit.repetition);
      expect(setLog.beforeImage, isNull);
      expect(setLog.afterImage?['load_entered'], '100');
      expect(setLog.afterImage?['reps_entered'], '5');
    });

    test('workout sessions freeze and query by training day local date',
        () async {
      const trainingDay = TrainingDayDate(year: 2026, month: 6, day: 14);
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 15, 4),
          timezone: 'Pacific/Auckland',
          localDate: trainingDay,
        ),
        actor: 'tester',
      );

      await repositories.workoutSessions.updateEndedAt(
        workoutId,
        endedAt: DateTime.utc(2026, 6, 15, 5),
        actor: 'tester',
      );

      final workout = await repositories.workoutSessions.getById(workoutId);
      final sameDay = await repositories.workoutSessions.listActiveForLocalDate(
        trainingDay,
      );
      final nextDay = await repositories.workoutSessions.listActiveForLocalDate(
        trainingDay.addDays(1),
      );
      final logs = await repositories.activityLog.listEntries();
      final createLog = logs.firstWhere(
        (entry) =>
            entry.entityTable == AppDatabase.workoutSessionsTable &&
            entry.beforeImage == null,
      );

      expect(workout?.localDate, trainingDay);
      expect(sameDay.single.id, workoutId);
      expect(nextDay, isEmpty);
      expect(createLog.afterImage?['started_at'],
          DateTime.utc(2026, 6, 15, 4).toIso8601String());
      expect(createLog.afterImage?['timezone'], 'Pacific/Auckland');
      expect(createLog.afterImage?['local_date'], trainingDay.storageValue);
    });

    test('per-workout set queries keep entry position order after edits',
        () async {
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Bench Press',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
      );
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 5),
          timezone: 'Australia/Brisbane',
        ),
      );
      final firstSetId = await repositories.sets.create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
          position: 0,
          values: LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.load,
                entered: '80',
                unit: TrainingUnit.kilogram,
              ),
              SetDimensionValue(
                dimension: DimensionId.reps,
                entered: '5',
                unit: TrainingUnit.repetition,
              ),
            ],
          ),
        ),
      );
      final secondSetId = await repositories.sets.create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
          position: 1,
          values: LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.load,
                entered: '82.5',
                unit: TrainingUnit.kilogram,
              ),
              SetDimensionValue(
                dimension: DimensionId.reps,
                entered: '5',
                unit: TrainingUnit.repetition,
              ),
            ],
          ),
        ),
      );

      await repositories.sets.updateValues(
        firstSetId,
        values: LoggedSet.fromValues(
          const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.load,
              entered: '85',
              unit: TrainingUnit.kilogram,
            ),
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '5',
              unit: TrainingUnit.repetition,
            ),
          ],
        ),
      );
      // Make the edit timestamp definitively newer without slowing the suite.
      await (database.update(database.loggedSets)
            ..where((row) => row.id.equals(firstSetId)))
          .write(
        LoggedSetsCompanion(
          updatedAt: Value<DateTime>(DateTime.utc(2030)),
        ),
      );

      final sets = await repositories.sets.listActiveForWorkout(workoutId);

      expect(sets.map((set) => set.id), <String>[firstSetId, secondSetId]);
    });

    test('sets can be reordered and marked complete with activity logs',
        () async {
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Bench Press',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
      );
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 5),
          timezone: 'Australia/Brisbane',
        ),
      );
      final firstSetId = await repositories.sets.create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
          position: 0,
          values: LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.load,
                entered: '80',
                unit: TrainingUnit.kilogram,
              ),
              SetDimensionValue(
                dimension: DimensionId.reps,
                entered: '5',
                unit: TrainingUnit.repetition,
              ),
            ],
          ),
        ),
      );
      final secondSetId = await repositories.sets.create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
          position: 1,
          values: LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.load,
                entered: '82.5',
                unit: TrainingUnit.kilogram,
              ),
              SetDimensionValue(
                dimension: DimensionId.reps,
                entered: '5',
                unit: TrainingUnit.repetition,
              ),
            ],
          ),
        ),
      );
      final thirdSetId = await repositories.sets.create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
          position: 2,
          values: LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.load,
                entered: '85',
                unit: TrainingUnit.kilogram,
              ),
              SetDimensionValue(
                dimension: DimensionId.reps,
                entered: '3',
                unit: TrainingUnit.repetition,
              ),
            ],
          ),
        ),
      );

      await repositories.sets.setCompleted(
        secondSetId,
        isCompleted: true,
        actor: 'tester',
      );
      await repositories.sets.reorderForWorkoutExercise(
        workoutId: workoutId,
        exerciseId: exerciseId,
        orderedIds: <String>[thirdSetId, firstSetId, secondSetId],
        actor: 'tester',
      );

      final sets = await repositories.sets.listActiveForWorkout(workoutId);
      final logs = await repositories.activityLog.listEntries();
      final completionLog = logs.singleWhere(
        (entry) =>
            entry.entityTable == AppDatabase.loggedSetsTable &&
            entry.entityId == secondSetId &&
            entry.beforeImage?['is_completed'] == false &&
            entry.afterImage?['is_completed'] == true,
      );
      final reorderLogs = logs.where(
        (entry) =>
            entry.entityTable == AppDatabase.loggedSetsTable &&
            entry.beforeImage != null &&
            entry.beforeImage?['position'] != entry.afterImage?['position'],
      );

      expect(sets.map((set) => set.id), <String>[
        thirdSetId,
        firstSetId,
        secondSetId,
      ]);
      expect(sets.last.isCompleted, isTrue);
      expect(completionLog.actor, 'tester');
      expect(
        reorderLogs.map((entry) => entry.entityId),
        unorderedEquals(<String>[firstSetId, secondSetId, thirdSetId]),
      );
      expect(reorderLogs.map((entry) => entry.actor), everyElement('tester'));
    });

    test('finds latest performed prior set for exercise before current workout',
        () async {
      final benchId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Bench Press',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
      );
      final rowId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Row',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
      );
      final oldWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 1, 5),
          timezone: 'Australia/Brisbane',
        ),
      );
      final newerWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 7, 5),
          timezone: 'Australia/Brisbane',
        ),
      );
      final currentWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 5),
          timezone: 'Australia/Brisbane',
        ),
      );

      await _createLoadRepsSet(
        repositories,
        workoutId: oldWorkoutId,
        exerciseId: benchId,
        position: 0,
        load: '80',
        reps: '5',
        isCompleted: true,
      );
      await _createLoadRepsSet(
        repositories,
        workoutId: oldWorkoutId,
        exerciseId: benchId,
        position: 1,
        load: '82.5',
        reps: '4',
        isCompleted: true,
      );
      await _createLoadRepsSet(
        repositories,
        workoutId: newerWorkoutId,
        exerciseId: rowId,
        position: 0,
        load: '60',
        reps: '8',
        isCompleted: true,
      );
      final latestPriorId = await _createLoadRepsSet(
        repositories,
        workoutId: newerWorkoutId,
        exerciseId: benchId,
        position: 1,
        load: '85',
        reps: '3',
        isCompleted: true,
      );
      // A placeholder the Template left incomplete: never performed, so it
      // must not become the prefill even though it sits last.
      await _createLoadRepsSet(
        repositories,
        workoutId: newerWorkoutId,
        exerciseId: benchId,
        position: 2,
        load: '0',
        reps: '10',
      );
      await _createLoadRepsSet(
        repositories,
        workoutId: currentWorkoutId,
        exerciseId: benchId,
        position: 0,
        load: '90',
        reps: '1',
      );

      final priorSet = await repositories.sets.findLatestPriorForExercise(
        exerciseId: benchId,
        beforeWorkoutId: currentWorkoutId,
        dimensions: const <DimensionId>[DimensionId.load, DimensionId.reps],
      );
      final missingHistory = await repositories.sets.findLatestPriorForExercise(
        exerciseId: rowId,
        beforeWorkoutId: oldWorkoutId,
        dimensions: const <DimensionId>[DimensionId.load, DimensionId.reps],
      );

      expect(priorSet?.id, latestPriorId);
      expect(priorSet?.values.load?.entered, '85');
      expect(priorSet?.values.reps?.entered, '3');
      expect(missingHistory, isNull);
    });

    test('multi-row workout logging action shares one batch id', () async {
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Run',
          type: ExerciseType(<DimensionId>[
            DimensionId.duration,
            DimensionId.distance,
          ]),
        ),
      );

      final result = await repositories.logWorkoutWithSet(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 5),
          timezone: 'Australia/Brisbane',
        ),
        LoggedSetDraft(
          exerciseId: exerciseId,
          position: 0,
          values: LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.duration,
                entered: '1800',
                unit: TrainingUnit.second,
              ),
              SetDimensionValue(
                dimension: DimensionId.distance,
                entered: '5',
                unit: TrainingUnit.kilometer,
              ),
            ],
          ),
        ),
        actor: 'tester',
      );

      final logs = await repositories.activityLog.listEntries();
      final actionLogs = logs
          .where((entry) => entry.batchId == result.batchId)
          .toList(growable: false);

      expect(actionLogs, hasLength(2));
      expect(
        actionLogs.map((entry) => entry.entityTable),
        containsAll(<String>['workout_sessions', 'logged_sets']),
      );
      expect(actionLogs.map((entry) => entry.batchId).toSet(), hasLength(1));

      final set = await repositories.sets.getById(result.loggedSetId);
      expect(set?.workoutId, result.workoutSessionId);
      expect(set?.values.valueFor(DimensionId.distance)?.entered, '5');
      expect(set?.values.valueFor(DimensionId.distance)?.unit,
          TrainingUnit.kilometer);
      expect(set?.values.valueFor(DimensionId.duration)?.numericValue, 1800);
    });

    test('workout comments, copy, move, and share are activity logged',
        () async {
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Back Squat',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
          isUnilateral: true,
          usesRpe: true,
        ),
        actor: 'tester',
      );
      const sourceDay = TrainingDayDate(year: 2026, month: 6, day: 14);
      const copyDay = TrainingDayDate(year: 2026, month: 6, day: 16);
      const moveDay = TrainingDayDate(year: 2026, month: 6, day: 17);
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 7),
          timezone: 'Australia/Brisbane',
          localDate: sourceDay,
          endedAt: DateTime.utc(2026, 6, 14, 8, 30),
          comment: '  Early volume  ',
        ),
        actor: 'tester',
      );
      final workoutExerciseId = await repositories.workoutExercises.create(
        WorkoutExerciseDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
        ),
        actor: 'tester',
      );
      final sourcePerformedAt = DateTime.utc(2026, 6, 14, 7, 20);
      final setId = await repositories.sets.create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
          position: 0,
          performedAt: sourcePerformedAt,
          values: LoggedSet.fromValues(
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
            ],
          ),
          isCompleted: true,
          comment: 'Smooth',
          side: SetSide.left,
          rpe: 8.5,
        ),
        actor: 'tester',
      );

      await repositories.workoutSessions.updateComment(
        workoutId,
        comment: ' Felt great ',
        actor: 'tester',
      );
      final commentedWorkout =
          await repositories.workoutSessions.getById(workoutId);
      expect(commentedWorkout?.comment, 'Felt great');

      final copiedWorkoutId = await repositories.workoutSessions.copyWorkout(
        workoutId,
        localDate: copyDay,
        now: DateTime(2026, 6, 16, 9),
        timezone: 'Australia/Brisbane',
        actor: 'tester',
      );
      final copiedWorkout =
          await repositories.workoutSessions.getById(copiedWorkoutId);
      final copiedWorkoutExercises =
          await repositories.workoutExercises.listActiveForWorkout(
        copiedWorkoutId,
      );
      final copiedSets =
          await repositories.sets.listActiveForWorkout(copiedWorkoutId);
      final originalSets =
          await repositories.sets.listActiveForWorkout(workoutId);

      expect(copiedWorkoutId, isNot(workoutId));
      expect(copiedWorkout, isNotNull);
      expect(copiedWorkout!.localDate, copyDay);
      expect(copiedWorkout.comment, 'Felt great');
      expect(
        copiedWorkout.endedAt?.difference(copiedWorkout.startedAt),
        const Duration(minutes: 90),
      );
      expect(copiedWorkoutExercises.single.id, isNot(workoutExerciseId));
      expect(copiedWorkoutExercises.single.exerciseId, exerciseId);
      expect(copiedWorkoutExercises.single.position, 0);
      expect(copiedSets.single.id, isNot(setId));
      expect(copiedSets.single.exerciseId, exerciseId);
      expect(copiedSets.single.values.load?.entered, '100');
      expect(copiedSets.single.values.reps?.entered, '5');
      expect(copiedSets.single.performedAt, sourcePerformedAt);
      expect(copiedSets.single.isCompleted, isTrue);
      expect(copiedSets.single.comment, 'Smooth');
      expect(copiedSets.single.side, SetSide.left);
      expect(copiedSets.single.rpe, 8.5);
      expect(originalSets.single.id, setId);
      expect(originalSets.single.performedAt, sourcePerformedAt);
      expect(commentedWorkout?.localDate, sourceDay);

      await repositories.workoutSessions.moveToTrainingDay(
        workoutId,
        localDate: moveDay,
        actor: 'tester',
      );
      expect(
        await repositories.workoutSessions.listActiveForLocalDate(sourceDay),
        isEmpty,
      );
      expect(
        (await repositories.workoutSessions.listActiveForLocalDate(moveDay))
            .single
            .id,
        workoutId,
      );

      final summary =
          await repositories.workoutSessions.shareSummary(copiedWorkoutId);
      expect(summary, contains('Workout on 2026-06-16'));
      expect(summary, contains('Duration: 1h 30m'));
      expect(summary, contains('Comment: Felt great'));
      expect(summary, contains('Back Squat'));
      expect(summary, contains('100 kg x 5 reps'));
      expect(summary, contains('Smooth'));

      final logs = await repositories.activityLog.listEntries();
      final commentLog = logs.singleWhere(
        (entry) =>
            entry.entityTable == AppDatabase.workoutSessionsTable &&
            entry.entityId == workoutId &&
            entry.beforeImage?['comment'] == 'Early volume' &&
            entry.afterImage?['comment'] == 'Felt great',
      );
      expect(commentLog.actor, 'tester');
      final copyLogs = logs
          .where(
            (entry) =>
                entry.entityId == copiedWorkoutId ||
                entry.afterImage?['workout_id'] == copiedWorkoutId,
          )
          .toList(growable: false);
      expect(copyLogs, hasLength(3));
      expect(copyLogs.every((entry) => entry.beforeImage == null), isTrue);
      expect(copyLogs.map((entry) => entry.batchId).toSet(), hasLength(1));
      expect(
        copyLogs.map((entry) => entry.entityTable),
        containsAll(<String>[
          AppDatabase.workoutSessionsTable,
          AppDatabase.workoutExercisesTable,
          AppDatabase.loggedSetsTable,
        ]),
      );
      final moveLog = logs.singleWhere(
        (entry) =>
            entry.entityTable == AppDatabase.workoutSessionsTable &&
            entry.entityId == workoutId &&
            entry.beforeImage?['local_date'] == sourceDay.storageValue &&
            entry.afterImage?['local_date'] == moveDay.storageValue,
      );
      expect(moveLog.afterImage?['comment'], 'Felt great');
    });

    test('workout start and finish times can be edited', () async {
      const localDate = TrainingDayDate(year: 2026, month: 6, day: 14);
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 8),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
          endedAt: DateTime.utc(2026, 6, 14, 9),
        ),
        actor: 'tester',
      );

      await repositories.workoutSessions.updateStartedAt(
        workoutId,
        startedAt: DateTime.utc(2026, 6, 14, 7, 30),
        localDate: localDate,
        actor: 'tester',
      );
      await repositories.workoutSessions.updateEndedAt(
        workoutId,
        endedAt: DateTime.utc(2026, 6, 14, 9, 45),
        actor: 'tester',
      );

      final workout = await repositories.workoutSessions.getById(workoutId);
      expect(workout?.startedAt, DateTime.utc(2026, 6, 14, 7, 30));
      expect(workout?.endedAt, DateTime.utc(2026, 6, 14, 9, 45));
      expect(workout?.localDate, localDate);
      expect(
        (await repositories.workoutSessions.listActiveForLocalDate(localDate))
            .single
            .id,
        workoutId,
      );

      final logs = await repositories.activityLog.listEntries();
      expect(
        logs.where(
          (entry) =>
              entry.entityTable == AppDatabase.workoutSessionsTable &&
              entry.entityId == workoutId &&
              entry.beforeImage?['started_at'] ==
                  DateTime.utc(2026, 6, 14, 8).toIso8601String() &&
              entry.afterImage?['started_at'] ==
                  DateTime.utc(2026, 6, 14, 7, 30).toIso8601String(),
        ),
        hasLength(1),
      );
      expect(
        logs.where(
          (entry) =>
              entry.entityTable == AppDatabase.workoutSessionsTable &&
              entry.entityId == workoutId &&
              entry.beforeImage?['ended_at'] ==
                  DateTime.utc(2026, 6, 14, 9).toIso8601String() &&
              entry.afterImage?['ended_at'] ==
                  DateTime.utc(2026, 6, 14, 9, 45).toIso8601String(),
        ),
        hasLength(1),
      );
    });

    test('workout time edits reject an end before the start', () async {
      const localDate = TrainingDayDate(year: 2026, month: 6, day: 14);
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 8),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
          endedAt: DateTime.utc(2026, 6, 14, 9),
        ),
        actor: 'tester',
      );

      expect(
        () => repositories.workoutSessions.updateStartedAt(
          workoutId,
          startedAt: DateTime.utc(2026, 6, 14, 9, 1),
          localDate: localDate,
          actor: 'tester',
        ),
        throwsArgumentError,
      );
      expect(
        () => repositories.workoutSessions.updateEndedAt(
          workoutId,
          endedAt: DateTime.utc(2026, 6, 14, 7, 59),
          actor: 'tester',
        ),
        throwsArgumentError,
      );

      final workout = await repositories.workoutSessions.getById(workoutId);
      expect(workout?.startedAt, DateTime.utc(2026, 6, 14, 8));
      expect(workout?.endedAt, DateTime.utc(2026, 6, 14, 9));
    });

    test('auto-finishes stale open workouts from last app interaction',
        () async {
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt:
              DateTime.now().toUtc().subtract(const Duration(minutes: 30)),
          timezone: 'Australia/Brisbane',
        ),
        actor: 'tester',
      );
      final workout = await repositories.workoutSessions.getById(workoutId);
      final lastInteractionAt =
          workout!.updatedAt.add(const Duration(minutes: 12));
      final expectedEndedAt = lastInteractionAt.add(const Duration(hours: 1));

      final finished =
          await repositories.workoutSessions.autoFinishStaleOpenWorkouts(
        idleThreshold: const Duration(hours: 1),
        now: expectedEndedAt.add(const Duration(minutes: 1)),
        lastInteractionAt: lastInteractionAt,
        actor: 'tester',
      );

      final after = await repositories.workoutSessions.getById(workoutId);
      expect(finished.map((entry) => entry.workoutId), <String>[workoutId]);
      expect(finished.single.lastInteractionAt, lastInteractionAt);
      expect(finished.single.endedAt, expectedEndedAt);
      expect(after?.endedAt, expectedEndedAt);

      final logs = await repositories.activityLog.listEntries();
      expect(
        logs.where(
          (entry) =>
              entry.entityTable == AppDatabase.workoutSessionsTable &&
              entry.entityId == workoutId &&
              entry.beforeImage?['ended_at'] == null &&
              entry.afterImage?['ended_at'] ==
                  expectedEndedAt.toIso8601String(),
        ),
        hasLength(1),
      );
    });

    test('auto-finish uses the latest workout activity when it is newer',
        () async {
      await repositories.ensureStarterExercises(actor: 'tester');
      final exercise = (await repositories.exercises.listActive()).first;
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt:
              DateTime.now().toUtc().subtract(const Duration(minutes: 30)),
          timezone: 'Australia/Brisbane',
        ),
        actor: 'tester',
      );
      final createdWorkout =
          await repositories.workoutSessions.getById(workoutId);
      final setId = await repositories.sets.create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exercise.id,
          position: 0,
          values: LoggedSet.fromValues(
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
            ],
          ),
        ),
        actor: 'tester',
      );
      final loggedSet = await repositories.sets.getById(setId);
      final expectedEndedAt =
          loggedSet!.updatedAt.add(const Duration(hours: 1));

      final finished =
          await repositories.workoutSessions.autoFinishStaleOpenWorkouts(
        idleThreshold: const Duration(hours: 1),
        now: expectedEndedAt.add(const Duration(minutes: 1)),
        lastInteractionAt: createdWorkout!.updatedAt,
        actor: 'tester',
      );

      final after = await repositories.workoutSessions.getById(workoutId);
      expect(finished.single.lastInteractionAt, loggedSet.updatedAt);
      expect(after?.endedAt, expectedEndedAt);
    });

    test('auto-finish leaves fresh and already finished workouts unchanged',
        () async {
      final freshWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt:
              DateTime.now().toUtc().subtract(const Duration(minutes: 15)),
          timezone: 'Australia/Brisbane',
        ),
        actor: 'tester',
      );
      final finishedWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
          timezone: 'Australia/Brisbane',
          endedAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
        ),
        actor: 'tester',
      );
      final fresh = await repositories.workoutSessions.getById(freshWorkoutId);

      final finished =
          await repositories.workoutSessions.autoFinishStaleOpenWorkouts(
        idleThreshold: const Duration(hours: 1),
        now: fresh!.updatedAt.add(const Duration(minutes: 30)),
        lastInteractionAt: fresh.updatedAt,
        actor: 'tester',
      );

      expect(finished, isEmpty);
      expect(
        (await repositories.workoutSessions.getById(freshWorkoutId))?.endedAt,
        isNull,
      );
      expect(
        (await repositories.workoutSessions.getById(finishedWorkoutId))
            ?.endedAt,
        isNotNull,
      );
    });

    test('starter exercises are seeded exactly once', () async {
      await repositories.ensureStarterExercises(actor: 'tester');
      await repositories.ensureStarterExercises(actor: 'tester');

      final exercises = await repositories.exercises.listActive();

      expect(exercises.map((exercise) => exercise.name), <String>[
        'Barbell Squat',
        'Plank',
      ]);
      expect(
        exercises
            .singleWhere((exercise) => exercise.name == 'Barbell Squat')
            .type
            .dimensions,
        <DimensionId>[DimensionId.load, DimensionId.reps],
      );
      expect(
        exercises
            .singleWhere((exercise) => exercise.name == 'Plank')
            .type
            .dimensions,
        <DimensionId>[DimensionId.duration],
      );
    });

    test('logs a starter weight and reps set through the activity log',
        () async {
      await repositories.ensureStarterExercises(actor: 'tester');

      final emissions = <List<LoggedSetRecord>>[];
      final subscription =
          repositories.sets.watchAllActive().listen(emissions.add);
      addTearDown(subscription.cancel);

      await _waitFor(() => emissions.isNotEmpty);
      expect(emissions.single, isEmpty);

      final result = await repositories.logDefaultWeightRepsSet(
        now: DateTime(2026, 6, 14, 16, 30),
        timezone: 'Australia/Brisbane',
        actor: 'tester',
      );

      await _waitFor(() => emissions.any((sets) => sets.length == 1));

      final workouts = await repositories.workoutSessions.listActive();
      final sets =
          await repositories.sets.listActiveForWorkout(result.workoutSessionId);
      final set = sets.single;

      expect(workouts, hasLength(1));
      expect(workouts.single.id, result.workoutSessionId);
      expect(workouts.single.timezone, 'Australia/Brisbane');
      expect(set.id, result.loggedSetId);
      expect(set.position, 0);
      expect(set.values.load?.entered, '100');
      expect(set.values.load?.unit, TrainingUnit.kilogram);
      expect(set.values.reps?.entered, '5');
      expect(set.values.reps?.unit, TrainingUnit.repetition);

      final logs = await repositories.activityLog.listEntries();
      final setLog = logs.singleWhere(
        (entry) =>
            entry.batchId == result.batchId &&
            entry.entityTable == AppDatabase.loggedSetsTable,
      );

      expect(setLog.beforeImage, isNull);
      expect(setLog.afterImage?['load_entered'], '100');
      expect(setLog.afterImage?['reps_entered'], '5');
    });

    test('seeded exercise and logged set survive reopening the database',
        () async {
      final directory = await Directory.systemTemp.createTemp('perennia_test_');
      addTearDown(() => directory.delete(recursive: true));

      final databaseFile = File('${directory.path}/walking_skeleton.sqlite');
      final firstDatabase = AppDatabase.openFile(databaseFile);
      final firstRepositories = TrainingRepositories(
        firstDatabase,
        platformSeedSource: const _StarterSeedSource(),
      );

      await firstRepositories.ensureStarterExercises(actor: 'tester');
      final result = await firstRepositories.logDefaultWeightRepsSet(
        now: DateTime(2026, 6, 14, 16, 30),
        timezone: 'Australia/Brisbane',
        actor: 'tester',
      );
      await firstDatabase.close();

      final reopenedDatabase = AppDatabase.openFile(databaseFile);
      addTearDown(reopenedDatabase.close);
      final reopenedRepositories = TrainingRepositories(
        reopenedDatabase,
        platformSeedSource: const _StarterSeedSource(),
      );

      await reopenedRepositories.ensureStarterExercises(actor: 'tester');

      final exercises = await reopenedRepositories.exercises.listActive();
      final workouts = await reopenedRepositories.workoutSessions.listActive();
      final sets = await reopenedRepositories.sets
          .listActiveForWorkout(workouts.single.id);

      expect(exercises, hasLength(2));
      expect(workouts, hasLength(1));
      expect(sets.single.id, result.loggedSetId);
      expect(sets.single.values.load?.entered, '100');
      expect(sets.single.values.reps?.entered, '5');
    });

    test('started session survives reopening on its original training day',
        () async {
      final directory = await Directory.systemTemp.createTemp('perennia_test_');
      addTearDown(() => directory.delete(recursive: true));

      final databaseFile = File('${directory.path}/training_day.sqlite');
      final firstDatabase = AppDatabase.openFile(databaseFile);
      final firstRepositories = TrainingRepositories(
        firstDatabase,
        platformSeedSource: const _StarterSeedSource(),
      );
      const trainingDay = TrainingDayDate(year: 2026, month: 6, day: 14);

      final workoutId = await firstRepositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 15, 4),
          timezone: 'Pacific/Auckland',
          localDate: trainingDay,
        ),
        actor: 'tester',
      );
      await firstDatabase.close();

      final reopenedDatabase = AppDatabase.openFile(databaseFile);
      addTearDown(reopenedDatabase.close);
      final reopenedRepositories = TrainingRepositories(
        reopenedDatabase,
        platformSeedSource: const _StarterSeedSource(),
      );

      final sameDay =
          await reopenedRepositories.workoutSessions.listActiveForLocalDate(
        trainingDay,
      );
      final nextDay =
          await reopenedRepositories.workoutSessions.listActiveForLocalDate(
        trainingDay.addDays(1),
      );

      expect(sameDay.single.id, workoutId);
      expect(nextDay, isEmpty);
    });

    test('repository stream re-emits on insert, update, and soft-delete',
        () async {
      final emissions = <List<ExerciseRecord>>[];
      final subscription =
          repositories.exercises.watchActive().listen(emissions.add);
      addTearDown(subscription.cancel);

      await _waitFor(() => emissions.isNotEmpty);
      expect(emissions.single, isEmpty);

      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Deadlift',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
      );
      await _waitFor(() => emissions.length >= 2);
      expect(emissions[1].single.name, 'Deadlift');

      await repositories.exercises.rename(exerciseId, name: 'Paused Deadlift');
      await _waitFor(() => emissions.length >= 3);
      expect(emissions[2].single.name, 'Paused Deadlift');

      await repositories.exercises.softDelete(exerciseId);
      await _waitFor(() => emissions.length >= 4);
      expect(emissions[3], isEmpty);
    });

    test('home summary groups exercise logs by workout session', () async {
      const trainingDay = TrainingDayDate(year: 2026, month: 6, day: 14);
      final runId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Morning Run',
          type: ExerciseType(<DimensionId>[
            DimensionId.distance,
            DimensionId.duration,
          ]),
        ),
        actor: 'tester',
      );
      final squatId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Evening Squat',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
        actor: 'tester',
      );
      final morningWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime(2026, 6, 14, 7),
          timezone: 'Australia/Brisbane',
          localDate: trainingDay,
        ),
        actor: 'tester',
      );
      final eveningWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime(2026, 6, 14, 18),
          timezone: 'Australia/Brisbane',
          localDate: trainingDay,
        ),
        actor: 'tester',
      );
      await repositories.workoutExercises.create(
        WorkoutExerciseDraft(
          workoutId: morningWorkoutId,
          exerciseId: runId,
        ),
        actor: 'tester',
      );
      await repositories.workoutExercises.create(
        WorkoutExerciseDraft(
          workoutId: eveningWorkoutId,
          exerciseId: squatId,
        ),
        actor: 'tester',
      );

      final emissions = <HomeSummary>[];
      final subscription = RepositoryHomeRepository(repositories)
          .watchTrainingDay(trainingDay)
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      await _waitFor(
        () => emissions.any(
          (summary) =>
              summary.workouts.length == 2 &&
              summary.workouts.every(
                (workout) => workout.workoutExercises.length == 1,
              ),
        ),
      );
      final summary = emissions.lastWhere(
        (summary) =>
            summary.workouts.length == 2 &&
            summary.workouts.every(
              (workout) => workout.workoutExercises.length == 1,
            ),
      );

      expect(
        summary.workouts.map((workout) => workout.id),
        <String>[morningWorkoutId, eveningWorkoutId],
      );
      expect(
          summary.workouts.first.workoutExercises.single.name, 'Morning Run');
      expect(
        summary.workouts.last.workoutExercises.single.name,
        'Evening Squat',
      );
      expect(summary.workoutExercises, hasLength(2));
    });

    test('home summary re-scopes children when same-day workouts change',
        () async {
      const trainingDay = TrainingDayDate(year: 2026, month: 6, day: 14);
      final benchId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Bench Press',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
        actor: 'tester',
      );
      final rowId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Barbell Row',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
        actor: 'tester',
      );
      final firstWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime(2026, 6, 14, 7),
          timezone: 'Australia/Brisbane',
          localDate: trainingDay,
        ),
        actor: 'tester',
      );
      final firstWorkoutExerciseId = await repositories.workoutExercises.create(
        WorkoutExerciseDraft(
          workoutId: firstWorkoutId,
          exerciseId: benchId,
        ),
        actor: 'tester',
      );
      final firstSetId = await _createLoadRepsSet(
        repositories,
        workoutId: firstWorkoutId,
        exerciseId: benchId,
        position: 0,
        load: '100',
        reps: '5',
        // Performed, so the day status line counts it.
        isCompleted: true,
      );

      bool hasWorkoutExerciseAndSet(
        HomeSummary summary, {
        required String workoutId,
        required String workoutExerciseId,
        required String setId,
      }) {
        final matches = summary.workouts.where(
          (workout) => workout.id == workoutId,
        );
        if (matches.isEmpty) {
          return false;
        }

        final workout = matches.single;
        if (workout.workoutExercises.length != 1) {
          return false;
        }

        final workoutExercise = workout.workoutExercises.single;
        return workoutExercise.id == workoutExerciseId &&
            workoutExercise.sets.length == 1 &&
            workoutExercise.sets.single.id == setId;
      }

      final emissions = <HomeSummary>[];
      final subscription = RepositoryHomeRepository(repositories)
          .watchTrainingDay(trainingDay)
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      await _waitFor(
        () => emissions.any(
          (summary) => hasWorkoutExerciseAndSet(
            summary,
            workoutId: firstWorkoutId,
            workoutExerciseId: firstWorkoutExerciseId,
            setId: firstSetId,
          ),
        ),
      );
      final firstEmissionCount = emissions.length;
      final firstSummary = emissions.lastWhere(
        (summary) => hasWorkoutExerciseAndSet(
          summary,
          workoutId: firstWorkoutId,
          workoutExerciseId: firstWorkoutExerciseId,
          setId: firstSetId,
        ),
      );

      expect(firstSummary.workouts.map((workout) => workout.id), <String>[
        firstWorkoutId,
      ]);
      expect(firstSummary.workoutExercises.map((row) => row.id), <String>[
        firstWorkoutExerciseId,
      ]);
      expect(firstSummary.sets.map((set) => set.id), <String>[firstSetId]);

      final secondWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime(2026, 6, 14, 18),
          timezone: 'Australia/Brisbane',
          localDate: trainingDay,
        ),
        actor: 'tester',
      );
      final secondWorkoutExerciseId =
          await repositories.workoutExercises.create(
        WorkoutExerciseDraft(
          workoutId: secondWorkoutId,
          exerciseId: rowId,
        ),
        actor: 'tester',
      );
      final secondSetId = await _createLoadRepsSet(
        repositories,
        workoutId: secondWorkoutId,
        exerciseId: rowId,
        position: 0,
        load: '80',
        reps: '8',
        isCompleted: true,
      );

      await _waitFor(
        () =>
            emissions.length > firstEmissionCount &&
            emissions.any(
              (summary) =>
                  hasWorkoutExerciseAndSet(
                    summary,
                    workoutId: firstWorkoutId,
                    workoutExerciseId: firstWorkoutExerciseId,
                    setId: firstSetId,
                  ) &&
                  hasWorkoutExerciseAndSet(
                    summary,
                    workoutId: secondWorkoutId,
                    workoutExerciseId: secondWorkoutExerciseId,
                    setId: secondSetId,
                  ),
            ),
      );
      final secondEmissionCount = emissions.length;
      final expandedSummary = emissions.lastWhere(
        (summary) =>
            hasWorkoutExerciseAndSet(
              summary,
              workoutId: firstWorkoutId,
              workoutExerciseId: firstWorkoutExerciseId,
              setId: firstSetId,
            ) &&
            hasWorkoutExerciseAndSet(
              summary,
              workoutId: secondWorkoutId,
              workoutExerciseId: secondWorkoutExerciseId,
              setId: secondSetId,
            ),
      );

      expect(expandedSummary.workouts.map((workout) => workout.id), <String>[
        firstWorkoutId,
        secondWorkoutId,
      ]);
      expect(expandedSummary.workoutExercises.map((row) => row.id), <String>[
        firstWorkoutExerciseId,
        secondWorkoutExerciseId,
      ]);
      expect(expandedSummary.sets.map((set) => set.id), <String>[
        firstSetId,
        secondSetId,
      ]);
      expect(expandedSummary.status, '2 workouts - 2 sets');

      await repositories.workoutSessions.softDelete(firstWorkoutId);

      await _waitFor(
        () =>
            emissions.length > secondEmissionCount &&
            emissions.any(
              (summary) =>
                  summary.workouts.length == 1 &&
                  summary.workouts.single.id == secondWorkoutId &&
                  hasWorkoutExerciseAndSet(
                    summary,
                    workoutId: secondWorkoutId,
                    workoutExerciseId: secondWorkoutExerciseId,
                    setId: secondSetId,
                  ),
            ),
      );
      final archivedSummary = emissions.lastWhere(
        (summary) =>
            summary.workouts.length == 1 &&
            summary.workouts.single.id == secondWorkoutId &&
            hasWorkoutExerciseAndSet(
              summary,
              workoutId: secondWorkoutId,
              workoutExerciseId: secondWorkoutExerciseId,
              setId: secondSetId,
            ),
      );

      expect(archivedSummary.status, '1 workout - 1 set');
      expect(
        archivedSummary.workoutExercises.map((row) => row.id),
        isNot(contains(firstWorkoutExerciseId)),
      );
      expect(
        archivedSummary.sets.map((set) => set.id),
        isNot(contains(firstSetId)),
      );
    });

    test('home summary ignores unrelated exercise changes', () async {
      const trainingDay = TrainingDayDate(year: 2026, month: 6, day: 14);
      final benchId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Bench Press',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
        actor: 'tester',
      );
      final unrelatedExerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Unrelated Curl',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
        actor: 'tester',
      );
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime(2026, 6, 14, 7),
          timezone: 'Australia/Brisbane',
          localDate: trainingDay,
        ),
        actor: 'tester',
      );
      await repositories.workoutExercises.create(
        WorkoutExerciseDraft(
          workoutId: workoutId,
          exerciseId: benchId,
        ),
        actor: 'tester',
      );

      final emissions = <HomeSummary>[];
      final subscription = RepositoryHomeRepository(repositories)
          .watchTrainingDay(trainingDay)
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      await _waitFor(
        () => emissions.any(
          (summary) =>
              summary.workouts.length == 1 &&
              summary.workouts.single.workoutExercises.single.name ==
                  'Bench Press',
        ),
      );
      for (var index = 0; index < 5; index += 1) {
        await pumpEventQueue();
      }
      final initialEmissionCount = emissions.length;

      await repositories.exercises.rename(
        unrelatedExerciseId,
        name: 'Renamed Unrelated Curl',
        actor: 'tester',
      );
      for (var index = 0; index < 5; index += 1) {
        await pumpEventQueue();
      }

      expect(emissions, hasLength(initialEmissionCount));
      expect(
        emissions.last.workouts.single.workoutExercises.single.name,
        'Bench Press',
      );

      await repositories.exercises.rename(
        benchId,
        name: 'Competition Bench Press',
        actor: 'tester',
      );
      await _waitFor(() => emissions.length > initialEmissionCount);

      expect(
        emissions.last.workouts.single.workoutExercises.single.name,
        'Competition Bench Press',
      );
    });

    test('home summary ignores exercise changes on empty days', () async {
      const trainingDay = TrainingDayDate(year: 2026, month: 6, day: 14);
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Bench Press',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
        actor: 'tester',
      );

      final emissions = <HomeSummary>[];
      final subscription = RepositoryHomeRepository(repositories)
          .watchTrainingDay(trainingDay)
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      await _waitFor(() => emissions.isNotEmpty);
      for (var index = 0; index < 5; index += 1) {
        await pumpEventQueue();
      }
      final initialEmissionCount = emissions.length;

      expect(emissions.last.workouts, isEmpty);
      expect(emissions.last.workoutExercises, isEmpty);
      expect(emissions.last.exercises, isEmpty);

      await repositories.exercises.rename(
        exerciseId,
        name: 'Competition Bench Press',
        actor: 'tester',
      );
      for (var index = 0; index < 5; index += 1) {
        await pumpEventQueue();
      }

      expect(emissions, hasLength(initialEmissionCount));
      expect(emissions.last.exercises, isEmpty);
    });

    test('home workout summary ignores unrelated workout session changes',
        () async {
      const trainingDay = TrainingDayDate(year: 2026, month: 6, day: 14);
      final benchId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Bench Press',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
        actor: 'tester',
      );
      final targetWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime(2026, 6, 14, 7),
          timezone: 'Australia/Brisbane',
          localDate: trainingDay,
        ),
        actor: 'tester',
      );
      final unrelatedWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime(2026, 6, 15, 7),
          timezone: 'Australia/Brisbane',
          localDate: trainingDay.addDays(1),
        ),
        actor: 'tester',
      );
      await repositories.workoutExercises.create(
        WorkoutExerciseDraft(
          workoutId: targetWorkoutId,
          exerciseId: benchId,
        ),
        actor: 'tester',
      );

      final emissions = <HomeWorkoutSummary?>[];
      final subscription = RepositoryHomeRepository(repositories)
          .watchWorkout(targetWorkoutId)
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      await _waitFor(() => emissions.any(
            (workout) => workout?.id == targetWorkoutId,
          ));
      for (var index = 0; index < 5; index += 1) {
        await pumpEventQueue();
      }
      final initialEmissionCount = emissions.length;

      await repositories.workoutSessions.updateComment(
        unrelatedWorkoutId,
        comment: 'Unrelated session note',
        actor: 'tester',
      );
      for (var index = 0; index < 5; index += 1) {
        await pumpEventQueue();
      }

      expect(emissions, hasLength(initialEmissionCount));
      expect(emissions.last?.id, targetWorkoutId);
      expect(emissions.last?.workoutExercises.single.name, 'Bench Press');

      await repositories.workoutSessions.updateComment(
        targetWorkoutId,
        comment: 'Target session note',
        actor: 'tester',
      );
      await _waitFor(() => emissions.length > initialEmissionCount);

      expect(emissions.last?.id, targetWorkoutId);
      expect(emissions.last?.comment, 'Target session note');
    });

    test('home controller is driven by the repository stream', () async {
      final container = ProviderContainer(
        overrides: [
          trainingRepositoriesProvider.overrideWith((ref) => repositories),
          homeRepositoryProvider.overrideWith(
            (ref) => RepositoryHomeRepository(
                ref.watch(trainingRepositoriesProvider)),
          ),
        ],
      );
      addTearDown(container.dispose);

      final states = <HomeState>[];
      final subscription = container.listen(
        homeControllerProvider,
        (_, next) {
          if (next case AsyncData(:final value)) {
            states.add(value);
          }
        },
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      await _waitFor(() => states.isNotEmpty);
      const trainingDay = TrainingDayDate(year: 2026, month: 6, day: 14);
      container
          .read(homeControllerProvider.notifier)
          .selectTrainingDay(trainingDay);

      await container.read(homeControllerProvider.notifier).startNewWorkout();

      await _waitFor(
        () => states.any(
          (state) =>
              state.summary.selectedDate == trainingDay &&
              state.summary.workouts.length == 1,
        ),
      );
      // A Workout with no Performed Set is not counted as started.
      expect(states.last.summary.status, 'No workout started');
      expect(states.last.summary.sets, isEmpty);
      expect(
        await repositories.workoutSessions.listActiveForLocalDate(trainingDay),
        hasLength(1),
      );

      final firstWorkoutId = states.last.summary.workouts.single.id;
      await container.read(homeControllerProvider.notifier).startNewWorkout();
      await _waitFor(
        () => states.any(
          (state) =>
              state.summary.selectedDate == trainingDay &&
              state.summary.workouts.length == 2,
        ),
      );
      final sameDayWorkouts =
          await repositories.workoutSessions.listActiveForLocalDate(
        trainingDay,
      );
      expect(sameDayWorkouts, hasLength(2));
      expect(
        sameDayWorkouts.map((workout) => workout.id).toSet(),
        hasLength(2),
      );
      expect(
        states.last.summary.workouts.map((workout) => workout.id),
        contains(firstWorkoutId),
      );
      expect(states.last.summary.workouts, hasLength(2));

      final nextTrainingDay = trainingDay.addDays(1);
      final nextWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime(2026, 6, 15, 9),
          timezone: 'Australia/Brisbane',
          localDate: nextTrainingDay,
        ),
        actor: 'tester',
      );

      container.read(homeControllerProvider.notifier).showNextDay();

      await _waitFor(
        () => states.any(
          (state) =>
              state.summary.selectedDate == nextTrainingDay &&
              state.summary.workouts.length == 1 &&
              state.summary.workouts.single.id == nextWorkoutId,
        ),
      );
      expect(states.last.summary.selectedDate, nextTrainingDay);
      expect(states.last.summary.workouts.single.id, nextWorkoutId);
    });
  });

  test('rest timer deadline persists and resumes after reopening the database',
      () async {
    final directory = await Directory.systemTemp.createTemp('perennia_timer_');
    addTearDown(() => directory.delete(recursive: true));
    final databaseFile = File('${directory.path}/timer.sqlite');
    final startedAt = DateTime.utc(2026, 6, 16, 1);
    const rest = Duration(seconds: 90);
    const trainingDay = TrainingDayDate(year: 2026, month: 6, day: 16);
    late String workoutId;

    var database = AppDatabase.openFile(databaseFile);
    var repositories = TrainingRepositories(
      database,
      platformSeedSource: const _StarterSeedSource(),
    );
    final exerciseId = await repositories.exercises.create(
      ExerciseDraft(
        name: 'Back Squat',
        type: ExerciseType(
          const <DimensionId>[DimensionId.load, DimensionId.reps],
        ),
      ),
    );
    workoutId = await repositories.workoutSessions.create(
      WorkoutSessionDraft(
        startedAt: startedAt,
        timezone: 'UTC',
        localDate: trainingDay,
      ),
    );
    final setId = await repositories.sets.create(
      LoggedSetDraft(
        workoutId: workoutId,
        exerciseId: exerciseId,
        position: 0,
        values: _loadRepsValues(load: '100', reps: '5'),
        plannedRestAfter: rest,
      ),
    );
    final plannedSet = await repositories.sets.getById(setId);

    final timerId = await repositories.restTimers.startForSet(
      plannedSet!,
      defaultDuration: const Duration(seconds: 120),
      alertVolume: 0.4,
      now: startedAt,
    );
    final timer = await repositories.restTimers.getById(timerId!);

    expect(timer?.duration, rest);
    expect(timer?.deadlineAt, startedAt.add(rest));
    expect(
      timer?.remainingAt(startedAt.add(const Duration(seconds: 25))),
      const Duration(seconds: 65),
    );
    await database.close();

    database = AppDatabase.openFile(databaseFile);
    addTearDown(database.close);
    repositories = TrainingRepositories(
      database,
      platformSeedSource: const _StarterSeedSource(),
    );

    final resumed = await repositories.restTimers.getCurrentForWorkout(
      workoutId,
    );

    expect(resumed?.id, timerId);
    expect(resumed?.sourceSetId, setId);
    expect(resumed?.deadlineAt, startedAt.add(rest));
    expect(
      resumed?.remainingAt(startedAt.add(const Duration(seconds: 45))),
      const Duration(seconds: 45),
    );
    expect(resumed?.alertVolume, 0.4);
    expect(resumed?.status, RestTimerStatus.running);
  });

  test('a planned rest of zero starts no timer and keeps the running one',
      () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repositories = TrainingRepositories(
      database,
      platformSeedSource: const _StarterSeedSource(),
    );
    final startedAt = DateTime.utc(2026, 6, 16, 1);
    final exerciseId = await repositories.exercises.create(
      ExerciseDraft(
        name: 'Back Squat',
        type: ExerciseType(
          const <DimensionId>[DimensionId.load, DimensionId.reps],
        ),
      ),
    );
    final workoutId = await repositories.workoutSessions.create(
      WorkoutSessionDraft(startedAt: startedAt, timezone: 'UTC'),
    );
    Future<LoggedSetRecord> plannedSet(int position, Duration rest) async {
      final setId = await repositories.sets.create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exerciseId,
          position: position,
          values: _loadRepsValues(load: '100', reps: '5'),
          plannedRestAfter: rest,
        ),
      );
      return (await repositories.sets.getById(setId))!;
    }

    final runningId = await repositories.restTimers.startForSet(
      await plannedSet(0, const Duration(seconds: 90)),
      now: startedAt,
    );
    final skippedId = await repositories.restTimers.startForSet(
      await plannedSet(1, Duration.zero),
      now: startedAt.add(const Duration(seconds: 10)),
    );

    expect(skippedId, isNull);
    final current = await repositories.restTimers.getCurrentForWorkout(
      workoutId,
    );
    expect(current?.id, runningId);
    expect(current?.status, RestTimerStatus.running);
  });

  group('WorkoutSessionRepository.watchProgressWorkoutsBetween', () {
    const monday = TrainingDayDate(year: 2026, month: 10, day: 26);
    const sunday = TrainingDayDate(year: 2026, month: 11, day: 1);

    late AppDatabase database;
    late TrainingRepositories repositories;
    late String exerciseId;

    setUp(() async {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(
        database,
        platformSeedSource: const _StarterSeedSource(),
      );
      exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Back Squat',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );
    });

    tearDown(() async {
      await database.close();
    });

    Future<List<ProgressWorkout>> read() => repositories.workoutSessions
        .watchProgressWorkoutsBetween(monday, sunday)
        .first;

    /// A template "Lower" prescribing three Back Squat Sets.
    Future<String> lowerTemplate() async {
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Lower'),
      );
      final templateExerciseId = await repositories.workoutTemplates
          .addExercise(templateId, exerciseId);
      await repositories.workoutTemplates.addPrescription(
        templateExerciseId,
        PrescriptionDraft(
          mode: PrescriptionMode.fixed,
          values: _loadRepsValues(load: '100', reps: '5'),
          repeat: 3,
        ),
      );
      return templateId;
    }

    Future<String> workoutOn(
      TrainingDayDate day, {
      int hour = 7,
      bool ended = true,
      String? focusId,
    }) {
      final startedAt = DateTime.utc(day.year, day.month, day.day, hour);
      return repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: startedAt,
          timezone: 'UTC',
          localDate: day,
          endedAt: ended ? startedAt.add(const Duration(hours: 1)) : null,
          focusId: focusId,
        ),
      );
    }

    test(
        'a synced Workout whose local date cannot be read is left out, not '
        'an error', () async {
      final good = await workoutOn(monday);
      final broken = await workoutOn(monday, hour: 9);
      await repositories.sets.create(
        LoggedSetDraft(
          workoutId: good,
          exerciseId: exerciseId,
          position: 0,
          values: _loadRepsValues(load: '100', reps: '5'),
          isCompleted: true,
        ),
      );
      // Sorts inside the range as text, but is not a YYYY-MM-DD date.
      await (database.update(database.workoutSessions)
            ..where((row) => row.id.equals(broken)))
          .write(const WorkoutSessionsCompanion(localDate: Value('2026-10-3')));

      final workouts = await read();

      expect(workouts.map((workout) => workout.workoutId), <String>[good]);
    });

    test(
        'a materialized Workout with only incomplete Sets has no Performed '
        'Set until one is completed', () async {
      final templateId = await lowerTemplate();
      final result = await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(workoutTemplateId: templateId),
        now: DateTime(2026, 10, 27, 7),
      );
      final sets =
          await repositories.sets.listActiveForWorkout(result.workoutId);
      expect(sets, hasLength(3));
      expect(sets.every((set) => !set.isCompleted), isTrue);

      final emissions = <List<ProgressWorkout>>[];
      final subscription = repositories.workoutSessions
          .watchProgressWorkoutsBetween(monday, sunday)
          .listen(emissions.add);
      addTearDown(subscription.cancel);
      await _waitFor(() => emissions.isNotEmpty);

      final abandoned = emissions.last.single;
      expect(abandoned.workoutId, result.workoutId);
      expect(abandoned.localDate,
          const TrainingDayDate(year: 2026, month: 10, day: 27));
      expect(abandoned.linkedTemplateId, templateId);
      expect(abandoned.performedSetCount, 0);
      expect(abandoned.isLogged, isFalse);

      await repositories.sets.setCompleted(sets.first.id, isCompleted: true);
      await _waitFor(
        () => emissions.last.single.performedSetCount == 1,
      );
      // A completed Set that is later deleted is no longer performed.
      await repositories.sets.softDelete(sets.first.id);
      await _waitFor(
        () => emissions.last.single.performedSetCount == 0,
      );
    });

    test(
        'a deleted Workout and Workouts outside the range are absent; an '
        'Open Workout is listed', () async {
      final kept = await workoutOn(monday, focusId: 'focus-weights');
      final open = await workoutOn(sunday, hour: 18, ended: false);
      final deleted = await workoutOn(
        const TrainingDayDate(year: 2026, month: 10, day: 28),
      );
      await _createLoadRepsSet(
        repositories,
        workoutId: deleted,
        exerciseId: exerciseId,
        position: 0,
        load: '100',
        reps: '5',
      );
      await repositories.workoutSessions.softDelete(deleted);
      await workoutOn(const TrainingDayDate(year: 2026, month: 10, day: 25));
      await workoutOn(const TrainingDayDate(year: 2026, month: 11, day: 2));
      await _createLoadRepsSet(
        repositories,
        workoutId: kept,
        exerciseId: exerciseId,
        position: 0,
        load: '100',
        reps: '5',
      );
      final keptSetId = await _createLoadRepsSet(
        repositories,
        workoutId: kept,
        exerciseId: exerciseId,
        position: 1,
        load: '100',
        reps: '5',
      );
      await repositories.sets.setCompleted(keptSetId, isCompleted: true);

      final workouts = await read();

      expect(
        workouts.map((workout) => workout.workoutId),
        <String>[kept, open],
      );
      final first = workouts.first;
      expect(first.localDate, monday);
      expect(first.startedAt, DateTime.utc(2026, 10, 26, 7));
      expect(first.endedAt, DateTime.utc(2026, 10, 26, 8));
      expect(first.focusId, 'focus-weights');
      expect(first.linkedTemplateId, isNull);
      expect(first.performedSetCount, 1);
      expect(workouts.last.endedAt, isNull);
      expect(workouts.last.performedSetCount, 0);
    });

    test(
        'of two live Template Links, the latest updated wins, then the '
        'highest id; a deleted link is ignored', () async {
      final firstTemplate = await lowerTemplate();
      final secondTemplate = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Upper'),
      );
      final thirdTemplate = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Run'),
      );
      final result = await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(workoutTemplateId: firstTemplate),
        now: DateTime(2026, 10, 27, 7),
      );
      // This device keeps one link per Workout; a second one can only come
      // from elsewhere, so the test lifts the device's own constraint.
      await database.customStatement(
        'DROP INDEX template_links_workout_id_unique',
      );
      Future<void> link(
        String id,
        String templateId,
        DateTime updatedAt, {
        DateTime? deletedAt,
      }) {
        return database.into(database.templateLinks).insert(
              TemplateLinksCompanion.insert(
                id: id,
                workoutId: result.workoutId,
                workoutTemplateId: templateId,
                updatedAt: updatedAt,
                deletedAt: Value<DateTime?>(deletedAt),
              ),
            );
      }

      final later = DateTime.utc(2030);
      await link('link-b', secondTemplate, later);
      await link(
        'link-z',
        thirdTemplate,
        DateTime.utc(2031),
        deletedAt: DateTime.utc(2031),
      );
      expect((await read()).single.linkedTemplateId, secondTemplate);

      await link('link-c', thirdTemplate, later);
      expect((await read()).single.linkedTemplateId, thirdTemplate);
    });
  });
  group('plan-guided logging writes', () {
    late AppDatabase database;
    late TrainingRepositories repositories;
    late String exerciseId;
    late String workoutId;
    final idGenerator = UuidV7Generator();
    final startedAt = DateTime.utc(2026, 11, 2, 6);
    const ninety = Duration(seconds: 90);

    setUp(() async {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(
        database,
        platformSeedSource: const _StarterSeedSource(),
      );
      exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Incline Press',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );
      workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(startedAt: startedAt, timezone: 'UTC'),
      );
    });

    tearDown(() async {
      await database.close();
    });

    String newBatchId() => idGenerator.generate(timestamp: DateTime.now());

    /// Now, to the second: the database stores times at second precision.
    DateTime nowInSeconds() {
      final now = DateTime.now().toUtc();
      return now.subtract(
        Duration(
          milliseconds: now.millisecond,
          microseconds: now.microsecond,
        ),
      );
    }

    Future<String> plannedSet(
      int position, {
      String load = '0',
      String reps = '10',
      Duration? rest = ninety,
      bool isCompleted = false,
      String? inWorkoutId,
      DateTime? performedAt,
    }) {
      return repositories.sets.create(
        LoggedSetDraft(
          workoutId: inWorkoutId ?? workoutId,
          exerciseId: exerciseId,
          position: position,
          values: _loadRepsValues(load: load, reps: reps),
          plannedRestAfter: rest,
          isCompleted: isCompleted,
          performedAt: performedAt,
        ),
      );
    }

    Future<LoggedSetRecord> setById(String id) async {
      return (await repositories.sets.getById(id))!;
    }

    Future<List<ActivityLogEntry>> entriesFor(String batchId) async {
      final entries = await repositories.activityLog.listEntries();
      return entries
          .where((entry) => entry.batchId == batchId)
          .toList(growable: false);
    }

    test(
        'logSet performs the Current Set, carries the new load, and one undo '
        'restores every touched Set', () async {
      // Planned well before it is done: Log set stamps the completion time.
      final plannedAt = DateTime.utc(2026, 1, 1, 9);
      final ids = <String>[
        for (var position = 0; position < 3; position += 1)
          await plannedSet(position, performedAt: plannedAt),
      ];
      final plannedBefore = <LoggedSetRecord>[
        for (final id in ids) await setById(id),
      ];
      final loggedAfter = nowInSeconds();
      final batchId = newBatchId();

      final result = await repositories.sets.logSet(
        LogSetRequest(
          workoutId: workoutId,
          exerciseId: exerciseId,
          currentSetId: ids.first,
          values: _loadRepsValues(load: '26', reps: '10'),
          comment: '  felt strong ',
          side: SetSide.left,
          rpe: 8,
          restChanged: false,
          rest: const Duration(seconds: 150),
        ),
        batchId: batchId,
      );

      expect(result.setId, ids.first);
      expect(result.alreadyLogged, isFalse);
      expect(result.carriedCount, 2);

      final logged = await setById(ids.first);
      expect(logged.isCompleted, isTrue);
      expect(logged.values, _loadRepsValues(load: '26', reps: '10'));
      expect(logged.comment, 'felt strong');
      expect(logged.side, SetSide.left);
      expect(logged.rpe, 8);
      expect(logged.plannedRestAfter, ninety, reason: 'rest unchanged');
      expect(logged.performedAt!.isBefore(loggedAfter), isFalse);
      for (final id in ids.skip(1)) {
        final later = await setById(id);
        expect(later.performedAt, plannedAt);
        expect(later.isCompleted, isFalse);
        expect(later.values, _loadRepsValues(load: '26', reps: '10'));
        expect(later.plannedRestAfter, ninety);
        expect(later.comment, isNull);
      }

      final entries = await entriesFor(batchId);
      expect(entries, hasLength(3));
      expect(entries.map((entry) => entry.entityId).toSet(), ids.toSet());
      expect(
        entries.map((entry) => entry.entityTable).toSet(),
        <String>{AppDatabase.loggedSetsTable},
      );

      final undo = await repositories.activityLog.undoBatch(batchId);
      expect(undo.hasConflicts, isFalse);
      for (final before in plannedBefore) {
        final restored = await setById(before.id);
        expect(restored.isCompleted, isFalse);
        expect(restored.values, before.values);
        expect(restored.plannedRestAfter, before.plannedRestAfter);
        expect(restored.performedAt, before.performedAt);
        expect(restored.comment, isNull);
        expect(restored.side, isNull);
        expect(restored.rpe, isNull);
      }
    });

    test(
        'logSet writes a planned rest only when changed, and carries it only '
        'to later Sets with the same rest', () async {
      final first = await plannedSet(0, load: '60');
      final second = await plannedSet(1, load: '60');
      final third = await plannedSet(2,
          load: '60',
          rest: const Duration(
            seconds: 60,
          ));
      final unplanned = await plannedSet(3, load: '60', rest: null);
      final unplannedNext = await plannedSet(4, load: '60', rest: null);

      final unchangedBatch = newBatchId();
      await repositories.sets.logSet(
        LogSetRequest(
          workoutId: workoutId,
          exerciseId: exerciseId,
          currentSetId: unplanned,
          values: _loadRepsValues(load: '60', reps: '10'),
          restChanged: false,
          rest: const Duration(seconds: 120),
        ),
        batchId: unchangedBatch,
      );
      expect((await setById(unplanned)).plannedRestAfter, isNull);
      expect(await entriesFor(unchangedBatch), hasLength(1));

      final changedBatch = newBatchId();
      final result = await repositories.sets.logSet(
        LogSetRequest(
          workoutId: workoutId,
          exerciseId: exerciseId,
          currentSetId: first,
          values: _loadRepsValues(load: '60', reps: '10'),
          restChanged: true,
          rest: const Duration(seconds: 120),
        ),
        batchId: changedBatch,
      );

      expect(result.carriedCount, 1);
      expect(
        (await setById(first)).plannedRestAfter,
        const Duration(seconds: 120),
      );
      expect(
        (await setById(second)).plannedRestAfter,
        const Duration(seconds: 120),
      );
      expect(
        (await setById(third)).plannedRestAfter,
        const Duration(seconds: 60),
      );
      expect((await setById(unplannedNext)).plannedRestAfter, isNull);
      expect(await entriesFor(changedBatch), hasLength(2));

      final undo = await repositories.activityLog.undoBatch(changedBatch);
      expect(undo.hasConflicts, isFalse);
      expect((await setById(first)).plannedRestAfter, ninety);
      expect((await setById(first)).isCompleted, isFalse);
      expect((await setById(second)).plannedRestAfter, ninety);
    });

    test(
        'logSet on a completed, deleted or missing Current Set returns '
        'alreadyLogged and writes nothing', () async {
      final completed = await plannedSet(0, isCompleted: true);
      final deleted = await plannedSet(1);
      await repositories.sets.softDelete(deleted);
      final completedBefore = await setById(completed);
      final entryCount = (await repositories.activityLog.listEntries()).length;

      for (final currentSetId in <String>[
        completed,
        deleted,
        '00000000-0000-7000-8000-000000000000',
      ]) {
        final batchId = newBatchId();
        final result = await repositories.sets.logSet(
          LogSetRequest(
            workoutId: workoutId,
            exerciseId: exerciseId,
            currentSetId: currentSetId,
            values: _loadRepsValues(load: '99', reps: '1'),
            restChanged: true,
            rest: const Duration(seconds: 30),
          ),
          batchId: batchId,
        );

        expect(result.alreadyLogged, isTrue);
        expect(result.setId, currentSetId);
        expect(result.carriedCount, 0);
        expect(await entriesFor(batchId), isEmpty);
      }

      expect(
        (await repositories.activityLog.listEntries()).length,
        entryCount,
      );
      final completedAfter = await setById(completed);
      expect(completedAfter.values, completedBefore.values);
      expect(completedAfter.updatedAt, completedBefore.updatedAt);
    });

    test(
        'logSet without a Current Set creates a Performed Set at the next '
        'position', () async {
      await plannedSet(0, isCompleted: true);
      await plannedSet(4, isCompleted: true);
      final loggedAfter = nowInSeconds();

      final batchId = newBatchId();
      final result = await repositories.sets.logSet(
        LogSetRequest(
          workoutId: workoutId,
          exerciseId: exerciseId,
          values: _loadRepsValues(load: '40', reps: '8'),
          comment: 'extra',
          restChanged: false,
          rest: const Duration(seconds: 120),
        ),
        batchId: batchId,
      );

      expect(result.alreadyLogged, isFalse);
      expect(result.carriedCount, 0);
      final created = await setById(result.setId);
      expect(created.position, 5);
      expect(created.isCompleted, isTrue);
      expect(created.values, _loadRepsValues(load: '40', reps: '8'));
      expect(created.comment, 'extra');
      expect(created.plannedRestAfter, isNull);
      expect(created.performedAt!.isBefore(loggedAfter), isFalse);
      final entries = await entriesFor(batchId);
      expect(entries, hasLength(1));
      expect(entries.single.beforeImage, isNull);

      final withRest = await repositories.sets.logSet(
        LogSetRequest(
          workoutId: workoutId,
          exerciseId: exerciseId,
          values: _loadRepsValues(load: '40', reps: '8'),
          restChanged: true,
          rest: const Duration(seconds: 75),
        ),
        batchId: newBatchId(),
      );
      final second = await setById(withRest.setId);
      expect(second.position, 6);
      expect(second.plannedRestAfter, const Duration(seconds: 75));
    });

    test('logSet rejects a hard-invalid value and writes nothing', () async {
      final current = await plannedSet(0);
      final later = await plannedSet(1);
      final batchId = newBatchId();

      await expectLater(
        repositories.sets.logSet(
          LogSetRequest(
            workoutId: workoutId,
            exerciseId: exerciseId,
            currentSetId: current,
            values: _loadRepsValues(load: '-1', reps: '10'),
            restChanged: false,
          ),
          batchId: batchId,
        ),
        throwsA(isA<SetValidationException>()),
      );

      expect((await setById(current)).isCompleted, isFalse);
      expect((await setById(later)).values.load?.entered, '0');
      expect(await entriesFor(batchId), isEmpty);
    });

    test(
        'findRememberedRest takes the latest Performed Set with a rest, '
        'skipping null and zero rests, Planned Sets and deleted Workouts',
        () async {
      expect(await repositories.sets.findRememberedRest(exerciseId), isNull);

      // A later-started Workout whose Set was performed earlier: performedAt
      // decides, not the Workout's start.
      final laterStartedWorkout = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: startedAt.add(const Duration(days: 1)),
          timezone: 'UTC',
        ),
      );
      await plannedSet(
        0,
        rest: const Duration(seconds: 45),
        isCompleted: true,
        inWorkoutId: laterStartedWorkout,
        performedAt: startedAt.add(const Duration(minutes: 5)),
      );
      await plannedSet(
        0,
        rest: ninety,
        isCompleted: true,
        performedAt: startedAt.add(const Duration(minutes: 10)),
      );
      expect(await repositories.sets.findRememberedRest(exerciseId), ninety);

      await plannedSet(
        1,
        rest: null,
        isCompleted: true,
        performedAt: startedAt.add(const Duration(minutes: 20)),
      );
      await plannedSet(
        2,
        rest: Duration.zero,
        isCompleted: true,
        performedAt: startedAt.add(const Duration(minutes: 30)),
      );
      await plannedSet(
        3,
        rest: const Duration(seconds: 30),
        performedAt: startedAt.add(const Duration(minutes: 40)),
      );
      expect(await repositories.sets.findRememberedRest(exerciseId), ninety);

      // The Workout row deleted on its own (as a synced tombstone can land),
      // with its Set still active.
      final deletedWorkout = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: startedAt.add(const Duration(days: 2)),
          timezone: 'UTC',
        ),
      );
      await plannedSet(
        0,
        rest: const Duration(seconds: 15),
        isCompleted: true,
        inWorkoutId: deletedWorkout,
        performedAt: startedAt.add(const Duration(days: 2)),
      );
      await (database.update(database.workoutSessions)
            ..where((row) => row.id.equals(deletedWorkout)))
          .write(
        WorkoutSessionsCompanion(
          deletedAt: Value<DateTime?>(DateTime.utc(2026, 11, 5)),
        ),
      );
      expect(await repositories.sets.findRememberedRest(exerciseId), ninety);

      final otherExercise = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Pull-Up',
          type: ExerciseType(const <DimensionId>[DimensionId.reps]),
        ),
      );
      expect(
        await repositories.sets.findRememberedRest(otherExercise),
        isNull,
      );
    });

    test('updatePerformed writes one row with one Activity Log entry',
        () async {
      final performed = await plannedSet(0, load: '60', isCompleted: true);
      final later = await plannedSet(1, load: '60');
      final batchId = newBatchId();

      await repositories.sets.updatePerformed(
        performed,
        values: _loadRepsValues(load: '62.5', reps: '9'),
        comment: 'grip slipped',
        rpe: 9,
        restChanged: false,
        rest: const Duration(seconds: 150),
        batchId: batchId,
      );

      final updated = await setById(performed);
      expect(updated.values, _loadRepsValues(load: '62.5', reps: '9'));
      expect(updated.comment, 'grip slipped');
      expect(updated.rpe, 9);
      expect(updated.isCompleted, isTrue);
      expect(updated.plannedRestAfter, ninety);
      expect((await setById(later)).values.load?.entered, '60');
      final entries = await entriesFor(batchId);
      expect(entries, hasLength(1));
      expect(entries.single.entityId, performed);

      await repositories.sets.updatePerformed(
        performed,
        values: _loadRepsValues(load: '62.5', reps: '9'),
        restChanged: true,
        rest: const Duration(seconds: 45),
        batchId: newBatchId(),
      );
      final rested = await setById(performed);
      expect(rested.plannedRestAfter, const Duration(seconds: 45));
      expect(rested.comment, isNull);
      expect((await setById(later)).plannedRestAfter, ninety);
    });

    test(
        'appendToWorkout gives drafts consecutive positions after the last '
        'Set, under one batch that one Undo removes', () async {
      await plannedSet(0);
      await plannedSet(4);
      final batchId = newBatchId();

      final ids = await repositories.sets.appendToWorkout(
        workoutId,
        <LoggedSetDraft>[
          for (final load in <String>['60', '62.5'])
            LoggedSetDraft(
              workoutId: workoutId,
              exerciseId: exerciseId,
              position: 0,
              values: _loadRepsValues(load: load, reps: '8'),
              plannedRestAfter: ninety,
            ),
        ],
        batchId: batchId,
      );

      expect(ids, hasLength(2));
      final appended = <LoggedSetRecord>[
        for (final id in ids) await setById(id),
      ];
      expect(appended.map((set) => set.position), <int>[5, 6]);
      expect(
        appended.map((set) => set.values.load?.entered),
        <String>['60', '62.5'],
      );
      expect(appended.every((set) => !set.isCompleted), isTrue);
      expect(appended.every((set) => set.plannedRestAfter == ninety), isTrue);
      expect(await entriesFor(batchId), hasLength(2));

      final undo = await repositories.activityLog.undoBatch(batchId);
      expect(undo.hasConflicts, isFalse);
      final active = await repositories.sets.listActiveForWorkout(workoutId);
      expect(active.map((set) => set.id), isNot(contains(ids.first)));
      expect(active.map((set) => set.id), isNot(contains(ids.last)));
    });

    test(
        'adjust extends, shortens, shortens past now and clears the prepare '
        'cue', () async {
      final timerId = await repositories.restTimers.start(
        RestTimerDraft(workoutId: workoutId, duration: ninety),
        now: startedAt,
      );

      await repositories.restTimers.adjust(
        timerId,
        const Duration(seconds: 15),
        now: startedAt.add(const Duration(seconds: 10)),
      );
      var timer = (await repositories.restTimers.getById(timerId))!;
      expect(timer.deadlineAt, startedAt.add(const Duration(seconds: 105)));
      expect(timer.duration, const Duration(seconds: 105));

      await repositories.restTimers.adjust(
        timerId,
        const Duration(seconds: -15),
        now: startedAt.add(const Duration(seconds: 20)),
      );
      timer = (await repositories.restTimers.getById(timerId))!;
      expect(timer.deadlineAt, startedAt.add(ninety));
      expect(timer.duration, ninety);

      // The prepare cue fired close to the deadline; +15 s leaves more than
      // 3 s, so it plays again.
      final nearEnd = startedAt.add(const Duration(seconds: 88));
      await repositories.restTimers.markPrepareAlertFired(
        timerId,
        now: nearEnd,
      );
      await repositories.restTimers.adjust(
        timerId,
        const Duration(seconds: 15),
        now: nearEnd,
      );
      timer = (await repositories.restTimers.getById(timerId))!;
      expect(timer.prepareAlertFiredAt, isNull);

      // With 3 s or less left after the adjust, a fired cue stays fired.
      final almostDone = startedAt.add(const Duration(seconds: 102));
      await repositories.restTimers.markPrepareAlertFired(
        timerId,
        now: almostDone,
      );
      await repositories.restTimers.adjust(
        timerId,
        const Duration(seconds: -1),
        now: almostDone,
      );
      timer = (await repositories.restTimers.getById(timerId))!;
      expect(timer.deadlineAt, startedAt.add(const Duration(seconds: 104)));
      expect(timer.prepareAlertFiredAt, isNotNull);

      final pastNow = startedAt.add(const Duration(seconds: 103));
      await repositories.restTimers.adjust(
        timerId,
        const Duration(seconds: -200),
        now: pastNow,
      );
      timer = (await repositories.restTimers.getById(timerId))!;
      expect(timer.deadlineAt, pastNow);
      expect(timer.duration, const Duration(seconds: 1));
      expect(timer.status, RestTimerStatus.running);

      final timerEntries = (await repositories.activityLog.listEntries())
          .where((entry) => entry.entityId == timerId)
          .toList(growable: false);
      // The start, five adjusts and two prepare cues.
      expect(timerEntries, hasLength(8));

      await repositories.restTimers.cancel(timerId);
      final canceled = (await repositories.restTimers.getById(timerId))!;
      await repositories.restTimers.adjust(
        timerId,
        const Duration(seconds: 15),
        now: pastNow,
      );
      final untouched = (await repositories.restTimers.getById(timerId))!;
      expect(untouched.deadlineAt, canceled.deadlineAt);
      expect(untouched.updatedAt, canceled.updatedAt);
    });

    test('watchActiveForWorkout orders tied positions by id', () async {
      // Ids that sort against insertion order.
      const earliestId = '00000000-0000-7000-8000-000000000000';
      const latestId = 'ffffffff-ffff-7fff-bfff-ffffffffffff';
      for (final id in <String>[latestId, earliestId]) {
        final created = await plannedSet(0);
        await (database.update(database.loggedSets)
              ..where((row) => row.id.equals(created)))
            .write(LoggedSetsCompanion(id: Value<String>(id)));
      }

      final sets =
          await repositories.sets.watchActiveForWorkout(workoutId).first;

      expect(sets.map((set) => set.id), <String>[earliestId, latestId]);
    });

    test(
        'a Template with no rests, logged unchanged through logSet, gives no '
        'divergence (CUJ 6)', () async {
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Upper B'),
      );
      final entryId = await repositories.workoutTemplates.addExercise(
        templateId,
        exerciseId,
      );
      await repositories.workoutTemplates.addPrescription(
        entryId,
        PrescriptionDraft(
          mode: PrescriptionMode.fixed,
          values: _loadRepsValues(load: '60', reps: '10'),
          repeat: 3,
        ),
      );
      final materialized = await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(workoutTemplateId: templateId),
        now: DateTime(2026, 11, 2, 8),
      );

      final planned =
          await repositories.sets.listActiveForWorkout(materialized.workoutId);
      expect(planned, hasLength(3));
      for (final set in planned) {
        expect(set.plannedRestAfter, isNull);
        await repositories.sets.logSet(
          LogSetRequest(
            workoutId: materialized.workoutId,
            exerciseId: exerciseId,
            currentSetId: set.id,
            values: set.values,
            restChanged: false,
            rest: RestTimerRepository.defaultDuration,
          ),
          batchId: newBatchId(),
        );
      }

      final performed =
          await repositories.sets.listActiveForWorkout(materialized.workoutId);
      expect(performed.every((set) => set.isCompleted), isTrue);
      expect(performed.every((set) => set.plannedRestAfter == null), isTrue);
      final summary = await repositories.templateDivergence.summaryForWorkout(
        materialized.workoutId,
      );
      expect(summary, isNotNull);
      expect(summary!.hasDivergence, isFalse);
    });
  });

  group('WorkoutExerciseRepository.replace', () {
    late AppDatabase database;
    late TrainingRepositories repositories;
    late String workoutId;
    final idGenerator = UuidV7Generator();
    final startedAt = DateTime.utc(2026, 11, 2, 6);
    final names = <String, String>{};
    var nextSetPosition = 0;

    setUp(() async {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(
        database,
        platformSeedSource: const _StarterSeedSource(),
      );
      names.clear();
      nextSetPosition = 0;
      workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(startedAt: startedAt, timezone: 'UTC'),
      );
    });

    tearDown(() async {
      await database.close();
    });

    String newBatchId() => idGenerator.generate(timestamp: DateTime.now());

    Future<String> exercise(
      String name, {
      List<DimensionId> dimensions = const <DimensionId>[
        DimensionId.load,
        DimensionId.reps,
      ],
      TrainingUnit defaultLoadUnit = TrainingUnit.kilogram,
    }) async {
      final id = await repositories.exercises.create(
        ExerciseDraft(
          name: name,
          type: ExerciseType(dimensions),
          defaultLoadUnit: defaultLoadUnit,
        ),
      );
      names[id] = name;
      return id;
    }

    /// Adds [name] to the Workout with [performed] Performed Sets, then
    /// [planned] Planned Sets resting 90 s, 60 s, 90 s... in turn.
    Future<String> addExercise(
      String name, {
      int performed = 0,
      int planned = 2,
    }) async {
      final exerciseId = await exercise(name);
      final workoutExerciseId = await repositories.workoutExercises.create(
        WorkoutExerciseDraft(workoutId: workoutId, exerciseId: exerciseId),
      );
      for (var index = 0; index < performed + planned; index += 1) {
        await repositories.sets.create(
          LoggedSetDraft(
            workoutId: workoutId,
            exerciseId: exerciseId,
            position: nextSetPosition++,
            values: _loadRepsValues(load: '60', reps: '10'),
            plannedRestAfter: Duration(seconds: index.isEven ? 90 : 60),
            isCompleted: index < performed,
          ),
        );
      }
      return workoutExerciseId;
    }

    Future<String> superset(List<String> workoutExerciseIds) {
      return repositories.exerciseGroups.create(
        ExerciseGroupDraft(
          workoutId: workoutId,
          name: 'Superset',
          colorHex: '#2F6FED',
          workoutExerciseIds: workoutExerciseIds,
        ),
      );
    }

    /// A Workout before this one in which [exerciseId] was performed.
    Future<void> performedEarlier(
      String exerciseId, {
      required String load,
      required String reps,
    }) async {
      final earlierId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: startedAt.subtract(const Duration(days: 3)),
          timezone: 'UTC',
        ),
      );
      await repositories.sets.create(
        LoggedSetDraft(
          workoutId: earlierId,
          exerciseId: exerciseId,
          position: 0,
          values: _loadRepsValues(load: load, reps: reps),
          isCompleted: true,
        ),
      );
    }

    Future<List<WorkoutExerciseRecord>> workoutExercises() {
      return repositories.workoutExercises.listActiveForWorkout(workoutId);
    }

    Future<List<String>> orderNames() async {
      return (await workoutExercises())
          .map((row) => names[row.exerciseId]!)
          .toList(growable: false);
    }

    /// Each active group's members by name, in member position order.
    Future<List<List<String>>> groupNames() async {
      final byId = <String, String>{
        for (final row in await workoutExercises()) row.id: row.exerciseId,
      };
      final groups =
          await repositories.exerciseGroups.listActiveForWorkout(workoutId);
      return <List<String>>[
        for (final group in groups)
          <String>[
            for (final id in group.workoutExerciseIds) names[byId[id]]!,
          ],
      ];
    }

    Future<List<LoggedSetRecord>> setsOf(String exerciseId) async {
      final sets = await repositories.sets.listActiveForWorkout(workoutId);
      return sets
          .where((set) => set.exerciseId == exerciseId)
          .toList(growable: false);
    }

    Future<List<ActivityLogEntry>> entriesFor(String batchId) async {
      final entries = await repositories.activityLog.listEntries();
      return entries
          .where((entry) => entry.batchId == batchId)
          .toList(growable: false);
    }

    /// Every group's members are next to each other in the Workout order.
    Future<void> expectGroupsAdjacent() async {
      final order = (await workoutExercises()).map((row) => row.id).toList();
      final groups =
          await repositories.exerciseGroups.listActiveForWorkout(workoutId);
      for (final group in groups) {
        final indexes = group.workoutExerciseIds.map(order.indexOf).toList()
          ..sort();
        expect(indexes.first, isNonNegative);
        expect(indexes.last - indexes.first, indexes.length - 1);
      }
    }

    Future<void> expectEachRowWrittenOnce(String batchId) async {
      final entries = await entriesFor(batchId);
      final keys =
          entries.map((entry) => '${entry.entityTable}/${entry.entityId}');
      expect(keys.toSet(), hasLength(entries.length));
    }

    for (final size in <int>[2, 3]) {
      for (var oldIndex = 0; oldIndex < size; oldIndex += 1) {
        for (final withPerformed in <bool>[false, true]) {
          final place = oldIndex == 0
              ? 'first'
              : oldIndex == size - 1
                  ? 'last'
                  : 'middle';
          test(
              'old $place in a $size-member group, '
              '${withPerformed ? 'with' : 'without'} a Performed Set',
              () async {
            final memberNames = <String>[
              for (var index = 0; index < size; index += 1) 'M$index',
            ];
            final oldName = memberNames[oldIndex];
            await addExercise('Warm-up');
            final memberIds = <String>[
              for (final name in memberNames)
                await addExercise(
                  name,
                  performed: name == oldName && withPerformed ? 1 : 0,
                ),
            ];
            await addExercise('Finisher');
            final groupId = await superset(memberIds);
            final oldWorkoutExercise = (await workoutExercises())
                .firstWhere((row) => row.id == memberIds[oldIndex]);
            final oldPlanned = (await setsOf(oldWorkoutExercise.exerciseId))
                .where((set) => !set.isCompleted)
                .toList(growable: false);
            final orderBefore = await orderNames();
            final newExerciseId = await exercise('New');
            await performedEarlier(newExerciseId, load: '40', reps: '8');
            final batchId = newBatchId();

            final newId = await repositories.workoutExercises.replace(
              memberIds[oldIndex],
              newExerciseId,
              batchId: batchId,
            );

            final replacedMembers = <String>[...memberNames]..[oldIndex] =
                'New';
            expect(await orderNames(), <String>[
              'Warm-up',
              ...replacedMembers,
              if (withPerformed) oldName,
              'Finisher',
            ]);
            expect(await groupNames(), <List<String>>[replacedMembers]);
            final group = await repositories.exerciseGroups.getById(groupId);
            expect(group!.workoutExerciseIds[oldIndex], newId);
            await expectGroupsAdjacent();

            final newSets = await setsOf(newExerciseId);
            expect(newSets.every((set) => !set.isCompleted), isTrue);
            expect(
              newSets.map((set) => set.position),
              oldPlanned.map((set) => set.position),
            );
            expect(
              newSets.map((set) => set.plannedRestAfter),
              oldPlanned.map((set) => set.plannedRestAfter),
            );
            for (final set in newSets) {
              expect(set.values, _loadRepsValues(load: '40', reps: '8'));
            }
            final oldSetsAfter = await setsOf(oldWorkoutExercise.exerciseId);
            expect(oldSetsAfter, hasLength(withPerformed ? 1 : 0));
            expect(oldSetsAfter.every((set) => set.isCompleted), isTrue);
            final oldAfter = await repositories.workoutExercises
                .getById(memberIds[oldIndex]);
            expect(oldAfter!.deletedAt, withPerformed ? isNull : isNotNull);

            await expectEachRowWrittenOnce(batchId);
            final undo = await repositories.activityLog.undoBatch(batchId);
            expect(undo.hasConflicts, isFalse);
            expect(await orderNames(), orderBefore);
            expect(await groupNames(), <List<String>>[memberNames]);
            expect(await setsOf(newExerciseId), isEmpty);
            expect(
              (await setsOf(oldWorkoutExercise.exerciseId))
                  .where((set) => !set.isCompleted)
                  .map((set) => set.id),
              oldPlanned.map((set) => set.id),
            );
          });
        }
      }
    }

    test('an ungrouped old without a Performed Set leaves the Workout',
        () async {
      await addExercise('A');
      final oldId = await addExercise('Old');
      await addExercise('B');
      final newExerciseId = await exercise('New');
      final batchId = newBatchId();

      await repositories.workoutExercises.replace(
        oldId,
        newExerciseId,
        batchId: batchId,
      );

      expect(await orderNames(), <String>['A', 'New', 'B']);
      expect(await groupNames(), isEmpty);
      expect(
        (await workoutExercises()).map((row) => row.position),
        <int>[0, 1, 2],
      );
      await expectEachRowWrittenOnce(batchId);
      final undo = await repositories.activityLog.undoBatch(batchId);
      expect(undo.hasConflicts, isFalse);
      expect(await orderNames(), <String>['A', 'Old', 'B']);
    });

    test('an ungrouped old with a Performed Set moves after the new one',
        () async {
      await addExercise('A');
      final oldId = await addExercise('Old', performed: 1);
      await addExercise('B');
      final newExerciseId = await exercise('New');
      final batchId = newBatchId();

      await repositories.workoutExercises.replace(
        oldId,
        newExerciseId,
        batchId: batchId,
      );

      expect(await orderNames(), <String>['A', 'New', 'Old', 'B']);
      expect(
        (await workoutExercises()).map((row) => row.position),
        <int>[0, 1, 2, 3],
      );
      await expectEachRowWrittenOnce(batchId);
      final undo = await repositories.activityLog.undoBatch(batchId);
      expect(undo.hasConflicts, isFalse);
      expect(await orderNames(), <String>['A', 'Old', 'B']);
    });

    test('with no history the new Planned Sets are zero in its own units',
        () async {
      final oldId = await addExercise('Old');
      final newExerciseId = await exercise(
        'New',
        defaultLoadUnit: TrainingUnit.pound,
      );
      final plankId = await exercise(
        'Plank',
        dimensions: const <DimensionId>[DimensionId.duration],
      );

      await repositories.workoutExercises.replace(
        oldId,
        newExerciseId,
        batchId: newBatchId(),
      );
      final newSets = await setsOf(newExerciseId);
      expect(newSets, hasLength(2));
      for (final set in newSets) {
        expect(
          set.values,
          zeroLoggedSetFor(
            dimensions: const <DimensionId>[DimensionId.load, DimensionId.reps],
            defaultLoadUnit: TrainingUnit.pound,
          ),
        );
      }

      final newId = (await workoutExercises()).single.id;
      await repositories.workoutExercises.replace(
        newId,
        plankId,
        batchId: newBatchId(),
      );
      final plankSets = await setsOf(plankId);
      expect(
        plankSets.map((set) => set.plannedRestAfter),
        newSets.map((set) => set.plannedRestAfter),
      );
      for (final set in plankSets) {
        expect(
          set.values,
          zeroLoggedSetFor(
            dimensions: const <DimensionId>[DimensionId.duration],
            defaultLoadUnit: TrainingUnit.kilogram,
          ),
        );
      }
    });

    test('history with other dimensions is not used', () async {
      final oldId = await addExercise('Old');
      final newExerciseId = await exercise('New');
      final earlierId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: startedAt.subtract(const Duration(days: 3)),
          timezone: 'UTC',
        ),
      );
      await repositories.sets.create(
        LoggedSetDraft(
          workoutId: earlierId,
          exerciseId: newExerciseId,
          position: 0,
          values: LoggedSet.fromValues(<SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '12',
              unit: TrainingUnit.repetition,
            ),
          ]),
          isCompleted: true,
        ),
      );

      await repositories.workoutExercises.replace(
        oldId,
        newExerciseId,
        batchId: newBatchId(),
      );

      for (final set in await setsOf(newExerciseId)) {
        expect(set.values, _loadRepsValues(load: '0', reps: '0'));
      }
    });

    test('an Exercise already in the Workout throws and writes nothing',
        () async {
      final oldId = await addExercise('Old');
      final otherId = await addExercise('Other');
      final otherExerciseId = (await workoutExercises())
          .firstWhere((row) => row.id == otherId)
          .exerciseId;
      final oldExerciseId = (await workoutExercises())
          .firstWhere((row) => row.id == oldId)
          .exerciseId;
      final entriesBefore = await repositories.activityLog.listEntries();

      for (final exerciseId in <String>[otherExerciseId, oldExerciseId]) {
        final batchId = newBatchId();
        await expectLater(
          repositories.workoutExercises.replace(
            oldId,
            exerciseId,
            batchId: batchId,
          ),
          throwsA(isA<AlreadyInWorkoutException>()),
        );
        expect(await entriesFor(batchId), isEmpty);
      }

      expect(
        await repositories.activityLog.listEntries(),
        hasLength(entriesBefore.length),
      );
      expect(await orderNames(), <String>['Old', 'Other']);
    });

    test('a removed old or an archived Exercise throws and writes nothing',
        () async {
      final oldId = await addExercise('Old');
      final archivedId = await exercise('Archived');
      await repositories.exercises.softDelete(archivedId);
      final removedId = await addExercise('Removed');
      await repositories.workoutExercises.softDelete(removedId);
      final newExerciseId = await exercise('New');
      final entriesBefore = await repositories.activityLog.listEntries();

      for (final (workoutExerciseId, exerciseId) in <(String, String)>[
        (oldId, archivedId),
        (oldId, 'missing-exercise'),
        (removedId, newExerciseId),
      ]) {
        final batchId = newBatchId();
        await expectLater(
          repositories.workoutExercises.replace(
            workoutExerciseId,
            exerciseId,
            batchId: batchId,
          ),
          throwsA(isA<StateError>()),
        );
        expect(await entriesFor(batchId), isEmpty);
      }

      expect(
        await repositories.activityLog.listEntries(),
        hasLength(entriesBefore.length),
      );
      expect(await orderNames(), <String>['Old']);
    });

    test('the group survives a later reorder', () async {
      await addExercise('Warm-up');
      final pullUpId = await addExercise('Pull-Up', performed: 1);
      final pressId = await addExercise('Press', performed: 1);
      await addExercise('Finisher');
      await superset(<String>[pullUpId, pressId]);
      final newExerciseId = await exercise('New');

      final newId = await repositories.workoutExercises.replace(
        pressId,
        newExerciseId,
        batchId: newBatchId(),
      );
      final ids = (await workoutExercises()).map((row) => row.id).toList();
      // Move the Finisher to the front; the group's run is unbroken.
      await repositories.workoutExercises.reorderForWorkout(
        workoutId: workoutId,
        orderedIds: <String>[ids.last, ...ids.take(ids.length - 1)],
      );

      expect(await orderNames(), <String>[
        'Finisher',
        'Warm-up',
        'Pull-Up',
        'New',
        'Press',
      ]);
      expect(await groupNames(), <List<String>>[
        <String>['Pull-Up', 'New'],
      ]);
      final groups =
          await repositories.exerciseGroups.listActiveForWorkout(workoutId);
      expect(groups.single.workoutExerciseIds, <String>[pullUpId, newId]);
    });

    test('CUJ 13: replace Incline Press in a superset mid-way', () async {
      final pullUpId = await addExercise('Pull-Up', performed: 1);
      final inclinePressId = await addExercise('Incline Press', performed: 1);
      await superset(<String>[pullUpId, inclinePressId]);
      final inclinePressExerciseId = (await workoutExercises())
          .firstWhere((row) => row.id == inclinePressId)
          .exerciseId;
      final oldPlanned = (await setsOf(inclinePressExerciseId))
          .where((set) => !set.isCompleted)
          .toList(growable: false);
      expect(oldPlanned, hasLength(2));
      final machinePressExerciseId = await exercise('Incline Machine Press');
      await performedEarlier(machinePressExerciseId, load: '50', reps: '12');
      final batchId = newBatchId();

      final newId = await repositories.workoutExercises.replace(
        inclinePressId,
        machinePressExerciseId,
        batchId: batchId,
      );

      expect(await orderNames(), <String>[
        'Pull-Up',
        'Incline Machine Press',
        'Incline Press',
      ]);
      expect(await groupNames(), <List<String>>[
        <String>['Pull-Up', 'Incline Machine Press'],
      ]);
      final machineSets = await setsOf(machinePressExerciseId);
      expect(machineSets, hasLength(2));
      expect(
        machineSets.map((set) => set.plannedRestAfter),
        oldPlanned.map((set) => set.plannedRestAfter),
      );
      for (final set in machineSets) {
        expect(set.isCompleted, isFalse);
        expect(set.values, _loadRepsValues(load: '50', reps: '12'));
      }
      final inclineSets = await setsOf(inclinePressExerciseId);
      expect(inclineSets, hasLength(1));
      expect(inclineSets.single.isCompleted, isTrue);
      await expectEachRowWrittenOnce(batchId);

      // Now stays on the superset: Incline Press holds the latest Performed
      // Set, but the group is still in progress.
      final groups =
          await repositories.exerciseGroups.listActiveForWorkout(workoutId);
      final groupIdByMember = <String, String>{
        for (final group in groups)
          for (final id in group.workoutExerciseIds) id: group.id,
      };
      final allSets = await repositories.sets.listActiveForWorkout(workoutId);
      final progress = <ProgressExercise>[
        for (final row in await workoutExercises())
          progressExerciseFor(
            workoutExerciseId: row.id,
            groupId: groupIdByMember[row.id],
            sets: allSets
                .where((set) => set.exerciseId == row.exerciseId)
                .map(progressSetOf),
          ),
      ];
      expect(currentExerciseFor(progress), CurrentGroup(groups.single.id));
      expect(nowCardWorkoutExerciseId(progress), pullUpId);
      expect(newId, isNot(inclinePressId));
    });
  });
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (condition()) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  fail('Timed out waiting for condition.');
}

Future<Set<String>> _indexNames(
  AppDatabase database,
  String tableName,
) async {
  final rows =
      await database.customSelect('PRAGMA index_list($tableName)').get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

Future<String> _createLoadRepsSet(
  TrainingRepositories repositories, {
  required String workoutId,
  required String exerciseId,
  required int position,
  required String load,
  required String reps,
  bool isCompleted = false,
}) {
  return repositories.sets.create(
    LoggedSetDraft(
      workoutId: workoutId,
      exerciseId: exerciseId,
      position: position,
      values: _loadRepsValues(load: load, reps: reps),
      isCompleted: isCompleted,
    ),
  );
}

LoggedSet _loadRepsValues({
  required String load,
  required String reps,
}) {
  return LoggedSet.fromValues(
    <SetDimensionValue>[
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
    ],
  );
}

class _StarterSeedSource implements PlatformExerciseSeedSource {
  const _StarterSeedSource();

  @override
  Future<PlatformExerciseSeed> load() async {
    return PlatformExerciseSeed(
      categories: <SeedExerciseCategory>[
        SeedExerciseCategory(
          id: '01910000-0000-7000-8000-000000000001',
          name: 'Strength',
          sortOrder: 0,
          colorHex: '#2F6FED',
          updatedAt: DateTime.utc(2026),
        ),
        SeedExerciseCategory(
          id: '01910000-0000-7000-8000-000000000002',
          name: 'Core',
          sortOrder: 1,
          colorHex: '#1F9D55',
          updatedAt: DateTime.utc(2026),
        ),
      ],
      exercises: <SeedExercise>[
        SeedExercise(
          id: '01910000-0000-7000-8000-000000000101',
          name: 'Barbell Squat',
          dimensions: <DimensionId>[DimensionId.load, DimensionId.reps],
          categoryId: '01910000-0000-7000-8000-000000000001',
          notes: null,
          updatedAt: DateTime.utc(2026),
        ),
        SeedExercise(
          id: '01910000-0000-7000-8000-000000000102',
          name: 'Plank',
          dimensions: <DimensionId>[DimensionId.duration],
          categoryId: '01910000-0000-7000-8000-000000000002',
          notes: null,
          updatedAt: DateTime.utc(2026),
        ),
      ],
    );
  }
}
