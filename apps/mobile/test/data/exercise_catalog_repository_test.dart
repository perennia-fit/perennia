import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/platform_exercise_seed.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/analytics/repositories/exercise_overview_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  group('exercise catalog repository', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(
        database,
        platformSeedSource: _FakePlatformExerciseSeedSource(_fakeSeed),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('bundled platform seed asset is readable offline', () async {
      final seed = await AssetPlatformExerciseSeedSource().load();

      expect(seed.metadata.sourceName, contains('wger'));
      expect(seed.metadata.sourceUrl, 'https://github.com/wger-project/wger');
      expect(seed.metadata.sourceCommit, isNotEmpty);
      expect(seed.metadata.licenseSummary, contains('CC-BY-SA'));
      expect(seed.metadata.licenseSummary, contains('CC-BY-SA 4.0'));
      expect(seed.metadata.sourceName, contains('Workout.cool'));
      expect(seed.metadata.licenseSummary, contains('Workout.cool'));
      expect(seed.metadata.licenseSummary, contains('MIT'));
      expect(seed.metadata.licenseSummary, contains('provenance'));
      expect(seed.exercises, hasLength(greaterThan(1700)));
      final categoriesById = <String, SeedExerciseCategory>{
        for (final category in seed.categories) category.id: category,
      };
      expect(seed.categories.map((category) => category.name),
          contains('Strength'));
      expect(seed.categories.map((category) => category.name),
          containsAll(<String>['Chest', 'Back', 'Legs', 'Core']));
      expect(seed.exercises.map((exercise) => exercise.name),
          contains('Barbell Squat'));
      expect(
          seed.exercises.map((exercise) => exercise.name),
          containsAll(<String>[
            'Biceps Curls With Barbell',
            'Walking',
            'Lying Hip Abduction with Band',
            'Facepulls',
          ]));
      expect(
        seed.exercises.map((exercise) => exercise.name.toLowerCase()).toSet(),
        hasLength(seed.exercises.length),
      );
      expect(seed.exercises.map((exercise) => exercise.id),
          everyElement(_isUuidV7));
      expect(seed.redirects, isNotEmpty);
      expect(seed.redirects.map((redirect) => redirect.fromExerciseId),
          everyElement(_isUuidV7));
      expect(seed.redirects.map((redirect) => redirect.toExerciseId),
          everyElement(_isUuidV7));
      final exerciseIds = seed.exercises.map((exercise) => exercise.id).toSet();
      expect(
        seed.redirects.map((redirect) => redirect.toExerciseId),
        everyElement(isIn(exerciseIds)),
      );
      expect(
        seed.exercises.map((exercise) => exercise.notes).whereType<String>(),
        everyElement(isNot(contains('Adapted from the wger'))),
      );
      expect(
        seed.exercises.map((exercise) => exercise.notes).whereType<String>(),
        everyElement(isNot(startsWith('Equipment:'))),
      );
      final seedJson = _readBundledSeedJson();
      expect(seedJson, isNot(contains('fullVideoUrl')));
      expect(seedJson, isNot(contains('fullVideoImageUrl')));
      expect(seedJson, isNot(contains('youtube')));
      expect(seedJson, contains('"source_attribution"'));
      expect(seedJson, contains('"exercise_data_provenance"'));
      expect(seedJson, contains('"short_name": "CC-BY-SA 4"'));
      final seedLicense = _readBundledSeedLicense();
      expect(seedLicense, contains('SPDX-License-Identifier: CC-BY-SA-4.0'));
      expect(seedLicense, contains('Changes were made by Perennia'));
      expect(seedLicense, contains('wger commit:'));
      expect(
        seed.exercises
            .singleWhere((exercise) => exercise.name == 'Bench Press')
            .equipment,
        containsAll(<ExerciseEquipment>[
          ExerciseEquipment.barbell,
          ExerciseEquipment.bench,
        ]),
      );
      expect(
        seed.exercises
            .singleWhere(
              (exercise) => exercise.name == 'Biceps Curls With Barbell',
            )
            .equipment,
        contains(ExerciseEquipment.barbell),
      );
      final bandHipAbduction = seed.exercises.singleWhere(
        (exercise) => exercise.name == 'Lying Hip Abduction with Band',
      );
      expect(categoriesById[bandHipAbduction.categoryId]?.name, 'Legs');
      expect(bandHipAbduction.equipment, contains(ExerciseEquipment.band));
      expect(bandHipAbduction.dimensions.toSet(), <DimensionId>{
        DimensionId.reps,
      });
      final facepulls = seed.exercises.singleWhere(
        (exercise) => exercise.name == 'Facepulls',
      );
      expect(categoriesById[facepulls.categoryId]?.name, 'Shoulders');
      expect(
          facepulls.equipment,
          containsAll(<ExerciseEquipment>[
            ExerciseEquipment.cable,
            ExerciseEquipment.rope,
          ]));
      expect(facepulls.dimensions.toSet(), <DimensionId>{
        DimensionId.load,
        DimensionId.reps,
      });
      final allEquipmentIds = seed.exercises
          .expand((exercise) => exercise.equipment)
          .map((equipment) => equipment.id)
          .toSet();
      expect(allEquipmentIds, isNot(contains('car')));
      expect(allEquipmentIds, isNot(contains('chain')));
      expect(allEquipmentIds, isNot(contains('desk')));
      expect(
        seed.exercises
            .singleWhere((exercise) => exercise.name == 'Strength Training')
            .dimensions
            .toSet(),
        <DimensionId>{DimensionId.load, DimensionId.reps},
      );
      expect(
        seed.exercises
            .singleWhere((exercise) => exercise.name == 'Mobility Flow')
            .dimensions,
        isEmpty,
      );
    });

    test('bundled platform seed includes canonical cardio taxonomy', () async {
      final seed = await AssetPlatformExerciseSeedSource().load();
      final categoriesByName = <String, SeedExerciseCategory>{
        for (final category in seed.categories) category.name: category,
      };
      final exercisesByName = <String, SeedExercise>{
        for (final exercise in seed.exercises) exercise.name: exercise,
      };

      const categoryIds = <String, String>{
        'Running': '01910000-0000-7000-8000-000000000004',
        'Cycling': '01910000-0000-7000-8000-000000000005',
        'Swimming': '01910000-0000-7000-8000-000000000006',
      };
      const taxonomy = <String, Map<String, String>>{
        'Running': <String, String>{
          'Running': '01910000-0000-7000-8000-000000000109',
          'Road Running': '01910000-0000-7000-8000-000000000110',
          'Trail Running': '01910000-0000-7000-8000-000000000111',
          'Treadmill Running': '01910000-0000-7000-8000-000000000112',
          'Track Running': '01910000-0000-7000-8000-000000000113',
        },
        'Cycling': <String, String>{
          'Cycling': '01910000-0000-7000-8000-000000000114',
          'Indoor Cycling': '01910000-0000-7000-8000-000000000115',
          'Outdoor Cycling': '01910000-0000-7000-8000-000000000116',
        },
        'Swimming': <String, String>{
          'Swimming': '01910000-0000-7000-8000-000000000117',
          'Pool Swim': '01910000-0000-7000-8000-000000000118',
          'Open-Water Swim': '01910000-0000-7000-8000-000000000119',
        },
      };

      for (final entry in taxonomy.entries) {
        final category = categoriesByName[entry.key];
        expect(category, isNotNull, reason: '${entry.key} category missing.');
        expect(category!.id, categoryIds[entry.key]);

        for (final exerciseEntry in entry.value.entries) {
          final exerciseName = exerciseEntry.key;
          final exercise = exercisesByName[exerciseName];
          expect(exercise, isNotNull, reason: '$exerciseName missing.');
          expect(exercise!.id, exerciseEntry.value);
          expect(exercise.categoryId, category.id);
          expect(
            exercise.dimensions.toSet(),
            <DimensionId>{DimensionId.distance, DimensionId.duration},
          );
        }
      }
    });

    test('seeds platform exercises exactly once with catalog metadata',
        () async {
      await repositories.catalog.ensurePlatformLibrarySeeded();
      await repositories.catalog.ensurePlatformLibrarySeeded();

      final rows = await database.select(database.exercises).get();
      final columnsByTable = await database.describeSchema();

      expect(rows, hasLength(3));
      expect(
        columnsByTable[AppDatabase.exercisesTable],
        containsAll(<String>[
          'library_origin',
          'category_id',
          'notes',
          'dimension_ids',
          'equipment_ids',
          'is_favorite',
          'load_mode',
          'record_profile',
          'updated_at',
          'deleted_at',
        ]),
      );
      expect(
        rows.map((row) => row.libraryOrigin).toSet(),
        <String>{ExerciseLibraryOrigin.platform.name},
      );
      expect(rows.map((row) => row.id), everyElement(_isUuidV7));
      expect(
        rows.singleWhere((row) => row.name == 'Mobility Flow').dimensionIds,
        '[]',
      );
      expect(
        rows.singleWhere((row) => row.name == 'Barbell Squat').equipmentIds,
        '["barbell"]',
      );
      expect(rows.map((row) => row.isFavorite), everyElement(isFalse));
    });

    test('canonical cardio taxonomy round-trips as Categories and Exercises',
        () async {
      repositories = TrainingRepositories(database);

      await repositories.catalog.ensurePlatformLibrarySeeded();

      final sections = await repositories.catalog.listMergedCatalog();
      final running = sections.singleWhere(
        (section) => section.title == 'Running',
      );
      final cycling = sections.singleWhere(
        (section) => section.title == 'Cycling',
      );
      final swimming = sections.singleWhere(
        (section) => section.title == 'Swimming',
      );

      expect(running.category?.id, '01910000-0000-7000-8000-000000000004');
      expect(cycling.category?.id, '01910000-0000-7000-8000-000000000005');
      expect(swimming.category?.id, '01910000-0000-7000-8000-000000000006');
      expect(
        running.exercises.map((exercise) => exercise.name),
        containsAll(<String>[
          'Running',
          'Road Running',
          'Trail Running',
          'Treadmill Running',
          'Track Running',
        ]),
      );
      expect(
        cycling.exercises.map((exercise) => exercise.name),
        containsAll(<String>[
          'Cycling',
          'Indoor Cycling',
          'Outdoor Cycling',
        ]),
      );
      expect(
        swimming.exercises.map((exercise) => exercise.name),
        containsAll(<String>[
          'Swimming',
          'Pool Swim',
          'Open-Water Swim',
        ]),
      );

      final trailRunning = running.exercises.singleWhere(
        (exercise) => exercise.name == 'Trail Running',
      );
      expect(trailRunning.id, '01910000-0000-7000-8000-000000000111');
      expect(trailRunning.origin, ExerciseLibraryOrigin.platform);
      expect(trailRunning.recordProfile, RecordProfile.fastestPace);
      expect(
        trailRunning.type.dimensions.toSet(),
        <DimensionId>{DimensionId.distance, DimensionId.duration},
      );

      final overview = await ExerciseOverviewRepository(
        repositories,
      ).getForExercise(trailRunning.id);
      expect(overview?.exercise.id, trailRunning.id);
      expect(overview?.category?.id, running.category?.id);
      expect(overview?.groups, isEmpty);
      expect(overview?.setsById, isEmpty);
    });

    test('reapplying the same bundled seed does not duplicate platform rows',
        () async {
      final seedSource = _CountingPlatformExerciseSeedSource(_fakeSeed);
      repositories = TrainingRepositories(
        database,
        platformSeedSource: seedSource,
      );

      await repositories.catalog.ensurePlatformLibrarySeeded();
      await repositories.catalog.ensurePlatformLibrarySeeded();

      final rows = await database.select(database.exercises).get();

      expect(seedSource.loadCount, 1);
      expect(rows, hasLength(3));
      expect(rows.map((row) => row.id).toSet(), hasLength(3));
    });

    test('reapplying the seed preserves existing platform exercise state',
        () async {
      final seedSource = _CountingPlatformExerciseSeedSource(_fakeSeed);
      repositories = TrainingRepositories(
        database,
        platformSeedSource: seedSource,
      );

      await repositories.catalog.ensurePlatformLibrarySeeded();
      await repositories.exercises.setFavorite(
        '01910000-0000-7000-8000-000000000101',
        isFavorite: true,
        actor: 'tester',
      );
      await repositories.catalog.ensurePlatformLibrarySeeded();

      final squat = await repositories.exercises.getById(
        '01910000-0000-7000-8000-000000000101',
      );

      expect(seedSource.loadCount, 1);
      expect(squat?.origin, ExerciseLibraryOrigin.platform);
      expect(squat?.isFavorite, isTrue);
      expect(squat?.notes, 'A platform strength exercise.');
      expect(squat?.equipment, <ExerciseEquipment>[ExerciseEquipment.barbell]);
      expect(squat?.deletedAt, isNull);
    });

    test('platform redirects archive old ids while preserving lookup rows',
        () async {
      const oldId = '01910000-0000-7000-8000-000000000101';
      const canonicalId = '01910000-0000-7000-8000-000000000102';
      final originalSeed = PlatformExerciseSeed(
        categories: _fakeSeed.categories,
        exercises: _fakeSeed.exercises
            .where((exercise) =>
                exercise.id == oldId || exercise.id == canonicalId)
            .toList(growable: false),
      );
      final cleanedSeed = PlatformExerciseSeed(
        categories: _fakeSeed.categories,
        redirects: const <SeedExerciseRedirect>[
          SeedExerciseRedirect(
            fromExerciseId: oldId,
            toExerciseId: canonicalId,
          ),
        ],
        exercises: _fakeSeed.exercises
            .where((exercise) => exercise.id == canonicalId)
            .toList(growable: false),
      );

      repositories = TrainingRepositories(
        database,
        platformSeedSource: _FakePlatformExerciseSeedSource(originalSeed),
      );
      await repositories.catalog.ensurePlatformLibrarySeeded();
      repositories = TrainingRepositories(
        database,
        platformSeedSource: _FakePlatformExerciseSeedSource(cleanedSeed),
      );
      await repositories.catalog.ensurePlatformLibrarySeeded();

      final oldExercise = await repositories.exercises.getById(oldId);
      final canonicalExercise =
          await repositories.exercises.getById(canonicalId);
      expect(oldExercise?.origin, ExerciseLibraryOrigin.platform);
      expect(oldExercise?.deletedAt, isNotNull);
      expect(canonicalExercise?.deletedAt, isNull);
    });

    test('platform redirects materialize archived aliases on a fresh database',
        () async {
      const oldId = '01910000-0000-7000-8000-000000000101';
      const canonicalId = '01910000-0000-7000-8000-000000000102';
      final cleanedSeed = PlatformExerciseSeed(
        categories: _fakeSeed.categories,
        redirects: const <SeedExerciseRedirect>[
          SeedExerciseRedirect(
            fromExerciseId: oldId,
            toExerciseId: canonicalId,
          ),
        ],
        exercises: _fakeSeed.exercises
            .where((exercise) => exercise.id == canonicalId)
            .toList(growable: false),
      );
      repositories = TrainingRepositories(
        database,
        platformSeedSource: _FakePlatformExerciseSeedSource(cleanedSeed),
      );

      await repositories.catalog.ensurePlatformLibrarySeeded();

      final alias = await repositories.exercises.getById(oldId);
      final activeIds = (await repositories.exercises.listActive())
          .map((exercise) => exercise.id);
      expect(alias?.origin, ExerciseLibraryOrigin.platform);
      expect(alias?.deletedAt, isNotNull);
      expect(activeIds, isNot(contains(oldId)));
      expect(activeIds, contains(canonicalId));
    });

    test('reapplying the seed removes legacy wger attribution exercise notes',
        () async {
      const squatId = '01910000-0000-7000-8000-000000000101';
      final legacySeed = PlatformExerciseSeed(
        categories: _fakeSeed.categories,
        exercises: <SeedExercise>[
          SeedExercise(
            id: squatId,
            name: 'Barbell Squat',
            dimensions: <DimensionId>[DimensionId.load, DimensionId.reps],
            categoryId: '01910000-0000-7000-8000-000000000001',
            equipment: <ExerciseEquipment>[ExerciseEquipment.barbell],
            notes:
                'Adapted from the wger exercise database. Equipment: Barbell.',
            updatedAt: DateTime.utc(2026),
          ),
        ],
      );
      final cleanedSeed = PlatformExerciseSeed(
        categories: _fakeSeed.categories,
        exercises: <SeedExercise>[
          SeedExercise(
            id: squatId,
            name: 'Barbell Squat',
            dimensions: <DimensionId>[DimensionId.load, DimensionId.reps],
            categoryId: '01910000-0000-7000-8000-000000000001',
            equipment: <ExerciseEquipment>[ExerciseEquipment.barbell],
            notes: null,
            updatedAt: DateTime.utc(2026),
          ),
        ],
      );
      repositories = TrainingRepositories(
        database,
        platformSeedSource: _QueuedPlatformExerciseSeedSource(
          <PlatformExerciseSeed>[legacySeed, cleanedSeed],
        ),
      );

      await repositories.catalog.ensurePlatformLibrarySeeded();
      final userCopyId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Legacy User Copy',
          type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
          notes:
              'Adapted from the wger exercise database. Equipment: Dumbbell.',
        ),
      );
      await repositories.catalog.ensurePlatformLibrarySeeded();

      final squat = await repositories.exercises.getById(squatId);
      final userCopy = await repositories.exercises.getById(userCopyId);

      expect(squat?.origin, ExerciseLibraryOrigin.platform);
      expect(squat?.equipment, <ExerciseEquipment>[ExerciseEquipment.barbell]);
      expect(squat?.notes, isNull);
      expect(userCopy?.origin, ExerciseLibraryOrigin.user);
      expect(userCopy?.equipment, isEmpty);
      expect(
        userCopy?.notes,
        'Adapted from the wger exercise database. Equipment: Dumbbell.',
      );
    });

    test('backfills newly-added platform seed rows by stable id', () async {
      final firstSeedSource = _CountingPlatformExerciseSeedSource(_fakeSeed);
      repositories = TrainingRepositories(
        database,
        platformSeedSource: firstSeedSource,
      );
      await repositories.catalog.ensurePlatformLibrarySeeded();

      final upgradedSeedSource = _CountingPlatformExerciseSeedSource(
        _fakeSeedWithRunning,
      );
      repositories = TrainingRepositories(
        database,
        platformSeedSource: upgradedSeedSource,
      );

      await repositories.catalog.ensurePlatformLibrarySeeded();
      await repositories.catalog.ensurePlatformLibrarySeeded();

      final exercises = await database.select(database.exercises).get();
      final categories =
          await database.select(database.exerciseCategories).get();

      expect(firstSeedSource.loadCount, 1);
      expect(upgradedSeedSource.loadCount, 1);
      expect(exercises, hasLength(4));
      expect(categories, hasLength(3));
      expect(
        exercises.singleWhere((row) => row.name == 'Running').id,
        '01910000-0000-7000-8000-000000000201',
      );
      expect(
        exercises.singleWhere((row) => row.name == 'Running').dimensionIds,
        '["distance","duration"]',
      );
    });

    test('migrates v1 databases to current schema and backfills user fields',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('perennia_v1_');
      addTearDown(() => directory.delete(recursive: true));
      final databaseFile = File('${directory.path}/migration.sqlite');
      const exerciseId = '01910000-0000-7000-8000-000000000901';
      const workoutId = '01910000-0000-7000-8000-000000000902';
      final updatedAt = DateTime.utc(2026, 6, 14, 12);
      final workoutStartedAt = DateTime.utc(2026, 6, 14, 12);

      _createV1Database(
        databaseFile,
        exerciseId: exerciseId,
        workoutId: workoutId,
        workoutStartedAt: workoutStartedAt,
        updatedAt: updatedAt,
      );

      final migratedDatabase = AppDatabase.openFile(databaseFile);
      addTearDown(migratedDatabase.close);

      final columnsByTable = await migratedDatabase.describeSchema();
      final exercises = await migratedDatabase
          .select(
            migratedDatabase.exercises,
          )
          .get();
      final workouts = await migratedDatabase
          .select(
            migratedDatabase.workoutSessions,
          )
          .get();
      final version = await migratedDatabase
          .customSelect(
            'PRAGMA user_version',
          )
          .getSingle();

      expect(version.read<int>('user_version'), migratedDatabase.schemaVersion);
      expect(
        columnsByTable[AppDatabase.exerciseCategoriesTable],
        containsAll(<String>[
          'id',
          'name',
          'sort_order',
          'color_hex',
          'updated_at',
          'deleted_at',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.exercisesTable],
        containsAll(<String>[
          'library_origin',
          'default_load_unit',
          'is_favorite',
          'load_mode',
          'record_profile',
          'is_unilateral',
          'uses_rpe',
          'category_id',
          'equipment_ids',
          'notes',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.workoutSessionsTable],
        contains('local_date'),
      );
      expect(
        columnsByTable[AppDatabase.workoutExercisesTable],
        containsAll(<String>['workout_id', 'exercise_id', 'position']),
      );
      expect(
        columnsByTable[AppDatabase.exerciseGroupsTable],
        containsAll(<String>['workout_id', 'name', 'color_hex', 'position']),
      );
      expect(
        columnsByTable[AppDatabase.exerciseGroupMembersTable],
        containsAll(<String>['group_id', 'workout_exercise_id', 'position']),
      );
      for (final retiredTable in <String>{
        'routines',
        'routine_days',
        'routine_exercises',
        'predefined_sets',
        'routine_exercise_groups',
        'routine_exercise_group_members',
      }) {
        expect(columnsByTable, isNot(contains(retiredTable)));
      }
      expect(
        columnsByTable[AppDatabase.loggedSetsTable],
        containsAll(<String>[
          'position',
          'planned_rest_after',
          'performed_at',
          'is_completed',
          'comment',
          'side',
          'rpe',
          'sync_device_id',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.restTimersTable],
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
      expect(
        columnsByTable[AppDatabase.syncStatesTable],
        containsAll(<String>['id', 'pull_cursor', 'updated_at']),
      );
      expect(exercises, hasLength(1));
      expect(exercises.single.id, exerciseId);
      expect(exercises.single.name, 'Existing User Exercise');
      expect(exercises.single.dimensionIds, '["load","reps"]');
      expect(exercises.single.libraryOrigin, ExerciseLibraryOrigin.user.name);
      expect(exercises.single.defaultLoadUnit, TrainingUnit.kilogram.name);
      expect(exercises.single.isFavorite, isFalse);
      expect(exercises.single.isUnilateral, isFalse);
      expect(exercises.single.usesRpe, isFalse);
      expect(exercises.single.loadMode, ExerciseLoadMode.added.name);
      expect(exercises.single.recordProfile, RecordProfile.repMax.name);
      expect(exercises.single.categoryId, isNull);
      expect(exercises.single.notes, isNull);
      expect(exercises.single.updatedAt.toUtc(), updatedAt);
      expect(workouts, hasLength(1));
      expect(workouts.single.id, workoutId);
      expect(workouts.single.startedAt.toUtc(), workoutStartedAt);
      expect(workouts.single.localDate, '2026-06-14');
      expect(workouts.single.localDate, isNot('1970-01-01'));
    });

    test('migrates v13 core data while dropping the retired routine tree',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('perennia_v13_');
      addTearDown(() => directory.delete(recursive: true));
      final databaseFile = File('${directory.path}/migration.sqlite');
      const exerciseId = '01910000-0000-7000-8000-000000000911';
      const routineId = '01910000-0000-7000-8000-000000000912';
      const routineDayId = '01910000-0000-7000-8000-000000000913';
      const routineExerciseId = '01910000-0000-7000-8000-000000000914';
      const predefinedSetId = '01910000-0000-7000-8000-000000000915';
      final updatedAt = DateTime.utc(2026, 6, 15, 12);

      _createV13Database(
        databaseFile,
        exerciseId: exerciseId,
        routineId: routineId,
        routineDayId: routineDayId,
        routineExerciseId: routineExerciseId,
        predefinedSetId: predefinedSetId,
        updatedAt: updatedAt,
      );

      final migratedDatabase = AppDatabase.openFile(databaseFile);
      addTearDown(migratedDatabase.close);

      final columnsByTable = await migratedDatabase.describeSchema();
      final exercise = await (migratedDatabase.select(
        migratedDatabase.exercises,
      )..where((row) => row.id.equals(exerciseId)))
          .getSingle();
      final version = await migratedDatabase
          .customSelect(
            'PRAGMA user_version',
          )
          .getSingle();

      expect(version.read<int>('user_version'), migratedDatabase.schemaVersion);
      expect(exercise.equipmentIds, '[]');
      expect(exercise.notes, 'Equipment: Dumbbell, Incline bench.');
      for (final retiredTable in <String>{
        'routines',
        'routine_days',
        'routine_exercises',
        'predefined_sets',
        'routine_exercise_groups',
        'routine_exercise_group_members',
      }) {
        expect(columnsByTable, isNot(contains(retiredTable)));
      }
      expect(
        columnsByTable[AppDatabase.loggedSetsTable],
        containsAll(<String>['planned_rest_after', 'sync_device_id']),
      );
      expect(
        columnsByTable[AppDatabase.restTimersTable],
        containsAll(<String>[
          'workout_id',
          'source_set_id',
          'deadline_at',
          'status',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.intervalTimersTable],
        containsAll(<String>[
          'workout_id',
          'deadline_at',
          'current_step_index',
          'phase',
          'status',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.intervalTimersTable],
        isNot(contains('routine_day_id')),
      );
      expect(
        columnsByTable[AppDatabase.syncStatesTable],
        containsAll(<String>['id', 'pull_cursor', 'updated_at']),
      );
    });

    test('migrates v19 sync state rows to current health columns', () async {
      final directory =
          await Directory.systemTemp.createTemp('perennia_v19_');
      addTearDown(() => directory.delete(recursive: true));
      final databaseFile = File('${directory.path}/migration.sqlite');
      const syncStateId = 'sync-state';
      final updatedAt = DateTime.utc(2026, 6, 22, 12);

      _createV19Database(
        databaseFile,
        syncStateId: syncStateId,
        updatedAt: updatedAt,
      );

      final migratedDatabase = AppDatabase.openFile(databaseFile);
      addTearDown(migratedDatabase.close);

      final columnsByTable = await migratedDatabase.describeSchema();
      final syncState = await migratedDatabase
          .select(migratedDatabase.syncStates)
          .getSingle();
      final version = await migratedDatabase
          .customSelect(
            'PRAGMA user_version',
          )
          .getSingle();

      expect(version.read<int>('user_version'), migratedDatabase.schemaVersion);
      expect(
        columnsByTable[AppDatabase.syncStatesTable],
        containsAll(<String>[
          'sync_status',
          'last_successful_sync_at',
          'first_failure_at',
          'last_failure_at',
          'last_failure_message',
        ]),
      );
      expect(syncState.id, syncStateId);
      expect(syncState.pullCursor, 'cursor-v19');
      expect(syncState.syncStatus, 'idle');
      expect(syncState.lastSuccessfulSyncAt, isNull);
      expect(syncState.firstFailureAt, isNull);
      expect(syncState.lastFailureAt, isNull);
      expect(syncState.lastFailureMessage, isNull);
      expect(syncState.updatedAt.toUtc(), updatedAt);
    });

    test('merged catalog groups by category and shadows platform by user name',
        () async {
      await repositories.catalog.ensurePlatformLibrarySeeded();
      final userExerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'barbell squat',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
      );

      final sections = await repositories.catalog.listMergedCatalog();
      final exercises = sections
          .expand((section) => section.exercises)
          .toList(growable: false);

      expect(sections.map((section) => section.title), <String>[
        'Strength',
        'Mobility',
        'Uncategorized',
      ]);
      expect(
        exercises.where(
            (exercise) => exercise.name.toLowerCase() == 'barbell squat'),
        hasLength(1),
      );
      final shadowingExercise = exercises.singleWhere(
        (exercise) => exercise.id == userExerciseId,
      );
      expect(shadowingExercise.origin, ExerciseLibraryOrigin.user);
      expect(shadowingExercise.isReadOnly, isFalse);
    });

    test('platform rows are read-only through user-facing exercise writes',
        () async {
      await repositories.catalog.ensurePlatformLibrarySeeded();
      final platformExercise = (await repositories.catalog.listMergedCatalog())
          .expand((section) => section.exercises)
          .singleWhere((exercise) => exercise.name == 'Barbell Squat');

      expect(
        () => repositories.exercises.rename(
          platformExercise.id,
          name: 'Edited Squat',
        ),
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => repositories.exercises.softDelete(platformExercise.id),
        throwsA(isA<UnsupportedError>()),
      );

      final stillSeeded = await repositories.catalog.listMergedCatalog();
      expect(
        stillSeeded
            .expand((section) => section.exercises)
            .map((exercise) => exercise.name),
        contains('Barbell Squat'),
      );
    });

    test('customizes platform exercises as shadowing editable user copies',
        () async {
      await repositories.catalog.ensurePlatformLibrarySeeded();
      final platformExercise = (await repositories.catalog.listMergedCatalog())
          .expand((section) => section.exercises)
          .singleWhere((exercise) => exercise.name == 'Barbell Squat');

      final userCopyId = await repositories.exercises.customizePlatformExercise(
        platformExercise.id,
        actor: 'tester',
      );

      final userCopy = await repositories.exercises.getById(userCopyId);
      final sections = await repositories.catalog.listMergedCatalog();
      final visibleExercises = sections
          .where((section) => !section.isVirtual)
          .expand((section) => section.exercises)
          .toList(growable: false);
      final visibleSquat = visibleExercises.singleWhere(
        (exercise) => exercise.name.toLowerCase() == 'barbell squat',
      );
      final log = (await repositories.activityLog.listEntries()).lastWhere(
        (entry) =>
            entry.actor == 'tester' &&
            entry.entityTable == AppDatabase.exercisesTable &&
            entry.entityId == userCopyId,
      );

      expect(userCopy, isNotNull);
      expect(userCopy?.origin, ExerciseLibraryOrigin.user);
      expect(userCopy?.name, platformExercise.name);
      expect(userCopy?.type.dimensions, platformExercise.type.dimensions);
      expect(userCopy?.defaultLoadUnit, platformExercise.defaultLoadUnit);
      expect(userCopy?.loadMode, platformExercise.loadMode);
      expect(userCopy?.recordProfile, platformExercise.recordProfile);
      expect(userCopy?.categoryId, platformExercise.categoryId);
      expect(visibleSquat.id, userCopyId);
      expect(visibleSquat.isReadOnly, isFalse);
      expect(visibleSquat.shadowsPlatformExercise, isTrue);
      expect(log.beforeImage, isNull);
      expect(
          log.afterImage?['library_origin'], ExerciseLibraryOrigin.user.name);
      expect(log.afterImage?['name'], platformExercise.name);
    });

    test('restore platform version archives the shadowing user copy', () async {
      await repositories.catalog.ensurePlatformLibrarySeeded();
      final platformExercise = (await repositories.catalog.listMergedCatalog())
          .expand((section) => section.exercises)
          .singleWhere((exercise) => exercise.name == 'Barbell Squat');
      final userCopyId = await repositories.exercises.customizePlatformExercise(
        platformExercise.id,
        actor: 'customize',
      );

      await repositories.exercises.restorePlatformVersion(
        userCopyId,
        actor: 'tester',
      );

      final archivedCopy = await repositories.exercises.getById(userCopyId);
      final sections = await repositories.catalog.listMergedCatalog();
      final visibleSquat = sections
          .where((section) => !section.isVirtual)
          .expand((section) => section.exercises)
          .singleWhere((exercise) => exercise.name == 'Barbell Squat');
      final log = (await repositories.activityLog.listEntries()).lastWhere(
        (entry) =>
            entry.actor == 'tester' &&
            entry.entityTable == AppDatabase.exercisesTable &&
            entry.entityId == userCopyId,
      );

      expect(archivedCopy?.deletedAt, isNotNull);
      expect(visibleSquat.id, platformExercise.id);
      expect(visibleSquat.origin, ExerciseLibraryOrigin.platform);
      expect(visibleSquat.shadowsPlatformExercise, isFalse);
      expect(log.beforeImage?['deleted_at'], isNull);
      expect(log.afterImage?['deleted_at'], isNotNull);
    });

    test('shadow badges are computed from active user exercises only',
        () async {
      await repositories.catalog.ensurePlatformLibrarySeeded();
      final platformExercise = (await repositories.catalog.listMergedCatalog())
          .expand((section) => section.exercises)
          .singleWhere((exercise) => exercise.name == 'Barbell Squat');
      final shadowId = await repositories.exercises.customizePlatformExercise(
        platformExercise.id,
      );
      final nonShadowId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Tempo Press',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
      );

      var exercises = (await repositories.catalog.listMergedCatalog())
          .where((section) => !section.isVirtual)
          .expand((section) => section.exercises)
          .toList(growable: false);
      expect(
        exercises
            .singleWhere((exercise) => exercise.id == shadowId)
            .shadowsPlatformExercise,
        isTrue,
      );
      expect(
        exercises
            .singleWhere((exercise) => exercise.id == nonShadowId)
            .shadowsPlatformExercise,
        isFalse,
      );

      await repositories.exercises.softDelete(shadowId);

      exercises = (await repositories.catalog.listMergedCatalog())
          .where((section) => !section.isVirtual)
          .expand((section) => section.exercises)
          .toList(growable: false);
      final visibleSquat = exercises.singleWhere(
        (exercise) => exercise.name == 'Barbell Squat',
      );
      expect(visibleSquat.id, platformExercise.id);
      expect(visibleSquat.shadowsPlatformExercise, isFalse);
      expect(exercises.map((exercise) => exercise.id), contains(nonShadowId));
    });

    test('toggles favorites for platform and user exercises with activity logs',
        () async {
      await repositories.catalog.ensurePlatformLibrarySeeded();
      final platformExercise = (await repositories.catalog.listMergedCatalog())
          .expand((section) => section.exercises)
          .singleWhere((exercise) => exercise.name == 'Barbell Squat');
      final userExerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Tempo Press',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
      );

      await repositories.exercises.setFavorite(
        platformExercise.id,
        isFavorite: true,
        actor: 'tester',
      );
      await repositories.exercises.setFavorite(
        userExerciseId,
        isFavorite: true,
        actor: 'tester',
      );

      final platform = await repositories.exercises.getById(
        platformExercise.id,
      );
      final user = await repositories.exercises.getById(userExerciseId);
      final sections = await repositories.catalog.listMergedCatalog();
      final favorites = sections.singleWhere(
        (section) => section.id == ExerciseCatalogSectionRecord.favoritesId,
      );
      final favoriteNames =
          favorites.exercises.map((exercise) => exercise.name).toList();
      final logs = (await repositories.activityLog.listEntries())
          .where(
            (entry) =>
                entry.actor == 'tester' &&
                entry.entityTable == AppDatabase.exercisesTable,
          )
          .toList(growable: false);

      expect(platform?.isFavorite, isTrue);
      expect(user?.isFavorite, isTrue);
      expect(favorites.isVirtual, isTrue);
      expect(favorites.title, 'Favorites');
      expect(favoriteNames, <String>['Barbell Squat', 'Tempo Press']);
      expect(logs, hasLength(2));
      expect(logs.first.beforeImage?['is_favorite'], isFalse);
      expect(logs.first.afterImage?['is_favorite'], isTrue);
      expect(logs.last.beforeImage?['is_favorite'], isFalse);
      expect(logs.last.afterImage?['is_favorite'], isTrue);

      await repositories.exercises.setFavorite(
        platformExercise.id,
        isFavorite: false,
      );

      expect(
        (await repositories.exercises.getById(platformExercise.id))?.isFavorite,
        isFalse,
      );
    });

    test(
        'favorites section is built after active-only user-before-platform resolution',
        () async {
      await repositories.catalog.ensurePlatformLibrarySeeded();
      final platformSquat = (await repositories.catalog.listMergedCatalog())
          .expand((section) => section.exercises)
          .singleWhere((exercise) => exercise.name == 'Barbell Squat');
      await repositories.exercises.setFavorite(
        platformSquat.id,
        isFavorite: true,
      );
      final shadowingUserId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'barbell squat',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
        ),
      );
      final archivedFavoriteId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Tempo Row',
          type: ExerciseType(<DimensionId>[DimensionId.reps]),
        ),
      );
      await repositories.exercises.setFavorite(
        archivedFavoriteId,
        isFavorite: true,
      );
      await repositories.exercises.softDelete(archivedFavoriteId);

      final sections = await repositories.catalog.listMergedCatalog();
      final visibleIds = sections
          .where((section) => !section.isVirtual)
          .expand((section) => section.exercises)
          .map((exercise) => exercise.id)
          .toSet();

      expect(visibleIds, contains(shadowingUserId));
      expect(visibleIds, isNot(contains(platformSquat.id)));
      expect(visibleIds, isNot(contains(archivedFavoriteId)));
      expect(
        sections.map((section) => section.id),
        isNot(contains(ExerciseCatalogSectionRecord.favoritesId)),
      );
    });

    test('creates user exercises with catalog fields and allows platform name',
        () async {
      await repositories.catalog.ensurePlatformLibrarySeeded();

      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Barbell Squat',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
          categoryId: '01910000-0000-7000-8000-000000000001',
          notes: 'My squat setup.',
          defaultLoadUnit: TrainingUnit.pound,
          loadMode: ExerciseLoadMode.assisted,
          recordProfile: RecordProfile.minAssistancePerRepCount,
        ),
        actor: 'tester',
      );

      final sections = await repositories.catalog.listMergedCatalog();
      final exercises = sections
          .expand((section) => section.exercises)
          .toList(growable: false);
      final exercise = exercises.singleWhere(
        (exercise) => exercise.id == exerciseId,
      );

      expect(exercise.origin, ExerciseLibraryOrigin.user);
      expect(exercise.name, 'Barbell Squat');
      expect(exercise.categoryId, '01910000-0000-7000-8000-000000000001');
      expect(exercise.notes, 'My squat setup.');
      expect(exercise.defaultLoadUnit, TrainingUnit.pound);
      expect(exercise.loadMode, ExerciseLoadMode.assisted);
      expect(exercise.recordProfile, RecordProfile.minAssistancePerRepCount);
      expect(
        exercises.where((exercise) => exercise.name == 'Barbell Squat'),
        hasLength(1),
      );

      final logs = await repositories.activityLog.listEntries();
      final createLog = logs.last;
      expect(createLog.actor, 'tester');
      expect(createLog.entityTable, AppDatabase.exercisesTable);
      expect(createLog.beforeImage, isNull);
      expect(createLog.afterImage?['library_origin'], 'user');
      expect(createLog.afterImage?['default_load_unit'], 'pound');
      expect(createLog.afterImage?['load_mode'], 'assisted');
      expect(
        createLog.afterImage?['record_profile'],
        'minAssistancePerRepCount',
      );
    });

    test('blocks duplicate active user exercise names case-insensitively',
        () async {
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Tempo Row',
          type: ExerciseType(<DimensionId>[DimensionId.reps]),
        ),
      );

      expect(
        () => repositories.exercises.create(
          ExerciseDraft(
            name: ' tempo row ',
            type: ExerciseType(<DimensionId>[DimensionId.reps]),
          ),
        ),
        throwsA(isA<DuplicateExerciseNameException>()),
      );

      await repositories.exercises.softDelete(exerciseId);
      await repositories.exercises.create(
        ExerciseDraft(
          name: 'TEMPO ROW',
          type: ExerciseType(<DimensionId>[DimensionId.reps]),
        ),
      );

      final activeUserRows = (await database.select(database.exercises).get())
          .where(
            (row) =>
                row.libraryOrigin == ExerciseLibraryOrigin.user.name &&
                row.deletedAt == null,
          )
          .toList(growable: false);
      expect(activeUserRows, hasLength(1));
      expect(activeUserRows.single.name, 'TEMPO ROW');
    });

    test('archives and restores user exercises without losing identity',
        () async {
      await repositories.catalog.ensurePlatformLibrarySeeded();
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Tempo Row',
          type: ExerciseType(<DimensionId>[DimensionId.reps]),
          notes: 'Original coaching cue.',
        ),
        actor: 'tester',
      );
      final result = await repositories.logWorkoutWithSet(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 12),
          timezone: 'Australia/Brisbane',
        ),
        LoggedSetDraft(
          exerciseId: exerciseId,
          position: 0,
          values: LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.reps,
                entered: '8',
                unit: TrainingUnit.repetition,
              ),
            ],
          ),
        ),
      );

      await repositories.exercises.softDelete(exerciseId, actor: 'tester');

      final archived = await repositories.exercises.getById(exerciseId);
      expect(archived, isNotNull);
      expect(archived?.deletedAt, isNotNull);
      expect(archived?.notes, 'Original coaching cue.');
      expect(
        (await repositories.exercises.listActive())
            .map((exercise) => exercise.id),
        isNot(contains(exerciseId)),
      );
      expect(
        (await repositories.catalog.listMergedCatalog())
            .expand((section) => section.exercises)
            .map((exercise) => exercise.id),
        isNot(contains(exerciseId)),
      );
      expect(
        (await repositories.sets.getById(result.loggedSetId))?.exerciseId,
        exerciseId,
      );

      final replacementId = await repositories.exercises.create(
        ExerciseDraft(
          name: ' tempo row ',
          type: ExerciseType(<DimensionId>[DimensionId.reps]),
        ),
      );

      // Reusing an archived name is allowed; restoring it requires first
      // clearing the active-name conflict so active user names stay unique.
      expect(
        () => repositories.exercises.restore(exerciseId, actor: 'tester'),
        throwsA(isA<DuplicateExerciseNameException>()),
      );
      expect(
        (await repositories.exercises.getById(exerciseId))?.deletedAt,
        isNotNull,
      );

      await repositories.exercises.rename(
        replacementId,
        name: 'Tempo Row Active',
      );
      await repositories.exercises.restore(exerciseId, actor: 'tester');

      final restored = await repositories.exercises.getById(exerciseId);
      final activeExercises = await repositories.exercises.listActive();
      final activeTempoRows = activeExercises
          .where((exercise) => exercise.name.toLowerCase() == 'tempo row')
          .toList(growable: false);
      final catalogIds = (await repositories.catalog.listMergedCatalog())
          .expand((section) => section.exercises)
          .map((exercise) => exercise.id)
          .toSet();
      final archivedUserExercises =
          await repositories.exercises.listArchivedUser();
      final logs = await repositories.activityLog.listEntries();
      final archiveAndRestoreLogs = logs
          .where(
            (entry) =>
                entry.actor == 'tester' &&
                entry.entityTable == AppDatabase.exercisesTable &&
                entry.entityId == exerciseId &&
                entry.beforeImage != null,
          )
          .toList(growable: false);

      expect(restored?.deletedAt, isNull);
      expect(activeTempoRows.map((exercise) => exercise.id), <String>[
        exerciseId,
      ]);
      expect(
        activeExercises
            .singleWhere((exercise) => exercise.id == replacementId)
            .name,
        'Tempo Row Active',
      );
      expect(catalogIds, contains(exerciseId));
      expect(archivedUserExercises, isEmpty);
      expect(archiveAndRestoreLogs, hasLength(2));
      expect(archiveAndRestoreLogs.first.beforeImage?['deleted_at'], isNull);
      expect(archiveAndRestoreLogs.first.afterImage?['deleted_at'], isNotNull);
      expect(archiveAndRestoreLogs.last.beforeImage?['deleted_at'], isNotNull);
      expect(archiveAndRestoreLogs.last.afterImage?['deleted_at'], isNull);
    });

    test('edits user exercise type without changing historical logged sets',
        () async {
      await repositories.catalog.ensurePlatformLibrarySeeded();
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Loaded Carry',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.distance,
          ]),
          notes: 'Original note.',
          defaultLoadUnit: TrainingUnit.kilogram,
        ),
        actor: 'tester',
      );
      final result = await repositories.logWorkoutWithSet(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 6, 14, 12),
          timezone: 'Australia/Brisbane',
        ),
        LoggedSetDraft(
          exerciseId: exerciseId,
          position: 0,
          values: LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.load,
                entered: '40',
                unit: TrainingUnit.kilogram,
              ),
              SetDimensionValue(
                dimension: DimensionId.distance,
                entered: '20',
                unit: TrainingUnit.kilometer,
              ),
            ],
          ),
        ),
      );

      await repositories.exercises.update(
        exerciseId,
        ExerciseDraft(
          name: 'Loaded Carry',
          type: ExerciseType.empty,
          categoryId: '01910000-0000-7000-8000-000000000002',
          notes: 'Now completion only.',
          defaultLoadUnit: TrainingUnit.pound,
          recordProfile: RecordProfile.completionStreak,
        ),
        actor: 'tester',
      );

      final exercise = (await repositories.exercises.listActive())
          .singleWhere((exercise) => exercise.id == exerciseId);
      final loggedSet = await repositories.sets.getById(result.loggedSetId);

      expect(exercise.type, ExerciseType.empty);
      expect(exercise.notes, 'Now completion only.');
      expect(exercise.defaultLoadUnit, TrainingUnit.pound);
      expect(exercise.loadMode, ExerciseLoadMode.added);
      expect(exercise.recordProfile, RecordProfile.completionStreak);
      expect(loggedSet?.values.load?.entered, '40');
      expect(loggedSet?.values.distance?.entered, '20');

      final logs = await repositories.activityLog.listEntries();
      final editLog = logs.lastWhere(
        (entry) =>
            entry.entityTable == AppDatabase.exercisesTable &&
            entry.entityId == exerciseId,
      );
      expect(editLog.beforeImage?['dimension_ids'], '["load","distance"]');
      expect(editLog.afterImage?['dimension_ids'], '[]');
      expect(editLog.afterImage?['default_load_unit'], 'pound');
      expect(editLog.beforeImage?['record_profile'], 'maxDistance');
      expect(editLog.afterImage?['record_profile'], 'completionStreak');
    });

    test('creates renames recolors and orders categories with activity logs',
        () async {
      await repositories.catalog.ensurePlatformLibrarySeeded();

      final categoryId = await repositories.catalog.createCategory(
        const ExerciseCategoryDraft(
          name: ' Accessories ',
          colorHex: '#0891b2',
        ),
        actor: 'tester',
      );

      var categories = await repositories.catalog.listCategories();
      final created = categories.singleWhere(
        (category) => category.id == categoryId,
      );
      expect(created.name, 'Accessories');
      expect(created.sortOrder, 2);
      expect(created.colorHex, '#0891B2');

      await repositories.catalog.renameCategory(
        categoryId,
        name: 'Pulling',
        actor: 'tester',
      );
      await repositories.catalog.recolorCategory(
        categoryId,
        colorHex: '#e11d48',
        actor: 'tester',
      );
      await repositories.catalog.reorderCategories(
        <String>[
          categoryId,
          '01910000-0000-7000-8000-000000000001',
          '01910000-0000-7000-8000-000000000002',
        ],
        actor: 'tester',
      );

      categories = await repositories.catalog.listCategories();
      expect(
        categories.map((category) => category.name),
        <String>['Pulling', 'Strength', 'Mobility'],
      );
      expect(categories.first.sortOrder, 0);

      await repositories.catalog.alphabetizeCategories(actor: 'tester');
      categories = await repositories.catalog.listCategories();
      expect(
        categories.map((category) => category.name),
        <String>['Mobility', 'Pulling', 'Strength'],
      );

      final logs = (await repositories.activityLog.listEntries())
          .where(
            (entry) =>
                entry.entityTable == AppDatabase.exerciseCategoriesTable &&
                entry.entityId == categoryId,
          )
          .toList(growable: false);
      expect(logs.first.actor, 'tester');
      expect(logs.first.beforeImage, isNull);
      expect(logs.first.afterImage?['name'], 'Accessories');
      expect(
        logs.any(
          (entry) =>
              entry.beforeImage?['name'] == 'Accessories' &&
              entry.afterImage?['name'] == 'Pulling',
        ),
        isTrue,
      );
      expect(
        logs.any((entry) => entry.afterImage?['color_hex'] == '#E11D48'),
        isTrue,
      );
      expect(
        logs.any((entry) => entry.afterImage?['sort_order'] == 0),
        isTrue,
      );
    });

    test('blocks category archive until active member exercises are cleared',
        () async {
      await repositories.catalog.ensurePlatformLibrarySeeded();
      final categoryId = await repositories.catalog.createCategory(
        const ExerciseCategoryDraft(name: 'Core'),
      );
      final deadBugId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Dead Bug',
          type: ExerciseType.empty,
          categoryId: categoryId,
        ),
      );
      final birdDogId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Bird Dog',
          type: ExerciseType.empty,
          categoryId: categoryId,
        ),
      );

      try {
        await repositories.catalog.archiveCategory(categoryId);
        fail('Expected category archive to be blocked.');
      } on CategoryHasActiveExercisesException catch (error) {
        expect(error.categoryId, categoryId);
        expect(error.activeExerciseCount, 2);
      }

      await repositories.exercises.update(
        deadBugId,
        ExerciseDraft(
          name: 'Dead Bug',
          type: ExerciseType.empty,
          categoryId: null,
        ),
      );
      await repositories.exercises.softDelete(birdDogId);
      await repositories.catalog.archiveCategory(categoryId, actor: 'tester');

      final categories = await repositories.catalog.listCategories();
      final activeExercises = await repositories.exercises.listActive();
      expect(categories.map((category) => category.id),
          isNot(contains(categoryId)));
      expect(
        activeExercises
            .singleWhere((exercise) => exercise.id == deadBugId)
            .categoryId,
        isNull,
      );
      expect(
        activeExercises.map((exercise) => exercise.id),
        isNot(contains(birdDogId)),
      );

      final archiveLog =
          (await repositories.activityLog.listEntries()).lastWhere(
        (entry) =>
            entry.entityTable == AppDatabase.exerciseCategoriesTable &&
            entry.entityId == categoryId,
      );
      expect(archiveLog.actor, 'tester');
      expect(archiveLog.beforeImage?['deleted_at'], isNull);
      expect(archiveLog.afterImage?['deleted_at'], isNotNull);
    });
  });
}

