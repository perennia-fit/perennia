part of 'training_repositories.dart';

extension on CadenceKind {
  String get storageValue => switch (this) {
        CadenceKind.weekly => 'weekly',
        CadenceKind.rotating => 'rotating',
      };
}

/// One requested slot assignment in a full Routine layout replacement.
final class RoutineEntrySlotPlacement {
  const RoutineEntrySlotPlacement({required this.entryId, required this.slot});

  final String entryId;
  final int slot;
}

/// Authored values of a redesigned Routine collection.
final class RoutinePlanDraft {
  const RoutinePlanDraft({required this.name, this.notes});

  final String name;
  final String? notes;
}

/// Lightweight list representation of a redesigned Routine.
final class RoutinePlanSummaryRecord {
  const RoutinePlanSummaryRecord({
    required this.id,
    required this.name,
    required this.notes,
    required this.cadence,
    required this.entryCount,
    required this.archivedTemplateCount,
    required this.updatedAt,
    required this.deletedAt,
  });

  final String id;
  final String name;
  final String? notes;
  final Cadence? cadence;
  final int entryCount;
  final int archivedTemplateCount;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isArchived => deletedAt != null;
}

/// Complete editable content of one redesigned Routine.
final class RoutinePlanRecord {
  RoutinePlanRecord({
    required this.id,
    required this.name,
    required this.notes,
    required this.cadence,
    required Iterable<RoutineEntryRecord> entries,
    required this.updatedAt,
    required this.deletedAt,
  }) : entries = List<RoutineEntryRecord>.unmodifiable(entries);

  final String id;
  final String name;
  final String? notes;
  final Cadence? cadence;
  final List<RoutineEntryRecord> entries;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isArchived => deletedAt != null;
}

