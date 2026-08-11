/// The Protocols domain (CONTEXT.md, PROTOCOLS.md) — the fourth authored domain.
///
/// A `Compound` is the catalogue/template (the analog of an `Exercise`/`Food`);
/// a `Dose` is the self-describing, standalone, timestamped logged event (the
/// analog of a `Set`/`Food Entry`). A `Dose` is authored intake, **never a
/// `Metric`**, and the model **never categorizes a `Compound` by
/// substance type or legality** (a neutral logbook, not a
/// facilitator). Doses are grouped into a derived `Protocol Day` day-view
/// (nothing stored), with each Dose's local date frozen at log time
/// via its captured timezone.
///
/// The Compound/Dose model carries the full strength snapshot
/// immutability and the curated sealed unit/route registries plus the
/// derived resolved active mass (this slice). The shared dose validator
/// and sync land in later slices.
library;

/// A frozen `Protocol Day` local date (YYYY-MM-DD). Mirrors `TrainingDayDate` /
/// `NutritionDayDate`: a `Dose` freezes this at log time from its captured
/// timezone so `Protocol Day` grouping stays stable across travel and
/// device-timezone changes. A presentation concept — data always
/// belongs to a `Dose`, never to the day (CONTEXT.md).
class ProtocolDayDate implements Comparable<ProtocolDayDate> {
  const ProtocolDayDate({
    required this.year,
    required this.month,
    required this.day,
  })  : assert(month >= 1 && month <= 12),
        assert(day >= 1 && day <= 31);

  /// Freezes the local date of [value] in the device's current local timezone.
  factory ProtocolDayDate.fromDateTime(DateTime value) {
    final local = value.toLocal();
    return ProtocolDayDate(
      year: local.year,
      month: local.month,
      day: local.day,
    );
  }

  factory ProtocolDayDate.parse(String value) {
    final match = _storagePattern.firstMatch(value);
    if (match == null) {
      throw FormatException('Expected a YYYY-MM-DD protocol day.', value);
    }

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final normalized = DateTime.utc(year, month, day);
    if (normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw FormatException('Invalid protocol day date.', value);
    }

    return ProtocolDayDate(year: year, month: month, day: day);
  }

  static final _storagePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  final int year;
  final int month;
  final int day;

  String get storageValue {
    final paddedYear = year.toString().padLeft(4, '0');
    final paddedMonth = month.toString().padLeft(2, '0');
    final paddedDay = day.toString().padLeft(2, '0');
    return '$paddedYear-$paddedMonth-$paddedDay';
  }

  DateTime toLocalDateTime() => DateTime(year, month, day);

  ProtocolDayDate addDays(int days) {
    final next = toLocalDateTime().add(Duration(days: days));
    return ProtocolDayDate.fromDateTime(next);
  }

  @override
  int compareTo(ProtocolDayDate other) {
    return storageValue.compareTo(other.storageValue);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ProtocolDayDate &&
            runtimeType == other.runtimeType &&
            year == other.year &&
            month == other.month &&
            day == other.day;
  }

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => storageValue;
}

/// The curated `Dose` amount units (PROTOCOLS.md §1.3). A sealed registry, never
/// free-text — the same discipline as `Dimension`/`Nutrient`. The
/// exhaustive [doseUnitLabel] switch makes the analyzer force a label per
/// member; [doseUnitFromName] rejects any value outside the registry.
enum DoseUnit {
  milligram,
  microgram,
  gram,
  internationalUnit,
  milliliter,
  tablet,
  capsule,
  drop,
  spray,
  puff,
  patch,
  unit;
}

/// The curated `Dose` administration routes (PROTOCOLS.md §1.3). Sealed
/// registry, never free-text. [doseRouteLabel] is exhaustive.
///
/// Deliberately a route registry only — the model NEVER names or categorizes a
/// `Compound` by substance type or legality.
enum DoseRoute {
  oral,
  sublingual,
  subcutaneous,
  intramuscular,
  transdermal,
  intranasal,
  inhaled,
  topical,
  other;
}

/// Who performed the log action (CONTEXT.md `Provenance`): the same stamp used
/// across the app (PROTOCOLS.md §7).
enum DoseProvenance {
  manual,
  integration,
  agent;
}

