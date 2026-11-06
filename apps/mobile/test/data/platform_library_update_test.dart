import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/platform_exercise_seed.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/home/repositories/home_repository.dart';

const _strengthId = '01910000-0000-7000-8000-000000000001';
const _coreId = '01910000-0000-7000-8000-000000000002';
const _weightsId = '01910000-0000-7000-8000-000000000401';
const _enduranceId = '01910000-0000-7000-8000-000000000402';
const _squatId = '01910000-0000-7000-8000-000000000101';
const _fullPlankId = '01910000-0000-7000-8000-000000000102';
const _plankId = '01910000-0000-7000-8000-000000000201';
const _sideBendId = '01910000-0000-7000-8000-000000000202';
const _unlistedId = '01910000-0000-7000-8000-000000000301';

final _libraryStamp = DateTime.utc(2026, 1, 1);

/// Carries milliseconds, as 177 retired and 711 live records in the bundled
/// seed do. Drift stores whole seconds, so a row never equals this stamp exactly.
final _recordStamp = DateTime.utc(2026, 3, 1, 12, 0, 0, 500);
final _retiredAt = DateTime.utc(2026, 11, 5);

/// A stamp as the database hands it back.
DateTime _stored(DateTime stamp) => DateTime.fromMillisecondsSinceEpoch(
      stamp.millisecondsSinceEpoch ~/ 1000 * 1000,
      isUtc: true,
    );

final _categories = <SeedExerciseCategory>[
  SeedExerciseCategory(
    id: _strengthId,
    name: 'Strength',
    sortOrder: 0,
    colorHex: '#2F6FED',
    updatedAt: _libraryStamp,
  ),
  SeedExerciseCategory(
    id: _coreId,
    name: 'Core',
    sortOrder: 1,
    colorHex: '#1F9D55',
    updatedAt: _libraryStamp,
  ),
];

SeedExercise _squat({
  String name = 'Barbell Squat',
  String? categoryId = _strengthId,
  String? notes = 'Brace first.',
  List<ExerciseEquipment> equipment = const <ExerciseEquipment>[
    ExerciseEquipment.barbell,
    ExerciseEquipment.plate,
  ],
  List<String> focusIds = const <String>[_weightsId, _enduranceId],
  List<DimensionId> dimensions = const <DimensionId>[
    DimensionId.load,
    DimensionId.reps,
  ],
  DateTime? updatedAt,
}) {
  return SeedExercise(
    id: _squatId,
    name: name,
    dimensions: dimensions,
    categoryId: categoryId,
    equipment: equipment,
    focusIds: focusIds,
    notes: notes,
    updatedAt: updatedAt ?? _libraryStamp,
  );
}

final _fullPlank = SeedExercise(
  id: _fullPlankId,
  name: 'Full Plank',
  dimensions: const <DimensionId>[DimensionId.reps],
  categoryId: _coreId,
  focusIds: const <String>[_weightsId],
  notes: null,
  updatedAt: _recordStamp,
);

/// `Plank` as an older library offered it, before the library merged it.
final _plankInstalled = SeedExercise(
  id: _plankId,
  name: 'Plank (old name)',
  dimensions: const <DimensionId>[DimensionId.reps],
  categoryId: _strengthId,
  focusIds: const <String>[_weightsId],
  notes: 'An older note.',
  updatedAt: _libraryStamp,
);

SeedRetiredExercise _plankRetired({
  List<DimensionId> dimensions = const <DimensionId>[DimensionId.reps],
}) {
  return SeedRetiredExercise(
    id: _plankId,
    name: 'Plank',
    dimensions: dimensions,
    categoryId: _coreId,
    equipment: const <ExerciseEquipment>[ExerciseEquipment.gymMat],
    focusIds: const <String>[_enduranceId],
    notes: 'Hold it.',
    updatedAt: _recordStamp,
    retiredAt: _retiredAt,
  );
}

final _sideBendInstalled = SeedExercise(
  id: _sideBendId,
  name: 'Side Bend',
  dimensions: const <DimensionId>[DimensionId.reps],
  categoryId: _coreId,
  focusIds: const <String>[_weightsId],
  notes: null,
  updatedAt: _libraryStamp,
);

final _sideBendRetired = SeedRetiredExercise(
  id: _sideBendId,
  name: 'Side Bend',
  dimensions: const <DimensionId>[DimensionId.reps],
  categoryId: _coreId,
  focusIds: const <String>[_weightsId],
  notes: null,
  updatedAt: _recordStamp,
  retiredAt: _retiredAt,
);

PlatformExerciseSeed _seed({
  required List<SeedExercise> exercises,
  List<SeedRetiredExercise> retired = const <SeedRetiredExercise>[],
}) {
  return PlatformExerciseSeed(
    categories: _categories,
    exercises: exercises,
    retired: retired,
  );
}

