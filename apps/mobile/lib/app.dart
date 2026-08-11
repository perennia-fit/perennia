import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import 'features/activity/widgets/activity_feed_screen.dart';
import 'features/auth/repositories/auth_repository.dart';
import 'features/auth/widgets/sign_in_screen.dart';
import 'features/body_tracker/widgets/body_tracker_screen.dart';
import 'features/catalog/repositories/exercise_catalog_repository.dart';
import 'features/home/repositories/home_repository.dart';
import 'features/home/services/workout_auto_finish_service.dart';
import 'features/home/widgets/home_screen.dart';
import 'features/metrics/widgets/metrics_screen.dart';
import 'features/nutrition/widgets/nutrition_day_view.dart';
import 'features/protocols/widgets/compound_list_screen.dart';
import 'features/protocols/widgets/protocols_day_view.dart';
import 'features/protocols/widgets/protocols_lock_screen.dart';
import 'features/routine_plans/repositories/routine_plan_feature_repository.dart';
import 'features/routine_plans/widgets/routine_plan_editor_screen.dart';
import 'features/routine_plans/widgets/routine_plan_list_screen.dart';
import 'features/template_picker/repositories/template_picker_feature_repository.dart';
import 'features/up_next/repositories/up_next_feature_repository.dart';
import 'app_navigation.dart';
import 'data/repositories/training_repositories.dart';
import 'features/settings/repositories/settings_repository.dart';
import 'features/settings/services/client_crash_reporting.dart';
import 'features/settings/services/keep_screen_awake.dart';
import 'features/settings/widgets/settings_screen.dart';
import 'features/sync/services/sync_coordinator.dart';
import 'features/sync/services/sync_providers.dart';
import 'features/training/services/timer_notification_router.dart';
import 'features/workout_templates/repositories/workout_template_feature_repository.dart';
import 'features/workout_templates/widgets/workout_template_editor_screen.dart';
import 'features/workout_templates/widgets/workout_template_list_screen.dart';
import 'l10n/l10n.dart';
import 'theme/theme.dart';

class PerenniaRoot extends StatelessWidget {
  const PerenniaRoot({
    super.key,
    this.exerciseCatalogRepository,
    this.authRepository,
    this.homeRepository,
    this.upNextFeatureRepository,
    this.templatePickerRepository,
    this.routinePlanRepository,
    this.workoutTemplateRepository,
    this.settingsRepository,
    this.extraOverrides = const <Override>[],
  });

  final ExerciseCatalogRepository? exerciseCatalogRepository;
  final AuthRepository? authRepository;
  final HomeRepository? homeRepository;
  final UpNextFeatureRepository? upNextFeatureRepository;
  final TemplatePickerFeatureRepository? templatePickerRepository;
  final RoutinePlanFeatureRepository? routinePlanRepository;
  final WorkoutTemplateFeatureRepository? workoutTemplateRepository;
  final SettingsRepository? settingsRepository;
  final List<Override> extraOverrides;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        ...extraOverrides,
        if (exerciseCatalogRepository != null)
          exerciseCatalogRepositoryProvider.overrideWith(
            (ref) => exerciseCatalogRepository!,
          ),
        if (authRepository != null)
          authRepositoryProvider.overrideWith((ref) => authRepository!),
        if (homeRepository != null)
          homeRepositoryProvider.overrideWith((ref) => homeRepository!),
        if (upNextFeatureRepository != null)
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => upNextFeatureRepository!,
          )
        else if (homeRepository != null)
          // Home is already stubbed away from a real database (widget
          // tests, the app-shell harness): default the Up-next strip's
          // repository the same way rather than requiring every call site
          // to know about a second, unrelated provider.
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
        if (templatePickerRepository != null)
          templatePickerFeatureRepositoryProvider.overrideWith(
            (ref) => templatePickerRepository!,
          )
        else if (homeRepository != null)
          // Same rationale as the Up-next default above: Home's "Load
          // Routine" affordance now opens the picker sheet, so a harness
          // that stubs Home away from a real database needs this
          // repository stubbed too, without every call site knowing about
          // it.
          templatePickerFeatureRepositoryProvider.overrideWith(
            (ref) => const StubTemplatePickerFeatureRepository(),
          ),
        if (routinePlanRepository != null)
          routinePlanFeatureRepositoryProvider.overrideWith(
            (ref) => routinePlanRepository!,
          ),
        if (workoutTemplateRepository != null)
          workoutTemplateFeatureRepositoryProvider.overrideWith(
            (ref) => workoutTemplateRepository!,
          ),
        if (settingsRepository != null)
          settingsRepositoryProvider.overrideWith((ref) => settingsRepository!),
      ],
      child: const PerenniaApp(),
    );
  }
}

