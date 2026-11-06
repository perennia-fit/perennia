import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/platform_exercise_seed.dart';
import 'package:perennia/domain/training/training_dimensions.dart';

import '../support/kill_point_snapshot_interceptor.dart';

/// Kill-and-reopen for the launch pass
/// (docs/designs/platform-library-updates.md, Crash safety and CUJ 10),
/// following `test/data/focus_recolor_reopen_test.dart`: a database file that
/// is closed and opened again.
///
/// A process kill mid-write can't be staged inside one test process, so the
/// kill is taken as what it leaves on disk. A query interceptor copies the
/// database file and its journal just before the first write to `exercises`
/// and just before the commit. Each copy is exactly the disk a kill at that
/// moment leaves behind, and opening it runs SQLite's crash recovery. The pass
/// is one transaction, so a kill leaves nothing of it, and the next launch
/// runs it again from the start.
void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'prn_platform_library_update_reopen_',
    );
    file = File('${directory.path}/library.sqlite');
  });

  tearDown(() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  test(
      'a kill during the first pass leaves nothing of it, and the next launch '
      'completes it', () async {
    // Create the schema first, so the kill points only see the pass.
    await AppDatabase.openFile(file).close();

    final killPoints = _KillPointInterceptor(file, directory);
    final database = AppDatabase(
      NativeDatabase(file).interceptWith(killPoints),
    );
    await _launch(database, _updatedSeed);
    await database.close();

    expect(
      killPoints.snapshots.keys.toSet(),
      <String>{'before-first-exercise-write', 'before-commit'},
    );
    for (final entry in killPoints.snapshots.entries) {
      final reopened = AppDatabase.openFile(entry.value);
      try {
        expect(
          await reopened.select(reopened.exercises).get(),
          isEmpty,
          reason: 'killed ${entry.key}: no Platform row survives',
        );
        expect(
          await reopened.select(reopened.exerciseCategories).get(),
          isEmpty,
          reason: 'killed ${entry.key}: no seed category survives',
        );
        expect(
          await reopened.select(reopened.activityLog).get(),
          isEmpty,
          reason: 'killed ${entry.key}: no Activity Log entry survives',
        );

        await _launch(reopened, _updatedSeed);

        await _expectCompleteFirstPass(reopened, killedAt: entry.key);
      } finally {
        await reopened.close();
      }
    }
  });

  test(
      'CUJ 10: reopening mid-Workout on a seed that retires its exercise keeps '
      'it, and logging continues', () async {
    var database = AppDatabase.openFile(file);
    var repositories = await _launch(database, _installedSeed);
    final workoutId = await repositories.workoutSessions.create(
      WorkoutSessionDraft(
        startedAt: DateTime.utc(2026, 1, 2, 8),
        timezone: 'UTC',
      ),
    );
    await repositories.workoutExercises.create(
      WorkoutExerciseDraft(workoutId: workoutId, exerciseId: _plankId),
    );
    final firstSetId = await repositories.sets.create(
      LoggedSetDraft(
        workoutId: workoutId,
        exerciseId: _plankId,
        position: 0,
        values: _repsSet('10'),
        isCompleted: true,
      ),
    );
    final firstSetBefore = await _setRow(database, firstSetId);
    // The process dies mid-Workout, and the app comes back on the new version.
    await database.close();

    database = AppDatabase.openFile(file);
    addTearDown(database.close);
    repositories = await _launch(database, _updatedSeed);

    final kept = await _exerciseRow(database, _plankId);
    expect(kept.libraryOrigin, ExerciseLibraryOrigin.user.name);
    expect(kept.deletedAt, isNull);
    expect(kept.name, 'Plank');
    expect(kept.updatedAt.toUtc(), _retiredAt);

    final secondSetId = await repositories.sets.create(
      LoggedSetDraft(
        workoutId: workoutId,
        exerciseId: _plankId,
        position: 1,
        values: _repsSet('12'),
        isCompleted: true,
      ),
    );

    expect(await _setRow(database, firstSetId), firstSetBefore);
    final secondSet = await _setRow(database, secondSetId);
    expect(secondSet.exerciseId, _plankId);
    expect(secondSet.repsEntered, '12');
    final liveSets = await (database.select(database.loggedSets)
          ..where(
            (row) => row.workoutId.equals(workoutId) & row.deletedAt.isNull(),
          ))
        .get();
    expect(
      liveSets.map((row) => row.id).toSet(),
      <String>{firstSetId, secondSetId},
    );
  });
}

const _categoryId = '01910000-0000-7000-8000-000000000002';
const _fullPlankId = '01910000-0000-7000-8000-000000000102';
const _plankId = '01910000-0000-7000-8000-000000000201';
const _sideBendId = '01910000-0000-7000-8000-000000000202';

final _libraryStamp = DateTime.utc(2026, 1, 1);
final _retiredAt = DateTime.utc(2026, 1, 5);

final _categories = <SeedExerciseCategory>[
  SeedExerciseCategory(
    id: _categoryId,
    name: 'Core',
    sortOrder: 0,
    colorHex: '#1F9D55',
    updatedAt: _libraryStamp,
  ),
];