/// One ordered Workout Template reference in a redesigned Routine.
///
/// Template display values are read live from the referenced row. They are
/// never persisted on the Routine Entry, so template edits are visible in
/// every Routine that references it.
final class RoutineEntryRecord {
  const RoutineEntryRecord({
    required this.id,
    required this.routineId,
    required this.workoutTemplateId,
    required this.position,
    required this.slot,
    required this.templateName,
    required this.templateNotes,
    required this.templateDeletedAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  final String id;
  final String routineId;
  final String workoutTemplateId;
  final int position;
  final int? slot;
  final String templateName;
  final String? templateNotes;
  final DateTime? templateDeletedAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get templateIsArchived => templateDeletedAt != null;
}

/// Local repository for the cadence-less Routine collection.
///
/// Every public mutation owns exactly one transaction and one write context,
/// so all rows changed by one user action share an Activity Log batch.
class RoutinePlanRepository {
  const RoutinePlanRepository._(this._repositories);

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  Future<List<RoutinePlanSummaryRecord>> listActiveSummaries() {
    return _listSummaries(archived: false);
  }

  Future<List<RoutinePlanSummaryRecord>> listArchivedSummaries() {
    return _listSummaries(archived: true);
  }

  Future<List<RoutinePlanSummaryRecord>> listAllSummaries() {
    return _listSummaries(archived: null);
  }

  Stream<List<RoutinePlanSummaryRecord>> watchActiveSummaries() {
    return _watchSummaries(archived: false);
  }

  Stream<List<RoutinePlanSummaryRecord>> watchArchivedSummaries() {
    return _watchSummaries(archived: true);
  }

  Stream<List<RoutinePlanSummaryRecord>> watchAllSummaries() {
    return _watchSummaries(archived: null);
  }

  Future<RoutinePlanRecord?> getById(
    String id, {
    bool includeArchived = true,
  }) async {
    return _routinePlanFromJoinedRows(
      _database,
      await _detailQuery(id, includeArchived: includeArchived).get(),
    );
  }

  /// Streams every active Routine with its full ordered entries in one
  /// query — the picker sheet's Routines group source (ROUTINES.md §3.2):
  /// cadenced Routines need their slot layout, collections their ordered
  /// list, and a Template referenced by several Routines must appear under
  /// each of them. Archived Routines are excluded; an active Routine's
  /// entries may still reference an archived Template (`templateIsArchived`
  /// on the entry) — the caller decides whether to filter those out.
  Stream<List<RoutinePlanRecord>> watchActiveDetails() {
    final query = _database.select(_database.planRoutines).join([
      leftOuterJoin(
        _database.routineEntries,
        _database.routineEntries.routineId.equalsExp(
              _database.planRoutines.id,
            ) &
            _database.routineEntries.deletedAt.isNull(),
      ),
      leftOuterJoin(
        _database.workoutTemplates,
        _database.workoutTemplates.id.equalsExp(
          _database.routineEntries.workoutTemplateId,
        ),
      ),
    ])
      ..where(_database.planRoutines.deletedAt.isNull());
    query.orderBy([
      OrderingTerm.asc(_database.planRoutines.name),
      OrderingTerm.asc(_database.planRoutines.id),
      OrderingTerm.asc(_database.routineEntries.position),
      OrderingTerm.asc(_database.routineEntries.id),
    ]);
    return query.watch().map(
          (rows) => _routinePlanDetailsFromJoinedRows(_database, rows),
        );
  }

  Stream<RoutinePlanRecord?> watchById(
    String id, {
    bool includeArchived = true,
  }) {
    return _detailQuery(id, includeArchived: includeArchived).watch().map(
          (rows) => _routinePlanFromJoinedRows(_database, rows),
        );
  }

  /// Validates a Cadence value without writing it.
  SetValidationResult validateCadence(Cadence? cadence) {
    return _validateRoutineCadence(
      cadence,
      slots: const <int?>[],
    );
  }

  /// Replaces a Routine's optional Cadence and defaults every active Entry's
  /// slot from its existing collection order.
  ///
  /// Entry identities, template references, and `position`s are preserved.
  /// Switching Cadence meaning deliberately resets the slot layout because a
  /// weekday and a rotation position are not interchangeable concepts.
  Future<SetValidationResult> setCadence(
    String routineId,
    Cadence? cadence, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final beforeRoutine = await _requireActiveRoutineRow(routineId);
      final entries = await _activeEntryRows(routineId);
      _requireNormalizedRoutineEntryPositions(entries);

      // Validate the Cadence before using its window in modulo arithmetic.
      _validateRoutineCadence(
        cadence,
        slots: const <int?>[],
      ).throwIfRejected();

      final beforeCadence = _cadenceFromRow(beforeRoutine);
      if (_cadencesEqual(beforeCadence, cadence)) {
        final result = _validateRoutineCadence(
          cadence,
          slots: entries.map((entry) => entry.slot),
        );
        result.throwIfRejected();
        return result;
      }

      final defaultSlots = <String, int?>{
        for (final entry in entries)
          entry.id: _defaultRoutineEntrySlot(entry.position, cadence),
      };
      final result = _validateRoutineCadence(
        cadence,
        slots: entries.map((entry) => defaultSlots[entry.id]),
      );
      result.throwIfRejected();

      await (_database.update(_database.planRoutines)
            ..where((row) => row.id.equals(routineId)))
          .write(
        PlanRoutinesCompanion(
          cadenceKind: Value<String?>(cadence?.kind.storageValue),
          cadenceWindow: Value<int?>(cadence?.window),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final afterRoutine = await _requireRoutineRow(routineId);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.planRoutinesTable,
        entityId: routineId,
        beforeImage: _planRoutineImage(beforeRoutine),
        afterImage: _planRoutineImage(afterRoutine),
      );

      for (final entry in entries) {
        await _setEntrySlot(
          entry,
          defaultSlots[entry.id],
          context,
          forceWrite: true,
        );
      }
      return result;
    });
  }

  /// Atomically replaces every active Entry's flattened authored order and
  /// slot. The exact active Entry id set must be supplied once.
  Future<SetValidationResult> replaceCadenceLayout(
    String routineId,
    List<RoutineEntrySlotPlacement> placements, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final routine = await _requireActiveRoutineRow(routineId);
      final cadence = _cadenceFromRow(routine);
      final entries = await _activeEntryRows(routineId);
      _requireExactRoutineEntryOrder(
        entries,
        placements.map((placement) => placement.entryId).toList(),
      );
      final result = _validateRoutineCadence(
        cadence,
        slots: placements.map((placement) => placement.slot),
      );
      result.throwIfRejected();

      final entriesById = <String, RoutineEntryRow>{
        for (final entry in entries) entry.id: entry,
      };
      for (var position = 0; position < placements.length; position += 1) {
        final placement = placements[position];
        await _setEntryPlacement(
          entriesById[placement.entryId]!,
          position: position,
          slot: placement.slot,
          context: context,
        );
      }
      return result;
    });
  }

  /// Moves one active Entry between existing Cadence slots.
  Future<SetValidationResult> moveTemplateReferenceToSlot(
    String entryId,
    int slot, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final target = await _requireActiveEntryRow(entryId);
      final routine = await _requireActiveRoutineRow(target.routineId);
      final cadence = _cadenceFromRow(routine);
      final entries = await _activeEntryRows(target.routineId);
      final result = _validateRoutineCadence(
        cadence,
        slots: entries.map(
          (entry) => entry.id == entryId ? slot : entry.slot,
        ),
      );
      result.throwIfRejected();
      await _setEntrySlot(target, slot, context);
      return result;
    });
  }

  Future<String> create(
    RoutinePlanDraft draft, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final id = _repositories.createId(context.timestamp);
      await _database.into(_database.planRoutines).insert(
            PlanRoutinesCompanion.insert(
              id: id,
              name: _normalizeRoutinePlanName(draft.name),
              notes: Value<String?>(_normalizeOptionalText(draft.notes)),
              updatedAt: context.timestamp,
            ),
          );
      final after = await _requireRoutineRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.planRoutinesTable,
        entityId: id,
        beforeImage: null,
        afterImage: _planRoutineImage(after),
      );
      return id;
    });
  }

  Future<void> updateRoutine(
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
      final before = await _requireActiveRoutineRow(id);
      final normalizedName = _normalizeRoutinePlanName(name);
      final normalizedNotes = _normalizeOptionalText(notes);
      if (before.name == normalizedName && before.notes == normalizedNotes) {
        return;
      }
      await (_database.update(_database.planRoutines)
            ..where((row) => row.id.equals(id)))
          .write(
        PlanRoutinesCompanion(
          name: Value<String>(normalizedName),
          notes: Value<String?>(normalizedNotes),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireRoutineRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.planRoutinesTable,
        entityId: id,
        beforeImage: _planRoutineImage(before),
        afterImage: _planRoutineImage(after),
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

  Future<String> addTemplateReference(
    String routineId,
    String workoutTemplateId, {
    int? slot,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(
      () => _insertTemplateReferenceInContext(
        routineId: routineId,
        workoutTemplateId: workoutTemplateId,
        requestedSlot: slot,
        slotResolution: _RoutineEntrySlotResolution.defaultFromOrder,
        context: context,
      ),
    );
  }

  /// Canonical context-aware Routine Entry insertion for compound writes.
  ///
  /// Capture passes `exact` resolution so collection placement is
  /// semantically distinct from choosing a Cadence slot. Ordinary editor adds
  /// keep the existing order-derived default behavior.
  Future<String> _insertTemplateReferenceInContext({
    required String routineId,
    required String workoutTemplateId,
    required int? requestedSlot,
    required _RoutineEntrySlotResolution slotResolution,
    required _WriteContext context,
  }) async {
    final routine = await _requireActiveRoutineRow(routineId);
    await _requireActiveWorkoutTemplateRow(workoutTemplateId);
    final activeEntries = await _activeEntryRows(routineId);
    _requireNormalizedRoutineEntryPositions(activeEntries);
    final cadence = _cadenceFromRow(routine);
    final position = activeEntries.length;
    final resolvedSlot = switch (slotResolution) {
      _RoutineEntrySlotResolution.defaultFromOrder =>
        requestedSlot ?? _defaultRoutineEntrySlot(position, cadence),
      _RoutineEntrySlotResolution.exact => requestedSlot,
    };
    _validateRoutineCadence(
      cadence,
      slots: <int?>[
        ...activeEntries.map((entry) => entry.slot),
        resolvedSlot,
      ],
    ).throwIfRejected();
    final id = _repositories.createId(context.timestamp);
    await _database.into(_database.routineEntries).insert(
          RoutineEntriesCompanion.insert(
            id: id,
            routineId: routineId,
            workoutTemplateId: workoutTemplateId,
            position: position,
            slot: Value<int?>(resolvedSlot),
            updatedAt: context.timestamp,
          ),
        );
    final after = await _requireEntryRow(id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.routineEntriesTable,
      entityId: id,
      beforeImage: null,
      afterImage: _routineEntryImage(after),
    );
    return id;
  }

  Future<void> removeTemplateReference(
    String entryId, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final target = await _requireEntryRow(entryId);
      if (target.deletedAt != null) {
        return;
      }
      await _requireActiveRoutineRow(target.routineId);
      final activeEntries = await _activeEntryRows(target.routineId);
      _requireNormalizedRoutineEntryPositions(activeEntries);

      await (_database.update(_database.routineEntries)
            ..where((row) => row.id.equals(entryId)))
          .write(
        RoutineEntriesCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      final archived = await _requireEntryRow(entryId);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.routineEntriesTable,
        entityId: entryId,
        beforeImage: _routineEntryImage(target),
        afterImage: _routineEntryImage(archived),
      );

      for (final row in activeEntries.where(
        (row) => row.position > target.position,
      )) {
        await _setEntryPosition(
          row,
          row.position - 1,
          context,
        );
      }
    });
  }

  Future<void> reorderTemplateReferences(
    String routineId,
    List<String> orderedEntryIds, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      await _requireActiveRoutineRow(routineId);
      final activeEntries = await _activeEntryRows(routineId);
      _requireExactRoutineEntryOrder(activeEntries, orderedEntryIds);
      final rowsById = <String, RoutineEntryRow>{
        for (final row in activeEntries) row.id: row,
      };
      for (var position = 0; position < orderedEntryIds.length; position += 1) {
        final row = rowsById[orderedEntryIds[position]]!;
        if (row.position == position) {
          continue;
        }
        await _setEntryPosition(row, position, context);
      }
    });
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
      final before = await _requireRoutineRow(id);
      if ((before.deletedAt != null) == archived) {
        return;
      }
      await (_database.update(_database.planRoutines)
            ..where((row) => row.id.equals(id)))
          .write(
        PlanRoutinesCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(archived ? context.timestamp : null),
        ),
      );
      final after = await _requireRoutineRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.planRoutinesTable,
        entityId: id,
        beforeImage: _planRoutineImage(before),
        afterImage: _planRoutineImage(after),
      );
    });
  }

  Future<List<RoutinePlanSummaryRecord>> _listSummaries({
    required bool? archived,
  }) async {
    return _routinePlanSummariesFromJoinedRows(
      _database,
      await _summaryQuery(archived: archived).get(),
    );
  }

  Stream<List<RoutinePlanSummaryRecord>> _watchSummaries({
    required bool? archived,
  }) {
    return _summaryQuery(archived: archived).watch().map(
          (rows) => _routinePlanSummariesFromJoinedRows(_database, rows),
        );
  }

  Selectable<TypedResult> _summaryQuery({required bool? archived}) {
    final query = _database.select(_database.planRoutines).join([
      leftOuterJoin(
        _database.routineEntries,
        _database.routineEntries.routineId.equalsExp(
              _database.planRoutines.id,
            ) &
            _database.routineEntries.deletedAt.isNull(),
      ),
      leftOuterJoin(
        _database.workoutTemplates,
        _database.workoutTemplates.id.equalsExp(
          _database.routineEntries.workoutTemplateId,
        ),
      ),
    ]);
    if (archived != null) {
      query.where(
        archived
            ? _database.planRoutines.deletedAt.isNotNull()
            : _database.planRoutines.deletedAt.isNull(),
      );
    }
    query.orderBy([
      OrderingTerm.asc(_database.planRoutines.name),
      OrderingTerm.asc(_database.planRoutines.id),
      OrderingTerm.asc(_database.routineEntries.position),
      OrderingTerm.asc(_database.routineEntries.id),
    ]);
    return query;
  }

  Selectable<TypedResult> _detailQuery(
    String id, {
    required bool includeArchived,
  }) {
    final query = _database.select(_database.planRoutines).join([
      leftOuterJoin(
        _database.routineEntries,
        _database.routineEntries.routineId.equalsExp(
              _database.planRoutines.id,
            ) &
            _database.routineEntries.deletedAt.isNull(),
      ),
      leftOuterJoin(
        _database.workoutTemplates,
        _database.workoutTemplates.id.equalsExp(
          _database.routineEntries.workoutTemplateId,
        ),
      ),
    ])
      ..where(_database.planRoutines.id.equals(id));
    if (!includeArchived) {
      query.where(_database.planRoutines.deletedAt.isNull());
    }
    query.orderBy([
      OrderingTerm.asc(_database.routineEntries.position),
      OrderingTerm.asc(_database.routineEntries.id),
    ]);
    return query;
  }

  Future<PlanRoutineRow> _requireRoutineRow(String id) async {
    final row = await (_database.select(_database.planRoutines)
          ..where((table) => table.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Routine not found: $id.');
    }
    return row;
  }

  Future<PlanRoutineRow> _requireActiveRoutineRow(String id) async {
    final row = await _requireRoutineRow(id);
    if (row.deletedAt != null) {
      throw StateError('Routine is archived: $id.');
    }
    return row;
  }

  Future<WorkoutTemplateRow> _requireActiveWorkoutTemplateRow(String id) async {
    final row = await (_database.select(_database.workoutTemplates)
          ..where((table) => table.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Workout Template not found: $id.');
    }
    if (row.deletedAt != null) {
      throw StateError('Workout Template is archived: $id.');
    }
    return row;
  }

  Future<RoutineEntryRow> _requireEntryRow(String id) async {
    final row = await (_database.select(_database.routineEntries)
          ..where((table) => table.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Routine Entry not found: $id.');
    }
    return row;
  }

  Future<RoutineEntryRow> _requireActiveEntryRow(String id) async {
    final row = await _requireEntryRow(id);
    if (row.deletedAt != null) {
      throw StateError('Routine Entry is removed: $id.');
    }
    return row;
  }

  Future<List<RoutineEntryRow>> _activeEntryRows(String routineId) {
    final query = _database.select(_database.routineEntries)
      ..where(
        (row) => row.routineId.equals(routineId) & row.deletedAt.isNull(),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.position),
        (row) => OrderingTerm.asc(row.id),
      ]);
    return query.get();
  }

  Future<void> _setEntryPosition(
    RoutineEntryRow before,
    int position,
    _WriteContext context,
  ) async {
    await (_database.update(_database.routineEntries)
          ..where((row) => row.id.equals(before.id)))
        .write(
      RoutineEntriesCompanion(
        position: Value<int>(position),
        updatedAt: Value<DateTime>(context.timestamp),
      ),
    );
    final after = await _requireEntryRow(before.id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.routineEntriesTable,
      entityId: before.id,
      beforeImage: _routineEntryImage(before),
      afterImage: _routineEntryImage(after),
    );
  }

  Future<void> _setEntrySlot(
    RoutineEntryRow before,
    int? slot,
    _WriteContext context, {
    bool forceWrite = false,
  }) async {
    if (!forceWrite && before.slot == slot) {
      return;
    }
    await (_database.update(_database.routineEntries)
          ..where((row) => row.id.equals(before.id)))
        .write(
      RoutineEntriesCompanion(
        slot: Value<int?>(slot),
        updatedAt: Value<DateTime>(context.timestamp),
      ),
    );
    final after = await _requireEntryRow(before.id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.routineEntriesTable,
      entityId: before.id,
      beforeImage: _routineEntryImage(before),
      afterImage: _routineEntryImage(after),
    );
  }

  Future<void> _setEntryPlacement(
    RoutineEntryRow before, {
    required int position,
    required int slot,
    required _WriteContext context,
  }) async {
    if (before.position == position && before.slot == slot) {
      return;
    }
    await (_database.update(_database.routineEntries)
          ..where((row) => row.id.equals(before.id)))
        .write(
      RoutineEntriesCompanion(
        position: Value<int>(position),
        slot: Value<int?>(slot),
        updatedAt: Value<DateTime>(context.timestamp),
      ),
    );
    final after = await _requireEntryRow(before.id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.routineEntriesTable,
      entityId: before.id,
      beforeImage: _routineEntryImage(before),
      afterImage: _routineEntryImage(after),
    );
  }
}