/// The curated `Schedule` frequency registry (PROTOCOLS.md §1.4, CONTEXT.md
/// `Schedule`): how often a Compound's planned dose is intended. A sealed
/// registry, never free-text — the same discipline as [DoseUnit]/[DoseRoute].
/// Deliberately lean: formal phases/titration steps are deferred
/// (PROTOCOLS.md §12) — a `Schedule` is a flat, purely prescriptive template,
/// never the source of dose-response analysis (that is always the actual
/// logged `Dose`s).
enum ScheduleFrequency {
  onceDaily,
  twiceDaily,
  threeTimesDaily,
  everyOtherDay,
  weekly,
  asNeeded;
}

/// The human-facing label for a [ScheduleFrequency]. Exhaustive — no
/// `default`, so adding a member is a compile error until it is labelled.
String scheduleFrequencyLabel(ScheduleFrequency frequency) {
  return switch (frequency) {
    ScheduleFrequency.onceDaily => 'Once daily',
    ScheduleFrequency.twiceDaily => 'Twice daily',
    ScheduleFrequency.threeTimesDaily => 'Three times daily',
    ScheduleFrequency.everyOtherDay => 'Every other day',
    ScheduleFrequency.weekly => 'Weekly',
    ScheduleFrequency.asNeeded => 'As needed',
  };
}

/// Resolves a stored/entered frequency name to a sealed [ScheduleFrequency]
/// member, REJECTING anything outside the curated registry (never
/// free-text).
ScheduleFrequency scheduleFrequencyFromName(String name) {
  for (final frequency in ScheduleFrequency.values) {
    if (frequency.name == name) {
      return frequency;
    }
  }
  throw ArgumentError.value(
    name,
    'name',
    'Schedule frequency is not in the curated registry.',
  );
}

/// The short human-facing label for a [DoseUnit]. Exhaustive — no `default`, so
/// adding a member is a compile error until it is labelled.
String doseUnitLabel(DoseUnit unit) {
  return switch (unit) {
    DoseUnit.milligram => 'mg',
    DoseUnit.microgram => 'mcg',
    DoseUnit.gram => 'g',
    DoseUnit.internationalUnit => 'IU',
    DoseUnit.milliliter => 'mL',
    DoseUnit.tablet => 'tablet',
    DoseUnit.capsule => 'capsule',
    DoseUnit.drop => 'drop',
    DoseUnit.spray => 'spray',
    DoseUnit.puff => 'puff',
    DoseUnit.patch => 'patch',
    DoseUnit.unit => 'unit',
  };
}

/// The human-facing label for a [DoseRoute]. Exhaustive.
String doseRouteLabel(DoseRoute route) {
  return switch (route) {
    DoseRoute.oral => 'Oral',
    DoseRoute.sublingual => 'Sublingual',
    DoseRoute.subcutaneous => 'Subcutaneous',
    DoseRoute.intramuscular => 'Intramuscular',
    DoseRoute.transdermal => 'Transdermal',
    DoseRoute.intranasal => 'Intranasal',
    DoseRoute.inhaled => 'Inhaled',
    DoseRoute.topical => 'Topical',
    DoseRoute.other => 'Other',
  };
}

/// Resolves a stored/entered unit name to a sealed [DoseUnit] member, REJECTING
/// anything outside the curated registry (never free-text). This is
/// the single chokepoint the validator and storage path both consume,
/// so a malformed unit can never round-trip as data.
DoseUnit doseUnitFromName(String name) {
  for (final unit in DoseUnit.values) {
    if (unit.name == name) {
      return unit;
    }
  }
  throw ArgumentError.value(
    name,
    'name',
    'Dose unit is not in the curated registry.',
  );
}

/// Resolves a stored/entered route name to a sealed [DoseRoute] member,
/// REJECTING anything outside the curated registry (never free-text).
DoseRoute doseRouteFromName(String name) {
  for (final route in DoseRoute.values) {
    if (route.name == name) {
      return route;
    }
  }
  throw ArgumentError.value(
    name,
    'name',
    'Dose route is not in the curated registry.',
  );
}

