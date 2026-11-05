import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/analytics/exercise_analytics.dart';
import '../../../domain/training/plan_logging.dart';
import '../../../domain/training/template_materialize.dart';
import '../../../domain/training/training_dimensions.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../analytics/repositories/exercise_analytics_repository.dart';
import '../../analytics/widgets/exercise_overview_screen.dart';
import '../../catalog/widgets/exercise_catalog_picker.dart';
import '../../settings/repositories/settings_repository.dart';
import '../services/timer_background_scheduler.dart';
import 'plan_progress_labels.dart';
import 'replace_exercise.dart';
import 'rest_strip.dart';
import 'training_confirmation.dart';

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

  /// Replaces the whole Workout's Sets stream (tests). The screen filters it
  /// to the open exercise for the rows and reads it whole for the superset
  /// walk, the round and the Next button.
  final Stream<List<LoggedSetRecord>>? setsStream;
  final Stream<Set<String>>? recordSetIdsStream;
  final bool enableRestTimerTicker;

  static const logSetButtonKey = Key('training.logSet');

  /// The Log set confirmation; the performance test finds it after one frame.
  static const saveSetConfirmationKey = Key('training.saveSet.confirmation');
  static const updateSetButtonKey = Key('training.updateSet');
  static const deleteSelectedSetButtonKey = Key('training.deleteSelectedSet');
  static const notDoneButtonKey = Key('training.notDone');
  static const addSetButtonKey = Key('training.addSet');
  static const addRoundButtonKey = Key('training.addRound');
  static const nextExerciseButtonKey = Key('training.nextExercise');
  static const restAfterValueKey = Key('training.restAfter.value');
  static const restAfterDecrementKey = Key('training.restAfter.decrement');
  static const restAfterIncrementKey = Key('training.restAfter.increment');
  static const contextLineKey = Key('training.contextLine');
  static const restStripKey = RestStrip.stripKey;
  static const restStripStopKey = RestStrip.stopKey;
  static const restStripStartKey = RestStrip.startKey;

  /// The alert volume slider, in the sheet the rest strip's time opens.
  static const restTimerVolumeSliderKey = RestStrip.volumeSliderKey;
  static const screenMenuButtonKey = Key('training.menu');
  static const replaceExerciseMenuItemKey = Key('training.menu.replace');
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

  static Key restStripAdjustKey(int seconds) {
    return RestStrip.adjustKey(seconds);
  }

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

  static Key reorderHandleKey(String setId) {
    return Key('training.set.$setId.reorder');
  }

  @override
  ConsumerState<TrainingScreen> createState() => _TrainingScreenState();
}

/// How far one tap on **Rest after**'s [−] or [+] moves the rest.
const _restAfterStep = Duration(seconds: 15);

/// The longest rest **Rest after** offers.
const _restAfterMax = Duration(minutes: 60);

class _TrainingScreenState extends ConsumerState<TrainingScreen> {
  late String _activeWorkoutExerciseId;

  /// The loaded exercise. It stays on screen while the next one loads, so
  /// the rest strip (and its ticker) stays mounted across a switch.
  _TrainingExerciseState? _state;
  bool _loadFailed = false;
  int _loadGeneration = 0;
  Stream<Set<String>>? _overrideRecordSetIdsStream;

  // The whole Workout, from the streams the Navigation Panel also reads.
  String? _subscribedWorkoutId;
  StreamSubscription<List<LoggedSetRecord>>? _setsSubscription;
  StreamSubscription<List<WorkoutExerciseRecord>>?
      _workoutExercisesSubscription;
  StreamSubscription<List<ExerciseGroupRecord>>? _groupsSubscription;
  StreamSubscription<List<ExerciseRecord>>? _exercisesSubscription;
  StreamSubscription<ReplaceUndone>? _replaceUndoneSubscription;
  Set<String> _subscribedExerciseIds = const <String>{};
  List<LoggedSetRecord>? _workoutSets;
  List<WorkoutExerciseRecord> _workoutExercises =
      const <WorkoutExerciseRecord>[];
  Map<String, WorkoutExerciseRecord> _workoutExercisesById =
      const <String, WorkoutExerciseRecord>{};
  Map<String, ExerciseGroupRecord> _groupByWorkoutExerciseId =
      const <String, ExerciseGroupRecord>{};
  Map<String, ExerciseRecord> _exercisesById = const <String, ExerciseRecord>{};

  /// The Workout's Sets by exercise, in plan order, without Planned Sets
  /// being swiped away; null until next read after the Sets or the swiped
  /// Sets change. Every build reads it once per group member (context line,
  /// Next, rounds), so it is bucketed once rather than rescanned per read.
  Map<String, List<LoggedSetRecord>>? _setsByExerciseIdCache;

  // The form's controls.
  final _controllers = <DimensionId, TextEditingController>{};
  final _commentController = TextEditingController();
  final _rpeController = TextEditingController();
  SetSide _selectedSide = SetSide.left;
  Duration _rest = defaultRestAfter;

  // Screen state (the spec's "Screen state").
  String? _pickedSetId;

  /// A Performed Set selected for Update; the form never reloads on its own
  /// while it is set.
  String? _selectedSetId;

  /// The unit of each dimension field, from the Set the form last loaded.
  /// A dimension missing here takes the unit setting, so a kg plan on an
  /// imperial setting still logs kg and a prefill keeps today's units.
  final _formUnits = <DimensionId, TrainingUnit>{};

  /// The rest shown at the last form load; **Rest after** is changed (and
  /// only then written and carried forward) when it differs from this.
  Duration _loadedRest = defaultRestAfter;

  /// Set by any change to any form control, cleared by a form load. A sync,
  /// an Agent or a carry-forward reloads the Current Set's values only
  /// while this is false, so a stepped but unsaved value survives them.
  bool _formDirty = false;
  bool _logInFlight = false;

  /// The Workout Exercise the form was last loaded for; a different one is
  /// a new visit (picked and selected rows clear).
  String? _formVisitId;
  _FormSource _formSource = const _FormSource(null, null, null);

  /// The Set Log set just wrote; the form loads the next Current Set once
  /// the Sets stream shows it performed.
  String? _pendingLoggedSetId;

  /// The values last logged on this exercise in this visit, which a form
  /// with no Current Set keeps instead of the prefill.
  LoggedSet? _lastLoggedValues;
  bool _loadingForm = false;

  /// Planned Sets swiped away whose delete the Sets stream does not show
  /// yet; hidden so `Dismissible` leaves the tree at once.
  final _removingSetIds = <String>{};
  int _restTimerRevision = 0;

  /// The rest strip's volume, which Log set's timer starts with.
  double _alertVolume = RestTimerRepository.defaultAlertVolume;

  /// The one message the rest strip shows, if any.
  TrainingConfirmation? _confirmation;

  /// Keys the strip's crossfade between messages.
  int _confirmationSequence = 0;
  Timer? _confirmationTimer;

  /// Runs when [_confirmationTimer] fires: the background alerts message,
  /// waiting for the confirmation with Undo to end. One slot; a later request
  /// replaces it. Dropped, not run, when the screen closes.
  VoidCallback? _afterUndoEnds;

  @override
  void initState() {
    super.initState();
    _activeWorkoutExerciseId = widget.workoutExerciseId;
    _overrideRecordSetIdsStream =
        widget.recordSetIdsStream?.asBroadcastStream();
    _trackFormChanges(_commentController);
    _trackFormChanges(_rpeController);
    // Undo of a Replace while its new Workout Exercise is open switches
    // back, so the screen never sits on a soft-deleted row; the Replace may
    // have started here or on the Workout screen.
    _replaceUndoneSubscription =
        ref.read(replaceUndoneProvider).stream.listen((undone) {
      if (mounted && _activeWorkoutExerciseId == undone.newWorkoutExerciseId) {
        _selectWorkoutExercise(undone.oldWorkoutExerciseId);
      }
    });
    _startLoad(
      _activeWorkoutExerciseId,
      useInitial: widget.initialWorkoutExercise != null &&
          widget.initialExercise != null,
    );
  }

