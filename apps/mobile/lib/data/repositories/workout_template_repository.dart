part of 'training_repositories.dart';

/// The authored values of a Workout Template itself.
final class WorkoutTemplateDraft {
  const WorkoutTemplateDraft({required this.name, this.notes});

  final String name;
  final String? notes;
}

/// A new exercise entry in a Workout Template.
final class TemplateExerciseDraft {
  const TemplateExerciseDraft({required this.exerciseId, this.note});

  final String exerciseId;
  final String? note;
}

/// Authored superset/circuit structure within a Workout Template.
final class TemplateGroupDraft {
  TemplateGroupDraft({
    required this.name,
    required this.colorHex,
    required this.rounds,
    required Iterable<String> orderedTemplateExerciseIds,
  }) : orderedTemplateExerciseIds =
            List<String>.unmodifiable(orderedTemplateExerciseIds);

  final String name;
  final String colorHex;
  final int rounds;
  final List<String> orderedTemplateExerciseIds;
}

/// How a Prescription obtains the values for its performed Sets.
enum PrescriptionMode { fixed, copyPrevious }

extension on PrescriptionMode {
  String get storageValue => switch (this) {
        PrescriptionMode.fixed => 'fixed',
        PrescriptionMode.copyPrevious => 'copy-previous',
      };
}

/// One planned set-block within a Template Exercise.
final class PrescriptionDraft {
  const PrescriptionDraft({
    required this.mode,
    required this.values,
    this.repeat = 1,
    this.restAfter,
  });

  final PrescriptionMode mode;
  final LoggedSet values;
  final int repeat;
  final Duration? restAfter;
}

/// A complete ordered Workout Template content tree for one atomic write.
///
/// This is the canonical batch-write shape shared by capture today and the
/// later divergence/update verbs. Group members reference Exercise indexes so
/// generated Template Exercise ids never leak into the authored draft.
final class WorkoutTemplateContentDraft {
  WorkoutTemplateContentDraft({
    required Iterable<WorkoutTemplateExerciseContentDraft> exercises,
    required Iterable<WorkoutTemplateGroupContentDraft> groups,
  })  : exercises = List<WorkoutTemplateExerciseContentDraft>.unmodifiable(
          exercises,
        ),
        groups = List<WorkoutTemplateGroupContentDraft>.unmodifiable(groups);

  final List<WorkoutTemplateExerciseContentDraft> exercises;
  final List<WorkoutTemplateGroupContentDraft> groups;
}

final class WorkoutTemplateExerciseContentDraft {
  WorkoutTemplateExerciseContentDraft({
    required this.exerciseId,
    this.note,
    required Iterable<PrescriptionDraft> prescriptions,
  }) : prescriptions = List<PrescriptionDraft>.unmodifiable(prescriptions);

  final String exerciseId;
  final String? note;
  final List<PrescriptionDraft> prescriptions;
}

final class WorkoutTemplateGroupContentDraft {
  WorkoutTemplateGroupContentDraft({
    required this.name,
    required this.colorHex,
    required this.rounds,
    required Iterable<int> memberExerciseIndexes,
  }) : memberExerciseIndexes = List<int>.unmodifiable(memberExerciseIndexes);

  final String name;
  final String colorHex;
  final int rounds;
  final List<int> memberExerciseIndexes;
}

/// Lightweight list representation of a Workout Template.
final class WorkoutTemplateSummaryRecord {
  const WorkoutTemplateSummaryRecord({
    required this.id,
    required this.name,
    required this.notes,
    required this.exerciseCount,
    required this.updatedAt,
    required this.deletedAt,
  });

  final String id;
  final String name;
  final String? notes;
  final int exerciseCount;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isArchived => deletedAt != null;
}

/// Complete editable plan content for one Workout Template.
final class WorkoutTemplateRecord {
  WorkoutTemplateRecord({
    required this.id,
    required this.name,
    required this.notes,
    required List<TemplateExerciseRecord> exercises,
    required List<TemplateGroupRecord> groups,
    required this.updatedAt,
    required this.deletedAt,
  })  : exercises = List<TemplateExerciseRecord>.unmodifiable(exercises),
        groups = List<TemplateGroupRecord>.unmodifiable(groups);

  final String id;
  final String name;
  final String? notes;
  final List<TemplateExerciseRecord> exercises;
  final List<TemplateGroupRecord> groups;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isArchived => deletedAt != null;
}

/// One ordered superset/circuit and its member Template Exercises.
final class TemplateGroupRecord {
  TemplateGroupRecord({
    required this.id,
    required this.workoutTemplateId,
    required this.name,
    required this.colorHex,
    required this.rounds,
    required this.position,
    required List<TemplateGroupMemberRecord> members,
    required this.updatedAt,
    required this.deletedAt,
  }) : members = List<TemplateGroupMemberRecord>.unmodifiable(members);

  final String id;
  final String workoutTemplateId;
  final String name;
  final String colorHex;
  final int rounds;
  final int position;
  final List<TemplateGroupMemberRecord> members;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

/// One ordered membership inside a Template Group.
final class TemplateGroupMemberRecord {
  const TemplateGroupMemberRecord({
    required this.id,
    required this.groupId,
    required this.templateExerciseId,
    required this.position,
    required this.updatedAt,
    required this.deletedAt,
  });

  final String id;
  final String groupId;
  final String templateExerciseId;
  final int position;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

/// Removing a grouped entry would silently damage authored circuit structure.
/// The caller must update/dissolve its Template Group first.
final class TemplateExerciseGroupedException implements Exception {
  const TemplateExerciseGroupedException(this.templateExerciseId);

  final String templateExerciseId;

  @override
  String toString() => 'Template Exercise is in an active Template Group: '
      '$templateExerciseId.';
}

/// One ordered Exercise reference and its standing plan guidance.
final class TemplateExerciseRecord {
  TemplateExerciseRecord({
    required this.id,
    required this.workoutTemplateId,
    required this.exerciseId,
    required this.position,
    required this.note,
    required this.exercise,
    required List<PrescriptionRecord> prescriptions,
    required this.updatedAt,
    required this.deletedAt,
  }) : prescriptions = List<PrescriptionRecord>.unmodifiable(prescriptions);

  final String id;
  final String workoutTemplateId;
  final String exerciseId;
  final int position;
  final String? note;
  final ExerciseRecord exercise;
  final List<PrescriptionRecord> prescriptions;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

/// Stored Prescription content, including values exactly as entered.
final class PrescriptionRecord {
  const PrescriptionRecord({
    required this.id,
    required this.templateExerciseId,
    required this.mode,
    required this.position,
    required this.values,
    required this.repeat,
    required this.restAfter,
    required this.updatedAt,
    required this.deletedAt,
  });

  final String id;
  final String templateExerciseId;
  final PrescriptionMode mode;
  final int position;
  final LoggedSet values;
  final int repeat;
  final Duration? restAfter;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

/// Local-only repository for the first-class Workout Template plan tree.
///
/// Every public mutation creates one [_WriteContext] and runs exactly one Drift
/// transaction. All rows changed by that user action share the context's
/// Activity Log batch.
class WorkoutTemplateRepository {
  const WorkoutTemplateRepository._(this._repositories);

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  Future<List<WorkoutTemplateSummaryRecord>> listActiveSummaries() {
    return _listSummaries(archived: false);
  }

  Future<List<WorkoutTemplateSummaryRecord>> listArchivedSummaries() {
    return _listSummaries(archived: true);
  }

  Stream<List<WorkoutTemplateSummaryRecord>> watchActiveSummaries() {
    return _watchSummaries(archived: false);
  }

  Stream<List<WorkoutTemplateSummaryRecord>> watchArchivedSummaries() {
    return _watchSummaries(archived: true);
  }

  /// Watches active and archived templates in one query result.
  ///
  /// Consumers that render both lifecycle sections can partition this single
  /// emission without combining independently invalidated Drift streams.
  Stream<List<WorkoutTemplateSummaryRecord>> watchAllSummaries() {
    return _watchSummaries(archived: null);
  }

