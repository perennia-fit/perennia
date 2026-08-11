import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/analytics/exercise_analytics.dart';
import '../../../domain/training/training_dimensions.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../analytics/repositories/exercise_analytics_repository.dart';
import '../../analytics/widgets/exercise_overview_screen.dart';
import '../../catalog/widgets/exercise_catalog_picker.dart';
import '../../settings/repositories/settings_repository.dart';
import '../services/timer_background_scheduler.dart';

final restTimerAlertProvider = Provider<RestTimerAlert>(
  (ref) => const SystemRestTimerAlert(),
);

abstract interface class RestTimerAlert {
  /// The end cue: rest/interval bout is over.
  Future<void> fire(double volume);

  /// The 3-2-1 prepare cue: rest ends soon (remaining <= 3s). A lighter,
  /// distinct signal from [fire] so the two are never confused.
  Future<void> firePrepare(double volume);
}

class SystemRestTimerAlert implements RestTimerAlert {
  const SystemRestTimerAlert();

  @override
  Future<void> fire(double volume) async {
    await HapticFeedback.vibrate();
    if (volume > 0) {
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  @override
  Future<void> firePrepare(double volume) async {
    // Lighter than the end cue: a selection click + a short click tone, paired
    // so vibration is never the sole signal. Sound honors the volume slider;
    // the platform still respects silent mode / DND.
    await HapticFeedback.selectionClick();
    if (volume > 0) {
      await SystemSound.play(SystemSoundType.click);
    }
  }
}

Future<TimerBackgroundPermissionStatus> _scheduleRestBackgroundTimer(
  WidgetRef ref,
  RestTimerRecord timer, {
  String? workoutExerciseId,
  required bool soundEnabled,
}) {
  return ref.read(timerBackgroundSchedulerProvider).schedule(
        TimerBackgroundSchedule.rest(
          timer,
          workoutExerciseId: workoutExerciseId,
          soundEnabled: soundEnabled,
        ),
      );
}

void _notifyIfBackgroundAlertsDenied(
  BuildContext context,
  TimerBackgroundPermissionStatus status,
) {
  if (status != TimerBackgroundPermissionStatus.denied || !context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        context.l10n.trainingBackgroundAlertsDenied,
      ),
    ),
  );
}

class TrainingScreen extends ConsumerStatefulWidget {
  const TrainingScreen({
    super.key,
    required this.workoutExerciseId,
    this.initialWorkoutExercise,
    this.initialExercise,
    this.initialPriorSet,
    this.setsStream,
    this.recordSetIdsStream,
    this.enableRestTimerTicker = true,
  });

  final String workoutExerciseId;
  final WorkoutExerciseRecord? initialWorkoutExercise;
  final ExerciseRecord? initialExercise;
  final LoggedSetRecord? initialPriorSet;
  final Stream<List<LoggedSetRecord>>? setsStream;
  final Stream<Set<String>>? recordSetIdsStream;
  final bool enableRestTimerTicker;

  static const saveSetButtonKey = Key('training.saveSet');
  static const saveSetConfirmationKey = Key('training.saveSet.confirmation');
  static const commentFieldKey = Key('training.comment');
  static const sideFieldKey = Key('training.side');
  static const rpeFieldKey = Key('training.rpe');
  static const durationHoursFieldKey = Key('training.dimension.duration.hours');
  static const durationMinutesFieldKey =
      Key('training.dimension.duration.minutes');
  static const durationSecondsFieldKey =
      Key('training.dimension.duration.seconds');
  static const navigationPanelButtonKey = Key('training.navigation.open');
  static const navigationPanelKey = Key('training.navigation.panel');
  static const addExerciseButtonKey = Key('training.navigation.addExercise');
  static const createGroupButtonKey = Key('training.navigation.createGroup');
  static const saveGroupButtonKey = Key('training.navigation.saveGroup');
  static const groupNameFieldKey = Key('training.navigation.groupName');
  static const groupColorFieldKey = Key('training.navigation.groupColor');
  static const restTimerPanelKey = Key('training.restTimer.panel');
  static const restTimerDurationFieldKey = Key('training.restTimer.duration');
  static const restTimerStartButtonKey = Key('training.restTimer.start');
  static const restTimerCancelButtonKey = Key('training.restTimer.cancel');
  static const restTimerVolumeSliderKey = Key('training.restTimer.volume');

  static Key navigationItemKey(String workoutExerciseId) {
    return Key('training.navigation.exercise.$workoutExerciseId');
  }

  static Key overviewButtonKey(String workoutExerciseId) {
    return Key('training.navigation.exercise.$workoutExerciseId.overview');
  }

  static Key groupMemberCheckboxKey(String workoutExerciseId) {
    return Key('training.navigation.groupMember.$workoutExerciseId');
  }

  static Key editGroupButtonKey(String groupId) {
    return Key('training.navigation.group.$groupId.edit');
  }

  static Key dimensionFieldKey(DimensionId dimension) {
    return Key('training.dimension.${dimension.name}');
  }

  static Key decrementButtonKey(DimensionId dimension) {
    return Key('training.dimension.${dimension.name}.decrement');
  }

  static Key incrementButtonKey(DimensionId dimension) {
    return Key('training.dimension.${dimension.name}.increment');
  }

  static Key setTileKey(String setId) {
    return Key('training.set.$setId');
  }

  static Key recordTrophyKey(String setId) {
    return Key('training.set.$setId.recordTrophy');
  }

  static Key editSetButtonKey(String setId) {
    return Key('training.set.$setId.edit');
  }

  static Key deleteSetButtonKey(String setId) {
    return Key('training.set.$setId.delete');
  }

  static Key completeSetCheckboxKey(String setId) {
    return Key('training.set.$setId.complete');
  }

  static Key reorderHandleKey(String setId) {
    return Key('training.set.$setId.reorder');
  }

  static Key editDimensionFieldKey(String setId, DimensionId dimension) {
    return Key('training.set.$setId.dimension.${dimension.name}');
  }

  static Key editDurationHoursFieldKey(String setId) {
    return Key('training.set.$setId.dimension.duration.hours');
  }

  static Key editDurationMinutesFieldKey(String setId) {
    return Key('training.set.$setId.dimension.duration.minutes');
  }

  static Key editDurationSecondsFieldKey(String setId) {
    return Key('training.set.$setId.dimension.duration.seconds');
  }

  static Key editCommentFieldKey(String setId) {
    return Key('training.set.$setId.comment');
  }

  static Key editSideFieldKey(String setId) {
    return Key('training.set.$setId.side');
  }

  static Key editRpeFieldKey(String setId) {
    return Key('training.set.$setId.rpe');
  }

  static Key saveEditButtonKey(String setId) {
    return Key('training.set.$setId.saveEdit');
  }

  @override
  ConsumerState<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends ConsumerState<TrainingScreen> {
  late Future<_TrainingExerciseState> _stateFuture;
  late String _activeWorkoutExerciseId;
  Stream<List<LoggedSetRecord>>? _overrideSetsStream;
  Stream<Set<String>>? _overrideRecordSetIdsStream;
  final _controllers = <DimensionId, TextEditingController>{};
  final _commentController = TextEditingController();
  final _rpeController = TextEditingController();
  SetSide _selectedSide = SetSide.left;
  String? _populatedWorkoutExerciseId;
  int _restTimerRevision = 0;

  @override
  void initState() {
    super.initState();
    _activeWorkoutExerciseId = widget.workoutExerciseId;
    _overrideSetsStream = widget.setsStream?.asBroadcastStream();
    _overrideRecordSetIdsStream =
        widget.recordSetIdsStream?.asBroadcastStream();
    final initialWorkoutExercise = widget.initialWorkoutExercise;
    final initialExercise = widget.initialExercise;
    if (initialWorkoutExercise != null && initialExercise != null) {
      _stateFuture = Future<_TrainingExerciseState>.value(
        _TrainingExerciseState(
          workoutExercise: initialWorkoutExercise,
          exercise: initialExercise,
          priorSet: widget.initialPriorSet,
        ),
      );
    } else {
      _stateFuture = _loadState(_activeWorkoutExerciseId);
    }
  }

  @override
  void didUpdateWidget(covariant TrainingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workoutExerciseId == widget.workoutExerciseId) {
      if (oldWidget.setsStream != widget.setsStream) {
        _overrideSetsStream = widget.setsStream?.asBroadcastStream();
      }
      if (oldWidget.recordSetIdsStream != widget.recordSetIdsStream) {
        _overrideRecordSetIdsStream =
            widget.recordSetIdsStream?.asBroadcastStream();
      }
      return;
    }

    _activeWorkoutExerciseId = widget.workoutExerciseId;
    _overrideSetsStream = widget.setsStream?.asBroadcastStream();
    _overrideRecordSetIdsStream =
        widget.recordSetIdsStream?.asBroadcastStream();
    _populatedWorkoutExerciseId = null;
    _stateFuture = _loadState(_activeWorkoutExerciseId);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _commentController.dispose();
    _rpeController.dispose();
    super.dispose();
  }

