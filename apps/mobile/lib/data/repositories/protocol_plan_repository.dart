part of 'training_repositories.dart';

/// The label one row of the Planned list carries (D6). A future Protocol Day
/// has no Day Status, so its rows carry [none]: they show their times and
/// amounts with no label and no log action.
enum PlannedRowStatus {
  /// The slot is filled by a Dose.
  logged,

  /// The slot is unfilled, and the day is today.
  pending,

  /// The slot is unfilled, and the day is in the past.
  notLogged,

  /// The day is after today: nothing to label.
  none,
}

/// One row of the Planned list: one numbered planned dose (a slot) of one
/// Compound on the day, under the Protocol that planned it. Derived, never
/// stored.
final class PlannedRow {
  const PlannedRow({
    required this.protocolId,
    required this.compoundId,
    required this.slot,
    required this.plannedLocalTime,
    required this.amount,
    required this.status,
  });

  final String protocolId;
  final String compoundId;

  /// The slot's number among the Compound's planned doses on the day, as
  /// matching numbers it (D6).
  final int slot;

  /// The planned `HH:MM` time, or null for an untimed planned dose.
  final String? plannedLocalTime;

  /// The planned amount, unit and route.
  final PlanAmount amount;
  final PlannedRowStatus status;
}

/// One Protocol's rows on the Planned list, in display order.
final class PlannedRowGroup {
  PlannedRowGroup({required this.protocol, required Iterable<PlannedRow> rows})
      : rows = List<PlannedRow>.unmodifiable(rows);

  /// The Protocol's id and name, also the tag a Dose logged from its rows
  /// carries.
  final ProtocolOptionRecord protocol;
  final List<PlannedRow> rows;
}

/// What the plan says about one Protocol Day, for the Planned list (D6):
/// the day's [PlanDay]s, its [DayStatus]es, and each Compound's and
/// Protocol's record for the rows. Derived on read, never stored.
///
/// [dayStatuses] is empty when [localDate] is after [today]: a future day has
/// no Day Status (D6), only its plan.
final class PlannedDay {
  PlannedDay({
    required this.localDate,
    required this.today,
    required this.day,
    required Iterable<PlanDay> planDays,
    required Iterable<DayStatus> dayStatuses,
    required Iterable<DayStatus> rowStatuses,
    required Map<String, CompoundRecord> compounds,
    required Map<String, ProtocolOptionRecord> protocols,
  })  : planDays = List<PlanDay>.unmodifiable(planDays),
        dayStatuses = List<DayStatus>.unmodifiable(dayStatuses),
        _rowStatuses = List<DayStatus>.unmodifiable(rowStatuses),
        compounds = Map<String, CompoundRecord>.unmodifiable(compounds),
        protocols = Map<String, ProtocolOptionRecord>.unmodifiable(protocols);

  final ProtocolDayDate localDate;

  /// The day's logged Doses, read in the same emission the Day Statuses were
  /// matched against, so the log and the Planned list never disagree.
  final ProtocolDayRecord day;

  /// The device's local date when this was read; it decides Pending against
  /// Not logged, and whether the day has Day Statuses at all.
  final ProtocolDayDate today;
  final List<PlanDay> planDays;
  final List<DayStatus> dayStatuses;

  /// The statuses the rows are read from: [dayStatuses] on today or a past
  /// day. A future day has none, so its slots come from the same matching
  /// run over its PlanDays with no Doses, which keeps one numbering of slots
  /// for every day; no status is read from them.
  final List<DayStatus> _rowStatuses;

  /// Every Compound a Protocol on this day plans, archived ones included, by
  /// id. A Dose logged from a row snapshots its name and strength from here.
  final Map<String, CompoundRecord> compounds;

  /// Every Protocol on this day, archived ones included, by id.
  final Map<String, ProtocolOptionRecord> protocols;

  bool get isToday => localDate == today;
  bool get isFuture => localDate.compareTo(today) > 0;

  /// The Planned list's rows, grouped under their slot's Protocol. Empty
  /// when nothing is planned on the day, and the list is then hidden (D6).
  ///
  /// Groups are ordered by Protocol name, then id. Within a group, rows are
  /// ordered by planned time (untimed last), then Compound name, then
  /// Compound id, then slot.
  late final List<PlannedRowGroup> groups = _groups();

