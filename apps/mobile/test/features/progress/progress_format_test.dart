import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/analytics/progress_measure.dart';
import 'package:perennia/features/progress/widgets/progress_format.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/l10n/l10n.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  String metric(ProgressMeasureKind measure, double value) =>
      formatProgressValue(measure, value, UnitSystem.metric, l10n);
  String imperial(ProgressMeasureKind measure, double value) =>
      formatProgressValue(measure, value, UnitSystem.imperial, l10n);
  String difference(
    ProgressMeasureKind measure,
    double value, [
    UnitSystem unitSystem = UnitSystem.metric,
  ]) =>
      formatProgressValue(
        measure,
        value,
        unitSystem,
        l10n,
        isDifference: true,
      );

  group('values (D8)', () {
    test('loads: kilograms or pounds, one decimal, no trailing .0', () {
      for (final measure in <ProgressMeasureKind>[
        ProgressMeasureKind.estimatedOneRepMax,
        ProgressMeasureKind.maxLoad,
      ]) {
        expect(metric(measure, 102.5), '102.5 kg');
        expect(metric(measure, 100), '100 kg');
        expect(metric(measure, 102.04), '102 kg');
        expect(imperial(measure, 100), '220.5 lb');
        // 225 lb as the engine normalizes it to kilograms.
        expect(imperial(measure, 225 * 0.45359237), '225 lb');
      }
    });

    test('reps: a whole number in both systems', () {
      expect(metric(ProgressMeasureKind.maxReps, 12), '12 reps');
      expect(metric(ProgressMeasureKind.maxReps, 1), '1 rep');
      expect(imperial(ProgressMeasureKind.maxReps, 12), '12 reps');
    });

    test('durations: m:ss under an hour, h:mm:ss from one, in both systems',
        () {
      for (final measure in <ProgressMeasureKind>[
        ProgressMeasureKind.maxDuration,
        ProgressMeasureKind.minDuration,
      ]) {
        expect(metric(measure, 304), '5:04');
        expect(metric(measure, 59.5), '1:00');
        expect(metric(measure, 3725), '1:02:05');
        expect(imperial(measure, 304), '5:04');
      }
    });

    test('distances: kilometres or miles, two decimals', () {
      expect(metric(ProgressMeasureKind.maxDistance, 5), '5.00 km');
      expect(metric(ProgressMeasureKind.maxDistance, 21.1), '21.10 km');
      expect(imperial(ProgressMeasureKind.maxDistance, 5), '3.11 mi');
    });

    test('paces: m:ss per kilometre or per mile', () {
      expect(metric(ProgressMeasureKind.fastestPace, 304), '5:04 /km');
      expect(metric(ProgressMeasureKind.fastestPace, 321.5), '5:22 /km');
      // 304 s/km is 489.24 s/mi.
      expect(imperial(ProgressMeasureKind.fastestPace, 304), '8:09 /mi');
    });
  });

  group('differences (D8)', () {
    test('a pace or duration gap under a minute reads in seconds', () {
      expect(difference(ProgressMeasureKind.fastestPace, 18), '18 s');
      expect(difference(ProgressMeasureKind.minDuration, 18), '18 s');
      expect(difference(ProgressMeasureKind.maxDuration, 59.4), '59 s');
      // 18 s/km is 28.97 s/mi.
      expect(
        difference(ProgressMeasureKind.fastestPace, 18, UnitSystem.imperial),
        '29 s',
      );
    });

    test('a pace or duration gap of a minute or more reads m:ss', () {
      expect(difference(ProgressMeasureKind.fastestPace, 65), '1:05');
      expect(difference(ProgressMeasureKind.minDuration, 60), '1:00');
      expect(difference(ProgressMeasureKind.maxDuration, 59.5), '1:00');
    });

    test('display steps are the values as shown, in whole steps', () {
      int steps(ProgressMeasureKind measure, double value,
              [UnitSystem unitSystem = UnitSystem.metric]) =>
          progressDisplaySteps(measure, value, unitSystem);

      expect(steps(ProgressMeasureKind.maxLoad, 100.018), 1000);
      expect(
          steps(ProgressMeasureKind.maxLoad, 100, UnitSystem.imperial), 2205);
      expect(steps(ProgressMeasureKind.maxReps, 12), 12);
      expect(steps(ProgressMeasureKind.minDuration, 59.5), 60);
      expect(steps(ProgressMeasureKind.maxDistance, 21.1), 2110);
      expect(steps(ProgressMeasureKind.fastestPace, 304.4), 304);
      expect(
        steps(ProgressMeasureKind.fastestPace, 304, UnitSystem.imperial),
        489,
      );
    });

    test('other measures read as their values do', () {
      expect(difference(ProgressMeasureKind.maxLoad, 2.5), '2.5 kg');
      expect(difference(ProgressMeasureKind.maxReps, 3), '3 reps');
      expect(difference(ProgressMeasureKind.maxDistance, 0.5), '0.50 km');
    });
  });
}
