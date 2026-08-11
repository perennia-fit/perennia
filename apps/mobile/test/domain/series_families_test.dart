import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/analytics/series_families.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';

void main() {
  group('SeriesFamily', () {
    test('the two families are distinct and self-describing', () {
      expect(SeriesFamily.values, hasLength(2));
      expect(SeriesFamily.metric.label, 'Metric');
      expect(SeriesFamily.nutritionAnalytic.label, 'Nutrition');
      // Provenance is spelled out so the family is legible, not implied.
      expect(SeriesFamily.metric.provenanceLabel, isNotEmpty);
      expect(SeriesFamily.nutritionAnalytic.provenanceLabel, isNotEmpty);
      expect(
        SeriesFamily.metric.provenanceLabel,
        isNot(SeriesFamily.nutritionAnalytic.provenanceLabel),
      );
    });
  });

  group('TrendSeries.fromNutritionTrend', () {
    test('carries the nutrition family and preserves unknown gaps as null', () {
      final range = NutritionDayRange(
        start: const NutritionDayDate(year: 2026, month: 6, day: 25),
        end: const NutritionDayDate(year: 2026, month: 6, day: 26),
      );
      final trend = NutritionTrend.forNutrient(
        nutrient: NutrientId.carbohydrate,
        range: range,
        days: <NutritionDayRecord>[
          _nutritionDay(25, carbohydrate: 220),
          // 26th: carbs unknown (only energy was logged).
          _nutritionDay(26, carbohydrate: null),
        ],
        target: null,
      );

      final series = TrendSeries.fromNutritionTrend(trend);

      expect(series.family, SeriesFamily.nutritionAnalytic);
      expect(series.name, 'Carbs');
      expect(series.unitLabel, 'g');
      expect(series.data, hasLength(2));
      expect(() => series.data.clear(), throwsUnsupportedError);
      // Day 25 is a real value; day 26 is an unknown gap, NOT a coerced 0.
      final known = series.data.firstWhere((d) => d.localDate.day == 25);
      final gap = series.data.firstWhere((d) => d.localDate.day == 26);
      expect(known.value, 220);
      expect(known.isUnknown, isFalse);
      expect(gap.value, isNull);
      expect(gap.isUnknown, isTrue);
      // Only the complete day is comparable / plottable.
      final comparablePoints = series.comparablePoints;
      expect(comparablePoints, hasLength(1));
      expect(comparablePoints.single.localDate.day, 25);
      expect(() => comparablePoints.clear(), throwsUnsupportedError);
    });
  });

  group('TrendSeries.fromMetricReadings', () {
    test('carries the metric family and reads stored Reading values', () {
      final series = TrendSeries.fromMetricReadings(
        metricName: 'Calories Burned',
        unitLabel: 'kcal',
        readings: <MetricReadingPoint>[
          _reading(26, 2600),
          _reading(25, 2400),
        ],
      );

      expect(series.family, SeriesFamily.metric);
      expect(series.name, 'Calories Burned');
      // Stored Readings are real, complete signals — never unknown gaps.
      expect(series.data.map((d) => d.value), <double?>[2400, 2600]);
      expect(series.data.every((d) => !d.isUnknown), isTrue);
      // Points are ordered chronologically for rendering.
      expect(
        series.data.map((d) => d.localDate.day),
        <int>[25, 26],
      );
    });

    test('drops Readings with no usable scalar value', () {
      final series = TrendSeries.fromMetricReadings(
        metricName: 'Calories Burned',
        unitLabel: 'kcal',
        readings: <MetricReadingPoint>[
          _reading(25, 2400),
          _readingWithoutScalar(26),
        ],
      );

      expect(series.data, hasLength(1));
      expect(series.data.single.value, 2400);
      expect(() => series.data.clear(), throwsUnsupportedError);
    });
  });

  group('TwoSeriesFamilies', () {
    test('keeps the families in separate lists — join, never merge', () {
      final metricSeries = TrendSeries.fromMetricReadings(
        metricName: 'Calories Burned',
        unitLabel: 'kcal',
        readings: <MetricReadingPoint>[_reading(26, 2600)],
      );
      final nutritionSeries = TrendSeries.fromNutritionTrend(
        NutritionTrend.forNutrient(
          nutrient: NutrientId.energy,
          range: NutritionDayRange(
            start: const NutritionDayDate(year: 2026, month: 6, day: 26),
            end: const NutritionDayDate(year: 2026, month: 6, day: 26),
          ),
          days: <NutritionDayRecord>[_nutritionDay(26, energy: 2100)],
          target: null,
        ),
      );

      final metricFamily = <TrendSeries>[metricSeries];
      final nutritionFamily = <TrendSeries>[nutritionSeries];
      final families = TwoSeriesFamilies(
        metricSeries: metricFamily,
        nutritionSeries: nutritionFamily,
      );
      metricFamily.clear();
      nutritionFamily.clear();

      // The two families remain distinct collections, never a single merged
      // series list.
      expect(families.metricSeries, hasLength(1));
      expect(families.nutritionSeries, hasLength(1));
      expect(() => families.metricSeries.clear(), throwsUnsupportedError);
      expect(() => families.nutritionSeries.clear(), throwsUnsupportedError);
      expect(
        families.metricSeries.single.family,
        SeriesFamily.metric,
      );
      expect(
        families.nutritionSeries.single.family,
        SeriesFamily.nutritionAnalytic,
      );
      // Every series, whichever the family, is labelled with its family.
      final allSeries = families.allSeries;
      expect(allSeries.map((s) => s.family).toSet(), <SeriesFamily>{
        SeriesFamily.metric,
        SeriesFamily.nutritionAnalytic,
      });
      expect(() => allSeries.clear(), throwsUnsupportedError);
      expect(families.hasBothFamilies, isTrue);
    });

    test('reports when one family is missing', () {
      final families = TwoSeriesFamilies(
        metricSeries: const <TrendSeries>[],
        nutritionSeries: <TrendSeries>[
          TrendSeries.fromNutritionTrend(
            NutritionTrend.forNutrient(
              nutrient: NutrientId.energy,
              range: NutritionDayRange(
                start: const NutritionDayDate(year: 2026, month: 6, day: 26),
                end: const NutritionDayDate(year: 2026, month: 6, day: 26),
              ),
              days: <NutritionDayRecord>[_nutritionDay(26, energy: 2100)],
              target: null,
            ),
          ),
        ],
      );

      expect(families.hasBothFamilies, isFalse);
      expect(families.hasMetricFamily, isFalse);
      expect(families.hasNutritionFamily, isTrue);
    });
  });
}