final _fakeSeed = PlatformExerciseSeed(
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
      name: 'Mobility',
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
      equipment: <ExerciseEquipment>[ExerciseEquipment.barbell],
      notes: 'A platform strength exercise.',
      updatedAt: DateTime.utc(2026),
    ),
    SeedExercise(
      id: '01910000-0000-7000-8000-000000000102',
      name: 'Pull-Up',
      dimensions: <DimensionId>[DimensionId.reps],
      categoryId: '01910000-0000-7000-8000-000000000001',
      notes: null,
      updatedAt: DateTime.utc(2026),
    ),
    SeedExercise(
      id: '01910000-0000-7000-8000-000000000103',
      name: 'Mobility Flow',
      dimensions: <DimensionId>[],
      categoryId: '01910000-0000-7000-8000-000000000002',
      notes: 'Completion-only movement.',
      updatedAt: DateTime.utc(2026),
    ),
  ],
);

final _fakeSeedWithRunning = PlatformExerciseSeed(
  categories: <SeedExerciseCategory>[
    ..._fakeSeed.categories,
    SeedExerciseCategory(
      id: '01910000-0000-7000-8000-000000000003',
      name: 'Running',
      sortOrder: 2,
      colorHex: '#12A4A6',
      updatedAt: DateTime.utc(2026, 6, 25),
    ),
  ],
  exercises: <SeedExercise>[
    ..._fakeSeed.exercises,
    SeedExercise(
      id: '01910000-0000-7000-8000-000000000201',
      name: 'Running',
      dimensions: <DimensionId>[DimensionId.distance, DimensionId.duration],
      categoryId: '01910000-0000-7000-8000-000000000003',
      notes: 'Generic running fallback for imported activities.',
      updatedAt: DateTime.utc(2026, 6, 25),
    ),
  ],
);

