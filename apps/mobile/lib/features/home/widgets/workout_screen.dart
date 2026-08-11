import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart'
    show TemplateDivergenceSummary;
import '../../../domain/training/training_day.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../catalog/widgets/exercise_catalog_picker.dart';
import '../../template_divergence/repositories/template_divergence_feature_repository.dart';
import '../../template_divergence/widgets/template_update_prompt_dialog.dart';
import '../../training/services/timer_notification_router.dart';
import '../../workout_capture/widgets/workout_capture_sheet.dart';
import '../controllers/home_controller.dart';
import '../repositories/home_repository.dart';

class WorkoutScreen extends ConsumerWidget {
  const WorkoutScreen({
    super.key,
    required this.workoutId,
  });

  final String workoutId;

  static Key addExerciseButtonKey(String workoutId) {
    return Key('workout.$workoutId.addExercise');
  }

  static Key exerciseCardKey(String workoutExerciseId) {
    return Key('workout.exercise.$workoutExerciseId');
  }

  static Key exerciseDismissibleKey(String workoutExerciseId) {
    return Key('workout.exercise.$workoutExerciseId.dismissible');
  }

  static Key exerciseDeleteBackgroundKey(String workoutExerciseId) {
    return Key('workout.exercise.$workoutExerciseId.deleteBackground');
  }

  static Key reorderExerciseHandleKey(String workoutExerciseId) {
    return Key('workout.exercise.$workoutExerciseId.reorder');
  }

  static Key openExerciseButtonKey(String workoutExerciseId) {
    return Key('workout.exercise.$workoutExerciseId.open');
  }

  static Key finishButtonKey(String workoutId) {
    return Key('workout.$workoutId.finish');
  }

  static Key resumeButtonKey(String workoutId) {
    return Key('workout.$workoutId.resume');
  }

  static Key notesButtonKey(String workoutId) {
    return Key('workout.$workoutId.notes');
  }

  static Key notesFieldKey(String workoutId) {
    return Key('workout.$workoutId.notes.field');
  }

  static Key saveNotesButtonKey(String workoutId) {
    return Key('workout.$workoutId.notes.save');
  }

  static Key deleteNotesButtonKey(String workoutId) {
    return Key('workout.$workoutId.notes.delete');
  }

  static Key optionsButtonKey(String workoutId) {
    return Key('workout.$workoutId.options');
  }

  static Key captureTemplateButtonKey(String workoutId) {
    return Key('workout.$workoutId.captureTemplate');
  }

  static Key editStartTimeButtonKey(String workoutId) {
    return Key('workout.$workoutId.editStartTime');
  }

  static Key editFinishTimeButtonKey(String workoutId) {
    return Key('workout.$workoutId.editFinishTime');
  }

  static Key deleteConfirmButtonKey(String workoutId) {
    return Key('workout.$workoutId.delete.confirm');
  }

  static Key finishedSnackBarShareActionKey(String workoutId) {
    return Key('workout.$workoutId.finished.share');
  }

