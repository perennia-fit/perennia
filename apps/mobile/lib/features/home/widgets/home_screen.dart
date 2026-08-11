import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/repositories/auth_repository.dart';
import '../../auth/widgets/sign_in_screen.dart';
import '../../body_tracker/widgets/body_tracker_screen.dart';
import '../../catalog/widgets/exercise_editor_screen.dart';
import '../../metrics/widgets/metrics_screen.dart';
import '../../protocols/controllers/protocols_day_controller.dart';
import '../../protocols/widgets/compound_list_screen.dart';
import '../../protocols/widgets/protocols_day_view.dart';
import '../../protocols/widgets/protocols_lock_screen.dart';
import '../../routine_plans/widgets/routine_plan_list_screen.dart';
import '../../template_materialize/controllers/template_materialize_controller.dart';
import '../../template_picker/widgets/template_picker_sheet.dart';
import '../../up_next/widgets/up_next_strip.dart';
import '../../workout_templates/widgets/workout_template_list_screen.dart';
import '../../settings/repositories/settings_repository.dart';
import '../../settings/widgets/settings_screen.dart';
import '../../nutrition/controllers/nutrition_day_controller.dart';
import '../../nutrition/widgets/nutrition_day_view.dart';
import '../../../domain/protocols/protocols.dart';
import '../../../domain/training/training_day.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../controllers/home_controller.dart';
import '../repositories/home_repository.dart';
import 'workout_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const String routeName = '/';
  static const todayDestinationKey = Key('home.destination.today');
  static const progressDestinationKey = Key('home.destination.progress');
  static const libraryDestinationKey = Key('home.destination.library');
  static const accountAndAppButtonKey = Key('home.accountAndApp');
  static const accountAndAppSignInKey = Key('home.accountAndApp.signIn');
  static const accountAndAppSettingsKey = Key('home.accountAndApp.settings');
  static const logButtonKey = Key('home.log');
  static const logWorkoutKey = Key('home.log.workout');
  static const logFoodKey = Key('home.log.food');
  static const logSupplementKey = Key('home.log.supplement');
  static const manageRoutinesButtonKey = Key('home.manageRoutines');
  static const routinePlansButtonKey = Key('home.routinePlans');
  static const workoutTemplatesButtonKey = Key('home.workoutTemplates');
  static const createExerciseButtonKey = Key('home.createExercise');
  static const domainToggleKey = Key('home.domainToggle');
  static const trainingDomainButtonKey = Key('home.domain.training');
  static const nutritionDomainButtonKey = Key('home.domain.nutrition');
  static const trainingDomainBodyKey = Key('home.domainBody.training');
  static const nutritionDomainBodyKey = Key('home.domainBody.nutrition');
  static const dayHeaderKey = Key('home.dayHeader');
  static const previousDayButtonKey = Key('home.previousDay');
  static const nextDayButtonKey = Key('home.nextDay');
  static const startWorkoutButtonKey = Key('home.startWorkout');
  static const loadRoutineButtonKey = Key('home.loadRoutine');
  static const addExerciseButtonKey = Key('home.addExercise');
  static Key workoutDurationKey(String workoutId) {
    return Key('home.workoutDuration-$workoutId');
  }

  static Key workoutCommentFieldKey(String workoutId) {
    return Key('home.workoutComment-$workoutId');
  }

  static Key saveWorkoutCommentButtonKey(String workoutId) {
    return Key('home.saveWorkoutComment-$workoutId');
  }

  static Key copyWorkoutButtonKey(String workoutId) {
    return Key('home.copyWorkout-$workoutId');
  }

  static Key moveWorkoutButtonKey(String workoutId) {
    return Key('home.moveWorkout-$workoutId');
  }

  static Key shareWorkoutButtonKey(String workoutId) {
    return Key('home.shareWorkout-$workoutId');
  }

  static Key sessionHeaderKey(String workoutId) {
    return Key('home.sessionHeader-$workoutId');
  }

  static Key sessionBlockKey(String workoutId) {
    return Key('home.sessionBlock-$workoutId');
  }

  static Key addExerciseToWorkoutButtonKey(String workoutId) {
    return Key('home.addExercise-$workoutId');
  }

  static Key openWorkoutButtonKey(String workoutId) {
    return Key('home.openWorkout-$workoutId');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homeControllerProvider);
    final selectedDestination = ref.watch(selectedHomeDestinationProvider);
    final selectedDomain = ref.watch(selectedHomeDomainProvider);
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings.defaults;

    Future<void> startWorkout(BuildContext navigationContext) async {
      try {
        final workoutId =
            await ref.read(homeControllerProvider.notifier).startNewWorkout();
        if (!navigationContext.mounted) {
          return;
        }
        await Navigator.of(navigationContext).push(
          MaterialPageRoute<void>(
            builder: (_) => WorkoutScreen(workoutId: workoutId),
          ),
        );
      } on Object {
        if (!navigationContext.mounted) {
          return;
        }
        ScaffoldMessenger.of(navigationContext).showSnackBar(
          SnackBar(
            content: Text(navigationContext.l10n.homeStartWorkoutFailed),
          ),
        );
      }
    }

    void openSupplements(BuildContext navigationContext) {
      final selectedDate = ref.read(selectedTrainingDayProvider);
      ref.read(selectedProtocolDayProvider.notifier).select(
            ProtocolDayDate(
              year: selectedDate.year,
              month: selectedDate.month,
              day: selectedDate.day,
            ),
          );
      Navigator.of(navigationContext).push(
        MaterialPageRoute<void>(
          builder: (_) => const ProtocolsLockGate(
            child: ProtocolsDayView(),
          ),
        ),
      );
    }

    void openFood(BuildContext navigationContext) {
      final selectedDate = ref.read(selectedTrainingDayProvider);
      ref
          .read(selectedNutritionDayProvider.notifier)
          .select(nutritionDayDateFromTrainingDay(selectedDate));
      Navigator.of(navigationContext).push(
        MaterialPageRoute<void>(builder: (_) => const NutritionDayView()),
      );
    }

    Future<void> loadRoutine(BuildContext navigationContext) async {
      final picked = await showTemplatePickerSheet(navigationContext);
      if (picked == null || !navigationContext.mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(navigationContext);
      final navigator = Navigator.of(navigationContext);
      final failureMessage = navigationContext.l10n.homeUpNextStartFailed;
      try {
        final workoutId =
            await ref.read(templateMaterializeControllerProvider).start(
                  workoutTemplateId: picked.workoutTemplateId,
                  routineId: picked.routineId,
                  slot: picked.slot,
                );
        if (!navigationContext.mounted) {
          return;
        }
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => WorkoutScreen(workoutId: workoutId),
          ),
        );
      } on Object {
        if (navigationContext.mounted) {
          messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
        }
      }
    }

    final todayBody = state.when<Widget>(
      data: (homeState) => _HomeContent(
        summary: homeState.summary,
        homeScreenDisplay: settings.homeScreenDisplay,
        selectedDomain: selectedDomain,
        onPreviousDay: () {
          ref.read(homeControllerProvider.notifier).showPreviousDay();
        },
        onNextDay: () {
          ref.read(homeControllerProvider.notifier).showNextDay();
        },
        onStartWorkout: startWorkout,
        onLoadRoutine: loadRoutine,
      ),
      loading: () => const SizedBox.expand(),
      error: (error, stackTrace) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.base),
          child: Text(
            context.l10n.homeUnavailable,
            style: context.textStyles.body.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
    final isToday = selectedDestination == HomeDestination.today;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          switch (selectedDestination) {
            HomeDestination.today => l10n.homeTodayDestination,
            HomeDestination.progress => l10n.homeProgressTitle,
            HomeDestination.library => l10n.homeLibraryTitle,
          },
        ),
        bottom: isToday
            ? PreferredSize(
                preferredSize: const Size.fromHeight(
                  AppDimens.touchTarget + AppDimens.dense,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.base,
                    0,
                    AppDimens.base,
                    AppDimens.dense,
                  ),
                  child: _HomeDomainToggle(
                    selectedDomain: selectedDomain,
                    onChanged: (domain) {
                      ref
                          .read(selectedHomeDomainProvider.notifier)
                          .select(domain);
                    },
                  ),
                ),
              )
            : null,
        actions: const [_AccountAndAppButton()],
      ),
      floatingActionButton: isToday
          ? FloatingActionButton.extended(
              key: HomeScreen.logButtonKey,
              onPressed: () => _showLogSheet(
                context,
                onStartWorkout: startWorkout,
                onOpenFood: openFood,
                onOpenSupplements: openSupplements,
              ),
              icon: const Icon(Icons.add),
              label: Text(l10n.homeLogAction),
            )
          : null,
      bottomNavigationBar: _HomeNavigationBar(
        selectedDestination: selectedDestination,
        onSelectDestination: (destination) {
          ref
              .read(selectedHomeDestinationProvider.notifier)
              .select(destination);
        },
      ),
      body: IndexedStack(
        index: selectedDestination.index,
        children: [
          todayBody,
          const _ProgressHomeContent(),
          const _LibraryHomeContent(),
        ],
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.summary,
    required this.homeScreenDisplay,
    required this.selectedDomain,
    required this.onPreviousDay,
    required this.onNextDay,
    required this.onStartWorkout,
    required this.onLoadRoutine,
  });

  final HomeSummary summary;
  final HomeScreenDisplay homeScreenDisplay;
  final HomeDomain selectedDomain;
  final VoidCallback onPreviousDay;
  final VoidCallback onNextDay;
  final Future<void> Function(BuildContext context) onStartWorkout;
  final Future<void> Function(BuildContext context) onLoadRoutine;

  @override
  Widget build(BuildContext context) {
    final sectionGap = homeScreenDisplay == HomeScreenDisplay.compact
        ? AppDimens.dense
        : AppDimens.base;
    final l10n = context.l10n;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.base),
        child: ListView(
          children: [
            _TrainingDayHeader(
              localDate: summary.selectedDate,
              onPreviousDay: onPreviousDay,
              onNextDay: onNextDay,
            ),
            SizedBox(height: sectionGap),
            if (selectedDomain == HomeDomain.training)
              KeyedSubtree(
                key: HomeScreen.trainingDomainBodyKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ..._trainingDomainChildren(
                      context,
                      l10n,
                      sectionGap,
                    ),
                  ],
                ),
              )
            else
              _NutritionHomeBody(
                localDate: summary.selectedDate,
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _trainingDomainChildren(
    BuildContext context,
    AppLocalizations l10n,
    double sectionGap,
  ) {
    return [
      Text(
        summary.status,
        style: context.textStyles.body.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
      SizedBox(height: sectionGap),
      const UpNextStrip(),
      if (summary.workouts.isEmpty)
        Wrap(
          spacing: AppDimens.dense,
          runSpacing: AppDimens.dense,
          children: [
            FilledButton.icon(
              key: HomeScreen.startWorkoutButtonKey,
              onPressed: () => unawaited(onStartWorkout(context)),
              icon: const Icon(Icons.add),
              label: Text(l10n.homeStartNewWorkout),
            ),
            OutlinedButton.icon(
              key: HomeScreen.loadRoutineButtonKey,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.textPrimary,
              ),
              onPressed: () => unawaited(onLoadRoutine(context)),
              icon: const Icon(Icons.playlist_add_check),
              label: Text(l10n.homeLoadRoutine),
            ),
          ],
        )
      else ...[
        Wrap(
          spacing: AppDimens.dense,
          runSpacing: AppDimens.dense,
          children: [
            OutlinedButton.icon(
              key: HomeScreen.startWorkoutButtonKey,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.textPrimary,
              ),
              onPressed: () => unawaited(onStartWorkout(context)),
              icon: const Icon(Icons.add),
              label: Text(l10n.homeStartNewWorkout),
            ),
            FilledButton.icon(
              key: HomeScreen.loadRoutineButtonKey,
              onPressed: () => unawaited(onLoadRoutine(context)),
              icon: const Icon(Icons.playlist_add_check),
              label: Text(l10n.homeLoadRoutine),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.base),
        Text(l10n.workoutSummaryListTitle, style: context.textStyles.h2),
        const SizedBox(height: AppDimens.dense),
        for (final workout in summary.workouts) ...[
          _WorkoutSummaryTile(
            workout: workout,
            exercises: _workoutExercisesFor(workout),
          ),
          const SizedBox(height: AppDimens.dense),
        ],
      ],
      const SizedBox(height: AppDimens.dense),
      TextButton.icon(
        key: HomeScreen.manageRoutinesButtonKey,
        style: TextButton.styleFrom(
          foregroundColor: context.colors.textPrimary,
        ),
        onPressed: () {
          Navigator.of(context).pushNamed(RoutinePlanListScreen.routeName);
        },
        icon: const Icon(Icons.assignment_outlined),
        label: Text(l10n.homeManageRoutines),
      ),
    ];
  }

  List<HomeWorkoutExerciseSummary> _workoutExercisesFor(
    HomeWorkoutSummary workout,
  ) {
    if (workout.workoutExercises.isNotEmpty) {
      return workout.workoutExercises;
    }

    return summary.workoutExercises
        .where((exercise) => exercise.workoutId == workout.id)
        .toList(growable: false);
  }
}

class _HomeNavigationBar extends StatelessWidget {
  const _HomeNavigationBar({
    required this.selectedDestination,
    required this.onSelectDestination,
  });

  final HomeDestination selectedDestination;
  final ValueChanged<HomeDestination> onSelectDestination;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return NavigationBar(
      selectedIndex: selectedDestination.index,
      onDestinationSelected: (index) {
        onSelectDestination(HomeDestination.values[index]);
      },
      destinations: [
        NavigationDestination(
          key: HomeScreen.todayDestinationKey,
          icon: const Icon(Icons.today_outlined),
          selectedIcon: const Icon(Icons.today),
          label: l10n.homeTodayDestination,
        ),
        NavigationDestination(
          key: HomeScreen.progressDestinationKey,
          icon: const Icon(Icons.insights_outlined),
          selectedIcon: const Icon(Icons.insights),
          label: l10n.homeProgressDestination,
        ),
        NavigationDestination(
          key: HomeScreen.libraryDestinationKey,
          icon: const Icon(Icons.inventory_2_outlined),
          selectedIcon: const Icon(Icons.inventory_2),
          label: l10n.homeLibraryDestination,
        ),
      ],
    );
  }
}

