import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/profile/user_profile.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';
import 'package:perennia/features/onboarding/controllers/onboarding_controller.dart';
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

  group('flow', () {
    late AppDatabase database;
    late TrainingRepositories repositories;
    late InMemorySettingsRepository settingsRepository;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
      settingsRepository = InMemorySettingsRepository(
        AppSettings.defaults.copyWith(onboardingDone: false),
      );
    });

    tearDown(() async {
      await database.close();
    });

    /// A container with the flow kept alive, as the open screen keeps it.
    ProviderContainer openFlow({AuthRepository? authRepository}) {
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWith((ref) => settingsRepository),
          trainingRepositoriesProvider.overrideWith((ref) => repositories),
          authRepositoryProvider.overrideWith(
            (ref) => authRepository ?? InMemoryAuthRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(onboardingControllerProvider, (_, __) {});
      return container;
    }

    OnboardingController flow(ProviderContainer container) {
      return container.read(onboardingControllerProvider.notifier);
    }

    OnboardingStep step(ProviderContainer container) {
      return container.read(onboardingControllerProvider).step;
    }

    Future<List<UserProfileSectionRow>> rows() {
      return database.select(database.userProfileSections).get();
    }

    Future<List<ActivityLogEntry>> profileEntries() async {
      final entries = await repositories.activityLog.listEntries();
      return entries
          .where(
            (entry) =>
                entry.entityTable == AppDatabase.userProfileSectionsTable,
          )
          .toList();
    }

    Future<UserProfile> profile() => repositories.userProfile.watch().first;

    const aboutYou = <String, Object?>{
      'sex': 'female',
      'birth_year': 1990,
      'height': <String, Object?>{'value': 66, 'unit': 'in'},
    };
    const goalsAndLevels = <UserProfileSection, Map<String, Object?>>{
      UserProfileSection.trainingGoals: <String, Object?>{
        'goals': <String>['strength'],
      },
      UserProfileSection.experience: <String, Object?>{
        'levels': <Map<String, Object?>>[
          <String, Object?>{'focus_id': 'strength', 'level': 'beginner'},
        ],
      },
    };

    Future<void> leaveScreen1(ProviderContainer container) {
      return flow(container).next(
        changes: const <UserProfileSection, Map<String, Object?>>{},
      );
    }

    test('screen 1 saves units and About you, and only those (CUJ 2)',
        () async {
      final container = openFlow();

      await flow(container).next(
        changes: const {UserProfileSection.aboutYou: aboutYou},
        unitSystem: UnitSystem.imperial,
        weekStartDay: WeekStartDay.monday,
      );

      final settings = await settingsRepository.load();
      expect(settings.unitSystem, UnitSystem.imperial);
      expect(settings.onboardingDone, isTrue);
      final stored = await profile();
      expect(stored.sex, ProfileSex.female);
      expect(stored.birthYear, 1990);
      expect(
          stored.height, const ProfileHeight(value: 66, unit: HeightUnit.inch));
      expect(
        jsonDecode((await rows()).single.valuesJson)['height'],
        <String, Object?>{'value': 66, 'unit': 'in'},
      );
      expect(stored.trainingGoals, isNull);
      expect(stored.experience, isNull);
      expect(stored.trainingSetup, isNull);
      expect(step(container), OnboardingStep.screen2);

      await flow(container).skipThis();
      await flow(container).skipThis();

      expect(step(container), OnboardingStep.done);
      expect((await profileEntries()), hasLength(1));
    });

    test('screen 1 saves the setting, then About you, then onboardingDone',
        () async {
      final seen = <String>[];
      settingsRepository = _ObservingSettingsRepository(
        AppSettings.defaults.copyWith(onboardingDone: false),
        onSave: (settings) async {
          final hasSection = await repositories.userProfile.hasAnySection();
          seen.add(
            '${settings.unitSystem.name} '
            'section:$hasSection done:${settings.onboardingDone}',
          );
        },
      );
      final container = openFlow();

      await flow(container).next(
        changes: const {UserProfileSection.aboutYou: aboutYou},
        unitSystem: UnitSystem.imperial,
      );

      expect(seen, <String>[
        'imperial section:false done:false',
        'imperial section:true done:true',
      ]);
    });

    test(
        'next with nothing entered writes nothing, and screen 1 still finishes',
        () async {
      final container = openFlow();

      await flow(container).next(
        changes: const {
          UserProfileSection.aboutYou: <String, Object?>{},
        },
      );

      expect(await rows(), isEmpty);
      expect(await repositories.activityLog.listEntries(), isEmpty);
      expect((await settingsRepository.load()).onboardingDone, isTrue);
      expect(step(container), OnboardingStep.screen2);

      await flow(container).next(
        changes: const {
          UserProfileSection.trainingGoals: <String, Object?>{},
          UserProfileSection.experience: <String, Object?>{},
        },
      );

      expect(await rows(), isEmpty);
      expect(await repositories.activityLog.listEntries(), isEmpty);
      expect(step(container), OnboardingStep.screen3);
    });

    test('next with every field cleared on no row writes nothing', () async {
      final container = openFlow();

      await flow(container).next(
        changes: const {
          UserProfileSection.aboutYou: <String, Object?>{
            'sex': null,
            'birth_year': null,
          },
        },
      );

      expect(await rows(), isEmpty);
      expect(await repositories.activityLog.listEntries(), isEmpty);
    });

    test('screen 2 writes its two sections as one Batch', () async {
      final container = openFlow();
      await leaveScreen1(container);

      await flow(container).next(changes: goalsAndLevels);

      final entries = await profileEntries();
      expect(entries, hasLength(2));
      expect(entries.map((entry) => entry.batchId).toSet(), hasLength(1));
      final stored = await profile();
      expect(stored.goals, <TrainingGoalId>[TrainingGoalId.strength]);
      expect(stored.experienceLevels, const <ExperienceEntry>[
        ExperienceEntry(focusId: 'strength', level: ExperienceLevel.beginner),
      ]);
      expect(step(container), OnboardingStep.screen3);
    });

    test('screen 3 saves Training setup and reaches done', () async {
      final container = openFlow();
      await leaveScreen1(container);
      await flow(container).skipThis();

      await flow(container).next(
        changes: const {
          UserProfileSection.trainingSetup: <String, Object?>{
            'days_per_week': 3,
          },
        },
      );

      expect((await profile()).daysPerWeek, 3);
      expect(await profileEntries(), hasLength(1));
      expect(step(container), OnboardingStep.done);
    });

    test('check reports a hard error in one section and writes nothing',
        () async {
      final container = openFlow();
      await leaveScreen1(container);

      final checks = await flow(container).check(const {
        UserProfileSection.trainingGoals: <String, Object?>{
          'goals': <String>['strength'],
        },
        UserProfileSection.experience: <String, Object?>{
          'levels': <Map<String, Object?>>[
            <String, Object?>{'focus_id': 'strength', 'level': 'expert'},
          ],
        },
      });

      expect(checks, hasLength(2));
      expect(checks.first.errors, isEmpty);
      expect(
        checks.last.errors.map((issue) => issue.rule),
        contains('levels.unknown_level'),
      );
      expect(await rows(), isEmpty);
      expect(await repositories.activityLog.listEntries(), isEmpty);
      expect(step(container), OnboardingStep.screen2);
    });

    test('check reports a soft warning and writes nothing', () async {
      final container = openFlow();

      final checks = await flow(container).check({
        UserProfileSection.aboutYou: <String, Object?>{
          'birth_year': DateTime.now().year - 5,
        },
      });

      expect(checks.single.errors, isEmpty);
      expect(
        checks.single.warnings.map((issue) => issue.rule),
        contains('birth_year.improbable_age'),
      );
      expect(await rows(), isEmpty);
    });

    test('check merges over the stored values', () async {
      final container = openFlow();
      await flow(container).next(
        changes: const {
          UserProfileSection.aboutYou: <String, Object?>{'birth_year': 1990},
        },
      );

      final checks = await flow(container).check(const {
        UserProfileSection.aboutYou: <String, Object?>{'sex': 'female'},
      });

      expect(checks.single.values['birth_year'], 1990);
      expect(checks.single.values['sex'], 'female');
    });

    test('check has nothing to say about a save that changes nothing',
        () async {
      final container = openFlow();
      final improbable = <String, Object?>{
        'birth_year': DateTime.now().year - 5,
      };
      await flow(container).next(
        changes: {UserProfileSection.aboutYou: improbable},
      );

      expect(
        await flow(container).check({UserProfileSection.aboutYou: improbable}),
        isEmpty,
      );
      expect(
        await flow(container).check(const {
          UserProfileSection.trainingGoals: <String, Object?>{},
        }),
        isEmpty,
      );
    });

    test('back then an unchanged re-entry writes nothing', () async {
      final container = openFlow();
      await flow(container).next(
        changes: const {UserProfileSection.aboutYou: aboutYou},
      );
      // Whole-second stamps would hide a rewrite inside the same second.
      final stamp = DateTime.utc(2026);
      await database.update(database.userProfileSections).write(
            UserProfileSectionsCompanion(updatedAt: Value<DateTime>(stamp)),
          );

      await flow(container).back();

      final state = container.read(onboardingControllerProvider);
      expect(state.step, OnboardingStep.screen1);
      expect(state.profile.birthYear, 1990);

      await flow(container).next(
        changes: const {UserProfileSection.aboutYou: aboutYou},
      );

      expect(await profileEntries(), hasLength(1));
      expect((await rows()).single.updatedAt.toUtc(), stamp);
      expect(step(container), OnboardingStep.screen2);
    });

    test('back then a real change writes a new Batch', () async {
      final container = openFlow();
      await flow(container).next(
        changes: const {UserProfileSection.aboutYou: aboutYou},
      );

      await flow(container).back();
      await flow(container).next(
        changes: const {
          UserProfileSection.aboutYou: <String, Object?>{'birth_year': 1991},
        },
      );

      final entries = await profileEntries();
      expect(entries, hasLength(2));
      expect(entries.map((entry) => entry.batchId).toSet(), hasLength(2));
      final stored = await profile();
      expect(stored.birthYear, 1991);
      expect(stored.sex, ProfileSex.female);
    });

    test('back moves one screen at a time and does nothing on screen 1',
        () async {
      final container = openFlow();

      await flow(container).back();
      expect(step(container), OnboardingStep.screen1);

      await flow(container).skipThis();
      await flow(container).skipThis();
      expect(step(container), OnboardingStep.screen3);

      await flow(container).back();
      expect(step(container), OnboardingStep.screen2);
      await flow(container).back();
      expect(step(container), OnboardingStep.screen1);
    });

    test('a second tap on Next while the first runs writes once', () async {
      final container = openFlow();
      await leaveScreen1(container);

      await Future.wait<void>(<Future<void>>[
        flow(container).next(changes: goalsAndLevels),
        flow(container).next(changes: goalsAndLevels),
      ]);

      expect(await profileEntries(), hasLength(2));
      expect(step(container), OnboardingStep.screen3);
    });

    test('skipThis on screen 1 saves nothing and sets onboardingDone',
        () async {
      final container = openFlow();

      await flow(container).skipThis();

      final settings = await settingsRepository.load();
      expect(settings.onboardingDone, isTrue);
      expect(settings.unitSystem, UnitSystem.metric);
      expect(await rows(), isEmpty);
      expect(await repositories.activityLog.listEntries(), isEmpty);
      expect(step(container), OnboardingStep.screen2);
    });

    test('skipAll reaches done from screen 1', () async {
      final container = openFlow();

      await flow(container).skipAll();

      expect(step(container), OnboardingStep.done);
      expect((await settingsRepository.load()).onboardingDone, isTrue);
      expect(await rows(), isEmpty);
    });

    test('a slow read at start-up does not put the user back on screen 1',
        () async {
      final userProfile = _SlowFirstReadUserProfile();
      repositories = _FakeRepositories(userProfile);
      final container = openFlow();

      await flow(container).skipAll();
      expect(step(container), OnboardingStep.done);

      userProfile.firstRead.complete(const UserProfile());
      await pumpEventQueue();

      expect(step(container), OnboardingStep.done);
    });

    test('skipAll reaches done from screens 2 and 3', () async {
      for (final skips in <int>[1, 2]) {
        final container = openFlow();
        for (var i = 0; i < skips; i += 1) {
          await flow(container).skipThis();
        }

        await flow(container).skipAll();

        expect(step(container), OnboardingStep.done);
      }
      expect(await rows(), isEmpty);
    });

    test('undoing the About you Batch leaves onboardingDone and settings',
        () async {
      final container = openFlow();
      await flow(container).next(
        changes: const {UserProfileSection.aboutYou: aboutYou},
        unitSystem: UnitSystem.imperial,
      );
      final batchId = (await profileEntries()).single.batchId;

      final result = await repositories.activityLog.undoBatch(batchId);

      expect(result.hasConflicts, isFalse);
      expect((await profile()).aboutYou, isNull);
      final settings = await settingsRepository.load();
      expect(settings.onboardingDone, isTrue);
      expect(settings.unitSystem, UnitSystem.imperial);
    });

    group('signIn', () {
      test('a session made by the opener finishes and writes nothing',
          () async {
        final container = openFlow();

        await flow(container).signIn(() {
          return container
              .read(authControllerProvider.notifier)
              .signInWithEmail(
                rawServerUrl: 'https://sync.example.test',
                email: 'lifter@example.test',
                password: 'correct horse',
              );
        });

        expect((await settingsRepository.load()).onboardingDone, isTrue);
        expect(step(container), OnboardingStep.done);
        expect(await rows(), isEmpty);
        expect(await repositories.activityLog.listEntries(), isEmpty);
      });

      test('a session that already existed counts when the user returns',
          () async {
        final serverUrl = Uri.parse('https://sync.example.test');
        final container = openFlow(
          authRepository: InMemoryAuthRepository(
            AuthState(
              serverUrl: serverUrl,
              session: AuthSession(
                provider: AuthSessionProvider.email,
                serverUrl: serverUrl,
                token: 'memory-email-token',
                userEmail: 'lifter@example.test',
                userId: 'memory-user',
                userName: 'lifter',
              ),
            ),
          ),
        );

        await flow(container).signIn(() async {});

        expect((await settingsRepository.load()).onboardingDone, isTrue);
        expect(step(container), OnboardingStep.done);
      });

      test('no session stays on screen 1', () async {
        final container = openFlow();

        await flow(container).signIn(() async {});

        expect(step(container), OnboardingStep.screen1);
        expect((await settingsRepository.load()).onboardingDone, isFalse);
      });

      test('a failed attempt stays on screen 1', () async {
        final container = openFlow();

        await flow(container).signIn(() {
          return container
              .read(authControllerProvider.notifier)
              .signInWithEmail(
                rawServerUrl: 'https://sync.example.test',
                email: 'lifter@example.test',
                password: '',
              );
        });

        expect(step(container), OnboardingStep.screen1);
        expect((await settingsRepository.load()).onboardingDone, isFalse);
      });
    });
  });
}

class _ObservingSettingsRepository extends InMemorySettingsRepository {
  _ObservingSettingsRepository(super.initial, {required this.onSave});

  final Future<void> Function(AppSettings settings) onSave;

  @override
  Future<void> save(AppSettings settings) async {
    await onSave(settings);
    await super.save(settings);
  }
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

class _SlowFirstReadUserProfile extends Fake implements UserProfileRepository {
  final firstRead = Completer<UserProfile>();
  int _reads = 0;

  @override
  Stream<UserProfile> watch() {
    _reads += 1;
    return _reads == 1
        ? Stream<UserProfile>.fromFuture(firstRead.future)
        : Stream<UserProfile>.value(const UserProfile());
  }
}

class _ProfileStoreUnavailable implements Exception {
  const _ProfileStoreUnavailable();
}