  static Key updateTemplateMenuButtonKey(String workoutId) {
    return Key('workout.$workoutId.updateTemplate');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workout = ref.watch(workoutSummaryProvider(workoutId));
    return workout.when(
      data: (workout) {
        if (workout == null) {
          return Scaffold(
            appBar: AppBar(title: Text(context.l10n.workoutTitle)),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppDimens.base),
                child: Text(
                  context.l10n.workoutUnavailable,
                  style: context.textStyles.body.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }

        return _WorkoutContent(workout: workout);
      },
      loading: () => Scaffold(
        appBar: AppBar(title: Text(context.l10n.workoutTitle)),
        body: const SizedBox.expand(),
      ),
      error: (_, __) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.workoutTitle)),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Text(
              context.l10n.workoutUnavailable,
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _WorkoutMenuAction {
  editStartTime,
  editFinishTime,
  copy,
  move,
  captureTemplate,
  updateTemplate,
  share,
  delete,
}

class _WorkoutContent extends ConsumerWidget {
  const _WorkoutContent({
    required this.workout,
  });

  final HomeWorkoutSummary workout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(homeControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.workoutTitle),
        actions: [
          PopupMenuButton<_WorkoutMenuAction>(
            key: WorkoutScreen.optionsButtonKey(workout.id),
            tooltip: context.l10n.workoutOptionsTooltip,
            onSelected: (action) {
              switch (action) {
                case _WorkoutMenuAction.editStartTime:
                  unawaited(_editWorkoutStartTime(context, controller));
                case _WorkoutMenuAction.editFinishTime:
                  unawaited(_editWorkoutFinishTime(context, controller));
                case _WorkoutMenuAction.copy:
                  unawaited(_copyWorkout(context, controller));
                case _WorkoutMenuAction.move:
                  unawaited(_moveWorkout(context, controller));
                case _WorkoutMenuAction.captureTemplate:
                  unawaited(_captureWorkoutAsTemplate(context));
                case _WorkoutMenuAction.updateTemplate:
                  unawaited(_updateWorkoutTemplate(context, ref));
                case _WorkoutMenuAction.share:
                  unawaited(_shareWorkout(context, controller));
                case _WorkoutMenuAction.delete:
                  unawaited(_confirmDeleteWorkout(context, controller));
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<_WorkoutMenuAction>(
                key: WorkoutScreen.editStartTimeButtonKey(workout.id),
                value: _WorkoutMenuAction.editStartTime,
                child: _MenuRow(
                  icon: Icons.schedule_outlined,
                  label: context.l10n.workoutEditStartTime,
                ),
              ),
              if (!workout.isOpen)
                PopupMenuItem<_WorkoutMenuAction>(
                  key: WorkoutScreen.editFinishTimeButtonKey(workout.id),
                  value: _WorkoutMenuAction.editFinishTime,
                  child: _MenuRow(
                    icon: Icons.flag_outlined,
                    label: context.l10n.workoutEditFinishTime,
                  ),
                ),
              PopupMenuItem<_WorkoutMenuAction>(
                value: _WorkoutMenuAction.copy,
                child: _MenuRow(
                  icon: Icons.copy_outlined,
                  label: context.l10n.homeCopyWorkoutTooltip,
                ),
              ),
              PopupMenuItem<_WorkoutMenuAction>(
                value: _WorkoutMenuAction.move,
                child: _MenuRow(
                  icon: Icons.drive_file_move_outlined,
                  label: context.l10n.homeMoveWorkoutTooltip,
                ),
              ),
              PopupMenuItem<_WorkoutMenuAction>(
                key: WorkoutScreen.captureTemplateButtonKey(workout.id),
                value: _WorkoutMenuAction.captureTemplate,
                child: _MenuRow(
                  icon: Icons.bookmark_add_outlined,
                  label: context.l10n.workoutCaptureMenuAction,
                ),
              ),
              PopupMenuItem<_WorkoutMenuAction>(
                key: WorkoutScreen.updateTemplateMenuButtonKey(workout.id),
                value: _WorkoutMenuAction.updateTemplate,
                child: _MenuRow(
                  icon: Icons.sync_outlined,
                  label: context.l10n.workoutUpdateTemplateMenuAction,
                ),
              ),
              PopupMenuItem<_WorkoutMenuAction>(
                value: _WorkoutMenuAction.share,
                child: _MenuRow(
                  icon: Icons.share_outlined,
                  label: context.l10n.homeShareWorkoutTooltip,
                ),
              ),
              PopupMenuItem<_WorkoutMenuAction>(
                value: _WorkoutMenuAction.delete,
                child: _MenuRow(
                  icon: Icons.delete_outline,
                  label: context.l10n.workoutDelete,
                  isDestructive: true,
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.base),
          child: ListView(
            children: [
              _WorkoutHeader(
                workout: workout,
                onAddExercise: () => _showExercisePicker(context, controller),
                onFinish: () => _finishWorkout(context, controller, ref),
                onResume: () async {
                  await controller.resumeWorkout(workout.id);
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.l10n.workoutResumed)),
                  );
                },
              ),
              const SizedBox(height: AppDimens.base),
              Text(context.l10n.workoutExercisesTitle,
                  style: context.textStyles.h2),
              const SizedBox(height: AppDimens.dense),
              if (workout.workoutExercises.isEmpty)
                Text(
                  context.l10n.homeNoExercisesLoggedYet,
                  style: context.textStyles.body.copyWith(
                    color: context.colors.textSecondary,
                  ),
                )
              else
                _WorkoutExerciseList(
                  exercises: workout.workoutExercises,
                  exerciseGroups: workout.exerciseGroups,
                  onRemove: (exercise) {
                    return _removeExerciseFromWorkout(
                      context,
                      controller,
                      exercise,
                    );
                  },
                  onReorder: (orderedIds) {
                    unawaited(
                      controller.reorderWorkoutExercises(
                        workoutId: workout.id,
                        orderedWorkoutExerciseIds: orderedIds,
                      ),
                    );
                  },
                  onLinkAsSuperset: (first, second) {
                    return controller.linkWorkoutExercisesAsSuperset(
                      workoutId: workout.id,
                      firstWorkoutExerciseId: first.id,
                      secondWorkoutExerciseId: second.id,
                    );
                  },
                  onUnlinkFromSuperset: (first, second) {
                    return controller.unlinkWorkoutExercisesFromSuperset(
                      workoutId: workout.id,
                      firstWorkoutExerciseId: first.id,
                      secondWorkoutExerciseId: second.id,
                    );
                  },
                ),
              const SizedBox(height: AppDimens.base),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: WorkoutScreen.notesButtonKey(workout.id),
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => _WorkoutNotesScreen(workout: workout),
                      ),
                    );
                  },
                  icon: Icon(
                    workout.comment?.trim().isNotEmpty ?? false
                        ? Icons.sticky_note_2_outlined
                        : Icons.notes_outlined,
                  ),
                  label: Text(context.l10n.workoutNotesButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editWorkoutStartTime(
    BuildContext context,
    HomeController controller,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(workout.startedAt.toLocal()),
    );
    if (picked == null) {
      return;
    }

    final localDate = _workoutLocalDate(workout);
    final startedAt = localDate.atLocalTimeOf(_timeOfDayAsDateTime(picked));
    final endedAt = workout.endedAt?.toLocal();
    if (endedAt != null && !startedAt.isBefore(endedAt)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.workoutStartTimeAfterFinish)),
        );
      }
      return;
    }

    await controller.updateWorkoutStartedAt(
      workoutId: workout.id,
      startedAt: startedAt,
      localDate: localDate,
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.workoutStartTimeUpdated)),
    );
  }

  Future<void> _editWorkoutFinishTime(
    BuildContext context,
    HomeController controller,
  ) async {
    final currentEndedAt = workout.endedAt;
    if (currentEndedAt == null) {
      return;
    }
    final endedAtLocal = currentEndedAt.toLocal();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(endedAtLocal),
    );
    if (picked == null) {
      return;
    }

    final finishLocalDate = TrainingDayDate.fromDateTime(endedAtLocal);
    final endedAt = finishLocalDate.atLocalTimeOf(
      _timeOfDayAsDateTime(picked),
    );
    final startedAt = workout.startedAt.toLocal();
    if (!endedAt.isAfter(startedAt)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.workoutFinishTimeBeforeStart)),
        );
      }
      return;
    }

    await controller.updateWorkoutEndedAt(
      workoutId: workout.id,
      endedAt: endedAt,
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.workoutFinishTimeUpdated)),
    );
  }

  Future<void> _showExercisePicker(
    BuildContext context,
    HomeController controller,
  ) {
    // Guards the whole sheet lifetime: a rapid double-tap on a catalog row
    // fires ExerciseCatalogPicker's onTap twice before the first
    // addExerciseToWorkout await resolves. Without this, both selections
    // would add the exercise and auto-land, stacking two ExercisePage
    // routes for what the user experienced as one tap.
    var isAddingExercise = false;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.85,
              child: ExerciseCatalogPicker(
                onExerciseSelected: (exercise) {
                  if (isAddingExercise) {
                    return;
                  }
                  isAddingExercise = true;
                  unawaited(() async {
                    final workoutExerciseId =
                        await controller.addExerciseToWorkout(
                      workoutId: workout.id,
                      exerciseId: exercise.id,
                    );
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                    if (!context.mounted) {
                      return;
                    }
                    // Auto-land into the just-added exercise instead of
                    // leaving the user back on the workout card list.
                    Navigator.of(context).push(
                      buildExercisePageRoute(workoutExerciseId),
                    );
                  }());
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _copyWorkout(
    BuildContext context,
    HomeController controller,
  ) async {
    await controller.copyWorkout(workout.id);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.workoutCopied)),
    );
  }

  Future<void> _moveWorkout(
    BuildContext context,
    HomeController controller,
  ) async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: (workout.localDate ??
              TrainingDayDate.fromDateTime(workout.startedAt.toLocal()))
          .toLocalDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selectedDate == null) {
      return;
    }

    await controller.moveWorkout(
      workoutId: workout.id,
      localDate: TrainingDayDate.fromDateTime(selectedDate),
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.workoutMoved)),
    );
  }

  Future<void> _captureWorkoutAsTemplate(BuildContext context) async {
    final result = await showWorkoutCaptureSheet(
      context,
      workoutId: workout.id,
    );
    if (result == null || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.workoutCaptureSaved)),
    );
  }

  Future<void> _finishWorkout(
    BuildContext context,
    HomeController controller,
    WidgetRef ref,
  ) async {
    // Capture everything context-derived before the await: Finish pops this
    // screen back to Home, so the SnackBar (and, if diverged, the update
    // prompt) must be shown on state tied to the surviving Navigator, not to
    // this (about to be popped) context. `l10n` itself is safe to hold past
    // the pop — it's a plain resolved instance, not a live context view.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = context.l10n;
    final workoutId = workout.id;
    // Read (not watch): only touched when Finish is actually tapped, so
    // widget tests that never tap Finish never instantiate the real
    // Drift-backed repository behind this provider.
    final divergenceRepository = ref.read(
      templateDivergenceFeatureRepositoryProvider,
    );

    // Divergence is read from the Workout's facts as they stand right now;
    // finishing (setting endedAt) doesn't change them, so this can safely
    // happen before the write.
    final divergenceSummary =
        await divergenceRepository.summaryForWorkout(workoutId);

    await controller.finishWorkout(workoutId);
    if (!context.mounted) {
      return;
    }
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.workoutFinished),
        action: SnackBarAction(
          key: WorkoutScreen.finishedSnackBarShareActionKey(workoutId),
          label: l10n.workoutShareAction,
          onPressed: () {
            unawaited(
              _shareWorkoutSummary(
                messenger,
                controller,
                workoutId,
                l10n.homeWorkoutSummaryCopied,
              ),
            );
          },
        ),
      ),
    );

    // The update prompt joins Finish's pop-to-Home + Share moment only when
    // linked and diverged (ROUTINES.md §3.4) — never mid-workout, and never
    // when there's nothing to ask about.
    if (divergenceSummary == null || !divergenceSummary.hasDivergence) {
      return;
    }
    await _offerTemplateUpdate(
      navigator: navigator,
      messenger: messenger,
      l10n: l10n,
      divergenceRepository: divergenceRepository,
      summary: divergenceSummary,
    );
  }

  /// The overflow's "Update template" verb (ROUTINES.md §2, §3.4): available
  /// forever on any linked Workout, regardless of whether it has diverged —
  /// never automatic, always an explicit ask.
  Future<void> _updateWorkoutTemplate(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = context.l10n;
    final workoutId = workout.id;
    final divergenceRepository = ref.read(
      templateDivergenceFeatureRepositoryProvider,
    );

    final summary = await divergenceRepository.summaryForWorkout(workoutId);
    if (summary == null) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.templateUpdateNotLinkedMessage)),
      );
      return;
    }
    await _offerTemplateUpdate(
      navigator: navigator,
      messenger: messenger,
      l10n: l10n,
      divergenceRepository: divergenceRepository,
      summary: summary,
    );
  }

  /// Shared by the Finish prompt and the overflow verb: shows the update
  /// prompt, and — only on explicit confirmation — performs the atomic
  /// capture-replace write. Dismissing resolves `false` and writes nothing.
  Future<void> _offerTemplateUpdate({
    required NavigatorState navigator,
    required ScaffoldMessengerState messenger,
    required AppLocalizations l10n,
    required TemplateDivergenceFeatureRepository divergenceRepository,
    required TemplateDivergenceSummary summary,
  }) async {
    if (!navigator.mounted) {
      return;
    }
    final shouldUpdate = await showTemplateUpdatePromptDialog(
      navigator.context,
      summary: summary,
    );
    if (!shouldUpdate) {
      return;
    }
    await divergenceRepository.updateTemplateFromWorkout(summary.workoutId);
    if (!navigator.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.templateUpdateConfirmedMessage)),
    );
  }

  Future<void> _shareWorkout(
    BuildContext context,
    HomeController controller,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final copiedMessage = context.l10n.homeWorkoutSummaryCopied;
    await _shareWorkoutSummary(
        messenger, controller, workout.id, copiedMessage);
  }

  /// Shared by the overflow "Share Workout" action and the Finish snackbar's
  /// Share action. Takes a [ScaffoldMessengerState] rather than a
  /// [BuildContext] so it works even after the WorkoutScreen that started it
  /// has been popped (the Finish flow pops back to Home before this runs).
  Future<void> _shareWorkoutSummary(
    ScaffoldMessengerState messenger,
    HomeController controller,
    String workoutId,
    String copiedMessage,
  ) async {
    final summary = await controller.shareWorkout(workoutId);
    await Clipboard.setData(ClipboardData(text: summary));
    messenger.showSnackBar(
      SnackBar(content: Text(copiedMessage)),
    );
  }

  Future<void> _confirmDeleteWorkout(
    BuildContext context,
    HomeController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(context.l10n.workoutDeleteTitle),
          content: Text(context.l10n.workoutDeleteMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.l10n.cancelAction),
            ),
            FilledButton.icon(
              key: WorkoutScreen.deleteConfirmButtonKey(workout.id),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.delete_outline),
              label: Text(context.l10n.workoutDelete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    await controller.deleteWorkout(workout.id);
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<bool> _removeExerciseFromWorkout(
    BuildContext context,
    HomeController controller,
    HomeWorkoutExerciseSummary exercise,
  ) async {
    await controller.removeExerciseFromWorkout(
      workoutExerciseId: exercise.id,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.workoutExerciseRemoved)),
      );
    }
    return true;
  }
}