  /// Whether any slot is planned on the day.
  bool get hasPlanned => groups.isNotEmpty;

  List<PlannedRowGroup> _groups() {
    final rowsByProtocol = <String, List<PlannedRow>>{};
    for (final status in _rowStatuses) {
      if (status.localDate != localDate) {
        continue;
      }
      for (final fill in status.fills) {
        rowsByProtocol.putIfAbsent(fill.protocolId, () => <PlannedRow>[]).add(
              PlannedRow(
                protocolId: fill.protocolId,
                compoundId: status.compoundId,
                slot: fill.slot,
                plannedLocalTime: fill.plannedLocalTime,
                amount: fill.amount,
                status: _rowStatus(fill),
              ),
            );
      }
    }

    final protocolIds = rowsByProtocol.keys.toList()
      ..sort((a, b) {
        final byName = _protocolName(a).compareTo(_protocolName(b));
        return byName != 0 ? byName : a.compareTo(b);
      });
    return List<PlannedRowGroup>.unmodifiable(
      protocolIds.map(
        (protocolId) => PlannedRowGroup(
          protocol: protocols[protocolId] ??
              ProtocolOptionRecord(id: protocolId, name: protocolId),
          rows: rowsByProtocol[protocolId]!..sort(_compareRows),
        ),
      ),
    );
  }

  PlannedRowStatus _rowStatus(PlanSlotFill fill) {
    if (isFuture) {
      return PlannedRowStatus.none;
    }
    if (fill.isFilled) {
      return PlannedRowStatus.logged;
    }
    return isToday ? PlannedRowStatus.pending : PlannedRowStatus.notLogged;
  }

  int _compareRows(PlannedRow a, PlannedRow b) {
    final aTime = a.plannedLocalTime;
    final bTime = b.plannedLocalTime;
    if (aTime != bTime) {
      if (aTime == null) {
        return 1;
      }
      if (bTime == null) {
        return -1;
      }
      final byTime = aTime.compareTo(bTime);
      if (byTime != 0) {
        return byTime;
      }
    }
    final byName =
        _compoundName(a.compoundId).compareTo(_compoundName(b.compoundId));
    if (byName != 0) {
      return byName;
    }
    final byId = a.compoundId.compareTo(b.compoundId);
    return byId != 0 ? byId : a.slot.compareTo(b.slot);
  }

  String _protocolName(String protocolId) =>
      protocols[protocolId]?.name ?? protocolId;

  String _compoundName(String compoundId) =>
      compounds[compoundId]?.name ?? compoundId;
}

/// The longest range the Consistency view reads, inclusive of both ends: a
/// year and a day, so a leap year's 366 days fit (Phase 4, file 41).
const int maxConsistencyRangeDays = 366;

void _checkConsistencyRange(ProtocolDayDate from, ProtocolDayDate to) {
  if (from.compareTo(to) > 0) {
    throw ArgumentError('A Consistency range starts on or before its end.');
  }
  if (to.daysBetween(from) + 1 > maxConsistencyRangeDays) {
    throw ArgumentError(
      'A Consistency range holds at most $maxConsistencyRangeDays days.',
    );
  }
}

/// One planned dose (a slot) of a Consistency day, with the logged Dose that
/// fills it, or null when it is unfilled. Which slot a Dose filled is
/// matching's answer (D6), shown so a Dose logged nearer a later planned time
/// is seen filling that one.
final class ConsistencySlot {
  const ConsistencySlot({required this.fill, required this.dose});

  final PlanSlotFill fill;

  /// The Dose that fills the slot, or null when it is unfilled.
  final DoseRecord? dose;
}

/// One date of the Consistency view's day list: its Day Status, if it has
/// one, each slot with the Dose that fills it, and the Doses that filled
/// nothing. Derived, never stored.
final class ConsistencyDay {
  ConsistencyDay({
    required this.localDate,
    required this.status,
    required Iterable<ConsistencySlot> slots,
    required Iterable<DoseRecord> extraDoses,
    required Iterable<DoseRecord> doses,
  })  : slots = List<ConsistencySlot>.unmodifiable(slots),
        extraDoses = List<DoseRecord>.unmodifiable(extraDoses),
        doses = List<DoseRecord>.unmodifiable(doses);