/// A `Compound`'s optional strength/concentration (PROTOCOLS.md §1.3): a mass (or
/// activity) amount per a countable/volumetric unit — e.g. "5 mg/capsule",
/// "250 mg/mL", "1000 IU/tablet". Both units come from the curated [DoseUnit]
/// registry, never free-text. This is an INPUT the user records on
/// the Compound; the resolved active mass is derived from it on read, never
/// stored.
class CompoundStrength {
  CompoundStrength({
    required this.amount,
    required String amountEntered,
    required this.massUnit,
    required this.perUnit,
  }) : amountEntered = amountEntered.trim() {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Compound strength amount must be positive.',
      );
    }
    if (this.amountEntered.isEmpty) {
      throw ArgumentError.value(
        amountEntered,
        'amountEntered',
        'Entered Compound strength amount must not be empty.',
      );
    }
  }

  /// Parses a canonical `<amount> <massUnit>/<perUnit>` strength (e.g.
  /// "5 mg/capsule"). REJECTS a malformed shape or any unit outside the curated
  /// registry with a [FormatException] — strength is never free-text.
  factory CompoundStrength.parse(String value) {
    final match = _pattern.firstMatch(value.trim());
    if (match == null) {
      throw FormatException(
        'Expected a "<amount> <unit>/<unit>" Compound strength.',
        value,
      );
    }
    final amountEntered = match.group(1)!;
    final amount = double.tryParse(amountEntered);
    if (amount == null) {
      throw FormatException('Compound strength amount is not a number.', value);
    }
    final massLabel = match.group(2)!;
    final perLabel = match.group(3)!;
    final massUnit = _unitForLabel(massLabel);
    final perUnit = _unitForLabel(perLabel);
    if (massUnit == null || perUnit == null) {
      throw FormatException(
        'Compound strength unit is not in the curated registry.',
        value,
      );
    }
    try {
      return CompoundStrength(
        amount: amount,
        amountEntered: amountEntered,
        massUnit: massUnit,
        perUnit: perUnit,
      );
    } on ArgumentError catch (error) {
      throw FormatException(error.message.toString(), value);
    }
  }

  /// Like [CompoundStrength.parse] but tolerant of a null/blank snapshot: an
  /// ad-hoc Dose / strengthless Compound simply has no strength (PROTOCOLS.md
  /// §1.3 — active mass stays unresolved, never blocking).
  static CompoundStrength? tryParse(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return CompoundStrength.parse(trimmed);
  }

  static final _pattern = RegExp(r'^(\S+)\s+([A-Za-z]+)\s*/\s*([A-Za-z]+)$');

  static DoseUnit? _unitForLabel(String label) {
    for (final unit in DoseUnit.values) {
      if (doseUnitLabel(unit) == label) {
        return unit;
      }
    }
    return null;
  }

  /// The amount of [massUnit] delivered by one [perUnit] (e.g. 5).
  final double amount;

  /// The amount as the user entered it (source of truth for re-display).
  final String amountEntered;

  /// The unit the strength is expressed in — the unit the resolved active mass
  /// comes out in (e.g. mg in "5 mg/capsule").
  final DoseUnit massUnit;

  /// The countable/volumetric unit the strength is per (e.g. capsule, mL).
  final DoseUnit perUnit;

  /// The canonical, human-readable + re-parseable label (e.g. "5 mg/capsule").
  String get storageValue =>
      '$amountEntered ${doseUnitLabel(massUnit)}/${doseUnitLabel(perUnit)}';

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CompoundStrength &&
            runtimeType == other.runtimeType &&
            amount == other.amount &&
            amountEntered == other.amountEntered &&
            massUnit == other.massUnit &&
            perUnit == other.perUnit;
  }

  @override
  int get hashCode => Object.hash(amount, amountEntered, massUnit, perUnit);

  @override
  String toString() => storageValue;
}

/// The kind of ONE target outcome a `Protocol` declares (PROTOCOLS.md §1.4,
/// §4): WHAT to correlate, seeding the later `Effect` view (M29) — no
/// analysis happens in this slice. A sealed registry, never
/// free-text. [protocolOutcomeKindLabel] is exhaustive;
/// [protocolOutcomeKindFromName] rejects any value outside the registry.
///
/// - `metric`: correlates one specific catalogue `Metric` (its soft
///   [ProtocolTargetOutcomeDraft.metricId] reference).
/// - `performance`: correlates Workout analytics broadly (PROTOCOLS.md §4) —
///   no `Metric` row backs it.
enum ProtocolOutcomeKind {
  metric,
  performance;
}

/// The human-facing label for a [ProtocolOutcomeKind]. Exhaustive — no
/// `default`, so adding a member is a compile error until it is labelled.
String protocolOutcomeKindLabel(ProtocolOutcomeKind kind) {
  return switch (kind) {
    ProtocolOutcomeKind.metric => 'Metric',
    ProtocolOutcomeKind.performance => 'Performance',
  };
}

