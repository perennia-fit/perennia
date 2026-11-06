import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/profile/user_profile.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';
import 'package:perennia/features/auth/widgets/sign_in_screen.dart';
import 'package:perennia/features/focus/controllers/focus_providers.dart';
import 'package:perennia/features/onboarding/controllers/onboarding_controller.dart';
import 'package:perennia/features/onboarding/repositories/onboarding_gate.dart';
import 'package:perennia/features/onboarding/widgets/onboarding_flow.dart';
import 'package:perennia/features/onboarding/widgets/onboarding_launcher.dart';
import 'package:perennia/features/profile/widgets/profile_screen.dart';
import 'package:perennia/features/profile/widgets/profile_section_editors.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

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

      test('an attempt still running on return is not waited for', () async {
        final auth = _HeldSignInAuthRepository();
        final container = openFlow(authRepository: auth);
        await container.read(authControllerProvider.future);
        late Future<void> attempt;

        await flow(container).signIn(() async {
          attempt =
              container.read(authControllerProvider.notifier).signInWithEmail(
                    rawServerUrl: 'https://sync.example.test',
                    email: 'lifter@example.test',
                    password: 'correct horse',
                  );
        }).timeout(const Duration(seconds: 5));

        expect(container.read(authControllerProvider).isLoading, isTrue);
        expect(step(container), OnboardingStep.screen1);
        expect((await settingsRepository.load()).onboardingDone, isFalse);

        await flow(container).skipAll().timeout(const Duration(seconds: 5));
        expect(step(container), OnboardingStep.done);

        auth.release();
        await attempt;
      });

      test('an auth state still retrying its load is not waited for', () async {
        final container = openFlow(
          authRepository: _HeldSignInAuthRepository(failLoad: true),
        );
        container.listen(authControllerProvider, (_, __) {});
        await pumpEventQueue();
        final auth = container.read(authControllerProvider);
        expect(auth.isLoading && auth.hasError, isTrue);

        await flow(container)
            .signIn(() async {})
            .timeout(const Duration(seconds: 5));

        expect(step(container), OnboardingStep.screen1);
        expect((await settingsRepository.load()).onboardingDone, isFalse);
      });

      test('finishLateSignIn finishes on screen 1 and writes no section',
          () async {
        final container = openFlow();

        await flow(container).finishLateSignIn();

        expect((await settingsRepository.load()).onboardingDone, isTrue);
        expect(step(container), OnboardingStep.done);
        expect(await rows(), isEmpty);
      });

      test('finishLateSignIn does nothing past screen 1', () async {
        final container = openFlow();
        await flow(container).skipThis();

        await flow(container).finishLateSignIn();

        expect(step(container), OnboardingStep.screen2);
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

  group('screens', () {
    const localOnlyLine =
        'Stored on this phone and in its backups. If you sign in, it syncs to '
        "your account, where the server's operator and any agent you connect "
        'can read it.';
    const syncedLine =
        "Synced to perennia.example.com. The server's operator and any agent "
        'you connect can read it. Change history on the server is kept for up '
        'to 180 days.';

    late AppDatabase database;
    late TrainingRepositories repositories;
    late InMemorySettingsRepository settingsRepository;

    final updatedAt = DateTime.utc(2026);
    final focuses = <FocusRecord>[
      FocusRecord(
        id: 'focus-strength',
        name: 'Strength',
        sortOrder: 0,
        updatedAt: updatedAt,
      ),
      FocusRecord(
        id: 'focus-running',
        name: 'Running',
        sortOrder: 1,
        updatedAt: updatedAt,
      ),
    ];

    final flowFinder = find.byType(OnboardingFlow);
    final todayFinder = find.text('Today');
    final nextButton = find.byKey(OnboardingFlow.nextButtonKey);
    final skipThisButton = find.byKey(OnboardingFlow.skipThisButtonKey);
    final skipAllButton = find.byKey(OnboardingFlow.skipAllButtonKey);
    final signInLink = find.byKey(OnboardingFlow.signInLinkKey);
    final centimetres = find.byKey(AboutYouFields.heightCentimetresKey);

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

    /// Long enough for an action's Drift reads and writes, then a route's exit.
    Future<void> settle(WidgetTester tester) async {
      for (var attempt = 0; attempt < 24; attempt += 1) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pumpApp(
      WidgetTester tester, {
      AuthRepository? authRepository,
      TrainingRepositories? trainingRepositories,
      ThemeData? theme,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainingRepositoriesProvider.overrideWith(
              (ref) => trainingRepositories ?? repositories,
            ),
            authRepositoryProvider.overrideWith(
              (ref) => authRepository ?? InMemoryAuthRepository(),
            ),
            settingsRepositoryProvider.overrideWith(
              (ref) => settingsRepository,
            ),
            activeFocusesProvider.overrideWith(
              (ref) => Stream<List<FocusRecord>>.value(focuses),
            ),
          ],
          child: MaterialApp(
            theme: theme ?? AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const OnboardingLauncher(child: Text('Today')),
          ),
        ),
      );
      await settle(tester);
    }

    /// Disposes the tree, so Drift streams close inside the test's clock and a
    /// later [pumpApp] starts with a new ProviderScope, as a reopened app does.
    Future<void> disposeApp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    Future<void> tapControl(WidgetTester tester, Finder control) async {
      await tester.ensureVisible(control);
      await tester.pump();
      await tester.tap(control);
      await settle(tester);
    }

    Future<void> tapSegment(WidgetTester tester, Key control, String label) {
      return tapControl(
        tester,
        find.descendant(of: find.byKey(control), matching: find.text(label)),
      );
    }

    Future<void> pickBirthYear(WidgetTester tester, int year) async {
      await tapControl(tester, find.byKey(AboutYouFields.birthYearKey));
      final item = find.text('$year');
      await tester.scrollUntilVisible(
        item,
        400,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pump();
      await tester.tap(item);
      await settle(tester);
    }

    Future<void> enterHeight(
      WidgetTester tester,
      Finder field,
      String text,
    ) async {
      await tester.ensureVisible(field);
      await tester.pump();
      await tester.enterText(field, text);
      await tester.pump();
    }

    Future<List<UserProfileSectionRow>> rows(WidgetTester tester) async {
      return (await tester.runAsync(
        () => database.select(database.userProfileSections).get(),
      ))!;
    }

    Future<bool> onboardingDone(WidgetTester tester) async {
      return (await tester.runAsync(settingsRepository.load))!.onboardingDone;
    }

    String textOf(WidgetTester tester, Finder field) {
      return tester.widget<TextField>(field).controller!.text;
    }

    void expectScreen1() {
      expect(flowFinder, findsOneWidget);
      expect(find.text('About you'), findsOneWidget);
      expect(find.byKey(OnboardingFlow.backButtonKey), findsNothing);
    }

    void expectScreen2() {
      expect(flowFinder, findsOneWidget);
      expect(find.text('Training Goals and Experience'), findsOneWidget);
      expect(find.byKey(OnboardingFlow.backButtonKey), findsOneWidget);
    }

    void expectToday() {
      expect(flowFinder, findsNothing);
      expect(todayFinder, findsOneWidget);
    }

    group('launcher', () {
      testWidgets('opens over Today when the gate is true', (tester) async {
        await pumpApp(tester);

        expectScreen1();
        expect(todayFinder, findsNothing);
        expect(find.text('Skip all'), findsOneWidget);
        expect(find.text('Skip this'), findsOneWidget);
        expect(find.text('Next'), findsOneWidget);
        await disposeApp(tester);
      });

      testWidgets('stays closed when a section row exists', (tester) async {
        await tester.runAsync(
          () => repositories.userProfile.saveSection(
            UserProfileSection.aboutYou,
            <String, Object?>{'birth_year': 1990},
          ),
        );

        await pumpApp(tester);

        expectToday();
        await disposeApp(tester);
      });

      testWidgets('stays closed when onboardingDone is true', (tester) async {
        settingsRepository = InMemorySettingsRepository(AppSettings.defaults);

        await pumpApp(tester);

        expectToday();
        await disposeApp(tester);
      });

      testWidgets('a gate that throws shows Today and no onboarding', (
        tester,
      ) async {
        final userProfile = _ThrowingUserProfile();

        await pumpApp(
          tester,
          trainingRepositories: _FakeRepositories(userProfile),
        );

        expect(userProfile.calls, 1);
        expectToday();
        expect(tester.takeException(), isNull);
        await disposeApp(tester);
      });
    });

    group('journeys', () {
      testWidgets('CUJ 1: Skip all lands on Today and writes nothing', (
        tester,
      ) async {
        await pumpApp(tester);

        await tapControl(tester, skipAllButton);

        expectToday();
        expect(await rows(tester), isEmpty);
        expect(await onboardingDone(tester), isTrue);
        await disposeApp(tester);

        await pumpApp(tester);

        expectToday();
        await disposeApp(tester);
      });

      testWidgets('CUJ 2: fill About you in Imperial, skip the rest', (
        tester,
      ) async {
        await pumpApp(tester);

        await tapSegment(tester, OnboardingFlow.unitSystemKey, 'Imperial');
        await tapSegment(tester, AboutYouFields.sexKey, 'Female');
        await pickBirthYear(tester, 1990);
        await enterHeight(
            tester, find.byKey(AboutYouFields.heightFeetKey), '5');
        await enterHeight(
            tester, find.byKey(AboutYouFields.heightInchesKey), '6');
        await tapControl(tester, nextButton);

        expectScreen2();
        await tapControl(tester, skipThisButton);
        expect(find.text('Training setup'), findsOneWidget);
        expect(find.text('Done'), findsOneWidget);
        await tapControl(tester, skipThisButton);

        expectToday();
        final settings = await tester.runAsync(settingsRepository.load);
        expect(settings!.unitSystem, UnitSystem.imperial);
        expect(settings.onboardingDone, isTrue);
        final row = (await rows(tester)).single;
        expect(row.section, UserProfileSection.aboutYou.wireName);
        expect(jsonDecode(row.valuesJson), <String, Object?>{
          'sex': 'female',
          'birth_year': 1990,
          'height': <String, Object?>{'value': 66, 'unit': 'in'},
        });
        await disposeApp(tester);
      });

      testWidgets('CUJ 3: killed on screen 1 before any tap, it shows again', (
        tester,
      ) async {
        await pumpApp(tester);
        expectScreen1();
        await disposeApp(tester);

        await pumpApp(tester);

        expectScreen1();
        expect(await onboardingDone(tester), isFalse);
        await disposeApp(tester);
      });

      testWidgets('CUJ 3: killed after leaving screen 1, it does not', (
        tester,
      ) async {
        await pumpApp(tester);
        await enterHeight(tester, centimetres, '170');
        await tapControl(tester, nextButton);
        expectScreen2();
        await disposeApp(tester);

        await pumpApp(tester);

        expectToday();
        expect(
          jsonDecode((await rows(tester)).single.valuesJson)['height'],
          <String, Object?>{'value': 170, 'unit': 'cm'},
        );
        await disposeApp(tester);
      });

      testWidgets('CUJ 4: signing in closes the flow and writes no section', (
        tester,
      ) async {
        final auth = InMemoryAuthRepository();
        await pumpApp(tester, authRepository: auth);
        await enterHeight(tester, centimetres, '170');

        await tapControl(tester, signInLink);
        expect(find.byType(SignInScreen), findsOneWidget);

        await tester.enterText(
          find.byKey(SignInScreen.serverUrlFieldKey),
          'https://sync.example.test',
        );
        await tester.enterText(
          find.byKey(SignInScreen.emailFieldKey),
          'lifter@example.test',
        );
        await tester.enterText(
          find.byKey(SignInScreen.passwordFieldKey),
          'correct horse',
        );
        await tapControl(
          tester,
          find.byKey(SignInScreen.emailSignInButtonKey),
        );

        expect(auth.emailAttempts, hasLength(1));
        expect(find.byType(SignInScreen), findsNothing);
        expectToday();
        expect(await onboardingDone(tester), isTrue);
        expect(await rows(tester), isEmpty);
        await disposeApp(tester);
      });

      testWidgets('back from sign-in returns to screen 1, fields kept', (
        tester,
      ) async {
        await pumpApp(tester);
        await enterHeight(tester, centimetres, '170');

        await tapControl(tester, signInLink);
        await tester.binding.handlePopRoute();
        await settle(tester);

        expect(find.byType(SignInScreen), findsNothing);
        expectScreen1();
        expect(textOf(tester, centimetres), '170');
        expect(await onboardingDone(tester), isFalse);
        expect(await rows(tester), isEmpty);

        await tapControl(tester, nextButton);

        expectScreen2();
        expect(
          jsonDecode((await rows(tester)).single.valuesJson)['height'],
          <String, Object?>{'value': 170, 'unit': 'cm'},
        );
        await disposeApp(tester);
      });

      group('backing out of a running sign-in', () {
        Future<void> backOutOfRunningSignIn(WidgetTester tester) async {
          await tapControl(tester, signInLink);
          await tester.enterText(
            find.byKey(SignInScreen.serverUrlFieldKey),
            'https://sync.example.test',
          );
          await tester.enterText(
            find.byKey(SignInScreen.emailFieldKey),
            'lifter@example.test',
          );
          await tester.enterText(
            find.byKey(SignInScreen.passwordFieldKey),
            'correct horse',
          );
          await tapControl(
            tester,
            find.byKey(SignInScreen.emailSignInButtonKey),
          );
          expect(find.byType(SignInScreen), findsOneWidget);
          await tester.binding.handlePopRoute();
          await settle(tester);
          expect(find.byType(SignInScreen), findsNothing);
        }

        testWidgets('leaves screen 1 working, and Skip all leaves it', (
          tester,
        ) async {
          final auth = _HeldSignInAuthRepository();
          await pumpApp(tester, authRepository: auth);
          await enterHeight(tester, centimetres, '170');

          await backOutOfRunningSignIn(tester);

          expectScreen1();
          expect(textOf(tester, centimetres), '170');
          for (final control in [skipAllButton, skipThisButton, nextButton]) {
            final button = find.descendant(
              of: control,
              matching: find.bySubtype<ButtonStyleButton>(),
              matchRoot: true,
            );
            expect(
              tester.widget<ButtonStyleButton>(button).onPressed,
              isNotNull,
            );
          }
          expect(tester.widget<TextButton>(signInLink).onPressed, isNotNull);

          await tapControl(tester, skipAllButton);

          expectToday();
          expect(await onboardingDone(tester), isTrue);

          auth.release();
          await settle(tester);
          expectToday();
          await disposeApp(tester);
        });

        testWidgets('a later success on screen 1 opens Today', (tester) async {
          final auth = _HeldSignInAuthRepository();
          await pumpApp(tester, authRepository: auth);

          await backOutOfRunningSignIn(tester);
          expectScreen1();

          auth.release();
          await settle(tester);

          expectToday();
          expect(await onboardingDone(tester), isTrue);
          expect(await rows(tester), isEmpty);
          await disposeApp(tester);
        });

        testWidgets('a later failure stays on screen 1, still working', (
          tester,
        ) async {
          final auth = _HeldSignInAuthRepository(failSignIn: true);
          await pumpApp(tester, authRepository: auth);

          await backOutOfRunningSignIn(tester);

          auth.release();
          await settle(tester);

          expectScreen1();
          expect(await onboardingDone(tester), isFalse);

          await tapControl(tester, nextButton);
          expectScreen2();
          await disposeApp(tester);
        });

        testWidgets('a later success on screen 2 leaves the user there', (
          tester,
        ) async {
          final auth = _HeldSignInAuthRepository();
          await pumpApp(tester, authRepository: auth);

          await backOutOfRunningSignIn(tester);
          await tapControl(tester, nextButton);
          expectScreen2();

          auth.release();
          await settle(tester);

          expectScreen2();
          await disposeApp(tester);
        });

        testWidgets('a later success does not pop a picker open over the flow',
            (tester) async {
          final auth = _HeldSignInAuthRepository();
          await pumpApp(tester, authRepository: auth);

          await backOutOfRunningSignIn(tester);
          await tapControl(tester, find.byKey(AboutYouFields.birthYearKey));
          final year = find.text('1988');
          await tester.scrollUntilVisible(
            year,
            400,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.pump();

          auth.release();
          await settle(tester);

          expect(year, findsOneWidget);
          await tester.tap(year);
          await settle(tester);

          expectScreen1();
          await tapControl(tester, skipAllButton);
          expectToday();
          await disposeApp(tester);
        });
      });
    });

    group('saving', () {
      testWidgets('a pick left behind by Skip this is not saved', (
        tester,
      ) async {
        await pumpApp(tester);

        await tapSegment(tester, OnboardingFlow.unitSystemKey, 'Imperial');
        await tapControl(tester, skipThisButton);
        expectScreen2();
        await tapControl(tester, find.byKey(OnboardingFlow.backButtonKey));
        expectScreen1();

        expect(centimetres, findsOneWidget);
        await tapControl(tester, nextButton);

        final settings = await tester.runAsync(settingsRepository.load);
        expect(settings!.unitSystem, UnitSystem.metric);
        await disposeApp(tester);
      });

      testWidgets('a soft warning asks first; Edit stays, Save anyway saves', (
        tester,
      ) async {
        await pumpApp(tester);
        await pickBirthYear(tester, DateTime.now().year - 101);

        await tapControl(tester, nextButton);

        expect(find.byKey(ProfileEditorKeys.warningDialog), findsOneWidget);
        expect(
          find.text('That makes you 101. Check the birth year.'),
          findsOneWidget,
        );

        await tapControl(
            tester, find.byKey(ProfileEditorKeys.warningEditButton));

        expect(find.byKey(ProfileEditorKeys.warningDialog), findsNothing);
        expectScreen1();
        expect(await rows(tester), isEmpty);
        expect(await onboardingDone(tester), isFalse);

        await tapControl(tester, nextButton);
        await tapControl(
          tester,
          find.byKey(ProfileEditorKeys.warningSaveAnywayButton),
        );

        expectScreen2();
        expect(
          jsonDecode((await rows(tester)).single.valuesJson)['birth_year'],
          DateTime.now().year - 101,
        );
        expect(await onboardingDone(tester), isTrue);
        await disposeApp(tester);
      });

      testWidgets('a hard error shows and stays; editing clears it', (
        tester,
      ) async {
        await pumpApp(tester);
        await enterHeight(tester, centimetres, '301');

        await tapControl(tester, nextButton);

        const message = 'Height must be 300 cm (118.1 in) or less.';
        expect(find.text(message), findsOneWidget);
        expect(find.text(message).hitTestable(), findsOneWidget);
        expect(find.byKey(ProfileEditorKeys.warningDialog), findsNothing);
        expectScreen1();
        expect(await rows(tester), isEmpty);
        expect(await onboardingDone(tester), isFalse);

        await enterHeight(tester, centimetres, '170');

        expect(find.text(message), findsNothing);
        await disposeApp(tester);
      });

      testWidgets('a future birth year from a stored row is a hard error', (
        tester,
      ) async {
        await pumpApp(tester);
        await tapControl(tester, skipThisButton);
        // The year dropdown stops at this year, so only a pulled row can hold
        // a later one. The repository rejects it, so it goes in through Drift.
        await tester.runAsync(
          () => database.into(database.userProfileSections).insert(
                UserProfileSectionRow(
                  id: 'pulled-about-you',
                  section: UserProfileSection.aboutYou.wireName,
                  valuesJson: jsonEncode(<String, Object?>{
                    'birth_year': DateTime.now().year + 1,
                  }),
                  syncPreviouslySynced: false,
                  updatedAt: updatedAt,
                ),
              ),
        );
        await tapControl(tester, find.byKey(OnboardingFlow.backButtonKey));
        expectScreen1();
        await tapSegment(tester, AboutYouFields.sexKey, 'Female');

        await tapControl(tester, nextButton);

        expect(find.text("Birth year can't be in the future."), findsOneWidget);
        expectScreen1();
        await disposeApp(tester);
      });

      testWidgets('a second tap on Next writes one Batch', (tester) async {
        await pumpApp(tester);
        await tapControl(tester, skipThisButton);
        await tapControl(
          tester,
          find.byKey(TrainingGoalsFields.goalKey(TrainingGoalId.strength)),
        );
        await tester.ensureVisible(nextButton);
        await tester.pump();

        await tester.tap(nextButton);
        await tester.pump();
        await tester.tap(nextButton, warnIfMissed: false);
        await settle(tester);

        expect(find.text('Training setup'), findsOneWidget);
        final entries = await tester.runAsync(
          () => repositories.activityLog.listEntries(),
        );
        expect(entries, hasLength(1));
        await disposeApp(tester);
      });
    });

    group('system back', () {
      testWidgets('does nothing on screen 1 and steps back on screen 2', (
        tester,
      ) async {
        await pumpApp(tester);

        await tester.binding.handlePopRoute();
        await settle(tester);
        expectScreen1();

        await tapControl(tester, skipThisButton);
        expectScreen2();

        await tester.binding.handlePopRoute();
        await settle(tester);
        expectScreen1();
        await disposeApp(tester);
      });
    });

    group('disclosure line', () {
      testWidgets('shows the Local-only Mode line', (tester) async {
        await pumpApp(tester);

        expect(find.text(localOnlyLine), findsOneWidget);
        expect(find.text(syncedLine), findsNothing);
        await disposeApp(tester);
      });

      testWidgets('shows the Synced Mode line', (tester) async {
        final serverUrl = Uri.parse('https://perennia.example.com');
        await pumpApp(
          tester,
          authRepository: InMemoryAuthRepository(
            AuthState(
              serverUrl: serverUrl,
              session: AuthSession(
                provider: AuthSessionProvider.email,
                serverUrl: serverUrl,
                token: 'token-a',
                userEmail: 'lifter@example.test',
                userId: 'user-a',
                userName: 'lifter',
              ),
            ),
          ),
        );

        expect(find.text(syncedLine), findsOneWidget);
        expect(find.text(localOnlyLine), findsNothing);
        await disposeApp(tester);
      });
    });

    group('accessibility', () {
      testWidgets('every screen meets the guidelines in both themes', (
        tester,
      ) async {
        for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
          settingsRepository = InMemorySettingsRepository(
            AppSettings.defaults.copyWith(onboardingDone: false),
          );
          final semantics = tester.ensureSemantics();
          await pumpApp(tester, theme: theme);

          for (final screen in <int>[1, 2, 3]) {
            final reason = 'screen $screen, ${theme.brightness.name}';
            await expectLater(
              tester,
              meetsGuideline(textContrastGuideline),
              reason: reason,
            );
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
              reason: reason,
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
              reason: reason,
            );
            if (screen < 3) {
              await tapControl(tester, skipThisButton);
            }
          }

          semantics.dispose();
          await disposeApp(tester);
        }
      });

      testWidgets(
          'at 200% text on a phone nothing overflows and every control can be '
          'reached', (tester) async {
        tester.view.physicalSize = const Size(360, 720);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        Future<void> expectReachable(List<Finder> controls) async {
          for (final control in controls) {
            await tester.ensureVisible(control);
            await tester.pump();
            expect(control.hitTestable(), findsOneWidget, reason: '$control');
          }
          expect(skipAllButton.hitTestable(), findsOneWidget);
          expect(skipThisButton.hitTestable(), findsOneWidget);
          expect(nextButton.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }

        await pumpApp(tester);
        expect(tester.takeException(), isNull);

        await expectReachable([
          find.byKey(OnboardingFlow.unitSystemKey),
          find.byKey(OnboardingFlow.weekStartDayKey),
          find.byKey(AboutYouFields.sexKey),
          find.byKey(AboutYouFields.birthYearKey),
          centimetres,
          signInLink,
          find.byType(ProfileDisclosureLine),
        ]);

        await tapSegment(tester, OnboardingFlow.unitSystemKey, 'Imperial');
        await expectReachable([
          find.byKey(AboutYouFields.heightFeetKey),
          find.byKey(AboutYouFields.heightInchesKey),
        ]);

        await tapControl(tester, skipThisButton);
        expect(tester.takeException(), isNull);
        await expectReachable([
          find.byKey(OnboardingFlow.backButtonKey),
          for (final goal in TrainingGoalId.values)
            find.byKey(TrainingGoalsFields.goalKey(goal)),
          find.byKey(TrainingGoalsFields.noneKey),
          for (final focus in focuses)
            for (final level in <ExperienceLevel?>[
              ...ExperienceLevel.values,
              null,
            ])
              find.byKey(ExperienceFields.levelKey(focus.id, level)),
          find.byKey(ExperienceFields.noneKey),
          find.byType(ProfileDisclosureLine),
        ]);

        await tapControl(tester, skipThisButton);
        expect(tester.takeException(), isNull);
        await expectReachable([
          find.byKey(OnboardingFlow.backButtonKey),
          find.byKey(TrainingSetupFields.equipmentKey('skiErg')),
          find.byKey(TrainingSetupFields.equipmentNoneKey),
          find.byKey(TrainingSetupFields.daysDecreaseKey),
          find.byKey(TrainingSetupFields.daysIncreaseKey),
          find.byKey(TrainingSetupFields.sessionMinutesKey),
          find.byType(ProfileDisclosureLine),
        ]);

        await tapControl(tester, nextButton);
        expectToday();
        await disposeApp(tester);
      });
    });
  });
}

/// Holds each email sign-in open until [release], like a slow or hung server.
class _HeldSignInAuthRepository extends InMemoryAuthRepository {
  _HeldSignInAuthRepository({this.failLoad = false, this.failSignIn = false});

  final bool failLoad;
  final bool failSignIn;
  final _held = Completer<void>();

  void release() => _held.complete();

  @override
  Future<AuthState> load() {
    return failLoad
        ? Future.error(const _AuthStoreUnavailable())
        : super.load();
  }

  @override
  Future<AuthSession> signInWithEmail({
    required Uri serverUrl,
    required String email,
    required String password,
  }) async {
    await _held.future;
    if (failSignIn) {
      throw const _AuthStoreUnavailable();
    }
    return super.signInWithEmail(
      serverUrl: serverUrl,
      email: email,
      password: password,
    );
  }
}

class _AuthStoreUnavailable implements Exception {
  const _AuthStoreUnavailable();
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