  final ProtocolDayDate localDate;

  /// The date's Day Status, or null when it has none: the Compound is in no
  /// Protocol, or the date is after today (D6). Its Doses are then listed
  /// with no status label, and none of them is an extra.
  final DayStatus? status;

  /// Every slot of the date, in slot order.
  final List<ConsistencySlot> slots;

  /// The Doses that filled no slot (`extraCount` of them), in log order.
  /// Empty when [status] is null: a Dose with no PlanDay is never an extra.
  final List<DoseRecord> extraDoses;

  /// Every Dose of the Compound on the date, in log order.
  final List<DoseRecord> doses;
}

/// What the Consistency view shows for one Compound over a date range (D6):
/// the range's [PlanDay]s, its [DayStatus]es and the Compound's logged
/// Doses, read together so the chart and the day list never disagree.
/// Derived on read, never stored.
final class ConsistencyRange {
  ConsistencyRange({
    required this.compoundId,
    required this.from,
    required this.to,
    required this.today,
    required Iterable<PlanDay> planDays,
    required Iterable<DayStatus> dayStatuses,
    required Iterable<DoseRecord> doses,
    required this.compound,
    required Map<String, ProtocolOptionRecord> protocols,
  })  : planDays = List<PlanDay>.unmodifiable(planDays),
        dayStatuses = List<DayStatus>.unmodifiable(dayStatuses),
        doses = List<DoseRecord>.unmodifiable(doses),
        protocols = Map<String, ProtocolOptionRecord>.unmodifiable(protocols);

  final String compoundId;

  /// The first and last dates of the range, both inclusive.
  final ProtocolDayDate from;
  final ProtocolDayDate to;

  /// The caller's local date when this was read.
  final ProtocolDayDate today;

  /// The Compound's PlanDays, one per Protocol it is a member of and date.
  final List<PlanDay> planDays;

  /// One per date through [today]; empty for a Compound in no Protocol.
  final List<DayStatus> dayStatuses;

  /// The Compound's non-archived Doses in the range, in log order.
  final List<DoseRecord> doses;

  /// The Compound's record, read with the plan, or null when it is in no
  /// Protocol. Its strength resolves a planned amount's active mass.
  final CompoundRecord? compound;

  /// Each Protocol the Compound is a member of, by id.
  final Map<String, ProtocolOptionRecord> protocols;

  /// Whether the Compound is in any Protocol, so its dates have Day Statuses.
  bool get isPlanned => planDays.isNotEmpty;

  /// The day list, newest date first. A Compound in a Protocol lists every
  /// date through [today]; dates with no Day Status (a Compound in no
  /// Protocol, or a date after today) are listed only when they hold a Dose.
  late final List<ConsistencyDay> days = _days();

  /// The ids of every Dose that filled no slot of its day: each day's
  /// [ConsistencyDay.extraDoses]. The one reading of an extra, which the
  /// chart marks and the day list lists, so the two never disagree.
  late final Set<String> extraDoseIds = Set<String>.unmodifiable(<String>{
    for (final day in days)
      for (final dose in day.extraDoses) dose.id,
  });