  Future<_TrainingExerciseState> _loadState(String workoutExerciseId) async {
    final repositories = ref.read(trainingRepositoriesProvider);
    final workoutExercise =
        await repositories.workoutExercises.getById(workoutExerciseId);
    if (workoutExercise == null) {
      throw StateError('Workout exercise not found.');
    }

    final exercise = await repositories.exercises.getById(
      workoutExercise.exerciseId,
    );
    if (exercise == null) {
      throw StateError('Exercise not found.');
    }

    final priorSet = await repositories.sets.findLatestPriorForExercise(
      exerciseId: workoutExercise.exerciseId,
      beforeWorkoutId: workoutExercise.workoutId,
      dimensions: exercise.type.dimensions,
    );

    return _TrainingExerciseState(
      workoutExercise: workoutExercise,
      exercise: exercise,
      priorSet: priorSet,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_TrainingExerciseState>(
      future: _stateFuture,
      builder: (context, snapshot) {
        // Gate on data-presence, not connectionState: swapping `_stateFuture`
        // on auto-select-next-set (after every save) makes FutureBuilder emit a
        // transient non-done frame, but it preserves `snapshot.data` across the
        // swap. Rendering the last-known state keeps `_RestTimerPanel` mounted
        // so its `Timer.periodic` ticker survives the exercise switch;
        // switching on connectionState fell to `SizedBox.expand()`
        // and cancelled it. A genuine load failure with no prior state still
        // surfaces the unavailable text.
        final state = snapshot.data;
        final hasError = snapshot.connectionState == ConnectionState.done &&
            snapshot.hasError &&
            state == null;
        return Scaffold(
          appBar: AppBar(
            title: Text(
                state?.exercise.name ?? context.l10n.trainingFallbackTitle),
            actions: [
              Builder(
                builder: (context) {
                  return IconButton(
                    key: TrainingScreen.navigationPanelButtonKey,
                    tooltip: context.l10n.trainingOpenNavigationTooltip,
                    onPressed: state == null
                        ? null
                        : () => Scaffold.of(context).openEndDrawer(),
                    icon: const Icon(Icons.menu_open),
                  );
                },
              ),
            ],
          ),
          endDrawer: state == null
              ? null
              : _NavigationPanelDrawer(
                  workoutId: state.workoutExercise.workoutId,
                  activeWorkoutExerciseId: state.workoutExercise.id,
                  onWorkoutExerciseSelected: _selectWorkoutExercise,
                  onExerciseAdded: _selectWorkoutExercise,
                ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppDimens.base),
              child: switch ((hasError, state)) {
                (true, _) => Text(
                    context.l10n.trainingUnavailable,
                    style: context.textStyles.body.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                (_, final state?) => _buildTrainingForm(state),
                _ => const SizedBox.expand(),
              },
            ),
          ),
        );
      },
    );
  }

  void _selectWorkoutExercise(String workoutExerciseId) {
    if (workoutExerciseId == _activeWorkoutExerciseId) {
      return;
    }

    setState(() {
      _activeWorkoutExerciseId = workoutExerciseId;
      _populatedWorkoutExerciseId = null;
      _commentController.clear();
      _rpeController.clear();
      _selectedSide = SetSide.left;
      _stateFuture = _loadState(workoutExerciseId);
    });
  }

  Widget _buildTrainingForm(_TrainingExerciseState state) {
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings.defaults;
    final overrideRecordSetIdsStream = _overrideRecordSetIdsStream;
    if (overrideRecordSetIdsStream != null) {
      return StreamBuilder<Set<String>>(
        stream: overrideRecordSetIdsStream,
        initialData: const <String>{},
        builder: (context, snapshot) {
          return _buildTrainingFormContent(
            state,
            settings: settings,
            recordSetIds: settings.prTrackingEnabled
                ? snapshot.data ?? const <String>{}
                : const <String>{},
          );
        },
      );
    }

    final recordSetIds = ref
        .watch(exerciseAnalyticsControllerProvider(state.exercise.id))
        .maybeWhen(
          data: _headlineRecordSetIds,
          orElse: () => const <String>{},
        );
    return _buildTrainingFormContent(
      state,
      settings: settings,
      recordSetIds:
          settings.prTrackingEnabled ? recordSetIds : const <String>{},
    );
  }

  Widget _buildTrainingFormContent(
    _TrainingExerciseState state, {
    required AppSettings settings,
    required Set<String> recordSetIds,
  }) {
    _populateEntryControllers(state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RestTimerPanel(
          workoutId: state.workoutExercise.workoutId,
          workoutExerciseId: state.workoutExercise.id,
          enableTicker: widget.enableRestTimerTicker,
          revision: _restTimerRevision,
        ),
        const SizedBox(height: AppDimens.dense),
        Expanded(
          child: _TrainingForm(
            state: state,
            controllers: _controllers,
            commentController: _commentController,
            rpeController: _rpeController,
            selectedSide: _selectedSide,
            sets: _watchSets(state),
            recordSetIds: recordSetIds,
            settings: settings,
            onSave: () => _saveSet(state, settings),
            onStep: _stepDimension,
            onSideChanged: (side) {
              setState(() => _selectedSide = side);
            },
            onEdit: (set) => _editSet(state, set, settings),
            onDelete: _deleteSet,
            onSetCompleted: (set, isCompleted) =>
                _setCompleted(state, settings, set, isCompleted),
            onReorder: (sets) => _reorderSets(state, sets),
          ),
        ),
      ],
    );
  }

  void _populateEntryControllers(_TrainingExerciseState state) {
    if (_populatedWorkoutExerciseId == state.workoutExercise.id) {
      return;
    }

    _populatedWorkoutExerciseId = state.workoutExercise.id;
    _setDimensionControllerDefaults(state.exercise, state.priorSet?.values);
  }

  void _setDimensionControllerDefaults(
    ExerciseRecord exercise,
    LoggedSet? values,
  ) {
    for (final dimension in exercise.type.dimensions) {
      final controller = _controllers.putIfAbsent(
        dimension,
        TextEditingController.new,
      );
      controller.text = values?.valueFor(dimension)?.entered ?? '';
    }
  }

  Stream<List<LoggedSetRecord>> _watchSets(_TrainingExerciseState state) {
    final setsStream = _overrideSetsStream;
    if (setsStream != null) {
      return setsStream;
    }

    final repositories = ref.read(trainingRepositoriesProvider);
    return repositories.sets
        .watchActiveForWorkout(state.workoutExercise.workoutId)
        .map(
          (sets) => sets
              .where(
                  (set) => set.exerciseId == state.workoutExercise.exerciseId)
              .toList(growable: false),
        );
  }

  Future<void> _saveSet(
    _TrainingExerciseState state,
    AppSettings settings,
  ) async {
    final values = _valuesFromControllers(
      controllers: _controllers,
      exercise: state.exercise,
      unitSystem: settings.unitSystem,
    );
    if (values == null) {
      return;
    }

    _showSetSavedConfirmation();

    final repositories = ref.read(trainingRepositoriesProvider);
    final nextPosition = await repositories.sets.nextPositionForWorkout(
      state.workoutExercise.workoutId,
    );

    final setId = await repositories.sets.create(
      LoggedSetDraft(
        workoutId: state.workoutExercise.workoutId,
        exerciseId: state.workoutExercise.exerciseId,
        position: nextPosition,
        values: values,
        isCompleted: true,
        comment: _commentController.text,
        side: state.exercise.isUnilateral ? _selectedSide : null,
        rpe: state.exercise.usesRpe ? _rpeFromController(_rpeController) : null,
      ),
    );
    final createdSet = await repositories.sets.getById(setId);
    if (createdSet != null) {
      final timerId = await repositories.restTimers.startForSet(createdSet);
      final timer = await repositories.restTimers.getById(timerId);
      if (timer != null) {
        _scheduleRestBackgroundTimerWithoutBlocking(
          timer,
          workoutExerciseId: state.workoutExercise.id,
          soundEnabled: settings.restTimerSoundsEnabled,
        );
      }
      _notifyRestTimerChanged();
    }
    final nextWorkoutExerciseId =
        await repositories.exerciseGroups.findNextWorkoutExerciseIdAfter(
      state.workoutExercise.id,
    );

    _setDimensionControllerDefaults(state.exercise, values);
    _commentController.clear();
    _rpeController.clear();
    setState(() {
      if (state.exercise.isUnilateral) {
        _selectedSide = _nextSide(_selectedSide);
      }
    });
    FocusManager.instance.primaryFocus?.unfocus();
    if (settings.autoSelectNextSet &&
        nextWorkoutExerciseId != null &&
        mounted) {
      _selectWorkoutExercise(nextWorkoutExerciseId);
    }
  }

  void _showSetSavedConfirmation() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: TrainingScreen.saveSetConfirmationKey,
          content: Text(context.l10n.trainingSetSaved),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(
            AppDimens.base * 2,
            AppDimens.base * 2,
            AppDimens.base * 2,
            AppDimens.base * 12,
          ),
        ),
      );
  }

  void _stepDimension(DimensionId dimension, double delta) {
    final controller = _controllers.putIfAbsent(
      dimension,
      TextEditingController.new,
    );
    final currentValue = double.tryParse(controller.text.trim()) ?? 0;
    final nextValue = (currentValue + delta).clamp(0, double.infinity);
    controller.text = _formatEnteredNumber(nextValue);
  }

  Future<void> _editSet(
    _TrainingExerciseState state,
    LoggedSetRecord set,
    AppSettings settings,
  ) async {
    final initialValues = <DimensionId, String>{
      for (final dimension in state.exercise.type.dimensions)
        dimension: set.values.valueFor(dimension)?.entered ?? '',
    };

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _EditSetSheet(
          set: set,
          exercise: state.exercise,
          unitSystem: settings.unitSystem,
          initialValues: initialValues,
          onSave: (edit) async {
            final sets = ref.read(trainingRepositoriesProvider).sets;
            await sets.updateValues(
              set.id,
              values: edit.values,
            );
            await sets.updateAnnotations(
              set.id,
              comment: edit.comment,
              side: state.exercise.isUnilateral ? edit.side : null,
              rpe: state.exercise.usesRpe ? edit.rpe : null,
            );
            if (sheetContext.mounted) {
              Navigator.of(sheetContext).pop();
            }
          },
        );
      },
    );
  }

  Future<void> _deleteSet(LoggedSetRecord set) {
    return ref.read(trainingRepositoriesProvider).sets.softDelete(set.id);
  }

  Future<void> _setCompleted(
    _TrainingExerciseState state,
    AppSettings settings,
    LoggedSetRecord set,
    bool isCompleted,
  ) async {
    final repositories = ref.read(trainingRepositoriesProvider);
    await repositories.sets.setCompleted(
      set.id,
      isCompleted: isCompleted,
    );
    if (!isCompleted) {
      return;
    }

    final completedSet = await repositories.sets.getById(set.id);
    if (completedSet != null) {
      final timerId = await repositories.restTimers.startForSet(completedSet);
      final timer = await repositories.restTimers.getById(timerId);
      if (timer != null) {
        _scheduleRestBackgroundTimerWithoutBlocking(
          timer,
          workoutExerciseId: state.workoutExercise.id,
          soundEnabled: settings.restTimerSoundsEnabled,
        );
      }
      _notifyRestTimerChanged();
    }
  }

  void _scheduleRestBackgroundTimerWithoutBlocking(
    RestTimerRecord timer, {
    required String workoutExerciseId,
    required bool soundEnabled,
  }) {
    unawaited(
      _scheduleRestBackgroundTimer(
        ref,
        timer,
        workoutExerciseId: workoutExerciseId,
        soundEnabled: soundEnabled,
      ).then((status) {
        if (mounted) {
          _notifyIfBackgroundAlertsDenied(context, status);
        }
      }),
    );
  }

  void _notifyRestTimerChanged() {
    if (mounted) {
      setState(() => _restTimerRevision += 1);
    }
  }

  Future<void> _reorderSets(
    _TrainingExerciseState state,
    List<LoggedSetRecord> sets,
  ) {
    return ref
        .read(trainingRepositoriesProvider)
        .sets
        .reorderForWorkoutExercise(
          workoutId: state.workoutExercise.workoutId,
          exerciseId: state.workoutExercise.exerciseId,
          orderedIds: sets.map((set) => set.id).toList(growable: false),
        );
  }
}