SeedExercise _seedExercise(String id, String name) {
  return SeedExercise(
    id: id,
    name: name,
    dimensions: const <DimensionId>[DimensionId.reps],
    categoryId: _categoryId,
    notes: null,
    updatedAt: _libraryStamp,
  );
}

SeedRetiredExercise _seedRetired(String id, String name) {
  return SeedRetiredExercise(
    id: id,
    name: name,
    dimensions: const <DimensionId>[DimensionId.reps],
    categoryId: _categoryId,
    notes: null,
    updatedAt: _libraryStamp,
    retiredAt: _retiredAt,
  );
}

/// The library an installed app first seeded, which still offers `Plank`.
final _installedSeed = PlatformExerciseSeed(
  categories: _categories,
  exercises: <SeedExercise>[
    _seedExercise(_fullPlankId, 'Full Plank'),
    _seedExercise(_plankId, 'Plank (old name)'),
  ],
);

/// The same library after it merged `Plank` and removed `Side Bend`.
final _updatedSeed = PlatformExerciseSeed(
  categories: _categories,
  exercises: <SeedExercise>[_seedExercise(_fullPlankId, 'Full Plank')],
  retired: <SeedRetiredExercise>[
    _seedRetired(_plankId, 'Plank'),
    _seedRetired(_sideBendId, 'Side Bend'),
  ],
);

class _SeedSource implements PlatformExerciseSeedSource {
  const _SeedSource(this.seed);

  final PlatformExerciseSeed seed;

  @override
  Future<PlatformExerciseSeed> load() async => seed;
}

LoggedSet _repsSet(String reps) {
  return LoggedSet.fromValues(<SetDimensionValue>[
    SetDimensionValue(
      dimension: DimensionId.reps,
      entered: reps,
      unit: TrainingUnit.repetition,
    ),
  ]);
}

/// One launch: the pass is memoized per instance, so a rerun needs a new one.
Future<TrainingRepositories> _launch(
  AppDatabase database,
  PlatformExerciseSeed seed,
) async {
  final repositories = TrainingRepositories(
    database,
    platformSeedSource: _SeedSource(seed),
  );
  await repositories.catalog.ensurePlatformLibrarySeeded();
  return repositories;
}

Future<ExerciseRow> _exerciseRow(AppDatabase database, String id) {
  return (database.select(database.exercises)
        ..where((row) => row.id.equals(id)))
      .getSingle();
}

Future<LoggedSetRow> _setRow(AppDatabase database, String id) {
  return (database.select(database.loggedSets)
        ..where((row) => row.id.equals(id)))
      .getSingle();
}

/// What the first pass over [_updatedSeed] leaves: the category, the live
/// exercise, both retired exercises hidden, one Activity Log entry per row, and
/// nothing left to write.
Future<void> _expectCompleteFirstPass(
  AppDatabase database, {
  required String killedAt,
}) async {
  final reason = 'killed $killedAt';
  final categories = await database.select(database.exerciseCategories).get();
  expect(categories.map((row) => row.id), <String>[_categoryId],
      reason: reason);

  final exercises = await (database.select(database.exercises)
        ..orderBy([(row) => OrderingTerm.asc(row.id)]))
      .get();
  expect(
    exercises.map(
      (row) => (
        id: row.id,
        name: row.name,
        origin: row.libraryOrigin,
        updatedAt: row.updatedAt.toUtc(),
        deletedAt: row.deletedAt?.toUtc(),
      ),
    ),
    <Object>[
      (
        id: _fullPlankId,
        name: 'Full Plank',
        origin: ExerciseLibraryOrigin.platform.name,
        updatedAt: _libraryStamp,
        deletedAt: null,
      ),
      (
        id: _plankId,
        name: 'Plank',
        origin: ExerciseLibraryOrigin.platform.name,
        updatedAt: _libraryStamp,
        deletedAt: _retiredAt,
      ),
      (
        id: _sideBendId,
        name: 'Side Bend',
        origin: ExerciseLibraryOrigin.platform.name,
        updatedAt: _libraryStamp,
        deletedAt: _retiredAt,
      ),
    ],
    reason: reason,
  );

  final entries = await database.select(database.activityLog).get();
  expect(
    entries.map((entry) => entry.entityId).toSet(),
    <String>{_categoryId, _fullPlankId, _plankId, _sideBendId},
    reason: reason,
  );
  expect(entries, hasLength(4), reason: reason);

  // A second launch finds nothing to change.
  await _launch(database, _updatedSeed);
  expect(
    await database.select(database.exercises).get(),
    unorderedEquals(exercises),
    reason: reason,
  );
  expect(await database.select(database.activityLog).get(), hasLength(4),
      reason: reason);
}

/// Copies the database file and its journal, as a kill would leave them, just
/// before the pass first writes to `exercises` and just before its commit.
class _KillPointInterceptor extends KillPointSnapshotInterceptor {
  _KillPointInterceptor(super.file, super.directory);

  var _exerciseWrites = 0;

  void _beforeWrite(String statement) {
    if (statement.contains('"exercises"')) {
      if (_exerciseWrites == 0) {
        snapshot('before-first-exercise-write');
      }
      _exerciseWrites += 1;
    }
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _beforeWrite(statement);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _beforeWrite(statement);
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) {
    if (_exerciseWrites > 0) {
      snapshot('before-commit');
    }
    return super.commitTransaction(inner);
  }
}
