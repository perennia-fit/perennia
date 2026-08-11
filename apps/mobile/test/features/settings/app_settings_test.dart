import 'package:flutter_test/flutter_test.dart';
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
  });
}
