part of 'training_repositories.dart';

/// One request to start (materialize) a Workout Template (ROUTINES.md
/// §1.4, §3.2;;).
///
/// Starting a Template always begins a brand-new Workout. Pass [routineId]
/// (and, when the Routine has a Cadence, [slot]) only when the start was
/// reached through a Routine — the Template Link then records provenance;
/// a bare Template start leaves both null.
final class TemplateMaterializeRequest {
  const TemplateMaterializeRequest({
    required this.workoutTemplateId,
    this.routineId,
    this.slot,
  }) : assert(
          slot == null || routineId != null,
          'A Cadence slot requires a Routine.',
        );

  final String workoutTemplateId;
  final String? routineId;
  final int? slot;
}

/// Identities created by one atomic materialize batch.
final class TemplateMaterializeResult {
  const TemplateMaterializeResult({
    required this.workoutId,
    required this.templateLinkId,
    required this.batchId,
  });

  final String workoutId;
  final String templateLinkId;
  final String batchId;
}

/// Provenance-only association between one Workout and the Template (and
/// optional Routine slot) it was materialized from. Never a
/// snapshot, never carries adherence status.
final class TemplateLinkRecord {
  const TemplateLinkRecord({
    required this.id,
    required this.workoutId,
    required this.workoutTemplateId,
    required this.routineId,
    required this.slot,
    required this.updatedAt,
    required this.deletedAt,
  });

  final String id;
  final String workoutId;
  final String workoutTemplateId;
  final String? routineId;
  final int? slot;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

/// Local-only repository for the app-side "start a Template" verb.
///
/// Every materialize is exactly one Drift transaction and one Activity Log
/// batch: one new Workout, its Workout Exercises and Sets (Prescriptions
/// resolved and expanded via [materializeTemplateContent]), its Exercise
/// Groups mirroring the Template's Template Groups, and exactly one
/// Template Link. Template notes are plan guidance and are never copied
/// onto the Workout (ROUTINES.md §1.5).
final class TemplateMaterializeRepository {
  const TemplateMaterializeRepository._(this._repositories);

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  Future<TemplateMaterializeResult> materialize(
    TemplateMaterializeRequest request, {
    DateTime? now,
    String? timezone,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(
      () => _materialize(request, context, now: now, timezone: timezone),
    );
  }

  /// Reads the (at most one) Template Link recorded for a Workout.
  Future<TemplateLinkRecord?> getByWorkoutId(String workoutId) async {
    final row = await (_database.select(_database.templateLinks)
          ..where(
            (row) => row.workoutId.equals(workoutId) & row.deletedAt.isNull(),
          ))
        .getSingleOrNull();
    return row == null ? null : _templateLinkRecordFromRow(row);
  }

  Future<TemplateMaterializeResult> _materialize(
    TemplateMaterializeRequest request,
    _WriteContext context, {
    DateTime? now,
    String? timezone,
  }) async {
    final template = await _repositories.workoutTemplates
        ._requireActiveTemplateRow(request.workoutTemplateId);
    final content = await _repositories.workoutTemplates.getById(
      template.id,
      includeArchived: false,
    );
    if (content == null) {
      throw StateError('Workout Template not found: ${template.id}.');
    }

    if (request.routineId != null) {
      final routine = await _repositories.routinePlans
          ._requireActiveRoutineRow(request.routineId!);
      if (request.slot != null) {
        final cadence = _cadenceFromRow(routine);
        _validateRoutineCadence(cadence, slots: <int?>[request.slot])
            .throwIfRejected();
      }
    }

    final localNow = (now ?? DateTime.now()).toLocal();
    final localDate = TrainingDayDate.fromDateTime(localNow);
    final workoutId = await _repositories.workoutSessions._create(
      WorkoutSessionDraft(
        startedAt: localNow,
        timezone: timezone ?? localNow.timeZoneName,
        localDate: localDate,
      ),
      context,
    );

    final lastPerformedByExerciseId = await _lastPerformedValuesByExerciseId(
      content.exercises.map((exercise) => exercise.exerciseId).toSet(),
    );

    final exerciseInputs = content.exercises.map((exercise) {
      return MaterializeExerciseInput(
        exerciseId: exercise.exerciseId,
        dimensions: exercise.exercise.type.dimensions,
        defaultLoadUnit: exercise.exercise.defaultLoadUnit,
        prescriptions: exercise.prescriptions.map((prescription) {
          return MaterializePrescriptionInput(
            mode: prescription.mode == PrescriptionMode.fixed
                ? MaterializePrescriptionMode.fixed
                : MaterializePrescriptionMode.copyPrevious,
            fixedValues: prescription.mode == PrescriptionMode.fixed
                ? prescription.values
                : null,
            lastPerformedValues:
                lastPerformedByExerciseId[exercise.exerciseId],
            repeat: prescription.repeat,
            restAfter: prescription.restAfter,
          );
        }),
      );
    }).toList(growable: false);

    final templateExerciseIndex = <String, int>{
      for (var index = 0; index < content.exercises.length; index += 1)
        content.exercises[index].id: index,
    };
    final groupInputs = content.groups.map((group) {
      return MaterializeGroupInput(
        name: group.name,
        colorHex: group.colorHex,
        memberExerciseIndexes: group.members.map(
          (member) => templateExerciseIndex[member.templateExerciseId]!,
        ),
      );
    }).toList(growable: false);

    final plan = materializeTemplateContent(
      exercises: exerciseInputs,
      groups: groupInputs,
    );

    final workoutExerciseIdsByIndex = <int, String>{};
    for (var index = 0; index < plan.exercises.length; index += 1) {
      final exercise = plan.exercises[index];
      final workoutExerciseId = await _repositories.workoutExercises._create(
        WorkoutExerciseDraft(
          workoutId: workoutId,
          exerciseId: exercise.exerciseId,
        ),
        context,
      );
      workoutExerciseIdsByIndex[index] = workoutExerciseId;

      for (var setIndex = 0; setIndex < exercise.sets.length; setIndex += 1) {
        final set = exercise.sets[setIndex];
        await _repositories.sets._create(
          LoggedSetDraft(
            workoutId: workoutId,
            exerciseId: exercise.exerciseId,
            position: setIndex,
            values: set.values,
            plannedRestAfter: set.plannedRestAfter,
          ),
          context,
        );
      }
    }

    for (final group in plan.groups) {
      if (group.memberExerciseIndexes.length < 2) {
        // Template Groups always keep at least two active members
        // (plan_validation.validateTemplateGroup); defensive, never hit.
        continue;
      }
      await _repositories.exerciseGroups._create(
        ExerciseGroupDraft(
          workoutId: workoutId,
          name: group.name,
          colorHex: group.colorHex,
          workoutExerciseIds: group.memberExerciseIndexes
              .map((index) => workoutExerciseIdsByIndex[index]!),
        ),
        context,
      );
    }

    final linkId = _repositories.createId(context.timestamp);
    await _database.into(_database.templateLinks).insert(
          TemplateLinksCompanion.insert(
            id: linkId,
            workoutId: workoutId,
            workoutTemplateId: template.id,
            routineId: Value<String?>(request.routineId),
            slot: Value<int?>(request.slot),
            updatedAt: context.timestamp,
          ),
        );
    final linkRow = await _requireTemplateLinkRow(linkId);
    final workoutRow = await _repositories.workoutSessions._requireRow(
      workoutId,
    );
    final workoutExerciseRows = await _repositories.workoutExercises
        ._activeWorkoutExerciseQuery(workoutId: workoutId)
        .get();
    final exerciseGroupRows = await _repositories.exerciseGroups
        ._activeExerciseGroupQuery(workoutId: workoutId)
        .get();
    final exerciseGroupMemberRows = exerciseGroupRows.isEmpty
        ? const <ExerciseGroupMemberRow>[]
        : await _repositories.exerciseGroups
            ._activeExerciseGroupMemberQuery(
              groupIds: exerciseGroupRows.map((group) => group.id).toSet(),
            )
            .get();
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.templateLinksTable,
      entityId: linkId,
      beforeImage: null,
      afterImage: _templateLinkImage(
        linkRow,
        workout: workoutRow,
        workoutExercises: workoutExerciseRows,
        exerciseGroups: exerciseGroupRows,
        exerciseGroupMembers: exerciseGroupMemberRows,
      ),
    );

    return TemplateMaterializeResult(
      workoutId: workoutId,
      templateLinkId: linkId,
      batchId: context.batchId,
    );
  }

