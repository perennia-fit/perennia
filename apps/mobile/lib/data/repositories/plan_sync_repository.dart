part of 'training_repositories.dart';

/// Sync-only plan-tree writes. Ordinary plan repositories remain purely local;
/// this adapter is called only by the explicit sync coordinator.
extension PlanSyncActivityLogRepository on ActivityLogRepository {
  Future<bool> applyPlanSyncImage({
    required String entityTable,
    required Map<String, Object?> image,
    required String deviceId,
    required String localDeviceId,
    required String batchId,
    String actor = 'sync',
    String? activityLogId,
    Map<String, Object?>? activityBeforeImage,
    Map<String, Object?>? activityAfterImage,
    DateTime? activityOccurredAt,
  }) async {
    final id = _activityRequiredString(image, 'id');
    final incomingUpdatedAt = _activityRequiredDateTime(image, 'updated_at');
    final metadata = await _planSyncMetadata(entityTable, id);
    if (metadata != null &&
        !syncLwwWins(
          incomingUpdatedAt,
          deviceId,
          metadata.updatedAt,
          metadata.deviceId ?? localDeviceId,
        )) {
      return false;
    }

    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    final before = await _currentImageFor(
      entityTable: entityTable,
      entityId: id,
    );
    await _insertPlanSyncImage(
      entityTable: entityTable,
      image: image,
      deviceId: deviceId,
    );
    final after = await _currentImageFor(
      entityTable: entityTable,
      entityId: id,
    );
    if (before != null &&
        after != null &&
        _activityImagesEqual(before, after)) {
      return false;
    }
    await _append(
      context,
      entityTable: entityTable,
      entityId: id,
      beforeImage: activityBeforeImage ?? before,
      afterImage: activityAfterImage ?? after,
      id: activityLogId,
      occurredAt: activityOccurredAt,
      syncAcknowledgedAt: context.timestamp,
    );
    return true;
  }

  Future<void> markPlanRowsAbsentFromSnapshotDeleted({
    required String entityTable,
    required Set<String> liveSnapshotIds,
    required DateTime timestamp,
  }) async {
    for (final id in await _previouslySyncedLivePlanRowIds(entityTable)) {
      if (liveSnapshotIds.contains(id)) {
        continue;
      }
      await _writePlanTombstone(
        entityTable: entityTable,
        id: id,
        timestamp: timestamp,
      );
    }
  }

