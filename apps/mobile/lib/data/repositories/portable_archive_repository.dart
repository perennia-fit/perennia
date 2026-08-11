part of 'training_repositories.dart';

class PortableArchiveRepository {
  PortableArchiveRepository._(this._repositories);

  static const archiveFormatVersion = 1;
  static const appVersion = '0.1.0+1';
  static const importActor = 'portable_archive_import';
  static const manifestFileName = 'manifest.json';
  static const encryptedManifestFileName = 'encrypted_manifest.json';
  static const encryptedPayloadFileName = 'payload.bin';
  static const keyDerivationIterations = 600000;
  static const minimumKeyDerivationIterations = 100000;

  static const _encryptedArchiveFormatVersion = 1;
  static const _encryptionAlgorithm = 'AES-256-GCM';
  static const _kdfAlgorithm = 'PBKDF2-HMAC-SHA256';
  static const _saltLength = 16;

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  static String entityFileName(String tableName) {
    return 'entities/$tableName.jsonl';
  }

  Future<List<int>> exportPortableArchive({
    DateTime? createdAt,
    PortableArchiveEncryptionOptions? encryption,
  }) async {
    final archiveCreatedAt = (createdAt ?? DateTime.now()).toUtc();
    final plaintext = await _exportPlaintextPortableArchive(
      createdAt: archiveCreatedAt,
    );
    final encryptionOptions = encryption;
    if (encryptionOptions == null) {
      return plaintext;
    }

    return _encryptArchive(
      plaintext,
      passphrase: encryptionOptions.passphrase,
      createdAt: archiveCreatedAt,
    );
  }

