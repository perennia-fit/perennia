import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/repositories/auth_repository.dart';
import '../../auth/widgets/sign_in_screen.dart';
import '../../catalog/widgets/exercise_editor_screen.dart';
import '../../focus/controllers/focus_providers.dart';
import '../../focus/widgets/focus_manager_screen.dart';
import '../../focus/widgets/focus_visuals.dart';
import '../../protocols/widgets/compound_list_screen.dart';
import '../../protocols/widgets/protocols_day_view.dart';
import '../../protocols/widgets/protocol_screen.dart';
import '../../protocols/widgets/protocols_lock_screen.dart';
import '../../routine_plans/widgets/routine_plan_list_screen.dart';
import '../../template_materialize/controllers/template_materialize_controller.dart';
import '../../template_materialize/widgets/empty_template_start_dialog.dart';
import '../../template_picker/widgets/template_picker_sheet.dart';
import '../../up_next/widgets/up_next_strip.dart';
import '../../workout_templates/widgets/workout_template_list_screen.dart';
import '../../settings/repositories/settings_repository.dart';
import '../../settings/widgets/settings_screen.dart';
import '../../sync/controllers/sync_status_controller.dart';
import '../../nutrition/controllers/meal_screen_controller.dart'
    show isFutureNutritionDay, mealScreenClockProvider;