class _NavigationPanelDrawer extends ConsumerStatefulWidget {
  const _NavigationPanelDrawer({
    required this.workoutId,
    required this.activeWorkoutExerciseId,
    required this.onWorkoutExerciseSelected,
    required this.onExerciseAdded,
  });

  final String workoutId;
  final String activeWorkoutExerciseId;
  final ValueChanged<String> onWorkoutExerciseSelected;
  final ValueChanged<String> onExerciseAdded;

  @override
  ConsumerState<_NavigationPanelDrawer> createState() =>
      _NavigationPanelDrawerState();
}

class _NavigationPanelDrawerState
    extends ConsumerState<_NavigationPanelDrawer> {
  late Stream<_NavigationPanelModel> _panelStream;
  final _groupNameController = TextEditingController();
  final _groupColorController = TextEditingController(text: '#2F6FED');
  final _selectedWorkoutExerciseIds = <String>{};
  String? _editingGroupId;
  bool _showGroupForm = false;

  @override
  void initState() {
    super.initState();
    _panelStream = _watchNavigationPanel(
      ref.read(trainingRepositoriesProvider),
      widget.workoutId,
    );
  }

  @override
  void didUpdateWidget(covariant _NavigationPanelDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workoutId != widget.workoutId) {
      _panelStream = _watchNavigationPanel(
        ref.read(trainingRepositoriesProvider),
        widget.workoutId,
      );
      _clearGroupForm();
    }
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _groupColorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Drawer(
      key: TrainingScreen.navigationPanelKey,
      child: SafeArea(
        child: StreamBuilder<_NavigationPanelModel>(
          stream: _panelStream,
          builder: (context, snapshot) {
            final model = snapshot.data;
            if (model == null) {
              return const SizedBox.expand();
            }

            return ListView(
              padding: const EdgeInsets.all(AppDimens.base),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.trainingExercisesTitle,
                        style: context.textStyles.h2,
                      ),
                    ),
                    IconButton(
                      key: TrainingScreen.addExerciseButtonKey,
                      tooltip: l10n.homeAddExercise,
                      onPressed: () => unawaited(_showExercisePicker()),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: AppDimens.dense),
                if (model.items.isEmpty)
                  Text(
                    l10n.trainingNoExercisesYet,
                    style: context.textStyles.body.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  )
                else
                  for (final item in model.items)
                    _NavigationExerciseTile(
                      item: item,
                      isSelected: item.workoutExercise.id ==
                          widget.activeWorkoutExerciseId,
                      onOverview: () {
                        final navigator = Navigator.of(context);
                        navigator.pop();
                        unawaited(
                          navigator.push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => ExerciseOverviewScreen(
                                exerciseId: item.exercise.id,
                              ),
                            ),
                          ),
                        );
                      },
                      onTap: () {
                        widget.onWorkoutExerciseSelected(
                          item.workoutExercise.id,
                        );
                        Navigator.of(context).pop();
                      },
                    ),
                const Divider(height: AppDimens.base * 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.trainingGroupsTitle,
                        style: context.textStyles.h2,
                      ),
                    ),
                    if (!_showGroupForm)
                      IconButton(
                        key: TrainingScreen.createGroupButtonKey,
                        tooltip: l10n.trainingCreateGroupTooltip,
                        onPressed: () => setState(_startGroupCreate),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                  ],
                ),
                if (model.groups.isEmpty && !_showGroupForm)
                  Text(
                    l10n.trainingNoGroupsYet,
                    style: context.textStyles.body.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                for (final group in model.groups)
                  _ExerciseGroupTile(
                    group: group,
                    onEdit: () => setState(() => _startGroupEdit(group)),
                  ),
                if (_showGroupForm) ...[
                  const SizedBox(height: AppDimens.base),
                  _ExerciseGroupForm(
                    items: model.items,
                    nameController: _groupNameController,
                    colorController: _groupColorController,
                    selectedWorkoutExerciseIds: _selectedWorkoutExerciseIds,
                    onMemberChanged: _setMemberSelected,
                    onCancel: () => setState(_clearGroupForm),
                    onSave: () => unawaited(_saveGroup()),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  void _startGroupCreate() {
    _editingGroupId = null;
    _showGroupForm = true;
    _groupNameController.clear();
    _groupColorController.text = '#2F6FED';
    _selectedWorkoutExerciseIds.clear();
  }

  void _startGroupEdit(ExerciseGroupRecord group) {
    _editingGroupId = group.id;
    _showGroupForm = true;
    _groupNameController.text = group.name;
    _groupColorController.text = group.colorHex;
    _selectedWorkoutExerciseIds
      ..clear()
      ..addAll(group.workoutExerciseIds);
  }

  void _clearGroupForm() {
    _editingGroupId = null;
    _showGroupForm = false;
    _groupNameController.clear();
    _groupColorController.text = '#2F6FED';
    _selectedWorkoutExerciseIds.clear();
  }

  void _setMemberSelected(String workoutExerciseId, bool selected) {
    setState(() {
      if (selected) {
        _selectedWorkoutExerciseIds.add(workoutExerciseId);
      } else {
        _selectedWorkoutExerciseIds.remove(workoutExerciseId);
      }
    });
  }

  Future<void> _saveGroup() async {
    final selectedIds = _selectedWorkoutExerciseIds.toList(growable: false);
    if (_groupNameController.text.trim().isEmpty || selectedIds.length < 2) {
      return;
    }

    final repository = ref.read(trainingRepositoriesProvider).exerciseGroups;
    final editingGroupId = _editingGroupId;
    if (editingGroupId == null) {
      await repository.create(
        ExerciseGroupDraft(
          workoutId: widget.workoutId,
          name: _groupNameController.text,
          colorHex: _groupColorController.text,
          workoutExerciseIds: selectedIds,
        ),
      );
    } else {
      await repository.update(
        editingGroupId,
        name: _groupNameController.text,
        colorHex: _groupColorController.text,
        workoutExerciseIds: selectedIds,
      );
    }

    if (mounted) {
      setState(_clearGroupForm);
    }
  }

  Future<void> _showExercisePicker() {
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
                  unawaited(
                    ref
                        .read(trainingRepositoriesProvider)
                        .workoutExercises
                        .create(
                          WorkoutExerciseDraft(
                            workoutId: widget.workoutId,
                            exerciseId: exercise.id,
                          ),
                        )
                        .then((workoutExerciseId) {
                      widget.onExerciseAdded(workoutExerciseId);
                      if (sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                      if (mounted) {
                        Navigator.of(context).pop();
                      }
                    }),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NavigationExerciseTile extends StatelessWidget {
  const _NavigationExerciseTile({
    required this.item,
    required this.isSelected,
    required this.onOverview,
    required this.onTap,
  });

  final _NavigationExerciseItem item;
  final bool isSelected;
  final VoidCallback onOverview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final group = item.group;
    final l10n = context.l10n;
    return ListTile(
      key: TrainingScreen.navigationItemKey(item.workoutExercise.id),
      selected: isSelected,
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: AppDimens.base,
        child: Center(
          child: Semantics(
            container: true,
            label: group == null
                ? l10n.trainingExerciseUngroupedIndicator
                : l10n.trainingGroupColorIndicator(group.name),
            child: Container(
              width: AppDimens.supersetBar,
              height: AppDimens.touchTarget,
              decoration: BoxDecoration(
                color: group == null
                    ? context.colors.divider
                    : colorFromHex(
                        group.colorHex,
                        fallback: context.colors.categoryColor('other'),
                      ),
                border: Border.all(color: context.colors.textSecondary),
                borderRadius: AppRadii.chipFull,
              ),
            ),
          ),
        ),
      ),
      title: Text(item.exercise.name),
      subtitle: group == null
          ? Text(l10n.trainingSetCount(item.setCount))
          : Text(
              '${l10n.trainingSetCount(item.setCount)} '
              '\u00B7 ${group.name}',
              semanticsLabel: '${l10n.trainingSetCount(item.setCount)}, '
                  '${l10n.trainingExerciseGroupIndicator(group.name)}',
            ),
      trailing: IconButton(
        key: TrainingScreen.overviewButtonKey(item.workoutExercise.id),
        tooltip: l10n.trainingOpenExerciseOverviewTooltip,
        onPressed: onOverview,
        icon: const Icon(Icons.insights_outlined),
      ),
      onTap: onTap,
    );
  }
}

class _ExerciseGroupTile extends StatelessWidget {
  const _ExerciseGroupTile({
    required this.group,
    required this.onEdit,
  });

  final ExerciseGroupRecord group;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Semantics(
        container: true,
        label: l10n.trainingGroupColorIndicator(group.name),
        child: Container(
          width: AppDimens.base,
          height: AppDimens.touchTarget,
          decoration: BoxDecoration(
            color: colorFromHex(
              group.colorHex,
              fallback: context.colors.categoryColor('other'),
            ),
            border: Border.all(color: context.colors.textSecondary),
            borderRadius: AppRadii.chipFull,
          ),
        ),
      ),
      title: Semantics(
        container: true,
        label: l10n.trainingExerciseGroupIndicator(group.name),
        child: Text(group.name),
      ),
      subtitle: Text(l10n.trainingGroupExerciseCount(group.members.length)),
      trailing: IconButton(
        key: TrainingScreen.editGroupButtonKey(group.id),
        tooltip: l10n.trainingEditGroupTooltip,
        onPressed: onEdit,
        icon: const Icon(Icons.edit_outlined),
      ),
    );
  }
}

class _ExerciseGroupForm extends StatelessWidget {
  const _ExerciseGroupForm({
    required this.items,
    required this.nameController,
    required this.colorController,
    required this.selectedWorkoutExerciseIds,
    required this.onMemberChanged,
    required this.onCancel,
    required this.onSave,
  });

  final List<_NavigationExerciseItem> items;
  final TextEditingController nameController;
  final TextEditingController colorController;
  final Set<String> selectedWorkoutExerciseIds;
  final void Function(String workoutExerciseId, bool selected) onMemberChanged;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: TrainingScreen.groupNameFieldKey,
          controller: nameController,
          decoration: InputDecoration(labelText: l10n.trainingGroupNameLabel),
        ),
        const SizedBox(height: AppDimens.base),
        TextField(
          key: TrainingScreen.groupColorFieldKey,
          controller: colorController,
          decoration: InputDecoration(labelText: l10n.trainingGroupColorLabel),
          textCapitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: AppDimens.base),
        for (final item in items)
          CheckboxListTile(
            key: TrainingScreen.groupMemberCheckboxKey(
              item.workoutExercise.id,
            ),
            contentPadding: EdgeInsets.zero,
            value: selectedWorkoutExerciseIds.contains(item.workoutExercise.id),
            title: Text(item.exercise.name),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (value) {
              onMemberChanged(item.workoutExercise.id, value ?? false);
            },
          ),
        const SizedBox(height: AppDimens.base),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppDimens.dense,
          runSpacing: AppDimens.dense,
          children: [
            TextButton(onPressed: onCancel, child: Text(l10n.trainingCancel)),
            FilledButton.icon(
              key: TrainingScreen.saveGroupButtonKey,
              onPressed: onSave,
              icon: const Icon(Icons.check),
              label: Text(l10n.trainingSaveGroup),
            ),
          ],
        ),
      ],
    );
  }
}

