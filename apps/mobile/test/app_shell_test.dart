import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:perennia/app.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/platform_exercise_seed.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';
import 'package:perennia/features/auth/widgets/sign_in_screen.dart';
import 'package:perennia/features/body_tracker/widgets/body_tracker_screen.dart';
import 'package:perennia/features/catalog/repositories/exercise_catalog_repository.dart';
import 'package:perennia/features/catalog/widgets/exercise_catalog_picker.dart';
import 'package:perennia/features/catalog/widgets/exercise_editor_screen.dart';
import 'package:perennia/features/exercise/widgets/exercise_page.dart';
import 'package:perennia/features/home/controllers/home_controller.dart';
import 'package:perennia/features/home/repositories/home_repository.dart';
import 'package:perennia/features/home/widgets/home_screen.dart';
import 'package:perennia/features/home/widgets/workout_screen.dart';
import 'package:perennia/features/metrics/controllers/metrics_controller.dart';
import 'package:perennia/features/metrics/widgets/metrics_screen.dart';
import 'package:perennia/features/nutrition/controllers/nutrition_day_controller.dart';
import 'package:perennia/features/nutrition/widgets/nutrition_day_view.dart';
import 'package:perennia/features/protocols/controllers/protocols_day_controller.dart';
import 'package:perennia/features/protocols/services/protocols_lock_store.dart';
import 'package:perennia/features/protocols/widgets/compound_list_screen.dart';
import 'package:perennia/features/protocols/widgets/protocols_day_view.dart';
import 'package:perennia/features/routine_plans/controllers/routine_plan_controller.dart';
import 'package:perennia/features/routine_plans/repositories/routine_plan_feature_repository.dart';
import 'package:perennia/features/routine_plans/widgets/routine_plan_list_screen.dart';
import 'package:perennia/features/settings/repositories/integration_consent_repository.dart';
import 'package:perennia/features/template_divergence/repositories/template_divergence_feature_repository.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/features/settings/services/client_crash_reporting.dart';
import 'package:perennia/features/settings/widgets/settings_screen.dart';
import 'package:perennia/features/sync/controllers/sync_status_controller.dart';
import 'package:perennia/features/sync/services/sync_coordinator.dart';
import 'package:perennia/features/sync/services/sync_providers.dart';
import 'package:perennia/features/template_picker/widgets/template_picker_sheet.dart';
import 'package:perennia/features/up_next/repositories/up_next_feature_repository.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  testWidgets('launches home through the ProviderScope app root',
      (tester) async {
    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [_homeNutritionDayOverride()],
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: StubHomeRepository(),
      ),
    );
    await tester.pump();

    expect(find.byType(ProviderScope), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byKey(HomeScreen.todayDestinationKey), findsOneWidget);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.localizationsDelegates, AppLocalizations.localizationsDelegates);
    expect(app.supportedLocales, AppLocalizations.supportedLocales);

    final context = tester.element(find.byType(HomeScreen));
    expect(Theme.of(context).colorScheme.primary, DesignTokens.primary);
    expect(context.colors.save, DesignTokens.save);
  });

  testWidgets('root navigation separates Today, Progress, and Library', (
    tester,
  ) async {
    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [_homeNutritionDayOverride()],
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: StubHomeRepository(),
      ),
    );
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(HomeScreen.todayDestinationKey), findsOneWidget);
    expect(find.byKey(HomeScreen.progressDestinationKey), findsOneWidget);
    expect(find.byKey(HomeScreen.libraryDestinationKey), findsOneWidget);

    await tester.tap(find.byKey(HomeScreen.progressDestinationKey));
    await tester.pumpAndSettle();

    expect(find.text('Body'), findsOneWidget);
    expect(find.text('Health metrics'), findsOneWidget);
  });

  testWidgets('root chrome stays available when the Training Day fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [_homeNutritionDayOverride()],
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: const _ErrorHomeRepository(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Home unavailable'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(HomeScreen.accountAndAppButtonKey), findsOneWidget);

    await tester.tap(find.byKey(HomeScreen.progressDestinationKey));
    await tester.pumpAndSettle();

    expect(find.text('Body'), findsOneWidget);
    expect(find.text('Health metrics'), findsOneWidget);
  });

  testWidgets('root chrome stays available while the Training Day loads', (
    tester,
  ) async {
    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [_homeNutritionDayOverride()],
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: const _LoadingHomeRepository(),
      ),
    );
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(HomeScreen.accountAndAppButtonKey), findsOneWidget);

    await tester.tap(find.byKey(HomeScreen.libraryDestinationKey));
    await tester.pumpAndSettle();

    expect(find.text('Routines'), findsOneWidget);
    expect(find.text('Supplements'), findsWidgets);
  });

  testWidgets('Progress and Library meet accessibility guidelines', (
    tester,
  ) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            upNextFeatureRepositoryProvider.overrideWith(
              (ref) => const StubUpNextFeatureRepository(),
            ),
            settingsRepositoryProvider.overrideWith(
              (ref) => InMemorySettingsRepository(),
            ),
            homeRepositoryProvider.overrideWith(
              (ref) => const _DateEchoHomeRepository(),
            ),
            _homeNutritionDayOverride(),
          ],
          child: MaterialApp(
            theme: theme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final destinationKey in <Key>[
        HomeScreen.progressDestinationKey,
        HomeScreen.libraryDestinationKey,
      ]) {
        await tester.tap(find.byKey(destinationKey));
        await tester.pumpAndSettle();

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Today keeps its scroll position across root destinations', (
    tester,
  ) async {
    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [_homeNutritionDayOverride()],
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: const _ScrollableHomeRepository(),
      ),
    );
    await tester.pumpAndSettle();

    final todayScrollable = find.ancestor(
      of: find.byKey(HomeScreen.trainingDomainBodyKey),
      matching: find.byType(Scrollable),
    );
    await tester.drag(todayScrollable, const Offset(0, -700));
    await tester.pumpAndSettle();
    final before =
        tester.state<ScrollableState>(todayScrollable).position.pixels;
    expect(before, greaterThan(0));

    await tester.tap(find.byKey(HomeScreen.progressDestinationKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeScreen.todayDestinationKey));
    await tester.pumpAndSettle();

    final after =
        tester.state<ScrollableState>(todayScrollable).position.pixels;
    expect(after, before);
  });

  testWidgets('Today app bar exposes one Account and app control', (
    tester,
  ) async {
    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [_homeNutritionDayOverride()],
        authRepository: InMemoryAuthRepository(),
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: StubHomeRepository(),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Account & app'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(IconButton),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Account & app'));
    await tester.pumpAndSettle();

    expect(find.text('Account & app'), findsOneWidget);
    expect(find.text('Local only'), findsOneWidget);
    expect(find.text('Sign in to sync'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('Today keeps plans contextual and groups daily log actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [_homeNutritionDayOverride()],
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: StubHomeRepository(),
      ),
    );
    await tester.pump();

    expect(find.text('No meals logged yet'), findsNothing);
    expect(find.text('Manage routines'), findsOneWidget);

    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();

    expect(find.text('Log for this day'), findsOneWidget);
    expect(find.text('Workout'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Supplement'), findsOneWidget);
  });

  testWidgets('follows platform brightness', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [_homeNutritionDayOverride()],
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: StubHomeRepository(),
      ),
    );
    await tester.pump();

    final context = tester.element(find.byType(HomeScreen));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(context.colors.background, DesignTokens.backgroundDark);
  });

  testWidgets('settings theme preference repaints the app', (tester) async {
    final settingsRepository = InMemorySettingsRepository(
      const AppSettings(themePreference: AppThemePreference.light),
    );
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [
          _homeNutritionDayOverride(),
          appDatabaseProvider.overrideWith((ref) => database),
          garminImportConsentStateProvider.overrideWith(
            (ref) => Stream<GarminImportConsentState>.value(
              GarminImportConsentState.empty,
            ),
          ),
          syncStatusControllerProvider.overrideWith(
            () => _StubSyncStatusController(
              SyncStatusState.initial(DateTime.utc(2026, 6, 22, 12)),
            ),
          ),
        ],
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: StubHomeRepository(),
        settingsRepository: settingsRepository,
      ),
    );
    await tester.pump();

    expect(
      Theme.of(tester.element(find.byType(HomeScreen))).brightness,
      Brightness.light,
    );

    await _openAccountAndAppSettings(tester);
    await tester.tap(find.byKey(SettingsScreen.generalTileKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.byType(GeneralSettingsScreen))).brightness,
      Brightness.dark,
    );
    expect(
      (await settingsRepository.load()).themePreference,
      AppThemePreference.dark,
    );
  });

  testWidgets('renders home while settings are still loading', (tester) async {
    final settingsRepository = _DeferredSettingsRepository();

    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [_homeNutritionDayOverride()],
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: StubHomeRepository(),
        settingsRepository: settingsRepository,
      ),
    );
    await tester.pump();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byKey(HomeScreen.todayDestinationKey), findsOneWidget);
  });

  testWidgets(
    'default split settings repository resolves on a fresh database',
    (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final supportDirectory =
          Directory.systemTemp.createTempSync('perennia-settings-');
      const pathProviderChannel =
          MethodChannel('plugins.flutter.io/path_provider');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pathProviderChannel,
        (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return supportDirectory.path;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          pathProviderChannel,
          null,
        );
        if (supportDirectory.existsSync()) {
          supportDirectory.deleteSync(recursive: true);
        }
      });

      final container = ProviderContainer(
        overrides: [
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          _homeNutritionDayOverride(),
          appDatabaseProvider.overrideWith((ref) => database),
          exerciseCatalogRepositoryProvider.overrideWith(
            (ref) => const StubExerciseCatalogRepository(),
          ),
          homeRepositoryProvider.overrideWith(
            (ref) => StubHomeRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final settingsRepository = container.read(settingsRepositoryProvider);
      expect(settingsRepository, isA<SplitSettingsRepository>());
      final settings = await tester.runAsync(
        () => settingsRepository.load().timeout(const Duration(seconds: 5)),
      );
      expect(settings, isNotNull);
      expect(settings!.themePreference, AppThemePreference.system);
      expect(settings.unitSystem, UnitSystem.metric);

      final accountSettings = await tester.runAsync(
        () =>
            container.read(trainingRepositoriesProvider).accountSettings.load(),
      );
      expect(accountSettings, isNotNull);
      expect(accountSettings!.themePreference, 'system');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const PerenniaApp(),
        ),
      );
      await tester.pump();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byKey(HomeScreen.todayDestinationKey), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settings crash reporting preference updates the reporter', (
    tester,
  ) async {
    final settingsRepository = InMemorySettingsRepository(
      AppSettings.defaults.copyWith(crashReportingEnabled: true),
    );
    final crashReporter = _FakeClientCrashReporter();
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [
          _homeNutritionDayOverride(),
          appDatabaseProvider.overrideWith((ref) => database),
          garminImportConsentStateProvider.overrideWith(
            (ref) => Stream<GarminImportConsentState>.value(
              GarminImportConsentState.empty,
            ),
          ),
          clientCrashReporterProvider.overrideWith((ref) => crashReporter),
          syncStatusControllerProvider.overrideWith(
            () => _StubSyncStatusController(
              SyncStatusState.initial(DateTime.utc(2026, 6, 22, 12)),
            ),
          ),
        ],
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: StubHomeRepository(),
        settingsRepository: settingsRepository,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(crashReporter.enabledValues, contains(true));

    await _openAccountAndAppSettings(tester);
    await tester.scrollUntilVisible(
      find.byKey(SettingsScreen.privacyTileKey),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(SettingsScreen.privacyTileKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SettingsScreen.privacyTileKey));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(SettingsScreen.crashReportingSwitchKey),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(SettingsScreen.crashReportingSwitchKey));
    await tester.pump();
    await tester.pump();

    expect(crashReporter.enabledValues.last, isFalse);
  });

  testWidgets('home account action opens auth-only sign-in', (tester) async {
    final authRepository = InMemoryAuthRepository();

    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [_homeNutritionDayOverride()],
        authRepository: authRepository,
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: StubHomeRepository(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(HomeScreen.accountAndAppButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeScreen.accountAndAppSignInKey));
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
    // Prefilled from the build's configured default, which is empty unless a
    // distributor injected one — a stock build must not suggest a server the
    // user never chose.
    expect(
      tester
          .widget<TextField>(find.byKey(SignInScreen.serverUrlFieldKey))
          .controller
          ?.text,
      defaultAuthServerUrl,
    );
  });

  testWidgets('Account and app reports the signed-in account', (tester) async {
    final serverUrl = Uri.parse('https://perennia.example.com');
    final session = AuthSession(
      provider: AuthSessionProvider.email,
      serverUrl: serverUrl,
      token: 'token-a',
      userEmail: 'qa@example.com',
      userId: 'user-a',
      userName: 'QA User',
    );

    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [
          _homeNutritionDayOverride(),
          _disabledSyncCoordinatorOverride(),
        ],
        authRepository: InMemoryAuthRepository(
          AuthState(serverUrl: serverUrl, session: session),
        ),
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: StubHomeRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(HomeScreen.accountAndAppButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('qa@example.com'), findsOneWidget);
    expect(find.text('Manage account and sync'), findsOneWidget);
    expect(find.text('Local only'), findsNothing);
  });

  testWidgets('Account and app waits for the live auth state', (tester) async {
    final authRepository = _DeferredAuthRepository();
    final serverUrl = Uri.parse('https://perennia.example.com');

    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [
          _homeNutritionDayOverride(),
          _disabledSyncCoordinatorOverride(),
        ],
        authRepository: authRepository,
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: StubHomeRepository(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(HomeScreen.accountAndAppButtonKey));
    await tester.pump();

    expect(find.text('Local only'), findsNothing);
    expect(find.text('Checking account status'), findsOneWidget);

    authRepository.completer.complete(
      AuthState(
        serverUrl: serverUrl,
        session: AuthSession(
          provider: AuthSessionProvider.email,
          serverUrl: serverUrl,
          token: 'token-live',
          userEmail: 'live@example.com',
          userId: 'user-live',
          userName: 'Live User',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('live@example.com'), findsOneWidget);
    expect(find.text('Manage account and sync'), findsOneWidget);
  });

  testWidgets('Progress opens Body Tracker', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [
          _homeNutritionDayOverride(),
          appDatabaseProvider.overrideWith((ref) => database),
        ],
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: StubHomeRepository(),
        settingsRepository: InMemorySettingsRepository(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(HomeScreen.progressDestinationKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Body'));
    await tester.pump(const Duration(milliseconds: 300));
    await _pumpUntilFound(tester, find.byType(BodyTrackerScreen));

    expect(find.byType(BodyTrackerScreen), findsOneWidget);

    await _disposeAppShellWidgetTree(tester);
  });

  testWidgets('Progress opens Metrics', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [
          _homeNutritionDayOverride(),
          appDatabaseProvider.overrideWith((ref) => database),
          // Navigation smoke test only: keep this off real Drift watch streams.
          metricsControllerProvider.overrideWith(_StubMetricsController.new),
        ],
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: StubHomeRepository(),
        settingsRepository: InMemorySettingsRepository(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(HomeScreen.progressDestinationKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Health metrics'));
    await tester.pump(const Duration(milliseconds: 300));
    await _pumpUntilFound(tester, find.byType(MetricsScreen));

    expect(find.byType(MetricsScreen), findsOneWidget);
  });

  testWidgets('Today Routine actions use the canonical Library and editor',
      (tester) async {
    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [
          _homeNutritionDayOverride(),
          routinePlanListControllerProvider.overrideWith(
            _StubRoutinePlanListController.new,
          ),
        ],
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: StubHomeRepository(),
        settingsRepository: InMemorySettingsRepository(),
      ),
    );
    await tester.pumpAndSettle();

    // The "Load Routine" affordance now opens the picker sheet (M34-03)
    // rather than switching to the Library tab — that interim M33-06
    // destination is retired.
    expect(find.byKey(HomeScreen.loadRoutineButtonKey), findsOneWidget);
    await tester.tap(find.byKey(HomeScreen.loadRoutineButtonKey));
    await tester.pumpAndSettle();
    expect(find.byType(TemplatePickerSheet), findsOneWidget);
    expect(find.byKey(TemplatePickerSheet.emptyStateKey), findsOneWidget);
    Navigator.of(tester.element(find.byType(TemplatePickerSheet))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(HomeScreen.todayDestinationKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeScreen.libraryDestinationKey));
    await tester.pumpAndSettle();
    expect(find.byKey(HomeScreen.workoutTemplatesButtonKey), findsOneWidget);
    expect(find.byKey(HomeScreen.routinePlansButtonKey), findsOneWidget);

    await tester.tap(find.byKey(HomeScreen.routinePlansButtonKey));
    await tester.pumpAndSettle();
    expect(find.byType(RoutinePlanListScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(RoutinePlanListScreen))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(HomeScreen.todayDestinationKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeScreen.manageRoutinesButtonKey));
    await tester.pumpAndSettle();
    expect(find.byType(RoutinePlanListScreen), findsOneWidget);
  });

  testWidgets('Library opens the New Exercise editor', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repositories = TrainingRepositories(
      database,
      platformSeedSource: const _EmptyAppShellExerciseSeedSource(),
    );

    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [
          _homeNutritionDayOverride(),
          trainingRepositoriesProvider.overrideWith(
            (ref) => repositories,
          ),
        ],
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: StubHomeRepository(),
        settingsRepository: InMemorySettingsRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(HomeScreen.libraryDestinationKey));
    await tester.pumpAndSettle();

    expect(
      find.byKey(HomeScreen.createExerciseButtonKey),
      findsOneWidget,
    );

    await tester.tap(find.byKey(HomeScreen.createExerciseButtonKey));
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseEditorScreen), findsOneWidget);
    expect(find.text('New exercise'), findsOneWidget);
  });

  testWidgets('Library opens the discreet Compound list', (tester) async {
    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [
          _homeNutritionDayOverride(),
          compoundListProvider.overrideWith(
            (ref) => Stream<List<CompoundRecord>>.value(
              const <CompoundRecord>[],
            ),
          ),
          recentCompoundIdsProvider.overrideWith(
            (ref) => Stream<List<String>>.value(const <String>[]),
          ),
          protocolDayControllerProvider.overrideWith(
            _StubProtocolDayController.new,
          ),
          protocolsLockStoreProvider.overrideWith((ref) => _NoLockStore()),
        ],
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: StubHomeRepository(),
        settingsRepository: InMemorySettingsRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(HomeScreen.libraryDestinationKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supplements').last);
    await tester.pumpAndSettle();

    expect(find.byType(CompoundListScreen), findsOneWidget);
  });

  testWidgets('Today Log opens the selected Nutrition Day for Food', (
    tester,
  ) async {
    final selectedDate =
        TrainingDayDate.fromDateTime(DateTime.now()).addDays(1);

    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [
          _homeNutritionDayOverride(),
          nutritionDayControllerProvider.overrideWith(
            _StubNutritionDayController.new,
          ),
        ],
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: const _DateEchoHomeRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeScreen.nextDayButtonKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(HomeScreen.logButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeScreen.logFoodKey));
    await tester.pumpAndSettle();

    expect(find.byType(NutritionDayView), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NutritionDayView)),
    );
    expect(
      container.read(selectedNutritionDayProvider),
      nutritionDayDateFromTrainingDay(selectedDate),
    );
  });

  testWidgets('Today Log opens a new Workout', (tester) async {
    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [_homeNutritionDayOverride()],
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: StubHomeRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(HomeScreen.logButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeScreen.logWorkoutKey));
    await tester.pumpAndSettle();

    expect(find.byType(WorkoutScreen), findsOneWidget);
  });

  testWidgets('Today reports a failure to start a Workout', (tester) async {
    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [_homeNutritionDayOverride()],
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: _FailingStartHomeRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(HomeScreen.logButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeScreen.logWorkoutKey));
    await tester.pumpAndSettle();

    expect(find.text('Could not start workout. Try again.'), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Today Log opens the discreet Protocol Day surface', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    // This is a NAVIGATION smoke test, not a Protocols data test. Stub the
    // Protocol Day providers so the assertion stays focused on the route.
    await tester.pumpWidget(
      PerenniaRoot(
        upNextFeatureRepository: const StubUpNextFeatureRepository(),
        extraOverrides: [
          _homeNutritionDayOverride(),
          appDatabaseProvider.overrideWith((ref) => database),
          compoundListProvider.overrideWith(
            (ref) => Stream<List<CompoundRecord>>.value(
              const <CompoundRecord>[],
            ),
          ),
          recentCompoundIdsProvider.overrideWith(
            (ref) => Stream<List<String>>.value(
              const <String>[],
            ),
          ),
          protocolDayControllerProvider.overrideWith(
            _StubProtocolDayController.new,
          ),
          // Keeps `ProtocolsLockGate` off the real secure-storage
          // plugin channel, which no widget test has a device for.
          protocolsLockStoreProvider.overrideWith(
            (ref) => _NoLockStore(),
          ),
        ],
        exerciseCatalogRepository: const StubExerciseCatalogRepository(),
        homeRepository: StubHomeRepository(),
        settingsRepository: InMemorySettingsRepository(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(HomeScreen.logButtonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(HomeScreen.logSupplementKey), findsOneWidget);
    // Neutral capsule iconography — never a syringe.
    expect(
      find.descendant(
        of: find.byKey(HomeScreen.logSupplementKey),
        matching: find.byIcon(Icons.medication_outlined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(HomeScreen.logSupplementKey),
        matching: find.byIcon(Icons.vaccines),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(HomeScreen.logSupplementKey));
    await tester.pump(const Duration(milliseconds: 300));
    await _pumpUntilFound(tester, find.byType(ProtocolsDayView));

    expect(find.byType(ProtocolsDayView), findsOneWidget);
  });

  testWidgets(
    'the Training|Nutrition domain toggle never carries a Supplements segment',
    (tester) async {
      final today = TrainingDayDate.fromDateTime(DateTime.now());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            upNextFeatureRepositoryProvider.overrideWith(
              (ref) => const StubUpNextFeatureRepository(),
            ),
            homeRepositoryProvider.overrideWith(
              (ref) => const _DateEchoHomeRepository(),
            ),
            homeNutritionDayProvider.overrideWith((ref) {
              final selectedDate = ref.watch(selectedTrainingDayProvider);
              return Stream<NutritionDayRecord>.value(
                _nutritionDayFor(selectedDate),
              );
            }),
            mealTypeListProvider.overrideWith(
              (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
            ),
          ],
          child: const PerenniaApp(),
        ),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(HomeScreen.trainingDomainBodyKey),
      );
      expect(find.text(today.storageValue), findsOneWidget);

      final segmentedButton = tester.widget<SegmentedButton<HomeDomain>>(
        find.byKey(HomeScreen.domainToggleKey),
      );
      expect(
        segmentedButton.segments.map((segment) => segment.value),
        <HomeDomain>[HomeDomain.training, HomeDomain.nutrition],
      );
    },
  );

  testWidgets('home renders state from controller-backed repository', (
    tester,
  ) async {
    final repository = StubHomeRepository(
      summary: HomeSummary(
        title: 'Training Day',
        selectedDate: TrainingDayDate(year: 2026, month: 6, day: 14),
        status: 'Controller state from repository',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          _homeNutritionDayOverride(),
          exerciseCatalogRepositoryProvider.overrideWith(
            (ref) => StubExerciseCatalogRepository(
              sections: _strengthCatalog(),
            ),
          ),
          homeRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const PerenniaApp(),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(HomeScreen.todayDestinationKey), findsOneWidget);
    expect(find.text('Controller state from repository'), findsOneWidget);
    expect(find.text('Start New Workout'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    expect(
      container.read(homeControllerProvider).value,
      HomeState(
        summary: HomeSummary(
          title: 'Training Day',
          selectedDate: TrainingDayDate(year: 2026, month: 6, day: 14),
          status: 'Controller state from repository',
        ),
      ),
    );
  });

  testWidgets('home day header navigates with arrows and swipe', (
    tester,
  ) async {
    const repository = _DateEchoHomeRepository();
    final today = TrainingDayDate.fromDateTime(DateTime.now());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          _homeNutritionDayOverride(),
          homeRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const PerenniaApp(),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text(today.storageValue), findsOneWidget);

    await tester.tap(find.byKey(HomeScreen.nextDayButtonKey));
    await tester.pumpAndSettle();
    expect(find.text(today.addDays(1).storageValue), findsOneWidget);

    await tester.fling(
      find.byKey(HomeScreen.dayHeaderKey),
      const Offset(320, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.text(today.storageValue), findsOneWidget);
  });

  testWidgets('home domain toggle swaps body while keeping the selected date', (
    tester,
  ) async {
    final today = TrainingDayDate.fromDateTime(DateTime.now());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          homeRepositoryProvider.overrideWith(
            (ref) => const _DateEchoHomeRepository(),
          ),
          homeNutritionDayProvider.overrideWith((ref) {
            final selectedDate = ref.watch(selectedTrainingDayProvider);
            return Stream<NutritionDayRecord>.value(
              _nutritionDayFor(selectedDate),
            );
          }),
          mealTypeListProvider.overrideWith(
            (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
          ),
        ],
        child: const PerenniaApp(),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(HomeScreen.trainingDomainBodyKey),
    );

    expect(find.byKey(HomeScreen.trainingDomainBodyKey), findsOneWidget);
    expect(find.byKey(HomeScreen.nutritionDomainBodyKey), findsNothing);
    expect(find.text(today.storageValue), findsOneWidget);

    await tester.tap(find.byKey(HomeScreen.nutritionDomainButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(HomeScreen.trainingDomainBodyKey), findsNothing);
    expect(find.byKey(HomeScreen.nutritionDomainBodyKey), findsOneWidget);
    expect(find.byKey(NutritionDayView.daySummaryKey), findsOneWidget);
    expect(find.text('Nutrition ${today.storageValue}'), findsOneWidget);

    await tester.tap(find.byKey(HomeScreen.trainingDomainButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(HomeScreen.trainingDomainBodyKey), findsOneWidget);
    expect(find.text(today.storageValue), findsOneWidget);
  });

  testWidgets('home shared date strip changes day without changing domain', (
    tester,
  ) async {
    final today = TrainingDayDate.fromDateTime(DateTime.now());
    final nextDay = today.addDays(1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          homeRepositoryProvider.overrideWith(
            (ref) => const _DateEchoHomeRepository(),
          ),
          homeNutritionDayProvider.overrideWith((ref) {
            final selectedDate = ref.watch(selectedTrainingDayProvider);
            return Stream<NutritionDayRecord>.value(
              _nutritionDayFor(selectedDate),
            );
          }),
          mealTypeListProvider.overrideWith(
            (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
          ),
        ],
        child: const PerenniaApp(),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(HomeScreen.trainingDomainBodyKey),
    );

    await tester.tap(find.byKey(HomeScreen.nutritionDomainButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('Nutrition ${today.storageValue}'), findsOneWidget);

    await tester.tap(find.byKey(HomeScreen.nextDayButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(HomeScreen.nutritionDomainBodyKey), findsOneWidget);
    expect(find.byKey(NutritionDayView.daySummaryKey), findsOneWidget);
    expect(find.text('Nutrition ${nextDay.storageValue}'), findsOneWidget);

    await tester.fling(
      find.byKey(HomeScreen.dayHeaderKey),
      const Offset(320, 0),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(HomeScreen.nutritionDomainBodyKey), findsOneWidget);
    expect(find.text('Nutrition ${today.storageValue}'), findsOneWidget);

    await tester.tap(find.byKey(HomeScreen.trainingDomainButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(HomeScreen.trainingDomainBodyKey), findsOneWidget);
    expect(find.text(today.storageValue), findsOneWidget);
  });

  testWidgets('home domain toggle meets accessibility guidelines', (
    tester,
  ) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            upNextFeatureRepositoryProvider.overrideWith(
              (ref) => const StubUpNextFeatureRepository(),
            ),
            settingsRepositoryProvider.overrideWith(
              (ref) => InMemorySettingsRepository(),
            ),
            homeRepositoryProvider.overrideWith(
              (ref) => const _DateEchoHomeRepository(),
            ),
            homeNutritionDayProvider.overrideWith((ref) {
              final selectedDate = ref.watch(selectedTrainingDayProvider);
              return Stream<NutritionDayRecord>.value(
                _nutritionDayFor(selectedDate),
              );
            }),
            mealTypeListProvider.overrideWith(
              (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
            ),
          ],
          child: MaterialApp(
            theme: theme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(HomeScreen.trainingDomainBodyKey),
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.tap(find.byKey(HomeScreen.nutritionDomainButtonKey));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('home nutrition start meal uses the shared selected date', (
    tester,
  ) async {
    final controller = _HomeStartMealNutritionController();
    final selectedDate = TrainingDayDate.fromDateTime(DateTime.now()).addDays(
      1,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          homeRepositoryProvider.overrideWith(
            (ref) => const _DateEchoHomeRepository(),
          ),
          homeNutritionDayProvider.overrideWith((ref) {
            final selectedDate = ref.watch(selectedTrainingDayProvider);
            return Stream<NutritionDayRecord>.value(
              _nutritionDayFor(selectedDate),
            );
          }),
          nutritionDayControllerProvider.overrideWith(() => controller),
          mealTypeListProvider.overrideWith(
            (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
          ),
        ],
        child: const PerenniaApp(),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(HomeScreen.trainingDomainBodyKey),
    );

    await tester.tap(find.byKey(HomeScreen.nextDayButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeScreen.nutritionDomainButtonKey));
    await tester.pumpAndSettle();

    final startMealButton = find.byKey(
      NutritionDayView.startMealButtonKey('meal-type-breakfast'),
    );
    await tester.scrollUntilVisible(
      startMealButton,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(startMealButton),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(startMealButton);
    await tester.pump();

    expect(
      controller.startedMealDates,
      <NutritionDayDate>[nutritionDayDateFromTrainingDay(selectedDate)],
    );
  });

  testWidgets('starting a workout opens the empty workout page', (
    tester,
  ) async {
    final repository = _StartWorkoutHomeRepository();
    addTearDown(repository.dispose);
    final expectedDate = TrainingDayDate.fromDateTime(DateTime.now());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          _homeNutritionDayOverride(),
          homeRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const PerenniaApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(HomeScreen.startWorkoutButtonKey));
    await tester.pumpAndSettle();

    expect(find.byType(WorkoutScreen), findsOneWidget);
    expect(find.text('No exercises logged yet'), findsOneWidget);
    expect(
        find.byKey(WorkoutScreen.finishButtonKey('workout-1')), findsOneWidget);
    expect(
      tester
          .getCenter(
            find.byKey(WorkoutScreen.addExerciseButtonKey('workout-1')),
          )
          .dy,
      lessThan(tester.getCenter(find.text('Exercises')).dy),
      reason: 'Add Exercise belongs in the always-visible workout header.',
    );
    expect(repository.startedDates, <TrainingDayDate>[expectedDate]);
  });

  testWidgets('home renders compact workout summary tiles', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          _homeNutritionDayOverride(),
          homeRepositoryProvider.overrideWith(
            (ref) => const _MultiSessionHomeRepository(),
          ),
        ],
        child: const PerenniaApp(),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(HomeScreen.sessionHeaderKey('morning')), findsOneWidget);
    expect(find.byKey(HomeScreen.sessionHeaderKey('evening')), findsOneWidget);
    expect(find.textContaining('Session'), findsNWidgets(2));
    expect(
      find.byKey(HomeScreen.addExerciseToWorkoutButtonKey('morning')),
      findsNothing,
    );
    expect(
      find.byKey(HomeScreen.openWorkoutButtonKey('morning')),
      findsOneWidget,
    );
  });

  testWidgets(
      'selecting an exercise row adds it and lands directly on the '
      'Exercise page', (tester) async {
    final repository = _AddExerciseHomeRepository();
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          _homeNutritionDayOverride(),
          exerciseCatalogRepositoryProvider.overrideWith(
            (ref) => StubExerciseCatalogRepository(
              sections: _strengthCatalog(),
            ),
          ),
          homeRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const PerenniaApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(HomeScreen.openWorkoutButtonKey('workout-1')));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(WorkoutScreen.addExerciseButtonKey('workout-1')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(
          ExerciseCatalogPicker.selectButtonKey(
            '01910000-0000-7000-8000-000000000101',
          ),
        ),
        matching: find.byIcon(Icons.add_circle_outline),
      ),
      findsNothing,
    );
    await tester.tap(
      find.byKey(
        ExerciseCatalogPicker.selectButtonKey(
          '01910000-0000-7000-8000-000000000101',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.addedExerciseIds, <String>[
      '01910000-0000-7000-8000-000000000101',
    ]);

    // One-step landing: the picker sheet is gone and the Exercise page for
    // the just-added exercise is already on screen — no second tap on the
    // WorkoutScreen card required.
    expect(find.byType(ExerciseCatalogPicker), findsNothing);
    expect(find.byType(ExercisePage), findsOneWidget);
    expect(find.byType(WorkoutScreen), findsNothing);

    final exercisePageRoute = ModalRoute.of(
      tester.element(find.byType(ExercisePage)),
    );
    expect(
      exercisePageRoute?.settings.name,
      '/exercise/workout-exercise-1',
    );

    // Back from the auto-landed Exercise page returns to the WorkoutScreen
    // (the workout that owns the just-added exercise), not Home.
    Navigator.of(tester.element(find.byType(ExercisePage))).pop();
    await tester.pumpAndSettle();

    expect(find.byType(ExercisePage), findsNothing);
    expect(find.byType(WorkoutScreen), findsOneWidget);
    expect(
      find.byKey(WorkoutScreen.openExerciseButtonKey('workout-exercise-1')),
      findsOneWidget,
    );
  });

  testWidgets(
      'a rapid double-tap on the same catalog row adds the exercise once '
      'and lands on one Exercise page', (tester) async {
    // Holds addExerciseToWorkout pending so a second tap can be delivered
    // while the first is still in flight, simulating a fast double-tap.
    final addExerciseGate = Completer<void>();
    final repository = _AddExerciseHomeRepository(
      addExerciseDelay: () => addExerciseGate.future,
    );
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          _homeNutritionDayOverride(),
          exerciseCatalogRepositoryProvider.overrideWith(
            (ref) => StubExerciseCatalogRepository(
              sections: _strengthCatalog(),
            ),
          ),
          homeRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const PerenniaApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(HomeScreen.openWorkoutButtonKey('workout-1')));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(WorkoutScreen.addExerciseButtonKey('workout-1')));
    await tester.pumpAndSettle();

    final selectButton = find.byKey(
      ExerciseCatalogPicker.selectButtonKey(
        '01910000-0000-7000-8000-000000000101',
      ),
    );

    // First tap starts addExerciseToWorkout, which is held pending by the
    // gate. Pump (not pumpAndSettle) so the picker sheet is still showing
    // when the second tap fires.
    await tester.tap(selectButton);
    await tester.pump();
    await tester.tap(selectButton);
    await tester.pump();

    // Release the gate: exactly one addExerciseToWorkout call should have
    // been in flight, regardless of the second tap.
    addExerciseGate.complete();
    await tester.pumpAndSettle();

    expect(repository.addedExerciseIds, <String>[
      '01910000-0000-7000-8000-000000000101',
    ]);
    expect(find.byType(ExercisePage), findsOneWidget);

    // Only one ExercisePage route was pushed: a single pop returns straight
    // to WorkoutScreen, not to a second stacked ExercisePage.
    Navigator.of(tester.element(find.byType(ExercisePage))).pop();
    await tester.pumpAndSettle();

    expect(find.byType(ExercisePage), findsNothing);
    expect(find.byType(WorkoutScreen), findsOneWidget);
  });

  testWidgets('workout page saves notes and exposes session actions', (
    tester,
  ) async {
    final repository = _WorkoutActionsHomeRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          _homeNutritionDayOverride(),
          homeRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const PerenniaApp(),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
        find.byKey(HomeScreen.copyWorkoutButtonKey('workout-1')), findsNothing);

    await tester.tap(find.byKey(HomeScreen.openWorkoutButtonKey('workout-1')));
    await tester.pumpAndSettle();

    expect(find.text('1h 35m'), findsOneWidget);
    expect(find.text('Heavy pulls'), findsNothing);
    expect(
      find.byKey(WorkoutScreen.notesButtonKey('workout-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(WorkoutScreen.optionsButtonKey('workout-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(WorkoutScreen.resumeButtonKey('workout-1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(WorkoutScreen.notesButtonKey('workout-1')));
    await tester.pumpAndSettle();

    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Heavy pulls'), findsOneWidget);

    await tester.enterText(
      find.byKey(WorkoutScreen.notesFieldKey('workout-1')),
      'Back-off work',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(
      find.byKey(WorkoutScreen.saveNotesButtonKey('workout-1')),
    );
    await tester.pumpAndSettle();

    expect(repository.commentUpdates, <String?>['Back-off work']);
  });

  testWidgets('workout options open start and finish time editors', (
    tester,
  ) async {
    final repository = _WorkoutActionsHomeRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          _homeNutritionDayOverride(),
          homeRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const PerenniaApp(),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(HomeScreen.openWorkoutButtonKey('workout-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(WorkoutScreen.optionsButtonKey('workout-1')));
    await tester.pumpAndSettle();

    expect(find.text('Edit start time'), findsOneWidget);
    expect(find.text('Edit finish time'), findsOneWidget);

    await tester.tap(
      find.byKey(WorkoutScreen.editStartTimeButtonKey('workout-1')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(WorkoutScreen.optionsButtonKey('workout-1')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(WorkoutScreen.editFinishTimeButtonKey('workout-1')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  });

  testWidgets('open workout options hide finish time editing', (
    tester,
  ) async {
    final repository = _FinishableWorkoutHomeRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          _homeNutritionDayOverride(),
          homeRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const PerenniaApp(),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(HomeScreen.openWorkoutButtonKey('workout-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(WorkoutScreen.optionsButtonKey('workout-1')));
    await tester.pumpAndSettle();

    expect(find.text('Edit start time'), findsOneWidget);
    expect(find.text('Edit finish time'), findsNothing);
  });

  testWidgets(
      'finishing a workout pops to Home and shows a Share action in the '
      'snackbar', (tester) async {
    final repository = _FinishableWorkoutHomeRepository();
    final copiedSummaries = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final arguments = call.arguments as Map<Object?, Object?>;
          copiedSummaries.add(arguments['text']! as String);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          _homeNutritionDayOverride(),
          homeRepositoryProvider.overrideWith((ref) => repository),
          templateDivergenceFeatureRepositoryProvider.overrideWith(
            (ref) => const _NoDivergenceRepository(),
          ),
        ],
        child: const PerenniaApp(),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(HomeScreen.openWorkoutButtonKey('workout-1')));
    await tester.pumpAndSettle();

    expect(find.byType(WorkoutScreen), findsOneWidget);
    expect(
      find.byKey(WorkoutScreen.finishButtonKey('workout-1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(WorkoutScreen.finishButtonKey('workout-1')));
    await tester.pumpAndSettle();

    expect(repository.finishedWorkoutIds, <String>['workout-1']);
    // Finish pops the WorkoutScreen back to Home.
    expect(find.byType(WorkoutScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);

    expect(find.text('Workout finished'), findsOneWidget);
    final shareActionFinder = find.descendant(
      of: find.byType(SnackBar),
      matching: find.widgetWithText(SnackBarAction, 'Share'),
    );
    expect(shareActionFinder, findsOneWidget);

    await tester.tap(shareActionFinder);
    await tester.pumpAndSettle();

    expect(copiedSummaries, <String>['Workout summary']);
    expect(find.text('Workout summary copied'), findsOneWidget);
  });

  testWidgets('finishing a zero-set workout pops to Home without error', (
    tester,
  ) async {
    final repository = _FinishableWorkoutHomeRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          _homeNutritionDayOverride(),
          homeRepositoryProvider.overrideWith((ref) => repository),
          templateDivergenceFeatureRepositoryProvider.overrideWith(
            (ref) => const _NoDivergenceRepository(),
          ),
        ],
        child: const PerenniaApp(),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(HomeScreen.openWorkoutButtonKey('workout-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(WorkoutScreen.exerciseCardKey('any')), findsNothing);
    expect(find.text('No exercises logged yet'), findsOneWidget);

    await tester.tap(find.byKey(WorkoutScreen.finishButtonKey('workout-1')));
    await tester.pumpAndSettle();

    expect(repository.finishedWorkoutIds, <String>['workout-1']);
    expect(tester.takeException(), isNull);
    expect(find.byType(WorkoutScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('workout notes screen deletes existing notes', (
    tester,
  ) async {
    final repository = _WorkoutActionsHomeRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          _homeNutritionDayOverride(),
          homeRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const PerenniaApp(),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(HomeScreen.openWorkoutButtonKey('workout-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(WorkoutScreen.notesButtonKey('workout-1')));
    await tester.pumpAndSettle();

    expect(find.text('Heavy pulls'), findsOneWidget);

    await tester.tap(
      find.byKey(WorkoutScreen.deleteNotesButtonKey('workout-1')),
    );
    await tester.pumpAndSettle();

    expect(repository.commentUpdates, <String?>[null]);
  });

  testWidgets('workout page removes and reorders exercise rows', (
    tester,
  ) async {
    final repository = _WorkoutExerciseManagementHomeRepository();
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          _homeNutritionDayOverride(),
          homeRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const PerenniaApp(),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(HomeScreen.openWorkoutButtonKey('workout-1')));
    await tester.pumpAndSettle();

    expect(find.text('Back Squat'), findsOneWidget);
    expect(find.text('2 sets'), findsOneWidget);
    expect(find.text('100 kg × 5 reps'), findsNothing);
    expect(find.text('105 kg × 5 reps'), findsNothing);
    expect(find.byIcon(Icons.link_off), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.link_off).first);
    await tester.pumpAndSettle();

    expect(repository.linkedWorkoutExerciseIds, <List<String>>[
      <String>['workout-exercise-squat', 'workout-exercise-row'],
    ]);
    expect(find.byIcon(Icons.link), findsOneWidget);
    expect(find.byIcon(Icons.link_off), findsOneWidget);

    await tester.tap(find.byIcon(Icons.link));
    await tester.pumpAndSettle();

    expect(repository.unlinkedWorkoutExerciseIds, <List<String>>[
      <String>['workout-exercise-squat', 'workout-exercise-row'],
    ]);
    expect(find.byIcon(Icons.link), findsNothing);
    expect(find.byIcon(Icons.link_off), findsNWidgets(2));

    expect(
      find.byKey(WorkoutScreen.exerciseDismissibleKey('workout-exercise-row')),
      findsOneWidget,
    );
    final initialDismissible = tester.widget<Dismissible>(
      find.byKey(WorkoutScreen.exerciseDismissibleKey('workout-exercise-row')),
    );
    expect(initialDismissible.direction, DismissDirection.startToEnd);
    expect(initialDismissible.background, isNotNull);
    expect(
      find.byKey(
        WorkoutScreen.reorderExerciseHandleKey('workout-exercise-curl'),
      ),
      findsOneWidget,
    );

    final cardFinder = find.byKey(
      WorkoutScreen.exerciseCardKey('workout-exercise-curl'),
    );
    final initialCard = tester.widget<Material>(cardFinder);
    final initialShape = initialCard.shape! as RoundedRectangleBorder;
    expect(initialShape.side.width, 1);

    final dragHandleGesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(
          WorkoutScreen.reorderExerciseHandleKey('workout-exercise-curl'),
        ),
      ),
    );
    await tester.pump();

    final armedCard = tester.widget<Material>(cardFinder);
    final armedShape = armedCard.shape! as RoundedRectangleBorder;
    expect(armedShape.side.width, 2);

    await dragHandleGesture.up();
    await tester.pumpAndSettle();

    final releasedCard = tester.widget<Material>(cardFinder);
    final releasedShape = releasedCard.shape! as RoundedRectangleBorder;
    expect(releasedShape.side.width, 1);

    final reorderableList = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    reorderableList.onReorderItem!(2, 0);
    await tester.pumpAndSettle();

    expect(repository.reorderedWorkoutExerciseIds, <List<String>>[
      <String>[
        'workout-exercise-curl',
        'workout-exercise-squat',
        'workout-exercise-row',
      ],
    ]);
    expect(find.text('Curl'), findsOneWidget);

    final dismissible = tester.widget<Dismissible>(
      find.byKey(WorkoutScreen.exerciseDismissibleKey('workout-exercise-row')),
    );
    final shouldDismiss = await dismissible.confirmDismiss!(
      DismissDirection.startToEnd,
    );
    await tester.pumpAndSettle();

    expect(shouldDismiss, isTrue);
    expect(repository.removedWorkoutExerciseIds, <String>[
      'workout-exercise-row',
    ]);
    expect(find.text('Row'), findsNothing);
    expect(find.text('Exercise removed'), findsOneWidget);
  });

  testWidgets('workout page tolerates an invalid Exercise Group color', (
    tester,
  ) async {
    final repository = _WorkoutExerciseManagementHomeRepository()
      ..exerciseGroupColorHex = 'not-a-color';
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          _homeNutritionDayOverride(),
          homeRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const PerenniaApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeScreen.openWorkoutButtonKey('workout-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.link_off).first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.link), findsOneWidget);
  });

  testWidgets('workout page reports a failed superset change', (
    tester,
  ) async {
    final repository = _WorkoutExerciseManagementHomeRepository()
      ..failSupersetChanges = true;
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          _homeNutritionDayOverride(),
          homeRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const PerenniaApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeScreen.openWorkoutButtonKey('workout-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.link_off).first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Could not update superset. Try again.'), findsOneWidget);
  });

  testWidgets('home scopes multi-session exercise logs by workout', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          _homeNutritionDayOverride(),
          homeRepositoryProvider.overrideWith(
            (ref) => const _MultiSessionHomeRepository(),
          ),
        ],
        child: const PerenniaApp(),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(HomeScreen.sessionHeaderKey('morning')), findsOneWidget);
    expect(find.byKey(HomeScreen.sessionHeaderKey('evening')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(HomeScreen.sessionBlockKey('morning')),
        matching: find.text('Morning Run'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(HomeScreen.sessionBlockKey('morning')),
        matching: find.text('Evening Squat'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(HomeScreen.sessionBlockKey('evening')),
        matching: find.text('Evening Squat'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(HomeScreen.sessionBlockKey('evening')),
        matching: find.text('Morning Run'),
      ),
      findsNothing,
    );
  });
}

class _StubSyncStatusController extends SyncStatusController {
  _StubSyncStatusController(this.status);

  final SyncStatusState status;

  @override
  Stream<SyncStatusState> build() => Stream<SyncStatusState>.value(status);
}

class _StubMetricsController extends MetricsController {
  @override
  Stream<MetricsState> build() {
    return Stream<MetricsState>.value(
      MetricsState(summaries: const <MetricSummary>[]),
    );
  }
}

/// A stub for the overflow-navigation smoke test: emits an empty derived
/// Protocol Day without ever touching the real repository/Drift streams
/// (mirrors protocols_day_view_test.dart's fake-controller pattern).
class _StubProtocolDayController extends ProtocolDayController {
  @override
  Stream<ProtocolDayState> build() {
    return Stream<ProtocolDayState>.value(
      ProtocolDayState(
        day: ProtocolDayRecord(
          localDate: const ProtocolDayDate(year: 2026, month: 6, day: 30),
          doses: <DoseRecord>[],
        ),
      ),
    );
  }

  @override
  Future<void> ensureOtcLibrarySeeded() async {}
}

class _StubNutritionDayController extends NutritionDayController {
  @override
  Stream<NutritionDayState> build() {
    final selectedDate = ref.watch(selectedNutritionDayProvider);
    return Stream<NutritionDayState>.value(
      NutritionDayState(
        day: NutritionDayRecord(
          localDate: selectedDate,
          meals: <NutritionDayMealRecord>[],
        ),
      ),
    );
  }
}

class _StubRoutinePlanListController extends RoutinePlanListController {
  @override
  Stream<RoutinePlanListSnapshot> build() {
    return Stream<RoutinePlanListSnapshot>.value(
      RoutinePlanListSnapshot.empty,
    );
  }
}

/// An in-memory `ProtocolsLockStore` fake that never reports a configured
/// lock — keeps `ProtocolsLockGate`/`ProtocolsLockSettingsTile` off
/// the real secure-storage plugin channel in widget tests that don't care
/// about the lock itself.
class _NoLockStore implements ProtocolsLockStore {
  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<void> setEnabled(bool enabled) async {}

  @override
  Future<String?> readPinHash() async => null;

  @override
  Future<void> writePinHash(String hash) async {}

  @override
  Future<void> clearPin() async {}
}

class _DeferredSettingsRepository implements SettingsRepository {
  final completer = Completer<AppSettings>();

  @override
  Future<AppSettings> load() => completer.future;

  @override
  Future<void> save(AppSettings _) async {}
}

class _DeferredAuthRepository extends InMemoryAuthRepository {
  final completer = Completer<AuthState>();

  @override
  Future<AuthState> load() => completer.future;
}

class _FailingStartHomeRepository extends StubHomeRepository {
  @override
  Future<String> startNewWorkout(TrainingDayDate localDate) async {
    throw StateError('Database unavailable');
  }
}

class _FakeClientCrashReporter implements ClientCrashReporter {
  final enabledValues = <bool>[];

  @override
  Future<void> setEnabled(bool enabled) async {
    enabledValues.add(enabled);
  }

  @override
  Future<void> captureException(
    Object throwable,
    StackTrace stackTrace, {
    Hint? hint,
  }) async {}

  @override
  Future<void> addBreadcrumb(Breadcrumb breadcrumb, {Hint? hint}) async {}
}

abstract class _HomeRepositoryTestDefaults implements HomeRepository {
  const _HomeRepositoryTestDefaults();

  @override
  Stream<HomeWorkoutSummary?> watchWorkout(String workoutId) {
    return Stream<HomeWorkoutSummary?>.value(null);
  }

  @override
  Future<void> finishWorkout(String workoutId) async {}

  @override
  Future<void> resumeWorkout(String workoutId) async {}

  @override
  Future<void> deleteWorkout(String workoutId) async {}

  @override
  Future<void> removeExerciseFromWorkout({
    required String workoutExerciseId,
  }) async {}

  @override
  Future<void> reorderWorkoutExercises({
    required String workoutId,
    required List<String> orderedWorkoutExerciseIds,
  }) async {}

  @override
  Future<void> linkWorkoutExercisesAsSuperset({
    required String workoutId,
    required String firstWorkoutExerciseId,
    required String secondWorkoutExerciseId,
  }) async {}

  @override
  Future<void> unlinkWorkoutExercisesFromSuperset({
    required String workoutId,
    required String firstWorkoutExerciseId,
    required String secondWorkoutExerciseId,
  }) async {}

  @override
  Future<void> updateWorkoutStartedAt({
    required String workoutId,
    required DateTime startedAt,
    required TrainingDayDate localDate,
  }) async {}

  @override
  Future<void> updateWorkoutEndedAt({
    required String workoutId,
    required DateTime endedAt,
  }) async {}
}

class _ErrorHomeRepository extends _HomeRepositoryTestDefaults {
  const _ErrorHomeRepository();

  @override
  Stream<HomeSummary> watchTrainingDay(TrainingDayDate localDate) {
    return Stream<HomeSummary>.error(StateError('Training Day unavailable'));
  }

  @override
  Future<String> startNewWorkout(TrainingDayDate localDate) async {
    throw StateError('Training Day unavailable');
  }

  @override
  Future<String> addExerciseToWorkout({
    required String workoutId,
    required String exerciseId,
  }) async {
    throw StateError('Training Day unavailable');
  }

  @override
  Future<String> copyWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {
    throw StateError('Training Day unavailable');
  }

  @override
  Future<void> moveWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {
    throw StateError('Training Day unavailable');
  }

  @override
  Future<String> shareWorkout(String workoutId) async {
    throw StateError('Training Day unavailable');
  }

  @override
  Future<void> updateWorkoutComment({
    required String workoutId,
    String? comment,
  }) async {
    throw StateError('Training Day unavailable');
  }

  @override
  Future<void> logDefaultWeightRepsSet() async {
    throw StateError('Training Day unavailable');
  }
}

class _LoadingHomeRepository extends _HomeRepositoryTestDefaults {
  const _LoadingHomeRepository();

  @override
  Stream<HomeSummary> watchTrainingDay(TrainingDayDate localDate) {
    return const Stream<HomeSummary>.empty();
  }

  @override
  Future<String> startNewWorkout(TrainingDayDate localDate) async {
    return 'workout-loading';
  }

  @override
  Future<String> addExerciseToWorkout({
    required String workoutId,
    required String exerciseId,
  }) async {
    return 'workout-exercise-loading';
  }

  @override
  Future<String> copyWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {
    return 'workout-copy-loading';
  }

  @override
  Future<void> moveWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {}

  @override
  Future<String> shareWorkout(String workoutId) async => 'Shared workout';

  @override
  Future<void> updateWorkoutComment({
    required String workoutId,
    String? comment,
  }) async {}

  @override
  Future<void> logDefaultWeightRepsSet() async {}
}

class _ScrollableHomeRepository extends _HomeRepositoryTestDefaults {
  const _ScrollableHomeRepository();

  @override
  Stream<HomeSummary> watchTrainingDay(TrainingDayDate localDate) {
    return Stream<HomeSummary>.value(
      HomeSummary(
        title: 'Training Day',
        selectedDate: localDate,
        status: 'Scrollable Training Day',
        workouts: List<HomeWorkoutSummary>.generate(
          20,
          (index) => HomeWorkoutSummary(
            id: 'workout-$index',
            startedAt: DateTime.utc(2026, 7, 11, index % 24),
            localDate: localDate,
            endedAt: DateTime.utc(2026, 7, 11, index % 24)
                .add(const Duration(minutes: 30)),
          ),
        ),
      ),
    );
  }

  @override
  Future<String> startNewWorkout(TrainingDayDate localDate) async {
    return 'workout-new';
  }

  @override
  Future<String> addExerciseToWorkout({
    required String workoutId,
    required String exerciseId,
  }) async {
    return 'workout-exercise-new';
  }

  @override
  Future<String> copyWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async =>
      'workout-copy';

  @override
  Future<void> moveWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {}

  @override
  Future<String> shareWorkout(String workoutId) async => 'Shared workout';

  @override
  Future<void> updateWorkoutComment({
    required String workoutId,
    String? comment,
  }) async {}

  @override
  Future<void> logDefaultWeightRepsSet() async {}
}

class _DateEchoHomeRepository extends _HomeRepositoryTestDefaults {
  const _DateEchoHomeRepository();

  @override
  Stream<HomeSummary> watchTrainingDay(TrainingDayDate localDate) {
    return Stream<HomeSummary>.value(
      HomeSummary(
        title: 'Training Day',
        selectedDate: localDate,
        status: localDate.storageValue,
      ),
    );
  }

  @override
  Future<String> startNewWorkout(TrainingDayDate localDate) async {
    return 'workout-${localDate.storageValue}';
  }

  @override
  Future<String> addExerciseToWorkout({
    required String workoutId,
    required String exerciseId,
  }) async {
    return 'workout-exercise-$exerciseId';
  }

  @override
  Future<void> updateWorkoutComment({
    required String workoutId,
    String? comment,
  }) async {}

  @override
  Future<void> updateWorkoutStartedAt({
    required String workoutId,
    required DateTime startedAt,
    required TrainingDayDate localDate,
  }) async {}

  @override
  Future<void> updateWorkoutEndedAt({
    required String workoutId,
    required DateTime endedAt,
  }) async {}

  @override
  Future<String> copyWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {
    return 'copy-$workoutId';
  }

  @override
  Future<void> moveWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {}

  @override
  Future<String> shareWorkout(String workoutId) async {
    return 'Workout summary';
  }

  @override
  Future<void> logDefaultWeightRepsSet() async {}
}

class _StartWorkoutHomeRepository extends _HomeRepositoryTestDefaults {
  _StartWorkoutHomeRepository();

  final _controller = StreamController<HomeSummary>.broadcast();
  final startedDates = <TrainingDayDate>[];
  final _workouts = <HomeWorkoutSummary>[];

  @override
  Stream<HomeSummary> watchTrainingDay(TrainingDayDate localDate) {
    Future<void>.microtask(() {
      if (!_controller.isClosed) {
        _controller.add(_emptyDay(localDate));
      }
    });
    return _controller.stream;
  }

  @override
  Stream<HomeWorkoutSummary?> watchWorkout(String workoutId) {
    final workout = _workouts.where((row) => row.id == workoutId).firstOrNull;
    return Stream<HomeWorkoutSummary?>.value(workout);
  }

  @override
  Future<String> startNewWorkout(TrainingDayDate localDate) async {
    startedDates.add(localDate);
    final workoutId = 'workout-${startedDates.length}';
    _workouts.add(
      HomeWorkoutSummary(
        id: workoutId,
        startedAt: localDate
            .toLocalDateTime()
            .add(Duration(hours: 6 + startedDates.length)),
      ),
    );
    _controller.add(
      HomeSummary(
        title: 'Training Day',
        selectedDate: localDate,
        status: 'Empty exercise log',
        workouts: List<HomeWorkoutSummary>.unmodifiable(_workouts),
      ),
    );
    return workoutId;
  }

  @override
  Future<String> addExerciseToWorkout({
    required String workoutId,
    required String exerciseId,
  }) async {
    return 'workout-exercise-$exerciseId';
  }

  @override
  Future<void> updateWorkoutComment({
    required String workoutId,
    String? comment,
  }) async {}

  @override
  Future<String> copyWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {
    return 'copy-$workoutId';
  }

  @override
  Future<void> moveWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {}

  @override
  Future<String> shareWorkout(String workoutId) async {
    return 'Workout summary';
  }

  @override
  Future<void> logDefaultWeightRepsSet() async {}

  Future<void> dispose() => _controller.close();

  HomeSummary _emptyDay(TrainingDayDate localDate) {
    return HomeSummary(
      title: 'Training Day',
      selectedDate: localDate,
      status: 'No workout started',
    );
  }
}

class _AddExerciseHomeRepository extends _HomeRepositoryTestDefaults {
  _AddExerciseHomeRepository({this.addExerciseDelay});

  /// Optional artificial delay before `addExerciseToWorkout` resolves, so a
  /// test can interleave a second tap within the pending window (simulating
  /// a rapid double-tap on the same catalog row).
  final Future<void> Function()? addExerciseDelay;

  final _controller = StreamController<HomeSummary>.broadcast();
  final addedExerciseIds = <String>[];
  HomeSummary? _latestSummary;

  @override
  Stream<HomeSummary> watchTrainingDay(TrainingDayDate localDate) {
    Future<void>.microtask(() {
      if (!_controller.isClosed) {
        _emit(_summary(localDate));
      }
    });
    return _controller.stream;
  }

  @override
  Stream<HomeWorkoutSummary?> watchWorkout(String workoutId) {
    Future<void>.microtask(() {
      if (_controller.isClosed) {
        return;
      }
      _emit(
        _latestSummary ??
            _summary(const TrainingDayDate(year: 2026, month: 6, day: 14)),
      );
    });
    return _controller.stream.map(
      (summary) =>
          summary.workouts.where((row) => row.id == workoutId).firstOrNull,
    );
  }

  @override
  Future<String> startNewWorkout(TrainingDayDate localDate) async {
    return 'workout-1';
  }

  @override
  Future<String> addExerciseToWorkout({
    required String workoutId,
    required String exerciseId,
  }) async {
    final delay = addExerciseDelay;
    if (delay != null) {
      await delay();
    }
    addedExerciseIds.add(exerciseId);
    _emit(
      _summary(
        const TrainingDayDate(year: 2026, month: 6, day: 14),
        workoutExercises: <HomeWorkoutExerciseSummary>[
          HomeWorkoutExerciseSummary(
            id: 'workout-exercise-1',
            workoutId: 'workout-1',
            exerciseId: exerciseId,
            name: 'Barbell Squat',
            type: ExerciseType(
              const <DimensionId>[DimensionId.load, DimensionId.reps],
            ),
          ),
        ],
      ),
    );
    return 'workout-exercise-1';
  }

  @override
  Future<void> updateWorkoutComment({
    required String workoutId,
    String? comment,
  }) async {}

  @override
  Future<String> copyWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {
    return 'copy-$workoutId';
  }

  @override
  Future<void> moveWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {}

  @override
  Future<String> shareWorkout(String workoutId) async {
    return 'Workout summary';
  }

  @override
  Future<void> logDefaultWeightRepsSet() async {}

  Future<void> dispose() => _controller.close();

  void _emit(HomeSummary summary) {
    _latestSummary = summary;
    _controller.add(summary);
  }

  HomeSummary _summary(
    TrainingDayDate localDate, {
    List<HomeWorkoutExerciseSummary> workoutExercises =
        const <HomeWorkoutExerciseSummary>[],
  }) {
    return HomeSummary(
      title: 'Training Day',
      selectedDate: localDate,
      status: workoutExercises.isEmpty ? 'Empty exercise log' : 'Ready to log',
      workouts: <HomeWorkoutSummary>[
        HomeWorkoutSummary(
          id: 'workout-1',
          startedAt: localDate.toLocalDateTime(),
          workoutExercises: workoutExercises,
        ),
      ],
      workoutExercises: workoutExercises,
    );
  }
}

class _WorkoutActionsHomeRepository extends _HomeRepositoryTestDefaults {
  final commentUpdates = <String?>[];

  HomeWorkoutSummary get _workout => HomeWorkoutSummary(
        id: 'workout-1',
        startedAt: DateTime.utc(2026, 6, 14, 8),
        endedAt: DateTime.utc(2026, 6, 14, 9, 35),
        comment: 'Heavy pulls',
      );

  @override
  Stream<HomeSummary> watchTrainingDay(TrainingDayDate localDate) {
    return Stream<HomeSummary>.value(
      HomeSummary(
        title: 'Training Day',
        selectedDate: localDate,
        status: 'Ready to log',
        workouts: <HomeWorkoutSummary>[_workout],
      ),
    );
  }

  @override
  Stream<HomeWorkoutSummary?> watchWorkout(String workoutId) {
    return Stream<HomeWorkoutSummary?>.value(
      workoutId == _workout.id ? _workout : null,
    );
  }

  @override
  Future<String> startNewWorkout(TrainingDayDate localDate) async {
    return 'workout-1';
  }

  @override
  Future<String> addExerciseToWorkout({
    required String workoutId,
    required String exerciseId,
  }) async {
    return 'workout-exercise-$exerciseId';
  }

  @override
  Future<void> updateWorkoutComment({
    required String workoutId,
    String? comment,
  }) async {
    commentUpdates.add(comment);
  }

  @override
  Future<String> copyWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {
    return 'copy-$workoutId';
  }

  @override
  Future<void> moveWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {}

  @override
  Future<String> shareWorkout(String workoutId) async {
    return 'Workout summary';
  }

  @override
  Future<void> logDefaultWeightRepsSet() async {}
}

/// An open, zero-set workout used to exercise the Finish flow:
/// popping to Home, the Share snackbar action, and the zero-set finish path.
class _FinishableWorkoutHomeRepository extends _HomeRepositoryTestDefaults {
  final finishedWorkoutIds = <String>[];

  HomeWorkoutSummary get _workout => HomeWorkoutSummary(
        id: 'workout-1',
        startedAt: DateTime.utc(2026, 6, 14, 8),
      );

  @override
  Stream<HomeSummary> watchTrainingDay(TrainingDayDate localDate) {
    return Stream<HomeSummary>.value(
      HomeSummary(
        title: 'Training Day',
        selectedDate: localDate,
        status: 'Ready to log',
        workouts: <HomeWorkoutSummary>[_workout],
      ),
    );
  }

  @override
  Stream<HomeWorkoutSummary?> watchWorkout(String workoutId) {
    return Stream<HomeWorkoutSummary?>.value(
      workoutId == _workout.id ? _workout : null,
    );
  }

  @override
  Future<String> startNewWorkout(TrainingDayDate localDate) async {
    return 'workout-1';
  }

  @override
  Future<String> addExerciseToWorkout({
    required String workoutId,
    required String exerciseId,
  }) async {
    return 'workout-exercise-$exerciseId';
  }

  @override
  Future<void> updateWorkoutComment({
    required String workoutId,
    String? comment,
  }) async {}

  @override
  Future<void> finishWorkout(String workoutId) async {
    finishedWorkoutIds.add(workoutId);
  }

  @override
  Future<String> copyWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {
    return 'copy-$workoutId';
  }

  @override
  Future<void> moveWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {}

  @override
  Future<String> shareWorkout(String workoutId) async {
    return 'Workout summary';
  }

  @override
  Future<void> logDefaultWeightRepsSet() async {}
}

/// Always reports "not linked" — keeps the Finish flow in these tests from
/// reaching the real Drift-backed default provider.
class _NoDivergenceRepository implements TemplateDivergenceFeatureRepository {
  const _NoDivergenceRepository();

  @override
  Future<TemplateDivergenceSummary?> summaryForWorkout(String workoutId) {
    return Future<TemplateDivergenceSummary?>.value();
  }

  @override
  Future<TemplateUpdateFromWorkoutResult?> updateTemplateFromWorkout(
    String workoutId,
  ) {
    return Future<TemplateUpdateFromWorkoutResult?>.value();
  }
}

class _WorkoutExerciseManagementHomeRepository
    extends _HomeRepositoryTestDefaults {
  _WorkoutExerciseManagementHomeRepository();

  final _controller = StreamController<HomeSummary>.broadcast();
  final removedWorkoutExerciseIds = <String>[];
  final reorderedWorkoutExerciseIds = <List<String>>[];
  final linkedWorkoutExerciseIds = <List<String>>[];
  final unlinkedWorkoutExerciseIds = <List<String>>[];
  final _exerciseGroups = <HomeExerciseGroupSummary>[];
  String exerciseGroupColorHex = '#2F6FED';
  bool failSupersetChanges = false;
  final _localDate = const TrainingDayDate(year: 2026, month: 6, day: 14);
  late List<HomeWorkoutExerciseSummary> _workoutExercises =
      <HomeWorkoutExerciseSummary>[
    _workoutExercise(
      id: 'workout-exercise-squat',
      exerciseId: 'squat',
      name: 'Back Squat',
      sets: const <HomeSetSummary>[
        HomeSetSummary(
          id: 'squat-set-1',
          description: 'Back Squat - 100 kg × 5 reps',
          isCompleted: true,
        ),
        HomeSetSummary(
          id: 'squat-set-2',
          description: 'Back Squat - 105 kg × 5 reps',
          isCompleted: true,
        ),
      ],
    ),
    _workoutExercise(
      id: 'workout-exercise-row',
      exerciseId: 'row',
      name: 'Row',
    ),
    _workoutExercise(
      id: 'workout-exercise-curl',
      exerciseId: 'curl',
      name: 'Curl',
    ),
  ];

  @override
  Stream<HomeSummary> watchTrainingDay(TrainingDayDate localDate) {
    Future<void>.microtask(() {
      if (!_controller.isClosed) {
        _emit();
      }
    });
    return _controller.stream;
  }

  @override
  Stream<HomeWorkoutSummary?> watchWorkout(String workoutId) {
    Future<void>.microtask(() {
      if (!_controller.isClosed) {
        _emit();
      }
    });
    return _controller.stream.map(
      (summary) => summary.workouts
          .where((workout) => workout.id == workoutId)
          .firstOrNull,
    );
  }

  @override
  Future<String> startNewWorkout(TrainingDayDate localDate) async {
    return 'workout-1';
  }

  @override
  Future<String> addExerciseToWorkout({
    required String workoutId,
    required String exerciseId,
  }) async {
    return 'workout-exercise-$exerciseId';
  }

  @override
  Future<void> removeExerciseFromWorkout({
    required String workoutExerciseId,
  }) async {
    removedWorkoutExerciseIds.add(workoutExerciseId);
    _workoutExercises = _workoutExercises
        .where((exercise) => exercise.id != workoutExerciseId)
        .toList(growable: false);
    _emit();
  }

  @override
  Future<void> reorderWorkoutExercises({
    required String workoutId,
    required List<String> orderedWorkoutExerciseIds,
  }) async {
    reorderedWorkoutExerciseIds.add(
      List<String>.unmodifiable(orderedWorkoutExerciseIds),
    );
    final byId = <String, HomeWorkoutExerciseSummary>{
      for (final exercise in _workoutExercises) exercise.id: exercise,
    };
    _workoutExercises = <HomeWorkoutExerciseSummary>[
      for (final id in orderedWorkoutExerciseIds) byId[id]!,
    ];
    _emit();
  }

  @override
  Future<void> linkWorkoutExercisesAsSuperset({
    required String workoutId,
    required String firstWorkoutExerciseId,
    required String secondWorkoutExerciseId,
  }) async {
    if (failSupersetChanges) {
      throw StateError('stale adjacent exercises');
    }
    linkedWorkoutExerciseIds.add(
      <String>[firstWorkoutExerciseId, secondWorkoutExerciseId],
    );
    _exerciseGroups
      ..clear()
      ..add(
        HomeExerciseGroupSummary(
          id: 'group-1',
          name: 'Superset 1',
          colorHex: exerciseGroupColorHex,
          workoutExerciseIds: <String>[
            firstWorkoutExerciseId,
            secondWorkoutExerciseId,
          ],
        ),
      );
    _emit();
  }

  @override
  Future<void> unlinkWorkoutExercisesFromSuperset({
    required String workoutId,
    required String firstWorkoutExerciseId,
    required String secondWorkoutExerciseId,
  }) async {
    if (failSupersetChanges) {
      throw StateError('stale adjacent exercises');
    }
    unlinkedWorkoutExerciseIds.add(
      <String>[firstWorkoutExerciseId, secondWorkoutExerciseId],
    );
    _exerciseGroups.clear();
    _emit();
  }

  @override
  Future<void> updateWorkoutComment({
    required String workoutId,
    String? comment,
  }) async {}

  @override
  Future<String> copyWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {
    return 'copy-$workoutId';
  }

  @override
  Future<void> moveWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {}

  @override
  Future<String> shareWorkout(String workoutId) async {
    return 'Workout summary';
  }

  @override
  Future<void> logDefaultWeightRepsSet() async {}

  Future<void> dispose() => _controller.close();

  void _emit() {
    _controller.add(
      HomeSummary(
        title: 'Training Day',
        selectedDate: _localDate,
        status: 'Ready to log',
        workouts: <HomeWorkoutSummary>[
          HomeWorkoutSummary(
            id: 'workout-1',
            startedAt: DateTime.utc(2026, 6, 14, 8),
            workoutExercises: List<HomeWorkoutExerciseSummary>.unmodifiable(
              _workoutExercises,
            ),
            exerciseGroups: List<HomeExerciseGroupSummary>.unmodifiable(
              _exerciseGroups,
            ),
          ),
        ],
        workoutExercises: List<HomeWorkoutExerciseSummary>.unmodifiable(
          _workoutExercises,
        ),
      ),
    );
  }

  static HomeWorkoutExerciseSummary _workoutExercise({
    required String id,
    required String exerciseId,
    required String name,
    List<HomeSetSummary> sets = const <HomeSetSummary>[],
  }) {
    return HomeWorkoutExerciseSummary(
      id: id,
      workoutId: 'workout-1',
      exerciseId: exerciseId,
      name: name,
      type: ExerciseType(
        const <DimensionId>[DimensionId.load, DimensionId.reps],
      ),
      sets: sets,
    );
  }
}

class _MultiSessionHomeRepository extends _HomeRepositoryTestDefaults {
  const _MultiSessionHomeRepository();

  @override
  Stream<HomeSummary> watchTrainingDay(TrainingDayDate localDate) {
    final run = HomeWorkoutExerciseSummary(
      id: 'morning-run',
      workoutId: 'morning',
      exerciseId: 'run',
      name: 'Morning Run',
      type: ExerciseType(
        const <DimensionId>[DimensionId.distance, DimensionId.duration],
      ),
    );
    final squat = HomeWorkoutExerciseSummary(
      id: 'evening-squat',
      workoutId: 'evening',
      exerciseId: 'squat',
      name: 'Evening Squat',
      type: ExerciseType(
        const <DimensionId>[DimensionId.load, DimensionId.reps],
      ),
    );
    return Stream<HomeSummary>.value(
      HomeSummary(
        title: 'Training Day',
        selectedDate: localDate,
        status: 'Ready to log',
        workouts: <HomeWorkoutSummary>[
          HomeWorkoutSummary(
            id: 'morning',
            startedAt: DateTime(2026, 6, 14, 7),
            workoutExercises: <HomeWorkoutExerciseSummary>[run],
          ),
          HomeWorkoutSummary(
            id: 'evening',
            startedAt: DateTime(2026, 6, 14, 18),
            workoutExercises: <HomeWorkoutExerciseSummary>[squat],
          ),
        ],
        workoutExercises: <HomeWorkoutExerciseSummary>[run, squat],
      ),
    );
  }

  @override
  Future<String> startNewWorkout(TrainingDayDate localDate) async {
    return 'new-workout';
  }

  @override
  Future<String> addExerciseToWorkout({
    required String workoutId,
    required String exerciseId,
  }) async {
    return '$workoutId-$exerciseId';
  }

  @override
  Future<void> updateWorkoutComment({
    required String workoutId,
    String? comment,
  }) async {}

  @override
  Future<String> copyWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {
    return 'copy-$workoutId';
  }

  @override
  Future<void> moveWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) async {}

  @override
  Future<String> shareWorkout(String workoutId) async {
    return 'Workout summary';
  }

  @override
  Future<void> logDefaultWeightRepsSet() async {}
}

class _HomeStartMealNutritionController extends NutritionDayController {
  final startedMealDates = <NutritionDayDate>[];

  @override
  Stream<NutritionDayState> build() {
    const localDate = NutritionDayDate(year: 1970, month: 1, day: 1);
    return Stream<NutritionDayState>.value(
      NutritionDayState(
        day: NutritionDayRecord(
          localDate: localDate,
          meals: <NutritionDayMealRecord>[],
        ),
      ),
    );
  }

  @override
  Future<String> startMeal({
    required MealTypeRecord mealType,
    DateTime? startedAt,
    NutritionDayDate? localDate,
  }) async {
    startedMealDates.add(localDate!);
    return 'created-meal-id';
  }
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 20,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  final visibleText = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data)
      .whereType<String>()
      .join(', ');
  fail('Could not find $finder. Visible text: $visibleText');
}

Future<void> _disposeAppShellWidgetTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 5; i += 1) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
}

Future<void> _openAccountAndAppSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(HomeScreen.accountAndAppButtonKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(HomeScreen.accountAndAppSettingsKey));
  await tester.pumpAndSettle();
}

Override _homeNutritionDayOverride({
  NutritionDayRecord Function(TrainingDayDate localDate)? dayFor,
}) {
  return homeNutritionDayProvider.overrideWith((ref) {
    final selectedDate = ref.watch(selectedTrainingDayProvider);
    return Stream<NutritionDayRecord>.value(
      (dayFor ?? _nutritionDayFor)(selectedDate),
    );
  });
}

Override _disabledSyncCoordinatorOverride() {
  return syncCoordinatorProvider.overrideWith(
    (ref) => SyncCoordinator(
      loadSession: () async => null,
      loadDeviceId: () async => 'test-device',
      runCycle: ({
        required session,
        required deviceId,
      }) async =>
          SyncCycleResult.skipped,
    ),
  );
}

NutritionDayRecord _nutritionDayFor(TrainingDayDate localDate) {
  final nutritionDate = NutritionDayDate(
    year: localDate.year,
    month: localDate.month,
    day: localDate.day,
  );
  final startedAt = nutritionDate.toLocalDateTime().add(
        const Duration(hours: 8),
      );

  return NutritionDayRecord(
    localDate: nutritionDate,
    meals: [
      NutritionDayMealRecord(
        meal: MealRecord(
          id: 'meal-${nutritionDate.storageValue}',
          mealType: 'Nutrition ${nutritionDate.storageValue}',
          startedAt: startedAt,
          timezone: 'Australia/Brisbane',
          localDate: nutritionDate,
          updatedAt: startedAt,
        ),
        entries: const <FoodEntryRecord>[],
      ),
    ],
  );
}

List<MealTypeRecord> _mealTypes() {
  return <MealTypeRecord>[
    MealTypeRecord(
      id: 'meal-type-breakfast',
      name: 'Breakfast',
      sortOrder: 0,
      updatedAt: DateTime.utc(2026, 6, 26),
    ),
  ];
}

List<ExerciseCatalogSectionRecord> _strengthCatalog() {
  const categoryId = '01910000-0000-7000-8000-000000000001';

  return <ExerciseCatalogSectionRecord>[
    ExerciseCatalogSectionRecord(
      category: ExerciseCategoryRecord(
        id: categoryId,
        name: 'Strength',
        sortOrder: 0,
        colorHex: '#2F6FED',
        updatedAt: DateTime.utc(2026),
      ),
      exercises: <ExerciseRecord>[
        ExerciseRecord(
          id: '01910000-0000-7000-8000-000000000101',
          origin: ExerciseLibraryOrigin.platform,
          name: 'Barbell Squat',
          type: ExerciseType(<DimensionId>[
            DimensionId.load,
            DimensionId.reps,
          ]),
          defaultLoadUnit: TrainingUnit.kilogram,
          loadMode: ExerciseLoadMode.added,
          recordProfile: RecordProfile.repMax,
          categoryId: categoryId,
          notes: null,
          isFavorite: false,
          updatedAt: DateTime.utc(2026),
        ),
      ],
    ),
  ];
}

class _EmptyAppShellExerciseSeedSource implements PlatformExerciseSeedSource {
  const _EmptyAppShellExerciseSeedSource();

  @override
  Future<PlatformExerciseSeed> load() async {
    return const PlatformExerciseSeed(
      categories: <SeedExerciseCategory>[],
      exercises: <SeedExercise>[],
    );
  }
}