  Future<List<int>> _exportPlaintextPortableArchive({
    required DateTime createdAt,
  }) async {
    final entities = _entities;
    final rowsByEntity = <_PortableArchiveEntity, List<Map<String, Object?>>>{};
    final manifestEntities = <PortableArchiveEntityManifest>[];

    for (final entity in entities) {
      final rows = await entity.exportRows();
      rowsByEntity[entity] = rows;
      manifestEntities.add(
        PortableArchiveEntityManifest(
          tableName: entity.tableName,
          fileName: entity.fileName,
          rowCount: rows.length,
        ),
      );
    }

    final manifest = PortableArchiveManifest(
      formatVersion: archiveFormatVersion,
      schemaVersion: _database.schemaVersion,
      appVersion: appVersion,
      createdAt: createdAt,
      entities: List<PortableArchiveEntityManifest>.unmodifiable(
        manifestEntities,
      ),
    );
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          manifestFileName,
          jsonEncode(manifest.toJson()),
        ),
      );

    for (final entity in entities) {
      archive.addFile(
        ArchiveFile.string(
          entity.fileName,
          _jsonLines(rowsByEntity[entity]!),
        ),
      );
    }

    return ZipEncoder().encode(archive, modified: createdAt);
  }

  Future<File> exportPortableArchiveToFile(
    File destination, {
    DateTime? createdAt,
    PortableArchiveEncryptionOptions? encryption,
  }) async {
    final bytes = await exportPortableArchive(
      createdAt: createdAt,
      encryption: encryption,
    );
    await destination.parent.create(recursive: true);
    return destination.writeAsBytes(bytes, flush: true);
  }

  Future<PortableArchiveManifest> inspectPortableArchive(
    List<int> bytes, {
    String? passphrase,
  }) async {
    return (await _readSnapshot(bytes, passphrase: passphrase)).manifest;
  }

  Future<PortableArchiveImportResult> importPortableArchive(
    List<int> bytes, {
    String? passphrase,
    String actor = importActor,
  }) async {
    final snapshot = await _readSnapshot(bytes, passphrase: passphrase);
    final changedRowsByTable = <String, int>{};
    final skippedRowsByTable = <String, int>{};
    final changedExerciseIds = <String>{};
    final context = _repositories._createWriteContext(actor: actor);
    final entities = _entities;
    final routineEntryEntity = entities.singleWhere(
      (entity) => entity.tableName == AppDatabase.routineEntriesTable,
    );
    final pendingActivities = <String, _PendingPortableActivity>{};
    final sourceCadencesByRoutineId = <String, Cadence?>{
      for (final value in snapshot.rowsByTable[AppDatabase.planRoutinesTable]!)
        (value as PlanRoutineRow).id: _cadenceFromRow(value),
    };
    final sourceWonRoutineEntryIds = <String>{};

    await _database.transaction(() async {
      final localCadencesByRoutineId = <String, Cadence?>{
        for (final routine
            in await _database.select(_database.planRoutines).get())
          routine.id: _cadenceFromRow(routine),
      };
      for (final entity in entities) {
        final rows = snapshot.rowsByTable[entity.tableName]!;
        for (final row in _rowsInMergeOrder(entity, rows)) {
          final existing = await entity.findById(entity.idOf(row));
          if (existing != null &&
              entity.updatedAtOf(existing).isAfter(entity.updatedAtOf(row))) {
            _increment(skippedRowsByTable, entity.tableName);
            continue;
          }
          if (existing != null && entity.hasSamePortableImage(existing, row)) {
            _increment(skippedRowsByTable, entity.tableName);
            continue;
          }

          await entity.upsert(row);
          changedExerciseIds.addAll(entity.affectedExerciseIdsOf(row));

          if (entity.tableName == AppDatabase.activityLogTable) {
            _increment(changedRowsByTable, entity.tableName);
            continue;
          }
          final entityId = entity.idOf(row);
          if (_recordPendingPortableActivity(
            pendingActivities,
            entity: entity,
            entityId: entityId,
            beforeImage: existing == null ? null : entity.imageOf(existing),
          )) {
            _increment(changedRowsByTable, entity.tableName);
          }
          if (entity.tableName == AppDatabase.routineEntriesTable) {
            sourceWonRoutineEntryIds.add(entityId);
          }
        }
      }
      await _normalizeStoredRoutineEntryPositions(
        context,
        changedRowsByTable,
        pendingActivities,
        routineEntryEntity,
      );
      await _reconcileStoredRoutineEntrySlots(
        context,
        changedRowsByTable,
        pendingActivities,
        routineEntryEntity,
        localCadencesByRoutineId: localCadencesByRoutineId,
        sourceCadencesByRoutineId: sourceCadencesByRoutineId,
        sourceWonRoutineEntryIds: sourceWonRoutineEntryIds,
      );
      await _validateStoredTemplateGroupGraph();
      await _validateStoredRoutinePlanGraph();
      await _appendPendingPortableActivities(context, pendingActivities);
    });

    return PortableArchiveImportResult(
      changedRowsByTable: Map<String, int>.unmodifiable(changedRowsByTable),
      skippedRowsByTable: Map<String, int>.unmodifiable(skippedRowsByTable),
      changedExerciseIds: Set<String>.unmodifiable(changedExerciseIds),
    );
  }

  Iterable<Object> _rowsInMergeOrder(
    _PortableArchiveEntity entity,
    List<Object> rows,
  ) {
    if (entity.tableName != AppDatabase.templateGroupMembersTable) {
      return rows;
    }
    final ordered = rows.cast<TemplateGroupMemberRow>().toList()
      ..sort((left, right) {
        final leftRank = left.deletedAt == null ? 1 : 0;
        final rightRank = right.deletedAt == null ? 1 : 0;
        final lifecycle = leftRank.compareTo(rightRank);
        return lifecycle != 0 ? lifecycle : left.id.compareTo(right.id);
      });
    return ordered;
  }

  Future<void> _validateStoredTemplateGroupGraph() async {
    final templates = await _database.select(_database.workoutTemplates).get();
    final exercises = await _database.select(_database.templateExercises).get();
    final groups = await _database.select(_database.templateGroups).get();
    final members =
        await _database.select(_database.templateGroupMembers).get();
    _validatePortableTemplateGroupGraph(<String, List<Object>>{
      AppDatabase.workoutTemplatesTable: List<Object>.of(templates),
      AppDatabase.templateExercisesTable: List<Object>.of(exercises),
      AppDatabase.templateGroupsTable: List<Object>.of(groups),
      AppDatabase.templateGroupMembersTable: List<Object>.of(members),
    });
  }

  Future<void> _validateStoredRoutinePlanGraph() async {
    final templates = await _database.select(_database.workoutTemplates).get();
    final routines = await _database.select(_database.planRoutines).get();
    final entries = await _database.select(_database.routineEntries).get();
    _validatePortableRoutinePlanGraph(<String, List<Object>>{
      AppDatabase.workoutTemplatesTable: List<Object>.of(templates),
      AppDatabase.planRoutinesTable: List<Object>.of(routines),
      AppDatabase.routineEntriesTable: List<Object>.of(entries),
    });
  }

  Future<void> _normalizeStoredRoutineEntryPositions(
    _WriteContext context,
    Map<String, int> changedRowsByTable,
    Map<String, _PendingPortableActivity> pendingActivities,
    _PortableArchiveEntity routineEntryEntity,
  ) async {
    final rows = await (_database.select(_database.routineEntries)
          ..where((row) => row.deletedAt.isNull())
          ..orderBy([
            (row) => OrderingTerm.asc(row.routineId),
            (row) => OrderingTerm.asc(row.position),
            (row) => OrderingTerm.asc(row.id),
          ]))
        .get();
    final nextPositionByRoutine = <String, int>{};
    for (final before in rows) {
      final position = nextPositionByRoutine[before.routineId] ?? 0;
      nextPositionByRoutine[before.routineId] = position + 1;
      if (before.position == position) {
        continue;
      }
      final updatedAt = context.timestamp.isAfter(before.updatedAt)
          ? context.timestamp
          : before.updatedAt.add(const Duration(seconds: 1));
      await (_database.update(_database.routineEntries)
            ..where((row) => row.id.equals(before.id)))
          .write(
        RoutineEntriesCompanion(
          position: Value<int>(position),
          updatedAt: Value<DateTime>(updatedAt),
        ),
      );
      if (_recordPendingPortableActivity(
        pendingActivities,
        entity: routineEntryEntity,
        entityId: before.id,
        beforeImage: _routineEntryImage(before),
      )) {
        _increment(changedRowsByTable, AppDatabase.routineEntriesTable);
      }
    }
  }

  Future<void> _reconcileStoredRoutineEntrySlots(
    _WriteContext context,
    Map<String, int> changedRowsByTable,
    Map<String, _PendingPortableActivity> pendingActivities,
    _PortableArchiveEntity routineEntryEntity, {
    required Map<String, Cadence?> localCadencesByRoutineId,
    required Map<String, Cadence?> sourceCadencesByRoutineId,
    required Set<String> sourceWonRoutineEntryIds,
  }) async {
    final routines = <String, PlanRoutineRow>{
      for (final routine
          in await _database.select(_database.planRoutines).get())
        routine.id: routine,
    };
    final cadences = <String, Cadence?>{};
    for (final routine in routines.values) {
      final cadenceResult = plan_validation.validateRoutineCadence(
        cadenceKind: routine.cadenceKind,
        cadenceWindow: routine.cadenceWindow,
        slots: const <int?>[],
      );
      if (!cadenceResult.accepted) {
        throw PortableArchiveException(
          'Stored Routine has an invalid Cadence '
          '(${cadenceResult.errors.first.rule}).',
        );
      }
      cadences[routine.id] = _cadenceFromRow(routine);
    }
    final rows = await (_database.select(_database.routineEntries)
          ..where((row) => row.deletedAt.isNull())
          ..orderBy([
            (row) => OrderingTerm.asc(row.routineId),
            (row) => OrderingTerm.asc(row.position),
            (row) => OrderingTerm.asc(row.id),
          ]))
        .get();
    for (final before in rows) {
      final routine = routines[before.routineId];
      if (routine == null) {
        throw const PortableArchiveException(
          'Stored Routine Entry references a missing Routine.',
        );
      }
      final cadence = cadences[before.routineId];
      final authoredCadences = sourceWonRoutineEntryIds.contains(before.id)
          ? sourceCadencesByRoutineId
          : localCadencesByRoutineId;
      if (!authoredCadences.containsKey(before.routineId)) {
        throw const PortableArchiveException(
          'Stored Routine Entry has no authored Cadence context.',
        );
      }
      final authoredCadence = authoredCadences[before.routineId];
      final cadenceMeaningChanged = !_cadencesEqual(authoredCadence, cadence);
      final slot = cadenceMeaningChanged
          ? _defaultRoutineEntrySlot(before.position, cadence)
          : _reconciledRoutineEntrySlot(
              before.slot,
              position: before.position,
              cadence: cadence,
            );
      if (!cadenceMeaningChanged && before.slot == slot) {
        continue;
      }
      final updatedAt = context.timestamp.isAfter(before.updatedAt)
          ? context.timestamp
          : before.updatedAt.add(const Duration(seconds: 1));
      await (_database.update(_database.routineEntries)
            ..where((row) => row.id.equals(before.id)))
          .write(
        RoutineEntriesCompanion(
          slot: Value<int?>(slot),
          updatedAt: Value<DateTime>(updatedAt),
        ),
      );
      if (_recordPendingPortableActivity(
        pendingActivities,
        entity: routineEntryEntity,
        entityId: before.id,
        beforeImage: _routineEntryImage(before),
      )) {
        _increment(changedRowsByTable, AppDatabase.routineEntriesTable);
      }
    }
  }

  bool _recordPendingPortableActivity(
    Map<String, _PendingPortableActivity> pendingActivities, {
    required _PortableArchiveEntity entity,
    required String entityId,
    required Map<String, Object?>? beforeImage,
  }) {
    final key = '${entity.tableName}\u0000$entityId';
    if (pendingActivities.containsKey(key)) {
      return false;
    }
    pendingActivities[key] = _PendingPortableActivity(
      entity: entity,
      entityId: entityId,
      beforeImage: beforeImage,
    );
    return true;
  }

  Future<void> _appendPendingPortableActivities(
    _WriteContext context,
    Map<String, _PendingPortableActivity> pendingActivities,
  ) async {
    for (final pending in pendingActivities.values) {
      final current = await pending.entity.findById(pending.entityId);
      await _repositories.activityLog._append(
        context,
        entityTable: pending.entity.tableName,
        entityId: pending.entityId,
        beforeImage: pending.beforeImage,
        afterImage: current == null ? null : pending.entity.imageOf(current),
      );
    }
  }

  Future<PortableArchiveImportResult> importPortableArchiveFromFile(
    File source, {
    String? passphrase,
    String actor = importActor,
  }) async {
    return importPortableArchive(
      await source.readAsBytes(),
      passphrase: passphrase,
      actor: actor,
    );
  }

  Future<List<int>> _encryptArchive(
    List<int> plaintext, {
    required String passphrase,
    required DateTime createdAt,
  }) async {
    final normalizedPassphrase = _normalizeArchivePassphrase(passphrase);
    final salt = _secureRandomBytes(_saltLength);
    final algorithm = AesGcm.with256bits();
    final nonce = algorithm.newNonce();
    final secretKey = await _deriveArchiveKey(
      normalizedPassphrase,
      salt,
      iterations: keyDerivationIterations,
    );
    final secretBox = await algorithm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );
    final manifest = PortableArchiveEncryptedManifest(
      formatVersion: _encryptedArchiveFormatVersion,
      encryptionAlgorithm: _encryptionAlgorithm,
      keyDerivationAlgorithm: _kdfAlgorithm,
      keyDerivationIterations: keyDerivationIterations,
      salt: salt,
      nonce: nonce,
      mac: secretBox.mac.bytes,
      createdAt: createdAt,
    );
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          encryptedManifestFileName,
          jsonEncode(manifest.toJson()),
        ),
      )
      ..addFile(
        ArchiveFile.bytes(encryptedPayloadFileName, secretBox.cipherText),
      );

    return ZipEncoder().encode(archive, modified: createdAt);
  }

  List<_PortableArchiveEntity> get _entities => <_PortableArchiveEntity>[
        _TypedPortableArchiveEntity<ExerciseCategoryRow>(
          tableName: AppDatabase.exerciseCategoriesTable,
          selectRows: () {
            final query = _database.select(_database.exerciseCategories)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: ExerciseCategoryRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.exerciseCategories)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.exerciseCategories)
              .insert(row, mode: InsertMode.insertOrReplace),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _exerciseCategoryImage,
        ),
        _TypedPortableArchiveEntity<ExerciseRow>(
          tableName: AppDatabase.exercisesTable,
          selectRows: () {
            final query = _database.select(_database.exercises)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: ExerciseRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.exercises)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.exercises)
              .insert(row, mode: InsertMode.insertOrReplace),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _exerciseImage,
          affectedExerciseIdsOf: (row) => <String>[row.id],
        ),
        _TypedPortableArchiveEntity<WorkoutSessionRow>(
          tableName: AppDatabase.workoutSessionsTable,
          selectRows: () {
            final query = _database.select(_database.workoutSessions)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: WorkoutSessionRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.workoutSessions)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.workoutSessions)
              .insert(row, mode: InsertMode.insertOrReplace),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _workoutSessionImage,
        ),
        _TypedPortableArchiveEntity<MealTypeRow>(
          tableName: AppDatabase.mealTypesTable,
          selectRows: () {
            final query = _database.select(_database.mealTypes)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: MealTypeRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.mealTypes)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database.into(_database.mealTypes).insert(
                row,
                mode: InsertMode.insertOrReplace,
              ),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _mealTypeImage,
        ),
        _TypedPortableArchiveEntity<MealRow>(
          tableName: AppDatabase.mealsTable,
          selectRows: () {
            final query = _database.select(_database.meals)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: MealRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.meals)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database.into(_database.meals).insert(
                row,
                mode: InsertMode.insertOrReplace,
              ),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _mealImage,
        ),
        _TypedPortableArchiveEntity<FoodRow>(
          tableName: AppDatabase.foodsTable,
          selectRows: () {
            final query = _database.select(_database.foods)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: FoodRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.foods)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database.into(_database.foods).insert(
                row,
                mode: InsertMode.insertOrReplace,
              ),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _foodImage,
        ),
        _TypedPortableArchiveEntity<FoodEntryRow>(
          tableName: AppDatabase.foodEntriesTable,
          selectRows: () {
            final query = _database.select(_database.foodEntries)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: FoodEntryRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.foodEntries)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database.into(_database.foodEntries).insert(
                row,
                mode: InsertMode.insertOrReplace,
              ),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _foodEntryImage,
        ),
        _TypedPortableArchiveEntity<NutritionGoalRow>(
          tableName: AppDatabase.nutritionGoalsTable,
          selectRows: () {
            final query = _database.select(_database.nutritionGoals)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: NutritionGoalRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.nutritionGoals)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database.into(_database.nutritionGoals).insert(
                row,
                mode: InsertMode.insertOrReplace,
              ),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _nutritionGoalImage,
        ),
        _TypedPortableArchiveEntity<UserSettingsRow>(
          tableName: AppDatabase.userSettingsTable,
          selectRows: () {
            final query = _database.select(_database.userSettings)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: UserSettingsRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.userSettings)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database.into(_database.userSettings).insert(
                row,
                mode: InsertMode.insertOrReplace,
              ),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _userSettingsImage,
        ),
        _TypedPortableArchiveEntity<WorkoutExerciseRow>(
          tableName: AppDatabase.workoutExercisesTable,
          selectRows: () {
            final query = _database.select(_database.workoutExercises)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: WorkoutExerciseRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.workoutExercises)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.workoutExercises)
              .insert(row, mode: InsertMode.insertOrReplace),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _workoutExerciseImage,
          affectedExerciseIdsOf: (row) => <String>[row.exerciseId],
        ),
        _TypedPortableArchiveEntity<ExerciseGroupRow>(
          tableName: AppDatabase.exerciseGroupsTable,
          selectRows: () {
            final query = _database.select(_database.exerciseGroups)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: ExerciseGroupRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.exerciseGroups)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.exerciseGroups)
              .insert(row, mode: InsertMode.insertOrReplace),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _exerciseGroupImage,
        ),
        _TypedPortableArchiveEntity<ExerciseGroupMemberRow>(
          tableName: AppDatabase.exerciseGroupMembersTable,
          selectRows: () {
            final query = _database.select(_database.exerciseGroupMembers)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: ExerciseGroupMemberRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.exerciseGroupMembers)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.exerciseGroupMembers)
              .insert(row, mode: InsertMode.insertOrReplace),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _exerciseGroupMemberImage,
        ),
        _TypedPortableArchiveEntity<WorkoutTemplateRow>(
          tableName: AppDatabase.workoutTemplatesTable,
          selectRows: () {
            final query = _database.select(_database.workoutTemplates)
              ..orderBy([(row) => OrderingTerm.asc(row.id)]);
            return query.get();
          },
          fromJson: WorkoutTemplateRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.workoutTemplates)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.workoutTemplates)
              .insertOnConflictUpdate(row),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _portableWorkoutTemplateImage,
        ),
        _TypedPortableArchiveEntity<TemplateExerciseRow>(
          tableName: AppDatabase.templateExercisesTable,
          selectRows: () {
            final query = _database.select(_database.templateExercises)
              ..orderBy([(row) => OrderingTerm.asc(row.id)]);
            return query.get();
          },
          fromJson: TemplateExerciseRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.templateExercises)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.templateExercises)
              .insertOnConflictUpdate(row),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _portableTemplateExerciseImage,
          affectedExerciseIdsOf: (row) => <String>[row.exerciseId],
        ),
        _TypedPortableArchiveEntity<TemplateGroupRow>(
          tableName: AppDatabase.templateGroupsTable,
          selectRows: () {
            final query = _database.select(_database.templateGroups)
              ..orderBy([(row) => OrderingTerm.asc(row.id)]);
            return query.get();
          },
          fromJson: TemplateGroupRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.templateGroups)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.templateGroups)
              .insertOnConflictUpdate(row),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _portableTemplateGroupImage,
        ),
        _TypedPortableArchiveEntity<TemplateGroupMemberRow>(
          tableName: AppDatabase.templateGroupMembersTable,
          selectRows: () {
            final query = _database.select(_database.templateGroupMembers)
              ..orderBy([(row) => OrderingTerm.asc(row.id)]);
            return query.get();
          },
          fromJson: TemplateGroupMemberRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.templateGroupMembers)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.templateGroupMembers)
              .insertOnConflictUpdate(row),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _portableTemplateGroupMemberImage,
        ),
        _TypedPortableArchiveEntity<PlanRoutineRow>(
          tableName: AppDatabase.planRoutinesTable,
          selectRows: () {
            final query = _database.select(_database.planRoutines)
              ..orderBy([(row) => OrderingTerm.asc(row.id)]);
            return query.get();
          },
          fromJson: PlanRoutineRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.planRoutines)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.planRoutines)
              .insertOnConflictUpdate(row),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _planRoutineImage,
        ),
        _TypedPortableArchiveEntity<RoutineEntryRow>(
          tableName: AppDatabase.routineEntriesTable,
          selectRows: () {
            final query = _database.select(_database.routineEntries)
              ..orderBy([(row) => OrderingTerm.asc(row.id)]);
            return query.get();
          },
          fromJson: RoutineEntryRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.routineEntries)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.routineEntries)
              .insertOnConflictUpdate(row),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _routineEntryImage,
        ),
        _TypedPortableArchiveEntity<PrescriptionRow>(
          tableName: AppDatabase.prescriptionsTable,
          selectRows: () {
            final query = _database.select(_database.prescriptions)
              ..orderBy([(row) => OrderingTerm.asc(row.id)]);
            return query.get();
          },
          fromJson: PrescriptionRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.prescriptions)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.prescriptions)
              .insertOnConflictUpdate(row),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _portablePrescriptionImage,
          validateRow: _validatePortablePrescriptionRow,
        ),
        _TypedPortableArchiveEntity<TemplateLinkRow>(
          tableName: AppDatabase.templateLinksTable,
          selectRows: () {
            final query = _database.select(_database.templateLinks)
              ..orderBy([(row) => OrderingTerm.asc(row.id)]);
            return query.get();
          },
          fromJson: TemplateLinkRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.templateLinks)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.templateLinks)
              .insertOnConflictUpdate(row),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _portableTemplateLinkImage,
        ),
        _TypedPortableArchiveEntity<LoggedSetRow>(
          tableName: AppDatabase.loggedSetsTable,
          selectRows: () {
            final query = _database.select(_database.loggedSets)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: LoggedSetRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.loggedSets)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.loggedSets)
              .insert(row, mode: InsertMode.insertOrReplace),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _loggedSetImage,
          affectedExerciseIdsOf: (row) => <String>[row.exerciseId],
        ),
        _TypedPortableArchiveEntity<RestTimerRow>(
          tableName: AppDatabase.restTimersTable,
          selectRows: () {
            final query = _database.select(_database.restTimers)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: RestTimerRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.restTimers)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.restTimers)
              .insert(row, mode: InsertMode.insertOrReplace),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _restTimerImage,
        ),
        _TypedPortableArchiveEntity<IntervalTimerRow>(
          tableName: AppDatabase.intervalTimersTable,
          selectRows: () {
            final query = _database.select(_database.intervalTimers)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: IntervalTimerRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.intervalTimers)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.intervalTimers)
              .insert(row, mode: InsertMode.insertOrReplace),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _intervalTimerImage,
        ),
        _TypedPortableArchiveEntity<MeasurementRow>(
          tableName: AppDatabase.measurementsTable,
          selectRows: () {
            final query = _database.select(_database.measurements)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: MeasurementRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.measurements)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.measurements)
              .insert(row, mode: InsertMode.insertOrReplace),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _measurementImage,
        ),
        _TypedPortableArchiveEntity<MeasurementEntryRow>(
          tableName: AppDatabase.measurementEntriesTable,
          selectRows: () {
            final query = _database.select(_database.measurementEntries)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: MeasurementEntryRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.measurementEntries)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.measurementEntries)
              .insert(row, mode: InsertMode.insertOrReplace),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _measurementEntryImage,
        ),
        _TypedPortableArchiveEntity<MetricRow>(
          tableName: AppDatabase.metricsTable,
          selectRows: () {
            final query = _database.select(_database.metrics)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: MetricRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.metrics)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.metrics)
              .insert(row, mode: InsertMode.insertOrReplace),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _metricImage,
        ),
        _TypedPortableArchiveEntity<MetricReadingRow>(
          tableName: AppDatabase.metricReadingsTable,
          selectRows: () {
            final query = _database.select(_database.metricReadings)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: MetricReadingRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.metricReadings)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.metricReadings)
              .insert(row, mode: InsertMode.insertOrReplace),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _metricReadingImage,
        ),
        // Protocols rides the same merge-only LWW backup rails. Kept in the
        // encrypted portable archive so a user keeps a complete sovereign
        // backup (PROTOCOLS.md §8) even though Protocols is excluded from CSV.
        _TypedPortableArchiveEntity<CompoundRow>(
          tableName: AppDatabase.compoundsTable,
          selectRows: () {
            final query = _database.select(_database.compounds)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: CompoundRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.compounds)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.compounds)
              .insert(row, mode: InsertMode.insertOrReplace),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _compoundImage,
        ),
        _TypedPortableArchiveEntity<DoseRow>(
          tableName: AppDatabase.dosesTable,
          selectRows: () {
            final query = _database.select(_database.doses)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: DoseRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.doses)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.doses)
              .insert(row, mode: InsertMode.insertOrReplace),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _doseImage,
        ),
        // The `Protocol` plan-layer entity (PROTOCOLS.md §1.4) rides
        // the same merge-only backup rails: kept in the encrypted portable
        // archive so a user keeps a complete sovereign backup, even though a
        // Protocol is excluded from CSV like the rest of the domain.
        _TypedPortableArchiveEntity<ProtocolRow>(
          tableName: AppDatabase.protocolsTable,
          selectRows: () {
            final query = _database.select(_database.protocols)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: ProtocolRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.protocols)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.protocols)
              .insert(row, mode: InsertMode.insertOrReplace),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _protocolImage,
        ),
        _TypedPortableArchiveEntity<ProtocolCompoundRow>(
          tableName: AppDatabase.protocolCompoundsTable,
          selectRows: () {
            final query = _database.select(_database.protocolCompounds)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: ProtocolCompoundRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.protocolCompounds)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.protocolCompounds)
              .insert(row, mode: InsertMode.insertOrReplace),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _protocolCompoundImage,
        ),
        // The OPTIONAL `Schedule` per member Compound (PROTOCOLS.md
        // §1.4) rides the same merge-only backup rails as the rest of the
        // Protocols domain: kept in the encrypted portable archive for a
        // complete sovereign backup, excluded from CSV like the rest.
        _TypedPortableArchiveEntity<ScheduleRow>(
          tableName: AppDatabase.schedulesTable,
          selectRows: () {
            final query = _database.select(_database.schedules)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: ScheduleRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.schedules)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.schedules)
              .insert(row, mode: InsertMode.insertOrReplace),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _scheduleImage,
        ),
        // A Protocol's declared target outcomes (PROTOCOLS.md §1.4,
        // §4) ride the same merge-only backup rails: kept in the encrypted
        // portable archive for a complete sovereign backup, excluded from CSV
        // like the rest of the domain.
        _TypedPortableArchiveEntity<ProtocolTargetOutcomeRow>(
          tableName: AppDatabase.protocolTargetOutcomesTable,
          selectRows: () {
            final query = _database.select(_database.protocolTargetOutcomes)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: ProtocolTargetOutcomeRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.protocolTargetOutcomes)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.protocolTargetOutcomes)
              .insert(row, mode: InsertMode.insertOrReplace),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _protocolTargetOutcomeImage,
        ),
        _TypedPortableArchiveEntity<ActivityLogRow>(
          tableName: AppDatabase.activityLogTable,
          selectRows: () {
            final query = _database.select(_database.activityLog)
              ..orderBy([
                (row) => OrderingTerm.asc(row.id),
              ]);
            return query.get();
          },
          fromJson: ActivityLogRow.fromJson,
          toJson: (row) => row.toJson(),
          findById: (id) {
            final query = _database.select(_database.activityLog)
              ..where((row) => row.id.equals(id));
            return query.getSingleOrNull();
          },
          upsert: (row) => _database
              .into(_database.activityLog)
              .insert(row, mode: InsertMode.insertOrReplace),
          idOf: (row) => row.id,
          updatedAtOf: (row) => row.updatedAt,
          imageOf: _activityLogImage,
        ),
      ];

  Future<_PortableArchiveSnapshot> _readSnapshot(
    List<int> bytes, {
    String? passphrase,
  }) async {
    final archiveBytes = await _decryptArchiveIfNeeded(
      bytes,
      passphrase: passphrase,
    );
    final archive = _decodeZip(archiveBytes);
    final manifest = _readManifest(archive);
    _validateManifest(manifest);

    final rowsByTable = <String, List<Object>>{};
    final manifestEntities = <String, PortableArchiveEntityManifest>{
      for (final entity in manifest.entities) entity.tableName: entity,
    };
    if (manifestEntities.length != manifest.entities.length) {
      throw const PortableArchiveException(
        'Archive manifest contains duplicate entity entries.',
      );
    }

    for (final entity in _entities) {
      final manifestEntity = manifestEntities[entity.tableName];
      if (manifestEntity == null) {
        if (_mayBeAbsentFromArchive(
          entity.tableName,
          archiveSchemaVersion: manifest.schemaVersion,
        )) {
          rowsByTable[entity.tableName] = const <Object>[];
          continue;
        }
        throw PortableArchiveException(
          'Archive manifest is missing ${entity.tableName}.',
        );
      }
      if (manifestEntity.fileName != entity.fileName) {
        throw PortableArchiveException(
          'Archive manifest file mismatch for ${entity.tableName}.',
        );
      }

      final archiveFile = archive.findFile(entity.fileName);
      if (archiveFile == null) {
        throw PortableArchiveException(
          'Archive is missing ${entity.fileName}.',
        );
      }

      final rows = _decodeRows(entity, archiveFile);
      if (rows.length != manifestEntity.rowCount) {
        throw PortableArchiveException(
          'Archive row count mismatch for ${entity.tableName}.',
        );
      }
      rowsByTable[entity.tableName] = rows;
    }

    // Before schema 53, Template Link routine IDs belonged to an unfinished
    // seam with no referential target. Treat those opaque values as absent so
    // old archives preserve the Template Link instead of failing the new
    // Plan Routine foreign-key graph.
    if (manifest.schemaVersion < 53) {
      final templateLinks = rowsByTable[AppDatabase.templateLinksTable]!
          .cast<TemplateLinkRow>()
          .map(
            (row) => row.routineId == null
                ? row
                : row.copyWith(routineId: const Value<String?>(null)),
          )
          .toList(growable: false);
      rowsByTable[AppDatabase.templateLinksTable] =
          List<Object>.of(templateLinks);
    }

    _validatePortableTemplateExerciseUniqueness(
      rowsByTable[AppDatabase.templateExercisesTable]!,
    );
    _validatePortableTemplateGroupGraph(rowsByTable);
    _validatePortableRoutinePlanGraph(rowsByTable);

    return _PortableArchiveSnapshot(
      manifest: manifest,
      rowsByTable: Map<String, List<Object>>.unmodifiable(rowsByTable),
    );
  }

  Archive _decodeZip(List<int> bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes);
    } catch (error) {
      throw PortableArchiveException(
        'Archive is not a readable zip file.',
        cause: error,
      );
    }
  }

  PortableArchiveManifest _readManifest(Archive archive) {
    final manifestFile = archive.findFile(manifestFileName);
    if (manifestFile == null) {
      throw const PortableArchiveException(
        'Archive is missing manifest.json.',
      );
    }

    try {
      return PortableArchiveManifest.fromJson(
        _decodeJsonObject(utf8.decode(manifestFile.content)),
      );
    } catch (error) {
      if (error is PortableArchiveException) {
        rethrow;
      }
      throw PortableArchiveException(
        'Archive manifest is invalid.',
        cause: error,
      );
    }
  }

  void _validateManifest(PortableArchiveManifest manifest) {
    if (manifest.formatVersion != archiveFormatVersion) {
      throw PortableArchiveException(
        'Archive format ${manifest.formatVersion} is not supported.',
      );
    }
    if (manifest.schemaVersion > _database.schemaVersion) {
      throw PortableArchiveException(
        'Archive schema ${manifest.schemaVersion} is newer than this app.',
      );
    }
    final expectedTableNames =
        _entities.map((entity) => entity.tableName).toSet();
    if (manifest.entities.any(
      (entity) => !expectedTableNames.contains(entity.tableName),
    )) {
      throw const PortableArchiveException(
        'Archive manifest has an unexpected entity set.',
      );
    }
  }

  bool _mayBeAbsentFromArchive(
    String tableName, {
    required int archiveSchemaVersion,
  }) {
    if (archiveSchemaVersion < 51 &&
        (tableName == AppDatabase.workoutTemplatesTable ||
            tableName == AppDatabase.templateExercisesTable ||
            tableName == AppDatabase.prescriptionsTable ||
            tableName == AppDatabase.templateLinksTable)) {
      return true;
    }
    if (archiveSchemaVersion < 52 &&
        (tableName == AppDatabase.templateGroupsTable ||
            tableName == AppDatabase.templateGroupMembersTable)) {
      return true;
    }
    return archiveSchemaVersion < 53 &&
        (tableName == AppDatabase.planRoutinesTable ||
            tableName == AppDatabase.routineEntriesTable);
  }

  List<Object> _decodeRows(
    _PortableArchiveEntity entity,
    ArchiveFile archiveFile,
  ) {
    final content = utf8.decode(archiveFile.content).trimRight();
    if (content.isEmpty) {
      return const <Object>[];
    }

    final rows = <Object>[];
    final lines = content.split('\n');
    for (var index = 0; index < lines.length; index += 1) {
      try {
        rows.add(entity.rowFromJson(_decodeJsonObject(lines[index])));
      } catch (error) {
        if (error is PortableArchiveException) {
          rethrow;
        }
        throw PortableArchiveException(
          'Archive row ${index + 1} is invalid in ${entity.fileName}.',
          cause: error,
        );
      }
    }

    return List<Object>.unmodifiable(rows);
  }

  Future<List<int>> _decryptArchiveIfNeeded(
    List<int> bytes, {
    required String? passphrase,
  }) async {
    final outerArchive = _decodeZip(bytes);
    final encryptedManifestFile =
        outerArchive.findFile(encryptedManifestFileName);
    if (encryptedManifestFile == null) {
      return bytes;
    }

    final payloadFile = outerArchive.findFile(encryptedPayloadFileName);
    if (payloadFile == null) {
      throw const PortableArchiveException(
        'Encrypted archive is missing its payload.',
      );
    }
    if (passphrase == null || passphrase.isEmpty) {
      throw const PortableArchiveException(
        'This archive is encrypted and needs a passphrase.',
      );
    }

    final encryptedManifest = _readEncryptedManifest(encryptedManifestFile);
    _validateEncryptedManifest(encryptedManifest);

    try {
      final algorithm = AesGcm.with256bits();
      final secretKey = await _deriveArchiveKey(
        _normalizeArchivePassphrase(passphrase),
        encryptedManifest.salt,
        iterations: encryptedManifest.keyDerivationIterations,
      );
      return await algorithm.decrypt(
        SecretBox(
          payloadFile.content,
          nonce: encryptedManifest.nonce,
          mac: Mac(encryptedManifest.mac),
        ),
        secretKey: secretKey,
      );
    } catch (error) {
      throw PortableArchiveException(
        'Could not decrypt archive. Check the passphrase and archive integrity.',
        cause: error,
      );
    }
  }

  PortableArchiveEncryptedManifest _readEncryptedManifest(
    ArchiveFile manifestFile,
  ) {
    try {
      return PortableArchiveEncryptedManifest.fromJson(
        _decodeJsonObject(utf8.decode(manifestFile.content)),
      );
    } catch (error) {
      if (error is PortableArchiveException) {
        rethrow;
      }
      throw PortableArchiveException(
        'Encrypted archive manifest is invalid.',
        cause: error,
      );
    }
  }

  void _validateEncryptedManifest(PortableArchiveEncryptedManifest manifest) {
    if (manifest.formatVersion != _encryptedArchiveFormatVersion) {
      throw PortableArchiveException(
        'Encrypted archive format ${manifest.formatVersion} is not supported.',
      );
    }
    if (manifest.encryptionAlgorithm != _encryptionAlgorithm) {
      throw PortableArchiveException(
        'Encrypted archive algorithm ${manifest.encryptionAlgorithm} '
        'is not supported.',
      );
    }
    if (manifest.keyDerivationAlgorithm != _kdfAlgorithm) {
      throw PortableArchiveException(
        'Encrypted archive key derivation '
        '${manifest.keyDerivationAlgorithm} is not supported.',
      );
    }
    if (manifest.keyDerivationIterations < minimumKeyDerivationIterations) {
      throw PortableArchiveException(
        'Encrypted archive iteration count '
        '${manifest.keyDerivationIterations} is below the supported minimum.',
      );
    }
  }

  Future<SecretKey> _deriveArchiveKey(
    String passphrase,
    List<int> salt, {
    required int iterations,
  }) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKeyFromPassword(
      password: passphrase,
      nonce: salt,
    );
  }
}