  @override
  void didUpdateWidget(covariant TrainingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recordSetIdsStream != widget.recordSetIdsStream) {
      _overrideRecordSetIdsStream =
          widget.recordSetIdsStream?.asBroadcastStream();
    }
    if (oldWidget.workoutExerciseId != widget.workoutExerciseId) {
      _activeWorkoutExerciseId = widget.workoutExerciseId;
      _startLoad(_activeWorkoutExerciseId);
    } else if (oldWidget.setsStream != widget.setsStream) {
      final workoutId = _subscribedWorkoutId;
      if (workoutId != null) {
        _subscribeToSets(workoutId);
      }
    }
  }

  @override
  void dispose() {
    unawaited(_setsSubscription?.cancel());
    unawaited(_workoutExercisesSubscription?.cancel());
    unawaited(_groupsSubscription?.cancel());
    unawaited(_exercisesSubscription?.cancel());
    unawaited(_replaceUndoneSubscription?.cancel());
    _confirmationTimer?.cancel();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _commentController.dispose();
    _rpeController.dispose();
    super.dispose();
  }

  /// Marks the form dirty when [controller]'s text changes outside a form
  /// load. Text, not every notification: tapping a field selects its value,
  /// which notifies listeners without changing anything.
  void _trackFormChanges(TextEditingController controller) {
    var lastText = controller.text;
    controller.addListener(() {
      if (controller.text == lastText) {
        return;
      }
      lastText = controller.text;
      if (!_loadingForm) {
        _formDirty = true;
      }
    });
  }

  TextEditingController _dimensionController(DimensionId dimension) {
    return _controllers.putIfAbsent(dimension, () {
      final controller = TextEditingController();
      _trackFormChanges(controller);
      return controller;
    });
  }

  void _startLoad(String workoutExerciseId, {bool useInitial = false}) {
    final generation = ++_loadGeneration;
    _loadState(workoutExerciseId, useInitial: useInitial).then(
      (state) {
        if (!mounted || generation != _loadGeneration) {
          return;
        }
        setState(() {
          _state = state;
          _loadFailed = false;
          _subscribeToWorkout(state.workoutExercise.workoutId);
          _reconcileForm();
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || generation != _loadGeneration) {
          return;
        }
        setState(() => _loadFailed = true);
      },
    );
  }

  Future<_TrainingExerciseState> _loadState(
    String workoutExerciseId, {
    required bool useInitial,
  }) async {
    final repositories = ref.read(trainingRepositoriesProvider);
    final workoutExercise =
        (useInitial ? widget.initialWorkoutExercise : null) ??
            await repositories.workoutExercises.getById(workoutExerciseId);
    if (workoutExercise == null) {
      throw StateError('Workout exercise not found.');
    }

    final exercise = (useInitial ? widget.initialExercise : null) ??
        await repositories.exercises.getById(workoutExercise.exerciseId);
    if (exercise == null) {
      throw StateError('Exercise not found.');
    }

    final workout =
        await repositories.workoutSessions.getById(workoutExercise.workoutId);
    if (workout == null) {
      throw StateError('Workout not found.');
    }

    final priorSet = useInitial
        ? widget.initialPriorSet
        : await repositories.sets.findLatestPriorForExercise(
            exerciseId: workoutExercise.exerciseId,
            beforeWorkoutId: workoutExercise.workoutId,
            dimensions: exercise.type.dimensions,
          );
    // Read once per opening, with the prefill. Within this visit the
    // exercise's last Set carries any rest since (`restShownFor`): Log set
    // writes a changed rest onto its Set, and a new Set also writes the rest
    // it took from the Set before it (`_logSetInFlight`), so this value
    // never needs a refresh.
    final rememberedRest =
        await repositories.sets.findRememberedRest(exercise.id);

    return _TrainingExerciseState(
      workoutExercise: workoutExercise,
      exercise: exercise,
      priorSet: priorSet,
      workout: workout,
      rememberedRest: rememberedRest,
    );
  }

  void _subscribeToWorkout(String workoutId) {
    if (_subscribedWorkoutId == workoutId) {
      return;
    }
    _subscribedWorkoutId = workoutId;
    _workoutSets = null;
    _setsByExerciseIdCache = null;
    _workoutExercises = const <WorkoutExerciseRecord>[];
    _workoutExercisesById = const <String, WorkoutExerciseRecord>{};
    _groupByWorkoutExerciseId = const <String, ExerciseGroupRecord>{};
    _exercisesById = const <String, ExerciseRecord>{};
    _subscribedExerciseIds = const <String>{};
    _removingSetIds.clear();

    final repositories = ref.read(trainingRepositoriesProvider);
    _subscribeToSets(workoutId);
    unawaited(_workoutExercisesSubscription?.cancel());
    _workoutExercisesSubscription = repositories.workoutExercises
        .watchActiveForWorkout(workoutId)
        .listen((rows) {
      if (!mounted) {
        return;
      }
      setState(() {
        // Already in Workout order, the order the Navigation Panel shows.
        _workoutExercises = rows;
        _workoutExercisesById = <String, WorkoutExerciseRecord>{
          for (final row in rows) row.id: row,
        };
        _subscribeToExercises(rows);
      });
    });
    unawaited(_groupsSubscription?.cancel());
    _groupsSubscription =
        repositories.exerciseGroups.watchActiveForWorkout(workoutId).listen(
      (rows) {
        if (mounted) {
          setState(() {
            // A Workout Exercise is in at most one group; should two
            // claim it, the first in stream order wins.
            final byMemberId = <String, ExerciseGroupRecord>{};
            for (final group in rows) {
              for (final memberId in group.workoutExerciseIds) {
                byMemberId.putIfAbsent(memberId, () => group);
              }
            }
            _groupByWorkoutExerciseId = byMemberId;
          });
        }
      },
    );
  }

  void _subscribeToSets(String workoutId) {
    unawaited(_setsSubscription?.cancel());
    final stream = widget.setsStream ??
        ref.read(trainingRepositoriesProvider).sets.watchActiveForWorkout(
              workoutId,
            );
    _setsSubscription = stream.listen((rows) {
      if (!mounted) {
        return;
      }
      setState(() {
        _workoutSets = rows;
        _setsByExerciseIdCache = null;
        _removingSetIds.removeWhere(
          (id) => !rows.any((set) => set.id == id),
        );
        _reconcileForm();
      });
    });
  }

  /// The exercises of the Workout, for the names on the context line and
  /// the Next button and the dimensions Add round fills.
  void _subscribeToExercises(List<WorkoutExerciseRecord> workoutExercises) {
    final ids = workoutExercises.map((row) => row.exerciseId).toSet();
    if (_sameStringSet(ids, _subscribedExerciseIds) &&
        _exercisesSubscription != null) {
      return;
    }
    _subscribedExerciseIds = ids;
    unawaited(_exercisesSubscription?.cancel());
    _exercisesSubscription = ref
        .read(trainingRepositoriesProvider)
        .exercises
        .watchActiveByIds(ids)
        .listen(
      (rows) {
        if (mounted) {
          setState(() {
            _exercisesById = <String, ExerciseRecord>{
              for (final exercise in rows) exercise.id: exercise,
            };
          });
        }
      },
    );
  }

  /// The open exercise's Sets in plan order, without Planned Sets being
  /// swiped away.
  List<LoggedSetRecord> _exerciseSetsFor(_TrainingExerciseState state) {
    return _setsOfExercise(state.workoutExercise.exerciseId);
  }

  List<LoggedSetRecord> _setsOfExercise(String exerciseId) {
    return _setsByExerciseId[exerciseId] ?? const <LoggedSetRecord>[];
  }

  /// See [_setsByExerciseIdCache]. Sorted here, not trusted from the
  /// stream, because a test's `setsStream` need not come from the query.
  Map<String, List<LoggedSetRecord>> get _setsByExerciseId {
    final cached = _setsByExerciseIdCache;
    if (cached != null) {
      return cached;
    }
    final byExerciseId = <String, List<LoggedSetRecord>>{};
    for (final set in _workoutSets ?? const <LoggedSetRecord>[]) {
      if (set.workoutId == _subscribedWorkoutId &&
          set.deletedAt == null &&
          !_removingSetIds.contains(set.id)) {
        byExerciseId
            .putIfAbsent(set.exerciseId, () => <LoggedSetRecord>[])
            .add(set);
      }
    }
    return _setsByExerciseIdCache = <String, List<LoggedSetRecord>>{
      for (final entry in byExerciseId.entries)
        entry.key: List<LoggedSetRecord>.unmodifiable(
          entry.value..sort(compareSetsInPlanOrder),
        ),
    };
  }

  WorkoutExerciseRecord? _workoutExerciseById(String workoutExerciseId) {
    final state = _state;
    if (state != null && state.workoutExercise.id == workoutExerciseId) {
      return state.workoutExercise;
    }
    return _workoutExercisesById[workoutExerciseId];
  }

  List<LoggedSetRecord> _setsOfWorkoutExercise(String workoutExerciseId) {
    final workoutExercise = _workoutExerciseById(workoutExerciseId);
    if (workoutExercise == null) {
      return const <LoggedSetRecord>[];
    }
    return _setsOfExercise(workoutExercise.exerciseId);
  }

  ({int performed, int planned}) _countsFor(String workoutExerciseId) {
    final sets = _setsOfWorkoutExercise(workoutExerciseId);
    final planned = sets.where(isPlannedSet).length;
    return (performed: sets.length - planned, planned: planned);
  }

  String? _exerciseNameFor(String workoutExerciseId) {
    final state = _state;
    if (state != null && state.workoutExercise.id == workoutExerciseId) {
      return state.exercise.name;
    }
    final workoutExercise = _workoutExerciseById(workoutExerciseId);
    return workoutExercise == null
        ? null
        : _exercisesById[workoutExercise.exerciseId]?.name;
  }

  ExerciseGroupRecord? _groupFor(String workoutExerciseId) {
    return _groupByWorkoutExerciseId[workoutExerciseId];
  }

  /// Applies the spec's reload rules after the data or the screen state
  /// changed. Called inside `setState`.
  void _reconcileForm() {
    final state = _state;
    if (state == null || _workoutSets == null) {
      return;
    }
    final exerciseSets = _exerciseSetsFor(state);

    if (_formVisitId != state.workoutExercise.id) {
      _formVisitId = state.workoutExercise.id;
      _pickedSetId = null;
      _selectedSetId = null;
      _pendingLoggedSetId = null;
      _lastLoggedValues = null;
      _selectedSide = SetSide.left;
      _loadForm(state, currentSetFor(exerciseSets), exerciseSets);
      return;
    }

    final selectedSetId = _selectedSetId;
    if (selectedSetId != null) {
      if (exerciseSets
          .any((set) => set.id == selectedSetId && set.isCompleted)) {
        return;
      }
      // Un-completed, deleted or undone elsewhere: Update mode ends.
      _selectedSetId = null;
      _loadCurrentSet(state, exerciseSets);
      return;
    }

    final pendingLoggedSetId = _pendingLoggedSetId;
    if (pendingLoggedSetId != null) {
      final logged =
          exerciseSets.where((set) => set.id == pendingLoggedSetId).firstOrNull;
      if (logged != null && !logged.isCompleted) {
        // The stream has not shown the write yet.
        return;
      }
      _pendingLoggedSetId = null;
      _loadCurrentSet(state, exerciseSets);
      return;
    }

    final current = currentSetFor(exerciseSets, pickedSetId: _pickedSetId);
    if (current?.id != _formSource.setId ||
        (current != null && !_formDirty && _formSource.differsFrom(current))) {
      _loadForm(state, current, exerciseSets);
    }
  }

  void _loadCurrentSet(
    _TrainingExerciseState state,
    List<LoggedSetRecord> exerciseSets,
  ) {
    _loadForm(
      state,
      currentSetFor(exerciseSets, pickedSetId: _pickedSetId),
      exerciseSets,
    );
  }

  /// The spec's "form loads": [set] is the Current Set or the selected
  /// Performed Set; null is a new Set, which keeps the values last logged
  /// in this visit or else takes the prefill.
  void _loadForm(
    _TrainingExerciseState state,
    LoggedSetRecord? set,
    List<LoggedSetRecord> exerciseSets,
  ) {
    _loadingForm = true;
    try {
      final lastLoggedValues = _lastLoggedValues;
      final LoggedSet? values;
      final bool unitsFromValues;
      if (set != null) {
        values = set.values;
        unitsFromValues = true;
        _commentController.text = set.comment ?? '';
        final rpe = set.rpe;
        _rpeController.text = rpe == null ? '' : _formatRpe(rpe);
        // A Planned Set has no side; keeping the current one lets the side
        // alternate across a unilateral plan, as it does after Save set.
        final side = set.side;
        if (side != null) {
          _selectedSide = side;
        }
      } else {
        values = lastLoggedValues ?? state.priorSet?.values;
        // The prefill takes the unit setting, as before; the values last
        // logged keep the units they were logged in.
        unitsFromValues = lastLoggedValues != null;
        _commentController.clear();
        _rpeController.clear();
      }
      _formUnits.clear();
      for (final dimension in state.exercise.type.dimensions) {
        final value = values?.valueFor(dimension);
        _dimensionController(dimension).text = value?.entered ?? '';
        if (unitsFromValues && value != null) {
          _formUnits[dimension] = value.unit;
        }
      }
      _rest = restShownFor(
        shownSet: set,
        lastSetOfExercise: exerciseSets.lastOrNull,
        rememberedRest: state.rememberedRest,
      );
      _loadedRest = _rest;
      _formDirty = false;
      _formSource = _FormSource.of(set);
    } finally {
      _loadingForm = false;
    }
  }

  TrainingUnit _unitFor(DimensionId dimension, UnitSystem unitSystem) {
    return _formUnits[dimension] ?? _defaultUnitFor(dimension, unitSystem);
  }

  AppSettings _readSettings() {
    return ref.read(settingsControllerProvider).value ?? AppSettings.defaults;
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final ready = state != null && _workoutSets != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(state?.exercise.name ?? context.l10n.trainingFallbackTitle),
        actions: [
          PopupMenuButton<_TrainingScreenMenuAction>(
            key: TrainingScreen.screenMenuButtonKey,
            tooltip: context.l10n.trainingScreenMenuTooltip,
            enabled: state != null,
            onSelected: (action) {
              final exercise = _state?.exercise;
              if (exercise == null) {
                return;
              }
              switch (action) {
                case _TrainingScreenMenuAction.replaceExercise:
                  unawaited(_replaceOpenExercise());
                case _TrainingScreenMenuAction.exerciseOverview:
                  unawaited(
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ExerciseOverviewScreen(exerciseId: exercise.id),
                      ),
                    ),
                  );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<_TrainingScreenMenuAction>(
                key: TrainingScreen.replaceExerciseMenuItemKey,
                value: _TrainingScreenMenuAction.replaceExercise,
                child: Text(context.l10n.replaceExerciseMenuItem),
              ),
              PopupMenuItem<_TrainingScreenMenuAction>(
                value: _TrainingScreenMenuAction.exerciseOverview,
                child: Text(context.l10n.trainingExerciseOverviewMenuItem),
              ),
            ],
          ),
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
              isWorkoutOpen: state.workout.endedAt == null,
              onWorkoutExerciseSelected: _selectWorkoutExercise,
              onExerciseAdded: _selectWorkoutExercise,
            ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.base),
          child: _loadFailed
              ? Text(
                  context.l10n.trainingUnavailable,
                  style: context.textStyles.body.copyWith(
                    color: context.colors.textSecondary,
                  ),
                )
              : ready
                  ? _buildTrainingForm(state)
                  : const SizedBox.expand(),
        ),
      ),
    );
  }

  /// Replace exercise: the screen switches to the new Workout Exercise (and
  /// back on its Undo: see [initState]).
  Future<void> _replaceOpenExercise() async {
    final newId = await replaceExercise(
      context,
      ref,
      _activeWorkoutExerciseId,
      show: _showConfirmation,
    );
    if (newId != null && mounted) {
      _selectWorkoutExercise(newId);
    }
  }

  void _selectWorkoutExercise(String workoutExerciseId) {
    if (workoutExerciseId == _activeWorkoutExerciseId) {
      return;
    }

    setState(() => _activeWorkoutExerciseId = workoutExerciseId);
    _startLoad(workoutExerciseId);
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
    final l10n = context.l10n;
    final workoutExerciseId = state.workoutExercise.id;
    final confirmation = _confirmation;
    final exerciseSets = _exerciseSetsFor(state);
    final selectedSetId = _selectedSetId;
    final selectedSet = selectedSetId == null
        ? null
        : exerciseSets
            .where((set) => set.id == selectedSetId && set.isCompleted)
            .firstOrNull;
    final currentSet = currentSetFor(exerciseSets, pickedSetId: _pickedSetId);
    final group = _groupFor(workoutExerciseId);
    final contextLine = group == null
        ? null
        : _contextLineFor(
            l10n,
            group,
            workoutExerciseId: workoutExerciseId,
            loggedAPlannedSet: currentSet != null,
            autoSelectNextSet: settings.autoSelectNextSet,
          );
    final nextExerciseId = selectedSet == null
        ? _nextExerciseIdFor(workoutExerciseId, group)
        : null;
    final nextExerciseName =
        nextExerciseId == null ? null : _exerciseNameFor(nextExerciseId);

    final Widget actions;
    if (selectedSet != null) {
      actions = _UpdateModeButtons(
        onNotDone: () => unawaited(_markNotDone(state, selectedSet)),
        onUpdate: () => unawaited(_updateSelected(state, selectedSet)),
        onDelete: () => unawaited(_deleteSelected(state, selectedSet)),
      );
    } else {
      final currentNumber =
          currentSet == null ? null : exerciseSets.indexOf(currentSet) + 1;
      actions = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            key: TrainingScreen.logSetButtonKey,
            style: _saveButtonStyle(context),
            onPressed: () => unawaited(_logSet(state)),
            icon: const Icon(Icons.check),
            label: Text(
              currentNumber == null
                  ? l10n.trainingLogSet
                  : l10n.trainingLogSetOf(currentNumber, exerciseSets.length),
            ),
          ),
          if (nextExerciseId != null && nextExerciseName != null) ...[
            const SizedBox(height: AppDimens.dense),
            OutlinedButton(
              key: TrainingScreen.nextExerciseButtonKey,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(AppDimens.touchTarget),
              ),
              onPressed: () => _selectWorkoutExercise(nextExerciseId),
              child: Text(l10n.trainingNextExercise(nextExerciseName)),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (group != null && contextLine != null)
                  _ContextLine(
                    text: contextLine,
                    onAddRound: () => unawaited(_addRound(state, group)),
                  ),
                _SetRows(
                  exercise: state.exercise,
                  sets: exerciseSets,
                  currentSetId: currentSet?.id,
                  selectedSetId: selectedSet?.id,
                  recordSetIds: recordSetIds,
                  onTap: (set) => _onRowTapped(state, set),
                  onRemove: (set) => unawaited(_removePlannedSet(set)),
                  onReorder: (sets) => _reorderSets(state, sets),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: TrainingScreen.addSetButtonKey,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, AppDimens.touchTarget),
                    ),
                    onPressed: () => unawaited(_addSet(state)),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.trainingAddSet),
                  ),
                ),
                const Divider(),
                const SizedBox(height: AppDimens.dense),
                _SetEntryForm(
                  exercise: state.exercise,
                  controllerFor: _dimensionController,
                  commentController: _commentController,
                  rpeController: _rpeController,
                  selectedSide: _selectedSide,
                  unitFor: (dimension) =>
                      _unitFor(dimension, settings.unitSystem),
                  defaultWeightIncrement: settings.defaultWeightIncrement,
                  rest: _rest,
                  onStep: _stepDimension,
                  onStepRest: _stepRest,
                  onSideChanged: (side) {
                    setState(() {
                      _selectedSide = side;
                      _formDirty = true;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppDimens.dense),
        // Always at this place in the Column, whatever the buttons below
        // are, so the strip (the rest timer's one owner) stays mounted
        // across exercise switches and Update mode.
        RestStrip(
          workoutId: state.workoutExercise.workoutId,
          workoutExerciseId: workoutExerciseId,
          rest: _rest,
          enableTicker: widget.enableRestTimerTicker,
          revision: _restTimerRevision,
          onAlertVolumeChanged: (volume) => _alertVolume = volume,
          onConfirmation: _showConfirmation,
          undoShowing: _undoShowing,
          whenUndoEnds: _whenUndoEnds,
          confirmation: confirmation == null
              ? null
              : (confirmation: confirmation, sequence: _confirmationSequence),
        ),
        const SizedBox(height: AppDimens.dense),
        actions,
      ],
    );
  }

  /// The context line, or null when the group has no round (no member has
  /// a Set). "· Next:" is left out when Log set would not move.
  String? _contextLineFor(
    AppLocalizations l10n,
    ExerciseGroupRecord group, {
    required String workoutExerciseId,
    required bool loggedAPlannedSet,
    required bool autoSelectNextSet,
  }) {
    final memberIds = group.workoutExerciseIds;
    final counts = <String, ({int performed, int planned})>{
      for (final memberId in memberIds) memberId: _countsFor(memberId),
    };
    final round = groupRoundFor(counts.values.toList(growable: false));
    switch (round) {
      case null:
        return null;
      case GroupRoundAllDone():
        return l10n.trainingContextAllRoundsDone(group.name);
      case GroupRoundInProgress(:final round, :final of):
        final nextMemberId = nextGroupMemberAfterLog(
          memberIdsInOrder: memberIds,
          loggedWorkoutExerciseId: workoutExerciseId,
          membersWithPlannedSetBefore: <String>{
            for (final entry in counts.entries)
              if (entry.value.planned > 0) entry.key,
          },
          loggedAPlannedSet: loggedAPlannedSet,
          autoSelectNextSet: autoSelectNextSet,
        );
        final nextName =
            nextMemberId == null ? null : _exerciseNameFor(nextMemberId);
        return nextName == null
            ? l10n.trainingContextRound(group.name, round, of)
            : l10n.trainingContextRoundNext(group.name, round, of, nextName);
    }
  }

  /// The Next button's target: only when this exercise (and every member
  /// of its group) has no Planned Set.
  String? _nextExerciseIdFor(
    String workoutExerciseId,
    ExerciseGroupRecord? group,
  ) {
    final memberIds = group?.workoutExerciseIds ?? <String>[workoutExerciseId];
    if (memberIds.any((id) => _countsFor(id).planned > 0)) {
      return null;
    }
    return nextExerciseWithPlan(
      exercises: _progressExercises(),
      fromWorkoutExerciseId: workoutExerciseId,
    );
  }

  List<ProgressExercise> _progressExercises() {
    return <ProgressExercise>[
      for (final workoutExercise in _workoutExercises)
        _progressFor(workoutExercise.id),
    ];
  }

  ProgressExercise _progressFor(String workoutExerciseId) {
    return progressExerciseFor(
      workoutExerciseId: workoutExerciseId,
      groupId: _groupFor(workoutExerciseId)?.id,
      sets: _setsOfWorkoutExercise(workoutExerciseId).map(progressSetOf),
    );
  }

  void _onRowTapped(_TrainingExerciseState state, LoggedSetRecord set) {
    final exerciseSets = _exerciseSetsFor(state);
    setState(() {
      if (set.isCompleted) {
        if (_selectedSetId == set.id) {
          _selectedSetId = null;
          _loadCurrentSet(state, exerciseSets);
        } else {
          _selectedSetId = set.id;
          _loadForm(state, set, exerciseSets);
        }
        return;
      }
      _selectedSetId = null;
      _pickedSetId = set.id;
      _loadCurrentSet(state, exerciseSets);
    });
  }

  void _stepDimension(DimensionId dimension, double delta) {
    final controller = _dimensionController(dimension);
    final currentValue = double.tryParse(controller.text.trim()) ?? 0;
    final nextValue = (currentValue + delta).clamp(0, double.infinity);
    controller.text = _formatEnteredNumber(nextValue);
  }

  void _stepRest(int direction) {
    final seconds = (_rest + _restAfterStep * direction)
        .inSeconds
        .clamp(0, _restAfterMax.inSeconds);
    setState(() {
      _rest = Duration(seconds: seconds);
      _formDirty = true;
    });
  }

  LoggedSet? _valuesFromForm(ExerciseRecord exercise, UnitSystem unitSystem) {
    return _valuesFromControllers(
      controllers: _controllers,
      exercise: exercise,
      unitFor: (dimension) => _unitFor(dimension, unitSystem),
    );
  }

  /// Log set, step by step as the spec lists it: the confirmation shows
  /// before any await (within one frame), the write runs under its own
  /// batch so Undo reverses it, and the rest starts under another batch.
  ///
  /// `_logInFlight` stays set until the superset move (step 8), not just
  /// until the write returns: the Sets stream re-emits as soon as the write
  /// commits, so a second tap while the rest starts would otherwise log
  /// this member's next Set instead of being absorbed.
  Future<void> _logSet(_TrainingExerciseState state) async {
    if (_logInFlight ||
        _selectedSetId != null ||
        state.workoutExercise.id != _activeWorkoutExerciseId) {
      return;
    }
    final settings = _readSettings();
    final exercise = state.exercise;
    final values = _valuesFromForm(exercise, settings.unitSystem);
    if (values == null) {
      return;
    }

    _logInFlight = true;
    try {
      await _logSetInFlight(state, settings, values);
    } finally {
      _logInFlight = false;
    }
  }

  Future<void> _logSetInFlight(
    _TrainingExerciseState state,
    AppSettings settings,
    LoggedSet values,
  ) async {
    final exercise = state.exercise;
    final repositories = ref.read(trainingRepositoriesProvider);
    final scheduler = ref.read(timerBackgroundSchedulerProvider);
    final l10n = context.l10n;
    final batchId = repositories.uuidGenerator.generate();
    final exerciseSets = _exerciseSetsFor(state);
    final currentSet = currentSetFor(exerciseSets, pickedSetId: _pickedSetId);
    final number = currentSet == null
        ? exerciseSets.length + 1
        : exerciseSets.indexOf(currentSet) + 1;
    final memberIds = _groupFor(state.workoutExercise.id)?.workoutExerciseIds ??
        const <String>[];
    final membersWithPlannedSetBefore = <String>{
      for (final memberId in memberIds)
        if (_countsFor(memberId).planned > 0) memberId,
    };
    final rest = _rest;
    // A new Set also writes a rest it took unchanged from the exercise's
    // last Set in this Workout. Otherwise it stores null, and the Set after
    // it, whose rest comes from this one, falls back to the Remembered Rest
    // read when the exercise opened, losing a rest changed since (or a
    // plan's Off). A new Set is never Template divergence of rest: it
    // already diverges by count.
    final restChanged = rest != _loadedRest ||
        (currentSet == null &&
            exerciseSets.lastOrNull?.plannedRestAfter != null);

    _showConfirmation(
      TrainingConfirmation(
        message: l10n.trainingSetLogged(number),
        textKey: TrainingScreen.saveSetConfirmationKey,
      ),
    );

    final LogSetResult result;
    try {
      result = await repositories.sets.logSet(
        LogSetRequest(
          workoutId: state.workoutExercise.workoutId,
          exerciseId: state.workoutExercise.exerciseId,
          currentSetId: currentSet?.id,
          values: values,
          comment: _commentController.text,
          side: exercise.isUnilateral ? _selectedSide : null,
          rpe: exercise.usesRpe ? _rpeFromController(_rpeController) : null,
          restChanged: restChanged,
          rest: rest,
        ),
        batchId: batchId,
      );
    } catch (error) {
      _showConfirmation(
        TrainingConfirmation(
          message: l10n.trainingSetNotLogged(_errorReason(error)),
        ),
      );
      return;
    }
    if (result.alreadyLogged) {
      if (mounted) {
        setState(() => _confirmation = null);
      }
      return;
    }

    if (mounted) {
      setState(() {
        _pickedSetId = null;
        _pendingLoggedSetId = result.setId;
        _lastLoggedValues = values;
        _loadingForm = true;
        _commentController.clear();
        _rpeController.clear();
        _loadingForm = false;
        if (exercise.isUnilateral) {
          _selectedSide = _nextSide(_selectedSide);
        }
      });
      FocusManager.instance.primaryFocus?.unfocus();
    }

    final timerId = await _startRestAfterLog(
      repositories,
      scheduler,
      state,
      setId: result.setId,
      rest: rest,
      soundEnabled: settings.restTimerSoundsEnabled,
    );

    _showConfirmation(
      TrainingConfirmation(
        message: result.carriedCount > 0
            ? l10n.trainingSetLoggedCarried(number, result.carriedCount)
            : l10n.trainingSetLogged(number),
        textKey: TrainingScreen.saveSetConfirmationKey,
        undoLabel: l10n.trainingUndo,
        onUndo: () => unawaited(
          _undoLogSet(
            repositories,
            scheduler,
            _showConfirmation,
            l10n,
            batchId: batchId,
            timerId: timerId,
            workoutId: state.workoutExercise.workoutId,
          ),
        ),
        replacesCurrent: true,
      ),
    );

    final nextWorkoutExerciseId = nextGroupMemberAfterLog(
      memberIdsInOrder: memberIds,
      loggedWorkoutExerciseId: state.workoutExercise.id,
      membersWithPlannedSetBefore: membersWithPlannedSetBefore,
      loggedAPlannedSet: currentSet != null,
      autoSelectNextSet: settings.autoSelectNextSet,
    );
    if (nextWorkoutExerciseId != null && mounted) {
      _selectWorkoutExercise(nextWorkoutExerciseId);
    }
  }

  /// Starts the rest after a logged Set, unless the rest that runs is zero
  /// (Off, or a plan's zero) or the Workout has ended. The timer is written
  /// under its own batch, never the Log set's: the strip writes the timer
  /// row again later (prepare cue, end alert, Stop), which would make the
  /// Log set's batch impossible to undo.
  Future<String?> _startRestAfterLog(
    TrainingRepositories repositories,
    TimerBackgroundScheduler scheduler,
    _TrainingExerciseState state, {
    required String setId,
    required Duration rest,
    required bool soundEnabled,
  }) async {
    if (rest <= Duration.zero || state.workout.endedAt != null) {
      return null;
    }
    final loggedSet = await repositories.sets.getById(setId);
    if (loggedSet == null) {
      return null;
    }
    final timerId = await repositories.restTimers.startForSet(
      loggedSet,
      defaultDuration: rest,
      alertVolume: _alertVolume,
    );
    if (timerId == null) {
      return null;
    }
    final timer = await repositories.restTimers.getById(timerId);
    if (timer != null) {
      unawaited(
        scheduler
            .schedule(
          TimerBackgroundSchedule.rest(
            timer,
            workoutExerciseId: state.workoutExercise.id,
            soundEnabled: soundEnabled,
          ),
        )
            .then((status) {
          if (mounted) {
            notifyIfBackgroundAlertsDenied(
              status,
              message: context.l10n.trainingBackgroundAlertsDenied,
              show: _showConfirmation,
              undoShowing: _undoShowing,
              whenUndoEnds: _whenUndoEnds,
            );
          }
        }),
      );
    }
    _notifyRestTimerChanged();
    return timerId;
  }

  /// Undo of Log set: reverses the Set and its carry-forward, then cancels
  /// the rest it started if that is still the Workout's current timer.
  Future<void> _undoLogSet(
    TrainingRepositories repositories,
    TimerBackgroundScheduler scheduler,
    ShowTrainingConfirmation show,
    AppLocalizations l10n, {
    required String batchId,
    required String? timerId,
    required String workoutId,
  }) async {
    final undone = await _undoBatch(repositories, show, l10n, batchId);
    if (!undone || timerId == null) {
      return;
    }
    final current = await repositories.restTimers.getCurrentForWorkout(
      workoutId,
    );
    if (current?.id != timerId) {
      return;
    }
    await repositories.restTimers.cancel(timerId);
    await scheduler.cancel(timerId);
    _notifyRestTimerChanged();
  }

  /// See [undoTrainingBatch].
  Future<bool> _undoBatch(
    TrainingRepositories repositories,
    ShowTrainingConfirmation show,
    AppLocalizations l10n,
    String batchId,
  ) {
    return undoTrainingBatch(repositories, show, l10n, batchId);
  }

  Future<void> _updateSelected(
    _TrainingExerciseState state,
    LoggedSetRecord set,
  ) async {
    final exercise = state.exercise;
    final values = _valuesFromForm(exercise, _readSettings().unitSystem);
    if (values == null) {
      return;
    }
    final repositories = ref.read(trainingRepositoriesProvider);
    final l10n = context.l10n;
    try {
      await repositories.sets.updatePerformed(
        set.id,
        values: values,
        comment: _commentController.text,
        side: exercise.isUnilateral ? _selectedSide : null,
        rpe: exercise.usesRpe ? _rpeFromController(_rpeController) : null,
        restChanged: _rest != _loadedRest,
        rest: _rest,
        batchId: repositories.uuidGenerator.generate(),
      );
    } catch (error) {
      _showConfirmation(
        TrainingConfirmation(
          message: l10n.trainingSetNotUpdated(_errorReason(error)),
        ),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedSetId = null;
      _loadCurrentSet(state, _exerciseSetsFor(state));
    });
  }

  Future<void> _deleteSelected(
    _TrainingExerciseState state,
    LoggedSetRecord set,
  ) async {
    final repositories = ref.read(trainingRepositoriesProvider);
    final l10n = context.l10n;
    final batchId = repositories.uuidGenerator.generate();
    setState(() {
      _selectedSetId = null;
      _loadCurrentSet(state, _exerciseSetsFor(state));
    });
    await repositories.sets.softDelete(set.id, batchId: batchId);
    _showConfirmation(
      TrainingConfirmation(
        message: l10n.trainingSetDeleted,
        undoLabel: l10n.trainingUndo,
        onUndo: () => unawaited(
          _undoBatch(repositories, _showConfirmation, l10n, batchId),
        ),
      ),
    );
  }

  Future<void> _markNotDone(
    _TrainingExerciseState state,
    LoggedSetRecord set,
  ) async {
    // The Set becomes the picked Current Set; its values load now, so the
    // Sets stream showing it planned again changes nothing on the form.
    setState(() {
      _selectedSetId = null;
      _pickedSetId = set.id;
      _loadForm(state, set, _exerciseSetsFor(state));
    });
    await ref
        .read(trainingRepositoriesProvider)
        .sets
        .setCompleted(set.id, isCompleted: false);
  }

  Future<void> _removePlannedSet(LoggedSetRecord set) async {
    final repositories = ref.read(trainingRepositoriesProvider);
    final l10n = context.l10n;
    final batchId = repositories.uuidGenerator.generate();
    setState(() {
      _removingSetIds.add(set.id);
      _setsByExerciseIdCache = null;
      _reconcileForm();
    });
    await repositories.sets.softDelete(set.id, batchId: batchId);
    _showConfirmation(
      TrainingConfirmation(
        message: l10n.trainingPlannedSetRemoved,
        undoLabel: l10n.trainingUndo,
        onUndo: () => unawaited(
          _undoBatch(repositories, _showConfirmation, l10n, batchId)
              .then((undone) {
            if (undone && mounted) {
              setState(() {
                _removingSetIds.remove(set.id);
                _setsByExerciseIdCache = null;
              });
            }
          }),
        ),
      ),
    );
  }

  /// Add set: a Planned Set after the exercise's last Set, with its values
  /// and planned rest; with no Set yet, the form's values and, when changed,
  /// its rest.
  Future<void> _addSet(_TrainingExerciseState state) async {
    final exerciseSets = _exerciseSetsFor(state);
    final lastSet = exerciseSets.lastOrNull;
    final values = lastSet?.values ??
        _valuesFromForm(state.exercise, _readSettings().unitSystem);
    if (values == null) {
      return;
    }
    final plannedRestAfter = lastSet != null
        ? lastSet.plannedRestAfter
        : _rest != _loadedRest
            ? _rest
            : null;
    final workoutId = state.workoutExercise.workoutId;
    await ref.read(trainingRepositoriesProvider).sets.appendToWorkout(
      workoutId,
      <LoggedSetDraft>[
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: state.workoutExercise.exerciseId,
          position: 0,
          values: values,
          plannedRestAfter: plannedRestAfter,
        ),
      ],
    );
  }

  /// Add round: one Planned Set for every member of [group], under one
  /// batch id so one Undo removes the round. A member with Sets copies its
  /// last Set; one without takes its last performed values from before this
  /// Workout, or zeros, with no planned rest.
  Future<void> _addRound(
    _TrainingExerciseState state,
    ExerciseGroupRecord group,
  ) async {
    final repositories = ref.read(trainingRepositoriesProvider);
    final l10n = context.l10n;
    final batchId = repositories.uuidGenerator.generate();
    final workoutId = state.workoutExercise.workoutId;
    final drafts = <LoggedSetDraft>[];
    for (final memberId in group.workoutExerciseIds) {
      final workoutExercise = _workoutExerciseById(memberId);
      if (workoutExercise == null) {
        continue;
      }
      final lastSet = _setsOfWorkoutExercise(memberId).lastOrNull;
      if (lastSet != null) {
        drafts.add(
          LoggedSetDraft(
            workoutId: workoutId,
            exerciseId: workoutExercise.exerciseId,
            position: 0,
            values: lastSet.values,
            plannedRestAfter: lastSet.plannedRestAfter,
          ),
        );
        continue;
      }
      final exercise = workoutExercise.exerciseId == state.exercise.id
          ? state.exercise
          : _exercisesById[workoutExercise.exerciseId] ??
              await repositories.exercises.getById(workoutExercise.exerciseId);
      if (exercise == null) {
        continue;
      }
      final prior = await repositories.sets.findLatestPriorForExercise(
        exerciseId: exercise.id,
        beforeWorkoutId: workoutId,
        dimensions: exercise.type.dimensions,
      );
      drafts.add(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exercise.id,
          position: 0,
          values: prior?.values ??
              zeroLoggedSetFor(
                dimensions: exercise.type.dimensions,
                defaultLoadUnit: exercise.defaultLoadUnit,
              ),
        ),
      );
    }
    if (drafts.isEmpty) {
      return;
    }
    // One transaction, so the Sets stream shows the whole round at once.
    await repositories.sets.appendToWorkout(
      workoutId,
      drafts,
      batchId: batchId,
    );
    _showConfirmation(
      TrainingConfirmation(
        message: l10n.trainingRoundAdded,
        undoLabel: l10n.trainingUndo,
        onUndo: () => unawaited(
          _undoBatch(repositories, _showConfirmation, l10n, batchId),
        ),
      ),
    );
  }

  /// Puts [confirmation] on the rest strip's row, in place of whatever
  /// message it shows, until its duration ends. It can run after an await
  /// that outlives the screen, so it does nothing once unmounted.
  ///
  /// Tapping Undo clears the message but leaves the timer running: only a
  /// new message or [dispose] cancels it. The Undo wrapper is once-only: the
  /// outgoing child of the strip's crossfade keeps a live button for its
  /// 150 ms, so a second tap could otherwise reach the original again.
  void _showConfirmation(TrainingConfirmation confirmation) {
    if (!mounted) {
      return;
    }
    final onUndo = confirmation.onUndo;
    var undoTapped = false;
    setState(() {
      if (!confirmation.replacesCurrent) {
        _confirmationSequence += 1;
      }
      _confirmation = TrainingConfirmation(
        message: confirmation.message,
        textKey: confirmation.textKey,
        undoLabel: confirmation.undoLabel,
        replacesCurrent: confirmation.replacesCurrent,
        onUndo: onUndo == null
            ? null
            : () {
                if (undoTapped) {
                  return;
                }
                undoTapped = true;
                if (mounted) {
                  setState(() => _confirmation = null);
                }
                onUndo();
              },
      );
    });
    _confirmationTimer?.cancel();
    _confirmationTimer = Timer(confirmation.duration, () {
      if (mounted) {
        setState(() => _confirmation = null);
        final afterUndoEnds = _afterUndoEnds;
        _afterUndoEnds = null;
        afterUndoEnds?.call();
      }
    });
  }

  /// Whether a message would take Undo away from the lifter.
  ///
  /// `_logInFlight` counts because Log set's first message has no Undo yet: a
  /// schedule result that arrives then, such as Start rest's, would show the
  /// notice only for the Undo version to overwrite it at once, so the lifter
  /// would never see it. Log set restarts [_confirmationTimer], so the waiting
  /// message runs when Log set's message ends.
  bool _undoShowing() => _logInFlight || _confirmation?.onUndo != null;

  void _whenUndoEnds(VoidCallback callback) => _afterUndoEnds = callback;

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