  Future<void> markPlanRowSynced({
    required String entityTable,
    required String id,
    String? deviceId,
    DateTime? updatedAt,
  }) {
    final syncDeviceId = deviceId == null
        ? const Value<String?>.absent()
        : Value<String?>(deviceId);
    final syncUpdatedAt = updatedAt == null
        ? const Value<DateTime>.absent()
        : Value<DateTime>(updatedAt);
    return switch (entityTable) {
      AppDatabase.workoutSessionsTable =>
        (_database.update(_database.workoutSessions)
              ..where((row) => row.id.equals(id)))
            .write(
          WorkoutSessionsCompanion(
            syncDeviceId: syncDeviceId,
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: syncUpdatedAt,
          ),
        ),
      AppDatabase.workoutExercisesTable =>
        (_database.update(_database.workoutExercises)
              ..where((row) => row.id.equals(id)))
            .write(
          WorkoutExercisesCompanion(
            syncDeviceId: syncDeviceId,
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: syncUpdatedAt,
          ),
        ),
      AppDatabase.exerciseGroupsTable =>
        (_database.update(_database.exerciseGroups)
              ..where((row) => row.id.equals(id)))
            .write(
          ExerciseGroupsCompanion(
            syncDeviceId: syncDeviceId,
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: syncUpdatedAt,
          ),
        ),
      AppDatabase.exerciseGroupMembersTable =>
        (_database.update(_database.exerciseGroupMembers)
              ..where((row) => row.id.equals(id)))
            .write(
          ExerciseGroupMembersCompanion(
            syncDeviceId: syncDeviceId,
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: syncUpdatedAt,
          ),
        ),
      AppDatabase.workoutTemplatesTable =>
        (_database.update(_database.workoutTemplates)
              ..where((row) => row.id.equals(id)))
            .write(
          WorkoutTemplatesCompanion(
            syncDeviceId: syncDeviceId,
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: syncUpdatedAt,
          ),
        ),
      AppDatabase.templateExercisesTable =>
        (_database.update(_database.templateExercises)
              ..where((row) => row.id.equals(id)))
            .write(
          TemplateExercisesCompanion(
            syncDeviceId: syncDeviceId,
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: syncUpdatedAt,
          ),
        ),
      AppDatabase.prescriptionsTable =>
        (_database.update(_database.prescriptions)
              ..where((row) => row.id.equals(id)))
            .write(
          PrescriptionsCompanion(
            syncDeviceId: syncDeviceId,
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: syncUpdatedAt,
          ),
        ),
      AppDatabase.templateGroupsTable =>
        (_database.update(_database.templateGroups)
              ..where((row) => row.id.equals(id)))
            .write(
          TemplateGroupsCompanion(
            syncDeviceId: syncDeviceId,
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: syncUpdatedAt,
          ),
        ),
      AppDatabase.templateGroupMembersTable =>
        (_database.update(_database.templateGroupMembers)
              ..where((row) => row.id.equals(id)))
            .write(
          TemplateGroupMembersCompanion(
            syncDeviceId: syncDeviceId,
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: syncUpdatedAt,
          ),
        ),
      AppDatabase.planRoutinesTable =>
        (_database.update(_database.planRoutines)
              ..where((row) => row.id.equals(id)))
            .write(
          PlanRoutinesCompanion(
            syncDeviceId: syncDeviceId,
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: syncUpdatedAt,
          ),
        ),
      AppDatabase.routineEntriesTable =>
        (_database.update(_database.routineEntries)
              ..where((row) => row.id.equals(id)))
            .write(
          RoutineEntriesCompanion(
            syncDeviceId: syncDeviceId,
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: syncUpdatedAt,
          ),
        ),
      AppDatabase.templateLinksTable =>
        (_database.update(_database.templateLinks)
              ..where((row) => row.id.equals(id)))
            .write(
          TemplateLinksCompanion(
            syncDeviceId: syncDeviceId,
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: syncUpdatedAt,
          ),
        ),
      _ => Future<void>.error(
          ArgumentError.value(
            entityTable,
            'entityTable',
            'Unsupported plan sync entity.',
          ),
        ),
    };
  }