Future<void> _showLogSheet(
  BuildContext context, {
  required Future<void> Function(BuildContext context) onStartWorkout,
  required void Function(BuildContext context) onOpenFood,
  required void Function(BuildContext context) onOpenSupplements,
}) {
  final navigator = Navigator.of(context);
  return _showTitledActionSheet(
    context: context,
    title: context.l10n.homeLogSheetTitle,
    actionsBuilder: (sheetContext) {
      final l10n = sheetContext.l10n;
      return [
        ListTile(
          key: HomeScreen.logWorkoutKey,
          leading: const Icon(Icons.fitness_center),
          title: Text(l10n.homeLogWorkout),
          onTap: () {
            Navigator.of(sheetContext).pop();
            unawaited(onStartWorkout(context));
          },
        ),
        ListTile(
          key: HomeScreen.logFoodKey,
          leading: const Icon(Icons.restaurant_outlined),
          title: Text(l10n.homeLogFood),
          onTap: () {
            Navigator.of(sheetContext).pop();
            onOpenFood(navigator.context);
          },
        ),
        ListTile(
          key: HomeScreen.logSupplementKey,
          leading: const Icon(Icons.medication_outlined),
          title: Text(l10n.homeLogSupplement),
          onTap: () {
            Navigator.of(sheetContext).pop();
            onOpenSupplements(navigator.context);
          },
        ),
      ];
    },
  );
}

