import '../nutrition/nutrition.dart';

/// Whether a day's energy balance could be computed, or stays indeterminate
/// because one of its two independent sides is unknown.
///
/// There is no "zero" status: a genuinely-zero *complete* side is [computed],
/// not indeterminate (`0 ≠ unknown`, NUTRITION.md §4).
enum EnergyBalanceStatus {
  /// Both sides are known — the net is `energy-in − energy-out`.
  computed,

  /// At least one side is unknown (an incomplete energy-in, or a day with no
  /// calories-burned `Reading`), so no net is fabricated.
  indeterminate,
}

/// The headline cross-family read of M22: a day's **energy-in vs energy-out**
/// balance, computed on demand from two **independent** sources and stored
/// nowhere.
///
/// - Energy-in is the **derived nutrition analytic** — energy aggregated over a
///   day's `Food Entry` snapshots (a [NutrientTotal], unknown-aware).
/// - Energy-out is a **`Metric`** — calories burned, a tracker/monitoring signal
///   from the M12 Metric domain (CONTEXT.md reserves `Metric` for the body's
///   response). It is read as a `Metric` `Reading` value, never reconstructed
///   from authored intake.
///
/// The two are aligned only by local date and combined only here, at read time:
/// neither side writes into the other and **no balance value or in/out
/// association is stored** ("join, never merge"; NUTRITION.md §2, §8). This type
/// is the join itself — a transient value, never a persisted row.
///
/// It is **unknown-aware on both sides** (`0 ≠ unknown`, NUTRITION.md §4): if the
/// in-side is incomplete (a contributing `Food Entry` lacked an energy value) or
/// the out-side is missing (no calories-burned `Reading` that day), the net is
/// [isIndeterminate] rather than fabricating a precise number. A "—" is never
/// silently treated as zero in the subtraction; a complete `0` is a real value.
class EnergyBalance {
  const EnergyBalance._({
    required this.localDate,
    required this.status,
    required this.energyInValue,
    required this.energyOutValue,
    required this.unit,
  });

  /// Derives the balance for [localDate] from the two independent sides.
  ///
  /// [energyIn] is the derived energy total over the day's `Food Entry`s — its
  /// [NutrientTotal.isComplete] flag carries the unknown-aware state. [energyOut]
  /// is the calories-burned `Metric` value for the day, or `null` when there is
  /// no `Reading` (an unknown out-side, never an implicit zero).
  factory EnergyBalance.derive({
    required NutritionDayDate localDate,
    required NutrientTotal energyIn,
    required double? energyOut,
  }) {
    assert(
      energyIn.id == NutrientId.energy,
      'Energy balance in-side must be the energy total.',
    );

    // The in-side is known only when its derived total is complete: an
    // incomplete total means a contributing Food Entry lacked an energy value,
    // so its value is withheld rather than coerced into the subtraction.
    final inKnown = energyIn.isComplete;
    // The out-side is known only when a calories-burned Reading exists.
    final outKnown = energyOut != null;

    final status = inKnown && outKnown
        ? EnergyBalanceStatus.computed
        : EnergyBalanceStatus.indeterminate;

    return EnergyBalance._(
      localDate: localDate,
      status: status,
      energyInValue: inKnown ? energyIn.value : null,
      energyOutValue: energyOut,
      unit: NutrientId.energy.defaultUnit,
    );
  }

  /// The local date the two sides were aligned on (the `Nutrition Day` grouping
  /// on the in-side, the `Reading`'s day on the out-side).
  final NutritionDayDate localDate;

  final EnergyBalanceStatus status;

  /// The known energy-in (kcal), or `null` when the in-side is unknown.
  final double? energyInValue;

  /// The known energy-out (kcal), or `null` when there is no `Reading`.
  final double? energyOutValue;

  /// The shared energy unit of both sides and the net.
  final NutrientUnit unit;

  bool get energyInKnown => energyInValue != null;
  bool get energyOutKnown => energyOutValue != null;

  bool get isIndeterminate => status == EnergyBalanceStatus.indeterminate;

  /// `energy-in − energy-out` when both sides are known, else `null`. Never
  /// fabricated from a missing side — a missing value is held out of the
  /// subtraction, never coerced to `0` (NUTRITION.md §4).
  double? get net {
    if (isIndeterminate) {
      return null;
    }
    return energyInValue! - energyOutValue!;
  }

  /// More was burned than eaten (a negative net) — only meaningful when
  /// [net] is known.
  bool get isDeficit {
    final value = net;
    return value != null && value < 0;
  }

  /// More was eaten than burned (a positive net) — only meaningful when
  /// [net] is known.
  bool get isSurplus {
    final value = net;
    return value != null && value > 0;
  }
}