enum _TrainingScreenMenuAction { replaceExercise, exerciseOverview }

/// What the form last loaded, for the reload rules: a different Current Set
/// always reloads, and changed stored values or rest reload a clean form.
class _FormSource {
  const _FormSource(this.setId, this.values, this.rest);

  _FormSource.of(LoggedSetRecord? set)
      : setId = set?.id,
        values = set?.values,
        rest = set?.plannedRestAfter;

  final String? setId;
  final LoggedSet? values;
  final Duration? rest;

  bool differsFrom(LoggedSetRecord set) {
    return set.values != values || set.plannedRestAfter != rest;
  }
}

/// The reason a hard reject or a failed write gives, for "Set not logged".
String _errorReason(Object error) {
  return switch (error) {
    SetValidationException(:final errors) when errors.isNotEmpty =>
      errors.map((issue) => issue.message).join(' '),
    StateError(:final message) => message,
    ArgumentError(:final message) when message != null => '$message',
    _ => '$error',
  };
}

ButtonStyle _saveButtonStyle(BuildContext context) {
  return FilledButton.styleFrom(
    backgroundColor: context.colors.save,
    foregroundColor: Theme.of(context).colorScheme.onSecondary,
    minimumSize: const Size.fromHeight(AppDimens.rowHeight),
  );
}

