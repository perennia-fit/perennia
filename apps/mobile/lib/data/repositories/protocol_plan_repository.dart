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
    this.doseId,
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

  /// The Dose that fills the slot, or null when it is unfilled.
  final String? doseId;
}

/// One Protocol's rows on the Planned list, in display order.
final class PlannedRowGroup {
  PlannedRowGroup({
    required this.protocol,
    required Iterable<PlannedRow> rows,
  }) : rows = List<PlannedRow>.unmodifiable(rows);

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
    required Iterable<PlanDay> planDays,
    required Iterable<DayStatus> dayStatuses,
    required Map<String, CompoundRecord> compounds,
    required Map<String, ProtocolOptionRecord> protocols,
  })  : planDays = List<PlanDay>.unmodifiable(planDays),
        dayStatuses = List<DayStatus>.unmodifiable(dayStatuses),
        compounds = Map<String, CompoundRecord>.unmodifiable(compounds),
        protocols = Map<String, ProtocolOptionRecord>.unmodifiable(protocols);

  final ProtocolDayDate localDate;

  /// The device's local date when this was read; it decides Pending against
  /// Not logged, and whether the day has Day Statuses at all.
  final ProtocolDayDate today;
  final List<PlanDay> planDays;
  final List<DayStatus> dayStatuses;

  /// Every Compound a Protocol on this day plans, archived ones included, by
  /// id. A Dose logged from a row snapshots its name and strength from here.
  final Map<String, CompoundRecord> compounds;

  /// Every Protocol on this day, archived ones included, by id.
  final Map<String, ProtocolOptionRecord> protocols;

  bool get isToday => localDate == today;
  bool get isPast => localDate.compareTo(today) < 0;
  bool get isFuture => localDate.compareTo(today) > 0;

  /// The Planned list's rows, grouped under their slot's Protocol. Empty
  /// when nothing is planned on the day, and the list is then hidden (D6).
  ///
  /// Groups are ordered by Protocol name, then id. Within a group, rows are
  /// ordered by planned time (untimed last), then Compound name, then
  /// Compound id, then slot.
  ///
  /// A future day has no Day Statuses, so its slots are numbered by running
  /// the same matching over its PlanDays with no Doses. That keeps one
  /// numbering of slots for every day, rather than a second ordering here.
  late final List<PlannedRowGroup> groups = _groups();

  /// Whether any slot is planned on the day.
  bool get hasPlanned => groups.isNotEmpty;

  List<PlannedRowGroup> _groups() {
    final statuses = isFuture
        ? plan_core.dayStatuses(planDays, const <PlanDose>[], localDate)
        : dayStatuses;
    final rowsByProtocol = <String, List<PlannedRow>>{};
    for (final status in statuses) {
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
                doseId: fill.doseId,
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
    final byName = _compoundName(a.compoundId).compareTo(
      _compoundName(b.compoundId),
    );
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

/// Read-only local repository deriving the Planned list from the plan rows
/// and the day's Doses (D6), the way [RoutineUpNextRepository] derives Up
/// next: nothing is stored, so there is nothing here to write, batch or
/// Activity-Log. Two Drift watches (the plan; the day's Doses) are combined
/// and re-derived through the shared core (`planDays`, `dayStatuses`) on
/// every emission from either.
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
  /// rows name. [today] is the device's local date, read now when omitted.
  /// Re-emits whenever a Protocol, Protocol Member, Schedule Version,
  /// Compound or Dose changes, so the list invalidates mechanically.
  Stream<PlannedDay> watchPlannedDay(
    ProtocolDayDate localDate, {
    ProtocolDayDate? today,
  }) {
    return _combineLatest2(
      _planQuery().watch().map(_planFromJoinedRows),
      _doseQuery(localDate).watch().map(_planDosesFromRows),
      (plan, doses) => _plannedDay(localDate, today, plan, doses),
    );
  }

  /// One read of [watchPlannedDay], for a write that acts on what is stored
  /// at the moment it runs ("Log all planned") rather than on a rendered
  /// snapshot.
  Future<PlannedDay> plannedDay(
    ProtocolDayDate localDate, {
    ProtocolDayDate? today,
  }) async {
    final plan = _planFromJoinedRows(await _planQuery().get());
    final doses = _planDosesFromRows(await _doseQuery(localDate).get());
    return _plannedDay(localDate, today, plan, doses);
  }

  PlannedDay _plannedDay(
    ProtocolDayDate localDate,
    ProtocolDayDate? today,
    _PlanRows plan,
    List<PlanDose> doses,
  ) {
    final resolvedToday = today ?? ProtocolDayDate.fromDateTime(DateTime.now());
    final days = planDays(plan.protocols, localDate, localDate);
    final statuses = localDate.compareTo(resolvedToday) > 0
        ? const <DayStatus>[]
        : dayStatuses(days, doses, resolvedToday);
    return PlannedDay(
      localDate: localDate,
      today: resolvedToday,
      planDays: days,
      dayStatuses: statuses,
      compounds: plan.compounds,
      protocols: plan.protocolOptions,
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
      ..where(protocols.deletedAt.isNull() | protocols.archivedOn.isNotNull())
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
      final versions =
          versionsByMember.putIfAbsent(member.id, () => <ScheduleVersion>[]);
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
                  versions: List<ScheduleVersion>.of(
                    versionsByMember[member.id]!,
                  )..sort(compareScheduleVersions),
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

  /// The day's Doses as matching reads them (D6 step 2): every Dose not
  /// archived, tagged or not, of a catalogue Compound, numbered by local
  /// time and then id. A Dose logged without a Compound can fill no slot.
  SimpleSelectStatement<$DosesTable, DoseRow> _doseQuery(
    ProtocolDayDate localDate,
  ) {
    return _database.select(_database.doses)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            row.localDate.equals(localDate.storageValue) &
            row.compoundId.isNotNull(),
      );
  }

  List<PlanDose> _planDosesFromRows(List<DoseRow> rows) {
    final records = rows.map(_repositories.protocols._doseFromRow).toList()
      ..sort((a, b) {
        final byTime = a.localTime.compareTo(b.localTime);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    final sequenceByCompound = <String, int>{};
    return List<PlanDose>.unmodifiable(
      records.map((dose) {
        final compoundId = dose.compoundId!;
        final sequence = sequenceByCompound[compoundId] ?? 0;
        sequenceByCompound[compoundId] = sequence + 1;
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
    final unit = row.doseUnit;
    final route = row.route;
    return ScheduleVersion(
      id: row.id,
      effectiveFrom: ProtocolDayDate.parse(row.effectiveFrom),
      rule: ScheduleRule.fromJson(jsonDecode(row.rule)),
      amount: PlanAmount(
        amountValue: row.doseAmountValue,
        amountEntered: row.doseAmountEntered,
        unit: unit == null ? null : doseUnitFromName(unit),
        route: route == null ? null : doseRouteFromName(route),
      ),
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
