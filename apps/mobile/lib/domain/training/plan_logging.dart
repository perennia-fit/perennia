/// Pure rules for logging a Workout against its plan: which Set the Track
/// form fills (the Current Set), which later Planned Sets take a logged
/// Set's new load, placeholder values or rest (carry-forward), where a
/// superset moves after Log set, the round a group is on, the rest the form
/// shows, and which Workout Exercise is Now (the Current Exercise).
///
/// Everything here is derived on read from the Workout's Sets and never
/// stored, as AGENTS.md requires of derived state; the screen and the
/// repository call these functions with rows they already hold. The rules
/// are app presentation logic with no TypeScript counterpart, so they have
/// Dart unit tests and no golden vectors. The design record is
/// `docs/designs/plan-guided-logging.md`.
library;

import 'training_dimensions.dart';
import 'training_records.dart';

/// The rest after a Set when neither the Set, the exercise's last Set nor
/// the Remembered Rest gives one. `RestTimerRepository.defaultDuration` is
/// this value, so the form and the timer agree.
const defaultRestAfter = Duration(seconds: 120);

/// The order of one Workout Exercise's Sets: `position`, then `id`.
///
/// Positions can tie (Materialize numbers each exercise from 0, and Agents
/// supply their own), so "later" in this file always means later in this
/// order, never a raw `position` comparison.
int compareSetsInPlanOrder(LoggedSetRecord a, LoggedSetRecord b) {
  final byPosition = a.position.compareTo(b.position);
  return byPosition != 0 ? byPosition : a.id.compareTo(b.id);
}

/// Whether [set] is a Planned Set: active and not complete. The caller
/// passes only Sets of Workouts that are not deleted.
bool isPlannedSet(LoggedSetRecord set) =>
    set.deletedAt == null && !set.isCompleted;

List<LoggedSetRecord> _inPlanOrder(Iterable<LoggedSetRecord> sets) {
  return sets.where((set) => set.deletedAt == null).toList()
    ..sort(compareSetsInPlanOrder);
}

/// The Planned Set the form fills, or null when no Set is planned.
///
/// [exerciseSets] are one Workout Exercise's Sets; they are put in plan
/// order here, so a caller's order cannot change the answer. A
/// [pickedSetId] that names a Planned Set wins; one that names a Performed
/// or missing Set falls back to the first Planned Set.
LoggedSetRecord? currentSetFor(
  List<LoggedSetRecord> exerciseSets, {
  String? pickedSetId,
}) {
  final planned = _inPlanOrder(exerciseSets).where(isPlannedSet).toList();
  if (planned.isEmpty) {
    return null;
  }
  if (pickedSetId != null) {
    for (final set in planned) {
      if (set.id == pickedSetId) {
        return set;
      }
    }
  }
  return planned.first;
}

/// One later Planned Set and what carry-forward writes on it.
final class CarryTarget {
  CarryTarget({
    required this.setId,
    required Iterable<SetDimensionValue> values,
    this.rest,
    required this.restChanged,
  }) : values = List<SetDimensionValue>.unmodifiable(values);

  final String setId;

  /// The dimensions to write, each replacing the target's value for that
  /// dimension; the target's other dimensions stay. Empty when only the rest
  /// carries.
  final List<SetDimensionValue> values;

  /// The new `plannedRestAfter`; meaningful only when [restChanged].
  final Duration? rest;

  /// Whether this target's `plannedRestAfter` is written.
  final bool restChanged;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CarryTarget &&
            other.setId == setId &&
            other.rest == rest &&
            other.restChanged == restChanged &&
            _sameValues(other.values, values);
  }

  @override
  int get hashCode =>
      Object.hash(setId, rest, restChanged, Object.hashAll(values));

  @override
  String toString() =>
      'CarryTarget($setId, values: ${values.map(_describe).join(', ')}, '
      'rest: $rest, restChanged: $restChanged)';
}