class _NavigationPanelDrawer extends ConsumerStatefulWidget {
  const _NavigationPanelDrawer({
    required this.workoutId,
    required this.activeWorkoutExerciseId,
    required this.isWorkoutOpen,
    required this.onWorkoutExerciseSelected,
    required this.onExerciseAdded,
  });

  final String workoutId;
  final String activeWorkoutExerciseId;

  /// Whether the Workout has not ended: only an open Workout marks Now.
  final bool isWorkoutOpen;
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
            final nowWorkoutExerciseId =
                widget.isWorkoutOpen ? model.nowWorkoutExerciseId : null;

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
                      isNow: item.workoutExercise.id == nowWorkoutExerciseId,
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
    required this.isNow,
    required this.onOverview,
    required this.onTap,
  });

  final _NavigationExerciseItem item;
  final bool isSelected;

  /// Whether this row is the Current Exercise, or its group's first row.
  final bool isNow;
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
      // The same count text as the exercise's Workout screen card.
      subtitle: Wrap(
        spacing: AppDimens.dense / 2,
        runSpacing: AppDimens.dense / 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (isNow) const CurrentExerciseLabel(),
          ExerciseProgressCount(
            performed: item.progress.performed,
            planned: item.progress.planned,
          ),
          if (group != null)
            Text(
              '\u00B7 ${group.name}',
              semanticsLabel: l10n.trainingExerciseGroupIndicator(group.name),
            ),
        ],
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
    final setsByExerciseId = <String, List<LoggedSetRecord>>{};
    for (final set in sets) {
      setsByExerciseId.putIfAbsent(set.exerciseId, () => []).add(set);
    }
    final groupByWorkoutExerciseId = <String, ExerciseGroupRecord>{};
    for (final group in groups) {
      for (final member in group.members) {
        groupByWorkoutExerciseId[member.workoutExerciseId] = group;
      }
    }

    // Every Workout Exercise counts toward Now, one whose Exercise is
    // archived included, though it gets no row: the Workout screen keeps
    // that exercise's card, and both must mark the same exercise.
    final progress = <ProgressExercise>[];
    final items = <_NavigationExerciseItem>[];
    for (final workoutExercise in workoutExercises) {
      final group = groupByWorkoutExerciseId[workoutExercise.id];
      final exerciseProgress = progressExerciseFor(
        workoutExerciseId: workoutExercise.id,
        groupId: group?.id,
        sets: (setsByExerciseId[workoutExercise.exerciseId] ??
                const <LoggedSetRecord>[])
            .map(progressSetOf),
      );
      progress.add(exerciseProgress);
      final exercise = exerciseById[workoutExercise.exerciseId];
      if (exercise == null) {
        continue;
      }

      items.add(
        _NavigationExerciseItem(
          workoutExercise: workoutExercise,
          exercise: exercise,
          progress: exerciseProgress,
          group: group,
        ),
      );
    }

    addIfChanged(
      _NavigationPanelModel(
        items: List<_NavigationExerciseItem>.unmodifiable(items),
        groups: groups,
        nowWorkoutExerciseId: nowCardWorkoutExerciseId(progress),
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
      item.progress.performed,
      item.progress.planned,
      item.group?.id,
      item.group?.name,
      item.group?.colorHex,
      item.group?.position,
    ],
    'now',
    model.nowWorkoutExerciseId,
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
    required this.nowWorkoutExerciseId,
  });

  final List<_NavigationExerciseItem> items;
  final List<ExerciseGroupRecord> groups;

  /// [nowCardWorkoutExerciseId] over every Workout Exercise, whether or not
  /// the Workout is open; the drawer shows it only on an open Workout.
  final String? nowWorkoutExerciseId;
}