/// Resolves a stored/entered outcome kind name to a sealed
/// [ProtocolOutcomeKind] member, REJECTING anything outside the curated
/// registry (never free-text).
ProtocolOutcomeKind protocolOutcomeKindFromName(String name) {
  for (final kind in ProtocolOutcomeKind.values) {
    if (kind.name == name) {
      return kind;
    }
  }
  throw ArgumentError.value(
    name,
    'name',
    'Protocol outcome kind is not in the curated registry.',
  );
}

/// The input for declaring ONE target outcome on a `Protocol` (PROTOCOLS.md
/// §1.4, §4): WHICH `Metric`/performance to correlate — seeds the later
/// `Effect` view (M29). Declaring ZERO target outcomes is fully valid; a
/// Protocol simply MAY declare them. Stored as plan data only — this never
/// computes an `Effect` (that analysis is a later M29 slice).
class ProtocolTargetOutcomeDraft {
  const ProtocolTargetOutcomeDraft({required this.kind, this.metricId});

  /// A `metric` outcome referencing an active catalogue `Metric` by id.
  factory ProtocolTargetOutcomeDraft.metric(String metricId) {
    return ProtocolTargetOutcomeDraft(
      kind: ProtocolOutcomeKind.metric,
      metricId: metricId,
    );
  }

  /// The `performance` outcome (Workout analytics broadly, PROTOCOLS.md §4) —
  /// no `Metric` row backs it.
  static const ProtocolTargetOutcomeDraft performance =
      ProtocolTargetOutcomeDraft(kind: ProtocolOutcomeKind.performance);

  final ProtocolOutcomeKind kind;

  /// The referenced `Metric`'s id for a [ProtocolOutcomeKind.metric] outcome;
  /// always null for [ProtocolOutcomeKind.performance].
  final String? metricId;
}

/// A persisted target outcome (plan-only read model, PROTOCOLS.md §1.4).
/// Archives via the Protocol's own reconciliation (mirrors `Schedule`) —
/// never touches a logged `Dose`, and never computes an `Effect` itself
/// (M29).
class ProtocolTargetOutcomeRecord {
  const ProtocolTargetOutcomeRecord({
    required this.id,
    required this.kind,
    required this.position,
    this.metricId,
  });

  final String id;
  final ProtocolOutcomeKind kind;
  final String? metricId;
  final int position;
}

/// A `Dose`'s **resolved active mass** (PROTOCOLS.md §1.3): the active quantity
/// of a `Dose`, derived on read from amount × unit × the Compound's strength
/// (computed, never stored). Mirrors `Portion`→grams. Exists only
/// when the strength resolves; a Dose without a resolvable strength logs fine
/// with no active mass (non-blocking).
class ResolvedActiveMass {
  const ResolvedActiveMass({
    required this.value,
    required this.unit,
  });

  final double value;
  final DoseUnit unit;

  /// The resolved active mass as the user reads it (e.g. "5 mg").
  String get label => '${_formatValue(value)} ${doseUnitLabel(unit)}';

  static String _formatValue(double value) {
    final fixed = value.toStringAsFixed(6);
    return fixed
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ResolvedActiveMass &&
            runtimeType == other.runtimeType &&
            value == other.value &&
            unit == other.unit;
  }

  @override
  int get hashCode => Object.hash(value, unit);

  @override
  String toString() => label;
}

/// Derives the resolved active mass of a `Dose` from its entered [amount] +
/// [unit] and the snapshotted Compound [strength] (PROTOCOLS.md §1.3 —
/// computed on read, NEVER persisted). The same "store inputs, derive the rest"
/// split as `Portion`→grams.
///
/// - "1 capsule" × "5 mg/capsule" → 5 mg (the dose unit IS the strength's
///   per-unit).
/// - A dose already entered in the strength's mass unit (e.g. 250 mg of a
///   5 mg/capsule compound) resolves to itself.
/// - No strength, or a unit matching neither side, leaves it UNRESOLVED (null) —
///   never blocking the log (PROTOCOLS.md §1.3).
ResolvedActiveMass? resolveDoseActiveMass({
  required double amount,
  required DoseUnit unit,
  required CompoundStrength? strength,
}) {
  if (strength == null || !amount.isFinite) {
    return null;
  }
  if (unit == strength.perUnit) {
    return ResolvedActiveMass(
      value: amount * strength.amount,
      unit: strength.massUnit,
    );
  }
  if (unit == strength.massUnit) {
    return ResolvedActiveMass(value: amount, unit: strength.massUnit);
  }
  return null;
}