SetValidationResult _validateRoutineCadence(
  Cadence? cadence, {
  required Iterable<num?> slots,
}) {
  return plan_validation.validateRoutineCadence(
    cadenceKind: cadence?.kind.storageValue,
    cadenceWindow: cadence?.window,
    slots: slots,
  );
}

Cadence? _cadenceFromRow(PlanRoutineRow row) {
  return switch (row.cadenceKind) {
    null when row.cadenceWindow == null => null,
    null => throw StateError(
        'Routine ${row.id} has a Cadence window without a kind.',
      ),
    'weekly' when row.cadenceWindow == null => const Cadence.weekly(),
    'weekly' => throw StateError(
        'Weekly Routine ${row.id} must not store a Cadence window.',
      ),
    'rotating' when row.cadenceWindow != null && row.cadenceWindow! >= 1 =>
      Cadence.rotating(row.cadenceWindow!),
    'rotating' => throw StateError(
        'Rotating Routine ${row.id} must store a positive Cadence window.',
      ),
    final kind => throw StateError(
        'Routine ${row.id} has unsupported Cadence kind: $kind.',
      ),
  };
}

enum _RoutineEntrySlotResolution { defaultFromOrder, exact }

bool _cadencesEqual(Cadence? left, Cadence? right) {
  return left?.kind == right?.kind && left?.window == right?.window;
}