Future<void> _showTitledActionSheet({
  required BuildContext context,
  required String title,
  required List<Widget> Function(BuildContext sheetContext) actionsBuilder,
}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: AppDimens.base),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.base,
                ),
                child: Text(title, style: sheetContext.textStyles.h2),
              ),
              const SizedBox(height: AppDimens.dense),
              ...actionsBuilder(sheetContext),
            ],
          ),
        ),
      );
    },
  );
}

class _ProgressHomeContent extends StatelessWidget {
  const _ProgressHomeContent();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppDimens.base),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: SettingsNavTile(
              icon: Icons.monitor_weight_outlined,
              title: l10n.homeBodyTitle,
              subtitle: l10n.navBodyTracker,
              onTap: () {
                Navigator.of(context).pushNamed(BodyTrackerScreen.routeName);
              },
            ),
          ),
          const SizedBox(height: AppDimens.dense),
          Card(
            margin: EdgeInsets.zero,
            child: SettingsNavTile(
              icon: Icons.monitor_heart_outlined,
              title: l10n.homeHealthMetricsTitle,
              subtitle: l10n.metricsTitle,
              onTap: () {
                Navigator.of(context).pushNamed(MetricsScreen.routeName);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryHomeContent extends StatelessWidget {
  const _LibraryHomeContent();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppDimens.base),
        children: [
          _LibrarySectionHeader(title: l10n.homeLibraryTrainingSection),
          const SizedBox(height: AppDimens.dense),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                SettingsNavTile(
                  key: HomeScreen.createExerciseButtonKey,
                  icon: Icons.add_circle_outline,
                  title: l10n.homeCreateExercise,
                  subtitle: l10n.homeCreateExerciseSubtitle,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ExerciseEditorScreen(),
                      ),
                    );
                  },
                ),
                const Divider(),
                SettingsNavTile(
                  key: HomeScreen.workoutTemplatesButtonKey,
                  icon: Icons.fitness_center_outlined,
                  title: l10n.workoutTemplatesTitle,
                  subtitle: l10n.workoutTemplatesLibrarySubtitle,
                  onTap: () {
                    Navigator.of(context).pushNamed(
                      WorkoutTemplateListScreen.routeName,
                    );
                  },
                ),
                const Divider(),
                SettingsNavTile(
                  key: HomeScreen.routinePlansButtonKey,
                  icon: Icons.assignment_outlined,
                  title: l10n.navRoutines,
                  onTap: () {
                    Navigator.of(context).pushNamed(
                      RoutinePlanListScreen.routeName,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.base),
          _LibrarySectionHeader(title: l10n.homeLibrarySupplementsSection),
          const SizedBox(height: AppDimens.dense),
          Card(
            margin: EdgeInsets.zero,
            child: SettingsNavTile(
              icon: Icons.medication_outlined,
              title: l10n.navSupplements,
              onTap: () {
                Navigator.of(context).pushNamed(CompoundListScreen.routeName);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LibrarySectionHeader extends StatelessWidget {
  const _LibrarySectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: context.textStyles.label.copyWith(
        color: context.colors.textSecondary,
      ),
    );
  }
}

class _AccountAndAppButton extends StatelessWidget {
  const _AccountAndAppButton();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return IconButton(
      key: HomeScreen.accountAndAppButtonKey,
      tooltip: l10n.homeAccountAndAppTitle,
      onPressed: () => _showAccountAndAppSheet(context),
      icon: const Icon(Icons.account_circle_outlined),
    );
  }
}

Future<void> _showAccountAndAppSheet(BuildContext context) {
  final navigator = Navigator.of(context);
  return _showTitledActionSheet(
    context: context,
    title: context.l10n.homeAccountAndAppTitle,
    actionsBuilder: (sheetContext) {
      final l10n = sheetContext.l10n;
      void openAccount() {
        Navigator.of(sheetContext).pop();
        navigator.pushNamed(SignInScreen.routeName);
      }

      return [
        _AccountStatusTile(onTap: openAccount),
        ListTile(
          key: HomeScreen.accountAndAppSettingsKey,
          leading: const Icon(Icons.settings_outlined),
          title: Text(l10n.navSettings),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(sheetContext).pop();
            navigator.pushNamed(SettingsScreen.routeName);
          },
        ),
      ];
    },
  );
}

class _AccountStatusTile extends ConsumerWidget {
  const _AccountStatusTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final authState = ref.watch(authControllerProvider);
    return authState.when(
      data: (state) {
        final session = state.session;
        return ListTile(
          key: HomeScreen.accountAndAppSignInKey,
          leading: Icon(
            session == null
                ? Icons.cloud_off_outlined
                : Icons.cloud_done_outlined,
          ),
          title: Text(session?.userEmail ?? l10n.homeLocalOnlyStatus),
          subtitle: Text(
            session == null
                ? l10n.homeSignInToSync
                : l10n.homeManageAccountAndSync,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        );
      },
      loading: () => ListTile(
        key: HomeScreen.accountAndAppSignInKey,
        leading: const Icon(Icons.cloud_sync_outlined),
        title: Text(l10n.homeAccountStatusLoading),
      ),
      error: (error, stackTrace) => ListTile(
        key: HomeScreen.accountAndAppSignInKey,
        leading: const Icon(Icons.error_outline),
        title: Text(l10n.homeAccountStatusUnavailable),
        subtitle: Text(l10n.homeSignInToSync),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _HomeDomainToggle extends StatelessWidget {
  const _HomeDomainToggle({
    required this.selectedDomain,
    required this.onChanged,
  });

  final HomeDomain selectedDomain;
  final ValueChanged<HomeDomain> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Semantics(
      label: l10n.homeDomainToggleLabel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SegmentedButton<HomeDomain>(
          key: HomeScreen.domainToggleKey,
          selected: <HomeDomain>{selectedDomain},
          style: _homeDomainToggleStyle(context),
          segments: <ButtonSegment<HomeDomain>>[
            ButtonSegment<HomeDomain>(
              value: HomeDomain.training,
              label: Text(
                l10n.homeTrainingDomain,
                key: HomeScreen.trainingDomainButtonKey,
              ),
            ),
            ButtonSegment<HomeDomain>(
              value: HomeDomain.nutrition,
              label: Text(
                l10n.homeNutritionDomain,
                key: HomeScreen.nutritionDomainButtonKey,
              ),
            ),
          ],
          onSelectionChanged: (selection) {
            onChanged(selection.single);
          },
        ),
      ),
    );
  }
}

ButtonStyle _homeDomainToggleStyle(BuildContext context) {
  final colors = context.colors;
  final scheme = Theme.of(context).colorScheme;

  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(
      Size.fromHeight(AppDimens.touchTarget),
    ),
    textStyle: WidgetStatePropertyAll(context.textStyles.label),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return scheme.primary;
      }
      return colors.surface;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return scheme.onPrimary;
      }
      return colors.textPrimary;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      return BorderSide(
        color: states.contains(WidgetState.selected)
            ? scheme.primary
            : colors.divider,
      );
    }),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

class _NutritionHomeBody extends ConsumerWidget {
  const _NutritionHomeBody({
    required this.localDate,
  });

  final TrainingDayDate localDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(homeNutritionDayProvider);

    return KeyedSubtree(
      key: HomeScreen.nutritionDomainBodyKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          day.when(
            data: (day) => NutritionDayBody(
              day: day,
              onStartMeal: (mealType) {
                return ref
                    .read(nutritionDayControllerProvider.notifier)
                    .startMeal(
                      mealType: mealType,
                      localDate: nutritionDayDateFromTrainingDay(localDate),
                    );
              },
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => Text(
              context.l10n.homeNutritionUnavailable,
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkoutSummaryTile extends StatelessWidget {
  const _WorkoutSummaryTile({
    required this.workout,
    required this.exercises,
  });

  final HomeWorkoutSummary workout;
  final List<HomeWorkoutExerciseSummary> exercises;

  @override
  Widget build(BuildContext context) {
    final exerciseNames = exercises.map((exercise) => exercise.name).toList();
    return Material(
      key: HomeScreen.sessionBlockKey(workout.id),
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: context.colors.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: HomeScreen.openWorkoutButtonKey(workout.id),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => WorkoutScreen(workoutId: workout.id),
            ),
          );
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Row(
              children: [
                Icon(
                  workout.isOpen
                      ? Icons.play_circle_outline
                      : Icons.check_circle_outline,
                  color: workout.isOpen
                      ? Theme.of(context).colorScheme.primary
                      : context.colors.save,
                ),
                const SizedBox(width: AppDimens.dense),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatSessionHeader(context, workout),
                        key: HomeScreen.sessionHeaderKey(workout.id),
                        style: context.textStyles.h2,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatWorkoutTileSubtitle(context, workout),
                        style: context.textStyles.body.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                      if (exerciseNames.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          exerciseNames.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.caption.copyWith(
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppDimens.dense),
                Icon(
                  Icons.chevron_right,
                  color: context.colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatSessionHeader(
  BuildContext context,
  HomeWorkoutSummary workout,
) {
  final startedAt = workout.startedAt.toLocal();
  final time = MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay.fromDateTime(startedAt),
  );
  return context.l10n.homeSessionHeader(time);
}

class _TrainingDayHeader extends StatelessWidget {
  const _TrainingDayHeader({
    required this.localDate,
    required this.onPreviousDay,
    required this.onNextDay,
  });

  final TrainingDayDate localDate;
  final VoidCallback onPreviousDay;
  final VoidCallback onNextDay;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: HomeScreen.dayHeaderKey,
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > 0) {
          onPreviousDay();
        } else if (velocity < 0) {
          onNextDay();
        }
      },
      child: Row(
        children: [
          IconButton(
            key: HomeScreen.previousDayButtonKey,
            tooltip: context.l10n.homePreviousDayTooltip,
            onPressed: onPreviousDay,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              _formatTrainingDay(context, localDate),
              textAlign: TextAlign.center,
              style: context.textStyles.h2,
            ),
          ),
          IconButton(
            key: HomeScreen.nextDayButtonKey,
            tooltip: context.l10n.homeNextDayTooltip,
            onPressed: onNextDay,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

String _formatTrainingDay(BuildContext context, TrainingDayDate localDate) {
  return MaterialLocalizations.of(context).formatMediumDate(
    localDate.toLocalDateTime(),
  );
}

String _formatWorkoutDuration(AppLocalizations l10n, Duration? duration) {
  if (duration == null || duration.isNegative) {
    return l10n.workoutDurationInProgress;
  }

  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return minutes == 0
        ? l10n.workoutDurationHours(hours)
        : l10n.workoutDurationHoursMinutes(hours, minutes);
  }
  if (minutes > 0) {
    return l10n.workoutDurationMinutes(minutes);
  }
  return l10n.workoutDurationSeconds(seconds);
}

String _formatWorkoutTileSubtitle(
  BuildContext context,
  HomeWorkoutSummary workout,
) {
  final status = workout.isOpen
      ? context.l10n.workoutOpenStatus
      : context.l10n.workoutFinishedStatus;
  final exerciseCount = switch (workout.workoutExercises.length) {
    0 => context.l10n.workoutNoExercises,
    1 => context.l10n.workoutOneExercise,
    final count => context.l10n.workoutExerciseCount(count),
  };
  final setCount = switch (workout.setCount) {
    0 => context.l10n.workoutNoSets,
    1 => context.l10n.workoutOneSet,
    final count => context.l10n.workoutSetCount(count),
  };
  final duration = _formatWorkoutDuration(context.l10n, workout.duration);
  return '$status - $duration - $exerciseCount - $setCount';
}