/// The input for creating a `Compound` (catalogue/template). A name + default
/// unit/route the user picks (from the curated registries), and an optional
/// structured [strength]/concentration. NEVER carries a substance type or
/// legality field.
class CompoundDraft {
  const CompoundDraft({
    required this.name,
    required this.defaultUnit,
    required this.defaultRoute,
    this.strength,
  });

  final String name;
  final DoseUnit defaultUnit;
  final DoseRoute defaultRoute;

  /// The optional structured strength/concentration (curated units, never
  /// free-text). Null for a Compound with no recorded strength.
  final CompoundStrength? strength;
}

/// The input for logging a `Dose` — a self-describing snapshot of the
/// `Compound` at log time (PROTOCOLS.md §1.1). Carries the soft
/// [compoundId] reference plus the denormalized [compoundName] AND
/// [compoundStrength] so the Dose carries its own meaning and renders without
/// its Compound — and survives the Compound being renamed, restrengthened,
/// archived, or deleted. The amount is stored as entered ([amountEntered] is the
/// source of truth; [amountValue] is its numeric projection). [tookAt] is the
/// real dose instant; [timezone]/[localDate] are frozen from it at log time
/// when omitted.
///
/// [protocolId] is the OPTIONAL, soft tag to a `Protocol` (PROTOCOLS.md §1.2,
/// §1.4): a Dose logged during a course can be attributed to it, but
/// an untagged ad-hoc Dose remains fully first-class — omitting it (or
/// passing null) is always valid. Like the Compound snapshot, [protocolName]
/// is denormalized alongside it so the Dose keeps rendering its own
/// attribution without a live join even if the Protocol is later renamed or
/// archived — the tag never makes a Dose depend on a live Protocol row
/// (self-description holds).
class DoseSnapshotDraft {
  const DoseSnapshotDraft({
    required this.compoundName,
    required this.amountValue,
    required this.amountEntered,
    required this.unit,
    required this.route,
    required this.tookAt,
    this.compoundId,
    this.compoundStrength,
    this.timezone,
    this.localDate,
    this.provenance = DoseProvenance.manual,
    this.protocolId,
    this.protocolName,
  });

  /// The amount + unit as the user would read it back (e.g. "5 mg").
  String get amountLabel => '$amountEntered ${doseUnitLabel(unit)}';

  /// The resolved active mass derived from the entered amount + unit and the
  /// snapshotted Compound strength (PROTOCOLS.md §1.3 — derived on
  /// read, never stored). Null when there is no resolvable strength.
  ResolvedActiveMass? get resolvedActiveMass => resolveDoseActiveMass(
        amount: amountValue,
        unit: unit,
        strength: compoundStrength,
      );

  /// Snapshots [compound]'s identity (id), name, and strength at log time, so a
  /// caller cannot forget to freeze the strength alongside the name. The Dose
  /// thereafter reads its own snapshot, never the live `Compound` row (§1.1).
  factory DoseSnapshotDraft.fromCompound({
    required CompoundRecord compound,
    required double amountValue,
    required String amountEntered,
    required DoseUnit unit,
    required DoseRoute route,
    required DateTime tookAt,
    String? timezone,
    ProtocolDayDate? localDate,
    DoseProvenance provenance = DoseProvenance.manual,
    ProtocolOptionRecord? protocol,
  }) {
    return DoseSnapshotDraft(
      compoundId: compound.id,
      compoundName: compound.name,
      compoundStrength: compound.strength,
      amountValue: amountValue,
      amountEntered: amountEntered,
      unit: unit,
      route: route,
      tookAt: tookAt,
      timezone: timezone,
      localDate: localDate,
      provenance: provenance,
      protocolId: protocol?.id,
      protocolName: protocol?.name,
    );
  }

  /// The soft reference to the catalogue `Compound`, or null for a Dose logged
  /// without one (an ad-hoc Dose never auto-creates a Compound).
  final String? compoundId;
  final String compoundName;

  /// The `Compound`'s structured strength/concentration as it read at log time
  /// (e.g. "1000 IU/capsule"), or null when the Compound had none / the Dose is
  /// ad-hoc. Frozen into the Dose so later edits to the Compound never rewrite
  /// it (PROTOCOLS.md §1.1).
  final CompoundStrength? compoundStrength;
  final double amountValue;
  final String amountEntered;
  final DoseUnit unit;
  final DoseRoute route;
  final DateTime tookAt;
  final String? timezone;
  final ProtocolDayDate? localDate;
  final DoseProvenance provenance;

