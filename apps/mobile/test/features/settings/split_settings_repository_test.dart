import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('SplitSettingsRepository', () {
    late AppDatabase database;
    late TrainingRepositories repositories;
    late SplitSettingsRepository settings;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
      settings = SplitSettingsRepository(
        deviceStore: InMemorySettingsRepository(),
        accountSettings: repositories.accountSettings,
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('first load migrates the JSON account half into the synced row',
        () async {
      // Seed a device store that already carries an account-level choice
      // (imperial) as an existing user's settings.json would.
      const existing = AppSettings(unitSystem: UnitSystem.imperial);
      final deviceStore = InMemorySettingsRepository(existing);
      final migrating = SplitSettingsRepository(
        deviceStore: deviceStore,
        accountSettings: repositories.accountSettings,
      );

      final loaded = await migrating.load();
      expect(loaded.unitSystem, UnitSystem.imperial);

      // The synced row now exists with the migrated value (idempotent — a second
      // load reads the row, not the JSON, and must not create a duplicate).
      final rowsAfterFirst =
          await database.select(database.userSettings).get();
      expect(rowsAfterFirst, hasLength(1));
      expect(rowsAfterFirst.single.unitSystem, 'imperial');

      await migrating.load();
      final rowsAfterSecond =
          await database.select(database.userSettings).get();
      expect(rowsAfterSecond, hasLength(1));
    });

    test('save splits account fields to the row and device fields to the JSON',
        () async {
      // Initialize (migrates defaults into the row).
      await settings.load();

      const next = AppSettings(
        unitSystem: UnitSystem.imperial,
        weekStartDay: WeekStartDay.sunday,
        keepScreenOn: true,
        crashReportingEnabled: true,
      );
      await settings.save(next);

      // Account half landed on the synced Drift row.
      final row =
          (await database.select(database.userSettings).get()).single;
      expect(row.unitSystem, 'imperial');
      expect(row.weekStartDay, 'sunday');

      // A fresh merged load reflects BOTH halves.
      final reloaded = await settings.load();
      expect(reloaded.unitSystem, UnitSystem.imperial);
      expect(reloaded.weekStartDay, WeekStartDay.sunday);
      expect(reloaded.keepScreenOn, isTrue);
      expect(reloaded.crashReportingEnabled, isTrue);
    });

    test('the synced row is the source of truth for account fields on load',
        () async {
      await settings.load(); // create the row at defaults

      // A pulled/agent write changes the account row directly (bypassing JSON).
      await repositories.accountSettings.applySyncImage(
        image: const <String, Object?>{
          'id': 'user-settings:remote',
          'theme_preference': 'dark',
          'unit_system': 'imperial',
          'week_start_day': 'monday',
          'default_weight_increment': 2.5,
          'home_screen_display': 'comfortable',
          'pr_tracking_enabled': true,
          'mark_sets_complete_by_default': false,
          'auto_select_next_set': true,
          'updated_at': '2999-01-01T00:00:00.000Z',
          'deleted_at': null,
        },
        deviceId: 'agent:key-1',
        batchId: 'batch-1',
      );

      final merged = await settings.load();
      expect(merged.themePreference, AppThemePreference.dark);
      expect(merged.unitSystem, UnitSystem.imperial);
    });
  });
}