class _NavigationExerciseItem {
  const _NavigationExerciseItem({
    required this.workoutExercise,
    required this.exercise,
    required this.progress,
    required this.group,
  });

  final WorkoutExerciseRecord workoutExercise;
  final ExerciseRecord exercise;

  /// The exercise's Performed and Planned Sets in this Workout.
  final ProgressExercise progress;
  final ExerciseGroupRecord? group;
}

/// "*group name* · Round *r* of *R* · Next: *member*", or "· All rounds
/// done", ending with **Add round**.
class _ContextLine extends StatelessWidget {
  const _ContextLine({required this.text, required this.onAddRound});

  final String text;
  final VoidCallback onAddRound;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.dense),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              key: TrainingScreen.contextLineKey,
              style: context.textStyles.label,
            ),
          ),
          TextButton(
            key: TrainingScreen.addRoundButtonKey,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, AppDimens.touchTarget),
            ),
            onPressed: onAddRound,
            child: Text(context.l10n.trainingAddRound),
          ),
        ],
      ),
    );
  }
}

/// The open exercise's Set rows in plan order. The list sits inside the
/// screen's one scroll view with the form, so it does not scroll itself.
class _SetRows extends StatelessWidget {
  const _SetRows({
    required this.exercise,
    required this.sets,
    required this.currentSetId,
    required this.selectedSetId,
    required this.recordSetIds,
    required this.onTap,
    required this.onRemove,
    required this.onReorder,
  });