  Future<WorkoutTemplateRecord?> getById(
    String id, {
    bool includeArchived = true,
  }) async {
    final query = _detailQuery(id, includeArchived: includeArchived);
    return _workoutTemplateFromJoinedRows(_database, await query.get());
  }

  Stream<WorkoutTemplateRecord?> watchById(
    String id, {
    bool includeArchived = true,
  }) {
    final query = _detailQuery(id, includeArchived: includeArchived);
    return query.watch().map(
          (rows) => _workoutTemplateFromJoinedRows(_database, rows),
        );
  }

  Future<String> create(
    WorkoutTemplateDraft draft, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() => _create(draft, context));
  }

  Future<void> updateTemplate(
    String id, {
    required String name,
    String? notes,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final before = await _requireTemplateRow(id);
      if (before.deletedAt != null) {
        throw StateError('Workout Template is archived: $id.');
      }
      final normalizedName = _normalizeWorkoutTemplateName(name);
      final normalizedNotes = _normalizeOptionalText(notes);
      if (before.name == normalizedName && before.notes == normalizedNotes) {
        return;
      }

      await (_database.update(_database.workoutTemplates)
            ..where((row) => row.id.equals(id)))
          .write(
        WorkoutTemplatesCompanion(
          name: Value<String>(normalizedName),
          notes: Value<String?>(normalizedNotes),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireTemplateRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.workoutTemplatesTable,
        entityId: id,
        beforeImage: _workoutTemplateImage(before),
        afterImage: _workoutTemplateImage(after),
      );
    });
  }

  Future<void> archive(
    String id, {
    String actor = 'app',
    String? batchId,
  }) {
    return _setArchived(
      id,
      archived: true,
      actor: actor,
      batchId: batchId,
    );
  }

  Future<void> restore(
    String id, {
    String actor = 'app',
    String? batchId,
  }) {
    return _setArchived(
      id,
      archived: false,
      actor: actor,
      batchId: batchId,
    );
  }

  Future<String> addExercise(
    String templateId,
    String exerciseId, {
    String? note,
    String actor = 'app',
    String? batchId,
  }) {
    return addExerciseDraft(
      templateId,
      TemplateExerciseDraft(exerciseId: exerciseId, note: note),
      actor: actor,
      batchId: batchId,
    );
  }

  Future<String> addExerciseDraft(
    String templateId,
    TemplateExerciseDraft draft, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      await _requireActiveTemplateRow(templateId);
      await _requireActiveExerciseRow(draft.exerciseId);
      final activeRows = await _activeTemplateExerciseRows(templateId).get();
      final matchingRows = await (_database.select(_database.templateExercises)
            ..where(
              (row) =>
                  row.workoutTemplateId.equals(templateId) &
                  row.exerciseId.equals(draft.exerciseId),
            ))
          .get();
      TemplateExerciseRow? existing;
      for (final candidate in matchingRows) {
        if (candidate.deletedAt == null) {
          throw ArgumentError.value(
            draft.exerciseId,
            'exerciseId',
            'Exercise is already in this Workout Template.',
          );
        }
        final selected = existing;
        if (selected == null ||
            candidate.updatedAt.isAfter(selected.updatedAt) ||
            (candidate.updatedAt == selected.updatedAt &&
                candidate.id.compareTo(selected.id) > 0)) {
          existing = candidate;
        }
      }

      final normalizedNote = _normalizeOptionalText(draft.note);
      final position = _nextTemplateExercisePosition(activeRows);
      final archivedExisting = existing;
      if (archivedExisting != null) {
        await (_database.update(_database.templateExercises)
              ..where((row) => row.id.equals(archivedExisting.id)))
            .write(
          TemplateExercisesCompanion(
            position: Value<int>(position),
            note: Value<String?>(normalizedNote),
            updatedAt: Value<DateTime>(context.timestamp),
            deletedAt: const Value<DateTime?>(null),
          ),
        );
        final after = await _requireTemplateExerciseRow(archivedExisting.id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.templateExercisesTable,
          entityId: archivedExisting.id,
          beforeImage: _templateExerciseImage(archivedExisting),
          afterImage: _templateExerciseImage(after),
        );
        return archivedExisting.id;
      }

      final id = _repositories.createId(context.timestamp);
      await _database.into(_database.templateExercises).insert(
            TemplateExercisesCompanion.insert(
              id: id,
              workoutTemplateId: templateId,
              exerciseId: draft.exerciseId,
              position: position,
              note: Value<String?>(normalizedNote),
              updatedAt: context.timestamp,
            ),
          );
      final after = await _requireTemplateExerciseRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.templateExercisesTable,
        entityId: id,
        beforeImage: null,
        afterImage: _templateExerciseImage(after),
      );
      return id;
    });
  }

  Future<void> updateExerciseNote(
    String templateExerciseId, {
    String? note,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final before = await _requireActiveTemplateExerciseRow(
        templateExerciseId,
      );
      await _requireActiveTemplateRow(before.workoutTemplateId);
      final normalizedNote = _normalizeOptionalText(note);
      if (before.note == normalizedNote) {
        return;
      }
      await (_database.update(_database.templateExercises)
            ..where((row) => row.id.equals(templateExerciseId)))
          .write(
        TemplateExercisesCompanion(
          note: Value<String?>(normalizedNote),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireTemplateExerciseRow(templateExerciseId);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.templateExercisesTable,
        entityId: templateExerciseId,
        beforeImage: _templateExerciseImage(before),
        afterImage: _templateExerciseImage(after),
      );
    });
  }