TrainingDayDate _workoutLocalDate(HomeWorkoutSummary workout) {
  return workout.localDate ??
      TrainingDayDate.fromDateTime(workout.startedAt.toLocal());
}

DateTime _timeOfDayAsDateTime(TimeOfDay time) {
  return DateTime(1970, 1, 1, time.hour, time.minute);
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive
        ? Theme.of(context).colorScheme.error
        : context.colors.textPrimary;
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: AppDimens.dense),
        Flexible(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}

class _WorkoutHeader extends StatelessWidget {
  const _WorkoutHeader({
    required this.workout,
    required this.onAddExercise,
    required this.onFinish,
    required this.onResume,
  });

  final HomeWorkoutSummary workout;
  final Future<void> Function() onAddExercise;
  final Future<void> Function() onFinish;
  final Future<void> Function() onResume;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: context.colors.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                  child: Text(
                    workout.isOpen
                        ? context.l10n.workoutOpenStatus
                        : context.l10n.workoutFinishedStatus,
                    style: context.textStyles.h2,
                  ),
                ),
                Text(
                  _formatWorkoutDuration(context.l10n, workout.duration),
                  style: context.textStyles.body.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.dense),
            Text(
              _formatWorkoutTimeRange(context, workout),
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppDimens.base),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: WorkoutScreen.addExerciseButtonKey(workout.id),
                onPressed: () => unawaited(onAddExercise()),
                icon: const Icon(Icons.add),
                label: Text(context.l10n.homeAddExercise),
              ),
            ),
            const SizedBox(height: AppDimens.dense),
            SizedBox(
              width: double.infinity,
              child: workout.isOpen
                  ? OutlinedButton.icon(
                      key: WorkoutScreen.finishButtonKey(workout.id),
                      onPressed: () => unawaited(onFinish()),
                      icon: const Icon(Icons.flag_outlined),
                      label: Text(context.l10n.workoutFinish),
                    )
                  : OutlinedButton.icon(
                      key: WorkoutScreen.resumeButtonKey(workout.id),
                      onPressed: () => unawaited(onResume()),
                      icon: const Icon(Icons.play_arrow_outlined),
                      label: Text(context.l10n.workoutResume),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutExerciseList extends StatefulWidget {
  const _WorkoutExerciseList({
    required this.exercises,
    required this.exerciseGroups,
    required this.onRemove,
    required this.onReorder,
    required this.onLinkAsSuperset,
    required this.onUnlinkFromSuperset,
  });

  final List<HomeWorkoutExerciseSummary> exercises;
  final List<HomeExerciseGroupSummary> exerciseGroups;
  final Future<bool> Function(HomeWorkoutExerciseSummary exercise) onRemove;
  final ValueChanged<List<String>> onReorder;
  final Future<void> Function(
    HomeWorkoutExerciseSummary first,
    HomeWorkoutExerciseSummary second,
  ) onLinkAsSuperset;
  final Future<void> Function(
    HomeWorkoutExerciseSummary first,
    HomeWorkoutExerciseSummary second,
  ) onUnlinkFromSuperset;

  @override
  State<_WorkoutExerciseList> createState() => _WorkoutExerciseListState();
}

class _WorkoutExerciseListState extends State<_WorkoutExerciseList> {
  String? _armedDragExerciseId;

  @override
  Widget build(BuildContext context) {
    final groupByWorkoutExerciseId = <String, HomeExerciseGroupSummary>{
      for (final group in widget.exerciseGroups)
        for (final workoutExerciseId in group.workoutExerciseIds)
          workoutExerciseId: group,
    };
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.exercises.length,
      onReorderItem: (oldIndex, newIndex) {
        if (newIndex == oldIndex) {
          return;
        }

        final reordered = List<HomeWorkoutExerciseSummary>.of(widget.exercises);
        final moved = reordered.removeAt(oldIndex);
        reordered.insert(newIndex, moved);
        widget.onReorder(
          reordered.map((exercise) => exercise.id).toList(growable: false),
        );
        _clearArmedDragExercise();
      },
      itemBuilder: (context, index) {
        final exercise = widget.exercises[index];
        final exerciseGroup = groupByWorkoutExerciseId[exercise.id];
        final nextExercise = index + 1 < widget.exercises.length
            ? widget.exercises[index + 1]
            : null;
        final nextExerciseGroup = nextExercise == null
            ? null
            : groupByWorkoutExerciseId[nextExercise.id];
        final linkedGroup =
            exerciseGroup?.id == nextExerciseGroup?.id ? exerciseGroup : null;
        return Padding(
          key: ValueKey<String>('workout.exercise.${exercise.id}.row'),
          padding: EdgeInsets.only(
            bottom: nextExercise == null ? 0 : AppDimens.dense,
          ),
          child: Column(
            children: [
              Dismissible(
                key: WorkoutScreen.exerciseDismissibleKey(exercise.id),
                direction: DismissDirection.startToEnd,
                background:
                    _WorkoutExerciseDeleteBackground(exercise: exercise),
                confirmDismiss: (direction) {
                  if (direction != DismissDirection.startToEnd) {
                    return Future<bool>.value(false);
                  }
                  return widget.onRemove(exercise);
                },
                child: _WorkoutExerciseCard(
                  exercise: exercise,
                  exerciseGroup: exerciseGroup,
                  index: index,
                  isDragArmed: _armedDragExerciseId == exercise.id,
                  onDragHandleDown: () => _setArmedDragExercise(exercise.id),
                  onDragHandleRelease: _clearArmedDragExercise,
                ),
              ),
              if (nextExercise != null)
                SizedBox(
                  height: AppDimens.touchTarget,
                  child: IconButton(
                    tooltip: linkedGroup == null
                        ? context.l10n.workoutLinkSupersetTooltip(
                            exercise.name,
                            nextExercise.name,
                          )
                        : context.l10n.workoutUnlinkSupersetTooltip(
                            exercise.name,
                            nextExercise.name,
                            linkedGroup.name,
                          ),
                    onPressed: () => unawaited(
                      _changeSupersetLink(
                        first: exercise,
                        second: nextExercise,
                        unlink: linkedGroup != null,
                      ),
                    ),
                    icon: Icon(
                      linkedGroup == null ? Icons.link_off : Icons.link,
                      color: linkedGroup == null
                          ? context.colors.textSecondary
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _setArmedDragExercise(String exerciseId) {
    if (_armedDragExerciseId == exerciseId) {
      return;
    }
    setState(() {
      _armedDragExerciseId = exerciseId;
    });
  }

  void _clearArmedDragExercise() {
    if (_armedDragExerciseId == null || !mounted) {
      return;
    }
    setState(() {
      _armedDragExerciseId = null;
    });
  }

  Future<void> _changeSupersetLink({
    required HomeWorkoutExerciseSummary first,
    required HomeWorkoutExerciseSummary second,
    required bool unlink,
  }) async {
    try {
      if (unlink) {
        await widget.onUnlinkFromSuperset(first, second);
      } else {
        await widget.onLinkAsSuperset(first, second);
      }
    } on Object {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.workoutSupersetUpdateFailed)),
      );
    }
  }
}

class _WorkoutExerciseDeleteBackground extends StatelessWidget {
  const _WorkoutExerciseDeleteBackground({
    required this.exercise,
  });

  final HomeWorkoutExerciseSummary exercise;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: WorkoutScreen.exerciseDeleteBackgroundKey(exercise.id),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: AppDimens.base),
          child: Semantics(
            label: context.l10n.workoutRemoveExerciseTooltip,
            child: const Icon(
              Icons.delete_outline,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkoutExerciseCard extends StatelessWidget {
  const _WorkoutExerciseCard({
    required this.exercise,
    required this.exerciseGroup,
    required this.index,
    required this.isDragArmed,
    required this.onDragHandleDown,
    required this.onDragHandleRelease,
  });

  final HomeWorkoutExerciseSummary exercise;
  final HomeExerciseGroupSummary? exerciseGroup;
  final int index;
  final bool isDragArmed;
  final VoidCallback onDragHandleDown;
  final VoidCallback onDragHandleRelease;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cardColor = isDragArmed
        ? Color.alphaBlend(
            colorScheme.primary.withValues(alpha: 0.12),
            context.colors.surface,
          )
        : context.colors.surface;
    final borderColor =
        isDragArmed ? colorScheme.primary : context.colors.divider;
    return Material(
      key: WorkoutScreen.exerciseCardKey(exercise.id),
      color: cardColor,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: borderColor,
          width: isDragArmed ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  key: WorkoutScreen.openExerciseButtonKey(exercise.id),
                  onTap: () {
                    Navigator.of(context).push(
                      buildExercisePageRoute(exercise.id),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.base,
                      vertical: AppDimens.dense,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            exercise.name,
                            style: context.textStyles.h2,
                          ),
                        ),
                        const SizedBox(width: AppDimens.dense),
                        Text(
                          _formatSetCount(
                            context.l10n,
                            exercise.setCount,
                          ),
                          style: context.textStyles.label.copyWith(
                            color: context.colors.textSecondary,
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
              Listener(
                onPointerDown: (_) => onDragHandleDown(),
                onPointerUp: (_) => onDragHandleRelease(),
                onPointerCancel: (_) => onDragHandleRelease(),
                child: ReorderableDragStartListener(
                  index: index,
                  child: Semantics(
                    button: true,
                    label: context.l10n.workoutReorderExerciseTooltip,
                    child: SizedBox(
                      key: WorkoutScreen.reorderExerciseHandleKey(exercise.id),
                      width: AppDimens.touchTarget,
                      height: AppDimens.touchTarget,
                      child: Center(
                        child: Icon(
                          Icons.drag_handle,
                          color: isDragArmed
                              ? colorScheme.primary
                              : context.colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (exerciseGroup != null)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Semantics(
                label: context.l10n.trainingExerciseGroupIndicator(
                  exerciseGroup!.name,
                ),
                child: ColoredBox(
                  color: colorFromHex(
                    exerciseGroup!.colorHex,
                    fallback: context.colors.categoryColor('other'),
                  ),
                  child: const SizedBox(width: AppDimens.supersetBar),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WorkoutNotesScreen extends ConsumerStatefulWidget {
  const _WorkoutNotesScreen({
    required this.workout,
  });

  final HomeWorkoutSummary workout;

  @override
  ConsumerState<_WorkoutNotesScreen> createState() =>
      _WorkoutNotesScreenState();
}

class _WorkoutNotesScreenState extends ConsumerState<_WorkoutNotesScreen> {
  late final TextEditingController _controller;
  late bool _hasPersistedNote;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.workout.comment ?? '');
    _hasPersistedNote = _controller.text.trim().isNotEmpty;
  }

  @override
  void didUpdateWidget(covariant _WorkoutNotesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workout.id != widget.workout.id ||
        oldWidget.workout.comment != widget.workout.comment) {
      _controller.text = widget.workout.comment ?? '';
      _hasPersistedNote = _controller.text.trim().isNotEmpty;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.workoutNotesTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: TextField(
                  key: WorkoutScreen.notesFieldKey(widget.workout.id),
                  controller: _controller,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  keyboardType: TextInputType.multiline,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    labelText: context.l10n.homeWorkoutCommentLabel,
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: AppDimens.base),
              Row(
                children: [
                  if (_hasPersistedNote)
                    OutlinedButton.icon(
                      key: WorkoutScreen.deleteNotesButtonKey(
                        widget.workout.id,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: errorColor,
                        side: BorderSide(color: errorColor),
                      ),
                      onPressed: () => unawaited(_deleteNote(context)),
                      icon: const Icon(Icons.delete_outline),
                      label: Text(context.l10n.workoutDeleteNote),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    key: WorkoutScreen.saveNotesButtonKey(widget.workout.id),
                    onPressed: () => unawaited(_saveNote(context)),
                    icon: const Icon(Icons.save_outlined),
                    label: Text(context.l10n.workoutSaveNote),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveNote(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final savedMessage = context.l10n.workoutNoteSaved;
    final text = _controller.text.trim();
    await ref.read(homeControllerProvider.notifier).updateWorkoutComment(
          workoutId: widget.workout.id,
          comment: text.isEmpty ? null : text,
        );
    if (!mounted) {
      return;
    }
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text(savedMessage)),
    );
  }

  Future<void> _deleteNote(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final deletedMessage = context.l10n.workoutNoteDeleted;
    await ref.read(homeControllerProvider.notifier).updateWorkoutComment(
          workoutId: widget.workout.id,
          comment: null,
        );
    if (!mounted) {
      return;
    }
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text(deletedMessage)),
    );
  }
}

String _formatWorkoutTimeRange(
  BuildContext context,
  HomeWorkoutSummary workout,
) {
  final localizations = MaterialLocalizations.of(context);
  final started = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(workout.startedAt.toLocal()),
  );
  final endedAt = workout.endedAt;
  if (endedAt == null) {
    return context.l10n.workoutStartedAt(started);
  }

  final ended = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(endedAt.toLocal()),
  );
  return context.l10n.workoutTimeRange(started, ended);
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

String _formatSetCount(AppLocalizations l10n, int count) {
  return switch (count) {
    0 => l10n.workoutNoSets,
    1 => l10n.workoutOneSet,
    _ => l10n.workoutSetCount(count),
  };
}