  final ExerciseRecord exercise;
  final List<LoggedSetRecord> sets;
  final String? currentSetId;
  final String? selectedSetId;
  final Set<String> recordSetIds;
  final ValueChanged<LoggedSetRecord> onTap;
  final ValueChanged<LoggedSetRecord> onRemove;
  final ValueChanged<List<LoggedSetRecord>> onReorder;

  @override
  Widget build(BuildContext context) {
    if (sets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppDimens.dense),
        child: Text(
          context.l10n.homeNoSetsYet,
          style: context.textStyles.body.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: sets.length,
      onReorderItem: (oldIndex, newIndex) {
        if (newIndex == oldIndex) {
          return;
        }

        final reordered = List<LoggedSetRecord>.of(sets);
        final moved = reordered.removeAt(oldIndex);
        reordered.insert(newIndex, moved);
        onReorder(reordered);
      },
      itemBuilder: (context, index) {
        final set = sets[index];
        final rowState = set.isCompleted
            ? _SetRowState.performed
            : set.id == currentSetId
                ? _SetRowState.current
                : _SetRowState.planned;
        return _LoggedSetTile(
          key: TrainingScreen.setTileKey(set.id),
          set: set,
          exercise: exercise,
          index: index,
          rowState: rowState,
          // Only one row is highlighted: the selected Performed Set, or
          // else the Current Set.
          isHighlighted: selectedSetId == null
              ? rowState == _SetRowState.current
              : set.id == selectedSetId,
          isRecord: recordSetIds.contains(set.id),
          onTap: () => onTap(set),
          onRemove:
              rowState == _SetRowState.performed ? null : () => onRemove(set),
        );
      },
    );
  }
}

