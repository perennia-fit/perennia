/// The Protocols domain (CONTEXT.md) — the fourth authored domain.
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

import 'protocol_plan.dart';

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

  /// The last date a `YYYY-MM-DD` value holds.
  static const ProtocolDayDate max =
      ProtocolDayDate(year: 9999, month: 12, day: 31);

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

  /// This date as UTC midnight: the calendar arithmetic below runs here, never
  /// on a local [DateTime]. A local day is 23 or 25 hours long on a
  /// daylight-saving change, so adding 24-hour [Duration]s to local midnight
  /// repeats a date in autumn and skips one in spring (and in a zone whose
  /// change falls at midnight, local midnight itself may not exist). UTC has
  /// no such days, so every date is exactly one day apart from the next.
  DateTime utcMidnight() => DateTime.utc(year, month, day);

  /// The date [days] calendar days after this one (before it, when negative).
  /// Computed in UTC, so it never depends on the device's timezone.
  ProtocolDayDate addDays(int days) {
    final next = DateTime.utc(year, month, day + days);
    return ProtocolDayDate(year: next.year, month: next.month, day: next.day);
  }

  /// The number of calendar days from [other] to this date: positive when
  /// this date is later, zero on the same date. The same UTC arithmetic as
  /// [addDays], so `other.addDays(daysBetween(other)) == this`.
  int daysBetween(ProtocolDayDate other) {
    return utcMidnight().difference(other.utcMidnight()).inDays;
  }

  /// The ISO 8601 weekday of this date: 1 is Monday and 7 is Sunday, as a
  /// Schedule Rule's chosen weekdays store it.
  int get isoWeekday => utcMidnight().weekday;

  /// Calendar order, compared field by field: the plan core compares dates
  /// on every planned day, so this never builds a string.
  @override
  int compareTo(ProtocolDayDate other) {
    if (year != other.year) {
      return year.compareTo(other.year);
    }
    if (month != other.month) {
      return month.compareTo(other.month);
    }
    return day.compareTo(other.day);
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

/// The curated `Dose` amount units. A sealed registry, never
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

/// The curated `Dose` administration routes. Sealed
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
/// across the app.
enum DoseProvenance {
  manual,
  integration,
  agent;
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

/// A `Compound`'s optional strength/concentration: a mass (or
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
  /// ad-hoc Dose / strengthless Compound simply has no strength (its active
  /// mass stays unresolved, never blocking).
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

/// The kind of ONE target outcome a `Protocol` declares: WHAT to correlate, seeding the later `Effect` view (M29) — no
/// analysis happens in this slice. A sealed registry, never
/// free-text. [protocolOutcomeKindLabel] is exhaustive;
/// [protocolOutcomeKindFromName] rejects any value outside the registry.
///
/// - `metric`: correlates one specific catalogue `Metric` (its soft
///   [ProtocolTargetOutcomeDraft.metricId] reference).
/// - `performance`: correlates Workout analytics broadly —
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

/// The input for declaring ONE target outcome on a `Protocol`: WHICH `Metric`/performance to correlate — seeds the later
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

  /// The `performance` outcome (Workout analytics broadly) —
  /// no `Metric` row backs it.
  static const ProtocolTargetOutcomeDraft performance =
      ProtocolTargetOutcomeDraft(kind: ProtocolOutcomeKind.performance);

  final ProtocolOutcomeKind kind;

  /// The referenced `Metric`'s id for a [ProtocolOutcomeKind.metric] outcome;
  /// always null for [ProtocolOutcomeKind.performance].
  final String? metricId;
}

/// A persisted target outcome (plan-only read model).
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

/// A `Dose`'s **resolved active mass**: the active quantity
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
/// [unit] and the snapshotted Compound [strength] (computed on read, NEVER
/// persisted). The same "store inputs, derive the rest"
/// split as `Portion`→grams.
///
/// - "1 capsule" × "5 mg/capsule" → 5 mg (the dose unit IS the strength's
///   per-unit).
/// - A dose already entered in the strength's mass unit (e.g. 250 mg of a
///   5 mg/capsule compound) resolves to itself.
/// - No strength, or a unit matching neither side, leaves it UNRESOLVED (null) —
///   never blocking the log.
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
/// `Compound` at log time. Carries the soft
/// [compoundId] reference plus the denormalized [compoundName] AND
/// [compoundStrength] so the Dose carries its own meaning and renders without
/// its Compound — and survives the Compound being renamed, restrengthened,
/// archived, or deleted. The amount is stored as entered ([amountEntered] is the
/// source of truth; [amountValue] is its numeric projection). [tookAt] is the
/// real dose instant; [timezone]/[localDate] are frozen from it at log time
/// when omitted, and its UTC offset always is.
///
/// [protocolId] is the OPTIONAL, soft tag to a `Protocol`: a Dose logged
/// during a course can be attributed to it, but an untagged ad-hoc Dose remains fully first-class — omitting it (or
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
  /// snapshotted Compound strength (derived on read, never stored). Null when there is no resolvable strength.
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
  /// it.
  final CompoundStrength? compoundStrength;
  final double amountValue;
  final String amountEntered;
  final DoseUnit unit;
  final DoseRoute route;
  final DateTime tookAt;
  final String? timezone;
  final ProtocolDayDate? localDate;
  final DoseProvenance provenance;

  /// The OPTIONAL soft tag to a `Protocol`, or null for an untagged ad-hoc Dose (fully first-class).
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
    this.timezoneOffsetMinutes,
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

  /// A display label only (an abbreviation such as "BRT"), never converted
  /// back to an offset; [timezoneOffsetMinutes] is what fixes the local time.
  final String timezone;
  final ProtocolDayDate localDate;
  final DoseProvenance provenance;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// The UTC offset, in minutes, frozen when the Dose was logged (−180 for
  /// UTC−3). With [tookAt] it gives the Dose's local clock time for good, so
  /// travel never moves it. Null on a Dose logged before the offset was
  /// recorded.
  final int? timezoneOffsetMinutes;

  /// The Dose's local clock time, `HH:MM`, derived on read, never stored:
  /// [tookAt] shifted by its frozen [timezoneOffsetMinutes]. A Dose with no
  /// frozen offset reads in the device's current zone instead, so the app and
  /// the server (which reads it in UTC) can disagree on those older Doses.
  String get localTime {
    final offset = timezoneOffsetMinutes;
    final local = offset == null
        ? tookAt.toLocal()
        : tookAt.toUtc().add(Duration(minutes: offset));
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// The OPTIONAL soft tag to a `Protocol`, or null for an untagged ad-hoc
  /// Dose — fully first-class either way.
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

  /// The resolved active mass of this Dose: derived on read from the entered amount + unit and the frozen Compound
  /// strength snapshot — never stored, and null when there is no resolvable
  /// strength (non-blocking).
  ResolvedActiveMass? get resolvedActiveMass => resolveDoseActiveMass(
        amount: amountValue,
        unit: unit,
        strength: compoundStrength,
      );
}

/// The input for creating/editing a `Protocol`: a named course associating
/// **one or more** `Compound`s (a multi-Compound Protocol is a "stack"). A
/// `Protocol` is a **mutable plan**: creating or editing it never reads or
/// writes a logged `Dose`. [compoundIds] is the ordered membership list.
///
/// The bounds are local dates: [startLocalDate], and [endLocalDate], which
/// is inclusive, or null for an ongoing course. [period] carries the
/// Protocol Period's on/off cycle and its Pauses, or null for neither.
/// [remindersEnabled] is synced plan data: "remind me about this Protocol".
///
/// [schedulesByCompoundId] carries each member Compound's OPTIONAL
/// `Schedule`, keyed by compound id. A compound absent from the map, or
/// mapped to null, carries no Schedule; a `Protocol` with no Schedules at all
/// is still valid. Saving it inserts a new Schedule Version only for a
/// member whose Schedule changed; it never reads or writes a logged `Dose`.
///
/// [targetOutcomes] declares WHICH `Metric`s/performance the `Effect` view
/// correlates; no analysis happens here. Empty is valid.
class ProtocolDraft {
  ProtocolDraft({
    required this.name,
    required this.startLocalDate,
    required List<String> compoundIds,
    this.endLocalDate,
    this.period,
    this.remindersEnabled = false,
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
  final ProtocolDayDate startLocalDate;
  final ProtocolDayDate? endLocalDate;
  final ProtocolPeriod? period;
  final bool remindersEnabled;
  final List<String> compoundIds;
  final Map<String, ScheduleDraft?> schedulesByCompoundId;
  final List<ProtocolTargetOutcomeDraft> targetOutcomes;
}

/// One member `Compound` of a `Protocol` (CONTEXT.md `Protocol Member`): the
/// soft link to the catalogue `Compound` (never a snapshot — a `Protocol` is a
/// live plan, not a logged event) plus its ordering [position] within the
/// stack and its Schedule Versions.
///
/// [currentVersion] is the version with the latest `effectiveFrom` (then the
/// larger id): the one the editor shows, even when it applies only from a
/// future start. [versionInEffectToday] is the version that applies today,
/// or null when none does yet. Both are null for a member with no Schedule
/// Version at all; a version whose rule is [UnscheduledScheduleRule] also
/// means "no Schedule".
class ProtocolMemberRecord {
  const ProtocolMemberRecord({
    required this.id,
    required this.compoundId,
    required this.position,
    this.currentVersion,
    this.versionInEffectToday,
  });

  final String id;
  final String compoundId;
  final int position;
  final ScheduleRecord? currentVersion;
  final ScheduleRecord? versionInEffectToday;
}

/// The input for one member's `Schedule`: its Schedule Rule (which days and
/// times a dose is due, or "as needed") and the planned amount, unit and
/// route. Purely prescriptive: dose-response analysis is ALWAYS derived from
/// the actual logged `Dose`s, never a `Schedule`.
///
/// A `timed` or `untimed` [rule] needs all four amount fields, judged by the
/// same shared two-tier validator as a logged `Dose`. An
/// [AsNeededScheduleRule] or [UnscheduledScheduleRule] plans nothing, so its
/// amount fields are stored null whatever the draft carries.
class ScheduleDraft {
  const ScheduleDraft({
    required this.rule,
    this.doseAmountValue,
    this.doseAmountEntered,
    this.doseUnit,
    this.route,
  });

  final ScheduleRule rule;

  /// The planned dose amount as entered (source of truth for re-display).
  final String? doseAmountEntered;

  /// The planned dose amount's numeric projection.
  final double? doseAmountValue;
  final DoseUnit? doseUnit;
  final DoseRoute? route;
}

/// A persisted Schedule Version (CONTEXT.md `Schedule Version`, plan-only
/// read model): one stored state of a member's `Schedule`, applying from
/// [effectiveFrom]. Versions are insert-only, and editing a Schedule NEVER
/// touches a logged `Dose`. The amount fields are null for an `as_needed` or
/// `unscheduled` [rule].
class ScheduleRecord {
  const ScheduleRecord({
    required this.id,
    required this.protocolCompoundId,
    required this.effectiveFrom,
    required this.rule,
    required this.updatedAt,
    this.doseAmountValue,
    this.doseAmountEntered,
    this.doseUnit,
    this.route,
    this.deletedAt,
  });

  final String id;

  /// The `Protocol`'s member row (`ProtocolCompound`) this version belongs to
  /// — a Schedule always belongs to exactly one member Compound of exactly
  /// one Protocol.
  final String protocolCompoundId;
  final ProtocolDayDate effectiveFrom;
  final ScheduleRule rule;
  final double? doseAmountValue;
  final String? doseAmountEntered;
  final DoseUnit? doseUnit;
  final DoseRoute? route;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// The planned dose + unit as the user would read it back (e.g. "5 g"), or
  /// null when the rule plans no amount.
  String? get doseLabel {
    final entered = doseAmountEntered;
    final unit = doseUnit;
    if (entered == null || unit == null) {
      return null;
    }
    return '$entered ${doseUnitLabel(unit)}';
  }
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
    required this.startLocalDate,
    required List<String> compoundIds,
    this.endLocalDate,
    this.period,
    this.remindersEnabled = false,
  }) : compoundIds = List<String>.unmodifiable(compoundIds);

  final String id;
  final String name;
  final ProtocolDayDate startLocalDate;

  /// Inclusive; null for an ongoing course.
  final ProtocolDayDate? endLocalDate;
  final ProtocolPeriod? period;
  final bool remindersEnabled;
  final List<String> compoundIds;

  bool get isStack => compoundIds.length > 1;
}

/// A persisted `Protocol` (plan read model). Archives via [deletedAt] —
/// history survives, and archiving/editing NEVER cascades to a logged `Dose`.
/// [members] is ordered by [ProtocolMemberRecord.position].
class ProtocolRecord {
  ProtocolRecord({
    required this.id,
    required this.name,
    required this.startLocalDate,
    required Iterable<ProtocolMemberRecord> members,
    required this.updatedAt,
    this.endLocalDate,
    this.period,
    this.remindersEnabled = false,
    this.deletedAt,
    Iterable<ProtocolTargetOutcomeRecord> targetOutcomes =
        const <ProtocolTargetOutcomeRecord>[],
  })  : members = List<ProtocolMemberRecord>.unmodifiable(members),
        targetOutcomes =
            List<ProtocolTargetOutcomeRecord>.unmodifiable(targetOutcomes);

  final String id;
  final String name;
  final ProtocolDayDate startLocalDate;

  /// Inclusive; null for an ongoing course.
  final ProtocolDayDate? endLocalDate;

  /// The on/off cycle and Pauses, or null for neither.
  final ProtocolPeriod? period;
  final bool remindersEnabled;
  final List<ProtocolMemberRecord> members;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// The declared target outcomes — WHICH
  /// Metrics/performance to correlate, seeding the later `Effect` view (M29).
  /// Ordered by [ProtocolTargetOutcomeRecord.position]; empty is fully valid.
  final List<ProtocolTargetOutcomeRecord> targetOutcomes;

  bool get isArchived => deletedAt != null;

  /// A multi-Compound Protocol is a "stack".
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