class PortableArchiveEncryptionOptions {
  const PortableArchiveEncryptionOptions({required this.passphrase});

  static const forgottenPassphraseWarning =
      'Encryption is optional. If you forget this passphrase, this backup '
      'cannot be recovered.';

  final String passphrase;
}

class PortableArchiveManifest {
  PortableArchiveManifest({
    required this.formatVersion,
    required this.schemaVersion,
    required this.appVersion,
    required this.createdAt,
    required List<PortableArchiveEntityManifest> entities,
  }) : entities = List<PortableArchiveEntityManifest>.unmodifiable(entities);

  final int formatVersion;
  final int schemaVersion;
  final String appVersion;
  final DateTime createdAt;
  final List<PortableArchiveEntityManifest> entities;

  factory PortableArchiveManifest.fromJson(Map<String, Object?> json) {
    return PortableArchiveManifest(
      formatVersion: _requiredInt(json, 'formatVersion'),
      schemaVersion: _requiredInt(json, 'schemaVersion'),
      appVersion: _requiredString(json, 'appVersion'),
      createdAt: _requiredDateTime(json, 'createdAt'),
      entities: List<PortableArchiveEntityManifest>.unmodifiable(
        _requiredList(json, 'entities').map(
          (entry) => PortableArchiveEntityManifest.fromJson(
            _requireJsonObject(entry, 'entities entry'),
          ),
        ),
      ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'formatVersion': formatVersion,
      'schemaVersion': schemaVersion,
      'appVersion': appVersion,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'entities': entities.map((entity) => entity.toJson()).toList(),
    };
  }
}

class PortableArchiveEncryptedManifest {
  PortableArchiveEncryptedManifest({
    required this.formatVersion,
    required this.encryptionAlgorithm,
    required this.keyDerivationAlgorithm,
    required this.keyDerivationIterations,
    required List<int> salt,
    required List<int> nonce,
    required List<int> mac,
    required this.createdAt,
  })  : salt = List<int>.unmodifiable(salt),
        nonce = List<int>.unmodifiable(nonce),
        mac = List<int>.unmodifiable(mac);