/// The library an installed app first seeded.
PlatformExerciseSeed _installedSeed() {
  return _seed(
    exercises: <SeedExercise>[
      _squat(),
      _fullPlank,
      _plankInstalled,
      _sideBendInstalled,
    ],
  );
}

/// The same library after it merged `Plank` and removed `Side Bend`.
PlatformExerciseSeed _updatedSeed({
  List<DimensionId> plankDimensions = const <DimensionId>[DimensionId.reps],
}) {
  return _seed(
    exercises: <SeedExercise>[_squat(), _fullPlank],
    retired: <SeedRetiredExercise>[
      _plankRetired(dimensions: plankDimensions),
      _sideBendRetired,
    ],
  );
}

class _SeedSource implements PlatformExerciseSeedSource {
  const _SeedSource(this.seed);

  final PlatformExerciseSeed seed;

  @override
  Future<PlatformExerciseSeed> load() async => seed;
}

/// Valid on any test exercise that records reps. A partial Set is valid at this
/// layer for one that also records load.
LoggedSet _repsSet() {
  return LoggedSet.fromValues(const <SetDimensionValue>[
    SetDimensionValue(
      dimension: DimensionId.reps,
      entered: '10',
      unit: TrainingUnit.repetition,
    ),
  ]);
}

void main() {
  // The bundled seed loads from assets.
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

  late AppDatabase database;

  setUp(() {
    database = AppDatabase.inMemory();
  });

  tearDown(() async {
    await database.close();
  });

  /// One launch: the pass is memoized per instance, so a rerun needs a new one.
  Future<TrainingRepositories> launch(
    PlatformExerciseSeed seed, {
    String actor = 'platform_seed',
    AppDatabase? on,
  }) async {
    final repositories = TrainingRepositories(
      on ?? database,
      platformSeedSource: _SeedSource(seed),
    );
    await repositories.catalog.ensurePlatformLibrarySeeded(actor: actor);
    return repositories;
  }

  Future<ExerciseRow> rowOf(String id) {
    return (database.select(database.exercises)
          ..where((row) => row.id.equals(id)))
        .getSingle();
  }

  Future<List<ExerciseRow>> allRows() {
    return (database.select(database.exercises)
          ..orderBy([(row) => OrderingTerm.asc(row.id)]))
        .get();
  }

  Future<List<ActivityLogRow>> logEntries() {
    return (database.select(database.activityLog)
          ..orderBy([(row) => OrderingTerm.asc(row.id)]))
        .get();
  }

  Future<List<ActivityLogRow>> logEntriesFor(String id) async {
    return (await logEntries())
        .where((entry) => entry.entityId == id)
        .toList(growable: false);
  }

  Future<void> setRow(String id, ExercisesCompanion changes) {
    return (database.update(database.exercises)
          ..where((row) => row.id.equals(id)))
        .write(changes);
  }

  Future<String> startWorkout(TrainingRepositories repositories) {
    return repositories.workoutSessions.create(
      WorkoutSessionDraft(
        startedAt: DateTime.utc(2026, 10, 1, 8),
        timezone: 'UTC',
      ),
    );
  }

  /// A Workout with one entry and one Set on [exerciseId].
  Future<({String workoutId, String entryId, String setId})> logSet(
    TrainingRepositories repositories,
    String exerciseId, {
    bool isCompleted = true,
  }) async {
    final workoutId = await startWorkout(repositories);
    final entryId = await repositories.workoutExercises.create(
      WorkoutExerciseDraft(workoutId: workoutId, exerciseId: exerciseId),
    );
    final setId = await repositories.sets.create(
      LoggedSetDraft(
        workoutId: workoutId,
        exerciseId: exerciseId,
        position: 0,
        values: _repsSet(),
        isCompleted: isCompleted,
      ),
    );
    return (workoutId: workoutId, entryId: entryId, setId: setId);
  }

  void expectKept(ExerciseRow row) {
    expect(row.libraryOrigin, ExerciseLibraryOrigin.user.name);
    expect(row.deletedAt, isNull);
    expect(row.name, 'Plank');
    expect(row.dimensionIds, '["reps"]');
    expect(row.categoryId, _coreId);
    expect(row.equipmentIds, '["gymMat"]');
    expect(row.focusIds, '["$_enduranceId"]');
    expect(row.notes, 'Hold it.');
    expect(row.updatedAt.toUtc(), _retiredAt);
  }

  void expectHidden(ExerciseRow row) {
    expect(row.libraryOrigin, ExerciseLibraryOrigin.platform.name);
    expect(row.name, 'Plank');
    expect(row.categoryId, _coreId);
    expect(row.equipmentIds, '["gymMat"]');
    expect(row.focusIds, '["$_enduranceId"]');
    expect(row.notes, 'Hold it.');
    expect(row.updatedAt.toUtc(), _stored(_recordStamp));
    expect(row.deletedAt?.toUtc(), _retiredAt);
  }

  group('an id the seed offers', () {
    test('with no row is inserted with the stated defaults', () async {
      await launch(_installedSeed());
      final logBefore = await logEntries();

      const addedId = '01910000-0000-7000-8000-000000000103';
      await launch(
        _seed(
          exercises: <SeedExercise>[
            ..._installedSeed().exercises,
            SeedExercise(
              id: addedId,
              name: 'Pigeon Pose',
              dimensions: const <DimensionId>[DimensionId.duration],
              categoryId: _coreId,
              equipment: const <ExerciseEquipment>[ExerciseEquipment.gymMat],
              focusIds: const <String>[_enduranceId],
              notes: 'Breathe.',
              updatedAt: _recordStamp,
            ),
          ],
        ),
      );

      final row = await rowOf(addedId);
      expect(row.libraryOrigin, ExerciseLibraryOrigin.platform.name);
      expect(row.name, 'Pigeon Pose');
      expect(row.dimensionIds, '["duration"]');
      expect(row.loadMode, ExerciseLoadMode.added.name);
      expect(row.recordProfile, RecordProfile.maxDuration.name);
      expect(row.defaultLoadUnit, TrainingUnit.kilogram.name);
      expect(row.isUnilateral, isFalse);
      expect(row.usesRpe, isFalse);
      expect(row.isFavorite, isFalse);
      expect(row.categoryId, _coreId);
      expect(row.equipmentIds, '["gymMat"]');
      expect(row.focusIds, '["$_enduranceId"]');
      expect(row.notes, 'Breathe.');
      expect(row.updatedAt.toUtc(), _stored(_recordStamp));
      expect(row.deletedAt, isNull);

      final logAfter = await logEntries();
      expect(logAfter, hasLength(logBefore.length + 1));
      final entry = (await logEntriesFor(addedId)).single;
      expect(entry.beforeImage, isNull);
      expect(jsonDecode(entry.afterImage!)['name'], 'Pigeon Pose');
    });

    test('a rename, category or notes change applies in place (CUJ 1)',
        () async {
      final installed = await launch(_installedSeed());
      await installed.exercises.setFavorite(_squatId, isFavorite: true);
      final logged = await logSet(installed, _squatId);
      final setBefore = await (database.select(database.loggedSets)
            ..where((row) => row.id.equals(logged.setId)))
          .getSingle();

      final updated = await launch(
        _seed(
          exercises: <SeedExercise>[
            _squat(
              name: 'Back Squat',
              categoryId: _coreId,
              notes: 'Brace harder.',
              equipment: const <ExerciseEquipment>[ExerciseEquipment.barbell],
              focusIds: const <String>[_weightsId],
              updatedAt: _recordStamp,
            ),
          ],
        ),
      );

      final exercise = await updated.exercises.getById(_squatId);
      expect(exercise?.name, 'Back Squat');
      expect(exercise?.origin, ExerciseLibraryOrigin.platform);
      expect(exercise?.categoryId, _coreId);
      expect(exercise?.notes, 'Brace harder.');
      expect(exercise?.equipment, <ExerciseEquipment>[
        ExerciseEquipment.barbell,
      ]);
      expect(exercise?.focusIds, <String>[_weightsId]);
      expect(exercise?.isFavorite, isTrue);
      expect((await rowOf(_squatId)).updatedAt.toUtc(), _stored(_recordStamp));

      final setAfter = await (database.select(database.loggedSets)
            ..where((row) => row.id.equals(logged.setId)))
          .getSingle();
      expect(setAfter, setBefore);

      final workout = await RepositoryHomeRepository(updated)
          .watchWorkout(logged.workoutId)
          .first;
      expect(workout?.workoutExercises.single.name, 'Back Squat');
    });

    test('never corrects an Exercise Type in place', () async {
      await launch(_installedSeed());
      await launch(
        _seed(
          exercises: <SeedExercise>[
            _squat(
              name: 'Back Squat',
              dimensions: const <DimensionId>[DimensionId.duration],
            ),
          ],
        ),
      );

      final row = await rowOf(_squatId);
      expect(row.name, 'Back Squat');
      expect(row.dimensionIds, '["load","reps"]');
      expect(row.recordProfile, RecordProfile.repMax.name);
    });

    test('a row whose only difference is updatedAt is not written', () async {
      await launch(_installedSeed());
      final rowBefore = await rowOf(_squatId);
      final logBefore = await logEntries();

      await launch(
        _seed(exercises: <SeedExercise>[_squat(updatedAt: _recordStamp)]),
      );

      expect(await rowOf(_squatId), rowBefore);
      expect(await logEntries(), logBefore);
    });

    test('compares equipment and Focuses as sets', () async {
      await launch(_installedSeed());
      final rowBefore = await rowOf(_squatId);
      final logBefore = await logEntries();

      await launch(
        _seed(
          exercises: <SeedExercise>[
            _squat(
              equipment: const <ExerciseEquipment>[
                ExerciseEquipment.plate,
                ExerciseEquipment.barbell,
              ],
              focusIds: const <String>[_enduranceId, _weightsId],
            ),
          ],
        ),
      );

      expect(await rowOf(_squatId), rowBefore);
      expect(await logEntries(), logBefore);
    });

    test('never writes the fields that are not the seed\'s to set', () async {
      await launch(_installedSeed());
      await setRow(
        _squatId,
        const ExercisesCompanion(
          isFavorite: Value<bool>(true),
          loadMode: Value<String>('assisted'),
          defaultLoadUnit: Value<String>('pound'),
          isUnilateral: Value<bool>(true),
          usesRpe: Value<bool>(true),
          recordProfile: Value<String>('maxLoad'),
        ),
      );

      await launch(
        _seed(exercises: <SeedExercise>[_squat(name: 'Back Squat')]),
      );

      final row = await rowOf(_squatId);
      expect(row.name, 'Back Squat');
      expect(row.isFavorite, isTrue);
      expect(row.loadMode, 'assisted');
      expect(row.defaultLoadUnit, 'pound');
      expect(row.isUnilateral, isTrue);
      expect(row.usesRpe, isTrue);
      expect(row.recordProfile, 'maxLoad');
    });

    test('a Platform row with deletedAt set is reactivated', () async {
      await launch(_installedSeed());
      await setRow(
        _squatId,
        ExercisesCompanion(deletedAt: Value<DateTime?>(_retiredAt)),
      );

      final updated = await launch(_installedSeed());

      expect((await rowOf(_squatId)).deletedAt, isNull);
      expect(
        (await updated.exercises.listActive()).map((row) => row.id),
        contains(_squatId),
      );
    });
  });

  group('a retired id that is used is kept', () {
    test('by a live Set: same id, user origin, fields from the record',
        () async {
      final installed = await launch(_installedSeed());
      final logged = await logSet(installed, _plankId);
      // Only the Set names it.
      await (database.update(database.workoutExercises)
            ..where((row) => row.id.equals(logged.entryId)))
          .write(
        WorkoutExercisesCompanion(deletedAt: Value<DateTime?>(_retiredAt)),
      );
      final setBefore = await (database.select(database.loggedSets)
            ..where((row) => row.id.equals(logged.setId)))
          .getSingle();

      final updated = await launch(_updatedSeed());

      expectKept(await rowOf(_plankId));
      final exercise = await updated.exercises.getById(_plankId);
      expect(exercise?.origin, ExerciseLibraryOrigin.user);
      expect(
        (await updated.exercises.listActive()).map((row) => row.id),
        contains(_plankId),
      );
      final setAfter = await (database.select(database.loggedSets)
            ..where((row) => row.id.equals(logged.setId)))
          .getSingle();
      expect(setAfter, setBefore);
      // The merge target is a separate exercise, without those Sets (CUJ 2).
      expect(
        await updated.sets.listActiveForExercise(_fullPlankId),
        isEmpty,
      );
      expect(await updated.sets.listActiveForExercise(_plankId), hasLength(1));
    });

    test('by a live Planned Set', () async {
      final installed = await launch(_installedSeed());
      final logged = await logSet(installed, _plankId, isCompleted: false);
      await (database.update(database.workoutExercises)
            ..where((row) => row.id.equals(logged.entryId)))
          .write(
        WorkoutExercisesCompanion(deletedAt: Value<DateTime?>(_retiredAt)),
      );

      await launch(_updatedSeed());

      expectKept(await rowOf(_plankId));
    });

    test('by a live Workout entry with no Set', () async {
      final installed = await launch(_installedSeed());
      final workoutId = await startWorkout(installed);
      await installed.workoutExercises.create(
        WorkoutExerciseDraft(workoutId: workoutId, exerciseId: _plankId),
      );

      await launch(_updatedSeed());

      expectKept(await rowOf(_plankId));
    });

    test('by a live Template entry (CUJ 7)', () async {
      final installed = await launch(_installedSeed());
      final templateId = await installed.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Core'),
      );
      await installed.workoutTemplates.addExercise(templateId, _plankId);

      final updated = await launch(_updatedSeed());

      expectKept(await rowOf(_plankId));
      final template = await updated.workoutTemplates.getById(templateId);
      expect(
        template?.exercises.single.exerciseId,
        _plankId,
      );
    });

    test('by a live entry in an archived Template, whose editor then saves',
        () async {
      final installed = await launch(_installedSeed());
      final templateId = await installed.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Core'),
      );
      final entryId = await installed.workoutTemplates.addExercise(
        templateId,
        _plankId,
      );
      await installed.workoutTemplates.archive(templateId);

      final updated = await launch(_updatedSeed());

      expectKept(await rowOf(_plankId));

      await updated.workoutTemplates.restore(templateId);
      await updated.workoutTemplates.updateTemplate(
        templateId,
        name: 'Core Day',
      );
      await updated.workoutTemplates.updateExerciseNote(entryId, note: 'Slow.');
      await updated.workoutTemplates.addPrescription(
        entryId,
        PrescriptionDraft(mode: PrescriptionMode.fixed, values: _repsSet()),
      );
      await updated.workoutTemplates.removeExercise(entryId);
      await updated.workoutTemplates.addExercise(templateId, _plankId);

      final template = await updated.workoutTemplates.getById(templateId);
      expect(template?.name, 'Core Day');
      expect(template?.exercises.single.exerciseId, _plankId);
    });

    test('with a recordProfile recalculated when the dimensions differ',
        () async {
      final installed = await launch(_installedSeed());
      await logSet(installed, _plankId);
      await setRow(
        _plankId,
        const ExercisesCompanion(loadMode: Value<String>('assisted')),
      );

      await launch(
        _updatedSeed(
          plankDimensions: const <DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ],
        ),
      );

      final row = await rowOf(_plankId);
      expect(row.libraryOrigin, ExerciseLibraryOrigin.user.name);
      expect(row.dimensionIds, '["load","reps"]');
      expect(row.loadMode, 'assisted');
      expect(row.recordProfile, RecordProfile.minAssistancePerRepCount.name);
    });

    test('with a recordProfile left alone when the dimensions match', () async {
      final installed = await launch(_installedSeed());
      await logSet(installed, _plankId);
      await setRow(
        _plankId,
        const ExercisesCompanion(recordProfile: Value<String>('maxLoad')),
      );

      await launch(_updatedSeed());

      expect((await rowOf(_plankId)).recordProfile, 'maxLoad');
    });

    test('a favorite on it survives', () async {
      final installed = await launch(_installedSeed());
      await logSet(installed, _plankId);
      await installed.exercises.setFavorite(_plankId, isFavorite: true);

      await launch(_updatedSeed());

      final row = await rowOf(_plankId);
      expect(row.isFavorite, isTrue);
      expect(row.updatedAt.toUtc(), _retiredAt);
    });

    test('its older unacknowledged Activity Log entries are acknowledged, and '
        'the kept entry is not', () async {
      final installed = await launch(_installedSeed());
      await logSet(installed, _plankId);
      await installed.exercises.setFavorite(_plankId, isFavorite: true);
      final older = await logEntriesFor(_plankId);
      expect(older, hasLength(2));
      expect(
        older.map((entry) => entry.syncAcknowledgedAt),
        everyElement(isNull),
      );
      final squatEntries = await logEntriesFor(_squatId);

      await launch(_updatedSeed());

      final entries = await logEntriesFor(_plankId);
      expect(entries, hasLength(older.length + 1));
      final olderIds = older.map((entry) => entry.id).toSet();
      for (final entry in entries) {
        if (olderIds.contains(entry.id)) {
          expect(entry.syncAcknowledgedAt, isNotNull);
        }
      }
      final kept = entries.singleWhere((entry) => !olderIds.contains(entry.id));
      expect(kept.syncAcknowledgedAt, isNull);
      final image = jsonDecode(kept.afterImage!) as Map<String, Object?>;
      expect(image['library_origin'], ExerciseLibraryOrigin.user.name);
      expect(image['name'], 'Plank');
      expect(
        DateTime.parse(image['updated_at']! as String).toUtc(),
        _retiredAt,
      );
      // Another exercise's queue is left alone.
      expect(await logEntriesFor(_squatId), squatEntries);
    });

    test('a kept row is not rewritten by later launches', () async {
      final installed = await launch(_installedSeed());
      await logSet(installed, _plankId);
      final updated = await launch(_updatedSeed());
      await updated.exercises.update(
        _plankId,
        ExerciseDraft(
          name: 'My Plank',
          type: ExerciseType(const <DimensionId>[DimensionId.reps]),
        ),
      );
      final rowBefore = await rowOf(_plankId);
      final logBefore = await logEntries();

      await launch(_updatedSeed());

      expect(await rowOf(_plankId), rowBefore);
      expect(await logEntries(), logBefore);
    });

    test('with a name an active User Library exercise has, both stay active '
        'and an edit to either is refused until one is renamed (CUJ 9)',
        () async {
      final type = ExerciseType(const <DimensionId>[DimensionId.reps]);
      final installed = await launch(
        _seed(
          exercises: <SeedExercise>[
            SeedExercise(
              id: _plankId,
              name: 'Plank',
              dimensions: const <DimensionId>[DimensionId.reps],
              categoryId: _coreId,
              notes: null,
              updatedAt: _libraryStamp,
            ),
          ],
        ),
      );
      await logSet(installed, _plankId);
      final copyId = await installed.exercises.customizePlatformExercise(
        _plankId,
      );

      final updated = await launch(_updatedSeed());

      final kept = await rowOf(_plankId);
      final copy = await rowOf(copyId);
      expect(kept.libraryOrigin, ExerciseLibraryOrigin.user.name);
      expect(kept.deletedAt, isNull);
      expect(copy.libraryOrigin, ExerciseLibraryOrigin.user.name);
      expect(copy.deletedAt, isNull);
      expect(kept.name, copy.name);

      await expectLater(
        updated.exercises.update(
          _plankId,
          ExerciseDraft(name: 'Plank', type: type),
        ),
        throwsA(isA<DuplicateExerciseNameException>()),
      );
      await expectLater(
        updated.exercises.update(
          copyId,
          ExerciseDraft(name: 'Plank', type: type),
        ),
        throwsA(isA<DuplicateExerciseNameException>()),
      );

      await updated.exercises.update(
        copyId,
        ExerciseDraft(name: 'My Plank', type: type),
      );
      await updated.exercises.update(
        _plankId,
        ExerciseDraft(name: 'Plank', type: type, notes: 'Edited.'),
      );
      expect((await rowOf(_plankId)).notes, 'Edited.');
    });
  });

  group('a retired id that is not used is hidden', () {
    test('with only a deleted Set; restoring the Set keeps it', () async {
      final installed = await launch(_installedSeed());
      final logged = await logSet(installed, _plankId);
      await installed.workoutExercises.softDelete(logged.entryId);

      await launch(_updatedSeed());
      expectHidden(await rowOf(_plankId));

      await (database.update(database.loggedSets)
            ..where((row) => row.id.equals(logged.setId)))
          .write(const LoggedSetsCompanion(deletedAt: Value<DateTime?>(null)));
      await launch(_updatedSeed());

      expectKept(await rowOf(_plankId));
    });

    test('with a Set in a deleted Workout', () async {
      final installed = await launch(_installedSeed());
      final logged = await logSet(installed, _plankId);
      await installed.workoutSessions.softDelete(logged.workoutId);

      await launch(_updatedSeed());

      expectHidden(await rowOf(_plankId));
    });

    test('and absent from everywhere the user looks (CUJ 4)', () async {
      await launch(_installedSeed());

      final updated = await launch(_updatedSeed());

      expectHidden(await rowOf(_plankId));
      expect(
        (await updated.exercises.listActive()).map((row) => row.id),
        isNot(anyOf(contains(_plankId), contains(_sideBendId))),
      );
      expect(
        (await updated.exercises.listArchivedUser()).map((row) => row.id),
        isNot(anyOf(contains(_plankId), contains(_sideBendId))),
      );
      final catalogIds = (await updated.catalog.listMergedCatalog())
          .expand((section) => section.exercises)
          .map((exercise) => exercise.id)
          .toSet();
      expect(catalogIds, isNot(contains(_plankId)));
      expect(catalogIds, isNot(contains(_sideBendId)));
      expect(catalogIds, containsAll(<String>[_squatId, _fullPlankId]));
    });

    test('even as a favorite, and a stamp a favorite wrote is corrected',
        () async {
      final installed = await launch(_installedSeed());
      await installed.exercises.setFavorite(_plankId, isFavorite: true);

      final updated = await launch(_updatedSeed());
      expectHidden(await rowOf(_plankId));
      expect((await rowOf(_plankId)).isFavorite, isTrue);

      // A favorite on a Platform row stamps the current time, here later than
      // retired_at. The next pass puts both stamps back.
      await updated.exercises.setFavorite(_plankId, isFavorite: false);
      await setRow(
        _plankId,
        ExercisesCompanion(
          updatedAt: Value<DateTime>(_retiredAt.add(const Duration(days: 30))),
        ),
      );
      await launch(_updatedSeed());

      expectHidden(await rowOf(_plankId));
    });

    test('with a recordProfile recalculated when the dimensions differ',
        () async {
      await launch(_installedSeed());

      await launch(
        _updatedSeed(
          plankDimensions: const <DimensionId>[
            DimensionId.distance,
            DimensionId.duration,
          ],
        ),
      );

      final row = await rowOf(_plankId);
      expect(row.dimensionIds, '["distance","duration"]');
      expect(row.recordProfile, RecordProfile.fastestPace.name);
    });

    test('a fresh install inserts one with the record\'s own name for every '
        'retired id', () async {
      final repositories = await launch(_updatedSeed());

      final plank = await rowOf(_plankId);
      expectHidden(plank);
      expect(plank.dimensionIds, '["reps"]');
      expect(plank.loadMode, ExerciseLoadMode.added.name);
      expect(plank.recordProfile, RecordProfile.maxReps.name);
      expect(plank.defaultLoadUnit, TrainingUnit.kilogram.name);
      expect(plank.isUnilateral, isFalse);
      expect(plank.usesRpe, isFalse);
      final sideBend = await rowOf(_sideBendId);
      expect(sideBend.name, 'Side Bend');
      expect(sideBend.libraryOrigin, ExerciseLibraryOrigin.platform.name);
      expect(sideBend.deletedAt?.toUtc(), _retiredAt);
      expect(
        (await repositories.exercises.listActive()).map((row) => row.id),
        unorderedEquals(<String>[_squatId, _fullPlankId]),
      );
      final entry = (await logEntriesFor(_plankId)).single;
      expect(entry.beforeImage, isNull);
      expect(
        DateTime.parse(
          (jsonDecode(entry.afterImage!) as Map<String, Object?>)['updated_at']!
              as String,
        ).toUtc(),
        _stored(_recordStamp),
      );
    });

    test('a Set that arrives later is accepted and the next pass keeps it '
        '(CUJ 6)', () async {
      final repositories = await launch(_updatedSeed());
      expectHidden(await rowOf(_plankId));

      final workoutId = await startWorkout(repositories);
      final setId = await repositories.sets.create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: _plankId,
          position: 0,
          values: _repsSet(),
          isCompleted: true,
        ),
        actor: 'sync',
      );
      expect((await rowOf(_plankId)).deletedAt, isNotNull);

      await launch(_updatedSeed());

      expectKept(await rowOf(_plankId));
      expect(await repositories.sets.getById(setId), isNotNull);
    });
  });

  group('a second run', () {
    test('writes nothing and appends no Activity Log entry', () async {
      final installed = await launch(_installedSeed());
      await logSet(installed, _plankId);
      await launch(_updatedSeed());
      final rowsBefore = await allRows();
      final logBefore = await logEntries();
      // The stamp with milliseconds is what would rewrite a row every launch.
      expect(
        (await rowOf(_sideBendId)).updatedAt.millisecondsSinceEpoch,
        isNot(_recordStamp.millisecondsSinceEpoch),
      );

      await launch(_updatedSeed());

      expect(await allRows(), rowsBefore);
      expect(await logEntries(), logBefore);
    });

    test('after a fresh install also writes nothing', () async {
      await launch(_updatedSeed());
      final rowsBefore = await allRows();
      final logBefore = await logEntries();

      await launch(_updatedSeed());

      expect(await allRows(), rowsBefore);
      expect(await logEntries(), logBefore);
    });

    test('a differing dimension order settles after one write', () async {
      await launch(
        _updatedSeed(
          plankDimensions: const <DimensionId>[
            DimensionId.distance,
            DimensionId.duration,
          ],
        ),
      );
      final reordered = _updatedSeed(
        plankDimensions: const <DimensionId>[
          DimensionId.duration,
          DimensionId.distance,
        ],
      );
      final logBefore = await logEntries();

      await launch(reordered);
      final row = await rowOf(_plankId);
      expect(row.dimensionIds, '["duration","distance"]');
      final logAfterFirst = await logEntries();
      expect(logAfterFirst, hasLength(logBefore.length + 1));

      await launch(reordered);
      expect(await rowOf(_plankId), row);
      expect(await logEntries(), logAfterFirst);
    });
  });

  test('the bundled seed settles after one pass', () async {
    await TrainingRepositories(database).catalog.ensurePlatformLibrarySeeded();
    final rowsBefore = await allRows();
    final logCountBefore = (await logEntries()).length;
    expect(rowsBefore.where((row) => row.deletedAt != null), hasLength(309));

    await TrainingRepositories(database).catalog.ensurePlatformLibrarySeeded();

    expect(await allRows(), rowsBefore);
    expect(await logEntries(), hasLength(logCountBefore));
  });

  test('applies both lists in id order whatever the seed order', () async {
    await launch(
      PlatformExerciseSeed(
        categories: _categories,
        exercises: <SeedExercise>[_fullPlank, _squat()],
        retired: <SeedRetiredExercise>[_sideBendRetired, _plankRetired()],
      ),
    );

    final exerciseEntries = (await logEntries())
        .where((entry) => entry.entityTable == AppDatabase.exercisesTable);
    expect(
      exerciseEntries.map((entry) => entry.entityId),
      <String>[_squatId, _fullPlankId, _plankId, _sideBendId],
    );
  });

  group('a row left by the old redirect step', () {
    Future<TrainingRepositories> installAlias() async {
      final installed = await launch(
        _seed(exercises: <SeedExercise>[_squat(), _fullPlank]),
      );
      // The old step inserted a merged id with its target's name and stamp.
      await database.into(database.exercises).insert(
            ExercisesCompanion.insert(
              id: _plankId,
              libraryOrigin: Value<String>(ExerciseLibraryOrigin.platform.name),
              name: _fullPlank.name,
              dimensionIds: '["reps"]',
              categoryId: const Value<String?>(_coreId),
              updatedAt: _fullPlank.updatedAt,
              deletedAt: Value<DateTime?>(_fullPlank.updatedAt),
            ),
          );
      return installed;
    }

    test('is rewritten from the record and stays hidden when unused', () async {
      await installAlias();

      await launch(_updatedSeed());

      expectHidden(await rowOf(_plankId));
    });

    test('is rewritten from the record and kept when used', () async {
      final installed = await installAlias();
      await logSet(installed, _plankId);

      await launch(_updatedSeed());

      expectKept(await rowOf(_plankId));
    });
  });

  group('rows the pass does not own', () {
    Future<void> insertUserRow(String id, {required String name}) {
      return database.into(database.exercises).insert(
            ExercisesCompanion.insert(
              id: id,
              libraryOrigin: Value<String>(ExerciseLibraryOrigin.user.name),
              name: name,
              dimensionIds: '["reps"]',
              updatedAt: _libraryStamp,
            ),
          );
    }

    test('a User Library row with a retired id or a seed id is never modified',
        () async {
      await insertUserRow(_plankId, name: 'My Plank');
      await insertUserRow(_squatId, name: 'My Squat');
      final repositories = TrainingRepositories(
        database,
        platformSeedSource: _SeedSource(_updatedSeed()),
      );
      await repositories.catalog.ensurePlatformLibrarySeeded();
      final plankBefore = await rowOf(_plankId);
      final squatBefore = await rowOf(_squatId);
      expect(plankBefore.name, 'My Plank');
      expect(plankBefore.deletedAt, isNull);
      expect(squatBefore.name, 'My Squat');
      await logSet(repositories, _plankId);
      await repositories.exercises.softDelete(_squatId);
      final archivedSquat = await rowOf(_squatId);

      await launch(_updatedSeed());

      expect(await rowOf(_plankId), plankBefore);
      expect(await rowOf(_squatId), archivedSquat);
      expect(await logEntriesFor(_plankId), isEmpty);
    });

    test('a Platform row in neither list is never modified', () async {
      await launch(_updatedSeed());
      await database.into(database.exercises).insert(
            ExercisesCompanion.insert(
              id: _unlistedId,
              libraryOrigin: Value<String>(ExerciseLibraryOrigin.platform.name),
              name: 'Hand Written',
              dimensionIds: '["reps"]',
              updatedAt: _libraryStamp,
            ),
          );
      final before = await rowOf(_unlistedId);

      await launch(_updatedSeed());

      expect(await rowOf(_unlistedId), before);
      expect(await logEntriesFor(_unlistedId), isEmpty);
    });
  });

  test('an imported merged alias and removed active row are corrected by the '
      'next pass', () async {
    // An older backup: the merged id is an alias under its target's name, and
    // the removed exercise is still active.
    final sourceDatabase = AppDatabase.inMemory();
    addTearDown(sourceDatabase.close);
    final source = await launch(
      _seed(
        exercises: <SeedExercise>[_squat(), _fullPlank, _sideBendInstalled],
      ),
      on: sourceDatabase,
    );
    final backupStamp = _retiredAt.add(const Duration(days: 1));
    await sourceDatabase.into(sourceDatabase.exercises).insert(
          ExercisesCompanion.insert(
            id: _plankId,
            libraryOrigin: Value<String>(ExerciseLibraryOrigin.platform.name),
            name: _fullPlank.name,
            dimensionIds: '["reps"]',
            categoryId: const Value<String?>(_coreId),
            updatedAt: backupStamp,
            deletedAt: Value<DateTime?>(backupStamp),
          ),
        );
    await (sourceDatabase.update(sourceDatabase.exercises)
          ..where((row) => row.id.equals(_sideBendId)))
        .write(ExercisesCompanion(updatedAt: Value<DateTime>(backupStamp)));
    final archive = await source.portableArchives.exportPortableArchive();

    final target = await launch(_updatedSeed());
    await target.portableArchives.importPortableArchive(archive);

    // The import merges as it always has: old name, reactivated row.
    expect((await rowOf(_plankId)).name, 'Full Plank');
    expect((await rowOf(_sideBendId)).deletedAt, isNull);

    await launch(_updatedSeed());

    expectHidden(await rowOf(_plankId));
    final sideBend = await rowOf(_sideBendId);
    expect(sideBend.name, 'Side Bend');
    expect(sideBend.libraryOrigin, ExerciseLibraryOrigin.platform.name);
    expect(sideBend.updatedAt.toUtc(), _stored(_recordStamp));
    expect(sideBend.deletedAt?.toUtc(), _retiredAt);
  });
}