bool _sameValues(List<SetDimensionValue> a, List<SetDimensionValue> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

String _describe(SetDimensionValue value) =>
    '${value.dimension.name}=${value.entered} ${value.unit.name}';

/// The dimensions whose planned zero is a placeholder: reps, duration and
/// distance are outcomes of a Set, so a zero for them is never a real target.
/// Load is left out because 0 kg is a real load (nothing added).
const _placeholderDimensions = <DimensionId>[
  DimensionId.reps,
  DimensionId.duration,
  DimensionId.distance,
];

/// Whether [value]'s entered text is the number zero ("0", "0.0").
bool _isPlannedZero(SetDimensionValue? value) =>
    value != null && double.tryParse(value.entered) == 0;

/// The later Planned Sets that take a logged Set's new load or rest.
///
/// [logged] is the Set being logged as stored before the write, [newValues]
/// the form's values and [newRest] the form's rest. The rules:
///
/// *   **Load** carries only when the exercise records load and the new load
///     differs from [logged]'s stored load (`SetDimensionValue` equality, so
///     "60" and "60.0" differ); then every later Planned Set whose load
///     equals that stored load takes the new one. Carrying by the planned
///     value fixes a weight missing from the plan without lowering a plan
///     after a missed rep, and keeps a pyramid's shape.
/// *   **Placeholders.** For each of reps, duration and distance: only when
///     [logged]'s stored value is a planned zero and the new value differs;
///     then every later Planned Set whose value for it is a planned zero
///     takes the new value. A missed rep against a real target carries
///     nothing.
/// *   **Rest** carries only when [restChanged]; then every later Planned Set
///     whose `plannedRestAfter` equals [logged]'s (two nulls are equal) takes
///     [newRest].
///
/// A Set that would receive only values it already holds is not a target.
/// Comment, side and RPE never carry, and Sets before [logged] never change.
List<CarryTarget> carryForwardFor({
  required List<LoggedSetRecord> exerciseSets,
  required LoggedSetRecord logged,
  required LoggedSet newValues,
  required bool restChanged,
  required Duration? newRest,
}) {
  final ordered = _inPlanOrder(exerciseSets);
  final loggedIndex = ordered.indexWhere((set) => set.id == logged.id);
  final later = loggedIndex < 0
      ? <LoggedSetRecord>[
          for (final set in ordered)
            if (compareSetsInPlanOrder(set, logged) > 0) set,
        ]
      : ordered.sublist(loggedIndex + 1);

  final storedLoad = logged.values.load;
  final newLoad = newValues.load;
  final loadCarries =
      storedLoad != null && newLoad != null && newLoad != storedLoad;

  final placeholderCarries = <DimensionId, SetDimensionValue>{
    for (final dimension in _placeholderDimensions)
      if (_isPlannedZero(logged.values.valueFor(dimension)) &&
          newValues.valueFor(dimension) != null &&
          newValues.valueFor(dimension) != logged.values.valueFor(dimension))
        dimension: newValues.valueFor(dimension)!,
  };

  final targets = <CarryTarget>[];
  for (final set in later.where(isPlannedSet)) {
    final values = <SetDimensionValue>[];
    final load = set.values.load;
    if (loadCarries && load == storedLoad && load != newLoad) {
      values.add(newLoad);
    }
    for (final entry in placeholderCarries.entries) {
      final current = set.values.valueFor(entry.key);
      if (_isPlannedZero(current) && current != entry.value) {
        values.add(entry.value);
      }
    }
    final takesRest = restChanged &&
        set.plannedRestAfter == logged.plannedRestAfter &&
        set.plannedRestAfter != newRest;
    if (values.isEmpty && !takesRest) {
      continue;
    }
    targets.add(
      CarryTarget(
        setId: set.id,
        values: values,
        rest: takesRest ? newRest : null,
        restChanged: takesRest,
      ),
    );
  }
  return targets;
}

/// The member Log set moves to, or null to stay.
///
/// [memberIdsInOrder] are the Workout Exercise ids of the logged exercise's
/// Exercise Group in member order (empty when ungrouped), and
/// [membersWithPlannedSetBefore] those of them holding a Planned Set before
/// the write.
///
/// *   With [autoSelectNextSet] off, or fewer than two members: null. An
///     ungrouped exercise never moves on its own, so a Set can be added
///     after its plan.
/// *   **A planned superset** ([loggedAPlannedSet]): the first member after
///     the logged one, wrapping, other than the logged one, that still has a
///     Planned Set. This interleaves A1, B1, A2, B2; when only the logged
///     member has Sets left it keeps its turn (null, the screen stays).
/// *   **A freestyle superset, or a Set logged after the plan**: the next
///     member in order, wrapping.
String? nextGroupMemberAfterLog({
  required List<String> memberIdsInOrder,
  required String loggedWorkoutExerciseId,
  required Set<String> membersWithPlannedSetBefore,
  required bool loggedAPlannedSet,
  required bool autoSelectNextSet,
}) {
  if (!autoSelectNextSet || memberIdsInOrder.length < 2) {
    return null;
  }
  final loggedIndex = memberIdsInOrder.indexOf(loggedWorkoutExerciseId);
  if (loggedIndex < 0) {
    return null;
  }
  final count = memberIdsInOrder.length;
  if (!loggedAPlannedSet) {
    return memberIdsInOrder[(loggedIndex + 1) % count];
  }
  // The write completes one of the logged member's own Sets, so only the
  // other members are candidates, and their Planned Sets are unchanged by it.
  for (var step = 1; step < count; step += 1) {
    final candidate = memberIdsInOrder[(loggedIndex + step) % count];
    if (candidate != loggedWorkoutExerciseId &&
        membersWithPlannedSetBefore.contains(candidate)) {
      return candidate;
    }
  }
  return null;
}

/// The round an Exercise Group is on, derived from its members' Set counts.
sealed class GroupRound {
  const GroupRound();
}

/// Round [round] of [of] is under way.
final class GroupRoundInProgress extends GroupRound {
  const GroupRoundInProgress({required this.round, required this.of});

  final int round;
  final int of;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is GroupRoundInProgress && other.round == round && other.of == of;
  }

  @override
  int get hashCode => Object.hash(round, of);

  @override
  String toString() => 'GroupRoundInProgress($round of $of)';
}

