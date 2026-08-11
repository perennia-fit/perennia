import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';

/// Regression guard for blocking finding #1: an account-level Settings
/// sync pull (or agent write) that lands in the Drift `user_settings` singleton
/// must rebuild the merged `AppSettings` the UI reads. The controller is a
/// one-shot `load()`; reactivity comes from the sync layer invalidating
/// `settingsControllerProvider` after a pull applied a `user_settings` change
/// (see sync_repository / settings_providers / sync_nudge_handler). This test
/// exercises the controller half of that contract: once the account row exists,
/// invalidating the provider re-merges it — the merged value is NOT stuck stale.
void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('settingsControllerProvider reactivity to an applied account pull', () {
    late AppDatabase database;
    late TrainingRepositories repositories;
    late ProviderContainer container;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
      container = ProviderContainer(
        overrides: [
          trainingRepositoriesProvider.overrideWith((ref) => repositories),
          settingsRepositoryProvider.overrideWith(
            (ref) => SplitSettingsRepository(
              deviceStore: InMemorySettingsRepository(),
              accountSettings: repositories.accountSettings,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
    });

    tearDown(() async {
      await database.close();
    });

    Future<AppSettings> readWhenReady() async {
      for (var attempt = 0; attempt < 200; attempt += 1) {
        final data = container.read(settingsControllerProvider).asData?.value;
        if (data != null) {
          return data;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      fail('settingsControllerProvider never produced data');
    }

    test(
        'invalidating after an applied account pull re-merges the new '
        'account row into the merged AppSettings', () async {
      final subscription =
          container.listen(settingsControllerProvider, (_, __) {});
      addTearDown(subscription.close);

      final initial = await readWhenReady();
      expect(initial.themePreference, AppThemePreference.system);
      expect(initial.unitSystem, UnitSystem.metric);

      // A pulled/agent write lands directly on the account Drift row — the same
      // path `SyncRepository._applyPulledUserSettingsChange` drives.
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

      // The sync layer invalidates the controller after a user_settings pull;
      // simulate that seam here and assert the merged value is not stuck stale.
      container.invalidate(settingsControllerProvider);

      AppSettings? updated;
      for (var attempt = 0; attempt < 200; attempt += 1) {
        final data = container.read(settingsControllerProvider).asData?.value;
        if (data != null && data.themePreference == AppThemePreference.dark) {
          updated = data;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(
        updated,
        isNotNull,
        reason: 'settingsControllerProvider did not reflect the applied pull '
            'after invalidation',
      );
      expect(updated!.themePreference, AppThemePreference.dark);
      expect(updated.unitSystem, UnitSystem.imperial);
    });
  });
}