int? _defaultRoutineEntrySlot(int position, Cadence? cadence) {
  if (cadence == null) {
    return null;
  }
  final slotCount = cadence.slotCount;
  if (slotCount < 1) {
    throw StateError('Cadence must have at least one slot.');
  }
  return (position % slotCount) + 1;
}

int? _reconciledRoutineEntrySlot(
  int? slot, {
  required int position,
  required Cadence? cadence,
}) {
  if (cadence == null) {
    return null;
  }
  if (slot != null && slot >= 1 && slot <= cadence.slotCount) {
    return slot;
  }
  return _defaultRoutineEntrySlot(position, cadence);
}

String _normalizeRoutinePlanName(String name) {
  final normalized = name.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(name, 'name', 'Routine name is required.');
  }
  return normalized;
}

void _requireNormalizedRoutineEntryPositions(List<RoutineEntryRow> rows) {
  for (var position = 0; position < rows.length; position += 1) {
    if (rows[position].position != position) {
      throw StateError('Routine Entry positions are not normalized.');
    }
  }
}

void _requireExactRoutineEntryOrder(
  List<RoutineEntryRow> activeRows,
  List<String> orderedIds,
) {
  final activeIds = activeRows.map((row) => row.id).toSet();
  final orderedIdSet = orderedIds.toSet();
  if (orderedIds.length != activeRows.length ||
      orderedIdSet.length != orderedIds.length ||
      !activeIds.containsAll(orderedIdSet)) {
    throw ArgumentError.value(
      orderedIds,
      'orderedEntryIds',
      'Order must contain every active Routine Entry exactly once.',
    );
  }
}