  /// The OPTIONAL soft tag to a `Protocol` (PROTOCOLS.md §1.4), or
  /// null for an untagged ad-hoc Dose (fully first-class).
  final String? protocolId;

  /// The tagged Protocol's name as it read at tag time, or null when
  /// untagged. Frozen alongside [protocolId] so the Dose renders its own
  /// attribution without a live join (self-description holds).
  final String? protocolName;
}

/// A persisted `Compound` (catalogue read model). Archives via [deletedAt].
class CompoundRecord {
  const CompoundRecord({
    required this.id,
    required this.name,
    required this.defaultUnit,
    required this.defaultRoute,
    required this.updatedAt,
    this.strength,
    this.isFavorite = false,
    this.deletedAt,
  });

  final String id;
  final String name;
  final DoseUnit defaultUnit;
  final DoseRoute defaultRoute;

  /// The optional structured strength/concentration (curated units, never
  /// free-text). Null when the Compound records no strength.
  final CompoundStrength? strength;

  /// A UI-affordance flag only, mirroring `ExerciseRecord.isFavorite`:
  /// hoists this Compound into the Compound list's virtual "Favorites" section.
  /// Never categorizes the Compound.
  final bool isFavorite;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isArchived => deletedAt != null;
}

/// A lightweight active `Compound` picker/read option. This intentionally
/// carries only the identity an Effect source picker needs; default unit,
/// route, strength, favorite state, and lifecycle timestamps are detail/logging
/// concerns.
class CompoundOptionRecord {
  const CompoundOptionRecord({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;
}

/// A lightweight active `Compound` option for Protocol schedule planning.
/// It carries the identity needed by membership chips plus the default
/// unit/route used to seed an optional `Schedule`; strength, favorite state,
/// and lifecycle timestamps stay out of this read path.
class CompoundScheduleOptionRecord {
  const CompoundScheduleOptionRecord({
    required this.id,
    required this.name,
    required this.defaultUnit,
    required this.defaultRoute,
  });

  final String id;
  final String name;
  final DoseUnit defaultUnit;
  final DoseRoute defaultRoute;
}

/// A persisted `Dose` (self-describing logged event read model). Renders from
/// its own snapshot fields, so no `Compound` lookup is required. The
/// [compoundName] and [compoundStrength] are frozen at log time and never
/// re-read from the live `Compound`.
class DoseRecord {
  const DoseRecord({
    required this.id,
    required this.compoundName,
    required this.amountValue,
    required this.amountEntered,
    required this.unit,
    required this.route,
    required this.tookAt,
    required this.timezone,
    required this.localDate,
    required this.provenance,
    required this.updatedAt,
    this.compoundId,
    this.compoundStrength,
    this.deletedAt,
    this.protocolId,
    this.protocolName,
  });

  final String id;
  final String? compoundId;
  final String compoundName;

  /// The `Compound`'s structured strength/concentration as snapshotted at log
  /// time, or null when none was captured. Immutable across any later Compound
  /// edit/lifecycle.
  final CompoundStrength? compoundStrength;
  final double amountValue;
  final String amountEntered;
  final DoseUnit unit;
  final DoseRoute route;
  final DateTime tookAt;
  final String timezone;
  final ProtocolDayDate localDate;
  final DoseProvenance provenance;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// The OPTIONAL soft tag to a `Protocol` (PROTOCOLS.md §1.4), or
  /// null for an untagged ad-hoc Dose — fully first-class either way.
  final String? protocolId;

  /// The tagged Protocol's name as it read at tag time, frozen alongside
  /// [protocolId] (self-description holds even if the Protocol is later
  /// renamed or archived); null when untagged.
  final String? protocolName;

  /// Whether this Dose carries a Protocol tag. An untagged ad-hoc
  /// Dose is equally first-class — this is presentation only.
  bool get isTaggedToProtocol => protocolId != null;

  /// The amount + unit as the user would read it back (e.g. "5 mg").
  String get amountLabel => '$amountEntered ${doseUnitLabel(unit)}';

  /// The resolved active mass of this Dose (PROTOCOLS.md §1.3):
  /// derived on read from the entered amount + unit and the frozen Compound
  /// strength snapshot — never stored, and null when there is no resolvable
  /// strength (non-blocking).
  ResolvedActiveMass? get resolvedActiveMass => resolveDoseActiveMass(
        amount: amountValue,
        unit: unit,
        strength: compoundStrength,
      );
}

/// The input for creating/editing a `Protocol` (PROTOCOLS.md §1.4): the
/// Routine analog — a named, time-bounded course associating **one or more**
/// `Compound`s (a multi-Compound Protocol is a "stack"). A `Protocol` is a
/// **mutable plan**: creating or editing it never reads or writes a logged
/// `Dose` (§1.4). [compoundIds] is the ordered membership list; [endDate]
/// null means an open-ended (ongoing) course.
///
/// [schedulesByCompoundId] carries each member Compound's OPTIONAL `Schedule`
/// (planned dose · frequency · route), keyed by compound id. A
/// compound absent from the map — or mapped to null — simply carries no
/// Schedule; a `Protocol` with no Schedules at all is still fully valid
/// (PROTOCOLS.md §1.4). Editing a Schedule through this draft is plan-only:
/// it never reads or writes a logged `Dose`.
///
/// [targetOutcomes] declares WHICH `Metric`s/performance to correlate
/// (PROTOCOLS.md §1.4, §4) — seeding the later `Effect` view (M29);
/// NO analysis happens here. Empty is fully valid: a Protocol MAY declare
/// target outcomes.
class ProtocolDraft {
  ProtocolDraft({
    required this.name,
    required this.startDate,
    required List<String> compoundIds,
    this.endDate,
    Map<String, ScheduleDraft?>? schedulesByCompoundId,
    List<ProtocolTargetOutcomeDraft>? targetOutcomes,
  })  : compoundIds = List<String>.unmodifiable(compoundIds),
        schedulesByCompoundId = Map<String, ScheduleDraft?>.unmodifiable(
          schedulesByCompoundId ?? const <String, ScheduleDraft?>{},
        ),
        targetOutcomes = List<ProtocolTargetOutcomeDraft>.unmodifiable(
          targetOutcomes ?? const <ProtocolTargetOutcomeDraft>[],
        );

  final String name;
  final DateTime startDate;
  final DateTime? endDate;
  final List<String> compoundIds;
  final Map<String, ScheduleDraft?> schedulesByCompoundId;
  final List<ProtocolTargetOutcomeDraft> targetOutcomes;
}

/// One member `Compound` of a `Protocol`: the soft link to the catalogue
/// `Compound` (never a snapshot — a `Protocol` is a live plan, not a logged
/// event, §1.1 vs §1.4) plus its ordering [position] within the stack and its
/// OPTIONAL [schedule]. A null [schedule] simply means this member
/// has no planned dose/frequency/route recorded — always valid.
class ProtocolMemberRecord {
  const ProtocolMemberRecord({
    required this.id,
    required this.compoundId,
    required this.position,
    this.schedule,
  });

  final String id;
  final String compoundId;
  final int position;
  final ScheduleRecord? schedule;
}

/// The input for creating/editing a `Schedule` (PROTOCOLS.md §1.4): the
/// `Prescription` analog — an OPTIONAL planned dose · frequency · route for
/// one member `Compound` of a `Protocol`. Purely prescriptive: dose-response
/// analysis is ALWAYS derived from the actual logged `Dose`s, never a
/// `Schedule` (so formal phases/titration are out of scope, deferred §12).
/// The dose amount/unit/route run through the SAME shared two-tier validator
/// as a logged `Dose` (PROTOCOLS.md §6) — there is no parallel validator.
class ScheduleDraft {
  const ScheduleDraft({
    required this.doseAmountValue,
    required this.doseAmountEntered,
    required this.doseUnit,
    required this.frequency,
    required this.route,
  });

  /// The planned dose amount as entered (source of truth for re-display).
  final String doseAmountEntered;

  /// The planned dose amount's numeric projection.
  final double doseAmountValue;
  final DoseUnit doseUnit;
  final ScheduleFrequency frequency;
  final DoseRoute route;
}

/// A persisted `Schedule` (plan-only read model, PROTOCOLS.md §1.4). Archives
/// via [deletedAt] — mirrors `Prescription`/`Compound`/`Protocol`: editing or
/// removing a Schedule NEVER touches a logged `Dose` (§7).
class ScheduleRecord {
  const ScheduleRecord({
    required this.id,
    required this.protocolCompoundId,
    required this.doseAmountValue,
    required this.doseAmountEntered,
    required this.doseUnit,
    required this.frequency,
    required this.route,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;

  /// The `Protocol`'s member row (`ProtocolCompound`) this Schedule attaches
  /// to — a Schedule always belongs to exactly one member Compound of exactly
  /// one Protocol.
  final String protocolCompoundId;
  final double doseAmountValue;
  final String doseAmountEntered;
  final DoseUnit doseUnit;
  final ScheduleFrequency frequency;
  final DoseRoute route;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isArchived => deletedAt != null;

  /// The planned dose + unit as the user would read it back (e.g. "5 g").
  String get doseLabel => '$doseAmountEntered ${doseUnitLabel(doseUnit)}';
}

/// A lightweight active `Protocol` picker/read option. This intentionally
/// carries only the identity a `Dose` needs to snapshot for its optional
/// Protocol tag; members, Schedules, target outcomes, and plan timestamps are
/// separate detail concerns.
class ProtocolOptionRecord {
  const ProtocolOptionRecord({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;
}

/// A lightweight active `Protocol` option for the `Effect` source picker.
/// Unlike a Dose tag option, Effect selection needs declared target outcomes
/// for seeding. It still intentionally excludes members and Schedules because
/// those plan details are not source-picker concerns.
class ProtocolEffectOptionRecord {
  ProtocolEffectOptionRecord({
    required this.id,
    required this.name,
    List<ProtocolTargetOutcomeRecord> targetOutcomes =
        const <ProtocolTargetOutcomeRecord>[],
  }) : targetOutcomes =
            List<ProtocolTargetOutcomeRecord>.unmodifiable(targetOutcomes);

  final String id;
  final String name;
  final List<ProtocolTargetOutcomeRecord> targetOutcomes;
}

/// A lightweight active `Protocol` list row summary. The Protocol list only
/// renders identity, window, and ordered member Compound ids; Schedules and
/// target outcomes are detail/edit concerns that load from [ProtocolRecord].
class ProtocolSummaryRecord {
  ProtocolSummaryRecord({
    required this.id,
    required this.name,
    required this.startDate,
    required List<String> compoundIds,
    this.endDate,
  }) : compoundIds = List<String>.unmodifiable(compoundIds);

  final String id;
  final String name;
  final DateTime startDate;
  final DateTime? endDate;
  final List<String> compoundIds;

  bool get isStack => compoundIds.length > 1;
}

/// A persisted `Protocol` (plan read model). Archives via [deletedAt] —
/// history survives, and archiving/editing NEVER cascades to a logged `Dose`
/// (PROTOCOLS.md §7). [members] is ordered by [ProtocolMemberRecord.position].
class ProtocolRecord {
  ProtocolRecord({
    required this.id,
    required this.name,
    required this.startDate,
    required Iterable<ProtocolMemberRecord> members,
    required this.updatedAt,
    this.endDate,
    this.deletedAt,
    Iterable<ProtocolTargetOutcomeRecord> targetOutcomes =
        const <ProtocolTargetOutcomeRecord>[],
  })  : members = List<ProtocolMemberRecord>.unmodifiable(members),
        targetOutcomes =
            List<ProtocolTargetOutcomeRecord>.unmodifiable(targetOutcomes);

  final String id;
  final String name;
  final DateTime startDate;
  final DateTime? endDate;
  final List<ProtocolMemberRecord> members;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// The declared target outcomes (PROTOCOLS.md §1.4, §4) — WHICH
  /// Metrics/performance to correlate, seeding the later `Effect` view (M29).
  /// Ordered by [ProtocolTargetOutcomeRecord.position]; empty is fully valid.
  final List<ProtocolTargetOutcomeRecord> targetOutcomes;

  bool get isArchived => deletedAt != null;

  /// A multi-Compound Protocol is a "stack" (PROTOCOLS.md §1.4).
  bool get isStack => members.length > 1;
}

/// The derived `Protocol Day` view (NOTHING stored): the `Dose`s
/// sharing one frozen local date, computed on read. Mirrors `NutritionDayRecord`
/// / `TrainingDayRecord`. A presentation grouping — data always belongs to a
/// `Dose`.
class ProtocolDayRecord {
  ProtocolDayRecord({
    required this.localDate,
    required Iterable<DoseRecord> doses,
  }) : doses = List<DoseRecord>.unmodifiable(doses);

  final ProtocolDayDate localDate;
  final List<DoseRecord> doses;

  bool get isEmpty => doses.isEmpty;

  int get doseCount => doses.length;
}