class _FakePlatformExerciseSeedSource implements PlatformExerciseSeedSource {
  const _FakePlatformExerciseSeedSource(this.seed);

  final PlatformExerciseSeed seed;

  @override
  Future<PlatformExerciseSeed> load() async => seed;
}

class _CountingPlatformExerciseSeedSource
    implements PlatformExerciseSeedSource {
  _CountingPlatformExerciseSeedSource(this.seed);

  final PlatformExerciseSeed seed;
  int loadCount = 0;

  @override
  Future<PlatformExerciseSeed> load() async {
    loadCount += 1;
    return seed;
  }
}

class _QueuedPlatformExerciseSeedSource implements PlatformExerciseSeedSource {
  _QueuedPlatformExerciseSeedSource(this.seeds);

  final List<PlatformExerciseSeed> seeds;
  int loadCount = 0;

  @override
  Future<PlatformExerciseSeed> load() async {
    final index = loadCount < seeds.length ? loadCount : seeds.length - 1;
    loadCount += 1;
    return seeds[index];
  }
}

void _createV1Database(
  File file, {
  required String exerciseId,
  required String workoutId,
  required DateTime workoutStartedAt,
  required DateTime updatedAt,
}) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    database.execute('''
      CREATE TABLE exercises (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        dimension_ids TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE TABLE workout_sessions (
        id TEXT NOT NULL PRIMARY KEY,
        started_at INTEGER NOT NULL,
        timezone TEXT NOT NULL,
        ended_at INTEGER NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE TABLE logged_sets (
        id TEXT NOT NULL PRIMARY KEY,
        workout_id TEXT NOT NULL REFERENCES workout_sessions (id),
        exercise_id TEXT NOT NULL REFERENCES exercises (id),
        position INTEGER NOT NULL,
        load_value REAL NULL,
        load_unit TEXT NULL,
        load_entered TEXT NULL,
        reps_value REAL NULL,
        reps_unit TEXT NULL,
        reps_entered TEXT NULL,
        duration_value REAL NULL,
        duration_unit TEXT NULL,
        duration_entered TEXT NULL,
        distance_value REAL NULL,
        distance_unit TEXT NULL,
        distance_entered TEXT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE INDEX logged_sets_workout_id_index
        ON logged_sets (workout_id);

      CREATE TABLE activity_log (
        id TEXT NOT NULL PRIMARY KEY,
        actor TEXT NOT NULL,
        batch_id TEXT NOT NULL,
        entity_table TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        before_image TEXT NULL,
        after_image TEXT NULL,
        occurred_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE INDEX activity_log_batch_id_index
        ON activity_log (batch_id);

      PRAGMA user_version = 1;
    ''');
    database.execute(
      '''
        INSERT INTO exercises (
          id,
          name,
          dimension_ids,
          updated_at,
          deleted_at
        ) VALUES (?, ?, ?, ?, NULL);
      ''',
      <Object?>[
        exerciseId,
        'Existing User Exercise',
        '["load","reps"]',
        updatedAt.millisecondsSinceEpoch ~/ 1000,
      ],
    );
    database.execute(
      '''
        INSERT INTO workout_sessions (
          id,
          started_at,
          timezone,
          ended_at,
          updated_at,
          deleted_at
        ) VALUES (?, ?, ?, NULL, ?, NULL);
      ''',
      <Object?>[
        workoutId,
        workoutStartedAt.millisecondsSinceEpoch ~/ 1000,
        'Australia/Brisbane',
        updatedAt.millisecondsSinceEpoch ~/ 1000,
      ],
    );
  } finally {
    database.close();
  }
}