NutritionDayRecord _nutritionDay(
  int day, {
  double energy = 2000,
  double? carbohydrate = 200,
}) {
  final localDate = NutritionDayDate(year: 2026, month: 6, day: day);
  return NutritionDayRecord(
    localDate: localDate,
    meals: [
      NutritionDayMealRecord(
        meal: MealRecord(
          id: 'meal-$day',
          mealType: 'Breakfast',
          startedAt: DateTime.utc(2026, 6, day, 8),
          timezone: 'UTC',
          localDate: localDate,
          updatedAt: DateTime.utc(2026, 6, day, 8),
        ),
        entries: [
          FoodEntryRecord(
            id: 'entry-$day',
            mealId: 'meal-$day',
            kind: FoodEntryKind.quickEntry,
            position: 0,
            name: 'Logged food',
            nutrients: NutrientVector.energyAndMacros(
              energy: NutrientAmount.complete(
                value: energy,
                entered: energy.toStringAsFixed(0),
                unit: NutrientUnit.kilocalorie,
              ),
              protein: NutrientAmount.complete(
                value: 100,
                entered: '100',
                unit: NutrientUnit.gram,
              ),
              carbohydrate: carbohydrate == null
                  ? NutrientAmount.unknown(NutrientUnit.gram)
                  : NutrientAmount.complete(
                      value: carbohydrate,
                      entered: carbohydrate.toStringAsFixed(0),
                      unit: NutrientUnit.gram,
                    ),
              fat: NutrientAmount.complete(
                value: 60,
                entered: '60',
                unit: NutrientUnit.gram,
              ),
            ),
            updatedAt: DateTime.utc(2026, 6, day, 8),
          ),
        ],
      ),
    ],
  );
}

MetricReadingPoint _reading(int day, double value) {
  return MetricReadingPoint(
    at: DateTime.utc(2026, 6, day, 9),
    value: value,
  );
}

MetricReadingPoint _readingWithoutScalar(int day) {
  return MetricReadingPoint(
    at: DateTime.utc(2026, 6, day, 9),
    value: null,
  );
}