  Future<void> removeExercise(
    String templateExerciseId, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final before = await _requireTemplateExerciseRow(templateExerciseId);
      if (before.deletedAt != null) {
        return;
      }
      await _requireActiveTemplateRow(before.workoutTemplateId);
      if (await _hasActiveTemplateGroupMembership(templateExerciseId)) {
        throw TemplateExerciseGroupedException(templateExerciseId);
      }
      await (_database.update(_database.templateExercises)
            ..where((row) => row.id.equals(templateExerciseId)))
          .write(
        TemplateExercisesCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      final after = await _requireTemplateExerciseRow(templateExerciseId);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.templateExercisesTable,
        entityId: templateExerciseId,
        beforeImage: _templateExerciseImage(before),
        afterImage: _templateExerciseImage(after),
      );
    });
  }

  Future<void> reorderExercises(
    String templateId,
    List<String> orderedIds, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      await _requireActiveTemplateRow(templateId);
      final rows = await _activeTemplateExerciseRows(templateId).get();
      _requireExactReorderIds(
        orderedIds: orderedIds,
        activeIds: rows.map((row) => row.id),
        label: 'Template Exercise',
      );
      final byId = <String, TemplateExerciseRow>{
        for (final row in rows) row.id: row,
      };
      for (var position = 0; position < orderedIds.length; position += 1) {
        final before = byId[orderedIds[position]]!;
        if (before.position == position) {
          continue;
        }
        await (_database.update(_database.templateExercises)
              ..where((row) => row.id.equals(before.id)))
            .write(
          TemplateExercisesCompanion(
            position: Value<int>(position),
            updatedAt: Value<DateTime>(context.timestamp),
          ),
        );
        final after = await _requireTemplateExerciseRow(before.id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.templateExercisesTable,
          entityId: before.id,
          beforeImage: _templateExerciseImage(before),
          afterImage: _templateExerciseImage(after),
        );
      }
    });
  }

  Future<String> createTemplateGroup(
    String templateId,
    TemplateGroupDraft draft, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      _validateTemplateGroupDraft(draft).throwIfRejected();
      await _requireActiveTemplateRow(templateId);
      final memberRows = await _requireAvailableTemplateGroupMembers(
        templateId: templateId,
        orderedTemplateExerciseIds: draft.orderedTemplateExerciseIds,
      );
      final activeGroups = await _activeTemplateGroupRows(templateId).get();
      final id = _repositories.createId(context.timestamp);
      await _database.into(_database.templateGroups).insert(
            TemplateGroupsCompanion.insert(
              id: id,
              workoutTemplateId: templateId,
              name: draft.name.trim(),
              colorHex: _normalizeColorHex(draft.colorHex),
              rounds: Value<int>(draft.rounds),
              position: _nextTemplateGroupPosition(activeGroups),
              updatedAt: context.timestamp,
            ),
          );
      final after = await _requireTemplateGroupRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.templateGroupsTable,
        entityId: id,
        beforeImage: null,
        afterImage: _templateGroupImage(after),
      );

      for (var position = 0; position < memberRows.length; position += 1) {
        await _insertTemplateGroupMember(
          groupId: id,
          templateExerciseId: memberRows[position].id,
          position: position,
          context: context,
        );
      }
      return id;
    });
  }

  Future<void> updateTemplateGroup(
    String groupId,
    TemplateGroupDraft draft, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      _validateTemplateGroupDraft(draft).throwIfRejected();
      final before = await _requireActiveTemplateGroupRow(groupId);
      await _requireActiveTemplateRow(before.workoutTemplateId);
      await _requireAvailableTemplateGroupMembers(
        templateId: before.workoutTemplateId,
        orderedTemplateExerciseIds: draft.orderedTemplateExerciseIds,
        excludingGroupId: groupId,
      );

      final normalizedName = draft.name.trim();
      final normalizedColorHex = _normalizeColorHex(draft.colorHex);
      if (before.name != normalizedName ||
          before.colorHex != normalizedColorHex ||
          before.rounds != draft.rounds) {
        await (_database.update(_database.templateGroups)
              ..where((row) => row.id.equals(groupId)))
            .write(
          TemplateGroupsCompanion(
            name: Value<String>(normalizedName),
            colorHex: Value<String>(normalizedColorHex),
            rounds: Value<int>(draft.rounds),
            updatedAt: Value<DateTime>(context.timestamp),
          ),
        );
        final after = await _requireTemplateGroupRow(groupId);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.templateGroupsTable,
          entityId: groupId,
          beforeImage: _templateGroupImage(before),
          afterImage: _templateGroupImage(after),
        );
      }

      await _replaceTemplateGroupMembers(
        groupId: groupId,
        orderedTemplateExerciseIds: draft.orderedTemplateExerciseIds,
        context: context,
      );
    });
  }

  Future<void> reorderTemplateGroups(
    String templateId,
    List<String> orderedIds, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      await _requireActiveTemplateRow(templateId);
      final rows = await _activeTemplateGroupRows(templateId).get();
      _requireExactReorderIds(
        orderedIds: orderedIds,
        activeIds: rows.map((row) => row.id),
        label: 'Template Group',
      );
      final byId = <String, TemplateGroupRow>{
        for (final row in rows) row.id: row,
      };
      for (var position = 0; position < orderedIds.length; position += 1) {
        final before = byId[orderedIds[position]]!;
        if (before.position == position) {
          continue;
        }
        await _setTemplateGroupPosition(before, position, context);
      }
    });
  }

  Future<void> dissolveTemplateGroup(
    String groupId, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final before = await _requireTemplateGroupRow(groupId);
      if (before.deletedAt != null) {
        return;
      }
      await _requireActiveTemplateRow(before.workoutTemplateId);
      final members = await _activeTemplateGroupMemberRows(
        groupId: groupId,
      ).get();
      for (final member in members) {
        await _archiveTemplateGroupMember(member, context);
      }
      await (_database.update(_database.templateGroups)
            ..where((row) => row.id.equals(groupId)))
          .write(
        TemplateGroupsCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      final after = await _requireTemplateGroupRow(groupId);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.templateGroupsTable,
        entityId: groupId,
        beforeImage: _templateGroupImage(before),
        afterImage: _templateGroupImage(after),
      );
      await _normalizeTemplateGroupPositions(
        before.workoutTemplateId,
        context,
      );
    });
  }

  Future<SetValidationResult> validatePrescriptionDraft(
    String templateExerciseId,
    PrescriptionDraft draft,
  ) async {
    final templateExercise =
        await _requireActiveTemplateExerciseRow(templateExerciseId);
    final exercise = await _requireExerciseRow(templateExercise.exerciseId);
    return _validatePrescriptionDraft(exercise, draft);
  }

  Future<String> addPrescription(
    String templateExerciseId,
    PrescriptionDraft draft, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final templateExercise =
          await _requireActiveTemplateExerciseRow(templateExerciseId);
      await _requireActiveTemplateRow(templateExercise.workoutTemplateId);
      final exercise = await _requireExerciseRow(templateExercise.exerciseId);
      _validatePrescriptionDraft(exercise, draft).throwIfRejected();
      final rows = await _activePrescriptionRows(templateExerciseId).get();
      final id = _repositories.createId(context.timestamp);
      await _database.into(_database.prescriptions).insert(
            _prescriptionInsertCompanion(
              id: id,
              templateExerciseId: templateExerciseId,
              position: _nextPrescriptionPosition(rows),
              draft: draft,
              updatedAt: context.timestamp,
            ),
          );
      final after = await _requirePrescriptionRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.prescriptionsTable,
        entityId: id,
        beforeImage: null,
        afterImage: _prescriptionImage(after),
      );
      return id;
    });
  }

  Future<void> updatePrescription(
    String prescriptionId,
    PrescriptionDraft draft, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final before = await _requireActivePrescriptionRow(prescriptionId);
      final templateExercise = await _requireActiveTemplateExerciseRow(
        before.templateExerciseId,
      );
      await _requireActiveTemplateRow(templateExercise.workoutTemplateId);
      final exercise = await _requireExerciseRow(templateExercise.exerciseId);
      _validatePrescriptionDraft(exercise, draft).throwIfRejected();
      await (_database.update(_database.prescriptions)
            ..where((row) => row.id.equals(prescriptionId)))
          .write(
        _prescriptionValueCompanion(draft, updatedAt: context.timestamp),
      );
      final after = await _requirePrescriptionRow(prescriptionId);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.prescriptionsTable,
        entityId: prescriptionId,
        beforeImage: _prescriptionImage(before),
        afterImage: _prescriptionImage(after),
      );
    });
  }

  Future<void> removePrescription(
    String prescriptionId, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final before = await _requirePrescriptionRow(prescriptionId);
      if (before.deletedAt != null) {
        return;
      }
      final templateExercise = await _requireActiveTemplateExerciseRow(
        before.templateExerciseId,
      );
      await _requireActiveTemplateRow(templateExercise.workoutTemplateId);
      await (_database.update(_database.prescriptions)
            ..where((row) => row.id.equals(prescriptionId)))
          .write(
        PrescriptionsCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      final after = await _requirePrescriptionRow(prescriptionId);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.prescriptionsTable,
        entityId: prescriptionId,
        beforeImage: _prescriptionImage(before),
        afterImage: _prescriptionImage(after),
      );
    });
  }

  Future<void> reorderPrescriptions(
    String templateExerciseId,
    List<String> orderedIds, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final templateExercise =
          await _requireActiveTemplateExerciseRow(templateExerciseId);
      await _requireActiveTemplateRow(templateExercise.workoutTemplateId);
      final rows = await _activePrescriptionRows(templateExerciseId).get();
      _requireExactReorderIds(
        orderedIds: orderedIds,
        activeIds: rows.map((row) => row.id),
        label: 'Prescription',
      );
      final byId = <String, PrescriptionRow>{
        for (final row in rows) row.id: row,
      };
      for (var position = 0; position < orderedIds.length; position += 1) {
        final before = byId[orderedIds[position]]!;
        if (before.position == position) {
          continue;
        }
        await (_database.update(_database.prescriptions)
              ..where((row) => row.id.equals(before.id)))
            .write(
          PrescriptionsCompanion(
            position: Value<int>(position),
            updatedAt: Value<DateTime>(context.timestamp),
          ),
        );
        final after = await _requirePrescriptionRow(before.id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.prescriptionsTable,
          entityId: before.id,
          beforeImage: _prescriptionImage(before),
          afterImage: _prescriptionImage(after),
        );
      }
    });
  }

  Future<List<WorkoutTemplateSummaryRecord>> _listSummaries({
    required bool? archived,
  }) async {
    final query = _summaryQuery(archived: archived);
    return _workoutTemplateSummariesFromJoinedRows(
      _database,
      await query.get(),
    );
  }

  Stream<List<WorkoutTemplateSummaryRecord>> _watchSummaries({
    required bool? archived,
  }) {
    final query = _summaryQuery(archived: archived);
    return query.watch().map(
          (rows) => _workoutTemplateSummariesFromJoinedRows(_database, rows),
        );
  }

  Selectable<TypedResult> _summaryQuery({
    required bool? archived,
  }) {
    final query = _database.select(_database.workoutTemplates).join([
      leftOuterJoin(
        _database.templateExercises,
        _database.templateExercises.workoutTemplateId.equalsExp(
              _database.workoutTemplates.id,
            ) &
            _database.templateExercises.deletedAt.isNull(),
      ),
    ]);
    if (archived != null) {
      query.where(
        archived
            ? _database.workoutTemplates.deletedAt.isNotNull()
            : _database.workoutTemplates.deletedAt.isNull(),
      );
    }
    query.orderBy([
      OrderingTerm.asc(_database.workoutTemplates.name),
      OrderingTerm.asc(_database.workoutTemplates.id),
      OrderingTerm.asc(_database.templateExercises.position),
    ]);
    return query;
  }

  Selectable<TypedResult> _detailQuery(
    String id, {
    required bool includeArchived,
  }) {
    final query = _database.select(_database.workoutTemplates).join([
      leftOuterJoin(
        _database.templateExercises,
        _database.templateExercises.workoutTemplateId.equalsExp(
              _database.workoutTemplates.id,
            ) &
            _database.templateExercises.deletedAt.isNull(),
      ),
      leftOuterJoin(
        _database.exercises,
        _database.exercises.id.equalsExp(
          _database.templateExercises.exerciseId,
        ),
      ),
      leftOuterJoin(
        _database.templateGroupMembers,
        _database.templateGroupMembers.templateExerciseId.equalsExp(
              _database.templateExercises.id,
            ) &
            _database.templateGroupMembers.deletedAt.isNull(),
      ),
      leftOuterJoin(
        _database.templateGroups,
        _database.templateGroups.id.equalsExp(
              _database.templateGroupMembers.groupId,
            ) &
            _database.templateGroups.workoutTemplateId.equalsExp(
              _database.workoutTemplates.id,
            ) &
            _database.templateGroups.deletedAt.isNull(),
      ),
      leftOuterJoin(
        _database.prescriptions,
        _database.prescriptions.templateExerciseId.equalsExp(
              _database.templateExercises.id,
            ) &
            _database.prescriptions.deletedAt.isNull(),
      ),
    ])
      ..where(_database.workoutTemplates.id.equals(id));
    if (!includeArchived) {
      query.where(_database.workoutTemplates.deletedAt.isNull());
    }
    query.orderBy([
      OrderingTerm.asc(_database.templateExercises.position),
      OrderingTerm.asc(_database.templateExercises.id),
      OrderingTerm.asc(_database.templateGroups.position),
      OrderingTerm.asc(_database.templateGroupMembers.position),
      OrderingTerm.asc(_database.prescriptions.position),
      OrderingTerm.asc(_database.prescriptions.id),
    ]);
    return query;
  }

  Future<String> _create(
    WorkoutTemplateDraft draft,
    _WriteContext context,
  ) async {
    final result = await _createWithContent(
      draft,
      WorkoutTemplateContentDraft(
        exercises: const <WorkoutTemplateExerciseContentDraft>[],
        groups: const <WorkoutTemplateGroupContentDraft>[],
      ),
      context,
    );
    return result.workoutTemplateId;
  }

  /// Writes a complete new Template tree with an existing write context.
  ///
  /// The caller owns the surrounding transaction and warning-acknowledgement
  /// policy. This method preflights hard plan validation, then creates every
  /// row and Activity entry through one canonical path. Historical capture may
  /// opt into retained archived Exercise references without restoring them.
  Future<_WorkoutTemplateContentWriteResult> _createWithContent(
    WorkoutTemplateDraft draft,
    WorkoutTemplateContentDraft content,
    _WriteContext context, {
    _WorkoutTemplateContentExercisePolicy exercisePolicy =
        _WorkoutTemplateContentExercisePolicy.activeEditor,
  }) async {
    await _validateContentDraft(content, exercisePolicy);

    final id = _repositories.createId(context.timestamp);
    await _database.into(_database.workoutTemplates).insert(
          WorkoutTemplatesCompanion.insert(
            id: id,
            name: _normalizeWorkoutTemplateName(draft.name),
            notes: Value<String?>(_normalizeOptionalText(draft.notes)),
            updatedAt: context.timestamp,
          ),
        );
    final after = await _requireTemplateRow(id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.workoutTemplatesTable,
      entityId: id,
      beforeImage: null,
      afterImage: _workoutTemplateImage(after),
    );

    await _insertContentTree(id, content, context);

    return _WorkoutTemplateContentWriteResult(
      workoutTemplateId: id,
    );
  }

  /// Capture-replaces an existing Template's whole content tree while
  /// preserving its identity: id, name, notes, Routine memberships, and
  /// existing Template Links are all untouched (ROUTINES.md §2 "Update").
  ///
  /// Every currently-active Template Exercise, Prescription, and Template
  /// Group is archived (never hard-deleted) before the new content is
  /// inserted, in the same transaction and Activity Log batch as the caller's
  /// [_WriteContext] — all-or-nothing, per the same canonical path
  /// [_createWithContent] uses for a brand-new Template.
  Future<void> _replaceContent(
    String templateId,
    WorkoutTemplateContentDraft content,
    _WriteContext context, {
    _WorkoutTemplateContentExercisePolicy exercisePolicy =
        _WorkoutTemplateContentExercisePolicy.historicalFact,
  }) async {
    await _validateContentDraft(content, exercisePolicy);
    final before = await _requireActiveTemplateRow(templateId);

    await _archiveContentTree(templateId, context);
    await _insertContentTree(templateId, content, context);

    await (_database.update(_database.workoutTemplates)
          ..where((row) => row.id.equals(templateId)))
        .write(
      WorkoutTemplatesCompanion(
        updatedAt: Value<DateTime>(context.timestamp),
      ),
    );
    final after = await _requireTemplateRow(templateId);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.workoutTemplatesTable,
      entityId: templateId,
      beforeImage: _workoutTemplateImage(before),
      afterImage: _workoutTemplateImage(after),
    );
  }

  /// Hard preflight validation shared by [_createWithContent] and
  /// [_replaceContent] — read-only, no writes, so a rejected draft never
  /// touches storage.
  Future<void> _validateContentDraft(
    WorkoutTemplateContentDraft content,
    _WorkoutTemplateContentExercisePolicy exercisePolicy,
  ) async {
    final exerciseIds = <String>{};
    for (final exercise in content.exercises) {
      if (exercise.exerciseId.trim().isEmpty ||
          !exerciseIds.add(exercise.exerciseId)) {
        throw ArgumentError.value(
          exercise.exerciseId,
          'exerciseId',
          'Workout Template Exercise ids must be non-empty and unique.',
        );
      }
      final isHistoricalFact = exercisePolicy ==
          _WorkoutTemplateContentExercisePolicy.historicalFact;
      final exerciseRow = isHistoricalFact
          ? await _requireExerciseRow(exercise.exerciseId)
          : await _requireActiveExerciseRow(exercise.exerciseId);
      for (final prescription in exercise.prescriptions) {
        if (isHistoricalFact && prescription.mode == PrescriptionMode.fixed) {
          plan_validation
              .validatePrescription(
                mode: prescription.mode.name,
                dimensions: prescription.values.dimensionIds,
                loadMode: _exerciseFromRow(exerciseRow).loadMode,
                repeat: prescription.repeat,
                restAfterSeconds: prescription.restAfter?.inSeconds,
                values: prescription.values.values.values,
              )
              .throwIfRejected();
        } else {
          _validatePrescriptionDraft(exerciseRow, prescription)
              .throwIfRejected();
        }
      }
    }

    final groupedExerciseIndexes = <int>{};
    for (final group in content.groups) {
      final indexes = group.memberExerciseIndexes;
      if (indexes.toSet().length != indexes.length ||
          indexes
              .any((index) => index < 0 || index >= content.exercises.length)) {
        throw ArgumentError.value(
          indexes,
          'memberExerciseIndexes',
          'Template Group members must be unique valid Exercise indexes.',
        );
      }
      if (indexes.any((index) => !groupedExerciseIndexes.add(index))) {
        throw ArgumentError.value(
          indexes,
          'memberExerciseIndexes',
          'A Template Exercise can belong to only one Template Group.',
        );
      }
      plan_validation
          .validateTemplateGroup(
            name: group.name,
            colorHex: group.colorHex,
            rounds: group.rounds,
            memberIds: indexes.map(
              (index) => content.exercises[index].exerciseId,
            ),
          )
          .throwIfRejected();
    }
  }

  /// Inserts a validated content tree's Template Exercises, Prescriptions,
  /// and Template Groups under an existing (new or emptied) [templateId].
  Future<void> _insertContentTree(
    String templateId,
    WorkoutTemplateContentDraft content,
    _WriteContext context,
  ) async {
    final templateExerciseIds = <String>[];
    for (var exercisePosition = 0;
        exercisePosition < content.exercises.length;
        exercisePosition += 1) {
      final exercise = content.exercises[exercisePosition];
      final templateExerciseId = _repositories.createId(context.timestamp);
      await _database.into(_database.templateExercises).insert(
            TemplateExercisesCompanion.insert(
              id: templateExerciseId,
              workoutTemplateId: templateId,
              exerciseId: exercise.exerciseId,
              position: exercisePosition,
              note: Value<String?>(_normalizeOptionalText(exercise.note)),
              updatedAt: context.timestamp,
            ),
          );
      final templateExercise =
          await _requireTemplateExerciseRow(templateExerciseId);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.templateExercisesTable,
        entityId: templateExerciseId,
        beforeImage: null,
        afterImage: _templateExerciseImage(templateExercise),
      );
      templateExerciseIds.add(templateExerciseId);

      for (var prescriptionPosition = 0;
          prescriptionPosition < exercise.prescriptions.length;
          prescriptionPosition += 1) {
        final prescriptionId = _repositories.createId(context.timestamp);
        await _database.into(_database.prescriptions).insert(
              _prescriptionInsertCompanion(
                id: prescriptionId,
                templateExerciseId: templateExerciseId,
                position: prescriptionPosition,
                draft: exercise.prescriptions[prescriptionPosition],
                updatedAt: context.timestamp,
              ),
            );
        final prescription = await _requirePrescriptionRow(prescriptionId);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.prescriptionsTable,
          entityId: prescriptionId,
          beforeImage: null,
          afterImage: _prescriptionImage(prescription),
        );
      }
    }

    for (var groupPosition = 0;
        groupPosition < content.groups.length;
        groupPosition += 1) {
      final group = content.groups[groupPosition];
      final templateGroupId = _repositories.createId(context.timestamp);
      await _database.into(_database.templateGroups).insert(
            TemplateGroupsCompanion.insert(
              id: templateGroupId,
              workoutTemplateId: templateId,
              name: group.name.trim(),
              colorHex: _normalizeColorHex(group.colorHex),
              rounds: Value<int>(group.rounds),
              position: groupPosition,
              updatedAt: context.timestamp,
            ),
          );
      final templateGroup = await _requireTemplateGroupRow(templateGroupId);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.templateGroupsTable,
        entityId: templateGroupId,
        beforeImage: null,
        afterImage: _templateGroupImage(templateGroup),
      );
      for (var memberPosition = 0;
          memberPosition < group.memberExerciseIndexes.length;
          memberPosition += 1) {
        await _insertTemplateGroupMember(
          groupId: templateGroupId,
          templateExerciseId:
              templateExerciseIds[group.memberExerciseIndexes[memberPosition]],
          position: memberPosition,
          context: context,
        );
      }
    }
  }

  /// Archives every currently-active Template Exercise (and its
  /// Prescriptions) and Template Group (and its members) for [templateId].
  /// Soft-delete only — "user-facing delete = archive", no cascading hard
  /// deletes, ever.
  Future<void> _archiveContentTree(
    String templateId,
    _WriteContext context,
  ) async {
    final groups = await _activeTemplateGroupRows(templateId).get();
    for (final group in groups) {
      final members =
          await _activeTemplateGroupMemberRows(groupId: group.id).get();
      for (final member in members) {
        await _archiveTemplateGroupMember(member, context);
      }
      await (_database.update(_database.templateGroups)
            ..where((row) => row.id.equals(group.id)))
          .write(
        TemplateGroupsCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      final after = await _requireTemplateGroupRow(group.id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.templateGroupsTable,
        entityId: group.id,
        beforeImage: _templateGroupImage(group),
        afterImage: _templateGroupImage(after),
      );
    }

    final exercises = await _activeTemplateExerciseRows(templateId).get();
    for (final exercise in exercises) {
      final prescriptions = await _activePrescriptionRows(exercise.id).get();
      for (final prescription in prescriptions) {
        await (_database.update(_database.prescriptions)
              ..where((row) => row.id.equals(prescription.id)))
            .write(
          PrescriptionsCompanion(
            updatedAt: Value<DateTime>(context.timestamp),
            deletedAt: Value<DateTime?>(context.timestamp),
          ),
        );
        final after = await _requirePrescriptionRow(prescription.id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.prescriptionsTable,
          entityId: prescription.id,
          beforeImage: _prescriptionImage(prescription),
          afterImage: _prescriptionImage(after),
        );
      }
      await (_database.update(_database.templateExercises)
            ..where((row) => row.id.equals(exercise.id)))
          .write(
        TemplateExercisesCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      final after = await _requireTemplateExerciseRow(exercise.id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.templateExercisesTable,
        entityId: exercise.id,
        beforeImage: _templateExerciseImage(exercise),
        afterImage: _templateExerciseImage(after),
      );
    }
  }

  Future<void> _setArchived(
    String id, {
    required bool archived,
    required String actor,
    required String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final before = await _requireTemplateRow(id);
      if ((before.deletedAt != null) == archived) {
        return;
      }
      await (_database.update(_database.workoutTemplates)
            ..where((row) => row.id.equals(id)))
          .write(
        WorkoutTemplatesCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(archived ? context.timestamp : null),
        ),
      );
      final after = await _requireTemplateRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.workoutTemplatesTable,
        entityId: id,
        beforeImage: _workoutTemplateImage(before),
        afterImage: _workoutTemplateImage(after),
      );
    });
  }

  Future<WorkoutTemplateRow> _requireTemplateRow(String id) async {
    final row = await (_database.select(_database.workoutTemplates)
          ..where((table) => table.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Workout Template not found: $id.');
    }
    return row;
  }

  Future<WorkoutTemplateRow> _requireActiveTemplateRow(String id) async {
    final row = await _requireTemplateRow(id);
    if (row.deletedAt != null) {
      throw StateError('Workout Template is archived: $id.');
    }
    return row;
  }

  Future<ExerciseRow> _requireExerciseRow(String id) async {
    final row = await (_database.select(_database.exercises)
          ..where((table) => table.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Exercise not found: $id.');
    }
    return row;
  }

  Future<ExerciseRow> _requireActiveExerciseRow(String id) async {
    final row = await _requireExerciseRow(id);
    if (row.deletedAt != null) {
      throw StateError('Exercise is archived: $id.');
    }
    return row;
  }

  Future<TemplateExerciseRow> _requireTemplateExerciseRow(String id) async {
    final row = await (_database.select(_database.templateExercises)
          ..where((table) => table.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Template Exercise not found: $id.');
    }
    return row;
  }

  Future<TemplateExerciseRow> _requireActiveTemplateExerciseRow(
    String id,
  ) async {
    final row = await _requireTemplateExerciseRow(id);
    if (row.deletedAt != null) {
      throw StateError('Template Exercise is removed: $id.');
    }
    return row;
  }

  Future<PrescriptionRow> _requirePrescriptionRow(String id) async {
    final row = await (_database.select(_database.prescriptions)
          ..where((table) => table.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Prescription not found: $id.');
    }
    return row;
  }

  Future<PrescriptionRow> _requireActivePrescriptionRow(String id) async {
    final row = await _requirePrescriptionRow(id);
    if (row.deletedAt != null) {
      throw StateError('Prescription is removed: $id.');
    }
    return row;
  }

  SimpleSelectStatement<$TemplateExercisesTable, TemplateExerciseRow>
      _activeTemplateExerciseRows(String templateId) {
    return _database.select(_database.templateExercises)
      ..where(
        (row) =>
            row.workoutTemplateId.equals(templateId) & row.deletedAt.isNull(),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.position),
        (row) => OrderingTerm.asc(row.id),
      ]);
  }

  SimpleSelectStatement<$PrescriptionsTable, PrescriptionRow>
      _activePrescriptionRows(String templateExerciseId) {
    return _database.select(_database.prescriptions)
      ..where(
        (row) =>
            row.templateExerciseId.equals(templateExerciseId) &
            row.deletedAt.isNull(),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.position),
        (row) => OrderingTerm.asc(row.id),
      ]);
  }

  Future<TemplateGroupRow> _requireTemplateGroupRow(String id) async {
    final row = await (_database.select(_database.templateGroups)
          ..where((table) => table.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Template Group not found: $id.');
    }
    return row;
  }

  Future<TemplateGroupRow> _requireActiveTemplateGroupRow(String id) async {
    final row = await _requireTemplateGroupRow(id);
    if (row.deletedAt != null) {
      throw StateError('Template Group is dissolved: $id.');
    }
    return row;
  }

  Future<TemplateGroupMemberRow> _requireTemplateGroupMemberRow(
    String id,
  ) async {
    final row = await (_database.select(_database.templateGroupMembers)
          ..where((table) => table.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Template Group member not found: $id.');
    }
    return row;
  }

  SimpleSelectStatement<$TemplateGroupsTable, TemplateGroupRow>
      _activeTemplateGroupRows(String templateId) {
    return _database.select(_database.templateGroups)
      ..where(
        (row) =>
            row.workoutTemplateId.equals(templateId) & row.deletedAt.isNull(),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.position),
        (row) => OrderingTerm.asc(row.id),
      ]);
  }

  SimpleSelectStatement<$TemplateGroupMembersTable, TemplateGroupMemberRow>
      _activeTemplateGroupMemberRows({
    String? groupId,
    Iterable<String>? templateExerciseIds,
  }) {
    final query = _database.select(_database.templateGroupMembers)
      ..where((row) => row.deletedAt.isNull());
    if (groupId != null) {
      query.where((row) => row.groupId.equals(groupId));
    }
    if (templateExerciseIds != null) {
      query.where(
        (row) => row.templateExerciseId.isIn(templateExerciseIds),
      );
    }
    query.orderBy([
      (row) => OrderingTerm.asc(row.groupId),
      (row) => OrderingTerm.asc(row.position),
      (row) => OrderingTerm.asc(row.id),
    ]);
    return query;
  }

  Future<bool> _hasActiveTemplateGroupMembership(
    String templateExerciseId,
  ) async {
    final query = _database.select(_database.templateGroupMembers).join([
      innerJoin(
        _database.templateGroups,
        _database.templateGroups.id.equalsExp(
              _database.templateGroupMembers.groupId,
            ) &
            _database.templateGroups.deletedAt.isNull(),
      ),
    ])
      ..where(
        _database.templateGroupMembers.templateExerciseId.equals(
              templateExerciseId,
            ) &
            _database.templateGroupMembers.deletedAt.isNull(),
      )
      ..limit(1);
    return (await query.get()).isNotEmpty;
  }

  Future<List<TemplateExerciseRow>> _requireAvailableTemplateGroupMembers({
    required String templateId,
    required List<String> orderedTemplateExerciseIds,
    String? excludingGroupId,
  }) async {
    final rows = await (_database.select(_database.templateExercises)
          ..where(
            (row) =>
                row.workoutTemplateId.equals(templateId) &
                row.deletedAt.isNull() &
                row.id.isIn(orderedTemplateExerciseIds),
          ))
        .get();
    final byId = <String, TemplateExerciseRow>{
      for (final row in rows) row.id: row,
    };
    if (byId.length != orderedTemplateExerciseIds.length) {
      throw ArgumentError.value(
        orderedTemplateExerciseIds,
        'orderedTemplateExerciseIds',
        'All Template Group members must be active Template Exercises on '
            'the same Workout Template.',
      );
    }

    final memberships = await _activeTemplateGroupMemberRows(
      templateExerciseIds: orderedTemplateExerciseIds,
    ).get();
    final unavailable = memberships.where(
      (member) => member.groupId != excludingGroupId,
    );
    if (unavailable.isNotEmpty) {
      throw ArgumentError.value(
        orderedTemplateExerciseIds,
        'orderedTemplateExerciseIds',
        'A Template Exercise can belong to only one active Template Group.',
      );
    }
    return <TemplateExerciseRow>[
      for (final id in orderedTemplateExerciseIds) byId[id]!,
    ];
  }

  Future<void> _replaceTemplateGroupMembers({
    required String groupId,
    required List<String> orderedTemplateExerciseIds,
    required _WriteContext context,
  }) async {
    final allRows = await (_database.select(_database.templateGroupMembers)
          ..where((row) => row.groupId.equals(groupId))
          ..orderBy([
            (row) => OrderingTerm.desc(row.updatedAt),
            (row) => OrderingTerm.desc(row.id),
          ]))
        .get();
    final activeByExerciseId = <String, TemplateGroupMemberRow>{};
    final archivedByExerciseId = <String, TemplateGroupMemberRow>{};
    for (final row in allRows) {
      if (row.deletedAt == null) {
        activeByExerciseId[row.templateExerciseId] = row;
      } else {
        archivedByExerciseId.putIfAbsent(row.templateExerciseId, () => row);
      }
    }
    final targetIds = orderedTemplateExerciseIds.toSet();
    for (final row in activeByExerciseId.values) {
      if (!targetIds.contains(row.templateExerciseId)) {
        await _archiveTemplateGroupMember(row, context);
      }
    }

    for (var position = 0;
        position < orderedTemplateExerciseIds.length;
        position += 1) {
      final templateExerciseId = orderedTemplateExerciseIds[position];
      final active = activeByExerciseId[templateExerciseId];
      if (active != null) {
        if (active.position != position) {
          await _setTemplateGroupMemberPosition(active, position, context);
        }
        continue;
      }
      final archived = archivedByExerciseId[templateExerciseId];
      if (archived != null) {
        await (_database.update(_database.templateGroupMembers)
              ..where((row) => row.id.equals(archived.id)))
            .write(
          TemplateGroupMembersCompanion(
            position: Value<int>(position),
            updatedAt: Value<DateTime>(context.timestamp),
            deletedAt: const Value<DateTime?>(null),
          ),
        );
        final after = await _requireTemplateGroupMemberRow(archived.id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.templateGroupMembersTable,
          entityId: archived.id,
          beforeImage: _templateGroupMemberImage(archived),
          afterImage: _templateGroupMemberImage(after),
        );
        continue;
      }
      await _insertTemplateGroupMember(
        groupId: groupId,
        templateExerciseId: templateExerciseId,
        position: position,
        context: context,
      );
    }
  }

  Future<void> _insertTemplateGroupMember({
    required String groupId,
    required String templateExerciseId,
    required int position,
    required _WriteContext context,
  }) async {
    final id = _repositories.createId(context.timestamp);
    await _database.into(_database.templateGroupMembers).insert(
          TemplateGroupMembersCompanion.insert(
            id: id,
            groupId: groupId,
            templateExerciseId: templateExerciseId,
            position: position,
            updatedAt: context.timestamp,
          ),
        );
    final after = await _requireTemplateGroupMemberRow(id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.templateGroupMembersTable,
      entityId: id,
      beforeImage: null,
      afterImage: _templateGroupMemberImage(after),
    );
  }

  Future<void> _archiveTemplateGroupMember(
    TemplateGroupMemberRow before,
    _WriteContext context,
  ) async {
    await (_database.update(_database.templateGroupMembers)
          ..where((row) => row.id.equals(before.id)))
        .write(
      TemplateGroupMembersCompanion(
        updatedAt: Value<DateTime>(context.timestamp),
        deletedAt: Value<DateTime?>(context.timestamp),
      ),
    );
    final after = await _requireTemplateGroupMemberRow(before.id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.templateGroupMembersTable,
      entityId: before.id,
      beforeImage: _templateGroupMemberImage(before),
      afterImage: _templateGroupMemberImage(after),
    );
  }

  Future<void> _setTemplateGroupPosition(
    TemplateGroupRow before,
    int position,
    _WriteContext context,
  ) async {
    await (_database.update(_database.templateGroups)
          ..where((row) => row.id.equals(before.id)))
        .write(
      TemplateGroupsCompanion(
        position: Value<int>(position),
        updatedAt: Value<DateTime>(context.timestamp),
      ),
    );
    final after = await _requireTemplateGroupRow(before.id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.templateGroupsTable,
      entityId: before.id,
      beforeImage: _templateGroupImage(before),
      afterImage: _templateGroupImage(after),
    );
  }

  Future<void> _setTemplateGroupMemberPosition(
    TemplateGroupMemberRow before,
    int position,
    _WriteContext context,
  ) async {
    await (_database.update(_database.templateGroupMembers)
          ..where((row) => row.id.equals(before.id)))
        .write(
      TemplateGroupMembersCompanion(
        position: Value<int>(position),
        updatedAt: Value<DateTime>(context.timestamp),
      ),
    );
    final after = await _requireTemplateGroupMemberRow(before.id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.templateGroupMembersTable,
      entityId: before.id,
      beforeImage: _templateGroupMemberImage(before),
      afterImage: _templateGroupMemberImage(after),
    );
  }

  Future<void> _normalizeTemplateGroupPositions(
    String templateId,
    _WriteContext context,
  ) async {
    final rows = await _activeTemplateGroupRows(templateId).get();
    for (var position = 0; position < rows.length; position += 1) {
      final row = rows[position];
      if (row.position != position) {
        await _setTemplateGroupPosition(row, position, context);
      }
    }
  }

  SetValidationResult _validateTemplateGroupDraft(TemplateGroupDraft draft) {
    return plan_validation.validateTemplateGroup(
      name: draft.name,
      colorHex: draft.colorHex,
      rounds: draft.rounds,
      memberIds: draft.orderedTemplateExerciseIds,
    );
  }

  SetValidationResult _validatePrescriptionDraft(
    ExerciseRow exerciseRow,
    PrescriptionDraft draft,
  ) {
    final exercise = _exerciseFromRow(exerciseRow);
    if (draft.mode == PrescriptionMode.fixed &&
        !exercise.type.accepts(draft.values)) {
      throw ArgumentError.value(
        draft.values,
        'values',
        'Fixed Prescription values must match the Exercise dimensions.',
      );
    }
    return plan_validation.validatePrescription(
      mode: draft.mode.name,
      dimensions: exercise.type.dimensions,
      loadMode: exercise.loadMode,
      repeat: draft.repeat,
      restAfterSeconds: draft.restAfter?.inSeconds,
      values: draft.values.values.values,
    );
  }
}