class PerenniaApp extends ConsumerStatefulWidget {
  const PerenniaApp({super.key});

  @override
  ConsumerState<PerenniaApp> createState() =>
      _PerenniaAppState();
}

class _PerenniaAppState extends ConsumerState<PerenniaApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Register the timer-notification tap handler and drain any cold-start tap
    // once the first frame is up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        ref
            .read(workoutAutoFinishServiceProvider)
            .checkForStaleWorkoutsOnOpen(),
      );
      ref.read(syncCoordinatorProvider).requestSync(SyncTrigger.appLaunch);
      final router = ref.read(timerNotificationRouterProvider) ??
          TimerNotificationRouter(
            navigatorKey: rootNavigatorKey,
            scaffoldMessengerKey: rootScaffoldMessengerKey,
            resolveWorkoutExercise: (id) => ref
                .read(trainingRepositoriesProvider)
                .workoutExercises
                .getById(id),
          );
      router.start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) {
      return;
    }
    final service = ref.read(workoutAutoFinishServiceProvider);
    if (state == AppLifecycleState.resumed) {
      unawaited(service.checkForStaleWorkoutsOnOpen());
      final coordinator = ref.read(syncCoordinatorProvider);
      coordinator.resumePeriodic();
      coordinator.requestSync(SyncTrigger.appResume);
      return;
    }
    ref.read(syncCoordinatorProvider).pausePeriodic();
    unawaited(service.persistLastInteraction());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AppSettings>>(settingsControllerProvider, (
      _,
      next,
    ) {
      final settings = next.value;
      if (settings == null) {
        return;
      }
      unawaited(
        ref
            .read(keepScreenAwakeControllerProvider)
            .setEnabled(settings.keepScreenOn),
      );
      unawaited(
        ref
            .read(clientCrashReporterProvider)
            .setEnabled(settings.crashReportingEnabled),
      );
    });

    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings.defaults;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        ref.read(workoutAutoFinishServiceProvider).recordInteraction();
      },
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        onGenerateTitle: (context) => context.l10n.appTitle,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: settings.themeMode,
        initialRoute: HomeScreen.routeName,
        onGenerateRoute: (settings) {
          if (settings.name == WorkoutTemplateEditorScreen.routeName) {
            final templateId = settings.arguments;
            if (templateId is! String) {
              return null;
            }
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => WorkoutTemplateEditorScreen(
                templateId: templateId,
              ),
            );
          }
          if (settings.name == RoutinePlanEditorScreen.routeName) {
            final routineId = settings.arguments;
            if (routineId is! String) {
              return null;
            }
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => RoutinePlanEditorScreen(routineId: routineId),
            );
          }
          return null;
        },
        routes: <String, WidgetBuilder>{
          HomeScreen.routeName: (_) => const HomeScreen(),
          ActivityFeedScreen.routeName: (_) => const ActivityFeedScreen(),
          BodyTrackerScreen.routeName: (_) => const BodyTrackerScreen(),
          MetricsScreen.routeName: (_) => const MetricsScreen(),
          NutritionDayView.routeName: (_) => const NutritionDayView(),
          SignInScreen.routeName: (_) => const SignInScreen(),
          RoutinePlanListScreen.routeName: (_) => const RoutinePlanListScreen(),
          WorkoutTemplateListScreen.routeName: (_) =>
              const WorkoutTemplateListScreen(),
          SettingsScreen.routeName: (_) => const SettingsScreen(),
          CompoundListScreen.routeName: (_) => const ProtocolsLockGate(
                child: CompoundListScreen(),
              ),
          ProtocolsDayView.routeName: (_) => const ProtocolsLockGate(
                child: ProtocolsDayView(),
              ),
        },
      ),
    );
  }
}