Stream<_NavigationPanelModel> _watchNavigationPanel(
  TrainingRepositories repositories,
  String workoutId,
) {
  late final StreamSubscription<List<WorkoutExerciseRecord>>
      workoutExerciseSubscription;
  StreamSubscription<List<ExerciseRecord>>? exerciseSubscription;
  late final StreamSubscription<List<LoggedSetRecord>> setSubscription;
  late final StreamSubscription<List<ExerciseGroupRecord>> groupSubscription;
  final controller = StreamController<_NavigationPanelModel>();
  List<WorkoutExerciseRecord>? latestWorkoutExercises;
  List<ExerciseRecord>? latestExercises;
  List<LoggedSetRecord>? latestSets;
  List<ExerciseGroupRecord>? latestGroups;
  var subscribedExerciseIds = const <String>{};
  var exerciseSubscriptionVersion = 0;
  List<Object?>? lastEmittedSignature;

  void addIfChanged(_NavigationPanelModel model) {
    final signature = _navigationPanelSignature(model);
    if (listEquals(signature, lastEmittedSignature)) {
      return;
    }
    lastEmittedSignature = signature;
    controller.add(model);
  }

  void emitIfReady() {
    final workoutExercises = latestWorkoutExercises;
    final exercises = latestExercises;
    final sets = latestSets;
    final groups = latestGroups;
    if (workoutExercises == null ||
        exercises == null ||
        sets == null ||
        groups == null) {
      return;
    }

    final exerciseById = <String, ExerciseRecord>{
      for (final exercise in exercises) exercise.id: exercise,
    };
    final setCountsByExerciseId = <String, int>{};
    for (final set in sets) {
      setCountsByExerciseId.update(
        set.exerciseId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final groupByWorkoutExerciseId = <String, ExerciseGroupRecord>{};
    for (final group in groups) {
      for (final member in group.members) {
        groupByWorkoutExerciseId[member.workoutExerciseId] = group;
      }
    }

    final items = <_NavigationExerciseItem>[];
    for (final workoutExercise in workoutExercises) {
      final exercise = exerciseById[workoutExercise.exerciseId];
      if (exercise == null) {
        continue;
      }

      items.add(
        _NavigationExerciseItem(
          workoutExercise: workoutExercise,
          exercise: exercise,
          setCount: setCountsByExerciseId[workoutExercise.exerciseId] ?? 0,
          group: groupByWorkoutExerciseId[workoutExercise.id],
        ),
      );
    }

    addIfChanged(
      _NavigationPanelModel(
        items: List<_NavigationExerciseItem>.unmodifiable(items),
        groups: groups,
      ),
    );
  }

  void subscribeToExercises(List<WorkoutExerciseRecord> workoutExercises) {
    final nextExerciseIds = workoutExercises
        .map((workoutExercise) => workoutExercise.exerciseId)
        .toSet();
    if (_sameStringSet(nextExerciseIds, subscribedExerciseIds) &&
        exerciseSubscription != null) {
      return;
    }

    subscribedExerciseIds = nextExerciseIds;
    latestExercises = null;
    final version = ++exerciseSubscriptionVersion;

    unawaited(exerciseSubscription?.cancel());
    exerciseSubscription =
        repositories.exercises.watchActiveByIds(nextExerciseIds).listen(
      (rows) {
        if (version != exerciseSubscriptionVersion) {
          return;
        }
        latestExercises = rows;
        emitIfReady();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (version == exerciseSubscriptionVersion) {
          controller.addError(error, stackTrace);
        }
      },
    );
  }

  controller.onListen = () {
    workoutExerciseSubscription =
        repositories.workoutExercises.watchActiveForWorkout(workoutId).listen(
      (rows) {
        latestWorkoutExercises = rows;
        subscribeToExercises(rows);
        emitIfReady();
      },
      onError: controller.addError,
    );
    setSubscription = repositories.sets.watchActiveForWorkout(workoutId).listen(
      (rows) {
        latestSets = rows;
        emitIfReady();
      },
      onError: controller.addError,
    );
    groupSubscription =
        repositories.exerciseGroups.watchActiveForWorkout(workoutId).listen(
      (rows) {
        latestGroups = rows;
        emitIfReady();
      },
      onError: controller.addError,
    );
  };
  controller.onCancel = () async {
    exerciseSubscriptionVersion++;
    await workoutExerciseSubscription.cancel();
    await exerciseSubscription?.cancel();
    await setSubscription.cancel();
    await groupSubscription.cancel();
  };

  return controller.stream;
}

List<Object?> _navigationPanelSignature(_NavigationPanelModel model) {
  return <Object?>[
    'items',
    model.items.length,
    for (final item in model.items) ...[
      item.workoutExercise.id,
      item.workoutExercise.exerciseId,
      item.workoutExercise.position,
      item.exercise.id,
      item.exercise.name,
      item.setCount,
      item.group?.id,
      item.group?.name,
      item.group?.colorHex,
      item.group?.position,
    ],
    'groups',
    model.groups.length,
    for (final group in model.groups) ...[
      group.id,
      group.name,
      group.colorHex,
      group.position,
      group.members.length,
      for (final member in group.members) ...[
        member.id,
        member.workoutExerciseId,
        member.position,
      ],
    ],
  ];
}

bool _sameStringSet(Set<String> left, Set<String> right) {
  return left.length == right.length && left.containsAll(right);
}

@visibleForTesting
Stream<List<String>> watchNavigationPanelExerciseNamesForTesting(
  TrainingRepositories repositories,
  String workoutId,
) {
  return _watchNavigationPanel(repositories, workoutId).map(
    (model) =>
        model.items.map((item) => item.exercise.name).toList(growable: false),
  );
}

class _NavigationPanelModel {
  const _NavigationPanelModel({
    required this.items,
    required this.groups,
  });

  final List<_NavigationExerciseItem> items;
  final List<ExerciseGroupRecord> groups;
}

class _NavigationExerciseItem {
  const _NavigationExerciseItem({
    required this.workoutExercise,
    required this.exercise,
    required this.setCount,
    required this.group,
  });

  final WorkoutExerciseRecord workoutExercise;
  final ExerciseRecord exercise;
  final int setCount;
  final ExerciseGroupRecord? group;
}

class _RestTimerPanel extends ConsumerStatefulWidget {
  const _RestTimerPanel({
    required this.workoutId,
    required this.workoutExerciseId,
    required this.enableTicker,
    required this.revision,
  });

  final String workoutId;
  final String workoutExerciseId;
  final bool enableTicker;
  final int revision;

  @override
  ConsumerState<_RestTimerPanel> createState() => _RestTimerPanelState();
}

class _RestTimerPanelState extends ConsumerState<_RestTimerPanel> {
  late final TextEditingController _durationController;
  Stream<RestTimerRecord?>? _timerStream;
  late Future<RestTimerRecord?> _timerFuture;
  Timer? _ticker;
  DateTime _now = DateTime.now().toUtc();
  String? _renderedTimerId;
  double _alertVolume = RestTimerRepository.defaultAlertVolume;
  final _alertsInFlight = <String>{};
  final _prepareAlertsInFlight = <String>{};

  /// The 3-2-1 prepare cue starts when the timer has <= 3s left.
  static const _prepareWindow = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _durationController = TextEditingController(
      text: RestTimerRepository.defaultDuration.inSeconds.toString(),
    );
    _timerFuture = _loadTimer(widget.workoutId);
    if (widget.enableTicker) {
      _timerStream = _watchTimer(widget.workoutId);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _now = DateTime.now().toUtc());
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _RestTimerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workoutId != widget.workoutId ||
        oldWidget.revision != widget.revision) {
      _timerStream = widget.enableTicker ? _watchTimer(widget.workoutId) : null;
      _timerFuture = _loadTimer(widget.workoutId);
      _renderedTimerId = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _durationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.enableTicker) {
      return StreamBuilder<RestTimerRecord?>(
        stream: _timerStream!,
        builder: (context, snapshot) => _buildPanel(context, snapshot.data),
      );
    }

    return FutureBuilder<RestTimerRecord?>(
      future: _timerFuture,
      builder: (context, snapshot) => _buildPanel(context, snapshot.data),
    );
  }

  Stream<RestTimerRecord?> _watchTimer(String workoutId) {
    return ref
        .read(trainingRepositoriesProvider)
        .restTimers
        .watchCurrentForWorkout(workoutId);
  }

  Future<RestTimerRecord?> _loadTimer(String workoutId) {
    return ref
        .read(trainingRepositoriesProvider)
        .restTimers
        .getCurrentForWorkout(workoutId);
  }

  Widget _buildPanel(BuildContext context, RestTimerRecord? timer) {
    final repository = ref.read(trainingRepositoriesProvider).restTimers;
    _syncControls(timer);
    if (timer != null &&
        timer.status == RestTimerStatus.running &&
        timer.alertFiredAt == null &&
        timer.isExpiredAt(_now)) {
      _queueAlert(timer);
    } else if (timer != null &&
        timer.status == RestTimerStatus.running &&
        timer.alertFiredAt == null &&
        timer.prepareAlertFiredAt == null &&
        _isWithinPrepareWindow(timer)) {
      _queuePrepareAlert(timer);
    }

    final remaining = timer?.remainingAt(_now) ?? Duration.zero;
    final isActive = timer != null &&
        timer.status == RestTimerStatus.running &&
        remaining > Duration.zero;
    final l10n = context.l10n;
    final title = timer == null
        ? l10n.trainingRestTimer
        : isActive
            ? l10n.trainingRestCountdown(_formatRestDuration(remaining))
            : l10n.trainingRestComplete;

    return DecoratedBox(
      key: TrainingScreen.restTimerPanelKey,
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.divider),
        borderRadius: AppRadii.cardMd,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.dense),
        child: Wrap(
          spacing: AppDimens.dense,
          runSpacing: AppDimens.dense,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 136,
              child: Text(
                title,
                style: context.textStyles.label,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 96,
              child: TextField(
                key: TrainingScreen.restTimerDurationFieldKey,
                controller: _durationController,
                decoration: InputDecoration(
                  labelText: l10n.trainingRestSecondsLabel,
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            FilledButton.icon(
              key: TrainingScreen.restTimerStartButtonKey,
              onPressed: () => unawaited(_startOrAdjustTimer()),
              icon: const Icon(Icons.timer_outlined),
              label: Text(
                timer == null
                    ? l10n.trainingStartTimer
                    : l10n.trainingUpdateTimer,
              ),
            ),
            if (timer != null)
              IconButton(
                key: TrainingScreen.restTimerCancelButtonKey,
                tooltip: l10n.trainingCancelTimerTooltip,
                onPressed: () => unawaited(_cancelTimer(timer.id)),
                icon: const Icon(Icons.close),
              ),
            SizedBox(
              width: 180,
              child: Row(
                children: [
                  const Icon(Icons.volume_up_outlined, size: 20),
                  Expanded(
                    child: Slider(
                      key: TrainingScreen.restTimerVolumeSliderKey,
                      value: _alertVolume,
                      onChanged: (value) {
                        setState(() => _alertVolume = value);
                        final currentTimer = timer;
                        if (currentTimer != null) {
                          unawaited(
                            repository
                                .updateAlertVolume(
                                  currentTimer.id,
                                  alertVolume: value,
                                )
                                .then((_) => _refreshTimer()),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _syncControls(RestTimerRecord? timer) {
    if (timer?.id == _renderedTimerId) {
      return;
    }

    _renderedTimerId = timer?.id;
    if (timer == null) {
      _durationController.text =
          RestTimerRepository.defaultDuration.inSeconds.toString();
      return;
    }

    _durationController.text = timer.duration.inSeconds.toString();
    _alertVolume = timer.alertVolume;
  }

  Future<void> _startOrAdjustTimer() async {
    final seconds = int.tryParse(_durationController.text.trim()) ??
        RestTimerRepository.defaultDuration.inSeconds;
    final duration = Duration(
      seconds: seconds <= 0
          ? RestTimerRepository.defaultDuration.inSeconds
          : seconds,
    );
    final repository = ref.read(trainingRepositoriesProvider).restTimers;
    final timerId = await repository.start(
      RestTimerDraft(
        workoutId: widget.workoutId,
        duration: duration,
        alertVolume: _alertVolume,
      ),
    );
    final timer = await repository.getById(timerId);
    if (timer != null) {
      final status = await _scheduleRestBackgroundTimer(
        ref,
        timer,
        workoutExerciseId: widget.workoutExerciseId,
        soundEnabled: _restTimerSoundsEnabled(),
      );
      if (mounted) {
        _notifyIfBackgroundAlertsDenied(context, status);
      }
    }
    _refreshTimer();
  }

  Future<void> _cancelTimer(String timerId) async {
    await ref.read(trainingRepositoriesProvider).restTimers.cancel(timerId);
    await ref.read(timerBackgroundSchedulerProvider).cancel(timerId);
    _refreshTimer();
  }

  void _refreshTimer() {
    if (!mounted || widget.enableTicker) {
      return;
    }
    setState(() {
      _timerFuture = _loadTimer(widget.workoutId);
      _renderedTimerId = null;
    });
  }

  void _queueAlert(RestTimerRecord timer) {
    if (!_alertsInFlight.add(timer.id)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_fireAlert(timer));
    });
  }

  Future<void> _fireAlert(RestTimerRecord timer) async {
    try {
      if (_restTimerSoundsEnabled()) {
        await ref.read(restTimerAlertProvider).fire(timer.alertVolume);
      }
    } finally {
      if (mounted) {
        await ref.read(trainingRepositoriesProvider).restTimers.markAlertFired(
              timer.id,
            );
        await ref.read(timerBackgroundSchedulerProvider).cancel(timer.id);
      }
      _alertsInFlight.remove(timer.id);
    }
  }

  bool _isWithinPrepareWindow(RestTimerRecord timer) {
    final remaining = timer.remainingAt(_now);
    return remaining > Duration.zero && remaining <= _prepareWindow;
  }

  void _queuePrepareAlert(RestTimerRecord timer) {
    if (!_prepareAlertsInFlight.add(timer.id)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_firePrepareAlert(timer));
    });
  }

  Future<void> _firePrepareAlert(RestTimerRecord timer) async {
    try {
      final restTimers = ref.read(trainingRepositoriesProvider).restTimers;
      final current = await restTimers.getById(timer.id);
      // Re-check under the current row: don't prepare-cue a timer that already
      // expired/fired its end cue, or already prepare-cued.
      if (current == null ||
          current.status != RestTimerStatus.running ||
          current.alertFiredAt != null ||
          current.prepareAlertFiredAt != null) {
        return;
      }
      if (_restTimerSoundsEnabled()) {
        await ref.read(restTimerAlertProvider).firePrepare(current.alertVolume);
      }
      await restTimers.markPrepareAlertFired(timer.id);
    } finally {
      _prepareAlertsInFlight.remove(timer.id);
    }
  }

  bool _restTimerSoundsEnabled() {
    return ref.read(settingsControllerProvider).value?.restTimerSoundsEnabled ??
        AppSettings.defaults.restTimerSoundsEnabled;
  }
}

class _TrainingForm extends StatelessWidget {
  const _TrainingForm({
    required this.state,
    required this.controllers,
    required this.commentController,
    required this.rpeController,
    required this.selectedSide,
    required this.sets,
    required this.recordSetIds,
    required this.settings,
    required this.onSave,
    required this.onStep,
    required this.onSideChanged,
    required this.onEdit,
    required this.onDelete,
    required this.onSetCompleted,
    required this.onReorder,
  });

  final _TrainingExerciseState state;
  final Map<DimensionId, TextEditingController> controllers;
  final TextEditingController commentController;
  final TextEditingController rpeController;
  final SetSide selectedSide;
  final Stream<List<LoggedSetRecord>> sets;
  final Set<String> recordSetIds;
  final AppSettings settings;
  final VoidCallback onSave;
  final void Function(DimensionId dimension, double delta) onStep;
  final ValueChanged<SetSide> onSideChanged;
  final ValueChanged<LoggedSetRecord> onEdit;
  final ValueChanged<LoggedSetRecord> onDelete;
  final void Function(LoggedSetRecord set, bool isCompleted) onSetCompleted;
  final ValueChanged<List<LoggedSetRecord>> onReorder;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final setEntryForm = _SetEntryForm(
      exercise: state.exercise,
      controllers: controllers,
      commentController: commentController,
      rpeController: rpeController,
      selectedSide: selectedSide,
      unitSystem: settings.unitSystem,
      defaultWeightIncrement: settings.defaultWeightIncrement,
      onSave: onSave,
      onStep: onStep,
      onSideChanged: onSideChanged,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final shouldScrollEntryForm =
            MediaQuery.textScalerOf(context).scale(1) > 1.2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: StreamBuilder<List<LoggedSetRecord>>(
                stream: sets,
                builder: (context, snapshot) {
                  final loggedSets = snapshot.data ?? const <LoggedSetRecord>[];
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      snapshot.data == null) {
                    return const SizedBox.expand();
                  }
                  if (loggedSets.isEmpty) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        l10n.homeNoSetsYet,
                        style: context.textStyles.body.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    );
                  }

                  return ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: loggedSets.length,
                    onReorderItem: (oldIndex, newIndex) {
                      if (newIndex == oldIndex) {
                        return;
                      }

                      final reordered = List<LoggedSetRecord>.of(loggedSets);
                      final moved = reordered.removeAt(oldIndex);
                      reordered.insert(newIndex, moved);
                      onReorder(reordered);
                    },
                    itemBuilder: (context, index) {
                      final set = loggedSets[index];
                      return _LoggedSetTile(
                        key: TrainingScreen.setTileKey(set.id),
                        set: set,
                        exercise: state.exercise,
                        index: index,
                        isRecord: recordSetIds.contains(set.id),
                        onEdit: () => onEdit(set),
                        onDelete: () => onDelete(set),
                        onCompletedChanged: (value) {
                          onSetCompleted(set, value ?? false);
                        },
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(),
            if (shouldScrollEntryForm)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.9,
                ),
                child: SingleChildScrollView(child: setEntryForm),
              )
            else
              setEntryForm,
          ],
        );
      },
    );
  }
}

class _LoggedSetTile extends StatelessWidget {
  const _LoggedSetTile({
    super.key,
    required this.set,
    required this.exercise,
    required this.index,
    required this.isRecord,
    required this.onEdit,
    required this.onDelete,
    required this.onCompletedChanged,
  });

  final LoggedSetRecord set;
  final ExerciseRecord exercise;
  final int index;
  final bool isRecord;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool?> onCompletedChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final completeLabel = set.isCompleted
        ? l10n.trainingMarkSetIncompleteLabel
        : l10n.trainingMarkSetCompleteLabel;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: set.isCompleted
            ? null
            : Semantics(
                container: true,
                label: completeLabel,
                checked: false,
                enabled: true,
                onTap: () {
                  onCompletedChanged(true);
                },
                child: ExcludeSemantics(
                  child: Checkbox(
                    key: TrainingScreen.completeSetCheckboxKey(set.id),
                    value: false,
                    onChanged: onCompletedChanged,
                  ),
                ),
              ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                _formatSet(l10n, set, exercise),
                style: context.textStyles.body,
              ),
            ),
            if (isRecord) ...[
              const SizedBox(width: AppDimens.dense),
              Tooltip(
                message: l10n.trainingPersonalRecordTooltip,
                child: Icon(
                  Icons.emoji_events_outlined,
                  key: TrainingScreen.recordTrophyKey(set.id),
                  color: context.colors.record,
                  size: 20,
                ),
              ),
            ],
          ],
        ),
        subtitle: _setSubtitle(context, l10n, set),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: TrainingScreen.editSetButtonKey(set.id),
              tooltip: l10n.trainingEditSetTooltip,
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              key: TrainingScreen.deleteSetButtonKey(set.id),
              tooltip: l10n.trainingDeleteSetTooltip,
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
            Semantics(
              container: true,
              button: true,
              label: l10n.trainingReorderSetLabel,
              child: ReorderableDragStartListener(
                key: TrainingScreen.reorderHandleKey(set.id),
                index: index,
                child: const SizedBox.square(
                  dimension: 48,
                  child: Center(child: Icon(Icons.drag_handle)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetEntryForm extends StatelessWidget {
  const _SetEntryForm({
    required this.exercise,
    required this.controllers,
    required this.commentController,
    required this.rpeController,
    required this.selectedSide,
    required this.unitSystem,
    required this.defaultWeightIncrement,
    required this.onSave,
    required this.onStep,
    required this.onSideChanged,
  });

  final ExerciseRecord exercise;
  final Map<DimensionId, TextEditingController> controllers;
  final TextEditingController commentController;
  final TextEditingController rpeController;
  final SetSide selectedSide;
  final UnitSystem unitSystem;
  final double defaultWeightIncrement;
  final VoidCallback onSave;
  final void Function(DimensionId dimension, double delta) onStep;
  final ValueChanged<SetSide> onSideChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final dimension in exercise.type.dimensions) ...[
          Builder(
            builder: (context) {
              final dimensionLabel = _dimensionLabel(l10n, dimension);
              final decreaseLabel = l10n.trainingDecreaseDimensionTooltip(
                dimensionLabel,
              );
              final increaseLabel = l10n.trainingIncreaseDimensionTooltip(
                dimensionLabel,
              );
              final controller = controllers.putIfAbsent(
                dimension,
                TextEditingController.new,
              );
              void decrement() {
                onStep(
                  dimension,
                  -_defaultIncrementFor(
                    dimension,
                    defaultWeightIncrement,
                  ),
                );
              }

              void increment() {
                onStep(
                  dimension,
                  _defaultIncrementFor(
                    dimension,
                    defaultWeightIncrement,
                  ),
                );
              }

              if (dimension == DimensionId.duration) {
                return _DurationDimensionInput(
                  groupKey: TrainingScreen.dimensionFieldKey(dimension),
                  hoursKey: TrainingScreen.durationHoursFieldKey,
                  minutesKey: TrainingScreen.durationMinutesFieldKey,
                  secondsKey: TrainingScreen.durationSecondsFieldKey,
                  decrementKey: TrainingScreen.decrementButtonKey(dimension),
                  incrementKey: TrainingScreen.incrementButtonKey(dimension),
                  controller: controller,
                  decreaseLabel: decreaseLabel,
                  increaseLabel: increaseLabel,
                  onDecrement: decrement,
                  onIncrement: increment,
                );
              }

              return _ScalarDimensionInput(
                fieldKey: TrainingScreen.dimensionFieldKey(dimension),
                decrementKey: TrainingScreen.decrementButtonKey(dimension),
                incrementKey: TrainingScreen.incrementButtonKey(dimension),
                controller: controller,
                label: dimensionLabel,
                unitLabel: _unitShortLabel(
                  l10n,
                  _defaultUnitFor(dimension, unitSystem),
                ),
                decreaseLabel: decreaseLabel,
                increaseLabel: increaseLabel,
                onDecrement: decrement,
                onIncrement: increment,
              );
            },
          ),
          const SizedBox(height: AppDimens.base),
        ],
        TextField(
          key: TrainingScreen.commentFieldKey,
          controller: commentController,
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: l10n.trainingCommentLabel),
        ),
        if (exercise.isUnilateral) ...[
          const SizedBox(height: AppDimens.base),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<SetSide>(
              key: TrainingScreen.sideFieldKey,
              selected: <SetSide>{selectedSide},
              segments: <ButtonSegment<SetSide>>[
                ButtonSegment<SetSide>(
                  value: SetSide.left,
                  label: Text(l10n.trainingSideLeft),
                  tooltip: l10n.trainingSideLeftTooltip,
                ),
                ButtonSegment<SetSide>(
                  value: SetSide.right,
                  label: Text(l10n.trainingSideRight),
                  tooltip: l10n.trainingSideRightTooltip,
                ),
              ],
              onSelectionChanged: (selection) {
                onSideChanged(selection.single);
              },
            ),
          ),
        ],
        if (exercise.usesRpe) ...[
          const SizedBox(height: AppDimens.base),
          TextField(
            key: TrainingScreen.rpeFieldKey,
            controller: rpeController,
            decoration: InputDecoration(labelText: l10n.trainingRpeLabel),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
          ),
        ],
        const SizedBox(height: AppDimens.base),
        FilledButton.icon(
          key: TrainingScreen.saveSetButtonKey,
          onPressed: onSave,
          icon: const Icon(Icons.check),
          label: Text(l10n.trainingSaveSet),
        ),
      ],
    );
  }
}