  List<ConsistencyDay> _days() {
    final dosesByDate = <ProtocolDayDate, List<DoseRecord>>{};
    final doseById = <String, DoseRecord>{};
    for (final dose in doses) {
      dosesByDate.putIfAbsent(dose.localDate, () => <DoseRecord>[]).add(dose);
      doseById[dose.id] = dose;
    }
    final statusByDate = <ProtocolDayDate, DayStatus>{
      for (final status in dayStatuses) status.localDate: status,
    };
    final dates = <ProtocolDayDate>{
      ...statusByDate.keys,
      ...dosesByDate.keys,
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    return List<ConsistencyDay>.unmodifiable(
      dates.map((date) {
        final status = statusByDate[date];
        final dayDoses = dosesByDate[date] ?? const <DoseRecord>[];
        final fills = status?.fills ?? const <PlanSlotFill>[];
        final filledIds = {
          for (final fill in fills)
            if (fill.doseId != null) fill.doseId!,
        };
        return ConsistencyDay(
          localDate: date,
          status: status,
          slots: fills.map(
            (fill) => ConsistencySlot(
              fill: fill,
              dose: fill.doseId == null ? null : doseById[fill.doseId],
            ),
          ),
          extraDoses: status == null
              ? const <DoseRecord>[]
              : dayDoses.where((dose) => !filledIds.contains(dose.id)),
          doses: dayDoses,
        );
      }),
    );
  }
}

/// Read-only local repository deriving the Planned list and the Consistency
/// view from the plan rows and the Doses (D6), the way
/// [RoutineUpNextRepository] derives Up next: nothing is stored, so there is
/// nothing here to write, batch or Activity-Log. Each read combines two Drift
/// watches (the plan; the Doses it is matched against) and re-derives through
/// the shared core (`planDays`, `dayStatuses`) on every emission from either.
/// The Planned list reads the day's Doses through
/// `ProtocolsRepository.watchProtocolDay`, the same watch the day's log
/// shows.
///
/// It builds `PlanProtocol`s and `PlanDose`s from Drift. Rows tombstoned by
/// undo are left out, and archived Protocols and Protocol Members are kept
/// with their `archived_on` (D1): an archived Protocol still plans its past
/// days through that date, and a removed member reads `removed` after it.
final class ProtocolPlanRepository {
  const ProtocolPlanRepository._(this._repositories);

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  /// The Planned list for [localDate]: its PlanDays, its Day Statuses (none
  /// when the date is after [today]), and the Compounds and Protocols its
  /// rows name, with the day's logged Doses they were matched against.
  /// [today] is the caller's local date (its clock), never read here.
  /// Re-emits whenever a Protocol, Protocol Member, Schedule Version,
  /// Compound or Dose changes, so the list invalidates mechanically. It does
  /// not re-emit when midnight passes: the caller re-reads with a new
  /// [today].
  Stream<PlannedDay> watchPlannedDay(
    ProtocolDayDate localDate, {
    required ProtocolDayDate today,
  }) {
    return _combineLatest2(
      _planQuery().watch().map(_planFromJoinedRows),
      _repositories.protocols.watchProtocolDay(localDate),
      (_PlanRows plan, ProtocolDayRecord day) =>
          _plannedDay(localDate, today, plan, day),
    );
  }

  /// One read of [watchPlannedDay], for a write that acts on what is stored
  /// at the moment it runs ("Log all planned") rather than on a rendered
  /// snapshot.
  Future<PlannedDay> plannedDay(
    ProtocolDayDate localDate, {
    required ProtocolDayDate today,
  }) async {
    final plan = _planFromJoinedRows(await _planQuery().get());
    final day = await _repositories.protocols.protocolDay(localDate);
    return _plannedDay(localDate, today, plan, day);
  }

  PlannedDay _plannedDay(
    ProtocolDayDate localDate,
    ProtocolDayDate today,
    _PlanRows plan,
    ProtocolDayRecord day,
  ) {
    final days = planDays(plan.protocols, localDate, localDate);
    final isFuture = localDate.compareTo(today) > 0;
    final statuses = isFuture
        ? const <DayStatus>[]
        : dayStatuses(days, _planDoses(day.doses), today);
    return PlannedDay(
      localDate: localDate,
      today: today,
      day: day,
      planDays: days,
      dayStatuses: statuses,
      rowStatuses: isFuture
          ? dayStatuses(days, const <PlanDose>[], localDate)
          : statuses,
      compounds: plan.compounds,
      protocols: plan.protocolOptions,
    );
  }

