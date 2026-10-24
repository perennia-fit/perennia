part of 'training_repositories.dart';

/// Focuses: the training disciplines a Workout is performed under.
///
/// They behave like Exercise Categories: the starter Focuses are seeded with
/// fixed ids alongside the Platform Library, users rename, reorder, archive,
/// and add their own, and every change is an Activity Log entry that syncs as
/// an ordinary LWW row. Archiving never blocks on use: a Workout or Exercise
/// keeps naming an archived Focus, which is how history survives it.
class FocusRepository {
  FocusRepository._(this._repositories);

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  /// Active Focuses in the user's order, for pickers.
  Stream<List<FocusRecord>> watchActive() {
    return _activeQuery()
        .watch()
        .map((rows) => rows.map(_focusFromRow).toList(growable: false));
  }

  Future<List<FocusRecord>> listActive() async {
    final rows = await _activeQuery().get();
    return rows.map(_focusFromRow).toList(growable: false);
  }

  /// Every Focus, archived ones included, so a Workout recorded under a Focus
  /// that was archived later still shows its name.
  Stream<Map<String, FocusRecord>> watchAllById() {
    return _database.select(_database.focuses).watch().map(
          (rows) => <String, FocusRecord>{
            for (final row in rows) row.id: _focusFromRow(row),
          },
        );
  }