class _ScalarDimensionInput extends StatelessWidget {
  const _ScalarDimensionInput({
    required this.fieldKey,
    required this.decrementKey,
    required this.incrementKey,
    required this.controller,
    required this.label,
    required this.unitLabel,
    required this.decreaseLabel,
    required this.increaseLabel,
    required this.onDecrement,
    required this.onIncrement,
  });

  final Key fieldKey;
  final Key decrementKey;
  final Key incrementKey;
  final TextEditingController controller;
  final String label;
  final String unitLabel;
  final String decreaseLabel;
  final String increaseLabel;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _DimensionStepButton(
          key: decrementKey,
          label: decreaseLabel,
          icon: Icons.remove,
          onPressed: onDecrement,
        ),
        Expanded(
          child: TextField(
            key: fieldKey,
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              suffixText: unitLabel,
            ),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
          ),
        ),
        _DimensionStepButton(
          key: incrementKey,
          label: increaseLabel,
          icon: Icons.add,
          onPressed: onIncrement,
        ),
      ],
    );
  }
}

class _DurationDimensionInput extends StatelessWidget {
  const _DurationDimensionInput({
    required this.groupKey,
    required this.hoursKey,
    required this.minutesKey,
    required this.secondsKey,
    required this.decrementKey,
    required this.incrementKey,
    required this.controller,
    required this.decreaseLabel,
    required this.increaseLabel,
    required this.onDecrement,
    required this.onIncrement,
  });