List<RoutinePlanSummaryRecord> _routinePlanSummariesFromJoinedRows(
  AppDatabase database,
  List<TypedResult> rows,
) {
  final routineOrder = <String>[];
  final routinesById = <String, PlanRoutineRow>{};
  final entriesByRoutine = <String, Set<String>>{};
  final archivedEntriesByRoutine = <String, Set<String>>{};
  for (final result in rows) {
    final routine = result.readTable(database.planRoutines);
    if (!routinesById.containsKey(routine.id)) {
      routinesById[routine.id] = routine;
      routineOrder.add(routine.id);
    }
    final entry = result.readTableOrNull(database.routineEntries);
    if (entry == null) {
      continue;
    }
    entriesByRoutine.putIfAbsent(routine.id, () => <String>{}).add(entry.id);
    final template = result.readTableOrNull(database.workoutTemplates);
    if (template == null) {
      throw StateError(
        'Workout Template not found for Routine Entry ${entry.id}.',
      );
    }
    if (template.deletedAt != null) {
      archivedEntriesByRoutine
          .putIfAbsent(routine.id, () => <String>{})
          .add(entry.id);
    }
  }
  return List<RoutinePlanSummaryRecord>.unmodifiable(
    routineOrder.map((id) {
      final routine = routinesById[id]!;
      return RoutinePlanSummaryRecord(
        id: routine.id,
        name: routine.name,
        notes: routine.notes,
        cadence: _cadenceFromRow(routine),
        entryCount: entriesByRoutine[id]?.length ?? 0,
        archivedTemplateCount: archivedEntriesByRoutine[id]?.length ?? 0,
        updatedAt: routine.updatedAt.toUtc(),
        deletedAt: routine.deletedAt?.toUtc(),
      );
    }),
  );
}