void _createV13Database(
  File file, {
  required String exerciseId,
  required String routineId,
  required String routineDayId,
  required String routineExerciseId,
  required String predefinedSetId,
  required DateTime updatedAt,
}) {
  final database = sqlite.sqlite3.open(file.path);
  final timestamp = updatedAt.millisecondsSinceEpoch ~/ 1000;
  try {
    database.execute('''
      CREATE TABLE exercise_categories (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        color_hex TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE TABLE exercises (
        id TEXT NOT NULL PRIMARY KEY,
        library_origin TEXT NOT NULL DEFAULT 'user',
        name TEXT NOT NULL,
        dimension_ids TEXT NOT NULL,
        default_load_unit TEXT NOT NULL DEFAULT 'kilogram',
        load_mode TEXT NOT NULL DEFAULT 'added',
        record_profile TEXT NOT NULL DEFAULT 'repMax',
        is_favorite INTEGER NOT NULL DEFAULT 0,
        is_unilateral INTEGER NOT NULL DEFAULT 0,
        uses_rpe INTEGER NOT NULL DEFAULT 0,
        category_id TEXT NULL REFERENCES exercise_categories (id),
        notes TEXT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE TABLE workout_sessions (
        id TEXT NOT NULL PRIMARY KEY,
        started_at INTEGER NOT NULL,
        timezone TEXT NOT NULL,
        local_date TEXT NOT NULL DEFAULT '1970-01-01',
        ended_at INTEGER NULL,
        comment TEXT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE TABLE workout_exercises (
        id TEXT NOT NULL PRIMARY KEY,
        workout_id TEXT NOT NULL REFERENCES workout_sessions (id),
        exercise_id TEXT NOT NULL REFERENCES exercises (id),
        position INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE INDEX workout_exercises_workout_id_index
        ON workout_exercises (workout_id);

      CREATE TABLE exercise_groups (
        id TEXT NOT NULL PRIMARY KEY,
        workout_id TEXT NOT NULL REFERENCES workout_sessions (id),
        name TEXT NOT NULL,
        color_hex TEXT NOT NULL,
        position INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE INDEX exercise_groups_workout_id_index
        ON exercise_groups (workout_id);

      CREATE TABLE exercise_group_members (
        id TEXT NOT NULL PRIMARY KEY,
        group_id TEXT NOT NULL REFERENCES exercise_groups (id),
        workout_exercise_id TEXT NOT NULL REFERENCES workout_exercises (id),
        position INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE INDEX exercise_group_members_group_id_index
        ON exercise_group_members (group_id);
      CREATE INDEX exercise_group_members_workout_exercise_id_index
        ON exercise_group_members (workout_exercise_id);

      CREATE TABLE routines (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        notes TEXT NULL,
        position INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE INDEX routines_position_index ON routines (position);

      CREATE TABLE routine_days (
        id TEXT NOT NULL PRIMARY KEY,
        routine_id TEXT NOT NULL REFERENCES routines (id),
        name TEXT NOT NULL,
        position INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE INDEX routine_days_routine_id_index
        ON routine_days (routine_id);

      CREATE TABLE routine_exercises (
        id TEXT NOT NULL PRIMARY KEY,
        routine_day_id TEXT NOT NULL REFERENCES routine_days (id),
        exercise_id TEXT NOT NULL REFERENCES exercises (id),
        position INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE INDEX routine_exercises_routine_day_id_index
        ON routine_exercises (routine_day_id);
      CREATE INDEX routine_exercises_exercise_id_index
        ON routine_exercises (exercise_id);

      CREATE TABLE predefined_sets (
        id TEXT NOT NULL PRIMARY KEY,
        routine_exercise_id TEXT NOT NULL REFERENCES routine_exercises (id),
        mode TEXT NOT NULL DEFAULT 'fixed',
        position INTEGER NOT NULL,
        load_value REAL NULL,
        load_unit TEXT NULL,
        load_entered TEXT NULL,
        reps_value REAL NULL,
        reps_unit TEXT NULL,
        reps_entered TEXT NULL,
        duration_value REAL NULL,
        duration_unit TEXT NULL,
        duration_entered TEXT NULL,
        distance_value REAL NULL,
        distance_unit TEXT NULL,
        distance_entered TEXT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE INDEX predefined_sets_routine_exercise_id_index
        ON predefined_sets (routine_exercise_id);

      CREATE TABLE logged_sets (
        id TEXT NOT NULL PRIMARY KEY,
        workout_id TEXT NOT NULL REFERENCES workout_sessions (id),
        exercise_id TEXT NOT NULL REFERENCES exercises (id),
        position INTEGER NOT NULL,
        load_value REAL NULL,
        load_unit TEXT NULL,
        load_entered TEXT NULL,
        reps_value REAL NULL,
        reps_unit TEXT NULL,
        reps_entered TEXT NULL,
        duration_value REAL NULL,
        duration_unit TEXT NULL,
        duration_entered TEXT NULL,
        distance_value REAL NULL,
        distance_unit TEXT NULL,
        distance_entered TEXT NULL,
        comment TEXT NULL,
        side TEXT NULL,
        rpe REAL NULL,
        is_completed INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE INDEX logged_sets_workout_id_index
        ON logged_sets (workout_id);

      CREATE TABLE activity_log (
        id TEXT NOT NULL PRIMARY KEY,
        actor TEXT NOT NULL,
        batch_id TEXT NOT NULL,
        entity_table TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        before_image TEXT NULL,
        after_image TEXT NULL,
        occurred_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE INDEX activity_log_batch_id_index
        ON activity_log (batch_id);

      PRAGMA user_version = 13;
    ''');
    database.execute(
      '''
        INSERT INTO exercises (
          id,
          library_origin,
          name,
          dimension_ids,
          default_load_unit,
          load_mode,
          record_profile,
          is_favorite,
          is_unilateral,
          uses_rpe,
          category_id,
          notes,
          updated_at,
          deleted_at
        ) VALUES (?, 'user', 'Existing Exercise', '["load","reps"]',
            'kilogram', 'added', 'repMax', 0, 0, 0, NULL,
            'Equipment: Dumbbell, Incline bench.', ?, NULL);
      ''',
      <Object?>[exerciseId, timestamp],
    );
    database.execute(
      '''
        INSERT INTO routines (
          id,
          name,
          notes,
          position,
          updated_at,
          deleted_at
        ) VALUES (?, 'Existing Routine', NULL, 0, ?, NULL);
      ''',
      <Object?>[routineId, timestamp],
    );
    database.execute(
      '''
        INSERT INTO routine_days (
          id,
          routine_id,
          name,
          position,
          updated_at,
          deleted_at
        ) VALUES (?, ?, 'Workout A', 0, ?, NULL);
      ''',
      <Object?>[routineDayId, routineId, timestamp],
    );
    database.execute(
      '''
        INSERT INTO routine_exercises (
          id,
          routine_day_id,
          exercise_id,
          position,
          updated_at,
          deleted_at
        ) VALUES (?, ?, ?, 0, ?, NULL);
      ''',
      <Object?>[routineExerciseId, routineDayId, exerciseId, timestamp],
    );
    database.execute(
      '''
        INSERT INTO predefined_sets (
          id,
          routine_exercise_id,
          mode,
          position,
          load_value,
          load_unit,
          load_entered,
          reps_value,
          reps_unit,
          reps_entered,
          duration_value,
          duration_unit,
          duration_entered,
          distance_value,
          distance_unit,
          distance_entered,
          updated_at,
          deleted_at
        ) VALUES (?, ?, 'fixed', 0, 100.0, 'kilogram', '100', 5.0,
            'repetition', '5', NULL, NULL, NULL, NULL, NULL, NULL, ?, NULL);
      ''',
      <Object?>[predefinedSetId, routineExerciseId, timestamp],
    );
  } finally {
    database.close();
  }
}