  final int formatVersion;
  final String encryptionAlgorithm;
  final String keyDerivationAlgorithm;
  final int keyDerivationIterations;
  final List<int> salt;
  final List<int> nonce;
  final List<int> mac;
  final DateTime createdAt;

  factory PortableArchiveEncryptedManifest.fromJson(
    Map<String, Object?> json,
  ) {
    return PortableArchiveEncryptedManifest(
      formatVersion: _requiredInt(json, 'formatVersion'),
      encryptionAlgorithm: _requiredString(json, 'encryption'),
      keyDerivationAlgorithm: _requiredString(json, 'kdf'),
      keyDerivationIterations: _requiredInt(json, 'iterations'),
      salt: _requiredBase64Bytes(json, 'salt'),
      nonce: _requiredBase64Bytes(json, 'nonce'),
      mac: _requiredBase64Bytes(json, 'mac'),
      createdAt: _requiredDateTime(json, 'createdAt'),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'formatVersion': formatVersion,
      'encryption': encryptionAlgorithm,
      'kdf': keyDerivationAlgorithm,
      'iterations': keyDerivationIterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'mac': base64Encode(mac),
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }
}

class PortableArchiveEntityManifest {
  const PortableArchiveEntityManifest({
    required this.tableName,
    required this.fileName,
    required this.rowCount,
  });

