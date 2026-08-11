part of 'training_repositories.dart';

/// One card in a Routine's derived Up-next suggestion, presentation-ready.
final class RoutineUpNextCardRecord {
  const RoutineUpNextCardRecord({
    required this.routineEntryId,
    required this.workoutTemplateId,
    required this.templateName,
    required this.isDone,
  });

  final String routineEntryId;
  final String workoutTemplateId;
  final String templateName;
  final bool isDone;
}

/// One cadenced Routine's derived Up-next suggestion for the selected
/// Training Day (ROUTINES.md §3.1;). Absent entirely from
/// [RoutineUpNextRepository.watchSuggestions] when the Routine has nothing
/// to suggest — a weekly rest day, or a rotating Cadence whose every slot is
/// empty.
final class RoutineUpNextSummary {
  RoutineUpNextSummary({
    required this.routineId,
    required this.routineName,
    required this.cadenceKind,
    required this.slot,
    required Iterable<RoutineUpNextCardRecord> cards,
  }) : cards = List<RoutineUpNextCardRecord>.unmodifiable(cards);

  final String routineId;
  final String routineName;
  final CadenceKind cadenceKind;
  final int slot;
  final List<RoutineUpNextCardRecord> cards;
}

/// Read-only local repository deriving Up-next suggestions for every
/// cadenced Routine (ROUTINES.md §1.2, §3.1;;).
///
/// Purely a read path over existing rows: no cursor is stored anywhere, so
/// there is nothing here to write, batch, or Activity-Log. Two independent
/// Drift watches (cadenced Routine entries; Template Link history) are
/// combined and re-derived through [deriveRoutineUpNext] on every emission
/// from either.
final class RoutineUpNextRepository {
  const RoutineUpNextRepository._(this._repositories);

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  Stream<List<RoutineUpNextSummary>> watchSuggestions(
    TrainingDayDate selectedDate,
  ) {
    return _combineLatest2(
      _watchCadencedRoutines(),
      _watchTemplateLinkFacts(),
      (routines, factsByRoutineId) {
        final summaries = <RoutineUpNextSummary>[];
        for (final routine in routines) {
          final suggestion = deriveRoutineUpNext(
            cadence: routine.cadence,
            entries: routine.entries,
            links: factsByRoutineId[routine.routineId] ??
                const <UpNextTemplateLinkFact>[],
            selectedDate: selectedDate,
          );
          if (suggestion == null) {
            continue;
          }
          summaries.add(
            RoutineUpNextSummary(
              routineId: routine.routineId,
              routineName: routine.routineName,
              cadenceKind: routine.cadence.kind,
              slot: suggestion.slot,
              cards: suggestion.cards.map(
                (card) => RoutineUpNextCardRecord(
                  routineEntryId: card.routineEntryId,
                  workoutTemplateId: card.workoutTemplateId,
                  templateName: card.templateName,
                  isDone: card.isDone,
                ),
              ),
            ),
          );
        }
        return List<RoutineUpNextSummary>.unmodifiable(summaries);
      },
    );
  }

  Stream<List<_CadencedRoutineEntries>> _watchCadencedRoutines() {
    final query = _database.select(_database.planRoutines).join([
      innerJoin(
        _database.routineEntries,
        _database.routineEntries.routineId.equalsExp(
              _database.planRoutines.id,
            ) &
            _database.routineEntries.deletedAt.isNull(),
      ),
      innerJoin(
        _database.workoutTemplates,
        _database.workoutTemplates.id.equalsExp(
              _database.routineEntries.workoutTemplateId,
            ) &
            _database.workoutTemplates.deletedAt.isNull(),
      ),
    ])
      ..where(
        _database.planRoutines.deletedAt.isNull() &
            _database.planRoutines.cadenceKind.isNotNull(),
      )
      ..orderBy([
        OrderingTerm.asc(_database.planRoutines.name),
        OrderingTerm.asc(_database.planRoutines.id),
        OrderingTerm.asc(_database.routineEntries.position),
        OrderingTerm.asc(_database.routineEntries.id),
      ]);
    return query.watch().map(_cadencedRoutinesFromJoinedRows);
  }

  Stream<Map<String, List<UpNextTemplateLinkFact>>>
      _watchTemplateLinkFacts() {
    final query = _database.select(_database.templateLinks).join([
      innerJoin(
        _database.workoutSessions,
        _database.workoutSessions.id.equalsExp(
          _database.templateLinks.workoutId,
        ),
      ),
    ])
      ..where(
        _database.templateLinks.deletedAt.isNull() &
            _database.templateLinks.routineId.isNotNull() &
            _database.templateLinks.slot.isNotNull() &
            _database.workoutSessions.deletedAt.isNull(),
      )
      ..orderBy([OrderingTerm.asc(_database.templateLinks.id)]);
    return query.watch().map(_templateLinkFactsFromJoinedRows);
  }

