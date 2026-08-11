part of 'training_repositories.dart';

/// Application/data boundary for save-as-new Workout capture.
///
/// Preview is read-only. Save always re-reads the authoritative Workout and
/// performs the complete Template tree plus optional Routine Entry in one
/// Drift transaction and one Activity Log batch.
final class WorkoutCaptureRepository {
  WorkoutCaptureRepository._(this._repositories)
      : _snapshotLoader = _WorkoutCaptureSnapshotLoader(
          _repositories.database,
        );

  final TrainingRepositories _repositories;
  final _WorkoutCaptureSnapshotLoader _snapshotLoader;

  AppDatabase get _database => _repositories.database;

  Future<WorkoutCapturePreview> preview(String workoutId) {
    return _database.transaction(() async {
      final loaded = await _snapshotLoader.load(workoutId);
      final content = captureWorkout(loaded.snapshot);
      return WorkoutCapturePreview(
        workoutId: workoutId,
        content: content,
        suggestedName: suggestCapturedWorkoutTemplateName(loaded.snapshot),
        exerciseCount: loaded.snapshot.exercises.length,
        setCount: loaded.snapshot.exercises.fold<int>(
          0,
          (total, exercise) => total + exercise.sets.length,
        ),
        groupCount: loaded.snapshot.groups.length,
        validation: _validateContent(loaded, content),
      );
    });
  }

  Future<WorkoutCaptureSaveResult> save(
    WorkoutCaptureSaveRequest request, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final normalizedName = _normalizeWorkoutTemplateName(request.name);
      final loaded = await _snapshotLoader.load(request.workoutId);
      final content = captureWorkout(loaded.snapshot);
      final placement = await _preparePlacement(request.placement);
      final validation = _mergeCaptureValidationResults(
        <WorkoutCaptureValidationResult>[
          _validateContent(loaded, content),
          if (placement != null) placement.validation,
        ],
      );
      if (!validation.accepted) {
        throw WorkoutCaptureValidationException(validation);
      }
      final authoritativeWarningTokens =
          validation.warningAcknowledgementTokenSet;
      if (!_sameCaptureWarningTokens(
        authoritativeWarningTokens,
        request.acknowledgedWarningTokens,
      )) {
        throw WorkoutCaptureWarningsNotAcknowledged(
          validation: validation,
          providedWarningTokens: request.acknowledgedWarningTokens,
        );
      }

      final templateWrite =
          await _repositories.workoutTemplates._createWithContent(
        WorkoutTemplateDraft(name: normalizedName),
        _workoutTemplateContentDraftFromCapture(content),
        context,
        exercisePolicy: _WorkoutTemplateContentExercisePolicy.historicalFact,
      );

      final routineEntryId = placement == null
          ? null
          : await _repositories.routinePlans._insertTemplateReferenceInContext(
              routineId: placement.routineId,
              workoutTemplateId: templateWrite.workoutTemplateId,
              requestedSlot: placement.slot,
              slotResolution: _RoutineEntrySlotResolution.exact,
              context: context,
            );
      return WorkoutCaptureSaveResult(
        workoutTemplateId: templateWrite.workoutTemplateId,
        routineEntryId: routineEntryId,
        activityBatchId: context.batchId,
      );
    });
  }

  WorkoutCaptureValidationResult _validateContent(
    _LoadedWorkoutCapture loaded,
    CapturedWorkoutTemplateContent content,
  ) {
    final results = <WorkoutCaptureValidationResult>[];
    for (var exerciseIndex = 0;
        exerciseIndex < content.exercises.length;
        exerciseIndex += 1) {
      final exercise = content.exercises[exerciseIndex];
      final source =
          _exerciseFromRow(loaded.exercisesById[exercise.exerciseId]!);
      for (var prescriptionIndex = 0;
          prescriptionIndex < exercise.prescriptions.length;
          prescriptionIndex += 1) {
        final prescription = exercise.prescriptions[prescriptionIndex];
        results.add(
          _captureValidationAtPath(
            plan_validation.validatePrescription(
              mode: CapturedPrescriptionContent.mode,
              // Exercise Type is an input template, never a history schema.
              // Historical capture validates the self-describing dimensions
              // that actually survived projection.
              dimensions: prescription.values.dimensionIds,
              loadMode: source.loadMode,
              repeat: prescription.repeat,
              restAfterSeconds: prescription.restAfter?.inSeconds,
              values: prescription.values.values.values,
            ),
            sourcePath:
                'exercises[$exerciseIndex].prescriptions[$prescriptionIndex]',
          ),
        );
      }
    }
    for (var groupIndex = 0;
        groupIndex < content.groups.length;
        groupIndex += 1) {
      final group = content.groups[groupIndex];
      results.add(
        _captureValidationAtPath(
          plan_validation.validateTemplateGroup(
            name: group.name,
            colorHex: group.colorHex,
            rounds: CapturedTemplateGroupContent.rounds,
            memberIds: group.memberExerciseIndexes.map(
              (index) => content.exercises[index].exerciseId,
            ),
          ),
          sourcePath: 'groups[$groupIndex]',
        ),
      );
    }
    return _mergeCaptureValidationResults(results);
  }

  Future<_PreparedWorkoutCapturePlacement?> _preparePlacement(
    WorkoutCapturePlacement placement,
  ) async {
    final (routineId, requestedSlot) = switch (placement) {
      WorkoutCaptureNoPlacement() => (null, null),
      WorkoutCaptureCollectionAppendPlacement(:final routineId) => (
          routineId,
          null
        ),
      WorkoutCaptureCadenceSlotPlacement(
        :final routineId,
        :final slot,
      ) =>
        (routineId, slot),
    };
    if (routineId == null) {
      return null;
    }

    final routine =
        await _repositories.routinePlans._requireActiveRoutineRow(routineId);
    final entries =
        await _repositories.routinePlans._activeEntryRows(routineId);
    _requireNormalizedRoutineEntryPositions(entries);
    final cadence = _cadenceFromRow(routine);
    return _PreparedWorkoutCapturePlacement(
      routineId: routineId,
      slot: requestedSlot,
      validation: _captureValidationAtPath(
        _validateRoutineCadence(
          cadence,
          slots: <int?>[
            ...entries.map((entry) => entry.slot),
            requestedSlot,
          ],
        ),
        sourcePath: 'placement',
      ),
    );
  }
}