  final String tableName;
  final String fileName;
  final int rowCount;

  factory PortableArchiveEntityManifest.fromJson(Map<String, Object?> json) {
    return PortableArchiveEntityManifest(
      tableName: _requiredString(json, 'table'),
      fileName: _requiredString(json, 'file'),
      rowCount: _requiredInt(json, 'rows'),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'table': tableName,
      'file': fileName,
      'rows': rowCount,
    };
  }
}

class PortableArchiveImportResult {
  PortableArchiveImportResult({
    required Map<String, int> changedRowsByTable,
    required Map<String, int> skippedRowsByTable,
    required Set<String> changedExerciseIds,
  })  : changedRowsByTable = Map<String, int>.unmodifiable(
          changedRowsByTable,
        ),
        skippedRowsByTable = Map<String, int>.unmodifiable(
          skippedRowsByTable,
        ),
        changedExerciseIds = Set<String>.unmodifiable(changedExerciseIds);

  final Map<String, int> changedRowsByTable;
  final Map<String, int> skippedRowsByTable;
  final Set<String> changedExerciseIds;
}

class PortableArchiveException implements Exception {
  const PortableArchiveException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    final causedBy = cause == null ? '' : ' ($cause)';
    return 'PortableArchiveException: $message$causedBy';
  }
}

class _PortableArchiveSnapshot {
  const _PortableArchiveSnapshot({
    required this.manifest,
    required this.rowsByTable,
  });