  Future<_PlanSyncMetadata?> _planSyncMetadata(
    String entityTable,
    String id,
  ) async {
    return switch (entityTable) {
      AppDatabase.workoutSessionsTable =>
        (await (_database.select(_database.workoutSessions)
                  ..where((row) => row.id.equals(id)))
                .getSingleOrNull())
            ?._planSyncMetadata,
      AppDatabase.workoutExercisesTable =>
        (await (_database.select(_database.workoutExercises)
                  ..where((row) => row.id.equals(id)))
                .getSingleOrNull())
            ?._planSyncMetadata,
      AppDatabase.exerciseGroupsTable =>
        (await (_database.select(_database.exerciseGroups)
                  ..where((row) => row.id.equals(id)))
                .getSingleOrNull())
            ?._planSyncMetadata,
      AppDatabase.exerciseGroupMembersTable =>
        (await (_database.select(_database.exerciseGroupMembers)
                  ..where((row) => row.id.equals(id)))
                .getSingleOrNull())
            ?._planSyncMetadata,
      AppDatabase.workoutTemplatesTable =>
        (await (_database.select(_database.workoutTemplates)
                  ..where((row) => row.id.equals(id)))
                .getSingleOrNull())
            ?._planSyncMetadata,
      AppDatabase.templateExercisesTable =>
        (await (_database.select(_database.templateExercises)
                  ..where((row) => row.id.equals(id)))
                .getSingleOrNull())
            ?._planSyncMetadata,
      AppDatabase.prescriptionsTable =>
        (await (_database.select(_database.prescriptions)
                  ..where((row) => row.id.equals(id)))
                .getSingleOrNull())
            ?._planSyncMetadata,
      AppDatabase.templateGroupsTable =>
        (await (_database.select(_database.templateGroups)
                  ..where((row) => row.id.equals(id)))
                .getSingleOrNull())
            ?._planSyncMetadata,
      AppDatabase.templateGroupMembersTable =>
        (await (_database.select(_database.templateGroupMembers)
                  ..where((row) => row.id.equals(id)))
                .getSingleOrNull())
            ?._planSyncMetadata,
      AppDatabase.planRoutinesTable =>
        (await (_database.select(_database.planRoutines)
                  ..where((row) => row.id.equals(id)))
                .getSingleOrNull())
            ?._planSyncMetadata,
      AppDatabase.routineEntriesTable =>
        (await (_database.select(_database.routineEntries)
                  ..where((row) => row.id.equals(id)))
                .getSingleOrNull())
            ?._planSyncMetadata,
      AppDatabase.templateLinksTable =>
        (await (_database.select(_database.templateLinks)
                  ..where((row) => row.id.equals(id)))
                .getSingleOrNull())
            ?._planSyncMetadata,
      _ => throw ArgumentError.value(
          entityTable,
          'entityTable',
          'Unsupported plan sync entity.',
        ),
    };
  }

  Future<void> _insertPlanSyncImage({
    required String entityTable,
    required Map<String, Object?> image,
    required String deviceId,
  }) {
    return switch (entityTable) {
      AppDatabase.workoutSessionsTable => _database
          .into(_database.workoutSessions)
          .insertOnConflictUpdate(
            _workoutSessionSyncCompanionFromImage(
              image,
              syncDeviceId: deviceId,
            ),
          ),
      AppDatabase.workoutExercisesTable => _database
          .into(_database.workoutExercises)
          .insertOnConflictUpdate(
            _workoutExerciseSyncCompanionFromImage(
              image,
              syncDeviceId: deviceId,
            ),
          ),
      AppDatabase.exerciseGroupsTable => _database
          .into(_database.exerciseGroups)
          .insertOnConflictUpdate(
            _exerciseGroupSyncCompanionFromImage(
              image,
              syncDeviceId: deviceId,
            ),
          ),
      AppDatabase.exerciseGroupMembersTable => _database
          .into(_database.exerciseGroupMembers)
          .insertOnConflictUpdate(
            _exerciseGroupMemberSyncCompanionFromImage(
              image,
              syncDeviceId: deviceId,
            ),
          ),
      AppDatabase.workoutTemplatesTable => _database
          .into(_database.workoutTemplates)
          .insertOnConflictUpdate(
            _workoutTemplateSyncCompanionFromImage(
              image,
              syncDeviceId: deviceId,
            ),
          ),
      AppDatabase.templateExercisesTable => _database
          .into(_database.templateExercises)
          .insertOnConflictUpdate(
            _templateExerciseSyncCompanionFromImage(
              image,
              syncDeviceId: deviceId,
            ),
          ),
      AppDatabase.prescriptionsTable => _database
          .into(_database.prescriptions)
          .insertOnConflictUpdate(
            _prescriptionSyncCompanionFromImage(
              image,
              syncDeviceId: deviceId,
            ),
          ),
      AppDatabase.templateGroupsTable => _database
          .into(_database.templateGroups)
          .insertOnConflictUpdate(
            _templateGroupSyncCompanionFromImage(
              image,
              syncDeviceId: deviceId,
            ),
          ),
      AppDatabase.templateGroupMembersTable => _database
          .into(_database.templateGroupMembers)
          .insertOnConflictUpdate(
            _templateGroupMemberSyncCompanionFromImage(
              image,
              syncDeviceId: deviceId,
            ),
          ),
      AppDatabase.planRoutinesTable => _database
          .into(_database.planRoutines)
          .insertOnConflictUpdate(
            _planRoutineSyncCompanionFromImage(
              image,
              syncDeviceId: deviceId,
            ),
          ),
      AppDatabase.routineEntriesTable => _database
          .into(_database.routineEntries)
          .insertOnConflictUpdate(
            _routineEntrySyncCompanionFromImage(
              image,
              syncDeviceId: deviceId,
            ),
          ),
      AppDatabase.templateLinksTable => _insertTemplateLinkSyncImage(
          image: image,
          deviceId: deviceId,
        ),
      _ => Future<void>.error(
          ArgumentError.value(
            entityTable,
            'entityTable',
            'Unsupported plan sync entity.',
          ),
        ),
    };
  }