enum _SetRowState { performed, current, planned }

class _LoggedSetTile extends StatelessWidget {
  const _LoggedSetTile({
    super.key,
    required this.set,
    required this.exercise,
    required this.index,
    required this.rowState,
    required this.isHighlighted,
    required this.isRecord,
    required this.onTap,
    required this.onRemove,
  });

  final LoggedSetRecord set;
  final ExerciseRecord exercise;
  final int index;
  final _SetRowState rowState;
  final bool isHighlighted;
  final bool isRecord;
  final VoidCallback onTap;

  /// Removes a Planned Set (the swipe and its semantics action); null for a
  /// Performed Set, which is removed from Update mode instead.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final number = index + 1;
    final values = _formatSet(l10n, set, exercise);
    final semanticsLabel = switch (rowState) {
      _SetRowState.performed => l10n.trainingSetRowDoneLabel(number, values),
      _SetRowState.current => l10n.trainingSetRowNextLabel(number, values),
      _SetRowState.planned => l10n.trainingSetRowPlannedLabel(number, values),
    };
    final textStyle = rowState == _SetRowState.planned
        ? context.textStyles.body.copyWith(color: context.colors.textSecondary)
        : context.textStyles.body;
    Widget tile = Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        selected: isHighlighted,
        selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
        minLeadingWidth: 24,
        leading: SizedBox(
          width: 24,
          child: rowState == _SetRowState.current
              ? const Icon(Icons.arrow_right)
              : null,
        ),
        title: Row(
          children: [
            Expanded(
              child: Semantics(
                label: semanticsLabel,
                excludeSemantics: true,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: AppDimens.dense),
                      child: Text('$number', style: textStyle),
                    ),
                    Expanded(child: Text(values, style: textStyle)),
                  ],
                ),
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
            if (rowState == _SetRowState.performed)
              Icon(Icons.check, color: context.colors.textSecondary),
            Semantics(
              container: true,
              button: true,
              label: l10n.trainingReorderSetLabel,
              child: ReorderableDragStartListener(
                key: TrainingScreen.reorderHandleKey(set.id),
                index: index,
                child: const SizedBox.square(
                  dimension: AppDimens.touchTarget,
                  child: Center(child: Icon(Icons.drag_handle)),
                ),
              ),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );

    final remove = onRemove;
    if (remove != null) {
      final colorScheme = Theme.of(context).colorScheme;
      tile = Semantics(
        customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
          CustomSemanticsAction(label: l10n.trainingRemovePlannedSetAction):
              remove,
        },
        child: Dismissible(
          key: ValueKey<String>('training.set.${set.id}.dismiss'),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => remove(),
          background: ColoredBox(
            color: colorScheme.error,
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: AppDimens.base),
                child: Icon(Icons.delete_outline, color: colorScheme.onError),
              ),
            ),
          ),
          child: tile,
        ),
      );
    }
    return tile;
  }
}

/// Update mode's buttons: **Not done** above **Update** and **Delete**.
class _UpdateModeButtons extends StatelessWidget {
  const _UpdateModeButtons({
    required this.onNotDone,
    required this.onUpdate,
    required this.onDelete,
  });

  final VoidCallback onNotDone;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton(
          key: TrainingScreen.notDoneButtonKey,
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(AppDimens.touchTarget),
          ),
          onPressed: onNotDone,
          child: Text(l10n.trainingNotDone),
        ),
        const SizedBox(height: AppDimens.dense),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                key: TrainingScreen.updateSetButtonKey,
                style: _saveButtonStyle(context),
                onPressed: onUpdate,
                child: Text(l10n.trainingUpdateSet),
              ),
            ),
            const SizedBox(width: AppDimens.dense),
            Expanded(
              child: FilledButton(
                key: TrainingScreen.deleteSelectedSetButtonKey,
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                  minimumSize: const Size.fromHeight(AppDimens.rowHeight),
                ),
                onPressed: onDelete,
                child: Text(l10n.trainingDeleteSet),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// **Rest after**: [−] and [+] in 15 s steps, "m:ss", or "Off" at zero.
class _RestAfterInput extends StatelessWidget {
  const _RestAfterInput({required this.rest, required this.onStep});

  final Duration rest;

  /// Called with -1 or 1.
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: Text(l10n.trainingRestAfterLabel,
              style: context.textStyles.label),
        ),
        _DimensionStepButton(
          key: TrainingScreen.restAfterDecrementKey,
          label: l10n.trainingDecreaseRestTooltip,
          icon: Icons.remove,
          onPressed: () => onStep(-1),
        ),
        ConstrainedBox(
          constraints:
              const BoxConstraints(minWidth: AppDimens.touchTarget * 1.5),
          child: Text(
            rest <= Duration.zero
                ? l10n.trainingRestOff
                : formatRestDuration(rest),
            key: TrainingScreen.restAfterValueKey,
            textAlign: TextAlign.center,
            style: context.textStyles.numeralRow,
          ),
        ),
        _DimensionStepButton(
          key: TrainingScreen.restAfterIncrementKey,
          label: l10n.trainingIncreaseRestTooltip,
          icon: Icons.add,
          onPressed: () => onStep(1),
        ),
      ],
    );
  }
}

class _SetEntryForm extends StatelessWidget {
  const _SetEntryForm({
    required this.exercise,
    required this.controllerFor,
    required this.commentController,
    required this.rpeController,
    required this.selectedSide,
    required this.unitFor,
    required this.defaultWeightIncrement,
    required this.rest,
    required this.onStep,
    required this.onStepRest,
    required this.onSideChanged,
  });

  final ExerciseRecord exercise;
  final TextEditingController Function(DimensionId dimension) controllerFor;
  final TextEditingController commentController;
  final TextEditingController rpeController;
  final SetSide selectedSide;

  /// The unit each dimension field shows and logs (`formUnits`).
  final TrainingUnit Function(DimensionId dimension) unitFor;
  final double defaultWeightIncrement;
  final Duration rest;
  final void Function(DimensionId dimension, double delta) onStep;
  final ValueChanged<int> onStepRest;
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
              final controller = controllerFor(dimension);
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
                unitLabel: _unitShortLabel(l10n, unitFor(dimension)),
                decreaseLabel: decreaseLabel,
                increaseLabel: increaseLabel,
                onDecrement: decrement,
                onIncrement: increment,
              );
            },
          ),
          const SizedBox(height: AppDimens.base),
        ],
        _RestAfterInput(rest: rest, onStep: onStepRest),
        const SizedBox(height: AppDimens.base),
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
            onTap: () => _selectAllOnTap(rpeController),
            decoration: InputDecoration(labelText: l10n.trainingRpeLabel),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
          ),
        ],
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
            onTap: () => _selectAllOnTap(controller),
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

/// Selects a number field's whole value on tap, so typing replaces a
/// prefilled or placeholder value instead of appending to it: tapping "0"
/// and typing 26 must give 26, not "026", which a Set would keep as entered.
void _selectAllOnTap(TextEditingController controller) {
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: controller.text.length,
  );
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
      onTap: () => _selectAllOnTap(controller),
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

class _TrainingExerciseState {
  const _TrainingExerciseState({
    required this.workoutExercise,
    required this.exercise,
    required this.priorSet,
    required this.workout,
    required this.rememberedRest,
  });

  final WorkoutExerciseRecord workoutExercise;
  final ExerciseRecord exercise;
  final LoggedSetRecord? priorSet;

  /// The Workout, for `endedAt`: Log set starts no rest once it has ended.
  final WorkoutSessionRecord workout;

  /// The exercise's Remembered Rest (`findRememberedRest`), read with the
  /// prefill when the exercise opens.
  final Duration? rememberedRest;
}

Set<String> _headlineRecordSetIds(ExerciseAnalyticsResult? result) {
  if (result == null) {
    return const <String>{};
  }

  return result.headlineRecords.map((record) => record.setId).toSet();
}

/// The form's values in [unitFor]'s units (`formUnits`), or null when a
/// field does not parse.
LoggedSet? _valuesFromControllers({
  required Map<DimensionId, TextEditingController> controllers,
  required ExerciseRecord exercise,
  required TrainingUnit Function(DimensionId dimension) unitFor,
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
        unit: unitFor(dimension),
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