import '../../nutrition/widgets/meal_screen.dart';
import '../../nutrition/widgets/nutrition_day_view.dart';
import '../../profile/widgets/profile_screen.dart';
import '../../progress/widgets/progress_overview.dart';
import '../../../domain/protocols/protocols.dart';
import '../../../domain/training/training_records.dart';
import '../../../domain/training/training_day.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../controllers/home_controller.dart';
import '../repositories/home_repository.dart';
import 'start_workout_sheet.dart';
import 'workout_duration.dart';
import 'workout_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const String routeName = '/';
  static const todayDestinationKey = Key('home.destination.today');
  static const progressDestinationKey = Key('home.destination.progress');
  static const libraryDestinationKey = Key('home.destination.library');
  static const accountAndAppButtonKey = Key('home.accountAndApp');
  static const accountAndAppSignInKey = Key('home.accountAndApp.signIn');
  static const accountSignInExpiredBadgeKey =
      Key('home.accountAndApp.signInExpiredBadge');
  static const accountAndAppProfileKey = Key('home.accountAndApp.profile');
  static const accountAndAppSettingsKey = Key('home.accountAndApp.settings');
  static const logButtonKey = Key('home.log');
  static const logWorkoutKey = Key('home.log.workout');
  static const logMealKey = Key('home.log.meal');
  static const logDoseKey = Key('home.log.dose');
  static const routinePlansButtonKey = Key('home.routinePlans');
  static const workoutTemplatesButtonKey = Key('home.workoutTemplates');
  static const focusesButtonKey = Key('home.focuses');
  static const createExerciseButtonKey = Key('home.createExercise');
  static const domainToggleKey = Key('home.domainToggle');
  static const trainingDomainButtonKey = Key('home.domain.training');
  static const nutritionDomainButtonKey = Key('home.domain.nutrition');
  static const protocolsDomainButtonKey = Key('home.domain.protocols');
  static const trainingDomainBodyKey = Key('home.domainBody.training');
  static const nutritionDomainBodyKey = Key('home.domainBody.nutrition');
  static const protocolsDomainBodyKey = Key('home.domainBody.protocols');
  static const libraryProtocolsButtonKey = Key('home.library.protocols');
  static const libraryCompoundsButtonKey = Key('home.library.compounds');
  static const dayHeaderKey = Key('home.dayHeader');
  static const previousDayButtonKey = Key('home.previousDay');
  static const nextDayButtonKey = Key('home.nextDay');
  static const startWorkoutButtonKey = Key('home.startWorkout');
  static const routinesButtonKey = Key('home.routines');
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
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings.defaults;
    final showProtocols = settings.showProtocolsOnToday;
    final pickedDomain = ref.watch(selectedHomeDomainProvider);
    // Hiding the tab while it is selected falls back to Training rather
    // than leaving Protocols showing behind a toggle that no longer offers it.
    final selectedDomain =
        !showProtocols && pickedDomain == HomeDomain.protocols
            ? HomeDomain.training
            : pickedDomain;

    Future<void> startWorkout(
      BuildContext navigationContext, {
      String? focusId,
    }) async {
      try {
        final workoutId = await ref
            .read(homeControllerProvider.notifier)
            .startNewWorkout(focusId: focusId);
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

    // Log → Dose goes straight to picking what was taken, on Today's date:
    // the repeat-dose path, not a detour through a day view.
    void openDoseLog(BuildContext navigationContext) {
      final selectedDate = ref.read(selectedTrainingDayProvider);
      Navigator.of(navigationContext).push(
        MaterialPageRoute<void>(
          builder: (_) => ProtocolsLockGate(
            child: CompoundListScreen(
              protocolDay: ProtocolDayDate(
                year: selectedDate.year,
                month: selectedDate.month,
                day: selectedDate.day,
              ),
            ),
          ),
        ),
      );
    }

    // Log → Meal opens the Meal screen for the selected day
    // (docs/designs/meal-logging.md §6), not the Nutrition Day.
    void openMeal(BuildContext navigationContext) {
      final selectedDate = ref.read(selectedTrainingDayProvider);
      Navigator.of(navigationContext).push(
        MaterialPageRoute<void>(
          builder: (_) => MealScreen.newMeal(
            day: nutritionDayDateFromTrainingDay(selectedDate),
          ),
        ),
      );
    }

    Future<void> startFromTemplate(
      BuildContext navigationContext, {
      required String workoutTemplateId,
      String? routineId,
      int? slot,
    }) async {
      final proceed = await confirmTemplateStart(
        navigationContext,
        ref,
        workoutTemplateId: workoutTemplateId,
      );
      if (!proceed || !navigationContext.mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(navigationContext);
      final navigator = Navigator.of(navigationContext);
      final failureMessage = navigationContext.l10n.homeUpNextStartFailed;
      try {
        final workoutId =
            await ref.read(templateMaterializeControllerProvider).start(
                  workoutTemplateId: workoutTemplateId,
                  routineId: routineId,
                  slot: slot,
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

    Future<void> loadRoutine(BuildContext navigationContext) async {
      final picked = await showTemplatePickerSheet(navigationContext);
      if (picked == null || !navigationContext.mounted) {
        return;
      }
      await startFromTemplate(
        navigationContext,
        workoutTemplateId: picked.workoutTemplateId,
        routineId: picked.routineId,
        slot: picked.slot,
      );
    }

    Future<void> openStartSheet(BuildContext navigationContext) async {
      final choice = await showStartWorkoutSheet(navigationContext);
      if (choice == null || !navigationContext.mounted) {
        return;
      }
      await startWorkout(navigationContext, focusId: choice.focusId);
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
        onStartWorkout: openStartSheet,
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
        actions: const [_AccountAndAppButton()],
      ),
      floatingActionButton: isToday
          ? FloatingActionButton.extended(
              key: HomeScreen.logButtonKey,
              onPressed: () => _showLogSheet(
                context,
                isFutureDay: _isFutureDay(ref),
                onStartWorkout: openStartSheet,
                onOpenMeal: openMeal,
                onOpenDose: openDoseLog,
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Under the app bar, not in its `bottom`: an AppBar bottom has a
              // fixed preferred height, and at large text scales the toggle's
              // labels wrap past it. Here it takes the height they need.
              Material(
                color: context.colors.chrome,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.base,
                    0,
                    AppDimens.base,
                    AppDimens.dense,
                  ),
                  child: Center(
                    child: _HomeDomainToggle(
                      selectedDomain: selectedDomain,
                      showProtocols: showProtocols,
                      onChanged: (domain) {
                        ref
                            .read(selectedHomeDomainProvider.notifier)
                            .select(domain);
                      },
                    ),
                  ),
                ),
              ),
              Expanded(child: todayBody),
            ],
          ),
          // Built only while selected: Progress Overview's providers are
          // autoDispose, so nothing on it is computed while the user is on
          // Today or Library. Its list's PageStorageKey restores the scroll.
          if (selectedDestination == HomeDestination.progress)
            const ProgressOverview()
          else
            const SizedBox.shrink(),
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
            else if (selectedDomain == HomeDomain.nutrition)
              const _NutritionHomeBody()
            else
              KeyedSubtree(
                key: HomeScreen.protocolsDomainBodyKey,
                child: ProtocolsTodayBody(
                  localDate: ProtocolDayDate(
                    year: summary.selectedDate.year,
                    month: summary.selectedDate.month,
                    day: summary.selectedDate.day,
                  ),
                ),
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
      // Two jobs, two buttons: Start is the unplanned workout (a Focus or
      // empty); Routines is the plan, one Routine and one workout away, with
      // editing reached from inside it. Today's planned workout is the Up
      // next strip above, so neither sheet repeats it.
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
            key: HomeScreen.routinesButtonKey,
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.textPrimary,
            ),
            onPressed: () => unawaited(onLoadRoutine(context)),
            icon: const Icon(Icons.assignment_outlined),
            label: Text(l10n.homeLoadRoutine),
          ),
        ],
      ),
      if (summary.workouts.isNotEmpty) ...[
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

/// Whether Today's selected day is after today. A Meal can't start in the
/// future (§8), so the Log sheet offers no Meal there; "today" comes from the
/// Meal screen's clock, which tests override.
bool _isFutureDay(WidgetRef ref) {
  final selectedDate = ref.read(selectedTrainingDayProvider);
  return isFutureNutritionDay(
    nutritionDayDateFromTrainingDay(selectedDate),
    ref.read(mealScreenClockProvider)(),
  );
}

/// The Log sheet: Workout, Meal and Dose for the selected day. Meal is
/// hidden when [isFutureDay].
Future<void> _showLogSheet(
  BuildContext context, {
  required bool isFutureDay,
  required Future<void> Function(BuildContext context) onStartWorkout,
  required void Function(BuildContext context) onOpenMeal,
  required void Function(BuildContext context) onOpenDose,
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
        if (!isFutureDay)
          ListTile(
            key: HomeScreen.logMealKey,
            leading: const Icon(Icons.restaurant_outlined),
            title: Text(l10n.homeLogMeal),
            onTap: () {
              Navigator.of(sheetContext).pop();
              onOpenMeal(navigator.context);
            },
          ),
        ListTile(
          key: HomeScreen.logDoseKey,
          leading: const Icon(Icons.medication_outlined),
          title: Text(l10n.homeLogDose),
          onTap: () {
            Navigator.of(sheetContext).pop();
            onOpenDose(navigator.context);
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
                  key: HomeScreen.focusesButtonKey,
                  icon: Icons.flag_outlined,
                  title: l10n.focusManagerTitle,
                  subtitle: l10n.focusManagerLibrarySubtitle,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const FocusManagerScreen(),
                      ),
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
          _LibrarySectionHeader(title: l10n.homeLibraryProtocolsSection),
          const SizedBox(height: AppDimens.dense),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                SettingsNavTile(
                  key: HomeScreen.libraryProtocolsButtonKey,
                  icon: Icons.event_repeat_outlined,
                  title: l10n.protocolsDomainTitle,
                  subtitle: l10n.protocolsLibrarySubtitle,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProtocolsLockGate(
                          child: ProtocolListScreen(),
                        ),
                      ),
                    );
                  },
                ),
                const Divider(),
                SettingsNavTile(
                  key: HomeScreen.libraryCompoundsButtonKey,
                  icon: Icons.medication_outlined,
                  title: l10n.navCompounds,
                  subtitle: l10n.compoundsLibrarySubtitle,
                  onTap: () {
                    Navigator.of(context)
                        .pushNamed(CompoundListScreen.routeName);
                  },
                ),
              ],
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

/// True when this device holds a session the server last rejected as
/// unauthorized: it looks signed in, but nothing syncs until the user signs in
/// again.
bool _watchSessionExpired(WidgetRef ref) {
  final session = ref.watch(authControllerProvider).value?.session;
  final syncKind = ref.watch(syncStatusControllerProvider).value?.kind;
  return session != null && syncKind == SyncStatusKind.authExpired;
}

class _AccountAndAppButton extends ConsumerWidget {
  const _AccountAndAppButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // A quiet dot, never a dialog: sync failures stay silent (AGENTS.md), but
    // an expired sign-in only heals when the user acts, so the root says so
    // where the way back already lives. The tooltip carries it in words.
    final sessionExpired = _watchSessionExpired(ref);
    return IconButton(
      key: HomeScreen.accountAndAppButtonKey,
      tooltip: sessionExpired
          ? l10n.homeAccountAndAppSignInExpiredTooltip
          : l10n.homeAccountAndAppTitle,
      onPressed: () => _showAccountAndAppSheet(context),
      icon: Badge(
        key: sessionExpired ? HomeScreen.accountSignInExpiredBadgeKey : null,
        isLabelVisible: sessionExpired,
        backgroundColor: Theme.of(context).colorScheme.error,
        child: const Icon(Icons.account_circle_outlined),
      ),
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

      void signInAgain() {
        Navigator.of(sheetContext).pop();
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const SignInScreen(signInAgain: true),
          ),
        );
      }

      return [
        _AccountStatusTile(onTap: openAccount, onSignInAgain: signInAgain),
        ListTile(
          key: HomeScreen.accountAndAppProfileKey,
          leading: const Icon(Icons.person_outline),
          title: Text(l10n.navProfile),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(sheetContext).pop();
            navigator.pushNamed(ProfileScreen.routeName);
          },
        ),
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
  const _AccountStatusTile({required this.onTap, required this.onSignInAgain});

  final VoidCallback onTap;
  final VoidCallback onSignInAgain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final authState = ref.watch(authControllerProvider);
    final sessionExpired = _watchSessionExpired(ref);
    return authState.when(
      data: (state) {
        final session = state.session;
        if (session != null && sessionExpired) {
          return ListTile(
            key: HomeScreen.accountAndAppSignInKey,
            leading: Icon(
              Icons.person_off_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(session.userEmail),
            subtitle: Text(l10n.homeSignInExpired),
            trailing: const Icon(Icons.chevron_right),
            onTap: onSignInAgain,
          );
        }
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
    required this.showProtocols,
    required this.onChanged,
  });

  final HomeDomain selectedDomain;
  final bool showProtocols;
  final ValueChanged<HomeDomain> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Semantics(
      label: l10n.homeDomainToggleLabel,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: showProtocols ? 480 : 360),
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
            if (showProtocols)
              ButtonSegment<HomeDomain>(
                value: HomeDomain.protocols,
                label: Text(
                  l10n.protocolsDomainTitle,
                  key: HomeScreen.protocolsDomainButtonKey,
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

/// Today's Nutrition view: the selected day's [NutritionDayBody], whose
/// `Log meal` button and Meal cards open the Meal screen.
class _NutritionHomeBody extends ConsumerWidget {
  const _NutritionHomeBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(homeNutritionDayProvider);

    return KeyedSubtree(
      key: HomeScreen.nutritionDomainBodyKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          day.when(
            data: (day) => NutritionDayBody(day: day),
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

class _WorkoutSummaryTile extends ConsumerWidget {
  const _WorkoutSummaryTile({
    required this.workout,
    required this.exercises,
  });

  final HomeWorkoutSummary workout;
  final List<HomeWorkoutExerciseSummary> exercises;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exerciseNames = exercises.map((exercise) => exercise.name).toList();
    final focus = ref.watch(focusRecordProvider(workout.focusId));
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
                        _formatSessionHeader(context, workout, focus),
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
  FocusRecord? focus,
) {
  final startedAt = workout.startedAt.toLocal();
  final time = MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay.fromDateTime(startedAt),
  );
  return focus == null
      ? context.l10n.homeSessionHeader(time)
      : context.l10n.homeSessionHeaderWithFocus(
          focusDisplayName(context, focus),
          time,
        );
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
  // Progress against the plan while the Workout has a Planned Set.
  final setCount = workout.performedSetCount < workout.setCount
      ? context.l10n.workoutPerformedSetsOfTotal(
          workout.performedSetCount,
          workout.setCount,
        )
      : switch (workout.setCount) {
          0 => context.l10n.workoutNoSets,
          1 => context.l10n.workoutOneSet,
          final count => context.l10n.workoutSetCount(count),
        };
  final duration = formatWorkoutDuration(context.l10n, workout.duration);
  return '$status - $duration - $exerciseCount - $setCount';
}