  Future<String> create(
    String name, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._writeContexts.create(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      await _ensureUniqueActiveName(name);
      final activeRows = await _activeQuery().get();
      final id = _repositories._ids.create(context.timestamp);
      await _database.into(_database.focuses).insert(
            FocusesCompanion.insert(
              id: id,
              name: _normalizeFocusNameForStorage(name),
              sortOrder: _nextPosition(activeRows, (row) => row.sortOrder),
              updatedAt: context.timestamp,
            ),
          );
      await _appendChange(context, id, before: null);
      return id;
    });
  }

  Future<void> rename(
    String id, {
    required String name,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._writeContexts.create(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final before = await _requireRow(id);
      await _ensureUniqueActiveName(name, exceptId: id);
      final normalized = _normalizeFocusNameForStorage(name);
      if (normalized == before.name) {
        return;
      }
      await (_database.update(_database.focuses)
            ..where((row) => row.id.equals(id)))
          .write(
        FocusesCompanion(
          name: Value<String>(normalized),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      await _appendChange(context, id, before: before);
    });
  }

  Future<void> reorder(
    List<String> focusIds, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._writeContexts.create(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final activeRows = await _activeQuery().get();
      final activeIds = activeRows.map((row) => row.id).toSet();
      if (focusIds.length != activeIds.length ||
          focusIds.toSet().length != focusIds.length ||
          !focusIds.every(activeIds.contains)) {
        throw ArgumentError.value(
          focusIds,
          'focusIds',
          'Ordering must include each active Focus exactly once.',
        );
      }
      final beforeById = <String, FocusRow>{
        for (final row in activeRows) row.id: row,
      };
      for (var index = 0; index < focusIds.length; index += 1) {
        final id = focusIds[index];
        final before = beforeById[id]!;
        if (before.sortOrder == index) {
          continue;
        }
        await (_database.update(_database.focuses)
              ..where((row) => row.id.equals(id)))
            .write(
          FocusesCompanion(
            sortOrder: Value<int>(index),
            updatedAt: Value<DateTime>(context.timestamp),
          ),
        );
        await _appendChange(context, id, before: before);
      }
    });
  }

  Future<void> archive(
    String id, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._writeContexts.create(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final before = await _requireRow(id);
      if (before.deletedAt != null) {
        return;
      }
      await (_database.update(_database.focuses)
            ..where((row) => row.id.equals(id)))
          .write(
        FocusesCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      await _appendChange(context, id, before: before);
    });
  }

  /// The staple exercises of each starter Focus, keyed by Focus id, in the
  /// order they are offered. Read from the bundled seed: guidance shipped
  /// with the app, not user data, so it is never stored or synced. A Focus
  /// the user created has none.
  Future<Map<String, List<String>>> starterExerciseIds() async {
    final seed = await _repositories.catalog._platformSeedSource.load();
    return <String, List<String>>{
      for (final focus in seed.focuses) focus.id: focus.starterExerciseIds,
    };
  }

  /// The exercises the user has logged in Workouts under [focusId], most
  /// recently performed first. Derived on every read from the Workouts
  /// themselves, never stored, so it cannot drift from what was logged.
  Stream<List<FocusExerciseUse>> watchRecentExerciseUses(
    String focusId, {
    int limit = 20,
  }) {
    return _database
        .customSelect(
          '''
          SELECT
            workout_exercises.exercise_id AS exercise_id,
            MAX(workout_sessions.started_at) AS last_started_at,
            COUNT(DISTINCT workout_sessions.id) AS workout_count
          FROM workout_exercises
          JOIN workout_sessions
            ON workout_sessions.id = workout_exercises.workout_id
          JOIN exercises
            ON exercises.id = workout_exercises.exercise_id
          WHERE workout_sessions.focus_id = ?
            AND workout_sessions.deleted_at IS NULL
            AND workout_exercises.deleted_at IS NULL
            AND exercises.deleted_at IS NULL
          GROUP BY workout_exercises.exercise_id
          ORDER BY last_started_at DESC, workout_exercises.exercise_id
          LIMIT ?
          ''',
          variables: <Variable<Object>>[
            Variable<String>(focusId),
            Variable<int>(limit),
          ],
          readsFrom: <ResultSetImplementation<HasResultSet, dynamic>>{
            _database.workoutExercises,
            _database.workoutSessions,
            _database.exercises,
          },
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (row) => FocusExerciseUse(
                  exerciseId: row.read<String>('exercise_id'),
                  lastPerformedAt: _focusSqlDateTime(
                    row.data['last_started_at'],
                  ),
                  workoutCount: row.read<int>('workout_count'),
                ),
              )
              .toList(growable: false),
        );
  }

  /// Applies a pulled Focus sync image: upserts the row, stamping the source
  /// device, and appends a sync-acknowledged Activity Log entry so the value
  /// it replaced stays recoverable.
  Future<void> applySyncImage({
    required Map<String, Object?> image,
    required String deviceId,
    required String batchId,
    String actor = 'sync',
    String? activityLogId,
    Map<String, Object?>? activityBeforeImage,
    Map<String, Object?>? activityAfterImage,
    DateTime? activityOccurredAt,
  }) {
    final context = _repositories._writeContexts.create(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final id = _activityRequiredString(image, 'id');
      final localBeforeImage = await _imageFor(id);
      await _database.into(_database.focuses).insertOnConflictUpdate(
            _focusSyncCompanionFromImage(image, syncDeviceId: deviceId),
          );
      final localAfterImage = await _imageFor(id);
      if (localAfterImage == null ||
          (localBeforeImage != null &&
              _activityImagesEqual(localBeforeImage, localAfterImage))) {
        return;
      }
      await _repositories._activityLogWriter.append(
        context,
        entityTable: AppDatabase.focusesTable,
        entityId: id,
        beforeImage: activityBeforeImage ?? localBeforeImage,
        afterImage: activityAfterImage ?? localAfterImage,
        id: activityLogId,
        occurredAt: activityOccurredAt,
        syncAcknowledgedAt: context.timestamp,
      );
    });
  }

  /// Inserts the starter Focuses this device has never had. Runs inside the
  /// Platform Library seed transaction; a starter the user archived or
  /// renamed is left alone because its row already exists.
  Future<void> _seedStarterFocuses(
    List<SeedFocus> starters,
    WriteContext context,
  ) async {
    if (starters.isEmpty) {
      return;
    }
    final existingIds =
        (await _database.select(_database.focuses).get())
            .map((row) => row.id)
            .toSet();
    for (final starter in starters) {
      if (existingIds.contains(starter.id)) {
        continue;
      }
      await _database.into(_database.focuses).insert(
            FocusesCompanion.insert(
              id: starter.id,
              name: starter.name,
              sortOrder: starter.sortOrder,
              updatedAt: starter.updatedAt,
            ),
          );
      await _appendChange(context, starter.id, before: null);
    }
  }

  Future<Map<String, Object?>?> _imageFor(String id) async {
    final row = await (_database.select(_database.focuses)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _focusImage(row);
  }

  Future<void> _appendChange(
    WriteContext context,
    String id, {
    required FocusRow? before,
  }) async {
    final after = await _requireRow(id);
    await _repositories._activityLogWriter.append(
      context,
      entityTable: AppDatabase.focusesTable,
      entityId: id,
      beforeImage: before == null ? null : _focusImage(before),
      afterImage: _focusImage(after),
    );
  }

  SimpleSelectStatement<$FocusesTable, FocusRow> _activeQuery() {
    return _database.select(_database.focuses)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([
        (row) => OrderingTerm.asc(row.sortOrder),
        (row) => OrderingTerm.asc(row.name),
      ]);
  }

  Future<FocusRow> _requireRow(String id) async {
    final row = await (_database.select(_database.focuses)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Focus not found: $id.');
    }
    return row;
  }

  Future<void> _ensureUniqueActiveName(String name, {String? exceptId}) async {
    final normalized = _normalizeCategoryName(name);
    if (normalized.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A Focus needs a name.');
    }
    final rows = await _activeQuery().get();
    final duplicate = rows.any(
      (row) =>
          row.id != exceptId && _normalizeCategoryName(row.name) == normalized,
    );
    if (duplicate) {
      throw DuplicateFocusNameException(name);
    }
  }
}

