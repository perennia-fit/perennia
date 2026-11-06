import 'dart:convert';

import 'package:drift/drift.dart' show QueryRow, Variable, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/settings/account_settings.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';

void main() {
  // The bundled seeds load from assets.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('eraseAllData', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('every table is either erased or deliberately kept', () {
      expect(
        <String>{
          ...TrainingRepositories.eraseTableNames,
          ..._keptTables,
        },
        AppDatabase.schemaTableNames.toSet(),
      );
      expect(
        TrainingRepositories.eraseTableNames.toSet().intersection(_keptTables),
        isEmpty,
      );
    });

    test('erases every authored domain and keeps settings and the seeds',
        () async {
      final seeded = await _seedEveryDomain(repositories);
      final platformExerciseIds = await _liveIds(
        database,
        AppDatabase.exercisesTable,
        where: "library_origin = 'platform'",
      );
      final otcCompoundIds = await _liveIds(
        database,
        AppDatabase.compoundsTable,
        where: 'id != ?',
        variables: <Object>[seeded.userCompoundId],
      );
      final defaultMealTypeIds = await _liveIds(
        database,
        AppDatabase.mealTypesTable,
        where: 'id != ?',
        variables: <Object>[seeded.userMealTypeId],
      );
      final platformCategoryIds = await _liveIds(
        database,
        AppDatabase.exerciseCategoriesTable,
        where: 'id != ?',
        variables: <Object>[seeded.userCategoryId],
      );
      final starterFocusIds = await _liveIds(
        database,
        AppDatabase.focusesTable,
        where: 'id != ?',
        variables: <Object>[seeded.userFocusId],
      );
      final starterPurposeIds = await _liveIds(
        database,
        AppDatabase.purposesTable,
        where: 'id != ?',
        variables: <Object>[seeded.userPurposeId],
      );
      expect(platformExerciseIds, isNotEmpty);
      expect(starterFocusIds, isNotEmpty);
      expect(starterPurposeIds, hasLength(6));
      expect(otcCompoundIds, isNotEmpty);
      expect(defaultMealTypeIds, isNotEmpty);
      expect(platformCategoryIds, isNotEmpty);
      for (final table in TrainingRepositories.eraseTableNames) {
        if (table == AppDatabase.measurementsTable ||
            table == AppDatabase.measurementEntriesTable) {
          continue; // Legacy tables: nothing writes them any more.
        }
        expect(
          await _liveIds(database, table),
          isNotEmpty,
          reason: 'the fixture should seed $table',
        );
      }
      final settingsBefore = await database.select(database.userSettings).get();

      await repositories.eraseAllData();

      final seedOwned = <String, Set<String>>{
        AppDatabase.exercisesTable: platformExerciseIds,
        AppDatabase.compoundsTable: otcCompoundIds,
        AppDatabase.mealTypesTable: defaultMealTypeIds,
        AppDatabase.exerciseCategoriesTable: platformCategoryIds,
        AppDatabase.focusesTable: starterFocusIds,
        AppDatabase.purposesTable: starterPurposeIds,
      };
      for (final table in TrainingRepositories.eraseTableNames) {
        expect(
          await _liveIds(database, table),
          seedOwned[table] ?? isEmpty,
          reason: '$table should keep only seed-owned rows',
        );
      }
      expect(
          await database.select(database.userSettings).get(), settingsBefore);
      expect(await repositories.exercises.listActive(), isNotEmpty);
    });

    test(
        'the starter Purposes and seed Compounds keep their names and tags '
        '(compound-purposes.md, D1)', () async {
      await _seedEveryDomain(repositories);
      await repositories.protocols.purposes.rename(
        starterPurposes.first.id,
        name: 'Rest',
      );
      List<Map<String, Object?>> rowsOf(Iterable<QueryRow> rows) =>
          rows.map((row) => row.data).toList(growable: false);
      Future<List<Map<String, Object?>>> seedCompounds() async => rowsOf(
            await database
                .customSelect(
                  'SELECT id, name, purpose_ids FROM compounds '
                  "WHERE id LIKE '019200ff-%' ORDER BY id",
                )
                .get(),
          );
      final compoundsBefore = await seedCompounds();
      expect(compoundsBefore, hasLength(6));
      expect(
        compoundsBefore.every((row) => row['purpose_ids'] != '[]'),
        isTrue,
      );

      await repositories.eraseAllData();

      expect(await seedCompounds(), compoundsBefore);
      final purposes = await repositories.protocols.purposes.listActive();
      expect(purposes, hasLength(6));
      expect(purposes.first.name, 'Rest');
      expect(
        purposes.map((p) => p.id).toSet(),
        starterPurposes.map((s) => s.id).toSet(),
      );
    });

    test('records one Activity Log tombstone per erased row, in one batch',
        () async {
      await _seedEveryDomain(repositories);
      final liveBefore = <String, Set<String>>{
        for (final table in TrainingRepositories.eraseTableNames)
          table: await _liveIds(database, table),
      };

      await repositories.eraseAllData();

      final eraseRows = await (database.select(database.activityLog)
            ..where((row) => row.actor.equals('settings')))
          .get();
      expect(eraseRows.map((row) => row.batchId).toSet(), hasLength(1));
      final tombstonedByTable = <String, Set<String>>{};
      for (final row in eraseRows) {
        final after = jsonDecode(row.afterImage!) as Map<String, Object?>;
        expect(after['deleted_at'], isNotNull, reason: row.entityTable);
        tombstonedByTable
            .putIfAbsent(row.entityTable, () => <String>{})
            .add(row.entityId);
      }
      for (final table in TrainingRepositories.eraseTableNames) {
        final erased =
            liveBefore[table]!.difference(await _liveIds(database, table));
        expect(
          tombstonedByTable[table] ?? const <String>{},
          erased,
          reason: '$table erased rows should each have a tombstone',
        );
      }
    });

    test('undoing the erase batch restores the erased rows', () async {
      await _seedEveryDomain(repositories);
      final liveBefore = <String, Set<String>>{
        for (final table in TrainingRepositories.eraseTableNames)
          table: await _liveIds(database, table),
      };
      await repositories.eraseAllData();
      final batchId = (await (database.select(database.activityLog)
                ..where((row) => row.actor.equals('settings')))
              .get())
          .first
          .batchId;

      final result = await repositories.activityLog.undoBatch(batchId);

      expect(result.conflicts, isEmpty);
      for (final table in TrainingRepositories.eraseTableNames) {
        expect(await _liveIds(database, table), liveBefore[table],
            reason: table);
      }
    });
  });
}

