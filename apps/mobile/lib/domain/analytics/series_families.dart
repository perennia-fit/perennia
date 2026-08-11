import '../nutrition/nutrition.dart';

/// The minimum a `Metric` `Reading` contributes to a trend line: when it was
/// taken and its scalar value (or `null` when the Reading has no usable scalar).
///
/// Carrying this small value type keeps the domain free of the data layer — the
/// repository maps its stored `Reading`s onto it, and the domain never imports a
/// storage record.
class MetricReadingPoint {
  const MetricReadingPoint({
    required this.at,
    required this.value,
  });

  final DateTime at;
  final double? value;
}

/// The two series families the trends/goals surface composes.
///
/// This is the observable face of the boundary in NUTRITION.md §2 /:
/// a [metric] is the body's measured state or response (a stored, provenance-
/// stamped `Metric` `Reading`), while a [nutritionAnalytic] is a derived total
/// over authored `Food Entry`s (computed on demand, stored nowhere —).
/// The two are displayed together but **joined, never merged** into a common
/// series store.
enum SeriesFamily {
  metric('Metric', 'Measured signal'),
  nutritionAnalytic('Nutrition', 'Derived from your meals');

  const SeriesFamily(this.label, this.provenanceLabel);

  /// The short family name shown next to each series so a reader can tell a
  /// measured body signal from a derived intake analytic.
  final String label;

  /// A one-line provenance description making the storage model legible (a
  /// signal that is conveyed by more than colour alone, per the a11y rule).
  final String provenanceLabel;
}

/// One point on a trend line, shared across both families so they can be drawn
/// on one screen without merging their stores.
///
/// A `null` [value] is an **unknown gap**, never a `0`: a nutrition analytic
/// whose nutrient was unreported on that day stays Unknown (`0 ≠ unknown`,
/// NUTRITION.md §4) and must never be blended into a neighbouring value.
class TrendDatum {
  const TrendDatum({
    required this.localDate,
    required this.value,
  });

  final NutritionDayDate localDate;
  final double? value;

  bool get isUnknown => value == null;
}

/// A single labelled trend series belonging to exactly one [SeriesFamily].
///
/// The family is carried on the series itself so the rendering layer can label
/// it (more than colour) and keep the two families' provenance distinct even
/// while they share a screen.
class TrendSeries {
  TrendSeries._({
    required this.family,
    required this.name,
    required this.unitLabel,
    required Iterable<TrendDatum> data,
  }) : data = List<TrendDatum>.unmodifiable(data);

  /// A nutrition-analytics series adapted from a derived [NutritionTrend].
  ///
  /// Nothing here is read from a stored series — the trend is computed over
  /// `Food Entry` snapshots. Unknown days stay unknown gaps so the
  /// line never dips to a false zero.
  factory TrendSeries.fromNutritionTrend(NutritionTrend trend) {
    return TrendSeries._(
      family: SeriesFamily.nutritionAnalytic,
      name: nutrientDisplayLabel(trend.nutrient),
      unitLabel: nutrientUnitLabel(trend.nutrient.defaultUnit),
      data: <TrendDatum>[
        for (final point in trend.points)
          TrendDatum(
            localDate: point.localDate,
            value: point.plottableValue,
          ),
      ],
    );
  }

  /// A `Metric` series read straight from stored, provenance-stamped
  /// [MetricReadingPoint]s. The Metric store is the only source — no value is
  /// reconstructed from nutrition data.
  ///
  /// Readings without a usable scalar value are dropped; the remaining points
  /// are ordered chronologically and bucketed onto their `Nutrition Day` for
  /// display alongside the nutrition family.
  factory TrendSeries.fromMetricReadings({
    required String metricName,
    required String unitLabel,
    required Iterable<MetricReadingPoint> readings,
  }) {
    final data = <TrendDatum>[];
    for (final reading in readings) {
      final value = reading.value;
      if (value == null) {
        continue;
      }
      data.add(
        TrendDatum(
          localDate: NutritionDayDate.fromDateTime(reading.at),
          value: value,
        ),
      );
    }
    data.sort((left, right) => left.localDate.compareTo(right.localDate));

    return TrendSeries._(
      family: SeriesFamily.metric,
      name: metricName,
      unitLabel: unitLabel,
      data: List<TrendDatum>.unmodifiable(data),
    );
  }

  final SeriesFamily family;
  final String name;
  final String unitLabel;
  final List<TrendDatum> data;

  /// The points with a comparable (known) value — what a rendered line is drawn
  /// from. Unknown gaps are held out so they never read as a false zero.
  List<TrendDatum> get comparablePoints {
    return List<TrendDatum>.unmodifiable(<TrendDatum>[
      for (final datum in data)
        if (!datum.isUnknown) datum,
    ]);
  }

  bool get hasComparablePoints => comparablePoints.isNotEmpty;
}

/// The two series families presented together on the trends surface.
///
/// They are held in **two separate lists** — there is no merged series store.
/// This is the type-level statement of "join, never merge" (NUTRITION.md §2):
/// the `Metric` family is read from the Metric repository, the nutrition family
/// is computed over `Food Entry`s, and neither writes into a shared table.
class TwoSeriesFamilies {
  TwoSeriesFamilies({
    required Iterable<TrendSeries> metricSeries,
    required Iterable<TrendSeries> nutritionSeries,
  })  : metricSeries = List<TrendSeries>.unmodifiable(metricSeries),
        nutritionSeries = List<TrendSeries>.unmodifiable(nutritionSeries) {
    assert(
      this.metricSeries.every((s) => s.family == SeriesFamily.metric),
      'The metric family must hold only Metric series.',
    );
    assert(
      this
          .nutritionSeries
          .every((s) => s.family == SeriesFamily.nutritionAnalytic),
      'The nutrition family must hold only nutrition-analytic series.',
    );
  }

  final List<TrendSeries> metricSeries;
  final List<TrendSeries> nutritionSeries;

  bool get hasMetricFamily => metricSeries.isNotEmpty;
  bool get hasNutritionFamily => nutritionSeries.isNotEmpty;
  bool get hasBothFamilies => hasMetricFamily && hasNutritionFamily;

  /// Every series across both families, for iteration only. The families stay
  /// distinct — this convenience never collapses them into one store.
  List<TrendSeries> get allSeries {
    return List<TrendSeries>.unmodifiable(<TrendSeries>[
      ...metricSeries,
      ...nutritionSeries,
    ]);
  }
}