final class _WorkoutTemplateContentWriteResult {
  const _WorkoutTemplateContentWriteResult({
    required this.workoutTemplateId,
  });

  final String workoutTemplateId;
}

enum _WorkoutTemplateContentExercisePolicy {
  activeEditor,
  historicalFact,
}

int _nextTemplateExercisePosition(List<TemplateExerciseRow> rows) {
  var next = 0;
  for (final row in rows) {
    if (row.position >= next) {
      next = row.position + 1;
    }
  }
  return next;
}

int _nextTemplateGroupPosition(List<TemplateGroupRow> rows) {
  var next = 0;
  for (final row in rows) {
    if (row.position >= next) {
      next = row.position + 1;
    }
  }
  return next;
}

int _nextPrescriptionPosition(List<PrescriptionRow> rows) {
  var next = 0;
  for (final row in rows) {
    if (row.position >= next) {
      next = row.position + 1;
    }
  }
  return next;
}

void _requireExactReorderIds({
  required List<String> orderedIds,
  required Iterable<String> activeIds,
  required String label,
}) {
  final expected = activeIds.toSet();
  final received = orderedIds.toSet();
  if (received.length != orderedIds.length ||
      received.length != expected.length ||
      !received.containsAll(expected)) {
    throw ArgumentError.value(
      orderedIds,
      'orderedIds',
      'Reorder ids must include each active $label exactly once.',
    );
  }
}