/// Tables erase leaves alone: Settings and integration consents stay, the
/// Activity Log is how the erase is recorded and recovered, and the rest are
/// caches or sync bookkeeping.
const _keptTables = <String>{
  AppDatabase.userSettingsTable,
  AppDatabase.integrationDataClassConsentsTable,
  AppDatabase.activityLogTable,
  AppDatabase.syncStatesTable,
  AppDatabase.deferredSyncChangesTable,
  AppDatabase.quarantinedSyncChangesTable,
  AppDatabase.monitoringSeriesCacheTable,
};

Future<Set<String>> _liveIds(
  AppDatabase database,
  String table, {
  String? where,
  List<Object> variables = const <Object>[],
}) async {
  final rows = await database.customSelect(
    'SELECT id FROM $table WHERE deleted_at IS NULL'
    '${where == null ? '' : ' AND $where'}',
    variables: <Variable<Object>>[
      for (final value in variables) Variable<Object>(value),
    ],
  ).get();
  return rows.map((row) => row.read<String>('id')).toSet();
}

typedef _SeededIds = ({
  String userCompoundId,
  String userMealTypeId,
  String userCategoryId,
  String userFocusId,
  String userPurposeId,
});

/// One live row in every erasable table, next to the bundled seeds (Platform
/// Library, OTC compounds, default meal types) erase must keep.
Future<_SeededIds> _seedEveryDomain(TrainingRepositories repositories) async {
  final database = repositories.database;
  await repositories.catalog.ensurePlatformLibrarySeeded();
  await repositories.protocols.ensureOtcLibrarySeeded();
  await repositories.nutrition.ensureDefaultMealTypes();
  await repositories.accountSettings.save(AccountSettings.defaults);

  final userCategoryId = await repositories.catalog.createCategory(
    const ExerciseCategoryDraft(name: 'Grip'),
  );
  final userFocusId = await repositories.focuses.create('Climbing');
  final userPurposeId = await repositories.protocols.purposes.create('Joints');
  final exerciseId = await repositories.exercises.create(
    ExerciseDraft(
      name: 'Farmer Carry',
      type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
      categoryId: userCategoryId,
    ),
  );
  final workoutId = await repositories.workoutSessions.create(
    WorkoutSessionDraft(
      startedAt: DateTime.utc(2026, 6, 16, 8),
      timezone: 'UTC',
      localDate: const TrainingDayDate(year: 2026, month: 6, day: 16),
    ),
  );
  final workoutExerciseId = await repositories.workoutExercises.create(
    WorkoutExerciseDraft(workoutId: workoutId, exerciseId: exerciseId),
  );
  final setId = await repositories.sets.create(
    LoggedSetDraft(
      workoutId: workoutId,
      exerciseId: exerciseId,
      position: 0,
      isCompleted: true,
      values: LoggedSet.fromValues(const <SetDimensionValue>[
        SetDimensionValue(
          dimension: DimensionId.load,
          entered: '40',
          unit: TrainingUnit.kilogram,
        ),
        SetDimensionValue(
          dimension: DimensionId.reps,
          entered: '10',
          unit: TrainingUnit.repetition,
        ),
      ]),
    ),
  );
  await repositories.restTimers.startForSet(
    (await repositories.sets.getById(setId))!,
    defaultDuration: const Duration(seconds: 90),
    now: DateTime.utc(2026, 6, 16, 8, 5),
  );
  final updatedAt = DateTime.utc(2026, 6, 16, 9);
  await database.into(database.exerciseGroups).insert(
        ExerciseGroupsCompanion.insert(
          id: 'erase-group',
          workoutId: workoutId,
          name: 'Superset',
          colorHex: '#4A8FE0',
          position: 0,
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.exerciseGroupMembers).insert(
        ExerciseGroupMembersCompanion.insert(
          id: 'erase-group-member',
          groupId: 'erase-group',
          workoutExerciseId: workoutExerciseId,
          position: 0,
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.intervalTimers).insert(
        IntervalTimersCompanion.insert(
          id: 'erase-interval-timer',
          workoutId: workoutId,
          startedAt: updatedAt,
          phaseStartedAt: updatedAt,
          deadlineAt: updatedAt.add(const Duration(seconds: 20)),
          updatedAt: updatedAt,
        ),
      );
  await _seedPlanTree(database, exerciseId, workoutId, updatedAt);

  final userMealTypeId = await repositories.nutrition.createMealType(
    const MealTypeDraft(name: 'Second breakfast', sortOrder: 9),
  );
  final quickEntry = await repositories.nutrition.logQuickEntry(
    target: NewMealTarget(
      PendingMeal(
        id: repositories.nutrition.newMealId(),
        startedAt: DateTime(2026, 6, 16, 7),
        mealTypeName: 'Breakfast',
      ),
    ),
    entry: QuickFoodEntryDraft(
      name: 'Oats',
      nutrients: NutrientVector.energyAndMacros(
        energy: NutrientAmount.complete(
          value: 320,
          entered: '320',
          unit: NutrientUnit.kilocalorie,
        ),
        protein: NutrientAmount.complete(
          value: 18,
          entered: '18',
          unit: NutrientUnit.gram,
        ),
        carbohydrate: NutrientAmount.complete(
          value: 42,
          entered: '42',
          unit: NutrientUnit.gram,
        ),
        fat: NutrientAmount.complete(
          value: 7,
          entered: '7',
          unit: NutrientUnit.gram,
        ),
      ),
    ),
  );
  expect(quickEntry.mealId, isNotEmpty);
  await repositories.nutrition.createUserFood(
    UserFoodDraft(
      name: 'Protein bar',
      nutrientsPer100: NutrientVector.energyAndMacros(
        energy: NutrientAmount.complete(
          value: 500,
          entered: '500',
          unit: NutrientUnit.kilocalorie,
        ),
        protein: NutrientAmount.complete(
          value: 40,
          entered: '40',
          unit: NutrientUnit.gram,
        ),
        carbohydrate: NutrientAmount.complete(
          value: 35,
          entered: '35',
          unit: NutrientUnit.gram,
        ),
        fat: NutrientAmount.complete(
          value: 18,
          entered: '18',
          unit: NutrientUnit.gram,
        ),
      ),
      isLiquid: false,
    ),
  );
  await repositories.nutrition.saveNutritionGoal(
    NutritionGoalTarget(
      nutrient: NutrientId.energy,
      value: 2400,
      entered: '2400',
    ),
  );

  final metricId = await repositories.metrics.createMetric(
    const MetricDraft(
      name: 'Body Weight',
      unit: 'kilogram',
      valueShape: MetricValueShape.scalar,
      group: MetricGroup.bodyComposition,
      enabled: true,
      pinned: true,
    ),
  );
  await repositories.metrics.createManualReading(
    ManualMetricReadingDraft.scalar(
      metricId: metricId,
      valueEntered: '82',
      atTime: DateTime.utc(2026, 6, 16, 7),
      source: 'manual',
    ),
  );

  final compound = await repositories.protocols.createCompound(
    CompoundDraft(
      name: 'Creatine',
      defaultUnit: DoseUnit.gram,
      defaultRoute: DoseRoute.oral,
    ),
  );
  final protocol = await repositories.protocols.createProtocol(
    ProtocolDraft(
      name: 'Lean bulk',
      startLocalDate: const ProtocolDayDate(year: 2026, month: 6, day: 1),
      compoundIds: <String>[compound.compoundId],
      schedulesByCompoundId: <String, ScheduleDraft?>{
        compound.compoundId: ScheduleDraft(
          rule: _onceDaily,
          doseAmountValue: 5,
          doseAmountEntered: '5',
          doseUnit: DoseUnit.gram,
          route: DoseRoute.oral,
        ),
      },
      targetOutcomes: const <ProtocolTargetOutcomeDraft>[
        ProtocolTargetOutcomeDraft.performance,
      ],
    ),
  );
  await repositories.protocols.logDose(
    DoseSnapshotDraft(
      compoundId: compound.compoundId,
      compoundName: 'Creatine',
      amountValue: 5,
      amountEntered: '5',
      unit: DoseUnit.gram,
      route: DoseRoute.oral,
      tookAt: DateTime.utc(2026, 6, 16, 8),
    ),
  );
  // A Skip (D8) is authored data like the Dose, so erase clears it too.
  await repositories.protocols.skipPlannedDose(
    ProtocolSkipDraft(
      protocolId: protocol.protocolId,
      compoundId: compound.compoundId,
      localDate: const ProtocolDayDate(year: 2026, month: 6, day: 15),
      plannedLocalTime: '08:00',
    ),
    today: const ProtocolDayDate(year: 2026, month: 6, day: 16),
  );

  return (
    userCompoundId: compound.compoundId,
    userMealTypeId: userMealTypeId,
    userCategoryId: userCategoryId,
    userFocusId: userFocusId,
    userPurposeId: userPurposeId,
  );
}

Future<void> _seedPlanTree(
  AppDatabase database,
  String exerciseId,
  String workoutId,
  DateTime updatedAt,
) async {
  await database.into(database.workoutTemplates).insert(
        WorkoutTemplatesCompanion.insert(
          id: 'erase-template',
          name: 'Push',
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.templateExercises).insert(
        TemplateExercisesCompanion.insert(
          id: 'erase-template-exercise',
          workoutTemplateId: 'erase-template',
          exerciseId: exerciseId,
          position: 0,
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.prescriptions).insert(
        PrescriptionsCompanion.insert(
          id: 'erase-prescription',
          templateExerciseId: 'erase-template-exercise',
          position: 0,
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.templateGroups).insert(
        TemplateGroupsCompanion.insert(
          id: 'erase-template-group',
          workoutTemplateId: 'erase-template',
          name: 'Group',
          colorHex: '#4A8FE0',
          position: 0,
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.templateGroupMembers).insert(
        TemplateGroupMembersCompanion.insert(
          id: 'erase-template-group-member',
          groupId: 'erase-template-group',
          templateExerciseId: 'erase-template-exercise',
          position: 0,
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.planRoutines).insert(
        PlanRoutinesCompanion.insert(
          id: 'erase-routine',
          name: 'Upper/Lower',
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.routineEntries).insert(
        RoutineEntriesCompanion.insert(
          id: 'erase-routine-entry',
          routineId: 'erase-routine',
          workoutTemplateId: 'erase-template',
          position: 0,
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.templateLinks).insert(
        TemplateLinksCompanion.insert(
          id: 'erase-template-link',
          workoutId: workoutId,
          workoutTemplateId: 'erase-template',
          updatedAt: updatedAt,
        ),
      );
}

/// One untimed dose a day: the nearest Schedule Rule to "once daily".
final _onceDaily = UntimedScheduleRule(
  days: const DailyScheduleDays(),
  count: 1,
);