  /// The Consistency view's read (D6) for one Compound over [from] through
  /// [to], inclusive: the range's PlanDays, its Day Statuses (none after
  /// [today]) and the Compound's logged Doses in it. [today] is the caller's
  /// local date, read from its clock, as [watchPlannedDay] takes it: it
  /// decides "Pending" against "Not logged", and the repository never reads
  /// a clock.
  ///
  /// The plan is read for every Protocol the Compound is a member of, and
  /// only that Compound's PlanDays are kept, so the PlanDays and Day
  /// Statuses are exactly the ones a read of the whole plan would give for
  /// it: matching and statuses are per Compound and date (D6). A Compound in no Protocol
  /// has no PlanDays, so it has no Day Statuses, and its Doses are still
  /// returned for the view to list by date.
  ///
  /// Re-emits when a Protocol, Protocol Member, Schedule Version, Compound or
  /// Dose changes, like [watchPlannedDay]. Throws an [ArgumentError] when
  /// [from] is after [to], or the range is longer than
  /// [maxConsistencyRangeDays].
  Stream<ConsistencyRange> watchConsistency(
    String compoundId,
    ProtocolDayDate from,
    ProtocolDayDate to, {
    required ProtocolDayDate today,
  }) {
    _checkConsistencyRange(from, to);
    return _combineLatest2(
      _planQuery().watch().map(_planFromJoinedRows),
      _repositories.protocols
          ._activeDoseQuery(
            (row) =>
                row.compoundId.equals(compoundId) &
                row.localDate.isBetweenValues(
                  from.storageValue,
                  to.storageValue,
                ),
          )
          .watch()
          .map(
            (rows) => rows
                .map(_repositories.protocols._doseFromRow)
                .toList(growable: false)
              ..sort(_compareConsistencyDoses),
          ),
      (_PlanRows plan, List<DoseRecord> doses) => _consistencyRange(
        compoundId,
        from,
        to,
        today,
        plan,
        doses,
      ),
    );
  }

  ConsistencyRange _consistencyRange(
    String compoundId,
    ProtocolDayDate from,
    ProtocolDayDate to,
    ProtocolDayDate today,
    _PlanRows plan,
    List<DoseRecord> doses,
  ) {
    // Every Protocol the Compound is a member of, as read, and only this
    // Compound's PlanDays from them: `planDays` decides each Compound and
    // date on its own, so these are the PlanDays a read of the whole plan
    // gives it.
    final protocols = <PlanProtocol>[
      for (final protocol in plan.protocols)
        if (protocol.members.any((member) => member.compoundId == compoundId))
          protocol,
    ];
    final days = <PlanDay>[
      for (final day in planDays(protocols, from, to))
        if (day.compoundId == compoundId) day,
    ];
    return ConsistencyRange(
      compoundId: compoundId,
      from: from,
      to: to,
      today: today,
      planDays: days,
      dayStatuses: dayStatuses(days, _planDoses(doses), today),
      doses: doses,
      compound: plan.compounds[compoundId],
      protocols: <String, ProtocolOptionRecord>{
        for (final protocol in protocols)
          protocol.protocolId: plan.protocolOptions[protocol.protocolId]!,
      },
    );
  }

  JoinedSelectStatement<HasResultSet, dynamic> _planQuery() {
    final protocols = _database.protocols;
    final members = _database.protocolCompounds;
    final compounds = _database.compounds;
    final schedules = _database.schedules;
    final query = _database.select(protocols).join([
      // A member row tombstoned by undo (`deleted_at` with no `archived_on`)
      // never existed (D1); an archived one is kept with its date.
      innerJoin(
        members,
        members.protocolId.equalsExp(protocols.id) &
            (members.deletedAt.isNull() | members.archivedOn.isNotNull()),
      ),
      innerJoin(compounds, compounds.id.equalsExp(members.compoundId)),
      leftOuterJoin(
        schedules,
        schedules.protocolCompoundId.equalsExp(members.id) &
            schedules.deletedAt.isNull(),
      ),
    ])
      ..where(
        protocols.deletedAt.isNull() | protocols.archivedOn.isNotNull(),
      )
      ..orderBy([
        OrderingTerm.asc(protocols.id),
        OrderingTerm.asc(members.id),
        OrderingTerm.asc(schedules.effectiveFrom),
        OrderingTerm.asc(schedules.id),
      ]);
    return query;
  }