PrescriptionsCompanion _prescriptionInsertCompanion({
  required String id,
  required String templateExerciseId,
  required int position,
  required PrescriptionDraft draft,
  required DateTime updatedAt,
}) {
  final values = draft.mode == PrescriptionMode.fixed
      ? draft.values
      : LoggedSet.completion();
  final columns = _setColumns(values);
  return PrescriptionsCompanion.insert(
    id: id,
    templateExerciseId: templateExerciseId,
    mode: Value<String>(draft.mode.storageValue),
    position: position,
    repeat: Value<int>(draft.repeat),
    restAfter: Value<int?>(draft.restAfter?.inSeconds),
    loadValue: Value<double?>(columns.load.value),
    loadUnit: Value<String?>(columns.load.unit),
    loadEntered: Value<String?>(columns.load.entered),
    repsValue: Value<double?>(columns.reps.value),
    repsUnit: Value<String?>(columns.reps.unit),
    repsEntered: Value<String?>(columns.reps.entered),
    durationValue: Value<double?>(columns.duration.value),
    durationUnit: Value<String?>(columns.duration.unit),
    durationEntered: Value<String?>(columns.duration.entered),
    distanceValue: Value<double?>(columns.distance.value),
    distanceUnit: Value<String?>(columns.distance.unit),
    distanceEntered: Value<String?>(columns.distance.entered),
    updatedAt: updatedAt,
  );
}