/// Groups one flat joined-rows result (Routine ⋈ Entry ⋈ Template) into a
/// list of complete [RoutinePlanRecord]s, preserving the query's Routine
/// order and each Routine's entry position order.
List<RoutinePlanRecord> _routinePlanDetailsFromJoinedRows(
  AppDatabase database,
  List<TypedResult> rows,
) {
  final routineOrder = <String>[];
  final routinesById = <String, PlanRoutineRow>{};
  final entriesByRoutine = <String, Map<String, RoutineEntryRecord>>{};
  for (final result in rows) {
    final routine = result.readTable(database.planRoutines);
    if (!routinesById.containsKey(routine.id)) {
      routinesById[routine.id] = routine;
      routineOrder.add(routine.id);
    }
    final entry = result.readTableOrNull(database.routineEntries);
    if (entry == null) {
      continue;
    }
    final template = result.readTableOrNull(database.workoutTemplates);
    if (template == null) {
      throw StateError(
        'Workout Template not found for Routine Entry ${entry.id}.',
      );
    }
    entriesByRoutine.putIfAbsent(
      routine.id,
      () => <String, RoutineEntryRecord>{},
    )[entry.id] = RoutineEntryRecord(
      id: entry.id,
      routineId: entry.routineId,
      workoutTemplateId: entry.workoutTemplateId,
      position: entry.position,
      slot: entry.slot,
      templateName: template.name,
      templateNotes: template.notes,
      templateDeletedAt: template.deletedAt?.toUtc(),
      updatedAt: entry.updatedAt.toUtc(),
      deletedAt: entry.deletedAt?.toUtc(),
    );
  }
  return List<RoutinePlanRecord>.unmodifiable(
    routineOrder.map((id) {
      final routine = routinesById[id]!;
      final entries =
          (entriesByRoutine[id]?.values.toList() ?? <RoutineEntryRecord>[])
            ..sort((left, right) {
              final position = left.position.compareTo(right.position);
              return position != 0 ? position : left.id.compareTo(right.id);
            });
      return RoutinePlanRecord(
        id: routine.id,
        name: routine.name,
        notes: routine.notes,
        cadence: _cadenceFromRow(routine),
        entries: entries,
        updatedAt: routine.updatedAt.toUtc(),
        deletedAt: routine.deletedAt?.toUtc(),
      );
    }),
  );
}