  Future<void> _insertTemplateLinkSyncImage({
    required Map<String, Object?> image,
    required String deviceId,
  }) async {
    await _ensureTemplateLinkWorkoutParent(image);
    await _ensureTemplateLinkWorkoutStructure(image);
    await _database.into(_database.templateLinks).insertOnConflictUpdate(
          _templateLinkSyncCompanionFromImage(
            image,
            syncDeviceId: deviceId,
          ),
        );
  }

  Future<void> _ensureTemplateLinkWorkoutStructure(
    Map<String, Object?> image,
  ) async {
    final workoutId = _activityRequiredString(image, 'workout_id');
    final workoutExercises = _planMaterializeSnapshotRows(
      image,
      'workout_exercises',
    );
    final exerciseGroups = _planMaterializeSnapshotRows(
      image,
      'workout_exercise_groups',
    );
    final exerciseGroupMembers = _planMaterializeSnapshotRows(
      image,
      'workout_exercise_group_members',
    );

    for (final workoutExercise in workoutExercises) {
      if (_activityRequiredString(workoutExercise, 'workout_id') != workoutId) {
        throw const FormatException(
          'Template Link Workout Exercise belongs to another Workout.',
        );
      }
      await _database.into(_database.workoutExercises).insert(
            _workoutExerciseCompanionFromImage(workoutExercise).copyWith(
              id: Value<String>(
                _activityRequiredString(workoutExercise, 'id'),
              ),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    for (final exerciseGroup in exerciseGroups) {
      if (_activityRequiredString(exerciseGroup, 'workout_id') != workoutId) {
        throw const FormatException(
          'Template Link Exercise Group belongs to another Workout.',
        );
      }
      await _database.into(_database.exerciseGroups).insert(
            _exerciseGroupCompanionFromImage(exerciseGroup).copyWith(
              id: Value<String>(_activityRequiredString(exerciseGroup, 'id')),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    for (final exerciseGroupMember in exerciseGroupMembers) {
      await _database.into(_database.exerciseGroupMembers).insert(
            _exerciseGroupMemberCompanionFromImage(
              exerciseGroupMember,
            ).copyWith(
              id: Value<String>(
                _activityRequiredString(exerciseGroupMember, 'id'),
              ),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  Future<void> _ensureTemplateLinkWorkoutParent(
    Map<String, Object?> image,
  ) async {
    final workoutId = _activityRequiredString(image, 'workout_id');
    final existing = await (_database.select(_database.workoutSessions)
          ..where((row) => row.id.equals(workoutId)))
        .getSingleOrNull();
    if (existing != null) {
      return;
    }

    final linkUpdatedAt = _activityRequiredDateTime(image, 'updated_at');
    final startedAt =
        _activityNullableDateTime(image, 'workout_started_at') ?? linkUpdatedAt;
    final timezone =
        _activityNullableString(image, 'workout_timezone') ?? 'UTC';
    final localDate = _activityNullableString(image, 'workout_local_date') ??
        TrainingDayDate.fromDateTime(startedAt).storageValue;

    await _database.into(_database.workoutSessions).insert(
          WorkoutSessionsCompanion.insert(
            id: workoutId,
            startedAt: startedAt,
            timezone: timezone,
            localDate: Value<String>(localDate),
            endedAt: Value<DateTime?>(
              _activityNullableDateTime(image, 'workout_ended_at'),
            ),
            comment: Value<String?>(
              _activityNullableString(image, 'workout_comment'),
            ),
            updatedAt: _activityNullableDateTime(image, 'workout_updated_at') ??
                linkUpdatedAt,
            deletedAt: Value<DateTime?>(
              _activityNullableDateTime(image, 'workout_deleted_at'),
            ),
          ),
        );
  }

  Future<List<String>> _previouslySyncedLivePlanRowIds(
    String entityTable,
  ) async {
    switch (entityTable) {
      case AppDatabase.workoutSessionsTable:
        final rows = await (_database.select(_database.workoutSessions)
              ..where(_previouslySyncedWorkoutSession))
            .get();
        return rows.map((row) => row.id).toList(growable: false);
      case AppDatabase.workoutExercisesTable:
        final rows = await (_database.select(_database.workoutExercises)
              ..where(_previouslySyncedWorkoutExercise))
            .get();
        return rows.map((row) => row.id).toList(growable: false);
      case AppDatabase.exerciseGroupsTable:
        final rows = await (_database.select(_database.exerciseGroups)
              ..where(_previouslySyncedExerciseGroup))
            .get();
        return rows.map((row) => row.id).toList(growable: false);
      case AppDatabase.exerciseGroupMembersTable:
        final rows = await (_database.select(_database.exerciseGroupMembers)
              ..where(_previouslySyncedExerciseGroupMember))
            .get();
        return rows.map((row) => row.id).toList(growable: false);
      case AppDatabase.workoutTemplatesTable:
        final rows = await (_database.select(_database.workoutTemplates)
              ..where(_previouslySyncedWorkoutTemplate))
            .get();
        return rows.map((row) => row.id).toList(growable: false);
      case AppDatabase.templateExercisesTable:
        final rows = await (_database.select(_database.templateExercises)
              ..where(_previouslySyncedTemplateExercise))
            .get();
        return rows.map((row) => row.id).toList(growable: false);
      case AppDatabase.prescriptionsTable:
        final rows = await (_database.select(_database.prescriptions)
              ..where(_previouslySyncedPrescription))
            .get();
        return rows.map((row) => row.id).toList(growable: false);
      case AppDatabase.templateGroupsTable:
        final rows = await (_database.select(_database.templateGroups)
              ..where(_previouslySyncedTemplateGroup))
            .get();
        return rows.map((row) => row.id).toList(growable: false);
      case AppDatabase.templateGroupMembersTable:
        final rows = await (_database.select(_database.templateGroupMembers)
              ..where(_previouslySyncedTemplateGroupMember))
            .get();
        return rows.map((row) => row.id).toList(growable: false);
      case AppDatabase.planRoutinesTable:
        final rows = await (_database.select(_database.planRoutines)
              ..where(_previouslySyncedPlanRoutine))
            .get();
        return rows.map((row) => row.id).toList(growable: false);
      case AppDatabase.routineEntriesTable:
        final rows = await (_database.select(_database.routineEntries)
              ..where(_previouslySyncedRoutineEntry))
            .get();
        return rows.map((row) => row.id).toList(growable: false);
      case AppDatabase.templateLinksTable:
        final rows = await (_database.select(_database.templateLinks)
              ..where(_previouslySyncedTemplateLink))
            .get();
        return rows.map((row) => row.id).toList(growable: false);
      default:
        throw ArgumentError.value(
          entityTable,
          'entityTable',
          'Unsupported plan sync entity.',
        );
    }
  }

  Future<void> _writePlanTombstone({
    required String entityTable,
    required String id,
    required DateTime timestamp,
  }) {
    final updatedAt = Value<DateTime>(timestamp);
    final deletedAt = Value<DateTime?>(timestamp);
    return switch (entityTable) {
      AppDatabase.workoutSessionsTable =>
        (_database.update(_database.workoutSessions)
              ..where((row) => row.id.equals(id)))
            .write(
          WorkoutSessionsCompanion(
            updatedAt: updatedAt,
            deletedAt: deletedAt,
          ),
        ),
      AppDatabase.workoutExercisesTable =>
        (_database.update(_database.workoutExercises)
              ..where((row) => row.id.equals(id)))
            .write(
          WorkoutExercisesCompanion(
            updatedAt: updatedAt,
            deletedAt: deletedAt,
          ),
        ),
      AppDatabase.exerciseGroupsTable =>
        (_database.update(_database.exerciseGroups)
              ..where((row) => row.id.equals(id)))
            .write(
          ExerciseGroupsCompanion(
            updatedAt: updatedAt,
            deletedAt: deletedAt,
          ),
        ),
      AppDatabase.exerciseGroupMembersTable =>
        (_database.update(_database.exerciseGroupMembers)
              ..where((row) => row.id.equals(id)))
            .write(
          ExerciseGroupMembersCompanion(
            updatedAt: updatedAt,
            deletedAt: deletedAt,
          ),
        ),
      AppDatabase.workoutTemplatesTable =>
        (_database.update(_database.workoutTemplates)
              ..where((row) => row.id.equals(id)))
            .write(
          WorkoutTemplatesCompanion(
            updatedAt: updatedAt,
            deletedAt: deletedAt,
          ),
        ),
      AppDatabase.templateExercisesTable =>
        (_database.update(_database.templateExercises)
              ..where((row) => row.id.equals(id)))
            .write(
          TemplateExercisesCompanion(
            updatedAt: updatedAt,
            deletedAt: deletedAt,
          ),
        ),
      AppDatabase.prescriptionsTable =>
        (_database.update(_database.prescriptions)
              ..where((row) => row.id.equals(id)))
            .write(
          PrescriptionsCompanion(
            updatedAt: updatedAt,
            deletedAt: deletedAt,
          ),
        ),
      AppDatabase.templateGroupsTable =>
        (_database.update(_database.templateGroups)
              ..where((row) => row.id.equals(id)))
            .write(
          TemplateGroupsCompanion(
            updatedAt: updatedAt,
            deletedAt: deletedAt,
          ),
        ),
      AppDatabase.templateGroupMembersTable =>
        (_database.update(_database.templateGroupMembers)
              ..where((row) => row.id.equals(id)))
            .write(
          TemplateGroupMembersCompanion(
            updatedAt: updatedAt,
            deletedAt: deletedAt,
          ),
        ),
      AppDatabase.planRoutinesTable =>
        (_database.update(_database.planRoutines)
              ..where((row) => row.id.equals(id)))
            .write(
          PlanRoutinesCompanion(
            updatedAt: updatedAt,
            deletedAt: deletedAt,
          ),
        ),
      AppDatabase.routineEntriesTable =>
        (_database.update(_database.routineEntries)
              ..where((row) => row.id.equals(id)))
            .write(
          RoutineEntriesCompanion(
            updatedAt: updatedAt,
            deletedAt: deletedAt,
          ),
        ),
      AppDatabase.templateLinksTable =>
        (_database.update(_database.templateLinks)
              ..where((row) => row.id.equals(id)))
            .write(
          TemplateLinksCompanion(
            updatedAt: updatedAt,
            deletedAt: deletedAt,
          ),
        ),
      _ => Future<void>.error(
          ArgumentError.value(
            entityTable,
            'entityTable',
            'Unsupported plan sync entity.',
          ),
        ),
    };
  }
}

Expression<bool> _previouslySyncedWorkoutSession($WorkoutSessionsTable row) =>
    row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull();

Expression<bool> _previouslySyncedWorkoutExercise($WorkoutExercisesTable row) =>
    row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull();

Expression<bool> _previouslySyncedExerciseGroup($ExerciseGroupsTable row) =>
    row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull();

Expression<bool> _previouslySyncedExerciseGroupMember(
  $ExerciseGroupMembersTable row,
) =>
    row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull();

Expression<bool> _previouslySyncedWorkoutTemplate(
  $WorkoutTemplatesTable row,
) =>
    row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull();

Expression<bool> _previouslySyncedTemplateExercise(
  $TemplateExercisesTable row,
) =>
    row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull();

Expression<bool> _previouslySyncedPrescription($PrescriptionsTable row) =>
    row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull();

Expression<bool> _previouslySyncedTemplateGroup($TemplateGroupsTable row) =>
    row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull();

Expression<bool> _previouslySyncedTemplateGroupMember(
  $TemplateGroupMembersTable row,
) =>
    row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull();

Expression<bool> _previouslySyncedPlanRoutine($PlanRoutinesTable row) =>
    row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull();

Expression<bool> _previouslySyncedRoutineEntry($RoutineEntriesTable row) =>
    row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull();

Expression<bool> _previouslySyncedTemplateLink($TemplateLinksTable row) =>
    row.syncPreviouslySynced.equals(true) & row.deletedAt.isNull();

WorkoutSessionsCompanion _workoutSessionSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) =>
    _workoutSessionCompanionFromImage(image).copyWith(
      id: Value<String>(_activityRequiredString(image, 'id')),
      syncDeviceId: Value<String?>(syncDeviceId),
      syncPreviouslySynced: const Value<bool>(true),
    );

WorkoutExercisesCompanion _workoutExerciseSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) =>
    _workoutExerciseCompanionFromImage(image).copyWith(
      id: Value<String>(_activityRequiredString(image, 'id')),
      syncDeviceId: Value<String?>(syncDeviceId),
      syncPreviouslySynced: const Value<bool>(true),
    );

ExerciseGroupsCompanion _exerciseGroupSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) =>
    _exerciseGroupCompanionFromImage(image).copyWith(
      id: Value<String>(_activityRequiredString(image, 'id')),
      syncDeviceId: Value<String?>(syncDeviceId),
      syncPreviouslySynced: const Value<bool>(true),
    );

ExerciseGroupMembersCompanion _exerciseGroupMemberSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) =>
    _exerciseGroupMemberCompanionFromImage(image).copyWith(
      id: Value<String>(_activityRequiredString(image, 'id')),
      syncDeviceId: Value<String?>(syncDeviceId),
      syncPreviouslySynced: const Value<bool>(true),
    );

WorkoutTemplatesCompanion _workoutTemplateSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) =>
    _workoutTemplateCompanionFromImage(image).copyWith(
      id: Value<String>(_activityRequiredString(image, 'id')),
      syncDeviceId: Value<String?>(syncDeviceId),
      syncPreviouslySynced: const Value<bool>(true),
    );

TemplateExercisesCompanion _templateExerciseSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) =>
    _templateExerciseCompanionFromImage(image).copyWith(
      id: Value<String>(_activityRequiredString(image, 'id')),
      syncDeviceId: Value<String?>(syncDeviceId),
      syncPreviouslySynced: const Value<bool>(true),
    );

PrescriptionsCompanion _prescriptionSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) =>
    _prescriptionCompanionFromImage(image).copyWith(
      id: Value<String>(_activityRequiredString(image, 'id')),
      syncDeviceId: Value<String?>(syncDeviceId),
      syncPreviouslySynced: const Value<bool>(true),
    );

TemplateGroupsCompanion _templateGroupSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) =>
    _templateGroupCompanionFromImage(image).copyWith(
      id: Value<String>(_activityRequiredString(image, 'id')),
      syncDeviceId: Value<String?>(syncDeviceId),
      syncPreviouslySynced: const Value<bool>(true),
    );

TemplateGroupMembersCompanion _templateGroupMemberSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) =>
    _templateGroupMemberCompanionFromImage(image).copyWith(
      id: Value<String>(_activityRequiredString(image, 'id')),
      syncDeviceId: Value<String?>(syncDeviceId),
      syncPreviouslySynced: const Value<bool>(true),
    );

PlanRoutinesCompanion _planRoutineSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) =>
    _planRoutineCompanionFromImage(image).copyWith(
      id: Value<String>(_activityRequiredString(image, 'id')),
      syncDeviceId: Value<String?>(syncDeviceId),
      syncPreviouslySynced: const Value<bool>(true),
    );