PrescriptionsCompanion _prescriptionValueCompanion(
  PrescriptionDraft draft, {
  required DateTime updatedAt,
}) {
  final values = draft.mode == PrescriptionMode.fixed
      ? draft.values
      : LoggedSet.completion();
  final columns = _setColumns(values);
  return PrescriptionsCompanion(
    mode: Value<String>(draft.mode.storageValue),
    repeat: Value<int>(draft.repeat),
    restAfter: Value<int?>(draft.restAfter?.inSeconds),
    loadValue: Value<double?>(columns.load.value),
    loadUnit: Value<String?>(columns.load.unit),
    loadEntered: Value<String?>(columns.load.entered),
    repsValue: Value<double?>(columns.reps.value),
    repsUnit: Value<String?>(columns.reps.unit),
    repsEntered: Value<String?>(columns.reps.entered),
    durationValue: Value<double?>(columns.duration.value),
    durationUnit: Value<String?>(columns.duration.unit),
    durationEntered: Value<String?>(columns.duration.entered),
    distanceValue: Value<double?>(columns.distance.value),
    distanceUnit: Value<String?>(columns.distance.unit),
    distanceEntered: Value<String?>(columns.distance.entered),
    updatedAt: Value<DateTime>(updatedAt),
  );
}

String _normalizeWorkoutTemplateName(String name) {
  final normalized = name.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(
      name,
      'name',
      'Workout Template name is required.',
    );
  }
  return normalized;
}