  /// Resolves each exercise's most recent genuinely-performed values, for
  /// copy-previous Prescription resolution.
  ///
  /// Only completed Sets ([LoggedSetRow.isCompleted]) count as "performed" —
  /// a not-yet-performed placeholder Set (e.g. one left behind by an
  /// abandoned/unfinished materialized Workout) must never be fabricated
  /// into a copy-previous value (ROUTINES.md; mirrors the completion gate in
  /// `performanceVolumeSamples`).
  Future<Map<String, LoggedSet>> _lastPerformedValuesByExerciseId(
    Set<String> exerciseIds,
  ) async {
    if (exerciseIds.isEmpty) {
      return const <String, LoggedSet>{};
    }
    final rows = await (_database.select(_database.loggedSets)
          ..where(
            (row) =>
                row.exerciseId.isIn(exerciseIds) &
                row.deletedAt.isNull() &
                row.isCompleted.equals(true),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.exerciseId),
            (row) => OrderingTerm.desc(row.performedAt),
            (row) => OrderingTerm.desc(row.id),
          ]))
        .get();
    final result = <String, LoggedSet>{};
    for (final row in rows) {
      result.putIfAbsent(row.exerciseId, () => _loggedSetValuesFromRow(row));
    }
    return result;
  }

  Future<TemplateLinkRow> _requireTemplateLinkRow(String id) async {
    final row = await (_database.select(_database.templateLinks)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Template Link not found: $id.');
    }
    return row;
  }
}

TemplateLinkRecord _templateLinkRecordFromRow(TemplateLinkRow row) {
  return TemplateLinkRecord(
    id: row.id,
    workoutId: row.workoutId,
    workoutTemplateId: row.workoutTemplateId,
    routineId: row.routineId,
    slot: row.slot,
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );
}