class DuplicateFocusNameException implements Exception {
  const DuplicateFocusNameException(this.name);

  final String name;

  @override
  String toString() => 'Duplicate Focus name: $name.';
}

String _normalizeFocusNameForStorage(String name) => name.trim();

// `customSelect` hands back the stored Drift value of a DATETIME column,
// which is Unix seconds unless the database stores DateTimes as text.
DateTime _focusSqlDateTime(Object? value) {
  return switch (value) {
    final int seconds =>
      DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
    final String text => DateTime.parse(text).toUtc(),
    _ => throw StateError('Unexpected stored date value: $value.'),
  };
}

FocusRecord _focusFromRow(FocusRow row) {
  return FocusRecord(
    id: row.id,
    name: row.name,
    sortOrder: row.sortOrder,
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );
}

Map<String, Object?> _focusImage(FocusRow row) {
  return <String, Object?>{
    'id': row.id,
    'name': row.name,
    'sort_order': row.sortOrder,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

FocusesCompanion _focusCompanionFromImage(Map<String, Object?> image) {
  return FocusesCompanion(
    name: Value<String>(_activityRequiredString(image, 'name')),
    sortOrder: Value<int>(_activityRequiredInt(image, 'sort_order')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

FocusesCompanion _focusSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) {
  return _focusCompanionFromImage(image).copyWith(
    id: Value<String>(_activityRequiredString(image, 'id')),
    syncDeviceId: Value<String?>(syncDeviceId),
    syncPreviouslySynced: const Value<bool>(true),
  );
}

// A Focus reference read from an Activity Log or sync image. Images written
// before Focus existed carry no key, and reading "no key" as "no Focus" would
// let an old undo or an older device's push erase one, so a missing key leaves
// the column untouched.
Value<String?> _imageFocusId(Map<String, Object?> image) {
  return image.containsKey('focus_id')
      ? Value<String?>(_activityNullableString(image, 'focus_id'))
      : const Value<String?>.absent();
}

Value<String> _imageFocusIds(Map<String, Object?> image) {
  return image.containsKey('focus_ids')
      ? Value<String>(_activityNullableString(image, 'focus_ids') ?? '[]')
      : const Value<String>.absent();
}

String _encodeFocusIds(Iterable<String> focusIds) {
  return jsonEncode(focusIds.toSet().toList(growable: false));
}

List<String> _decodeFocusIds(String encoded) {
  final decoded = jsonDecode(encoded);
  if (decoded is! List) {
    return const <String>[];
  }
  return List<String>.unmodifiable(decoded.whereType<String>());
}