/// Every member's Sets are performed.
final class GroupRoundAllDone extends GroupRound {
  const GroupRoundAllDone();

  @override
  bool operator ==(Object other) => other is GroupRoundAllDone;

  @override
  int get hashCode => (GroupRoundAllDone).hashCode;

  @override
  String toString() => 'GroupRoundAllDone()';
}

/// The group's round from each member's Performed and Planned Set counts;
/// null when no member has a Set.
///
/// Members with no Sets are left out. `of` is the most Sets any member has
/// and `round = of − (most Planned Sets any member has) + 1`: the member
/// with the most left to do sets the round. That reads right with unequal
/// counts, and after a member was replaced mid-superset (its replacement has
/// no Performed Set but as many Sets left as the others).
GroupRound? groupRoundFor(List<({int performed, int planned})> members) {
  final withSets =
      members.where((member) => member.performed + member.planned > 0).toList();
  if (withSets.isEmpty) {
    return null;
  }
  var of = 0;
  var mostPlanned = 0;
  for (final member in withSets) {
    final total = member.performed + member.planned;
    if (total > of) {
      of = total;
    }
    if (member.planned > mostPlanned) {
      mostPlanned = member.planned;
    }
  }
  if (mostPlanned == 0) {
    return const GroupRoundAllDone();
  }
  return GroupRoundInProgress(round: of - mostPlanned + 1, of: of);
}

/// The rest the form shows for [shownSet] (the Current Set, or the
/// performed Set selected for Update), or for a new Set when it is null.
///
/// A Set's own `plannedRestAfter` wins, then the Remembered Rest, then
/// [defaultRestAfter]. For a new Set, the exercise's last Set in this
/// Workout stands in for the Set. A planned zero (Off) is kept: it is the
/// plan's statement that no rest follows.
Duration restShownFor({
  required LoggedSetRecord? shownSet,
  required LoggedSetRecord? lastSetOfExercise,
  required Duration? rememberedRest,
}) {
  final source = shownSet ?? lastSetOfExercise;
  return source?.plannedRestAfter ?? rememberedRest ?? defaultRestAfter;
}

/// One Workout Exercise's progress, the input of [currentExerciseFor] and
/// [nextExerciseWithPlan].
final class ProgressExercise {
  const ProgressExercise({
    required this.workoutExerciseId,
    this.groupId,
    required this.performed,
    required this.planned,
    this.latestPerformedAt,
  });

  final String workoutExerciseId;

  /// The Exercise Group it is a member of, or null when ungrouped.
  final String? groupId;
  final int performed;
  final int planned;

  /// The latest `performedAt` over its Performed Sets.
  final DateTime? latestPerformedAt;
}

/// The Workout Exercise, or the Exercise Group, the user is working through.
sealed class CurrentExercise {
  const CurrentExercise();
}

final class CurrentWorkoutExercise extends CurrentExercise {
  const CurrentWorkoutExercise(this.workoutExerciseId);