List<WorkoutTemplateSummaryRecord> _workoutTemplateSummariesFromJoinedRows(
  AppDatabase database,
  List<TypedResult> rows,
) {
  final templateOrder = <String>[];
  final templatesById = <String, WorkoutTemplateRow>{};
  final exerciseIdsByTemplate = <String, Set<String>>{};
  for (final result in rows) {
    final template = result.readTable(database.workoutTemplates);
    if (!templatesById.containsKey(template.id)) {
      templatesById[template.id] = template;
      templateOrder.add(template.id);
    }
    final exercise = result.readTableOrNull(database.templateExercises);
    if (exercise != null) {
      exerciseIdsByTemplate
          .putIfAbsent(template.id, () => <String>{})
          .add(exercise.id);
    }
  }
  return List<WorkoutTemplateSummaryRecord>.unmodifiable(
    templateOrder.map((id) {
      final template = templatesById[id]!;
      return WorkoutTemplateSummaryRecord(
        id: template.id,
        name: template.name,
        notes: template.notes,
        exerciseCount: exerciseIdsByTemplate[id]?.length ?? 0,
        updatedAt: template.updatedAt.toUtc(),
        deletedAt: template.deletedAt?.toUtc(),
      );
    }),
  );
}

WorkoutTemplateRecord? _workoutTemplateFromJoinedRows(
  AppDatabase database,
  List<TypedResult> rows,
) {
  if (rows.isEmpty) {
    return null;
  }
  final template = rows.first.readTable(database.workoutTemplates);
  final exerciseRowsById = <String, TemplateExerciseRow>{};
  final exercisesById = <String, ExerciseRecord>{};
  final prescriptionsByExercise = <String, Map<String, PrescriptionRow>>{};
  final groupRowsById = <String, TemplateGroupRow>{};
  final membersByGroup = <String, Map<String, TemplateGroupMemberRow>>{};

  for (final result in rows) {
    final templateExercise = result.readTableOrNull(database.templateExercises);
    if (templateExercise == null) {
      continue;
    }
    exerciseRowsById[templateExercise.id] = templateExercise;
    final exerciseRow = result.readTableOrNull(database.exercises);
    if (exerciseRow == null) {
      throw StateError(
        'Exercise not found for Template Exercise ${templateExercise.id}.',
      );
    }
    exercisesById[templateExercise.id] = _exerciseFromRow(exerciseRow);
    final prescription = result.readTableOrNull(database.prescriptions);
    if (prescription != null) {
      prescriptionsByExercise.putIfAbsent(templateExercise.id,
          () => <String, PrescriptionRow>{})[prescription.id] = prescription;
    }
    final group = result.readTableOrNull(database.templateGroups);
    final member = result.readTableOrNull(database.templateGroupMembers);
    if (group != null && member != null) {
      groupRowsById[group.id] = group;
      membersByGroup.putIfAbsent(
        group.id,
        () => <String, TemplateGroupMemberRow>{},
      )[member.id] = member;
    }
  }

  final exerciseRows = exerciseRowsById.values.toList()
    ..sort((left, right) {
      final position = left.position.compareTo(right.position);
      return position != 0 ? position : left.id.compareTo(right.id);
    });
  final exercises = <TemplateExerciseRecord>[];
  for (final row in exerciseRows) {
    final prescriptionRows = (prescriptionsByExercise[row.id]
            ?.values
            .toList() ??
        <PrescriptionRow>[])
      ..sort((left, right) {
        final position = left.position.compareTo(right.position);
        return position != 0 ? position : left.id.compareTo(right.id);
      });
    exercises.add(
      TemplateExerciseRecord(
        id: row.id,
        workoutTemplateId: row.workoutTemplateId,
        exerciseId: row.exerciseId,
        position: row.position,
        note: row.note,
        exercise: exercisesById[row.id]!,
        prescriptions:
            prescriptionRows.map(_prescriptionFromRow).toList(growable: false),
        updatedAt: row.updatedAt.toUtc(),
        deletedAt: row.deletedAt?.toUtc(),
      ),
    );
  }

  final groupRows = groupRowsById.values.toList()
    ..sort((left, right) {
      final position = left.position.compareTo(right.position);
      return position != 0 ? position : left.id.compareTo(right.id);
    });
  final groups = <TemplateGroupRecord>[];
  for (final row in groupRows) {
    final memberRows =
        (membersByGroup[row.id]?.values.toList() ?? <TemplateGroupMemberRow>[])
          ..sort((left, right) {
            final position = left.position.compareTo(right.position);
            return position != 0 ? position : left.id.compareTo(right.id);
          });
    groups.add(_templateGroupFromRows(row, memberRows));
  }

  return WorkoutTemplateRecord(
    id: template.id,
    name: template.name,
    notes: template.notes,
    exercises: exercises,
    groups: groups,
    updatedAt: template.updatedAt.toUtc(),
    deletedAt: template.deletedAt?.toUtc(),
  );
}