  final Key groupKey;
  final Key hoursKey;
  final Key minutesKey;
  final Key secondsKey;
  final Key decrementKey;
  final Key incrementKey;
  final TextEditingController controller;
  final String decreaseLabel;
  final String increaseLabel;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _DimensionStepButton(
          key: decrementKey,
          label: decreaseLabel,
          icon: Icons.remove,
          onPressed: onDecrement,
        ),
        Expanded(
          child: _DurationPartsFields(
            key: groupKey,
            controller: controller,
            hoursKey: hoursKey,
            minutesKey: minutesKey,
            secondsKey: secondsKey,
          ),
        ),
        _DimensionStepButton(
          key: incrementKey,
          label: increaseLabel,
          icon: Icons.add,
          onPressed: onIncrement,
        ),
      ],
    );
  }
}

class _DimensionStepButton extends StatelessWidget {
  const _DimensionStepButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      ),
    );
  }
}

class _DurationPartsFields extends StatefulWidget {
  const _DurationPartsFields({
    super.key,
    required this.controller,
    required this.hoursKey,
    required this.minutesKey,
    required this.secondsKey,
  });

  final TextEditingController controller;
  final Key hoursKey;
  final Key minutesKey;
  final Key secondsKey;

  @override
  State<_DurationPartsFields> createState() => _DurationPartsFieldsState();
}