  List<_CadencedRoutineEntries> _cadencedRoutinesFromJoinedRows(
    List<TypedResult> rows,
  ) {
    final order = <String>[];
    final routineRowById = <String, PlanRoutineRow>{};
    final entriesByRoutine = <String, List<UpNextRoutineEntry>>{};
    for (final result in rows) {
      final routine = result.readTable(_database.planRoutines);
      if (!routineRowById.containsKey(routine.id)) {
        routineRowById[routine.id] = routine;
        entriesByRoutine[routine.id] = <UpNextRoutineEntry>[];
        order.add(routine.id);
      }
      final entry = result.readTable(_database.routineEntries);
      final template = result.readTable(_database.workoutTemplates);
      final slot = entry.slot;
      if (slot == null) {
        // A Cadence-bearing Routine keeps every active Entry's slot
        // reconciled (setCadence/replaceCadenceLayout); defensive, never
        // hit.
        continue;
      }
      entriesByRoutine[routine.id]!.add(
        UpNextRoutineEntry(
          routineEntryId: entry.id,
          workoutTemplateId: entry.workoutTemplateId,
          templateName: template.name,
          slot: slot,
        ),
      );
    }
    return List<_CadencedRoutineEntries>.unmodifiable(
      order.map((id) {
        final routine = routineRowById[id]!;
        return _CadencedRoutineEntries(
          routineId: routine.id,
          routineName: routine.name,
          cadence: _cadenceFromRow(routine) ??
              (throw StateError(
                'Cadence-bearing Routine ${routine.id} has no Cadence.',
              )),
          entries: entriesByRoutine[id]!,
        );
      }),
    );
  }

  Map<String, List<UpNextTemplateLinkFact>> _templateLinkFactsFromJoinedRows(
    List<TypedResult> rows,
  ) {
    final factsByRoutineId = <String, List<UpNextTemplateLinkFact>>{};
    var sequence = 0;
    for (final result in rows) {
      final link = result.readTable(_database.templateLinks);
      final workout = result.readTable(_database.workoutSessions);
      final routineId = link.routineId;
      final slot = link.slot;
      if (routineId == null || slot == null) {
        continue;
      }
      factsByRoutineId.putIfAbsent(routineId, () => <UpNextTemplateLinkFact>[]).add(
            UpNextTemplateLinkFact(
              workoutTemplateId: link.workoutTemplateId,
              slot: slot,
              sequence: sequence,
              workoutLocalDate: _parseTrainingDayDate(workout.localDate),
            ),
          );
      sequence += 1;
    }
    return factsByRoutineId;
  }
}

final class _CadencedRoutineEntries {
  const _CadencedRoutineEntries({
    required this.routineId,
    required this.routineName,
    required this.cadence,
    required this.entries,
  });

  final String routineId;
  final String routineName;
  final Cadence cadence;
  final List<UpNextRoutineEntry> entries;
}

TrainingDayDate? _parseTrainingDayDate(String value) {
  try {
    return TrainingDayDate.parse(value);
  } on FormatException {
    return null;
  }
}

/// Combines the latest values of two Streams, emitting only once both have
/// produced at least one value. Neither Stream is expected to complete —
/// both are Drift `.watch()` queries, which live for the lifetime of the
/// subscription.
Stream<T> _combineLatest2<A, B, T>(
  Stream<A> streamA,
  Stream<B> streamB,
  T Function(A, B) combine,
) {
  late final StreamController<T> controller;
  StreamSubscription<A>? subscriptionA;
  StreamSubscription<B>? subscriptionB;
  A? latestA;
  B? latestB;
  var hasA = false;
  var hasB = false;

  void emitIfReady() {
    if (hasA && hasB) {
      controller.add(combine(latestA as A, latestB as B));
    }
  }

  controller = StreamController<T>(
    onListen: () {
      subscriptionA = streamA.listen(
        (value) {
          latestA = value;
          hasA = true;
          emitIfReady();
        },
        onError: controller.addError,
      );
      subscriptionB = streamB.listen(
        (value) {
          latestB = value;
          hasB = true;
          emitIfReady();
        },
        onError: controller.addError,
      );
    },
    onCancel: () async {
      await subscriptionA?.cancel();
      await subscriptionB?.cancel();
    },
  );
  return controller.stream;
}