/// Reusable authoritative fact loader for capture, divergence, and update-back.
final class _WorkoutCaptureSnapshotLoader {
  const _WorkoutCaptureSnapshotLoader(this._database);

  final AppDatabase _database;

  Future<_LoadedWorkoutCapture> load(String workoutId) async {
    final workout = await _requireActiveWorkout(workoutId);
    final workoutExercises = await _activeWorkoutExercises(workoutId);
    final exercisesById = await _exercisesById(workoutExercises);
    final setsByExerciseId = await _activeSetsByExercise(
      workoutId,
      activeExerciseIds: exercisesById.keys.toSet(),
    );
    final groups = await _activeGroups(workoutId);
    final membersByGroupId = await _activeMembersByGroup(groups);
    return _LoadedWorkoutCapture(
      snapshot: _mapSnapshot(
        workout: workout,
        workoutExercises: workoutExercises,
        exercisesById: exercisesById,
        setsByExerciseId: setsByExerciseId,
        groups: groups,
        membersByGroupId: membersByGroupId,
      ),
      exercisesById: exercisesById,
    );
  }

  Future<WorkoutSessionRow> _requireActiveWorkout(String workoutId) async {
    final workout = await (_database.select(_database.workoutSessions)
          ..where((row) => row.id.equals(workoutId)))
        .getSingleOrNull();
    if (workout == null) {
      throw StateError('Workout not found: $workoutId.');
    }
    if (workout.deletedAt != null) {
      throw StateError('Workout is deleted: $workoutId.');
    }
    return workout;
  }