class _DurationPartsFieldsState extends State<_DurationPartsFields> {
  late final TextEditingController _hoursController;
  late final TextEditingController _minutesController;
  late final TextEditingController _secondsController;
  bool _updatingFromParts = false;
  bool _updatingFromCanonical = false;

  @override
  void initState() {
    super.initState();
    _hoursController = TextEditingController();
    _minutesController = TextEditingController();
    _secondsController = TextEditingController();
    widget.controller.addListener(_syncFromCanonical);
    _hoursController.addListener(_syncFromParts);
    _minutesController.addListener(_syncFromParts);
    _secondsController.addListener(_syncFromParts);
    _syncFromCanonical();
  }

  @override
  void didUpdateWidget(covariant _DurationPartsFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller.removeListener(_syncFromCanonical);
    widget.controller.addListener(_syncFromCanonical);
    _syncFromCanonical();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromCanonical);
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: _DurationPartTextField(
            key: widget.hoursKey,
            controller: _hoursController,
            label: l10n.trainingDurationHoursLabel,
            suffix: l10n.trainingUnitHour,
            textInputAction: TextInputAction.next,
          ),
        ),
        const SizedBox(width: AppDimens.dense),
        Expanded(
          child: _DurationPartTextField(
            key: widget.minutesKey,
            controller: _minutesController,
            label: l10n.trainingDurationMinutesLabel,
            suffix: l10n.trainingUnitMinute,
            textInputAction: TextInputAction.next,
          ),
        ),
        const SizedBox(width: AppDimens.dense),
        Expanded(
          child: _DurationPartTextField(
            key: widget.secondsKey,
            controller: _secondsController,
            label: l10n.trainingDurationSecondsLabel,
            suffix: l10n.trainingUnitSecond,
            textInputAction: TextInputAction.done,
          ),
        ),
      ],
    );
  }

  void _syncFromCanonical() {
    if (_updatingFromParts) {
      return;
    }
    final totalSeconds = _wholeSecondsFromCanonical(widget.controller.text);
    _updatingFromCanonical = true;
    if (totalSeconds == null) {
      _setText(_hoursController, '');
      _setText(_minutesController, '');
      _setText(_secondsController, '');
    } else {
      _setText(_hoursController, _durationPartText(totalSeconds ~/ 3600));
      _setText(
        _minutesController,
        _durationPartText((totalSeconds ~/ 60).remainder(60)),
      );
      final secondsText = totalSeconds == 0
          ? '0'
          : _durationPartText(totalSeconds.remainder(60));
      _setText(_secondsController, secondsText);
    }
    _updatingFromCanonical = false;
  }

  void _syncFromParts() {
    if (_updatingFromCanonical) {
      return;
    }
    final hoursText = _hoursController.text.trim();
    final minutesText = _minutesController.text.trim();
    final secondsText = _secondsController.text.trim();
    final allBlank =
        hoursText.isEmpty && minutesText.isEmpty && secondsText.isEmpty;
    final hours = _durationPartValue(hoursText);
    final minutes = _durationPartValue(minutesText);
    final seconds = _durationPartValue(secondsText);
    final nextText =
        allBlank || hours == null || minutes == null || seconds == null
            ? ''
            : ((hours * 3600) + (minutes * 60) + seconds).toString();

    if (widget.controller.text == nextText) {
      return;
    }
    _updatingFromParts = true;
    widget.controller.text = nextText;
    _updatingFromParts = false;
  }

  void _setText(TextEditingController controller, String text) {
    if (controller.text == text) {
      return;
    }
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _DurationPartTextField extends StatelessWidget {
  const _DurationPartTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.suffix,
    required this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
      ),
      keyboardType: TextInputType.number,
      textInputAction: textInputAction,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
      ],
    );
  }
}

class _EditSetSheet extends StatefulWidget {
  const _EditSetSheet({
    required this.set,
    required this.exercise,
    required this.unitSystem,
    required this.initialValues,
    required this.onSave,
  });

  final LoggedSetRecord set;
  final ExerciseRecord exercise;
  final UnitSystem unitSystem;
  final Map<DimensionId, String> initialValues;
  final Future<void> Function(_SetEditResult edit) onSave;

  @override
  State<_EditSetSheet> createState() => _EditSetSheetState();
}

class _EditSetSheetState extends State<_EditSetSheet> {
  late final Map<DimensionId, TextEditingController> _controllers;
  late final TextEditingController _commentController;
  late final TextEditingController _rpeController;
  late SetSide _selectedSide;