void _createV19Database(
  File file, {
  required String syncStateId,
  required DateTime updatedAt,
}) {
  final database = sqlite.sqlite3.open(file.path);
  final timestamp = updatedAt.millisecondsSinceEpoch ~/ 1000;
  try {
    database.execute('''
      CREATE TABLE logged_sets (
        id TEXT NOT NULL PRIMARY KEY,
        workout_id TEXT NOT NULL REFERENCES workout_sessions (id),
        exercise_id TEXT NOT NULL REFERENCES exercises (id),
        position INTEGER NOT NULL,
        planned_rest_after INTEGER NULL,
        load_value REAL NULL,
        load_unit TEXT NULL,
        load_entered TEXT NULL,
        reps_value REAL NULL,
        reps_unit TEXT NULL,
        reps_entered TEXT NULL,
        duration_value REAL NULL,
        duration_unit TEXT NULL,
        duration_entered TEXT NULL,
        distance_value REAL NULL,
        distance_unit TEXT NULL,
        distance_entered TEXT NULL,
        comment TEXT NULL,
        side TEXT NULL,
        rpe REAL NULL,
        is_completed INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      );

      CREATE INDEX logged_sets_workout_id_index
        ON logged_sets (workout_id);

      CREATE TABLE sync_states (
        id TEXT NOT NULL PRIMARY KEY,
        pull_cursor TEXT NULL,
        updated_at INTEGER NOT NULL
      );

      PRAGMA user_version = 19;
    ''');
    database.execute(
      '''
        INSERT INTO sync_states (
          id,
          pull_cursor,
          updated_at
        ) VALUES (?, 'cursor-v19', ?);
      ''',
      <Object?>[syncStateId, timestamp],
    );
  } finally {
    database.close();
  }
}

String _readBundledSeedJson() {
  for (final path in <String>[
    'assets/seeds/platform_exercises.json',
    'apps/mobile/assets/seeds/platform_exercises.json',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }

  throw StateError('Bundled platform exercise seed asset was not found.');
}

String _readBundledSeedLicense() {
  for (final path in <String>[
    'assets/seeds/platform_exercises.LICENSE.md',
    'apps/mobile/assets/seeds/platform_exercises.LICENSE.md',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }

  throw StateError('Bundled platform exercise seed license was not found.');
}

Matcher get _isUuidV7 => matches(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ),
    );