  Future<List<WorkoutExerciseRow>> _activeWorkoutExercises(
    String workoutId,
  ) {
    return (_database.select(_database.workoutExercises)
          ..where(
            (row) => row.workoutId.equals(workoutId) & row.deletedAt.isNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.position),
            (row) => OrderingTerm.asc(row.id),
          ]))
        .get();
  }

  Future<Map<String, ExerciseRow>> _exercisesById(
    List<WorkoutExerciseRow> workoutExercises,
  ) async {
    final exerciseIds = workoutExercises
        .map((workoutExercise) => workoutExercise.exerciseId)
        .toSet();
    final exerciseRows = exerciseIds.isEmpty
        ? <ExerciseRow>[]
        : await (_database.select(_database.exercises)
              ..where((row) => row.id.isIn(exerciseIds)))
            .get();
    final exercisesById = <String, ExerciseRow>{
      for (final exercise in exerciseRows) exercise.id: exercise,
    };
    if (exercisesById.length != exerciseIds.length) {
      throw StateError('Workout references an Exercise that does not exist.');
    }
    return Map<String, ExerciseRow>.unmodifiable(exercisesById);
  }

  Future<Map<String, List<LoggedSetRow>>> _activeSetsByExercise(
    String workoutId, {
    required Set<String> activeExerciseIds,
  }) async {
    final sets = await (_database.select(_database.loggedSets)
          ..where(
            (row) => row.workoutId.equals(workoutId) & row.deletedAt.isNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.position),
            (row) => OrderingTerm.asc(row.id),
          ]))
        .get();
    if (sets.any((set) => !activeExerciseIds.contains(set.exerciseId))) {
      throw StateError(
        'Workout has an active Set without an active Workout Exercise.',
      );
    }
    final setsByExerciseId = <String, List<LoggedSetRow>>{};
    for (final set in sets) {
      setsByExerciseId
          .putIfAbsent(set.exerciseId, () => <LoggedSetRow>[])
          .add(set);
    }
    return Map<String, List<LoggedSetRow>>.unmodifiable(
      setsByExerciseId.map(
        (exerciseId, rows) => MapEntry(
          exerciseId,
          List<LoggedSetRow>.unmodifiable(rows),
        ),
      ),
    );
  }

  Future<List<ExerciseGroupRow>> _activeGroups(String workoutId) {
    return (_database.select(_database.exerciseGroups)
          ..where(
            (row) => row.workoutId.equals(workoutId) & row.deletedAt.isNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.position),
            (row) => OrderingTerm.asc(row.id),
          ]))
        .get();
  }

  Future<Map<String, List<ExerciseGroupMemberRow>>> _activeMembersByGroup(
    List<ExerciseGroupRow> groups,
  ) async {
    final groupIds = groups.map((group) => group.id).toSet();
    final rows = groupIds.isEmpty
        ? <ExerciseGroupMemberRow>[]
        : await (_database.select(_database.exerciseGroupMembers)
              ..where(
                (row) => row.groupId.isIn(groupIds) & row.deletedAt.isNull(),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.groupId),
                (row) => OrderingTerm.asc(row.position),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    final membersByGroupId = <String, List<ExerciseGroupMemberRow>>{};
    for (final row in rows) {
      membersByGroupId
          .putIfAbsent(row.groupId, () => <ExerciseGroupMemberRow>[])
          .add(row);
    }
    return Map<String, List<ExerciseGroupMemberRow>>.unmodifiable(
      membersByGroupId.map(
        (groupId, members) => MapEntry(
          groupId,
          List<ExerciseGroupMemberRow>.unmodifiable(members),
        ),
      ),
    );
  }

  WorkoutCaptureSnapshot _mapSnapshot({
    required WorkoutSessionRow workout,
    required List<WorkoutExerciseRow> workoutExercises,
    required Map<String, ExerciseRow> exercisesById,
    required Map<String, List<LoggedSetRow>> setsByExerciseId,
    required List<ExerciseGroupRow> groups,
    required Map<String, List<ExerciseGroupMemberRow>> membersByGroupId,
  }) {
    return WorkoutCaptureSnapshot(
      workoutId: workout.id,
      comment: workout.comment,
      startedAt: workout.startedAt.toUtc(),
      endedAt: workout.endedAt?.toUtc(),
      exercises: workoutExercises.map((workoutExercise) {
        final exercise = exercisesById[workoutExercise.exerciseId]!;
        return WorkoutCaptureExerciseSnapshot(
          sourceWorkoutExerciseId: workoutExercise.id,
          exerciseId: exercise.id,
          exerciseName: exercise.name,
          position: workoutExercise.position,
          sets: (setsByExerciseId[exercise.id] ?? const <LoggedSetRow>[]).map(
            _mapSet,
          ),
        );
      }),
      groups: groups.map((group) {
        return WorkoutCaptureGroupSnapshot(
          sourceGroupId: group.id,
          name: group.name,
          colorHex: group.colorHex,
          position: group.position,
          memberSourceWorkoutExerciseIds:
              (membersByGroupId[group.id] ?? const <ExerciseGroupMemberRow>[])
                  .map((member) => member.workoutExerciseId),
        );
      }),
    );
  }

  WorkoutCaptureSetSnapshot _mapSet(LoggedSetRow set) {
    return WorkoutCaptureSetSnapshot(
      sourceSetId: set.id,
      position: set.position,
      values: _loggedSetValuesFromRow(set),
      plannedRestAfter: set.plannedRestAfter == null
          ? null
          : Duration(seconds: set.plannedRestAfter!),
      comment: set.comment,
      side: set.side,
      rpe: set.rpe,
      isCompleted: set.isCompleted,
      performedAt: set.performedAt?.toUtc(),
    );
  }
}