  @override
  void initState() {
    super.initState();
    _controllers = <DimensionId, TextEditingController>{
      for (final dimension in widget.exercise.type.dimensions)
        dimension: TextEditingController(
          text: widget.initialValues[dimension] ?? '',
        ),
    };
    _commentController = TextEditingController(text: widget.set.comment ?? '');
    _rpeController = TextEditingController(
      text: widget.set.rpe == null ? '' : _formatRpe(widget.set.rpe!),
    );
    _selectedSide = widget.set.side ?? SetSide.left;
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _commentController.dispose();
    _rpeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppDimens.base,
          right: AppDimens.base,
          top: AppDimens.base,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppDimens.base,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final dimension in widget.exercise.type.dimensions) ...[
                if (dimension == DimensionId.duration)
                  _DurationPartsFields(
                    key: TrainingScreen.editDimensionFieldKey(
                      widget.set.id,
                      dimension,
                    ),
                    controller: _controllers[dimension]!,
                    hoursKey: TrainingScreen.editDurationHoursFieldKey(
                      widget.set.id,
                    ),
                    minutesKey: TrainingScreen.editDurationMinutesFieldKey(
                      widget.set.id,
                    ),
                    secondsKey: TrainingScreen.editDurationSecondsFieldKey(
                      widget.set.id,
                    ),
                  )
                else
                  TextField(
                    key: TrainingScreen.editDimensionFieldKey(
                      widget.set.id,
                      dimension,
                    ),
                    controller: _controllers[dimension],
                    decoration: InputDecoration(
                      labelText: _dimensionLabel(l10n, dimension),
                      suffixText: _unitShortLabel(
                        l10n,
                        _defaultUnitFor(
                          dimension,
                          widget.unitSystem,
                        ),
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                const SizedBox(height: AppDimens.base),
              ],
              TextField(
                key: TrainingScreen.editCommentFieldKey(widget.set.id),
                controller: _commentController,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.done,
                decoration:
                    InputDecoration(labelText: l10n.trainingCommentLabel),
              ),
              if (widget.exercise.isUnilateral) ...[
                const SizedBox(height: AppDimens.base),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<SetSide>(
                    key: TrainingScreen.editSideFieldKey(widget.set.id),
                    selected: <SetSide>{_selectedSide},
                    segments: <ButtonSegment<SetSide>>[
                      ButtonSegment<SetSide>(
                        value: SetSide.left,
                        label: Text(l10n.trainingSideLeft),
                        tooltip: l10n.trainingSideLeftTooltip,
                      ),
                      ButtonSegment<SetSide>(
                        value: SetSide.right,
                        label: Text(l10n.trainingSideRight),
                        tooltip: l10n.trainingSideRightTooltip,
                      ),
                    ],
                    onSelectionChanged: (selection) {
                      setState(() => _selectedSide = selection.single);
                    },
                  ),
                ),
              ],
              if (widget.exercise.usesRpe) ...[
                const SizedBox(height: AppDimens.base),
                TextField(
                  key: TrainingScreen.editRpeFieldKey(widget.set.id),
                  controller: _rpeController,
                  decoration: InputDecoration(labelText: l10n.trainingRpeLabel),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],
              const SizedBox(height: AppDimens.base),
              FilledButton.icon(
                key: TrainingScreen.saveEditButtonKey(widget.set.id),
                onPressed: () {
                  final values = _valuesFromControllers(
                    controllers: _controllers,
                    exercise: widget.exercise,
                    unitSystem: widget.unitSystem,
                  );
                  if (values == null) {
                    return;
                  }

                  unawaited(
                    widget.onSave(
                      _SetEditResult(
                        values: values,
                        comment: _commentController.text,
                        side: _selectedSide,
                        rpe: _rpeFromController(_rpeController),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.save_outlined),
                label: Text(l10n.trainingSaveChanges),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrainingExerciseState {
  const _TrainingExerciseState({
    required this.workoutExercise,
    required this.exercise,
    required this.priorSet,
  });

  final WorkoutExerciseRecord workoutExercise;
  final ExerciseRecord exercise;
  final LoggedSetRecord? priorSet;
}

class _SetEditResult {
  const _SetEditResult({
    required this.values,
    required this.comment,
    required this.side,
    required this.rpe,
  });

  final LoggedSet values;
  final String? comment;
  final SetSide? side;
  final double? rpe;
}

Set<String> _headlineRecordSetIds(ExerciseAnalyticsResult? result) {
  if (result == null) {
    return const <String>{};
  }

  return result.headlineRecords.map((record) => record.setId).toSet();
}

LoggedSet? _valuesFromControllers({
  required Map<DimensionId, TextEditingController> controllers,
  required ExerciseRecord exercise,
  required UnitSystem unitSystem,
}) {
  final values = <SetDimensionValue>[];
  for (final dimension in exercise.type.dimensions) {
    final controller = controllers[dimension];
    final entered = controller?.text.trim() ?? '';
    if (entered.isEmpty) {
      continue;
    }
    values.add(
      SetDimensionValue(
        dimension: dimension,
        entered: entered,
        unit: _defaultUnitFor(dimension, unitSystem),
      ),
    );
  }

  if (values.isEmpty) {
    return exercise.type.isCompletionOnly ? LoggedSet.completion() : null;
  }

  try {
    return LoggedSet.fromValues(values);
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

String _formatSet(
  AppLocalizations l10n,
  LoggedSetRecord set,
  ExerciseRecord exercise,
) {
  final load = set.values.load;
  final reps = set.values.reps;
  if (load != null && reps != null) {
    return '${load.entered} ${_unitShortLabel(l10n, load.unit)} x '
        '${reps.entered}';
  }

  final segments = <String>[];
  for (final dimension in exercise.type.dimensions) {
    final value = set.values.valueFor(dimension);
    if (value != null) {
      segments.add(_formatDimensionValue(l10n, value));
    }
  }

  return segments.isEmpty ? l10n.trainingCompletedSet : segments.join(' - ');
}

String _formatDimensionValue(
  AppLocalizations l10n,
  SetDimensionValue value,
) {
  if (value.dimension == DimensionId.duration &&
      value.unit == TrainingUnit.second) {
    return _formatDurationValue(l10n, value);
  }
  return '${value.entered} ${_unitShortLabel(l10n, value.unit)}';
}

String _formatDurationValue(
  AppLocalizations l10n,
  SetDimensionValue value,
) {
  final totalSeconds = _wholeSecondsFromCanonical(value.entered);
  if (totalSeconds == null) {
    return '${value.entered} ${_unitShortLabel(l10n, value.unit)}';
  }
  return _formatClockDuration(totalSeconds);
}

Widget? _setSubtitle(
  BuildContext context,
  AppLocalizations l10n,
  LoggedSetRecord set,
) {
  final segments = <String>[];
  final side = set.side;
  if (side != null) {
    segments.add(_sideLabel(l10n, side));
  }
  final rpe = set.rpe;
  if (rpe != null) {
    segments.add(l10n.trainingSetRpe(_formatRpe(rpe)));
  }
  final comment = set.comment;
  if (comment != null && comment.isNotEmpty) {
    segments.add(comment);
  }
  if (segments.isEmpty) {
    return null;
  }
  return Text(
    segments.join(' - '),
    style: context.textStyles.caption.copyWith(
      color: context.colors.textSecondary,
    ),
  );
}

SetSide _nextSide(SetSide side) {
  return switch (side) {
    SetSide.left => SetSide.right,
    SetSide.right => SetSide.left,
  };
}

double _defaultIncrementFor(
  DimensionId dimension,
  double defaultWeightIncrement,
) {
  return switch (dimension) {
    DimensionId.load => defaultWeightIncrement,
    DimensionId.reps => 1,
    DimensionId.duration => 5,
    DimensionId.distance => 0.1,
  };
}

String _formatRpe(double value) {
  return _formatEnteredNumber(value);
}

String _formatRestDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _formatClockDuration(int totalSeconds) {
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds ~/ 60).remainder(60);
  final seconds = totalSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

int? _wholeSecondsFromCanonical(String entered) {
  final trimmed = entered.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final value = double.tryParse(trimmed);
  if (value == null ||
      !value.isFinite ||
      value < 0 ||
      value.truncateToDouble() != value) {
    return null;
  }
  return value.toInt();
}

String _durationPartText(int value) {
  return value == 0 ? '' : value.toString();
}

int? _durationPartValue(String text) {
  if (text.isEmpty) {
    return 0;
  }
  return int.tryParse(text);
}

double? _rpeFromController(TextEditingController controller) {
  final entered = controller.text.trim();
  if (entered.isEmpty) {
    return null;
  }

  final value = double.tryParse(entered);
  if (value == null ||
      value < 0 ||
      value > 10 ||
      (value * 2).roundToDouble() != value * 2) {
    return null;
  }
  return value;
}

String _sideLabel(AppLocalizations l10n, SetSide side) {
  return switch (side) {
    SetSide.left => l10n.trainingSideLeft,
    SetSide.right => l10n.trainingSideRight,
  };
}

String _formatEnteredNumber(num value) {
  final formatted = value.toStringAsFixed(3);
  return formatted
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

TrainingUnit _defaultUnitFor(DimensionId dimension, UnitSystem unitSystem) {
  return switch (dimension) {
    DimensionId.load => switch (unitSystem) {
        UnitSystem.metric => TrainingUnit.kilogram,
        UnitSystem.imperial => TrainingUnit.pound,
      },
    DimensionId.reps => TrainingUnit.repetition,
    DimensionId.duration => TrainingUnit.second,
    DimensionId.distance => switch (unitSystem) {
        UnitSystem.metric => TrainingUnit.kilometer,
        UnitSystem.imperial => TrainingUnit.mile,
      },
  };
}

String _dimensionLabel(AppLocalizations l10n, DimensionId dimension) {
  return switch (dimension) {
    DimensionId.load => l10n.trainingDimensionLoad,
    DimensionId.reps => l10n.trainingDimensionReps,
    DimensionId.duration => l10n.trainingDimensionDuration,
    DimensionId.distance => l10n.trainingDimensionDistance,
  };
}

String _unitShortLabel(AppLocalizations l10n, TrainingUnit unit) {
  return switch (unit) {
    TrainingUnit.kilogram => l10n.trainingUnitKilogram,
    TrainingUnit.pound => l10n.trainingUnitPound,
    TrainingUnit.repetition => l10n.trainingUnitRepetition,
    TrainingUnit.second => l10n.trainingUnitSecond,
    TrainingUnit.kilometer => l10n.trainingUnitKilometer,
    TrainingUnit.mile => l10n.trainingUnitMile,
  };
}