  final PortableArchiveManifest manifest;
  final Map<String, List<Object>> rowsByTable;
}

final class _PendingPortableActivity {
  const _PendingPortableActivity({
    required this.entity,
    required this.entityId,
    required this.beforeImage,
  });

  final _PortableArchiveEntity entity;
  final String entityId;
  final Map<String, Object?>? beforeImage;
}

abstract class _PortableArchiveEntity {
  String get tableName;
  String get fileName;

  Future<List<Map<String, Object?>>> exportRows();
  Object rowFromJson(Map<String, Object?> json);
  Future<Object?> findById(String id);
  Future<void> upsert(Object row);
  String idOf(Object row);
  DateTime updatedAtOf(Object row);
  Map<String, Object?> imageOf(Object row);
  Iterable<String> affectedExerciseIdsOf(Object row);
  bool hasSamePortableImage(Object left, Object right);
}

class _TypedPortableArchiveEntity<T extends Object>
    implements _PortableArchiveEntity {
  _TypedPortableArchiveEntity({
    required this.tableName,
    required this.selectRows,
    required this.fromJson,
    required this.toJson,
    required Future<T?> Function(String id) findById,
    required Future<void> Function(T row) upsert,
    required String Function(T row) idOf,
    required DateTime Function(T row) updatedAtOf,
    required Map<String, Object?> Function(T row) imageOf,
    Iterable<String> Function(T row)? affectedExerciseIdsOf,
    void Function(T row)? validateRow,
  })  : findByIdRow = findById,
        upsertRow = upsert,
        idOfRow = idOf,
        updatedAtOfRow = updatedAtOf,
        imageOfRow = imageOf,
        affectedExerciseIdsOfRow =
            affectedExerciseIdsOf ?? _emptyAffectedExerciseIds,
        validateRowValue = validateRow;

  @override
  final String tableName;
  final Future<List<T>> Function() selectRows;
  final T Function(Map<String, dynamic>) fromJson;
  final Map<String, dynamic> Function(T) toJson;
  final Future<T?> Function(String id) findByIdRow;
  final Future<void> Function(T row) upsertRow;
  final String Function(T row) idOfRow;
  final DateTime Function(T row) updatedAtOfRow;
  final Map<String, Object?> Function(T row) imageOfRow;
  final Iterable<String> Function(T row) affectedExerciseIdsOfRow;
  final void Function(T row)? validateRowValue;

  @override
  String get fileName => PortableArchiveRepository.entityFileName(tableName);

  @override
  Future<List<Map<String, Object?>>> exportRows() async {
    final rows = await selectRows();
    return rows
        .map((row) => Map<String, Object?>.unmodifiable(toJson(row)))
        .toList(growable: false);
  }

  @override
  Object rowFromJson(Map<String, Object?> json) {
    final row = fromJson(Map<String, dynamic>.from(json));
    validateRowValue?.call(row);
    return row;
  }

  @override
  Future<Object?> findById(String id) {
    return findByIdRow(id);
  }

  @override
  Future<void> upsert(Object row) {
    return upsertRow(row as T);
  }

  @override
  String idOf(Object row) {
    return idOfRow(row as T);
  }

  @override
  DateTime updatedAtOf(Object row) {
    return updatedAtOfRow(row as T);
  }

  @override
  Map<String, Object?> imageOf(Object row) {
    return imageOfRow(row as T);
  }

  @override
  Iterable<String> affectedExerciseIdsOf(Object row) {
    return affectedExerciseIdsOfRow(row as T);
  }

  @override
  bool hasSamePortableImage(Object left, Object right) {
    return jsonEncode(toJson(left as T)) == jsonEncode(toJson(right as T));
  }
}

Iterable<String> _emptyAffectedExerciseIds<T>(T _) {
  return const <String>[];
}

void _validatePortablePrescriptionRow(PrescriptionRow row) {
  final values = _prescriptionValuesFromRow(row);
  final mode = row.mode == 'copy-previous' ? 'copyPrevious' : row.mode;
  plan_validation
      .validatePrescription(
        mode: mode,
        dimensions: values.dimensionIds,
        loadMode: ExerciseLoadMode.added,
        repeat: row.repeat,
        restAfterSeconds: row.restAfter,
        values: values.values.values,
      )
      .throwIfRejected();
}

void _validatePortableTemplateExerciseUniqueness(List<Object> rows) {
  final activeKeys = <(String, String)>{};
  for (final value in rows) {
    final row = value as TemplateExerciseRow;
    if (row.deletedAt != null) {
      continue;
    }
    final key = (row.workoutTemplateId, row.exerciseId);
    if (!activeKeys.add(key)) {
      throw const PortableArchiveException(
        'Archive contains duplicate active Template Exercises.',
      );
    }
  }
}

void _validatePortableTemplateGroupGraph(
  Map<String, List<Object>> rowsByTable,
) {
  final templates = <String, WorkoutTemplateRow>{
    for (final value in rowsByTable[AppDatabase.workoutTemplatesTable]!)
      (value as WorkoutTemplateRow).id: value,
  };
  final exercises = <String, TemplateExerciseRow>{
    for (final value in rowsByTable[AppDatabase.templateExercisesTable]!)
      (value as TemplateExerciseRow).id: value,
  };
  final groups = <String, TemplateGroupRow>{
    for (final value in rowsByTable[AppDatabase.templateGroupsTable]!)
      (value as TemplateGroupRow).id: value,
  };
  final members = rowsByTable[AppDatabase.templateGroupMembersTable]!
      .cast<TemplateGroupMemberRow>();
  final activeMembersByGroup = <String, List<TemplateGroupMemberRow>>{};
  final activeMembershipByExercise = <String, TemplateGroupMemberRow>{};

  for (final group in groups.values) {
    if (!templates.containsKey(group.workoutTemplateId)) {
      throw const PortableArchiveException(
        'Archive Template Group references a missing Workout Template.',
      );
    }
  }
  for (final member in members) {
    final group = groups[member.groupId];
    final exercise = exercises[member.templateExerciseId];
    if (group == null || exercise == null) {
      throw const PortableArchiveException(
        'Archive Template Group member has a missing parent.',
      );
    }
    if (group.workoutTemplateId != exercise.workoutTemplateId) {
      throw const PortableArchiveException(
        'Archive Template Group members must belong to the same '
        'Workout Template.',
      );
    }
    if (member.deletedAt != null) {
      continue;
    }
    if (group.deletedAt != null || exercise.deletedAt != null) {
      throw const PortableArchiveException(
        'Archive contains an active Template Group membership under an '
        'archived row.',
      );
    }
    final duplicate = activeMembershipByExercise[member.templateExerciseId];
    if (duplicate != null && duplicate.id != member.id) {
      throw const PortableArchiveException(
        'Archive contains a Template Exercise in more than one active '
        'Template Group.',
      );
    }
    activeMembershipByExercise[member.templateExerciseId] = member;
    activeMembersByGroup
        .putIfAbsent(group.id, () => <TemplateGroupMemberRow>[])
        .add(member);
  }

  for (final group in groups.values) {
    final activeMembers =
        activeMembersByGroup[group.id] ?? const <TemplateGroupMemberRow>[];
    final validationMemberIds = group.deletedAt == null
        ? activeMembers.map((member) => member.templateExerciseId)
        : <String>[
            '${group.id}:archived-member-1',
            '${group.id}:archived-member-2',
          ];
    try {
      plan_validation
          .validateTemplateGroup(
            name: group.name,
            colorHex: group.colorHex,
            rounds: group.rounds,
            memberIds: validationMemberIds,
          )
          .throwIfRejected();
    } catch (error) {
      throw PortableArchiveException(
        'Archive contains invalid Template Group content.',
        cause: error,
      );
    }
    if (group.deletedAt == null) {
      _requireNormalizedPortablePositions(
        activeMembers.map((member) => member.position),
        label: 'Template Group member',
      );
    }
  }

  final activeGroupsByTemplate = <String, List<TemplateGroupRow>>{};
  for (final group in groups.values.where((row) => row.deletedAt == null)) {
    activeGroupsByTemplate
        .putIfAbsent(group.workoutTemplateId, () => <TemplateGroupRow>[])
        .add(group);
  }
  for (final entry in activeGroupsByTemplate.entries) {
    _requireNormalizedPortablePositions(
      entry.value.map((group) => group.position),
      label: 'Template Group',
    );
  }
}

void _requireNormalizedPortablePositions(
  Iterable<int> positions, {
  required String label,
}) {
  final sorted = positions.toList(growable: false)..sort();
  for (var index = 0; index < sorted.length; index += 1) {
    if (sorted[index] != index) {
      throw PortableArchiveException(
        'Archive $label positions must be normalized.',
      );
    }
  }
}

void _validatePortableRoutinePlanGraph(
  Map<String, List<Object>> rowsByTable,
) {
  final templates = <String, WorkoutTemplateRow>{
    for (final value in rowsByTable[AppDatabase.workoutTemplatesTable]!)
      (value as WorkoutTemplateRow).id: value,
  };
  final routines = <String, PlanRoutineRow>{
    for (final value in rowsByTable[AppDatabase.planRoutinesTable]!)
      (value as PlanRoutineRow).id: value,
  };
  final activeEntriesByRoutine = <String, List<RoutineEntryRow>>{};

  for (final routine in routines.values) {
    if (routine.name.trim().isEmpty) {
      throw const PortableArchiveException(
        'Archive contains a Routine without a name.',
      );
    }
  }
  for (final value in rowsByTable[AppDatabase.routineEntriesTable]!) {
    final entry = value as RoutineEntryRow;
    if (!routines.containsKey(entry.routineId) ||
        !templates.containsKey(entry.workoutTemplateId)) {
      throw const PortableArchiveException(
        'Archive Routine Entry references a missing parent.',
      );
    }
    if (entry.deletedAt != null) {
      continue;
    }
    // An archived Routine keeps its Entries and an archived Workout Template
    // remains referenced/restorable, so lifecycle state is intentionally not
    // part of this parent check.
    activeEntriesByRoutine
        .putIfAbsent(entry.routineId, () => <RoutineEntryRow>[])
        .add(entry);
  }

  for (final routine in routines.values) {
    final entries =
        activeEntriesByRoutine[routine.id] ?? const <RoutineEntryRow>[];
    final cadenceResult = plan_validation.validateRoutineCadence(
      cadenceKind: routine.cadenceKind,
      cadenceWindow: routine.cadenceWindow,
      slots: entries.map((entry) => entry.slot),
    );
    if (!cadenceResult.accepted) {
      throw PortableArchiveException(
        'Archive contains an invalid Routine Cadence or slot '
        '(${cadenceResult.errors.first.rule}).',
      );
    }
  }

  for (final entry in activeEntriesByRoutine.entries) {
    _requireNormalizedPortablePositions(
      entry.value.map((row) => row.position),
      label: 'Routine Entry',
    );
  }
}

Map<String, Object?> _portableWorkoutTemplateImage(WorkoutTemplateRow row) {
  return <String, Object?>{
    'id': row.id,
    'name': row.name,
    'notes': row.notes,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _portableTemplateExerciseImage(TemplateExerciseRow row) {
  return <String, Object?>{
    'id': row.id,
    'workout_template_id': row.workoutTemplateId,
    'exercise_id': row.exerciseId,
    'position': row.position,
    'note': row.note,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _portableTemplateGroupImage(TemplateGroupRow row) {
  return <String, Object?>{
    'id': row.id,
    'workout_template_id': row.workoutTemplateId,
    'name': row.name,
    'color_hex': row.colorHex,
    'rounds': row.rounds,
    'position': row.position,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _portableTemplateGroupMemberImage(
  TemplateGroupMemberRow row,
) {
  return <String, Object?>{
    'id': row.id,
    'group_id': row.groupId,
    'template_exercise_id': row.templateExerciseId,
    'position': row.position,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _portablePrescriptionImage(PrescriptionRow row) {
  return <String, Object?>{
    'id': row.id,
    'template_exercise_id': row.templateExerciseId,
    'mode': row.mode,
    'position': row.position,
    'repeat': row.repeat,
    'rest_after': row.restAfter,
    'load_value': row.loadValue,
    'load_unit': row.loadUnit,
    'load_entered': row.loadEntered,
    'reps_value': row.repsValue,
    'reps_unit': row.repsUnit,
    'reps_entered': row.repsEntered,
    'duration_value': row.durationValue,
    'duration_unit': row.durationUnit,
    'duration_entered': row.durationEntered,
    'distance_value': row.distanceValue,
    'distance_unit': row.distanceUnit,
    'distance_entered': row.distanceEntered,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _portableTemplateLinkImage(TemplateLinkRow row) {
  return <String, Object?>{
    'id': row.id,
    'workout_id': row.workoutId,
    'workout_template_id': row.workoutTemplateId,
    'routine_id': row.routineId,
    'slot': row.slot,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

String _jsonLines(List<Map<String, Object?>> rows) {
  if (rows.isEmpty) {
    return '';
  }
  return '${rows.map(jsonEncode).join('\n')}\n';
}

Map<String, Object?> _decodeJsonObject(String content) {
  final decoded = jsonDecode(content);
  return _requireJsonObject(decoded, 'JSON object');
}

Map<String, Object?> _requireJsonObject(Object? value, String label) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw PortableArchiveException('Expected $label.');
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw PortableArchiveException('Manifest field $key must be an integer.');
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw PortableArchiveException('Manifest field $key must be a string.');
}

DateTime _requiredDateTime(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw PortableArchiveException('Manifest field $key must be a date.');
  }
  return parsed.toUtc();
}

List<int> _requiredBase64Bytes(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  try {
    return base64Decode(value);
  } catch (error) {
    throw PortableArchiveException(
      'Manifest field $key must be base64.',
      cause: error,
    );
  }
}

List<Object?> _requiredList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is List<Object?>) {
    return value;
  }
  if (value is List) {
    return List<Object?>.from(value);
  }
  throw PortableArchiveException('Manifest field $key must be a list.');
}

void _increment(Map<String, int> counts, String tableName) {
  counts[tableName] = (counts[tableName] ?? 0) + 1;
}

String _normalizeArchivePassphrase(String passphrase) {
  final normalized = passphrase.trim();
  if (normalized.isEmpty) {
    throw const PortableArchiveException(
      'Encrypted archive passphrase is required.',
    );
  }
  return normalized;
}

List<int> _secureRandomBytes(int length) {
  final random = math.Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}

Map<String, Object?> _activityLogImage(ActivityLogRow row) {
  return <String, Object?>{
    'id': row.id,
    'actor': row.actor,
    'batch_id': row.batchId,
    'entity_table': row.entityTable,
    'entity_id': row.entityId,
    'before_image': row.beforeImage,
    'after_image': row.afterImage,
    'occurred_at': _iso(row.occurredAt),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}