final class _LoadedWorkoutCapture {
  const _LoadedWorkoutCapture({
    required this.snapshot,
    required this.exercisesById,
  });

  final WorkoutCaptureSnapshot snapshot;
  final Map<String, ExerciseRow> exercisesById;
}

final class _PreparedWorkoutCapturePlacement {
  const _PreparedWorkoutCapturePlacement({
    required this.routineId,
    required this.slot,
    required this.validation,
  });

  final String routineId;
  final int? slot;
  final WorkoutCaptureValidationResult validation;
}

WorkoutTemplateContentDraft _workoutTemplateContentDraftFromCapture(
  CapturedWorkoutTemplateContent content,
) {
  return WorkoutTemplateContentDraft(
    exercises: content.exercises.map((exercise) {
      return WorkoutTemplateExerciseContentDraft(
        exerciseId: exercise.exerciseId,
        prescriptions: exercise.prescriptions.map((prescription) {
          return PrescriptionDraft(
            mode: PrescriptionMode.fixed,
            values: prescription.values,
            repeat: prescription.repeat,
            restAfter: prescription.restAfter,
          );
        }),
      );
    }),
    groups: content.groups.map((group) {
      return WorkoutTemplateGroupContentDraft(
        name: group.name,
        colorHex: group.colorHex,
        rounds: CapturedTemplateGroupContent.rounds,
        memberExerciseIndexes: group.memberExerciseIndexes,
      );
    }),
  );
}

WorkoutCaptureValidationResult _captureValidationAtPath(
  SetValidationResult result, {
  required String sourcePath,
}) {
  return WorkoutCaptureValidationResult(
    errors: result.errors.map(
      (issue) => WorkoutCaptureValidationIssue(
        sourcePath: sourcePath,
        issue: issue,
      ),
    ),
    warnings: result.warnings.map(
      (issue) => WorkoutCaptureValidationIssue(
        sourcePath: sourcePath,
        issue: issue,
      ),
    ),
  );
}

WorkoutCaptureValidationResult _mergeCaptureValidationResults(
  Iterable<WorkoutCaptureValidationResult> results,
) {
  final errors = <WorkoutCaptureValidationIssue>[];
  final warnings = <WorkoutCaptureValidationIssue>[];
  for (final result in results) {
    errors.addAll(result.errors);
    warnings.addAll(result.warnings);
  }
  return WorkoutCaptureValidationResult(errors: errors, warnings: warnings);
}

bool _sameCaptureWarningTokens(Set<String> left, Set<String> right) {
  return left.length == right.length && left.containsAll(right);
}