  final String workoutExerciseId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CurrentWorkoutExercise &&
            other.workoutExerciseId == workoutExerciseId;
  }

  @override
  int get hashCode => workoutExerciseId.hashCode;

  @override
  String toString() => 'CurrentWorkoutExercise($workoutExerciseId)';
}

final class CurrentGroup extends CurrentExercise {
  const CurrentGroup(this.groupId);

  final String groupId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CurrentGroup && other.groupId == groupId;
  }

  @override
  int get hashCode => groupId.hashCode;

  @override
  String toString() => 'CurrentGroup($groupId)';
}

CurrentExercise _currentFor(ProgressExercise exercise) {
  final groupId = exercise.groupId;
  return groupId == null
      ? CurrentWorkoutExercise(exercise.workoutExerciseId)
      : CurrentGroup(groupId);
}

/// The Current Exercise, marked Now; [exercises] in Workout order.
///
/// 1.  The first exercise that is in progress: it, or its group across all
///     members, has both a Performed Set and a Planned Set.
/// 2.  Otherwise, [nextExerciseWithPlan] from the exercise with the latest
///     `latestPerformedAt` (the later in Workout order on a tie).
/// 3.  Otherwise, with no Performed Set at all, the first exercise with a
///     Planned Set.
/// 4.  Otherwise null.
///
/// The result is the exercise, or its group when it is grouped. Rule 1
/// keeps Now on a superset whose member was just replaced: the old
/// exercise, moved after the group, holds the latest Performed Set, but the
/// group is still in progress.
CurrentExercise? currentExerciseFor(List<ProgressExercise> exercises) {
  final performedByGroup = <String, int>{};
  final plannedByGroup = <String, int>{};
  for (final exercise in exercises) {
    final groupId = exercise.groupId;
    if (groupId == null) {
      continue;
    }
    performedByGroup[groupId] =
        (performedByGroup[groupId] ?? 0) + exercise.performed;
    plannedByGroup[groupId] = (plannedByGroup[groupId] ?? 0) + exercise.planned;
  }

  for (final exercise in exercises) {
    final groupId = exercise.groupId;
    final performed =
        groupId == null ? exercise.performed : performedByGroup[groupId]!;
    final planned =
        groupId == null ? exercise.planned : plannedByGroup[groupId]!;
    if (performed > 0 && planned > 0) {
      return _currentFor(exercise);
    }
  }

  ProgressExercise? latest;
  for (final exercise in exercises) {
    if (exercise.performed == 0) {
      continue;
    }
    if (latest == null || !_performedBefore(exercise, latest)) {
      latest = exercise;
    }
  }
  if (latest != null) {
    final nextId = nextExerciseWithPlan(
      exercises: exercises,
      fromWorkoutExerciseId: latest.workoutExerciseId,
    );
    if (nextId == null) {
      return null;
    }
    return _currentFor(
      exercises.firstWhere((exercise) => exercise.workoutExerciseId == nextId),
    );
  }

  for (final exercise in exercises) {
    if (exercise.planned > 0) {
      return _currentFor(exercise);
    }
  }
  return null;
}

/// Whether [exercise]'s latest Performed Set is strictly before
/// [latest]'s; a null time counts as earliest.
bool _performedBefore(ProgressExercise exercise, ProgressExercise latest) {
  final at = exercise.latestPerformedAt;
  final latestAt = latest.latestPerformedAt;
  if (at == null) {
    return latestAt != null;
  }
  return latestAt != null && at.isBefore(latestAt);
}

/// The Workout Exercise after [fromWorkoutExerciseId] (after its group when
/// grouped), in Workout order and wrapping, that has a Planned Set.
///
/// It never returns the start exercise or a member of its group, and is
/// null when no other exercise has a plan or the start is not in
/// [exercises]. The Next button uses it from the open exercise.
String? nextExerciseWithPlan({
  required List<ProgressExercise> exercises,
  required String fromWorkoutExerciseId,
}) {
  final fromIndex = exercises.indexWhere(
    (exercise) => exercise.workoutExerciseId == fromWorkoutExerciseId,
  );
  if (fromIndex < 0) {
    return null;
  }
  final fromGroupId = exercises[fromIndex].groupId;
  final count = exercises.length;
  for (var step = 1; step < count; step += 1) {
    final candidate = exercises[(fromIndex + step) % count];
    if (fromGroupId != null && candidate.groupId == fromGroupId) {
      continue;
    }
    if (candidate.planned > 0) {
      return candidate.workoutExerciseId;
    }
  }
  return null;
}