RoutineEntriesCompanion _routineEntrySyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) =>
    _routineEntryCompanionFromImage(image).copyWith(
      id: Value<String>(_activityRequiredString(image, 'id')),
      syncDeviceId: Value<String?>(syncDeviceId),
      syncPreviouslySynced: const Value<bool>(true),
    );

TemplateLinksCompanion _templateLinkSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) =>
    _templateLinkCompanionFromImage(image).copyWith(
      id: Value<String>(_activityRequiredString(image, 'id')),
      syncDeviceId: Value<String?>(syncDeviceId),
      syncPreviouslySynced: const Value<bool>(true),
    );

List<Map<String, Object?>> _planMaterializeSnapshotRows(
  Map<String, Object?> image,
  String field,
) {
  final value = image[field];
  if (value == null) {
    return const <Map<String, Object?>>[];
  }
  if (value is! List<Object?>) {
    throw FormatException('$field must be a list.');
  }
  return value.map((row) {
    if (row is! Map<Object?, Object?>) {
      throw FormatException('$field entries must be objects.');
    }
    return row.map(
      (key, value) => MapEntry<String, Object?>(key.toString(), value),
    );
  }).toList(growable: false);
}

final class _PlanSyncMetadata {
  const _PlanSyncMetadata(this.updatedAt, this.deviceId);

