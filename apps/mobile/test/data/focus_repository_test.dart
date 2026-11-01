import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/platform_exercise_seed.dart';
import 'package:perennia/domain/training/training_dimensions.dart';

const _weightsId = '01910000-0000-7000-8000-000000000401';
const _enduranceId = '01910000-0000-7000-8000-000000000402';
const _squatId = '01910000-0000-7000-8000-000000000201';
const _rowId = '01910000-0000-7000-8000-000000000202';

final _seed = PlatformExerciseSeed(
  categories: <SeedExerciseCategory>[
    SeedExerciseCategory(
      id: '01910000-0000-7000-8000-000000000009',
      name: 'Legs',
      sortOrder: 0,
      colorHex: '#5FB05C',
      updatedAt: DateTime.utc(2026, 6, 29),
    ),
  ],
  focuses: <SeedFocus>[
    SeedFocus(
      id: _weightsId,
      name: 'Weights',
      sortOrder: 0,
      updatedAt: DateTime.utc(2026, 10, 24),
    ),
    SeedFocus(
      id: _enduranceId,
      name: 'Endurance',
      sortOrder: 1,
      updatedAt: DateTime.utc(2026, 10, 24),
    ),
  ],
  exercises: <SeedExercise>[
    SeedExercise(
      id: _squatId,
      name: 'Barbell Squat',
      dimensions: const <DimensionId>[DimensionId.load, DimensionId.reps],
      categoryId: '01910000-0000-7000-8000-000000000009',
      focusIds: const <String>[_weightsId],
      notes: null,
      updatedAt: DateTime.utc(2026, 6, 29),
    ),
    SeedExercise(
      id: _rowId,
      name: 'Rowing Machine',
      dimensions: const <DimensionId>[
        DimensionId.distance,
        DimensionId.duration,
      ],
      categoryId: '01910000-0000-7000-8000-000000000009',
      focusIds: const <String>[_enduranceId, _weightsId],
      notes: null,
      updatedAt: DateTime.utc(2026, 6, 29),
    ),
  ],
);

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

  setUp(() async {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(
      database,
      platformSeedSource: _SeedSource(_seed),
    );
    await repositories.catalog.ensurePlatformLibrarySeeded();
  });

  tearDown(() async {
    await database.close();
  });

  test('seeds the starter Focuses once and maps Platform exercises', () async {
    final focuses = await repositories.focuses.listActive();
    expect(focuses.map((focus) => focus.name), <String>['Weights', 'Endurance']);

    final row = await repositories.exercises.getById(_rowId);
    expect(row!.focusIds, <String>[_enduranceId, _weightsId]);

    // A second seed pass writes nothing new.
    final logBefore = await repositories.activityLog.listEntries();
    final reopened = TrainingRepositories(
      database,
      platformSeedSource: _SeedSource(_seed),
    );
    await reopened.catalog.ensurePlatformLibrarySeeded();
    expect(await reopened.activityLog.listEntries(), hasLength(logBefore.length));
  });

  test('backfills Focuses onto Platform rows seeded before they existed',
      () async {
    await (database.update(database.exercises)
          ..where((row) => row.id.equals(_squatId)))
        .write(const ExercisesCompanion(focusIds: Value<String>('[]')));
    final reopened = TrainingRepositories(
      database,
      platformSeedSource: _SeedSource(_seed),
    );

    await reopened.catalog.ensurePlatformLibrarySeeded();

    final squat = await reopened.exercises.getById(_squatId);
    expect(squat!.focusIds, <String>[_weightsId]);
  });

  test('a later seed that remaps a Platform exercise reaches the device',
      () async {
    // As if an earlier seed had mapped the squat to Endurance only.
    await (database.update(database.exercises)
          ..where((row) => row.id.equals(_squatId)))
        .write(
      const ExercisesCompanion(focusIds: Value<String>('["$_enduranceId"]')),
    );
    final reopened = TrainingRepositories(
      database,
      platformSeedSource: _SeedSource(_seed),
    );

    await reopened.catalog.ensurePlatformLibrarySeeded();

    expect((await reopened.exercises.getById(_squatId))!.focusIds, <String>[
      _weightsId,
    ]);
  });

  test('a customization made before Focus existed gets its Focuses once',
      () async {
    // Before the upgrade: Platform rows name no Focus, and the user has a
    // customized copy of the squat, also with none.
    await (database.update(database.exercises)
          ..where((row) => row.libraryOrigin.equals('platform')))
        .write(const ExercisesCompanion(focusIds: Value<String>('[]')));
    final copyId = await repositories.exercises.customizePlatformExercise(_squatId);
    await (database.update(database.exercises)
          ..where((row) => row.id.equals(copyId)))
        .write(const ExercisesCompanion(focusIds: Value<String>('[]')));

    await TrainingRepositories(
      database,
      platformSeedSource: _SeedSource(_seed),
    ).catalog.ensurePlatformLibrarySeeded();
    final filled = await repositories.exercises.getById(copyId);
    expect(filled!.focusIds, <String>[_weightsId]);

    // A user who then clears it keeps that choice on later launches.
    await repositories.exercises.update(
      copyId,
      ExerciseDraft(
        name: filled.name,
        type: filled.type,
        focusIds: const <String>[],
      ),
    );
    await TrainingRepositories(
      database,
      platformSeedSource: _SeedSource(_seed),
    ).catalog.ensurePlatformLibrarySeeded();
    expect((await repositories.exercises.getById(copyId))!.focusIds, isEmpty);
  });

  test('a renamed or archived starter Focus is not reseeded', () async {
    await repositories.focuses.rename(_weightsId, name: 'Lifting');
    await repositories.focuses.archive(_enduranceId);
    final reopened = TrainingRepositories(
      database,
      platformSeedSource: _SeedSource(_seed),
    );

    await reopened.catalog.ensurePlatformLibrarySeeded();

    final active = await reopened.focuses.listActive();
    expect(active.map((focus) => focus.name), <String>['Lifting']);
  });

  test('creates, reorders, and rejects a duplicate name', () async {
    final climbingId = await repositories.focuses.create('  Climbing ');
    await repositories.focuses.reorder(
      <String>[climbingId, _weightsId, _enduranceId],
    );

    final active = await repositories.focuses.listActive();
    expect(
      active.map((focus) => focus.name),
      <String>['Climbing', 'Weights', 'Endurance'],
    );
    await expectLater(
      repositories.focuses.create('climbing'),
      throwsA(isA<DuplicateFocusNameException>()),
    );
  });

  test('a Workout records its Focus and an undo restores the previous one',
      () async {
    final workoutId = await repositories.workoutSessions.create(
      WorkoutSessionDraft(
        startedAt: DateTime.utc(2026, 10, 24, 7),
        timezone: 'Australia/Brisbane',
        focusId: _weightsId,
      ),
    );
    expect(
      (await repositories.workoutSessions.getById(workoutId))!.focusId,
      _weightsId,
    );

    await repositories.workoutSessions.setFocus(
      workoutId,
      focusId: _enduranceId,
      batchId: 'focus-change',
    );
    expect(
      (await repositories.workoutSessions.getById(workoutId))!.focusId,
      _enduranceId,
    );

    await repositories.activityLog.undoBatch('focus-change');
    expect(
      (await repositories.workoutSessions.getById(workoutId))!.focusId,
      _weightsId,
    );
  });

  test('an archived Focus still names the Workouts recorded under it',
      () async {
    final workoutId = await repositories.workoutSessions.create(
      WorkoutSessionDraft(
        startedAt: DateTime.utc(2026, 10, 24, 7),
        timezone: 'UTC',
        focusId: _enduranceId,
      ),
    );

    await repositories.focuses.archive(_enduranceId);

    final all = await repositories.focuses.watchAllById().first;
    expect(all[_enduranceId]!.isArchived, isTrue);
    expect(
      (await repositories.workoutSessions.getById(workoutId))!.focusId,
      _enduranceId,
    );
  });

  test('recent uses come from Workouts under the Focus, newest first',
      () async {
    Future<void> logWorkout(
      DateTime startedAt,
      String? focusId,
      List<String> exerciseIds,
    ) async {
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: startedAt,
          timezone: 'UTC',
          focusId: focusId,
        ),
      );
      for (final exerciseId in exerciseIds) {
        await repositories.workoutExercises.create(
          WorkoutExerciseDraft(workoutId: workoutId, exerciseId: exerciseId),
        );
      }
    }

    await logWorkout(DateTime.utc(2026, 10, 1), _weightsId, <String>[
      _squatId,
      _rowId,
    ]);
    await logWorkout(DateTime.utc(2026, 10, 8), _weightsId, <String>[
      _squatId,
    ]);
    await logWorkout(DateTime.utc(2026, 10, 20), _enduranceId, <String>[
      _rowId,
    ]);
    await logWorkout(DateTime.utc(2026, 10, 22), null, <String>[_rowId]);

    final uses =
        await repositories.focuses.watchRecentExerciseUses(_weightsId).first;

    expect(uses.map((use) => use.exerciseId), <String>[_squatId, _rowId]);
    expect(uses.first.lastPerformedAt, DateTime.utc(2026, 10, 8));
    expect(uses.first.workoutCount, 2);
    expect(uses.last.lastPerformedAt, DateTime.utc(2026, 10, 1));
  });

  test('materializing a template copies its Focus onto the Workout', () async {
    final templateId = await repositories.workoutTemplates.create(
      const WorkoutTemplateDraft(name: 'Leg day', focusId: _weightsId),
    );
    await repositories.workoutTemplates.addExercise(templateId, _squatId);

    final result = await repositories.templateMaterialize.materialize(
      TemplateMaterializeRequest(workoutTemplateId: templateId),
      now: DateTime.utc(2026, 10, 24, 7),
      timezone: 'UTC',
    );

    final workout = await repositories.workoutSessions.getById(
      result.workoutId,
    );
    expect(workout!.focusId, _weightsId);
  });

  test("setting a template's Focus leaves earlier Workouts alone", () async {
    final templateId = await repositories.workoutTemplates.create(
      const WorkoutTemplateDraft(name: 'Leg day', focusId: _weightsId),
    );
    await repositories.workoutTemplates.addExercise(templateId, _squatId);
    final first = await repositories.templateMaterialize.materialize(
      TemplateMaterializeRequest(workoutTemplateId: templateId),
      now: DateTime.utc(2026, 10, 24, 7),
      timezone: 'UTC',
    );

    await repositories.workoutTemplates.setFocus(
      templateId,
      focusId: _enduranceId,
    );

    final template = await repositories.workoutTemplates.getById(templateId);
    expect(template!.focusId, _enduranceId);
    expect(
      (await repositories.workoutSessions.getById(first.workoutId))!.focusId,
      _weightsId,
    );
  });

  test('an image written before Focus existed never clears one', () async {
    final workoutId = await repositories.workoutSessions.create(
      WorkoutSessionDraft(
        startedAt: DateTime.utc(2026, 10, 24, 7),
        timezone: 'UTC',
        focusId: _weightsId,
      ),
    );
    final current = await database.select(database.workoutSessions).getSingle();

    await repositories.activityLog.applyPlanSyncImage(
      entityTable: AppDatabase.workoutSessionsTable,
      image: <String, Object?>{
        'id': workoutId,
        'started_at': current.startedAt.toUtc().toIso8601String(),
        'timezone': 'UTC',
        'local_date': current.localDate,
        'ended_at': null,
        'comment': 'from an older device',
        'updated_at': DateTime.utc(2027).toIso8601String(),
        'deleted_at': null,
      },
      deviceId: 'device-b',
      localDeviceId: 'device-a',
      batchId: 'pulled',
    );

    final after = await repositories.workoutSessions.getById(workoutId);
    expect(after!.comment, 'from an older device');
    expect(after.focusId, _weightsId);
  });

  test('applies a pulled Focus and records it in the Activity Log', () async {
    await repositories.activityLog.applyPlanSyncImage(
      entityTable: AppDatabase.focusesTable,
      image: <String, Object?>{
        'id': '01a16cdc-0000-7000-8000-000000000001',
        'name': 'Climbing',
        'sort_order': 5,
        'updated_at': DateTime.utc(2026, 10, 24, 9).toIso8601String(),
        'deleted_at': null,
      },
      deviceId: 'device-b',
      localDeviceId: 'device-a',
      batchId: 'pulled',
    );

    final active = await repositories.focuses.listActive();
    expect(active.map((focus) => focus.name), contains('Climbing'));
    final entries = await repositories.activityLog.listEntries();
    final pulled = entries.singleWhere(
      (entry) =>
          entry.entityTable == AppDatabase.focusesTable &&
          entry.entityId == '01a16cdc-0000-7000-8000-000000000001',
    );
    expect(pulled.afterImage!['name'], 'Climbing');
  });

  group('recolor', () {
    Future<FocusRecord> focus(String id) async =>
        (await repositories.focuses.watchAllById().first)[id]!;

    Future<List<ActivityLogEntry>> focusEntries() async {
      final entries = await repositories.activityLog.listEntries();
      return entries
          .where((entry) => entry.entityTable == AppDatabase.focusesTable)
          .toList();
    }

    test('stores the normalized color with its Activity Log entry', () async {
      final before = (await focusEntries()).length;

      await repositories.focuses.recolor(_weightsId, colorHex: '#e06c5a');

      expect((await focus(_weightsId)).colorHex, '#E06C5A');
      final entries = await focusEntries();
      expect(entries, hasLength(before + 1));
      final entry = entries.firstWhere(
        (entry) =>
            entry.entityId == _weightsId &&
            entry.afterImage?['color_hex'] == '#E06C5A',
      );
      expect(entry.beforeImage!['color_hex'], isNull);
    });

    test('to the stored color writes nothing', () async {
      await repositories.focuses.recolor(_weightsId, colorHex: '#E06C5A');
      final before = await focusEntries();
      final updatedAt = (await focus(_weightsId)).updatedAt;

      await repositories.focuses.recolor(_weightsId, colorHex: '#e06c5a');

      expect(await focusEntries(), hasLength(before.length));
      expect((await focus(_weightsId)).updatedAt, updatedAt);
    });

    test('rejects anything but #RRGGBB', () async {
      await expectLater(
        repositories.focuses.recolor(_weightsId, colorHex: 'red'),
        throwsArgumentError,
      );
      await expectLater(
        repositories.focuses.recolor(_weightsId, colorHex: '#E06C5'),
        throwsArgumentError,
      );
      expect((await focus(_weightsId)).colorHex, isNull);
    });

    test('works on an archived Focus', () async {
      await repositories.focuses.archive(_enduranceId);

      await repositories.focuses.recolor(_enduranceId, colorHex: '#3FBFB0');

      final archived = await focus(_enduranceId);
      expect(archived.isArchived, isTrue);
      expect(archived.colorHex, '#3FBFB0');
    });

    test('a sync image without color_hex leaves the color', () async {
      await repositories.focuses.recolor(_weightsId, colorHex: '#E06C5A');

      await repositories.activityLog.applyPlanSyncImage(
        entityTable: AppDatabase.focusesTable,
        image: <String, Object?>{
          'id': _weightsId,
          'name': 'Strength',
          'sort_order': 0,
          'updated_at': DateTime.utc(2027).toIso8601String(),
          'deleted_at': null,
        },
        deviceId: 'device-b',
        localDeviceId: 'device-a',
        batchId: 'pulled',
      );

      final after = await focus(_weightsId);
      expect(after.name, 'Strength');
      expect(after.colorHex, '#E06C5A');
    });

    test('a sync image with an explicit null clears it', () async {
      await repositories.focuses.recolor(_weightsId, colorHex: '#E06C5A');

      await repositories.activityLog.applyPlanSyncImage(
        entityTable: AppDatabase.focusesTable,
        image: <String, Object?>{
          'id': _weightsId,
          'name': 'Weights',
          'sort_order': 0,
          'color_hex': null,
          'updated_at': DateTime.utc(2027).toIso8601String(),
          'deleted_at': null,
        },
        deviceId: 'device-b',
        localDeviceId: 'device-a',
        batchId: 'pulled',
      );

      expect((await focus(_weightsId)).colorHex, isNull);
    });

    test('undo of an entry whose images lack color_hex succeeds', () async {
      await repositories.focuses.rename(
        _weightsId,
        name: 'Lifting',
        batchId: 'old-rename',
      );
      // Rewrite the entry as a device without Focus colors wrote it.
      final rows = await (database.select(database.activityLog)
            ..where((row) => row.batchId.equals('old-rename')))
          .get();
      for (final row in rows) {
        String? strip(String? image) {
          if (image == null) {
            return null;
          }
          final decoded = jsonDecode(image) as Map<String, Object?>
            ..remove('color_hex');
          return jsonEncode(decoded);
        }

        await (database.update(database.activityLog)
              ..where((entry) => entry.id.equals(row.id)))
            .write(
          ActivityLogCompanion(
            beforeImage: Value<String?>(strip(row.beforeImage)),
            afterImage: Value<String?>(strip(row.afterImage)),
          ),
        );
      }

      final undo = await repositories.activityLog.undoBatch('old-rename');

      expect(undo.hasConflicts, isFalse);
      final after = await focus(_weightsId);
      expect(after.name, 'Weights');
      expect(after.colorHex, isNull);
    });
  });
}

class _SeedSource implements PlatformExerciseSeedSource {
  const _SeedSource(this.seed);

  final PlatformExerciseSeed seed;

  @override
  Future<PlatformExerciseSeed> load() async => seed;
}
