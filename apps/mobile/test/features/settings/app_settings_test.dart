import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
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

  group('onboardingDone', () {
    test('AppSettings.defaults has it true', () {
      expect(AppSettings.defaults.onboardingDone, isTrue);
    });

    test('round-trips through JSON', () {
      for (final value in const <bool>[true, false]) {
        final settings = AppSettings(onboardingDone: value);
        final restored = AppSettings.fromJson(settings.toJson());
        expect(restored.onboardingDone, value);
        expect(restored, settings);
      }
    });

    test('copyWith changes equality and hashCode', () {
      const done = AppSettings();
      final notDone = done.copyWith(onboardingDone: false);
      expect(notDone.onboardingDone, isFalse);
      expect(notDone == done, isFalse);
      expect(notDone.hashCode == done.hashCode, isFalse);
      expect(notDone.copyWith(onboardingDone: true), done);
    });

    test('is not part of the synced account half', () {
      const notDone = AppSettings(onboardingDone: false);
      expect(
          notDone.toAccountSettings(), const AppSettings().toAccountSettings());
      expect(
        notDone.mergeAccountSettings(const AppSettings().toAccountSettings()),
        notDone,
      );
    });

    group('FileSettingsRepository', () {
      late Directory directory;
      late File file;
      late FileSettingsRepository repository;

      setUp(() async {
        directory = await Directory.systemTemp.createTemp('settings_test_');
        file = File('${directory.path}${Platform.pathSeparator}settings.json');
        repository = FileSettingsRepository(settingsFile: () async => file);
      });

      tearDown(() async {
        await directory.delete(recursive: true);
      });

      test('a missing file loads false', () async {
        expect((await repository.load()).onboardingDone, isFalse);
      });

      test('a file without the key loads false', () async {
        await file.writeAsString(
          jsonEncode(<String, Object?>{'themePreference': 'dark'}),
        );

        final loaded = await repository.load();

        expect(loaded.onboardingDone, isFalse);
        expect(loaded.themePreference, AppThemePreference.dark);
      });

      test('a file with true loads true', () async {
        await file.writeAsString(
          jsonEncode(<String, Object?>{'onboardingDone': true}),
        );

        expect((await repository.load()).onboardingDone, isTrue);
      });

      test('a corrupt file loads true', () async {
        await file.writeAsString('{not json');

        expect((await repository.load()).onboardingDone, isTrue);
      });

      test('a file holding something other than a map loads true', () async {
        await file.writeAsString('[]');

        expect((await repository.load()).onboardingDone, isTrue);
      });

      test('an unreadable location loads true', () async {
        final failing = FileSettingsRepository(
          settingsFile: () async => throw const FileSystemException('no path'),
        );

        expect((await failing.load()).onboardingDone, isTrue);
      });

      test('a saved value survives a reload', () async {
        await repository.save(const AppSettings(onboardingDone: false));
        expect((await repository.load()).onboardingDone, isFalse);

        await repository.save(const AppSettings());
        expect((await repository.load()).onboardingDone, isTrue);
      });
    });

    group('SplitSettingsRepository', () {
      late AppDatabase database;
      late TrainingRepositories repositories;
      late InMemorySettingsRepository deviceStore;
      late SplitSettingsRepository settings;

      setUpAll(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      });

      setUp(() {
        database = AppDatabase.inMemory();
        repositories = TrainingRepositories(database);
        deviceStore = InMemorySettingsRepository(
          const AppSettings(onboardingDone: false),
        );
        settings = SplitSettingsRepository(
          deviceStore: deviceStore,
          accountSettings: repositories.accountSettings,
        );
      });

      tearDown(() async {
        await database.close();
      });

      test('keeps the value across save and load', () async {
        // The first load seeds the account row; later loads merge it, and the
        // merge must not reset the device half.
        expect((await settings.load()).onboardingDone, isFalse);
        expect((await settings.load()).onboardingDone, isFalse);

        final current = await settings.load();
        await settings.save(current.copyWith(onboardingDone: true));

        expect((await settings.load()).onboardingDone, isTrue);
        expect((await deviceStore.load()).onboardingDone, isTrue);
      });

      test('setOnboardingDone on an existing row appends no Activity Log entry',
          () async {
        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWith((ref) => settings),
          ],
        );
        addTearDown(container.dispose);

        final loaded = await container.read(settingsControllerProvider.future);
        expect(loaded.onboardingDone, isFalse);
        final entriesBefore = await database.select(database.activityLog).get();
        final rowBefore =
            (await database.select(database.userSettings).get()).single;
        expect(entriesBefore, isNotEmpty);

        await container
            .read(settingsControllerProvider.notifier)
            .setOnboardingDone();

        expect(
          container.read(settingsControllerProvider).value?.onboardingDone,
          isTrue,
        );
        expect((await settings.load()).onboardingDone, isTrue);
        expect(
          await database.select(database.activityLog).get(),
          hasLength(entriesBefore.length),
        );
        expect(
          (await database.select(database.userSettings).get()).single.updatedAt,
          rowBefore.updatedAt,
        );
      });
    });
  });
}