  final DateTime updatedAt;
  final String? deviceId;
}

extension on WorkoutSessionRow {
  _PlanSyncMetadata get _planSyncMetadata =>
      _PlanSyncMetadata(updatedAt.toUtc(), syncDeviceId);
}

extension on WorkoutExerciseRow {
  _PlanSyncMetadata get _planSyncMetadata =>
      _PlanSyncMetadata(updatedAt.toUtc(), syncDeviceId);
}

extension on ExerciseGroupRow {
  _PlanSyncMetadata get _planSyncMetadata =>
      _PlanSyncMetadata(updatedAt.toUtc(), syncDeviceId);
}

extension on ExerciseGroupMemberRow {
  _PlanSyncMetadata get _planSyncMetadata =>
      _PlanSyncMetadata(updatedAt.toUtc(), syncDeviceId);
}

extension on WorkoutTemplateRow {
  _PlanSyncMetadata get _planSyncMetadata =>
      _PlanSyncMetadata(updatedAt.toUtc(), syncDeviceId);
}

extension on TemplateExerciseRow {
  _PlanSyncMetadata get _planSyncMetadata =>
      _PlanSyncMetadata(updatedAt.toUtc(), syncDeviceId);
}

extension on PrescriptionRow {
  _PlanSyncMetadata get _planSyncMetadata =>
      _PlanSyncMetadata(updatedAt.toUtc(), syncDeviceId);
}

extension on TemplateGroupRow {
  _PlanSyncMetadata get _planSyncMetadata =>
      _PlanSyncMetadata(updatedAt.toUtc(), syncDeviceId);
}

extension on TemplateGroupMemberRow {
  _PlanSyncMetadata get _planSyncMetadata =>
      _PlanSyncMetadata(updatedAt.toUtc(), syncDeviceId);
}

extension on PlanRoutineRow {
  _PlanSyncMetadata get _planSyncMetadata =>
      _PlanSyncMetadata(updatedAt.toUtc(), syncDeviceId);
}

extension on RoutineEntryRow {
  _PlanSyncMetadata get _planSyncMetadata =>
      _PlanSyncMetadata(updatedAt.toUtc(), syncDeviceId);
}

extension on TemplateLinkRow {
  _PlanSyncMetadata get _planSyncMetadata =>
      _PlanSyncMetadata(updatedAt.toUtc(), syncDeviceId);
}