TemplateGroupRecord _templateGroupFromRows(
  TemplateGroupRow row,
  List<TemplateGroupMemberRow> memberRows,
) {
  return TemplateGroupRecord(
    id: row.id,
    workoutTemplateId: row.workoutTemplateId,
    name: row.name,
    colorHex: row.colorHex,
    rounds: row.rounds,
    position: row.position,
    members: memberRows
        .map(
          (member) => TemplateGroupMemberRecord(
            id: member.id,
            groupId: member.groupId,
            templateExerciseId: member.templateExerciseId,
            position: member.position,
            updatedAt: member.updatedAt.toUtc(),
            deletedAt: member.deletedAt?.toUtc(),
          ),
        )
        .toList(growable: false),
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );
}

PrescriptionRecord _prescriptionFromRow(PrescriptionRow row) {
  return PrescriptionRecord(
    id: row.id,
    templateExerciseId: row.templateExerciseId,
    mode: _prescriptionModeFromStorage(row.mode),
    position: row.position,
    values: _prescriptionValuesFromRow(row),
    repeat: row.repeat,
    restAfter: row.restAfter == null ? null : Duration(seconds: row.restAfter!),
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );
}

PrescriptionMode _prescriptionModeFromStorage(String value) {
  return switch (value) {
    'fixed' => PrescriptionMode.fixed,
    'copy-previous' || 'copyPrevious' => PrescriptionMode.copyPrevious,
    _ => throw StateError('Unsupported Prescription mode: $value.'),
  };
}

LoggedSet _prescriptionValuesFromRow(PrescriptionRow row) {
  final values = <SetDimensionValue>[];
  _addSetValue(
    values,
    dimension: DimensionId.load,
    entered: row.loadEntered,
    unitName: row.loadUnit,
  );
  _addSetValue(
    values,
    dimension: DimensionId.reps,
    entered: row.repsEntered,
    unitName: row.repsUnit,
  );
  _addSetValue(
    values,
    dimension: DimensionId.duration,
    entered: row.durationEntered,
    unitName: row.durationUnit,
  );
  _addSetValue(
    values,
    dimension: DimensionId.distance,
    entered: row.distanceEntered,
    unitName: row.distanceUnit,
  );
  return values.isEmpty ? LoggedSet.completion() : LoggedSet.fromValues(values);
}
