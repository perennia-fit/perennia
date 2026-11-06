import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/profile/user_profile.dart';
import 'package:perennia/features/onboarding/repositories/onboarding_gate.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('gate', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    ProviderContainer containerFor({
      required bool onboardingDone,
      TrainingRepositories Function()? trainingRepositories,
    }) {
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWith(
            (ref) => InMemorySettingsRepository(
              AppSettings(onboardingDone: onboardingDone),
            ),
          ),
          trainingRepositoriesProvider.overrideWith(
            (ref) => trainingRepositories?.call() ?? repositories,
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('is true when onboardingDone is false and no row exists', () async {
      final container = containerFor(onboardingDone: false);

      expect(await container.read(onboardingGateProvider.future), isTrue);
    });

    test('is false when a live section row exists', () async {
      await repositories.userProfile.saveSection(
        UserProfileSection.aboutYou,
        <String, Object?>{'birth_year': 1990},
      );
      final container = containerFor(onboardingDone: false);

      expect(await container.read(onboardingGateProvider.future), isFalse);
    });

    test('is true when the only section row is tombstoned', () async {
      await database.into(database.userProfileSections).insert(
            UserProfileSectionRow(
              id: 'tombstoned-section',
              section: UserProfileSection.aboutYou.wireName,
              valuesJson: '{}',
              syncPreviouslySynced: false,
              updatedAt: DateTime.utc(2026),
              deletedAt: DateTime.utc(2026),
            ),
          );
      final container = containerFor(onboardingDone: false);

      expect(await container.read(onboardingGateProvider.future), isTrue);
    });

    test('is false when onboardingDone is true, without reading the database',
        () async {
      final container = containerFor(
        onboardingDone: true,
        trainingRepositories: () {
          throw StateError('the gate must not reach the repositories');
        },
      );

      expect(await container.read(onboardingGateProvider.future), isFalse);
    });

    test('a throwing hasAnySection fails .future promptly', () async {
      final userProfile = _ThrowingUserProfile();
      final container = containerFor(
        onboardingDone: false,
        trainingRepositories: () => _FakeRepositories(userProfile),
      );

      // Well under Riverpod's default retry backoff, so a provider that retries
      // fails here with a TimeoutException. The fake throws an Exception, since
      // the default retry passes over an Error.
      await expectLater(
        container
            .read(onboardingGateProvider.future)
            .timeout(const Duration(seconds: 5)),
        throwsA(isA<_ProfileStoreUnavailable>()),
      );
      expect(userProfile.calls, 1);
    });
  });
}

class _FakeRepositories extends Fake implements TrainingRepositories {
  _FakeRepositories(this.userProfile);

  @override
  final UserProfileRepository userProfile;
}

class _ThrowingUserProfile extends Fake implements UserProfileRepository {
  int calls = 0;

  @override
  Future<bool> hasAnySection() async {
    calls += 1;
    throw const _ProfileStoreUnavailable();
  }
}

class _ProfileStoreUnavailable implements Exception {
  const _ProfileStoreUnavailable();
}
