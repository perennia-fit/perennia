import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';

void main() {
  group('AppSettings', () {
    test('restTimerSoundsEnabled defaults on', () {
      expect(AppSettings.defaults.restTimerSoundsEnabled, isTrue);
    });

    test('round-trips restTimerSoundsEnabled through JSON', () {
      const settings = AppSettings(restTimerSoundsEnabled: false);
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.restTimerSoundsEnabled, isFalse);
      expect(restored, settings);
    });

    test('defaults restTimerSoundsEnabled to true for legacy JSON', () {
      // Older settings files predate the field; treat a missing key as on.
      final restored = AppSettings.fromJson(const <String, Object?>{
        'themePreference': 'system',
      });
      expect(restored.restTimerSoundsEnabled, isTrue);
    });

    test('copyWith toggles restTimerSoundsEnabled and updates equality', () {
      const on = AppSettings();
      final off = on.copyWith(restTimerSoundsEnabled: false);
      expect(off.restTimerSoundsEnabled, isFalse);
      expect(off == on, isFalse);
      expect(off.hashCode == on.hashCode, isFalse);
      expect(off.copyWith(restTimerSoundsEnabled: true), on);
    });

    // weekStartFor steps back by calendar days, not by 24-hour spans from a
    // local midnight, which land on the day before after a spring-forward.
    // Every date of years with daylight-saving changes in the common zones
    // (São Paulo changed at midnight in 2018) is checked, so a run in any
    // such zone exercises a change.
    test('weekStartFor is the week start on or before every date', () {
      final failures = <String>[];
      for (final weekStartDay in WeekStartDay.values) {
        final settings = AppSettings(weekStartDay: weekStartDay);
        for (final year in const <int>[2018, 2019, 2026]) {
          // Each date built on its own, so the walk cannot repeat a date.
          for (var index = 0; index < 365; index += 1) {
            final utc = DateTime.utc(year, 1, 1 + index);
            final date = TrainingDayDate(
              year: utc.year,
              month: utc.month,
              day: utc.day,
            );
            final start = settings.weekStartFor(date);
            final startUtc = DateTime.utc(start.year, start.month, start.day);
            final gap = utc.difference(startUtc).inDays;
            if (startUtc.weekday != weekStartDay.dateTimeWeekday ||
                gap < 0 ||
                gap > 6) {
              failures.add('${weekStartDay.name} ${date.storageValue}: '
                  '${start.storageValue}');
            }
          }
        }
      }
      expect(failures, isEmpty);
    });
  });
}