  _PlanRows _planFromJoinedRows(List<TypedResult> rows) {
    final protocolRows = <String, ProtocolRow>{};
    final memberRowsByProtocol = <String, Map<String, ProtocolCompoundRow>>{};
    final versionsByMember = <String, List<ScheduleVersion>>{};
    final compounds = <String, CompoundRecord>{};
    for (final result in rows) {
      final protocol = result.readTable(_database.protocols);
      final member = result.readTable(_database.protocolCompounds);
      final compound = result.readTable(_database.compounds);
      final schedule = result.readTableOrNull(_database.schedules);
      protocolRows[protocol.id] = protocol;
      memberRowsByProtocol
          .putIfAbsent(protocol.id, () => <String, ProtocolCompoundRow>{})
          .putIfAbsent(member.id, () => member);
      compounds.putIfAbsent(
        compound.id,
        () => _repositories.protocols._compoundFromRow(compound),
      );
      final versions = versionsByMember.putIfAbsent(
        member.id,
        () => <ScheduleVersion>[],
      );
      if (schedule != null) {
        versions.add(_scheduleVersionFromRow(schedule));
      }
    }

    final planProtocols = <PlanProtocol>[];
    final protocolOptions = <String, ProtocolOptionRecord>{};
    for (final protocol in protocolRows.values) {
      protocolOptions[protocol.id] = ProtocolOptionRecord(
        id: protocol.id,
        name: protocol.name,
      );
      planProtocols.add(
        PlanProtocol(
          protocolId: protocol.id,
          startLocalDate: ProtocolDayDate.parse(protocol.startLocalDate),
          endLocalDate: _nullableProtocolDay(protocol.endLocalDate),
          period: _protocolPeriodFromColumn(protocol.period),
          archivedOn: _nullableProtocolDay(protocol.archivedOn),
          remindersEnabled: protocol.remindersEnabled,
          members: memberRowsByProtocol[protocol.id]!.values.map(
                (member) => PlanMember(
                  memberId: member.id,
                  compoundId: member.compoundId,
                  archivedOn: _nullableProtocolDay(member.archivedOn),
                  // Already in `compareScheduleVersions` order: the query
                  // orders each member's rows by `effective_from`, then id.
                  versions: versionsByMember[member.id]!,
                ),
              ),
        ),
      );
    }
    return _PlanRows(
      protocols: planProtocols,
      compounds: compounds,
      protocolOptions: protocolOptions,
    );
  }

  /// A range's Doses by local date, and each date's in the day log's order
  /// ([_compareDosesByClock]), so a day list's Doses and extras read in clock
  /// order, as the day's log does.
  static int _compareConsistencyDoses(DoseRecord a, DoseRecord b) {
    final byDate = a.localDate.compareTo(b.localDate);
    return byDate != 0 ? byDate : _compareDosesByClock(a, b);
  }

  /// The Doses as matching reads them (D6 step 2): every Dose not archived,
  /// tagged or not, of a catalogue Compound, numbered among its Compound's
  /// Doses on its local date by local time and then id. A Dose logged
  /// without a Compound can fill no slot. One day's Doses (the Planned list)
  /// and a range's (the Consistency view) are numbered the same way.
  List<PlanDose> _planDoses(Iterable<DoseRecord> doses) {
    final records = doses.where((dose) => dose.compoundId != null).toList()
      ..sort((a, b) {
        final byTime = a.localTime.compareTo(b.localTime);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    final sequenceByCompoundDate = <(String, ProtocolDayDate), int>{};
    return List<PlanDose>.unmodifiable(
      records.map((dose) {
        final compoundId = dose.compoundId!;
        final key = (compoundId, dose.localDate);
        final sequence = sequenceByCompoundDate[key] ?? 0;
        sequenceByCompoundDate[key] = sequence + 1;
        return PlanDose(
          doseId: dose.id,
          compoundId: compoundId,
          localDate: dose.localDate,
          localTime: dose.localTime,
          sequence: sequence,
        );
      }),
    );
  }

  ScheduleVersion _scheduleVersionFromRow(ScheduleRow row) {
    final record = _repositories.protocols._scheduleRecordFromRow(row);
    return ScheduleVersion(
      id: record.id,
      effectiveFrom: record.effectiveFrom,
      rule: record.rule,
      amount: record.amount,
    );
  }
}

final class _PlanRows {
  const _PlanRows({
    required this.protocols,
    required this.compounds,
    required this.protocolOptions,
  });

  final List<PlanProtocol> protocols;
  final Map<String, CompoundRecord> compounds;
  final Map<String, ProtocolOptionRecord> protocolOptions;
}