RoutinePlanRecord? _routinePlanFromJoinedRows(
  AppDatabase database,
  List<TypedResult> rows,
) {
  if (rows.isEmpty) {
    return null;
  }
  final routine = rows.first.readTable(database.planRoutines);
  final entriesById = <String, RoutineEntryRecord>{};
  for (final result in rows) {
    final entry = result.readTableOrNull(database.routineEntries);
    if (entry == null) {
      continue;
    }
    final template = result.readTableOrNull(database.workoutTemplates);
    if (template == null) {
      throw StateError(
        'Workout Template not found for Routine Entry ${entry.id}.',
      );
    }
    entriesById[entry.id] = RoutineEntryRecord(
      id: entry.id,
      routineId: entry.routineId,
      workoutTemplateId: entry.workoutTemplateId,
      position: entry.position,
      slot: entry.slot,
      templateName: template.name,
      templateNotes: template.notes,
      templateDeletedAt: template.deletedAt?.toUtc(),
      updatedAt: entry.updatedAt.toUtc(),
      deletedAt: entry.deletedAt?.toUtc(),
    );
  }
  final entries = entriesById.values.toList()
    ..sort((left, right) {
      final position = left.position.compareTo(right.position);
      return position != 0 ? position : left.id.compareTo(right.id);
    });
  return RoutinePlanRecord(
    id: routine.id,
    name: routine.name,
    notes: routine.notes,
    cadence: _cadenceFromRow(routine),
    entries: entries,
    updatedAt: routine.updatedAt.toUtc(),
    deletedAt: routine.deletedAt?.toUtc(),
  );
}

Map<String, Object?> _planRoutineImage(PlanRoutineRow row) {
  return <String, Object?>{
    'id': row.id,
    'name': row.name,
    'notes': row.notes,
    'cadence_kind': row.cadenceKind,
    'cadence_window': row.cadenceWindow,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _routineEntryImage(RoutineEntryRow row) {
  return <String, Object?>{
    'id': row.id,
    'routine_id': row.routineId,
    'workout_template_id': row.workoutTemplateId,
    'position': row.position,
    'slot': row.slot,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}
