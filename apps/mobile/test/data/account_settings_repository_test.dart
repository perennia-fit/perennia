import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/settings/account_settings.dart';
import 'package:perennia/domain/settings/settings_validation.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('AccountSettingsRepository', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('load returns null when the account settings row is absent', () async {
      expect(await repositories.accountSettings.load(), isNull);
    });

    test('save hard-rejects invalid settings and writes nothing', () async {
      const unknownTheme = AccountSettings(
        themePreference: 'midnight',
        unitSystem: 'metric',
        weekStartDay: 'monday',
        defaultWeightIncrement: 2.5,
        homeScreenDisplay: 'comfortable',
        prTrackingEnabled: true,
        markSetsCompleteByDefault: false,
        autoSelectNextSet: true,
      );
      final oversizedIncrement =
          AccountSettings.defaults.copyWith(defaultWeightIncrement: 150);

      await expectLater(
        repositories.accountSettings.save(unknownTheme),
        throwsA(
          isA<SettingsValidationException>().having(
            (error) => error.errors.map((issue) => issue.rule),
            'rules',
            <String>['setting_enum_membership'],
          ),
        ),
      );
      await expectLater(
        repositories.accountSettings.save(oversizedIncrement),
        throwsA(
          isA<SettingsValidationException>().having(
            (error) => error.errors.map((issue) => issue.rule),
            'rules',
            <String>['setting_weight_increment_max'],
          ),
        ),
      );

      expect(await database.select(database.userSettings).get(), isEmpty);
      expect(await database.select(database.activityLog).get(), isEmpty);
    });

    test('save creates the singleton row and records one Activity Log entry',
        () async {
      const settings = AccountSettings(
        themePreference: 'dark',
        unitSystem: 'imperial',
        weekStartDay: 'sunday',
        defaultWeightIncrement: 5,
        homeScreenDisplay: 'compact',
        prTrackingEnabled: false,
        markSetsCompleteByDefault: true,
        autoSelectNextSet: false,
      );

      await repositories.accountSettings.save(settings);

      final loaded = await repositories.accountSettings.load();
      expect(loaded, settings);

      final rows = await database.select(database.userSettings).get();
      expect(rows, hasLength(1));

      final logRows = await (database.select(database.activityLog)
            ..where(
              (row) =>
                  row.entityTable.equals(AppDatabase.userSettingsTable),
            ))
          .get();
      expect(logRows, hasLength(1));
      expect(logRows.single.beforeImage, isNull);
      expect(logRows.single.afterImage, isNotNull);
    });

    test('save updates the same singleton row in place (LWW), not a new row',
        () async {
      await repositories.accountSettings.save(AccountSettings.defaults);
      await repositories.accountSettings.save(
        AccountSettings.defaults.copyWith(unitSystem: 'imperial'),
      );

      final rows = await database.select(database.userSettings).get();
      expect(rows, hasLength(1));
      expect(rows.single.unitSystem, 'imperial');

      final loaded = await repositories.accountSettings.load();
      expect(loaded!.unitSystem, 'imperial');
    });

    test('an unchanged save appends no new Activity Log entry', () async {
      await repositories.accountSettings.save(AccountSettings.defaults);
      await repositories.accountSettings.save(AccountSettings.defaults);

      final logRows = await (database.select(database.activityLog)
            ..where(
              (row) =>
                  row.entityTable.equals(AppDatabase.userSettingsTable),
            ))
          .get();
      expect(logRows, hasLength(1));
    });

    test(
        'an unchanged save writes nothing even when the clock has moved on '
        'since the last write', () async {
      await repositories.accountSettings.save(AccountSettings.defaults);
      // Backdate the row so the next save always lands in a later second
      // than the stored `updated_at`, instead of only under load.
      final lastWrite = DateTime.utc(2026, 1, 1, 12);
      await database
          .update(database.userSettings)
          .write(UserSettingsCompanion(updatedAt: Value<DateTime>(lastWrite)));

      await repositories.accountSettings.save(AccountSettings.defaults);

      final row = await database.select(database.userSettings).getSingle();
      expect(row.updatedAt.toUtc(), lastWrite);
      final logRows = await (database.select(database.activityLog)
            ..where(
              (row) =>
                  row.entityTable.equals(AppDatabase.userSettingsTable),
            ))
          .get();
      expect(logRows, hasLength(1));
    });

    test(
        'applySyncImage upserts a pulled row and reflects it in load '
        '(agent/other-device write path)', () async {
      const image = <String, Object?>{
        'id': 'user-settings:remote',
        'theme_preference': 'light',
        'unit_system': 'imperial',
        'week_start_day': 'sunday',
        'default_weight_increment': 5.0,
        'home_screen_display': 'compact',
        'pr_tracking_enabled': false,
        'mark_sets_complete_by_default': true,
        'auto_select_next_set': false,
        'updated_at': '2026-07-04T09:00:00.000Z',
        'deleted_at': null,
      };

      await repositories.accountSettings.applySyncImage(
        image: image,
        deviceId: 'agent:key-1',
        batchId: 'batch-1',
      );

      final loaded = await repositories.accountSettings.load();
      expect(loaded!.unitSystem, 'imperial');
      expect(loaded.themePreference, 'light');
      expect(loaded.defaultWeightIncrement, 5.0);
    });
  });
}
